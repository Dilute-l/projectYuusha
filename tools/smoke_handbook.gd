extends Node

## 手册自检 —— 不需要编辑器，也不需要打开场景。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_handbook.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是「手册每次打开都从**封面（stamp 那页）**开始」这条约定：
##
##   interview.gd 的手册按钮 → Handbook.open() → open_entry(COVER_ENTRY_ID)
##                              → 组页（页序 = 解锁顺序）→ 翻开
##
## 顺带钉住它成立的前提：封面条目必须**无条件**（一开局就在账本里）、而且排在账本第一位。
## 哪天给 `data/handbook/stamp.tres` 加了 unlock_condition，它会先失败 —— 那正是要拦的。

const HANDBOOK_SCENE := preload("res://scenes/day/interview/handbook.tscn")

## 真的实例化面试场景，验「点那颗手册按钮 → 停在封面」。体量比单 Handbook 大，
## 但起始页的约定最终是**调用方**决定的，只测 Handbook 拦不住调用方传错 id。
const INTERVIEW_SCENE := preload("res://scenes/day/interview/interview.tscn")

## 游戏的实际画布（project.godot 的 canvas_items 拉伸基准）
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


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = GAME_CANVAS
	vp.disable_3d = true
	get_tree().root.add_child(vp)

	# ---- 1. 数据层：封面条目存在、无条件、是页序第一 ----
	var cover_id := Handbook.COVER_ENTRY_ID
	var cover: HandbookEntry = DataDB.get_handbook_entry(cover_id)
	_check(cover != null, "封面条目「%s」在 data/handbook 里" % cover_id)
	if cover == null:
		return
	_check(cover.unlock_condition.strip_edges().is_empty(),
			"封面条目**无条件**（一开局就能看）—— 实际条件：「%s」" % cover.unlock_condition)

	GameState.start_new_run(20261013)
	GameState.record_handbook_unlocks()
	var order := GameState.get_handbook_unlock_order()
	_check(order.size() > 0, "开局账本里就有条目（%d 条）" % order.size())
	_check(order.size() > 0 and order[0] == cover_id,
			"封面排在账本第一位（实际第一位 = %s）" % (order[0] if order.size() > 0 else "<空>"))

	# ---- 2. 控件层：open() 每次都落在封面上 ----
	var handbook := HANDBOOK_SCENE.instantiate() as Handbook
	vp.add_child(handbook)
	await _settle()
	_check(not handbook.is_open(), "刚挂上去是收着的")

	_check(handbook.open(), "open() 能打开手册")
	await _settle()
	_check(handbook.is_open(), "打开后 is_open() 为真")
	_check(handbook.current_entry() != null and handbook.current_entry().id == cover_id,
			"打开后停在**封面**（实际 %s）" % (
				handbook.current_entry().id if handbook.current_entry() != null else "<null>"))
	_check(handbook.page_count() == order.size(),
			"可翻页数 = 账本条数（%d / %d）" % [handbook.page_count(), order.size()])

	# 关掉再打开：**不能记住上次翻到哪**，仍从封面开始
	handbook._on_nextpage_pressed()
	await _settle()
	var after_turn := handbook.current_entry()
	_check(after_turn != null and after_turn.id != cover_id,
			"往后翻一页真的翻了（现在 = %s）" % (after_turn.id if after_turn != null else "<null>"))

	handbook.close()
	await _settle()
	_check(not handbook.is_open(), "close() 能收起手册")

	_check(handbook.open(), "再次打开")
	await _settle()
	_check(handbook.current_entry() != null and handbook.current_entry().id == cover_id,
			"**再打开仍然从封面开始**（不记住上次翻到哪）—— 实际 %s" % (
				handbook.current_entry().id if handbook.current_entry() != null else "<null>"))

	# ---- 3. open_entry(id) 那条路仍然可跳页（手册唯一的「翻到某条」能力）----
	var second: StringName = order[1] if order.size() > 1 else order[0]
	if order.size() > 1:
		_check(handbook.open_entry(second), "open_entry(%s) 能打开" % second)
		await _settle()
		_check(handbook.current_entry() != null and handbook.current_entry().id == second,
				"open_entry(id) 仍然直接翻到那一条（%s）" % second)
	# 传一条还没解锁 / 不存在的 id：退回第一页（= 封面），不报错
	_check(handbook.open_entry(&"__不存在__"), "open_entry(不存在的 id) 不崩、照常打开")
	await _settle()
	_check(handbook.current_entry() != null and handbook.current_entry().id == cover_id,
			"不存在的 id 退回第一页（= 封面）")

	# ---- 4. 边界按钮：封面是第一页 → 没有「上一页」 ----
	handbook.open()
	await _settle()
	var last_btn: TextureButton = handbook.get_node_or_null("lastpage") as TextureButton
	var next_btn: TextureButton = handbook.get_node_or_null("nextpage") as TextureButton
	_check(last_btn != null and not last_btn.visible, "封面页没有「上一页」按钮")
	_check(next_btn != null and next_btn.visible == (order.size() > 1),
			"不是最后一页时「下一页」可见")

	# ---- 5. 集成：面试场景那颗手册按钮，走的确实是「从封面开始」 ----
	# 这一条盯的是**调用方**：早先 interview.gd 里有个 HANDBOOK_PLACEHOLDER_ID = &"slime"，
	# 于是点手册直接跳到史莱姆那页 —— 上面的 open() 全绿也拦不住那种回归。
	#
	# ⚠️ 必须先把阶段拨到 INTERVIEW 再实例化：默认阶段是 DAY_BRIEFING，一挂上去就会播开场对话，
	#   而「对话没播完不开手册」是**正确行为**（interview.gd 的第一道守卫），
	#   不设阶段的话这里会验到那条守卫上去，而不是验本文件关心的起始页。
	GameState.set_phase(DayPhase.Phase.INTERVIEW)
	var interview := INTERVIEW_SCENE.instantiate()
	vp.add_child(interview)
	await _settle()
	interview.skip_animation()
	await _settle()
	_check(not interview.is_animating(), "面试场景的出场演出已经跳过")

	interview._on_handbook_button_pressed()
	await _settle()
	var itv_handbook: Handbook = interview.get_node_or_null("Handbook") as Handbook
	_check(itv_handbook != null and itv_handbook.is_open(), "面试场景的手册按钮能把手册打开")
	if itv_handbook != null and itv_handbook.is_open():
		_check(itv_handbook.current_entry() != null
				and itv_handbook.current_entry().id == cover_id,
				"点面试的手册按钮 → 停在封面（实际 %s）" % (
					itv_handbook.current_entry().id if itv_handbook.current_entry() != null else "<null>"))
		itv_handbook.close()
		await _settle()
	interview.queue_free()
	await _settle()

	handbook.queue_free()
	await _settle()
	vp.queue_free()
	await _settle()


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_handbook] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_handbook] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
