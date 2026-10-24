extends Node
## 读数探针：**达沃（DAVAO）的城市现状**（2026-09-28）。
##
## ⚠️ 必须**带窗口**跑（不能 `--headless`）：要读 `MultiMesh.get_instance_transform()`，
##    dummy 渲染器下回读全是单位变换（见 `godot-headless-probe-shots` §十六）。
##
##   godot --path <工程> res://tools/_r8_davao_probe.tscn
##
## ## 为什么要它
## 用户要求"**达沃也做一份这样的重新设计文档**"。奥恩贝利那份的每一条判据都建立在
## **实测读数**上（66.4% / 21.5% 穿楼 / 0°×108）。达沃与奥恩贝利**共享同一批函数**
## （路网 / 高架 / 彩虹桥三个都不分图），只在 `CITY_SHAPE[1]` 里有另一套数 ——
## 所以"达沃的读数"不是"奥恩贝利的读数换个名字"，必须**重新量**。
##
## | # | 量什么 | 为什么 |
## |---|---|---|
## | 1 | 规划剖面：岛 / 海湾 / 运河 / 山 的**实际交界**（按米扫描） | 一切位置判据的底图 |
## | 2 | 桥**按图给**的那条线（`bridge_axis/pos/center/span`）落在**水还是陆** | ⚠️ 2026-09-28 B0 之后桥**不再**读全局 `CITY_BRIDGE_Z`；本节原来按旧常量采样，会报出"桥面 40 段全在陆上"这个**旧缺陷**（已改） |
## | 3 | 桥面段 ∩ 楼体 AABB | "高架穿插楼"的硬证据 |
## | 4 | 路网逐线缺段 + 缺口成因（逐段判，不取中点） | "道路断断续续" |
## | 5 | 高架段 ∩ 楼体 + 偏航角直方图 | "穿插" + "都是直的" |
## | 6 | 路灯杆 / 灯头实例数 | 达沃是**活城**（`city_lights = true`） |
## | 7 | 楼高分布 | "楼房高度" |

var _w: WorldBuilder
var _unit := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
const LAY := MapDef.CityLayout.DAVAO


func _ready() -> void:
	_w = WorldBuilder.new()
	add_child(_w)
	await get_tree().physics_frame
	_w.apply_map(MapDef.davao())
	await get_tree().physics_frame
	await get_tree().physics_frame

	var cb: float = WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	_section0_consts(cb)
	_section1_profile(cb)

	# ---- 楼体 AABB（先收，后面三节都用）----
	var bld: Array[AABB] = []
	var towers: Array[AABB] = []
	var heights: Array[float] = []
	for b: Node in _w.find_children("*", "StaticBody3D", true, false):
		var nm := String(b.name)
		if not (nm.begins_with("Podium_") or nm.begins_with("Tower_")
				or nm.begins_with("Setback_")):
			continue
		var mi := b.get_child(0) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ab := _box_aabb(mi.global_transform, mi.mesh.get_aabb())
		bld.append(ab)
		heights.append(mi.scale.y)
		if nm.begins_with("Tower_"):
			towers.append(ab)
	heights.sort()
	print("")
	print("==== 2 · 楼体 ====")
	print("  裙房 / 塔 / 退台 AABB 共 %d 个" % bld.size())
	if heights.size() > 0:
		print("  高度（mesh scale.y，米）：min %.0f  中位 %.0f  p90 %.0f  max %.0f" % [
			heights[0], heights[heights.size() / 2],
			heights[int(float(heights.size()) * 0.9)], heights[heights.size() - 1]])

	_section3_bridge(bld, cb)
	_section4_roads(cb)
	_section5_viaduct(bld, cb)
	_section6_lamps()
	_section2b_heights(towers, bld)
	_section7_spawn()
	_section8_landmarks()
	_section9_bridge_corridor(bld, cb)


## §8：**地标 vs 最高楼** —— 判据「针塔必须高过最高楼」得靠实测，不能靠注释。
func _section8_landmarks() -> void:
	print("")
	print("==== 8 · 地标高度（每个构件取 AABB 顶 y）====")
	var groups := {}
	for b: Node in _w.find_children("*", "StaticBody3D", true, false):
		var nm := String(b.name)
		var key := ""
		for pre: String in ["SandsTower", "SandsShip", "NeedleSeg", "NeedleSpire",
				"PortApron", "PortGantry", "Crane", "SandsKeel", "SandsParapet"]:
			if nm.begins_with(pre):
				key = pre
				break
		if key == "":
			continue
		var mi := b.get_child(0) as MeshInstance3D
		if mi == null:
			continue
		var ab := _box_aabb(mi.global_transform, mi.mesh.get_aabb())
		var top := ab.position.y + ab.size.y
		var g: Array = groups.get(key, [0, -1.0e18, 1.0e18])
		g[0] = int(g[0]) + 1
		g[1] = maxf(float(g[1]), top)
		g[2] = minf(float(g[2]), top)
		groups[key] = g
	var keys: Array = groups.keys()
	keys.sort()
	for k: String in keys:
		var g: Array = groups[k]
		print("  %-13s %3d 个 · 顶 y %.0f … %.0f m" % [k, int(g[0]), float(g[2]), float(g[1])])


