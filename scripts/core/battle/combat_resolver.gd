class_name CombatResolver
extends RefCounted

## 战斗结算（ARCHITECTURE.md §6.5）。**纯静态、不碰节点** —— §0 的纪律。
##
## 目前仍是**桩**：不读 NarrativeRule，谎言处罚 / 特殊事件 / 运气修正都还是 0。
## 已经实装的是两块：
##   · powerCaculation()  个人战力 = 主属性 × 等级 × 10；
##   · synergyOf()       队员特质互相影响（特质 × 特质 / 特质 × 种族，硬编码一行行判断）。
## 它负责产出一份「结构正确、同种子可复现」的 BattleReport：
##
##     core 产出  →  GameState 持有  →  battle_report.tscn 渲染

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
	# 先加个人战力（纯属性），再叠「队员特质互相影响」的分数增减 ——
	# 后者是硬编码的一行行判断（见 synergyOf），命中的每一对还会往战报里播一条。
	var true_power := finalPowerCaculation(member_ids)
	var synergy := synergyOf(member_ids, report)
	report.day_score = true_power + synergy
	report.breakdown = {
		"true_power": true_power,
		"synergy": synergy,
		"lie_penalty": 0,
		"event_bonus": 0,
		"luck": 0,
	}
	return report

## 个人战力 = 主属性 × 等级 × 10（**纯属性**，不含任何队伍相性）。
##
## ⚠️ 读的是**实际属性**（`true_strength()` 那一组），不是简历上写的 `member.strength`：
## 纸上的数是他自称的，结算只认真身板（§3.1）。没写 true_attributes 的人两者相等，
## 所以老数据一行都不用改。
##
## 等级是 `member.level` —— **隐藏属性**，玩家在简历上看不到（§3.1），
## 所以「纸上写得漂亮但只有一级」的人，分数当场掉下来。
## 等级 ≥ 1 由数据层兜底（smoke_m0 盯着，谁都不许填 0 / 负数），这里不做夹取 ——
## 夹了只会把「数据填错了」这件事盖住。
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


## 全队**纯属性**战力 = Σ 个人战力。
##
## ⚠️ 这里**不叠**队员之间的相性 / 羁绊 —— 那是 synergyOf() 的活，
## 由 resolve() 加上去并单独记进 breakdown.synergy。本函数只回答「这几个人各自值多少分」。
static func finalPowerCaculation(member_ids: Array[StringName]) -> int:
	var temptotal: int = 0
	for member_id in member_ids:
		var member := DataDB.get_candidate(member_id)
		if member == null:
			# 查不到人不能静默跳过：那样这一份战力就是凭空少了，还看不出来
			push_warning("[CombatResolver] 名单里的 %s 查不到，战力按 0 计" % member_id)
			continue
		temptotal += powerCaculation(member)
	return temptotal


# ---------------------------------------------------------------------------
# 队员特质互相影响（硬编码一行行判断）
# ---------------------------------------------------------------------------
#
# 「谁和谁」：队伍里每两位队员两两配对。一方的**特质**可能撞上另一方的**特质**，
# 也可能撞上另一方的**种族** —— 所以每条规则都写成对称判断：谁站左边、谁站右边，
# 同一条规则都只结算一次。正数 = 配合（战力 +），负数 = 冲突（战力 −）。
#
# 加一条规则 = 加一段「一行判断 + 一行记分 + 一行播报」，不碰任何资源，也不建新列表。
# 特意**不读** TraitInteractionTable / data/traits/interactions.tres：这套相性就是这些 if 行本身。


## 队员特质互相影响的总分（配合为正、冲突为负）。
##
## report 不为 null 时，每命中一条规则就往战报里追加一条播报（见 _add_synergy_event）。
static func synergyOf(member_ids: Array[StringName], report: BattleReport = null) -> int:
	var total: int = 0
	for i in member_ids.size():
		for j in range(i + 1, member_ids.size()):
			var a := DataDB.get_candidate(member_ids[i])
			var b := DataDB.get_candidate(member_ids[j])
			if a == null or b == null:
				push_warning("[CombatResolver] 相性配对跳过：%s / %s 查不到" % [
					member_ids[i], member_ids[j]])
				continue
			total += _pair_synergy(a, b, report)
	return total


