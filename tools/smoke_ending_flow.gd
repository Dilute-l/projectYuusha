extends Node

## 结局分流 的自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_ending_flow.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 验四件事：
##   1. `DayConfig.score_request` 存在且 10 天都是 1（数据侧）；
##   2. 好结局场景（ending.tscn）只播 `Ending_Good`，`{total_score}` 被替换，播完自动回主界面；
##   3. `day_loop._passes_score_request()` 的判定：0 = 没要求、达标放行、不达标判负；
##   4. 这条判定**真的接在战报之后**：`day_loop.advance()` 在 BATTLE_REPORT 结束时
##      判负 → 请求切 `bad_ending` 且不进下一天；达标 → 进下一天 / 最后一天进 `ending`。
##      判据用「今日分数」而不是累计分（5e 专门钉这条）。

const ENDING_SCENE := preload("res://scenes/ending/ending.tscn")
const BAD_SCENE := preload("res://scenes/ending/bad_ending.tscn")
const DAY_LOOP_SCENE := preload("res://scenes/day/day_loop.tscn")

const GAME_CANVAS := Vector2i(1152, 648)

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	_report()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK  " if ok else "FAIL", what])


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	# 自检自己就挂在「当前场景」上，而流程里进坏结局 / 进结局都是**真的切场景** ——
	# 一旦切过去，自检节点会跟着当前场景一起被释放，后面的检查项就全没了。
	# 把过场拉到 30 秒：切换会停在 fade 上（自检早就退出了），
	# 而「要切到哪个场景」看 EventBus.scene_change_started —— 它在 fade **之前**发。
	SceneRouter.set_fade_duration(30.0)

	# ---- 1. 数据侧：10 天都有 DayConfig，score_request 读得出来 ----
	# ⚠️ 不钉具体数值：score_request 已经从"十天统一临时值 1"变成逐日不同的策划配置，
	#    自检只保证「字段存在且是能用的整数」，具体多少由 data/days/*.tres 决定。
	var missing := 0
	var values: Array[String] = []
	for day in range(1, GameConfig.TOTAL_DAYS + 1):
		var cfg := DataDB.get_day_config(day)
		if cfg == null:
			missing += 1
			continue
		values.append("day%d=%d" % [day, cfg.score_request])
	_check(missing == 0, "10 天的 DayConfig 都读得到（缺 %d）" % missing)
	print("      · 当前 score_request：%s" % ", ".join(values))

	# ---- 2. 判定逻辑：0 = 没要求 / 达标放行 / 不达标判负 ----
	var vp := SubViewport.new()
	vp.size = GAME_CANVAS
	vp.disable_3d = true
	get_tree().root.add_child(vp)

	GameState.start_new_run(20261018)
	var loop := DAY_LOOP_SCENE.instantiate()
	vp.add_child(loop)
	await _settle()

	# 把第 1 天临时换成可控的 score_request / 分数
	var days := DataDB.get_table(&"days")
	var backup: Dictionary = days.duplicate()

	# 2a. score_request = 0（没要求）→ 哪怕 0 分也达标
	_set_day1(days, 0, 0.0)
	_check(loop._passes_score_request(), "score_request = 0 → 没要求，0 分也放行")

	# 2b. score_request = 100，分数 100 → 达标（边界：不小于即通过）
	_set_day1(days, 100, 100.0)
	_check(loop._passes_score_request(), "分数 = 要求（100 vs 100）→ 放行（不小于即通过）")

	# 2c. score_request = 100，分数 99.99 → 判负
	_set_day1(days, 100, 99.99)
	_check(not loop._passes_score_request(), "分数 99.99 < 要求 100 → 判负")

	# 2d. score_request = 100，分数 0 → 判负
	_set_day1(days, 100, 0.0)
	_check(not loop._passes_score_request(), "分数 0 < 要求 100 → 判负")

	# 还原 days 表
	for key in days.keys():
		days.erase(key)
	for key in backup.keys():
		days[key] = backup[key]

	loop.queue_free()
	await _settle()

	# ---- 3. 好结局场景：只播 Ending_Good，播完自动回主界面 ----
	GameState.start_new_run(20261018)
	GameState.record_day_score(1, 400.0, {})
	GameState.record_day_score(2, 124.0, {})
	var total_text := "%.0f" % GameState.get_total_score()

	var ending := ENDING_SCENE.instantiate()
	vp.add_child(ending)
	await _settle()
	var dlg: Dialoguer = ending.get_node_or_null("Dialoguer")
	_check(dlg != null, "好结局场景有 Dialoguer")
	# 行数**不写死**：Ending_Good 的文案会继续加长（写手一直在补），
	# 自检只钉「播的就是 json 里那一段」和「{total_score} 那一行真的被替换」。
	var expect_good := _dialogue_rows("Ending_Good")
	_check(not expect_good.is_empty(), "data/dialogue.json 里有 Ending_Good 段")
	if dlg != null and not expect_good.is_empty():
		_check(dlg.typer.lines.size() == expect_good.size(),
				"播的是 Ending_Good（%d 行，实际 %d）" % [expect_good.size(), dlg.typer.lines.size()])
		var score_index := -1
		for i in expect_good.size():
			var row: Dictionary = expect_good[i]
			if String(row.get("text", "")).contains("{total_score}"):
				score_index = i
				break
		_check(score_index >= 0, "Ending_Good 里有一行写着 {total_score} 占位符")
		if score_index >= 0:
			dlg.typer.start_line(score_index)
			await _settle()
			var text := dlg.typer.get_full_text()
			_check(text.contains(total_text), "那一行念出真实总分（含 %s）：%s" % [total_text, text])
			_check(not text.contains("{total_score}"), "占位符已被替换")

	# 自动返回：好结局在**对话播完**之后停顿 RETURN_DELAY 秒，自己发 restart_requested 并切主菜单。
	# ⚠️ 别用 is_transitioning 判断 —— headless 下它本来就是 false，那样等于没验。
	# ⚠️ 也别真的 await 那 2.5 秒：headless 下计时器要走真实时间，自检会被拖住。
	#    这里验的是**逻辑**：播完前不安排、播完后安排、以及_go_back() 真的发信号。
	_check(ending.RETURN_DELAY > 0.0, "好结局有自动返回的停顿（%.1fs）" % ending.RETURN_DELAY)
	var returned: Array[int] = []
	ending.restart_requested.connect(func() -> void: returned.append(1))
	_check(not ending.get("_returning"), "对话还没播完时**不会**安排返回")
	# 模拟对话播到底：dialoguer 的 dialogue_ended 就是"玩家把最后一句点掉了"
	dlg.dialogue_ended.emit()
	await _settle()
	_check(ending.get("_returning"), "对话播完后才安排返回")
	# 直接验证「返回」这一步本身：_go_back() 会发 restart_requested 并切主菜单
	ending._go_back()
	_check(returned.size() == 1, "返回时发起了 restart_requested（%d 次）" % returned.size())

	if is_instance_valid(ending) and ending.is_inside_tree():
		ending.queue_free()
	await _settle()

	# ---- 4. 坏结局场景：播 Ending_Bad ----
	var bad := BAD_SCENE.instantiate()
	vp.add_child(bad)
	await _settle()
	var bdlg: Dialoguer = bad.get_node_or_null("Dialoguer")
	_check(bdlg != null, "坏结局场景有 Dialoguer")
	if bdlg != null:
		_check(bdlg.typer.lines.size() >= 1, "播的是 Ending_Bad（%d 行）" % bdlg.typer.lines.size())
		_check(bad.RETURN_DELAY > 0.0, "坏结局也有自动返回的停顿（%.1fs）" % bad.RETURN_DELAY)
	if is_instance_valid(bad) and bad.is_inside_tree():
		bad.queue_free()
	await _settle()

	# ---- 5. 判定接在流程里：战报结束 → advance() → 达标 / 判负 ----
	# 第 2 段只验了判定函数本身。这里验它有没有被**接进流程**：
	# 第 1〜9 天走 DAY_END、第 10 天走 RUN_END，两条路都要在记分之后先判一次。
	#
	# 十天的 score_request 临时统一成 100：这一段的「判负 / 放行」必须由自检掌握，
	# 不能跟着 data/days/*.tres 里正在调的数值变（现在逐日不同，还可能是 0 = 没要求）。
	var gate_days := DataDB.get_table(&"days")
	var gate_days_backup: Dictionary = gate_days.duplicate()
	for day in range(1, GameConfig.TOTAL_DAYS + 1):
		_patch_day(gate_days, day, 100)

	var requests: Array[StringName] = []
	EventBus.scene_change_started.connect(
		func(key: StringName, _path: String) -> void: requests.append(key))

	var gate := DAY_LOOP_SCENE.instantiate()
	vp.add_child(gate)
	await _settle()

	# 5a. 第 1 天 0 分（要求 1）→ 坏结局，天数停在 1
	_arm_battle_report(1, 0.0)
	await _settle()
	gate.advance()
	await _settle()
	_check(requests.has(&"bad_ending"),
			"第 1 天 0 分 < 要求 1 → 请求切到 bad_ending（实际 %s）" % str(requests))
	_check(GameState.get_phase() == DayPhase.Phase.ENDING, "判负后阶段是 ENDING（实际 %s）" % DayPhase.to_name(GameState.get_phase()))
	_check(GameState.get_day() == 1, "判负后没有进入第 2 天（停在第 %d 天）" % GameState.get_day())

	# 5b. 第 10 天 0 分 → 最后一天的战报看完同样先判负，不直接进好结局
	requests.clear()
	_arm_battle_report(GameConfig.TOTAL_DAYS, 0.0)
	await _settle()
	gate.advance()
	await _settle()
	_check(requests.has(&"bad_ending"), "第 10 天 0 分 → 也请求 bad_ending（实际 %s）" % str(requests))
	_check(not requests.has(&"ending"), "判负时**没有**同时请求好结局")
	_check(GameState.get_day() == GameConfig.TOTAL_DAYS, "判负后仍停在最后一天")

	# 5c. 第 10 天达标 → 好结局
	requests.clear()
	_arm_battle_report(GameConfig.TOTAL_DAYS, 500.0)
	await _settle()
	gate.advance()
	await _settle()
	_check(requests.has(&"ending"), "第 10 天达标 → 请求切到 ending（实际 %s）" % str(requests))
	_check(not requests.has(&"bad_ending"), "达标时没有误判成坏结局")

	# 5d. 第 1 天达标 → 进第 2 天，不切场景
	requests.clear()
	_arm_battle_report(1, 500.0)
	await _settle()
	gate.advance()
	await _settle()
	_check(requests.is_empty(), "达标后只是换天，没有场景切换请求（实际 %s）" % str(requests))
	_check(GameState.get_day() == 2, "达标后进入第 2 天（实际第 %d 天）" % GameState.get_day())
	_check(GameState.get_phase() == DayPhase.Phase.DAY_BRIEFING, "换天后回到 DAY_BRIEFING")
	_check(absf(GameState.get_day_score(1) - 500.0) < 0.001,
			"第 1 天的分数先落地了（%.2f）" % GameState.get_day_score(1))

	# 5e. 累计分很高 + 当天 0 分 → 照样判负（判的是今日分数，不是累计分）
	requests.clear()
	GameState.record_day_score(1, 999.0, {})
	_arm_battle_report(2, 0.0)
	await _settle()
	gate.advance()
	await _settle()
	_check(requests.has(&"bad_ending"), "累计分很高但当天 0 分 → 判负（实际 %s）" % str(requests))
	_check(GameState.get_total_score() >= 999.0,
			"判负时累计分仍然是高的（%.2f）—— 说明判的是今日分数" % GameState.get_total_score())

	if is_instance_valid(gate) and gate.is_inside_tree():
		gate.queue_free()
	await _settle()

	# 还原 data/days 表（第 5 段临时改过的 score_request）
	for key in gate_days.keys():
		gate_days.erase(key)
	for key in gate_days_backup.keys():
		gate_days[key] = gate_days_backup[key]

	vp.queue_free()
	await _settle()


