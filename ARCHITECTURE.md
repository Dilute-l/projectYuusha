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
│       ├─ portrait_composer.gd     立绘部件命名 + 拼装（面试立绘与组队圆头像共用，见 §12）
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
│   │   │   ├─ team_builder_ui.tscn     组队 UI：今日候选人头像列表、已录用 / 名额（§12）
│   │   │   └─ candidate.tscn          左侧单条候选人：圆头像 + 名字（悬停 / 左键，§12）
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
| `resume` | 简历 | `Array[ResumeEntry]`，每条 = 一句描述 + 追问对话 json 的路径 |
| `resume_header` | 简历抬头 | **一整段字**，原样铺在纸面上半；运行时不做任何拼接（§10.6） |
| `portrait_*` | 拼装立绘配方 | 种族 + 各部件差分编号；面试者的长相也是数据，不是代码里摇的（§10.7） |

> 真假不再由隐藏字段承载：玩家看到的 `strength / intelligence / wisdom / level / job / traits`
> 就是全部数值，判断依据来自「属性与简历描述的落差」＋「手册常识」，见 §6.2 / §6.3。

### 3.2 简历条目（ResumeEntry）

```gdscript
class_name ResumeEntry extends Resource

## 简历上写的那句话，例如「我曾单独讨伐过三只食人魔。」
@export_multiline var description: String = ""

## 针对本条的追问对话：一段独立 json 的路径（一条追问一个文件）
@export_file("*.json") var ask_path: String = ""
```

简历由若干条目组成，**每条只有两样东西**：简历上写的那句话，以及这条的追问对话存在哪个
json 里。台词**不住在档案里** —— 档案只留路径，正文全部写在 `data/asks/<候选人>_<序号>.json`：

```
data/asks/c_0001_1.json
[
	{ "speaker_name": "面试官", "text": "你是怎么打败它们的？" },
	{ "speaker_name": "棍木",   "text": "趁它们分食时逐个击破的。" }
]
```

文件格式就是 `data/dialogue.json` 里**一段对话**的格式，所以 Typer 那套逐字显示 / 点击推进 /
段级 `config` 全部照用，不需要任何额外机制。

面试交互见 §6.2：玩家点击某一条 → 播出该条的 json（先问、后答）；是否可信，由玩家结合
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
> （技能定义）。追问也不查题库：问句与答句都写在**这条自己的 json** 里，档案上只留一个路径。

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
| `team_builder_ui.tscn` | 在 team_builder 下，用于展示组队过程中的 UI：**左半边今日面试者的头像列表**、已录用 / 名额表头（§12） | `candidate_hovered` / `candidate_toggled` |
| `candidate.tscn` | 在 team_builder 下，左侧**单条**候选人：圆形头像（黑色纯色圆边框）+ 名字（§12） | `hovered` / `toggled` |
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
  招人（每天一次）  Interview 在面试场景里看简历、逐条追问、给出录用判定
		↓
  TeamBuild         从通过者中挑满名额，组成今日队伍
		↓
  BattleReport      马车上看战报演出、车夫对话、逐条事件播报、当日分数
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
2. 玩家点击某一条追问，播出该条的 `ResumeEntry.ask_path` 指的那份 json；
3. 玩家对照候选人的 `strength / intelligence / wisdom / level / job / traits` 与手册常识，
   自行判断这条描述与回答是否可信。

> **② 已实现**（`Interview` 阶段内）：点词条 → 菜单「追问」→ `resume.gd` 广播
> `EventBus.resume_entry_asked(candidate_id, entry_index)` → `interview.gd` 拿到
> `ask_path`，用 `typer.load_dialogue_from(path)` 装入那份 json，再 `dialoguer.play()`。
> 追问是临时对话，播完只收起对话框、**不推进阶段**。详见 §10.7。

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

- 一天走 5 个阶段：DayBriefing → SpecialEvent → Interview → TeamBuild → BattleReport；
  第 10 天的 BattleReport 之后进 Ending，其余天数回到 DayBriefing。招人阶段（Interview）
  内部怎么走由面试流程自己决定，`DayDirector` 给的是一条默认推进路线。
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

- **悬停高亮**只靠 Button 的 `theme_override_styles/hover`（**一个淡黄色矩形，没有描边**），
  normal 是一条细下划线。脚本里没有任何 `_on_mouse_entered`：hover 由 Button 自己驱动，改配色只动 `.tres`。
- **点击效果 = 在旁边弹出词条菜单**（见下面「词条菜单」与 §10.7）：`pressed` 与 `normal`
  指向**同一个** `.tres`，按下去的画法和没按一模一样；`focus_mode = 0` 关掉焦点框，点完不会残留高亮。
  视觉上的「选中」由 `resume.gd` 订阅 `selected` 后弹菜单来表达，不是按钮自己画的。
- **纸上的字全部来自数据**：`resume.gd` 里没有一句候选人文案，也没有「默认履历」这种兜底。
  唯一的数据入口是 `set_candidate(candidate: CandidateResource)`：
  抬头 ← `resume_header`（原样），词条 ← `descriptions_of()`（逐条 `description`）。
  传 `null` 表示「当前没有候选人」→ 抬头清空、词条全部收起。`get_candidate()` 能把当前这位取回来，
  追问时就从它身上取 `resume[i].ask_path`（§6.2）。
