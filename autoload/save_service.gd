extends Node

## SaveService —— 存档 / 读档 / 自动存档（ARCHITECTURE.md §2 / §7）。
##
## 只序列化 `RunState`（§7 的存档根结构），**绝不写静态数据**：
## 静态数据在 data/ 里，随版本走；存档里只有「这一局发生了什么」。
##
## 路径：`user://saves/slot_{n}.json`，自动存档另存一份 `user://saves/auto.json`。

## 自动存档在事件与列表接口中的槽位号
const AUTO_SLOT: int = -1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(GameConfig.SAVE_DIR)

# ---------------------------------------------------------------------------
# 写入
# ---------------------------------------------------------------------------


## 写入第 slot 号存档槽（1..MAX_SAVE_SLOTS）
func save_to_slot(slot: int) -> bool:
	if not GameConfig.is_valid_slot(slot):
		push_error("[SaveService] 非法存档槽位：%d" % slot)
		return false
	return _write(GameConfig.slot_path(slot), slot)


## 自动存档：每日开始 / 关键节点调用
func autosave() -> bool:
	return _write(GameConfig.AUTO_SAVE_PATH, AUTO_SLOT)


func _write(path: String, slot: int) -> bool:
	if GameState.run_state == null or not GameState.has_run():
		push_warning("[SaveService] 没有进行中的一局，跳过写档")
		EventBus.save_written.emit(slot, false)
		return false

	DirAccess.make_dir_recursive_absolute(GameConfig.SAVE_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveService] 无法写入 %s（错误码 %d）" % [path, FileAccess.get_open_error()])
		EventBus.save_written.emit(slot, false)
		return false
	file.store_string(JSON.stringify(to_dict(GameState.run_state), "\t"))
	file.close()
	EventBus.save_written.emit(slot, true)
	return true

# ---------------------------------------------------------------------------
# 读取
# ---------------------------------------------------------------------------


## 读取第 slot 号存档槽并接管 GameState
func load_from_slot(slot: int) -> bool:
	if not GameConfig.is_valid_slot(slot):
		push_error("[SaveService] 非法存档槽位：%d" % slot)
		return false
	return _load(GameConfig.slot_path(slot), slot)


## 读取自动存档并接管 GameState
func load_auto() -> bool:
	return _load(GameConfig.AUTO_SAVE_PATH, AUTO_SLOT)


func _load(path: String, slot: int) -> bool:
	if not FileAccess.file_exists(path):
		EventBus.save_loaded.emit(slot, false)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveService] 无法读取 %s（错误码 %d）" % [path, FileAccess.get_open_error()])
		EventBus.save_loaded.emit(slot, false)
		return false
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("[SaveService] 存档损坏：%s" % path)
		EventBus.save_loaded.emit(slot, false)
		return false

	var state := from_dict(parsed)
	GameState.apply_run_state(state)
	EventBus.save_loaded.emit(slot, true)
	return true


