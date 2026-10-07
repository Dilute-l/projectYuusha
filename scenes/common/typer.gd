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
## 文本里支持的动作语法：
##   `^n`  在此处额外停顿 n * PAUSE_UNIT 秒（默认 0.2s/单位），控制记号不显示。
##   标点 / 空白 / 数字默认不发声（见 DEFAULT_SILENT_CHARS），但仍正常显示。
##
## 最小用法（把本脚本挂到对话框里的正文 Label 上）：
##     var typer = $Dialoguer/Dialogue          # 该节点已挂本脚本
##     typer.load_dialogue("second")            # 从 res://data/dialogue.json 取 id 为 second 的那段
##     # 间隔由 JSON 决定；也可以在 JSON 里没写时手动指定：
##     # typer.char_duration = typer.DEFAULT_CHAR_DURATION
##     typer.dialogue_finished.connect(_on_done)
##     typer.start_dialogue()
##
## 也可以直接实例化 scenes/common/typer.tscn（根节点即挂本脚本的 Label）。

## 默认的字间隔（秒）。节点上的 `char_duration` 初值即此值；
## JSON 里没写间隔时也回退到它。
const DEFAULT_CHAR_DURATION: float = 0.03

## 停顿语法 `^n` 的单位：n 个 `^n` 单位 = n * PAUSE_UNIT 秒。
## 例：「你好^3」= 打完「好」之后停 3 * 0.2 = 0.6 秒。
const PAUSE_UNIT: float = 0.2

## 默认的逐字音效（config 里没写 sound 时用它）
const DEFAULT_SOUND: StringName = &"normal"

## 音效目录：assets/sound/text/
const SOUND_DIR: String = "res://assets/sound/text"

## 音效名 -> 文件名（不含扩展名）。显示名与文件名不一致时在这里映射。
const SOUND_FILES: Dictionary = {
	&"no": "normal",
	&"su": "susie",
}

# ---------------------------------------------------------------------------
# 动作语法：不发声的字符（SILENT_CHAR）
# ---------------------------------------------------------------------------
#
# 逐字音效不应该对每个字符都响：标点、空白、数字本身没有发音，
# 给它们配音效会变成「哔哩哔啦」的杂音。下面三组常量就是「不发声」的字符集合。
#
# 未在 config 里指定时使用这三组的并集。config 里可以覆盖：
#   "silent": "，。！？"        替换为自定义集合（那就只有这些不发声）
#   "extra_silent": "……——"     在三组默认之外再追加
#
# 另外空字符串 "" 是置空标记：会把静音集合清空（等于「每个字符都发声」）。

## 空白：空格、制表、换行本身都是「不出声」的
const SILENT_WHITESPACE: String = " \t\r\n\u3000"

## 标点：ASCII 标点、CJK 标点、以及常见的中文引号/书名号等
const SILENT_PUNCTUATION: String = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~" \
	+ "，。、！？；：「」『』（）〔〕【】《》〈〉…—～·　" \
	+ "“”‘’" \
	+ "！？。，、；：（）《》"

## 数字：阿拉伯数字与全角数字
const SILENT_DIGITS: String = "0123456789０１２３４５６７８９"

## 默认静音集合（三组的并集）。运行时真正用的是 _silent_chars。
const DEFAULT_SILENT_CHARS: String = SILENT_WHITESPACE + SILENT_PUNCTUATION + SILENT_DIGITS

## 单个字间隔上限（秒）。节点的初始值 = DEFAULT_CHAR_DURATION；
## 可在 Inspector 里调，也可由 JSON 按段/按行覆盖（见 load_dialogue 说明）。
@export_range(0.001, 1.0, 0.001, "suffix:s") var char_duration: float = DEFAULT_CHAR_DURATION

## 单帧可累计的最大时间（秒）。超过此值的 delta 会被截断，见 _process 说明。
@export_range(0.0, 2.0, 0.01, "suffix:s") var max_frame_delta: float = 0.1

## 对话数据文件路径
@export_file("*.json") var dialogue_path: String = "res://data/dialogue.json"

## 进入树后自动开始播放（便于单独 F6 运行本场景调试）
@export var autostart: bool = false

## 打开/关闭逐字音效
@export var sound_enabled: bool = true

## 逐字音效音量（dB，相对基准的微调）
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var sound_volume_db: float = 0.0

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

