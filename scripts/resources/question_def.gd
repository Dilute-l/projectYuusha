class_name QuestionDef
extends Resource

## 追问问题库。data/questions/ 按主题分类。

## 命名空间化 ID，例如 question.ogre_count
@export var id: StringName

## 问题本体，显示在追问选项里
@export var display_name: String

## 主题。复用 ClaimResource.Topic，保证「简历主题」与「追问主题」是同一套分类
@export var topic: ClaimResource.Topic = ClaimResource.Topic.EXPERIENCE

## 从第几天起可追问
@export var min_day: int = 1

## 施加的追问压力。配合 HiddenProfile.patience，超限会翻脸 / 拒答 / 退赛
@export_range(0.0, 1.0, 0.01) var pressure: float = 0.0

## 前置技能门槛（ID 命名空间：skill.xxx）。留空 = 无门槛。
## 注：文档字段名写作 requires_skill（单数），此处按可挂多个前置技能实现。
@export var requires_skill: Array[StringName] = []
