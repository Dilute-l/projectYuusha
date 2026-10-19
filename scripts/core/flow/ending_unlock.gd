class_name EndingUnlock
extends RefCounted

## 真结局的解锁条件（两条**都**要达成）：
##
##   1. 某一天把带 `trait.true_ending` 的候选人**编进了队伍**（`FLAG_MEMBER_TEAMED`）；
##   2. 正常走完十天、好结局收尾（`FLAG_NORMAL_CLEARED`）。
##
## 两条都达成 → 主菜单的标题按钮（Title）解锁：可按，按下去进真结局场景（Ending_True）。
## 只是第一条达成时主菜单**什么都不变**；第二条达成后标题文案会换成
## 「败犬面试官太多了！」（见 main_menu.gd），这是给玩家的暗示。
##
## 规则放这里、不放进 UI 的理由和其它 core 一样：按钮和文案会改，判定不该跟着改。
##
## ⚠️ 这两个 flag 记在 **GameState.progress_flags**（跨局账本，user://saves/progress.json），
##    而**不是** run_state.flags。「解锁了什么」是玩家层面的事，开新局 / 读别的档都不该抹掉；
##    run 的 flag 说的是「这一局发生了什么」，两件事别混在一张表里。

## 真结局候选人的特质 id（data/traits/true_ending.tres）
const TRUE_ENDING_TRAIT := &"trait.true_ending"

## 第一个条件：真结局候选人进过队
const FLAG_MEMBER_TEAMED := &"true_ending_member_teamed"

## 第二个条件：正常走完十天
const FLAG_NORMAL_CLEARED := &"true_ending_normal_cleared"


## 这位候选人带不带真结局特质
static func is_true_ending_candidate(candidate: CandidateResource) -> bool:
	if candidate == null or candidate.traits == null:
		return false
	# ⚠️ 循环变量不能叫 trait：Godot 4.7 把 trait 当保留字，会报
	#    "Expected loop variable name after for"。
	for trait_def in candidate.traits:
		if trait_def != null and trait_def.id == TRUE_ENDING_TRAIT:
			return true
	return false


## 结算「队伍换成了 member_ids」：里面出现真结局候选人 → 点亮第一个 flag。
## 返回这次是否**真的点亮**（已经点过 → false，调用方据此决定要不要播提示）。
##
## 看的是「当前整支队伍」而不是「新加的那一位」：调用方（GameState.set_current_team）
## 只在队伍真的变了时进来，不管谁把这位放进来的都能覆盖到。
## 人后来被移出队伍也**不撤销** —— 条件是「被编入过」，不是「结算时还在队里」。
static func note_team(member_ids: Array[StringName]) -> bool:
	for member_id in member_ids:
		if is_true_ending_candidate(DataDB.get_candidate(member_id)):
			return GameState.set_progress_flag(FLAG_MEMBER_TEAMED)
	return false


## 结算「正常走完十天」。返回这次是否真的点亮。
static func note_normal_ending() -> bool:
	return GameState.set_progress_flag(FLAG_NORMAL_CLEARED)


## 第一个条件达成没有
static func has_member_teamed() -> bool:
	return GameState.get_progress_flag(FLAG_MEMBER_TEAMED)


## 第二个条件达成没有（也是「标题文案要不要换」的开关）
static func is_normal_cleared() -> bool:
	return GameState.get_progress_flag(FLAG_NORMAL_CLEARED)


## 两个条件都达成 → 真结局入口解锁
static func is_unlocked() -> bool:
	return has_member_teamed() and is_normal_cleared()