## 每段对话自己的字间隔（秒）：id -> float。没写的段回退到 char_duration。
var _segment_char_durations: Dictionary = {}

## 每段对话自己的逐字音效名：id -> StringName。没写的段回退到 DEFAULT_SOUND。
var _segment_sounds: Dictionary = {}

## 每段对话自己的静音字符集合：id -> String。没写的段回退到 DEFAULT_SILENT_CHARS。
var _segment_silents: Dictionary = {}

## 当前这段对话的基准字间隔（段级或默认）。行级覆盖只临时生效，每行开始时复位到它。
var _base_char_duration: float = DEFAULT_CHAR_DURATION

## 当前这段对话用的音效名（config.sound，缺省为 DEFAULT_SOUND）
var char_sound: StringName = DEFAULT_SOUND

## 当前生效的静音字符集合（动作语法：这些字符不发声）。
## 由 load_dialogue() 按 config 的 silent / extra_silent 决定，缺省为 DEFAULT_SILENT_CHARS。
var _silent_chars: String = DEFAULT_SILENT_CHARS

## 音效资源路径缓存：音效名 -> res:// 路径
var _sound_paths: Dictionary = {}

## 已加载的音效资源缓存：路径 -> AudioStream
var _sound_cache: Dictionary = {}

## 当前行号；-1 表示还没开始
var current_index: int = -1

## 当前行是否正在逐字显示
var is_typing: bool = false

## 距下一个字还需等待的秒数（累加器）
var _char_timer: float = 0.0

## 当前行完整文本（**已剥掉 `^n` 控制记号**，与 Label 上显示的内容一致）
var _full_text: String = ""

## 当前行经过解析的字序列：`^n` 记号被剥掉，换成每个字「之前」的额外停顿
var _op_chars: Array[String] = []
var _op_delays: Array[float] = []

## 行尾遗留的停顿（`^2` 写在整行最后时）
var _trailing_pause: float = 0.0

## 当前字「之前」要额外等待的秒数（由 _op_delays 取用）
var _pending_delay: float = 0.0

## 正在等待的停顿剩余秒数（> 0 时不推进任何字）
var _pause_left: float = 0.0

## 行首停顿：进 _process 时再转成 _pause_left，避免被 _parse_line 重置
var _leading_wait: float = 0.0


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
	# 本帧实际计入的时长（已截断异常大的 delta）
	var d := _clamp_frame_delta(delta)

	# ^n 停顿：停顿期间**不推进任何字**，直到等待时间耗尽。
	# 注意：不能把停顿加进 _char_timer —— 那是「该露出几个字」的预算，
	# 加上去反而会把剩下的字一口气全推出来（等同于没有停顿）。
	if _pause_left > 0.0:
		_pause_left -= d
		if _pause_left <= 0.0 and not is_typing:
			# 停顿走完且这一行已经没有字要出了（行首/行尾停顿的情况）
			_finish_line()
		return

	# 行首的 ^n：先等够再出第一个字
	if _leading_wait > 0.0:
		_pause_left = _leading_wait
		_leading_wait = 0.0
		_pause_left -= d
		return

	# 整行没有任何可见字符（写成 "^2" 这种只有停顿记号的行）：
	# 仍然要先把行尾停顿等完，再算这一行结束。否则会「零耗时」通过。
	if _full_text.is_empty():
		_pause_left = _trailing_pause
		_trailing_pause = 0.0
		if _pause_left > 0.0:
			_pause_left -= d
			return
		_finish_line()
		return

	_char_timer += d

	# 一帧内可能推进多个字（掉帧/预热），但音效每帧最多响一次：
	# 否则同一瞬间叠好几个相同音效，听感上只会变成噪音。
	# 另外只有「会发声」的字符才算数——标点/空白/数字等静音字符不触发音效，
	# 这样一句话里全是标点时也不会响。
	var voiced := false
	while is_typing and _char_timer >= char_duration:
		_char_timer -= char_duration
		var was_last: bool = visible_characters == _full_text.length() - 1
		if _reveal_next_char():
			voiced = true
		# ^n 停顿记在下一个字上：转成暂停状态，循环到此为止
		if _pending_delay > 0.0:
			_pause_left = _pending_delay
			_pending_delay = 0.0
			break
		if was_last:
			# 整行最后一个字已经露出。_reveal_next_char() 内部已经调过 _finish_line()，
			# 那一并把 set_process(false) 关掉了 —— 所以「行尾还有 ^n」必须在这里
			# 就地转成暂停状态并重新打开 _process，否则那个停顿永远不会被执行。
			if _trailing_pause > 0.0:
				_pause_left = _trailing_pause
				_trailing_pause = 0.0
				is_typing = true
				set_process(true)
			break
	if voiced:
		_play_char_sound()


