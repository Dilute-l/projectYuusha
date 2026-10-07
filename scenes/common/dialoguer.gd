extends Control

## Dialoguer —— 对话框容器，负责把场景内部的零件接起来，并处理「点击推进」。
##
## 场景结构（dialoguer.tscn）：
##   Dialogue (Control)   ← 本脚本
##   ├─ TextboxPhd (Sprite2D)   底板
##   ├─ Dialogue (Label)        正文，挂 typer.gd
##   └─ Name (Label)            说话人
##
## 职责分工：
##   - typer.gd 只管「一个字一个字地显示」，打完一行就停下等调用方；
##   - 本脚本管**流程与输入**：鼠标左键推进，最后一句也要点一下才收起对话框。
##
## 点击语义（沿用惯例）：
##   本行还在逐字 → 左键点一下 = 立刻把本行显示完；
##   本行已打完   → 左键点一下 = 进入下一句；
##   最后一句打完 → 左键点一下 = 收起对话框并发出 dialogue_ended。
##
## 场景只负责接线与寿命，不关心具体哪一段对话：调用方 load_dialogue(id) 后调 play()。

## 一段对话全部结束（且玩家已点击收起对话框）
signal dialogue_ended

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
	if not typer.dialogue_finished.is_connected(_on_typer_dialogue_finished):
		typer.dialogue_finished.connect(_on_typer_dialogue_finished)


## 显示对话框并从已 load_dialogue() 选好的那段对话的第 0 行开始播。
## 调用方先调 typer.load_dialogue(id)，再调本方法。
func play() -> void:
	if typer == null:
		return
	visible = true
	typer.start_dialogue()


## 对话是否正在进行（本脚本据此决定要不要吃掉鼠标左键）
func is_playing() -> bool:
	return visible and typer != null and typer.is_active()


func _input(event: InputEvent) -> void:
	if not is_playing():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 吃掉这次点击：本帧的 GUI（按钮等）不应再处理它。
		# 放在 _input 而非 _unhandled_input，是为了在对话框开着时
		# 避免「点击穿透」到主菜单按钮上。
		get_viewport().set_input_as_handled()
		typer.advance()


func _on_typer_dialogue_finished() -> void:
	# typer 在「最后一行已打完、且被要求推进」时才发这个信号：
	# 这一刻玩家已经点过了，所以直接收起对话框。
	visible = false
	dialogue_ended.emit()
