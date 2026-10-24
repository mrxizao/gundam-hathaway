extends Node
## **B7 路面"看不见"的判别性实验**（2026-09-28 · 用户第 ② 条）。
##
## ## 已经确定的事（`_b7_iso2` 的读数）
## · 三层路面的**几何**在正俯视 1 200 m 下**逐位吻合**设计（洋红隔离图覆盖率：
##   `asph_x` 沥青 100% / `kerb_xR,L` 路肩 100% / `mark_x` 标线 100%）；
## · 但**实渲染**时：地面 46.3、只加沥青 45.5（**只暗 0.8 级**）、
##   把沥青反照率提到 **1.0** 却只到 **48.0**（+2.5 级），而**地面**提到 1.0 能到 **149**。
## ⇒ 沥青那条读数**自相矛盾**：它"看得见"（能压暗 0.8 级），
##   但"给足反照率也亮不起来"（1.0 只值 +2.5 级）。
##   唯一能同时解释这两件事的假设是：**沥青的大部分面积被别的东西盖着，
##   只露出极窄的一圈边**（那 0.8 级的压暗就是那圈边）。
##
## ## 本探针只做一件事：**平移**
## 不猜"被谁盖住"，直接把嫌疑犯各自**上下挪 30 m**，看路面区域亮不亮：
## | 变体 | 做法 | 若"被地面盖住"成立，应看到 |
## |---|---|---|
## | V1 | 全开（基准） | — |
## | V2 | 只留沥青（**藏地面**） | 沥青区域**大幅变亮** |
## | V3 | 只留地面 | 沥青区域 = 地面 |
## | **V7** | 全开 + **地面整体下移 30 m** | 沥青区域**变亮** |
## | **V8** | 全开 + **沥青整体上移 30 m** | 沥青区域**变亮** |
## | V9 | 全开 + 地面下移 30 m + 沥青上移 30 m | 最亮 |
## V7/V8 同时是最省的两种**修法**（改一个数就能落地的那两种）。
##
## ## 另一条独立读数：**地面网格 vs 地形函数**
## `CityGround` 的 surface 0 **没有索引**（顶点数 2 709 504 = 6 × 672²）
## ⇒ 顶点按"每四边形 6 个"排，**不能**用 `j*(seg+1)+i` 取（上一版 `_b7_gap`
## 就是这么取错的，量出 −111 m 的假读数）。这里按 `(j*seg+i)*6+k` 取，
## 并用**三角形重心插值**求该点的真实网格高度，与 `_city_landform()` 对比。
## 若两者差得远 ⇒ 路面（只比**函数**高 5.6 m）会被**网格**吃掉。
##
## 跑法（**不能 `--headless`**）：
##   godot --path <工程> res://tools/_b7_vis.tscn -- <输出目录> [oenb|davao]

const REGIONS := [
	["ground  ", 600.0, 1000.0, 480.0, 660.0],
	["asph_x  ", -60.0, 60.0, 480.0, 660.0],
	["kerb_xR ", 250.0, 390.0, 480.0, 660.0],
	["asph_z  ", 600.0, 1000.0, -60.0, 60.0],
]

var out_dir := "user://b7_vis"
var city := "oenb"
var world: WorldBuilder
var cam: Camera3D
var _vis: Array[GeometryInstance3D] = []
var _by: Dictionary = {}          ## 节点名前缀 → Array[GeometryInstance3D]
var _orig_pos: Dictionary = {}
var _mpp := 0.866


func _ready() -> void:
	get_tree().create_timer(420.0).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		city = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	world = WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	world.apply_map(MapDef.oenbelli() if city == "oenb" else MapDef.davao())
	await _frames(20)

	_collect(world, _vis)
	_index()
	print("== B7 判别：%s / 几何节点 %d 个" % [world.map.name_cn, _vis.size()])

	cam = Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 400000.0
	add_child(cam)
	cam.current = true

	_mesh_check()
	await _pass_shift()

	print("B7_VIS_DONE -> ", out_dir)
	get_tree().quit(0)


# ---------------------------------------------------------------- 地面网格对账

