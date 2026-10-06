extends Control

func _ready() -> void:
	# 隐藏系统光标，并限制在窗口内，避免手跑出窗口卡住
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

func _exit_tree() -> void:
	# 手被移除时恢复光标，否则回到菜单会没有光标点不了按钮
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta):
	$Hand.position = get_viewport().get_mouse_position()
