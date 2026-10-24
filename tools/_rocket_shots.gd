extends Node
## **马夫蒂火箭发射段的定点验收图**（2026-09-30）。
##
## 老板原话：
## > 「把马夫蒂的火箭加入游戏中 …… 玩家需要操控火箭**从太平洋发射到近地轨道**，
## >  中间需要做**无缝切换房间**，可以在发射过程中做切换，**通过云层来挡住玩家视线**，
## >  然后在后台偷偷加载切换房间，然后切换到**近地轨道中离柯西运输仓 200 km 的地方**。」
## > 「**不需要用发射平台，直接从海里面出来就行了**」
## > 「**云层贴图过于敷衍了，需要用模型遮挡或者是更精细的云层。**」
## > 「发射过程中镜头离火箭太远了，我希望做**全程跟随**的」+「在火箭最上端加一个
## >  **驾驶舱第一人称**（不是全周天！）需要建模驾驶舱视角的 ui 和控制台仪表盘」
## > 「发射时候的的云雾**遮挡少70%**，至少要看见火箭和背景和星空」
## > 「发射时候的周围环绕的东西做成风压太丑陋了，还不如**做成烟雾**呢」
## > 「火箭升空的时候都**没有大型火焰拖尾**」
##
## 十九张，**按真实上升顺序**排（箭底高度单调增 ⇒ 看图的人能顺着"一次发射"读下来）：
## | # | 文件 | 箭底高度 | 回答 |
## |---|---|---|---|
## | 1 | `01_sea_site` | 静置 −34 m | ★ **发射点上一件人造物都没有**（平台已砍）+ 头顶那垛**真云几何**在不在 |
## | 2 | `02_breach_side` | 14 m | ★★ **出水**：泡沫环 + **烟** + 箭体正穿过水面 —— 「从海里出来」的**唯一**证据 |
## | 3 | `03_breach_top` | 14 m | ★ 出水**俯视**：读得出"环"是**环**，且烟是**一圈在环上滚的团**（不是一根柱） |
## | 4 | `04_chase_follow` | 180 m | ★★ **真机追尾档**（`set_launch_view(true)`）：箭体占屏高 **53%** + **离箭 80.92 m**（`_dist_summary()` 给极差）—— 「全程跟随 + 一直保持一个距离」的判据 |
##
## ⚠️ ④ 那一张在**箭底 180 m**（速度还近 0）⇒ FOV 仍 68°、占屏高 53%。
## 同一次上升里 ⑫（出云之后）量到的是 **约 43%** —— 2026-09-30 晚补上的
## 「FOV 速度项」（`RocketBody.speed_fov_mix()`，对数响应）让视野从 68° 连续张到 ~80°。
## 两者不矛盾：**离箭距离始终 80.92 m**（硬约束没动），占屏高只随 FOV 走。
## | 5 | `05_rocket_side` | 180 m | ★ **机头朝上**（不是倒插）+ ★ **两个助推器左右并排**（不是上下叠） |
## | 6 | `06_rocket_top` | 180 m | ★ 横截面 **宽 > 厚**（与⑤互为佐证；俯视最直观） |
## | 7 | `07_cloud_mound` | 180 m | ★★ 头顶那垛云**单独一张**（只关雾、**留云**）：有前后、有远近 —— 老板要的"用模型遮挡" |
## | 8 | `08_flame_wide` | 8 km | ★ **对照老板那张参考图的构图**：细长箭体 + 一条长焰 + 下方夜海 + 被烤亮的云底（机位在箭体斜后上方、**朝着发射点回看**） |
## | 9 | `09_flame_side` | 25 km | ★★ **大型火焰拖尾**本体：箭底那根橙白色火柱，近景可数出三层（焰长 144 m = 箭体 2.5 倍） |
## | 10 | `10_swap_before` | 100 km | ★★ **换图前一帧**（座舱档 / 太平洋 / 卡门线）—— 换图窗口的**唯一遮挡物**现在就是舱体 |
## | 11 | `11_swap_after` | 100 km → LEO | ★★ **换图后一帧**（同一机位、只差一次 `apply_map_staged()`）⇒ 与 ⑩ 逐像素差 **减掉基线** = 玩家真正看见了多少 |
## | 12 | `12_space_view` | ~545 km | 交还舱外档之后：**地球临边 + 星空 + 长焰**（"我出云了"那一瞬） |
## | 13 | `13_arrival` | LEO | 抵达：550 km、离运输仓 200 km（**箭体在前景、朝运输仓方向**） |
## | 14 | `14_cockpit_hud`（+`14b_eye_off` / `14c_hud_off` 两张对照） | LEO | ★★ **座舱档 = HUD 的全周天那一层**（刻度导轨 + 仪表台 + 取景框）—— 老板：「**你驾驶舱做的好丑，直接用全周天驾驶舱的代码吧**」。三张**只差一个开关** ⇒ 两次逐像素差把这一层拆成「框」与「台」，并给出**像素落在屏幕哪几个区**的分布表（回答「**不需要屏幕左上角那么多白色文字了**」） |
## | 15 | `15_cockpit_countdown` | 点火前 8 s | **倒计时档的读数形态**：中央屏 `note = 点火倒计时 7.5 s`、左格段位「待发」、两根指针**归零**（箭还浸在水里）。★ **不在时间线上**（它是点火前那一档），排在这里只为与 ⑭ 同机位对照。 |
##
## ⚠️⚠️ **⑩⑪ 是 2026-09-30 换掉 ⑧⑨（云幕）的那一对**。老板这一轮的三条：
## > 「**不需要云层了**」⇒ 整屏云幕（`RoomCurtain` / `RoomStreamer` / `room_curtain.gdshader`）
## >  连文件一起删；换图窗口改由**座舱**遮住（`main._swap_to_orbit()` 的 `_swap_eye_lock`）。
## > 「**相机要一直和火箭保持一个距离**」⇒ `ChaseCamera._rigid_chase()`（逐帧硬落位）。
## > 「**把玩家视角跳到座舱内，然后星空盒都是同一片的情况下可以直接换**」⇒ 换图触发
## >  从 2 800 m 抬到 `REVEAL_ALT`（卡门线），见 `LaunchScript.REVEAL_ALT` 那段。
##
## ## ⚠️⚠️ 每张图用哪台相机**必须显式声明**（`_use_cam()`），`_look()` 里也调它
## `ChaseCamera._ready()` 里写着 `current = true` —— 它一进树就把本探针那台 `cam` 顶掉。
## 第一版没管这件事，于是 ①②③ 三张"手摆机位"的图**全是追尾机位拍的**
##（②③ 两张一模一样），而**日志里一条异常都没有**：`cam.global_position` 白写了，
## `SHOT ... err=0` 照旧、亮度读数照旧"有内容"。
## ⇒ 现在每张 `SHOT` 行都带**当时真正生效的那台相机名**，看日志就能抓住这类事。
##
## ## ⚠️ 为什么 ⑤ 要"沿世界 Z 看"
## 模型的**助推器沿机体 +X 排开**，而 `upright_basis()` 让机体 +X **就是世界 +X**。
## ⇒ 只有从**世界 ±Z** 看过去，画面水平方向才是世界 X ⇒ 助推器才**左右并排**。
## 从世界 X 看过去它们会**前后重叠**（那也对，但读不出"并排"）。
## 判"有没有上下叠"（= 少做了一次滚转的那个错）也必须在这一侧看：那时它们会**竖直**排开。
##
## ## ⚠️ ⑥（箭体俯视）与 ③（水面俯视）都是"正俯视"，两者的机位**不能用同一套**
## ⑥ 读的是**箭体的横截面**（宽 > 厚）⇒ 机位要贴近箭顶（否则 58 m 的箭只有一个点）；
## ③ 读的是**水面上的环**（内径 0.78 / 外径 1.0 ⇒ 环带本身只有 22% 半径宽）
## ⇒ 机位要**拉到环的正上方**（半径最大 860 m ⇒ 至少 900 m 高），否则环在画面里
## 只有十几像素，"环"与"一坨白斑"分不出来。
##
## ## ⚠️ 高空那两张（⑫⑬）**必须关天气层**
## `env.fog_enabled` + `env.volumetric_fog_enabled` + `_cloud_root` + `_sea_mist`
## **四个都要关**，漏任一个就是一整张米色，什么都读不出（`_b7_shots` / `_r5_shots` 踩过）。
## ⑦ 只关前**两**个 + `_sea_mist`（`_cloud_root` 必须**留着** —— 不然后六张里那垛真云
## 没了，而它正是 ⑦ 要回答的东西）。低空那几张（①~⑨）**保留天气** ——
## "云到底挡没挡住视线"要看**真实大气**。⇒ 关掉之后**必须还原**（`_restore_fog()`），
## 不还原的话 ⑧⑨ 会变成"云幕在干净天空下的一张图"，判据对象被偷偷换掉。
##
## ## ⚠️⚠️ 相机远裁面**必须照抄工程自己的两个常数**
## 第一版这里写死 `cam.far = 4.0e7`，结果**九张图全废**：只有 `Environment` 的天空盒
## 画得出来（太平洋是夜间 ⇒ "星空 + 下半纯黑"），132 m 外的 58 m 火箭、
## 260 m 半径的平台、连"全遮"那张的整屏云幕**一件都没有**。
## 日志里刷的是 `create_frustum_points (rendering_light_culler.cpp:682)` —— 那是个**假线索**。
##
## A/B 对照（`tools/_far_ab.gd`，正俯视发射平台，读像素均值 / 亮像素占比）：
## | 档 | `far` | `sun.shadow_enabled` | 均值 | 亮像素 >40 占比 |
## |---|---|---|---|---|
## | A | 40 000 km | true | **0.0** | **0.0000** |
## | B | **90 km** | true | **19.5** | **0.0586** |
## | C | 40 000 km | **false** | **0.0** | **0.0000** |
## ⇒ 凶手是 `far`，**与阴影无关**（C 档关了阴影照旧全黑）。
##
## 工程自己的口径：地表图 `ChaseCamera.GROUND_FAR = 90 000`、
## 轨道图 `ChaseCamera.ORBIT_FAR = 1.0e7`（`_sync_depth_range()` 按 `map.has_ground` 切）。
## 探针写了 **444 倍** —— 而它**不报任何错**，画面只是"什么都没有"。
## ⇒ 一律走 `_set_far_for()`，一个字都不许自己写。
## ⚠️⚠️ 而且这个函数**只管探针那台 `cam`**：`ChaseCamera` 的远裁面由它自己
## `_sync_depth_range()` 从 **`Game.active_map`** 拿（不是 `world.map`）⇒
## 探针里换图必须**同时**写 `Game.active_map`，否则 ⑭ 那张在 LEO 上留着 90 km 的
## 地表远裁面，"太阳只画到 90 km"⇒ 换图之后窗外一片黑，而它**看起来像"没做星空"**。
##
## ## ⚠️ 曝光也要手动压
## 发射点是**夜图**（`MapDef._pacific_night()`）而且全是黑海面 ⇒
## `env.adjustment_enabled` 不开的话，火箭与泡沫环都是一团黑，什么都读不出。
## 见 `_set_exposure()`（只动曝光，**不改时段** —— 改时段会把"夜色"这个真条件换掉）。
## ⚠️ 但它是个**全屏乘性增益**（`brightness 2.6`）：任何本来就亮的东西
##（比如那片橙色的烟）一乘就顶到 255，于是"幕布到底透过多少"这件事**没法判**。
## ⇒ 每张图都能单独指定曝光，而 `SHOT` 行会把当时的 `brightness` 打出来。
##
## ## ⚠️ 每张图都附一条像素读数
## `SHOT <路径> <相机> <曝光> err=<0=成功> [亮 <亮像素占比> / 均值 / 最亮]`。
## 判"空景 vs 有内容"看 `lit`：只有星点是**万分之几**，有箭体/海面/地球是**百分之几**。
## 第一版九张全黑时 `lit` 恒为 0.0000~0.0015，而**光看文件名与 `err=0` 完全看不出来**。
##
## 跑法（**不能加 `--headless`**，dummy 渲染器抓出来全黑）：
##   godot --path <工程> res://tools/_rocket_shots.tscn -- <输出目录>

