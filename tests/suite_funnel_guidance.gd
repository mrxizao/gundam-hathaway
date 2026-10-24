class_name SuiteFunnelGuidance
extends RefCounted
## **浮游导弹的跟踪能力**（轮 15：用户「浮游导弹的跟踪能力减弱 25%」）。
##
## ## 「跟踪能力」在这里指什么
##
## 制导的**整条转向角速度曲线** `rate(a) = maxf(turn_rate − turn_decay·a, TURN_FLOOR)`
##（`Missile._physics_process`）。「减弱 25%」的可验证含义就是**这条曲线整体乘 0.75**。
##
## ## 为什么判据是**比值**，不是「2.55 / 0.03」这两个数
##
## 抄两个魔法数字进测试什么都不证明：下次有人手改衰减（或把下限抬到 2.0），
## 测试照样绿，而「−25%」已经不成立了。所以①③两节断言的都是**比值**。
##
## ## ⚠️ 这条测试**抓出过一次真错**（写在这里，因为这就是本套件存在的理由）
##
## 实现的第一版**只缩了上限**、留着 `turn_decay = 0.04` —— 那是把曲线**平移** −0.85，
## 不是**缩放**。于是实际减弱幅度随弹龄漂移：age 0 s 是 −25.0%、age 14 s 是 −30.0%。
## ①节那条"逐点核比值"当场红在 `age = 0.00 s`。
## **只断言一个常数的话，这个错会一路绿到底。**
##
## ## 四节
##
##   ① 常量与账：「−25%」是一个乘 0.75 的关系，逐点核（含最坏点）
##   ② 真路径：`Missile.funnel()` 造出来的弹确实带新值（常量改了但没接上，是常见事故）
##   ③ **真跑一帧物理**：量到的转角 = 新 rate × delta，且**不是**旧 rate × delta
##   ④ 有意**不动**的东西：弹速 / 展开段 / 加速 / 引信 / 抗干扰 / **普通导弹**

const ALT := 3000.0


static func run(t: T, host: Node) -> void:
	t.suite("FunnelGuidance / −25% 的账")
	_ledger(t)
	t.suite("FunnelGuidance / 真路径：funnel() 造出来的弹")
	await _real_path(t, host)
	t.suite("FunnelGuidance / 真跑一帧物理：量到的转角")
	await _measured_turn(t, host)
	t.suite("FunnelGuidance / 有意不动的东西")
	await _untouched(t, host)


# ============================================================ ① 账

static func _ledger(t: T) -> void:
	t.near(Missile.FUNNEL_TURN_RATE, 2.55, 1e-9, "浮游导弹的转向角速度**上限** = 2.55 rad/s")
	t.near(Missile.FUNNEL_TURN_DECAY, 0.03, 1e-9,
		"衰减 = 0.03 rad/s² —— **它也乘了 0.75**（只缩上限是「平移」不是「减弱 25%」，见套件头）")
	t.near(Missile.FUNNEL_TURN_RATE / Missile.FUNNEL_TURN_RATE_WAS, 0.75, 1e-9,
		"上限：新 / 改前（%.1f）= %.4f"
			% [Missile.FUNNEL_TURN_RATE_WAS,
				Missile.FUNNEL_TURN_RATE / Missile.FUNNEL_TURN_RATE_WAS])
	t.near(Missile.FUNNEL_TURN_DECAY / Missile.FUNNEL_TURN_DECAY_WAS, 0.75, 1e-9,
		"衰减：新 / 改前（%.2f）= %.4f"
			% [Missile.FUNNEL_TURN_DECAY_WAS,
				Missile.FUNNEL_TURN_DECAY / Missile.FUNNEL_TURN_DECAY_WAS])
	t.near(Missile.TURN_FLOOR, 0.55, 1e-9, "转向下限仍是 0.55 rad/s（本轮没动它）")

	# 下限什么时候咬住？两条曲线都要到 66 s 以外，而寿命只有 14 s ⇒ 全程都是未截断的直线。
	var lifetime_probe := Missile.new()
	var life := lifetime_probe.lifetime
	lifetime_probe.free()
	var age_old := (Missile.FUNNEL_TURN_RATE_WAS - Missile.TURN_FLOOR) \
		/ Missile.FUNNEL_TURN_DECAY_WAS
	var age_new := (Missile.FUNNEL_TURN_RATE - Missile.TURN_FLOOR) / Missile.FUNNEL_TURN_DECAY
	t.gt(age_old, life, "改前曲线 %.2f s 才碰到下限（寿命 %.0f s）⇒ 改前全程是未截断的直线"
		% [age_old, life])
	t.gt(age_new, life, "改后曲线 %.2f s 才碰到下限 ⇒ 改后也全程是直线" % age_new)

	# **逐点核比值** —— 这条才是「全程 −25%」的真正判据。
	# ⚠️ 初值不能写 1.0：`absf(1.0 − 0.75) = 0.25` 比任何真实点的偏差都大，
	# 于是循环里的 `if` 一次都不命中、`worst` 永远是那个假初值（判据退化成"必红"）。
	# 必须**取自 a = 0 那一点**。
	var worst := Missile.FUNNEL_TURN_RATE / Missile.FUNNEL_TURN_RATE_WAS
	var arg := 0.0
	var a := 0.0
	while a <= life:
		var old := maxf(Missile.FUNNEL_TURN_RATE_WAS - Missile.FUNNEL_TURN_DECAY_WAS * a,
			Missile.TURN_FLOOR)
		var new := maxf(Missile.FUNNEL_TURN_RATE - Missile.FUNNEL_TURN_DECAY * a,
			Missile.TURN_FLOOR)
		var r := new / old
		if absf(r - 0.75) > absf(worst - 0.75):
			worst = r
			arg = a
		a += 0.25
	t.near(worst, 0.75, 1e-9,
		"寿命内最坏那一点（age = %.2f s）的比值仍是 %.9f —— **全程** −25%%" % [arg, worst])
	print(("  [R15] 浮游导弹跟踪：上限 %.2f→%.2f rad/s、衰减 %.2f→%.2f rad/s²（各 ×%.2f）；"
		+ "寿命 %.0f s 内最低比值 %.6f（下限 %.1f 要到 %.1f s 才咬住）")
		% [Missile.FUNNEL_TURN_RATE_WAS, Missile.FUNNEL_TURN_RATE,
			Missile.FUNNEL_TURN_DECAY_WAS, Missile.FUNNEL_TURN_DECAY,
			Missile.FUNNEL_TURN_RATE / Missile.FUNNEL_TURN_RATE_WAS,
			life, worst, Missile.TURN_FLOOR, age_new])