## 只读取存档信息，不改动 GameState（主菜单「继续」按钮的摘要用）
func peek(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	var roster_size := 0
	var raw_roster: Variant = data.get("roster", [])
	if raw_roster is Array:
		var roster: Array = raw_roster
		roster_size = roster.size()
	return {
		"exists": true,
		"version": int(data.get("version", 0)),
		"day": int(data.get("day", 1)),
		"total_score": _sum_scores(data.get("scores", [])),
		"roster_size": roster_size,
		"saved_at": FileAccess.get_modified_time(path),
	}

# ---------------------------------------------------------------------------
# 槽位管理
# ---------------------------------------------------------------------------


func has_slot(slot: int) -> bool:
	return GameConfig.is_valid_slot(slot) and FileAccess.file_exists(GameConfig.slot_path(slot))


func has_auto_save() -> bool:
	return FileAccess.file_exists(GameConfig.AUTO_SAVE_PATH)


## 是否存在任何可「继续」的存档（自动存档优先）
func has_any_save() -> bool:
	if has_auto_save():
		return true
	for slot in range(1, GameConfig.MAX_SAVE_SLOTS + 1):
		if has_slot(slot):
			return true
	return false


func delete_slot(slot: int) -> bool:
	if not has_slot(slot):
		return false
	return DirAccess.remove_absolute(GameConfig.slot_path(slot)) == OK


## 全部槽位摘要（含空槽），供存档界面直接铺列表
func list_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot in range(1, GameConfig.MAX_SAVE_SLOTS + 1):
		var path := GameConfig.slot_path(slot)
		var info := peek(path)
		info["slot"] = slot
		info["path"] = path
		if not info.has("exists"):
			info["exists"] = false
		slots.append(info)
	return slots


func slot_path(slot: int) -> String:
	return GameConfig.slot_path(slot)

# ---------------------------------------------------------------------------
# RunState <-> Dictionary（§7 的 JSON 形状）
# ---------------------------------------------------------------------------


## RunState -> 存档字典。StringName 一律转 String 再交给 JSON
static func to_dict(state: RunState) -> Dictionary:
	if state == null:
		return {}
	return {
		"version": state.version,
		"run_seed": state.run_seed,
		"day": state.day,
		"scores": Array(state.scores),
		"roster": _names_to_strings(state.roster),
		"flags": state.flags.duplicate(true),
		"handbook_unlocked": _names_to_strings(state.handbook_unlocked),
		"phase": String(state.phase),
	}


## 存档字典 -> RunState。缺字段一律取默认值，尽量让老存档还能读进来
static func from_dict(data: Dictionary) -> RunState:
	var state := RunState.new()
	state.version = int(data.get("version", GameConfig.SAVE_VERSION))
	state.run_seed = int(data.get("run_seed", 0))
	state.day = clampi(int(data.get("day", 1)), 1, GameConfig.TOTAL_DAYS)

	var scores: Array[int] = []
	var raw_scores: Variant = data.get("scores", [])
	if raw_scores is Array:
		for value in raw_scores:
			scores.append(int(value))
	state.scores = scores

	var roster: Array[StringName] = []
	var raw_roster: Variant = data.get("roster", [])
	if raw_roster is Array:
		for value in raw_roster:
			roster.append(StringName(str(value)))
	state.roster = roster

	# flag 名在内存里统一是 StringName（GameState.get_flag(&"liar_hired")）；
	# JSON 只存得下 String，读回来必须转回 StringName，否则读档后查不到 flag
	var flags: Dictionary = {}
	var raw_flags: Variant = data.get("flags", {})
	if raw_flags is Dictionary:
		var raw_flags_dict: Dictionary = raw_flags
		for key in raw_flags_dict.keys():
			flags[StringName(str(key))] = _normalize_number(raw_flags_dict[key])
	state.flags = flags

	var unlocked: Array[StringName] = []
	var raw_unlocked: Variant = data.get("handbook_unlocked", [])
	if raw_unlocked is Array:
		for value in raw_unlocked:
			unlocked.append(StringName(str(value)))
	state.handbook_unlocked = unlocked

	state.phase = StringName(str(data.get("phase", DayPhase.to_name(DayPhase.Phase.DAY_BRIEFING))))
	return state


## JSON 把数字一律读成 float（3 -> 3.0），整数型 flag 要还原成 int，
## 否则读档后 flag 与存档前不相等（3 != 3.0），M6「存档读档一致」就会挂
static func _normalize_number(value: Variant) -> Variant:
	if value is float:
		var number: float = value
		if is_equal_approx(number, roundf(number)) and absf(number) < 2147483647.0:
			return int(number)
	return value


static func _names_to_strings(names: Array[StringName]) -> Array:
	var result: Array = []
	for entry_name in names:
		result.append(String(entry_name))
	return result


static func _sum_scores(raw: Variant) -> int:
	var total := 0
	if raw is Array:
		for value in raw:
			total += int(value)
	return total
