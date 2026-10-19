class_name Resume
extends Control

## 候选人的完整简历（ARCHITECTURE.md §4「resume.tscn」、§3.1、§6.2）。
##
## 版面 = assets/art/interview/resume/resume_phder.png 这张纸，上面分几块：
##
##   姓名 / 种族 / 职业 / 性别 / 年龄   → 各自的 *Container（Label）
##   力量 / 智力 / 感知                 → Status 按钮里的 *Container
##   个人履历与奖项                     → ExperienceScroll 里一串 ResumeToken
##   专长                              → SkillScroll 里一串 ResumeToken
##   组队宣言                           → DeclarationScroll（一整段自由文本）
##   印章                              → ResumeStamp（Sprite2D；有没有图由数据决定，见 _apply_stamp）
##
## 履历 / 专长 / 组队宣言 都包在 ScrollContainer 里：内容超出栏位时
## 纵向滚动条自动出现（长句靠换行折行；子节点设了 SIZE_EXPAND_FILL 才会拉满栏宽），见 _reset_scrolls()。
##
## ⚠️ 数据来源：**全部来自 CandidateResource**（data/candidates/*.tres）。
##   本脚本里没有一句候选人文案，也没有「默认履历」这种兜底 ——
##   谁把候选人喂进来就显示谁（`set_candidate()`），喂 null 就把纸清空。
##   调用方是 interview.gd，它拿的是 GameState 当日名单（data/days/day_XX.tres）里的那一位。
##
## ⚠️ 字体：纸上的字全在**场景里**各自 `theme_override_fonts/font`（assets/fonts/youaimoshouheiti-bold.ttf），
##   所以中文能正常显示。本脚本不碰字体，改字体去改 .tscn。

const TOKEN_SCENE := preload("res://scenes/day/interview/resume/resume_token.tscn")

## 「属性追问」的条目序号。
##
## 简历上的栏目分两类：
##   · experience / skill 是**条目列表**，每条一个词条、各占一个序号（从 0 开始往上发）；
##   · 姓名 / 种族 / 职业 / 性别 / 年龄 / 三围属性是**一整块状态区**（Status 按钮那块），
##     不占条目序号 —— 但玩家点它也该能追问「你这身板是真的吗」。
##
## 所以给状态区发一个不会和真条目撞号的负数序号；它的对话文件走约定路径
## <id>_status.json（见 STATUS_ASK_FORMAT 与 ask_path_of()）。
const STATUS_ENTRY_INDEX := -1

## 约定：属性追问的对话文件。一条追问一份 json，属性这条由 id 拼出来。
const STATUS_ASK_FORMAT := "res://data/asks/%s_status.json"

## 印章节点名，**两个都认**。
##
## 场景里现在叫 `ResumeStamp`，早先叫 `ResumeStampPhd`（同一个节点，只改过名）。
## 认两个是因为「谁把 .tscn 存成哪个名字」这件事不该让印章**静默消失** ——
## 找不到节点时 _apply_stamp 会直接返回，效果就是「数据填了也不盖章」，
## 那是最难查的一类 bug。两个名字都没有才在 _ready() 里报错。
const STAMP_NODE_NAMES: Array[StringName] = [&"ResumeStamp", &"ResumeStampPhd"]

# ---- 节点 -------------------------------------------------------------------

@onready var _token_menu: ResumeTokenMenu = get_node_or_null("TokenMenu") as ResumeTokenMenu
@onready var _page: Sprite2D = get_node_or_null("ResumePagePhd") as Sprite2D
@onready var _status: Button = get_node_or_null("Status") as Button
@onready var _experience_scroll: ScrollContainer = get_node_or_null("ExperienceScroll") as ScrollContainer
@onready var _skill_scroll: ScrollContainer = get_node_or_null("SkillScroll") as ScrollContainer
@onready var _declaration_scroll: ScrollContainer = get_node_or_null("DeclarationScroll") as ScrollContainer
@onready var _experience_list: VBoxContainer = get_node_or_null("ExperienceScroll/ExperienceContainer") as VBoxContainer
@onready var _skill_list: VBoxContainer = get_node_or_null("SkillScroll/SkillContainer") as VBoxContainer

## 盖在纸上的那枚印章。显不显示、用哪张图全看 CandidateResource.resume_stamp ——
## 这里是它唯一的落点（见 _apply_stamp）。
@onready var _stamp: Sprite2D = _find_stamp()

