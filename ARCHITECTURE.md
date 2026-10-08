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
│   │   ├─ resume_entry.gd
│   │   ├─ job_def.gd
│   │   ├─ race_def.gd
│   │   ├─ trait_def.gd
│   │   ├─ trait_interaction_table.gd
│   │   ├─ monster_def.gd
│   │   ├─ handbook_entry.gd
│   │   ├─ day_config.gd
│   │   ├─ daily_event_def.gd
│   │   ├─ narrative_rule.gd
│   │   ├─ battle_report.gd
│   │   └─ run_state.gd
│   │
│   ├─ core/                        ← 领域逻辑（纯逻辑，禁止实例化节点）
│   │   ├─ interview/
│   │   │   └─ interview_session.gd
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
│   ├─ races/         人类 / 精灵 / 矮人 / 兽人 …
│   ├─ traits/        性格与癖好；interactions.tres 为相性矩阵
│   ├─ candidates/    写死的候选人（每天固定名单，被 days/ 引用）
│   ├─ monsters/      魔物图鉴数据（特点标签、弱点、克制倍率）
│   ├─ handbook/      手册条目（玩家判断简历真伪的常识依据）
│   ├─ narrative/     战报叙事规则与文案模板
│   ├─ days/          day_01.tres … day_10.tres（含当日固定候选人名单）
│   ├─ events/        每日特殊事件池
│   └─ endings/       结局定义
│
├─ scenes/
│   ├─ boot/                   boot.tscn
│   ├─ menu/                   main_menu.tscn（收容新游戏 / 继续 / 设置 / 图鉴回顾等子场景）
│   ├─ day/                    day_loop.tscn（每日流程容器）
│   │   ├─ interview/          interview.tscn（面试流程容器）
│   │   │   ├─ interview_ui.tscn       面试系统 UI：暂停、设置、候选人列表、今日事件
│   │   │   ├─ interviewee.tscn        面试者立绘、表情差分、对话框
│   │   │   ├─ resume/                  resume.tscn（候选人完整简历）
│   │   │   │   └─ resume_token.tscn    单条简历词条（复用控件）
│   │   │   └─ handbook_overlay.tscn   随时可呼出的手册浮层，按关键词检索
│   │   ├─ team_builder/       team_builder.tscn（组队容器）
│   │   │   ├─ team_builder_ui.tscn     组队 UI：队伍人数、空位、羁绊、当日事件
│   │   │   └─ candidate.tscn          当日候选人的简历
│   │   └─ battle_report.tscn          战报演出容器（车夫对话、逐条事件、分数）
│   ├─ ending/                 ending.tscn（收容结局相关子场景）
│   └─ common/                 dialogue.tscn / interview_background.tscn / haohan.tscn
│                                 （可在多场景实例化复用的通用场景）
│
├─ ui/
│   ├─ components/    stat_bar.tscn / tag_chip.tscn / trait_tooltip.tscn / portrait_frame.tscn
│   ├─ themes/        default_theme.tres + 字体资源
│   └─ styles/        StyleBox 资源
│
├─ assets/
│   ├─ art/           UI 边框、纸张背景、图标
│   ├─ portraits/     立绘（按 job 分组，先放占位）
│   ├─ fonts/         中文主字体 + 数字字体
│   ├─ audio/bgm/ · audio/sfx/
│   └─ shaders/       羊皮纸、印章等 UI 效果
│
└─ tests/
	├─ unit/          test_candidate.gd / test_scorer.gd …
	└─ fixtures/      写死名单的期望输出
```

---

## 2. 全局单例（Autoload）

| 单例 | 职责 | 依赖 |
| --- | --- | --- |
| `EventBus` | 全局信号中继。UI 与逻辑之间只通过信号通信，不互相持有引用 | 无 |
| `GameState` | 一次「讨伐季」的全部运行时状态：当前天数、已录用名单、每日分数、剧情 flag、手册解锁项、当前队伍 | EventBus |
| `DataDB` | 启动时扫描 `res://data/`，把所有 `.tres` 收进字典，提供 `get_job(id)` / `get_candidate(id)` / `get_trait(id)` / `get_monster(id)` 等查询 | 无 |
| `RngService` | 唯一随机源，可设种子；每日派生种子 `day_seed = run_seed ^ day_index`，保证同种子可复现整局 | 无 |
| `SaveService` | 存档 / 读档 / 自动存档，只序列化 `RunState`，不写静态数据 | GameState |
| `AudioService` | BGM 与音效播放、淡入淡出 | 无 |
| `SceneRouter` | 场景切换、返回栈、过场遮罩；每日流程各阶段的跳转都走它 | EventBus |

> 关键点：`GameState` 只存**状态**，所有**规则**放在 `scripts/core/` 里以静态函数实现。
> 这样「同一种子 → 同一份候选人 → 同一个战报」可以被测试完整复现。

---

## 3. 数据模型（Resource 定义）

> **与旧版的关键差异**：每天出场的候选人不再由生成器随机拼装，而是**全部直接写死**——
> 策划在 `data/` 里逐条填好，`DayConfig.candidates` 指向当天固定名单；`RngService`
> 不再参与造人，只服务战报等无关随机。

