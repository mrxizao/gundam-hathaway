extends RefCounted
## 批 11 手感（2026-09-22）：突进感与运动感 —— "更像王牌空战 + 装甲核心"。
##
## 四块用户需求，各一组断言：
##   1. **驾驶/空战能量感**（王牌空战）：`FlightModel.turn_drag` 大过载诱导阻力
##      —— 拉杆转向掉能量（偏航版测点：机头保持水平，排除重力项干扰）、
##      松杆回血、滚转不掉速（滚转不改航向，物理上没有诱导阻力）；
##   2. **QB 爆冲**（装甲核心）：起跑 0.12 s 爆冲段 + 起跑信号恰好发一次
##      （重复点按不重发 —— 没跑起来就没有起跑感）；
##   3. **平移模式转弯侧倾**：左转左压坡（王牌空战式），改出后归零；
##   4. **超级加速 FOV 档 + 喷口爆闪**：进入超级档视野在普通加力之上再开一截；
##      FX.qb_burst 挂节点、按时收口，零向量不炸。
##   6. **超级加速持续微晃**（批 12，用户要求"镜头小晃动 + FOV 大幅提升"）：
##      渐入不跳变、峰值可见但压得住、关抖动设置时安静且回位干净。
##
## ⚠️ 侧倾/QB 都真跑物理帧（`_apply_translate` 的行为，纯函数测不出来）；
##    相机节照 `suite_camera_feedback._fresh()` 的规矩：进树 + 手动关引擎驱动。

static func run(t: T, host: Node) -> void:
	_turn_drag(t)
	await _qb_burst(t, host)
	await _bank(t, host)
	_super_fov(t, host)
	await _super_wobble(t, host)
	await _fx_burst(t, host)


# ---------------------------------------------------------------- 工具

## 一台调好的巡航模型（与 `suite_flight.cruise_model()` 同一套参数思路）：
## 速度钉在巡航点、油门对准"目标速度 = 巡航"—— 松杆后速度会回升，能测回血。
static func _cruise_fm() -> FlightModel:
	var fm := FlightModel.new()
	fm.configure(340.0, 560.0)
	fm.speed = fm.cruise_speed
	fm.throttle = (fm.cruise_speed - fm.min_speed) / (fm.max_speed - fm.min_speed)
	fm.align_velocity(Vector3.FORWARD)
	return fm


# ---------------------------------------------------------------- ① 诱导阻力

static func _turn_drag(t: T) -> void:
	t.suite("MotionFeel / 大过载诱导阻力（能量空战）")
	t.gt(FlightModel.new().turn_drag, 0.0, "turn_drag 参数存在且为正")
	var dt := 1.0 / 60.0
	# ---- A/B：同起点满杆**偏航**一秒 vs 不拉杆 ----
	# 用偏航不用俯仰：机头始终水平，重力沿航迹项两边都是 0，
	# 速度差**只能**来自诱导阻力（俯仰版会混进爬升掉速，测不纯）。
	var pull := _cruise_fm()
	var idle := _cruise_fm()
	var b := Basis.IDENTITY
	for i in 60:
		b = pull.advance(dt, b, Vector3(0, 1, 0))
		idle.advance(dt, Basis.IDENTITY, Vector3.ZERO)
	var gap1: float = idle.speed - pull.speed
	t.gt(gap1, 3.0,
		"满杆转一秒比不转多掉 %.1f m/s —— 急转在花能量（王牌空战的前提）" % gap1)
	# ---- 松杆回血：双方都松杆两秒，差距必须收窄 ----
	for i in 120:
		pull.advance(dt, b, Vector3.ZERO)
		idle.advance(dt, Basis.IDENTITY, Vector3.ZERO)
	var gap2: float = idle.speed - pull.speed
	t.lt(gap2, gap1,
		"松杆后差距 %.2f → %.2f 收窄 —— 阻力只在拉杆时存在，松杆回血" % [gap1, gap2])
	# ---- 滚转不变量：滚转不改航向 ⇒ 没有诱导阻力，速度轨迹与不拉杆一致 ----
	var roll := _cruise_fm()
	var rb := Basis.IDENTITY
	var rolled := false
	for i in 60:
		rb = roll.advance(dt, rb, Vector3(0, 0, 1))
		rolled = rolled or rb.x.dot(Vector3.RIGHT) < 0.999
	t.ok(rolled, "前置：满杆滚转真的滚动了（排除测点空转）")
	t.near(roll.speed, idle.speed, 0.5,
		"滚转满杆一秒速度与不拉杆一致（%.2f vs %.2f）—— 诱导阻力不挂滚转"
			% [roll.speed, idle.speed])


