class_name RunState
extends Resource

## 一局「讨伐季」的运行时状态，也是存档根结构（ARCHITECTURE.md §7）。
## SaveService 只序列化本类，绝不写静态数据。
## 落盘位置：user://saves/slot_{n}.json，另有 user://saves/auto.json

## 存档格式版本
@export var version: int = 1

## 本局种子。每日派生种子 day_seed = run_seed ^ day_index，保证同种子可复现整局
@export var run_seed: int = 0

## 当前天数，1..GameConfig.TOTAL_DAYS
@export var day: int = 1

## 每日得分，scores[0] 为第 1 天
@export var scores: Array[int] = []

## 已录用名单（CandidateResource.id）
@export var roster: Array[StringName] = []

## 剧情 flag，例如 { "liar_hired": 3, "team_broke": 1 }
@export var flags: Dictionary = {}

## 已解锁手册条目 ID，例如 ["monster.ogre", "skill.sword_basic"]
@export var handbook_unlocked: Array[StringName] = []

## 当前阶段，取值对应 DayPhase，例如 "TEAM_BUILD"
@export var phase: StringName = &"DAY_BRIEFING"

## 注意：ARCHITECTURE.md §2 说 GameState 还持有「当前队伍」，但 §7 的存档样例
## 里没有对应字段。若读档要恢复当日队伍，这里需要补 current_team。
