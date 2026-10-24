extends Node
## **路面为什么看不见：地形网格 vs 路面盒子的标高对账**（2026-09-28 · B7）。
##
## 实景读数已经把范围收死到一句话：
## > 把 `CityRoads` 的材质换成**纯白 1.0**，它自己那一格里只从 45.5 抬到 **48.0**
## >（对照：把 `CityGround` 换纯白 ⇒ 同一格 149）⇒ **沥青只有约 1.7% 的面积露在外面**。
##
## 也就是说「沥青太黑」不是主因（黑不黑先得看得见），**主因是被地形盖住了**。
## 本探针把"盖住"这件事**直接量出来**：
##
## ① `CityGround` 网格里，路面线附近那几个顶点的高度 vs `_city_landform()` 的值
##    （两者本该逐点相等 —— 网格就是拿这个函数生成的）；
## ② 按 `_append_road_span()` 的同一套算式**手算**沥青顶标高，与 ① 相减 ⇒ **净空**；
## ③ 网格的 AABB / 顶点间距（确认网格没被整体抬起来）。
##
## 纯静态读数，**可以 `--headless`**。
##
## 跑法：
##   godot --headless --path <工程> res://tools/_b7_gap.tscn -- [oenb|davao]

func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	var city := "oenb"
	if args.size() > 0:
		city = args[0]
	var w := WorldBuilder.new()
	add_child(w)
	await get_tree().physics_frame
	w.apply_map(MapDef.oenbelli() if city == "oenb" else MapDef.davao())
	await get_tree().physics_frame
	var lay: int = w.map.city_layout
	print("== 路面净空对账：%s ==" % w.map.name_cn)

	var cg: MeshInstance3D = _find(w, "CityGround")
	if cg == null or cg.mesh == null:
		print("找不到 CityGround")
		get_tree().quit(1)
		return
	var arr := cg.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var aabb := cg.mesh.get_aabb()
	var seg := int(round(sqrt(float(vs.size())))) - 1
	var span := aabb.size.x
	var step := span / float(seg)
	print("CityGround 顶点 %d 个 / seg %d / 间距 %.3f m / AABB size %s / origin %s"
		% [vs.size(), seg, step, str(aabb.size), str(aabb.position)])
	print("  ⇒ 顶点 x = (i/seg − 0.5)·%.0f ⇒ x=0 的列号 i = %.3f（整除才对得上）"
		% [span, (0.0 / span + 0.5) * float(seg)])

	var probes := [
		["x=0 主干道(沿 z)", 0.0, 0.0, 1],
		["z=0 主干道(沿 x)", 0.0, 0.0, 0],
		["x=4025 支路(沿 z)", 4025.0, 0.0, 1],
		["z=12075 支路(沿 x)", 0.0, 12075.0, 0],
	]
	for pr: Array in probes:
		var line: float = pr[1]
		var base: float = pr[2]
		var axis: int = pr[3]
		print("---- %s（line = %.0f, axis = %d）----" % [pr[0], line, axis])
		for k in 2:
			var t := base + float(k) * 2400.0 + 600.0
			var x := line if axis == 0 else t
			var z := t if axis == 0 else line
			var h := WorldBuilder._city_landform(x, z, lay)
			var mv := _mesh_at(vs, seg, aabb, x, z)
			# 手算沥青顶（与 `_append_road_span()` 同一套式子）
			var piece := WorldBuilder.CITY_ROAD_PIECE
			var t0 := floorf(t / piece) * piece
			var t1 := t0 + piece
			var h0 := WorldBuilder._city_landform(
				line if axis == 0 else t0, t0 if axis == 0 else line, lay)
			var h1 := WorldBuilder._city_landform(
				line if axis == 0 else t1, t1 if axis == 0 else line, lay)
			var top := (h0 + h1) * 0.5 + WorldBuilder.CITY_ROAD_LIFT \
				+ WorldBuilder.CITY_ROAD_T * 0.5
			# 该片内地形最大值（板顶要盖过它才露得出来）
			var hmax := -1.0e9
			for i in 33:
				var tt := t0 + (t1 - t0) * float(i) / 32.0
				hmax = maxf(hmax, WorldBuilder._city_landform(
					line if axis == 0 else tt, tt if axis == 0 else line, lay))
			print("  t=%7.0f  (%.0f,%.0f)  地形函数 %8.3f / **网格顶点 %8.3f**（差 %+.3f）"
				% [t, x, z, h, mv, mv - h])
			print("            板 z∈[%.0f,%.0f] h0=%8.3f h1=%8.3f ⇒ **板顶 %8.3f**"
				% [t0, t1, h0, h1, top])
			print("            ⇒ 板顶 − 地形函数 = %+.3f m / 板顶 − 全片最高 = **%+.3f m**"
				% [top - h, top - hmax])
	get_tree().quit(0)


## 网格是**规则**的：`x = (i/seg − 0.5)·span`、`z = (j/seg − 0.5)·span`
## ⇒ 直接算下标，不要遍历 45 万个顶点（那要 5 分钟，第一次就这么卡的）。
func _mesh_at(vs: PackedVector3Array, seg: int, aabb: AABB, x: float, z: float) -> float:
	var span := aabb.size.x
	# ⚠️ 顶点坐标带 `aabb.position` 的偏移时先减掉（本工程是 0，但别假设）。
	var i := int(round((x - aabb.position.x) / span * float(seg)))
	var j := int(round((z - aabb.position.z) / span * float(seg)))
	i = clampi(i, 0, seg)
	j = clampi(j, 0, seg)
	return vs[j * (seg + 1) + i].y


func _find(n: Node, prefix: String) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name).begins_with(prefix):
		return n
	for c in n.get_children():
		var r := _find(c, prefix)
		if r != null:
			return r
	return null


func _on_watchdog() -> void:
	print("WATCHDOG_TIMEOUT")
	get_tree().quit(3)
