extends Node3D
## 喷口**近景**取证探针（第十八轮）：把相机搬到某个喷口点跟前，多角度拍正交特写。
##
## ## 为什么要它
## 量朝向的两套"远距"口径都给不出决定性答案：
##   · 深度栅格的凹陷判据在**剪影边缘**会给出很大的伪影（`nozzle_scan.tscn` 的读数在
##     佩涅罗佩后视上贴着轮廓连成一条带）；
##   · 射线自由程给出的是"**最空的方向**"，而这两个口所在曲面**对外几乎完全敞开**
##     （逃逸锥张角 ±159°，实测），于是峰值方向不唯一。
## ⇒ 剩下唯一能定案的是**看**：把口拍清楚。这对应方法论 §10.1 ——
## 数字答不了"它是什么"时，先做归因实验（这里是最省的"染色"替代：正交特写）。
##
## ## 做法
## 正交相机（正交 ⇒ 特写不带透视变形，形状可直接判读）架在 `P + k·d`，看向 `P`。
## `k` 由 `仰角:方位角` 给，参数化与 `nozzle_scan.tscn` / `nozzle_axis.tscn` **同一套**。
## 窗口边长按**米**给（探针按模型的包围盒高度把米换算成模型单位）。
##
## ## 跑法（要真渲染 ⇒ **不加 `--headless`**）
##   godot --path <工程> res://tools/nozzle_closeup.tscn -- \
##        <输出目录> <模型路径> <窗口米> <tag:x,y,z> [仰角:方位角 ...]

const WIN_PX := 512
## 相机到目标的距离（模型单位）。正交投影下它只影响裁剪，不影响取景 ——
## 给足是为了让相机**落在机体外面**（贴太近会拍到自己人的内壁）。
const CAM_DIST := 3.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("用法：-- <输出目录> <模型路径> <窗口米> <tag:x,y,z> [仰角:方位角 ...]")
		get_tree().quit(2)
		return
	var out_dir := args[0]
	var model_path := args[1]
	var win_m := float(args[2])
	var sx := String(args[3])
	var c := sx.find(":")
	var tag := sx.substr(0, c)
	var xs := sx.substr(c + 1).split(",")
	var frac := Vector3(float(xs[0]), float(xs[1]), float(xs[2]))
	var views: Array[Vector2] = []
	for i in range(4, args.size()):
		var p := String(args[i]).split(":")
		if p.size() == 2:
			views.append(Vector2(float(p[0]), float(p[1])))
	if views.is_empty():
		views = [Vector2(0, 0), Vector2(-20, 0), Vector2(-40, 0), Vector2(0, 40),
			Vector2(-20, 40), Vector2(-40, 40), Vector2(0, -40), Vector2(-20, -40),
			Vector2(-90, 0), Vector2(90, 0)]

	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(WIN_PX, WIN_PX))

	var inst := _load_model(model_path)
	if inst == null:
		push_error("模型加载失败：%s" % model_path)
		get_tree().quit(3)
		return
	add_child(inst)

	# 复刻 `FlightBody._center_and_measure()` 的居中规则（与另两个喷口探针一致）
	var raw := _aabb_of(inst)
	var offset := raw.get_center()
	offset.y = raw.position.y + raw.size.y * 0.55
	inst.position = -offset
	var bounds := AABB(raw.position - offset, raw.size)
	## 米 → 模型单位：用包围盒高度对齐 `SuitProfile.target_height`（32.5 m）那一档口径。
	## ⚠️ 这里写死 32.5 是**佩涅罗佩**的数；换机体要跟着换（探针头注已写明）。
	var m_per_u := 32.5 / bounds.size.y
	var p: Vector3 = bounds.position + frac * bounds.size
	print("### BOUNDS pos=(%.5f, %.5f, %.5f) size=(%.5f, %.5f, %.5f) 1u=%.3fm" % [
		bounds.position.x, bounds.position.y, bounds.position.z,
		bounds.size.x, bounds.size.y, bounds.size.z, m_per_u])
	print("### TARGET %s frac=(%.4f, %.4f, %.4f) world=(%.4f, %.4f, %.4f)" % [
		tag, frac.x, frac.y, frac.z, p.x, p.y, p.z])
	print("### WINDOW %.2f m = %.5f 模型单位" % [win_m, win_m / m_per_u])

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
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = win_m / m_per_u
	cam.near = 0.01
	cam.far = 12.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(cam)
	cam.current = true

	for v in views:
		var el := deg_to_rad(v.x)
		var az := deg_to_rad(v.y)
		var k := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
		cam.global_position = p + k * CAM_DIST
		var up := Vector3.UP
		if absf(k.dot(up)) > 0.99:
			up = Vector3(0, 0, 1)
		cam.look_at(p, up)
		for _i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var vname := "el%+d_az%+d" % [int(v.x), int(v.y)]
		if img == null:
			print("### SHOT %s FAILED (img == null)" % vname)
			continue
		var path := out_dir.path_join("%s_%s.png" % [tag, vname])
		img.save_png(path)
		print("### SHOT %-14s -> %s  %dx%d" % [vname, path, img.get_width(), img.get_height()])
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
