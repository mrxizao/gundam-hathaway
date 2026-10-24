extends Node
## **`CityGround` 网格在指定点附近的真实高度**（2026-09-28 · 治 #46 的最后一块）。
##
## ## 为什么还要再查一次
## `tools/_b7_vis.gd` 用 `(j*seg+i)*6+k` 猜非索引网格的顶点布局，量出
## 「(0,550) 网格 3.26 m」。但那个假设**从未被独立验证**：城市地形只有 ±7.9 m 起伏，
## 任何错布局都会量出差不多的数（九个定点"平均差 0.34 m"因此**不构成证据**）。
##
## ## 本探针只做一件事：**暴力邻域扫描**
## 把 `CityGround` 的顶点数组整个过一遍，把落在 `|x−X| < R ∧ |z−Z| < R` 里的
## 顶点全部收下来，然后打印它们的 **y 的 min / max / 均值**。
## 不管索引怎么排，"地面那一点的网格高度"都必然落在这个区间里 —— 无法作弊。
##
## 判据：
##   · 若 (0,550) 邻域的 y 都在 **3…4 m** ⇒ 地面确实在 3.5 m，
##     那"路面顶 9.8 m 却被它盖住"就是**同一像素上的深度反常**（不是几何）；
##   · 若邻域里有 **> 10 m** 的顶点 ⇒ 地面的渲染面真在路面之上，**几何就是根因**。
##
## 跑法（**可 `--headless`**，只读 mesh 数组）：
##   godot --headless --path <工程> res://tools/_b7_mesh2.tscn -- [oenb|davao]

const R := 200.0
const TARGETS := [
	["x=0   z=550", 0.0, 550.0],
	["x=37  z=550", 37.0, 550.0],
	["x=0   z=0  ", 0.0, 0.0],
	["x=0   z=756", 0.0, 756.0],
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var city := args[0] if args.size() > 0 else "oenb"
	var w := WorldBuilder.new()
	add_child(w)
	await get_tree().physics_frame
	w.apply_map(MapDef.oenbelli() if city == "oenb" else MapDef.davao())
	await get_tree().physics_frame

	var root: Node = w.get_node_or_null("TerrainRoot")
	if root == null:
		# 名字可能不同：直接找第一个带 mesh 的 MeshInstance3D
		root = w
	var node := _find_ground(w)
	if node == null:
		print("找不到地面网格")
		get_tree().quit(1)
		return
	var mesh: Mesh = node.mesh
	print("== %s / 地面节点 `%s` / 面数 %d" % [w.map.name_cn, node.name, mesh.get_surface_count()])
	var arr: Array = mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var raw = arr[Mesh.ARRAY_INDEX]
	print("  顶点 %d / 有索引 %s / AABB %s" % [vs.size(), str(raw != null), str(mesh.get_aabb())])
	var gt := (node as Node3D).global_transform
	print("  节点 global_transform origin %s / 轴长 %.3f/%.3f/%.3f"
		% [str(gt.origin), gt.basis.x.length(), gt.basis.y.length(), gt.basis.z.length()])

	for t: Array in TARGETS:
		var tx: float = t[1]
		var tz: float = t[2]
		var lo := 1e18
		var hi := -1e18
		var acc := 0.0
		var n := 0
		var nearest := Vector3(1e18, 0, 1e18)
		var nd := 1e18
		for v: Vector3 in vs:
			var dx := v.x - tx
			var dz := v.z - tz
			var d2 := dx * dx + dz * dz
			if d2 < nd:
				nd = d2
				nearest = v
			if absf(dx) < R and absf(dz) < R:
				lo = minf(lo, v.y)
				hi = maxf(hi, v.y)
				acc += v.y
				n += 1
		print("  ---- %s ----" % t[0])
		print("     最近顶点 (%.2f, %.3f, %.2f)  水平距 %.2f m"
			% [nearest.x, nearest.y, nearest.z, sqrt(nd)])
		if n > 0:
			print("     ±%.0f m 内 %d 个顶点：y min %.3f / 均值 %.3f / max %.3f"
				% [R, n, lo, acc / float(n), hi])
		else:
			print("     ±%.0f m 内没有顶点" % R)
		print("     `_city_landform` %.3f" % w._city_landform(tx, tz, w.map.city_layout))

	print("B7_MESH2_DONE")
	get_tree().quit(0)


func _find_ground(w: Node) -> MeshInstance3D:
	for c in w.get_children():
		var found := _find_ground(c)
		if found != null:
			return found
	if w is MeshInstance3D and String(w.name).begins_with("CityGround"):
		return w
	return null
