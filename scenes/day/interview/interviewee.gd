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

## 立绘部位贴图目录——所有路径集中在这里，以后挪目录只改这一行
const PORTRAIT_DIR := "res://assets/art/portrait/"

## 用 tall_* 系列（眼/发/嘴）的种族；其余（st）用 st_hat_*
const TALL_RACES: Array[StringName] = [&"hu", &"el"]

## 部件编号范围，对应 *_phd1..3 三个文件
const PART_MIN := 1
const PART_MAX := 3

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


func _ready() -> void:
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

	_set_texture(_body, "%s_body_phd" % race)

	var is_tall := race in TALL_RACES
	# 传 false 表示「这个种族不用这个部件」，会把贴图清空
	_set_texture(_eye,   "tall_eye_phd%d" % eye,   is_tall)
	_set_texture(_hair,  "tall_hir_phd%d" % hair,  is_tall)   # ← 是 hir，不是 hair
	_set_texture(_mouth, "tall_mth_phd%d" % mouth, is_tall)
	_set_texture(_hat,   "st_hat_phd%d"  % hat,    not is_tall)


## 拼路径 → load → 赋值。找不到就报错，绝不静默
func _set_texture(node: Sprite2D, file_stem: String, enabled: bool = true) -> void:
	if not enabled:
		node.texture = null
		return
	var path := PORTRAIT_DIR + file_stem + ".png"
	if not ResourceLoader.exists(path):
		push_error("[Interviewee] 找不到贴图：%s" % path)
		node.texture = null
		return
	node.texture = load(path)
