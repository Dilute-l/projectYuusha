extends Node

## GameState —— 一次「讨伐季」的全部运行时状态（ARCHITECTURE.md §2）。
##
## 关键纪律（§2 尾注）：**GameState 只存状态，所有规则放在 `scripts/core/` 里以静态函数实现**。
## 这样「同一种子 → 同一份候选人 → 同一个战报」可以被测试完整复现。
##
## 可存档部分全部落在 `run_state: RunState`（§7 的存档根结构）；
## 当日候选人、当前队伍属于「本日过程量」，不入存档，读档后按种子重放即可得到。

## 存档根结构（§7）。永远不为 null，便于菜单 / 调试在没有开局时安全访问
var run_state: RunState = null

## 当日候选人（由 candidate_generator 写入，本日过程量）
var current_candidates: Array[CandidateResource] = []

## 当前队伍（组队阶段挑满名额）
var current_team: Array[StringName] = []

## 本日通过者（面试阶段累计，组队阶段的候选池）
var passed_ids: Array[StringName] = []


func _ready() -> void:
	# 未开局时给一个空的 RunState：UI 可以无脑读 day / phase，不用到处判空
	if run_state == null:
		run_state = RunState.new()

# ---------------------------------------------------------------------------
# 局的生命周期
# ---------------------------------------------------------------------------


## 是否已经开了一局（由 start_new_run / load 设置）
func has_run() -> bool:
	return run_state != null and run_state.run_seed != 0


## 开新局：重置状态、设定种子、广播 day_started
func start_new_run(seed_value: int = 0) -> RunState:
	var used_seed := RngService.start_run(seed_value)
	run_state = RunState.new()
	run_state.version = GameConfig.SAVE_VERSION
	run_state.run_seed = used_seed
	run_state.day = 1
	run_state.scores = []
	run_state.roster = []
	run_state.flags = {}
	run_state.handbook_unlocked = []
	run_state.phase = DayPhase.to_name(DayPhase.Phase.DAY_BRIEFING)
	current_candidates = []
	current_team = []
	passed_ids = []
	EventBus.run_started.emit(used_seed)
	EventBus.day_started.emit(run_state.day)
	return run_state


## 读档后接管一局：以存档里的种子重建随机流，之后的日子必须与当初完全一致
func apply_run_state(state: RunState) -> void:
	run_state = state if state != null else RunState.new()
	RngService.start_run(run_state.run_seed)
	current_candidates = []
	current_team = []
	passed_ids = []
	EventBus.run_loaded.emit(run_state.run_seed)


## 清空到「未开局」状态（回主菜单、弃档）
func clear_run() -> void:
	run_state = RunState.new()
	current_candidates = []
	current_team = []
	passed_ids = []

# ---------------------------------------------------------------------------
# 天数与阶段
# ---------------------------------------------------------------------------


func get_day() -> int:
	return run_state.day


func get_run_seed() -> int:
	return run_state.run_seed


## 当前阶段（DayPhase.Phase）
func get_phase() -> int:
	return DayPhase.from_name(run_state.phase)


## 当前阶段名（存档用的 StringName 形式）
func get_phase_name() -> StringName:
	return run_state.phase


## 切阶段并广播。同阶段重复设置不会重复广播
func set_phase(phase: int) -> void:
	var phase_name := DayPhase.to_name(phase)
	if run_state.phase == phase_name:
		return
	run_state.phase = phase_name
	EventBus.day_phase_changed.emit(phase)

func is_last_day() -> bool:
	return run_state.day >= GameConfig.TOTAL_DAYS


## 天数 +1 并回到 DAY_BRIEFING。已是第 10 天则返回 false（该走结局了）
func advance_day() -> bool:
	if is_last_day():
		return false
	run_state.day += 1
	_set_phase_silent(DayPhase.Phase.DAY_BRIEFING)
	current_candidates = []
	current_team = []
	passed_ids = []
	EventBus.day_started.emit(run_state.day)
	EventBus.day_phase_changed.emit(DayPhase.Phase.DAY_BRIEFING)
	return true


func _set_phase_silent(phase: int) -> void:
	run_state.phase = DayPhase.to_name(phase)

