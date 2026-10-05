# 《警报!!勇者数量已超过路边野狗!!》项目架构设计

> 版本 v0.1（骨架规划） · 引擎 Godot 4.7 / GDScript
> 玩法定位：2D UI 驱动的「面试官模拟器」——文字 + 数值推演，无实时战斗操作。
> 本文档描述**目录结构、场景划分、数据模型与运行时数据流**，不含具体数值平衡与文案。

---

## 0. 技术基线

| 项目 | 决定 | 说明 |
| --- | --- | --- |
| 引擎 | Godot 4.7 | `project.godot` 已就绪（`canvas_items` 拉伸、Forward+） |
| 语言 | GDScript，数据用自定义 `Resource` | 策划在编辑器里改表，不改代码 |
| 物理 | 不参与玩法 | Jolt Physics 是脚手架默认值，保留即可，全程无碰撞体 |
| 数据载体 | `.tres` 资源文件为主，`user://` JSON 存档 | 静态数据与运行时状态严格分离 |
| 逻辑测试 | GdUnit4 / GUT | `scripts/core/` 是纯逻辑，可脱离场景树单测 |

核心纪律：**表现层不写规则，规则层不碰节点。**

- `scenes/` + `scripts/ui/`：只做显示与输入，拿到数据就画，发出信号就走。
- `scripts/core/`：纯函数式领域逻辑，输入数据、输出结果，可被测试直接调用。
- `scripts/resources/`：只定义数据结构，不含规则。
- `data/`：数据的实例，全部可在 Inspector 里编辑。

---

## 1. 目录总览

