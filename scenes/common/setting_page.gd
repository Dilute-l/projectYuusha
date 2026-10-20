class_name SettingPage
extends CanvasLayer

## 设置页（ARCHITECTURE.md §14）：盖在当前场景之上的全屏浮层。
##
## 两种状态：
##   常规 —— 只有左上角那颗设置按钮（`setting_button_phd.png`，原生 50×50）可见；
##   打开 —— `setting_page_phd.png` 铺满画布盖住底下的一切，页面上竖着四颗按钮，
##           自上而下：继续游戏 / 全屏开关 / 回到标题界面 / 退出游戏（§14.4）。
##
## 开与关都是**同一个开关**，两个入口：
##   点设置按钮 / 按 Esc —— 关着就开、开着就收（设置按钮一直画在页面**之上**，所以开着时也点得到）。
## **有对话框（台词）挡着的时候也点得开**：系统级的东西不该被台词挡住（§14.5）。
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
## 「回到标题界面」= 回主菜单（`SceneRouter.goto_main_menu()`，单点就走）。
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

## 全屏开关按钮上那句字：`%s` 处填「开」/「关」（见 `fullscreen_label()`）。
const FULLSCREEN_TEXT := "全屏：%s"

## 悬停高亮：全游戏共用那一份（§10.6），设置页这四颗按钮只是在它基础上**整体上移**一点。
const HOVER_STYLE := preload("res://ui/styles/hover_gray.tres")

## 四颗按钮的灰底往**上**挪多少（像素）。
##
## 为什么字会偏高：按钮的字是 60 号的 `Silver.ttf`，它的 ascent / descent 是 38 / 29；
## Godot 拿「行盒」（38+29=67）在 90px 高的按钮里居中，而中文的墨迹是**坐在基线上**的、
## 高约 33px —— 于是字的墨迹中心比按钮正中**高了大约 13px**。
## 灰底老老实实铺满整个按钮矩形时，下半截就比上半截多出一大块（看着就是「阴影偏下」）。
## 所以把画出来的框原样上移这么多：上下就一样宽了。
##
## ⚠️ 框是**画**在控制矩形之外的（`expand_margin`），不影响布局、不影响点击区域，
##   也不影响字的位置。想微调「灰底相对字的上下留白」，改这一个数即可。
const HOVER_SHIFT := 13.0

## 现在有几个设置页是开着的。**静态**：对话框在 `_input` 里要据此给系统浮层让路
## （见 `is_any_open()` 与 `dialoguer.gd::_input()`）—— 对话框不认识任何一个具体实例。
static var _open_count: int = 0

@onready var _page: Control = get_node_or_null("Page") as Control
@onready var _setting_button: TextureButton = get_node_or_null("SettingButton") as TextureButton
@onready var _continue_button: Button = get_node_or_null("Page/ContinueButton") as Button
@onready var _exit_button: Button = get_node_or_null("Page/ExitButton") as Button
@onready var _fullscreen_button: Button = get_node_or_null("Page/FullscreenButton") as Button
@onready var _back_to_title_button: Button = get_node_or_null("Page/BackToTitleButton") as Button
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
	# 四颗按钮 / 鼠标移出的接线都在 .tscn 的 [connection] 里（和 main_menu / handbook 一致），
	# 这里只做一次「接上了没有」的检查：把「节点改名」这种低级错误当场喊出来。
	if _setting_button == null:
		push_error("[SettingPage] 找不到 SettingButton（那颗设置按钮）")
	if _continue_button == null:
		push_error("[SettingPage] 找不到 Page/ContinueButton（那颗继续游戏按钮）")
	if _exit_button == null:
		push_error("[SettingPage] 找不到 Page/ExitButton（设置页上那颗退出按钮）")
	if _fullscreen_button == null:
		push_error("[SettingPage] 找不到 Page/FullscreenButton（全屏开关按钮）")
	if _back_to_title_button == null:
		push_error("[SettingPage] 找不到 Page/BackToTitleButton（回到标题界面按钮）")
	if _haohan == null:
		push_error("[SettingPage] 找不到 Haohan（手不会画在设置页之上）")
	if _dialoguer == null:
		push_error("[SettingPage] 找不到 Dialoguer，退出确认播不出来")
	# 按钮上的「开 / 关」一开始就对到**实际**窗口模式上（不是写死在 .tscn 里当默认文案）
	_sync_fullscreen_button()
	# 悬停灰底：共用那份灰的一份「上移」变体（见 HOVER_SHIFT）
	_apply_hover_styles()


