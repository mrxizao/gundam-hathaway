# GUNDAM 会话交接（2026-09-21 · 城市重做 / 尺度放大 / 多人玩法）

> **写给谁**：接手这个工程的**下一个 AI 会话**（或三个月后的老板）。
> **写法约定**（沿用它原来的 `GUNDAM_HANDOFF.md`）：只写**能验证的事实**（路径 / 命令 / 常量 / 实测数字）。
> 凡是"我记得好像是"一律标 ⚠️ 或写"待核"。**与磁盘冲突时，永远以磁盘为准。**
> **本文日期**：2026-09-21 02:40 成稿。
> **验证方式**：无头 Godot 4.7.1，见 §6 —— 本轮**全量入口几乎跑不完**（原因见 §7），数字都来自**独立探针入口**。

---

## 0. 三十秒速览

| 项 | 值 |
|---|---|
| 是什么 | 《机动战士高达 闪光的哈萨维》题材的 3D 空战原型（Ace Combat 风格缠斗 + 训练靶场） |
| **boss 工程（真源）** | `C:\Users\MSIPC\Documents\gundam` |
| **本会话的隔离副本** | `C:\Users\MSIPC\Desktop\aiwork\city-odaiba` |
| 引擎 | Godot 4.7.1 stable（`C:\Users\MSIPC\Desktop\Godot_v4.7.1-stable_win64_console.exe` = 无头；`..._win64.exe` = GUI） |
| 本轮完成 | ① 奥恩贝利城市重做成台场格局 ② 全部地图 ×2.3 ③ 奥恩贝利改"死城 / 阴天黄昏" ④ 1v1 移除量产机 ⑤ 耐久 ×1.60 ⑥ **多人玩法规则 + 菜单 + 出生逻辑** |
| 本轮未完成 | **多人同乘的"后座输入中转"**（§5.5，必须两台机器才能验） |
| 测试（我的部分） | 多人 **144 PASS / 0 FAIL**；城市+尺度 **727 PASS / 2 FAIL**（那 2 条是并行会话的，§7） |

**最要紧的三句话**：

1. ⚠️ **这个工程此刻有另一个 AI 会话在并行编辑**。本会话被它的进程清掉 **10 次以上**（`EXITCODE=-1`、无汇总行）。动手前先看 mtime 与进程。
2. ⚠️ **并行会话正在同一条代码线上**（踏板 / 后座 / 编队乘板 —— `suite_squad_ride` 那批）。多人玩法的"同乘"与它**共用同一片代码**，改动前务必先同步、后动手。
3. ✅ 本轮所有改动**都已落进 boss 工程**（§8 有逐项核查清单），副本只是我的隔离工作区。

---

## 1. 本轮六件事 · 一页速查

| # | 事 | 关键文件 | 判据 |
|---|---|---|---|
| 1 | 奥恩贝利城市重做成**台场格局** | `scripts/world/world_builder.gd` | `suite_round20` 的"死城地图"组（**242 条**） |
| 2 | **全部地图范围 ×2.3**（只放大空间、机体数值不动） | `world_builder.gd` + `suit_profile.gd`(未动) | `suite_worldscale.gd`（**29 条**） |
| 3 | 奥恩贝利改**死城 / 阴天黄昏**（删尽灯光） | `world_builder.gd` + `time_of_day.gd` + `map_def.gd` | `suite_round` / `suite_round20` |
| 4 | 1v1 与敌人选择**移除古斯塔夫/梅萨**（小队保留） | `main_menu.gd` + `main.gd` | `suite_round17::_wiring()`（**30 条**） |
| 5 | **所有机体血条与护盾 ×1.60** | `suit_profile.gd`（**一个常量**） | `suite_abilities` 耐久组 |
| 6 | **多人（局域网）玩法**：同阵营+双量产 ⇒ 同乘一板 | `lan_plan.gd`(新) + `main.gd` + `main_menu.gd` + `net_session.gd` | `suite_lan_plan`(125) + `suite_lan_spawn`(19) = **144 条** |

---

## 2. 城市重做：奥恩贝利 = 台场式海湾城市

