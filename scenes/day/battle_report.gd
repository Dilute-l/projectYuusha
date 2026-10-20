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
##
## ── 演出顺序（本脚本的主线）────────────────────────────────────────────────
##
##   ① 纸面底下先把「总分 0 / 今日目标 xxx」亮出来 —— **一开始就在**，
##      玩家先知道自己今天要交多少，再往下看账怎么一笔笔累上去。
##   ② 正文逐行跳出来（一行一个 RichTextLabel，淡入 + 轻微放大）：
##        · 个人评价那一条，行尾跟 `+xxx`（这个人自身战力，core 算好的 `event.score`）
##        · 相性 / 事件那一条，行尾跟 `×1.1`（这一条真正乘上去的倍数，`event.factor`）
##      每跳一行，底下那个总分就跟着动一次：加法往上爬，乘法按比例放大缩小。
##   ③ 全部播完，总分落在 `report.day_score` 上 —— 和存档 / 结局读的是同一个数。
##
## ⚠️ 本脚本**一分钱都不算**：`+` 与 `×` 的数都来自 core（CombatResolver）塞进
##    `report.events` 的 `score` / `factor`。表现层重算一遍就等于有了第二个真相，
##    两边一旦分岔（比如相性公式改了、这边没跟上）就没人说得清哪个是对的。
##    自检见 tools/smoke_report_playback.gd：把这两列数加/乘回去必须等于 day_score。

var _phase: int = DayPhase.Phase.DAY_BRIEFING

## 本阶段做完了。day_loop 挂载本场景时会把它接到 advance() 上。
signal phase_finished()

## 当前正在演出的战报（可能为 null：当天还没生成）
var _report: BattleReport = null

# ---------------------------------------------------------------------------
# 签名回放
# ---------------------------------------------------------------------------

## 点完「确认」之后，在右下角把开场签的那一笔重描出来，这么久播完（秒）。
const SIGNATURE_REPLAY_SECONDS := 1.0

## 要回放哪一份签名 —— 第一天开场逼玩家签的那份「入职合同」（data/dialogue.json 的
## day1_briefing，key 就是 `signature`）。
const SIGNATURE_KEY := &"signature"

## 回放画布的位置与大小 —— **落在纸面右下角、紧挨着「确认」**，像一份签收单的落款。
##
## ⚠️ 以前它在纸面正中那条空白横带（610,340 360×129）上。正文改成「逐行跳出来」之后
##    那条横带要留给战报正文（现在正文可以铺满整张纸），于是把它挪到了右下角：
##    确认键右边那块一直空着的地方，(846,498)–(977,545)。
##
## ⚠️ 宽高比仍锁在 970:348（≈2.788）：131/47 = 2.787。
##    Pad 的渲染是「归一化坐标 × 当前矩形」，比例一变字就被拉变形 —— 要改尺寸请等比缩放。
const SIGNATURE_PAD_RECT := Rect2(846, 498, 131, 47)

const SIGNATURE_PAD_SCENE := preload("res://ui/components/signature_pad.tscn")

# ---------------------------------------------------------------------------
# 逐行播报
# ---------------------------------------------------------------------------

## 正文用的字体（和改动前 ReportContent 同一个：assets/fonts/Silver.ttf）。
const REPORT_FONT: Font = preload("res://assets/fonts/Silver.ttf")

## 开场停一下，让「总分 / 今日目标」先被看见，再开始播第一行（秒）
const START_DELAY := 0.35
## 一行跳出来之后，停这么久再结算它的分数（秒）
const ROW_HOLD := 0.20
## 底下总分「跳」到新值用多久（秒）
const COUNT_SECONDS := 0.24
## 提示行（第 N 天 · 出战）不结算分数，只多给一眼看的时间
const HEADER_HOLD := 0.28

## 字号自适应：正文一行一行变多，纸张尺寸是死的，所以字号得自己让。
## 从大到小试，第一个「量出来的总高 ≤ 可用高度」的胜出；都塞不下就用最小号（会裁掉尾巴）。
const FIT_MAX_FONT := 26
const FIT_MIN_FONT := 11
## 行与行之间的间距（和 .tscn 里 ReportContent 的 separation 保持一致）
const LINE_SEPARATION := 6.0
## .tscn 还没铺好尺寸时的兜底（正常走不到：ReportContent 的矩形是写死的）
const FALLBACK_CONTENT_SIZE := Vector2(368, 360)

