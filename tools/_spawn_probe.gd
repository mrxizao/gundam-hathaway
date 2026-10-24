extends Node
## 读数探针：**出生点在丘陵的什么位置**。
##
## 只打印数值、不渲染 ⇒ 可以直接 `--headless` 跑（几秒）。
##
## 跑法：
##   godot --headless --path <工程> res://tools/_spawn_probe.tscn
##
## ## 为什么必须量
## 出生点是 `spawn_point(-95.0, match_spawn_radius(), PLAYER_START_ALT)`。
##
## ⚠️⚠️ 2026-09-28：**出击半径按图给**（`CITY_SHAPE[·].spawn_r`），
## 不再是全局 `SPAWN_RADIUS`（46 575 —— 那个数现在**落在城里**，
## 正好在青海块上）。奥恩贝利取 **90 000 m**，而丘陵是 **径向**环带
## 82 000 … 96 000 m ⇒ 出生点落在环带**中段**（`t = smoothstep(0.5) = 0.5`）。
## 而出生标高是"请求值 3 200 m **与** 地形 + `SPAWN_CLEARANCE` 取大者"——
## 环带中段的地形可以到 **4 000 m** ⇒ 出生点可能**埋在山体里**。
## 这件事不看数就只能靠"进游戏撞一下"。
##
## ⚠️ 本文件读的是 `_world.match_spawn_radius()`（按图给的那一个），
## **不是** `WorldBuilder.SPAWN_RADIUS` —— 用后者量出来的是一张**非城市图**的环。

## 扫环用的参数（与 main.gd 对得上）。
const SPAWN_ANGLE_DEG := -95.0
const ENEMY_ANGLE_DEG := 85.0

var _world: WorldBuilder


func _ready() -> void:
	_world = WorldBuilder.new()
	add_child(_world)
	await get_tree().physics_frame
	_world.apply_map(MapDef.oenbelli())
	await get_tree().physics_frame

	# ⚠️ **按图给的出击半径**（不是全局 `SPAWN_RADIUS`）。奥恩贝利 = 90 000 m。
	var r: float = _world.match_spawn_radius()
	var alt: float = WorldBuilder.PLAYER_START_ALT
	var alt_e: float = WorldBuilder.ENEMY_START_ALT
	print("==== 常量 ====")
	print("出击半径（match_spawn_radius） = %.0f m" % r)
	print("  （全局 SPAWN_RADIUS = %.0f m，那是非城市图的）" % WorldBuilder.SPAWN_RADIUS)
	print("PLAYER_START_ALT  = %.0f m（**下限**，实际值取地形 + SPAWN_CLEARANCE）" % alt)
	print("ENEMY_START_ALT   = %.0f m（**绝对下限**；" % alt_e)
	print("                   相对玩家的高差由 ENEMY_ABOVE_PLAYER = %.0f m 给）"
		% WorldBuilder.ENEMY_ABOVE_PLAYER)
	print("SPAWN_CLEARANCE   = %.0f m" % WorldBuilder.SPAWN_CLEARANCE)
	print("CITY_HILL_IN/OUT  = %.0f / %.0f m  AMP = %.0f m"
		% [WorldBuilder.CITY_HILL_IN, WorldBuilder.CITY_HILL_OUT,
			WorldBuilder.CITY_HILL_AMP])

	_report("玩家出生点", SPAWN_ANGLE_DEG, r, alt)
	_report("敌机出生点", ENEMY_ANGLE_DEG, r, alt_e)

	# ---- 成对关系：`main.gd` 用的是 `spawn_point_foe()` ----
	var player_actual := _world.spawn_point(SPAWN_ANGLE_DEG, r, alt)
	var foe_actual := _world.spawn_point_foe(player_actual, ENEMY_ANGLE_DEG, r)
	print("")
	print("==== 成对出生（玩家 → 敌机）====")
	print("玩家实际标高 %.1f m ⇒ 敌机 %.1f m（**高差 %.1f m**，ENEMY_ABOVE_PLAYER = %.0f）"
		% [player_actual.y, foe_actual.y, foe_actual.y - player_actual.y,
			WorldBuilder.ENEMY_ABOVE_PLAYER])

	# ---- 沿整条出生环扫一圈：这是"出生点高不高"的真实分布 ----
	print("")
	print("==== 出生环（r = %.0f m）逐角度地形高度 ====" % r)
	print("角度   地形高度(m)   实际标高(m)  余量(m)  干燥  方位")
	var worst_clear := 1.0e9
	var worst_ang := 0.0
	var max_h := -1.0e9
	var min_h := 1.0e9
	var buried := 0
	var n := 0
	for i in 72:
		var ang := -180.0 + 360.0 * float(i) / 72.0
		var p := _ring(ang, r)
		var h: float = WorldBuilder._city_landform(p.x, p.z, MapDef.CityLayout.OENBELLI)
		var dry: bool = WorldBuilder.city_is_dry(p.x, p.z, MapDef.CityLayout.OENBELLI)
		var actual := _world.spawn_point(ang, r, alt)
		var clear := actual.y - h
		n += 1
		max_h = maxf(max_h, h)
		min_h = minf(min_h, h)
		if clear <= 0.0:
			buried += 1
		if clear < worst_clear:
			worst_clear = clear
			worst_ang = ang
		print("%7.1f  %11.1f  %11.1f  %7.1f  %s  %s"
			% [ang, h, actual.y, clear, "是" if dry else "否", _quad(p.x, p.z)])
	print("")
	print("地形高度区间   : %.1f … %.1f m" % [min_h, max_h])
	print("余量最小点     : 角度 %.1f°，余量 %.1f m" % [worst_ang, worst_clear])
	print("**埋在山里**的环上角度数 : %d / %d" % [buried, n])
	print("⇒ 判定：%s" % ("**出生点会被埋进山体**" if buried > 0 else "出生点在所有方位都在地面之上"))
	get_tree().quit(0)


