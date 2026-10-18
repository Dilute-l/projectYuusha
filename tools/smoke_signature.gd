extends Node

## 签名自检（ARCHITECTURE.md §16）—— 不需要编辑器，也不需要打开场景。
##
## 用法：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_signature.tscn
##   全绿退出码 0；有失败项退出码 1。
##
## 钉住的是几条**会静默失效**的东西：
##   ① 归一化坐标：换个画布尺寸，同一段笔迹必须落在同一个相对位置（否则缩略图里字会漂）；
##   ② 存读一致：Signature → 存档 JSON → Signature，点数和位置都对得上；
##   ③ 一笔画：签完就不再接受落笔（松手 = 签名结束，不是「这一笔结束」）；
##   ④ 出界吸附：鼠标跑到画布外，**只是笔迹**贴到边界上，且记录的点全部落在 0..1 里；
##   ⑤ 没签完不许翻页：blocks_advance() 在签之前为真、签之后为假；
##   ⑥ 换手：落笔时 Haohan 变蘸墨那只，签完自动还原。

const POPUP_SCENE := preload("res://scenes/common/Popup.tscn")
const PAD_SCENE := preload("res://ui/components/signature_pad.tscn")
const HAHAN_SCENE := preload("res://scenes/common/haohan.tscn")
const DIALOGUER_SCENE := preload("res://scenes/common/dialoguer.tscn")

const PAD_SIZE := Vector2(270, 160)

