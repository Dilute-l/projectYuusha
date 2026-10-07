class_name Resume
extends Control

## 候选人的完整简历（ARCHITECTURE.md §4「resume.tscn」、§3.1、§6.2）。
##
## 版面 = assets/art/interview/resume_page_phd.png 这张纸 + 贴在纸上的文字：
## 上半是基础信息（姓名 / 职业 / 等级 / 三项属性 / 特质），
## 下半是若干条简历词条，每条一个 resume_token.tscn 实例（复用控件）。
##
## ⚠️ 数据来源：**当前一行业务数据都不读**。
##   不碰 DataDB、不碰 CandidateResource、不碰 GameState.current_candidates，
##   纸上的字全部来自下面那组 PLACEHOLDER_* 常量。
##   M1 候选人数据落地后，把 _ready() 里的 _apply_placeholder() 换成
##   「set_info(...) + set_entries(candidate.resume 的 description 数组)」，
##   版面代码一行都不用动：抬头那一整块就是一个字符串，
##     姓名 ← candidate.display_name，职业 ← candidate.job.display_name，
##     等级 ← candidate.level，属性 ← strength / intelligence / wisdom，
##     特质 ← candidate.traits，词条 ← candidate.resume（逐条取 description）。
##
## ⚠️ 文案暂用 ASCII：assets/fonts 还没接入中文主字体，默认字体没有中文字形，
##   直接写中文会变成方块（同 §10.5 里占位 HUD 的处理）。字体接进来后
##   把 PLACEHOLDER_* 换成中文即可，这里的字符串本身与字体无关。

const TOKEN_SCENE := preload("res://scenes/day/interview/resume/resume_token.tscn")

# ---- 占位数据：写死，不来自数据库 -------------------------------------------
# （下面这一整块是临时内容，M1 接上候选人数据后整块删掉。）

## 抬头：姓名 / 职业 + 等级 / 三项属性 / 特质 —— **全部拼在同一个字符串里**，
## 对应场景里 Paper/Rows/HeaderInfo 这**一个** Label（多行）。
## 想调抬头版式（换行、字段间距、字段顺序）直接改这个常量，不用动场景。
const PLACEHOLDER_INFO := """我是·名字
这里是 描述第一行
这里是 描述第二行
"""

const PLACEHOLDER_CAPTION := "RESUME ENTRIES"

## 五条占位简历词条，逐条铺成 resume_token
const PLACEHOLDER_ENTRIES: Array[String] = [
	"Slew three ogres single-handedly on the Border Watch.",
	"Graduated first in class from the Royal Sword Academy.",
	"Fluent in Ancient Draconic, Elvish and Dwarvish.",
	"Survived fourteen days alone in the Cursed Marsh.",
	"Never lost a duel in six years of royal service.",
]

# ---- 节点 -------------------------------------------------------------------

@onready var _info_label: Label = $Paper/Rows/HeaderInfo
@onready var _caption_label: Label = $Paper/Rows/EntriesCaption
@onready var _token_list: VBoxContainer = $Paper/Rows/TokenList


func _ready() -> void:
	_apply_placeholder()


## 铺一整份简历。M1 接上候选人数据后由调用方拿 candidate.resume 喂进来。
## descriptions 里每一条 = 一条 ResumeEntry.description（§3.2）。
func set_entries(descriptions: Array) -> void:
	# 场景里预摆了 5 个 ResumeToken 实例：编辑器一打开就能看到真实版面。
	# 数据条数和预摆数对不上时按数据走 —— 多的现场新建，富余的隐藏，
	# 所以「若干项」都能撑住，不用改场景。
	var placed := _token_list.get_children()
	for i in descriptions.size():
		var token: ResumeToken
		if i < placed.size():
			token = placed[i] as ResumeToken
			token.visible = true
		else:
			token = TOKEN_SCENE.instantiate() as ResumeToken
			token.name = "ResumeToken%d" % (i + 1)
			_token_list.add_child(token)
		token.set_entry(i, String(descriptions[i]))

	for i in range(descriptions.size(), placed.size()):
		(placed[i] as Control).visible = false


## 换抬头。姓名 / 职业 / 等级 / 属性 / 特质整块就是**一个**字符串，
## 怎么分行、怎么对齐都在字符串里排，不用再去点散落的 Label。
func set_info(text: String) -> void:
	_info_label.text = text


# ---- 占位数据 ---------------------------------------------------------------

func _apply_placeholder() -> void:
	set_info(PLACEHOLDER_INFO)
	_caption_label.text = PLACEHOLDER_CAPTION
	set_entries(PLACEHOLDER_ENTRIES)
