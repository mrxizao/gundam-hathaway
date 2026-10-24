extends "res://tools/_rocket_shots.gd"
## 发射段**操纵方向**探针（2026-09-30 晚）。
##
## ## 它回答的唯一问题
## 「**把机位绕箭体水平转 180° 之后，按键方向会不会在屏幕上翻过来？**」
##
## 相机的 `right` 轴由**相机自己朝向**决定（`Basis.looking_at`），而发射段的机位是
## `target.global_transform * LAUNCH_OFFSET` —— 相机绕到箭体对侧，`right` 必然换向。
## 于是"按左键机头往屏幕左"这条**直觉**在改机位之后**可能变成反的**，
## 而它不会报任何错：箭照样按配平指令偏转，只是屏幕上偏反了。
##
## ## 量法：机头**方向**在相机两轴上的分量变化（不用屏幕投影）
##
## ⚠️⚠️ 第一版量的是"机头外推 300 m 那个点的**屏幕位移**"，那是**错的**：
## 火箭这 1.5 s 里一直在飞（`step()` 每帧积分 `velocity` 与 `global_position`），
## 于是外推点自己就往上跑了几百像素 —— 实测 offset.y=+62 那一组
## `pitch_in=+1` 给出 Δy = +403 px，而把它投影到相机两轴上才看清：
## 那 403 px 里绝大部分是"箭在上升"，姿态只占一小部分。**位置淹没方向**。
##
## 现在改成：`dn = 机头(末) − 机头(初)`（两个单位向量之差 —— 纯方向变化，与位置无关），
## 再点乘相机的 `basis.x`（屏幕右）与 `-basis.y`（屏幕上）：
##   · `sx > 0` ⇒ 机头往**屏幕右**偏；`sx < 0` ⇒ 往左
##   · `sy > 0` ⇒ 机头往**屏幕上**偏；`sy < 0` ⇒ 往下
## 另外跑一组**零输入**作对照：制导会把机身拉回程序方向 ⇒ 那一组应当 ≈ 0，
## 它就是"这个读数有没有零点漂移"的基线。
##
## ⚠️ 测的是**纯输入**（`rocket.step(dt, pitch_in, yaw_in, 0)`），不走 `_launch_axis()`
## ——那里只多一层"按键名 → 符号"的映射，是纯符号问题，看一眼代码就知道。
## 本探针钉的是**几何**：`pitch_in = +1` / `yaw_in = +1` 在屏幕上到底往哪走。
##
## ⚠️ 每个 case 之间**把火箭整个重飞一遍**（`u`/`velocity`/`trim` 全部归零）。
## 不重置的话第二个 case 是从"上一个 case 已经偏过的姿态"起跑，
## 而"偏了多少"正是要量的东西 —— 那会得出一个方向都对不上的一半结果。

## 要测的两个机位：`LAUNCH_OFFSET.y` 的正 / 负（= 相机在箭体两侧）。
const OFFSET_Y := [62.0, -62.0]
## 每个 case 跑多少帧。90 帧 = 1.5 s：配平以 `TRIM_RATE_DEG = 34°/s` 积分，
## 上限 `MAX_TRIM_DEG = 26°` ⇒ 1.5 s 足够走到上限（0.76 s 到顶）。
const RUN_FRAMES := 90

func _ready() -> void:
	get_tree().create_timer(420.0).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))

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
		push_error("火箭资产载不到")
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
	_use_cam(chase)

	_set_exposure(2.6)

	print("== 读数约定：sx > 0 = 机头往**屏幕右**；sy > 0 = 机头往**屏幕上**（两轴都取相机自己的坐标）")
	print("== 每个 case：先把火箭整个重飞一遍（u / velocity / trim 全归零），再给 1.5 s 恒定输入")

	for oy: float in OFFSET_Y:
		await _reset(oy)
		await _run_case(oy, 0.0, 0.0, "零输入（基线）")
		await _reset(oy)
		await _run_case(oy, 1.0, 0.0, "pitch_in = +1")
		await _reset(oy)
		await _run_case(oy, 0.0, 1.0, "yaw_in = +1")

	print("== 探针结束 ==")
	get_tree().quit(0)


## 把火箭重飞到箭底 180 m，并把机位摆成"`LAUNCH_OFFSET.y = oy`"那一档。
func _reset(oy: float) -> void:
	rocket.u = 0.0
	rocket.velocity = Vector3.ZERO
	rocket.fuel = RocketBody.FUEL0
	rocket.trim_deg = Vector2.ZERO
	rocket.throttle_trim = 0.0
	rocket.base_throttle = 0.0
	rocket.place_at_launch(LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))
	await _fly_to_alt(180.0, false)
	# ⚠️ 顺序：先切档（它会把 offset 写回 `LAUNCH_OFFSET`），再覆盖成要测的那个。
	chase.set_launch_eye(ChaseCamera.LaunchEye.CHASE)
	chase.offset = Vector3(0.0, oy, -52.0)
	await _frames(30)


func _run_case(oy: float, pitch_in: float, yaw_in: float, label: String) -> void:
	var n0 := (-rocket.global_transform.basis.z).normalized()
	var pitch_a := rocket.pitch_deg()
	for i in RUN_FRAMES:
		rocket.step(1.0 / 60.0, pitch_in, yaw_in, 0.0)
		chase.step_now(1.0 / 60.0)
		await get_tree().physics_frame
	var n1 := (-rocket.global_transform.basis.z).normalized()
	var dn := n1 - n0
	# 相机自己的两轴：`basis.x` = 屏幕右，`basis.y` = 屏幕上（Godot 屏幕 y 向下，
	# 所以"往上偏"的点乘对象是 `-basis.y`）。
	var cb := chase.global_transform.basis
	var sx := dn.dot(cb.x)
	var sy := dn.dot(-cb.y)
	print("== 机位 offset.y = %+.0f ／ %s" % [oy, label])
	print("   · 机头方向变化在相机轴上：sx = %+.5f（右）/ sy = %+.5f（上）" % [sx, sy])
	print("   · 配平 %s / 机身仰角 %.1f° → %.1f°"
		% [str(rocket.trim_deg.round()), pitch_a, rocket.pitch_deg()])
	print("   · ⇒ 屏幕上：%s%s"
		% ["往右 " if sx > 0.002 else ("往左 " if sx < -0.002 else "几乎不动 "),
			"往上" if sy > 0.002 else ("往下" if sy < -0.002 else "")])
