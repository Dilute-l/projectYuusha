class_name PortraitComposer
extends RefCounted

## 立绘部件的「文件命名」与「拼装」的唯一出处（ARCHITECTURE.md §3.1 / §4 / §12）。
##
## 立绘不是一整张图，而是按部位拼出来的（配方写在 CandidateResource 的 portrait_* 字段里）：
##
##     身体 + 眼睛 / 头发 / 嘴巴   （hu / el，tall_* 系列）
##     身体 + 帽子                 （st，st_hat_* 系列）
##
## 命名规则原本只写在 scenes/day/interview/interviewee.gd 里；组队界面的圆形头像
## 也要用同一套图，于是抽到这里 —— **改文件名 / 加种族只改本文件**：
##
##   * `interviewee.gd`   逐个部件摆 Sprite2D（面试立绘，行为原样保留）
##   * `avatar_texture()` 把所有部件拼成一张**圆形头像**（组队界面左侧）
##
## ⚠️ 所有部件图都是同一个 300x300 画布坐标系的一部分（实测，见 §12 的探针数据），
##   所以「同一个取景框套在每个部件上」不会错位 —— 圆头像就是靠这一点拼的。

## 部件贴图目录
const DIR := "res://assets/art/portrait/"

## 每个部件图的画布边长。部件图都按这个画布对齐，拼装时直接原地叠加即可。
const CANVAS := 300

## 用 tall_* 系列（眼 / 发 / 嘴）的种族；其余（st）用 st_hat_*
const TALL_RACES: Array[StringName] = [&"hu", &"el"]

## 部件编号范围，对应 *_phd1..3 三个文件
const PART_MIN := 1
const PART_MAX := 3

## 头像取景的留白比例：拼好的整身四周多留这么多（1.12 = 上下左右各留 6%）。
##
## 取景框是**自动**算的（见 framing_for_image）：先拼出整身，量出它的 alpha 包围盒，
## 再把包围盒居中放进一个正方形 —— 正方形内切于圆，所以框外的东西一律被圆裁掉。
## 好处是换立绘、加种族、换帽子都不用回来调常量：
## 矮人的三顶帽子（宽檐 / 小圆帽 / 高帽）身量差一倍，自动取景各自都站得住。
const AUTO_MARGIN := 1.12

## 一个部件都没拼出来时（数据配错 / 贴图丢了）退回去的取景框：整张画布
const FRAMING_FALLBACK := Rect2(0, 0, CANVAS, CANVAS)

## 头像贴图缓存：key = 配方签名 + 尺寸。头像在界面上是静态的，
## 每次悬停 / 刷新都重拼一遍纯属浪费（一次拼装要过 1 万多个像素）。
static var _cache: Dictionary = {}


# ---------------------------------------------------------------------------
# 部件命名（唯一出处）
# ---------------------------------------------------------------------------


## 该种族是否用 tall_* 系列部件（眼 / 发 / 嘴）
static func is_tall(race: StringName) -> bool:
	return TALL_RACES.has(race)


## 身体：所有种族都有
static func body_stem(race: StringName) -> String:
	return "%s_body_phd" % race


## 眼睛：仅 hu / el；不适用的种族返回空串（调用方据此清空贴图）
static func eye_stem(race: StringName, index: int) -> String:
	return "tall_eye_phd%d" % index if is_tall(race) else ""


## 头发：仅 hu / el（注意是 hir，不是 hair —— 文件本来就叫这个）
static func hair_stem(race: StringName, index: int) -> String:
	return "tall_hir_phd%d" % index if is_tall(race) else ""


## 嘴巴：仅 hu / el
static func mouth_stem(race: StringName, index: int) -> String:
	return "tall_mth_phd%d" % index if is_tall(race) else ""


## 帽子：仅 st
static func hat_stem(race: StringName, index: int) -> String:
	return "st_hat_phd%d" % index if not is_tall(race) else ""


## 部件文件名 → res:// 路径
static func path_of(stem: String) -> String:
	return DIR + stem + ".png"


## 按部件名取贴图；找不到就报错，绝不静默（空串 = 该种族不用这个部件，返回 null 且不报错）
static func load_part(stem: String) -> Texture2D:
	if stem.is_empty():
		return null
	var path := path_of(stem)
	if not ResourceLoader.exists(path):
		push_error("[PortraitComposer] 找不到贴图：%s" % path)
		return null
	return load(path)


## 一位候选人要拼的全部部件，**按绘制顺序**：身体 → 眼睛 → 头发 → 嘴巴 / 帽子。
## （与 interviewee.tscn 里 Sprite2D 的节点顺序一致，拼出来的样子才是面试时的样子。）
static func stems_for(candidate: CandidateResource) -> Array[String]:
	var stems: Array[String] = []
	if candidate == null:
		return stems
	var race := candidate.portrait_race
	stems.append(body_stem(race))
	for stem in [
		eye_stem(race, candidate.portrait_eye),
		hair_stem(race, candidate.portrait_hair),
		mouth_stem(race, candidate.portrait_mouth),
		hat_stem(race, candidate.portrait_hat),
	]:
		if not stem.is_empty():
			stems.append(stem)
	return stems


