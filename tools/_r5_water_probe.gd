extends Node
## 读数探针：**四块岛"外圈"到底是水还是地**（2026-09-28）。
##
## 只打印数值、不渲染 ⇒ 可以 `--headless` 跑（几秒）：
##   godot --headless --path <工程> res://tools/_r5_water_probe.tscn
##
## ## 为什么非量不可
## `is_water_at()` 说"盒内非岛 ⇒ 水"，`_oenbelli_canal_dig()` 说"切到 −110 m" ——
## 两句话是**两个真源**：前者管规划（路网 / 地块筛选），后者管**地形**。
## 只信前者的话，若地形没真的切下去，画面上就是"几条莫名空着的缝 / 一整圈干地"，
## 而且**不报任何错**。所以这里把两件事**并排量**：
##   地形高度（米） · 水面高度 `CITY_WATER_Y` · `is_water_at` · `city_is_dry`
## 判据：`is_water_at == true` 的点，地形必须 **< CITY_WATER_Y`**（否则"规划是水、
## 画面上是干地"）。反过来 `is_water_at == false` 的点，地形必须 **> 水面**。

const WATER_Y := -12.0


func _ready() -> void:
	var w := WorldBuilder.new()
	add_child(w)
	await get_tree().physics_frame
	w.apply_map(MapDef.oenbelli())
	await get_tree().physics_frame

	print("==== 常量 ====")
	print("CITY_WATER_Y      = %.1f m" % WorldBuilder.CITY_WATER_Y)
	print("CITY_CANAL_DEPTH  = %.1f m   CITY_CANAL_RAMP = %.1f m"
		% [WorldBuilder.CITY_CANAL_DEPTH, WorldBuilder.CITY_CANAL_RAMP])
	print("CITY_CBLOCK       = %.1f m"
		% (WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)))
	print("OENB_BOX（格）    = %s" % str(WorldBuilder.OENB_BOX))
	# 水面平面本体：高度与尺寸（`_build_ocean()` 建的那个 `Ocean` 节点）。
	var ocean := w.find_child("Ocean", true, false) as MeshInstance3D
	if ocean != null:
		print("Ocean 节点        : y = %.1f m   mesh = %s"
			% [ocean.global_position.y, str(ocean.mesh.get_aabb().size if ocean.mesh else "?")])
	else:
		print("Ocean 节点        : **没找到**（名字变了？）")

	# ---- ① 采样：从盒心往外横穿一条线，跨过「台场 → 台场-青海 运河 → 青海 → 外圈」----
	print("")
	print("==== 横穿线 z = 0（x 从 −80 km 到 +80 km，每 2 025 m 一点）====")
	print("      x(m)   档位  地形高度(m)  规划为水  干燥  沟槽")
	var bad := 0
	var x := -80000.0
	while x <= 80000.0:
		var h: float = WorldBuilder._city_landform(x, 0.0, MapDef.CityLayout.OENBELLI)
		var water: bool = WorldBuilder.is_water_at(x, 0.0, MapDef.CityLayout.OENBELLI)
		var dry: bool = WorldBuilder.city_is_dry(x, 0.0, MapDef.CityLayout.OENBELLI)
		var inconsistent := (water and h >= WorldBuilder.CITY_WATER_Y) \
			or (not water and h < WorldBuilder.CITY_WATER_Y - 1.0)
		if inconsistent:
			bad += 1
		print("%11.0f   %-5s %11.1f  %-8s  %-5s  %s"
			% [x, "水" if water else "地", h, "是" if water else "否",
				"是" if dry else "否", "**矛盾**" if inconsistent else ""])
		x += 2025.0
	print("")
	print("矛盾点数 = %d（判据：规划为水 ⇒ 地形必须 < %.0f m）" % [bad, WorldBuilder.CITY_WATER_Y])
	print("⇒ 判定：%s" % ("**规划与地形对不上**" if bad > 0 else "规划与地形一致"))

	# ---- ② 三条运河中线的剖面：河床深度够不够（要低于水面才有"水"）----
	#
	# ⚠️⚠️ 中线**从块表算**（"两块面对面取中"），**不写格号**。
	# 本函数的**第一版**把三条运河写成 ±7.5 格 / −8.5 格，其中**两条是错的**：
	#   · 台场 gx ∈ [−6, 6] / 有明 gx ∈ [−15, −8] ⇒ 中间那一格是 **gx = −7**
	#     ⇒ 中线是 **−6.5 格**（−26 162.5 m），而 −7.5 格已经落在**有明岛上**；
	#   · 台场 gz ∈ [−7, 7] / 东八潮 gz ∈ [−16, −9] ⇒ 中间那一格是 **gz = −8**
	#     ⇒ 中线是 **−7.5 格**（−30 187.5 m），而 −8.5 格已经在**东八潮岛上**。
	# 后果是读数看起来像"两条运河没挖"（河床 +0.6 / −0.6 m，比水面还高）——
	# **而工程完全正常**。差一点就把这个假警报写进交付说明。
	print("")
	print("==== 三条运河中线的河床标高（中线从块表算）====")
	for row: Array in [["台场-青海", _canal_x(0, 3, true), 0.0],
			["有明-台场", _canal_x(2, 0, true), 0.0],
			["台场-东八潮", 0.0, _canal_x(1, 0, false)]]:
		var h2: float = WorldBuilder._city_landform(
			float(row[1]), float(row[2]), MapDef.CityLayout.OENBELLI)
		var w2: bool = WorldBuilder.is_water_at(
			float(row[1]), float(row[2]), MapDef.CityLayout.OENBELLI)
		print("  %-12s 中线 (%.0f, %.0f)  河床 %.1f m  水面 %.1f m  ⇒ 水深 %.1f m  "
			% [str(row[0]), float(row[1]), float(row[2]), h2,
				WorldBuilder.CITY_WATER_Y, WorldBuilder.CITY_WATER_Y - h2]
			+ "规划为水 %s" % ("是" if w2 else "**否**"))

	# ---- ③ 外圈：盒内非岛、但离块很远的地方（S1 图里那一大片）----
	print("")
	print("==== 外圈样点（盒内非岛、离块 ≥ 8 km）====")
	for p: Vector2 in [Vector2(50000.0, 40000.0), Vector2(0.0, 39000.0),
			Vector2(-50000.0, -55000.0), Vector2(60000.0, -60000.0),
			Vector2(0.0, -66000.0)]:
		var h3: float = WorldBuilder._city_landform(p.x, p.y, MapDef.CityLayout.OENBELLI)
		var w3: bool = WorldBuilder.is_water_at(p.x, p.y, MapDef.CityLayout.OENBELLI)
		print("  (%.0f, %.0f)  地形 %8.1f m  规划为水 %s  ⇒ 露出水面 %.1f m"
			% [p.x, p.y, h3, "是" if w3 else "否", h3 - WorldBuilder.CITY_WATER_Y])
	get_tree().quit(0)