var out_dir := "user://rocket_shots"
var _idx := 0
var world: WorldBuilder
var rocket: RocketBody
var cam: Camera3D
## ★ 真的 `ChaseCamera`（④⑫⑭ 用；手摆机位证明不了工程里那一档算成那样）。
var chase: ChaseCamera
## ★ 全周天座舱那一层（HUD）：⑭⑮ 用它 —— 舱内表现在是**屏幕空间的**，
## 工程里**一件 3D 舱几何都没有**（第一版那套 `RocketCockpit` 已被老板否掉、
## 文件已归档；老板：「**你驾驶舱做的好丑，直接用全周天驾驶舱的代码吧**」）。
var hud: FlightHUD
var hud_layer: CanvasLayer
var flame: RocketFlame
## 被 `_clear_fog_only()` 关掉之前的状态（**用完必须还**，见文件头）。
var _fog_saved := {}
## 当前生效的曝光增益（写进 `SHOT` 行，免得"哪张压过曝"要靠猜）。
var _brightness := 1.0
## ★ 每次 `_chase_readout()` 记一个"相机离箭"的读数 —— 末尾给一条极差。
##
## 老板：「**相机要一直和火箭保持一个距离**」。这条需求**不能只在一个高度上量**：
## 静置时量到 80.92 m 证明不了末段 8 km/s 时它还是 80.92 m
##（旧版的弹簧在那里会落后 1 231 m，而画面上看起来只是"镜头在跟随"）。
var _dist_log: Array = []


