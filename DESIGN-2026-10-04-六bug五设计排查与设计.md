# DESIGN-2026-10-04 · 六 bug + 五设计 · 排查与设计（**先设计，不开工**）

> **本文件对产品源码的改动 = 零。** 自证命令与读数见 §6.2。
> 本轮的全部产出 = 这份文档 + 两个只读算账脚本（§6.1）。工程源码 / 场景 / 数据一个字没动。
>
> 工程根 `C:/Users/MSIPC/Documents/gundam`（Godot 4.7.1 · 不在 git）。
> 备份与回退口径沿用既有规矩：备份写**绝对路径** `%LOCALAPPDATA%\Temp\gundam_bak\rN\`。

---

## 0. 读法

### 0.1 结论强度四档（每一节都标一档，不含糊）

| 档 | 含义 | 能不能开工 |
|---|---|---|
| **已定量证实** | 有算式 / 有引擎读数 / 有历史实测表，数字可复算 | 能 |
| **已定位** | 路径上每一处都指得到 `文件:行`，机制闭环 | 能（但要先拍板） |
| **设计题** | 缺的是"要什么"，不是"在哪" | 先拍板 |
| **候选，缺现场** | 说不清楚是哪一条 | **取证之前不进入编码阶段** |

### 0.2 每条都过三问

1. **这个量谁写、谁读？有唯一写入点吗？**（两处争写 = 这一轮最常见的一类根因）
2. **它跟别的量乘在同一根链条上吗？**（改一个会连带改三个）
3. **有没有"注释与代码相反"？**（本项目已抓到多次）

### 0.3 反向纪律

**没有可证伪判据 + 负对照的方案 = 没写方案。** 下文每一节的「判据」都写成能变红的形式，
并给出「负对照」—— 即"把这一条改回去，哪一条断言必须红"。

---

## 1. 总览

### 1.1 总览表

| # | 用户原话要点 | 结论强度 | 一句话根因 | 改动量 | 回归风险 | 建议批次 |
|---|---|---|---|---|---|---|
| **B1** | 古斯塔夫/梅萨在踏板上穿模看到它们的胸部 | **已定位** | 同一个 `model_root.visible` 被**两处争写**：踏板只在上下板时 hide 一次，`main` **每帧**把它设回 true | 小 | 低 | 批 1 |
| **B2** | 联机对方没进房间就一直卡住、没有退出办法 | **已定位** | 等待态那一块在 `:2513` 就 `return`，把同函数里**唯一的返回出口**（`:2533`）与 Esc 保险丝（`:2728` 不含 LAN）全挡在下面 | 小 | 低 | 批 1 |
| **B3** | 防撞地未生效 | **已定位（结构）** | `_tick_assist()` 在 `translate_mode` 下 `:1596` 直接 return ⇒ **辅助驾驶的防撞地在平移模式下根本不跑**；而平移模式是绝大多数机体在辅助下的默认路 | 中 | **中** | 批 3 |
| **B4** | 小队战选敌方阿利宙斯，实际来的是佩涅罗佩 | **已定位（双根因）** | ① 菜单 `SQUAD` 分支**丢弃** `enemy_suit`；② 敌人 ACE 槽恒取 `aces[0]` = 佩涅罗佩 | 小~中 | 低 | 批 2 |
| **B5** | 阿利宙斯偶尔一直跑路，要增强进攻欲望 | **已定位** | `AGGRESSION` 是唯一旋钮（`:121`），且 `SEEK ⇒ throttle 0.92` **没接 AGGRESSION** ⇒ 加欲望不会让它更少跑 | 小 | 低 | 批 4 |
| **B6** | 去掉长按 T 丢枪、保留 T 撑盾、撑盾免伤改 80% | **已定位** | 长按丢枪的**第二支读的就是 `shield`（T）**（`:268`）⇒ 用户没说错；免伤落点 `flight_body.gd:5226`，但 6 处值不同 | 小 | 低 | 批 1 |
| **D1** | m02 梅萨一直逃跑、追不上打不死 | **已定量证实** | 玩家古斯塔夫 00 巡航 **554**，敌机极速被天花板钉在 **765** = 玩家巡航的 **1.38 倍** ⇒ 不按加力永远追不上（加力相对速度仅 160 m/s ⇒ 追平 12 km 要 **75 s**） | 小 | 低 | 批 2 |
| **D2** | 辅助驾驶下 CTRL 切换成倒着飞（W 减速 / S 加速） | **设计题** | 键位**不冲突**（`hover` 在平移模式下根本没被读），缺的是三条语义 | 中 | 中 | 批 3 |
| **D3** | 光束步枪辅助瞄准 + 放大镜 + 预测圈 + 准星吸附 | **设计题（含需求变更）** | `aim_assist_weight` 因**单位错**恒 0（死代码）；放大镜**没有底座**（全工程无 SubViewport、无第二台相机） | **大** | 中 | 批 5 |
| **D4** | 增加敌方机体坠毁提醒（不要和结算冲突） | **已定位** | `push_notice` 通道现成，但**与击毁零连接**；冲突是结构性的——`notify_destroyed`（会判胜）与 `destroyed`（会起结算）在**同一帧**前后发生 | 小 | 低 | 批 1 |
| **D5** | 导弹拖尾白烟透明度 −20%、密度 −20%、体积不变 | **已定量证实** | **只有粒子层有"密度"这个量**；而 `amount ×0.8` 会**打破「无缝」不变量**（间距 8.124 → 10.156 > 直径 9.945） | 小 | 低 | 批 2 |

### 1.2 分组：能不能现在就动手

**A. 零歧义 / 一处拍板即可开工（批 1 + 批 2，8 项）**
B1 · B2 · B4 · B6 · D1 · D4 · D5 —— 都指得到行，方案唯一，判据能变红。

**B. 需要先拍板"要什么"（3 项）**
D2（倒飞的朝向语义）· D3（辅助瞄准与 README 需求 4 冲突 + 放大镜要不要做）· B5（只调阿利宙斯还是 ACE 通用）。

**C. 需要先取现场（1 项）**
B3（"防撞地未生效"有三种互斥语义，见 §3.3 的鉴别表）。

---

## 2. 逐项（bug 1~6）

### 2.1 · B1 · 古斯塔夫 / 梅萨在飞行踏板上穿模，看到它们的胸部模型

**用户原话** · 「古斯塔夫，梅萨在踏板上的时候会穿模看到梅萨和古斯塔夫的胸部模型。」

**结论强度** · **已定位**（两处争写同一字段，机制闭环）

**一句话根因** · 踏板侧只在上下板时把骑手模型 `hide` 一次，而 `main` **每帧**把玩家模型设回可见 ⇒ 骑手自己的机体与"踏板模型里烤死的机体几何"**叠影**。

**现象拆解** · 用户看到的是"两台机体叠在一起"——其中一台是踏板模型自带的几何，另一台是骑手自己的模型被重新显示出来。

**证据（文件:行）**

| 位置 | 内容 | 作用 |
|---|---|---|
| `scripts/flight/flight_pedal.gd:601` | `func hide_rider_model(r)` → `:606 r.model_root.visible = false` | 踏板侧的 hide（**只在状态变化时**调） |
| `scripts/flight/flight_pedal.gd:596-598` | 注释：「**载人状态的踏板模型里自带机体几何**……所以只要板上有人就必须藏骑手自己的模型，否则两台叠影」 | 设计前提，写得很清楚 |
| `scripts/flight/flight_pedal.gd:610` | `func show_riders()` → `:614 r.model_root.visible = true` | 脱板还原 |
| `scripts/flight/flight_pedal.gd:722` | `func _sync_rider_model_visibility()` | 只在**状态变化**时同步 |
| `scripts/main.gd:2865` | `player.set_model_visible((not Settings.first_person) and player.alive)` | **每帧**写（争写方） |
| `scripts/flight/flight_body.gd:2074` | `func set_model_visible(v)` → 直接写 `model_root.visible` | 幂等短路，但**不知道**踏板在管它 |
| `scripts/flight/flight_pedal.gd:136` | `const SUIT_GAME_HEIGHT := 23.0` | 踏板模型的高度基准 |
| `scripts/data/suit_profile.gd:2371` / `:2479` | `p.target_height = 22.0`（古斯塔夫 / 梅萨） | 机体目标高度 —— **与 23.0 差 4.3%**，是第二处（较轻的）不一致 |

**根因（两问）**

- 三问①「谁写谁读」：`model_root.visible` 的写入点有 **4 个**（`flight_body.set_model_visible`、`flight_pedal.hide_rider_model`、`show_riders`、`:652` / `:1265` 两处直写），而 `main` 每帧的那个是**唯一的、无条件的、外部**写入者 ⇒ 它必然把踏板侧的一次性 hide 覆盖掉。
- 三问②「连在谁的链条上」：`set_model_visible()` 同时被"第一人称"和"存活"两个语义使用（`not Settings.first_person and player.alive`）—— **一个函数管三件事**（fpv 隐藏 / 残骸隐藏 / 踏板隐藏），这就是它没法知道踏板的原因。

**方案**

> **原则：把"骑手模型该不该显示"升格为一个有唯一真源的判据，而不是"谁最后写谁赢"。**

- **方案 A（推荐）**：在 `FlightBody` 上加一个只读判据 `rider_hidden := false`（唯一写入点 = 踏板侧 `hide_rider_model` / `show_riders`），并让 `set_model_visible(v)` 变成 `model_root.visible = v and not rider_hidden`。`main` 那一行**一个字都不用改** ⇒ 逐位不变的部分最多。
- **方案 B**：在 `main.gd:2865` 的表达式里加 `and not player.is_carried()`。改动更小，但把判据留在了调用方 ⇒ 哪天多一个调用者就重现（正是这次的成因）。
- **方案 C（否决）**：让踏板每帧也写一次 —— 两个每帧写入者互相打架，谁是最后写的取决于节点顺序，**是最坏的一种修法**。

**可证伪判据 + 负对照**

1. `player` 骑板（`has_pedal()` 为真）⇒ 即使调 `player.set_model_visible(true)`，`player.model_root.visible` 必须仍是 `false`。
   **负对照**：把 `and not rider_hidden` 去掉 ⇒ 本断言必须红。
2. 脱板 ⇒ 恢复 `not Settings.first_person and alive`（**不是**无条件 true）。
   **负对照**：写死 true ⇒ 第一人称下必须红。
3. 真机判据（唯一能证明"看不见"的方式）：非第一人称 + 古斯塔夫 00 骑板，出图，踏板区域**只有一个机体轮廓**。
   ⚠️ 只断"节点存在"或只断"visible 是 false"都不够 —— 本项目有"两条断言都绿却看不见"的先例；**判据必须断 `is_visible_in_tree()`**。
4. 尺寸一致性：`SUIT_GAME_HEIGHT 23.0` 与古斯塔夫/梅萨的 `target_height 22.0` 的差**必须在文档里说明**是刻意的，或者收敛到一处。**负对照**：两边各自硬编码，一条断言都不动就改值 ⇒ 必须能指到"没有判据看着这件事"。

**未决** · P1（裁决优先权给谁）、以及 23.0 vs 22.0 是不是刻意的。

---

### 2.2 · B2 · 联机对战：对方没进房间就一直卡住，没有退出办法

**用户原话** · 「联机对战如果对方没有进房间就会一直卡住，没有退出的办法。」

**结论强度** · **已定位**

**一句话根因** · `_read_lan_input()` 的等待态分支在 `:2513` 无条件 `return`，把**同函数下方唯一的返回出口**（`:2533` 的 `menu_back` → 回 `Stage.SUIT`）与 Esc 保险丝（`:2728`，**不含 LAN**）全部挡在下面 ⇒ `_lan_wait = true` 之后，**没有任何函数能把它置回 false**（除了"对手到齐"和"连接失败/主机关闭"那两条回调）。

**现象拆解** · 三种"卡住"其实是**两条独立路径**：
- 主机：建了房、没人进来 ⇒ `Net.role` 恒为 `HOST` ⇒ 上面那条 `if Net.role == Net.Role.NONE` 永不成立 ⇒ 永久等待。
- 加入方：连不上/对方关主机 ⇒ `_on_connection_failed` / `_on_server_disconnected` 会 `close()`（role → NONE）⇒ **这条是通的**。
⇒ 用户描述的"卡住"是**主机/等待对手**那一侧。

**证据（文件:行）**

| 位置 | 内容 |
|---|---|
| `scripts/ui/main_menu.gd:2472` | `var _lan_wait := false` |
| `scripts/ui/main_menu.gd:2496` | `if _lan_wait:` —— 等待态的**唯一**处理块 |
| `scripts/ui/main_menu.gd:2499` | 对手到齐 ⇒ `_lan_wait = false` + `LanBrowser.stop()` + `_launch()` + `return` |
| `scripts/ui/main_menu.gd:2511` | `if Net.role == Net.Role.NONE:` ⇒ `_lan_wait = false`（**只覆盖"连接失败"那一侧**） |
| `scripts/ui/main_menu.gd:2513` | **`return`** ← 元凶：它让下面整段对等待态不可达 |
| `scripts/ui/main_menu.gd:2533-2540` | `if Input.is_action_just_pressed("menu_back"):` → `LanBrowser.stop()` / `Net.close()` / `stage = Stage.SUIT` ← **真正的返回出口，被上面那个 return 挡住** |
| `scripts/ui/main_menu.gd:2728` | `_input()` 里写死的 Esc 保险丝，条件列 `SETTINGS / KEYS / BGM / FPV_CONFIRM / PASSWORD` —— **没有 `Stage.LAN`** |
| `scripts/ui/main_menu.gd:2868-2869` | 页面底部写着「等待对手的选择…（**Esc 取消**）」← **声称有出口，实际无出口** |
| `scripts/autoload/net_session.gd:227` | `_on_peer_disconnected` **不 close、不改 role** |
| `scripts/autoload/net_session.gd:247` / `:252` | `_on_connection_failed` / `_on_server_disconnected` 才会 `close()`（role → NONE） |
| 全工程 | `lobby_changed` / `match_ready` **零消费者**（菜单没接） |

**方案**

- **方案 A（推荐，最小且闭合）**：
  1. 等待态里**先**处理 `menu_back`（把 `:2533` 那段上移到等待分支内、或改成等待分支**不 return** 而是落到公共输入段）；
  2. 给等待态加**超时兜底**（纯函数 `NetSession.lan_wait_timed_out(elapsed, timeout, role)`，可单测），默认 20 s，超时回可操作态 + `_system_say` 式提示；
  3. `_input()` 的 Esc 保险丝加上 `Stage.LAN`（三层保险的第 ① 层本来就该覆盖它）。
- **方案 B**：只做 ①（去掉 return）⇒ 能退出，但仍没有超时，玩家得知道按 Esc。**不推荐单独用**，但可作为 A 的第一步分两次提交。

**可证伪判据 + 负对照**

1. **纯函数**：`lan_wait_timed_out(25.0, 20.0, Role.HOST) == true`；`(10.0, 20.0, HOST) == false`；`(99.0, 20.0, NONE) == false`（角色已回 NONE 时不该再报超时）。
   **负对照**：把实现了的时间比较改成 `>= 0` ⇒ 第二条必须红。
2. **接线（能变红的那个）**：构造等待态（`_lan_wait = true`）后模拟 `menu_back` ⇒ 断言 `_lan_wait == false` **且** `Net.role == Net.Role.NONE` **且** `stage == Stage.SUIT`。
   **负对照**：保留 `:2513` 那个 `return` ⇒ 本断言必须红（这是它今天的读数）。
3. **文案与出口一致**（这条是治"声称有出口"的）：`_draw_lan_footer()` 等待文案里出现「Esc 取消」时，必须存在一条与之配对的"Esc 真能取消"断言。
   **负对照**：删掉断言但保留文案 ⇒ 必须有 gate 报"文案无人守"。
4. **真机**：建房 → 不进人 → 按 Esc（与超时各一次）⇒ 回到机体选择页、房间广播已停、连接已关。

**未决** · 超时时长（建议 20 s）；超时后是"回可操作态"还是"直接回上层"（建议回可操作态，玩家可以改房间号重试）。

---

### 2.3 · B3 · 防撞地未生效

**用户原话** · 「防撞地未生效。」

**结论强度** · **已定位（结构性缺失）**，但**用户指的语义要先鉴别**（三种互斥可能）

> ### ★★ 施工期实测修正（轮 63-9 · B3 落地时发现：**根因确认，但下面「第一步」的写法要改两处，且第二步多了一个硬证据**）
>
> **修正 0 · 下面正文里的 `:1596` / `:1613` / `:1631` 是改前的行号。**
> 改后 `_assist.update()` 的平移调用点在 `_tick_assist()` 的**平移分支**里，
> 整段状态机抽成了 `_tick_auto_pull(delta) -> bool`，
> 夺杆口径抽成了 `_pull_up_command()`。
>
> **修正 1 · 「把代码挪到早退之前」不够 —— 平移模式写 `control_input` 是空转。**
> `FlightBody._apply_translate()` 直接改 `fm.velocity`，
> **一个字都不读 `control_input`** ⇒ 只把那一段搬上来，观感是
> 「提示弹了、机体照样扎进地里」（本工程最忌讳的「看着对、其实空转」）。
> 平移模式真正的抬头旋钮是**升降（Q/E）**，即 `translate_dir` 的 y 分量。
> ⇒ 夺杆按模式分家，共三个写点：
> `translate_dir = UP` · `translate_fwd = ZERO`（不清会被当成「前进」削掉 85%）·
> `face_target = null`。
>
> **修正 2 · 「玩家有没有在压杆」这条口径也要跟着换。**
> `_read_translate_input()` 每帧把 `control_input` 清零（`:734`）⇒ 若仍传
> `control_input.x`（恒 0），等于告诉辅助「玩家永远没在压杆」，
> 于是**按着 E 往地里扎也会被夺杆** —— 正是老板点名不许的那件事。
> ⇒ 平移模式传 `translate_dir.y`（`_read_translate_input()` 里唯一带 y 的分量）。
>
> **修正 3 · 平移模式「不锁目标就不会俯冲」。**
> `_apply_translate()` 在无目标时把底速的 y 分量**强制归零**（`fwd.y = 0`）
> ⇒ 唯一会撞地的场景 = **锁着一台下方目标**（「朝目标飞」本身就是俯冲指令）。
> 于是夺杆时清 `face_target` 才有意义：接管期间的净垂速
> = `(TRANSLATE_OFFSET − sin θ) · v`（θ = 目标在水平线下夹角）：
> **10° ⇒ +0.48 v · 30° ⇒ +0.15 v · 40° ⇒ +0.007 v ≈ 0**。
> 清掉 ⇒ 底速退回机头水平投影，净垂速恒 `+0.65 v`（≈ 33° 爬升）。
> ⚠️ 但这一笔**在真机上测不出来**（见修正 4）：判据只能断**结构**（`face_target == null`），
> 负对照 `nc_no_face` 也确实**只红那一条**。
>
> **修正 4 · ⚠️ 重要负面发现：`GROUND_GUARD_ALT = 50 m` 在平移模式极速下只剩 0.02~0.13 s。**
> 拉起窗口 = `(GROUND_GUARD_ALT − CRASH_ALTITUDE) / (v · sinθ)` = `26 m / (v · sinθ)`：
>
> | v（引擎域） | θ = 6° | 10° | 15° | 30° | **33°**（= E 键俯冲角） |
> |---|---|---|---|---|---|
> | 1512（巡航极速） | 0.165 s | 0.099 s | 0.066 s | 0.034 s | 0.032 s |
> | **2268（加力极速）** | **0.110 s** | **0.066 s** | **0.044 s** | **0.023 s** | **0.021 s** |
>
> ⇒ **「按住 E 俯冲」在几何上救不回来** —— E 的修正权重
> `TRANSLATE_OFFSET = 0.65` 恰好就是 `atan(0.65) = 33.0°`。
> ⇒ 这正是下面「**第二步**（`CRASH_ALTITUDE` 的绝对 y 改成离地高度，
> 或者让门槛随速度缩放）」的**量化依据**。
> ⚠️ **本轮不做**（高风险、单独立轮）⇒ 记为 **B3-2**。
>
> **修完之后的真机读数**（`tests/suite_ground_guard.gd` §⑤：
> 锁一台**水平线下 6°、距 40 km** 的敌机，离地 200 m 起飞，**不动摇杆**）：
>
> | 版本 | 最低 y | 接管 | 垂速 | 结局 |
> |---|---|---|---|---|
> | **改前**（`nc_early_return`） | **24.8 m** | 从不 | −231.9 m/s | **撞地**（末高 20.9 m） |
> | **改后** | **42.5 m** | 第 48 帧 | **+3.4 m/s** | **存活** |
>
> 结构读数：`ground_time = 0.0444 s` · `ground_dist = 40.00 m` ·
> 系统提示行 = 「自动改出 · 接管俯仰」。
>
> **本轮的实际改动（全在 `scripts/flight/player_controller.gd`，`player_controller.gd` 字节数 128822 → 133566）**
>
> | # | 改动 |
> |---|---|
> | ① | `_tick_assist()` 的平移早退 → 改成「照样跑 `_assist.update()` + 状态机」（且传 `translate_dir.y`） |
> | ② | 新增 `_tick_auto_pull(delta) -> bool`（状态机 + 提示 + 告警音 + `fm.boosting = false`），**两种模式共用** |
> | ③ | 新增 `_pull_up_command()`，夺杆口径按模式分家（平移：3 个写点；老路：原样） |
> | ④ | 老路的顺序**一字未动**（`suite_round14` 仍 125 PASS / 0 FAIL） |
>
> **新判据**：`tests/suite_ground_guard.gd`（5 段 / **32 PASS**）；六个负对照：
> `nc_early_return` 红 **16** · `nc_pitch_src` 红 **5** · `nc_no_dir` 红 **5** ·
> `nc_no_face` 红 **1**（**只** §③③）· `nc_no_fwd_zero` 红 **1**（**只** §③②）·
> `nc_branch` 红 **2**（**只** §④）。


**一句话根因** · `PlayerController._tick_assist()` 在 `translate_mode == true` 时 `:1596` 直接 `return`，而**防撞地的全部代码都在那一行之后**（`_assist.update(...)` 在 `:1613`、`release_pull` 判定在 `:1631`）⇒ 辅助驾驶下，只要走平移模式，**防撞地一次都不会执行**。

**关键事实（必须先分清"防撞地"的两个语义）**

| 语义 | 实现 | 现状 | 谁受影响 |
|---|---|---|---|
| **判死**（撞上去了要死） | `flight_body.gd:2609 _check_ceiling()`：有地面图 `y < CRASH_ALTITUDE(24.0)` ⇒ `destroy("撞海")`；另外 `:2990 _check_collisions()` 撞 WORLD 层实体 ⇒ `destroy("撞地")` | **是通的**（且 `_check_collisions` 无条件判死） | 所有人（玩家 + AI） |
| **规避**（自动帮你拉升） | 玩家侧 `FlightAssist`（`ground_time` / `needs_release_pull_up` / `correction_for`）；AI 侧 `bandit_ai.gd:893 _needs_pull_up` / `:925 _blend_safety` / `:954 _probe_terrain` | **玩家侧在平移模式下结构性不跑**；AI 侧是另一套独立实现 | 玩家（辅助驾驶时）；AI（自己那套） |

**证据（文件:行）**

| 位置 | 内容 |
|---|---|
| `scripts/flight/player_controller.gd:1568-1574` | `_tick_assist()` 首段：**辅助关** ⇒ `_auto_pull_up = false` 并 `return` |
| `scripts/flight/player_controller.gd:1595-1596` | **`if translate_mode: return`** ← 元凶：防撞地全在它下面 |
| `scripts/flight/player_controller.gd:1613` | `_assist.update(self, tgt, preferred, delta, control_input.x)` ← 不可达 |
| `scripts/flight/player_controller.gd:1623-1631` | `var pulling := _assist.release_pull` + `_auto_pull_up` 接管/交还 ← 不可达 |
| `scripts/flight/player_controller.gd:629-633` | `assist_uses_translation(p, riding_pedal)`：**只有**「骑板」或「阿利宙斯 + 巡航形态」返回 false ⇒ 其余全部走平移模式 |
| `scripts/flight/player_controller.gd:230` | `translate_mode = assist_on and assist_uses_translation(profile, has_pedal())` |
| `scripts/flight/player_controller.gd:661-662` | `_read_translate_input()` **全文不读 `hover`**（顺带是本轮 D2 的好消息） |
| `scripts/flight/flight_assist.gd:276-290` | `_probe_down()`：`collision_mask = 1`（WORLD_LAYER）；打空 ⇒ `ground_dist = INF` ⇒ `ground_time` 也 INF ⇒ `needs_release_pull_up` 在 `:145 ground_time >= RELEASE_PULL_TIME(2.8)` 处必然为假 |
| `scripts/flight/flight_assist.gd:139` | `if altitude > GROUND_GUARD_ALT(50.0): return false` |
| `scripts/flight/flight_assist.gd:143` | `if vertical_speed > -DIVE_SINK(40.0): return false`（平飞/微降不碰） |
| `scripts/flight/flight_assist.gd:134` | `if released_for < RELEASE_GRACE(0.25)` ⇒ "推一下杆再松"不算松手 |
| `scripts/flight/flight_body.gd:2609-2613` | `_check_ceiling()` 判死；`CRASH_ALTITUDE = 24.0` 是**绝对 y**，不是离地高度 |
| `scripts/flight/flight_body.gd:2668-2670` | `map_has_ground()` → `m == null or m.has_ground`（**决定判死还是推回轨道**） |
| `scripts/flight/flight_body.gd:2620-2622` | 无地面图改走 `_enforce_orbit_floor()`（**不判死**） |
| `scripts/flight/flight_body.gd:2990-3010` | `_check_collisions()`：非机体 ⇒ **无条件** `destroy("撞地" if map_has_ground() else "撞毁")` |
| `scripts/flight/flight_body.gd:2503-2507` | `if is_carried(): _apply_carried(...); return` ⇒ **被载机永远不跑** `move_and_slide / _check_collisions / _check_ceiling`（由领机负责，符合设计） |
| `scripts/ai/bandit_ai.gd:33/35` | `SAFE_ALTITUDE 1600.0` / `CRITICAL_ALTITUDE 700.0`（AI 那套，**绝对 y**） |
| `scripts/ai/bandit_ai.gd:51/53/55` | `TERRAIN_PULL_TIME 2.0` / `TERRAIN_AVOID_TIME 3.0` / `TERRAIN_PROBE_DOWN 0.55` |
| `scripts/ai/bandit_ai.gd:63` | `SABER_ABORT_ALTITUDE 650.0`；`bandit_ai.gd:561` 注释明说**军刀突进期间避地逻辑失效** |

**鉴别表（这就是"要先取现场"的原因）**

| 用户实际看到 | 对应机制 | 是不是 bug | 鉴别方法 |
|---|---|---|---|
| ①「撞上去了但没死 / 穿过去了」 | `CRASH_ALTITUDE` 是**绝对 y**（`24 m`），而有起伏地形/楼体的图上地表高度远高于 24 m ⇒ 高度判死不触发；只剩 `_check_collisions()` 的碰撞体判死。若碰撞体是薄面 + 速度 2268 m/s（每物理步 37.8 m）则可能漏判 | **可能是 bug** | 记录"地点 + 当时 `global_position.y` + 有没有出现 `[destroy]` 打印" |
| ②「辅助驾驶开着，它自己往地上撞，不帮我拉」 | **平移模式下 `_assist.update()` 不可达**（本节根因） | **是 bug** | 确认辅助是开还是关；开的话**按构造必然复现** |
| ③「轨道图上撞下去没死，被弹回去了」 | `has_ground == false` ⇒ `_enforce_orbit_floor()`（**设计如此**：老板原话「近地轨道没有撞地这种情况」） | **不是 bug** | 看地图是不是 LEO / `has_ground` |
| ④「AI 没撞地」 | AI 走自己那套 `_needs_pull_up`；军刀突进期间（`:561`）显式失效 | 设计如此（有注释） | 看是不是在军刀突进 |

**方案**

- **第一步（无论哪种语义都要做）**：把 `_tick_assist()` 的两处早退理清 —— **"辅助关"与"平移模式"都不该同时关掉防撞地**。
  - 建议：平移模式下**至少**跑 `_assist.update()` + `release_pull` 这一段（姿态修正与"替你按住 Shift"确实不属于平移模式，那两条可以继续跳过）。
  - 判据：这是一个**纯结构断言**——"平移模式下 `_assist` 每帧被更新过"，可以做成一个可读的计数（`_assist_updates`）来测。
- **第二步（只在语义 ① 成立时做）**：把 `CRASH_ALTITUDE` 的判据从**绝对 y** 改成**离地高度**（用一条向下射线或 `map_def` 的高度场），或者明确写成"24 m 只对海平面/平地有效"。
  ⚠️ **这是高风险改动**（会动到所有图的撞地行为）⇒ 单独立轮 + 判据必须无头 + 有真机图。
- **第三步（可选）**：`_probe_down` 打空时给出可观测信号（现在静默变 `INF`）—— 与 D5「两层账」同理：**"静默退到兜底值"是本工程已记录的陷阱之一**。

**可证伪判据 + 负对照**

1. **结构**：辅助开 + 非巡航形态（`translate_mode == true`）⇒ 断言 `_assist` 本帧被更新过（读计数或读 `ground_time != INF`）。
   **负对照**：保留 `:1596 return` ⇒ 必须红。
2. **纯函数**（已存在，核对即可）：`needs_release_pull_up(0.0, 1.0, -60.0, 1.0, 40.0) == true`；
   **负对照** 三条：`altitude = 60.0` ⇒ false；`vertical_speed = -20.0` ⇒ false；`pitch_input = -0.3` ⇒ false。
   这四条今天应该已经是绿的（`suite_round14` 有两组）—— 本轮的 bug **不在这个纯函数里**，这是要点。
3. **判死**（只在这轮动到它时才需要）：`y = 23` 且 `map_has_ground()` ⇒ `alive == false`；**负对照** `y = 25` ⇒ `alive == true`。
4. **真机**：辅助开 + 平移模式，主动俯冲松手 ⇒ 出现「自动改出 · 接管俯仰」+ 地形告警音。
   ⚠️ 今日预期**不出现** —— 这条断言就是"防撞地真的接回去了"的证明。

**未决** · P13（先给现场：是 ①②③④ 哪一个）

---

### 2.4 · B4 · 小队战选敌方阿利宙斯，实际来的是佩涅罗佩

**用户原话** · 「小队战选择敌方是阿利宙斯会变成佩涅罗佩来。」

**结论强度** · **已定位（双根因）**

**一句话根因** · ① 菜单在 `SQUAD` 分支**根本不读**玩家选的敌机（`enemy_suit` 保持 `-1`）；② 敌人那边的 ACE 槽**恒取 `aces[0]`**，而联邦的 `aces = [佩涅罗佩, 阿利宙斯]` ⇒ 永远是佩涅罗佩。

**证据（文件:行）**

| 位置 | 内容 |
|---|---|
| `scripts/ui/main_menu.gd:1561` | `func _launch()` |
| `scripts/ui/main_menu.gd:1567` | `var enemy_suit := -1` |
| `scripts/ui/main_menu.gd:1569-1570` | **只有 `mode == VERSUS`** 才 `enemy_suit = selected_enemy()` |
| `scripts/ui/main_menu.gd:1579-1584` | `elif mode == SQUAD:` —— 注释写「**敌机由编制决定**（不选敌机）」，**没有赋值** ⇒ 玩家的选择被丢弃 |
| `scripts/ui/main_menu.gd:1606` | `start_match.emit(suit, selected_level(), map_id, mode, enemy_suit)` ⇒ SQUAD 时第 5 参恒 `-1` |
| `scripts/ui/main_menu.gd:226` | `const ENEMY_SUITS := [XI, PENELOPE, ARIZEUS]`（**三台，含跨阵营的柯西**） |
| `scripts/ui/main_menu.gd:1063-1064` | `func selected_enemy() -> int: return ENEMY_SUITS[clampi(enemy_index, 0, ...)]` |
| `scripts/data/battle_formation.gd:123-129` | `func ace() -> int: if not aces.is_empty(): return aces[0]` ★ |
| `scripts/data/battle_formation.gd:196` | **联邦**：`r.aces = [PENELOPE, ARIZEUS]` ⇒ `aces[0]` **恒是佩涅罗佩** |
| `scripts/data/battle_formation.gd:167` | 马夫蒂：`r.aces = [XI]` |
| `scripts/data/battle_formation.gd:246` | `static func lineup(side: int, player_suit: int) -> Array` —— **签名里没有"敌方 ACE id"这个参数** |
| `scripts/data/battle_formation.gd:288` | `var ace_suit: int = player_suit if is_player_ace else r.ace()` |
| `scripts/main.gd:1761` | `var theirs := BattleFormation.lineup(foe_side, -1)` —— **只传 side，不传 ACE** |
| `scripts/data/battle_formation.gd:153-154` | `SQUADS_PER_SIDE = 3` / `UNITS_PER_SQUAD = 2` / `ACES_PER_SIDE = 1` |

**根因（两问）**

- 三问①「唯一写入点」：**没有**。`enemy_suit` 这条信息在菜单里存在（`selected_enemy()`），在 `_launch()` 的 SQUAD 分支里丢失，之后 `lineup()` 的签名根本容不下它 ⇒ 信息在**两处**被截断。
- 三问②「连在谁的链条上」：`ace()` 的返回值同时承担三件事 —— ①"这个阵营有哪台 ACE"②"AI 补出来的那台"③兜底。⇒ 所以"玩家挑一台"这件事无处表达。
- 三问③「注释与代码相反」：✅ **命中**。菜单注释说「敌机由编制决定（不选敌机）」，但**敌机页在 SQUAD 下依然可选可切**（`:1479-1492` 处理 `Stage.ENEMY` 的左右拨）⇒ 界面允许玩家做出一个被静默丢弃的选择。

**方案**

- **方案 A（推荐）**：
  1. `BattleFormation.lineup(side, player_suit, ace_override := -1)` —— 第三个参数**默认 −1 ⇒ 旧行为逐位不变**；
  2. `lineup()` 里 `var ace := (ace_override if ace_override >= 0 else r.ace())`，并**守卫同阵营**（`r.all_suits().has(ace_override)`，现有 `:297-298` 已有这个守卫的雏形）；
  3. `main_menu._launch()` 的 SQUAD 分支补上 `enemy_suit = selected_enemy()`；
  4. `main.spawn_squad()` 把它传进 `lineup(foe_side, -1, enemy_ace)`。
- **方案 B**：只在菜单侧把 SQUAD 的敌机页**禁掉**（把"选敌方 ACE"这个入口从 SQUAD 移除）。**代价**：用户明确想要"小队战里能选敌方是谁"（这就是这条 bug 的来源）⇒ 不接受。
- ⚠️ **新增约束（要拍板）**：ACE **必须同阵营**。玩家在 SQUAD 先选阵营，敌方就是另一阵营 ⇒ 敌机池只能是**那个阵营的 ACE**：
  - 玩家选马夫蒂 ⇒ 敌方 = 联邦 ⇒ 可选 **{佩涅罗佩, 阿利宙斯}**
  - 玩家选联邦 ⇒ 敌方 = 马夫蒂 ⇒ 可选 **{柯西}**（唯一一台）
  ⇒ 今天写死的 `ENEMY_SUITS = [XI, PENELOPE, ARIZEUS]` 在 SQUAD 下是**错的**（会把柯西当联邦的 ACE 送到对面 = 跨阵营，正是 `battle_formation.gd` 注释里已经踩过的那类坑）。

**可证伪判据 + 负对照**

1. **纯函数**：`lineup(FEDERATION, -1, ARIZEUS)` 返回名单里 `aces` 槽（或那台 ACE 单位的 id）== `ARIZEUS`。
   **负对照**：`lineup(FEDERATION, -1)` （默认 −1）必须**仍然**给出 `PENELOPE` ⇒ 证明"旧行为没被改"。
2. **同阵营守卫**：`lineup(FEDERATION, -1, MESSER_M01)`（跨阵营）必须**退回** `r.ace()` 或 `r.mp()`，**不得**把梅萨放到联邦那边。
   **负对照**：去掉守卫 ⇒ 本断言红。
3. **接线（能变红的那个）**：菜单侧 —— 在 SQUAD 下把 `enemy_index` 拨到 ARIZEUS，`start_match` 发出的第 5 个参数必须 == `ARIZEUS`。
   **负对照**：删掉 SQUAD 分支那一行 ⇒ 红（今天就是红的）。
4. **端到端**：`spawn_squad()` 之后，敌方 ACE 单位的 `profile.id` == 菜单选的那台（用 `units_root` 找 `is_ace` 的那一台）。
5. **菜单池**：SQUAD 下敌机页的行**必须**来自"敌方阵营的 ACE 池"，而不是写死的三台。
   **负对照**：把池子写回 `ENEMY_SUITS` ⇒ 玩家选联邦时列表里仍出现柯西 ⇒ 红。

**未决** · P4（SQUAD 的敌机池是否按阵营过滤 —— 建议按，且这属于修 bug 的一部分而不是新需求）

---

### 2.5 · B5 · 阿利宙斯偶尔一直跑路，要增强其进攻欲望

**用户原话** · 「阿利宙斯偶尔会一直跑路，需要让他进攻欲望增强。」

**结论强度** · **已定位**（旋钮唯一）· 但"为什么偶尔"目前是**候选，缺现场**

> ### ★★ 施工期实测修正（轮 63-9 · B5 落地时发现：**方案 A 照拍板执行，但正文判据 1 的目标值口径错了；另外摸到一条「脉冲在远距是无声的」**）
>
> **修正 0 · 下面正文里的 `bandit_ai.gd:121` / `:731-733` / `:783-796` 等行号是改前的。**
> 改后 `bandit_ai.gd` 55200 → **57182** B，`ACE_ATTACK_PERIOD` 在 `:805`、
> `ACE_COMMIT_WINDOW` 在 `:815`、状态机第三条出口在 `:877` 附近。
>
> **修正 1 · ★★ 判据 1 的目标「阿利宙斯 ≥ 45%」口径错了。**
> 45% 是按 `README.md:1678` 那张历史标定表（`×1.14 ⇒ 34.4%`）推的，
> 而那张表**不是本探针口径**。用 `tools/probe_aggression.tscn`
>（3 态势 × 60 s、AI 对 AI、`--fixed-fps 60`）在**改动前**跑出来：
>
> | 难度 | ATTACK 占比 | 躲+脱离 | 平均交战距离 |
> |---|---|---|---|
> | 简单 | 72.6% | 10.2% | 2686 m |
> | 中等 | 65.6% | 12.9% | 3640 m |
> | **困难** | **29.4%** | **26.9%** | **5259 m** |
> | 平均 | **55.9%** | — | — |
>
> ⇒ **「≥ 45%」在改动前就已经满足了**（平均 55.9%），它根本不是个判据。
> 真正对应老板那句「偶尔会一直跑路」的是**困难档**：29.4% 在进攻、
> **26.9% 在躲或脱离**。⇒ 可行动的口径 = **困难档**（下表里它也是唯一有区分度的一列）。
> ⚠️ 顺带一个好消息：这个探针是**确定性**的 —— 同一状态下跑两遍逐位相同
>（55.9% / 55.9%，12/4 那一行在取曲线时又复现了一次），
> 所以"再跑一遍对一下"在这里是**有效**的验证手段，不是安慰剂。
>
> **修正 2 · ★★ 旋钮曲线（四个取值，实测）** —— 正文只给了 12→9 一个点：
>
> | PERIOD / WINDOW | 占空比 | 简单 | 中等 | **困难** | 平均 |
> |---|---|---|---|---|---|
> | 12.0 / 4.0（原稿） | 33.3% | 72.6% | 65.6% | **29.4%** | 55.9% |
> | 12.0 / 5.0 | 41.7% | 80.9% | 73.0% | **70.8%** | 74.9% |
> | 10.0 / 4.5 | 45.0% | 85.8% | 85.8% | **82.8%** | 84.8% |
> | **9.0 / 5.0（拍板 P6，已落地）** | 55.6% | 85.7% | 87.4% | **87.5%** | **86.9%** |
>
> 两个观察：
> ① **起决定作用的是窗口**：`12/4 → 12/5` 单独就把困难档从 29.4% 抬到 70.8%；
>    周期再收到 9 只是把它推到 87.5%。也就是说这条曲线**很陡**，
>    而"窗口"那 1 秒是性价比最高的一笔。
> ② **已经接近饱和**：困难档 87.5% 进攻 / **4.2%** 躲或脱离 ⇒ 王牌机几乎不再脱离。
>    ⚠️ 这是**收益也是风险**（可能变成"一直冲、不躲"）。记在这里：
>    若老板玩下来觉得"太莽"，**退档只有一个字**（真源只有一处：
>    `bandit_ai.gd` 的 `ACE_ATTACK_PERIOD` / `ACE_COMMIT_WINDOW`）：
>    `12.0 / 5.0 ⇒ 困难 70.8%`，或 `9.0 / 4.0 ⇒ 占空比 44.4%（未单独实测）`。
>
> **修正 3 · ★★★ 施工期最重要的发现：强制脉冲在**远距是无声的**。**
> `_tick_ace_pressure()` 触发时只做三件事：清 `_ace_pressure`、
> 置 `_ace_commit = ACE_COMMIT_WINDOW`、`set_state(ATTACK)`。
> **但同一帧**紧接着的 `_decide_desired_direction()` 会把它推翻 ——
> ATTACK 那一支有三个出口，而 `_ace_commit` 只守住了前两个：
>
> | 出口 | 有没有被窗口守住 |
> |---|---|
> | `_ace_commit <= 0.0 and dist < break_dist()` ⇒ `EXTEND` | ✅ 守住了 |
> | `_ace_commit <= 0.0 and threatened and _state_time > ...` ⇒ `EVADE` | ✅ 守住了 |
> | `dist > engage_dist() * 1.35` ⇒ `SEEK` | ❌ **没守** |
>
> ⇒ 远距触发脉冲之后，状态**当帧就回到 SEEK**。
> 实测指纹（`suite_ace_pressure` §④-b：120 km、观察一个周期）：
> `_ace_pressure` 约在第 **540** 帧归零、`_ace_commit` 被武装成比 0 大，
> 但整个观察窗里 `state` **一个都没变过**（全程 SEEK）。
>
> **为什么不把它当 bug 修**（这一步是量出来的，不是猜的）：
> 看 `_direction_for_state()` —— 远距时 `ATTACK` 与 `SEEK` 走的是**同一个方向**
>（`dist >= gun_range` ⇒ 两边都返回 `_intercept_dir_beam()`），
> 差别**只在油门**：`SEEK` 是 `0.92 + boosting`、`ATTACK` 是 `1.0 + 不 boost`。
> ⇒ 让位给 SEEK **更快**；硬把 ATTACK 钉在远距上反而**拖慢**它压上去
>（"更凶"变成"更慢"，与需求反着走）。
> 负对照 `nc_far_guard`（把窗口守门也加到第三条出口上 = 把"让位"当 bug 修掉）
> ⇒ **只红 §④-b 那两条**，证明那两条判据确实咬在这条行为上。
> ⇒ 本轮**只加注释**（`bandit_ai.gd` 里 `elif dist > engage_dist() * 1.35:` 上方那一段）
> 并用 §④-b 把行为钉住，免得下一个人把它当 bug"修"掉。
> ⚠️ 由此得到一条判据纪律：**这条脉冲只在 `break_dist() < dist < engage_dist() * 1.35`
> 那一段里有可观测效果**，判据必须站在那一段上；站在 120 km 上量到的只是"让位"。
>
> **修正 4 · 正文判据 1~4 的落地**
>
> | 正文判据 | 落地 |
> |---|---|
> | 1 · 探针 ATTACK 占比 ≥ 45% | 目标改成**困难档**（见修正 1）；探针不进套件（绝对值随态势漂），读数与曲线写进交付件 |
> | 2 · 占空比 ≥ 某个下界 | 取 **0.5**（`ACE_COMMIT_WINDOW / ACE_ATTACK_PERIOD`，实测 0.556） |
> | 3 · SEEK 的 throttle 与 AGGRESSION 耦不耦 | 取**第二个选项**（不耦）+ 注释 + 断言钉住。理由：SEEK 是**巡速**，接上 AGGRESSION 等于让"更凶"顺便"更快"，与 D1（追不上）反着走 |
> | 4 · 五个量在改动前后逐位不变 | 落成**源码字面量扫描 17 条**（机炮 / 光束锥角、两条开火判据、两条点射时长、导弹距离窗口、齐射冷却、`SAFE_ALTITUDE` / `CRITICAL_ALTITUDE`、`AGGRESSION`、`difficulty` 的四个 lock 量 × 三档） |
>
> **新判据**：`tests/suite_ace_pressure.gd`（5 段 / **51 PASS / 0 FAIL**）；
> **四个负对照全部精确咬住**（每次回滚后 `bandit_ai.gd` 的 md5 与金标逐位一致）：
>
> | 变体 | 红 | 咬在哪 |
> |---|---|---|
> | `nc_period12`（周期回 12.0） | **3** | **只**红 §① 的周期值 / 方向 / 占空比 |
> | `nc_window4`（窗口回 4.0） | **3** | **只**红 §① 的窗口值 / 方向 / 占空比 |
> | `nc_far_guard`（把第三条出口也守上） | **2** | **只**红 §④-b（远距只触发、不换态） |
> | `nc_no_gate`（去掉"只对 ACE 生效"的闸门） | **2** | §① 结构 1 条 + §④-a 真机 1 条（量产机 **361 帧** 在 ATTACK） |
>
> **⚠️ 施工期踩过的两个夹具坑**（写下来，省下一次重走）：
> ① 状态机量的是 `_aim_pos()` —— **滞后**的瞄准点，实测比真实间距**近约 500 m**。
>    第一版按 `engage_dist() * 1.15` 钉间距，有效距离掉到 3163 m < 3192 m
>    ⇒ 第 **262** 帧就**自然**转进 ATTACK，看着像"提前乱冲"。
>    ⇒ 改成 `* 1.30`，并把"有效距离始终在接战距离之外"做成**实测断言**而不是假设
>    （前提一旦不成立它会自己红出来，而不是把结论悄悄带歪）。
> ② 给"量产机不吃这个节拍"配靶机时**不要与 ACE 共用同一个**：
>    几何不同 ⇒ 滞后方向不同 ⇒ 实测量产机的有效距离变成 **4788 m**，
>    掉到让位线（`engage_dist() * 1.35 = 4309 m`）**之外** ⇒
>    就算去掉闸门它也会被距离条款挡住 ⇒ **负对照咬不到**（差一点就成了假绿）。
>    各配一套之后 `nc_no_gate` 才咬到 361 帧。
>
> **本轮的实际改动**
>
> | 文件 | 改前 → 改后（字节） | md5（改后） | 改动 |
> |---|---|---|---|
> | `scripts/ai/bandit_ai.gd` | 55200 → **57182** | `c68f5387ae314549165c1f90d150b483` | ①`ACE_ATTACK_PERIOD 12.0 → 9.0` ②`ACE_COMMIT_WINDOW 4.0 → 5.0` ③第三条出口上方补一段说明 ④调用点 / 量产机说明 / 窗口守卫注释里的"12 秒"改成中性说法 |
> | `tests/suite_hardmode.gd` | 13725 → **14616** | `53e749132ad4fcad0fd93679ad0ea0ad` | ①那条把 `12.0` 写死的回归门改成 `9.0` + 沿革 ②新增占空比下界两条 ③节名与六处"12 秒"文案 |
> | `tests/suite_ace_pressure.gd` | 新建 **17576** | `0bd08d4922313b643efd226aa72bded5` | 5 段 / 51 PASS |
> | `tests/test_runner.gd` | 23997 → **24140** | `8e4ac2863eeea8bf8b140d7c5d3e8945` | 注册 `AcePressure` |
> | `README.md` | 307275 → **307480** | `ea8172885f863c00c17d507c30ad1aea` | §22.1「ACE 规则」那一行：12 秒 / 4 秒 → **9 秒 / 5 秒**（不改就是规格书在撒谎） |
>
> **未决 P6 至此落地**：取 **ACE 通用**（不是阿利宙斯专属），且**不碰 `AGGRESSION`**。
> 正文那句「"偶尔"到底对应哪个候选」也有答案了：**候选 1（周期窗口）** ——
> 光是占空比上去，困难档就从 29.4% 变 70.8%，不是"被锁定的代价"也不是燃料槽。

**一句话根因** · AI **没有**"进攻欲望"这个变量，它就是「一场战斗里处于 `ATTACK` 的时间占比」；唯一旋钮是 `bandit_ai.gd:121 const AGGRESSION := 1.14`，落在 5 处。

**证据（文件:行）**

| 位置 | 内容 |
|---|---|
| `scripts/ai/bandit_ai.gd:121` | `const AGGRESSION := 1.14`（带长篇换算注释） |
| `scripts/ai/bandit_ai.gd:731-733` | `engage_dist() = engage_range × AGGRESSION` |
| `scripts/ai/bandit_ai.gd:736-738` | `break_dist() = break_range / AGGRESSION` |
| `scripts/ai/bandit_ai.gd:741-743` | `evade_seconds() = lerpf(4.2, 2.4, skill) / AGGRESSION` |
| `scripts/ai/bandit_ai.gd:746-748` | `extend_seconds() = lerpf(4.5, 2.6, skill) / AGGRESSION` |
| `scripts/ai/bandit_ai.gd:783-796` | `_tick_ace_pressure()`：**只对 ACE 生效**，每 `ACE_ATTACK_PERIOD(12.0)` 秒强制 `set_state(ATTACK)` + `_ace_commit = ACE_COMMIT_WINDOW(4.0)` |
| `scripts/ai/bandit_ai.gd:1090-1106` | `_drive_throttle()`：`EXTEND/EVADE ⇒ throttle 1.0 + boosting`；**`SEEK ⇒ throttle 0.92`（没有接 AGGRESSION）**；`ATTACK ⇒ lerpf(0.45, 1.0, …)` 且 `boosting = false` |
| `scripts/ai/bandit_ai.gd:1114-1118` | `_drive_shield()`：`dist < 1600 and _is_locked_by_player()` 或 `hp < 25%` 想举盾 |
| `README.md:1678` | 历史标定表：`×1.00 ⇒ 26.4%` · `×1.30 ⇒ 46.3%（+75%，过头）` · `×1.12 ⇒ 33.1%` · **`×1.14 ⇒ 34.4%（+30.3%）`** |
| `README.md:1680` | 基线里另一个反常：**难度越高、攻击占比越低**（30.6 / 24.8 / 23.7%） |
| `scripts/ai/bandit_ai.gd:112-119` | 明写**刻意不动**的四件事：射击锥角 / 点射节奏 / 导弹发射概率（那是准头射速）· `difficulty.lock_*` · 避地安全线 |

**一个非显然的结论（值得单列）**

> **调高 `AGGRESSION` 会让它"少跑"**——因为 `EXTEND / EVADE` 是**唯一**给到 `throttle 1.0 + boosting` 的状态，
> 而 `ATTACK` 反而是 `boosting = false`、油门 `lerpf(0.45, 1.0, …)`。
> ⇒ 提高 `AGGRESSION` = 缩短逃跑时长 + 缩小脱离距离 + 拉长交战距离 ⇒ **平均速度下降**。
> 这条正好与 D1（m02 追不上）同向，可以一起用。

**"偶尔"的候选（按可能性排序，都还没证实 ⇒ 缺现场）**

1. **`_tick_ace_pressure` 的周期窗口**：阿利宙斯是 ACE ⇒ 每 12 s 才被强制 ATTACK 4 s ⇒ 上界 4/12 = **33%**；剩下的 8 s 若一直判 `EXTEND/EVADE`，玩家就会看到"一直跑"。
2. **被锁定的代价**：`_drive_shield` 的 `_is_locked_by_player()` 与状态机里的被威胁判定会让它 EXTEND —— 玩家一锁上它就跑（"偶尔"= 玩家锁上它的时候）。
3. **燃料槽**：`resolve_jet_gauge()` 裁决下，量产机/ACE 的加力时机不同（ACE 不骑板、自己扛燃料）⇒ 槽空时退巡航，表现为"节奏性的快慢变化"。

**方案**

- **方案 A（推荐）**：**不动 `AGGRESSION`**（它已标定到 +30% 且历史表在案），改 **ACE 专属**的两个常量：`ACE_ATTACK_PERIOD 12.0 → 9.0`、`ACE_COMMIT_WINDOW 4.0 → 5.0`（占空比 33% → 56%）。
  - 理由：① 用户抱怨的对象是**阿利宙斯**，而阿利宙斯是 ACE；② `_tick_ace_pressure` 是**唯一**为"ACE 该更凶"专门写的机制，改动范围最窄；③ 不会连带改掉 `AGGRESSION` 那张历史标定表。
- **方案 B**：`AGGRESSION 1.14 → 1.22`（+2 档）。代价：全局生效（所有 AI 都更凶），并且与 `README.md:1678` 那张表脱钩，需要重跑 `probe_aggression` 重新标定。
- **方案 C（否决）**：把 `SEEK` 的 `throttle 0.92` 顶到 1.0 —— 那是**速度**不是欲望，会让"追不上的对手"更追不上（与 D1 反向）。**但**：把 `SEEK` 的 throttle **接上 AGGRESSION** 是可以的（见判据 3）。

**可证伪判据 + 负对照**

1. **真 AI 对打探针**（既有工具）：`tools/probe_aggression.tscn` 量 ATTACK 时间占比。
   - 目标：阿利宙斯 ≥ 45%（现状读数**必须先跑出来**当基线，不能凭记忆写）。
   - **负对照**：把 `ACE_ATTACK_PERIOD` 改回 12.0 ⇒ 必须跌破阈值。
2. **占空比**（纯函数级）：`ACE_COMMIT_WINDOW / ACE_ATTACK_PERIOD` 必须 ≥ 某个下界（把"想让它多凶"变成可算的数）。
3. **`SEEK` 与 AGGRESSION 的耦合**（这条今天会红，是"没有可证伪判据"的典型）：
   `aggression = 1.14` 与 `aggression = 2.0` 两种取值下，`SEEK` 的 `fm.throttle` 必须**不同**。
   **负对照**：今天两者完全相同（都是 0.92）⇒ 红。要么接上，要么把"AGGRESSION 不影响巡速"写进注释并加一条断言钉住。
4. **不许连带**：射击锥角 / 点射节奏 / 导弹发射概率 / `difficulty.lock_*` / `SAFE_ALTITUDE` 五个量在本次改动前后**逐位不变**（这也是可断言的）。

**未决** · ~~P6（只调 ACE 还是调全局）~~ —— **轮 63-9 已拍定并落地**：取 **ACE 通用**（`ACE_ATTACK_PERIOD 12.0 → 9.0` + `ACE_COMMIT_WINDOW 4.0 → 5.0`），**不碰** `AGGRESSION`。
~~以及「"偶尔"到底对应哪个候选」~~ —— 也有了答案：**候选 1（周期窗口）**（困难档 ATTACK 占比 29.4% ⇒ 70.8%，见本节顶部「施工期实测修正」）。

---

### 2.6 · B6 · 去掉长按 T 丢枪、保留 T 撑盾、撑盾免伤改 80%

**用户原话** · 「把长按 t 的丢枪去掉，保留 t 撑盾的功能，把撑盾的免伤改为 80%。」

**结论强度** · **已定位**

**⚠️ 一处重要的自我纠正（先说）** · 我原本准备问"你说的长按 T 丢枪其实是长按 R 吧" —— **查完发现用户没说错**：
`_tick_holds()` 的**第二支读的就是 `shield` 动作**，而 `shield` = 键盘 **T** / 手柄 **B**。
⇒ **长按 T 确实会丢枪**。同时存在的是**长按 R（`reload`）**那一支。

**一句话根因** · 丢枪有**两条输入路径**（`reload` 与 `shield`），用户要去掉的是 `shield` 那一条；
免伤落点是单一字段 `profile.shield_reduction`（`flight_body.gd:5226`），但它有 **6 处不同的值**，要改**哪几处**需要拍板。

**证据（文件:行）**

| 位置 | 内容 |
|---|---|
| `scripts/flight/player_controller.gd:263-275` | `_tick_holds()`：`var r := ...("reload")` / `var b := ...("shield")`；两支都 `_try_discard_rifle()`；`:270 var p := maxf(_hold_discard_r.progress(), _hold_discard_b.progress())` |
| `scripts/flight/player_controller.gd:78-80` | `_hold_discard_r` / `_hold_discard_b` / `_discard_warned` |
| `scripts/flight/player_controller.gd:92-93` | 两者都 `configure(0.6)`（长按 0.6 s） |
| `scripts/flight/player_controller.gd:385` | `func _try_discard_rifle()` |
| `scripts/flight/player_controller.gd:375-390` | 三条 `notice.emit` 文案：「已脱离飞行踏板」「本机不能丢弃步枪」「没有可丢弃的步枪」 |
| `scripts/flight/player_controller.gd:580-586` | `_read_shield_key()`：`just_pressed("shield")` ⇒ `has_pedal()` 时 `dismount_pedal()`，否则 `raise_shield()` ← **T 的另一个语义（要保留）** |
| `scripts/autoload/input_setup.gd:36` | `"shield": [KEY_T]` |
| `scripts/autoload/input_setup.gd:37` | `"reload": [KEY_R]` |
| `scripts/autoload/input_setup.gd:559-560` | 手柄：`shield = JOY_BUTTON_B` / `reload = JOY_BUTTON_Y` |
| `scripts/autoload/input_setup.gd:778` | 帮助表那一行：`[[["kb","reload"], " 长按"], "丢弃步枪 · 仅柯西（长按 0.6 s，HUD 有进度提示）", "长按 B"]` ← **手柄列写"长按 B"是对的（因为代码读 `shield`）**，删掉那一支之后**必须改成"长按 Y"** |
| `scripts/autoload/input_setup.gd:715` | `SHARED_KEYS_OK` 含 `["menu_back","shield"]`（手柄 B 一键两义，阶段互斥） |
| `scripts/data/suit_profile.gd:751` | `var can_discard_rifle := false`（只有柯西开） |
| `scripts/data/suit_profile.gd:791` | `discard_unlockable_seconds := 15.0` |
| `scripts/flight/flight_body.gd:5226` | `to_hull *= (1.0 - profile.shield_reduction)` ← **免伤唯一落点** |
| `scripts/data/suit_profile.gd:326` | 默认 `var shield_reduction := 0.55` |
| `scripts/data/suit_profile.gd:1452` | 柯西 **0.55** |
| `scripts/data/suit_profile.gd:1559` | 佩涅罗佩 **0.35** |
| `scripts/data/suit_profile.gd:2133` | 阿利宙斯（主形态）**0.45** |
| `scripts/data/suit_profile.gd:2218` | 阿利宙斯（其余形态）**0.30** |
| `scripts/data/suit_profile.gd:2291` | 古斯塔夫 00 **武装** **0.30** |
| `scripts/data/suit_profile.gd:2387` | `_gustav_base()` **0.0** ← **靶机没有盾**（配套 `ifield_hp = 0.0`），**语义不是"免伤 0%"而是"没有这个功能"** |
| `scripts/data/suit_profile.gd:2509` | 梅萨 M01 / CMD / F01 共用 **0.40** |
| `scripts/data/suit_profile.gd:1152-1153` | 存活率文案 `举盾减伤 %d%%`（自动跟着走） |
| `scripts/ui/hud.gd:2545` | `"SHIELD UP  -%d%%"` |
| `scripts/ui/hud.gd:3096` / `:3100` | 面板那一列 |
| `scripts/ui/main_menu.gd:3360-3361` | 机体卡「举盾减伤」 |
| `tests/suite_abilities.gd:889-920` | `_discard_rifle()` 测的是**机体方法**与 AI 丢枪规则，**不测输入长按** ⇒ 删掉 `shield` 那一支**不会**直接变红（所以必须**新加**判据） |

**方案**

- **丢枪侧**：
  1. 删掉 `_tick_holds()` 里 `_hold_discard_b` 那一支（`:268-269`），并把 `:270` 的 `maxf(...)` 收敛成 `_hold_discard_r.progress()`；
  2. 删掉 `_hold_discard_b` 的声明（`:79`）与 `configure`（`:93`）；
  3. **同步改帮助表** `input_setup.gd:778` 的手柄列：`"长按 B"` → `"长按 Y"`（**这条最容易漏，且漏了不报错**）；
  4. 保留长按 R / 长按 Y（用户只说去掉 T）。
  ⚠️ 删除后 `_hold_discard_b` 若留成死变量，`suite` 里若有"扫描未使用变量"的 gate 会抓；确认一下有没有。
- **免伤侧**：
  1. `flight_body.gd:5226` **一个字都不改**（那是唯一正确的落点）；
  2. 改 `SuitProfile` 里的**逐机值**。建议：**所有"有盾"的机体统一 0.80**，`_gustav_base()` 的 **0.0 保持不动**；
  3. 顺手加一条**上限断言**（今天很可能没有）：`shield_reduction <= 0.85` 之类，防止将来有人写 1.0（= 免伤 100%）；
  4. 加一条"靶机不许有盾"的负断言：`not gustav_target().can_raise_shield()` 或 `shield_reduction == 0.0`。
- ⚠️ **平衡副作用（必须写在文档里给拍板人看）**：柯西 0.55 → 0.80 意味着**承伤系数 0.45 → 0.20**，即 **2.25 倍耐打**；
  这是一次**大幅强化**（不是"小调"），会直接改变所有对战/联机/剧情的难度手感。
  而现有的回归门（`suite_round` 的"敌机极速 ≤ 玩家加力 × 0.92"、`suite_round14` 的 27 种组合）**都不覆盖盾的减伤** ⇒ 改完没有任何门会拦住它。

**可证伪判据 + 负对照**

1. **负对照（带牙齿的那条）**：模拟长按 `shield` 0.7 s ⇒ `_try_discard_rifle()` **不得**被调用（枪还在）；
   模拟长按 `reload` 0.7 s ⇒ **必须**被调用。
   实现方式：给 `PlayerController` 加一个可读的 `discard_count`（或复用 `notice` 文本断言）。
   **负对照**：把 `_hold_discard_b` 那一支加回去 ⇒ 第一条必须红。
2. **T 的另一个语义没被误伤**：长按 `shield` ⇒ **仍然**走 `raise_shield()`（或骑板时 `dismount_pedal()`）。
   **负对照**：把 `_read_shield_key()` 一起删掉 ⇒ 红。
3. **文案一致性**：`HELP_SECTIONS` 里"丢弃步枪"那一行的手柄列，必须与代码里**实际存在的入口**一致（一条把两处绑起来的断言）。
   **负对照**：保留 `"长按 B"` 而代码已删掉 `shield` 支 ⇒ 红。
4. **免伤表**：逐机断言 `xi / penelope / arizeus / arizeus其它形态 / gustav00_armed / messer_* == 0.80`，**且 `_gustav_base() == 0.0`**。
   **负对照**：把 `_gustav_base()` 也改成 0.80 ⇒ 第 4 条必须红。
5. **显示同源**：`hud.gd:2545 / :3096` 与 `main_menu.gd:3360` 读的都是 `profile.shield_reduction`（断言"显示不另抄一份 80"）。

**未决** · P2（改哪几项）· P3（长按 R 保不保留）

---

## 3. 逐项（设计 1~5）

### 3.1 · D1 · m02 的梅萨一直逃跑、追不上打不死

**用户原话** · 「m02 梅萨一直在逃跑，速度太快追不上所以打不死，要削弱一下 M02 本关的梅萨飞行速度，增强一点他的进攻欲望。测试玩家们反馈 m02 的梅萨就是打不到、追不上、打不死。」

**结论强度** · **已定量证实**（两套算式，可复算）

> ### ★★ 施工期实测修正（轮 63-9 · D1 落地时发现，**结论不变、绝对值全错**）
>
> **修正 1 · m02 的玩家机是「古斯塔夫 00 武装版」`speed_scale 0.85`，不是下面写的 0.55。**
> 剧情关玩家机走 `main.spawn_challenge()` 的 `SuitProfile.by_id(Game.active_suit)`
> （`main.gd:1628`），而 `by_id(Id.GUSTAV00)` **默认返回 `gustav00_armed()`**
> （`suit_profile.gd:2738-2759` 的注释写得很清楚：靶机版只能被显式索取，
> 只有 `main.spawn_training()` 这么干）。
> ⇒ 实测读数：`player.player_top_speed() = 856.8`、`player_boost_speed() = 1285.2`
>（下面表里的 554 / 832 应为 **856.8 / 1285.2**）。
>
> **修正 2 · 「三档难度下完全相同」只对旧口径成立。**
> 天花板 `0.92 × 加力` 要**先低于**敌机自己的上限才会出现「三档一致」：
> · 玩家 0.55 ⇒ 天花板 **765.07** < 梅萨下限 927.36 ⇒ 三档都被咬 ⇒ 一致；
> · 玩家 0.85 ⇒ 天花板 **1182.384** **>** 简单档的 927.36 ⇒ **简单档不被咬，三档不一致**。
>
> **修完之后的真读数**（引擎速度域，实测见 `_r63_9_d1_green.log`）：
>
> | 难度 | 现状敌机极速 | /玩家巡航 856.8 | 本关(×0.75) | /巡航 | 加力接近速度(现状→本关) |
> |---|---|---|---|---|---|
> | 简单 | 927.36 | 1.082× | 695.52 | 0.812× | 357.8 → 589.7 m/s |
> | 中等 | **1182.384** | **1.380×** | **886.788** | **1.035×** | **102.8 → 398.4 m/s（3.87×）** |
> | 困难 | 1182.384 | 1.380× | 886.788 | 1.035× | 102.8 → 398.4 m/s |
>
> ⚠️ 所以「追不上」**只在中等/困难成立**（简单档本来就能追上，只是慢）。
> P5 的 **×0.75 拍板不变** —— 中等档加力接近速度从 102.8 提到 398.4 m/s，
> 39.6 km 的纯追击最坏情况 385 s → 99 s。
> ⚠️ 另一条口径：`player_top_speed()` 注释原话「2026-09-25 起这两个数**是实际速度**
> （已含 `SPEED_REAL_MULT`）」⇒ 下面那张表里「12 km 追平 75 s」把 2.4 多计了一次，
> **绝对秒数不可信，比例可信**（修正后 102.8 → 398.4 是 3.87 倍，这个比例与口径无关）。


**一句话根因** · **两条独立根因叠加**：
(a) 本关玩家机是**古斯塔夫 00（`speed_scale 0.55`）**，敌机是**梅萨（0.92）** ⇒ 底子上玩家就慢 1.67 倍；
(b) 敌机极速被"≤ 玩家加力 × 0.92"钉在 **765**，而玩家**巡航**只有 **554** ⇒ **敌机是玩家巡航的 1.38 倍**、且在**三档难度下完全相同**（天花板先咬住）⇒ 不按加力就**永远**追不上。

**读数（`_d2_speed.py` 复刻四个速度函数算出；显示域，真机 ×2.4）**

| 机体 | speed_scale | 巡航 | 加力 |
|---|---|---|---|
| 柯西 XI | 1.50 | 1512 | 2268 |
| 佩涅罗佩 | 1.55 | 1562 | 2344 |
| 阿利宙斯 常态 | 1.55 | 1562 | 2344 |
| 阿利宙斯 巡航 | 1.5965 | 1609 | 2414 |
| 阿利宙斯 核心 | 1.455 | 1467 | 2200 |
| **古斯塔夫 00 常态** | **0.55** | **554** | **832** |
| 古斯塔夫 00 武装 | 0.85 | 857 | 1285 |
| **梅萨 M01/CMD/F01** | **0.92** | **927** | **1391** |

**m02 对局表（玩家古斯塔夫 00 常态 vs 梅萨）**

| 难度 | 玩家巡航 | 玩家加力 | 敌机上界 | 天花板 | **敌机极速** | **极速 / 玩家巡航** | **加力追平 12 km** |
|---|---|---|---|---|---|---|---|
| 简单 | 554 | 832 | 927 | **765** | **765** | **1.38×** | **75 s** |
| 中等 | 554 | 832 | 1206 | **765** | **765** | **1.38×** | **75 s** |
| 困难 | 554 | 832 | 1391 | **765** | **765** | **1.38×** | **75 s** |

⇒ 与用户反馈完全一致：**追平 12 km 要 75 秒**，而一场交战的窗口根本没那么长。

**削弱档位（k = 玩家巡航 / 敌机极速，k ≥ 1.0 就是"不按加力也追得上"）**

| 档 | 敌机极速 | 相对玩家巡航 | 加力相对速度 | **追平 12 km** |
|---|---|---|---|---|
| 现状 ×1.00 | 765 | **1.38×** | 160 m/s | **75 s** |
| **×0.85** | 650 | 1.17× | 435 m/s | **27 s** |
| **×0.75（建议）** | **574** | **1.03×** | **619 m/s** | **19 s** |
| ×0.62 | 474 | 0.86× | 857 m/s | **14 s** |

（全表见 `_d2_speed.out` §③；`k(追平) = 554/765 = 0.725`）

**证据（文件:行）**

| 位置 | 内容 |
|---|---|
| `scripts/data/mission_script.gd:1505-1540` | `m02()`：`player_suit = GUSTAV00`（`:1513`）、`enemy_suit = MESSER_M01`（`:1512`）、`arena = "DAVAO"`、`waves = _davao_waves(...)`（`:1517`）、`objectives = [destroy_all(1, "击溃一台梅萨")]` |
| `scripts/data/mission_script.gd:1369-1372` | `DAVAO_INTERCEPT_SHAPE := [{"count": 1, "alt": EARTH_ALT, "spread": 62.0, "aggr": false}]` ← **`aggr: false`**（出场不进入 ATTACK） |
| `scripts/data/mission_script.gd:1374-1379` | `_davao_waves()` |
| `scripts/data/mission_script.gd:151` | `EARTH_ALT = 3200.0` |
| `scripts/data/challenge_script.gd:16-35` | `class Wave`：`count / suit / altitude / spread_deg / aggressive`（**没有速度字段**） |
| `scripts/main.gd:2384-2387` | `_attach_ai(wave.suit, ...)` + `if wave.aggressive: ai.set_state(BanditAI.State.ATTACK)` |
| `scripts/data/suit_profile.gd:2371` | `_gustav_base()`：`target_height 22.0`、`speed_scale 0.55`（`:2385` 附近） |
| `scripts/data/suit_profile.gd:2532` | `messer_m01()`：`p.speed_scale = 0.92`（M01/CMD/F01 共用） |
| `scripts/data/suit_profile.gd:2801/2805` | `player_top_speed()` / `player_boost_speed()` |
| `scripts/data/suit_profile.gd:2814/2840/2850` | `enemy_top_speed(sm)` / `enemy_speed_ceiling(pb)` / `enemy_top_speed_capped(sm, pb)` |
| `scripts/data/suit_profile.gd:2836` | `ENEMY_SPEED_CEILING_RATIO = 0.92` |
| `scripts/ai/bandit_ai.gd:267-269` | `_apply_top_speed()`：`var top := profile.enemy_top_speed_capped(difficulty.speed_mult, _player_boost_reference()); fm.configure(top, top)` |
| `scripts/ai/bandit_ai.gd:60-62` | 「速度天花板 = 玩家加力 ×0.92」那条**第十四轮的回归门**（`suite_round14` 的 27 种组合）**动不得** |
| `tests/suite_round.gd` / `tests/suite_round14.gd` | 那条不变量就住在这两个套件里 |

**方案**

- **方案 A（推荐）**：新增 `Mission.enemy_speed_mult := 1.0`（`mission_script.gd` 的 `Mission` 类，`:1005`），m02 填 `0.75`；`BanditAI._apply_top_speed()` 把它乘进 `top`。
  - 优点：默认 1.0 ⇒ **其余全部关卡与模式逐位不变**；可单测（纯数据 + 一处乘法）；粒度正好是"本关"。
  - 配套：`m02` 的 `DAVAO_INTERCEPT_SHAPE` 把 `aggr` 改成 `true`（出场就 ATTACK）**或**走方案里的进攻欲望（见下）。
- **方案 B**：给 `ChallengeScript.Wave` 加 `speed_mul` 字段。粒度更细（可以只调某一波），但 `Wave._init` 是 **5 参位置参数**（`:28`），加参数会撞**所有**既有 `Wave.new(...)` 调用点 ⇒ 风险大于收益。**不推荐**。
- **方案 C（否决）**：直接把 `messer_m01().speed_scale 0.92 → 0.75`。那是**全局**的：小队战 / 对战 / 联机里的梅萨会一起变慢，而且会动到 `suite_round14` 那张"玩家机体 × 敌机机体 × 难度"27 种组合的不变量表。
- **进攻欲望**：与本关的"速度"是**两件事**，且**同向**（见 B5 的非显然结论：提高 `AGGRESSION` = 更多 `ATTACK` = 更少 `boosting` = 平均更慢）。
  ⇒ 建议：本关 `aggr = true`（一处数据）+ **ACE 通用的 `ACE_ATTACK_PERIOD / ACE_COMMIT_WINDOW` 调整**（若 P6 选 A）。

**可证伪判据 + 负对照**

1. **不动机型**（防"顺手换机"）：`m02().enemy_suit == MESSER_M01`、`wave_count == 1`、`waves[0].count == 1` —— 三条**逐位不变**。
   （⚠️ 换机型要动"四件套"：`Mission.enemy_suit` 只给简报、`waves[].suit` 才是真撒的 + 目标 `label` + `comms.RADIO` 正文与说话人 —— 只改一个 = **简报撒谎且不报错**。本方案**不换机**，所以四件套不动。）
2. **追得上**（这一条是本需求的核心，且今天必须红）：
   `enemy_top_speed_capped(m02的难度, player_boost) <= player_top_speed()` —— 即 **k ≥ 1.0**。
   **负对照**：`enemy_speed_mult = 1.0` ⇒ 必须红（今天 765 > 554）。
3. **不越界**：`enemy_speed_mult = 1.0` 的所有既有对局，敌机极速**逐位不变**（守住那条 27 组合不变量）。
   **负对照**：把默认值写成 0.9 ⇒ 红。
4. **进攻欲望**：`probe_aggression` 的 ATTACK 占比 ≥ 阈值（先跑取基线）。
5. **真机**：m02 里 30 秒内能咬到敌机（不看"感觉"，看"两机距离 ≤ 800 m 的累计时长"这种可量的量）。

**未决** · P5（三档选哪个 —— 建议 ×0.75）

---

### 3.2 · D2 · 辅助驾驶模式下 CTRL 切换成"倒着飞"

**用户原话** · 「在辅助驾驶模式下，CTRL 键按下可以切换飞行模式：按下 ctrl 会变成倒着飞，w 就变成减速，s 就变成加速。」

**结论强度** · **设计题**（键位不冲突，缺的是三条语义）

> ### ★★ 施工期实测修正（轮 63-9 · D2 落地时发现：**三条语义与 ①(b) 全部成立，但正文的方案里有一处自相矛盾，且漏掉了一个必然自旋的坑**）
>
> **修正 0 · 变量名落地成 `translate_reverse`（不是下面写的 `reverse_fly`）。**
> 理由：它与 `translate_mode` / `translate_dir` / `translate_fwd` / `translate_dash`
> **同一族、同一层**（都是"平移模式"的派生状态），名字扎堆才好一眼认门；
> 且写入点就在 `translate_mode` 那一行**正下方**。
>
> **修正 1 · ★★ 门必须与 `translate_mode` 同源，不能用 `assist_on`。**
> 下面方案写"CTRL 在**辅助开**时改读倒飞 toggle"，但工程里"辅助开"有两种后果：
> 「骑板」与「阿利宙斯 + 巡航形态」虽然辅助**也开着**，却**走普通飞行读取**
> （`assist_uses_translation()` 为假，`player_controller.gd:230`）⇒ 那两支里
> **根本没有底速可取反**（底速是平移模式独有的）。
> 用 `assist_on` 当门，结果是巡航形态里按 CTRL「提示弹了、飞行方式不变」——
> 本工程最忌讳的**空转**。更糟：巡航形态下 `_read_flight_input()` 真的读 `hover`
> （`player_controller.gd:556-557` → `fm.hovering`）⇒ 会**同时**触发悬停与倒飞。
> ⇒ 最终门 = `translate_mode`（`_tick_reverse_toggle()` 第一句
> `if not translate_mode: translate_reverse = false; return`）。
> 于是「辅助关着的时候 CTRL 保持今天的悬停语义」这条**自然成立**，一行特判都不用写。
>
> **修正 2 · ★★★ 正文与判据都没预见到：无锁定目标时，底速一反向，机头会连续自旋。**
> 平移模式的机头朝向分两支（`flight_body.gd:3026` / `:3033`）：**有目标** ⇒ 钉着目标；
> **无目标** ⇒ 追**速度矢量**（改前 `:2990`，改后 `:3034` 读 `vref`）。
> 底速反过来之后**真实速度也反过来** ⇒「机头追速度」每帧都在追一个
> 与自己差 **180°** 的方向 ⇒ 不是抖，是**转个不停**。
> 实测（负对照 `nc_no_vref`：1v1、无锁定、倒飞、120 帧）：
> 机头累计偏转 **177.65°**、`forward · 初始 = −0.9992`。
> **正解** = 水平朝向改追**等效正向速度** `vref = fwd * auto_speed + corr`
> （把底速那一份换回正向、平移修正原样保留）——
> ① 无输入时它就是机头自己的方向 ⇒ **不动点**（实测 120 帧 **0.00°**）；
> ② 按 A/D 时转向增益与正向**完全一致**（修正 / 底速 的比值没变，
> 不会出现"按左反而右转"的反向操舵）。
> ⚠️ 正向时 `vref := fm.velocity` 就是它自己 ⇒ 那一段**逐位等于改动前**（§②"逐位"四条守着）。
>
> **修正 3 · ★★ 正文方案自相矛盾：「只翻速度方向（机头仍朝敌）」与「视觉：把模型翻 180°」不能同时成立。**
> 模型的朝向**就是**机头朝向（`model_root` 挂在 `global_transform` 底下）。
> 真去翻模型 180°，玩家看到的是"背对敌机"，而锁定圈 / 弹道 / 军刀吸附
> **仍然按 `forward()` 朝敌算** ⇒ 一眼可见的**"视觉与判定不一致"**（本工程头号禁忌）。
> 想消掉它只有两条路：连 `forward()` 一起翻（⇒ 锁定、弹道、炮口与喷口锚点、
> `model_yaw_deg` 修正全部跟着动，成本与风险都远超这一件），或者**都不翻**。
> ⇒ **最终取"都不翻"**：「倒着飞」= **速度层语义**（机头仍咬着目标、机体沿机尾方向后撤），
> `global_transform` **一个字节不改**。这也正是 ①(b) 的本义。
> 代价面（同时是卖点）：锁定 / 弹道 / 军刀吸附 / 炮口与喷口锚点 / `model_yaw_deg` 修正
> **全部逐位不变** ⇒ 倒飞时**照样能开火命中**，这才是"倒着飞"在对战里有技术意义的地方。
> ⚠️ 若老板要的是"模型真转身"，那是另一件独立需求（= ①(a)），**不在本轮**。
>
> **修正 4 · W/S 语义量化（"互换"只是表象：实际是 W 变减速、S 变加速，且**幅度差 6.7 倍**）。**
> 底速反向之后 `translate_dir` 一个字没改，W/S 落在**修正量**上：
> `corr = translate_offset_vec(translate_dir, translate_fwd, top_speed × TRANSLATE_OFFSET)`
> （`TRANSLATE_OFFSET = 0.65` @ `flight_body.gd:348`、`TRANSLATE_FWD_SCALE = 0.15` @ `:361`）。
> ⚠️ **修正量锚在巡航极速上**（`1512 × 0.65 = 982.8`），**底速**才随加力变 ⇒ 百分比随底速变：
>
> | 键 | 修正方向 | 大小 | ÷ 底速（巡航 1512） | ÷ 底速（加力 2268） | 真机（\|v\| ≈ 2228） |
> |---|---|---|---|---|---|
> | **W**（降档 0.15） | 与机头同向 ⇒ **减速** | **147.4 m/s** | 9.75% | **6.5%** | 6.6% |
> | **S**（满权重） | 与机头反向 ⇒ **加速** | **982.8 m/s** | 65.0% | **43.3%** | 44.1% |
>
> ⇒ 「W 减速」很轻、「S 加速」很重 —— 与用户原话「w 就变成减速，s 就变成加速」不冲突，
> 但**不是**对称的一对开关，玩家的实际感受是"**S 才是我要的那个油门**"。
> 对比：正向时 W 是那个"轻油门"（`TRANSLATE_FWD_SCALE` 专门给它降过档，`:694-701` 有留档注释）——
> 倒飞正好把它翻成"轻刹车"，两者共用同一个常数，**没有再引入新旋钮**。
>
> **修正 5 · HUD 三个 x 常量（正文只写"给一条状态提示"，落地必须落数）。**
> `hud.gd` 原本把两个 x **硬编码在绘制行里**（状态字 `name_x + 82.0`、系统提示行 `name_x + 230.0`），
> 本轮提成三个 const（`hud.gd:3463-3465`）：
>
> | 常量 | 值 | 画什么 |
> |---|---|---|
> | `ASSIST_STATE_X` | **82.0** | `辅助驾驶 开启 / 关闭` 状态字（原硬编码，提出来） |
> | `ASSIST_REVERSE_X` | **155.0** | **倒着飞**（本轮新增，同一行、紧挨状态字右侧） |
> | `ASSIST_EVENT_X` | **230.0** | 系统提示行（原硬编码，提出来；换挡提示走这里） |
>
> ⚠️ 判据断**位置关系**（`82 < 155 < 230`），不断各自存在性 ——
> 「插分支挤走上一条调用体」是本工程反复吃过的亏。
> 负对照 `nc_hud_stack` 把 `ASSIST_REVERSE_X` 改成 260 ⇒ **只红那一条**。
> ⚠️ 倒飞格用 `WARN` 色 / 字号 **14**（状态字 15、提示行 14），占位比其他两格都短。
> ⚠️ 换挡提示走**左上角系统提示行**（`_system_say`）而**不是**中央那摞 toast ——
> 中央 toast 留给战斗事件（击坠 / 结算），这也是 §3.4「坠毁提醒不要和结算冲突」的同一条纪律。
>
> **修完之后的真机读数**（`tools/_r63_9_d2_shot.tscn`，1v1 对战、**真长按** `flight_assist` 0.45 s 开辅助）：
>
> | 图 | `assist_on` / `translate_mode` / `reverse` | `velocity · forward()` | 系统提示行 |
> |---|---|---|---|
> | `01_reverse_on` | true / true / **true** | **−2166.0** | 倒着飞 开启 |
> | `02_reverse_off` | true / true / false | **+2219.9** | 倒着飞 关闭 |
> | `03_no_assist` | false / false / false | **+1852.2** | 辅助驾驶 关闭 |
>
> ⇒ **`03` 是"键位没被抢走"的证明**：辅助关着按 CTRL 仍是悬停语义、`reverse` 保持 false。
> HUD 条带亮像素（倒飞格区间）：**01 = 718 / 02 = 443 / 03 = 477** ——
> 一开一关差 **+275**（≈ 两个字"倒着飞"加一格间隔的量级），负对照侧无此增量。
> 自旋读数（无锁定、倒飞 120 帧）：**机头 · 初始 = 1.0000（0.00°）**、`v·f = −2261.7`。
>
> **本轮的实际改动（4 个产品文件 + 1 处注册 + 1 个新套件）**
>
> | 文件 | 改前 → 改后（字节） | md5（改后） | 改动 |
> |---|---|---|---|
> | `scripts/flight/flight_body.gd` | 281627 → **284479** | `402e6e4fe7ab0fd35c6a1eaba48b1c43` | ⑨处：`translate_reverse` 字段 + `translate_base_dir()` 纯函数（`:2914`）+ `base_dir` 两用 + 闪避默认方向 + `corr` 提成变量 + 底速改成 `base_dir * auto_speed` + `vref` 块（`:3015-3017`）+ 机头水平参考改读 `vref`（`:3034`） |
> | `scripts/flight/player_controller.gd` | 133565 → **136486** | `cbea750e56dace87739ade797ae292a8` | ④处：`_think()` 哨兵段归零（`:203`）+ `_tick_reverse_toggle()` 新方法（`:1605`）+ `_think()` 里紧接 `translate_mode` 那行的调用 + `assist_state()["reverse"]`（`:2358`） |
> | `scripts/ui/hud.gd` | 324581 → **325891** | `66ba9b8a2bb863fac56571bea9d72e4e` | ④处：三个 x 常量（`:3463-3465`）+ 读 `reverse`（`:3490`）+ 倒飞格（`:3505`）+ 状态字 / 提示行改用常量 |
> | `scripts/autoload/input_setup.gd` | 55023 → **55419** | `e69f94f59b3704ec8a1a4484ac187494` | ①处：键位说明书加一行「Ctrl / R3 = 倒着飞（再按恢复）· W 减速 / S 加速」 |
> | `tests/test_runner.gd` | 23931 → **23997** | `332cea3a97ab2a6d5f42e1e440a960d9` | ①处：`SUITES` 注册 `suite_reverse_fly` |
> | `tests/suite_reverse_fly.gd` | 新建 **22250** | `fd7cdc9d5c82326c456cf2a8e060d00e` | 5 段 / **68 PASS / 0 FAIL** |
>
> **新判据**：`tests/suite_reverse_fly.gd`（①结构 20 + ②纯函数 15 + ③清零 8 + ④真机 12 + ⑤自旋守卫与 HUD 位置 13 = **68**）；
> **八个负对照全部精确咬住**（每次回滚后 `fb/pc/hud` 的 md5 与金标逐位一致）：
>
> | 变体 | 红 | 咬在哪 |
> |---|---|---|
> | `nc_pure_hard`（`translate_base_dir` 写死 `-fwd`） | **9** | ①逐位 ×4 + ②正向那两条 + ④基线 / 复原 |
> | `nc_pure_norm`（`else fwd.normalized()`） | **4** | 只红 ①逐位 ×4（归一化破坏了逐位） |
> | `nc_no_clear`（开关函数不归零） | **3** | 写入点数 ×2 + ③关辅助 |
> | `nc_no_guard`（哨兵段不归零） | **3** | 写入点数 ×2 + ③禁控 |
> | `nc_hover_in_tx`（把 `hover` 读进平移路） | **1** | **只** ①键位不冲突 |
> | `nc_no_vref`（机头追真实速度） | **1** | **只** ⑤ 最大偏转 **177.65°** |
> | `nc_hud_stack`（`ASSIST_REVERSE_X = 260`） | **1** | **只** ⑤ 位置关系（260 > 230） |
> | `nc_no_flip`（底速不取反） | **3** | ①`target = base_dir…`（咬在产品那条算式上）+ ④变号 + ⑤变号 |
>
> **邻近套件联跑（15 个，全部 0 FAIL / 四类报错 0 / 节数非零）**：
> `suite_ui_style 188` · `suite_assist_drive 164` · `suite_ground_guard 32` ·
> `suite_motion_feel 22` · `suite_fx_plume 237` · `suite_round14 125` · `suite_round15 183` ·
> `suite_round16 69` · `suite_round19 73` · `suite_input 325` · `suite_keybind 148` ·
> `suite_gamepad 142` · `suite_abilities 490` · `suite_fpv 692` · `suite_tutorial 382`。
> `test_runner` 全表注册核对：磁盘 79 个 `suite_*.gd` ↔ 注册 79 条，**两个方向差集都空**。
>
> **未决 P7（三条语义）至此全部拍定并落地**：
> ① 取 **(b) 只翻速度**（且**不翻机头**，见修正 3）｜
> ② 取 **(a) 油门互换**（幅度不对称，见修正 4）｜
> ③ 手柄 **R3 与 CTRL 同名同源**（都读 `hover`）⇒ 一起变成倒飞开关；
> 玩家在设置里改绑"悬停"，倒飞跟着走（键位只有 `InputSetup` 一处真源）。

**关键发现（好消息）** · **在辅助驾驶这条路上，CTRL 是空键。**
`_read_translate_input()`（`player_controller.gd:661-...`）**全文不读 `hover`**；
`hover` 只在 `_read_flight_input()`（`:556`）里被读。
而辅助驾驶下，除「骑板」与「阿利宙斯 + 巡航形态」之外**全部走平移模式**（`:629-633`、`:230`）。
⇒ 用户说的"辅助驾驶模式下按 CTRL"**不产生键位冲突**。冲突只存在于**辅助关闭**时（那里 CTRL = 悬停，`flight_model.gd:115/21` 明说"极猛刹车把速度压到 0 并顶住重力"）。

**证据（文件:行）**

| 位置 | 内容 |
|---|---|
| `scripts/autoload/input_setup.gd:33` | `"hover": [KEY_CTRL]` |
| `scripts/autoload/input_setup.gd:571` | `"hover": [JOY_BUTTON_RIGHT_STICK]`（手柄 R3） |
| `scripts/autoload/input_setup.gd:745` | 帮助表：`[[["kb","hover"]], "悬停（空中定住）", "R3"]` |
| `scripts/flight/flight_model.gd:115` / `:21` | `var hovering` + 注释「悬停模式（`hovering`，Ctrl）：极猛刹车把速度压到 0 并顶住重力」 |
| `scripts/flight/player_controller.gd:556-557` | `want_hover := ...("hover")` / `want_boost := ...("boost") and not want_hover`（**只有手动路读它**） |
| `scripts/flight/player_controller.gd:563` | `fm.hovering = want_hover` ← 手动路的唯一写入点 |
| `scripts/flight/player_controller.gd:197/205/729` | `fm.hovering = false` / `= debug_hover`（平移路自己管） |
| `scripts/flight/player_controller.gd:661-702` | `_read_translate_input()`：`mv = W(+1) / S(−1)`、`strafe = D / A`、`lift = Q / E`；写 `translate_dir` |
| `scripts/flight/player_controller.gd:694-701` | 注释：「**W（向前推杆）那一份单独留档**」+ `TRANSLATE_FWD_SCALE`（W 的加速速率已单独降过档 ⇒ 这一次又要动 W/S，**必须与它对齐**） |
| `scripts/flight/player_controller.gd:646` | 平移模式注释：「机体**永远以加力极速沿机头自动飞**，WASD/QE 只是在底速上**叠加**平移修正」 ← **"倒飞"要动的正是这条"沿机头"** |
| `scripts/flight/flight_body.gd:162/776/2578/3314` | `translate_mode` 的执行落点（`_apply_translate` 一段） |
| `scripts/flight/flight_body.gd:3201` | `return translate_mode and translate_dash` |
| （轮 33 既有机制） | 视觉专用旋转枢轴（冲刺转身用 `spin_pivot`，`_rebuild_visual()` 里要 `free`）—— 可复用于"模型翻 180°" |

**三条必须先定的语义（这就是"设计题"的由来）**

| # | 问题 | 选项 | 影响 |
|---|---|---|---|
| ① | "倒着飞"是**机体真的转身 180°**（模型朝后、镜头跟着转）还是**只翻速度方向**（机头仍朝敌、飞向反方向）？ | (a) 转身 (b) 只翻速度 | (a) 会让锁定/弹道/机头判据全部跟着翻；(b) 弹道与锁定**逐位不变**（因为机头没动） |
| ② | "W 减速 / S 加速"是**油门互换**还是**位移方向互换**？ | (a) 互换油门 (b) 互换位移方向 | (a) 只改 `mv` 的符号来源；(b) 会连带改 `translate_dir` ⇒ 八向动画、左右冲刺转身判据（`flight_body.gd:3201`）全部跟着变 |
| ③ | 手柄 R3（现在也是 `hover`）怎么办？ | (a) 一起变成倒飞开关 (b) 另给一个键 | 手柄上 R3 是"点按切换性质"的动作（`input_setup.gd:571` 注释自己说了） |

**建议方案（若拍板取 ①(b) + ②(a)）**

- 新增 `var reverse_fly := false`，**唯一写入点**在 `_think()`（与 `translate_mode` 同一层，`:230` 附近）；
- CTRL 在**辅助开**时改读 `reverse_fly` 的 toggle（`just_pressed`），**辅助关**时保持今天的悬停语义；
- `reverse_fly` 为真时：`translate_dir` 与自动巡航的底速方向取反；W/S 的油门语义互换；HUD 给一条状态提示（工程禁止静默改状态）；
- **辅助关闭 / 脱离平移模式 ⇒ 强制 `reverse_fly = false`**（否则语义残留）；
- 视觉：沿用既有的 visual-only 旋转机制把模型翻 180°（**不动 `fm` 朝向**）⇒ 弹道/锁定不受影响。

**可证伪判据 + 负对照**

1. **纯函数**：`reverse_fly_axis(mv, reverse)`；`reverse == false` 时必须与今天的取值**逐位相同**。
   **负对照**：把 `reverse` 写死 true ⇒ 第一条红。
2. **语义残留**：`assist_on` 由 true→false ⇒ `reverse_fly` 必须归 `false`。
   **负对照**：不归零 ⇒ 红（症状：关掉辅助后 CTRL 忽然又变成悬停、且机体保持倒飞）。
3. **键位不冲突**（结构）：`_read_translate_input()` 里仍然**不出现 `hover`**；`_read_flight_input()` 里仍然只读 `hover`。
   **负对照**：把 `hover` 加进平移路 ⇒ 红（症状：辅助模式下 CTRL 同时触发悬停与倒飞）。
4. **真机**：按 CTRL ⇒ `fm.velocity · forward()` 变号，且 HUD 出现状态提示；再按 ⇒ 复原。
5. **顺序关系（防"插分支挤走上一条调用体"）**：`hud` 上"倒飞"提示与"辅助驾驶 开启/关闭"提示的**位置关系**要断，而不是各自断存在性。

**未决** · ~~P7（三条语义）~~ —— **轮 63-9 已拍定并落地**（取 ①(b) 只翻速度 · ②(a) 互换油门 · ③ R3 与 CTRL 同名同源），见本节顶部「施工期实测修正」。

---

### 3.3 · D3 · 光束步枪辅助瞄准模式（辅助驾驶下自动开启）+ 放大镜 + 预测圈 + 准星吸附

**用户原话** · 「给光束步枪加入辅助瞄准模式，辅助驾驶模式下自动开启，在屏幕的空白处有放大镜效果（在对方机体 0.4 km 处设置相机，来显示对方）增加射击预测提示圈和射击时候的准星吸附，准星靠近提示圈会有吸附和射击提醒。」

**结论强度** · **设计题 + 一处需求变更**（这是本轮最大的一件）

**两处硬事实（先说，因为一条是坑、一条是成本）**

1. **辅助瞄准今天是一段死代码。**
   `flight_body.gd:3605` 写的是 `aim_assist_weight(Ballistics.angle_off_boresight(to_bore, to_lead))`，
   而 `Ballistics.angle_off_boresight()`（`ballistics.gd:76-79`）结尾是 **`return rad_to_deg(...)`（返度）**，
   `aim_assist_weight(angle_rad)`（`flight_body.gd:3560`）里面按**弧度**比（`AIM_ASSIST_SNAP_DEG 2.5° → 0.0436 rad`、`AIM_ASSIST_CONE_DEG 7.0° → 0.1222 rad`）。
   ⇒ 传进来的"度"（比如 2.0）**恒大于锥角 0.1222** ⇒ **`w` 恒为 0.0**，永久走"完全按机头"。
2. **"放大镜"没有底座。**
   `scenes/main.tscn` **只有一个 `Main`（Node3D）**；全工程**只有一台 `Camera3D`**（`chase_camera.gd:2 extends Camera3D`，`main.gd` 实例化）；**没有任何 `SubViewport`**（唯一提到它的是 `settings.gd:107` 的一句注释）。

**⚠️ 与既有需求冲突（必须拍板）**

`README.md` §16.1 第 4 条（用户当时给的原话）：

> 4. （补充）「光束步枪和火神炮的**射击方向跟随鼠标操控的准星**（鼠标不影响视角）」

而"辅助瞄准"的定义就是**让弹道偏离准星**去指向提前量点。
⇒ 一轮前用户已经就这件事拍过 **「丙：不动弹道」**（理由正是它违反上面这条）。
**本轮的用户要求实际上推翻了这个决定** ⇒ 要么改 `README.md` 的这条需求，要么把"吸附"限制在**不改弹道**的范围内（见方案 A）。

**放大镜的真实成本（要摆在台面上）**

- 实现方式只有一条标准路：新建 `SubViewport` + 一台 `Camera3D`，并把 `sub_viewport.world_3d = get_viewport().world_3d`（**渲染同一份世界**）；
- ⇒ **每帧一次额外的全场景渲染**。本项目有性能分解的先例读数（`DESIGN-2026-10-03` 附 C3）：**关 HUD 省 8.34 ms、停 13 台 AI 物理 11.25 ms、隐藏 13 台 AI 模型 12.21 ms、隐藏 5 块踏板 4.03 ms**，而 MSAA 4×→2× 只省 0.83 ms。⇒ **多一次全场景渲染是同一量级的开销，必须限量。**
- 摊薄手段（建议）：尺寸 320×180；`render_target_update_mode = ONCE`（每 N 帧推一次，N = 4~6）；`Camera3D.cull_mask` 只留必要层。

**证据（文件:行）**

| 位置 | 内容 |
|---|---|
| `scripts/flight/flight_body.gd:3550-3551` | `const AIM_ASSIST_SNAP_DEG := 2.5` / `const AIM_ASSIST_CONE_DEG := 7.0` |
| `scripts/flight/flight_body.gd:3560-3568` | `static func aim_assist_weight(angle_rad)`：`<= snap ⇒ 1.0`；`>= cone ⇒ 0.0`；中间线性 |
| `scripts/flight/flight_body.gd:3605` | `var w := aim_assist_weight(Ballistics.angle_off_boresight(to_bore, to_lead))` ← **单位错** |
| `scripts/combat/ballistics.gd:76-79` | `static func angle_off_boresight(...) -> float: ... return rad_to_deg(...)` ← **返度** |
| `scripts/combat/projectile.gd:82-85` | 已把这个坑写进注释 |
| `scripts/combat/lock_on_system.gd:925` | `gun_lead_point()`（可复用的提前量点） |
| `scripts/combat/lock_on_system.gd:938` | `gun_lead_point_beam()`（光束那一路） |
| `scripts/combat/lock_on_system.gd:945/952` | `angle_to_target()` / `range_to_target()` |
| `scripts/combat/lock_on_system.gd:315` | `lock_ratio()` |
| `scripts/combat/lock_on_system.gd:914` | `rel_v := target.fm.velocity - unit.fm.velocity`（提前量的真源） |
| `scripts/ui/hud.gd:1368` | `_draw_reticle()` |
| `scripts/ui/hud.gd:1425` | `_draw_aim_cursor()` |
| `scripts/ui/hud.gd:1611` | `_draw_target()`（`LOCK ON` 与锁定环 `:1647` / `:1662`） |
| `scripts/ui/hud.gd:1706-1713` | **提前量标记圈已在**（`gun_lead_point` 6.0 px / `gun_lead_point_beam` 10.0 px）← 用户要的"预测提示圈"**已经有了**，要加的是"吸附 + 提醒" |
| `scripts/ui/hud.gd:1732` | `_draw_lock_group()` |
| `scripts/flight/flight_body.gd:3570-3584` | `aim_point(...)`：`lead=false` 时 `boresight = global_position + aim_forward() * dist`，再 `origin + to_bore.slerp(to_lead, w)` ← **吸附的现成落点** |
| `scenes/main.tscn` | 只有一个 `Main` Node3D（**无 SubViewport**） |
| `scripts/autoload/settings.gd:107` | 「……要修得把 3D 世界渲进 `SubViewport` 再做后处理」 |

**方案（建议拆成两件，别捆在一起做）**

- **D3a · 辅助瞄准 + 提示圈 + 提醒（接线级，风险低）**
  1. 修单位：调用点 `deg_to_rad(Ballistics.angle_off_boresight(...))`；
  2. **开门条件**：只在辅助驾驶开启且武器是光束步枪时生效（用户要求"辅助驾驶模式下自动开启"）；
  3. 提示圈：已有（`hud.gd:1706`），补"准星进入锥内"的**提醒**（`push_notice` 或 HUD 上的一行）；
  4. **吸附范围建议只做 ≤ `AIM_ASSIST_SNAP_DEG (2.5°)`** —— 这样"弹道基本仍跟随准星"，与 README 需求 4 的冲突被压到最小；若要更宽的锥（7°），就必须改 README。（⚠️ 实测的最大偏转是 **2.7222°**、不是 2.5°，**不过结论不变**：仍取「不改 README 需求 4」，只是口径要按 2.7223° 说。见同上修正 2）
- **D3b · 放大镜（新系统，独立轮）**
  1. `SubViewport` + `Camera3D`，放在目标机 0.4 km 处、朝向目标；
  2. 限量（320×180 / `ONCE` / 每 4~6 帧一推）；
  3. HUD 侧画一张 `SubViewportTexture`（"屏幕空白处"= 建议固定右上或左下角，避开准星与锁定环）；
  4. 性能判据（必须有）：开/关放大镜的**同轮配对**帧时差 ≤ 1.0 ms（用工程既有的交错多轮 + 取中位 + 看 min/max 的方法，**顺序分解不可用**）。

> ### ★★ 施工期实测修正（轮 63-9 · D3a 落地时发现：**正文里有一个目标值写错了，还有一个口径要按实测改**；另外"两处门"被正文混成了一句）
>
> **修正 1 · ★★ 判据 1 里的 `aim_assist_weight(deg_to_rad(3.5)) ≈ 0.5` 是错的 —— 中点不在 3.5°。**
> 权重在 `[SNAP, CONE] = [2.5, 7.0]` 上线性下降 ⇒ `w = 0.5` 落在**中点 `(2.5 + 7) / 2 = 4.75°`**；
> 3.5° 处的真值是 **0.7778**（`1 − (3.5 − 2.5) / 4.5`）。
> `tests/suite_aim_assist.gd` ① 段已按 **4.75° ⇒ 0.5** 钉住（`suite_ballistics` 里
> 那条 `4.0° ⇒ 0.667` 与它是同一族的两个点，互不矛盾），并把 3.5 这个数**留给"最大偏转"用**。
>
> **修正 2 · ★★★ 「吸附只做 ≤ 2.5°」这个口径实际是 ≤ 2.7223°，而且最大值不在锥边缘上。**
> 偏转量 = `偏角 × 权重`，而权重随偏角线性下降 ⇒ 它是 `[SNAP, CONE]` 上的**凹二次式**：
> `d/dθ [θ · (1 − (θ − 2.5) / 4.5)] = 0 ⇒ θ = (2.5 + 7) / 2 = 3.5°`，峰值
> `3.5 × (1 − 1/4.5) = **2.7222°**`。
> **两条独立的实测量法**（① 段都写了断言）：
> ① 2.5° → 7.0° 每 **0.001°** 扫 4500 点取最大 ⇒ **2.7222°**（出现在 3.500° 处）；
> ② 4001 点均匀抽样求上确界 ⇒ 同一个数（互证）。
> ⇒ `README.md` §16.1 需求 4（"光束步枪和火神炮的射击方向跟随准星"）被偏离的**真实上界是 2.7223°**，
> 不是 2.5°（差 9 个百分点）。**结论不变（P8 仍取"不改这条需求"）**，但口径必须按 2.7223° 说 ——
> 这条已经写进 `README.md` §16.1 的追加段，`suite_aim_assist` ①② 两段各有一条牙咬它。
>
> **修正 3 · ★★ 门必须拆成"武器门 × 模式门"两处，正文把它们混成了一句话。**
> 正文 D3a 第 2 条写的是"只在辅助驾驶开启**且**武器是光束步枪时生效"，读起来是一个条件，
> 落地时是**两个独立条件**、而且**落在两个不同的文件**：
>
> | 门 | 落点 | 判据 |
> |---|---|---|
> | **武器门** `assist := false` | `aim_point()` 新增**第 6 个形参**；只有 `fire_beam()` 传 `true`，`_fire_vulcan_round()` **一位都不传** | ② 段量 `_argc()`：火神炮 **4** 个实参、光束 **6** 个 |
> | **模式门** `aim_assist_enabled()` | `FlightBody` 上是**虚函数恒 false**；`PlayerController` 覆写 `return assist_on` | ② 段量两处定义 + `fb` 里不许出现 `assist_on`；③ 段量真机行为 |
>
> ⚠️ **模式门必须走覆写、不能在 `FlightBody.aim_point()` 里直接读 `assist_on`**：
> `assist_on` 声明在子类 `PlayerController` 上，基类里引用它是**解析期**错误 ⇒
> 整套件编译不过、末尾的节被静默吃掉（本工程反复踩过的假绿）。
> 这与 `_think()` 用虚函数是同一条路。
> ⚠️ 武器门那条判据**不能**写成"源码里不出现 `aim_assist` 字样" —— 那抓不住
> "多补两个 `false, true`"（负对照 `nc_vulcan_assist` 第一版就是这么漏过去的），
> 必须**数实参个数**。
>
> **修正 4 · ⚠️ `w == 0` 时必须原样返回 `boresight`，不能让它走 `slerp`。**
> 要的语义是"辅助关 / 锥外 ⇒ 弹道**逐位**回到今天"，而 `slerp(to_lead, 0.0)` 在浮点上
> 不保证逐位等于 `to_bore`（实现里还有"夹角 < eps 就直接返回终点"的分支）。
> ⇒ 写成 `if w <= 0.0: return boresight`，③ 段用 `t.eq()` 断**逐位相等**（3 条）。
>
> **修正 5 · 提示圈量的夹角是"准星 vs 提示圈"，与弹道那侧的"炮口视差角"差 0.19°。**
> `aim_point()` 量的 `to_bore` / `to_lead` 都从**炮口**起算（本项目炮口离机体中心约 10 m，
> `MUZZLE_INWARD = 0.45`），而玩家眼里看到的是"准星方向 → 提示圈"。
> 3 km 处两者的差 ≈ `atan(10 / 3000) = 0.19°`，只影响锥边缘那一线。
> ⇒ HUD 侧按**玩家视角**量（这正是用户说的"准星靠近提示圈"），
> 阈值仍读同一个常量 `FlightBody.AIM_ASSIST_SNAP_DEG` ⇒ "只有一处真源"那条判据成立。
>
> **修正 6 · 落地文件与真源（改动前 → 后）**
>
> | 文件 | 字节 | md5（后） | 内容 |
> |---|---|---|---|
> | `scripts/flight/flight_body.gd` | 284479 → **287243** | `0542ca527d4a1c587fded38345597ff3` | 新增虚函数 `aim_assist_enabled()`；`aim_point()` 加第 6 形参 `assist`；调用点补 `deg_to_rad()`；`w == 0` 原样返回；`fire_beam()` 传 `true` |
> | `scripts/flight/player_controller.gd` | 136486 → **137107** | `1e494106869da33fe06d2fa1c4c5ed52` | 覆写 `aim_assist_enabled() -> return assist_on` |
> | `scripts/ui/hud.gd` | 325891 → **327165** | `50776b5b5d856fb402ff84da3e3dd3d1` | `_draw_target()` 里加"准星进锥"的吸附环（`DANGER`）+ 一行 `辅助瞄准 吸附` |
> | `tests/test_runner.gd` | 24140 → **24296** | `60b6a745239f768ca51032f95d248220` | 注册 `AimAssist` |
> | `tests/suite_aim_assist.gd` | 新建 → **19791** | `075889186d19d4308912e44357c9c8ba` | 4 段 / **68 PASS / 0 FAIL** |
> | `README.md` | 307480 → **309586** | `e24c1704d359f1f3ba7ccf1ffe05d48e` | §16.1 追加"辅助瞄准接通"一段（含 2.7223° 的量化与"放大镜单独立轮"） |
>
> **新判据**：`tests/suite_aim_assist.gd`（①单位与锥形 **15** + ②接线 **24** + ③真机对象 **14** + ④提示圈同源 **15** = **68**）。
> 真机读数（③ 段打印）：偏 **3.0000°** ⇒ 权重 **0.8889** ⇒ 拉到离准星 **2.6667°**（= 3 × 0.8889）。
>
> **五个负对照（每个只许红它该红的；每次回滚后五份文件与金标逐位一致）**：
>
> | 变体 | 红 | 咬在哪 |
> |---|---|---|
> | `nc_deg_inside`（`aim_assist_weight()` 内部按度比） | **15** | ① 12（中点 / 锥边 / 传度归零 / 最大偏转变 7.0°…）+ ③ 3（拉走量变 3.0°、锥外也拉） |
> | `nc_no_rad`（调用点去掉 `deg_to_rad()`） | **6** | ② 2（结构）+ ③ 4（3° 时一点不拉 ⇒ dot 掉到 cos3° = 0.99863） |
> | `nc_no_gate`（去掉模式门、只留武器门） | **4** | ② 3 + ③ 1（辅助关时也拉） |
> | `nc_vulcan_assist`（火神炮那一处也传两位） | **1** | **只** ② 的实参个数（4 → 6） |
> | `nc_hud_literal`（HUD 把常量换成字面量 `2.5`） | **2** | **只** ④（常量引用 1 → 0 + 取不到那一行） |
>
> **两条施工教训（都是夹具/工具的问题，不是产品的）**
>
> 1. **`_body()` 的终止符必须一次找全 `func` / `static func` / `const` / `var` / `class`。**
>    只找 `"\nfunc "` 的版本（`suite_reverse_fly` 那一版）会把 `_fire_vulcan_round()` 的函数体
>    一路吞到 `aim_point()` 的头上去 —— 中间那些 `static func` / `const` **都不匹配** `"\nfunc "`。
>    症状是"火神炮里不许出现 `aim_assist`"因为吞进了 `aim_assist_weight` 而**假红**。
> 2. **负对照脚本的 `assert count == 1` 必须先确认锚点真的唯一，而且驱动必须检查返回值。**
>    `nc_hud_literal` 第一版用了裸的 `FlightBody.AIM_ASSIST_SNAP_DEG` 当锚点，而那个串
>    在文件里出现 **2** 次（代码 1 + 我新写的那条注释 1）⇒ `apply` 抛异常、
>    **负对照根本没被应用**，套件照样 66 PASS / 0 FAIL —— 读起来像"套件没牙齿"，
>    差点把一条好的判据改坏。修法：锚点带 `if snap_ang` 前缀（只匹配代码那一行），
>    并在驱动里让子命令非 0 退出即中止。
>
> **未决 P8 / P9 至此拍定并落地**：
> **P8** 取"**吸附只做 ≤ `AIM_ASSIST_SNAP_DEG`**、不改 `README.md` 需求 4" ——
> 实测上界 **2.7223°**（不是 2.5°，见修正 2），并在 README §16.1 里把这两个数写清楚。
> **P9** 取"**放大镜单独立轮**"（本轮**不做**）：它要给全场景再加一次 `SubViewport` 渲染
>（本工程的性能先例读数：关 HUD 省 **8.34 ms**、隐藏 13 台 AI 模型 12.21 ms），
> 按"相机类改动全工程风险最高 ⇒ 独立轮 + 性能判据"的规矩单独立轮；
> 同时设计文档 §3.3 里给它的**判据 5 / 判据 6**（放大镜存在性与机位、性能 ≤ 1.0 ms）
> **随之顺延到 D3b 那一轮**，本轮 `suite_aim_assist` 只实现判据 1 – 4。

**可证伪判据 + 负对照**

1. **单位守卫（这条断言就是"单位不许再错"的牙齿）**：
   - `aim_assist_weight(deg_to_rad(0.0)) == 1.0`
   - `aim_assist_weight(deg_to_rad(3.5)) ≈ 0.5`（⚠️ 3.5° 处实际是 **0.7778**；`w = 0.5` 落在中点 **4.75°**。见本节「施工期实测修正」修正 1）
   - `aim_assist_weight(deg_to_rad(7.0)) == 0.0`
   - **`aim_assist_weight(3.5) == 0.0`**（传度必须归零）← **负对照**
2. **接线**：`aim_point(origin, target, false, speed)` 在"目标偏离机头 3°"时必须返回**不是** `boresight` 的点；
   **负对照**：偏 20° ⇒ 必须**等于** `boresight`（锥外不动）。
3. **只在辅助开时生效**：辅助关 ⇒ `w` 必须为 0（弹道逐位回到今天）。
   **负对照**：把开门条件去掉 ⇒ 红。
4. **提示圈与吸附同源**：吸附用的角度阈值与 `hud` 画圈的判定半径**必须是同一个常量**（只有一处真源）。
   **负对照**：两处各写一个数 ⇒ 必须有 gate 报"两处口径不一致"。
5. **放大镜存在性 + 机位**：`SubViewport` 存在且 `world_3d` 与主视口**同一个对象**；其 `Camera3D` 与目标的距离 ∈ [0.39, 0.41] km，朝向与"相机→目标"方向夹角 ≤ 5°。
   **负对照**：把 `world_3d` 留空（默认空世界）⇒ 放大镜里必然是黑屏 ⇒ 必须有断言抓到（这是最容易静默失败的一处）。
6. **性能**：开/关放大镜的帧时差 ≤ 1.0 ms（同轮配对、取中位、看 min/max）。

**未决** · ~~P8 / P9~~ —— **轮 63-9 已拍定并落地**（P8：吸附只做 ≤ `AIM_ASSIST_SNAP_DEG`，**不改 README**，实测上界 2.7223°；P9：**放大镜单独立轮**，判据 5 / 6 随之顺延），见本节顶部「施工期实测修正」。

---

### 3.4 · D4 · 增加敌方机体坠毁提醒（不要和游戏结算冲突）

**用户原话** · 「增加敌方机体坠毁提醒（不要和游戏结算冲突）。」

**结论强度** · **已定位**（通道现成、冲突是结构性的）

**一句话根因** · 通知通道 `push_notice` 现成，但**目前与"击毁"零连接**；而"冲突"的来源是——`destroy()` 里 `Game.notify_destroyed()`（会判胜、会 `set_phase(WIN)`）**先跑**，`destroyed.emit()`（`main._on_enemy_destroyed()` → `_finish_round()`）**后跑**，两者在**同一帧**内 ⇒ 最后一架敌机被击毁的那一帧，"提示"与"结算页"是同时发生的。

**证据（文件:行）**

| 位置 | 内容 |
|---|---|
| `scripts/flight/flight_body.gd:5320-5321` | `Game.notify_destroyed(self, killer)` **然后** `destroyed.emit(killer)` ← 顺序写死 |
| `scripts/flight/flight_body.gd:5325` | `Game.log_event("敌机被击坠")` ← **只在结算页被读** |
| `scripts/autoload/game.gd:504-524` | `notify_destroyed()`：记账 + `unit_destroyed.emit` + **`_evaluate_end()`** |
| `scripts/autoload/game.gd:527-533` | `_evaluate_end()`：`if phase != Phase.FIGHT: return` ⇒ 玩家没了 ⇒ LOSE |
| `scripts/autoload/game.gd:553-556` | ★ 历史 bug 的注释：「清掉两台古斯塔夫之后结算直接跳出来……判胜抢在刷怪前面跑」⇒ **同一类坑**，已有前科 |
| `scripts/autoload/game.gd:557-560` | 挑战模式的补丁：`challenge_wave + 1 < wave_count` 时不判胜 |
| `scripts/main.gd:3029-3030` | `func _on_enemy_destroyed(_killer) -> void: _finish_round()` |
| `scripts/main.gd:3084-3094` | `_finish_round()`：`if phase == RESULT: return` → `phase = RESULT` + `hud.capture_result(WIN)` |
| `scripts/main.gd:2393` | `_on_challenge_enemy_destroyed()`（剧情/挑战那一侧的击毁回调） |
| `scripts/main.gd:1720` / `:1893` | `enemy.destroyed.connect(_on_enemy_destroyed)` / `ai.destroyed.connect(_on_enemy_destroyed)`（对战 / 小队 / 联机） |
| `scripts/ui/hud.gd:1100-1103` | `func push_notice(text, seconds := 1.4)`：`_notices.append`，**上限 5 条**（`pop_front`） |
| `scripts/ui/hud.gd:1093` | `if p != null and not p.notice.is_connected(push_notice): p.notice.connect(push_notice)` ← **只接了玩家的 `notice` 信号** |
| `scripts/ui/hud.gd:3733` | `_draw_notices()` |
| `scripts/ui/hud.gd:5550-5562` | 结算页读 `Game.phase` 画 MISSION COMPLETE / FAILED |
| 全工程 | **没有任何一处 `notice.emit` 与"敌机被击毁"相连**（`notice.emit` 全部来自 `player_controller.gd`） |
| `scripts/flight/player_controller.gd:41` | `signal notice(text, seconds)` |

**方案**

- **落点**：在 `main` 侧新增 `_notify_enemy_down(unit: FlightBody)`，由 `_on_enemy_destroyed()`（`:3029`，对战/小队/联机）与 `_on_challenge_enemy_destroyed()`（`:2393`，剧情/挑战）**共用** ⇒ 一处真源覆盖所有模式。
- **与结算的门（这就是用户说的"不要冲突"）**：只在 **`Game.phase == Game.Phase.FIGHT`** 时提示；
  并且在"这一击把场上清空"的情况下**延后**（例如用一个极短的计时器在下一次 `process` 里再判一次 `phase`），或者干脆**不在这一帧提示**。
- **文案**：用 `unit.display_name`（与 B4 同源：谁被击落要说对名字）。
- **风格**：`push_notice` 是"中央那摞 toast，给战斗信息用"（`player_controller.gd:1643-1645` 的注释明确把"辅助飞行状态"划给了 `_system_say()`）⇒ 击毁提醒属于**战斗信息** ⇒ 用 `push_notice` 是对的。

**可证伪判据 + 负对照**

1. **非终结性击毁**（场上还有敌对单位）：`hud._notices` 里出现一条包含被击毁机体名的提示，且此刻 `Game.phase == FIGHT`。
   **负对照**：把提示那一行注释掉 ⇒ 红。
2. **终结性击毁**（场上清空 ⇒ `phase` 会变 WIN/RESULT）：**不得**出现"结算页上还挂着一条 toast"，或至少 `_notices` 的内容在 `phase != FIGHT` 之后**不再增长**。
   **负对照**：去掉 `Game.phase == FIGHT` 那道门 ⇒ 必须红。
3. **上限**：连续击毁 6 架 ⇒ `_notices` 长度不超过 5（既有行为，`hud.gd:1102-1103`）。
4. **模式覆盖**：对战 / 小队 / 剧情 / 挑战四条路各有一条断言（因为落点被 `_on_enemy_destroyed` 与 `_on_challenge_enemy_destroyed` **两条**调用）。
   **负对照**：只接一条 ⇒ 另一条必须红。
5. **⚠️ 与剧情"死拍子"的交叉**：m02 是 `win_on_clear` + **单波** ⇒ 末机销毁那一帧就 `set_phase(WIN)`，之后 `phase != FIGHT ⇒ return`；所以**m02 的坠毁提醒必然落在"终结性"那一条**。若实现成"终结性不提示"，m02 就不会有新提醒（本条要拍板）。

**未决** · P12（终结性击毁要不要提示 —— 建议要，但落在结算页/"已清空"那一行，或延后到结算之后）

---

### 3.5 · D5 · 导弹拖尾白烟：透明度 −20%、密度 −20%、体积不变

**用户原话** · 「导弹拖尾白烟太挡视野了，透明度降低和密度降低 20%：体积不变。」

**结论强度** · **已定量证实**（含一条会直接撞红的算术）

> ### ★★ 施工期实测修正（轮 63-9 · D5 落地时发现：**方案 A 成立，但下面漏列了一条必改的断言**）
>
> **修正 1 · 下面「撞红清单」漏了一条：方案 A 必须同步改 `suite_missile_smoke.gd` 的 lifetime 断言。**
> 该文件第 241–245 行的 `t.near(p.lifetime, 0.16, 0.001, …)` 是**硬断言**，
> 文档只列了 `:650-652` 的间距不变量与 `:264` 的色带起点 alpha，**没列到它**。
> 方案 A 把 lifetime 改成 0.128 ⇒ **不改它必红**（已同步改为 `0.128 / 0.0005`，
> 断言文案改成「= 轮 39 的 0.16 s × 0.8」）。**这是本轮唯一一处「方案外新增必改点」。**
>
> **修正 2 · 真机 A/B 读数（线性空间、逐像素比值）** —— `_deliver/shots_r63_9_d5/`
> 机位：纯黑背景 + 固定相机（`tools/_r63_9_d5_shot.gd`，`CAM_Z 800` / `fov 15`），
> 14 点 × 120 m 直烟带，2560×1600 真机。
>
> | 量 | 0.55（改前） | 0.44（改后） | 比值 | 目标 | 偏差 |
> |---|---|---|---|---|---|
> | 主体线性亮度（逐像素线性比值中位） | — | — | **0.79679** | 0.80000 | **−0.401%** |
> | 覆盖像素（阈值 8） | 133750 | 133608 | **0.99894** | 1.00000 | −0.106% |
> | 覆盖行数 | 59 | 59 | **1.000** | 1.000 | 0 |
>
> ⇒ 亮度降 20.3%（= 1 − 0.7968）、**覆盖面积与行数逐位不变** ⇒ 字面需求「透明度 −20%、体积不变」在真机像素上成立。
> 逐像素比值分布 p10~p90 = 0.78547~0.80691，±0.4% 的散布 = **8 bit 量化**（不是引擎非线性）。
>
> **修正 3 · sRGB 直接比会得到假数 0.897。**
> 引擎在**线性空间**混合、再编码成 sRGB 存 PNG ⇒ 直接对 sRGB 字节比亮度，
> 目标 0.80 会被读成 **0.897**（偏差 +12%）。
> **必须先 `srgb_to_lin()` 解码回线性再比**。另一条错法（先对通道加权平均、再解码）得 0.7957，
> 因解码函数是凸的 ⇒ 也有 0.5% 偏差。⇒ **口径：解码 → 逐像素相除 → 取中位。**
>
> **修正 4 · 「挡视野」的像素证据只能拍烟带层。**
> 粒子层是 `GPUParticles3D`（**无 seed**）⇒ 随机场，做不出可复现的像素 A/B。
> 烟带是**确定性几何** ⇒ 上面这张表只对 `MissileRibbon` 成立。
> 粒子层的 −20% 由**读数**钉住（`amount 64` / `lifetime 0.128` / 间距 8.124 m 不变），不由像素钉住。
>
> **修正 5 · 出图时会看到「除主带外还有一条全宽细亮线」，它也是烟带画的。**
> 诊断跑（`_r63_9_d5_shot.gd` 第二参 `noribbon`，隐藏烟带节点）⇒ **画面全黑**
> （非黑像素 = 0）⇒ 那条线**不是引擎 artifact**。
> ASCII dump 显示 y≈762 一条约 2 px 横向特征、主带从 y≈787 起。
> 成因：**近乎侧向视角下烟带自身多边形/正面朝向翻转**（`side = dir.cross(to_cam)` 在视线几乎平行于带面时退化），
> **与 `ALPHA` 无关**（两遍都落在同一行、比值同样 ≈0.8）。
> ⇒ 它**不污染本轮结论**（两个读数都在主带主体上取），但**若要消除它，是另一个轮次的题**。
>
> **未决转已决** · P10（粒子层透明度要不要一起降）⇒ **不降**（保留 `suite_missile_smoke.gd:264`
> 的旧需求「色带起点加浓 —— 弹幕里烟读得出来」）· P11（柱长 −20% 算不算违反“体积不变”）⇒ **不算**
> （整条拖尾长度由烟带承担，柱长只是厚度那一段）。

**关键结构（整个方案都建在这上面）** · 拖尾是**两层**：

| 层 | 类 | 它负责 | 有"密度"这个量吗 |
|---|---|---|---|
| **烟带** | `MissileRibbon` | **长度**（沿弹道的连续带子） | **没有** —— 代码注释原话：「**没有"间距"这个量**」 |
| **粒子** | `GPUParticles3D`（`FX.missile_trail`） | **厚度** | **有** —— 间距 = 弹速 × lifetime ÷ amount |

⇒ **"密度 −20%"只能落在粒子层的 `amount`**。
而带子的 `SPACING 120` **不是密度旋钮**：它只决定折线分段的粗细（提高它不会让烟变稀，只会让转弯处出现折角）；并且现有判据对 `SPACING ∈ [120, 200]` **是盲的**（`suite_missile_smoke.gd:836-839` 的 `point_count` 在两个区间都落在 90~130）⇒ **改它既不改变观感也不会变红** —— 属于"改了一个没有判据看着的量"，**建议不碰**。

**⚠️⚠️ 核心算术：只降 `amount` 会打破「无缝」不变量**

- 引擎现值：峰值弹速 `missile_speed() = 420 × 1.55 × 2.4 × 2.6 = 4062.24 m/s`；`lifetime = 0.16`；`amount = 80`（HIGH）
  ⇒ 摊开后间距 = `4062.24 × 0.16 / 80 = 8.124 m`
- 粒子最大出生直径 = `1.8 × 8.5 × 0.65 = 9.945 m`
- ⇒ `8.124 < 9.945` ⇒ **相邻烟团重叠、连成一道**（轮 39 治好的那个病）

- **只降 amount（80 → 64）**：间距 = `10.156 m` **> 9.945 m**
  ⇒ ① `tests/suite_missile_smoke.gd:650-652` 的 `t.lt(spacing, diam_max)` **当场变红**；
  ⇒ ② 屏幕观感**退回"一串孤立的点"**（就是轮 39 用户投诉的那个现象）。
- **amount 与 lifetime 同比例降（80→64、0.16→0.128）**：间距 = **8.124 m（逐位不变）** ✅，粒子柱长 `650 → 520 m`（−20%）。
  ⚠️ 柱长是**厚度那一段**的长度，而**整条拖尾的长度由烟带承担**（12 km 交战时烟带实铺 100.0% 弹道）⇒ **玩家看到的拖尾长度与宽度都不变** ⇒ 满足"体积不变"。

**证据（文件:行）**

| 位置 | 内容 |
|---|---|
| `scripts/world/missile_ribbon.gd:49` | `const SPACING := 120.0`（注释：转弯误差 `120²/(8×1593) ≈ 1.1 m`，远小于带宽） |
| `scripts/world/missile_ribbon.gd:55` | `const MAX_POINTS := 512`（14 s × 4062 / 120 ≈ 474） |
| `scripts/world/missile_ribbon.gd:59` | `const HALF_W := 6.0` ← **体积（宽）** |
| `scripts/world/missile_ribbon.gd:61` | `const FADE_TIME := 1.6` |
| `scripts/world/missile_ribbon.gd:64` | `const ALPHA := 0.55` ← **烟带的透明度** |
| `scripts/world/missile_ribbon.gd:73-74` | `LOD_NEAR_M 2500` / `LOD_FAR_M 7000`（渲染抽稀，**只影响段数不影响长度**） |
| `scripts/world/missile_ribbon.gd:318-321` | `a_tail = ALPHA * f_tail * global_a` / `a_head = ALPHA * f_head * global_a` |
| `scripts/world/missile_ribbon.gd:351` | `func _along(idx, n) = 0.15 + 0.85 * t`（尾淡头浓） |
| `scripts/world/missile_ribbon.gd:122-125` | 材质：`TRANSPARENCY_ALPHA` + `vertex_color_use_as_albedo` |
| `scripts/world/fx.gd:1974-1975` | `const TRAIL_HIGH_AMOUNT := 80` / `const TRAIL_LOW_AMOUNT := 28` |
| `scripts/world/fx.gd:1993` | `static func missile_trail(parent, scale := 0.5, amount := TRAIL_HIGH_AMOUNT)` |
| `scripts/world/fx.gd:2061` | `p.lifetime = 0.16` ← **可动的那个因子** |
| `scripts/world/fx.gd:2065-2066` | `p.fixed_fps = 30`（簇间距的分母）/ `p.local_coords = false` |
| `scripts/world/fx.gd:2122-2128` | `pm.scale_min = 3.2 * scale` / `pm.scale_max = 8.5 * scale` ← **体积（粗）** |
| `scripts/world/fx.gd:2136-2140` | `color_ramp` 三点：`(0.86,0.86,0.89, 0.88)` / `(0.74,0.74,0.78, 0.56)` / `(0.62,0.62,0.67, 0.0)` ← **粒子的透明度** |
| `scripts/world/fx.gd:2100` | `const EMIT_SPAN := 135.4`（发射盒长 = 簇间距，摊开用） |
| `scripts/combat/missile.gd:170` | `return FX.TRAIL_LOW_AMOUNT if level == Trail.LOW else FX.TRAIL_HIGH_AMOUNT` |
| `tests/suite_missile_smoke.gd:650-652` | **不变量**：`t.lt(spacing, diam_max)`；`spacing = v_max * lifetime / amount`，`diam_max = 1.8 * pm.scale_max` |
| `tests/suite_missile_smoke.gd:654` | `t.lt(spacing, 12.0)` |
| `tests/suite_missile_smoke.gd:657` / `:659` | `col < 900` / `col > 200`（`col = v_max * lifetime`） |
| `tests/suite_missile_smoke.gd:661` | `col > hz * 2` |
| `tests/suite_missile_smoke.gd:264` | **`t.gt(r0.a, 0.84, "色带起点加浓 —— 弹幕里烟读得出来")`** ← **透明度 −20% 会撞到它** |
| `tests/suite_missile_smoke.gd:151` / `:326` | `LOW < HIGH` / `HIGH > LOW × 2` |
| `tests/suite_fx_plume.gd:573` / `:576` | **性能红线**：`3 × HIGH < 300` / `100 × LOW < 3000` |
| `scripts/flight/player_controller.gd:1920` | `const FULL_SALVO_COUNT := 100` |

**方案（三档，推荐 A）**

| 方案 | amount | lifetime | ALPHA（烟带） | 色带 alpha（粒子） | 间距 | 柱长 | 判定 |
|---|---|---|---|---|---|---|---|
| **A（推荐）** | 80→**64** / 28→**22** | 0.16→**0.128** | 0.55→**0.44** | **不动** | **8.124（不变）** | 650→520 | ✅ 全部不变量成立 |
| B | 不动 | 不动 | 0.55→0.44 | 0.88→0.704 | 8.124 | 650 | ⚠️ 只降了透明度，"密度"没变 ⇒ 不满足字面需求 |
| **C（否决）** | 80→64 / 28→22 | 不动 | 0.55→0.44 | 不动 | **10.156 ⇒ 破不变量** | 650 | ❌ 撞红 + 观感退回旧病 |

**⚠️ 透明度 −20% 撞到一条旧需求**：粒子层色带起点 alpha `0.88 × 0.8 = 0.704 < 0.84` ⇒
`suite_missile_smoke.gd:264` 的 `t.gt(r0.a, 0.84, "色带起点加浓 —— 弹幕里烟读得出来")` **变红**。
⇒ 想降**粒子层**的透明度，就必须同时**推翻**"弹幕里烟读得出来"这条旧需求（要拍板）。
**无痛的一半**：**烟带层** `ALPHA 0.55 → 0.44` —— 测试里**没有任何断言读 `MissileRibbon.ALPHA`**（已 grep 全 `tests/`）⇒ 自由。

**预算红线核对（方案 A 全过）**

| 红线 | 现值 | 方案 A | 结论 |
|---|---|---|---|
| `3 × TRAIL_HIGH_AMOUNT < 300` | 240 | **192** | ✅ |
| `100 × TRAIL_LOW_AMOUNT < 3000` | 2800 | **2200** | ✅ |
| `TRAIL_HIGH_AMOUNT > TRAIL_LOW_AMOUNT × 2` | 80 > 56 | **64 > 44** | ✅ |
| `LOW < HIGH` | ✅ | ✅ | ✅ |
| `spacing < diam_max` | 8.124 < 9.945 | **8.124 < 9.945** | ✅（关键） |
| `spacing < 12` | ✅ | ✅ | ✅ |
| `200 < col < 900` | 650 | **520** | ✅ |
| `col > 盒长 135.4` | ✅ | ✅ | ✅ |

**可证伪判据 + 负对照**

1. **间距不变量**：`v_max × lifetime ÷ amount < 1.8 × scale_max`（新值 8.124 < 9.945）。
   **负对照**：**只改 amount 不改 lifetime** ⇒ 10.156 > 9.945 ⇒ 必须红（这就是方案 C 的牙齿）。
2. **密度真的降了**：`amount == round(80 × 0.8) == 64` 且 `lifetime ≈ 0.16 × 0.8`（±1%）。
3. **透明度真的降了**：`MissileRibbon.ALPHA ≈ 0.44`（±0.005）。
   **负对照**：写回 0.55 ⇒ 红。
4. **体积不变**（把"体积"写成四条可证伪的断言）：`HALF_W`、`scale_min/scale_max`、`emission_box_extents`、`EMIT_SPAN` **四者逐位不变**。
   **负对照**：动其中任一个 ⇒ 必须红。
5. **性能红线**（既有）：四条预算断言全绿。
6. **真机**：同一机位、同一发弹，出 A/B 图；"挡视野"的客观量 = 画面中"白烟覆盖的像素占比"下降约 20%（不是靠肉眼说"淡了"）。

**未决** · P10（粒子层透明度要不要一起降 ⇒ 要放弃一条旧需求）· P11（柱长 −20% 算不算违反"体积不变" ⇒ 建议不算，因为整条拖尾长度由烟带承担）

---

## 4. 建议批次（按依赖 + 风险，不按用户报的顺序）

### 批 1 · 四小件（互相独立、各自能出真机判据）

**B2 · B1 · B6 · D4**

- 为什么一起：四者分属 `main_menu.gd` / `flight_pedal.gd`+`main.gd` / `player_controller._tick_holds`+`suit_profile.gd` / `main.gd` 的击毁回调 —— **没有一处重叠**，可以并行且互不干扰。
- 前置：只有 B6 需要 P2/P3 两处拍板（若取"所有有盾机体统一 80%、保留长按 R"，则零歧义）。

### 批 2 · 数据与参数级（判据以纯函数 / 引擎读数为准）

**B4 · D1 · D5**

- 三者都是"改数据 + 一处乘法"，判据都能写成可复算的算式。
- **B4 与 D4 同源**（都要读被击毁/被选中的机体名）⇒ 批 1 先落地能让 B4 的文案判据直接复用。

### 批 3 · `_tick_assist()` 链（**必须一起动**）

**B3 → D2**

- 为什么必须一起：B3 要改的是 `_tick_assist()` 的 `:1596 if translate_mode: return`，而 D2 要加的东西**正好也要挂进这条链**（`translate_mode` / `_read_translate_input`）。
  分两次动同一个函数 = 两次都要重新核"顺序关系"（本工程有"往 `if` 链插分支挤走上一条调用体"的前科）。
- **B3 是 D2 的前置**：先把两处早退（`辅助关` / `平移模式`）理清，再往上加"倒飞"，否则会在一块自己都没搞清的结构上加状态。

### 批 4 · 先取证再动

**B5**

- 第一件事是**跑 `tools/probe_aggression.tscn` 取现状读数**（含"被锁定时的状态直方图"），把"偶尔"变成一个数，再决定动 `ACE_*` 还是 `AGGRESSION`。

### 批 5 · 独立轮（最大件）

**D3**

- 建议再拆：**D3a（辅助瞄准 + 提示圈 + 提醒，接线级）** 可以并入批 3（因为也在辅助那条链上）；**D3b（放大镜）** 必须独立轮。
- 独立轮的原因：① 它要改 `README.md` 的一条需求（§16.1 第 4 条）；② 放大镜要从零建 `SubViewport`；③ 有性能红线要现场量。

### 全局注意事项（每一批都适用）

1. **不许顺手改**：本文件只设计不施工；任何一批开工前先备份 + md5 闸门（备份写**绝对路径** `%LOCALAPPDATA%\Temp\gundam_bak\rN\`）。
2. **并行会话**：本工程有并行会话 ⇒ 交付编号先 `ls _deliver` 核最大号；改前 / 改后各一份 md5 快照查窗口内的 `M/A/D`。
3. **判据的形态**：汇总行 + 节数 `^--- ` + 尾部条数表 + 四类报错（Parse / `SCRIPT ERROR` / SHADER / `Failed to load`）—— **不看退出码**；`0 FAIL ≠ 跑完`。
4. **玩家可见文案一改 ⇒ 收尾必须出真机图**（B6 的帮助表、D2 的状态提示、D3 的提醒、D4 的提示全都算）。
5. **半透明叠实时世界的判据不能逐像素相等**（D3 放大镜、D5 烟）⇒ 用对世界微动不敏感的统计量。

---

## 5. 拍板清单（我的建议在前）

| 编号 | 项 | 要拍的事 | 我的建议 |
|---|---|---|---|
| **P1** | B1 | "骑手模型该不该显示"的**裁决优先权**给谁 | 给踏板（升格为 `rider_hidden` 单一真源，`set_model_visible()` 过它）⇒ `main` 那一行不动 |
| **P2** | B6 | 撑盾 80% 改**哪几项** | 所有"有盾"机体统一 **0.80**；`_gustav_base()` 的 **0.0 保持**（那是"靶机没盾"，不是"免伤 0%"） |
| **P3** | B6 | 长按 R（`reload`）那一支留不留 | **留**（用户只说去掉 T）；帮助表手柄列同步 `"长按 B"` → `"长按 Y"` |
| **P4** | B4 | SQUAD 的敌机池要不要**按阵营过滤** | **要**（这是修 bug 的一部分：玩家选联邦时列表里不该出现柯西） |
| **P5** | D1 | m02 削弱档位 | **×0.75**（敌机 574 ≈ 玩家巡航 554 的 1.03 倍 ⇒ 不按加力也追得上，但不成"随便打"） |
| **P6** | B5 | 进攻欲望调**阿利宙斯专属**还是**ACE 通用** | **ACE 通用**（动 `ACE_ATTACK_PERIOD 12→9` + `ACE_COMMIT_WINDOW 4→5`），**不碰**已标定的 `AGGRESSION` |
| **P7** | D2 | 倒飞的**三条语义**（朝向 / 油门互换 / R3） | ①只翻速度方向（机头仍朝敌）②互换油门 ③手柄 R3 一起变成开关 |
| **P8** | D3 | 辅助瞄准与 `README.md` §16.1 第 4 条冲突（上一轮你拍的是"丙：不动弹道"） | **吸附只做 ≤ 2.5°（`AIM_ASSIST_SNAP_DEG`）**，弹道基本仍跟随准星 ⇒ 不改 README；若要 7° 就必须**明确改 README** |
| **P9** | D3 | 放大镜**是否必做**（成本最高、要从零建 `SubViewport` + 性能红线） | 先做 D3a（瞄准 + 提示圈 + 提醒），**放大镜单独立轮**并带性能预算 |
| **P10** | D5 | 粒子层透明度要不要一起降（要放弃"弹幕里烟读得出来"这条旧需求） | **不动粒子层透明度**，只在**烟带层**降（0.55→0.44）⇒ 零冲突 |
| **P11** | D5 | 粒子柱长 −20% 算不算违反"体积不变" | **不算**：整条拖尾的长度由烟带承担（12 km 交战实铺 100%），宽度 `HALF_W`/`scale_*` 全部不动 |
| **P12** | D4 | **终结性**击毁（最后一架）要不要提示 | **要**，但落在结算页/"已清空"那一行（否则 m02 这种单波关永远不会有坠毁提醒） |
| **P13** | B3 | 你说的「防撞地未生效」是哪一个语义 | **先给现场**：地图 / 是否开辅助 / 大概高度 / 能不能复现。我按"①撞上了没死"与"②辅助没帮我拉"两条分别准备判据（②按结构必然复现） |

**另有两条不属于本轮、但悬着的**（上一轮 ★63-8 的 §8/§九-2）：

- 柯西后刃长度取 7.5 / 9.0 / 11.0（建议 **9.0**）；"上长下短"是竖直还是共线（§九-5）
- 闪退现场取证（**取证之前不许改代码**）

---

## 6. 附录

### 6.1 本轮新建的只读工具

| 文件 | 用途 | 末尾标记 |
|---|---|---|
| `<workspace>/_d2_speed.py` → `_d2_speed.out` | 复刻 4 个速度函数（`player_top_speed` / `player_boost_speed` / `enemy_top_speed` / `enemy_top_speed_capped`），算"谁追得上谁"与 m02 的削弱阶梯 | `SPEED_ANALYSIS_DONE` |
| `<workspace>/_d3_smoke.py` → `_d3_smoke.out` | 设计 5 的两层账：间距不变量、柱长、预算红线、两层透明度与各自的守卫 | `SMOKE_DESIGN_DONE` |

两者都**只读工程**、不写任何工程文件。

### 6.2 零改动自证

**命令**

```bash
cd "C:/Users/MSIPC/Documents/gundam"
find . -newermt "2026-10-04 00:00" -type f | grep -v "/\.godot/" | xargs -I{} stat -c "%y  %n" {} | sort
```

**读数（本轮收尾时）** —— 今天被改过的工程文件共 **31 个**，其中：

- **01:17:06 ~ 04:23:59 的 30 个** = 更早的几轮（★63-6 房间+密码 / ★63-7 军刀验收尺 / ★63-8 军刀幅度重做）留下的，各自有自己的交付说明（`_deliver/187~195`），**与本轮无关**；
- **05:37:42 的 1 个** = 本文件 `DESIGN-2026-10-04-六bug五设计排查与设计.md`。

把窗口缩到本轮开始之后（`-newermt "2026-10-04 05:00"`），**只剩本文件一个**：

```
2026-10-04 05:37:42  ./DESIGN-2026-10-04-六bug五设计排查与设计.md
```

⇒ **`/scripts`、`/scenes`、`/tests`、`/tools`、`/assets` 在本轮内一个文件都没被动过。**

**本文件自身的格式口径**（与既有 `DESIGN-*.md` 一致）

```
CRLF = 0   CR-only = 0   BOM = False
bytes ≈ 82.6 KB   lines ≈ 994
```

（参照：`DESIGN-2026-10-03-七项问题排查与设计.md` = 57706 B / CRLF 0）
（本块自身被写进去时会让字节数再涨几十 —— 所以写"≈"，**判据是 CRLF / BOM 那两个零**，不是那个字节数。）

### 6.3 本轮读到的关键 `文件:行` 索引（下一轮直接跳）

```
【B1 穿模】       flight_pedal.gd:136 / :596-598 / :601 / :606 / :610 / :614 / :722 / :1265
                  main.gd:2865 · flight_body.gd:2074 · suit_profile.gd:2371 / :2479