### 2.1 为什么要重做
第一版是**一张均质方盒网格**（16×16 个等高盒子 + 中心一根塔）。工程上没错，但它三样都不像城市：没有海岸线/水系/分区；每栋楼只有一个长方体；没有辨识物。用户的原话：**"建模太粗糙了"**。

### 2.2 参考：台场（お台場）
用户指定参考日本台场。落进代码时**平面照抄台场的地理关系，竖向按玩法尺度放大**（真楼 100~250 m 在 64 km 的图里连石子都不算）：

| 台场的结构 | 本工程的实现 |
|---|---|
| 东京湾 + 人工运河 | 挖出来的**海湾**（+Z 前景）+ 一条**穿城运河**；地形按海拔分色 |
| 彩虹桥 | 跨湾口的桥：桥面 **560 m**、主塔顶 **1680 m**，**可以从桥下钻过去** |
| 富士电视台本社 | 两塔 + 连廊 + **真的球体**瞭望室（`SphereMesh`，半径 135 m）|
| 1:1 高达立像 | 台座/腿/腰/胸/肩/头/天线（≈170 m）+ 背后 DiverCity 商业楼 |
| 东京 Big Sight | 四塔 + **倒锥**（`CylinderMesh.top_radius > bottom_radius`）|
| 百合海鸥号单轨 | 420 m 高架环线 + 墩（带碰撞）+ 绕圈列车（2 组 × 8 节）|
| 北商务/中商业/南低层 | 四圈分区 downtown/midtown/fringe/waterfront |

### 2.3 精细化具体加在哪
- 每格从 1 个盒子变成 **2~5 个体量**：裙房 + 塔楼 + 退台 + 顶冠 + 屋顶机房
- 配 **离散窗格**、坡屋顶、路面、护岸、公园树（**注：窗格与路灯已在第 3 件事里全部删掉**）
- **共用几何**：全城一份单位立方体网格 + 一个 `BoxShape3D`（第一版是 256 份 `BoxMesh`）

### 2.4 ⚠️⚠️ 最容易复发的坑：单位立方体的**绕序**
`_make_unit_cube()` 的六个面**必须逐面写对绕序**。第一版手工列六个面、靠"看着对称"推绕序，结果**六面全反**（法线朝内）⇒ Godot 默认背面剔除 ⇒ **每栋楼只剩一个可见面**，从任何角度看都像薄板，用户报的就是"**很多房子都是空的，你只做了一面**"。

现在的正确表（`world_builder.gd` 内，含交叉积验算注释）：

```gdscript
var quads := [
    [1, 0, 3, 2],   # -Z
    [4, 5, 6, 7],   # +Z
    [0, 4, 7, 3],   # -X
    [1, 2, 6, 5],   # +X
    [3, 7, 6, 2],   # +Y
    [0, 1, 5, 4],   # -Y
]
```

**复现工具**：`tools/cube_check.tscn`（把细高柱 / 薄板 / 大盒子各画一排，从斜上斜看 —— 绕序反了会看到三排全是单面）。

### 2.5 城市尺度常量（第 2 件事放大后）
| 常量 | 值 | 备注 |
|---|---|---|
| `CITY_GRID` / `CITY_FILL` | 16 / 0.62 | 街区 **4025 m**、占地 2496 m |
| `CITY_BAY_Z` / `CITY_BAY_WAVE` | 29900 / 3450 | 海湾岸线是条**正弦** |
| `CITY_CANAL_X` / `_HALF` / `_END_Z` | 14260 / 2070 / 26450 | 运河 |
| `CITY_MONORAIL_R` / `_Y` | 27600 / 420 | 单轨 |
| `CITY_BRIDGE_Z` / `_DECK_Y` / `_TOWER_Y` | 32200 / 560 / 1680 | 彩虹桥 |
| `CITY_PLAZA_R` | 11960 | 中央广场 |
| `CITY_GROUND_SEG` | 336 | 每格 ≈301 m |

**纯函数**（可直接单测）：`city_is_land()` / `is_water_at()` / `_city_landform()` / `city_lot_for()`。