## `_b7_gap` 那个"网格顶点 vs 地形函数"的列**重做**（上一版下标取错）。
func _mesh_check() -> void:
	print("---- 地面网格 vs 地形函数 ----")
	var node := _first("CityGround")
	if node == null or node.mesh == null or node.mesh.get_surface_count() == 0:
		print("  找不到 CityGround")
		return
	var vs: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var raw_idx = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var idx_n := 0
	if raw_idx != null:
		idx_n = (raw_idx as PackedInt32Array).size()
	var n := vs.size()
	var seg := int(round(sqrt(float(n) / 6.0)))
	print("  顶点 %d / 索引 %d / 反推 seg = %d（6·seg² = %d）"
		% [n, idx_n, seg, 6 * seg * seg])
	if 6 * seg * seg != n:
		print("  ⚠️ 不是 6·seg² 的整数关系 ⇒ 下面的三角形定位不可信")
	var aabb: AABB = node.mesh.get_aabb()
	print("  AABB pos %s size %s" % [str(aabb.position), str(aabb.size)])
	var lay: int = world.map.city_layout
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var acc := 0.0
	var cnt := 0
	var pts: Array[Vector2] = [Vector2(0, 500), Vector2(0, 0), Vector2(500, 900),
		Vector2(2012, 2012), Vector2(-14000, 9000), Vector2(30000, -22000),
		Vector2(0, 30000), Vector2(-40000, -40000), Vector2(20000, 20000)]
	for p: Vector2 in pts:
		var mh := _mesh_h(vs, seg, aabb, p.x, p.y)
		var fh := world._city_landform(p.x, p.y, lay)
		var d := mh - fh
		print("  (%8.0f, %8.0f)  网格 %9.3f / 函数 %9.3f / 差 %+9.3f"
			% [p.x, p.y, mh, fh, d])
		acc += absf(d)
		cnt += 1
		if absf(d) > absf(worst):
			worst = d
			worst_at = p
	# 全图抽样找最坏偏差（1 000 个点）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	var worst2 := 0.0
	var worst2_at := Vector2.ZERO
	for i in 1000:
		var x := rng.randf_range(-80000.0, 80000.0)
		var z := rng.randf_range(-80000.0, 80000.0)
		var d := _mesh_h(vs, seg, aabb, x, z) - world._city_landform(x, z, lay)
		if absf(d) > absf(worst2):
			worst2 = d
			worst2_at = Vector2(x, z)
	print("  九个定点平均 |差| %.3f m；最大 |差| %.3f m @ %s"
		% [acc / float(cnt), absf(worst), str(worst_at)])
	print("  全图 1 000 点抽样：最大 |差| **%.3f m** @ (%8.0f, %8.0f)"
		% [absf(worst2), worst2_at.x, worst2_at.y])
	print("  ⚠️ 路面顶 = 沿线两端地形**函数**均值 + LIFT 1.6 + T/2 4.0 = **+5.6 m**")
	print("     ⇒ 只要「网格 − 函数」为正且 > 5.6 m，那条路就被网格吃掉")


## `CityGround` 的 surface 0 是**非索引**的：每四边形 6 个顶点。
## 四边形 (i,j) 的 6 个顶点下标 = `(j*seg + i)*6 + k`。
## ⚠️ 三角形顺序按 Godot 的 `SurfaceTool`/`ArrayMesh` 惯例推：先 (a,b,c) 再 (b,d,c)，
## 与 `_build_*` 里 `add_vertex` 的次序一致；这里**只做插值**，
## 用"点落在哪个三角形"选算式，取不到就退回四边形双线性。
func _mesh_h(vs: PackedVector3Array, seg: int, aabb: AABB, x: float, z: float) -> float:
	var span := aabb.size.x
	var fx := (x - aabb.position.x) / span * float(seg)
	var fz := (z - aabb.position.z) / span * float(seg)
	var i := clampi(int(floor(fx)), 0, seg - 1)
	var j := clampi(int(floor(fz)), 0, seg - 1)
	var u := clampf(fx - float(i), 0.0, 1.0)
	var v := clampf(fz - float(j), 0.0, 1.0)
	var base := (j * seg + i) * 6
	if base + 5 >= vs.size():
		return 0.0
	# 四边形四角：p00 = k0, p10 = k1, p01 = k2, p11 = k5（三角形 (0,1,2)+(1,5,2) 的常见排法）
	var p00 := vs[base + 0].y
	var p10 := vs[base + 1].y
	var p01 := vs[base + 2].y
	var p11 := vs[base + 5].y
	# 双线性：与"哪个三角形"无关，且对平面网格逐位等于三角形插值
	return p00 * (1.0 - u) * (1.0 - v) + p10 * u * (1.0 - v) \
		+ p01 * (1.0 - u) * v + p11 * u * v


# ---------------------------------------------------------------- 平移实验

