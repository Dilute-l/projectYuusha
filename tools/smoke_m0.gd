extends Node

## M0 自检脚本（不需要编辑器，也不需要打开场景）。
##
## 用法（跑的是一个空场景，Autoload 会照常加载，所以能按裸标识符访问单例）：
##   & "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_m0.tscn
##
## 覆盖 M0 验收标准：
##   · Autoload 齐备（EventBus / RngService / DataDB / GameState / SaveService / AudioService / SceneRouter）
##   · DataDB 能扫到 data/ 下的资源
##   · RngService 同种子可复现、每日派生种子符合 day_seed = run_seed ^ day_index
##   · GameState 能连续走完 10 天（第 10 天不再推进，应走结局）
##   · SaveService 存读档后状态一致
##   · SceneRouter 能真实完成 主菜单 → 每日循环 的场景切换
##   · 在真实 day_loop 场景里点满 10 天 × 5 阶段，并落到结局场景
##
## 全部通过退出码 0；有失败项退出码 1。

## 单次运行允许的帧数上限（headless 下帧率很高，约等于几十秒）
const FRAME_BUDGET: int = 100000

## 常驻 runner 的节点名：自检要真的切场景，而切场景会释放 current_scene，
## 所以自检逻辑挂在这个名字的节点上（它是 root 的子节点，不是当前场景）。
const RUNNER_NAME: String = "SmokeM0Runner"

var _failures: Array[String] = []
var _check_count: int = 0

var _step: int = 0
var _frames: int = 0
var _had_auto_save: bool = false

## 十天走完没有。走十天是跨帧的（见 _walk_day_loop），所以由协程置真、_process 等它。
var _walk_done: bool = false


func _ready() -> void:
	if name == RUNNER_NAME:
		return
	# 场景根的身份：把自检逻辑交给 root 下的常驻 runner，然后自己静待被切走
	var runner := Node.new()
	runner.name = RUNNER_NAME
	runner.set_script(get_script())
	get_tree().root.add_child.call_deferred(runner)
	set_process(false)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > FRAME_BUDGET:
		_failures.append("自检超时（%d 帧内未完成）" % FRAME_BUDGET)
		_finish()
		return

	match _step:
		0:
			# 过场淡入淡出在自检里设为瞬时，避免依赖真实时间
			SceneRouter.set_fade_duration(0.0)
			_run_sync_checks()
			_step = 1
			SceneRouter.goto_scene(&"main_menu", true)
		1:
			if not SceneRouter.is_transitioning:
				_check(SceneRouter.current_scene_key() == &"main_menu", "SceneRouter 切到主菜单")
				_press_start_button()
				_step = 2
		2:
			if not SceneRouter.is_transitioning:
				_check(SceneRouter.current_scene_key() == &"day_loop", "主菜单 Start 按钮把自己带到了每日循环")
				_check(GameState.has_run(), "Start 按钮开出了一局")
				_check(SceneRouter.can_go_back(), "SceneRouter 记下了返回栈")
				# 走十天是**跨帧**的：day_loop 有「同一帧只许推进一次」的重入锁
				# （_advance_locked + call_deferred），一帧内连点 70 次只有第一次算数。
				# 所以这里交给一个协程按帧点，本状态机只等它收工。
				_walk_day_loop()
				_step = 20
		20:
			if _walk_done:
				_step = 3
		3:
			# 第 10 天走完会请求切到结局场景，等它落地
			if not SceneRouter.is_transitioning:
				if SceneRouter.current_scene_key() == &"ending":
					_check(true, "十天走完后进入结局场景")
					_press_ending_back_button()
					_step = 4
				else:
					_failures.append("十天走完后没有进入结局场景（当前：%s）" % SceneRouter.current_scene_key())
					_finish()
		4:
			if not SceneRouter.is_transitioning:
				_check(SceneRouter.current_scene_key() == &"main_menu", "结局场景「返回主菜单」把闭环收上了")
				_finish()

