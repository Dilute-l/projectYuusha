extends Node

## 组队界面自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_team_builder.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是 ARCHITECTURE.md §12 那几件事：
##   1. 左半边：**今天通过面试的那几位**，一人一个方头像框
##      （`avatar_frame_phd` 方框 + `avatar_frame_background_phd` 底板 + **裁切过**的整身立绘）；
##   2. 右半边：**一进来是空的**，左键点某位的头像才铺出他的简历，位置与面试时一模一样；
##   3. 点头像 → 两个按钮从头像底下滑出来（approve 向右、reject 向左）+ 右下角露出名额空位；
##   4. 进队 = 底色转绿 + 占掉一个空格；不进队 = 转红 + 不占格（真身在 GameState）。
##
## 画布与 smoke_resume_menu 同样是 1152x648：headless 下窗口尺寸不是游戏画布，
## 放进尺寸可控的 SubViewport 里才测得到「和面试同一个位置」这件事。

const TEAM_BUILDER_SCENE := preload("res://scenes/day/team_builder/team_builder.tscn")
const FRAMED_AVATAR_SCENE := preload("res://scenes/day/team_builder/framed_avatar.tscn")
const INTERVIEW_SCENE := preload("res://scenes/day/interview/interview.tscn")
const INTERVIEWEE_SCENE := preload("res://scenes/day/interview/interviewee.tscn")

const GAME_CANVAS := Vector2i(1152, 648)

## 简历纸在画布上的实际范围（resume_page_phd.png 的不透明包围盒 + 底纸的 position）。
## 版面自检拿它当「右边那块不能压」的界线。
const RESUME_PAPER := Rect2(579, 29, 447, 556)

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


## 等按钮滑到位（tween 跑完）
func _settle_slide() -> void:
	await get_tree().create_timer(CandidateEntry.SLIDE_TIME + 0.12).timeout
	await _settle()


func _make_canvas() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = GAME_CANVAS
	vp.disable_3d = true
	get_tree().root.add_child(vp)
	return vp


## 左键点一下某个控件（直接走 _gui_input，不依赖鼠标位置）
func _click(control: Control) -> void:
	control._gui_input(_left_click())


func _left_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


