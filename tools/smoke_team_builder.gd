extends Node

## 组队界面自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_team_builder.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是 ARCHITECTURE.md §12 那几件事：
##   1. 左半边：**今日出现的面试者**一个不落，一人一个圆头像（黑色纯色圆边框 + 圆形裁切）；
##   2. 悬停：鼠标移上去 → 右半边铺出这一位的简历，**位置与面试时一模一样**；
##   3. 左键：点一下标记录用，再点一下撤销（真身在 GameState.current_team）。
##
## 画布与 smoke_resume_menu 同样是 1152x648：headless 下窗口尺寸不是游戏画布，
## 放进尺寸可控的 SubViewport 里才测得到「和面试同一个位置」这件事。

const TEAM_BUILDER_SCENE := preload("res://scenes/day/team_builder/team_builder.tscn")
const INTERVIEW_SCENE := preload("res://scenes/day/interview/interview.tscn")
const INTERVIEWEE_SCENE := preload("res://scenes/day/interview/interviewee.tscn")

const GAME_CANVAS := Vector2i(1152, 648)

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


func _make_canvas() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = GAME_CANVAS
	vp.disable_3d = true
	get_tree().root.add_child(vp)
	return vp


func _run() -> void:
	var vp := _make_canvas()

	# 数据全部来自 data/：开一局 → 当日名单 → 组队界面照着它铺。
	# 这里**不造**测试用候选人，测的就是「data/days/*.tres → 左半边头像」这条路。
	GameState.start_new_run(20261011)
	# 面试场景在 DAY_BRIEFING 会自己播开场对话；自检不需要那一段，把阶段拨到招人。
	GameState.set_phase(DayPhase.Phase.INTERVIEW)

	var candidates := GameState.current_candidates
	_check(candidates.size() >= 2, "第 1 天名单里至少 2 位候选人（实际 %d）" % candidates.size())
	if candidates.is_empty():
		return

	var builder := TEAM_BUILDER_SCENE.instantiate()
	vp.add_child(builder)
	await _settle()

	var ui: TeamBuilderUI = builder.get_node_or_null("TeamBuilderUI")
	var resume: Resume = builder.get_node_or_null("Resume")
	_check(ui != null, "组队场景里有 TeamBuilderUI")
	_check(resume != null, "组队场景里有 Resume（复用面试那一页简历）")
	if ui == null or resume == null:
		return

	var config := DataDB.get_day_config(GameState.get_day())
	var slots: int = config.slots if config != null else 0
	print("[smoke_team_builder] 第 %d 天：%d 位候选人，名额 %d" % [
		GameState.get_day(), candidates.size(), slots])

	# ---- 左半边：一人一个条目，顺序与名单一致 ----
	var entries := ui.entries()
	_check(entries.size() == candidates.size(),
			"左半边条数 = 今日候选人数（%d）" % candidates.size())
	_check(ui.header_text() == "HIRED 0 / %d" % slots,
			"表头报的是「已录用 0 / 名额」（实际「%s」）" % ui.header_text())

	for i in entries.size():
		var entry := entries[i]
		var who := candidates[i]
		_check(entry.candidate == who, "第 %d 条对应名单里的第 %d 位（%s）" % [i + 1, i + 1, who.id])
		_check(entry.hired == false, "第 %d 条初始没有录用标记" % (i + 1))

	# ---- 头像：拼自数据里的立绘配方，尺寸 = 圆的直径 ----
	var first := entries[0]
	var texture := first.avatar_texture()
	_check(texture != null, "第 1 条有头像贴图")
	if texture != null:
		_check(texture.get_size() == Vector2(CandidateEntry.AVATAR_SIZE, CandidateEntry.AVATAR_SIZE),
				"头像尺寸 = AVATAR_SIZE（%s）" % texture.get_size())

		# 圆形裁切：圆外必须一个不透明像素都没有，圆内得有内容（不是空图）
		var img := texture.get_image()
		var side := img.get_width()
		var center := Vector2(side, side) * 0.5
		var radius := side * 0.5
		var outside := 0
		var inside := 0
		var box := Rect2()
		var has_box := false
		for y in side:
			for x in side:
				if img.get_pixel(x, y).a <= 0.0:
					continue
				var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
				if distance > radius + 1.0:
					outside += 1
				elif distance < radius - 2.0:
					inside += 1
				var point := Vector2(x, y)
				if has_box:
					box = box.expand(point)
				else:
					box = Rect2(point, Vector2.ZERO)
					has_box = true
		_check(outside == 0, "圆外没有像素漏出来（越界像素 %d 个）" % outside)
		_check(inside > 0, "圆内有立绘内容（圆内不透明像素 %d 个）" % inside)
		_check(float(inside) / (PI * pow(radius, 2.0)) > 0.3,
				"头像填得够满（占圆面积 %.0f%%）" % (100.0 * float(inside) / (PI * pow(radius, 2.0))))

		# 取景是自动算的（框住整身的 alpha 包围盒）→ 人必须落在圆**正中**
		var box_center := box.position + box.size * 0.5
		_check(box_center.distance_to(center) <= 2.0,
				"立绘落在圆正中（包围盒中心 %s vs 圆心 %s）" % [box_center, center])

	# 每位都得有自己的头像（不是同一个人被铺了 N 遍）
	if candidates.size() >= 2:
		var textures_differ := entries[0].avatar_texture() != entries[1].avatar_texture()
		_check(textures_differ, "不同候选人的头像是各自的（不是同一张）")

	# ---- 2. 悬停 → 右半边铺简历，位置与面试同一处 ----
	_check(not resume.visible, "还没悬停过任何一位 → 右半边不铺简历")
	_check(resume.get_candidate() == null, "还没悬停过任何一位 → 简历没有候选人")

	entries[1].mouse_entered.emit()
	await _settle()
	_check(resume.visible, "悬停第 2 条 → 右半边出现简历")
	_check(resume.get_candidate() == candidates[1],
			"悬停的是名单里的第 2 位（%s）" % candidates[1].id)

	var info: Label = resume.get_node("Paper/Rows/HeaderInfo")
	_check(info.text == candidates[1].resume_header, "简历抬头 = 这一位数据里的 resume_header")
	var shown := 0
	for child in (resume.get_node("Paper/Rows/TokenList") as Node).get_children():
		if (child as Control).visible:
			shown += 1
	_check(shown == candidates[1].resume.size(),
			"铺出的词条数 = 这一位的简历条数（%d）" % candidates[1].resume.size())

	# 换一位：内容整块跟着换
	entries[0].mouse_entered.emit()
	await _settle()
	_check(resume.get_candidate() == candidates[0], "悬停第 1 条 → 换成第 1 位的简历")
	_check(info.text == candidates[0].resume_header, "抬头跟着换成第 1 位的")

	# 和面试场景比位置：同一个 resume.tscn、同一个绝对偏移 → 纸面矩形必须一模一样
	var itv_vp := _make_canvas()
	var interview := INTERVIEW_SCENE.instantiate()
	itv_vp.add_child(interview)
	await _settle()
	var itv_resume: Resume = interview.get_node_or_null("Resume")
	_check(itv_resume != null, "面试场景里也有 Resume")
	if itv_resume != null:
		_check(itv_resume.visible, "招人阶段面试的简历是可见的（对照前提成立）")
		var paper: Control = resume.get_node("Paper")
		var itv_paper: Control = itv_resume.get_node("Paper")
		_check(paper.get_global_rect() == itv_paper.get_global_rect(),
				"简历纸面与面试同一块位置（组队 %s / 面试 %s）" % [
					paper.get_global_rect(), itv_paper.get_global_rect()])
		var page: Sprite2D = resume.get_node("ResumePagePhd")
		var itv_page: Sprite2D = itv_resume.get_node("ResumePagePhd")
		_check(page.get_global_position() == itv_page.get_global_position(),
				"简历底纸与面试同一点（%s / %s）" % [
					page.get_global_position(), itv_page.get_global_position()])
		_check(resume.get_global_rect() == itv_resume.get_global_rect(),
				"简历根控件与面试同尺寸同位置")

	# ---- 3. 左键：标记录用 / 再点一次撤销 ----
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true

	entries[0]._gui_input(click)
	await _settle()
	_check(GameState.get_current_team().has(candidates[0].id),
			"左键点第 1 条 → 进了 GameState.current_team")
	_check(entries[0].is_hired(), "第 1 条画上了录用标记")
	_check(ui.header_text() == "HIRED 1 / %d" % slots,
			"表头跟着变成「已录用 1」（实际「%s」）" % ui.header_text())
	_check(builder.hired_ids() == GameState.get_current_team(),
			"team_builder 报的已录用名单 = GameState 里的队伍")

	entries[0]._gui_input(click)
	await _settle()
	_check(not GameState.get_current_team().has(candidates[0].id),
			"再点一次 → 从队伍里撤销")
	_check(not entries[0].is_hired(), "录用标记也撤掉")
	_check(ui.header_text() == "HIRED 0 / %d" % slots, "表头回到「已录用 0」")

	# 右键不该有任何反应（否则误触会把人选上又撤掉）
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	entries[0]._gui_input(right)
	await _settle()
	_check(not GameState.get_current_team().has(candidates[0].id), "右键点条目：不标记录用")

	# 两位都点上 → 都在队伍里
	entries[0]._gui_input(click)
	entries[1]._gui_input(click)
	await _settle()
	var team := GameState.get_current_team()
	_check(team.has(candidates[0].id) and team.has(candidates[1].id), "可以同时标记多位")
	_check(team.size() == 2, "队伍里有 2 位（实际 %d）" % team.size())
	_check(entries[0].is_hired() and entries[1].is_hired(), "两条都画着标记")
	_check(ui.hired_count() == 2, "hired_count() = 2")

	# 点子也顺手把简历换到这一位（「没悬停就点」的路径也说得通）
	_check(resume.get_candidate() == candidates[1], "点第 2 条后简历停在点的那一位")

	# ---- 空名单：不炸，条目全收起 ----
	ui.set_candidates([] as Array[CandidateResource])
	await _settle()
	_check(ui.entries().is_empty(), "名单为空 → 没有条目在画面上")
	_check(ui.hired_count() == 0, "名单为空 → 已录用计数归零")
	_check(ui.header_text() == "HIRED 0 / %d" % slots, "名单为空也照样报表头")
	ui.set_candidates(candidates)
	ui.set_hired_ids(GameState.get_current_team())
	await _settle()
	_check(ui.entries().size() == candidates.size(), "名单铺回来 → 条目数还原")
	_check(ui.hired_count() == 2, "已录用标记跟着还原")

	# ---- 立绘配方只有一份：头像与面试立绘用的是同一套部件图 ----
	await _check_portrait_parts(vp, candidates)

	# ---- 全库头像体检：换立绘 / 加种族 / 换帽子之后这条最先响 ----
	_check_all_avatars()

	# ---- 单条条目也能自己用（F6 / 复用） ----
	_check(entries[0].name == "CandidateEntry1", "条目按顺序命名（%s）" % entries[0].name)


