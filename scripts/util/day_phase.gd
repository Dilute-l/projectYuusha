class_name DayPhase
extends RefCounted

## 每日流程状态机的阶段（ARCHITECTURE.md §4「每日流程」）。
##
## 枚举用于逻辑与信号（`EventBus.day_phase_changed(phase: int)`），
## `StringName` 形式用于存档（`RunState.phase`，见 §7 的 "TEAM_BUILD"）。
## 两者通过 `to_name()` / `from_name()` 互转，保证存档里存的是可读字符串。

## 每日流程阶段
enum Phase {
	DAY_BRIEFING,   ## 国王下旨：今日名额 / 新解锁的面试内容 / 教程提示
	SPECIAL_EVENT,  ## 记者报道今日魔物 / 特殊规则
	SCREENING,      ## 招人：浏览简历
	INTERVIEW,      ## 招人：追问面试（与 SCREENING 可来回切换）
	TEAM_BUILD,     ## 从通过者中挑满名额
	BATTLE_REPORT,  ## 马车上看战报演出、车夫对话、当日分数
	ENDING,         ## 第 10 天之后的结局场景
}

## 与 Phase 一一对应的名字表，索引即枚举值。
##
## ⚠️ 增删 Phase 里的一项时，NAMES / DISPLAY_NAMES / ORDER 必须在**对应下标**同步增删：
## 前两张表是「索引即枚举值」的平行数组，漏改会让所有后续阶段的存档名整体错位，
## 而且**不会报任何错**。
const NAMES: Array[StringName] = [
	&"DAY_BRIEFING",
	&"SPECIAL_EVENT",
	&"SCREENING",
	&"INTERVIEW",
	&"TEAM_BUILD",
	&"BATTLE_REPORT",
	&"ENDING",
]

## 阶段顺序（不含 ENDING），day_loop 据此推进
const ORDER: Array[int] = [
	Phase.DAY_BRIEFING,
	Phase.SPECIAL_EVENT,
	Phase.SCREENING,
	Phase.INTERVIEW,
	Phase.TEAM_BUILD,
	Phase.BATTLE_REPORT,
]

## 便于在占位 HUD / 调试输出里显示的中文阶段名，索引与 Phase 一一对应
const DISPLAY_NAMES: Array[String] = [
	"国王下旨",
	"今日事件",
	"浏览简历",
	"追问面试",
	"组队",
	"战报",
	"结局",
]


## 枚举 -> 存档用名字
static func to_name(phase: int) -> StringName:
	if phase < 0 or phase >= NAMES.size():
		return NAMES[Phase.DAY_BRIEFING]
	return NAMES[phase]


## 枚举 -> 显示名（占位 HUD / 调试用；正式文案在 M5 定稿）
static func display_name(phase: int) -> String:
	if phase < 0 or phase >= DISPLAY_NAMES.size():
		return DISPLAY_NAMES[Phase.DAY_BRIEFING]
	return DISPLAY_NAMES[phase]


## 存档用名字 -> 枚举；无法识别时回退到 DAY_BRIEFING
static func from_name(phase_name: StringName) -> int:
	var index := NAMES.find(phase_name)
	return index if index >= 0 else Phase.DAY_BRIEFING


## 「招人」阶段：Screening 与 Interview 都属于招人，可来回切换
static func is_recruiting(phase: int) -> bool:
	return phase == Phase.SCREENING or phase == Phase.INTERVIEW


## 该阶段是否属于某个具体的一天（ENDING 不属于任何一天）
static func is_day_phase(phase: int) -> bool:
	return ORDER.has(phase)


## 下一个阶段。当天最后一个阶段（BATTLE_REPORT）没有「下一个」，
## 这里回到 DAY_BRIEFING —— 是否真的换天 / 进结局由 DayDirector 与 GameState.advance_day 决定。
static func next(phase: int) -> int:
	var index := ORDER.find(phase)
	if index < 0 or index >= ORDER.size() - 1:
		return Phase.DAY_BRIEFING
	return ORDER[index + 1]