## 各栏的「值」显示位。名字带 _value 是为了和场景里那批 *Label（栏目标题）区分开。
@onready var _name_value: Label = get_node_or_null("NameContainer") as Label
@onready var _race_value: Label = get_node_or_null("RaceContainer") as Label
@onready var _class_value: Label = get_node_or_null("ClassContainer") as Label
@onready var _gender_value: Label = get_node_or_null("GenderContainer") as Label
@onready var _age_value: Label = get_node_or_null("AgeContainer") as Label
@onready var _declaration_value: Label = get_node_or_null("DeclarationScroll/DeclarationContainer") as Label
@onready var _str_value: Label = get_node_or_null("Status/StrContainer") as Label
@onready var _int_value: Label = get_node_or_null("Status/IntContainer") as Label
@onready var _wis_value: Label = get_node_or_null("Status/WisContainer") as Label

## 当前铺在纸上的那位候选人；null = 纸是空的
var _candidate: CandidateResource = null

## 扁平序号 → 词条控件。experience 在前、skill 在后，两个列表共用一套序号。
## 菜单要锚在「被点的那一条」上，所以得能由序号反查控件。
var _tokens: Array[ResumeToken] = []

## 点词条时弹出菜单的形态。
##
## 同一张简历被两个阶段共用，而「点词条」这件事在两边的意思并不一样：
##   · 面试里是去**问**（追问）—— 点一下就该直接问，中间不必再过一手菜单；
##   · 组队里是去**回顾**（回忆当时的追问）—— 那边有的条目根本没问过，
##     需要一个"置灰、点不动"的落点，菜单就是那个落点。
## 所以形态由调用方声明，本控件照着做 —— interview 保持默认（ASK），team_builder 改成 RECALL。
enum EntryMenu {
	HIDDEN,   ## 不弹菜单、也不响应点击（拿去做纯展示时）
	ASK,      ## 「追问」：**点一下直接问**，不弹二级菜单（面试）
	RECALL,   ## 「回忆」：点一下弹菜单，只有面试时**问过**的条目能点，没问过的置灰（组队）
}

## 点词条时的行为。默认 ASK = 面试里的「点一下直接追问」。
@export var entry_menu: EntryMenu = EntryMenu.ASK

## 站定的位置：_ready() 时记下来。整页的进出动画都是**相对它**算的纵向偏移，
## 偏移重置零 = 回到场景里摆的那一处（和组队页共用的绝对偏移，§12.2）。
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

	# 状态区（力量 / 智力 / 感知 那一块）也是可追问的：点它弹同一个菜单
	if _status != null and not _status.pressed.is_connected(_on_status_pressed):
		_status.pressed.connect(_on_status_pressed)

	# 印章节点不见了就得喊：_apply_stamp 找不到节点会直接返回，
	# 表现是「数据里填了章，纸上什么都不发生」—— 不报错的话根本查不出来。
	if _stamp == null:
		push_error("[Resume] 找不到印章节点（ResumeStamp / ResumeStampPhd 都没有），resume_stamp 不会显示")

	# 没人喂数据时保持空纸：场景里预摆的词条只是版面占位，不该有内容。
	# （F6 单独跑本场景看到的就是一张空简历，这是预期行为。）
	if _candidate == null:
		_clear()


## 按 STAMP_NODE_NAMES 找印章节点；一个都没有则返回 null。
func _find_stamp() -> Sprite2D:
	for node_name in STAMP_NODE_NAMES:
		var node := get_node_or_null(NodePath(String(node_name)))
		if node is Sprite2D:
			return node
	return null


func _on_visibility_changed() -> void:
	if not is_visible_in_tree() and _token_menu != null:
		_token_menu.close()

# ---------------------------------------------------------------------------
# 数据入口
# ---------------------------------------------------------------------------


## 铺一整份简历。传 null 表示「当前没有候选人」→ 清空。
## 这是本控件唯一的业务数据入口：每一栏都从 candidate 里取，本脚本一个字都不拼。
func set_candidate(candidate: CandidateResource) -> void:
	_candidate = candidate
	if candidate == null:
		_clear()
		return
	_fill_fields(candidate)
	_fill_tokens(candidate)
	_apply_stamp(candidate)
	_reset_scrolls()


