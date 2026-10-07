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

## 当前阶段（DayPhase.Phase）
var _phase: int = DayPhase.Phase.DAY_BRIEFING

@onready var _resume: Control = get_node_or_null("Resume") as Control
@onready var _approved: TextureButton = get_node_or_null("Approved") as TextureButton
@onready var _nah: TextureButton = get_node_or_null("Nah") as TextureButton

## 本阶段做完了。day_loop 挂载本场景时会把它接到 advance() 上。
signal phase_finished()

## 本日已判定的候选人数（同时用作「当前看的是第几位」的下标）
var finished_interviewee: int = 0

# ===========================================================================
# ⚠️ 临时调试代码 —— 只为肉眼检查立绘部件组合，不参与任何玩法逻辑。
#
# 接入正式候选人生成器（scripts/core/generation/candidate_generator.gd）后，
# 把 _ready() 里那一行调用和 _debug_randomize_interviewee() 整段删掉即可。
# ===========================================================================

const INTERVIEWEE_SCENE := preload("res://scenes/day/interview/interviewee.tscn")

## 可用种族，对应 assets/art/portrait/ 里的文件名前缀
const RACES: Array[StringName] = [&"hu", &"el", &"st"]

## 部位编号范围，对应 *_phd1..3 三个文件
const PART_MIN := 1
const PART_MAX := 3


func _ready() -> void:
	# 先确保 Interviewee 存在（临时调试段可能会现场生成一个），再按阶段设显示 ——
	# 否则「场景里没有 Interviewee、由代码生成」这条路上，阶段 1/2 就不会被隐藏。
	_debug_randomize_interviewee()

	# 由 day_loop **首次实例化**本场景时走的是「新建实例」那条路，不会调 set_phase()，
	# 所以这里自己按 GameState 里的当前阶段初始化一次。
	# （单独 F6 运行本场景时，这一行同样让它直接落到正确的阶段。）
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
	# 用 get_node_or_null 现查而不是 @onready 缓存：临时调试段可能现场生成一个 Interviewee。
	var interviewee := get_node_or_null("Interviewee") as Control
	if interviewee != null:
		interviewee.visible = (
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
# 录用判定
# ---------------------------------------------------------------------------


## 当日候选人总数。
## 优先用 data/days 的 DayConfig；还没有数据时回退到实际候选人列表；
## 两者都空则返回 1 —— 让 M0 的空流程点一下就能过，方便走通十天。
func _candidate_total() -> int:
	var cfg = DataDB.get_day_config(GameState.get_day())
	if cfg != null and int(cfg.candidate_count) > 0:
		return int(cfg.candidate_count)
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

	var index := finished_interviewee
	if index < GameState.current_candidates.size():
		var candidate: CandidateResource = GameState.current_candidates[index]
		GameState.issue_verdict(candidate.id, passed)
	else:
		# 候选人生成器还没接上 —— 这是 M0 的预期状态，用 print 而不是 warning
		print("[Interview] 尚无候选人数据（index=%d），本次判定只计数" % index)

	finished_interviewee += 1
	# 用 >= 而不是 ==：多算一次也还能收口，不会永远不触发
	if finished_interviewee >= _candidate_total():
		finished_interviewee = 0
		phase_finished.emit()


# ---------------------------------------------------------------------------
# ⚠️ 临时调试（整段可删）
# ---------------------------------------------------------------------------


func _debug_randomize_interviewee() -> void:
	# 场景里已经有 Interviewee 就直接用；没有就拉一个出来
	var iv := get_node_or_null("Interviewee") as Interviewee
	var spawned := false
	if iv == null:
		iv = INTERVIEWEE_SCENE.instantiate() as Interviewee
		iv.name = "Interviewee"
		spawned = true

	# 随机走 RngService（项目的唯一随机源，纪律见 autoload/rng_service.gd）。
	# 流名带 ticks 是为了「每次进场景都换一套」——纯调试目的。
	# 这里并没有新增随机源，只是向 RngService 要了一条新流。
	# 想改成「同种子复现同一套」就把流名换成固定的 &"debug:portrait"。
	var s := StringName("debug:portrait:%d" % Time.get_ticks_msec())

	iv.race = StringName(RngService.pick(s, RACES))
	iv.eye = RngService.randi_in(s, PART_MIN, PART_MAX)
	iv.hair = RngService.randi_in(s, PART_MIN, PART_MAX)
	iv.mouth = RngService.randi_in(s, PART_MIN, PART_MAX)
	iv.hat = RngService.randi_in(s, PART_MIN, PART_MAX)

	if spawned:
		# 先填数据再入树：_ready() 里那次 apply() 就已经是正确的一套，不会白跑
		add_child(iv)
	else:
		# 场景里已有的实例，_ready() 早就跑过了，得手动重刷
		iv.apply()

	print("[Interview][debug] 随机面试者 race=%s eye=%d hair=%d mouth=%d hat=%d" % [
		iv.race, iv.eye, iv.hair, iv.mouth, iv.hat])


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
