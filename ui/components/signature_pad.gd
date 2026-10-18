class_name SignaturePad
extends Control

## 签名画布（ui/components/signature_pad.tscn）。
##
## 「写」和「放」是**同一个渲染函数**的两个用法：
##   RECORD —— 左键按下开始写，松开即结束（**一笔画**，见下）；
##   REPLAY —— 按存下来的时间戳把笔迹重描一遍，或者直接把 playhead 拖到终点静态显示。
## 所以「复现签名的过程」不是另写的功能，只是让 _playhead 从头跑一趟。
##
## ⚠️ **一笔画**：松手 = 签名结束，不是「这一笔结束」。所以签完就不再接受落笔
##    （要重签请调 clear()）。想改回多笔签名，放开 _gui_input 里那句 `if _signed: return`
##    即可 —— 数据层（Signature.strokes）本来就是多笔的。
##
## ⚠️ **出界不拽鼠标**：鼠标跑到画布外面时只把**笔迹**吸附到最近的边界（_clamp_pos），
##    绝不去动系统光标。那只手是玩家自己的（Haohan），挪它就是抢方向盘。
##
## ⚠️ 不定时采样，只认事件：点与点之间的距离小于 min_point_distance_px 就丢掉。
##    既去抖、又压存档体积 —— 鼠标 1000Hz 也不至于把一段字记成几千个点。

## 玩家按下左键，开始落笔（牌子据此把光标换成蘸了墨的那只，见 haohan.gd）
signal signing_started

## 这一笔结束了（松手；无论有没有签成）—— 光标可以还原了
signal signing_finished

## 一笔有效笔迹完成。调用方拿它去写给存档。
signal signature_completed(signature: Signature)

## 墨色。压在米黄纸面上要够深，但别用纯黑 —— 纯黑在暖底上显得脏。
@export var ink_color: Color = Color(0.09, 0.06, 0.05)

## 线宽 = 画布高 × 这个比例。跟着画布缩放，缩成缩略图也不会变成一根头发。
@export var ink_width_ratio: float = 0.020

## 空白画布的纸面颜色。alpha = 0 就是**不铺垫子**（盖在自家美术上的场合用，此时
## 只看得到墨迹和提示字）。
## 底板由 `_draw()` 自己画，不用子节点 —— 这样「纸面 / 边线 / 墨迹」的层级只由
## `_draw` 里的语句顺序决定，不必再操心 show_behind_parent 这类隐式规则。
@export var backdrop_color: Color = Color(0.996, 0.988, 0.961, 1.0)

## 画布边线：没有它，一大片白看起来更像「渲染漏了」而不是「一块画布」。
## `border_width = 0` 就是不画边。
@export var border_color: Color = Color(0.357, 0.298, 0.239, 1.0)
@export var border_width: float = 2.0

## 笔迹总长不到它（像素）就不算签名：按下就松的一次误点，不该把人「签」了。
@export var min_length_px: float = 14.0

## 相邻两点距离小于它就不记（去抖 + 压体积）
@export var min_point_distance_px: float = 1.5

## 回放速度倍数（1.0 = 当初写的节奏）。`play_signature(sig, fit_seconds)` 会临时盖过它。
@export var playback_speed: float = 1.0

## 画布上要不要显示那行提示字。
## 只用来**回放**的画布（例如战报右下角那枚签名）应设成 false —— 没有人会在那儿落笔，
## 「按住左键签名」只会让人困惑。
@export var show_hint: bool = true

## 还没落笔时的提示字
@export var hint_idle: String = "在画布上按住左键，一笔签完"

## 签完之后换成这句（一句话交代「这就完事了」）
@export var hint_signed: String = "已签好"

## 已完成的笔迹（签完的 / 从存档读回来要显示的）
var _signature: Signature = null

## 正在写的这一笔（**归一化坐标**，和 _signature 里存的是同一种东西，
## 所以 _draw 对两者用同一套换算，没有「录的时候一套、放的时候另一套」）
var _live_points := PackedVector2Array()
var _live_times := PackedFloat32Array()
var _live_length_px: float = 0.0

## 此刻笔尖是不是按在纸上
var _drawing: bool = false

## 是否已经签好（一笔画：签好就定了）
var _signed: bool = false

## 画布是否在「等玩家签名」。**没等的时候一律不收输入** —— 否则一块只是用来
## 展示签名的牌子会白吃掉点击。
var _armed: bool = false

