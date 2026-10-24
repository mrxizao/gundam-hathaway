extends Node
## 量**马夫蒂火箭的喷口位置**（2026-09-30 晚）。
##
## 老板原话：
## > 「**火箭下面只有一条长拖尾，但是火箭左右两边还有辅助推进器，
## >   这两条辅助推进器都需要做尾焰和拖尾**」
##
## 所以要先知道那两根助推器的**喷口在箭体局部哪里**（机头 = −Z、箭底 = 原点）。
## 本探针**不拍图、不开窗口**（headless 即可：只读 mesh 的 AABB 与节点变换，
## 与 `RocketBody._fit_scale()` 走同一条纯数学路径）。
##
## ## 判据怎么读
## 打印"**局部 AABB 的 z_min < 6 m**"（= 贴着箭底）的每一个零件，
## 再按 X 分三档聚合 —— 左助推器 / 芯级 / 右助推器各成一簇，
## 每簇的（X 中心, Z 最小）就是那个喷口的位置。
##
## ⚠️ 用 `RocketBody._xb_aabb()` 而不是 `mi.mesh.get_aabb()`：
## 后者是**模型空间**的，而这份资产是 268 个带旋转的零件（`_fit_scale()` 的注释里
## 记着这个坑：直接拿它会得到"未变换的顶点并集"，实测差 47%）。
##
## 跑法：
##   godot --headless --path <工程> res://tools/_rocket_nozzle_probe.tscn

## 只打印"贴到箭底"这个深度以内的零件（米）。
##
## ⚠️ 箭底的局部 z 是 **0**（`_fit_scale()` 把模型尾端对齐到机体原点），
## 而整枚箭占 z ∈ [−58, 0]（机头 = −Z）。所以"贴着箭底"= **z 的最大值接近 0**，
## 判据是 `zmax > −Z_BOTTOM` —— 第一版写成 `zmin < Z_BOTTOM`，
## 结果把**全部 268 个零件**都选进来（所有零件的 z_min 都远小于 0）。
const Z_BOTTOM := 6.0
## 按 X 分簇的边界（米）。助推器在 ±X 两侧，芯级在 0 —— 中间那档留宽一点，
## 因为芯级的喷口盘本身有直径。
const X_SPLIT := 4.0

func _ready() -> void:
	var rk := RocketBody.new()
	rk.name = "MaftyRocket"
	rk.configure(LaunchScript.ASCENT_SPAN)
	add_child(rk)
	rk.place_at_launch(LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))
	var ps := load("res://assets/models/mafty_rocket/mafty_rocket.glb") as PackedScene
	if ps == null:
		push_error("火箭资产载不到")
		get_tree().quit(1)
		return
	rk.set_model(ps.instantiate())
	await get_tree().process_frame

	var mr := rk.model_root()
	print("== 模型根：scale = %.5f / position = (%.3f, %.3f, %.3f) / basis.y = %s"
		% [mr.scale.x, mr.position.x, mr.position.y, mr.position.z, str(mr.basis.y)])

	# 世界 → 箭体局部：`rk.global_transform` 的逆。
	var inv := rk.global_transform.affine_inverse()
	var total := 0
	var bottom: Array = []
	for n in mr.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		total += 1
		var xf: Transform3D = inv * mi.global_transform
		var a := RocketBody._xb_aabb(mi.mesh.get_aabb(), xf)
		var zlo := minf(a.position.z, a.position.z + a.size.z)
		var zhi := maxf(a.position.z, a.position.z + a.size.z)
		if zhi > -Z_BOTTOM:
			bottom.append({
				"name": String(mi.name),
				"x": a.position.x + a.size.x * 0.5,
				"y": a.position.y + a.size.y * 0.5,
				"zmin": zlo,
				"zmax": zhi,
				"sx": a.size.x, "sy": a.size.y, "sz": a.size.z,
			})
	print("== 模型共 %d 个 MeshInstance3D；其中贴着箭底（局部 z_max > −%.0f m）的有 %d 个"
		% [total, Z_BOTTOM, bottom.size()])
	print("== 箭体局部约定：机头 = −Z / 箭底 = z 0 / 右 = +X / 上 = +Y")

	bottom.sort_custom(func(a, b): return float(a["zmax"]) > float(b["zmax"]))
	print("---- 贴着箭底的零件（按 z_max 降序 = 越靠前越贴近箭底）----")
	for it: Dictionary in bottom:
		print("   %-34s X %+7.2f  Y %+7.2f  Z [%+6.2f, %+6.2f]  尺寸 (%.2f, %.2f, %.2f)"
			% [it["name"], it["x"], it["y"], it["zmin"], it["zmax"],
				it["sx"], it["sy"], it["sz"]])

	# ---- 按 X 分三簇聚合：每簇给"最靠箭底那一点"与 X 范围 ----
	var buckets := {"左 (-X)": [], "中": [], "右 (+X)": []}
	for it: Dictionary in bottom:
		var x := float(it["x"])
		if x < -X_SPLIT:
			buckets["左 (-X)"].append(it)
		elif x > X_SPLIT:
			buckets["右 (+X)"].append(it)
		else:
			buckets["中"].append(it)
	print("---- 按 X 分簇（|X| > %.0f m 算侧助推器）----" % X_SPLIT)
	for key: String in ["左 (-X)", "中", "右 (+X)"]:
		var arr: Array = buckets[key]
		if arr.is_empty():
			print("   %-8s 没有零件贴到箭底" % key)
			continue
		var xlo := INF
		var xhi := -INF
		var zmax := -INF
		var x_at := 0.0
		for it: Dictionary in arr:
			xlo = minf(xlo, float(it["x"]) - float(it["sx"]) * 0.5)
			xhi = maxf(xhi, float(it["x"]) + float(it["sx"]) * 0.5)
			if float(it["zmax"]) > zmax:
				zmax = float(it["zmax"])
				x_at = float(it["x"])
		print("   %-8s 零件 %2d 个 / X ∈ [%+.2f, %+.2f] / 最靠箭底 z_max = %+.2f（在 X = %+.2f）"
			% [key, arr.size(), xlo, xhi, zmax, x_at])

	get_tree().quit(0)
