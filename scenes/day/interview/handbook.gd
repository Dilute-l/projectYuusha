class_name Handbook
extends Control

## 手册浮层（ARCHITECTURE.md §4 / §10.4）：玩家判断简历真伪的常识依据。
##
## 做四件事：**组装可翻阅的条目列表**、**翻页**、**铺当前页**（标题 + 正文）、
## **开着时把别处的输入挡掉**。
##
## ⚠️ 本控件不持有真身，只持有一份**视图快照**：
##   条目数据 → DataDB（data/handbook/*.tres）
##   解锁状态 → GameState（handbook_unlocked / 天数 / 累计分 / 录用数）
##   「谁该出现」的规则 → scripts/core/flow/unlock_schedule.gd（§0：规则不在表现层）
##   所以列表是**每次 open_entry() 现算**的，解锁了新条目下次打开就能翻到。

## 图标目录。路径集中在这里，以后挪目录只改这一行。
const ICON_DIR := "res://assets/art/interview/Handbook/"

## 手册的**封面页**（= 第一条，讲怎么识别真假印章的那一页）。
##
## 它照样是一条普通条目（`data/handbook/stamp.tres`，`unlock_condition` 为空 =
## **一开始就有**），所以不需要任何特殊通道 —— 这里只记住它的 id，
## 把「打开手册先看封面」这条约定收在一处。
##
## ⚠️ 页序 = 解锁顺序（`GameState.get_handbook_unlock_order()`）。封面是唯一
##   无条件条目，按「条件最早哪天成立 + id 兜底」排序后恒为**第 0 页** ——
##   这正是「每次从封面开始翻」能成立的前提。哪天给它加了条件，它会被挤到后面去。
const COVER_ENTRY_ID := &"stamp"

## 翻页按钮的**可点区域**：边长（画布坐标），两个按钮各贴一个下角。
##
## 为什么要在代码里给：美术切好的 texture_click_mask 精确到笔画本身
## （next 65×52 @ (1016,547)、last 66×39 @ (75,555)），鼠标偏几个像素就点不中，手感很差。
## 这里把判定换成 200×200 的正方形 —— **只换判定，不碰画面**：按钮仍是整块画布、
## 贴图与显隐逻辑一个字没动，两个箭头也仍然落在各自的方块里。
## 想调手感只改这一个数字。
const PAGE_HITBOX_SIDE := 200

## 标题与正文的字体。
##
## ⚠️ 不设它的话标题和正文**一个字都看不见** —— 引擎默认字体没有中文字形
## （实测 fallback_font.has_char("史") == false），而 HandbookEntry.title / body 都是中文。
## 项目里 Silver.ttf 是带中文字形的（has_char("史") == true），所以先用它。
## 想换字体只改这一行；更好的做法是把 Silver 设成项目默认字体
## （ProjectSettings: gui/theme/custom_font），那样所有中文 UI 一起好 —— 但那会
## 改变已有的文字宽度，得整体看一眼版面。
##
## 注：**字号与颜色不在这里** —— 它们是版面的组成部分，写在 handbook.tscn 的
## Theme Overrides 上（代码里再覆盖一次会让 Inspector 的调整失效）。
## ⚠️ 但字体本身必须在这里挂：Theme Overrides 里只写得出字号，写不出「换一个字体」，
## 而默认字体没有中文字形（标题是中文，会整条消失）。
const CONTENT_FONT_PATH := "res://assets/fonts/Silver.ttf"

## 本界面关闭了。上层（interview.gd）据此恢复别的操作。
signal closed()

@onready var _icon: Sprite2D = get_node_or_null("HandbookIcon") as Sprite2D
@onready var _title: Label = get_node_or_null("HandbookTitle") as Label
@onready var _content: RichTextLabel = get_node_or_null("HandbookContent") as RichTextLabel
@onready var _next_page: TextureButton = get_node_or_null("nextpage") as TextureButton
@onready var _last_page: TextureButton = get_node_or_null("lastpage") as TextureButton

## 本次打开时可供翻阅的条目（视图快照，**顺序 = 解锁顺序**，新解锁的在最后）。
## 真身是 DataDB（数据）+ GameState 的解锁账本（顺序），这里只是组装成「能翻的几页」。
var _entries: Array[HandbookEntry] = []

## 当前看到第几页（_entries 的下标）
var _index: int = 0


