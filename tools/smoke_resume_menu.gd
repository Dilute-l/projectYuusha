extends Node

## resume / resume_token_menu 自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_resume_menu.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 为什么套一层 SubViewport：headless 下窗口是 1152x1152，--resolution 不生效，
## 直接挂在 root 上就测不到真实画布。放进一个尺寸可控的 SubViewport 里，
## 既能复现游戏真正的 1152x648，也能随手改尺寸来验「画布大小变化时的适配」，
## 而且结果与显示器/窗口无关，跑多少次都一样。

const RESUME_SCENE := preload("res://scenes/day/interview/resume/resume.tscn")

## 游戏的实际画布（project.godot 的 canvas_items 拉伸基准）
const GAME_CANVAS := Vector2i(1152, 648)

## 先按真实画布跑，再放大画布验重排
const TALL_CANVAS := Vector2i(1152, 900)
const WIDE_CANVAS := Vector2i(1600, 900)

## resume.tscn 里预摆的那枚印章用的贴图。期望值从**文件名**来，不抄场景里的 uid ——
## 换图时这里跟着改一行就够了，改不动就说明换的不是这一张。
const STAMP_TEXTURE_PATH := "res://assets/art/interview/resume/resume_stamp_phd.png"

var _failures: Array[String] = []
var _checks: int = 0
var _canvas := Vector2.ZERO


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


