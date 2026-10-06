class_name DailyEventDef
extends Resource

## 每日特殊事件池。data/events/
## 由记者报道今日魔物与特殊规则（DayBriefing → SpecialEvent 阶段）。

## 命名空间化 ID，例如 event.ogre_raid
@export var id: StringName

## 当日可能出现的事件名称
@export var event_name: StringName

## 记者播报文案
@export_multiline var announce_text: String = ""

## 特殊规则，每项形如 { "key": StringName, "value": Variant }
@export var bonus_rules: Array[Dictionary] = []
