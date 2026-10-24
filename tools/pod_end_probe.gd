extends Node
## 运输仓模型**两端外缘半径**探针（2026-10-01，为 R4「立起来、大圆面朝下」定朝向）。
##
## ## 为什么必须量，不能推
## `POD_RAW_BOX`（`0.97977 x 0.40694 x 0.45036`）只是 **AABB** —— 它量不出
## "**哪一端更粗**"。而老板 2026-10-01 的口径是「运输仓现在是横着的，把它立起来，
## **圆的面积大的是底面**」⇒ 必须知道 **+X 端（7 只喷口）** 与 **−X 端（舱门面）**
## 哪一端外缘半径大，才能定 `PodHull.rotation_degrees.z` 的**符号**。
##
## ## 跑法（**headless 就够**，不需要像素）
##   godot --headless --path <工程> res://tools/pod_end_probe.tscn
##
## ## 量法
## 把 glb 里所有 `MeshInstance3D` 的顶点换到**根节点局部空间**（模型自己的坐标系，
## 与 `POD_RAW_BOX` 同口径），按 x 分 20 箱，每箱记 `max(sqrt(y²+z²))`；
## 两端各取**最外侧 5% 长度**看平均/最大外缘半径。
##
## ⚠️ 判据要**按半径**而不是按 AABB 的 y/z 分量：筒身不是圆的（`pod_fit_check.py` 记着
## 中段外缘半径在 0.14044…0.19907 之间波动，最窄/最宽 = 0.705），AABB 半宽只是
## 全件包络，不等于某一端的半径。

const MODEL := "res://assets/models/xi_pod/xi_pod.glb"
const BINS := 20


func _ready() -> void:
	var ps := load(MODEL) as PackedScene
	if ps == null:
		push_error("模型缺失：%s" % MODEL)
		get_tree().quit(1)
		return
	var root := ps.instantiate() as Node3D
	add_child(root)
	await get_tree().process_frame

	var pts := PackedVector3Array()
	_collect(root, root, pts)
	print("[pod_end] 模型 = %s" % MODEL)
	print("[pod_end] 顶点总数 = %d" % pts.size())
	if pts.is_empty():
		push_error("一个顶点都没读到")
		get_tree().quit(1)
		return

	var xmin := 1e12
	var xmax := -1e12
	for p: Vector3 in pts:
		xmin = minf(xmin, p.x)
		xmax = maxf(xmax, p.x)
	var span := xmax - xmin
	print("[pod_end] x 范围 %.6f .. %.6f   长轴长 %.6f" % [xmin, xmax, span])

	# ---- 按 x 分箱：每箱的 max 半径 + 顶点数 ----
	var max_r := PackedFloat32Array()
	var n_in := PackedInt32Array()
	max_r.resize(BINS)
	n_in.resize(BINS)
	for i in BINS:
		max_r[i] = 0.0
		n_in[i] = 0
	for p: Vector3 in pts:
		var r := sqrt(p.y * p.y + p.z * p.z)
		var b := int(floor((p.x - xmin) / span * float(BINS)))
		b = clampi(b, 0, BINS - 1)
		if r > max_r[b]:
			max_r[b] = r
		n_in[b] += 1

	print("[pod_end] ---- 沿长轴分 %d 箱：外缘半径 max(sqrt(y²+z²)) ----" % BINS)
	var peak_bin := 0
	for i in BINS:
		var x0 := xmin + span * float(i) / float(BINS)
		var x1 := xmin + span * float(i + 1) / float(BINS)
		var bar := ""
		for k in int(max_r[i] / 0.5 * 60.0):
			bar += "#"
		print("  bin %2d  x %.4f..%.4f  r_max %.5f  n %7d  %s"
			% [i, x0, x1, max_r[i], n_in[i], bar])
		if max_r[i] > max_r[peak_bin]:
			peak_bin = i

	# ---- 两端各取最外侧 5% 长度：只看贴端面的那一圈 ----
	var cut := span * 0.05
	var neg_r := 0.0   # −X 端（舱门面）
	var pos_r := 0.0   # +X 端（推进簇）
	var neg_n := 0
	var pos_n := 0
	for p: Vector3 in pts:
		var r := sqrt(p.y * p.y + p.z * p.z)
		if p.x <= xmin + cut:
			neg_n += 1
			if r > neg_r:
				neg_r = r
		if p.x >= xmax - cut:
			pos_n += 1
			if r > pos_r:
				pos_r = r

	print("[pod_end] ---- 两端最外侧 5%%（%.4f m）外缘半径 ----" % cut)
	print("[pod_end] -X 端（x <= %.4f，注释称**舱门面**）  n %7d  r_max %.5f" % [xmin + cut, neg_n, neg_r])
	print("[pod_end] +X 端（x >= %.4f，注释称**7 只喷口**）n %7d  r_max %.5f" % [xmax - cut, pos_n, pos_r])
	print("[pod_end] 比值  +X / -X = %.4f" % (pos_r / maxf(neg_r, 1e-9)))
	print("[pod_end] 全件峰值箱 = bin %d（x %.4f..%.4f，r %.5f）"
		% [peak_bin, xmin + span * float(peak_bin) / float(BINS),
		   xmin + span * float(peak_bin + 1) / float(BINS), max_r[peak_bin]])

	# ---- 结论：哪一端当底面 ----
	var bigger := "+X（推进簇端）" if pos_r > neg_r else "-X（舱门面）"
	print("[pod_end] ⇒ 「大圆面」在 %s ｜ r=%.5f vs %.5f（差 %.2f%%）"
		% [bigger, pos_r, neg_r, absf(pos_r - neg_r) / maxf(maxf(pos_r, neg_r), 1e-9) * 100.0])
	if absf(pos_r - neg_r) / maxf(maxf(pos_r, neg_r), 1e-9) < 0.02:
		print("[pod_end] ⚠️ 两端半径差 < 2%% ⇒ 视觉上分不出粗细，「大圆面朝下」要另找理由（见设计文档 §3.4）")

	get_tree().quit(0)


## 把 `node` 子树里所有网格的顶点换到 `root` 的局部空间。
##
## ⚠️ 用 `global_transform` 相对换算（不是 `Node3D.transform` 逐层累乘）：
## glb 导入后可能夹着若干层 `Node3D`，手写累乘漏一层就是**整体偏移**且不报错。
func _collect(node: Node, root: Node3D, out: PackedVector3Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var m := mi.mesh
		if m != null:
			var xf := root.global_transform.affine_inverse() * mi.global_transform
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				if arr.size() == 0:
					continue
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				for v: Vector3 in vs:
					out.append(xf * v)
	for c in node.get_children():
		_collect(c, root, out)
