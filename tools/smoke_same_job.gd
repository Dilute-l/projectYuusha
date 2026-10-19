extends Node

## 「整队清一色同一个职业 → 分数 ×0.5，并在战报上多一句话」的自检
## （不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_same_job.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是 combat_resolver.gd 里那条**整队**规则：
##
##   最后选出的那一队（resolve() 收到的 member_ids）
##     → same_job_id()：两个人以上、人人都有 job、且 job.id 全都一样 → 返回那个 id
##     → multiplier × SAME_JOB_PENALTY（0.5），**一队只罚一次**，不随人数 / 对数叠加
##     → 战报追加一条 rule_id = "same_job" 的播报，**文案按职业各说各话**（SAME_JOB_LINES）
##
## ⚠️ 断言一律走**相对基线**：同一支队伍在「规则命中 / 不命中」各量一次，看比值。
##    因为候选人彼此之间还有相性规则（例：prideful × prideful = −0.1），
##    把绝对值写死会在规则调整时假红。
##
## 挑来当「没有相性规则」的样本：这几位不沾 bard / fourth_wall / prideful / timid /
## active / caring / rude / dwarf_joke，两两配对一条规则都不命中 —— 于是测出来的倍率
## 只剩「同职业」这一项，0.5 才能直接写死在断言里。

# 三个法师：9191 没特质、0002 只有 active、0033 只有 timid（两两都不成规则）
const MAGE_PLAIN := &"c_md_9191"
const MAGE_ACTIVE := &"c_md_0002"
const MAGE_TIMID := &"c_ct_0033"
# 一个没特质的战士：用来当混编队伍的对照组
const FIGHTER_PLAIN := &"c_md_0001"
# 另一个没特质的战士 / 两个牧师（其中一位只有 caring，两两仍不成规则）
const FIGHTER_PLAIN2 := &"c_md_9902"
const CLERIC_PLAIN := &"c_dl_0008"
const CLERIC_CARING := &"c_ct_0014"
# 两个都带 prideful 的法师：验证「相性和同职业叠加」
const MAGE_PRIDE_A := &"c_ct_0029"
const MAGE_PRIDE_B := &"c_ct_0030"


var _failures: Array[String] = []
var _checks: int = 0
var _days_backup: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	_days_backup = DataDB.get_table(&"days").duplicate()
	_run()
	_restore()
	_report()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK  " if ok else "FAIL", what])


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


## 事件池清空：本自检只关心「同职业」这一项，别让当日怪物混进倍率里
func _clear_pool() -> void:
	var cfg := DayConfig.new()
	cfg.day_index = 1
	DataDB.get_table(&"days")[&"1"] = cfg


func _ids(arr: Array) -> Array[StringName]:
	var typed: Array[StringName] = []
	for a in arr:
		typed.append(StringName(a))
	return typed


func _mult(team: Array) -> float:
	return CombatResolver.synergyMultiplier(1, _ids(team))


## 战报里 rule_id = same_job 的播报条数
func _same_job_lines(report: BattleReport) -> Array:
	return report.events.filter(func(e): return StringName(e.get("rule_id", &"")) == &"same_job")


## 断言信息里用的职业叫法（读 data/jobs 的 display_name，读不到就退回 id）
func _job_label(job_id: StringName) -> String:
	var job := DataDB.get_job(job_id)
	if job != null and not job.display_name.strip_edges().is_empty():
		return job.display_name.strip_edges()
	return String(job_id)


