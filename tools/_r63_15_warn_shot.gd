extends Node
## ★63-15 真机出图：「地形告警 · 拉起」这一行**真的画在屏上、而且是 DANGER 色**。
##
## ## 为什么要出图
## 本轮的玩家可见字面量只有一条：`PlayerController._tick_terrain_warn()` 里那句
## `_system_say("地形告警 · 拉起")`。无头套件能断的是：
##   · 门随**垂速**缩放（不是定高门）；
##   · 真机深俯冲时**告警先于硬夺杆发生**（`warn_y = 3053.0 m`）。
## 但「它真的上屏了没有、以及画出来是什么颜色」**只有像素说了算** ——
## 本工程栽过"两条断言都绿却看不见"。而且 `hud.gd` 里那一行原本只对
## 「接管 / 改出 / 交还」上色，本轮才把「地形告警」并进 `DANGER` 一支。
##
## ## 三张图 + 差分（同一条链路上的三次抓帧）
##   ⓿ `00_base_a` / `00_base_b`  **仪器自检**：世界已冻，什么都没改，拍两帧。
##      这两帧**不可能**逐字节全等（HUD 自己还在跑、世界还有粒子尾迹），
##      所以仪器自检的报告形式是"**基线静止像素掩码**"而不是"全屏为零"。
##   ① `01_warn_on`   真触发告警那一帧（`pc.system_event` = 「地形告警 · 拉起」）
##   ② `02_warn_off`  只把 `system_event` 清空 ⇒ 屏上只少那一行
##   ⇒ **判据**（探针自己打印）：在 ⓿ 证明静止的那批像素上，①与② 差了多少 px，
##     以及这些变化里有多少是 **DANGER(255,76,66)** 色。前者=字画出来了，
##     后者=它走的是 DANGER 那一支（`hud.gd:3724`）。
##
## ⚠️ **判据只许落在"基线静止"的像素上**。实测基线全屏差 4.0%（5.8 万 px）——
##    这 4% 里既有 HUD 自身的动画（目标框读数、电台字幕、PULL UP 闪烁），
##    也有世界粒子的尾巴；拿全屏计数说话必然把噪声算进结论。
##    实测那条字所在的带 [x350..800, y25..75] 基线噪声 **0 px**。
##
## ⚠️ 冻结必须做，而且必须**硬**冻：第一版只关了 `pc.set_physics_process()`，
##    差分里 81 万像素（56% 屏面）都在变 —— 世界还在动，等于没量。
##
## ## 三个踩过的坑（前两版就是这么静默失败的）
##   ① **不能用锁定目标来摆俯冲**：`main.tscn` 每帧重算锁定（`_tick_contacts`），
##      探针写进去的 `pc.lock.target` 下一帧就被清 ⇒ `face_target = null`
##      ⇒ `_apply_translate()` 把底速的 y 强制归零 ⇒ **机头水平、根本不俯冲**
##      （实测垂速从 -1235 一路衰到 -0.0）。⇒ 改走**真实输入**：按住 E（`yaw_right`）。
##   ② **不能用地图自带的地面**：`_probe_down()` 打 `collision_mask = 1`，
##      而这张图上打空 ⇒ `ground_dist = INF` ⇒ `terrain_warning()` 恒 false
##      （这正是 `notes/20` 记的"静默退到兜底值"）。⇒ 探针**自造一块 `WORLD_LAYER` 地面**。
##   ③ **`get_tree().paused = true` 冻不住机体**：`main.gd:266` 把 main 自己设成
##      `PROCESS_MODE_ALWAYS`，而 `FlightBody` 是 `INHERIT` ⇒ **整棵子树都跟着 ALWAYS**
##      （只有 `ChaseCamera` 显式写了 `PAUSABLE`）。⇒ 必须**递归关**每个后代自己的
##      `set_process` / `set_physics_process`，并且**跳过 HUD 子树**（HUD 自己也要
##      `PROCESS_MODE_ALWAYS`，它得继续画；而且它每帧 `queue_redraw()`）。
##
## ⚠️ 不能加 `--headless`：dummy 渲染器一个像素都不产生，抓出来全黑。
##
## 跑法：godot --path <工程> res://tools/_r63_15_warn_shot.tscn -- <输出目录>

