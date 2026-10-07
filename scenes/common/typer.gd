extends Label

## Typer —— 打字机：按 id 从 JSON 读取对话，以**固定间隔逐字**显示在 Label 上。
##
## 设计约定：
##   - 「固定间隔」按时间累加实现，与帧率无关：无论 30fps 还是 144fps，
##     每字之间的**真实时间**都等于 `char_duration`，不会因为帧率不同而变快变慢。
##   - 逐字显示用 Label 自带的 `visible_characters`，而不是每帧拼一个新字符串。
##     前者只改一个计数、由引擎负责裁切，自动换行 / 中文 / 表情都不会错位；
##     后者每帧 `substr` 会退化成 O(n²)，长文本会拖慢。
##   - 本脚本**只管一个字一个字地显示**：不加载场景、不发场景跳转、不读输入。
##     一句话打完之后要做什么（等确认 / 播下一句 / 关掉对话框）由调用方决定。
##
## 最小用法（把本脚本挂到对话框里的正文 Label 上）：
##     var typer = $Dialoguer/Dialogue          # 该节点已挂本脚本
##     typer.char_duration = 0.03               # 固定间隔
##     typer.load_dialogue("second")            # 从 res://data/dialogue.json 取 id 为 second 的那段
##     typer.dialogue_finished.connect(_on_done)
##     typer.start_dialogue()
##
## 也可以直接实例化 scenes/common/typer.tscn（根节点即挂本脚本的 Label）。

## 单个字间隔上限（秒）
@export_range(0.001, 1.0, 0.001, "suffix:s") var char_duration: float = 0.03

## 单帧可累计的最大时间（秒）。超过此值的 delta 会被截断，见 _process 说明。
@export_range(0.0, 2.0, 0.01, "suffix:s") var max_frame_delta: float = 0.1

## 对话数据文件路径
@export_file("*.json") var dialogue_path: String = "res://data/dialogue.json"

## 进入树后自动开始播放（便于单独 F6 运行本场景调试）
@export var autostart: bool = false

## 一行打完后自动接着打下一行；false 时需由调用方调 next_line()
@export var auto_next: bool = true

## 整段对话播完
signal dialogue_finished

## 开始播放某一行；index 为行号（0 起）
signal line_started(index: int, text: String)

## 某一行逐字显示完毕
signal line_finished(index: int)

## 已解析的对话行：[{ "speaker_name": String, "text": String }, ...]
var lines: Array[Dictionary] = []

## 文件里所有对话：id -> 行数组
var _conversations: Dictionary = {}

## 当前行号；-1 表示还没开始
var current_index: int = -1

## 当前行是否正在逐字显示
var is_typing: bool = false

## 距下一个字还需等待的秒数（累加器）
var _char_timer: float = 0.0

## 当前行完整文本（含 BBCode 时是原文，长度口径与 visible_characters 一致）
var _full_text: String = ""


func _ready() -> void:
	# 先清空，避免编辑器里预览的静态文本在开局时露出（此时 visible_characters 还是 -1）
	text = ""
	visible_characters = 0
	set_process(false)
	if lines.is_empty():
		load_dialogue()
	if autostart and not lines.is_empty():
		start_dialogue()


func _process(delta: float) -> void:
	# 固定间隔累加：不足一个间隔就攒着，攒够几次就推进几个字。
	# 这样即便某帧卡顿（delta 很大）也不会丢字，且与帧率解耦。
	#
	# 但 delta 需要截断：引擎冷启动的第一帧、或窗口被拖动/最小化后恢复的那一帧，
	# delta 会是正常帧的几十倍（实测约 0.13s），不截断的话此处会一次蹦出好几个字，
	# 看起来像「没有逐字」。截断相当于把这类异常帧按最多 max_frame_delta 计。
	_char_timer += _clamp_frame_delta(delta)
	while is_typing and _char_timer >= char_duration:
		_char_timer -= char_duration
		_reveal_next_char()


## 把异常大的帧间隔截断到 max_frame_delta（0 表示不截断）
func _clamp_frame_delta(delta: float) -> float:
	if max_frame_delta > 0.0 and delta > max_frame_delta:
		return max_frame_delta
	return delta

# ---------------------------------------------------------------------------
# 数据加载
# ---------------------------------------------------------------------------


