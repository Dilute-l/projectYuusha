class_name HiddenProfile
extends Resource

##这里是柳絮
##这一整个东西我觉得它写的都有那么一点问题，之后考虑把它词条化吧。

## 候选人隐藏属性。UI 永不直接显示，玩家只通过面试与战报间接感知。
##
## 注意：ARCHITECTURE.md §3.1 中本段被注释包裹，并标注「以下一段需要修正，
## 根据游戏具体设计」。因此下列字段集尚未定稿，先按文档表格落地，待确认。

## 诚实度 -1..1，决定回答时的说谎概率与破绽多少
@export_range(-1.0, 1.0, 0.01) var honesty: float = 0.0

## 真实技能值：skill_id -> 0..100。
## 与 CandidateResource.skill_levels（自称值）的差额 = 谎言严重程度
@export var true_skills: Dictionary = {}

## 性格内核，影响战报事件触发与相性计算
@export_range(0.0, 1.0, 0.01) var courage: float = 0.5
@export_range(0.0, 1.0, 0.01) var loyalty: float = 0.5
@export_range(0.0, 1.0, 0.01) var teamwork: float = 0.5
@export_range(0.0, 1.0, 0.01) var ego: float = 0.5
@export_range(0.0, 1.0, 0.01) var greed: float = 0.5

## 追问容忍度：追问过度会翻脸、拒答，甚至当场退赛
@export_range(0.0, 1.0, 0.01) var patience: float = 0.5

## 运气修正：极端战报的开关
@export_range(-1.0, 1.0, 0.01) var luck: float = 0.0
