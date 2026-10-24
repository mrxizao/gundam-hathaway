extends Node
## 读数探针：**墩 / 塔族在平面（XZ）上的最小间距与重叠深度**（2026-09-28，B6 前置）。
##
## ## 为什么要它
## v3 §R 第 2 条与达沃 v2 §7 第 1 条都是同一个悬案：
## 「**单轨墩与环线墩径向重叠 110 m**，靠方位错开 ⇒ **必须出图核**」。
## 而代码注释（`world_builder.gd:7009`）写的是
## 「改成 `i % 6 == 3` ⇒ `11.25° + 22.5k`，**最小角距 2.5°**（在 `R = 27 600` 上 = **1 204 m**）」——
## ⚠️ **那是估的**：`11.25 + 22.5k` 对 `20m` 的最小差是 **1.25°**（k=3 ⇒ 78.75 vs 80），
## 不是 2.5° ⇒ 弧长 **602 m**，**估大了一倍**。结论（不撞）侥幸没错，数是错的。
## 这类"注释里的数当结论"是本工程最贵的一种错 ⇒ **一律从建好的场景读回来**。
##
## ## 为什么可以 `--headless`
## 本探针只读 `_add_box()` 造的 **StaticBody3D 节点变换**（`global_transform` + `mesh.get_aabb()`），
## **不碰 `MultiMesh.get_instance_transform()`** —— dummy 渲染器只让后者回单位变换。
## 所以这里 headless 的读数是**真的**（对比 `_r6_road_probe` / `_r8_davao_probe` 必须带窗口）。
##
##   godot --headless --path <工程> res://tools/_r10_pier_overlap_probe.tscn -- --city=oenb
##   godot --headless --path <工程> res://tools/_r10_pier_overlap_probe.tscn -- --city=davao
##
## ## 判据本身（四个坑，都踩过一遍）
## 1. **不能用 `_box_aabb` 的四角**：它给的是**轴对齐**包围盒，120×600 的墩一转 45°
##    就变成 509×509 ⇒ **凭空造出重叠**。必须用 `global_transform` 把网格 AABB 的 8 个角
##    **真变换**再投到 XZ（旋转矩形）。
## 2. **"单件尺寸"不能读轴对齐跨度**（同上一条的镜像错误）：`600` 那个数只在 yaw = 0 时
##    才等于跨度。这里改读**多边形自己的两条边长**（自洽、与 yaw 无关）。
## 3. **`ViaductPier*` 一个族里混着两类**（环线 + 三条运河走线）⇒ 算"单轨 vs 环线"必须
##    **先分桶**。⚠️ 按 `|r − via_ring_r| < 1 500` 分会**把运河线墩收进来**
##    （`x = −26 162.5` 那条线在 `z ≈ 0` 处 `r = 26 162`，离 27 600 只有 1 438）——
##    实测那样分会读出"环线 16 根"，而真的环线墩**在半径 27 573.7 上**（弦心，不是弧上）。
##    ⇒ 判据改成 `|r − rr·cos(π/segs)| < 5 m`，并**自检**（这批的方位角必须全 ≡ 2.5°+20k）。
## 4. **相交与相离要给同一个数轴**：相交 ⇒ 返回**负的最小平移距离**；相离 ⇒ 正边距。
##    只报"0 = 没撞"会把"贴死"和"差 400 m"混成一样。
##
## 同时把每个墩的**平面四角**写到 `<工作区>/_pier_dump_<city>.txt`，供 Python 画俯视核图。

const FAMS: Array[String] = [
	"ViaductPier", "CanalBridgePier", "BridgeRampPier", "MonorailPylon",
	"BridgePylon",
]

const OUT_DIR := "C:/Users/MSIPC/WorkBuddy/2026-09-27-13-34-43"

