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
		var member := DataDB.get_candidate(member_id)
		if member == null:
			push_warning("[CombatResolver] 名单里的 %s 查不到，跳过" % member_id)   # 别静默
			continue

		# 这一条播的就是这位候选人自己的 judgment（data/candidates/*.tres 里写好的那句评价）。
		# 顺序**严格跟着 member_ids 走** —— 谁先出战谁先播，不重排、不排序。
		var text := member.judgment.strip_edges()
		var rule_id := &"judgment"
		if text.is_empty():
			# 没写评价不能留一行空白：退回桩文案，但要留痕
			push_warning("[CombatResolver] %s 没写 judgment，这一条退回桩文案" % member_id)
			text = STUB_TEMPLATES[rng.randi_range(0, STUB_TEMPLATES.size() - 1)]
			rule_id = &"stub"
		report.events.append({
			"text": text,
			"actor": member_id,
			"rule_id": rule_id,
			"priority": 0,
		})

	# ── 循环外：全队合计 ──
	var team_power := finalPowerCaculation(member_ids)
	report.day_score = team_power
	report.breakdown = {
		"true_power": team_power,      # ← 不再是 report.day_score（那会儿它还是 0）
		"synergy": 0,
		"lie_penalty": 0,
		"event_bonus": 0,
		"luck": 0,
	}
	return report

##后续要加入根据特质决定个人分数的地方，在这里加入对tempower的计算就好
##
## ⚠️ 读的是**实际属性**（`true_strength()` 那一组），不是简历上写的 `member.strength`：
## 纸上的数是他自称的，结算只认真身板（§3.1）。没写 true_attributes 的人两者相等，
## 所以老数据一行都不用改。
##
## 公式：**主属性 × 等级 × 10**（主属性 = 职业对应的那一项）。
##   · 等级是 `member.level` —— **隐藏属性**，玩家在简历上看不到（§3.1），
##     所以「纸上写得漂亮但只有一级」的人，分数当场掉下来；
##   · 等级 ≥ 1 由数据层兜底（smoke_m0 盯着，谁都不许填 0 / 负数），这里不做夹取 ——
##     夹了只会把「数据填错了」这件事盖住。
static func powerCaculation(member: CandidateResource) -> int:
	var tempower: int = 0
	match member.job.id:
		&"job.fighter":
			tempower += member.true_strength() * member.level * 10
		&"job.mage":
			tempower += member.true_intelligence() * member.level * 10
		&"job.cleric":
			tempower += member.true_wisdom() * member.level * 10
	return tempower
	
##后需要加入根据羁绊队伍增减分可以在这里修改temptotal
static func finalPowerCaculation(member_ids: Array[StringName])->int:
	var temptotal: int = 0
	for member_id in member_ids:
		var member := DataDB.get_candidate(member_id)
		if member == null:
			# 查不到人不能静默跳过：那样这一份战力就是凭空少了，还看不出来
			push_warning("[CombatResolver] 名单里的 %s 查不到，战力按 0 计" % member_id)
			continue
		temptotal += powerCaculation(member) 
	return temptotal
