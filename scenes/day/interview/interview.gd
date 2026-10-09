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

## 当前阶段（DayPhase.Phase）
var _phase: int = DayPhase.Phase.DAY_BRIEFING

@onready var _resume: Resume = get_node_or_null("Resume") as Resume
@onready var _approved: TextureButton = get_node_or_null("Approved") as TextureButton
@onready var _nah: TextureButton = get_node_or_null("Nah") as TextureButton
@onready var _dialoguer: Dialoguer = get_node_or_null("Dialoguer") as Dialoguer

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
		_defer_phase_finished()
		return
	# 换下一位：立绘与简历一起翻页
	_refresh_interviewee()


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------


func _on_notice_board_pressed() -> void:
	if _dialoguer == null:
		push_error("[Interview] 找不到 Dialoguer")
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
