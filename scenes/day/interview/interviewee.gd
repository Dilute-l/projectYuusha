extends Control

## 立绘部位贴图目录——所有路径集中在这里，以后挪目录只改这一行
const PORTRAIT_DIR := "res://assets/art/portrait/"

## 用 tall_* 系列（眼/发/嘴）的种族；其余（st）用 st_hat_*
const TALL_RACES: Array[StringName] = [&"hu", &"el"]

# ---- 数据 ----
var race: StringName = &"hu"
var eye: int = 0
var hair: int = 0
var mouth: int = 0
var hat: int = 0

@onready var _body: Sprite2D = $Body
@onready var _eye: Sprite2D = $Eye
@onready var _hair: Sprite2D = $Hair
@onready var _mouth: Sprite2D = $Mouth
@onready var _hat: Sprite2D = $HatForDwarf


func _ready() -> void:
	apply()


## 按当前数据刷新全部部位
func apply() -> void:
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
