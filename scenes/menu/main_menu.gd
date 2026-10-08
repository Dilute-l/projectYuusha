extends Control

## 主菜单（ARCHITECTURE.md §4）：新游戏 / 退出。
## 只做显示与输入：开局走 GameState，跳转走 SceneRouter。

var _exit_confirming := false


func _on_typertest_pressed() -> void:
	# 点了退出确认后又点这个按钮时，先把退出确认收掉，避免两种文本叠在同一对话框里
	_cancel_exit_confirm()

	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[MainMenu] 找不到 Dialoguer")
		return
	# 取 data/dialogue.json 里 id 为 "second" 的那段测试对话。
	# 这里每次点击都重新读文件，改完 JSON 不用重启即可看到新文案。
	if not dialoguer.typer.load_dialogue("second"):
		return
	# 之后的推进与收起都由 Dialoguer 处理：左键点一下才进下一句，
	# 最后一句也要点一下才隐藏对话框（见 dialoguer.gd）。
	dialoguer.play()


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
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[MainMenu] 找不到 Dialoguer")
		return
	if not dialoguer.typer.load_dialogue("test1"):
		return
	dialoguer.play()


func _on_exitgame_mouse_exited() -> void:
	_cancel_exit_confirm()


func _on_mouse_exited() -> void:
	# 鼠标移出窗口也算放弃退出，免得切回来时误触第二次点击
	_cancel_exit_confirm()


func _cancel_exit_confirm() -> void:
	if not _exit_confirming:
		return
	_exit_confirming = false
	$Dialoguer.visible = false


func _on_credits_pressed() -> void:
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[MainMenu] 找不到 Dialoguer")
		return
	if not dialoguer.typer.load_dialogue("Sorry"):
		return
	dialoguer.play()

##占位符按钮，按下来之后可以看到mcc花了个把小时都干了些什么
func _on_place_holder_button_pressed() -> void:
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[MainMenu] 找不到 Dialoguer")
		return
	if not dialoguer.typer.load_dialogue("WhatN1zHasDone"):
		return
	dialoguer.play()


## Title 按钮的音效
const TITLE_SFX_PATH: String = "res://assets/sound/squeak.mp3"


func _on_title_pressed() -> void:
	# 这是个音效按钮：按下就响一声 squeak，不做别的。
	# 走 AudioService 的 SFX 池，找不到资源只会警告、不会崩。
	AudioService.play_sfx(TITLE_SFX_PATH)
	# 顺手释放按钮焦点，免得之后按空格/回车又把 squeak 触发一遍。
	# 注意：Window 上叫 gui_release_focus()，没有 child_focus_exited() 这个方法。
	var win := get_window()
	if win != null:
		win.gui_release_focus()