func _ready() -> void:
	# ⚠️ **看门狗**：带窗口跑时 `_ready()` 里任何一条抛错都会静默中断协程，
	# 而 `quit()` 在最后一行 ⇒ 进程**永远不退出**。
	get_tree().create_timer(420.0).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	# ============================================================ 世界
	#
	# ⚠️ `Game.active_map` **必须与 `world.apply_map()` 同步写** ——
	# `ChaseCamera._sync_depth_range()` 读的是它（见文件头最后那段）。
	world = WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	Game.active_map = MapDef.pacific()
	world.apply_map(Game.active_map)
	await _frames(20)

	cam = Camera3D.new()
	cam.name = "ProbeCam"
	cam.fov = 60.0
	cam.near = 1.0
	add_child(cam)
	cam.current = true
	_set_far_for(world.map)

	# ---- 火箭：**浸在海里**（平台已砍），挂上模型 ----
	rocket = RocketBody.new()
	rocket.name = "MaftyRocket"
	rocket.configure(LaunchScript.ASCENT_SPAN)
	add_child(rocket)
	# ⚠️ 出生点 = `launch_pos() + rest_alt()`，与 `main.gd._begin_launch()` **逐字同源**。
	# 两边分家的话图上读出来是"火箭悬在水面上 / 沉到海底"，而它**不报错**。
	rocket.place_at_launch(LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))
	var ps := load("res://assets/models/mafty_rocket/mafty_rocket.glb") as PackedScene
	if ps == null:
		push_error("火箭资产载不到 ⇒ 后十四张图全是空景")
	else:
		rocket.set_model(ps.instantiate())
	await _frames(4)

	# ---- ★ 火焰拖尾：**按 `main.gd._begin_launch()` 的方式接线** ----
	flame = RocketFlame.new()
	rocket.add_child(flame)

	# ---- ★ 真的 `ChaseCamera` ----
	#
	# ⚠️ `set_target()` 要在 `set_launch_view()` **之前**：后者会立刻
	# `global_position = _desired_position()`（它需要 target）。
	#
	# ⚠️⚠️ 它一进树就 `current = true`（`ChaseCamera._ready()` 里那一行）
	# ⇒ **必须在它之后把 `cam` 抢回来**，否则 ①②③ 会用追尾机位去拍（第一版就是这么错的）。
	chase = ChaseCamera.new()
	chase.name = "ChaseCamera"
	add_child(chase)
	chase.set_target(rocket)
	chase.set_launch_view(true)
	_use_cam(cam)

	# ---- ★★ 座舱（全周天那一层）：按 `main._begin_launch()` + `_sync_cockpit_hud()` 的方式接线 ----
	#
	# ⚠️ 2026-09-30 晚：舱内表现从**一套 3D 几何**（`RocketCockpit`）换成
	# **HUD 的那一层**（刻度导轨 + 仪表台 + 取景框）。第一版那套已被老板否掉
	#（「**你驾驶舱做的好丑，直接用全周天驾驶舱的代码吧**」）并**已从工程删除**。
	# ⇒ 探针这边不再建 3D 节点，而是建一个 `FlightHUD`、把 `camera` 与那三个开关
	# 照 `main.gd._sync_cockpit_hud()` 的写法填上。
	#
	# ⚠️ **必须摆在 `chase` 之后**：HUD 那三块都要 `camera` 才画得出来
	#（`can_draw()` 只查它）。
	# ⚠️ 而且**必须挂在 `CanvasLayer` 下**：`FlightHUD` 是 `Control`，`_ready()` 里
	# `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` 要一个能给尺寸的父
	#（挂在裸 `Node` 下 size 恒为 0 ⇒ 仪表台全部挤在左上角，而它**不报错**）。
	hud_layer = CanvasLayer.new()
	hud_layer.name = "ProbeHudLayer"
	add_child(hud_layer)
	hud = FlightHUD.new()
	hud.name = "ProbeHUD"
	hud_layer.add_child(hud)
	hud.camera = chase
	hud.visible = true
	await _frames(4)

	_set_exposure(2.6)
	_cloud_probe()

	# ---- ★ 判据读数：机身在世界里的真实包围盒 ----
	# 火箭是**直立**的 ⇒ 世界 X = 机体 X（助推器排开的方向）、世界 Y = 机身高度、
	# 世界 Z = 机体 Y（"厚"的方向）。
	# ⇒ 这一行直接读出"宽 / 高 / 厚"三个数，和 ⑤⑥ 两张图互为佐证。
	var bb := _world_aabb(rocket.model_root())
	print("== 火箭世界包围盒 size = (X %.1f, Y %.1f, Z %.1f) m  ⇒  宽X / 高Y / 厚Z"
		% [bb.size.x, bb.size.y, bb.size.z])
	print("== ⇒ 助推器沿 **世界 X** 排开（宽 %.1f m）> 厚 %.1f m ⇒ 从世界 ±Z 看是左右并排"
		% [bb.size.x, bb.size.z])
	print("== 发射点 launch_pos() = (%.0f, %.0f)；箭底静置 y = %.0f m（吃水 %.0f m）；平台已**整个砍掉**"
		% [LaunchScript.launch_pos().x, LaunchScript.launch_pos().z,
			LaunchScript.rest_alt(), LaunchScript.PAD_DRAFT])
	# ⚠️ `base_fov` 是**实例**上的 `@export`（没有 const 版本）⇒ 只能建一台临时相机读。
	# 读完**立刻 `free()`**：不入树的 `Node` 不会被自动回收，留着会在退出时打一串
	# `ObjectDB instances leaked`，而那看起来像"探针有 bug"。
	var tmp_cam := ChaseCamera.new()
	print("== 相机口径：base_fov %.0f° / `LAUNCH_OFFSET` (%.0f, %.0f) / `LAUNCH_NEAR` %.2f（两档共用）"
		% [tmp_cam.base_fov, ChaseCamera.LAUNCH_OFFSET.y, ChaseCamera.LAUNCH_OFFSET.z,
			ChaseCamera.LAUNCH_NEAR])
	print("== 远裁面：`GROUND_FAR` %.0f km / `ORBIT_FAR` %.0f km（★ 从 1e7 降到 7e6 —— 见 `ORBIT_FAR` 那张定点扫描表）"
		% [ChaseCamera.GROUND_FAR / 1000.0, ChaseCamera.ORBIT_FAR / 1000.0])
	tmp_cam.free()
	_geom_probe()

	# ============================================================ ① 发射点全景
	var base := LaunchScript.launch_pos()
	# ★ 这一张回答两件事：**水面上没有任何人造物**（平台砍了）+ **头顶真有一垛云**。
	# ⚠️ 机位取"海面上 210 m、斜后方 1.15 km、往上看 900 m"：
	#   · 再低（近水面）就看不到头顶那垛云，只有一条海平线；
	#   · 再高，那垛云（1500~5000 m）会把箭体整个吞掉。
	await _look(cam, base + Vector3(0.0, 210.0, 1150.0),
		base + Vector3(0.0, 900.0, 0.0), "01_sea_site")

	# ============================================================ ②③ 出水
	#
	# ★★ 这两张是「从海里出来」的**唯一**证据：泡沫环 + 烟 + 箭体正穿过水面。
	# 没有它们的话，"只把箭体从水下搬到水上"读起来是**穿模**。
	#
	# ⚠️⚠️ 必须**把特效和箭一起驱动**：`_fly_to_alt()` 走的是真实 `step()`，
	# 而 `SeaSplash.update()` 要拿**同一帧的箭底高度**喂 —— 少喂一次，
	# 图上就是"环涨开了但箭还在水里"（或者反过来），而那**正是**第一版
	# "半径按时间扩散"那个 bug 的画面表现（见 `SeaSplash.RING_GROW_ALT`）。
	#
	# ⚠️ 第二版把"水柱"换成了**烟团**（老板：「做成风压太丑陋了，还不如做成烟雾呢」）
	# ⇒ 读数也从 `col_alpha` 换成 `smoke_alpha`（`col_alpha` 那个字段已经删了，
	# 探针还读它的话就是一个**编译期不报错、永远读 0** 的假读数）。
	world.launch_splash.begin()
	await _fly_to_alt(14.0, true)     # 箭底出水 14 m ⇒ 箭体正穿过水面
	print("== 出水：箭底 y = %.1f m / 阶段 = %s / 环 alpha = %.3f / 烟 alpha = %.3f"
		% [rocket.global_position.y, rocket.leg_name(),
			world.launch_splash.ring_alpha, world.launch_splash.smoke_alpha])
	await _look(cam, base + Vector3(46.0, 22.0, 175.0),
		base + Vector3(0.0, 20.0, 0.0), "02_breach_side")
	# ★ 出水**俯视**：读得出"环"是**环**（内缘 0.78 留出的空档）。
	# ⚠️ 半径上限 860 m ⇒ 机位必须拉到 1150 m 高，否则环带在画面里只有十几像素，
	# "环"与"一坨糊在水面的白斑"分不出来。
	await _look(cam, base + Vector3(30.0, 1150.0, 30.0), base, "03_breach_top")

	# ============================================================ ④ 真机追尾档
	#
	# ★★ 老板：「**镜头离火箭太远了，我希望做全程跟随的**」。
	# 这一张就是那条需求的判据：**工程里的那一档机位**（不是手摆的）。
	await _fly_to_alt(180.0, true)
	# ⚠️ 这一等**现在只是让渲染帧稳下来**，不再是为了"等弹簧收敛"：
	# 舱外档已经是刚性落位（`_rigid_chase()`，见 ⑧⑨ 之后那段），位置每帧硬写。
	# 从前 `follow_lag = 6.5` 要等约 0.7 s 才进稳态，不收敛的话拍到的是
	# "上一套机位往新机位飞的中间态"，而它看起来只是"镜头位置有点怪"。
	_use_cam(chase)
	await _frames(120)
	_chase_readout("④ 追尾档")
	await _shot("04_chase_follow")

	# ============================================================ ⑤⑥ 箭体姿态
	# ★ 判据点：沿**世界 Z** 平视（机体 +X 落在画面水平方向 ⇒ 助推器左右并排）。
	# 箭底 180 m ⇒ 水下那 34 m 看不到，读得出"整支箭长什么样"。
	await _look(cam, rocket.global_position + Vector3(0.0, 22.0, 148.0),
		rocket.global_position + Vector3(0.0, 26.0, 0.0), "05_rocket_side")
	# ★ 判据点：正俯视（读横截面 **宽 > 厚**）。
	#
	# ⚠️ 第一版写的是 `cam.global_basis = Basis()` —— 那是**水平朝世界 −Z**，
	# 根本不在俯视（相机的视线是自身 −Z）。而它拍出来"看着像俯视"是因为
	# 那张图整个是黑的（见文件头 far 那段），黑屏看不出朝向。
	# ⇒ 正俯视要**真的把视线转到 −Y**：用 `look_at`，`up` 取水平的世界 +Z
	#（`Vector3.BACK`）—— 它与视线不平行，滚转才是确定的。
	# 机位取"箭顶之上 78 m"：`ROCKET_HEIGHT_M` 58 + 78 ⇒ 横截面在画面里约 110 px 宽，
	# 读得出"左右两个助推器"而不是一个点。
	var top := rocket.global_position
	await _look(cam, Vector3(top.x + 0.5, top.y + RocketBody.ROCKET_HEIGHT_M + 78.0, top.z),
		top + Vector3(0.0, 29.0, 0.0), "06_rocket_top")

	# ============================================================ ⑦ 头顶那垛云（单独一张）
	#
	# ★★ 老板：「**云层贴图过于敷衍了，需要用模型遮挡**」。
	# 全屏云幕（`RoomCurtain`）贴在相机上、**跟着相机走 ⇒ 它没有视差**，
	# 单靠它读起来就是"糊了一层贴图" —— 老板看的就是那个。
	# 这一张要回答的是"发射点上空那垛是**真几何**吗"：有前后、有远近、有体积，
	# 而不是一层贴片。⇒ 机位侧移到云垛旁边、从**里面**往外看。
	#
	# ⚠️ 这一张**只关雾、必须留着 `_cloud_root`** —— 关掉云层就没东西可拍了。
	# 而且机位要**退到云垛外面**（铺开半径 9.8 km ⇒ 站到 13 km 外往里看）：
	# 站在云垛里面拍到的是一屏白，读不出"有前后"。
	# ⚠️ 曝光也压到 1.4：这张的天顶是**夜空的近地平带**，2.6 倍增益会把上半屏整个顶白。
	_clear_fog_only()
	_set_exposure(1.4)
	await _look(cam, base + Vector3(0.0, 3800.0, 13000.0),
		base + Vector3(0.0, 3000.0, 0.0), "07_cloud_mound")
	_restore_fog()
	_set_exposure(2.6)

	# ============================================================ ⑨d 新 UI 块：**告警阈值真的分开了吗**
	#
	# ★★ 老板 2026-09-30 晚：「**另外开机体的UI系统也搬过来（不搬雷达系统）**」，
	# 选定的范围是「**接火箭真有的读数**」⇒ 补了三块：**机名标签 / 姿态仪 / 告警**。
	# 这一张就是那三块的**真机像素证据**（套件里那几条是源码子串与纯函数，证明不了"画出来了"）。
	#
	# ## ⚠️ 为什么挑 7 km 这一档（不是随手挑一个高度）
	# 火箭的过载是**几何决定的**（`LaunchScript.accel_g_estimate()`），7 km 处 ≈ **21.5 G**：
	#   · **大于**机体的 `OVER_G_THRESHOLD`（12 G）；
	#   · **小于**发射段的 `LAUNCH_OVER_G`（50 G）。
	# ⇒ 这张图上**不该**有 `OVER G`。若哪天有人把发射段的阈值改回 12 G，**它就会亮**
	# —— 而"亮了一条告警"看起来完全像"告警正常工作"，不会有人起疑。
	# 同一张图上还应当看得见**姿态仪**（地平线/滚转读的是火箭自己的基）与
	# **机名标签**（箭名 + 阶段 +「余 N s」）；**雷达圆盘是空的**（老板：不搬雷达系统）。
	#
	# ⚠️ 必须在 ⑧**之前**：`_fly_to_alt()` **只往上飞**（`while y < target`），
	# ⑧ 一到 8 km 就再也回不到 7 km 了。
	await _fly_to_alt(7000.0, true)
	chase.set_launch_view(true)
	chase.set_launch_eye(ChaseCamera.LaunchEye.COCKPIT)
	hud.cockpit_only = true
	hud.visible = true
	_use_cam(chase)
	await _frames(10)
	# ⚠️ 速度必须走**解析式**（`ascent_velocity()`）：`_fly_to_alt()` 虽然真跑了 `step()`，
	# 但下面还要再飞两段，这里统一按 u 取，免得"这张图是 8 km 的速度"。
	var u7 := pow(clampf((rocket.global_position.y - LaunchScript.rest_alt())
		/ maxf(LaunchScript.ORBIT_ALT - LaunchScript.rest_alt(), 1.0), 0.0, 1.0),
		1.0 / LaunchScript.ALT_SHAPE)
	_sync_hud_at(rocket.global_position.y, LaunchScript.ascent_velocity(u7).length(),
		(1.0 - u7) * LaunchScript.ASCENT_SPAN, 0.0,
		LaunchScript.ascent_pitch_deg(u7), LaunchScript.ascent_velocity(u7).y, _rocket_hdg())
	await _frames(6)
	var wl := _hud_readout("⑨d 座舱档 / 7 km（21.5 G ⇒ 应当**不报** OVER G）")
	print("   · ★★ 这张图的判据：告警 = 「%s」（应当是「一条都不亮」）"
		% ("一条都不亮" if wl == "" else wl))
	await _shot("09d_ui_low")
	# 还原成舱外档 —— ⑧⑨ 走的是手摆机位 + 无座舱层。
	chase.set_launch_eye(ChaseCamera.LaunchEye.CHASE)
	hud.cockpit_only = false
	hud.cockpit_eye = false
	hud.cockpit_readout = {}
	hud.launch_warn = {}
	hud.visible = false

	# ============================================================ ⑧ 参考图构图（远景）
	#
	# ★ 老板给了一张参考图（`发射场景参考`）：**细长箭体 + 一条极长的橙白色尾焰
	#   拖向下方云层、底部积云被尾焰烤亮、深夜蓝黑星空**。
	# 这一张就是照那个构图摆的：机位在**箭体斜后上方**、**朝着发射点回看** ——
	# 于是画面里"箭在上、焰往下、云垛在下方远处"，与参考图同构。
	#
	# ⚠️ 机位方向**不能写死**（这文件为"写死机位"翻过车：写死图心 ⇒ 拍到中央公园；
	# 换个写死坐标 ⇒ 拍到海里）。这里取"从火箭指向发射点的水平方向"，
	# 与 `ascent_pos()` 的航迹**同源** ⇒ 无论曲线怎么改，镜头永远回看发射点。
	await _fly_to_alt(8000.0, true)
	var to_pad := LaunchScript.launch_pos() - rocket.global_position
	to_pad.y = 0.0
	if to_pad.length() < 1.0:
		to_pad = Vector3(0.0, 0.0, 1.0)
	to_pad = to_pad.normalized()
	cam.fov = 60.0
	await _look(cam, rocket.global_position + Vector3(0.0, 160.0, 0.0) - to_pad * 700.0,
		rocket.global_position + Vector3(0.0, -60.0, 0.0), "08_flame_wide")
	print("== ⑧ 远景：箭底 %.0f m / 下程 %.0f m / 机位离发射点 %.0f m（朝发射点回看）/ 焰长 %.0f m"
		% [rocket.global_position.y,
			Vector2(rocket.global_position.x - LaunchScript.launch_pos().x,
				rocket.global_position.z - LaunchScript.launch_pos().z).length(),
			cam.global_position.distance_to(LaunchScript.launch_pos()), flame.length])

	# ============================================================ ⑨ 大型火焰拖尾（近景）
	#
	# ★★ 老板：「**火箭升空的时候都没有大型火焰拖尾**」。
	# 25 km 处的焰长 = `lerp(LEN_MIN 46, LEN_MAX 262, 25/55)` ≈ **144 m**，箭体 58 m
	# ⇒ 焰是箭体的 **2.5 倍**。"大型"这个词的全部来源就在这一张里。
	#
	# ⚠️ 这张必须排在**换图之前**（⑩⑪ 才是换图）：换到 LEO 之后就**没有夜海、
	# 没有云垛**了，而老板那张参考图的构图（箭 + 长焰 + 夜海 + 被烤亮的云底）
	# 只在这张的机位下存在（这条也是"换图触发高度必须抬到卡门线"的理由之一，
	# 见 `LaunchScript.REVEAL_ALT` 那段）。
	await _fly_to_alt(25000.0, true)
	cam.fov = 60.0
	await _look(cam, rocket.global_position + Vector3(0.0, -40.0, 330.0),
		rocket.global_position + Vector3(0.0, -70.0, 0.0), "09_flame_side")
	print("== ⑨ 火焰：箭底 %.0f m / 节流 strength %.2f / 膨胀 widen %.2f / 焰长 %.1f m（箭体 %.0f m 的 %.2f 倍）"
		% [rocket.global_position.y, flame.strength, flame.widen, flame.length,
			RocketBody.ROCKET_HEIGHT_M, flame.length / RocketBody.ROCKET_HEIGHT_M])
	for ly in flame.get_children():
		var mi := ly as MeshInstance3D
		if mi != null and mi.mesh != null:
			var ab := _world_aabb(mi)
			print("   · 层 %s：世界包围盒 = (%.1f, %.1f, %.1f) m / 最高点世界 y = %.1f m（箭底 %.1f m）"
				% [mi.name, ab.size.x, ab.size.y, ab.size.z, ab.end.y, rocket.global_position.y])

	# ============================================================ ⑨b 三根尾焰（芯级 + 左右助推器）
	#
	# ★★ 老板 2026-09-30 晚：
	# > 「**火箭下面只有一条长拖尾，但是火箭左右两边还有辅助推进器，
	# >   这两条辅助推进器都需要做尾焰和拖尾**」
	#
	# ## ⚠️ 为什么这一张必须**贴着箭底**拍（追尾 / 侧视都不行）
	# 加色混合下三根焰会糊成一根更宽的柱：芯级焰外沿半径 = `R_MAX` 17.5 m，
	# 而"两条侧焰的外沿" = 7.72 + 17.5 × 0.55 = **17.3 m** —— 两者几乎一样宽
	# ⇒ **"横向展宽"这个读数区分不出一根还是三根**（差 0.2 m，比像素还小）。
	# 只有从**箭底斜下方**（三个喷口的"正面"）拍，三个起点在画面上才是
	# 三个**分开的位置** —— 那是"三根"这件事唯一能被眼睛判定的机位。
	cam.fov = 60.0
	await _look(cam, rocket.global_position + Vector3(180.0, -130.0, 180.0),
		rocket.global_position + Vector3(0.0, -18.0, 0.0), "09b_nozzles")
	# 数值判据：三根焰各自的**起点**（箭体局部）与长度 —— 图给人看，数给回归看。
	var nz_meshes: Array = flame.get("_meshes")
	for i in nz_meshes.size():
		var mi3 := nz_meshes[i] as MeshInstance3D
		if mi3 == null:
			continue
		print("   · 焰 %-9s：x %+7.2f / 起点 z %+7.2f / 长 %6.1f m / 半径 %5.1f m"
			% [String(mi3.name), mi3.transform.origin.x,
				mi3.transform.origin.z - mi3.transform.basis.y.length() * 0.5,
				mi3.transform.basis.y.length(), mi3.transform.basis.x.length()])

	# ============================================================ ⑨c 追尾档移到**箭体对侧**
	#
	# ★★ 老板 2026-09-30 晚：「**镜头转过去拍火箭的另外一面**」
	# ⇒ `ChaseCamera.LAUNCH_OFFSET.y` 由 `+62` 变 `−62`（绕箭体轴 180°）。
	# 这一张走**真的 `ChaseCamera`**（`set_launch_view(true)` + `set_launch_eye(CHASE)`），
	# **不是手摆机位** —— 手摆的机位证明不了"工程里那一档真算成那样"。
	#
	# ## ⚠️ 判据是"相机落在箭体哪一侧"，**不是**"图看着像不像"
	# 把相机的世界位置反解回**箭体局部**（`basis.inverse() * (相机 − 箭底)`），
	# 看那个 `y` 的符号 —— 它必须与 `LAUNCH_OFFSET.y` **同号**。
	# ⚠️ 这一对符号错了的症状是「玩家按左键往右转」，而它**不报任何错**：
	# 套件里那一条源码子串断言抓的正是它（见 `suite_rocket_launch` 的机位一节）。
	chase.set_launch_eye(ChaseCamera.LaunchEye.CHASE)
	_use_cam(chase)
	await _frames(40)
	var local := rocket.global_transform.basis.inverse() \
		* (chase.global_position - rocket.global_position)
	print("== ⑨c 追尾档：相机在**箭体局部** (%+.1f, %+.1f, %+.1f) m / `LAUNCH_OFFSET` (%.0f, %.0f, %.0f)"
		% [local.x, local.y, local.z,
			ChaseCamera.LAUNCH_OFFSET.x, ChaseCamera.LAUNCH_OFFSET.y, ChaseCamera.LAUNCH_OFFSET.z])
	print("   · ★ 实测局部 `y` %+.1f ⇒ 相机在箭体**%s**；`LAUNCH_OFFSET.y` %+.0f 与它同号 ⇒ 真机位确实走上了那个常量"
		% [local.y, "−y 侧（对侧，老板要的那一面）" if local.y < 0.0 else "+y 侧（原侧）",
			ChaseCamera.LAUNCH_OFFSET.y])
	_chase_readout("⑨c 追尾档（对侧）")
	await _shot("09c_chase_flip")

	# ============================================================ ⑨e 同一块 UI 的**告警真亮**那一档
	#
	# 与 ⑨d 成对：44 km 处过载 ≈ **51 G**，刚跨过发射段的 50 G 阈值
	# ⇒ 这一张上**应当看得见 `OVER G`**（`WARN_STYLE` 里它是常亮，`flash = 0`）。
	# ⚠️ 两张缺一不可：⑨d 证明"阈值不是机体的 12 G"，⑨e 证明"这条告警真的会亮"。
	# 只出 ⑨e 的话，"告警块根本没接上"与"接上了但阈值定得离谱"分不出来。
	chase.set_launch_view(true)
	chase.set_launch_eye(ChaseCamera.LaunchEye.COCKPIT)
	hud.cockpit_only = true
	hud.visible = true
	_use_cam(chase)
	await _fly_to_alt(44000.0, false)
	await _frames(10)
	var u44 := pow(clampf((rocket.global_position.y - LaunchScript.rest_alt())
		/ maxf(LaunchScript.ORBIT_ALT - LaunchScript.rest_alt(), 1.0), 0.0, 1.0),
		1.0 / LaunchScript.ALT_SHAPE)
	_sync_hud_at(rocket.global_position.y, LaunchScript.ascent_velocity(u44).length(),
		(1.0 - u44) * LaunchScript.ASCENT_SPAN, 0.0,
		LaunchScript.ascent_pitch_deg(u44), LaunchScript.ascent_velocity(u44).y, _rocket_hdg())
	await _frames(6)
	var wh := _hud_readout("⑨e 座舱档 / 44 km（51 G ⇒ 应当**报** OVER G）")
	print("   · ★★ 这张图的判据：告警 = 「%s」（应当是 `over_g`）" % ("一条都不亮" if wh == "" else wh))
	await _shot("09e_ui_high")
	# 还原成舱外档 —— ⑩ 换图那一段会自己切回座舱档。
	chase.set_launch_eye(ChaseCamera.LaunchEye.CHASE)
	hud.cockpit_only = false
	hud.cockpit_eye = false
	hud.cockpit_readout = {}
	hud.launch_warn = {}
	hud.visible = false

	# ============================================================ ⑩⑪ 换图窗口（玩家看不看得见）
	#
	# ★★ 老板 2026-09-30 第三次改（这一段就是那三条需求的判据）：
	# > 「**不需要云层了**」（⇒ 整屏云幕 `RoomCurtain` 连文件一起删掉）
	# > 「**把玩家视角跳到座舱内，然后星空盒都是同一片的情况下可以直接换**」
	# > 「**相机要一直和火箭保持一个距离**」（④ 那张的 `_chase_readout` 已经量了）
	#
	# ## 换图窗口的**唯一遮挡物**从"全屏幕布"变成了"**全周天座舱那一层**"
	# 而"这一层挡住了多少"**没有画面之外的判据**（套件里只能断言源码与接线）。
	# ⇒ 这里成对拍两张 + **两次**逐像素差：
	#   · 基线：同一静止机位、相隔 20 帧、**什么都没换** ⇒ 画面自己会动多少；
	#   · 换图：同一机位，只差一次 `apply_map_staged()`。
	# 换图那一张的 `>40 占比` 减去基线，才是"这次换图被玩家看到的分量"。
	#
	# ⚠️ **不加基线就是自欺**：云垛在转、海雾在飘，那些像素自己就在变；
	# 少了这一栏，分不清"换图改的"与"画面本来就在动"。
	#
	# ⚠️ 高度取 `REVEAL_ALT`（**卡门线**，与 `main.gd._tick_launch()` 的触发同源）。
	# 这条不是随便挑的：换图之后就没有夜海与云垛了，而老板要的
	# 「大型火焰拖尾 / 箭 + 长焰 + 夜海 + 被烤亮的云底」只在这之下存在
	# ⇒ 换图必须**抬到大气层外**，否则整段大气层内上升被砍掉 99%。
	await _fly_to_alt(LaunchScript.REVEAL_ALT, true)
	chase.set_launch_eye(ChaseCamera.LaunchEye.COCKPIT)
	hud.cockpit_only = true
	hud.visible = true
	_use_cam(chase)
	await _frames(20)
	# ★ 这里可以用**实时** `rocket.speed()`：这一张之前刚跑过 `_fly_to_alt()`，
	# `velocity` 是 `step()` 真推出来的（与后文瞬移之后的情形相反，见 `_sync_hud_at()`）。
	_sync_hud_at(rocket.global_position.y, rocket.speed(),
		(1.0 - clampf(rocket.u, 0.0, 1.0)) * LaunchScript.ASCENT_SPAN, 0.0,
		rocket.pitch_deg(), rocket.velocity.y, _rocket_hdg())
	_hud_readout("⑩ 换图前（座舱档 / 卡门线）")
	var img_b1 := await _grab()
	await _shot("10_swap_before")
	await _frames(20)
	var img_b2 := await _grab()
	var base_d := _img_diff(img_b1, img_b2)
	print("== 基线（同一静止机位 / 相隔 20 帧 / 什么都没换）：均值 %.2f / 最大 %d / 差 >40 占比 %.4f"
		% [base_d.mean, base_d.maxv, base_d.frac])

	var t_swap := Time.get_ticks_msec()
	Game.active_map = MapDef.leo()          # ★ 与 `world.apply_map_staged()` 同步（见文件头）
	await world.apply_map_staged(Game.active_map)
	var build_ms := int(Time.get_ticks_msec() - t_swap)
	print("== 幕后换图：太平洋 → LEO，耗时 %d ms（座舱档锁着 —— 玩家看见的就是 ⑪ 那张）" % build_ms)
	print("== 换图后 world.map = %s / has_ground = %s"
		% [world.map.name_cn, str(world.map.has_ground)])
	# 把箭搬到轨道高度（真实流程里是它自己飞上去的；这里直接摆位，省 20 秒）
	rocket.global_position = LaunchScript.ascent_pos(1.0 - 0.045)
	rocket.room_swapped = true
	_set_far_for(world.map)   # ★ 换图必须跟着换远裁面（见文件头那张 A/B 表）
	# ⚠️⚠️ 这里**故意不重新喂读数** —— 让仪表台在 ⑩ 与 ⑪ 之间**逐像素不变**。
	# 真机当然每帧都在跳字，但那些字**每一帧都会变**（不是换图造成的）：
	# 重喂一次的话，"换图被玩家看见多少"这个读数里就混进了一份仪表改字，
	# 而它会把结论往"换图藏得住"的方向**偏**（字变多 ⇒ 差变小）。
	# ⇒ 冻住它，差出来的就只剩世界。
	await _frames(20)
	var img_a := await _grab()
	await _shot("11_swap_after")
	var swap_d := _img_diff(img_b2, img_a)
	print("== ★★ 换图前后（同一机位 / 座舱档）：均值 %.2f / 最大 %d / 差 >40 占比 %.4f（基线 %.4f）"
		% [swap_d.mean, swap_d.maxv, swap_d.frac, base_d.frac])
	print("   · 判据：这个占比**越接近基线**，说明「座舱那一层把外面挡住了」；越接近 1.0，"
		+ "说明玩家在一次换图里看见了整屏新东西")
	# 切回舱外档 —— 真实流程里 `_swap_eye_lock` 一放就回追尾档（`_apply_camera_settings()`）。
	# ⚠️ 全周天那一层必须同时关掉（`cockpit_only = false`）：它是**屏幕空间的**，
	# 留在屏幕上就是"舱外视角却顶着一块仪表台"，而它**不会自己消失**。
	# ⚠️ 这里**不用** `hud.visible = false`：⑫ 之后虽然都是舱外图，
	# 但 HUD 本身要继续活着（战斗 HUD 那一路才是 `_finish_launch()` 之后的事）。
	chase.set_launch_eye(ChaseCamera.LaunchEye.CHASE)
	hud.cockpit_only = false
	hud.cockpit_eye = false
	hud.cockpit_readout = {}
	_clear_weather()
	# ★★ 曝光回到**工程自己的那个值**（`world_builder.gd` 里 `adjustment_brightness = 1.0`）。
	#
	# ⚠️ 2.60 是给太平洋**夜图**（全黑海面）压出来的量，换到 LEO 之后画面里多了一整颗
	# 亮地球 ⇒ `12_space_view` 整帧爆成 255（均值 255 / 亮像素 1.0000，文件只有 117 KB），
	# 判据图直接变成一张白纸 —— 而那条 `SHOT` 行**照样打着 `err=0`**。
	#
	# ⚠️ 换的时机必须在 ⑪ **之后**：⑩ 与 ⑪ 是同一机位的逐像素对比，
	# 两次的曝光一旦不同，那一对的差值里就混进了整屏乘性增益。
	_set_exposure(1.0)

	# ============================================================ ⑫ 出云之后（舱外）
	#
	# ⚠️ 原来这一步要把幕布 `request_reveal()` 淡出。幕布删掉之后**没有这一步**了：
	# 换图窗口由**屏幕空间的全周天座舱层**挡着，切回舱外档就是"一下全亮" —— 这正是老板选的方案。
	await _look(cam, rocket.global_position + Vector3(260.0, 90.0, 240.0),
		rocket.global_position, "12_space_view")
	# ★ 出云之后再量一次离箭距离（此时箭快到了、速度是 km/s 量级）——
	# 这是「相机要一直和火箭保持一个距离」这条需求在**末段**的采样点。
	# ⚠️ 少这一个采样，`_dist_summary()` 就只在低速段量过 —— 而那正是
	# 旧版弹簧"看起来也对"的那一段（它的漂移随速度线性增长）。
	await _frames(30)
	_chase_readout("⑫ 出云之后（舱外档）")

	# ============================================================ ⑬ 抵达
	rocket.global_position = LaunchScript.arrival_pos()
	flame.update(rocket)
	await _frames(2)
	print("== 抵达点 = (%.0f, %.0f, %.0f) ⇒ 离运输仓 %.1f km"
		% [rocket.global_position.x, rocket.global_position.y, rocket.global_position.z,
			rocket.global_position.distance_to(LaunchScript.pod_pos()) / 1000.0])
	# ★ 构图：机位要落在**箭的背面**（相对运输仓的方向）——
	# 这样画面里"箭在前景、运输仓方向在正前方"。
	# ⚠️ 第一版写的是固定偏移 `+(70, 46, 150)`，而运输仓在 **+X** 侧 ⇒
	# 那个机位把箭**放到相机背后**去了，拍出来只有地球和星星（箭没了）。
	# ⇒ 方向一律**从 POD 推**，不写死。
	var away := rocket.global_position - LaunchScript.pod_pos()
	away.y = 0.0
	if away.length() < 1.0:
		away = Vector3(1.0, 0.0, 0.0)
	away = away.normalized()
	await _look(cam, rocket.global_position + away * 130.0 + Vector3(0.0, 52.0, 0.0),
		LaunchScript.pod_pos(), "13_arrival")

	# ============================================================ ⑭ 座舱档（全周天那一层）
	#
	# ★★ 老板 2026-09-30 晚第三次改：
	# > 「**你驾驶舱做的好丑，直接用全周天驾驶舱的代码吧**」
	# > 「**正常驾驶模式的UI也使用啊，比如燃料和雷达啊高度和时速这些显示器，
	# >   不需要屏幕左上角那么多白色文字了**」
	# ⇒ 第一版给火箭单独建的 3D 舱（`RocketCockpit` + 一块 **7 行白字的 `Label`**）
	# **整套删掉**（文件已归档），舱内表现改成 **HUD 那一层全周天代码**：
	# 刻度导轨（`_draw_cockpit_rails`）+ 仪表台（`_draw_cockpit_dash`）+ 取景框
	#（`_draw_cockpit_frame`），读数走 `hud.cockpit_readout` 那份字典。
	#
	# ## ⚠️⚠️ 所以 ⑭ 的判据**整条换掉了** —— 别照抄旧版那几行
	# 旧版量的是"相机有没有落在眼位 / 八件几何在不在视锥里 / 三块表法线朝哪边"，
	# 那些全是**3D 几何**的问题。现在工程里一件 3D 舱件都不存在
	# ⇒ 那些量法**无对象可量**（量下去只会得到一串 null 判据）。
	# 新判据只有一条，而它正是老板要的那件事：**这一层把像素放在了屏幕的哪些区**。
	# ⇒ 同一机位拍三张**只差一个开关**的图，再做逐像素差，把这一层拆开：
	# | 图 | `hud.visible` | `cockpit_only` | `cockpit_eye` | 应当看见 |
	# |---|---|---|---|---|
	# | `14_cockpit_hud` | true | true | **true** | 导轨 + 仪表台 + 取景框（完整一层） |
	# | `14b_eye_off`    | true | true | **false** | **只剩仪表台**（导轨 / 框消失） |
	# | `14c_hud_off`    | **false** | true | true | 一层都**没有**（对照组） |
	# 差 A−B = 导轨 + 取景框的像素；差 B−C = **仪表台**的像素。
	#
	# ⚠️ 对照组用 `hud.visible = false`、**不是** `cockpit_only = false`：
	# 后者会让 `_draw()` 继续往下跑 `_draw_notices()` / `_draw_comms()` /
	# `_draw_phase_overlay()`，那几块**也会画东西**（探针里 Game 的阶段状态非空）
	# ⇒ 差出来的就不只是"这一座舱层"了，而它**看起来还是一张很像的图**。
	chase.set_launch_view(true)
	chase.set_launch_eye(ChaseCamera.LaunchEye.COCKPIT)
	hud.cockpit_only = true
	hud.visible = true
	_use_cam(chase)
	# ★ 读数的来源见 `_sync_hud_at()` —— 高度/燃料/段位读**实时**，
	# **只有速度**不能用 `rocket.speed()`（探针是瞬移过来的，`velocity` 是 0）。
	_sync_hud_at(rocket.global_position.y, LaunchScript.ascent_velocity(1.0).length(), 0.0,
		0.0, rocket.pitch_deg(), rocket.velocity.y, _rocket_hdg())
	await _frames(8)
	_hud_readout("⑭ 座舱档（全周天层）")
	var hud_a := await _grab()
	await _shot("14_cockpit_hud")

	# ⑭b：关掉导轨 + 取景框那一段（`cockpit_eye = false`）——
	# 这**正是换图那 1.5 s 的形态**（`_swap_eye_lock` 把眼位锁在座舱档、
	# 而 `_sync_cockpit_hud()` 每帧按 `chase.launch_eye()` 写这一位）。
	hud.cockpit_eye = false
	await _frames(6)
	var hud_b := await _grab()
	await _shot("14b_eye_off")

	# ⑭c：整层关掉，当对照。
	hud.cockpit_eye = true
	hud.visible = false
	await _frames(6)
	var hud_c := await _grab()
	await _shot("14c_hud_off")
	hud.visible = true

	var d_ac := _img_diff(hud_a, hud_c)
	var d_ab := _img_diff(hud_a, hud_b)
	var d_bc := _img_diff(hud_b, hud_c)
	print("== ★ 全周天层的像素分解（同机位 / 只差一个开关）：")
	print("   · 整层（A−C）：均值 %.2f / 最大 %d / 差 >40 占比 %.4f" % [d_ac.mean, d_ac.maxv, d_ac.frac])
	print("   · 导轨+框（A−B）：均值 %.2f / 最大 %d / 差 >40 占比 %.4f" % [d_ab.mean, d_ab.maxv, d_ab.frac])
	print("   · 仪表台（B−C）：均值 %.2f / 最大 %d / 差 >40 占比 %.4f" % [d_bc.mean, d_bc.maxv, d_bc.frac])
	_hud_map("整层（A−C）", hud_a, hud_c)
	_hud_map("仪表台（B−C）", hud_b, hud_c)
	print("   · ★ 判据是**分布**，不是总量：仪表台的像素应当**几乎全部落在底栏**；"
		+ "**左上角**（原来那 7 行白字住的地方）应当 ≈ 0。")

	# ============================================================ ⑮ 倒计时档的读数形态
	#
	# ★ 这一张**不在时间线上** —— 它是点火前 8 s 那一档（`LaunchScript.COUNTDOWN`），
	# 排在 ⑭ 之后只为**与 ⑭ 同一个机位**对照。
	# `LaunchScript.dash_readout()` 在 `countdown > 0` 时换一整套文字：
	#   `note` = 「点火倒计时 7.5 s」、`leg` = 「待发」、速度与高度**两根指针归零**
	#（箭浸在水里一动不动）。
	# 套件里断言的是那几行**字符串**（纯函数，喂数核对）；这一张出的是
	# **它们真的被画在屏上**。两件事缺一件都可能是"改对了字、没接上表"。
	chase.set_launch_eye(ChaseCamera.LaunchEye.COCKPIT)
	_sync_hud_at(0.0, 0.0, LaunchScript.ASCENT_SPAN, 7.5)
	await _frames(8)
	_hud_readout("⑮ 倒计时档")
	await _shot("15_cockpit_countdown")
	# 还原成实时读数（后面 `_dist_summary()` 不再用 HUD，但别留一个假状态）。
	_sync_hud_at(rocket.global_position.y, LaunchScript.ascent_velocity(1.0).length(), 0.0)

	_dist_summary()
	print("== 出图完成：%d 张 ⇒ %s" % [_idx, out_dir])
	get_tree().quit(0)