## 两位队员之间跑一遍特质 / 种族判断，返回这一对的分数增减。
##
## ★ 想加 / 改相性就改这一个函数 ★
static func _pair_synergy(a: CandidateResource, b: CandidateResource, report: BattleReport = null) -> int:
	var delta: int = 0

    # 示例代码：
    
	# # ── 特质 × 特质：正义感 × 骑士精神 → 配合默契 ──
	# if _both_have_traits(a, b, &"trait.justice", &"trait.chivalry"):
	# 	delta += 30
	# 	_add_synergy_event(report, "「%s」与「%s」同频共振，两人配合默契（战力 +30）。" % [
	# 		_trait_label(a, b, &"trait.justice"), _trait_label(a, b, &"trait.chivalry")])
	# # 自恋 × 独狼：一个要人捧，一个要独处 → 争吵
	# if _both_have_traits(a, b, &"trait.ego", &"trait.lone_wolf"):
	# 	delta -= 30
	# 	_add_synergy_event(report, "「%s」遇上「%s」：一个要人捧，一个要独处，没走两步就吵了起来（战力 -30）。" % [
	# 		_trait_label(a, b, &"trait.ego"), _trait_label(a, b, &"trait.lone_wolf")])
	# # 热血 × 冷静：一热一冷，恰好互补
	# if _both_have_traits(a, b, &"trait.hot_blooded", &"trait.calm"):
	# 	delta += 20
	# 	_add_synergy_event(report, "「%s」与「%s」一热一冷，恰好补上了彼此的短板（战力 +20）。" % [
	# 		_trait_label(a, b, &"trait.hot_blooded"), _trait_label(a, b, &"trait.calm")])
	# # 贪婪 × 收集癖：都想把战利品往自己兜里塞 → 争抢
	# if _both_have_traits(a, b, &"trait.greedy", &"trait.collector"):
	# 	delta -= 20
	# 	_add_synergy_event(report, "「%s」和「%s」为战利品争红了脸，队伍行动都慢了半拍（战力 -20）。" % [
	# 		_trait_label(a, b, &"trait.greedy"), _trait_label(a, b, &"trait.collector")])
	# # 嗜酒 × 嗜酒：酒友相投
	# if _both_have_traits(a, b, &"trait.drunkard", &"trait.drunkard"):
	# 	delta += 20
	# 	_add_synergy_event(report, "两个「%s」凑在一起，夜里多喝了两壶，反倒处出了交情（战力 +20）。" % [
	# 		_trait_label(a, b, &"trait.drunkard")])
	# # 收集癖 × 收集癖：争抢藏品
	# if _both_have_traits(a, b, &"trait.collector", &"trait.collector"):
	# 	delta -= 15
	# 	_add_synergy_event(report, "两个「%s」都想把同一件东西收进自己包里（战力 -15）。" % [
	# 		_trait_label(a, b, &"trait.collector")])
	# # 自恋 × 自恋：谁也不服谁
	# if _both_have_traits(a, b, &"trait.ego", &"trait.ego"):
	# 	delta -= 25
	# 	_add_synergy_event(report, "两个「%s」互不相让，队伍里全是较劲的味道（战力 -25）。" % [
	# 		_trait_label(a, b, &"trait.ego")])
	# # 失眠 × 失眠：同病相怜，夜里搭伴闲聊
	# if _both_have_traits(a, b, &"trait.insomnia", &"trait.insomnia"):
	# 	delta += 10
	# 	_add_synergy_event(report, "两个「%s」在夜里聊了一宿，第二天居然意外精神（战力 +10）。" % [
	# 		_trait_label(a, b, &"trait.insomnia")])
	# # 正义感 × 热血：侠义心肠一拍即合
	# if _both_have_traits(a, b, &"trait.justice", &"trait.hot_blooded"):
	# 	delta += 20
	# 	_add_synergy_event(report, "「%s」与「%s」一拍即合，抢着打头阵（战力 +20）。" % [
	# 		_trait_label(a, b, &"trait.justice"), _trait_label(a, b, &"trait.hot_blooded")])
	# # 骑士精神 × 独狼：一个非要护着，一个不领情
	# if _both_have_traits(a, b, &"trait.chivalry", &"trait.lone_wolf"):
	# 	delta -= 10
	# 	_add_synergy_event(report, "「%s」非要护着「%s」，后者只觉得被冒犯（战力 -10）。" % [
	# 		_trait_label(a, b, &"trait.chivalry"), _trait_label(a, b, &"trait.lone_wolf")])

	# # ── 特质 × 种族：一方是特质、另一方是种族（谁站左边都认）──
	# # 嗜酒 × 矮人：矮人对酒很执着 → 酒友
	# if _trait_meets_race(a, b, &"trait.drunkard", &"race.st"):
	# 	delta += 20
	# 	_add_synergy_event(report, "「%s」遇上了%s，当晚就拼上了酒，成了酒友（战力 +20）。" % [
	# 		_trait_label(a, b, &"trait.drunkard"), _race_label(a, b, &"race.st")])
	# # 收集癖 × 矮人：矮人对矿脉执着，和收藏癖一拍即合
	# if _trait_meets_race(a, b, &"trait.collector", &"race.st"):
	# 	delta += 15
	# 	_add_synergy_event(report, "「%s」拉着%s去挖矿，两个人都心满意足（战力 +15）。" % [
	# 		_trait_label(a, b, &"trait.collector"), _race_label(a, b, &"race.st")])
	# # 热血 × 精灵：精灵说话慢，热血的人被磨得难受
	# if _trait_meets_race(a, b, &"trait.hot_blooded", &"race.el"):
	# 	delta -= 15
	# 	_add_synergy_event(report, "「%s」嫌%s磨磨蹭蹭，一路催个不停（战力 -15）。" % [
	# 		_trait_label(a, b, &"trait.hot_blooded"), _race_label(a, b, &"race.el")])
	# # 冷静 × 精灵：都慢条斯理，节奏正好
	# if _trait_meets_race(a, b, &"trait.calm", &"race.el"):
	# 	delta += 10
	# 	_add_synergy_event(report, "「%s」和%s都不着急，配合得十分从容（战力 +10）。" % [
	# 		_trait_label(a, b, &"trait.calm"), _race_label(a, b, &"race.el")])
	# # 正义感 × 矮人：矮人固执但讲原则，正义感的人懂他
	# if _trait_meets_race(a, b, &"trait.justice", &"race.st"):
	# 	delta += 15
	# 	_add_synergy_event(report, "「%s」乐得给%s的倔脾气评理，两人处得不错（战力 +15）。" % [
	# 		_trait_label(a, b, &"trait.justice"), _race_label(a, b, &"race.st")])

	return delta


