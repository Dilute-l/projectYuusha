class_name Interviewee
extends Control

## 面试者立绘：按部位拼装（ARCHITECTURE.md §4「interviewee.tscn」）。
##
## 立绘不是一整张图，而是「身体 + 眼睛 / 头发 / 嘴巴」或「身体 + 帽子」拼出来的：
## 取值直接对应 assets/art/portrait/ 下的文件名，见 _set_texture()。
##
## ⚠️ 配方来自数据，不来自代码：种族与各部件差分编号全部读自
##   CandidateResource 的 portrait_* 字段（data/candidates/*.tres）。
##   本控件自己不摇随机数、也没有「默认长相」——
##   在 apply_candidate() 之前它什么都不画。
##
## ⚠️ 部件文件名与「哪个种族用哪几个部件」的规则**不在本文件**：
##   统一在 scripts/util/portrait_composer.gd（组队界面的圆头像也走那一套）。
##
## 走路（出场 / 退场）见本文件下半的「走路」一节：横向平移 + 上下晃动，
## 什么时候走、走多远由 interview.gd 决定（§13）。

# ---- 数据（由 apply_candidate() 从候选人资源灌入）----
var race: StringName = &""
var eye: int = 1
var hair: int = 1
var mouth: int = 1
var hat: int = 1

## 是否已经拿到过候选人的立绘配方。没有数据就保持空白 —— 不画「默认人」。
var _has_recipe: bool = false

@onready var _body: Sprite2D = $Body
@onready var _eye: Sprite2D = $Eye
@onready var _hair: Sprite2D = $Hair
@onready var _mouth: Sprite2D = $Mouth
@onready var _hat: Sprite2D = $HatForDwarf

## 「站定」的位置：_ready() 时从场景里摆的那一处记下来（400, 350）。
##
## ⚠️ 一切走路动画都是**相对它**算的：走进来 / 走出去最后都回到这个 y，
##   所以走路不会让立绘在纵向上慢慢飘走，也不会和桌子错位。
var _rest_position: Vector2 = Vector2.ZERO

## 正在跑的走路 Tween；没有 = 站着不动
var _walk_tween: Tween = null


func _ready() -> void:
	# 记下站定位置。必须在任何动画之前 —— _ready() 比 interview.gd 的调度早，
	# 那时还没人动过这个节点。
	_rest_position = position

	# 先填数据再入树的调用顺序下，这里会把正确的一套画出来；
	# 没数据则 apply() 直接返回，保持空白。
	apply()


## 按候选人的立绘配方刷新。这是本控件唯一的业务数据入口。
func apply_candidate(candidate: CandidateResource) -> void:
	if candidate == null:
		return
	race = candidate.portrait_race
	eye = candidate.portrait_eye
	hair = candidate.portrait_hair
	mouth = candidate.portrait_mouth
	hat = candidate.portrait_hat
	_has_recipe = true
	apply()


## 按当前数据刷新全部部位。没有配方时不做任何事（立绘内容不属于表现层的默认值）。
func apply() -> void:
	if not _has_recipe:
		return

	# 部件名 → 贴图 的规则在 PortraitComposer：种族决定用眼 / 发 / 嘴还是帽子，
	# 不适用的部件拿到空串，_set_texture() 会清掉它的贴图（不会残留上一个种族的脸）。
	_set_texture(_body,  PortraitComposer.body_stem(race))
	_set_texture(_eye,   PortraitComposer.eye_stem(race, eye))
	_set_texture(_hair,  PortraitComposer.hair_stem(race, hair))
	_set_texture(_mouth, PortraitComposer.mouth_stem(race, mouth))
	_set_texture(_hat,   PortraitComposer.hat_stem(race, hat))


## 部件名 → load → 赋值。空串 = 这个种族不用这个部件（清空贴图，不报错）；
## 文件真的找不到时 PortraitComposer 会 push_error，绝不静默。
func _set_texture(node: Sprite2D, file_stem: String) -> void:
	node.texture = PortraitComposer.load_part(file_stem)


# ---------------------------------------------------------------------------
# 走路（§13：出场走进来 / 判定后退场走出去）
# ---------------------------------------------------------------------------
#
# 这里只提供「怎么走」这一个动作，**不决定什么时候走、从哪儿走到哪儿** ——
# 那是面试流程的事，落在 interview.gd 的演出调度里。
#
# 走路 = 横向平移 + 上下晃动：
#   横向  position.x  从 from_x 线性走到 to_x（走完全程）
#   纵向  position.y  在站定高度上叠一条 sin 曲线，走完 N 个来回
#
# 两条曲线合在**一个** tween_method 里算，而不是「一个 Tween 管 x、另一个管 y」：
# Godot 的 Tween 是按属性写入的，两个 Tween 同时写 position 只会互相覆盖
# （每帧最后跑的那个说了算），合在一个 method 里就没有这个问题。