## 两块"面对面"之间的那一格的中线（米）。`along_x = true` 取 x（竖运河），
## 否则取 z（横运河）。下标与 `OENB_BLOCKS` 的顺序一致：0 台场 / 1 东八潮 /
## 2 有明 / 3 青海。
##
## ⚠️ 由**块表**算而不是写格号 —— 写在调用处就是第二份真源，块表一挪就错，
## 而错的表现是"读数是岛面高度"，看起来像"运河没挖"（本函数第一版就这么错过）。
func _canal_x(ia: int, ib: int, along_x: bool) -> float:
	var a: Array = WorldBuilder.OENB_BLOCKS[ia]
	var b: Array = WorldBuilder.OENB_BLOCKS[ib]
	var cb: float = WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	if along_x:
		# a 在 −X 侧 ⇒ 用它的 gx1 外边；b 在 +X 侧 ⇒ 用它的 gx0 内边。
		var ea: float = (float(int(a[1])) + 1.0) * cb
		var eb: float = float(int(b[0])) * cb
		return (minf(ea, eb) + maxf(ea, eb)) * 0.5
	var fa: float = (float(int(a[3])) + 1.0) * cb
	var fb: float = float(int(b[2])) * cb
	return (minf(fa, fb) + maxf(fa, fb)) * 0.5