## §7：出击点（`spawn_point(-95.0, spawn_r, alt)`）落在哪 —— 达沃的夜袭进场必须在海上。
func _section7_spawn() -> void:
	var r: float = float(WorldBuilder.CITY_SHAPE[LAY].spawn_r)
	var a := deg_to_rad(-95.0)
	var x := cos(a) * r
	var z := sin(a) * r
	print("")
	print("==== 7 · 出击点（方位 −95°）====")
	print("  r %.0f ⇒ (x %+.0f, z %+.0f)  r = %.0f" % [r, x, z, sqrt(x * x + z * z)])
	print("  该点：地形 %.1f m · 规划水 %s · 地形干燥 %s" % [
		WorldBuilder._city_landform(x, z, LAY),
		"是" if WorldBuilder.is_water_at(x, z, LAY) else "否",
		"是" if WorldBuilder.city_is_dry(x, z, LAY) else "否"])
	var ring: float = float(WorldBuilder.CITY_SHAPE[LAY].via_ring_r)
	print("  到环线高架（R %.0f）的径向差：%+.0f m（%s）" % [
		ring, r - ring, "在环外" if r > ring else "在环内"])


## §2b：**按分区**量楼高。`towers` 只含 `Tower_*`（真塔楼），`bld` 含裙房/退台。
func _section2b_heights(towers: Array[AABB], bld: Array[AABB]) -> void:
	var cb: float = WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var p: Dictionary = WorldBuilder.CITY_SHAPE[LAY]
	var hf: float = float(p.zone_hf) * cb
	var cz: float = float(p.cz) * cb
	print("")
	print("==== 2b · 楼高按分区（分区半径 = `zone_hf` × 格距 = %.0f m）====" % hf)
	print("  downtown d<0.34 ⇒ r < %.0f m；midtown d<0.62 ⇒ r < %.0f m；fringe d<0.82 ⇒ r < %.0f m"
		% [0.34 * hf, 0.62 * hf, 0.82 * hf])
	for band: Array in [["downtown", 0.0, 0.34], ["midtown", 0.34, 0.62],
			["fringe", 0.62, 0.82], ["waterfront", 0.82, 9.9]]:
		var arr: Array[float] = []
		var arr_all: Array[float] = []
		for src: Array in [[towers, arr], [bld, arr_all]]:
			var dst: Array[float] = src[1]
			for ba: AABB in src[0]:
				var c := ba.position + ba.size * 0.5
				var d := sqrt(c.x * c.x + (c.z - cz) * (c.z - cz)) / hf
				if d >= float(band[1]) and d < float(band[2]):
					dst.append(ba.size.y)
			dst.sort()
		var s := "  %-11s " % band[0]
		if arr.is_empty():
			s += "塔 0 栋"
		else:
			s += "塔 %3d 栋 · 中位 %5.0f · p90 %5.0f · **最高 %5.0f** m" % [
				arr.size(), arr[arr.size() / 2],
				arr[int(float(arr.size()) * 0.9)], arr[arr.size() - 1]]
		if not arr_all.is_empty():
			s += "   | 含裙房/退台 %d 个 · 最高 %.0f" % [
				arr_all.size(), arr_all[arr_all.size() - 1]]
		print(s)

	get_tree().quit(0)


