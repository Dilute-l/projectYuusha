class_name CandidateResource
extends Resource

## 候选人数据模型（ARCHITECTURE.md §3.1）。
## 只定义数据结构，不含规则逻辑。

## 命名空间化 ID，例如 c_0012
@export var id: StringName

@export var display_name: String
@export var age: int
@export var gender: StringName

@export var race: RaceDef
@export var job: JobDef

## 可用技能（ID 命名空间：skill.xxx）
@export var skill_ids: Array[StringName] = []

## skill_id -> 0..100。这是**自称值**，真实值在 HiddenProfile.true_skills，
## 两者的差额即谎言严重程度
@export var skill_levels: Dictionary = {}

## 性格 / 特殊癖好（对玩家可见的部分）
@export var traits: Array[TraitDef] = []

## 简历与口述经历，说谎机制的载体
@export var claims: Array[ClaimResource] = []

## TODO: 拼五官自动生成 Portrait
@export var portrait: Texture2D

## 隐藏属性，UI 永不直接显示
@export var hidden: HiddenProfile
