extends Node3D
## 佩涅罗佩**整机环绕**取证探针（第十九轮）：带贴图、多方位角/仰角拍整机。
##
## ## 为什么要它
## 第十九轮要"去掉支架"，第一件事是**把支架人肉认出来** ——
## 用户给的截图是局部特写，不知道机位、不知道部位。整机环绕图是**归因联络表**：
## 量到的每一个数字/每一块几何，都能指回屏幕上具体是哪一块。
##
## ## 与 `nozzle_closeup.gd` 的区别
##   · 那个是**正交近景**（看喷口内壁，不要透视变形）；
##   · 这个是**整机全景**（要看清红色零件在整机的哪个位置）⇒ 透视相机 + 拉远。
##
## ## 跑法（要真渲染 ⇒ **不加 `--headless`**）
##   godot --path <工程> res://tools/penelope_orbit.tscn -- \
##        <输出目录> <模型路径> [窗口px] [仰角1,仰角2,...] [方位步长]
##
## 落盘文件名：`orbit_el%+d_az%+d.png`；机位基写进 `orbit_marks.txt`。

const DEF_PX := 640
const CAM_R := 2.6          ## 相机到包围盒中心的距离（模型单位倍数）
const FOV := 32.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("用法：-- <输出目录> <模型路径> [窗口px] [仰角表] [方位步长]")
		get_tree().quit(2)
		return
	var out_dir := args[0]
	var model_path := args[1]
	var px := int(args[2]) if args.size() > 2 else DEF_PX
	var els: Array[float] = [0.0, -30.0, 30.0]
	if args.size() > 3:
		els = []
		for s in String(args[3]).split(","):
			if s.strip_edges() != "":
				els.append(float(s))
	var step := float(args[4]) if args.size() > 4 else 45.0

	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(px, px))

	var inst := _load_model(model_path)
	if inst == null:
		push_error("模型加载失败：%s" % model_path)
		get_tree().quit(3)
		return
	add_child(inst)

	var raw := _aabb_of(inst)
	var offset := raw.get_center()
	offset.y = raw.position.y + raw.size.y * 0.55
	inst.position = -offset
	var bounds := AABB(raw.position - offset, raw.size)
	var radius := bounds.size.length() * 0.5
	print("### BOUNDS pos=(%.5f, %.5f, %.5f) size=(%.5f, %.5f, %.5f)" % [
		bounds.position.x, bounds.position.y, bounds.position.z,
		bounds.size.x, bounds.size.y, bounds.size.z])

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.85, 0.95)
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 145, 0)
	sun.light_energy = 1.7
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -55, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.72, 0.82, 1.0)
	add_child(fill)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = FOV
	cam.near = 0.01
	cam.far = 60.0
	add_child(cam)
	cam.current = true

	var marks := FileAccess.open(out_dir.path_join("orbit_marks.txt"), FileAccess.WRITE)
	marks.store_line("bounds_pos %.5f %.5f %.5f" % [bounds.position.x, bounds.position.y, bounds.position.z])
	marks.store_line("bounds_size %.5f %.5f %.5f" % [bounds.size.x, bounds.size.y, bounds.size.z])
	marks.store_line("radius %.5f" % radius)

	var az := 0.0
	while az < 360.0:
		for el in els:
			var e := deg_to_rad(el)
			var a := deg_to_rad(az)
			var k := Vector3(sin(a) * cos(e), sin(e), cos(a) * cos(e)).normalized()
			var tgt := Vector3(0, bounds.size.y * 0.5 - (raw.get_center().y - offset.y) * 0.0, 0)
			tgt = Vector3.ZERO
			cam.global_position = tgt + k * (radius * CAM_R)
			var up := Vector3.UP
			if absf(k.dot(up)) > 0.99:
				up = Vector3(0, 0, 1)
			cam.look_at(tgt, up)
			marks.store_line("view el%+d az%+d cam %.4f %.4f %.4f" % [
				int(el), int(az), cam.global_position.x, cam.global_position.y, cam.global_position.z])
			for _i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var vname := "el%+d_az%+d" % [int(el), int(az)]
			if img == null:
				print("### SHOT %s FAILED" % vname)
				continue
			img.save_png(out_dir.path_join("orbit_%s.png" % vname))
			print("### SHOT %-16s ok" % vname)
		az += step
	marks.close()
	print("### DONE -> %s" % out_dir)
	get_tree().quit(0)


func _load_model(path: String) -> Node3D:
	if path.begins_with("res://"):
		var ps := load(path) as PackedScene
		if ps != null:
			return ps.instantiate() as Node3D
		return null
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return null
	return doc.generate_scene(st) as Node3D


func _aabb_of(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a: AABB = mi.transform * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	if first:
		out = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return out