## 当前队伍是否就是这几个人（顺序也要一样）
func _team_equals(expected: Array) -> bool:
	var team := GameState.get_current_team()
	if team.size() != expected.size():
		return false
	for i in team.size():
		if team[i] != expected[i]:
			return false
	return true


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

	# 面试只录用了第 1 位、否掉了第 2 位 —— 组队上该只看到第 1 位
	GameState.issue_verdict(candidates[0].id, true)
	GameState.issue_verdict(candidates[1].id, false)

	var config := DataDB.get_day_config(GameState.get_day())
	var slots: int = config.slots if config != null else 0
	print("[smoke_team_builder] 第 %d 天：%d 位候选人，通过 %d 位，名额 %d" % [
		GameState.get_day(), candidates.size(), GameState.get_passed_ids().size(), slots])

	var builder := TEAM_BUILDER_SCENE.instantiate()
	vp.add_child(builder)
	await _settle()

	var ui: TeamBuilderUI = builder.get_node_or_null("TeamBuilderUI")
	var resume: Resume = builder.get_node_or_null("Resume")
	_check(ui != null, "组队场景里有 TeamBuilderUI")
	_check(resume != null, "组队场景里有 Resume（复用面试那一页简历）")
	if ui == null or resume == null:
		return

	# ---- 1. 左半边 = 通过面试的人（被否掉的那位不出现）----
	var entries := ui.entries()
	_check(entries.size() == 1, "左半边只列通过者（%d 条，实际 %d）" % [1, entries.size()])
	if entries.is_empty():
		return
	var entry := entries[0]
	_check(entry.candidate == candidates[0], "这一条就是面试录用的那位（%s）" % candidates[0].id)
	for other in entries:
		_check(other.candidate != candidates[1], "被否掉的 %s 不在候选池里" % candidates[1].id)
	_check(GameState.get_current_team().is_empty(), "开场队伍是空的（进队要玩家自己按）")
	_check(entry.decision == FramedAvatar.Tint.NONE, "开场这位还没被判定（原色）")

	# ---- 2. 头像框：方框 + 底板 + 裁切过的整身立绘 ----
	_check_avatar_frame(entry, candidates[0], candidates[1] if candidates.size() > 1 else null)

	# ---- 3. 右半边一进来是空的 ----
	_check(not resume.visible, "还没点过任何一位 → 右半边不铺简历")
	_check(resume.get_candidate() == null, "还没点过任何一位 → 简历里没有候选人")

	# ---- 4. 右下角的名额空位：开局不露，数量 = 当天名额 ----
	var frames := ui.slot_frames()
	_check(not ui.slots_visible(), "还没点过任何一位 → 右下角的名额空位不露出来")
	_check(frames.size() == maxi(slots, 0),
			"空位数量 = 当天名额（%d 个，实际 %d）" % [slots, frames.size()])
	for frame in frames:
		_check(frame.is_empty(), "空位一开始都是空的（没有铺人）")
		_check(frame.pixel_size == TeamBuilderUI.SLOT_SIZE
				and frame.size.is_equal_approx(
					Vector2(TeamBuilderUI.SLOT_SIZE, TeamBuilderUI.SLOT_SIZE)),
				"空位按 SLOT_SIZE 渲染（pixel_size=%d size=%s）" % [
					frame.pixel_size, frame.size])

	# ---- 4b. 版面：谁在哪儿（§12.5）----
	_check_layout(ui, entries)

	# ---- 5. 按钮：先收在头像底下 ----
	var avatar: FramedAvatar = entry.framed_avatar()
	_check(not entry.is_expanded(), "还没点过 → 两个按钮收着")
	_check_button_art(entry)
	_check(entry.approve_button().get_index() < avatar.get_index()
			and entry.reject_button().get_index() < avatar.get_index(),
			"两个按钮排在头像**之前**（藏起来时真的被头像压住）")
	var collapsed: Dictionary = entry.collapsed_positions()
	_check(entry.approve_button().position.is_equal_approx(collapsed["approve"])
			and entry.reject_button().position.is_equal_approx(collapsed["reject"]),
			"收起来时两个按钮都在头像框里面（%s / %s）" % [
				entry.approve_button().position, entry.reject_button().position])
	_check(_inside_avatar(entry.approve_button()) and _inside_avatar(entry.reject_button()),
			"收起来时两个按钮的矩形完全落在头像矩形内 → 一点都看不见")
	_check(entry.approve_button().mouse_filter == Control.MOUSE_FILTER_IGNORE
			and entry.reject_button().mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"收起来时按钮不吃鼠标（GUI 拾取是从树尾往树头找的，留着 STOP 会点到头像底下的隐形按钮）")

	# ---- 6. 左键点头像 → 滑出按钮 + 铺简历 + 露出空位 ----
	_click(entry)
	await _settle_slide()
	_check(entry.is_expanded(), "左键点头像 → 两个按钮滑出来")
	_check(resume.visible, "点头像 → 右半边出现这一位的简历")
	_check(resume.get_candidate() == candidates[0], "铺的是点的那一位（%s）" % candidates[0].id)
	_check(ui.expanded_entry() == entry, "UI 记得现在展开的是这一条")
	_check(ui.slots_visible(), "点头像 → 右下角的名额空位露出来")

	var declaration: Label = resume.get_node("DeclarationContainer")
	_check(declaration.text == candidates[0].team_declaration,
			"组队宣言 = 这一位数据里的 team_declaration")
	_check(resume.token_count() == Resume.entries_of(candidates[0]).size(),
			"铺出的词条数 = 这一位的履历 + 专长（%d）" % Resume.entries_of(candidates[0]).size())

	var want: Dictionary = entry.expanded_positions()
	_check(entry.approve_button().position.is_equal_approx(want["approve"]),
			"approve 滑到右边（%s，期望 %s）" % [entry.approve_button().position, want["approve"]])
	_check(entry.reject_button().position.is_equal_approx(want["reject"]),
			"reject 滑到左边（%s，期望 %s）" % [entry.reject_button().position, want["reject"]])
	_check(entry.approve_button().position.x > 0.0
			and entry.reject_button().position.x < 0.0,
			"approve 在头像右外侧、reject 在左外侧")
	_check(_overlaps_avatar(entry.approve_button(), CandidateEntry.BUTTON_OVERLAP)
			and _overlaps_avatar(entry.reject_button(), CandidateEntry.BUTTON_OVERLAP),
			"滑出来之后各自还压着头像 %d px（像是从框底下滑出来的）" % int(CandidateEntry.BUTTON_OVERLAP))
	_check(entry.approve_button().mouse_filter == Control.MOUSE_FILTER_STOP
			and entry.reject_button().mouse_filter == Control.MOUSE_FILTER_STOP,
			"滑出来之后按钮才吃鼠标")

	# ---- 7. 进队：底色转绿 + 占掉一个空格 ----
	entry.approve_button().pressed.emit()
	await _settle_slide()
	_check(_team_equals([candidates[0].id]),
			"按 approve → 进了 GameState.current_team（实际 %s）" % str(GameState.get_current_team()))
	_check(entry.is_approved(), "这一条的判定变成「进队」")
	_check(avatar.background_control().self_modulate
			.is_equal_approx(FramedAvatar.TINT_COLORS[FramedAvatar.Tint.APPROVED]),
			"进队的人底板转绿（实际 %s）" % avatar.background_control().self_modulate)
	_check(not entry.is_expanded(), "判定完两个按钮收回去（再点一次头像可以重新展开）")
	_check(entry.approve_button().mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"收回去之后按钮又不吃鼠标了")
	_check(ui.approved_count() == 1, "已进队计数 = 1（实际 %d）" % ui.approved_count())
	var slots_now := ui.slot_frames()
	_check(slots_now.size() == maxi(slots, 0), "空位数量不因为进人而变化")
	_check(slots_now.size() > 0 and slots_now[0].candidate == candidates[0],
			"第 1 个空格填进了这一位")
	_check(slots_now.size() > 0 and slots_now[0].background_control().self_modulate
			.is_equal_approx(FramedAvatar.TINT_COLORS[FramedAvatar.Tint.APPROVED]),
			"被占的格子底色也是绿的")
	_check(resume.get_candidate() == candidates[0], "判定完简历不撤（不会读到一半白掉）")

	# ---- 8. 再点头像 → 重新展开 → 改成「不进队」 ----
	_click(entry)
	await _settle_slide()
	_check(entry.is_expanded(), "判定过的人再点一次头像，两个按钮重新展开（可以改主意）")
	entry.reject_button().pressed.emit()
	await _settle_slide()
	_check(not GameState.get_current_team().has(candidates[0].id),
			"按 reject → 从 current_team 里拿掉")
	_check(GameState.get_rejected_ids().has(candidates[0].id),
			"按 reject → 记进 GameState.rejected_ids（实际 %s）" % str(GameState.get_rejected_ids()))
	_check(entry.is_rejected(), "这一条的判定变成「不进队」")
	_check(avatar.background_control().self_modulate
			.is_equal_approx(FramedAvatar.TINT_COLORS[FramedAvatar.Tint.REJECTED]),
			"不进队的人底板转红（实际 %s）" % avatar.background_control().self_modulate)
	_check(slots_now.size() > 0 and ui.slot_frames()[0].candidate == null,
			"不进队的人不占名额：第 1 个格子又空了")

	# 再按回进队：两种判定互斥，rejected_ids 要跟着划掉
	_click(entry)
	await _settle_slide()
	entry.approve_button().pressed.emit()
	await _settle_slide()
	_check(_team_equals([candidates[0].id]), "改回进队 → 又回到 current_team")
	_check(not GameState.get_rejected_ids().has(candidates[0].id),
			"改回进队 → rejected_ids 里划掉（实际 %s）" % str(GameState.get_rejected_ids()))

	# 右键不该有任何反应（否则误触会把人选上又撤掉）
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	entry._gui_input(right)
	await _settle_slide()
	_check(not entry.is_expanded(), "右键点条目：不展开按钮")
	_check(_team_equals([candidates[0].id]), "右键不改队伍")
	_check(not GameState.get_rejected_ids().has(candidates[0].id), "右键不改「不进队」名单")

	# ---- 9. 和面试比位置：同一个 resume.tscn、同一套绝对偏移 → 纸面矩形必须一模一样 ----
	await _check_resume_geometry(vp, resume)

	# ---- 10. 立绘配方只有一份：头像与面试立绘用的是同一套部件图 ----
	var who: Array[CandidateResource] = [candidates[0]]
	await _check_portrait_parts(vp, who)

	# ---- 11. 全库立绘体检：换立绘 / 加种族 / 换帽子之后这条最先响 ----
	_check_all_portraits()

	# ---- 12. 单条条目也能自己用（F6 / 复用） ----
	_check(entry.name == "CandidateEntry1", "条目按顺序命名（%s）" % entry.name)

	# 前面这两个实例先撤掉：下面要**重开一局**，留着它们会让两个 TeamBuilder
	# 同时挂在新一天的信号上（同一次「回忆」被播两遍）。
	builder.queue_free()
	await _settle()

	# ---- 13. 新一天：两条候选人 / 回忆 / 名额拦截 ----
	await _check_new_day(vp)

	# ---- 悬停高亮：只剩一个灰色矩形，没有描边（哪款灰见 smoke_hover_gray）----
	_check_hover_style()


