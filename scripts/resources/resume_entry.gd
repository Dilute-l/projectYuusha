class_name ResumeEntry
extends Resource

## 简历条目（ARCHITECTURE.md §3.2）。
##
## 每条含**两样**东西：简历上写的那句话，以及针对该条的追问对话存在哪个 json 里。
## 是否可信，由玩家结合候选人的属性、等级、职业、特质与手册常识自行判断。

## 简历上写的那句话，例如「我曾单独讨伐过三只食人魔。」
@export_multiline var description: String = ""

## 针对本条的追问对话：**一段独立 json 文件的路径**（一条追问一个文件）。
##
## 台词不住在候选人档案里 —— 档案只留一个路径，正文全部写在 json 里：
##
##     res://data/asks/c_0001_1.json
##     [
##         { "speaker_name": "面试官", "text": "你是怎么打败它们的？" },
##         { "speaker_name": "棍木",   "text": "趁它们分食时逐个击破的。" }
##     ]
##
## 文件格式就是 data/dialogue.json 里**一段对话**的格式（也可以写成
## `{ "段名": [ ... ] }`），所以 Typer 那套逐字显示 / 点击推进 / 段级 config
## 全都照用，不需要任何额外机制。见 interview.gd 的 _on_resume_entry_asked()。
@export_file("*.json") var ask_path: String = ""
