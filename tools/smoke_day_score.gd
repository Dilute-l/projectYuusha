extends Node

## 「战报分数 → GameState 累计分」的自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_day_score.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是这条**曾断过**的链路（早先 `record_day_score()` 全仓库零调用方，
## 于是战报算出的分数只显示在屏幕上、从不进累计分，结局永远是 0 分）：
##
##   CombatResolver.resolve() → report.day_score
##     → day_loop._record_today_score()（DAY_END / RUN_END 那一刻）
##     → GameState.record_day_score() → run_state.scores → get_total_score()
##     → 存档 scores（float，小数不能丢）
##
## 顺带钉住三件事：同日重复记分不翻倍、没有战报时不记分、存档往返保小数。

const DAY_LOOP_SCENE := preload("res://scenes/day/day_loop.tscn")

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


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _run() -> void:
	GameState.start_new_run(20261018)

	# ---- 0. 开局：累计分是 0、scores 是空 ----
	_check(_approx(GameState.get_total_score(), 0.0), "开局累计分 0")
	_check(GameState.run_state.scores.is_empty(), "开局 scores 为空")

	# ---- 1. 造一份带倍率的战报（小数不能丢） ----
	var team: Array[StringName] = [&"c_ct_0006", &"c_ct_0001"]   # slime_slayer + caring
	GameState.set_current_team(team)
	var report := CombatResolver.resolve(1, team)
	GameState.set_battle_report(report)
	_check(report.day_score > 0.0, "战报有分数（%.2f）" % report.day_score)

	# 明细里的浮点尾巴要被收敛掉（420 × 1.1 = 462.0000000000001 那种）
	var breakdown: Dictionary = report.breakdown
	var raw_synergy := float(breakdown.get("synergy", 0.0))
	_check(_approx(raw_synergy, snappedf(raw_synergy, 0.01)),
			"breakdown.synergy 已收敛到两位小数（%s）" % str(breakdown.get("synergy")))

	# ---- 2. 走入记分：day_loop._record_today_score() ----
	var loop := DAY_LOOP_SCENE.instantiate()
	add_child(loop)
	await get_tree().process_frame
	loop._record_today_score()
	await get_tree().process_frame

	_check(GameState.run_state.scores.size() == 1, "scores 里出现第 1 天（%d 条）" % GameState.run_state.scores.size())
	_check(_approx(GameState.get_day_score(1), report.day_score),
			"第 1 天的分数 = 战报分数（%.2f vs %.2f）" % [
				GameState.get_day_score(1), report.day_score])
	_check(_approx(GameState.get_total_score(), report.day_score),
			"累计分 = 战报分数（%.2f）" % GameState.get_total_score())

	# ---- 3. 幂等：同一天再记一次不翻倍 ----
	var once := GameState.get_total_score()
	loop._record_today_score()
	await get_tree().process_frame
	_check(_approx(GameState.get_total_score(), once),
			"同一天重复记分不翻倍（%.2f → %.2f）" % [once, GameState.get_total_score()])

	# ---- 4. 多天累加 ----
	GameState.run_state.day = 2
	var report2 := CombatResolver.resolve(2, team)
	GameState.set_battle_report(report2)
	loop._record_today_score()
	await get_tree().process_frame
	_check(GameState.run_state.scores.size() == 2, "scores 有两天")
	_check(_approx(GameState.get_total_score(), report.day_score + report2.day_score),
			"累计分 = 两天之和（%.2f）" % GameState.get_total_score())

	# ---- 5. 没有战报 → 不记分（并打警告） ----
	var before := GameState.get_total_score()
	GameState.set_battle_report(null)
	GameState.run_state.day = 3
	loop._record_today_score()
	await get_tree().process_frame
	_check(_approx(GameState.get_total_score(), before),
			"没有战报时不记分（%.2f 保持不变）" % GameState.get_total_score())
	_check(GameState.run_state.scores.size() == 2, "也不会凭空多出第 3 天")

	# ---- 6. 存档往返：小数要保住 ----
	var dict := SaveService.to_dict(GameState.run_state)
	var back := SaveService.from_dict(dict)
	_check(back.scores.size() == 2, "存档里带回了 2 天的分数")
	var sum := 0.0
	for v in back.scores:
		sum += float(v)
	_check(_approx(sum, GameState.get_total_score()),
			"读回来的分数之和与内存一致（%.2f vs %.2f）" % [sum, GameState.get_total_score()])

	loop.queue_free()
	await get_tree().process_frame


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_day_score] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_day_score] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
