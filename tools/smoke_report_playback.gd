extends Node

## 「战报逐行播报的账，能不能加 / 乘回去」的自检（不需要编辑器，也不用开着场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_report_playback.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯两件事：
##
##  A. **core 塞给战报的那两列说话数是自洽的**：
##        Σ event.score  == breakdown.true_power      （每个人自身战力加起来 = 队伍战力）
##        Π event.factor == breakdown.multiplier      （每条倍率乘起来 = 总倍率）
##     第二条最容易写错：一对同时命中两条相性时，第二条乘的是「增量」而不是它自己的
##     delta（结算的是 1+Σdelta，不是 (1+d1)×(1+d2)）。见 combat_resolver._pair_step_factor。
##
##  B. **界面照这两列数播完，底下总分落在 report.day_score 上**，
##     而且一开始就是「总分 0 + 今日目标」—— 这是这次演出改动的两条硬指标。
##
## 它不测动画好不好看（那要人眼），只测「播完的数 == 存盘 / 结局读的数」。

const BATTLE_REPORT_SCENE := preload("res://scenes/day/battle_report.tscn")

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


func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) < eps


func _run() -> void:
	GameState.start_new_run(20261018)

	# ---- 1. 十天各跑一遍：真数据下的两列说话数 ----
	# 用当天配置里的前 slots 位候选人，跟真实游玩同一条路（CombatResolver.resolve）。
	print("[1] 十天 × 当天队伍：Σscore == true_power、Πfactor == multiplier")
	for day in range(1, GameConfig.TOTAL_DAYS + 1):
		var config := DataDB.get_day_config(day)
		if config == null:
			continue
		var team: Array[StringName] = []
		for i in mini(config.slots, config.candidates.size()):
			team.append(config.candidates[i].id)
		if team.is_empty():
			continue
		var report := CombatResolver.resolve(day, team)
		_verify_ledger(report, "第 %d 天（%d 人）" % [day, team.size()])

	# ---- 2. 一对命中两条规则：第二条乘的是「增量」 ----
	# 直接钉住那条容易写错的算式，先不管数据里有没有这种组合。
	print("[2] 一对命中两条规则时的倍率口径")
	_check(_approx(CombatResolver._pair_step_factor(0.0, 0.2), 1.2),
			"只命中一条 +0.2 → 播 ×1.2（实际 %s）" % CombatResolver._pair_step_factor(0.0, 0.2))
	var second := CombatResolver._pair_step_factor(0.2, 0.3)
	_check(second > 1.0 and second < 1.1,
			"同一对的第二条（合计 +0.3）播 ×%s，是增量不是 ×1.1" % snappedf(second, 0.0001))
	_check(_approx(1.2 * second, 1.3), "×1.2 再乘这条 = ×1.3（结算给的那一个数）")

	# ---- 3. 真数据里找一对命中两条的，验一遍 ----
	# 找不到不算失败（相性表改了就可能一对只撞一条），但要如实说出来。
	var multi_rule_pairs := 0
	var sample := ""
	for a_id in DataDB.get_ids(&"candidates"):
		var a := DataDB.get_candidate(a_id)
		if a == null:
			continue
		for b_id in DataDB.get_ids(&"candidates"):
			if b_id <= a_id:
				continue
			var b := DataDB.get_candidate(b_id)
			if b == null:
				continue
			var probe := BattleReport.new()
			var delta := CombatResolver._pair_synergy(a, b, probe)
			if probe.events.size() < 2:
				continue
			multi_rule_pairs += 1
			var product := 1.0
			for event in probe.events:
				product *= float(event.get("factor", 1.0))
			if sample.is_empty():
				sample = "%s × %s：%d 条，乘完 ×%s / 结算 delta %s" % [
					a_id, b_id, probe.events.size(), snappedf(product, 0.0001),
					snappedf(delta, 0.0001)]
				_check(_approx(product, 1.0 + delta, 0.0002),
						"一对命中 %d 条时 Πfactor == 1+delta（%s）" % [probe.events.size(), sample])
	print("      · 数据里一对命中多条规则的有 %d 对%s" % [
		multi_rule_pairs, ("，例：" + sample) if not sample.is_empty() else "（这批数据没撞上，算式已在 [2] 里钉住）"])

	# ---- 4. 界面：一开始 0 分 + 今日目标 ----
	print("[4] 战报界面：起始状态")
	GameState.set_battle_report(null)
	var team: Array[StringName] = [&"c_ct_0006", &"c_ct_0001"]   # 一个人 + 一位相性搭档
	GameState.set_current_team(team)
	var report := CombatResolver.resolve(1, team)
	var day_config := DataDB.get_day_config(1)
	GameState.set_battle_report(report)

	var view := BATTLE_REPORT_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(view._score != null and view._score.text == "0",
			"一进界面总分就是 0（实际「%s」）" % (view._score.text if view._score else "?"))
	_check(view._target != null and view._target.text == str(day_config.score_request),
			"今日目标一直在，且只写数字（「%s」= 今天要求 %d）" % [
				view._target.text if view._target else "?", day_config.score_request])
	# 「同一副样子」= 同字号 + 同颜色：今日目标不许再掉回小号灰字
	var score_size: int = view._score.get_theme_font_size("font_size")
	var target_size: int = view._target.get_theme_font_size("font_size")
	var score_color: Color = view._score.get_theme_color("font_color")
	var target_color: Color = view._target.get_theme_color("font_color")
	_check(score_size == target_size, "今日目标与总分同一个字号（%d vs %d）" % [
			score_size, target_size])
	_check(score_color == target_color, "今日目标与总分同一个颜色（%s vs %s）" % [
			score_color.to_html(false), target_color.to_html(false)])
	_check(view._row_labels.size() == report.events.size() + 1,
			"行数 = 抬头行 1 + 事件 %d（实际 %d 行）" % [
				report.events.size(), view._row_labels.size()])

	# 每一行该跟的尾巴：个人 → +xxx，相性 / 事件 → ×x
	var member_rows := 0
	var synergy_rows := 0
	var bad_rows: Array[String] = []
	for row in view._rows:
		var kind := StringName(row.get("kind", &"note"))
		var plain := str(row.get("plain", ""))
		if kind == &"member":
			member_rows += 1
			if not plain.contains("+"):
				bad_rows.append(plain)
		elif kind == &"synergy":
			synergy_rows += 1
			if not plain.contains("×"):
				bad_rows.append(plain)
	_check(bad_rows.is_empty(), "每行都跟上了自己的说话数%s" % (
			"" if bad_rows.is_empty() else "（漏了：%s）" % ", ".join(bad_rows)))
	_check(member_rows == report.events.filter(
			func(e: Dictionary) -> bool: return e.has("score")).size(),
			"个人评价那几行各有一个 +xxx（%d 行）" % member_rows)
	print("      · 这份战报：%d 个个人行 + %d 条相性 / 事件行" % [member_rows, synergy_rows])

	# ---- 5. 播完：总分落在 day_score 上 ----
	print("[5] 播完（跳过动画）之后")
	# 先硬造一条「还在滚」的分数补间：这正是「播到一半点确认」时的状态。
	# 跳过如果不把它掐掉，它会一帧帧把摆好的 day_score 拽回 123456。
	view._count_to(123456.0, Color.WHITE)
	view.finish_playback()
	await get_tree().create_timer(0.6).timeout
	_check(_approx(view._shown_score, report.day_score),
			"显示的总分 == day_score（%s vs %.2f）" % [view._shown_score, report.day_score])
	_check(view._score.text == view._format_number(report.day_score),
			"中途跳过之后总分没被还在飞的补间拽走（「%s」）" % view._score.text)
	var shown := 0
	for label in view._row_labels:
		if is_instance_valid(label) and label.modulate.a >= 1.0:
			shown += 1
	_check(shown == view._row_labels.size(), "所有行都亮着（%d / %d）" % [shown, view._row_labels.size()])

	# 同一份战报再喂一次不许重播（_ready 与 day_phase_entered 会连着来两次）
	var rows_before: int = view._row_labels.size()
	var token_before: int = view._play_token
	view.set_report(report)
	await get_tree().process_frame
	_check(view._row_labels.size() == rows_before and view._play_token == token_before,
			"同一份战报重复 set_report 不重播")

	# 签名回放跟着正文一起挪到了右下角落款位（原来占着纸面正中那条横带）
	var pad: SignaturePad = view._ensure_signature_pad()
	_check(pad != null and pad.position == view.SIGNATURE_PAD_RECT.position
			and pad.size == view.SIGNATURE_PAD_RECT.size,
			"签名回放画布落在右下角（%s）" % (str(pad.position) if pad != null else "没建出来"))

	view.queue_free()
	await get_tree().process_frame
	GameState.set_battle_report(null)

	# ---- 6. 最长的战报也压不到底下那条分数 ----
	# 十天里事件最多的是第 10 天那种 4 人队（十几条相性 / 事件）。字号的活就是给它干的：
	# 量出来塞得下才用，塞不下就往下让 —— 这一项盯的是「量」和「真排版」是同一个数。
	print("[6] 最长战报的排版")
	var worst_config := DataDB.get_day_config(GameConfig.TOTAL_DAYS)
	var worst_team: Array[StringName] = []
	for i in mini(worst_config.slots, worst_config.candidates.size()):
		worst_team.append(worst_config.candidates[i].id)
	var worst := CombatResolver.resolve(GameConfig.TOTAL_DAYS, worst_team)
	GameState.set_battle_report(worst)
	var long_view := BATTLE_REPORT_SCENE.instantiate()
	add_child(long_view)
	await get_tree().process_frame
	await get_tree().process_frame

	var lowest := 0.0
	for label in long_view._row_labels:
		if is_instance_valid(label):
			lowest = maxf(lowest, float(label.position.y + label.size.y))
	_check(lowest <= long_view._content.size.y + 0.5,
			"最低一行底边 %.0f ≤ 正文框高 %.0f（%d 行 / %d 条事件）" % [
				lowest, long_view._content.size.y, long_view._row_labels.size(),
				worst.events.size()])

	long_view.finish_playback()
	await get_tree().create_timer(0.6).timeout
	_check(_approx(long_view._shown_score, worst.day_score),
			"长战报也落回 day_score（%s vs %.2f）" % [long_view._shown_score, worst.day_score])
	long_view.queue_free()
	await get_tree().process_frame
	GameState.set_battle_report(null)


