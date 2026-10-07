extends Node

## DataDB —— 静态数据库（ARCHITECTURE.md §2）。
##
## 启动时扫描 `res://data/`，把所有 `.tres` / `.res` 按**一级子目录**归类收进字典，
## 提供 `get_job(id)` / `get_candidate(id)` / `get_monster(id)` 等查询。
##
## 纪律：**只读静态数据，不持有任何运行时状态**。运行时状态一律走 GameState。
## 目录名即数据类别（data/jobs/ → jobs，data/monsters/ → monsters …），
## 新增一类数据只要建目录 + 对应 Resource 脚本，本文件无需改动。

## 数据类别表：StringName -> { id -> Resource }
var _tables: Dictionary = {}

## 相性 / 克制矩阵：单文件集中维护（data/traits/interactions.tres）
var _interaction_table: TraitInteractionTable = null

## 加载过程中的警告（缺 id 回退、重复 id、加载失败…），便于启动时排查
var _warnings: Array[String] = []

var _loaded: bool = false

## 回退 id 前缀：目录名 -> 单数前缀，例如 jobs -> job（job.fighter）
const _SINGULAR: Dictionary = {
	&"jobs": "job",
	&"races": "race",
	&"traits": "trait",
	&"candidates": "candidate",
	&"monsters": "monster",
	&"handbook": "handbook",
	&"narrative": "narrative",
	&"days": "day",
	&"events": "event",
	&"endings": "ending",
}

## 相性矩阵文件名（data/traits/interactions.tres）
const _INTERACTION_FILE: String = "interactions"


func _ready() -> void:
	reload()


## 是否已完成一次扫描
func is_loaded() -> bool:
	return _loaded


## 全量重扫（数据热重载、编辑器内调试用）
func reload() -> void:
	_tables.clear()
	_interaction_table = null
	_warnings.clear()
	_scan_dir(GameConfig.DATA_ROOT, &"")
	_loaded = true
	var summary: Array[String] = []
	for kind in _tables.keys():
		summary.append("%s %d" % [kind, count(kind)])
	print("[DataDB] 已载入 %d 个静态资源：%s" % [total_count(), ", ".join(summary)])
	for warning in _warnings:
		push_warning("[DataDB] " + warning)


## 扫描期间的警告列表
func get_warnings() -> Array[String]:
	var copy: Array[String] = []
	copy.assign(_warnings)
	return copy

# ---------------------------------------------------------------------------
# 通用查询
# ---------------------------------------------------------------------------


## 某个类别的全部条目：{ id -> Resource }
func get_table(kind: StringName) -> Dictionary:
	return _tables.get(kind, {})


