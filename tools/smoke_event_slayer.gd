extends Node

## 当日事件 × 队员 slayer 特质 的自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_event_slayer.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是**羁绊倍率**里那条「队外」规则（combat_resolver.gd::synergyMultiplier）：
##
##   DayConfig.event_pool → event_monsters(day) → 怪物 id
##     → 队里有没有 `trait.<怪物>_slayer`（只看有无）
##     → 每种怪物 ×(1+0.05) 或 ×(1−0.3)，**一队只算一次**，不随人数 / 对数叠加
##     → day_score = true_power × multiplier
##
## ⚠️ 断言一律走**相对基线**：同一支队伍在「事件池空 / 有事件」各量一次，看比值。
##    因为这些候选人自己之间也有相性规则（例：prideful × rude = −0.4），
##    把绝对值写死会在规则调整时假红。

const SLIME_SLAYER := &"c_ct_0006"   # trait.slime_slayer
const GHOST_SLAYER := &"c_ct_0008"   # trait.ghost_slayer
const PLAIN := &"c_ct_0005"          # trait.timid（没有 slayer）
const PLAIN2 := &"c_ct_0001"         # trait.caring
const PLAIN3 := &"c_ct_0004"         # trait.caring

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


func _set_pool(pool: Array) -> void:
	var cfg := DayConfig.new()
	cfg.day_index = 1
	var typed: Array[StringName] = []
	for p in pool:
		typed.append(StringName(p))
	cfg.event_pool = typed
	DataDB.get_table(&"days")[&"1"] = cfg


func _ids(arr: Array) -> Array[StringName]:
	var typed: Array[StringName] = []
	for a in arr:
		typed.append(StringName(a))
	return typed


## 同一支队伍：事件池空时的倍率 → [0]，带上 pool 时的倍率 → [1]
func _measure(team: Array, pool: Array) -> Array:
	_set_pool([])
	var base := CombatResolver.synergyMultiplier(1, _ids(team))
	_set_pool(pool)
	var with_events := CombatResolver.synergyMultiplier(1, _ids(team))
	return [base, with_events]


