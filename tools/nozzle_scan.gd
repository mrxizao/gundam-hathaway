extends Node3D
## 喷口扫描探针（第十六轮）：把机体的**后半球**做成一组正交深度栅格，
## 用来找「喷口开口」在**包围盒归一化坐标**里的位置。
##
## ## 为什么需要它
## `SuitProfile.engine_plumes` 要的是**包围盒归一化分数**（和 `model_bounds` 同一套口径）。
## 阿利宙斯巡航态的 16 个喷口当年是 `高达模型/nozzle_scan.py` 用"后视渲染图 +
## 局部对比度 + 连通域 + 射线拾取"扫出来的 —— 那个脚本**不在本仓库里**，
## 而本轮要给佩涅罗佩 / 柯西补喷口，于是把它重新实现成 Godot 探针（可复现、无外部依赖）。
##
## ## 做法
## 每个视图 = 一台**正交**相机（正交 ⇒ 像素↔模型坐标是**严格线性**的，反解不用射线拾取）：
##   1. `k` = 从包围盒中心指向相机的单位向量（由 `--views` 的 仰角,方位角 给）；
##   2. 射线方向 `cam_dir = -k`；像素 (i,j) 的射线原点
##      `o = center + right*u + up*v - cam_dir*BIG`（`u/v` 由像素线性映射）；
##   3. `intersect_ray` 打第一条命中的三角形 ⇒ 记 `t`（沿射线距离）；
##   4. 存两张图：**深度**（16 位量化进 RGB）与**命中掩膜**；外加一张**受光预览图**，
##      给 Python 叠候选圈用。
##
## ⚠️ 深度是"**相机到表面的距离**"，所以**凹陷 = 深度比邻域大**（不是小）。
##    `nozzle_scan.py` 当年的"局部对比度"就是这一步。
##
## ## 跑法
##   godot --path <工程> res://tools/nozzle_scan.tscn -- <输出目录> <模型res路径或绝对路径> [视图...]
##
## 视图写法 `仰角:方位角`（度）。仰角 **正 = 相机在机体上方**，方位角 **正 = 相机偏 +X 一侧**。
## 默认 `0:0 25:0 45:0 -20:0 0:35 0:-35 30:35 30:-35`。

const GRID := 384
## 正交窗口相对包围盒投影尺寸的留边系数。
const MARGIN := 1.12

