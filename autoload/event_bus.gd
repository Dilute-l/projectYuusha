extends Node

## EventBus —— 全局信号中继（ARCHITECTURE.md §2 / §5）。
##
## UI 与逻辑之间只通过信号通信，不互相持有引用。
## 命名统一「名词 + 过去式」，**只放信号与转发，不写任何状态与规则**。
##
## 这里全是「只声明、由别处 emit」的信号，GDScript 会为此报 unused_signal 警告，
## 对整个文件统一静音——事件总线本来就该是这样。

@warning_ignore_start("unused_signal")

# ---------------------------------------------------------------------------
# 每日流程与玩法（§5 约定）
# ---------------------------------------------------------------------------

## 新的一天开始
signal day_started(day_index: int)

## 每日流程阶段切换，取值对应 DayPhase.Phase
signal day_phase_changed(phase: int)

## 打开某位候选人的简历
signal candidate_opened(candidate_id: StringName)

## 玩家追问了简历上的某一条目（entry_index 为该候选人 resume 的下标）
signal resume_entry_asked(candidate_id: StringName, entry_index: int)

## 对某位候选人给出录用判定
signal verdict_issued(candidate_id: StringName, passed: bool)

## 当日队伍提交（挑满名额）
signal team_submitted(member_ids: Array[StringName])

## 战报演出数据就绪
signal battle_report_ready(report: BattleReport)

## 当日结算完成，result = {day, gained, total, breakdown}
signal day_scored(result: Dictionary)

## 手册条目解锁
signal handbook_entry_unlocked(entry_id: StringName)

## 一局结束
signal run_finished(ending_id: StringName)

# ---------------------------------------------------------------------------
# M0 追加：局与存档生命周期（§5 未列，但 M0 的 boot / 菜单 / 存档需要）
# ---------------------------------------------------------------------------

## 新开一局，广播本局种子
signal run_started(run_seed: int)

## 读档接管了一局
signal run_loaded(run_seed: int)

## 某位候选人被录用进名单
signal candidate_hired(candidate_id: StringName)

## 写档结果（slot = -1 表示自动存档）
signal save_written(slot: int, ok: bool)

## 读档结果（slot = -1 表示自动存档）
signal save_loaded(slot: int, ok: bool)

# ---------------------------------------------------------------------------
# M0 追加：场景路由（SceneRouter 广播；UI 不持有 SceneRouter 引用也能响应）
# ---------------------------------------------------------------------------

## 开始切换场景（遮罩淡出前）
signal scene_change_started(scene_key: StringName, scene_path: String)

## 场景切换完成（新场景已进入树）
signal scene_changed(scene_key: StringName, scene_path: String)

# ---------------------------------------------------------------------------
# M0 追加：音频（AudioService 广播，供 UI 同步音量滑块等显示）
# ---------------------------------------------------------------------------

## 音量变化：bus 名 -> 线性值 0..1
signal volume_changed(bus_name: StringName, linear_volume: float)

@warning_ignore_restore("unused_signal")
