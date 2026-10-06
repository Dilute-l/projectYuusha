class_name JobDef
extends Resource

## 职业定义。data/jobs/ —— 剑士、法师、牧师 …

## 命名空间化 ID，例如 job.sword
@export var id: StringName

##展示在简历上的职业名称
@export var display_name: String

## 技能树：技能 ID 列表（ID 命名空间：skill.xxx）。
## 注：文档只写 skill_tree，未定层级；先按平铺列表落地，需要分阶时再改为嵌套结构。
@export var skill_tree: Array[StringName] = []

## 属性画像：属性名 -> 基准值
@export var stat_profile: Dictionary = {}

## 克制标签，用于针对当日魔物做适配判定
@export var counter_tags: Array[StringName] = []

@export_multiline var description: String = ""
