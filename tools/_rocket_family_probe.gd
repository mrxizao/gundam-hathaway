extends SceneTree
## 一次性工具：把 `马夫蒂火箭.glb` **按族**量一遍 AABB（Godot 空间，Y-up）。
##
## ## 为什么需要它
## 清洗时把 444 张贴图改名成 `mafty_rocket_<r|p>_p<件号>_<role>`，
## 族标 `r`/`p` 就**存在贴图名里**。于是"哪些网格属于哪一族"是可读的 ——
## 不需要再猜、不需要再聚类。
##
## 得到两族的 AABB 之后，"模型长轴是哪根、载荷段朝哪边"就是**读数**而不是观感。
##
## ⚠️ 两个坑（都在 `_dump_parts.gd` 上踩过）
## ① `tools/_dump_parts.gd` 算 AABB 用的是 `get_global_transform()`，而它
##    **不入树** ⇒ 那个函数直接返回单位矩阵、报
##    `Condition "!is_inside_tree()" is true`，算出来的是"未变换的顶点并集"
##    （实测 size=(0.8084, 0.5484, 0.4513)，与逐顶点投影的真值
##    (0.1708, 0.8038, 0.3079) **完全不同**）。
##    **本脚本的修法不是"记得入树"，而是根本不问场景树** ——
##    见 `_walk()`：沿父链把 `Node3D.transform` **自己乘起来**。
##    本脚本第一版写了 `root.add_child(inst)`，实测在 `SceneTree._initialize()`
##    的时机里**仍然**报 `!is_inside_tree()`（268 个网格全报），
##    于是"修好了"是假象、读数照旧是错的 —— 这类"改了个看不见的东西、
##    读数没变而你以为变了"的坑，比不改更危险。
## ② `MeshInstance3D.get_aabb()` 是**模型空间**的，必须自己乘变换的 8 个角
##    （Godot 没有 `Transform3D * AABB` 这个重载）。
##
## 用法：
##   godot --headless --path <工程> --script res://tools/_rocket_family_probe.gd

const MODEL := "res://assets/models/mafty_rocket/mafty_rocket.glb"


func _initialize() -> void:
	var ps := load(MODEL) as PackedScene
	if ps == null:
		print("load 失败：", MODEL)
		quit(1)
		return
	var inst := ps.instantiate() as Node3D
	var acc := {}          # 族 -> AABB
	var n := {}            # 族 -> 网格数
	var tris := {}         # 族 -> 三角数
	var total := [0]
	_walk(inst, Transform3D.IDENTITY, acc, n, tris, total)

	print("\n=== %s ===" % MODEL)
	print("MeshInstance3D 总数 %d，族数 %d" % [total[0], acc.size()])
	var keys := acc.keys()
	keys.sort()
	for k: String in keys:
		var a: AABB = acc[k]
		print("  族 '%s'  网格 %4d  三角 %8d  AABB pos=(%.4f, %.4f, %.4f) size=(%.4f, %.4f, %.4f)"
			% [k, int(n[k]), int(tris[k]),
			a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z])
	var all := AABB()
	var first := true
	for k: String in keys:
		all = acc[k] if first else all.merge(acc[k])
		first = false
	print("  合计 AABB pos=(%.4f, %.4f, %.4f) size=(%.4f, %.4f, %.4f)"
		% [all.position.x, all.position.y, all.position.z, all.size.x, all.size.y, all.size.z])
	# 长轴 / 次轴 / 最短 三档（用排序，别手写嵌套三元 —— 那正是本脚本第一版写错的地方）
	var s := all.size
	var arr := [[s.x, "X"], [s.y, "Y"], [s.z, "Z"]]
	arr.sort_custom(func(a, b): return a[0] > b[0])
	print("  ⇒ 长轴 %s=%.4f   次轴 %s=%.4f   最短 %s=%.4f"
		% [arr[0][1], arr[0][0], arr[1][1], arr[1][0], arr[2][1], arr[2][0]])

	# ---- 朝向备选：把**模型的 X/Y/Z 各送到机体的哪根轴**打出来 ----
	#
	# ⚠️ 这一步的来历：光知道"长轴 = Y"只够摆正**机头**（模型 +Y → 机体 −Z），
	# 摆不摆得对**滚转**是另一回事 —— 而两族的 X/Z 宽度是 0.174 / 0.308
	# （Z 明显更宽 = 两个助推器沿模型 **Z** 排开），所以滚转错了的话
	# 两个助推器会变成"一前一后叠着"而不是"左右并排"，**不报任何错**。
	# 与其在脑子里推 `Basis` 的乘法顺序，不如让引擎把它算出来。
	print("\n  ---- 朝向备选（模型轴 → 机体轴）----")
	for name in ["A: 只转 X −90°", "B: 再绕机体 Z 滚 −90°"]:
		var b := _candidate_basis(name)
		print("  %s" % name)
		print("     模型 +X → 机体 (%+.3f, %+.3f, %+.3f)" % [b.x.x, b.x.y, b.x.z])
		print("     模型 +Y → 机体 (%+.3f, %+.3f, %+.3f)" % [b.y.x, b.y.y, b.y.z])
		print("     模型 +Z → 机体 (%+.3f, %+.3f, %+.3f)" % [b.z.x, b.z.y, b.z.z])
		var w := _xb_aabb(all, Transform3D(b, Vector3.ZERO))
		print("     ⇒ 机体包围盒 size=(%.4f, %.4f, %.4f)  横向 X %.4f vs 竖向 Y %.4f  %s"
			% [w.size.x, w.size.y, w.size.z, w.size.x, w.size.y,
			("← 助推器左右并排（对）" if w.size.x > w.size.y else "← 助推器上下叠着（错）")])
	quit(0)