```
res://
├─ project.godot
├─ icon.svg
├─ ARCHITECTURE.md                  ← 本文档
│
├─ docs/                            ← 策划与文案，不参与运行
│   ├─ gdd.md                       ← 策划案原文
│   ├─ handbook_source.md           ← 手册文案母本，用于生成 data/handbook/
│   ├─ balance/                     ← 数值草表
│   └─ lore/                        ← 世界观、种族、魔王设定
│
├─ autoload/                        ← 全局单例（Project Settings ▸ Autoload）
│   ├─ event_bus.gd
│   ├─ game_state.gd
│   ├─ data_db.gd
│   ├─ rng_service.gd
│   ├─ save_service.gd
│   ├─ audio_service.gd
│   └─ scene_router.gd
│
├─ scripts/
│   ├─ resources/                   ← 数据模型（class_name，无逻辑）
│   │   ├─ candidate_resource.gd
│   │   ├─ claim_resource.gd
│   │   ├─ hidden_profile.gd
│   │   ├─ job_def.gd
│   │   ├─ skill_def.gd
│   │   ├─ race_def.gd
│   │   ├─ trait_def.gd
│   │   ├─ trait_interaction_table.gd
│   │   ├─ monster_def.gd
│   │   ├─ handbook_entry.gd
│   │   ├─ question_def.gd
│   │   ├─ day_config.gd
│   │   ├─ daily_event_def.gd
│   │   ├─ narrative_rule.gd
│   │   ├─ battle_report.gd
│   │   └─ run_state.gd
│   │
│   ├─ core/                        ← 领域逻辑（纯逻辑，禁止实例化节点）
│   │   ├─ generation/
│   │   │   ├─ candidate_generator.gd
│   │   │   ├─ claim_generator.gd
│   │   │   └─ name_pool.gd
│   │   ├─ interview/
│   │   │   ├─ interview_session.gd
│   │   │   ├─ answer_builder.gd
│   │   │   ├─ lie_detector.gd
│   │   │   └─ pressure_tracker.gd
│   │   ├─ team/
│   │   │   ├─ team_validator.gd
│   │   │   └─ synergy_calculator.gd
│   │   ├─ battle/
│   │   │   ├─ combat_resolver.gd
│   │   │   ├─ narrative_engine.gd
│   │   │   └─ casualty_rules.gd
│   │   ├─ scoring/
│   │   │   ├─ day_scorer.gd
│   │   │   └─ ending_resolver.gd
│   │   └─ flow/
│   │       ├─ day_director.gd
│   │       └─ unlock_schedule.gd
│   │
│   ├─ ui/                          ← 挂在 .tscn 上的表现层脚本
│   └─ util/
│       ├─ weighted_picker.gd
│       ├─ text_formatter.gd
│       └─ enum_utils.gd
│
├─ data/                            ← 静态数据实例（.tres）
│   ├─ jobs/          sword.tres / mage.tres / priest.tres …
│   ├─ skills/        按职业分组：剑术、弓箭、火球、治疗、驱魔 …
│   ├─ races/         人类 / 精灵 / 矮人 / 兽人 …
│   ├─ traits/        性格与癖好；interactions.tres 为相性矩阵
│   ├─ monsters/      魔物图鉴数据（特点标签、弱点、克制倍率）
│   ├─ handbook/      手册条目（玩家判断谎言的知识依据）
│   ├─ questions/     追问问题库，按主题分类
│   ├─ narrative/     战报叙事规则与文案模板
│   ├─ days/          day_01.tres … day_10.tres
│   ├─ events/        每日特殊事件池
│   ├─ names/         姓名与种族命名表
│   └─ endings/       结局定义
│
├─ scenes/
│   ├─ boot/          boot.tscn
│   ├─ menu/          main_menu.tscn / settings.tscn
│   ├─ day/           day_loop.tscn（每日流程容器）/ day_briefing.tscn
│   ├─ screening/     screening_list.tscn / candidate_card.tscn / resume_panel.tscn
│   ├─ interview/     interview_panel.tscn / question_picker.tscn / answer_log.tscn
│   ├─ team/          team_builder.tscn / team_slot.tscn
│   ├─ report/        battle_report.tscn / report_entry.tscn / day_result.tscn
│   ├─ handbook/      handbook_overlay.tscn / handbook_index.tscn
│   ├─ ending/        ending.tscn
│   └─ common/        modal_dialog.tscn / loading_veil.tscn / toast.tscn
│
├─ ui/
│   ├─ components/    stat_bar.tscn / tag_chip.tscn / trait_tooltip.tscn / portrait_frame.tscn
│   ├─ themes/        default_theme.tres + 字体资源
│   └─ styles/        StyleBox 资源
│
├─ assets/
│   ├─ art/           UI 边框、纸张背景、图标
│   ├─ portraits/     立绘（按 race/job 分组，先放占位）
│   ├─ fonts/         中文主字体 + 数字字体
│   ├─ audio/bgm/ · audio/sfx/
│   └─ shaders/       羊皮纸、印章等 UI 效果
│
└─ tests/
    ├─ unit/          test_candidate_generator.gd / test_scorer.gd …
    └─ fixtures/      固定种子的期望输出
```

---

## 2. 全局单例（Autoload）

| 单例 | 职责 | 依赖 |
| --- | --- | --- |
| `EventBus` | 全局信号中继。UI 与逻辑之间只通过信号通信，不互相持有引用 | 无 |
| `GameState` | 一次「讨伐季」的全部运行时状态：当前天数、已录用名单、每日分数、剧情 flag、手册解锁项、当前队伍 | EventBus |
| `DataDB` | 启动时扫描 `res://data/`，把所有 `.tres` 收进字典，提供 `get_job(id)` / `get_skill(id)` / `get_monster(id)` 等查询 | 无 |
| `RngService` | 唯一随机源，可设种子；每日派生种子 `day_seed = run_seed ^ day_index`，保证同种子可复现整局 | 无 |
| `SaveService` | 存档 / 读档 / 自动存档，只序列化 `RunState`，不写静态数据 | GameState |
| `AudioService` | BGM 与音效播放、淡入淡出 | 无 |
| `SceneRouter` | 场景切换、返回栈、过场遮罩；每日流程各阶段的跳转都走它 | EventBus |

> 关键点：`GameState` 只存**状态**，所有**规则**放在 `scripts/core/` 里以静态函数实现。
> 这样「同一种子 → 同一份候选人 → 同一个战报」可以被测试完整复现。

