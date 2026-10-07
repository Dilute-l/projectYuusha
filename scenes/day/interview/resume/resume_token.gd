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
## ⚠️ 当前阶段：**点击没有任何效果**。
##   §4 给这个控件定的对外信号是 selected，这里按架构预留并照常发出，
##   但 resume.gd 目前不订阅它 —— 没有任何订阅者时 emit 就是一次空操作，
##   玩家点上去不会有任何反应。
##   追问流程（§6.2：先给 question、再展开 answer）留到 M2。
##   为了让「点了没反应」在视觉上也成立：pressed 与 normal 用的是同一个
##   StyleBox（见 resume_token.tscn），并且 focus_mode 关闭，不会残留焦点框。

## 本条被点击。M2 接追问流程时，由 resume.gd 订阅它。
## 参数是条目在简历中的序号（从 0 开始），方便调用方回去查 ResumeEntry。
signal selected(entry_index: int)

## 本条在简历中的序号（从 0 开始）。跟着 selected 一起抛出去。
var entry_index: int = 0


func _ready() -> void:
	# 见文件头：现在没人订阅 selected，所以这里连上也不会产生任何表现。
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


## 版面文案：「01  Slew three ogres single-handedly.」
## 序号补零是为了在简历纸上对齐成一列。
func _format_line(index: int, description: String) -> String:
	return "%02d  %s" % [index + 1, description]
