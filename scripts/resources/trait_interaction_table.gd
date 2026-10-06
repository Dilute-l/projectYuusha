class_name TraitInteractionTable
extends Resource

## 相性 / 克制矩阵。单文件集中维护：data/traits/interactions.tres
## 由 scripts/core/team/synergy_calculator.gd 读取。

## 每一对的格式：
##   { "a": StringName, "b": StringName, "delta": float, "note": String }
## delta > 0 为配合（例：正义感 × 骑士精神），< 0 为冲突（例：自恋 × 独狼）。
## 暂按无向处理（a / b 顺序无关）；若需要单向克制，再补 "directed": bool。
@export var pairs: Array[Dictionary] = []
