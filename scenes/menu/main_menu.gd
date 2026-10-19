extends Control

## 主菜单（ARCHITECTURE.md §4）：新游戏 / 继续游戏 / 退出。
## 只做显示与输入：开局走 GameState，跳转走 SceneRouter。

## 「继续游戏」按钮的节点名（置灰与接线都认它）
const CONTINUE_BUTTON: String = "ContinuegameText"

var _exit_confirming := false


func _ready() -> void:
	_refresh_continue_button()
	_refresh_title_button()


## 「继续游戏」有没有东西可读 —— 没有就置灰（ARCHITECTURE.md §15）。
##
## 每次进主菜单都会重刷（本场景是被 SceneRouter 重新实例化的），
## 所以「打完一局回到主菜单」时按钮上的灰是按当下磁盘上的存档算的。
func _refresh_continue_button() -> void:
	var button := get_node_or_null(CONTINUE_BUTTON) as Button
	if button == null:
		push_error("[MainMenu] 找不到「继续游戏」按钮：%s" % CONTINUE_BUTTON)
		return
	button.disabled = not SaveService.has_any_save()


## 「继续游戏」：读**最新**那一份存档接着玩，**不从头开始**。
##
## 读不出来（存档损坏 / 刚刚被删掉）时什么都不做，只把按钮重刷一遍：
## 这一下绝不能退化成「开一局新的」——玩家点的是继续，不是新游戏。
func _on_continuegame_pressed() -> void:
	if SceneRouter.is_transitioning:
		return
	_cancel_exit_confirm()
	if not SaveService.load_latest():
		_refresh_continue_button()
		return
	SceneRouter.goto_scene(&"day_loop")


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


## 退出按钮。
##
## 退出是破坏性操作，所以要点两次：第一下弹提醒对话，第二下才真的退出。
## 这段提醒用**穿透模式**（play(true)）：对话不会被左键吃掉，玩家仍然可以
## 正常操作界面 —— 包括「再点一下退出按钮」这一下，它会一边把对话推完、
## 一边照常触发按钮（同时也支持去点别的按钮，比如反悔点「新游戏」）。
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
	dialoguer.play(true)


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
	SceneRouter.goto_scene(&"credits_room")

##占位符按钮，按下来之后可以看到mcc花了个把小时都干了些什么
func _on_place_holder_button_pressed() -> void:
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[MainMenu] 找不到 Dialoguer")
		return
	if not dialoguer.typer.load_dialogue("WhatN1zHasDone"):
		return
	dialoguer.play()


## 标题按钮的音效（squeak）
const TITLE_SFX_PATH: String = "res://assets/sound/squeak.mp3"

## 标题按钮上的两句文案：
##   · 默认那句（和 main_menu.tscn 里写的一致）；
##   · 「正常走完十天」之后换成下面这句，暗示真结局入口已经不一样了。
## 换文案的开关是 EndingUnlock.is_normal_cleared()，能不能按是 is_unlocked() ——
## 两者**刻意分开**：只差「带过真结局角色」时，文案已经变了，但按钮还按不动。
const TITLE_TEXT_DEFAULT: String = "败犬勇者太多了！"
const TITLE_TEXT_HINT: String = "败犬面试官太多了！"

## 真结局场景的 key（SceneRouter 里登记）
const TRUE_ENDING_SCENE: StringName = &"true_ending"


## 标题按钮（Title）的解锁状态与文案。
##
## 每次进主菜单都会重刷（本场景是被 SceneRouter 重新实例化的），
## 所以「打完一局回到主菜单」看到的是**当下**账本里的状态（见 EndingUnlock）。
func _refresh_title_button() -> void:
	var title := get_node_or_null("Title") as Button
	if title == null:
		push_error("[MainMenu] 找不到标题按钮：Title")
		return
	# 文案跟「正常走完十天」这个 flag 走；能不能按要两个条件都达成
	title.text = TITLE_TEXT_HINT if EndingUnlock.is_normal_cleared() else TITLE_TEXT_DEFAULT
	title.disabled = not EndingUnlock.is_unlocked()