## 打印单个出生点的读数。
func _report(label: String, ang: float, radius: float, altitude: float) -> void:
	var p := _ring(ang, radius)
	var h: float = WorldBuilder._city_landform(p.x, p.z, MapDef.CityLayout.OENBELLI)
	var dry: bool = WorldBuilder.city_is_dry(p.x, p.z, MapDef.CityLayout.OENBELLI)
	var water: bool = WorldBuilder.is_water_at(p.x, p.z, MapDef.CityLayout.OENBELLI)
	var hills: float = WorldBuilder._city_hills(p.x, p.z, MapDef.CityLayout.OENBELLI)
	print("")
	print("==== %s（角度 %.1f°）====" % [label, ang])
	print("世界坐标 (x, z)  = (%.0f, %.0f)   半径 %.0f m"
		% [p.x, p.z, sqrt(p.x * p.x + p.z * p.z)])
	print("地形高度         = %.1f m   （其中丘陵项 %.1f m）" % [h, hills])
	print("请求标高         = %.1f m" % altitude)
	print("离地余量（请求） = **%.1f m**  ⇒ %s"
		% [altitude - h, "**在地下**" if altitude - h <= 0.0 else "在地上"])
	# ---- 实际出生点：走 `spawn_point()`，这是 `main.gd` 真正用的那一个 ----
	var actual := _world.spawn_point(ang, radius, altitude)
	print("实际出生标高     = **%.1f m**（离地余量 **%.1f m**，SPAWN_CLEARANCE = %.0f）"
		% [actual.y, actual.y - h, WorldBuilder.SPAWN_CLEARANCE])
	print("干燥 / 规划为水  = %s / %s" % ["是" if dry else "否", "是" if water else "否"])


func _ring(angle_deg: float, radius: float) -> Vector3:
	var a := deg_to_rad(angle_deg)
	return Vector3(cos(a) * radius, 0.0, sin(a) * radius)


func _quad(x: float, z: float) -> String:
	var ns := "北" if z < 0.0 else "南"
	var ew := "西" if x < 0.0 else "东"
	return ew + ns
