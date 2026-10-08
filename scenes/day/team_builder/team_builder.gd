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
##
## 「谁被录用了」是 GameState 的状态，不是 UI 的状态：本脚本只负责把名单同步给界面，
## 以及把界面的两个信号翻译成状态变更。§6 那些数值 / 相性规则一条都不在这里。

var _phase: int = DayPhase.Phase.DAY_BRIEFING

signal phase_finished()

@onready var _ui: TeamBuilderUI = get_node_or_null("TeamBuilderUI") as TeamBuilderUI
@onready var _resume: Resume = get_node_or_null("Resume") as Resume


func set_phase(new_phase: int) -> void:
	_phase = new_phase


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
	_ui.set_hired_ids(GameState.get_current_team())


## 当日名额，来自 data/days/day_XX.tres 的 slots；数据没填就返回 0（表头只报人数）
func _today_slots() -> int:
	var config := DataDB.get_day_config(GameState.get_day())
	return config.slots if config != null else 0


## 一进组队，右半边是空的：还没悬停过任何一位（§12：鼠标移上去才展示）。
func _refresh() -> void:
	if _resume == null:
		return
	_resume.set_candidate(null)
	_resume.visible = false


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
func _on_candidate_toggled(candidate: CandidateResource) -> void:
	if candidate == null:
		return

	var team := GameState.get_current_team()
	if team.has(candidate.id):
		team.erase(candidate.id)
	else:
		team.append(candidate.id)
	GameState.set_current_team(team)

	if _ui != null:
		_ui.set_hired_ids(team)

	# 点一下也把这位的简历铺上：正常路径下悬停已经铺过了，
	# 但「没悬停就点到」（键盘 / 脚本 / 手速）这条路径也说得通。
	_on_candidate_hovered(candidate)


## 当前被标记为录用的 id（= GameState.current_team 的快照）。调试 / 测试用。
func hired_ids() -> Array[StringName]:
	return GameState.get_current_team()
