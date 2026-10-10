extends Control

## interview.tscn 承载三个阶段（ARCHITECTURE.md §4）：
##   DAY_BRIEFING   国王下旨
##   SPECIAL_EVENT  记者报道今日魔物 / 特殊规则
##   INTERVIEW      招人：看简历、追问面试、录用判定
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
##
## 一位面试者的**出场 / 退场演出**（走进来、简历升起、走出去、简历移走）也归本脚本调度，
## 见下面「出场演出」一节与 ARCHITECTURE.md §13。

## 当前阶段（DayPhase.Phase）
var _phase: int = DayPhase.Phase.DAY_BRIEFING

@onready var _resume: Resume = get_node_or_null("Resume") as Resume
@onready var _interviewee: Interviewee = get_node_or_null("Interviewee") as Interviewee
@onready var _approved: TextureButton = get_node_or_null("Approved") as TextureButton
@onready var _nah: TextureButton = get_node_or_null("Nah") as TextureButton
@onready var _dialoguer: Dialoguer = get_node_or_null("Dialoguer") as Dialoguer
@onready var _handbook: Handbook = get_node_or_null("Handbook") as Handbook
@onready var _notice_board: TextureButton = get_node_or_null("NoticeBoard") as TextureButton

## 本阶段做完了。day_loop 挂载本场景时会把它接到 advance() 上。
signal phase_finished()

## 本日已判定的候选人数（同时用作「当前看的是第几位」的下标）
var finished_interviewee: int = 0

## 当前是否真的有候选人可展示（没有名单时立绘不出场）
var _has_interviewee: bool = false

## 上一次真正「进入」的阶段。-1 = 本实例还没进入过任何阶段。
##
## 为什么需要它：set_phase() 在挂载那一次会被调用两遍 —— _ready() 里的自初始化一次、
## day_loop 通过 EventBus.day_phase_entered 再一次；同一个实例切阶段时也会被通知两遍
## （day_loop 的直接调用 + 信号）。所以**一次性的进入动作**（播对话、重置计数）
## 必须挂在「阶段真的变了」上，否则对话会重播、计数会翻倍，而且一声不响。
var _last_entered_phase: int = -1


func _ready() -> void:
	# 当日名单是「本日过程量」，开局 / 换天时由 GameState 从 data/days/ 载入。
	# 单独 F6 跑本场景时没人做过这件事，这里补一次。
	if GameState.current_candidates.is_empty():
		GameState.load_day_candidates()

	# 接上「进入阶段」通知。is_connected 守卫是防重复连接（同一个 信号+回调 连两次会报错）。
	if not EventBus.day_phase_entered.is_connected(set_phase):
		EventBus.day_phase_entered.connect(set_phase)

	# 接上「玩家追问了简历某一条」（resume.gd 广播，见 _on_resume_entry_asked）。
	if not EventBus.resume_entry_asked.is_connected(_on_resume_entry_asked):
		EventBus.resume_entry_asked.connect(_on_resume_entry_asked)

	# 手册关掉时要把本场景别的操作放开（见 _set_scene_interaction_enabled）
	if _handbook != null and not _handbook.closed.is_connected(_on_handbook_closed):
		_handbook.closed.connect(_on_handbook_closed)

	# 由 day_loop **首次实例化**本场景时走的是「新建实例」那条路，不会调 set_phase()，
	# 所以这里自己按 GameState 里的当前阶段初始化一次。
	# （单独 F6 运行本场景时，这一行同样让它直接落到正确的阶段。）
	_refresh_interviewee()
	set_phase(GameState.get_phase())


# ---------------------------------------------------------------------------
# 阶段（由 day_loop 驱动）
# ---------------------------------------------------------------------------