# ---------------------------------------------------------------------------
# 头像
# ---------------------------------------------------------------------------


## 候选人的圆形头像贴图（组队界面左侧那一圈）。candidate 为 null 时返回 null。
##
## size = 头像直径（像素）。第一次调用会拼一次并缓存，之后直接拿同一张。
static func avatar_texture(candidate: CandidateResource, size: int) -> ImageTexture:
	if candidate == null or size <= 0:
		return null
	var key := _cache_key(candidate, size)
	if _cache.has(key):
		return _cache[key]
	var texture := ImageTexture.create_from_image(avatar_image(candidate, size))
	_cache[key] = texture
	return texture


## 丢掉贴图缓存（换了立绘 / 测完一局之后调用）
static func clear_cache() -> void:
	_cache.clear()


## 拼一张头像图：部件叠成 300x300 → 按内容自动取景 → 缩到 size → 套圆形遮罩。
## 拆开给测试用（可以直接拿图验「圆外是透明的」「人在圆中间」）。
static func avatar_image(candidate: CandidateResource, size: int) -> Image:
	var composed := compose(candidate)
	var framed := _frame(composed, framing_for_image(composed), size)
	_apply_circle_mask(framed)
	return framed


## 该候选人的取景框（调试 / 测试用；正式拼装时用 framing_for_image 免得拼两遍）
static func framing_for(candidate: CandidateResource) -> Rect2:
	return framing_for_image(compose(candidate))


## 取景框：把拼好的整身「居中框住」。
##
## 量的是 alpha 包围盒（有内容的那一块），所以这个人戴什么帽子、是矮人还是精灵
## 都不用另外配常量；框是正方形（内切于圆），四周留 AUTO_MARGIN 的余量。
## 一个部件都没拼出来时退回整张画布 —— 宁可画得小，也不要画错位。
static func framing_for_image(composed: Image) -> Rect2:
	var used := composed.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		push_warning("[PortraitComposer] 拼出来是空的，退回整张画布取景")
		return FRAMING_FALLBACK
	var side := maxf(float(used.size.x), float(used.size.y)) * AUTO_MARGIN
	var center := Vector2(used.position) + Vector2(used.size) * 0.5
	return Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side))


## 把候选人的部件叠成一张 300x300 的图（相当于「拼装立绘」的静态版本）
static func compose(candidate: CandidateResource) -> Image:
	var canvas := Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	for stem in stems_for(candidate):
		var texture := load_part(stem)
		if texture == null:
			continue
		var part := texture.get_image()
		if part == null:
			push_error("[PortraitComposer] 部件取不到像素：%s" % path_of(stem))
			continue
		# blend_rect 要求两图格式一致；导入后的贴图格式随导入设置而变，统一转一次
		part.convert(Image.FORMAT_RGBA8)
		canvas.blend_rect(part, Rect2i(0, 0, part.get_width(), part.get_height()), Vector2i.ZERO)
	return canvas


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------


## 取景：把取景框那一块从 300x300 画布上「拍照」下来，再缩到 size x size。
##
## 取景框可以超出部件画布（矮人的框就伸到画布下方），越界的地方留透明 ——
## 所以这里按「两个矩形的交集」拷贝，而不是直接 blit（负数目标位置会报错）。
static func _frame(src: Image, frame: Rect2, size: int) -> Image:
	var out_w := int(frame.size.x)
	var out_h := int(frame.size.y)
	var out := Image.create_empty(out_w, out_h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))

	# 部件图的 (0,0) 落在输出画布的哪个位置
	var dst := Vector2i(-int(frame.position.x), -int(frame.position.y))
	var src_x := maxi(0, -dst.x)
	var src_y := maxi(0, -dst.y)
	var pos := Vector2i(dst.x + src_x, dst.y + src_y)
	var w := mini(CANVAS - src_x, out_w - pos.x)
	var h := mini(CANVAS - src_y, out_h - pos.y)
	if w > 0 and h > 0:
		out.blend_rect(src, Rect2i(src_x, src_y, w, h), pos)

	if out_w != size or out_h != size:
		out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return out


## 圆形遮罩：圆外一律抹成透明，圆边留 1 像素渐变（否则锯齿很难看）。
static func _apply_circle_mask(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var center := Vector2(w, h) * 0.5
	var radius := minf(w, h) * 0.5 - 0.5
	for y in h:
		for x in w:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var mask := clampf(radius - distance + 0.5, 0.0, 1.0)
			if mask >= 1.0:
				continue
			if mask <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var color := img.get_pixel(x, y)
				color.a *= mask
				img.set_pixel(x, y, color)


## 缓存 key：配方（种族 + 各部件编号）+ 尺寸。同一个人换配方会自动重拼。
static func _cache_key(candidate: CandidateResource, size: int) -> String:
	return "%s|%d|%s|%d%d%d%d" % [
		candidate.id,
		size,
		candidate.portrait_race,
		candidate.portrait_eye,
		candidate.portrait_hair,
		candidate.portrait_mouth,
		candidate.portrait_hat,
	]