## 数据里**每一位**候选人都得拼得出一张「有内容、且人在圆正中」的头像。
## 矮人的三顶帽子身量差一倍、精灵的耳朵横着伸出画布，这条就是防它们被取景切坏的锁。
func _check_all_avatars() -> void:
	const SIZE := 48
	var ids := DataDB.get_ids(&"candidates")
	_check(ids.size() > 0, "data/candidates 里有候选人（%d 位）" % ids.size())

	var blank := 0
	var off_center := 0
	var worst := 0.0
	for id in ids:
		var candidate: CandidateResource = DataDB.get_candidate(id)
		if candidate == null:
			continue
		var box := _opaque_box(PortraitComposer.avatar_image(candidate, SIZE))
		if box.size == Vector2.ZERO:
			blank += 1
			print("      · %s 拼出来是空的（race=%s）" % [id, candidate.portrait_race])
			continue
		var offset := (box.position + box.size * 0.5).distance_to(Vector2(SIZE, SIZE) * 0.5)
		worst = maxf(worst, offset)
		if offset > 2.0:
			off_center += 1
			print("      · %s 没落在圆正中（偏 %.1f px）" % [id, offset])

	_check(blank == 0, "%d 位候选人都拼得出头像（空图 %d 张）" % [ids.size(), blank])
	_check(off_center == 0,
			"每一位都落在圆正中（偏离 %d 位，最大偏移 %.1f px）" % [off_center, worst])