# ---------------------------------------------------------------------------
# 头像框本身
# ---------------------------------------------------------------------------


## 一条条目的头像框：方框 / 底板用的是指定的两张美术，立绘**不居中、超出部分被切掉**。
func _check_avatar_frame(
	entry: CandidateEntry,
	who: CandidateResource,
	absent: CandidateResource
) -> void:
	var avatar := entry.framed_avatar()
	_check(avatar != null, "条目的头像是个 FramedAvatar（方框头像）")
	if avatar == null:
		return

	var background := avatar.background_control()
	var frame: TextureRect = avatar.get_node("Frame")
	_check(avatar.pixel_size == CandidateEntry.AVATAR_SIZE
			and avatar.size.is_equal_approx(
				Vector2(CandidateEntry.AVATAR_SIZE, CandidateEntry.AVATAR_SIZE)),
			"头像框按 CandidateEntry.AVATAR_SIZE 渲染（pixel_size=%d size=%s）" % [
				avatar.pixel_size, avatar.size])
	_check(background.texture != null
			and background.texture.resource_path == AvatarFrame.BACKGROUND_PATH,
			"底板用的是 %s" % AvatarFrame.BACKGROUND_PATH.get_file())
	_check(frame.texture != null and frame.texture.resource_path == AvatarFrame.FRAME_PATH,
			"方框用的是 %s" % AvatarFrame.FRAME_PATH.get_file())

	# 立绘 = 整张立绘画布（没有取景、没有裁圆、没有缩放）；尺寸是**立绘自己的**画布常量
	var portrait: TextureRect = avatar.get_node("Clip/Portrait")
	var texture := avatar.portrait_texture()
	_check(texture != null, "这一位铺上了立绘")
	_check(texture != null and texture == PortraitComposer.portrait_texture(who),
			"立绘来自 PortraitComposer.portrait_texture()（和面试同一套部件图）")
	_check(texture != null and texture.get_size() == Vector2(
				PortraitComposer.CANVAS, PortraitComposer.CANVAS_H),
			"立绘是**整张画布**原位贴的，没有被缩放 / 取景（%s）" % (
				texture.get_size() if texture != null else Vector2.ZERO))
	if absent != null:
		_check(texture != PortraitComposer.portrait_texture(absent),
				"不同候选人的立绘不是同一张")

	# 取景窗：clip_contents 的窗口按 AvatarFrame 的常量摆
	var window := AvatarFrame.window_rect(float(CandidateEntry.AVATAR_SIZE))
	var clip := avatar.clip_control()
	_check(clip.clip_contents, "取景窗开了 clip_contents（框外的像素画不出来）")
	_check(clip.position.is_equal_approx(window.position)
			and clip.size.is_equal_approx(window.size),
			"取景窗落在 AvatarFrame.window_rect()（%s %s）" % [clip.position, clip.size])

	# 水平**居中**：立绘画布的中心必须落在取景窗的中心上（横向不偏）。
	# 立绘里的人都画在画布正中，所以这条成立 = 画面里的人是居中的。
	var portrait_center := portrait.position.x + portrait.size.x * 0.5
	var window_center := window.position.x + window.size.x * 0.5
	_check(is_equal_approx(portrait_center, window_center),
			"立绘画布在取景窗里**水平居中**（画布中心 %.1f == 窗口中心 %.1f）" % [
				portrait_center, window_center])
	# 两边的留白相等（上一条的直观等价写法）。
	# ⚠️ 这两个值在 160px 的头像上是**负的**：立绘折算后宽 192 > 窗口宽 135，
	#   居中就意味着两侧各被窗口盖掉一截（对称），这是「画布比窗口大」的正常结果，
	#   不是版面错 —— 所以只断言左右相等，不断言正负。
	var left_gap := portrait.position.x - window.position.x
	var right_gap := window.position.x + window.size.x - (portrait.position.x + portrait.size.x)
	_check(is_equal_approx(left_gap, right_gap),
			"立绘左右两侧露出的余量相等（左 %.1f / 右 %.1f）" % [left_gap, right_gap])
	_check(portrait.size.x > window.size.x and portrait.size.y > window.size.y,
			"立绘比取景窗大 → 超出边框的部分交给裁切切掉（立绘 %s / 窗口 %s）" % [
				portrait.size, window.size])

	# 空位（没人）时立绘清空
	var probe := FRAMED_AVATAR_SCENE.instantiate() as FramedAvatar
	add_child(probe)
	probe.set_candidate(null)
	_check(probe.is_empty() and probe.portrait_texture() == null, "没人的格子不画立绘")
	probe.queue_free()