- **条目数量自适应**：`set_entries()` 会先复用场景里预摆的 5 个实例（编辑器里直接看到真实版面，
  但它们**不写死任何正文**，`text` 全是空串），数据比预摆多就现场 `instantiate()`，
  少就把富余的 `visible = false`。所以「若干项」都不用回头改场景。
- 纸上的文案现在是**中文**（和 `data/dialogue.json` 一致）—— 中文字体没接入前会变方块，原因见 §10.5。
  字体接进来后这里一行都不用改。

#### 挂载点

`resume.tscn` 作为 **`interview.tscn` 的子节点**实例化。`597305d` 之后 `interview` 一个场景承载
DayBriefing / SpecialEvent / Interview 三个阶段：

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
| `scenes/day/interview/resume/resume_token_menu.gd` / `.tscn` | 面板 + 选项列表，`class_name ResumeTokenMenu`，对外信号 `ask_requested(entry_index)`；文案可换（`set_option_text`）、可置灰（`open_for` 的 `enabled`） |
| `assets/art/interview/resume_token_menu_phd.png` | 手绘白纸面板贴图，原生 145×223 |

节点：`ResumeTokenMenu (Control)` → `Panel (TextureRect)` + `Options (MarginContainer)` →
`OptionList (VBoxContainer)` → `AskButton`。它作为 `resume.tscn` 里的 `TokenMenu` 子节点实例化，
默认 `visible = false`，开关由 `resume.gd` 管。

- **交互**：点词条 → `resume_token` 的 `selected` → `resume.gd._on_token_selected()` →
  `menu.open_for(token, i, enabled)`；点菜单外面或按 Esc 收起。点菜单外面时**故意不 `set_input_as_handled()`**，
  所以点到别的词条上时那条词条照样收到 `pressed`，菜单顺势挪过去（要的就是这个手感）。
- **同一个按钮，两个阶段两种意思**：面试里是「追问」，组队里是「回忆」——
  文案由 `resume.gd` 按自己的 `entry_menu` 设，点下去抛的仍是 `ask_requested`，
  由 `resume.gd._on_ask_requested()` 分流成 `resume_entry_asked` / `resume_entry_recalled` 两个信号。
  `enabled = false`（组队里「这条当时没问过」）时按钮**置灰且点不动**，但菜单照常弹出来 ——
  玩家至少能看到「哦，这条我没问」。
  **`resume.gd` 不播对话** —— 台词交给所在阶段（`interview.gd` 真的去问 / `team_builder.gd` 重播，见 §10.7）。
  按钮的 normal / hover 直接复用 `ui/styles/resume_token_*.tres`，和词条同一套观感；
  置灰另有 `font_disabled_color` + `disabled` 样式（同一个 normal 底，只把字压灰，别退回默认主题那个灰框）。

**画布适配**（主画布在 `aspect=keep` 下恒为 1152×648、**不随窗口变**；位置仍不写死，
因为 `SubViewport` 自检会自己造别的尺寸）：

- 面板按纹理原生尺寸摆放、**不拉伸**（手绘边框拉变形很难看）；窗口缩放统一交给 `canvas_items`。
- `open_for()` 现算词条的 `global rect` 再摆：默认贴右边、与词条顶对齐 → 右边放不下翻到左边 →
  最后整体夹进 `get_viewport_rect()`。并且接了 `viewport.size_changed` 重算 ——
  主画布下它不会触发，但 `tools/smoke_resume_menu.gd` 用 `SubViewport` 造不同尺寸的画布，
  靠的就是这条路径，**别删**。
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
整块显隐不诈尸、「追问」广播 `resume_entry_asked` 并收起菜单。全绿退出码 0。

它把简历放进一个尺寸可控的 `SubViewport`（1152×648 = 游戏真实画布）：headless 下窗口是 1152×1152
且 `--resolution` 不生效，直接挂在 root 上既测不到真实画布，也测不了「画布变了」这一条。

「底部夹取」那几条不写死 y 坐标：词条条数现在由数据决定，位置不再是个固定值，
所以测试先把画布压到「最后一条词条刚好放不下整块菜单」的高度，再验夹取。

---

### 10.7 追问（简历条目 → 对话框）

§6.2 第 ② 步的实现。**台词一句都不在代码里，也不在候选人档案里** ——
档案上只留一个路径（`ResumeEntry.ask_path`），正文写在那份独立 json 中，
`data/asks/<候选人 id>_<条目序号>.json`（序号从 1 开始），一条追问一个文件。

```
点词条 ─ selected ─→ resume.gd._on_token_selected() ─ open_for() ─→ 菜单
菜单「追问」─ ask_requested ─→ resume.gd._on_ask_requested()
									│  收菜单；越界 / 空纸就地拦下
									↓
					 EventBus.resume_entry_asked(candidate_id, entry_index)
									↓
			  interview.gd._on_resume_entry_asked()
									│  过守卫（阶段 / 不打断阶段对话 / 是不是这一位）
									│  取 entry.ask_path，确认文件在
									↓
					typer.load_dialogue_from(ask_path) ─→ dialoguer.play()
```

