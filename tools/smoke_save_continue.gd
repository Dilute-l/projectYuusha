extends Node

## 存档 / 继续游戏自检（ARCHITECTURE.md §7 / §15）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_save_continue.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是这几条：
##   · 存档落在 user:// 下（不在只读的 res:// 里），而 .gitignore 挡着那个目录；
##   · **每天开始**自动存档：进第 N 天时文件里的 day 就是 N，
##     前一天挣的分留在 scores 里（「过去几天的分数 + 今天的天数」）；
##   · 主菜单「继续游戏」：**没存档时置灰且按不动**；有存档时按下去
##     读回**存档里那一局**（不是新开一局），并落到每日流程；
##   · 「最新」按文件修改时间算，手动槽位也参与比较；
##   · 坏档读不出来时**什么都不做**，绝不开一局新的把玩家那份存档骗掉。
##
## ⚠️ 自检要自己造存档，所以会把 user:// 下的自动存档与三个手动槽位**临时接管**
##   （开头备份、结尾原样还原）。中途被打断的话，桌面上会留着自检造的那几份。
##
## 为什么要常驻 runner：自检里要真的切场景（主菜单 → 每日流程），
## 而切场景会把 current_scene 释放掉 —— 逻辑挂在 root 下的常驻节点上才活得下来
## （与 smoke_m0 同一条理由、同一套写法）。

const MENU_BUTTON: String = "ContinuegameText"
const RUNNER_NAME: String = "SmokeSaveContinueRunner"

## 等一次场景切换的帧数上限（淡入淡出被设成 0，正常一两帧就落地）
const SCENE_WAIT_FRAMES: int = 600

## 「最新」那一条要隔开一秒再写第二份：判据是**文件修改时间**，
## 而它是秒级的 —— 同一秒里写两份就分不出先后了。
const MTIME_GAP_SECONDS: float = 1.2

## 主菜单上从上到下的四行菜单项（§15.2 那张版面表）
const MENU_ROWS: Array[String] = ["ContinuegameText", "StartgameText", "Credits", "ExitgameText"]

## 相邻两行墨迹上沿的差：四行一律 50，墨迹高 38 → **行距一律 12px**。
## 这个数是版面，改版面就要改它（会红一条，正是它该干的活）。
const MENU_ROW_STEP: float = 50.0

## 逐行点一下「墨迹上沿往下 2px」看归谁：这一处是**重叠区**最容易出事的地方
## （矩形比墨迹高得多，抢鼠标的都是这些看不见的边）。
const PICK_ROWS: Array[String] = [
	"Title", "Title2", "ContinuegameText", "StartgameText", "Credits", "ExitgameText", "PlaceHolderButton",
]

var _failures: Array[String] = []
var _checks: int = 0

## 自检开始前桌面上原有的存档：path -> 文件内容（跑完原样写回去）
var _backup: Dictionary = {}


func _ready() -> void:
	if name != RUNNER_NAME:
		var runner := Node.new()
		runner.name = RUNNER_NAME
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	await get_tree().process_frame
	SceneRouter.set_fade_duration(0.0)
	_backup_saves()
	await _run()
	_restore_saves()
	await _report()

# ---------------------------------------------------------------------------
# 各项检查
# ---------------------------------------------------------------------------


func _run() -> void:
	print("=== 存档 / 继续游戏自检 ===")
	_check_save_paths()
	await _check_daily_autosave()
	await _check_menu_without_save()
	await _check_menu_with_save()
	await _check_latest_save()
	await _check_corrupt_save()
	await _check_menu_layout()


## [1] 存哪儿：user:// 下（导出之后 res:// 只读），且 .gitignore 挡着
func _check_save_paths() -> void:
	print("[1] 存档路径与 .gitignore")
	_check(GameConfig.AUTO_SAVE_PATH.begins_with("user://"),
			"自动存档在 user:// 下：%s" % GameConfig.AUTO_SAVE_PATH)
	_check(GameConfig.SAVE_DIR.begins_with("user://"),
			"存档目录在 user:// 下：%s" % GameConfig.SAVE_DIR)
	var gitignore := _read_text("res://.gitignore")
	_check(gitignore.contains("saves/"), ".gitignore 里挡着存档目录 saves/")