---

## 3. 数据模型（Resource 定义）

### 3.1 候选人

```gdscript
class_name CandidateResource extends Resource
@export var id: StringName
@export var display_name: String
@export var age: int
@export var gender: StringName
@export var race: RaceDef
@export var job: JobDef
@export var skill_ids: Array[StringName]        # 可用技能
@export var skill_levels: Dictionary            # skill_id -> 0..100（自称值）
@export var traits: Array[TraitDef]             # 性格 / 特殊癖好（对玩家可见部分）
@export var claims: Array[ClaimResource]        # 简历与口述经历
@export var portrait: Texture2D
@export var hidden: HiddenProfile               # 隐藏属性，UI 永不直接显示
```

`HiddenProfile` 是设计的核心，玩家永远看不到，只通过面试与战报间接感知：

| 字段 | 含义 | 影响 |
| --- | --- | --- |
| `honesty` | 诚实度 −1..1 | 决定回答时的说谎概率与破绽多少 |
| `true_skills` | 真实技能值 | 与自称值的差额 = 谎言严重程度 |
| `courage` / `loyalty` / `teamwork` / `ego` / `greed` | 性格内核 | 战报事件触发、相性计算 |
| `patience` | 追问容忍度 | 追问过度会翻脸、拒答，甚至当场退赛 |
| `luck` | 运气修正 | 极端战报的开关 |

### 3.2 履历主张（说谎机制的载体）

```gdscript
class_name ClaimResource extends Resource
enum Topic { JOB, SKILL, EXPERIENCE, PERSONALITY, QUIRK }

@export var topic: Topic
@export var statement: String            # "我曾单独讨伐过三只食人魔。"
@export var is_true: bool
@export var exaggeration: float          # 0 真实 .. 1 完全造假（中间值为夸大）
@export var verification: StringName     # 验证路径：手册条目 / 技能细节 / 数字矛盾
@export var related_skill_ids: Array[StringName]
@export var rebuttals: Array[String]     # 被追问时的回应，按追问强度分级
```

设计的妙处：**谎言不是一个 bool，而是一条可被戳破的链。** 同一份 claim 在不同追问强度下的回答不同，玩家用手册里的知识去对齐，才能判断真假。

### 3.3 其它数据定义

| 类 | 关键字段 | 用途 |
| --- | --- | --- |
| `JobDef` | `id` / `skill_tree` / `stat_profile` / `counter_tags` | 剑士、法师、牧师 |
| `SkillDef` | `id` / `damage_type`（近战/远程/魔法）/ `range` / `tags` | 属性适配与克制判定 |
| `RaceDef` | `id` / `base_modifiers` / `naming_table` | 种族差异与姓名生成 |
| `TraitDef` | `id` / `category`（性格 or 癖好）/ `synergy_tags` | 相性计算 |
| `TraitInteractionTable` | `pairs: Array[{a, b, delta, note}]` | 相性 / 克制矩阵，单文件集中维护 |
| `MonsterDef` | `id` / `tags`（群居、重甲、再生、畏光）/ `weaknesses` / `counters` / `threat` | 特殊事件与战报 |
| `HandbookEntry` | `id` / `category` / `body`（BBCode）/ `unlock_condition` | 可随时翻阅的手册 |
| `QuestionDef` | `id` / `topic` / `min_day` / `pressure` / `requires_skill` | 追问问题库 |
| `DayConfig` | `day_index` / `candidate_count` / `slots` / `questions_per_candidate` / `unlocked_topics` / `event_pool` / `tutorial_step` | 每一天的规则与教程进度 |
| `DailyEventDef` | `id` / `monster` / `announce_text` / `bonus_rules` | 记者报道的特殊情况 |
| `NarrativeRule` | `when`（条件）/ `template`（占位符文案）/ `weight` / `priority` | 战报叙事生成 |
| `RunState` | 见第 7 节 | 存档根结构 |

---

## 4. 场景划分与职责