func _ready() -> void:
	# ⚠️ 这里为什么用**显式尺寸**而不是 FULL_RECT 锚点：
	# 本控件在场景里是 0 尺寸、锚点全 0，而它的父节点（interview.tscn 的根 Control）
	# **自己也是 0×0** —— 在 0 尺寸的父节点里设全屏锚点，算出来仍然是 0×0。
	# 所以直接按画布尺寸给大小。子节点都是位置模式（layout_mode = 0），不受影响。
	var canvas := get_viewport_rect().size
	size = canvas
	position = Vector2.ZERO

	# 正文支持 BBCode（HandbookEntry.body 就是那么写的），而 RichTextLabel 的
	# bbcode_enabled 默认是 false —— 不打开的话标签会原样显示成一堆方括号。
	if _content != null:
		_content.bbcode_enabled = true
	_apply_fonts()

	_install_input_blocker()
	_install_page_hitboxes()
	visible = false


## 给标题与正文挂上带中文字形的字体（理由见 CONTENT_FONT_PATH）。
##
## 两处都要挂，而且是**只在这里挂字体、不在这里改字号**：
## 换字体 Theme Overrides 表达不了，字号则是版面 —— 见 handbook.tscn。
## 字体缺失就报错、退回默认字体 —— 默认字体画不出中文，但至少不会崩。
func _apply_fonts() -> void:
	if not ResourceLoader.exists(CONTENT_FONT_PATH):
		push_error("[Handbook] 找不到正文字体：%s（退回默认字体，中文会画不出来）" % CONTENT_FONT_PATH)
		return
	var font: Font = load(CONTENT_FONT_PATH)
	if _content != null:
		_content.add_theme_font_override("normal_font", font)
	if _title != null:
		_title.add_theme_font_override("font", font)


## 全屏「挡板」：本界面开着时，鼠标点到哪儿都穿不到下面的场景去。
##
## 为什么放在代码里而不是场景里：根节点原来是 0 尺寸，光靠它挡不住整屏；
## 挡板必须显式铺满并设成 STOP。加为**第一个**子节点 —— Godot 的命中测试从后往前，
## 所以 quit / 翻页按钮仍然排在它之上、照常可点。
func _install_input_blocker() -> void:
	if has_node("InputBlocker"):
		return
	var blocker := Control.new()
	blocker.name = "InputBlocker"
	# 同样用显式尺寸 —— 理由见 _ready() 的注释：
	# 祖先链上有 0 尺寸的 Control，设全屏锚点算出来还是 0×0。
	blocker.position = Vector2.ZERO
	blocker.size = get_viewport_rect().size
	# STOP = 吃掉落在它身上的鼠标事件，不让它继续往下传
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	move_child(blocker, 0)


## 把两个翻页按钮的可点区域换成「贴下角的大正方形」（理由见 PAGE_HITBOX_SIDE）。
##
## 为什么是运行时生成而不是美术切一张方块 mask：mask 是 1152×648 的位图 .tres（120KB 文本），
## 两张就得再进仓库两份死数据；而这里一行 create + set_bit_rect 就够，还能跟着画布尺寸走。
##
## ⚠️ 两个按钮的 rect 都是整块画布（贴图就是整张 1152×648），所以它们**完全重叠**：
## 能不能点得中**只由 mask 决定**。换成两个对角方块之后它们才互不遮挡 ——
## 这也是为什么方块必须贴角、不能都堆在中间。
##
## 场景（handbook.tscn）里仍然挂着美术切的那张 mask：它是**兜底** ——
## 万一这段脚本没跑起来，判定退回旧的手感，总好过整块画布都能点。
func _install_page_hitboxes() -> void:
	var canvas := Vector2i(get_viewport_rect().size)
	var side := mini(PAGE_HITBOX_SIDE, mini(canvas.x, canvas.y))
	_install_square_hitbox(_next_page, canvas, Rect2i(canvas.x - side, canvas.y - side, side, side))
	_install_square_hitbox(_last_page, canvas, Rect2i(0, canvas.y - side, side, side))


## 给一个翻页按钮装上「只有 rect 那块正方形为真」的点击遮罩。
## mask 的尺寸必须与贴图一致（TextureButton 的约定），所以整张按画布大小开。
func _install_square_hitbox(button: TextureButton, canvas: Vector2i, rect: Rect2i) -> void:
	if button == null:
		return
	var mask := BitMap.new()
	mask.create(canvas)
	mask.set_bit_rect(rect, true)
	button.texture_click_mask = mask


# ---------------------------------------------------------------------------
# 开关
# ---------------------------------------------------------------------------


## 打开手册，**每次都从封面页开始**。
##
## 这是手册唯一的对外开法（`interview.gd` 的按钮走这里）。想「翻到某一条」时
## 用 open_entry()，那是另一条路 —— 目前还没人用，留给以后的关键词检索 / 图鉴跳转。
func open() -> bool:
	return open_entry(COVER_ENTRY_ID)


