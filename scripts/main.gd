extends Node3D
## 主场景：装配世界、双方机体、镜头、HUD，并驱动整个回合流程。
##
## 流程：**主菜单（选机体 → 选难度）→ INTRO → FIGHT → WIN/LOSE → 回主菜单**
##
## 注意：**没有"再战一局"**。结算之后一律回主菜单重新选机体与难度
## （用户要求撤掉再战，顺带也就没有了"重开时漏清状态"那一类 bug）。
##
## 全部节点都由代码创建（工程里没有手搭的 .tscn 场景树）。
## 玩家选哪台机，敌机就是**另一台** —— 两台模型剪影完全不同，
## 所以不需要靠涂装来区分敌我，HUD 的目标框 + 雷达继续负责识别。

## ⚠️ 1.2 起**没有 INTRO**：用户要求删掉"按空格出击"，菜单一关就直接进 FIGHT。
## 原枚举里的 `INTRO` 已删掉 —— 留着一个永远不会被赋值的成员，
## 只会让后来的人以为"还有这么一个阶段"（`Game.Phase.INTRO` 另有一个，
## 那是给暂停/HUD 判定用的，情况不同，暂时保留）。
##
## ★ 轮 C 加了 `CAMPAIGN` / `BRIEF` 两档：**剧情模式的"出击"不再直接开打** ——
## 菜单只是把玩家送进**战役图**，真正的出击发生在"选关 → 读简报 → 按确认"之后。
## 两页都由 main 持有（而不是塞进 `MainMenu`），因为它们的输入去向是**进战斗**，
## 而菜单的职责到"发射一局配置"（`start_match` 信号）为止。
## ⚠️ 枚举**只加成员、不改已有成员的顺序**：`suite_round::_main_phase()` 是按**名字**
## 从 `get_script_constant_map()` 里取的，重排会让一批断言莫名其妙地红。
##
## ★ 2026-09-30：`LAUNCH` 插在 **`BRIEF` 与 `FIGHT` 之间** —— 语义上它就在那儿
##（读完简报、开打之前）。
## ⚠️ 它会把 `FIGHT` / `RESULT` 的**数值**各推后一位。已核过一遍：本仓库对
## `Main.Phase` **没有一处读数值** —— `suite_fpv` 是查源码子串、`suite_round`
## 是用 `get_script_constant_map()` 按名字取。谁将来要按数值存盘，得先看这一行。
enum Phase { MENU, CAMPAIGN, BRIEF, LAUNCH, FIGHT, RESULT, POD_STRIKE, DAVAO_INTRO, SORTIE }

## ⚠️ **对局尺度常量已经挪到 `WorldBuilder`**（`SPAWN_RADIUS` / `PLAYER_START_ALT` /
## `ENEMY_START_ALT`）。原因：`main.gd` **没有 `class_name`**（它是挂在场景根节点上的
## `extends Node3D`），所以**测试里读不到这里的常量** ——
## `suite_round19` 第一版就是这么红的（`Identifier "Main" not declared`）。
## 而这一组数必须与 `ARENA_RADIUS` 一起被断言（"出击点在世界内""槽够不够飞完"），
## 于是放在有 `class_name` 的 `WorldBuilder` 上，这里只做转发。
const SPAWN_RADIUS := WorldBuilder.SPAWN_RADIUS
const PLAYER_START_ALT := WorldBuilder.PLAYER_START_ALT
const ENEMY_START_ALT := WorldBuilder.ENEMY_START_ALT
## 训练模式撒几架靶机。四架的理由：三架时"绕圈打靶"太稀疏、六架时同时锁定的
## 目标切换会变得混乱，而四架的三角 + 一架错开相位刚好能看清提前量练习的效果。
## （每架古斯塔夫 4.5 万面，撒太多也会真的吃掉帧率。）
const TRAINING_TARGETS := 4
const TRAINING_PATROL_ALT := 2600.0
## ⚠️ 靶场半径的真源在 `WorldBuilder`（那边有 `class_name`，测试读得到）。
## 这里**转发而不是重抄一个 5200**：两份字面量迟早会对不上，
## 而"靶场半径"和"竞技场半径"的关系是有断言盯着的（`suite_round19`）。
const TRAINING_PATROL_RADIUS := WorldBuilder.TRAINING_PATROL_RADIUS

## 三渲二全屏后处理 shader（批 17）。思路来自 B 站教程 BV1PGBiBvEFG
## 的 cel-shading 方案，落地为全屏 canvas_item 后处理 —— 见 cel_post.gdshader 头注。
const CEL_POST_SHADER := "res://shaders/cel_post.gdshader"

# ============================================================ ★ 轮 C：剧情模式的四个件
#
## ⚠️ 一律走 `preload` 而**不是** `class_name`：本仓库是并行编辑的，新加的 `class_name`
## 只有在编辑器重新扫过之后才进 `.godot/global_script_class_cache.cfg`；在那之前
## `CampaignScript.xxx` / `MissionScript.xxx` 会**当场编译失败**，而 `--headless`
## 跑回归时没人会去刷新那份缓存（详见 `campaign.gd` 文件头那段）。
## 数据层的两个别名与 `suite_campaign.gd` 用的是同一对（`MS` / `CS`），
## 三处指向同一份真源、不会各建一份。
const MS := preload("res://scripts/data/mission_script.gd")
const CS := preload("res://scripts/data/campaign.gd")
## 战役播片的片目表（轮 C 只留钩子：P/B/D 三处接线，四槽位的完整系统是轮 G）。
const CUT := preload("res://scripts/data/cutscene_script.gd")

## 三页 UI（都是 `extends Control`、没有 `class_name`，只能按路径取）。
const CAMPAIGN_MAP_UI := preload("res://scripts/ui/campaign_map.gd")
const MISSION_BRIEF_UI := preload("res://scripts/ui/mission_brief.gd")
const MISSION_TITLE_UI := preload("res://scripts/ui/mission_title.gd")

var world: WorldBuilder
var projectiles: Node3D
var units_root: Node3D
var chase: ChaseCamera

var canvas: CanvasLayer
var hud: FlightHUD
var menu: MainMenu
var pause_menu: PauseMenu
var speed_lines: SpeedLines
## 三渲二全屏后处理（批 17）。挂在 `canvas` 的**第一个**子节点位：
## CanvasLayer 的子节点按顺序画，最底的那个才能盖住 3D 画面、又不盖住 HUD。
## 开关在设置页（`Settings.cel_shading`），控制的是这一层的 visible。
var cel_quad: MeshInstance3D
## 读条界面（批 10）：进战斗地图前的全屏加载层。
## 走 `_begin_match_loading()` 的菜单路径会用到；测试直调的 `_on_start_match()` 不经过它。
var loading: LoadingScreen
## ★ 轮 C：剧情模式的**战役图**（选关）与**简报页**。
## 挂在 `canvas` 上、`menu` 之后 `pause_menu` 之前 —— 它们是"菜单那一层"的界面，
## 但暂停菜单仍要能盖住它们。
var campaign_map: Control
var mission_brief: Control
## ★ 轮 C：**任务标题卡**（`MISSION 04` + 任务名 + 地图名，2 秒）。
## ⚠️ 它是 `canvas` 的**最后一个**子节点：CanvasLayer 的子节点按顺序画，
## 最后挂的才盖得住读条层（标题卡必须在读条收完之后出现在最上面）。
var mission_title: Control
## 剧情模式里玩家在主菜单选的难度。剧情模式**不做机体页**（机体由每一关的
## `Mission.player_suit` 定，§9.5 的 POV 就是靠它），但难度还是玩家选的。
var _campaign_level := Difficulty.Level.NORMAL
## 剧情模式**当前这一关**的 id（`""` = 不在剧情流程里）。
## 它同时是"重来"要重开的那一关 —— 所以不能在回菜单时清掉，
## 只能在真正离开剧情流程（`_show_menu()`）时清。
var _campaign_mission_id := ""
## ★ 剧情模式存档路径。默认就是 `CampaignScript.PATH`（`user://campaign.cfg`）。
##
## ⚠️ 它是**给测试留的注入点**，不是配置项：§6.6 的第 1 条存档纪律是
## "读写走注入路径"—— 套件里跑一遍真流程就会**写花玩家的存档**（军资、解锁进度），
## 而那种损失是查不回来也不该发生的（`Settings` 那边栽过一次，见 `campaign.gd` 头注）。
## `suite_sally` 把它指到一个临时文件，于是"真流程 + 真落盘"这两件事**都能被测**，
## 而玩家那一份**一个字节都不动**。
var campaign_save_path := CS.PATH
## 开场动画（进游戏一开头）。**没播 / 已播完时为 null** ——
## 它不是 `canvas` 的常驻子节点，只有"真开局"那一次才由 `_maybe_play_intro()` 现造。
var intro: IntroMovie

var player: PlayerController
var enemy: BanditAI
var player_lock: LockOnSystem
var enemy_lock: LockOnSystem
## 训练模式的靶机（对战模式下为空）。
var targets: Array[TargetDrone] = []
## 剧情挑战里的敌机（1.2）。按波次创建，波次清空后换下一波。
var wave_units: Array[BanditAI] = []
## 联机里"对手那台机"的本地代理（1.2）。
##
## ⚠️ 第二十二轮下半：多人模式里**可能不止一个**远端玩家（同队时远端是队友），
## 所以真正的真源是下面的 `remote_proxies` 数组；`remote_proxy` 保留为
## **"第一个 / 对面那个"**的别名，1v1 那套代码与测试继续用它。
var remote_proxy: NetProxyBody = null
## 这一局里**所有远端玩家**的代理机体（主机视角：加入方那一台；加入方视角：主机那一台）。
var remote_proxies: Array[NetProxyBody] = []
## 每台 AI 敌机都有自己的锁定系统（多敌机时不能共用一条）。
var _ai_locks: Array[LockOnSystem] = []

var phase := Phase.MENU
var _death_anchor: Node3D
var _menu_angle := 0.0
var _paused := false
## 上一帧"有多少枚导弹在追我"，用来抓 0→N 的边沿（警报只在刚出现时响一次）。
var _prev_incoming := 0
## 残血告警只喊一次，别一直喊。
var _low_hp_announced := false
## 阶段切换时的输入锁。防止"上一个界面的按键被下一个界面接着吃"。
##
## 两种都会真的发生：
##   - 菜单按 Enter 开局 → 同一帧 `main` 也可能看到这个 `just_pressed`，
##     于是 INTRO 直接被跳过、一开局就是 FIGHT（玩家根本没看到"按空格出击"）；
##   - 击坠那一刻手还按着开火/确认键 → 结算画面一闪而过。
## 所以每次切阶段都上锁，锁内不吃输入。
var _phase_lockout := 0.0

## 当前这一波从 `Game.elapsed` 的哪一刻开始。波次用时靠它算。
var _wave_started := 0.0
## ★63-24 无限强化演习：`CLEARING` 的计时器（秒）。
##
## 语义与 `EndlessScript.CLEARING_SECS` 配套：最后一架爆掉之后还要等一会儿
## 才刷下一波，让爆炸特效 / 击坠播报收完尾（设计 §4.1 专门给它一个状态的理由）。
var _endless_clear_t := 0.0
## ★63-24 演习抽卡用的随机源。
##
## ⚠️ 自己持有一个（而不是用全局 `randi()`）：演习的阵容是"每波现算"的，
## 有一个显式的 rng 之后，将来要复现某一局只需把种子写进日志即可
##（`EndlessScript.wave_suits()` 也正好收一个 rng 参数）。
var _endless_rng := RandomNumberGenerator.new()
## ★63-24 间歇轮：**鼠标左键的按键闩**（自己做边沿用）。
##
## `Input` **没有** `is_mouse_button_just_pressed()`，只有 `is_mouse_button_pressed()`
## ⇒ "这一帧刚按下"必须自己量：拿上一次的按下状态与该帧比较。
## 不量边沿的话，按住左键会**每帧选一张**（奖励轮的 2/3 张一个按住就全被吃掉）。
##
## ⚠️ 为什么不用 `fire_primary`（左边就是鼠标左键）当这个闩：那个动作是
## **鼠标左键 + 手柄右扳机**两个物理键，用手柄的人会变成"按扳机选卡"。
## 键鼠 / 手柄在这一屏上各有各的入口（见 `_read_endless_round_input()`）。
var _endless_lmb_held := false
## ★ 轮 C：结算页 `R 重来` 的按键闩。
##
## `R` **没有对应的输入动作**（`project.godot` 里没有它的映射），所以只能自己量边沿 ——
## 直接 `Input.is_key_pressed(KEY_R)` 会**每帧触发一次重来**（按住不放就是连环重开）。
## 它在 `Phase.RESULT` 的**每一帧**（含锁内）都要更新：只在锁外更新的话，
## "锁内按着 R、锁一过就判成刚按下"会立刻重来一次，玩家根本没想按。
var _restart_held := false
const PHASE_LOCKOUT := 0.35
const RESULT_LOCKOUT := 0.6

# ============================================================ ★ 发射段（剧情模式 M03）

## 火箭资产。**运行时 `load()`，不用 `preload()`** —— 见 `_attach_rocket_model()`。
const ROCKET_MODEL := "res://assets/models/mafty_rocket/mafty_rocket.glb"
## 玩家操控的载具本体。
##
## ⚠️ 类型写 `RocketBody` 而**不是** `Node3D`：写 `Node3D` 的话 `rocket.step(...)`
## 在**解析期**就报 "Cannot find member"，只能退化成 `rocket.call("step", ...)`——
## 那样每个参数都成了 `Variant`，一个打错的字要跑到运行时才炸。
var rocket: RocketBody = null
## ★ 发射段的容器。
##
## ⚠️⚠️ **绝不能挂 `units_root`**：`_clear_match()`（**每一局开局都会调**）
## 会把 `units_root` 的子节点**全部 `free()`** —— 火箭刚飞到 550 km 就被清掉，
## 而玩家下一步正要回头拿它当"我从哪儿来"的锚点。
## 而且 `rocket` 会变成一个**已释放节点**，后面任何读它的代码都会炸。
## ⇒ 单独一个容器，与那条清理路径完全不相干。
var launch_root: Node3D = null
## 换图有没有已经启动（只启动一次）。
var _story_skip:CanvasLayer
var _story_launch_skipping:=false
var _orbit_swap_started := false
## ★★ 换图**完成**了没有（`_swap_to_orbit()` 走到尾）。
##
## ⚠️ 它和 `_orbit_swap_started` 是**两件事**：启动那一刻世界还是旧的，
## 而交还操控必须等到新图建完（`rocket.room_swapped` 也才为真）。
## 从前这两件事由"换房间工序"的状态机一处兼管；幕布删掉之后
## 必须显式留一个"建完了"的位，否则 `_finish_launch()` 会在换图途中被触发。
var _orbit_swap_done := false
## ★★ 换图窗口**锁住眼位档**（老板 2026-09-30 定的做法）。
##
## ## 为什么靠"进舱"来换图
## 老板：「**把玩家视角跳到座舱内，然后星空盒都是同一片的情况下可以直接换**」。
## 世界是**先卸后建**的（`WorldBuilder._map_stage_free()` 把上一张图整个 `free()`），
## 中间那几帧什么都没有 —— 而这一段的舱内表现（全周天刻度导轨 + 仪表台）
## 是**画在屏幕上的**，外面是空的它照样在，于是那几帧是否空世界就不再重要。
##
## ⚠️ 它必须是一个**闩**而不是一次调用：`_apply_camera_settings()` 每帧都按
## `Settings.first_person` 重写眼位档（那一行在 `launch_view()` 分支里），
## 只调一次 `set_launch_eye(COCKPIT)` 会被**下一帧顶回去**，
## 于是"遮住换图"这件事在玩家的追尾视角下彻底失效 —— 而且**不报任何错**。
var _swap_eye_lock := false
## ★★ 发射段的眼位档：`true` = 座舱，`false` = 贴近追尾。**由 F1 翻**。
##
## 老板 2026-09-30：
## > 「**另外可以随便按F1切换火箭时候仓内的第一人称视角**」
##
## ## ⚠️ 为什么不让 F1 直接翻 `Settings.first_person`
## 那个是**玩家跨对局的偏好**（存进 cfg、换机体换关卡都还在），而本段是
## "想从箭顶往外看一眼"。两者共用一个位的话，玩家在发射段按一下 F1，
## 到手的机体就永久变成了第一人称 —— 那不是他要的，而且他不会知道是谁改的。
## ⇒ 进段时从 `Settings.first_person` **取一次初值**（上一局开着座舱的玩家，
##   进发射段还在舱里，符合直觉），之后各走各的。
var _launch_eye_cockpit := false
## 倒计时剩余秒数。`<= 0` ⇒ 点火，开始接受输入。
var _launch_countdown := 0.0
## ★ **主发动机火焰与拖尾**（老板：「火箭升空的时候都没有大型火焰拖尾」）。
var launch_flame: RocketFlame = null
## ★ "这一局的出生点由发射段的抵达点给" —— 见 `spawn_round()`。
##
## ⚠️ 不能拿一个坐标当哨兵（`Vector3.ZERO` 是合法位置），必须是一个独立的 `bool`。
var _spawn_from_launch := false

# ============================================================ ★ 轮 57：M04 开场演出
#
# 「佩涅罗佩用光束大炮轰柯西运输仓」（老板 2026-09-30）。时间线在 `PodStrikeScript`，
# 流程在 `_begin_pod_strike()` / `_tick_pod_strike()` / `_finish_pod_strike()`。
#
# ⚠️ **`preload` 而不是直接用 `class_name`**：本仓库有并行会话，新加的 `class_name`
# 在编辑器重新扫描之前**不在全局类缓存里**，直接引用会当场编译失败
#（`mission_script.gd` 的 `map_id()` 那段注释记着这个坑）。同 `flight_body.gd`
# 的 `BeamCannonScript`。
var _chapter_three: Node3D
var _davao_director: Node3D
var _sortie_director: Node

const PodStrike := preload("res://scripts/data/pod_strike_script.gd")
const BeamCannonScript := preload("res://scripts/combat/beam_cannon.gd")
## 演出已走的秒数。只喂 `PodStrikeScript` 的纯函数，不参与任何别的判定。
var _strike_director: Node3D
var _strike_t := 0.0
var _strike_view_restore: Variant = null
## 演出里那条光束柱。`_finish_pod_strike()` 负责收掉它。
var _strike_beam: Node3D = null
## 演出里被接管的敌机（佩涅罗佩）。演完必须**把 AI 放回去**。
var _strike_foe: BanditAI = null
## 镜头是不是已经切到玩家了（`PodStrikeScript.T_CUT` 之后那一段）。
var _strike_cut := false
## 演出里的**运输仓本体**（`_build_transport_pod()` 建的 `PodBody`）。
## 起火之后每帧改它的 `position` / `rotation` —— 纯表演，见 `_tick_pod_strike()`。
var _strike_pod: Node3D = null
## 运输仓**原来**的位置（演出结束后不还原：这一局打完就换图了）。
var _strike_pod_home := Vector3.ZERO
## 运输仓的 **HUD 信标锚点**（`POD_TAG_GROUP` 那个 `Marker3D`）。
## ⚠️ 它**必须跟着仓体一起沉** —— 不然指示框停在原位、仓体掉到 150 m 以下，
## 画面上就是"框指着空处"（分离量 150 m ≫ 屏幕分辨力，一眼就看得出来）。
var _strike_pod_tag: Node3D = null
## ★ 2026-10-01：开场演出是不是**已经替这一局起过 BGM**。
##
## 老板口径：「car5p3/PENELOPE 演出 11 秒播放，**然后也作为本关的 bgm**」
## ⇒ 演出起的那一首**要接着当战斗曲**，`_start_fight()` 里必须跳过重起
##（`play_bgm(BATTLE)` 的语义是「接着轮换下一首」⇒ 再调一次就是**当场切歌**）。
## M03 发射段和 M01 出击演出会把它置真；M04 演出改用 XI，不置真。
## 进入战斗时由 `_start_fight()` **消费一次**
## 并清掉，所以「演出演完了但战斗重进一次」也不会把曲子接错。
var _strike_bgm_live := false


signal startup_stage(frac: float, label: String)
signal startup_finished
var staged_startup := false
var _startup_map_ready := false
var _transition_busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# **状态机必须先于喂它输入的 UI 处理**。
	#
	# Godot 默认按树序处理（父先子后），但同帧内的先后一旦反过来就会出事：
	# main 在 `_process` 里切阶段（比如结算页按 Enter 回主菜单 → 给菜单上锁），
	# 而菜单的 `_process` 若在这一帧更早跑过，它读到的还是"上一帧的状态"——
	# 同一个按键被两个界面各吃一次，于是"回主菜单"会顺带把菜单也推进一步。
	# 用 process_priority 把 main 钉在最前，这类同帧竞争从根上消失。
	process_priority = -100
	_build_world()
	# "检测到手柄就切换提示"：设备一变就切文案，并弹一条提示告诉玩家换了
	InputSetup.input_device_changed.connect(_on_input_device_changed)
	InputSetup.gamepad_connected.connect(_on_gamepad_connected)
	# ★ 轮 50：**地标被打中** —— 剧情关的目标达成事件。
	#
	# ⚠️ 这是本文件**第一个也是唯一一个** `Game` 信号接线。
	# 之前 `Game` 只在“被动式”地被读（`Game.phase` / `Game.player`），
	# 判胜**回路**一直分两条：`Game._evaluate_end()` 管 `Game.phase`，
	# `main._finish_round()` 管结算页——而两者原本靠
	# “敌机被击墜”这**同一个事件**各自推进。M01 一架敌机都没有，
	# 那个事件永远不会发生 ⇒ 必须再给一条路。
	Game.landmark_hit.connect(_on_landmark_hit)
	_build_camera()
	_build_ui()
	# ⚠️ 开场动画挡在 `_show_menu()` **前面**。该不该播全在 `IntroMovie.should_play_now()`
	# 里（**同步**判据：无头 / 被工具当子节点挂起来跑 / `--skip-intro` / 素材缺失
	# ⇒ 一律不播）。于是只有"真开局"那条路会把主菜单延后到动画结束
	#（`_on_intro_finished`），而 320 个套件与 11 个截图探针走的还是原来那一行。
	if staged_startup:
		_finish_startup.call_deferred()
	elif not _maybe_play_intro():
		_show_menu()


func _finish_startup() -> void:
	menu.close_menu()
	hud.hide()
	world.build_stage.connect(_forward_startup_stage)
	await world.apply_map_staged(MapDef.pacific())
	world.build_stage.disconnect(_forward_startup_stage)
	_startup_map_ready = true
	startup_finished.emit()

func _forward_startup_stage(frac: float, label: String) -> void:
	startup_stage.emit(0.35+frac*0.63,label)

func _return_to_menu_loading() -> void:
	if _transition_busy: return
	_transition_busy = true
	_set_paused(false)
	menu.close_menu()
	loading.open("返回主菜单")
	loading.advance(0.05,"清理战斗……")
	await get_tree().process_frame
	_clear_match()
	world.build_stage.connect(_on_world_build_stage)
	await world.apply_map_staged(MapDef.pacific())
	world.build_stage.disconnect(_on_world_build_stage)
	_startup_map_ready = true
	_show_menu()
	menu.close_menu()
	await loading.finish()
	menu.open_menu(PHASE_LOCKOUT)
	_refresh_super_hard_unlock(DisplayServer.get_name()!="headless")
	_transition_busy = false


# ============================================================ 装配

## ⚠️ **暂停要真的停住世界，靠的是这里的 PROCESS_MODE，而不是 `get_tree().paused` 本身。**
##
## Godot 的进程模式是**继承**的：main 为了在暂停期间还能收输入被设成 `ALWAYS`，
## 于是它所有 `INHERIT` 的子节点（世界、双方机体、弹丸、镜头）也一起变成 ALWAYS ——
## 树暂停对它们**完全无效**。玩家看到的就是"按了 Esc，遮罩出来了，可战斗还在继续"。
##
## 所以"要停的东西"必须显式标成 `PAUSABLE`：
##   - 世界（`world`）：天空/海面/云
##   - 场上单位与弹丸（`units_root` / `projectiles`，机体自身是它们的子节点）
##   - 追尾镜头（`chase`）
## 而"暂停期间还要活着的东西"另外显式标成 `ALWAYS`：
##   main 自己（收输入）、HUD、速度线、主菜单、暂停菜单 —— 都在下面标好了。
func _build_world() -> void:
	world = WorldBuilder.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	# initial_map / initial_preset 必须在 add_child 之前设：WorldBuilder._ready() 里就会应用它
	# 现在是夜战专用，所以默认时段直接给夜晚；地图先给太平洋群岛，
	# 回主菜单与开局时都由 `_show_menu()` / `_on_start_match()` 显式换图。
	world.initial_preset = TimeOfDay.Preset.NIGHT
	world.initial_map = MapDef.Id.PACIFIC
	world.defer_initial_map = staged_startup
	add_child(world)

	units_root = Node3D.new()
	units_root.name = "Units"
	units_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(units_root)

	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	projectiles.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(projectiles)

	# ★ 发射段的运载器容器 —— **故意不叫 `units_root`**，见 `launch_root` 的声明。
	launch_root = Node3D.new()
	launch_root.name = "Launch"
	launch_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(launch_root)


func _build_camera() -> void:
	chase = ChaseCamera.new()
	chase.name = "ChaseCamera"
	chase.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(chase)


func _build_ui() -> void:
	canvas = CanvasLayer.new()
	canvas.name = "HUDLayer"
	add_child(canvas)

	# ---- 三渲二全屏后处理（批 17 立项，批 19 重写挂载）----
	# ⚠️ **必须是挂在相机下的 spatial 全屏面片**，不能用 canvas_item ColorRect：
	# Godot 4.7 的 canvas_item shader 不支持 hint_depth_texture（真渲染编译
	# 直接报错 → ColorRect 显示默认白色 → "进战斗地图全屏白光"）。
# spatial 面片在顶点里写 clip space 铺满屏幕、透明队列最后画：
# 读 SCREEN_TEXTURE（完整 3D 画面）+ DEPTH_TEXTURE（场景深度）做量化与描边。
# ⚠️⚠️ 顶点那两行**两个分量都不许翻转**：任何翻转轴的映射会让屏幕空间绕序反转，
# 被默认的 `cull_back` 整个剔除 ⇒ **一个像素都不渲染**，而日志一切正常。
# 本效果从批 17 起一直没在画，就是这一条（详见 `cel_post.gdshader` 的头注）。
# HUD 等 2D 层永远在 3D 之后，保持锐利不进效果。
# 排序**显式**声明（`render_priority = 100`）→ 排在所有透明 FX
#（尾焰/光晕，priority 0）之后，screen_texture 才是"加了特效之后"的完整画面。
	cel_quad = MeshInstance3D.new()
	cel_quad.name = "CelPost"
	var cel_plane := QuadMesh.new()
	cel_plane.size = Vector2(2.0, 2.0)
	cel_quad.mesh = cel_plane
	if ResourceLoader.exists(CEL_POST_SHADER):
		var cel_mat := ShaderMaterial.new()
		cel_mat.shader = load(CEL_POST_SHADER)
		# ⚠️ 排序**必须显式声明**，不能靠"它在相机前 1 m，深度排序自然把它放最后"。
		# 那是**间接**的：一旦有 FX（尾焰/爆光）比它更近，后处理就插在中间，
		# `screen_texture` 里少了那部分特效 ⇒ 量化/描边作用在**半成品**上。
		# 100 排在所有 FX（priority 0）之后 ⇒ 读到的是加了特效的完整画面。
		# （批 K · 轮 3 补：原注释一直写着"render_priority 拉满"，而代码里从来没设过。）
		cel_mat.render_priority = 100
		cel_quad.material_override = cel_mat
	cel_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cel_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# 顶点被 vertex() 强制写进 clip space，模型真实位置在近平面之前
	#（z=-1 < near=1.2）—— 不给巨大的剔除余量，AABB 视锥剔除会把整个面片剔掉。
	cel_quad.extra_cull_margin = 10000.0
	cel_quad.visible = Settings.cel_shading
	chase.add_child(cel_quad)
	cel_quad.position = Vector3(0.0, 0.0, -1.0)
	# 设置页的开关立即生效：监听 changed（Settings 在 autoload 里比本节点先 ready）。
	Settings.changed.connect(func() -> void: cel_quad.visible = Settings.cel_shading)

	speed_lines = SpeedLines.new()
	speed_lines.name = "SpeedLines"
	speed_lines.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(speed_lines)

	hud = FlightHUD.new()
	hud.name = "HUD"
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(hud)

	menu = MainMenu.new()
	menu.name = "MainMenu"
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(menu)
	menu.start_match.connect(_begin_match_loading)

	# ---- ★ 轮 C：剧情模式的两页（战役图 → 简报）----
	# 位置在这里是刻意的：**menu 之后、pause_menu 之前**。
	#   前 ⇒ 它们画在菜单之上（菜单在这一流程里是关掉的，但不留"重叠时谁在上面"的疑问）；
	#   后 ⇒ 暂停菜单仍盖得住它们（战斗中按 Esc 那条路）。
	# 两页都是 `process_mode = ALWAYS`，与 HUD / 菜单 / 暂停菜单同一档：
	# 它们要在**非暂停的菜单态**下自己 `_process` + 收键盘。
	campaign_map = CAMPAIGN_MAP_UI.new()
	campaign_map.name = "CampaignMap"
	campaign_map.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(campaign_map)
	campaign_map.mission_chosen.connect(_on_campaign_chosen)
	campaign_map.cancelled.connect(_on_campaign_cancelled)
	campaign_map.difficulty_changed.connect(_on_campaign_difficulty_changed)

	mission_brief = MISSION_BRIEF_UI.new()
	mission_brief.name = "MissionBrief"
	mission_brief.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(mission_brief)
	mission_brief.confirmed.connect(_on_brief_confirmed)
	mission_brief.cancelled.connect(_on_brief_cancelled)

	# 暂停菜单挂在 HUD 之上（CanvasLayer 的子节点按顺序画）。
	# 它和 HUD / 主菜单一样是 ALWAYS：树暂停之后还得有人能画出界面、收得到输入。
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(pause_menu)
	pause_menu.resume_requested.connect(_on_pause_resume)
	pause_menu.menu_requested.connect(_on_pause_back_to_menu)

	# 读条层**最后挂**：CanvasLayer 的子节点按顺序画，最后挂的在最上面 ——
	# 读条必须盖住主菜单与暂停菜单。
	loading = LoadingScreen.new()
	loading.name = "LoadingScreen"
	loading.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(loading)

	# ---- ★ 轮 C：任务标题卡，**挂在读条之后**（也就是 canvas 的最上层）----
	# 它只有 2 秒、黑底铺满全屏，作用是"把读条那一屏和战斗那一屏隔开"。
	# 挂低一层就会被读条层的收条淡出盖住一半（读条是最后挂的，见上一段）。
	mission_title = MISSION_TITLE_UI.new()
	mission_title.name = "MissionTitle"
	mission_title.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(mission_title)


