# Yuusha / 面试官模拟器 · 最低配置（预估）

> 这是一份**按项目当前技术栈、素材规模与运行实测推断**的配置单，不是官方实测验收结论。
> 结论先行：本作是 **纯 2D** 游戏，真正卡住老机器的是**显卡要支持 DirectX 12**（引擎用的是 Forward+ 渲染后端），而不是算力。
> 建议拿一台 **2015 年前后的核显笔记本**做一次实机验收，再把这几个数定死。

---

## 一、配置表

| 项目 | 最低配置（预估） | 推荐配置 |
| --- | --- | --- |
| 操作系统 | **Windows 10 64 位**（1903 / 19H2 及以上） | Windows 10 21H2+ / Windows 11 64 位 |
| 处理器 | 双核 x86_64：Intel Core i3-2100 / AMD Athlon X4 860K 级别 | 四核：Intel Core i5-8400 / AMD Ryzen 5 2600 级别 |
| 内存 | **4 GB** | 8 GB |
| 显卡 | 支持 **DirectX 12** 的集成显卡或独显：Intel HD Graphics 530（Skylake）及以上、AMD Radeon Vega 8 / R7 260 及以上、NVIDIA GeForce GTX 750 Ti 及以上 | 现代核显（Intel Iris Xe / AMD Vega 8+）或独显（GTX 1050 / RX 560 级别） |
| 显存 | **512 MB**（集显可用共享内存） | 2 GB |
| 图形 API | DirectX 12（或 Vulkan 1.0+，需改回 Vulkan 驱动） | DirectX 12 |
| 分辨率 | **1280 × 720**（游戏基准画布 1152 × 648） | 1920 × 1080 |
| 存储空间 | **约 300 MB 可用空间**（安装后约 120–160 MB） | 500 MB（SSD） |
| 输入 | **鼠标（必需）**、键盘（菜单/快捷键） | 鼠标 + 键盘 |
| 音频 | 任意可用的音频输出设备 | 立体声耳机 / 音箱 |
| 其它 | 显卡驱动需支持 D3D12（建议 2018 年之后的驱动）；无需联网、无需 .NET 运行时 | — |

> 只提供 **64 位** 版本（导出 preset 的架构是 `x86_64`）。

---

## 二、为什么是这个数（依据）

### 1. 技术栈决定了「显卡必须支持 DX12」

- 引擎：**Godot 4.7.2**，项目特性 `PackedStringArray("4.7", "Forward Plus")` → 用的是 **Forward+ 渲染后端**，它依赖 `RenderingDevice`（现代图形 API），不是老的 GLES 路径。
- `project.godot` 里写死：`rendering/rendering_device/driver.windows="d3d12"` → **Windows 上强制走 D3D12**。
  - D3D12 只有 **Windows 10 及以上**才有 → 这就是"最低系统 Win10"的来源（Win7/8 装不上这个后端）。
  - 显卡必须是 D3D12 能力（大致 2015 年之后的 Intel 核显 / GCN、Maxwell 之后的独显）。**Intel HD 4000 这类只有 DX11 的老核显会直接跑不起来**，这跟游戏本身轻不轻没关系。

### 2. 游戏本身非常轻，CPU / 内存不是瓶颈

- **没有 3D 内容**：`scenes/` 里没有任何 `Node3D` / `MeshInstance3D` / `Camera3D`；`physics/3d/physics_engine="Jolt Physics"` 实际用不到（那套只服务 3D）。
- **没有自定义着色器**：仓库里没有 `.gdshader`，画面全是贴图 + `Control` 布局。
- 全部内容就是 2D 贴图、字体、音频和一个状态机，逻辑量很小（`scripts/` 约 0.1 MB）。

### 3. 素材规模（决定显存与安装体积）

| 类别 | 体量 | 说明 |
| --- | --- | --- |
| 图片 | **164 张 / 175.6 MP**（png 9.3 MB + jpg 2.8 MB） | 最大 2266 × 2266；常用整画布背景是 **2266 × 1274**（≈ 2× 基准画布 1152×648），单张带 VRAM 压缩约 3 MB |
| 字体 | 4 个 ttf，**13.7 MB** | 中文主字体（默认字体没有中文字形，必须随包带） |
| 音频 | 8 个 ogg + 5 个 wav + 1 个 mp3，**约 5 MB** | 无特殊音频硬件要求 |
| 场景 | 26 个 `.tscn`，6.3 MB | 纯 UI/2D 节点 |
| **assets 合计** | **35.4 MB** | 导出后（PCK 打包 + 纹理压缩）预计 40–50 MB |

