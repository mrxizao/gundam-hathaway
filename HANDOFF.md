# GUNDAM · 闪光的哈萨维 空中缠斗 —— 全量交接文档

> **写给谁**：接手这个工程的**下一个 AI 会话**（或三个月后的自己）。
> **成稿**：2026-10-07 · **基线**：**13337 PASS / 0 FAIL / 539 节 / 83 套件 / 零报错**（`_deliver` 侧最近一次全量实测）
> **写法约定**：只写**能验证的事实**（路径 / 命令 / 文件名 / 实测数字）。凡是"我记得好像是"的，标 ⚠️ 或写"待核"。
> **⚠️ 与磁盘冲突时，永远以磁盘为准。**
>
> **上一版**（写给 2026-09-20 / 第十五轮，基线 1763）已留档为
> `HANDOFF-旧-2026-09-20（停在第十五轮）.md`。那一版里的**十二条铁律**与**故障速查**仍然有效，
> 本文已把它们吸收并扩写；旧版里过期的数字（基线、规模、键位）**不要再用**。
>
> **配套的两份旧交接**：`GUNDAM_HANDOFF_2026-09-21.md`（城市重做那一轮）也是历史文档，别当现状。

---

## 目录

| § | 内容 |
|---|---|
| [0](#0-三十秒速览) | 三十秒速览 |
| [1](#1-这个游戏是什么) | 这个游戏是什么（定位 / 玩法 / 已做完 vs 没做完 / 版本号坑） |
| [2](#2-环境与怎么跑) | 环境与怎么跑（命令 / 陷阱） |
| [3](#3-工程规模与目录结构) | 工程规模与目录结构 |
| [4](#4-架构) | 架构（流程 / autoload / 关键类 / 数据真源） |
| [5](#5-玩法系统逐个说明) | 玩法系统逐个说明（12 个子系统） |
| [6](#6-主菜单与流程stage-机) | 主菜单与流程（Stage 机） |
| [7](#7-测试体系) | 测试体系（83 套件 / 判据口径 / 怎么加套件） |
| [8](#8-工程铁律) | 工程铁律（硬规则，每条一个事故） |
| [9](#9-编辑与夹具规矩) | 编辑与夹具规矩（CRLF 表 / Python 改码 / 断言） |
| [10](#10-一轮工作的标准流程) | 一轮工作的标准流程（六段式交付） |
| [11](#11-故障速查) | 故障速查 |
| [12](#12-当前遗留欠账) | 当前遗留欠账 |
| [13](#13-文档地图) | 文档地图 |
| [14](#14-第一个-15-分钟) | 第一个 15 分钟 |

---

## 0. 三十秒速览

| 项 | 值 |
|---|---|
| **是什么** | 《机动战士高达 闪光的哈萨维》题材的 **3D 空中缠斗游戏**（Ace Combat 风格），Godot 做的**可玩垂直切片** |
| **工程路径** | `C:\Users\MSIPC\Documents\gundam` |
| **引擎** | **Godot 4.7.1 stable**（`4.7.1.stable.official.a13da4feb`）· Forward+ · **Vulkan** · 物理 Jolt |
| **唯一手写场景** | `scenes/main.tscn` —— 里面**只有一个挂着 `main.gd` 的根节点**，其余全部代码 `new` |
| **autoload（6 个）** | `InputSetup` · `Settings` · `Audio` · `Game` · `Net` · `LanBrowser` |
| **逻辑画布** | **设计基准 `1600×900`（16:9）** —— `project.godot`：`window/size/viewport_width=1600` / `height=900`，`stretch/mode="canvas_items"` / `aspect="expand"`。⚠️ **但"真机尺寸"不是常量**（见下方框） |
| **主流程** | 主菜单（模式 → 机体 → 敌人 → 难度 → 地图）→ **FIGHT** → WIN/LOSE → 回主菜单 |
| **测试** | `tests/test_runner.tscn`，**83 个套件 / 13337 PASS / 0 FAIL / 539 节** |
| **规模** | GDScript **361 个（不含 `addons/`）/ 173,129 行**（含 `addons/` 共 429 个 / 184,490 行）；`.tscn` 188 个；`.glb` 211 个 |
| **版本号** | 用户在跑一条"1.3.x"的线；`README.md` 里写"没有 1.2，整条线都叫 1.1"。⚠️ **三套版本号并存**，见 §1.4 |

> ⚠️ **"真机尺寸"不是一个常量，别抄数字。** 实测过两种：
> - **`1600×900`** —— ★63-15 / ★63-16 探针抓帧（`_deliver/shots_r63_15|16/*.png` 全是这个尺寸）。
> - **`2560×1600`（逻辑 `1600×1000`）** —— `notes/12`、`notes/21` 等更早轮次的读数；
>   成因是**全屏跑在 2560×1600 显示器上 + content scale 1.6×**（`2560/1.6 = 1600`、`1600/1.6 = 1000`）。
> ⚠️ `aspect="expand"` ⇒ **逻辑视口会随窗口比例扩**，所以"画布多大"取决于**用什么模式跑**。
> ⇒ 两次取证大概率是**全屏 vs 窗口**之差（本轮**没有逐项核实**是哪一种）；**结论只有一条**：
> **真机裁图一律用归一化矩形 × 截图尺寸**（`notes/21`），像素坐标不许跨轮抄。
> 另外 **headless 视口是正方形 `1600×1600`**，与两者都不同（§7）。

**三句最要紧的话**：

1. ⚠️ **这个工程没有 git，而且经常有第二个 AI 会话在并行改它。** 动手前先看 mtime 与进程（§8.4）。
2. ⚠️ **测试的判据永远是套件打印的 `N PASS / M FAIL` + 节数 + 四类报错，不是退出码**（§7）。
3. ⚠️ **改完必须出真机图**（`--headless` 出不了像素）；**改「玩家可见的字面量」尤其必须**（§10）。

---

## 1. 这个游戏是什么

### 1.1 定位

- **同人作品**（fan project），基于《机动战士高达 闪光的哈萨维》（机动戦士ガンダム 閃光のハサウェイ）。
- 目标是 **Ace Combat 式的 3D 空中缠斗**：追尾视角、能量管理、导弹规避、光束武器对射。
- 资源**免费发布**；同时探索变现渠道。
- **不是**拟真飞行模拟 —— 是"街机气动"（arcade）。

### 1.2 玩法循环

```
主菜单
 └ 选模式
    ├ 对战模式 ─┬ 王牌战（VERSUS，1v1 单挑）
    │           └ 小队战（SQUAD，阵营编队 3×2 + ACE = 7 台）
    ├ 剧情挑战（CHALLENGE，战役图 → 简报 → 出击 → 结算）
    ├ 训练模式（TRAINING，废墟靶场 + 4 架古斯塔夫00 靶机）
    └ 局域网联机（LAN，两人都选王牌战 ⇒ 一人一台；否则打小队战）
 └ 选机体（柯西 / 佩涅罗佩 / 阿利宙斯；小队战还能搭乗 6 台量产机）
 └ 选难度（简单 / 中等 / 困难）
 └ 选地图（6 张）
 └ FIGHT ──→ 击坠 / 被击坠 / 任务目标达成 ──→ 结算菜单 ──→ 回主菜单
```

### 1.3 已做完 vs 没做完（能力矩阵）

✅ **已完成**：

| 系统 | 说明 |
|---|---|
| 飞行手感 | arcade 气动 / 失速 / 能量 / 加速 / 悬停 / 倒飞 / 辅助驾驶 —— **全部有单元测试锁死** |
| 追尾镜头 | 滞后 / 滚转混合 / FOV / 速度前馈 / 加速广角 / 三档舒适设置 |
| 鼠标 | **只做弹道准星 + 选锁定目标，不碰视角** |
| 锁定系统 | 质量条 / 保持 / 超距脱锁 / 多目标（≤3）/ `Alt` 锁定镜头 / 放大镜 |
| 机体 | 3 台可选 + 6 台量产机（可搭乗）+ 训练靶机；阿利宙斯**三形态**（巡航 / 常态 / 核心·量产型ν） |
| 武器 | 光束步枪（弹匣 + 换弹 + 丢枪）/ 火神炮（无限弹）/ 浮游导弹（弹幕化）/ 光束军刀（吸附突进）/ 蓄力光束炮 / I 立场 + 举盾 / 干扰弹 / 拦截弹 |
| 世界 | 6 张地图，**地形与天空一张贴图都没有**（全程序化）；自定义天空 shader / 海面 / 云层 / 云影 |
| HUD | 纯 `_draw()`；姿态仪 / 高度带 / 告警状态机 / 语音通道 / 雷达 / 敌机列表 / 辅助驾驶行 / 放大镜 |
| 音频 | BGM 四条通道 + 3D 定位音 + 座舱告警语音（带降级路径） |
| 剧情 | 7 个任务（`m01..m07`）+ 电台 + 触发器 + 任务评价（S·A·B·C） |
| 联机 | 局域网 PvP（房间号 + 密码 + 广播 + 代理同步） |
| 演出 | 开场 CG（Ogg Theora）+ 重力开场 + POD STRIKE 播片 |
| 平台 | 键盘鼠标 + 手柄完整适配；暂停 / 结算 / 设置菜单 |

⚠️ **没做完 / 待拍板**（详见 §12）：

- 军刀存在感（试玩者走不到"切武器 + 锁定 + 进 1400 m"这三步）
- 摇杆布局开关（"空战 / 射击"两套）
- 键位自定义 UI + 存档
- 2v2 / 1v多；白昼地图；更多机体（梅萨指挥官型 / 梅萨 F01 已有模型）
- 剧情第三章（「闪光的哈萨维」）不做
- 8% 植被（MultiMesh 撒草）

### 1.4 ⚠️ 版本号坑（必读）

**三套版本号并存**：

| 来源 | 说法 |
|---|---|
| `README.md` | 明写「**没有 1.2**，第九轮起整条线都叫 **1.1**」（`1.1 第十轮` 读作 "1.1 的第十轮"） |
| 工程根 `DESIGN-2026-09-22-1.3测试版.md` | 用 **1.3** |
| 用户口头 | 说「**1.3.2**」，并表示「版本号你自己知道就行了」 |

⇒ **别在交付物里擅自"统一版本号"**。引用时写清楚来源。

另外：`README.md` 是 **4518 行 / 306 KB**，**大量段落已过期**（基线、规模、键位都旧）。
**以代码与本文为准**；README 的价值在 §14「历轮修掉的真 bug」那类叙述。

---

## 2. 环境与怎么跑

### 2.1 两个可执行文件（用途不同，别搞混）

```
C:\Users\MSIPC\Desktop\Godot_v4.7.1-stable_win64.exe           ← GUI 版：编辑器 / 跑游戏
C:\Users\MSIPC\Desktop\Godot_v4.7.1-stable_win64_console.exe   ← console 版：无头测试 / 脚本
工程根 = C:\Users\MSIPC\Documents\gundam
```

⚠️ **跑无头测试必须用 `_console` 版** —— GUI 版不往 stdout 打印。

### 2.2 开游戏 / 开编辑器

```bash
"C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64.exe" --path "C:/Users/MSIPC/Documents/gundam"           # 直接开打
"C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64.exe" --editor --path "C:/Users/MSIPC/Documents/gundam" # 打开编辑器
```

⚠️ **不要写回 D3D12**：Windows 上编辑器 D3D12 后端会 UI 花屏（不重绘、严重时关不掉）。
工程**故意不写** `rendering_device/driver.windows` —— 不写 = 默认 = Vulkan。
现场判据：编辑器进程加载了 `vulkan-1.dll`。

⚠️ **新机器 / 新增 `class_name` 之后**先跑一次 `--import`：

```bash
"C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" --headless \
    --path "C:/Users/MSIPC/Documents/gundam" --import
```

不扫的话新类会报"找不到类"，**看起来像自己写错了**（真踩过：误判成 `hud.gd` 引用 `UILayout` 有问题，
真身是同一文件里一处重复的 `var total_w :=` 让整个脚本解析失败）。

### 2.3 跑测试（**每次改完必跑**）

```bash
# 全量（7~15 min）
"C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" --headless \
    --path "C:/Users/MSIPC/Documents/gundam" res://tests/test_runner.tscn

# 单套件（改哪块跑哪块）
... res://tests/test_runner.tscn -- --only=suite_ground_guard
```

⚠️ **`--only` 匹配的是「路径子串」**，写错 ⇒ **静默 0 条**，而汇总行照样打 `0 PASS / 0 FAIL`。

**判据（四件套，缺一不可）**：

1. **汇总行** `N PASS / M FAIL`
2. **节数**（`^--- ` 开头的行数）
3. **尾部「按套件断言条数表」**
4. **四类报错计数**：`Parse Error` / `SCRIPT ERROR` / `SHADER ERROR` / `Failed to load`

⚠️ **不看退出码** —— 各套件对退出码的写法不统一。
⚠️ **「0 FAIL」≠ 跑完** —— 0 条也可能是 `--only` 没匹配上。
⚠️ 日志先做 `\r\n` → `\n` 再做 grep。

### 2.4 出真机图 / 探针

```bash
# ⚠️ 不能加 --headless：headless 用 dummy 渲染器，抓出来是像素全空
"C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" \
    --path "C:/Users/MSIPC/Documents/gundam" res://tools/<探针>.tscn -- "<输出目录>"
```

⚠️ 工程里历史上有一个 `tools/capture.tscn`（26 张固定剧本），但**当前主流做法是"每轮写一个专用探针"**
（`tools/_r63_15_warn_shot.gd` 那种），因为专用探针能冻结世界、能配负对照、能打出判据读数。
探针约定见 §9.5。

**探针写在 `tools/`**，用 `.tscn` 包一个 `.gd`（裸 `.gd` 当场景跑会**挂住**）。

### 2.5 Python 环境

| 用哪个 | 路径 | 有什么 |
|---|---|---|
| **出图量测一律用这个** | `C:/Users/MSIPC/.workbuddy/binaries/python/envs/default/Scripts/python.exe` | **Pillow 12.2 + numpy 2.5 + scipy 1.18** 齐 |
| managed 基础 | `…/binaries/python/versions/3.13.12/python.exe` | 无 Pillow |
| 系统 | `C:/Python314/python.exe` | 有 Pillow、**无 numpy** |

```bash
PYTHONIOENCODING=utf-8 "C:/Users/MSIPC/.workbuddy/binaries/python/envs/default/Scripts/python.exe" script.py
```

⚠️ **`PYTHONIOENCODING=utf-8` 必须加**，否则往中文控制台打中文会炸。
⚠️ **Python 单行脚本里内层 ASCII 双引号会语法报错** ⇒ 内层一律用「」。
⚠️ 删文件用纯 POSIX 路径 `/c/...` 或 `mv`（`rm` 遇盘符会被拦）。

---

## 3. 工程规模与目录结构

### 3.1 规模（2026-10-07 实测）

| 项 | 数量 |
|---|---|
| GDScript 文件（不含 `addons/`） | **361** |
| GDScript 总行数（不含 `addons/`） | **173,129** |
| GDScript 文件 / 行数（含 `addons/`） | **429** / **184,490** |
| `.tscn` | 188 |
| `.glb`（模型） | 211 |

| 目录 | 文件 | 行数 | 管什么 |
|---|---|---|---|
| `scripts/`（根） | 1 | 3,306 | `main.gd`（引擎入口 / UI 流程状态机） |
| `scripts/autoload/` | 5 | 3,084 | 5 个 autoload |
| `scripts/flight/` | 17 | 16,596 | 飞行 / 相机 / 辅助 / 形态 / 骨架 |
| `scripts/combat/` | 8 | 2,950 | 弹丸 / 导弹 / 拦截 / 锁定 / 伤害 |
| `scripts/ai/` | 2 | 1,304 | 敌机 AI / 靶机 |
| `scripts/world/` | 5 | 13,804 | 世界构建 / 特效 / 烟带 |
| `scripts/ui/` | 11 | 13,266 | HUD / 菜单 / 版式 / 读条 / 开场 |
| `scripts/data/` | 20 | 13,375 | **全部数值真源**（机体/地图/难度/任务/电台…） |
| `scripts/audio/` | 2 | 919 | 音频导演 / 音效表 |
| `tests/` | 95 | 51,290 | 83 个套件 + 探针 + `t.gd` 断言库 |
| `tools/` | 195 | 53,235 | 探针 / 出图 / 一次性脚本（**历史堆积，多数已废**） |

### 3.2 目录树

```
gundam/
├── project.godot                 ← 配置（含 6 个 autoload、[input] 固化副本）
├── scenes/
│   └── main.tscn                 ← ★ 唯一手写场景
├── scripts/                      ← 见上表
├── data/
│   └── script/                   ← 剧情台词 CSV（h1_dialogue.csv / h2_dialogue.csv）
├── assets/
│   ├── models/                   ← 13 个目录：xi / penelope / arizeus / gustav /
│   │                                messer / messer_cmd / messer_f01 / nu_mp /
│   │                                deployed / pedal / pedal_states / xi_pod / mafty_rocket
│   ├── audio/{bgm,sfx}/
│   ├── ui/                       ← faction 图标 + title.png
│   └── video/                    ← intro_op.ogv / intro_mafty.ogv（Ogg Theora）
├── shaders/                      ← 5 个
├── tests/                        ← 83 套件 + test_runner.gd/tscn + t.gd
├── tools/                        ← 探针与出图（195 个，多数是历史遗留）
├── addons/lit/                   ← 第三方（LIT 光照插件）
├── DESIGN-*.md                   ← 13 份设计文档（见 §13）
├── GUIDE-2026-09-22-Blender骨骼与动作.md
├── README.md                     ← 4518 行主文档（⚠️ 部分过期）
├── HANDOFF.md                    ← ★ 本文
├── HANDOFF-旧-2026-09-20（停在第十五轮）.md
├── GUNDAM_HANDOFF_2026-09-21.md  ← 更旧的交接（历史）
└── _backup_20260927_pre_davao_build/  ← 唯一一份工程内旧备份
```

⚠️ **工程根有大量 `_*.txt` / `_*.png` / `_r*_shots/` 临时产物**（**实测 1916 项 / 约 1.4 GB**），那是历轮跑出来的日志与图，
**别当源码**，也别指望它们是最新的。

### 3.3 备份与交付在哪

| 东西 | 位置 |
|---|---|
| **回退备份**（唯一！） | `%LOCALAPPDATA%\Temp\gundam_bak\r<轮号>\` —— **必须写绝对路径** |
| **交付物** | `C:\Users\MSIPC\WorkBuddy\2026-09-25-17-05-06\_deliver\`（四件套：主说明 / 源文件md5 / 判据运行日志 / 判据图） |
| **工作记忆** | `C:\Users\MSIPC\WorkBuddy\2026-09-25-17-05-06\.workbuddy\memory\`（`MEMORY.md` + `notes/01..23` + 逐轮 `YYYY-MM-DD.md`） |
| **临时补丁脚本** | 工作区根（`_r63_16_*.py` 那种） |

⚠️ **备份不许写在工程目录内**：相对路径落进工程 ⇒ 撞 `class_name` ⇒ **套件一条都不跑而 runner 照样绿**。

---

## 4. 架构

### 4.1 场景与流程

```
scenes/main.tscn （Node3D + main.gd）
└─ main.gd  ── _ready() 里 new 出：world / units_root / projectiles / chase / HUD / 菜单
   process_priority = -100   ← 状态机必须早于喂它输入的 UI 处理（否则同帧竞争）
   process_mode = ALWAYS     ← ★ 见下面那条坑
```

⚠️⚠️ **两个 `Phase` 枚举并存**（新人必踩）：

| 枚举 | 在哪 | 管什么 | 值 |
|---|---|---|---|
| `main.gd` 的 `enum Phase` | `scripts/main.gd` | **只管 UI 流程** | `MENU / FIGHT / RESULT` |
| `Game.Phase` | `scripts/autoload/game.gd` | **管对局状态** | `MENU / INTRO / FIGHT / WIN / LOSE` |

⚠️ `Game.Phase.INTRO` 是一个**永远不会被 `set_phase()` 赋值**的残留成员（只有 `var phase` 的初值用它）。
`main.gd` 里已写明"1.2 起没有 INTRO（用户要求删掉'按空格出击'）"。

⚠️⚠️ **`process_mode` 是继承的**：`main.gd` 把 main 设成 `PROCESS_MODE_ALWAYS` ⇒ 整棵子树跟着 ALWAYS
（`FlightBody` 是 `INHERIT`）。所以 **`get_tree().paused = true` 冻不住机体**；
要站住的显式标 `PAUSABLE`（如 `ChaseCamera`），要活的显式标 `ALWAYS`（如 HUD）。
见 §8 铁律 8。

没有"再战一局"：结算后**一律回菜单重选**（少一条阶段转换 = 少一类状态残留）。

### 4.2 六个 autoload

| 名字 | 文件 | 管什么 |
|---|---|---|
| `InputSetup` | `scripts/autoload/input_setup.gd` | **键位唯一真源**（`BINDINGS` / `KEY_LABELS` / `ACTION_NAMES` / `HELP_SECTIONS` / `SHARED_KEYS_OK` / `RETIRED_ACTIONS`）+ 当前设备追踪 |
| `Settings` | `scripts/autoload/settings.gd` | 画面尺寸 / 音量（BGM / SFX 两条总线）+ 存档；`begin_isolated()` 是测试隔离闸门（⚠️ **有洞，见 §12**） |
| `Audio` | `scripts/audio/audio_director.gd` | BGM / 非定位音 / 3D 定位音三条通道 + 座舱告警语音 |
| `Game` | `scripts/autoload/game.gd` | **对局状态唯一真源**：谁在场 / 谁死了 / 时钟 / 模式 / 阶段 / 统计 |
| `Net` | `scripts/autoload/net_session.gd` | 局域网联机（`net_proxy_body.gd` 是对端代理机体） |
| `LanBrowser` | `scripts/autoload/lan_browser.gd` | 局域网房间发现（广播收发） |

### 4.3 关键类（按职责）

| 层 | 类 / 文件 | 一句话 |
|---|---|---|
| **入口** | `main.gd` | UI 流程状态机；唯一手写场景的根 |
| 飞行 | `FlightModel` | **手感的地基**：不碰场景树，只吃 `Basis` + 输入 → 返回新 `Basis`。**可纯函数测试** |
| 飞行 | `FlightBody` | 机体基类（**最大文件**）：姿态 / 位移 / 两层减伤 / 武器 / 军刀状态机 / 换弹 / 夜航灯 / 喷口 |
| 飞行 | `PlayerController` | 键鼠手柄 → 控制输入（摇杆轴 / 模拟油门 / 丢枪长按 / 拦截 / 敌机列表数字键） |
| 飞行 | `FlightAssist` | **辅助驾驶**：自动按住 Shift / 平移模式 / 防撞地 / 地形警告 |
| 飞行 | `ChaseCamera` | 追尾镜头（滞后 + 滚转混合 + FOV + 速度前馈） |
| 飞行 | `SuitRig` | 槽位骨架：真模型可见后仍提供**炮口 / 喷口 / 手 / 翼尖**锚点 |
| 飞行 | `ModelAnim` / `ModelAnimFSM` / `FormWeld` / `FormCurveModifier` | 模型动画 / 状态机 / 形态焊接 / 形态曲线 |
| 飞行 | `CruiseFormModifier` | 柯西 / 阿利宙斯巡航形态的变形曲线（morph target） |
| 战斗 | `LockOnSystem` | 锁定（质量条 / 保持 / 超距脱锁 / `<3` 多目标） |
| 战斗 | `Projectile` / `Ballistics` | 光束与火神炮（**球形扫掠**防穿透）/ 纯函数提前量解算 `intercept_point()` |
| 战斗 | `Missile` / `Interceptor` / `Flare` | 导弹 / 拦截弹 / 干扰弹 |
| 战斗 | `BeamCannon` | 蓄力光束炮（阿利宙斯） |
| 战斗 | `Damage` | 伤害类型 + I 立场减伤表 |
| AI | `BanditAI` / `TargetDrone` | 敌机四态机 + 难度；训练靶机（固定航线、不还手） |
| 世界 | `WorldBuilder` | 天空 / 海 / 三带云 / 岛屿 / 沙漠 / 靶场 / 城市 / 轨道（**全程序化，无贴图**） |
| 世界 | `FX` / `BoostTrail` / `MissileRibbon` / `SeaSplash` | 爆炸 / 光束 / 尾焰 / 变形烟 / 拖尾光条 / 烟带 / 落水 |
| UI | `UILayout` | **三屏公共版式网格**（外框 / 内容列 / 数值列）—— 版式数字的唯一真源 |
| UI | `MainMenu` / `PauseMenu` / `FlightHUD` / `SpeedLines` / `LoadingScreen` / `IntroMovie` | 全部纯 `_draw()` |
| UI | `CampaignMap` / `MissionBrief` / `MissionTitle` / `SilhLines` | 剧情模式界面 |
| 数据 | `SuitProfile` / `MapDef` / `Difficulty` / `TimeOfDay` / `LaunchScript` | **数值只在这些文件里出现** |
| 数据 | `MissionScript` / `Campaign` / `Comms` / `CommsBank` / `Trigger` | 剧情任务 / 战役 / 电台 |
| 数据 | `BattleFormation` / `LanPlan` / `LanRoom` / `Producer` / `SuitRig` | 编队 / 联机计划 / 房间 / 制作人名单 |
| 数据 | `MissionRating` / `PodStrikeScript` / `IntroPlaylist` / `CutsceneScript` / `ChallengeScript` | 任务评价 / 播片 / 开场 / 过场 |

### 4.4 ★ 数据真源表（要改数值就来这里）

| 想改什么 | 唯一真源 | 备注 |
|---|---|---|
| **机体数值**（速度 / 耐久 / 武器 / 军刀 / 导弹 / 丢枪 / 喷口） | `scripts/data/suit_profile.gd` | 7 个 id + 阿利宙斯三形态；**别处不许出现魔数** |
| **速度基准** | 同上：`XI_REFERENCE_SPEED := 420.0` / `PLAYER_BOOST_MULT := 1.5` / `SPEED_REAL_MULT := 2.4` | 玩家加速 = 基准 ×1.5；敌机 = 基准 × 难度倍率（1.0 / 1.3 / 1.5） |
| **敌机速度天花板** | 同上：`ENEMY_SPEED_CEILING_RATIO := 0.92` | 钳到"玩家加力上限 ×0.92"（第十四轮修"追不上敌机"） |
| **耐久 / 护盾** | 同上：`DURABILITY_MULT := 1.60` / `SHIELD_REDUCTION := 0.80` | 耐久调过 5 次（1.35 → 1.60） |
| **浮游导弹** | 同上：`MISSILE_PER_SHOT=3` / `MISSILE_DAMAGE_MULT=0.3` / `MISSILE_COUNT_MULT=5.0` | 载弹 120→600，**都是有意的加强**，护栏已反向成 `> 1.0`，**不要再改回去** |
| **难度** | `scripts/data/difficulty.gd` | `enum Level { EASY, NORMAL, HARD }`；AI 速度 / 锁定效率 / 丢枪 |
| **地图**（地表 / 云量 / 夜色 / 强调色 / 灯） | `scripts/data/map_def.gd` | `enum Id { PACIFIC, ULURU, RANGE, OENBELLI, DAVAO, LEO }` |
| **时段光照** | `scripts/data/time_of_day.gd` | `night()` / `dusk_overcast()` / `space()` |
| **键位** | `scripts/autoload/input_setup.gd` 的 `BINDINGS` 等表 | 改完**必须**重跑 `tools/gen_input_map.gd` |
| **操作说明文案** | 同上 `HELP_SECTIONS` | **必须**和实际读取点一致（§8 铁律 3） |
| **三屏版式** | `scripts/ui/ui_layout.gd` | `suite_layout` 会在四种窗口比例下断言 |
| **音频路径** | `scripts/audio/sound_bank.gd` | 所有路径只在这里出现一次 |
| **剧情任务** | `scripts/data/mission_script.gd` | `m01..m07`；`Mission.enemy_suit` / `waves[].suit` / `comms.RADIO` |
| **电台台词** | `scripts/data/comms_bank.gd` + `data/script/*.csv` | |
| **编队 / 阵营池** | `scripts/data/battle_formation.gd` | `mafty()` / `federation()` |
| **HUD 告警表** | `scripts/ui/hud.gd`：`WARN_TEXT` / `WARN_STYLE` / `WARN_ORDER` / `WARN_PRIORITY` | 全是英文 |
| **手柄字形** | `FlightHUD.PAD_GLYPH`（`hud.gd`） | ⚠️ 与 `PAD_BINDINGS` 是**两份**，改键位两边都要动 |

### 4.5 机体名单

```gdscript
enum Id { XI, PENELOPE, ARIZEUS, GUSTAV00, MESSER_M01, MESSER_CMD, MESSER_F01 }
```

| id | 机体 | 说明 |
|---|---|---|
| `XI` | 柯西高达 RX-105 | 玩家机；有丢枪脱锁 |
| `PENELOPE` | 佩涅罗佩 RX-104FF | 玩家机 / 常当 ACE |
| `ARIZEUS` | 阿利宙斯 TX-ff104 | **一台机带三形态**（见下） |
| `GUSTAV00` | 古斯塔夫 00 | 训练靶机（不还手） |
| `MESSER_M01` | 梅萨 M01 | 量产机 |
| `MESSER_CMD` | 梅萨指挥官型 | 量产机 |
| `MESSER_F01` | 梅萨 F01 | 量产机 |

⚠️ **加枚举值时必须同时改 4 处**（少一处不报错，只会静默走错）：

1. `by_id()` —— 漏了 ⇒ 该 id **回落成柯西**（兜底 `return xi()`）；
2. `id_name()` —— 漏了 ⇒ 返回 `"XI"`；
3. `FlightPedal.kind_for_suit()` —— 漏了 ⇒ 这台机**静默骑喀耳刻板**（兜底 `Kind.KILCE`）；
4. `BattleFormation.mafty()/federation()` 的池子 —— 漏了 ⇒ 玩家选不到。

**阿利宙斯三形态**：巡航（直线比佩涅罗佩快 40%，转不动）/ 常态（人形，速度同级）/
**核心 · 量产型ν高达**（外壳战损剥离后露出，速度是柯西的 95%，**没有浮游导弹**，
但光束步枪 / 火神炮 / 光束军刀 / 蓄力激光炮四件都有）。

### 4.6 地图名单

```gdscript
enum Id      { PACIFIC, ULURU, RANGE, OENBELLI, DAVAO, LEO }
enum Terrain { ISLANDS, DESERT, RANGE, CITY, SPACE }
enum CityLayout { OENBELLI, DAVAO }
```

| 图 | 地表 | 说明 |
|---|---|---|
| 太平洋群岛 | `ISLANDS` | 1.0 起就有；**第十四轮起没有岛了**（老板："小岛要删掉，不好看"） |
| 艾尔斯岩 | `DESERT` | 1v1 图：暗红沙漠 + 巨岩（乌卢鲁）+ 沙丘 |
| 废墟靶场 | `RANGE` | 训练模式专用：夜里的废墟靶场 + 地面靶环 + 探照灯 |
| 奥恩贝利 | `CITY` | 阴天黄昏下的**死城**（刚经历大屠杀，有路灯但**一盏不点**） |
| 达沃 | `CITY` | 夜袭的**活港都**（灯火全开）；与奥恩贝利**共用城市管线**，分开的只有种子 / 地标 / 配色 / 灯 |
| **低地球轨道** | **`SPACE`** | ★ 剧情轮 B2 新增，**唯一一张没有地表的地图**；见 `has_ground` |

⚠️⚠️ **`SPACE` 必须显式加进 `_map_stage_terrain()` 的 `match`** —— 那一处有 `_` 兜底分支
（`_build_islands(ISLAND_COUNT)`）。漏了分支 ⇒ 轨道图会**静默建成太平洋群岛**：
不报错、不警告，只是"宇宙图里有一片海和几座岛"。**这个坑踩过一次**（`suite_round20` 是它的见证）。

⚠️ **`has_ground` 是语义 flag，不依赖碰撞体存在** —— Pacific Islands 没有 collider 但 `is_ground = true`。

---

## 5. 玩法系统逐个说明

> 这一节只给"形状"。**要动某一块之前**去读对应的 `notes/NN`（见 §13）—— 那里有实测数与推导。

### 5.1 飞行模型

- `FlightModel` **不碰场景树**：只吃 `Basis` + 输入 → 返回新 `Basis` ⇒ **可纯函数测试**。
- 把"**机头姿态**"和"**速度矢量**"**分开**（这是全工程最关键的设计决策）。
- 概念：推动杆 / 拉杆 / 滚转 / 偏航 / 油门 / 加速（boost）/ 悬停（hover）/ 失速 / 能量 / 诱导阻力。
- **倒飞**（`translate_reverse`）、**辅助驾驶**（自动按住 Shift）、**平移模式**（`translate_dir.y` = Q/E）见 §5.9。

### 5.2 相机

⚠️⚠️ **视场定式（必记）**：

```
fov 是【垂直】FOV  ⇒  半水平角 h = atan( tan(fov/2) × aspect )
base_fov 68  ⇒  16:9 时 h = 50.17° ；headless（正方形）时 h = 34.00°
```

⇒ **锁定锥 55° > 半水平视场** ⇒ 目标飞到锥边缘时**自机必然出画**。这是**几何必然，不是 bug**。
⚠️ **headless 视口是正方形 1600×1600**（与真机的 1600×900 不同）⇒ 与宽高比有关的判据**必须运行时算**，不能写死。

- 追尾镜头：滞后 + 滚转混合 + FOV + **速度前馈**；加速时广角。
- **三档舒适设置**：滚转跟随 / 抖动 / 降低动态。
- ⚠️ **动相机的风险是全工程最高的** ⇒ 必须**独立轮** + 判据**必须无头**。
- **放大镜**（第二台相机，★63-10）：全工程**唯一一个 `SubViewport`** + 专属 `Camera3D`
  （**垂直** `fov 6°`、距目标 400 m、`far 60000`）。

### 5.3 鼠标 / 锁定 / 辅助瞄准

- **鼠标只做两件事**：弹道准星（光束 / 火神炮方向）+ 准星罩住敌机即锁定。**不参与机头姿态。**
- 锁定：质量条 → 保持 → 超距脱锁 → `<3` 多目标（火力按人数分散）。
- **锁定对象只由玩家切换**（★轮 36 重修，`suite_lock_manual`）：不自动补位、鼠标只管准星。
- `Alt` = 锁定镜头；`Tab` = 切换目标；`1`–`9` = 直选右上角敌机列表第 n 架。
- **辅助瞄准**（★63-9 D3a）：`aim_point()` 第 6 形参；`FlightBody` 虚函数恒 `false`，
  `PlayerController` 覆写。⚠️ 它**曾经是死代码**（度/弧度单位错）。
- ⚠️ 锁目标前先看 **`LockOnSystem.seeker_range` = 46575 m** —— VERSUS 出击点相隔 92 km > 它
  ⇒ **`select_target()` 会静默返回 `false`**。

### 5.4 武器与伤害

| 武器 | 说明 |
|---|---|
| 光束步枪 | 弹匣制 + `R` 换弹（长按 0.6 s = **丢枪脱锁**，仅柯西）；锁定后有限度的命中辅助 |
| 火神炮 | `空格`（手柄 R1）按住连发，**无限弹** |
| 浮游导弹 | `F`（手柄 L2）一次三发，需锁定；载弹 ×5.0 = 600 发 |
| 光束军刀 | `X` 切换后左键；**吸附突进**；有 `xi_slash.glb` 动作 |
| 蓄力光束炮 | 阿利宙斯专属；柱体是**圆台**（炮口细、末端 ×2），匀速 10900 m/s |
| I 立场 + 举盾 | `T`（手柄 B）按一次举 5 秒；`SHIELD_REDUCTION = 0.80` |
| 干扰弹 | `C` |
| 拦截弹 | `B` 选威胁 / 鼠标右键 / 手柄 L1；**L1 按住 = 自动拦截**（`InterceptAuto`） |

**伤害模型**：两层减伤（护盾层 + 结构层）。
⚠️ **光束有「两个独立半径」**：**视觉半径 ≠ 判定半径**，**两个独立常量**，**不许绑回**
"判定 = 视觉 × 2"（有守卫）；命中**全押 `cast_motion()`**。
⚠️ 命中判定用**球形扫掠**（不是零半径射线）—— 零半径会**穿透**。

### 5.5 AI

- `BanditAI`：**四态机** + 难度表；阿利宙斯会自己切换巡航 / 常态。
- **AI 为锁定付钱**（难度表里有"AI 锁定效率"）。
- **进攻欲望**：`AGGRESSION 1.14`（5 处）；`SEEK ⇒ 0.92`；`_tick_ace_pressure()`；
  `ACE_COMMIT_WINDOW` / `ACE_ATTACK_PERIOD`。
  ⚠️ **提 `AGGRESSION` 反而让平均节奏更慢**；想更凶要动 `ACE_*`（12.0 / 4.0 → 9.0 / 5.0）。
  ⚠️ **强制脉冲在远距"无声"是刻意的** ⇒ **别当 bug 修**。
- AI **避地**（"敌机一头扎海"那个历史 bug 的正解）：有探针 `tools/probe_ai_dive.tscn`。
- **猎杀规则**：阿利宙斯对残血柯西（用户指定，**只给 AI**）。

### 5.6 地图与世界

- **全程序化，一张贴图都没有**：自定义天空 shader / 海面 / 三带云（MultiMesh）/ 岛屿 / 沙漠 /
  巨岩 / 靶场 / 城市 / 轨道。
- 竞技场半径 **26 km**；云量**按地图配置**（群岛 ~2340 朵 / 艾尔斯岩 ×1.9 ≈ 4491 朵）。
- **云影**：一张程序化覆盖图，自机 + 敌机 + 地表 + 海面**共用同一个场**（CPU 与 GPU 同源）。
- 城市（`Terrain.CITY`）：栅格 / 海岸线 / 海湾 / 运河 / 单轨 / 桥是**共享管线**；
  分开的只有**种子 / 地标 / 配色 / 灯**。
- **城市点灯是枚举不是 `bool`**（`CityLight`）：`NONE` / `POSTS_ONLY` / `FULL`。
  ⚠️ **`bool` 赋给 `int` 时 `true` 会静默变成 1**，所以不能用 `bool`。

### 5.7 HUD / UI 版式

- **全部纯 `_draw()`** —— 没有 Control 树。
- 组成：姿态仪 / 高度带 / 中央告警状态机 / 语音字幕 / 雷达 / 附近敌机列表 / 辅助驾驶行 /
  放大镜面板 / 数值列 / VS 垂直速度 / 准星 / 威胁层（飞弹框 + TTI）。
- ⚠️⚠️ **版式数字的唯一真源是 `UILayout`**（外框 / 内容列 / 数值列）。
- ⚠️⚠️ **「给手柄看的信息」绝不能长在鼠标分支里**：`_draw_aim_cursor()` 第一行是
  `if not player.cursor_seen: return`，而手柄**不产生鼠标移动事件** ⇒ 长在里面的东西
  **手柄玩家一辈子看不见**。**这个 bug 发作过两次**（辅助飞行角标 / 整套威胁层）。
  修法已抽成纯函数 `FlightHUD.threat_layer_visible()` + 回归门。
- ⚠️ **UI 风格闸门**（`tests/suite_ui_style.gd`）：
  - 颜色常量**只许 9 个名字**（`HUD HUD_DIM HUD_FAINT WARN DANGER NEUTRAL IFIELD IFIELD_DIM OUTLINE`），
    `hud.gd` **恰好 9 个** `const X := Color(...)` ⇒ 新颜色写 float 常量 + 绘制处 `Color(...)`；
  - 线宽**只两档**（`LINE_HAIR` / `LINE_STRUCT`）；闸门扫 `draw_*` 的**实参原文**：
    必须**字面**含 `UILayout.LINE_*`、**一个数字都不许有**。
- ⚠️ **上屏不许写 Markdown `**`**（不会渲染）。

### 5.8 音频

- `AudioDirector`（autoload `Audio`）三条通道：**BGM / 非定位音 / 3D 定位音** + 座舱告警语音。
- ⚠️ **「调大 N%」= 振幅 ×(1+N/100) = `20·log10(1+N/100)` dB**
  —— +25% ⇒ **+1.9382 dB**。**写 `+25.0` 是 17.78 倍、会削顶。**
- ⚠️ **音量不许留调用点** ⇒ 一律走 `GAIN_DB` 表（`sound_bank.gd`）。
  **例外**：座舱告警语音**故意不走**增益表（它是写死的救命基准 `VOICE_DB`）—— 否则玩家把 SFX 调低会把它一起调没。
- ⚠️ **Godot 只认 Ogg Theora**（没有 WebM 支持）。16:9 铺 16:10 ⇒ `AspectRatioContainer` + 黑底。
- ⚠️ **播片必须有看门狗**：`finished` 信号不来 = **永久黑屏**。
- ⚠️ **无头环境测不了音频**（dummy 驱动）。

### 5.9 辅助驾驶 / 能量 / 防撞地

- 真源：`FlightAssist.assist_uses_translation()`；触发条件是 **`has_pedal()`**（**不是** `can_ride_pedal()`）。
- ⚠️ 辅助驾驶 = **每帧替你按住 Shift** ⇒ **能量槽烧空后永远停在 0**（要调就动 `jet_recharge`）。
- ⚠️ `_tick_assist()` 有**两处早退**（辅助关 / 平移模式）；**光挪代码没用**。
- ⚠️ 平移模式下**抬头旋钮是 `translate_dir.y`**（`Q`/`E`），**不是** `control_input.x`。
- ⚠️ **`hover`（CTRL / R3）在平移模式全文不读**；辅助下按 CTRL = **倒飞**（`translate_reverse`）。
- ⚠️⚠️ **无锁定 + 底速反向 ⇒ 机头连续自旋**（实测 177.65°）⇒ 追**等效正向速度** `vref`。
- **防撞地**（★63-15）：
  - **`GROUND_GUARD_ALT := 50.0` 已拍板钉死**（"严守 50 m 字面"）。
  - ⇒ 极速深俯冲**救不回来**：拉起窗 `(50−24)/(2268·sin33°) = 0.021 s` vs 平移模式 `3τ ≈ 0.94 s`
    ⇒ **差 45 倍 = 几何，不是参数**（实测把 `RELEASE_GRACE` 压到 0.0，真机读数**逐位不变**）。
  - 落地形态 = **50 m 之上「只报警、不改出」**：门 = `TERRAIN_WARN_TIME 2.5 × 当前垂速`
    （**是时间，不是高度**）、纯函数 `terrain_warning()`、边沿闩 `_terrain_warn_on`
    ⇒ `_system_say("地形警告 · 拉起")` ⇒ `hud.gd:3724` 走 `DANGER` 色。
  - ⚠️ **同一屏本来就有一条更早的 `PULL UP`**（`alt + vs×2.6 < PULL_UP_ALTITUDE(420)`，
    早约 **0.55 s / 530 m**、且 `flash 5.0` 会闪）⇒ 交付时**必须主动标注**，别把既有红字算成本轮成果。

### 5.10 剧情模式

- 三章结构：**第一章「正当的预言之王」5 任务 · 第二章「喀尔刻的魔女」3 任务 · 第三章「闪光的哈萨维」暂不做**。
- 玩家可扮演：哈萨维 / 雷恩艾姆 / 加乌曼 / 古斯塔夫的无名驾驶员。
- 任务目标**不限于歼灭**：打捞物资 / 破坏目标区域 / **到达指定区域（含空中点位）**。
- 任务表：`scripts/data/mission_script.gd` 的 `m01()..m07()`。
- 触发器动作**只有两种**：`radio:` / `end:` —— ⚠️ **`cutscene:` 走不通**（写了也不会跑）。
- ⚠️ **换机型要动「四件套」**：`Mission.enemy_suit` / `waves[].suit` / `comms.RADIO` / `model_root.visible`
  —— **只改一个 = 简报撒谎且不报错**。
- ⚠️ **死拍子**：波次/事件按 `elapsed` 硬拍，改时间轴要成组改。
- ⚠️ ACE **必须与玩家同阵营**。
- ⚠️ **m02 敌机速度 ×1.380 ⇒ 要 ×0.75**（不能直接削全局 `speed_scale`）。
- **任务评价**：`MissionRating` —— 波次计时 + S·A·B·C（1.3 批）。
- **经济系统 + 强化改装**（**数据层已落地 / 界面层未做**，2026-10-07 实测）：
  - **已落地**（`scripts/data/campaign.gd`）：初始军资 `progress["credits"]`、唯一入口 `credits_of()`
    / `credits_text()`（→ 上屏「军资 N」）、槽位常量 **`UPGRADE_SLOTS_UP := 1`** / **`UPGRADE_SLOTS_DOWN := 3`**、
    `empty_loadout()` / `loadout_of()` / `slots_left()` / `clamp_loadout()`，以及存档的 `[wallet]` / `[upgrades]` 段读写。
  - **未落地**：商店。`campaign.gd:121` 原文「工程里**还没有商店**（`DESIGN §6.5` 的 `campaign_shop.gd` 是轮 C2 的事）」；
    `main.gd:1267`「改装与商店是**轮 C2**」。
  - 设计文档 `DESIGN-2026-09-28-剧情模式.md`（2610 行，§6.4 老板原话「一台机体只能带**一个上级** / **三个**下级」）。

### 5.11 联机（局域网）

- 房间：`LanRoom` —— **房间号 ↔ 端口 / 密码 / 广播报文 的唯一真源**；`LanBrowser` 负责发现。
- ⚠️ **端口只由房间号「低两位」决定** ⇒ 广播包必须带**真实端口 + 发包方 IP**。
- ⚠️⚠️ **`set_broadcast_enabled()` 返回 `void`** —— 若写成 `var err := set_broadcast_enabled()`
  ⇒ **autoload 加载不了** ⇒ **末节静默被吃掉 = 假绿**。
- ⚠️ **密码不是安全**（局域网内明文）。
- ⚠️⚠️ **「双方卡着不动」= 两条独立断线**，**必须成对修**（`net_session.gd` 两处 `set_process(false)`）。
- ✅ **`NetProxyBody.interp()` 已有调用方**（2026-10-07 实测，**此前的"零调用方"是修好之前的状态**）：
  `main.gd:2229` 在 `_tick_remote_proxies()` 里 `p.interp(delta)`，由 `_process` 的 `Phase.FIGHT` 每帧调；
  守卫见 `suite_net_sync.gd:86-87`。⚠️ 但 `main.gd:2585-2586` 的历史注释仍写着"零调用方"（说的是当年那个 bug），**别照它下结论**。
- ⚠️ **双开两进程在本机跑不了** ⇒ **用户实机复测才是最终验收**。
- 死锁的根因形态：等待态**早退**挡住了真出口与 Esc 保险丝（**不含 `Stage.LAN`**）
  ⇒ 正解 = **超时纯函数** + 保险丝加 LAN。

### 5.12 演出 / 开场 / 播片

- 开场 CG：`assets/video/intro_op.ogv`（Ogg Theora）+ `IntroMovie` + 看门狗。
- 重力开场演出调整：`DESIGN-2026-10-01-重力开场演出调整.md`。
- **POD STRIKE**：`Mission.pod_strike` / `Phase.POD_STRIKE` / `_tick_pod_strike()`。
- ⚠️ **锁 BGM 要 `duplicate()` 再循环**，否则会**写穿**到对战（`lock_battle_track()`）。
- ⚠️ **9.5 km 与「仓占画面 40%」在几何上互斥**（只能二选一）。

### 5.13 换弹 / 读条 / 教学

- **滚动读条**：`LoadingScreen`（进战斗地图前的加载层 + 分阶段建图）；
  换弹与浮游导弹装填也有滚动读条（`suite_reload_gauge`）。
- **教学**：`scripts/flight/tutorial_director.gd`（`suite_tutorial`）。
- ⚠️ 读条界面有过"露底"问题：`DESIGN-2026-10-01-读条界面露底修复.md`。

---

## 6. 主菜单与流程（Stage 机）

`scripts/ui/main_menu.gd`：

```gdscript
enum Stage { MODE, BATTLE, SIDE, SUIT, TRAINING, ENEMY, DIFFICULTY, MAP,
             ENCOUNTER, LAN, SETTINGS, KEYS, BGM, FPV_CONFIRM, PASSWORD }
```

**两层架构**：

```gdscript
const MODE_GROUPS := [
    {"name": "对战模式",   "modes": [Game.MatchMode.VERSUS, Game.MatchMode.SQUAD], "lines": [...]},
    {"name": "剧情挑战",   "modes": [Game.MatchMode.CHALLENGE], "lines": []},
    {"name": "训练模式",   "modes": [Game.MatchMode.TRAINING],  "lines": []},
    {"name": "局域网联机", "modes": [Game.MatchMode.LAN],       "lines": []},
]
const BATTLE_GROUP := 0     # 「对战模式」在 MODE_GROUPS 里的下标 —— 唯一有子页的那一组
```

⚠️⚠️ **行数取 `MODE_GROUPS.size()`（4 组），不是 `all_modes().size()`（5 个模式）** ——
把 5 当行数用，排版会按 5 行去算 4 行，**最后一行会凭空伸到面板外面**。

**菜单是纯 `_draw()` 画的，只用键盘 / 手柄导航，没有鼠标 UI。**

⚠️ `Stage` 加子屏用 `*_SUB_*` 常量，**不加枚举值**；`_draw()` 只按 `stage` 分支
⇒ 摆 `stage` 验页时必须注明是**探针摆位**。

### 6.1 当前键位（**已按 `input_setup.gd` 的 `BINDINGS` 核对**）

**键鼠**：

| 输入 | 作用 |
|---|---|
| `S` / `↓` | 拉杆抬头（`pitch_nose_up`）—— 真实操纵杆约定 |
| `W` / `↑` | 推杆低头（`pitch_nose_down`） |
| `A` / `←` · `D` / `→` | 左 / 右滚转 |
| `Q` / `E` | 左 / 右偏航 |
| `[` / `]` | 收 / 加油门 |
| `Shift` | 加速 · `Ctrl` | 悬停 |
| **鼠标移动** | **弹道准星 + 准星罩住敌机即锁定**（**不碰机头姿态**） |
| 鼠标左键 | 当前武器（步枪 / 军刀，`X` 切换） |
| 鼠标右键 | 拦截来袭飞弹 |
| `空格` | 火神炮（按住）· `F` | 浮游导弹 |
| `R` | 换弹（**长按 0.6 s = 丢枪**，仅柯西） |
| `T` | 举盾 · `C` | 干扰弹 · `B` | 选来袭飞弹作拦截目标 |
| `Tab` | 切换目标 · `1`–`9` | 直选敌机列表第 n 架 |
| `X` | 切换武器 · `Z` | 变形（阿利宙斯，冷却 4 s） |
| `I` | 反转俯仰 · `V` | 回头看 · `Alt` | 锁定镜头 |
| `G` | 辅助驾驶（长按）· `U` | 修复 |
| `P` | 设置 · `Esc` | 暂停 |

**手柄**：左摇杆俯仰+滚转 / 右摇杆偏航+油门 / R2 主武器 / R1 火神炮 / L1 拦截（点按一发，
**按住 = 自动拦截**）/ L2 浮游导弹 / `A` 加速 / `B` 举盾 / `X` 换弹 / `Y` 悬停 /
十字键 ↑↓←→ 切换敌机 / 干扰弹 / 锁定镜头 / 切换武器 / `Back` 回头看 / `Start` 暂停。
⚠️ **`A` 长按 = 辅助驾驶开关**；**`B` 长按 = 丢枪**（因 `shield` 与 `reload` 都有一条丢枪路）。

⚠️ **改键位同步 5~6 张表**：`BINDINGS` / `KEY_LABELS` / `ACTION_NAMES` /
`MainMenu.KEY_GROUPS` / `InputSetup.HELP_SECTIONS` + 档位 + 存档夹取。
**漏 `KEY_GROUPS` ⇒ keybind 红；漏 `ACTION_NAMES` ⇒ 不报错也不红。**

---

## 7. 测试体系

### 7.1 入口与形态

- 入口：`tests/test_runner.tscn`（**场景**，不是 `--script` —— `--script` 不实例化 autoload，
  而 `Game` 是战斗系统的唯一真源，测不了它等于没测）。
- 表驱动：`tests/test_runner.gd` 的 `const SUITES`，**83 行**。
  每行 = `[路径, 显示名, 是否 async, 是否传 host]`。
  ⚠️ 后两项**不是多余的**：套件签名不统一（`Flight`/`Ballistics`/`Rig` 的 `run(t)` 只收一个参数，
  `Layout`/`Gamepad` 与其余是 `run(t, host)`），**写错会直接报 "Too many arguments"**。
- 断言库：`tests/t.gd`（`t.suite()` / `t.ok()` / `t.eq()` …）。
  ⚠️ **`t.suite()` 结算之前累积断言** ⇒ 新节要挂在 `run()` **最末**；**没有 `t.le`**。
- **两道保险**（都在 `t.gd` 末尾）：
  1. **单实例闸门** `T.guard_single_instance()`：检测到 GUI 版 Godot 或另一个测试进程在用这个工程就**拒绝运行**
     （起因：2026-09-20 那天"Godot 特别容易崩" —— 真相是**两个实例同时写 `.godot/`**，
     `global_script_class_cache.cfg` / `uid_cache.bin` / `imported/` 互相覆盖 ⇒
     autoload 与 `class_name` 解析不到 ⇒ 满屏 `Identifier not found: Game`。**不是显卡、不是内存**）。
     强行并行用 `--allow-concurrent`，**正解是工程副本**。
     ⚠️⚠️ **2026-10-07 实测：这道闸门当前是 no-op（形同虚设，读不到任何 Godot）** ⇒ 见 §7.7。
  2. **坏套件不拖垮整轮** `T.run_suite()`：某个套件编译不过**只记一条 FAIL 并点名**，其余照跑，
     报告末尾单列「未能执行的套件」。（以前是无条件顺序调用，任何一个坏掉就整轮中断。）

### 7.2 ★ 判据口径（**必背**）

**判据 = 四件套，缺一不可**：

```
① 汇总行         N PASS / M FAIL
② 节数           ^---  开头的行数
③ 尾部条数表      「按套件断言条数」那一张表
④ 四类报错计数    Parse Error / SCRIPT ERROR / SHADER ERROR / Failed to load
```

⚠️ **不看退出码**（各套件写法不统一）。
⚠️ **「0 FAIL」≠ 跑完** —— 也可能是 `--only` 没匹配上（`--only` 匹配的是**路径子串**）。
⚠️ 日志先 `\r\n` → `\n` 再 grep。

**当前基线**：`13337 PASS / 0 FAIL / 539 节 / 83 套件 / 四类报错全 0`

**历史**：949 → 1108 → … → 1620 → 1763 → … → 13287（★63-13）→ 13321（★63-14）→ 13337（★63-15）。
⚠️ **总数会变**：`t.gd` 会打"按套件断言条数表"。"总数少了 100"未必是你干的 —— 先看那张表。

### 7.3 套件命名约定

⚠️⚠️ **按主题命名，不按轮次命名。** 这个仓库**有并行会话**，两边都按"轮次"占编号时**撞过一次**
（本套件第一版叫 `suite_round22.gd`，把对方同编号的教学套件整个覆盖掉了）。

- `suite_round14..21.gd` 是历史遗留的轮次名（早期没有并行），**不要再用轮次命名**。
- 新套件一律语义名：`suite_ground_guard` / `suite_magnifier` / `suite_hud_instruments` / `suite_lan_room` …

### 7.4 怎么加一个套件

1. 写 `tests/suite_<语义名>.gd`，暴露 `static func run(t, host) -> void`（或 `run(t)` 视签名）；
2. 在 `test_runner.gd` 的 `SUITES` **加一行**（⚠️ **显式注册**，加文件不会自动被发现）；
3. ⚠️ 只加那一行，**别在别处动 `test_runner.gd`**（共用文件）；
4. 跑 `--only=suite_<语义名>` 自检。

### 7.5 探针（`tools/`）

工程的一条硬习惯：**猜错了要留下探针。**

- 改数值/机制之前**先量，别猜**。
- 主流做法是**每轮写一个专用探针**（如 `tools/_r63_15_warn_shot.gd` + `.tscn`），
  而不是复用老探针 —— 因为专用探针能**冻结世界 / 配负对照 / 打判据读数**。
- 历史探针（`tools/probe_ai_dive.tscn` / `probe_aggression.tscn` / `probe_ttk.tscn` /
  `probe_twin.tscn` / `probe_model.tscn` / `probe_stress.tscn` / `probe_replay.tscn`）多数仍在，
  但**不一定跟得上现在的代码**，用前先核。

### 7.6 ⚠️ 无害噪声（**别去"修"**）

跑测试时下列输出是**正常**的，不要当成 bug：

- `Leaked instance dependency`
- `Pages in use exist at exit in PagedAllocator`
- `ObjectDB instances were leaked at exit`
- `N resources still in use at exit`
- `Unicode parsing error` —— 单实例闸门读 `tasklist`，中文 Windows 是 GBK 编码
- `Parameter "material" is null.` —— **每条 = 一个会造真 3D 机体的节**

### 7.7 ⚠️⚠️ 单实例闸门当前**失效**（2026-10-07 实测，形同虚设）

`T.guard_single_instance()` **读不到任何 Godot 进程** ⇒ **永远返回"放行"**。根因是三层，全部可复跑：

1. **`tasklist` 把镜像名截断到 25 字符** ⇒ `Godot_v4.7.1-stable_win64.exe`（29 字符）与
   `Godot_v4.7.1-stable_win64_console.exe`（37 字符）**都显示成** `Godot_v4.7.1-stable_win64`。
   （实测：`tasklist /NH` 该行全长 76 字符、名字段正好 25 字符，`cat -A` 可验。）
2. **闸门的判据根本没机会命中**：`l.contains("_console")` / `l.contains("win64.exe")` ——
   截断后的字符串**两个都不含** ⇒ `gui=0` / `console=0` ⇒ 闸门认为"本机没有 Godot"⇒ 放行。
   实测（3 个 Godot 同时活着：1 个项目管理器 + 1 个测试壳 + 1 个引擎子进程）同款解析仍得 `gui=0 console=0`。
3. **换成 CSV 也修不干净**：`_console.exe` 是 **198 KB 的壳**，它 **spawn 真正的引擎**
   `Godot_v4.7.1-stable_win64.exe` 当**子进程**（实测 PPID 吻合：壳 57068 → 子 31928）
   ⇒ 照现有"`gui>0` 就拦"的规则，**每次跑测试都会拦自己**。⇒ 现有**计数模型本身**就是错的。

⇒ **现实含义**：编辑器 / 游戏开着时 `test_runner` **也会照跑**，而"两个实例同写 `.godot/`"
**正是 §7.1 那条事故的成因**。⇒ **当前唯一可靠的护栏是人的自觉**（跑前自己 `tasklist` 看一遍）。

**候选修法（未落地，待拍板）**：

- 改用 **`tasklist /NH /FO CSV`**（实测 **不截断**，带全名）取代表格格式；解析要去掉外层引号；
- 计数模型改成：**测试实例数 = `…_console.exe` 的个数**；
  **真·GUI 数 = `…win64.exe` 的个数 − `…_console.exe` 的个数**（每个壳恰好带一个引擎子进程）。
  实测当前 = 2 − 1 = **1**（那 1 个正是项目管理器）⇒ 判据成立。
- ⚠️ `wmic` 在本机被安全策略拦掉、`reg.exe` / `sc.exe` 同样 ⇒ **拿不到命令行**，
  所以"按命令行分辨 `test_runner.tscn`"这条更稳的路**当前走不通**。

⚠️ 本条**只做了诊断，没有改 `t.gd`**（它是共用文件）—— **改动需用户拍板**。

---

## 8. 工程铁律

> 每条都对应一个**真实事故**。这一节是从 63+ 轮里筛出来的，**每一条都值得背下来**。

### 8.1 输入 / UI 铁律

1. **绑了键一定有读取点；写了读取器也一定有触发源。**
   两个方向都栽过：`switch_weapon()` 写好了但没在输入循环里读（"按 X 没反应"）；
   `_hold_threat_pad` 配好了却从来没被 `tick()` 过。
   **死代码的危险不是多几行，是让后一个人以为功能已经做了。**
2. **改键位必须重跑 `tools/gen_input_map.gd`；一个键不得同时属于两个动作。**
   `project.godot` 的 `[input]` 是**固化副本**，改表不会自动更新。当年 `fire_missile`
   同时留着 F 和 Q，玩家按 F 举盾会**同时打出导弹**。
3. **说明书（`HELP_SECTIONS`）必须和"代码里真的读了什么"一致。**
   判据不是"绑了什么"，而是 `PlayerController._read_weapon_input()` **真读了什么**。
4. **⚠️ 一键两义要查全** —— 丢枪有**两条**路：`reload`（`R`/`Y`）**和** `shield`（`T`/`B`）长按 0.6 s。
   ⇒「长按 T 丢枪」是真的；帮助表里手柄列写"长按 B"**是对的**（因为它读 `shield`）；
   ⇒ **删掉那一支后必须同步改文案**（漏了**不报错**）。
5. **「给手柄看的信息」绝不能长在鼠标分支里**（§5.7）。发作过两次。
6. **`draw_string(..., HORIZONTAL_ALIGNMENT_RIGHT, -1, ...)` 的对齐参数会被忽略**
   （宽度传 −1 时）—— 右对齐必须自己 `get_string_size()` 量宽度再往左挪。
7. **数字只能有一个真源**（`suit_profile` / `UILayout` / `sound_bank` / `difficulty` / `map_def`）。
8. **加行 / 换序**：行下标提成 `const`，**只有一处真源**。

### 8.2 引擎行为铁律

9. **`process_mode` 是继承的。** `get_tree().paused = true` 对 `INHERIT` 子节点**无效** ——
   要停的显式标 `PAUSABLE`，要活的显式标 `ALWAYS`。**回归测试量位移，不看标志位。**
10. **已释放的实例不能直接赋给带类型标注的变量**（会抛
    `Trying to assign invalid previously freed instance`）。正确姿势：
    先取**无类型**变量 → `is_instance_valid` → 再 `as` 转。
11. **新增 `class_name` 之后先 `--import`**（否则报"找不到类"，看起来像自己写错）。
12. **`bool` 赋给 `int` 时 `true` 静默变成 `1`** ⇒ 三态不能用 `bool`（城市点灯就是这么改的）。
13. **`fov` 是垂直 FOV**（§5.2）；**headless 视口是正方形**。
14. **裸 `.gd` 当场景跑会挂住** ⇒ 用 `.tscn` 包。
15. **`--check-only --script` 解析不了 autoload**；跨文件引用走 `preload`，**不走 `class_name`**。

### 8.3 并行会话纪律（**代价最大的一节**）

**事实**：工程**没有 git**，而**经常有两个 AI 会话同时改它**。

**动手前的三步体检**：

```bash
# 1) 热点文件的 mtime（连续 10 分钟没人动 = 可以开工）
cd /c/Users/MSIPC/Documents/gundam && ls -l --time-style=+%H:%M \
   scripts/flight/player_controller.gd scripts/ui/hud.gd scripts/autoload/input_setup.gd README.md

# 2) 有没有人在跑
#    Windows 上任务管理器 / `tasklist` 看 godot;  再看最近 15 分钟内被改的文件

# 3) 工作目录里的旁证（另一个会话的日志会落在自己的工作区）
```

**并行的五条约定**（都是血换来的）：

1. **一个功能一个 suite 文件**，且**按主题命名**（§7.3）—— 共用 suite 文件 = 互相覆盖。
2. **不要整文件重写 `README.md`**（4518 行）—— 双方各改一段时整文件重写必然吞掉对方。
3. **`test_runner.gd` 是共用文件**：只加一行 `SUITES` 表项，别在别处动它。
4. **总数变了先怀疑并行**，不是自己的代码。
5. ⚠️⚠️ **别人跑回归时别改源码** ⇒ 跑前 / 跑后各取一份 **md5 快照**，查窗口内的 `M/A/D`。
   工程里有现成脚本（工作区 `_r63_15_snap.py` / `_r63_15_window.py`，逐文件 md5 + M/A/D 对账）。

⚠️ **`project.godot` 会被编辑器自己重写**（打开编辑器就重新序列化一次）⇒ 它的 mtime 变了
**不等于**有人在改键位。判据是看 `[input]` 段里那几条绑定**还在不在**。同理 `export_presets.cfg`。

### 8.4 改码 / 证据铁律

16. **改前备份 + md5 闸门 + 读后被改就中止**（没有 git，md5 是唯一回退）。
17. **改码一律用 Python 脚本**，`assert count == 1`（锚点唯一），**断言先于落盘**，落盘后核查无关改动。
18. **`size` 不变型改动要把它当判据用**（如"告警→警告"两个 3 字节 CJK 对调 ⇒ `size` 必须一字不变）。
19. **负对照必须精确咬住**：每条 NC 只该红它该红的那几条；**回滚后所有文件必须与金标 md5 逐位一致**。
20. **负对照的最高形态**：**判决行本身**要在负对照下能读 **FAIL**，否则「PASS」可能只是「恒 PASS」。
21. **改「玩家可见的字面量」⇒ 收尾必须出真机图**（且必须查全**耦合点**：
    产出方 + 上色匹配 + 测试匹配 + 探针 `WANT`）。
22. **没分清「仪器 vs 产品」之前不许改产品。**
23. **读数型判据要先报不确定度**：「差 ≤ 红线」型判据必须先报 **± SE**（`σ√2/√n`，**n 得 200+ 对起步**）。

---

## 9. 编辑与夹具规矩

### 9.1 行尾（⚠️ 混用！）

**CRLF 文件**（改它们**必须**走 `io.open(..., newline='')` + 前后各断一次
`raw.count(b'\n') == raw.count(b'\r\n')`；**直接用写文件工具会把整文件洗成 LF**）：

```
scripts/ui/hud.gd                （336976 B / crlf = 6078）
scripts/main.gd
tests/test_runner.gd
tests/t.gd                       （实测全 CRLF / 501 行 —— 断言的唯一真源，改它同样不能洗成 LF）
tests/suite_fx_plume.gd
tests/suite_abilities.gd
scripts/data/map_def.gd
README.md
```

**LF 文件**（其余全部，例如 `player_controller.gd` / `suite_ground_guard.gd` / `net_session.gd` /
`main_menu.gd` / `suite_lan_room.gd`）。

**查法**：

```bash
python -c "raw=open('文件','rb').read(); print(len(raw), raw.count(b'\r\n'), raw.count(b'\n'))"
```

### 9.2 改码脚本模板

```python
import io
p = r"C:/Users/MSIPC/Documents/gundam/scripts/....gd"
s = io.open(p, encoding="utf-8", newline="").read()          # ⚠️ newline="" 保住 CRLF
old, new = "...", "..."
assert s.count(old) == 1, "锚点不唯一：%d" % s.count(old)      # ⚠️ 先断言
if CRLF: assert s.count("\r\n") == 期望值
out = s.replace(old, new, 1)
assert len(out.encode("utf-8")) == len(s.encode("utf-8"))     # 视改动类型而定
io.open(p, "w", encoding="utf-8", newline="").write(out)      # ⚠️ 后落盘
```

### 9.3 GDScript 语法陷阱

- **中文串里嵌 ASCII 双引号会坏解析** ⇒ 内层一律用「」。
- **`%` + 中文标点会炸，而断言照样 PASS**（静默！）。
- **嵌套遮蔽同名变量 = 整套件 Parse Error**。
- **`Variant` 推断警告会变成 Parse Error** ⇒ 显式标类型。
- ⚠️ **取函数体的终止符（`_body()` 那类取体器）要一次找全
  `func` / `static func` / `const` / `var` / `class`** —— 只找 `"\nfunc "`
  会把函数体吞到下一个 `static func` 上 ⇒ **假红**。
- 多行 `print` 折行时 `%` 必须**在括号内**（否则 **Parse Error**）。

### 9.4 编辑次序

**先就地补注、再插块。** 反过来会在插块后让锚点漂移。

### 9.5 探针纪律（出图 / 量测）

⚠️ **出图探针有"七坑"**（`notes/09` 有全文）：

1. `set_process(false)` **停不住子节点** → 要**递归**关；
2. 隐藏会**翻渲染历史**；
3. 相机挪位要**等 40 帧**；
4. 探针是 **root** 就会**先跑** ⇒ `process_priority = 1000`；
5. `get_tree().paused = true` **冻不住机体**（§8 铁律 9）⇒ ★63-15 实测要**递归关 1058 个后代**、
   **跳过 HUD 子树**（HUD 自己 `ALWAYS`，得继续 `_process` → `queue_redraw()`）；
6. **动态行程不能被镜头锁住判据物**；
7. ⚠️ **主视口抓帧可能与你设的相机无关 ⇒ 改用 `SubViewport`**。

其它必须记住的：

- `RENDER_TOTAL_PRIMITIVE_COUNT` **不存在** ⇒ 用 `_PRIMITIVES_IN_FRAME`。
- **仪器自检不能用"全屏逐字节相同"**（HUD 自己还在动，**永远不过**）⇒ 用**基线静止像素掩码**。
- ⚠️ **HUD 提示行的显示窗只有 `SYSTEM_EVENT_SECS` = 1.8 s** ⇒ 抓帧必须**立刻**，不能先等。
- 探针要**托住动态判据物**并注明"这是摆位"。
- 真机裁图用**归一化矩形 × 截图尺寸**。
- `scipy.ndimage.label` 之后**必须用 `bincount` + `find_objects`**，
  **别按分量数循环 `lb == i`**（噪声分量上万 ⇒ 自拖死到 `SIGTERM`）。
- ⚠️ **Pillow 默认位图字体没有中文字形** ⇒ 用 `C:/Windows/Fonts/simhei.ttf`
  （但 **simhei 缺 `−`(U+2212) 字形** ⇒ 用 ASCII `-`）。

---

## 10. 一轮工作的标准流程

### 10.1 六段式（项目惯例）

用户交付验收沿用的结构：

```
① 根因（为什么会这样 —— 台账/实测，不是"我觉得"）
② 回归标准（判据是什么、怎么算 PASS）
③ 证据（读数 / 图 / md5）
④ 全量回归（N PASS / M FAIL / 节数 / 四类报错）
⑤ 交付物：判据图 + 记忆 + 技能 + 报告
⑥ present_files
```

### 10.2 一轮的动作序列

```
0) 体检并行（§8.3）
1) 摸现场：grep 定「文件:行」；把影响面**枚举成机械证据**（可复跑的 grep），不要靠"我扫过了"
2) 备份：%LOCALAPPDATA%\Temp\gundam_bak\r<轮号>\（⭐ 绝对路径）+ 改前 md5 快照
3) 写补丁脚本：Python + assert count==1 + 断言先于落盘
4) 落盘后：核 md5、核 size、核 CRLF、窗口对账（M/A/D）
5) 判据：
   · 单套件（改动相关的那几个）
   · **负对照**（至少一条能精确咬住的）
   · 玩家可见改动 ⇒ **真机图**
   · 最后 **全量回归**
6) 出交付四件套到 `_deliver/NNN_*`
7) 更新记忆（`notes/NN` + `notes/23_轮次账` + 逐轮 `YYYY-MM-DD.md` + `MEMORY.md`）
8) present_files
```

### 10.3 交付四件套命名

```
_deliver/
├── NNN_主说明_轮<轮号>_<主题>.md        ← 零·一句话结论 / 根因 / 改动 / 判据 / NC / 遗留 / 交付物
├── NNN_源文件md5_轮<轮号>.txt            ← 改前改后 md5 + size + 行尾 + 范围对账 + 备份清单
├── NNN_判据运行日志_轮<轮号>.txt          ← 原始日志分区汇编（逐套件 / 全量 / NC / 真机 / 对账）
└── NNN_判据图_轮<轮号>_<主题>.png         ← 1600×1010 拼图：全屏 + 放大格 + 读数台
```

⚠️ **编号先 `ls _deliver` 核最大号**（有并行会话，编号会撞）。
**当前最大编号：227**（★63-16）。

### 10.4 工作记忆在哪

```
C:\Users\MSIPC\WorkBuddy\2026-09-25-17-05-06\.workbuddy\memory\
├── MEMORY.md                  ← 长期索引（⚠️ 已顶到 ~16.8 KB，注入时会被截断）
├── notes/
│   ├── 01_回归_套件_编辑文件的坑.md
│   ├── 02_UI风格闸门_输入路由.md
│   ├── 03_音频_开场动画.md
│   ├── 04_相机标定_探针纪律.md
│   ├── 05_中央屏_几何与线稿.md
│   ├── 06_喷口与尾焰.md
│   ├── 07_冲刺转身_与形态收起.md
│   ├── 08_阿利宙斯_匀速弹速与蓄力激光炮.md
│   ├── 09_判据图通用坑_与工程规矩.md
│   ├── 10_浮游飞弹尾迹长度_烟带.md
│   ├── 11_性能_多发导弹与多台机体.md
│   ├── 12_菜单文案_撤绘制留数据.md
│   ├── 13_半截重构_调用方与套件.md
│   ├── 14_剧情关数据_敌我编制与死拍子.md
│   ├── 15_实机演出段_与可见窗口.md
│   ├── 16_弹道_提前角与辅助瞄准.md
│   ├── 17_联机_断线与房间密码.md
│   ├── 18_光束军刀_动作幅度与屏幕量法.md
│   ├── 19_改成品glb动画_无Blender幅度重做.md
│   ├── 20_一批bug的设计排查_落点索引与陷阱.md
│   ├── 21_放大镜_子视口_帧时读数台与真机取证.md
│   ├── 22_其它子系统细则.md        ← ★ 原样全文（含实测数与推导）
│   └── 23_轮次账.md                ← ★ 轮号 / 交付编号 / 关键读数
└── YYYY-MM-DD.md              ← 逐轮工作日志（append-only）
```

⚠️ **`notes/23_轮次账.md` 是查「哪一轮改了什么」的第一入口。**
⚠️ **`notes/22` 是"其它子系统"的全文** —— `MEMORY.md` 里那些索引行是它的缩略版。

---

## 11. 故障速查

| 现象 | 最可能的根因 | 去哪看 |
|---|---|---|
| 按某个键没反应 | 绑了键但**没有读取点**（或反过来） | §8 铁律 1 |
| 按一个键同时触发两件事 | `project.godot` 里旧绑定没剪 | 重跑 `tools/gen_input_map.gd`；`suite_input` 会红 |
| 说明书印着一个按不出来的键 | `HELP_SECTIONS` 与 `PAD_BINDINGS` / 实际读取点不一致 | `input_setup.gd`；§8 铁律 3 |
| **手柄玩家看不见某块 HUD** | 它画在 `cursor_seen` 门控里 | `_draw_aim_cursor()` vs `_draw()` 无条件分支；§8 铁律 5 |
| 按 Esc 遮罩出来了但战斗还在继续 | `process_mode` 继承：main 是 ALWAYS | 给要停的标 `PAUSABLE`；§8 铁律 9 |
| 右对齐文字冲出屏幕 | `draw_string` 宽度传 −1 时对齐被忽略 | 自己 `get_string_size()` 量宽；§8 铁律 6 |
| `Trying to assign invalid previously freed instance` | 把已释放实例赋给带类型标注的变量 | 先取无类型 → `is_instance_valid` → `as`；§8 铁律 10 |
| "找不到类 `XxxYyy`" | 新 `class_name` 没扫 / **或某个脚本解析失败（真凶常在别处）** | 先 `--import`；再查重复局部变量 |
| 测试总数莫名少一截 | **另一个会话**在并行落地 / 某套件提前退出 | `t.gd` 的分套件表；§8.3 |
| `--only=xxx` 出来 `0 PASS / 0 FAIL` | 子串没匹配上（匹配的是**路径**） | 用完整套件名 |
| `test_runner.gd` 整个解析失败 | 某个 suite 语法错（并行会话改到一半） | 用单套件 `--only` 绕开 |
| 某个套件报 `FAIL [套件缺失]` | 整块编译不过 | **查 Parse Error** |
| 编辑器 UI 花屏 / 关不掉 | D3D12 后端（引擎 bug） | 别写 `rendering_device/driver.windows` |
| 截图全黑 | 加了 `--headless`（dummy 渲染器） | 去掉 `--headless` |
| 敌机自己扎海 | AI 避地链路 | `tools/probe_ai_dive.tscn` |
| 计数型红（`got=7 want=8`） | 台账常量与源码实际个数对不上 | **别顺着调数** ⇒ 拿 `gundam_bak/` 副本同口径对账 |
| 轨道图里出现了海和岛 | `SPACE` 没加进 `_map_stage_terrain()` 的 `match`，落进 `_` 兜底 | `map_def.gd`；§4.6 |
| 某台新机体"能用但用错东西" | `by_id()` / `id_name()` / `kind_for_suit()` / 编队池 **四处漏改** | §4.5 |
| 战斗一响就往对战里串 | 锁 BGM 没 `duplicate()` | `lock_battle_track()`；§5.12 |
| 拿到的机体比简报里说的快/慢 | 只改了 `enemy_suit`，没改 `waves[].suit` / `comms.RADIO` | §5.10 四件套 |

---

## 12. 当前遗留欠账

### 12.1 需用户拍板

| # | 事项 | 说明 |
|---|---|---|
| 1 | **★63-15 的三条候选** | (a) 保持现状（`PULL UP` 与"地形警告"两条并行）(b) 把门口径提到与 `PULL UP` 同源（`2.5 → 2.6` + 420 m 余量）(c) **撤掉**「地形警告 · 拉起」这条 |
| 2 | **军刀存在感** | "切武器 + 锁定 + 进 1400 m"三步太远，试玩者没走到 ⇒ HUD 常驻就绪指示 / 进射程播报 / 开局教学 |
| 3 | **摇杆布局开关**（"空战 / 射击"） | 试玩者想左右摇杆对调；会断掉与键盘 A/D+Q/E 的对应 |
| 4 | **"准星感觉有点偏"** | **不能凭猜改**：先写探针把 `aim_point()` 投影回屏幕与光标比对，量出差多少 |
| 5 | **键位自定义 UI + 存档** | 大工程 |
| 6 | **2v2 / 1v多** | 大工程 |
| 7 | **剧情第三章** | 用户已明确"暂不做" |
| 8 | **柯西后刃长度** | ★63-8 遗留，建议 **9.0** |
| 9 | **剧情模式的版本号口径** | 三套并存（§1.4） |

### 12.2 已知缺陷 / 待核

| # | 事项 | 位置 |
|---|---|---|
| 1 | ⚠️⚠️ **`Settings.begin_isolated()` 的隔离仍有洞** | ★63-11 收口挂起：`full2` 趟暴露真档 `settings.cfg` 在隔离生效期间被写过一次（★63-12 趟碰 `keybinds.cfg` ⇒ 间歇性）⇒ **判据「跑前跑后 md5 相同」是假绿，不许当证据**。`notes/01` |
| 2 | ⚠️ **`suite_ground_guard.gd` 行 462 的断言文案仍写「地形告警」** | 产物说"警告"、测试标题写"告警" —— ★63-16 范围所致，**不影响行为** |
| 3 | ⚠️ **其它子系统约 24 处「告警」文案 + `flight_assist.gd`/`player_controller.gd` 约 40 行注释 + 5 份设计文档 38 行** | 同上 |
| 4 | **`missile_ribbon.gd` 的 `MAX_POINTS` 注释 `474` 过期** | 待订正 |
| 5 | **核心形态 `rifle_magazine = 8` 是死赋值**（被后面统一的 6 覆盖） | `suit_profile.gd` |
| 6 | **模型管线"扁平件"判据会误删尾翼** | 必须带 `--keep-all` 跑 |
| 7 | **8% 植被**（MultiMesh 撒草） | 从第十三轮欠到现在 |
| 8 | **拦截图形的滚转符号方向没有实测证据** | HUD |
| 9 | ✅ **已销案**：`NetProxyBody.interp()` 早就有调用方（`main.gd:2229`，`suite_net_sync.gd:86-87` 有守卫）。原记录记的是**修好之前**的状态 | 2026-10-07 实测，见 §5.11 |
| 10 | **`README.md` 大段过期** | 基线 / 规模 / 键位都旧（§1.4） |
| 11 | ✅ **已销案**：`MEMORY.md` 已从 17010 B 降到 **10824 B**（把「其它子系统」整块**原样搬迁**到 `notes/24_子系统索引.md`，15 条一字未改）⇒ 注入不再被截断 | 2026-10-07 |
| 12 | **`notes/17` 判据 5/7 的联机双进程** | 本机双开跑不了 ⇒ 需用户实机复测 |
| 13 | 工程根堆积 **1916 项 / 约 1.4 GB** 历史临时产物（`_*.txt` / `_*.png` / `_r*_shots/` 等，见 §3.2） | 可清理，但**先确认没有别的东西引用**；**用户拍板后再做** |

### 12.3 建议的下一步

1. **跑一次全量回归**（★63-16 改名那轮只跑了单套件，全量没验过）。
2. 清一次工程根的历史临时文件（**用户拍板后再做**）。
3. ~~`MEMORY.md` 的"搬迁"~~ —— **2026-10-07 已做**（见 §12.2 第 11 条）。
4. 从 §12.1 里挑一条需拍板的推进。

---

## 13. 文档地图

### 13.1 工程内

| 文档 | 行数 | 讲什么 |
|---|---|---|
| `README.md` | 4518 | 主文档。**⚠️ 多处过期**；有价值的是 §14「历轮修掉的真 bug」、§9 目录结构、§10 设计决策 |
| **`HANDOFF.md`（本文）** | — | **给新会话的总入口** |
| `HANDOFF-旧-2026-09-20（停在第十五轮）.md` | 455 | 旧版（基线 1763）；**十二条铁律与故障速查的原始出处** |
| `GUNDAM_HANDOFF_2026-09-21.md` | 372 | 更旧的交接（城市重做那轮） |
| `GUIDE-2026-09-22-Blender骨骼与动作.md` | 625 | Blender 绑定 / 动作制作指南 |

**设计文档（`DESIGN-*.md`，共 13 份 / 12,907 行）**：

| 文档 | 行数 | 主题 |
|---|---|---|
| `DESIGN-2026-09-21-锁定与手感优化.md` | 1612 | 锁定 / 手感 / **HUD 仪表（姿态仪 / 高度带 / 告警状态机 / 语音通道）** |
| `DESIGN-2026-09-22-1.3测试版.md` | 1170 | 1.3 测试版规划 |
| `DESIGN-2026-09-23-画质材质优化.md` | 1671 | 画质 / 材质 |
| `DESIGN-2026-09-27-达沃重制.md` | 461 | 达沃地图 |
| `DESIGN-2026-09-27-达沃重制-详规.md` | 637 | 同上（详规） |
| `DESIGN-2026-09-27-奥恩贝利台场重制-详规.md` | 663 | 奥恩贝利 |
| `DESIGN-2026-09-27-其余三图重制.md` | 451 | 其余地图 |
| `DESIGN-2026-09-28-剧情模式.md` | **2610** | ★ **剧情模式完整设计**（经济系统 / 改装 / 三章 / 任务目标） |
| `DESIGN-2026-09-28-城市肌理-详规.md` | 434 | 城市 |
| `DESIGN-2026-10-01-读条界面露底修复.md` | 396 | 读条 |
| `DESIGN-2026-10-01-重力开场演出调整.md` | 450 | 开场演出 |
| `DESIGN-2026-10-03-七项问题排查与设计.md` | 866 | 七项排查 |
| `DESIGN-2026-10-04-六bug五设计排查与设计.md` | 1486 | ★ 六 bug + 五设计（★63-9 的源头） |

### 13.2 工作区（工程外）

| 位置 | 讲什么 |
|---|---|
| `…\.workbuddy\memory\MEMORY.md` | 长期索引（标识符 / 常量名 / 陷阱触发词） |
| `…\.workbuddy\memory\notes\01..23` | **逐块细则**（实测数 / 推导 / 坑） |
| `…\.workbuddy\memory\notes\23_轮次账.md` | **轮号 / 交付编号 / 关键读数（查"哪一轮改了什么"的第一入口）** |
| `…\.workbuddy\memory\YYYY-MM-DD.md` | 逐轮工作日志 |
| `…\_deliver\NNN_*` | 历轮交付四件套（当前最大 227） |
| `…\_deliver\shots_r*` | 历轮真机原图 |

---

## 14. 第一个 15 分钟

```bash
# 0) 体检并行（§8.3）
cd /c/Users/MSIPC/Documents/gundam
ls -l --time-style=+%m-%d_%H:%M scripts/flight/player_controller.gd scripts/ui/hud.gd \
      scripts/autoload/input_setup.gd README.md
#   再确认没有别的 Godot 进程在跑

# 1) 拿基线（必须 0 FAIL 才能动手）
"C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" --headless \
    --path "C:/Users/MSIPC/Documents/gundam" res://tests/test_runner.tscn > /tmp/base.log 2>&1
tr -d '\r' < /tmp/base.log | tail -5
#   期望：13337 PASS / 0 FAIL；再看节数（539）、条数表、四类报错（全 0）

# 2) 读这四份就够开工：
#    · 本文 §4（架构 + 数据真源）
#    · 本文 §8（铁律）
#    · .workbuddy/memory/notes/23_轮次账.md（最近改了什么）
#    · .workbuddy/memory/notes/22_其它子系统细则.md（动某块之前先读那一块）

# 3) 要改东西之前：备份到 %LOCALAPPDATA%\Temp\gundam_bak\r<轮号>\（⭐ 绝对路径，没有 git！）
```

**三条最容易上手就踩的**：

① 别在 `project.godot` 里手改键位（改 `input_setup.gd` 再重跑 `tools/gen_input_map.gd`）；
② 别把 HUD 的新东西画进 `_draw_aim_cursor()`（手柄玩家看不见）；
③ 改完跑测试**看汇总行**，**别信退出码**。

---

*本文所有路径、行数、命令与数字均来自 2026-10-07 的磁盘实测。与磁盘冲突时，以磁盘为准。*
