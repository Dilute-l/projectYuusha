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
	# **羁绊是乘数，不是加数**：它作用在 total 上，把整队战力放大或缩小一个倍率。
	#
	#   multiplier = 队伍羁绊倍率（1.0 = 无影响，见 synergyMultiplier）
	#             = 队内两两相性（_pair_synergy 的 delta 当「倍率增量」逐对相乘）
	#             × 当日事件（每种怪物一次：有 slayer ×(1+加成)，没有 ×(1−惩罚)）
	#
	#   day_score  = true_power × multiplier
	#   breakdown.synergy = 倍率带来的差值（= day_score − true_power），
	#                       所以「true_power + synergy == day_score」这条仍然成立，
	#                       下游（战报明细 / 自检）不用改。
	var true_power := finalPowerCaculation(member_ids)
	var multiplier := synergyMultiplier(day_index, member_ids, report)
	report.day_score = true_power * multiplier
	report.breakdown = {
		"true_power": true_power,
		"synergy": report.day_score - true_power,
		"multiplier": multiplier,
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
static func powerCaculation(member: CandidateResource) -> float:
	var tempower: float = 0
	match member.job.id:
		&"job.fighter":
			tempower += member.true_strength() * member.level * 10
		&"job.mage":
			tempower += member.true_intelligence() * member.level * 10
		&"job.cleric":
			tempower += member.true_wisdom() * member.level * 10
	match member.fake_level:
		&"fake0":
			tempower *= 1
		&"fake1":
			tempower *= 0.8
		&"fake0":
			tempower *= 0.5
		&"fake0":
			tempower *= 0.1
	return tempower


## 全队**纯属性**战力 = Σ 个人战力。
##
## ⚠️ 这里**不叠**队员之间的相性 / 羁绊 —— 那是 synergyOf() 的活，
## 由 resolve() 加上去并单独记进 breakdown.synergy。本函数只回答「这几个人各自值多少分」。
static func finalPowerCaculation(member_ids: Array[StringName]) -> float:
	var temptotal: float = 0
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
#
# ⚠️ 这里的 delta 是**倍率增量**，不是分数：+0.1 表示这一对让 total ×1.1。
#    total 是四位数（属性 × 等级 × 10），加 0.1 分毫无意义 —— 所以要乘不要加。
#    队外事件（当日怪物 × slayer）**不在 _pair_synergy 里**：它按「每种怪物一次」结算，
#    而本函数是「每对一次」，塞进来会随队伍人数重复扣分。见 synergyMultiplier()。


## 当日「大量出没」的怪物，队里有对口的 `<怪物>_slayer` 时，加多少倍率。
const EVENT_SLAYER_BONUS := 0.05

## 当日「大量出没」的怪物，队里**没人**克它时扣多少倍率（0.3 = total ×0.7）。
## 每种怪物只扣一次 —— 不随队伍人数 / 对数叠加。
const EVENT_MISSING_SLAYER_PENALTY := 0.3



## 当日事件池里的魔物 id（`DayConfig.event_pool` → `DailyEventDef.id`）。
##
## 约定：**魔物 id 就是事件 id** —— `data/event/slime.tres` 的 id 是 `slime`，
## 对应的特质叫 `trait.slime_slayer`。数据里没有单独的 monster 字段，所以这条命名
## 必须对齐，否则永远配不上。
##
## 池子没填 / 当天配置读不到 → 返回空数组，事件加成**安静地不加**（不是报错）：
## 特殊事件还没实装完，不能因为数据没填就把整份战报搞崩。
## 查不到对应 DailyEventDef 的 id 会 push_warning 并跳过 —— 否则表现就是「今天白跑一趟」。
static func event_monsters(day_index: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	var config := DataDB.get_day_config(day_index)
	if config == null:
		return ids
	for event_id in config.event_pool:
		if event_id == &"":
			continue
		var event := DataDB.get_event(event_id)
		if event == null:
			push_warning("[CombatResolver] 第 %d 天的事件池里有 %s，但 data/event 里查不到" % [
				day_index, event_id])
			continue
		# event.id 才是「魔物 id」的正身（文件名可能和它不同）
		ids.append(event.id if event.id != &"" else event_id)
	return ids


## 这一对里，有没有人正好是 monster_id 的 slayer（只看**有无**，不看几个人）。
##
## 和 _both_have_traits() 是同一个写法：两人任一带有即可，谁站左边都认。
static func _pair_slays(a: CandidateResource, b: CandidateResource, monster_id: StringName) -> bool:
	var bare := String(monster_id).trim_prefix("monster.")
	var trait_id := StringName("trait.%s_slayer" % bare)
	return _has_trait(a, trait_id) or _has_trait(b, trait_id)


## 整支队伍的**羁绊倍率**（1.0 = 无影响）。
##
## 羁绊是**乘数**不是加数：它作用在 total 战力上（total 是四位数，加 0.1 毫无意义），
## 所以这里返回的是一个倍率，由 resolve() 乘上去。
##
## 组成 = 队内两两相性 × 队外当日事件：
##   · 队内：每种相性规则给 _pair_synergy 一个 delta，逐对相乘 —— (1 + delta)
##           正 delta = 放大，负 delta = 缩小。没命中任何规则的一对返回 0.0 → ×1.0。
##   · 队外：**每种当日怪物只判一次**（不看队里有几个人、也不看几对）：
##           队里有人带 `trait.<魔物>_slayer` → ×(1 + EVENT_SLAYER_BONUS)
##           没人带                            → ×(1 − EVENT_MISSING_SLAYER_PENALTY)
##           为什么按「怪物」而不是按「对」：按对扣分会让「队里人多」变成一种惩罚
##           （3 人队扣 3 次），而设计意图是「今天要打的东西你熟不熟」——这是一件事。
##
## report 不为 null 时，每条命中的规则往战报里追加一条播报。
static func synergyMultiplier(day_index: int, member_ids: Array[StringName],
		report: BattleReport = null) -> float:
	var multiplier: float = 1.0
	for i in member_ids.size():
		for j in range(i + 1, member_ids.size()):
			var a := DataDB.get_candidate(member_ids[i])
			var b := DataDB.get_candidate(member_ids[j])
			if a == null or b == null:
				push_warning("[CombatResolver] 相性配对跳过：%s / %s 查不到" % [
					member_ids[i], member_ids[j]])
				continue
			multiplier *= 1.0 + _pair_synergy(a, b, report)

	# 队外：每种怪物一次
	for monster_id in event_monsters(day_index):
		var slayer := _any_slayer(member_ids, monster_id)
		if not slayer.is_empty():
			multiplier *= 1.0 + EVENT_SLAYER_BONUS
			_add_synergy_event(report, "旅途上遇到了很多%s，%s轻松的处理掉了这些敌人。" % [
				_monster_name(monster_id), _names_of(slayer)])
		else:
			multiplier *= 1.0 - EVENT_MISSING_SLAYER_PENALTY
			_add_synergy_event(report, "今日%s大量出没，可是队里没人知道该怎么对付它们。" % [
				_monster_name(monster_id)])

	return multiplier


## 队里所有克这只怪物的人（空数组 = 没人克）。只用来判有无 + 播报点名，不参与计分次数。
static func _any_slayer(member_ids: Array[StringName], monster_id: StringName) -> Array[StringName]:
	var hit: Array[StringName] = []
	for member_id in member_ids:
		var member := DataDB.get_candidate(member_id)
		if member != null and _pair_slays(member, member, monster_id) and not hit.has(member_id):
			hit.append(member_id)
	return hit


## 一串 id → 显示名（播报用；空名退回 id）
static func _names_of(ids: Array[StringName]) -> String:
	var out: Array[String] = []
	for id in ids:
		var member := DataDB.get_candidate(id)
		var label := member.display_name.strip_edges() if member != null else ""
		out.append(label if not label.is_empty() else String(id))
	return "、".join(out)


## 两位队员之间的相性 —— 返回**倍率增量**（0.0 = 没影响，+0.1 = ×1.1，−0.3 = ×0.7）。
##
## ★ 想加 / 改相性就改这一个函数 ★
##
## ⚠️ 队外事件（当日怪物 × slayer）**不在这里** —— 它按「每种怪物一次」结算，
##    而本函数是「每对一次」，塞进来会随人数重复扣分。见 synergyMultiplier()。
static func _pair_synergy(a: CandidateResource, b: CandidateResource,
		report: BattleReport = null) -> float:
	var delta: float = 0.0
#傲慢+胆小
	if _both_have_traits(a, b, &"trait.prideful", &"trait.timid"):
		delta -= 0.1
		_add_synergy_event(report, "%s一路上都在压力%s，搞得大家都有点不愉快。" % [
		_trait_label(a, b, &"trait.prideful"), _trait_label(a, b, &"trait.timid")])
#积极+积极		
	if _both_have_traits(a, b, &"trait.active", &"trait.active"):
		delta += 0.2
		_add_synergy_event(report, "%s和%s把队伍的气氛调动了起来，所有人都很有干劲。" % [
		_trait_label(a, b,&"trait.active"), _trait_label(a, b,&"trait.active")])
#体贴+胆小		
	if _both_have_traits(a, b, &"trait.caring", &"trait.timid"):
		delta += 0.1
		_add_synergy_event(report, "虽然%s有点软脚了，但%s就像妈妈一样把他照顾的很好。" % [
		_trait_label(a, b,&"trait.timid"), _trait_label(a, b,&"trait.caring")])
#傲慢+粗鲁		
	if _both_have_traits(a, b, &"trait.rude", &"trait.prideful"):
		delta -= 0.2
		_add_synergy_event(report, "在%s吹嘘自己的时候，%s诋毁了他一句，俩人差点打了起来。" % [
		_trait_label(a, b,&"trait.prideful"), _trait_label(a, b,&"trait.rude")])
#傲慢+傲慢
	if _both_have_traits(a, b, &"trait.prideful", &"trait.prideful"):
		delta -= 0.1
		_add_synergy_event(report, "%s和%s都认为自己才是最强的，导致路上他们一直在吵。" % [
		_trait_label(a, b,&"trait.prideful"), _trait_label(a, b,&"trait.prideful")])
#粗鲁+胆小
	if _both_have_traits(a, b, &"trait.timid", &"trait.rude"):
		delta -= 0.1
		_add_synergy_event(report, "%s的战斗技巧和为人处世都有些暴躁，搞得%s有些害怕。" % [
		_trait_label(a, b,&"trait.rude"), _trait_label(a, b,&"trait.timid")])	
#傲慢+活跃
	if _both_have_traits(a, b, &"trait.active", &"trait.prideful"):
		delta += 0.1
		_add_synergy_event(report, "%s总觉得%s的积极表现是在和自己竞争，然后……他似乎出了更多的力。" % [
		_trait_label(a, b,&"trait.prideful"), _trait_label(a, b,&"trait.active")])	
#积极+体贴
	if _both_have_traits(a, b, &"trait.active", &"trait.caring"):
		delta += 0.1
		_add_synergy_event(report, "%s把有些莽撞的%s照顾得很好。" % [
		_trait_label(a, b,&"trait.caring"), _trait_label(a, b,&"trait.active")])	
#吟游诗人
	if _has_trait(a, &"trait.bard") or _has_trait(b, &"trait.bard"):
		delta += 0.3
		_add_synergy_event(report, "不管怎么说，作为吟游诗人的%s确实用音乐鼓舞了士气。" % [
		(a if _has_trait(a, &"trait.bard") else b).display_name])
#第四面墙
	if _has_trait(a, &"trait.fourth_wall") or _has_trait(b, &"trait.fourth_wall"):
		delta -= 0.2
		_add_synergy_event(report, "%s一直在念叨些奇奇怪怪的东西，搞得大家精神状态都很糟糕。" % [
		(a if _has_trait(a, &"trait.fourth_wall") else b).display_name])
#矮人笑话+矮人
	if _trait_meets_race(a, b, &"trait.dwarf_joke", &"race.st"):
		delta += 20
		_add_synergy_event(report, "%s讲了致死量的矮人笑话，然后被%s记到了仇恨之书里。" % [
		_trait_label(a, b, &"trait.dwarf_joke"), _race_label(a, b, &"race.st")])
	
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


## 「这一对里那位 slayer」的名字（播报用）。两人都带就报先找到的那个 ——
## 这一对只结算一次，所以也只需要一个名字。
static func _slayer_label(a: CandidateResource, b: CandidateResource, monster_id: StringName) -> String:
	var bare := String(monster_id).trim_prefix("monster.")
	var trait_id := StringName("trait.%s_slayer" % bare)
	if _has_trait(a, trait_id):
		return _trait_name(a, trait_id)
	if _has_trait(b, trait_id):
		return _trait_name(b, trait_id)
	return String(trait_id)


## 魔物的显示名：优先取事件数据里的 event_name（"史莱姆出没"），没有就用 id。
## ⚠️ 不读 MonsterDef —— data/monsters/ 还不存在。
## ⚠️ 表键是单数 &"event"（理由见 DataDB.get_event 的注释），别写回 &"events"。
static func _monster_name(monster_id: StringName) -> String:
	for event_id in DataDB.get_ids(&"event"):
		var event := DataDB.get_event(event_id)
		if event != null and event.id == monster_id:
			var label := String(event.event_name).strip_edges()
			if not label.is_empty():
				return label
	return String(monster_id)


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