## 把异常大的帧间隔截断到 max_frame_delta（0 表示不截断）。
## 引擎冷启动的第一帧、或窗口被拖动/最小化后恢复的那一帧，delta 会是正常帧的
## 几十倍（实测约 0.13s），不截断的话一次就会蹦出好几个字，看起来像「没有逐字」。


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
##
## 字间隔（char_duration，单位秒）可以从两个层级指定，粒度细的优先：
##
##   段级 —— 在段里放一个带 "config" 的对象（位置不限，建议放段首）：
##       { "id": "second", "config": { "char_duration": 0.02 } }
##       顶层对象写法同理： { "second": [ { "config": { "char_duration": 0.02 } }, ... ] }
##
##   行级 —— 直接写在某一行的对象里，只影响该行：
##       { "id": "second", "text": "...", "char_duration": 0.08 }
##
## 都没写时使用节点上的 `char_duration`（初值 = DEFAULT_CHAR_DURATION）。
## 每次 load_dialogue() 都会按所选段重新设定间隔，所以两段对话可以不同速。
##
## 逐字音效（sound）同样在段级 config 里指定，每打出一个字响一次：
##
##   { "id": "second", "config": { "char_duration": 0.02, "sound": "su" } }
##
## 音效名 -> 文件的映射见 SOUND_FILES： "normal" -> normal.wav（默认）、"su" -> susie.wav。
## 没写 sound 的段用 DEFAULT_SOUND。可用 typer.sound_enabled = false 整体关掉。
##
## 动作语法：静音字符（SILENT_CHAR）。标点 / 空白 / 数字默认**不发声**
## （它们本来就「没有发音」，配音效只会变成杂音），但仍然按间隔正常显示。
## 默认集合见 DEFAULT_SILENT_CHARS，可在 config 里覆盖：
##
##   { "id": "x", "config": { "silent": "，。！？" } }       替换为自定义集合
##   { "id": "x", "config": { "extra_silent": "……——" } }    在默认集合外追加
##   { "id": "x", "config": { "silent": "" } }               明确置空（每个字符都发声）
##
## 动作语法：停顿。文本里写 `^n`（n 为十进制数字）表示在此处额外停顿
## n * PAUSE_UNIT 秒（PAUSE_UNIT 默认 0.2，即 `^3` 停 0.6 秒）：
##
##   "你好^3，欢迎。^10"   → 「好」之后停 0.6s，「。」之后停 2.0s
##
## `^n` 是控制记号，**不会显示出来**，也不影响字符间隔本身。
## 写在行首则先停顿再出第一个字；写在行尾则整行打完后还要停一下才算结束。
## 单独的 `^`（后面不是数字）按普通字符原样显示。
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

	# 应用这一段的字间隔：JSON 里写了就用它，没写则回到默认间隔。
	var segment_duration := _as_positive_float(_segment_char_durations.get(chosen))
	_base_char_duration = segment_duration if segment_duration > 0.0 else DEFAULT_CHAR_DURATION
	char_duration = _base_char_duration
	# 同理应用这一段的逐字音效：写了 sound 就用它，没写则用默认音效。
	char_sound = _segment_sounds.get(chosen, DEFAULT_SOUND)
	# 以及这一段的静音字符集合（动作语法 SILENT_CHAR）。
	_silent_chars = _segment_silents.get(chosen, DEFAULT_SILENT_CHARS)
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
		var grouped := _group_by_id(parsed, true)
		_conversations = grouped.get("lines", {})
		for key in grouped.get("durations", {}).keys():
			_segment_char_durations[key] = grouped["durations"][key]
		for key in grouped.get("sounds", {}).keys():
			_segment_sounds[key] = grouped["sounds"][key]
		for key in grouped.get("silents", {}).keys():
			_segment_silents[key] = grouped["silents"][key]
		return not _conversations.is_empty()

	if parsed is Dictionary:
		var dict := parsed as Dictionary
		# 旧写法：单个「行」对象（有 text 字段，没有 id）
		if dict.has("text") and not dict.has("id"):
			var one := _normalize_lines([dict])
			if not one.is_empty():
				_conversations[""] = one
			return not _conversations.is_empty()
		# 嵌套写法：{ "second": [ 配置?, 行... ], ... }
		for key in dict.keys():
			var value: Variant = dict[key]
			if value is Array:
				var seg := _normalize_segment(value)
				var conv: Array[Dictionary] = seg["lines"]
				if conv.is_empty():
					push_warning("[Typer] 对话「%s」为空或没有可用行，已跳过" % key)
					continue
				var name := String(key)
				_conversations[name] = conv
				if seg["char_duration"] > 0.0:
					_segment_char_durations[name] = seg["char_duration"]
				if seg["sound"] != DEFAULT_SOUND:
					_segment_sounds[name] = seg["sound"]
				if seg["silent"] != DEFAULT_SILENT_CHARS:
					_segment_silents[name] = seg["silent"]
			else:
				push_warning("[Typer] 对话「%s」不是数组，已跳过" % key)
		if _conversations.is_empty():
			push_error("[Typer] %s 里没有任何可用对话" % dialogue_path)
		return not _conversations.is_empty()

	push_error("[Typer] %s 顶层必须是对象或数组" % dialogue_path)
	return false


