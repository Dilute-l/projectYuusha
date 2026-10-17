class_name CandidateResource
extends Resource

## 候选人数据模型（ARCHITECTURE.md §3.1）。
## 只定义数据结构，不含规则逻辑。
##
## 每天出场的候选人在 data/ 里直接写死（DayConfig.candidates），不再由生成器随机拼装。

## 命名空间化 ID，例如 candidate.c_0001
@export var id: StringName

@export var display_name: String

## 等级：这位冒险者**真正的**水平（与职业共同构成「常理上限」，是手册常识那一侧的锚点）。
##
## ⚠️ **隐藏属性 —— 不上简历纸**。简历上那三围是「他自己写的」，等级不写给他：
## 玩家看到的只有属性 / 职业 / 特质与手册，等级得靠追问和常理去估。
## 所以它**不在 true_attributes 那套机制里**（那套管的是「纸面上写的数 vs 实际数」，
## 而等级压根没有纸面上那一半 —— 别顺手把它塞进那个字典）。
##
## 用途：**个人战力就是拿它乘的** —— `主属性 × 等级 × 10`（combat_resolver.gd::powerCaculation）；
## 叙事规则的条件也读它（`data/narrative/*.tres`，见 scripts/resources/narrative_rule.gd）。
## 默认 1：**老 .tres 里没有这一行 = 一级**，现有 26 份数据一行都不用改
## （等级 1 时战力与「没加等级」之前一模一样）。
@export var level: int = 1

## 三项属性 —— **简历上写的那三个数**（玩家在纸上看到的就是它，
## 也是他自称的身板）。真正进结算的是 true_attributes，见下。
@export var strength: int = 0        # 力量
@export var intelligence: int = 0    # 智力
@export var wisdom: int = 0          # 感知

## 真实属性：**这具身板实际有多少**（取值一律走 true_attribute / true_strength 这组助手）。
##
## 有了它，简历上写的和实际的就是两回事：`strength` 是「他自己写在纸上的」，
## 这里是他「真有」的。玩家看不到这一份 —— 他只能靠追问、手册常识和常理去猜。
##
## 格式：{ "strength": int, "intelligence": int, "wisdom": int }
##   · 键就是上面那三个字段名（String / StringName 都认，`&"strength"` 一样查得到）；
##   · **只写要改的那几项** —— 只在力量上吹了牛就写 { "strength": 4 }，
##     另两项没写，就照简历走；
##   · 空字典（默认）= 一个字都没吹，实际值就是简历值。
##
## .tres 里的写法（**没吹牛就一行都不写**，和 resume_stamp 同一条规矩 ——
## 默认值本来也是 {}，写个空字典进去只会让 diff 变脏）：
##   true_attributes = { "strength": 4, "wisdom": 12 }
##
## 谁负责哪一头：纸上的字读 strength（resume.gd），结算读 true_strength()
## （combat_resolver.gd）。判断真伪的活不在本文件里 —— 本文件只提供「两个数都拿得到」。
@export var true_attributes: Dictionary = {}

##种族
@export var race: RaceDef

## 职业
@export var job: JobDef

## 性别。**单个值**（"男" / "女"）—— 简历上那一栏显示的就是它。
## （曾经写成 Array[StringName] = ["男","女"]，那是笔误：所有候选人显示出来会一模一样。）
@export var gender: StringName = &"男"

## 年龄
@export var age: int = 2

## 特质（list，可含多项，也可为空）；相性计算的输入
@export var traits: Array[TraitDef] = []

## 个人履历与奖项（简历左下的「个人履历与奖项」那一栏）。每条一个词条、可追问。
@export var experience: Array[ResumeEntry] = []

## 专长（简历左下的「专长」那一栏）。每条一个词条、可追问。
@export var skill: Array[ResumeEntry] = []

## 组队宣言：简历右下那一栏，写一句他想跟队伍说的话。
##
## 和 experience / skill 不同，它是**一整段自由文本**，不挂追问 ——
## 那两栏是「可以被质疑的履历」，这一栏是「他自己喊的口号」，性质不一样。
@export_multiline var team_declaration: String = ""

##作为最终在战报上呈现出的对这个人的评价
@export var judgment: String = ""

## 造假程度：**不上任何界面**，只作为后续机制（还没做）的参考值。
##
## 0 = 没造假，1~3 = 一 / 二 / 三级。这批数据照着导入时文件夹名里的 `fake0`~`fake3`
## 标注填（`candidates_tmp/*/c_XXXX_ct fake1 …`），所以和那几个 `fakeN` 特质同源 ——
## 但两者**互不替代**：特质参与相性计算，这个字段不参与。
##
## ⚠️ 现在**没有任何代码读它**（战力、相性、简历纸面都不读）。留着是为了以后真要
## 「按造假程度算风险 / 举报 / 派系反应」时，不用回头再翻一遍文件名。
## 默认 0：老 .tres 里没有这一行 = 没造假。
@export var fake_level: int = 0

## 简历上**显示**的种族名。
##
## 空 = 照旧用 `race.display_name`；非空 = 简历那一栏就印这一串（例如 race 是 `elf`
## 的皮尔莉，纸面上可以印成「仙灵」）。**只换纸面那一个字**，不动 `race` 本身 ——
## 相性、叙事规则、`_is_race()` 那些判定读的仍然是 `race`，所以改这里不会顺手改掉玩法。
## 立绘另有一套 `portrait_race`，也不受影响。取值走 `shown_race_name()`。
## （要改这两个字段：编辑器 tools/candidate_generator.html；排班预览里也会显示。）
@export var display_race: String = ""

