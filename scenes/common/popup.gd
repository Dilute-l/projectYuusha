class_name DialoguePopup
extends Control

## 对话期间弹出的「小牌子」（scenes/common/Popup.tscn）。
##
## 怎么用：对话的某一句在 json 里多写一个键，值是**本控件要显示的子节点名**：
##
##     { "speaker_name": "面试官", "text": "……", "popup": "AwardPhd" }
##
## 这句话一出现 → 那个子节点可见；这句话结束（翻到下一句 / 整段结束）→ 收起。
##
## ⚠️ 本控件**不认识 Typer，也不驱动对话**：谁播对话谁负责在 line_started /
##    line_finished 上喊它（见文件末尾）。这样它才能被任意阶段复用 ——
##    和 resume.tscn「台词交给所在阶段去播」是同一个道理。
##
## 子节点里的文字从哪来：见 FILL_RULES ——「哪个子节点里的哪个 Label ← 候选人的哪个字段」。

## 「子节点名 → { 子节点里的 Label 名: CandidateResource 的字段名 }」。
##
## 加一条规则 = 加一行。想读别的字段（job / age / race / traits…）就往这里扩；
## 字段名直接用 CandidateResource 上的属性名。取值为空时会把那个 Label 清空 ——
## 不写「未知」这种兜底字，免得看不出来数据漏了。
const FILL_RULES: Dictionary = {
	&"AwardPhd": { &"Name": "display_name" },
}

## 当前显示着的子节点名；没有显示时是 &""
var _shown: StringName = &""


func _ready() -> void:
	hide_all()


## 显示名为 child_name 的子节点，并按 candidate 填它的内容。
##
## candidate 传 null 时只显示、不填（这样也能拿来当纯装饰用）。
func show_for(child_name: StringName, candidate: CandidateResource = null) -> void:
	hide_all()
	if child_name == &"":
		return
	var child := get_node_or_null(NodePath(String(child_name)))
	if child == null:
		push_error("[DialoguePopup] 没有名为「%s」的子节点" % child_name)
		return
	_fill(child, child_name, candidate)
	child.visible = true
	_shown = child_name


## 收起全部子节点。翻到下一句 / 整段对话结束时都调它。
func hide_all() -> void:
	for child in get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
	_shown = &""


func is_showing() -> bool:
	return _shown != &""


func shown_name() -> StringName:
	return _shown


## 按 FILL_RULES 把候选人字段铺进子节点里的 Label。
func _fill(child: Node, child_name: StringName, candidate: CandidateResource) -> void:
	if candidate == null or not FILL_RULES.has(child_name):
		return
	var rules: Dictionary = FILL_RULES[child_name]
	for label_name in rules:
		var label := child.get_node_or_null(NodePath(String(label_name))) as Label
		if label == null:
			push_warning("[DialoguePopup] %s 里找不到 Label「%s」" % [child_name, label_name])
			continue
		label.text = str(candidate.get(String(rules[label_name])))
