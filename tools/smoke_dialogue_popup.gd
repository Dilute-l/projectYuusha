extends Node

## 对话小牌子（Popup / DialoguePopup）自检 —— 不需要编辑器，也不需要打开场景。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_dialogue_popup.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 盯的是「牌子上的印章」这条新链路（ARCHITECTURE.md §10.6 的第二枚章）：
##
##   对话 json 某一行 { "popup": "AwardPhd", "popup_stamp": "resume_stamp_fake1" }
##     → typer._normalize_line() 保留 popup_stamp
##     → dialoguer._on_line_started() 把它交给 DialoguePopup.show_for()
##     → _apply_stamp() 按白名单换图 + 显隐
##
## **一句台词都不在脚本里**：期望值全部从 data/asks/*.json 现读现比。
##
## 为什么要单独一个自检：印章是「静默消失」型的功能 —— 名字写错 / 节点改名 /
## 图搬了家，画面上只是少一枚章，隔着对话框根本看不出来。这几条就是把它钉住。

const POPUP_SCENE := preload("res://scenes/common/Popup.tscn")

## 游戏的实际画布（project.godot 的 canvas_items 拉伸基准）
const GAME_CANVAS := Vector2i(1152, 648)

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
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


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = GAME_CANVAS
	vp.disable_3d = true
	get_tree().root.add_child(vp)

	# ---- 1. 白名单：每个名字都得真的有一张图 ----
	_check(DialoguePopup.STAMP_NAMES.size() > 0, "STAMP_NAMES 不是空的（%d 张）" % DialoguePopup.STAMP_NAMES.size())
	var missing := 0
	for name in DialoguePopup.STAMP_NAMES:
		var path := DialoguePopup.STAMP_DIR + String(name) + ".png"
		if not ResourceLoader.exists(path):
			missing += 1
			print("      · 找不到 %s" % path)
	_check(missing == 0, "STAMP_NAMES 里每一张章都有对应贴图（缺 %d 张）" % missing)

	# 真·假两族都要在名单里：名字能自解释，也免得「白名单只剩一张」这种退化解
	var has_real := false
	var has_fake := false
	for name in DialoguePopup.STAMP_NAMES:
		if String(name).contains("_real"):
			has_real = true
		if String(name).contains("_fake"):
			has_fake = true
	_check(has_real and has_fake, "白名单里既有真章也有假章（真 %s / 假 %s）" % [has_real, has_fake])

	# ---- 2. 不认识的印章名：报出来，且**绝不猜路径**（返回 null） ----
	_check(DialoguePopup.stamp_texture(&"resume_stamp_不存在") == null,
			"不在白名单里的名字取不到图（返回 null，不猜路径）")
	_check(DialoguePopup.stamp_texture(&"") == null, "空名字取不到图")

	# ---- 3. 牌子本体：节点结构 + 三个状态 ----
	var popup := POPUP_SCENE.instantiate() as DialoguePopup
	vp.add_child(popup)
	await _settle()

	_check(popup.get_node_or_null("AwardPhd") != null, "牌子上有 AwardPhd 这个子节点")
	# 章槽**挂在牌子自己底下**，不能是牌子控件根下的共用槽：
	# 共用一个槽的话，「这一句没写 popup_stamp」的沿用语义会跨牌子生效 ——
	# 换一块牌子就把上一块牌子的章按旧位置盖到新牌子上（见 popup.gd 的长注释）。
	var award_stamp := popup.get_node_or_null("AwardPhd/PopupStamp") as Sprite2D
	_check(award_stamp != null, "AwardPhd 底下有自己的章槽（AwardPhd/PopupStamp）")
	if award_stamp == null:
		return
	_check(popup.get_node_or_null("PopupStamp") == null,
			"牌子根节点下**没有**共用章槽（否则会跨牌子串台）")
	_check(not popup.is_showing(), "刚挂上去什么都不显示")
	_check(not award_stamp.visible, "刚挂上去印章不显示（默认藏在场景里）")
	# 槽是**显示哪块牌子才绑哪块**的（_ready 里不预先绑），所以这时候还没绑
	_check(popup.stamp_node() == null, "还没显示任何牌子 → 当前没有绑定的章槽")

	# 3a. 写了名字 → 盖那张
	var first := DialoguePopup.STAMP_NAMES[0]
	popup.show_for(&"AwardPhd", null, first)
	await _settle()
	_check(popup.is_showing() and popup.shown_name() == &"AwardPhd", "show_for 亮起了 AwardPhd")
	_check(popup.stamp_node() == award_stamp, "显示 AwardPhd 时绑定的就是它自己的章槽")
	var stamp := popup.stamp_node()
	if stamp == null:
		return
	_check(stamp.visible, "写了 popup_stamp → 章盖上了")
	_check(stamp.texture == DialoguePopup.stamp_texture(first),
			"盖的就是那一张（%s）" % first)
	_check(stamp.position != Vector2.ZERO, "章摆在自己那一处（不是 (0,0)：位置由场景说了算，代码不碰）")

	# 3b. "none" → 明确不盖
	popup.show_for(&"AwardPhd", null, DialoguePopup.STAMP_NONE)
	await _settle()
	_check(not stamp.visible, "popup_stamp = none → 这一句明确不盖章")
	_check(stamp.texture == null, "明确不盖时连图也摘干净（不会张冠李戴）")

	# 3c. 没写这个键（默认 &""）→ 不动印章
	stamp.texture = null
	stamp.visible = false
	popup.show_for(&"AwardPhd", null)
	await _settle()
	_check(not stamp.visible, "没写 popup_stamp → 不改变印章状态（保持不盖）")
	popup.show_for(&"AwardPhd", null, first)
	await _settle()
	popup.show_for(&"AwardPhd", null)
	await _settle()
	_check(stamp.visible and stamp.texture == DialoguePopup.stamp_texture(first),
			"没写 popup_stamp → 沿用上一句已经盖上的那张")

	# 3d. 换一句不弹牌子 → 牌子收起来（翻页语义：line_started 先 hide_all 再亮新的）
	popup.show_for(&"", null)
	await _settle()
	_check(not popup.is_showing(), "这一句没写 popup → 牌子收起来")
	_check(not stamp.visible, "牌子收起来时印章一起藏")

	# 3e. 名字写错 → 不盖章（而不是拿上一张凑数）
	popup.show_for(&"AwardPhd", null, first)
	await _settle()
	popup.show_for(&"AwardPhd", null, &"resume_stamp_不存在")
	await _settle()
	_check(not stamp.visible and stamp.texture == null,
			"popup_stamp 写错名字 → 本句不盖章（宁可空着，也不拿上一张凑）")

	# ---- 3f. 换一块**别人家的牌子**：上一块的章不许跨过来 ----
	# 这就是「以后加一个不在 AwardPhd 下的牌子」那条路：章槽挂在牌子自己底下，
	# 换牌子 = 换槽，于是「没写 popup_stamp」拿到的是新牌子自己的初始状态（不盖）。
	var other := Sprite2D.new()
	other.name = "NoticeBoardPhd"
	popup.add_child(other)
	await _settle()

	popup.show_for(&"AwardPhd", null, first)
	await _settle()
	_check(stamp.visible, "先让 AwardPhd 盖上章（跨牌子那一步的前提）")

	popup.show_for(&"NoticeBoardPhd", null)
	await _settle()
	_check(popup.shown_name() == &"NoticeBoardPhd", "换到了新牌子上")
	_check(popup.stamp_node() == null, "新牌子**没有**章槽 → 当前印章节点为空")
	_check(not stamp.visible and stamp.texture == null,
			"上一块牌子的章没有跨到新牌子上（换牌子 = 换槽，不是沿用）")
	_check(other.visible, "新牌子自己照常显示")

	# 3g. 新牌子没槽却写了 popup_stamp → 报出来、不盖到别人家的槽上
	popup.show_for(&"NoticeBoardPhd", null, first)
	await _settle()
	_check(not stamp.visible and stamp.texture == null,
			"新牌子没有章槽时写 popup_stamp → 不会盖到 AwardPhd 的槽上（push_warning 且章留在原地不动）")

	# 换回 AwardPhd：它自己的槽照旧可用（绑定的槽没被上一步改坏）
	popup.show_for(&"AwardPhd", null, &"resume_stamp_fake1")
	await _settle()
	_check(popup.stamp_node() == stamp and stamp.visible,
			"换回 AwardPhd → 它自己的章槽照旧可用（盖的是它自己那张）")
	other.queue_free()
	await _settle()

	# ---- 4. 填字规则：牌子上的 Name 跟着候选人走 ----
	var who := CandidateResource.new()
	who.display_name = "自检用名字"
	popup.show_for(&"AwardPhd", who, DialoguePopup.STAMP_NONE)
	await _settle()
	var name_label := popup.get_node_or_null("AwardPhd/Name") as Label
	_check(name_label != null and name_label.text == who.display_name,
			"牌子上的 Name = 候选人的 display_name（%s）" % (
				name_label.text if name_label != null else "<找不到 Label>"))
	# 不喂候选人时只显示、不填 —— 不该把上一位的名字留在牌子上
	popup.show_for(&"AwardPhd", null, DialoguePopup.STAMP_NONE)
	await _settle()
	_check(name_label != null and name_label.text == who.display_name,
			"不喂候选人时不改字（只显示不填）")

	# ---- 4b. 牌子亮起来时，肚子里的字必须一起出来 ----
	# 挡的是「牌子和章都亮了、字一个都不出来」那类 bug：hide_all() 早先对整棵子树递归置
	# visible=false，而 show_for() 只把牌子**根节点**恢复成 true —— 三个 Label 就停在 false
	# 上再也回不来。上面 4 那几条只比 text，看不见这件事，所以单独钉一遍 visible。
	var card_labels: Array[String] = []
	for child in popup.get_node("AwardPhd").get_children():
		if child is Label:
			card_labels.append(String(child.name))
	_check(card_labels.size() > 0, "AwardPhd 底下有 Label（%s）" % ", ".join(card_labels))

	popup.show_for(&"AwardPhd", null, DialoguePopup.STAMP_NONE)
	await _settle()
	var dark: Array[String] = []
	for label_name in card_labels:
		var label := popup.get_node_or_null("AwardPhd/" + label_name) as Label
		if label == null or not label.visible:
			dark.append(label_name)
	_check(dark.is_empty(), "牌子亮起来时肚子里的 Label 全都可见（看不见的：%s）" % (
			", ".join(dark) if not dark.is_empty() else "无"))

	# 收起来只收「牌子 + 章槽」这一层：Label 自己的 visible 是版面，归场景管，不该被改写
	popup.show_for(&"", null)
	await _settle()
	var clobbered: Array[String] = []
	for label_name in card_labels:
		var label := popup.get_node_or_null("AwardPhd/" + label_name) as Label
		if label == null or not label.visible:
			clobbered.append(label_name)
	_check(clobbered.is_empty(), "收起牌子时不改写 Label 的 visible（被改动的：%s）" % (
			", ".join(clobbered) if not clobbered.is_empty() else "无"))

	# ---- 5. 数据链路：现有追问 json 里的 popup / popup_stamp 都能被认出来 ----
	_check_data_lines(popup)

	popup.queue_free()
	await _settle()


