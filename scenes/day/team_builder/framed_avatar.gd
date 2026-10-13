class_name FramedAvatar
extends Control

## 一个**头像框头像**（ARCHITECTURE.md §12.4）：底板 + 裁切过的整身立绘 + 方框。
##
## 三层的摆放都以「头像框自己的 300x300 坐标系」为准（常量与换算见 `AvatarFrame`）：
##
##     Background ── 底板，实心；**头像的底色**就是它，进队染绿 / 不进队染红
##     Clip ──────── 取景窗（`clip_contents`），窗口外的像素一律不画
##       └ Portrait  候选人的整身立绘（`PortraitComposer.portrait_texture()`），
##                   按 `AvatarFrame.PORTRAIT_SCALE` 折算进本坐标系后**原位**铺开
##     Frame ─────── 方框，压在最上
##
## ⚠️ 「超出边框的部分自动截掉」就是 Clip 干的这件事：立绘按自己的坐标系铺开
##   （腿、矮人的帽檐都还在），只有取景窗里那一块露出来 —— 纵向不做任何取景 / 居中计算，
##   人物在框里的高低只由**立绘本身**决定；横向只做一件事：
##   让**立绘画布中心对上取景窗中心**（见 `_layout_layers()`，否则人会偏在窗口右边）。
##
## ⚠️ 本控件不认数据、不写状态：喂它一位候选人 + 一个底色，它就画出来。
##   「谁能进队」是规则（TeamValidator），「谁被选了」在 GameState（§0）。

## 头像底色。三态 = 组队界面上的「还没决定 / 进队 / 不进队」（§12.3）。
enum Tint {
	NONE,      ## 还没决定：底板原色
	APPROVED,  ## 进队：绿
	REJECTED,  ## 不进队：红
}

## 底板染色：底板本身是白色的，乘上去就是纯色底
const TINT_COLORS := {
	Tint.NONE: Color(1.0, 1.0, 1.0, 1.0),
	Tint.APPROVED: Color(0.33, 0.78, 0.38, 1.0),
	Tint.REJECTED: Color(0.86, 0.28, 0.26, 1.0),
}

## 默认渲染边长（像素）。版面用 `set_pixel_size()` 改，三层一起跟着换。
const DEFAULT_SIZE := 128

## 头像框渲染出来的边长（= 整个控件是 size x size 的正方形）
var pixel_size: int = DEFAULT_SIZE

## 铺在位上的候选人（null = 空位：只有底板和框，不画人）
var candidate: CandidateResource = null

## 当前底色（Tint）
var tint: Tint = Tint.NONE

@onready var _background: TextureRect = $Background
@onready var _clip: Control = $Clip
@onready var _portrait: TextureRect = $Clip/Portrait
@onready var _frame: TextureRect = $Frame


func _ready() -> void:
	_apply_size()
	_refresh()


# ---------------------------------------------------------------------------
# 数据入口
# ---------------------------------------------------------------------------


## 换头像尺寸（像素边长）。三层美术一起按比例摆过去。
func set_pixel_size(px: int) -> void:
	pixel_size = maxi(px, 1)
	_apply_size()


## 铺一位候选人（null = 空位）。立绘来自数据里的配方，本控件不认识候选人。
func set_candidate(value: CandidateResource) -> void:
	candidate = value
	_refresh_portrait()


## 换底色：进队绿 / 不进队红 / 还没决定原色。
func set_tint(value: Tint) -> void:
	tint = value
	_refresh_tint()


func is_empty() -> bool:
	return candidate == null


## 当前贴的立绘（空位为 null）。自检用。
func portrait_texture() -> Texture2D:
	return _portrait.texture if _portrait != null else null


## 取景窗控件本身。自检用（要验「窗外的像素画不出来」）。
func clip_control() -> Control:
	return _clip


## 底板控件本身。自检用（要验底色）。
func background_control() -> TextureRect:
	return _background


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------


func _refresh() -> void:
	_refresh_portrait()
	_refresh_tint()


