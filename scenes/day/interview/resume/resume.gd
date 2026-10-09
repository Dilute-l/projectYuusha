class_name Resume
extends Control

## 候选人的完整简历（ARCHITECTURE.md §4「resume.tscn」、§3.1、§6.2）。
##
## 版面 = assets/art/interview/resume_page_phd.png 这张纸 + 贴在纸上的文字：
## 上半是抬头（`CandidateResource.resume_header` 那一整段字），
## 下半是若干条简历词条，每条一个 resume_token.tscn 实例（复用控件）。
##
## ⚠️ 数据来源：**全部来自 CandidateResource**（data/candidates/*.tres）。
##   本脚本里没有一句候选人文案，也没有"默认履历"这种兜底 ——
##   谁把候选人喂进来就显示谁（`set_candidate()`），喂 null 就把纸清空。
##   调用方是 interview.gd，它拿的是 GameState 当日名单（data/days/day_XX.tres）里的那一位。
##   抬头是候选人数据里那一段 `resume_header` 字符串，**原样铺上去，本脚本一个字都不拼**：
##   姓名 / 职业 / 等级 / 属性 / 特质要不要写、怎么分行、什么顺序，全由那段字自己决定。
##   词条同理，逐条取 `resume[i].description`。
##
## ⚠️ 文案是中文字，而 assets/fonts 还没接入中文主字体：默认字体没有中文字形，
##   纸上的中文现在会渲染成方块（同 dialogue.json 的处境）。字体接进来后这里不用改。

const TOKEN_SCENE := preload("res://scenes/day/interview/resume/resume_token.tscn")

# ---- 节点 -------------------------------------------------------------------

@onready var _info_label: Label = $Paper/Rows/HeaderInfo
@onready var _token_list: VBoxContainer = $Paper/Rows/TokenList
@onready var _token_menu: ResumeTokenMenu = $TokenMenu

## 当前铺在纸上的那位候选人；null = 纸是空的
var _candidate: CandidateResource = null

## 点词条时弹出的菜单形态。
##
## 同一张简历被两个阶段共用，但「点词条」这件事在两边的意思是不同的：
## 面试里是去**问**（追问），组队里是去**回顾**（回忆当时的追问）。
## 所以形态由调用方声明，本控件照着摆 —— interview 保持默认，team_builder 改成 RECALL。
enum EntryMenu {
	HIDDEN,   ## 不弹菜单（拿去做纯展示时）
	ASK,      ## 「追问」：每条都能问
	RECALL,   ## 「回忆」：只有面试时**问过**的条目能点，没问过的置灰
}

## 点词条时弹什么菜单。默认 ASK = 保持面试现有的行为。
@export var entry_menu: EntryMenu = EntryMenu.ASK

## 站定的位置：_ready() 时记下来。整页的进出动画都是**相对它**算的纵向偏移，
## 偏移归零 = 回到场景里摆的那一处（和组队页共用的绝对偏移，§12.2）。
var _rest_position: Vector2 = Vector2.ZERO

## 当前纵向偏移（正 = 往下，负 = 往上，0 = 站定）
var _slide_offset: float = 0.0

## 正在跑的滑动 Tween；没有 = 待在原地
var _slide_tween: Tween = null


func _ready() -> void:
	_rest_position = position

	# interview.gd 会按阶段把本节点整块显隐（_apply_phase_visuals）。
	# 父节点隐藏时子节点只是不画，菜单自己的 visible 还是 true —— 再回到招人阶段就会「诈尸」。
	# 所以本节点一被藏起来就顺手把菜单收掉。
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)

	# 菜单里的「追问」：本控件只负责把「谁 + 第几条」广播出去，不碰对话（见 _on_ask_requested）。
	if _token_menu != null and not _token_menu.ask_requested.is_connected(_on_ask_requested):
		_token_menu.ask_requested.connect(_on_ask_requested)

	# 没人喂数据时保持空纸：场景里预摆的词条只是版面占位，不该有内容。
	# （F6 单独跑本场景看到的就是一张空简历，这是预期行为。）
	if _candidate == null:
		set_entries([])
		set_info("")