## 数据里凡是写了 popup 的行（`data/asks/*.json` 每一份，加上 `data/dialogue.json` 每一段）：
##   ① popup 那块牌子必须真的在 Popup.tscn 里（不然那句台词就是**静默不弹**，只有一个 push_error）；
##   ② popup_stamp（若写了）必须在白名单里，或者是 STAMP_NONE（"none" 是合法值，不是错）；
##   ③ popup_signature（若写了）必须挂在一块**带签名画布**的牌子上，否则玩家签不了字（§16）。
## 这三条挡的是「生成器里选了个名字、Godot 侧还没加」这类两边不同步的错。
##
## 两份数据都扫：`data/dialogue.json` 里第一天的开场（day1_briefing）就是靠 popup_signature
## 让玩家签字的 —— 只扫 asks 的话，那一句写错了没人会知道。
func _check_data_lines(popup: Node) -> void:
	var popup_lines := 0
	var bad_stamp := 0
	var bad_node := 0
	var bad_signature := 0

	# ---- ① data/asks/*.json：每份文件是一个行数组 ----
	var dir := DirAccess.open("res://data/asks")
	_check(dir != null, "data/asks 打得开")
	if dir != null:
		for file_name in dir.get_files():
			if not file_name.ends_with(".json"):
				continue
			var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string("res://data/asks/" + file_name))
			if not (parsed is Array):
				continue
			var report := _scan_lines(popup, file_name, parsed)
			popup_lines += int(report["lines"])
			bad_node += int(report["bad_node"])
			bad_stamp += int(report["bad_stamp"])
			bad_signature += int(report["bad_signature"])

	# ---- ② data/dialogue.json：{ 段 id -> 行数组 } ----
	var shared: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/dialogue.json"))
	_check(shared is Dictionary, "data/dialogue.json 读得出来")
	if shared is Dictionary:
		var segments: Dictionary = shared
		for segment_id in segments:
			var lines: Variant = segments[segment_id]
			if not (lines is Array):
				continue
			var report := _scan_lines(popup, "dialogue.json / %s" % segment_id, lines)
			popup_lines += int(report["lines"])
			bad_node += int(report["bad_node"])
			bad_stamp += int(report["bad_stamp"])
			bad_signature += int(report["bad_signature"])

	_check(popup_lines > 0, "数据里至少有一行弹牌子（%d 行，数据链路真的在用）" % popup_lines)
	_check(bad_node == 0, "数据里写的 popup 都能在 Popup.tscn 里找到（找不到 %d 处）" % bad_node)
	_check(bad_stamp == 0, "数据里写的 popup_stamp 全在白名单里（不认识 %d 处）" % bad_stamp)
	_check(bad_signature == 0, "数据里写了 popup_signature 的牌子都挂着 SignaturePad（落不上 %d 处）" % bad_signature)


