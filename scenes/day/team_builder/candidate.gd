class_name CandidateEntry
extends Control

## 组队界面左侧的一条「候选人头像框」（ARCHITECTURE.md §12.2）。
##
## 一条 = 一个方头像框（`FramedAvatar`：底板 + **裁切过的**整身立绘 + 方框）
##        + 两个**藏在他身后**的按钮：
##
##     ApproveButton ── 进队；展开时从「被头像挡住」的位置向**右**滑出来
##     RejectButton  ── 不进队；展开时向**左**滑出来
##
## ⚠️ 两个按钮排在头像**之前**（CanvasItem 按树序绘制），所以收起来的时候是真的
##   被头像压住，而不是靠调 alpha 淡出 —— 「从底下滑出来」这件事靠的就是这个顺序，
##   别把 Avatar 挪到按钮前面。
##
## ⚠️ 本控件不写 GameState、也不认识简历控件：左键点头像只报「点了谁」，
##   进队 / 不进队由上层（team_builder.gd）落状态，再把底色推回来（§0）。

## 左键点了头像本身（展开 / 收起两个按钮由上层决定谁展开）
signal selected(entry: CandidateEntry)

## 点了「进队」
signal approved(entry: CandidateEntry)

## 点了「不进队」
signal rejected(entry: CandidateEntry)

## 头像框渲染边长（像素）。头像框是正方形，三层美术按 `AvatarFrame` 的换算一起缩放。
const AVATAR_SIZE := 160

## 两个按钮渲染出来的**宽度**（高度按美术自己的宽高比跟着算，见 AvatarFrame.size_for_width）
const BUTTON_WIDTH := 96.0

## 按钮滑出来之后，仍然压在头像框底下的那一段（像素）。
## 留一点重叠才有「从框底下滑出来」的感觉；留成 0 就是凭空贴上去。
const BUTTON_OVERLAP := 14.0

## 滑出 / 收回的时长（秒）
const SLIDE_TIME := 0.16

## 本条目对应的候选人（null = 空位，什么都不画）
var candidate: CandidateResource = null

## 当前判定：还没决定 / 进队（绿）/ 不进队（红）。**只是显示状态**，
## 真身在 GameState（进队 = current_team，不进队 = rejected_ids），由上层同步下来。
var decision: FramedAvatar.Tint = FramedAvatar.Tint.NONE

## 两个按钮有没有滑出来
var _expanded: bool = false

## 名额满了没有。满了就把「进队」按钮置灰（「不进队」照旧可点）——
## 判定是规则，由上层用 TeamValidator 算完传进来（§0）。
var _team_full: bool = false

## 正在跑的那次滑动。换向时先把上一次杀掉，否则两个 tween 会互相打架
var _tween: Tween = null

@onready var _avatar: FramedAvatar = $Avatar
@onready var _approve: TextureButton = $ApproveButton
@onready var _reject: TextureButton = $RejectButton


func _ready() -> void:
	_setup_buttons()
	custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	size = custom_minimum_size
	_avatar.set_pixel_size(AVATAR_SIZE)
	if not _approve.pressed.is_connected(_on_approve_pressed):
		_approve.pressed.connect(_on_approve_pressed)
	if not _reject.pressed.is_connected(_on_reject_pressed):
		_reject.pressed.connect(_on_reject_pressed)
	_place_buttons(_collapsed_positions(), false)


# ---------------------------------------------------------------------------
# 数据入口
# ---------------------------------------------------------------------------


## 铺一位候选人：整身立绘给头像框（不居中、不缩放，超出的部分由取景窗切掉）。
## 传 null = 空位，只留底板和方框。
func set_candidate(value: CandidateResource) -> void:
	candidate = value
	_avatar.set_candidate(value)


## 换判定：进队绿 / 不进队红 / 还没决定原色。**不写 GameState**。
func set_decision(value: FramedAvatar.Tint) -> void:
	decision = value
	_avatar.set_tint(value)
	_refresh_approve_enabled()


## 名额满了没有（上层用 TeamValidator 判定后传进来）
func set_team_full(full: bool) -> void:
	if _team_full == full:
		return
	_team_full = full
	_refresh_approve_enabled()


## 展开 / 收起两个按钮（带滑动）。判定过的条目再点一次就能重新展开改主意。
func set_expanded(value: bool) -> void:
	if _expanded == value:
		return
	_expanded = value
	_place_buttons(_expanded_positions() if _expanded else _collapsed_positions(), true)


func is_expanded() -> bool:
	return _expanded


func is_approved() -> bool:
	return decision == FramedAvatar.Tint.APPROVED


func is_rejected() -> bool:
	return decision == FramedAvatar.Tint.REJECTED


# ---------------------------------------------------------------------------
# 查询（上层与自检用）
# ---------------------------------------------------------------------------