## 两个按钮：贴图裁自 AvatarFrame 报的那两块、尺寸按宽高比
func _check_button_art(entry: CandidateEntry) -> void:
	for spec in [
		{ "button": entry.approve_button(), "art": AvatarFrame.APPROVE_ART,
			"path": AvatarFrame.APPROVE_BUTTON_PATH },
		{ "button": entry.reject_button(), "art": AvatarFrame.REJECT_ART,
			"path": AvatarFrame.REJECT_BUTTON_PATH },
	]:
		var button: TextureButton = spec["button"]
		var art: Rect2 = spec["art"]
		var atlas := button.texture_normal as AtlasTexture
		_check(atlas != null, "按钮贴图是裁出来的 AtlasTexture")
		if atlas == null:
			continue
		_check(atlas.atlas != null and atlas.atlas.resource_path == spec["path"],
				"按钮贴图来自 %s" % String(spec["path"]).get_file())
		_check(atlas.region == art, "裁的是 AvatarFrame 报的那一块（%s）" % art)
		var want := AvatarFrame.size_for_width(art, CandidateEntry.BUTTON_WIDTH)
		_check(button.size.is_equal_approx(want),
				"按钮尺寸按美术宽高比算（%s，期望 %s）" % [button.size, want])


## 版面（§12.5）：UI 容器顶满画布、头像列在左半边、右下角的空位贴着右下角
## 且**躲在简历纸下缘之下**（纸面占 x 579〜1026 / y 29〜585），谁也不压谁。
func _check_layout(ui: TeamBuilderUI, entries: Array[CandidateEntry]) -> void:
	for i in entries.size():
		var want := Vector2(
			TeamBuilderUI.ENTRY_LEFT,
			TeamBuilderUI.ENTRY_TOP + float(i) * TeamBuilderUI.ENTRY_PITCH
		)
		_check(entries[i].position.is_equal_approx(want),
				"第 %d 个头像框摆在第 %d 行（%s）" % [i + 1, i + 1, entries[i].position])

	# 展开之后最右边那一下也不能压到简历纸
	var right_edge := TeamBuilderUI.ENTRY_LEFT + float(CandidateEntry.AVATAR_SIZE) \
			+ CandidateEntry.BUTTON_WIDTH - CandidateEntry.BUTTON_OVERLAP
	_check(right_edge <= RESUME_PAPER.position.x,
			"头像和滑出来的 approve 都在简历纸左边（最右 %d <= 纸面 %d）" % [
				int(right_edge), int(RESUME_PAPER.position.x)])

	var slots := ui.slots_control()
	var rect := slots.get_global_rect()
	_check(rect.size.x > 0.0 and rect.size.y > 0.0, "空位容器有实际尺寸（%s）" % rect.size)
	_check(is_equal_approx(rect.position.x + rect.size.x,
			float(GAME_CANVAS.x) - TeamBuilderUI.SLOT_RIGHT_MARGIN),
			"空位右对齐贴屏幕右边（右缘 %.1f）" % (rect.position.x + rect.size.x))
	_check(rect.position.y >= RESUME_PAPER.position.y + RESUME_PAPER.size.y,
			"空位整个落在简历纸下缘之下，不遮简历（空位顶 %.1f >= 纸底 %.1f）" % [
				rect.position.y, RESUME_PAPER.position.y + RESUME_PAPER.size.y])
	_check(rect.position.y + rect.size.y <= float(GAME_CANVAS.y),
			"空位不超出画布下沿（底 %.1f <= %d）" % [
				rect.position.y + rect.size.y, GAME_CANVAS.y])