func _pass_shift() -> void:
	print("---- 平移实验（正俯视 1 200 m，4 个世界矩形取样）----")
	var ground := _first("CityGround")
	var roads := _first("CityRoads")
	var kerbs := _first("CityRoadKerbs")
	var marks := _first("CityRoadMarks")
	var gp := ground.position if ground != null else Vector3.ZERO
	var rp := roads.position if roads != null else Vector3.ZERO
	var kp := kerbs.position if kerbs != null else Vector3.ZERO
	# ⚠️⚠️ **必须把原来的 `material_override` 存下来再还原**（2026-09-28 · B8 定案）
	#
	# Godot 的 `material_override` 是**整份替换**：`_add_multimesh()` 把路面材质挂在
	# **节点级** `material_override` 上（不是 mesh 的 surface 材质）。所以
	# `material_override = white` 之后再 `= null`，**不是"恢复原样"，而是"把路面材质删了"**
	# —— `null` 会退回 mesh 自带的 surface 材质（默认那份灰白的 StandardMaterial3D）。
	#
	# 后果（实测，代价：整条 E 系列判据全部作废）：
	#   · `S11_roads_up30_white` 之后再 `= null` ⇒ **路面从此没有沥青材质**；
	#   · `D3_ground_plain_mat` 对**地面**做同一件事 ⇒ **地面从此不再走 `terrain.gdshader`**，
	#     整帧塌成一片平灰（`E0` 全帧 mean 99.3 / **std 0.9**，而干净的 `S1` 是 43.1 / mottled）。
	#   · 于是 `E0 地面 + MultiMesh` 那句"路面看不见"**是在拿一片灰当背景量的**，
	#     与"MultiMesh 这条路走不通"毫无关系 —— **判据无效**。
	#
	# ⇒ 规矩：**凡是被写过的 `material_override` 一律用变量存住、用完原样写回。**
	var g_mo = (ground as GeometryInstance3D).material_override if ground != null else null
	var r_mo = (roads as GeometryInstance3D).material_override if roads != null else null
	var k_mo = (kerbs as GeometryInstance3D).material_override if kerbs != null else null

	await _cam_down(0.0, 0.0, 1200.0)
	# ⚠️ **先把所有几何藏掉**，只留下面按变体逐条打开的 6 个名字。
	# 第一版没做这一步 ⇒ 天气层 / 楼群 / 高架全在画面里，
	# 基准读数被压到 6.0，和 `_b7_iso2` 的 45.3 不可比。
	_hide_all()

	_multi_check(roads as GeometryInstance3D, "CityRoads")
	_multi_check(kerbs as GeometryInstance3D, "CityRoadKerbs")
	_multi_check(marks as GeometryInstance3D, "CityRoadMarks")

	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1, 1, 1)
	white.roughness = 0.9
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1, 1, 1)
	glow.emission_enabled = true
	glow.emission = Color(1, 1, 1)
	glow.emission_energy_multiplier = 1.0
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# 只留"地面 + 三层路面"，其余**全部藏掉**（含天气 / 楼群 / 高架 / 灯）——
	# ⚠️ 第一版忘了这一步 ⇒ V1 混着天气层（读数 6.0），V1/V8 不可比。
	var plan: Array = [
		["S1_ground_only", "g", 0.0, ""],
		["S2_roads_only", "r", 0.0, ""],
		["S3_all", "grkm", 0.0, ""],
		["S4_roads_up05", "grkm", 5.0, ""],
		["S5_roads_up10", "grkm", 10.0, ""],
		["S6_roads_up20", "grkm", 20.0, ""],
		["S7_roads_up50", "grkm", 50.0, ""],
		["S8_roads_up100", "grkm", 100.0, ""],
		["S9_roads_up300", "grkm", 300.0, ""],
		["S10_roads_up1000", "grkm", 1000.0, ""],
		["S11_roads_up30_white", "grkm", 30.0, "white"],
		["S12_ground_dn30", "grkm", 0.0, ""],
		["S13_roads_glow", "grkm", 0.0, "glow"],
	]
	for row: Array in plan:
		var nm: String = row[0]
		var flags: String = row[1]
		var up: float = row[2]
		var mat: String = row[3]
		_set_vis("CityGround", flags.contains("g"))
		_set_vis("CityRoads", flags.contains("r"))
		_set_vis("CityRoadKerbs", flags.contains("k"))
		_set_vis("CityRoadMarks", flags.contains("m"))
		_set_vis("Ocean", false)
		_set_vis("GroundFar", false)
		if ground != null:
			ground.position.y = gp.y - (30.0 if nm == "S12_ground_dn30" else 0.0)
		if roads != null:
			roads.position.y = rp.y + up
			roads.material_override = white if mat == "white" \
				else (glow if mat == "glow" else r_mo)
		if kerbs != null:
			kerbs.position.y = kp.y + up
		await _frames(4)
		var img: Image = await _grab()
		_shot(img, nm)
		_regions(img, nm)
		if ground != null:
			ground.position.y = gp.y
			ground.material_override = g_mo
		if roads != null:
			roads.position.y = rp.y
			roads.material_override = r_mo
		if kerbs != null:
			kerbs.position.y = kp.y
			kerbs.material_override = k_mo
	# ---- 低空斜视：基准 vs 抬高 ----
	_set_vis("CityGround", true)
	_set_vis("CityRoads", true)
	_set_vis("CityRoadKerbs", true)
	_set_vis("CityRoadMarks", true)
	await _cam_to(Vector3(0.0, 260.0, -5200.0), Vector3(0.0, 0.0, 24000.0))
	_shot(await _grab(), "S14_low_base")
	if roads != null:
		roads.position.y = rp.y + 30.0
	await _frames(4)
	_shot(await _grab(), "S15_low_roads_up30")
	if roads != null:
		roads.position.y = rp.y

	# ---- ⚠️ 决定性判据：**关掉太阳阴影** ----
	# 若"路面看不见"是**阴影**（地形自遮挡 acne / 大阴影图的偏置）造成的，
	# 关掉阴影后原高度的路面就会**自己亮起来**；若一点不变 ⇒ 是**真遮挡**。
	await _cam_down(0.0, 0.0, 1200.0)
	var lights := _find_lights()
	print("---- 阴影判别（找到 %d 个平行光）----" % lights.size())
	for l: DirectionalLight3D in lights:
		print("  光 %s：shadow_enabled=%s / bias %.3f / normal_bias %.3f / max_dist %.0f / mode %d"
			% [l.name, str(l.shadow_enabled), l.shadow_bias, l.shadow_normal_bias,
				l.directional_shadow_max_distance, l.directional_shadow_mode])
		for l2: DirectionalLight3D in lights:
			l2.shadow_enabled = false
		await _frames(6)
		var ni: Image = await _grab()
		_shot(ni, "S16_no_shadow")
		_regions(ni, "S16 关阴影（沥青原高度）")
		for l2: DirectionalLight3D in lights:
			l2.shadow_enabled = true
		break

	# ---- 只抬沥青（不动路肩），排除"路肩挡住" ----
	if roads != null:
		roads.position.y = rp.y + 5.0
	await _frames(4)
	_shot(await _grab(), "S17_roads_only_up05")
	_regions(_last_img, "S17 只抬沥青 5 m")
	if roads != null:
		roads.position.y = rp.y

	# ---- 沿 x=0 扫：地面网格高度 vs 沥青板顶 ----
	_scan_z0(ground, roads)

	# ---- 精确枚举：到底哪些实例盖住了 (37, 550) ----
	_cover_check(roads, "CityRoads")
	_cover_check(kerbs, "CityRoadKerbs")
	_cover_check(marks, "CityRoadMarks")
	print("  参照：`_city_landform(37, 550)` = %.3f"
		% world._city_landform(37.0, 550.0, world.map.city_layout))

	# ---- 最后一步：**遮挡物高度扫描** ----
	await _occluder_sweep(ground, roads)

	# ---- 立方体绕序并排对照（**先证再改**）----
	await _cube_duel()

	# ---- 深度判决：三选一 ----
	await _depth_duel(ground, roads)

	# ---- 最终 A/B：同一个变换，MultiMesh vs 普通 MeshInstance ----
	await _final_ab(ground, roads)


