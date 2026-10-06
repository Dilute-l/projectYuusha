class_name ClaimResource
extends Resource

## 履历主张 —— 说谎机制的载体。
## 简历上的每一条自称内容都是一个 Claim，玩家可以针对当前词条追问。

## 主张主题。简历主题与追问主题共用这一套分类（见 QuestionDef.topic）
enum Topic { JOB, SKILL, EXPERIENCE, PERSONALITY, QUIRK }

@export var topic: Topic = Topic.EXPERIENCE

## 自称内容，例如「我曾单独讨伐过三只食人魔。」
@export_multiline var statement: String = ""

## 是否真实。与 exaggeration 配合：is_true 为 true 时 exaggeration 应为 0
@export var is_true: bool = true

## 0 = 真实，1 = 完全造假，中间值为夸大
@export_range(0.0, 1.0, 0.01) var exaggeration: float = 0.0

## 验证路径：手册条目 / 技能细节 / 数字矛盾
@export var verification: StringName

## 本条主张涉及的技能（ID 命名空间：skill.xxx）
@export var related_skill_ids: Array[StringName] = []

## 被追问时的回应。
## 注：文档此处类型为 String，但 §6.2 描述为「调用词条里写好的追问问题和回答」；
## 若一条主张要挂多个问答，后续应改为 Array[Dictionary]。
@export_multiline var rebuttals: String = ""
