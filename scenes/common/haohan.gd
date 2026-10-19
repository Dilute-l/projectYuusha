extends Control

## 主角的手 —— 跟着鼠标走的自定义光标（ARCHITECTURE.md §4）。
##
## 除了跟随鼠标，还支持切换「手」的贴图：主菜单里按下某些按钮会把手换成别的样式
## （例如 MenuInk 按钮 → 手变黑）。贴图放在本场景里，切换接口由本脚本对外提供。
##
## 系统光标的处理分两种窗口模式（见 `_confines_cursor()` / `_apply_mouse_mode()`）：
## **全屏**时夹在窗口里，**窗口模式**时只藏不夹 —— 指针拖出游戏窗口是允许的。

## 默认（白色）的手
@export var hand_texture: Texture2D
## 备用的手（黑色）。MenuInk 按一下切到它
@export var hand_black_texture: Texture2D

@onready var _hand: Sprite2D = get_node_or_null("Hand")

## 落笔之前手上是哪个贴图。签名结束时**还原成它**，而不是直接还原成默认白手 ——
## 主菜单里 MenuInk 那类按钮本来就把手换黑了，签完字顺手抹回白色等于把人家踩掉。
var _texture_before_signing: Texture2D = null

## 当前在树上的 haohan 数量。
##
## 为什么要计数：切换阶段场景走的是 `queue_free()` + `add_child()`，而 queue_free 是
## **延迟**释放的 —— 本帧旧场景还挂在树上。于是时序变成：
##
##     新场景 _ready()   → 藏起系统光标（CONFINED_HIDDEN）
##     —— 帧末 ——
##     旧场景真正退场     → _exit_tree() → 又恢复成 VISIBLE
##
## 结果就是「一跳阶段，鼠标从隐藏+限制变回显示+不限制」。
## 有了计数：只要有任何一个 haohan 还活着就不恢复光标，**最后一个走了才恢复** ——
## 回菜单 / 结局那种需要真光标的场合（ending.tscn 里没有手）本来就该恢复。
static var _live_count: int = 0

## 上一次设下去的光标模式是不是「夹在窗口里」。用来判断要不要重设 ——
## 全屏 / 窗口模式在运行时被切换过（以后加全屏开关、或玩家自己按了 F11）就得补一次。
var _cursor_confined: bool = false


func _ready() -> void:
	_live_count += 1
	_apply_mouse_mode()
	# 签名期间换成蘸了墨的那只（§16）。走总线而不是让画布来找手：
	# 画布埋在 Popup → Dialoguer 底下，穿三层引用才能碰到手；而且每挂一次新场景
	# 都要重新接线。订阅之后换场景、加新场合都不用改一行（见 event_bus.gd 那一节）。
	if not EventBus.signature_signing_started.is_connected(_on_signing_started):
		EventBus.signature_signing_started.connect(_on_signing_started)
	if not EventBus.signature_signing_finished.is_connected(_on_signing_finished):
		EventBus.signature_signing_finished.connect(_on_signing_finished)


func _exit_tree() -> void:
	# 先摘信号再离开树（§5.5：queue_free() 之前先 disconnect）——
	# 手被释放之后信号还在，下一次签名就会打到一只已经没了的节点上。
	if EventBus.signature_signing_started.is_connected(_on_signing_started):
		EventBus.signature_signing_started.disconnect(_on_signing_started)
	if EventBus.signature_signing_finished.is_connected(_on_signing_finished):
		EventBus.signature_signing_finished.disconnect(_on_signing_finished)
	_live_count = maxi(_live_count - 1, 0)
	if _live_count > 0:
		# 还有别的手在（通常就是刚挂上来的那个新场景）：别把系统光标放出来
		return
	# 手全没了：恢复光标，否则回到菜单会没有光标点不了按钮
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## 玩家开始落笔 → 手蘸上墨
func _on_signing_started() -> void:
	if _hand == null:
		return
	_texture_before_signing = _hand.texture
	_set_texture(hand_black_texture)


## 这一笔结束（无论签成没有）→ 把手还回原样
func _on_signing_finished() -> void:
	if _hand == null:
		return
	if _texture_before_signing != null:
		_hand.texture = _texture_before_signing
	else:
		use_default_hand()
	_texture_before_signing = null


func _process(_delta: float) -> void:
	# 全屏 ↔ 窗口在运行时被切过就补一次（以后加全屏开关 / 玩家按 F11 都不用再改这里）
	if _confines_cursor() != _cursor_confined:
		_apply_mouse_mode()
	if _hand != null:
		_hand.position = _hand_position()


## 光标模式：**全屏**夹在窗口里，**窗口模式**只藏不夹（能拖出窗口）。
##
##   * 全屏（含独占全屏）：`CONFINED_HIDDEN` —— 全屏本来就没有「窗口外」，
##     夹住只是让手不会跑到屏幕边之外被系统吞掉；
##   * 窗口模式：`HIDDEN` —— 系统光标藏着，但仍能拖出游戏窗口
##     （去点别的窗口、拖到第二块屏幕都行）。
##
## ⚠️ 以前两种情况**一律** `CONFINED_HIDDEN`：窗口模式下指针被 `ClipCursor` 夹死在
##   窗口里，拖不出去 —— 那就是「一些场景里鼠标出不了窗口」的来源。现在只有全屏才夹。
static func _confines_cursor() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## 按当前窗口模式设置系统光标，并把「这一版夹没夹」记下来供 `_process()` 比较。
func _apply_mouse_mode() -> void:
	_cursor_confined = _confines_cursor()
	Input.set_mouse_mode(
			Input.MOUSE_MODE_CONFINED_HIDDEN if _cursor_confined else Input.MOUSE_MODE_HIDDEN)


## 手摆在哪儿：指针位置**夹进画布**。
##
## 窗口模式下指针能拖出窗口，`get_mouse_position()` 可能给出画布外的坐标
## （负数 / 超过宽高），不夹的话手就画到看不见的地方去了；夹住之后它停在贴边处。
## 全屏 + 夹光标时这一句其实是空操作，留着是为了两种模式走同一条路。
func _hand_position() -> Vector2:
	var rect := get_viewport_rect()
	return get_viewport().get_mouse_position().clamp(rect.position, rect.position + rect.size)


## 换成本场景里记录的那只「黑色的手」
func use_black_hand() -> void:
	$Hand.texture = hand_black_texture


## 换回默认（白色）的手
func use_default_hand() -> void:
	$Hand.texture = hand_texture


## 直接指定任意贴图
func set_hand_texture(texture: Texture2D) -> void:
	$Hand.texture = texture


## 当前手上用的贴图
func get_hand_texture() -> Texture2D:
	return _hand.texture if _hand != null else null


func _set_texture(texture: Texture2D) -> void:
	if _hand == null:
		push_warning("[Haohan] 找不到 Hand 节点，无法切换手的贴图")
		return
	if texture == null:
		push_warning("[Haohan] 要切换的手贴图是空的，已忽略")
		return
	_hand.texture = texture
