extends Node

## setting_page 自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_setting_page.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是 §14 那几条：
##   **常规只有那颗按钮可见**、**点按钮 / 按 Esc 都把整页盖上来**、
##   **整页真的盖满画布且吃鼠标（点得到底下的场景就等于没盖住）**、
##   **层号压过 day_loop 里所有的 CanvasLayer（「图层最高」）**、
##   退出按钮**跟主菜单那颗一样：第一下弹提醒、移开鼠标就算反悔**。
##
## 为什么不测「第二下真的退出」：那一下会 `get_tree().quit()`，把自检自己终结掉 ——
## 绿着退出，什么都验不到。第二下走的是同一行代码（`SceneRouter.quit_game()`），
## 与主菜单那颗按钮是同一条路。
##
## 画布塞进 1152×648 的 SubViewport 里测（理由见 ARCHITECTURE.md §10.6）。

const SETTING_PAGE_SCENE := preload("res://scenes/common/setting_page.tscn")
const DAY_LOOP_SCENE := preload("res://scenes/day/day_loop.tscn")

## 游戏的实际画布（project.godot 的 canvas_items 拉伸基准）
const GAME_CANVAS := Vector2i(1152, 648)

## 退出确认用的那段对话 —— 与 setting_page.gd / main_menu.gd 同一个 id
const EXIT_CONFIRM_DIALOGUE := "test1"

