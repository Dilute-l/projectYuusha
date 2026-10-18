extends Node

## 悬停高亮自检 —— 全游戏**只有一款**高亮：ui/styles/hover_gray.tres（ARCHITECTURE.md §10.6）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_hover_gray.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 为什么值得一条测试：简历页、战报页、设置页、手册是**四个各自独立的场景文件**，
## 高亮靠它们在 .tscn 里各写一行 `theme_override_styles/hover` 来引用同一份样式。
## 而在编辑器里点一下某个节点的那一栏，Godot 很容易**就地烘一个 sub_resource** 出来 ——
## 那一刻颜色还一样、看着没坏，但从此三个界面各走各的，改一处另外两处不会跟。
## 所以这里查的是「它们引的还是**同一个资源**」，不是「颜色碰巧一样」。
##
## 本测试**只读 .tscn 里写的样式**，不把场景挂进树、不跑它们的 _ready：
## 样式覆盖（theme_override_styles）在 `get_theme_stylebox()` 里优先于主题链，
## 离开场景树一样拿得到 —— 于是不用管战报要 GameState 数据、设置页要接线这些事。

const HOVER_PATH := "res://ui/styles/hover_gray.tres"

## 基准就是**属性值栏**（简历的 Status 按钮）的那款灰，取值见 §10.6：
## 它当年是引擎默认主题的 hover（Color(0.225, 0.225, 0.225, 0.6)，圆角 3），
## 现在被抄成显式资源，好让另外两个界面引同一份。
const EXPECTED_BG := Color(0.225, 0.225, 0.225, 0.6)
const EXPECTED_CORNER := 3

const RESUME := preload("res://scenes/day/interview/resume/resume.tscn")
const BATTLE := preload("res://scenes/day/battle_report.tscn")
const SETTING := preload("res://scenes/common/setting_page.tscn")
const HANDBOOK := preload("res://scenes/day/interview/handbook.tscn")

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_run()
	_report()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK  " if ok else "FAIL", what])


func _run() -> void:
	var hover := load(HOVER_PATH) as StyleBoxFlat
	_check(hover != null, "共用高亮样式能加载：%s" % HOVER_PATH)
	if hover == null:
		return
	_check_style_resource(hover)
	_check_resume(hover)
	_check_battle_report(hover)
	_check_setting_page(hover)
	_check_handbook(hover)


# ---------------------------------------------------------------------------
# 样式本身
# ---------------------------------------------------------------------------


func _check_style_resource(hover: StyleBoxFlat) -> void:
	print("[styles] %s" % HOVER_PATH)
	_check(hover.draw_center and hover.bg_color.is_equal_approx(EXPECTED_BG),
			"画的是那款灰：bg=%s（基准 %s）" % [hover.bg_color, EXPECTED_BG])
	_check(hover.corner_radius_top_left == EXPECTED_CORNER
			and hover.corner_radius_top_right == EXPECTED_CORNER
			and hover.corner_radius_bottom_left == EXPECTED_CORNER
			and hover.corner_radius_bottom_right == EXPECTED_CORNER,
			"四个圆角都是 %d" % EXPECTED_CORNER)
	var border := hover.border_width_left + hover.border_width_top \
			+ hover.border_width_right + hover.border_width_bottom
	_check(border == 0, "不描边（四边线宽合计 %d）" % border)
	# 词条的 normal 是「下划线 + 10/7 内边距」，hover 的内边距必须与它一致，
	# 否则悬停那一下最小高度会跳、整栏跟着抖。
	var normal := load("res://ui/styles/resume_token_normal.tres") as StyleBoxFlat
	_check(normal != null and hover.content_margin_left == normal.content_margin_left
			and hover.content_margin_top == normal.content_margin_top,
			"内边距与词条 normal 一致（%s / %s），悬停时整栏不会抖"
			% [hover.content_margin_left, normal.content_margin_left if normal else "?"])


# ---------------------------------------------------------------------------
# 三个界面：引的是不是同一份
# ---------------------------------------------------------------------------


