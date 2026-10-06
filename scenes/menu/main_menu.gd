extends Control

## 主菜单（ARCHITECTURE.md §4）：新游戏 / 退出。
## 只做显示与输入：开局走 GameState，跳转走 SceneRouter。

var _exit_confirming := false


func _on_startgame_pressed() -> void:
	if SceneRouter.is_transitioning:
		return
	_cancel_exit_confirm()
	# 开新的一局：种子、天数、名单全部重置；后面十天的流程由 day_loop 负责
	GameState.start_new_run()
	SceneRouter.goto_scene(&"day_loop")


func _on_exitgame_pressed() -> void:
	if _exit_confirming:
		SceneRouter.quit_game()
		return
	_exit_confirming = true
	$Dialogue.visible = true
	$Dialogue/Dialogue.text = "再点一次退出游戏"
	$Dialogue/Name.text = "棍木"


func _on_exitgame_mouse_exited() -> void:
	_cancel_exit_confirm()


func _on_mouse_exited() -> void:
	# 鼠标移出窗口也算放弃退出，免得切回来时误触第二次点击
	_cancel_exit_confirm()


func _cancel_exit_confirm() -> void:
	if not _exit_confirming:
		return
	_exit_confirming = false
	$Dialogue.visible = false