# ============================================================ 菜单

func _show_menu() -> void:
	if Net.role != Net.Role.NONE:
		Net.close()
	LanBrowser.stop()
	# 先把暂停清掉：从暂停状态切回菜单/重开时忘了清，
	# 就会出现"新一局在暂停的树里跑"这种假死
	_set_paused(false)
	_clear_match()
	# ★ 轮 C：回主菜单 = **真的离开剧情流程** —— 战役图/简报页关掉、
	# 当前关清空（`R 重来` 重开的依据就是它，留着会让下一局莫名其妙地重开上一关）。
	_close_campaign()
	Game.active_difficulty = null
	# 菜单背景固定用太平洋群岛（夜）—— 菜单不跟着上一局选过的地图变，
	# 否则"回主菜单"时背景会突然变成沙漠，看着像出错了。
	Game.active_map = MapDef.pacific()
	Game.active_time_of_day = Game.active_map.time_of_day
	if not _startup_map_ready:
		world.apply_map(Game.active_map)
	_startup_map_ready = false
	phase = Phase.MENU
	Game.set_phase(Game.Phase.MENU)
	menu.stage = MainMenu.Stage.MODE
	# 菜单要上锁，而且**先关 active**：触发"回主菜单"的那一下按键会被菜单在同一帧看到，
	# 只靠计时锁不够稳（main 与菜单谁先处理这一帧不确定）。关掉 active 就与顺序无关了。
	menu.open_menu(PHASE_LOCKOUT)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	hud.visible = false
	speed_lines.set_intensity(0.0)
	speed_lines.set_dash(0.0)
	chase.set_target(null)
	Audio.play_bgm(Audio.Bgm.MENU)

	_prev_incoming = 0
	_low_hp_announced = false


## 开场动画（进游戏第一眼）。返回 true = 动画接手，`_show_menu()` 延到动画结束再跑。
##
## ⚠️ 这里**刻意**不写 `DisplayServer` / `current_scene` 之类的判据 —— 全部收在
## `IntroMovie.should_play_now()` 那个纯函数里。判据散在 main 里就只剩"跑一遍看看有没有
## 动画"这一种验法；收在一处，才能对它逐条断言（见 `tests/suite_intro.gd`）。
##
## ⚠️ **同步**，不许改成 `call_deferred`：无头下 `_show_menu()` 仍必须在这一帧里跑完，
## 否则一批"实例化完主场景就断言菜单状态"的用例会集体变红。
func _maybe_play_intro() -> bool:
	if not IntroMovie.should_play_now(self):
		return false
	intro = IntroMovie.spawn(canvas)
	if intro == null:
		return false
	intro.finished.connect(_on_intro_finished)
	if not intro.begin():
		# 素材缺失 / 装不上解码器：**原样**退场，绝不留个黑屏卡住玩家。
		intro.dispose()
		intro = null
		return false
	# 动画期间没有菜单、没有 HUD、没有锁定目标。这几样本来都是 `_show_menu()` 干的活，
	# 但菜单要等动画结束才开 —— 先手动把"会被看见 / 会被按到"的那几样摆好。
	#
	# ⚠️ `close_menu()` 不只是为了"看不见"：`MainMenu.active` 默认是 `true`，
	# 不关掉的话玩家按下的那一发"跳过键"会被底下的菜单**再读一次**
	#（本工程反复踩的"同一个按键被两个界面各吃一次"）。
	menu.close_menu()
	hud.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	chase.set_target(null)
	return true


## 动画结束（自然播完 / 任意键跳过 —— 两条路都汇到 `IntroMovie.finished`）。
## 到这一步才真正进主菜单；`_show_menu()` 自己会把暂停清掉、把菜单打开并上锁，
## 所以"跳过的那一下按键"不会顺手把菜单推进一格。
func _on_intro_finished() -> void:
	if intro != null:
		intro.dispose()
		intro = null
	_show_menu()


## 开一局（**同步版**）。
##
## ⚠️ 这是**测试与探针的正式入口**（十几处 `m.call("_on_start_match", ...)`），
## 必须保持同步语义：返回时玩家/敌机/世界全部就位、阶段已到 FIGHT。
## 玩家实际走的菜单路径是 `_begin_match_loading()`（带读条）—— 两条路共用
## `_resolve_match()` + `_launch_match()`，差别只在"建图分不分阶段"。
##
## `map_id` / `mode` / `enemy_suit_id` 都带默认值：老的调用方（截图脚本、若干测试）
## 只传两台机的选择，那就按"对战模式 + 太平洋群岛 + 自动挑对手"处理 ——
## 少几处必须同步改的调用点。
func _on_start_match(suit_id: int, difficulty_level: int, map_id := -1, mode := -1,
		enemy_suit_id := -1) -> void:
	_resolve_match(suit_id, difficulty_level, map_id, mode, enemy_suit_id)
	_launch_match()


## 解析这一局的全部配置（机体/难度/模式/地图/时段），只动 `Game.*` 状态、不建任何节点。
## 同步入口与读条入口共用 —— 配置规则**只有这一份**（训练强制靶场、挑战地图跟脚本走、
## 靶场是训练专用图的回退守卫，全都在这里）。
func _resolve_match(suit_id: int, difficulty_level: int, map_id := -1, mode := -1,
		enemy_suit_id := -1) -> void:
	_set_paused(false)
	if SuitProfile.is_thunderbolt(suit_id) and mode not in [Game.MatchMode.LAN,Game.MatchMode.ENDLESS]:
		mode=Game.MatchMode.VERSUS
		enemy_suit_id=SuitProfile.thunderbolt_opponent(suit_id)
	elif SuitProfile.is_thunderbolt(enemy_suit_id) and not SuitProfile.is_thunderbolt(suit_id):
		enemy_suit_id=SuitProfile.Id.PENELOPE
	# Large MAs are reserved for orbital mirror/counterpart duels.
	var orbital_ma := [SuitProfile.Id.GP03D, SuitProfile.Id.NEUE_ZIEL]
	if suit_id in orbital_ma and mode not in [Game.MatchMode.LAN,Game.MatchMode.ENDLESS]:
		mode = Game.MatchMode.VERSUS
		map_id = MapDef.Id.LEO
		if not enemy_suit_id in orbital_ma:
			enemy_suit_id = SuitProfile.Id.NEUE_ZIEL if suit_id == SuitProfile.Id.GP03D else SuitProfile.Id.GP03D
	elif mode == Game.MatchMode.LAN and suit_id in orbital_ma:
		map_id = MapDef.Id.LEO
	elif enemy_suit_id in orbital_ma:
		enemy_suit_id = SuitProfile.Id.PENELOPE
	var axis_opponent := Net.remote_suit if mode == Game.MatchMode.LAN else enemy_suit_id
	if mode in [Game.MatchMode.VERSUS,Game.MatchMode.SQUAD,Game.MatchMode.LAN] and Net.requires_axis(suit_id,axis_opponent):
		map_id = MapDef.Id.AXIS
	if mode in [Game.MatchMode.VERSUS,Game.MatchMode.LAN] and Net.requires_colony(suit_id,axis_opponent):
		map_id=MapDef.Id.COLONY_RUINS
	Game.active_suit = suit_id
	Game.active_difficulty = Difficulty.make(difficulty_level)
	Game.match_mode = mode if mode >= 0 else Game.MatchMode.VERSUS
	Game.active_enemy_suit = enemy_suit_id
	Game.active_challenge = null
	# ★★ 轮 E：这一条路是**非剧情**入口 ⇒ 必须把"上一局残留的任务对象"摘掉。
	#
	# ⚠️ 为什么不是可有可无：`Game.active_mission` 只在 `_open_campaign()` 里被清过。
	# 剧情出击之后不经过剧情图、直接从菜单开一局普通遭遇战（或测试里连着起两个场景），
	# 上一关的 `Mission` 就**还挂在全局**。后果有两处，**都不报错**：
	#   ① 轮 E 的触发器会拿**上一关**的表继续求值 —— 它的 `all_done` / `elapsed>=`
	#      可能当场成立 ⇒ 一局遭遇战被上一关的"任务完成"判胜；
	#   ② `Game._evaluate_end()` 里 `active_mission != null` 那条分支
	#      （`win_on_clear`）也会照着上一关的语义走。
	# ⇒ 门禁放在**唯一的"新起一局"配置入口**上（剧情入口走
	# `_resolve_campaign_match()`，它随后自己把这两个字段写回去）。
	Game.active_mission = null
	_campaign_mission_id = ""
	# 训练模式**强制**用靶场那张图（用户要求"靶场选为新的沙漠地图"）——
	# 菜单里不会给训练模式显示地图页，但这里是真正的门禁：即使有别的入口绕进来，
	# 训练也只会落在靶场。
	if Game.match_mode == Game.MatchMode.TRAINING:
		Game.active_map = MapDef.training_range()
	elif Game.match_mode == Game.MatchMode.ENDLESS:
		# All twelve player suits share the same orbital escalation simulation.
		Game.active_map = MapDef.leo()
	elif Game.match_mode == Game.MatchMode.CHALLENGE:
		# 挑战的**地图由剧情脚本决定**（柯西打佩涅罗佩在太平洋、打阿利宙斯在艾尔斯岩）
		var enc := ChallengeScript.by_id(Game.active_challenge_id)
		if enc == null:
			enc = ChallengeScript.for_suit(suit_id)[0] if not ChallengeScript.for_suit(suit_id).is_empty() \
				else ChallengeScript.xi_vs_penelope()
		Game.active_challenge = enc
		Game.active_map = MapDef.by_id(enc.map_id)
	else:
		Game.active_map = MapDef.by_id(map_id if map_id >= 0 else MapDef.Id.PACIFIC)
	if Game.active_map.id == MapDef.Id.RANGE and Game.match_mode != Game.MatchMode.TRAINING:
		# 靶场是训练专用图，别的模式选到它时回退到群岛（防御性：菜单本来不会给这个选项）
		Game.active_map = MapDef.pacific()
	# 第四轮起固定夜战：时段由地图决定（三张图都是夜，只是雾/云的颜色不同）。
	Game.active_time_of_day = Game.active_map.time_of_day


## 起局：换图 → 关菜单 → 撒人 → 开打。**不解析配置**（那是 `_resolve_match` 的事），
## 所以调用前 `Game.active_map` 必须已经就位。
## [param skip_map] `true` ⇒ **不重建地图**。
##
## ★ 这是给发射段用的：那一局的 LEO 图已经在 `_swap_to_orbit()` 里建好了（玩家在舱里），
## 到这里再 `apply_map()` 一次就是"把刚建好的世界拆了重建" ——
## 而且那一顿正好落在"玩家刚出舱、第一次看见地球"的那一刻。
## 其余所有调用点不传（默认 `false`），行为与从前逐位相同。
## ⚠️ `start_now`（轮 57）：`false` ⇒ **撒完机体就停**，不起战斗
##（BGM 与"战斗开始"事件流水都不发生）。M04 的开场演出要的正是这个 ——
## 演出期间战场是"摆好了、但还没开打"的状态，演完由 `_finish_pod_strike()`
## 补上 `_start_fight()` ⇒ **BGM 只起一次、事件只记一条**。
func _launch_match(skip_map := false, start_now := true) -> void:
	if not skip_map:
		world.apply_map(Game.active_map)
	menu.visible = false
	# 菜单必须**整体停掉**，不只是隐藏：隐藏的 Control 照样会 _process，
	# 于是开局的这一下 Enter 会被它接着吃，直接跳过 INTRO。
	menu.close_menu()
	# 进战斗后藏起系统光标：锁定光标由 HUD 自己画
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	hud.visible = true
	# spawn_round clears cinematic state. The rocket's music belongs to
	# this same mission, so carry it across the ground-to-orbit handoff.
	var carry_launch_music := phase == Phase.LAUNCH and _strike_bgm_live
	spawn_round()
	if carry_launch_music: _strike_bgm_live = true
	# 启动音效**先放**，再起战斗 BGM —— 反过来的话启动音会盖在 BGM 上
	# （这是原来那版就定下的顺序，注释里写着"免得被启动音盖住"）。
	Audio.play_self("startup", -4.0)
	# ⚠️ 1.2 用户要求："删除每次游戏开始时候的按空格开始游戏"。
	# 所以**不再进 INTRO 等一个按键**：菜单一关就直接开打。
	# 原来那三行（`phase = Phase.INTRO` / `Game.set_phase(INTRO)` / `_phase_lockout`）
	# 存在的唯一目的就是"把菜单那一下 Enter 挡在 INTRO 之外"，
	# 现在没有 INTRO 可跳，锁也就不需要了 —— `_start_fight()` 不读任何输入。
	if start_now:
		_start_fight()


## 开一局（**读条版**，批 10 —— 玩家实际走的入口）。
##
## 菜单的 `start_match` 信号接到这里。协程流程：
##   ① 同步解析配置（`_resolve_match` —— 纯状态，一帧内完事）；
##   ② 开读条、**先让出一帧**把读条画面画出来（不 yield 的话第一个重阶段
##      还是冻在同一帧里，玩家只会看到黑屏卡一下）；
##   ③ 分阶段建图（`apply_map_staged`，阶段间广播进度给读条）；
##   ④ 起局（`_launch_match` —— 撒机体相对便宜，不再单独拆帧）；
##   ⑤ 等读条走满 + 最短显示时间 + 淡出。
##
## ⚠️ 测试不走这条路（它们直调同步的 `_on_start_match`），所以这条协程里
## 不需要兼容"调用方期待同步完成"的旧契约。
func _begin_match_loading(suit_id: int, difficulty_level: int, map_id := -1, mode := -1,
		enemy_suit_id := -1) -> void:
	# ★ 轮 C：剧情模式的"出击"**不直接开打** —— 菜单只是把玩家送到**战役图**，
	# 真正的出击发生在"选关 → 读简报 → 按确认"之后（`_sortie_campaign()`）。
	#
	# ⚠️ 拦在这里、而不是改菜单：菜单只管"发一局配置"，而"这一局去哪"归 main 管。
	# 而**难度不再由菜单问**（§6.1 的循环里没有难度页）：战役图上有难度那一行
	# （左 / 右切），出击时由 `_on_campaign_chosen()` 读进 `_campaign_level`。
	# ⇒ 这里传的是一个**有意的常量**，而**不是**菜单里那个玩家看不见的下标 ——
	#    "隐藏的难度"是本工程明列为必须修掉的一类（见 `MainMenu.step_labels()` 那条注释）。
	if _transition_busy: return
	var m := mode if mode >= 0 else Game.match_mode
	if m == Game.MatchMode.CHALLENGE:
		_open_campaign(Difficulty.Level.NORMAL)
		return
	_transition_busy = true
	_resolve_match(suit_id, difficulty_level, map_id, mode, enemy_suit_id)
	menu.close_menu()
	var map := Game.active_map
	loading.open("%s · %s" % [map.name_cn, "夜战" if map.time_of_day != null else ""])
	loading.advance(0.08, "进入战场……")
	# Retire the previous match before decoding the next loadout, avoiding two
	# generations of large meshes/textures in memory at the same time.
	Game.set_phase(Game.Phase.INTRO)
	_clear_match()
	await get_tree().process_frame
	# 世界建图进度 → 读条（0.08..0.9 区间；剩下的留给"部署机体"）
	world.build_stage.connect(_on_world_build_stage)
	await world.apply_map_staged(map)
	world.build_stage.disconnect(_on_world_build_stage)
	loading.advance(0.90, "读取机体与武装……")
	var warm_resources:=await preload("res://scripts/flight/loadout_warmup.gd").warm(self,
		preload("res://scripts/flight/loadout_warmup.gd").paths(_warmup_suit_ids()),
		func(done:int,total:int):loading.advance(.90+.015*float(done)/maxi(total,1),"读取机体与武装……"))
	loading.advance(0.92, "部署机体……")
	_launch_match(true,false)
	warm_resources.clear()
	units_root.process_mode = Node.PROCESS_MODE_DISABLED
	projectiles.process_mode = Node.PROCESS_MODE_DISABLED
	await loading.finish()
	units_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectiles.process_mode = Node.PROCESS_MODE_PAUSABLE
	_begin_sortie_or_fight()
	_transition_busy = false


## `WorldBuilder.build_stage` → 读条的进度转发（0..1 映射进 0.08..0.90）。
func _warmup_suit_ids()->Array:
	var ids:Array=[Game.active_suit]
	if Game.match_mode==Game.MatchMode.TRAINING:ids.append(SuitProfile.Id.GUSTAV00)
	elif Game.active_mission!=null:
		ids.append(Game.active_mission.enemy_suit)
		ids.append_array(Game.active_mission.enemy_roster)
		ids.append_array(Game.active_mission.ally_roster)
	elif Game.match_mode==Game.MatchMode.SQUAD:
		var side: int = Game.active_side if Game.active_side >= 0 else BattleFormation.Side.MAFTY
		for unit in BattleFormation.lineup(side, Game.active_suit):
			if not ids.has(unit.suit): ids.append(unit.suit)
		for unit in BattleFormation.lineup(BattleFormation.opposing(side), -1, Game.active_enemy_suit):
			if not ids.has(unit.suit): ids.append(unit.suit)
	elif Game.match_mode==Game.MatchMode.LAN:ids.append(Net.remote_suit)
	else:ids.append(Game.active_enemy_suit if Game.active_enemy_suit>=0 else versus_opponent_of(Game.active_suit))
	return ids

func _on_world_build_stage(frac: float, label: String) -> void:
	loading.advance(0.08 + clampf(frac, 0.0, 1.0) * 0.82, label)


# ============================================================ ★ 发射段（M03 演出）
#
## 这一段做什么（老板原话）：
## > 「玩家需要操控火箭从太平洋发射到近地轨道，中间需要做无缝切换房间，
## >  可以在发射过程中做切换，通过云层来挡住玩家视线，然后在后台偷偷加载切换房间，
## >  然后切换到近地轨道中离柯西运输仓 200 km 的地方。」
##
## 拆成四件事，各自的落点：
## | 事 | 落点 |
## |---|---|
## | 从太平洋发射 | `WorldBuilder._build_launch_clouds()`（发射点上空的云垛）+ `_build_launch_splash()`（出水特效），**只在太平洋图建** |
## | 玩家操控 | `RocketBody`（真实力积分 + 制导跟踪） |
## | 舱内表现 | ★ **`hud.gd` 的全周天座舱那一层**（刻度导轨 + 仪表台 + 取景框），读数走 `LaunchScript.dash_readout()` —— 老板 2026-09-30：「**你驾驶舱做的好丑，直接用全周天驾驶舱的代码吧**」（第一版那套 3D 舱已删） |
## | 换图那一下怎么盖住 | ★ **`_swap_to_orbit()`：把玩家按进座舱**（`_swap_eye_lock`）—— 那一刻舱内 UI 照画，外面空不空无所谓（老板：「**不需要云层了**」） |
## | 到 200 km | `LaunchScript.arrival_pos()`（纯函数，测试直接钉） |
##
## 时间线（`LaunchScript` 头注里有完整版）：
## ```
##   倒计时 8 s   →  仪表台报「点火倒计时」，火箭**浸在海里**（箭底在 −34 m，见 `PAD_DRAFT`）
##    0 .. 37 s   大气层内全程（可见：出水泡沫环与烟雾 / 海面远去 / 云垛铺开 /
##                焰长从 46 m 长到 262 m —— 老板那张参考图就在这一段的 8~25 km 处）
##      ~6 s      烟起满（老板：「烟雾要在发射后 4s 再渐变生成」，见 `SeaSplash.SMOKE_DELAY`）
##   ~37.6 s      **越过卡门线**（`REVEAL_ALT` 100 km）⇒ 锁座舱档、换图
##   ~39.5 s      LEO 图建完（实测 ~1.9 s）
##   60 s         抵达（离运输仓 200 km）→ 交还给正常战斗流程
## ```
##
## ## ⚠️ 两个容器
## 火箭**不挂 `units_root`**（见 `launch_root` 的声明：`_clear_match()` 会清空它）。
## 换图期间**没有任何东西挂在会被清掉的地形根上** —— 这一点从前靠"幕布挂相机下"
## 保证；幕布删掉之后靠的是**舱内 UI 是屏幕空间的、根本不在 3D 树里**。


## 起一段发射演出。**调用前必须已经把太平洋图建好**（含发射点上空的云垛与出水特效）。
func _begin_launch() -> void:
	_start_launch_music()
	phase = Phase.LAUNCH
	Game.set_phase(Game.Phase.INTRO)
	_phase_lockout = PHASE_LOCKOUT
	_restart_held = false
	# ★★ 老板 2026-09-30：「**正常驾驶模式的UI也使用啊，比如燃料和雷达啊高度和时速
	# 这些显示器，不需要屏幕左上角那么多白色文字了**」。
	# ⇒ 这一段不改 `hud.visible = false` 了：**战斗 HUD 换成"只画全周天座舱这一层"**
	#（`cockpit_only`），读数由 `_sync_cockpit_hud()` 每帧塞。
	# 第一版是 `hud.visible = false` + 一个摆了 7 行白字的 `Label`
	#（`_build_launch_ui()`，已删）—— 那 7 行白字就是老板点名要去掉的东西。
	hud.visible = true
	hud.cockpit_only = true
	hud.cockpit_eye = false
	hud.cockpit_readout = {}
	hud.cockpit_basis = Basis()
	hud.launch_warn = {}
	_story_launch_skipping=false
	_orbit_swap_started = false
	_orbit_swap_done = false
	_swap_eye_lock = false
	# ★ 眼位档的初值从玩家的偏好取一次（之后 F1 只翻本段自己那一位）。
	_launch_eye_cockpit = Settings.first_person
	_launch_countdown = LaunchScript.COUNTDOWN
	# ★ 这一局的出生点由发射段的抵达点给（见 `spawn_round()`）
	_spawn_from_launch = true

	rocket = RocketBody.new()
	rocket.name = "MaftyRocket"
	rocket.process_mode = Node.PROCESS_MODE_PAUSABLE
	rocket.configure(LaunchScript.ASCENT_SPAN)
	launch_root.add_child(rocket)
	# ⚠️ 出生点 = `LaunchScript` 给的**吃水线**，**不是另写一个数**：
	# 出水特效（`WorldBuilder._build_launch_splash()`）也是照同一个坐标建的，
	# 两边一旦分家，泡沫环就会长在箭体旁边几十米 —— 而且不报任何错。
	rocket.place_at_launch(LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))
	_attach_rocket_model()
	# ★ 火焰与拖尾（老板：「火箭升空的时候都没有大型火焰拖尾」）。
	# 挂在箭体局部 `z = 0`（喷口平面）⇒ 箭体直立时它朝世界 −Y（**朝下**）。
	launch_flame = RocketFlame.new()
	rocket.add_child(launch_flame)

	chase.set_target(rocket)
	# ★ 发射段机位与战斗机位**不是同一个**：默认机位在箭底下方 53 m、火箭吃水 34 m
	# ⇒ 相机直接落到海面下（实测 −87 m），画面里只剩水下的黑。见 `set_launch_view()`。
	chase.set_launch_view(true)
	# ★★ 相机从**这一帧起**改由 `_tick_launch()` 在渲染帧里驱动（见 `step_now()` 头注）。
	# ⚠️ 必须摆在 `set_launch_view(true)` **之后**：那一行自己会把相机硬落位一次，
	# 而它读的 `_desired_position()` 只依赖 target，两件事互不干扰；
	# 顺序反过来（先外部驱动、后 set_launch_view）会在换档那一瞬留一帧旧机位。
	chase.externally_stepped = true

	# 第一帧就把仪表台填上（否则从"倒计时第一秒"到"下一次 `_tick_launch`"之间
	# 会有一帧空仪表台）。
	_sync_cockpit_hud()
	Audio.play_ui("ui_confirm")


## Start the mission track once; _launch_match preserves it across spawn_round.
func _start_launch_music() -> void:
	_start_mission_music()


## Mission music starts with the sortie and keeps its current playback at handoff.
func _start_mission_music() -> void:
	_strike_bgm_live = false
	if Game.active_mission == null or Game.active_mission.bgm == "": return
	Audio.set_story_mode(Game.match_mode == Game.MatchMode.CHALLENGE)
	Audio.lock_battle_track(Game.active_mission.bgm)
	Audio.request_battle_open(Game.active_mission.bgm)
	Audio.play_bgm(Audio.Bgm.BATTLE)
	_strike_bgm_live = true


## 载入并挂上火箭资产。
##
## ## ⚠️ 为什么是 `load()` 而不是 `preload()`
## `preload` 是**编译期**解析：`main.gd` 一被解析就把这份 39.9 MB / 890 个文件的
## 资产拉起来 —— 而 `main.gd` 是**开机就加载**的脚本（主菜单还没出来就先读 40 MB），
## 而这段演出在菜单之外的每一条路径上**根本不会发生**。
## `load()` 是运行时解析 ⇒ 只有真进发射段才付这份代价。
##
## ⚠️ 而且**不要**在这里做"已经载过就不载"的判断：`ResourceLoader` 自己会缓存，
## 第二次 `load()` 是命中缓存（重开一关不会重复读盘）。加一层自己的缓存反而会
## 在"资产被重新导入"之后拿着一份旧引用 —— 那是另一个静默故障。
func _attach_rocket_model() -> void:
	if rocket == null or not is_instance_valid(rocket):
		return
	var ps := load(ROCKET_MODEL) as PackedScene
	if ps == null:
		# ⚠️ **必须喊出来**：静默失败的表现是"这一局只有一枚看不见的箭" ——
		# 玩家看到的是摄像机对着空气飞，而日志里一切正常。
		push_warning("火箭资产载不到（%s）⇒ 这一局只有一枚看不见的箭" % ROCKET_MODEL)
		return
	rocket.set_model(ps.instantiate())


## ★★ 发射段的**舱内表现**：把火箭的当前读数喂给 HUD 的全周天仪表台。
##
## ## 这一段为什么是这个形状（老板两条指令合起来的结果）
## 第一版：发射段 `hud.visible = false`，另建**一个 3D 舱**（含一块自绘的表盘
## shader）+ **一个 7 行白字的 `Label`**（摆在屏幕左上角 `(36, 28)`）。
##（那两个文件已**从工程删除**、归档在 relay workspace 的
## `_archive_rocket_cockpit_20260930/` —— 套件里有一条断言扫本文件"不许再出现
## 那两个类名"，连注释也算。）
## 老板 2026-09-30 连着两条否掉了它：
## > 「**你驾驶舱做的好丑，直接用全周天驾驶舱的代码吧**」
## > 「**正常驾驶模式的UI也使用啊，比如燃料和雷达啊高度和时速这些显示器，
## >  不需要屏幕左上角那么多白色文字了**」
##
## ⇒ 现在的形状：HUD 打开、切到 `cockpit_only`（只画全周天那一层），
## 读数由**纯函数** `LaunchScript.dash_readout()` 造，每帧塞进 `hud.cockpit_readout`。
## 于是"仪表台 / 刻度导轨 / 取景框"这三样**一行几何都不用改**，
## 发射段与机体第一人称**共用同一份代码**。
##
## ## 为什么在这里推、而不是让 HUD 自己去读 `rocket`
## 与 `SeaSplash.update()` / 第一版那个 3D 舱的 `update()` 同一条规矩：
## **显式调用、显式传参** ⇒ 单测能按固定数据复现，不必造一整个 `main`。
## 而 HUD 那边只认归一化读数，**不认识 `RocketBody`**（见 `hud.cockpit_readout`）。
##
## ## 为什么每帧都要写 `cockpit_eye`
## 它决定"导轨与取景框画不画"，而眼位档**可以被 `_swap_eye_lock` 临时锁住**
## （那一刻 `Settings.first_person` 还是 false）—— 只写一次的话，
## 换图那 1.5 s 里导轨会消失，只剩一块仪表台浮在空屏上。
func _sync_cockpit_hud() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	hud.cockpit_eye = chase.launch_view() \
		and chase.launch_eye() == ChaseCamera.LaunchEye.COCKPIT
	if rocket == null or not is_instance_valid(rocket):
		hud.cockpit_readout = {}
		hud.cockpit_basis = Basis()
		hud.launch_warn = {}
		return
	var left_s := (1.0 - clampf(rocket.u, 0.0, 1.0)) * LaunchScript.ASCENT_SPAN
	# ★ 俯仰 / 垂直速度 / 航向是给**高度块**那三行用的（老板要"正常驾驶机体的
	# 高度指示器"拿过来）—— 它们与"高度"是同一族读数，一起在这里取，
	# 免得 HUD 反过来去认 `RocketBody`。
	#
	# ⚠️ 航向取机头 `−basis.z`，**不是 `velocity` 的方向**：上升段有一段是
	# 斜着爬的，两者差着一个迎角；HUD 上 `HDG` 那一行报的是"机头指哪"。
	var hdg := fposmod(rad_to_deg(atan2(-rocket.basis.z.x, rocket.basis.z.z)), 360.0)
	hud.cockpit_readout = LaunchScript.dash_readout(rocket.global_position.y,
		rocket.speed(), rocket.base_throttle, rocket.fuel_fraction(),
		rocket.leg_name(), left_s, _launch_countdown,
		rocket.pitch_deg(), rocket.velocity.y, hdg)
	# ★★ 姿态源（姿态仪用）。火箭的 `basis` **直接喂**给 `HUD.attitude_readout()` ——
	# 那个函数是"一个 Basis 进、地平线偏移 + 滚转出"的**纯函数**，
	# 所以姿态仪那段几何一行都不用为发射段另写一份。
	# ⚠️ 不是 `global_transform.basis` 与 `basis` 混用：`rocket.basis` 就是
	# `global_transform.basis`（`Node3D` 上的同名属性），上面 `hdg` 用的是同一个。
	hud.cockpit_basis = rocket.global_transform.basis
	# ★★ 告警的**原始量**（`_tick_launch_warnings()` 拿它算状态）。三个数全是火箭自己的：
	#   · `alt` 取 `global_position.y` —— 它**就是箭底高度**（见 `place_at_launch()`）
	#   · `vs`  取 `velocity.y` —— 真实世界速度的竖直分量（向上为正）
	#   · `g`   取 `LaunchScript.accel_g_estimate(u)` —— 与制导前馈**同一个真源**
	# ⚠️ 倒计时期间**喂空字典**（不喂三个 0）：那时箭一动不动，
	# `pull_up_clearance(0, 0)` 恰好等于 0 —— 正好卡在 `< 0` 的门限上，
	# 会让 PULL UP 在倒计时里随浮点末位偶发地闪一下。空字典 = 明确地"这一帧没有告警"。
	hud.launch_warn = {} if _launch_countdown > 0.0 else {
		"alt": rocket.global_position.y,
		"vs": rocket.velocity.y,
		"g": LaunchScript.accel_g_estimate(rocket.u),
	}


