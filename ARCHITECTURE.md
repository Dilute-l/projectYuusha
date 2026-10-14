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
│       ├─ portrait_composer.gd     立绘部件命名 + 拼装（面试立绘与组队头像框共用，见 §12）
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
│   │   │   └─ handbook.tscn           手册浮层（模态）：翻页浏览已解锁条目
│   │   ├─ team_builder/       team_builder.tscn（组队容器）
│   │   │   ├─ team_builder_ui.tscn     组队 UI：左边通过者头像列 + 右下角名额空位（§12）
│   │   │   ├─ candidate.tscn          左侧单条候选人：方头像框 + 滑出来的两个按钮（§12）
│   │   │   └─ framed_avatar.tscn      方头像框：底板 + 裁切过的整身立绘 + 方框（§12.4）
│   │   └─ battle_report.tscn          战报演出容器（车夫对话、逐条事件、分数）
│   ├─ ending/                 ending.tscn（收容结局相关子场景）
│   └─ common/                 dialogue.tscn / interview_background.tscn / haohan.tscn
│                                 / setting_page.tscn（设置页浮层，§14）
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
@export var wisdom: int = 0                     # 感知
@export var race: RaceDef                       # 种族（见 §3.3）
@export var job: JobDef                         # 职业（见 §3.3）
@export var gender: StringName = &"男"          # 性别：单个值
@export var age: int = 2                        # 年龄
@export var traits: Array[TraitDef] = []        # 特质（list，可含多项，也可为空）
@export var experience: Array[ResumeEntry] = [] # 个人履历与奖项（见 §3.2）
@export var skill: Array[ResumeEntry] = []      # 专长（见 §3.2）
@export_multiline var team_declaration: String  # 组队宣言：一整段自由文本，不挂追问
@export var portrait: Texture2D                 # 整张立绘（可选；当前用拼装立绘，见下）
@export var resume_stamp: Texture2D             # 简历上那枚印章；留空 = 不盖章（§10.6）

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
| `race` | 种族 | `RaceDef`，见 §3.3；`data/races/{human,elf,dwarf}.tres` |
| `job` | 职业 | `JobDef`，见 §3.3 |
| `gender` | 性别 | **单个 `StringName`**（`&"男"` / `&"女"`）。曾写成 `Array[StringName]`，那是笔误 —— 那会让所有候选人这一栏长得一模一样 |
| `age` | 年龄 | 简历上那一栏。旧的 `level` 字段已删除，「常理上限」现在由属性 + 职业 + 手册常识共同承担 |
| `traits` | 特质 | `Array[TraitDef]`，可含多项；相性计算输入（§6.4） |
| `experience` | 个人履历与奖项 | `Array[ResumeEntry]`，每条 = 一句描述 + 追问对话 json 的路径 |
| `skill` | 专长 | 同上。**与 `experience` 共用一套扁平序号**，见 §10.6 |
| `team_declaration` | 组队宣言 | **一整段自由文本**，原样铺在纸面右下；不挂追问（它是「他自己喊的口号」，不是「可被质疑的履历」） |
| `resume_stamp` | 简历上的印章 | 一张贴图同时决定**显不显示**与**用哪张**：留空 = 不盖章（§10.6） |
| `portrait_*` | 拼装立绘配方 | 种族 + 各部件差分编号；面试者的长相也是数据，不是代码里摇的（§10.7） |

> 真假不再由隐藏字段承载：玩家看到的 `strength / intelligence / wisdom / race / job / traits`
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
`strength / intelligence / wisdom / race / job / traits` 与手册常识自行判断。



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
| `day_loop.tscn` | **每日流程容器**，按 `DayPhase` 状态机切换子场景 | `day_phase_entered` |
| `interview.tscn` | 在day_loop下，用于收容所有与面试流程相关的细分场景，作为实际游戏过程中呈现出的面试场景 | `phase_finished` |
| `interview_ui.tscn` | 在 interview 下，用于展示面试中的 UI，包括暂停、设置按钮等系统向 UI 和候选人列表、今日事件等 | — |
| `interviewee.tscn` | 在 interview 下，管理面试者立绘、管理表情差分、对话框 | — |
| `resume.tscn` | 在 interview 下，候选者的完整简历：姓名 / 种族 / 职业 / 性别 / 年龄、三围属性（Status 区）、个人履历与奖项、专长、组队宣言 | — |
| `resume_token.tscn` | 在 resume 下，单条简历词条（复用控件）；点它弹出词条菜单 | `selected` |
| `resume_token_menu.tscn` | 在 resume 下，词条旁的小菜单（面试=「追问」/ 组队=「回忆」） | `ask_requested` |
| `handbook.tscn` | 在 interview 下，**模态**手册浮层：翻页浏览已解锁条目，开着时挡住本场景其它操作 | `closed` |
| `team_builder.tscn` | 在 day_loop 下，用于收容从通过者中挑满名额组队这一过程的相关场景 | `team_submitted` |
| `team_builder_ui.tscn` | 在 team_builder 下，用于展示组队过程中的 UI：**左半边今日通过者的头像列** + **右下角的名额空位**（§12） | `candidate_selected` / `candidate_approved` / `candidate_rejected` |
| `candidate.tscn` | 在 team_builder 下，左侧**单条**候选人：方头像框 + 两个从他身后滑出来的按钮（进队 / 不进队，§12） | `selected` / `approved` / `rejected` |
| `framed_avatar.tscn` | 在 team_builder 下，**方头像框**：底板 + 裁切过的整身立绘 + 方框（右下角的名额空位也用它，§12.4） | — |
| `battle_report.tscn` | 在 day_loop 下，用于收容下班马车上看战报演出，车夫对话，逐条事件播报，以及分数这一过程的场景 | `report_finished` |
| `ending.tscn` | 用于收容所有与结局场景相关的细分场景，十天后按总分与 flag 判定结局 | `restart_requested` |
| `dialogue.tscn` | 用于在多个场景下创建实例化的对话框 |  |
| `interview_background.tscn` | 用于在多个场景下实现背景相关动画 | 多种（动画种类） |
| `haohan.tscn` | 用于在剧情等地方创建实例化的主角的手 |  |
| `setting_page.tscn` | **设置页浮层**（§14）：常规只有左上角那颗设置按钮，点它或按 Esc 就把整页盖在最上层；页面上有「继续游戏」「退出游戏」两颗按钮，手（光标）也画在这一层里 | `opened` / `closed` |

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
`interview.gd` 管理单个候选人的问答循环：