### 3.1 候选人

```gdscript
class_name CandidateResource extends Resource
@export var id: StringName
@export var display_name: String
@export var strength: int = 0                   # 力量
@export var intelligence: int = 0               # 智力
@export var wisdom: int = 0                 # 感知
@export var level: int = 1                      # 等级
@export var job: JobDef                         # 职业
@export var traits: Array[TraitDef] = []        # 特质（list，可含多项，也可为空）
@export var resume: Array[ResumeEntry] = []     # 简历（见 §3.2）
@export_multiline var resume_header: String     # 简历抬头：整段字，见 §10.6
@export var portrait: Texture2D                 # 整张立绘（可选；当前用拼装立绘，见下）

# 拼装立绘的「配方」（见 §10.7）。取值直接对应 assets/art/portrait/ 的文件名。
@export var portrait_race: StringName = &"hu"   # hu / el / st → {race}_body_phd.png
@export var portrait_eye: int = 1               # 1..3，仅 hu / el 使用
@export var portrait_hair: int = 1              # 1..3，仅 hu / el 使用
@export var portrait_mouth: int = 1             # 1..3，仅 hu / el 使用
@export var portrait_hat: int = 1               # 1..3，仅 st 使用
```

> 字段说明：

| 字段 | 含义 | 备注 |
| --- | --- | --- |
| `strength` / `intelligence` / `wisdom` | 力量 / 智力 / 感知 | 玩家可见；对照简历描述的判断依据 |
| `level` | 等级 | 与职业共同构成「常理上限」，是手册常识的锚点 |
| `job` | 职业 | `JobDef`，见 §3.3 |
| `traits` | 特质 | `Array[TraitDef]`，可含多项；相性计算输入（§6.4） |
| `resume` | 简历 | `Array[ResumeEntry]`，每条 = 一句描述 + 追问问题 + 追问回答 |
| `resume_header` | 简历抬头 | **一整段字**，原样铺在纸面上半；运行时不做任何拼接（§10.6） |
| `portrait_*` | 拼装立绘配方 | 种族 + 各部件差分编号；面试者的长相也是数据，不是代码里摇的（§10.7） |

> 真假不再由隐藏字段承载：玩家看到的 `strength / intelligence / wisdom / level / job / traits`
> 就是全部数值，判断依据来自「属性与简历描述的落差」＋「手册常识」，见 §6.2 / §6.3。

### 3.2 简历条目（ResumeEntry）

```gdscript
class_name ResumeEntry extends Resource

## 简历上写的那句话，例如「我曾单独讨伐过三只食人魔。」
@export_multiline var description: String = ""


## 针对本条的追问，例如「你是怎么打败它们的？」
@export_multiline var question: String = ""

## 针对本条追问之后得到的回答，例如「那次是趁它们分食时逐个击破的。」
@export_multiline var answer: String = ""
```

简历由若干条目组成，**每条只有三样东西**：简历上写的那句话、追问问题、追问后得到的回答。
面试交互见 §6.2：玩家点击某一条 → 先给出该条的 `question`，再展开对应的 `answer`；是否可信，由玩家结合
`strength / intelligence / wisdom / level / job / traits` 与手册常识自行判断。



### 3.3 其它数据定义

| 类 | 关键字段 | 用途 |
| --- | --- | --- |
| `JobDef` | `id` / `display_name` / `description` | 职业身份，简历展示 |
| `TraitDef` | `id` / `category`（性格 or 癖好）/ `synergy_tags` / `description` | 特质展示与相性计算 |
| `TraitInteractionTable` | `pairs: Array[{a, b, delta, note}]` | 相性 / 克制矩阵，单文件集中维护 |
| `MonsterDef` | `id` / `tags`（群居、重甲、再生、畏光等） | 特殊事件与战报 |
| `HandbookEntry` | `id` / `category` / `body`（BBCode）/ `unlock_condition` | 可随时翻阅的手册，判断简历真伪的常识依据 |
| `DayConfig` | `day_index` / `candidates` / `slots` / `event_pool` / `tutorial_step` | 每一天写死的候选人名单与规则（见 §3.4） |
| `DailyEventDef` | `id` / `monster` / `announce_text` / `bonus_rules` | 记者报道的特殊情况 |
| `NarrativeRule` | `when`（条件）/ `template`（占位符文案）/ `weight` / `priority` | 战报叙事生成 |
| `RunState` | 见第 7 节 | 存档根结构 |

> 随旧机制一并移除：`HiddenProfile`、`ClaimResource`、`QuestionDef`（追问题库）、`SkillDef`
> （技能定义）。追问不再查题库：问句与答句都直接读简历条目自带的 `question` / `answer`。

### 3.4 每日配置（DayConfig）

「每天出现的人直接写死」的落点就在这里：`candidates` 是当日固定名单，数组顺序即出场顺序。