---

## 3. 全部地图范围 ×2.3（只放大空间，机体数值一律不动）

### 3.1 数值
| 常量 | 旧 | 新 |
|---|---|---|
| `ARENA_RADIUS` | 28 km | **64.4 km**（一张图 129 km 见方）|
| `OCEAN_SIZE` | 160 km | 368 km |
| `LAND_SIZE` | 200 km | 460 km |
| `TERRAIN_DETAIL_SIZE` | 44 km | 101.2 km |
| `SPAWN_RADIUS` | 9 km | **20.7 km** |
| `TRAINING_PATROL_RADIUS` | 5.2 km | 11.96 km |
| `MAP_SCALE`（新增） | — | **2.3**（所有"跟地图走"的距离都乘它）|

**高度刻意不放大**（`PLAYER_START_ALT` 3200 / 云的三个高度带）：那些是垂直方向的量。

### 3.2 ⚠️ 两条必须知道的设计后果
1. **开局赶路 16 s → 约 36 s**（同样的速度飞更远的距离）。这是"只放大空间"的必然代价，已写进 `suite_round19` 的新契约（判据从 12~26 s 改成 **30~45 s**）。
2. **喷气槽从"能飞大半个战场"变成"一次冲刺"**：槽程占比 **71% → 22%**（梅萨 579 m/s × 8 s = 4.6 km，出击 20.7 km）。`suite_round19` 里有断言显式钉住"占比 < 35%"，免得以后有人以为是 bug 又调回去。

### 3.3 雾密度必须跟着调（**否则城市在雾里消失**）
`Environment.FOG_MODE_EXPONENTIAL` 的密度是"每米" ⇒ 地图放大 2.3 倍而密度不动，能见度等效缩水 2.3 倍。
实测：64 km 的图里 40 km 外的城市被雾吃掉九成以上。已按比例调低：

| 地图 | 旧 | 新 |
|---|---|---|
| 奥恩贝利（城市）| 0.000042 | **0.000019** |
| 艾尔斯岩（沙漠）| 0.000052 | **0.000023** |
| 废墟靶场 | 0.000040 | **0.000018** |

### 3.4 判据
`tests/suite_worldscale.gd`（**29 条**，三类）：
- **比例**：出击点 / 训练半径 / 城市各坐标都跟着 `MAP_SCALE` 同倍放大
- **连带项**：海面 / 地坪 / 细分网格 / 云场跨度必须比竞技场大出一截
- **不变量**：**机体速度、槽时长、导弹倍率一个字都没动** —— 这一组把"方案 B"写成了可执行判据

---

## 4. 奥恩贝利改"死城 / 阴天黄昏"

用户设定：**"一座死城，刚经历完大屠杀，时间是阴天黄昏 —— 不需要路灯和楼房灯光"**。

### 4.1 删掉了什么
| 删掉 | 原本的作用 |
|---|---|
| 楼房窗户（4 档色温、3568 个实例）| 夜景读图主力 |
| 街道灯（700 盏）| 让街道网络可读 |
| 航空障碍灯（高楼 + 桥塔）| 夜里判读高楼分布 |
| 地标自发光（富士台球体环带、中央塔顶灯）| 地标夜间识别物 |
| **楼体的暖色泛光** | 上一轮专为"从黑夜里读得出楼"加的 |

替代方案：街道网络改由**路面比地面暗一档**承担；楼的立体感改由**阴天散射天光**承担（楼体 albedo 从夜城 0.10~0.15 提到 **0.24~0.30**，地面提亮约 2.4 倍 —— 没有这一步，删灯之后就是一片纯黑）。

### 4.2 新增时段 `TimeOfDay.dusk_overcast()`
⚠️ **不要照抄现成的 `dusk()`**（那是晴天的火烧云）：

