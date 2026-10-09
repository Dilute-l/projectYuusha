extends Node

## SceneRouter —— 场景切换、返回栈、过场遮罩（ARCHITECTURE.md §2）。
##
## 纪律：**每日流程各阶段的跳转都走它**，场景脚本里不允许直接 `change_scene_to_file`。
## 好处是过场遮罩、返回栈、场景路径校验只有一处实现，也方便 M6 换成异步加载。
##
## 覆盖层是一个常驻 CanvasLayer + 全屏 ColorRect：它挂在 Autoload 下，
## 因此切场景时不会随旧场景一起被释放，遮罩才不会闪断。

## 场景表：key -> res:// 路径。key 用小写下划线，与目录结构对应
const SCENES: Dictionary = {
	&"boot": "res://scenes/boot/boot.tscn",
	&"main_menu": "res://scenes/menu/main_menu.tscn",
	&"day_loop": "res://scenes/day/day_loop.tscn",
	&"interview": "res://scenes/day/interview/interview.tscn",
	&"team_builder": "res://scenes/day/team_builder/team_builder.tscn",
	&"battle_report": "res://scenes/day/battle_report.tscn",
	&"ending": "res://scenes/ending/ending.tscn",
	&"credits_room": "res://scenes/credits/credits_room.tscn",
}

## 过场遮罩所在层级，压在一切 UI 之上（CanvasLayer 默认 1）
const OVERLAY_LAYER: int = 128

## 正在切换中（切换期间拒绝新的切换请求）
var is_transitioning: bool = false

var _overlay: CanvasLayer = null
var _fade_rect: ColorRect = null
var _fade_duration: float = GameConfig.TRANSITION_FADE
var _current_key: StringName = &""
var _current_path: String = ""

## 返回栈：每项 { "key": StringName, "path": String }
var _history: Array[Dictionary] = []


func _ready() -> void:
	_build_overlay()
	var tree := get_tree()
	if tree != null:
		_current_path = tree.current_scene.scene_file_path if tree.current_scene != null else ""
		_current_key = key_for_path(_current_path)

# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------


## 按 key 切场景（推荐）。默认淡入淡出并记入返回栈
func goto_scene(scene_key: StringName, fade: bool = true, remember: bool = true) -> Error:
	return await _goto(scene_key, scene_path_for(scene_key), fade, remember)


## 按 res:// 路径切场景；path 必须在 SCENES 中登记（避免散落硬编码路径）
func goto_path(scene_path: String, fade: bool = true, remember: bool = true) -> Error:
	var scene_key := key_for_path(scene_path)
	if scene_key == &"":
		push_error("[SceneRouter] 未登记的场景路径：%s" % scene_path)
		return ERR_DOES_NOT_EXIST
	return await _goto(scene_key, scene_path, fade, remember)


## 回上一场景（返回栈为空时什么也不做）
func go_back(fade: bool = true) -> Error:
	if _history.is_empty():
		push_warning("[SceneRouter] 返回栈为空")
		return ERR_DOES_NOT_EXIST
	var entry: Dictionary = _history.pop_back()
	# 跳过与当前场景相同的栈顶（连续跳同一场景时可能出现）
	if String(entry.get("key", "")) == String(_current_key) and not _history.is_empty():
		entry = _history.pop_back()
	return await _goto(StringName(entry.get("key", &"")), String(entry.get("path", "")), fade, false)


func can_go_back() -> bool:
	return not _history.is_empty()


## 清空返回栈（例如「新游戏」时）
func clear_history() -> void:
	_history.clear()


## 设置过场淡入淡出时长；0 表示瞬时（自检 / 无演出需求时用）
func set_fade_duration(seconds: float) -> void:
	_fade_duration = maxf(seconds, 0.0)


## 重载当前场景（读档失败提示「重试」用）
func reload_current(fade: bool = true) -> Error:
	if _current_key == &"":
		return ERR_DOES_NOT_EXIST
	return await _goto(_current_key, _current_path, fade, false)


## 退出游戏
func quit_game() -> void:
	get_tree().quit()


## 直接切到主菜单并清空返回栈
func goto_main_menu(fade: bool = true) -> Error:
	clear_history()
	return await goto_scene(&"main_menu", fade, false)

# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------


func scene_path_for(scene_key: StringName) -> String:
	return String(SCENES.get(scene_key, ""))


func has_scene(scene_key: StringName) -> bool:
	return SCENES.has(scene_key)


func key_for_path(scene_path: String) -> StringName:
	for key in SCENES.keys():
		if String(SCENES[key]) == scene_path:
			return key
	return &""


## 当前场景 key（未登记场景为空）
func current_scene_key() -> StringName:
	return _current_key


func current_scene_path() -> String:
	return _current_path


## 返回栈快照（调试 / 面包屑显示）
func history() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	snapshot.assign(_history)
	return snapshot

# ---------------------------------------------------------------------------
# 内部实现
# ---------------------------------------------------------------------------


func _goto(scene_key: StringName, scene_path: String, fade: bool, remember: bool) -> Error:
	if is_transitioning:
		push_warning("[SceneRouter] 正在切换场景，忽略重复请求：%s" % scene_key)
		return ERR_BUSY
	if scene_path.is_empty():
		push_error("[SceneRouter] 未知场景 key：%s" % scene_key)
		return ERR_DOES_NOT_EXIST
	if not ResourceLoader.exists(scene_path):
		push_error("[SceneRouter] 场景文件不存在：%s" % scene_path)
		return ERR_FILE_NOT_FOUND

	is_transitioning = true
	EventBus.scene_change_started.emit(scene_key, scene_path)

	if fade:
		await _fade_to(1.0)

	var previous_key := _current_key
	var previous_path := _current_path
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("[SceneRouter] 切换场景失败（%d）：%s" % [err, scene_path])
		if fade:
			await _fade_to(0.0)
		is_transitioning = false
		return err

	# change_scene_to_file 是延迟到帧末生效的，等一帧后再更新内部状态
	await get_tree().process_frame
	if remember and previous_path != "" and previous_path != scene_path:
		_history.append({ "key": previous_key, "path": previous_path })

	_current_key = scene_key
	_current_path = scene_path

	if fade:
		await _fade_to(0.0)

	is_transitioning = false
	EventBus.scene_changed.emit(scene_key, scene_path)
	return OK


## 遮罩：常驻 CanvasLayer + 全屏 ColorRect（鼠标事件在遮罩期间被挡住，防连点）
func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "TransitionOverlay"
	_overlay.layer = OVERLAY_LAYER
	add_child(_overlay)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_fade_rect)


func _fade_to(alpha: float) -> void:
	if _fade_rect == null:
		return
	# 遮罩生效期间吞掉输入
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP if alpha > 0.0 else Control.MOUSE_FILTER_IGNORE
	if _fade_duration <= 0.0:
		_fade_rect.color.a = alpha
		return
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", alpha, _fade_duration)
	await tween.finished