### 4. 本机实测（开发机，仅看"占用"不看帧数）

| 指标 | 实测值 |
| --- | --- |
| 图形 API / 显卡 | `12_0`（D3D12 feature level 12_0）/ NVIDIA RTX 5060 Laptop |
| 窗口 | 1152 × 648（默认窗口尺寸 = 基准画布） |
| 引擎静态内存 | **146 MB** |
| 主菜单显存占用 | **429 MB**（含纹理缓存） |

> 这个显存数字解释了为什么"显存 512 MB"是底线：主菜单就吃掉 430 MB，进到有整画布背景 + 立绘 + 论文纸的场景还会再涨。
> 内存一侧非常宽松：引擎 146 MB + 素材，整套流程下 **4 GB 机器足够**（Win10 自己就要 2 GB，所以不建议写 2 GB）。

---

## 三、几条判定说明

1. **为什么"推荐显存 2 GB"**：纸面数字不大，但 2266×1274 的整画布背景一次会载入多张；显存不够会掉到系统内存、表现为切换场景卡顿。
2. **为什么分辨率写 1280×720**：项目没有单独设窗口尺寸，走的是 Godot 默认 **1152×648**（`window/stretch/mode="canvas_items"` 按比例缩放）。1280×720 是能完整显示且不缩放的最小常见分辨率。
3. **为什么只提 Windows**：`export_presets.cfg` 目前只有 **Windows Desktop（x86_64）** 一个 preset。要出 Linux/macOS 版的话，配置单需要另外写（macOS 还必须走 Metal/Vulkan，且需要 Apple Silicon 或较新的 Intel 核显）。
4. **不需要的东西**：不联网、不需要 .NET / VC++ 运行库（`script_export_mode=2`，纯 GDScript）、不需要光驱/手柄/触屏。

---

## 四、打包与"降门槛"的备注（可选操作）

这些不改变配置表，但会影响包体和老机器的成功率：

1. **`export_filter="all_resources"` 会把开发插件打进去**：`addons/` 现在 7.6 MB（Godot AI 的 MCP 插件，共 556 个文件），而且 `_mcp_game_helper` 是 autoload。发布版建议在导出时**排除 `addons/godot_ai`**（顺手也能减点体积）。
2. **`application/export_d3d12=0`**：不随包带 D3D12 运行时（Agility SDK），完全依赖系统自带。对老 Win10 机器更稳的做法是打开这个选项，或者……
3. **想大幅降低门槛 → 改渲染后端**：把项目切到 **`gl_compatibility`**（OpenGL 3.3 / DX11 级显卡，Win7 起），最低配置可以降到「Intel HD 4000 + 2 GB 内存」这一档。
   本作是纯 2D、无自定义 shader，**视觉上几乎没有损失**，这是最省事的一档降级方案。
4. **保持 `texture_format/s3tc_bptc=true`**：VRAM 压缩开着的时候大图才只占 3 MB 左右，关掉会明显吃显存。

---

## 五、验收建议

- 找一台 **2015–2017 年的核显笔记本**（例如 i5-6200U + HD 520 + 4 GB）：确认能进主菜单、能走完一天流程、战斗报告/结局切换不卡。
- 再用一台 **只有 DX11 显卡**的老机器验证：如果目标玩家群体里有这类机器，就得按上面第 3 条切 `gl_compatibility`，否则它们会直接黑屏/报错退出。
- 最终对外发布的配置单，建议用实测数据替换本文的"预估"字样。

---

*本文依据：`project.godot`、`export_presets.cfg`、`assets/` 素材统计、以及在本机运行主菜单时的 `OS.get_static_memory_usage()` / `Performance.MEMORY_STATIC` / `Performance.RENDER_VIDEO_MEM_USED` 实测值（2026-10）。*