## 某个类别的全部 id
func get_ids(kind: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in get_table(kind).keys():
		ids.append(id)
	return ids


## 某个类别的条目数
func count(kind: StringName) -> int:
	return get_table(kind).size()


## 全部类别的总条目数
func total_count() -> int:
	var total := 0
	for kind in _tables.keys():
		total += count(kind)
	return total


func has(kind: StringName, id: StringName) -> bool:
	return get_table(kind).has(id)


## 通用取用；不存在返回 null
func get_resource(kind: StringName, id: StringName) -> Resource:
	return get_table(kind).get(id)


## 某个类别的全部条目，顺序按 id 字典序（便于 UI 稳定展示）
func get_all(kind: StringName) -> Array:
	var table := get_table(kind)
	var ids: Array = table.keys()
	ids.sort()
	var result: Array = []
	for id in ids:
		result.append(table[id])
	return result

# ---------------------------------------------------------------------------
# 各类别快捷查询
# ---------------------------------------------------------------------------


func get_job(id: StringName) -> JobDef:
	return get_resource(&"jobs", id) as JobDef


func get_candidate(id: StringName) -> CandidateResource:
	return get_resource(&"candidates", id) as CandidateResource


func get_race(id: StringName) -> RaceDef:
	return get_resource(&"races", id) as RaceDef


func get_trait(id: StringName) -> TraitDef:
	return get_resource(&"traits", id) as TraitDef


func get_monster(id: StringName) -> MonsterDef:
	return get_resource(&"monsters", id) as MonsterDef


func get_handbook_entry(id: StringName) -> HandbookEntry:
	return get_resource(&"handbook", id) as HandbookEntry


func get_event(id: StringName) -> DailyEventDef:
	return get_resource(&"events", id) as DailyEventDef


## 第 n 天的配置（data/days/day_XX.tres），不存在返回 null
func get_day_config(day_index: int) -> DayConfig:
	return get_resource(&"days", StringName(str(day_index))) as DayConfig


## 战报叙事规则全集（data/narrative/），narrative_engine 按 priority / weight 使用
func get_narrative_rules() -> Array[NarrativeRule]:
	var rules: Array[NarrativeRule] = []
	for resource in get_all(&"narrative"):
		if resource is NarrativeRule:
			rules.append(resource)
	return rules


## 相性 / 克制矩阵；文件缺失时返回 null，由 synergy_calculator 兜底
func get_interaction_table() -> TraitInteractionTable:
	return _interaction_table


## 按关键词检索手册条目（handbook_overlay 的搜索框用）
func search_handbook(keyword: String) -> Array[HandbookEntry]:
	var result: Array[HandbookEntry] = []
	if keyword.strip_edges().is_empty():
		return result
	var needle := keyword.strip_edges().to_lower()
	for resource in get_all(&"handbook"):
		var entry := resource as HandbookEntry
		if entry == null:
			continue
		if entry.title.to_lower().contains(needle) or entry.body.to_lower().contains(needle):
			result.append(entry)
			continue
		for tag in entry.keywords:
			if String(tag).to_lower().contains(needle):
				result.append(entry)
				break
	return result

# ---------------------------------------------------------------------------
# 扫描实现
# ---------------------------------------------------------------------------


func _scan_dir(dir_path: String, kind_hint: StringName) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		# 某个类别目录还没建是正常的（M0 只有 data/jobs）
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			pass
		elif dir.current_is_dir():
			var child_kind := kind_hint if kind_hint != &"" else StringName(entry)
			_scan_dir(dir_path.path_join(entry), child_kind)
		else:
			var child_kind := kind_hint if kind_hint != &"" else StringName(dir_path.get_file())
			_collect(dir_path.path_join(entry), child_kind)
		entry = dir.get_next()
	dir.list_dir_end()


func _collect(path: String, kind: StringName) -> void:
	var extension := path.get_extension().to_lower()
	if extension != "tres" and extension != "res":
		return
	var resource := ResourceLoader.load(path)
	if resource == null:
		_warnings.append("加载失败：%s" % path)
		return

	# 相性矩阵单文件：不进常规表，单独持有
	if path.get_file().get_basename() == _INTERACTION_FILE and kind == &"traits":
		if resource is TraitInteractionTable:
			_interaction_table = resource
			return

	var id := _resolve_id(resource, path, kind)
	if id == &"":
		_warnings.append("无法确定 id，已跳过：%s" % path)
		return

	if not _tables.has(kind):
		_tables[kind] = {}
	var table: Dictionary = _tables[kind]
	if table.has(id):
		_warnings.append("重复 id %s：%s 覆盖 %s" % [id, path, table[id].resource_path])
	table[id] = resource


## id 取值顺序：显式 @export id（天数据用 day_index）→ 文件名回退 → 跳过
func _resolve_id(resource: Resource, path: String, kind: StringName) -> StringName:
	if resource is DayConfig:
		var day_config := resource as DayConfig
		if day_config.day_index <= 0:
			_warnings.append("DayConfig 未设置 day_index：%s" % path)
			return &""
		return StringName(str(day_config.day_index))

	# 叙事规则用文件名为 id（模板变体多，逐条命名）
	if kind == &"narrative":
		return StringName("%s.%s" % [_SINGULAR.get(kind, String(kind)), path.get_file().get_basename()])

	if _has_property(resource, "id"):
		var raw: Variant = resource.get("id")
		if raw != null and String(raw).strip_edges() != "":
			return StringName(String(raw))

	# 回退：目录单数前缀 + 文件名。现有 .tres 多为骨架资源（尚未填 id），
	# 回退后 DataDB 依然可用，同时给出警告提醒补 id。
	var fallback := StringName("%s.%s" % [_SINGULAR.get(kind, String(kind)), path.get_file().get_basename()])
	_warnings.append("资源未设置 id，已回退为 %s：%s" % [fallback, path])
	return fallback


func _has_property(obj: Object, property_name: String) -> bool:
	for info in obj.get_property_list():
		if String(info.get("name", "")) == property_name:
			return true
	return false