```gdscript
class_name DayConfig extends Resource

@export var day_index: int = 1                          # 第几天，1..GameConfig.TOTAL_DAYS
@export var candidates: Array[CandidateResource] = []   # 当日候选人，写死；size() 即当日人数
@export var slots: int = 3                              # 队伍名额，挑满即进入 BattleReport
@export var event_pool: Array[StringName] = []          # 当日事件池（DailyEventDef.id）
@export var tutorial_step: int = 0                      # 教程进度标识，0 = 本日无教程
```

> `candidates.size()` 取代旧的 `candidate_count`；`questions_per_candidate` / `unlocked_topics`
> 随追问题库一起删除。候选人既可直接内嵌在 `day_XX.tres` 里，也可引用 `data/candidates/*.tres`。

---

## 4. 场景划分与职责

| 场景 | 职责 | 主要信号 |
| --- | --- | --- |
| `boot.tscn` | 加载 `DataDB`，检查存档，跳到主菜单 | — |
| `main_menu.tscn` | 用于收容所有与开始菜单相关的细分场景，新游戏 / 继续 / 设置 / 图鉴回顾 | `new_run_requested` |
| `day_loop.tscn` | **每日流程容器**，按 `DayPhase` 状态机切换子场景 | `phase_changed` |
| `interview.tscn` | 在day_loop下，用于收容所有与面试流程相关的细分场景，作为实际游戏过程中呈现出的面试场景 | — |
| `interview_ui.tscn` | 在 interview 下，用于展示面试中的 UI，包括暂停、设置按钮等系统向 UI 和候选人列表、今日事件等 | — |
| `interviewee.tscn` | 在 interview 下，管理面试者立绘、管理表情差分、对话框 | — |
| `resume.tscn` | 在 interview 下，候选者的完整简历：基础信息、三项属性、等级、职业、特质与简历条目 | — |
| `resume_token.tscn` | 在 resume 下，单个张简历词条以及相关的信息（复用控件） | `selected` |
| `handbook_overlay.tscn` | 在 interview 下，随时可呼出的手册浮层，按关键词检索 | `entry_bookmarked` |
| `team_builder.tscn` | 在 day_loop 下，用于收容从通过者中挑满名额组队这一过程的相关场景 | `team_submitted` |
| `team_builder_ui.tscn` | 在 team_builder 下，用于展示组队过程中的 UI，包括队伍人数，剩余空位，当前激活的羁绊、当日的事件等 | — |
| `candidate.tscn` | 在 team_builder 下，用于展示当日的候选人的简历 | — |
| `battle_report.tscn` | 在 day_loop 下，用于收容下班马车上看战报演出，车夫对话，逐条事件播报，以及分数这一过程的场景 | `report_finished` |
| `ending.tscn` | 用于收容所有与结局场景相关的细分场景，十天后按总分与 flag 判定结局 | `restart_requested` |
| `dialogue.tscn` | 用于在多个场景下创建实例化的对话框 |  |
| `interview_background.tscn` | 用于在多个场景下实现背景相关动画 | 多种（动画种类） |
| `haohan.tscn` | 用于在剧情等地方创建实例化的主角的手 |  |

每日流程由 `day_loop.tscn` 持有状态机驱动：

```
每日流程（第 1..10 天，每天都必须完成一次招人）：

  DayBriefing       国王下旨：今日名额 / 新解锁的面试内容 / 教程提示
		↓
  SpecialEvent      记者报道今日魔物 / 特殊规则
		↓
  招人（每天一次）  Screening 浏览简历 ⇄ Interview 追问面试，两者可来回切换
		↓
  TeamBuild         从通过者中挑满名额，组成今日队伍
		↓
  BattleReport      马车上看战报演出、车夫对话、逐条事件播报、当日分数
		↓
  DayResult         当日得分明细、累计分、手册新解锁
		↓
  ├─ 第 1〜9 天：天数 +1，回到 DayBriefing 开始下一天
  └─ 第 10 天：→ Ending（按累计分与 flag 判定结局）
```

---

## 5. 信号约定（EventBus）

命名统一用「名词 + 过去式」，避免 UI 直接调用逻辑：

暂定这些，如有需要再加

```gdscript
signal day_started(day_index: int)
signal day_phase_changed(phase: int)
signal candidate_opened(candidate_id: StringName)
signal resume_entry_asked(candidate_id: StringName, entry_index: int)
signal verdict_issued(candidate_id: StringName, passed: bool)
signal team_submitted(member_ids: Array[StringName])
signal battle_report_ready(report: BattleReport)
signal day_scored(result: Dictionary)          # {day, gained, total, breakdown}
signal handbook_entry_unlocked(entry_id: StringName)
signal run_finished(ending_id: StringName)
```

---

## 6. 核心机制的实现落点

### 6.1 候选人出场（写死）
`DayConfig.candidates` 直接把当天全部候选人写死（`data/days/day_XX.tres`），数组顺序即出场顺序。
`DataDB` 读到当天配置后交给 `GameState`；刷新、读档拿到的都是同一份名单。

### 6.2 面试与追问
`interview_session.gd` 管理单个候选人的问答循环：

