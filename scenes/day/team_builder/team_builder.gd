extends Control

## 组队容器（ARCHITECTURE.md §4「team_builder.tscn」，§12）。
##
##   左半边：**今日通过面试的候选人**，一人一个方头像框（team_builder_ui.tscn → candidate.tscn）
##   右半边：复用面试那一页简历（resume.tscn）—— 位置和面试里**完全一样**，
##          因为用的是同一个场景、同一套绝对偏移，所以没有任何对齐代码。
##
## 本脚本只做「接线」，不写规则：
##
##   名单   → GameState.passed_ids（面试阶段判定通过的人，data/days/day_XX.tres 里今天出场的那几位）
##   左键   → 头像底下滑出两个按钮 + 把这一位的简历铺到右半边（和面试同一个数据入口）
##   进队   → GameState.current_team 里加上这一位；不进队 → GameState.rejected_ids
##   名额   → 能不能再加一位由 scripts/core/team/team_validator.gd 判定（§0：规则不在表现层）
##
## 开场**谁都没被选中**：面试的「录用」只是把候选池缩小到今天这几位，
## 真正挑满名额是玩家在这儿一位一位按出来的（§12.7）。
##
## 另外两件事（§12 / §10.7）：
##
##   回忆     → 点简历词条弹「回忆」：重播当时那段追问 + 面试官一句自言自语

var _phase: int = DayPhase.Phase.DAY_BRIEFING

signal phase_finished()

@onready var _ui: TeamBuilderUI = get_node_or_null("TeamBuilderUI") as TeamBuilderUI
@onready var _resume: Resume = get_node_or_null("Resume") as Resume
@onready var _dialoguer: Dialoguer = get_node_or_null("Dialoguer") as Dialoguer

## 「回忆」最后追加的那句自言自语。
## 这是**场外补充**，不属于任何候选人、也不在 data/asks/ 那几份 json 里 ——
## 那几份是「当时真的说了什么」，这一句是现在回头看时面试官的感慨，两回事。
const RECALL_TAIL_SPEAKER: String = "面试官"
const RECALL_TAIL_TEXT: String = "当时好像是这样追问的。"

## 「队伍没满，真的要走吗？」已经问过一次了 —— 再点一次就出发。
##
## 与 main_menu.gd 的 _exit_confirming 是同一个模式：**第一次点只提醒，第二次点才执行**。
## 区别是它那里鼠标移出按钮就撤销（退出是破坏性操作，防误触）；
## 这里改成「**改了队伍**才撤销」—— 因为要撤销的是「刚才那份名单确定要走吗」这个问题，
## 名单一变，问题本身就作废了。而且鼠标移出就撤销会和"再点一次"天然打架
## （要再点一次，鼠标难免要动）。
var _confirming_incomplete := false


func set_phase(new_phase: int) -> void:
	_phase = new_phase
	# 换阶段 = 上一次那个「确定要走吗」作废
	_cancel_incomplete_confirm()


func _ready() -> void:
	# 进入阶段通知（其它阶段场景同款接法）
	if not EventBus.day_phase_entered.is_connected(set_phase):
		EventBus.day_phase_entered.connect(set_phase)

	# 当日名单是「本日过程量」，开局 / 换天时由 GameState 从 data/days/ 载入。
	# 单独 F6 跑本场景时没人做过这件事，这里补一次（连一局都没有就先开一局，
	# 和 day_loop.gd 的 F6 处理一致 —— 不然 F6 看到的是一张空桌子）。
	if not GameState.has_run():
		GameState.start_new_run()
	elif GameState.current_candidates.is_empty():
		GameState.load_day_candidates()

	# 这里是「翻简历」，不是「面试」，但词条照样能点开菜单 —— 只是里面那一项
	# 从「追问」变成「回忆」：重播面试时问过的那一条（没问过的置灰）。
	# 见 resume.gd 的 entry_menu。
	if _resume != null:
		_resume.entry_menu = Resume.EntryMenu.RECALL

	# 接上「回忆」：点词条 → 菜单 → 回忆（resume.gd 广播，见 _on_resume_entry_recalled）
	if not EventBus.resume_entry_recalled.is_connected(_on_resume_entry_recalled):
		EventBus.resume_entry_recalled.connect(_on_resume_entry_recalled)

	_wire_ui()
	_refresh()


