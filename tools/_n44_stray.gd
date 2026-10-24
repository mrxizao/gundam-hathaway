extends Node3D
## N44 佩涅罗佩主模型的「**游离网格**」扫描。
##
## ## 为什么要单独扫这一遍
##
## `_n44_shot.tscn` 的四张机位图里，机体**腿下方浮着一个灰色小方块**：
##   - 摆成 `fly` 时它在、换成 `slash` 时**它还在原地**（机体姿势变了它没动）
##     ⇒ 它**不是骨骼蒙皮件**（蒙皮件会跟着姿势走），是挂在根上的自由网格。
##   - 本工程踩过这个坑（`xi_rig_v17.blend` 场景里那个辅助物体 `PC`；
##     更早一次是「忘删 3 个标记球 ⇒ glb 多 3 个网格 +210 KB，**不报错**」）。
##
## ## 判据（不靠名字猜，靠几何）
##
## 真机体件必然**聚成一坨**（并集高 ≈ 0.999 m，与本工程 `model_native_height` 同量级），
## 游离件则表现为**离群的小件**：尺寸远小于整体、且中心远离机体主轴。
## 所以这里同时报三条：
##   ① 全体并集 AABB（与 `_relay/log_pen_geom.txt` 对账）；
##   ② 按「离机体中轴的水平距离」排序的**离群前 8 件**；
##   ③ 每件的 `skin`（蒙皮）有无 —— 无蒙皮 + 离群 = 头号嫌疑。
##
## 跑法：
##   godot --headless --path <工程> res://tools/_n44_stray.tscn

const MAIN := "res://assets/models/penelope_movie/penelope_movie_rigged.scn"


func _ready() -> void:
	var ps := load(MAIN) as PackedScene
	if ps == null:
		print("!! 载入失败 %s" % MAIN)
		get_tree().quit(1)
		return
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	var sk := _first_skeleton(inst)
	print("骨架 = %s ｜ 骨数 %d"
		% [str(sk.get_path()) if sk != null else "(无)", sk.get_bone_count() if sk != null else 0])

	var rows: Array = []
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var ab: AABB = mi.mesh.get_aabb()
		var xf := mi.global_transform
		var mlo := Vector3(1e9, 1e9, 1e9)
		var mhi := Vector3(-1e9, -1e9, -1e9)
		for i in 8:
			var w: Vector3 = xf * ab.get_endpoint(i)
			mlo = mlo.min(w)
			mhi = mhi.max(w)
		lo = lo.min(mlo)
		hi = hi.max(mhi)
		var ctr := (mlo + mhi) * 0.5
		var sz := mhi - mlo
		rows.append({
			"path": str(mi.get_path()),
			"ctr": ctr,
			"span": sz.length(),
			"h": sz.y,
			"skin": mi.skin != null,
			"par": str(mi.get_parent().name),
		})

	var size := hi - lo
	print("")
	print("★ 全体并集 AABB : lo=%s  hi=%s" % [_v(lo), _v(hi)])
	print("★ 整体尺寸      : X %.4f  Y %.4f  Z %.4f   (原生高应 ≈0.9990)" % [size.x, size.y, size.z])
	print("★ 网格总数      : %d" % rows.size())

	# 机体中轴 = 整体 AABB 的水平中心；离群判据 = 水平距离 / 整体水平对角
	var axis := Vector2((lo.x + hi.x) * 0.5, (lo.z + hi.z) * 0.5)
	var horiz_diag: float = maxf(size.x, size.z)
	print("★ 中轴(水平)    : (%.4f, %.4f) ｜ 水平基准 %.4f ｜ 垂直范围 [%.4f, %.4f]"
		% [axis.x, axis.y, horiz_diag, lo.y, hi.y])
	print("")

	# 先把「离中轴的水平距离」算进字典，排序就不用多行 lambda（少一个语法风险点）。
	for r in rows:
		r["d"] = Vector2(r["ctr"].x, r["ctr"].z).distance_to(axis)
	rows.sort_custom(func(a, b): return float(a["d"]) > float(b["d"]))

	print("=== 离中轴最远的 8 件（相对整体水平的倍数）===")
	var n := 0
	for r in rows:
		if n >= 8:
			break
		n += 1
		print("  [%d] d/horiz = %.3f ｜ 跨度 %.4f ｜ 高 %.4f ｜ skin=%s ｜ y %.3f"
			% [r["path"].hash() & 0xFFFF, float(r["d"]) / horiz_diag, r["span"], r["h"],
				str(r["skin"]), r["ctr"].y])
		print("      %s   (parent=%s)" % [r["path"], r["par"]])

	print("")
	print("=== 最小 5 件（按跨度）===")
	var by_sz: Array = rows.duplicate()
	by_sz.sort_custom(func(a, b): return a["span"] < b["span"])
	for i in mini(5, by_sz.size()):
		var r: Dictionary = by_sz[i]
		print("  跨度 %.4f ｜ 高 %.4f ｜ skin=%s ｜ ctr=(%.4f, %.4f, %.4f)"
			% [r["span"], r["h"], str(r["skin"]), r["ctr"].x, r["ctr"].y, r["ctr"].z])
		print("      %s" % r["path"])

	print("")
	print("=== 无蒙皮件（skin == null）===")
	var noskin := 0
	for r in rows:
		if not bool(r["skin"]):
			noskin += 1
			if noskin <= 12:
				print("  ctr=(%.4f, %.4f, %.4f) 跨度 %.4f ｜ %s"
					% [r["ctr"].x, r["ctr"].y, r["ctr"].z, r["span"], r["path"]])
	print("  合计无蒙皮 %d / %d" % [noskin, rows.size()])
	print("")
	print("VERDICT: N44-STRAY-DONE")
	get_tree().quit(0)


func _first_skeleton(n: Node) -> Skeleton3D:
	for c in n.find_children("*", "Skeleton3D", true, false):
		return c as Skeleton3D
	return null


func _v(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]
