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

## 当日**最低得分要求**：战报结算完，若「今日分数 < score_request」→ 当天判负，
## 直接进坏结局（播 `Ending_Bad` 后回主界面）。
##
## ⚠️ **0 = 没有要求**（老 .tres 里没这一行就是这个值，行为与以前一致）：
##    那样永远判不死，适合调试 / 前几天的教学日。
##    现在 10 天都填了 1（临时值）—— 只要当天不是 0 分就过。
@export var score_request: int = 0

## 教程进度标识，0 = 本日无教程
@export var tutorial_step: int = 0