## 两个候选滚转。**返回的是"模型 → 机体"的 basis**。
func _candidate_basis(name: String) -> Basis:
	if name.begins_with("B"):
		# ① 绕机体 X 轴 −90°：模型 +Y（长轴）→ 机体 −Z（机头）
		# ② 再绕机体 Z 轴 −90°：让模型 +Z（助推器排开的方向）落到**水平**的机体 +X
		return Basis(Vector3.BACK, -PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5)
	return Basis(Vector3.RIGHT, -PI * 0.5)


## 递归累乘父链变换。`xf` = **父**空间到根的总变换，不含 `node` 自己。
func _walk(node: Node, xf: Transform3D, acc: Dictionary, n: Dictionary,
		tris: Dictionary, total: Array) -> void:
	var here := xf
	if node is Node3D:
		here = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			total[0] = int(total[0]) + 1
			var fam := _family_of(mi)
			var a := _xb_aabb(mi.mesh.get_aabb(), here)
			acc[fam] = acc[fam].merge(a) if acc.has(fam) else a
			n[fam] = int(n.get(fam, 0)) + 1
			var t := 0
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				t += (idx.size() / 3) if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX].size() / 3)
			tris[fam] = int(tris.get(fam, 0)) + t
	for c in node.get_children():
		_walk(c, here, acc, n, tris, total)


## 族标：从贴图路径里抠 `_r_` / `_p_` 那段。**这是清洗时刻进名字里的**。
func _family_of(mi: MeshInstance3D) -> String:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m is BaseMaterial3D:
			var tex := (m as BaseMaterial3D).albedo_texture
			if tex != null:
				var p := tex.resource_path
				if p.contains("_r_p"):
					return "r"
				if p.contains("_p_p"):
					return "p"
	return "?"


## MeshInstance3D 的 AABB 乘上 `xf` 之后的轴对齐包围盒。
##
## ⚠️ 自己乘 8 个角：Godot **没有** `Transform3D * AABB` 这个重载，
## 而 `xf * aabb.get_center() ± aabb.size/2` 这种"乘中心再加减半长"是**错的**
## —— 变换含旋转时它给出的是一个歪掉的盒子。
func _xb_aabb(a: AABB, xf: Transform3D) -> AABB:
	var out := AABB()
	for i in 8:
		var corner := a.position + Vector3(
			a.size.x * float(i & 1), a.size.y * float((i >> 1) & 1), a.size.z * float((i >> 2) & 1))
		var w := xf * corner
		out = AABB(w, Vector3.ZERO) if i == 0 else out.expand(w)
	return out