## 把「每行带 id」的行数组按 id 归成若干段对话。
## 返回 { "lines": { id -> Array[Dictionary] },
##        "durations": { id -> float }, "sounds": { id -> StringName } }。
## durations / sounds 只包含该段显式写了 config 对应项的条目。
func _group_by_id(raw_lines: Array, use_id: bool) -> Dictionary:
	var grouped: Dictionary = {}
	var durations: Dictionary = {}
	var sounds: Dictionary = {}
	var silents: Dictionary = {}
	for entry in raw_lines:
		if entry is Dictionary and (entry as Dictionary).has("config"):
			# 段级配置。id 决定它归哪一段；没写 id 则视为全局默认段（""）
			var cfg_id := String((entry as Dictionary).get("id", ""))
			if use_id:
				var cfg := _read_segment_config(entry)
				var cfg_duration := _as_positive_float(cfg.get("char_duration"))
				if cfg_duration > 0.0:
					durations[cfg_id] = cfg_duration
				var cfg_sound := _read_config_sound(cfg)
				if cfg_sound != DEFAULT_SOUND:
					sounds[cfg_id] = cfg_sound
				var cfg_silent := _resolve_silent_chars(cfg)
				if cfg_silent != DEFAULT_SILENT_CHARS:
					silents[cfg_id] = cfg_silent
			continue

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
	return { "lines": grouped, "durations": durations, "sounds": sounds, "silents": silents }