## 滚动位置归零。同一张纸会被反复喂不同的候选人（§11.2 换人时整体重刷），
## 不重置的话，下一位的简历会停在上一页滚到一半的位置。
func _reset_scrolls() -> void:
	if _experience_scroll != null:
		_experience_scroll.scroll_vertical = 0
	if _skill_scroll != null:
		_skill_scroll.scroll_vertical = 0
	if _declaration_scroll != null:
		_declaration_scroll.scroll_vertical = 0


## 当前铺在纸上的候选人；没有则 null
func get_candidate() -> CandidateResource:
	return _candidate


## 扁平序号 → 词条控件；越界返回 null。测试 / 调试用。
func token_at(entry_index: int) -> ResumeToken:
	if entry_index < 0 or entry_index >= _tokens.size():
		return null
	return _tokens[entry_index]


## 两个列表里实际铺出来的词条总数（= 可追问的条目数）。
func token_count() -> int:
	return _tokens.size()


## 两位候选人各自的**扁平条目表**：experience 在前、skill 在后。
##
## 追问对话、以及「这一条问过没有」的记录（GameState.record_entry_asked）都按这一套序号走，
## 所以两个列表共用同一套流程，不需要给 skill 另开一套机制。
## 空条目（null）在这里就被滤掉 —— 序号必须和铺出来的词条一一对应。
static func entries_of(candidate: CandidateResource) -> Array[ResumeEntry]:
	var all: Array[ResumeEntry] = []
	if candidate == null:
		return all
	for entry in candidate.experience:
		if entry != null:
			all.append(entry)
	for entry in candidate.skill:
		if entry != null:
			all.append(entry)
	return all


## 某个扁平序号对应的追问对话文件路径。
##
## **约定只写在这一处** —— interview.gd（真的去问）与 team_builder.gd（重播回忆）
## 都调它，两边不必各自记住「-1 表示属性」这件事。
## 序号越界 / 该条没写 ask_path 时返回空串。
static func ask_path_of(candidate: CandidateResource, entry_index: int) -> String:
	if candidate == null:
		return ""
	if entry_index == STATUS_ENTRY_INDEX:
		return STATUS_ASK_FORMAT % candidate.id
	var all := entries_of(candidate)
	if entry_index < 0 or entry_index >= all.size():
		return ""
	return all[entry_index].ask_path.strip_edges()


# ---- 各栏的值 ---------------------------------------------------------------


## 把姓名 / 种族 / 职业 / 性别 / 年龄 / 三围 / 组队宣言铺到各自的显示位上。
##
## race 与 job 都是资源（RaceDef / JobDef），取它们的 display_name；
## 种族那一栏走 `shown_race_name()` —— 候选人要是填了 display_race，纸面上就印那一串
## （只改显示，玩法判定仍然读 race 本身）。
## 任一为空就把那一栏清空 —— 不写「未知」这种兜底字，宁可空着，免得看不出来数据漏了。
func _fill_fields(candidate: CandidateResource) -> void:
	_set_label(_name_value, candidate.display_name)
	_set_label(_race_value, candidate.shown_race_name())
	_set_label(_class_value, candidate.job.display_name if candidate.job != null else "")
	_set_label(_gender_value, String(candidate.gender))
	_set_label(_age_value, str(candidate.age))
	# ⚠️ 这三项读的是**简历上写的那三个数**（`candidate.strength` / …），
	#    **不是** `candidate.true_strength()` —— 纸上的是他自己填的，可能吹了牛；
	#    真实值只进结算（combat_resolver.gd），从不往纸面上摆（§3.1）。
	_set_label(_str_value, str(candidate.strength))
	_set_label(_int_value, str(candidate.intelligence))
	_set_label(_wis_value, str(candidate.wisdom))
	_set_label(_declaration_value, candidate.team_declaration)


func _set_label(label: Label, text: String) -> void:
	if label != null:
		label.text = text


# ---- 印章 -------------------------------------------------------------------


## 把候选人那枚印章盖到纸上（`ResumeStamp`）。
##
## 规则只有一条，**全在数据里**（CandidateResource.resume_stamp）：
##
##   有图 → 换上这张图并显示；
##   没图 → 不显示（并且把上一次那张图**从节点上摘掉**）。
##
## 「摘掉」这一下不是多余的：同一张简历会被反复喂不同的候选人（§11.2 换人时整体重刷），
## 只改 visible 的话，下一位没章的候选人纸上不会画章、但节点里还留着上一位的图 ——
## 谁哪天顺手把它 visible 回来，就会盖出一个张冠李戴的章。空就是空。
##
## 位置 / 缩放 / centered 一律**不在这里碰**：那是版面，写在 resume.tscn 上。
func _apply_stamp(candidate: CandidateResource) -> void:
	if _stamp == null:
		return
	var texture: Texture2D = candidate.resume_stamp if candidate != null else null
	_stamp.texture = texture
	_stamp.visible = texture != null