# ============================================================ 工具

## 显式切换"下面这几张用哪台相机"，并把**当时真正生效的那台**打出来。
##
## ⚠️ 它**不是**形式主义：`ChaseCamera._ready()` 里写着 `current = true` ——
## 它一进树就把探针那台 `cam` 顶掉，于是"手摆机位"那几张会用 **ChaseCamera 的变换**
## 去拍（手摆的 `cam.global_position` 白写了）。症状是那几张图全变成同一个机位，
## 而它**不报任何错**。第一版 ①②③ 就是这么废掉的（②③ 逐字节相同）。
## ⇒ 现在每次 `SHOT` 行都带相机名，看日志就能抓住。
func _use_cam(c: Camera3D) -> void:
	cam.current = false
	chase.current = false
	c.current = true
	var got := get_viewport().get_camera_3d()
	print("== 相机切到 %s ⇒ viewport 实际生效：%s"
		% [c.name, got.name if got != null else "★ 没有生效相机"])


## 火箭模型**自身几何**的真值：世界包围盒 + 眼位所在点。
##
## ⚠️ 眼位必须一起打：`rig_anchor("head")` 是一个**常量** `(0, 0, −59)`，
## 它假设"模型顶面在局部 z = −58"。**资产一换、或者 `model_basis()` 的符号一改，
## 这个假设就静默失效** —— 后果是相机跑到箭体外面（或里面）去，
## 而⑭那张只会变成"一片星空"，看不出是位置错了。
## 这一行把"眼位离模型顶面到底多远"直接读出来。
func _geom_probe() -> void:
	var mr := rocket.model_root()
	if mr == null:
		push_error("`model_root()` 是 null ⇒ ⑦ 之后那些图全是空景")
		return
	var bb := _world_aabb(mr)
	# 直立时：模型顶面在世界 y 的最大处；眼位在世界里就是 `rocket.global_transform * eye`。
	var eye_w := rocket.global_transform * rocket.cockpit_eye_local()
	print("== 模型几何：包围盒底 y = %.2f m / 顶 y = %.2f m（箭底 %.2f m）⇒ 顶面高出箭底 %.2f m"
		% [bb.position.y, bb.end.y, rocket.global_position.y, bb.end.y - rocket.global_position.y])
	print("== 眼位（`cockpit_eye_local()`）：机体局部 (%.2f, %.2f, %.2f) ⇒ 世界 y = %.2f m / 高出模型顶面 %.2f m / 离轴 %.2f m"
		% [rocket.cockpit_eye_local().x, rocket.cockpit_eye_local().y, rocket.cockpit_eye_local().z,
			eye_w.y, eye_w.y - bb.end.y,
			Vector2(eye_w.x - rocket.global_position.x, eye_w.z - rocket.global_position.z).length()])
	print("== HUD 座舱层：`cockpit_only` %s / `cockpit_eye` %s / `cockpit_readout` 键 %d 个 / visible %s"
		% [str(hud.cockpit_only), str(hud.cockpit_eye), hud.cockpit_readout.size(),
			str(hud.visible)])


