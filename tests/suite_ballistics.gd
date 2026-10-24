class_name SuiteBallistics
extends RefCounted
## 弹道解算测试。提前量算错的表现是"永远打不中"，而不是报错 —— 必须有断言。

static func run(t: T) -> void:
	t.suite("Ballistics / 提前量")
	_intercept(t)
	t.suite("Ballistics / 视场角与逃逸锥")
	_angles(t)
	t.suite("Ballistics / 辅助瞄准的权重（单位契约）")
	_aim_assist(t)


static func _intercept(t: T) -> void:
	# --- 目标静止：直接打当前位置 ---
	var p := Ballistics.intercept_point(Vector3.ZERO, Vector3(1000, 0, 0), Vector3.ZERO, 1400.0)
	t.near(p.distance_to(Vector3(1000, 0, 0)), 0.0, 0.001, "静止目标的提前量即其当前位置")

	# --- 横向穿越：解出来的点必须同时被"弹丸"和"目标"在同一时刻到达 ---
	var cases := [
		{"from": Vector3.ZERO, "tp": Vector3(1200, 0, 0), "tv": Vector3(0, 0, 220), "s": 1400.0},
		{"from": Vector3(0, 3000, 0), "tp": Vector3(800, 3100, -1600), "tv": Vector3(-150, 40, 260), "s": 1400.0},
		{"from": Vector3(0, 3000, 0), "tp": Vector3(-2400, 2600, 900), "tv": Vector3(310, -60, -120), "s": 900.0},
	]
	for c: Dictionary in cases:
		var from: Vector3 = c["from"]
		var tp: Vector3 = c["tp"]
		var tv: Vector3 = c["tv"]
		var s: float = c["s"]
		var hit := Ballistics.intercept_point(from, tp, tv, s)
		var t_shell := from.distance_to(hit) / s
		var t_target := tp.distance_to(hit) / maxf(tv.length(), 0.001)
		t.near(t_shell, t_target, 0.02, "弹丸与目标同时到达提前量点")

	# --- 目标比弹快且在远离：无解，退化为打当前位置 ---
	var no_sol := Ballistics.intercept_point(Vector3.ZERO, Vector3(1000, 0, 0), Vector3(2000, 0, 0), 1400.0)
	t.near(no_sol.distance_to(Vector3(1000, 0, 0)), 0.0, 0.001, "追不上的目标退化为打当前位置")

	# --- 迎头接近：提前量应落在目标与我方之间 ---
	var head_on := Ballistics.intercept_point(
		Vector3.ZERO, Vector3(1500, 0, 0), Vector3(-300, 0, 0), 1400.0)
	t.between(head_on.x, 0.0, 1500.0, "迎头目标的提前量落在我方与目标之间")
	t.gt(head_on.x, 1200.0, "迎头目标的提前量接近但不到目标位置")


static func _angles(t: T) -> void:
	t.near(Ballistics.angle_off_boresight(Vector3.FORWARD, Vector3.FORWARD), 0.0, 0.001,
		"正前方偏角为 0")
	t.near(Ballistics.angle_off_boresight(Vector3.FORWARD, Vector3.RIGHT), 90.0, 0.001,
		"正右方偏角为 90°")
	t.near(Ballistics.angle_off_boresight(Vector3.FORWARD, Vector3.BACK), 180.0, 0.001,
		"正后方偏角为 180°")
	t.near(Ballistics.angle_off_boresight(Vector3.FORWARD, Vector3.ZERO), 0.0, 0.001,
		"零向量偏角视为 0（不产生 NaN）")

	# 逃逸锥
	t.ok(Ballistics.is_fleeing(Vector3.ZERO, Vector3(1000, 0, 0), Vector3(200, 0, 0)),
		"背向远离 = 在逃逸")
	t.not_ok(Ballistics.is_fleeing(Vector3.ZERO, Vector3(1000, 0, 0), Vector3(-200, 0, 0)),
		"迎头接近 = 未逃逸")

	t.near(Ballistics.time_to_impact(Vector3.ZERO, Vector3(1400, 0, 0), 1400.0), 1.0, 0.0001,
		"1400 m / 1400 m·s⁻¹ = 1 s")


