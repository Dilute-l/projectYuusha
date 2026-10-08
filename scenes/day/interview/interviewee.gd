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
