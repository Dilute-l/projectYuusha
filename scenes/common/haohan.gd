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


func _ready() -> void:
	# 隐藏系统光标，并限制在窗口内，避免手跑出窗口卡住
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)


func _exit_tree() -> void:
	# 手被移除时恢复光标，否则回到菜单会没有光标点不了按钮
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(_delta: float) -> void:
	if _hand != null:
		_hand.position = get_viewport().get_mouse_position()


## 换成本场景里记录的那只「黑色的手」
func use_black_hand() -> void:
	_set_texture(hand_black_texture)


## 换回默认（白色）的手
func use_default_hand() -> void:
	_set_texture(hand_texture)


## 直接指定任意贴图
func set_hand_texture(texture: Texture2D) -> void:
	_set_texture(texture)


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