## 发射段的三根杆：`(俯仰, 偏航, 节流)`，每根都在 −1..1。
##
## ## ⚠️ 符号不是猜的，是**探针量出来的**（`tools/_launch_ctrl_probe.gd`）
## 2026-09-30 晚第四次改：追尾机位**水平转到对侧**（`LAUNCH_OFFSET.y` 由 `+62` 变 `−62`，
## 完整头注在 `chase_camera.gd` 那一段）。机位绕箭体轴转了 180° ⇒ 相机自己的 `right` 轴
##（由 `Basis.looking_at()` 定）**整体换向** ⇒ 屏幕上的"左右"与"上下"两个通道**同时镜像**。
##
## 量法不是"看像素"，是**把机头单位向量的变化量点乘相机的两根轴**、再减掉零输入基线：
## ```
##                    offset.y = +62        offset.y = −62（现在这一档）
##   pitch_in = +1     sy = +0.0063（上）    sy = −0.0069（下）
##   yaw_in   = +1     sx = −0.0171（左）    sx = +0.0171（右）
## ```
##（第一版量屏幕投影位移是**假读数**：箭在 90 帧里一直飞，位移里绝大部分是位置不是方向。）
##   · 俯仰：新机位下 `pitch_nose_up` 把机头画到**屏幕下方** ⇒ 取**负**（下面把两个 action 对调）。
##   · 偏航：新机位下 `yaw_left` 把机头画到**屏幕右方** ⇒ 取**负**（同上）。
##   · 节流那一根**与机位无关** —— 它进的是箭体自身（`trim` / `base_throttle`），不经过相机。
##
## ⚠️⚠️ **机位与符号是一对，不能只改一半**：改机位不改符号 = 玩家按左键往右转，
## 而它**不报任何错**；改符号不改机位 = 同样反。`suite_rocket_launch` 里有一条断言
## 把"机位在箭体哪一侧"与"这两个符号"钉在一起（见 `_launch_axis_signs`）。
func _launch_axis() -> Vector3:
	return Vector3(
		Input.get_action_strength("pitch_nose_down") - Input.get_action_strength("pitch_nose_up"),
		Input.get_action_strength("yaw_right") - Input.get_action_strength("yaw_left"),
		Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down"))


## ★★ 换图（太平洋 → 近地轨道）：**不遮幕布**，靠"把玩家按进座舱"盖住这一下。
##
## ## 老板 2026-09-30 定的做法
## > 「**不需要云层了**」+「**把玩家视角跳到座舱内，然后星空盒都是同一片的情况下
## > 可以直接换**」
##
## ## 为什么这样能成立（而不是"随便挡一下"）
## ① **座舱壳体不透光**：眼位在箭顶之上，舱体（顶棚 / 侧壁 / 底板 / 后壁）全是
##    不透明的盒子 ⇒ 世界被卸掉那几帧，玩家视野里是仪表盘和舱壁，不是空世界。
##    视线的**上半**仍能透过风挡看到天 —— 而两图的天空是**同一个 `_sky_mat`**，
##    只有 `star_amount` 这类参数不同（夜 0.22 / 真空 1.0）⇒ 差别是"星星多了"，
##    不是"背景被换掉了"。
## ② **位置连续**：换图不动 `rocket.global_position`、也不动相机 ⇒
##    放锁那一刻玩家看到的还是同一枚箭、同一个方向。
##
## ## ⚠️ 三个必须写对的点
## ① `_swap_eye_lock` 要**先闩上、后卸世界**：`_apply_camera_settings()` 是每帧跑的，
##    同帧内先卸图再换档的话，玩家会有**一帧追尾视角看到空世界**。
## ② **建图全程不放锁**（整个 `await` 期间锁着），否则玩家一按 F1 就能看见没有地形的世界。
## ③ 结束时**清锁**。不清的话玩家被永久锁在舱里，看起来像"按键失灵"。
func _swap_to_orbit() -> void:
	_swap_eye_lock = true
	# 让锁生效两帧再卸世界（见上面第 ① 条）。
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	# `apply_map_staged()` 是**先卸后建**的（阶段之间 `await` 一帧）——
	# 那几帧世界里什么都没有，正是要靠"人坐在舱里"盖住的那一段。
	# ⚠️ 舱内表现在是**屏幕空间的**（HUD 的全周天那一层），它不在 3D 树里、
	# 不随地图被 free ⇒ 那几帧照画不误。
	await world.apply_map_staged(MapDef.leo())
	_orbit_swap_done = true
	if rocket != null and is_instance_valid(rocket):
		# 阶段播报从"穿云"切到真空段（`RocketBody.leg_for()` 读的就是这一位）。
		rocket.room_swapped = true
	print("== 换图（太平洋 → 近地轨道）：耗时 %d ms（座舱档全程锁着，舱内 UI 照画）"
		% int(Time.get_ticks_msec() - t0))
	_swap_eye_lock = false


## 每帧推进发射段。**由 `_process()` 在 `Phase.LAUNCH` 下显式调用**。
##
## ⚠️ 倒计时期间**不调 `rocket.step()`**：那会让 `u` 从第 0 秒就开始推进
##（= 倒计时还没数完火箭就起飞了）。倒计时就是倒计时，箭浸在水里一动不动。
##
## ## 仪表读数为什么按"眼位档"给、而不是按 `Settings.first_person`
## `chase.launch_eye()` 是**相机实际处在哪一档**的答案，而它才是"玩家此刻看见什么"
## 的直接原因（换图那 1.5 s 它被 `_swap_eye_lock` 锁在座舱档，而设置一位没动）。
## 读设置的话，那一秒半里导轨与取景框会消失，只剩一块仪表台浮在空屏上。
func _tick_launch(delta: float) -> void:
	if _story_launch_skipping:
		if _orbit_swap_done:
			_story_launch_skipping=false;_finish_launch()
		return
	if rocket == null or not is_instance_valid(rocket):
		_step_launch_cam(delta)
		return
	# ★ 舱内表现（全周天仪表台的读数）。**摆在倒计时早退之前**：
	# 倒计时那 8 s 玩家就在舱里坐着，仪表必须已经在那儿报「点火倒计时」
	#（否则是一屏没有任何座舱痕迹的画面 + 火箭静立，看起来像"这段没做"）。
	# 每帧**只喂一次**（两个分支各一次）：多喂不会更准，只会让"谁写的这一帧"变成两处。
	if _launch_countdown > 0.0:
		_launch_countdown = maxf(_launch_countdown - delta, 0.0)
		_sync_cockpit_hud()
		_step_launch_cam(delta)
		if _launch_countdown <= 0.0:
			# 点火那一下给一记低音（与 `_launch_match()` 里那记是同一个音效，
			# 但这里离"开打"还有 60 s，不会撞在一起）。
			Audio.play_self("startup", -2.0)
			# ★ 出水特效与箭体**同一帧起跑** —— 点火那一帧才是"水被顶开"的第 0 帧。
			# 放这儿而不是 `_begin_launch()`：倒计时 8 s 里箭是静的，水也该是静的。
			if world != null and world.launch_splash != null:
				world.launch_splash.begin()
		return
	var ax := _launch_axis()
	rocket.step(delta, ax.x, ax.y, ax.z)
	# ★ 火焰与拖尾：**必须摆在 `step()` 之后** —— 它读的 `base_throttle`
	# 与 `global_position` 就是这一步算出来的。摆在前面会整整晚一帧
	#（点火那一帧焰还没起来，而"点火"正是这一段最该给反馈的一帧）。
	if launch_flame != null and is_instance_valid(launch_flame):
		launch_flame.update(rocket)
	# ★ 出水特效跟着**箭底**走：`rocket.global_position.y` 就是箭底（见 `place_at_launch()`）。
	# 环扩多大 / 柱还举不举着全由它自己按这个高度推，这里只喂读数。
	# ⚠️ 两个 null 判都不能少：换图之后 `launch_splash` 会随太平洋图一起被 free。
	if world != null and world.launch_splash != null:
		world.launch_splash.update(rocket.global_position.y, delta)
	# ★★ 越过**卡门线**换图。**没有幕布**（老板 2026-09-30：「不需要云层了」）——
	# 换图那几帧靠 `_swap_to_orbit()` 把玩家按进座舱来盖住，见那个函数的头注。
	#
	# ⚠️⚠️ 触发高度 **`REVEAL_ALT`(100 km)，不是 `CLOUD_BASE_ALT`(2 800 m)**。
	# 原来是"进云就换"，那是**幕布时代**的约束（换图窗口必须藏在云里）。
	# 幕布删掉、遮挡物换成座舱之后那条约束就消失了，而它留下的代价极大：
	# 换图点钉在 2 800 m ⇒ 从那儿到 550 km（**99.5% 的上升**）全在轨道图里飞,
	# 没有夜海、没有云垛、天不会变黑 ⇒ 老板那张参考图的构图
	#（细长箭体 + 极长橙白尾焰 + 被烤亮的云底 + 深夜星空）
	# **在真实流程里一帧都拍不出来**（焰长是随高度长的，2 800 m 处只有 57 m）。
	# ⇒ 搬到卡门线：与"出大气层"这个叙事节点重合，那一刻天空本来就是黑的，
	# 而两张图**共用同一份 `_sky_mat`** ⇒ 星星逐位相同，换图本来就看不见。
	# ★★ 相机在**这一刻**落位：本帧的 `rocket.step()` / 火焰 / 出水都已经算完，
	# 于是"算 want 用的 target 变换"与"这一帧画出去的 target 变换"逐位相同
	# ⇒ 相机与火箭的相对位移恒为 0（见 `ChaseCamera.step_now()` 头注）。
	# ⚠️ 摆在 `_swap_to_orbit()` **之前**：那个分支会 `await` 好几帧，
	# 挂在它后面的话换图那一帧的机位还是旧的。
	_step_launch_cam(delta)
	if not _orbit_swap_started and rocket.global_position.y >= LaunchScript.REVEAL_ALT:
		_orbit_swap_started = true
		_swap_to_orbit()
	_sync_cockpit_hud()
	# ---- 交还操控：换图建完 **且** 已滑行到抵达点 ----
	if _orbit_swap_done and rocket.u >= 1.0:
		_finish_launch()


## 发射段的相机：**在渲染帧里**走一步。
##
## ⚠️ 这么做**只因为**发射段的相机与火箭必须在同一个钟上 —— 完整论证在
## `ChaseCamera.step_now()` 的头注里（"抽搐"的根因）。
## 战斗段一个字没动：那边 `externally_stepped` 恒为假，相机照旧走 `_physics_process`。
func _step_launch_cam(delta: float) -> void:
	if chase != null and is_instance_valid(chase):
		chase.step_now(delta)


## 发射段结束：把操控交还给正常的战斗流程。
##
## 运载器**留在原地**不删 —— 玩家接下来要飞的那 200 km 需要一个"我从哪儿来的"锚点，
## 而且它本来就是老板要"加入游戏"的那件东西。
func _skip_story_launch()->void:
	if phase!=Phase.LAUNCH or _story_launch_skipping:return
	_story_launch_skipping=true;_launch_countdown=0.0
	if is_instance_valid(rocket):rocket.u=1.0
	if not _orbit_swap_started:
		_orbit_swap_started=true;_swap_to_orbit()

func _finish_launch() -> void:
	# ⚠️ 收尾**必须清锁**：万一在某条异常路径上（换图取消 / 测试直接调本函数）
	# 锁还闩着，玩家就会被永久按在座舱档里，而它看起来像"F1 失灵"。
	_swap_eye_lock = false
	# ★ 把相机交回物理钟（`set_launch_view(false)` 里也会放一次，两处都放的理由见那儿）。
	if chase != null and is_instance_valid(chase):
		chase.externally_stepped = false
	if rocket != null and is_instance_valid(rocket):
		# 断电：关制导、推力归零、速度清零 ⇒ 它就停在那儿当一枚静止的大家伙。
		# （它没有 `_process`，不再被 `step()` 驱动，所以这就是"停住"的全部条件。）
		rocket.assist = false
		rocket.base_throttle = 0.0
		rocket.velocity = Vector3.ZERO
		# ★ 焰**必须显式熄掉**：`_finish_launch()` 之后没人再调 `RocketFlame.update()`
		#（火箭不再被 `step()` 驱动）⇒ 焰会冻在"抵达那一刻的满推力"上，
		# 于是箭尾永远挂着一根火柱。见 `RocketFlame.extinguish()` 的注释。
		if launch_flame != null and is_instance_valid(launch_flame):
			launch_flame.extinguish()
	# ★ 收掉舱内表现：把 HUD 从"只画全周天那一层"切回战斗 HUD。
	#
	# ⚠️ 这一步**必须做**，而且必须在 `_launch_match()` **之前**：那一函数会
	# `hud.visible = true` 并撒机体，若 `cockpit_only` 还开着，玩家会拿到一屏
	# 只有仪表台、没有准星/血条/目标框的界面 —— 而它看起来像"HUD 坏了"。
	if hud != null and is_instance_valid(hud):
		hud.cockpit_only = false
		hud.cockpit_eye = false
		hud.cockpit_readout = {}
		hud.cockpit_basis = Basis()
		hud.launch_warn = {}
	# ⚠️ 这里其实**通常已经是 null 了** —— 出水特效挂在太平洋图的 `_terrain_root` 下，
	# 换图（`_swap_to_orbit()` 干的那件事）已经把它连根 free 掉。
	# 留着这一行是为了"没换图也走到了 `_finish_launch()`"那条路径（测试 / 将来改动）
	# 不会把环和水柱永远挂在海面上。
	if world != null and world.launch_splash != null:
		world.launch_splash.end()
	# ⚠️ `true` = **不再重建地图**：LEO 已经在幕布后面建好了。
	# 不传这一位的话会在抵达的下一帧把刚建好的世界整个拆了重建
	#（屏幕上一顿，而且正好落在"刚揭开、最好看"的那一刻）。
	_launch_match(true)


# ============================================================ ★ 轮 57：M04 开场演出
#
## 「重力这一关我说要先做**佩涅罗佩使用光束大炮攻击柯西运输仓**，
##  然后再是玩家操控柯西和佩涅罗佩对决。」（老板 2026-09-30）
##
## ## 与发射段（`_begin_launch()`）的关系：**同一种形态，不同的形状**
## | | 发射段 M03 | 开场演出 M04 |
## |---|---|---|
## | 阶段 | `Phase.LAUNCH` | `Phase.POD_STRIKE` |
## | 地图 | **换图**（太平洋 → LEO） | **不换图**（起点就是战场） |
## | 玩家 | 操控火箭（`RocketBody`） | **不能动**（`controls_enabled = false`） |
## | 相机 | `chase.set_target(rocket)` + 外部驱动 | 外部驱动（`cam_pos`/`cam_look` 纯函数） |
## | 演完 | `_launch_match(true)` | `_start_fight()` |
## | 数据 | `LaunchScript` | `PodStrikeScript` |
##
## ## ⚠️ 它是**演出**，不是玩法（老板 2026-09-30 三条口径）
##   · 运输仓**不掉血**（保持"可显示不可被攻击"，见 `WorldBuilder._build_transport_pod()`）；
##   · 第一拍**玩家不能操控**（"先看过场"）；
##   · 运输仓被打爆**不算失败**（它没有判定对象，所以这条**刻意不做**）。
## 表现上的"命中"= `BeamCannon` 的 `dps = 0.0` 的光束柱照在仓上 —— 它照画不误、
## 一点都不伤人（`_apply_damage()` 在 `amount <= 0` 时直接 return）。这是"只好看、不结算"
## 最干净的做法：**复用真武器，只把伤害调成 0**，而不是另写一套只有视觉的假柱。


## 起一段「佩涅罗佩轰运输仓」的开场演出。**调用前地图必须已经建好**
##（`_sortie_campaign()` 的通用路径已经建完了）。
func _start_pod_strike_music() -> void:
	Audio.set_story_mode(Game.match_mode == Game.MatchMode.CHALLENGE)
	Audio.lock_battle_track(PodStrike.BGM)
	Audio.request_battle_open(PodStrike.BGM)
	Audio.play_bgm(Audio.Bgm.BATTLE)
	# Do not carry the cinematic track through _start_fight().
	_strike_bgm_live = false


func _begin_pod_strike() -> void:
	# ① 把这一局原样摆好（撒玩家与佩涅罗佩），但**不起战斗**。
	#    ⇒ 位置与演出末态的交接处不会有任何跳变：演出只改"镜头看哪儿"
	#      与"佩涅罗佩此刻在哪儿"，别的全是 `spawn_round()` 的正常结果。
	_launch_match(true, false)
	phase = Phase.POD_STRIKE
	Game.set_phase(Game.Phase.INTRO)
	_phase_lockout = PHASE_LOCKOUT
	_restart_held = false
	# ② 玩家**不能动**（老板 2026-09-30：「不能，先看过场」）。
	#    `spawn_round()` 本来就把它关着，这里再钉一次 —— 因为 `_launch_match()`
	#    中间的路径将来若有人加了一句"开操控"，演出就会静默变成"能边看边打"。
	if player != null and is_instance_valid(player):
		player.controls_enabled = false
		player.velocity = Vector3.ZERO
	# ③ 接管佩涅罗佩（`wave_units` 就是本关的敌机表；M04 只有一台）。
	_strike_foe = wave_units[0] if not wave_units.is_empty() else null
	if _strike_foe != null and is_instance_valid(_strike_foe):
		_strike_foe.set_scripted(true)
	# ④ 相机交给本函数的外部驱动（`_physics_process` 那条路整段让路）。
	_strike_t = 0.0
	_strike_beam = null
	_strike_cut = false
	# ⑤ 取运输仓**本体**（起火之后要挪它）。
	#    ⚠️ `_build_transport_pod()` 只把那个 `Marker3D` 加进 `POD_TAG_GROUP`，
	#    **本体不在任何组里**（老板定的"可显示不可被攻击"）⇒ 从信标锚点取它的兄弟。
	#    两者**同级**（都挂在 `_terrain_root` 下），名字见 `_build_transport_pod()`。
	_strike_pod = null
	_strike_pod_tag = null
	_strike_pod_home = Vector3.ZERO
	var tag := get_tree().get_first_node_in_group(WorldBuilder.POD_TAG_GROUP) as Node3D
	if tag != null and is_instance_valid(tag):
		_strike_pod_tag = tag
		if tag.get_parent() != null:
			_strike_pod = tag.get_parent().get_node_or_null("PodBody") as Node3D
	if _strike_pod != null:
		# 本体与信标**同级**且都建在同一个 `at` 上 ⇒ 同一个 home 够用。
		_strike_pod_home = _strike_pod.position
	# M04 uses XI for the cinematic, then the mission track on battle handoff.
	_start_pod_strike_music()
	chase.externally_stepped = true
	Audio.play_self("startup", -4.0)
	if is_instance_valid(_strike_director): _strike_director.free()
	_strike_director=preload("res://scripts/cinematics/pod_strike_director.gd").new()
	_strike_director.setup(self,_strike_pod,_strike_foe)
	add_child(_strike_director)
	_strike_director.step(0.0,0.0)


## 演出每帧一步。**只在 `Phase.POD_STRIKE` 下被 `_process` 调用**
##（与 `_tick_launch()` 同一条路："显式驱动的状态"，好让整段按固定 dt 复现）。
func _tick_pod_strike(delta: float) -> void:
	if is_instance_valid(_strike_director):
		_strike_t = _strike_director.advance_timeline(_strike_t,delta)
		_strike_director.step(_strike_t,delta)
	else:
		_strike_t += delta
	if PodStrike.done(_strike_t):
		_finish_pod_strike()


## 演出收尾：收掉光束、把 AI 放回去、交还操控。
##
## ⚠️ 顺序有讲究：`_start_fight()` 必须**最后**调 —— 它把 `phase` 推进 FIGHT，
## 而 `_tick_pod_strike()` 是"只在 `Phase.POD_STRIKE` 下跑"的，谁先谁后会决定
## 这一帧还要不要再演一步（多演一步 = 镜头从玩家背后被拽回运输仓）。
func _finish_pod_strike() -> void:
	if is_instance_valid(_strike_director):
		_strike_director.cleanup()
		_strike_director.queue_free()
	_strike_director=null
	if _strike_beam != null and is_instance_valid(_strike_beam):
		_strike_beam.queue_free()
	_strike_beam = null
	if _strike_foe != null and is_instance_valid(_strike_foe):
		# 放开 AI：它从"刚轰完运输仓"的姿态接着飞（位置不重置 ——
		# 重置会瞬移，而它现在的位置本来就是合理的战场位置）。
		_strike_foe.set_scripted(false)
	_strike_foe = null
	chase.externally_stepped = false
	# ★ 2026-10-01：把演出期间的**长焦**还回去。
	#
	# ⚠️ 不还的症状是**整局战斗都是长焦**，而它**不报错**：
	# 演出期间 `externally_stepped = true` 让 `_update_fov()` 一次都不跑（正是长焦
	# 能生效的前提），一旦它回到 false，`_physics_process()` 会重新接管——
	# 但那一帧之前玩家已经看见一个被压扁的世界。显式写一次，行为不靠时序巧合。
	chase.fov = chase.base_fov
	_strike_t = 0.0
	# 交还操控。`_start_fight()` 自己是幂等的（`phase == FIGHT` 就早退），
	# 而此刻 `phase` 还是 `POD_STRIKE` ⇒ 它会真的跑一遍。
	_start_fight()


## 摆演出机位（外部驱动）。**切镜那一段（`T_CUT` 之后）交给正常的追尾相机**。
func _push_strike_camera() -> void:
	if is_instance_valid(_strike_director):
		_strike_director.step(_strike_t,0.0)


# ============================================================ ★ 轮 C：剧情模式（出击循环）
#
## 这一节是 DESIGN §3.2 那条时间线在代码里的落点：
##
## ```
## 战役图 →🎬P 序章 → 简报 →🎬B 任务前 → 标题卡 → 战斗 → 结算（军资 +N / 重来）→🎬D 任务后 → 回战役图
## ```
##
## ⚠️ **轮 C 只做到这里**：目标系统与触发器是**轮 D/E**、完整四槽位播片是**轮 G**、
## 改装与商店是**轮 C2**。所以 P/B/D 三个钩子**都接了**，而 `mid` 槽
##（战斗中暂停播片）**一个调用点都没有** —— 那是轮 D 的 `Trigger` 才有的东西。
##
## ⚠️ 这一节**只碰剧情模式**：四种现有模式（VERSUS / SQUAD / TRAINING / LAN）
## 走的还是原来那两条路（`_on_start_match` / `_begin_match_loading`），一行都不变。
## 判据是 `Game.sally_result`（空字典 = 非剧情模式）—— 结算页那行军资与
## "R 重来"提示全靠它分家（见 `FlightHUD.sally_text()` / `result_hint()`）。

## 进战役图。`level` = 主菜单选的难度（剧情模式**不做机体页**，
## 机体由每一关的 `Mission.player_suit` 定 —— §9.5 的 POV 就是靠它）。
func _open_campaign(level: int) -> void:
	if level<0:level=Difficulty.Level.NORMAL
	_set_paused(false)
	_clear_match()
	_close_campaign()
	# 每次进战役图重读对应难度组的存档；原有三档共用旧档，超级困难独立。
	# 读在这里意味着"手改过存档 / 刚通关"都能立刻反映到图上。
	_refresh_super_hard_unlock(false)
	if level==Difficulty.Level.SUPER_HARD and not Game.super_hard_unlocked: level=Difficulty.Level.HARD
	_campaign_level=level
	Game.campaign_progress = CS.load_progress(CS.path_for_difficulty(campaign_save_path,level))
	Game.active_mission = null
	Game.active_challenge = null
	Game.active_challenge_id = ""
	# 背景沿用主菜单那一套（太平洋群岛 · 夜）—— 与 `_show_menu()` 同一个理由：
	# 从别处回到剧情流程时背景突然变成上一局的地图，看着像出错。
	Game.active_map = MapDef.pacific()
	Game.active_time_of_day = Game.active_map.time_of_day
	world.apply_map(Game.active_map)
	phase = Phase.CAMPAIGN
	Game.set_phase(Game.Phase.MENU)
	menu.close_menu()
	menu.visible = false
	mission_brief.close()
	mission_title.skip()
	campaign_map.open(Game.campaign_progress)
	# ★ 难度**落进这一页**：它是"选关"那一屏的一部分（左 / 右切），
	# 而且必须在 `open()` 之后 —— `open()` 只摆光标，不动 `level`。
	# ⚠️ 反向的读取在 `_on_campaign_chosen()`：离开这一页时把玩家选的难度抄进 `_campaign_level`。
	campaign_map.level = _campaign_level
	campaign_map.super_hard_unlocked = Game.super_hard_unlocked
	# ★ 制作人模式**落进这一页**（2026-09-30）：与上面那一行同一条分工 ——
	# 战役图页不认任何全局状态（它的 `producer` / `progress` 都是注入的），
	# 而"现在是谁在玩"归 `Game` 管。
	# ⚠️ 它是**每次进图现读**，不是缓存：玩家在设置页把开关一开，
	# 回主菜单再进战役图就是全解锁 —— 不需要重启游戏。
	# ⚠️ 反过来（开了制作人模式**打了一关**再关掉）也成立：这里的重新落值
	# 会把 `producer` 改回 `false`，锁立刻回来。那正是它的意义（"调试用"）。
	# ⚠️ 它**绝不落盘** —— 这里只是把内存里那个布尔值搬进这一页，
	# `CampaignScript.save_progress()` 那段一个字都没碰（老板要求：每次开游戏手动开）。
	campaign_map.producer = Game.producer_mode
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	hud.visible = false
	speed_lines.set_intensity(0.0)
	speed_lines.set_dash(0.0)
	chase.set_target(null)
	Audio.play_bgm(Audio.Bgm.MENU)
	_prev_incoming = 0
	_low_hp_announced = false


## 离开剧情流程。**回主菜单 = 真的走人** —— 战役图/简报关掉、当前关清空
##（`R 重来` 要重开的那一关就是它，留着会让下一局莫名其妙地重开上一关）。
func _close_campaign() -> void:
	_campaign_mission_id = ""
	if campaign_map != null and is_instance_valid(campaign_map):
		campaign_map.close()
	if mission_brief != null and is_instance_valid(mission_brief):
		mission_brief.close()
	Game.sally_result = {}


## 战役图上选定了一关 → 开简报页。
##
## ★ P 槽（序章播片）就挂在这里：§3.2 的箭头是「[战役图] 选任务 → 🎬P 序章 → ① 简报」，
## 而它**只在第一次进战役前播**。存档表里没有"序章看过没有"这一位，
## 但"一关都还没通关"恰好等价于"第一次进战役"（`cleared_count() == 0`）。
func _on_campaign_chosen(mission_id: String) -> void:
	var m: MS.Mission = MS.by_id(mission_id)
	if m == null:
		return
	campaign_map.close()
	# ★ 离开战役图 = "选关"这件事定案 ⇒ 把玩家在这一页选的**难度**抄下来。
	# 那一页是难度的唯一可改点（菜单不再问难度），所以这一行是它的唯一出口 ——
	# 少了它，玩家在图上切的难度**一步都不生效**，而且不报错。
	_campaign_level = campaign_map.level
	if CS.cleared_count(Game.campaign_progress) == 0:
		await _play_cutscene("prologue", "")
	_campaign_mission_id = mission_id
	if not mission_brief.open(m):
		# 数据缺失（不该发生）：退回战役图，而不是留一个空白页
		_campaign_mission_id = ""
		campaign_map.open(Game.campaign_progress, true)
		return
	phase = Phase.BRIEF


## 简报页返回 → 回战役图，**光标停在刚才那一关**（玩家改主意多半是想换一关，
## 而不是想从头再找一遍）。
func _on_brief_cancelled() -> void:
	mission_brief.close()
	_campaign_mission_id = ""
	phase = Phase.CAMPAIGN
	campaign_map.open(Game.campaign_progress, true)


## 简报页按确认 → 出击。
func _on_brief_confirmed() -> void:
	var id := _campaign_mission_id
	if id.is_empty():
		return
	mission_brief.close()
	_sortie_campaign(id)


## 战役图返回（Esc）→ 回主菜单。
func _on_campaign_cancelled() -> void:
	Audio.play_ui("ui_return")
	_show_menu()


## ★ 真正的出击：从"一关"走到"战斗开始"。
##
## 顺序（§3.2 的 ③④）：
##   ① 把这一关解析进 `Game.*`（机体 / 难度 / 地图 / 波次入口）
##   ② 🎬 B 槽：任务前播片（有片子且非无头才播）
##   ③ 读条 + 分阶段建图
##   ④ 任务标题卡（2 秒 / 可跳过；**无头下同步跳过**）
##   ⑤ `_launch_match()` —— 撒机体、起战斗
##
## ⚠️ 标题卡**必须排在 `_launch_match()` 之前**：那一刻战斗还没起，
## `Game.elapsed` 一秒都没走 ⇒"这一关打了多久"里**不含演出的 2 秒**
##（结算页的效率项与 `Mission.par_secs` 都吃这个数）。
##
## ⚠️ 出击期间阶段钉在 `CAMPAIGN`：`_process` 的分支因此什么都不做，
## 尤其**不会**再走一遍结算页的输入分支 —— 那会把"重来"变成一串连环重开。
func _sortie_campaign(mission_id: String) -> void:
	if not _resolve_campaign_match(mission_id):
		_open_campaign(_campaign_level)
		return
	phase = Phase.CAMPAIGN
	Game.set_phase(Game.Phase.INTRO)
	_phase_lockout = PHASE_LOCKOUT
	_restart_held = false
	hud.visible = false
	campaign_map.close()
	mission_brief.close()
	await _play_cutscene("brief", mission_id)
	_clear_match()
	# ★ 发射段（M03 的演出）：这一关的**起点不是战场**，而是太平洋的**海面**。
	#   先建起点图 → 播发射演出 → 演出末段自己把图换成战场（LEO）→ 交还战斗流程。
	#   见 `_begin_launch()`。
	#   ⚠️ 2026-09-30：老板砍掉了海上平台（「不需要用发射平台，直接从海里面出来就行了」）
	#   ⇒ 发射点上**一件人造物都没有**，只有水 + 出水特效（`SeaSplash`）+ 头顶那垛云。
	var mission: MS.Mission = Game.active_mission
	if mission != null and mission.launch_prologue:
		var start_map := MapDef.pacific()
		loading.open("%s · 夜战" % start_map.name_cn)
		loading.advance(0.08, "前往发射场……")
		await get_tree().process_frame
		world.build_stage.connect(_on_world_build_stage)
		await world.apply_map_staged(start_map)
		world.build_stage.disconnect(_on_world_build_stage)
		loading.advance(0.92, "发前准备……")
		await loading.finish()
		if mission_title.play(mission_id):
			await mission_title.finished
		_begin_launch()
		return
	var map := Game.active_map
	loading.open("%s · %s" % [map.name_cn, "夜战" if map.time_of_day != null else ""])
	loading.advance(0.08, "进入战场……")
	await get_tree().process_frame
	world.build_stage.connect(_on_world_build_stage)
	await world.apply_map_staged(map)
	world.build_stage.disconnect(_on_world_build_stage)
	var warm_resources:=await preload("res://scripts/flight/loadout_warmup.gd").warm(self,
		preload("res://scripts/flight/loadout_warmup.gd").paths(_warmup_suit_ids()))
	loading.advance(0.92, "部署机体……")
	await loading.finish()
	if mission_title.play(mission_id):
		await mission_title.finished
	# ★ 轮 57：M04 的**开场演出**（佩涅罗佩用光束大炮轰运输仓）。
	#   与发射段是**同一种形态**（先建图 → 播一段 → 再交还战斗流程），
	#   差别在"不换图、玩家不能动"。判据走 `Mission` 的数据，**不写 `if id == "M04"`**。
	if mission != null and mission.davao_intro:
		_begin_davao_intro()
		return
	if mission != null and mission.pod_strike:
		_begin_pod_strike()
		return
	_launch_match(true,false)
	warm_resources.clear()
	_begin_sortie_or_fight()


## 把"一关"解析成 `Game.*` 配置。
##
## ## ⚠️ 为什么**不**复用 `_resolve_match()` 的 CHALLENGE 分支
## 那个分支拿 `Game.active_challenge_id` 去 `ChallengeScript.by_id()` 查表，
## 查不到就**兜底成 `xi_vs_penelope()`**（太平洋群岛）。而 `ChallengeScript` 里
## 只有轮 B 迁移过来的 4 场（M01/M02/M04/M07）—— M03/M05/M06 查不到
## ⇒ **静默用错地图**（打的是太平洋，而不是这一关该在的那张图）。
## ⇒ 剧情模式的地图**只从 `Mission.map_id()` 来**，一面兜底都不留：
## 查不到就返回 false、退回战役图，绝不拿别的图顶上。
func _resolve_campaign_match(mission_id: String) -> bool:
	var m: MS.Mission = MS.by_id(mission_id)
	if m == null:
		push_warning("剧情模式：查不到这一关（%s）" % mission_id)
		return false
	var mid: int = m.map_id()
	if mid < 0:
		push_warning("剧情模式：%s 的战场名不认（%s）" % [mission_id, m.arena])
		return false
	_set_paused(false)
	_campaign_mission_id = mission_id
	Game.match_mode = Game.MatchMode.CHALLENGE
	# 机体**不由玩家选**（剧情模式没有机体页）：它就是这一关的 `player_suit`。
	Game.active_suit = m.player_suit
	Game.active_difficulty = Difficulty.make(_campaign_level)
	Game.active_enemy_suit = -1
	Game.active_mission = m
	# 波次管线的入口：`Mission` → `Encounter`（**同一个 `Wave` 类型**）
	# ⇒ `spawn_challenge()` / `_spawn_wave()` 一行都不用改（§5.1「升级，不是重写」）。
	Game.active_challenge = MS.to_encounter(m)
	Game.active_challenge_id = m.id
	Game.active_map = MapDef.by_id(mid)
	Game.active_time_of_day = Game.active_map.time_of_day
	return true


## ★ 结算：把这一局的战果落进军资（§6.3）。
##
## ⚠️ **只在剧情模式里做事**：`Game.active_mission == null` ⇒ 立刻返回
## ⇒ `Game.sally_result` 为空 ⇒ 四种现有模式的结算页**一行都不多**（§9.4 的硬约束）。
##
## ⚠️ 必须在 `hud.capture_result()` **之前**调用：结算页读的是那一刻抄下来的快照，
## 先开结算再算钱的话，那一行永远显示 `+0`。
func _settle_campaign(win: bool) -> void:
	var m: MS.Mission = Game.active_mission
	if m == null:
		Game.sally_result = {}
		return
	# 评价用的那几个读数与 `hud.capture_result()` **走同一个纯函数**
	#（`FlightHUD.rating_stats`）⇒ 两边不可能算出不同的字母。
	# ⚠️ 这里必须读 `player` 还活着时的数：本函数在阵亡/击坠那一下被调，
	#    残骸 2.2 秒后就释放了（与 `capture_result` 同一条理由）。
	var hp_ratio := 0.0
	var ifield := 0.0
	var ifield_max := 0.0
	if player != null and is_instance_valid(player):
		hp_ratio = player.hp_ratio()
		ifield = player.ifield_hp
		ifield_max = player.ifield_max
	var outcome := MissionRating.Outcome.WIN if win else MissionRating.Outcome.LOSE
	var rating: Dictionary = MissionRating.evaluate(
		FlightHUD.rating_stats(outcome, hp_ratio, ifield, ifield_max))
	# "这一关是不是首通"要在 `settle()` **之前**问出来 —— 它决定结算页要不要写
	# "解锁 M02"（重打一关时那个提示会变成噪音）。
	var was_cleared := CS.is_cleared(Game.campaign_progress, m.id)
	var settled := CS.settle(Game.campaign_progress, m.id, {
		"win": win,
		"grade": str(rating.get("grade", MissionRating.NO_GRADE)),
		"score": float(rating.get("score", 0.0)),
		"kills": Game.kills,
		# 命名王牌是**轮 F** 的事（§7.1 的 `NamedAce` 表），本轮恒 0。
		"named_kills": 0,
		"base": m.base_reward,
	})
	# ⚠️ 显式过一道类型：`settled["progress"]` 的静态类型是 `Variant`，
	# 直接赋给带类型的 `Game.campaign_progress` 在静态检查下不可靠
	#（运行时能跑，但会在别处炸 —— 与 `campaign_map.state_label()` 那条同一个坑）。
	var prog: Dictionary = settled["progress"]
	Game.campaign_progress = prog
	# 落盘。**失败也落**（图鉴的"见过"照记），但金额是 0 —— 那是 `settle()` 的事。
	CS.save_progress(Game.campaign_progress, CS.path_for_difficulty(campaign_save_path,_campaign_level))
	# 结算页只读这四个数：**不把整份进度**（含改装槽位）**塞进 HUD 的快照**。
	Game.sally_result = {
		"reward": int(settled["reward"]),
		"delta": int(settled["delta"]),
		"win": win,
		"next": CS.next_id(m.id) if (win and not was_cleared) else "",
	}


## 这一局的结算页是不是"剧情模式的结算页"（判据与渲染那条同源：`sally_result` 空不空）。
func _in_campaign_result() -> bool:
	return not Game.sally_result.is_empty()


## ★ §6.7 的「重来」：**就地重开同一关**。
##
## ⚠️ 这不是 README 里被撤掉的那个"再战一局" —— 那是**回菜单重选机体与难度**。
## 剧情模式的单位是**一关**：同一台机 / 同一张图 / 同一套 profile
##（§6.7 的 R5 追加：改装必须跟着回来 ⇒ 重来**不重新读存档**，
##  复用的是内存里那一份已经施加了改装的 profile）。
## 本轮还没有改装（轮 C2 才做），但这条口径现在就守着：
## 本函数**不碰** `Game.campaign_progress`，也不调 `_open_campaign()`。
##
## ⚠️ 只在**失败**时给（§3.2 的流程图里它写在"失败"那一支上）。
func _can_retry() -> bool:
	return _in_campaign_result() and not bool(Game.sally_result.get("win", false))


func _retry_campaign() -> void:
	if _campaign_mission_id.is_empty():
		_show_menu()
		return
	Game.sally_result = {}
	_sortie_campaign(_campaign_mission_id)


## 🎬 播一个槽位的片。
##
## ## 片的"清单"由 `Mission` 给，**路径**由 `CutsceneScript` 给
## `Mission.cutscenes[slot]` 是**片目 id 的有序数组**（§7.5.4 的原话：
## 「顺序由 `Mission` 数据决定，不由表和 roll 决定」；`mid` 槽更是一支一个 id、
## 由 `Trigger` 的 `cutscene:<id>` 点名）。而"这个 id 对应哪个文件"归
## `cutscene_script.gd` —— 那一层只认 id。
##
## ⚠️ **不去调 `CutsceneScript.by_slot(mission, slot)`** 作为第二条路：那会变成
## "两份清单"，两边一旦不一致，表现是"表里明明有片、游戏里永远不播"，
## 而且**一处都不报错**（本工程吃过好几次这种分家）。
## `by_slot()` 只为**序章**留着 —— 那一支不属于任何一关（`mission == ""`）。
##
## **一支片都没有也不报错** —— 素材是可选依赖（§7.5.5）：
## 老板给的原剧切片还没到，整条战役必须在"一支片都没有"的仓库里跑通。
##
## ⚠️ 无头下 `IntroMovie.should_play_in_mission_now()` 恒为 false
## ⇒ `play_blocking()` **同步返回 false、绝不 await**。这条是硬性的：
## await 一个永不到来的信号 = 整条回归挂在这一步，而且看起来只是"跑得很慢"。
func _play_cutscene(slot: String, mission_id: String) -> void:
	var ids: Array = []
	if mission_id.is_empty():
		var c: CUT.Cutscene = CUT.by_slot("", slot)
		if c != null:
			ids.append(c.id)
	else:
		var m: MS.Mission = MS.by_id(mission_id)
		if m == null:
			return
		ids = m.slot(slot)
	for raw in ids:
		var clip: CUT.Cutscene = CUT.by_id(str(raw))
		if clip == null or not clip.available():
			# 表里没登记 / 文件还没到 ⇒ 跳过这一支，战役照常推进
			continue
		await IntroMovie.play_blocking(canvas, clip.id)


## 离开剧情模式的结算页：🎬 D 槽（任务后播片）→ 回战役图。
##
## ⚠️ 先把阶段挪开再 `await`：D 槽要播一会儿，期间不该还能被结算页的输入分支读到
##（不然玩家连按两下 Enter 就会走两遍）。
func _leave_campaign_result() -> void:
	phase = Phase.CAMPAIGN
	_phase_lockout = PHASE_LOCKOUT
	await _play_cutscene("debrief", _campaign_mission_id)
	_open_campaign(_campaign_level)


# ============================================================ 出生

func spawn_round() -> void:
	_clear_match()
	Game.reset()
	# 新手教学（1.2 第二十六轮修复）：菜单在开局前把意图写进
	# `tutorial_requested`，而上一行的 `Game.reset()` 会清 `tutorial_mode` ——
	# 所以必须**reset 之后**落成正式开关，并顺手消费掉请求（不留给下一局）。
	# 不走菜单的流程（联机等）请求恒为 false，教学不会凭空挂着。
	Game.tutorial_mode = Game.tutorial_requested
	Game.tutorial_requested = false

	var player_suit := SuitProfile.by_id(Game.active_suit)
	# Apply mission bonuses only to this player's fresh sortie profile.
	if Game.match_mode == Game.MatchMode.CHALLENGE and Game.active_mission != null:
		player_suit = Game.active_mission.make_player_profile()
	# ★63-24 无限强化演习：**开局自选的 3 张卡必须在赋给机体之前施加好**。
	#
	# ⚠️⚠️ 位置不能挪到 `spawn_endless()` 里 —— `FlightBody._ready()` 会把
	# `profile.hull_hp` / `ifield_hp` / `rifle_count` / `rifle_magazine` 这一批值
	# **抄进自己的字段**（`flight_body.gd:903` 一带：`max_hp = profile.hull_hp` …），
	# 而 `_ready()` 发生在下面 `units_root.add_child(player)` 那一刻 ——
	# 也就是本行**之后**几行。在 `spawn_endless()` 里才施加的话，那一批抄过去的数
	# 永远是出厂值：**装甲卡的加血一个点都不生效**，而伤害 / 间隔那类"每次现读
	# `profile`"的卡全都正常 ⇒ 典型的静默半失效，且只有量血条才看得出来。
	#
	# ⚠️ `Game.reset()` 已经在本函数开头跑过 ⇒ 这里的 `player_suit` 是干净的出厂实例，
	# `EndlessScript.apply_run()` 的"先还原出厂值、再整批施加"从正确的地基起算。
	if Game.is_endless():
		# 消费菜单写下的**自选卡请求**。
		#
		# ⚠️ 为什么请求要在这里才消费：链路是"菜单写请求 → `Game.reset()` → 这里"，
		# 而 `reset()` **故意不清** `endless_pick_request`（清了就等于白写 ——
		# `tutorial_requested` 正因此踩过、1.2 第二十六轮才修）。见 `game.gd` 的注释。
		Game.endless_owned.clear()
		Game.endless_owned_tier.clear()
		Game.endless_owned.append_array(Game.endless_pick_request)
		# ⚠️ **品质数组必须同步写**（与 `endless_owned` 同长同序）。
		# 开局自选全部来自**基础卡池**（设计 §5.6 的 `basic_pool()`）⇒ 恒 `BASIC`。
		# 漏了这一段的后果不是报错，而是 `_apply_endless_cards()` 里
		# `i < endless_owned_tier.size()` 双双落空 ⇒ 退回 `BASIC` 兜底值 ——
		# 今天恰好一模一样，但等奖励轮把 `PERFECT` 卡塞进来之后就**静默错档**。
		for _i in Game.endless_pick_request.size():
			Game.endless_owned_tier.append(UpgradeCard.Tier.BASIC)
		Game.endless_pick_request = []
		_apply_endless_cards(player_suit)
	# ⚠️ 出击半径**按图给**（`match_spawn_radius()`）：奥恩贝利的丘陵外移到
	# 82…96 km 之后，出击点跟着去那一圈（46 575 会落在城里）；非城市图仍是
	# 全局 `SPAWN_RADIUS`。详见 `WorldBuilder.match_spawn_radius()`。
	# ★ 出击点：**这一局由发射段的抵达点给**（见 `LaunchScript.arrival_pos()`）。
	#
	# 为什么不是"照常 `spawn_point()` 再挪一下"：M03 的第一个目标是
	# `Objective.reach("orbit_cargo")`（**抵达**运输仓接收点），
	# 也就是说"从别处飞过来"本来就是这一关的核心动作。
	# 改前玩家在离运输仓 46.6 km 处出生，"飞过去"只有十几秒，读起来像出生就贴脸；
	# 发射段把他放在 **200 km** 外，这一关的进场才有了该有的尺度。
	# ★ 轮 50：出击方位角改走 `mission_spawn_angle()`。
	# 非剧情模式它**恒返** -95.0 ⇒ 四种老模式的出点**逐位不变**；
	# 剧情模式读这一关自己的 `spawn_angle_deg`
	#（M01 = -95°、M02 = +85° —— 关于图心点对称，差整 180°）。
	var player_pos := world.spawn_point(mission_spawn_angle(), world.match_spawn_radius(),
		world.match_player_alt())
	if _spawn_from_launch:
		player_pos = LaunchScript.arrival_pos()
	_spawn_from_launch = false

	player = PlayerController.new()
	player.name = "Player"
	player.team = 0
	player.is_player = true
	player.profile = player_suit
	player.display_name = player_suit.display_name
	player.projectile_container = projectiles
	units_root.add_child(player)
	if Game.active_mission != null:
		player.hp = player.max_hp * clampf(Game.active_mission.player_start_hull_ratio,0.0,1.0)

	player_lock = LockOnSystem.new()
	player_lock.name = "PlayerLockOn"
	player_lock.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player_lock)
	# 轮 36：**玩家火控的自动接战只允许一次**。
	#
	# 需求原话：「锁定系统重修，除非玩家手动切换锁定，不然不会自动切换锁定对象」。
	# 保留"进场自动锁住正前方最近的那一架"当保底（屏上不会一开局就是空的），
	# 之后一旦没有锁定对象（被打掉 / 飞出脱锁距离 / 对方丢枪脱锁），
	# 火控**不再自己咬下一个** —— 交给玩家按 Tab（`cycle_target`）或数字键。
	#
	# ⚠️ **敌机的火控不设这一条**（`_attach_ai()` 那边保持默认 `-1` = 不限次）：
	# AI 就是靠自动接战选目标的，而它从不 `add_lock()` ⇒ 组里永远只有一个人
	# ⇒ 它的行为与改动前**逐位相同**。
	player_lock.auto_engage_limit = 1
	player_lock.setup(player)
	Game.register_lock(player, player_lock)
	player_lock.lock_acquired.connect(_on_player_lock_acquired)
	player_lock.lock_lost.connect(_on_player_lock_lost)

	if Game.match_mode == Game.MatchMode.TRAINING:
		spawn_training(player_pos)
	elif Game.match_mode == Game.MatchMode.CHALLENGE:
		spawn_challenge(player_pos)
	elif Game.match_mode == Game.MatchMode.LAN:
		spawn_lan(player_pos)
	elif Game.match_mode == Game.MatchMode.SQUAD:
		spawn_squad(player_pos)
	elif Game.match_mode == Game.MatchMode.ENDLESS:
		spawn_endless(player_pos)
	else:
		spawn_versus(player_pos)

	chase.set_target(player)
	player.setup_refs(player_lock, chase)
	player.controls_enabled = false

	_death_anchor = null
	hud.setup(player, chase, player_lock)

	player.destroyed.connect(_on_player_destroyed)
	player.damaged.connect(_on_player_damaged)
	player.rifle_discarded.connect(_on_rifle_discarded)
	player.ifield_broken.connect(_on_player_ifield_broken)
	player.ifield_hit.connect(_on_player_ifield_hit)


