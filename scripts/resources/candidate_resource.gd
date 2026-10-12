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