## 回放进度（毫秒）
var _playhead_ms: float = 0.0
var _playing: bool = false

## 这次回放的实际倍速。由 play_signature() 定：playback_speed 与「N 秒内播完」取其一。
var _play_speed: float = 1.0

## 落笔瞬间的 tick，用来算每点的时间戳
var _stroke_started_tick: int = 0

@onready var _hint: Label = get_node_or_null("Hint") as Label


func _ready() -> void:
	# 一开始就不收输入，等调用方 set_armed(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()
	set_process(false)


# ---------------------------------------------------------------------------
# 对外接口
# ---------------------------------------------------------------------------


## 是否已经签好（调用方据此决定「这一句能不能翻页」）
func is_signed() -> bool:
	return _signed


## 已完成的那段签名（没有则 null）
func signature() -> Signature:
	return _signature


## 是否正在等签名
func is_armed() -> bool:
	return _armed


## 进入 / 退出「等签名」状态。
##
## ⚠️ 没等签名时把拾取让出去（MOUSE_FILTER_IGNORE）：牌子上的画布不该在
##    只是展示的场合吃掉点击。这条和「空就是空」是同一类规矩 —— 状态要收干净。
func set_armed(armed: bool) -> void:
	if _armed == armed:
		return
	_armed = armed
	if not armed and _drawing:
		# 中途被收走（翻页 / 收牌子）：按松手处理，别把笔留在按下状态
		_end_stroke()
	mouse_filter = Control.MOUSE_FILTER_STOP if armed else Control.MOUSE_FILTER_IGNORE
	_refresh()


## 重签：把画布擦干净，回到「等落笔」的状态
func clear() -> void:
	_signature = null
	_live_points = PackedVector2Array()
	_live_times = PackedFloat32Array()
	_live_length_px = 0.0
	_drawing = false
	_signed = false
	_playhead_ms = 0.0
	_playing = false
	set_process(false)
	_refresh()


## 直接显示一段签名。
## instant = true → 一帧画完（静态展示）；false → 从第一点开始，用 play_signature 播。
##
## 形参叫 incoming 而不是 signature：本类有个同名的 signature() 取值方法，
## 用同名局部变量会触发 SHADOWED_VARIABLE 警告（反正读起来也更清楚）。
func show_signature(incoming: Signature, instant: bool = true) -> void:
	_signature = incoming
	_signed = incoming != null and not incoming.is_empty()
	_playing = false
	set_process(false)
	_playhead_ms = _end_playhead() if instant else 0.0
	_refresh()


## 「全部画完」那个时刻。
##
## ⚠️ 不是 duration_ms()，而是它 + 1ms：时间戳是 10ms 量化的，一段**极短**的笔迹
##    （甚至所有点都落在同一毫秒里）总时长可能是 0，playhead 停在 0 就一笔都画不出来 ——
##    静态显示会变成一张空牌。加一点余量，让「画完」永远是画完。
func _end_playhead() -> float:
	return (_signature.duration_ms() if _signature != null else 0.0) + 1.0


## 把签名「再写一遍」——这就是「复现签名的过程」。
##
## fit_seconds（默认 0 = 按原节奏播）：
##   大于 0 时**自动加速**，让整段在这么多秒内播完，节奏按比例压缩。
##   用途是「播放位置有硬时限」的场合 —— 例如战报点确认后要在 1 秒内把字盖上去，
##   再播完就该翻页了。手写 2 秒的签名压到 1 秒，笔画顺序和相对快慢都不变，只是整体变快。
##
##   ⚠️ 只压缩、不拉伸：fit_seconds 比原来还长时不会变慢（这里取「按比例」，不是「等比放慢」）。
##      真要慢放，用 playback_speed。
func play_signature(incoming: Signature, fit_seconds: float = 0.0) -> void:
	show_signature(incoming, false)
	if _signature == null or _signature.is_empty():
		return

	var total := _signature.duration_ms()
	_play_speed = maxf(playback_speed, 0.01)
	if total <= 0.0:
		# 总时长为 0（时间戳被量化压平了）：没有「过程」可播，直接画完，
		# 否则 playhead 停在 0，一帧都画不出来。
		_playhead_ms = _end_playhead()
		_refresh()
		return
	if fit_seconds > 0.0:
		# 原速要 total 毫秒，现在要求在 fit_seconds 秒内播完 → 倍速就是两者之比
		_play_speed = total / (fit_seconds * 1000.0)

	# 播的时候不接受落笔，免得别人一边看一边往里加笔
	_playing = true
	set_process(true)