## 告警文案里**必须出现**的那个词 —— 与产品侧 `_tick_terrain_warn()` 逐字一致。
const WANT := "地形警告"
## 上带的高度门（像素）。
##
## ⚠️ 这道门不是凑数：`hud.gd` **本来就有一条** `danger: true` 且 `flash: 5.0` 的
##    中央告警字幕（`PULL UP`，判据是"预测高度 + 2.6 s 外推 < 420 m"），
##    它**每次抓帧都在闪** ⇒ 全屏数 DANGER 色像素必然把它的字形一起算进去。
##    按实测几何：本轮的「地形告警 · 拉起」画在左上辅助行（y ≈ 25..40），
##    中央告警字幕排在中部（y ≥ 110）⇒ 两者在屏幕上不相交，用 y 门分开。
##    判据同时把 bbox 打出来，日志里一眼能看出数的是哪一块。
const TOP_GATE := 100.0
## 起始离地高度（米）：给足观察窗，让告警在远高于 50 m 的地方出现。
const START_Y := 4000.0
## 自造地面的顶面高度：`ground.global_position.y = -20` 且厚 40 ⇒ 顶面正好 y = 0。
const GROUND_TOP := 0.0
## 冻结后等多久再抓帧。
##
## ⚠️⚠️ **这个值只能是 0 附近的个位数**，第一版写 100（≈1.67 s）把判据物本身等没了：
## `hud.gd` 的系统提示行有个 `SYSTEM_EVENT_SECS = 1.8 s` 的显示窗
##（`_system_event_timer`，边沿触发一次、然后一路倒数到 0），
## 等 1.67 s 再抓 ⇒ 窗口只剩 0.13 s，抓出来那行字**已经消失**
##（实测：写 100 时屏上根本没有那一行）。⇒ 触发后**立刻**抓，全程 ≤ 0.2 s。
## 世界噪声用**同条件**下的一套基线帧来标定，不靠"多等一会儿"。
const SETTLE := 2

var out := "user://r63_15_warn_shot"
var main: Node
var pc: PlayerController
var hud: Node
var warn_frame := -1
var warn_y := 0.0
var warn_vy := 0.0
var frozen_nodes := 0
## 最近一次抓帧的原始 RGB 字节（`Image.get_data()`）。判定要**逐像素**比，不能再存一份图。
var last_data := PackedByteArray()
## 最近一次抓帧的高度（像素）—— 把 `last_data` 的线性下标还原成 (x, y) 要用它。
var img_h := 900


