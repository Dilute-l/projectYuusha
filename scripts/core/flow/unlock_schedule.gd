class_name UnlockSchedule
extends RefCounted

## 手册条目的解锁判定（ARCHITECTURE.md §3.x / §6）。**纯静态：不碰节点、不读 GameState**。
##
## `HandbookEntry.unlock_condition` 是一句**表达式**，可用的变量见 INPUT_NAMES：
##
##     "day >= 7"            第 7 天起出现
##     "hired_count >= 2"    录用满两人后出现
##     ""（空字符串）          一开始就能看
##
## 判定结果只回答「该不该出现」，**不往存档里写** —— 它是每次现算的，
## 条件本身就是可重放的（§7：存档只放运行时状态）。

## 表达式里能用的变量。加/改这里 = 改数据作者能用的词汇。
const INPUT_NAMES := ["day", "total_score", "hired_count"]


## 条件本身满足了吗。空字符串 = 无条件 = 满足。
##
## 条件写错（语法错、用了没声明的变量）时**报错并返回 false** ——
## 既不让一条写错的数据悄悄变成「永远可见」，也不让它悄悄变成「永远不可见」。
static func is_satisfied(condition: String, day: int, total_score: int, hired_count: int) -> bool:
	var expr := _compile(condition)
	if expr == null:
		return condition.strip_edges().is_empty()
	return _run(expr, day, total_score, hired_count)


## 这条条件**最早**在哪一天成立。用来给「一次补登很多条」排出先后
## （见 GameState.record_handbook_unlocks）。
##
## 只在 [1, current_day] 里扫。条件若根本不看 day（例如 "total_score>=100"），
## 扫描会停在 day 1 —— 我们无从知道它当时究竟成不成立，就按「最早」处理。
## 返回 current_day + 1 表示「到今天都还没成立」。
static func first_satisfied_day(
	condition: String, current_day: int, total_score: int, hired_count: int
) -> int:
	var expr := _compile(condition)
	if expr == null:
		# 空条件 = 一开始就有，所以排最前；写错的排最后（它本来也不会被登记）
		return 1 if condition.strip_edges().is_empty() else current_day + 1
	for day in range(1, current_day + 1):
		if _run(expr, day, total_score, hired_count):
			return day
	return current_day + 1


## 这一条现在该不该出现。
##
## 两个来源取**或**：
##   · 条件满足   —— 数据自带的排期（unlock_condition）
##   · 显式解锁过 —— GameState.handbook_unlocked，剧情提前塞给玩家的那种
##
## 显式解锁能越过条件，这是**有意**的：剧情把「兽人」提前告诉玩家时，
## 不该被 `day >= 7` 拦回去。
##
## 注：手册组页走的是「账本」（GameState.record_handbook_unlocks），不走这里 ——
## 账本一旦登记就不反悔。本函数留给需要**不登记**的场合用（例如「有新条目」角标）。
static func is_visible(
	condition: String,
	explicitly_unlocked: bool,
	day: int,
	total_score: int,
	hired_count: int
) -> bool:
	if explicitly_unlocked:
		return true
	return is_satisfied(condition, day, total_score, hired_count)


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------


## 编译条件。空条件返回 null（调用方按「无条件 = 满足」处理）；
## 写错的也返回 null —— 但会报错，不静默。
static func _compile(condition: String) -> Expression:
	var text := condition.strip_edges()
	if text.is_empty():
		return null
	var expr := Expression.new()
	if expr.parse(text, PackedStringArray(INPUT_NAMES)) != OK:
		push_error("[UnlockSchedule] 解锁条件写错了：「%s」：%s" % [condition, expr.get_error_text()])
		return null
	return expr


static func _run(expr: Expression, day: int, total_score: int, hired_count: int) -> bool:
	var result: Variant = expr.execute([day, total_score, hired_count])
	if expr.has_execute_failed():
		push_error("[UnlockSchedule] 解锁条件求值失败：%s" % expr.get_error_text())
		return false
	return bool(result)
