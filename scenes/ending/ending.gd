extends Control

## 结局场景（ARCHITECTURE.md §4）：十天走完后**只播好结局**，播完自动回主界面。
##
## 现在的流程：
##   进场景 → 播 `Ending_Good`（那段里写着 `{total_score}` 占位符）
##          → 对话播完 → 铺出最终成绩 → **自动**返回主界面
##
## 坏结局**不走这个场景**：某天战报分数低于当天 `score_request` 时，
## `day_loop` 当场判死，直接播 `Ending_Bad` 后回主界面（见 day_loop.gd）。
## 所以这里不需要"按分数挑结局"的判断 —— 走到本场景就等于活过了十天。
##
## 对外信号沿用 §4 的约定（`restart_requested` 在回主界面时发一次）。

## 请求重开一局（M4 的结局演出也走这个信号）
signal restart_requested

## 结局叙事用哪一段对话
const ENDING_DIALOGUE_ID := "Ending_Good"

## 播完叙事到自动回主界面之间留的停顿（秒）——
## 让玩家看清"Final score"那一行再切走；0 = 立刻切。
const RETURN_DELAY := 2.5

var _score_label: Label = null
var _back_button: Button = null
var _dialoguer: Dialoguer = null

## 已经安排过返回（防重复：对话结束信号 + 兜底计时器只该生效一次）
var _returning: bool = false


func _ready() -> void:
	# 本场景的根 Control 在场景里是 0 尺寸（anchors_preset = 0），
	# 而 Dialoguer 里的子节点是**绝对坐标**（贴图画在 1152×648 的画布上）——
	# 祖先 0 尺寸时全屏锚点算出来还是 0，所以这里显式给画布尺寸。
	# 和 handbook.gd 的处理一致。
	var canvas := get_viewport_rect().size
	size = canvas
	position = Vector2.ZERO

	_score_label = get_node_or_null("Hud/Margin/Layout/ScoreLabel") as Label
	_back_button = get_node_or_null("Hud/Margin/Layout/BackButton") as Button
	_dialoguer = get_node_or_null("Dialoguer") as Dialoguer
	if _back_button != null and not _back_button.pressed.is_connected(_on_back_pressed):
		_back_button.pressed.connect(_on_back_pressed)

	# 成绩先算好，但**先不显示** —— 等叙事播完再铺，免得剧透"总计是……{score}"那句
	_refresh()
	_play_ending_dialogue()


## 播好结局叙事。对话文本里的 `{total_score}` 等占位符在这里被注入。
func _play_ending_dialogue() -> void:
	if _dialoguer == null:
		push_error("[Ending] 找不到 Dialoguer，直接显示成绩并返回")
		_reveal_score()
		_schedule_return()
		return

	if not _dialoguer.typer.load_dialogue(ENDING_DIALOGUE_ID):
		# 没这段文案不是错误：直接把成绩亮出来，结局屏仍然是完整的
		push_warning("[Ending] 找不到对话「%s」，直接显示成绩" % ENDING_DIALOGUE_ID)
		_reveal_score()
		_schedule_return()
		return

	if not _dialoguer.dialogue_ended.is_connected(_on_dialogue_ended):
		_dialoguer.dialogue_ended.connect(_on_dialogue_ended)

	# 变量在 **play 之前**塞：Typer 是每行开始时替换的，play 之后行才开始跑。
	_dialoguer.set_vars({
		"total_score": _score_text(),
		"hired_count": GameState.get_roster().size(),
		"days": GameConfig.TOTAL_DAYS,
	})
	# 叙事期间先藏着成绩
	if _score_label != null:
		_score_label.visible = false
	_dialoguer.play()


func _on_dialogue_ended() -> void:
	_reveal_score()
	_schedule_return()


## 亮出最终成绩
func _reveal_score() -> void:
	if _score_label != null:
		_score_label.visible = true
	_refresh()


## 安排「自动回主界面」：等 RETURN_DELAY 秒，让玩家看清成绩再切。
##
## ⚠️ 为什么用 await + 计时器而不是直接 goto：
##    `dialogue_ended` 是**对话被玩家点掉**的那一刻，同一帧就切场景的话，
##    成绩那行字等于没显示过。留一点停顿，玩家才看得到总分。
##    计时器挂在场景树上，场景被释放时它会跟着没 —— 不会在切走之后又触发。
func _schedule_return() -> void:
	if _returning:
		return
	_returning = true
	if RETURN_DELAY > 0.0:
		await get_tree().create_timer(RETURN_DELAY).timeout
	_go_back()


## 回主界面。**只在这里发 restart_requested** —— 它是"这一局结束了"的公告，
## 不是"玩家想重开"（重开由主菜单的 Start 决定）。
func _go_back() -> void:
	if not is_inside_tree():
		return
	restart_requested.emit()
	# 结局是这一局的终点，回主菜单时不再保留返回栈
	SceneRouter.goto_main_menu()


## 总分的显示文本。累计分是 float（当日分 = 战力 × 羁绊倍率），显示成整数。
func _score_text() -> String:
	return "%.0f" % GameState.get_total_score()


func _refresh() -> void:
	if _score_label == null:
		return
	# %.0f 而不是 %d：累计分是 float，%d 配 float 在 GDScript 里会报错。
	_score_label.text = "Final score %s     Hired %d     Day %d / %d" % [
		_score_text(),
		GameState.get_roster().size(),
		GameState.get_day(),
		GameConfig.TOTAL_DAYS,
	]


## 「返回主菜单」按钮：不等停顿，立刻走（玩家主动点的）
func _on_back_pressed() -> void:
	_go_back()
