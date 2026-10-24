extends Node
## **B6-B 定点测量**：环线墩 / 走线墩落在楼体占地里时，**沿弦挪多远才能出楼**？
##
## ## 为什么必须先量
## `_append_via_seg()` 的 D3 判据是 `_city_via_lot_top(mid) > 0` ⇒ 旧写法**丢墩**。
## 改成"挪墩"就得选一个**限幅**，而这个限幅被两条约束夹住：
## | 约束 | 来源 | 上限 |
## |---|---|---|
## | 墩要保持在**桥面下方** | 桥面宽 420 ⇒ 半宽 210，墩宽 120 ⇒ 半径 60 | 沿弦 ≤ 半段；横向 ≤ 150 |
## | 墩不能挪到**单轨墩**身上 | P1 的半步错开 ⇒ 固有最小角距 **1.25°（602 m）** | 沿弦 ≤ ~480 m |
## ⇒ 能挪多远，是**量出来的**，不是估出来的。本探针把"每个被挤掉的墩位
##    离最近空地有多远"逐个打出来（沿弦 + 横向两个方向各扫一遍）。
##
## 只用 `_city_via_lot_top()`（**唯一真源**）—— 不重建任何几何判断。
##
##   godot --headless --path <工程> res://tools/_b6_pier_slide_probe.tscn
##   godot --headless --path <工程> res://tools/_b6_pier_slide_probe.tscn -- --city=davao

var _w: WorldBuilder
var _map: MapDef


func _ready() -> void:
	var city := "oenb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--city="):
			city = a.substr(7)
	_map = MapDef.davao() if city == "davao" else MapDef.oenbelli()
	_w = WorldBuilder.new()
	add_child(_w)
	await get_tree().physics_frame
	_w.apply_map(_map)
	await get_tree().physics_frame

	var shape: Dictionary = WorldBuilder.CITY_SHAPE[_map.city_layout]
	print("==== B6-B 墩位移测量 · %s ====" % _map.name_cn)
	print("  沿弦限幅：半段 / 单轨安全（1.25° − 0.5°）× R；横向限幅：桥面半宽 − 墩半宽")
	var rows: Array = []
	# ---- ① 环线墩 ----
	var rr := float(shape.via_ring_r)
	if rr > 0.0:
		var segs: int = WorldBuilder.CITY_VIA_RING_SEGS
		var step_deg := 360.0 / float(segs)
		var every: int = WorldBuilder.CITY_VIA_RING_PIER_EVERY
		var hlen := 2.0 * rr * sin(PI / float(segs))
		print("")
		print("── 环线：R %.0f / %d 段 / 每 %d 段一根 ⇒ %d 根；弦长 %.1f m"
			% [rr, segs, every, segs / every, hlen])
		for i in range(0, segs, every):
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var p0 := Vector2(cos(a0) * rr, sin(a0) * rr)
			var p1 := Vector2(cos(a1) * rr, sin(a1) * rr)
			var mid := (p0 + p1) * 0.5
			rows.append(_scan("环线", i, mid, p0, p1, hlen))
	# ---- ② 走线墩 ----
	print("")
	print("── 走线（`via_lines`）：`PIER_EVERY = %d`" % WorldBuilder.CITY_VIA_PIER_EVERY)
	var cb: float = WorldBuilder.CITY_CBLOCK
	for def: Array in shape.via_lines:
		var along_z := String(def[0]) == "z"
		var pos := float(def[1])
		var t0 := float(def[2])
		var t1 := float(def[3])
		var n := maxi(1, int(round(absf(t1 - t0) / cb)))
		var stp := (t1 - t0) / float(n)
		for i in n:
			if i % WorldBuilder.CITY_VIA_PIER_EVERY != 0:
				continue
			var ta := t0 + stp * float(i)
			var tb := t0 + stp * float(i + 1)
			var pa := Vector2(pos, ta) if along_z else Vector2(ta, pos)
			var pb := Vector2(pos, tb) if along_z else Vector2(tb, pos)
			rows.append(_scan("走线", i, (pa + pb) * 0.5, pa, pb, (pb - pa).length()))
	# ---- ③ 汇总 ----
	print("")
	print("── 汇总 ──")
	var tot := rows.size()
	var inside := 0
	var by_a := {}
	var by_l := {}
	var both_fail := 0
	var rows2: Array = []
	for r: Array in rows:
		if not bool(r[0]):
			continue
		inside += 1
		rows2.append(r)
		var a := float(r[1])
		var l := float(r[2])
		var ka := "沿弦可挪" if a >= 0.0 else "沿弦挪不出"
		by_a[ka] = int(by_a.get(ka, 0)) + 1
		var kl := "横向可挪" if l >= 0.0 else "横向挪不出"
		by_l[kl] = int(by_l.get(kl, 0)) + 1
		if a < 0.0 and l < 0.0:
			both_fail += 1
	print("  墩位 %d 个 ⇒ **落进楼体占地的 %d 个**（%.1f%%）"
		% [tot, inside, 100.0 * float(inside) / float(maxi(tot, 1))])
	print("  沿弦：%s ；横向：%s" % [str(by_a), str(by_l)])
	print("  ⚠️ **两个方向都挪不出去的 = %d 个 / %d**（= 旧写法会**丢掉的**）"
		% [both_fail, inside])
	rows2.sort_custom(func(a, b):
		if float(a[1]) < 0.0 and float(b[1]) >= 0.0:
			return false
		if float(b[1]) < 0.0 and float(a[1]) >= 0.0:
			return true
		return float(a[1]) < float(b[1]))
	print("  逐个（沿弦最小位移 / 横向最小位移 / 限幅内可用点数；−1 = 挪不出）：")
	for r: Array in rows2:
		print("     %-6s 段 %+3d  沿弦 %8.1f / 横向 %8.1f   （可用点 %3d / %3d，弦长 %.0f）"
			% [String(r[5]), int(r[6]), float(r[1]), float(r[2]),
				int(r[3]), int(r[4]), float(r[7])])
	# ---- ④ 决定性一问：这些"落楼"到底是**带子的判据**造成的还是**墩自己**造成的 ----
	#
	# `_city_via_lot_top()` 的 `reach = CITY_VIA_W / 2 = 210` —— 它自己的文档写得明白：
	# "判据是**桥自身的 footprint**（420 宽的带子），**不是所在的那一整格**"。
	# 但**墩**只有 `CITY_VIA_PIER_W = 120` 宽（半宽 60）⇒ 拿带子的 `reach` 判墩，
	# 等于给每根墩凭空加了一圈 150 m 的余量。两者差多少，是量出来的。
	print("")
	print("── 决定性一问：把 `reach` 换成**墩自己的半宽**（%.0f m）会怎样 ──"
		% (WorldBuilder.CITY_VIA_PIER_W * 0.5))
	print("  `reach` 来自调用方：带子 210 / 墩 60；地块半宽 %.1f m"
		% (WorldBuilder.CITY_CBLOCK * WorldBuilder.CITY_FILL * 0.5))
	var at_all := 0
	var at_deck := 0
	var at_pier := 0
	var detail: Array[String] = []
	for r: Array in rows:
		var nm := String(r[5])
		var idx := int(r[6])
		var p := Vector2(float(r[8]), float(r[9]))
		at_all += 1
		var d := _near_lots(p.x, p.y, WorldBuilder.CITY_VIA_W * 0.5)
		var q := _near_lots(p.x, p.y, WorldBuilder.CITY_VIA_PIER_W * 0.5)
		if not d.is_empty():
			at_deck += 1
		if not q.is_empty():
			at_pier += 1
		if not d.is_empty() and detail.size() < 6:
			detail.append("     %s 段 %+3d @ (%.0f, %.0f)：带子口径命中 %s；墩口径命中 %s"
				% [nm, idx, p.x, p.y, str(d), str(q)])
	print("  墩位 %d 个：**按带子（reach 210）判落楼 = %d 个**；**按墩自己（reach 60）判 = %d 个**"
		% [at_all, at_deck, at_pier])
	for s: String in detail:
		print(s)
	get_tree().quit(0)