# ============================================================ ② 真路径

static func _real_path(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), true)
	var foe := _new_unit(c, 1, Vector3(3000, ALT, 0))

	var m := Missile.funnel(c, Vector3(0, ALT, 0), Vector3(0, 0, -1), foe, me)
	t.ok(m != null, "（前提）浮游导弹造得出来")
	if m == null:
		_teardown(c)
		return
	t.near(m.turn_rate, Missile.FUNNEL_TURN_RATE, 1e-9,
		"`funnel()` 造出来的弹带着新上限 %.2f（**改的是常量不是字段** —— 常量与调用点没接上就红在这里）"
			% m.turn_rate)
	t.near(m.turn_decay, Missile.FUNNEL_TURN_DECAY, 1e-9, "……也带着新衰减 %.2f" % m.turn_decay)
	t.eq(m.damage_type, Damage.Type.FUNNEL, "仍是浮游导弹类型（没误伤普通导弹的分支）")

	# 普通导弹必须**没被带跑**。
	var plain := Missile.spawn(c, Vector3(0, ALT, 0), Vector3(0, 0, -1), foe, me)
	t.near(plain.turn_rate, 2.1, 1e-9, "普通导弹的转向上限仍是默认 2.1（本轮的改动没有漏过去）")
	t.near(plain.turn_decay, 0.055, 1e-9, "普通导弹的衰减仍是默认 0.055")
	t.gt(Missile.FUNNEL_TURN_RATE, plain.turn_rate,
		"**减弱 25%% 之后浮游导弹仍然比普通导弹灵**（%.2f > %.2f）—— 否则这条需求就改过头了"
			% [Missile.FUNNEL_TURN_RATE, plain.turn_rate])
	_teardown(c)


# ============================================================ ③ 真跑一帧物理