# ---------------------------------------------------------------------------
# 接线
# ---------------------------------------------------------------------------


func _wire_ui() -> void:
	if _ui == null:
		push_warning("[TeamBuilder] 找不到 TeamBuilderUI，本日只能看到背景")
		return
	if not _ui.candidate_selected.is_connected(_on_candidate_selected):
		_ui.candidate_selected.connect(_on_candidate_selected)
	if not _ui.candidate_approved.is_connected(_on_candidate_approved):
		_ui.candidate_approved.connect(_on_candidate_approved)
	if not _ui.candidate_rejected.is_connected(_on_candidate_rejected):
		_ui.candidate_rejected.connect(_on_candidate_rejected)
	_ui.set_slots(_today_slots())
	_ui.set_candidates(_passed_candidates())
	_push_team_to_ui()


## 今天要摆到左半边的候选人：**面试通过了的那几位**，顺序 = passed_ids 的顺序（§12.2）。
##
## 还没面试 / 一个都没通过时返回空数组（左半边空着，右下角的空位照样在）。
## 名单里的 id 在当日名单里查不到（数据写错 / 换了天）时报一声跳过，不硬塞。
func _passed_candidates() -> Array[CandidateResource]:
	var list: Array[CandidateResource] = []
	for id in GameState.get_passed_ids():
		var candidate := GameState.get_candidate(id)
		if candidate == null:
			push_warning("[TeamBuilder] 通过者 %s 不在今天的名单里，跳过" % id)
			continue
		list.append(candidate)
	return list


## 当日名额，来自 data/days/day_XX.tres 的 slots；数据没填就返回 0（不摆空位、也不限人）
func _today_slots() -> int:
	var config := DataDB.get_day_config(GameState.get_day())
	return config.slots if config != null else 0


## 把队伍状态推给界面：谁进队 / 谁不进队 + 名额满了没有。
## 「满没满」交给 TeamValidator 判，界面只负责画（§0）。
func _push_team_to_ui() -> void:
	if _ui == null:
		return
	var team := GameState.get_current_team()
	_ui.set_decisions(team, GameState.get_rejected_ids())
	_ui.set_team_full(TeamValidator.is_full(team, _today_slots()))


## 一进组队，右半边是空的：还没点过任何一位（§12.3：点头像才展示）。
func _refresh() -> void:
	if _resume == null:
		return
	_resume.set_candidate(null)
	_resume.visible = false


# ---------------------------------------------------------------------------
# 回忆：重播面试时问过的那一条（§10.7）
# ---------------------------------------------------------------------------


## 玩家在组队阶段点了某一条的「回忆」。
##
## 播的内容 = **当时那份追问 json** + 面试官一句自言自语。
## 追加那句走 Typer.append_line()：它只影响这一次播放，不动任何文件 ——
## data/asks/ 那几份 json 里存的永远是「面试当时真正播的东西」。
##
## 这里**不校验「问过没有」**：菜单那层已经置灰了（resume.gd 的 _option_enabled），
## 但万一有人绕过它发了信号，GameState 里没有记录就干脆不播，比播错强。
func _on_resume_entry_recalled(candidate_id: StringName, entry_index: int) -> void:
	if not GameState.has_asked_entry(candidate_id, entry_index):
		push_warning("[TeamBuilder] %s 的第 %d 条没有追问记录，不播回忆" % [candidate_id, entry_index])
		return
	if _dialoguer == null:
		push_error("[TeamBuilder] 找不到 Dialoguer，无法播出回忆")
		return

	var candidate := GameState.get_candidate(candidate_id)
	if candidate == null:
		push_warning("[TeamBuilder] 回忆的候选人找不到：%s" % candidate_id)
		return
	# 序号 → 对话文件这一层交给 Resume.ask_path_of()（和 interview.gd 同一处约定）
	var ask_path := Resume.ask_path_of(candidate, entry_index)
	if ask_path.is_empty():
		push_warning("[TeamBuilder] %s[%d] 没有可回忆的对话" % [candidate_id, entry_index])
		return
	if not FileAccess.file_exists(ask_path):
		push_error("[TeamBuilder] 追问 json 不存在：%s" % ask_path)
		return

	# 一份 json = 一条追问，所以 id 留空（取文件里的第一段）
	if not _dialoguer.typer.load_dialogue_from(ask_path):
		return
	_dialoguer.typer.append_line(RECALL_TAIL_SPEAKER, RECALL_TAIL_TEXT)
	_dialoguer.play()