1. 展示简历（`experience` 与 `skill` 逐条 `ResumeEntry.description`，见 §10.6）；
2. 玩家点击某一条追问，播出该条的 `ResumeEntry.ask_path` 指的那份 json；
   序号 → 文件这一层统一走 `Resume.ask_path_of(candidate, entry_index)`（**约定只写在那一处**）；
3. 玩家对照候选人的 `strength / intelligence / wisdom / race / job / traits` 与手册常识，
   自行判断这条描述与回答是否可信。

> **② 已实现**（`Interview` 阶段内）：点词条 → 菜单「追问」→ `resume.gd` 广播
> `EventBus.resume_entry_asked(candidate_id, entry_index)` → `interview.gd` 拿到
> `ask_path`，用 `typer.load_dialogue_from(path)` 装入那份 json，再 `dialoguer.play()`。
> 追问是临时对话，播完只收起对话框、**不推进阶段**。详见 §10.6。

### 6.3 手册（玩家能力锚点）
`handbook.tscn` 是 interview 里的**模态浮层**：点手册按钮打开，翻页浏览当前已解锁的条目，点 X 关闭。
**打开期间本场景其它操作一律停手**（按钮 disabled + 全屏输入挡板 + `_is_judging_allowed()` 返回 false 三层）。
`data/handbook/` 的条目承担两件事：
给出魔物弱点、同时给出**常识基线**（例如"初级剑士不可能单人讨伐食人魔"），让撒谎能被推理而不是靠猜。

**翻页按钮的可点区域比图形大**（`handbook.gd` 的 `PAGE_HITBOX_SIDE`）：`nextpage` / `lastpage`
两个 `TextureButton` 的 rect 都是整块 1152×648 画布（贴图就是整张图），判定完全由
`texture_click_mask` 决定。美术切好的那张 mask 精确到笔画本身（next 65×52、last 66×39），
鼠标偏几个像素就点不中，手感很差 —— 所以 `_ready()` 里把两张 mask 换成
**贴下角的 200×200 正方形**：图形一个字没动，变的只有「能点到哪儿」。

### 6.4 相性与组队
`synergy_calculator.gd` 读取 `TraitInteractionTable`，对队伍做两两配对：

- 配合（例：正义感 × 骑士精神）→ 战报触发"配合默契"正向事件；
- 冲突（例：自恋 × 独狼）→ 触发争吵负向事件，严重时影响当日成败。

### 6.5 战报生成
`combat_resolver.gd` 计算基础结果，`narrative_engine.gd` 用 `NarrativeRule` 把结果翻译成人话：

```gdscript
# data/narrative/claim_exposed.tres（示意）
when     = "member.strength + member.intelligence + member.wisdom < 30"
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
版面里没有任何候选人文案，内容全靠 `set_candidate()` 灌。

| 文件 | 职责 |
| --- | --- |
| `scenes/day/interview/resume/resume.gd` / `.tscn` | 简历整页 |
| `scenes/day/interview/resume/resume_token.gd` / `.tscn` | 单条词条，根节点是 `Button`（`class_name ResumeToken`），对外信号 `selected(entry_index)` |
| `scenes/day/interview/resume/resume_token_menu.gd` / `.tscn` | 词条旁的小菜单 |
| `ui/styles/resume_token_normal.tres` · `resume_token_hover.tres` | 词条的 normal / hover 两个 StyleBox |

#### 版面：一栏一个 Container

底纸是 `ResumePagePhd`（`Sprite2D`，`centered = false`，摆在 (8,9)）。
纸上叠的**不是**「一整段抬头」，而是**一栏一个节点**，由 `resume.gd::_fill_fields()` 逐栏填：

| 栏 | 节点 | 数据源 |
| --- | --- | --- |
| 姓名 | `NameContainer` | `display_name` |
| 种族 | `RaceContainer` | `race.display_name`（`RaceDef`） |
| 职业 | `ClassContainer` | `job.display_name`（`JobDef`） |
| 性别 | `GenderContainer` | `gender` |
| 年龄 | `AgeContainer` | `age` |
| 力量 / 智力 / 感知 | `Status/Str·Int·WisContainer` | `strength` / `intelligence` / `wisdom` |
| 组队宣言 | `DeclarationContainer` | `team_declaration` |
| 印章 | `ResumeStamp` | `resume_stamp`（见下） |

栏目标题（「姓名」「种族」…）是场景里另外一批 `*Label` 节点，**不是数据**。
任一字段为空就把那一栏清空 —— 不写「未知」这种兜底字，免得看不出来数据漏了。

> ⚠️ **这里没有「抬头」了**。早先的 `CandidateResource.resume_header` 是「上半部分整段字，
> 一个多行字符串说了算，`resume.gd` 一个字都不拼」。版面拆成一栏一格之后，它变成了重复的第二份文案，
> 而且没有任何节点能放它 —— 已删除。`team_declaration` 接替了「一整段自由文本」这个位置
> （但它只占右下角那一栏，不挂追问）。

#### 印章（`ResumeStamp`）：一个字段管「显不显示」和「用哪张」

纸面右上方盖着的那枚章由 **`CandidateResource.resume_stamp`（`Texture2D`）** 决定：

```gdscript
# data/candidates/c_0001.tres
resume_stamp = ExtResource("7_stamp")   # → assets/art/interview/resume/stamp/resume_stamp_real.png
# 没写这一行的候选人 → 不盖章
```

> **图案目录只有一个**：`assets/art/interview/resume/stamp/`，里面是
> `resume_stamp_<real|fakeN>.png`。文件名就是「这张章是真是假」的记号 ——
> `real` 是真章（「行」字印），`fake1..4` 是假章。**加一张新章 = 丢一个 .png 进去**，
> 然后按需要把它写进候选人的 `resume_stamp`（简历）或对话行的 `popup_stamp`（牌子）。
> 没有 `_phd` 后缀那种占位命名了。

`resume.gd::_apply_stamp()` 是它唯一的落点，规则只有一条：

| 数据 | 纸上 |
| --- | --- |
| 有图 | 换上这张图并显示 |
| 没图（null） | **不显示**，并且把节点上的 `texture` 一起清成空 |

- **为什么不留一个「要不要盖章」的 bool**：章就是「有没有图」这件事本身。
  两个字段必然会写出 `show = true` 却没图的组合，还得多一条兜底规则去猜谁说了算。
- **为什么「没图」还要把 `texture` 摘掉**：同一张简历会被反复喂不同的候选人（§11.2 换人时整体重刷）。
  只改 `visible` 的话，下一位没章的候选人纸上不画章、但节点里还留着上一位的图 ——
  哪天有人顺手 `visible = true`，就会盖出一个**张冠李戴**的章。空就是空。
- **位置 / 缩放 / `centered` 一律不碰**：那是版面，写在 `resume.tscn` 上；本脚本只换图与显隐。
  换一张尺寸不同的章不用改一行代码。
- **`ResumeStamp` 与 `ResumeStampPhd` 两个名字都认**（`STAMP_NODE_NAMES`）：节点改过一次名，
  而「节点名没对上」的后果是**印章静默消失**（`_apply_stamp` 找不到节点就直接返回），
  是最难查的一类 bug。两个名字都没有时 `_ready()` 会 `push_error`。
- 数据样本：`data/candidates/c_0001.tres` 是**唯一**填了章的候选人，其余 25 位都留空。

#### 牌子上的印章（`DialoguePopup`）：同一套图，但**由台词决定**

`Popup.tscn` 上还站着一枚章（`PopupStamp`），盖在**对话小牌子** `AwardPhd` 的位置上。
它和简历那枚**共用同一批图**，但「显不显示、盖哪张」的来源完全不同：

| | 简历那枚（`ResumeStamp`） | 牌子这枚（`PopupStamp`） |
| --- | --- | --- |
| 谁决定 | **候选人数据** `CandidateResource.resume_stamp` | **对话那一行** 的 `popup_stamp` 键 |
| 落点 | `resume.gd::_apply_stamp()` | `popup.gd::_apply_stamp()` |
| 粒度 | 一个人一枚（整局固定） | 一句台词一枚（同一人可换） |

```jsonc
// data/asks/c_0101_1.json —— 某一行
{ "speaker_name": "法斯特", "text": "我觉得我是",
  "popup": "AwardPhd",                      // 先亮牌子，印章才有地方盖
  "popup_stamp": "resume_stamp_real" }      // 再决定这一句盖哪张