# ---------------------------------------------------------------------------
# 同步检查（一帧内即可完成的部分）
# ---------------------------------------------------------------------------


func _run_sync_checks() -> void:
	print("=== M0 Autoload 自检 ===")
	_check_autoloads()
	_check_event_bus()
	_check_data_db()
	_check_candidate_data()
	_check_rng_service()
	_check_game_state()
	_check_save_service()
	_check_audio_service()
	_check_scene_router()


func _check_autoloads() -> void:
	print("[1] Autoload 注册")
	for node_name in ["EventBus", "RngService", "DataDB", "GameState", "SaveService", "AudioService", "SceneRouter"]:
		_check(get_tree().root.get_node_or_null(node_name) != null, "Autoload 存在：%s" % node_name)


func _check_event_bus() -> void:
	print("[2] EventBus 信号")
	var received: Array = []
	EventBus.day_started.connect(func(day_index: int) -> void: received.append(day_index))
	EventBus.day_started.emit(7)
	_check(received == [7], "信号可连接并收到参数")
	_check(EventBus.has_signal("day_phase_changed") and EventBus.has_signal("verdict_issued"), "§5 约定的信号齐全")


func _check_data_db() -> void:
	print("[3] DataDB 扫描")
	_check(DataDB.is_loaded(), "已完成一次扫描")
	_check(DataDB.count(&"jobs") == 3, "data/jobs 下有 3 份职业资源（实际 %d）" % DataDB.count(&"jobs"))
	_check(DataDB.get_job(&"job.fighter") != null, "可按 id 查询职业：job.fighter")
	_check(DataDB.get_job(&"job.not_exist") == null, "未知 id 返回 null 而不是报错")
	# 还没有数据的类别必须安全返回空，M5 才会有内容
	_check(DataDB.get_day_config(999) == null, "不存在的天数安全返回 null")
	_check(DataDB.get_narrative_rules().is_empty(), "尚无 data/narrative 时返回空数组")