## 1v1：默认"另一台"，也可以在菜单里**指定敌机**（1.2 的"选择敌人"）。
##
## 1.1 起有三台机，所以"另一台"不再是一个三元表达式：
## 从 `SuitProfile` 的对战池里取"不是玩家这台"的第一台 ——
## 池子的顺序就是"默认对手"的优先级（柯西 ↔ 佩涅罗佩 仍是最经典的一组）。
## `Game.active_enemy_suit >= 0` 时用玩家选的那台（可以选成跟自己一样的镜像战）。
func spawn_versus(player_pos: Vector3) -> void:
	var chosen := Game.active_enemy_suit if Game.active_enemy_suit >= 0 \
		else versus_opponent_of(Game.active_suit)
	var enemy_pos := world.spawn_point_foe(player_pos, 85.0, world.match_spawn_radius())
	# ⚠️ 玩家也必须在这里摆位。抽成 spawn_versus 之后漏掉这一行，
	# 玩家就会停在原点（高度 0 → 第一个物理帧触发"撞海"直接坠机），
	# 表现是"一开局就死" —— 测试里是 round 套件在 4 秒后拿到一个已释放的玩家机。
	_place(player, player_pos, enemy_pos)

	enemy = _attach_ai(chosen, enemy_pos, player_pos, "Bandit")
	enemy_lock = Game.lock_of(enemy)
	enemy.destroyed.connect(_on_enemy_destroyed.bind(enemy))
	enemy.rifle_discarded.connect(_on_enemy_rifle_discarded)

	# ⚠️ **1v1 就是一对一的单挑，这里不再多撒僚机。**
	#
	# 历史上这里曾调过 `attach_pedal_pair()`，理由是当时用户说
	# "马夫蒂的踏板是前后两台"、而工程里还没有"编队"这个概念，
	# 于是把"两台"塞进了 1v1。用户随后实测报障：
	# 「游戏的 1v1 对战模式会**多一台敌机**」—— 那正是这一段。
	#
	# 现在"多台 + 踏板 + 编队"有了**独立的模式**（`MatchMode.SQUAD`，
	# 见 `spawn_squad()`），所以 1v1 回到纯 1v1：
	# 一架敌机、一块板、胜负判定与"击坠即胜"的老行为一字不变。
	#
	# `attach_pedal_pair()` 仍然保留 —— 但**只给编队战用**（见 `_spawn_side`），
	# 不再从 1v1 这条路进来。


## **编队战**（1.2 第二十轮）。老板定的编制：
## 「三个量产机编队（三台飞行踏板 + 六台量产机）+ 一台 ace 机……玩家可以自己选择
## 阵营的机型配置。**两边都有**（ACE 机）」。
##
## ## 谁是谁
## 玩家阵营由 `Game.active_side` 给定；玩家开 `Game.active_suit`（菜单只列该阵营的机）。
## 出战名单由 `BattleFormation.lineup()` 生成 —— **那边是编制的唯一真源**，
## 这里只负责"照表撒人"，所以 `main` 里不出现任何"几台""什么机"的硬编码。
##
## ## 编队与踏板的关系
## 每个量产编队 = **一块踏板 + 两台机体**：0 号位是领机（板挂在他身上、他正常飞），
## 1 号位是后座（`set_formation(lead, 1)`，靠 `BanditAI._blend_formation` 贴住挂位）。
## ACE 机**不骑板**（用户定过 ACE 不可骑），自己飞 —— 这正是"量产机得等板、
## ACE 得自己扛着燃料槽飞"那个不对称设计的落点。
func spawn_squad(player_pos: Vector3) -> void:
	var side: int = Game.active_side if Game.active_side >= 0 else BattleFormation.Side.MAFTY
	# ★63-9 B4：走 `opposing()` —— 这条「对面是谁」以前在主菜单里又写了一遍，
	# 两份 if 迟早对不上，而对不上的表现是**跨阵营**（不报错）。
	var foe_side: int = BattleFormation.opposing(side)
	var mine := BattleFormation.lineup(side, Game.active_suit)
	# 敌人那边没有玩家 ⇒ `player_suit` 传 −1（它不在这边的池子里，
	# 于是 `lineup()` 里 `player_is_ace` 为 false、所有位置都归 AI）。
	# ⚠️ 这里必须传**负一**而不是 0（`SuitProfile.Id.XI`）：
	# 传 0 会让"玩家开柯西"时敌人也以为玩家开的是柯西，名单因此错位。
	# ★63-9 B4：第三个参数 = **玩家在菜单里挑的那台敌方 ACE**。
	# 传 −1（没挑 / 别的模式）时 `lineup()` 自己退回 `r.ace()`，旧行为不变。
	var theirs := BattleFormation.lineup(foe_side, -1, Game.active_enemy_suit)
	Game.squad_units_per_side = BattleFormation.unit_count_per_side()

	# 玩家摆位：面向战场中心（与世界其它模式同一套站位）
	var enemy_focus := world.spawn_point_foe(player_pos, 85.0, world.match_spawn_radius())
	_place(player, player_pos, enemy_focus)

	_spawn_side(mine, 0, player_pos, enemy_focus, true)
	_spawn_side(theirs, 1, enemy_focus, player_pos, false)


## 把一边的名单撒出来。
##
## `is_mine` = 这一边是玩家的阵营（team 0）。玩家的那一台**已经在 `spawn_round()` 里
## 建好了**（`player` 是 `PlayerController`），所以这里遇到 `owner_is_player` 就跳过，
## 只把他的阵营与编队关系补上。
func _spawn_side(units: Array, team: int, base_pos: Vector3, look_target: Vector3,
		is_mine: bool, online := false) -> void:
	# 每个编队的领机，按 squad 号存起来 —— 后座要用它找自己的领机。
	var leads: Dictionary = {}
	var ai_index := 0
	for u: BattleFormation.Unit in units:
		if u.owner_is_player:
			# 玩家那台：**不重建节点**（他在 `spawn_round()` 里已经就位了），
			# 但有两件事必须在这里补上：
			#   ① **给他挂板** —— 玩家开量产机时他就是一个编队的领机，
			#      而板是挂在领机身上的。AI 那一路走 `_attach_ai() → attach_pedal()`，
			#      玩家这一路没有那条线，**必须显式补**（漏了的表现是
			#      "玩家没有板、僚机找不到领机，整队只有 5 块板" —— 实测就是这么红的）。
			#   ② 把他记进 `leads`，后座才能找到自己的领机。
			if online and not u.is_ace and u.slot == 1:
				var carrier = leads.get(u.squad)
				if carrier is FlightBody and carrier.has_pedal():
					carrier.pedal_owner().add_rider(player)
					player.set_carried_by(carrier,1)
				continue
			if not u.is_ace:
				leads[u.squad] = player
				# ⚠️ `attach_pedal()` 的形参是 `BanditAI`（那是给 AI 敌机写的），
				# 所以玩家走 `FlightBody` 那一层的公共入口 `spawn_with_pedal()`。
				player.spawn_with_pedal()
			continue
		# ---- 先决定"这台要不要自己的板"，再建 ----
		#
		# ⚠️ **后座不挂自己的板**：一块板上一队两人，板挂在领机身上。
		# 而且必须**建的时候就不给**（`with_pedal = false`），不能"配完再摘" ——
		# `apply_pedal_flight_bonus()` 的**转向折扣**是一次性乘上去的
		# （`_pedal_turn_applied`），摘掉就得额外写"还原转向"，
		# 漏了会让后座的转向永远慢 20%。
		#
		# ⚠️ 顺序也重要：`_attach_ai()` 是先建节点、后挂板，
		# 所以"先建一台不要板的、再建一台要板的"这条路要求**领机先于后座**被建 ——
		# 而 `lineup()` 生成名单时就是按 (squad, slot) 顺序排的（slot 0 在前）。
		var want_pedal: bool = (not u.is_ace) and u.slot == 0
		# 这一台摆在哪儿：与 AI 那一路共用同一套抖动，免得两台叠在一起。
		var jitter := float(ai_index) * 140.0
		# ---- **归远端玩家开的机体**（多人模式，第二十二轮下半）----
		#
		# ⚠️ **不建 AI**，而是建一个代理机体（`NetProxyBody`）：
		# 那台机体的物理与开火都在**对面的机器上**跑，这台机器只负责按快照插值地画出来
		#（与 1v1 的"对手"完全同一套机制，见 `NetSession` 的文件头）。
		#
		# ⚠️ 两种情况的**位置来源不同**，这是同乘最容易漏的一处：
		#   - **各自出战**：代理位置来自快照（对面在自己机器上飞）；
		#   - **同乘一块板**：代理位置来自**本机踏板的挂位**（`set_carried_by`）——
		#     因为那块板的物理在这台机器上跑（主机驾驶），对面只是"坐在上面"。
		#     走快照的话会出现"板在这、人却在自己飞"的分裂。
		if u.owner_is_client and online:
			var mate_pos := base_pos + Vector3(jitter, float(team) * 60.0, jitter * 0.35)
			ai_index += 1
			var proxy := _spawn_remote_player(u.suit, mate_pos, look_target,
				"%s%d_%d" % ["Mate", u.squad, u.slot], team)
			if want_pedal:
				if online and Net.role == Net.Role.CLIENT: proxy.spawn_with_pedal()
				# 远端玩家占的是领机位（他开板）—— 建完先记下，回传位姿时要用
				leads[u.squad] = proxy
			else:
				# 后座：贴到本机领机的板上（同乘）
				var lead2 = leads.get(u.squad, null)
				if lead2 is FlightBody and lead2.has_pedal():
					var board2: FlightPedal = lead2.pedal_owner()
					if board2 != null:
						board2.add_rider(proxy)
					proxy.set_carried_by(lead2, 1)
			continue
		ai_index += 1
		var pos := base_pos + Vector3(jitter, float(team) * 60.0, jitter * 0.35)
		var ai := _attach_ai(u.suit, pos, look_target, "%s%d_%d" % [
			"Ally" if is_mine else "Bandit", u.squad, u.slot], -1.0, want_pedal)
		# ⚠️ **玩家的僚机也是 team 0** —— `is_hostile_to()` 判的是 "team 不等"，
		# 所以跨队伤害天然被挡住（编队战里这条最要紧：6 台僚机挨打不能算在敌机上）。
		# `_attach_ai()` 默认给 team 1（它是为"敌机"写的），这里按边改回来。
		ai.team = team
		if online and ai.get("net_unit_id") != null:
			var canonical_team := team if Net.local_team == 0 or _lan_plan_now().same_team else 1 - team
			var key := "%d:%d:%d" % [canonical_team, u.squad, u.slot]
			ai.set("net_unit_id", key)
			Net.squad_bodies[key] = ai
		if want_pedal:
			# 领机：板挂在他身上，后座要用它当挂位锚点
			leads[u.squad] = ai
		elif not u.is_ace:
			# ---- 后座：**真正被载到领机那块板上**（1.2 第二十六轮）----
			#
			# ⚠️ 这里原来是 `set_formation(lead, 1)` —— 那只是"靠转向跟着飞"，
			# **他并没有上板**（`has_pedal()` 为假、板上也只登记着领机一台）。
			# 用户实测报的正是这个：「开局六台量产机，**只有三台是在踏板上的**」。
			#
			# 现在改成 `set_carried_by()`：位置由领机踏板的挂位驱动、不做气动。
			# 于是"一个编队 = 一块板 + 两台机体"才真的成立，
			# 分状态模型也才会显示"两台都在"而不是"只有一号机"。
			#
			# ⚠️ 领机**没有板**时退回转向跟随（否则 `_apply_carried()` 找不到挂位，
			# 这台会原地悬着不动）—— 领机是玩家、而玩家开的是 ACE 机时就是这种情况。
			var lead = leads.get(u.squad, null)
			if lead is FlightBody and lead.has_pedal():
				# ⚠️ **两件事都要做，缺一不可**：
				#   ① `set_carried_by()` —— 位置由领机踏板的挂位驱动（不做气动）；
				#   ② `board.add_rider()` —— **登记进板的骑手表**。
				# 只做 ① 的话位置是对的，但板只认领机一台 ⇒
				# `vis_state()` 停在 SLOT0_ONLY、**模型只画一台机体**、
				# `gun_operator()` 也看不到他（"后座负责踏板武器"就不成立）。
				# 这一条是 `suite_squad_ride` 抓出来的。
				# ⚠️ **类型必须显式标注**：`var board := lead.pedal_owner()` 推不出类型
				#（`lead` 是无类型的 `leads.get(...)` 结果，它的返回值也就没有静态类型）——
				# 那会让**整个 main.gd 编译不过**（实测：`Parse Error: Cannot infer the type
				# of "board" variable`，然后世界/菜单/HUD 全部建不出来）。
				# 这是本工程第三次栽在"三元或 Variant 与类型推断"上，见 `hud.gd` 里同款注释。
				var board: FlightPedal = lead.pedal_owner()
				if board != null:
					board.add_rider(ai)
				ai.set_carried_by(lead, 1)
			elif lead is FlightBody:
				ai.set_formation(lead, 1)
		# ★ 轮 50：**只有敌方那一边**的阵亡才推结算页。
		#
		# ⚠️ 这一行原来是**无条件**接的，而 `_on_enemy_destroyed()`
		# 做的就是一行 `_finish_round()`（**无条件判胜**）⇒
		# “僚机自己撞地 ⇒ 这一局判胜”：
		#   ① 编队战（`is_mine == true` 那一路）—— 既有缺陷；
		#   ② M01「夜袭达沃」—— **功能级**故障：那一关一架敌机都没有，
		#      5 台僚机里任何一台摔了就直接“任务完成”，
		#      玩家永远不需要朝酒店开枪。
		if not is_mine:
			ai.destroyed.connect(_on_enemy_destroyed.bind(ai))
		ai.rifle_discarded.connect(_on_enemy_rifle_discarded)