## 复刻 `_city_via_lot_top()` 的命中集合，但 `reach` 由调用方给 ⇒ 能分辨
## "撞楼的是**桥面带子**"还是"**墩自己**"。
func _near_lots(x: float, z: float, reach: float) -> Array[String]:
	var half: float = WorldBuilder.CITY_CBLOCK * WorldBuilder.CITY_FILL * 0.5
	var cb: float = WorldBuilder.CITY_CBLOCK
	var out: Array[String] = []
	var gx0 := int(floorf((x - reach - half) / cb))
	var gx1 := int(floorf((x + reach + half) / cb))
	var gz0 := int(floorf((z - reach - half) / cb))
	var gz1 := int(floorf((z + reach + half) / cb))
	for gx in range(gx0, gx1 + 1):
		for gz in range(gz0, gz1 + 1):
			var key := Vector2i(gx, gz)
			if not _w._city_lot_h.has(key):
				continue
			var cx := (float(gx) + 0.5) * cb
			var cz := (float(gz) + 0.5) * cb
			if absf(cx - x) < reach + half and absf(cz - z) < reach + half:
				out.append("(%d,%d)h%.0f" % [gx, gz, float(_w._city_lot_h[key])])
	return out
	get_tree().quit(0)


## 扫描一个墩位：沿弦 ±`hlen/2`、横向 ±150，找**位移最小**的空地。
## 返回 `[是否落楼, 沿弦最小位移或 −1, 横向最小位移或 −1, 沿弦可用点数, 横向可用点数, 族名, 段号, 弦长]`
## （"落楼"= `_city_via_lot_top() > 0`，它判的是"420 宽的桥面带子撞到楼"。
##  `−1` = 在限幅内**找不到**空地 ⇒ 挪不出去。）
func _scan(fam: String, idx: int, mid: Vector2, p0: Vector2,
		p1: Vector2, hlen: float) -> Array:
	var inside := _w._city_via_lot_top(mid.x, mid.y) > 0.0
	if not inside:
		return [false, 0.0, 0.0, 0, 0, fam, idx, hlen, mid.x, mid.y]
	var u := (p1 - p0).normalized()
	var lat := Vector2(-u.y, u.x)
	var lim_along: float = hlen * 0.5
	var lim_lat: float = WorldBuilder.CITY_VIA_W * 0.5 - WorldBuilder.CITY_VIA_PIER_W * 0.5
	var best_a := -1.0
	var n_a := 0
	var step := 25.0
	var k := 1
	while step * float(k) <= lim_along + 0.01:
		var d := step * float(k)
		for s: float in [-1.0, 1.0]:
			var q := mid + u * (s * d)
			if _w._city_via_lot_top(q.x, q.y) <= 0.0:
				n_a += 1
				if best_a < 0.0:
					best_a = d
		k += 1
	var best_l := -1.0
	var n_l := 0
	var k2 := 1
	while step * float(k2) <= lim_lat + 0.01:
		var d2 := step * float(k2)
		for s2: float in [-1.0, 1.0]:
			var q2 := mid + lat * (s2 * d2)
			if _w._city_via_lot_top(q2.x, q2.y) <= 0.0:
				n_l += 1
				if best_l < 0.0:
					best_l = d2
		k2 += 1
	return [true, best_a, best_l, n_a, n_l, fam, idx, hlen, mid.x, mid.y]
