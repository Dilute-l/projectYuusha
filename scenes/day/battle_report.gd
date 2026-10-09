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

@onready var _confirm: Button = get_node_or_null("BattleReportPhd/Confirm") as Button
@onready var _content: RichTextLabel = get_node_or_null("BattleReportPhd/ReportContent") as RichTextLabel


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
		push_warning("[BattleReport] 当天的战报还没生成（GameState.get_battle_report() 返回 null）")
		return
	_content.text = _format_report(report)


## 战报 → 显示文本。
##
## ★ 想改「文字怎么呈现」就改这一个函数 ★
##
## 这里刻意只产出**纯文本**（换行分隔），因为 ReportContent 的 `bbcode_enabled`
## 默认是 false —— 直接写 BBCode 会原样显示成一堆方括号。
## 要上颜色 / 加粗 / 图标，先把 bbcode_enabled 打开，再把这个函数改成拼 BBCode。
func _format_report(report: BattleReport) -> String:
	var lines: Array[String] = []
	lines.append("第 %d 天战报" % report.day_index)
	lines.append("出战：%s" % _member_names(report.member_ids))
	lines.append("")
	for event in report.events:
		lines.append("· %s" % _event_text(event))
	lines.append("")
	lines.append("当日得分：%d" % report.day_score)
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
		return "（无人出战）"
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
func _on_confirm_pressed() -> void:
	phase_finished.emit()
