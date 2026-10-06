extends Control

var _exit_confirming := false

func _on_exitgame_pressed() -> void:
	if _exit_confirming:
		get_tree().quit()
		return
	_exit_confirming = true
	$Dialogue.visible = true
	$Dialogue/Dialogue.text = "再点一次退出游戏"
	$Dialogue/Name.text = "棍木"


func _on_startgame_pressed() -> void:
	pass # Replace with function body.

func _on_exitgame_mouse_exited() -> void:
	if not _exit_confirming:
		return
	_exit_confirming = false
	$Dialogue.visible = false