## 墨色（正文）
const INK := Color(0, 0, 0, 1)
## 抬头的行（第 N 天 · 出战）淡一点，别抢正文
const HEADER_INK := Color(0.35, 0.30, 0.26, 1)
## 行尾那截加分的颜色（深绿）
const SUFFIX_GAIN := "#2f6b46"
## 行尾那截扣分的颜色（深红）
const SUFFIX_LOSS := "#8c2f2c"
## 底分往上涨时闪一下的颜色 / 往下掉时闪一下的颜色（落点回 INK）
const FLASH_GAIN := Color(0.13, 0.42, 0.24, 1)
const FLASH_LOSS := Color(0.62, 0.15, 0.15, 1)

@onready var _confirm: Button = get_node_or_null("BattleReportPhd/Confirm") as Button
@onready var _content: VBoxContainer = get_node_or_null("BattleReportPhd/ReportContent") as VBoxContainer
@onready var _score: Label = get_node_or_null("BattleReportPhd/ScoreContainer") as Label
@onready var _target: Label = get_node_or_null("BattleReportPhd/TargetContainer") as Label

## 正文要播的行（每项：plain / bbcode / kind / value）
var _rows: Array[Dictionary] = []
## 和 `_rows` 一一对应的控件（一次性全建好、先把 alpha 藏掉，播到谁再放谁出来 ——
## 这样版面从第一帧起就是最终版，播放过程中不会因为「又加了一行」而整体重排）
var _row_labels: Array[RichTextLabel] = []

## 底下总分**此刻显示**的值（跟真实的 day_score 分开：它在追动画）
var _shown_score: float = 0.0

## 正在滚的那条分数补间。**跳过 / 收尾时必须 kill 掉** ——
## tween_method 是每帧回调 `_show_score()` 的；放着不管的话，「点确认跳过」摆好的
## day_score 会被这条还在飞的补间一帧帧拽回它原来的目标值，然后再也不会自己纠正。
var _score_tween: Tween = null

## 播放批次号。换了一份战报就 +1，让上一条协程自己认领「我已经过期了」退出
var _play_token: int = 0
var _playing: bool = false
## 这一份战报已经播完（再 set_report 同一份就不重播，见 set_report）
var _played: bool = false

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
	# 同一份战报**不重播**：本场景会被连着喂两次（_ready 一次 + day_phase_entered 一次），
	# 没有这道守卫的话，玩家会看到战报播到一半又从 0 开始。
	if report != null and report == _report and (_playing or _played):
		return

	_report = report
	if _content == null:
		push_error("[BattleReport] 找不到 ReportContent")
		return
	# 换战报 = 上一份的动画全部作废（分数补间还在滚的话会把 0 拽回旧值）
	_kill_score_tween()
	if report == null:
		# 还没生成时不要静默留空：清掉上一次的内容，并说清原因
		_clear_rows()
		_show_score(0.0)
		_set_target_text(-1)
		push_warning("[BattleReport] 当天的战报还没生成（GameState.get_battle_report() 返回 null）")
		return

	_build_rows(report)
	_set_target_text(report.day_index)
	# 一开始就是 0 分 + 今日目标一起亮着（§「演出顺序」①）
	_show_score(0.0)
	_start_playback()


## 今日目标（`DayConfig.score_request`）。
##
## 显示是**和总分同一副样子**（同样的 36px 粗体黑字，只是靠右）：两栏并排，
## 左边「总分」右边「今日目标」，一眼就能对上自己离及格线还差多少。
## 所以这里**只填数字**——「今日目标」那四个字是场景里另一个小标题（`TargetTitle`）。
##
## 0 = 当天没有要求（见 day_config.gd），写成「无要求」而不是 0：
## 那不是一个「考 0 分就过」的门槛。取不到当天配置时写「—」，也不装作有要求。
func _set_target_text(day_index: int) -> void:
	if _target == null:
		return
	if day_index < 0:
		_target.text = "—"
		return
	var config := DataDB.get_day_config(day_index)
	var required := config.score_request if config != null else 0
	_target.text = str(required) if required > 0 else "无要求"


# ---------------------------------------------------------------------------
# 行 → 控件
# ---------------------------------------------------------------------------


## 按战报铺出所有行（**先全建好、alpha 藏起来**，播到谁再放谁出来）。
func _build_rows(report: BattleReport) -> void:
	_clear_rows()
	_rows = _collect_rows(report)

	var width: float = _content.size.x if _content.size.x > 1.0 else FALLBACK_CONTENT_SIZE.x
	var height: float = _content.size.y if _content.size.y > 1.0 else FALLBACK_CONTENT_SIZE.y
	var font_size := _fit_font_size(width, height)
	for row in _rows:
		var label := _make_row_label(row, font_size, width)
		_content.add_child(label)
		_row_labels.append(label)


