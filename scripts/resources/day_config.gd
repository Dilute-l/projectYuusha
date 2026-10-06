class_name DayConfig
extends Resource

## 每一天的规则与教程进度。data/days/day_01.tres … day_10.tres
## candidate_generator.gd 依据本配置 + RngService 一次性生成当日全部候选人。

## 第几天，1..GameConfig.TOTAL_DAYS
@export var day_index: int = 1

## 当日候选人数
@export var candidate_count: int = 4

## 队伍名额，挑满即进入 BattleReport
@export var slots: int = 3

## 每位候选人可追问的次数
@export var questions_per_candidate: int = 3

## 当日解锁的追问主题，取值来自 ClaimResource.Topic。
## 注：枚举类型不能用作 Array 类型参数，故为 Array[int]。
@export var unlocked_topics: Array[int] = []

## 当日事件池（DailyEventDef.id）
@export var event_pool: Array[StringName] = []

## 教程进度标识，0 = 本日无教程
@export var tutorial_step: int = 0