## 四颗按钮的悬停灰底 = 共用那份灰（§10.6）**整体上移 HOVER_SHIFT**。
##
## 在运行期复制一份再改 `expand_margin`，而不是另存一个 `.tres`：
## 颜色、圆角、透明度照样只有 `ui/styles/hover_gray.tres` 一处，
## 改那一个文件，设置页这边跟着变 —— 只有「框画在哪儿」是本页自己的事。
## `expand_margin` 只影响**画出来的矩形**，不碰布局、不碰点击区域。
func _apply_hover_styles() -> void:
	for button in [_continue_button, _fullscreen_button, _back_to_title_button, _exit_button]:
		var b := button as Button
		if b == null:
			continue
		var hover := HOVER_STYLE.duplicate() as StyleBoxFlat
		if hover == null:
			continue
		hover.expand_margin_top = HOVER_SHIFT
		hover.expand_margin_bottom = -HOVER_SHIFT
		b.add_theme_stylebox_override("hover", hover)


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
	# 收着的时候窗口模式可能被别处切过：盖上来之前先把「开 / 关」对一次
	_sync_fullscreen_button()
	_page.visible = true
	_open_count += 1
	opened.emit()


## 收起设置页：回到「只有那颗设置按钮」的常规状态。
func close() -> void:
	if not is_open():
		return
	_cancel_exit_confirm()
	_page.visible = false
	_open_count = maxi(_open_count - 1, 0)
	closed.emit()


## 开关。Esc 与设置按钮都走它，所以两个入口的手感必然一致。
func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func is_open() -> bool:
	return _page != null and _page.visible


## 有没有任何一页设置页开着（供对话框判断「现在该不该吃点击」）。
static func is_any_open() -> bool:
	return _open_count > 0


## 页面开着的时候被释放（切场景 / 回主菜单）也要把计数扣掉：
## 否则下一场里所有对话框都会以为「系统浮层还开着」，点击全不推进（见 dialoguer.gd）。
func _exit_tree() -> void:
	if is_open():
		_open_count = maxi(_open_count - 1, 0)


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------


## 窗口模式可能被**别处**改掉（系统窗口菜单、以后加的快捷键）：字永远跟着实际模式走。
## 和手（`haohan.gd::_process()`）同一套做法 —— 它也得在模式变了之后补一次光标模式。
func _process(_delta: float) -> void:
	if _fullscreen_button == null:
		return
	if _fullscreen_button.text != fullscreen_label(is_fullscreen()):
		_sync_fullscreen_button()


## 点左上角那颗设置按钮 —— **在 `_input` 阶段自己认这一下**（§14.5）。
##
## 为什么不能只靠 Button 自己的点击：**有对话框的时候**，`dialoguer.gd::_input()` 在
## GUI 之前就把左键吃掉了（阻挡模式：得先把这段台词点完），GUI 根本收不到这一下，
## 设置按钮就成了「点不动」。设置页是系统级的东西，不该被台词挡着 ——
## 所以在这里先认一次「点的是不是那颗按钮」，是就开页面，并把这一下吃掉
## （那一句对话不该因为「点设置」而翻页）。
##
## 为什么这里一定排在对话框前面：`_input` 是**倒着**派发的（后加的子节点先收到），
## 而 `day_loop` 把本浮层实例化在**最后**一个（§14.1）—— 同一帧里先到的是这里。
##
## 只管**收着**的时候：开着时那颗按钮走正常的 GUI 点击（页面铺满画布吃掉了底下的一切，
## 而对话框此时已经让路、不再吃点击 —— 见 `is_any_open()` 与 dialoguer.gd 里那一句）。
func _input(event: InputEvent) -> void:
	if is_open() or _setting_button == null:
		return
	# 切场景的遮罩期间不接点击：那会儿画面上盖着一层黑，点它没有意义（§10.6 遮罩）
	if SceneRouter.is_transitioning:
		return
	if not (event is InputEventMouseButton):
		return
	var click: InputEventMouseButton = event
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _setting_button.get_global_rect().has_point(click.position):
		return
	get_viewport().set_input_as_handled()
	open()