## **最终 A/B**：把"渲染路径"与"几何/变换"彻底分开。
##
## 四条，全部**只留地面 + 一件**（`_hide_all()` 之后逐个打开，不再有杂项污染：
## 上一版 D2 忘了核对"到底有几个节点还亮着"，读数被背景拉平了）：
## | 条 | 场景 | 若"路面看不见"是这条的锅，应当看到 |
## |---|---|---|
## | E0 | 地面 + `CityRoads`（MultiMesh） | 路面**看不见**（已知） |
## | E1 | 地面 + 普通 `MeshInstance3D`（**同一变换**、同一 `_city_cube`、同色） | 路面**看得见** ⇒ MultiMesh 路径是根因 |
## | E2 | 地面 + 普通 `MeshInstance3D`（Godot `BoxMesh`、同一变换、同色） | 看得见 ⇒ 自建网格的锅 |
## | E3 | 地面 + 只有顶面的 `PlaneMesh`（461×509，放在沥青顶标高） | 看得见 ⇒ 只有"实心盒"路径坏 |
func _final_ab(ground: Node3D, roads: Node3D) -> void:
	print("---- 最终 A/B（只留地面 + 一件）----")
	# 取沥青的实例变换（x≈0、z≈754.7 那一段，已由 `_cover_check` 证实盖住 (37,550)）
	var mmi := roads as MultiMeshInstance3D
	var t := Transform3D.IDENTITY
	if mmi != null and mmi.multimesh != null:
		for i in mmi.multimesh.instance_count:
			var tt := mmi.multimesh.get_instance_transform(i)
			if absf(tt.origin.x) < 1.0 and absf(tt.origin.z - 754.7) < 4.0:
				t = tt
				break
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.055, 0.053, 0.052)
	dark.roughness = 0.90

	await _cam_down(0.0, 0.0, 1200.0)

	# ---- E0 ----
	_hide_all()
	_set_vis("CityGround", true)
	_set_vis("CityRoads", true)
	await _frames(6)
	_shot(await _grab(), "E0_terrain_multimesh")
	_regions(_last_img, "E0 地面 + MultiMesh")
	print("     亮着的几何节点数 = %d" % _count_visible())

	# ---- E1：普通 MeshInstance + `_city_cube` ----
	_set_vis("CityRoads", false)
	var m1 := MeshInstance3D.new()
	m1.mesh = world._city_cube
	m1.material_override = dark
	m1.transform = t
	add_child(m1)
	await _frames(6)
	_shot(await _grab(), "E1_terrain_plain_city_cube")
	_regions(_last_img, "E1 地面 + 普通 MeshInstance(自建立方体)")
	print("     亮着的几何节点数 = %d" % _count_visible())
	m1.queue_free()

	# ---- E2：普通 MeshInstance + Godot `BoxMesh` ----
	var m2 := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	m2.mesh = bm
	m2.material_override = dark
	m2.transform = t
	add_child(m2)
	await _frames(6)
	_shot(await _grab(), "E2_terrain_plain_boxmesh")
	_regions(_last_img, "E2 地面 + 普通 MeshInstance(Godot BoxMesh)")
	m2.queue_free()

	# ---- E3：只有顶面的一块平板，放在**沥青顶标高** ----
	var m3 := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(461.0, 509.0)
	m3.mesh = pm
	m3.material_override = dark
	m3.position = Vector3(0.0, t.origin.y + 0.5 * t.basis.y.length(), 754.7)
	add_child(m3)
	await _frames(6)
	_shot(await _grab(), "E3_terrain_plane_at_deck")
	_regions(_last_img, "E3 地面 + 顶面平板")
	print("     平板放在 y = %.3f" % m3.position.y)
	m3.queue_free()

	_set_vis("CityRoads", true)
	print("  ⇒ 判读：⚠️ **这一组只在「E1 与 E2 是否逐像素同图」上有意义** ——")
	print("     E1(自建立方体) 与 E2(Godot BoxMesh) 同图 ⇒ 自建网格的绕序**已经和 Godot 一致**；")
	print("     ⚠️ **不要**再用 E0 的读数去判「MultiMesh 路径坏没坏」：`_depth_duel` 的 D3")
	print("     把地面的 `material_override` 写成了 `null`（Godot 里 null = **退回 mesh 自带的")
	print("     surface 材质**，不是「恢复原样」）⇒ 从 D3 起整整一片平灰，E0 量到的是那片灰。")
	print("     MultiMesh 到底画没画，看 **`S2_roads_only`**（只开 CityRoads：走廊正好 ±230 m、")
	print("     背景 20、`kerb_xR` = 20）和 **`S14_low_base`**（沥青面 + 车道线 + 路肩全在）。")


