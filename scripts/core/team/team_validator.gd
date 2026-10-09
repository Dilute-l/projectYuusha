class_name TeamValidator
extends RefCounted

## 组队校验（ARCHITECTURE.md §6.4 / §0）。**纯静态：不碰节点、不读 GameState、不改状态**。
##
## 「今天这一队能带几个人」「这位能不能进队」都是**规则**，所以落在这里；
## team_builder.gd 只负责在玩家点击时问一句，然后照着改 GameState。
##
## 队伍与名额都由调用方传进来 —— 本类不认识 GameState，所以不需要场景树就能直接测。

## can_add() 的 reason 取值
const REASON_OK := &"ok"
const REASON_INVALID_ID := &"invalid_id"      ## 传进来一个空 id
const REASON_ALREADY_IN := &"already_in"      ## 已经在队里了
const REASON_FULL := &"full"                  ## 名额已满


## 当天是否**真有**名额数据。slots <= 0 = data/days 里还没填，
## 这时既不限制玩家，也不该拿它去问「确定要走吗」。
static func has_quota(slots: int) -> bool:
	return slots > 0


## 名额是否已经用满。
##
## **`slots <= 0` 返回 false**（= 没有名额限制），不是 true —— 这一点很要紧：
## 数据没填时如果算「满」，玩家就一个人都加不进来了。
static func is_full(team_ids: Array[StringName], slots: int) -> bool:
	if not has_quota(slots):
		return false
	return team_ids.size() >= slots


## 还能再带几个人；没有名额数据时返回 -1（表示「不限」）。
static func remaining(team_ids: Array[StringName], slots: int) -> int:
	if not has_quota(slots):
		return -1
	return maxi(slots - team_ids.size(), 0)


## **超出**名额了没有。比 is_full() 严格一格：刚好满（size == slots）不算超。
##
## 为什么会超：面试阶段「录用」的人可能比今天的名额多 —— 组队界面一开始就把他们
## 全标上（§12 的「先带进来再调整」），于是开局就可能是超员状态。
## 超员不是「提醒一下」而是**硬拦**：多带的人没有名额，不能就这么出发。
static func is_over(team_ids: Array[StringName], slots: int) -> bool:
	if not has_quota(slots):
		return false
	return team_ids.size() > slots


## 能不能把 candidate_id 加进这一队。
## 返回 { "ok": bool, "reason": StringName }，reason 取上面那四个常量。
##
## 注意：本函数**只管「能不能加」**，不管「撤下来」—— 撤销永远允许，
## 否则满员之后玩家就没法换人了。
static func can_add(team_ids: Array[StringName], slots: int, candidate_id: StringName) -> Dictionary:
	if candidate_id == &"":
		return { "ok": false, "reason": REASON_INVALID_ID }
	if team_ids.has(candidate_id):
		return { "ok": false, "reason": REASON_ALREADY_IN }
	if is_full(team_ids, slots):
		return { "ok": false, "reason": REASON_FULL }
	return { "ok": true, "reason": REASON_OK }
