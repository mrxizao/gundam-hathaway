class_name Ballistics
extends RefCounted
## 纯函数弹道解算 —— 无状态、无随机，便于无头单元测试。


## 解提前量：求最早的时刻 t，使弹丸能在 t 秒后与目标相遇。
##
##   |D + V·t|² = s²·t²   其中 D = 目标位置 − 发射点，V = 目标速度，s = 弹速
##   展开：  (V·V − s²)·t² + 2(D·V)·t + D·D = 0
##
## 无解（目标比弹快且在远离）时退化为"打当前位置"。
static func intercept_point(from: Vector3, target_pos: Vector3, target_vel: Vector3,
		projectile_speed: float) -> Vector3:
	var d := target_pos - from
	var a := target_vel.length_squared() - projectile_speed * projectile_speed
	var b := 2.0 * d.dot(target_vel)
	var c := d.length_squared()

	if absf(a) < 0.0001:
		if absf(b) < 0.0001:
			return target_pos
		var t_lin := -c / b
		if t_lin <= 0.0:
			return target_pos
		return target_pos + target_vel * t_lin

	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return target_pos
	var sq := sqrt(disc)
	var t1 := (-b - sq) / (2.0 * a)
	var t2 := (-b + sq) / (2.0 * a)
	var t := INF
	if t1 > 0.0:
		t = t1
	if t2 > 0.0:
		t = minf(t, t2)
	if t == INF:
		return target_pos
	return target_pos + target_vel * t


## 光束步枪的提前量落点（2026-09-25 两段式弹道专用）。
##
## ## 为什么不能复用 `intercept_point()`
## 那套方程的前提是"弹丸以一个**恒定**速度飞"（真正解的是
## `|target + v·t − from| = projectile_speed · t` 这个二次式）。
## 光束现在**没有"一个弹速"**了：出膛段 2880 m/s、中段 9×10⁴ m/s
##（见 `SuitProfile` 那张三段式弹道的图）。往等速方程里代任何一个数都是错的：
## 代 900 ⇒ 提前量算到天上；代 9×10⁴ ⇒ 等于完全不提前量。
##
## ## 所以改成"飞行时间不动点迭代"
## 飞行时间 `rifle_flight_time(d)` 是距离的单调函数，于是
##   `t ← flight_time(|目标(t) − 炮口|)`
## 迭代几次就是解。而且它收敛得很快 —— 中段快得让 `t` 基本只由**出膛段**决定，
## 对距离几乎不敏感。**没有 `t` 的解（目标在飞离）时**，迭代自然停在某个有限值上，
## 不会像二次式那样返回 INF 或负根。
##
## ## ⚠️ 可观测的变化：提前量**几乎归零**
## 这是弹道改快的必然结果，不是 bug —— 1 km 只要 11 ms，当然不用提前量。
## `suite_combat` 里有一条"提前量落点 ≈ 目标当前位置"的断言盯着它，
## 免得以后有人把它"修"回一个明显的提前量。
##
## `steady > 0` ⇒ 这台机（阿利宙斯）的弹是**匀速**的，飞行时间改用 `d / steady`。
## ⚠️ **必须跟实际弹道读同一个字段**：漏传的话 HUD 的提前量圈会按两段制算，
## 而屏幕上飞的是匀速光柱 —— 正是本文件反复点名的那类偏差。
static func beam_lead_point(from: Vector3, target_pos: Vector3, target_vel: Vector3,
		steady := 0.0) -> Vector3:
	var t := 0.0
	for i in 6:
		t = SuitProfile.rifle_flight_time(from.distance_to(target_pos + target_vel * t), steady)
	return target_pos + target_vel * t


## 目标相对于某朝向的偏角（度）。用于导引头视场判定。
static func angle_off_boresight(boresight: Vector3, to_target: Vector3) -> float:
	if to_target.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(boresight.normalized().angle_to(to_target.normalized()))


## 逃逸锥：目标速度方向与"从发射者指向目标"的夹角 < 90° 说明在远离。
static func is_fleeing(from: Vector3, target_pos: Vector3, target_vel: Vector3) -> bool:
	var los := target_pos - from
	if los.length_squared() < 0.0001:
		return false
	return los.normalized().dot(target_vel) > 0.0


## 命中目标的剩余时间估计（用弹速做一阶近似）。
static func time_to_impact(from: Vector3, target_pos: Vector3, projectile_speed: float) -> float:
	return from.distance_to(target_pos) / maxf(projectile_speed, 0.001)


## 两条**线段**之间的最短距离。
##
## ⚠️ 它存在的理由是"**扫掠**"：导弹对撞如果只拿**每帧的位置**做点距判定，
## 两发高速对头的弹会**在两次采样之间互相穿过去**。以 1134 m/s 的弹速算，
## 对头接近最快 37.8 m/帧；判定半径 48 m 时，最近距离落在 44~48 m 那一小条带的
## 擦过就会被漏掉。用"这一帧从哪走到哪"的两条线段求最近距离，才是把
## 写好的判定半径**真的兑现**。
##
## 算法是标准的两线段最近点：先解最近参数对 (s, t)，再钳到 [0,1]，
## 最后取两个最近点的距离。退化情形（线段长度≈0）单独处理，避免除零。
static func segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return r.length()
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 1e-9:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	return c1.distance_to(c2)


## Conservative broad phase: reject separated swept bounds before the exact segment test.
static func swept_bounds_overlap(a:Vector3,b:Vector3,c:Vector3,d:Vector3,radius:float)->bool:
	return not (minf(a.x,b.x)>maxf(c.x,d.x)+radius or maxf(a.x,b.x)<minf(c.x,d.x)-radius or minf(a.y,b.y)>maxf(c.y,d.y)+radius or maxf(a.y,b.y)<minf(c.y,d.y)-radius or minf(a.z,b.z)>maxf(c.z,d.z)+radius or maxf(a.z,b.z)<minf(c.z,d.z)-radius)