## Esc 兼开关。
##
## 走 `_unhandled_input` 而不是 `_input`：场景里已经有别的控件在 `_input` 里处理 Esc
## （简历词条菜单 `resume.gd` 的 `ui_cancel`），它们在**该吃的时候**会
## `set_input_as_handled()` —— 那时这一下是「收菜单」，不该被抢来开设置页。
## （对话框只吃鼠标左键、不吃 Esc，所以「有台词时按 Esc」本来就能开。）
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
# 全屏开关
# ---------------------------------------------------------------------------


## 现在是不是全屏。真值取自 `DisplayServer` 的**实际**窗口模式，而不是本地记的一个 bool ——
## 窗口在别处被切过之后，按钮上的字不会说反话。判定口径与手
## （`haohan.gd::_confines_cursor()`）完全一致：**独占全屏也算全屏**。
func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## 按钮上那句字（「全屏：开」/「全屏：关」）。
## 做成静态函数是为了自检能直接验文案 —— headless 的 DisplayServer 什么都切不动，
## 「把窗口真切成全屏再看字」那条路在自检里走不通。
static func fullscreen_label(on: bool) -> String:
	return FULLSCREEN_TEXT % ("开" if on else "关")


## 直接设定全屏开 / 关。关 = 回到 `WINDOW_MODE_WINDOWED`（普通带边框窗口）。
##
## 用**无边框全屏**（`WINDOW_MODE_FULLSCREEN`）而不是独占全屏（`WINDOW_MODE_EXCLUSIVE_FULLSCREEN`）：
## 独占全屏切出 / 切回时会把整个画面黑一下，还容易和录屏、叠加层打架；
## 无边框全屏观感一样，切换也干净。
func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	_sync_fullscreen_button()


## 开 ↔ 关。按钮点一下、或者以后加快捷键，都走它。
func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())


## 把按钮上的字对到**实际**窗口模式上：开着显示「开」，关着显示「关」。
func _sync_fullscreen_button() -> void:
	if _fullscreen_button == null:
		return
	_fullscreen_button.text = fullscreen_label(is_fullscreen())


func _on_fullscreen_pressed() -> void:
	toggle_fullscreen()


# ---------------------------------------------------------------------------
# 回到标题界面
# ---------------------------------------------------------------------------


## 「回到标题界面」：回主菜单（`SceneRouter.goto_main_menu()` 顺手把返回栈清掉）。
##
## **单点就走**，不像「退出游戏」要点两次：离开这一局并不是终止操作 ——
## 每天开始时都自动存过档（§15），回标题之后主菜单的「继续游戏」读最新那份就能接回来；
## 当天进行到一半的进度不存（和直接关游戏一样，读档从**那一天开始**接着走）。
## 真要防误触的话，玩家自己再加一层确认，而不是把这个按钮做成「两下才走」。
##
## 切换期间（`is_transitioning`）直接忽略：连点两下不会叠两次切场景请求
## —— 和主菜单那几颗按钮是同一个约定。
## 顺手作废退出确认：提醒还开着就切走，留着一个「已确认」状态没有意义。
func _on_back_to_title_pressed() -> void:
	if SceneRouter.is_transitioning:
		return
	_cancel_exit_confirm()
	SceneRouter.goto_main_menu()


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
