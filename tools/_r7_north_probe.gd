extends Node
## 读数探针：**彩虹桥北端**的地形剖面（2026-09-28 · 城市设计 v3 定案用）。
##
## ## 为什么单独量这一条
## v2 的 §P5 把"桥北端（北岸 `z ≥ 80 500`）什么都没有"的解法写成
## 「桥台 + 一小段引道（~2 格）」。但那个解法**成立与否取决于北岸地形怎么长**：
##
## - 若出了 `CITY_WATER_R = 78 000` 的门就是**平陆**（丘陵从 `CITY_HILL_IN = 82 000` 才起），
##   那"引道按 4.5% 落坡"要在 12.4 km 内落完 560 m ⇒ **落点必然进山**；
## - 若进山处地形已经 2 000 m，而引道那时只降到 0 m ⇒ **桥埋在山里**（不报错的错）。
##
## ⇒ 北端的设计必须是**读出来的**，不是推的。这里打三样：
##   ① 桥轴线 `x = 0` 的纵剖面（地形 / 水 / 干燥 / 岛）；
##   ② 北岸横向剖面（`z` 固定、`x` 扫）—— 看山是"一道墙"还是"有谷"；
##   ③ 每个 4 km 带上 `x ∈ [−20, 20] km` 的**地形上界**—— 引道净空的下界。
##
## 纯静态函数调用 ⇒ 不建城、可 `--headless`：
##   godot --headless --path <工程> res://tools/_r7_north_probe.tscn

const O := MapDef.CityLayout.OENBELLI
const CB := 4025.0


func _ready() -> void:
	var lf := func(x: float, z: float) -> float:
		return WorldBuilder._city_landform(x, z, O)

	print("==== 0 · 常量 ====")
	print("  CITY_HILL_IN %.0f   CITY_HILL_OUT %.0f   CITY_WATER_R %.0f"
		% [WorldBuilder.CITY_HILL_IN, WorldBuilder.CITY_HILL_OUT, WorldBuilder.CITY_WATER_R])
	print("  CITY_BAY_Z %.0f   CITY_BRIDGE_Z %.0f   ARENA_RADIUS %.0f"
		% [WorldBuilder.CITY_BAY_Z, WorldBuilder.CITY_BRIDGE_Z, WorldBuilder.ARENA_RADIUS])

	print("")
	print("==== 1 · 桥轴线 x = 0 纵剖面（z 从 30 km 向北）====")
	print("         z         r   地形(m)   水  干燥   岛")
	var z := 30000.0
	while z <= 106000.0:
		print("  %8.0f  %8.0f  %8.2f    %s   %s   %s" % [
			z, absf(z), float(lf.call(0.0, z)),
			_b(WorldBuilder.is_water_at(0.0, z, O)),
			_b(WorldBuilder.city_is_dry(0.0, z, O)),
			_b(WorldBuilder.city_is_land(0.0 / CB, z / CB, O))])
		z += 2500.0

	print("")
	print("==== 2 · 北岸横向剖面（行 = z，列 = x 从 −40 km 到 +40 km，步长 10 km）====")
	print("        z \\ x        -40     -30     -20     -10       0     +10     +20     +30     +40")
	for zz: float in [76000.0, 80000.0, 84000.0, 88000.0, 92000.0, 96000.0, 100000.0]:
		var row := ""
		var x := -40000.0
		while x <= 40000.5:
			row += "%8.0f" % float(lf.call(x, zz))
			x += 10000.0
		print("  %8.0f     %s" % [zz, row])

	print("")
	print("==== 3 · 北向走廊地形上界（x ∈ [−20, 20] km，步长 1 km）====")
	print("        z 带        上界(m)")
	z = 80000.0
	while z <= 104000.0:
		var mx := -1.0e9
		var x2 := -20000.0
		while x2 <= 20000.5:
			mx = maxf(mx, float(lf.call(x2, z)))
			x2 += 1000.0
		print("  %6.0f…%6.0f   %8.0f" % [z, z + 4000.0, mx])
		z += 4000.0

	print("")
	print("==== 4 · 沿 x = 0 向北：地形首次超过阈值的 z（山脚在哪）====")
	for thr: float in [200.0, 500.0, 1000.0, 2000.0, 3000.0]:
		var hit := -1.0
		var z3 := 78000.0
		while z3 <= 112000.0:
			if float(lf.call(0.0, z3)) > thr:
				hit = z3
				break
			z3 += 250.0
		print("  地形 > %6.0f m 首次出现在 z = %s" % [
			thr, ("%.0f" % hit) if hit > 0.0 else "（未出现）"])

	get_tree().quit()


func _b(v: bool) -> String:
	return "是" if v else "否"
