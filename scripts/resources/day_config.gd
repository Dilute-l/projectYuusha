class_name DayConfig
extends Resource

## 每一天的规则（ARCHITECTURE.md §3.4）。data/days/day_01.tres … day_10.tres
## 当日候选人直接写死在本配置里（candidates），不再随机生成。

## 第几天，1..GameConfig.TOTAL_DAYS
@export var day_index: int = 1

## 当日候选人，写死；数组顺序即出场顺序，size() 即当日人数。
## 可直接内嵌 CandidateResource 子资源，也可引用 data/candidates/*.tres。
@export var candidates: Array[CandidateResource] = []

## 队伍名额，挑满即进入 BattleReport
@export var slots: int = 3

## 当日事件池（DailyEventDef.id）
@export var event_pool: Array[StringName] = []

## 教程进度标识，0 = 本日无教程
@export var tutorial_step: int = 0
