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
##     **唯一的例外是设置页**（`SettingPage`，系统浮层 §14.5）：那一层开着时本对话框
##     既不吃点击、也不推进 —— 否则设置页上的按钮一颗都点不动（见 `_input()`）。
##
##   穿透模式（play(true)）——对话框照常被这一下点击推进，但**不吃掉**它：
##     被点到的按钮同一次点击里也会照常收到 pressed（以及 hover / 移出等一切常规交互）。
##     适合「这句话只是提醒，界面照用」的场合：主菜单的退出确认、
##     组队没满时的「确定要走吗」都是这种 —— 玩家可以一边看提醒一边点按钮。
##
## 场景只负责接线与寿命，不关心具体哪一段对话：调用方 load_dialogue(id) 后调 play()。

## 一段对话全部结束（且玩家已点击收起对话框）
signal dialogue_ended

## 玩家在牌子的签名画布上签好了（key 来自对话那一行的 popup_signature）。
##
## ⚠️ 本脚本**只转发、不落盘**：Dialoguer 不认识 GameState（见文件头）。真正把它写进
##    RunState 的是 GameState 自己 —— 它订阅 EventBus.signature_signed（§16.7），
##    所以场景侧一根线都不用接。本信号留给「这一段播完想顺便做点别的」的调用方。
signal signature_signed(signature_key: StringName, signature: Signature)

## 正文 Label（挂 typer.gd）
@onready var typer: Typer = get_node_or_null("Dialogue") as Typer

## 说话人 Label
@onready var name_label: Label = get_node_or_null("Name") as Label

## 对话期间的「小牌子」（Popup.tscn，本场景的子节点）。没有就什么都不弹。
@onready var _popup: DialoguePopup = get_node_or_null("Popup") as DialoguePopup

## 本次播放是否为穿透模式（由 play() 的参数决定，整段对话期间不变）。
## false = 吃掉左键（默认）；true = 左键照常传给底下的 GUI。
var _pass_through: bool = false

## 本次对话要用来填 popup 的候选人。
##
## ⚠️ Dialoguer **不认识 GameState**（它只是个控件，被主菜单 / 面试 / 战报一起复用），
##   所以候选人是**调用方塞进来的**：谁播对话谁在 play() 之前调 set_candidate()。
##   不塞就是 null —— popup 照常显示，只是不填字。
var _candidate: CandidateResource = null


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
	# 每一句开始 / 结束时驱动牌子：句子里的 "popup" 键写的是牌子下面哪个子节点
	if not typer.line_started.is_connected(_on_line_started):
		typer.line_started.connect(_on_line_started)
	if not typer.line_finished.is_connected(_on_line_finished):
		typer.line_finished.connect(_on_line_finished)
	# 牌子上签了字 → 往上转发（本脚本不落盘，见 signature_signed 的说明）
	if _popup != null and not _popup.signature_signed.is_connected(_on_popup_signature_signed):
		_popup.signature_signed.connect(_on_popup_signature_signed)


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
	# 设置页（系统浮层，§14.5）开着 → 这一下归它：对话框既不推进、也不吃。
	# 否则点击在 `_input` 阶段就被这里吃掉，设置页上的按钮一颗都点不动。
	#
	# ⚠️ 只对**阻挡模式**让路：穿透模式本来就不吃点击，而设置页自己的「退出确认」
	#    用的正是穿透模式 —— 也让它让路的话，那段提醒就永远翻不了页。
	if not _pass_through and SettingPage.is_any_open():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# ⚠️ 牌子正在等玩家签字 → 这一下**属于画布**：既不推进对话，也不吃掉事件。
		#    顺序很关键 —— 本方法在 GUI 输入**之前**跑，这里一 return，事件就会
		#    照常落到画布的 _gui_input 上（落笔）；若在这里 set_input_as_handled()，
		#    画布就永远收不到这一下，玩家签不了字。
		#    签好之后 blocks_advance() 变假，点击恢复推进 —— 语义正好是「签完才能往下走」。
		#
		# ⚠️ 但「这一句还在逐字显示」时别抢：玩家点一下是想把字快进完，不是想落笔。
		#    这时候照常吃掉这一下、照常 advance()（逐字中它只 skip_line，不会翻页），
		#    画布收不到事件，于是不会平白多一个墨点。打完字之后的点击才归画布。
		var waiting_for_signature := _popup != null and _popup.blocks_advance()
		if waiting_for_signature and not typer.is_typing:
			return
		# 放在 _input 而非 _unhandled_input，是为了在对话框开着时
		# 决定「这次点击要不要穿透到主菜单按钮上」——见下面的两分支。
		if not _pass_through:
			# 阻挡模式：吃掉这次点击，本帧的 GUI（按钮等）不应再处理它。
			get_viewport().set_input_as_handled()
		# 穿透模式：什么都不做，事件继续往下走，被点到的按钮照常按下。
		# 注意顺序 —— 本方法在 GUI 输入**之前**被调用，所以这里先推进对话、
		# 按钮的 pressed 随后才发；同一次点击两边都会响应。
		typer.advance()