func _clear() -> void:
	_set_label(_name_value, "")
	_set_label(_race_value, "")
	_set_label(_class_value, "")
	_set_label(_gender_value, "")
	_set_label(_age_value, "")
	_set_label(_str_value, "")
	_set_label(_int_value, "")
	_set_label(_wis_value, "")
	_set_label(_declaration_value, "")
	_fill_lists([], [])
	_apply_stamp(null)


# ---- 词条 -------------------------------------------------------------------


## 按候选人铺两个列表。experience 拿序号 0..E-1，skill 接着拿 E..E+S-1。
func _fill_tokens(candidate: CandidateResource) -> void:
	_fill_lists(_non_null(candidate.experience), _non_null(candidate.skill))


## 滤掉空条目。序号必须和铺出来的词条一一对应，所以两个列表走同一条过滤。
func _non_null(entries: Array[ResumeEntry]) -> Array[ResumeEntry]:
	var kept: Array[ResumeEntry] = []
	for entry in entries:
		if entry != null:
			kept.append(entry)
	return kept


func _fill_lists(experience: Array[ResumeEntry], skill: Array[ResumeEntry]) -> void:
	# 换一批词条时先把菜单收起来：它正锚着的那条可能马上就被隐藏/换内容了
	if _token_menu != null:
		_token_menu.close()
	_tokens.clear()
	_fill_list(_experience_list, experience)
	_fill_list(_skill_list, skill)


## 往一个容器里铺词条，序号接着 _tokens 的长度往下发。
##
## 场景里每个容器预摆了 1 个 ResumeToken（编辑器一打开就能看到真实版面）。
## 数据条数和预摆数对不上时按数据走 —— 多的现场建、富余的藏起来，所以「若干项」都撑得住。
func _fill_list(list: VBoxContainer, entries: Array[ResumeEntry]) -> void:
	if list == null:
		return
	# ⚠️ 两个下标不是一回事，别混：
	#   local —— 在本容器**预摆实例**里的位置（每个容器各自从 0 开始）
	#   index —— 扁平序号（experience 与 skill 连着往下发），喂给词条、菜单与存档记录
	# 早先这里把 index 当成 local 用：skill 容器会去找 placed[2]（它只有 1 个预摆），
	# 于是那个空实例留在原地、真词条另加一个 —— 看起来就像「专长栏是空的」。
	var placed := list.get_children()
	var local := 0
	for entry in entries:
		var index := _tokens.size()
		var token: ResumeToken
		if local < placed.size():
			token = placed[local] as ResumeToken
		else:
			token = TOKEN_SCENE.instantiate() as ResumeToken
			token.name = "%sToken%d" % [list.name, local + 1]
			list.add_child(token)
			# 加了新节点，重新取一次，保持 placed 与真实 children 对齐
			placed = list.get_children()
		local += 1
		if token == null:
			continue
		token.visible = true
		token.set_entry(index, entry.description)
		_connect_token(token)
		_tokens.append(token)

	# 这个容器里富余的预摆词条：藏起来（不是删掉，编辑器里还要看版面）
	for i in range(local, placed.size()):
		var extra := placed[i] as Control
		if extra != null and extra.get_parent() == list:
			extra.visible = false


# ---- 整页的进出（§13：站定之后从下方升起 / 判定之后往上方移走）-----------------
#
# 和 interviewee.gd 的走路一样，这里只提供「怎么滑」这一个动作，
# **什么时候滑、滑到哪儿**由 interview.gd 的演出调解决定。
#
# 动的是一整页（本节点），不是只动纸：纸、纸上的字、词条是同一张纸的组成部分，拆开动会散架。


## 当前纵向偏移：正 = 被推到画面下方，负 = 被推到画面上方，0 = 站定
func slide_offset() -> float:
	return _slide_offset


## 一整页的滑动行程。
##
## 取「一个画布高度」与「底纸底边」里**更大的那个**：
## 用 viewport 的高度而不是写死 648 —— 画布尺寸本来就该由 viewport 说了算；
## 但底纸 ResumePagePhd 是整张手绘图，`position.y + 贴图高` 可能比画布还大一点点
## （实测 9 + 648 = 657），只滑一个画布高会剩一条边留在画面顶上。
func travel_distance() -> float:
	var canvas := get_viewport_rect().size.y
	if _page == null or _page.texture == null:
		return canvas
	return maxf(canvas, _page.position.y + _page.texture.get_size().y)