## ★ 真的 `ChaseCamera` 的**实际取值**读数（④）。
##
## 判"是不是真的进了追尾档"只能读这几个字段 + 相机自己的世界坐标：
## 图上"看起来像跟在后面"这件事，手摆一台相机也能做到。
func _chase_readout(tag: String) -> void:
	var d := chase.global_position.distance_to(rocket.global_position)
	# 箭体在画面里占多高（竖直 FOV 的比例）。这是"贴近跟随"唯一的量化判据。
	var half := tan(deg_to_rad(chase.fov * 0.5))
	var frac := (RocketBody.ROCKET_HEIGHT_M / d) / (2.0 * half)
	print("== %s：launch_view %s / eye %d（0=追尾）/ offset (%.0f, %.0f, %.0f) / look_ahead %.0f / roll %.2f / near %.2f"
		% [tag, str(chase.launch_view()), chase.launch_eye(),
			chase.offset.x, chase.offset.y, chase.offset.z,
			chase.look_ahead, chase.roll_blend, chase.near])
	print("   · 相机世界 y = %.1f m（箭底 %.1f ⇒ 高 %.1f m）/ 离箭底 %.1f m / 箭体占屏高 %.1f%%（fov %.0f°）"
		% [chase.global_position.y, rocket.global_position.y,
			chase.global_position.y - rocket.global_position.y, d, frac * 100.0, chase.fov])
	_dist_log.append(snappedf(d, 0.01))


