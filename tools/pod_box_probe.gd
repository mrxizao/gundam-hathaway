extends Node
## 探针：量运输仓**真模型**（`PodHull`）的实建外框、缩放、网格规模与碰撞体，
## 并核对 HUD 目标信标 `CargoTarget` 的"可显示但不可被攻击"性质。
##
## ⚠️ 本探针只管"读数好不好看"，**判据在 `suite_space_map` 里**
##（同一套口径量同一个 AABB；探针挂了不影响回归，判据挂了才算数）。
##
## ## 口径演进（三轮）—— 探针别再用旧的两条
## | 轮次 | 做法 | 结局 |
## |---|---|---|
## | 轮 44 | **最长边** × 2.3（程序化三段盒体） | 高只有机体的 0.63 倍 ⇒ 露头露脚 |
## | 轮 45 | **逐轴** × 2.3（程序化壳式方筒） | 方筒凑得出，但那是**替身** |
## | 轮 46 | 换**真模型** ⇒ 逐轴**无解** | 改问需求本身：**装得下 + 5% 余量** |
##
## ★ 为什么"逐轴 × 2.3"在真件上无解：仓是**圆柱**，等比缩放时三轴倍率必然相同，
## 硬凑要 `kx 48.8 / ky 158.3 / kz 110.6` ⇒ 会把筒压成扁鼓。
##
## ★★ **本探针量不出"装得下"** —— 真正的判据只在 `tools/pod_fit_check.py`（Blender）：
## 从仓轴心打 87 120 条射线得外缘半径图，再拿柯西 `xi_fly.glb` 的 **7948 个真实顶点**
## 逐点查表。原因：筒壁**不是圆的**（中段外缘半径 0.14044 … 0.19907 ⇒ 最窄/最宽
## = 0.705），柯西是**斜着躺**进去的 ⇒ 拿 AABB 当"内腔"会算出**假红**。
##
## 用法：godot --headless --path <工程> res://tools/pod_box_probe.tscn

var _world: WorldBuilder
var _terrain: Node


