extends Node

## 开场剧情 的自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_opening.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 验的是「第一次启动播一次、之后不播；火漆按钮可以重看」这条链：
##
##   1. 数据：data/dialogue.json 里有 `opening` 和 `seal_opening_hint`；
##   2. 规则（OpeningFlow）：没看过 → 启动要播；mark_seen 之后不再播，且幂等；
##   3. boot 路由：没看过 → 请求 opening；看过 → 请求 main_menu；
##   4. 主菜单火漆按钮：第一次只弹提示、不切场景；第二次请求 opening；
##   5. opening 场景：播的就是 `opening` 那一段，播完自动回主菜单。
##
## ⚠️ 自检会临时写 user://saves/progress.json（boot 里的 mark_seen 会落盘）：
##    开头备份、结尾原样还原 —— 否则跑一次自检就等于替玩家把开场标记成"看过了"。

const MENU_SCENE := preload("res://scenes/menu/main_menu.tscn")
const BOOT_SCENE := preload("res://scenes/boot/boot.tscn")
const OPENING_SCENE := preload("res://scenes/opening/opening.tscn")

## 游戏的实际画布（project.godot 的 canvas_items 拉伸基准）
const GAME_CANVAS := Vector2i(1152, 648)

const DIALOGUE_PATH := "res://data/dialogue.json"
const HINT_TEXT := "再按一次观看开场剧情"

var _failures: Array[String] = []
var _checks: int = 0

## 自检开始前磁盘上那份跨局账本；null = 原本没有这个文件
var _progress_backup: Variant = null