var _w: WorldBuilder
var _city := "oenb"
var _dump: Array[String] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--city="):
			_city = a.substr(7)
	var m: MapDef = MapDef.davao() if _city == "davao" else MapDef.oenbelli()
	_w = WorldBuilder.new()
	add_child(_w)
	await get_tree().physics_frame
	_w.apply_map(m)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# ---------------------------------------------------------------- 收族
	var fam: Dictionary = {}
	for f in FAMS:
		fam[f] = []
	var at_n := 0
	for b: Node in _w.find_children("*", "StaticBody3D", true, false):
		var nm := String(b.name)
		if nm.begins_with("@"):
			at_n += 1
		for f in FAMS:
			if nm.begins_with(f):
				var arr: Array = fam[f]
				arr.append(b)
				break

	# ⚠️ `rect[f]` 与 `nmap[f]` **必须同长同序**（取矩形时可能丢掉退化件 ⇒ 不能另开一轮数名字）
	var rect: Dictionary = {}
	var nmap: Dictionary = {}
	for f in FAMS:
		var rs: Array = []
		var ns: Array = []
		for b: Node in fam[f]:
			var p := _rect_xz(b)
			if p.size() >= 3:
				rs.append(p)
				ns.append(String(b.name))
		rect[f] = rs
		nmap[f] = ns
		for i in rs.size():
			var c := _centroid(rs[i])
			var line := "%s|%s|%s|%.1f|%.1f|0" % [_city, f, String(ns[i]), c.x, c.y]
			for v: Vector2 in rs[i]:
				line += "|%.1f|%.1f" % [v.x, v.y]
			_dump.append(line)

	print("==== 0 · 城 ====")
	print("  %s（gundam 工程）" % m.name_cn)
	print("  ⚠️ 名字被引擎改成 `@…` 的 StaticBody3D = **%d**（应为 0；非 0 说明又有人在同一个"
		% at_n + "父节点下重名了）")

	print("")
	print("==== 1 · 族清册（**按名字精确数**）====")
	print("  | 族 | 个数 | 径向带 min…max (m) | 单件平面尺寸（多边形真边长） | 长边方位 |")
	print("  |---|---|---|---|---|")
	for f in FAMS:
		var rs: Array = rect[f]
		if rs.is_empty():
			print("  | `%s*` | **0** | — | — | — |" % f)
			continue
		var rlo := 1.0e18
		var rhi := -1.0e18
		for p: PackedVector2Array in rs:
			for v: Vector2 in p:
				var rv: float = v.length()
				rlo = minf(rlo, rv)
				rhi = maxf(rhi, rv)
		var sd := _sides(rs[0])
		print("  | `%s*` | %d | %.0f … %.0f | %.0f × %.0f m | %s |" % [
			f, rs.size(), rlo, rhi, sd.y, sd.x, _dir(rs[0], sd.y)])

	# ---------------------------------------------------------------- 两两
	print("")
	print("==== 2 · 族两两：**平面最小边距**（负 = 相交，值是重叠深度）====")
	print("  | A × B | 最小边距 | 最近的一对 | 相交对数 | 最深 |")
	print("  |---|---|---|---|---|")
	for i in FAMS.size():
		for j in range(i + 1, FAMS.size()):
			var A: String = FAMS[i]
			var B: String = FAMS[j]
			var r := _pair(rect[A], nmap[A], rect[B], nmap[B])
			if r.is_empty():
				continue
			print("  | `%s` × `%s` | **%.1f m** | %s / %s | %d | %.1f |" % [
				A, B, float(r["gap"]), String(r["na"]), String(r["nb"]),
				int(r["hits"]), float(r["depth"])])

	# ---------------------------------------------------------------- 专项
	print("")
	print("==== 3 · 专项 ①：环线墩 vs 单轨墩（**v3 §R 第 2 条**）====")
	_ring_vs_monorail(m, rect, nmap)

	print("")
	print("==== 4 · 专项 ②：墩族 vs **楼体占地**（幽灵碰撞）====")
	_pier_in_building(rect, nmap)

	print("")
	print("==== 5 · 专项 ③：**墩间距**（环线为什么看着像「飘着」）====")
	_ring_spacing_sec(m, rect, nmap)

	# ---------------------------------------------------------------- 落盘
	var path := "%s/_pier_dump_%s.txt" % [OUT_DIR, _city]
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh == null:
		print("  ⚠️ 写不了 `%s`" % path)
	else:
		for line in _dump:
			fh.store_line(line)
		fh.close()
		print("")
		print("  ⇒ 平面四角已落盘：`%s`（%d 行）" % [path, _dump.size()])
	get_tree().quit()