## 候选人 / 每日名单的数据层（ARCHITECTURE.md §3.1 / §3.4）。
## 这一节盯的是「面试者信息与简历内容都在 data/ 里，代码里不写死」：
## 每个人一份 data/candidates/*.tres（含立绘配方 + 逐条简历），
## 每天一份 data/days/day_XX.tres（只列今天出场哪几个人）。
func _check_candidate_data() -> void:
	print("[3.1] 候选人 / 每日名单")
	var candidate_count := DataDB.count(&"candidates")
	_check(candidate_count > 0, "data/candidates 下有候选人（实际 %d）" % candidate_count)
	_check(DataDB.count(&"traits") > 0, "data/traits 下有特质（实际 %d）" % DataDB.count(&"traits"))

	var first := DataDB.get_candidate(&"c_0001")
	_check(first != null, "可按 id 查候选人：c_0001")
	if first != null:
		_check(not first.display_name.strip_edges().is_empty(), "候选人填了姓名")
		_check(
			first.job != null and not first.job.display_name.strip_edges().is_empty(),
			"候选人引用的职业带 display_name"
		)
		_check(not first.resume.is_empty(), "候选人带简历条目（%d 条）" % first.resume.size())
		_check(first.portrait_race != &"", "候选人带立绘配方（race=%s）" % first.portrait_race)
		_check(not first.resume_header.strip_edges().is_empty(), "候选人在数据里填了抬头（resume_header）")

		var entries_ok := true
		for entry in first.resume:
			if entry == null:
				entries_ok = false
				continue
			if entry.description.strip_edges().is_empty() \
					or entry.ask_path.strip_edges().is_empty():
				entries_ok = false
		_check(entries_ok, "每条简历都齐了描述 + 追问 json 路径两样")

		# 追问的台词自 §11 起单独成文件（一条追问一份 json）。75 份 json 里最容易错的
		# 就是「路径写错 / 文件忘了提交 / json 写坏」这三样，所以这里把全部候选人一次过完。
		var asks_ok := true
		for candidate_id in DataDB.get_ids(&"candidates"):
			var candidate := DataDB.get_candidate(candidate_id)
			if candidate == null:
				continue
			for entry in candidate.resume:
				if entry == null or not _ask_json_ok(entry.ask_path):
					asks_ok = false
		_check(asks_ok, "每位候选人的每条追问都指到一份存在的、能读的 json")

	# 抬头是写死在数据里的一段字，代码不再按字段拼 —— 所以每个人都得有
	var headers_ok := true
	for id in DataDB.get_ids(&"candidates"):
		var candidate := DataDB.get_candidate(id)
		if candidate == null or candidate.resume_header.strip_edges().is_empty():
			headers_ok = false
	_check(headers_ok, "每位候选人都自带一段抬头文案")

	# 每天都要有写死的名单，slots 不能超过当天人数，名单里的人必须都在 data/candidates/ 里
	var days_ok := true
	var slots_ok := true
	var listed: Array[StringName] = []
	for day in range(1, GameConfig.TOTAL_DAYS + 1):
		var config := DataDB.get_day_config(day)
		if config == null or config.candidates.is_empty():
			days_ok = false
			continue
		if config.slots < 1 or config.slots > config.candidates.size():
			slots_ok = false
		for candidate in config.candidates:
			if candidate == null or candidate.id == &"":
				days_ok = false
				continue
			listed.append(candidate.id)
			if DataDB.get_candidate(candidate.id) == null:
				days_ok = false
	_check(
		days_ok,
		"第 1..%d 天都有出场名单，且名单里的每个人都能在 data/candidates/ 里查到" % GameConfig.TOTAL_DAYS
	)
	_check(slots_ok, "每天的名额 slots 都没超过当天人数")
	_check(
		listed.size() == candidate_count,
		"每日名单合起来正好覆盖全部候选人（名单 %d 人次 / 数据 %d 份）" % [listed.size(), candidate_count]
	)


func _check_rng_service() -> void:
	print("[4] RngService 可复现性")
	RngService.start_run(20261005)
	var first: Array[int] = [RngService.day_rng(1).randi(), RngService.day_rng(1).randi()]
	RngService.start_run(20261005)
	var second: Array[int] = [RngService.day_rng(1).randi(), RngService.day_rng(1).randi()]
	_check(first == second, "同种子 → 每日随机流完全一致")
	_check(RngService.day_seed(3) == (20261005 ^ 3), "day_seed = run_seed ^ day_index")
	_check(RngService.day_seed(1) != RngService.day_seed(2), "不同天派生不同种子")

	# 命名流互不干扰：多抽一条别的流，不应改变本条流的后续结果
	RngService.start_run(7)
	var alpha_a: Array[int] = [RngService.stream(&"alpha").randi(), RngService.stream(&"alpha").randi()]
	RngService.start_run(7)
	var alpha_b: int = RngService.stream(&"alpha").randi()
	RngService.stream(&"beta").randi()
	alpha_b = RngService.stream(&"alpha").randi()
	_check(alpha_a[1] == alpha_b, "命名流互不干扰（抽取别的流不改变本流序列）")

	# 0 权重的条目永不被抽中
	RngService.start_run(99)
	var entries := [
		{ "id": "always", "weight": 1.0 },
		{ "id": "never", "weight": 0.0 },
	]
	var always := true
	for _i in 50:
		var picked: Dictionary = RngService.weighted_pick(&"pick", entries)
		if picked.get("id", "") != "always":
			always = false
	_check(always, "weighted_pick 不会抽中 0 权重条目")


