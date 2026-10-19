extends Node

## 启动引导（ARCHITECTURE.md §2 / §4）：加载 DataDB → 检查存档 → 开场 / 主菜单。
##
## 这个场景现在是**真正的启动场景**（project.godot 的 application/run/main_scene），
## 因为「第一次启动要播开场」这件事只能有一个入口来做 —— 挂在主菜单里的话，
## 自检每次实例化 main_menu 都会被拽去播开场。
##
## 路由规则见 scripts/core/flow/opening_flow.gd：
##   没看过开场 → 先播 `opening`（播完自己回主菜单），之后每次启动直接进主菜单。

func _ready() -> void:
	# DataDB 在自己的 _ready 里已经扫过一遍，这里只做兜底与提示
	if not DataDB.is_loaded():
		DataDB.reload()
	if DataDB.total_count() == 0:
		push_warning("[Boot] res://data/ 下没有扫到任何静态资源，检查目录结构与 .tres 的 id 字段")

	print("[Boot] 静态资源 %d 项；存档：%s" % [
		DataDB.total_count(),
		"有（可继续）" if SaveService.has_any_save() else "无",
	])

	# 第一次启动：先播开场，再回主菜单。
	# ⚠️ 先把「看过了」记下来再切场景：开场播完会回主菜单，
	#    万一玩家中途退出，下次启动不该再被拦一遍（宁可少播，也不要每次都播）。
	if OpeningFlow.should_play_on_launch():
		OpeningFlow.mark_seen()
		print("[Boot] 第一次启动 → 先播开场剧情")
		SceneRouter.goto_scene(&"opening", true, false)
		return

	# 引导阶段不进返回栈
	SceneRouter.goto_scene(&"main_menu", true, false)