## 控件的矩形是否完全落在头像矩形里（= 藏起来时被头像盖住）
func _inside_avatar(control: Control) -> bool:
	var avatar := Rect2(Vector2.ZERO, Vector2(CandidateEntry.AVATAR_SIZE, CandidateEntry.AVATAR_SIZE))
	return avatar.encloses(Rect2(control.position, control.size))


## 控件的矩形是否和头像矩形重叠**正好** overlap 像素（= 滑出来之后还压着框边）
func _overlaps_avatar(control: Control, overlap: float) -> bool:
	var left := control.position.x
	var right := control.position.x + control.size.x
	if left >= 0.0:
		return is_equal_approx(left, CandidateEntry.AVATAR_SIZE - overlap)
	return is_equal_approx(right, overlap)


# ---------------------------------------------------------------------------
# 简历与面试同一处
# ---------------------------------------------------------------------------


func _check_resume_geometry(vp: SubViewport, resume: Resume) -> void:
	var itv_vp := _make_canvas()
	var interview := INTERVIEW_SCENE.instantiate()
	itv_vp.add_child(interview)
	# 面试场景一进招人阶段就会演一段出场（§13），刚挂上去时纸还在画面下方。
	# 这里要比的是**站定之后**的纸面矩形，所以先把演出跳过再量。
	interview.skip_animation()
	await _settle()
	var itv_resume: Resume = interview.get_node_or_null("Resume")
	_check(itv_resume != null, "面试场景里也有 Resume")
	if itv_resume != null:
		_check(itv_resume.visible, "招人阶段面试的简历是可见的（对照前提成立）")
		# 新版面没有 Paper 这个中间容器了，各栏直接挂在根节点下 ——
		# 换成比一栏的真实矩形：两个实例共用同一个 resume.tscn 的绝对偏移，位置必须一模一样。
		var name_here: Control = resume.get_node("NameContainer")
		var name_itv: Control = itv_resume.get_node("NameContainer")
		_check(name_here.get_global_rect() == name_itv.get_global_rect(),
				"简历各栏与面试同一块位置（组队 %s / 面试 %s）" % [
					name_here.get_global_rect(), name_itv.get_global_rect()])
		var page: Sprite2D = resume.get_node("ResumePagePhd")
		var itv_page: Sprite2D = itv_resume.get_node("ResumePagePhd")
		_check(page.get_global_position() == itv_page.get_global_position(),
				"简历底纸与面试同一点（%s / %s）" % [
					page.get_global_position(), itv_page.get_global_position()])
		_check(resume.get_global_rect() == itv_resume.get_global_rect(),
				"简历根控件与面试同尺寸同位置")
	interview.queue_free()
	await _settle()