func _inside(r: Rect2, c: Vector2) -> bool:
	return r.position.x >= -0.01 and r.position.y >= -0.01 \
			and r.end.x <= c.x + 0.01 and r.end.y <= c.y + 0.01


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = GAME_CANVAS
	vp.disable_3d = true
	get_tree().root.add_child(vp)

	# 简历内容全部来自数据：开一局 → 从第 1 天名单里挑**条目最多**的那一位 → 喂给简历。
	# 这里**不**造一份测试用简历，测的就是「data/candidates/*.tres → 纸面」这条路。
	#
	# ⚠️ 为什么不是「名单第一位」：本测试后面要用到**第 3 条**词条（下标 2），
	# 名单里谁条目多完全由数据决定 —— 写死「第一位」会在数据一改就红，
	# 而那根本不是这个测试该管的事（数据覆盖度是 smoke_m0 的活，§11.4）。
	GameState.start_new_run(20261010)
	var candidate: CandidateResource = null
	for c in GameState.current_candidates:
		if candidate == null or Resume.entries_of(c).size() > Resume.entries_of(candidate).size():
			candidate = c
	_check(candidate != null, "第 1 天名单里有候选人")
	if candidate == null:
		_report()
		return
	var entries := Resume.entries_of(candidate)
	_check(entries.size() >= 3, "挑出的这位至少带 3 条履历/专长（实际 %d，%s）" % [entries.size(), candidate.id])

	var resume := RESUME_SCENE.instantiate() as Resume
	vp.add_child(resume)
	await _settle()

	var stamp: Sprite2D = resume.get_node("ResumeStamp")
	var stamp_rest := stamp.position

	# ---- 空纸不盖章（场景里预摆的那张图不该自己冒出来）----
	_check(stamp != null, "ResumeStamp 就位")
	_check(not stamp.visible, "还没喂候选人 → 不盖章")
	_check(stamp.texture == null, "还没喂候选人 → 节点上也没有残留的图")

	# 实例化时纸上是空的（场景里不写死任何候选人文案），数据靠这里灌进去
	resume.set_candidate(candidate)
	await _settle()

	_canvas = resume.get_viewport_rect().size
	print("[smoke_resume_menu] 画布 = %s，候选人 = %s（%d 条履历/专长）" % [
		_canvas, candidate.display_name, entries.size()])
	_check(_canvas == Vector2(GAME_CANVAS), "画布是自己设定的 1152x648")

	var menu: ResumeTokenMenu = resume.get_node("TokenMenu")
	var panel: TextureRect = menu.get_node("Panel")
	var ask: Button = menu.get_node("Options/OptionList/AskButton")
	var third: Control = resume.token_at(2)
	var last: Control = resume.token_at(entries.size() - 1)

	# ---- 结构与素材 ----
	_check(menu != null, "TokenMenu 存在且是 ResumeTokenMenu")
	_check(not menu.visible, "菜单默认隐藏")
	_check(panel.texture != null, "面板纹理已加载")
	_check(panel.texture.get_size() == ResumeTokenMenu.PANEL_SIZE,
			"纹理实际尺寸 %s == PANEL_SIZE %s" % [panel.texture.get_size(), ResumeTokenMenu.PANEL_SIZE])
	_check(ask.text == "追问", "按钮文案是「追问」")

	# ---- 纸面内容来自数据（不是代码里的占位常量）----
	_check(resume.token_count() == entries.size(),
			"铺出来的词条数 = 履历 + 专长条数（%d）" % entries.size())
	_check(not candidate.team_declaration.strip_edges().is_empty(), "候选人在数据里填了组队宣言")
	var declaration: Label = resume.get_node("DeclarationContainer")
	_check(declaration.text == candidate.team_declaration,
			"组队宣言把数据里那一段字原样铺上去（不做拼接）")
	var name_value: Label = resume.get_node("NameContainer")
	_check(name_value.text == candidate.display_name, "姓名栏 = 数据里的 display_name")
	_check((third as Button).text.contains(entries[2].description),
			"第三条词条正文 = 数据里的 description")

	# ---- 印章：显不显示、用哪张图，全部来自候选人数据（CandidateResource.resume_stamp）----
	# 数据样本是 data/candidates/c_0001.tres（故意填了章的那一位）。这里**显式按 id 取**，
	# 不跟着上面那位走 —— 上面那位是「条目最多」挑出来的，跟有没有章没有关系。
	var stamped: CandidateResource = DataDB.get_candidate(&"c_0001")
	_check(stamped != null and stamped.resume_stamp != null,
			"data/candidates/c_0001.tres 在数据里填了 resume_stamp")
	_check(stamped != null and stamped.resume_stamp != null
			and stamped.resume_stamp.resource_path == STAMP_TEXTURE_PATH,
			"填的就是 %s" % STAMP_TEXTURE_PATH)

	# 纸上的章严格跟着**当前这位**走：有图就盖，没图就不盖
	_check(stamp.visible == (candidate.resume_stamp != null),
			"盖章与否 = 当前这位有没有 resume_stamp（%s：%s）"
			% [candidate.id, "有" if candidate.resume_stamp != null else "没有"])
	_check(stamp.texture == candidate.resume_stamp, "盖的就是他数据里那张")
	_check(stamp.position == stamp_rest, "章的位置是场景摆的那一处，代码没动它（%s）" % stamp.position)

	# 顺带如实报一下按钮能不能画中文（§10.5）。
	# 查的是**按钮真正生效的那一款字体**（get_theme_font 会把 theme_override_fonts/font 解出来），
	# 不是引擎的 fallback —— 简历这边已经和别处一样接上了 assets/fonts/Silver.ttf，
	# 再拿 fallback 去问「缺不缺中文」就成了与按钮无关的假警报。
	var ask_font := ask.get_theme_font("font")
	var missing := ""
	for ch in ask.text:
		if not ask_font.has_char(ch.unicode_at(0)):
			missing += ch
	if missing.is_empty():
		print("  [note] 按钮字体有「%s」的字形，按钮能正常显示" % ask.text)
	else:
		print("  [note] ⚠ 按钮字体缺字形「%s」—— 按钮会显示成方块" % missing)

	# ---- 点词条 → 开菜单 ----
	# 序号 2 现在是「专长」那条：它在两个词条列表的后半，菜单被要求摆**左边**
	# （右边紧挨着纸面别的内容）。履历那栏仍然摆右边，下面单独验。
	_check(third.selected.get_connections().size() > 0, "词条的 selected 已接到 resume.gd")
	third.emit_signal("pressed")
	await _settle()

	_check(menu.visible, "点词条后菜单打开")
	_check(menu.entry_index == 2, "菜单记住词条序号 = 2")
	var r := menu.get_global_rect()
	var a := third.get_global_rect()
	_check(is_equal_approx(r.end.x, a.position.x - ResumeTokenMenu.GAP),
			"专长那条 → 菜单摆左边")
	# 与词条顶对齐 —— 但贴不下时会被画布底部夹住（_reposition 对 y 只夹取、不翻转）。
	var expected_top: float = minf(a.position.y, _canvas.y - ResumeTokenMenu.PANEL_SIZE.y)
	_check(is_equal_approx(r.position.y, expected_top), "与词条顶对齐（贴不下时夹进画布）")
	_check(_inside(r, _canvas), "菜单整块落在画布内 %s" % r)

	# ---- 履历那条（序号 0）仍然按默认摆右边 ----
	var first_token: Control = resume.token_at(0)
	menu.close()
	first_token.emit_signal("pressed")
	await _settle()
	var r0 := menu.get_global_rect()
	var a0 := first_token.get_global_rect()
	_check(is_equal_approx(r0.position.x, a0.end.x + ResumeTokenMenu.GAP),
			"履历那条 → 菜单默认摆右边")
	_check(menu.entry_index == 0, "菜单记住词条序号 = 0")
	menu.close()

	# ---- 状态区（力量 / 智力 / 感知）也是可追问的，序号 -1，菜单摆左边 ----
	var status_btn: Button = resume.get_node("Status")
	status_btn.pressed.emit()
	await _settle()
	_check(menu.is_open(), "点状态区 → 菜单也打开")
	_check(menu.entry_index == Resume.STATUS_ENTRY_INDEX,
			"状态区的序号是 -1（实际 %d）" % menu.entry_index)
	var rs := menu.get_global_rect()
	var as_rect := status_btn.get_global_rect()
	_check(is_equal_approx(rs.end.x, as_rect.position.x - ResumeTokenMenu.GAP),
			"状态区 → 菜单摆左边")
	menu.close()

	# ---- 底部夹取 ----
	# 词条条数现在由数据决定，位置不再是个固定值，所以先把画布压到
	# 「最后一条词条刚好放不下整块菜单」的高度，再验夹取。
	# （Paper 用的是绝对偏移，画布变矮时词条本身不会跟着挪。）
	menu.close()
	var last_top: float = last.get_global_rect().position.y
	var tight := Vector2i(GAME_CANVAS.x, int(last_top + ResumeTokenMenu.PANEL_SIZE.y - 1.0))
	_check(tight.y > 1, "能构造出「放不下」的画布（高 %d）" % tight.y)
	vp.size = tight
	await _settle()
	_canvas = resume.get_viewport_rect().size
	last_top = last.get_global_rect().position.y
	last.emit_signal("pressed")
	await _settle()
	r = menu.get_global_rect()
	_check(last_top + ResumeTokenMenu.PANEL_SIZE.y > _canvas.y, "前提成立：最后一条词条放不下整块菜单")
	_check(is_equal_approx(r.position.y, _canvas.y - ResumeTokenMenu.PANEL_SIZE.y),
			"底部放不下 → 夹到画布底边（y=%s，期望 %s）" % [r.position.y, _canvas.y - ResumeTokenMenu.PANEL_SIZE.y])
	_check(_inside(r, _canvas), "夹取后仍在画布内 %s" % r)

	# ---- 画布变大：夹取应自动松开（走的是 size_changed，不是手动重排）----
	vp.size = TALL_CANVAS
	await _settle()
	_canvas = resume.get_viewport_rect().size
	r = menu.get_global_rect()
	_check(_canvas == Vector2(TALL_CANVAS), "画布已变成 1152x900（%s）" % _canvas)
	_check(is_equal_approx(r.position.y, last_top),
			"画布变高后菜单自动回到词条顶对齐（y=%s，期望 %s）" % [r.position.y, last_top])
	_check(_inside(r, _canvas), "变大后仍完整在画布内 %s" % r)

	# ---- 画布变宽：位置跟着重算，仍然贴边不越界 ----
	vp.size = WIDE_CANVAS
	await _settle()
	_canvas = resume.get_viewport_rect().size
	r = menu.get_global_rect()
	_check(_inside(r, _canvas), "变宽后仍完整在画布内 %s" % r)

	# ---- 右侧翻边：右边塞不下时翻到词条左边 ----
	var far := Control.new()
	far.size = Vector2(60, 30)
	vp.add_child(far)
	far.global_position = Vector2(_canvas.x - 50.0, 100.0)
	menu.open_for(far, 0)
	await _settle()
	r = menu.get_global_rect()
	_check(is_equal_approx(r.end.x, far.get_global_rect().position.x - ResumeTokenMenu.GAP),
			"右边放不下 → 翻到词条左边")
	_check(_inside(r, _canvas), "翻边后仍在画布内 %s" % r)

	# ---- 收起：点外面 / Esc ----
	third.emit_signal("pressed")
	await _settle()
	_check(menu.visible, "重新打开")
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	outside.position = Vector2(5.0, 5.0)
	resume._input(outside)
	_check(not menu.visible, "点菜单外面 → 收起")

	third.emit_signal("pressed")
	await _settle()
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	resume._input(esc)
	_check(not menu.visible, "Esc → 收起")

	# ---- 「追问」按钮：广播 resume_entry_asked，并收起菜单 ----
	# 台词不归简历这一层管 —— 档案上只有一个 json 路径，正文由 interview.gd 播。
	# 所以这里只验「广播对了吗」；端到端那一半见 tools/smoke_interview_ask.gd。
	third.emit_signal("pressed")
	await _settle()
	_check(menu.ask_requested.get_connections().size() > 0,
			"ask_requested 已接到 resume.gd")
	var seen: Array = []
	var spy := func(cid: StringName, i: int) -> void: seen.append([cid, i])
	EventBus.resume_entry_asked.connect(spy)
	ask.emit_signal("pressed")
	await _settle()
	EventBus.resume_entry_asked.disconnect(spy)
	_check(seen == [[candidate.id, 2]],
			"「追问」广播了 resume_entry_asked(%s, 2)（实际 %s）" % [candidate.id, seen])
	_check(not menu.visible, "「追问」后菜单收起")
	_check(third.visible, "词条没有被动过")

	# ---- 简历整块被显隐时（interview.gd 按阶段控制 Resume.visible）菜单不能诈尸 ----
	third.emit_signal("pressed")
	await _settle()
	_check(menu.is_open(), "再开一次做显隐测试")
	resume.visible = false
	await _settle()
	_check(not menu.is_open(), "Resume 被隐藏 → 菜单自己收起")
	resume.visible = true
	await _settle()
	_check(not menu.is_open(), "Resume 重新显示 → 菜单不会诈尸")

	# ---- 换一位候选人：纸面内容整块跟着换 ----
	resume.set_candidate(null)
	await _settle()
	_check(name_value.text.is_empty(), "喂 null → 姓名栏清空")
	_check(declaration.text.is_empty(), "喂 null → 组队宣言清空")
	_check(resume.token_count() == 0, "喂 null → 词条全部收起")
	_check(not menu.is_open(), "喂 null → 菜单不会留在半空")
	_check(not stamp.visible, "喂 null → 章也收起来")
	_check(stamp.texture == null, "喂 null → 章那张图从节点上摘掉（不留上一位的图）")

	# ---- 组队宣言就是一段字：长得再不像「字段拼出来的」也照样原样铺 ----
	var odd := CandidateResource.new()
	odd.team_declaration = "—— 江湖人称「一晚上砍死三头魔物」的那个男人 ——"
	resume.set_candidate(odd)
	await _settle()
	_check(declaration.text == odd.team_declaration, "组队宣言原样铺，不做任何拼接 / 加工")
	_check(resume.get_candidate() == odd, "get_candidate 能把当前这位取回来")
	_check(not stamp.visible, "这位没填 resume_stamp → 不盖章")
	_check(stamp.texture == null, "没填就是空，不退回默认那张图")

	# ---- 换回一位带章的：章要跟着回来，而且换的是**他那张** ----
	var with_stamp := CandidateResource.new()
	with_stamp.resume_stamp = load(STAMP_TEXTURE_PATH)
	resume.set_candidate(with_stamp)
	await _settle()
	_check(stamp.visible, "换到填了章的候选人 → 章又盖上")
	_check(stamp.texture == with_stamp.resume_stamp, "盖的是他自己那张")

	# ---- 从带章的换到不带章的：不能留上一位的章 ----
	resume.set_candidate(odd)
	await _settle()
	_check(not stamp.visible, "换回没章的 → 章消失")
	_check(stamp.texture == null, "换回没章的 → 图也摘干净（不会张冠李戴）")


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_resume_menu] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_resume_menu] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
