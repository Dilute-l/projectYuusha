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
##
## 牌子上的**印章**（例如 AwardPhd/PopupStamp）走 popup_stamp 键，见 STAMP_DIR 那一节。

## 「子节点名 → { 子节点里的 Label 名: CandidateResource 的字段名 }」。
##
## 加一条规则 = 加一行。想读别的字段（job / age / race / traits…）就往这里扩；
## 字段名直接用 CandidateResource 上的属性名。取值为空时会把那个 Label 清空 ——
## 不写「未知」这种兜底字，免得看不出来数据漏了。
const FILL_RULES: Dictionary = {
	&"AwardPhd": { &"Name": "display_name" },
	# YINIANJI 是新增那块牌子的**占位版**：底图 / 章 / 版面目前全跟 AwardPhd 一样
	# （见 data/asks/c_md_1155_status.json 已经在用它）。等真图真版面来了，只改
	# Popup.tscn 上的贴图和 Label，这条规则不用动。
	&"YINIANJI": { &"Name": "display_name" },
	# Contract 是**签名牌**：屏幕上那一大片空白画布由 popup_signature 键点亮（见 SIGNATURE
	# 那一节）。它**没有 Label** —— 名字由玩家亲手写，所以这里没有对应的一行。
}

## 牌子里的签名画布节点叫什么。
##
## 和章槽一样是「**牌子自己的**」：想做一块新签名牌，只要在它底下放一个叫这个名字的
## SignaturePad，本控件就认 —— 不认识的牌子照常显示，不会因为「没画布」而报错。
const SIGNATURE_NODE_NAME := &"SignaturePad"

## 牌子上的印章节点叫什么（§10.6 简历那枚章的「牌子版」）。
##
## ⚠️ **它是「牌子自己的」章槽，不是牌子控件的共用槽**：每个牌子子节点（`AwardPhd` / 将来
##    每一种新牌子）各自把自己那一个放在**自己底下**，跟着自己的版面走。
##    理由是踩过的：章的位置是写死的节点偏移（`AwardPhd/PopupStamp` 在 (541,410)，
##    正落在牌面里）。共用一个槽的话，「这一句没写 popup_stamp」的**沿用上一句**语义
##    会跨牌子生效 —— 换一块牌子就把上一块牌子的章按旧位置盖到新牌子上。
##    槽挂在牌子底下之后，换牌子 = 换槽，「沿用」天然只在同一种牌子内部成立。
##
## 名字认两个：`PopupStamp` 是现在用的，`ResumeStampPhd` 是它早先的名字（节点改过名，
## 而「名字没对上」的后果是**印章静默消失**，是最难查的一类 bug）。
const STAMP_NODE_NAME := &"PopupStamp"
const STAMP_NODE_ALIASES: Array[StringName] = [&"PopupStamp", &"ResumeStampPhd"]

## 印章图放哪儿、都有哪几张。**这里是唯一出处**：加一张新章 = 把 .png 丢进本目录，
## 再把文件名（不带扩展名）加进 STAMP_NAMES。
##
## 为什么是白名单而不是「什么都让 json 写」：路径写错在 Godot 里只会静默少一张图
## （牌子上不盖章），数据里根本看不出来。白名单让错写在**运行期当场喊出来**，
## 顺带让两个生成器有确定的候选项可列。
const STAMP_DIR := "res://assets/art/interview/resume/stamp/"
const STAMP_NAMES: Array[StringName] = [
	&"resume_stamp_real",
	&"resume_stamp_fake1",
	&"resume_stamp_fake2",
	&"resume_stamp_fake3",
	&"resume_stamp_fake4",
]

## 行级 popup_stamp 的哨兵值：**这一句不盖章**。
##
## 为什么要它：另外两个状态分别是「写了名字 → 盖那张」和「没写这个键 → 沿用调用方的默认」，
## 缺一个「明确不盖」的表达。想在同一段对话里让牌子先盖章、后不盖，就得靠它。
const STAMP_NONE := &"none"

## 当前显示着的子节点名；没有显示时是 &""
var _shown: StringName = &""

## 当前这块牌子**自己**的印章节点（每牌子一个，见 STAMP_NODE_NAME）；没有则 null
var _stamp: Sprite2D = null

## 当前这块牌子**自己**的签名画布（见 SIGNATURE_NODE_NAME）；没有则 null
var _pad: SignaturePad = null

## 这一句要签的是哪一份（来自对话那一行的 popup_signature）；不签时是 &""
var _signature_key: StringName = &""

