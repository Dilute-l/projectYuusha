class_name NarrativeRule
extends Resource

## 战报叙事规则。data/narrative/
## combat_resolver.gd 算出结果，narrative_engine.gd 用本规则把结果翻译成人话。
## 规则按 priority 排序、weight 加权抽取，避免同一天重复同一模板。

## 条件表达式，例如：
## "member.honesty < -0.3 and member.true_power < member.claimed_power * 0.5"
@export_multiline var when: String = ""

## 占位符文案，例如：
## "{actor} 在简历上说谎了，是个货真价实的水货，他把大家携带的装备全都搞坏了。"
@export_multiline var template: String = ""

@export var weight: float = 1.0

@export var priority: int = 0