## 走路的步频：每秒上下晃几下。横向走多久由调用方给，晃几下按这个节奏算 ——
## 走得快、走得慢都还是同一个人的步频，不会「走得越快抖得越凶」。
const WALK_BOB_HZ := 4.5

## 上下晃动的振幅（像素）：纵向偏移的峰值。9 px 在 1.5 倍缩放的立绘上差不多是一个小跳。
const WALK_BOB_PIXELS := 9.0


## 站定的位置（场景里摆的那一处，立绘与桌子的相对关系靠它守住）
func rest_position() -> Vector2:
	return _rest_position


## 立绘整身的半宽：部件都画在同一张 300x300 的画布上、Sprite2D 居中摆放，
## 所以整身宽度就是画布宽，再乘上节点缩放。
func portrait_half_width() -> float:
	return PortraitComposer.CANVAS * 0.5 * absf(scale.x)


## 画面右边外面：整身刚好完全离开画面的那个 x。
##
## 现算而不是写死 1152：自检会把场景放进别的尺寸的 SubViewport 里跑，
## 而画布尺寸本来就该由 viewport 说了算。
func offscreen_right_x() -> float:
	return _local_x_at_edge(1.0) + portrait_half_width()


## 画面左边外面：同样的算法，方向相反。
func offscreen_left_x() -> float:
	return _local_x_at_edge(-1.0) - portrait_half_width()


## 把「画面某一边的边线」换算成本节点父坐标系里的 x。
##
## 为什么要换算：position 是相对父节点的，而 viewport 的边线是全局的。
## 换算里用的是 global_position 与 position 的差（即父节点在全局里的原点），
## 所以无论此刻立绘正被动画带到哪里，算出来的边线都是同一条。
func _local_x_at_edge(side: float) -> float:
	var rect := get_viewport_rect()
	var edge := rect.position.x + (rect.size.x if side > 0.0 else 0.0)
	return edge - (global_position.x - position.x)


## 从 from_x 走到 to_x：横向匀速，纵向叠一路上下晃动。返回这个 Tween。
##
## 起止两端的晃动都归零（sin(0) = sin(cycles·2π) = 0），所以**不会停在半空中** ——
## 站定时 y 一定回到 rest_position().y。
func walk_to(from_x: float, to_x: float, duration: float) -> Tween:
	stop_walk()
	position = Vector2(from_x, _rest_position.y)

	var cycles := cycles_for(duration)
	_walk_tween = create_tween()
	_walk_tween.tween_method(
		_apply_walk.bind(from_x, to_x, cycles), 0.0, 1.0, duration)
	return _walk_tween


## 这一段路该晃几下：按步频和时长算，至少一下（时长极短时也不该是「没走路」）
static func cycles_for(duration: float) -> int:
	return maxi(1, int(roundf(duration * WALK_BOB_HZ)))


## 走路时 t ∈ [0,1] 处的纵向偏移。
##
## sin 而不是三角波：起止自然收住，中间不会在最高 / 最低点拐硬弯。
## 取负号是因为 Godot 里 y 轴朝下 —— 先抬脚往上，看起来才像迈步。
static func bob_offset(t: float, cycles: int) -> float:
	return -sin(t * float(cycles) * TAU) * WALK_BOB_PIXELS


## tween_method 的回调：把这一帧的位置算出来写进去
func _apply_walk(t: float, from_x: float, to_x: float, cycles: int) -> void:
	position = Vector2(
		lerpf(from_x, to_x, t),
		_rest_position.y + bob_offset(t, cycles),
	)


## 立刻回到站定姿态（跳过动画 / 收场时用）
func stop_walk() -> void:
	if _walk_tween != null and _walk_tween.is_valid():
		_walk_tween.kill()
	_walk_tween = null


## 站到指定横向位置、纵向回到站定高度
func stand_at(x: float) -> void:
	stop_walk()
	position = Vector2(x, _rest_position.y)


## 回到场景里摆的那一处
func stand_still() -> void:
	stand_at(_rest_position.x)


## 是否正在走（演出调度用它判断「站定了没有」）
##
## ⚠️ 判据是 `is_running()` 而**不是** `is_valid()`：跑完之后 `is_valid()` 还会再真几帧
##    （它问的是「这个 Tween 还在不在」，不是「还有没有没跑完的动作」）。
##   拿 `is_valid()` 当「还在走」，会让人多走几步才被认作站定 —— 自检里表现为
##   「简历已经在升了，立绘却还报 walking」。
func is_walking() -> bool:
	return _walk_tween != null and _walk_tween.is_valid() and _walk_tween.is_running()