## 把 JSON 里的行数组规整成 [{ speaker_name, text, char_duration? }, ...]
func _normalize_lines(raw_lines: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in raw_lines:
		if entry is Dictionary:
			if (entry as Dictionary).has("config"):
				continue  # 段级配置由 _normalize_segment / _group_by_id 处理
			out.append(_normalize_line(entry))
		elif entry is String:
			# 纯字符串简写：["第一句", "第二句"]
			out.append({ "speaker_name": "", "text": entry })
		else:
			push_warning("[Typer] 有一行不是对象或字符串，已跳过")
	return out


## 规整一段对话：
## { "lines": Array[Dictionary], "char_duration": float,
##   "sound": StringName, "silent": String }
## char_duration 为 0.0 表示没有单独指定间隔；sound 缺省 DEFAULT_SOUND；
## silent 为本段生效的静音字符集合（缺省 DEFAULT_SILENT_CHARS）。
func _normalize_segment(raw_lines: Array) -> Dictionary:
	var cfg := _read_segment_config_array(raw_lines)
	return {
		"lines": _normalize_lines(raw_lines),
		"char_duration": _as_positive_float(cfg.get("char_duration")),
		"sound": _read_config_sound(cfg),
		"silent": _resolve_silent_chars(cfg),
	}


## 在一段的行数组里找段级配置。约定：任何带 "config" 键的对象都是配置，
## 不当作对话行。推荐写在段首，但写在任意位置都能被识别。
func _read_segment_config_array(raw_lines: Array) -> Dictionary:
	for entry in raw_lines:
		if entry is Dictionary and (entry as Dictionary).has("config"):
			return _read_segment_config(entry)
	return {}


## 取出一条段的 config 对象本体（未写则返回空字典）。
##   { "config": { "char_duration": 0.02, "sound": "su" } }
## 也接受 { "config": 0.02 } 这种只写间隔的简写（等价于 char_duration）。
func _read_segment_config(entry: Dictionary) -> Dictionary:
	var cfg: Variant = entry.get("config")
	if cfg is Dictionary:
		return cfg as Dictionary
	if cfg is float or cfg is int:
		return { "char_duration": cfg }
	return {}


## 从 config 里取音效名；未写或非法则回退到 DEFAULT_SOUND
func _read_config_sound(cfg: Dictionary) -> StringName:
	var raw: Variant = cfg.get("sound")
	if raw == null:
		return DEFAULT_SOUND
	var name := StringName(str(raw).strip_edges())
	if name == &"":
		return DEFAULT_SOUND
	return name


## 把 JSON 数字转成正的 float；缺失或非法一律返回 0.0（表示「未指定」）
func _as_positive_float(value: Variant) -> float:
	if value is float or value is int:
		var f := float(value)
		if f > 0.0:
			return f
	return 0.0

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
	# 解析动作语法：剥掉 ^n 控制记号，把停顿记到对应字符上
	_parse_line(String(line.get("text", "")))

	# 先刷说话人再出字：本行该显示谁的名字
	if _speaker_label != null:
		_speaker_label.text = String(line.get("speaker_name", ""))

	# 每行开始先把间隔复位到本段的基准值，避免上一行的行级覆盖「漏」到下一行
	char_duration = _base_char_duration
	# 本行若单独写了 char_duration，则只在这一行临时覆盖
	var line_duration: Variant = line.get("char_duration")
	if line_duration is float or line_duration is int:
		var ld := float(line_duration)
		if ld > 0.0:
			char_duration = ld

	# 一次性写入完整文本，再用 visible_characters 控制露出进度
	text = _full_text
	visible_characters = 0
	_char_timer = 0.0
	# 行首的 ^n 由 _parse_line 记入 _leading_wait，进 _process 后再转成暂停状态

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


## 当前是否正处于一段对话中（正在逐字，或已打完本行、等待推进）
func is_active() -> bool:
	return current_index >= 0


## 玩家点击时的默认推进：
##   本行还在逐字 → 立刻显示完；
##   本行已打完   → 进入下一行（最后一行则结束整段并发 dialogue_finished）
func advance() -> void:
	if is_typing:
		skip_line()
	else:
		next_line()


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


## 露出下一个字。返回「这个字是否应该发声」（静音字符返回 false）。
## 注意：静音字符仍然会按间隔逐个露出，只是不发声——显示速度不变。
func _reveal_next_char() -> bool:
	var index := visible_characters
	var char := _char_at(index)
	visible_characters += 1
	if visible_characters >= _full_text.length():
		_finish_line()
		_pending_delay = 0.0
	else:
		# 下一个字之前要额外等的停顿（来自 ^n）
		_pending_delay = _op_delays[index + 1] if index + 1 < _op_delays.size() else 0.0
	return is_voiced_char(char)


## 取第 index 个字符（越界返回空串）。
## visible_characters 的口径就是「已显示几个字符」，所以它正好是下一个要显示的字符下标。
func _char_at(index: int) -> String:
	if index < 0 or index >= _op_chars.size():
		return ""
	return _op_chars[index]


## 解析一行的动作语法：
##   `^n`  → 在此处停顿 n * PAUSE_UNIT 秒；n 为十进制数字（可多位）
##   单独的 `^`（后面不是数字）→ 当作普通字符原样显示，便于写出真的尖号
## 控制记号不会出现在显示文本里，只影响推进节奏。
func _parse_line(raw: String) -> void:
	_op_chars.clear()
	_op_delays.clear()
	_trailing_pause = 0.0
	_pending_delay = 0.0
	_pause_left = 0.0
	_leading_wait = 0.0

	var pending := 0.0
	var i := 0
	var total := raw.length()
	while i < total:
		var ch := raw[i]
		if ch == "^":
			var digits := _digits_at(raw, i + 1)
			if not digits.is_empty():
				pending += float(digits.to_int()) * PAUSE_UNIT
				i += 1 + digits.length()
				continue
		_op_chars.append(ch)
		_op_delays.append(pending)
		pending = 0.0
		i += 1

	# ^n 写在行尾：这段停顿没有「下一个字」可挂，单独记下来
	_trailing_pause = pending
	if not _op_delays.is_empty():
		_leading_wait = _op_delays[0]
	_full_text = "".join(_op_chars)


## 从 from 开始连续读到的十进制数字串（没有数字则返回空串）
func _digits_at(text: String, from: int) -> String:
	var out := ""
	var i := from
	while i < text.length():
		var ch := text[i]
		if ch >= "0" and ch <= "9":
			out += ch
			i += 1
		else:
			break
	return out


## 该字符是否应该发声：默认音效开启、且不在静音集合里
func is_voiced_char(char: String) -> bool:
	if not sound_enabled or char.is_empty():
		return false
	return not is_silent_char(char)


## 该字符是否属于静音集合（动作语法 SILENT_CHAR）
func is_silent_char(char: String) -> bool:
	return _silent_chars.contains(char)


## 由 config 决定本段的静音字符集合（动作语法）。
## 没写 silent / extra_silent 时用 DEFAULT_SILENT_CHARS。
func _resolve_silent_chars(cfg: Dictionary) -> String:
	var has_silent: bool = cfg.has("silent")
	var has_extra: bool = cfg.has("extra_silent")
	if not has_silent and not has_extra:
		return DEFAULT_SILENT_CHARS
	var result: String = String(cfg.get("silent", "")) if has_silent else DEFAULT_SILENT_CHARS
	if has_extra:
		result += String(cfg.get("extra_silent", ""))
	return result


## 播放一次逐字音效。走 AudioService 的 SFX 池（8 路，自动抢占），
## 所以不需要自己管理 AudioStreamPlayer。
func _play_char_sound() -> bool:
	if not sound_enabled:
		return false
	var stream := _resolve_sound(char_sound)
	if stream == null:
		return false
	return AudioService.play_sfx(stream, sound_volume_db)


## 音效名 -> AudioStream（带缓存）。找不到对应文件时警告并返回 null。
func _resolve_sound(sound_name: StringName) -> AudioStream:
	var path := sound_path_for(sound_name)
	if path.is_empty():
		push_warning("[Typer] 未知音效名「%s」，可用：%s" % [
			sound_name, ", ".join(SOUND_FILES.keys())])
		return null
	if _sound_cache.has(path):
		return _sound_cache[path]
	if not ResourceLoader.exists(path):
		push_warning("[Typer] 音效文件不存在：%s" % path)
		_sound_cache[path] = null
		return null
	var stream := ResourceLoader.load(path)
	if not (stream is AudioStream):
		push_warning("[Typer] 不是音频资源：%s" % path)
		_sound_cache[path] = null
		return null
	_sound_cache[path] = stream
	return stream


## 音效名对应的资源路径；未知名字返回空串。
##   normal -> res://assets/sound/text/normal.wav
##   su     -> res://assets/sound/text/susie.wav
func sound_path_for(sound_name: StringName) -> String:
	if not SOUND_FILES.has(sound_name):
		return ""
	return "%s/%s.wav" % [SOUND_DIR, SOUND_FILES[sound_name]]


func _finish_line() -> void:
	visible_characters = _full_text.length()
	is_typing = false
	_char_timer = 0.0
	set_process(false)
	# 行级覆盖只在本行有效：本行结束就回到本段的基准间隔，
	# 否则 char_duration 会一直停留在被覆盖的值上（外部读到的就不是「本段间隔」）。
	char_duration = _base_char_duration
	line_finished.emit(current_index)
	# 本行打完后**不自动进入下一行**：由调用方（dialoguer）在玩家点击时推进。
	# 所以这里只报告「这一行打完了」，不触碰 current_index，
	# 也不发 dialogue_finished —— 调用方据此等待输入。


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
	var line := {
		"speaker_name": String(entry.get("speaker_name", entry.get("speaker", ""))),
		"text": String(entry.get("text", entry.get("dialogue", ""))),
	}
	# 行级字间隔（可选）。没写就不放这个键，开始播时回退到段级/节点默认值。
	var duration := _as_positive_float(entry.get("char_duration"))
	if duration > 0.0:
		line["char_duration"] = duration
	return line