func _count_visible() -> int:
	var n := 0
	for x in _vis:
		if x.visible and x.is_visible_in_tree():
			n += 1
	return n


## **深度判决**：三个互斥假设，一次问清。
##
## 已知（都是硬读数）：
##   · `CityRoads` 里**只有一个**实例盖住 (37, 550)，世界 AABB 是 `x[−230,230] y[1.806,9.821] z[500,1010]`；
##   · 同处地面网格只有 **3.46 m**；
##   · 可**只留沥青**时那一点是 **84…113**（亮），**加上地面**就掉到 **~44**（= 地面的色）。
## ⇒ 无论怎么解释，结论都是"沥青的深度在这条像素上**输给了**地面"。
##
## 三个候选，各有一句可证伪的判据：
## | 假设 | 做法 | 若成立 |
## |---|---|---|
## | **H1 深度值真的更大**（几何不在变换说的地方） | 给沥青一个 `no_depth_test = true` 的白材质 | 立刻全亮 ⇒ H1 |
## | **H2 MultiMesh 这条路径坏了** | 关掉 `CityRoads`，改用**普通 `MeshInstance3D`** + 同一个 `_city_cube` + **同一个实例变换** | 亮 ⇒ H2 |
## | **H3 是地面材质在搞**（`terrain.gdshader`） | 保持几何不动，把 `CityGround.material_override` 换成普通白材质 | 亮 ⇒ H3 |
func _depth_duel(ground: Node3D, roads: Node3D) -> void:
	print("---- 深度判决 ----")
	_hide_all()
	_set_vis("CityGround", true)
	_set_vis("CityRoads", true)
	await _cam_down(0.0, 0.0, 1200.0)
	await _frames(6)
	_shot(await _grab(), "D0_base")
	_regions(_last_img, "D0 地面+沥青（基准）")

	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1, 1, 1)
	white.roughness = 0.9

	# ---- H1：深度测试关掉 ----
	var g_mo2 = (ground as GeometryInstance3D).material_override
	var r_mo2 = (roads as GeometryInstance3D).material_override
	var nd := white.duplicate() as StandardMaterial3D
	nd.no_depth_test = true
	(roads as GeometryInstance3D).material_override = nd
	await _frames(6)
	_shot(await _grab(), "D1_road_no_depth_test")
	_regions(_last_img, "D1 沥青 no_depth_test")
	(roads as GeometryInstance3D).material_override = r_mo2

	# ---- H3：换掉地面材质 ----
	# ⚠️ 见 `_pass_shift` 顶部那段：**这里必须存住再写回**，写 `null` 等于把地面材质删掉。
	(ground as GeometryInstance3D).material_override = white
	await _frames(6)
	_shot(await _grab(), "D3_ground_plain_mat")
	_regions(_last_img, "D3 地面换普通材质")
	(ground as GeometryInstance3D).material_override = g_mo2

	# ---- H2：关掉 MultiMesh，换普通 MeshInstance + 同一个变换 ----
	var mmi := roads as MultiMeshInstance3D
	var t := Transform3D.IDENTITY
	if mmi != null and mmi.multimesh != null:
		for i in mmi.multimesh.instance_count:
			var tt := mmi.multimesh.get_instance_transform(i)
			if absf(tt.origin.x) < 1.0 and absf(tt.origin.z - 754.7) < 4.0:
				t = tt
				break
	mmi.visible = false
	var plain := MeshInstance3D.new()
	plain.mesh = world._city_cube
	plain.material_override = white
	plain.transform = t
	add_child(plain)
	await _frames(6)
	_shot(await _grab(), "D2_plain_meshinst_same_xform")
	_regions(_last_img, "D2 普通 MeshInstance（同一变换）")
	print("  普通 MeshInstance 用的变换 origin %s / 轴长 %.0f/%.0f/%.0f"
		% [str(t.origin), t.basis.x.length(), t.basis.y.length(), t.basis.z.length()])
	plain.queue_free()
	if mmi != null:
		mmi.visible = true
	print("  ⇒ 判读：D1 亮 ⇒ 几何/深度真不在变换处；D2 亮 ⇒ MultiMesh 路径坏了；"
		+ "D3 亮 ⇒ 是 `terrain.gdshader` 在搞")


