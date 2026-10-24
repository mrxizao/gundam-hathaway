extends Node
## R1/R2/R3 探针（2026-09-27 第二轮：公路 / 高架 / 错落 / 不在水上）。
##
## 跑法（**必须走场景，不能用 `--script`**）：
##   godot --headless --path <工程> res://tools/_p0_probe.tscn
##
## ⚠️ 为什么不能用 `--script`：`--script` 模式**不实例化 autoload**，而
## `world_builder.gd` 引用了 autoload `Settings`（`lock_on_system.gd` 引用 `Game`）
## ⇒ 整份脚本编译不过。这不是本文件的问题，换任何脚本都一样。
##
## 本探针**只读纯函数与常量**（不建场景、不建节点），所以它同时是
## "工程能不能编译" 与 "判据取值是多少" 的一发读数。
## 路网 / 高架桥的**段数**由 `_build_*()` 的 `print()` 给出（跑全量回归即可看到）。


func _ready() -> void:
	print("=========== R1/R2/R3 探针 ===========")
	var cblock := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var D := MapDef.CityLayout.DAVAO
	var O := MapDef.CityLayout.OENBELLI
	print("[水面与陆地]  CITY_WATER_Y = %.1f  DRY_MARGIN = %.1f  ⇒ 判据 h > %.1f"
		% [WorldBuilder.CITY_WATER_Y, WorldBuilder.CITY_DRY_MARGIN,
			WorldBuilder.CITY_WATER_Y + WorldBuilder.CITY_DRY_MARGIN])

	# ---- R3 ①：地形低于水面的比例（这是"房子在水上"的主因）----
	# 分两组读：全体网格点 / **只算 `is_water_at()` 说"陆"的点**。
	# 后者才是真正会出事的那一批（前者里有海湾与运河，本来就该在水下）。
	for pair: Array in [[O, "奥恩贝利"], [D, "达沃"]]:
		var lay: int = pair[0]
		var nm: String = pair[1]
		var sub := 0
		var tot := 0
		var land_sub := 0
		var land_tot := 0
		var mn := 1.0e9
		var mx := -1.0e9
		var lo := 0
		var hi := 0
		for i in 121:
			for j in 121:
				var x := (float(i) / 120.0 * 2.0 - 1.0) * 65000.0
				var z := (float(j) / 120.0 * 2.0 - 1.0) * 65000.0
				var h: float = WorldBuilder._city_landform(x, z, lay)
				tot += 1
				if h < WorldBuilder.CITY_WATER_Y:
					sub += 1
					if not WorldBuilder.is_water_at(x, z, lay):
						land_sub += 1
					lo += 1
				if h >= WorldBuilder.CITY_WATER_Y:
					hi += 1
				if WorldBuilder.is_water_at(x, z, lay):
					continue
				land_tot += 1
				mn = minf(mn, h)
				mx = maxf(mx, h)
		print("  %s：全场水下 %.1f%%；**`is_water_at` 说陆但地形在水下的** %d/%d = %.3f%%"
			% [nm, float(sub) / float(tot) * 100.0,
				land_sub, land_tot, float(land_sub) / float(land_tot) * 100.0])
		print("      （判据 = 0：水面 −12 低于陆地最低点 −7.9）")
		print("      陆地区域地形范围 %.2f … %.2f m（判据：最低点 > %.1f）"
			% [mn, mx, WorldBuilder.CITY_WATER_Y])

	# ---- R3 ②：建楼的三道闸门各自刷掉多少格 ----
	for pair: Array in [[O, "奥恩贝利"], [D, "达沃"]]:
		var lay: int = pair[0]
		var nm: String = pair[1]
		var half := WorldBuilder.CITY_GRID / 2
		var footprint := cblock * WorldBuilder.CITY_FILL
		var hf_fp := footprint * 0.5
		var g_island := 0
		var g_water := 0
		var g_dry := 0
		var use := 0
		for gx in range(-half, half):
			for gz in range(-half, half):
				var cx := (float(gx) + 0.5) * cblock
				var cz := (float(gz) + 0.5) * cblock
				if not WorldBuilder.city_is_land(
						float(gx) + 0.5, float(gz) + 0.5, lay):
					continue
				g_island += 1
				if WorldBuilder.is_water_at(cx, cz, lay):
					g_water += 1
					continue
				var dry := true
				for oi in 3:
					for oj in 3:
						if not WorldBuilder.city_is_dry(
								cx + (float(oi) - 1.0) * hf_fp,
								cz + (float(oj) - 1.0) * hf_fp, lay):
							dry = false
							break
					if not dry:
						break
				if not dry:
					g_dry += 1
					continue
				use += 1
		print("  %s 建楼闸门：岛上 %d 格 → 海湾/运河刷掉 %d → **裙房不干燥刷掉 %d** → 实建 %d"
			% [nm, g_island, g_water, g_dry, use])

	# ---- R3 ③：路灯位（沿格线每 900 m 一点）有几盏在水上 ----
	for pair: Array in [[O, "奥恩贝利"], [D, "达沃"]]:
		var lay: int = pair[0]
		var nm: String = pair[1]
		var half := WorldBuilder.CITY_GRID / 2
		var wet := 0
		var lit := 0
		var t := -WorldBuilder.ARENA_RADIUS + WorldBuilder.CITY_LAMP_PITCH * 0.5
		while t <= WorldBuilder.ARENA_RADIUS:
			for gi in range(-half, half + 1):
				var line := float(gi) * cblock
				for axis in 2:
					var px := line if axis == 0 else t
					var pz := t if axis == 0 else line
					if not WorldBuilder.city_is_land(px / cblock, pz / cblock, lay):
						continue
					if WorldBuilder.is_water_at(px, pz, lay):
						continue
					if WorldBuilder.city_is_dry(px, pz, lay):
						lit += 1
					else:
						wet += 1
			t += WorldBuilder.CITY_LAMP_PITCH
		print("  %s 灯位：**留下 %d 盏（全部在干地上）** / 闸门拦掉 %d 盏（这些原本会浮在水面上）"
			% [nm, lit, wet])

	# ---- R1：路面分档 ----
	print("[路网分档] 支路 %.0f / 次干 %.0f / 主干 %.0f m ⇒ 极差 %.2f 倍（判据 ≥ 2.5）"
		% [WorldBuilder.CITY_ROAD_W_LOCAL, WorldBuilder.CITY_ROAD_W_ARTERIAL,
			WorldBuilder.CITY_ROAD_W_TRUNK,
			WorldBuilder.CITY_ROAD_W_TRUNK / WorldBuilder.CITY_ROAD_W_LOCAL])
	var w0 := WorldBuilder.city_road_width(0)
	var w1 := WorldBuilder.city_road_width(1)
	var w5 := WorldBuilder.city_road_width(5)
	var w6 := WorldBuilder.city_road_width(6)
	var w15 := WorldBuilder.city_road_width(15)
	print("  抽样 gi = 0 / 1 / 5 / 6 / 15 ⇒ %.0f / %.0f / %.0f / %.0f / %.0f"
		% [w0, w1, w5, w6, w15])
	print("[高架桥] 桥面 %.0f m / 宽 %.0f / 板厚 %.0f / 墩 %.0f 见方 / 环线每 %.0f 段一根"
		% [WorldBuilder.CITY_VIA_DECK_Y, WorldBuilder.CITY_VIA_W,
			WorldBuilder.CITY_VIA_DECK_T, WorldBuilder.CITY_VIA_PIER_W,
			float(WorldBuilder.CITY_VIA_RING_PIER_EVERY)])
	print("  桥面 %.0f 必须 > 240（机体能从底下钻）⇒ %s"
		% [WorldBuilder.CITY_VIA_DECK_Y,
			"OK" if WorldBuilder.CITY_VIA_DECK_Y > 240.0 else "❌"])
	print("  环线半径：奥恩贝利 %.1f km / 达沃 %.1f km"
		% [float(WorldBuilder.CITY_SHAPE[O].via_ring_r) / 1000.0,
			float(WorldBuilder.CITY_SHAPE[D].via_ring_r) / 1000.0])

	# ---- R2：楼高分布（错落的量化判据）----
	print("[楼高分布] 判据：① 同区**极差/中位** ≥ 0.35（错落）② 达沃市中心中位 ≫ 奥恩贝利")
	for pair: Array in [[O, "奥恩贝利", 20260922], [D, "达沃", 20260325]]:
		var lay: int = pair[0]
		var nm: String = pair[1]
		var sv: int = pair[2]
		var by_zone := {}
		var rng := RandomNumberGenerator.new()
		var half := WorldBuilder.CITY_GRID / 2
		for gx in range(-half, half):
			for gz in range(-half, half):
				if not WorldBuilder.city_is_land(float(gx) + 0.5, float(gz) + 0.5, lay):
					continue
				rng.seed = WorldBuilder._city_lot_seed(gx, gz, sv)
				var lot: Dictionary = WorldBuilder.city_lot_for(gx, gz, rng, sv, lay)
				if not by_zone.has(lot.zone):
					by_zone[lot.zone] = []
				by_zone[lot.zone].append(lot.h)
		var hmul := 1.0
		if lay == D:
			hmul = MapDef.davao().city_height_mul
		var dt_mul := float(WorldBuilder.CITY_SHAPE[lay].dt_mul)
		for zn: String in ["downtown", "midtown", "fringe", "waterfront"]:
			if not by_zone.has(zn):
				continue
			var arr: Array = by_zone[zn]
			arr.sort()
			var n := arr.size()
			var lo2: float = arr[0]
			var hi2: float = arr[n - 1]
			var med: float = arr[n / 2]
			var spr := (hi2 - lo2) / maxf(med, 1.0)
			print("  %s·%-10s n=%4d  %.0f … %.0f（中位 %.0f）极差/中位 = %.2f  %s"
				% [nm, zn, n, lo2, hi2, med, spr, "✓" if spr >= 0.35 else "❌"])
		# ⚠️⚠️ `dt_mul` **已经在 `city_lot_for()` 里面乘过了**（它作用在 `lot.h` 上），
		# 所以这里**只能再乘 `city_height_mul`** —— 第一版两处都乘了 `dt_mul`，
		# 读数整体偏高 10~35%（那会让人按错的数去调倍率）。
		# 而 `city_height_mul` 是在 `_city_block_at()` 里乘的 ⇒ 探针要手动补上。
		var dt_arr: Array = by_zone.get("downtown", [])
		var dt_typ := 0.0
		var dt_max := 0.0
		for h: float in dt_arr:
			dt_typ += h
			dt_max = maxf(dt_max, h)
		if not dt_arr.is_empty():
			dt_typ /= float(dt_arr.size())
		print("   %s 市中心 `lot.h` 均值 %.0f / 最大 %.0f（**已含 dt_mul %.2f**）"
			% [nm, dt_typ, dt_max, dt_mul])
		print("   %s ⇒ **典型 %.0f m**（×height_mul %.2f）"
			% [nm, dt_typ * hmul, hmul])
		print("   %s ⇒ **最高 %.0f m**（同上）" % [nm, dt_max * hmul])

	# ---- R2：针塔必须高过最高的楼 ----
	var needle := (1250.0 + 1300.0 + 1050.0 + 600.0) * float(WorldBuilder.CITY_SHAPE[D].needle_mul) \
		+ 350.0 * float(WorldBuilder.CITY_SHAPE[D].needle_mul) * 2.0
	print("[针塔] 达沃 %.0f m（`needle_mul` %.2f）⇒ 判据：必须 > 全城最高楼"
		% [needle, WorldBuilder.CITY_SHAPE[D].needle_mul])

	# ---- 两座城的运河护岸能不能跑起来（旧版达沃一次都不跑）----
	# ⚠️ 2026-09-28：奥恩贝利的 `CITY_SHAPE[0]` 里**没有** `canal_*` 三个键了
	#（它的运河是"四块岛的补集"，见 `OENB_BLOCKS`）⇒ 直接取会**崩**。
	# 奥恩贝利改量"有几条块边临运河"，达沃仍然量那条直槽上有多少段。
	for pair: Array in [[O, "奥恩贝利"], [D, "达沃"]]:
		var lay: int = pair[0]
		var nm: String = pair[1]
		var sh: Dictionary = WorldBuilder.CITY_SHAPE[lay]
		var n := 0
		if sh.has("canal_x"):
			var bay_z2 := float(sh.bay_z)
			var side2b := float(sh.bay_side)
			var zz := float(sh.canal_end_z) * 0.5
			while (zz - bay_z2 * 0.6) * side2b <= 0.0 and n < 4000:
				n += 1
				zz += 340.0 * side2b
		else:
			# 四块岛：数"外侧那一列是运河"的块边有几条（`_oenbelli_quays()` 的落位数）
			var gr := WorldBuilder.CITY_GRID / 2
			for bb: Array in WorldBuilder.OENB_BLOCKS:
				var g0 := int(bb[0])
				var g1 := int(bb[1])
				var h0 := int(bb[2])
				var h1 := int(bb[3])
				var mgx := (g0 + g1) / 2
				var mgz := (h0 + h1) / 2
				for pr: Array in [[g0 - 1, mgz], [g1 + 1, mgz],
						[mgx, h0 - 1], [mgx, h1 + 1]]:
					var gi := int(pr[0])
					var gj := int(pr[1])
					if gi < -gr or gi >= gr or gj < -gr or gj >= gr:
						continue
					if WorldBuilder._oenbelli_canal_cell(gi, gj):
						n += 1
		print("  护岸段数 %s = %d  %s" % [nm, n, "✓" if n > 0 else "❌ 一段都没有"])
	# ---- R2 ⚠️ **核心判据**：分区是不是圆的 ----
	#
	# ⚠️ "同区极差/中位"那条**拦不住**旧实现（旧的同心圆里每格仍然各自抽一次
	# `randf_range(h_min, h_max)` ⇒ 极差本来就大）。真正拦得住的是：
	# **同一个半径圈上出现了两个不同的分区** —— 旧实现下分区是半径的函数，
	# 每圈只有一个 zone ⇒ 这个数**恒为 0**。
	print("[分区形状] 判据：**同一半径圈上出现 ≥2 个分区**的圈数 > 2")
	for pair: Array in [[O, "奥恩贝利"], [D, "达沃"]]:
		var lay: int = pair[0]
		var nm: String = pair[1]
		var sh: Dictionary = WorldBuilder.CITY_SHAPE[lay]
		var hf := float(sh.zone_hf)
		var cz0 := float(sh.cz)
		var half2 := WorldBuilder.CITY_GRID / 2
		var rings := {}
		for gx in range(-half2, half2):
			for gz in range(-half2, half2):
				if not WorldBuilder.city_is_land(
						float(gx) + 0.5, float(gz) + 0.5, lay):
					continue
				var uu := (float(gx) + 0.5) / hf
				var vv := (float(gz) + 0.5 - cz0) / hf
				var d0 := sqrt(uu * uu + vv * vv)
				var bin := int(round(d0 * 50.0))
				var rng2 := RandomNumberGenerator.new()
				rng2.seed = WorldBuilder._city_lot_seed(gx, gz, WorldBuilder.CITY_SEED)
				var lt: Dictionary = WorldBuilder.city_lot_for(gx, gz, rng2,
					WorldBuilder.CITY_SEED, lay)
				if not rings.has(bin):
					rings[bin] = {}
				rings[bin][lt.zone] = true
		var mixed := 0
		for b in rings.keys():
			if rings[b].size() >= 2:
				mixed += 1
		print("  %s：半径圈共 %d 个，其中 **%d 个圈上有 ≥2 个分区**  %s"
			% [nm, rings.size(), mixed, "✓" if mixed > 2 else "❌"])

	# ---- R3 ⚠️ **核心判据**：水面 < **纯内陆**最低点 ----
	#
	# ⚠️ 必须把海湾 / 运河两侧的**边坡**剔掉：那两条带本来就是坡（渐降 480 / 110 m），
	# 拿它们算"陆地最低点"量到的是坡不是地（第一版全陆地取 p5，达沃量到 −63 m）。
	print("[水面 vs 内陆] 判据：CITY_WATER_Y < 纯内陆最低点")
	for pair: Array in [[O, "奥恩贝利"], [D, "达沃"]]:
		var lay: int = pair[0]
		var nm: String = pair[1]
		var sh2: Dictionary = WorldBuilder.CITY_SHAPE[lay]
		var side2 := float(sh2.bay_side)
		var half3 := WorldBuilder.CITY_GRID / 2
		var mn2 := 1.0e9
		var mx2 := -1.0e9
		var n_in := 0
		for gx in range(-half3, half3):
			for gz in range(-half3, half3):
				if not WorldBuilder.city_is_land(
						float(gx) + 0.5, float(gz) + 0.5, lay):
					continue
				var wx := (float(gx) + 0.5) * cblock
				var wz := (float(gz) + 0.5) * cblock
				if WorldBuilder.is_water_at(wx, wz, lay):
					continue
				var coast2 := float(sh2.bay_z) \
					+ float(sh2.bay_wave) * sin(wx / float(sh2.bay_lam))
				if (wz - (coast2 - 1400.0 * side2)) * side2 > 0.0:
					continue
				if sh2.has("canal_x"):
					if absf(wx - float(sh2.canal_x)) < float(sh2.canal_half) + 340.0 \
							and wz < float(sh2.canal_end_z):
						continue
				var hh := WorldBuilder._city_landform(wx, wz, lay)
				n_in += 1
				mn2 = minf(mn2, hh)
				mx2 = maxf(mx2, hh)
		print("  %s：纯内陆 %d 格，范围 %.2f … %.2f m；水面 %.1f m  %s"
			% [nm, n_in, mn2, mx2, WorldBuilder.CITY_WATER_Y,
				"✓" if WorldBuilder.CITY_WATER_Y < mn2 else "❌"])

	print("=========== 探针结束 ===========")
	get_tree().quit()
