extends Control

## 战报演出（ARCHITECTURE.md §4）：下班马车上看当天结果。
##
## 与其它阶段场景一样，本脚本**不决定**下一步是什么 —— 只发 `phase_finished`
## 报告「本阶段做完了」，换阶段 / 换天 / 进结局由 day_loop 问 DayDirector 决定。
##
## 战报数据怎么来：**Pull**。本场景自己在挂载时、以及收到阶段通知时去
## `GameState.get_battle_report()` 取 —— 和 interview.gd 读 `GameState.current_candidates`
## 是同一个路子。
##
## 为什么不用 `EventBus.battle_report_ready`（Push）：那个信号在**组队提交 / 推进到战报之前**
## 就发了，而那一刻本场景还没被挂载，一定会错过。同一个坑见 day_phase_entered 的由来。

var _phase: int = DayPhase.Phase.DAY_BRIEFING

## 本阶段做完了。day_loop 挂载本场景时会把它接到 advance() 上。
signal phase_finished()

## 当前正在演出的战报（可能为 null：当天还没生成）
var _report: BattleReport = null

## 点完「确认」之后，在右下角把开场签的那一笔重描出来，这么久播完（秒）。
const SIGNATURE_REPLAY_SECONDS := 1.0

## 要回放哪一份签名 —— 第一天开场逼玩家签的那份「入职合同」（data/dialogue.json 的
## day1_briefing，key 就是 `signature`）。
const SIGNATURE_KEY := &"signature"

## 回放画布的位置与大小 —— **落在纸面内的那块空白上**。
##
## 量出来的三个硬边界（都不是猜的，是采像素扫出来的）：
##   · 纸张实体（paper.png 的不透明外接框）：x 592..988, y 30..570 —— 不是整屏 1152×648！
##     画布出了这个框就是吊在空气里，所以它必须整块待在框内。
##   · 报告正文的墨迹到 y≈290 为止（`ReportContent` 的矩形框更大，但字没铺满）；
##   · 「总分：72.5」那一行在 y 487..516、「确认」在 x 736..839 / y 533..561。
## 于是纸面中间剩下一条干净的横带 y 310..470，本画布就取它的下半截：
##   (610,340)–(970,469)，360×129。
##
## ⚠️ 宽高比锁在 970:348（≈2.788），就是录制时那块画布的比：360/129 = 2.791，
##    差 0.1%，肉眼看不出。Pad 的渲染是「归一化坐标 × 当前矩形」，比例一变字就被拉变形 ——
##    要改尺寸请等比缩放，别只动一边。
const SIGNATURE_PAD_RECT := Rect2(610, 340, 360, 129)

const SIGNATURE_PAD_SCENE := preload("res://ui/components/signature_pad.tscn")

@onready var _confirm: Button = get_node_or_null("BattleReportPhd/Confirm") as Button
@onready var _content: RichTextLabel = get_node_or_null("BattleReportPhd/ReportContent") as RichTextLabel
@onready var _score: Label = get_node_or_null("BattleReportPhd/ScoreContainer") as Label

## 右下角那块**只用来回放**的签名画布（第一次点确认时才建，见 _ensure_signature_pad）
var _signature_pad: SignaturePad = null

## 已经按下确认、正在放签名动画。用来挡重复点击（不然会 emit 两次 phase_finished）
var _confirming: bool = false


func _ready() -> void:
	EventBus.day_phase_entered.connect(set_phase)

	# 「确认」= 本阶段做完了。
	# 连接写在代码里而不是 .tscn 的 [connection] 上：加 is_connected 守卫就天然幂等，
	# 也不依赖编辑器里那份容易漏存的记录（battle_report.tscn 里目前确实没有它）。
	if _confirm != null and not _confirm.pressed.is_connected(_on_confirm_pressed):
		_confirm.pressed.connect(_on_confirm_pressed)

	# 挂载时先自己取一次。紧接着 day_loop 的 day_phase_entered 还会再来一次 ——
	# 两次都是 Pull，幂等，不会重复播什么。
	_refresh_report()


func set_phase(new_phase: int) -> void:
	_phase = new_phase
	_refresh_report()


# ---------------------------------------------------------------------------
# 战报数据 → 界面
# ---------------------------------------------------------------------------


## 从 GameState 取当天战报并铺到界面上。
func _refresh_report() -> void:
	set_report(GameState.get_battle_report())


## 把一份战报铺到界面上。数据由调用方给，本函数只负责显示，不算任何东西。
func set_report(report: BattleReport) -> void:
	_report = report
	if _content == null:
		push_error("[BattleReport] 找不到 ReportContent")
		return
	if report == null:
		# 还没生成时不要静默留空：清掉上一次的内容，并说清原因
		_content.text = ""
		_set_score_text("")
		push_warning("[BattleReport] 当天的战报还没生成（GameState.get_battle_report() 返回 null）")
		return
	_content.text = _format_report(report)
	# 总分**不在正文里** —— 它有自己的显示位（ScoreContainer），位置由场景摆
	_set_score_text(str(report.day_score))


func _set_score_text(text: String) -> void:
	if _score == null:
		push_error("[BattleReport] 找不到 ScoreContainer，总分显示不出来")
		return
	_score.text = text


