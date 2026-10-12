class_name SettingPage
extends CanvasLayer

## 设置页（ARCHITECTURE.md §14）：盖在当前场景之上的全屏浮层。
##
## 两种状态：
##   常规 —— 只有左上角那颗设置按钮（`setting_button_phd.png`，原生 50×50）可见；
##   打开 —— `setting_page_phd.png` 铺满画布盖住底下的一切，页面上有「继续游戏」与「退出游戏」两颗按钮。
##
## 开与关都是**同一个开关**，两个入口：
##   点设置按钮 / 按 Esc —— 关着就开、开着就收（设置按钮一直画在页面**之上**，所以开着时也点得到）。
##
## 为什么是 CanvasLayer 而不是普通 Control：
##   `day_loop` 的阶段界面在默认画布（layer 0），占位 HUD 在 `CanvasLayer(layer 10)`；
##   而 CanvasLayer 的绘制顺序**只由 layer 决定**，跟树序无关 —— 想「盖住当前场景的一切」
##   就只有另开一层、层号压过 FlowHud 这一条路。层号见 LAYER。
##
## 手（`haohan.tscn`）**实例化在本层里**：手是光标，盖在设置页底下就等于没有光标。
## 场景里那只手在 layer 0，被本层整个盖住；本层这只手跟着同一个鼠标位置走、贴图也一样，
## 所以看上去仍然是「一只跟着鼠标的手」，只是它排在设置页**之上**。
##
## 「继续游戏」= 收起本页（继续玩）。
## 「退出游戏」与主菜单那颗按钮**行为完全一致**（§12.9）：
##   第一下弹提醒对话，第二下才真的退出；鼠标移出按钮 / 移出窗口都算反悔。

## 打开 / 收起。给上层（`day_loop`，以后还有主菜单）用。
signal opened()
signal closed()

## 本浮层所在的画布层。
## **只要比 `day_loop` 的 FlowHud(10) 大就行** —— 「图层最高」由这一个数字保证。
const LAYER := 100

## 退出确认播的那段对话：和主菜单用的是同一段（`data/dialogue.json` 的 "test1"）。
const EXIT_CONFIRM_DIALOGUE := "test1"

@onready var _page: Control = get_node_or_null("Page") as Control
@onready var _setting_button: TextureButton = get_node_or_null("SettingButton") as TextureButton
@onready var _continue_button: Button = get_node_or_null("Page/ContinueButton") as Button
@onready var _exit_button: Button = get_node_or_null("Page/ExitButton") as Button
@onready var _haohan: Control = get_node_or_null("Haohan") as Control
@onready var _dialoguer: Dialoguer = get_node_or_null("Dialoguer") as Dialoguer

## 「退出确认已弹过」——第二下点击才真的退出。与 `main_menu.gd` 同名同义。
var _exit_confirming := false


func _ready() -> void:
	# 层号写在这里而不是只在场景里填一次：场景里那个值是给人看的，
	# 这里这一行才是「无论谁把 .tscn 里的 layer 改成了多少，本浮层都在最上面」的保证。
	layer = LAYER

	if _page == null:
		push_error("[SettingPage] 找不到 Page 节点（设置页整页）")
		return
	# 常规状态：只有按钮可见。页面本身的显隐**只**由 open() / close() 管。
	_page.visible = false
	# 三颗按钮 / 鼠标移出的接线都在 .tscn 的 [connection] 里（和 main_menu / handbook 一致），
	# 这里只做一次「接上了没有」的检查：把「节点改名」这种低级错误当场喊出来。
	if _setting_button == null:
		push_error("[SettingPage] 找不到 SettingButton（那颗设置按钮）")
	if _continue_button == null:
		push_error("[SettingPage] 找不到 Page/ContinueButton（那颗继续游戏按钮）")
	if _exit_button == null:
		push_error("[SettingPage] 找不到 Page/ExitButton（设置页上那颗退出按钮）")
	if _haohan == null:
		push_error("[SettingPage] 找不到 Haohan（手不会画在设置页之上）")
	if _dialoguer == null:
		push_error("[SettingPage] 找不到 Dialoguer，退出确认播不出来")


# ---------------------------------------------------------------------------
# 开关
# ---------------------------------------------------------------------------


## 打开设置页：整页盖上来，并挡掉底下场景的一切鼠标交互。
##
## 挡鼠标靠的是 `Page.mouse_filter = STOP` + 铺满画布（在 .tscn 里），
## 而不是靠「把下面的场景 disabled 掉」—— 见 §10.6 手册浮层那套三层做法的前两层：
## 本浮层的层号压过一切，所以「吃不到」就已经等于「点不动」。
func open() -> void:
	if _page == null or is_open():
		return
	# 换到设置页 = 上一次的退出确认作废，否则收掉页面再按退出会「一按就退」
	_cancel_exit_confirm()
	_page.visible = true
	opened.emit()


## 收起设置页：回到「只有那颗设置按钮」的常规状态。
func close() -> void:
	if not is_open():
		return
	_cancel_exit_confirm()
	_page.visible = false
	closed.emit()


## 开关。Esc 与设置按钮都走它，所以两个入口的手感必然一致。
func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func is_open() -> bool:
	return _page != null and _page.visible


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------


## Esc 兼开关。
##
## 走 `_unhandled_input` 而不是 `_input`：场景里已经有别的控件在 `_input` 里处理 Esc
## （简历词条菜单 `resume.gd` 的 `ui_cancel`），它们在**该吃的时候**会
## `set_input_as_handled()` —— 那时这一下是「收菜单」，不该被抢来开设置页。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	toggle()
	get_viewport().set_input_as_handled()


func _on_setting_button_pressed() -> void:
	toggle()


## 「继续游戏」：就是收起设置页 —— 底下那个场景一直是活的，收起来就接着玩。
func _on_continue_pressed() -> void:
	close()


# ---------------------------------------------------------------------------
# 退出游戏
# ---------------------------------------------------------------------------


## 退出按钮。
##
## 退出是破坏性操作，所以要点两次：第一下弹提醒对话，第二下才真的退出。
## 提醒走**穿透模式**（`play(true)`）：对话不会被左键吃掉，玩家仍然可以正常操作界面
## —— 包括「再点一下退出按钮」这一下，它会一边把对话推完、一边照常触发按钮。
func _on_exit_pressed() -> void:
	if _exit_confirming:
		SceneRouter.quit_game()
		return
	if _dialoguer == null:
		push_error("[SettingPage] 找不到 Dialoguer，退出确认播不出来")
		return
	if not _dialoguer.typer.load_dialogue(EXIT_CONFIRM_DIALOGUE):
		# 文案读不出来就**不算确认过**：这一下什么都没发生，而不是变得「一按就退」
		return
	_exit_confirming = true
	_dialoguer.play(true)


func _on_exit_mouse_exited() -> void:
	_cancel_exit_confirm()


func _on_mouse_exited() -> void:
	# 鼠标移出窗口也算放弃退出，免得切回来时误触第二次点击
	_cancel_exit_confirm()


func _cancel_exit_confirm() -> void:
	if not _exit_confirming:
		return
	_exit_confirming = false
	if _dialoguer != null:
		_dialoguer.visible = false