## 头像框控件本身（要看底色 / 取景窗 / 立绘就找它）
func framed_avatar() -> FramedAvatar:
	return _avatar


func approve_button() -> TextureButton:
	return _approve


func reject_button() -> TextureButton:
	return _reject


## 按钮「滑出来」之后应该在的位置（上层与自检拿来比对动画终点）
func expanded_positions() -> Dictionary:
	return _expanded_positions()


## 按钮「收进头像底下」时的位置
func collapsed_positions() -> Dictionary:
	return _collapsed_positions()


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------


## 左键点头像本身 = 展开 / 收起两个按钮。只认左键（右键、滚轮一律不响应）。
##
## 按钮是子控件，点它们不会走到这里 —— 这里收到的只可能是头像那一块。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			selected.emit(self)


func _on_approve_pressed() -> void:
	approved.emit(self)


func _on_reject_pressed() -> void:
	rejected.emit(self)


# ---------------------------------------------------------------------------
# 按钮：贴图 / 位置 / 滑动
# ---------------------------------------------------------------------------


## 按钮贴图从 `AvatarFrame` 来：整张 300x300 里**真的有画**的那一块裁出来
## （透明留白不裁掉的话，按钮会带着一圈空白，既摆不准也点不到）。
func _setup_buttons() -> void:
	var button_size := AvatarFrame.size_for_width(AvatarFrame.APPROVE_ART, BUTTON_WIDTH)
	for spec in [
		{ "button": _approve, "path": AvatarFrame.APPROVE_BUTTON_PATH, "art": AvatarFrame.APPROVE_ART },
		{ "button": _reject, "path": AvatarFrame.REJECT_BUTTON_PATH, "art": AvatarFrame.REJECT_ART },
	]:
		var button: TextureButton = spec["button"]
		var art: Rect2 = spec["art"]
		var atlas := AtlasTexture.new()
		atlas.atlas = load(spec["path"])
		atlas.region = art
		button.texture_normal = atlas
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_SCALE
		button.size = AvatarFrame.size_for_width(art, BUTTON_WIDTH)
	# 两个按钮共用同一个高度（两张美术裁出来都是 222x144），竖着居中压在头像腰上
	for button in [_approve, _reject]:
		button.position = Vector2(button.position.x, (AVATAR_SIZE - button_size.y) * 0.5)


## 收起来：两个按钮都躲进头像框中间（整个矩形都在头像底下 → 一点都看不见）
func _collapsed_positions() -> Dictionary:
	var x := (AVATAR_SIZE - BUTTON_WIDTH) * 0.5
	var y := _approve.position.y
	return { "approve": Vector2(x, y), "reject": Vector2(x, y) }


## 展开：approve 向右滑到头像框右边、reject 向左滑到左边，各留 BUTTON_OVERLAP 压着
func _expanded_positions() -> Dictionary:
	var y := _approve.position.y
	return {
		"approve": Vector2(AVATAR_SIZE - BUTTON_OVERLAP, y),
		"reject": Vector2(-BUTTON_WIDTH + BUTTON_OVERLAP, y),
	}


func _place_buttons(targets: Dictionary, animate: bool) -> void:
	if _approve == null or _reject == null:
		return
	_apply_button_input()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate:
		_approve.position = targets["approve"]
		_reject.position = targets["reject"]
		return
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_approve, "position", targets["approve"], SLIDE_TIME)
	_tween.tween_property(_reject, "position", targets["reject"], SLIDE_TIME)


## 谁能吃到鼠标。
##
## ⚠️ 收起来的时候必须把按钮从鼠标拾取里摘掉：它们此刻正躺在头像底下（绘制顺序在头像
##   之前），虽然看不见，但 GUI 拾取是**从树尾往树头**找的 —— 留着 STOP 的话，
##   玩家点头像那一下会打到那颗看不见的按钮上（一点就把人进队了）。绘制顺序管「看不看得见」，
##   这个管「点不点得到」，两件事要一起对。
## 置灰的「进队」同理：按不动就别拦着，让这一下落到头像上去（展开 / 收起）。
func _apply_button_input() -> void:
	if _approve == null or _reject == null:
		return
	var approve_live := _expanded and not _approve.disabled
	_approve.mouse_filter = Control.MOUSE_FILTER_STOP if approve_live else Control.MOUSE_FILTER_IGNORE
	_reject.mouse_filter = Control.MOUSE_FILTER_STOP if _expanded else Control.MOUSE_FILTER_IGNORE


## 名额满了、且这一位又还没进队 → 「进队」按不动（免得点了没反应）。
## 「不进队」永远可点：撤销从来不该被名额挡住（同 TeamValidator 的约定）。
func _refresh_approve_enabled() -> void:
	if _approve == null:
		return
	_approve.disabled = _team_full and not is_approved()
	_apply_button_input()