| 场景 | 职责 | 主要信号 |
| --- | --- | --- |
| `boot.tscn` | 加载 `DataDB`，检查存档，跳到主菜单 | — |
| `main_menu.tscn` | 新游戏 / 继续 / 设置 / 图鉴回顾 | `new_run_requested` |
| `day_loop.tscn` | **每日流程容器**，按 `DayPhase` 状态机切换子场景 | `phase_changed` |
| `day_briefing.tscn` | 国王下旨：今日名额、新解锁的面试内容、教程提示 | `briefing_confirmed` |
| `screening_list.tscn` | 当日候选人列表，显示"已审 / 未审 / 剩余名额" | `candidate_opened` |
| `candidate_card.tscn` | 单张简历卡（复用控件） | `selected` |
| `resume_panel.tscn` | 完整简历：基础信息、自称技能、经历、癖好 | — |
| `interview_panel.tscn` | 面试主界面：问答记录 + 追问入口 + 判定按钮 | `verdict_issued` |
| `question_picker.tscn` | 从当日可用问题库中选问题（受主题解锁与次数限制） | `question_chosen` |
| `handbook_overlay.tscn` | 随时可呼出的手册浮层，按关键词检索 | `entry_bookmarked` |
| `team_builder.tscn` | 从通过者中挑满名额组队 | `team_submitted` |
| `battle_report.tscn` | 战报演出：逐条事件播报 + 结局等级 | `report_finished` |
| `day_result.tscn` | 当日得分明细、累计分、手册新解锁 | `day_closed` |
| `ending.tscn` | 十天后按总分与 flag 判定结局 | `restart_requested` |

每日流程由 `day_loop.tscn` 持有状态机驱动：

```
DayBriefing → SpecialEvent → Screening ⇄ Interview → TeamBuild → BattleReport → DayResult
                                                                    ↑              │
                                                                    └── 天数 +1 ───┘
                                                        第 10 天结束 → Ending
```

---

## 5. 信号约定（EventBus）

命名统一用「名词 + 过去式」，避免 UI 直接调用逻辑：

```gdscript
signal day_started(day_index: int)
signal day_phase_changed(phase: int)
signal candidate_opened(candidate_id: StringName)
signal question_asked(candidate_id: StringName, question_id: StringName)
signal verdict_issued(candidate_id: StringName, passed: bool)
signal team_submitted(member_ids: Array[StringName])
signal battle_report_ready(report: BattleReport)
signal day_scored(result: Dictionary)          # {day, gained, total, breakdown}
signal handbook_entry_unlocked(entry_id: StringName)
signal run_finished(ending_id: StringName)
```

---

## 6. 核心机制的实现落点

### 6.1 候选人生成
`candidate_generator.gd` 依据 `DayConfig` + `RngService` 一次性生成当日全部候选人，写入 `GameState`。
同一天刷新不会重掷（种子固定），读档后也完全一致。

### 6.2 面试与追问
`interview_session.gd` 管理单个候选人的问答循环：

1. 展示简历（`claims` 中的自称内容）；
2. 玩家从 `question_picker` 选题 → `answer_builder.gd` 依据 `honesty` + `exaggeration` + `追问强度` + RNG 生成回答；
3. `lie_detector.gd` 只负责**给出可被玩家观察的线索**（语气、细节矛盾、数据不符），不替玩家下结论；
4. `pressure_tracker.gd` 累积追问强度，触顶则候选人拒答 / 翻脸 / 提前离场。

### 6.3 手册（玩家能力锚点）
`handbook_overlay` 是全局浮层，任何阶段都能呼出。`data/handbook/` 的条目承担两件事：
给出魔物弱点、同时给出**常识基线**（例如"初级剑士不可能单人讨伐食人魔"），让撒谎能被推理而不是靠猜。

### 6.4 相性与组队
`synergy_calculator.gd` 读取 `TraitInteractionTable`，对队伍做两两配对：

- 配合（例：正义感 × 骑士精神）→ 战报触发"配合默契"正向事件；
- 冲突（例：自恋 × 独狼）→ 触发争吵负向事件，严重时影响当日成败。