## 读取对话文件（dialogue_path），按 id 选出其中一段对话，成功返回 true。
##
## 文件支持两种写法：
##
##   1) 行数组，每行带 "id"（推荐）——相同 id 的行属于同一段对话：
##      [
##        { "id": "first",  "speaker_name": "棍木", "text": "..." },
##        { "id": "first",  "speaker_name": "棍木", "text": "..." },
##        { "id": "second", "speaker_name": "勇者", "text": "..." }
##      ]
##
##   2) 顶层对象，每个键是一段对话：
##      { "first": [ { "speaker_name": "...", "text": "..." } ], "second": [ ... ] }
##
## 兼容旧写法：行数组里都不带 "id" 时，整份文件算作一段对话（id 为 ""）。
##
## 行的字段：文本取 "text"，说话人取 "speaker_name"；"id" 决定归属。
## 也接受纯字符串简写行（归入 id ""）。
func load_dialogue(id: String = "") -> bool:
	lines.clear()
	current_index = -1
	is_typing = false
	set_process(false)

	if _conversations.is_empty() and not _load_all():
		return false

	var chosen := id
	if chosen.is_empty():
		# 没指定 id：取第一个（字典保持 JSON 里的书写顺序）
		chosen = String(_conversations.keys()[0])

	if not _conversations.has(chosen):
		push_error("[Typer] %s 里没有 id 为「%s」的对话。现有 id：%s" % [
			dialogue_path, chosen, ", ".join(list_dialogue_ids())])
		return false

	# 必须复制：Dictionary 取出来的数组是**同一个对象**，
	# 直接 lines = ... 会让 lines 与 _conversations[chosen] 互为别名，
	# 而本函数开头的 lines.clear() 就会把文件里那一段对话原地清空，
	# 导致「先载入 A、再查一个不存在的 id」之后 A 变空，且无法再次载入。
	lines = _copy_lines(_conversations[chosen])
	if lines.is_empty():
		push_warning("[Typer] 对话「%s」里没有任何行" % chosen)
		return false
	return true