## 本次对话要用来填牌子的候选人。谁播对话谁在 play() 之前调它。
func set_candidate(candidate: CandidateResource) -> void:
	_candidate = candidate


## 先把一份**已知的**签名喂给牌子（读档之后想让它显示出旧签名就调一次）。
##
## 透传给 Popup —— 调用方只碰 Dialoguer，不必知道底下那块画布叫什么。
func set_known_signature(signature_key: StringName, signature: Signature) -> void:
	if _popup != null:
		_popup.remember_signature(signature_key, signature)


## 牌子此刻是否正等着玩家签字（为真时左键不推进对话，见 _input）。
func blocks_advance() -> bool:
	return _popup != null and _popup.blocks_advance()


## 牌子报「签好了」：往上报，并且**自动进入下一句**。
##
## 「松手 = 这一句办完了」—— 玩家刚把笔抬起来，这时候还要再点一下才能继续，
## 手感是断的：他这一下的意图已经表达完了。所以签完就自动翻页。
##
## ⚠️ 隔着一次 `call_deferred`：这次签字正是**松开左键**引发的，此刻还站在画布的
##    `_gui_input` 里。等这一轮输入处理完再翻页，免得翻页顺手把牌子和画布藏掉，
##    而画布自己还在往下走自己的收尾逻辑。
func _on_popup_signature_signed(signature_key: StringName, signature: Signature) -> void:
	signature_signed.emit(signature_key, signature)
	_advance_after_signature.call_deferred()


## 签字之后自动翻页（见 _on_popup_signature_signed）。
##
## 只翻**一句**：`typer.advance()` 在「本行已打完」时是 next_line()，逐字中才是 skip_line()。
## 签字那一句必然是打完的（没打完时点击都不给画布，见 _input），所以这里一定翻页。
func _advance_after_signature() -> void:
	# deferred 到这一帧末尾时，对话可能已经被收掉了（例如整段结束把 Dialoguer 藏了）
	if not is_playing() or typer == null:
		return
	typer.advance()


## 给这次对话设变量：对话文本里的 `{total_score}` 之类会被替换成值。
##
## 透传给 typer —— 调用方只碰 Dialoguer，不必知道底下是 Typer。
## 键不带花括号；未在表里的占位符**原样保留**（见 typer.gd::_substitute）。
func set_vars(values: Dictionary) -> void:
	if typer != null:
		typer.set_vars(values)


## 清空变量（同一份 Dialoguer 换一段对话时用，免得上一段的值漏过来）。
func clear_vars() -> void:
	if typer != null:
		typer.clear_vars()


## 某一**句开始播** → 按这一行的 "popup" / "popup_stamp" 键把牌子亮出来。
##
##   popup        牌子下面哪个子节点（例如 "AwardPhd"）；没写或写空就不弹。
##   popup_stamp  牌子上盖哪枚章（"resume_stamp_fake1" 之类，看 DialoguePopup.STAMP_NAMES）；
##                写 "none" = 这一句明确不盖，没写这个键 = 沿上一句 / 场景默认。
##
## 字号 / 位置全在 Popup.tscn 里，本函数只负责「亮哪一块 + 填什么字 + 盖哪枚章」。
func _on_line_started(index: int, _text: String) -> void:
	if _popup == null:
		return
	var line: Dictionary = {}
	if index >= 0 and index < typer.lines.size():
		line = typer.lines[index]
	_popup.show_for(
		StringName(String(line.get("popup", "")).strip_edges()),
		_candidate,
		StringName(String(line.get("popup_stamp", "")).strip_edges()),
		StringName(String(line.get("popup_signature", "")).strip_edges()),
	)


## 这一句**打完字了**。这里**故意什么都不做**。
##
## 「牌子什么时候收」是按**玩家的动作**定的，不是按「打字机打完」定的：
##   1. 正在逐字显示时点一下 → 只是把本行显示完，这一句玩家还没读完 → 牌子**留着**；
##   2. 整句已显示完时点一下 → 翻到下一句 → 那一刻 line_started 会先 hide_all()
##      再亮新的（这一句没写 popup 的话就是纯收起）→ 牌子跟着上一句一起消失；
##   3. 最后一句点掉 → dialogue_finished 里兜一次 hide_all()。
##
## 所以「收牌子」已经被 line_started / dialogue_finished 两处覆盖了。
## 早先挂在这里的 hide_all() 会让牌子在**打字刚打完**时就消失 —— 那正是之前的问题。
func _on_line_finished(_index: int) -> void:
	pass


func _on_typer_dialogue_finished() -> void:
	# typer 在「最后一行已打完、且被要求推进」时才发这个信号：
	# 这一刻玩家已经点过了，所以直接收起对话框。
	visible = false
	# 牌子也要收 —— line_finished 通常已经收过一道了，这里再兜一次，
	# 免得「最后一句刚亮起牌子就被玩家点掉」时那块牌子留在画面上。
	# 牌子收起来时会把签名画布的拾取一起松开（§16）。
	if _popup != null:
		_popup.hide_all()
	# 模式跟着这次播放一起结束，免得下次 play() 忘了传参数还留着穿透
	_pass_through = false
	dialogue_ended.emit()