## 已签过的签名：key -> Signature。
##
## 为什么由本控件自己记：牌子和对话都**不认识 GameState**（见文件头「不认识 Typer」那条，
## 同理）。所以「这份签过了没有」要么由调用方 remember_signature() 提前喂进来，
## 要么就是本次会话里刚签的。读档之后想让它显示旧签名，调用方喂一次即可。
var _known_signatures: Dictionary = {}

## 一份签名签好了（本该由谁存进 RunState 是调用方的事，见文件头分层说明）
signal signature_signed(signature_key: StringName, signature: Signature)


func _ready() -> void:
	hide_all()


## 显示名为 child_name 的子节点，并按 candidate 填它的内容。
##
## candidate 传 null 时只显示、不填（这样也能拿来当纯装饰用）。
##
## stamp_name（通常直接来自对话那一行的 "popup_stamp" 键）：
##   名字           → 盖上那张章（须在 STAMP_NAMES 里，写错会 push_warning 且不盖）
##   DialoguePopup.STAMP_NONE → 明确不盖
##   &""（默认）    → 沿用**同一块牌子**上一次的印章状态（换牌子则是新牌子自己的初始状态）
##
## signature_key（来自对话那一行的 "popup_signature" 键）：写了就表示**这一句要签** ——
## 牌子里的 SignaturePad 被 arm 起来等玩家落笔，签之前 blocks_advance() 为真
## （Dialoguer 据此不让对话翻页）。没写就是普通牌子。
func show_for(
	child_name: StringName,
	candidate: CandidateResource = null,
	stamp_name: StringName = &"",
	signature_key: StringName = &"",
) -> void:
	# ⚠️ hide_all() 会把印章一起藏掉（它也是 CanvasItem），所以「没写 popup_stamp」那一档
	#   得先把**本牌子自己**的上一次状态记下来再放回去。不记的话，连续两句都用同一块牌子、
	#   第二句没写 popup_stamp 时章会当场消失 —— 而这正是「沿用上一句」要表达的相反意思。
	#
	#    这里记的是「上一次 show_for 用过的那个槽」（_stamp），也就是**同一位牌子**的槽；
	#    换牌子时下面会重新绑定，prev 是空的 —— 所以章不会跟着牌子跨过去。
	var prev_stamp_visible := _stamp != null and _stamp.visible
	var prev_stamp_texture: Texture2D = _stamp.texture if _stamp != null else null

	hide_all()
	if child_name == &"":
		return
	var child := get_node_or_null(NodePath(String(child_name)))
	if child == null:
		push_error("[DialoguePopup] 没有名为「%s」的子节点（可用：%s）" % [
			child_name, ", ".join(PackedStringArray(_child_names()))])
		return
	_bind_stamp_to(child)
	_bind_pad_to(child)
	_fill(child, child_name, candidate)
	if stamp_name != &"":
		_apply_stamp(stamp_name)
	elif _stamp != null:
		_stamp.texture = prev_stamp_texture
		_stamp.visible = prev_stamp_visible
	_apply_signature(signature_key)
	child.visible = true
	_shown = child_name


## 收起牌子：每块牌子（以及它**肚子里**的章槽）一律不显示。整段结束 / 翻到不弹牌子的那一句时调。
##
## ⚠️ **只藏到「牌子根节点 + 它的章槽」这一层，不往肚子里的其他东西递归**：
##   牌子底下的 Label（`Name` / `Awardto` / `Gerat` …）的 `visible` 是**版面**，在 Popup.tscn
##   里就该是 true。早先这里对整棵子树递归置 false，而 show_for() 只把牌子**根节点**
##   恢复成 true —— 于是那些 Label 停在 false 上再也回不来：牌子和章都亮了，**字一个都不出来**。
##   行级的显隐状态只有「亮哪块牌子」这一档，肚子里的东西跟着牌子走。
##
## ⚠️ 但章槽必须**单独**收到：它挂在牌子自己底下（见 STAMP_NODE_NAME），只藏牌子的话章的
##   `visible` 还是 true —— 画面上暂时看不出来（父节点盖着），哪天有谁把牌子重新显示出来，
##   章就会**跟着诈尸**。这和「`queue_free()` 之前先 `disconnect`」（§5.5）是同一类坑：
##   收干净要收到最里面。
##
## ⚠️ 它**不负责记忆**：连续两句都用同一块牌子时，「这一句没写 popup_stamp」要把上一句盖的
##   章接着盖出来 —— 那是 show_for() 的事（它进门前先把状态记下来）。
func hide_all() -> void:
	for child in get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		_hide_stamp_slots(child)
	# 画布也要松开拾取：牌子都藏了就不该再拦玩家的点击（见 SignaturePad.set_armed）
	if _pad != null:
		_pad.set_armed(false)
	_signature_key = &""
	_shown = &""