## 扫一份「行数组」，返回 { lines, bad_node, bad_stamp, bad_signature } 四个计数。
func _scan_lines(popup: Node, source: String, entries: Array) -> Dictionary:
	var report := {"lines": 0, "bad_node": 0, "bad_stamp": 0, "bad_signature": 0}
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var line: Dictionary = entry
		var popup_name := String(line.get("popup", "")).strip_edges()
		if popup_name.is_empty():
			continue
		report["lines"] += 1
		var card := popup.get_node_or_null(NodePath(popup_name))
		if card == null:
			report["bad_node"] += 1
			print("      · %s 里的 popup「%s」在 Popup.tscn 里没有同名子节点" % [source, popup_name])
		# 签名要落到一块有画布的牌子上（§16）；牌子本身不存在时上面已经记过一笔，不再重复数
		var signature_key := String(line.get("popup_signature", "")).strip_edges()
		if not signature_key.is_empty() and card != null \
				and card.find_child("SignaturePad", true, false) == null:
			report["bad_signature"] += 1
			print("      · %s 里的 popup_signature「%s」落在牌子「%s」上，但那块牌子没有 SignaturePad" % [
				source, signature_key, popup_name])
		var stamp_name := String(line.get("popup_stamp", "")).strip_edges()
		if stamp_name.is_empty():
			continue
		if StringName(stamp_name) == DialoguePopup.STAMP_NONE:
			continue  # 「这一句明确不盖章」，合法值
		if not DialoguePopup.STAMP_NAMES.has(StringName(stamp_name)):
			report["bad_stamp"] += 1
			print("      · %s 里的 popup_stamp「%s」不在白名单里" % [source, stamp_name])
	return report


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_dialogue_popup] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_dialogue_popup] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
