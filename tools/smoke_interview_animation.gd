extends Node

## 面试出场演出自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_interview_animation.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是 ARCHITECTURE.md §13 那一串动作，逐帧采样后按顺序验：
##
##   进入招人阶段 → 面试者从画面右边走进来（边走边上下晃）→ 站定
##                → 简历从画面下方升起
##   按下录用     → 面试者向左走出画面 → 他的简历往画面上方移走
##                → 下一位从右边走进来 → 下一位的简历从下方升起
##   最后一位     → 停在「走光 + 纸移走」，然后才发 phase_finished
##
## **采样而不是等固定秒数**：演出是按 delta 走的，headless 下帧率又不受限，
## 「等 1 秒」和「动画走完了没有」之间没有稳定换算关系 —— 按条件等才不会假红。

const INTERVIEW_SCENE := preload("res://scenes/day/interview/interview.tscn")

## 游戏的实际画布（project.godot 的 canvas_items 拉伸基准）
const GAME_CANVAS := Vector2i(1152, 648)

## 演出按真实时间走，自检没必要陪它等：把时间整体调快，采样反而更密。
## 结束时记得拨回 1.0 —— 同一个进程里后面若还有别的检查，不该受这里影响。
const TIME_SCALE := 2.0

## 单段演出的采样上限（真实毫秒）。正常一段不到两秒，超过就是卡住了。
const SEQUENCE_TIMEOUT_MS := 20000

var _failures: Array[String] = []
var _checks: int = 0


## 逐帧采样一段演出：立绘的 x / y、简历的纵向偏移、以及「这一帧他是不是在走」。
##
## 三条曲线放在一起按同一套下标对齐，才能验「谁先谁后」这件事 ——
## 只看首尾姿态是验不出顺序的。
class Track:
	var xs: Array[float] = []
	var ys: Array[float] = []
	var offs: Array[float] = []
	var walking: Array[bool] = []

	func size() -> int:
		return xs.size()

	func min_x() -> float:
		var out := INF
		for v in xs:
			out = minf(out, v)
		return out

	func max_x() -> float:
		var out := -INF
		for v in xs:
			out = maxf(out, v)
		return out

	func min_offset() -> float:
		var out := INF
		for v in offs:
			out = minf(out, v)
		return out

	func max_offset() -> float:
		var out := -INF
		for v in offs:
			out = maxf(out, v)
		return out

	## 纵向离站定高度最远的那一帧（走路晃动的振幅）
	func max_bob(rest_y: float) -> float:
		var out := 0.0
		for v in ys:
			out = maxf(out, absf(v - rest_y))
		return out

	## x 第一次落到 limit 及以下的下标（-1 = 一直没到）
	func first_x_at_most(limit: float) -> int:
		for i in xs.size():
			if xs[i] <= limit:
				return i
		return -1

	## 纵向偏移第一次落到 limit 及以下的下标（找「往上方移走」那一拍）
	func first_offset_at_most(limit: float) -> int:
		for i in offs.size():
			if offs[i] <= limit:
				return i
		return -1

	## 最后一帧「正在走」的下标（-1 = 一次都没走）
	func last_walking_index() -> int:
		var out := -1
		for i in walking.size():
			if walking[i]:
				out = i
		return out

	## 纵向偏移第一次**开始变小**的下标：简历离开站定处的那一刹那
	func first_offset_decrease() -> int:
		for i in range(1, offs.size()):
			if offs[i] < offs[i - 1] - 0.001:
				return i
		return -1

	## x 第一次**开始变大**的下标：下一位从画面右边起步的那一刹那
	func first_x_increase() -> int:
		for i in range(1, xs.size()):
			if xs[i] > xs[i - 1] + 0.001:
				return i
		return -1

	## 最后一帧**还在横向移动**的下标：立绘真正站住的那一帧
	##
	## 用位置来判断「站定了没有」，而不是问 Interviewee.is_walking()：
	## 那个判据底下是 Tween 的 is_running()，而 Tween 跑完之后还会再报几帧 running
	## （它问的是「还在不在跑」，不是「动作做完了没有」）。位置不会骗人。
	func last_x_decrease() -> int:
		var out := -1
		for i in range(1, xs.size()):
			if xs[i] < xs[i - 1] - 0.001:
				out = i
		return out


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