### 6.5 战报生成
`combat_resolver.gd` 计算基础结果，`narrative_engine.gd` 用 `NarrativeRule` 把结果翻译成人话：

```gdscript
# data/narrative/lie_exposed.tres（示意）
when     = "member.honesty < -0.3 and member.true_power < member.claimed_power * 0.5"
template = "{actor} 在简历上说谎了，是个货真价实的水货，他把大家携带的装备全都搞坏了。"
weight   = 1.0
priority = 10
```

规则按 `priority` 排序、`weight` 加权抽取，避免同一天重复同一模板。

### 6.6 评分与结局

```
当日分 = 队伍真实战力
       + 相性加成（synergy_calculator）
       − 谎言处罚（录用说谎者，越假扣越多）
       + 特殊事件加成（是否针对今日魔物选人）
       + 运气修正
累计分 = Σ 当日分
```

`ending_resolver.gd` 依据累计分 + flag（录用假货总数、队伍解散次数、是否有幸存者…）判定结局。
**设计的爽点**：说谎者不会当场暴露，而是在十天后以"王国惨败"的形式惩罚玩家，玩家会自发形成"仔细查证"的习惯。

---

## 7. 存档结构

只存运行时状态，静态数据不需要存：

```json
{
  "version": 1,
  "run_seed": 20261005,
  "day": 4,
  "scores": [72, 68, 85],
  "roster": ["c_0012", "c_0031"],
  "flags": { "liar_hired": 3, "team_broke": 1 },
  "handbook_unlocked": ["monster.ogre", "skill.sword_basic"],
  "phase": "TEAM_BUILD"
}
```

路径：`user://saves/slot_{n}.json`，另存一份 `user://saves/auto.json` 用于每日开始自动存档。

---

## 8. 命名与编码规范

- 场景与脚本：`snake_case.tscn` / `snake_case.gd`，同基名成对出现。
- 自定义 Resource 类：`class_name` 用 `PascalCase`，文件名用 `snake_case`。
- ID 统一 `StringName`，命名空间化：`job.sword`、`trait.ego`、`monster.ogre`、`skill.fireball`。
- 常量 `UPPER_SNAKE_CASE`；全局配置放 `GameConfig`（`TOTAL_DAYS = 10` 等）。
- 目录内不出现空场景；每个 `.tscn` 只做一件事。
- `.godot/` 已在 `.gitignore` 中；`*.import` 由 Godot 生成，若版本间产生噪音，可在 `.gitignore` 追加 `*.import`。

---

## 9. 实现里程碑

| 阶段 | 目标 | 验收标准 |
| --- | --- | --- |
| M0 骨架 | autoload 齐备、`SceneRouter` 可跑通 主菜单 → 每日循环（空壳） | 能连续走完 10 天空流程 |
| M1 候选人 | 数据模型 + 生成器 + 简历卡 UI | 固定种子能复现同一批候选人 |
| M2 面试 | 追问、回答、手册、判定 | 能靠手册推理戳破一个谎 |
| M3 组队与战报 | 相性计算、战斗结算、叙事引擎 | 出现四种典型战报文案 |
| M4 评分结局 | 每日评分、累计分、结局判定 | 好/坏两条结局都能打出来 |
| M5 内容 | 填满 10 天数据、手册、文案、立绘占位 | 一局可玩通 |
| M6 打磨 | 演出、音频、存档、图鉴回顾 | 存档读档一致，可复现整局 |

---

## 10. 预留扩展点

- **新职业 / 新种族**：加 `.tres` 即可，无需改逻辑。
- **多周目**：`GameState` 增加 flag 继承层，结局判定读取上一周目记录。
- **候选人导入**：`ClaimResource` 的表结构可直接由 CSV 导出，便于批量产出上百份简历。
- **本地化**：所有文案集中在 `data/`，`text_formatter.gd` 统一做占位符替换，便于日后接翻译。
- **Mod 支持**：`DataDB` 支持覆盖目录，玩家自制数据包可直接替换同名 ID。

