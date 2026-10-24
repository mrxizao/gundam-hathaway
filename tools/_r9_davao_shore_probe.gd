extends Node
## 达沃**水系**剖面探针（纯静态函数 ⇒ 不建城、可 headless、秒级）。
##
## ## 为什么单独量这一条
## 达沃 v1 的 §3.4 E2 把"彩虹桥改成薛尔思桥"的位置写成
## 「**运河口 / 湾口**（`z ≈ −20 000`），跨过运河出口」，跨取 **3 225 m**。
## 但 `is_water_at()` 里达沃的运河判据是
##     `absf(x - canal_x) < canal_half and z < canal_end_z`
## —— **只有上界 `z < 34 000`，没有下界**。
## ⇒ 运河一路延伸到海湾、两者**连成同一片水** ⇒「运河口」这个位置**不存在**；
##    而运河宽 **7 860 m** > 3 225 m ⇒ **桥跨不过去**。
## ⇒ 桥的位置与跨径**必须量出来**（这正是奥恩贝利那一轮 P5 翻车的同一种错）。
##
## 打四样：
##   ① 运河轴线（`x = 6 000`）沿 `z` 的水/陆切换点 —— 看它与海湾怎么接；
##   ② 横向断面（`z` 每 5～10 km，沿 `x` 扫）—— 水区间的起点 / 终点 / 宽度；
##   ③ 南岸岸线（`x` 每 10 km，沿 `z` 找水流的第一点）；
##   ④ 跨运河的**桥位候选表**：从运河中心往两侧找**第一个干燥点**（= 接地点）
##      ＋ 两岸地形高度 ＋ 两岸是不是岛。
##
## ⚠️ 三个静态函数都是 `static`：`_city_landform` / `is_water_at` / `city_is_dry` / `city_is_land`
## ⇒ 不用 `WorldBuilder.new()`、不用 `add_child`、不用 await 物理帧。
## ⚠️ 但仍**必须走场景**（`res://tools/_r9_davao_shore_probe.tscn`），
## 不能用 `--script`：后者不实例化 autoload，而 `world_builder.gd` 引用 `Settings`。

const LAY := MapDef.CityLayout.DAVAO
const CB := 4025.0          # `CITY_CBLOCK`：一格 4 025 m（换算中枢，只此一处）


func _ready() -> void:
	print("======== 达沃水系剖面（纯静态 · 不建城）========")
	_axis()
	_lateral()
	_shores()
	_candidates()
	get_tree().quit()


## §A 运河轴线：沿 `z` 从 −80 km 到 +60 km，打印**水/陆切换点**。
## 目的：看运河与海湾是不是连成一片（⇒ 有没有"运河口"可跨）。
func _axis() -> void:
	print("")
	print("==== §A 运河轴线 `x = 6 000` 沿 z（只看切换点）====")
	print("         z        地形 m   规划水")
	var last := 9
	var z := -80000.0
	while z <= 60000.0:
		var wet := WorldBuilder.is_water_at(6000.0, z, LAY)
		var tag := 1 if wet else 0
		if tag != last:
			var h := WorldBuilder._city_landform(6000.0, z, LAY)
			print("  %+10.0f  %+9.1f   %s" % [z, h, "水" if wet else "陆"])
			last = tag
		z += 250.0
	var h2 := WorldBuilder._city_landform(6000.0, 60000.0, LAY)
	print("  %+10.0f  %+9.1f   %s" % [60000.0, h2,
		"水" if WorldBuilder.is_water_at(6000.0, 60000.0, LAY) else "陆"])