## 进入某个阶段时被调用（day_loop 的直接调用与 EventBus.day_phase_entered 都会到这儿）。
##
## 分两段：**一次性动作**只在新阶段进入时做一遍；**显示刷新**每次都做（幂等）。
func set_phase(phase: int) -> void:
	var entered := phase != _last_entered_phase
	_last_entered_phase = phase
	_phase = phase

	if entered:
		# 每次进入新阶段都先撤销「对话结束就推进」的标记。
		# 有些阶段（如 INTERVIEW）根本不播阶段对话，
		# 留着上一阶段留下的 true，会让**下一段临时对话**（如提示板）播完时误推进。
		_advance_when_dialogue_ends = false

		match phase:
			DayPhase.Phase.DAY_BRIEFING:
				# 对话 id 的命名约定见 data/dialogue.json：day1_briefing（**不补零**）
				_play_phase_dialogue([
					"day%d_briefing" % GameState.get_day(),
					"day-1_briefing",
				])
			DayPhase.Phase.SPECIAL_EVENT:
				_play_phase_dialogue([
					"day%d_spevent" % GameState.get_day(),
					"day-1_spevent",
				])
			DayPhase.Phase.INTERVIEW:
				# 进入追问 = 新一轮判定，计数归零。
				finished_interviewee = 0
				_refresh_interviewee()
				# 第一位面试者从画面右边走进来，站定之后简历才从下方升起（§13）
				_play_enter_sequence()

	_apply_phase_visuals()


## 当前阶段
func get_phase() -> int:
	return _phase


## 追问环节才允许做录用判定（§4：其余阶段不该出现这个操作）。
##
## 手册开着时**一律不允许** —— 那是「在看手册」的模态状态，别的操作都该停手。
func _is_judging_allowed() -> bool:
	if is_handbook_open():
		return false
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
	if _interviewee != null:
		_interviewee.visible = _has_interviewee and (
			_phase != DayPhase.Phase.DAY_BRIEFING
			and _phase != DayPhase.Phase.SPECIAL_EVENT
		)

	# 第 1 层守卫（UI 层）：隐藏的 Control 收不到鼠标输入，也不会被焦点导航选中，
	# 所以这一层就挡住了绝大多数误操作。逻辑层的守卫见 _judge()。
	#
	# 演出期间也算「不许判定」：立绘还在往画面里走的时候不该能按下录用按钮
	# （按了也没用，见 _judge 的 _animating 守卫 —— 但按钮消失更直观）。
	var judging := _is_judging_allowed() and not _animating
	if _approved != null:
		_approved.visible = judging
	if _nah != null:
		_nah.visible = judging


# ---------------------------------------------------------------------------
# 追问（简历条目 → 对话框）
# ---------------------------------------------------------------------------