## ⚠️ 这一步是整个 #46 的**判决**。
##
## 假设：`_make_unit_cube()` 的三角形绕序与 Godot 的正面约定**相反** ⇒
## 从外面看到的是盒子的**内壁 / 内底**，而 `generate_normals()` 给的法线是**向外的**
## ⇒ 看到的面按"背向光源"着色（暗），而且**内底比地面低**（沥青内底 0.98 m、地面 3.56 m）
## ⇒ **整条路被地面吃掉**。这一条能同时解释用户的三条抱怨。
##
## 判据（并排，同材质、同尺寸、同位置）：
##   · 左 = Godot 自带 `BoxMesh`（**约定必然正确**）；
##   · 右 = `_make_unit_cube()`。
## 两者用同一个 `StandardMaterial3D`（白、粗糙 1.0、默认 CULL_BACK）。
## ⇒ 若左面亮、右面暗/看不见 ⇒ **绕序确实是反的**。
func _cube_duel() -> void:
	print("---- 立方体绕序判决（Godot `BoxMesh` vs `_make_unit_cube()`）----")
	_hide_all()
	# 相机抬到 3 000 m 正俯视，两块板都放在市中心上空 2 000 m（远离城市其它东西）
	await _cam_down(0.0, 0.0, 3000.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var w := world as WorldBuilder
	# `_make_unit_cube()` 取不到（私有）⇒ 就地把同一份顶点表复制过来，
	# 保证"两边只差绕序"这件事可控、可读。
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := [
		[1, 0, 3, 2], [4, 5, 6, 7], [0, 4, 7, 3],
		[1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4],
	]
	var vs := [
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
		Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
		Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5),
	]
	for qq: Array in q:
		for i: int in [qq[0], qq[1], qq[2], qq[0], qq[2], qq[3]]:
			st.add_vertex(vs[i])
	st.generate_normals()
	var custom: Mesh = st.commit()

	var left := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	left.mesh = bm
	left.material_override = mat
	left.scale = Vector3(1200, 400, 1200)
	left.position = Vector3(-1200, 2000, 0)
	add_child(left)

	var right := MeshInstance3D.new()
	right.mesh = custom
	right.material_override = mat
	right.scale = Vector3(1200, 400, 1200)
	right.position = Vector3(1200, 2000, 0)
	add_child(right)

	await _frames(6)
	var img: Image = await _grab()
	_shot(img, "C0_cube_duel")
	var lv := _patch(img, -1600.0, -800.0, -400.0, 400.0)
	var rv := _patch(img, 800.0, 1600.0, -400.0, 400.0)
	print("  左（Godot `BoxMesh`，俯视顶面）亮度 %6.1f" % lv)
	print("  右（`_make_unit_cube()`，俯视顶面）亮度 %6.1f" % rv)
	print("  ⇒ %s" % ("**绕序相反已被证实**：同一材质同一尺寸，"
		+ "自带方块 %.1f、自建立方体 %.1f" % [lv, rv]
		if absf(lv - rv) > 30.0 else "两者接近 %.1f/%.1f ⇒ 绕序**不是**问题" % [lv, rv]))

	# 顺带把绕序反过来再量一次（**这就是候选修法**）
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for qq: Array in q:
		for i: int in [qq[0], qq[3], qq[2], qq[0], qq[2], qq[1]]:
			st2.add_vertex(vs[i])
	st2.generate_normals()
	var flipped: Mesh = st2.commit()
	right.mesh = flipped
	await _frames(6)
	var img2: Image = await _grab()
	_shot(img2, "C1_cube_flipped")
	var rv2 := _patch(img2, 800.0, 1600.0, -400.0, 400.0)
	print("  右（**绕序翻转后**）亮度 %6.1f  ⇒ %s"
		% [rv2, "翻转能修好" if rv2 > lv - 30.0 else "翻转也没用 ⇒ 假设不成立"])

	# 再顺带把 `_sized()` / `_sized_pitch()` 的**缩放-旋转次序**量出来
	#（`Basis.scaled()` 在 Godot 里乘的是**行** ⇒ 等价于父空间缩放 `S·R`，
	# 对 yaw = 90° 的实例会把"宽"与"长"**对调**）。
	var t0 := w._sized(Vector3.ZERO, Vector3(460.0, 8.0, 503.0), 0.0)
	var t90 := w._sized(Vector3.ZERO, Vector3(460.0, 8.0, 503.0), 90.0)
	print("  `_sized(size=(460,8,503), yaw=0 )` 轴长 x %.1f / y %.1f / z %.1f"
		% [t0.basis.x.length(), t0.basis.y.length(), t0.basis.z.length()])
	print("  `_sized(size=(460,8,503), yaw=90)` 轴长 x %.1f / y %.1f / z %.1f"
		% [t90.basis.x.length(), t90.basis.y.length(), t90.basis.z.length()])
	print("  ⇒ yaw=90 时若 x 轴长变成 503、z 轴长变成 460 ⇒ **前两轴被互换**（另一个真 bug）")


