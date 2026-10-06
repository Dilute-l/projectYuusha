extends Node

## 启动引导（ARCHITECTURE.md §2 / §4）：加载 DataDB → 检查存档 → 跳主菜单。
##
## 注意：当前项目的主场景是 `main_menu.tscn`（见 project.godot 的 application/run/main_scene），
## 所以这个场景平时不会被走到。保留它的用途是「开场演出 / 存档位选择 UI」：
## 需要时把 project.godot 的 `application/run/main_scene` 改回 `res://scenes/boot/boot.tscn` 即可。

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

	# 引导阶段不进返回栈
	SceneRouter.goto_scene(&"main_menu", true, false)
