extends SceneTree
## 量模型的**三个轴**尺寸（之前的探针只报了"高度"，而踏板/机体的"该缩多大"
## 取决于哪个轴算高 —— 这正是本轮出错的地方）。
##
## 用法：godot --headless --path <工程> --script res://tools/measure_models.gd


func _initialize() -> void:
	# ⚠️ **默认只打"根的直接子节点"那一层**（合集里就是 踏板 / 机体1 / 机体2 三块）。
	# 逐块清单有 200+ 行、还会把输出刷爆（第一版就是这样，
	# 真需要时加 `--parts` 显式要）。
	var want_parts := OS.get_cmdline_user_args().has("--parts")
	var want_states := OS.get_cmdline_user_args().has("--states")
	var targets := [
		["马夫蒂出击合集", "C:/Users/MSIPC/Desktop/游戏/闪哈游戏/梅萨M01/梅萨出击！.glb"],
		["联邦出击合集", "C:/Users/MSIPC/Desktop/游戏/闪哈游戏/古斯塔夫/古斯塔夫出击！.glb"],
		["踏板·马夫蒂(单体)", "res://assets/models/pedal/mafty_base_jabber.glb"],
		["踏板·喀耳刻(单体)", "res://assets/models/pedal/kilce_base_jabber.glb"],
		["梅萨M01", "res://assets/models/messer/messer_m01.glb"],
		["古斯塔夫", "res://assets/models/gustav/gustav_karl_00.glb"],
	]
	if want_states:
		targets = [
			["马夫蒂·空板", "res://assets/models/pedal_states/mafty_empty.glb"],
			["马夫蒂·只有前机", "res://assets/models/pedal_states/mafty_front.glb"],
			["马夫蒂·只有后机", "res://assets/models/pedal_states/mafty_back.glb"],
			["马夫蒂·两台都在", "res://assets/models/pedal_states/mafty_both.glb"],
			["喀耳刻·空板", "res://assets/models/pedal_states/kilce_empty.glb"],
			["喀耳刻·只有左机", "res://assets/models/pedal_states/kilce_left.glb"],
			["喀耳刻·只有右机", "res://assets/models/pedal_states/kilce_right.glb"],
			["喀耳刻·两台都在", "res://assets/models/pedal_states/kilce_both.glb"],
		]
	for item: Array in targets:
		_measure(str(item[0]), str(item[1]), want_parts)


func _measure(label: String, path: String, want_parts := false) -> void:
	print("\n=== %s ===" % label)
	print("  %s" % path)
	var root: Node = null
	if path.begins_with("res://"):
		var ps := load(path) as PackedScene
		if ps != null:
			root = ps.instantiate()
	else:
		# 工程外的 .glb 要先复制进来才能 load；这里用 GLTFDocument 直接读
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var err := doc.append_from_file(path, st)
		if err != OK:
			print("  GLTFDocument 读失败 err=%d" % err)
			return
		root = doc.generate_scene(st)
	if root == null:
		print("  ⚠️ 读不到")
		return
	var aabb := _aabb_of(root)
	print("  整体 AABB  X=%.4f  Y=%.4f  Z=%.4f" % [aabb.size.x, aabb.size.y, aabb.size.z])
	# ---- **根的直接子节点**各自多大 ----
	# 这是合集里"哪一块是踏板、哪一块是机体、两者比例多少"的判据。
	print("  ---- 根的直接子节点 ----")
	for c in root.get_children():
		if not (c is Node3D):
			continue
		var n3 := c as Node3D
		var b := _aabb_of_xf(n3, _rel_transform(n3, root))
		print("    %-16s X=%.4f Y=%.4f Z=%.4f   中心=(%.4f, %.4f, %.4f)  底面y=%.4f  面=%d" % [
			str(n3.name), b.size.x, b.size.y, b.size.z,
			b.position.x + b.size.x * 0.5, b.position.y + b.size.y * 0.5,
			b.position.z + b.size.z * 0.5, b.position.y, _tri_count_all(n3)])
	if root.get_child_count() > 1 and not want_parts:
		root.free()
		return
	if root.get_child_count() <= 1 or want_parts:
		# 单体模型：根下面通常就一层包装，把那一层再摊开
		print("  ---- 逐块（按 AABB 体积从大到小）----")
	var rows: Array = []
	for m in _meshes(root):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _rel_transform(mi, root)
		var b := _aabb_xf(mi.get_aabb(), xf)
		rows.append({
			"name": _node_path(mi, root),
			"size": b.size,
			"pos": b.position,
			"surf": mi.mesh.get_surface_count(),
			"tris": _tri_count(mi.mesh),
		})
	# ⚠️ `sort_custom` 的 lambda **不能跨行**（GDScript 会在 `return` 那行断句，
	# 报 "Expected closing \")\" after call arguments"）—— 用一个具名函数替掉。
	rows.sort_custom(_by_volume_desc)
	for r: Dictionary in rows:
		var s: Vector3 = r["size"]
		var p: Vector3 = r["pos"]
		print("    %-34s X=%.4f Y=%.4f Z=%.4f  底面y=%.4f  面=%d" % [
			str(r["name"]).substr(0, 34), s.x, s.y, s.z, p.y, r["tris"]])
	root.free()