func _ready() -> void:
	await get_tree().process_frame
	_backup_progress()
	await _run()
	_restore_progress()
	_report()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK  " if ok else "FAIL", what])


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## 读 data/dialogue.json 里某一段的行数组（读不出来返回空数组）
func _dialogue_rows(id: String) -> Array:
	var file := FileAccess.open(DIALOGUE_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and (parsed as Dictionary).get(id) is Array:
		return (parsed as Dictionary)[id]
	return []


## 把账本清成「什么都没解锁」，但**不落盘**（结尾统一还原）
func _clear_progress_in_memory() -> void:
	GameState.progress_flags.clear()
	GameState._progress_loaded = true


# ---------------------------------------------------------------------------
# 账本文件的备份 / 还原
# ---------------------------------------------------------------------------


func _backup_progress() -> void:
	if FileAccess.file_exists(GameConfig.PROGRESS_PATH):
		_progress_backup = FileAccess.get_file_as_string(GameConfig.PROGRESS_PATH)
	else:
		_progress_backup = null


func _restore_progress() -> void:
	GameState.progress_flags.clear()
	GameState._progress_loaded = true
	if _progress_backup == null:
		if FileAccess.file_exists(GameConfig.PROGRESS_PATH):
			DirAccess.remove_absolute(GameConfig.PROGRESS_PATH)
		return
	var file := FileAccess.open(GameConfig.PROGRESS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(String(_progress_backup))
		file.close()


# ---------------------------------------------------------------------------
# 自检主体
# ---------------------------------------------------------------------------


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = GAME_CANVAS
	vp.disable_3d = true
	get_tree().root.add_child(vp)
	await _settle()

	# 这里的场景切换全是**真的**（boot 会切走、火漆按钮会切走），而自检自己就在当前场景上。
	# 把过场拉到 30 秒：切换停在 fade 上（自检早退出了）；
	# 要看"请求去哪个场景"就监听 EventBus.scene_change_started（它在 fade **之前**发）。
	SceneRouter.set_fade_duration(30.0)
	var requests: Array[StringName] = []
	EventBus.scene_change_started.connect(
		func(key: StringName, _path: String) -> void: requests.append(key))

	# ---- 1. 数据：开场与提示的文案都在 ----
	var opening_rows := _dialogue_rows("opening")
	_check(not opening_rows.is_empty(), "data/dialogue.json 里有 opening 段（%d 行）" % opening_rows.size())
	var hint_rows := _dialogue_rows("seal_opening_hint")
	_check(not hint_rows.is_empty(), "data/dialogue.json 里有 seal_opening_hint 段")
	if not hint_rows.is_empty():
		var hint_text := ""
		for row in hint_rows:
			var line: Dictionary = row
			hint_text += String(line.get("text", ""))
		_check(hint_text.contains(HINT_TEXT), "提示文案是「%s」（实际「%s」）" % [HINT_TEXT, hint_text])

	# ---- 2. 规则：没看过 → 要播；记过 → 不再播 ----
	_clear_progress_in_memory()
	_check(OpeningFlow.should_play_on_launch(), "没看过开场 → 启动时要播")
	_check(not OpeningFlow.has_seen(), "初始状态是「没看过」")
	_check(OpeningFlow.mark_seen(), "mark_seen 返回「这次真的变了」")
	_check(OpeningFlow.has_seen(), "记过之后 has_seen 为真")
	_check(not OpeningFlow.should_play_on_launch(), "记过之后启动不再播")
	_check(not OpeningFlow.mark_seen(), "再记一次是幂等的（返回 false）")

	# ---- 3. boot 路由：没看过 → opening；看过 → main_menu ----
	_clear_progress_in_memory()
	SceneRouter.is_transitioning = false
	requests.clear()
	var boot1 := BOOT_SCENE.instantiate()
	vp.add_child(boot1)
	await _settle()
	_check(requests.has(&"opening"), "第一次启动 → 请求切到 opening（实际 %s）" % str(requests))
	_check(OpeningFlow.has_seen(), "切走之前就把「看过了」记下来了（中途退出也不会重播）")
	if is_instance_valid(boot1) and boot1.is_inside_tree():
		boot1.queue_free()
	await _settle()

	SceneRouter.is_transitioning = false
	requests.clear()
	var boot2 := BOOT_SCENE.instantiate()
	vp.add_child(boot2)
	await _settle()
	_check(requests.has(&"main_menu"), "第二次启动 → 直接请求 main_menu（实际 %s）" % str(requests))
	_check(not requests.has(&"opening"), "第二次启动不会再播开场")
	if is_instance_valid(boot2) and boot2.is_inside_tree():
		boot2.queue_free()
	await _settle()

	# ---- 4. 主菜单火漆按钮：第一次提示、第二次进开场 ----
	var menu := MENU_SCENE.instantiate()
	vp.add_child(menu)
	await _settle()
	var seal: BaseButton = menu.get_node_or_null("SealButton")
	var dialoguer: Dialoguer = menu.get_node_or_null("Dialoguer")
	_check(seal != null, "主菜单有 SealButton")
	_check(dialoguer != null, "主菜单有 Dialoguer")
	if seal == null or dialoguer == null:
		return

	SceneRouter.is_transitioning = false
	requests.clear()
	seal.emit_signal("pressed")
	await _settle()
	_check(dialoguer.visible, "第一次按火漆 → 弹出提示")
	_check(dialoguer.typer.get_full_text().contains(HINT_TEXT),
			"提示说的是「%s」（实际「%s」）" % [HINT_TEXT, dialoguer.typer.get_full_text()])
	_check(requests.is_empty(), "第一次按**不会**切场景（实际 %s）" % str(requests))

	SceneRouter.is_transitioning = false
	requests.clear()
	seal.emit_signal("pressed")
	await _settle()
	_check(requests.has(&"opening"), "第二次按火漆 → 请求切到 opening（实际 %s）" % str(requests))
	if is_instance_valid(menu) and menu.is_inside_tree():
		menu.queue_free()
	await _settle()

	# ---- 5. opening 场景：播 opening，播完回主菜单 ----
	var opening := OPENING_SCENE.instantiate()
	vp.add_child(opening)
	await _settle()
	var odlg: Dialoguer = opening.get_node_or_null("Dialoguer")
	_check(odlg != null, "开场场景有 Dialoguer")
	if odlg != null and not opening_rows.is_empty():
		_check(odlg.typer.lines.size() == opening_rows.size(),
				"播的是 opening（%d 行，实际 %d）" % [opening_rows.size(), odlg.typer.lines.size()])
		var text_match := true
		for i in mini(odlg.typer.lines.size(), opening_rows.size()):
			var want: Dictionary = opening_rows[i]
			if String(odlg.typer.lines[i].get("text", "")) != String(want.get("text", "")):
				text_match = false
		_check(text_match, "每一行正文与 json 逐字一致")
	_check(float(opening.RETURN_DELAY) > 0.0, "开场播完会自动回主菜单（RETURN_DELAY = %.1fs）" % float(opening.RETURN_DELAY))
	SceneRouter.is_transitioning = false
	requests.clear()
	opening._go_back()
	await _settle()
	_check(requests.has(&"main_menu"), "开场播完 → 请求回主菜单（实际 %s）" % str(requests))
	if is_instance_valid(opening) and opening.is_inside_tree():
		opening.queue_free()
	await _settle()

	vp.queue_free()
	await _settle()


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_opening] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_opening] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