## 立绘（可选，UI 用）
@export var portrait: Texture2D

## 简历上那枚印章（resume.tscn 的 `ResumeStamp`）。
##
## **一张贴图同时决定两件事**：
##   · 留空（null）→ 这张简历**不盖章**；
##   · 填一张图   → 就在纸上盖这枚章（图就是 assets/art/interview/resume/ 下的那张）。
##
## 为什么不留一个「要不要盖章」的 bool：章是「有没有图」这件事本身 ——
## 两个字段的话必然会出现 `show = true` 却没图的组合，还得多写一条兜底。
##
## 图的**位置 / 缩放**不在这里：那是版面，写在 resume.tscn 上（换图不用动它）。
## 谁把谁盖在纸上由 `scenes/day/interview/resume/resume.gd::_apply_stamp()` 落地。
@export var resume_stamp: Texture2D

# ---------------------------------------------------------------------------
# 立绘部件（面试者那身「拼装立绘」的配方，见 scenes/day/interview/interviewee.gd）
# ---------------------------------------------------------------------------
#
# 立绘不是一整张图，而是按部位拼的：种族决定身体，眼睛 / 头发 / 嘴巴（hu / el）
# 或帽子（st）各挑一张差分。这里就是这套配方的数据落点 —— 以前是 interview.gd
# 里随机摇的调试段，现在由候选人的 .tres 写死。
#
# 取值直接对应 assets/art/portrait/ 的文件名：
#   portrait_race = &"hu" → hu_body_phd.png
#   portrait_eye  = 2     → tall_eye_phd2.png

## 种族，对应 assets/art/portrait/{race}_body.png 的前缀（hu / el / st）
@export var portrait_race: StringName = &"hu"

## 部件编号一律是**四位数字**：<组><组内编号>（101 就是文件名里的 "0101"）。
##
##   eye / hair   组 01 = 男、02 = 女、99 = 特殊     仅 hu / el 使用，st 忽略
##   mouth        组 01 = 通用、99 = 特殊            所有种族共用
##   hat          组 01 = 矮人、02 = 其他、99 = 特殊
##
## 占位数据一律 101。完整规则见 scripts/util/portrait_composer.gd。
@export var portrait_eye: int = 101

@export var portrait_hair: int = 101

@export var portrait_mouth: int = 101

## 帽子：**可选件**。0 = 不戴帽子（除矮人外默认如此）；
## 矮人填 101（= hat_0101）就戴上，换帽子只改后两位。
@export var portrait_hat: int = 0

# ---------------------------------------------------------------------------
# 属性取值（简历值 vs 实际值）
# ---------------------------------------------------------------------------
#
# 「纸上写的」与「真有」怎么区分，**只在这几个函数里定** —— 别处一律不许自己写
# `true_attributes.get(...)`：那样一来「没写这项 = 照简历走」这条兜底就会散到各处，
# 哪天改了规则必然漏掉几处（旧版 HiddenProfile 就是这么烂掉的）。

## 三项属性的键名。也是 true_attributes 的键，取值助手都收它。
const ATTRIBUTE_KEYS: Array[StringName] = [&"strength", &"intelligence", &"wisdom"]


## 简历上写的那一项（玩家在纸上看到的就是它）。
## 不认识键时返回 0 并告警 —— 静默返回 0 会让人以为「他就是 0 力量」。
func claimed_attribute(key: StringName) -> int:
	match StringName(key):
		&"strength":
			return strength
		&"intelligence":
			return intelligence
		&"wisdom":
			return wisdom
	push_warning("[CandidateResource] 没有这个属性：%s" % key)
	return 0


## 实际生效的那一项。**没写 / 写得不成数 = 照简历走**（兼容老格式：老 .tres 里
## 根本没有 true_attributes，那就是「实际 = 简历」）。
func true_attribute(key: StringName) -> int:
	var raw: Variant = true_attributes.get(StringName(key), null)
	if raw is int or raw is float:
		return int(raw)
	if raw != null:
		# 填了个「不是数」的东西：宁可退回简历值，也不要拿一个莫名其妙的数去结算
		push_warning("[CandidateResource] true_attributes.%s 不是数字（%s），按简历值算"
				% [key, raw])
	return claimed_attribute(key)


## 实际力量 —— 结算 / 战报读的是这个，不是 `strength`（纸上的那个）
func true_strength() -> int:
	return true_attribute(&"strength")


## 实际智力
func true_intelligence() -> int:
	return true_attribute(&"intelligence")


## 实际感知
func true_wisdom() -> int:
	return true_attribute(&"wisdom")


# ---------------------------------------------------------------------------
# 简历上显示的名字（纸面 ≠ 玩法）
# ---------------------------------------------------------------------------


## 简历上该印的种族名：`display_race` 非空就优先用它，否则回退 `race.display_name`。
##
## **只给 UI 用**（resume.gd）。玩法一侧请照旧读 `race`（相性 / 叙事规则 / _is_race），
## 别拿它去判种族 —— 否则「显示成仙灵」会悄悄变成「真的按仙灵算」。
func shown_race_name() -> String:
	var custom: String = display_race.strip_edges()
	if not custom.is_empty():
		return custom
	if race == null:
		return ""
	return race.display_name