## [2] 每天开始的自动存档：真实进一次 day_loop，再走完第 1 天
func _check_daily_autosave() -> void:
	print("[2] 每天开始的自动存档")
	GameState.start_new_run(20261016)
	_remove_all_saves()

	# 进每日流程这件事本身就是「这一天开始了」的存档点（day_loop._ready）
	var loop: Node = load("res://scenes/day/day_loop.tscn").instantiate()
	get_tree().root.add_child(loop)
	await _settle()

	var data := _read_save()
	_check(not data.is_empty(), "进了每日流程就有自动存档")
	_check(int(data.get("day", 0)) == 1, "存档里记着今天是第几天（第 %d 天）" % int(data.get("day", 0)))
	_check(data.get("scores") is Array, "存档里有 scores（过去几天的分数）")
	_check(int(data.get("version", 0)) == GameConfig.SAVE_VERSION, "存档带 version，以后加字段靠它认")
	_check(data.has("phase") and data.has("run_seed"), "存档里有 run_seed / phase（读档要接着往下走）")

	# 队伍里**必须真有人**再走这一天：战报分数 = 战力 × 倍率，空队伍是 0 分，
	# 而 score_request 现在是「每天最低分」（第 1 天起是 1）—— 0 分会在战报结束时
	# 当场判负、直接切坏结局，这一天就走不完，后面「第 2 天开始时的存档」也就无从验起。
	var walk_team: Array[StringName] = []
	for candidate in GameState.get_current_candidates():
		if candidate != null:
			walk_team.append(candidate.id)
			break
	GameState.set_current_team(walk_team)
	var button: BaseButton = loop.get_node_or_null("FlowHud/Hud/Margin/Layout/NextButton") as BaseButton
	for _phase in DayDirector.phases_of_day():
		if button != null:
			button.pressed.emit()
		else:
			loop.call("advance")
		# day_loop.advance() 有「同一帧只许推进一次」的重入锁，按帧点才等价于玩家点击
		await get_tree().process_frame
	_check(GameState.get_day() == 2, "第 1 天走完后进入第 2 天")
	# 分数由战报算出来（不再在手上前置 record_day_score）：这里读**落地后**的值
	# 当期望值，规则怎么改（战力公式 / 倍率）都不用动本文件。
	var day1_score := GameState.get_day_score(1)
	_check(day1_score > 0.0, "第 1 天的战报分数落了地（%.2f）" % day1_score)

	data = _read_save()
	_check(int(data.get("day", 0)) == 2, "第 2 天开始时的存档记的是第 2 天（不是第 1 天）")
	_check(_scores_of(data) == [int(roundf(day1_score))],
			"存档里留着第 1 天的分数（%s）" % str(data.get("scores")))
	_check(int(data.get("day", 0)) == GameState.get_day(), "存档里的天数与内存里的天数一致")

	loop.queue_free()
	await _settle()


## [3] 一份存档都没有：「继续游戏」是灰的，而且按不动
func _check_menu_without_save() -> void:
	print("[3] 没存档时的「继续游戏」")
	_remove_all_saves()
	GameState.clear_run()
	SceneRouter.goto_scene(&"main_menu")
	await _await_scene(&"main_menu")

	var menu := get_tree().current_scene
	var button := menu.get_node_or_null(MENU_BUTTON) as Button
	_check(button != null, "主菜单上有「继续游戏」按钮（%s）" % MENU_BUTTON)
	if button == null:
		return
	_check(button.text == "继续游戏", "按钮文案是「继续游戏」")
	_check(button.disabled, "一份存档都没有时按钮置灰")
	_check(not SaveService.has_any_save(), "SaveService 也说没有可继续的存档")

	# 置灰只是外观；真按下去（绕过 disabled 直接发信号）也得什么都不发生
	button.pressed.emit()
	await _settle()
	_check(SceneRouter.current_scene_key() == &"main_menu", "没存档时按「继续游戏」不会切场景")
	_check(not GameState.has_run(), "没存档时按「继续游戏」不会开新局")


## [4] 有存档：按钮亮着，按下去接着**存档里那一局**玩
func _check_menu_with_save() -> void:
	print("[4] 有存档时的「继续游戏」")
	GameState.clear_run()
	GameState.start_new_run(777)
	GameState.record_day_score(1, 100)
	GameState.record_day_score(2, 50)
	while GameState.get_day() < 5:
		GameState.advance_day()
	_check(SaveService.autosave(), "造一份「第 5 天、前两天各有分」的存档")

	SceneRouter.goto_scene(&"main_menu")
	await _await_scene(&"main_menu")
	var menu := get_tree().current_scene
	var button := menu.get_node_or_null(MENU_BUTTON) as Button
	_check(button != null and not button.disabled, "有存档时按钮是亮的")
	if button == null:
		return

	# 先把内存里这一局擦掉 —— 验的是「从磁盘上读回来的」，不是「手上还留着的那份」
	GameState.clear_run()
	button.pressed.emit()
	await _await_scene(&"day_loop")

	_check(GameState.has_run(), "按「继续游戏」读回了一局")
	_check(SceneRouter.current_scene_key() == &"day_loop", "按「继续游戏」落到每日流程")
	_check(GameState.get_day() == 5, "读到的是存档里那一天（第 %d 天）" % GameState.get_day())
	_check(GameState.get_run_seed() == 777, "读回来的是同一局的种子（不是新开的一局）")
	_check(GameState.get_day_score(1) == 100 and GameState.get_day_score(2) == 50,
			"存档里往日的分数一并读了回来")
	_check(int(_read_save().get("day", 0)) == 5,
			"继续之后那天的自动存档还是第 5 天（没被打回第 1 天）")


