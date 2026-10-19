extends Control

## 开场剧情场景：**第一次启动**时由 boot.gd 切进来；之后可以从主菜单的火漆按钮重看。
##
## 流程：播 data/dialogue.json 的 `opening` → 播完 → 停顿 RETURN_DELAY → 回主界面。
##
## 它和 ending / bad_ending / true_ending 是同一套结构（根 Control + 底色 + Dialoguer），
## 区别只有 DIALOGUE_ID 和"播完去哪"：开场没有成绩可看，播完直接回菜单。
##
## 根 Control 在场景里是 0 尺寸，而 Dialoguer 的子节点是绝对坐标（按 1152×648 画布摆），
## 所以 _ready() 里显式给画布尺寸 —— 和 ending / bad_ending / true_ending / handbook 同一处理。

## 开场对话
const DIALOGUE_ID := "opening"

## 播完到自动回主界面之间留的停顿（秒）。0 = 立刻切。
## 比结局短一点：开场只是旁白，没有分数要看。
const RETURN_DELAY := 1.5

var _dialoguer: Dialoguer = null

## 已经安排过返回（防重复：对话结束信号 + 兜底计时器只该生效一次）
var _returning: bool = false


func _ready() -> void:
	var canvas := get_viewport_rect().size
	size = canvas
	position = Vector2.ZERO

	_dialoguer = get_node_or_null("Dialoguer") as Dialoguer
	if _dialoguer == null:
		push_error("[Opening] 找不到 Dialoguer，直接回主界面")
		_schedule_return()
		return

	if not _dialoguer.typer.load_dialogue(DIALOGUE_ID):
		push_warning("[Opening] 找不到开场对话「%s」，直接回主界面" % DIALOGUE_ID)
		_schedule_return()
		return

	if not _dialoguer.dialogue_ended.is_connected(_on_dialogue_ended):
		_dialoguer.dialogue_ended.connect(_on_dialogue_ended)

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


## 回主界面。开场不是一局，也不留返回栈（和 true_ending / bad_ending 一样）。
func _go_back() -> void:
	if not is_inside_tree():
		return
	SceneRouter.goto_main_menu()
