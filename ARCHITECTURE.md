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
@export var level: int = 1                      # 等级：**隐藏属性**，不上简历纸（见下）
@export var strength: int = 0                   # 力量：**简历上写的**（他自称的）
@export var intelligence: int = 0               # 智力：同上
@export var wisdom: int = 0                     # 感知：同上
@export var true_attributes: Dictionary = {}    # 实际属性：只写偏差项；没写 = 与简历一致（见下）
@export var race: RaceDef                       # 种族（见 §3.3）
@export var job: JobDef                         # 职业（见 §3.3）
@export var gender: StringName = &"男"          # 性别：单个值
@export var age: int = 2                        # 年龄
@export var traits: Array[TraitDef] = []        # 特质（list，可含多项，也可为空）
@export var experience: Array[ResumeEntry] = [] # 个人履历与奖项（见 §3.2）
@export var skill: Array[ResumeEntry] = []      # 专长（见 §3.2）
@export_multiline var team_declaration: String  # 组队宣言：一整段自由文本，不挂追问
@export var judgment: String                    # 战报评语：结算后呈现的那句「真相」
@export var fake_level: int = 0                 # 造假程度 0~3：**不上任何界面**，只给后续机制参考
@export var display_race: String = ""           # 简历上印的种族名；空 = 照 race.display_name
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
| `level` | 等级 | **隐藏属性：不上简历纸**（见下）。与职业共同构成「常理上限」，是手册常识那一侧的锚点；老 `.tres` 里没这一行 = 1 级 |
| `strength` / `intelligence` / `wisdom` | 力量 / 智力 / 感知 | **简历上写的那三个数** = 他自称的身板，玩家在纸上看到的就是它（见下） |
| `true_attributes` | 实际属性 | `{ "strength": int, "intelligence": int, "wisdom": int }`。**只写和简历不一样的那几项**；空 = 实际就是简历值 |
| `race` | 种族 | `RaceDef`，见 §3.3；`data/races/{human,elf,dwarf}.tres` |
| `job` | 职业 | `JobDef`，见 §3.3 |
| `gender` | 性别 | **单个 `StringName`**（`&"男"` / `&"女"`）。曾写成 `Array[StringName]`，那是笔误 —— 那会让所有候选人这一栏长得一模一样 |
| `age` | 年龄 | 简历上那一栏。旧的 `level` 字段曾随「属性承担常理上限」一并删除，现在以**隐藏属性**的身份回来了（见上） |
| `traits` | 特质 | `Array[TraitDef]`，可含多项；相性计算输入（§6.4） |
| `experience` | 个人履历与奖项 | `Array[ResumeEntry]`，每条 = 一句描述 + 追问对话 json 的路径 |
| `skill` | 专长 | 同上。**与 `experience` 共用一套扁平序号**，见 §10.6 |
| `team_declaration` | 组队宣言 | **一整段自由文本**，原样铺在纸面右下；不挂追问（它是「他自己喊的口号」，不是「可被质疑的履历」） |
| `judgment` | 战报评语 | 结算之后战报上呈现的那句「真相」；和简历上的自述是**两回事** |
| `fake_level` | 造假程度 | `0`~`3`（0 = 没造假）。**不上任何界面，当前没有任何代码读它** —— 留着给以后的机制（风险 / 举报 / 派系反应）当参考。⚠️ 和 `traits` 里的 `fake0`~`fake3` **不同源**：那个参与相性计算，这个不参与；老 `.tres` 没这一行 = 0 |
| `display_race` | 简历上印的种族名 | 非空就替换纸面那一栏（例如 `race` 是 `elf`，纸面印「仙灵」）。**只换显示**：相性 / 叙事规则 / `combat_resolver.gd::_is_race()` 读的仍然是 `race`；立绘另看 `portrait_race`。取值走 `CandidateResource.shown_race_name()`，别处别自己拼 |
| `resume_stamp` | 简历上的印章 | 一张贴图同时决定**显不显示**与**用哪张**：留空 = 不盖章（§10.6） |
| `portrait_*` | 拼装立绘配方 | 种族 + 各部件差分编号；面试者的长相也是数据，不是代码里摇的（§10.7） |

#### 属性：纸上写的那三个数 vs 实际的那三个数

**同一项属性有两个数**，`true_attributes` 就是它们的差：

| | 落在哪 | 谁读它 | 玩家看得到吗 |
| --- | --- | --- | --- |
| **简历值** | `strength` / `intelligence` / `wisdom` | `resume.gd::_fill_fields()`（纸面那一栏） | **看得到** —— 他自称的 |
| **实际值** | `true_attributes` | `combat_resolver.gd::powerCaculation()`（结算） | 看不到，只能靠追问 + 手册常识猜 |

规则三条，**全在 `CandidateResource` 那几个取值助手里**：

```gdscript
@export var true_attributes: Dictionary = {}   # { "strength": 4, "wisdom": 12 }

candidate.claimed_attribute(&"strength")   # 20 → 纸面上那个数
candidate.true_strength()                  #  4 → 真正进结算的那个数
```

- **没写 = 一样**：`true_attributes` 里没有那一项（或整个字典是空的），实际值就是简历值 ——
  所以现有 `data/candidates/*.tres` **一行都不用改**，老格式天然就是「谁都没吹牛」。
- **只写偏差项**：只在力量上吹了牛就写 `{ "strength": 4 }`，另两项照简历走。
  `.tres` 里**没吹牛时连 `true_attributes` 这一行都不写**（默认值就是 `{}`，和 `resume_stamp` 同一条规矩）。
- **取值只走那几个助手**：`true_attribute(key)` / `true_strength()` / `true_intelligence()` /
  `true_wisdom()`（键 = 上面那三个字段名，`ATTRIBUTE_KEYS` 列全了）。
  别处一律不许自己 `true_attributes.get(...)` —— 兜底散到各处，改规则时必然漏掉几处。
  不是数字的值一律**退回简历值**并告警，绝不拿一个莫名其妙的数去结算。

> **这里没有「说谎」这件事**：本字段只保证「两个数都拿得到」。谁真谁假由玩法判断
> （追问、手册、常理），谎言处罚按 §6.6 的公式算 —— 那是 `combat_resolver` / `ending_resolver` 的活。
>
> **为什么不用隐藏字段**：早先的 `HiddenProfile`（§3.3 尾注）是把「真相」整套藏在一份平行资源里，
> 于是每个字段都要维护两份、还得记住哪一份是真的。现在只有**一个偏差字典**，
> 没有偏差的人连字段都不存在 —— 旧机制就是这么烂掉的。

> **等级（`level`）为什么不在上面这张表里**：它也是「属性」，但它是**隐藏属性**（§3.1 字段表）——
> 简历纸上根本没有它那一栏，于是不存在「纸上写的 vs 实际有的」这一对，`claimed_*` 那一半无从谈起。
> 它就是一个普通字段，读它的人直接写 `member.level`（叙事规则的条件里就是这么用的）。
> **别把它塞进 `true_attributes`**：那是个「偏差字典」，而它无偏可偏。
> 这也和上面「为什么不用隐藏字段」不矛盾 —— 那条反对的是「把整套真相复制一份」，
> 而不是「某一个字段本来就不给玩家看」。