| 量 | `dusk()` | `dusk_overcast()` | 为什么 |
|---|---|---|---|
| `star_amount` | 0.22 | **0** | 阴天没有星 |
| `disc_amount` | 1.6（大太阳）| **0** | 太阳在云后 |
| `sun_energy` | 0.85 | **0.30** | 直射被云吃掉 |
| `ambient_energy` | 0.55 | **1.05** | 阴天是散射光天下 |
| 云量（`map_def`）| — | **1.15** | 阴天 ⇒ 云是天空主角（第一版 1.7 太厚，俯瞰只剩云）|

### 4.3 ⚠️ 一个可能让人误判的连锁
`suite_round` 里原本有"**四张图都是夜战**"的一刀切断言。奥恩贝利改成黄昏后，那条改成**按图判**（奥恩贝利判 `DUSK` + 星/太阳为 0，其余三张判 `NIGHT`）。
`suite_abilities` 里测"夜晚才有月光镜面"的那批断言**测的是 `night()` 这个预设本身**，不受影响。

---

## 5. 多人（局域网）玩法 —— 本轮最大的一块

### 5.1 规则（用户原话 → 代码）
> 「玩家可以选择王牌机对战；也可以选择小队模式。小队模式如果选择**统一阵营**的情况下，又都选择了**量产机**，那就**一起乘坐同一台踏板出击**，系统补一个 AI ACE。如果没有都选择量产机，那么都做选择量产机的正常出战，选择王牌机的也正常出战。」

整理成表（**四种组合只有一种特例**）：

| 阵营 | 两人机体 | 结果 |
|---|---|---|
| **同阵营** | **都是量产机** | **同乘一块踏板**（主机驾驶 / 加入方后座）|
| 同阵营 | 一台量产 + 一台 ACE | 各自正常出战 |
| 不同阵营 | 都量产机 | 正常对打 |
| 不同阵营 | 双 ACE | 正常王牌机对打 |

用户后续澄清的三点（**都已落地**）：
1. **踏板分工**："主机驾驶、加入方后座，**后座保留自己的开火权**"
2. **联机也先选阵营**（否则"同一阵营"这个前提无从判定）
3. **两边各恰好一台 ACE**；"对面原来有 ACE 就不补，没有才补"（编制表天然满足）

### 5.2 三个层次与文件

| 层 | 文件 | 状态 |
|---|---|---|
| **规则**（纯函数）| `scripts/data/lan_plan.gd`（新）| ✅ 125 条断言 |
| **菜单流程** | `scripts/ui/main_menu.gd` | ✅ 联机 4 步 |
| **出生逻辑** | `scripts/main.gd` | ✅ 19 条断言（单机可验）|
| **网络同步** | `scripts/autoload/net_session.gd` | ⚠️ 只做了"阵营同步"，**后座输入中转未做** |

### 5.3 规则层的核心设计
- `LanPlan.Choice`（一个玩家的选择：阵营 + 机体）+ `LanPlan.Plan`（一局的部署方案）
- 每边编制**恒定** `3 编队 × 2 台 + 1 ACE`；玩家**占槽**，不是额外加人
- **`Plan` 是"主机视角的一份完整对局"**，两台机器各用它一次；访问器 `local_team()` / `enemy_lineup()` 负责"本机该用哪一份"
- ⚠️ **两台机器各算一遍 `LanPlan`，结果必须一致** —— 它只依赖"两人的选择"，不依赖"谁是本机"。**这是把规则做成纯函数的回报：同步层只需同步"选择"，不需要同步"方案"。**

### 5.4 出生逻辑（`main.spawn_lan()`）
- 我方名单 `plan.local_team()` → `_spawn_side(..., online=true)`
- 对面 `plan.enemy_lineup()`
- `_spawn_side()` 新增处理 **`owner_is_client`** 的机体：**不建 AI**，建 `NetProxyBody` 代理
  - 各自出战时：代理位置来自**快照**
  - **同乘时**：代理位置来自**本机踏板的挂位**（`proxy.set_carried_by(lead, 1)` + `board.add_rider(proxy)`）
- **单机实测**（`suite_lan_spawn`）：主机的板 `riders.size() == 2`；加入方 `is_carried()` 为真、不做气动

### 5.5 ❌ 未做：同乘的"后座输入中转"
**这是本项唯一剩下的功能**，而且**必须两台机器才能验**。