## 专项 ①：环线墩（`ViaductPier*` 里**在环线上**的那批）对单轨墩。
func _ring_vs_monorail(m: MapDef, rect: Dictionary, nmap: Dictionary) -> void:
	var shape: Dictionary = WorldBuilder.CITY_SHAPE[m.city_layout]
	var rr := float(shape.via_ring_r)
	var segs := float(WorldBuilder.CITY_VIA_RING_SEGS)
	if rr <= 0.0:
		print("  本图 `via_ring_r = 0` ⇒ 没有环线，跳过")
		return
	# ⚠️ 环线墩**不在弧上**：`_append_via_seg()` 把墩放在**弦的中点** ⇒ 半径
	# `rr·cos(π/segs)`（72 段 ⇒ 27 573.7，比 27 600 少 26 m）。
	# 按 `|r − rr| < 1 500` 分会把 `x = −26 162.5` 那条运河线（`z≈0` 处 r = 26 162）收进来。
	var chord_r: float = rr * cos(PI / segs)
	var mon: Array = rect["MonorailPylon"]
	var vp: Array = rect["ViaductPier"]
	if mon.is_empty() or vp.is_empty():
		print("  ⚠️ `MonorailPylon` = %d / `ViaductPier` = %d ⇒ 本图没有这一对"
			% [mon.size(), vp.size()])
		return
	var vpn: Array = nmap["ViaductPier"]
	var monn: Array = nmap["MonorailPylon"]
	var ring: Array = []
	var ringn: Array = []
	var other := 0
	for i in vp.size():
		var r := _centroid(vp[i]).length()
		if absf(r - chord_r) < 5.0:
			ring.append(vp[i])
			ringn.append(vpn[i])
		else:
			other += 1
	print("  环线墩判据：`|r − rr·cos(π/%d)| < 5 m`（rr = %.0f ⇒ 弦心半径 %.1f m）"
		% [int(segs), rr, chord_r])
	print("  `ViaductPier*` 共 %d 根 ⇒ **环线 %d 根** ＋ 走线（3 条运河线）%d 根"
		% [vp.size(), ring.size(), other])
	# 自检：环线墩的方位角必须全 ≡ 2.5° + step·k（`_append_via_seg` 取的是**弦中点**，
	# 而每段跨 5°）⇒ `step = 5° × RING_PIER_EVERY`。
	# ⚠️ 2026-09-28 v3 · B6：这里原先是**硬写的 `4.0`** —— `RING_PIER_EVERY` 一从 4 改 2
	# 就整块自检**假红**（`mod 20°` 下 `2.5+10k` 的偶数项根本不是 2.5）。**必须读常量**。
	var exp_step: float = 360.0 / segs * float(WorldBuilder.CITY_VIA_RING_PIER_EVERY)
	var bad := 0
	var az_list: Array[String] = []
	for p: PackedVector2Array in ring:
		var c := _centroid(p)
		var az := fposmod(rad_to_deg(atan2(c.y, c.x)), exp_step)
		if absf(az - 2.5) > 0.05:
			bad += 1
		az_list.append("%.2f" % az)
	print("  **自检**：环线墩方位角 mod %.0f° 应恒为 2.5° ⇒ 不合格 **%d** 根；前 6 个：%s"
		% [exp_step, bad, str(az_list.slice(0, 6))])
	var expect_n: int = int(WorldBuilder.CITY_VIA_RING_SEGS \
		/ WorldBuilder.CITY_VIA_RING_PIER_EVERY)
	print("  ⚠️ `CITY_VIA_RING_SEGS / EVERY` = %d ⇒ 理论 %d 根；实测 %d 根"
		% [expect_n, expect_n, ring.size()]
		+ "（⚠️ B6 之后差额应恒为 **0**：避楼已改成**沿弦挪墩**，只有整条弦都压楼才会丢）")
	print("  单轨墩 %d 根（`CITY_MONORAIL_R` = %.0f m）" % [
		mon.size(), WorldBuilder.CITY_MONORAIL_R])

	var r2 := _pair(ring, ringn, mon, monn)
	if r2.is_empty():
		print("  ⚠️ 空")
		return
	print("  **环线墩 × 单轨墩：最小边距 %.1f m**（%s × %s）" % [
		float(r2["gap"]), String(r2["na"]), String(r2["nb"])])
	print("  相交对数 **%d**（最深 %.1f m）" % [int(r2["hits"]), float(r2["depth"])])
	print("  最近那对的心距 = **%.1f m**，两只的方位角 = **%.3f°** vs **%.3f°**"
		% [float(r2["cd"]), float(r2["aa"]), float(r2["ab"])])

	# 全域最小角距（不只看最近那一对）
	var aa: Array[float] = []
	for p: PackedVector2Array in ring:
		aa.append(rad_to_deg(atan2(_centroid(p).y, _centroid(p).x)))
	var ba: Array[float] = []
	for p: PackedVector2Array in mon:
		ba.append(rad_to_deg(atan2(_centroid(p).y, _centroid(p).x)))
	var best := 1.0e18
	var pair := Vector2.ZERO
	var best_i := -1
	var best_j := -1
	for i in ba.size():
		for j in aa.size():
			var d := absf(ba[i] - aa[j])
			d = minf(d, 360.0 - d)
			if d < best:
				best = d
				pair = Vector2(ba[i], aa[j])
				best_i = i
				best_j = j
	print("  全域：单轨 %d 个方位 × 环线墩 %d 个方位的**最小角距 %.3f°**"
		% [ba.size(), aa.size(), best] + "（%.3f° vs %.3f° ⇒ 弧长 **%.1f m**）" % [
			pair.x, pair.y, deg_to_rad(best) * rr])
	print("      这一对就是 %s × %s"
		% [String(monn[best_i]), String(ringn[best_j])])
	print("  切向半宽：单轨 %.0f + 环线墩 %.0f = %.0f m ⇒ 需要 > %.0f m；弧长 %.1f ⇒ **余 %.1f m**"
		% [_sides(mon[0]).x * 0.5, WorldBuilder.CITY_VIA_PIER_W * 0.5,
			_sides(mon[0]).x * 0.5 + WorldBuilder.CITY_VIA_PIER_W * 0.5,
			_sides(mon[0]).x * 0.5 + WorldBuilder.CITY_VIA_PIER_W * 0.5,
			deg_to_rad(best) * rr, deg_to_rad(best) * rr
			- _sides(mon[0]).x * 0.5 - WorldBuilder.CITY_VIA_PIER_W * 0.5])
	# 径向：这是"110 m 重叠"那个说法的正主
	var mr := _radial(mon)
	var vr := _radial(ring)
	print("  径向带：单轨墩 **%.0f … %.0f** / 环线墩 **%.0f … %.0f** ⇒ 重叠 **%.0f m**"
		% [mr.x, mr.y, vr.x, vr.y, maxf(0.0, minf(mr.y, vr.y) - maxf(mr.x, vr.x))])
	print("  ⇒ **径向重叠不是缺陷**（切向已经错开 %.1f m）：判定用**边距**（%.1f m），不用带重叠"
		% [deg_to_rad(best) * rr, float(r2["gap"])])


