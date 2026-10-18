extends Control

## 坏结局场景：某天的战报分数低于当天 `DayConfig.score_request` 时，由 `day_loop` 切过来。
##
## 流程：进场景 → 播 `data/dialogue.json` 的 `Ending_Bad` → 播完 → 自动回主界面。
##
## ⚠️ 它和 `ending.tscn`（好结局）是两个场景，不是同一个加参数：
##    好结局要铺成绩、要判"活过十天"，坏结局是**半路判负**、没有十天成绩可看 ——
##    塞进一个场景会变成一堆 if（而且 `goto_scene` 没有"带参数"的通道）。
##
## 根 Control 在场景里是 0 尺寸，而 Dialoguer 的子节点是绝对坐标（按 1152×648 画布摆），
## 所以 `_ready()` 里显式给画布尺寸 —— 和 handbook.gd / ending.gd 同一处理。

## 结局对话
const DIALOGUE_ID := "Ending_Bad"

## 播完到自动回主界面之间留的停顿（秒）。0 = 立刻切。
const RETURN_DELAY := 2.5

var _dialoguer: Dialoguer = null

## 已经安排过返回（防重复）
var _returning: bool = false


func _ready() -> void:
	var canvas := get_viewport_rect().size
	size = canvas
	position = Vector2.ZERO

	_dialoguer = get_node_or_null("Dialoguer") as Dialoguer
	if _dialoguer == null:
		push_error("[BadEnding] 找不到 Dialoguer，直接回主界面")
		_schedule_return()
		return

	if not _dialoguer.typer.load_dialogue(DIALOGUE_ID):
		push_warning("[BadEnding] 找不到对话「%s」，直接回主界面" % DIALOGUE_ID)
		_schedule_return()
		return

	if not _dialoguer.dialogue_ended.is_connected(_on_dialogue_ended):
		_dialoguer.dialogue_ended.connect(_on_dialogue_ended)

	# 坏结局也可能想说"你第几天倒了"——变量先塞好，文案里想用就用
	_dialoguer.set_vars({
		"failed_day": GameState.get_day(),
		"days": GameConfig.TOTAL_DAYS,
	})
	_dialoguer.play()


func _on_dialogue_ended() -> void:
	_schedule_return()


## 安排自动回主界面。计时器挂在场景树上，场景被释放时会跟着没。
func _schedule_return() -> void:
	if _returning:
		return
	_returning = true
	if RETURN_DELAY > 0.0:
		await get_tree().create_timer(RETURN_DELAY).timeout
	if not is_inside_tree():
		return
	SceneRouter.goto_main_menu()
