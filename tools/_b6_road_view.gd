extends Node
## **定点诊断：公路路面到底看不看得见**（B6 · 2026-09-28）。
##
## 用户原话："**路面和地面依旧没做区分还是没做出来，现在还是看不到公路路面**"。
##
## 这个探针不猜，只做两件事：
##   ① 打**读数**：在若干已知"路上"的点，把**四层标高**并排量出来 ——
##      地形解析值 / 地形**网格**值（复刻 `_build_city_terrain()` 的三角化）/
##      路面顶 / 水面。哪一层在最上面，读者一眼看得出；
##   ② 拍**定点图**：正俯视 + 低空，机位一律避开中央广场（`CITY_PLAZA_R`），
##      因为广场地板/浅水池本身是另一个对象，会把"路面看不见"这件事混进来。
##
## 跑法（**不能加 `--headless`**，dummy 渲染器抓出来全黑）：
##   godot --path <工程> res://tools/_b6_road_view.tscn -- <输出目录> [city]

var out_dir := "user://b6_road_view"
var _idx := 0
var world: WorldBuilder


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var city := "oenb"
	if args.size() > 1:
		city = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	world = WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	world.apply_map(MapDef.oenbelli() if city == "oenb" else MapDef.davao())
	await _frames(20)

	print("==== ① 路面几何 ====")
	print("  一格 %.0f / 三档宽 %.0f / %.0f / %.0f / 板厚 %.0f / 抬离 %.1f m"
		% [WorldBuilder.CITY_CBLOCK, WorldBuilder.CITY_ROAD_W_LOCAL,
			WorldBuilder.CITY_ROAD_W_ARTERIAL, WorldBuilder.CITY_ROAD_W_TRUNK,
			WorldBuilder.CITY_ROAD_T, WorldBuilder.CITY_ROAD_LIFT])
	_scan("CityRoads")
	_scan("CityGround")
	var seg := world._detail_segments()
	print("  地形网格 %d 段 ⇒ 一格 **%.1f m**（`TERRAIN_DETAIL_SIZE %.0f`）"
		% [seg, WorldBuilder.TERRAIN_DETAIL_SIZE / float(seg), WorldBuilder.TERRAIN_DETAIL_SIZE])
	print("  水面 `CITY_WATER_Y` = %.1f m；中央广场 R = %.0f m"
		% [WorldBuilder.CITY_WATER_Y, WorldBuilder.CITY_PLAZA_R])

	# ---- ② 四层标高并排量（在"路上"的点）----
	print("==== ② 四层标高：地形解析 / 地形网格 / 路面顶 / 水面 ====")
	for pt: Vector2 in [Vector2(12075.0, 12075.0), Vector2(0.0, 30000.0),
			Vector2(12075.0, -12075.0), Vector2(20125.0, 20125.0)]:
		var x := pt.x
		var z := pt.y
		var h_ana: float = world._city_landform(x, z, world.map.city_layout)
		var h_mesh := _mesh_h(x, z, seg)
		var top := _road_top(x, z)
		var wet: bool = world.city_is_dry(x, z) == false
		print("  (%.0f, %.0f)：解析 %.1f / **网格 %.1f** / 路面顶 %s / %s"
			% [x, z, h_ana, h_mesh,
				"无路" if top < -1.0e17 else "%.1f" % top,
				"**水面**" if wet else "陆地"])

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 400000.0
	add_child(cam)
	cam.current = true

	# ③ 正俯视一个街廓十字（**远离中央广场**：`(gx,gz) = (7,7)` ⇒ 28 km）
	await _look(cam, Vector3(12075.0, 2200.0, 12075.0 + 0.01),
		Vector3(12075.0, 0.0, 12075.0), "01_topdown_block_cross")
	# ④ 同一处 45° 斜俯视（看路面板、路缘、两侧楼）
	await _look(cam, Vector3(12075.0 - 3200.0, 1500.0, 12075.0 + 3200.0),
		Vector3(12075.0, 0.0, 12075.0), "02_oblique_block_cross")
	# ⑤ 低空沿主干道（与用户视角一致）
	await _look(cam, Vector3(-14000.0, 300.0, 0.0), Vector3(30000.0, 300.0, 0.0),
		"03_low_along_trunk")
	# ⑥ 支路正上方 600 m（避开广场：`(gx,gz) = (7,1)`）
	await _look(cam, Vector3(12075.0, 600.0, 4225.0 + 0.01),
		Vector3(12075.0, 0.0, 4225.0), "04_topdown_local")
	# ⑦ 路口 30° 低斜（看标线）
	await _look(cam, Vector3(12075.0 - 2400.0, 260.0, 12075.0 - 2400.0),
		Vector3(12075.0 + 800.0, 60.0, 12075.0 + 800.0), "05_low_oblique_road")

	print("B6_ROAD_VIEW_DONE -> ", out_dir)
	get_tree().quit(0)


