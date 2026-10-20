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
		# `score` = 这个人**自身**的战力（§6.5 的「个人战力」），战报上就播成 `+xxx`。
		# 一条事件自带自己的分数，而不是让表现层回头去算 —— 那是 core 的活，
		# 而且表现层重算一遍就等于有了第二个真相，两边一旦分岔就没人说得清。
		report.events.append({
			"text": text,
			"actor": member_id,
			"rule_id": rule_id,
			"priority": 0,
			"score": powerCaculation(member),
		})

	# ── 循环外：全队合计 ──
	# **羁绊是乘数，不是加数**：它作用在 total 上，把整队战力放大或缩小一个倍率。
	#
	#   multiplier = 队伍羁绊倍率（1.0 = 无影响，见 synergyMultiplier）
	#             = 队内两两相性（_pair_synergy 的 delta 当「倍率增量」逐对相乘）
	#             × 当日事件（每种怪物一次：有 slayer ×(1+加成)，没有 ×(1−惩罚)）
	#             × 整队同职业（全员同一个 job → ×SAME_JOB_PENALTY，一队只罚一次）
	#
	#   day_score  = true_power × multiplier
	#   breakdown.synergy = 倍率带来的差值（= day_score − true_power），
	#                       所以「true_power + synergy == day_score」这条仍然成立，
	#                       下游（战报明细 / 自检）不用改 —— 同职业罚的那一半也含在这里面，
	#                       不需要为它另开一个 breakdown 键。
	var true_power := finalPowerCaculation(member_ids)
	var multiplier := synergyMultiplier(day_index, member_ids, report)
	# 分数收敛到两位小数：`420 × 1.1` 的浮点尾巴（462.0000000000001）会一路传进
	# 存档、累计分和界面。两位小数足够表达所有倍率（±0.05 / ±0.3）。
	var score := snappedf(true_power * multiplier, 0.01)
	report.day_score = score
	report.breakdown = {
		"true_power": true_power,
		"synergy": snappedf(score - true_power, 0.01),
		"multiplier": snappedf(multiplier, 0.0001),
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
			tempower += member.true_strength() * (5+member.level) * 10
		&"job.mage":
			tempower += member.true_intelligence() * (5+member.level) * 10
		&"job.cleric":
			tempower += member.true_wisdom() * (5+member.level) * 10
	match member.fake_level:
		0:
			tempower *= 1
		1:
			tempower *= 0.8
		2:
			tempower *= 0.5
		3:
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
# 播报里点名的是**队员的名字**，不是特质名：data/traits/*.tres 的 display_name 现在全是
# 占位（"PLACEHOLDER TRAIT (...)"），播这种名字没人看得懂。队员名是真名。
# 等特质定稿、想把播报换回特质名时，把 _rule_names() / _trait_owner_name() 换成 _trait_name()
# 即可 —— 下面那些 if 行一行都不用动。
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

## 整队**清一色同一个职业**时，总分乘多少（0.5 = 砍一半）。
##
## 设计意图：职业就是「这一队里谁干什么活」—— 战士扛线、法师输出、牧师治伤。
## 三个人全是战士，等于既没人施法也没人治疗，路上只能各自抡剑 —— 结构单一是**整队**
## 的问题，所以它和当日事件一样按「一队一次」结算，不随人数 / 对数叠加。
##
## ⚠️ 判的是「最后选出的那一队」（resolve() 收到的 member_ids），不是面试时录用过谁；
## ⚠️ **两个人以上才判**：一个人没有「结构」可谈单一，而第 1 天 data/days/day_01.tres
##    就只有一个候选人（slots = 2），独苗队天天被砍一半不是这条规则想表达的事。
const SAME_JOB_PENALTY := 0.5

## 整队同职业时，战报上那句话 —— **一个职业一句，不许共用通用文案**。
##
## 为什么按职业分开写：三支「一群人干同一件事」的队，缺的东西根本不是一回事 ——
## 全战士缺的是法术和治疗，全法师缺的是前排，全牧师缺的是把敌人打死的那只手。
## 一句「没人会干别的活儿」把三件事说成了一件，玩家看不出自己错在哪。
##
## 为什么文案写在代码里、而不是 JobDef 上加个字段：和 _pair_synergy() 那几十行同一条规矩 ——
## 「加一条规则 = 一行判断 + 一行记分 + 一行播报，不碰任何资源」。这句是**玩法口吻**，
## 不属于简历纸面（那边印的是 JobDef.display_name），两者不该住在一起。
##
## 键是 `job.id`（data/jobs/*.tres 里的 id：job.fighter / job.mage / job.cleric）。
## ★ 加新职业就往这里加一行；漏了也不会崩 —— 会退回 SAME_JOB_FALLBACK_LINE ★
const SAME_JOB_LINES: Dictionary = {
	&"job.fighter": "一整队战士拖着重甲，被远程的敌人溜了一天。",
	&"job.mage": "几个法师根本没有安全的施法环境，最后只能谁跑得慢谁来冒充前排。",
	&"job.cleric": "一队牧师面面相觑，我打输出，真的假的？",
}

## 表里没有的职业（以后新加的第 4 个）用这一句兜底。
## 它是**兜底，不是通用文案**：三种既有职业各说各话，走不到这里。
## `%s` 填职业名 —— 宁可留一句平淡的，也别在战报上留空 / 留个 `job.xxx`。
const SAME_JOB_FALLBACK_LINE := "一整队全是%s，没人会干别的活儿，一路上只能见招拆招。"


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
## 组成 = 队内两两相性 × 队外当日事件 × 整队职业结构：
##   · 队内：每种相性规则给 _pair_synergy 一个 delta，逐对相乘 —— (1 + delta)
##           正 delta = 放大，负 delta = 缩小。没命中任何规则的一对返回 0.0 → ×1.0。
##   · 队外：**每种当日怪物只判一次**（不看队里有几个人、也不看几对）：
##           队里有人带 `trait.<魔物>_slayer` → ×(1 + EVENT_SLAYER_BONUS)
##           没人带                            → ×(1 − EVENT_MISSING_SLAYER_PENALTY)
##           为什么按「怪物」而不是按「对」：按对扣分会让「队里人多」变成一种惩罚
##           （3 人队扣 3 次），而设计意图是「今天要打的东西你熟不熟」——这是一件事。
##   · 整队：**全员同一个职业**（`same_job_id` 非空）→ ×SAME_JOB_PENALTY（0.5）。
##           同样「一队一次」：三个人都是战士只砍一刀，不是砍两刀。
##
## report 不为 null 时，每条命中的规则往战报里追加一条播报。
static func synergyMultiplier(day_index: int, member_ids: Array[StringName],
		report: BattleReport = null) -> float:
	var multiplier: float = 1.0
	for i in member_ids.size():
		# 吟游诗人
		var a := DataDB.get_candidate(member_ids[i])
		if _has_trait(a, &"trait.bard"):
			multiplier *= 1.3
			_add_synergy_event(report, "不管怎么说，作为吟游诗人的%s确实用音乐鼓舞了士气。" %
				_member_name(a), &"synergy", 1.3)

		# 第四面墙
		if _has_trait(a, &"trait.fourth_wall"):
			multiplier *= 0.8
			_add_synergy_event(report, "%s一直在念叨些奇奇怪怪的东西，搞得大家精神状态都很糟糕。" %
					_member_name(a), &"synergy", 0.8)

		for j in range(i + 1, member_ids.size()):
			var b := DataDB.get_candidate(member_ids[j])
			if a == null or b == null:
				push_warning("[CombatResolver] 相性配对跳过：%s / %s 查不到" % [
					member_ids[i], member_ids[j]])
				continue
			multiplier *= 1.0 + _pair_synergy(a, b, report)

	# ── 整队：清一色同一个职业 ──
	# 这是**队伍结构**上的判定，所以放在两两配对之外、也放在当日事件之前：
	# 它算的是「这一队是怎么搭起来的」，而不是「谁和谁撞了哪种特质」。
	# 只在全员同职业时命中一次；队员查不到 / 没填职业 → same_job_id 返回 &""，不加不减。
	# 播报按职业各说各话（SAME_JOB_LINES），同一个 id 只会走同一条文案。
	var same_job := same_job_id(member_ids)
	if same_job != &"":
		multiplier *= SAME_JOB_PENALTY
		_add_synergy_event(report, _same_job_line(same_job), &"same_job", SAME_JOB_PENALTY)

	# 队外：每种怪物一次
	for monster_id in event_monsters(day_index):
		var slayer := _any_slayer(member_ids, monster_id)
		if not slayer.is_empty():
			multiplier *= 1.0 + EVENT_SLAYER_BONUS
			_add_synergy_event(report, "旅途上遇到了很多%s，%s轻松的处理掉了这些敌人。" % [
				_monster_name(monster_id), _names_of(slayer)], &"synergy", 1.0 + EVENT_SLAYER_BONUS)
		else:
			multiplier *= 1.0 - EVENT_MISSING_SLAYER_PENALTY
			_add_synergy_event(report, "今日%s大量出没，可是队里没人知道该怎么对付它们。" % [
				_monster_name(monster_id)], &"synergy", 1.0 - EVENT_MISSING_SLAYER_PENALTY)

	return multiplier


## 这一队全员共有的那个职业 id；**`&""` = 不算「同一个职业」**。
##
## 判定只做「是不是同一个」这一件事，返回 id 是为了让播报能念出职业名（`_job_name`）。
##
## 返回空串的三种情况（都不扣分）：
##   · 队里不到两个人 —— 一个人没有「结构」可谈单一（独苗队不该天天被砍一半）；
##   · 有人查不到 / 没填 job —— 数据残缺时宁可放过，也不要拿半个队去砍分数；
##   · 职业确实不止一种 —— 这就是正常的混编队伍。
##
## ⚠️ 判的是**最后选出的那一队**（resolve() 收到的 member_ids），面试阶段录用过谁不算数。
static func same_job_id(member_ids: Array[StringName]) -> StringName:
	if member_ids.size() < 2:
		return &""
	var job_id: StringName = &""
	for member_id in member_ids:
		var member := DataDB.get_candidate(member_id)
		if member == null or member.job == null or member.job.id == &"":
			return &""
		if job_id == &"":
			job_id = member.job.id
		elif member.job.id != job_id:
			return &""
	return job_id


## 这一队是不是**清一色同一个职业**（读的东西见 same_job_id）。
## 单独留一个 bool 版本，是为了让「要不要罚」在调用处读起来是一句话，而不是 `!= &""`。
static func all_same_job(member_ids: Array[StringName]) -> bool:
	return same_job_id(member_ids) != &""


## 战报上那句话 —— 按职业取（SAME_JOB_LINES），表里没有的才走 SAME_JOB_FALLBACK_LINE。
##
## 返回值一定是**能直接播的成品文案**：调用方不再拼职业名，也不该再往里填占位符。
## 专属文案里写死的职业名（「全是战士」）比 `%s` 好读 —— 但兜底那句仍需 %s，
## 所以这里用 `contains("%s")` 判一下，别把占位符原样播出去。
static func _same_job_line(job_id: StringName) -> String:
	var raw: Variant = SAME_JOB_LINES.get(job_id, SAME_JOB_FALLBACK_LINE)
	var line := String(raw)
	if line.contains("%s"):
		return line % _job_name(job_id)
	return line


## 职业的显示名（data/jobs/*.tres 的 `display_name`，例：「战士」「法师」「牧师」）。
## 空名退回 id 本体，并把 `job.` 命名空间前缀去掉 —— 播报里至少别出现 `job.fighter`。
static func _job_name(job_id: StringName) -> String:
	var job := DataDB.get_job(job_id)
	if job != null:
		var label := String(job.display_name).strip_edges()
		if not label.is_empty():
			return label
	return String(job_id).trim_prefix("job.")


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
	# 每条规则都记一个 `before`：这一对**可能同时命中好几条**，而结算是
	# 「(1 + Δ) 整体乘一次」，不是每条形如 x1.2 x0.9 那样各乘一次。
	# 所以播报上的倍数必须取「这一步真正涨落的那一截」——
	# 见 _pair_step_factor()，不这么算的话纸上乘出来的数会跟底下跳的数对不上。
	var before: float = 0.0
#傲慢+胆小
	if _both_have_traits(a, b, &"trait.prideful", &"trait.timid"):
		before = delta
		delta -= 0.1
		_add_synergy_event(report, "%s一路上都在压力%s，搞得大家都有点不愉快。" %
				_rule_names(a, b, &"trait.prideful", &"trait.timid"),
				&"synergy", _pair_step_factor(before, delta))
#积极+积极
	if _both_have_traits(a, b, &"trait.active", &"trait.active"):
		before = delta
		delta += 0.2
		_add_synergy_event(report, "%s和%s把队伍的气氛调动了起来，所有人都很有干劲。" %
				_rule_names(a, b, &"trait.active", &"trait.active"),
				&"synergy", _pair_step_factor(before, delta))
#体贴+胆小
	if _both_have_traits(a, b, &"trait.caring", &"trait.timid"):
		before = delta
		delta += 0.1
		_add_synergy_event(report, "虽然%s有点软脚了，但%s就像妈妈一样把他照顾的很好。" %
				_rule_names(a, b, &"trait.timid", &"trait.caring"),
				&"synergy", _pair_step_factor(before, delta))
#傲慢+粗鲁
	if _both_have_traits(a, b, &"trait.rude", &"trait.prideful"):
		before = delta
		delta -= 0.2
		_add_synergy_event(report, "在%s吹嘘自己的时候，%s诋毁了他一句，俩人差点打了起来。" %
				_rule_names(a, b, &"trait.prideful", &"trait.rude"),
				&"synergy", _pair_step_factor(before, delta))
#傲慢+傲慢
	if _both_have_traits(a, b, &"trait.prideful", &"trait.prideful"):
		before = delta
		delta -= 0.1
		_add_synergy_event(report, "%s和%s都认为自己才是最强的，导致路上他们一直在吵。" %
				_rule_names(a, b, &"trait.prideful", &"trait.prideful"),
				&"synergy", _pair_step_factor(before, delta))
#粗鲁+胆小
	if _both_have_traits(a, b, &"trait.timid", &"trait.rude"):
		before = delta
		delta -= 0.1
		_add_synergy_event(report, "%s的战斗技巧和为人处世都有些暴躁，搞得%s有些害怕。" %
				_rule_names(a, b, &"trait.rude", &"trait.timid"),
				&"synergy", _pair_step_factor(before, delta))
#傲慢+活跃
	if _both_have_traits(a, b, &"trait.active", &"trait.prideful"):
		before = delta
		delta += 0.1
		_add_synergy_event(report, "%s总觉得%s的积极表现是在和自己竞争，然后……他似乎出了更多的力。" %
				_rule_names(a, b, &"trait.prideful", &"trait.active"),
				&"synergy", _pair_step_factor(before, delta))
#积极+体贴
	if _both_have_traits(a, b, &"trait.active", &"trait.caring"):
		before = delta
		delta += 0.1
		_add_synergy_event(report, "%s把有些莽撞的%s照顾得很好。" %
				_rule_names(a, b, &"trait.caring", &"trait.active"),
				&"synergy", _pair_step_factor(before, delta))
#吟游诗人
	# if _has_trait(a, &"trait.bard") or _has_trait(b, &"trait.bard"):
	# 	delta += 0.3
	# 	_add_synergy_event(report, "不管怎么说，作为吟游诗人的%s确实用音乐鼓舞了士气。" %
	# 			_member_name(a if _has_trait(a, &"trait.bard") else b))
#第四面墙
	# if _has_trait(a, &"trait.fourth_wall") or _has_trait(b, &"trait.fourth_wall"):
	# 	delta -= 0.2
	# 	_add_synergy_event(report, "%s一直在念叨些奇奇怪怪的东西，搞得大家精神状态都很糟糕。" %
	# 			_member_name(a if _has_trait(a, &"trait.fourth_wall") else b))
#矮人笑话+矮人
	if _trait_meets_race(a, b, &"trait.dwarf_joke", &"race.st"):
		before = delta
		delta -= 0.2
		_add_synergy_event(report, "%s讲了致死量的矮人笑话，然后被%s记到了仇恨之书里。" % [
				_trait_owner_name(a, b, &"trait.dwarf_joke"), _race_label(a, b, &"race.st")],
				&"synergy", _pair_step_factor(before, delta))

	return delta


## 这一对里「第几条命中的规则」真正乘上去的倍数。
##
## 一对命中两条规则时，真正乘的不是 (1+d1)×(1+d2)，而是 1+(d1+d2)（见 _pair_synergy
## 的 delta 累加 + synergyMultiplier 的 `multiplier *= 1.0 + delta`）。于是第 k 条的
## **有效倍数** = (1 + Σ_{≤k}) / (1 + Σ_{<k})：
##
##   d = +0.2 再 +0.1  →  ×1.2 然后 ×1.0833（合起来正好 ×1.3）
##
## 播报照这个数写，底下总分照这个数乘，最后一定落回 day_score —— 玩家拿纸笔跟着算也不会错。
## 只命中一条规则时（绝大多数情况）它退化回 1 + d，也就是 ×1.2 / ×0.8 这种好读的数。
static func _pair_step_factor(before: float, after: float) -> float:
	var base := 1.0 + before
	if is_zero_approx(base):
		# 理论上到不了（delta 只有 ±0.1 / ±0.2 这种量级）。不要 0 除，退回增量本身。
		return 1.0 + (after - before)
	return (1.0 + after) / base


## 命中的相性往战报里追加一条播报。文本里不放 {actor}：
## 它说的是两位队员之间的特质 / 种族，而不是某一个人的台词。
##
## rule_id 默认是 `synergy`（两两相性 / 当日事件的通用标签）。
## 「整队同职业」那条传自己的 `same_job`，这样以后要按规则分类统计 / 换文案时，
## 不用回头翻文本去猜这条是谁播的。
##
## factor = **这一条真正乘上去的倍数**（1.0 = 不影响）。战报照着它播 `×1.1`，
## 底下的总分也照着它跳 —— 于是「播出来的字」与「跳成那个数的算术」是同一份数据，
## 玩家自己在纸上乘一遍也对得上。
static func _add_synergy_event(report: BattleReport, text: String,
		rule_id: StringName = &"synergy", factor: float = 1.0) -> void:
	if report == null:
		return
	report.events.append({
		"text": text,
		"actor": &"",
		"rule_id": rule_id,
		"priority": 1,
		"factor": snappedf(factor, 0.0001),
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


## 这条规则里「带这个特质的那位」的名字（先在 a 上找，再在 b 上找）。
## ⚠️ 两人都带的规则（积极+积极 / 傲慢+傲慢）不能用它取两次 —— 那会把同一个人念两遍，
##    那种规则请用 _rule_names()。
static func _trait_owner_name(a: CandidateResource, b: CandidateResource, trait_id: StringName) -> String:
	if _has_trait(a, trait_id):
		return _member_name(a)
	if _has_trait(b, trait_id):
		return _member_name(b)
	return String(trait_id)


## 播报里点名的两位当事人：[带 x 的那位, 带 y 的那位]（x / y 允许是同一个特质）。
##
## 取人的顺序和 _both_have_traits() 同源：「a 带 x 且 b 带 y」优先，其次「b 带 x 且 a 带 y」。
## 所以「两人都带 active」那条会播成两个**不同的人**，而不会把同一个名字念两遍。
## 只有规则已命中才会走到这里；万一两条都不成立就退回 a / b —— 播报里不留空白。
static func _rule_names(a: CandidateResource, b: CandidateResource,
		x: StringName, y: StringName) -> Array[String]:
	var first := a
	var second := b
	if not (_has_trait(a, x) and _has_trait(b, y)) and _has_trait(b, x) and _has_trait(a, y):
		first = b
		second = a
	var names: Array[String] = []
	names.append(_member_name(first))
	names.append(_member_name(second))
	return names


## 队员的显示名（播报用）。空名退回 id —— 播报里绝不出现空白。
static func _member_name(member: CandidateResource) -> String:
	if member == null:
		return "某人"
	var label := String(member.display_name).strip_edges()
	return label if not label.is_empty() else String(member.id)


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