func _check_game_state() -> void:
	print("[5] GameState 十天空流程")
	var phase_events: Array[int] = []
	EventBus.day_phase_changed.connect(func(phase: int) -> void: phase_events.append(phase))

	GameState.start_new_run(12345)
	_check(GameState.has_run(), "开新局后 has_run 为真")
	_check(GameState.get_day() == 1 and GameState.get_phase() == DayPhase.Phase.DAY_BRIEFING, "新局从第 1 天 DAY_BRIEFING 开始")

	# 当日名单是「本日过程量」，不进存档 —— 由 GameState 在开局 / 换天时按天从 data/days/ 载入
	var day_one := DataDB.get_day_config(1)
	var day_last := DataDB.get_day_config(GameConfig.TOTAL_DAYS)
	_check(
		day_one != null and GameState.current_candidates.size() == day_one.candidates.size(),
		"开局即载入第 1 天名单（%d 人）" % GameState.current_candidates.size()
	)

	var walked := true
	for day in range(1, GameConfig.TOTAL_DAYS + 1):
		if GameState.get_day() != day:
			walked = false
		GameState.set_phase(DayPhase.Phase.BATTLE_REPORT)
		GameState.record_day_score(day, day * 10, { "true_power": day * 10 })
		if day < GameConfig.TOTAL_DAYS:
			if not GameState.advance_day():
				walked = false
		elif GameState.advance_day():
			walked = false  # 第 10 天不该再推进
	_check(walked, "能连续走完 10 天，第 10 天不再推进（应进结局）")
	_check(GameState.is_last_day(), "第 10 天 is_last_day 为真")
	_check(
		day_last != null and GameState.current_candidates.size() == day_last.candidates.size(),
		"换到最后一天时名单也跟着换（%d 人）" % GameState.current_candidates.size()
	)
	_check(GameState.get_total_score() == 550, "累计分 = 550（实际 %d）" % GameState.get_total_score())
	_check(GameState.get_day_score(3) == 30, "单日分数按第 n 天索引")

	GameState.hire(&"c_0001")
	_check(GameState.is_hired(&"c_0001") and not GameState.hire(&"c_0001"), "录用去重")
	GameState.issue_verdict(&"c_0002", true)
	GameState.issue_verdict(&"c_0002", true)
	GameState.issue_verdict(&"c_0003", false)
	_check(GameState.get_passed_ids() == [&"c_0002"], "本日通过者去重，且不含未通过者")
	GameState.add_flag(&"liar_hired", 1)
	GameState.add_flag(&"liar_hired", 2)
	_check(GameState.get_flag(&"liar_hired") == 3, "flag 可累加")
	_check(GameState.unlock_handbook_entry(&"monster.ogre"), "手册条目首次解锁返回 true")
	_check(not GameState.unlock_handbook_entry(&"monster.ogre"), "重复解锁返回 false")
	_check(not phase_events.is_empty(), "阶段切换广播了 day_phase_changed")


func _check_save_service() -> void:
	print("[6] SaveService 存读档")
	_had_auto_save = SaveService.has_auto_save()
	GameState.set_phase(DayPhase.Phase.TEAM_BUILD)
	var before := {
		"day": GameState.get_day(),
		"seed": GameState.get_run_seed(),
		"total": GameState.get_total_score(),
		"roster": GameState.get_roster(),
		"flag": GameState.get_flag(&"liar_hired"),
		"phase": String(GameState.get_phase_name()),
		"unlocked": GameState.is_handbook_unlocked(&"monster.ogre"),
	}

	_check(SaveService.autosave(), "自动存档写入成功")
	_check(SaveService.save_to_slot(1), "手动存档写入成功")

	GameState.clear_run()
	_check(not GameState.has_run(), "clear_run 后回到未开局")

	_check(SaveService.load_auto(), "自动存档读取成功")
	var after := {
		"day": GameState.get_day(),
		"seed": GameState.get_run_seed(),
		"total": GameState.get_total_score(),
		"roster": GameState.get_roster(),
		"flag": GameState.get_flag(&"liar_hired"),
		"phase": String(GameState.get_phase_name()),
		"unlocked": GameState.is_handbook_unlocked(&"monster.ogre"),
	}
	_check(before == after, "读档后状态与存档前一致（day/seed/分数/名单/flag/阶段/手册）")
	if before != after:
		printerr("   存档前：%s" % before)
		printerr("   读档后：%s" % after)

	_check(SaveService.load_from_slot(1), "手动存档读取成功")
	var slots := SaveService.list_slots()
	_check(slots.size() == GameConfig.MAX_SAVE_SLOTS, "存档槽列表长度 = MAX_SAVE_SLOTS")
	_check(slots[0].get("exists", false) == true and slots[1].get("exists", false) == false, "槽位摘要能区分空槽")
	_check(int(slots[0].get("total_score", -1)) == 550, "槽位摘要带累计分")

	_check(SaveService.delete_slot(1), "删除存档槽")
	_check(not SaveService.has_slot(1), "删除后槽位为空")
	if not _had_auto_save:
		# 自检产生的自动存档不留在磁盘上
		DirAccess.remove_absolute(GameConfig.AUTO_SAVE_PATH)