建议做法（**不新增协议**）：
- 加入方（后座）把操作打包成一个 `send_state` 之外的新 RPC（或复用现有通道反向发）→ 主机
- 主机把"后座的操作"应用到**它那块踏板**上（主机是物理权威）
- 主机把踏板的位姿回传给加入方 → 加入方的代理机体（其实就是他"自己"）按位姿贴

⚠️ 为什么建议"不新增协议"：`net_session.gd` 已有 `send_state` / `send_fire` / `send_damage` 三条通道，加第四条意味着又一套握手与超时逻辑。局域网延迟 <1 ms，**不需要**预测/回滚。

---

## 6. 怎么跑 / 怎么验（**本轮的关键教训：全量入口不可用**）

### 6.1 两个可执行文件
```powershell
$godot = "C:\Users\MSIPC\Desktop\Godot_v4.7.1-stable_win64_console.exe"   # 无头
$gui   = "C:\Users\MSIPC\Desktop\Godot_v4.7.1-stable_win64.exe"           # GUI（截图用）
$proj  = "C:\Users\MSIPC\Documents\gundam"
```

### 6.2 ⚠️ 全量测试入口本轮**几乎跑不完**
`& $godot --headless --path $proj res://tests/test_runner.tscn`
—— 本会话跑了 **10 次以上**，绝大多数在中途被**外部进程清掉**（`EXITCODE=-1`、无 `N PASS / M FAIL` 汇总行），原因见 §7。

**可靠做法：独立探针入口**（只跑与本轮相关的那几套，几十秒出结果）：

| 探针 | 跑什么 | 本轮实测 |
|---|---|---|
| `res://tests/_probe_city.tscn` | Round / Round20 / Round19 / WorldScale | **727 PASS / 2 FAIL** |
| `res://tests/_probe_lan.tscn` | LanPlan / LanSpawn | **144 PASS / 0 FAIL** |