## 战报 → 行的数据。**每一行的 + / × 都照抄 core 给的数**，这里一个乘除都不做。
func _collect_rows(report: BattleReport) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var header := "第 %d 天 · 出战 %s" % [report.day_index, _member_names(report.member_ids)]
	rows.append({"plain": header, "bbcode": header, "kind": &"header", "value": 0.0})

	for event in report.events:
		var text := _event_text(event)
		var kind := &"note"
		var value := 0.0
		var suffix := ""
		if event.has("score"):
			# 这个人自身的战力 → 行尾 `+xxx`，底下总分加这么多
			kind = &"member"
			value = float(event.get("score", 0.0))
			suffix = "+%s" % _format_number(value)
		elif event.has("factor"):
			# 这一条真正乘上去的倍数 → 行尾 `×1.1`，底下总分乘这一下
			kind = &"synergy"
			value = float(event.get("factor", 1.0))
			suffix = "×%s" % _format_factor(value)

		var plain := "· %s" % text
		var bbcode := plain
		if not suffix.is_empty():
			var tone := SUFFIX_GAIN if (kind == &"member" or value >= 1.0) else SUFFIX_LOSS
			plain = "%s  %s" % [plain, suffix]
			bbcode = "%s  [b][color=%s]%s[/color][/b]" % [bbcode, tone, suffix]
		rows.append({"plain": plain, "bbcode": bbcode, "kind": kind, "value": value})

	return rows


func _make_row_label(row: Dictionary, font_size: int, width: float) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(width, 0.0)
	label.add_theme_font_override("normal_font", REPORT_FONT)
	label.add_theme_font_override("bold_font", REPORT_FONT)
	# 字号要把 normal / bold 一路全盖掉：只盖 normal 的话，`[b]` 那截会退回
	# 主题里那个 16px 的默认字号，行尾的 +xxx 会比正文小一圈。
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	label.add_theme_font_size_override("italics_font_size", font_size)
	label.add_theme_font_size_override("bold_italics_font_size", font_size)
	label.add_theme_font_size_override("mono_font_size", font_size)
	label.add_theme_color_override("default_color", HEADER_INK if row.get("kind") == &"header" else INK)
	label.text = str(row.get("bbcode", ""))
	# 先藏着：播到它才放出来（见 _reveal_row）
	label.modulate.a = 0.0
	return label


## 挑一个「全部行都塞得进这张纸」的字号。
func _fit_font_size(width: float, height: float) -> int:
	var font_size := FIT_MAX_FONT
	while font_size > FIT_MIN_FONT:
		if _measured_height(width, font_size) <= height:
			return font_size
		font_size -= 1
	# 最小号也塞不下：照播（尾巴会被裁掉），但别静默 —— 这说明战报该想想排版了
	if _measured_height(width, FIT_MIN_FONT) > height:
		push_warning("[BattleReport] 战报太长，%dpx 也塞不进纸面（共 %d 行），尾巴会被裁掉" % [
			FIT_MIN_FONT, _rows.size()])
	return FIT_MIN_FONT


## 全部行按这个字号折行之后有多高（用字体自己量，不依赖控件排版跑过一帧）。
##
## 宽度让出 6px：误差宁可在「以为塞得下、其实塞不下」这一侧留，也不要反过来 ——
## 差一点点就会把最后一行顶到底下的分数条上。
func _measured_height(width: float, font_size: int) -> float:
	var total := 0.0
	for row in _rows:
		var measured := REPORT_FONT.get_multiline_string_size(
				str(row.get("plain", "")), HORIZONTAL_ALIGNMENT_LEFT,
				maxf(width - 6.0, 16.0), font_size)
		total += measured.y + LINE_SEPARATION
	return total


func _clear_rows() -> void:
	for label in _row_labels:
		if is_instance_valid(label):
			label.queue_free()
	_row_labels.clear()
	_rows.clear()


# ---------------------------------------------------------------------------
# 播报
# ---------------------------------------------------------------------------


func _start_playback() -> void:
	_play_token += 1
	_played = false
	_playing = true
	_play_rows(_play_token)


## 一行一行往外跳，跳一行结一笔账。`token` 是本次播放的批次号：
## 播放途中被换了一份战报（或者场景被拆了），它就跟 `_play_token` 对不上，立即收工。
func _play_rows(token: int) -> void:
	await _wait(START_DELAY)
	for index in _row_labels.size():
		if token != _play_token or not is_inside_tree():
			return
		_reveal_row(index)
		var is_header := StringName(_rows[index].get("kind", &"note")) == &"header"
		await _wait(HEADER_HOLD if is_header else ROW_HOLD)
		if token != _play_token or not is_inside_tree():
			return
		_apply_row(_rows[index])
		if is_header:
			continue
		await _wait(COUNT_SECONDS)

	if token != _play_token or not is_inside_tree():
		return
	_apply_final()
	_playing = false
	_played = true