func _run() -> void:
	_clear_pool()

	# ---- 0. 底层：三种职业的样本都要真的是那个职业（不然下面测的不是「同职业」） ----
	var all_mage := true
	for id in [MAGE_PLAIN, MAGE_ACTIVE, MAGE_TIMID, MAGE_PRIDE_A, MAGE_PRIDE_B]:
		var m := DataDB.get_candidate(StringName(id))
		if m == null or m.job == null or m.job.id != &"job.mage":
			all_mage = false
			print("    ! %s 不是 job.mage" % id)
	_check(all_mage, "样本 5 位都是 job.mage（DataDB 按 id 读得到职业）")

	# 三支「清一色」队伍各要一对：战士 / 法师 / 牧师
	var squads := {
		&"job.fighter": [FIGHTER_PLAIN, FIGHTER_PLAIN2],
		&"job.mage": [MAGE_PLAIN, MAGE_ACTIVE],
		&"job.cleric": [CLERIC_PLAIN, CLERIC_CARING],
	}
	var jobs_ok := true
	for job_id in squads.keys():
		for id in squads[job_id]:
			var m := DataDB.get_candidate(StringName(id))
			if m == null or m.job == null or m.job.id != job_id:
				jobs_ok = false
				print("    ! %s 不是 %s" % [id, job_id])
	_check(jobs_ok, "三支样本队（战士 / 法师 / 牧师）的人都在各自职业上")
	_check(CombatResolver.all_same_job(_ids(squads[&"job.fighter"]))
			and CombatResolver.all_same_job(_ids(squads[&"job.cleric"])),
			"战士队、牧师队的 same_job_id 判定同样命中")

	# ---- 1. same_job_id：判定本身 ----
	_check(CombatResolver.same_job_id(_ids([MAGE_PLAIN, MAGE_ACTIVE])) == &"job.mage",
			"两个法师 → same_job_id = job.mage（实际 %s）"
			% CombatResolver.same_job_id(_ids([MAGE_PLAIN, MAGE_ACTIVE])))
	_check(CombatResolver.same_job_id(_ids([MAGE_PLAIN, MAGE_ACTIVE, MAGE_TIMID])) == &"job.mage",
			"三个法师 → same_job_id = job.mage（一队只看「是不是同一个」，不看几个）")
	_check(CombatResolver.same_job_id(_ids([MAGE_PLAIN, FIGHTER_PLAIN])) == &"",
			"一法一战 → &\"\"（正常的混编队伍，不算同一个职业）")

	# ---- 2. 不该命中的三种情况 ----
	_check(CombatResolver.same_job_id(_ids([])) == &"", "空队 → &\"\"")
	_check(CombatResolver.same_job_id(_ids([MAGE_PLAIN])) == &"",
			"**独苗队不判**（第 1 天就只有一个候选人，独苗天天被砍一半不是这条规则的意思）")
	_check(CombatResolver.same_job_id(_ids([MAGE_PLAIN, &"__不存在__"])) == &"",
			"队里有人查不到 → &\"\"（数据残缺时宁可放过，也别拿半个队去砍分数）")

	# ---- 3. all_same_job 与 same_job_id 同源 ----
	_check(CombatResolver.all_same_job(_ids([MAGE_PLAIN, MAGE_ACTIVE])),
			"all_same_job(两法师) = true")
	_check(not CombatResolver.all_same_job(_ids([MAGE_PLAIN, FIGHTER_PLAIN])),
			"all_same_job(法 + 战) = false")

	# ---- 4. 倍率：命中 → ×0.5 ----
	var penalty := CombatResolver.SAME_JOB_PENALTY
	_check(_approx(penalty, 0.5), "SAME_JOB_PENALTY = 0.5（实际 %.2f）" % penalty)

	var m_two := _mult([MAGE_PLAIN, MAGE_ACTIVE])
	_check(_approx(m_two, penalty),
			"两个法师（无相性规则）→ 倍率 = %.2f（实际 %.4f）" % [penalty, m_two])

	# 三个职业都该被砍到同一个倍率：规则只看「是不是同一个职业」，不看是哪个职业
	for job_id in squads.keys():
		var mi := _mult(squads[job_id])
		_check(_approx(mi, penalty),
				"%s队（无相性规则）→ 倍率 = %.2f（实际 %.4f）" % [
					_job_label(job_id), penalty, mi])

	var m_three := _mult([MAGE_PLAIN, MAGE_ACTIVE, MAGE_TIMID])
	_check(_approx(m_three, penalty),
			"三个法师（3 对都没命中规则）→ **仍然只罚 %.2f 一次**（实际 %.4f）" % [
				penalty, m_three])

	# ---- 5. 倍率：不命中 → 不罚 ----
	var m_mixed := _mult([MAGE_PLAIN, FIGHTER_PLAIN])
	_check(_approx(m_mixed, 1.0),
			"法 + 战（无相性规则）→ 倍率 1.0，同职业不罚（实际 %.4f）" % m_mixed)

	var m_single := _mult([MAGE_PLAIN])
	_check(_approx(m_single, 1.0),
			"独苗队 → 倍率 1.0，不罚（实际 %.4f）" % m_single)

	# ---- 6. 和相性一起乘：prideful × prideful = −0.1 ----
	var m_pride := _mult([MAGE_PRIDE_A, MAGE_PRIDE_B])
	_check(_approx(m_pride, 0.9 * penalty),
			"两个傲慢的法师 → (1 − 0.1) × %.2f = %.4f（实际 %.4f）" % [
				penalty, 0.9 * penalty, m_pride])

	# ---- 7. 集成：resolve() 的 day_score / breakdown ----
	var team := _ids([MAGE_PLAIN, MAGE_ACTIVE])
	var report := CombatResolver.resolve(1, team)
	var tp: float = report.breakdown.get("true_power", 0.0)
	var mult: float = report.breakdown.get("multiplier", 0.0)
	_check(tp > 0.0, "战报有底分（true_power = %.2f）" % tp)
	_check(_approx(mult, penalty),
			"resolve() 的 multiplier 被砍到 %.2f（实际 %.4f）" % [penalty, mult])
	_check(_approx(report.day_score, snappedf(tp * mult, 0.01)),
			"day_score = true_power × multiplier（%.2f × %.4f = %.2f，实际 %.2f）" % [
				tp, mult, tp * mult, report.day_score])
	_check(_approx(report.breakdown.get("synergy", 0.0), report.day_score - tp),
			"breakdown.synergy 仍等于 day_score − true_power（罚的那一半含在里面，下游不用改）")

	# ---- 8. 战报上那句话：**一个职业一句，不许共用通用文案** ----
	var lines := _same_job_lines(report)
	_check(lines.size() == 1, "战报里正好 1 条 same_job 播报（实际 %d 条）" % lines.size())
	if lines.size() == 1:
		var text := String(lines[0].get("text", ""))
		_check(text.contains("法师"), "法师队的播报念到自己那个职业（%s）" % text)
		_check(StringName(lines[0].get("actor", &"x")) == &"", "播报不挂某一位队员当 actor")
		_check(not text.contains("%s"), "播报里没有漏下来的占位符（%s）" % text)

	# 三支队伍各播一句，互相**不能是同一句**
	var texts: Dictionary = {}
	for job_id in [&"job.fighter", &"job.mage", &"job.cleric"]:
		var r := CombatResolver.resolve(1, _ids(squads[job_id]))
		var hits := _same_job_lines(r)
		_check(hits.size() == 1, "%s队正好 1 条 same_job 播报（实际 %d 条）" % [
				_job_label(job_id), hits.size()])
		if hits.size() != 1:
			continue
		var t := String(hits[0].get("text", ""))
		texts[job_id] = t
		var job := DataDB.get_job(job_id)
		var shown := job.display_name.strip_edges() if job != null else ""
		_check(not shown.is_empty() and t.contains(shown),
				"%s队的播报里出现自己的职业名（%s）（%s）" % [_job_label(job_id), shown, t])
		_check(not t.contains("%s"), "%s队的播报没有漏下来的占位符" % _job_label(job_id))
		var others := texts.keys().filter(func(k): return k != job_id)
		var clashes := others.filter(func(k): return String(texts[k]) == t)
		_check(clashes.is_empty(), "%s队的播报和别的职业不是同一句（撞了：%s）" % [
				_job_label(job_id), str(clashes)])

	# 每条文案确实在 SAME_JOB_LINES 表里（而不是靠兜底那一句过日子）
	for job_id in [&"job.fighter", &"job.mage", &"job.cleric"]:
		_check(CombatResolver.SAME_JOB_LINES.has(job_id),
				"SAME_JOB_LINES 里为 %s 写了专属文案" % _job_label(job_id))

	# 兜底：以后新加的第 4 个职业不会播空 / 播成 job.xxx
	var fallback := CombatResolver._same_job_line(&"job.__没有这个职业__")
	_check(not fallback.is_empty(), "表里没有的职业走兜底文案，不播空白（%s）" % fallback)
	_check(not fallback.contains("%s") and not fallback.contains("job."),
			"兜底文案也把职业名填进去了、没漏出 job. 前缀（%s）" % fallback)

	# 不命中的两种情况：不该多这句
	var r_mixed := CombatResolver.resolve(1, _ids([MAGE_PLAIN, FIGHTER_PLAIN]))
	_check(_same_job_lines(r_mixed).is_empty(),
			"混编队伍的战报里**没有** same_job 播报（实际 %d 条）" % _same_job_lines(r_mixed).size())
	var r_single := CombatResolver.resolve(1, _ids([MAGE_PLAIN]))
	_check(_same_job_lines(r_single).is_empty(),
			"独苗队的战报里**没有** same_job 播报（实际 %d 条）" % _same_job_lines(r_single).size())

	# ---- 9. 播报跟着队员播报之后、当日事件之前：顺序即优先级 ----
	var r_order := CombatResolver.resolve(1, _ids([MAGE_PRIDE_A, MAGE_PRIDE_B]))
	var names := r_order.events.map(func(e): return StringName(e.get("rule_id", &"")))
	var idx_same := names.find(&"same_job")
	var idx_pair := names.find(&"synergy")
	_check(idx_same > 0 and (idx_pair == -1 or idx_same > idx_pair),
			"same_job 播报排在个人评价 / 两两相性之后（下标 %d，相性 %d）" % [idx_same, idx_pair])


## 把 days 表还原成自检开始前的样子（别的自检可能并行跑 / 之后还要用）
func _restore() -> void:
	var live := DataDB.get_table(&"days")
	for key in live.keys():
		live.erase(key)
	for key in _days_backup.keys():
		live[key] = _days_backup[key]


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_same_job] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_same_job] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
