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

	# 简历内容全部来自数据：开一局 → 取第 1 天名单里第一位 → 喂给简历。
	# 这里**不**造一份测试用简历，测的就是「data/candidates/*.tres → 纸面」这条路。
	GameState.start_new_run(20261010)
	var candidate: CandidateResource = null
	if not GameState.current_candidates.is_empty():
		candidate = GameState.current_candidates[0]
	_check(candidate != null, "第 1 天名单里有候选人")
	if candidate == null:
		_report()
		return
	_check(candidate.resume.size() >= 3, "第 1 天第一位至少带 3 条简历（实际 %d）" % candidate.resume.size())

	var resume := RESUME_SCENE.instantiate() as Resume
	vp.add_child(resume)
	await _settle()

	# 实例化时纸上是空的（场景里不写死任何候选人文案），数据靠这里灌进去
	resume.set_candidate(candidate)
	await _settle()

	_canvas = resume.get_viewport_rect().size
	print("[smoke_resume_menu] 画布 = %s，候选人 = %s（%d 条简历）" % [
		_canvas, candidate.display_name, candidate.resume.size()])
	_check(_canvas == Vector2(GAME_CANVAS), "画布是自己设定的 1152x648")

	var menu: ResumeTokenMenu = resume.get_node("TokenMenu")
	var panel: TextureRect = menu.get_node("Panel")
	var ask: Button = menu.get_node("Options/OptionList/AskButton")
	var list: VBoxContainer = resume.get_node("Paper/Rows/TokenList")
	var info: Label = resume.get_node("Paper/Rows/HeaderInfo")
	var third: Control = list.get_child(2)
	var last: Control = list.get_child(candidate.resume.size() - 1)

	# ---- 结构与素材 ----
	_check(menu != null, "TokenMenu 存在且是 ResumeTokenMenu")
	_check(not menu.visible, "菜单默认隐藏")
	_check(panel.texture != null, "面板纹理已加载")
	_check(panel.texture.get_size() == ResumeTokenMenu.PANEL_SIZE,
			"纹理实际尺寸 %s == PANEL_SIZE %s" % [panel.texture.get_size(), ResumeTokenMenu.PANEL_SIZE])
	_check(ask.text == "追问", "按钮文案是「追问」")

	# ---- 纸面内容来自数据（不是代码里的占位常量）----
	var shown := 0
	for child in list.get_children():
		if (child as Control).visible:
			shown += 1
	_check(shown == candidate.resume.size(),
			"铺出来的词条数 = 候选人简历条数（%d）" % candidate.resume.size())
	_check(not candidate.resume_header.strip_edges().is_empty(), "候选人在数据里填了抬头")
	_check(info.text == candidate.resume_header,
			"抬头把数据里那一段字原样铺上去（不做拼接）")
	_check((third as Button).text.contains(candidate.resume[2].description),
			"第三条词条正文 = 数据里的 description")

	# 顺带如实报一下默认字体能不能画中文 —— assets/fonts 还没接入主字体（§10.5），
	# 画不出来按钮就是两个方块。这条只提示，不算失败。
	var missing := ""
	for ch in ask.text:
		if not ThemeDB.fallback_font.has_char(ch.unicode_at(0)):
			missing += ch
	if missing.is_empty():
		print("  [note] 默认字体有「%s」的字形，按钮能正常显示" % ask.text)
	else:
		print("  [note] ⚠ 默认字体缺字形「%s」—— 按钮会显示成两个方块，等 assets/fonts 接入中文字体" % missing)

	# ---- 点词条 → 开菜单 ----
	_check(third.selected.get_connections().size() > 0, "词条的 selected 已接到 resume.gd")
	third.emit_signal("pressed")
	await _settle()

	_check(menu.visible, "点词条后菜单打开")
	_check(menu.entry_index == 2, "菜单记住词条序号 = 2")
	var r := menu.get_global_rect()
	var a := third.get_global_rect()
	_check(is_equal_approx(r.position.x, a.end.x + ResumeTokenMenu.GAP), "默认贴在词条右边")
	_check(is_equal_approx(r.position.y, a.position.y), "与词条顶对齐")
	_check(_inside(r, _canvas), "菜单整块落在画布内 %s" % r)

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
	_check(info.text.is_empty(), "喂 null → 抬头清空")
	var still_shown := 0
	for child in list.get_children():
		if (child as Control).visible:
			still_shown += 1
	_check(still_shown == 0, "喂 null → 词条全部收起")
	_check(not menu.is_open(), "喂 null → 菜单不会留在半空")

	# ---- 抬头就是一段字：长得再不像「字段拼出来的」也照样原样铺 ----
	var odd := CandidateResource.new()
	odd.resume_header = "—— 江湖人称「一晚上砍死三头魔物」的那个男人 ——"
	resume.set_candidate(odd)
	await _settle()
	_check(info.text == odd.resume_header, "抬头原样铺，不做任何拼接 / 加工")
	_check(resume.get_candidate() == odd, "get_candidate 能把当前这位取回来")


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