## 建一个**远端玩家**的代理机体（多人模式，第二十二轮下半）。
##
## 它只做三件事：按 `team` 站队、按快照插值位置、把"被本机打中"转成一次 RPC。
## 物理与开火都在对面那台机器上跑 —— 与 1v1 里的"对手"是同一个东西，
## 区别只是这里它可能是**队友**（同队时 `team` 和本机相同）。
##
## ⚠️ `team` 必须显式传：`_attach_ai()` 默认给敌队，而队友的代理机体要是也给了敌队，
## 会出现"本机打自己队友"（`is_hostile_to()` 判的是 team 不等）。
func _spawn_remote_player(suit_id: int, pos: Vector3, look_target: Vector3,
		node_name: String, team: int) -> NetProxyBody:
	var proxy := NetProxyBody.new()
	proxy.name = node_name
	proxy.team = team
	proxy.is_player = false
	proxy.profile = SuitProfile.by_id(suit_id)
	proxy.display_name = SuitProfile.by_id(suit_id).display_name
	proxy.projectile_container = projectiles
	units_root.add_child(proxy)
	proxy.global_position = pos
	proxy.look_at(look_target, Vector3.UP)
	proxy.fm.speed = SuitProfile.spawn_speed()
	proxy.fm.align_velocity(proxy.forward())
	remote_proxies.append(proxy)
	if not is_instance_valid(remote_proxy):
		remote_proxy = proxy
	if team != player.team:
		proxy.destroyed.connect(_on_enemy_destroyed.bind(proxy))
	return proxy


## 建一台 AI 敌机（含它自己的锁定系统）。**多敌机之后必须走这一条**：
## 每个 AI 都要有自己的 `LockOnSystem`，否则两台杂兵会共用一个导引头
## （一架锁定、另一架跟着"以为自己锁了"），而且 `Game.register_lock` 是按机体登记的。
##
## 顺带统一了两件事，避免"对战里的敌机"和"挑战里的敌机"行为不一致：
##   - **阿利宙斯一律从巡航形态入场**（它本来就是"赶路状态"来的）；
##   - 锁定警报、难度倍率、模型名的接线都在这里一次性做好。
func _attach_ai(suit_id: int, pos: Vector3, look_target: Vector3, node_name: String,
		alt_override := -1.0, with_pedal := true) -> BanditAI:
	var suit := SuitProfile.by_id(suit_id)
	var ai: BanditAI = preload("res://scripts/ai/lan_squad_ai.gd").new() if Game.match_mode == Game.MatchMode.LAN else BanditAI.new()
	ai.name = node_name
	ai.team = 1
	ai.profile = SuitProfile.by_id_form(suit.id, SuitProfile.ArizeusForm.CRUISE) \
		if suit.id == SuitProfile.Id.ARIZEUS else suit
	ai.difficulty = Game.active_difficulty if Game.active_difficulty != null \
		else Difficulty.make(Difficulty.Level.NORMAL)
	ai.display_name = suit.display_name
	ai.projectile_container = projectiles
	units_root.add_child(ai)
	if alt_override > 0.0:
		pos.y = alt_override
	_place(ai, pos, look_target)

	# ---- 飞行踏板（1.2）：**只有 AI 敌机骑** ----
	#
	# 必须在 `_place()` **之后**：踏板要对到骑手脚下，读的是 `model_bounds`
	# （机体摆好位、模型量完才有值）。`configure_pedal()` 内部还会按骑行状态
	# 重算一次速度上限（`BanditAI._apply_top_speed` 的踏板分支）。
	#
	# ⚠️ 这里是"谁能骑踏板"的**唯一写入点**。玩家（`PlayerController`）与
	# 玩家的 AI 僚机都不调它 —— 所以"玩家机体用不到踏板"在代码上是结构性的，
	# 不是一个开关。
	#
	# `with_pedal = false` 给"一板载两台"的后一台用：他会接到**前机那块板上**，
	# 所以这里不能先给他挂一块自己的。**必须走这个参数而不是"挂完再摘"** ——
	# `apply_pedal_flight_bonus()` 的转向折扣是一次性乘上去的（`_pedal_turn_applied`），
	# 挂完再摘就需要"还原转向"这条额外逻辑，漏掉就会让后机的转向永远慢 20%。
	if with_pedal:
		attach_pedal(ai)

	var lk := LockOnSystem.new()
	lk.name = "%sLockOn" % node_name
	lk.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(lk)
	lk.setup(ai)
	Game.register_lock(ai, lk)
	ai.lock = lk
	_ai_locks.append(lk)
	# 敌机锁定玩家的那一刻响警报 —— 需求里三种警报要"用在不同的提示上"，
	# 这一种专指"你被咬住了"。多敌机时会连着响，靠音频层的 900 ms 节流压住。
	lk.lock_acquired.connect(_on_enemy_lock_acquired)
	return ai


## 给一台敌机挂飞行踏板（**"谁能骑踏板"的唯一入口**）。
##
## 拆成函数是因为两个调用点（单机 `_attach_ai` 与一台配一台）都要它，
## 而且这里必须**先挂板再重算速度**：`_apply_top_speed()` 会读 `has_pedal()`
## 决定要不要贴踏板加成，顺序反了就静默少一半加成（本轮真踩过）。
##
## ⚠️ 资格门禁读 `SuitProfile.can_ride_pedal()`：**AI 敌机默认全员可骑**，
## 但 ACE 机（柯西/佩涅罗佩/阿利宙斯）即使当敌机也不骑 ——
## 用户定的规则是"机体属性"，不该因为"谁在开"而变（这也是
## `PlayerController` 那条"ACE 机不可搭乘"能成立的前提：两边同一条判据）。
func attach_pedal(ai: BanditAI) -> void:
	if ai == null or ai.profile == null or not ai.profile.can_ride_pedal():
		return
	ai.configure_pedal()
	if ai.has_pedal():
		ai._apply_top_speed()


## **一台踏板上两台机体**（1.2 用户指定）。
##
## ## 最终做法（用户 2026-09-20 澄清后定型）
##
## 一开始我用了他给的 `梅萨出击！/古斯塔夫出击！` 套装模型（踏板+两台机烤在一起），
## 结果"歪 + 打不掉的影子 + 不能混编"三个问题都出来了（详见
## `FlightPedal.USE_DEPLOYED_MODEL` 的注释）。用户随后明确：
## **那两份模型只是"参考踏板该缩放多大"**，排列方式由我定。
##
## 所以现在是：**每台机体带自己的模型**，各自是一台独立的 `FlightBody`，
## 两块踏板各挂一位骑手 —— 用户的分工由此天然成立：
##   - **领队机**（`lead`，板挂在它身上）负责**操控踏板**；
##   - **另一台**（`follow`，自带一块板）负责**踏板的武器**，
##     由 `FlightPedal.gun_operator()` 判定（板上第二位骑手 = 他）。
##
## 两块板并排、间距由 `FlightPedal.SLOT_SPREAD_X_M` 给，
## 所以两台看起来是**站在同一条线上**，而不是一前一后。
##
## 返回被配对的第二台（没造成时返回 null）。
func attach_pedal_pair(lead: BanditAI, suit_id: int, name_hint := "Wing") -> BanditAI:
	if lead == null:
		return null
	# ⚠️ **不要求领机自己有板**：ACE 机（柯西/佩涅罗佩/阿利宙斯）骑不了板，
	# 但它们照样可以当"一对"里的领队 —— 只是两台都没板。
	# 早先这里 return null，会让"开着佩涅罗佩的敌人"变成孤零零一架，
	# 而用户要的编队是"一对"。
	var side := lead.global_transform.basis.x * FlightPedal.SLOT_SPREAD_X_M
	var back := lead.global_position + side - lead.forward() * 18.0
	# ⚠️ `with_pedal` 保持 true：**每台机体各带一块板**（当前路线），
	# 而 `attach_pedal()` 自己会按资格门禁决定挂不挂。
	var follow := _attach_ai(suit_id, back, lead.global_position, name_hint)
	return follow


## 局域网对战（1.2）：本地只模拟自己那台，对手是一个**代理机体**。
##
## 分工（详见 `NetSession` 的文件头）：
##   - 本机机体 = 正常的 `PlayerController`（物理、开火、命中都在本地跑）；
##   - 对手 = `NetProxyBody`：不吃伤害、不跑气动，位置按 20 Hz 快照插值；
##   - 我打中代理机体 → 代理把伤害 RPC 给对面（谁的血条谁维护）；
##   - 对面打中我 → 收到 RPC，把伤害落在**我自己的**机体上。
## 局域网对战（1.2；**第二十二轮下半扩成"多人玩法"**）。
##
## 分工（详见 `NetSession` 的文件头）：
##   - 本机机体 = 正常的 `PlayerController`（物理、开火、命中都在本地跑）；
##   - 远端玩家 = `NetProxyBody`：位置按 20 Hz 快照插值（同乘时改成贴本机的板）；
##   - 我打中代理机体 → 代理把伤害 RPC 给对面（谁的血条谁维护）；
##   - 对面打中我 → 收到 RPC，把伤害落在**我自己的**机体上。
##
## ## 第二十二轮下半：部署方式由 `LanPlan` 决定（用户定的规则表）
## | 组合 | 部署 |
## |---|---|
## | 同阵营 + 两人都量产机 | **同乘一块踏板**：主机驾驶、加入方后座 |
## | 其余（含"同阵营但有人选 ACE"）| 各自正常出战，两边满编 + 各一台 ACE |
##
## ⚠️ **两台机器各自算一遍 `LanPlan`，结果必须一致** —— 它只依赖两人的选择
##（阵营 + 机体），不依赖"谁是本机"。所以两边跑同一份纯函数就够了，不需要额外同步方案。
## 这也是把规则做成纯函数的**回报**：同步层只需要同步"选择"，不需要同步"方案"。
##
## ⚠️ `remote_proxy` 在多人模式下要建**两台**（同队时远端是队友，对面是 AI），
## 而 1v1 那套代码只认一个。所以真正的真源是 `remote_proxies` 数组，
## `remote_proxy` 留作"第一个"的别名。
func spawn_lan(player_pos: Vector3) -> void:
	Net.squad_bodies.clear()
	Net.squad_tombstones.clear()
	remote_proxies.clear()
	remote_proxy = null
	var plan := _lan_plan_now()
	Game.squad_units_per_side = BattleFormation.unit_count_per_side()
	var host_pos := world.spawn_point(-95.0, world.match_spawn_radius(), world.match_player_alt())
	var guest_pos := world.spawn_point_foe(host_pos,85.0,world.match_spawn_radius())
	var my_focus := host_pos if Net.local_team == 0 or plan.same_team else guest_pos
	var foe_focus := guest_pos if Net.local_team == 0 or plan.same_team else host_pos
	player_pos = my_focus

	# ---- 王牌战：一人一台，**没有编制也没有僚机**（本轮新增的那条路）----
	#
	# 判据只有一个真源：`plan.is_ace_duel()`（= 两人都选了"王牌战"这形式）。
	# 它在这里**先判**，因为下面那一整套都是"按编制撒人"，王牌战里一条都不适用。
	if plan.is_ace_duel():
		_spawn_lan_duel(plan, player_pos, foe_focus)
		_wire_net("王牌战（一人一台 · 1v1）")
		return

	# ---- 本机的站位与朝向 ----
	# 同队（两人并肩）：本机从 −95° 出发、朝向对面的 AI；
	# 不同队（互相对打）：保持原有"面对面"。
	var to_enemy := plan.same_team
	_place(player, my_focus, foe_focus)

	# ---- 我方名单 ----
	# `plan.host_team` / `plan.client_team` 是**两台机器各自视角**的两份名单，
	# 由 `Plan.local_is_host` 决定本机该用哪一份（不要自己去猜）。
	var lineups := _lan_canonical_lineups(plan)
	var mine: Array = lineups["mine"]
	# ⚠️ 名单里的 `human_seat` 是**本机视角**的（0 = 本机）。
	# 加入方那台机器上 `client_team` 的 0 号才是它自己 —— `local_team()` 已经处理了。
	_spawn_side(mine, 0, player_pos, foe_focus, true, true)

	# ---- 对面名单 ----
	# 同队时对面 = **另一阵营 + 它的 AI ACE**（全 AI，没有真人 —— 这正是用户说的
	# "系统补一个 AI ACE"）；不同队时对面 = 另一个真人的那份名单，
	# 里面那台 `owner_is_client` 会被换成**远端玩家的代理机体**。
	var theirs: Array = lineups["theirs"]
	_spawn_side(theirs, 1, foe_focus, player_pos, false, true)

	_wire_net("局域网对战 —— %s（%s）" % [
		Game.lan_status, "同队同乘" if plan.is_shared_pedal() else "常规出战"])


## **王牌战**（联机的第二种形式）：两人各一台，场上只有两台机。
##
## 与小队战的区别不是"人少"而是**没有编制**：没有量产编队、没有僚机、
## 没有"系统补的 AI ACE"（那是同队时才需要的东西），也没有飞行踏板 ——
## 对面就是**那一个真人**，由 `NetProxyBody` 代理。
##
## ⚠️ 两台机体的型号都取自**双方各自的选择**（`plan` 里的两份名单各一台），
## 所以菜单等双方选择到齐再出击（`Net.choices_ready()`）；
## 不等就出击的话，这里只能拿兜底机型建代理 —— 而"对面开的是哪台机"恰恰是
## 王牌战唯一的变量（小队战至少还有编制撑着）。
func _spawn_lan_duel(plan: LanPlan.Plan, player_pos: Vector3, foe_focus: Vector3) -> void:
	Game.squad_units_per_side = 1
	# 本机：正对战场中心（与世界其它模式同一套站位）
	_place(player, player_pos, foe_focus)
	# 对面那台：`enemy_lineup()` 只有一台，且**座位号已经标成 1**（远端），
	# 所以 `_spawn_side()` 会把它建成本机的 `NetProxyBody` 而不是跳过它。
	_spawn_side(plan.enemy_lineup(), 1, foe_focus, player_pos, false, true)


## 联机开局的网络接线（两条形式共用）。
##
## [param log_line] = 写进战斗日志的那句话（两种形式的说法不同）。
func _wire_net(log_line: String) -> void:
	# 告诉对面"我选了什么"（机体 + 阵营 + 形式）—— 对面据此重算同一份方案。
	#
	# ⚠️ 这里**再发一遍自己的选择**（握手包里已经发过一次）不是多余的：它是"开局那一帧
	# 的权威值"，用来覆盖"对面连上之前收到的那次可能过期 / 缺失"的情况。
	# 传的是 `Net.choice_of(...)` 而不是 `Game.*` —— 理由同 `_lan_plan_now()`：
	# 联机这条路里 `Game.active_side` 没人写过，直接传它会把阵营发成兜底值。
	Net.announce_suit(Net.choice_of("suit", Game.active_suit))
	# 阵营这一条要保底：`_choice` 与 `Game.active_side` **都**没值时（不走菜单的
	# 测试 / 探针路径）退回 0 = 马夫蒂，与改这行之前的行为逐位相同。
	var sd := Net.choice_of("side", Game.active_side)
	Net.announce_side(sd if sd >= 0 else 0)
	if not Net.remote_state.is_connected(_on_net_state):
		Net.remote_state.connect(_on_net_state)
	if not Net.remote_fire.is_connected(_on_net_fire):
		Net.remote_fire.connect(_on_net_fire)
	if not Net.remote_damage.is_connected(_on_net_damage):
		Net.remote_damage.connect(_on_net_damage)
	Game.log_event(log_line)


## 按**两个人的选择**算出这一局的部署方案（用户定的规则表，见 `LanPlan`）。
##
## ⚠️ 两台机器各算一遍，**结果必须一致**：
## 它只依赖"两人的选择"（阵营 + 机体 + **对战形式**），不依赖"谁是本机"、
## 也不依赖"谁是主机" —— 这是把规则做成纯函数的回报，
## 同步层因此只需要同步**选择**，不需要同步方案本身。
##
## 本机那一票读 `Net.choice_of()`（= 菜单真的发出去的那一份）、
## 对面那一票读 `Net.remote_*`（= 对面真的发过来的那一份）——
## 两条来自**同一组握手包**，所以两台机器手里的两个 `Choice` 必然一样。
##
## 拿不到对面的选择时（对面还没 announce）退回"不同阵营的正面对打"，
## 那正是 `LanPlan` 在"两人不同阵营"下的默认行为，不会崩也不会误判成同队。
func _lan_plan_now() -> LanPlan.Plan:
	var my_side := Net.choice_of("side", Game.active_side)
	if my_side < 0:
		my_side = BattleFormation.Side.MAFTY
	# ⚠️ **本机这一票从 `Net.choice_of()` 取，不从 `Game.*` 取** —— 完整理由见那个函数。
	# 一句话：`announce_choice()` 发出去的那一份才是"我选了什么"的真源，
	# 而 `Game.active_side` 在联机这条路里**从来没人写过**、`Game.active_lan_form`
	# 同理（恒为小队战）。拿 `Game.*` 组方案会让**本机那一票**与**对面收到的那一票**
	# 不是同一个值，于是两台机器按不同的 (host_side, client_side) 分配编制。
	# 兜底值仍传 `Game.*`：不走菜单的测试 / 探针（`suite_lan_spawn` 直接
	# `Game.active_suit = …` 再调本函数）逐位保持原行为。
	var mine := LanPlan.Choice.new(
		Net.choice_of("suit", Game.active_suit), my_side,
		Net.choice_of("form", Game.active_lan_form))
	var foe_side := _foe_side_of(null)
	# 对面那一票：三个字段都以 `Net.remote_*` 为准（−1 = 还没收到，退回兜底值）。
	var foe := LanPlan.Choice.new(
		Net.remote_suit if Net.remote_suit >= 0 else SuitProfile.Id.PENELOPE,
		Net.remote_side if Net.remote_side >= 0 else foe_side,
		Net.remote_form if Net.remote_form >= 0 else LanPlan.Form.SQUAD)
	# 本机是主机时：host = 我、client = 对面；否则反过来（`LanPlan` 不关心谁是谁，
	# 只关心"两人选了什么"，所以这里按 local_team 摆正位置即可）。
	var plan := LanPlan.build(mine, foe) if Net.local_team == 0 else LanPlan.build(foe, mine)
	# ⚠️ **王牌战必须知道自己是不是主机**：它的两份名单各只有一台，`enemy_lineup()`
	# 得据此挑"另一份"当对面（小队战那一路不读这个字段）。
	#
	# 顺带记一笔既有情况（**本轮不动它**）：`Plan.local_is_host` 此前**没有任何人写过**
	#（恒为 `true`），于是小队战在加入方那台机器上用的是"主机那份名单"。
	# 改它等于改一条已经在真机上跑过的部署路径，而这条路径**只有两台机器才能验**，
	# 所以这里只给王牌战写，小队战的取名单方式逐位保持原样。
	plan.local_is_host = (Net.local_team == 0)
	return plan


## 对面的阵营。同队判定已经在 `LanPlan` 里，这里只回答"另一半是谁"。
func _foe_side_of(plan) -> int:
	var my_side := Game.active_side
	if plan != null and plan is LanPlan.Plan:
		my_side = plan.host_side if Net.local_team == 0 else plan.client_side
	if my_side < 0:
		return BattleFormation.Side.FEDERATION
	return BattleFormation.Side.FEDERATION if my_side == BattleFormation.Side.MAFTY \
		else BattleFormation.Side.MAFTY


## 收到对手的状态快照 → 喂给代理机体。
##
## ⚠️ 多人模式下**可能有两台代理**（同队时远端是队友），所以按数组遍历；
## `remote_proxy` 只是"第一个"的别名（1v1 那套代码继续用它）。
func _on_net_state(pkt: Dictionary) -> void:
	var s := Net.unpack_state(pkt)
	for p: NetProxyBody in remote_proxies:
		if p != null and is_instance_valid(p):
			p.apply_state(s)


## 每帧把远端代理推向最近一份快照（`Phase.FIGHT` 调用，见 `_process`）。
##
## ⚠️ 这一条**不是可有可无的收尾**：`apply_state()` 只写"目标值"（`_want_*`），
## 真正让它"走过去"的是 `NetProxyBody.interp()`。没有这个每帧调用，
## 快照收得再多，代理也只是在原地不动 —— 与"快照根本发不出去"是**同一症状的
## 两条独立断线**，必须成对修（只修一条，现象照旧）。
##
## 单机 / 训练 / 挑战模式下 `remote_proxies` 是空数组，这一圈就是空转，
## 不碰网络层（那些模式一分流就完事，见 `net_session.gd` 文件头）。
func _tick_remote_proxies(delta: float) -> void:
	for p: NetProxyBody in remote_proxies:
		if p != null and is_instance_valid(p):
			p.interp(delta)


## 对手开火 → 在**他那台代理机体**的位置生成同样的弹丸（观感与声音）。
## 命中判定不在这里（见 NetSession 的文件头）。
func _on_net_fire(kind: String, origin: Vector3, dir: Vector3) -> void:
	if kind.begins_with("nu_fin_hit_"):
		var index:=int(kind.trim_prefix("nu_fin_hit_"))
		if is_instance_valid(player) and is_instance_valid(player.nu_systems) and index>=0 and index<6:
			player.nu_systems.fins[index].take_damage(clampf(dir.x,0,1000),remote_proxy)
		return
	if kind.begins_with("nu_fin_ai_"):
		var key:=kind.trim_prefix("nu_fin_ai_").rsplit("_",true,1)
		var ai=Net.squad_bodies.get(key[0]) if key.size()==2 else null
		var index:=int(key[1]) if key.size()==2 else -1
		if Net.role==Net.Role.HOST and is_instance_valid(ai) and is_instance_valid(ai.nu_systems) and index>=0 and index<6:
			ai.nu_systems.fins[index].take_damage(clampf(dir.x,0,1000),remote_proxy)
		return
	if not is_instance_valid(projectile_container()):
		return
	var shooter: FlightBody = remote_proxy if is_instance_valid(remote_proxy) else null
	if shooter == null:
		for proxy: NetProxyBody in remote_proxies:
			if is_instance_valid(proxy):
				shooter = proxy
				break
	if kind.begins_with("ai|"):
		var parts := kind.split("|")
		if parts.size() != 3: return
		shooter = Net.squad_bodies.get(parts[1])
		if not is_instance_valid(shooter): return
		kind = parts[2]
	if not is_instance_valid(shooter) or shooter.profile == null:
		return
	if kind.begins_with("gp03s_equip_"):
		shooter.gp03s_equip(kind.trim_prefix("gp03s_equip_"))
		return
	if kind.begins_with("tb_") and shooter.thunderbolt_systems!=null:
		shooter.thunderbolt_systems.remote_fire(kind,origin,dir);return
	if kind.begins_with("sazabi_"):
		preload("res://scripts/combat/sazabi_network.gd").receive(self,shooter,kind,origin,dir)
		return
	match kind:
		"saber_rush":
			shooter.melee_guard.remote_attack(shooter,player,dir)
		"saber_stop":
			shooter.abort_saber()
		"saber_parry":
			shooter.melee_guard.remote_parry(shooter)
		"saber_shield", "saber_shield_block":
			shooter.melee_guard.remote_shield(shooter,kind=="saber_shield_block")
		"melee_hit":
			shooter.abort_saber()
			if shooter.model_fsm!=null: shooter.model_fsm.interrupt_melee()
			shooter.melee_hit_reaction.trigger_direction(shooter,dir)
		"beam":
			var shot := Projectile.beam(projectiles, origin, dir, shooter, 0.0,
				shooter.profile.beam_color(), SuitProfile.RIFLE_DEFAULT_RANGE,
				shooter.profile.rifle_scale, shooter.profile.rifle_steady_speed)
			shot.visual_only = true
		"nu_jettison":
			if is_instance_valid(shooter.nu_systems):shooter.nu_systems.discard_equipment()
			return
		"zorin_barrier":
			if is_instance_valid(shooter.nu_systems):shooter.nu_systems.remote_minovsky()
			return
		"zorin_pak":
			var shot:=Projectile.spawn(projectiles,origin,dir,shooter,0.0,Color(1,.82,.42),Damage.Type.VULCAN,14000,1.5,1.5)
			shot.visual_only=true
		"nu_fin", "zorin_fin":
			var beam=preload("res://scripts/combat/funnel_beam.gd")
			beam.pulse(projectiles,shooter,origin,dir,0.0,Color(1,.83,.32),1.15,beam.remote_emitter(shooter,origin),true)
		"nu_bazooka":
			preload("res://scripts/combat/nu_bazooka.gd").spawn(projectiles,origin,dir,shooter,0.0)
		"bazooka":
			Missile.spawn(projectiles, origin, dir, player, shooter, 0.0, Missile.Trail.LOW)
		"missile":
			var trail:=Missile.Trail.HIGH if shooter.profile.id==SuitProfile.Id.NEUE_ZIEL else Missile.Trail.LOW
			Missile.spawn(projectiles, origin, dir, player, shooter, 0.0, trail)
		"gp03s_bazookas":
			shooter.bazooka_cd = 1.1
			shooter._gp03s_pose("bazooka")
			for slot in ["bazooka_L","bazooka_R"]:
				Missile.spawn(projectiles,shooter.global_transform * shooter.rig_anchor(slot),dir,player,shooter,0.0,Missile.Trail.LOW)
		"regz_battery":
			preload("res://scripts/combat/regz_weapons.gd").new().fire_battery(shooter,true)
		"cannon":
			preload("res://scripts/combat/beam_cannon.gd").launch(projectiles,shooter,shooter.cannon_muzzles(),null,0.0,shooter.profile.cannon_duration,shooter.profile.cannon_color(),shooter.profile.beam_cannon_radius)
		"gun":
			var shot := Projectile.vulcan(projectiles, origin, dir, shooter, 0.0)
			shot.visual_only = true
		"funnel":
			# 对手的导弹只需要看得见：给一个同样速度的普通弹丸即可
			Missile.funnel(projectiles, origin, dir, player, shooter, 0.0)
		"pod":
			# ★ GP03D 的集束弹仓（2026-10-11）：远端重建**同一套弹幕**，但 `damage` 归零 ——
			# 那一仓在开枪方那边已经结算过命中了，这边再算一次就是**双倍伤害**。
			# ⚠️ `plan` 传空数组 = "整仓都咬**本机玩家**"（`configure()` 里 `plan.is_empty()` 那一支）。
			var wave = preload("res://scripts/combat/gp03d_pod_salvo.gd").new()
			wave.configure(shooter, player, [])
			wave.damage = 0.0
			projectiles.add_child(wave)
		"wire":
			# ★ 露维杰露的线控炮（2026-10-11）：远端在**代理机体**上挂一副。
			# Remote arms retain their beams with zero damage and no interceptions.
			# Damage remains authoritative on the firing peer.
			# ⚠️ `configure()` 找不到臂骨就返回 false —— 那时**什么都不挂**（不崩、不报错）；
			# 所以那条 `else: arms.free()` 是必须的，少了它就是一个永远不动的空节点。
			var arms = preload("res://scripts/combat/neue_wire_arms.gd").new()
			arms.visual_only = true
			if arms.configure(shooter, player):
				projectiles.add_child(arms)
			else:
				arms.free()
		_:
			return # Unknown events must not silently become rifle shots.
	Audio.play_3d("funnel_fire" if kind in ["funnel","missile","bazooka","gp03s_bazookas","pod","nu_bazooka"] else ("beam_rifle" if kind in ["beam","nu_fin"] else "vulcan"), origin, -6.0)


## 对手打中了我 → 把这一发落在**我自己的**机体上（我的血条我维护）。
func _on_net_damage(amount: float, damage_type: int) -> void:
	if player != null and is_instance_valid(player):
		player.take_damage(amount, remote_proxy, damage_type)


func projectile_container() -> Node3D:
	return projectiles