| 落点 | 职责 |
| --- | --- |
| `resume.gd._on_ask_requested()` | 收菜单 + 广播 `resume_entry_asked`。**不播对话** |
| `interview.gd._on_resume_entry_asked()` | 守卫 + 取 `ask_path` + 交给自己的 `Dialoguer` |
| `resume_token_menu.gd.ask_requested` | 菜单里那个按钮的信号（`entry_index` 跟着抛出来） |
| `typer.gd.load_dialogue_from()` | 从指定 json 装入一段；`load_dialogue()` 的姐妹方法，见下 |

**为什么要有 `typer.load_dialogue_from()`**：`load_dialogue(id)` 只读 `dialogue_path` 这一个文件，
而追问是一条一个文件。新方法就是「把文件也当参数传进来」：

```gdscript
# main_menu.gd —— 台词来自默认的 data/dialogue.json，按 id 选段
if not dialoguer.typer.load_dialogue("second"):
	return
dialoguer.play()

# interview.gd —— 台词来自这一条追问自己的 json
if not _dialoguer.typer.load_dialogue_from(entry.ask_path):
	return
_dialoguer.play()
```

装入之后那条链（逐字显示 → 点一下推进 → 最后一句点一下收起）**与 JSON 对话完全是同一套**，
`dialoguer.play()` 一个字都没改。`load_dialogue_from()` 按 path 判断要不要重读文件：
换了文件就重读（所以连着追问两条不会串味），同一个文件连着播两段也不会白读盘。
`_load_all()` 里的三张段级表（字间隔 / 音效 / 静音集合）也跟着一起清 —— 它们按 id 索引，
换了文件之后同名 id 的设置会串味。

**两条约定**：

- **追问是临时对话**：不置 `_advance_when_dialogue_ends`，所以播完只收起对话框，
  **不会把阶段推走**（见 `_on_dialogue_ended` 的说明）。追问完还能继续追问、继续判定。
- **不打断阶段对话**：国王下旨 / 今日事件那几段还挂着「看完自动推进」时，追问直接返回 ——
  打断等于把阶段对话换掉，而它不会再播第二次。

#### 「问过没有」记在哪儿

追问**播成功**之后（`interview.gd` 里 `load_dialogue_from()` 返回 true、`play()` 之前），
`GameState.record_entry_asked(candidate_id, entry_index)` 记一笔：

```gdscript
## 本日追问过的条目：candidate_id -> Array[int]。本日过程量，不入存档。
var asked_entries: Dictionary = {}
```

- **为什么在 GameState 而不是 `ResumeEntry`**：`ResumeEntry` 是被候选人共用的**资源**，
  往里写运行时状态会在「同一条被两个人引用」时串味，也会被编辑器当成数据改动。
- **为什么「没播成就不算」**：`ask_path` 为空 / 文件不在 / 阶段不对时都没真的问出来，
  这种条目在组队里不该亮起来（否则点开一片空白）。自检专门盯了这条。
- 换天、开新局、读档、回主菜单都会把它清空（和 `passed_ids` 同命，见 `GameState` 里那四处 reset）。

#### 组队阶段的「回忆」（§12）

同一张简历、同一个菜单，到了组队阶段换成 `entry_menu = RECALL`：文案变「回忆」，
**没问过的条目置灰**（`resume.gd._option_enabled()` 查的正是上面那份记录）。

```
菜单「回忆」─ ask_requested ─→ resume.gd._on_ask_requested()
									│  entry_menu == RECALL → 发另一个信号
									↓
					 EventBus.resume_entry_recalled(candidate_id, entry_index)
									↓
			  team_builder.gd._on_resume_entry_recalled()
									│  查记录（没记录就不播）
									↓
	typer.load_dialogue_from(ask_path) ─→ typer.append_line(面试官, "当时好像是这样追问的。")
									─→ dialoguer.play()
```

**为什么两个信号不复用**：按钮是同一个、菜单也是同一个，但两个阶段要做的事完全不同
（面试=真的去问，组队=重播当时那段）。分开之后，收信号的人不必再自己判断「现在是哪个阶段」。

**最后那句自言自语走 `typer.append_line()`**：它只往**内存里这次播放**的行数组后面接一句，
不碰任何文件 —— `data/asks/` 里那些 json 存的永远是「面试当时真正播的东西」。
那句文案是 `team_builder.gd` 的两个常量（`RECALL_TAIL_SPEAKER` / `RECALL_TAIL_TEXT`）：
它是场外补充，不属于任何候选人，和「当时真的说了什么」是两回事。

