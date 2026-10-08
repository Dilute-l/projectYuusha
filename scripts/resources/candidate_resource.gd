class_name CandidateResource
extends Resource

## 候选人数据模型（ARCHITECTURE.md §3.1）。
## 只定义数据结构，不含规则逻辑。
##
## 每天出场的候选人在 data/ 里直接写死（DayConfig.candidates），不再由生成器随机拼装。

## 命名空间化 ID，例如 candidate.c_0001
@export var id: StringName

@export var display_name: String

## 三项属性（玩家可见，作为对照简历描述的判断依据）
@export var strength: int = 0        # 力量
@export var intelligence: int = 0    # 智力
@export var wisdom: int = 0          # 感知

## 等级，与职业共同构成「常理上限」（手册常识的锚点）
@export var level: int = 1

## 职业
@export var job: JobDef

## 特质（list，可含多项，也可为空）；相性计算的输入
@export var traits: Array[TraitDef] = []

## 简历：若干条目，每条 = 一句描述 + 追问问题 + 追问回答（见 ResumeEntry）
@export var resume: Array[ResumeEntry] = []

## 简历抬头：纸面上半那一段字，**整段就是一个字符串**，直接写在这里。
##
## 版面（怎么分行、字段顺序、要不要带属性、加不加一句花腔）全由这段字自己说了算，
## 运行时**不做任何拼接**，也不从 strength / job / traits 那些字段生成 ——
## 那些字段是给玩法用的数值，抬头是给人看的文案，两者故意不联动。
## 想让人物写得更随意一点（比如藏一个谎言），改这一栏就行。
@export_multiline var resume_header: String = ""

## 立绘（可选，UI 用）
@export var portrait: Texture2D

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

## 种族，对应 assets/art/portrait/{race}_body_phd.png 的前缀（hu / el / st）
@export var portrait_race: StringName = &"hu"

## 眼睛差分编号 1..3（仅 hu / el 使用，st 忽略）
@export var portrait_eye: int = 1

## 头发差分编号 1..3（仅 hu / el 使用，st 忽略）
@export var portrait_hair: int = 1

## 嘴巴差分编号 1..3（仅 hu / el 使用，st 忽略）
@export var portrait_mouth: int = 1

## 帽子差分编号 1..3（仅 st 使用，其余种族忽略）
@export var portrait_hat: int = 1