## 玩家在简历上点了某一条的「追问」（§6.2 第 2 步）。
##
## 追问的台词**不在本脚本里，也不在候选人档案里** —— 档案上只留了一个路径
## （`ResumeEntry.ask_path`），正文写在那份**独立 json** 里，格式就是
## data/dialogue.json 里的一段对话：
##
##     [ { "speaker_name": "面试官", "text": "..." },
##       { "speaker_name": "棍木",   "text": "..." } ]
##
## 所以这里的调用方式与 main_menu.gd 播 JSON 对话**完全一致**，只是文件换成了
## 这一条自己的那份（`load_dialogue_from()`）：
##
##     typer.load_dialogue_from(path)  →  typer.load_dialogue(id)
##     dialoguer.play()                →  dialoguer.play()
##
## 之后的逐字显示、点一下推进、最后一句点一下收起，仍然全部由 Dialoguer / Typer 负责，
## 本脚本一行输入处理都不写。
func _on_resume_entry_asked(candidate_id: StringName, entry_index: int) -> void:
	# 第 1 层守卫（逻辑层）：只有追问环节能追问。简历在别的阶段本就是隐藏的，
	# 走到这里说明有别的代码在乱发信号 —— 要响，不要吞。
	if not _is_judging_allowed():
		push_warning("[Interview] 阶段 %s 不接受追问，已忽略" % DayPhase.to_name(_phase))
		return

	# 第 2 层守卫：阶段对话还没播完时**不要打断它**（同 _on_notice_board_pressed）。
	# 打断等于把阶段对话换掉，而它不会再播第二次 —— 那个阶段就失去了「看完自动推进」这条路径。
	if _advance_when_dialogue_ends:
		return

	# 第 3 层守卫：演出期间不受理追问。
	# 这时那张纸正在画面外／正在往上往下滑，点到的词条马上就会跟着纸一起跑掉，
	# 问出来的对话也就没根了。静默忽略 —— 这是玩家手快，不是接线错了。
	if _animating:
		return

	if _dialoguer == null:
		push_error("[Interview] 找不到 Dialoguer，无法播出追问")
		return

	# 只受理「正在面试的这一位」的追问：本信号是全局广播，台下可能站着别人
	var candidate := current_candidate()
	if candidate == null or candidate.id != candidate_id:
		push_warning("[Interview] 追问的候选人 %s 不是当前在面试的那位，已忽略" % candidate_id)
		return
	if entry_index < 0 or entry_index >= candidate.resume.size():
		push_warning("[Interview] 追问的条目下标越界：%d（共 %d 条）" % [
			entry_index, candidate.resume.size()])
		return
	var entry: ResumeEntry = candidate.resume[entry_index]
	if entry == null:
		push_warning("[Interview] 第 %d 条简历是空的，无法追问" % entry_index)
		return

	var ask_path: String = entry.ask_path.strip_edges()
	if ask_path.is_empty():
		push_warning("[Interview] 第 %d 条简历没写 ask_path，没有台词可播" % entry_index)
		return
	# 先自己确认文件在，再去 load：Typer 那层的报错是「JSON 读不出来」，
	# 而这里最常见的错因其实是路径写错 / 文件忘了提交，分开报更好排查。
	if not FileAccess.file_exists(ask_path):
		push_error("[Interview] 追问 json 不存在：%s（第 %d 条简历 ask_path 指错了？）" % [
			ask_path, entry_index])
		return

	# 一份 json = 一条追问的一段对话，所以 id 留空（取文件里的第一段）
	if not _dialoguer.typer.load_dialogue_from(ask_path):
		return
	# 播成功才算「问过」：组队阶段的「回忆」照这份记录判断哪几条能点
	# （阶段不对 / json 缺失都不该让那一条在组队时亮起来）。
	GameState.record_entry_asked(candidate.id, entry_index)
	_dialoguer.play()


# ---------------------------------------------------------------------------
# 阶段对话
# ---------------------------------------------------------------------------


## 本次播放的对话结束时，是否要推进阶段。
##
## 为什么需要它：Dialoguer 只有**一个** `dialogue_ended` 信号，**不区分是哪一段对话结束的**；
## 而连接一旦建立就会一直挂着。于是「点提示板顺手看一段」播完时，那个回调照样会跑到 ——
## 阶段就被推进了。
##
## 所以「要不要推进」必须是**每次播放时决定的状态**，不能靠「连接存不存在」来表达。
var _advance_when_dialogue_ends := false


## 播一段阶段对话，**等玩家看完再推进**。
##
## 为什么推进挂在 dialogue_ended 上，而不是 play() 之后立刻 emit：
##   1. play() 只是开始播，"立刻 emit"等于马上换阶段，对话根本看不到；
##   2. 挂载那一刻 day_loop 还没把 phase_finished 连上（它在 add_child 之后才连），
##      同步 emit 会被**静默丢掉** —— 这正是「第 1 天卡住不动」的成因。
## 对话结束是一次独立的点击事件，早已跳出 advance() 的调用链，这两个问题都不存在。
##
## ids 按优先级排，第一个能加载的胜出。全都加载不到就跳过播放、直接推进 ——
## 播放失败不该把整个流程锁死。
func _play_phase_dialogue(ids: Array[String]) -> void:
	if _dialoguer == null:
		push_error("[Interview] 找不到 Dialoguer，跳过对话直接推进")
		_defer_phase_finished()
		return

	var loaded := false
	for id in ids:
		if _dialoguer.typer.load_dialogue(id):
			loaded = true
			break
	if not loaded:
		# load_dialogue() 失败时自己已经 push_error 并列出现有 id 了，这里只补一句「所以跳过了」
		push_warning("[Interview] 这几段对话都不存在，跳过播放直接推进：%s" % str(ids))
		_defer_phase_finished()
		return

	_advance_when_dialogue_ends = true
	if not _dialoguer.dialogue_ended.is_connected(_on_dialogue_ended):
		_dialoguer.dialogue_ended.connect(_on_dialogue_ended)
	_dialoguer.play()