# ------------------------------------------------------------------ §0 常量
func _section0_consts(cb: float) -> void:
	var p: Dictionary = WorldBuilder.CITY_SHAPE[LAY]
	print("==== 0 · 达沃的 CITY_SHAPE 摘要 ====")
	print("  格距 %.1f m   CITY_GRID %d" % [cb, WorldBuilder.CITY_GRID])
	print("  岛形   rx %.1f 格 = %.0f m   rz %.1f 格 = %.0f m   cz %.1f 格 = %.0f m   n %.1f"
		% [p.rx, float(p.rx) * cb, p.rz, float(p.rz) * cb, p.cz, float(p.cz) * cb, p.n])
	print("  海湾   bay_z %.0f  bay_wave %.0f  bay_lam %.0f  bay_side %.0f"
		% [p.bay_z, p.bay_wave, p.bay_lam, p.bay_side])
	print("  运河   canal_x %.0f  canal_half %.0f  canal_end_z %.0f"
		% [p.canal_x, p.canal_half, p.canal_end_z])
	print("  分区   zone_hf %.1f   广场 plaza_r %.0f   单轨 monorail_r %.0f"
		% [p.zone_hf, p.plaza_r, p.monorail_r])
	print("  高架环 via_ring_r %.0f m（%d 段）" % [p.via_ring_r, WorldBuilder.CITY_VIA_RING_SEGS])
	print("  丘陵   hill_in %.0f  hill_out %.0f  hill_amp %.0f" % [p.hill_in, p.hill_out, p.hill_amp])
	print("  水域径向门 water_r %.0f（<=0 = 不设门）" % p.water_r)
	print("  出击点 spawn_r %.0f（全局 SPAWN_RADIUS %.0f）" % [p.spawn_r, WorldBuilder.SPAWN_RADIUS])
	print("  彩虹桥 CITY_BRIDGE_Z %.0f（**全局常量**）  桥面 %.0f  塔 %.0f"
		% [WorldBuilder.CITY_BRIDGE_Z, WorldBuilder.CITY_BRIDGE_DECK_Y,
			WorldBuilder.CITY_BRIDGE_TOWER_Y])
	print("  高架桥面 CITY_VIA_DECK_Y %.0f  宽 %.0f" % [
		WorldBuilder.CITY_VIA_DECK_Y, WorldBuilder.CITY_VIA_W])
	print("  路灯 PITCH %.0f  杆高 %.0f" % [
		WorldBuilder.CITY_LAMP_PITCH, WorldBuilder.CITY_LAMP_POLE_H])


# ------------------------------------------------------------ §1 规划剖面
func _section1_profile(cb: float) -> void:
	print("")
	print("==== 1 · 规划剖面（沿轴线按米扫描，500 m 步长）====")
	print("  [x = 0 · 沿 z]  z : 地形(m) / W=规划水 / D=地形干燥")
	var zz := -115000.0
	var last_tag := ""
	while zz <= 75000.0:
		var hz := WorldBuilder._city_landform(0.0, zz, LAY)
		var wz := WorldBuilder.is_water_at(0.0, zz, LAY)
		var dz := WorldBuilder.city_is_dry(0.0, zz, LAY)
		var tag := "%s%s" % ["W" if wz else "-", "D" if dz else "-"]
		if tag != last_tag or absf(zz) < 1.0:
			print("    z %+9.0f  h %+9.1f  %s" % [zz, hz, tag])
			last_tag = tag
		zz += 500.0
	print("  [z = 0 · 沿 x]  x : 地形(m) / W=规划水 / D=地形干燥")
	var xx := -115000.0
	last_tag = ""
	while xx <= 115000.0:
		var hx := WorldBuilder._city_landform(xx, 0.0, LAY)
		var wx := WorldBuilder.is_water_at(xx, 0.0, LAY)
		var dx := WorldBuilder.city_is_dry(xx, 0.0, LAY)
		var tag2 := "%s%s" % ["W" if wx else "-", "D" if dx else "-"]
		if tag2 != last_tag:
			print("    x %+9.0f  h %+9.1f  %s" % [xx, hx, tag2])
			last_tag = tag2
		xx += 500.0
	# ---- 岛的形状：逐格扫 ----
	var gi_min := 999
	var gi_max := -999
	var gj_min := 999
	var gj_max := -999
	var nland := 0
	for gi in range(-36, 37):
		for gj in range(-36, 37):
			if WorldBuilder.city_is_land(float(gi) + 0.5, float(gj) + 0.5, LAY):
				nland += 1
				gi_min = mini(gi_min, gi)
				gi_max = maxi(gi_max, gi)
				gj_min = mini(gj_min, gj)
				gj_max = maxi(gj_max, gj)
	print("  岛（格）：gx [%d, %d] × gz [%d, %d]，合计 **%d 格**" % [
		gi_min, gi_max, gj_min, gj_max, nland])
	print("    ⇒ 世界坐标 x [%.0f, %.0f]  z [%.0f, %.0f]" % [
		float(gi_min) * cb, float(gi_max + 1) * cb, float(gj_min) * cb, float(gj_max + 1) * cb])
	print("  运河：x ∈ [%.0f, %.0f]（宽 %.0f m），z < %.0f" % [
		float(WorldBuilder.CITY_SHAPE[LAY].canal_x - WorldBuilder.CITY_SHAPE[LAY].canal_half),
		float(WorldBuilder.CITY_SHAPE[LAY].canal_x + WorldBuilder.CITY_SHAPE[LAY].canal_half),
		float(WorldBuilder.CITY_SHAPE[LAY].canal_half) * 2.0,
		float(WorldBuilder.CITY_SHAPE[LAY].canal_end_z)])