## 浮点比较的容差：坐标量化到 1e-4，往返一趟以后留一倍余量
const EPSILON := 0.0002

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
	var host := Control.new()
	host.size = Vector2(1152, 648)
	add_child(host)
	await _settle()

	# ---- 1. 归一化：同一段笔迹在两种画布尺寸上落在同一个相对位置 ----
	var small := Rect2(Vector2.ZERO, Vector2(270, 160))
	var big := Rect2(Vector2.ZERO, Vector2(540, 320))
	var center := Vector2(135.0, 80.0)
	var normalized := Signature.to_normalized(small, center)
	_check(normalized.is_equal_approx(Vector2(0.5, 0.5)),
			"画布正中归一化成 (0.5, 0.5)（实际 %s）" % normalized)
	_check(Signature.to_canvas(big, normalized).is_equal_approx(Vector2(270.0, 160.0)),
			"同一个 (0.5, 0.5) 在双倍画布上是 (270,160) —— 换尺寸不漂（实际 %s）"
			% Signature.to_canvas(big, normalized))

	# 牌子里的画布不在 (0,0)，换算必须带上画布自己的 origin
	var offset_canvas := Rect2(Vector2(430, 355), PAD_SIZE)
	var corner := Vector2(430.0, 355.0)
	_check(Signature.to_canvas(offset_canvas, Signature.to_normalized(offset_canvas, corner))
			.is_equal_approx(corner), "带偏移的画布：归一化往返回到原点")

	# ---- 2. Signature 本体读数 ----
	var source := _make_signature()
	_check(source.point_count() == 12, "点数是 12（实际 %d）" % source.point_count())
	_check(is_equal_approx(source.duration_ms(), 275.0),
			"总时长 = 最后一点的时间戳 275ms（实际 %.1f）" % source.duration_ms())
	_check(source.total_length() > 0.4, "笔迹总长 > 0.4（归一化单位，实际 %.3f）" % source.total_length())
	_check(not source.is_empty(), "有笔就不算空")
	_check(Signature.new().is_empty(), "新建的 Signature 是空的")

	# ---- 3. 存读一致：Signature → 存档 JSON → Signature ----
	var restored := Signature.from_dict(JSON.parse_string(JSON.stringify(source.to_dict())))
	_check(restored.point_count() == source.point_count(),
			"过一趟 JSON 点数不变（%d → %d）" % [source.point_count(), restored.point_count()])
	# 时间戳量化到 10ms（Signature.TIME_QUANTUM_MS），所以往返允许半个量子的误差。
	# 这不是妥协：275→280 的 5ms 差异在回放里根本看不出来，换来的是存档小一截。
	var time_drift := absf(restored.duration_ms() - source.duration_ms())
	_check(time_drift <= float(Signature.TIME_QUANTUM_MS) * 0.5,
			"过一趟 JSON 时长误差 ≤ 半个量子（%.1f → %.1f，差 %.1fms）" % [
				source.duration_ms(), restored.duration_ms(), time_drift])
	_check(restored.canvas.is_equal_approx(source.canvas),
			"画布尺寸也一起存了（%s）" % restored.canvas)
	var max_drift := 0.0
	var src_points: PackedVector2Array = source.strokes[0]["p"]
	var back_points: PackedVector2Array = restored.strokes[0]["p"]
	for i in range(mini(src_points.size(), back_points.size())):
		max_drift = maxf(max_drift, src_points[i].distance_to(back_points[i]))
	_check(max_drift <= EPSILON, "每个点的往返误差 ≤ %.4f（实际最大 %.6f）" % [EPSILON, max_drift])

	# 坏数据不许把读档整挂
	var broken := Signature.from_dict({"strokes": [{"p": [0.5]}, 42, {"p": []}]})
	_check(broken.point_count() == 0, "缺一半坐标 / 不是字典的笔 → 跳过，不报错")
	_check(Signature.from_dict({}).is_empty(), "空字典 → 空签名")

	# ---- 4. 画布：一笔画 / 出界吸附 / 误点 ----
	var pad := PAD_SCENE.instantiate() as SignaturePad
	host.add_child(pad)
	await _settle()
	_check(pad.size.is_equal_approx(PAD_SIZE), "画布尺寸取自场景（%s）" % pad.size)

	# 没 arm 的时候不收输入，也不抢拾取
	_check(pad.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"没在等签名时画布不抢拾取（MOUSE_FILTER_IGNORE）")
	_press(pad, Vector2(20, 20))
	_move(pad, Vector2(80, 60))
	_release(pad, Vector2(80, 60))
	_check(not pad.is_signed(), "没 arm 时落笔无效")

	var started := [0]
	var finished := [0]
	pad.signing_started.connect(func() -> void: started[0] += 1)
	pad.signing_finished.connect(func() -> void: finished[0] += 1)

	pad.set_armed(true)
	await _settle()
	_check(pad.mouse_filter == Control.MOUSE_FILTER_STOP,
			"等签名时画布收起拾取（MOUSE_FILTER_STOP）")

	_press(pad, Vector2(20, 20))
	_move(pad, Vector2(60, 40))
	_move(pad, Vector2(120, 90))
	# ⚠️ 跑到画布外面：只吸附笔迹，不拽鼠标
	_move(pad, Vector2(400, -120))
	_release(pad, Vector2(400, -120))
	await _settle()

	_check(started[0] == 1 and finished[0] == 1,
			"起笔 / 收笔各广播一次（%d / %d）" % [started[0], finished[0]])
	_check(pad.is_signed(), "松手就是一整份签名（一笔画）")
	var signed: Signature = pad.signature()
	_check(signed != null and signed.point_count() >= 4,
			"笔迹记下了 %d 个点" % (signed.point_count() if signed != null else 0))

	var out_of_range := 0
	var clamped_corner := false
	var all_points: PackedVector2Array = signed.strokes[0]["p"]
	for point in all_points:
		if point.x < -EPSILON or point.x > 1.0 + EPSILON \
				or point.y < -EPSILON or point.y > 1.0 + EPSILON:
			out_of_range += 1
		if point.is_equal_approx(Vector2(1.0, 0.0)):
			clamped_corner = true
	_check(out_of_range == 0, "所有点都在画布 0..1 之内（越界 %d 个）" % out_of_range)
	_check(clamped_corner, "跑到画布外面的那个点被吸附到了最近的角 (1, 0)")

	# 一笔画：签过之后再按也不开新的一笔
	var before := signed.point_count()
	_press(pad, Vector2(30, 120))
	_move(pad, Vector2(200, 140))
	_release(pad, Vector2(200, 140))
	await _settle()
	_check(pad.signature() == signed and pad.signature().point_count() == before,
			"签完之后再落笔不开新笔（还是原来那 %d 个点）" % before)

	# 误点（按下就松，几乎没动）不算签名
	var idler := PAD_SCENE.instantiate() as SignaturePad
	host.add_child(idler)
	await _settle()
	idler.set_armed(true)
	_press(idler, Vector2(50, 50))
	_release(idler, Vector2(50, 50))
	await _settle()
	_check(not idler.is_signed(), "按下就松的一次误点不算签名")
	_check(idler.signature() == null, "误点之后画布仍是空的")

	# ---- 5. 回放：playhead 决定能看见几个点 ----
	# 用 _make_signature() 这份**时间戳确定**的笔迹来数：手绘那段的第一个点可能落在
	# 第 0 还是第 1 毫秒，取决于当帧运气，拿它做断言就是给自己埋雷。
	idler.show_signature(source)
	_check(idler.is_signed() and idler.signature() == source, "show_signature 静态显示一份签名")
	_check(idler.visible_point_count(0.0) == 1,
			"playhead=0 → 只看得见起笔那个点（实际 %d 个）" % idler.visible_point_count(0.0))
	_check(idler.visible_point_count(50.0) == 3,
			"playhead=50ms → 看得见 0/25/50 三点（实际 %d 个）" % idler.visible_point_count(50.0))
	_check(idler.visible_point_count(source.duration_ms()) == source.point_count(),
			"播到底 → 12 个点全看得见（实际 %d）" % idler.visible_point_count(source.duration_ms()))
	# 手绘那一段：播到底必须等于它自己的点数
	_check(pad.visible_point_count(signed.duration_ms() + 100.0) == signed.point_count(),
			"手绘那段播到底 → 全部 %d 个点都看得见" % signed.point_count())
	idler.clear()
	_check(not idler.is_signed() and idler.signature() == null, "clear() 之后回到未签状态")

	# ---- 5b. 时间戳严格递增：同一毫秒里落下的点不许把时间轴压成 0 ----
	# 一口气推完四个点时 Time.get_ticks_msec() 往往全一样，若不兜住，duration 会是 0，
	# 回放时会「整段瞬间糊上去」而不是一笔一笔走。
	idler.set_armed(true)
	_press(idler, Vector2(20, 30))
	_move(idler, Vector2(90, 50))
	_move(idler, Vector2(160, 90))
	_release(idler, Vector2(160, 90))
	await _settle()
	var burst: Signature = idler.signature()
	_check(burst != null, "同一帧里推完的一串点也算签上了")
	if burst != null:
		var stamps: PackedFloat32Array = burst.strokes[0]["t"]
		var monotonic := true
		for i in range(1, stamps.size()):
			if stamps[i] <= stamps[i - 1]:
				monotonic = false
		_check(monotonic, "时间戳严格递增（%s）" % str(stamps))
		_check(burst.duration_ms() > 0.0, "总时长 > 0（实际 %.1f ms）" % burst.duration_ms())
	idler.clear()

	# ---- 5c. play_signature 的 fit_seconds：在固定秒数内播完（自动加速）----
	# source 时长 275ms。先验「按原节奏 0.1 秒内播不完」，再验「要求 0.15 秒播完 → 0.25 秒时画完了」。
	idler.play_signature(source)
	_check(is_equal_approx(idler.play_speed(), 1.0),
			"不传 fit_seconds → 按原节奏（%.2f×）" % idler.play_speed())
	await get_tree().create_timer(0.10).timeout
	_check(idler.visible_point_count() < source.point_count(),
			"原速播 0.1 秒还没到底（%d / %d 点）" % [
				idler.visible_point_count(), source.point_count()])

	idler.play_signature(source, 0.15)
	_check(idler.play_speed() > 1.0,
			"fit_seconds 算出了加速倍速（%.2f×）" % idler.play_speed())
	_check(is_equal_approx(idler.play_speed(), source.duration_ms() / 150.0),
			"倍速 = 原时长 / 目标时长（%.2f×）" % idler.play_speed())
	await get_tree().create_timer(0.25).timeout
	_check(idler.visible_point_count() == source.point_count(),
			"要求在 0.15 秒内播完 → 0.25 秒时已经全部画出来（%d / %d 点）" % [
				idler.visible_point_count(), source.point_count()])
	idler.clear()
	var popup := POPUP_SCENE.instantiate() as DialoguePopup
	host.add_child(popup)
	await _settle()
	var who := CandidateResource.new()
	who.display_name = "签名用名字"

	var reported: Array = []
	popup.signature_signed.connect(func(key: StringName, signature: Signature) -> void:
		reported.append([key, signature]))

	var contract_pad := popup.get_node_or_null("Contract/SignaturePad") as SignaturePad
	_check(contract_pad != null, "Contract 牌子上挂着签名画布（Contract/SignaturePad）")

	popup.show_for(&"Contract", who, &"", &"contract.smoke")
	await _settle()
	_check(popup.shown_name() == &"Contract", "show_for 亮起了 Contract")
	# 签名牌现在**没有 Label**（名字由玩家亲手写），所以也不该再按 FILL_RULES 填字 ——
	# 更不该因为找不到 Label 而 push_warning。亮起来以后底下只剩一块空白画布。
	_check(popup.get_node_or_null("Contract/Name") == null, "签名牌上没有 Name 这个 Label")
	var card_kids := 0
	for child in popup.get_node("Contract").get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			card_kids += 1
	_check(card_kids == 1, "签名牌亮起来时只显示一样东西（那块画布），实际 %d 个" % card_kids)
	_check(popup.blocks_advance(), "写了 popup_signature → 签字之前不许翻页")
	_check(contract_pad.is_armed(), "画布被 arm 起来等着落笔")

	_press(contract_pad, Vector2(30, 40))
	_move(contract_pad, Vector2(90, 70))
	_move(contract_pad, Vector2(150, 110))
	_release(contract_pad, Vector2(150, 110))
	await _settle()
	_check(not popup.blocks_advance(), "签完之后可以翻页了")
	_check(reported.size() == 1 and reported[0][0] == &"contract.smoke",
			"签好之后往上报了 key「contract.smoke」（实际 %s）" % str(reported.size()))

	# 已经签过的 key：再亮牌子时直接显示旧笔迹，而且不拦翻页
	var signed_once: Signature = contract_pad.signature()
	popup.hide_all()
	await _settle()
	popup.remember_signature(&"contract.smoke", signed_once)
	popup.show_for(&"Contract", who, &"", &"contract.smoke")
	await _settle()
	_check(contract_pad.is_signed() and contract_pad.signature() != null,
			"已知签过的 key → 画布上直接显示那段旧笔迹")
	_check(not popup.blocks_advance(), "已经签过就不再拦翻页")

	# 牌子上没有画布却写了 popup_signature：只警告，不拦
	popup.show_for(&"AwardPhd", who, &"", &"contract.smoke")
	await _settle()
	_check(not popup.blocks_advance(), "牌子上没有画布时不会拦住对话（只 push_warning）")

	# 没写 popup_signature 就只是普通牌子
	popup.show_for(&"Contract", who)
	await _settle()
	_check(not popup.blocks_advance() and not contract_pad.is_armed(),
			"没写 popup_signature → 画布不进等签状态")

	# 收牌子时画布要松开拾取（否则会白吃掉后面的点击）
	popup.hide_all()
	await _settle()
	_check(not contract_pad.is_armed()
			and contract_pad.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"收牌子之后画布松开拾取")

	# ---- 7. 存档：签名随 RunState 进 JSON 再回来 ----
	var state := RunState.new()
	state.signatures[&"contract.smoke"] = signed_once
	var as_dict := SaveService.to_dict(state)
	_check(as_dict.has("signatures") and (as_dict["signatures"] as Dictionary).has("contract.smoke"),
			"存档字典里有 signatures 这一段")
	var reread := SaveService.from_dict(JSON.parse_string(JSON.stringify(as_dict)))
	var back := reread.signatures.get(&"contract.smoke") as Signature
	_check(back != null, "从存档里读回了那份签名")
	_check(back != null and back.point_count() == signed_once.point_count(),
			"读回来的点数一致（%d）" % (back.point_count() if back != null else -1))
	if back != null:
		var drift := 0.0
		var a: PackedVector2Array = signed_once.strokes[0]["p"]
		var b: PackedVector2Array = back.strokes[0]["p"]
		for i in range(mini(a.size(), b.size())):
			drift = maxf(drift, a[i].distance_to(b[i]))
		_check(drift <= EPSILON, "读回来的笔迹位置不漂（最大 %.6f）" % drift)

	var legacy := SaveService.from_dict({"version": 1, "run_seed": 7, "day": 3})
	_check(legacy.signatures.is_empty(), "老存档没有 signatures 字段 → 读成空表，不炸")

	# ---- 7b. 全链路：签完自动进 RunState（场景侧**一根线都不用接**）----
	# 这条挡的是「功能做好了、但没人调 set_signature」—— 也就是签了个寂寞。
	GameState.start_new_run(20261018)
	var chain_popup := POPUP_SCENE.instantiate() as DialoguePopup
	host.add_child(chain_popup)
	await _settle()
	chain_popup.show_for(&"Contract", null, &"", &"contract.chain")
	await _settle()
	var chain_pad := chain_popup.get_node("Contract/SignaturePad") as SignaturePad
	_press(chain_pad, Vector2(20, 20))
	_move(chain_pad, Vector2(80, 60))
	_move(chain_pad, Vector2(140, 120))
	_release(chain_pad, Vector2(140, 120))
	await _settle()
	_check(GameState.has_signature(&"contract.chain"),
			"签完自动进 RunState（GameState 订阅 EventBus，不必任何场景接线）")
	var stored := GameState.get_signature(&"contract.chain")
	_check(stored != null and stored.point_count() >= 3,
			"RunState 里存着那份笔迹（%d 个点）" % (stored.point_count() if stored != null else 0))

	# 顺手存的那一份档里也得有它（写不进去的环境——没给 APPDATA——就跳过这一条）
	if SaveService.has_auto_save():
		var on_disk: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(GameConfig.AUTO_SAVE_PATH))
		var saved_table: Variant = (on_disk as Dictionary).get("signatures", {}) \
				if on_disk is Dictionary else {}
		_check(saved_table is Dictionary and (saved_table as Dictionary).has("contract.chain"),
				"磁盘上那份自动存档里也有这份签名")
	chain_popup.queue_free()
	await _settle()

	# ---- 8. 换手：落笔时蘸墨，签完还原 ----
	var haohan := HAHAN_SCENE.instantiate()
	host.add_child(haohan)
	await _settle()
	var default_texture: Texture2D = haohan.get_hand_texture()
	_check(haohan.hand_black_texture != null, "Haohan 上配着蘸墨的那只手")
	EventBus.signature_signing_started.emit()
	_check(haohan.get_hand_texture() == haohan.hand_black_texture, "落笔时手换成蘸墨的那只")
	EventBus.signature_signing_finished.emit()
	_check(haohan.get_hand_texture() == default_texture, "这一笔结束 → 手自动还原")
	haohan.queue_free()
	await _settle()

	# ---- 9. 真输入：走真实 GUI 路由，验证「按住之后跑出画布还能收到 motion」----
	# 上面几条是直接喂 _gui_input 的，验不到这条 —— 而「出界吸附」全靠它：
	# 按住左键后跑到画布外面，motion 必须还发给画布（Godot 的 gui.mouse_focus 行为）。
	popup.show_for(&"Contract", who, &"", &"contract.real")
	await _settle()
	var real_pad := popup.get_node("Contract/SignaturePad") as SignaturePad
	var pad_rect := real_pad.get_global_rect()
	_check(pad_rect.size.x > 900.0 and pad_rect.size.y > 300.0,
			"屏幕下方是一大片画布（实际 %s）" % pad_rect.size)
	# 对话框底板在 y 15..258，画布必须让开它，否则点不到（z_index 也不站在画布这边）
	_check(pad_rect.position.y > 258.0,
			"画布落在对话框底板下方（y 从 %.0f 开始）" % pad_rect.position.y)

	# 出界点要选在**画面里**、画布外：viewport 是 1152×648，画布右边还有一条空档
	var outside := Vector2(1120.0, 450.0)
	_check(not pad_rect.has_point(outside) and outside.x < 1152.0,
			"取样点确实在画布之外、但还在画面之内（%s）" % outside)
	_push_root_button(pad_rect.get_center(), true)
	_push_root_move(pad_rect.position + Vector2(40, 40))
	_push_root_move(pad_rect.position + Vector2(120, 90))
	_push_root_move(outside)  # 手指已经跑到画布外面去了
	_push_root_button(outside, false)
	await _settle()

	_check(real_pad.is_signed(), "真实路由下按在画布上、松手即完成（一笔画）")
	var deep: Signature = real_pad.signature()
	_check(deep != null and deep.point_count() >= 3,
			"出界的 motion 也被画布收到了（记下 %d 个点）" % (deep.point_count() if deep != null else 0))
	if deep != null:
		var live_points: PackedVector2Array = deep.strokes[0]["p"]
		var last_point: Vector2 = live_points[live_points.size() - 1]
		# 期望值按画布矩形现算，别写死 —— 版面一改这条不该跟着烂
		var grabbed := Vector2(
			clampf(outside.x, pad_rect.position.x, pad_rect.end.x),
			clampf(outside.y, pad_rect.position.y, pad_rect.end.y))
		var expected_norm := Signature.to_normalized(pad_rect, grabbed)
		_check(last_point.is_equal_approx(expected_norm),
				"画布外面的那个点被吸附到右边界 %s（实际 %s）" % [expected_norm, last_point])

	popup.queue_free()
	await _settle()

	# ---- 10. 对话：等签名时，左键既不给对话推进，也必须落到画布上 ----
	var dialoguer = DIALOGUER_SCENE.instantiate()
	host.add_child(dialoguer)
	await _settle()

	var script_lines: Array[Dictionary] = []
	script_lines.append({
		"speaker_name": "勇者协会",
		"text": "签个字吧。",
		"popup": "Contract",
		"popup_signature": "contract.gate",
		# 故意打慢：下面要验「逐字显示中点击只是快进，不会顺手落笔」
		"char_duration": 0.4,
	})
	script_lines.append({"speaker_name": "勇者协会", "text": "收了。"})
	dialoguer.typer.lines = script_lines
	dialoguer.play()
	await get_tree().process_frame

	# 场景 1：这一句还在逐字显示，玩家点一下想快进
	_check(dialoguer.typer.is_typing, "签名那一句此刻还在逐字显示")
	var gate_pad := dialoguer.get_node("Popup/Contract/SignaturePad") as SignaturePad
	var gate_rect := gate_pad.get_global_rect()
	_push_root_button(gate_rect.get_center(), true)
	_push_root_button(gate_rect.get_center(), false)
	await _settle()
	_check(dialoguer.typer.current_index == 0, "逐字显示中点击只是快进，不翻页")
	_check(not gate_pad.is_signed(), "而且没有顺手把字签了（这一下没落到画布上）")

	# 场景 2：字已经打完，牌子在等签名 —— 这一下归画布
	await _await_typing(dialoguer.typer)
	_check(dialoguer.typer.current_index == 0, "第一句仍在播（current_index=0）")
	_check(dialoguer.blocks_advance(), "牌子在等签名 → 对话被拦着")

	_push_root_button(gate_rect.get_center(), true)
	await _settle()
	_check(dialoguer.typer.current_index == 0,
			"这一下点击没有推进对话（交给了画布，current_index 仍是 0）")

	_push_root_move(gate_rect.get_center() + Vector2(50, 30))
	_push_root_button(gate_rect.get_center() + Vector2(50, 30), false)
	# 松手 → 自动翻页是 deferred 的，多等两帧
	await _settle()
	await _settle()
	_check(gate_pad.is_signed(), "同一串事件把字签上了")
	_check(not dialoguer.blocks_advance(), "签完之后对话不再被拦")
	_check(dialoguer.typer.current_index == 1,
			"**松手就自动进入下一句**（current_index=%d，不用再点一下）" % dialoguer.typer.current_index)

	dialoguer.queue_free()
	await _settle()

	host.queue_free()
	await _settle()


