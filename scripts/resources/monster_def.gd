class_name MonsterDef
extends Resource

## 魔物图鉴数据。data/monsters/

## 命名空间化 ID，例如 monster.ogre
@export var id: StringName

@export var display_name: String

## 特点标签：群居、重甲、再生、畏光 …
@export var tags: Array[StringName] = []

## 弱点：技能标签或属性
@export var weaknesses: Array[StringName] = []

## 克制倍率：key 为技能标签 / 技能 ID，value 为倍率
@export var counter_multipliers: Dictionary = {}

## 图鉴 / 手册正文（支持 BBCode）
@export_multiline var description: String = ""