func _check_audio_service() -> void:
	print("[7] AudioService")
	_check(AudioServer.get_bus_index(&"BGM") != -1 and AudioServer.get_bus_index(&"SFX") != -1, "BGM / SFX 总线已自动创建")
	AudioService.set_volumes(0.8, 0.5, 0.6)
	_check(is_equal_approx(AudioService.get_volume(&"BGM"), 0.5), "BGM 音量可设置")
	_check(is_equal_approx(AudioService.get_volume(&"Master"), 0.8), "主音量可设置")
	# M0 还没有音频资源：必须只警告、返回 false，不能崩
	_check(AudioService.play_bgm("res://assets/audio/bgm/not_exist.ogg") == false, "缺失 BGM 资源返回 false")
	_check(AudioService.play_sfx("res://assets/audio/sfx/not_exist.wav") == false, "缺失音效资源返回 false")
	AudioService.set_volumes(1.0, 1.0, 1.0)


func _check_scene_router() -> void:
	print("[8] SceneRouter 场景表")
	var all_exist := true
	for scene_key in SceneRouter.SCENES.keys():
		if not ResourceLoader.exists(SceneRouter.scene_path_for(scene_key)):
			all_exist = false
			printerr("  缺失场景文件：%s -> %s" % [scene_key, SceneRouter.scene_path_for(scene_key)])
	_check(all_exist, "SCENES 表里的场景文件都存在")
	_check(SceneRouter.key_for_path("res://scenes/day/day_loop.tscn") == &"day_loop", "路径反查 key")
	_check(SceneRouter.has_node("TransitionOverlay"), "过场遮罩已建立（切场景时不会随场景释放）")


## 按主菜单上真实的 Startgame 按钮 —— 验证的是玩家会走的那条路
func _press_start_button() -> void:
	print("[8.1] 主菜单 Start 按钮")
	var menu: Node = get_tree().current_scene
	# 注意用 BaseButton：Startgame 是 TextureButton，不是 Button
	var button: BaseButton = menu.get_node_or_null("Startgame") as BaseButton
	_check(button != null, "主菜单上有 Startgame 按钮")
	_check(button != null and not button.pressed.get_connections().is_empty(), "Startgame 按钮已接上脚本方法")
	if button == null:
		return
	GameState.clear_run()
	button.pressed.emit()


## 按结局场景的「返回主菜单」——确认十天流程是个闭环，不是死胡同
func _press_ending_back_button() -> void:
	var ending_scene: Node = get_tree().current_scene
	var button: BaseButton = ending_scene.get_node_or_null("Hud/Margin/Layout/BackButton") as BaseButton
	_check(button != null, "结局场景上有返回按钮")
	if button == null:
		return
	button.pressed.emit()


