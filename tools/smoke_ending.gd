extends Node

## 结局**文案**的自检（不需要编辑器，也不需要打开场景）。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_ending.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 验三件事：
##   1. `data/dialogue.json` 里有 `Ending_Good` / `Ending_Bad` 两段，且都不空；
##   2. 好结局那段里写着 `{total_score}`，坏结局那段能播（有台词）；
##   3. **变量替换**（typer._substitute）：`{total_score}` 换成真实分数，
##      未定义的占位符原样保留 —— 且这条在 `load_dialogue()` 真装进来的
##      `Ending_Good` 上也成立（不是只在字符串上成立）。
##
## ⚠️ 这里**不碰 ending.tscn / bad_ending.tscn**：结局场景的播放与自动返回
##    由 `smoke_ending_flow` 管（它会真的把场景实例化进 SubViewport 跑一遍）。
##    本自检只钉「文案与占位符」，场景改了它不该红。
##
## 历史教训：这份自检曾经写死了 `Ending_p1` 和一个已经被删掉的成绩标签，
## 于是结局改成 `Ending_Good` + 只播对话之后，它整份飘红 —— 断言只该钉
## 契约（有这段、有占位符、替换生效），不该钉会被设计合理改掉的东西。

const DIALOGUE_PATH := "res://data/dialogue.json"
const GOOD_ID := "Ending_Good"
const BAD_ID := "Ending_Bad"

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_run()
	_report()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK  " if ok else "FAIL", what])


## 取一段对话，返回它的行数组；没有这段返回空数组。
func _segment(parsed: Dictionary, id: String) -> Array:
	var seg: Variant = parsed.get(id)
	return seg if seg is Array else []


func _run() -> void:
	# ---- 1. 数据侧：两段结局文案都在 ----
	var raw := FileAccess.get_file_as_string(DIALOGUE_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	_check(parsed is Dictionary, "dialogue.json 能解析")
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed

	var good := _segment(data, GOOD_ID)
	var bad := _segment(data, BAD_ID)
	_check(not good.is_empty(), "有「%s」这段对话（%d 行）" % [GOOD_ID, good.size()])
	_check(not bad.is_empty(), "有「%s」这段对话（%d 行）" % [BAD_ID, bad.size()])

	# 好结局末句要念总分 —— 没有这个占位符，结局就只是三段没有信息量的旁白
	var good_text := _joined(good)
	_check(good_text.contains("{total_score}"), "好结局文案里写了 {total_score} 占位符")
	# 坏结局虽然还是占位文本，但至少要真的有一句能播（空段会让场景直接回主菜单）
	_check(not _joined(bad).strip_edges().is_empty(), "坏结局文案不是空字符串")

	# ---- 2. 纯函数层：_substitute 的行为 ----
	var typer := Typer.new()
	typer.set_vars({ "total_score": "1234", "名字": "法斯特" })
	_check(typer._substitute("总计 {total_score} 分") == "总计 1234 分",
			"{total_score} 被替换成值")
	_check(typer._substitute("{名字}来了") == "法斯特来了", "中文键也能用")
	_check(typer._substitute("没有占位符") == "没有占位符", "没有占位符时原样返回")
	_check(typer._substitute("{没定义的}变量") == "{没定义的}变量",
			"**未定义的占位符原样保留**（不删、不报错）")
	typer.clear_vars()
	_check(typer._substitute("{total_score}") == "{total_score}",
			"clear_vars 之后不再替换")

	# ---- 3. 真装进来的 Ending_Good：末句念出分数 ----
	_check(typer.load_dialogue(GOOD_ID), "Typer 能装入 %s" % GOOD_ID)
	_check(typer.lines.size() == good.size(),
			"装入的行数与 json 一致（%d vs %d）" % [typer.lines.size(), good.size()])
	if not typer.lines.is_empty():
		typer.set_vars({ "total_score": "524" })
		typer.start_line(typer.lines.size() - 1)
		var last := typer.get_full_text()
		_check(last.contains("524"), "末句念出真实总分：%s" % last)
		_check(not last.contains("{total_score}"), "占位符已被替换，没有残留")
	typer.free()


func _joined(lines: Array) -> String:
	var out := ""
	for entry in lines:
		if entry is Dictionary:
			out += String((entry as Dictionary).get("text", ""))
	return out


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_ending] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_ending] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
