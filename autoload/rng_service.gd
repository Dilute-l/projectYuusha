extends Node

## RngService —— 唯一随机源（ARCHITECTURE.md §2）。
##
## 纪律：**玩法内任何随机都必须走这里**，不允许各脚本自己 `RandomNumberGenerator.new().randomize()`，
## 否则「同种子 → 同一份候选人 → 同一个战报」无法复现。
##
## 每日派生种子固定为 `day_seed = run_seed ^ day_index`（§2 / RunState.run_seed 注释）。
## 除每日流之外的其他用途（姓名池、事件池、叙事抽模板…）走命名流 `stream(name)`，
## 各自的种子由 run_seed 与流名字派生，互不干扰：多抽一个姓名不会影响战报结果。

## 本局种子。0 也合法，只是一个普通种子
var run_seed: int = 0

## 命名流缓存：StringName -> RandomNumberGenerator
var _streams: Dictionary = {}


func _ready() -> void:
	# 没有开局时（主菜单、图鉴回顾）也要能安全调用，先给一个随机种子
	start_run(randomize_seed())


## 开一局：设定种子并清空全部流。传 0 视为「请给一个随机种子」
func start_run(seed_value: int = 0) -> int:
	run_seed = seed_value if seed_value != 0 else randomize_seed()
	_streams.clear()
	return run_seed


## 清空流但保留种子（读档后重放当天时用）
func reset_streams() -> void:
	_streams.clear()


## 生成一个随机种子（新游戏、调试用）
func randomize_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var value := rng.randi() & 0x3FFFFFFF
	return value if value != 0 else 1


## 每日派生种子
func day_seed(day_index: int) -> int:
	return run_seed ^ day_index


## 当日主随机流：候选人生成等「当天一次性」的事情用它
func day_rng(day_index: int) -> RandomNumberGenerator:
	var stream_name := StringName("day:%d" % day_index)
	if not _streams.has(stream_name):
		var rng := RandomNumberGenerator.new()
		rng.seed = day_seed(day_index)
		_streams[stream_name] = rng
	return _streams[stream_name]


## 命名随机流：同一个流名在同一种子下永远给出同一序列
func stream(stream_name: StringName) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		var rng := RandomNumberGenerator.new()
		rng.seed = derive_seed(stream_name)
		_streams[stream_name] = rng
	return _streams[stream_name]


## 由「本局种子 + 流名」派生一个稳定种子
func derive_seed(stream_name: StringName) -> int:
	return hash("%d|%s" % [run_seed, String(stream_name)]) & 0x7FFFFFFF

# ---------------------------------------------------------------------------
# 便捷封装：调用方不必自己取流对象，也就不容易误用别的随机源
# ---------------------------------------------------------------------------


## [from, to] 闭区间整数
func randi_in(stream_name: StringName, from: int, to: int) -> int:
	return stream(stream_name).randi_range(from, to)


## [from, to) 浮点
func randf_in(stream_name: StringName, from: float, to: float) -> float:
	return stream(stream_name).randf_range(from, to)


## 概率判定
func chance(stream_name: StringName, probability: float) -> bool:
	return stream(stream_name).randf() < probability


## 随机取一项；空数组返回 null
func pick(stream_name: StringName, items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[stream(stream_name).randi_range(0, items.size() - 1)]


## 不放回抽取 n 项（返回新数组，不改动入参）
func pick_many(stream_name: StringName, items: Array, count: int) -> Array:
	var pool := items.duplicate()
	var result: Array = []
	var take: int = mini(count, pool.size())
	for _i in take:
		var index := stream(stream_name).randi_range(0, pool.size() - 1)
		result.append(pool[index])
		pool.remove_at(index)
	return result


## 洗牌（返回新数组）
func shuffled(stream_name: StringName, items: Array) -> Array:
	var result := items.duplicate()
	var rng := stream(stream_name)
	for i in range(result.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result


## 按权重抽取一项。entries 每项需带 weight_key（默认 "weight"），权重 <= 0 的项不参与；
## 全部权重非正时回退为等概率，空数组返回 null。
func weighted_pick(stream_name: StringName, entries: Array, weight_key: String = "weight") -> Variant:
	if entries.is_empty():
		return null
	var total := 0.0
	for entry in entries:
		total += _weight_of(entry, weight_key)
	if total <= 0.0:
		return pick(stream_name, entries)
	var roll := stream(stream_name).randf() * total
	for entry in entries:
		roll -= _weight_of(entry, weight_key)
		if roll <= 0.0:
			return entry
	return entries[entries.size() - 1]


func _weight_of(entry: Variant, weight_key: String) -> float:
	if entry is Dictionary:
		var dict: Dictionary = entry
		return maxf(float(dict.get(weight_key, 0.0)), 0.0)
	if entry is Object and _has_property(entry, weight_key):
		var obj: Object = entry
		return maxf(float(obj.get(weight_key)), 0.0)
	return 0.0


func _has_property(obj: Object, property_name: String) -> bool:
	for info in obj.get_property_list():
		if String(info.get("name", "")) == property_name:
			return true
	return false