## [5] 「最新」那份是怎么算的：自动存档与手动槽位一起比修改时间
func _check_latest_save() -> void:
	print("[5] 「最新」的那一份存档")
	# 先离开每日流程再测：那边还挂着 day_loop 的话，下面的 advance_day() 会顺手再自动存一次
	# （day_loop 的 _on_day_started 就是每日存档点），刚写好的那个槽位就成不了「最新的一份」。
	SceneRouter.goto_scene(&"main_menu")
	await _await_scene(&"main_menu")

	GameState.clear_run()
	GameState.start_new_run(4242)
	GameState.record_day_score(1, 10)
	_check(SaveService.autosave(), "先写自动存档（第 1 天）")

	await get_tree().create_timer(MTIME_GAP_SECONDS).timeout
	GameState.advance_day()
	_check(SaveService.save_to_slot(1), "后写手动槽位 1（第 2 天）")

	var latest := SaveService.latest_save()
	_check(int(latest.get("slot", 0)) == 1, "最新的那一份是后写的槽位 1（%s）" % str(latest))

	GameState.clear_run()
	_check(SaveService.load_latest(), "load_latest 读得回来")
	_check(GameState.get_day() == 2, "读到的是最新那份里的天数（第 %d 天）" % GameState.get_day())

	# 把自动存档挪开：只剩手动槽位时，它照样是「最新的一份」
	_remove_file(GameConfig.AUTO_SAVE_PATH)
	latest = SaveService.latest_save()
	_check(int(latest.get("slot", 0)) == 1, "只剩手动槽位时，最新的就是它")
	_check(SaveService.has_any_save(), "有手动存档也算「有存档可继续」")

	SaveService.delete_slot(1)


## [6] 坏档：读不出来就什么都不做
func _check_corrupt_save() -> void:
	print("[6] 坏档不会把人骗进新一局")
	_remove_all_saves()
	_write_text(GameConfig.AUTO_SAVE_PATH, "{ 这不是一份 json")
	GameState.clear_run()

	SceneRouter.goto_scene(&"main_menu")
	await _await_scene(&"main_menu")
	var menu := get_tree().current_scene
	var button := menu.get_node_or_null(MENU_BUTTON) as Button
	# 按钮亮不亮看的是「磁盘上有没有那份文件」，坏没坏要按下去才知道
	_check(button != null and not button.disabled, "有存档文件时按钮是亮的")
	if button == null:
		return
	button.pressed.emit()
	await _settle()
	_check(SceneRouter.current_scene_key() == &"main_menu", "坏档按「继续游戏」不切场景")
	_check(not GameState.has_run(), "坏档不会顺手开一局新的")

	_remove_all_saves()

# ---------------------------------------------------------------------------
# 主菜单版面与点击归属
# ---------------------------------------------------------------------------


