@tool
extends McpTestSuite

## 一次性验证 hover 判定的几个默认值。用完即删。

func suite_name() -> String:
	return "hover_defaults"


func test_control_default_mouse_filter() -> void:
	var c := Control.new()
	assert_eq(c.mouse_filter, Control.MOUSE_FILTER_STOP, "Control 默认 STOP")
	c.free()


func test_label_default_mouse_filter() -> void:
	var l := Label.new()
	assert_eq(l.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Label 默认 IGNORE")
	l.free()


func test_zero_size_control_never_hits() -> void:
	# 0×0 的 Control 对任何点都不算命中——这决定对话框根节点（当前是 0×0）
	# 会不会从按钮手里抢走 hover
	var c := Control.new()
	assert_false(c.has_point(Vector2(1, 1)), "0×0 Control 命中 (1,1)?")
	assert_false(c.has_point(Vector2.ZERO), "0×0 Control 连 (0,0) 都不命中?")
	c.free()


func test_sized_control_hits() -> void:
	var c := Control.new()
	c.size = Vector2(100, 50)
	assert_true(c.has_point(Vector2(1, 1)), "有尺寸的 Control 命中内部点")
	assert_false(c.has_point(Vector2(200, 200)), "有尺寸的 Control 不命中外部点")
	c.free()