【B2 联机卡住】   main_menu.gd:2472 / :2496 / :2499 / :2511 / :2513 / :2533-2540 / :2728 / :2868-2869
                  net_session.gd:227 / :247 / :252
【B3 防撞地】     player_controller.gd:230 / :629-633 / :1568-1574 / :1595-1596 / :1613 / :1623-1631
                  flight_assist.gd:37/41/78/88/91/105/107/125-146 / :276-290
                  flight_body.gd:29 / :2503-2507 / :2609-2613 / :2620-2622 / :2668-2670 / :2990-3010
                  bandit_ai.gd:33/35/51/53/55/56-63 / :561 / :893 / :925 / :954
【B4 小队战 ACE】 main_menu.gd:226 / :1063-1064 / :1479-1492 / :1561 / :1567 / :1569-1570 / :1579-1584 / :1606
                  battle_formation.gd:123-129 / :167 / :196 / :246 / :288 / :297-298
                  main.gd:1761
【B5 阿利宙斯】   bandit_ai.gd:112-121 / :731-748 / :783-796 / :1090-1106 / :1114-1118
                  README.md:1678 / :1680
【B6 丢枪/盾】    player_controller.gd:78-80 / :92-93 / :263-275 / :385 / :580-586
                  input_setup.gd:36 / :37 / :559-560 / :715 / :778
                  suit_profile.gd:326 / :751 / :791 / :1152-1153
                  / :1452 / :1559 / :2133 / :2218 / :2291 / :2387 / :2509
                  flight_body.gd:5226 · hud.gd:2545 / :3096 / :3100 · main_menu.gd:3360-3361