## **所有**对话结束时都会到这里（阶段对话、提示板、以后的任何临时对话）。
## 只有「结束时该推进」的那一段才真的推进 —— 见 _advance_when_dialogue_ends 的说明。
func _on_dialogue_ended() -> void:
	if not _advance_when_dialogue_ends:
		return
	_advance_when_dialogue_ends = false
	_defer_phase_finished()


## 延后一帧再发 phase_finished。
##
## 挂载那一刻（add_child → _ready() → set_phase()）day_loop 还没来得及 connect，
## 同步 emit 会静默丢掉；延后到帧末，连接就已经就绪了。
## 对话正常结束那条路虽然不依赖它，但统一走这里可以少一条容易踩的时序坑。
func _defer_phase_finished() -> void:
	_emit_phase_finished.call_deferred()


func _emit_phase_finished() -> void:
	phase_finished.emit()


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
# 出场演出（ARCHITECTURE.md §13）
# ---------------------------------------------------------------------------
#
# 一位面试者的完整戏份，按时间顺序：
#
#   从画面右边走进来（边走边上下晃）→ 站定 → 简历从画面下方升起
#     → ……玩家看简历、追问、按下录用 / 拒绝……
#   → 判定之后：向左走出去 → 他的简历往画面上方移走
#     → 下一位从右边走进来 → 下一位的简历从下方升起
#
# 做到「最后一位」时就停在「走出去 + 简历移走」，然后发 phase_finished 把阶段交出去。
#
# **演出用 Tween 串，不用协程 await**：
# day_loop 换阶段时会 queue_free() 掉本场景，而 `await` 一个已被释放的节点的信号
# 会让那个协程永远挂在那儿（不报错、不回收）。Tween 是绑在各自节点上的，
# 节点一没它自己就跟着没了，一个都不会漏。
#
# **顺序靠「等这一步动完」而不是「按固定时长往下排」**：见 _begin_sequence。
#
# 演出期间**不收任何输入**：判定按钮在 _apply_phase_visuals() 里藏起来（UI 层），
# _judge() 与 _on_resume_entry_asked() 再各挡一道（逻辑层）。

## 从画面右边外面走到站定处的时长
const WALK_IN_DURATION := 0.85

## 判定之后向左走出画面的时长
const WALK_OUT_DURATION := 0.65

## 简历从画面下方升到位的时长
const RESUME_IN_DURATION := 0.40

## 简历往画面上方移走的时长
const RESUME_OUT_DURATION := 0.30

## 正在演出吗（演出期间不收判定、不收追问、判定按钮也不画）
var _animating: bool = false

## 这一段演出收场时要做的事。
##
## ⚠️ **必须写成「把场面收成应该有的样子」，而不是「接着往下做」**：
## 它既会在演出自然播完时调用，也会在 skip_animation() 把演出掐掉时调用，
## 而掐掉的那一刻可能还停在任何一个中间步骤上 —— 所以它做的每一步都得是幂等的。
var _after_sequence: Callable = Callable()

## 这一段演出依次要做的动作（每一项返回一条 Tween，见「演出内部：一步一步的动作」）
var _steps: Array[Callable] = []

## 下一步在 _steps 里的下标
var _step_index: int = 0

## 当前这一步的动作；跑完就松手（null = 没有动作在跑）
var _step_tween: Tween = null


## 正在演出吗
func is_animating() -> bool:
	return _animating


## 立刻结束当前这段演出，直接落到「都站好了」的收场姿态。
##
## 给自检用：演出是按真实时间走的，测试没必要陪它等两秒。
## 也是玩家侧「点击跳过演出」的现成入口 —— 收场动作本身就是幂等的。
func skip_animation() -> void:
	if not _animating:
		return
	_finish_sequence()