# ---------------------------------------------------------------- ② QB 爆冲

static func _qb_burst(t: T, host: Node) -> void:
	t.suite("MotionFeel / QB 爆冲段 + 起跑信号（真跑物理帧）")
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "QbBurstProbe"
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.controls_enabled = true
	c.add_child(pc)
	pc.assist_on = true
	pc.global_position = Vector3(0, 900, 0)
	for i in 60:
		await host.get_tree().physics_frame
	t.ok(pc.translate_mode, "前置：柯西进入平移模式")
	var hits := [0]
	pc.quick_boost_started.connect(func(_d: Vector3) -> void:
		hits[0] += 1
	)
	var ab := pc.profile.player_boost_speed()
	var qb_want := ab * FlightBody.QB_SPEED_MULT
	pc.request_quick_boost()
	await host.get_tree().physics_frame
	t.ok(pc.translate_dash, "点按请求 → 闪避窗口开启")
	# 爆冲段判别：窗口开始后 9 帧（0.15 s）量速度。
	# 新代码（爆冲 22）：≈ 目标的 95%；旧代码（全程 8.0）：只有 ~70%。
	# 阈值取 0.85 —— 两边都留足余量，谁改掉爆冲段谁立刻红。
	for i in 9:
		await host.get_tree().physics_frame
	t.gt(pc.fm.speed, qb_want * 0.85,
		"爆冲段：0.15 s 内速度已到 QB 目标的 85%%（%.0f / %.0f）—— 起跑是砸到位的"
			% [pc.fm.speed, qb_want])
	t.eq(hits[0], 1, "起跑信号恰好发一次")
	# 窗口中的重复点按：请求被吞、不重发信号
	pc.request_quick_boost()
	for i in 10:
		await host.get_tree().physics_frame
	t.eq(hits[0], 1, "窗口中的重复点按不再发起跑信号")
	pc.free()
	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ---------------------------------------------------------------- ③ 转弯侧倾

static func _bank(t: T, host: Node) -> void:
	t.suite("MotionFeel / 平移模式转弯侧倾（真跑物理帧）")
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "BankProbe"
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.controls_enabled = true
	c.add_child(pc)
	pc.assist_on = true
	pc.global_position = Vector3(0, 900, 0)
	# 假敌机摆在**正左方**（自机朝 −Z 飞 ⇒ 左 = −X）：机头必须向左转。
	var foe := PlayerController.new()
	foe.name = "BankFoe"
	foe.profile = SuitProfile.xi()
	c.add_child(foe)
	foe.global_position = Vector3(-900, 900, 0)
	pc.face_target_override = foe
	# 记录转弯过程中的最大左倾量：up 向量朝"机头左侧"偏了多少。
	var max_left := 0.0
	for i in 90:
		await host.get_tree().physics_frame
		var fwd: Vector3 = -pc.global_transform.basis.z
		var left := Vector3.UP.cross(fwd)
		max_left = maxf(max_left, pc.global_transform.basis.y.dot(left))
	var to_foe: Vector3 = (foe.global_position - pc.global_position).normalized()
	var nose: Vector3 = -pc.global_transform.basis.z
	t.gt(nose.dot(to_foe), 0.5, "前置：机头确实在向左转（dot=%.2f）" % nose.dot(to_foe))
	t.gt(max_left, 0.10,
		"左转时机身向左压坡（最大 %.2f）—— 王牌空战式转弯，不是气垫船" % max_left)
	# 改出：撤掉目标 → 机头不再转 → 侧倾平滑归零（回正，不歪着定格）
	pc.face_target_override = null
	var lean_end := 0.0
	for i in 120:
		await host.get_tree().physics_frame
	var fwd2: Vector3 = -pc.global_transform.basis.z
	lean_end = pc.global_transform.basis.y.dot(Vector3.UP.cross(fwd2))
	t.lt(absf(lean_end), 0.08,
		"改出后侧倾归零（|%.3f| < 0.08）—— 不留歪机身的残态" % absf(lean_end))
	pc.free()
	foe.free()
	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ---------------------------------------------------------------- ④ 超级 FOV 档