#### 自检（`smoke_true_attributes`）

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_true_attributes.tscn
```

34 项，盯五件事：**老格式兼容**（`data/candidates/` 里没写 `true_attributes` 的每一位，
三项实际值都必须等于简历值 —— 判据是「那一行没写」，不是「不许有人吹牛」，
所以以后真给某位候选人填上偏差，这条不会误红）、**只写一项**（另两项照简历走）、
**两头各自读对**（把真 `resume.tscn` 实例化出来验纸面上是简历值、不是实际值；
`CombatResolver.powerCaculation()` 验结算按实际值算分**并乘等级** ——
三个职业分支都验，一级的老数据分数一点没变）、
**工具与引擎的格式契约**（`candidate_generator.html` 写出去的那行字典字面量，
交给 `str_to_var()` 真解析一遍）、**隐藏属性别掺和**（`level` 不在 `ATTRIBUTE_KEYS` 里 ——
它不上纸，没有「简历值」那一半）。全绿退出码 0。

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
`strength / intelligence / wisdom / race / job / traits` 与手册常识自行判断
（**等级不在这串里**：它是隐藏属性，玩家看不到，只能靠追问与常理去估 —— §3.1）。



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
   自行判断这条描述与回答是否可信。（**等级是隐藏属性**，不在这串里 —— §3.1。）

> **② 已实现**（`Interview` 阶段内）：点词条 → 菜单「追问」→ `resume.gd` 广播
> `EventBus.resume_entry_asked(candidate_id, entry_index)` → `interview.gd` 拿到
> `ask_path`，用 `typer.load_dialogue_from(path)` 装入那份 json，再 `dialoguer.play()`。
> 追问是临时对话，播完只收起对话框、**不推进阶段**。详见 §10.6。
> 这条追问**没有内容**时（没配 `ask_path` / 文件不在 / json 里一句台词都没有）不播空白框，
> 改播 `data/dialogue.json` 的 `ask_missing` 段（「面试官：这个地方好像没有什么好问的……」）。
> 详见 §10.7 的「追问没有内容时播什么」。

### 6.3 手册（玩家能力锚点）
`handbook.tscn` 是 interview 里的**模态浮层**：点手册按钮打开，翻页浏览当前已解锁的条目，点 X 关闭。
**打开期间本场景其它操作一律停手**（按钮 disabled + 全屏输入挡板 + `_is_judging_allowed()` 返回 false 三层）。
`data/handbook/` 的条目承担两件事：
给出魔物弱点、同时给出**常识基线**（例如"初级剑士不可能单人讨伐食人魔"），让撒谎能被推理而不是靠猜。

#### 每次都从封面（`stamp`）页开始翻

入口只有一个：`Handbook.open()` → `open_entry(COVER_ENTRY_ID = &"stamp")`。

- `stamp` 是一条**普通条目**（`data/handbook/stamp.tres`），内容就是那张手绘的
  「如何识别印章」—— 讲真章长什么样、哪几种是假的。它 **`unlock_condition` 为空 = 一开始就有**。
- 它是**恒定的第 0 页**：页序按「条件最早成立的天数 → id 字典序」排，唯一无条件的条目必然排最前
  （`stamp` 在 id 字典序里也靠前，两条依据同向）。**「每次从封面开始」就是靠这个前提成立的** ——
  哪天给封面加了 `unlock_condition`，它会先被 `smoke_handbook` 拦住。
- 关掉再打开**不记住上次翻到哪**，仍回封面（`open()` 每次都重新组页 + 从第 0 页铺）。
- `open_entry(entry_id)` 仍然保留「直接翻到某一条」的能力（目前没人用，留给以后的关键词检索 /
  图鉴跳页）；传进去的 id 不存在或还没解锁时**安静退回第一页**（= 封面）。
- ⚠️ **不要再在调用方传起始页**：早先 `interview.gd` 里有个 `HANDBOOK_PLACEHOLDER_ID = &"slime"`，
  于是每次打开都跳到史莱姆那页。现在那条常量已删除，起始页的约定只收在 `Handbook.open()` 一处。

**页序 = 解锁账本的顺序**（`RunState.handbook_unlocked` 这个有序数组，页码就是下标）：
`GameState.record_handbook_unlocks()` 把新满足条件的条目按「条件最早成立的天数 → id 字典序」补登，
新解锁的排在最后一页；**登记即既成事实**，条件日后变假也不移除、不重排。
注意排序键是 `id`（`ghost`/`goblin`…）而不是中文 `title` —— 同一天解锁的条目，顺序由 id 决定。
（旧存档里已登记的条目保持原位，改 id 只影响新开局。）

**版面**：`HandbookTitle`（48 号）压在 `HandbookContent`（32 号）正上方，两者都靠右半页的
白色书写区（x 557 起）。字号 / 颜色是版面，写在 `handbook.tscn` 的 Theme Overrides 上；
**字体**则在代码里挂（`handbook.gd` 的 `CONTENT_FONT_PATH`）—— Theme Overrides 表达不了「换字体」，
而引擎默认字体没有中文字形，标题和正文都会整条消失。

**翻页按钮的可点区域比图形大**（`handbook.gd` 的 `PAGE_HITBOX_SIDE`）：`nextpage` / `lastpage`
两个 `TextureButton` 的 rect 都是整块 1152×648 画布（贴图就是整张图），判定完全由
`texture_click_mask` 决定。美术切好的那张 mask 精确到笔画本身（next 65×52、last 66×39），
鼠标偏几个像素就点不中，手感很差 —— 所以 `_ready()` 里把两张 mask 换成
**贴下角的 200×200 正方形**：图形一个字没动，变的只有「能点到哪儿」。

#### 自检（`smoke_handbook`）

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_handbook.tscn
```

19 → 22 项，钉住「每次从封面开始」这条约定和它成立的前提：

- 封面条目存在、**无条件**、**排在账本第一位**（这三条是「封面恒为第 0 页」的依据）；
- `open()` 打开后停在 `stamp` 页；往后翻一页再 `close()` → 重新 `open()` **仍回封面**
  （证明不记住上次翻到哪）；
- 可翻页数 = 账本条数；
- `open_entry(id)` 仍能直接跳页；传不存在的 id **安静退回第一页**（= 封面），不报错；
- 边界按钮：封面是第一页 → 没有「上一页」；
- **集成**：真的实例化 `interview.tscn`、拨到 INTERVIEW、`skip_animation()` 之后
  点手册按钮 → 停在封面。这条盯的是**调用方**（光测 `Handbook.open()` 拦不住
  「调用方自己传了个 id 进去」那种回归，`HANDBOOK_PLACEHOLDER_ID` 就是这么来的）。

全绿退出码 0。

### 6.4 相性与组队
`synergy_calculator.gd` 读取 `TraitInteractionTable`，对队伍做两两配对：

- 配合（例：正义感 × 骑士精神）→ 战报触发"配合默契"正向事件；
- 冲突（例：自恋 × 独狼）→ 触发争吵负向事件，严重时影响当日成败。

### 6.5 战报生成
`combat_resolver.gd` 计算基础结果，`narrative_engine.gd` 用 `NarrativeRule` 把结果翻译成人话：

**战力怎么算**（`combat_resolver.gd`，纯静态、不碰节点）：

```
个人战力 = 主属性 × 等级 × 10     主属性 = 职业对应的那一项（剑士→力量 / 法师→智力 / 牧师→感知）
								 等级   = CandidateResource.level（隐藏属性，见 §3.1）
								 属性读实际值（true_strength() 那一组），不是简历上写的那个数
队伍战力 = Σ 个人战力             逐个相加，暂无相性 / 羁绊加成
```

> 就只有这两条：`breakdown` 里 `synergy` / `lie_penalty` / `event_bonus` / `luck` 目前都还是 0 占位（§6.6）。
> 个人的扩展点在 `powerCaculation()`（特质之类加在这里），队伍的扩展点在 `finalPowerCaculation()`（羁绊之类）。
> 等级是隐藏属性，所以「简历吹得漂亮、人其实只有一级」的分数会当场掉下来 —— 玩家看不见等级，只能靠追问与常识估。

```gdscript
# data/narrative/claim_exposed.tres（示意）
# ⚠️ 读的是**实际属性**（true_* 那一组，§3.1）：这句说的是「他真身板不行」，
#    拿简历上吹出来的数去比就永远不成立。
when     = "member.true_strength() + member.true_intelligence() + member.true_wisdom() < 30"
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

路径：`user://saves/slot_{n}.json`，另存一份 `user://saves/auto.json` 用于**每天开始**的自动存档。

玩家签的字也在这里（§16）。平时没有这一节，签过才有：

```jsonc
"signatures": {
  "contract.day1": {
	"canvas": [270, 160],                        // 录制时画布多大，回放时等比换算
	"strokes": [
	  { "p": [0.31,0.42, 0.32,0.44, 0.35,0.47],  // 归一化坐标，扁平存放（不存像素）
		"t": [0, 40, 80],                        // 本笔内的相对毫秒
		"g": 0 }                                 // 距上一笔结束停了多久（一笔画恒为 0）
	]
  }
}
```


- **存档目录在 `user://` 下**（Windows：`%APPDATA%\Godot\app_userdata\Yuusha\saves`），
  **不在 `res://` 里**：导出之后 `res://` 是只读的，往那儿写迟早写不进去。
  所以 `.gitignore` 里那条 `saves/` 平时是空转的，它兜的是「user 目录被指进项目里」
  （自检就是这么干的，见 §15.4）与调试时手动拷回来的那几份。
- **这个 JSON 不裁剪**：用户要的是「过去几天的分数 + 今天的天数」，而存档里
  本来就还有录用名单 / flag / 手册解锁 / 阶段 —— 它们都是「接着玩」必需的（§10.3：
  只有 `run_state` 进档，本日过程量靠种子重放）。**加字段就往 `RunState` 上加**，
  `version` 是给读档时的兼容判断用的（`from_dict()` 缺字段一律取默认值）。
