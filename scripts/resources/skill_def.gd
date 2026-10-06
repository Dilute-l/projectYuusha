class_name SkillDef
extends Resource

## 技能定义。data/skills/ 按职业分组：剑术、弓箭、火球、治疗、驱魔 …

## 伤害类型
enum DamageType { MELEE, RANGED, MAGIC }

## 命名空间化 ID，例如 skill.fireball
@export var id: StringName

@export var display_name: String

## 属性适配与克制判定的依据
@export var damage_type: DamageType = DamageType.MELEE

## 标签：火 / 神圣 / 范围 …
@export var tags: Array[StringName] = []

## 手册条目里对该技能的说明（支持 BBCode），
## 也是「初级剑士不可能单人讨伐食人魔」这类常识基线的依据
@export_multiline var description: String = ""