## ★★ 「相机要一直和火箭保持一个距离」的**汇总读数**。
##
## 判据：所有采样点的极差 ≈ 0，且每个点都等于 `LAUNCH_OFFSET.length()`。
## ⚠️ 采样必须跨**衰减到最后一段**（静置 → 卡门线）才有意义 ——
## `_rigid_chase()` 那段表里列过：旧版弹簧在 8 km/s 时落后 1 231 m。
func _dist_summary() -> void:
	if _dist_log.is_empty():
		return
	var lo: float = _dist_log[0]
	var hi: float = _dist_log[0]
	for v: float in _dist_log:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var want := ChaseCamera.LAUNCH_OFFSET.length()
	print("== ★★ 追尾档离箭距离：%d 次采样 = %s m ⇒ 极差 %.4f m"
		% [_dist_log.size(), str(_dist_log), hi - lo])
	print("   · 参考值 `LAUNCH_OFFSET.length()` = %.4f m / 最大偏差 %.4f m ⇒ %s"
		% [want, maxf(absf(hi - want), absf(lo - want)),
			"恒定" if maxf(absf(hi - want), absf(lo - want)) < 1.0 else "★ 会漂（弹簧没被绕开）"])


## ★ 复刻 `main._sync_cockpit_hud()` 的**全部**接线 —— 除了速度的来源。
##
## ## ⚠️⚠️ 为什么速度不能读 `rocket.speed()`
## 探针是**瞬移**到抵达点的（`rocket.global_position = LaunchScript.arrival_pos()`），
## `RocketBody.velocity` 从来没被 `step()` 推过 ⇒ `speed()` 读出来是 **0 m/s**
## ⇒ 仪表盘报「0 KM/H」、指针落零。而这张图**看起来像"表没接上"** ——
## 它和"表本来就该报满量程"（`END_SPEED_MS` 就是抵达速度）是两个完全相反的结论。
## ⇒ 速度改喂 `LaunchScript.ascent_velocity(u).length()`（**解析速度**，与
## `ascent_pos()` 同源）；高度 / 燃料 / 段位**照旧读实时状态**。
##
## [param left_s] 剩余秒数**显式传**：瞬移之后 `rocket.u` 停在换图那一刻的值
##（≈ 0.38），直接拿它算会印出「余 37 s」而箭已经在 550 km 处 —— 那是句假话。
func _sync_hud_at(alt_m: float, spd_ms: float, left_s: float, countdown := 0.0,
		pitch := 0.0, vs := 0.0, hdg := 0.0) -> void:
	if hud == null or not is_instance_valid(hud):
		print("== ★ HUD 不在（`FlightHUD.new()` 那一段没跑到）⇒ ⑭⑮ 会是一屏裸 3D")
		return
	# 每帧**照 `main._sync_cockpit_hud()` 重新推**这一位：眼位档可以被 `_swap_eye_lock`
	# 临时锁住，而"画不画导轨与取景框"只认 `chase.launch_eye()`，不认设置。
	hud.cockpit_eye = chase.launch_view() \
		and chase.launch_eye() == ChaseCamera.LaunchEye.COCKPIT
	# ⚠️ `rocket == null` 那一支**不能省**：`dash_readout` 之外的三处实时读数都在它上面。
	if rocket == null or not is_instance_valid(rocket):
		hud.cockpit_readout = {}
		hud.cockpit_basis = Basis()
		hud.launch_warn = {}
		return
	# ⚠️⚠️ `pitch` / `vs` / `hdg` 三个**必须真的喂**：它们默认 0，而 0 在高度块上
	# 长成 `PITCH +0.0° / VS +0 m/s / HDG 000` —— 那是**看着完全正常的假读数**
	#（第一版就是这样，三行恒零而没有任何一条判据会红）。
	hud.cockpit_readout = LaunchScript.dash_readout(alt_m, spd_ms,
		rocket.base_throttle, rocket.fuel_fraction(), rocket.leg_name(), left_s, countdown,
		pitch, vs, hdg)
	# ★★ 2026-09-30 晚第五改：`main._sync_cockpit_hud()` 多了**两路**接线
	#（姿态源 `cockpit_basis` 与告警原始量 `launch_warn`）—— **探针必须同步**。
	# 不同步的症状：验收图里姿态仪读的是**单位阵**（地平线恒在正中、滚转恒 0）、
	# 告警块**永远空**……而探针打印出来的每一行读数**照旧全绿**。
	# 这就是"探针与主程序分家"的经典坑（本工程"两次真源"那一类）。
	hud.cockpit_basis = rocket.global_transform.basis
	hud.launch_warn = {} if countdown > 0.0 else {
		"alt": alt_m,
		"vs": vs,
		"g": _g_at_alt(alt_m),
	}


## 由高度**反查**上升曲线上的过载（G）。
##
## ## 为什么不能读实时值
## 探针是**瞬移**到各档高度的（`_fly_to_alt()`），`rocket.velocity` 从来没被
## `step()` 推过 ⇒ 垂直速度是 0；而 `rocket.u` 停在换图那一刻（≈0.38）
## ⇒ 直接拿它算会在 550 km 那张图上印出 10 G。两个数都是**假的**。
##
## ## 反查走解析式（不是另写一张表）
## `alt = rest_alt() + (ORBIT_ALT − rest_alt()) · u^ALT_SHAPE`
## ⇒ `u = ((alt − rest_alt()) / (ORBIT_ALT − rest_alt()))^(1 / ALT_SHAPE)`，
## 再喂回 `accel_g_estimate()` —— 与 `main` **同一个真源**。
## 自己另写一张"高度 → G"的表，就等于给验收图开了第二份真源。
func _g_at_alt(alt_m: float) -> float:
	var lo := LaunchScript.rest_alt()
	var span := LaunchScript.ORBIT_ALT - lo
	var f := clampf((alt_m - lo) / maxf(span, 1.0), 0.0, 1.0)
	var u := pow(f, 1.0 / LaunchScript.ALT_SHAPE)
	return LaunchScript.accel_g_estimate(u)


## 火箭当前的**航向**（度，0 = 正北）。取机头 `−basis.z`，与 `main._sync_cockpit_hud()`
## 里那一行**逐字同源** —— 两边各写一份的话，屏上那个 `HDG` 与真机上会差一个迎角。
func _rocket_hdg() -> float:
	if rocket == null or not is_instance_valid(rocket):
		return 0.0
	return fposmod(rad_to_deg(atan2(-rocket.basis.z.x, rocket.basis.z.z)), 360.0)