## Title 按钮：平时是音效按钮，真结局解锁后变成「真结局入口」。
##
## 没解锁时它是 disabled（正常点不到），这里再挡一层逻辑守卫 ——
## 别让「绕过 disabled 直接发信号」的路径（自检 / 焦点残留 / 键盘）把真结局提前放出来。
func _on_title_pressed() -> void:
	if not EndingUnlock.is_unlocked():
		return
	AudioService.play_sfx(TITLE_SFX_PATH)
	_release_button_focus()
	SceneRouter.goto_scene(TRUE_ENDING_SCENE)


## Title2 按钮（标题下面那行小字）：纯音效按钮，按下响一声 squeak，不做别的。
func _on_title2_pressed() -> void:
	AudioService.play_sfx(TITLE_SFX_PATH)
	_release_button_focus()


## 释放按钮焦点，免得之后按空格 / 回车又把上一次按的按钮触发一遍。
## 注意：Window 上叫 gui_release_focus()，没有 child_focus_exited() 这个方法。
func _release_button_focus() -> void:
	var win := get_window()
	if win != null:
		win.gui_release_focus()


## 火漆按钮（SealButton）现在兼任「重看开场」：
##   第一次按 → 只提示「再按一次观看开场剧情」；
##   第二次按 → 进开场场景（播 data/dialogue.json 的 opening，播完回主菜单）。
##
## 提示文案在 data/dialogue.json 的这个 id 里 —— 写手改字不用动代码。
const OPENING_HINT_ID: String = "seal_opening_hint"

## 开场剧情场景的 key（SceneRouter 的 SCENES 里登记）
const OPENING_SCENE: StringName = &"opening"

## 火漆按钮按过一次没有（「待触发」状态）。
## 每次进主菜单都从"没按过"重新算 —— 本场景是被 SceneRouter 重新实例化的。
var _seal_opening_armed: bool = false


## 火漆按钮：**两段式**，第一次只提示，第二次才真的播开场。
##
## 为什么要按两次：开场是一整段旁白，误触一下就切走不合适。
## 和「退出游戏」是同一套约定（那边第一下弹退出确认）。
##
## 提示用**穿透模式**（play(true)）：玩家第二下点同一个按钮时，
## 这一次点击既把提示推完、也照常落到按钮上 —— 不用先点空处把提示收掉。
func _on_seal_button_pressed() -> void:
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[MainMenu] 找不到 Dialoguer")
		return

	if not _seal_opening_armed:
		_seal_opening_armed = true
		if not dialoguer.typer.load_dialogue(OPENING_HINT_ID):
			# 文案缺失不该把玩家卡住：已经进入「待触发」状态了，再按一下就进开场
			push_warning("[MainMenu] 找不到提示对话「%s」，再按一次即播放开场" % OPENING_HINT_ID)
			return
		dialoguer.play(true)
		return

	# 第二次：真的进开场场景（opening 播完自己回主菜单）
	if SceneRouter.is_transitioning:
		return
	_seal_opening_armed = false
	SceneRouter.goto_scene(OPENING_SCENE)


func _on_ink_button_pressed() -> void:
	# 墨水按钮：把主角的手换成黑色的那只（贴图存在 haohan.tscn 里）。
	AudioService.play_sfx(TITLE_SFX_PATH)
	var win := get_window()
	if win != null:
		win.gui_release_focus()
	var haohan = get_node_or_null("Haohan")
	if haohan == null:
		push_error("[MainMenu] 找不到 Haohan")
		return
	haohan.use_black_hand()


func _on_book_button_pressed() -> void:
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[MainMenu] 找不到 Dialoguer")
		return
	if not dialoguer.typer.load_dialogue("Sorry"):
		return
	dialoguer.play()