## 第一位面试者的出场：走进来 → 站定 → 简历从下方升起。
##
## 摆位（把人放到画面右边外面、把纸放到画面下方）是**同步**做的，不塞进 Tween 的回调：
## 回调要等到下一帧才跑，而 _apply_phase_visuals() 会在本函数之后把两者显示出来 ——
## 中间空出来的那一帧，纸会停在原地明明白白地闪一下。
func _play_enter_sequence() -> void:
	if not _has_interviewee:
		# 当天名单是空的（M0 空流程）：没有人也没有纸可演。
		# 界面保持现状，玩家的判定按钮照常可用，流程不会因此卡住。
		return

	if _resume != null:
		_resume.snap_slide(_resume.travel_distance())
	if _interviewee != null:
		_interviewee.stand_at(_interviewee.offscreen_right_x())

	var steps: Array[Callable] = [_step_walk_in, _step_resume_rise]
	_begin_sequence(_stand_candidate_ready, steps)


## 判定之后的演出：这位走开 → 他的简历移走 → （还有下一位的话）下一位进来。
## is_last = 这是今天最后一位，走完就交阶段。
func _play_verdict_sequence(is_last: bool) -> void:
	if not _has_interviewee:
		# 没有人可演：直接按结果收口（空名单时 _candidate_total() 恒为 1，所以一定是最后一位）
		if is_last:
			_defer_phase_finished()
		return

	# 1) 面试者向左走开（和走进来是同一套走路：平移 + 上下晃动）
	# 2) 然后简历往画面上方移走
	var steps: Array[Callable] = [_step_walk_out, _step_resume_raise]
	if not is_last:
		# 3) 换下一位：此刻人与纸都在画面外，换立绘、换字都看不见 —— 正是换数据的时候。
		#    换完让他从右边走进来。
		# 4) 他站定之后，他的简历再从下方升起
		steps.append(_step_next_candidate_walk_in)
		steps.append(_step_resume_rise)

	_begin_sequence(_conclude_interview if is_last else _stand_candidate_ready, steps)


# ---- 演出内部：一步一步的动作 -------------------------------------------------
#
# 每一步是一个**返回 Tween 的函数**：返回的那条 Tween 跑完 = 这一步做完了。
# 返回 null 表示这一步没有动作可等（节点不在），调度会立刻往下走。
#
# 它们只负责「把谁从哪儿送到哪儿」，不负责收场 —— 收场统一在收口函数里
# （_stand_candidate_ready / _conclude_interview），这样跳过演出也不会留下半路姿态。


## 走进来：先把纸放到画面下方等着（这一位还在走的时候纸上不该有东西），再起步
func _step_walk_in() -> Tween:
	if _interviewee == null:
		return null
	if _resume != null:
		_resume.snap_slide(_resume.travel_distance())
	return _interviewee.walk_to(
		_interviewee.offscreen_right_x(),
		_interviewee.rest_position().x,
		WALK_IN_DURATION,
	)


## 换下一位之后走进来：先换数据、再把纸摆到下方，然后起步
##
## 换数据放在这一步（而不是上一步走完的那一刻）是有意的：
## 到这一步时人已经停在画面左边外面、纸停在画面上方外面，换脸换字都看不见。
func _step_next_candidate_walk_in() -> Tween:
	_refresh_interviewee()
	return _step_walk_in()


## 走出去：一直走到画面左边外面
func _step_walk_out() -> Tween:
	if _interviewee == null:
		return null
	return _interviewee.walk_to(
		_interviewee.rest_position().x,
		_interviewee.offscreen_left_x(),
		WALK_OUT_DURATION,
	)


## 简历从下方升起：从画面下方滑回站定的那一处
func _step_resume_rise() -> Tween:
	if _resume == null:
		return null
	return _resume.slide_to(0.0, RESUME_IN_DURATION)


## 简历往上方移走
func _step_resume_raise() -> Tween:
	if _resume == null:
		return null
	return _resume.slide_to(-_resume.travel_distance(), RESUME_OUT_DURATION)


# ---- 演出内部：收口 ----------------------------------------------------------


## 收场成「这一位正站在台前、简历摊开」。
##
## 换下一位之后、以及首次出场的演出自然播完时都走这里 —— 两种情况下它都是幂等的：
## 数据本来就是这一位的（重刷一遍不换人），位置本来也已经在站定处（回位不动）。
## 但**跳过演出**时它就不幂等了：那正是它存在的意义 —— 把半路的人拽回站定处、
## 把还没换的数据换成当前这一位的。
func _stand_candidate_ready() -> void:
	_refresh_interviewee()
	if _interviewee != null:
		_interviewee.stand_still()
	if _resume != null:
		_resume.stand_still()