## 滑到某个纵向偏移（正 = 往下，负 = 往上），duration 秒内匀速走完。返回这个 Tween。
func slide_to(offset_y: float, duration: float) -> Tween:
	stop_slide()
	_slide_tween = create_tween()
	_slide_tween.tween_method(
		_apply_slide, _slide_offset, offset_y, duration)
	# 收尾时把最终值补上：Tween 走完最后一帧、到 is_running() 变假之间还差一帧，
	# 而演出调度是照 is_sliding()（= is_running()）判断「到位了没有」的，会在这之前就往下走 ——
	# 于是纸停在离目标差一帧的地方（实测差 18px；一张整画布大的底纸就会留一条边在画面里）。
	_slide_tween.finished.connect(func() -> void: _apply_slide(offset_y))
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

## 每条词条都要接上 —— 新现场 instantiate() 出来的那些也要，所以放在 _fill_list 里逐条接。
func _connect_token(token: ResumeToken) -> void:
	if not token.selected.is_connected(_on_token_selected):
		token.selected.connect(_on_token_selected)


## 收起词条菜单。手册弹开时上层会调它 —— 菜单只有巴掌大，留着会和手册叠在一起。
func close_token_menu() -> void:
	if _token_menu != null:
		_token_menu.close()


## 点了某一条词条。
##
## **面试（ASK）：点一下就直接追问** —— 不再先弹二级菜单、再点一次"追问"（现行手感）。
## **组队（RECALL）：仍然在旁边弹菜单** —— 那边"点一下"未必有东西可回忆，
##   菜单是「这条没问过 → 置灰、点不动」这个反馈的落点（见 _option_enabled）。
func _on_token_selected(entry_index: int) -> void:
	if entry_menu == EntryMenu.HIDDEN:
		return
	if entry_index < 0 or entry_index >= _tokens.size():
		return
	var token := _tokens[entry_index]
	if token == null or not token.visible:
		return
	if entry_menu == EntryMenu.ASK:
		_on_ask_requested(entry_index)
		return
	# 「专长」那一栏在纸的右下，菜单摆它右边会盖住纸面别的内容 —— 翻到左边去。
	# 履历那栏位置更靠上，没这个问题，仍然按默认摆右边。
	_open_menu_for(token, entry_index, token.get_parent() == _skill_list)


## 点了状态区（力量 / 智力 / 感知 那一块）。
##
## 状态区不是一个词条，但它同样值得被追问一句「你这身板是真的吗」，
## 所以把它当成一个**虚拟条目**接到同一套流程上 —— 对话、记录都不用改。
##
## 面试（ASK）：和词条一样，点一下**直接追问**（序号 STATUS_ENTRY_INDEX）。
## 组队（RECALL）：仍然先弹菜单 —— 没问过的那条要置灰，菜单负责这个反馈。
## 菜单摆**左边**：状态区右边紧挨着「个人履历与奖项」那一列，摆右边会把它盖住。
func _on_status_pressed() -> void:
	if entry_menu == EntryMenu.HIDDEN or _status == null:
		return
	if entry_menu == EntryMenu.ASK:
		_on_ask_requested(STATUS_ENTRY_INDEX)
		return
	_open_menu_for(_status, STATUS_ENTRY_INDEX, true)


func _open_menu_for(anchor: Control, entry_index: int, prefer_left: bool = false) -> void:
	if _token_menu == null:
		push_error("[Resume] 找不到 TokenMenu，弹不出菜单")
		return
	# 文案与可用性都在这里定：菜单自己不知道现在是哪个阶段（它只是个控件）。
	_token_menu.set_option_text(_option_text())
	_token_menu.open_for(anchor, entry_index, _option_enabled(entry_index), prefer_left)


## 菜单里那个选项当前该显示什么字。
## （菜单现在只在组队阶段弹，所以实际上只会走到「回忆」这一支；面试点一下就直接问了。）
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
	# 序号合不合法由 ask_path_of 一处统一判：属性那条是负数，真条目是 0..N-1
	if ask_path_of(_candidate, entry_index).is_empty():
		push_warning("[Resume] 条目下标越界或没写 ask_path：%d" % entry_index)
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