## §B 横向断面：`z` 固定、沿 `x` 扫（步长 250 m）⇒ 打印每条线上的**水区间**。
func _lateral() -> void:
	print("")
	print("==== §B 横向断面（沿 x 扫，步长 250 m）====")
	print("         z     水区间 [起 … 止]（宽）")
	var zs: Array[float] = [-60000.0, -50000.0, -45000.0, -40000.0, -35000.0, -30000.0,
		-25000.0, -20000.0, -15000.0, -10000.0, -5000.0, 0.0, 5000.0, 10000.0,
		20000.0, 30000.0, 40000.0]
	for z: float in zs:
		var segs: Array = []
		var x := -95000.0
		var run := 1.0e18
		while x <= 95000.0:
			if WorldBuilder.is_water_at(x, z, LAY):
				if run > 1.0e17:
					run = x
			elif run < 1.0e17:
				segs.append([run, x - 250.0])
				run = 1.0e18
			x += 250.0
		if run < 1.0e17:
			segs.append([run, 95000.0])
		var s := ""
		for sg: Array in segs:
			var a := float(sg[0])
			var b := float(sg[1])
			s += "[%+.0f … %+.0f 宽 %.0f]  " % [a, b, b - a]
		print("  %+9.0f   %s" % [z, s if s != "" else "（无）"])


## §C 南岸岸线：`x` 固定、沿 `z` 从上往下找**第一个水点**（= 岸线 z）。
## 目的：看南岸在哪、是不是一条平滑的弧（正弦）。
func _shores() -> void:
	print("")
	print("==== §C 南岸岸线（沿 z 从上往下找第一个水点）====")
	print("         x     岸线 z m   当地地形 m")
	var xs: Array[float] = [-70000.0, -60000.0, -50000.0, -40000.0, -30000.0, -20000.0,
		-10000.0, 0.0, 10000.0, 20000.0, 30000.0, 40000.0, 50000.0, 60000.0, 70000.0]
	for x: float in xs:
		var z := 30000.0
		var coast := 1.0e18
		while z >= -80000.0:
			if WorldBuilder.is_water_at(x, z, LAY):
				coast = z
				break
			z -= 100.0
		if coast > 1.0e17:
			print("  %+9.0f   （一路是陆）" % x)
		else:
			print("  %+9.0f   %+9.0f   %+9.1f"
				% [x, coast, WorldBuilder._city_landform(x, coast, LAY)])


## §D 跨运河的桥位候选：从运河中心（`x = 6 000`）往两侧走，找**第一个干燥点**。
## 那个点就是桥的**接地点**；`|xr − xl|` 是"最小桥长"。
func _candidates() -> void:
	print("")
	print("==== §D 跨运河的桥位候选（运河中心 x = 6 000 往两侧找第一个干燥点）====")
	print("         z      左岸 x   左岸地形  左岸岛   右岸 x   右岸地形  右岸岛     跨 m   水位宽 m")
	var zs: Array[float] = [-45000.0, -40000.0, -35000.0, -30000.0, -25000.0, -20000.0,
		-15000.0, -10000.0, -5000.0, 0.0, 5000.0, 10000.0, 15000.0, 20000.0, 25000.0, 30000.0]
	for z: float in zs:
		var xl := 6000.0
		while xl > -95000.0 and not WorldBuilder.city_is_dry(xl, z, LAY):
			xl -= 100.0
		var xr := 6000.0
		while xr < 95000.0 and not WorldBuilder.city_is_dry(xr, z, LAY):
			xr += 100.0
		# 水面宽（纯水，不含滩涂）
		var sx := 6000.0
		while sx > -95000.0 and WorldBuilder.is_water_at(sx, z, LAY):
			sx -= 100.0
		var ex := 6000.0
		while ex < 95000.0 and WorldBuilder.is_water_at(ex, z, LAY):
			ex += 100.0
		var ll := "Y" if WorldBuilder.city_is_land(xl / CB, z / CB, LAY) else "N"
		var rr := "Y" if WorldBuilder.city_is_land(xr / CB, z / CB, LAY) else "N"
		print("  %+9.0f %+10.0f %+9.1f %6s %+9.0f %+9.1f %6s %8.0f %9.0f"
			% [z, xl, WorldBuilder._city_landform(xl, z, LAY), ll,
				xr, WorldBuilder._city_landform(xr, z, LAY), rr, xr - xl, ex - sx])
