extends Control

## 组队容器（ARCHITECTURE.md §4「team_builder.tscn」，§12）。
##
##   左半边：**今日出现的面试者的头像**（team_builder_ui.tscn，一条一个 candidate.tscn）
##   右半边：复用面试那一页简历（resume.tscn）—— 位置和面试里**完全一样**，
##          因为用的是同一个场景、同一套绝对偏移，所以没有任何对齐代码。
##
## 本脚本只做「接线」，不写规则：
##
##   名单   → GameState.current_candidates（data/days/day_XX.tres 写死的当日名单）
##   悬停   → 把这一位的简历铺到右半边（和面试同一个数据入口 Resume.set_candidate）
##   左键   → 在 GameState.current_team 里加上这一位；再点一次 = 从名单里去掉（撤销）
##   名额   → 能不能加由 scripts/core/team/team_validator.gd 判定（§0：规则不在表现层）
##
## 另外两件事（§12 / §10.7）：
##
##   初始名单 → 面试阶段选了「录用」的人**一开始就标好**（见 _seed_team_from_verdicts）
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

	# **先播种再接线**：_wire_ui() 结尾会把队伍推给界面（_push_team_to_ui），
	# 顺序反了的话界面拿到的还是空名单，玩家会看到一个「没人被录用」的组队界面。
	_seed_team_from_verdicts()
	_wire_ui()
	_refresh()


# ---------------------------------------------------------------------------
# 接线
# ---------------------------------------------------------------------------


func _wire_ui() -> void:
	if _ui == null:
		push_warning("[TeamBuilder] 找不到 TeamBuilderUI，本日只能看到背景")
		return
	if not _ui.candidate_hovered.is_connected(_on_candidate_hovered):
		_ui.candidate_hovered.connect(_on_candidate_hovered)
	if not _ui.candidate_toggled.is_connected(_on_candidate_toggled):
		_ui.candidate_toggled.connect(_on_candidate_toggled)
	_ui.set_slots(_today_slots())
	_ui.set_candidates(GameState.current_candidates)
	_push_team_to_ui()


## 当日名额，来自 data/days/day_XX.tres 的 slots；数据没填就返回 0（表头只报人数）
func _today_slots() -> int:
	var config := DataDB.get_day_config(GameState.get_day())
	return config.slots if config != null else 0


## 把队伍状态推给界面：谁被选中 + 名额满了没有。
## 「满没满」交给 TeamValidator 判，界面只负责画（§0）。
func _push_team_to_ui() -> void:
	if _ui == null:
		return
	var team := GameState.get_current_team()
	_ui.set_hired_ids(team)
	_ui.set_team_full(TeamValidator.is_full(team, _today_slots()))


## 一进组队，右半边是空的：还没悬停过任何一位（§12：鼠标移上去才展示）。
func _refresh() -> void:
	if _resume == null:
		return
	_resume.set_candidate(null)
	_resume.visible = false


# ---------------------------------------------------------------------------
# 初始名单：面试阶段选了「录用」的人
# ---------------------------------------------------------------------------


## 把面试阶段的通过者直接带进今天的队伍（§12）。
##
## 组队阶段要做的是「从通过者里调整出最终名额」，而不是让玩家凭记忆再点一遍 ——
## 面试时按下的那个「录用」就是玩家的第一次筛选，这里把它接着用。
##
## 通过者可能**比名额多**：这时界面会把他们全标上，玩家去掉几位才能出发
## （见 _on_confirm_pressed 的超员拦截）。这是有意的 —— 该由玩家决定留下谁。
func _seed_team_from_verdicts() -> void:
	# 已经有队伍就别覆盖：换阶段回来 / F6 重进不该把玩家刚调整好的名单冲掉
	if not GameState.get_current_team().is_empty():
		return
	var passed := GameState.get_passed_ids()
	if passed.is_empty():
		return
	GameState.set_current_team(passed)


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
	if candidate == null or entry_index >= candidate.resume.size():
		push_warning("[TeamBuilder] 回忆的条目找不到：%s[%d]" % [candidate_id, entry_index])
		return
	var entry: ResumeEntry = candidate.resume[entry_index]
	if entry == null or entry.ask_path.strip_edges().is_empty():
		push_warning("[TeamBuilder] 第 %d 条没有 ask_path，没有可回忆的内容" % entry_index)
		return
	if not FileAccess.file_exists(entry.ask_path):
		push_error("[TeamBuilder] 追问 json 不存在：%s" % entry.ask_path)
		return

	# 一份 json = 一条追问，所以 id 留空（取文件里的第一段）
	if not _dialoguer.typer.load_dialogue_from(entry.ask_path):
		return
	_dialoguer.typer.append_line(RECALL_TAIL_SPEAKER, RECALL_TAIL_TEXT)
	_dialoguer.play()


