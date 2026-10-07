class_name JobDef
extends Resource

## 职业定义（ARCHITECTURE.md §3.3）。data/jobs/ —— 剑士、法师、牧师 …

## 命名空间化 ID，例如 job.sword
@export var id: StringName

## 展示在简历上的职业名称
@export var display_name: String

## 简历 / 手册里展示的职业描述（支持 BBCode）
@export_multiline var description: String = ""
