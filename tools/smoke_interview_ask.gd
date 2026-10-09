extends Node

## interview / 追问 自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_interview_ask.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 验的是「点简历某一条的『追问』→ 顶上对话框播出那条自己的 json」这条路：
##
##   点词条 → TokenMenu 的「追问」→ resume.gd 广播 EventBus.resume_entry_asked
##          → interview.gd 取 entry.ask_path → typer.load_dialogue_from(path)
##          → dialoguer.play()
##
## **一句台词都不在脚本里**：期望值全部从 data/asks/*.json 里现读现比 ——
## 改文案、改说话人都不用动这个文件；但改 json 的结构（行数 / 字段名）会在这里报出来。
##
## 为什么要真的实例化 interview.tscn：追问的落点在 interview.gd 身上，
## 单独拿 resume.tscn 测只能测到「信号发出去了」，测不到「对话框真的播了那份 json」。

const INTERVIEW_SCENE := preload("res://scenes/day/interview/interview.tscn")

## 游戏的实际画布（project.godot 的 canvas_items 拉伸基准）
const GAME_CANVAS := Vector2i(1152, 648)

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
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


## 读一份追问 json，返回它的行数组（读不出来返回空数组）
func _read_ask(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Array else []


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = GAME_CANVAS
	vp.disable_3d = true
	get_tree().root.add_child(vp)

	# 数据全部来自 data/：开一局 → 当日名单 → 面试场景照着它铺
	GameState.start_new_run(20261010)
	GameState.set_phase(DayPhase.Phase.INTERVIEW)

	var candidate: CandidateResource = null
	if not GameState.current_candidates.is_empty():
		candidate = GameState.current_candidates[0]
	_check(candidate != null, "第 1 天名单里有候选人")
	if candidate == null:
		return
	_check(candidate.resume.size() >= 2, "这位候选人至少带 2 条简历（实际 %d）" % candidate.resume.size())
	if candidate.resume.size() < 2:
		return

	# 档案里只该剩一个路径：追问的正文一个字都不许再存在档案上
	var entry0 := candidate.resume[0]
	var entry1 := candidate.resume[1]
	_check(not entry0.ask_path.strip_edges().is_empty(), "第 1 条简历指向一份追问 json")
	_check(entry0.ask_path != entry1.ask_path, "两条简历指向**不同**的追问 json（一条一个文件）")
	_check(not entry0.ask_path.begins_with("res://data/dialogue.json"),
			"追问 json 不是共用的 dialogue.json：%s" % entry0.ask_path)

	var expect0 := _read_ask(entry0.ask_path)
	var expect1 := _read_ask(entry1.ask_path)
	_check(expect0.size() >= 2, "第 1 条的追问 json 至少有 2 行（实际 %d）" % expect0.size())
	if expect0.size() < 2:
		return

	var interview := INTERVIEW_SCENE.instantiate()
	vp.add_child(interview)
	await _settle()

	var resume: Resume = interview.get_node_or_null("Resume")
	var dialoguer: Dialoguer = interview.get_node_or_null("Dialoguer")
	var menu: ResumeTokenMenu = resume.get_node_or_null("TokenMenu") if resume != null else null
	_check(resume != null, "面试场景里有 Resume")
	_check(dialoguer != null, "面试场景里有 Dialoguer")
	_check(menu != null, "Resume 里有 TokenMenu")
	if resume == null or dialoguer == null or menu == null:
		return

	# ---- 场景挂载：面试者与简历都按当日名单铺好了 ----
	_check(interview.get_phase() == DayPhase.Phase.INTERVIEW, "面试场景停在 INTERVIEW 阶段")
	_check(resume.get_candidate() == candidate, "简历上铺的就是当日名单第一位")
	_check(not dialoguer.visible, "对话框初始隐藏")
	_check(not menu.visible, "词条菜单初始隐藏")

	# ---- 追问过程中不能推进阶段：挂个探针 ----
	var advanced: Array[int] = []
	interview.phase_finished.connect(func() -> void: advanced.append(1))

	# ---- 点词条 → 开菜单 → 点「追问」----
	var list: VBoxContainer = resume.get_node("Paper/Rows/TokenList")
	var token0: Control = list.get_child(0)
	var ask: Button = menu.get_node("Options/OptionList/AskButton")
	token0.emit_signal("pressed")
	await _settle()
	_check(menu.is_open(), "点词条 → 菜单打开")

	ask.emit_signal("pressed")
	await _settle()

	_check(not menu.is_open(), "点「追问」→ 菜单收起（让位给对话框）")

	# ---- 对话框播的就是这一条的 json ----
	var typer: Typer = dialoguer.typer
	_check(dialoguer.visible, "点「追问」→ 对话框显示出来")
	_check(typer.lines.size() == expect0.size(),
			"播出的行数 = 该条追问 json 的行数（%d）" % expect0.size())
	if typer.lines.size() != expect0.size():
		return

	var lines_match := true
	for i in expect0.size():
		var want: Dictionary = expect0[i]
		var got: Dictionary = typer.lines[i]
		if String(got.get("speaker_name", "")) != String(want.get("speaker_name", "")) \
				or String(got.get("text", "")) != String(want.get("text", "")):
			lines_match = false
	_check(lines_match, "每一行的说话人 / 正文都与 json 逐字一致")
	_check(String(typer.lines[0].get("speaker_name", "")) == "面试官",
			"第 1 行说话人是「面试官」（实际「%s」）" % typer.lines[0].get("speaker_name", ""))
	_check(String(typer.lines[1].get("speaker_name", "")) == candidate.display_name,
			"第 2 行说话人是候选人名「%s」" % candidate.display_name)

	# 逐字显示：正文刚开播时不该一次性全露出来
	_check(typer.visible_characters < typer.get_full_text().length(),
			"正文是逐字显示（已露出 %d / %d）" % [
				typer.visible_characters, typer.get_full_text().length()])

	var name_label: Label = dialoguer.get_node_or_null("Name")
	_check(name_label != null and name_label.text == "面试官", "说话人 Label 显示「面试官」")

	# 播成功 = 这一条「问过了」：组队阶段的「回忆」就是照这份记录判断哪几条能点
	_check(GameState.has_asked_entry(candidate.id, 0), "追问成功后记下了「这一条问过」")
	_check(GameState.get_asked_entries(candidate.id) == [0],
			"记录里是第 0 条（实际 %s）" % str(GameState.get_asked_entries(candidate.id)))
	_check(not GameState.has_asked_entry(candidate.id, 1), "没问过的第 1 条仍然没有记录")

	# ---- 点一下：本行显示完 ----
	typer.skip_line()
	await _settle()
	_check(typer.visible_characters == typer.get_full_text().length(), "点一下 → 本行立刻显示完")

	# ---- 再点一下：翻到第 2 行，说话人换成候选人 ----
	typer.next_line()
	await _settle()
	_check(name_label.text == candidate.display_name,
			"翻到第 2 行 → 说话人换成「%s」" % candidate.display_name)

	# ---- 点到底：对话框收起，且**没有**推进阶段 ----
	typer.skip_line()
	typer.next_line()
	await _settle()
	_check(not dialoguer.visible, "最后一行点完 → 对话框收起")
	_check(advanced.is_empty(), "追问全程没有推进阶段（phase_finished 一次都没发）")
	_check(GameState.get_phase() == DayPhase.Phase.INTERVIEW, "阶段仍然是 INTERVIEW")

	# ---- 换一条：播的必须换成那一条自己的 json（换文件要重读）----
	token0 = list.get_child(1)
	token0.emit_signal("pressed")
	await _settle()
	ask.emit_signal("pressed")
	await _settle()
	_check(dialoguer.visible, "追问第 2 条 → 对话框再次播出")
	_check(typer.lines.size() == expect1.size(), "第 2 条播的行数 = 它自己那份 json 的行数")
	var second_match := typer.lines.size() == expect1.size()
	if second_match:
		for i in expect1.size():
			if String(typer.lines[i].get("text", "")) != String(expect1[i].get("text", "")):
				second_match = false
	_check(second_match, "第 2 条播的是**它自己**那份 json 的内容（没串成第 1 条的）")

	# ---- 播完追问之后再播默认文件：不能还留着追问 json 的内容 ----
	typer.next_line()
	typer.next_line()
	await _settle()
	_check(typer.load_dialogue("second"), "追问之后仍能按 id 装入默认 dialogue.json 的段")
	_check(String(typer.lines[0].get("speaker_name", "")) != "面试官",
			"装入默认文件后内容已换回（不是追问 json 的残留）")

	# ---- 别的阶段：追问必须被拦下（逻辑层守卫）----
	interview.set_phase(DayPhase.Phase.DAY_BRIEFING)
	await _settle()
	dialoguer.visible = false
	EventBus.resume_entry_asked.emit(candidate.id, 0)
	await _settle()
	_check(not dialoguer.visible, "非追问阶段发来的 resume_entry_asked 被忽略")

	# ---- 别人家的候选人：也该被拦下 ----
	interview.set_phase(DayPhase.Phase.INTERVIEW)
	await _settle()
	dialoguer.visible = false
	EventBus.resume_entry_asked.emit(&"c_9999", 0)
	await _settle()
	_check(not dialoguer.visible, "不是当前在面试那位的追问被忽略")

	# ---- 越界下标：不该炸，也不该播 ----
	dialoguer.visible = false
	EventBus.resume_entry_asked.emit(candidate.id, 999)
	await _settle()
	_check(not dialoguer.visible, "越界的条目下标被忽略")

	# ---- 档案忘配 ask_path：要拦住，而且不能拿上一份 json 顶包 ----
	# 同时确认**没播成的追问不算「问过」** —— 否则组队里那条会亮起来，点开却什么也没有。
	var saved := entry0.ask_path
	var asked_before := GameState.get_asked_entries(candidate.id)
	entry0.ask_path = ""
	dialoguer.visible = false
	EventBus.resume_entry_asked.emit(candidate.id, 0)
	await _settle()
	_check(not dialoguer.visible, "ask_path 为空 → 不播（也不拿上一份顶着）")
	entry0.ask_path = "res://data/asks/__not_there__.json"
	EventBus.resume_entry_asked.emit(candidate.id, 0)
	await _settle()
	_check(not dialoguer.visible, "ask_path 指向不存在的文件 → 不播")
	_check(GameState.get_asked_entries(candidate.id) == asked_before,
			"没播成的追问不记「问过」（记录仍是 %s）" % str(asked_before))
	entry0.ask_path = saved


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_interview_ask] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_interview_ask] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
