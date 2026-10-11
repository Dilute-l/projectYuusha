class_name TeamBuilderUI
extends Control

## 组队界面的 UI 容器（ARCHITECTURE.md §12）。
##
## 版面（§12.5）：
##
##     左边     今日**通过面试**的候选人，一人一个**方头像框**（candidate.tscn）
##     右边     简历（复用面试那一页 resume.tscn），**一进来是空的**，点过头像才铺
##     右下角   当天的名额空位：几个格子 = 今天最多能带几个人；进队的人依次填进去
##
## 交互（§12.3）：**左键点头像** → 那一条的两个按钮从头像底下滑出来（approve 向右、
## reject 向左）+ 右半边铺出他的简历 + 右下角露出名额空位。点了 approve / reject 之后
## 按钮收回去，再点一次头像就能重新展开改主意。
##
## 数据全部由 team_builder.gd 灌进来（`set_candidates` / `set_decisions` / `set_slots`），
## 本控件**不读 GameState**；玩家操作也只往外抛三个信号：
##
##   candidate_selected(candidate)   左键点了某一位的头像 → 上层铺简历
##   candidate_approved(candidate)   点了「进队」   → 上层往 GameState.current_team 里加
##   candidate_rejected(candidate)   点了「不进队」 → 上层记进 GameState.rejected_ids
##
## 「谁算进队」的判定不在这里 —— 这里只负责把底色画出来（表现层不写规则，§0）。

## 左键点了某一位的头像
signal candidate_selected(candidate: CandidateResource)

## 点了「进队」
signal candidate_approved(candidate: CandidateResource)

## 点了「不进队」
signal candidate_rejected(candidate: CandidateResource)

const ENTRY_SCENE := preload("res://scenes/day/team_builder/candidate.tscn")

## 名额空位用的就是头像框本身（空位 = 没铺人的 FramedAvatar）
const SLOT_SCENE := preload("res://scenes/day/team_builder/framed_avatar.tscn")

## ---- 左边头像列（§12.5）----
## 头像列从左上角往下排。一条 160 高、行距 176，三条正好 28〜540，
## 避开下面那颗「组队完成」按钮（y 572 起）。
const ENTRY_LEFT := 116.0
const ENTRY_TOP := 28.0
const ENTRY_PITCH := 176.0

## ---- 右下角的名额空位（§12.5）----
## 位置贴屏幕右下角、**躲在简历纸下缘之下**（纸面占 y 29〜585），所以空位定在 60px。
const SLOT_SIZE := 60
const SLOT_GAP := 10.0
const SLOT_RIGHT_MARGIN := 24.0
const SLOT_BOTTOM_MARGIN := 2.0

@onready var _roster: Control = $Roster
@onready var _slots: Control = $Slots

## 当日名额（来自 DayConfig.slots）；<= 0 = 数据还没填 → 不摆空位
var _slots_count: int = 0

## 已经进队 / 已经否掉的 id（真身在 GameState，这里只是显示用的副本）
var _approved: Array[StringName] = []
var _rejected: Array[StringName] = []

## 名额满了没有。**由上层用 TeamValidator 判定后传进来**（§0：规则不在这儿重算）
var _team_full: bool = false

## 现在展开着按钮的那一条（同一时刻只展开一条）
var _expanded: CandidateEntry = null

## 本次铺进来的候选人：id → 资源。右下角的空位要用它把人铺进格子里，
## 而本控件不读 GameState，只能记住上层给过它的这几个人。
var _candidates: Dictionary = {}


func _ready() -> void:
	_layout_entries()
	_refresh_slots()


# ---------------------------------------------------------------------------
# 数据入口（由 team_builder.gd 调用）
# ---------------------------------------------------------------------------


