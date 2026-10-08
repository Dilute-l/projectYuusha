extends Control

## interview.tscn 承载四个阶段（ARCHITECTURE.md §4）：
##   DAY_BRIEFING   国王下旨
##   SPECIAL_EVENT  记者报道今日魔物 / 特殊规则
##   SCREENING      浏览简历
##   INTERVIEW      追问面试
##
## 它们共用一个场景实例：day_loop 在同一个 scene_key 下不会重建本场景，
## 只调 set_phase() 把新阶段告诉它。所以「阶段 → 显示」的切换全部落在
## _apply_phase_visuals() 里。
##
## 本脚本**不负责推进流程**：它只发 `phase_finished` 报告「我这个阶段做完了」，
## 下一步是换阶段 / 换天 / 进结局由 day_loop 问 DayDirector 决定。
##
## 面试者从哪来：**当天出场名单**（data/days/day_XX.tres）里的第 finished_interviewee 位，
## 由 GameState.current_candidates 提供。本脚本一句候选人文案都不写死 ——
## 立绘配方和简历内容分别落在 data/candidates/*.tres 的 portrait_* 字段与 resume 数组里。

## 当前阶段（DayPhase.Phase）
var _phase: int = DayPhase.Phase.DAY_BRIEFING

@onready var _resume: Resume = get_node_or_null("Resume") as Resume
@onready var _approved: TextureButton = get_node_or_null("Approved") as TextureButton
@onready var _nah: TextureButton = get_node_or_null("Nah") as TextureButton

## 本阶段做完了。day_loop 挂载本场景时会把它接到 advance() 上。
signal phase_finished()

## 本日已判定的候选人数（同时用作「当前看的是第几位」的下标）
var finished_interviewee: int = 0

## 当前是否真的有候选人可展示（没有名单时立绘不出场）
var _has_interviewee: bool = false


func _ready() -> void:
	# 当日名单是「本日过程量」，开局 / 换天时由 GameState 从 data/days/ 载入。
	# 单独 F6 跑本场景时没人做过这件事，这里补一次。
	if GameState.current_candidates.is_empty():
		GameState.load_day_candidates()

	# 由 day_loop **首次实例化**本场景时走的是「新建实例」那条路，不会调 set_phase()，
	# 所以这里自己按 GameState 里的当前阶段初始化一次。
	# （单独 F6 运行本场景时，这一行同样让它直接落到正确的阶段。）
	_refresh_interviewee()
	set_phase(GameState.get_phase())


# ---------------------------------------------------------------------------
# 阶段（由 day_loop 驱动）
# ---------------------------------------------------------------------------


## 由 day_loop 在共用本场景的几个阶段之间切换时调用
func set_phase(phase: int) -> void:
	_phase = phase
	# 进入追问环节 = 新一轮判定，计数归零。
	# 注意：等实现 §4 的「Screening ⇄ Interview 来回切换」后，这里会把已判定的进度丢掉；
	# 届时把复位挪到「进入整轮招人」（SCREENING），或者干脆改成「已判定集合」。
	if phase == DayPhase.Phase.INTERVIEW:
		finished_interviewee = 0
		_refresh_interviewee()
	_apply_phase_visuals()


## 当前阶段
func get_phase() -> int:
	return _phase


## 追问环节才允许做录用判定（§4：其余阶段不该出现这个操作）
func _is_judging_allowed() -> bool:
	return _phase == DayPhase.Phase.INTERVIEW