```

`popup_stamp` 有**三个状态**，缺一个都表达不了完整的意图：

| 写法 | 这一句的章 |
| --- | --- |
| `"popup_stamp": "resume_stamp_fake1"` | 换上这张并显示（名字必须在 `DialoguePopup.STAMP_NAMES` 里） |
| `"popup_stamp": "none"` | **明确不盖**（`DialoguePopup.STAMP_NONE`） |
| 不写这个键 | **跟随上一句 / 场景默认**（`show_for()` 进门前先把状态记下来再放回去） |

- **为什么要 `"none"` 这个哨兵**：另外两档是「盖某张」和「沿用上一句」，
  没有它就写不出「这一段后面不盖章了」—— 只能靠「再盖一张透明图」这种歪招。
- **为什么白名单写死在代码里**（`STAMP_NAMES`）：路径写错在 Godot 里只会**静默少一张图**，
  数据里根本看不出来。白名单让错写在运行期当场 `push_warning`，顺带让两个生成器有确定的候选项。
  **加一张新章 = 丢 .png 进 `STAMP_DIR` + `STAMP_NAMES` 加一行 + 生成器那两处短名单各加一行。**
- **`popup_stamp` 只在同一行写了 `popup` 时才有意义**（牌子都没亮，章往哪儿盖）：
  `typer._normalize_line()` 两个键各自独立保留，但生成器在下拉框上就挡住了这种情况。
- **章槽挂在「牌子自己」底下**（`AwardPhd/PopupStamp`，**不是**牌子控件根节点下）：
  章的位置是写死的节点偏移（`(541,410)`，正落在牌面里），所以每块牌子各自带自己的章槽，
  跟着自己的版面走。**加一块新牌子 = 在它底下放一个 `PopupStamp` 子节点**，
  它就跟自己那块牌子的版面走了；新牌子不盖章就什么都不用放。
  共用一个根下的槽会踩两个坑（都是自检当场抓出来的）：
  ① 「这一句没写 `popup_stamp`」的**沿用**语义会跨牌子生效 —— 换牌子时把上一块的章
	 按旧位置盖到新牌子上；② 牌子收起来时章自己的 `visible` 还是 true（父节点盖着看不出来），
	 谁把牌子重新显示出来它就诈尸。所以 `hide_all()` 是**递归**的，换绑时还要把旧槽的
	 `texture` 一起摘干净（「空就是空」，和简历那枚同一条规矩）。
- **这块牌子没有章槽、数据却写了 `popup_stamp`** → `push_warning` 且不盖（不会去盖别人家的槽）。
- 位置 / 缩放 / `centered` 同样**不碰**（写在 `Popup.tscn` 上），换一张尺寸不同的章不用改代码。
- 自检见下面的 `smoke_dialogue_popup`。

#### 词条：两个列表共用一套「扁平序号」

`experience`（个人履历与奖项）与 `skill`（专长）各自铺进
`ExperienceContainer` / `SkillContainer`，但**序号是连着往下发的**：

```
experience[0] → 0      experience[1] → 1      skill[0] → 2   …
```

于是追问对话、以及「这一条问过没有」的记录（`GameState.record_entry_asked`）**两个列表走同一套流程**，
不需要给 skill 另开机制。序号 ↔ 数据的换算只有两个入口，都在 `resume.gd`：

```gdscript
static func entries_of(candidate) -> Array[ResumeEntry]      # 扁平条目表（experience 在前）
static func ask_path_of(candidate, entry_index) -> String    # 序号 → 追问 json 路径
```

`interview.gd`（真的去问）与 `team_builder.gd`（重播回忆）都调 `ask_path_of()` ——
**「序号怎么算」这条约定只写在那一处**，两边不必各自记住它。

#### 自检（`smoke_dialogue_popup`）

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_dialogue_popup.tscn
```

25 → 35 项，专门盯**牌子上的印章**这条链路（它属于「静默消失 / 静默串台」型功能：
名字写错、节点改名、图搬家、换了牌子，画面上只是多一枚或少一枚章，隔着对话框根本看不出来）：

- `STAMP_NAMES` 里每一张章都真的有对应贴图、真章假章都在名单里；
- 不在白名单里的名字**取不到图**（返回 null，绝不猜路径）；
- 牌子本体：章槽挂在牌子自己底下、根节点下**没有**共用槽、刚挂上去什么都不显示、
  还没显示任何牌子时**不预先绑槽**；
- `show_for` 三个状态各验一条：写了名字就盖那张、`"none"` 明确不盖（连图一起摘干净）、
  不写这个键就**沿用上一句**已经盖上的那张；
