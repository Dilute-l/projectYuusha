extends Node

## 真结局解锁链 的自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_true_ending.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 验的是「两个条件 → 主菜单标题解锁 → 真结局场景」这条链：
##
##   1. 把带 `trait.true_ending` 的人编进队伍 → 账本点亮 FLAG_MEMBER_TEAMED
##      （GameState.set_current_team → EndingUnlock.note_team）
##   2. 正常走完十天、好结局收尾 → 点亮 FLAG_NORMAL_CLEARED
##      （ending.gd::_go_back → EndingUnlock.note_normal_ending）
##   3. 两个都点亮才解锁：主菜单 Title 从 disabled 变可按、文案换成「败犬面试官太多了！」
##      按下后请求切 true_ending 场景，且那个场景真的播 Ending_True、播完回主菜单
##
## 期望文案 / 行数一律从 data/ 现读，写手改文案不用动这个文件。
##
## ⚠️ 自检会临时写 user://saves/progress.json：开头备份、结尾原样还原 ——
##    否则跑一次自检就等于替玩家把真结局提前解开了。

const MENU_SCENE := preload("res://scenes/menu/main_menu.tscn")
const TRUE_SCENE := preload("res://scenes/ending/true_ending.tscn")
const ENDING_SCENE := preload("res://scenes/ending/ending.tscn")

## 游戏的实际画布（project.godot 的 canvas_items 拉伸基准）
const GAME_CANVAS := Vector2i(1152, 648)

const DIALOGUE_PATH := "res://data/dialogue.json"

## 主菜单标题按钮的两句文案（断言用；改文案时这里也要跟着改）
const TITLE_TEXT_DEFAULT := "败犬勇者太多了！"
const TITLE_TEXT_HINT := "败犬面试官太多了！"

var _failures: Array[String] = []
var _checks: int = 0

## 自检开始前磁盘上那份解锁账本；null = 原本没有这个文件
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