## 命中的相性往战报里追加一条播报。文本里不放 {actor}：
## 它说的是两位队员之间的特质 / 种族，而不是某一个人的台词。
static func _add_synergy_event(report: BattleReport, text: String) -> void:
	if report == null:
		return
	report.events.append({
		"text": text,
		"actor": &"",
		"rule_id": &"synergy",
		"priority": 1,
	})


## 这个成员带不带这个特质（查的是 CandidateResource.traits）。
static func _has_trait(member: CandidateResource, trait_id: StringName) -> bool:
	if member == null or member.traits == null:
		return false
	for t in member.traits:
		if t != null and t.id == trait_id:
			return true
	return false


## 这个成员是不是这个种族（查的是 CandidateResource.race.id）。
static func _is_race(member: CandidateResource, race_id: StringName) -> bool:
	return member != null and member.race != null and member.race.id == race_id


## 对称判断：一方带 x、另一方带 y —— 谁站左边都只结算一次。
static func _both_have_traits(a: CandidateResource, b: CandidateResource, x: StringName, y: StringName) -> bool:
	return (_has_trait(a, x) and _has_trait(b, y)) or (_has_trait(b, x) and _has_trait(a, y))


## 特质 × 种族：一方带 trait_id、另一方是这个 race_id —— 谁站左边都认。
static func _trait_meets_race(a: CandidateResource, b: CandidateResource, trait_id: StringName, race_id: StringName) -> bool:
	return (_has_trait(a, trait_id) and _is_race(b, race_id)) \
			or (_has_trait(b, trait_id) and _is_race(a, race_id))


## 这条规则要显示的特质名：先在 a 身上找，再在 b 身上找；都没有就退回 id。
static func _trait_label(a: CandidateResource, b: CandidateResource, trait_id: StringName) -> String:
	if _has_trait(a, trait_id):
		return _trait_name(a, trait_id)
	if _has_trait(b, trait_id):
		return _trait_name(b, trait_id)
	return String(trait_id)


## 特质在数据里的显示名（空名退回 id —— 别让播报里出现空白）。
static func _trait_name(member: CandidateResource, trait_id: StringName) -> String:
	if member == null or member.traits == null:
		return String(trait_id)
	for t in member.traits:
		if t != null and t.id == trait_id:
			var label := t.display_name.strip_edges()
			return label if not label.is_empty() else String(trait_id)
	return String(trait_id)


## 这条规则要显示的种族名：同样两边都找。
static func _race_label(a: CandidateResource, b: CandidateResource, race_id: StringName) -> String:
	if _is_race(a, race_id):
		return _race_name(a, race_id)
	if _is_race(b, race_id):
		return _race_name(b, race_id)
	return String(race_id)


## 种族在数据里的显示名（空名退回 id）。
static func _race_name(member: CandidateResource, race_id: StringName) -> String:
	if member == null or member.race == null:
		return String(race_id)
	var label := member.race.display_name.strip_edges()
	return label if not label.is_empty() else String(race_id)
