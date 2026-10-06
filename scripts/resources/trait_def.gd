class_name TraitDef
extends Resource

## 性格与特殊癖好定义。data/traits/

## 分类：性格 or 癖好
enum Category { PERSONALITY, QUIRK }

## 命名空间化 ID，例如 trait.ego
@export var id: StringName

@export var display_name: String

@export var category: Category = Category.PERSONALITY

## 参与相性计算的标签，供 synergy_calculator.gd 做两两配对
@export var synergy_tags: Array[StringName] = []

## 悬浮提示文案（trait_tooltip.tscn 使用）
@export_multiline var description: String = ""