## 复制一份行数组（保持 Array[Dictionary] 类型，元素为不可变字典，浅拷贝即可）
func _copy_lines(src: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if src is Array:
		for item in (src as Array):
			if item is Dictionary:
				out.append(item)
	return out


## 文件里所有可用的对话 id（按书写顺序）
func list_dialogue_ids() -> Array[String]:
	if _conversations.is_empty():
		_load_all()
	var ids: Array[String] = []
	for key in _conversations.keys():
		ids.append(String(key))
	return ids


## 读取并解析整个对话文件，填进 _conversations；成功返回 true
func _load_all() -> bool:
	_conversations.clear()
	var parsed: Variant = _read_json(dialogue_path)
	if parsed == null:
		return false

	if parsed is Array:
		# 行数组：每行带 "id" 时按 id 归成多段；都不带 id 时整份算一段
		_conversations = _group_by_id(parsed, true)
		return not _conversations.is_empty()

	if parsed is Dictionary:
		var dict := parsed as Dictionary
		# 旧写法：单个「行」对象（有 text 字段，没有 id）
		if dict.has("text") and not dict.has("id"):
			var one := _normalize_lines([dict])
			if not one.is_empty():
				_conversations[""] = one
			return not _conversations.is_empty()
		# 嵌套写法：{ "second": [ 行... ], ... }
		for key in dict.keys():
			var value: Variant = dict[key]
			if value is Array:
				var conv := _normalize_lines(value)
				if conv.is_empty():
					push_warning("[Typer] 对话「%s」为空或没有可用行，已跳过" % key)
					continue
				_conversations[String(key)] = conv
			else:
				push_warning("[Typer] 对话「%s」不是数组，已跳过" % key)
		if _conversations.is_empty():
			push_error("[Typer] %s 里没有任何可用对话" % dialogue_path)
		return not _conversations.is_empty()

	push_error("[Typer] %s 顶层必须是对象或数组" % dialogue_path)
	return false


## 把「每行带 id」的行数组按 id 归成若干段对话
func _group_by_id(raw_lines: Array, use_id: bool) -> Dictionary:
	var grouped: Dictionary = {}
	for entry in raw_lines:
		var line: Dictionary
		var id := ""
		if entry is Dictionary:
			line = _normalize_line(entry)
			if use_id:
				id = String((entry as Dictionary).get("id", ""))
		elif entry is String:
			line = { "speaker_name": "", "text": entry }
		else:
			push_warning("[Typer] 有一行不是对象或字符串，已跳过")
			continue

		# 注意：不能写成 grouped[id].append(...)。
		# 取出来的是 Array[Dictionary] 的**副本**，对副本 append 会被丢弃
		# （实测只有最后一组能留下、且内容是别组的）。必须取到局部变量、
		# append 后再写回字典。
		var conv: Array[Dictionary]
		if grouped.has(id):
			conv = grouped[id]
		else:
			conv = [] as Array[Dictionary]
		conv.append(line)
		grouped[id] = conv
	return grouped


## 把 JSON 里的行数组规整成 [{ speaker_name, text }, ...]
func _normalize_lines(raw_lines: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in raw_lines:
		if entry is Dictionary:
			out.append(_normalize_line(entry))
		elif entry is String:
			# 纯字符串简写：["第一句", "第二句"]
			out.append({ "speaker_name": "", "text": entry })
		else:
			push_warning("[Typer] 有一行不是对象或字符串，已跳过")
	return out

# ---------------------------------------------------------------------------
# 播放控制
# ---------------------------------------------------------------------------


## 从头开始播放整段对话
func start_dialogue() -> void:
	if lines.is_empty():
		push_warning("[Typer] 对话为空，先调用 load_dialogue()")
		return
	start_line(0)


## 跳到指定行；越界则视为整段结束
func start_line(index: int) -> void:
	if index < 0 or index >= lines.size():
		current_index = -1
		is_typing = false
		set_process(false)
		dialogue_finished.emit()
		return

	current_index = index
	var line: Dictionary = lines[index]
	_full_text = String(line.get("text", ""))

	# 先刷说话人再出字：本行该显示谁的名字
	if _speaker_label != null:
		_speaker_label.text = String(line.get("speaker_name", ""))

	# 一次性写入完整文本，再用 visible_characters 控制露出进度
	text = _full_text
	visible_characters = 0
	_char_timer = 0.0

	line_started.emit(current_index, _full_text)

	# 空行 / 间隔非法：直接算作打完了，免得卡在这一行
	if _full_text.is_empty() or char_duration <= 0.0:
		_finish_line()
		return

	is_typing = true
	set_process(true)


## 播下一行
func next_line() -> void:
	if current_index < 0:
		start_line(0)
		return
	start_line(current_index + 1)


## 「跳过」：立刻显示完当前行并结束该行（不跳到下一行）
func skip_line() -> void:
	if is_typing:
		_finish_line()


## 当前行的完整文本
func get_full_text() -> String:
	return _full_text


## 按 `$Dialoguer/Dialogue` / `$Dialoguer/Name` 的既有约定，设置说话人名字。
## 本脚本挂在正文 Label 上，说话人 Label 是兄弟节点，故需由外部指定目标节点。
func set_speaker_label(label: Label) -> void:
	_speaker_label = label
	if label != null and current_index >= 0 and current_index < lines.size():
		label.text = String(lines[current_index].get("speaker_name", ""))


var _speaker_label: Label = null

# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------


func _reveal_next_char() -> void:
	visible_characters += 1
	if visible_characters >= _full_text.length():
		_finish_line()


func _finish_line() -> void:
	visible_characters = _full_text.length()
	is_typing = false
	_char_timer = 0.0
	set_process(false)
	line_finished.emit(current_index)
	# 最后一行打完 = 整段结束。这里必须发 dialogue_finished，
	# 否则调用方（如对话框自动收起）永远等不到这个信号。
	if current_index >= lines.size() - 1:
		current_index = -1
		dialogue_finished.emit()
	elif auto_next:
		# 顺延到下一行；start_line 会重新打开 _process
		start_line(current_index + 1)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("[Typer] 找不到对话文件：%s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[Typer] 打不开对话文件：%s（错误 %d）" % [path, FileAccess.get_open_error()])
		return null
	var raw := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(raw)
	if err != OK:
		push_error("[Typer] %s 第 %d 行 JSON 解析失败：%s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _normalize_line(entry: Dictionary) -> Dictionary:
	return {
		"speaker_name": String(entry.get("speaker_name", entry.get("speaker", ""))),
		"text": String(entry.get("text", entry.get("dialogue", ""))),
	}