func _ready() -> void:
	_world = WorldBuilder.new()
	add_child(_world)
	await get_tree().physics_frame
	_world.apply_map(MapDef.leo())
	await _frames(20)
	_terrain = _world.get("_terrain_root")

	# ---------------- ① 实建外框 ----------------
	var pod := _pods_aabb()
	var raw := WorldBuilder.POD_RAW_BOX
	var want := WorldBuilder.POD_BOX
	print("")
	print("[模型] AABB = %.5f x %.5f x %.5f m   × 缩放 %.3f  ⇒ 目标外框 %.2f x %.2f x %.2f"
		% [raw.x, raw.y, raw.z, WorldBuilder.POD_SCALE, want.x, want.y, want.z])
	print("[仓]   实建 AABB = %.2f x %.2f x %.2f m" % [pod.size.x, pod.size.y, pod.size.z])
	for k in 3:
		var got: float = [pod.size.x, pod.size.y, pod.size.z][k]
		var w: float = [want.x, want.y, want.z][k]
		print("   %s: 实建 %.2f / 目标 %.2f  => 比值 %.4f  %s"
			% ["XYZ"[k], got, w, got / w, "OK" if absf(got - w) <= 0.05 else "**不符**"])
	var pc := pod.position + pod.size * 0.5
	print("[仓]   中心 (%.2f, %.2f, %.2f)  相对场地中心偏移 (%.2f, %.2f, %.2f)"
		% [pc.x, pc.y, pc.z, pc.x - WorldBuilder.SPACE_POD_POS.x,
		   pc.y - WorldBuilder.SPACE_POD_POS.y, pc.z - WorldBuilder.SPACE_POD_POS.z])
	print("[仓]   最长边 / 柯西全高 = %.3f   （用户最初口径「大 2.3 倍左右」）"
		% (pod.size.x / SuitProfile.xi().target_height))

	# ---------------- ② 构型：闭合实体 ⇒ **没有内腔** ----------------
	#
	# 轮 46 前的程序化方筒是**壳式**的（壁 + 内腔），判据里有一组"内腔净空"。
	# 真模型是**闭合实体**（垂直长轴过轴心的射线只穿 2 面）⇒ 那组判据的**对象不存在了**，
	# 已随批② 删除。这里改成量"它到底是不是真的装进来了"。
	print("")
	var hull := _terrain.find_child("PodHull", true, false) as Node3D
	print("[模型] PodHull 存在 = %s" % (hull != null))
	if hull != null:
		print("[模型] 节点缩放 = (%.4f, %.4f, %.4f)   （必须等比且 == POD_SCALE %.3f）"
			% [hull.scale.x, hull.scale.y, hull.scale.z, WorldBuilder.POD_SCALE])
		var mi := _first_mesh(hull)
		print("[模型] 底下 MeshInstance3D 数 = %d" % _mesh_count(hull))
		if mi != null and mi.mesh != null:
			var m: Mesh = mi.mesh
			var nv := 0
			var ni := 0
			for si in m.get_surface_count():
				# ⚠️⚠️ **绝不对高模调 `surface_get_arrays()`** —— 它会把全套顶点属性
				# 在 GDScript 边界物化（这一个网格 111 万顶点 ⇒ 几百 MB）。
				# 第一版探针踩过：同一个网格调两次，**跑了 10 分钟没出来**。
				# 只取 O(1) 元数据。
				var al: int = m.surface_get_array_len(si)
				var il: int = m.surface_get_array_index_len(si)
				nv += al
				ni += il
			print("[模型] 表面 %d 个  顶点 %d  索引 %d（≈%d 三角）"
				% [m.get_surface_count(), nv, ni, ni / 3])

	# ---------------- ③ 碰撞：glTF 导入**不带**碰撞 ----------------
	print("")
	var body := _terrain.find_child("PodBody", true, false) as StaticBody3D
	print("[碰撞] PodBody = %s" % (body != null))
	if body != null:
		print("[碰撞] 所在层 = %d（= WORLD_LAYER %d）  mask = %d"
			% [body.collision_layer, FlightBody.WORLD_LAYER, body.collision_mask])
		for ch in body.get_children():
			if ch is CollisionShape3D:
				var cs := ch as CollisionShape3D
				if cs.shape is CylinderShape3D:
					var cyl := cs.shape as CylinderShape3D
					print("[碰撞] CylinderShape3D  radius=%.2f  height=%.2f  rot=(%.0f, %.0f, %.0f)"
						% [cyl.radius, cyl.height, cs.rotation_degrees.x,
						   cs.rotation_degrees.y, cs.rotation_degrees.z])
					print("[碰撞] 派生自 POD_RAW_BOX × %.3f ⇒ 期望 r=%.2f h=%.2f  %s"
						% [WorldBuilder.POD_SCALE, raw.y * 0.5 * WorldBuilder.POD_SCALE,
						   raw.x * WorldBuilder.POD_SCALE,
						   "OK" if absf(cyl.radius - raw.y * 0.5 * WorldBuilder.POD_SCALE) <= 0.05
						   else "**不符**"])

	# ---------------- ④ 「装得下」的真判据（在 Blender 里，这里只报出处）----------------
	print("")
	print("[装下] 判据出处 `tools/pod_fit_check.py`（Blender BVH）：")
	print("[装下]   探针实测最小可行 k = 71.92（打印值；真值 71.9219x）@ φ = %.1f°"
		% WorldBuilder.POD_CARGO_ROLL_DEG)
	print("[装下]   源码取**向上取整** %.2f（截断的 71.92 只有 0.9996）× 余量 %.2f = %.3f"
		% [WorldBuilder.POD_FIT_MIN, WorldBuilder.POD_CLEARANCE, WorldBuilder.POD_SCALE])
	print("[装下]   ⇒ 柯西 7948 个真实顶点**全部**在仓内（覆盖 1.0000）")
	print("[装下]   负对照 k×0.9 = 64.76 ⇒ 覆盖 0.9896、露 83 点（判据能变红）")
	print("[装下]   ★ 机体必须**躺着**（身高沿仓的长轴）：站着放在工程 k 下只有 0.9927，")
	print("[装下]     要 k = 91.53（1.27 倍）才装得下 ⇒ 摆位口径见 tools/pod_scale_shot.gd")
	print("[装下] ⚠️ 本探针**不做摆位**（一份口径只留一处实现）")

	# ---------------- ⑤ CargoTarget：可显示但不可被攻击 ----------------
	var tag := _terrain.find_child("CargoTarget", true, false)
	print("")
	print("[信标] 节点存在 = %s" % (tag != null))
	if tag != null:
		print("[信标] 在 pod_target 组 = %s" % tag.is_in_group(WorldBuilder.POD_TAG_GROUP))
		print("[信标] 在 units 组 = %s   （必须 false —— 否则进锁定候选表）"
			% tag.is_in_group("units"))
		print("[信标] 有 take_damage 方法 = %s   （必须 false —— 否则能被打）"
			% tag.has_method("take_damage"))
		print("[信标] 有 is_hostile_to 方法 = %s   （必须 false —— 否则会被当敌人）"
			% tag.has_method("is_hostile_to"))
		print("[信标] 位置 (%.1f, %.1f, %.1f)  vs SPACE_POD_POS (%.1f, %.1f, %.1f)"
			% [tag.position.x, tag.position.y, tag.position.z,
			   WorldBuilder.SPACE_POD_POS.x, WorldBuilder.SPACE_POD_POS.y,
			   WorldBuilder.SPACE_POD_POS.z])
	# 反查：PlayerController 的锁定候选表来源是 `Game.live_hostiles_of`
	var units := get_tree().get_nodes_in_group("units")
	var bad := 0
	for u: Node in units:
		if str(u.name).begins_with("Pod") or str(u.name) == "CargoTarget":
			bad += 1
	print("[信标] units 组里以 Pod/CargoTarget 命名的节点数 = %d   （必须 0）" % bad)

	print("[柯西] 机体 AABB = %.2f x %.2f x %.2f m（**不是判据**；决定装不装得下的是"
		% [WorldBuilder.XI_BOX.x, WorldBuilder.XI_BOX.y, WorldBuilder.XI_BOX.z])
	print("[柯西]   那条逐顶点覆盖 —— 见上面的「装下」一节）")

	print("")
	print("POD_BOX_DONE")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 合并 `_terrain_root` 下所有 `Pod*` 子树的 AABB（与 `suite_space_map._pods_aabb` 同源）。
func _pods_aabb() -> AABB:
	var box := AABB()
	var found := false
	var stack: Array[Node] = [_terrain]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and str(n.name).begins_with("Pod"):
			var b := _subtree_aabb(n)
			box = b if not found else box.merge(b)
			found = true
			continue
		for c in n.get_children():
			stack.append(c)
	return box


func _subtree_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var found := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var b: AABB = (cur as MeshInstance3D).global_transform * (cur as MeshInstance3D).get_aabb()
			box = b if not found else box.merge(b)
			found = true
		for c in cur.get_children():
			stack.append(c)
	return box


func _aabb_global(root: Node3D) -> AABB:
	return _subtree_aabb(root)


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


func _mesh_count(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D:
		c += 1
	for ch in n.get_children():
		c += _mesh_count(ch)
	return c