# ---------------------------------------------------------------------------
# 悬停 → 右半边铺简历
# ---------------------------------------------------------------------------


func _on_candidate_hovered(candidate: CandidateResource) -> void:
	if candidate == null or _resume == null:
		return
	# 与面试完全同一个数据入口：抬头 + 逐条词条全部来自 data/candidates/*.tres
	_resume.set_candidate(candidate)
	_resume.visible = true


# ---------------------------------------------------------------------------
# 左键 → 标记录用 / 撤销
# ---------------------------------------------------------------------------


## 左键点一位：没在队里就加进去（标记为录用），已在队里就拿出来（撤销）。
##
## 真身是 GameState.current_team（§2：本日过程量，不入存档），这里只是在改它。
## 「还能不能再加一位」是规则，问 TeamValidator。
func _on_candidate_toggled(candidate: CandidateResource) -> void:
	if candidate == null:
		return

	# 队伍一改，「刚才那份名单确定要走吗」这个问题就作废了
	_cancel_incomplete_confirm()

	var slots := _today_slots()
	var team := GameState.get_current_team()

	if team.has(candidate.id):
		# 撤销**永远**允许 —— 否则满员之后玩家就换不了人了
		team.erase(candidate.id)
	else:
		var verdict := TeamValidator.can_add(team, slots, candidate.id)
		if not bool(verdict.get("ok", false)):
			var reason := StringName(verdict.get("reason", &""))
			# 「满了」是玩家看得见的正常状态（头像已经变灰），不必刷警告；
			# 另外两种说明调用方出了问题 —— 要响，不要吞。
			if reason != TeamValidator.REASON_FULL:
				push_warning("[TeamBuilder] %s 加不进队伍：%s" % [candidate.id, reason])
			return
		team.append(candidate.id)

	GameState.set_current_team(team)
	_push_team_to_ui()

	# 点一下也把这位的简历铺上：正常路径下悬停已经铺过了，
	# 但「没悬停就点到」（键盘 / 脚本 / 手速）这条路径也说得通。
	_on_candidate_hovered(candidate)


## 当前被标记为录用的 id（= GameState.current_team 的快照）。调试 / 测试用。
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
## 注意「没满」那条第二下的实际路径：提醒对话开着时，Dialoguer 会吃掉左键（dialoguer.gd 的 _input），
## 所以玩家得先把这段对话点完收起来，那一下才会真的落到按钮上 —— 主菜单的退出按钮同理。
func _on_confirm_pressed() -> void:
	var slots := _today_slots()
	var team := GameState.get_current_team()

	# 超员是**硬拦**：多带的人没有名额，怎么点都出不去。
	# 为什么会超：面试录用的比名额多时，一进组队就是超员状态（见 _seed_team_from_verdicts）。
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
	if not _play_dialogue("team_not_full"):
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
func _play_dialogue(id: String) -> bool:
	if _dialoguer == null:
		push_error("[TeamBuilder] 找不到 Dialoguer")
		return false
	if not _dialoguer.typer.load_dialogue(id):
		return false
	_dialoguer.play()
	return true
