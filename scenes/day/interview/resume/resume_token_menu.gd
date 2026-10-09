class_name ResumeTokenMenu
extends Control

## 点开某一条简历词条后弹出的小菜单（ARCHITECTURE.md §4 / §6.2 / §10.7）。
##
## 现在里面**只有一个选项按钮**：面试阶段它是「追问」，组队阶段它是「回忆」——
## 文案由调用方设（`set_option_text()`），点下去抛的都是 `ask_requested`；
## 「这一下到底是去问还是去回忆」由 resume.gd 按自己的模式分流
## （见 resume.gd 的 `entry_menu` / `_on_ask_requested()`）。
## 没问过的条目传 `enabled = false` 进来，按钮变灰且点不动。
##
## ── 画布适配 ─────────────────────────────────────────────────────────────
## 1) 面板**按纹理原生尺寸摆，不拉伸**。手绘边框拉变形会很难看；窗口缩放这件事
##    由 project.godot 的 stretch/mode=canvas_items 统一负责，不需要在这里再缩一遍。
## 2) 位置不是写死的：open_for() 现算词条的 global rect 再摆；
##    还监听 viewport 的 size_changed 重算一次 —— 先贴右边，右边放不下翻到左边，
##    最后整体夹进画布，任何尺寸都不被切掉。
##    注意：主画布在 project.godot 的 aspect=keep 下恒为 1152×648、不随窗口变，
##    所以这条路径平时不会触发；但 tools/smoke_resume_menu.gd 用 SubViewport
##    自己造不同尺寸的画布，靠的就是它 —— 别删。

## 选项按钮被点击（语义由 resume.gd 的 entry_menu 决定：追问 or 回忆）。
signal ask_requested(entry_index: int)

## 选项按钮的默认文案。面试阶段就是它；组队阶段会被 set_option_text() 改成「回忆」。
const DEFAULT_OPTION_TEXT: String = "追问"

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
	# 画布尺寸变化后重新摆一次。
	# 主画布在 aspect=keep 下恒为 1152×648、不随窗口变，所以平时不会触发；
	# tools/smoke_resume_menu.gd 用 SubViewport 造不同尺寸的画布，走的就是这条。
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_reposition):
		vp.size_changed.connect(_reposition)

	# 换图了却忘了改 CONTENT_* 的话，按钮就会压到手绘边框上 —— 这里提前喊一声
	var tex := _panel.texture if _panel != null else null
	if tex != null and tex.get_size() != PANEL_SIZE:
		push_warning("[ResumeTokenMenu] 面板纹理实际尺寸是 %s，与 PANEL_SIZE %s 对不上；内边距要重新量" % [
			tex.get_size(), PANEL_SIZE])


## 换选项按钮的文案（面试 = 「追问」，组队 = 「回忆」）。入树前后调用都可以。
func set_option_text(text: String) -> void:
	if _ask_button == null:
		return
	_ask_button.text = text


## 打开菜单并摆到 anchor（被点的那条词条）旁边。
##
## `enabled = false` 时选项变灰且点不动 —— 用于「这一条当时根本没问过，没什么可回忆的」。
## 菜单**照常弹出来**（而不是干脆不弹）：玩家至少能看到「哦，这条我没问」。
func open_for(anchor: Control, index: int, enabled: bool = true) -> void:
	_anchor = anchor
	entry_index = index
	if _ask_button != null:
		_ask_button.disabled = not enabled
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
	# 置灰是**看得见**的那一层；这里再挡一次，免得将来有人绕过 disabled 直接 emit。
	if _ask_button != null and _ask_button.disabled:
		return
	# 本控件只抛信号：收菜单、找 json、播对话都在订阅方（见 §10.7）。
	ask_requested.emit(entry_index)