## [7] 看得见的那一行，点下去必须也是它
##
## 两件事一起测，因为它们本来就是一件事：按钮的**矩形**（67px 高）比**墨迹**（38px 高）大得多
## 且互相压着，谁抢到鼠标只看**树序**（GUI 拾取从树尾往前找，§12.3）——
## 排错了画面上完全看不出来，只会「点『开始游戏』却进了『继续游戏』」。
## 所以这里量的是**墨迹上沿**那一点（重叠区最容易出事的地方）归谁。
func _check_menu_layout() -> void:
	print("[7] 主菜单版面与点击归属")
	var menu: Control = load("res://scenes/menu/main_menu.tscn").instantiate()
	# 挂在 root 末尾：拾取从树尾往前找，这一份必然压在上面（与玩家看到的层次一致）
	get_tree().root.add_child(menu)
	await _settle()

	var previous_top := -1.0
	for name_of in MENU_ROWS:
		var row := menu.get_node_or_null(name_of) as Button
		_check(row != null, "主菜单上有 %s" % name_of)
		if row == null:
			continue
		var top := _ink_top(row)
		if previous_top >= 0.0:
			_check(is_equal_approx(top - previous_top, MENU_ROW_STEP),
					"「%s」与上一行等距：墨迹上沿差 %d（实际 %d）" % [
						row.text, int(MENU_ROW_STEP), int(roundf(top - previous_top)),
					])
		previous_top = top

	for name_of in PICK_ROWS:
		var row := menu.get_node_or_null(name_of) as Button
		if row == null:
			continue
		_hover_root(Vector2(row.global_position.x + row.size.x * 0.5, _ink_top(row) + 2.0))
		await get_tree().process_frame
		var hovered: Control = get_tree().root.gui_get_hovered_control()
		var hovered_name := String(hovered.name) if hovered != null else "<无>"
		_check(hovered == row, "「%s」墨迹上沿那一点归它自己（拾取到 %s）" % [row.text, hovered_name])

	menu.queue_free()
	await _settle()


## 一行文字的**墨迹上沿**。
##
## 行盒（ascent + descent）在按钮矩形里垂直居中，而墨迹是从行盒顶开始画的 ——
## 实测（渲染一帧再数非纸面像素，§15.4）：字号 60 的行盒正好 67 = 矩形高，
## 所以那几行的墨迹上沿就是矩形上沿。这个换算是「量版面」与「点哪儿」的共用前提。
func _ink_top(row: Button) -> float:
	var font := row.get_theme_font("font")
	if font == null:
		return row.global_position.y
	var font_size := row.get_theme_font_size("font_size")
	var line := font.get_ascent(font_size) + font.get_descent(font_size)
	return row.global_position.y + (row.size.y - line) * 0.5


## 往 root viewport 里真的发一次鼠标移动（in_local_coords：坐标就是画布坐标）。
## 之后 `gui_get_hovered_control()` 给出的就是「这个像素归谁」。
func _hover_root(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	get_tree().root.push_input(event, true)

# ---------------------------------------------------------------------------
# 存档文件的读写与备份
# ---------------------------------------------------------------------------


func _all_save_paths() -> Array[String]:
	var paths: Array[String] = [GameConfig.AUTO_SAVE_PATH]
	for slot in range(1, GameConfig.MAX_SAVE_SLOTS + 1):
		paths.append(GameConfig.slot_path(slot))
	return paths


func _backup_saves() -> void:
	for path in _all_save_paths():
		if FileAccess.file_exists(path):
			_backup[path] = _read_text(path)
	# 自检要自己造存档，先让桌面干净
	_remove_all_saves()


func _restore_saves() -> void:
	for path in _all_save_paths():
		if _backup.has(path):
			_write_text(path, String(_backup[path]))
		else:
			_remove_file(path)


func _remove_all_saves() -> void:
	for path in _all_save_paths():
		_remove_file(path)


## 自动存档的内容（读不出来返回空字典）
func _read_save() -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(GameConfig.AUTO_SAVE_PATH))
	return parsed if parsed is Dictionary else {}


## 存档里的往日分数，一律折成 int 再比
## —— JSON 里的数字读回来是 float（123 -> 123.0），而 GDScript 的数组比较不认这个。
func _scores_of(data: Dictionary) -> Array[int]:
	var scores: Array[int] = []
	var raw: Variant = data.get("scores", [])
	if raw is Array:
		for value in raw:
			scores.append(int(value))
	return scores


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(GameConfig.SAVE_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

# ---------------------------------------------------------------------------
# 等待与汇报
# ---------------------------------------------------------------------------


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## 等场景落地（过渡结束 + 当前场景就是 key）
func _await_scene(key: StringName) -> void:
	var frames := 0
	while frames < SCENE_WAIT_FRAMES:
		if not SceneRouter.is_transitioning and SceneRouter.current_scene_key() == key:
			break
		await get_tree().process_frame
		frames += 1
	await _settle()
	_check(SceneRouter.current_scene_key() == key,
			"切到场景 %s（等 %d 帧内落地）" % [key, SCENE_WAIT_FRAMES])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK  " if ok else "FAIL", what])


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("=== 自检结束：%d 项检查，全部通过 ===" % _checks)
	else:
		print("=== 自检结束：%d 项检查，%d 项失败 ===" % [_checks, _failures.size()])
		for failure in _failures:
			printerr("  失败：%s" % failure)
	# 退出前留一点时间让日志冲刷（与 smoke_m0 同一条理由）
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(1 if not _failures.is_empty() else 0)
