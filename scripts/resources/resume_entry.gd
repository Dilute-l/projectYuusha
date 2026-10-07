class_name ResumeEntry
extends Resource

## 简历条目（ARCHITECTURE.md §3.2）。
## 每条含三样东西：简历上写的那句话、针对该条的追问、追问后得到的回答。
## 是否可信，由玩家结合候选人的属性、等级、职业、特质与手册常识自行判断。

## 简历上写的那句话，例如「我曾单独讨伐过三只食人魔。」
@export_multiline var description: String = ""

## 针对本条的追问，例如「你是怎么打败它们的？」
@export_multiline var question: String = ""

## 针对本条追问之后得到的回答，例如「那次是趁它们分食时逐个击破的。」
@export_multiline var answer: String = ""