## 在真实的 day_loop 场景上按阶段顺序点满十天 —— M0 的「能连续走完 10 天空流程」。
##
## 这是个协程：**每次推进之间等一帧**。day_loop.advance() 有「同一帧只许推进一次」
## 的重入锁（_advance_locked，靠 call_deferred 解锁），一帧内连点 70 次只有第一次生效 ——
## 按帧点才等价于玩家真实的点击节奏。跑完把 _walk_done 置真，由 _process 的状态机接着走。
func _walk_day_loop() -> void:
	print("[9] 每日流程（真实 day_loop 场景，点的是 HUD 上的按钮）")
	var loop_scene: Node = get_tree().current_scene
	_check(loop_scene != null and loop_scene.has_method("advance"), "当前场景是带脚本的 day_loop")
	if loop_scene == null:
		_walk_done = true
		return

	# 前面的存读档检查把状态留在第 10 天，这里重开一局从头走
	GameState.start_new_run(20261010)
	_check(
		GameState.get_day() == 1 and GameState.get_phase() == DayPhase.Phase.DAY_BRIEFING,
		"重开一局后回到第 1 天 DAY_BRIEFING"
	)

	var button: BaseButton = loop_scene.get_node_or_null("FlowHud/Hud/Margin/Layout/NextButton") as BaseButton
	_check(button != null and not button.pressed.get_connections().is_empty(), "占位 HUD 的推进按钮已接线")

	var day_phases := DayDirector.phases_of_day()
	var walk_ok := true
	var presses := 0
	var phase_log: Array[String] = []
	for day in range(1, GameConfig.TOTAL_DAYS + 1):
		for phase in day_phases:
			if GameState.get_day() != day or GameState.get_phase() != phase:
				walk_ok = false
				phase_log.append("第 %d 天期望 %s，实际 %s（第 %d 天）" % [
					day, DayPhase.to_name(phase), DayPhase.to_name(GameState.get_phase()), GameState.get_day(),
				])
			if button != null:
				button.pressed.emit()
			else:
				loop_scene.call("advance")
			presses += 1
			await get_tree().process_frame

	_check(walk_ok, "按 DayBriefing→SpecialEvent→Interview→TeamBuild→BattleReport 走完 10 天")
	if not walk_ok:
		for line in phase_log:
			printerr("   " + line)
	_check(presses == GameConfig.TOTAL_DAYS * day_phases.size(), "共推进 %d 次（10 天 × %d 阶段）" % [presses, day_phases.size()])
	_check(GameState.get_day() == GameConfig.TOTAL_DAYS, "走完后停在第 %d 天" % GameConfig.TOTAL_DAYS)
	_check(GameState.get_phase_name() == DayPhase.to_name(DayPhase.Phase.ENDING), "走完后阶段是 ENDING")
	_check(SaveService.has_auto_save(), "每日流程里自动存档已生成")
	_walk_done = true

# ---------------------------------------------------------------------------
# 收尾
# ---------------------------------------------------------------------------


## 追问 json 是否可用：路径没空 + 文件在 + 是个能解析的**非空数组**。
## 只认行数组这一种写法 —— 这是 data/asks/ 的约定（见 resume_entry.gd 的 ask_path）。
func _ask_json_ok(path: String) -> bool:
	if path.strip_edges().is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed is Array and not (parsed as Array).is_empty()


func _check(condition: bool, label: String) -> void:
	_check_count += 1
	if condition:
		print("  [OK]   %s" % label)
	else:
		_failures.append(label)
		printerr("  [FAIL] %s" % label)


func _finish() -> void:
	set_process(false)
	print("=== 自检结束：%d 项检查，%d 项失败 ===" % [_check_count, _failures.size()])
	for failure in _failures:
		printerr("  失败：%s" % failure)
	# 退出前留一点时间让日志冲刷：在编辑器里运行时，同一帧内 print + quit
	# 会把最后的汇总行丢掉（转发还没写完进程就没了）
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(1 if not _failures.is_empty() else 0)