func _on_visibility_changed() -> void:
	if not is_visible_in_tree() and _token_menu != null:
		_token_menu.close()

# ---------------------------------------------------------------------------
# 数据入口
# ---------------------------------------------------------------------------


## 铺一整份简历。传 null 表示「当前没有候选人」→ 清空。
## 这是本控件唯一的业务数据入口：抬头 + 词条都从 candidate 里取。
func set_candidate(candidate: CandidateResource) -> void:
	_candidate = candidate
	if candidate == null:
		set_info("")
		set_entries([])
		return
	set_info(candidate.resume_header)
	set_entries(descriptions_of(candidate))


## 当前铺在纸上的候选人；没有则 null
func get_candidate() -> CandidateResource:
	return _candidate


## 候选人的简历条目正文（逐条 description）。喂给 set_entries()。
static func descriptions_of(candidate: CandidateResource) -> Array[String]:
	var lines: Array[String] = []
	if candidate == null:
		return lines
	for entry in candidate.resume:
		if entry != null:
			lines.append(entry.description)
	return lines


# ---- 版面 -------------------------------------------------------------------


## 换抬头。整段就是**一个**字符串 —— 从 CandidateResource.resume_header 原样搬过来，
## 怎么分行、写哪些字段都在那段字里排好了，这里不做任何拼接。
func set_info(text: String) -> void:
	_info_label.text = text


## 铺一整列词条。descriptions 里每一条 = 一条 ResumeEntry.description（§3.2）。
func set_entries(descriptions: Array) -> void:
	# 换一批词条时先把菜单收起来：它正锚着的那条可能马上就被隐藏/换内容了
	if _token_menu != null:
		_token_menu.close()

	# 场景里预摆了 5 个 ResumeToken 实例：编辑器一打开就能看到真实版面。
	# 数据条数和预摆数对不上时按数据走 —— 多的现场新建，富余的隐藏，
	# 所以「若干项」都能撑住，不用改场景。
	var placed := _token_list.get_children()
	for i in descriptions.size():
		var token: ResumeToken
		if i < placed.size():
			token = placed[i] as ResumeToken
			token.visible = true
		else:
			token = TOKEN_SCENE.instantiate() as ResumeToken
			token.name = "ResumeToken%d" % (i + 1)
			_token_list.add_child(token)
		token.set_entry(i, String(descriptions[i]))
		_connect_token(token)

	for i in range(descriptions.size(), placed.size()):
		(placed[i] as Control).visible = false


# ---- 整页的进出（§13：站定之后从下方升起 / 判定之后往上方移走）-----------------
#
# 和 interviewee.gd 的走路一样，这里只提供「怎么滑」这一个动作，
# **什么时候滑、滑到哪儿**由 interview.gd 的演出调解决定。
#
# 动的是一整页（本节点），不是只动 Paper：纸、纸上的字、词条、以及贴在最底下的
# ResumePagePhd 是同一张纸的组成部分，拆开动会散架。


## 当前纵向偏移：正 = 被推到画面下方，负 = 被推到画面上方，0 = 站定
func slide_offset() -> float:
	return _slide_offset


## 一整页的滑动行程：一个画布高度。
##
## 用 viewport 的高度而不是写死 648：纸面本身只占 62..542，一个画布高度足够
## 把它**完全**推出画面（进、出都够），而画布尺寸本来就该由 viewport 说了算。
func travel_distance() -> float:
	return get_viewport_rect().size.y


## 滑到某个纵向偏移（正 = 往下，负 = 往上），duration 秒内匀速走完。返回这个 Tween。
func slide_to(offset_y: float, duration: float) -> Tween:
	stop_slide()
	_slide_tween = create_tween()
	_slide_tween.tween_method(
		_apply_slide, _slide_offset, offset_y, duration)
	return _slide_tween


## 不给动画、立刻挪到某个偏移（摆位 / 跳过动画时用）
func snap_slide(offset_y: float) -> void:
	stop_slide()
	_apply_slide(offset_y)


## 回到站定的那一处
func stand_still() -> void:
	snap_slide(0.0)