#### 自检

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_interview_ask.tscn
```

37 项（再加「问过没有」的记录，见下），跑的是**真的 `interview.tscn`**（不是 `resume.tscn`）：
当日名单 → 点词条 → 点「追问」，把播出的每一行与该条 `ask_path` 那份 json **逐字比对**，
再验逐字显示、说话人 Label 随行切换、点到底对话框收起、**全程 `phase_finished` 一次都没发**、
换第 2 条时播的是**它自己**那份 json（换文件确实重读了）、追问之后仍能按 id 装入默认
`dialogue.json` 而不留残留内容，**播成功会记下「这一条问过」而没播成的不会**，
以及四条守卫（非追问阶段 / 不是当前在面试的那位 / 下标越界 / `ask_path` 空或指错）都拦得住。
全绿退出码 0。

> ⚠️ 期望值全部**现场从 `data/asks/*.json` 读**，脚本里没有一句台词 —— 改文案、改说话人都不用动它；
> 但改 json 的结构（行数、字段名）会在这里报出来。

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
| `data/candidates/` | **一位面试者一个文件**（`c_0001.tres` … `c_0025.tres`） | 姓名、等级、三项属性、职业（引用 `data/jobs/*.tres`）、特质（引用 `data/traits/*.tres`）、**简历抬头**（`resume_header`，一整段字）、**拼装立绘配方**、**逐条简历条目**（描述 + 追问 json 的路径，内联 `sub_resource`，跟着本人走） |
| `data/asks/` | **一条追问一个文件**（`c_0001_1.json` … 共 75 份） | 那一条的追问对话本身：行数组，每行 `{ speaker_name, text }`，格式同 `data/dialogue.json` 的一段 |
| `data/days/` | **一天一个文件**（`day_01.tres` … `day_10.tres`） | `day_index`、`candidates`（当天出场哪几个人，**引用** `data/candidates/*.tres`，数组顺序即出场顺序）、`slots`（当日名额）、`tutorial_step` |

配套还有 `data/jobs/`（剑士 / 法师 / 牧师）与 `data/traits/`（性格 6 种 + 癖好 4 种）。

> 简历条目**内联**在候选人文件里（而不是单独一个目录），因为它是「这个人」的一部分，
> 不该被别的候选人复用；职业与特质**引用**外部文件，因为它们是多个人共用的词表。
> 每日名单只列 id 引用，绝不内嵌副本 —— 改一次候选人，10 天里出场的那次跟着变。
>
> **追问对话反过来单独成文件**：它是「一段要播的戏」，有说话人、有行数、有节奏，
> 归到对话数据里更顺手（写手改台词不用碰 `.tres`，也不怕手滑改坏资源格式）。
> 档案只留 `ask_path` 一个路径 —— 这也是**唯一**允许指向 `data/asks/` 的地方。
> 数据完整性由 `smoke_m0` 兜底：每条 `ask_path` 都得指到一份存在的、能解析成非空数组的 json。

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
- **改追问台词** → 点开那一条的 `ask_path` 指的 `data/asks/*.json`。写手可以完全不碰 `.tres`：
  说话人、行数、停顿时长（段级 `config`）都在 json 里。
- **加一条追问** → `data/asks/` 下新建一份 json，再回候选人档案里把这一条的 `ask_path` 指过去。
- **改抬头** → 同一个文件里的 `resume_header`，多行文本框，写什么就显示什么。
  想让人物的自我介绍更有性格（甚至藏一个后面能被手册戳破的谎言），改这一栏就行。
- 换某天出场的人 / 调名额 → 点开 `data/days/day_XX.tres`，拖 `candidates` 数组。
- 加一位新面试者 → `data/candidates/` 下新建一份，再把它拖进某天的 `candidates`。
- 加一个新职业 / 新特质 → 在 `data/jobs/` / `data/traits/` 建资源，候选人引用它即可（`DataDB` 按目录自动归类）。

### 11.4 覆盖率自检

`smoke_m0` 第 `[3.1]` 节盯的就是这层数据：25 位候选人、10 天名单、每天 `slots` 不超过当天人数、
名单里的每个人都能在 `data/candidates/` 里查到、每条简历都齐了描述 + `ask_path` 两样、
**每位候选人的每条追问 json 都真的存在且能解析**（75 份，路径写错 / 文件忘提交 / json 写坏都在这里炸）、
**每位候选人都自带一段抬头文案**，以及 `GameState` 开局 / 换天时名单确实跟着换。

---

## 12. 组队界面（M3 前置：候选人头像 + 简历联动）

> 这一节记的是 §4 里 `team_builder` 那三个空壳里**左半边**最先落地的内容：
> **今日出现的面试者，一人一个圆头像；鼠标移上去，右半边铺出他的简历；左键点一下标记录用，再点一下撤销。**

### 12.1 文件

| 文件 | 职责 |
| --- | --- |
| `scenes/day/team_builder/team_builder.gd` / `.tscn` | **组队容器**。只做接线：名单 → UI、悬停 → 简历、左键 → `GameState.current_team` |
| `scenes/day/team_builder/team_builder_ui.gd` / `.tscn` | UI 容器：`Header`（HIRED n / 名额）+ `Roster`（`GridContainer`，一格一条候选人） |
| `scenes/day/team_builder/candidate.gd` / `.tscn` | 单条候选人：`class_name CandidateEntry`，圆头像（`_draw()` 画底衬 + 黑圆边框）+ 名字；对外 `hovered` / `toggled` |
| `scripts/util/portrait_composer.gd` | `class_name PortraitComposer`：立绘**部件命名**的唯一出处 + 把部件拼成**圆形头像** |
| `scenes/day/interview/resume/resume.tscn` | **原样复用**：右半边那页简历就是面试那一页（§10.6） |

场景树（`team_builder.tscn`）：

```
TeamBuilder (Control) [team_builder.gd]
├─ ItvBkgPhd / TablePhd       背景、桌子
├─ TeamBuilderUI (1)          左半边：头像列表 + 表头
├─ Resume (2)                 右半边：resume.tscn 实例（默认 visible=false）
├─ Haohan (3)                 主角的手 = 光标，压在 UI 之上
├─ ColorNight                 夜晚色调（CanvasModulate，整块画布一起变色）
└─ Dialoguer
```

> `Haohan` 从「UI 之前」挪到了「UI 之后」：它是个跟着鼠标走的 1024×1024 手形贴图，
> 排在 UI 前面的话，悬停头像时手会被头像盖住 —— 这一条和 `interview.tscn` 的层序对齐（手在最上）。

### 12.2 数据怎么流到画面上

```
data/days/day_XX.tres
   └─ candidates ──► GameState.current_candidates        （本日过程量，§7 不进存档）
						└─ team_builder.gd
							 ├─ TeamBuilderUI.set_candidates()  → 一人一条 CandidateEntry
							 │     └─ CandidateEntry.set_candidate()
							 │          ├─ 头像 ← PortraitComposer.avatar_texture(candidate, 112)
							 │          └─ 名字 ← candidate.display_name
							 └─ TeamBuilderUI.set_hired_ids()   → 画「已录用」标记
```

- **名单就是「今日出现的面试者」**：和面试同一个来源（`GameState.current_candidates`）。
  左半边列的是当天**全部**出场者（不是只列通过者），玩家想改主意时还能把别人点进来；
  §12.7 的初始名单会把面试录用的人先标上。
- **右半边复用 `resume.tscn`，位置靠「同一个场景」而不是靠对齐代码**：`Resume` 是整屏 Control，
  纸面 `Paper` 用的是绝对偏移（624,62 ～ 980,542），所以把它实例化到组队场景里，
  位置与面试**逐像素相同**。`smoke_team_builder` 会把两边的 `Paper` 全局矩形拿来比，
  以后谁动了偏移都会当场红。
- 组队场景**一进来右半边是空的**（`Resume.visible = false`）：要求是「鼠标移上去才展示」。
  悬停过之后内容就留着不撤 —— 移开鼠标只是不再换人，不然读简历读到一半手一抖就白了。

### 12.3 交互与「录用」的真身

| 操作 | 结果 |
| --- | --- |
| 鼠标移上某条头像 | `CandidateEntry.hovered` → `TeamBuilderUI.candidate_hovered` → `Resume.set_candidate(这一位)` + `visible = true` |
| **左键**点某条头像 | `toggled` → 在 `GameState.current_team` 里**加上**这一位的 id |
| 再点一次同一条 | 已经在队里 → 从 `current_team` 里**去掉**（撤销），标记随之消失 |
| 右键 / 滚轮 / 中键 | 一概不响应（`_gui_input` 只认 `MOUSE_BUTTON_LEFT`） |
| 点简历词条 | 菜单里那一项是「**回忆**」：重播面试时问过的那一段（§10.7）。没问过的置灰 |
| 「组队完成」 | 超员 → **拦住**；刚好满 → 出发；没满 → 提醒一次、再点一次出发 |
| 表头 | `HIRED 已录用数 / 当日名额`，名额来自 `DayConfig.slots` |

- 「已录用」的**真身是 `GameState.current_team`**（§2：本日过程量，不入存档），
  条目上的 `hired` 只是显示状态，由 `TeamBuilderUI.set_hired_ids()` 同步下来。
  这样没有新增任何 GameState API，也没有把状态塞进 UI。
- **`GameState.roster`（全季已录用名单）不动**：那个由面试的判定（`issue_verdict` / `hire`）负责，
  组队阶段挑的是「今天这一队」。提交队伍（`team_submitted` → `BattleReport`）留到接战报时再做。
- 表头文案是英文（`HIRED`）：`assets/fonts` 还没接入中文字体，中文会变方块（§10.5），
  和简历页的 `RESUME ENTRIES` 一致。

### 12.7 初始名单：面试录用了谁，就先标上谁

一进组队，`_ready()` 里先播种再接线：

```gdscript
_seed_team_from_verdicts()   # GameState.current_team = GameState.get_passed_ids()
_wire_ui()                   # 结尾 _push_team_to_ui() 把队伍画到界面上
```

- **为什么**：面试时按下的那个「录用」就是玩家的第一次筛选，组队要做的是**在此基础上调整**，
  而不是让玩家凭记忆再点一遍。所以 `passed_ids` 直接变成开场队伍。
- **顺序不能反**：`_wire_ui()` 结尾才把队伍推给界面。先接线再播种，界面拿到的还是空名单 ——
  玩家会看到一个「明明录用了却没人被标上」的组队界面（这个坑 `smoke_team_builder` 抓过一次）。
- **已经有队伍就不覆盖**：换阶段回来 / F6 重进时不该把玩家刚调整好的名单冲掉。

### 12.8 超员：硬拦，不是提醒

`passed_ids` 可能**比当天名额多**（面试录用了 3 位，今天只能带 2 位）。这时开场就处于超员状态，
界面把他们全标上、其余条目锁住，玩家去掉几位才能出发 —— 该由玩家决定留下谁。

```gdscript
if TeamValidator.is_over(team, slots):   # size > slots，刚好满不算
	_cancel_incomplete_confirm()
	_play_dialogue("team_over")          # 播不出文案也**不放行**
	return
```

- 和「没满」那条路**性质不同**：「没满」是提醒一次、再点一次就走（玩家有权少带人）；
  「超员」是**硬拦** —— 多带的人没有名额，点多少次都出不去。
- `TeamValidator.is_over()` 和 `is_full()` 是两个判定：`size >= slots` 是满，`size > slots` 才是超。
  刚好满必须能出发，这是「满了就立刻走」那条路的前提。
- 文案 `team_over` 在 `data/dialogue.json` 里（和 `team_not_full` 同一处）。

> ⚠️ **数据现状**：`data/days/day_XX.tres` 里只有 day 01/02/04/06/08 填了 `slots`，
> day 03/05/07/09/10 **没填**（`slots = 0`）。按 `TeamValidator.has_quota()` 的约定，
> 名额为 0 = 「没有名额限制」，所以那 5 天既不会锁人、也不会触发超员拦截。
> 要按设计走，得把那 5 天的 `slots` 补上。

### 12.4 圆形头像是怎么拼的

立绘不是一整张图，而是「身体 + 眼睛 / 头发 / 嘴巴」或「身体 + 帽子」按同一个 300×300 的画布坐标
叠出来的（§11.2）。头像就是把这套部件**拼成一张图再裁成圆**：

1. `PortraitComposer.compose()`：按 `stems_for()` 的顺序把部件 `blend_rect` 到一张 300×300 的透明图上。
   **部件文件名与「哪个种族用哪几个部件」只有这一处**（`interviewee.gd` 也读它，不再各写一份）。
2. `framing_for_image()`：量出这张图的 alpha 包围盒，**自动**取一个居中、四周留 12% 余量的正方形取景框。
   取景是自动的而不是一组写死的常量 —— 矮人三顶帽子（宽檐 / 小圆帽 / 高帽）身量差一倍，
   以后换立绘、加种族也不用回来调数字。
3. `_frame()`：按「取景框 ∩ 部件画布」拷贝（框可以伸到画布外，越界处留透明），再缩到 `size × size`。
4. `_apply_circle_mask()`：圆外 alpha 清零，圆边留 1 像素渐变（不然锯齿很难看）。
5. 结果存进 `avatar_texture()` 的静态缓存（key = 配方 + 尺寸），悬停换人时不再重拼。

**黑圆边框是画出来的，不是贴图**：`CandidateEntry._draw()` 里
`draw_circle()` 垫一层浅色底衬（立绘是白底黑描边的纸片人，得有底才在夜晚色调下站得住），
再用 `draw_arc(..., RING_COLOR, RING_WIDTH)` 描一圈**纯黑**；「已录用」是黑圈**外面**再加一圈暖色，
不动黑圈本身。

> 实测数据（量 alpha 轮廓的临时探针，用完已删）：`hu / el` 整身占 y 17..300，
> `st` 三顶帽子分别让整身落在 y 170..300 / 220..300 / 16..300 —— 正因为跨度差这么多，
> 取景才做成自动的；这套数据现在由 §12.6 的「25 位候选人逐个体检」守着。

### 12.5 版面与「别踩 M0 占位 HUD」

- 头像列表在**左半边下半部**：`Header` 在 (24,306)，`Roster` 在 (24,344)，3 列，每条 120×148
  （头像直径 112 + 名字一行）。今日 2〜3 位时正好一行；多了自动换到第二行（两行放 6 条）。
- 往左下角挪的原因是 `day_loop` 的 **M0 占位 HUD 占着左上 303×297**（`layer = 10`，
  `MOUSE_FILTER_STOP`）：压在那里的话既看不见、也点不到。占位 HUD 删掉之后，这里可以再往上摆。
- 右半边的简历纸面在 x 624 起，两半不重叠。

### 12.6 自检

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_team_builder.tscn
```

82 项：左半边条数 = 今日名单人数、每条的候选人与名字来自数据、头像尺寸 = `AVATAR_SIZE`、
**圆外一个像素都没有 / 圆内有内容 / 填得够满 / 包围盒中心落在圆心**（±2px）、
悬停换人后右半边抬头与词条都跟着换、**组队页的 `Paper` 全局矩形与面试页逐像素相同**、
左键标记与撤销、右键无反应、表头计数、空名单不炸、
**面试录用的人一进组队就已经标好**（被拒的没有）、
**「回忆」的整条链路**（菜单文案是「回忆」、没问过的置灰且点了没反应、问过的广播
`resume_entry_recalled`、播出的行 = 当时那份 json + 最后那句自言自语）、
**超员点多少次都出不去而减到名额以内一下就走**、
**悬停样式只剩底色矩形、四边线宽合计为 0**，以及
**`data/candidates/` 里 25 位候选人逐个拼得出「有内容且居中」的头像**。
另外还比对了 `Interviewee` 与 `PortraitComposer` 取的是同一套部件图（防两边走偏）。
全绿退出码 0。

画布同样是塞进 1152×648 的 `SubViewport` 里测的（理由见 §10.6）。

---

## 13. 面试出场演出（走位 + 简历升降）

> 一位面试者从进画到离场，是有走位的：
> **从画面右边走进来（边走边上下晃）→ 站定 → 简历从画面下方升起 → ……看简历、追问、判定……
> → 判定之后向左走出去 → 他的简历往画面上方移走 → 下一位从右边走进来 → 下一位的简历从下方升起。**

### 13.1 为什么顺序是「依次」而不是「前后交错」

判定之后有两条独立的线要收：**人**（走出去 / 下一位走进来）和**纸**（移走 / 下一位的纸升起来）。
两者的先后本来有两种排法，现在固定成**依次**：

```
判定 ─→ ① 面试者向左走出画面
	   ─→ ② 他的简历往画面上方移走
	   ─→ ③ 下一位从右边走进来、站定
	   ─→ ④ 下一位的简历从下方升起
```

挑这条的理由是**出场规则对每一位一视同仁**：「站定之后简历才从下方升起」这条对第 1 位成立，
对第 2、3 位也必须成立 —— 换成「③④ 并行」的话，新简历会在人还没站稳时就开始往上爬，
同一个规则在一局里出现两种表现。代价是换人间隔约 2.2 秒，全部时长都在常量里，随时能调。

### 13.2 落点

| 文件 | 职责 |
| --- | --- |
| `scenes/day/interview/interview.gd` | **演出调度**：什么时候演哪一段、每段的顺序、演出期间的输入守卫（§13.4） |
| `scenes/day/interview/interviewee.gd` | 立绘**怎么走**：`walk_to()` 横向平移 + `bob_offset()` 上下晃动；`offscreen_left_x()` / `offscreen_right_x()` 现算画面外的起止点 |
| `scenes/day/interview/resume/resume.gd` | 简历**怎么滑**：`slide_to()` / `snap_slide()` / `travel_distance()`；动的是一整页（本节点） |

时长与振幅（都在上面这三个文件里，改演出节奏不用碰逻辑）：

| 常量 | 位置 | 现在 | 含义 |
| --- | --- | --- | --- |
| `WALK_IN_DURATION` | `interview.gd` | 0.85s | 从画面右边外面走到站定处 |
| `WALK_OUT_DURATION` | `interview.gd` | 0.65s | 判定之后向左走出画面 |
| `RESUME_IN_DURATION` | `interview.gd` | 0.40s | 简历从下方升到位 |
| `RESUME_OUT_DURATION` | `interview.gd` | 0.30s | 简历往上方移走 |
| `WALK_BOB_HZ` | `interviewee.gd` | 4.5 | 走路步频：每秒晃几下（**晃几下按时长算出来**，不是写死个数） |
| `WALK_BOB_PIXELS` | `interviewee.gd` | 9.0 | 上下晃动的振幅 |

- **晃动幅度是「峰值」不是「总行程」**：`bob_offset()` 是一条 `sin`，起止两端都归零，
  所以走动过程中纵向**永远围着站定高度来回**，不会一边走一边整体往上 / 往下飘 ——
  立绘和桌子的相对关系就是这么守住的。
- **步频而不是步数**：`walk_to()` 按 `WALK_BOB_HZ × 时长` 现算晃几下。
  写死个数的话，把 `WALK_*_DURATION` 调快一点，人就会抖得像在跑。
- **画面外的起止点是现算的**（`get_viewport_rect()` + 立绘半宽），不是写死 1152 / -225：
  自检会把场景塞进别的尺寸的 `SubViewport`，画布尺寸本来就该由 viewport 说了算。

### 13.3 两条实现纪律（都不是洁癖，是踩过的）

**① 演出用 Tween 串，不用协程 `await`。**
`day_loop` 换阶段时会 `queue_free()` 掉本场景（§10.5），而 `await` 一个**已被释放**的节点的信号
会让那个协程永远挂在那儿：不报错、不回收、也没有任何现象。Tween 是绑在各自节点上的，
节点一没它自己就跟着没了，一个都不会漏。

**② 顺序靠「等这一步动完」，不是「按固定时长往下排」。**
`_begin_sequence()` 收的是一列**返回 Tween 的步骤**（`_step_walk_in` / `_step_resume_rise` / …），
`_run_next_step()` 启动一步、然后等**那条 Tween 自己的 `finished`** 再开下一步。

> ⚠️ 曾经写成「一条总闸 Tween 按 `tween_interval(时长)` 往下排」，在自检里当场炸了：
> 总闸与子 Tween 是两条独立的 Tween，同一帧里谁先谁后本来就差一点点，
> 几步累积下来成了「人还在往左走（x 还有 473），纸已经开始往上升了」。
> 当时想用「每步后面加 0.06s 余量」糊过去 —— 一跑发现余量根本不够，因为偏差**不是一帧**。
> 现在这版没有余量常量：顺序就是动作本身的顺序，压根没有可偏差的东西。

> ⚠️ 顺带一条：`Tween.is_running()`（以及 `is_valid()`）在 Tween **跑完之后还会再真几帧**，
> 拿它当「这个动作做完了没有」会多算出好几帧。`Interviewee.is_walking()` / `Resume.is_sliding()`
> 只用来给「正在动」做展示，**判断「到位了没有」一律看位置**（见 §13.5）。

### 13.4 演出期间不收输入

| 层 | 落点 | 表现 |
| --- | --- | --- |
| UI 层 | `_apply_phase_visuals()` → `_apply_judge_button()` | 录用 / 拒绝按钮**只在「这个阶段不该判定」时消失**（非招人阶段 / 手册开着）。演出期间它们**照常画着**，只是压暗（`JUDGE_LOCKED_TINT`）+ `MOUSE_FILTER_IGNORE` —— 看得见、按不动 |
| 逻辑层 | `_judge()` | `_animating` 时直接 return（静默：按钮这时按不动，走到这里只可能是代码连点） |
| 逻辑层 | `_on_resume_entry_asked()` | `_animating` 时直接 return：这时那张纸正在画面外 / 正在滑，点到的词条马上会跟着纸跑掉 |

演出**开始与结束**都会重刷一次 `_apply_phase_visuals()` —— 按钮的压暗 / 摘鼠标跟着 `_animating` 走，
而 `_animating` 只在 `_begin_sequence()` / `_finish_sequence()` 两处变。

> ⚠️ **按钮的显隐不能跟 `_animating` 绑**：早先写的是 `judging = _is_judging_allowed() and not _animating`，
> 于是面试者走进来（约 1.3s）和判定之后换人（约 2.2s）的两段时间里，两个按钮凭空消失 ——
> 在玩家眼里那不是「现在不能按」，而是界面闪了一下。**演出期间要挡的是点击，不是按钮本身。**
>
> 另外这里用的是 `modulate` + `mouse_filter`，**不是 `disabled`**：`interview.tscn` 没给这两个
> `TextureButton` 填 `texture_disabled`，一旦 `disabled`，引擎什么都不画 —— 又变回「按钮消失」了。
> `disabled` 仍然归 `_set_scene_interaction_enabled()`（手册那条路）用，两者各管各的。
>
> 压暗用的是 **modulate 的 RGB（亮度）**，alpha 保持 1.0：按钮是不透明的手绘贴图，
> 半透明会让面试间的背景从按钮里透出来，既不像「不能按」，也看着像贴纸没贴牢。

### 13.5 收场与「跳过演出」

`skip_animation()` 立刻掐掉当前这段演出（自带 `is_animating()`），落到收场姿态。

**收场动作写成「把场面收成应该有的样子」，不是「接着往下做」** —— 它既在演出自然播完时调用，
也在被掐掉时调用，而掐掉的那一刻可能停在任何一个中间步骤上，所以每一步都必须幂等：

| 收场 | 场面 |
| --- | --- |
| `_stand_candidate_ready()` | 换下一位的数据 + 人站回站定处 + 纸滑回站定处（首次出场结束时同样走这里，是幂等的） |
| `_conclude_interview()` | 人停在画面左边外面 + 纸停在画面上方外面 + `phase_finished`（**最后一位判完才发**，见下） |

- **`phase_finished` 在走完之后才发**：最后一位按下判定后，先演完「走出去 + 简历移走」才交阶段，
  不然镜头会停在一个人站在画面正中的画面上。
- 跳过演出时**也必须显式摆出收场姿态**，不能靠「反正马上就切场景了」：半路掐掉时，
  不摆的话画面就停在半路上了。
- `_finish_sequence()` 会 `kill()` 掉当前那一步还在跑的 Tween：跳过演出时它可能才走到一半，
  留着就会在收场之后继续往前跑，把刚摆好的姿态又推歪。（`kill()` 不发 `finished`，
  所以不会把 `_run_next_step` 再叫起来。）

### 13.6 自检

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_interview_animation.tscn
```

53 项，跑的是**真的 `interview.tscn`**：逐帧采样立绘的 x / y 与简历的纵向偏移，
再按顺序验（只看首尾姿态是验不出「谁先谁后」的）：

- 画面外的起止点**真的在画面外**、简历行程够把**纸面**（62..542）整个推出画面；
- 挂上去那一帧就已经摆好位（纸不会先在原地闪一下）；
- 走进来是**单向**从右往左、**上下都晃到了**、且不越过配置的振幅、走完正好停在场景摆的那一处；
- 简历只在画面下方、**立绘站定之后**才开始升、升完正好回到站定处；
- 演出期间判定按钮**不消失**（照常画着、压暗且按不动），发来的判定被忽略；
- 判定之后**人先走光、纸才往上升**、下一位**从下方**进来、**简历移走之后**下一位才走进来；
- 换人换干净（立绘与简历都是名单第 2 位）、全程没有推进阶段；
- 跳过演出立刻收在站定姿态、最后一位**演出收场之后**才发 `phase_finished`。

全绿退出码 0。它把 `Engine.time_scale` 调到 2 倍省等待，收尾会拨回 1.0。

> 采样是**按条件等**（`while is_animating()`）而不是「等固定秒数」：演出按 delta 走，
> headless 下帧率又不受限，「等 1 秒」和「动画走完了没有」之间没有稳定换算关系。

> 因为加了这个演出，另外两个自检在实例化 `interview.tscn` 之后各加了一句 `skip_animation()`：
> `smoke_team_builder` 要比的是**站定之后**的纸面矩形（§12.2），`smoke_interview_ask`
> 则是要立刻开始点词条（演出期间追问是被**故意**挡住的）。