## 辅助瞄准的权重函数（`FlightBody.aim_assist_weight`）。
##
## ⚠️ 这一组量的是**单位契约**，不是"手感好不好"。
##
## **现状（2026-10-03 用 `tools/probe_aim_follow.gd` 实测坐实）**：
##   `aim_assist_weight()` 的形参是**弧度**（函数内部拿 `deg_to_rad()` 去比常数），
##   而唯一的调用点 `FlightBody.aim_point()` 喂进去的是
##   `Ballistics.angle_off_boresight()` 的返回值 —— 那个函数返回的**是度**。
##   ⇒ 真实偏角 > 0.0436° 时权重一律 0.0 ⇒ **辅助瞄准实际是死代码**：
##     有目标时 `to_bore.slerp(to_lead, 0) == to_bore`，弹道恒等于机头/准星方向。
##
## **为什么不顺手把单位改对**：用户的硬要求是"射击方向跟随鼠标操控的准星"
##   （`README.md` 需求 4）。把单位改对 = 在目标附近一个锥内**自动带提前量**，
##   弹道就不再严格跟随准星 —— 那是**另一个手感方案**，必须先由用户拍板。
##   所以这里把**现状**钉成断言：谁改了单位，下面两条现状锚点会红，
##   改的人必须同时更新这一组 + 出一张真机图（工程规矩）。
static func _aim_assist(t: T) -> void:
	# ---- 函数自身的契约（入参 = 弧度）----
	t.near(FlightBody.aim_assist_weight(0.0), 1.0, 0.0001, "正对（0 rad）→ 权重 1.0")
	t.near(FlightBody.aim_assist_weight(deg_to_rad(2.5)), 1.0, 0.0001,
		"偏 2.5°（= 0.0436 rad）→ 权重仍 1.0（`AIM_ASSIST_SNAP_DEG` 之内完全代瞄）")
	t.near(FlightBody.aim_assist_weight(deg_to_rad(4.0)), 0.667, 0.005,
		"偏 4.0° 落在斜坡 1/3 处 → 0.667（线性、无跳变）")
	t.near(FlightBody.aim_assist_weight(deg_to_rad(7.0)), 0.0, 0.0001,
		"偏 7.0°（`AIM_ASSIST_CONE_DEG`）→ 权重 0.0")
	t.near(FlightBody.aim_assist_weight(deg_to_rad(40.0)), 0.0, 0.0001,
		"锥外（40°）→ 0.0（不产生负值）")
	t.gt(FlightBody.aim_assist_weight(deg_to_rad(3.0)),
		FlightBody.aim_assist_weight(deg_to_rad(6.0)), "斜坡段单调递减（不许出现回勾）")

	# ---- 调用点的真实单位 = 度 ⇒ 权重恒为 0 ----
	var deg1 := Ballistics.angle_off_boresight(
		Vector3.FORWARD, Vector3(sin(deg_to_rad(1.0)), 0.0, -cos(deg_to_rad(1.0))))
	t.near(deg1, 1.0, 0.001,
		"（前置）`angle_off_boresight` 把 1° 的偏角返回成 **1.0（度）**，不是 0.0175 rad")
	t.near(FlightBody.aim_assist_weight(deg1), 0.0, 0.0001,
		"⚠️ 现状锚点：真实偏角 1°（度）直接喂进去 → 权重 0.0 ⇒ 辅助瞄准不生效")
	t.near(FlightBody.aim_assist_weight(6.39), 0.0, 0.0001,
		"⚠️ 现状锚点：6.39°（横移 1000 m/s 所需提前角，见设计文档 §1.2）→ 0.0。"
		+ "设计文档按 0.136 算过那一格 —— 那是把入参当**度**算了，真读数恒为 0.0")