# ------------------------------------------------------------ §3 彩虹桥
func _section3_bridge(bld: Array[AABB], cb: float) -> void:
	print("")
	print("==== 3 · 桥（`_build_city_bridge()`，**按图给** · 2026-09-28 B0）====")
	# ⚠️⚠️ 这一节原来读的是**全局常量** `CITY_BRIDGE_Z` / `ARENA_RADIUS*0.82`，
	# 于是 B0 把桥改成"按图给"之后，它照样按 `z = 56 350` + 237.6 km 跨去采样 ⇒
	# 报出「桥面段 40 个 / 水上 0 / **陆上 40**」这个**陈旧结论**（达沃真正的桥在
	# `z = −20 125`、跨 8.6 km、沿 X）。**探针不改 = 拿旧结论当新证据。**
	var sh: Dictionary = WorldBuilder.CITY_SHAPE[LAY]
	var axis := String(sh.bridge_axis)
	var bpos := float(sh.bridge_pos)
	var ctr := float(sh.bridge_center)
	var span := float(sh.bridge_span)
	var deck_y := float(sh.bridge_deck_y)
	var tower_y := float(sh.bridge_tower_y)
	var bw := float(sh.bridge_w)
	var nseg := int(sh.bridge_segs)
	var along_x := axis == "x"
	print("  按图给：沿 **%s**，垂直方向坐标 **%.0f m**，桥心 **%.0f m**，跨 **%.0f m**"
		% [axis.to_upper(), bpos, ctr, span])
	print("  桥面 %.0f / 塔顶 %.0f / 宽 %.0f / **%d 段**（旧口径是全局常量 + 237.6 km 跨）"
		% [deck_y, tower_y, bw, nseg])

	# ---- 沿桥轴按米采样：桥面正下方是水、还是陆 ----
	print("  **桥面正下方**（沿桥轴每 5% 一点，共 21 点）：")
	var t0 := ctr - span * 0.5
	var t1 := ctr + span * 0.5
	var n_water := 0
	var line := ""
	for i in 21:
		var t := lerpf(t0, t1, float(i) / 20.0)
		var x := t if along_x else bpos
		var z := bpos if along_x else t
		var wet := WorldBuilder.is_water_at(x, z, LAY)
		if wet:
			n_water += 1
		if i % 4 == 0:
			line += "%+.0fkm:%s  " % [t / 1000.0, "水" if wet else "陆"]
	print("    %s" % line)
	print("  ⇒ 采样 21 点里 **水上 %d / 陆上 %d**（含两端岸上各约 370 m）"
		% [n_water, 21 - n_water])
	# 沿岸线精确找水陆交界
	var edge_lo := 0.0
	var edge_hi := 0.0
	for k in 2:
		var lo := t0 if k == 0 else ctr
		var hi := ctr if k == 0 else t1
		for _it in 40:
			var mid := (lo + hi) * 0.5
			var mx := mid if along_x else bpos
			var mz := bpos if along_x else mid
			var wet2 := WorldBuilder.is_water_at(mx, mz, LAY)
			if k == 0:
				if wet2:
					hi = mid
				else:
					lo = mid
			else:
				if wet2:
					lo = mid
				else:
					hi = mid
		if k == 0:
			edge_lo = (lo + hi) * 0.5
		else:
			edge_hi = (lo + hi) * 0.5
	print("  水面在桥轴上的区间：**%.0f … %.0f m**（宽 **%.0f m**）；两端岸上各 %.0f / %.0f m"
		% [edge_lo, edge_hi, edge_hi - edge_lo, edge_lo - t0, t1 - edge_hi])

	# ---- 桥面段 / 主塔：从场景里读（`_add_box`，节点变换 ⇒ headless 也准）----
	var deck_n := 0
	var hit := 0
	var hit_max := 0
	var pylon_n := 0
	var deck_bot := 1.0e18
	var deck_top := -1.0e18
	var ramp_n := 0
	for b: Node in _w.find_children("*", "StaticBody3D", true, false):
		var nm := String(b.name)
		if nm.begins_with("BridgeRampPier"):
			ramp_n += 1
			continue
		if not (nm.begins_with("BridgeDeck") or nm.begins_with("BridgePylon")):
			continue
		var mi := b.get_child(0) as MeshInstance3D
		if mi == null:
			continue
		var ab := _box_aabb(mi.global_transform, mi.mesh.get_aabb())
		if nm.begins_with("BridgePylon"):
			pylon_n += 1
			continue
		deck_n += 1
		deck_bot = minf(deck_bot, ab.position.y)
		deck_top = maxf(deck_top, ab.position.y + ab.size.y)
		var n := 0
		for ba: AABB in bld:
			if ab.intersects(ba):
				n += 1
		if n > 0:
			hit += 1
			hit_max = maxi(hit_max, n)
	print("  场景里认到：桥面段 **%d**（图上给 %d）/ 主塔柱 **%d**（图上给 2 塔 × 2 腿 = 4）"
		% [deck_n, nseg, pylon_n] + " / 引道墩 %d" % ramp_n)
	print("  桥面 AABB 的 y ∈ [%.0f, %.0f]（图上给 %.0f；塔顶 %.0f）"
		% [deck_bot, deck_top, deck_y, tower_y])
	if deck_n > 0:
		print("  **桥面段与楼体 AABB 相交 = %d / %d = %.1f%%**（单段最多穿 %d 栋）"
			% [hit, deck_n, 100.0 * float(hit) / float(deck_n), hit_max])

	# ---- 桥位走廊里到底有没有楼（垂直于桥轴切一条带）----
	var band_lo := bpos - bw * 0.5
	var band_hi := bpos + bw * 0.5
	var in_band := 0
	var near_d := 1.0e18
	var near_t := 0.0
	var t_lo := 1.0e18
	var t_hi := -1.0e18
	for ba: AABB in bld:
		var p0 := ba.position
		var p1 := ba.position + ba.size
		var bu0 := p0.z if along_x else p0.x
		var bu1 := p1.z if along_x else p1.x
		var bt0 := p0.x if along_x else p0.z
		var bt1 := p1.x if along_x else p1.z
		if bu1 < band_lo:
			if band_lo - bu1 < near_d:
				near_d = band_lo - bu1
				near_t = (bt0 + bt1) * 0.5
		elif bu0 > band_hi:
			if bu0 - band_hi < near_d:
				near_d = bu0 - band_hi
				near_t = (bt0 + bt1) * 0.5
		else:
			in_band += 1
			t_lo = minf(t_lo, bt0)
			t_hi = maxf(t_hi, bt1)
	print("  **桥位走廊（垂轴 ±%.0f m 那条带）里的楼 = %d 栋**" % [bw * 0.5, in_band]
		+ ("（沿轴 t ∈ [%.0f, %.0f]）" % [t_lo, t_hi] if in_band > 0 else ""))
	if in_band == 0:
		print("  ⚠️ 最近的一栋楼：垂轴差 **%.0f m**（沿轴 t = %.0f）" % [near_d, near_t])

	print("  桥面下方的地形（每 20% 一个点）：")
	var prof := ""
	for i in 6:
		var t := lerpf(t0, t1, float(i) / 5.0)
		var x2 := t if along_x else bpos
		var z2 := bpos if along_x else t
		prof += "t %+.0fkm: %.0f m  " % [t / 1000.0,
			WorldBuilder._city_landform(x2, z2, LAY)]
	print("    %s" % prof)