var out_dir := "user://nozzle_scan"
var model_path := ""
var views: Array[Vector2] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("用法：-- <输出目录> <模型路径> [仰角:方位角 ...]")
		get_tree().quit(2)
		return
	out_dir = args[0]
	model_path = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	if args.size() > 2:
		for i in range(2, args.size()):
			var parts := String(args[i]).split(":")
			if parts.size() == 2:
				views.append(Vector2(float(parts[0]), float(parts[1])))
	if views.is_empty():
		views = [Vector2(0, 0), Vector2(25, 0), Vector2(45, 0), Vector2(-20, 0),
			Vector2(0, 35), Vector2(0, -35), Vector2(30, 35), Vector2(30, -35)]

	# ⚠️ 视口必须是 **GRID×GRID 的正方形**：预览图是"整帧"，而深度栅格是"整帧"，
	# 两者要叠候选圈就必须共享同一套投影。第一版没设窗口大小，
	# 抓到的预览是整个屏幕、`blit_rect` 只取左上角 ⇒ 预览是"裁切"而不是"同一视图"。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(GRID, GRID))

	var inst := _load_model(model_path)
	if inst == null:
		get_tree().quit(3)
		return
	add_child(inst)

	# ---- 复刻 `FlightBody._center_and_measure()` 的居中规则 ----
	# 这一步是**必须**的：`engine_plumes` 的分数是相对 `model_bounds` 的，
	# 而 `model_bounds` 不是"原始模型包围盒"，是"居中之后的包围盒"。
	var raw := _aabb_of(inst)
	var offset := raw.get_center()
	offset.y = raw.position.y + raw.size.y * 0.55
	inst.position = -offset
	var bounds := AABB(raw.position - offset, raw.size)

	print("### BOUNDS  pos=(%.5f, %.5f, %.5f)  size=(%.5f, %.5f, %.5f)" % [
		bounds.position.x, bounds.position.y, bounds.position.z,
		bounds.size.x, bounds.size.y, bounds.size.z])

	# ---- 碰撞体（射线拾取要它）----
	# `create_trimesh_collision()` **返回 void** —— 它直接在 MeshInstance3D 下面
	# 挂一个 StaticBody3D（子节点），所以不需要我们自己建父节点。
	var n_shape := 0
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		mi.create_trimesh_collision()
		n_shape += 1
	print("### COLLIDERS %d" % n_shape)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_world_3d().direct_space_state
	var center := bounds.get_center()
	var diag := bounds.size.length()
	var big := diag * 2.0
	var near := -diag
	var far := diag

	# ---- 受光预览用的环境（深度图不需要光，但预览图要）----
	_build_preview_env()

	# 预览相机：每个视图抓一张，最后拼成一张联络表
	var sheet := Image.create(GRID * views.size(), GRID, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.09, 0.11))

	for vi in views.size():
		var v := views[vi]
		var el := deg_to_rad(v.x)
		var az := deg_to_rad(v.y)
		# k：模型中心 → 相机
		var k := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
		var cam_dir := -k
		var right := Vector3.UP.cross(k)
		if right.length() < 0.001:
			right = Vector3.RIGHT
		right = right.normalized()
		var up := k.cross(right).normalized()

		# 正交窗口：把包围盒 8 个角投影到 (right, up) 上取极值
		var hw := 0.0
		var hh := 0.0
		for sx in [0.0, 1.0]:
			for sy in [0.0, 1.0]:
				for sz in [0.0, 1.0]:
					var p: Vector3 = bounds.position + Vector3(
						bounds.size.x * sx, bounds.size.y * sy, bounds.size.z * sz) - center
					hw = maxf(hw, absf(p.dot(right)))
					hh = maxf(hh, absf(p.dot(up)))
		# ⚠️ **各向同性**：正交相机只有一个 `size`（正方形视口下 = 两个轴的视野）。
		# 取两轴较大者 ⇒ 机体一定装得下，且 x/y 的"每像素多少米"完全相同 ——
		# 这是"深度图上的像素 ↔ 预览图上的像素"能直接对应上的前提。
		var hs := maxf(hw, hh) * MARGIN
		hw = hs
		hh = hs

		var vname := "el%+d_az%+d" % [int(v.x), int(v.y)]
		var depth := PackedByteArray()
		depth.resize(GRID * GRID * 3)
		var hit_count := 0
		var t_min := INF
		var t_max := -INF
		for j in GRID:
			for i in GRID:
				var u := (float(i) + 0.5) / float(GRID) * 2.0 - 1.0
				var vv := 1.0 - (float(j) + 0.5) / float(GRID) * 2.0
				var o := center + right * (u * hw) + up * (vv * hh) - cam_dir * big
				var q := PhysicsRayQueryParameters3D.create(o, o + cam_dir * (big * 2.0))
				q.collision_mask = 0xFFFFFFFF
				var r := space.intersect_ray(q)
				var idx := (j * GRID + i) * 3
				if r.is_empty():
					depth[idx] = 0
					depth[idx + 1] = 0
					depth[idx + 2] = 0
					continue
				var hitp: Vector3 = r["position"]
				# 沿射线的距离（原点已知 ⇒ 直接用点积，不用 hit 的 t）
				var t := (hitp - o).dot(cam_dir)
				hit_count += 1
				t_min = minf(t_min, t)
				t_max = maxf(t_max, t)
				# 量化：把 [0, big*2] 映射到 16 位，高 8 位进 R、低 8 位进 G
				var norm := clampf(t / (big * 2.0), 0.0, 1.0)
				var q16 := int(round(norm * 65535.0))
				depth[idx] = (q16 >> 8) & 0xFF
				depth[idx + 1] = q16 & 0xFF
				depth[idx + 2] = 255
		var dimg := Image.create_from_data(GRID, GRID, false, Image.FORMAT_RGB8, depth)
		dimg.save_png(out_dir.path_join("depth_%s.png" % vname))

		# 视图参数落盘：Python 靠它把像素反解成模型坐标
		var f := FileAccess.open(out_dir.path_join("view_%s.txt" % vname), FileAccess.WRITE)
		f.store_line("name %s" % vname)
		# ⚠️ **列号必须落盘**：`view_*.txt` 按文件名排序读，而联络表按"传入顺序"拼 ——
		# 两者不一致时，"按文件名排序取第 i 个"会指到另一个视图上（第一版就踩了）。
		f.store_line("col %d" % vi)
		f.store_line("el %.6f" % v.x)
		f.store_line("az %.6f" % v.y)
		f.store_line("grid %d" % GRID)
		f.store_line("center %.6f %.6f %.6f" % [center.x, center.y, center.z])
		f.store_line("right %.8f %.8f %.8f" % [right.x, right.y, right.z])
		f.store_line("up %.8f %.8f %.8f" % [up.x, up.y, up.z])
		f.store_line("cam_dir %.8f %.8f %.8f" % [cam_dir.x, cam_dir.y, cam_dir.z])
		f.store_line("hw %.6f" % hw)
		f.store_line("hh %.6f" % hh)
		f.store_line("big %.6f" % big)
		f.store_line("bounds_pos %.6f %.6f %.6f" % [bounds.position.x, bounds.position.y, bounds.position.z])
		f.store_line("bounds_size %.6f %.6f %.6f" % [bounds.size.x, bounds.size.y, bounds.size.z])
		f.close()

		# ---- 受光预览：真相机走同一个正交窗口 ----
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.0 * hh
		cam.near = 0.01
		cam.far = big * 4.0
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		add_child(cam)
		cam.global_position = center + k * (big * 1.5)
		cam.look_at(center, up)
		cam.current = true
		for _i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.convert(Image.FORMAT_RGBA8)
			var cw := mini(GRID, img.get_width())
			sheet.blit_rect(img, Rect2i(0, 0, cw, mini(GRID, img.get_height())),
				Vector2i(GRID * vi, 0))
		cam.queue_free()
		print("### VIEW %-14s hits=%6d  t_min=%.3f t_max=%.3f  hw=%.3f hh=%.3f" % [
			vname, hit_count, t_min, t_max, hw, hh])

	sheet.save_png(out_dir.path_join("preview_sheet.png"))
	print("### DONE -> %s" % out_dir)
	get_tree().quit(0)


func _build_preview_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.12, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.80, 0.90)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 145, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -55, 0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.72, 0.82, 1.0)
	add_child(fill)


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