## 等某个条件成立（按**真实时间**超时）
func _wait_until(predicate: Callable, timeout_ms: int = SEQUENCE_TIMEOUT_MS) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return bool(predicate.call())


## 一直采样到演出结束为止
##
## 循环退出时**再补一帧**：退出条件（is_animating 变假）是在总闸那一帧里设的，
## 补的这一帧就是收场之后的姿态 —— 不补的话，最后一帧永远落在采样窗口外面。
func _record_until_idle(interview: Node, interviewee: Interviewee,
		resume: Resume, track: Track) -> bool:
	var deadline := Time.get_ticks_msec() + SEQUENCE_TIMEOUT_MS
	while interview.is_animating() and Time.get_ticks_msec() < deadline:
		track.xs.append(interviewee.position.x)
		track.ys.append(interviewee.position.y)
		track.offs.append(resume.slide_offset())
		track.walking.append(interviewee.is_walking())
		await get_tree().process_frame
	await get_tree().process_frame
	track.xs.append(interviewee.position.x)
	track.ys.append(interviewee.position.y)
	track.offs.append(resume.slide_offset())
	track.walking.append(interviewee.is_walking())
	return not interview.is_animating()


func _run() -> void:
	# 演出是按真实时间跑的，调快一点省掉等待；收尾会拨回去
	Engine.time_scale = TIME_SCALE

	var vp := _make_canvas()

	# 数据全部来自 data/：开一局 → 当日名单 → 面试场景照着它铺
	GameState.start_new_run(20261012)
	GameState.set_phase(DayPhase.Phase.INTERVIEW)

	var list := GameState.current_candidates
	_check(list.size() >= 2, "第 %d 天名单里至少 2 位候选人（实际 %d）" % [
		GameState.get_day(), list.size()])
	if list.size() < 2:
		return

	var interview := INTERVIEW_SCENE.instantiate()
	vp.add_child(interview)

	var interviewee: Interviewee = interview.get_node_or_null("Interviewee")
	var resume: Resume = interview.get_node_or_null("Resume")
	var approved: TextureButton = interview.get_node_or_null("Approved")
	var nah: TextureButton = interview.get_node_or_null("Nah")
	_check(interviewee != null, "面试场景里有 Interviewee")
	_check(resume != null, "面试场景里有 Resume")
	_check(approved != null and nah != null, "面试场景里有录用 / 拒绝按钮")
	if interviewee == null or resume == null or approved == null or nah == null:
		return

	var rest := interviewee.rest_position()
	var travel := resume.travel_distance()
	var left_out := interviewee.offscreen_left_x()
	var right_out := interviewee.offscreen_right_x()

	# 简历「完全离开画面」到底要滑多远，由**纸面本身**的位置决定，不是由画布高度决定：
	# 纸只占 62..542，行程 648 是个保守值（留了余量，换画布尺寸也不会露馅）。
	var paper: Control = resume.get_node("Paper")
	var paper_top := paper.position.y
	var paper_bottom := paper.position.y + paper.size.y
	var below_out := float(GAME_CANVAS.y) - paper_top   # 纸的顶边被推到画面底边之下
	var above_out := -paper_bottom                      # 纸的底边被推到画面顶边之上
	print("[smoke_interview_animation] 站定处 %s；左右画面外 %s / %s；简历行程 %.0f；纸面 %.0f..%.0f" % [
		rest, left_out, right_out, travel, paper_top, paper_bottom])

	# ---- 0. 出口就在画面外面：走进来 / 走出去的起止点必须真的离开画面 ----
	_check(right_out - interviewee.portrait_half_width() >= float(GAME_CANVAS.x),
			"画面右边外面的起点真的在画面外（立绘左缘 %.0f ≥ 画布宽 %d）" % [
				right_out - interviewee.portrait_half_width(), GAME_CANVAS.x])
	_check(left_out + interviewee.portrait_half_width() <= 0.0,
			"画面左边外面的终点真的在画面外（立绘右缘 %.0f ≤ 0）" % [
				left_out + interviewee.portrait_half_width()])
	_check(travel >= below_out and travel >= -above_out,
			"简历的行程够把纸面整个推出画面（往下要 %.0f、往上要 %.0f，实际 %.0f）" % [
				below_out, -above_out, travel])

	# ---- 1. 挂上去那一帧：摆位是同步做完的，纸上不会先闪一下 ----
	_check(interview.is_animating(), "进入招人阶段就开始演出")
	_check(absf(resume.slide_offset() - travel) < 0.001,
			"简历**当场**被摆到画面下方等着（偏移 %.0f）" % resume.slide_offset())
	_check(absf(interviewee.position.x - right_out) < 0.001,
			"立绘**当场**被摆到画面右边外面（x %.0f）" % interviewee.position.x)
	_check(not approved.visible and not nah.visible,
			"演出期间判定按钮不画出来（UI 层守卫）")

	# 演出期间不受理判定：按钮藏着是第 1 道，_judge() 里的 _animating 是第 2 道。
	# 这里按钮本来就是藏着的，所以直接发信号，走的就是第 2 道。
	approved.pressed.emit()
	await get_tree().process_frame
	_check(GameState.get_passed_ids().is_empty(),
			"演出期间发来的判定被忽略（录用名单仍为空）")

	# ---- 2. 出场：走进来 → 站定 → 简历升起 ----
	var enter := Track.new()
	var enter_done := await _record_until_idle(interview, interviewee, resume, enter)
	_check(enter_done, "出场演出自己走完了（没有卡住）")
	_check(enter.size() > 0, "出场演出采到了 %d 帧" % enter.size())
	if enter.size() == 0 or not enter_done:
		return

	# 走路：全程在走，而且确实在上下晃
	var walking_frames := 0
	for flag in enter.walking:
		if flag:
			walking_frames += 1
	_check(walking_frames > 0, "立绘确实走了（走路中 %d 帧 / 共 %d 帧）" % [
		walking_frames, enter.size()])
	var bob := enter.max_bob(rest.y)
	_check(bob > 1.0, "走动时在上下晃（最大纵向偏移 %.1f px）" % bob)
	_check(bob <= Interviewee.WALK_BOB_PIXELS + 0.5,
			"晃动幅度就是配置的那个（%.1f ≤ %.1f）" % [bob, Interviewee.WALK_BOB_PIXELS])

	# 晃动的**中心**始终是站定高度：上下都晃到了，而且哪一边都不越过配置的振幅。
	# （不是「一边轻轻推一下」那种位移 —— 那样看着不像走路。）
	var highest := INF
	var lowest := -INF
	for v in enter.ys:
		highest = minf(highest, v)
		lowest = maxf(lowest, v)
	_check(highest < rest.y - 1.0 and lowest > rest.y + 1.0,
			"上下都晃到了（最高 %.1f / 站定 %.1f / 最低 %.1f）" % [highest, rest.y, lowest])
	_check(rest.y - highest <= Interviewee.WALK_BOB_PIXELS + 0.5
			and lowest - rest.y <= Interviewee.WALK_BOB_PIXELS + 0.5,
			"上下晃动都不越过配置的振幅（%.1f px）" % Interviewee.WALK_BOB_PIXELS)

	# 从右往左走：x 单调不增，起点在右边外面，全程不越过站定处
	var monotonic := true
	for i in range(1, enter.xs.size()):
		if enter.xs[i] > enter.xs[i - 1] + 0.001:
			monotonic = false
	_check(monotonic, "出场是**单向**从右往左平移，没有来回弹")
	_check(enter.xs[0] > rest.x, "起步时在站定处的右边（x %.0f > %.0f）" % [
		enter.xs[0], rest.x])
	_check(enter.min_x() >= rest.x - 1.0,
			"走到站定处就停住，没有走过头（最小 x %.0f）" % enter.min_x())

	# 简历：全程只在站定处或**下方**（没往上跑过），最后升到位
	_check(enter.max_offset() <= travel + 0.001 and enter.min_offset() >= -0.001,
			"出场时简历只在画面下方（偏移 %.0f..%.0f）" % [
				enter.min_offset(), enter.max_offset()])
	_check(absf(enter.offs[enter.size() - 1]) < 0.001,
			"出场结束时简历正好升到站定处（偏移 %.3f）" % enter.offs[enter.size() - 1])

	# 「站定**之后**」才升起：简历开始上升的那一帧，横向必须已经不再动了
	var rise_at := enter.first_offset_decrease()
	var walked_until := enter.last_x_decrease()
	_check(rise_at > 0 and walked_until >= 0,
			"两个时机都找得到（简历开始升第 %d 帧 / 立绘最后动第 %d 帧）" % [rise_at, walked_until])
	_check(rise_at > walked_until,
			"简历是在立绘**站定之后**才升起的（升起第 %d 帧 > 走完第 %d 帧）" % [
				rise_at, walked_until])
	if rise_at > 0 and walked_until >= 0 and rise_at <= walked_until:
		print("      · 第 %d..%d 帧：x=%s" % [
			maxi(0, rise_at - 6), mini(enter.size() - 1, rise_at + 4),
			str(enter.xs.slice(maxi(0, rise_at - 6), mini(enter.size(), rise_at + 5)))])
		print("      · 第 %d..%d 帧：走路标记=%s" % [
			maxi(0, rise_at - 6), mini(enter.size() - 1, rise_at + 4),
			str(enter.walking.slice(maxi(0, rise_at - 6), mini(enter.size(), rise_at + 5)))])

	# 站定姿态：横向回到场景里摆的那一处，纵向回到站定高度
	_check(absf(interviewee.position.x - rest.x) < 0.001
			and absf(interviewee.position.y - rest.y) < 0.001,
			"出场结束后立绘正好站在场景摆的那一处（%s）" % interviewee.position)
	_check(absf(resume.slide_offset()) < 0.001, "出场结束后简历正好回到站定处")
	_check(resume.get_candidate() == list[0], "出场后简历上铺的是名单第 1 位")
	_check(approved.visible and nah.visible, "演出结束后判定按钮重新出现")

	# ---- 3. 判定第一位：走出去 → 简历移走 → 下一位走进来 ----
	var advanced: Array[int] = []
	interview.phase_finished.connect(func() -> void: advanced.append(1))

	approved.pressed.emit()
	_check(interview.is_animating(), "按下录用 → 开始演判定之后的这一段")
	_check(GameState.get_passed_ids().has(list[0].id), "第 1 位进了录用名单")
	_check(not approved.visible, "判定演出期间按钮又不画了")

	var swap := Track.new()
	var swap_done := await _record_until_idle(interview, interviewee, resume, swap)
	_check(swap_done, "换人演出自己走完了（没有卡住）")
	_check(swap.size() > 0, "换人演出采到了 %d 帧" % swap.size())
	if swap.size() == 0 or not swap_done:
		return

	# 面试者向左一直走出画面
	_check(swap.min_x() <= left_out + 1.0,
			"面试者向左走出了画面（最小 x %.0f ≤ %.0f）" % [swap.min_x(), left_out + 1.0])
	# 简历往上方一直移出画面
	_check(swap.min_offset() <= above_out + 1.0,
			"他的简历往上方移出了画面（最小偏移 %.0f ≤ %.0f）" % [
				swap.min_offset(), above_out + 1.0])

	# 顺序：**人先走光，纸才往上升**
	var man_out := swap.first_x_at_most(left_out + 1.0)
	var paper_out := swap.first_offset_at_most(above_out + 1.0)
	_check(man_out >= 0 and paper_out >= 0,
			"两个「移出画面」的时机都找得到（人第 %d 帧 / 纸第 %d 帧）" % [man_out, paper_out])
	_check(man_out < paper_out,
			"顺序对：面试者先走光（第 %d 帧），然后简历才往上移走（第 %d 帧）" % [
				man_out, paper_out])

	# 下一位的简历是从**下方**来的：纸最后是从 +行程 一路降到 0
	var after_out := paper_out
	var tail_max := -INF
	for i in range(after_out, swap.offs.size()):
		tail_max = maxf(tail_max, swap.offs[i])
	_check(tail_max >= travel - 1.0,
			"下一位的简历重新出现在画面**下方**（尾部最大偏移 %.0f）" % tail_max)
	_check(absf(swap.offs[swap.size() - 1]) < 0.001,
			"下一位的简历最终升到站定处（偏移 %.3f）" % swap.offs[swap.size() - 1])

	# 顺序：纸移走之后，下一位才从右边走进来
	var walk_back := swap.first_x_increase()
	_check(walk_back > paper_out,
			"顺序对：简历移走（第 %d 帧）之后，下一位才从右边走进来（第 %d 帧）" % [
				paper_out, walk_back])

	# 换人换干净了：立绘与简历都是名单第 2 位
	_check(resume.get_candidate() == list[1],
			"简历换成了名单第 2 位（%s）" % list[1].id)
	_check(absf(interviewee.position.x - rest.x) < 0.001
			and absf(interviewee.position.y - rest.y) < 0.001,
			"第 2 位也站在站定那一处（%s）" % interviewee.position)
	_check(absf(resume.slide_offset()) < 0.001, "第 2 位的简历也升到位了")
	_check(approved.visible, "换人演出结束后判定按钮又出现了")
	_check(advanced.is_empty(), "换人演出没有推进阶段（还有人在等着面试）")

	# ---- 4. 剩下的几位：判定 → 跳过演出（顺带验跳过后的收场姿态）----
	for i in range(1, list.size() - 1):
		approved.pressed.emit()
		_check(interview.is_animating(), "判定第 %d 位 → 开始演出" % (i + 1))
		interview.skip_animation()
		await _settle()
		_check(not interview.is_animating(), "跳过后演出立即结束")
		_check(resume.get_candidate() == list[i + 1],
				"跳过后场上就是名单第 %d 位（%s）" % [i + 2, list[i + 1].id])
		_check(absf(resume.slide_offset()) < 0.001
				and absf(interviewee.position.x - rest.x) < 0.001,
				"跳过后立绘与简历都收在站定姿态")
		_check(approved.visible, "跳过后判定按钮可用")

	# ---- 5. 最后一位：演出走完之后才交阶段 ----
	var last_index := list.size() - 1
	approved.pressed.emit()
	_check(interview.is_animating(), "判定最后一位 → 开始演出")
	await get_tree().process_frame
	_check(advanced.is_empty(), "最后一位的演出还在演，阶段没有被提前推走")

	interview.skip_animation()
	await _settle()
	_check(not advanced.is_empty(), "演出收场之后才发 phase_finished（推进阶段）")
	_check(absf(interviewee.position.x - left_out) < 0.001,
			"收场时面试者停在画面左边外面（x %.0f）" % interviewee.position.x)
	_check(absf(resume.slide_offset() + travel) < 0.001,
			"收场时简历停在画面上方外面（偏移 %.0f）" % resume.slide_offset())
	_check(GameState.get_passed_ids().has(list[last_index].id),
			"最后一位也记进了录用名单")

	# ---- 6. 收尾：把时间拨回去 ----
	Engine.time_scale = 1.0


func _report() -> void:
	Engine.time_scale = 1.0
	print("")
	if _failures.is_empty():
		print("[smoke_interview_animation] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_interview_animation] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
