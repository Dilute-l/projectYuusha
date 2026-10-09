class_name TeamBuilderUI
extends Control

## 组队界面的 UI 容器（ARCHITECTURE.md §4 team_builder 一节、§12）。
##
## 现在装两样东西：**左半边「今日出现的面试者」头像列表** + 一行「已录用 N / 名额」。
##
## 数据全部由 team_builder.gd 灌进来（`set_candidates` / `set_hired_ids` / `set_slots`），
## 本控件**不读 GameState**；玩家操作也只往外抛两个信号：
##
##   candidate_hovered(candidate)  悬停某一位 → 上层把这位的简历铺到右半边
##   candidate_toggled(candidate)  左键点某一位 → 上层加 / 撤「已录用」
##
## 「谁算被录用」的判定不在这里 —— 这里只负责把标记画出来（表现层不写规则）。
## 文案「HIRED」是英文：assets/fonts 还没接入中文字体，中文会渲染成方块（§10.5）。

## 鼠标停在某一位身上（candidate 可能为 null —— 空条目也会被悬停到）
signal candidate_hovered(candidate: CandidateResource)

## 左键点了某一位。录用还是撤销由上层决定，这里只报「点了谁」。
signal candidate_toggled(candidate: CandidateResource)

const ENTRY_SCENE := preload("res://scenes/day/team_builder/candidate.tscn")

@onready var _roster: GridContainer = $Roster
@onready var _header: Label = $Header

## 当日名额（来自 DayConfig.slots）；<= 0 表示数据还没填，表头只报已录用人数
var _slots: int = 0

## 名额是否已满。**由上层用 TeamValidator 判定后传进来** ——
## 「算不算满」是规则，不在本控件里再算一遍（§0）。
var _team_full: bool = false


func _ready() -> void:
	_refresh_header()


# ---------------------------------------------------------------------------
# 数据入口（由 team_builder.gd 调用）
# ---------------------------------------------------------------------------


## 铺今日的候选人名单。**顺序即出场顺序**（与 data/days/day_XX.tres 一致）。
##
## 场景里预摆了 3 个条目（编辑器打开就能看到版面），数据条数和它对不上时按数据走：
## 多的现场 instantiate，少的多余项隐藏 —— 所以「今天几个人」都不用回头改场景。
func set_candidates(candidates: Array[CandidateResource]) -> void:
	if _roster == null:
		return
	var placed := _roster.get_children()
	for i in candidates.size():
		var entry: CandidateEntry = placed[i] if i < placed.size() else _add_entry(i)
		entry.visible = true
		entry.set_candidate(candidates[i])
		# 换名单时连「已录用」标记一起复位，免得空位上残留上一批的高亮
		entry.set_hired(false)
		_connect_entry(entry)

	for i in range(candidates.size(), placed.size()):
		var extra := placed[i] as Control
		if extra != null:
			extra.visible = false

	_refresh_header()


## 把「已录用」名单同步到画面上（真身在 GameState.current_team）
func set_hired_ids(ids: Array[StringName]) -> void:
	if _roster == null:
		return
	for child in _roster.get_children():
		var entry := child as CandidateEntry
		if entry == null:
			continue
		entry.set_hired(entry.candidate != null and ids.has(entry.candidate.id))
	_refresh_header()
	_apply_lock()


## 当日名额（data/days/day_XX.tres 的 slots）
func set_slots(slots: int) -> void:
	_slots = slots
	_refresh_header()
	_apply_lock()


## 名额满了没有 —— 由上层用 TeamValidator 判定后传进来（§0：规则不在这儿重算一遍）。
## 满了就把**还没选中**的条目锁住（变灰 + 点击无效）；已选中的不锁，玩家要能点它们撤销。
func set_team_full(full: bool) -> void:
	if _team_full == full:
		return
	_team_full = full
	_apply_lock()


func _apply_lock() -> void:
	for entry in entries():
		entry.set_locked(_team_full and not entry.is_hired())


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


## 当前标记为「已录用」的人数
func hired_count() -> int:
	var count := 0
	for entry in entries():
		if entry.is_hired():
			count += 1
	return count


func header_text() -> String:
	return _header.text if _header != null else ""


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------


func _add_entry(index: int) -> CandidateEntry:
	var entry := ENTRY_SCENE.instantiate() as CandidateEntry
	entry.name = "CandidateEntry%d" % (index + 1)
	_roster.add_child(entry)
	return entry


func _connect_entry(entry: CandidateEntry) -> void:
	if not entry.hovered.is_connected(_on_entry_hovered):
		entry.hovered.connect(_on_entry_hovered)
	if not entry.toggled.is_connected(_on_entry_toggled):
		entry.toggled.connect(_on_entry_toggled)


func _on_entry_hovered(entry: CandidateEntry) -> void:
	candidate_hovered.emit(entry.candidate if entry != null else null)


func _on_entry_toggled(entry: CandidateEntry) -> void:
	candidate_toggled.emit(entry.candidate if entry != null else null)


func _refresh_header() -> void:
	if _header == null:
		return
	var hired := hired_count()
	if _slots > 0:
		_header.text = "HIRED %d / %d" % [hired, _slots]
	else:
		_header.text = "HIRED %d" % hired