# ---------------------------------------------------------------------------
# 新一天的玩法（§12 / §10.7）
# ---------------------------------------------------------------------------


func _check_new_day(vp: SubViewport) -> void:
	GameState.start_new_run(20261011)
	GameState.set_phase(DayPhase.Phase.TEAM_BUILD)
	var candidates := GameState.current_candidates
	_check(candidates.size() >= 2, "重开一局后名单至少 2 位（实际 %d）" % candidates.size())
	if candidates.size() < 2:
		return

	# 面试阶段：两位都通过（都在组队的候选池里）
	GameState.issue_verdict(candidates[0].id, true)
	GameState.issue_verdict(candidates[1].id, true)

	var builder := TEAM_BUILDER_SCENE.instantiate()
	vp.add_child(builder)
	await _settle()

	var ui: TeamBuilderUI = builder.get_node_or_null("TeamBuilderUI")
	var resume: Resume = builder.get_node_or_null("Resume")
	_check(ui != null and resume != null, "新一天的组队场景里有 UI 与简历")
	if ui == null or resume == null:
		return

	var entries := ui.entries()
	_check(entries.size() == 2, "两位都通过 → 左半边两条（实际 %d）" % entries.size())
	if entries.size() < 2:
		return
	_check(ui.slot_frames().size() == maxi(_today_slots(), 0),
			"右下角空位数 = 当天名额")

	# ---- 同时只展开一条 ----
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	entries[1]._gui_input(click)
	await _settle_slide()
	_check(entries[1].is_expanded() and not entries[0].is_expanded(),
			"点第 2 条 → 只有第 2 条展开")
	_check(ui.expanded_entry() == entries[1], "UI 记的展开条目跟着换")
	_check(resume.get_candidate() == candidates[1], "简历跟着换成第 2 位")
	entries[0]._gui_input(click)
	await _settle_slide()
	_check(entries[0].is_expanded() and not entries[1].is_expanded(),
			"改点第 1 条 → 上一条收起来、只剩第 1 条展开")
	entries[0]._gui_input(click)
	await _settle_slide()
	_check(not entries[0].is_expanded(), "再点同一条 → 收起来")
	_check(resume.get_candidate() == candidates[0], "收起来不动简历")

	# ---- 名额满了 → 「进队」按钮置灰，但仍然能点「不进队」 ----
	var slots := _today_slots()
	if slots > 0:
		var team: Array[StringName] = []
		for i in mini(slots, entries.size()):
			team.append(entries[i].candidate.id)
		GameState.set_current_team(team)
		ui.set_decisions(GameState.get_current_team(), GameState.get_rejected_ids())
		ui.set_team_full(TeamValidator.is_full(GameState.get_current_team(), slots))
		await _settle()
		var free_entry: CandidateEntry = _first_undecided(entries)
		if free_entry != null:
			_check(free_entry.approve_button().disabled,
					"名额满了 → 还没进队的那几条「进队」按钮置灰")
			_check(not free_entry.reject_button().disabled,
					"名额满了也不挡「不进队」（撤销从来不该被名额挡住）")
			free_entry.set_expanded(true)
			await _settle()
			_check(free_entry.approve_button().mouse_filter == Control.MOUSE_FILTER_IGNORE,
					"置灰的「进队」也不吃鼠标（这一下该落到头像上：展开 / 收起照旧）")
			_check(free_entry.reject_button().mouse_filter == Control.MOUSE_FILTER_STOP,
					"同一时刻「不进队」照旧可点")
			free_entry.set_expanded(false)

	# ---- 回忆 ----
	await _check_recall(builder, resume, entries, candidates)

	# ---- 超员：拦住，不让出发 ----
	await _check_over_quota_guard(builder, candidates)
	builder.queue_free()
	await _settle()