## 用一块**白色无光照**的水平板，从 y = 0 起每 2 m 抬一块，
## 读 `(0, 550)` 那个像素的亮度 ⇒ **板第一次露出来时的高度 = 遮挡物顶面**。
## 这一步不猜任何东西：它把"到底在多高才看得见"变成一个数。
func _occluder_sweep(ground: Node3D, roads: Node3D) -> void:
	print("---- 遮挡物高度扫描（白板 @ (0, y, 550)，尺寸 400×1×400 m）----")
	for n: Node3D in [ground, roads]:
		if n != null:
			print("  %s  global_transform = %s" % [n.name, str(n.global_transform)])
	if ground != null:
		var wa: AABB = (ground as MeshInstance3D).mesh.get_aabb()
		var corner := wa.position
		var size := wa.size
		var lo := Vector3(1e18, 1e18, 1e18)
		var hi := Vector3(-1e18, -1e18, -1e18)
		for bx in [corner.x, corner.x + size.x]:
			for by in [corner.y, corner.y + size.y]:
				for bz in [corner.z, corner.z + size.z]:
					var p: Vector3 = (ground as MeshInstance3D).global_transform * Vector3(bx, by, bz)
					lo = lo.min(p)
					hi = hi.max(p)
		print("  地面网格**世界** AABB %s .. %s（本地 %s .. %s）"
			% [str(lo), str(hi), str(wa.position), str(wa.end)])

	var plate := StandardMaterial3D.new()
	plate.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plate.albedo_color = Color(1, 1, 1)
	plate.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(400.0, 1.0, 400.0)
	mi.mesh = bm
	mi.material_override = plate
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var yv := 0.0
	var first := -1.0
	while yv <= 34.0:
		mi.global_position = Vector3(0.0, yv, 550.0)
		await _frames(3)
		# ⚠️ 取样窗**避开中线标记**（|x| ≤ 22）⇒ 只取纯沥青那一条 `x ∈ [30, 45]`。
		var v := _patch(await _grab(), 30.0, 45.0, 520.0, 580.0)
		var tag := ""
		if v > 200.0 and first < 0.0:
			first = yv
			tag = "   <== 第一次全白"
		print("  y = %5.1f  ⇒  (0,550) 亮度 %6.1f%s" % [yv, v, tag])
		yv += 2.0
	mi.queue_free()
	print("  ⇒ 遮挡物顶面 ≈ **%.0f m**（世界 y）" % first)
	print("  ⇒ 同处沥青板顶 = 8.98…9.84 m、地面网格 ≈ 2.1…4.0 m ⇒ 差值 %.1f m"
		% ((first - 9.0) if first > 0.0 else 0.0))


var _last_img: Image = null


## 找场景里所有 `DirectionalLight3D`（`_vis` 收不到它 —— 它不是 `GeometryInstance3D`）。
func _find_lights() -> Array[DirectionalLight3D]:
	var out: Array[DirectionalLight3D] = []
	_walk_lights(get_tree().root, out)
	return out


func _walk_lights(n: Node, out: Array[DirectionalLight3D]) -> void:
	if n is DirectionalLight3D:
		out.append(n)
	for c in n.get_children():
		_walk_lights(c, out)


