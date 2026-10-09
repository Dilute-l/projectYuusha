class_name ResumeToken
extends Button

## 单条简历词条（ARCHITECTURE.md §4「resume_token.tscn」，复用控件）。
##
## 表现层控件，只负责把一条简历正文铺在简历纸上：
##   - 正文走 Button 自身的 text + 自动换行，Button 会自己算最小高度，
##     放进 VBoxContainer 不用固定高度，长句子也不会被裁掉；
##   - 悬停高亮是纯 theme_override_styles 做的（normal / hover 两个 StyleBox），
##     不需要脚本插手，脚本里没有一处 _on_mouse_entered。
##
## ⚠️ 点击效果在**别处**：本控件只发 selected，由 resume.gd 订阅后在旁边弹出
##   词条菜单（「追问」按钮在里面）—— 见 §10.7。
##   为了让「选中」不靠按钮自己画：pressed 与 normal 用的是同一个
##   StyleBox（见 resume_token.tscn），并且 focus_mode 关闭，不会残留焦点框。

## 本条被点击，由 resume.gd 订阅后弹出词条菜单。
## 参数是条目在简历中的序号（从 0 开始），方便调用方回去查 ResumeEntry。
signal selected(entry_index: int)

## 本条在简历中的序号（从 0 开始）。跟着 selected 一起抛出去。
var entry_index: int = 0


func _ready() -> void:
	pressed.connect(_on_pressed)


## 填一条词条：序号 + 正文。入树前后调用都可以。
func set_entry(index: int, description: String) -> void:
	entry_index = index
	text = _format_line(index, description)


## 只换正文，保留序号
func set_description(description: String) -> void:
	set_entry(entry_index, description)


func _on_pressed() -> void:
	selected.emit(entry_index)


## 版面文案：「01  我在边境哨所单挑过一只食人魔。」（正文来自 data/candidates/*.tres）
## 序号补零是为了在简历纸上对齐成一列。
func _format_line(index: int, description: String) -> String:
	return "%02d  %s" % [index + 1, description]
