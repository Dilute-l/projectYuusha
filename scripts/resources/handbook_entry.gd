class_name HandbookEntry
extends Resource

## 手册条目。data/handbook/ —— 玩家判断谎言的知识依据。
## 承担两件事：给出魔物弱点，同时给出常识基线
## （例如「初级剑士不可能单人讨伐食人魔」），让撒谎能被推理而不是靠猜。

## 命名空间化 ID，例如 monster.ogre / skill.sword_basic
@export var id: StringName

## 分类，例如 monster / skill / rule
@export var category: StringName

@export var title: String

## 正文，支持 BBCode
@export_multiline var body: String = ""

## 解锁条件，例如 "day >= 3" / "monster.ogre 已出现"
@export var unlock_condition: String = ""

## 供 handbook_overlay.tscn 按关键词检索
@export var keywords: Array[StringName] = []