## 把一行放出来：淡入 + 从 94% 弹到 100%。
##
## 用 scale 而不是动 position —— 这些控件挂在 VBoxContainer 底下，
## 位置由容器排，只有 scale / modulate 是「谁都可以动」的。
func _reveal_row(index: int) -> void:
	if index < 0 or index >= _row_labels.size():
		return
	var label := _row_labels[index]
	if not is_instance_valid(label):
		return
	label.pivot_offset = Vector2(0.0, label.size.y * 0.5)
	label.scale = Vector2(0.94, 0.94)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.14)
	tween.tween_property(label, "scale", Vector2.ONE, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 结算一行：个人评价 → 加，相性 / 事件 → 乘。底下总分跟着跳。
func _apply_row(row: Dictionary) -> void:
	match StringName(row.get("kind", &"note")):
		&"member":
			_count_to(_shown_score + float(row.get("value", 0.0)), FLASH_GAIN)
		&"synergy":
			var factor := float(row.get("value", 1.0))
			_count_to(_shown_score * factor, FLASH_GAIN if factor >= 1.0 else FLASH_LOSS)
		_:
			pass  # 抬头行 / 没有说话数的行：不动总分


## 立刻播完（跳过）。点「确认」时代也走这里 —— 剩下几行没必要让玩家等。
func finish_playback() -> void:
	_play_token += 1
	for label in _row_labels:
		if is_instance_valid(label):
			label.modulate.a = 1.0
			label.scale = Vector2.ONE
	_apply_final()
	_playing = false
	_played = true


## 收尾：总分落在**真实的** day_score 上（不是我们一路乘出来的近似值）。
func _apply_final() -> void:
	_kill_score_tween()
	if _report != null:
		_show_score(_report.day_score)
	_restore_score_color()
	if _score != null:
		_score.scale = Vector2.ONE


# ---------------------------------------------------------------------------
# 底下那条分数
# ---------------------------------------------------------------------------


## 把显示值往 `target_value` 上跳一下：数字滚过去 + 闪个颜色 + 弹一下。
func _count_to(target_value: float, tone: Color) -> void:
	if _score == null:
		return
	_kill_score_tween()
	_score.pivot_offset = Vector2(0.0, _score.size.y * 0.5)
	_score.add_theme_color_override("font_color", tone)
	_score_tween = create_tween()
	_score_tween.tween_method(_show_score, _shown_score, target_value, COUNT_SECONDS)
	_score_tween.parallel().tween_property(_score, "scale", Vector2.ONE, 0.22) \
			.from(Vector2(1.10, 1.10))
	_score_tween.tween_interval(0.12)
	_score_tween.tween_callback(_restore_score_color)


## 掐掉还在滚的那条补间（跳过 / 收尾 / 下一行结算前都要先掐）。
## 留着它的话，它会在随后的每一帧继续 `_show_score()`，把摆好的数拽回去。
func _kill_score_tween() -> void:
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	_score_tween = null


func _restore_score_color() -> void:
	if _score != null:
		_score.add_theme_color_override("font_color", INK)


## 直接摆一个值（不带动画）。播报被打断 / 收尾时用。
func _show_score(value: float) -> void:
	_shown_score = value
	if _score != null:
		_score.text = _format_number(value)


# ---------------------------------------------------------------------------
# 数字怎么读
# ---------------------------------------------------------------------------


## 分数：整数就不带小数点（`+420`），带小数就留一位（`1076.4`）。
func _format_number(value: float) -> String:
	var rounded := roundf(value)
	if absf(value - rounded) < 0.05:
		return "%d" % int(rounded)
	return "%.1f" % value


## 倍数：留两位再去掉尾零（×1.05 / ×1.1 / ×0.5）。多留一位是因为
## 当日事件的 ×1.05 用一位小数会被念成 ×1.1，跟底下真正乘的数对不上。
func _format_factor(value: float) -> String:
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text


# ---------------------------------------------------------------------------
# 一条事件的可读文本
# ---------------------------------------------------------------------------


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


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


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
## ⚠️ 顺序是「先把账结清 → 把签名画出来 → 等它画完 → 才报 phase_finished」。
##    day_loop 一收到 phase_finished 就会换阶段 / 换天，**这个场景连同动画会被一起拆掉**；
##    先 emit 的话，玩家只会看到闪一下。所以这里必须 await。
##
## 播报还没放完就点确认 = 跳过：剩下的行一次亮完、总分直接落到位，
## 不让玩家等一串和他无关的动画（他可能已经读完了）。
func _on_confirm_pressed() -> void:
	if _confirming:
		return
	_confirming = true

	finish_playback()

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
