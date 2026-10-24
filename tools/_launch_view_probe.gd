extends "res://tools/_rocket_shots.gd"
## 发射段「机位候选」+「舱外档 HUD 现状」的对照探针（2026-09-30 晚）。
##
## 老板原话：
## > 「镜头转过去拍火箭的另外一面」
## > 「另外开机体的UI系统也搬过来（不搬雷达系统）」
##
## ## 一次跑出这几张（全部**同一箭底高度 ~180 m**、同一帧率、同一曝光）
## | 图 | 机位（世界坐标，相对箭底）| 回答 |
## |---|---|---|
## | `A_now`        | (0, +52, +62) = **工程现值** | 现状 |
## | `B_now_cockpit`| 同上，座舱档 | 座舱那一层（对照）|
## | `C_az90`       | (+62, +52, 0)  绕箭体轴 90° | 「另外一面」读法一：水平转 |
## | `D_az180`      | (0, +52, −62)  绕箭体轴 180° | 同上 |
## | `E_below`      | (0, **−80**, +62) 箭底**下方** | ★ 「另外一面」读法二：**仰视**（箭底 + 尾焰 + 水面）|
## | `F_high`       | (0, **+150**, +70) 抬高 | ★ 读法三：**俯视**（箭顶 + 星空）|
## | `G_side_far`   | (+180, +40, 0) 正侧面拉远 | ★ 读法四：整支箭 + 长尾焰同框 |
##
## ## ⚠️ 机位**不改工程文件**
## `ChaseCamera.offset` 是**实例字段**（`_apply_launch_eye()` 每次切档都会把它写回
## `LAUNCH_OFFSET`）⇒ 顺序必须是「**先 `set_launch_eye()`、再覆盖 `offset`**」。
##
## ⚠️ 而 `offset` 是**机体局部**坐标：`_desired_position()` 里算的是
## `target.global_transform * Vector3(off.x, off.y, off.z)`。
## ⇒ 想摆"世界坐标 w"的机位，必须 `off = target.basis.inverse() * w`
## （**不能**手抄一个常量 —— 火箭仰角 81.7° 时 `upright_basis()` 与真实 basis 差 8.3°，
## 抄出来的机位会偏，而日志里只显示"offset 是多少"，看不出它对应哪个世界方向）。
##
## ⚠️ **不设 `externally_stepped`**：真机里发射段由 `main._tick_launch()` 每帧调
## `chase.step_now()`，而本探针没有任何东西在驱动它 ⇒ 一旦设了真，相机就**冻在
## 上一次硬落位的位置**（实测第一版 A 图相机停在箭底 −163 m = 水下 18 m，
## 而 `SHOT` 行照样 `err=0`）。本探针等的是 `physics_frame` ⇒ 走物理帧这条钟正好同步。

## 候选机位：**世界坐标**（相对箭底，米）。
const SHOTS := [
	{"tag": "A_now", "w": Vector3(0.0, 52.0, 62.0),
		"note": "工程现值（水平 +Z 侧 62 m / 上方 52 m）"},
	{"tag": "C_az90", "w": Vector3(62.0, 52.0, 0.0),
		"note": "绕箭体轴 90°：正侧方"},
	{"tag": "D_az180", "w": Vector3(0.0, 52.0, -62.0),
		"note": "绕箭体轴 180°：对侧"},
	{"tag": "E_below", "w": Vector3(0.0, -80.0, 62.0),
		"note": "★ 箭底下方 80 m（仰视：箭底 + 尾焰 + 水面）"},
	{"tag": "F_high", "w": Vector3(0.0, 150.0, 70.0),
		"note": "★ 抬高到箭底上方 150 m（俯视：箭顶 + 星空）"},
	{"tag": "G_side_far", "w": Vector3(180.0, 40.0, 0.0),
		"note": "★ 正侧面拉远 180 m（整支箭 + 长尾焰同框）"},
]