## 设置按钮与设置页两张美术的期望尺寸。
##
## ⚠️ 这两个数跟着**美术文件本身**走，不跟屏幕观感走：
##   按钮 `setting_button.jpg` 是 32×32（场景里 scale = 1.6 → 屏幕上 51.2px，那是版面，不是贴图）；
##   整页 `setting_page.png` 是 2266×1274（靠 `expand_mode = 1` 撑满画布，所以也不用改版面）。
##   换美术时**同步改这里 + 下面那两句断言里的文件名**，否则自检会替旧图喊冤。
const BUTTON_SIZE := Vector2(32, 32)
const PAGE_SIZE := Vector2(2266, 1274)

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	# 等 root 把子节点装配完再往里加 —— _ready() 里直接 add_child 会被拒绝
	await get_tree().process_frame
	await _run()
	_report()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK  " if ok else "FAIL", what])


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _esc() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	return ev


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = GAME_CANVAS
	vp.disable_3d = true
	get_tree().root.add_child(vp)

	var setting := SETTING_PAGE_SCENE.instantiate() as SettingPage
	vp.add_child(setting)
	await _settle()

	var canvas := vp.get_visible_rect().size
	print("[smoke_setting_page] 画布 = %s" % canvas)
	_check(canvas == Vector2(GAME_CANVAS), "画布是自己设定的 1152x648")

	var page: Control = setting.get_node("Page")
	var page_phd: TextureRect = page.get_node("PagePhd")
	var continue_button: Button = page.get_node("ContinueButton")
	var exit_button: Button = page.get_node("ExitButton")
	var setting_button: TextureButton = setting.get_node("SettingButton")
	var haohan: Control = setting.get_node("Haohan")
	var dialoguer: Dialoguer = setting.get_node("Dialoguer")

	# ---- 结构 ----
	_check(setting is CanvasLayer, "根节点是 CanvasLayer")
	_check(page != null and page_phd != null, "Page / PagePhd 就位")
	_check(continue_button != null, "Page/ContinueButton 就位")
	_check(exit_button != null, "Page/ExitButton 就位")
	_check(setting_button != null, "SettingButton 就位")
	_check(haohan != null, "Haohan 就位（手要画在设置页之上）")
	_check(dialoguer != null, "Dialoguer 就位（退出确认要用的那段对话）")

	# ---- 手在设置页之上 ----
	_check(haohan.get_parent() == setting, "手实例化在设置页这一层里（不是底下那个场景里）")
	_check(haohan.visible, "手默认可见（不是藏在暗处的空节点）")
	var hand: Sprite2D = haohan.get_node_or_null("Hand") as Sprite2D
	_check(hand != null and hand.texture != null, "手有贴图")
	_check(haohan.z_index > page.z_index,
			"手的 z_index(%d) > 设置页的 z_index(%d) —— 手画在设置页之上" % [haohan.z_index, page.z_index])

	# ---- 系统光标：窗口模式下**只藏不夹**（全屏才夹，见 haohan.gd::_confines_cursor）----
	# 自检跑在 headless 里 = 窗口模式。以前一律 CONFINED_HIDDEN，指针被 ClipCursor
	# 夹死在窗口里拖不出去；这条就是防它退回去。
	#
	# ⚠️ 只能断言「判断」那一层：headless 的 DisplayServer 是空实现，
	#   `Input.get_mouse_mode()` 会被它归零成 VISIBLE，量不到设下去的模式。
	_check(not haohan._confines_cursor(),
			"窗口模式下不夹光标（全屏才夹）—— 报 true 的话指针又会被夹死在窗口里")

	# ---- 两张美术确实挂上了，而且尺寸对得上 ----
	_check(setting_button.texture_normal != null, "设置按钮的贴图已加载")
	if setting_button.texture_normal != null:
		_check(setting_button.texture_normal.get_size() == BUTTON_SIZE,
				"设置按钮用的是 setting_button.jpg（%s）" % setting_button.texture_normal.get_size())
	_check(page_phd.texture != null, "设置页的贴图已加载")
	if page_phd.texture != null:
		_check(page_phd.texture.get_size() == PAGE_SIZE,
				"设置页用的是 setting_page.png（%s）" % page_phd.texture.get_size())

	# ---- 常规状态：只有那颗按钮可见 ----
	_check(not page.visible, "常规状态：设置页不可见")
	_check(setting_button.visible, "常规状态：只有设置按钮可见")
	_check(not setting.is_open(), "is_open() 在常规状态返回 false")

	# ---- 按钮的位置与大小：左上角、贴图原生尺寸 × 场景里的 scale ----
	_check(setting_button.get_global_rect().position == Vector2.ZERO,
			"设置按钮贴在画布左上角（%s）" % setting_button.get_global_rect().position)
	# 屏幕上的大小 = 贴图原生尺寸 × scale（1.6）。这里比的是**渲染结果**，
	# 所以不能直接拿 BUTTON_SIZE 比 —— 那是贴图尺寸。
	var shown := BUTTON_SIZE * setting_button.scale
	_check(setting_button.get_global_rect().size.is_equal_approx(shown),
			"设置按钮按 %s 贴图 × scale %.1f 画（%s）" % [
				BUTTON_SIZE, setting_button.scale.x, setting_button.get_global_rect().size])
	_check(setting_button.position.x >= 0.0 and setting_button.position.y >= 0.0,
			"设置按钮没有跑出画布")

	# ---- 图层最高 ----
	var layers: Array[CanvasLayer] = []
	_collect_layers(vp, layers)
	var max_layer := -128
	for l in layers:
		max_layer = maxi(max_layer, l.layer)
	_check(setting.layer == SettingPage.LAYER, "设置页的层号 = LAYER（%d）" % SettingPage.LAYER)
	_check(setting.layer > 10, "层号压过 day_loop 的 FlowHud(10)（实际 %d）" % setting.layer)
	_check(max_layer == setting.layer and layers.size() == 1,
			"同一容器里没有比它更高的 CanvasLayer（最高 %d）" % max_layer)

	# ---- 点设置按钮 → 整页盖上来 ----
	_check(setting_button.pressed.get_connections().size() > 0, "设置按钮的 pressed 已接到 setting_page.gd")
	var opened := [0]
	var opened_spy := func() -> void: opened[0] += 1
	setting.opened.connect(opened_spy)
	setting_button.pressed.emit()
	await _settle()

	_check(page.visible, "点设置按钮 → 设置页打开")
	_check(setting.is_open(), "is_open() 跟着变 true")
	_check(opened[0] == 1, "opened 信号发了一次（实际 %d）" % opened[0])
	_check(setting_button.visible, "开着时设置按钮仍在（压在页面上，点得到）")

	# ---- 整页真的盖满了画布，而且吃鼠标 ----
	_check(page.get_global_rect().position == Vector2.ZERO, "设置页从画布左上角起铺")
	_check(page.size == canvas, "设置页的矩形 = 整块画布（%s）" % page.size)
	_check(page_phd.get_global_rect().size == canvas,
			"设置页贴图画满整块画布（%s）" % page_phd.get_global_rect().size)
	_check(page.mouse_filter == Control.MOUSE_FILTER_STOP,
			"设置页吃鼠标（MOUSE_FILTER_STOP）—— 底下的场景点不到")

	# ---- 设置按钮排在整页之后：同一层里绘制顺序靠树序，后画的在上面 ----
	_check(setting.get_child(0) == page, "Page 是第一个子节点")
	_check(setting.get_child(1) == setting_button,
			"设置按钮排在 Page 之后 —— 它压在设置页之上（子节点序 %s）" % setting_button.get_index())

	# ---- 再点一次：收起（同一个开关） ----
	var closed := [0]
	var closed_spy := func() -> void: closed[0] += 1
	setting.closed.connect(closed_spy)
	setting_button.pressed.emit()
	await _settle()
	_check(not page.visible, "再点一次设置按钮 → 收起")
	_check(closed[0] == 1, "closed 信号发了一次（实际 %d）" % closed[0])

	# ---- Esc：关着 → 打开 ----
	setting._unhandled_input(_esc())
	await _settle()
	_check(page.visible, "Esc → 设置页打开")

	# ---- Esc：开着 → 收起 ----
	setting._unhandled_input(_esc())
	await _settle()
	_check(not page.visible, "再按一次 Esc → 收起")
	_check(closed[0] == 2, "closed 一共发了两次（实际 %d）" % closed[0])

	# ---- 别的键不该打开它 ----
	var tab := InputEventAction.new()
	tab.action = &"ui_accept"
	tab.pressed = true
	setting._unhandled_input(tab)
	await _settle()
	_check(not page.visible, "ui_accept 不会打开设置页")

	# ---- 退出按钮在画布正中 ----
	var r := exit_button.get_global_rect()
	var center := Vector2(canvas.x * 0.5, canvas.y * 0.5)
	_check(is_equal_approx(r.get_center().x, center.x) and is_equal_approx(r.get_center().y, center.y),
			"退出按钮摆在画布正中（%s，期望 %s）" % [r.get_center(), center])
	_check(exit_button.text == "退出游戏", "退出按钮的文案是「退出游戏」")
	_check(exit_button.pressed.get_connections().size() > 0, "退出按钮的 pressed 已接到 setting_page.gd")

	# ---- 继续游戏按钮：就在退出按钮的**正上方** ----
	var cr := continue_button.get_global_rect()
	_check(continue_button.text == "继续游戏", "继续游戏按钮的文案是「继续游戏」")
	_check(continue_button.pressed.get_connections().size() > 0,
			"继续游戏按钮的 pressed 已接到 setting_page.gd")
	_check(cr.end.y < r.position.y, "继续游戏按钮在退出按钮**上面**（下缘 %s < 退出按钮上缘 %s）"
			% [cr.end.y, r.position.y])
	_check(cr.size == r.size, "两颗按钮一样大（%s）" % cr.size)
	_check(is_equal_approx(cr.position.x, r.position.x), "两颗按钮左缘对齐（%s / %s）"
			% [cr.position.x, r.position.x])
	_check(is_equal_approx(cr.get_center().x, center.x), "两颗按钮都横向居中（中心 x=%s）" % cr.get_center().x)
	_check(cr.position.y >= 0.0, "继续游戏按钮没有顶出画布上边（y=%s）" % cr.position.y)

	# ---- 继续游戏 = 收起设置页（接着玩） ----
	setting.open()
	await _settle()
	_check(page.visible, "前提：设置页开着")
	continue_button.pressed.emit()
	await _settle()
	_check(not page.visible, "点「继续游戏」→ 收起设置页")
	_check(closed[0] == 3, "closed 又发了一次（实际 %d）" % closed[0])
	_check(not dialoguer.visible, "「继续游戏」顺手把退出确认作废（不会留着变成一按就退）")

	# ---- 退出按钮第一下：弹提醒，且用的是主菜单同一段文案 ----
	_check(not dialoguer.visible, "退出提醒默认不显示")
	exit_button.pressed.emit()
	await _settle()
	_check(dialoguer.visible, "点退出按钮第一下 → 弹提醒（不退出）")
	_check(dialoguer.is_playing(), "提醒正在播")
	_check(dialoguer.is_pass_through(), "提醒走穿透模式（和主菜单一致）")
	var expected := _dialogue_lines(EXIT_CONFIRM_DIALOGUE)
	_check(not expected.is_empty(), "data/dialogue.json 里有 \"%s\" 这一段" % EXIT_CONFIRM_DIALOGUE)
	# 只比「有台词的行」：json 里那种只有 config 的段级设置行不进 typer.lines
	var got: Array = []
	for line in dialoguer.typer.lines:
		got.append(String(line.get("text", "")))
	var want: Array = []
	for line in expected:
		if line is Dictionary and (line as Dictionary).has("text"):
			want.append(String((line as Dictionary)["text"]))
	_check(got == want, "播的是 \"%s\" 那段（%d 行：%s）" % [EXIT_CONFIRM_DIALOGUE, want.size(), want])

	# ---- 鼠标移出退出按钮 = 反悔：确认作废、提醒收起 ----
	exit_button.mouse_exited.emit()
	await _settle()
	_check(not dialoguer.visible, "鼠标移出退出按钮 → 提醒收起")
	# 作废之后第一下又是「弹提醒」，而不是「直接退出」——
	# 真的退出了的话下面这行自检根本等不到：进程已经没了。
	exit_button.pressed.emit()
	await _settle()
	_check(dialoguer.visible, "反悔之后再点第一下 → 重新弹提醒（没有一按就退）")
	exit_button.mouse_exited.emit()
	await _settle()

	# ---- 开着设置页再收起来：退出确认不能留着（否则「一按就退」） ----
	exit_button.pressed.emit()
	await _settle()
	_check(dialoguer.visible, "前提：提醒开着")
	setting.open()
	setting.close()
	await _settle()
	_check(not dialoguer.visible, "收设置页 → 提醒一并作废")

	# 收回常规状态，免得后面的检查看到脏状态
	setting.close()
	await _settle()

	# ---- 鼠标移出窗口也算反悔 ----
	exit_button.pressed.emit()
	await _settle()
	_check(dialoguer.visible, "前提：提醒又开着")
	page.mouse_exited.emit()
	await _settle()
	_check(not dialoguer.visible, "鼠标移出窗口 → 提醒收起")

	# ---- day_loop 里确实实例化了它，且没有别的层压过它 ----
	var day_loop: Node = DAY_LOOP_SCENE.instantiate()
	vp.add_child(day_loop)
	await _settle()

	var mounted: Node = day_loop.get_node_or_null("SettingPage")
	_check(mounted != null, "day_loop.tscn 里实例化了 SettingPage")
	if mounted != null:
		_check(mounted is SettingPage, "挂上去的确实是 setting_page.tscn")
		_check(mounted.layer == SettingPage.LAYER, "挂上去的层号是 %d" % SettingPage.LAYER)
	var all: Array[CanvasLayer] = []
	_collect_layers(day_loop, all)
	var top := -128
	var others := 0
	for l in all:
		top = maxi(top, l.layer)
		if l != mounted:
			others += 1
	_check(others >= 1, "day_loop 里还有别的 CanvasLayer（FlowHud）—— 层号这条才有的比（%d 个）" % others)
	_check(top == SettingPage.LAYER,
			"设置页是 day_loop 里层号最高的那一层（最高 %d，期望 %d）" % [top, SettingPage.LAYER])

	# 挂上去之后仍然是常规状态：只有那颗按钮
	if mounted is SettingPage:
		_check(not (mounted as SettingPage).is_open(), "day_loop 里的设置页默认是收起的")

	day_loop.queue_free()
	await _settle()

	# 收尾：让最后那段提醒**自然打完**再退出。
	# typer 还在逐字跑的时候进程就没了的话，那些逐字音效的 AudioStreamPlayback
	# 还挂在 SFX 池上没放掉，退出时会报「leaked instances / resources still in use」，
	# 把自检的退出码顶成 1 —— 明明 57 项全绿。等它打完（这句不到 0.4 秒）就干净了。
	dialoguer.visible = false
	await get_tree().create_timer(1.0).timeout


## 递归收集一棵子树里的所有 CanvasLayer
func _collect_layers(root: Node, out: Array[CanvasLayer]) -> void:
	if root is CanvasLayer:
		out.append(root)
	for child in root.get_children():
		_collect_layers(child, out)


## 直接从 data/dialogue.json 里取一段。期望值**不写在脚本里** ——
## 改文案（`test1` 那句怎么写）不用动这里；改结构（字段名 / 段 id）才会红。
func _dialogue_lines(id: String) -> Array:
	var path := "res://data/dialogue.json"
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var all: Dictionary = parsed
	if not all.has(id):
		return []
	var section: Variant = all[id]
	if typeof(section) != TYPE_ARRAY:
		return []
	return section


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_setting_page] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_setting_page] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