## 专项 ②：每个墩是否落在**楼体占地**里。楼体按 XZ 多边形（保守 —— 越界只会多收）。
func _pier_in_building(rect: Dictionary, nmap: Dictionary) -> void:
	var boxes: Array = []
	var bnm: Array = []
	var bh: Array = []
	for b: Node in _w.find_children("*", "StaticBody3D", true, false):
		var nm := String(b.name)
		if not (nm.begins_with("Podium_") or nm.begins_with("Tower_")
				or nm.begins_with("Setback_")):
			continue
		var mi := b.get_child(0) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var p := _rect_xz(b)
		if p.size() >= 3:
			boxes.append(p)
			bnm.append(nm)
			bh.append(mi.scale.y)
			# 楼体也落盘（俯视核图的**背景**）：`meta` 那一位放楼高。
			var bc := _centroid(p)
			var bl := "%s|BUILDING|%s|%.1f|%.1f|%.0f" % [_city, nm, bc.x, bc.y, mi.scale.y]
			for v: Vector2 in p:
				bl += "|%.1f|%.1f" % [v.x, v.y]
			_dump.append(bl)
	print("  楼体占地 %d 块（按 XZ 多边形，**保守**：轴对齐的塔楼多为方形，误差小）"
		% boxes.size())
	for f in FAMS:
		var rs: Array = rect[f]
		if rs.is_empty():
			continue
		var ns: Array = nmap[f]
		var hit := 0
		var ex: Array[String] = []
		var hmax := 0.0
		var hmin := 1.0e18
		for i in rs.size():
			for j in boxes.size():
				if _poly_gap(rs[i], boxes[j]) > 0.0:
					continue
				hit += 1
				hmax = maxf(hmax, bh[j])
				hmin = minf(hmin, bh[j])
				if ex.size() < 3:
					ex.append("%s∈%s(%.0f m)" % [String(ns[i]), String(bnm[j]), bh[j]])
				break
		var extra := ""
		if hit > 0:
			var top: float = WorldBuilder.CITY_MONORAIL_Y + 60.0
			extra = "  楼高 %.0f…%.0f m；墩顶 %.0f m ⇒ %s" % [
				hmin, hmax, top,
				"**墩被整根埋进楼里**" if hmax > top else "墩从楼里穿出"]
		print("  `%s*` %d 根 ⇒ **在楼内 %d**（%.1f%%）%s" % [
			f, rs.size(), hit, 100.0 * float(hit) / float(rs.size()), extra])
		if hit > 0:
			print("      %s" % " / ".join(ex))