## 打开手册，并翻到 entry_id 那一页。
## 该条目现在不可见（条件没满足）时退回第一页；一条可看的都没有就返回 false。
##
## ⚠️ 「打开手册先看封面」这条约定不在这里 —— 它走 open()，别让调用方各自传 id：
##   传进来的是哪个条目就翻到哪个，是**刻意**留的能力（将来点图鉴跳页要用）。
func open_entry(entry_id: StringName) -> bool:
	_build_entries()
	if _entries.is_empty():
		push_warning("[Handbook] 现在没有任何可翻阅的条目（解锁条件都没满足？）")
		return false

	var page := _find_page(entry_id)
	if page < 0:
		# 条目不存在、或者现在还没解锁 —— 不报错，安静地从第一页开始
		page = 0
	_show_page(page)
	visible = true
	return true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## 当前这一页的条目（没有可看条目时为 null）。测试 / 调试用。
func current_entry() -> HandbookEntry:
	if _index < 0 or _index >= _entries.size():
		return null
	return _entries[_index]


## 当前可翻阅的条目数（= 页数）
func page_count() -> int:
	return _entries.size()


# ---------------------------------------------------------------------------
# 组页
# ---------------------------------------------------------------------------


## 把「现在能看哪些条目」组装出来，**顺序就是解锁顺序**。
##
## 每次都重新算：条件看的是当天状态，玩家换了一天再打开就该多出条目。
## 顺序取自 GameState 的解锁账本（有序）：新登记的 append 在末尾，
## 于是**新解锁的条目排在最后一页** —— 这正是想要的翻阅手感。
##
## ⚠️「谁该出现」这条规则**不在这里** —— 它在 scripts/core/flow/unlock_schedule.gd，
## 由 GameState.record_handbook_unlocks() 落地进账本；本控件只负责读账本、铺页面。
func _build_entries() -> void:
	# 先让账本落地：条件已满足但还没登记的条目补进去（幂等）
	GameState.record_handbook_unlocks()

	_entries.clear()
	for entry_id in GameState.get_handbook_unlock_order():
		var entry := DataDB.get_handbook_entry(entry_id)
		if entry != null:
			_entries.append(entry)


func _find_page(entry_id: StringName) -> int:
	for i in _entries.size():
		if _entries[i].id == entry_id:
			return i
	return -1


# ---------------------------------------------------------------------------
# 翻页
# ---------------------------------------------------------------------------


## 翻开第 index 页（会自动夹进合法范围），并铺上图标、标题与正文。
func _show_page(index: int) -> void:
	if _entries.is_empty():
		return
	_index = clampi(index, 0, _entries.size() - 1)
	var entry := _entries[_index]
	_apply_icon(entry.id)
	_apply_title(entry.title)
	_apply_body(entry.body)
	_refresh_page_buttons()


## 边界上把对应的按钮藏起来：第一页没有「上一页」，最后一页没有「下一页」。
##
## 藏起来的 Control 收不到鼠标输入，所以点击会落到下面的全屏挡板上 —— 不用额外处理。
func _refresh_page_buttons() -> void:
	if _last_page != null:
		_last_page.visible = _index > 0
	if _next_page != null:
		_next_page.visible = _index < _entries.size() - 1


func _on_nextpage_pressed() -> void:
	if _index < _entries.size() - 1:
		_show_page(_index + 1)


func _on_lastpage_pressed() -> void:
	if _index > 0:
		_show_page(_index - 1)


# ---------------------------------------------------------------------------
# 铺内容
# ---------------------------------------------------------------------------


## 图标按 id 拼：handbook_<id>_phd.png
func _apply_icon(entry_id: StringName) -> void:
	if _icon == null:
		return
	var path := ICON_DIR + "handbook_%s_phd.png" % entry_id
	if not ResourceLoader.exists(path):
		push_error("[Handbook] 找不到图标：%s" % path)
		_icon.texture = null
		return
	_icon.texture = load(path)


## 标题。字号 / 颜色 / 位置都是版面，写在 handbook.tscn 的 Theme Overrides 上；
## 这里只负责把当前条目的名字放上去（换页要跟着换，不然会停在上一条的名字上）。
func _apply_title(title: String) -> void:
	if _title == null:
		return
	_title.text = title


func _apply_body(body: String) -> void:
	if _content == null:
		return
	_content.text = body


func _on_quit_pressed() -> void:
	close()