- 谁在什么时候写：见 §15.1；怎么读回来接着玩：见 §15.2。

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
| `SaveService` | `autosave()` / `load_auto()`、`save_to_slot(n)` / `load_from_slot(n)`、`latest_save()` / `load_latest()`、`has_any_save()` / `has_slot(n)` / `delete_slot(n)` / `list_slots()` / `peek(path)`；`to_dict(RunState)` / `from_dict(Dictionary)` |
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
| `scenes/menu/main_menu.tscn` | `main_menu.gd` | 主菜单。Startgame → `GameState.start_new_run()` + `SceneRouter.goto_scene("day_loop")`；Continuegame → `SaveService.load_latest()` + 同一个跳转（没存档时按钮是灰的，§15.2）；Exitgame 二次点击确认退出；SealButton 二次点击重看开场剧情 |
| `scenes/day/day_loop.tscn` | `day_loop.gd` | 每日流程容器：订阅 `day_phase_changed` 换阶段子场景；`advance()` 向 `DayDirector` 问下一步；进入每天时自动存档 |
| `scenes/ending/ending.tscn` | `ending.gd` | 十天的落点：播 `Ending_Good`（念总分）+ 自动回主菜单，对外发 `restart_requested` |
| `scenes/boot/boot.tscn` | `boot.gd` | **项目启动场景**（`application/run/main_scene`）：DataDB 兜底检查 → 第一次启动先切 `opening`、之后直接切 `main_menu`（规则见 `scripts/core/flow/opening_flow.gd`） |
| `scenes/opening/opening.tscn` | `opening.gd` | 开场剧情：播 `opening` → 播完自动回主菜单。第一次启动由 boot 切进来，之后从主菜单火漆按钮重看 |
| `scenes/ending/true_ending.tscn` | `true_ending.gd` | 真结局：主菜单标题按钮解锁后按下进入，播 `Ending_True` 后回主菜单（解锁条件见 `scripts/core/flow/ending_unlock.gd`） |
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
| `ui/styles/resume_token_normal.tres` | 词条的 normal：无底色 + 一条下划线 |
| `ui/styles/hover_gray.tres` | **全游戏共用的悬停高亮**（灰色圆角矩形）—— 简历 / 战报 / 设置三处都引它，见下 |

#### 悬停高亮：全游戏只有一款（`ui/styles/hover_gray.tres`）

**鼠标移到哪一栏，哪一栏就压一块半透明灰**，四个界面共用同一个 `.tres`：

| 界面 | 会亮的栏 |
| --- | --- |
| 简历（本节） | 力量 / 智力 / 感知（`Status`）、个人履历与奖项的词条、专长的词条、词条菜单里的「追问」 |
| 战报（§4 `battle_report.tscn`） | 「确认」 |
| 设置（§14） | 「继续游戏」「退出游戏」 |
| 手册（§6.3 `handbook.tscn`） | 右上角的退出键（`quit`） |

- **颜色**：`Color(0.225, 0.225, 0.225, 0.6)` + 圆角 3，不描边。
  取值就是把**属性值栏当年那款**抄了下来 —— 那会儿 `Status` 没写 hover 覆盖，走的是引擎默认主题的
  Button hover；而词条用的是自己那份**暖黄**，于是同一张纸上两块高亮颜色不一样，三处观感也不统一。
  现在它成了显式资源，另外两个界面引同一份。
- **只有 hover 有底色**：normal 一律是空的（`StyleBoxEmpty`，或 `draw_center = false`）。
  进界面就一片灰的话，那就不叫高亮了 —— 自检专门盯这一条。
- **内边距（10 / 7）故意与 `resume_token_normal` 一模一样**：词条高度是 StyleBox 的
  content margin 撑出来的，hover 那一帧换成别的内边距，整栏会在鼠标底下跳一下。
  其它几处按钮都是写死的尺寸，不受影响（StyleBox 画的是整个控件矩形，内边距只管内容排版）。
- **改颜色只改这一个文件**：四个场景各写一行 `theme_override_styles/hover = ExtResource(...)` 引它。
  ⚠️ 在编辑器里点某个节点的那一栏，Godot 会**就地烘一个 `sub_resource`** 出来 —— 当时颜色还对，
  但从此那个界面就脱钩了。所以自检查的是「**还引着同一个资源吗**」，不是「颜色碰巧一样」。
- ⚠️ **只有 `Button` 画得出这个高亮**：手册右上角那颗退出键原来是 `TextureButton`，
  而 `TextureButton` **根本没有 hover 样式**（默认主题里 `has_stylebox("hover", "TextureButton")`
  是 `false`）—— 它只有一整套贴图，`theme_override_styles/hover` 挂上去一点用都没有。
  想和别处一样，只能把节点换成 `Button`（高亮由它画），**叉的贴图交给它底下的
  `QuitIcon`（`TextureRect`）画** —— 父节点先画、子节点后画，叉正好压在高亮之上；
  `QuitIcon` 必须 `mouse_filter = IGNORE`，否则它会把退出键的点击吞掉。
  顺带把那个 `scale = 0.48` 去掉了：缩放过的 `Control` 尺寸与命中区很容易对不上，
  现在控件矩形（62×62）就是叉的可视范围 —— 与改之前实测的 61.44 一样大，
  高亮框也正好落在这一块（自检盯的就是这几条）。

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_hover_gray.tscn
```

24 项：样式本身（颜色 / 圆角 / 不描边 / 内边距与词条 normal 一致）＋ 上表每一栏都引着同一份、
且 normal 不画底色（手册那两栏还验了节点类型与 `QuitIcon` 不吃鼠标）。全绿退出码 0。

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
| 个人履历与奖项 | `ExperienceScroll/ExperienceContainer`（`ScrollContainer` → `VBoxContainer`） | `experience`，每条约一个 `ResumeToken` |
| 专长 | `SkillScroll/SkillContainer`（`ScrollContainer` → `VBoxContainer`） | `skill`，每条约一个 `ResumeToken` |
| 组队宣言 | `DeclarationScroll/DeclarationContainer` | `team_declaration` |
| 印章 | `ResumeStamp` | `resume_stamp`（见下） |

栏目标题（「姓名」「种族」…）是场景里另外一批 `*Label` 节点，**不是数据**。
任一字段为空就把那一栏清空 —— 不写「未知」这种兜底字，免得看不出来数据漏了。

#### 溢出滚动（履历 / 专长 / 组队宣言）

三条「可长可短」的栏各包一个 `ScrollContainer`：内容超出栏位时纵向滚动条自动出现，
没超出就看不到（`vertical_scroll_mode` 默认 `AUTO`）。长句靠 Label / Button 自带的
`autowrap` 在栏宽内折行，所以正常情况下不会有横向滚动条。

> ⚠️ **子节点必须 `size_flags_horizontal = 3`（SIZE_EXPAND_FILL）**。
> `ScrollContainer` 默认只给子节点**最小尺寸**（`resume.gd` 用 `_reposition_children()` 的
> `r.size = minsize`；只有带 `SIZE_EXPAND` 的那一轴才会拉成 `max(容器尺寸, 最小尺寸)`）——
> 不设这个标志，`DeclarationContainer` 这个 autowrap Label 会缩成 1px 宽，每个字折一行。
> 三个滚动区的子节点（`ExperienceContainer` / `SkillContainer` / `DeclarationContainer`）都设了。

| 滚动节点 | 包住的栏 | 备注 |
| --- | --- | --- |
| `ExperienceScroll` | 个人履历与奖项 | 词条多了往下滚 |
| `SkillScroll` | 专长 | 词条多了往下滚 |
| `DeclarationScroll` | 组队宣言 | 整段自由文本超出一栏时滚 |


- **滚动条只在装不下时出现**：`vertical_scroll_mode` 用默认的 `AUTO`，内容没超出一页就看不到滚动条。
- **换人时滚回顶部**：`resume.gd::set_candidate()` 末尾调 `_reset_scrolls()` —— 同一张纸会被反复喂不同的
  候选人（§11.2），不归零的话下一位的简历会停在上一页滚到一半的位置。
- **改版面别把容器拆散**：`resume.gd` 按 `ExperienceScroll/ExperienceContainer` 这类路径取节点
  （`get_node_or_null`，取不到就静默不铺那一栏），挪节点记得五个脚本 + 三个 smoke 一起改：
  `resume.gd`、`tools/smoke_hover_gray.gd`（词条路径）、`tools/smoke_resume_menu.gd` 与
  `tools/smoke_team_builder.gd`（`DeclarationScroll/DeclarationContainer`）。

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
  **加一张新章 = 丢 .png 进 `STAMP_DIR` + 下面三处短名单各加一行**：`popup.gd` 的
  `STAMP_NAMES`、`tools/dialogue_generator.html` 的 `STAMP_NAMES`、
  `tools/candidate_generator.html` 的 `POPUP_STAMP_NAMES`（后两个是同一个下拉，各存一份）。
- **`popup_stamp` 只在同一行写了 `popup` 时才有意义**（牌子都没亮，章往哪儿盖）：
  `typer._normalize_line()` 两个键各自独立保留，但生成器在下拉框上就挡住了这种情况。
- **章槽挂在「牌子自己」底下**（`AwardPhd/PopupStamp`，**不是**牌子控件根节点下）：
  章的位置是写死的节点偏移（`(541,410)`，正落在牌面里），所以每块牌子各自带自己的章槽，
  跟着自己的版面走。**加一块新牌子 = 在它底下放一个 `PopupStamp` 子节点**，
  它就跟自己那块牌子的版面走了；新牌子不盖章就什么都不用放。
  共用一个根下的槽会踩两个坑（都是自检当场抓出来的）：
  ① 「这一句没写 `popup_stamp`」的**沿用**语义会跨牌子生效 —— 换牌子时把上一块的章
	 按旧位置盖到新牌子上；② 牌子收起来时章自己的 `visible` 还是 true（父节点盖着看不出来），
	 谁把牌子重新显示出来它就诈尸。所以 `hide_all()` 收牌子时**单独把章槽也藏掉**，换绑时
	 还要把旧槽的 `texture` 一起摘干净（「空就是空」，和简历那枚同一条规矩）。
- **`hide_all()` 只藏「牌子根节点 + 它的章槽」这一层，不往肚子里的 Label 递归**：
  牌子里 `Name` / `Awardto` / `Gerat` 这类 Label 的 `visible` 是**版面**（Popup.tscn 里写的），
  跟着牌子走；行级的显隐状态只有「亮哪块牌子」这一档。早先这里对整棵子树递归置 `false`，
  而 `show_for()` 只把牌子根节点恢复成 `true` —— 结果是**牌子和章都亮了、字一个都不出来**。
- **这块牌子没有章槽、数据却写了 `popup_stamp`** → `push_warning` 且不盖（不会去盖别人家的槽）。
- 位置 / 缩放 / `centered` 同样**不碰**（写在 `Popup.tscn` 上），换一张尺寸不同的章不用改代码。
- 自检见下面的 `smoke_dialogue_popup`。
- 同一行还能写 **`popup_signature`**（让玩家在牌子的空白画布上签一笔，笔迹进存档并可以重放）——
  那是另一套东西，见 **§16**。章槽那套「白名单 + 挂在牌子底下」的思路它整套照搬。

#### 词条：两个列表共用一套「扁平序号」

`experience`（个人履历与奖项）与 `skill`（专长）各自铺进
`ExperienceContainer` / `SkillContainer`（两栏都包在 `ScrollContainer` 里，见上「溢出滚动」），
但**序号是连着往下发的**：

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
									│  取 entry.ask_path，确认文件在、且里面有一句台词
									↓
					typer.load_dialogue_from(ask_path) ─→ dialoguer.play()
									┊  没有内容（没配路径 / 文件不在 / 全是空占位行）
									└─→ _play_ask_missing() ─→ dialoguer.play()
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
- **为什么「没有内容就不算问过」**：`ask_path` 为空 / 文件不在 / json 里一句台词都没有时，
  这一条确实没问出任何东西 —— 它不该在组队里亮起来（「回忆」播的就是那份 json 的内容，
  没有内容就没东西可回忆）。这几种情况**现在不再什么都不播**，而是播 `ask_missing`
  那一句（见下），但仍然不记账。自检专门盯了这两面：播了默认那句、且记录没变。
- 换天、开新局、读档、回主菜单都会把它清空（和 `passed_ids` 同命，见 `GameState` 里那四处 reset）。

#### 追问没有内容时播什么

`data/asks/` 里有一批**占位** json：行是有的，但 `speaker_name` / `text` 全是空串
（写手还没填词）。这种文件 `load_dialogue_from()` 会**返回 true** ——
照旧播就是一个空白对话框，还要点两下才收，比「没反应」更糟。

所以 `interview.gd` 把下面三种都归成「这份对话不存在」，统一改播一句默认台词
（`_play_ask_missing()`）：

| 情况 | 以前 | 现在 |
| --- | --- | --- |
| 该条没配 `ask_path`（数据漏了） | 什么都不播 | 播 `ask_missing` |
| `ask_path` 指到的 json 不在 | `push_error` 后什么都不播 | 播 `ask_missing`（仍 `push_error` 留痕） |
| json 在，但没有一句看得见的台词 | **播一个空白框** | 播 `ask_missing` |

台词的正本在 `data/dialogue.json` 的 `ask_missing` 段（写手改那句话不用碰脚本）：

```json
	"ask_missing":[
	{ "speaker_name": "面试官", "text": "这个地方好像没有什么好问的……" }
  ],