func _run() -> void:
	# ---- 0. 底层：get_event 读得到 data/event（上一版这里是 null，整套静默失效） ----
	var any_event: DailyEventDef = DataDB.get_event(&"slime")
	_check(any_event != null, "DataDB.get_event(&\"slime\") 读得到（表键是单数 event）")
	if any_event == null:
		return

	var miss := 1.0 - CombatResolver.EVENT_MISSING_SLAYER_PENALTY
	var hit := 1.0 + CombatResolver.EVENT_SLAYER_BONUS

	# ---- 1. 没有事件 → 与基线一致（不扣分） ----
	var m0 := _measure([PLAIN, PLAIN2], [])
	_check(_approx(m0[0], m0[1]), "没有事件 → 倍率与基线一致（%.4f）" % m0[0])

	# ---- 2. 有怪物、没人克 → 只乘一次惩罚（不随人数/对数叠加） ----
	var m2 := _measure([PLAIN, PLAIN2], [&"slime"])
	_check(_approx(m2[1], m2[0] * miss),
			"2 人队没人克史莱姆 → %.4f × %.2f = %.4f（实际 %.4f）" % [
				m2[0], miss, m2[0] * miss, m2[1]])

	var m3 := _measure([PLAIN, PLAIN2, PLAIN3], [&"slime"])
	_check(_approx(m3[1], m3[0] * miss),
			"3 人队（3 对）没人克史莱姆 → **仍然只乘 %.2f 一次**：%.4f → %.4f" % [
				miss, m3[0], m3[1]])

	# ---- 3. 有 slayer → 乘一次加成，两个 slayer 也不叠 ----
	var m_has := _measure([SLIME_SLAYER, PLAIN], [&"slime"])
	_check(_approx(m_has[1], m_has[0] * hit),
			"队里有史莱姆杀手 → %.4f × %.2f = %.4f（实际 %.4f）" % [
				m_has[0], hit, m_has[0] * hit, m_has[1]])

	var m_two := _measure([SLIME_SLAYER, &"c_dl_0003"], [&"slime"])
	_check(_approx(m_two[1], m_two[0] * hit),
			"两个史莱姆杀手同队 → 仍然只乘一次（实际 %.4f）" % m_two[1])

	# ---- 4. 克错了对象 → 按「没人克」处理 ----
	var m_wrong := _measure([GHOST_SLAYER, PLAIN], [&"slime"])
	_check(_approx(m_wrong[1], m_wrong[0] * miss),
			"带的是幽灵杀手 → 对史莱姆按「没人克」扣一次（实际 %.4f）" % m_wrong[1])

	# ---- 5. 两只不同怪物 → 各算一次 ----
	var m_both := _measure([SLIME_SLAYER, GHOST_SLAYER], [&"slime", &"ghost"])
	_check(_approx(m_both[1], m_both[0] * hit * hit),
			"两只都有人克 → %.4f × %.2f × %.2f = %.4f（实际 %.4f）" % [
				m_both[0], hit, hit, m_both[0] * hit * hit, m_both[1]])

	var m_one := _measure([SLIME_SLAYER, PLAIN], [&"slime", &"ghost"])
	_check(_approx(m_one[1], m_one[0] * hit * miss),
			"克史莱姆但不克幽灵 → 一加一扣：%.4f × %.2f × %.2f = %.4f（实际 %.4f）" % [
				m_one[0], hit, miss, m_one[0] * hit * miss, m_one[1]])

	# ---- 6. 不存在的 event id → 跳过（等于没有事件） ----
	var m_bad := _measure([PLAIN, PLAIN2], [&"__不存在__"])
	_check(_approx(m_bad[1], m_bad[0]),
			"池里写不存在的 id → 当没有事件，倍率不变（%.4f vs %.4f）" % [m_bad[1], m_bad[0]])

	# ---- 7. 集成：day_score = true_power × multiplier ----
	_set_pool([&"slime"])
	var report := CombatResolver.resolve(1, _ids([SLIME_SLAYER, PLAIN]))
	var tp: float = report.breakdown.get("true_power", 0.0)
	var mult: float = report.breakdown.get("multiplier", 0.0)
	_check(mult > 1.0, "resolve() 的 multiplier > 1.0（实际 %.4f）" % mult)
	_check(_approx(report.day_score, tp * mult),
			"day_score = true_power × multiplier（%.2f × %.4f = %.2f，实际 %.2f）" % [
				tp, mult, tp * mult, report.day_score])
	_check(_approx(report.breakdown.get("synergy", 0.0), report.day_score - tp),
			"breakdown.synergy 仍等于 day_score − true_power（下游兼容）")

	# 播报判据用**魔物名**（文案措辞会改，魔物名来自 data/event 的 event_name，稳定）
	var lines := report.events.filter(
		func(e): return String(e.get("text", "")).contains("史莱姆"))
	_check(lines.size() == 1, "战报里只播 1 条史莱姆相关的（每种怪物一次），实际 %d 条" % lines.size())

	_set_pool([&"slime", &"ghost"])
	var r2 := CombatResolver.resolve(1, _ids([SLIME_SLAYER, GHOST_SLAYER]))
	var lines_slime := r2.events.filter(
		func(e): return String(e.get("text", "")).contains("史莱姆"))
	var lines_ghost := r2.events.filter(
		func(e): return String(e.get("text", "")).contains("幽灵"))
	_check(lines_slime.size() == 1 and lines_ghost.size() == 1,
			"两只怪物 → 各播 1 条（史莱姆 %d / 幽灵 %d）" % [
				lines_slime.size(), lines_ghost.size()])


func _restore() -> void:
	var live := DataDB.get_table(&"days")
	for key in live.keys():
		live.erase(key)
	for key in _days_backup.keys():
		live[key] = _days_backup[key]


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_event_slayer] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_event_slayer] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