【D1 m02】        mission_script.gd:151 / :1369-1379 / :1505-1540 · challenge_script.gd:16-35
                  main.gd:2384-2387 · suit_profile.gd:2371 / :2532 / :2801-2850 / :2836
                  bandit_ai.gd:267-269 / :60-62 · suite_round.gd / suite_round14.gd
【D2 CTRL 倒飞】  input_setup.gd:33 / :571 / :745 · flight_model.gd:21 / :115
                  player_controller.gd:556-563 / :646 / :661-702 / :694-701
                  flight_body.gd:162 / :776 / :2578 / :3201 / :3314
【D3 辅助瞄准】   flight_body.gd:3550-3551 / :3560-3568 / :3570-3584 / :3605
                  ballistics.gd:76-79 · projectile.gd:82-85
                  lock_on_system.gd:315 / :914 / :925 / :938 / :945 / :952
                  hud.gd:1368 / :1425 / :1611 / :1706-1713 / :1732
                  scenes/main.tscn（无 SubViewport）· settings.gd:107
【D4 坠毁提醒】   flight_body.gd:5320-5321 / :5325
                  game.gd:504-524 / :527-533 / :553-560
                  main.gd:1720 / :1893 / :2393 / :3029-3030 / :3084-3094
                  hud.gd:1093 / :1100-1103 / :3733 / :5550-5562 · player_controller.gd:41
【D5 拖尾烟】     missile_ribbon.gd:49 / :55 / :59 / :61 / :64 / :73-74 / :122-125 / :318-321 / :351
                  fx.gd:1974-1975 / :1993 / :2061 / :2065-2066 / :2100 / :2122-2128 / :2136-2140
                  missile.gd:170
                  suite_missile_smoke.gd:264 / :650-661 / :151 / :326
                  suite_fx_plume.gd:573 / :576 · player_controller.gd:1920
```

---

**（本文件对产品源码的改动 = 零。施工请另开一轮，并按每一批的"判据 + 负对照"逐条过。）**