## 把一块牌子（含它将来可能嵌套的子牌子）自己的章槽藏掉，见 hide_all 的说明。
##
## 找法是 STAMP_NODE_ALIASES + 递归 search —— 和 _bind_stamp_to() 认同一套名字，
## 免得「绑的时候认得出、藏的时候认不出」。
func _hide_stamp_slots(node: Node) -> void:
	for node_name in STAMP_NODE_ALIASES:
		var slot := node.find_child(String(node_name), true, false)
		if slot is CanvasItem:
			(slot as CanvasItem).visible = false


# ---------------------------------------------------------------------------
# 签名（popup_signature）
# ---------------------------------------------------------------------------
#
# 和印章是同一个套路：**这一句写了键 → 这块牌子上的画布就要东西**。
# 区别是章只是换图，签名要玩家自己动手，所以多一层「没签完就别翻页」（blocks_advance）。


## 把签名画布绑到「本次要显示的这块牌子」底下（和 _bind_stamp_to 对称）。
##
## 牌子底下没有画布是**正常情况**（绝大多数牌子不签名），什么都不说；
## 只有「数据里真写了 popup_signature、而这牌子没有画布」时 _apply_signature() 才出声。
func _bind_pad_to(child: Node) -> void:
	if _pad != null:
		# 换牌子之前先摘掉旧画布上的信号，不然换回来时会收到两份
		# （「`queue_free()` 之前先 disconnect」，§5.5 同一条规矩）
		_pad.set_armed(false)
		if _pad.signature_completed.is_connected(_on_pad_signature_completed):
			_pad.signature_completed.disconnect(_on_pad_signature_completed)
		if _pad.signing_started.is_connected(_on_pad_signing_started):
			_pad.signing_started.disconnect(_on_pad_signing_started)
		if _pad.signing_finished.is_connected(_on_pad_signing_finished):
			_pad.signing_finished.disconnect(_on_pad_signing_finished)
	var found := child.find_child(String(SIGNATURE_NODE_NAME), true, false) as SignaturePad
	_pad = found
	if _pad == null:
		return
	if not _pad.signature_completed.is_connected(_on_pad_signature_completed):
		_pad.signature_completed.connect(_on_pad_signature_completed)
	if not _pad.signing_started.is_connected(_on_pad_signing_started):
		_pad.signing_started.connect(_on_pad_signing_started)
	if not _pad.signing_finished.is_connected(_on_pad_signing_finished):
		_pad.signing_finished.connect(_on_pad_signing_finished)


## 这一句要签 / 不要签。
##
## 三种情形：
##   ① 这个 key 已经签过（本次会话签的，或调用方 remember_signature() 喂进来的）
##      → 直接静态显示那段笔迹，**不 arm**：已经签过就不该再拦着翻页；
##   ② 这个 key 没签过 → 擦干净、arm 起来等落笔；
##   ③ 这一句没写 popup_signature → 只把画布松开拾取，画布上有什么就留什么
##      （同一块牌子连着亮两句时，不该突然把玩家刚签的擦掉）。
func _apply_signature(signature_key: StringName) -> void:
	if signature_key == &"":
		return
	if _pad == null:
		push_warning("[DialoguePopup] 当前牌子没有签名画布（%s），popup_signature「%s」没地方签" % [
			SIGNATURE_NODE_NAME, signature_key])
		return
	_signature_key = signature_key
	var saved: Signature = _known_signatures.get(signature_key) as Signature
	if saved != null:
		_pad.show_signature(saved)
		_pad.set_armed(false)
		return
	_pad.clear()
	_pad.set_armed(true)


## **这一句能不能翻页**（Dialoguer 每一下点击都问一次）。
##
## 为真 = 牌子正等着玩家在这块画布上签字 —— 这一下点击属于画布，不属于对话框。
func blocks_advance() -> bool:
	return _pad != null and _pad.is_armed() and not _pad.is_signed()


## 先把一份**已知的**签名告诉本控件（读档之后想让牌子显示旧签名就喂一次）。
##
## 和 set_candidate() 一样是「谁播对话谁负责塞」：本控件不认识 GameState。
func remember_signature(signature_key: StringName, signature: Signature) -> void:
	if signature_key == &"" or signature == null:
		_known_signatures.erase(signature_key)
		return
	_known_signatures[signature_key] = signature


## 玩家签好了：记下来、往上报。
func _on_pad_signature_completed(signature: Signature) -> void:
	if _signature_key == &"" or signature == null:
		return
	_known_signatures[_signature_key] = signature
	signature_signed.emit(_signature_key, signature)
	EventBus.signature_signed.emit(_signature_key, signature)