## 量**真正发生的**转角，而不是读字段。
##
## 摆法：弹朝 `-Z` 出膛，靶放在 `+X` 3000 m ⇒ 一开始偏轴 **90°**（远超单帧转角），
## 所以 `step = minf(rate·delta, angle)` 取的一定是 `rate·delta`，量到的就是 rate 本身。
static func _measured_turn(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), true)
	var foe := _new_unit(c, 1, Vector3(3000, ALT, 0))

	var m := Missile.funnel(c, Vector3(0, ALT, 0), Vector3(0, 0, -1), foe, me)
	if m == null:
		t.ok(false, "（前提）浮游导弹造得出来")
		_teardown(c)
		return

	# 飞到展开段结束之后：`deploy_time` 内不制导，太早量到的是 0。
	var guard := 0
	while m._age < m.deploy_time + 0.05 and guard < 400:
		await host.get_tree().physics_frame
		guard += 1
	t.ok(m._age >= m.deploy_time,
		"（前提）已经飞出展开段（age = %.3f s ≥ deploy %.2f s）" % [m._age, m.deploy_time])

	var fwd0: Vector3 = -m.global_transform.basis.z
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	await host.get_tree().physics_frame
	var fwd1: Vector3 = -m.global_transform.basis.z
	var measured := fwd0.angle_to(fwd1)
	# `_age` 在 `_physics_process` 开头就加过本帧 delta ⇒ 帧末读到的就是**本帧用的**那个值。
	var age := m._age
	var rate_new := maxf(m.turn_rate - m.turn_decay * age, Missile.TURN_FLOOR)
	var rate_old := maxf(Missile.FUNNEL_TURN_RATE_WAS - Missile.FUNNEL_TURN_DECAY_WAS * age,
		Missile.TURN_FLOOR)
	print(("  [R15] 浮游导弹真跑一帧：age %.3f s，实测转角 %.5f rad（= %.3f°）；"
		+ "新 rate %.4f × delta %.5f = %.5f rad；旧 %.5f rad ⇒ 比值 %.4f")
		% [age, measured, rad_to_deg(measured), rate_new, delta, rate_new * delta,
			rate_old * delta, measured / (rate_old * delta)])

	t.gt(measured, 0.0001, "（前提）它**真的转了**（不是没制导、也不是已经对准）")
	t.near(measured, rate_new * delta, rate_new * delta * 0.03,
		"实测转角 = 新 rate × 物理帧长（%.5f ≈ %.5f rad，容差 3%%）" % [measured, rate_new * delta])
	t.lt(measured, rate_old * delta * 0.999,
		"……而且**明显小于**旧 rate × 帧长（%.5f < %.5f）—— 这就是「跟踪变钝了」的可观测含义"
			% [measured, rate_old * delta])
	t.near(measured / (rate_old * delta), 0.75, 0.005,
		"实测转角 / 旧 rate 下的转角 = %.4f ≈ 0.75（−25%%）" % (measured / (rate_old * delta)))

	_teardown(c)


# ============================================================ ④ 没动的

static func _untouched(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), true)
	var foe := _new_unit(c, 1, Vector3(3000, ALT, 0))
	var m := Missile.funnel(c, Vector3(0, ALT, 0), Vector3(0, 0, -1), foe, me)
	if m == null:
		t.ok(false, "（前提）浮游导弹造得出来")
		_teardown(c)
		return

	# 「跟踪能力」只在**转向**这一根轴上减弱。下面每一项都在另一根轴上，
	# 把它们钉住，是为了让「减弱 25%」不能靠"顺手把别的也调了"蒙过去。
	t.near(m.speed, 90.0, 1e-9, "弹射初速仍是 90 m/s（相对载机）—— 速度不是跟踪能力")
	t.near(m.deploy_time, 0.55, 1e-9, "展开段仍是 0.55 s（「先散开再收拢」的观感来源）")
	t.near(m.max_speed, SuitProfile.missile_speed(), 1e-6,
		"弹速上限仍取自 `SuitProfile.missile_speed()`（全工程唯一真源）")
	t.near(m.fuse_radius, 24.0, 1e-9, "近炸引信半径仍是 24 m（与转向无关）")
	t.near(m.accel_time, 1.7, 1e-9, "出仓后的加速时间仍是 1.7 s（敏捷的另一半，**没动**）")
	t.near(m.damage, 26.0, 1e-9, "伤害仍是 26（这是伤害不是跟踪）")
	t.near(m.decoy_chance, 1.1, 1e-9, "抗干扰仍是默认值（那是「跟谁」不是「跟得多快」）")
	t.near(m.lifetime, 14.0, 1e-9, "寿命仍是 14 s —— ①节那条「曲线够不到下限」的账建在它上面")
	_teardown(c)


# ============================================================ 工具

static func _new_unit(c: Node3D, team: int, pos: Vector3, as_player := false) -> FlightBody:
	var u := FlightBody.new()
	u.team = team
	u.is_player = as_player
	u.profile = SuitProfile.penelope() if team == 0 else SuitProfile.xi()
	u.display_name = "T%d" % team
	u.projectile_container = c
	c.add_child(u)
	u.global_position = pos
	u.max_hp = 400.0
	u.hp = 400.0
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	u.fm.speed = 260.0
	u.fm.throttle = 0.78
	u.fm.align_velocity(u.forward())
	return u


static func _teardown(c: Node) -> void:
	if c != null and is_instance_valid(c):
		c.queue_free()