## 这次回放的**实际**倍速（playback_speed 与 fit_seconds 算出来的那个）。调试 / 自检用。
func play_speed() -> float:
	return _play_speed


## 此刻（给定回放时间）能看到几个点 —— 自检用，也方便将来做进度条
func visible_point_count(playhead_ms: float = -1.0) -> int:
	if _signature == null:
		return 0
	var at: float = _playhead_ms if playhead_ms < 0.0 else playhead_ms
	var total := 0
	for i in range(_signature.strokes.size()):
		var stroke: Dictionary = _signature.strokes[i]
		var local: float = at - _signature.stroke_start_ms(i)
		# 和 _draw_stroke 一个口径：< 0 才算「还没到这一笔」，等于 0 时起笔点已经落下
		if local < 0.0:
			continue
		var times: PackedFloat32Array = stroke.get("t", PackedFloat32Array())
		for t in times:
			if float(t) <= local:
				total += 1
	return total


# ---------------------------------------------------------------------------
# 输入：落笔 / 走笔 / 收笔
# ---------------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not _armed:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# 一笔画：签过了就不再接受落笔
			if _signed or _playing:
				return
			_begin_stroke(event.position)
		elif _drawing:
			_end_stroke()
		accept_event()
		return

	# ⚠️ 一帧内可能来好几个 motion；这里**逐点**收，不做时间插值 ——
	#    时间戳来自真实 tick，回放时才是当初那个节奏。
	if event is InputEventMouseMotion and _drawing:
		_append_point(event.position)
		accept_event()


func _begin_stroke(local_pos: Vector2) -> void:
	_drawing = true
	_live_points = PackedVector2Array()
	_live_times = PackedFloat32Array()
	_live_length_px = 0.0
	_stroke_started_tick = Time.get_ticks_msec()
	signing_started.emit()
	_append_point(local_pos)
	_refresh()  # 让提示字让开（见 _refresh）


## 追加一个点。**先吸附到边界再判断去抖** —— 顺序反了的话，鼠标在画布外面
## 反复挪动会给同一个吸附点记上几十个时间戳，回放时那一段就会「停」很久。
func _append_point(local_pos: Vector2) -> void:
	var canvas_rect := Rect2(Vector2.ZERO, size)
	var point := _clamp_pos(local_pos)
	if _live_points.size() > 0:
		var last := Signature.to_canvas(canvas_rect, _live_points[_live_points.size() - 1])
		var distance := last.distance_to(point)
		if distance < min_point_distance_px:
			return
		_live_length_px += distance
	_live_points.append(Signature.to_normalized(canvas_rect, point))
	# ⚠️ 时间戳必须**严格递增**：同一毫秒里落下两个点时，时间轴会退化
	#    （整段 duration = 0，回放时所有点在一帧里糊上去）。人手写不出同毫秒的两点，
	#    这条只是在钉真实鼠标的高频采样、以及自检里那种一口气推完的合成输入。
	var stamp := float(Time.get_ticks_msec() - _stroke_started_tick)
	if _live_times.size() > 0:
		stamp = maxf(stamp, _live_times[_live_times.size() - 1] + 1.0)
	_live_times.append(stamp)
	queue_redraw()


## 出界的点吸附到最近的边界。**只挪笔迹，不动鼠标**（见文件头）。
func _clamp_pos(local_pos: Vector2) -> Vector2:
	return Vector2(
		clampf(local_pos.x, 0.0, size.x),
		clampf(local_pos.y, 0.0, size.y),
	)


func _end_stroke() -> void:
	_drawing = false
	var signed_now := _live_points.size() >= 2 and _live_length_px >= min_length_px
	if signed_now:
		var built := Signature.new()
		built.canvas = size
		built.strokes.append({
			"p": _live_points.duplicate(),
			"t": _live_times.duplicate(),
			"g": 0,
		})
		_signature = built
		_signed = true
		_playhead_ms = _end_playhead()
	else:
		# 一次误点（按下就松，几乎没移动）：不算签名，擦掉，仍旧等玩家落笔
		_live_points = PackedVector2Array()
		_live_times = PackedFloat32Array()
		_live_length_px = 0.0

	# 存进去的是 duplicate，这里把「正在写的」那一份清掉，
	# 免得以后再落笔时把已完成的笔迹一起改掉
	_live_points = PackedVector2Array()
	_live_times = PackedFloat32Array()

	signing_finished.emit()
	_refresh()
	if _signed:
		signature_completed.emit(_signature)


