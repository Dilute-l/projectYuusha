class_name BattleReport
extends Resource

## 某一天的战报。battle_report.tscn 用它做演出：逐条事件播报、分数。
##
## 车夫对话**不在**这个资源里 —— 它走 data/dialogue.json 的 `day<N>_driver` id，
## 由 battle_report.tscn 自己按当天取（见 scenes/day/battle_report.gd）。
##
## 注意：ARCHITECTURE.md §3.3 未列出 BattleReport 的字段。
## 此处按 §4 场景职责与 §6.5 / §6.6 的产出做最小实现，待演出需求明确后补充。

## 第几天的战报
@export var day_index: int = 1

## 出战成员（CandidateResource.id）
@export var member_ids: Array[StringName] = []

## 当日魔物（MonsterDef.id，ID 命名空间：monster.ogre）
@export var monster_id: StringName

## 逐条事件播报，由 narrative_engine.gd 依 NarrativeRule 生成。
## 每条形如 { "text": String, "rule_id": StringName, "priority": int }
@export var events: Array[Dictionary] = []

## 当日分数 = `true_power × multiplier`（见 combat_resolver.gd::resolve）。
##
## ⚠️ 是 **float** 不是 int：羁绊是**乘数**（`synergyMultiplier` 返回 1.05 / 0.7 这种），
## true_power 乘上去必然带小数。用 int 会在赋值时静默截断，倍率的效果就丢了。
@export var day_score: float = 0.0

## 分数明细，对应 day_scored 信号的 breakdown。
## { "true_power": float, "synergy": float, "multiplier": float,
##   "lie_penalty": int, "event_bonus": int, "luck": int }
##
## synergy = day_score − true_power（倍率带来的差值），所以
## 「true_power + synergy == day_score」这条恒等式仍然成立，下游不必改。
@export var breakdown: Dictionary = {}
