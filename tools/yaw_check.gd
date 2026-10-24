extends Node
## **临时**验收（第十九轮前置）：梅萨M01 的**朝向修正**是否生效。
##
## 背景：用户实测"梅萨的模型方向不对，现在是左边朝前面了" ——
## 也就是模型正面朝 **+X**，而工程约定是 **−Z**（`SuitProfile.model_yaw_deg = 90` 修正）。
##
## 这个脚本要拍的就是"**机头到底朝哪**"，所以刻意把相机放在机体**正后方**
## 和**正前方**各一张：
##   - 后方机位：改对了 ⇒ 看到**背面**（背包、肩甲背面）；改错了 ⇒ 看到**侧面**；
##   - 前方机位：改对了 ⇒ 看到**正脸**（胸口、头）；改错了 ⇒ 看到侧面。
##
## 跑法（不能加 --headless）：
##   godot --path <工程> res://tools/yaw_check.tscn -- <输出目录> <机体id>

const W := 1100
const H := 800
var out_dir := "user://yaw_check"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var suit_id := SuitProfile.Id.MESSER_M01
	if args.size() > 1:
		suit_id = int(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))
	await get_tree().physics_frame

	# 中亮灰背景 + 足量环境光：要看清"哪一面朝前"，不能靠夜战剪影
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.62, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.83, 0.90)
	env.ambient_light_energy = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 130, 0)
	sun.light_energy = 1.7
	add_child(sun)

	var holder := Node3D.new()
	add_child(holder)
	var fb := FlightBody.new()
	fb.name = "YawProbe"
	fb.team = 1
	fb.profile = SuitProfile.by_id(suit_id)
	holder.add_child(fb)
	# ⚠️ 摆在高空：原点会让它第一个物理帧撞地（`CRASH_ALTITUDE` = 24 m）
	fb.global_position = Vector3(0.0, 3000.0, 0.0)
	fb.set_physics_process(false)
	# 朝向摆成"机头正朝 −Z"（工程的前方）——这样相机放哪一侧就是哪一面
	fb.global_transform = Transform3D(Basis(), Vector3(0.0, 3000.0, 0.0))
	await get_tree().physics_frame

	print("== %s ==  model_yaw_deg = %.1f" % [
		fb.profile.display_name, fb.profile.model_yaw_deg])
	print("   model_bounds size = %s" % str(fb.model_bounds.size))

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.05
	cam.far = 6000.0
	add_child(cam)
	cam.current = true
	var focus: Vector3 = fb.global_position + Vector3(0.0, fb.model_bounds.size.y * 0.08, 0.0)
	var r := maxf(fb.model_bounds.size.length() * 1.3, 1.0)

	# 机位 1：**正后方**（−Z 的反面 = +Z）。改对了应当看到背面。
	cam.global_position = focus + Vector3(0.0, r * 0.22, r)
	cam.look_at(focus, Vector3.UP)
	await _shot(cam, "01_from_behind_should_see_back")

	# 机位 2：**正前方**（−Z 侧）。改对了应当看到正脸。
	cam.global_position = focus + Vector3(0.0, r * 0.22, -r)
	cam.look_at(focus, Vector3.UP)
	await _shot(cam, "02_from_front_should_see_face")

	# 机位 3：**正右方**（+X）。侧视图 —— "侧着飞"这个 bug 就是从这里看出来的。
	cam.global_position = focus + Vector3(r, r * 0.22, 0.0)
	cam.look_at(focus, Vector3.UP)
	await _shot(cam, "03_from_right_side")

	print("YAW_CHECK_DONE -> ", out_dir)
	get_tree().quit(0)


func _shot(cam: Camera3D, shot_name: String) -> void:
	for i in 4:
		await get_tree().physics_frame
	cam.current = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT_FAILED ", shot_name)
		return
	var p := out_dir.path_join("%s.png" % shot_name)
	print("SHOT %s err=%d" % [p, img.save_png(p)])
