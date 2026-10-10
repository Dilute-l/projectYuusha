class_name Handbook
extends Control

## 手册浮层（ARCHITECTURE.md §4 / §10.4）：玩家判断简历真伪的常识依据。
##
## 只做三件事：**显示某一条目**、**关闭**、**开着的时候把别处的输入挡掉**。
## 规则一条都不在这里 —— 能不能查、解锁没解锁，由上层（interview.gd / GameState）决定。
##
## 数据来源：
##   条目 → DataDB.get_handbook_entry(id)（data/handbook/*.tres）
##   图标 → assets/art/interview/Handbook/handbook_<id>_phd.png
##   正文 → HandbookEntry.body（BBCode），直接铺进 RichTextLabel

## 图标目录。路径集中在这里，以后挪目录只改这一行。
const ICON_DIR := "res://assets/art/interview/Handbook/"

## 正文字体。
##
## ⚠️ 不设它的话正文**一个字都看不见** —— 引擎默认字体没有中文字形
## （实测 fallback_font.has_char("史") == false），而 HandbookEntry.body 是中文。
## 项目里 Silver.ttf 是带中文字形的（has_char("史") == true），所以先用它。
## 想换字体只改这一行；更好的做法是把 Silver 设成项目默认字体
## （ProjectSettings: gui/theme/custom_font），那样所有中文 UI 一起好 —— 但那会
## 改变已有的文字宽度，得整体看一眼版面。
const CONTENT_FONT_PATH := "res://assets/fonts/Silver.ttf"

## 正文颜色。**必须显式给** —— RichTextLabel 的 default_color 是纯白，
## 而手册底板是一整张白图（实测像素就是 (1,1,1,1)），白字压白底等于没字。
## 用深墨色，和简历纸上的文字（candidate.gd 的 NAME_COLOR）同一套观感。
const CONTENT_INK_COLOR := Color(0.12, 0.10, 0.09, 1.0)

## 本界面关闭了。上层（interview.gd）据此恢复别的操作。
signal closed()

@onready var _icon: Sprite2D = get_node_or_null("HandbookIcon") as Sprite2D
@onready var _content: RichTextLabel = get_node_or_null("HandbookContent") as RichTextLabel


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
		_apply_content_style()

	_install_input_blocker()
	visible = false


## 给正文挂上字体与颜色。
##
## 两样缺一不可，而且**都不能靠默认值**：
##   字体 —— 引擎默认字体没有中文字形（实测 has_char("史") == false），中文一个字都画不出来；
##   颜色 —— RichTextLabel 的 default_color 是**纯白**，而手册底板是整张白图，
##           白字压白底等于什么都看不见。
func _apply_content_style() -> void:
	if _content == null:
		return
	if ResourceLoader.exists(CONTENT_FONT_PATH):
		_content.add_theme_font_override("normal_font", load(CONTENT_FONT_PATH))
	else:
		push_error("[Handbook] 找不到正文字体：%s（退回默认字体，中文会画不出来）" % CONTENT_FONT_PATH)
	_content.add_theme_color_override("default_color", CONTENT_INK_COLOR)


## 全屏「挡板」：本界面开着时，鼠标点到哪儿都穿不到下面的场景去。
##
## 为什么放在代码里而不是场景里：根节点原来是 0 尺寸，光靠它挡不住整屏；
## 挡板必须显式铺满并设成 STOP。加为**第一个**子节点 —— Godot 的命中测试从后往前，
## 所以 quit 按钮仍然排在它之上、照常可点。
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


# ---------------------------------------------------------------------------
# 开关
# ---------------------------------------------------------------------------


## 打开并显示某一条目。条目缺失会报错并返回 false（图标缺失只报错、仍然打开）。
func open_entry(entry_id: StringName) -> bool:
	var entry := DataDB.get_handbook_entry(entry_id)
	if entry == null:
		push_error("[Handbook] data/handbook 里没有 id 为「%s」的条目" % entry_id)
		return false
	_apply_icon(entry_id)
	_apply_body(entry.body)
	visible = true
	return true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


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


func _apply_body(body: String) -> void:
	if _content == null:
		return
	_content.text = body


func _on_quit_pressed() -> void:
	close()
