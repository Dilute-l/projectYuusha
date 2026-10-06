extends Control

## 结局场景（ARCHITECTURE.md §4）：十天走完后按累计分与 flag 判定结局。
##
## M0 只是空壳：显示累计分 + 一个回主菜单的出口，让十天流程能走成一个闭环。
## 真正的结局判定（`scripts/core/scoring/ending_resolver.gd`，M4）会替换掉这里的占位界面。
##
## 对外信号沿用 §4 的约定。

## 请求重开一局（M4 的结局演出也走这个信号）
signal restart_requested

var _score_label: Label = null
var _back_button: Button = null


func _ready() -> void:
	# 文案暂时用 ASCII：assets/fonts 还没接入中文主字体
	_score_label = get_node_or_null("Hud/Margin/Layout/ScoreLabel") as Label
	_back_button = get_node_or_null("Hud/Margin/Layout/BackButton") as Button
	if _back_button != null and not _back_button.pressed.is_connected(_on_back_pressed):
		_back_button.pressed.connect(_on_back_pressed)
	_refresh()


func _refresh() -> void:
	if _score_label == null:
		return
	_score_label.text = "Final score %d     Hired %d     Day %d / %d" % [
		GameState.get_total_score(),
		GameState.get_roster().size(),
		GameState.get_day(),
		GameConfig.TOTAL_DAYS,
	]


func _on_back_pressed() -> void:
	restart_requested.emit()
	# 结局是这一局的终点，回主菜单时不再保留返回栈
	SceneRouter.goto_main_menu()
