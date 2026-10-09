class_name CandidateEntry
extends Control

## 组队界面左侧的一条「候选人头像」（ARCHITECTURE.md §4 team_builder 一节、§12）。
##
## 一条 = 圆形头像（**简单黑色纯色圆边框** + 圆形裁切的拼装立绘）+ 底下那一行名字。
## 它只管三件事：自己长什么样、鼠标记不记得住、左键点没点。其余交给上层：
##
##   hovered(entry)   鼠标移上来 → team_builder.gd 把这位的简历铺到右半边
##   toggled(entry)   左键点一下 → 上层在「已录用」名单里加上 / 去掉这一位（再点一次撤销）
##
## ⚠️ 本控件不写 GameState、也不认识简历控件：表现层只做显示与输入（§0 的核心纪律）。
## ⚠️ 头像的像素来自 PortraitComposer（和面试立绘同一套部件图），名字来自数据
##   `CandidateResource.display_name` —— 本文件里没有一句候选人相关的文案。

## 鼠标移上本条。参数是**自己**，让上层不必再去反查是哪一条。
signal hovered(entry: CandidateEntry)

## 左键点了本条（录用 ↔ 撤销由上层决定）。
signal toggled(entry: CandidateEntry)

## 圆头像直径（像素）。外圈黑边框画在这个直径之内。
const AVATAR_SIZE := 112

## 黑色纯色圆边框的线宽
const RING_WIDTH := 3.0

## 已录用的外圈：画在黑边框外面，留一圈空隙（不破坏「黑边框」本身的观感）
const HIRED_RING_GAP := 4.0

## 边框颜色：**纯黑**（要求就是「简单黑色纯色圆形边框」，别改成带透明度的灰）
const RING_COLOR := Color(0, 0, 0, 1)

## 已录用的标记色（外圈 + 名字）
const HIRED_COLOR := Color(0.76, 0.53, 0.13, 1)

## 头像底衬：立绘是白底黑描边的纸片人套色，垫一层浅色底才在夜晚色调下站得住
const BACKDROP_COLOR := Color(0.93, 0.91, 0.85, 0.9)
const BACKDROP_HOVER_COLOR := Color(1.0, 0.99, 0.94, 1.0)

## 名字颜色（未录用 / 已录用）
const NAME_COLOR := Color(0.12, 0.1, 0.09, 1)
const NAME_HIRED_COLOR := Color(0.99, 0.85, 0.5, 1)

## 锁住时的整体压暗（modulate 是**乘**上去的，所以看起来是"褪色 + 变暗"）。
## 用 modulate 而不是逐处改颜色：一处生效、头像和名字一起变暗，也不用动 _draw()。
const LOCKED_MODULATE := Color(0.52, 0.52, 0.58, 0.8)

## 本条目对应的候选人（null = 空条目，什么也不画）
var candidate: CandidateResource = null

## 是否已被标记为录用（标记的**真身**在 GameState.current_team，这里只是显示状态）
var hired: bool = false

## 是否「现在点不了」（名额已满、且本条又还没被选中）。
## 判定不是这里做的：上层用 TeamValidator 算完传进来（§0：表现层不写规则）。
var locked: bool = false

## 鼠标是否停在本条目上
var _hovered: bool = false

@onready var _avatar: TextureRect = $Avatar
@onready var _name_label: Label = $NameLabel


func _ready() -> void:
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	_refresh()


# ---------------------------------------------------------------------------
# 数据入口
# ---------------------------------------------------------------------------


## 铺一位候选人：头像按 portrait_* 配方拼圆、名字取 display_name。传 null 清空。
func set_candidate(value: CandidateResource) -> void:
	candidate = value
	_refresh()


## 显示层标记「已录用 / 已撤销」。**不写 GameState**（真身在 current_team，由上层同步下来）。
func set_hired(value: bool) -> void:
	if hired == value:
		return
	hired = value
	_refresh_name()
	queue_redraw()


func is_hired() -> bool:
	return hired


## 显示层标记「现在点不了」。**不写 GameState**，也不改变 hired。
##
## 锁住时：整块压暗 + 左键不再发 toggled。悬停**照旧有效** ——
## 玩家还得能把这一位的简历翻出来看，才谈得上决定换谁。
func set_locked(value: bool) -> void:
	if locked == value:
		return
	locked = value
	modulate = LOCKED_MODULATE if locked else Color(1, 1, 1, 1)


func is_locked() -> bool:
	return locked


## 当前头像贴图（没有候选人时为 null）。测试与调试用。
func avatar_texture() -> Texture2D:
	return _avatar.texture if _avatar != null else null


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------


func _refresh() -> void:
	_refresh_avatar()
	_refresh_name()
	queue_redraw()


func _refresh_avatar() -> void:
	if _avatar == null:
		return
	# 头像 = 拼装立绘 + 圆形裁切，size 就是圆的直径
	_avatar.texture = PortraitComposer.avatar_texture(candidate, AVATAR_SIZE)


func _refresh_name() -> void:
	if _name_label == null:
		return
	_name_label.text = "" if candidate == null else candidate.display_name
	_name_label.add_theme_color_override(
		"font_color", NAME_HIRED_COLOR if hired else NAME_COLOR
	)


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------


## 左键点一下 = 标记录用 / 再点一下撤销。
## 只认左键：右键、滚轮一概不响应（否则误触会把人选上又撤掉）。
##
## 锁住时直接不给出去：规则层（TeamValidator）也会拦住同一次点击，
## 但"点不动"应该在这儿就表达出来，而不是让玩家点了没反应。
func _gui_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			toggled.emit(self)


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()
	hovered.emit(self)


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()


# ---------------------------------------------------------------------------
# 画：底衬 + 圆边框（+ 已录用外圈）
# ---------------------------------------------------------------------------


## 头像所占的矩形。布局还没跑过时退回常量，保证第一帧就画得出来。
func _avatar_rect() -> Rect2:
	if _avatar != null and _avatar.size.x > 0.0 and _avatar.size.y > 0.0:
		return Rect2(_avatar.position, _avatar.size)
	return Rect2(
		Vector2(size.x * 0.5 - AVATAR_SIZE * 0.5, 0.0),
		Vector2(AVATAR_SIZE, AVATAR_SIZE)
	)


func _draw() -> void:
	var rect := _avatar_rect()
	var center := rect.position + rect.size * 0.5
	var radius := minf(rect.size.x, rect.size.y) * 0.5

	draw_circle(center, radius, BACKDROP_HOVER_COLOR if _hovered else BACKDROP_COLOR)

	if hired:
		draw_arc(center, radius + HIRED_RING_GAP, 0.0, TAU, 64, HIRED_COLOR, RING_WIDTH, true)

	# 黑边框画在直径之内（半径收半个线宽），否则会盖住头像的圆形边
	draw_arc(center, radius - RING_WIDTH * 0.5, 0.0, TAU, 64, RING_COLOR, RING_WIDTH, true)