func _check_resume(hover: StyleBox) -> void:
	print("[10.6] 简历页")
	var resume := RESUME.instantiate()
	_check_anchor(resume.get_node_or_null("Status"), hover, "力量 / 智力 / 感知（属性值栏）")
	_check_anchor(resume.get_node_or_null("ExperienceScroll/ExperienceContainer/ResumeToken"), hover,
			"个人履历与奖项（词条）")
	_check_anchor(resume.get_node_or_null("SkillScroll/SkillContainer/ResumeToken"), hover, "专长（词条）")
	_check_anchor(resume.get_node_or_null("TokenMenu/Options/OptionList/AskButton"), hover,
			"词条菜单里的「追问」")
	resume.free()


func _check_battle_report(hover: StyleBox) -> void:
	print("[4] 战报页")
	var battle := BATTLE.instantiate()
	_check_anchor(battle.get_node_or_null("BattleReportPhd/Confirm"), hover, "确认")
	battle.free()


func _check_setting_page(hover: StyleBox) -> void:
	print("[14] 设置页")
	var setting := SETTING.instantiate()
	_check_anchor(setting.get_node_or_null("Page/ContinueButton"), hover, "继续游戏")
	_check_anchor(setting.get_node_or_null("Page/ExitButton"), hover, "退出游戏")
	setting.free()


## 手册右上角那颗退出键。
##
## ⚠️ 它原来是个 `TextureButton` —— 而 `TextureButton` **根本没有 hover 样式**
## （默认主题里 `has_stylebox("hover", "TextureButton")` 是 false，它只有一整套贴图），
## 所以想要和别处一样的高亮，只能把它换成 `Button`：高亮由 `Button` 画，叉的贴图
## 交给它底下的 `QuitIcon`（TextureRect）画 —— 父节点先画、子节点后画，叉正好压在高亮上面。
## 顺带把原来那个 `scale = 0.48` 去掉了：缩放过的 Control 尺寸与命中区容易对不上，
## 现在控件矩形（62×62）就是叉的可视范围，和改之前实测的 61.44 一样大。
func _check_handbook(hover: StyleBox) -> void:
	print("[6.3] 手册")
	var handbook := HANDBOOK.instantiate()
	var quit := handbook.get_node_or_null("quit")
	_check_anchor(quit, hover, "右上角的退出键")
	_check(quit is Button, "退出键是 Button（TextureButton 画不了悬停高亮）")
	# 叉的贴图挂在子节点上，而且不能吃鼠标：吃了就点不动退出键了
	var icon := handbook.get_node_or_null("quit/QuitIcon") as Control
	_check(icon != null and (icon as TextureRect).texture != null, "退出键底下有画叉的 QuitIcon")
	_check(icon != null and icon.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"QuitIcon 不吃鼠标（否则它会把退出键的点击吞掉）")
	handbook.free()


## 一个「栏」：悬停画共用高亮，且**只有悬停才画** —— normal 不能自带底色，
## 否则进界面就一片灰，高亮就不叫高亮了。
func _check_anchor(node: Node, hover: StyleBox, label: String) -> void:
	if node == null:
		_check(false, "%s：节点在场景里（改名了就得同步改本测试）" % label)
		return
	if not (node is Control):
		_check(false, "%s：是 Control（样式覆盖只对 Control 生效）" % label)
		return
	var control := node as Control
	var got := control.get_theme_stylebox("hover")
	_check(got == hover, "%s：悬停高亮 = %s" % [label, HOVER_PATH])
	_check(_unfilled(control.get_theme_stylebox("normal")),
			"%s：normal 不画底色（高亮只在悬停时出现）" % label)


## 「这个 StyleBox 什么都不画」
func _unfilled(sb: StyleBox) -> bool:
	if sb == null or sb is StyleBoxEmpty:
		return true
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		return not flat.draw_center or flat.bg_color.a <= 0.0
	return false


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_hover_gray] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_hover_gray] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