# ---------------------------------------------------------------------------
# 悬停 → 右半边铺简历
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# 左键点头像 → 右半边铺简历
# ---------------------------------------------------------------------------


## 玩家左键点了某一位的**头像**（两个按钮跟着从头像底下滑出来，那件事在 UI 层）。
##
## 这里只负责把这一位的简历铺到右半边：和面试完全同一个数据入口，
## 抬头 + 逐条词条全部来自 data/candidates/*.tres。
##
## 铺过就**留着**：判定完把按钮收起来时简历不动，不然读到一半就白了。
func _on_candidate_selected(candidate: CandidateResource) -> void:
	if candidate == null or _resume == null:
		return
	_resume.set_candidate(candidate)
	_resume.visible = true


# ---------------------------------------------------------------------------
# 「进队」/「不进队」
# ---------------------------------------------------------------------------


## 点了「进队」：这一位进 GameState.current_team（右下角就多填一个格子、底色转绿）。
##
## 真身是 GameState.current_team（§2：本日过程量，不入存档），这里只是在改它。
## 「还能不能再加一位」是规则，问 TeamValidator。
## 进队和不进队**互斥**：进队的人从 rejected_ids 里划掉。
func _on_candidate_approved(candidate: CandidateResource) -> void:
	if candidate == null:
		return

	# 队伍一改，「刚才那份名单确定要走吗」这个问题就作废了
	_cancel_incomplete_confirm()

	# 点自己也顺手把简历铺上（点头像那一下已经铺过，但脚本直接发信号这条路径也说得通）
	_on_candidate_selected(candidate)

	var slots := _today_slots()
	var team := GameState.get_current_team()
	if team.has(candidate.id):
		# 已经在队里：再按一次不改任何东西（想反悔就按「不进队」）
		_push_team_to_ui()
		return

	var verdict := TeamValidator.can_add(team, slots, candidate.id)
	if not bool(verdict.get("ok", false)):
		var reason := StringName(verdict.get("reason", &""))
		# 「满了」是玩家看得见的正常状态（进队按钮已经置灰），不必刷警告；
		# 另外两种说明调用方出了问题 —— 要响，不要吞。
		if reason != TeamValidator.REASON_FULL:
			push_warning("[TeamBuilder] %s 加不进队伍：%s" % [candidate.id, reason])
		_push_team_to_ui()
		return

	team.append(candidate.id)
	GameState.set_current_team(team)
	_forget_rejection(candidate.id)
	_push_team_to_ui()


## 点了「不进队」：这一位记进 GameState.rejected_ids（底色转红、不占名额格）。
##
## 已经在队里的先拿出来 —— 进队和不进队是**互斥**的两种判定，不能同时成立。
func _on_candidate_rejected(candidate: CandidateResource) -> void:
	if candidate == null:
		return

	_cancel_incomplete_confirm()
	_on_candidate_selected(candidate)

	var team := GameState.get_current_team()
	if team.has(candidate.id):
		team.erase(candidate.id)
		GameState.set_current_team(team)

	var rejected := GameState.get_rejected_ids()
	if not rejected.has(candidate.id):
		rejected.append(candidate.id)
		GameState.set_rejected_ids(rejected)

	_push_team_to_ui()