## 收场成「今天面试完了」：这位停在画面左边外面、他的简历停在画面上方外面，
## 然后交阶段。
##
## 收场姿态要显式摆出来，而不是「反正马上就切场景了」：
## 跳过演出时可能才走到一半，不摆的话镜头会停在一个人站在画面正中的画面上。
func _conclude_interview() -> void:
	if _interviewee != null:
		_interviewee.stand_at(_interviewee.offscreen_left_x())
	if _resume != null:
		_resume.snap_slide(-_resume.travel_distance())
	_defer_phase_finished()


# ---- 演出内部：调度 ----------------------------------------------------------


## 开一段演出。after = 收场动作（见 _after_sequence），steps = 依次要做的动作。
##
## ⚠️ **演出是「等这一步动完再开下一步」，不是「按固定时长往下排」**：
## 排时长要求「总闸的 interval」与「子 Tween」两条独立 Tween 分毫不差，
## 而它们同一帧里谁先谁后本来就差一点点 —— 几步累积下来就成了
## 「人还在往左走，纸已经开始往上升了」。等子 Tween 自己的 finished 就没有这个偏差：
## 顺序就是动作本身的顺序，也就不需要任何「留一点余量」的魔法常量。
func _begin_sequence(after: Callable, steps: Array[Callable]) -> void:
	_animating = true
	_after_sequence = after
	_steps = steps
	_step_index = 0
	# 演出一开始就把判定按钮收起来（UI 层守卫），见 _apply_phase_visuals
	_apply_phase_visuals()
	_run_next_step()


## 跑下一步：启动它的动作，等**这条动作自己**跑完再接下下一步。
func _run_next_step() -> void:
	# 走到这里说明上一步的动画已经跑完（这里就是它的 finished 回调），
	# 所以先松手 —— 免得收场时去 kill 一条已经跑完的 Tween。
	_step_tween = null
	if not _animating:
		return
	if _step_index >= _steps.size():
		_finish_sequence()
		return

	var step: Callable = _steps[_step_index]
	_step_index += 1
	var tween: Tween = step.call()
	if tween == null or not tween.is_valid():
		# 这一步没有动作可等 → 立刻往下走。
		# 用 defer 而不是直接递归：连着几步都没动画时不至于把调用栈压深。
		_run_next_step.call_deferred()
		return
	_step_tween = tween
	_step_tween.finished.connect(_run_next_step, CONNECT_ONE_SHOT)


## 演出结束（自然播完或被跳过）后的唯一出口。
func _finish_sequence() -> void:
	if not _animating:
		return
	# 跳过演出时，这一步的动画可能才走到一半 —— 这里要把它掐掉，
	# 否则它会在收场之后继续往前跑，把刚摆好的姿态又推歪。
	# （kill() 不发 finished，所以不会把 _run_next_step 再叫起来。）
	if _step_tween != null and _step_tween.is_valid():
		_step_tween.kill()
	_step_tween = null
	_steps = []
	_step_index = 0

	_animating = false
	var after := _after_sequence
	_after_sequence = Callable()
	# 演出完了，判定按钮重新出现
	_apply_phase_visuals()
	if after.is_valid():
		after.call()


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
##
## 判定之后不立刻翻页，而是交给 _play_verdict_sequence() 演一段（§13）：
## 这位走出去 → 他的简历往上移走 → 下一位走进来 → 下一位的简历从下方升起。
func _judge(passed: bool) -> void:
	# 第 2 层守卫（逻辑层）：不在追问环节就不接受判定。
	# 走到这里说明有别的代码在乱调、或者场景接线出了问题 —— 要响，不要吞。
	if not _is_judging_allowed():
		push_warning("[Interview] 阶段 %s 不接受录用判定，已忽略" % DayPhase.to_name(_phase))
		return

	# 演出期间不接受第二次判定：按钮这时是藏着的，走到这里说明是代码在连点。
	# 静默忽略 —— 判定本身没错，只是来早了，不应该把它当成错误报出来。
	if _animating:
		return

	var candidate := current_candidate()
	if candidate != null:
		GameState.issue_verdict(candidate.id, passed)
	else:
		# 名单里没有这一位：可能是当天数据还没填，也可能已经判定完了一轮
		print("[Interview] 当日名单里没有第 %d 位候选人，本次判定只计数" % finished_interviewee)

	finished_interviewee += 1
	# 用 >= 而不是 ==：多算一次也还能收口，不会永远不触发
	var is_last := finished_interviewee >= _candidate_total()
	if is_last:
		finished_interviewee = 0
	# 换下一位：立绘与简历一起翻页 —— 翻页的动作在演出里（_play_verdict_sequence）
	_play_verdict_sequence(is_last)


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------


