class_name NarrativeRule
extends Resource

## 战报叙事规则。data/narrative/
## combat_resolver.gd 算出结果，narrative_engine.gd 用本规则把结果翻译成人话。
## 规则按 priority 排序、weight 加权抽取，避免同一天重复同一模板。

## 条件表达式，例如：
## "member.level < 3 and member.strength + member.intelligence + member.wisdom < 30"
##
## `member` 是一位 CandidateResource（字段名直接当属性用）：
##   · `member.strength` 那一组是**简历上写的**数，`member.true_strength()` 那组才是实际值（§3.1）；
##   · `member.level`（等级）是**隐藏属性** —— 玩家在简历上看不到它，
##     所以「这人的等级配不上他吹的履历」这类条件只能在这里判，别指望纸上写着。
@export_multiline var when: String = ""

## 占位符文案，例如：
## "{actor} 在简历上说谎了，是个货真价实的水货，他把大家携带的装备全都搞坏了。"
@export_multiline var template: String = ""

@export var weight: float = 1.0

@export var priority: int = 0