## 一份用来验算的签名：12 个点、每点间隔 25ms。形状不重要，点数和时长要紧。
func _make_signature() -> Signature:
	var signature := Signature.new()
	signature.canvas = PAD_SIZE
	var points := PackedVector2Array()
	var times := PackedFloat32Array()
	for i in range(12):
		points.append(Vector2(0.1 + float(i) * 0.06, 0.3 + sin(float(i) * 0.7) * 0.15))
		times.append(float(i) * 25.0)
	signature.strokes.append({"p": points, "t": times, "g": 0})
	return signature


# ---------------------------------------------------------------------------
# 造输入事件
#
# 两套：
#   _press/_move/_release —— 直接投给画布的 _gui_input，验画布自己的逻辑（坐标是局部坐标）；
#   _push_root_*          —— 往 root viewport 里真的发一次事件，验 GUI 路由与拾取
#                            （坐标就是画布坐标；和 smoke_save_continue 里量点击归属同一个路子）。
# ---------------------------------------------------------------------------


func _press(pad: SignaturePad, local_pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = local_pos
	pad._gui_input(event)


func _move(pad: SignaturePad, local_pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = local_pos
	pad._gui_input(event)


func _release(pad: SignaturePad, local_pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = local_pos
	pad._gui_input(event)


func _push_root_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_tree().root.push_input(event, true)


func _push_root_move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	# 按住左键的移动：真实鼠标事件里这个 mask 是有的，缺了它有些路径会当成悬停
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(event, true)


## 等这一行打完字（最多 2 秒）。打字期间 advance() 只是「立刻显示完」，
## 用它判断有没有推进对话会看走眼，所以先等打完。
func _await_typing(typer: Typer) -> void:
	var deadline := Time.get_ticks_msec() + 2000
	while typer.is_typing and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("[smoke_signature] 全绿：%d 项全部通过" % _checks)
		get_tree().quit(0)
	else:
		print("[smoke_signature] 失败 %d / %d 项：" % [_failures.size(), _checks])
		for failure in _failures:
			print("  失败：%s" % failure)
		get_tree().quit(1)