## 把 data/days 表里第 day 天换成一份可控的 DayConfig（只为自检用，用完要还原）。
## 和 _set_day1 的区别：它顺便写分数，这里只改 score_request。
func _patch_day(days: Dictionary, day: int, required: int) -> void:
	var cfg := DayConfig.new()
	cfg.day_index = day
	cfg.score_request = required
	days[StringName(str(day))] = cfg


## 把流程摆到「第 day 天的战报刚看完」：阶段 = BATTLE_REPORT，当天分数写进战报。
##
## 顺带把 SceneRouter 的切换状态清干净 —— 上一个用例已经发起过一次切换，
## 它现在正停在 30 秒的 fade 上（见 _run 开头），is_transitioning 还是 true，
## 不清掉的话下一次 advance() 会被「正在切换」直接挡回来。
func _arm_battle_report(day: int, today_score: float) -> void:
	GameState.run_state.day = day
	var report := BattleReport.new()
	report.day_index = day
	report.day_score = today_score
	GameState.set_battle_report(report)
	GameState.set_phase(DayPhase.Phase.BATTLE_REPORT)
	SceneRouter.is_transitioning = false


## 读 data/dialogue.json 里某一段的行数组（读不出来返回空数组）。
## 自检拿它当期望值：文案改字 / 加行都不用动这个文件。
func _dialogue_rows(id: String) -> Array:
	var file := FileAccess.open("res://data/dialogue.json", FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and (parsed as Dictionary).get(id) is Array:
		return (parsed as Dictionary)[id]
	return []


## 把第 1 天换成指定 score_request + 当天分数（分数写进 scores[0]）
func _set_day1(days: Dictionary, required: int, today_score: float) -> void:
	var cfg := DayConfig.new()
	cfg.day_index = 1
	cfg.score_request = required
	days[&"1"] = cfg
	GameState.run_state.scores.resize(1)
	GameState.run_state.scores[0] = today_score


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_ending_flow] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_ending_flow] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