## 画布开始落笔 / 这一笔结束 → 广播出去，让 Haohan 自己换手（见 event_bus.gd 那一节）。
func _on_pad_signing_started() -> void:
	EventBus.signature_signing_started.emit()


func _on_pad_signing_finished() -> void:
	EventBus.signature_signing_finished.emit()


func is_showing() -> bool:
	return _shown != &""


func shown_name() -> StringName:
	return _shown


## **当前这块牌子**自己的印章节点（自检 / 调试用；这块牌子没有章槽就是 null）
func stamp_node() -> Sprite2D:
	return _stamp


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


# ---------------------------------------------------------------------------
# 印章
# ---------------------------------------------------------------------------


## 把印章槽绑到「本次要显示的这块牌子」底下（见 STAMP_NODE_NAME 的长注释）。
##
## ⚠️ 换绑之前**先把旧槽藏掉并把图摘掉**：章槽挂在牌子自己底下，而 `hide_all()` 只把它藏起来、
##    **不会清 texture** —— 不清的话，换到另一块牌子时，旧牌子的槽里还留着
##    上一张章的图（只是 visible=false）。这和 resume.gd 里那条「空就是空」是同一条规矩：
##    哪天有谁顺手把牌子 `visible = true`，就会盖出一个张冠李戴的章。
##
## 牌子底下没有章槽是**正常情况**（这块牌子就是不盖章），什么都不说；
## 只有「数据里真写了 popup_stamp、而这牌子没有槽」时 _apply_stamp() 才出声。
func _bind_stamp_to(child: Node) -> void:
	if _stamp != null:
		_stamp.visible = false
		_stamp.texture = null
	for node_name in STAMP_NODE_ALIASES:
		var node := child.find_child(String(node_name), true, false)
		if node is Sprite2D:
			_stamp = node
			return
	_stamp = null


## 把 stamp_name 那张章盖到**当前这块牌子**的章槽上（见 show_for 的说明）。
##
## 规则与 resume.gd::_apply_stamp() 完全一致，只是**图从哪来**不同：
## 简历那枚看数据（CandidateResource.resume_stamp），牌子这枚看**对话那一行**（popup_stamp）——
## 同一句台词在不同剧情里可以盖不同的章，不必给候选人加字段。
##
## ⚠️ 图名不认识时**不静默**：报出来并保持不盖章。静默的话，数据里写错一个字母
##    的表现就是「牌子上少一枚章」，隔着一层对话根本查不出来。
func _apply_stamp(stamp_name: StringName) -> void:
	if _stamp == null:
		# 这块牌子没有章槽 —— 数据却要求盖章，说一声（否则就是静默无效果）
		push_warning("[DialoguePopup] 当前牌子没有印章子节点（%s），popup_stamp「%s」没地方盖" % [
			STAMP_NODE_NAME, stamp_name])
		return
	if stamp_name == STAMP_NONE:
		_stamp.texture = null
		_stamp.visible = false
		return
	if not STAMP_NAMES.has(stamp_name):
		push_warning("[DialoguePopup] popup_stamp「%s」不在 STAMP_NAMES 里，本句不盖章（可用：%s，或 %s）" % [
			stamp_name, ", ".join(STAMP_NAMES), STAMP_NONE])
		_stamp.texture = null
		_stamp.visible = false
		return
	_stamp.texture = stamp_texture(stamp_name)
	_stamp.visible = _stamp.texture != null


## 印章名 → 贴图。名字不在 STAMP_NAMES 里就报错并返回 null（绝不猜路径）。
##
## 位置 / 缩放 / centered 一律**不在这里碰**：那是版面，写在 Popup.tscn 上 ——
## 和简历那枚章同一个道理，换一张尺寸不同的章不用改一行代码。
static func stamp_texture(stamp_name: StringName) -> Texture2D:
	if not STAMP_NAMES.has(stamp_name):
		push_error("[DialoguePopup] 没有名为「%s」的印章（可用：%s）" % [
			stamp_name, ", ".join(STAMP_NAMES)])
		return null
	var path := STAMP_DIR + String(stamp_name) + ".png"
	if not ResourceLoader.exists(path):
		push_error("[DialoguePopup] 印章贴图不存在：%s" % path)
		return null
	return load(path)


## 本控件底下所有子节点的名字（报错信息里列给作者看）
func _child_names() -> Array[String]:
	var names: Array[String] = []
	for child in get_children():
		names.append(String(child.name))
	return names