## 第一条还没被判定的人（没有就返回 null）
func _first_undecided(entries: Array[CandidateEntry]) -> CandidateEntry:
	for entry in entries:
		if entry.decision == FramedAvatar.Tint.NONE:
			return entry
	return null


func _today_slots() -> int:
	var config := DataDB.get_day_config(GameState.get_day())
	return config.slots if config != null else 0


## 回忆：菜单文案变「回忆」，没问过的置灰，问过的重播当时那段 + 一句自言自语。
func _check_recall(
	builder: Node,
	resume: Resume,
	entries: Array[CandidateEntry],
	candidates: Array[CandidateResource]
) -> void:
	var menu: ResumeTokenMenu = resume.get_node("TokenMenu")
	var dialoguer: Dialoguer = builder.get_node_or_null("Dialoguer")
	_check(resume.entry_menu == Resume.EntryMenu.RECALL, "组队里的简历是「回忆」模式")
	_check(menu != null and dialoguer != null, "组队场景里有词条菜单与对话框")
	if menu == null or dialoguer == null:
		return

	var ask: Button = menu.get_node("Options/OptionList/AskButton")
	entries[0]._gui_input(_left_click())
	await _settle_slide()
	_check(resume.get_candidate() == candidates[0], "点头像后简历铺的是这一位")

	var token: Control = resume.token_at(0)
	token.emit_signal("pressed")
	await _settle()
	_check(menu.is_open(), "组队里点词条 → 菜单照样打开")
	_check(ask.text == "回忆", "选项文案是「回忆」（实际「%s」）" % ask.text)

	# 这一条没问过 → 置灰
	_check(not GameState.has_asked_entry(candidates[0].id, 0), "前提：这一条还没问过")
	_check(ask.disabled, "没问过的条目，选项是灰的")
	var recalled: Array = []
	var spy := func(cid: StringName, i: int) -> void: recalled.append([cid, i])
	EventBus.resume_entry_recalled.connect(spy)
	ask.pressed.emit()
	await _settle()
	_check(recalled.is_empty(), "置灰的选项点了也没反应")

	# 面试时问过这一条 → 亮起来
	GameState.record_entry_asked(candidates[0].id, 0)
	token.emit_signal("pressed")
	await _settle()
	_check(not ask.disabled, "问过的条目，选项可以点")
	ask.pressed.emit()
	await _settle()
	EventBus.resume_entry_recalled.disconnect(spy)
	_check(recalled == [[candidates[0].id, 0]],
			"点「回忆」广播了 resume_entry_recalled（实际 %s）" % str(recalled))

	# 播的内容 = 当时那份 json + 一句自言自语
	var expect := _read_ask(Resume.ask_path_of(candidates[0], 0))
	_check(dialoguer.visible, "回忆把对话框叫起来了")
	_check(dialoguer.typer.lines.size() == expect.size() + 1,
			"回忆的行数 = 当时那份 json + 1 句（%d + 1，实际 %d）" % [
				expect.size(), dialoguer.typer.lines.size()])
	if dialoguer.typer.lines.size() != expect.size() + 1:
		return
	var matched := true
	for i in expect.size():
		if String(dialoguer.typer.lines[i].get("text", "")) != String(expect[i].get("text", "")):
			matched = false
	_check(matched, "回忆的前几行 = 当时那份 json 的内容")
	var tail: Dictionary = dialoguer.typer.lines[expect.size()]
	_check(String(tail.get("speaker_name", "")) == "面试官"
			and String(tail.get("text", "")) == "当时好像是这样追问的。",
			"最后追加的是面试官那句自言自语（实际「%s：%s」）" % [
				tail.get("speaker_name", ""), tail.get("text", "")])