1. 展示简历（逐条 `ResumeEntry.description`）；
2. 玩家点击某一条追问，先显示该条的 `ResumeEntry.question`，再展开对应的 `ResumeEntry.answer`；
3. 玩家对照候选人的 `strength / intelligence / wisdom / level / job / traits` 与手册常识，
   自行判断这条描述与回答是否可信。

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
# data/narrative/claim_exposed.tres（示意）
when     = "member.level < 3 and member.strength + member.intelligence + member.wisdom < 30"
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
  "handbook_unlocked": ["monster.ogre", "job.sword"],
  "phase": "TEAM_BUILD"
}
```

路径：`user://saves/slot_{n}.json`，另存一份 `user://saves/auto.json` 用于每日开始自动存档。

---

## 8. 命名与编码规范

- 场景与脚本：`snake_case.tscn` / `snake_case.gd`，同基名成对出现。
- 自定义 Resource 类：`class_name` 用 `PascalCase`，文件名用 `snake_case`。
- ID 统一 `StringName`，命名空间化：`job.sword`、`trait.ego`、`monster.ogre`、`candidate.c_0001`。
- 常量 `UPPER_SNAKE_CASE`；全局配置放 `GameConfig`（`TOTAL_DAYS = 10` 等）。
- 目录内不出现空场景；每个 `.tscn` 只做一件事。
- `.godot/` 已在 `.gitignore` 中；`*.import` 由 Godot 生成，若版本间产生噪音，可在 `.gitignore` 追加 `*.import`。

---

## 9. 实现里程碑

| 阶段 | 目标 | 验收标准 |
| --- | --- | --- |
| M0 骨架 | autoload 齐备、`SceneRouter` 可跑通 主菜单 → 每日循环（空壳） | 能连续走完 10 天空流程 |
| M1 候选人 | 数据模型 + 写死的每日名单 + 简历卡 UI | 每天按名单稳定出场同一批候选人 |
| M2 面试 | 追问、回答、手册、判定 | 能靠手册推理戳破一个谎 |
| M3 组队与战报 | 相性计算、战斗结算、叙事引擎 | 出现四种典型战报文案 |
| M4 评分结局 | 每日评分、累计分、结局判定 | 好/坏两条结局都能打出来 |
| M5 内容 | 填满 10 天数据、手册、文案、立绘占位 | 一局可玩通 |
| M6 打磨 | 演出、音频、存档、图鉴回顾 | 存档读档一致，可复现整局 |

---

## 10. M0 实现记录（Autoload）

本节记录 §2 那 7 个单例的实际落地接口，供 M1 之后直接调用。

### 10.1 加载顺序（有约束）

`project.godot` 的 `[autoload]` 顺序即 `_ready` 顺序，**EventBus 必须最先**（别人要发信号），
`SceneRouter` 放最后（依赖 EventBus）：

```
EventBus → RngService → DataDB → GameState → SaveService → AudioService → SceneRouter
```

调换顺序会导致后加载者取不到前面的单例。

### 10.2 对外接口摘要

| 单例 | 主要接口 |
| --- | --- |
| `EventBus` | §5 全部信号；另加 `run_started` / `run_loaded` / `candidate_hired` / `save_written` / `save_loaded` / `scene_change_started` / `scene_changed` / `volume_changed`。只有信号，无状态 |
| `GameState` | `start_new_run(seed)` / `apply_run_state(state)` / `clear_run()`；`get_day()` / `advance_day()` / `is_last_day()`；`get_phase()` / `set_phase(DayPhase.Phase)`；`record_day_score()` / `get_total_score()`；`hire()` / `issue_verdict()` / `get_passed_ids()`；`get_flag()` / `set_flag()` / `add_flag()`；`unlock_handbook_entry()`；`set_current_candidates()` / `set_current_team()` |
| `DataDB` | `get_job/candidate/race/trait/monster/handbook_entry/event(id)`、`get_day_config(day)`、`get_narrative_rules()`、`get_interaction_table()`、`search_handbook(keyword)`、`get_ids(kind)` / `count(kind)` / `reload()` |
| `RngService` | `start_run(seed)`、`day_seed(day)`、`day_rng(day)`、`stream(name)`；便捷封装 `randi_in` / `randf_in` / `chance` / `pick` / `pick_many` / `shuffled` / `weighted_pick` |
| `SaveService` | `autosave()` / `load_auto()`、`save_to_slot(n)` / `load_from_slot(n)`、`has_any_save()` / `has_slot(n)` / `delete_slot(n)` / `list_slots()` / `peek(path)`；`to_dict(RunState)` / `from_dict(Dictionary)` |
| `AudioService` | `play_bgm()` / `stop_bgm()`、`play_sfx()`、`set_master_volume()` / `set_bgm_volume()` / `set_sfx_volume()` / `set_volumes()`；BGM/SFX 总线缺失时自动创建 |
| `SceneRouter` | `goto_scene(key)` / `goto_path(path)` / `go_back()` / `reload_current()` / `goto_main_menu()`、`scene_path_for(key)` / `current_scene_key()` / `history()`、`set_fade_duration(s)` |