## 复刻 `_build_city_terrain()` 的三角化，在 `(x, z)` 上取**网格面**高度。
func _mesh_h(x: float, z: float, seg: int) -> float:
	var size := WorldBuilder.TERRAIN_DETAIL_SIZE
	var fx := (x / size + 0.5) * float(seg)
	var fz := (z / size + 0.5) * float(seg)
	var i := int(floorf(fx))
	var j := int(floorf(fz))
	var u := fx - float(i)
	var v := fz - float(j)
	var cx := (float(i) / float(seg) - 0.5) * size
	var cz := (float(j) / float(seg) - 0.5) * size
	var st := size / float(seg)
	var ha: float = world._city_landform(cx, cz, world.map.city_layout)
	var hb: float = world._city_landform(cx + st, cz, world.map.city_layout)
	var hc: float = world._city_landform(cx + st, cz + st, world.map.city_layout)
	var hd: float = world._city_landform(cx, cz + st, world.map.city_layout)
	if (i + j) % 2 == 0:
		# 三角 (a,b,c) 与 (a,c,d)
		if v <= u:
			return ha + (hb - ha) * u + (hc - hb) * v
		return ha + (hc - hd) * u + (hd - ha) * v
	# 三角 (b,c,d) 与 (b,d,a)
	if v <= 1.0 - u:
		return hb + (hc - hb) * v
	return hd + (hb - hd) * (1.0 - v) + (hc - hb) * u


## 从 `_city_dry_spans`（建城侧真源）反查这一点的**路面顶**标高；不在路上 ⇒ −1e18。
func _road_top(x: float, z: float) -> float:
	for d: Dictionary in world._city_dry_spans:
		var axis := int(d["axis"])
		var line := float(d["line"])
		var t0 := float(d["t0"])
		var t1 := float(d["t1"])
		var t := z if axis == 0 else x
		var across := x if axis == 0 else z
		if absf(across - line) > float(d["w"]) * 0.5:
			continue
		if t < t0 - 1.0 or t > t1 + 1.0:
			continue
		# 段的两端插值（与 `_append_road_span()` 同式）
		var x0 := line if axis == 0 else t0
		var z0 := t0 if axis == 0 else line
		var x1 := line if axis == 0 else t1
		var z1 := t1 if axis == 0 else line
		var h0: float = world._city_landform(x0, z0, world.map.city_layout)
		var h1: float = world._city_landform(x1, z1, world.map.city_layout)
		var k := (t - t0) / maxf(t1 - t0, 0.001)
		return h0 + (h1 - h0) * k + WorldBuilder.CITY_ROAD_LIFT + WorldBuilder.CITY_ROAD_T * 0.5
	return -1.0e18


func _scan(nm: String) -> void:
	var n := world.find_child(nm, true, false)
	if n == null:
		print("  ⚠️ 节点 `%s` **不存在**" % nm)
		return
	if n is MultiMeshInstance3D:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		var mo: Material = (n as MultiMeshInstance3D).material_override
		var col := "—"
		if mo is StandardMaterial3D:
			col = str((mo as StandardMaterial3D).albedo_color)
		print("  `%s`：%d 个实例 / 反照率 %s" % [nm, 0 if mm == null else mm.instance_count, col])
	else:
		print("  `%s`：%s" % [nm, n.get_class()])


func _look(cam: Camera3D, from: Vector3, at: Vector3, shot_name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
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
	var p := out_dir.path_join("%02d_%s.png" % [_idx, shot_name])
	print("SHOT %s err=%d" % [p, img.save_png(p)])