## 剧情挑战（1.2）：按脚本一波一波地撒敌机。
##
## 第一波出杂兵、清空之后才刷下一波 —— 用户要的就是这个节奏：
## "当柯西遭遇阿利宙斯时候，阿利宙斯会先不出场，先出场两台古斯塔夫…
## 两台古斯塔夫都击杀之后，阿利宙斯才会从上方出场。"
func spawn_challenge(player_pos: Vector3) -> void:
	if Game.active_mission != null and Game.active_mission.chapter == 3:
		_chapter_three=preload("res://scripts/flight/chapter_three_controller.gd").new()
		_chapter_three.setup(self,Game.active_mission)
		add_child(_chapter_three)
		_chapter_three.deploy()
		return
	var enc := Game.active_challenge
	wave_units.clear()
	if enc == null:
		# 防御：没有脚本就退化成一场普通 1v1，而不是空场
		spawn_versus(player_pos)
		return
	var sea_target: Node3D = null
	if Game.active_mission != null and Game.active_mission.id == "M06":
		sea_target=get_tree().get_first_node_in_group("valiant_target")
		if is_instance_valid(sea_target): player_pos=sea_target.global_position+Vector3(-18000,3500,14000)
	Game.challenge_total = ChallengeScript.total_enemies(enc)
	Game.challenge_killed = 0
	Game.challenge_wave = 0
	_place(player, player_pos,
		sea_target.global_position+Vector3.UP*3500 if is_instance_valid(sea_target) else world.spawn_point_foe(player_pos, 85.0, world.match_spawn_radius()))
	# ★ 轮 54：**关卡里凡量产机都踩板出击**（老板 2026-09-30：「古斯塔夫出击的时候
	# 应该要踩着飞行踏板的」，追问后定口径为「剧情关**双方**量产机都配板」）。
	#
	# ## 为什么三侧里只需要补这一处
	#
	# 实测（`tools/_r54_pedal_probe.gd`，逐关打读数）表明板有三个来源，
	# 而**只有玩家这一侧是缺的**：
	#   · **敌机**：`_spawn_wave()` → `_attach_ai()`，后者的 `with_pedal` 默认 true
	#     ⇒ 各关波次里的梅萨 / 古斯塔夫**本来就有板**（M04 的佩涅罗佩是 ACE 机，
	#     被 `can_ride_pedal()` 挡掉 ⇒ 无板 —— 那正是「ACE 不可骑」在起作用）。
	#   · **友军**：`_spawn_mission_allies()` → `_spawn_side()`，编队领机在那边配板。
	#     M01 的玩家因此「顺带」有板 —— **但那是巧合**：`_spawn_side()` 只在
	#     「友军名单里含玩家那一格」时才处理他，不撒友军的关（M02 / M03）
	#     玩家就一直空手出击。
	#   · **玩家**：就是这一行。
	#
	# ## ⚠️ 必须在 `_place()` **之后**
	# `configure_pedal()` → `FlightPedal._align_to_rider()` 读的是骑手的
	# `model_bounds`（机体摆好位、模型量完才有值）—— `_attach_ai()` 那边
	# 有同一条注释。
	#
	# ## ⚠️ 幂等 ⇒ 与 M01 那一遍重复调用无害
	# `configure_pedal()` 第一行是 `if has_pedal(): return pedal_owner()`；
	# `_spawn_mission_allies()` 后面还会再走一次 `_spawn_side()`，两遍都到这里
	# 只会得到**同一块板**，骑手也不会重复登记。
	#
	# ## ⚠️ ACE 机在这里被自动挡掉
	# `spawn_with_pedal()` 内部判 `can_ride_pedal()`（柯西 / 佩涅罗佩 / 阿利宙斯为假）
	# ⇒ M04–M07 的玩家**一字不变**，只是这一行返回 null。
	#
	# ## ⚠️ 这一行只在「关卡」路径上
	# `spawn_challenge()` 只被 `Game.MatchMode.CHALLENGE` 走到（剧情关与挑战局共用它）
	# ⇒ 1v1 / 编队战 / 训练 / 联机的玩家出生**逐位不变**
	#（那几条路的玩家配板由 `_spawn_side()` 负责）。
	player.spawn_with_pedal()
	Game.challenge_wave_times.clear()
	_wave_started = Game.elapsed
	_spawn_wave(0)
	# ★ 轮 50：剧情关的**友军编队**（“开局三台马夫蒂踏板登场”）。
	#
	# ⚠️ 必须放在**波次之后**：波次是“今夜对面的人”，
	# 编队是“你身边的人” —— 先后决定了 `units_root` 里的树序，
	# 而 HUD 的目标列表按树序排：敌机在前、僚机在后。
	# ⚠️ 空波次不需要这里加守卫：`_spawn_wave()` 自己就有
	# `index >= enc.waves.size()` 的早退 ⇒ M01（`waves = []`）一架都不撒。
	if Game.active_mission != null:
		var _m: MS.Mission = Game.active_mission
		if _m.has_allies():
			_spawn_mission_allies(_m)


## ★ 轮 50：把剧情关的**友军编队**撒出来。
##
## 复用 `_spawn_side()` —— 与小队战**同一条撒人路径**（挂板 / 后座同乘 /
## 领机先建后座后建 / 玩家那一台不重建 全在那边）⇒
## “3 块板 × 每块 2 台 = 6 台”是白捡的，这里一行新逻辑都不写。
##
## ⚠️ `base_pos` 用**玩家的当前位置**，不是 `spawn_round()` 算出来的那一个。
## `spawn_challenge()` 刚刚 `_place()` 过玩家（城市地形会把原座标抬高） ⇒
## 用旧值会让整队僚机偏出去一截。
## ⚠️ `team = 0` + `is_mine = true`：`is_mine` 现在同时管**要不要接
## `_on_enemy_destroyed`**（见那边的注释）—— 友军**绝不能**接，
## 否则僚机一摔就把“夜袭达沃”判成通关。
func _spawn_mission_allies(m: MS.Mission) -> void:
	if player == null or not is_instance_valid(player):
		return
	var focus := world.spawn_point_foe(player.global_position, 85.0,
		world.match_spawn_radius())
	_spawn_side(m.allies(), 0, player.global_position, focus, true)


## ★ 轮 50：这一关的**出击方位角**（度）。
##
## 非剧情模式 ⇒ 恒为工程原来那个 **-95.0** ——
## 也就是说四种老模式的出生点**逐位不变**
##（`suite_round` 那一批出点断言一条都不动）。
## 剧情模式读 `Mission.spawn_angle_deg`
##（M01 = -95.0、M02 = 85.0 —— 两关一个从这头进、一个从对面进）。
##
## ⚠️ 为什么不在调用点直接写 `Game.active_mission.spawn_angle_deg`：
## `active_mission` 是**无类型**的 Variant，取字段就得处处加 `as MS.Mission`；
## 集中成一个函数后 “回退值”只有**一处**，可单点断言。
func mission_spawn_angle() -> float:
	var m: MS.Mission = Game.active_mission
	if m == null:
		return -95.0
	return m.spawn_angle_deg


## 撒第 `index` 波。出场位置在玩家**前方**的两侧 / 正上方（角度按波次配置给）。
func _spawn_wave(index: int) -> void:
	var enc := Game.active_challenge
	if enc == null or index >= enc.waves.size():
		return
	var wave: ChallengeScript.Wave = enc.waves[index]
	Game.challenge_wave = index
	Game.challenge_wave_remaining = wave.count
	_wave_started = Game.elapsed
	wave_units.clear()
	# ★ 轮 63-9 · D1：本关专属的敌机速度乘子（`Mission.enemy_speed_mult`）。
	# 只有剧情关能填它，而且默认 1.0 ⇒ 挑战 / 训练 / 对战 / 联机**一格不动**。
	var _mission_speed_mult: float = 1.0
	if Game.active_mission != null:
		var _am: MS.Mission = Game.active_mission
		_mission_speed_mult = _am.enemy_speed_mult
	var fwd := player.forward()
	for i in wave.count:
		# 单架就摆在正前方；多架左右对称分开（`spread_deg`）
		var off_deg := 0.0
		if wave.count > 1:
			off_deg = -wave.spread_deg + 2.0 * wave.spread_deg * float(i) / float(wave.count - 1)
		var along := world.match_spawn_radius() * 0.85
		var side := tan(deg_to_rad(off_deg)) * along
		var pos := player.global_position + fwd * along + player.right() * side
		pos.y = wave.altitude
		if Game.active_mission != null and Game.active_mission.id == "M06":
			var ship:Node3D=get_tree().get_first_node_in_group("valiant_target")
			if is_instance_valid(ship): pos=ship.global_position+Vector3(-2500+5000*i,wave.altitude,-2000)
		var ai := _attach_ai(wave.suit, pos, player.global_position, "Foe%d_%d" % [index, i])
		# M04 ends when Penelope's main hull is destroyed; no Odysseus escape.
		# Each AI owns a fresh profile, so other missions retain their core phase.
		if Game.active_mission != null and Game.active_mission.id == "M04" \
				and ai.profile.id == SuitProfile.Id.PENELOPE and ai.profile.form == 0:
			ai.profile.transform_hull_ratio = 0.0
			ai.profile.transform_to_form = -1
		if _mission_speed_mult != 1.0:
			ai.set_enemy_speed_mult(_mission_speed_mult)
		if wave.aggressive:
			# "从上方出场"的 BOSS：一出现就进入 ATTACK（压下来打），
			# 否则它会在高空慢慢悠悠地转一圈才俯冲 —— 那样"出场"就没气势了。
			ai.set_state(BanditAI.State.ATTACK)
		ai.destroyed.connect(_on_challenge_enemy_destroyed.bind(ai))
		wave_units.append(ai)
		if enemy == null:
			enemy = ai          # 兼容只认 `main.enemy` 的旧代码（HUD/测试）
	Game.log_event("挑战 · 第 %d 波：%s ×%d" % [index + 1, wave.suit_name(), wave.count])


## 挑战里掉了一架：本波清空就换下一波，最后一波清空就过关。
func _on_challenge_enemy_destroyed(_killer: Node3D, unit: Node3D) -> void:
	_notify_enemy_down(unit)
	if player == null or not is_instance_valid(player):
		return
	Game.challenge_killed += 1
	Game.challenge_wave_remaining = maxi(Game.challenge_wave_remaining - 1, 0)
	Game.log_event("击坠敌机（%d / %d）" % [Game.challenge_killed, Game.challenge_total])
	# ⚠️ 判"这一波清空了没有"用**计数器**，不查"场上还有没有活着的敌机"。
	# 后者受信号顺序影响：`destroyed` 发出的那一刻，这台机算不算"已阵亡"、
	# 会不会被延迟释放，都不确定 —— 于是"清空"这件事要么早一帧要么晚一帧。
	# 用户报的 bug（清掉两台古斯塔夫之后结算直接跳出来）就是这一帧之差：
	# `Game._evaluate_end()` 抢在刷下一波之前把胜负判成了 WIN。
	# 计数器是确定的：这一波该出几架、掉了几架，只有 main 知道。
	if Game.challenge_wave_remaining > 0:
		return
	var enc := Game.active_challenge
	if enc == null:
		return
	if Game.challenge_wave + 1 < ChallengeScript.wave_count(enc):
		_close_wave()
		_spawn_wave(Game.challenge_wave + 1)
		if player != null and is_instance_valid(player):
			var nxt: ChallengeScript.Wave = enc.waves[Game.challenge_wave]
			player.notice.emit("下一波：%s ×%d" % [nxt.suit_name(), nxt.count], 2.6)
			Audio.play_self("alarm_lock", -2.0)
	else:
		_close_wave()
		if Game.active_mission != null and not Game.active_mission.win_on_clear:
			Game.recheck_end()
			if Game.phase != Game.Phase.WIN:
				player.notice.emit("敌机已清除，继续完成攻击目标",3.0)
				return
		_finish_round()


# ============================================================ ★63-24 无限强化演习（ENDLESS）

## 演习开局：自选卡先落地（在 `spawn_round()` 里已施加到 profile）→ 摆位 → 第 1 波。
##
## 骨架照 `spawn_challenge()`，但**波次无限**：没有 `Encounter`、没有 `waves` 表，
## 每一波由 `EndlessScript.wave_suits()` 现算 ⇒ `Game.active_challenge` **恒为 `null`**。
##
## ⚠️⚠️ 正因为 `active_challenge` 恒为 null，`Game._evaluate_end()` 里那条
## "还有没刷出来的波次时不许判胜"的挑战守卫**在这里形同虚设**（它的第一个条件就不成立）
## ⇒ **必须**靠 `game.gd` 里新加的那条 `match_mode == ENDLESS: return` 兜住。
## 不兜的话：第一波清空的那一帧场上没有敌机 ⇒ 直接弹胜利结算（设计 §4.3 / §10 点名的最高风险处）。
func spawn_endless(player_pos: Vector3) -> void:
	wave_units.clear()
	_endless_rng.randomize()
	_endless_clear_t = 0.0
	Game.endless_phase = EndlessScript.Phase.WAVE
	Game.endless_wave = 0
	Game.endless_elapsed = 0.0
	Game.endless_wave_remaining = 0
	Game.endless_wave_total = 0
	Game.endless_hand.clear()
	# ★ 间歇轮那一组也要归零（`Game.reset()` 已经清过一遍，这里再清一次是**故意的**：
	# 这一组是"局面"而不是"上一局的残留"，两条路径都清 ⇒ 谁先谁后都不会漏）。
	Game.endless_hand_tier = 0
	Game.endless_hand_want = 0
	Game.endless_hand_got = 0
	Game.endless_focus = 0
	Game.endless_operating = false
	Game.endless_operate_secs = 0.0
	Game.endless_operate_idle = 0.0
	Game.endless_intermission_left = 0.0
	Game.endless_intermission_total = 0.0
	# 第 0 档（`t = 0` ⇒ 1.0）。之后由 `_tick_endless()` 每帧覆写。
	Game.endless_enemy_reinforce = EndlessScript.enemy_reinforce(0.0)
	# 玩家朝"对面"摆位 —— 与挑战同一条（先摆玩家、再按他的 forward() 撒波次）。
	_place(player, player_pos,
		world.spawn_point_foe(player_pos, 85.0, world.match_spawn_radius()))
	_spawn_endless_wave(1)