### 10.3 约定与实现细节

- 全局常量放 `GameConfig`（`scripts/util/`，`class_name` 而非 Autoload），阶段枚举放 `DayPhase`；
  `RunState.phase` 存 `StringName`，用 `DayPhase.to_name()` / `from_name()` 与枚举互转。
- `DataDB` 按 `data/` 的**一级子目录名**归类，新增一类数据只需建目录 + Resource 脚本，不必改代码。
  资源未填 `id` 时回退为 `job.fighter` 这样的「前缀.文件名」并给出警告——骨架 `.tres` 因此仍可用。
- `GameState` 里只有 `run_state` 是存档内容；`current_candidates` / `passed_ids` / `current_team`
  属于**本日过程量**，读档后靠种子重放，不进 JSON。
- 存档 JSON 读回来时 `flags` 的键会从 String 转回 `StringName`，整数型数字会从 float 转回 int，
  否则读档后 `get_flag()` 查不到、`3 != 3.0`。
- 场景跳转一律走 `SceneRouter.goto_scene()`，场景脚本不直接调 `change_scene_to_file`；
  过场遮罩挂在 Autoload 下（`TransitionOverlay`），切场景时不会闪断。

### 10.4 自检

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_m0.tscn
```

`tools/smoke_m0.gd` 覆盖上表接口与 M0 验收：单例齐备、DataDB 扫描、**候选人 / 每日名单数据层（§11）**、
同种子可复现、存读档一致、真实跑一遍 主菜单 Start 按钮 → 每日循环 → 十天四十步 → 结局 → 返回主菜单。
全绿时退出码 0。

> 自检脚本是 `tools/smoke_m0.tscn` 这个空场景，自检逻辑挂在 root 下的常驻 runner 上
> ——因为自检过程本身要切场景，而切场景会释放 current_scene。

> ⚠️ 走十天那一段（`_walk_day_loop`）是**协程**：每次推进之间 `await process_frame`。
> `day_loop.advance()` 有「同一帧只许推进一次」的重入锁（`_advance_locked`，靠 `call_deferred` 解锁），
> 早先一帧内连点 70 次只有第一次生效，后面 69 次全被吞掉、走到 SPECIAL_EVENT 就卡住了。
> 想改这段先看这条，别再把 `await` 去掉。

> ⚠️ 存读档那 7 项在**受限沙箱**里必然红：`user://`（Windows 上是 `%APPDATA%\Godot\app_userdata\Yuusha`）
> 落在项目目录之外，写不进去会报 `无法写入 user://saves/auto.json（错误码 12）`。
> 这是环境限制不是代码问题 —— 在正常机器上跑就是绿的。

### 10.5 场景层（M0 完成部分）

| 场景 | 脚本 | 职责 |
| --- | --- | --- |
| `scenes/menu/main_menu.tscn` | `main_menu.gd` | **项目启动场景**（`application/run/main_scene`）。Startgame → `GameState.start_new_run()` + `SceneRouter.goto_scene("day_loop")`；Exitgame 二次点击确认退出 |
| `scenes/day/day_loop.tscn` | `day_loop.gd` | 每日流程容器：订阅 `day_phase_changed` 换阶段子场景；`advance()` 向 `DayDirector` 问下一步；进入每天时自动存档 |
| `scenes/ending/ending.tscn` | `ending.gd` | 十天的落点：占位显示累计分 + 「返回主菜单」，对外发 `restart_requested` |
| `scenes/boot/boot.tscn` | `boot.gd` | 备用入口：DataDB 兜底检查 → 主菜单。当前**不是**启动场景，要开场演出时把 `run/main_scene` 改回来即可 |
| `scripts/core/flow/day_director.gd` | — | 每日流程推进规则（纯静态）：`advance(phase, day)` / `scene_key_for(phase)` |

- 一天走 7 个阶段：DayBriefing → SpecialEvent → Screening → Interview → TeamBuild → BattleReport → DayResult；
  第 10 天的 DayResult 之后进 Ending，其余天数回到 DayBriefing。招人阶段实际可在
  Screening / Interview 之间来回切换，`DayDirector` 给的是一条默认推进路线。
- `day_loop` 与 `ending` 里各有一块 **占位 HUD**：M0 的阶段子场景还是空壳，得有东西点着才能走完十天。
  占位文案暂时是 ASCII —— `assets/fonts` 还没接入中文主字体，默认字体没有中文字形，中文会变方块。
  做出真正的阶段界面后直接删掉这两个节点即可：脚本对它们的引用全部走 `get_node_or_null`。
  `day_loop` 这块（`FlowHud`）已经挪到 `layer = -1`，让有真正界面的阶段能盖住它 —— 见 §10.6。

### 10.6 resume / resume_token（简历版面）

简历版面。编辑器里打开 `resume.tscn` 按 F6 单独跑：看到的是一张**空**纸 ——
版面里没有任何候选人文案，内容全靠 `set_candidate()` 灌（见 §10.7）。