## 专项 ③：把**环状**墩族按方位角排序，量相邻墩的**弧距** ⇒ 最长无墩跨。
## 起因：`CITY_VIA_PIER_EVERY = 1`（走线每 4 025 m 一根）而
## `CITY_VIA_RING_PIER_EVERY` 曾是 `4`（环线每 **4 段 = 9 632 m** 一根）——
## **两条走线的墩距差 2.4 倍**，而且环线还要再被"避楼"挤掉一批。
## ⚠️ 2026-09-28 v3 · B6：`4 → 2`（名义墩距 4 817 m），且**避楼从"丢墩"改成"挪墩"** ⇒
## 环线墩**不再凭空少一批**；这个专项现在的用途变成"验挪墩没把墩距拉坏"。
func _ring_spacing_sec(m: MapDef, rect: Dictionary, nmap: Dictionary) -> void:
	var shape: Dictionary = WorldBuilder.CITY_SHAPE[m.city_layout]
	var rr := float(shape.via_ring_r)
	var segs := float(WorldBuilder.CITY_VIA_RING_SEGS)
	if rr > 0.0:
		var chord_r: float = rr * cos(PI / segs)
		var subs: Array = []
		var subn: Array = []
		var vp: Array = rect["ViaductPier"]
		var vpn: Array = nmap["ViaductPier"]
		for i in vp.size():
			if absf(_centroid(vp[i]).length() - chord_r) < 5.0:
				subs.append(vp[i])
				subn.append(vpn[i])
		var nominal: float = TAU * rr * float(WorldBuilder.CITY_VIA_RING_PIER_EVERY) / segs
		print("  环线：段长 %.0f m × `RING_PIER_EVERY %d` ⇒ **名义墩距 %.0f m**"
			% [TAU * rr / segs, WorldBuilder.CITY_VIA_RING_PIER_EVERY, nominal])
		_spacing(subs, subn, rr, "环线墩")
	print("  ⚠️ 单轨：96 段 / 每 6 段一根 ⇒ **名义墩距 %.0f m**"
		% (TAU * float(WorldBuilder.CITY_MONORAIL_R) / 96.0 * 6.0))
	_spacing(rect["MonorailPylon"], nmap["MonorailPylon"],
		float(WorldBuilder.CITY_MONORAIL_R), "单轨墩")


