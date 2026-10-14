extends Node

## true_attributes 自检 —— 「简历上写的属性值」与「实际属性值」是两回事（ARCHITECTURE.md §3.1）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_true_attributes.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是四件事：
##   1. **老格式兼容**：.tres 里没写 true_attributes 的候选人，实际值必须等于简历值
##      —— 现有 25 份候选人数据一行都不用改；
##   2. **只写一项也算数**：只吹了力量的人，另两项照简历走；
##   3. **两头各自读对**：纸面上读简历值（resume.gd），结算读实际值（combat_resolver.gd）；
##   4. **工具与引擎的格式契约**：candidate_generator.html 写出来的那一行，Godot 真读得懂。
##
## 为什么套一层 SubViewport：同 smoke_resume_menu —— headless 下窗口不是游戏画布，
## 简历那几个 Label 的排版得在真实尺寸下才有意义（这里只读 text，但也一并对齐做法）。

const RESUME_SCENE := preload("res://scenes/day/interview/resume/resume.tscn")

## 游戏的实际画布（project.godot 的 canvas_items 拉伸基准）
const GAME_CANVAS := Vector2i(1152, 648)

## `tools/candidate_generator.html` 里 `true_attributes` 那一行的样子（原样抄一份）。
## 它就是「工具 ↔ 引擎」的格式契约：生成器改写法（换个引号、换成 StringName 键…）
## 而引擎读不动时，这一条会红 —— 而不是等到某位候选人上线才发现他吹的牛没生效。
const GENERATED_LINE := '{ "strength": 4, "wisdom": 12 }'

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	# 等 root 把子节点装配完再往里加 —— _ready() 里直接 add_child 会被拒绝
	await get_tree().process_frame
	await _run()
	_report()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK  " if ok else "FAIL", what])


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	_check_legacy_data()
	await _check_resume_shows_claimed()
	_check_combat_uses_true()
	_check_generator_format()


# ---------------------------------------------------------------------------
# 1 / 2 老格式兼容 + 只写一项
# ---------------------------------------------------------------------------


## 现有 `data/candidates/*.tres` 全是老格式（没有 true_attributes），
## 拿它们逐位过一遍「实际值 == 简历值」——**这就是「兼容现有格式」的验收**。
##
## ⚠️ 判据是「那一行没写」（= true_attributes 是空字典），不是「不许有人吹牛」：
##    以后真给某位候选人填上 true_attributes，他就不再被这条盯着，测试不会误红。
func _check_legacy_data() -> void:
	print("[3.1] 老数据：没写 true_attributes 的人，实际属性 == 简历属性")
	var total := DataDB.count(&"candidates")
	_check(total > 0, "data/candidates 下有候选人（实际 %d）" % total)

	var old_format_ok := true
	var clean := 0
	var faked := 0
	for id in DataDB.get_ids(&"candidates"):
		var candidate := DataDB.get_candidate(id)
		if candidate == null:
			continue
		if not candidate.true_attributes.is_empty():
			faked += 1
			continue
		clean += 1
		for key in CandidateResource.ATTRIBUTE_KEYS:
			if candidate.true_attribute(key) != candidate.claimed_attribute(key):
				old_format_ok = false
	print("  候选人 %d 位：没写 true_attributes 的 %d 位、写了 %d 位" % [clean + faked, clean, faked])
	_check(old_format_ok, "没写 true_attributes 的人：三项实际属性都等于简历上写的那个数")

	# 只写一项 —— 这是本功能最常见的用法（只在一项上吹牛）
	var liar := CandidateResource.new()
	liar.strength = 20
	liar.intelligence = 8
	liar.wisdom = 15
	liar.true_attributes = { "strength": 4 }
	_check(liar.true_strength() == 4, "只写了 strength → 实际力量 4（简历上写的还是 20）")
	_check(liar.true_intelligence() == 8, "没写的 intelligence → 照简历走（8）")
	_check(liar.true_wisdom() == 15, "没写的 wisdom → 照简历走（15）")
	_check(liar.claimed_attribute(&"strength") == 20, "claimed_attribute 读到的是纸面上那个数（20）")
	_check(CandidateResource.ATTRIBUTE_KEYS.size() == 3, "属性键一共三个（strength / intelligence / wisdom）")
	for key in CandidateResource.ATTRIBUTE_KEYS:
		_check(liar.claimed_attribute(key) == liar.true_attribute(key) or key == &"strength",
				"除被改写的那一项外，%s 的实际值与简历值一致" % key)

	# 三项都写
	var all_fake := CandidateResource.new()
	all_fake.strength = 20
	all_fake.intelligence = 8
	all_fake.wisdom = 15
	all_fake.true_attributes = { "strength": 1, "intelligence": 2, "wisdom": 3 }
	_check(all_fake.true_strength() == 1 and all_fake.true_intelligence() == 2
			and all_fake.true_wisdom() == 3, "三项全写 → 三项都按实际值算")

	# 键的类型不该由人操心：.tres 里手写成 &"strength" 一样得认
	var name_keyed := CandidateResource.new()
	name_keyed.strength = 20
	name_keyed.true_attributes = { &"strength": 4 }
	_check(name_keyed.true_strength() == 4, "键写成 StringName（&\"strength\"）也认")

	# 填了个不是数的东西：宁可当他没吹牛，也别拿一个莫名其妙的数去结算（此处故意触发一条 push_warning）
	var broken := CandidateResource.new()
	broken.strength = 20
	broken.true_attributes = { "strength": "四" }
	_check(broken.true_strength() == 20, "值不是数字 → 退回简历值（20），不拿它去结算")