| 文件 | 职责 |
| --- | --- |
| `scenes/day/interview/resume/resume.gd` / `.tscn` | 简历整页。`assets/art/interview/resume_page_phd.png` 让 `Sprite2D(centered=false)` 铺在 (0,0)，右侧纸面（约 624,62 ～ 980,549）上叠一列信息 |
| `scenes/day/interview/resume/resume_token.gd` / `.tscn` | 单条词条，根节点是 `Button`（`class_name ResumeToken`），对外信号 `selected(entry_index)` |
| `ui/styles/resume_token_normal.tres` · `resume_token_hover.tres` | 词条的 normal / hover 两个 StyleBox。独立成资源而不是内联，以后做 `ui/themes/` 时能直接复用 |

版面自上而下：**抬头**（`Paper/Rows/HeaderInfo`，一个 Label）→ `RESUME ENTRIES` 小标题 → 词条列表（`Paper/Rows/TokenList`）。

- **抬头是一个字符串，不是一个字段一个 Label**：姓名 / 职业 + 等级 / 三项属性 / 特质全部写在
  `CandidateResource.resume_header` 那**一个**多行字符串里，`resume.gd` 只做一件事 ——
  `set_info(candidate.resume_header)`，**一个字都不拼**。
  想调抬头版式（换行、字段间距、字段顺序、要不要写属性、加不加一句花腔）直接在
  `data/candidates/*.tres` 里改那一段字，代码和场景都不用动。
  换句话说：**抬头是文案，不是由数值推导出来的**。`display_name` / `level` / `strength` 那些字段
  是给玩法（判定、相性、战报）用的数值，和抬头故意不联动 —— 抬头里写什么、写不写全，由文案说了算。
  `RESUME ENTRIES` 那行**没有**并进去 —— 它是词条区的段标题（场景自己的装饰文案），不是候选人信息。
  代价是所有行共用一个字号（现在 15）。若想让姓名单独放大，把这一个节点换成 `RichTextLabel` 走 BBCode
  即可（`HandbookEntry.body` 已经是这个路子），仍然是一个字符串。

- **悬停高亮**只靠 Button 的 `theme_override_styles/hover`（半透明琥珀底 + 描边），normal 是一条细下划线。
  脚本里没有任何 `_on_mouse_entered`：hover 由 Button 自己驱动，改配色只动 `.tres`。
- **点击目前没有任何效果**：`pressed` 与 `normal` 指向**同一个** `.tres`，按下去的画法和没按一模一样；
  `focus_mode = 0` 关掉焦点框，点完不会残留高亮。`selected` 按 §4 预留并照常 emit，只是当前没有订阅者。
  → §6.2 的追问流程（先给 `question`、再展开 `answer`）留到 M2，届时由 `resume.gd` 订阅 `selected`。
- **纸上的字全部来自数据**：`resume.gd` 里没有一句候选人文案，也没有「默认履历」这种兜底。
  唯一的数据入口是 `set_candidate(candidate: CandidateResource)`：
  抬头 ← `resume_header`（原样），词条 ← `descriptions_of()`（逐条 `description`）。
  传 `null` 表示「当前没有候选人」→ 抬头清空、词条全部收起。`get_candidate()` 能把当前这位取回来，
  M2 做追问时就从它身上取 `resume[i].question` / `.answer`。
- **条目数量自适应**：`set_entries()` 会先复用场景里预摆的 5 个实例（编辑器里直接看到真实版面，
  但它们**不写死任何正文**，`text` 全是空串），数据比预摆多就现场 `instantiate()`，
  少就把富余的 `visible = false`。所以「若干项」都不用回头改场景。
- 纸上的文案现在是**中文**（和 `data/dialogue.json` 一致）—— 中文字体没接入前会变方块，原因见 §10.5。
  字体接进来后这里一行都不用改。

#### 挂载点

`resume.tscn` 作为 **`interview.tscn` 的子节点**实例化。`597305d` 之后 `interview` 一个场景承载
DayBriefing / SpecialEvent / Screening / Interview 四个阶段：

```
DayLoop (Node)
├─ PhaseContainer (Node)
│   └─ Interview (Control)          ← interview.tscn，DayLoop 按阶段实例化
│       ├─ ItvBkgPhd   (0)  背景
│       ├─ Interviewee (1)  立绘
│       ├─ TablePhd    (2)  桌子
│       ├─ Resume      (3)  ← 简历，压在立绘/桌子之上（TokenMenu 是它的子节点）
│       ├─ NoticeBoard (4)  公告板
│       ├─ Dialoguer   (5)
│       ├─ Approved    (6)  录用
│       ├─ Nah         (7)  拒绝
│       └─ Haohan      (8)  主角的手
└─ FlowHud (CanvasLayer, layer 10)  ← M0 占位 HUD
```

**显隐由阶段决定，简历自己不管**：`interview.gd::_apply_phase_visuals()` 里
`_resume.visible = DayPhase.is_recruiting(_phase)`，简历只在招人阶段出现。
隐藏的是 Resume 整棵子树，所以菜单也跟着不画了 —— 但菜单自己的 `visible` 仍是 `true`，
回到招人阶段会「诈尸」。`resume.gd` 因此接了 `visibility_changed`，一被藏起来就 `close()`。

