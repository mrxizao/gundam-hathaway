extends Node
## 收纳仓 GLB 的**引擎侧**读数探针（Godot 4.7）。
##
## 为什么要有这个：`world_builder` 里的常量必须来自**引擎导入后**的 AABB
##（导入器的 `apply_root_scale` / 节点 TRS 会改数），拿 Blender 的读数去写迟早对不上。
##
## ★★ 性能纪律（第一版在这里卡了 10 分钟）：**绝不要对高模调 `surface_get_arrays()`**
##   —— 它会把 111 万顶点 × 全套属性在 GDScript 边界上物化一遍（几百 MB），
##   本探针第一版对同一网格调了**两次**（算三角数 + 算顶点数）⇒ 10 分钟以上没出来。
##   要便宜的数：`Mesh.get_aabb()` / `surface_get_array_len()` / `surface_get_array_index_len()`
##   —— 都是 O(1) 的元数据查询。
##
## 调用：godot --headless --path <工程> res://tools/pod_glb_probe.tscn

const GLB := "res://assets/models/xi_pod/xi_pod.glb"


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var ps := load(GLB) as PackedScene
	var t_load := Time.get_ticks_msec() - t0
	if ps == null:
		print("[pod_glb] ★ load 返回 null —— 资产没导入？")
		get_tree().quit(1)
		return
	var inst := ps.instantiate()
	add_child(inst)
	await get_tree().process_frame

	print("[pod_glb] load() 耗时 = %d ms" % t_load)
	print("[pod_glb] 实例根 = %s  transform = %s" % [inst.name, inst.transform])

	var lo := Vector3.INF
	var hi := -Vector3.INF
	var n_mesh := 0
	var n_tri := 0
	var n_vert := 0
	var lines: Array[String] = []
	for n in _all(inst):
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh := mi.mesh
			if mesh == null:
				continue
			n_mesh += 1
			var ab: AABB = mi.global_transform * mesh.get_aabb()
			lo = lo.min(ab.position)
			hi = hi.max(ab.position + ab.size)
			var tri := 0
			var vert := 0
			for si in mesh.get_surface_count():
				var al: int = mesh.surface_get_array_len(si)
				var il: int = mesh.surface_get_array_index_len(si)
				vert += al
				tri += (il if il > 0 else al) / 3
			n_tri += tri
			n_vert += vert
			lines.append("  %s  mesh=%s  面 %d  顶点 %d  三角 %d  local_transform=%s"
				% [mi.name, mesh.get_class(), mesh.get_surface_count(), vert, tri, mi.transform])
			for si in mesh.get_surface_count():
				var mat := mesh.surface_get_material(si)
				if mat is BaseMaterial3D:
					var b := mat as BaseMaterial3D
					lines.append("      材质[%d] 「%s」albedo_tex=%s"
						% [si, b.resource_name, b.albedo_texture.resource_path if b.albedo_texture else "<无>"])

	print("[pod_glb] 网格实例 %d  顶点 %d  三角 %d" % [n_mesh, n_vert, n_tri])
	for s in lines:
		print("[pod_glb]%s" % s)
	var size := hi - lo
	print("[pod_glb] AABB(Godot 世界) X=%.5f Y=%.5f Z=%.5f" % [size.x, size.y, size.z])
	print("[pod_glb] AABB min (%.5f, %.5f, %.5f)  max (%.5f, %.5f, %.5f)"
		% [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z])
	print("[pod_glb] 中心 (%.5f, %.5f, %.5f)" % [(lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5])
	print("[pod_glb] 总耗时 = %d ms" % (Time.get_ticks_msec() - t0))
	print("[pod_glb] DONE")
	get_tree().quit(0)


func _all(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