## 是否正在滑（演出调度用它判断「到位了没有」）
##
## ⚠️ 同 Interviewee.is_walking()：判据是 `is_running()` 而不是 `is_valid()` ——
##   跑完之后 `is_valid()` 还会再真几帧。
func is_sliding() -> bool:
	return _slide_tween != null and _slide_tween.is_valid() and _slide_tween.is_running()


## 停掉滑动，停在当前这一处（收场用，不回位）
func stop_slide() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = null


## tween_method 的回调
func _apply_slide(offset_y: float) -> void:
	_slide_offset = offset_y
	position = _rest_position + Vector2(0.0, offset_y)


# ---- 词条菜单 ---------------------------------------------------------------

## 每条词条都要接上 —— 新现场 instantiate() 出来的那些也要，所以放在 set_entries 里逐条接。
func _connect_token(token: ResumeToken) -> void:
	if not token.selected.is_connected(_on_token_selected):
		token.selected.connect(_on_token_selected)


## 点了某一条词条 → 在它旁边弹出菜单（§6.2 的第一步）。
##
## 摆出来的样子由 entry_menu 决定：面试是「追问」，组队是「回忆」（没问过的置灰）。
func _on_token_selected(entry_index: int) -> void:
	if entry_menu == EntryMenu.HIDDEN:
		return
	var token := _token_list.get_child(entry_index) as Control
	if token == null or not token.visible:
		return
	# 文案与可用性都在这里定：菜单自己不知道现在是哪个阶段（它只是个控件）。
	_token_menu.set_option_text(_option_text())
	_token_menu.open_for(token, entry_index, _option_enabled(entry_index))


## 菜单里那个选项当前该显示什么字
func _option_text() -> String:
	if entry_menu == EntryMenu.RECALL:
		return "回忆"
	return ResumeTokenMenu.DEFAULT_OPTION_TEXT


## 这一条现在能不能点。
##
## 面试阶段都能问；组队阶段只有**当时真的问过**的才谈得上回忆 ——
## 「问过没有」问 GameState（§2：运行时状态一律走 GameState，不写进 ResumeEntry，
## 那是个被多个候选人共用的资源，往里写运行时状态会串味）。
func _option_enabled(entry_index: int) -> bool:
	if entry_menu != EntryMenu.RECALL:
		return true
	if _candidate == null:
		return false
	return GameState.has_asked_entry(_candidate.id, entry_index)


## 选项被点。
##
## 本控件**不播对话**：简历只负责显示与抛事件，台词由所在阶段去播
## （interview.gd 真的去问 / team_builder.gd 重播当时那段）。
## 这不是洁癖 —— `resume.tscn` 在两个场景里被复用，team_builder 那边
## 就算有 Dialoguer，播的也不是同一段东西，所以这里不能自己决定播什么。
func _on_ask_requested(entry_index: int) -> void:
	if entry_menu == EntryMenu.HIDDEN:
		return
	# 先收菜单：菜单只有巴掌大，留着会和对话框叠在一起
	_token_menu.close()

	if _candidate == null:
		push_warning("[Resume] 纸上没有候选人，这条无从问起")
		return
	if entry_index < 0 or entry_index >= _candidate.resume.size():
		push_warning("[Resume] 条目下标越界：%d（共 %d 条）" % [
			entry_index, _candidate.resume.size()])
		return
	# 同一个按钮，两个阶段发两个信号：收信号的人不必再自己判断现在是哪个阶段。
	if entry_menu == EntryMenu.RECALL:
		EventBus.resume_entry_recalled.emit(_candidate.id, entry_index)
	else:
		EventBus.resume_entry_asked.emit(_candidate.id, entry_index)


## 菜单开着的时候：点菜单外面 = 收起，Esc = 收起。
## 这里**故意不吃掉鼠标事件** —— 点到别的词条上时那条词条还得正常收到 pressed，
## 于是菜单会顺势挪到新词条旁边，这正是想要的手感。
func _input(event: InputEvent) -> void:
	if _token_menu == null or not _token_menu.is_open():
		return
	if event is InputEventMouseButton and event.pressed:
		if not _token_menu.get_global_rect().has_point(event.position):
			_token_menu.close()
	elif event.is_action_pressed("ui_cancel"):
		_token_menu.close()
		get_viewport().set_input_as_handled()