- 名字写错时**宁可空着也不拿上一张凑**；换一句不弹牌子 → 牌子与章一起收；
- **跨牌子不串台**（临时造一块 `NoticeBoardPhd`）：换到没有章槽的牌子时，
  上一块的章既不显示、`texture` 也被摘干净，写 `popup_stamp` 也不会盖到别人家的槽上；
  换回来时 `AwardPhd` 自己的槽照旧可用；
- 填字规则：牌子上的 `Name` 跟着候选人走，不喂候选人时不改字；
- **数据链路**：`data/asks/*.json` 里凡写了 `popup` 的行，`popup_stamp` 必须在白名单里
  —— 挡的是「生成器里选了个名字、Godot 侧还没加」这种两边不同步的错。

全绿退出码 0。

#### 状态区也是可追问的（序号 -1）

力量 / 智力 / 感知那一块是**一个 `Button`（`Status`）**，点它弹的是同一个菜单，
序号发 `Resume.STATUS_ENTRY_INDEX = -1`（一个不会和真条目撞号的虚拟条目）。
它的对话文件走约定路径 `data/asks/<candidate_id>_status.json`。
这样「属性值是不是吹的」也能被追问，而菜单 / 对话 / 记录三套机制一行都不用改。

#### 其余

- **条目数量自适应**：`_fill_list()` 先复用容器里预摆的词条实例，数据比预摆多就现场 `instantiate()`，
  少就把富余的 `visible = false`。所以「若干项」都不用回头改场景。
- **悬停高亮**只靠 Button 的 `theme_override_styles/hover`（一个淡黄色矩形、没有描边），
  normal 是一条细下划线。脚本里没有任何 `_on_mouse_entered`。
- **点击效果 = 在旁边弹出词条菜单**：`pressed` 与 `normal` 指向**同一个** `.tres`，
  `focus_mode = 0` 关掉焦点框；「选中」由 `resume.gd` 订阅 `selected` 后弹菜单来表达。
- **纸上的字全部来自数据**：`resume.gd` 里没有一句候选人文案，也没有「默认履历」这种兜底。
  唯一的数据入口是 `set_candidate(candidate)`；传 `null` → 整张纸清空。
- **滑动**：整页（本节点）上下滑，`travel_distance()` 取「画布高」与「底纸底边」里**更大的那个** ——
  底纸是整画布大的贴图（`position.y + 贴图高` 比画布还高一点点，实测 657 > 648），
  只滑一个画布高会剩一条边留在画面顶上。什么时候滑、滑到哪儿由 `interview.gd` 的演出调解决定（§13）。
- 纸上的文案是**中文**：字体和游戏别处是同一款（`assets/fonts/youaimoshouheiti-bold.ttf`），
  在**场景里**各处 `theme_override_fonts/font` —— `resume.gd` 一个字都没碰字体。

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

> 按钮文案「追问」是中文，字体和词条一样走 `theme_override_fonts/font = Silver.ttf`，
> 所以 `smoke_resume_menu` 查的是**按钮自己生效的那款字体**（`get_theme_font("font")`），
> 实测「追问」两个字都有字形。这里曾经查 `ThemeDB.fallback_font` —— 那是**引擎默认字体**
> 缺中文字形，和这枚按钮画成什么样无关，接上 Silver 后就成了假警报。

