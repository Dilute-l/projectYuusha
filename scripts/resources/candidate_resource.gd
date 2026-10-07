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

## 立绘（可选，UI 用）
@export var portrait: Texture2D