## ⑭ 的**读数**判据：HUD 三个开关 + 那份字典的**实际内容**。
##
## ⚠️ 只打印"开关对不对"是**不够的**：`cockpit_readout` 是空字典时
## `_draw_cockpit_dash()` 会退回读 `player`（发射段是 `null`）⇒
## 仪表台**整块不画**，而三个开关**全绿**、画面也只是"少了点东西"。
## ⇒ 这里把字典里的每一个字符串都读出来，与 `dash_readout()` 的定义对着看。
##
## ★ 2026-09-30 晚第五改：返回值改成**本帧的最高告警名**（`""` = 一条都不亮）。
## ⑨d / ⑨e 两张就是靠它做"应当不报 / 应当报"的判据 —— 这两个结论
## **必须从 `launch_warn_state()` 出来**（与屏上画的是同一个函数），
## 而不是探针自己另写一条阈值。
func _hud_readout(tag: String) -> String:
	if hud == null or not is_instance_valid(hud):
		print("== %s：★ HUD 不在 ⇒ 座舱层没建出来" % tag)
		return ""
	var r := hud.cockpit_readout
	print("== %s：`cockpit_only` %s / `cockpit_eye` %s / `visible` %s / readout 键 %d 个"
		% [tag, str(hud.cockpit_only), str(hud.cockpit_eye), str(hud.visible), r.size()])
	if r.is_empty():
		print("   · ★★ 读数是**空**的 ⇒ 仪表台整块不画（退回读 `player`，而发射段是 null）"
			+ " —— 这张图看起来像「仪表没做」")
		return ""
	print("   · 中央屏：箭名「%s」/ note「%s」/ 左格段位「%s」"
		% [str(r.get("name", "")), str(r.get("note", "")), str(r.get("leg", ""))])
	# ⚠️ 这里印的是**原量**（`spd_kmh` / `alt_m` / ...），不是屏上的字：
	# 屏上那几个数字还要各乘一次显示缩放（`SPEED_DISPLAY_SCALE` /
	# `ALT_DISPLAY_SCALE`），而那一步在 HUD 里 —— 探针**不许**跟着再算一遍，
	# 否则"探针读数"与"屏上数字"就是两份真源，差一个系数都没人发现。
	print("   · 时速块：%.1f km/h（屏上 = 这个数 × %.2f）"
		% [float(r.get("spd_kmh", 0.0)), FlightHUD.SPEED_DISPLAY_SCALE])
	print("   · 高度块 / 带：%.1f m（屏上 = 这个数 × %.2f）/ PITCH %+.1f° / VS %+.1f m/s / HDG %03d°"
		% [float(r.get("alt_m", 0.0)), FlightHUD.ALT_DISPLAY_SCALE,
			float(r.get("pitch", 0.0)), float(r.get("vs", 0.0)), int(float(r.get("hdg", 0.0)))])
	print("   · 时速块的油门条 %.3f / 燃料槽 %.3f"
		% [float(r.get("thr01", 0.0)), float(r.get("fuel01", 0.0))])
	# ★★ 2026-09-30 晚第五改新增的两路 —— **它们不在 `cockpit_readout` 里**
	#（姿态源是 `Basis`、告警是三个原始量），所以上面那一段读数是**看不见**它们的。
	# 不印的话，⑨d / ⑨e 两张图上"姿态仪读的是单位阵"与"告警块没接上"
	# 都只能靠人眼对着图猜 —— 而那正是这一轮要避免的。
	var b := hud.cockpit_basis
	print("   · ★ 姿态源（火箭自己的基）：`attitude_readout()` 给地平线偏移 %+.1f px / 滚转 %+.1f°"
		% [float(FlightHUD.attitude_readout(b)["horizon_offset_px"]),
			float(FlightHUD.attitude_readout(b)["horizon_roll_deg"])])
	var wk := ""
	var wg := 0.0
	if hud.launch_warn.is_empty():
		print("   · ★ 告警：`launch_warn` 是**空字典** ⇒ 按「这一帧没有告警」处理（倒计时档就是这样）")
	else:
		wg = float(hud.launch_warn.get("g", 0.0))
		var ws := FlightHUD.launch_warn_state(float(hud.launch_warn.get("alt", 0.0)),
			float(hud.launch_warn.get("vs", 0.0)), wg)
		wk = FlightHUD.highest_warning(ws)
		print("   · ★ 告警：%s（过载 %.2f G / 发射段阈值 %.0f G / 机体阈值 %.0f G；拉起门限 = **水面 0 m**）"
			% ["一条都不亮" if wk == "" else wk, wg,
				FlightHUD.LAUNCH_OVER_G, FlightHUD.OVER_G_THRESHOLD])
	print("   · ★ 判据：过载应落在 (机体阈值, 发射段阈值] 之间时**不报** —— 那一段就是"
		+ "「发射段另用一档」与「复用了机体那一档」的唯一分界")
	return wk


## ★★ 两张图的差异**落在屏幕哪几个区** —— ⑭ 唯一的判据。
##
## 三个框各有各的"应当"（老板原话是「**不需要屏幕左上角那么多白色文字了**」）：
## | 区 | 归一化矩形 | 应当 |
## |---|---|---|
## | **左上角** | x < 30% / y < 26% | ★ 那一整层**几乎不放像素**（原来那 7 行白字住这儿） |
## | **底栏** | y ≥ 80% | 仪表台（两块圆表 + 两条底边点阵 + 取景框下沿）**应当主要落在这儿** |
## | 全屏 | 100% | 参照 |
## 末尾再给"落在底栏的份额"，把"分布"缩成一个数。
##
## ⚠️ 它**只能用来比两张图**，不能读单张的绝对值：背景是星空与地球临边，
## 左上角与底栏的背景亮度本来就不同 —— 那样读出来的差全是背景的。
func _hud_map(tag: String, a: Image, b: Image) -> void:
	if a == null or b == null or a.get_size() != b.get_size():
		print("== %s：★ 拿不到同尺寸的两张图 ⇒ 这一条不判（不是通过）" % tag)
		return
	var ia := a.duplicate() as Image
	var ib := b.duplicate() as Image
	ia.convert(Image.FORMAT_RGB8)
	ib.convert(Image.FORMAT_RGB8)
	var da := ia.get_data()
	var db := ib.get_data()
	var sz := ia.get_size()
	var thr := 12
	var y_tl := int(sz.y * 0.26)
	var x_tl := int(sz.x * 0.30)
	var y_low := int(sz.y * 0.80)
	var n_tl := 0
	var h_tl := 0
	var n_low := 0
	var h_low := 0
	var n_all := 0
	var h_all := 0
	var i := 0
	for y in sz.y:
		for x in sz.x:
			var v := maxi(absi(da[i] - db[i]),
				maxi(absi(da[i + 1] - db[i + 1]), absi(da[i + 2] - db[i + 2])))
			i += 3
			var hit := v > thr
			n_all += 1
			if hit:
				h_all += 1
			if y < y_tl and x < x_tl:
				n_tl += 1
				if hit:
					h_tl += 1
			if y >= y_low:
				n_low += 1
				if hit:
					h_low += 1
	print("== %s：屏 %dx%d / 阈值 >%d" % [tag, sz.x, sz.y, thr])
	print("   · 左上角（x < %.0f%%, y < %.0f%%）：占比 %.5f（%d / %d 像素）"
		% [30.0, 26.0, float(h_tl) / maxf(float(n_tl), 1.0), h_tl, n_tl])
	print("   · 底栏（y >= %.0f%%）：占比 %.5f（%d / %d 像素）"
		% [80.0, float(h_low) / maxf(float(n_low), 1.0), h_low, n_low])
	print("   · 全屏：占比 %.5f（%d / %d 像素）"
		% [float(h_all) / maxf(float(n_all), 1.0), h_all, n_all])
	print("   · ⇒ 差异像素里，落在底栏的份额 %.1f%% / 落在左上角的份额 %.1f%%"
		% [float(h_low) / maxf(float(h_all), 1.0) * 100.0,
			float(h_tl) / maxf(float(h_all), 1.0) * 100.0])


## ★ 发射点上空那垛云的**真几何读数**（`MultiMesh` 实例变换）。
##
## ## ⚠️ 这一段**只能在这里做**（带窗口）
## 无头环境下 `MultiMesh.get_instance_transform()` 一律回**单位变换**
##（`instance_count` 却是准的）⇒ 在 `suite_rocket_launch` 里量高度会得到
## "全部堆在海拔 0 m" 的假读数，而那种读数**看起来还很有条理**。
## ⇒ 分工：结构判据（建没建 / 复用哪份材质 / 换图清不清）在无头套件里；
##        几何判据（云底多高 / 铺多开）在这里。
func _cloud_probe() -> void:
	var cr: Node3D = world.get("launch_cloud_root")
	if cr == null:
		push_error("`launch_cloud_root` 不在 ⇒ 发射点上空那垛云没建出来（⑦ 那张会是空景）")
		return
	var lo := INF
	var hi := -INF
	var far := 0.0
	var n := 0
	var base := LaunchScript.launch_pos()
	for c in cr.get_children():
		var mm := c as MultiMeshInstance3D
		if mm == null or mm.multimesh == null:
			continue
		for i in mm.multimesh.instance_count:
			var xf := mm.multimesh.get_instance_transform(i)
			# 盘是**绕世界 Y 做公告板**的 ⇒ 世界竖直跨度恒为 `s * 0.62`（半高就是一半）。
			# 真源：`_build_launch_clouds()` 里那个 `at.y = maxf(at.y, CLOUD_FLOOR + s*0.62*0.5)`。
			var half := xf.basis.get_scale().y * 0.5
			var bottom := xf.origin.y - half
			lo = minf(lo, bottom)
			hi = maxf(hi, xf.origin.y + half)
			far = maxf(far, Vector2(xf.origin.x - base.x, xf.origin.z - base.z).length())
			n += 1
	print("== 云垛几何：%d 片 / 云底最低 %.0f m / 云顶最高 %.0f m / 离发射点最远 %.2f km"
		% [n, lo, hi, far / 1000.0])
	print("== 硬地板 `CLOUD_FLOOR` = %.0f m ⇒ 云底%s（差 %.1f m）"
		% [WorldBuilder.CLOUD_FLOOR, "合格" if lo >= WorldBuilder.CLOUD_FLOOR - 0.5 else "★犯规",
			lo - WorldBuilder.CLOUD_FLOOR])
	print("== 云幕判据对照：云垛底 %.0f m ≤ CLOUD_BASE_ALT %.0f m ≤ CLOUD_FULL_ALT %.0f m ≤ 云垛顶 %.0f m ⇒ %s"
		% [lo, LaunchScript.CLOUD_BASE_ALT, LaunchScript.CLOUD_FULL_ALT, hi,
			"两档都包在里面（进云幕时已经在真云里）"
				if lo <= LaunchScript.CLOUD_BASE_ALT and hi >= LaunchScript.CLOUD_FULL_ALT
				else "★ 没包住 ⇒ 进云幕那一刻会从「云里」跳到「云幕」上"])


## 发射点是**夜图**（`MapDef._pacific_night()`）且全是黑海面 ⇒
## 不压曝光的话火箭与泡沫环都是一团黑，"有没有出水特效"根本读不出来。
##
## ⚠️ **只动曝光，不改时段**：把夜改成昼会把"夜色"这个**真条件**换掉，
## 而"夜里看不看得见"本来就是老板要判的东西之一。
##
## ⚠️⚠️ 但它是个**全屏乘性增益**。第一版全程锁 2.6 ⇒ ⑦（天顶夜空）与 ⑧⑨
##（本来就顶到 255 的烟/幕布）全部过曝成纯白，"透过多少"根本没法判。
## ⇒ 改成**每张图可单独指定**，并把当时的增益打进 `SHOT` 行。
func _set_exposure(brightness: float) -> void:
	_brightness = brightness
	var env := world.get("_env") as Environment
	if env == null:
		push_warning("拿不到 `_env` ⇒ 夜图下这几张图会偏暗（不是失败，只是不好读）")
		return
	env.adjustment_enabled = true
	env.adjustment_brightness = brightness
	env.adjustment_contrast = 1.15
	env.adjustment_saturation = 1.1
	print("== 曝光：brightness %.2f / contrast %.2f（只动曝光，时段仍是夜）"
		% [env.adjustment_brightness, env.adjustment_contrast])