## 铺今日**通过面试**的候选人。顺序即出场顺序（= GameState.passed_ids 的顺序）。
##
## 场景里预摆了 3 个条目（编辑器打开就能看到版面），数据条数和它对不上时按数据走：
## 多的现场 instantiate，少的多余项隐藏 —— 所以「今天几个人」都不用回头改场景。
func set_candidates(candidates: Array[CandidateResource]) -> void:
	if _roster == null:
		return
	_expanded = null
	_candidates.clear()
	var placed := _roster.get_children()
	for i in candidates.size():
		var entry: CandidateEntry = placed[i] if i < placed.size() else _add_entry(i)
		entry.visible = true
		entry.set_candidate(candidates[i])
		# 换名单时连判定一起复位，免得空位上残留上一批的底色
		entry.set_decision(FramedAvatar.Tint.NONE)
		entry.set_expanded(false)
		_connect_entry(entry)
		if candidates[i] != null:
			_candidates[candidates[i].id] = candidates[i]

	for i in range(candidates.size(), placed.size()):
		var extra := placed[i] as Control
		if extra != null:
			extra.visible = false

	_layout_entries()
	_apply_decisions()


## 把「进队 / 不进队」名单同步到画面上。
##
## 进队 = GameState.current_team（**顺序有意义**：右下角的格子按它依次填），
## 不进队 = GameState.rejected_ids。两者互斥，上层保证。
func set_decisions(approved: Array[StringName], rejected: Array[StringName]) -> void:
	_approved = approved.duplicate()
	_rejected = rejected.duplicate()
	_apply_decisions()


## 当日名额（data/days/day_XX.tres 的 slots）：右下角摆几个空位就是它
func set_slots(slots: int) -> void:
	_slots_count = slots
	_rebuild_slots()


## 名额满了没有 —— 由上层用 TeamValidator 判定后传进来（§0）。
## 满了就把还没进队的那些条目的「进队」按钮置灰（「不进队」照旧可点）。
func set_team_full(full: bool) -> void:
	if _team_full == full:
		return
	_team_full = full
	for entry in entries():
		entry.set_team_full(full)


# ---------------------------------------------------------------------------
# 查询（上层与自检用）
# ---------------------------------------------------------------------------


## 画面上真正在用的条目（顺序 = 名单顺序）
func entries() -> Array[CandidateEntry]:
	var list: Array[CandidateEntry] = []
	if _roster == null:
		return list
	for child in _roster.get_children():
		var entry := child as CandidateEntry
		if entry != null and entry.visible:
			list.append(entry)
	return list


## 现在展开着按钮的那一条（没有则 null）
func expanded_entry() -> CandidateEntry:
	return _expanded


## 已进队的人数
func approved_count() -> int:
	var count := 0
	for entry in entries():
		if entry.is_approved():
			count += 1
	return count


## 右下角的格子（顺序 = 一个个空位）。没摆出来时是空数组。
func slot_frames() -> Array[FramedAvatar]:
	var list: Array[FramedAvatar] = []
	if _slots == null:
		return list
	for child in _slots.get_children():
		var frame := child as FramedAvatar
		if frame != null:
			list.append(frame)
	return list


## 名额空位露出来了没有（第一次点头像才露，§12.3）
func slots_visible() -> bool:
	return _slots != null and _slots.visible


## 格子容器本身（自检量位置用）
func slots_control() -> Control:
	return _slots


# ---------------------------------------------------------------------------
# 内部：条目
# ---------------------------------------------------------------------------


func _add_entry(index: int) -> CandidateEntry:
	var entry := ENTRY_SCENE.instantiate() as CandidateEntry
	entry.name = "CandidateEntry%d" % (index + 1)
	_roster.add_child(entry)
	return entry


func _connect_entry(entry: CandidateEntry) -> void:
	if not entry.selected.is_connected(_on_entry_selected):
		entry.selected.connect(_on_entry_selected)
	if not entry.approved.is_connected(_on_entry_approved):
		entry.approved.connect(_on_entry_approved)
	if not entry.rejected.is_connected(_on_entry_rejected):
		entry.rejected.connect(_on_entry_rejected)


## 头像列按固定行距往下摆（不用容器：按钮要滑到条目框**外面**去，
## 容器会把它们算进最小尺寸里，版面反而被撑歪）。
func _layout_entries() -> void:
	var list := entries()
	for i in list.size():
		list[i].position = Vector2(ENTRY_LEFT, ENTRY_TOP + float(i) * ENTRY_PITCH)