func _ready() -> void:
	process_priority = 1000
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await _frames(10)

	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, SuitProfile.Id.PENELOPE)
	await _frames(10)
	main.call("_start_fight")
	await _frames(20)

	pc = main.get("player") as PlayerController
	if pc == null:
		print("SHOT_FAILED(没有玩家机)")
		return

	# ---- 自造地面（见文件头坑 ②）----
	var ground := StaticBody3D.new()
	ground.name = "R63WarnGround"
	ground.collision_layer = FlightBody.WORLD_LAYER
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200000.0, 40.0, 200000.0)
	cs.shape = box
	ground.add_child(cs)
	add_child(ground)
	ground.global_position = Vector3(0.0, GROUND_TOP - 20.0, 0.0)
	await _frames(4)

	# ---- 开辅助：走**真的长按路径**，不直接写字段 ----
	Input.action_press("flight_assist")
	await _frames(40)
	Input.action_release("flight_assist")
	await _frames(6)
	print("[r63_15] 辅助开=%s 平移模式=%s（必须都是 true 才走得到防撞地那条链）"
		% [str(pc.assist_on), str(pc.translate_mode)])

	# ---- 摆位 + 按住 E 俯冲（见文件头坑 ①）----
	pc.global_position = Vector3(0.0, START_Y, 0.0)
	pc.fm.speed = pc.profile.player_boost_speed()
	await _frames(2)
	Input.action_press("yaw_right")          # ★ E 键 = 平移模式下的"下降"
	await _frames(2)
	print("[r63_15] 摆位完成：离地 %.0f m、translate_dir.y=%.2f、加力极速 %.1f m/s"
		% [pc.global_position.y, pc.translate_dir.y, pc.profile.player_boost_speed()])

	# ---- 等告警真的出现（带状态诊断：静默失败时没有读数就无从下手）----
	var f := 0
	while f < 400:
		await get_tree().physics_frame
		f += 1
		if not pc.alive:
			print("SHOT_FAILED(还没报就先撞地了，第 %d 帧)" % f)
			return
		var a0: FlightAssist = pc.get("_assist") as FlightAssist
		if f % 20 == 0:
			print("[r63_15] f=%d  y=%.1f  离地=%.1f  垂速=%.1f  terrain_warn=%s  硬夺杆=%s  系统行=「%s」"
				% [f, pc.global_position.y, a0.ground_dist, pc.fm.velocity.y,
					str(a0.terrain_warn), str(pc.get("_auto_pull_up")), str(pc.system_event)])
		if warn_frame < 0 and str(pc.system_event).contains(WANT):
			warn_frame = f
			warn_y = pc.global_position.y
			warn_vy = pc.fm.velocity.y
			break
	if warn_frame < 0:
		print("SHOT_FAILED(400 帧内没等到告警)")
		return

	var asst: FlightAssist = pc.get("_assist") as FlightAssist
	print("[r63_15] ★ 告警在第 %d 帧触发：离地 %.1f m、垂速 %.1f m/s"
		% [warn_frame, warn_y, warn_vy])
	print("[r63_15]   HUD 系统行=「%s」 terrain_warn=%s 硬夺杆=%s GROUND_GUARD_ALT=%.0f m"
		% [str(pc.system_event), str(asst.terrain_warn), str(pc.get("_auto_pull_up")),
			FlightAssist.GROUND_GUARD_ALT])

	# ---- 硬冻结世界（见文件头坑 ③）：递归关后代，跳过 HUD 子树 ----
	hud = main.get("hud")
	frozen_nodes = 0
	_freeze(main)
	get_tree().paused = true
	print("[r63_15] 冻结：递归关掉 %d 个节点的 process/physics_process（跳过 HUD 子树「%s」）"
		% [frozen_nodes, str(hud != null)])
	await _frames(SETTLE)

	# ---- 仪器自检：世界冻住了吗？什么都没改，拍两帧，必须逐字节相同 ----
	var a := await _grab("00_base_a")
	await _frames(4)
	var b := await _grab("00_base_b")
	if a == null or b == null:
		print("SHOT_FAILED(基线抓帧失败)")
		return
	var base_diff := _byte_diff(a, b)
	print("[r63_15] ★ 仪器自检：基线两帧相差 %d 字节 / %d"
		% [base_diff, a.get_data().size()])
	_report_window("基线")

	# ---- 正式两帧：只差 HUD 上那一行 ----
	await _shot("01_warn_on")
	var d1 := last_data
	_report_window("01_warn_on")
	var keep := str(pc.system_event)
	pc.system_event = ""
	await _frames(3)
	await _shot("02_warn_off")
	var d2 := last_data
	_report_window("02_warn_off")
	pc.system_event = keep
	await _frames(2)

	# ---- 判据：把「静态」与「变化」分开 ----
	#
	# 全屏逐字节相同是**做不到**的：HUD 自己仍在 `_process`（`PROCESS_MODE_ALWAYS`）、
	# 世界还有粒子尾迹 ⇒ 基线那两帧总差几十 KB。所以判据不能拿全屏计数说话，
	# 只能落在**基线证明静止的那批像素**上。这里就地把这批像素筛出来数。
	var pa := a.get_data()
	var pb := b.get_data()
	var px_total := d1.size() / 3
	var static_px := 0        ## 基线两帧逐像素完全相同的像素数
	var moved_on_static := 0  ## 其中 01 与 02 又不一样的（含 HUD 自身动画）
	var top_changed := 0      ## 上带 y<TOP_GATE 里的变化像素 —— **不分颜色**
	var danger_all := 0       ## 上述变化里，01 侧颜色 ≈ DANGER(255,76,66) 的（全屏）
	var danger_top := 0       ## 同上，但只数**上带** y < TOP_GATE
	var w := d1.size() / (3 * img_h)
	var d_x0 := -1
	var d_x1 := -1
	var d_y0 := -1
	var d_y1 := -1
	for i in px_total:
		var o := i * 3
		if pa[o] != pb[o] or pa[o + 1] != pb[o + 1] or pa[o + 2] != pb[o + 2]:
			continue
		static_px += 1
		if d1[o] == d2[o] and d1[o + 1] == d2[o + 1] and d1[o + 2] == d2[o + 2]:
			continue
		moved_on_static += 1
		var px := i % w
		var py := i / w
		# ⚠️ `top_changed` **必须与颜色无关**：它的用途是当负对照的配对读数 ——
		# 「字还在（top_changed 不变）但颜色不是 DANGER 了（danger_top → 0）」
		# 才能证明负对照咬的是**颜色这一支**，而不是"字根本没画"。
		if py < TOP_GATE:
			top_changed += 1
		var dr := absi(int(d1[o]) - 255)
		var dg := absi(int(d1[o + 1]) - 76)
		var db := absi(int(d1[o + 2]) - 66)
		if dr + dg + db > 40:
			continue
		danger_all += 1
		if d_x0 < 0 or px < d_x0:
			d_x0 = px
		if px > d_x1:
			d_x1 = px
		if d_y0 < 0 or py < d_y0:
			d_y0 = py
		if py > d_y1:
			d_y1 = py
		if py < TOP_GATE:
			danger_top += 1
	print("[r63_15] ★ 判据：基线静止像素 %d / %d（%.1f%%）" % [static_px, px_total,
		100.0 * float(static_px) / float(px_total)])
	print("[r63_15] ★ 判据：静止像素上 01 与 02 差 %d px（含 HUD 自身动画）" % moved_on_static)
	print("[r63_15] ★ 判据：**上带 y<%.0f** 变化 %d px（不分颜色 ⇒ 字画出来了没有）"
		% [TOP_GATE, top_changed])
	print("[r63_15] ★ 判据：其中 DANGER 色 %d px（全屏 bbox x%d..x%d y%d..y%d）" % [danger_all,
		d_x0, d_x1, d_y0, d_y1])
	print("[r63_15] ★ 判据：**上带** DANGER 色 %d px ⇒ 左上辅助行那一行字走的是 DANGER 一支"
		% danger_top)

	print("[r63_15] 结束：告警行「%s」（清空后再画回来的那一行 = 差分里的那块）" % keep)
	get_tree().quit(0)