## 把火箭飞到某个**箭底高度**（**制导正常开**，一步步真跑，不是瞬移）。
##
## ⚠️ 用 `step()` 而不是直接写位置：这样出图看到的姿态与机头方向
## **就是真机上那一帧会有的样子**（含姿态环的滞后）。瞬移会得到一个
## "位置对但姿态没跟上"的假画面。
##
## ⚠️ 按**高度**而不是按 `u` 停：出水那一段在 `u` 上挤得极小
##（`ALT_SHAPE = 3.64` ⇒ 箭底越过海面时 `u` 才 6e-5），拿 `u` 当判据根本停不到。
##
## ⚠️ **每一步都推火焰**（与 `main.gd._tick_launch()` 逐字同源：`step()` 之后紧跟
## `update()`）。不推的话，⑩⑪ 两张上的焰长停在 `_init()` 写死的 `LEN_MIN`，
## 而"焰随高度拉长"这件事就**没有任何图能证明**。
##
## [param drive_splash] = true 时**同帧**把箭底高度喂给出水特效 ——
## 少喂一次就是"环涨开了但箭还在水里"那种错位画面（见 `SeaSplash.RING_GROW_ALT`）。
func _fly_to_alt(target_alt: float, drive_splash := false) -> void:
	var dt := 1.0 / 60.0
	var guard := 0
	while rocket.global_position.y < target_alt and guard < 40000:
		rocket.step(dt, 0.0, 0.0, 0.0)
		if flame != null:
			flame.update(rocket)
		if drive_splash and world.launch_splash != null:
			world.launch_splash.update(rocket.global_position.y, dt)
		guard += 1
		if guard % 30 == 0:
			await get_tree().physics_frame
	if guard >= 40000:
		push_error("飞不到 %.0f m（实际 %.1f m / u = %.4f）⇒ 曲线或步长变了" %
			[target_alt, rocket.global_position.y, rocket.u])
	print("== 飞到箭底 %.0f m（u = %.5f）：速度 %.0f m/s / 机身仰角 %.1f° / 焰长 %.1f m / 烟 alpha %.3f"
		% [rocket.global_position.y, rocket.u, rocket.speed(), rocket.pitch_deg(), flame.length,
			world.launch_splash.smoke_alpha if world.launch_splash != null else 0.0])


## 抓一帧**不落盘**的画面（用来算"换图前后同一机位的逐像素差"）。
##
## ⚠️ 必须 `await RenderingServer.frame_post_draw` —— 在别的时刻抓到的
## `get_image()` 可能是**上一帧甚至半帧**的内容，而差值判据会把它读成"变了"。
func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		return null
	return vp.get_texture().get_image()


## 两张图的逐像素差。**每像素取三个通道里的最大差**，再统计。
##
## 返回 `{"mean": 平均差, "maxv": 最大差, "frac": 差 >40 的像素占比}`。
## `>40` 这个门槛与 `_lum()` 里 `lit` 用的是同一个 —— 两张图的亮暗统计
## 可以直接对着看。
##
## ⚠️ 尺寸不同时返回 −1（**不报错**）：`apply_map_staged()` 会重建 viewport 内容，
## 万一尺寸变了，"差 0"会伪装成"完全没变"，那是最坏的一种假绿。
func _img_diff(a: Image, b: Image) -> Dictionary:
	if a == null or b == null or a.get_size() != b.get_size():
		return {"mean": -1.0, "maxv": -1, "frac": -1.0}
	var ia := a.duplicate() as Image
	var ib := b.duplicate() as Image
	ia.convert(Image.FORMAT_RGB8)
	ib.convert(Image.FORMAT_RGB8)
	var da := ia.get_data()
	var db := ib.get_data()
	var n := 0
	var sum := 0.0
	var maxv := 0
	var big := 0
	var i := 0
	while i + 2 < da.size():
		var d := maxi(absi(da[i] - db[i]),
			maxi(absi(da[i + 1] - db[i + 1]), absi(da[i + 2] - db[i + 2])))
		n += 1
		sum += float(d)
		maxv = maxi(maxv, d)
		if d > 40:
			big += 1
		i += 3
	return {"mean": sum / maxf(float(n), 1.0), "maxv": maxv,
		"frac": float(big) / maxf(float(n), 1.0)}


## 按**当前地图**把远裁面设成工程自己的那个数。见文件头那张 A/B 表 ——
## 写死任何一个值都会让整张图变成"只有天空盒"，而且**不报错**。
##
## 判据与 `ChaseCamera._sync_depth_range()` 同源：`has_ground` 分两档。
## ⚠️ 这里**不自己写 90 000 / 1e7** —— 那又是"两份真源"，
## 相机将来改了这两个数，探针会静默拍出一张全黑图。
## ⚠️ 它只管探针那台 `cam`；`ChaseCamera` 由它自己的 `_sync_depth_range()` 管。
func _set_far_for(m: MapDef) -> void:
	if m == null:
		return
	cam.far = ChaseCamera.GROUND_FAR if m.has_ground else ChaseCamera.ORBIT_FAR
	print("== 远裁面：map = %s / has_ground = %s ⇒ cam.far = %.0f km"
		% [m.name_cn, str(m.has_ground), cam.far / 1000.0])


## 关掉**雾**（但**留着**云层），并**把原值存住**。给 ⑦ `07_cloud_mound` 用 ——
## 那张要判的是"云是**真几何**吗"，雾会在 13 km 视距上把它糊成一片米色。
##
## ⚠️ 与 `_clear_weather()` 分开写：那个会连 `_cloud_root` 一起关，
## 而 ⑦ 关掉云层就等于**把判据对象删了**（拍出来是一片干净的天空，看着"通过"）。
func _clear_fog_only() -> void:
	_fog_saved.clear()
	if world._env != null:
		_fog_saved["fog"] = world._env.fog_enabled
		_fog_saved["vfog"] = world._env.volumetric_fog_enabled
		world._env.fog_enabled = false
		world._env.volumetric_fog_enabled = false
	if world._sea_mist != null:
		_fog_saved["mist"] = world._sea_mist.visible
		world._sea_mist.visible = false


## ★ 把 `_clear_fog_only()` 关掉的**原样还回去**。
##
## ⚠️ 不还原的后果不是"图难看"，而是**判据对象被换掉**：⑧⑨ 要回答的是
## "在**真实大气**里云幕挡住了多少" —— 雾一直关着的话，穿云那张会比真机
## 干净一大截，于是"遮挡少 70% 之后还看不看得见"这件事被**悄悄放宽**了。
func _restore_fog() -> void:
	if world._env != null:
		world._env.fog_enabled = bool(_fog_saved.get("fog", true))
		world._env.volumetric_fog_enabled = bool(_fog_saved.get("vfog", true))
	if world._sea_mist != null:
		world._sea_mist.visible = bool(_fog_saved.get("mist", true))
	print("== 天气还原：fog %s / vfog %s / sea_mist %s"
		% [str(_fog_saved.get("fog", true)), str(_fog_saved.get("vfog", true)),
			str(_fog_saved.get("mist", true))])


## 关掉四个天气层。见文件头那段 —— 高空出图漏一个就是一整张米色。
func _clear_weather() -> void:
	if world._env != null:
		world._env.fog_enabled = false
		world._env.volumetric_fog_enabled = false
	if world._cloud_root != null:
		world._cloud_root.visible = false
	if world._sea_mist != null:
		world._sea_mist.visible = false


## 一棵子树在世界空间里的包围盒。
## ⚠️ 自己乘 8 个角：Godot **没有** `Transform3D * AABB`。
## ⚠️ 这里能用 `global_transform` 是因为**节点已经在树里**；
## 未入树时它会静默返回单位矩阵（`suite_rocket_launch` 的 `_fit_scale` 为此
## 沿父链自己乘 —— 那个坑的代价写在 `RocketBody._relative_to()` 的注释里）。
func _world_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a := mi.mesh.get_aabb()
		for i in 8:
			var p := a.position + Vector3(
				a.size.x * float(i & 1), a.size.y * float((i >> 1) & 1),
				a.size.z * float((i >> 2) & 1))
			var w := mi.global_transform * p
			if first:
				out = AABB(w, Vector3.ZERO)
				first = false
			else:
				out = out.expand(w)
	return out


## ★★ 手摆机位**一律走这里** —— 它自己会先把相机切成当前那台。
##
## ⚠️ 这条不是洁癖：第一版三个前置特写（①②③）全部拍成了追尾机位，
## 因为 `ChaseCamera._ready()` 把 `cam` 顶掉了，而这里只写了 `cam` 的位置。
## ⇒ 把"切相机"焊进 `_look()`，"忘记切"这件事就**不可能发生**。
func _look(c: Camera3D, from: Vector3, at: Vector3, shot_name: String) -> void:
	_use_cam(c)
	c.global_position = from
	c.look_at(at, Vector3.UP)
	await _frames(8)
	await _shot(shot_name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	_idx += 1
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		print("SHOT_FAILED ", shot_name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(img) ", shot_name)
		return
	# ⚠️ 名字里**别再拼一次序号** —— 调用方传进来的 `shot_name` 已经自带
	# `01_pad_wide` 这样的序号，早先这里又拼了一遍 `%02d_` ⇒ 产出 `04_04_liftoff.png`。
	var p := out_dir.path_join("%s.png" % shot_name)
	var err := img.save_png(p)
	# ★ 每张图附一条**读数**：相机名（防"拍错相机"）+ 曝光（防"过曝到判不出"）
	# + 亮度统计（判"空景 vs 有内容"）。
	# `lit`（>40 的像素占比）：空景是"万分之几"（只剩星点），有箭体/海面/地球是"百分之几"。
	var got := vp.get_camera_3d()
	var st := _lum(img)
	print("SHOT %s [相机 %s / 曝光 %.2f] err=%d  [亮 %.4f / 均值 %.1f / 最亮 %d]"
		% [p, got.name if got != null else "★ 无", _brightness, err, st.lit, st.mean, st.maxv])


## 一张图的亮度统计。⚠️ 逐字节扫 `get_data()`，**不用 `get_pixel()`**
##（GDScript 里那是逐次跨引擎边界的调用，1600×900 要几十秒）。
func _lum(img: Image) -> Dictionary:
	var im := img.duplicate() as Image
	im.convert(Image.FORMAT_RGB8)
	var d := im.get_data()
	var total := maxi(d.size() / 3, 1)
	var n := 0
	var sum := 0.0
	var lit := 0
	var maxv := 0
	var i := 0
	while i + 2 < d.size():
		var v := maxi(d[i], maxi(d[i + 1], d[i + 2]))
		n += 1
		sum += float(v)
		maxv = maxi(maxv, v)
		if v > 40:
			lit += 1
		i += 3
	return {"mean": sum / maxf(float(n), 1.0), "lit": float(lit) / float(total), "maxv": maxv}


func _on_watchdog() -> void:
	print("WATCHDOG_TIMEOUT")
	get_tree().quit(3)