static func _super_fov(t: T, host: Node) -> void:
	t.suite("MotionFeel / 超级加速 FOV 档（相机）")
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "SuperFovBody"
	pc.profile = SuitProfile.xi()
	pc.team = 0
	c.add_child(pc)
	pc.set_physics_process(false)   # 冻结机体：fm 的值完全由测试控制
	pc.fm.boosting = true
	pc.fm.speed = 300.0
	var cam := ChaseCamera.new()
	host.add_child(cam)
	cam.set_physics_process(false)
	cam.current = false
	cam.set_target(pc)
	cam.boost_amount = 0.0
	# 普通加力：同速度读数下量一次 FOV
	cam.fov = cam.base_fov
	cam._update_fov(1.0)
	var plain: float = cam.fov
	# 超级加速：只翻 super_boost 开关，速度读数不变 —— FOV 差只能来自新档
	pc.fm.super_boost = true
	cam.fov = cam.base_fov
	cam._update_fov(1.0)
	var sup: float = cam.fov
	t.gt(ChaseCamera.FOV_SUPER_BONUS, 0.0, "FOV_SUPER_BONUS 档位存在且为正")
	# ⚠️ `_update_fov` 是一阶滞后：一次调用只走 `1−exp(−3.5·dt)` 的路程 ——
	# 两次调用同起点同因子，差值 = 档位 × motion_scale × lerp 因子（第一版忘了乘因子）。
	var lerp_f := 1.0 - exp(-3.5 * 1.0)
	t.near(sup - plain, ChaseCamera.FOV_SUPER_BONUS * cam.motion_scale * lerp_f, 0.1,
		"同速度下超级档比普通加力多开 %.1f°（实得 %.1f）—— 超级加速有自己的视野档"
			% [ChaseCamera.FOV_SUPER_BONUS * cam.motion_scale * lerp_f, sup - plain])
	cam.queue_free()
	pc.free()
	c.free()
	await host.get_tree().process_frame


# ---------------------------------------------------------------- ⑥ 超级加速持续微晃