## 把 HUD 那一行的**显示窗**读出来 —— 「抓帧时那行字到底还在不在窗口内」的唯一直接证据。
## 只报读数、不做判断：`_timer > 0` 才是"画得出来"的必要条件（`hud.gd:3722`）。
func _report_window(tag: String) -> void:
	if hud == null:
		return
	print("[r63_15]   [%s] HUD 显示窗：seen=「%s」 timer=%.3f s（必须 > 0 才画得出来）"
		% [tag, str(hud.get("_system_event_seen")), float(hud.get("_system_event_timer"))])


## 递归关掉 `n` 及其后代的处理回调。**跳过 HUD 子树** —— HUD 是
## `PROCESS_MODE_ALWAYS`，它得继续 `_process` → `queue_redraw()`，否则画面不更新。
func _freeze(n: Node) -> void:
	if n.is_queued_for_deletion():
		return
	if hud != null and (n == hud or hud.is_ancestor_of(n)):
		return
	n.set_process(false)
	n.set_physics_process(false)
	frozen_nodes += 1
	for c in n.get_children():
		_freeze(c)


func _grab(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport) ", name)
		return null
	var tex := vp.get_texture()
	if tex == null:
		print("SHOT_FAILED(no texture) ", name)
		return null
	var img := tex.get_image()
	if img == null:
		print("SHOT_FAILED(no image) ", name)
		return null
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  %dx%d  err=%d"
		% [path, img.get_width(), img.get_height(), img.save_png(path)])
	last_data = img.get_data()
	img_h = img.get_height()
	return img


func _shot(name: String) -> void:
	await _grab(name)


func _byte_diff(a: Image, b: Image) -> int:
	var pa := a.get_data()
	var pb := b.get_data()
	if pa.size() != pb.size():
		return -1
	var n := 0
	for i in pa.size():
		if pa[i] != pb[i]:
			n += 1
	return n


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