## 一份战报的账：Σscore / Πfactor 必须等于 breakdown 里那两个数，
## 而且「一路加成 / 乘过来」的落点必须是 day_score。
func _verify_ledger(report: BattleReport, label: String) -> void:
	var sum_score := 0.0
	var product := 1.0
	var member_events := 0
	var factor_events := 0
	for event in report.events:
		if event.has("score"):
			sum_score += float(event.get("score", 0.0))
			member_events += 1
		if event.has("factor"):
			product *= float(event.get("factor", 1.0))
			factor_events += 1

	var breakdown: Dictionary = report.breakdown
	var true_power := float(breakdown.get("true_power", 0.0))
	var multiplier := float(breakdown.get("multiplier", 1.0))

	_check(_approx(sum_score, true_power, 0.01),
			"%s：Σ个人分 == true_power（%.2f vs %.2f，%d 条）" % [
				label, sum_score, true_power, member_events])
	_check(_approx(product, multiplier, 0.0005),
			"%s：Π倍率 == multiplier（%.4f vs %.4f，%d 条）" % [
				label, product, multiplier, factor_events])
	# 表现层就是这么播的：先把个人分加起来，再一条条乘过去
	_check(_approx(sum_score * product, report.day_score, 0.02),
			"%s：播到底的那个数 == day_score（%.2f vs %.2f）" % [
				label, sum_score * product, report.day_score])


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_report_playback] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_report_playback] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