## 把某位从「不进队」名单里划掉（他刚刚改成进队了）
func _forget_rejection(candidate_id: StringName) -> void:
	var rejected := GameState.get_rejected_ids()
	if not rejected.has(candidate_id):
		return
	rejected.erase(candidate_id)
	GameState.set_rejected_ids(rejected)


## 当前进队的 id（= GameState.current_team 的快照）。调试 / 测试用。
func hired_ids() -> Array[StringName]:
	return GameState.get_current_team()


# ---------------------------------------------------------------------------
# 出发
# ---------------------------------------------------------------------------


## 玩家点了「组队完成」。
##
##   队伍**超员**   → 拦住，播 team_over 提示先减人（**不是**提醒一次就放行）
##   队伍**已满**   → 立刻出发
##   队伍**没满**   → 先播 team_not_full 提醒，**再点一次**才出发（同主菜单退出按钮）
##   当天没有名额数据 → 也直接出发（数据没填是开发期问题，不该变成玩家的疑问）
##
## 「没满」那段提醒用**穿透模式**（play(true)，见 dialoguer.gd）：对话不吃左键，
## 所以第二次点「组队完成」时，同一次点击既把提醒推完、也照常落到按钮上 ——
## 不用先点空处把对话收掉再点按钮。超员那段则保持默认的阻挡模式：
## 它是硬拦，提醒期间不该顺手点到别处。
func _on_confirm_pressed() -> void:
	var slots := _today_slots()
	var team := GameState.get_current_team()

	# 超员是**硬拦**：多带的人没有名额，怎么点都出不去。
	# 界面上按「进队」是走 TeamValidator 的，正常玩不会超；
	# 这条兜的是「队伍被别处写成了超员」（调试 / 脚本 / 以后改数据）那条路。
	if TeamValidator.is_over(team, slots):
		_cancel_incomplete_confirm()
		if not _play_dialogue("team_over"):
			# 提示文案缺失也不能放行 —— 否则「超员」这个状态就白设了
			push_warning("[TeamBuilder] 队伍超出名额 %d/%d，且 team_over 播不出来" % [team.size(), slots])
		return

	if _confirming_incomplete:
		_depart()
		return

	if not TeamValidator.has_quota(slots) or TeamValidator.is_full(team, slots):
		_depart()
		return

	_confirming_incomplete = true
	if not _play_dialogue("team_not_full", true):
		# 提醒文案缺失 / 没有对话框 —— 不能因此把玩家卡在这里
		push_warning("[TeamBuilder] team_not_full 播不出来，直接出发")
		_depart()


## 真的出发：报告本阶段结束，换阶段 / 换天 / 进结局由 day_loop 问 DayDirector 决定。
func _depart() -> void:
	_confirming_incomplete = false
	phase_finished.emit()


## 撤销「确定要走吗」：换阶段、或改了队伍时调用。
## 和 main_menu.gd 的 _cancel_exit_confirm 同一套做法 —— 连同对话框一起收掉，
## 否则它还开着、还会继续吃左键。
func _cancel_incomplete_confirm() -> void:
	if not _confirming_incomplete:
		return
	_confirming_incomplete = false
	if _dialoguer != null:
		_dialoguer.visible = false


## 播一段对话。找不到 Dialoguer、或那段 id 不存在，都返回 false 让调用方决定怎么兜。
## pass_through 原样转给 Dialoguer.play()：true = 对话不吃左键（见 dialoguer.gd）。
func _play_dialogue(id: String, pass_through: bool = false) -> bool:
	if _dialoguer == null:
		push_error("[TeamBuilder] 找不到 Dialoguer")
		return false
	if not _dialoguer.typer.load_dialogue(id):
		return false
	_dialoguer.play(pass_through)
	return true
