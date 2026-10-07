extends Control

## Dialoguer —— 对话框容器，负责把场景内部的零件接起来。
##
## 场景结构（dialoguer.tscn）：
##   Dialogue (Control)   ← 本脚本
##   ├─ TextboxPhd (Sprite2D)   底板
##   ├─ Dialogue (Label)        正文，挂 typer.gd
##   └─ Name (Label)            说话人
##
## 本脚本只做**接线**，不做显示逻辑：逐字由 typer.gd 负责。
## 单独运行本场景（F6）时也能自检接线是否完好。

## 正文 Label（挂 typer.gd）
@onready var typer: Label = get_node_or_null("Dialogue") as Label

## 说话人 Label
@onready var name_label: Label = get_node_or_null("Name") as Label


func _ready() -> void:
	if typer == null:
		push_error("[Dialoguer] 找不到 Dialogue 节点（正文 Label）")
		return
	if typer.get_script() == null or not typer.has_method("set_speaker_label"):
		push_error("[Dialoguer] Dialogue 节点没有挂 typer.gd，逐字显示不可用")
		return
	# 把说话人 Label 交给 typer：每行开始时它会按 speaker_name 自动刷新
	typer.set_speaker_label(name_label)