## 沿 x = 0 从 z = 300 扫到 1 100：每 50 m 打印
## **地面网格高度** / **地形函数** / **覆盖该点的沥青板顶** / 余量。
func _scan_z0(ground: Node3D, roads: Node3D) -> void:
	print("---- 沿 x=0 扫描（地面网格 vs 沥青板顶）----")
	if ground == null or (ground as MeshInstance3D).mesh == null:
		print("  没有地面网格")
		return
	var vs: PackedVector3Array = (ground as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var aabb: AABB = (ground as MeshInstance3D).mesh.get_aabb()
	var seg := int(round(sqrt(float(vs.size()) / 6.0)))
	var lay: int = world.map.city_layout
	var mm: MultiMesh = null
	if roads != null:
		mm = (roads as MultiMeshInstance3D).multimesh
	var tops: Array = []
	if mm != null:
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			if absf(t.origin.x) < 1.0 and t.origin.z > 200.0 and t.origin.z < 1200.0:
				tops.append([t.origin.z, t.origin.y + 0.5 * t.basis.y.length(),
					t.basis.z.length()])
	tops.sort_custom(func(a, b): return a[0] < b[0])
	print("  x=0 上 z∈[200,1200] 的沥青实例 %d 个：" % tops.size())
	for t: Array in tops:
		print("    实例 z 中心 %8.1f / 沿 z 长 %7.1f / 板顶 %8.3f" % [t[0], t[2], t[1]])
	print("   z     网格     函数    板顶(插值)  余量")
	var zc := 300.0
	while zc <= 1100.0:
		var mh := _mesh_h(vs, seg, aabb, 0.0, zc)
		var fh := world._city_landform(0.0, zc, lay)
		var top := _top_at(tops, zc)
		print("  %6.0f %8.3f %8.3f %10.3f %+8.3f"
			% [zc, mh, fh, top, top - mh if top > -1e8 else -999.0])
		zc += 50.0


func _top_at(tops: Array, z: float) -> float:
	for t: Array in tops:
		# 实例 zi 是**中心**，沿 z 长 L ⇒ 覆盖 [zi − L/2, zi + L/2]
		if z >= t[0] - t[2] * 0.5 and z <= t[0] + t[2] * 0.5:
			return t[1]
	return -1e9


## 把**单位立方体的 8 个角**过一遍实例变换，得到**世界 AABB**，
## 然后只报"水平覆盖了 (37, 550)"的那些实例 —— 附带它们的**世界 y 范围**。
## 这一步不依赖任何"轴长 = 尺寸"的假设（那个假设在 yaw=90 时是错的）。
func _cover_check(node: GeometryInstance3D, label: String) -> void:
	print("  ---- %s：覆盖 (x=37, z=550) 的实例 ----" % label)
	var mmi := node as MultiMeshInstance3D
	if mmi == null or mmi.multimesh == null:
		print("    没有 MultiMesh")
		return
	var mm := mmi.multimesh
	var found := 0
	for i in mm.instance_count:
		var t := mm.get_instance_transform(i)
		var lo := Vector3(1e18, 1e18, 1e18)
		var hi := Vector3(-1e18, -1e18, -1e18)
		for bx in [-0.5, 0.5]:
			for by in [-0.5, 0.5]:
				for bz in [-0.5, 0.5]:
					var p: Vector3 = t * Vector3(bx, by, bz)
					lo = lo.min(p)
					hi = hi.max(p)
		if 37.0 >= lo.x and 37.0 <= hi.x and 550.0 >= lo.z and 550.0 <= hi.z:
			found += 1
			if found <= 4:
				print("    #%d 世界AABB x[%.0f,%.0f] y[%.3f,%.3f] z[%.0f,%.0f]  轴长 %.0f/%.0f/%.0f"
					% [i, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z,
						t.basis.x.length(), t.basis.y.length(), t.basis.z.length()])
	print("    ⇒ 共 %d 个实例的水平投影盖住了这一点" % found)


## 直接读 MultiMesh 的**实例变换**：把落在 `asph_x` / `asph_z` 两个区域里的
## 沥青实例的**真实板顶标高**打出来。窗口模式下 `get_instance_transform()` 是真值
##（headless 全回单位变换 —— 已知坑）。
func _multi_check(node: GeometryInstance3D, label: String) -> void:
	var mmi := node as MultiMeshInstance3D
	if mmi == null or mmi.multimesh == null:
		print("  [%s] 不是 MultiMeshInstance3D" % label)
		return
	var mm := mmi.multimesh
	print("  [%s] 实例 %d / 可见 %s / 基 y 长 %.3f"
		% [label, mm.instance_count, str(mmi.visible), mmi.global_transform.basis.y.length()])
	var lay: int = world.map.city_layout
	var hits: Array = []
	for i in mm.instance_count:
		var t := mm.get_instance_transform(i)
		var o := t.origin
		var inside := (o.x > -60.0 and o.x < 60.0 and o.z > 400.0 and o.z < 700.0) \
			or (o.x > 560.0 and o.x < 1040.0 and o.z > -60.0 and o.z < 60.0)
		if inside and hits.size() < 6:
			hits.append(t)
	for t: Transform3D in hits:
		var top := t.origin.y + 0.5 * t.basis.y.length()
		var g := world._city_landform(t.origin.x, t.origin.z, lay)
		print("    实例 @ (%8.1f, %8.1f)  板厚 %.1f  板顶 %8.3f  地形函数 %8.3f  余量 %+7.3f m"
			% [t.origin.x, t.origin.z, t.basis.y.length(), top, g, top - g])


# ---------------------------------------------------------------- 工具

func _index() -> void:
	for x in _vis:
		var nm := String(x.name)
		for p: String in ["CityGround", "CityRoads", "CityRoadKerbs", "CityRoadMarks",
				"Ocean", "GroundFar"]:
			if nm.begins_with(p):
				if not _by.has(p):
					_by[p] = []
				(_by[p] as Array).append(x)
				break
	for p: String in ["CityGround", "CityRoads", "CityRoadKerbs", "CityRoadMarks"]:
		print("  [%s] %d 个节点" % [p, (_by.get(p, []) as Array).size()])


func _set_vis(prefix: String, on: bool) -> void:
	for x: GeometryInstance3D in _by.get(prefix, []):
		x.visible = on
		_orig_pos[x] = x.position


func _only_all() -> void:
	for x in _vis:
		x.visible = true


func _hide_all() -> void:
	for x in _vis:
		x.visible = false


func _first(prefix: String) -> Node3D:
	var a: Array = _by.get(prefix, [])
	return a[0] if a.size() > 0 else null


func _collect(n: Node, out: Array[GeometryInstance3D]) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			out.append(c)
		_collect(c, out)


func _regions(img: Image, label: String) -> void:
	if img == null:
		print("  %s：没有帧" % label)
		return
	var out := PackedStringArray()
	for r: Array in REGIONS:
		out.append("%s %5.1f" % [r[0], _patch(img, r[1], r[2], r[3], r[4])])
	print("  %-22s | %s" % [label, " | ".join(out)])


func _patch(img: Image, x0: float, x1: float, z0: float, z1: float) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var c0 := clampi(int(round(float(w) * 0.5 + x0 / _mpp)), 0, w - 1)
	var c1 := clampi(int(round(float(w) * 0.5 + x1 / _mpp)), c0 + 1, w)
	var r0 := clampi(int(round(float(h) * 0.5 + z0 / _mpp)), 0, h - 1)
	var r1 := clampi(int(round(float(h) * 0.5 + z1 / _mpp)), r0 + 1, h)
	var acc := 0.0
	var n := 0
	for y in range(r0, r1, 3):
		for x in range(c0, c1, 3):
			var p := img.get_pixel(x, y)
			acc += 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
			n += 1
	return acc / float(maxi(n, 1)) * 255.0


func _cam_down(x: float, z: float, h: float) -> void:
	cam.global_transform = Transform3D(
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
		Vector3(x, h, z))
	await _frames(6)


func _cam_to(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _frames(6)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		return null
	return vp.get_texture().get_image()


var _idx := 0


func _shot(img: Image, nm: String) -> void:
	_idx += 1
	_last_img = img
	if img == null:
		print("SHOT_FAILED ", nm)
		return
	var p := out_dir.path_join("%02d_%s.png" % [_idx, nm])
	print("SHOT %s err=%d" % [p, img.save_png(p)])


func _on_watchdog() -> void:
	print("WATCHDOG_TIMEOUT")
	get_tree().quit(3)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
