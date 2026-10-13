class_name PortraitComposer
extends RefCounted

## 立绘部件的「文件命名」与「拼装」的唯一出处（ARCHITECTURE.md §3.1 / §4 / §12）。
##
## 立绘不是一整张图，而是按部位拼出来的（配方写在 CandidateResource 的 portrait_* 字段里）：
##
##     身体 + 眼睛 / 头发 / 嘴巴   （hu / el）
##     身体 + 帽子                 （st 戴帽子，其他种族可选）
##
## 命名规则原本只写在 scenes/day/interview/interviewee.gd 里；组队界面的头像框
## 也要用同一套图，于是抽到这里 —— **改文件名 / 加种族只改本文件**：
##
##   * `interviewee.gd`     逐个部件摆 Sprite2D（面试立绘，行为原样保留）
##   * `portrait_texture()` 把所有部件拼成一张**整身立绘**（组队界面头像框）
##
## ⚠️ 所有部件图都是同一个 `CANVAS × CANVAS_H` 画布坐标系的一部分，所以「直接原地叠加」
##   不会错位：每个人物都画在这张画布的同一处，换差分只换脸，身体一动不动。
##   组队界面要的是**原位**的整身（§12.4）：不取景、不居中、不裁圆 ——
##   露出来多少由头像框的取景窗决定，人物在框里的位置只由立绘自己决定。

## 部件贴图目录
const DIR := "res://assets/art/portrait/"

## 立绘画布：宽 × 高（像素）。**这是立绘自己的坐标系**，不是屏幕上的大小 ——
## 面试立绘靠节点 scale 缩放它，头像框靠 `AvatarFrame.PORTRAIT_SCALE` 缩放它。
##
## ⚠️ 这两个数必须等于实际贴图的尺寸：`compose()` 用它开画布，
##   比贴图小就会把人物的右下角整块切掉（头像框里只剩左上角就是这么来的）。
const CANVAS := 600
const CANVAS_H := 675

## 用 tall_* 系列（眼 / 发 / 嘴）的种族；其余（st）用 st_hat_*
const TALL_RACES: Array[StringName] = [&"hu", &"el"]

## 立绘贴图缓存：key = 配方签名。立绘在界面上是静态的，
## 每次刷新都重拼一遍纯属浪费（一次拼装要过 1 万多个像素）。
static var _cache: Dictionary = {}


# ---------------------------------------------------------------------------
# 部件命名（唯一出处）
# ---------------------------------------------------------------------------


## 该种族是否用「眼睛 / 头发 / 嘴巴」这套人脸部件。
## （矮人只有身体 + 帽子 —— 这条规则没变，变的只是文件名。）
static func is_tall(race: StringName) -> bool:
	return TALL_RACES.has(race)


## 「不戴帽子」。除矮人外，portrait_hat 填这个值就是不画帽子。
const NO_HAT := 0

## 部件编号是**四位数字**：<组><组内编号>。
##
##     eye / hair   组 01 = 男、02 = 女、99 = 特殊
##     mouth        组 01 = 通用、99 = 特殊
##     hat          组 01 = 矮人、02 = 其他、99 = 特殊
##
## CandidateResource 里存的是**整数**（101 就是文件名里的 "0101"），所以这里补零还原。
## 占位符候选人一律 101。
static func part_code(index: int) -> String:
	return "%04d" % index


## 身体：所有种族都有 → <race>_body.png
static func body_stem(race: StringName) -> String:
	return "%s_body" % race


## 眼睛：仅 hu / el；不适用的种族返回空串（调用方据此清空贴图）
static func eye_stem(race: StringName, index: int) -> String:
	return "eye_%s" % part_code(index) if is_tall(race) else ""


## 头发：仅 hu / el
static func hair_stem(race: StringName, index: int) -> String:
	return "hair_%s" % part_code(index) if is_tall(race) else ""


## 嘴巴：所有种族共用一套（新素材的嘴不分种族，编号只分「通用 01 / 特殊 99」）
static func mouth_stem(_race: StringName, index: int) -> String:
	return "mouth_%s" % part_code(index)


## 帽子：**可选件**，这是与旧命名规则唯一的行为差别。
##
##   矮人（st）  ：默认就戴（portrait_hat = 101 → hat_0101），换帽子改这个数
##   其他种族    ：portrait_hat == 0 = **不戴帽子**；填了数才画
##
## 旧规则是「只有矮人有帽子、其他人一律没有」，现在变成「谁都可以戴，只是要显式填」。
## 参数留 `_race`：戴不戴只由编号决定，但函数签名要与兄弟函数（眼 / 发 / 嘴）一致。
static func hat_stem(_race: StringName, index: int) -> String:
	if index == NO_HAT:
		return ""
	return "hat_%s" % part_code(index)


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
# 立绘
# ---------------------------------------------------------------------------


## 候选人的**整身立绘**贴图（组队界面头像框取景窗后面那一张）：`CANVAS × CANVAS_H`
## **原位**，不取景、不裁圆、不缩放 —— 露出来多少由头像框的取景窗决定（§12.4）。
##
## 头像框要的就是整张画布：立绘按自己的坐标系铺满整个框，只有窗口里那一块看得见，
## 所以既不用居中、也不用算取景框。第一次调用拼一次并缓存，之后直接拿同一张。
static func portrait_texture(candidate: CandidateResource) -> ImageTexture:
	if candidate == null:
		return null
	var key := _cache_key(candidate)
	if _cache.has(key):
		return _cache[key]
	var texture := ImageTexture.create_from_image(compose(candidate))
	_cache[key] = texture
	return texture


## 丢掉贴图缓存（换了立绘 / 测完一局之后调用）
static func clear_cache() -> void:
	_cache.clear()


## 把候选人的部件叠成一张 `CANVAS × CANVAS_H` 的图（相当于「拼装立绘」的静态版本）
static func compose(candidate: CandidateResource) -> Image:
	var canvas := Image.create_empty(CANVAS, CANVAS_H, false, Image.FORMAT_RGBA8)
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


## 缓存 key：配方（种族 + 各部件编号）。同一个人换配方会自动重拼。
static func _cache_key(candidate: CandidateResource) -> String:
	return "%s|%s|%d%d%d%d" % [
		candidate.id,
		candidate.portrait_race,
		candidate.portrait_eye,
		candidate.portrait_hair,
		candidate.portrait_mouth,
		candidate.portrait_hat,
	]