## 按方位角排序后量相邻弧距。`rr` 用**自己的半径**（弦心/弧上差 26 m，对间距无影响）。
func _spacing(rs: Array, ns: Array, rr: float, label: String) -> void:
	if rs.size() < 2:
		print("  %s 少于 2 根，量不了间距" % label)
		return
	var az: Array[float] = []
	for p: PackedVector2Array in rs:
		var c := _centroid(p)
		az.append(fposmod(rad_to_deg(atan2(c.y, c.x)), 360.0))
	var idx: Array[int] = []
	for i in az.size():
		idx.append(i)
	for a in range(idx.size()):
		for b in range(idx.size() - 1 - a):
			if az[idx[b]] > az[idx[b + 1]]:
				var t := idx[b]
				idx[b] = idx[b + 1]
				idx[b + 1] = t
	var gaps: Array[float] = []
	var gmax := -1.0
	var gi := 0
	for k in idx.size():
		var d := az[idx[(k + 1) % idx.size()]] - az[idx[k]]
		if d <= 0.0:
			d += 360.0
		var arc := deg_to_rad(d) * rr
		gaps.append(arc)
		if arc > gmax:
			gmax = arc
			gi = k
	var sorted_g := gaps.duplicate()
	sorted_g.sort()
	print("  %s %d 根 ⇒ 弧距 min %.0f / 中位 %.0f / **max %.0f m**"
		% [label, rs.size(), sorted_g[0], sorted_g[sorted_g.size() / 2], gmax])
	print("      最长那一跨：%s → %s（%.0f m）"
		% [String(ns[idx[gi]]), String(ns[idx[(gi + 1) % idx.size()]]), gmax])


# ==================================================================== 工具
## 把 `_add_box()` 那个**旋转矩形**的 XZ 四角读出来（真变换，不是轴对齐包围盒）。
func _rect_xz(b: Node) -> PackedVector2Array:
	var mi := b.get_child(0) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return PackedVector2Array()
	var ab := mi.mesh.get_aabb()
	var pts: Array[Vector2] = []
	for i in 8:
		var lp := ab.position + Vector3(
			ab.size.x * float(i & 1),
			ab.size.y * float((i >> 1) & 1),
			ab.size.z * float((i >> 2) & 1))
		var q := mi.global_transform * lp
		var v := Vector2(q.x, q.z)
		var dup := false
		for e: Vector2 in pts:
			if e.distance_to(v) < 0.5:
				dup = true
				break
		if not dup:
			pts.append(v)
	if pts.size() < 3:
		return PackedVector2Array()
	var c := Vector2.ZERO
	for e: Vector2 in pts:
		c += e
	c /= float(pts.size())
	# 按绕质心的角度排成**凸序**（矩形一定是凸的）
	for a in range(pts.size()):
		for b2 in range(pts.size() - 1 - a):
			var p1 := pts[b2]
			var p2 := pts[b2 + 1]
			if atan2(p1.y - c.y, p1.x - c.x) > atan2(p2.y - c.y, p2.x - c.x):
				pts[b2] = p2
				pts[b2 + 1] = p1
	return PackedVector2Array(pts)