#### 自检

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_resume_menu.tscn
```

66 项：面板/按钮就位、**纸面内容确实来自 `data/candidates/*.tres`**（抬头原样铺数据里那一段字、
逐条词条正文来自 `description`）、给一份「不像字段拼出来」的抬头也照样原样显示、喂 `null` 时整页清空、
**印章跟着数据走**（空纸不盖章、有图就盖、没图就收、换人时图也摘干净、位置不被代码动过）、
点词条开菜单并记住序号、贴边 / 翻边 / 底部夹取、**改画布尺寸后自动重排**、点外面与 Esc 收起、
整块显隐不诈尸、「追问」广播 `resume_entry_asked` 并收起菜单。全绿退出码 0。

> 样本候选人按「第 1 天名单里**条目最多**的那位」挑，不是「名单第一位」：后面要用到第 3 条词条，
> 而名单里谁条目多完全由数据决定 —— 写死第一位的话，数据一改测试就红，而那不是它该管的事
> （数据覆盖度是 `smoke_m0` 的活，§11.4）。印章那几条则**显式按 id 取 `c_0001`**。

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
> | 候选人 `team_declaration` | `PLACEHOLDER DECLARATION 01` …（单行） |
> | 简历条目 | `PLACEHOLDER ENTRY / QUESTION / ANSWER 01-1`（`编号-条目号`） |
> | 职业 | `PLACEHOLDER JOB 01` … `03`（+ `PLACEHOLDER JOB DESC NN`） |
> | 特质 | `PLACEHOLDER TRAIT 01` … `10`（+ `PLACEHOLDER TRAIT DESC NN`） |
>
> **编号规则**：按文件名排序从 01 起编 —— 候选人 `c_0001.tres` → `01`；
> 职业按 `cleric` / `fighter` / `mage`；特质按字母序（`calm` → `01` … `lone_wolf` → `10`）。
> 编号只用来对号入座，本身不代表任何含义。
>
> **这次只动文案，没动结构**，下面这些原样保留（它们是**键和数值**，不是文案）：
> `id`（每日名单靠它引用）、`strength` / `intelligence` / `wisdom`、`race` / `job`、`gender` / `age`、
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
| `data/candidates/` | **一位面试者一个文件**（`c_0001.tres` … `c_0025.tres`，另有 `c_0101.tres`） | 姓名、种族（引用 `data/races/*.tres`）、职业（引用 `data/jobs/*.tres`）、性别、年龄、三项属性、特质（引用 `data/traits/*.tres`）、**个人履历与奖项**（`experience`）、**专长**（`skill`）、**组队宣言**（`team_declaration`）、**简历印章**（`resume_stamp`，§10.6）、**拼装立绘配方**；每条履历/专长 = 描述 + 追问 json 的路径（内联 `sub_resource`，跟着本人走） |
| `data/races/` | **一个种族一个文件**（`human` / `elf` / `dwarf`） | `RaceDef`：`id` / `display_name` / `description`。与立绘配方代号对应：`hu`→human、`el`→elf、`st`→dwarf |
| `data/asks/` | **一条追问一份 json**（`c_0001_1.json` … `c_0025_3.json`，外加每人的 `<id>_status.json`） | 一份就是「一段对话」，格式与 `data/dialogue.json` 里的一段完全一致，所以 `Typer` 那套逐字显示 / 点击推进照用 |
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
- **改组队宣言** → 同一个文件里的 `team_declaration`，多行文本框，写什么就显示什么。
  想让人物的自我介绍更有性格（甚至藏一个后面能被手册戳破的谎言），改这一栏就行。
- 换某天出场的人 / 调名额 → 点开 `data/days/day_XX.tres`，拖 `candidates` 数组。
- 加一位新面试者 → `data/candidates/` 下新建一份，再把它拖进某天的 `candidates`。
  嫌手搓 `.tres` 麻烦就用 **`tools/candidate_generator.html`**：单文件、零依赖，浏览器直接打开，
  填完点「全部写入 data/…」（Chromium）或逐个下载 —— 它一次吐出
  `data/candidates/<id>.tres` + 该人每条追问的 `data/asks/<id>_N.json` + `<id>_status.json`，
  序号约定与 `Resume.gd::ask_path_of()` 一致。**改数据模型就得同步改它**（例如 §10.6 的 `resume_stamp`）。
- 加一个新职业 / 新特质 → 在 `data/jobs/` / `data/traits/` 建资源，候选人引用它即可（`DataDB` 按目录自动归类）。

### 11.4 覆盖率自检

`smoke_m0` 第 `[3.1]` 节盯的就是这层数据：25 位候选人、10 天名单、每天 `slots` 不超过当天人数、
名单里的每个人都能在 `data/candidates/` 里查到、每条简历都齐了描述 + `ask_path` 两样、
**每位候选人的每条追问 json 都真的存在且能解析**（75 份，路径写错 / 文件忘提交 / json 写坏都在这里炸）、
**每位候选人都自带一段抬头文案**，以及 `GameState` 开局 / 换天时名单确实跟着换。

---

## 12. 组队界面（从通过者里挑满今天这一队）

> 这一节记的是 §4 里 `team_builder` 那三个场景落地后的样子：
> **左边是今天通过面试的那几个人，一人一个方头像框；左键点一位的头像，两个按钮从他身后
> 滑出来（进队向右 / 不进队向左），右半边铺出他的简历，右下角同时露出今天的名额空位；
> 进队的人底色转绿并占掉一个空格，不进队的人转红、不占格。**

### 12.1 文件

| 文件 | 职责 |
| --- | --- |
| `scenes/day/team_builder/team_builder.gd` / `.tscn` | **组队容器**。只做接线：通过者 → UI、点头像 → 简历、进队 / 不进队 → `GameState` |
| `scenes/day/team_builder/team_builder_ui.gd` / `.tscn` | UI 容器：`Roster`（左边头像列）+ `Slots`（右下角名额空位） |
| `scenes/day/team_builder/candidate.gd` / `.tscn` | 单条候选人：`class_name CandidateEntry`，方头像框 + 两个藏在它身后的按钮；对外 `selected` / `approved` / `rejected` |
| `scenes/day/team_builder/framed_avatar.gd` / `.tscn` | `class_name FramedAvatar`：**方头像框**（底板 + 裁切过的整身立绘 + 方框）；右下角的空位也用它 |
| `scripts/util/avatar_frame.gd` | `class_name AvatarFrame`：头像框三张美术的出处 + 取景窗 / 按钮美术的几何常量 |
| `scripts/util/portrait_composer.gd` | `class_name PortraitComposer`：立绘**部件命名**的唯一出处、整身立绘贴图（`portrait_texture`） |
| `scenes/day/interview/resume/resume.tscn` | **原样复用**：右半边那页简历就是面试那一页（§10.6） |

场景树（`team_builder.tscn`）：

```
TeamBuilder (Control) [team_builder.gd]
├─ ItvBkgPhd / TablePhd       背景、桌子
├─ TeamBuilderUI (1)          左半边：头像列（Roster）；右下角：名额空位（Slots）
├─ Resume (2)                 右半边：resume.tscn 实例（默认 visible=false）
├─ Confirm                     「组队完成」
├─ Haohan (3)                 主角的手 = 光标，压在 UI 之上
├─ ColorNight                 夜晚色调（CanvasModulate，整块画布一起变色）
└─ Dialoguer
```

> `Haohan` 排在 UI 之后：它是个跟着鼠标走的 1024×1024 手形贴图，排在 UI 前面的话
> 点头像时手会被头像盖住 —— 这一条和 `interview.tscn` 的层序对齐（手在最上）。

### 12.2 数据怎么流到画面上

```
data/days/day_XX.tres
   └─ candidates ──► GameState.current_candidates
						  └─ 面试判定 ──► GameState.passed_ids   （本日过程量，§7 不进存档）
											  └─ team_builder.gd
												   ├─ _passed_candidates()  只留今天通过了的那几位
												   ├─ TeamBuilderUI.set_candidates()
												   │     └─ CandidateEntry.set_candidate()
												   │          └─ 头像 ← FramedAvatar ← PortraitComposer.portrait_texture()
												   └─ TeamBuilderUI.set_decisions(进队, 不进队)
```

- **左边列的是「今天通过面试的人」**（`GameState.passed_ids` 的顺序），不是当天全部出场者：
  面试的「录用」就是玩家的第一次筛选，组队是在**通过者里**挑满今天这一队（§12.7）。
- **立绘不取景、不居中**：`PortraitComposer.portrait_texture()` 给的是整张立绘画布
  （`600×675`），头像框按 `AvatarFrame.PORTRAIT_SCALE` 折算进自己的坐标系后原位铺上去，
  露出来多少由取景窗决定（§12.4）。
- **右半边复用 `resume.tscn`，位置靠「同一个场景」而不是靠对齐代码**：纸面用的是绝对偏移，
  所以把它实例化到组队场景里，位置与面试**逐像素相同**。`smoke_team_builder` 会把两边的
  栏目矩形与底纸位置拿来比，以后谁动了偏移都会当场红。
- 组队场景**一进来右半边是空的**（`Resume.visible = false`）：要求是「点过头像才展示」。
  点过之后内容就留着不撤 —— 判定完把按钮收起来时简历不动，不然读到一半就白了。

### 12.3 交互与两种判定的真身

| 操作 | 结果 |
| --- | --- |
| **左键**点某位的头像 | `selected` → 两个按钮滑出来（approve 向右、reject 向左）+ 右半边铺他的简历 + 右下角露出名额空位 |
| 再点一次同一条 | 两个按钮收回去（简历不动）；点别人则把上一条收掉、这条打开 —— 同时只展开一条 |
| 点 approve | 这一位进 `GameState.current_team`：底色转绿 + 占掉右下角一个空格 |
| 点 reject | 这一位进 `GameState.rejected_ids`：底色转红 + 不占格；**已经在队里的先拿出来** |
| 右键 / 滚轮 / 中键 | 一概不响应（`_gui_input` 只认 `MOUSE_BUTTON_LEFT`） |
| 点简历词条 | 菜单里那一项是「**回忆**」：重播面试时问过的那一段（§10.7）。没问过的置灰 |
| 「组队完成」 | 超员 → **拦住**；刚好满 → 出发；没满 → 提醒一次、再点一次出发 |

- 「进队」的**真身是 `GameState.current_team`**，「不进队」的**真身是 `GameState.rejected_ids`**
  （§2：都是本日过程量，不入存档）。两个数组互斥，由 `team_builder.gd` 保证；
  条目上的 `decision`（`FramedAvatar.Tint`）只是显示状态，由 `set_decisions()` 同步下来。
- **能不能再收一位**是规则，问 `TeamValidator.can_add()`（§0：规则不在表现层）。
  名额满了就把还没进队那些条目的 approve 按钮置灰；**reject 永远可点** —— 撤销 / 否决
  从来不该被名额挡住，否则满员之后玩家就换不了人了。
- 右键不响应不是洁癖：误触一下就把人「进队 ↔ 不进队」翻一遍，比没反应难查得多。

> ⚠️ **两个按钮「看不见」和「点不到」是两件事，要一起对**：GUI 拾取是**从树尾往树头**找的，
> 而两个按钮排在头像**之前**（所以藏起来时被头像盖住）。收起来时若不把它们从鼠标拾取里摘掉
> （`mouse_filter = IGNORE`），玩家点头像那一下会打到那颗**看不见的按钮**上 —— 一点就把人进队了。
> 同一个道理，置灰的「进队」也要摘掉：按不动就别拦着，让这一下落到头像上（展开 / 收起照旧）。
> `CandidateEntry._apply_button_input()` 就是管这件事的，`smoke_team_builder` 两边都盯着。

### 12.4 方头像框是怎么叠的

头像框自己是**一套三张同坐标系的 300×300 图**（`AvatarFrame` 是它们的唯一出处）；
立绘是**另一套坐标系**（`PortraitComposer.CANVAS × CANVAS_H` = 600×675），
两者差一个 `AvatarFrame.PORTRAIT_SCALE = 0.6`（取 0.6 而不是刚好对折的 0.5：
取景窗是「头肩像」画幅，脸占窗口约 3/4 宽最像原来那版；0.5 会小一圈、0.75 起发梢就被裁到）：

| 层 | 美术 | 作用 |
| --- | --- | --- |
| `Background` | `avatar_frame_background_phd.png` | 底板，**头像的底色**就是它；进队染绿 / 不进队染红（`self_modulate`） |
| `Clip` → `Portrait` | `PortraitComposer.portrait_texture()` | 取景窗（`clip_contents`）+ 整身立绘，按 `PORTRAIT_SCALE` 折算后**原位**铺开 |
| `Frame` | `avatar_frame_phd.png` | 方框，压在最上 |

- **不需要自动居中**：立绘按自己的坐标系铺满整个头像框（腿、矮人的帽檐都还在），
  只有取景窗里那一块露出来 —— 人物在框里的位置只由**立绘本身**决定，
  所以整个控件里没有一句取景 / 居中的计算。
  （唯一的例外是**水平方向**：取景窗自己的中心在 x=153，而立绘画布的中心在 x=300，
  两个原点直接对齐会让人偏在窗口右侧 —— 所以横向按「画布中心 == 窗口中心」摆，
  见 `FramedAvatar._portrait_center_offset_x()`；纵向不动，脸在画布上的高低是各画各的。）
- **超出边框的部分自动截掉**是 `Clip.clip_contents` 干的：窗口摆在 `AvatarFrame.WINDOW`
  （方框内沿围出来的透明区，实测量出来的），立绘横向按上面的居中规则摆、
  纵向按 `-窗口原点` 垫进去；窗口外的像素一律不画。
- ⚠️ **两套画布尺寸必须显式换算**（`AvatarFrame.PORTRAIT_SCALE`）：立绘重画成 600×675
  之后，若不折算就按 1:1 铺进 300×300 的框里，取景窗只框得到画布左上角那一小块 ——
  脸和眼睛全在窗口外面，看上去就是「头像过小、只露出左上角」。自检盯着这个数。
- 立绘矩形用的拉伸是 `STRETCH_SCALE`（**铺满**算好的矩形），不是 `keep_aspect_centered`：
  后者会让贴图在矩形里居中留边，「画布原点 = 立绘矩形原点」这个前提就不成立了，
  `-窗口原点` 的垫法随之错位。
- 三层是**同一个坐标系**的，所以换尺寸只走 `FramedAvatar.set_pixel_size()`：
  控件边长换成 px，三层按 `px / 300` 一起缩放，立绘与窗口的相对位置不动。
- 右下角的名额空位**就是同一个 `FramedAvatar`**：`set_candidate(null)` 只留底板和方框
  （空位），填进去的人用同一套配色（绿）。

### 12.5 版面

- **左边头像列**：`ENTRY_LEFT = 116`、`ENTRY_TOP = 28`、行距 `176`，一条 160×160。
  三条正好排到 540，避开下面那颗「组队完成」（y 572 起）。
- **两个按钮展开后的横向跨度**：reject 左缘 34 ～ approve 右缘 358，全部落在左半边
  （简历纸从 x 579 起）—— 展开时不会压到右边的简历。
- **右下角的名额空位**：贴屏幕右下角（右缘 1152−24、下缘 648−2），一个 60px、间隔 10px。
  这个尺寸是被逼出来的：简历纸占 y 29〜585，纸下只剩 63px —— 空位必须整块躲在纸下缘之下
  （这一条由 `smoke_team_builder` 的版面自检守着）。
- 整套版面是照 **1152×648 的画布摆绝对偏移**的（这几个阶段场景的根 Control 都是 0 尺寸，
  和 `interview.tscn` 一致）。所以右下角的空位是用 `get_viewport_rect()` 算画布尺寸的，
  不是拿控件尺寸做锚定 —— 拿 0 尺寸的父控件做锚定会算到屏幕外面去。

### 12.6 自检

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_team_builder.tscn
```

125 项：左半边只列通过者（被否掉的不出现）、头像框三张美术的来源与取景窗几何、
**立绘按 `PORTRAIT_SCALE` 折算后铺进取景窗、且画布中心与窗口中心对齐（横向居中）**、
**头像框与空位确实按 `AVATAR_SIZE` / `SLOT_SIZE` 渲染**、
一进来右半边是空的、点头像才铺简历、**按钮的树序在头像之前**（藏起来时真被压住）、
**收起来时按钮矩形完全落在头像矩形内 / 展开后各留 14px 压着框边**、
**收起来时按钮不吃鼠标（否则一点头像就点到那颗看不见的按钮上）**、
approve 的绿底与 reject 的红底、进队的人占掉第几个空格、两种判定互斥（改主意的来回）、
右键无反应、**版面自检**（头像列位置、最右不压简历纸、空位贴右下角且在纸下缘之下）、
简历各栏与底纸和面试逐像素同位置、**「回忆」的整条链路**、
**超员点多少次都出不去而减到名额以内一下就走**、
**悬停样式只剩底色矩形、四边线宽合计为 0**，以及
**`data/candidates/` 里 25 位候选人逐个拼得出「有内容」的整身立绘**。
另外还比对了 `Interviewee` 与 `PortraitComposer` 取的是同一套部件图（防两边走偏）。
全绿退出码 0。

画布同样是塞进 1152×648 的 `SubViewport` 里测的（理由见 §10.6）。

### 12.7 开场谁都没被选中

一进组队，`current_team` 是空的：**面试的「录用」只是把候选池缩小到今天这几位，
不等于「已经进队」** —— 谁进队是玩家在这页一位一位按出来的。

- 换天 / 开新局时 `GameState` 会把 `current_team` / `rejected_ids` 一起清空（本日过程量）；
  换阶段回来 / F6 重进时它们还在，玩家刚挑好的队伍不会被冲掉。
- 通过者可能**比名额多**：`TeamValidator.can_add()` 会在名额满时挡住下一份 approve，
  界面上那颗按钮也会随之置灰（§12.3）。要换人得先 reject 掉一位。
- 「队伍没满」仍然只是提醒一次（再点一次出发）；「超员」才是硬拦（§12.8）。

### 12.8 超员：硬拦，不是提醒

> 原本超员来自「面试录用的比名额多，一进组队就全标上」；现在进队都走 `TeamValidator`，
> 正常玩不会超 —— 这条兜的是「队伍被别处写成了超员」（调试 / 脚本 / 以后改数据）。

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
> 名额为 0 = 「没有名额限制」，所以那 5 天既不摆右下角的空位、也不会锁人。
> 要按设计走，得把那 5 天的 `slots` 补上。

### 12.9 提醒对话的穿透模式（`Dialoguer.play(pass_through)`）

对话框默认**吃掉左键**（`dialoguer.gd` 的 `_input` 里 `set_input_as_handled()`）：对话开着时
点哪儿都只是把对话往下推，底下的按钮收不到 —— 这是「先看完这段话再说」的场合要的。

但有两种提醒恰恰相反：**它只是一句话，界面该照用**。

| 场合 | 调用 | 为什么要穿透 |
| --- | --- | --- |
| 主菜单「退出」确认（`main_menu.gd._on_exitgame_pressed`） | `dialoguer.play(true)` | 第二下点退出按钮时，同一次点击既把提醒推完、也照常触发按钮；玩家也可以直接改点「新游戏」反悔 |
| 队伍没满时的「确定要走吗」（`team_builder.gd._on_confirm_pressed`） | `_play_dialogue("team_not_full", true)` | 第二次点「组队完成」不必先点空处把对话收掉，那一下直接落到按钮上并出发 |

```gdscript
func play(pass_through: bool = false) -> void:
	_pass_through = pass_through          # 只对本次播放有效
	visible = true
	typer.start_dialogue()
```

- 实现上只是**不再**调 `set_input_as_handled()`。`_input` 本来就在 GUI 输入**之前**被调用，
  所以穿透时顺序是「先推进对话 → 按钮的 `pressed` 随后发」，同一次点击两边都响应。
- 模式是**每次调用现选**的，不写死在场景上：同一份 `dialoguer.tscn`，追问 / 阶段对话 / 提示板
  仍旧走默认的阻挡模式，一个字都不用改。
- **超员那条（`team_over`）故意不穿透**：它是硬拦（§12.8），提醒期间不该顺手点到别处。
- 播完 / 通话结束时 `_pass_through` 复位为 false，下次 `play()` 忘传参数也不会残留穿透。

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

---

## 14. 设置页（`setting_page.tscn`）

> 游戏里随时能叫出来的那一页：**平时画面上只多一颗小按钮，
> 点它或者按 Esc，一整页设置纸就盖在当前场景最上面**；
> 纸上现在是「继续游戏」和「退出游戏」两颗按钮，
> 而**跟着鼠标的那只手仍然画在这一页之上**（手是光标，被盖住就等于没光标）。

### 14.1 文件与挂载点

| 文件 | 职责 |
| --- | --- |
| `scenes/common/setting_page.gd` / `.tscn` | `class_name SettingPage`：**开关**（按钮 / Esc）、**整页盖上来**、**继续游戏 / 退出游戏**、**手（`haohan.tscn`）也在这一层** |
| `assets/art/setting/setting_button_phd.png` | 设置按钮，原生 50×50 |
| `assets/art/setting/setting_page_phd.png` | 设置整页，原生 1152×648（= 整块画布） |
| `scenes/day/day_loop.tscn` | 把 `SettingPage` **实例化在最后**（和 FlowHud 平级） |

场景树：

```
SettingPage (CanvasLayer, layer = 100) [setting_page.gd]
├─ Page (Control, 全屏 = 画布大小, mouse_filter = STOP)   ← 默认 visible = false
│   ├─ PagePhd (TextureRect)     setting_page_phd.png，铺满整块画布
│   ├─ ContinueButton (Button)   「继续游戏」，画布正中偏上
│   └─ ExitButton (Button)       「退出游戏」，画布正中
├─ SettingButton (TextureButton)   setting_button_phd.png，贴在画布左上角 (0,0)
├─ Haohan (haohan.tscn)            手（光标），z_index = 1 → 画在设置页**之上**
└─ Dialoguer                       退出确认那段提醒（和主菜单同一个 dialoguer.tscn，z_index = 2）
```

### 14.2 为什么必须是 CanvasLayer

「盖在当前场景之上（图层最高）」**不能靠树序**：`day_loop` 的阶段界面是普通 `Control`
（默认画布 layer 0），而占位 HUD 是 `CanvasLayer(layer 10)`；CanvasLayer 的绘制顺序
**只由 `layer` 决定**，跟它在树里排第几无关（§10.6 那条「FlowHud 留在 layer 10」是同一个道理）。

所以本浮层自己就是一层，`LAYER = 100` —— 比 FlowHud 的 10 大，就必然在最上面。
层号在 `_ready()` 里再赋一次（不是只在 `.tscn` 里填）：**「最高」这条由代码保证**，
别人手滑改了场景里的数字也不会把设置页压到 HUD 底下去。

**挡鼠标 = 挡住底下场景**：`Page` 铺满画布且 `mouse_filter = STOP`，于是页面上任何一处点击
都被它吃掉，穿不到下面的按钮上。**不需要**再去 `disabled` 底下的场景 —— 点不到就已经等于点不动。

### 14.2.1 手（光标）也要在设置页之上

手是光标，被设置页盖住就等于「没有光标」—— 所以 `haohan.tscn` **实例化在本层里**
（`SettingPage/Haohan`），而不是让底下那个场景的手露出来。

- **凭什么它在上面**：同一块画布里，绘制顺序只由 `z_index` 决定（其次才是树序）。
  `haohan.tscn` 的根节点自带 `z_index = 1`，`Page` 是 0 —— 手必然画在设置页之上，
  跟它在树里排第几无关。
- **底下那只手怎么办**：不用管。它在 layer 0，被本层整块盖住；而且它和本层这只手
  读的是**同一个鼠标位置**、用的是**同一张贴图**，所以看上去仍然只有「一只跟着鼠标的手」。
  好处是本层这只手**不依赖底下的场景有没有手**（`battle_report` / 阶段切换的空档都不会没光标）。
- **它和退出提醒的先后**：`Dialoguer` 的根节点是 `z_index = 2`，所以在它之上 ——
  和主菜单的退出确认是同一个观感（§12.9 那套）。想把手提到提醒之上，只要给
  `SettingPage/Haohan` 填一个 `z_index = 3`。

### 14.3 开与关是同一个开关

| 入口 | 行为 |
| --- | --- |
| 左键点设置按钮 | `toggle()` |
| 按 **Esc** | `toggle()` |

- **两个入口走同一个 `toggle()`**，所以「关着就开、开着就收」的手感必然一致。
- 设置按钮**一直画在 `Page` 之上**（它是 `Page` 的兄弟、且排在它后面），所以页面开着时那颗按钮
  仍然点得到、看得见。
- Esc 走 **`_unhandled_input`** 而不是 `_input`：场景里已经有控件在 `_input` 里处理 `ui_cancel`
  （简历词条菜单 `resume.gd`），它在该吃的时候会 `set_input_as_handled()` ——
  那一下是「收菜单」，不该被抢来开设置页。**设置页永远排在它们后面。**
- 页面的显隐**只**由 `open()` / `close()` 管，两个方法各自幂等，并对外发 `opened` / `closed`。

### 14.4 两颗按钮：继续游戏 / 退出游戏

| 按钮 | 位置 | 干什么 |
| --- | --- | --- |
| **继续游戏** | 退出按钮的**正上方**（同宽、左缘对齐、间隔 20px） | 就是 `close()` —— 收起设置页接着玩 |
| **退出游戏** | 画布正中 | 见下：第一下弹提醒，第二下才退出 |

两颗按钮都是同一套观感（`Silver.ttf` + 三个 `StyleBoxEmpty`，和主菜单那几个文字按钮一致），
都 `focus_mode = 0`：不然点过一次之后按空格 / 回车会把它再触发一遍。

> 「继续游戏」和 Esc、和再点一次设置按钮走的是**同一个 `close()`**（§14.3），
> 顺手也会把退出确认作废 —— 三条退路的行为完全一致。

### 14.4.1 退出按钮：与主菜单那颗**功能一样**（§12.9）

```gdscript
func _on_exit_pressed() -> void:
	if _exit_confirming:
		SceneRouter.quit_game()          # 第二下：真的退出
		return
	if not _dialoguer.typer.load_dialogue(EXIT_CONFIRM_DIALOGUE):
		return
	_exit_confirming = true
	_dialoguer.play(true)                # 第一下：弹提醒，走**穿透模式**
```

- 文案用的就是主菜单那段（`data/dialogue.json` 的 `test1`），一点新文案都没有。
- `play(true)`（穿透）的理由和主菜单完全一样：第二下点退出按钮时，同一次点击**既把提醒推完、
  也照常触发按钮**；玩家也可以完全不理会它。
- **反悔**：鼠标移出退出按钮、移出窗口、或者收掉设置页 —— 三种都会 `_cancel_exit_confirm()`，
  把「已确认」抹掉、把提醒收起来。所以不会出现「上次留下的确认 + 这次点一下 = 直接退出」。

> ⚠️ 与主菜单的一处**细微差别**（故意的）：`main_menu.gd` 是先把 `_exit_confirming = true`
> 再 `load_dialogue()`，文案读不出来就会留下一个「已经确认过」的状态。
> 这里把标志位放在**读盘成功之后** —— 文案读不出来时这一下就是什么都没发生，
> 而不是变成「一按就退」。正常路径下两者表现完全一致。

### 14.5 自检

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_setting_page.tscn
```

74 项：两张美术的来源与尺寸、**常规状态只有那颗按钮可见**、按钮贴在左上角且不缩放、
**层号压过 FlowHud 且是容器里最高的一层**、**手实例化在本层、可见、z_index 高于设置页**、
点按钮 / 按 Esc 都能开、**再点 / 再按一次都能收**、`ui_accept` 不会误开、
**整页铺满画布且 `MOUSE_FILTER_STOP`（底下的场景点不到）**、
按钮排在整页之后（真的压在页面上）、**继续游戏按钮在退出按钮正上方且两颗一样宽**、
**点「继续游戏」会收起设置页并作废退出确认**、退出按钮在画布正中、
**第一下只弹提醒不退出（播的就是 `data/dialogue.json` 里那一段，逐字比对）**、
移出按钮 / 移出窗口 / 收页面三种反悔都作废、
以及 **`day_loop.tscn` 里确实实例化了它、挂上去的层号是最高的一层、默认是收起的**。
全绿退出码 0。

> 「第二下真的退出」**故意不测**：那一下会 `get_tree().quit()`，把自检自己终结掉 ——
> 绿着退出，什么都验不到。它和第一下走的是同一个函数，与主菜单那颗按钮是同一条路。

> 画布同样塞进 1152×648 的 `SubViewport` 里测（理由见 §10.6）；`day_loop` 那几条是
> **真的把 `day_loop.tscn` 实例化出来**再查的，不是查 `.tscn` 文本。