## 撒第 `n` 波（`n` **从 1 开始** —— 口径必须与 `EndlessScript.is_ace_wave()` 一致）。
##
## 摆位照 `_spawn_wave()`：都在玩家**前方**，多架左右对称分开压上来。
## 差别只有两处：① 阵容每波现算；② 强敌波（每 5 波）出的是 ACE 池。
func _spawn_endless_wave(n: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	wave_units.clear()
	Game.endless_wave = n
	Game.endless_phase = EndlessScript.Phase.WAVE
	var suits := EndlessScript.wave_suits(n, Game.endless_elapsed, _endless_rng)
	Game.endless_wave_total = suits.size()
	Game.endless_wave_remaining = suits.size()
	var fwd := player.forward()
	var along := world.match_spawn_radius() * 0.85
	for i in suits.size():
		# 单架摆正前方；多架左右对称分开（与 `_spawn_wave` 同一个形状）。
		var off_deg := 0.0
		if suits.size() > 1:
			off_deg = -34.0 + 68.0 * float(i) / float(suits.size() - 1)
		var side := tan(deg_to_rad(off_deg)) * along
		var pos := player.global_position + fwd * along + player.right() * side
		# 高度：**比玩家高 `ENEMY_ABOVE_PLAYER`**，并以 `ENEMY_START_ALT` 兜底 ——
		# 与 `WorldBuilder.spawn_point_foe()` 同一条口径。这样玩家贴海飞的时候
		# 也不会把敌机生成在山里 / 水面下；而玩家爬升时它们仍在头顶压下来。
		pos.y = maxf(ENEMY_START_ALT, player.global_position.y + WorldBuilder.ENEMY_ABOVE_PLAYER)
		var ai := _attach_ai(suits[i], pos, player.global_position, "Endless%d_%d" % [n, i])
		if EndlessScript.is_ace_wave(n):
			# 强敌波一出现就进入 ATTACK（压下来打）—— 与剧情关"从上空出场"的 BOSS 同款，
			# 否则 ACE 会先在高空慢慢转一圈才俯冲，"强敌波"的气势就没了。
			ai.set_state(BanditAI.State.ATTACK)
		ai.destroyed.connect(_on_endless_enemy_destroyed.bind(ai))
		wave_units.append(ai)
		if enemy == null:
			enemy = ai          # 兼容只认 `main.enemy` 的旧代码（HUD / 测试）
	var kind := "强敌" if EndlessScript.is_ace_wave(n) else "小波"
	Game.log_event("演习 · 第 %d 波（%s）×%d" % [n, kind, suits.size()])


## 演习里掉了一架：本波清空 ⇒ 进 `CLEARING`（1.2 s 收尾）⇒ 下一波。
##
## ⚠️ 判"这一波清空了没有"用**计数器**，不查"场上还有没有敌机" ——
## 理由与 `_on_challenge_enemy_destroyed()` 那段逐字相同：`destroyed` 发出时那台机
## 算不算"已阵亡"受信号顺序影响，于是"空场"这件事要么早一帧要么晚一帧。
## 计数器是确定的：这一波该出几架、掉了几架，只有 main 知道。
func _on_endless_enemy_destroyed(_killer: Node3D, unit: Node3D) -> void:
	_notify_enemy_down(unit)
	if player == null or not is_instance_valid(player):
		return
	Game.endless_wave_remaining = maxi(Game.endless_wave_remaining - 1, 0)
	if Game.endless_wave_remaining > 0:
		return
	# 本波清空 ⇒ 收尾过渡。**这里不发下一波**：刷怪交给 `_tick_endless()`，
	# 这样"清空 → 下一波"之间必然隔着 `CLEARING_SECS` 秒（设计 §4.1 给 CLEARING
	# 单开一个状态的理由就是这段收尾）。
	Game.endless_phase = EndlessScript.Phase.CLEARING
	_endless_clear_t = 0.0
	Game.log_event("演习 · 第 %d 波清空" % Game.endless_wave)
	player.notice.emit("第 %d 波清空" % Game.endless_wave, 2.0)
	Audio.play_self("alarm_lock", -2.0)


## 每帧推进演习的状态机（由 `_process` 的 `Phase.FIGHT` 分支驱动）。
##
## ## ⚠️ 总时长在这里累加，**不是** `Game.elapsed`
## 后者只在 `Phase.FIGHT` 累加，而演习的强度档要的是"从开局起连续走"的那一条
##（设计 §6.4 / §6.2 都专门点了这个名：用 `Game.elapsed` 算档位会让"拖延"变成
## 对自己有利的行为）。所以这里累加的是 `Game.endless_elapsed`。
##
## ## 状态机的两条出口
##   · `CLEARING` 走完 ⇒ **开间歇轮**（`_begin_endless_round()`），不再直接刷下一波；
##   · 间歇轮本身由 `_tick_endless_round()` 推（**同一个 `_process` 帧里、紧接着**）——
##     拆成两个函数只因为"波次在不在过渡"与"卡在不在选"是两个各自独立的钟。
##
## ⚠️ 本函数**不管**间歇轮的分支：它每帧照旧累加时长、覆写强化系数，
## 于是"玩家在选卡期间总时长照样连续走"这件事天然成立
##（而这一条正是 `bonus_picks()` 门槛不可拖延的前提，见 §7.2 的边界表）。
func _tick_endless(delta: float) -> void:
	if not Game.is_endless():
		return
	Game.endless_elapsed += delta
	# 敌机强化系数**每帧覆写**（这是它唯一的写入口）——
	# 不留"忘了更新"的路径，也不会把上一局的残留值带进非演习模式。
	var previous_reinforce := Game.endless_enemy_reinforce
	Game.endless_enemy_reinforce = EndlessScript.enemy_reinforce(Game.endless_elapsed)
	# Existing wave members must gain the same time tier as newly spawned enemies.
	# Scale damage only: do not reapply difficulty, heal, or reset AI skill state.
	if not is_equal_approx(previous_reinforce, Game.endless_enemy_reinforce):
		var ratio := Game.endless_enemy_reinforce / maxf(previous_reinforce, 0.0001)
		for unit in wave_units:
			if is_instance_valid(unit) and unit is BanditAI and unit.alive:
				unit.damage_mult *= ratio
	if Game.endless_phase == EndlessScript.Phase.CLEARING:
		_endless_clear_t += delta
		if _endless_clear_t >= EndlessScript.CLEARING_SECS:
			_endless_clear_t = 0.0
			# ⚠️ 只有**这一局还活着**的时候才开下一轮：玩家在这 1.2 s 收尾里被流弹打死的话
			# `Game.phase` 已经是 `LOSE`，而 `_tick_endless_round()` 是由 `_process` 的
			# `Phase.FIGHT` 分支驱动的 ⇒ 开出来的那一轮**永远走不动**：
			# 倒计时不走、超时自动选也不触发，选卡面板就一直挂在状态里
			#（虽然被结算页盖住看不见，但状态是脏的 —— 下一局得靠 `Game.reset()` 兜）。
			if Game.phase == Game.Phase.FIGHT:
				_begin_endless_round(Game.endless_wave)


## ★63-24：清空第 `cleared_wave` 波之后**开一轮三选一**（设计 §7）。
##
## 轮型与张数都走 `EndlessScript` 的纯函数（**不是副本**）——
## 于是"第 5 波之后是奖励轮、给几张"这类口径能在无头里逐条喂边界值钉死：
##   · `round_phase(w)`    普通轮 `INTERMISSION` / 强敌波之后 `BONUS`
##   · `round_picks(w, t)` 普通轮恒 1；奖励轮按**局内总时长**给 1 / 2 / 3
##
## ⚠️ 品质走 `tier_for(w, roll, has_radical)`：奖励轮**强制 PERFECT**（§2.2）。
## `has_radical` 读的是"玩家**已持有**一张激进"（不是"曾出现过"）——
## 所以必须拿**本局已拿到的卡**去问，不能问菜单里选了什么。
func _begin_endless_round(cleared_wave: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	Game.endless_phase = EndlessScript.round_phase(cleared_wave)
	var have := _owned_cards()
	Game.endless_hand_tier = EndlessScript.tier_for(cleared_wave, _endless_rng.randf(),
		EndlessScript.player_has_radical(have))
	Game.endless_hand.clear()
	Game.endless_hand.append_array(EndlessScript.draw_hand_ids(
		Game.endless_hand_tier, _endless_rng, player.profile, have))
	Game.endless_hand_want = EndlessScript.round_picks(cleared_wave, Game.endless_elapsed)
	Game.endless_hand_got = 0
	Game.endless_focus = 0
	Game.endless_operate_secs = 0.0
	# ⚠️⚠️ 开局把 `idle` 钉在**宽限值本身**（不是 0）。
	# `intermission_step()` 的算法是 `idle = 0 if pressed else idle + delta`，
	# 而 `operating = idle < OPERATE_GRACE`。起点写 0 的话，**开局那 0.6 s 会被判成
	# "玩家正在操作"** ⇒ 倒计时凭空停 0.6 s，还往 `operate_secs` 里记 0.6 s 假账
	#（下一张卡选定后会把这 0.6 s **还回去**）⇒ 每轮白送 0.6 s。
	Game.endless_operate_idle = EndlessScript.OPERATE_GRACE
	Game.endless_operating = false
	Game.endless_intermission_total = EndlessScript.INTERMISSION_BASE
	Game.endless_intermission_left = EndlessScript.INTERMISSION_BASE
	# 选卡期间**禁控**（`PlayerController._think()` 的哨兵段）：
	#   ① `switch_target`（Tab）平时是"切换锁定 / 长按加入锁定组"，两件事不能同时发生；
	#   ② 波刚清空，场上没有目标，"开着操纵"除了让机体飘走没有任何意义；
	#   ③ 这条门是**工程既有**的约定（结算 / 暂停 / 锁内都走它），不是为这一屏新造的开关。
	# 轮结束时由 `_finish_endless_round()` 放开。
	player.controls_enabled = false
	Game.log_event("演习 · 第 %d 波清空 ⇒ %s 选卡 ×%d"
		% [cleared_wave, UpgradeCard.TIER_NAMES[Game.endless_hand_tier],
			Game.endless_hand_want])
	player.notice.emit("强化 %d 选 %d  ——  Tab 切换 / Enter 选定"
		% [Game.endless_hand.size(), Game.endless_hand_want], 2.6)


## ★63-24：间歇轮**每帧**推进（由 `_process` 的 `Phase.FIGHT` 分支紧接 `_tick_endless()` 调）。
##
## ## 时序：**先读输入、再走钟**
## 反过来的话，玩家这一帧按下的选定会被"这一帧的倒计时"先消耗一次
##（`operating` 是**上一帧**的读数）—— 表现是"选了卡但时间也少了一格"。
## 当前这个顺序下，按下的那一帧一定先把 `idle` 清零、再判 `operating`。
##
## ## 超时（§7.2 边界表第 1 行）
## 一直不动 ⇒ 10 s 到 ⇒ `auto` = **当前焦点那张**，**不惩罚、不阻塞**：
## 玩家哪怕全程走开，流程也一定往前走。这条由 `intermission_step()` 保证
##（`auto = clampi(focus, 0, size-1)`），main 这边只负责把它选掉。
func _tick_endless_round(delta: float) -> void:
	if not Game.is_endless():
		return
	if not _in_endless_round():
		return
	if player == null or not is_instance_valid(player):
		return
	# ---- ① 读输入（键鼠 / 手柄 / 鼠标点选三条路，见 `_read_endless_round_input`）----
	var act := _read_endless_round_input()
	if int(act["step"]) != 0:
		Game.endless_focus = EndlessScript.cycle_focus(
			Game.endless_focus, Game.endless_hand.size(), int(act["step"]))
	var pick := int(act["pick"])
	if pick >= 0:
		_take_endless_card(pick)
		# `_take_endless_card()` 可能已经把这一轮收掉了（拿满 / 手牌空）
		# ⇒ 这时已经不是间歇轮了，别再拿旧局面去喂倒计时。
		if not _in_endless_round():
			return
	# ---- ② 走钟 ----
	var step := EndlessScript.intermission_step(Game.endless_intermission_left, delta,
		bool(act["pressed"]), Game.endless_operate_secs, Game.endless_operate_idle,
		Game.endless_focus, Game.endless_hand.size())
	Game.endless_intermission_left = float(step["left"])
	Game.endless_operate_secs = float(step["secs"])
	Game.endless_operate_idle = float(step["idle"])
	Game.endless_operating = bool(step["operating"])
	# ---- ③ 到点 ⇒ 替玩家选掉焦点那张 ----
	if bool(step["expired"]):
		var auto := int(step["auto"])
		if auto >= 0:
			Game.log_event("演习 · 选卡超时 ⇒ 自动选第 %d 张" % (auto + 1))
			_take_endless_card(auto)
		else:
			_finish_endless_round()


## 现在是不是正卡在一轮选卡里（`INTERMISSION` 或 `BONUS`）。
##
## 抽出来只因为它在 `_tick_endless_round()` 里出现了**三次** ——
## 那三次的判断条件必须完全一致（少一处就是"拿满之后又拿旧局面走了一帧钟"）。
func _in_endless_round() -> bool:
	return Game.endless_phase == EndlessScript.Phase.INTERMISSION \
		or Game.endless_phase == EndlessScript.Phase.BONUS


## ★63-24：间歇轮的输入。返回 `{pressed, step, pick}`：
##   `pressed` 这一帧**有没有动过**（喂给倒计时的暂停判定）
##   `step`    焦点位移（−1 / 0 / +1）
##   `pick`    要选的下标（−1 = 这一帧不选）
##
## ## 键位（设计 §7 没定，这一版定下来）
##   · **Tab**（`switch_target`）循环焦点 · **Shift + Tab** 反向
##   · **Enter / 小键盘 Enter / 手柄 A**（`confirm`）选**焦点**那张
##   · **鼠标左键**点在哪张上就选哪张（`intermission_hit()` 判命中）
##   · **手柄十字键 ←/→**（`ui_left` / `ui_right`）也循环焦点 —— 手柄上 `switch_target`
##     是十字键 ↑，只用它的话"往回翻"没有键可用
##
## ## ⚠️ 为什么**不用 `Space`**
## `Space` 在本工程是 `fire_gun`（`input_setup.gd` 的键位表里 `fire_gun = [KEY_SPACE]`）。
## 一个键同时管"开火"和"确认"，正是本工程反复点名的那种"两件事共用一个键"——
## 手感上会变成"选卡顺手打出一发"。`confirm` 已经把键盘 + 手柄都盖全了，不需要它。
##
## ## ⚠️ `pressed` 的口径是"**做了会改变局面的动作**"
## 光标乱飘（鼠标移动）不算 —— 否则玩家一晃鼠标倒计时就永远不走。
## 只认"循环焦点 / 选定"这两种真的在决策的动作。
func _read_endless_round_input() -> Dictionary:
	var pressed := false
	var step := 0
	# ---- 键盘 / 手柄：循环焦点 ----
	if Input.is_action_just_pressed("switch_target"):
		pressed = true
		step = -1 if Input.is_key_pressed(KEY_SHIFT) else 1
	if Input.is_action_just_pressed("ui_left"):
		pressed = true
		step = -1
	elif Input.is_action_just_pressed("ui_right"):
		pressed = true
		step = 1
	# ---- 选定 ----
	var pick := -1
	if Input.is_action_just_pressed("confirm"):
		pressed = true
		pick = Game.endless_focus
	# ---- 鼠标：点哪张选哪张（自己量边沿，见 `_endless_lmb_held`）----
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if lmb and not _endless_lmb_held and hud != null:
		pressed = true
		pick = hud.intermission_hit(hud.size, Game.endless_hand.size(),
			hud.get_local_mouse_position())
	_endless_lmb_held = lmb
	return {"pressed": pressed, "step": step, "pick": pick}


## ★63-24：选定第 `idx` 张手牌。
##
## 四件事，缺一不可：
##   ① 记账（`endless_owned` + **平行的** `endless_owned_tier`）；
##   ② **耗时回补**（§7.2 读法 A：把这一段操作暂停掉的秒数**加回**剩余时间）；
##   ③ 卡**立刻生效**（整批重算 profile + 把新读数抄进机体）；
##   ④ 判这一轮收没收（拿满 / 手牌空）⇒ 收则 `_finish_endless_round()`。
##
## ## ⚠️ 为什么这里要补一句 `refresh_profile_stats()`
## `FlightBody._ready()` 把 `profile.hull_hp` / `ifield_hp` / `rifle_count` /
## `repair_packs` 这一批**抄进了自己的字段**，之后**再也不看 `profile`**
##（`flight_body.gd:904` 一带）。⇒ 只改 `profile` 的话，"装甲卡的加血一个点都不生效"，
## 而"伤害 / 间隔"那类每次现读 `profile` 的卡全都正常 —— 典型的静默半失效。
## `_apply_endless_cards()` 之后必须把新读数重抄一次。
##
## ## ⚠️ 回补的量是**这一整段**（不是"这一次按键"）
## `refund_time()` 收的是 `endless_operate_secs`（累计暂停秒数），而它在每次选定后
## **清零**重记 ⇒ 奖励轮选 2/3 张时是"每选一张各回补一次"，不是"只在最后还一次"。
func _take_endless_card(idx: int) -> void:
	if idx < 0 or idx >= Game.endless_hand.size():
		return
	if player == null or not is_instance_valid(player):
		return
	var cid: String = Game.endless_hand[idx]
	var tier := Game.endless_hand_tier
	Game.endless_hand.remove_at(idx)
	Game.endless_owned.append(cid)
	Game.endless_owned_tier.append(tier)
	Game.endless_hand_got += 1
	Game.endless_intermission_left = EndlessScript.refund_time(
		Game.endless_intermission_left, Game.endless_operate_secs)
	Game.endless_operate_secs = 0.0
	Game.endless_operate_idle = EndlessScript.OPERATE_GRACE
	# 手牌短了一张 ⇒ 焦点可能越界（原本停在最后一张）。收进合法区间，
	# 不然"超时自动选"会拿到一个空下标（`intermission_step` 会 clamp，
	# 但焦点本身也要跟着收 —— HUD 那圈高亮画的就是它）。
	Game.endless_focus = clampi(Game.endless_focus, 0,
		maxi(Game.endless_hand.size() - 1, 0))
	# 卡**立刻**生效：整批重算 + 重抄读数。
	_apply_endless_cards(player.profile)
	player.refresh_profile_stats()
	var card := UpgradeCard.by_id(cid, tier)
	var label: String = card.name if card != null else cid
	Game.log_event("演习 · 强化 %s（%s）⇒ 第 %d 张"
		% [label, UpgradeCard.TIER_NAMES[tier], Game.endless_owned.size()])
	player.notice.emit("强化 %s · %s" % [label, UpgradeCard.TIER_NAMES[tier]], 2.2)
	Audio.play_ui("ui_confirm")
	if EndlessScript.round_done(Game.endless_hand_got, Game.endless_hand_want,
			Game.endless_hand.size()):
		_finish_endless_round()


## ★63-24：收掉这一轮 ⇒ **放开操作**并刷下一波。
##
## ⚠️ 下一波的编号是 `endless_wave + 1`：`endless_wave` 在整个间歇轮里**保持**
## 刚清空的那一波（`_spawn_endless_wave()` 只在真的刷出来时才改它）
## ⇒ 这里 +1 与原来那一行**逐位相同**，不是新口径。
func _finish_endless_round() -> void:
	Game.endless_hand.clear()
	Game.endless_hand_tier = 0
	Game.endless_hand_want = 0
	Game.endless_hand_got = 0
	Game.endless_focus = 0
	Game.endless_operate_secs = 0.0
	Game.endless_operate_idle = EndlessScript.OPERATE_GRACE
	Game.endless_operating = false
	Game.endless_intermission_left = 0.0
	Game.endless_intermission_total = 0.0
	if player != null and is_instance_valid(player):
		player.controls_enabled = true
	_spawn_endless_wave(Game.endless_wave + 1)


## 把**本局已拿到的卡**整批施加到 `profile` 上（设计 §5.5）。
##
## ## ⚠️ 幂等的正解是"整批重算"，不是"增量乘一遍"
## `EndlessScript.apply_run()` 先把 `profile` 逐字段**还原成出厂值**、再按 `cards`
## 施加 ⇒ 同一张卡拿两次不会乘两次。增量施加做不到这一点，而且**回滚不了**
##（本模式一局可能几十张卡）。所以将来每拿到一张新卡，**重新调一次本函数**即可。
##
## ⚠️ **品质必须逐张按 `Game.endless_owned_tier` 取**，不能一律写 `BASIC`。
## `UpgradeCard.id` 是**词条名**（`"rifle_dmg"`），同一个词条在四个档各有一张卡
## ⇒ 一律按 `BASIC` 反查的话，"局内抽到的那张完美卡"会在施加时**静默退化成基础档**
##（`by_id()` 的头注点名的正是这一条）。两个数组同长同序，按下标成对读即可。
##
## ⚠️ `factory` 必须是**同一机体**的另一份出厂实例：`SuitProfile.by_id()` 每次都
## `new` 一份干净的，所以随手再取一份就是出厂值（`apply_run()` 的头注写明了这条前提）。
##
## ⚠️ 卡的 `apply` **只写 `profile` 这一份实例**（不碰任何节点、不碰静态表）
## ⇒ 敌机那一边各自的 `SuitProfile.by_id()` 实例一格不动（判据 `NO_LEAK`）。
## 这一条是硬要求：`SuitProfile.Id` 是共享的名字，梅萨 M01 既是玩家可选机、
## 也是演习里的量产敌机 —— 误改静态表就会"连敌人一起强化"。
func _apply_endless_cards(profile: SuitProfile) -> void:
	if profile == null:
		return
	var cards: Array[UpgradeCard] = []
	for c: UpgradeCard in _owned_cards():
		cards.append(c)
	EndlessScript.apply_run(profile, SuitProfile.by_id(profile.id), cards)


## 本局已持有的卡（**带品质**）—— `Game.endless_owned` / `endless_owned_tier`
## 按下标成对还原成 `UpgradeCard`。
##
## ⚠️ 两个数组**只要有一个短了**（不该发生）⇒ 短的那几张退回 `BASIC`。
## 这里刻意**不报错也不补齐**：`_apply_endless_cards()` 是每拿一张卡都要跑的路径，
## 为一条不该出现的情况在这里抛异常，代价是"一局直接崩掉"。
## 真正该盯的是"写的时候有没有成对写"—— 那一条由判据（源码扫描）钉住。
func _owned_cards() -> Array[UpgradeCard]:
	var out: Array[UpgradeCard] = []
	for i in Game.endless_owned.size():
		var tier := UpgradeCard.Tier.BASIC
		if i < Game.endless_owned_tier.size():
			tier = Game.endless_owned_tier[i]
		var c := UpgradeCard.by_id(Game.endless_owned[i], tier)
		if c != null:
			out.append(c)
	return out


## 对手池：玩家开哪台，敌机就从剩下的里挑第一台。柯西 ↔ 佩涅罗佩仍是默认的一组。
static func versus_opponent_of(player_suit: int) -> int:
	for id: int in [SuitProfile.Id.PENELOPE, SuitProfile.Id.XI, SuitProfile.Id.ARIZEUS]:
		if id != player_suit:
			return id
	return SuitProfile.Id.PENELOPE


## 训练模式：靶场 + 四架古斯塔夫00靶机。
##
## 靶机**不还手**（`TargetDrone` 里根本没有开火代码），所以在训练局里
## 玩家不会听到"被锁定"的警报，也不会有导弹来袭 —— 这正是"训练"的含义：
## 只有自己在打靶，没有对手在打你。
func spawn_training(player_pos: Vector3) -> void:
	var suit := SuitProfile.gustav00()
	targets.clear()
	# 玩家朝场地中心摆位：靶机绕中心跑道飞，出生就看得见它们
	_place(player, player_pos, Vector3(0, TRAINING_PATROL_ALT, 0))
	Game.training_targets_total = TRAINING_TARGETS
	for i in TRAINING_TARGETS:
		var ang := TAU * float(i) / float(TRAINING_TARGETS) + 0.55
		var center := Vector3.ZERO
		var pos := center + Vector3(cos(ang), 0.0, sin(ang)) * TRAINING_PATROL_RADIUS \
			+ Vector3(0, TRAINING_PATROL_ALT, 0)
		var d := TargetDrone.new()
		d.name = "Target%d" % i
		d.team = 1
		d.profile = suit
		d.display_name = suit.display_name
		d.projectile_container = projectiles
		d.patrol_center = center
		d.patrol_altitude = TRAINING_PATROL_ALT
		d.patrol_radius = TRAINING_PATROL_RADIUS
		d.phase = ang
		# 无限血（1.2 第二十六轮）：**新手教学**时靶机打不爆 ——
		# 玩家练提前量 / 连发时靶机不会中途消失，教学也不会被"靶机全灭"提前结束。
		# 自由打靶照旧一梭子一架（这里不放开，两回事）。
		d.invincible = Game.tutorial_mode
		units_root.add_child(d)
		# ⚠️ 必须摆位。只算 pos 而不赋值的话，靶机会停在原点（高度 0），
		# 第一个物理帧就触发"撞海"全灭 —— 训练模式一开局就"靶机全没了"。
		d.global_position = pos
		# 机头沿圆周切向（90° 偏航），这样一出生就在"跑道"上而不是横着飘
		var tangent := Vector3(-sin(ang), 0.0, cos(ang))
		if pos.distance_squared_to(player_pos) > 1.0:
			d.look_at(pos + tangent, Vector3.UP)
		# ⚠️ 靶机**刻意不跟** `SuitProfile.spawn_speed()`：古斯塔夫00 的失速线
		#（×2.4 下 99.8 m/s）离 240 很远，提速不会把它推进失速；
		# 而"靶机绕圈跑多快"是**训练关自己的设定**，不该被主力机体的提速带着走。
		d.fm.speed = 240.0
		d.fm.throttle = 0.72
		d.fm.align_velocity(d.forward())
		d.destroyed.connect(_on_target_destroyed)
		targets.append(d)
	Game.log_event("训练开始 —— 靶机 ×%d" % TRAINING_TARGETS)


func _clear_match() -> void:
	if is_instance_valid(_chapter_three):
		_chapter_three.cleanup()
		_chapter_three.free()
	_chapter_three=null
	if is_instance_valid(_sortie_director):
		_sortie_director.cleanup(false)
		_sortie_director.free()
	_sortie_director=null
	if is_instance_valid(_davao_director):
		_davao_director.cleanup(false)
		_davao_director.free()
	_davao_director = null
	if _strike_view_restore != null:
		Settings.first_person=bool(_strike_view_restore)
		_strike_view_restore=null
	if is_instance_valid(_strike_director):
		_strike_director.cleanup()
		_strike_director.free()
	_strike_director=null
	for c: Node in units_root.get_children():
		c.free()
	for c: Node in projectiles.get_children():
		c.free()
	# 每台 AI 敌机的锁定系统都要清掉（多敌机之后 `enemy_lock` 只是"第一台"的别名，
	# 只清它的话，挑战局里第二台之后的导引头会一直挂在树上）。
	for l: Node in ([player_lock, enemy_lock] as Array[Node]) + (_ai_locks as Array[Node]):
		if l != null and is_instance_valid(l):
			l.free()
	# 死亡锚点是击坠后为了钉住镜头才建的，重开时必须清掉，
	# 否则每重开一局就多留一个，而且镜头可能还挂在旧锚点上
	if _death_anchor != null and is_instance_valid(_death_anchor):
		_death_anchor.free()
	_death_anchor = null
	# follow_lag 在玩家阵亡时被放慢到 2.2 让爆炸演完，重开必须还原，
	# 否则新一局的镜头会一直黏糊糊地吊在机体后面
	if chase != null:
		chase.follow_lag = 6.5
		# ★ 镜头也必须**从发射段机位切回战斗机位**：
		# 发射段把 offset / look_ahead / look_up / roll_blend 四个值换掉了，
		# 不还原的话下一局玩家会从一个"离机体 175 m、抬头 4°"的机位开打
		#（那是给静立在水里的火箭配的）。`set_launch_view(false)` 里有"没切过就空转"的
		# 早退，所以每局重开都调它是安全的。
		chase.set_launch_view(false)
	player_lock = null
	enemy_lock = null
	player = null
	enemy = null
	targets.clear()
	wave_units.clear()
	_ai_locks.clear()
	# ★ 轮 57：演出的四件状态也要清 —— 不清的话"重来一关"会带着上一局的秒数
	# 继续演，而 `_strike_foe` 还会指着一台已经被 free 掉的机体。
	_strike_t = 0.0
	_strike_beam = null
	_strike_foe = null
	_strike_cut = false
	_strike_pod = null
	_strike_pod_tag = null
	_strike_pod_home = Vector3.ZERO
	_strike_bgm_live = false


func _place(unit: FlightBody, pos: Vector3, look_target: Vector3) -> void:
	unit.global_position = pos
	if pos.distance_squared_to(look_target) > 1.0:
		unit.look_at(look_target, Vector3.UP)
	unit.fm.speed = SuitProfile.spawn_speed()
	unit.fm.throttle = 0.78
	unit.fm.align_velocity(unit.forward())


# ============================================================ 流程

## 输入设备切换。提示文案本身是"读的时候现取"（InputSetup.hint），
## 这里只负责告诉玩家"换了"，否则玩家会以为自己按错了键。
func _on_input_device_changed(using_pad: bool) -> void:
	if hud != null:
		hud.push_notice("已切换到手柄操作" if using_pad else "已切换到键鼠操作", 1.8)


func _on_gamepad_connected(connected: bool) -> void:
	if hud != null:
		hud.push_notice("检测到手柄 · 已切换到手柄提示" if connected
			else "手柄已断开 · 已切回键鼠提示", 2.4)


func _process(delta: float) -> void:
	if not is_instance_valid(_story_skip):
		_story_skip=preload("res://scripts/ui/story_skip.gd").new();_story_skip.setup(self);add_child(_story_skip)
	if _transition_busy: return
	_handle_global_input()
	_update_camera_assist(delta)
	_update_cloud_shade()
	_tick_lock_probe(delta)
	_tick_alarms()
	_phase_lockout = maxf(_phase_lockout - delta, 0.0)
	# ★63-24：间歇轮的**鼠标左键闩**在这里跟住实际状态 —— 但**只在这一屏之外跟**。
	#
	# 不跟的话：在暂停菜单 / 结算页里点一下左键，闩会停在"按着"，
	# 下一次选卡的**第一下点击没有边沿**、被吞掉（表现是"要点两次才生效"）。
	#
	# ⚠️ 必须在 `if not get_tree().paused` **外面**：`main` 是
	# `PROCESS_MODE_ALWAYS`（`_ready` 里设的），暂停时 `_process` 照跑，
	# 这一行才有机会在暂停期间把闩放平。
	# ⚠️ 判据复刻的是"**这一帧 `_read_endless_round_input()` 会不会去量边沿**"：
	# 会量的那一帧不碰它（边沿是它量的），其余每一帧都把它放平。
	if not (_in_endless_round() and not get_tree().paused and phase == Phase.FIGHT):
		_endless_lmb_held = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# ★ 轮 E：剧情关的**触发器**（电台 / 结束任务）。
	# ⚠️ 放在 `if not get_tree().paused` **外面**，与 `hud.comms.tick()` 同一条理由：
	# 暂停（结算页 / 播片）不该把已经排好的台词吞掉。它自己会挡掉 `phase != FIGHT`。
	# ★ 轮 55：Zone 进入检测（必须在触发器**之前** —— 见该函数的注释）。
	if not get_tree().paused and phase == Phase.FIGHT and is_instance_valid(_chapter_three):
		_chapter_three.tick(delta)
	_tick_mission_zones()
	_tick_mission_triggers()

	if not get_tree().paused:
		match phase:
			Phase.MENU, Phase.CAMPAIGN, Phase.BRIEF:
				# ★ 轮 C：剧情模式的两页沿用菜单那条相机轨道 —— 它们的背景就是主菜单
				# 那张图，镜头停住不动反而像卡住了。
				_menu_orbit(delta)
			Phase.FIGHT:
				# ★ 批 2：远端玩家的代理机体**必须每帧**有人把它推向最近一份快照。
				# `NetProxyBody.interp()` 的注释早就写着"由 main 每帧调用"，只是一直
				# 没人接（全工程 `.interp(` 零调用方）—— 于是代理出生后就再没动过。
				# ⚠️ 放在 `if not get_tree().paused` **里面**：结算页把树暂停时，
				# 代理也该定住（它的位移只在 FIGHT 里有意义）。
				_tick_remote_proxies(delta)
				# ★63-24：无限强化演习的波次状态机（只有演习局做事，别的模式第一行就早退）。
				_tick_endless(delta)
				# ★63-24：间歇轮（局内三选一）。**必须紧跟在 `_tick_endless()` 之后**：
				# 前者负责"CLEARING 走完就开一轮"，后者负责"这一轮怎么走"——
				# 同一帧里先开再推，玩家看不到"开了一轮但钟不走"的那一帧。
				# 它自己会挡掉"不在间歇轮"的情况（`_in_endless_round()`）。
				_tick_endless_round(delta)
			Phase.SORTIE:
				if is_instance_valid(_sortie_director):_sortie_director.step(delta)
			Phase.LAUNCH:
				# ★ 发射段：一个显式驱动的状态（不写 `_process`，这样它能在单测里
				# 按固定 dt 复现整段上升 —— `RocketBody.step()` 与 `RocketFlame.update()`
				# 都是"显式 dt、显式调用"的）。
				# ⚠️ 换图那一段（`_swap_to_orbit()`）是**协程**，不在这里驱动 ——
				# 它自己 `await` 帧，这样"锁座舱 → 建图 → 放锁"的次序不依赖帧率。
				_tick_launch(delta)
			Phase.DAVAO_INTRO:
				if is_instance_valid(_davao_director):
					_davao_director.step(delta)
			Phase.POD_STRIKE:
				# ★ 轮 57：M04「重力」的开场演出。与发射段同一种路数 ——
				# 显式驱动（`_tick_pod_strike(delta)`），时间线数据在 `PodStrikeScript`。
				_tick_pod_strike(delta)
			Phase.RESULT:
				# 不再提供"再战一局"（用户要求撤掉）：结算之后只能回主菜单，
				# 重新选机体与难度。Enter / Esc 都是"回主菜单"。
				#
				# ★ 轮 C：剧情模式在**同一条路**上分了个岔 ——
				#   · 成功/失败都按 Enter / Esc ⇒ 回**战役图**（不是回主菜单）；
				#   · **失败**时多一个 `R` ⇒ 就地重开同一关（§6.7）。
				#   `R` 给的是"重来一关"，**不是**被撤掉的"再战一局"：后者是回菜单
				#   重选机体与难度，前者是同一台机、同一张图、同一套 profile。
				# 分岔的判据只有 `Game.sally_result`（空 = 四种现有模式，走老路）。
				var r_down := Input.is_key_pressed(KEY_R)
				var r_edge := r_down and not _restart_held
				_restart_held = r_down
				# 刚出结算的锁内不吃输入：玩家在击坠那一刻多半还按着开火/确认键。
				if _phase_lockout <= 0.0:
					if r_edge and _can_retry():
						Audio.play_ui("ui_confirm")
						_retry_campaign()
					elif Input.is_action_just_pressed("confirm") \
							or Input.is_action_just_pressed("menu_back"):
						Audio.play_ui("ui_return")
						if _in_campaign_result():
							# 回战役图（路上先播 🎬 D 槽的任务后片段，有片才播）。
							# `_open_campaign` 会重读盘 ⇒"下一关高亮"与军资余额都是
							# 刚结算完的那一份。
							_leave_campaign_result()
						else:
							_return_to_menu_loading()


## 云影（第十四轮）：把 `WorldBuilder` 烘出来的那张覆盖图**按每台机的世界坐标**
## 采一次，写进它的材质。
##
## 为什么在 `main` 里而不是各机体自己算：机体不认识 `WorldBuilder`
## （`FlightBody` 是纯飞行/战斗，场景树那半边归 main 管）。
## 遍历 `units_root` 的子节点即可 —— 玩家、敌机、训练靶机都在那儿，
## 于是"自机 + 敌机"一起被遮，正是老板选的那一档。
##
## 代价是每帧 3×N 次查表（N = 场上的机体数，通常 1~5），可忽略。
func _update_cloud_shade() -> void:
	if world == null:
		return
	for c: Node in units_root.get_children():
		var fb := c as FlightBody
		if fb != null and fb.alive:
			fb.set_cloud_shade(world.cloud_shade_at(fb.global_position))


func _start_fight() -> void:
	# ⚠️ **幂等**：1.2 起开局就是 FIGHT，而测试与探针里有好几处仍会显式调它
	# （它们当年是为了"跳过 INTRO"）。不设这道闸，重复调用会把 BGM 重起一遍、
	# 在事件流水里多记一条"战斗开始" —— 而这两件事都会让断言莫名其妙地红。
	if phase == Phase.FIGHT:
		return
	phase = Phase.FIGHT
	Game.set_phase(Game.Phase.FIGHT)
	# 训练模式固定使用 Sweet Child O' Mine，不读取出击音乐或歌单。
	if _strike_bgm_live:
		# Other cinematics may carry their battle track across the handoff.
		# M04 starts its mission track after the XI cinematic.
		_strike_bgm_live = false
	elif Game.match_mode == Game.MatchMode.TRAINING:
		Audio.lock_battle_track("")
		Audio.request_battle_open("")
		Audio.play_bgm(Audio.Bgm.TRAINING)
	else:
		# 战斗轮换池：**剧情挑战不含閃光**，对战/联机含它
		#（两套名单的唯一真源是 `SoundBank.STORY_BATTLE_TRACKS` / `BATTLE_TRACKS`，
		#  这里不写首数 —— 曲池会继续长）。
		# `set_story_mode()` 同时重置"这一局用过閃光"的标记，它决定结算曲（见 AudioDirector）。
		Audio.set_story_mode(Game.match_mode == Game.MatchMode.CHALLENGE)
		# 批 23 出击前自选：设置页「战斗BGM」行（"" = 随机）→ 本场开场曲。
		# 只注入、不校验 —— 曲池校验在 `AudioDirector.bgm_name()` 消费时做
		#（选中的曲不在本模式曲池里就自动退回随机，剧情池不含閃光就是这一路）。
		#
		# ★ 2026-10-01（轮 59）：**关卡自带曲优先于设置页自选**。
		# 老板：「TRACER 作为 M01 的 bgm」。
		# `Mission.bgm` 是**关卡作者**指定的（管整关、还会被锁住），
		# `Settings.battle_bgm_pick` 是**玩家**的「这一场我想拿哪首开头」（只管开场一首）
		# —— 作者指定盖过它，否则玩家把设置选成别的，这一关的曲子就没了。
		#
		# Mission music and dedicated suit themes loop throughout the battle.
		# The settings-page selection remains an opening track for all other suits.
		var want: String = Settings.battle_bgm_pick
		var lock_want := SoundBank.suit_battle_track(Game.active_suit)
		if lock_want != "":want = lock_want
		if Game.match_mode != Game.MatchMode.TRAINING and Game.active_mission != null and Game.active_mission.bgm != "":
			want = str(Game.active_mission.bgm)
			lock_want = want
		Audio.lock_battle_track(lock_want)
		Audio.request_battle_open(want)
		Audio.play_bgm(Audio.Bgm.BATTLE)
	Game.log_event("战斗开始" if Game.match_mode == Game.MatchMode.VERSUS else "训练开始")
	if player != null and is_instance_valid(player):
		player.controls_enabled = true
		if Game.match_mode == Game.MatchMode.TRAINING:
			player.notice.emit("靶机 ×%d —— 用鼠标罩住目标锁定" % Game.training_targets_total, 3.2)
		elif Game.match_mode == Game.MatchMode.CHALLENGE and Game.active_challenge != null:
			var enc := Game.active_challenge
			player.notice.emit("%s —— %s" % [enc.title, enc.brief], 3.4)
		elif Game.match_mode == Game.MatchMode.LAN:
			player.notice.emit("局域网对战开始 —— %s" % Game.lan_status, 3.2)
		else:
			player.notice.emit("敌机接近 —— 咬住它的尾巴", 2.6)


## 暂停只在 INTRO / FIGHT 里可用。
##
## ⚠️ 这里踩过一个很坑的 bug：`pause` 与 `menu_back` 都绑在 ESC 上。
## 原来这个方法对"非主菜单"的所有阶段都生效，于是**在结算页按 ESC 会同时**
## 把树暂停、并跳回主菜单。暂停状态没人清掉 → 从菜单开新一局时，
## 新机体是在**已暂停的树**里创建的：机体不动、空格不响应，
## 看起来就是"卡住"。树一暂停，整个 `match phase` 分支都不再执行。
## 1.2 起没有 INTRO 了（用户要求删掉"按空格出击"），所以暂停**只在 FIGHT 生效**；
## 结算页的 ESC 只负责回主菜单。
##
## 暂停期间输入**整个交给暂停菜单**（继续战斗 / 返回主菜单都在它那边），
## 这里不再自己 toggle —— 否则同一个 Esc 会被两边各读一次。
func _handle_global_input() -> void:
	if is_instance_valid(_story_skip) and _story_skip.blocks_input():return
	# ★★ 老板 2026-09-30：「**另外可以随便按F1切换火箭时候仓内的第一人称视角**」。
	# ⇒ F1 在**发射段**也生效。
	#
	# ⚠️ 它必须摆在下面那道 `phase != Phase.FIGHT` 早退**之前**：发射段的
	# `phase` 是 `Phase.LAUNCH`，早退之后按 F1 **一个字都不会发生** ——
	# 而它在画面上看起来是"按键坏了"，日志里一条异常都没有。
	#（这正是这一条需求之前的实况：发射段想换视角只能去设置页，而设置页只在主菜单里。）
	#
	# ⚠️ 这里只翻 `_launch_eye_cockpit`，**不碰 `Settings.first_person`** ——
	# 两个舱不是同一个舱，理由见那个变量的声明。
	if phase == Phase.LAUNCH and not _paused \
			and Input.is_action_just_pressed("toggle_fpv"):
		_launch_eye_cockpit = not _launch_eye_cockpit
		Audio.play_ui("ui_confirm")
	if phase == Phase.POD_STRIKE:
		if not _paused and Input.is_action_just_pressed("pause"):
			_set_paused(true)
		return
	if phase != Phase.FIGHT:
		return
	if _paused:
		return
	if Input.is_action_just_pressed("pause"):
		_set_paused(true)
	# 轮 25：**F1 = 第一人称 / 第三人称随时切换**（用户指定）。
	# 手柄那条同款入口是"长按 Back"，走 `player_controller._run_pad_hold()`，
	# 两条路都只调 `Settings.toggle_first_person()`。
	#
	# ⚠️ 位置就在上面两道 early-return **之后**，这是刻意的：
	#   菜单里按 F1 什么都不做（那儿的"座舱视角"没有意义，菜单镜头是 `_menu_orbit`）；
	#   暂停时也不做 —— 暂停期间输入整个交给暂停菜单，与 `pause` 同一套理由。
	#
	# 而且这里**只翻状态、不碰相机**：`_apply_camera_settings()` 每帧把
	# `Settings.first_person` 写进 `chase.first_person`，进出座舱的 0.2 s 渐变
	#（`ChaseCamera.FPV_RATE`）由它自己走完 —— 这正是"自由切换"该有的手感：
	# 不瞬移，也不会和别的入口打架（设置页那条路已经没有了）。
	if Input.is_action_just_pressed("toggle_fpv"):
		Settings.toggle_first_person()
	# 轮 31：**M = 中央屏切换**（雷达 / 机体剪影 / 等高线地形图，机主指定）。
	# 与 F1 同一条规矩：只翻状态、不碰绘制 —— HUD 每帧读
	# `Settings.effective_dash_screen()`，所以「下一帧就是新模式」，不存在「切了但要等某个信号」的中间态。
	#
	# ⚠️ 轮 35：**M 只在座舱视角有效**（机主：「第三人称模式下按 m 不能切换除了雷达
	# 以外的」）。门开在**入口**这里而不是 HUD 里：这样「按键无效」与「屏上恒为雷达」
	# 是两件各自成立、各自可断言的事，HUD 也不必每帧去判「这一下按键算不算数」。
	if Settings.first_person and Input.is_action_just_pressed("cycle_dash_screen"):
		Settings.cycle_dash_screen()


## 暂停/解除暂停的唯一入口。
##
## 界面与状态必须**同时**变：树暂停了但屏幕上什么都没有，玩家会以为游戏卡死；
## 而暂停菜单的开关也只在 main 这一处被驱动，不存在"菜单开了但树没停"的组合。
func _set_paused(v: bool) -> void:
	_paused = v
	if phase == Phase.POD_STRIKE:
		Audio.set_bgm_paused(v)
		if is_instance_valid(_strike_director):
			_strike_director.set_paused(v)
	get_tree().paused = v
	if pause_menu != null:
		if v:
			pause_menu.open_pause()
		else:
			pause_menu.close_pause()


func _on_pause_resume() -> void:
	_set_paused(false)


## 暂停菜单里选"返回主菜单"：丢下这一局回菜单重选机体与难度。
## `_show_menu()` 自己会把暂停清掉（顺序很关键：先 `_set_paused(false)` 再拆场景）。
func _on_pause_back_to_menu() -> void:
	Game.log_event("主动退出战斗")
	_return_to_menu_loading()


## 加速时的镜头表现：FOV 再拉高一截 + 屏幕速度线。两者都由 boost_intensity 驱动。
## 顺手把"锁定目标"喂给镜头：锁定镜头（Alt）要靠它才知道该盯谁。
func _update_camera_assist(delta: float) -> void:
	if phase in [Phase.POD_STRIKE, Phase.DAVAO_INTRO]:
		if speed_lines != null:
			speed_lines.set_intensity(0.0); speed_lines.set_dash(0.0)
		return
	_apply_camera_settings(delta)
	if player == null or not is_instance_valid(player):
		speed_lines.set_intensity(0.0)
		speed_lines.set_dash(0.0)
		if chase != null:
			chase.boost_amount = move_toward(chase.boost_amount, 0.0, delta * 3.0)
			chase.aim_target = null
			chase.set_lock_view(false)
		return
	var b := player.boost_intensity
	# 速度线也是"动态"的一种：设置里打开"降低动态"就一起关掉
	# （它是铺满屏幕的放射线，对晕动的人是最难受的那一层）。
	speed_lines.set_intensity(b * Settings.cam_motion_scale())
	# 冲刺（辅助闪避 QB / 超级加速）时速度线换一种形态。
	# 判据用的是 `FlightBody.is_dashing()` —— 与尾焰形态 A/B 是**同一份判断**，
	# 别在这里另写一遍 `translate_dash or super_boost`。
	speed_lines.set_dash(1.0 if player.is_dashing() else 0.0)
	chase.boost_amount = b
	# ⚠️ 不能直接写 `chase.aim_target = player_lock.target`：目标是**可能已被释放**的敌机，
	# 而 `aim_target` 是带类型属性（Node3D）—— 把已释放实例赋给它会抛
	# "Invalid assignment of property ... with value of type 'previously freed'"。
	# 锁定系统自己会在物理帧里清掉失效目标（`_validate_group`），
	# 但 `main._process` 可能**早于**那一帧读到它，所以每个读取点都得自己验。
	var aim: Node3D = null
	if player_lock != null:
		var t = player_lock.target
		if t != null and is_instance_valid(t):
			aim = t
	chase.aim_target = aim


## 把设置页里的镜头项写进相机（第十四轮 A4）。
##
## 每帧写一次而不是监听 `Settings.changed`：四个浮点 + 一个布尔赋值，
## 而信号要多一条连线、还要在 `_clear_match()` 里断开，得不偿失。
## 第一人称那两行（`first_person` 与自机模型的可见性）同理：
## 前者是个布尔、后者在 `FlightBody.set_model_visible()` 里做了幂等短路，
## 每帧调也不会白白发可见性通知。
## 注意它**必须早于 `_update_camera_assist` 里那些带 `player == null` 早返回的地方** ——
## 菜单里也在用同一个相机（`_menu_orbit`），设置要立刻生效。
func _apply_camera_settings(_delta: float) -> void:
	# An explicit F1 / gamepad view change supersedes the temporary M04 handoff.
	if _strike_view_restore != null and Settings.first_person:
		_strike_view_restore=null
	if chase == null:
		return
	# ⚠️ **发射段机位自己管 `roll_blend`** —— 它必须被压到 0，理由见
	# `ChaseCamera.set_launch_view()`（不压的话"一枚竖直上升的箭"配一条歪 58° 的地平线）。
	# 而本函数是**每帧**跑的（`_process` 里无条件调），无脑写 `Settings` 的值
	# 会把 `set_launch_view(true)` 刚写进去的 0 **在下一帧顶回去** ——
	# 于是那半个修复静默失效，画面上看不出"少了一行代码"，只觉得"运镜怪"。
	# 只跳过这一项：`shake_scale` / `motion_scale` / `first_person` 在发射段
	# 照样该听玩家的（晕动设置在该看云的那 40 秒里更该生效）。
	# ★ **发射段的眼位档**（贴近追尾 / 座舱）与玩家的 `first_person` 是**同一根线**：
	# F1 在两段里都是"第一人称开关"，只是发射段的"座舱"是那枚火箭的眼位
	#（舱内表现走 HUD 的全周天那一层，见 `_sync_cockpit_hud()`）。
	# ⚠️ 必须走 `set_launch_eye()`（它一并把机位 / 视线 / 滚转换掉），
	# 直接写 `chase.first_person` 只换了一半 —— 那半个改动的症状是
	# "玩家进了舱但镜头还在箭底下方 80 m"。
	if chase.launch_view():
		# ★★ 换图窗口**压着不还给玩家** —— 见 `_swap_eye_lock` 那一段。
		# ⚠️ 这个闩必须在这里判：本函数每帧跑，只调一次 `set_launch_eye(COCKPIT)`
		# 会被**下一帧按 `Settings.first_person` 顶回去**，而"遮住换图"就静默失效了。
		# ★ 眼位档的来源是**本段自己那一位**（F1 翻它），不再是 `Settings.first_person`。
		# `_swap_eye_lock`（换图窗口）仍然无条件压过它 —— 那 1.5 s 必须让人在舱里。
		chase.set_launch_eye(ChaseCamera.LaunchEye.COCKPIT
			if (_launch_eye_cockpit or _swap_eye_lock) else ChaseCamera.LaunchEye.CHASE)
	else:
		chase.roll_blend = Settings.cam_roll_blend()
		chase.first_person = Settings.first_person
	chase.shake_scale = Settings.cam_shake_scale()
	chase.motion_scale = Settings.cam_motion_scale()
	# ---- 第一人称要**藏起自机模型**（轮 20）----
	#
	# 座舱眼位在头部壳内，而这些机体是 AI 扫描的单层壳（没有内构）——
	# 留着模型只会看到背面剔除的穿透碎片 + 近平面剖切（理由详见
	# `FlightBody.set_model_visible()`）。
	#
	# ⚠️ `and player.alive` 这一半**不能省**：`FlightBody.die()` 里也用
	# `model_root.visible = false` 把残骸藏起来，而本函数是**每帧**调的 ——
	# 少了这个条件，关着第一人称的玩家一被打爆就会"复活"一具残骸漂在那里。
	# 四象限都要对：FPV 关 + 活着 = 显示；其余三种（含阵亡）= 隐藏。
	#
	# ⚠️ 只藏**自己**。敌机 / 僚机是 `units_root` 里另外的节点，一行都不碰。
	if player != null and is_instance_valid(player):
		player.set_model_visible((not Settings.first_person) and player.alive)


func _menu_orbit(delta: float) -> void:
	_menu_angle += delta * 0.05
	var r := 3200.0
	var want := Vector3(cos(_menu_angle) * r, 2400.0, sin(_menu_angle) * r)
	chase.global_position = chase.global_position.lerp(want, 1.0 - exp(-1.4 * delta))
	var look := Vector3(cos(_menu_angle + 1.35) * r * 1.5, 900.0, sin(_menu_angle + 1.35) * r * 1.5)
	if chase.global_position.distance_squared_to(look) > 1.0:
		chase.look_at(look, Vector3.UP)
	chase.fov = lerpf(chase.fov, 62.0, 1.0 - exp(-2.0 * delta))


# ============================================================ 事件

## ★ 轮 E：剧情关的**触发器**。每帧把本帧的运行时状态喂给通讯播放器 ——
## `Mission.triggers` 里 `radio:` 那一条由它排队播出，其余（`end:*`）由
## `_apply_mission_action()` 落到游戏上。
##
## ⚠️ **只在 FIGHT 里跑**，与 `Game.elapsed` 的推进口径**逐字一致**
##（`game.gd._process()`：`if phase == Phase.FIGHT: elapsed += delta`）。
## 两处口径不一致会出现"电台按自己的时钟先响、而任务计时还没开始"。
##
## ⚠️ 分工：`radio:` 那一半（排队 + 显示）归 **HUD** 的 `CommsDirector`；
## `end:*` 那一半要**结束这一局** —— 那是 `main` 的事。所以求值挂 `main`、
## 显示挂 HUD（见 `hud.gd` 头部那段分工注释）。
##
## ⚠️ 这里**不缓存任何触发状态**：`fired` 的唯一持有人是 `CommsDirector._fired`
##（数据里存 `fired` 会让 7 关共享的 `Mission` 对象在重打一关时"这一条已经演过"）。
## 每帧现算一份字典交出去，是这条规矩的代价，也是它的证据。
## ★ 轮 55：剧情关的 **Zone 进入检测**（`REACH` 目标与 `enter:X` 触发器的共同上游）。
##
## ⚠️ 为什么必须单开一处：`Game._evaluate_end()` **没有周期性调用者**
##（唯一触发点是 `notify_destroyed()`）⇒ “飞到一个地方”这种**不靠击坠发生**的胜利
## 条件，必须由上报点**主动**再判一次。这里就是那个上报点。
##
## 语义是“**到过**”（锁存，见 `Game.zone_reached`）而不是“此刻在里面”。
##
## ⚠️ 只读**本关任务数据里写着**的 zone（`Mission.zones`）—— 一份真源，不另建表。
## ⚠️ 与 `_tick_mission_triggers()` 的先后**有讲究**：本函数在它**之前**跑，
##    这样“进区 ⇒ 锁存 ⇒ 同一帧 `all_done` 成立 ⇒ `end:win` ⇒ 出结算页”
##    在**一帧之内**走完，玩家不会看到“已经飞到了，但结算页迟一帧才出来”。
func _tick_mission_zones() -> void:
	if phase != Phase.FIGHT:
		return
	var m: MS.Mission = Game.active_mission
	if m == null or m.zones.is_empty():
		return
	var p: Node3D = Game.live_player()
	if p == null:
		return
	var pos := p.global_position
	var touched := false
	for z: MS.Zone in m.zones:
		if bool(Game.zone_reached.get(z.id, false)):
			continue
		if z.contains(pos):
			Game.zone_reached[z.id] = true
			touched = true
	if touched:
		# ⚠️ **不自己 `set_phase(WIN)`** —— 胜负的唯一出口是 `Game._evaluate_end()`。
		# 这里只让它重算一次；“出不出结算页”由 `all_done → end:win` 那条触发器
		# 经 `_apply_mission_action()` 决定（与 M01 同一条路，重复调用是幂等的）。
		Game.recheck_end()


func _tick_mission_triggers() -> void:
	if phase != Phase.FIGHT or hud == null or hud.comms == null:
		return
	var m: MS.Mission = Game.active_mission
	if m == null:
		return
	for a: Dictionary in hud.comms.tick_mission(m, Game.trigger_state(m)):
		# ⚠️⚠️ 动手之前先问一句"这条 `when` 依赖的键我**这一帧真有**吗"。
		# 少了这一句，"接线"这个动作本身会把 `< 缺省 0 ⇒ 恒真` 那半边放出来
		#（M06/M07 的 `protected_alive<1` ⇒ 开局即判负）。见 `Game.trigger_keys_sourced()`。
		if not _trigger_is_sourced(m, int(a["index"])):
			continue
		_apply_mission_action(a)


## 这条触发器依赖的状态键，`Game` 这一帧**全都**有源吗。
##
## ⚠️ **不在这里另写一张白名单** —— 真源是 `Game.trigger_keys_sourced()`，
## 这里只是**问**它。抄一份过来就成了两处：加一个源时漏一处，表现是
## "有源了但被跳过"，也就是那半场戏永远不演，**静默**。
func _trigger_is_sourced(m: MS.Mission, index: int) -> bool:
	var trs: Array = m.triggers
	if index < 0 or index >= trs.size():
		return false
	var when := str(trs[index].when)
	var have := Game.trigger_keys_sourced()
	for k: String in MS.Trigger.keys_of(when):
		if have.has(k):
			continue
		push_warning("MISSION_TRIGGER_UNSOURCED(%s[%d]) `%s` 依赖键 `%s`，本帧没有源 ⇒ 跳过"
			% [m.id, index, when, k])
		return false
	return true


## 把触发器的**非电台动作**落到游戏上。
##
## ⚠️ 本轮只认 `end:`。`spawn_wave` / `spawn` / `objective` / `zone` / `cutscene` /
## `music` **还没接**（它们此前也没接 ⇒ "不接"不改变现状），但**必须留痕**：
## 数据里写着、运行时不发生，正是本仓库记了无数次的静默陷阱 ——
## `push_warning` 让它在日志里自己说出来，而不是等人去猜。
func _apply_mission_action(a: Dictionary) -> void:
	var kind := str(a.get("kind", ""))
	var arg := str(a.get("arg", ""))
	if kind == "end" and arg == "win":
		# ★ **不自己 `set_phase(WIN)`**：胜负的唯一出口是 `Game._evaluate_end()`。
		# 让它重算一次、再问它算出了什么 —— 这样"谁判胜"仍然只有一处。
		#（M01 的 `all_done` 与目标门是同一件事的两条路，重复调用是幂等的。）
		Game.recheck_end()
		if Game.phase == Game.Phase.WIN:
			_finish_round()
		return
	if kind == "end" and arg == "lose":
		_mission_lose()
		return
	push_warning("MISSION_ACTION_NOT_WIRED(%s) `%s:%s` 尚未接（轮 D/G/H）"
		% [_campaign_mission_id, kind, arg])


## ★ 轮 E：**由触发器**判定的失败（M01..M05 的 `hp<0.25` / `hp<0.2` 那一类）。
##
## ⚠️ 与 `_on_player_destroyed()` 唯一的区别是**玩家还活着** ——
## 所以不需要 `_death_anchor`（相机没有失去跟随对象），机体也还在，
## `hud.capture_result()` 直接读得到数。
## ⚠️ 顺序与那条路**逐字一致**：`_settle_campaign()` **必须早于** `capture_result()`
##（结算页读的是那一刻抄下来的快照；先开结算再算钱的话那一行永远显示 +0）。
func _mission_lose() -> void:
	if phase == Phase.RESULT:
		return
	if Game.active_mission != null and Game.active_mission.chapter == 3:
		Game.set_phase(Game.Phase.LOSE)
		if is_instance_valid(player): player.controls_enabled=false
	_settle_campaign(false)
	phase = Phase.RESULT
	_phase_lockout = RESULT_LOCKOUT
	hud.capture_result(MissionRating.Outcome.LOSE)
	Audio.play_bgm(Audio.Bgm.RESULT)
	chase.set_lock_view(false)


func _on_player_destroyed(_killer: Node3D) -> void:
	# ★63-24 无限强化演习：玩家的死**就是这一局的终点**（本模式没有"通关"）。
	#
	# ⚠️ 必须在 `hud.capture_result()` **之前**把状态改成 `OVER` —— 结算页要读它
	# 才能把"失败"那两个字换成"演习终止 + 到第几波"（设计 §10）。
	# ⚠️ 顺手把敌机强化系数**钉回 1.0**：它是一处全工程共用的乘法，而结算页还会
	# 活一会儿（残骸 2.2 s 后才释放）—— 留着 >1 的值就是一颗给下一局的雷
	#（判据 `NO_TOUCH_OTHERS`：非演习模式下它必须恒为 1.0）。
	if Game.is_endless():
		Game.endless_phase = EndlessScript.Phase.OVER
		Game.endless_enemy_reinforce = 1.0
	# ★ 轮 C：军资结算**必须早于 `capture_result()`** —— 结算页读的是那一刻的快照，
	# 先开结算再算钱的话，那一行永远显示 +0。
	_settle_campaign(false)
	phase = Phase.RESULT
	_phase_lockout = RESULT_LOCKOUT
	# 快照结算数据。**必须在 player 还活着的时候抄**：残骸 2.2 秒后会被释放，
	# 而结算画面要在那之后继续显示（HUD 里直接读 player 会导致"结算画面秒没"）。
	hud.capture_result(MissionRating.Outcome.LOSE)
	Audio.play_bgm(Audio.Bgm.RESULT)
	# 机体销毁后镜头失去了跟随对象，用锚点把最后的姿态钉住，好让爆炸演完
	_death_anchor = Node3D.new()
	_death_anchor.name = "DeathAnchor"
	add_child(_death_anchor)
	_death_anchor.global_transform = player.global_transform
	chase.set_target(_death_anchor)
	chase.follow_lag = 2.2
	chase.set_lock_view(false)


## ★63-9 D4：**敌方机体坠毁提醒**（用户：「增加敌方机体坠毁提醒（不要和游戏结算冲突）」）。
##
## ## 为什么挂在 `main` 这一层、而不是 `FlightBody`
## 击坠分两种：**非终结性**（场上还有敌机）与**终结性**（这一下把场上打空）。
## 判据只有一个真源 —— `Game.phase`；它由 `Game.notify_destroyed()` 里的
## `_evaluate_end()` 决定，而那一句**先跑**；`destroyed.emit()` **后跑**
##（`flight_body.gd` 的 `destroy()` 里，顺序写死）。
## ⇒ 走到本函数时，「这一下算不算收场」已经被回答过了 —— 这正是用户要的
##   「不要和游戏结算冲突」的**结构性**解法：不去猜时序，直接读那个已经定了的状态。
##
## ⚠️ 判据必须用 `Game.phase`，**不能**用 `main.phase`：
## `_finish_round()` 只把 `main.phase` 改成 `RESULT`（含义是「结算快照已定格」），
## 而**结算页由 `Game.phase == WIN / LOSE` 驱动**（`hud._draw_phase_overlay()`）。
## 小队战实测（`tools/_r63_9_d4_probe.tscn`）：击坠 1 架之后 `main.phase` 已经是
## `RESULT`，而 `Game.phase` 仍是 `FIGHT`、屏幕上**根本没有结算页** ——
## 拿 `main.phase` 当门会把提醒整片掐掉（那是实打实的误判）。
##
## ⚠️ 提醒走 `player.notice`（中央那摞 toast），不是 `_system_say()`：
## 后者是「辅助飞行状态」专用的（`player_controller.gd` 里那条注释划的界），
## 击坠属于**战斗信息**。
##
## ⚠️ 训练靶机**故意不走这条路**（`_on_target_destroyed()` 是独立回调）：
## 靶机不是「敌方机体」，它有自己的 `5 / 8` 计数在 HUD 左下角。
func _notify_enemy_down(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var nm := ""
	if unit is FlightBody:
		nm = (unit as FlightBody).display_name
	if nm == "":
		return
	# ---- ★ 与结算的门（用户原话里的「不要冲突」）----
	# `Game.phase` 一旦不是 FIGHT，从那一帧起屏幕上就是结算页 —— 再弹一条 toast
	# 就是「结算页上浮着一条战斗提示」，正是要避免的那种冲突。
	# 终结性击毁的那一句落在结算页**本身**：左栏「战斗经过」里有一行带机名的
	# `敌机坠毁 —— <机名>`（由 `flight_body.destroy()` 写进 `Game.log_event()`）。
	if Game.phase != Game.Phase.FIGHT:
		return
	if player == null or not is_instance_valid(player):
		return
	player.notice.emit("敌机坠毁 —— %s" % nm, 2.2)

func _on_enemy_destroyed(_killer: Node3D, unit: Node3D) -> void:
	_notify_enemy_down(unit)
	_finish_round()


## ★ 轮 50：玩家**打中了剧情地标**（M01「夜袭达沃」）。
##
## ⚠️ 为什么非要有这一条：判胜的两个既有入口
##（`_on_enemy_destroyed()` 与 `Game.notify_destroyed()`）都挂在
## “**有一台单位被销毁**”这个事件上，而 M01 **一架敌机都没有**
## ⇒ 那两条路一次都不会被走到 ⇒ 玩家打中了酒店、
## 画面一切正常、**永远不出结算页**。
##
## ⚠️ 为什么不在这里判“达成没达成”：判据的真源在 `Game`
##（它读 `MissionScript.all_required_done()`）。这里只做两件事：
##   ① **主动**让它重算一次（`Game.recheck_end()`）；
##   ② 它说赢了就把结算页推出来。
## ⚠️ 也**不能**写成“读 `Game.phase` 就完事”：那会依赖
## `Game.note_landmark_hit()` 里 “先 `emit` 还是先 `_evaluate_end()`” 的顺序 ——
## 换个顺序这条就**静默失效**。主动重算与顺序无关（多算一次是幂等的）。
func _on_landmark_hit(_landmark: Node3D, _hitter: Node3D) -> void:
	Game.recheck_end()
	if Game.active_mission != null and Game.active_mission.id == "M06" and Game.landmark_hits == 1 and Game.phase != Game.Phase.WIN:
		player.notice.emit("英勇号攻击完成，击落剩余梅萨",3.0)
	if Game.phase == Game.Phase.WIN:
		_finish_round()


## 训练模式：打掉一架靶机。全部打光才算过关。
##
## 靶机是**多架**，所以不能像 1v1 那样"敌机死了就结算"——
## 要等场上再没有敌对单位。判据仍然走 `Game.live_hostiles_of()`
## （靶机撞地自毁也算消耗掉一架，玩家不会因为"它自己摔了"而卡在打不完的一局里）。
func _on_target_destroyed(_killer: Node3D) -> void:
	# 1.2 起开局即 FIGHT（没有 INTRO），所以这里只看 FIGHT ——
	# 仍要挡住结算页：结算画面里"靶机被击坠"的事件不应该再改战果。
	if phase != Phase.FIGHT:
		return
	if player == null or not is_instance_valid(player):
		return
	Game.log_event("靶机被击坠（%d / %d）" % [Game.training_targets_down, Game.training_targets_total])
	if Game.live_hostiles_of(player).is_empty():
		_finish_round()


## 记下刚清完的这一波用了多久（结算页的"波次用时"）。
##
## ⚠️ 只在挑战模式里记：别的模式没有"波"这个概念，记进去只会让结算页多一行
## 没意义的数字。判据用 `active_challenge` 而不是"波次表非空"——
## 后者在编队战里会成立（编队战也刷好几台）。
func _close_wave() -> void:
	if Game.active_challenge == null:
		return
	Game.challenge_wave_times.append(maxf(Game.elapsed - _wave_started, 0.0))
	_wave_started = Game.elapsed


## 一局打赢了的收尾（对战 / 训练共用）。
func _finish_round() -> void:
	if phase == Phase.RESULT:
		return
	# ★ 轮 C：军资结算**必须早于 `capture_result()`**（同 `_on_player_destroyed`）。
	_settle_campaign(true)
	phase = Phase.RESULT
	_phase_lockout = RESULT_LOCKOUT
	hud.capture_result(MissionRating.Outcome.WIN)
	Audio.play_bgm(Audio.Bgm.RESULT)
	chase.add_shake(1.2)
	chase.set_lock_view(false)


## 玩家挨打：把"幅度 / 方向 / 类型"翻译成相机反馈（DESIGN §4.9）。
##
## ⚠️ 2026-09-21 之前这里是一行 `chase.add_shake(0.5)` —— **三个参数全被丢掉**
##（形参前的下划线 `_amount` / `_source` / `_type` 在 GDScript 里就是"我故意没读它"）。
## 后果：机炮蹭一下和相杀级重击**体感一样重**，而且玩家分不出被打的是哪一侧，
## 只能靠随机抖动猜。`damaged` 信号的签名本来就是
## `(amount, source, damage_type)` —— 这三个参数当初就是为这一项准备的。
func _on_player_damaged(amount: float, source: Node3D, type: int) -> void:
	if chase == null or player == null or not is_instance_valid(player):
		return
	# ⚠️ 血量上限在 **`FlightBody.max_hp`** 上，不在 `SuitProfile` 上
	#（`profile` 那边叫 `hull_hp`，是"出厂值"；机体经过难度强化 / 换装之后
	# `max_hp` 才是这一局真正在用的分母）。2026-09-21 第一版写成
	# `player.profile.max_hp` ⇒ **每挨一次打就抛一次 SCRIPT ERROR**，
	# 而那正是"受击反馈"这个功能的唯一入口 —— 整项功能静默失效。
	var max_hp := maxf(player.max_hp, 1.0)
	var impact := Vector3.ZERO
	if source != null and is_instance_valid(source):
		# ⚠️ 传的是**冲击传播方向**（来源 → 自机），不是"来源在我的哪一边"。
		# 相机被推的方向就是这个方向（背离来源）—— 见 `add_hit_shake()` 的方向约定。
		impact = source.global_position.direction_to(player.global_position)
	chase.add_hit_shake(amount / max_hp, impact, type)


## 护盾期挨打（§4.9.2⑤）：`damaged` **不发**（血没变），但**必须有反馈** ——
## 否则护盾期被持续打是完全无感的，而护盾掉了不恢复。
##
## ⚠️ 幅度换算整体交给 `ChaseCamera.shield_hit_ratio()`：分母是**护盾池**
## 而不是机体血。理由、以及"0.45 那个数为什么最后取 1.0"都写在那边的注释里。
func _on_player_ifield_hit(absorbed: float, source: Node3D, type: int) -> void:
	if chase == null or player == null or not is_instance_valid(player):
		return
	var impact := Vector3.ZERO
	if source != null and is_instance_valid(source):
		# 与 `_on_player_damaged` 同一个约定：**冲击传播方向**（来源 → 自机）。
		impact = source.global_position.direction_to(player.global_position)
	chase.add_hit_shake(ChaseCamera.shield_hit_ratio(absorbed, player.ifield_max),
		impact, type)


func _on_player_lock_acquired(target: Node3D) -> void:
	Game.locks_acquired += 1
	Game.log_event("锁定敌机")
	Audio.play_self("ui_confirm", -10.0)


func _on_player_lock_lost() -> void:
	Game.locks_lost += 1


func _on_enemy_lock_acquired(_target: Node3D) -> void:
	if phase != Phase.FIGHT:
		return
	Game.log_event("敌机锁定了你")
	Audio.play_self("alarm_lock", -3.0)


func _on_player_ifield_broken() -> void:
	Audio.play_self("alarm_critical", -2.0)


func _on_rifle_discarded(remaining: int) -> void:
	if player != null and is_instance_valid(player):
		player.notice.emit("剩余步枪 ×%d" % remaining, 1.6)


func _on_enemy_rifle_discarded(remaining: int) -> void:
	if player != null and is_instance_valid(player):
		player.notice.emit("敌机丢弃步枪 —— 锁定被强制解除（剩余 ×%d）" % remaining, 2.2)
		Game.log_event("敌机丢枪脱锁（剩 %d 把）" % remaining)


## 三种警报各管一摊：被锁定（由 LockOnSystem 信号触发）、导弹逼近、危殆。
## 这一支负责后两种 —— 它们是"状态持续"而不是"事件"，所以要靠轮询边沿。
func _tick_alarms() -> void:
	if phase != Phase.FIGHT or get_tree().paused \
			or player == null or not is_instance_valid(player):
		return
	var n := player.incoming_missiles().size()
	if n > _prev_incoming:
		Audio.play_self("alarm_missile", -3.0)
		Game.log_event("导弹逼近")
		Game.missiles_incoming += n - _prev_incoming
	_prev_incoming = n

	if not _low_hp_announced and player.hp_ratio() < 0.25 and player.alive:
		_low_hp_announced = true
		Audio.play_self("alarm_critical", -3.0)
		Game.log_event("机体耐久低于 25%")
# ============================================================ 锁定诊断记录（1.2 调试工具）

## 按 **F9** 开始 / 停止录制：每 0.1 秒采一行锁定状态，停止时写进
## `user://lock_debug.csv` 并在控制台打印路径。
##
## 为什么要有它：用户两次反馈"锁不上"，我两次都是**猜**（先调数值、后来才发现
## 角度项挂错了对象）。测试能证明"规则对不对"，但证明不了"你在实战里卡在哪一项"——
## 那需要把实战里的 (距离 / 机头夹角 / 准星夹角 / 质量 / 层 / 阻塞原因) 记下来。
## 有了这份 CSV，"锁不上"是哪一项卡的就不再是猜的。
##
## 记录间隔 0.1 s（10 Hz）足够看出趋势，30 秒也才 300 行。
var _probe_on := false
var _probe_latch := false
var _probe_t := 0.0
var _probe_rows: Array[String] = []


func _tick_lock_probe(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_F9):
		if not _probe_latch:
			_probe_latch = true
			_probe_on = not _probe_on
			if _probe_on:
				_probe_rows.clear()
				_probe_rows.append("t,dist_km,nose_deg,aim_deg,quality,tier,reason,boosting,target")
				print("[锁定诊断] 开始记录 —— 再按 F9 停止并写文件")
			else:
				_dump_lock_probe()
	else:
		_probe_latch = false
	if not _probe_on:
		return
	_probe_t += delta
	if _probe_t < 0.1:
		return
	_probe_t = 0.0
	if player == null or not is_instance_valid(player) or player_lock == null:
		return
	var t := player_lock.target
	var dist := 0.0
	var nose := 0.0
	var aim := 0.0
	var tname := "-"
	if t != null and is_instance_valid(t):
		var to := t.global_position - player.global_position
		dist = to.length() / 1000.0
		nose = Ballistics.angle_off_boresight(player.forward(), to)
		aim = Ballistics.angle_off_boresight(player.aim_forward(), to)
		tname = t.display_name
	_probe_rows.append("%.2f,%.2f,%.1f,%.1f,%.2f,%s,%s,%s,%s" % [
		Game.clock, dist, nose, aim, player_lock.track_ratio(),
		player_lock.tier_name(), player_lock.block_reason(),
		"1" if player.fm.boosting else "0", tname])


func _dump_lock_probe() -> void:
	var path := "user://lock_debug.csv"
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh == null:
		print("[锁定诊断] 写文件失败：", FileAccess.get_open_error())
		return
	for r: String in _probe_rows:
		fh.store_line(r)
	fh.close()
	print("[锁定诊断] 已写入 ", ProjectSettings.globalize_path(path), "（", _probe_rows.size(), " 行）")
	print("[锁定诊断] 把这行路径下的文件发给我即可")


## Build one host-oriented deployment, then translate human seats for the guest.
## AI slot identifiers and pilot/passenger positions are identical on both peers.
func _lan_canonical_lineups(plan: LanPlan.Plan) -> Dictionary:
	var host_suit := Net.choice_of("suit", Game.active_suit) if Net.local_team == 0 else Net.remote_suit
	var guest_suit := Net.remote_suit if Net.local_team == 0 else Net.choice_of("suit", Game.active_suit)
	var friendly := BattleFormation.lineup(plan.host_side,host_suit)
	for u: BattleFormation.Unit in friendly:
		if u.owner_is_player: u.set_human_seat(0)
	var opposing: Array
	if plan.same_team:
		var guest_ace: bool = BattleFormation.roster_of(plan.host_side).aces.has(guest_suit)
		for u: BattleFormation.Unit in friendly:
			if u.owner_is_player: continue
			var seat_ok := u.squad == 0 and u.slot == 1 if plan.is_shared_pedal() else (u.is_ace if guest_ace and not BattleFormation.roster_of(plan.host_side).aces.has(host_suit) else not u.is_ace and u.slot == 0)
			if seat_ok:
				u.suit = guest_suit
				u.is_ace = guest_ace
				u.set_human_seat(1)
				break
		opposing = BattleFormation.lineup(plan.foe_side(),-1)
	else:
		opposing = BattleFormation.lineup(plan.client_side,guest_suit)
		for u: BattleFormation.Unit in opposing:
			if u.owner_is_player: u.set_human_seat(1)
	if Net.local_team == 1:
		for lineup in [friendly,opposing]:
			for u: BattleFormation.Unit in lineup:
				if u.human_seat >= 0: u.set_human_seat(1-u.human_seat)
	return {"mine": friendly if Net.local_team == 0 or plan.same_team else opposing,
		"theirs": opposing if Net.local_team == 0 or plan.same_team else friendly}


## M01: sea skim, mounted Messer reveal, cockpit radio, ascent and hotel focus.
func _begin_davao_intro() -> void:
	_launch_match(true, false)
	phase = Phase.DAVAO_INTRO
	Game.set_phase(Game.Phase.INTRO)
	Audio.set_story_mode(true)
	Audio.lock_battle_track(Game.active_mission.bgm)
	Audio.request_battle_open(Game.active_mission.bgm)
	Audio.play_bgm(Audio.Bgm.BATTLE)
	_strike_bgm_live = true
	_davao_director = preload("res://scripts/cinematics/davao_intro_director.gd").new()
	_davao_director.setup(self)
	add_child(_davao_director)

func _finish_davao_intro() -> void:
	if not is_instance_valid(_davao_director): return
	_davao_director.cleanup(true)
	_davao_director.queue_free()
	_davao_director = null
	_start_fight()


## Ordinary launch intros are automatic and skippable; authored mission intros
## retain their existing entry points. Headless regression retains instant start.
func _begin_sortie_or_fight(force:=false)->void:
	var timeline:=preload("res://scripts/data/sortie_script.gd")
	if not is_instance_valid(player) or not timeline.supported_in_mission(player.profile,_campaign_mission_id) or Game.match_mode==Game.MatchMode.TRAINING or (DisplayServer.get_name()=="headless" and not force):
		_start_fight();return
	_start_mission_music()
	phase=Phase.SORTIE;Game.set_phase(Game.Phase.INTRO)
	if _campaign_mission_id=="M09" and player.profile.id==SuitProfile.Id.PENELOPE:
		_sortie_director=preload("res://scripts/cinematics/m09_launch_director.gd").new()
	elif player.profile.id in [SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI]:
		_sortie_director=preload("res://scripts/cinematics/suit_video_director.gd").new()
	elif player.profile.id==SuitProfile.Id.NEUE_ZIEL:
		_sortie_director=preload("res://scripts/cinematics/neue_entry_director.gd").new()
	elif player.profile.id==SuitProfile.Id.GP03D:
		_sortie_director=preload("res://scripts/cinematics/gp03d_entry_director.gd").new()
	else:
		_sortie_director=preload("res://scripts/cinematics/sortie_director.gd").new()
	_sortie_director.setup(self)
	_sortie_director.finished.connect(_finish_sortie)
	add_child(_sortie_director)
func _finish_sortie()->void:
	if is_instance_valid(_sortie_director):_sortie_director.queue_free()
	_sortie_director=null
	_start_fight()


func _refresh_super_hard_unlock(show_notice:bool)->void:
	var normal:=CS.load_progress(campaign_save_path)
	Game.super_hard_unlocked=CS.super_hard_unlocked(normal)
	if is_instance_valid(menu):menu.diff_index=clampi(menu.diff_index,0,Difficulty.all_levels(Game.super_hard_unlocked).size()-1)
	if show_notice and Game.super_hard_unlocked and not bool(normal.get("super_hard_notice_seen",false)):
		menu.show_super_hard_notice()
		normal["super_hard_notice_seen"]=true
		CS.save_progress(normal,campaign_save_path)

func _on_campaign_difficulty_changed(level:int)->void:
	var previous_path:=CS.path_for_difficulty(campaign_save_path,_campaign_level)
	_campaign_level=level
	var next_path:=CS.path_for_difficulty(campaign_save_path,level)
	if previous_path==next_path:return
	Game.campaign_progress=CS.load_progress(next_path)
	campaign_map.open(Game.campaign_progress)