```

`interview.gd` 里另留了一份同文的常量（`ASK_MISSING_SPEAKER` / `ASK_MISSING_TEXT`）作**最后兜底**：
连 `dialogue.json` 都读不出来时，也不能给玩家一个空白框。

「有没有一句台词」的判定在 `typer.gd::has_visible_line()`：某一行**有正文**，
或者这一行要**弹点东西**（`popup` / `popup_signature`）就算有内容 ——
只亮牌子不写字的那一句也是真内容，不能被当成空对话顶掉。

⚠️ 序号越界**不算**「没有内容」：那是接线 / 调用方的错，`interview.gd` 只 `push_warning` 并不播。

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
| `data/candidates/` | **一位面试者一个文件**（`c_0001.tres` … `c_0025.tres`，另有 `c_0101.tres`） | 姓名、**等级**（`level`，隐藏属性，不上简历纸，§3.1）、种族（引用 `data/races/*.tres`）、职业（引用 `data/jobs/*.tres`）、性别、年龄、三项属性（**简历值**）、**实际属性**（`true_attributes`，只写偏差项，§3.1）、特质（引用 `data/traits/*.tres`）、**个人履历与奖项**（`experience`）、**专长**（`skill`）、**组队宣言**（`team_declaration`）、**简历印章**（`resume_stamp`，§10.6）、**拼装立绘配方**；每条履历/专长 = 描述 + 追问 json 的路径（内联 `sub_resource`，跟着本人走） |
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
  **要让他吹牛**（纸上写的 ≠ 实际有的）就填那个 `true_attributes` 字典，只写和简历不一样的那几项
  （§3.1）—— 没填的人两个数相等，等于没吹。
- **改等级**（隐藏属性，不上简历纸）→ 同一个文件里的 `level`，默认 1。
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
  序号约定与 `Resume.gd::ask_path_of()` 一致。**改数据模型就得同步改它**
  （例如 §10.6 的 `resume_stamp`、§3.1 的 `true_attributes` —— 「真实属性」那三栏留空就是不写这一行）。
  **它也能反过来读**：`读取 .tres / json…`（选文件，或把文件直接拖到页面上）与
  `从 data/ 读取…`（Chromium：整个 `data/` 一次读进来）把**已经存在的**候选人拆回表单接着改，
  改完还是走同一个「全部写入 data/…」。读进来的同 id 会**顶掉**原来那个标签，
  不会并排摆两份同 id（那样点「全部写入」时后一个会静默覆盖前一个）。两条读取期的规矩：
  - **追问台词住在 `asks/*.json` 里，不在 `.tres` 里**（`.tres` 只有 `ask_path`）。
	只选 `.tres` 时台词读不进来，那几条会被标成「台词没读进来」，**写回时跳过它们的 json** ——
	宁可少写一个文件，也不能用两行空台词把人家真写的对话盖掉。要连台词一起读：
	把同一个人的 json 一并选上，或者用「从 data/ 读取…」。
  - 写回时 `ask_path` 按序号重排成约定名 `<id>_<n>.json`；原文件名不合约定的话，
	旧文件会变成孤儿 —— 工具在提示里点名，但删旧文件得自己动手。
- 加一个新职业 / 新特质 → 在 `data/jobs/` / `data/traits/` 建资源，候选人引用它即可（`DataDB` 按目录自动归类）。

### 11.4 覆盖率自检

`smoke_m0` 第 `[3.1]` 节盯的就是这层数据：25 位候选人、10 天名单、每天 `slots` 不超过当天人数、
名单里的每个人都能在 `data/candidates/` 里查到、每条简历都齐了描述 + `ask_path` 两样、
**每位候选人的每条追问 json 都真的存在且能解析**（75 份，路径写错 / 文件忘提交 / json 写坏都在这里炸）、
**每位候选人都自带一段抬头文案**，以及 `GameState` 开局 / 换天时名单确实跟着换。
候选人那**一条隐藏属性**（`level`）也在这一节兜底：每位都得 ≥ 1（默认 1，谁都不该填成 0 / 负数）。

属性那一层的「简历值 vs 实际值」另有专门的 `smoke_true_attributes`（§3.1 尾）——
它不查内容写得对不对，只查**两个数各自被谁读**：纸面读简历值、结算读实际值、老数据不受影响。

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
| `scenes/day/team_builder/team_builder_ui.gd` / `.tscn` | UI 容器：`Backdrop`（灰色半透明底板）+ `RosterScroll → Roster`（可滚动的头像列）+ `Slots`（右下角名额空位） |
| `ui/styles/roster_panel.tres` | 左边那列的底板样式：灰色半透明 `StyleBoxFlat`（8px 圆角 + 一道极淡的描边） |
| `scenes/day/team_builder/candidate.gd` / `.tscn` | 单条候选人：`class_name CandidateEntry`，方头像框 + 两个藏在它身后的按钮；对外 `selected` / `approved` / `rejected` |
| `scenes/day/team_builder/framed_avatar.gd` / `.tscn` | `class_name FramedAvatar`：**方头像框**（底板 + 裁切过的整身立绘 + 方框）；右下角的空位也用它 |
| `scripts/util/avatar_frame.gd` | `class_name AvatarFrame`：头像框三张美术的出处 + 取景窗 / 按钮美术的几何常量 |
| `scripts/util/portrait_composer.gd` | `class_name PortraitComposer`：立绘**部件命名**的唯一出处、整身立绘贴图（`portrait_texture`） |
| `scenes/day/interview/resume/resume.tscn` | **原样复用**：右半边那页简历就是面试那一页（§10.6） |

场景树（`team_builder.tscn`）：

```
TeamBuilder (Control) [team_builder.gd]
├─ ItvBkgPhd / TablePhd       背景、桌子
├─ TeamBuilderUI (1)          左半边：底板（Backdrop）+ 滚动视口（RosterScroll→Roster）；
│                             右下角：名额空位（Slots）
├─ Resume (2)                 右半边：resume.tscn 实例（默认 visible=false）
├─ Confirm                     「组队完成」（挪到选人列右边的画布下方，x 700〜900 / y 586〜646）
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
| 右键 / 滚轮 / 中键（在**头像**上） | 一概不响应（`_gui_input` 只认 `MOUSE_BUTTON_LEFT`） |
| 滚轮 / 拖右边的滚动条（在**左边那列**上） | 那列上下滚（人比一屏多才出滚动条；滚轮是在 `ScrollContainer` 上处理的，头像不吞它） |
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
- ⚠️ **这个偏移是「取景窗（`Clip`）自己的坐标」，不能再加一次窗口原点**：立绘是 `Clip` 的子节点，
  `Clip.position` 已经是窗口左上角 —— 纵向那一句 `-window.position.y` 就是把画布原点垫回框原点，
  是同一套换算。曾经这里写成 `window.position.x + (窗口宽 − 立绘宽) / 2`，等于把「对齐两个原点」
  和「对齐两个中心」两个偏移叠在一起：画布中心落在窗口中心右边一个 `WINDOW.x`（160px 的头像上
  **偏右 13.9px**，人是贴着窗口右沿的）。现在自检两边都取 `get_global_rect()` 来比 ——
  以前拿 `portrait.position`（Clip 局部）减 `window.position`（头像框坐标）会算出「恰好相等」的假象。
  另外还量了**取景窗里真正看得见的那块像素**：它相对窗口中心不得偏出窗口半宽的 10%（实测 ≤ 3.5px）。
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

- **左边那列是一块灰色的半透明底板**（`Backdrop`：`Panel` + `ui/styles/roster_panel.tres`，
  `bg_color = (0.165, 0.165, 0.19, 0.55)` + 8px 圆角），占 x 16〜408 / y 16〜616。
  底板 `mouse_filter = IGNORE`：不吃左键，点击照样落到头像上。
- **底板里装的是一个滚动视口**（`RosterScroll`：`ScrollContainer`，x 26〜398 / y 26〜606）：
  今天通过面试的人比一屏多（视口高 580，一条 176 → 一屏 3 条出头）时，右缘自动露出竖直滚动条，
  滚轮 / 拖动都能滚。**人少时不出滚动条**（`vertical_scroll_mode` 保持默认 AUTO）。
  - 条目仍是**手摆坐标**（不用 VBox 之类的容器：两个按钮要滑到条目框外面去，容器会把它们
	算进最小尺寸里）。所以 `_layout_entries()` 摆完还要把内容高度
	（`ENTRY_TOP × 2 + (n−1) × 行距 + 160`）报给 `Roster.custom_minimum_size.y` ——
	不报的话 ScrollContainer 量不出手摆的条目有多高，人就多到画布外面去了也滚不动。
  - 视口开 `clip_contents`（ScrollContainer 默认），所以**滑出来的按钮必须落在视口里**：
	approve 滑到内容坐标系 x 338，视口内容宽 372（滚动条 8px 后仍 ≥ 360），够。
  - 被点的那一条要是正滚在视口边上，`_expand()` 会 `ensure_control_visible()` 把它滚回来。
- **左边头像列**：`ENTRY_LEFT = 96`、`ENTRY_TOP = 12`、行距 `176`，一条 160×160。
  这三个数是**视口内容坐标系**里的，换算到画布上是 x 122 起、y 38 起 —— 和原来那版基本对齐；
  左边留 96 是给 reject 往左滑的（滑到 14，还在视口里）。
- **两个按钮展开后的横向跨度**：画布上 reject 左缘 40 ～ approve 右缘 364，全部落在底板里、
  也落在左半边（简历纸从 x 579 起）—— 展开时不会戳穿灰底，也不会压到右边的简历。
- **「组队完成」挪到了选人列的右边**：x 700〜900 / y 586〜646（原来是 154〜354 / 572〜634，
  正好压在选人列下面）。现在它在简历纸下缘之下（纸占 y 29〜585）、右下角名额空位的左边
  （两个名额时空位从 x 998 起），三块谁也不压谁。
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

147 项：左半边只列通过者（被否掉的不出现）、头像框三张美术的来源与取景窗几何、
**立绘按 `PORTRAIT_SCALE` 折算后铺进取景窗、画布中心与窗口中心对齐（横向居中）、
取景窗里看得见的那个人也居中且没被窗口边缘切掉**、
**头像框与空位确实按 `AVATAR_SIZE` / `SLOT_SIZE` 渲染**、
一进来右半边是空的、点头像才铺简历、**按钮的树序在头像之前**（藏起来时真被压住）、
**收起来时按钮矩形完全落在头像矩形内 / 展开后各留 14px 压着框边**、
**收起来时按钮不吃鼠标（否则一点头像就点到那颗看不见的按钮上）**、
approve 的绿底与 reject 的红底、进队的人占掉第几个空格、两种判定互斥（改主意的来回）、
右键无反应、**版面自检**（底板是灰色半透明的、滚动视口在底板里、头像与滑出来的按钮都落在底板里、
最右不压简历纸、**「组队完成」挪到选人列右边且不压简历纸**、空位贴右下角且在纸下缘之下）、
**人多的时候能滚**（内容比视口高 → 滚动条露出来、往下滚条目跟着走、滚到底看得见最后一位、
approve 滑出来也不戳出视口）、
简历各栏与底纸和面试逐像素同位置、**「回忆」的整条链路**、
**超员点多少次都出不去而减到名额以内一下就走**、
**悬停样式只剩底色矩形、四边线宽合计为 0**，以及
**`data/candidates/` 里的候选人逐个拼得出「有内容」的整身立绘**。
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

两颗按钮都是同一套观感（`Silver.ttf` + normal / pressed 两个 `StyleBoxEmpty`，和主菜单那几个文字按钮一致），
都 `focus_mode = 0`：不然点过一次之后按空格 / 回车会把它再触发一遍。
**悬停高亮引的是全游戏共用的那一份**（`ui/styles/hover_gray.tres`，§10.6）——
和简历页的属性值栏、战报页的「确认」同一款灰，原来这两颗按钮悬停时什么都没画。

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

---

## 15. 存档与「继续游戏」

> **每天开始自动存一份**；主菜单上那颗「继续游戏」读**最新**的那份接着玩，
> 一份存档都没有时它是灰的。存档结构见 §7。

### 15.1 每天开始：自动存档

| 时机 | 落点 |
| --- | --- |
| 进每日流程 | `day_loop.gd._ready()` → `SaveService.autosave()` |
| 换天（第 2..10 天） | `GameState.advance_day()` 发 `day_started` → `day_loop.gd._on_day_started()` → `SaveService.autosave()` |

- 两处都是「**这一天开始了**」这一刻存下来的，所以文件里 `day` 就是今天、
  `phase` 是当天的起点（`DAY_BRIEFING`）、`scores` 里是**前面几天**已经挣下的分 ——
  玩家接着玩是从**这一天开头**开始，不是从按下存档的某一秒。
- **第 1 天为什么要在 `_ready()` 里补一次**：开局时 `start_new_run()` 就发过 `day_started` 了，
  那一刻 `day_loop` 还没进树，收不到（和 §10.5 那条注释是同一件事）。
- 一天里再往下走**不再存**（阶段切换不存）：「每天」就是用户要的粒度，
  存太密会把「今天刚开始」这个干净的起点冲掉。
- 写盘只有 `SaveService._write()` 一处；没有进行中的一局时它只警告不写（§7）。

> **打通关之后那份存档怎么算**：第 10 天走完进结局时，磁盘上那份还停在**第 10 天的起点**
> （最后一次写盘就是那天开始）。所以从结局回主菜单，「继续游戏」是亮的，按下去会重玩第 10 天。
> 要不要在结局时把那份存档收掉，等结局流程（`ending_resolver`）做完再定 ——
> 现在**不动玩家磁盘上的东西**：擅自删档比「多留一份」难补救得多。

### 15.2 主菜单的「继续游戏」

树里叫 `ContinuegameText`，观感与 `StartgameText` / `ExitgameText` 完全一套（Silver.ttf 60 号 +
四个 `StyleBoxEmpty`），接线照旧写在 `.tscn` 的 `[connection]` 里。

```
进主菜单 ─ _ready() ─ _refresh_continue_button()
						└─ button.disabled = not SaveService.has_any_save()

按下 ─ _on_continuegame_pressed()
		├─ SaveService.load_latest() 为真 → SceneRouter.goto_scene("day_loop")
		└─ 为假（一份都没有 / 读坏了）→ 什么都不做，只把按钮重刷一遍
```

- **亮不亮看的是「磁盘上有没有存档」**（`has_any_save()`：自动存档，或任何一个手动槽位）。
  本场景是被 `SceneRouter` 重新实例化的，所以**每次进主菜单都会按当下的磁盘重刷一次** ——
  打完一局回到主菜单时，那颗按钮的灰是新的。
- **「最新」按文件修改时间算**（`SaveService.latest_save()`），自动存档与手动槽位**一起参与比较**：
  现在只有自动存档在写，以后加了「存档 / 读档」界面也不用回来改这里。
  时间相同时（同一秒里写了两份）**自动存档优先** —— 它每天都在更新，手动槽位不该在一秒之内把它挤掉。
- ⚠️ **读不出来时绝不能开一局新的**：`load_latest()` 返回 false 时处理函数直接返回。
  玩家点的是「继续」不是「新游戏」，顺手 `start_new_run()` 等于把那份存档骗掉。
  按钮这时**仍然是亮的**（文件在，坏没坏要按下去才知道），所以这条守卫必须有 —— 自检专门盯它。
- ⚠️ **失败时不碰 `GameState`**：`load_latest()` 只在真读出东西之后才 `apply_run_state()`（§7）。

#### 那五行为什么这么排

版面照着 **1152×648 画布摆绝对偏移**；`Menu1.png` 在中间是一整片**空白纸**（实测纸面
x 360〜800、y 120〜620，纸上没有任何画好的行），字全是 Godot 画上去的 ——
所以位置只受「别和别的字撞上」约束。渲染一帧量出来的墨迹（怎么量的见 §15.4）：

| 行 | 墨迹 y | 与上一行的间距 |
| --- | --- | --- |
| 警告:勇者数量已超过路边野狗—— | 166..194 | — |
| 败犬勇者太多了！ | 226..286 | 31 |
| **继续游戏**（新） | **320..357** | 33（离标题远一点，见下） |
| 开始游戏 | 370..407 | **12** |
| 制作人员名单 | 420..457 | **12** |
| 退出游戏 | 470..507 | **12** |
| 点我查看nz今天又干了什么 | 551..584 | 43（另一颗小按钮，不在这串里） |

- **四行菜单项一律 12px 行距**：墨迹上沿相隔正好 **50**（320 / 370 / 420 / 470），
  墨迹高 38px，于是行距处处相等。为这一条把原来那两行各挪了一点：
  `Credits` 418→420、`ExitgameText` 471→470（它们原来彼此差 53、与上一行差 48，本来就不齐）。
- **离标题留了 33px**（比 12 大得多）：这样 `继续游戏` 读起来是**列表的第一行**，
  而不是标题的附属。再往上贴就会和「败犬勇者太多了！」黏成一团。
- ⚠️ **树序有硬要求**：`Button` 的**矩形**（67px 高）比墨迹（38px）大得多，四行的矩形本来就
  互相压着（`继续游戏` 的 320..387 压住 `开始游戏` 的 370..437），而谁抢到鼠标**只看树序**
  （GUI 拾取从树尾往前找，§12.3）：

  | 必须满足 | 否则 |
  | --- | --- |
  | `ContinuegameText` 排在 `Title` / `Title2` **之后** | 点「继续游戏」的上半边会去触发标题那颗音效按钮 |
  | `ContinuegameText` 排在 `StartgameText` **之前** | 点「开始游戏」的上半边会去读档 —— 玩家以为在开新局，其实被读回了旧档 |
  | `ExitgameText` 排在 `Credits` **之后** | 点「退出游戏」的上半边会跳去制作人员名单（**这个毛病本来就有**，这次顺手修了） |

  这三条由 `smoke_save_continue` 的 `[7]` 逐行盯着：往 root viewport 真的发一次鼠标移动，
  再问 `gui_get_hovered_control()`，量的是**每一行墨迹上沿往下 2px** 那一点归谁 ——
  也就是重叠区最容易出事的地方。「看得见的那一行，点下去必须也是它」。
- 置灰靠 `font_disabled_color` + `theme_override_styles/disabled`（同样是空的 `StyleBoxEmpty`）；
  只设颜色不设 disabled 样式的话，会退回引擎默认主题那个灰框（§10.6 里同一套做法）。

### 15.3 自检

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_save_continue.tscn
```

55 项，跑的是**真的主菜单 / 真的 `day_loop`**（自检逻辑挂在 root 下的常驻 runner 上，
因为中途要真的切场景，理由同 `smoke_m0`）：

- 存档路径在 `user://` 下（不在只读的 `res://` 里），并且 `.gitignore` 里挡着 `saves/`；
- **进每日流程就有存档**，里面 `day` / `scores` / `version` / `run_seed` / `phase` 都在；
- 走完第 1 天 → 第 2 天开始时的存档记的是**第 2 天**，且第 1 天的分留在 `scores` 里；
- 没存档时按钮**置灰**，而且直接发 `pressed`（绕过 `disabled`）也**不切场景、不开新局**；
- 有存档时按钮是亮的，按下去读回**存档里那一局**（天数 / 种子 / 往日分数都对得上）、
  落到每日流程，且那天的自动存档还是同一天（没被打回第 1 天）；
- 「最新」跟着**文件修改时间**走：后写的槽位赢过先写的自动存档；只剩手动槽位时也认得它；
- 坏档：按「继续游戏」不切场景、不开新局；
- **版面与点击归属**：四行菜单项等距（墨迹上沿差 50 = 行距 12），且逐行点「墨迹上沿往下 2px」
  都归它自己（§15.2 那三条树序要求就是靠这几项守住的）。

> ⚠️ 它**会临时接管** `user://` 下的自动存档与三个手动槽位（开头备份、结尾原样还原）。
> 中途被打断的话，桌面上会留着自检造的那几份。

> ⚠️ 测「最新」那一段**必须先离开每日流程**：那边还挂着 `day_loop` 的话，
> `advance_day()` 会顺手再自动存一次（§15.1 的换天存档点），刚写好的槽位就成不了最新的那份。

### 15.4 怎么量版面 / 怎么让 user:// 落进项目里

受受限沙箱与 CI 的环境限制，`user://` 落在项目目录之外时写不进去，存档那几项会**必然报红**
（§10.4 那条老注解说的就是这个）。跑之前把 `APPDATA` 指到项目里即可：

```powershell
$env:APPDATA = Join-Path <项目根> "tmp_userdata"
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_save_continue.tscn
```

`OS.get_user_data_dir()` 读的就是 `APPDATA` 这个环境变量（Windows 上 `user://` =
`%APPDATA%\Godot\app_userdata\<项目名>\`），所以覆盖它不需要引擎侧的任何开关。
`tmp_userdata/` 与里面那份 `saves/` 都不进版本库 —— `.gitignore` 里那一条 `saves/` 兜的正是这里。

> **量版面**（§15.2 那张表）走的是另一条路：拿一个临时场景把真主菜单渲染一帧，
> `get_viewport().get_texture().get_image().save_png()` 存下来，再逐行数**非纸面像素**
> 分出每一行的墨迹带。
>
> 之所以非得这么量：`font.get_string_size()` 给的是**行盒**（ascent 38 + descent 29 = 67，
> 正好等于按钮矩形高），真正画出来的墨迹只有 38px —— 只看行盒会以为 5 行字挤成一团，
> 只看墨迹又会漏掉「矩形比墨迹大、会抢鼠标」那一条。两个数都要。
>
> 还有一条：**跟着鼠标的那只手（`Haohan`）会随机盖在纸上**，量之前得先摘掉它，
> 否则整片纸都是「墨」，带与带之间全连在一起。摘的时候用 `free()` 而不是 `queue_free()`：
> 后者要到帧末才落地，截图那一帧它可能还画着。

> **量「点哪儿归谁」**（§15.2 那三条树序要求）截不出来，得真发事件：
> `Viewport.push_input(event, true)`（`in_local_coords = true`，坐标就是画布坐标），
> 再问 `gui_get_hovered_control()`。走的是鼠标**移动**而不是按下 —— 拾取结果才是归属，
> 而且**置灰的按钮照样会挡住下面的按钮**（`disabled` 只管按不按得动，不管拾取），
> 顺手就把「没存档时那颗灰按钮会不会挡住『开始游戏』」一并验了。
>
> ⚠️ **事件要发给 root viewport，别发给 `SubViewport`**：实测把主菜单挂进一个 1152×648 的
> `SubViewport` 里推事件，拾取结果全是「无」—— 菜单树根那个 `Control` 的尺寸是 **0×0**
> （它只有 `anchors_preset = 0` 的偏移，没人给它撑尺寸），拾取在那一层就断了。
> 挂到 root 下（和它平时当 `current_scene` 时一样）一切正常，所以自检里用的是 root。

---

## 16. 签名（玩家在牌子上写字）

一句台词可以让玩家在牌子的空白画布上**签一笔**，这笔字进存档，之后还能把「当时怎么写的」
重放出来：

```jsonc
// data/asks/xxx.json —— 某一行
{ "speaker_name": "勇者协会", "text": "签个字吧。",
  "popup": "Contract",                        // 牌子（底下带着一块 SignaturePad）
  "popup_signature": "contract.day1" }        // 这一句签的是哪一份
```

`popup_signature` 和 §10.6 的 `popup_stamp` 是同一套设计：**键写在台词上，落到牌子上**。
加一行数据就能用，不用给某个具体场景加代码。

**现在真的有一句在用**：`data/dialogue.json` 的 `day1_briefing`（第一天开场，由
`interview.gd` 在 DAY_BRIEFING 播）第 2 句 —— 牌子 `Contract`，key 就是 `signature`：

```jsonc
	"day1_briefing":[
	{ "speaker_name": "柳絮", "text": "这是酷炫占位符" },
	{ "speaker_name": "柳絮", "text": "来，先在这块牌子上签个字。",
	  "popup": "Contract", "popup_signature": "signature" }
  ],
```

这句话的后果是：**没签完就翻不到第 3 句**（那里现在没有第 3 句，签完再点一下就播完收场）。
玩家签的那一笔落在 `RunState.signatures["signature"]` 并当场存进 `auto.json`。

### 16.1 文件

| 文件 | 管什么 |
| --- | --- |
| `scripts/resources/signature.gd`（`Signature`） | 笔迹的数据形状 + 归一化换算 + 存档字典 |
| `ui/components/signature_pad.tscn` / `.gd`（`SignaturePad`） | 画布：录入 / 回放 / 边界吸附 |
| `scenes/common/Popup.tscn` 的 `Contract` 牌子 | 屏幕上那一大片空白画布（没有底图、没有 Label） |
| `scenes/common/popup.gd` | `popup_signature` → arm 画布、`blocks_advance()` |
| `scenes/common/dialoguer.gd` | 等签名时**不推进对话**，并把 `signature_signed` 往上转发 |
| `autoload/event_bus.gd` | `signature_signing_started` / `_finished` / `signature_signed` |
| `scenes/common/haohan.gd` | 落笔时换成蘸墨那只手，签完还原 |
| `autoload/game_state.gd` / `save_service.gd` / `RunState` | 落盘（§7 的 `signatures` 一节） |

### 16.2 数据形状：归一化坐标 + 每点时间戳

```gdscript
signature.canvas = Vector2(270, 160)       # 录制时画布多大
signature.strokes = [ { "p": PackedVector2Array, "t": PackedFloat32Array, "g": int } ]
```

三条都是踩过才知道的：

- **坐标归一化到 0..1**（`Signature.to_normalized()` / `to_canvas()`，**换算只写在那一处**）。
  存像素的话，同一段字放到缩略图 / 手册页 / 结算页里就漂了，而这块牌子注定要在好几个尺寸下出现。
  存 `canvas` 是为了「窄长画布上写的字放进方画布别变形」。
- **每一点都带时间戳**，不是「每笔记一个总时长」。人写字是起笔慢、行笔快、收笔顿，
  速度变化发生在**一笔之内**；只记总时长、笔内匀速描，回放一眼就假。量化到 10ms
  （`TIME_QUANTUM_MS`），300 个点也就多一两 KB —— 存档里塞得下，不必为它另开文件。
- **时间戳必须严格递增**（`_append_point` 里兜的 `+1ms`）：同一毫秒里落下两个点时，
  整段 `duration` 会变成 0，回放时所有点在一帧里糊上去。人手写不出同毫秒的两点，
  这条钉的是真实鼠标的高频采样、以及自检里那种一口气推完的合成输入。
- **点存成扁平 float 数组**（`[x0,y0,x1,y1,…]`）而不是 `[{"x":…,"y":…}]`：同一个意思，
  JSON 体积差一倍以上。这是唯一值得为体积做的取舍。
- **不要塞进 `flags`**：`SaveService.from_dict()` 的 `_normalize_number()` 会把整数型 float
  掰回 int，归一化坐标里的 `0.0` / `1.0` 一旦被掰，笔迹就被**静默**改坏一处。

### 16.3 录入与回放是同一个渲染函数

`SignaturePad._draw()` 只认一个变量：`_playhead_ms`（回放进度）。

- **录入** = 一边往笔迹里追加点，一边以「全部画完」渲染（`_live_points`）；
- **静态显示** = `show_signature(sig)`，playhead 直接放到终点（`_end_playhead()`，
  比总时长多 1ms —— 时间戳量化后极短的一笔总时长可能是 0，停在 0 就一笔都画不出来）；
- **动画复现** = `play_signature(sig, fit_seconds = 0)`，`_process` 按实际倍速推进 playhead。

`fit_seconds` 是「**在这么多秒内播完**」，用于播放位置有硬时限的场合：战报点确认后要在
1 秒内把字盖上去、再播完就该翻页（§16.9）。倍速 = `原时长 / 目标时长`，笔画顺序与相对
快慢都不变，只是整体变快。两档互斥：`fit_seconds > 0` 时它盖过 `playback_speed`；
真要慢放用 `playback_speed`。

所以「复现签名的过程」不是另写的功能，只是让 playhead 从头跑一趟；将来要做倍速、
拖动进度条、只播一半，都只是改这一个数。段内还按时间比例插值补点，
否则 10ms 量化下 60fps 的回放是一跳一跳的。

**为什么用 `Control._draw()` 而不是一堆 `Line2D`**：不用每帧重建 `points`；不留节点尸体
（「牌子收起来、章却诈尸」那类坑，§10.6）；换尺寸时归一化坐标现场乘即可。

### 16.3.1 画布自己长什么样：一大片空白纸，不是奖状

`Contract` 牌子**没有底图、也没有 Label** —— 它就是一个铺在屏幕下方的空白画布
（`(90,280)`–`(1060,628)`，970×348，让开上方 y 15..258 的对话框底板，否则点不到：
`Popup` 在 `dialoguer.tscn` 里是 `z_index = -2`，压不过对话框）。

- 纸面 / 边线 / 墨迹全在 `SignaturePad._draw()` 里按顺序画：**先铺纸、再描边、最后落墨**。
  层级只由语句顺序决定，不需要 `show_behind_parent` 这类隐式规则，也不多一个节点。
- `backdrop_color` 的 alpha 设成 0 就是「不铺垫子」，将来盖在自家美术上的牌子直接用它。
- `border_width = 0` 就是不描边。没有边线的话，一大片白更像「渲染漏了」而不是「一块画布」。
- `ink_width_ratio` 在 `Contract` 这个实例上覆写成 `0.012`（348 高 → 约 4px 的笔）。
  全局默认 `0.020` 是给 160 高的小牌子留的，直接套在大画布上会变成马克笔。

### 16.4 一笔画：松手 = 签名结束

**松手代表整份签名结束**，不是「这一笔结束」。所以 `_gui_input` 里签过之后
（`_signed`）就不再接受落笔，要重签得调 `clear()`。

- 数据层（`strokes` 是数组、每笔带 `"g"` 笔间停顿）本来就是多笔的，想改回多笔签名，
  放开 `_gui_input` 里那一句 `if _signed: return` 即可，存档格式不用动。
- **按下就松的一次误点不算签名**（`min_length_px`）：玩家想点一下推进会不小心把字
  「签」了，这条把它挡回去 —— 笔迹总长不够就擦掉、留在等签状态。

### 16.5 出界吸附：只挪笔迹，不挪鼠标

鼠标跑到画布外面时，`_clamp_pos()` 把**笔迹**吸附到最近的边界上，**绝不去动系统光标** ——
那只手是玩家自己的（`Haohan`），挪它就是抢方向盘。

- 顺序是**先吸附、再去抖**（`_append_point`）：反过来的话，鼠标在画布外反复挪动会给
  同一个吸附点记上几十个时间戳，回放时那一段会「停」很久。
- 这条能成立的前提是「按住左键后跑到画布外，`_gui_input` 还收得到 motion」——
  这是 Godot 的 `gui.mouse_focus` 行为，**自检里用真实事件钉住了**（见 16.8 第 9 条），
  不是想当然。

### 16.6 没签完不许翻页

`Dialoguer._input()` 里，每次左键先问一句 `_popup.blocks_advance()`：
为真就直接 `return` —— **既不推进对话，也不 `set_input_as_handled()`**。
后者很关键：`_input` 在 GUI 之前跑，一旦把事件吃掉，画布就永远收不到这一下，玩家签不了字。

签好之后 `blocks_advance()` 变假，下一击恢复推进 —— 语义正好是「签完才能往下走」。

⚠️ **但「这一句还在逐字显示」时别抢**：玩家点一下是想把字快进完，不是想落笔。所以门禁
多加半句条件 —— `waiting_for_signature and not typer.is_typing` 才 `return`；逐字显示期间
照常吃掉这一下并 `advance()`（逐字中它只 `skip_line()`、不会翻页），画布收不到事件，
于是**不会平白多一个墨点**。打完字之后的点击才归画布。

#### 松手就自动进下一句

签完不需要再点一下：`Dialoguer._on_popup_signature_signed()` 会 `call_deferred` 一个
`typer.advance()`。玩家的意图在抬笔那一刻已经表达完了，还要再点一下，手感是断的。

- **为什么要 deferred**：这次签字正是**松开左键**引发的，此刻还站在画布的 `_gui_input` 里。
  等这一轮输入处理完再翻页，免得翻页顺手把牌子和画布藏掉、而画布自己还在走收尾逻辑。
- 只翻**一句**：签字那一句必然是打完的（没打完时点击都不给画布），所以 `advance()` 走的是
  `next_line()`，不会连翻两页。

### 16.7 换手与落库：都走总线，不靠场景接线

画布埋在 `Popup → Dialoguer` 底下，而手是**每个场景自己的孩子**、`RunState` 又是
`GameState` 的。两条线都要往上穿三层，而且每挂一个新场景就得重接一次 —— 漏接一个的后果
分别是「签名时手不对」和**「签了个寂寞，存档里什么都没有」**，都是静默的。所以反过来做：
画布广播，需要知道的自己订阅。

```
SignaturePad.signing_started  ──┐
								├→ DialoguePopup 转成 ─→ EventBus ─→ haohan.gd 换手
SignaturePad.signing_finished ──┘                       │
														├→ EventBus.signature_signed
SignaturePad.signature_completed → DialoguePopup ───────┘        → GameState 落库 + 存一档
```

- `haohan.gd` 在 `_ready` 里订阅、`_exit_tree` 里**先断开再离开树**（§5.5）。
- 还原时回到**落笔之前那张图**（`_texture_before_signing`），不是直接回到默认白手 ——
  主菜单里 `MenuInk` 那类按钮本来就把手换黑了，签完字顺手抹白等于把人家踩掉。
- `GameState._on_signature_signed()` 既落库又**当场 `SaveService.autosave()`**：
  玩家签完就退出是最常见的路径，等到「第二天早上那份自动存档」那笔字就没了（§15.1 之外的
  新写档时机）。没有进行中的一局（`has_run()` 为假）就安静跳过，不凭空造一份档。
- 于是**加一段签名对话只要写一行 json，场景侧一根线都不用接**。

### 16.8 自检（`smoke_signature`）

```
& "<Godot_console.exe>" --headless --path <项目根> res://tools/smoke_signature.tscn
```

钉住十三条，都是**会静默失效**的那类：

1. 归一化往返：画布正中 → (0.5,0.5) → 双倍画布上是 (270,160)；带偏移的画布也回原点；
2. `Signature` 读数：点数 / 总时长 / 笔迹总长 / 空与非空；
3. **存读一致**：`Signature` → JSON → `Signature`，点数不变、位置漂移 ≤ 1e-4
   （时长允许半个量化量子）、画布尺寸也存了；缺一半坐标的数据跳过而不报错；
4. 画布尺寸取自场景；没 arm 时不抢拾取（`MOUSE_FILTER_IGNORE`）也不收输入；
5. **一笔画**：签完再落笔不开新笔、点数不变；按下就松的误点不算签名；
6. **时间戳严格递增**：同一帧里一口气推完的一串点，`t` 仍然递增、`duration > 0`
   （不然回放会把整段一帧糊上去）；
7. 出界吸附：所有点都在 0..1 里，跑到画布外的那个点落在角上；
8. 回放：playhead=0 只看得见起笔点、=50ms 看见 0/25/50 三点、到底看见全部；
9. Popup 联动：`Contract` 上真有画布、**且只剩画布**（没有 Label、没有底图）；
   写了 `popup_signature` → arm + 拦翻页；签好 → `signature_signed(contract.smoke, sig)`
   往上报、不再拦；已知签过的 key 直接显示旧笔迹；牌子上没画布时只警告不拦；
   收牌子后画布松开拾取；
10. **全链路落库**：签完 `GameState.has_signature()` 为真、笔迹点数对得上，
	磁盘上那份自动存档里也有它 —— 这条挡的是「功能做好了、但没人调 `set_signature`」
	（也就是签了个寂寞）；
11. **真输入**：`push_input` 到 root viewport —— 画布是一大片、落在对话框底板下方
	（y > 258），按住后把光标推到画布右边界外仍收得到 motion、那个点吸附到右边缘
	（期望值按画布矩形现算，版面改了这条不会跟着烂）；
12. **对话拦截 + 松手自动翻页**：`current_index` 在等签名时保持 0；**松手之后自己就变成 1**，
	不用再点一下；
13. **逐字显示中点击只是快进**：那一句还在打字时点一下，不翻页、也不落笔（不签名）。

> ⚠️ 第 11、12、13 条**必须走 `push_input`**，别图省事直接调 `_gui_input` —— 直接调验的是
> 画布自己的逻辑，验不了「事件到底有没有路由到画布上」。
>
> 第 10 条会真的写一份自动存档，所以跑之前照 §15.4 把 `APPDATA` 指进项目里。

数据侧的对应检查在 `smoke_dialogue_popup`：它扫 `data/asks/*.json` **和** `data/dialogue.json`，
凡是写了 `popup` / `popup_stamp` / `popup_signature` 的行都必须指到真牌子、真章名、
带画布的牌子 —— 第一天开场那一句就是这么被盯着的（改错了自检当场红）。

### 16.9 在对话框之外播放：战报右下角那枚签名

`SignaturePad` 是个**自包含的 Control** —— 它不认识 `Popup` / `Dialoguer` / `GameState`，
只依赖 `Signature`。所以想在哪播放就在哪播放，不需要对话、也不需要那块牌子。

现在的落点：**每日战报**（`scenes/day/battle_report.tscn`）。点「确认」之后，
纸面下方用 1 秒把开场签的那一笔重描出来，画完才真的收场。

```
玩家点确认
  → _on_confirm_pressed()（battle_report.gd）
	  → GameState.get_signature(&"signature")
	  → _ensure_signature_pad()          # 第一次点才建，挂在 BattleReportPhd 底下
	  → pad.play_signature(saved, 1.0)   # §16.3 的 fit_seconds
	  → await 1 秒
	  → phase_finished.emit()
```

五条都是踩过才会明白的：

- **必须先画完再 `emit`**。`day_loop` 一收到 `phase_finished` 就换阶段 / 换天，
  这个场景连同动画会被**一起拆掉** —— 先 emit 的话玩家只会看到闪一下。
- **画布挂在 `BattleReportPhd`（那张纸）底下**，不是场景根下。这样它画在纸之上、
  但在 `Haohan`（跟光标的那只手）之下，手不会被签名挡住。
- **`backdrop_color` 的 alpha 设成 0、`border_width` 设成 0、`show_hint = false`**：
  战报本身就是一整张纸，再糊一块白底 + 一圈边线上去很脏；而这枚签名只负责回放，
  没人会在这儿落笔，「按住左键签名」那行提示纯属误导。
- **先量清「纸面」到底在哪，再定位置**。`paper.png` 是 1152×648 的图，但**纸张实体只占
  `x 592..988, y 30..570`（396×540）** —— 不是整屏。画布出了这个框就是吊在空气里。
  纸上又不平：报告正文的墨迹到 y≈290 为止，「总分：72.5」在 y 487..516、「确认」在
  y 533..561。于是剩下的干净横带只有 **y 310..470**，画布取它的下半截：
  **`(610,340)–(970,469)`，360×129**。
- **宽高比锁 970:348**（录制时那块画布的比）。360/129 = 2.791 vs 2.787，差 0.1%，
  肉眼看不出。Pad 的渲染是「归一化坐标 × 当前矩形」，比例一变字就被拉变形 ——
  换尺寸请等比缩放。

实测（真窗口，画前/画后**逐像素比对**）：

```
画布矩形 = [P: (610,340), S: (360,129)]      纸面 = [P: (592,30), S: (396,540)]
画布整块都在纸面内 ✓   宽高比 2.791 vs 2.787 ✓
1 秒内全部画完（60/60 点）
画布内变化的像素 = 361，画布外变化的像素 = 0   ← 墨迹一个像素都没跑到纸外
从点确认到 phase_finished = 1010 ms
```

> ⚠️ 验「墨迹有没有出纸」**不能靠数深色像素**：纸外是夜色背景（`ColorNight` 压过），
> 本身就一片深色，数出来全是假的越界。要**画前 / 画后各存一帧再逐像素比对** ——
> 只有签名会改动帧，改动的像素全落在画布内，才算证明了它没出框。

> 想再加一个播放位（结局页 / 手册页）？照 `battle_report.gd::_ensure_signature_pad()`
> 抄一份即可，没有别的耦合 —— 但要重新量那个界面的纸面/空档，别把这一块坐标抄过去。