# ---------------------------------------------------------------------------
# 回放
# ---------------------------------------------------------------------------


func _process(delta: float) -> void:
	if not _playing or _signature == null:
		set_process(false)
		return
	# 用这次回放的**实际**倍速（可能是「N 秒内播完」算出来的），不是导出值
	_playhead_ms += delta * 1000.0 * _play_speed
	var total := _signature.duration_ms()
	if _playhead_ms >= total:
		_playhead_ms = total
		_playing = false
		set_process(false)
	queue_redraw()


# ---------------------------------------------------------------------------
# 画
# ---------------------------------------------------------------------------


func _refresh() -> void:
	if _hint != null:
		_hint.text = hint_signed if _signed else hint_idle
		# 正在落笔 / 正在回放时把提示让开：它就压在画布正中，挡着玩家看自己写的字。
		# show_hint = false 是「这块画布只负责回放」，一行提示都不该出现。
		_hint.visible = show_hint and not _playing and not _drawing
	queue_redraw()


func _draw() -> void:
	var canvas_rect := Rect2(Vector2.ZERO, size)
	var line_width := maxf(size.y * ink_width_ratio, 1.0)

	# 先铺纸面、再描边、最后才是墨迹 —— 顺序就是层级，不需要任何子节点配合
	if backdrop_color.a > 0.0:
		draw_rect(canvas_rect, backdrop_color, true)
	if border_width > 0.0:
		draw_rect(canvas_rect.grow(-border_width * 0.5), border_color, false, border_width)

	if _signature != null:
		for i in range(_signature.strokes.size()):
			var stroke: Dictionary = _signature.strokes[i]
			var local_ms: float = _playhead_ms - _signature.stroke_start_ms(i)
			_draw_stroke(stroke, canvas_rect, line_width, local_ms)

	# 正在写的这一笔（归一化 → 画布坐标，和上面走同一套换算）
	if _live_points.size() >= 2:
		var points := PackedVector2Array()
		for normalized in _live_points:
			points.append(Signature.to_canvas(canvas_rect, normalized))
		draw_polyline(points, ink_color, line_width, true)
	elif _live_points.size() == 1:
		draw_circle(
			Signature.to_canvas(canvas_rect, _live_points[0]), line_width * 0.5, ink_color)


## 把一笔画到「本笔内第 local_ms 毫秒」为止。
##
## 段内插值：笔画到第 i-1 到第 i 点之间时，按时间比例算一个中间点补上去 ——
## 不补的话回放是一跳一跳的（时间戳是 10ms 量化的，60fps 下肉眼就能看出来）。
func _draw_stroke(stroke: Dictionary, canvas_rect: Rect2, line_width: float, local_ms: float) -> void:
	# < 0 才算「还没到这一笔」；等于 0 时要画下去（第一点的 t 就是 0）
	if local_ms < 0.0:
		return
	var normalized: PackedVector2Array = stroke.get("p", PackedVector2Array())
	var times: PackedFloat32Array = stroke.get("t", PackedFloat32Array())
	var count := normalized.size()
	if count == 0:
		return
	if count == 1:
		draw_circle(Signature.to_canvas(canvas_rect, normalized[0]), line_width * 0.5, ink_color)
		return

	var points := PackedVector2Array()
	for i in range(count):
		var stamp: float = times[i] if i < times.size() else 0.0
		if stamp > local_ms:
			# 插值：上一个点和这一个点之间按时间比例补一个
			if i > 0:
				var prev_stamp: float = times[i - 1] if i - 1 < times.size() else 0.0
				var span := maxf(stamp - prev_stamp, 0.0001)
				var ratio := clampf((local_ms - prev_stamp) / span, 0.0, 1.0)
				points.append(Signature.to_canvas(
					canvas_rect, normalized[i - 1].lerp(normalized[i], ratio)))
			break
		points.append(Signature.to_canvas(canvas_rect, normalized[i]))

	if points.size() >= 2:
		draw_polyline(points, ink_color, line_width, true)
	elif points.size() == 1:
		draw_circle(points[0], line_width * 0.5, ink_color)