## 不透明像素的包围盒；全透明返回空矩形
func _opaque_box(img: Image) -> Rect2:
	var box := Rect2()
	var has_box := false
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a <= 0.0:
				continue
			var point := Vector2(x, y)
			if has_box:
				box = box.expand(point)
			else:
				box = Rect2(point, Vector2.ZERO)
				has_box = true
	return box


## 头像（PortraitComposer）与面试立绘（Interviewee）必须取到**同一批**部件图。
## 部件命名抽到 PortraitComposer 之后，这条就是防两边走偏的锁。
func _check_portrait_parts(vp: SubViewport, candidates: Array[CandidateResource]) -> void:
	var probe := INTERVIEWEE_SCENE.instantiate() as Interviewee
	vp.add_child(probe)
	await _settle()

	var mismatched := 0
	for candidate in candidates:
		probe.apply_candidate(candidate)
		var race := candidate.portrait_race
		# 空 stem = 这个种族不用这个部件 → 两边都该是「没有贴图」
		var expected := {
			"Body": _part_path(PortraitComposer.body_stem(race)),
			"Eye": _part_path(PortraitComposer.eye_stem(race, candidate.portrait_eye)),
			"Hair": _part_path(PortraitComposer.hair_stem(race, candidate.portrait_hair)),
			"Mouth": _part_path(PortraitComposer.mouth_stem(race, candidate.portrait_mouth)),
			"HatForDwarf": _part_path(PortraitComposer.hat_stem(race, candidate.portrait_hat)),
		}
		for node_name in expected.keys():
			var sprite := probe.get_node(node_name) as Sprite2D
			var want: String = expected[node_name]
			var got := "" if sprite.texture == null else sprite.texture.resource_path
			if got != want:
				mismatched += 1
				print("      · %s 的 %s：立绘=%s 期望=%s" % [candidate.id, node_name, got, want])
	_check(mismatched == 0, "面试立绘与头像取的是同一套部件图（不符 %d 处）" % mismatched)

	var stems := PortraitComposer.stems_for(candidates[0])
	_check(stems.size() >= 2, "第 1 位至少拼 2 个部件（实际 %d）" % stems.size())


## 空部件名（这个种族不用这个部件）→ 期望「没有贴图」，而不是拼出一个坏路径
func _part_path(stem: String) -> String:
	return "" if stem.is_empty() else PortraitComposer.path_of(stem)


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_team_builder] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_team_builder] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
