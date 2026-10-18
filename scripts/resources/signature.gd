class_name Signature
extends Resource

## 玩家签的一段字（笔迹）。落点是 `RunState.signatures`，随存档进 JSON（§7）。
##
## 形状是「一串笔 + 每点时间戳」，**不是一张图** —— 要求是能复现签名过程：
## 图只能静态显示，重放不出「笔是怎么走的」，而且跟分辨率绑死。
##
## ⚠️ 坐标一律**归一化到画布 0..1**（见 to_normalized）。存像素的话，同一段字放到
##    缩略图 / 手册页 / 结算页里换个尺寸就漂了 —— 而这块牌子注定要在好几个尺寸下出现。
##
## ⚠️ 每点都带时间戳，而不是「每笔记一个总时长」：人写字是起笔慢、行笔快、收笔顿，
##    速度变化发生在**一笔之内**；只记总时长、笔内匀速描，回放一眼假。
##    量化到 10ms，300 个点也就多一两 KB。

## 时间戳量化精度（毫秒）。见文件头。
const TIME_QUANTUM_MS: int = 10

## 坐标量化精度（归一化单位）。1e-4 × 1152px ≈ 0.12px，肉眼看不出，JSON 却短一截。
const POS_QUANTUM: float = 0.0001

## 录制时画布多大（像素）。回放时按「当前画布 / 这个尺寸」做换算，
## 保证窄长画布上写的字放进方画布里不会变形。
var canvas: Vector2 = Vector2.ZERO

## 笔。每一笔是
##   { "p": PackedVector2Array（归一化坐标）,
##     "t": PackedFloat32Array（本笔内相对毫秒）,
##     "g": int（这一笔落笔前，距离上一笔结束停了多少毫秒） }
##
## 用两个并行数组而不是 Array[Dictionary]：存档 JSON 小一个数量级，而且
## 它们是**同一笔的两个面**，不会各自跑偏（比如点数对不上时间戳）。
## "g" 只对多笔签名有意义；一笔画（当前玩法）永远是 0。
var strokes: Array[Dictionary] = []


# ---------------------------------------------------------------------------
# 坐标换算（**唯一出处**：画布组件和回放都走这两个函数）
# ---------------------------------------------------------------------------


## 画布内像素坐标 → 归一化 0..1
static func to_normalized(canvas_rect: Rect2, point: Vector2) -> Vector2:
	if canvas_rect.size.x <= 0.0 or canvas_rect.size.y <= 0.0:
		return Vector2.ZERO
	return (point - canvas_rect.position) / canvas_rect.size


## 归一化 0..1 → 画布内像素坐标
static func to_canvas(canvas_rect: Rect2, normalized: Vector2) -> Vector2:
	return canvas_rect.position + normalized * canvas_rect.size


# ---------------------------------------------------------------------------
# 读数
# ---------------------------------------------------------------------------


func is_empty() -> bool:
	for stroke in strokes:
		var points: PackedVector2Array = stroke.get("p", PackedVector2Array())
		if points.size() > 0:
			return false
	return true


func point_count() -> int:
	var total := 0
	for stroke in strokes:
		var points: PackedVector2Array = stroke.get("p", PackedVector2Array())
		total += points.size()
	return total


## 某一笔自己的跨度（毫秒）：最后一个点的时间戳
func stroke_span_ms(stroke: Dictionary) -> float:
	var times: PackedFloat32Array = stroke.get("t", PackedFloat32Array())
	return times[times.size() - 1] if times.size() > 0 else 0.0


## 某一笔**开始**于整段签名的第几毫秒（前面每一笔的跨度 + 笔间停顿都算进去）
func stroke_start_ms(index: int) -> float:
	var cursor := 0.0
	for i in range(mini(index, strokes.size())):
		cursor += float(strokes[i].get("g", 0)) + stroke_span_ms(strokes[i])
	return cursor


## 整段签名的总时长（毫秒）。回放的终点就是它。
func duration_ms() -> float:
	var cursor := 0.0
	for stroke in strokes:
		cursor += float(stroke.get("g", 0)) + stroke_span_ms(stroke)
	return cursor


## 笔迹总长（归一化单位）。用来判断「这是一次误点还是一笔字」。
func total_length() -> float:
	var total := 0.0
	for stroke in strokes:
		var points: PackedVector2Array = stroke.get("p", PackedVector2Array())
		for i in range(1, points.size()):
			total += points[i - 1].distance_to(points[i])
	return total


# ---------------------------------------------------------------------------
# 存档（§7：存档是 JSON，所以 Resource 必须自己会说 Dictionary）
# ---------------------------------------------------------------------------


## Signature → 可以塞进存档 JSON 的字典。
##
## 点存成**扁平 float 数组**（[x0,y0,x1,y1,…]）而不是 [{"x":…,"y":…},…]：
## 同一个意思，JSON 体积差一倍以上。这是唯一值得为存档体积做的取舍。
func to_dict() -> Dictionary:
	var out_strokes: Array = []
	for stroke in strokes:
		var points: PackedVector2Array = stroke.get("p", PackedVector2Array())
		var times: PackedFloat32Array = stroke.get("t", PackedFloat32Array())
		var flat_points: Array = []
		for point in points:
			flat_points.append(snappedf(point.x, POS_QUANTUM))
			flat_points.append(snappedf(point.y, POS_QUANTUM))
		var flat_times: Array = []
		for ms in times:
			flat_times.append(int(round(float(ms) / float(TIME_QUANTUM_MS))) * TIME_QUANTUM_MS)
		out_strokes.append({
			"p": flat_points,
			"t": flat_times,
			"g": int(stroke.get("g", 0)),
		})
	return {
		"canvas": [canvas.x, canvas.y],
		"strokes": out_strokes,
	}


## 存档字典 → Signature。缺字段一律给默认值，坏数据不至于把读档整挂。
static func from_dict(data: Dictionary) -> Signature:
	var signature := Signature.new()
	var raw_canvas: Variant = data.get("canvas", [])
	if raw_canvas is Array and (raw_canvas as Array).size() >= 2:
		var pair: Array = raw_canvas
		signature.canvas = Vector2(float(pair[0]), float(pair[1]))

	var raw_strokes: Variant = data.get("strokes", [])
	if not (raw_strokes is Array):
		return signature
	for raw_stroke in raw_strokes:
		if not (raw_stroke is Dictionary):
			continue
		var stroke: Dictionary = raw_stroke
		var points := PackedVector2Array()
		var times := PackedFloat32Array()
		var raw_points: Variant = stroke.get("p", [])
		if raw_points is Array:
			var flat: Array = raw_points
			# 奇偶配对：x0 y0 x1 y1 …
			var i := 0
			while i + 1 < flat.size():
				points.append(Vector2(float(flat[i]), float(flat[i + 1])))
				i += 2
		var raw_times: Variant = stroke.get("t", [])
		if raw_times is Array:
			for value in (raw_times as Array):
				times.append(float(value))
		# 时间戳比点少也不能错位：缺的按最后一个补（宁可匀速，不要数组越界）
		while times.size() < points.size():
			times.append(times[times.size() - 1] if times.size() > 0 else 0.0)
		signature.strokes.append({
			"p": points,
			"t": times,
			"g": int(stroke.get("g", 0)),
		})
	return signature