# ---------------------------------------------------------------------------
# 每日得分
# ---------------------------------------------------------------------------


## 记录当日得分；breakdown = { true_power, synergy, lie_penalty, event_bonus, luck }
func record_day_score(day_index: int, gained: int, breakdown: Dictionary = {}) -> void:
	if day_index < 1:
		return
	while run_state.scores.size() < day_index:
		run_state.scores.append(0)
	run_state.scores[day_index - 1] = gained
	EventBus.day_scored.emit({
		"day": day_index,
		"gained": gained,
		"total": get_total_score(),
		"breakdown": breakdown,
	})


func get_day_score(day_index: int) -> int:
	if day_index < 1 or day_index > run_state.scores.size():
		return 0
	return run_state.scores[day_index - 1]


func get_total_score() -> int:
	var total := 0
	for score in run_state.scores:
		total += score
	return total

# ---------------------------------------------------------------------------
# 录用名单
# ---------------------------------------------------------------------------


## 录用一位候选人；重复录用返回 false
func hire(candidate_id: StringName) -> bool:
	if candidate_id == &"" or is_hired(candidate_id):
		return false
	run_state.roster.append(candidate_id)
	EventBus.candidate_hired.emit(candidate_id)
	return true


func is_hired(candidate_id: StringName) -> bool:
	return run_state.roster.has(candidate_id)


func get_roster() -> Array[StringName]:
	var roster: Array[StringName] = []
	roster.assign(run_state.roster)
	return roster


## 对某位候选人给出录用判定。通过者留在本日过程量里，供组队阶段取用
func issue_verdict(candidate_id: StringName, passed: bool) -> void:
	EventBus.verdict_issued.emit(candidate_id, passed)
	if not passed or passed_ids.has(candidate_id):
		return
	passed_ids.append(candidate_id)


## 本日通过者（组队阶段的候选池；与当日候选人一样属于本日过程量，不入存档）
func get_passed_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(passed_ids)
	return ids

# ---------------------------------------------------------------------------
# 剧情 flag
# ---------------------------------------------------------------------------


func get_flag(flag_name: StringName, default_value: Variant = 0) -> Variant:
	return run_state.flags.get(flag_name, default_value)


func set_flag(flag_name: StringName, value: Variant) -> void:
	run_state.flags[flag_name] = value


## 累加型 flag，例如 liar_hired / team_broke 的计数
func add_flag(flag_name: StringName, amount: int = 1) -> int:
	var value := int(run_state.flags.get(flag_name, 0)) + amount
	run_state.flags[flag_name] = value
	return value

# ---------------------------------------------------------------------------
# 手册解锁
# ---------------------------------------------------------------------------


## 解锁手册条目；已解锁返回 false，避免 UI 重复弹提示
func unlock_handbook_entry(entry_id: StringName) -> bool:
	if entry_id == &"" or is_handbook_unlocked(entry_id):
		return false
	run_state.handbook_unlocked.append(entry_id)
	EventBus.handbook_entry_unlocked.emit(entry_id)
	return true


func is_handbook_unlocked(entry_id: StringName) -> bool:
	return run_state.handbook_unlocked.has(entry_id)

# ---------------------------------------------------------------------------
# 当日候选人 / 当前队伍（本日过程量，不入存档）
# ---------------------------------------------------------------------------


## 写入当日候选人并广播 day_started 之外的 UI 刷新由订阅方自行处理
func set_current_candidates(candidates: Array[CandidateResource]) -> void:
	var copy: Array[CandidateResource] = []
	copy.assign(candidates)
	current_candidates = copy


func get_current_candidates() -> Array[CandidateResource]:
	var copy: Array[CandidateResource] = []
	copy.assign(current_candidates)
	return copy


func get_candidate(candidate_id: StringName) -> CandidateResource:
	for candidate in current_candidates:
		if candidate != null and candidate.id == candidate_id:
			return candidate
	return null


func get_candidate_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for candidate in current_candidates:
		if candidate != null:
			ids.append(candidate.id)
	return ids


func set_current_team(member_ids: Array[StringName]) -> void:
	var copy: Array[StringName] = []
	copy.assign(member_ids)
	current_team = copy


func get_current_team() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(current_team)
	return copy
