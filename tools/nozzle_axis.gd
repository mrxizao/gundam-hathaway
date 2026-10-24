extends Node3D
## 喷口**朝向**扫描探针（第十八轮）：从喷口点向外打一圈射线，量每个方向的**自由程**。
##
## ## 为什么不用深度栅格（`nozzle_scan.tscn`）量朝向
## 那一套是"屏幕空间"的：凹陷判据 `t − 开运算(t)` 在**剪影边缘**同样会给出很大的值
##（边缘处深度陡升，开运算的圆盘放不下），于是"凹陷簇"会贴着机体轮廓连成一条带 ——
## 实测在佩涅罗佩后视上就是这样，读数**不是喷口**。用它量朝向 = 拿伪影当信号。
##
## ## 这一套量什么
## 从喷口点 `P` 出发，沿方向 `d` 打一条射线，记**首个交点距离 `L(d)`**（打不到 = 上限）。
## `L(d)` 大的方向 = "这个口朝外最空的那一边"。
## 对开在机体表面上的**开口 / 导管**来说，这就是它的**开口朝向** ——
## 导管壁与邻近结构会把其余方向堵住（`L` 很小）。
##
## ⚠️ **这套口径的边界要写清楚**（别当万能）：
##   · 它给的是"**最空的方向**"，不是"几何轴"的严格拟合；
##   · 若自由程的角度分布是一个**很宽的锥**（机体表面本来就朝外的一大片），
##     那么峰值方向**不唯一** ⇒ 必须把整张角度图打出来看**平台有多宽**，
##     只报峰值就是 10.20c 那类"单一量具"风险。
##   · 因此产物里同时给：① 峰值方向；② "自由程 ≥ 0.8 上限"的方向集合的**质心**与**张角**。
##
## ## 跑法
##   godot --headless --path <工程> res://tools/nozzle_axis.tscn -- \
##        <输出txt> <模型路径> <仰角起:止:步> <方位起:止:步> <标签:x,y,z> ...
##
## 方向参数化与本目录的 `nozzle_scan.tscn` **同一套**（便于两边互相对照）：
##   `d = (sin(az)cos(el), sin(el), cos(az)cos(el))`，仰角正 = 偏 +Y，方位正 = 偏 +X。

const CAP := 200.0
## 探针起点沿射线方向先**退**这么远再打 —— 起点正好落在三角面上时，
## `intersect_ray` 会以 `hit_from_inside` 命中自己那一格（距离≈0），
## 那会把"朝外"的方向也读成 0。退 2 cm 足以避开自命中，又不影响米级结论。
const EPS := 0.02


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("用法：-- <输出txt> <模型路径> <el起:止:步> <az起:止:步> <标签:x,y,z> ...")
		get_tree().quit(2)
		return
	var out := args[0]
	var model_path := args[1]
	var els := _range_of(args[2])
	var azs := _range_of(args[3])
	var targets: Array = []
	for i in range(4, args.size()):
		var s := String(args[i])
		var c := s.find(":")
		var tag := s.substr(0, c)
		var xs := s.substr(c + 1).split(",")
		targets.append({"tag": tag,
			"frac": Vector3(float(xs[0]), float(xs[1]), float(xs[2]))})

	var inst := _load_model(model_path)
	if inst == null:
		push_error("模型加载失败：%s" % model_path)
		get_tree().quit(3)
		return
	add_child(inst)

	# 复刻 `FlightBody._center_and_measure()` 的居中规则（与 `nozzle_scan.tscn` 一致）
	var raw := _aabb_of(inst)
	var offset := raw.get_center()
	offset.y = raw.position.y + raw.size.y * 0.55
	inst.position = -offset
	var bounds := AABB(raw.position - offset, raw.size)
	print("### BOUNDS  pos=(%.5f, %.5f, %.5f)  size=(%.5f, %.5f, %.5f)" % [
		bounds.position.x, bounds.position.y, bounds.position.z,
		bounds.size.x, bounds.size.y, bounds.size.z])

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
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_line("# tag el az L hit nx ny nz  (frac 为包围盒归一化分数；L 单位=模型单位)")
	f.store_line("# bounds %s %s %s %s %s %s" % [
		bounds.position.x, bounds.position.y, bounds.position.z,
		bounds.size.x, bounds.size.y, bounds.size.z])
	for t: Dictionary in targets:
		var frac: Vector3 = t["frac"]
		var p: Vector3 = bounds.position + frac * bounds.size
		for el in els:
			for az in azs:
				var er := deg_to_rad(el)
				var ar := deg_to_rad(az)
				var d := Vector3(sin(ar) * cos(er), sin(er), cos(ar) * cos(er)).normalized()
				var o := p + d * EPS
				var q := PhysicsRayQueryParameters3D.create(o, o + d * CAP)
				q.collision_mask = 0xFFFFFFFF
				var r := space.intersect_ray(q)
				if r.is_empty():
					f.store_line("ray %s %d %d %.6f 0 0 0 0" % [t["tag"], el, az, CAP])
				else:
					var hp: Vector3 = r["position"]
					var nn: Vector3 = r["normal"]
					f.store_line("ray %s %d %d %.6f 1 %.6f %.6f %.6f" % [
						t["tag"], el, az, (hp - o).length(), nn.x, nn.y, nn.z])
		print("### TARGET %s frac=(%.4f, %.4f, %.4f) world=(%.4f, %.4f, %.4f)" % [
			t["tag"], frac.x, frac.y, frac.z, p.x, p.y, p.z])
	f.close()
	print("### DONE -> %s  (%d 目标 × %d 方向 = %d 条)" % [
		out, targets.size(), els.size() * azs.size(), targets.size() * els.size() * azs.size()])
	get_tree().quit(0)


## "起:止:步" → 含首尾的整数序列（步长取绝对值；起 > 止 时自动递减）。
func _range_of(s: String) -> Array[int]:
	var xs := s.split(":")
	var a := int(xs[0])
	var b := int(xs[1])
	var st := absi(int(xs[2]))
	var out: Array[int] = []
	if st == 0:
		out.append(a)
		return out
	var i := a
	if a <= b:
		while i <= b:
			out.append(i)
			i += st
	else:
		while i >= b:
			out.append(i)
			i -= st
	return out


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