## 阶段 → 显示。
##
## 目前实现两条：
##   1. 简历页只在招人阶段出现
##   2. 录用判定按钮只在追问环节出现
## 国王下旨 / 今日事件的正式界面属于 M1〜M2 的内容，做的时候在这里按 _phase 切换即可
## （需要通知子控件时，也可以从这里发信号，而不是让子控件自己去读 GameState）。
func _apply_phase_visuals() -> void:
	if _resume != null:
		_resume.visible = DayPhase.is_recruiting(_phase)

	# 阶段 1（国王下旨）与阶段 2（今日事件）是开场播报，面试者不在场 —— 藏起来。
	#
	# 写成「不在这些阶段」而不是「只在招人阶段」：以后往招人流程里插新阶段时，
	# 面试者默认仍可见，不会莫名消失。
	#
	# 用 get_node_or_null 现查而不是 @onready 缓存：方便场景里换节点名。
	var interviewee := get_node_or_null("Interviewee") as Control
	if interviewee != null:
		interviewee.visible = _has_interviewee and (
			_phase != DayPhase.Phase.DAY_BRIEFING
			and _phase != DayPhase.Phase.SPECIAL_EVENT
		)

	# 第 1 层守卫（UI 层）：隐藏的 Control 收不到鼠标输入，也不会被焦点导航选中，
	# 所以这一层就挡住了绝大多数误操作。逻辑层的守卫见 _judge()。
	var judging := _is_judging_allowed()
	if _approved != null:
		_approved.visible = judging
	if _nah != null:
		_nah.visible = judging


# ---------------------------------------------------------------------------
# 当前面试者（数据全部来自 data/candidates/*.tres）
# ---------------------------------------------------------------------------


## 正在面试的那一位：当日名单里的第 finished_interviewee 位；名单里没有就返回 null。
func current_candidate() -> CandidateResource:
	var list := GameState.current_candidates
	if finished_interviewee < 0 or finished_interviewee >= list.size():
		return null
	return list[finished_interviewee]


## 把当前候选人铺到立绘和简历上。换人（判定完一位）后由 _judge() 再调一次。
func _refresh_interviewee() -> void:
	var candidate := current_candidate()
	_has_interviewee = candidate != null

	var interviewee := get_node_or_null("Interviewee") as Interviewee
	if interviewee != null and candidate != null:
		# 立绘配方（种族 + 各部件差分）写在候选人自己身上，不在代码里随机摇
		interviewee.apply_candidate(candidate)

	if _resume != null:
		_resume.set_candidate(candidate)


# ---------------------------------------------------------------------------
# 录用判定
# ---------------------------------------------------------------------------


## 当日候选人总数。
## 优先用 data/days 的 DayConfig；还没有数据时回退到实际候选人列表；
## 两者都空则返回 1 —— 让空流程点一下就能过，方便走通十天。
func _candidate_total() -> int:
	var cfg := DataDB.get_day_config(GameState.get_day())
	if cfg != null and cfg.candidates.size() > 0:
		return cfg.candidates.size()
	var actual := GameState.current_candidates.size()
	return actual if actual > 0 else 1


func _on_approved_pressed() -> void:
	_judge(true)


func _on_nah_pressed() -> void:
	_judge(false)


## 录用 / 拒绝的唯一入口。
## 两个按钮只是 passed 不同，判定与计数逻辑只写一份 —— 顺手修掉原来「两个按钮行为完全相同」的问题。
func _judge(passed: bool) -> void:
	# 第 2 层守卫（逻辑层）：不在追问环节就不接受判定。
	# 走到这里说明有别的代码在乱调、或者场景接线出了问题 —— 要响，不要吞。
	if not _is_judging_allowed():
		push_warning("[Interview] 阶段 %s 不接受录用判定，已忽略" % DayPhase.to_name(_phase))
		return

	var candidate := current_candidate()
	if candidate != null:
		GameState.issue_verdict(candidate.id, passed)
	else:
		# 名单里没有这一位：可能是当天数据还没填，也可能已经判定完了一轮
		print("[Interview] 当日名单里没有第 %d 位候选人，本次判定只计数" % finished_interviewee)

	finished_interviewee += 1
	# 用 >= 而不是 ==：多算一次也还能收口，不会永远不触发
	if finished_interviewee >= _candidate_total():
		finished_interviewee = 0
		_refresh_interviewee()
		phase_finished.emit()
		return
	# 换下一位：立绘与简历一起翻页
	_refresh_interviewee()


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------


func _on_notice_board_pressed() -> void:
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[Interview] 找不到 Dialoguer")
		return
	if not dialoguer.typer.load_dialogue("Boardery"):
		return
	dialoguer.play()
