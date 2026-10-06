extends Node

## 每日流程容器（ARCHITECTURE.md §4）：按 DayPhase 状态机切换子场景。
##
## 本脚本只做「显示 + 输入 + 转发」：
##   规则 → `scripts/core/flow/day_director.gd`（纯静态，可被测试直接调用）
##   状态 → GameState
##   跳转 → SceneRouter
##
## 关于 FlowHud：M0 阶段各阶段子场景（interview / team_builder / battle_report）还是空壳，
## 需要有个东西点着才能走完十天，所以 day_loop.tscn 里挂了一个**占位 HUD**。
## M1〜M5 做出真正的阶段界面后，直接删掉 FlowHud 节点即可：
## 脚本对它的引用全部走 get_node_or_null，删掉不影响流程本身。

## 阶段子场景（interview / team_builder / battle_report）的挂载点
@onready var _phase_container: Node = get_node_or_null("PhaseContainer")

var _day_label: Label = null
var _phase_label: Label = null
var _score_label: Label = null
var _next_button: Button = null

## 当前挂在 PhaseContainer 下的子场景 key 与实例
var _phase_scene_key: StringName = &""
var _phase_instance: Node = null


func _ready() -> void:
	# 单独运行本场景（F6）时也得有一局可跑；从菜单进来时已经开好局了
	if not GameState.has_run():
		GameState.start_new_run()

	_bind_hud()
	EventBus.day_started.connect(_on_day_started)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.day_scored.connect(_on_day_scored)

	# 进入每日流程 = 当日自动存档点（§7）。第 1 天的 day_started 在开新局时就发过了，
	# 那时本场景还没进树，所以这里补一次；之后每天由 _on_day_started 负责。
	SaveService.autosave()

	_refresh()
	_swap_phase_scene(GameState.get_phase())

# ---------------------------------------------------------------------------
# 推进流程
# ---------------------------------------------------------------------------


## 推进到下一步。M0 由占位 HUD 的「继续」按钮调用；M1 起由各阶段子场景自己决定何时推进
func advance() -> void:
	if SceneRouter.is_transitioning:
		return
	var step := DayDirector.advance(GameState.get_phase(), GameState.get_day())
	match int(step["step"]):
		DayDirector.Step.PHASE:
			GameState.set_phase(int(step["phase"]))
		DayDirector.Step.DAY_END:
			GameState.advance_day()
		DayDirector.Step.RUN_END:
			GameState.set_phase(DayPhase.Phase.ENDING)
			# 结局判定（ending_resolver）是 M4 的事，这里只负责把流程交给结局场景
			SceneRouter.goto_scene(&"ending")

# ---------------------------------------------------------------------------
# 事件
# ---------------------------------------------------------------------------


func _on_day_started(_day_index: int) -> void:
	SaveService.autosave()
	_refresh()


func _on_day_phase_changed(_phase: int) -> void:
	_refresh()
	_swap_phase_scene(GameState.get_phase())


func _on_day_scored(_result: Dictionary) -> void:
	_refresh()

# ---------------------------------------------------------------------------
# 阶段子场景切换
# ---------------------------------------------------------------------------


func _swap_phase_scene(phase: int) -> void:
	if _phase_container == null:
		return
	# 结局不是 day_loop 的子场景，而是一次整场景切换，交给 SceneRouter
	if phase == DayPhase.Phase.ENDING:
		_clear_phase_instance()
		return

	var scene_key := DayDirector.scene_key_for(phase)
	# 招人阶段的 Screening / Interview 共用 interview.tscn，不重建实例
	if scene_key == _phase_scene_key:
		if _phase_instance != null and _phase_instance.has_method("set_phase"):
			_phase_instance.call("set_phase", phase)
		return

	_clear_phase_instance()
	_phase_scene_key = scene_key
	if scene_key == &"":
		return

	var scene_path := SceneRouter.scene_path_for(scene_key)
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_warning("[DayLoop] 阶段 %s 没有可用子场景：%s" % [DayPhase.to_name(phase), scene_key])
		return
	var packed: PackedScene = load(scene_path)
	_phase_instance = packed.instantiate()
	_phase_container.add_child(_phase_instance)


func _clear_phase_instance() -> void:
	if _phase_instance != null:
		_phase_instance.queue_free()
		_phase_instance = null
	_phase_scene_key = &""

# ---------------------------------------------------------------------------
# 占位 HUD
# ---------------------------------------------------------------------------


func _bind_hud() -> void:
	# 注意：占位 HUD 的文案暂时用 ASCII —— assets/fonts 还没接入中文主字体，
	# 引擎默认字体没有中文字形，中文会渲染成方块。字体到位后再换回中文。
	_day_label = get_node_or_null("FlowHud/Hud/Margin/Layout/DayLabel") as Label
	_phase_label = get_node_or_null("FlowHud/Hud/Margin/Layout/PhaseLabel") as Label
	_score_label = get_node_or_null("FlowHud/Hud/Margin/Layout/ScoreLabel") as Label
	_next_button = get_node_or_null("FlowHud/Hud/Margin/Layout/NextButton") as Button
	if _next_button != null and not _next_button.pressed.is_connected(advance):
		_next_button.pressed.connect(advance)


func _refresh() -> void:
	if _day_label == null:
		return  # 占位 HUD 被删掉后，流程本身照常可用
	var day := GameState.get_day()
	var phase := GameState.get_phase()
	var index := DayPhase.ORDER.find(phase)
	var progress := "%d/%d" % [index + 1, DayPhase.ORDER.size()] if index >= 0 else "final"

	_day_label.text = "Day %d / %d" % [day, GameConfig.TOTAL_DAYS]
	_phase_label.text = "Phase %s  (%s)  %s" % [DayPhase.to_name(phase), progress, DayPhase.display_name(phase)]
	_score_label.text = "Score %d     Hired %d     Saved %s" % [
		GameState.get_total_score(),
		GameState.get_roster().size(),
		"yes" if SaveService.has_auto_save() else "no",
	]
	if _next_button != null:
		_next_button.text = _next_button_text(phase)


func _next_button_text(phase: int) -> String:
	if phase == DayDirector.LAST_PHASE:
		if GameState.is_last_day():
			return "Show Ending  >"
		return "Next Day  >"
	return "Continue  >"
