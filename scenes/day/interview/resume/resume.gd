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

## 点词条时是否弹出「追问」菜单。
##
## interview 里要弹（追问是面试的核心玩法）；team_builder 复用同一张简历，
## 那边只是「翻一下看看」，不该冒出追问入口 —— 由调用方关掉（见 team_builder.gd）。
## 默认 true = 保持 interview 现有的行为，谁要关谁自己关。
@export var token_menu_enabled: bool = true


func _ready() -> void:
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


# ---- 词条菜单 ---------------------------------------------------------------


## 每条词条都要接上 —— 新现场 instantiate() 出来的那些也要，所以放在 set_entries 里逐条接。
func _connect_token(token: ResumeToken) -> void:
	if not token.selected.is_connected(_on_token_selected):
		token.selected.connect(_on_token_selected)


## 点了某一条词条 → 在它旁边弹出菜单（§6.2 的第一步）。
## 菜单里那个「追问」的后续见 _on_ask_requested。
func _on_token_selected(entry_index: int) -> void:
	# 关掉追问入口的场合（team_builder）：点词条什么也不发生。
	# 词条本身仍然可点、悬停高亮照旧，只是不弹菜单。
	if not token_menu_enabled:
		return
	var token := _token_list.get_child(entry_index) as Control
	if token == null or not token.visible:
		return
	_token_menu.open_for(token, entry_index)


## 点了菜单里的「追问」→ 把「哪位候选人 + 第几条」广播出去（§5 的 resume_entry_asked）。
##
## 本控件**不播对话**：简历只负责显示与抛事件，台词由 interview.gd 去播。
## 这不是洁癖 —— `resume.tscn` 在 `team_builder.tscn` 里也被复用（组队时要翻简历），
## 那边根本没有 Dialoguer，所以这里不能去 `get_node("../Dialoguer")`。
func _on_ask_requested(entry_index: int) -> void:
	# 入口关掉时这里也不该有动作：菜单虽然弹不出来，但别留后门
	if not token_menu_enabled:
		return
	# 先收菜单：菜单只有巴掌大，留着会和对话框叠在一起
	_token_menu.close()

	if _candidate == null:
		push_warning("[Resume] 纸上没有候选人，追问无处可问")
		return
	if entry_index < 0 or entry_index >= _candidate.resume.size():
		push_warning("[Resume] 追问的条目下标越界：%d（共 %d 条）" % [
			entry_index, _candidate.resume.size()])
		return
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