# --------------------------------------------------------------- §4 路网
func _section4_roads(cb: float) -> void:
	var half: int = WorldBuilder.CITY_GRID / 2
	var hill_in: float = float(WorldBuilder.CITY_SHAPE[LAY].hill_in)
	print("")
	print("==== 4 · 路网 ====")
	var mm := _w.find_child("CityRoads", true, false) as MultiMeshInstance3D
	if mm == null:
		print("  **没找到 `CityRoads`**")
		return
	var have := {}
	var r_min := 1.0e18
	var r_max := 0.0
	var beyond_hill := 0
	var beyond_out := 0
	for i in mm.multimesh.instance_count:
		var t := mm.multimesh.get_instance_transform(i)
		var ox := t.origin.x / cb
		var oz := t.origin.z / cb
		var key := ""
		var gk := 0
		if absf(ox - round(ox)) < 0.02:
			gk = int(floor(oz))
			key = "0_%d" % int(round(ox))
		else:
			gk = int(floor(ox))
			key = "1_%d" % int(round(oz))
		if not have.has(key):
			have[key] = {}
		have[key][gk] = true
		var rr := sqrt(t.origin.x * t.origin.x + t.origin.z * t.origin.z)
		r_min = minf(r_min, rr)
		r_max = maxf(r_max, rr)
		if rr > hill_in:
			beyond_hill += 1
		if rr > float(WorldBuilder.CITY_SHAPE[LAY].hill_out):
			beyond_out += 1
	var lines := 0
	var lines_full := 0
	var present_total := 0
	var drops := 0
	var drop_bay := 0
	var drop_canal := 0
	var drop_shore := 0
	var drop_dry := 0
	var gap_runs := {}
	var gap_water := 0
	var gap_land := 0
	var worst: Array = []
	# ⚠️ **不用 lambda 收尾**：GDScript 的匿名函数**按值捕获**外层局部变量
	#（在 `Callable` 建出来的那一刻拷一份）⇒ 写在里面的 `run / run_water` 永远是旧值，
	# 于是"缺口长度分布"会全错而**不报任何错**。改成先**建表**、再扫表。
	for axis in 2:
		for gi in range(-half, half + 1):
			lines += 1
			var set: Dictionary = have.get("%d_%d" % [axis, gi], {})
			var present := 0
			var reasons: Array[int] = []
			for gk in range(-half, half):
				if set.has(gk):
					present += 1
					reasons.append(-1)
				else:
					drops += 1
					var rc := _drop_reason(axis, gi, gk, cb)
					match rc:
						0: drop_dry += 1
						1: drop_bay += 1
						2: drop_canal += 1
						3: drop_shore += 1
					reasons.append(rc)
			present_total += present
			if present == half * 2:
				lines_full += 1
			# ---- 扫表：连续非 -1 的一段 = 一个缺口 ----
			var run := 0
			var nwat := 0
			var nland := 0
			var runs: Array[int] = []
			var i2 := 0
			while i2 <= reasons.size():
				var v := reasons[i2] if i2 < reasons.size() else -1
				if v >= 0:
					if v == 0:
						nland += 1
					else:
						nwat += 1
					run += 1
				else:
					if run > 0:
						runs.append(run)
						gap_runs[run] = int(gap_runs.get(run, 0)) + 1
						if nwat >= nland:
							gap_water += 1
						else:
							gap_land += 1
					run = 0
					nwat = 0
					nland = 0
				i2 += 1
			if not runs.is_empty():
				worst.append([runs.size(), -present, axis, gi, runs.duplicate()])
	print("  实有段 %d / 理论 %d = **%.1f%%**；候选被丢 %d 段"
		% [present_total, lines * half * 2,
			100.0 * float(present_total) / float(lines * half * 2), drops])
	print("  **一段不缺的格线 = %d / %d**" % [lines_full, lines])
	print("  被丢的段：**海湾 %d / 运河 %d / 岸边滩涂 %d**"
		% [drop_bay, drop_canal, drop_shore]
		+ "；⚠️ **三点全干却被丢 = %d**（非 0 就是筛选逻辑本身有 bug）" % drop_dry)
	var gk2: Array = gap_runs.keys()
	gk2.sort()
	var gp: Array[String] = []
	for k: int in gk2:
		gp.append("缺 %d 段 × %d 处" % [k, gap_runs[k]])
	print("  缺口长度分布：%s" % "   ".join(gp))
	print("  缺口成因（按段的多数）：水上 %d 处 / 陆上 %d 处" % [gap_water, gap_land])
	print("  ⚠️ 路面段在 `hill_in`(%.0f m) 之外 = **%d / %d = %.1f%%**；"
		% [hill_in, beyond_hill, present_total,
			100.0 * float(beyond_hill) / float(maxi(1, present_total))]
		+ "在 `hill_out` 之外 = %d 段" % beyond_out)
	print("  路面段到图心距离：%.0f … %.0f m" % [r_min, r_max])
	# ---- 达沃专用：路面段有多少铺在**岛外**（城区边界的真判据）----
	var off_island := 0
	var off_max := 0.0
	var canal_by_line := {}
	for i in mm.multimesh.instance_count:
		var t2 := mm.multimesh.get_instance_transform(i)
		if not WorldBuilder.city_is_land(t2.origin.x / cb, t2.origin.z / cb, LAY):
			off_island += 1
			off_max = maxf(off_max, sqrt(t2.origin.x * t2.origin.x + t2.origin.z * t2.origin.z))
	for axis in 2:
		for gi in range(-half, half + 1):
			var set2: Dictionary = have.get("%d_%d" % [axis, gi], {})
			var c := 0
			for gk in range(-half, half):
				if not set2.has(gk) and _drop_reason(axis, gi, gk, cb) == 2:
					c += 1
			if c > 0:
				canal_by_line["轴%d·gi%+d" % [axis, gi]] = c
	print("  ⚠️ **路面段落在岛外（`city_is_land` = 假）的 = %d / %d = %.1f%%**，最远 r = %.0f m"
		% [off_island, present_total, 100.0 * float(off_island) / float(present_total), off_max])
	print("  ⚠️ **被运河吃掉的候选段 = 108 里按格线分**：%s" % str(canal_by_line))
	worst.sort()
	worst.reverse()
	print("  最碎的 5 条格线（轴, gi → 各缺口长度）：")
	for i in mini(5, worst.size()):
		var w: Array = worst[i]
		print("    轴 %d · gi = %+d → %s" % [int(w[2]), int(w[3]), str(w[4])])