func _refresh_portrait() -> void:
	if _portrait == null:
		return
	# 整身立绘：按自己的画布原位铺开，**不取景也不裁圆**（§12.4）
	_portrait.texture = PortraitComposer.portrait_texture(candidate)
	# 换人 / 第一次拿到贴图之后把矩形再算一遍：尺寸依赖画布常量，与贴图本身无关，
	# 但空位 → 有人的切换必须让新贴图落在**算好的**那个矩形里。
	_layout_layers(_render_size())


func _refresh_tint() -> void:
	if _background == null:
		return
	_background.self_modulate = TINT_COLORS.get(tint, Color(1, 1, 1, 1))


# ---------------------------------------------------------------------------
# 版面：三层按同一个缩放系数摆（换尺寸只走这里）
# ---------------------------------------------------------------------------


func _apply_size() -> void:
	var px := float(pixel_size)
	custom_minimum_size = Vector2(px, px)
	# 父节点是普通 Control 时容器不会帮忙摆，这里自己定尺寸；
	# 在 HBoxContainer 里时容器会覆盖它，而容器给的最小尺寸就是上面这个。
	size = Vector2(px, px)
	_layout_layers(_render_size())


## 三层实际按多大摆：容器说了算（它可能把控件撑得比 pixel_size 大），
## 没人摆过（还没进树 / size 还是 0）时才退回 pixel_size。
func _render_size() -> float:
	return size.x if size.x > 0.0 else float(pixel_size)


func _layout_layers(px: float) -> void:
	if _background == null:
		return
	# 底板与方框都铺满整个头像框（它们自己带透明边，照原样摆即可）
	_background.position = Vector2.ZERO
	_background.size = Vector2(px, px)
	_frame.position = Vector2.ZERO
	_frame.size = Vector2(px, px)

	# 取景窗：方框内沿围出来的那一块。
	var window := AvatarFrame.window_rect(px)
	_clip.position = window.position
	_clip.size = window.size

	# 立绘有自己的画布（PortraitComposer.CANVAS × CANVAS_H），先按 k 折算成控件尺寸。
	var k := px / float(AvatarFrame.CANVAS) * AvatarFrame.PORTRAIT_SCALE
	var portrait_size := Vector2(PortraitComposer.CANVAS, PortraitComposer.CANVAS_H) * k

	# ⚠️ **画布中心对窗口中心**，不是「两个左上角对齐」。
	#
	# 立绘里的人物都画在立绘画布的正中（各部件 bbox 中心 x ≈ 288~304，即画布中心 300），
	# 而取景窗自己的中心在头像框坐标系的 x = 26 + 254/2 = 153 —— 拿两个原点对齐，
	# 画布中心就会落在窗口右侧 71% 的地方（160px 的头像上偏右约 28px），看着就是「人偏在右边」。
	# 错开多少 = (窗口宽 - 立绘折算后的宽) / 2，按头像框坐标系算，与渲染边长 px 无关。
	#
	# 纵向仍然按窗口原点垫进去：脸在画布上的高度是各画各的（矮人那张脸就在画布最底部，
	# 是他「大帽子」的既定观感，见 AvatarFrame.PORTRAIT_SCALE），不做任何自动垂直居中。
	var offset_x := _portrait_center_offset_x(window, portrait_size)
	_portrait.position = Vector2(offset_x, -window.position.y)
	_portrait.size = portrait_size
	# 贴图**铺满**这个矩形（而不是 keep_aspect_centered：那样贴图会在矩形里居中留边，
	# 于是「画布原点」不再等于立绘矩形的原点，按 -窗口原点 垫进去的算法就错位了）。
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE


## 让「立绘画布中心」落在「取景窗中心」所需的水平位移（控件坐标）。
##
## 自检直接对这个不变量下断言（画布中心 == 窗口中心），改版面时不会悄悄偏回去。
func _portrait_center_offset_x(window: Rect2, portrait_size: Vector2) -> float:
	return window.position.x + (window.size.x - portrait_size.x) * 0.5


func _notification(what: int) -> void:
	# 尺寸被容器改了也要把三层重新摆一遍（否则立绘会从取景窗里滑出去）。
	# 这里**只摆子节点、不动自己的 size** —— 动了自己会再发一次 RESIZED，转不出来。
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_layers(_render_size())
