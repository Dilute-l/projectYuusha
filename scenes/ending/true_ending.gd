extends Control

## 真结局场景：主菜单的标题按钮解锁后按下才进来
## （解锁条件见 scripts/core/flow/ending_unlock.gd）。
##
## 流程：进场景 → 播 data/dialogue.json 的 `Ending_True` → 播完 → 停顿 RETURN_DELAY → 回主界面。
##
## ⚠️ 它和 ending.tscn（好结局）/ bad_ending.tscn（坏结局）是**三个**场景，不是同一个加参数：
##    好结局要铺「十天攒了多少分」、坏结局是半路判负（没有成绩可看）、
##    真结局是从主菜单直接进来的「番外」，连一局都没有。
##    塞进一个场景会变成一堆 if，而 goto_scene 没有「带参数」的通道。
##
## 根 Control 在场景里是 0 尺寸，而 Dialoguer 的子节点是绝对坐标（按 1152×648 画布摆），
## 所以 _ready() 里显式给画布尺寸 —— 和 ending / bad_ending / handbook 同一处理。

## 结局对话
const DIALOGUE_ID := "Ending_True"

## 播完到自动回主界面之间留的停顿（秒）。0 = 立刻切。
const RETURN_DELAY := 2.5

var _dialoguer: Dialoguer = null

## 已经安排过返回（防重复：对话结束信号 + 兜底计时器只该生效一次）
var _returning: bool = false


func _ready() -> void:
	var canvas := get_viewport_rect().size
	size = canvas
	position = Vector2.ZERO

	_dialoguer = get_node_or_null("Dialoguer") as Dialoguer
	if _dialoguer == null:
		push_error("[TrueEnding] 找不到 Dialoguer，直接回主界面")
		_schedule_return()
		return

	if not _dialoguer.typer.load_dialogue(DIALOGUE_ID):
		push_warning("[TrueEnding] 找不到对话「%s」，直接回主界面" % DIALOGUE_ID)
		_schedule_return()
		return

	if not _dialoguer.dialogue_ended.is_connected(_on_dialogue_ended):
		_dialoguer.dialogue_ended.connect(_on_dialogue_ended)

	# 真结局是不属于任何一局的一段「番外」：不给它塞分数 / 天数变量。
	# 以后文案里要用占位符，在 play() 之前 _dialoguer.set_vars({...}) 就行。
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
	_go_back()


## 回主界面。真结局看完这一趟就结束了，没有返回栈可留（和 bad_ending 一样）。
func _go_back() -> void:
	if not is_inside_tree():
		return
	SceneRouter.goto_main_menu()