# ---------------------------------------------------------------------------
# 3 纸面读简历值 / 结算读实际值
# ---------------------------------------------------------------------------


## 简历纸上摆的是**他自己填的那个数**（§3.1：玩家看不到真实值）。
## 这一位在力量上吹了牛 —— 纸上必须还是那个吹出来的 20，不能是实际值 4。
func _check_resume_shows_claimed() -> void:
	print("[10.6] 简历纸上：显示的是简历值，不是实际值")
	var vp := SubViewport.new()
	vp.size = GAME_CANVAS
	vp.disable_3d = true
	get_tree().root.add_child(vp)

	var resume := RESUME_SCENE.instantiate() as Resume
	vp.add_child(resume)
	await _settle()
	_check(resume.get_viewport_rect().size == Vector2(GAME_CANVAS), "画布是自己设定的 1152x648")

	var liar := CandidateResource.new()
	liar.display_name = "吹牛的棍木"
	liar.strength = 20          # 简历上写的（吹出来的）
	liar.intelligence = 8
	liar.wisdom = 15
	liar.true_attributes = { "strength": 4 }   # 实际只有 4

	resume.set_candidate(liar)
	await _settle()

	var str_label: Label = resume.get_node("Status/StrContainer")
	var int_label: Label = resume.get_node("Status/IntContainer")
	var wis_label: Label = resume.get_node("Status/WisContainer")
	_check(str_label.text == str(liar.strength), "力量栏 = 简历值 20")
	_check(str_label.text != str(liar.true_strength()), "力量栏**不显示**实际值（4）")
	_check(int_label.text == str(liar.intelligence), "智力栏 = 简历值 8")
	_check(wis_label.text == str(liar.wisdom), "感知栏 = 简历值 15")

	# 诚实的人：两个数相等，纸面照旧
	var honest := CandidateResource.new()
	honest.strength = 7
	honest.intelligence = 9
	honest.wisdom = 11
	resume.set_candidate(honest)
	await _settle()
	_check(str_label.text == "7" and int_label.text == "9" and wis_label.text == "11",
			"没写 true_attributes 的人，纸面就是他那三个数")

	vp.queue_free()


## 结算读的是**实际属性** —— 吹了牛的人在战报里只按真身板算分（§6.5）。
func _check_combat_uses_true() -> void:
	print("[6.5] 战斗结算：读的是实际属性")
	var job := DataDB.get_job(&"job.fighter")
	_check(job != null and job.id == &"job.fighter", "取到 job.fighter（data/jobs/fighter.tres）")

	var liar := CandidateResource.new()
	liar.job = job
	liar.strength = 20
	liar.true_attributes = { "strength": 4 }
	_check(CombatResolver.powerCaculation(liar) == 40,
			"战士按实际力量算分：4 × 10 = 40（不是简历的 20 × 10 = 200）")

	var honest := CandidateResource.new()
	honest.job = job
	honest.strength = 20
	_check(CombatResolver.powerCaculation(honest) == 200, "没写 true_attributes → 照简历算（200）")


# ---------------------------------------------------------------------------
# 4 工具那一行字的格式
# ---------------------------------------------------------------------------


## candidate_generator.html 生成的是**纯文本 .tres**，参数值就是一行字面量。
## 这里把它原样交给 Godot 的变体解析器，确认「工具写出去的东西引擎读得回来」。
func _check_generator_format() -> void:
	print("[tools] 生成器写出的 true_attributes 那一行，Godot 读得懂")
	var parsed: Variant = str_to_var(GENERATED_LINE)
	_check(parsed is Dictionary, "字典字面量能解析成 Dictionary（%s）" % GENERATED_LINE)
	if not (parsed is Dictionary):
		return
	var candidate := CandidateResource.new()
	candidate.strength = 20
	candidate.intelligence = 8
	candidate.wisdom = 5
	candidate.true_attributes = parsed
	_check(candidate.true_strength() == 4, "解析出来的 strength 生效（4）")
	_check(candidate.true_wisdom() == 12, "解析出来的 wisdom 生效（12）")
	_check(candidate.true_intelligence() == 8, "字典里没写的 intelligence 照简历走（8）")
	_check(candidate.true_attributes.size() == 2,
			"生成器**只写真改过的那几项**，不把三项都铺进去（实际 %d 项）" % candidate.true_attributes.size())


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_true_attributes] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_true_attributes] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
