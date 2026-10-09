class_name CombatResolver
extends RefCounted

## 战斗结算（ARCHITECTURE.md §6.5）。**纯静态、不碰节点** —— §0 的纪律。
##
## ⚠️ 目前是**桩**：既不算真实战力，也不读 NarrativeRule。
## 它只负责产出一份「结构正确、同种子可复现」的 BattleReport，用来先把这条链路跑通：
##
##     core 产出  →  GameState 持有  →  battle_report.tscn 渲染
##
## 真正实现时的分工（§6.5）：
##   combat_resolver.gd    算基础结果：真实战力 / 相性加成 / 谎言处罚 / 运气修正
##   narrative_engine.gd   用 data/narrative/*.tres 的 NarrativeRule 把结果翻译成人话
## 而 data/monsters 与 data/narrative 目前都还不存在 —— 见 §3.2 / §3.5。

## 桩用的事件文案模板。真实实现里这些来自 NarrativeRule.template 的占位符替换。
const STUB_TEMPLATES: Array[String] = [
	"{actor} 冲在最前面，替队伍挡下了第一波冲击。",
	"{actor} 的判断出了偏差，队伍被迫多绕了半天路。",
	"{actor} 的装备在半路上坏了，好在没人受伤。",
	"{actor} 和同伴配合得很顺，抓住了魔物的破绽。",
]


## 结算某一天的战斗，返回可供演出的战报。
##
## 随机一律走 RngService 的「当日主随机流」（autoload/rng_service.gd 里写明它服务战报结算），
## 所以同种子 + 同一天必然得到同一份战报（§2 尾注）。
static func resolve(day_index: int, member_ids: Array[StringName]) -> BattleReport:
	var report := BattleReport.new()
	report.day_index = day_index
	report.member_ids = member_ids
	# monster_id 暂时留空：DayConfig 还没有「今天打什么」这个字段，
	# data/monsters/ 也还没有数据。补上之后这里要改成传真的 id。
	report.monster_id = &""

	var rng := RngService.day_rng(day_index)

	for member_id in member_ids:
		var template: String = STUB_TEMPLATES[rng.randi_range(0, STUB_TEMPLATES.size() - 1)]
		# 刻意**不**在这里替换 {actor}：core 只认 id，把 id 翻成人名是表现层的事
		# （见 scenes/day/battle_report.gd 的 _event_text）。
		# 真实实现里 narrative_engine.gd 会输出成品文案，这条分工还会再变一次。
		report.events.append({
			"text": template,
			"actor": member_id,
			"rule_id": &"stub",
			"priority": 0,
		})

	report.day_score = rng.randi_range(30, 90)
	report.breakdown = {
		"true_power": report.day_score,
		"synergy": 0,
		"lie_penalty": 0,
		"event_bonus": 0,
		"luck": 0,
	}
	return report