func _on_notice_board_pressed() -> void:
	if _dialoguer == null:
		push_error("[Interview] 找不到 Dialoguer")
		return
	# 手册开着时提示板也不给看：那是模态状态，一点点击都不该漏出去。
	# （按钮这时本身也是 disabled 的，这里只是第二层防线。）
	if is_handbook_open():
		return
	# 阶段对话还没播完时**不要打断它**：Dialoguer 只有一个正文 Label，
	# 打断等于把阶段对话换掉，而它不会再播第二次 —— 这个阶段就失去了
	# 「看完自动推进」这条路径（现在还有占位 HUD 的按钮兜底，等 HUD 删掉就是死路）。
	if _advance_when_dialogue_ends:
		return
	if not _dialoguer.typer.load_dialogue("Boardery"):
		return
	# 提示板是临时对话：此时 _advance_when_dialogue_ends 为 false，播完不会推进阶段。
	_dialoguer.play()


# ---------------------------------------------------------------------------
# 手册（模态浮层，§10.4）
# ---------------------------------------------------------------------------


## 打开手册时先看哪一条。
## 占位：等关键词检索 / 图鉴列表做出来之后，这里换成「按玩家点的那条」传进去。
const HANDBOOK_PLACEHOLDER_ID := &"slime"


func _on_handbook_button_pressed() -> void:
	if _handbook == null:
		push_error("[Interview] 找不到 Handbook")
		return
	if is_handbook_open():
		return
	# 阶段对话还没播完时不打开：Dialoguer 的 _input 在 GUI 输入**之前**就吃掉左键，
	# 那时开着手册，点哪儿都只会把对话往下推。
	if _advance_when_dialogue_ends:
		return
	# 演出期间也不打开：画面正在动，这时候叠一层手册没有意义
	if _animating:
		return

	if not _handbook.open_entry(HANDBOOK_PLACEHOLDER_ID):
		return
	_set_scene_interaction_enabled(false)


## 手册当前是不是开着。本场景的其它入口据此判断要不要理人。
func is_handbook_open() -> bool:
	return _handbook != null and _handbook.is_open()


## 手册关掉了 → 把本场景别的操作放开。
func _on_handbook_closed() -> void:
	_set_scene_interaction_enabled(true)


## 手册开着期间，把本场景其它交互入口全堵上。
##
## 鼠标与键盘**两条路都要堵**，所以不能只加一层挡板：
##   按钮 disabled   → 点击和 ui_accept（回车 / 空格）都不会再发 pressed；
##   词条菜单 HIDDEN → 追问菜单根本弹不出来（手册盖着它，弹出来也是打架）；
##   逻辑层另有一道  → _is_judging_allowed() 在手册开着时返回 false。
##
## 关掉之后恢复：按钮 enabled、词条菜单回到 ASK（面试里点词条 = 追问）。
func _set_scene_interaction_enabled(enabled: bool) -> void:
	var buttons: Array[TextureButton] = [_approved, _nah, _notice_board]
	for button in buttons:
		if button != null:
			button.disabled = not enabled
	if _resume != null:
		_resume.entry_menu = Resume.EntryMenu.ASK if enabled else Resume.EntryMenu.HIDDEN
		if not enabled:
			_resume.close_token_menu()