⚠️ 探针脚本在**我的副本** `aiwork\city-odaiba\tests\` 下；boss 工程里**没有**（它们是临时入口，交接时可自行复制）。

### 6.3 ⚠️ 无头 Godot 的两个坑（都踩过）
1. **`--check-only` 报 `Identifier not found: Game` 是正常的** —— 那是 autoload，`--check-only` 不实例化 autoload。**只看 `Parse Error`，不要被 `Compile Error: Game` 带偏。**
2. **改完脚本要 `--import`**，否则可能跑的是**缓存里的旧脚本**（本轮在这个坑里白跑了 3 轮）。
3. **后台跑要"脱离进程树"**：本会话发现 PowerShell 子进程会被清，改用 `Start-Process cmd /c <脚本>` 才稳（脚本里 `> log 2>&1` + `echo EXITCODE=%ERRORLEVEL%`）。

### 6.4 截图
```powershell
& $gui --path $proj res://tools/city_shots.tscn -- <输出目录>   # 城市 8 机位
& $gui --path $proj res://tools/cube_check.tscn                  # 单位立方体绕序自检
```
本轮截图：`aiwork\city-dead-final\`（死城最终版）、`aiwork\city-shot-final3\`。

---

## 7. ⚠️ 并行会话纪律（**本轮最大的现实约束**）

1. **这个工程同时有另一个 AI 会话在编辑**，而且**与本轮改的是同一条代码线**（踏板 / 后座 / 编队乘板 / 战术引导）。
2. **它会把你的 Godot 进程清掉**：本轮 10 次以上 `EXITCODE=-1`。**不要反复重启同一个全量测试**，用探针。
3. **它频繁改这些文件**（本轮实测 mtime）：`main.gd` / `main_menu.gd` / `flight_body.gd` / `flight_pedal.gd` / `suit_profile.gd` / 多个 suite。
4. **事故记录：套件命名撞车**。本会话给地图放大写的测试原名 `suite_round22.gd`，**把对方同一编号的测试整个覆盖了**（对方只好改成 `suite_tutorial.gd` 才绕开）。
   **⇒ 本会话从此改用"按主题命名"**：`suite_worldscale` / `suite_lan_plan` / `suite_lan_spawn`。**请沿用这个约定。**
5. **改文件前先同步**：`aiwork\city-odaiba` 这份副本本轮**落后过**（缺 `CLOUD_FLOOR`），导致验证失败。
   标准动作：
   ```powershell
   # 把 boss 工程当前版本同步进副本，再动手
   Get-ChildItem "$proj\scripts" -Recurse -File -Include "*.gd" | ForEach-Object {
     $rel = $_.FullName.Replace("$proj\",""); Copy-Item $_.FullName "$w\$rel" -Force }
   ```

---

## 8. 落盘清单（交给下一个会话核对）

### 8.1 新增文件
| 文件 | 作用 |
|---|---|
| `scripts/data/lan_plan.gd` | 多人规则本体（纯函数） |
| `tests/suite_lan_plan.gd` | 规则层 125 条 |
| `tests/suite_lan_spawn.gd` | 出生逻辑 19 条 |
| `tests/suite_worldscale.gd` | 地图放大 29 条 |

### 8.2 改动文件（本轮碰过）
`scripts/world/world_builder.gd` · `scripts/data/map_def.gd` · `scripts/data/time_of_day.gd` · `scripts/data/suit_profile.gd` · `scripts/data/battle_formation.gd` · `scripts/ui/main_menu.gd` · `scripts/main.gd` · `scripts/autoload/net_session.gd` · `README.md` · `tests/suite_round.gd` · `tests/suite_round17.gd` · `tests/suite_round19.gd` · `tests/suite_round20.gd` · `tests/suite_abilities.gd` · `tests/test_runner.gd` · `tools/city_shots.gd`

### 8.3 备份（**没有 git，这是唯一的回滚手段**）
`aiwork\backup-city-20260921\` · `-004445` · `backup-scale-20260921-005529\` · `backup-deadcity-20260921-011320\` · `backup-suits-20260921-012247\`

### 8.4 逐项核查（下一个会话可照跑）
```powershell
$proj = "C:\Users\MSIPC\Documents\gundam"
Select-String -Path "$proj\scripts\world\world_builder.gd" -Pattern "\[1, 0, 3, 2\]"          # 绕序修复
Select-String -Path "$proj\scripts\world\world_builder.gd" -Pattern "const MAP_SCALE := 2.3" # 尺度
Select-String -Path "$proj\scripts\data\time_of_day.gd"    -Pattern "static func dusk_overcast"
Select-String -Path "$proj\scripts\data\suit_profile.gd"   -Pattern "const DURABILITY_MULT := 1.60"
Select-String -Path "$proj\scripts\data\lan_plan.gd"       -Pattern "class_name LanPlan"
```

---

## 9. 本轮踩过的坑（**都是真错，按"下次别再犯"写**）

### 9.1 代码层
| 坑 | 现象 | 正解 |
|---|---|---|
| **单位立方体绕序全反** | 楼只剩一个可见面（"房子是空的"）| 逐面写绕序 + 交叉积验算；`tools/cube_check` 复现 |
| **`emission_vertex_color_use_as_albedo` 不存在** | Godot 4 直接报 Invalid assignment | 窗光改"分 4 档色温、4 份材质" |
| **`CylinderShape3D` 没有 `top_radius`** | 运行时报错但**截图照常出** | Big Sight 倒锥的碰撞用 `radius + height` 近似 |
| **`append(x.size())` 先求值再追加** | 两个人挤进同一编队 ⇒ 一台机凭空消失 | 先 `var n := x.size()` 再 `append(n)` |
| **座位号靠数组下标暗示** | 两台机器上"我/远端"顺序相反 ⇒ 名单不一致 | **座位号显式写出**（`set_human_seat`）|
| **同一台机体标了两个 owner 布尔量** | 一台机同时属于两个玩家 | 只存一个**座位号**，两个布尔量由它派生 |
| **`main.gd` 没有 `class_name`** | 测试里写 `Main.xxx` ⇒ `Identifier "Main" not declared` | 实例化 `main.tscn`，从实例上 `call()` 静态方法 |
| **三元 + 类型推断** | `var board := lead.pedal_owner()` 让**整个 main.gd 编译不过** | 显式标注类型（本工程第 3 次栽在这） |
| **雾密度不跟尺度走** | 放大后城市在雾里糊成一片 | 密度按 `MAP_SCALE` 反向调低 |
| **探针绕过开局入口** | `player == null`，测试白跑 | 走 `_on_match_start()`（真入口）|
| **`--check-only` 的 `Game` 报错** | 误以为脚本编译不过 | 那是 autoload 未实例化，只看 `Parse Error` |
| **改完脚本没 `--import`** | 跑的是缓存旧脚本（白跑 3 轮）| 改脚本后先 `--import` |

### 9.2 判断层（比代码错更值得记）
| 坑 | 我的错判 | 事实 |
|---|---|---|
| 看到 `_apply_carried()` 的"已删除"注释 | 以为"同乘"要自己写 | 并行会话**已经实现**（`set_carried_by`），我读到的是过时注释。**以磁盘为准。** |
| 以为"耐久调高"可以随便加 | 差点按"翻倍"改 | 这项**被实测否过一次**（第八轮"11 分钟太漫长"），最终只加 19% 并加了 `DURABILITY_MULT < 1.80` 上限断言 |
| 测试红了就改代码 | 有 6 次是我**测试的期望值写死**（不是代码错） | 期望值应**从方案反推**（如编队数按真人占位算） |

---

## 10. 未完成 / 下一步

| 优先级 | 事项 | 说明 |
|---|---|---|
| **高** | **同乘的"后座输入中转"** | §5.5；必须两台机器；建议不新增协议 |
| 中 | 菜单侧跨阵营防护 | 用 `BattleFormation.belongs_to` 挡住"选马夫蒂却挑联邦机体"（`LanPlan` 已能兜底，但菜单最好不给） |
| 中 | `README.md` §16.22 补本轮记录 | 本会话只改了 README 的**耐久表**；城市/尺度/多人三段没写进 README |
| 低 | 全量测试跑通一次 | 需要等并行会话停下来（§7）|
| 低 | 同乘的 HUD 文案 | 后座要能看出"我在别人的板上"（`FlightPedal.vis_state()` 已有状态，HUD 未接）|

---

## 11. 给下一个会话的第一个 15 分钟

```powershell
$proj  = "C:\Users\MSIPC\Documents\gundam"
$godot = "C:\Users\MSIPC\Desktop\Godot_v4.7.1-stable_win64_console.exe"

# 1) 先看有没有别人在写（§7）
Get-ChildItem $proj -Recurse -File -Include *.gd | Where {$_.LastWriteTime -gt (Get-Date).AddMinutes(-15)} |
  Select LastWriteTime, FullName
Get-Process | Where {$_.ProcessName -match 'Godot'} | Select Id,StartTime

# 2) 拿基线（**全量入口大概率被清掉，改用探针**）
Copy-Item "C:\Users\MSIPC\Desktop\aiwork\city-odaiba\tests\_probe_city.*" "$proj\tests\" -Force
Copy-Item "C:\Users\MSIPC\Desktop\aiwork\city-odaiba\tests\_probe_lan.*"  "$proj\tests\" -Force
#   然后（**脱离进程树跑**）：
#   Start-Process cmd /c "<godot> --headless --path $proj res://tests/_probe_lan.tscn > log 2>&1"
#   期望：144 PASS / 0 FAIL

# 3) 读四份东西就够开工：
#    - 本文（本轮全貌）
#    - aiwork\GUNDAM_HANDOFF.md（工程原始交接，仍然有效）
#    - README.md §9 目录结构 / §10 设计决策 / §14 历轮真 bug
#    - scripts\data\lan_plan.gd 的文件头（多人规则原文 + 设计取舍）

# 4) 要改多人那块之前：**先同步副本**（§7.5），因为它与并行会话共用代码线
```

---

*本文所有路径、常量与数字均来自 2026-09-21 02:40 的磁盘实测与探针运行。与磁盘冲突时，以磁盘为准。*
