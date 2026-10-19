class_name OpeningFlow
extends RefCounted

## 「开场剧情」播不播的规则（规则放 core，场景只照着做）。
##
## 需求：**游戏第一次启动**时先播一遍 `opening`，之后每次启动直接进主菜单。
## 主菜单的火漆按钮（SealButton）可以再看一次 —— 那条路**不**看这个 flag
## （玩家主动要求重播，不该被"已经看过"拦住）。
##
## ⚠️ flag 记在 GameState.progress_flags（跨局 / 跨启动的账本，user://saves/progress.json），
##    不是 run_state.flags：它说的是「这台机器上的玩家看过开场没有」，
##    开新局、读别的档、甚至通关都不该把它抹掉。
##    和真结局的解锁条件共用同一本账本（见 ending_unlock.gd）。

## 「开场已经播过」的 flag
const FLAG_OPENING_SEEN := &"opening_seen"


## 这次启动要不要先播开场（没看过 → 要）
static func should_play_on_launch() -> bool:
	return not has_seen()


## 看过没有
static func has_seen() -> bool:
	return GameState.get_progress_flag(FLAG_OPENING_SEEN)


## 标记「看过了」。返回这次是否真的变了（已经记过 → false）。
##
## ⚠️ 调用方（boot.gd）必须在**切到开场场景之前**调它：
##    开场播完会回主菜单，万一玩家中途退出，下次启动不该再被拦一遍 ——
##    "宁可少播一次，也不要每次启动都播一遍"。
static func mark_seen() -> bool:
	return GameState.set_progress_flag(FLAG_OPENING_SEEN)