## 一段候选被丢的原因：0 = 三点全干（**真 bug**）、1 = 海湾、2 = 运河、3 = 岸边滩涂。
func _drop_reason(axis: int, gi: int, gk: int, cb: float) -> int:
	var line := float(gi) * cb
	var t := (float(gk) + 0.5) * cb
	var pts: Array[Vector2] = []
	for d: float in [-cb * 0.5, 0.0, cb * 0.5]:
		pts.append(Vector2(line, t + d) if axis == 0 else Vector2(t + d, line))
	for p: Vector2 in pts:
		if WorldBuilder.city_is_dry(p.x, p.y, LAY):
			continue
		# 是水。再分类：海湾 / 运河 / 滩涂
		if WorldBuilder.is_water_at(p.x, p.y, LAY):
			var cp: Dictionary = WorldBuilder.CITY_SHAPE[LAY]
			if absf(p.x - float(cp.canal_x)) < float(cp.canal_half) \
					and p.y < float(cp.canal_end_z):
				return 2
			return 1
		return 3
	return 0


# --------------------------------------------------------------- §5 高架
func _section5_viaduct(bld: Array[AABB], cb: float) -> void:
	print("")
	print("==== 5 · 高架 ====")
	var deck_mm := _w.find_child("CityViaductDeck", true, false) as MultiMeshInstance3D
	var ring_r: float = float(WorldBuilder.CITY_SHAPE[LAY].via_ring_r)
	if deck_mm == null:
		print("  **没找到 `CityViaductDeck`**")
		return
	var n := deck_mm.multimesh.instance_count
	var hit := 0
	var hit_max := 0
	var yaw_hist := {}
	var cross := 0
	var ring := 0
	var pier_total := 0
	var pier_in := 0
	var ring_water := 0
	for i in n:
		var t := deck_mm.multimesh.get_instance_transform(i)
		var ab := _box_aabb(t, _unit)
		var k := int(round(rad_to_deg(t.basis.get_euler().y) / 5.0)) * 5
		yaw_hist[k] = int(yaw_hist.get(k, 0)) + 1
		var rr := sqrt(t.origin.x * t.origin.x + t.origin.z * t.origin.z)
		var is_ring := ring_r > 0.0 and absf(rr - ring_r) < cb * 0.5
		if is_ring:
			ring += 1
			if WorldBuilder.is_water_at(t.origin.x, t.origin.z, LAY):
				ring_water += 1
		else:
			cross += 1
		var m := 0
		for ba: AABB in bld:
			if ab.intersects(ba):
				m += 1
		if m > 0:
			hit += 1
			hit_max = maxi(hit_max, m)
		var has_pier := true
		if is_ring:
			var idx := roundi(atan2(t.origin.z, t.origin.x) / TAU
				* float(WorldBuilder.CITY_VIA_RING_SEGS))
			has_pier = posmod(idx, WorldBuilder.CITY_VIA_RING_PIER_EVERY) == 0
		if has_pier:
			pier_total += 1
			for ba: AABB in bld:
				if t.origin.x >= ba.position.x and t.origin.x <= ba.position.x + ba.size.x \
						and t.origin.z >= ba.position.z \
						and t.origin.z <= ba.position.z + ba.size.z \
						and ba.position.y <= WorldBuilder.CITY_VIA_DECK_Y \
						and ba.position.y + ba.size.y >= WorldBuilder.CITY_VIA_DECK_Y:
					pier_in += 1
					break
	print("  桥面段 %d（十字 %d / 环线 %d）；环线段里**在水上**的 %d"
		% [n, cross, ring, ring_water])
	print("  ⚠️ **与楼体 AABB 相交的桥面段 = %d / %d = %.1f%%**（单段最多穿 %d 栋）"
		% [hit, n, 100.0 * float(hit) / float(n), hit_max])
	var keys: Array = yaw_hist.keys()
	keys.sort()
	var parts: Array[String] = []
	for k: int in keys:
		parts.append("%d°×%d" % [k, yaw_hist[k]])
	print("  偏航角直方图（量化 5°）：%s" % "  ".join(parts))
	print("  ⚠️ **墩立在楼体占地之内 = %d / %d = %.1f%%**"
		% [pier_in, pier_total,
			100.0 * float(pier_in) / float(maxi(1, pier_total))])
	var pier_nodes := 0
	for b: Node in _w.find_children("*", "StaticBody3D", true, false):
		var mi := b.get_child(0) as MeshInstance3D
		if mi == null:
			continue
		if absf(mi.scale.x - WorldBuilder.CITY_VIA_PIER_W) < 0.01 \
				and absf(mi.scale.z - WorldBuilder.CITY_VIA_PIER_W) < 0.01:
			pier_nodes += 1
	print("  场景里按尺寸（%.0f m 见方）认出来的墩 = %d 根" % [
		WorldBuilder.CITY_VIA_PIER_W, pier_nodes])