func _sort_mid(a: float, b: float, c: float) -> float:
	var arr := [a, b, c]
	arr.sort()
	return arr[1]


func _by_volume_desc(p: Dictionary, q: Dictionary) -> bool:
	var ps: Vector3 = p["size"]
	var qs: Vector3 = q["size"]
	return ps.x * ps.y * ps.z > qs.x * qs.y * qs.z


## 一棵子树在自己的父坐标系里的 AABB（递归合并所有 MeshInstance）。
func _aabb_of_xf(n: Node3D, parent_xf: Transform3D) -> AABB:
	var out := AABB()
	var found := false
	for m in _meshes(n):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := _aabb_xf(mi.get_aabb(), parent_xf * _rel_transform(mi, n))
		if not found:
			out = b
			found = true
		else:
			out = out.merge(b)
	return out


func _tri_count_all(n: Node) -> int:
	var t := 0
	for m in _meshes(n):
		var mi := m as MeshInstance3D
		if mi.mesh != null:
			t += _tri_count(mi.mesh)
	return t


func _aabb_xf(box: AABB, xf: Transform3D) -> AABB:
	var out := AABB(xf * box.position, Vector3.ZERO)
	for i in 8:
		var c := box.position + Vector3(
			box.size.x if (i & 1) else 0.0,
			box.size.y if (i & 2) else 0.0,
			box.size.z if (i & 4) else 0.0)
		out = out.expand(xf * c)
	return out


func _node_path(n: Node, ancestor: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	while cur != null and cur != ancestor:
		parts.push_front(str(cur.name))
		cur = cur.get_parent()
	return "/".join(parts)


func _tri_count(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
			n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _aabb_of(n: Node) -> AABB:
	var out := AABB()
	var found := false
	for m in _meshes(n):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		# 用**合并到根节点坐标系**的盒子：模型内部可能有自己的 transform
		var box := mi.get_aabb()
		var xf := _rel_transform(mi, n)
		var corners := [
			xf * box.position,
			xf * (box.position + Vector3(box.size.x, 0, 0)),
			xf * (box.position + Vector3(0, box.size.y, 0)),
			xf * (box.position + Vector3(0, 0, box.size.z)),
			xf * (box.position + Vector3(box.size.x, box.size.y, 0)),
			xf * (box.position + Vector3(box.size.x, 0, box.size.z)),
			xf * (box.position + Vector3(0, box.size.y, box.size.z)),
			xf * (box.position + box.size),
		]
		for c: Vector3 in corners:
			if not found:
				out = AABB(c, Vector3.ZERO)
				found = true
			else:
				out = out.expand(c)
	return out


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _rel_transform(node: Node, ancestor: Node) -> Transform3D:
	var t := Transform3D()
	var cur := node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