> 注：这里曾一度把 `FlowHud` 改成 `layer = -1`（让阶段界面盖住占位 HUD，顺带解决它抢鼠标）。
> `597305d` 走的是另一条路：HUD 留在 `layer = 10`，但把 `FlowHud/Hud` 的矩形缩到左上角 303×297
> （`offset_right = -849`、`offset_bottom = -351`），不再盖住简历区。两种做法都能解决
> 「全屏 `MOUSE_FILTER_STOP` 的占位 HUD 抢鼠标」，**以现在这版为准**。

#### resume_token_menu（点词条弹出的菜单）

| 文件 | 职责 |
| --- | --- |
| `scenes/day/interview/resume/resume_token_menu.gd` / `.tscn` | 面板 + 选项列表，`class_name ResumeTokenMenu`，对外信号 `ask_requested(entry_index)` |
| `assets/art/interview/resume_token_menu_phd.png` | 手绘白纸面板贴图，原生 145×223 |

节点：`ResumeTokenMenu (Control)` → `Panel (TextureRect)` + `Options (MarginContainer)` →
`OptionList (VBoxContainer)` → `AskButton`。它作为 `resume.tscn` 里的 `TokenMenu` 子节点实例化，
默认 `visible = false`，开关由 `resume.gd` 管。

- **交互**：点词条 → `resume_token` 的 `selected` → `resume.gd._on_token_selected()` →
  `menu.open_for(token, i)`；点菜单外面或按 Esc 收起。点菜单外面时**故意不 `set_input_as_handled()`**，
  所以点到别的词条上时那条词条照样收到 `pressed`，菜单顺势挪过去（要的就是这个手感）。
- **「追问」按钮暂时没有后续**：`ask_requested` 按 §4 的路子预留并照常 emit，但 `resume.gd` 不订阅，
  菜单也不会自己关 —— §6.2 的「先给 `question`、再展开 `answer`」留到 M2。
  按钮的 normal / hover 直接复用 `ui/styles/resume_token_*.tres`，和词条同一套观感。

**画布适配**（`aspect=expand` 下画布会随窗口比例变大，所以位置不能写死）：

- 面板按纹理原生尺寸摆放、**不拉伸**（手绘边框拉变形很难看）；窗口缩放统一交给 `canvas_items`。
- `open_for()` 现算词条的 `global rect` 再摆：默认贴右边、与词条顶对齐 → 右边放不下翻到左边 →
  最后整体夹进 `get_viewport_rect()`。并且接了 `viewport.size_changed` 重算，画布一变菜单自己会跟。
- `_ready()` 校验纹理尺寸 == `PANEL_SIZE`，对不上就 `push_warning`（换图必然要重新量内边距）。

> ⚠️ 按钮文案「追问」是中文，而 `assets/fonts` 还没接入中文字体：`smoke_resume_menu` 实测
> `ThemeDB.fallback_font.has_char('追')` 为 **false**，按钮现在会显示成**两个方块**。
> 字体接进来后这里不用改代码。