# --------------------------------------------------------------- §6 路灯
func _section6_lamps() -> void:
	print("")
	print("==== 6 · 路灯（达沃是活城，`city_lights = true`）====")
	for nm: String in ["CityLampPoles", "CityStreetLights", "CityWindows", "CityBeacons"]:
		var mm := _w.find_child(nm, true, false) as MultiMeshInstance3D
		if mm == null:
			print("  %-18s 不存在" % nm)
		else:
			print("  %-18s %d 个实例" % [nm, mm.multimesh.instance_count])


## §9：**新桥位**（薛尔思桥）的走廊楼高 ＋ **岛门**（`city_is_land`）对路网的效果。
##
## ## 为什么要 §9a
## v1 的 E2 把桥位写成「运河口 `z ≈ −20 000`」、跨取 3 225 m。`tools/_r9_davao_shore_probe`
## 量出来：运河与海湾**连成一片水**（`x = 6 000` 轴线上从 −80 km 到 +34 km 无切换点）
## ⇒ 没有"运河口"；且**水面宽 8 000 m** ⇒ 3 225 m 跨不过去。
## ⇒ 桥位能选的只有 `z ≥ −20 000` 那一段，跨 ≈ **8 600 m**（实测）。
## 而**桥面该多高**取决于走廊两侧的**楼**（不是推的）—— 这一节就是量这个。
##
## ## 为什么要 §9b
## v1 的 §3.1 主张"达沃用岛门（`city_is_land`）而不是半径门"，并说"直接砍掉 439 段
## （26.0%）"。但**容差**（允许 ±1 格，给滨水岸线留余地）会漏掉多少段，**没量过**。
func _section9_bridge_corridor(bld: Array[AABB], cb: float) -> void:
	print("")
	print("==== 9a · 薛尔思桥的桥位走廊（沿 x，格宽 %.0f m）====" % cb)
	var zs: Array[float] = [-20125.0, -18112.0, -16100.0]
	for z: float in zs:
		print("  ---- 候选桥位 z = %.0f ----" % z)
		var band := 400.0            # 桥面 z 方向半宽（估计值，桥宽待定）
		var top_all := -1.0e18
		var n_in := 0
		var n_water_col := 0
		var rows := ""
		for gi in range(-3, 8):      # x 从 −12 075 到 28 175
			var x0 := float(gi) * cb
			var x1 := x0 + cb
			var xm := (x0 + x1) * 0.5
			var top := -1.0e18
			var cnt := 0
			for ba: AABB in bld:
				var cx := ba.position.x + ba.size.x * 0.5
				var cz := ba.position.z + ba.size.z * 0.5
				if cx >= x0 and cx < x1 and absf(cz - z) < band + ba.size.z * 0.5:
					top = maxf(top, ba.position.y + ba.size.y)
					cnt += 1
			n_in += cnt
			top_all = maxf(top_all, top)
			var wet := WorldBuilder.is_water_at(xm, z, LAY)
			if wet:
				n_water_col += 1
			rows += "\n    gi %+d  x %+7.0f…%+7.0f  %-2s  楼 %3d 栋  顶 %s" \
				% [gi, x0, x1, "水" if wet else "陆", cnt,
					"—" if top < -1.0e17 else "%.0f m" % top]
		print(rows)
		var env := maxf(top_all, 0.0)
		print("    ⇒ 走廊内楼 **%d 栋** · **最高楼顶 %.0f m** · 桥面建议 **max(260, %.0f + 200) = %.0f m**（水上 %d 列）"
			% [n_in, env, env, maxf(260.0, env + 200.0), n_water_col])

	print("")
	print("==== 9b · 岛门（`city_is_land`）对路网的效果 ====")
	var mm := _w.find_child("CityRoads", true, false) as MultiMeshInstance3D
	if mm == null:
		print("  **没找到 `CityRoads`**")
		return
	var total := 0
	var outside := 0
	var rescued := 0
	var wet_out := 0
	for i in mm.multimesh.instance_count:
		var t := mm.multimesh.get_instance_transform(i)
		total += 1
		var gx := t.origin.x / cb
		var gz := t.origin.z / cb
		if WorldBuilder.city_is_land(gx, gz, LAY):
			continue
		outside += 1
		if WorldBuilder.is_water_at(t.origin.x, t.origin.z, LAY):
			wet_out += 1
		var near := false
		for dx: int in [-1, 0, 1]:
			for dz: int in [-1, 0, 1]:
				if WorldBuilder.city_is_land(gx + float(dx), gz + float(dz), LAY):
					near = true
					break
			if near:
				break
		if near:
			rescued += 1
	print("  路面段 **%d**；岛外 **%d = %.1f%%**（其中在水上 %d）；**±1 格容差后能留下 %d，仍须丢 %d**"
		% [total, outside, 100.0 * float(outside) / float(total), wet_out,
			rescued, outside - rescued])


func _box_aabb(xf: Transform3D, unit: AABB) -> AABB:
	var mn := Vector3(1.0e18, 1.0e18, 1.0e18)
	var mx := Vector3(-1.0e18, -1.0e18, -1.0e18)
	for i in 8:
		var p := unit.position + Vector3(
			unit.size.x * float(i & 1),
			unit.size.y * float((i >> 1) & 1),
			unit.size.z * float((i >> 2) & 1))
		var q := xf * p
		mn = mn.min(q)
		mx = mx.max(q)
	return AABB(mn, mx - mn)
