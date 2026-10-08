class_name ResumeTokenMenu
extends Control

## 点开某一条简历词条后弹出的小菜单（ARCHITECTURE.md §4 / §6.2）。
##
## 现在里面**只有一个「追问」按钮**，而且这个按钮点了没有任何后续 ——
## §6.2 的「先给 question、再展开 answer」留到 M2。这里沿用和 resume_token 一样的
## 做法：把 ask_requested 信号按架构预留好并照常 emit，但 resume.gd 目前不订阅它，
## 所以「点追问 = 什么都不发生」是当前阶段的既定行为，不是漏了。
##
## ── 画布适配 ─────────────────────────────────────────────────────────────
## 1) 面板**按纹理原生尺寸摆，不拉伸**。手绘边框拉变形会很难看；窗口缩放这件事
##    由 project.godot 的 stretch/mode=canvas_items 统一负责，不需要在这里再缩一遍。
## 2) 位置不是写死的：open_for() 现算词条的 global rect 再摆；
##    aspect=expand 下画布会随窗口比例变大变小，所以还监听 viewport 的 size_changed
##    重算一次 —— 先贴右边，右边放不下翻到左边，最后整体夹进画布，任何尺寸都不被切掉。

## 「追问」被点击。M2 接追问流程时由 resume.gd 订阅。
signal ask_requested(entry_index: int)

## 面板纹理的原生尺寸。换图要连下面 CONTENT_* 四个常量一起重新对
## （_ready() 里对不上会 push_warning）。
const PANEL_SIZE := Vector2(145.0, 223.0)

## 纹理里那块**可用白区**相对面板左上角的内边距。
## 数值是照着 resume_token_menu_phd.png 量的：手绘黑边内沿约 x24~123、y35~193，
## 顶上 y<35 还有一块装饰，所以上边距留得比另外三边大。
const CONTENT_LEFT := 26.0
const CONTENT_TOP := 40.0
const CONTENT_RIGHT := 22.0
const CONTENT_BOTTOM := 33.0

## 菜单和词条之间留的缝
const GAP := 6.0

## 当前菜单挂在哪一条词条上（从 0 开始），跟着 ask_requested 一起抛出去
var entry_index: int = 0

## 画布尺寸变化后要照它重算位置；没打开时为 null
var _anchor: Control = null

@onready var _panel: TextureRect = $Panel
@onready var _ask_button: Button = $Options/OptionList/AskButton


func _ready() -> void:
	size = PANEL_SIZE
	visible = false
	if not _ask_button.pressed.is_connected(_on_ask_pressed):
		_ask_button.pressed.connect(_on_ask_pressed)
	# 画布尺寸变化（aspect=expand 下窗口比例一变画布就会变大）后重新摆一次
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_reposition):
		vp.size_changed.connect(_reposition)

	# 换图了却忘了改 CONTENT_* 的话，按钮就会压到手绘边框上 —— 这里提前喊一声
	var tex := _panel.texture if _panel != null else null
	if tex != null and tex.get_size() != PANEL_SIZE:
		push_warning("[ResumeTokenMenu] 面板纹理实际尺寸是 %s，与 PANEL_SIZE %s 对不上；内边距要重新量" % [
			tex.get_size(), PANEL_SIZE])


## 打开菜单并摆到 anchor（被点的那条词条）旁边
func open_for(anchor: Control, index: int) -> void:
	_anchor = anchor
	entry_index = index
	visible = true
	_reposition()


func close() -> void:
	visible = false
	_anchor = null


func is_open() -> bool:
	return visible


## 摆位规则：默认贴在词条右边、与词条顶对齐；
## 右边放不下就翻到词条左边；最后整体夹进当前画布。
func _reposition() -> void:
	if not visible or _anchor == null or not is_instance_valid(_anchor):
		return
	# 面板永远按原生像素摆 —— 窗口缩放由 canvas_items 拉伸统一负责
	size = PANEL_SIZE

	var canvas := get_viewport_rect().size
	var anchor_rect := _anchor.get_global_rect()

	var pos := Vector2(anchor_rect.end.x + GAP, anchor_rect.position.y)
	if pos.x + size.x > canvas.x:
		pos.x = anchor_rect.position.x - GAP - size.x
	pos.x = clampf(pos.x, 0.0, maxf(0.0, canvas.x - size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, canvas.y - size.y))
	global_position = pos


func _on_ask_pressed() -> void:
	# 现在没有任何订阅者 → 一次空操作，菜单也不会自己关掉。M2 再说。
	ask_requested.emit(entry_index)