func _on_entry_selected(entry: CandidateEntry) -> void:
	# 同一个再点一次 = 收起来；点别人 = 把上一条收掉、这条打开
	_expand(entry if _expanded != entry else null)
	# 第一次点头像 → 右下角的名额空位露出来（§12.3）
	_reveal_slots()
	candidate_selected.emit(entry.candidate if entry != null else null)


func _on_entry_approved(entry: CandidateEntry) -> void:
	_expand(null)
	candidate_approved.emit(entry.candidate if entry != null else null)


func _on_entry_rejected(entry: CandidateEntry) -> void:
	_expand(null)
	candidate_rejected.emit(entry.candidate if entry != null else null)


## 同一时刻只展开一条：传 null = 全收起来
func _expand(entry: CandidateEntry) -> void:
	for other in entries():
		other.set_expanded(other == entry)
	_expanded = entry


## 判定同步到画面上：谁绿、谁红、谁还没决定，外加「进队按钮能不能点」
func _apply_decisions() -> void:
	for entry in entries():
		if entry.candidate == null:
			continue
		var id := entry.candidate.id
		if _approved.has(id):
			entry.set_decision(FramedAvatar.Tint.APPROVED)
		elif _rejected.has(id):
			entry.set_decision(FramedAvatar.Tint.REJECTED)
		else:
			entry.set_decision(FramedAvatar.Tint.NONE)
		entry.set_team_full(_team_full)
	_refresh_slots()


# ---------------------------------------------------------------------------
# 内部：右下角的名额空位
# ---------------------------------------------------------------------------


## 摆 `slots` 个空位、右对齐贴右下角。名额没填（<= 0）时一个都不摆。
##
## 空位的数量 = 今天最多能带几个人；进队的人按 current_team 的顺序依次填进去，
## 所以「还剩几个空格」= 还能再带几个（§12.5）。
func _rebuild_slots() -> void:
	if _slots == null:
		return
	# queue_free 是**延迟**释放的：先摘下来再排队销毁，否则紧接着的 _layout_slots()
	# 还会从 _slots 里读到上一批旧格子，摆出来的位置是错的。
	for child in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	var count := maxi(_slots_count, 0)
	for i in count:
		var frame := SLOT_SCENE.instantiate() as FramedAvatar
		frame.name = "Slot%d" % (i + 1)
		frame.set_pixel_size(SLOT_SIZE)
		_slots.add_child(frame)
	_layout_slots()
	_refresh_slots()


## 摆空位：右对齐贴屏幕右下角。
##
## 位置用**绝对坐标**算，不从自己身上量 —— 这几个组队 / 面试场景的根 Control 都是
## 0 尺寸的（整套版面是照 1152x648 的画布摆死偏移的，见 §12.5），拿控件尺寸做锚定
## 会算到屏幕外面去；画布尺寸只有 viewport 说得准。
func _layout_slots() -> void:
	if _slots == null:
		return
	var frames := slot_frames()
	var width := 0.0
	if not frames.is_empty():
		width = float(frames.size()) * float(SLOT_SIZE) \
				+ float(frames.size() - 1) * SLOT_GAP
	var canvas := get_viewport_rect().size
	_slots.size = Vector2(width, float(SLOT_SIZE))
	_slots.position = Vector2(
		canvas.x - SLOT_RIGHT_MARGIN - width,
		canvas.y - SLOT_BOTTOM_MARGIN - float(SLOT_SIZE)
	)
	for i in frames.size():
		frames[i].position = Vector2(float(i) * (float(SLOT_SIZE) + SLOT_GAP), 0.0)


## 进队的人依次填进格子；多出来的（超员）没格子可放，就不画 ——
## 超员本身由 team_builder 硬拦（§12.8），这里只是不画崩。
func _refresh_slots() -> void:
	var frames := slot_frames()
	for i in frames.size():
		var id: StringName = _approved[i] if i < _approved.size() else &""
		var candidate: CandidateResource = _candidates.get(id) if id != &"" else null
		frames[i].set_candidate(candidate)
		frames[i].set_tint(
			FramedAvatar.Tint.APPROVED if candidate != null else FramedAvatar.Tint.NONE
		)


func _reveal_slots() -> void:
	if _slots != null and not _slots.visible:
		_slots.visible = true