static func _super_wobble(t: T, host: Node) -> void:
	t.suite("MotionFeel / 超级加速持续微晃（相机）")
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "SuperWobBody"
	pc.profile = SuitProfile.xi()
	pc.team = 0
	c.add_child(pc)
	pc.set_physics_process(false)   # 冻结机体：fm 的值完全由测试控制
	pc.fm.boosting = true
	pc.fm.speed = 300.0
	pc.fm.super_boost = true
	var cam := ChaseCamera.new()
	host.add_child(cam)
	cam.set_physics_process(false)
	cam.current = false
	cam.set_target(pc)
	cam.boost_amount = 0.0
	var dt := 1.0 / 60.0
	# ---- 渐入：不能一帧打满（瞬间全幅会读成"挨了一记"）----
	cam._apply_super_wobble(dt)
	t.lt(cam._wob_amount, 0.5,
		"微晃渐入（第一步 %.2f）—— 不跳变，进档不读成挨打" % cam._wob_amount)
	# ---- 走 1 秒：摆动必须真的在画面上，但永远压得住 ----
	# 每帧先把 basis 拉回 desired（模拟 `_physics_process` 里跟随 lerp 做的事），
	# 再叠微晃 —— 与真机一致，测出的是**当帧偏转**而不是累积漂移。
	var max_ang := 0.0
	for i in 60:
		var desired := cam._desired_basis()
		cam.global_transform = Transform3D(desired, cam.global_position)
		cam._apply_super_wobble(dt)
		var ang := cam.global_transform.basis.get_rotation_quaternion() \
			.angle_to(desired.get_rotation_quaternion())
		max_ang = maxf(max_ang, rad_to_deg(ang))
	t.gt(max_ang, 0.08,
		"微晃真的在画面上（峰值 %.3f°）—— 持续小晃，不是没有" % max_ang)
	t.lt(max_ang, 0.6,
		"微晃压得住（峰值 %.3f° < 0.6°）—— 受击/相杀永远盖得过它" % max_ang)
	# ---- 关掉抖动设置：摆动照常渐出、位移照乘 0（无障碍铁律，与 _apply_shake 同规）----
	cam.shake_scale = 0.0
	pc.fm.super_boost = false
	for i in 120:
		var desired2 := cam._desired_basis()
		cam.global_transform = Transform3D(desired2, cam.global_position)
		cam._apply_super_wobble(dt)
	t.lt(cam._wob_amount, 0.01, "关抖动后渐出照走（不把残幅冻在池子里）")
	var final_ang := cam.global_transform.basis.get_rotation_quaternion() \
		.angle_to(cam._desired_basis().get_rotation_quaternion())
	t.lt(rad_to_deg(final_ang), 0.01, "渐出后机位干净归位（不留歪机头的残态）")
	cam.queue_free()
	pc.free()
	c.free()
	await host.get_tree().process_frame


# ---------------------------------------------------------------- ⑤ 喷口爆闪

static func _fx_burst(t: T, host: Node) -> void:
	t.suite("MotionFeel / FX.qb_burst（喷口爆闪）")
	# 零向量不炸（守卫：异常输入也不能把特效层炸掉）
	FX.qb_burst(host, Vector3(500, 300, 0), Vector3.ZERO)
	FX.qb_burst(host, Vector3(1000, 500, 0), Vector3.FORWARD)
	# ⚠️ 同帧同父节点两个爆闪：FX.qb_burst 用 add_child(root, true) 强制可读名
	#（否则 Godot 4 冲突改名按类名生成 "@Node3D@5"，原名整个丢掉）——
	# 第二个的名字是 "QbBurst2"，按**包含**匹配两个都能数到。
	var found := 0
	for ch: Node in host.get_children():
		if String(ch.name).contains("QbBurst"):
			found += 1
	t.eq(found, 2, "qb_burst 挂上了即弃节点（连零向量那次也安全落地）")
	# 按时收口：tween 收口 + 回调 queue_free，等一会儿之后必须干净。
	#
	# ⚠️ **必须按真实时间等，不能按帧数等。** 这一条原本写的是"等 30 个 process 帧"，
	# 而**无头环境的帧率不可控**（实测 30 帧只有 ~0.2 s，且随机器/负载浮动）——
	# 2026-09-25 把爆闪的收口从 0.16 s 延到 0.26 s（为了容下新加的冲击环与火星），
	# 这条断言当场**假红**：特效本身按时收口了，是"帧数≈秒数"这个假设不成立。
	# 凡是"按时收口"的判断都该量时间，帧数只在帧率被钉死的环境里才等价于时间。
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		await host.get_tree().process_frame
	var left := 0
	for ch: Node in host.get_children():
		if String(ch.name).contains("QbBurst") and is_instance_valid(ch) \
				and not ch.is_queued_for_deletion():
			left += 1
	t.eq(left, 0, "爆闪按时收口（不堆积残节点）")