## 超员时不许出发（§12）；减到名额以内立刻就能走。
func _check_over_quota_guard(builder: Node, candidates: Array[CandidateResource]) -> void:
	var slots := _today_slots()
	_check(slots > 0, "当天有名额数据（超员的前提，slots=%d）" % slots)
	var confirm: Button = builder.get_node_or_null("Confirm")
	_check(confirm != null, "组队场景里有「组队完成」按钮")
	if slots <= 0 or confirm == null:
		return

	var departed: Array[int] = []
	builder.phase_finished.connect(func() -> void: departed.append(1))

	# 把队伍撑到 slots + 1（这里只关心条数，多出来的那位借第一位的 id 凑数）
	var over: Array[StringName] = []
	for i in slots + 1:
		over.append(candidates[i % candidates.size()].id)
	GameState.set_current_team(over)
	_check(TeamValidator.is_over(over, slots),
			"TeamValidator.is_over 认得超员（%d > %d）" % [over.size(), slots])

	confirm.pressed.emit()
	await _settle()
	_check(departed.is_empty(), "队员超过名额 → 点「组队完成」出不去（连点两次也没用）")
	confirm.pressed.emit()
	await _settle()
	_check(departed.is_empty(), "再点一次仍然出不去")

	# 减到名额以内 → 立刻出发（证明拦的只是超员，不是把正常路也堵了）
	var legal: Array[StringName] = []
	for i in mini(slots, candidates.size()):
		legal.append(candidates[i].id)
	GameState.set_current_team(legal)
	await _settle()
	confirm.pressed.emit()
	await _settle()
	_check(departed.size() == 1, "减到名额以内后点一下就能出发")


# ---------------------------------------------------------------------------
# 其它
# ---------------------------------------------------------------------------


## 悬停高亮 = 只有一个灰色矩形，没有描边（全游戏共用同一款，见 smoke_hover_gray）。
## 直接量 StyleBox（不截图）：换个 .tres 就会在这儿响，不依赖渲染结果。
func _check_hover_style() -> void:
	var hover := load("res://ui/styles/hover_gray.tres") as StyleBoxFlat
	_check(hover != null, "词条的悬停样式能加载")
	if hover == null:
		return
	_check(hover.draw_center and hover.bg_color.a > 0.0,
			"悬停画的是底色矩形（bg=%.2f,%.2f,%.2f a=%.2f）" % [
				hover.bg_color.r, hover.bg_color.g, hover.bg_color.b, hover.bg_color.a])
	var border := hover.border_width_left + hover.border_width_top \
			+ hover.border_width_right + hover.border_width_bottom
	_check(border == 0, "悬停不再描边（四边线宽合计 %d）" % border)


## 读一份追问 json 的行数组（读不出来返回空数组）
func _read_ask(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Array else []


## 数据里**每一位**候选人都得拼得出一张「有内容」的整身立绘（头像框直接铺它）。
## 矮人的三顶帽子身量差一倍、精灵的耳朵横着伸出画布，这条就是防它们配不出图的锁。
func _check_all_portraits() -> void:
	var ids := DataDB.get_ids(&"candidates")
	_check(ids.size() > 0, "data/candidates 里有候选人（%d 位）" % ids.size())

	var blank := 0
	for id in ids:
		var candidate: CandidateResource = DataDB.get_candidate(id)
		if candidate == null:
			continue
		var texture := PortraitComposer.portrait_texture(candidate)
		if texture == null or _opaque_box(texture.get_image()).size == Vector2.ZERO:
			blank += 1
			print("      · %s 拼出来是空的（race=%s）" % [id, candidate.portrait_race])
	_check(blank == 0, "%d 位候选人都拼得出整身立绘（空图 %d 张）" % [ids.size(), blank])


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


## 头像框里的立绘（PortraitComposer）与面试立绘（Interviewee）必须取到**同一批**部件图。
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
	_check(mismatched == 0, "面试立绘与头像框取的是同一套部件图（不符 %d 处）" % mismatched)

	var stems := PortraitComposer.stems_for(candidates[0])
	_check(stems.size() >= 2, "第 1 位至少拼 2 个部件（实际 %d）" % stems.size())

	probe.queue_free()
	await _settle()


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
