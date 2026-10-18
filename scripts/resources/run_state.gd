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
##
## ⚠️ 是 **float** 不是 int：当日分 = true_power × 羁绊倍率（见 combat_resolver.gd），
##    乘数必然带小数。用 int 会在写入时静默截断，倍率的效果就丢了。
@export var scores: Array[float] = []

## 已录用名单（CandidateResource.id）
@export var roster: Array[StringName] = []

## 剧情 flag，例如 { "liar_hired": 3, "team_broke": 1 }
@export var flags: Dictionary = {}

## 玩家签过的字：signature_key -> Signature（§16）。
##
## key 来自对话那一行的 `popup_signature`（例如 "contract.day1"），和 popup_stamp 同一套路。
##
## ⚠️ **不要塞进 flags**：flags 是剧情计数器，而且 SaveService.from_dict() 里的
##    _normalize_number() 会把整数值的 float 掰回 int —— 归一化坐标里 0.0 / 1.0
##    这种值一旦被掰成 int，笔迹就被静默改坏一处。签名要有自己的字段。
@export var signatures: Dictionary = {}

## 已解锁手册条目 ID，例如 ["monster.ogre", "job.sword"]
@export var handbook_unlocked: Array[StringName] = []

## 当前阶段，取值对应 DayPhase，例如 "TEAM_BUILD"
@export var phase: StringName = &"DAY_BRIEFING"

## 注意：ARCHITECTURE.md §2 说 GameState 还持有「当前队伍」，但 §7 的存档样例
## 里没有对应字段。若读档要恢复当日队伍，这里需要补 current_team。
