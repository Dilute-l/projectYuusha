extends Control

## 主角的手 —— 跟着鼠标走的自定义光标（ARCHITECTURE.md §4）。
##
## 除了跟随鼠标，还支持切换「手」的贴图：主菜单里按下某些按钮会把手换成别的样式
## （例如 MenuInk 按钮 → 手变黑）。贴图放在本场景里，切换接口由本脚本对外提供。

## 默认（白色）的手
@export var hand_texture: Texture2D
## 备用的手（黑色）。MenuInk 按一下切到它
@export var hand_black_texture: Texture2D

@onready var _hand: Sprite2D = get_node_or_null("Hand")

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


func _ready() -> void:
	_live_count += 1
	# 隐藏系统光标，并限制在窗口内，避免手跑出窗口卡住
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)


func _exit_tree() -> void:
	_live_count = maxi(_live_count - 1, 0)
	if _live_count > 0:
		# 还有别的手在（通常就是刚挂上来的那个新场景）：别把系统光标放出来
		return
	# 手全没了：恢复光标，否则回到菜单会没有光标点不了按钮
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(_delta: float) -> void:
	if _hand != null:
		_hand.position = get_viewport().get_mouse_position()


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