## 多边形的**两条真边长**：返回 `Vector2(短边, 长边)`（与 yaw 无关）。
func _sides(p: PackedVector2Array) -> Vector2:
	var l0 := p[0].distance_to(p[1])
	var l1 := p[1].distance_to(p[2])
	if l0 > l1:
		var t := l0
		l0 = l1
		l1 = t
	return Vector2(l0, l1)


## 长边相对 +X 的方位（度）。`long_len` 由 `_sides()` 给。
func _dir(p: PackedVector2Array, long_len: float) -> String:
	for i in p.size():
		if absf(p[i].distance_to(p[(i + 1) % p.size()]) - long_len) < 0.5:
			var d := p[(i + 1) % p.size()] - p[i]
			var az := rad_to_deg(atan2(d.y, d.x))
			return "%.1f°" % fposmod(az, 180.0)
	return "—"


func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v: Vector2 in p:
		c += v
	return c / float(p.size())


## 一族多边形的**径向带**（`Vector2(min, max)`，按各族自己的「心」算 —— 这里都是图心）。
func _radial(rs: Array) -> Vector2:
	var lo := 1.0e18
	var hi := -1.0e18
	for p: PackedVector2Array in rs:
		for v: Vector2 in p:
			var r: float = v.length()
			lo = minf(lo, r)
			hi = maxf(hi, r)
	return Vector2(lo, hi)


## 两个族的最小边距：负 = 相交（值是**最小平移距离**）。
func _pair(ra: Array, na: Array, rb: Array, nb: Array) -> Dictionary:
	if ra.is_empty() or rb.is_empty():
		return {}
	var best := 1.0e18
	var bi := 0
	var bj := 0
	var hits := 0
	var depth := 0.0
	for i in ra.size():
		for j in rb.size():
			var g := _poly_gap(ra[i], rb[j])
			if g <= 0.0:
				hits += 1
				depth = maxf(depth, -g)
			if g < best:
				best = g
				bi = i
				bj = j
	var ca := _centroid(ra[bi])
	var cb := _centroid(rb[bj])
	return {
		"gap": best, "na": String(na[bi]), "nb": String(nb[bj]),
		"hits": hits, "depth": depth, "cd": ca.distance_to(cb),
		"aa": rad_to_deg(atan2(ca.y, ca.x)), "ab": rad_to_deg(atan2(cb.y, cb.x)),
	}


## 两凸多边形的间距：相交 ⇒ 负的最小平移距离；相离 ⇒ 最小边距。
func _poly_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var pen := _poly_penetration(a, b)
	if pen > 0.0:
		return -pen
	return minf(_min_cross(a, b), _min_cross(b, a))


## SAT：返回最小重叠深度（不相交 = 0）。
func _poly_penetration(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var depth := 1.0e18
	var polys: Array = [a, b]
	for poly: PackedVector2Array in polys:
		for i in poly.size():
			var e := poly[(i + 1) % poly.size()] - poly[i]
			var n := Vector2(-e.y, e.x)
			if n.length_squared() < 1.0e-9:
				continue
			n = n.normalized()
			var amin := 1.0e18
			var amax := -1.0e18
			for p: Vector2 in a:
				var d := p.dot(n)
				amin = minf(amin, d)
				amax = maxf(amax, d)
			var bmin := 1.0e18
			var bmax := -1.0e18
			for p: Vector2 in b:
				var d := p.dot(n)
				bmin = minf(bmin, d)
				bmax = maxf(bmax, d)
			var ov := minf(amax, bmax) - maxf(amin, bmin)
			if ov <= 0.0:
				return 0.0
			depth = minf(depth, ov)
	return depth


func _min_cross(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best := 1.0e18
	for v: Vector2 in a:
		for j in b.size():
			best = minf(best, _seg_dist(v, b[j], b[(j + 1) % b.size()]))
	return best


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l := ab.length_squared()
	if l < 1.0e-9:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l, 0.0, 1.0)
	return p.distance_to(a + ab * t)
