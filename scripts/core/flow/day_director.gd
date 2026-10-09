class_name DayDirector
extends RefCounted

## 每日流程推进规则（ARCHITECTURE.md §4）。**纯静态函数：不碰节点、不改状态**。
##
## day_loop.gd 只做两件事：问 DayDirector「下一步是什么」，然后按 DayPhase 换子场景。
## 这样「第 10 天走完该进结局」这类规则可以被测试直接调用，不需要跑起场景树。
##
## 流程（§4）：
##   DayBriefing → SpecialEvent → 招人（Interview）→ TeamBuild
##   → BattleReport → 第 1〜9 天回到 DayBriefing；第 10 天进 Ending

## 推进结果的三种走向
enum Step {
	PHASE,    ## 当天内推进到下一个阶段
	DAY_END,  ## 当天流程走完，进入下一天
	RUN_END,  ## 十天走完，进结局场景
}

## 当天最后一个阶段
const LAST_PHASE: int = DayPhase.Phase.BATTLE_REPORT

## 由 interview.tscn 承载的阶段：
##   DAY_BRIEFING   国王下旨
##   SPECIAL_EVENT  记者报道今日魔物 / 特殊规则
##   INTERVIEW      招人：看简历、追问面试、录用判定
##
## 这三段**共用同一个场景实例**：day_loop 在同一 scene_key 下不重建实例，只调 set_phase()，
## 所以三段之间切换是无缝的。
const INTERVIEW_HOSTED: Array[int] = [
	DayPhase.Phase.DAY_BRIEFING,
	DayPhase.Phase.SPECIAL_EVENT,
	DayPhase.Phase.INTERVIEW,
]


## 问：当前阶段之后是什么？
## 返回 { "step": Step, "phase": int, "day": int }
##   step = PHASE   → 把阶段切到 phase（同一天内）
##   step = DAY_END → 天数 +1，阶段切到 phase（DAY_BRIEFING）
##   step = RUN_END → 去结局场景，phase = ENDING
static func advance(phase: int, day_index: int) -> Dictionary:
	if phase == DayPhase.Phase.ENDING:
		return { "step": Step.RUN_END, "phase": DayPhase.Phase.ENDING, "day": day_index }
	if phase == LAST_PHASE:
		if day_index >= GameConfig.TOTAL_DAYS:
			return { "step": Step.RUN_END, "phase": DayPhase.Phase.ENDING, "day": day_index }
		return { "step": Step.DAY_END, "phase": DayPhase.Phase.DAY_BRIEFING, "day": day_index + 1 }
	# 注：招人阶段（Interview）内部由面试流程自己决定何时离开（M2 接）。
	# 这里给出的是一条默认推进路线，够 M0 的空壳流程跑通。
	return { "step": Step.PHASE, "phase": DayPhase.next(phase), "day": day_index }


## 该阶段是否由 interview.tscn 承载
static func is_interview_hosted(phase: int) -> bool:
	return INTERVIEW_HOSTED.has(phase)


## 阶段对应的子场景 key；空字符串表示该阶段暂时没有独立场景（由 day_loop 的占位 HUD 顶上）
static func scene_key_for(phase: int) -> StringName:
	if is_interview_hosted(phase):
		return &"interview"
	match phase:
		DayPhase.Phase.TEAM_BUILD:
			return &"team_builder"
		DayPhase.Phase.BATTLE_REPORT:
			return &"battle_report"
		DayPhase.Phase.ENDING:
			return &"ending"
	return &""


## 一天要走过的阶段序列（含首尾），供测试与进度显示用
static func phases_of_day() -> Array[int]:
	var phases: Array[int] = []
	phases.assign(DayPhase.ORDER)
	return phases
