class_name RaceDef
extends Resource

## 种族定义。data/races/ 下的 .tres 实例：人类 / 精灵 / 矮人 / 兽人 …
##
## 注意：ARCHITECTURE.md §3.3 未列出 RaceDef 的字段，
## 此处只落地身份信息，机制相关字段待设计确认后再补。

## 命名空间化 ID，例如 race.human
@export var id: StringName

@export var display_name: String

## 简历 / 手册中展示的种族描述（支持 BBCode）
@export_multiline var description: String = ""