## 战报 → 显示文本（**不含总分**，总分走 ScoreContainer）。
##
## ★ 想改「文字怎么呈现」就改这一个函数 ★
##
## 这里刻意只产出**纯文本**（换行分隔），因为 ReportContent 的 `bbcode_enabled`
## 默认是 false —— 直接写 BBCode 会原样显示成一堆方括号。
## 要上颜色 / 加粗 / 图标，先把 bbcode_enabled 打开，再把这个函数改成拼 BBCode。
func _format_report(report: BattleReport) -> String:
	var lines: Array[String] = []
	lines.append("第 %d 天" % report.day_index)
	lines.append("出战：%s" % _member_names(report.member_ids))
	lines.append("")
	for event in report.events:
		lines.append("· %s" % _event_text(event))
	return "\n".join(lines)


## 一条事件的可读文本。
##
## core 只产出 id（`text` 里留着 {actor} 占位符，另有 "actor" 字段），
## 把 id 翻成人名是**表现层**的事 —— core 不该认识 display_name。
## 真实实现里 narrative_engine 会直接吐成品文案，那时这里取 "text" 就够了。
func _event_text(event: Dictionary) -> String:
	var text := str(event.get("text", ""))
	var actor := StringName(event.get("actor", &""))
	if actor != &"":
		text = text.replace("{actor}", _name_of(actor))
	return text


## 把成员 id 换成能给人看的名字（data/candidates/*.tres 的 display_name）。
## 目的是显示「阿兰」而不是「c_0001」；查不到就退回 id，绝不显示空。
func _member_names(member_ids: Array[StringName]) -> String:
	if member_ids.is_empty():
		return "今天没有人出战。"
	var names: Array[String] = []
	for member_id in member_ids:
		names.append(_name_of(member_id))
	return "、".join(names)


## id → 能给人看的名字；查不到就退回 id。
func _name_of(candidate_id: StringName) -> String:
	var candidate := GameState.get_candidate(candidate_id)
	if candidate != null and not candidate.display_name.is_empty():
		return candidate.display_name
	return String(candidate_id)


# ---------------------------------------------------------------------------
# 车夫对话 / 推进
# ---------------------------------------------------------------------------


func _on_driver_dialoge_active_timeout() -> void:
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[BattleReport] 找不到 Dialoguer")
		return
	if not dialoguer.typer.load_dialogue("day%d_driver" % GameState.get_day()):
		dialoguer.typer.load_dialogue("day-1_driver")
	dialoguer.play()


## 玩家点了「确认」—— 报告本阶段结束。
##
## 这里**不加阶段守卫**：本场景只在 BATTLE_REPORT 阶段被 day_loop 挂载，
## 按钮也只存在于这个场景里；加守卫反而会让单独按 F6 跑本场景时点不动。
## （对比 interview.gd：那一个场景承载四个阶段，按钮必须分阶段限制。）
##
## ⚠️ 顺序是「先把签名画出来 → 等它画完 → 才报 phase_finished」。
##    day_loop 一收到 phase_finished 就会换阶段 / 换天，**这个场景连同动画会被一起拆掉**；
##    先 emit 的话，玩家只会看到闪一下。所以这里必须 await。
func _on_confirm_pressed() -> void:
	if _confirming:
		return
	_confirming = true

	var saved := GameState.get_signature(SIGNATURE_KEY)
	if saved == null or saved.is_empty():
		# 没签过（理论上走不到：第一天开场不签就翻不了页）。别为了动画把流程卡住。
		phase_finished.emit()
		return

	_play_signature(saved)
	await get_tree().create_timer(SIGNATURE_REPLAY_SECONDS).timeout
	# 等这一秒的功夫，场景可能已经被别人换掉了（换阶段 / 回菜单）
	if not is_inside_tree():
		return
	phase_finished.emit()


## 在右下角把这一笔重描出来（1 秒内播完，见 SIGNATURE_REPLAY_SECONDS）。
func _play_signature(saved: Signature) -> void:
	var pad := _ensure_signature_pad()
	if pad == null:
		return
	pad.play_signature(saved, SIGNATURE_REPLAY_SECONDS)


## 第一次要点时才建那块画布：没人点确认就什么都不多做。
##
## 挂在 `BattleReportPhd`（那张纸）底下，而不是场景根下 —— 这样它画在纸之上、
## 但仍在 Haohan（跟光标的那只手）之下，手不会被签名挡住。
func _ensure_signature_pad() -> SignaturePad:
	if _signature_pad != null:
		return _signature_pad
	var pad := SIGNATURE_PAD_SCENE.instantiate() as SignaturePad
	if pad == null:
		push_error("[BattleReport] 签名画布实例化失败（ui/components/signature_pad.tscn）")
		return null
	# 战报本身就是一整张纸：不要再糊一块白底和一圈边线上去，只留墨迹
	pad.backdrop_color = Color(0, 0, 0, 0)
	pad.border_width = 0.0
	# 这块画布只负责回放，不该出现「按住左键签名」那行提示字
	pad.show_hint = false
	# 缩小后线会跟着细到看不见；比「严格等比缩」稍粗一点点，读得清
	pad.ink_width_ratio = 0.016

	var host := get_node_or_null("BattleReportPhd")
	if host == null:
		host = self
	host.add_child(pad)
	pad.position = SIGNATURE_PAD_RECT.position
	pad.size = SIGNATURE_PAD_RECT.size

	# 回放画布不收输入：它只是「演出」，别让它挡住底下任何东西
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_signature_pad = pad
	return _signature_pad