#### 自检

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_resume_menu.tscn
```

43 项：面板/按钮就位、**纸面内容确实来自 `data/candidates/*.tres`**（抬头原样铺数据里那一段字、
逐条词条正文来自 `description`）、给一份「不像字段拼出来」的抬头也照样原样显示、喂 `null` 时整页清空、
点词条开菜单并记住序号、贴边 / 翻边 / 底部夹取、**改画布尺寸后自动重排**、点外面与 Esc 收起、
整块显隐不诈尸、「追问」抛信号但无后续。全绿退出码 0。

它把简历放进一个尺寸可控的 `SubViewport`（1152×648 = 游戏真实画布）：headless 下窗口是 1152×1152
且 `--resolution` 不生效，直接挂在 root 上既测不到真实画布，也测不了「画布变了」这一条。

「底部夹取」那几条不写死 y 坐标：词条条数现在由数据决定，位置不再是个固定值，
所以测试先把画布压到「最后一条词条刚好放不下整块菜单」的高度，再验夹取。

---

## 11. 面试者数据（M1）

> 这一节记的是「简历和候选人显示的东西，一句都不在代码里写死」这件事的落点。
> 面试者的**全部信息**在 `data/candidates/*.tres`，**每天出场哪几个人**在 `data/days/*.tres`。

> ### ⚠️ 当前 `data/` 里的文案**全是占位符**，不是内容
>
> 骨架期手搓的那批示例文案（姓名、抬头、简历条目、职业名、特质名）已经**全部清空成占位符**，
> 免得和之后真正手填的内容混在一起分不清哪句是新的哪句是旧的。现在的样子是：
>
> | 字段 | 现在长什么样 |
> | --- | --- |
> | 候选人 `display_name` | `PLACEHOLDER NAME 01` … `PLACEHOLDER NAME 25` |
> | 候选人 `resume_header` | `PLACEHOLDER HEADER 01` …（单行） |
> | 简历条目 | `PLACEHOLDER ENTRY / QUESTION / ANSWER 01-1`（`编号-条目号`） |
> | 职业 | `PLACEHOLDER JOB 01` … `03`（+ `PLACEHOLDER JOB DESC NN`） |
> | 特质 | `PLACEHOLDER TRAIT 01` … `10`（+ `PLACEHOLDER TRAIT DESC NN`） |
>
> **编号规则**：按文件名排序从 01 起编 —— 候选人 `c_0001.tres` → `01`；
> 职业按 `cleric` / `fighter` / `mage`；特质按字母序（`calm` → `01` … `lone_wolf` → `10`）。
> 编号只用来对号入座，本身不代表任何含义。
>
> **这次只动文案，没动结构**，下面这些原样保留（它们是**键和数值**，不是文案）：
> `id`（每日名单靠它引用）、`level` / `strength` / `intelligence` / `wisdom`、
> `job` 与 `traits` 的**引用关系**、`synergy_tags`、`portrait_*` 立绘配方、`data/days/` 全部。
>
> 手填时直接把这串 `PLACEHOLDER …` 替换掉就行 —— 全仓 `Ctrl+F "PLACEHOLDER"` 能一次找齐。
>
> 顺带一个副作用：占位符是纯 ASCII，而 `assets/fonts` 还没接入中文字体（§10.5），
> 所以现在简历页上的字是**能正常显示**的（不会变方块），正好可以拿来看版面。
> 换成中文文案后又会变回方块，直到字体接进来。

### 11.1 两类数据文件

| 目录 | 粒度 | 装什么 |
| --- | --- | --- |
| `data/candidates/` | **一位面试者一个文件**（`c_0001.tres` … `c_0025.tres`） | 姓名、等级、三项属性、职业（引用 `data/jobs/*.tres`）、特质（引用 `data/traits/*.tres`）、**简历抬头**（`resume_header`，一整段字）、**拼装立绘配方**、**逐条简历条目**（描述 / 追问 / 回答，内联 `sub_resource`，跟着本人走） |
| `data/days/` | **一天一个文件**（`day_01.tres` … `day_10.tres`） | `day_index`、`candidates`（当天出场哪几个人，**引用** `data/candidates/*.tres`，数组顺序即出场顺序）、`slots`（当日名额）、`tutorial_step` |

配套还有 `data/jobs/`（剑士 / 法师 / 牧师）与 `data/traits/`（性格 6 种 + 癖好 4 种）。

> 简历条目**内联**在候选人文件里（而不是单独一个目录），因为它是「这个人」的一部分，
> 不该被别的候选人复用；职业与特质**引用**外部文件，因为它们是多个人共用的词表。
> 每日名单只列 id 引用，绝不内嵌副本 —— 改一次候选人，10 天里出场的那次跟着变。

### 11.2 数据怎么流到画面上

```
data/days/day_XX.tres
   └─ candidates ──► GameState.load_day_candidates()          ← 开局 / 换天 / 读档时调
                        └─ GameState.current_candidates
                             └─ interview.gd.current_candidate()   （下标 = finished_interviewee）
                                  ├─ Interviewee.apply_candidate()  → 按 portrait_* 拼立绘
                                  └─ Resume.set_candidate()         → 抬头 + 逐条词条
```

- 当日名单是**本日过程量**，不进存档（§7）：`GameState` 在 `start_new_run()` / `advance_day()` /
  `apply_run_state()` 三处按当前天数重新从 `data/days/` 取，读档拿到的就是同一份。
- `interview.gd` 判定一位就把 `finished_interviewee` +1 并整体重刷 —— 立绘与简历一起翻页。
- 立绘的种族与部件编号全部读自候选人，**没有任何随机**：以前那段 `_debug_randomize_interviewee()`
  调试代码已删除。`Interviewee` 在拿到配方前保持空白，不画「默认人」。

### 11.3 改数据不用改代码

- 换简历文案 / 加一条词条 / 调属性 → 编辑器里点开对应的 `data/candidates/*.tres`。
- **改抬头** → 同一个文件里的 `resume_header`，多行文本框，写什么就显示什么。
  想让人物的自我介绍更有性格（甚至藏一个后面能被手册戳破的谎言），改这一栏就行。
- 换某天出场的人 / 调名额 → 点开 `data/days/day_XX.tres`，拖 `candidates` 数组。
- 加一位新面试者 → `data/candidates/` 下新建一份，再把它拖进某天的 `candidates`。
- 加一个新职业 / 新特质 → 在 `data/jobs/` / `data/traits/` 建资源，候选人引用它即可（`DataDB` 按目录自动归类）。

### 11.4 覆盖率自检

`smoke_m0` 第 `[3.1]` 节盯的就是这层数据：25 位候选人、10 天名单、每天 `slots` 不超过当天人数、
名单里的每个人都能在 `data/candidates/` 里查到、每条简历都齐了描述 / 追问 / 回答三样、
**每位候选人都自带一段抬头文案**，以及 `GameState` 开局 / 换天时名单确实跟着换。