func _ready() -> void:
	get_tree().create_timer(420.0).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	# ============================================================ 世界（照 `_rocket_shots.gd` 接线）
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

	rocket = RocketBody.new()
	rocket.name = "MaftyRocket"
	rocket.configure(LaunchScript.ASCENT_SPAN)
	add_child(rocket)
	rocket.place_at_launch(LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))
	var ps := load("res://assets/models/mafty_rocket/mafty_rocket.glb") as PackedScene
	if ps == null:
		push_error("火箭资产载不到 ⇒ 全部图都是空景")
	else:
		rocket.set_model(ps.instantiate())
	await _frames(4)

	flame = RocketFlame.new()
	rocket.add_child(flame)

	chase = ChaseCamera.new()
	chase.name = "ChaseCamera"
	add_child(chase)
	chase.set_target(rocket)
	chase.set_launch_view(true)
	_use_cam(cam)

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

	var tod = world.map.time_of_day
	var sun_dir: Vector3 = WorldBuilder.celestial_dir(tod.sun_rotation_deg)
	var sun_az := fposmod(rad_to_deg(atan2(sun_dir.x, sun_dir.z)), 360.0)
	print("== 天体方向（世界系，指向光源）：(%.3f, %.3f, %.3f) ⇒ 水平方位 %.1f° / 仰角 %.1f°"
		% [sun_dir.x, sun_dir.y, sun_dir.z, sun_az, rad_to_deg(asin(sun_dir.y))])
	print("== `Settings.first_person` = %s（它决定 `_draw_cockpit_rails()` 画不画）"
		% str(Settings.first_person))

	# ============================================================ 飞到箭底 180 m
	await _fly_to_alt(180.0, true)
	# ★ 出图前把相机切到真机那一档（`_apply_launch_eye()` 会把 offset 写回 `LAUNCH_OFFSET`）。
	chase.set_launch_eye(ChaseCamera.LaunchEye.CHASE)
	hud.cockpit_only = true
	hud.visible = true
	_use_cam(chase)
	# 先让物理钟把相机带到现值机位（不是硬落位，走的就是真机那条跟随）
	await _frames(90)

	var base := rocket.global_position
	for s: Dictionary in SHOTS:
		chase.set_launch_eye(ChaseCamera.LaunchEye.CHASE)   # 它会把 offset 写回现值
		var w: Vector3 = s["w"]
		# ★ 世界机位 → 机体局部 offset：**必须走 basis 的逆**（见文件头）。
		chase.offset = rocket.global_transform.basis.inverse() * w
		var want_world := rocket.global_transform * chase.offset
		await _frames(45)
		_sync_hud_at(rocket.global_position.y, rocket.speed(),
			(1.0 - clampf(rocket.u, 0.0, 1.0)) * LaunchScript.ASCENT_SPAN, 0.0,
			rocket.pitch_deg(), rocket.velocity.y, _rocket_hdg())
		var got := chase.global_position - rocket.global_position
		print("== %s：%s" % [s["tag"], s["note"]])
		print("   · 目标世界机位 (%.0f, %.0f, %.0f) ⇒ 实际 (%.0f, %.0f, %.0f) / 相机世界 y = %.1f m（箭底 %.1f）"
			% [w.x, w.y, w.z, got.x, got.y, got.z, chase.global_position.y, rocket.global_position.y])
		_chase_readout(s["tag"])
		await _shot(s["tag"])

	# ---- 座舱档对照 ----
	chase.set_launch_eye(ChaseCamera.LaunchEye.COCKPIT)
	await _frames(60)
	_sync_hud_at(rocket.global_position.y, rocket.speed(),
		(1.0 - clampf(rocket.u, 0.0, 1.0)) * LaunchScript.ASCENT_SPAN, 0.0,
		rocket.pitch_deg(), rocket.velocity.y, _rocket_hdg())
	await _shot("B_now_cockpit")

	# ---- 对照：关掉 HUD（证明画面上那些绿线确实是 HUD 画的）----
	chase.set_launch_eye(ChaseCamera.LaunchEye.CHASE)
	await _frames(45)
	hud.visible = false
	await _frames(10)
	await _shot("Z_nohud")
	hud.visible = true

	_dist_summary()
	print("== 探针结束 ==")
	get_tree().quit(0)
