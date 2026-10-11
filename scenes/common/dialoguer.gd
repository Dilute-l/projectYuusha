class_name Dialoguer
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
## 两种输入模式（由 play() 的参数在**调用时**选定）：
##
##   阻挡模式（默认）——对话框把左键吃掉，点击**不会**落到它下面的按钮上。
##     适合「先看完这段话再说」的场合：玩家必须把对话点完，才轮到底下的界面。
##
##   穿透模式（play(true)）——对话框照常被这一下点击推进，但**不吃掉**它：
##     被点到的按钮同一次点击里也会照常收到 pressed（以及 hover / 移出等一切常规交互）。
##     适合「这句话只是提醒，界面照用」的场合：主菜单的退出确认、
##     组队没满时的「确定要走吗」都是这种 —— 玩家可以一边看提醒一边点按钮。
##
## 场景只负责接线与寿命，不关心具体哪一段对话：调用方 load_dialogue(id) 后调 play()。

## 一段对话全部结束（且玩家已点击收起对话框）
signal dialogue_ended

## 正文 Label（挂 typer.gd）
@onready var typer: Typer = get_node_or_null("Dialogue") as Typer

## 说话人 Label
@onready var name_label: Label = get_node_or_null("Name") as Label

## 本次播放是否为穿透模式（由 play() 的参数决定，整段对话期间不变）。
## false = 吃掉左键（默认）；true = 左键照常传给底下的 GUI。
var _pass_through: bool = false


func _ready() -> void:
	# typer 的类型是 Typer —— 节点没挂 typer.gd 时这个 as 转换就会失败变成 null，
	# 所以「脚本挂错了」运行期也能被这一句拦下（编译期则由类型本身保证）。
	if typer == null:
		push_error("[Dialoguer] 找不到 Dialogue 节点，或它没有挂 typer.gd（正文 Label）")
		return
	# 把说话人 Label 交给 typer：每行开始时它会按 speaker_name 自动刷新
	typer.set_speaker_label(name_label)
	if not typer.dialogue_finished.is_connected(_on_typer_dialogue_finished):
		typer.dialogue_finished.connect(_on_typer_dialogue_finished)


## 显示对话框并从已 load_dialogue() 选好的那段对话的第 0 行开始播。
## 调用方先调 typer.load_dialogue(id)，再调本方法。
##
## pass_through（默认 false = 阻挡模式，见文件头）：
##   false —— 对话开着时吃掉左键，玩家得把这段点完才能点到下面的按钮；
##   true  —— 对话开着时不吃左键，点到的按钮同一次点击里照常收到按下。
## 模式只对**本次播放**有效，下次 play() 不传参数就又回到阻挡模式。
func play(pass_through: bool = false) -> void:
	if typer == null:
		return
	_pass_through = pass_through
	visible = true
	typer.start_dialogue()


## 本次播放是否为穿透模式。给调用方 / 调试用。
func is_pass_through() -> bool:
	return _pass_through


## 对话是否正在进行（本脚本据此决定要不要吃掉鼠标左键）
func is_playing() -> bool:
	return visible and typer != null and typer.is_active()


func _input(event: InputEvent) -> void:
	if not is_playing():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 放在 _input 而非 _unhandled_input，是为了在对话框开着时
		# 决定「这次点击要不要穿透到主菜单按钮上」——见下面的两分支。
		if not _pass_through:
			# 阻挡模式：吃掉这次点击，本帧的 GUI（按钮等）不应再处理它。
			get_viewport().set_input_as_handled()
		# 穿透模式：什么都不做，事件继续往下走，被点到的按钮照常按下。
		# 注意顺序 —— 本方法在 GUI 输入**之前**被调用，所以这里先推进对话、
		# 按钮的 pressed 随后才发；同一次点击两边都会响应。
		typer.advance()


func _on_typer_dialogue_finished() -> void:
	# typer 在「最后一行已打完、且被要求推进」时才发这个信号：
	# 这一刻玩家已经点过了，所以直接收起对话框。
	visible = false
	# 模式跟着这次播放一起结束，免得下次 play() 忘了传参数还留着穿透
	_pass_through = false
	dialogue_ended.emit()