## 把账本清成「什么都没解锁」，但**不落盘**（结尾统一还原，见 _restore_progress）
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
	# 先让内存停在「什么都不解锁」，再把磁盘那份写回去 —— 顺序反了会把自己造的 flag 写进账本
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

	# 进真结局、回主菜单都是**真的切场景**，而自检自己就挂在当前场景上。
	# 把过场拉到 30 秒：切换停在 fade 上（自检早退出了）；
	# 要验"请求去哪个场景"看 EventBus.scene_change_started（它在 fade **之前**发）。
	SceneRouter.set_fade_duration(30.0)
	var requests: Array[StringName] = []
	EventBus.scene_change_started.connect(
		func(key: StringName, _path: String) -> void: requests.append(key))

	# ---- 1. 数据 + 规则：trait.true_ending 认不认得出来 ----
	var trait_res: TraitDef = DataDB.get_trait(EndingUnlock.TRUE_ENDING_TRAIT)
	_check(trait_res != null, "data/traits/ 里有 %s" % EndingUnlock.TRUE_ENDING_TRAIT)

	GameState.start_new_run(20261019)
	_clear_progress_in_memory()
	_check(not EndingUnlock.is_unlocked(), "一开始什么都没解锁")

	var plain: CandidateResource = null
	for candidate in GameState.get_current_candidates():
		if candidate != null and not EndingUnlock.is_true_ending_candidate(candidate):
			plain = candidate
			break
	_check(plain != null, "当日名单里有一位普通候选人")
	if plain == null or trait_res == null:
		return

	_check(not EndingUnlock.is_true_ending_candidate(plain), "普通候选人没有真结局特质")

	# 临时给这一位挂上特质（只改内存里的资源；本段结束立刻还原）
	var saved_traits: Array[TraitDef] = []
	saved_traits.assign(plain.traits)
	plain.traits.append(trait_res)
	_check(EndingUnlock.is_true_ending_candidate(plain), "挂上 trait.true_ending → 认得出来")

	# 只挂特质、没进队：还不算「被编入队伍」
	_check(not EndingUnlock.has_member_teamed(), "只挂特质、没进队 → 第一个 flag 还没点")

	# 进队 → 点亮第一个 flag
	var trait_team: Array[StringName] = [plain.id]
	GameState.set_current_team(trait_team)
	_check(EndingUnlock.has_member_teamed(), "编入队伍 → 第一个 flag 点亮")
	_check(not EndingUnlock.is_unlocked(), "只有第一个 flag → 尚未解锁")

	# 幂等：同一位再进一次队不会重复点
	_check(not EndingUnlock.note_team(trait_team), "同一位再进一次队 → flag 不重复点亮")
	var empty_team: Array[StringName] = []
	_check(not EndingUnlock.note_team(empty_team), "空队伍不点亮任何东西")

	# 还原特质，别污染后面的场景
	plain.traits = saved_traits
	_check(not EndingUnlock.is_true_ending_candidate(plain), "特质已还原")

	# ---- 2. 正常走完十天 → 点亮第二个 flag（用真的好结局场景收尾）----
	_clear_progress_in_memory()
	var ending := ENDING_SCENE.instantiate()
	vp.add_child(ending)
	await _settle()
	SceneRouter.is_transitioning = false
	ending._go_back()
	await _settle()
	_check(EndingUnlock.is_normal_cleared(), "好结局收尾（_go_back）→ 第二个 flag 点亮")
	_check(not EndingUnlock.is_unlocked(), "只有第二个 flag → 仍未解锁")
	if is_instance_valid(ending) and ending.is_inside_tree():
		ending.queue_free()
	await _settle()

	# ---- 3. 主菜单：未解锁时不可按下、文案还是默认 ----
	_clear_progress_in_memory()
	var menu := MENU_SCENE.instantiate()
	vp.add_child(menu)
	await _settle()
	var title: Button = menu.get_node_or_null("Title")
	_check(title != null, "主菜单有 Title 按钮")
	if title == null:
		return
	_check(title.disabled, "未解锁 → 标题按钮不可按下")
	_check(title.text == TITLE_TEXT_DEFAULT,
			"未解锁 → 文案还是「%s」（实际「%s」）" % [TITLE_TEXT_DEFAULT, title.text])

	# 绕过 disabled 直接发信号：也不许进真结局
	requests.clear()
	title.emit_signal("pressed")
	await _settle()
	_check(requests.is_empty(), "未解锁时按下标题 → 不切场景（实际 %s）" % str(requests))

	# 只点亮第二个 flag（正常通关了、但没带过真结局角色）：文案该换，按钮仍不可按
	GameState.set_progress_flag(EndingUnlock.FLAG_NORMAL_CLEARED)
	menu._refresh_title_button()
	await _settle()
	_check(title.text == TITLE_TEXT_HINT,
			"正常通关后文案换成「%s」（实际「%s」）" % [TITLE_TEXT_HINT, title.text])
	_check(title.disabled, "只差第一个 flag → 按钮仍不可按下")

	# 两个都点亮 → 可按，按下请求真结局
	GameState.set_progress_flag(EndingUnlock.FLAG_MEMBER_TEAMED)
	menu._refresh_title_button()
	await _settle()
	_check(not title.disabled, "两个 flag 都点亮 → 标题按钮可按")
	SceneRouter.is_transitioning = false
	requests.clear()
	title.emit_signal("pressed")
	await _settle()
	_check(requests.has(&"true_ending"), "按下标题 → 请求切到 true_ending（实际 %s）" % str(requests))
	if is_instance_valid(menu) and menu.is_inside_tree():
		menu.queue_free()
	await _settle()

	# ---- 4. 真结局场景：播 Ending_True，播完自动回主菜单 ----
	var expect_true := _dialogue_rows("Ending_True")
	_check(not expect_true.is_empty(), "data/dialogue.json 里有 Ending_True 段")
	var true_scene := TRUE_SCENE.instantiate()
	vp.add_child(true_scene)
	await _settle()
	var tdlg: Dialoguer = true_scene.get_node_or_null("Dialoguer")
	_check(tdlg != null, "真结局场景有 Dialoguer")
	if tdlg != null and not expect_true.is_empty():
		_check(tdlg.typer.lines.size() == expect_true.size(),
				"播的是 Ending_True（%d 行，实际 %d）" % [expect_true.size(), tdlg.typer.lines.size()])
		var text_match := true
		for i in mini(tdlg.typer.lines.size(), expect_true.size()):
			var want: Dictionary = expect_true[i]
			if String(tdlg.typer.lines[i].get("text", "")) != String(want.get("text", "")):
				text_match = false
		_check(text_match, "每一行正文与 json 逐字一致")
	_check(true_scene.RETURN_DELAY > 0.0, "真结局也有自动返回的停顿（%.1fs）" % true_scene.RETURN_DELAY)
	SceneRouter.is_transitioning = false
	requests.clear()
	true_scene._go_back()
	await _settle()
	_check(requests.has(&"main_menu"), "真结局播完 → 请求回主菜单（实际 %s）" % str(requests))
	if is_instance_valid(true_scene) and true_scene.is_inside_tree():
		true_scene.queue_free()
	await _settle()

	# ---- 5. 账本落盘往返（沙箱写不了 user:// 时跳过这一条）----
	_clear_progress_in_memory()
	var wrote := GameState.set_progress_flag(EndingUnlock.FLAG_MEMBER_TEAMED)
	_check(wrote, "点亮 flag 返回「这次真的变了」")
	if not SaveService.has_progress():
		print("  [SKIP] 沙箱里写不了 user://，跳过账本落盘往返；编辑器里跑 F6 会走这一条")
	else:
		var back := SaveService.load_progress()
		_check(bool(back.get(EndingUnlock.FLAG_MEMBER_TEAMED, false)), "账本落盘后能读回来")

	vp.queue_free()
	await _settle()


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_true_ending] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_true_ending] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
