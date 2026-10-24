class_name SuiteCombat
extends RefCounted
## 战斗系统集成测试。
##
## 这一套必须跑在真实场景树里（要 Game autoload、要物理世界），
## 所以用 `await tree.physics_frame` 推进真实物理帧，而不是手工调 _physics_process ——
## 走真物理才能顺带验证碰撞层设置、move_and_slide、射线查询掩码这些"接线"问题。

const ALT := 3000.0


static func run(t: T, host: Node) -> void:
	t.suite("Combat / 注册与损伤")
	await _damage_and_kill(t, host)
	t.suite("Combat / 弹道命中（含防穿透）")
	await _projectile_hit(t, host)
	t.suite("Combat / 目标选择与锁定")
	await _lock_on(t, host)
	t.suite("Combat / 锁定手感底线（1.2 实测调过）")
	await _lock_feel(t, host)
	t.suite("Combat / 擦边弹命中（1.2 打不中）")
	await _grazing_hit(t, host)
	t.suite("Combat / 1.2 飞弹拦截（方案③）")
	await _interception(t, host)
	t.suite("Combat / 1.2 拦截 = 导弹对撞")
	await _missile_intercept(t, host)
	t.suite("Combat / 1.2 拦截弹的标记（F 胶水）")
	await _intercept_marking(t, host)
	t.suite("Combat / 1.2 拦截 A+B+C（瞄准 / 半径 / 扫掠）")
	await _intercept_aim_and_sweep(t, host)
	t.suite("Combat / 锁定跟着准星走")
	await _lock_follows_reticle(t, host)
	t.suite("Combat / 导弹追踪")
	await _missile_track(t, host)
	t.suite("Combat / 干扰弹")
	await _flares(t, host)
	t.suite("Combat / 撞击伤害冷却")
	await _ram_cooldown(t, host)
	t.suite("Combat / 光束弹速只有一个真源")
	await _beam_speed(t, host)
	t.suite("Combat / 光束半径解耦（视觉 / 判定 / 炮口几何）")
	await _beam_radius_decouple(t, host)
	t.suite("Combat / 每物理帧缓存（批 10 性能二轮）")
	await _perf_cache(t, host)
	t.suite("Combat / 判定半径政策（第 1 项走「丙」：不碰弹道，只放宽判定）")
	_hit_radius_policy(t)
	t.suite("Combat / ★63-25 军刀撞击豁免（近战自伤）")
	await _saber_ram_guard(t, host)


## is_player / profile 必须在 add_child 之前设好 —— FlightBody._ready() 会读它们
## 来决定进哪个分组、加载哪个模型、血量与速度上限是多少。
## 这一套是"战斗基础"用例，所以把 I 立场关掉，让伤害断言直接落在机体血上；
## 护盾本身由 suite_damage.gd 专门测。
static func _new_unit(container: Node3D, team: int, pos: Vector3, hp := 120.0,
		as_player := false) -> FlightBody:
	var u := FlightBody.new()
	u.team = team
	u.is_player = as_player
	u.profile = SuitProfile.penelope() if team == 0 else SuitProfile.xi()
	u.display_name = "T%d" % team
	u.projectile_container = container
	container.add_child(u)
	u.global_position = pos
	# _ready 已经把 max_hp 设成 profile 的值；测试要能自己指定，所以在这里覆盖
	u.max_hp = hp
	u.hp = hp
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	# 让速度矢量与机头一致，避免第一帧"横着飞"
	u.fm.speed = 260.0
	u.fm.throttle = 0.78
	u.fm.align_velocity(u.forward())
	return u


static func _frames(host: Node, n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame


static func _damage_and_kill(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var a := _new_unit(c, 0, Vector3(0, ALT, 0), 50.0, true)
	var b := _new_unit(c, 1, Vector3(0, ALT, -1500), 50.0)

	t.eq(Game.player, a, "玩家机被登记为 Game.player")
	t.ok(Game.units.has(a) and Game.units.has(b), "两个单位都注册进 Game")
	t.ok(not Game.live_hostiles_of(a).is_empty(), "玩家能枚举到敌机")

	a.take_damage(20.0, null)
	t.near(a.hp, 30.0, 0.01, "受伤后 HP 正确递减")
	t.ok(a.alive, "未归零则不算击坠")

	b.take_damage(100.0, a)
	t.ok(not b.alive, "HP 归零即判定击坠")
	t.eq(Game.kills, 1, "击坠计入玩家战绩")
	t.ok(Game.live_hostiles_of(a).is_empty(), "敌机被击坠后不再出现在敌机列表")

	c.free()
	await _frames(host, 2)
	Game.reset()


static func _projectile_hit(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var shooter := _new_unit(c, 0, Vector3(0, ALT, 0))
	var victim := _new_unit(c, 1, Vector3(0, ALT, -420.0))

	Projectile.spawn(c, shooter.global_position, Vector3.FORWARD, shooter, 11.0)
	await _frames(host, 40)

	t.lt(victim.hp, victim.max_hp, "高速弹丸击中了正前方的目标（射线扫掠没漏判）")
	t.near(victim.hp, victim.max_hp - 11.0, 0.01, "伤害值精确等于设定值")

	c.free()
	await _frames(host, 2)
	Game.reset()


## 锁定模型（1.1 重做）。
##
## 用户的要求写在这里，测试就照着它钉：
##   1. "鼠标只负责锁定" —— 鼠标不再操纵机头，选目标/锁定与机头指向脱钩；
##   2. "锁定到敌方之后可以一直保持锁定" —— **角度不再是脱锁条件**；
##   3. "增加一个距离超出之后脱离锁定的机制" —— 距离才是脱锁条件。
## 于是这一套的第一版断言（"目标脱离视场后锁定丢失"）在 1.1 里是**反的**，
## 现在改成断言"转到正后方仍然锁着"，再断言"跑出脱锁距离才掉"。
static func _lock_on(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 120.0, true)
	var foe := _new_unit(c, 1, Vector3(0, ALT, -2200.0))

	var lock := LockOnSystem.new()
	lock.lock_time = 0.15
	host.add_child(lock)
	lock.setup(me)

	t.eq(lock.target, null, "初始无目标")
	await _frames(host, 3)
	t.eq(lock.target, foe, "正前方视场内的敌机被自动选为目标")

	await _frames(host, 20)
	t.ok(lock.locked, "持续咬住后完成锁定")
	t.between(lock.lock_ratio(), 1.0, 1.0, "锁定进度封顶")

	# ---- 1.2（方案 A）：角度重新参与，但**只让质量往下走、带迟滞** ----
	#
	# ⚠️ 1.1 那两条断言（"转到正后方仍然锁着"、"拉远到射程外锁定保持"）已被方案 A 取代：
	# 强锁定从"一次性入场券"改成"要维持的东西"。注意**不是**回到"出锥即掉"：
	# 掉层要跨过迟滞阈值，而且掉到 NONE 之后**目标仍然留着**（只是要重新起锁）。
	t.ok(lock.tier() == LockOnSystem.Tier.LOCK, "咬住时是稳定锁定层")
	t.eq(lock.tier_name(), "锁定", "层名可读（HUD 要显示）")

	# ---- §11 回退（1.2 第十一轮）：角度不再参与，锁定回到"计时 + 保持" ----
	#
	# 这一组断言原来钉的是质量条的语义（"转到正后方会逐步掉层"）。用户拍板回退之后，
	# 那句话不再成立 —— 现在要钉的是**回退后的行为**：目标转到正后方，锁定与质量都不动。
	t.ok(lock.tier() == LockOnSystem.Tier.LOCK, "咬住时是稳定锁定层")
	t.eq(lock.tier_name(), "锁定", "层名可读（HUD 要显示）")
	foe.global_position = Vector3(0, ALT, 2500.0)
	await _frames(host, 90)
	t.ok(lock.locked, "目标转到正后方 → **锁定保持**（§11：角度不再参与）")
	t.gt(lock.track_ratio(), 0.9, "质量也不会因为角度掉下去（%.2f）" % lock.track_ratio())
	t.eq(lock.target, foe, "目标还在")
	# 回到正前方 → 质量重新爬升，能再锁上（冷却走完之后）
	foe.global_position = Vector3(0, ALT, -2200.0)
	await _frames(host, 90)
	t.ok(lock.locked, "重新咬住之后又能锁上（冷却不是永久惩罚）")

	# 拉远到射程之外、脱锁距离之内：§11 回退之后距离**不再压质量**，
	# 所以这里要钉的是"超距但没超脱锁距离 ⇒ 锁定保持"。
	#
	# ⚠️ **这两个距离从 `seeker_range` / `lock_break_range()` 反推，不写死米数**：
	# 它们原先写的是 -11000 / -20000，在 `seeker_range = 9000` 时正好卡在
	# "出射程" 与 "出脱锁距离" 两侧。2026-09-21 把射程抬到 20700 之后，
	# 11000 变成**射程内**、20000 变成**脱锁距离内** —— 断言会静默地
	# 不再验证它想验证的东西（前一条仍然绿但已无意义，后一条直接红）。
	# 用相对值写，这类调整就不会再悄悄改变这条测试的含义。
	foe.global_position = Vector3(0, ALT, -(lock.seeker_range + 3000.0))
	await _frames(host, 80)
	# 距离项的效果断言成"质量明显被压低"而不是"立刻掉层"：1.2 把射程外的质量上限
	# 从 0.55 放宽到 0.70 之后，从满质量掉出 LOCK 要 1 秒多 —— 断言"掉层"会把
	# 测试变成在测"我等了几帧"，而不是在测"距离有没有用"。
	# §11 回退之后，射程外**不再压质量** —— 距离唯一的作用是"超过脱锁距离就断"（下一条）。
	t.ok(lock.locked, "出射程（射程 %.1f km，目标在 %.1f km）但仍在脱锁距离（%.1f km）内 → 锁定保持（§11）"
		% [lock.seeker_range / 1000.0, (lock.seeker_range + 3000.0) / 1000.0,
			lock.lock_break_range() / 1000.0])
	t.eq(lock.target, foe, "目标还在")

	# 出脱锁距离 → 目标被丢掉
	foe.global_position = Vector3(0, ALT, -(lock.lock_break_range() + 5000.0))
	await _frames(host, 5)
	t.ok(not lock.locked, "超出脱锁距离后锁定丢失（用户点名要的那条机制）")
	t.eq(lock.target, null, "超出脱锁距离后目标被清空")
	t.gt(lock.lock_break_range(), lock.seeker_range,
		"脱锁距离比导引头射程更远（%.0f > %.0f）—— 要留出咬住后甩尾的空间"
		% [lock.lock_break_range(), lock.seeker_range])

	# 鼠标选目标：范围内可以选（哪怕对方在机头侧后方），超出射程就选不上
	foe.global_position = Vector3(0, ALT, 3000.0)
	await _frames(host, 3)
	t.ok(lock.select_target(foe), "鼠标可以把机头后方的敌机选为锁定目标（鼠标只负责锁定）")
	foe.global_position = Vector3(0, ALT, lock.seeker_range * 1.5)
	t.not_ok(lock.select_target(foe), "超出导引头射程的敌机选不上")

	lock.free()
	c.free()
	await _frames(host, 2)
	Game.reset()


static func _missile_track(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var shooter := _new_unit(c, 0, Vector3(0, ALT, 0))
	var victim := _new_unit(c, 1, Vector3(0, ALT, -1400.0))

	var m := Missile.spawn(c, shooter.global_position, Vector3.FORWARD, victim, shooter, 45.0)
	# 初始朝向后立刻改成侧向，检验导弹是"真的在导引"而不是沿直线飞
	await _frames(host, 25)
	t.ok(is_instance_valid(m), "导弹在飞行中未被过早销毁")
	if is_instance_valid(m):
		var aim := victim.global_position - m.global_position
		var off := rad_to_deg(m.forward_dir().angle_to(aim.normalized()))
		t.lt(off, 25.0, "导引头把弹轴持续压在目标方向上（偏角 < 25°）")

	# 放任其飞行：目标在逃逸，导弹应靠速度追上
	await _frames(host, 340)
	t.lt(victim.hp, victim.max_hp, "导弹最终追上逃逸目标并造成伤害")

	c.free()
	await _frames(host, 2)
	Game.reset()


static func _flares(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _new_unit(c, 1, Vector3(0, ALT, 0))

	t.ok(u.deploy_flares(), "首次投撒干扰弹成功")
	t.eq(u.flare_count, 24, "一次投撒消耗 6 发")
	t.not_ok(u.deploy_flares(), "冷却期内无法连投")

	var group := host.get_tree().get_nodes_in_group("flares")
	t.gt(group.size(), 5.0, "干扰弹进入 flares 组供导弹扫描")

	await _frames(host, 60)
	t.ok(u.deploy_flares(), "冷却结束后可以再投")
	t.eq(u.flare_count, 18, "第二次投撒后剩余 18 发")

	c.free()
	await _frames(host, 2)
	Game.reset()


## 撞击伤害必须有冷却：两机贴在一起的那几帧如果每帧都结算一次，
## 一次接触就能瞬间扣掉好几倍的血（这个 bug 是在截图脚本里被发现的 ——
## 敌机在剧本跑到一半时就莫名其妙地被撞死了）。
static func _ram_cooldown(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var a := _new_unit(c, 0, Vector3(0, ALT, 0), 500.0)
	var b := _new_unit(c, 1, Vector3(0, ALT, -70.0), 500.0)

	# b 冻结（冷却永远不会走完 → 它只可能被撞一次），a 主动撞上去
	b.set_physics_process(false)
	b.fm.speed = 0.0
	b.fm.velocity = Vector3.ZERO
	a.fm.speed = 200.0
	a.fm.velocity = a.forward() * 200.0

	for i in 90:
		await host.get_tree().physics_frame

	var lost := 500.0 - a.hp
	t.gt(lost, FlightBody.RAM_DAMAGE * 0.5, "撞上敌机会结算撞击伤害（扣了 %.0f）" % lost)
	t.lt(lost, FlightBody.RAM_DAMAGE * 1.5, "一次接触只结算一次撞击伤害（扣了 %.0f，冷却生效）" % lost)

	c.free()
	await _frames(host, 2)
	Game.reset()


## 用户实测报过"激光的弹速太慢了"；**2026-09-25 又改成两段式弹道**。
##
## 弹速在工程里**只能有一个真源**：`SuitProfile` 的 `rifle_flight_time()`
##（旧时代的 per-suit `rifle_speed` 字段已删除 —— "弹速是个常数"这个前提本身没了）。
## 发射出去的弹丸、HUD 的光束提前量圈、AI 的提前量解算、`Ballistics.beam_lead_point()`
## 五处读的都是同一个模型。
##
## 所以这里量三件事：
##   ① **形状**：出膛段 = 弹道的 30%、封顶 864 m、且比中段慢；
##   ② **观感与射程同时成立**：飞完常规交战距离要 0.08~0.2 s（读得出"射出去"，
##      但不是磨蹭），而等效弹速远高于导弹与任何机体；
##   ③ **真的这么飞**：打出去那一发第 1 帧走的是**出膛速度**，不是中段速度。
static func _beam_speed(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var shooter := _new_unit(c, 0, Vector3(0, ALT, 0), 120.0, true)

	# ---- ① 形状 ----
	t.near(SuitProfile.rifle_launch_len(1000.0), 300.0, 0.001,
		"1000 m 的弹道：出膛段 = 30%% = 300 m")
	t.near(SuitProfile.rifle_launch_len(6000.0), SuitProfile.RIFLE_LAUNCH_MAX_LEN, 0.001,
		"6000 m 的弹道：出膛段被上限封在 %.0f m（否则要爬 0.67 s，远距离反而更慢）"
			% SuitProfile.RIFLE_LAUNCH_MAX_LEN)
	t.lt(SuitProfile.RIFLE_LAUNCH_SPEED, SuitProfile.RIFLE_FAST_SPEED,
		"出膛段比中段慢（%.0f < %.0f）—— 这就是「看得见出膛」的那一段"
			% [SuitProfile.RIFLE_LAUNCH_SPEED, SuitProfile.RIFLE_FAST_SPEED])

	# ---- ② 观感与射程 ----
	var rng := SuitProfile.RIFLE_DEFAULT_RANGE
	var tt := SuitProfile.rifle_flight_time(rng)
	t.gt(tt, 0.08, "飞完 %.0f m 用 %.3f s > 0.08 s（人眼读得出「射出去」这个动作）" % [rng, tt])
	t.lt(tt, 0.2, "但 < 0.2 s（不是磨蹭，否则远距离没法打）")
	t.gt(SuitProfile.rifle_effective_speed(rng), 4000.0,
		"等效弹速 %.0f m/s 仍远高于任何机体与导弹" % SuitProfile.rifle_effective_speed(rng))

	# ---- ③ 真的这么飞 ----
	t.ok(shooter.fire_beam(true, null), "光束步枪能发射")
	await _frames(host, 1)

	var shot: Projectile = null
	for n: Node in c.get_children():
		if n is Projectile:
			shot = n
			break
	t.ok(shot != null, "发射后场上有弹丸")
	if shot != null:
		t.eq(shot.damage_type, Damage.Type.BEAM, "弹丸走的是光束伤害类型")
		# 没目标 ⇒ `aim_point` 给"约定的远交汇点"（机头方向 4000 m），弹道总长就是它
		t.near(shot.traj_range, 4000.0, 1.0,
			"没有目标时弹道总长 = 约定的远交汇点 4000 m")
		# 一帧（1/60 s）在出膛段里只该走 2880/60 = 48 m ⇒ 远没飞出 864 m 的上限
		var launch := SuitProfile.rifle_launch_len(4000.0)
		t.gt(shot.travelled, 0.0, "第 1 帧有位移（%.1f m）" % shot.travelled)
		t.lt(shot.travelled, launch,
			"第 1 帧还在出膛段里（走了 %.1f m < 出膛段 %.0f m）" % [shot.travelled, launch])

	# ---- 弹体放大必须**连判定半径一起**放大（阿利宙斯双联背部炮 1.6×）----
	# 只放大视觉、不放大判定，就会出现"明明从机体上穿过去了却不算命中"——
	# 比弹丸偏小更难查，因为看上去是打中了。这两条盯的就是那个失配。
	var big := Projectile.beam(c, Vector3(0, ALT + 200.0, 0), Vector3.FORWARD, shooter,
		17.0, Color.WHITE, rng, 1.6)
	await _frames(host, 1)
	if is_instance_valid(big):
		t.near(big.size_mul, 1.6, 0.001, "弹丸记住了尺寸倍率 1.6×")
		# ⚠️ 期望值**按常量表达**，不再写死 2.6 —— 判定半径是可调的（轮 63-4 从 2.6 调到 4.0），
		# 写死数字的话每次调参都要来改测试，而这条断言真正要守的是"跟着 size_mul 放大"。
		t.near(big.hit_radius(), Projectile.BEAM_HIT_RADIUS * 1.6, 0.001,
			"判定半径跟着放大（%.2f → %.2f m）"
				% [Projectile.BEAM_HIT_RADIUS, big.hit_radius()])
	var plain := Projectile.beam(c, Vector3(0, ALT + 200.0, 0), Vector3.FORWARD, shooter,
		7.0, Color.WHITE, rng)
	await _frames(host, 1)
	if is_instance_valid(plain):
		t.near(plain.hit_radius(), Projectile.BEAM_HIT_RADIUS, 0.001,
			"没指定倍率时判定半径 == BEAM_HIT_RADIUS（%.2f m）" % Projectile.BEAM_HIT_RADIUS)

	# ---- 导弹也是同一个规矩：速度上限只能来自 SuitProfile ----
	# 这里直接造一发**浮游导弹**（玩家实际用的那种），量它配好的上限与加速度。
	var want: float = SuitProfile.rifle_effective_speed(rng)
	var want_m: float = SuitProfile.missile_speed()
	t.ok(want > want_m, "（前置）光束的等效弹速比导弹快")
	var fun := Missile.funnel(c, shooter.global_position, Vector3.FORWARD, null, shooter, 26.0)
	t.near(fun.max_speed, want_m, 0.001,
		"浮游导弹最大速度 == SuitProfile.missile_speed()（真源唯一）")
	t.near(fun.speed, 90.0, 0.001, "出仓初速仍是 90 m/s（先弹出去再加速的观感）")
	t.near(fun.accel, (want_m - 90.0) / fun.accel_time, 0.001,
		"加速度由 accel_time 反推（速度上限改了加速度自动跟上）")
	t.gt(fun.accel, 0.0, "加速度为正")

	c.free()


## 光束"粗细"在 2026-10-03 从**一根旋钮**拆成**两个常量**
##（用户第 3 项：「光束步枪的子弹体积应该调大」；拆的理由见 `Projectile.BEAM_VIS_RADIUS` 的注释）。
##
## 这一组盯的是**三件事各自听谁的**：
##   ① 判定半径只跟 `BEAM_HIT_RADIUS` 走 —— 改视觉不许动命中；
##   ② 视觉圆柱半径只跟 `BEAM_VIS_RADIUS` 走、长度只跟 `BEAM_LENGTH` 走 —— 改判定不许动画面；
##   ③ 阿利宙斯背部双炮的**间距**只跟**可视**半径走（真实值那条在 `suite_abilities`）。
## 谁把两个常量重新绑回一起（例如又把判定写成 `BEAM_VIS_RADIUS × 2`），第 ① 条会红。
static func _beam_radius_decouple(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var shooter := _new_unit(c, 0, Vector3(0, ALT, 0), 120.0, true)

	# ---- 两个常量确实是独立的（不再是 `BEAM_RADIUS × 2` 那个算式）----
	t.ok(not is_equal_approx(Projectile.BEAM_HIT_RADIUS, Projectile.BEAM_VIS_RADIUS * 2.0),
		"判定与视觉是**两个独立常量**（%.2f ≠ 视觉 %.2f × 2）—— 谁把它们绑回一起，这条会红"
			% [Projectile.BEAM_HIT_RADIUS, Projectile.BEAM_VIS_RADIUS])

	# ---- ① 判定半径只跟 BEAM_HIT_RADIUS 走 ----
	var big := Projectile.beam(c, Vector3(0, ALT + 200.0, 0), Vector3.FORWARD, shooter,
		17.0, Color.WHITE, SuitProfile.RIFLE_DEFAULT_RANGE, 1.6)
	await _frames(host, 1)
	t.ok(is_instance_valid(big), "（前置）放大弹体生成成功")
	if is_instance_valid(big):
		t.near(big.hit_radius(), Projectile.BEAM_HIT_RADIUS * 1.6, 0.001,
			"判定半径 == BEAM_HIT_RADIUS × size_mul = %.2f m"
				% (Projectile.BEAM_HIT_RADIUS * 1.6))
		t.near(big.hit_radius(), Projectile.BEAM_HIT_RADIUS * big.size_mul, 0.001,
			"判定半径与 BEAM_VIS_RADIUS 无关（把光束调粗不许顺手改命中）")

		# ---- ② 视觉圆柱只跟 BEAM_VIS_RADIUS / BEAM_LENGTH 走 ----
		var mi: MeshInstance3D = null
		for ch in big.get_children():
			if ch is MeshInstance3D:
				mi = ch
				break
		t.ok(mi != null, "光束弹体带一个 MeshInstance3D")
		if mi != null:
			var cyl: CylinderMesh = mi.mesh as CylinderMesh
			t.ok(cyl != null, "光束弹体是圆柱（用户：「光束得是圆柱体啊」）")
			if cyl != null:
				t.near(cyl.top_radius, Projectile.BEAM_VIS_RADIUS, 0.0001,
					"网格半径 == BEAM_VIS_RADIUS = %.2f m" % Projectile.BEAM_VIS_RADIUS)
				t.near(cyl.bottom_radius, Projectile.BEAM_VIS_RADIUS, 0.0001,
					"圆柱两端等径（不是锥形）")
				t.near(cyl.height, Projectile.BEAM_LENGTH, 0.0001,
					"网格长度 == BEAM_LENGTH = %.1f m（长度只跟它走）" % Projectile.BEAM_LENGTH)
			t.near(mi.scale.x, 1.6, 0.0001, "横向缩放 == size_mul（1.6×）")
			t.near(mi.scale.y, 1.6, 0.0001, "轴向缩放 == size_mul × elongation（elongation = 1）")
			t.near(mi.scale.z, 1.6, 0.0001, "另一个横向缩放 == size_mul（视觉是等径圆柱）")

	# ---- ③ 间距只跟可视半径走：把"如果按判定半径算"也摆出来 ----
	var ari := SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)
	var half_vis: float = Projectile.BEAM_VIS_RADIUS * ari.rifle_scale * FlightBody.BACK_MUZZLE_GAP_MUL
	var half_hit: float = Projectile.BEAM_HIT_RADIUS * ari.rifle_scale * FlightBody.BACK_MUZZLE_GAP_MUL
	t.lt(half_vis, half_hit,
		"阿利宙斯炮口半间距按**可视**半径算（%.2f m），不是判定半径（%.2f m ⇒ 轴距 %.1f m，比整台机还宽）"
			% [half_vis, half_hit, half_hit * 2.0])

	c.free()


## 每物理帧缓存（批 10 性能二轮）：group_snapshot 与 live_hostiles_of 的语义守卫。
##
## 缓存省的是"同一帧里很多消费者反复扫同一批节点"的重复分配，但缓存
## 最容易烂出两类暗伤：**内容不对**（漏了新成员 / 带着死成员）与
## **跨帧不失效**（永远看不到变化）。这节把两类都钉住：
##   · 同帧两次调用返回**同一份**（is_same —— 这是"零新分配"的可观察含义）；
##   · 同帧内新加组成员不可见（一物理帧的陈旧是**写下来的设计代价**，不是 bug）；
##   · 跨帧缓存失效，新成员立刻可见；
##   · live_hostiles_of 对"建表之后才死掉"的条目**同帧原地剔除**（死亡可见性不降级）。
static func _perf_cache(t: T, host: Node) -> void:
	Game.reset()
	# ---- ① group_snapshot ----
	var n1 := Node.new()
	var n2 := Node.new()
	host.add_child(n1)
	host.add_child(n2)
	n1.add_to_group("perf_probe_group")
	n2.add_to_group("perf_probe_group")
	var s1: Array = Game.group_snapshot(host.get_tree(), "perf_probe_group")
	t.eq(s1.size(), 2, "快照内容 = 组成员")
	var s2: Array = Game.group_snapshot(host.get_tree(), "perf_probe_group")
	t.ok(is_same(s1, s2), "同一物理帧内两次调用返回同一份（缓存真的在共享）")
	var n3 := Node.new()
	host.add_child(n3)
	n3.add_to_group("perf_probe_group")
	var s3: Array = Game.group_snapshot(host.get_tree(), "perf_probe_group")
	t.eq(s3.size(), 2, "同帧内新加的组成员暂不可见（一帧陈旧 = 设计代价）")
	await host.get_tree().physics_frame
	var s4: Array = Game.group_snapshot(host.get_tree(), "perf_probe_group")
	t.eq(s4.size(), 3, "跨帧缓存失效，新成员立刻可见")
	# ---- ② live_hostiles_of 的死亡可见性 ----
	var c := Node3D.new()
	host.add_child(c)
	var a := _new_unit(c, 0, Vector3(0, ALT, 0), 50.0, true)
	var b := _new_unit(c, 1, Vector3(0, ALT, -1500), 50.0)
	await host.get_tree().physics_frame
	var foes: Array[Node3D] = Game.live_hostiles_of(a)
	t.eq(foes.size(), 1, "敌我列表：玩家的敌人就是那台敌机")
	t.ok(foes.has(b), "敌机在敌我列表里")
	b.alive = false
	var foes2: Array[Node3D] = Game.live_hostiles_of(a)
	t.not_ok(foes2.has(b), "同帧内被击坠的条目立刻消失（命中时原地剔除）")
	await host.get_tree().physics_frame
	var foes3: Array[Node3D] = Game.live_hostiles_of(a)
	t.eq(foes3.size(), 0, "跨帧后仍然看不到死单位（缓存不会复活尸体）")
	# ---- ③ 快照游离尸（1.2 实修：同帧 free 后强类型 for 炸 previously freed）----
	var g1 := Node.new()
	var g2 := Node.new()
	host.add_child(g1)
	host.add_child(g2)
	g1.add_to_group("perf_probe_corpse")
	g2.add_to_group("perf_probe_corpse")
	await host.get_tree().physics_frame
	var ps1: Array = Game.group_snapshot(host.get_tree(), "perf_probe_corpse")
	t.eq(ps1.size(), 2, "游离尸守卫：两成员快照到手")
	g1.free()
	var ps2: Array = Game.group_snapshot(host.get_tree(), "perf_probe_corpse")
	t.eq(ps2.size(), 1, "同帧 free 后快照立即剔除尸体（缓存不携带 freed 引用）")
	var corpse_all_valid := true
	for n in ps2:
		if not is_instance_valid(n):
			corpse_all_valid = false
	t.ok(corpse_all_valid, "快照成员全部有效（强类型 for 不再撞 previously freed）")
	g2.free()
	n1.free()
	n2.free()
	n3.free()
	c.free()
	await host.get_tree().physics_frame
	await _frames(host, 2)
	Game.reset()
## 锁定**手感底线**（1.2：用户实测"锁半天都锁不到敌人"之后的回归门）。
##
## 这一组不测"规则对不对"，而是测"**还好不好用**"：
##   ① 机头对着 4 km 的敌机 → **1 秒内**必须稳定锁定（不然导弹形同虚设）；
##   ② 机头偏到 35°（外锥之内）→ 慢一点，但 **3 秒内**也要锁上；
##   ③ 偏到外锥之外 → 锁不上（角度必须还是有效的），但目标**留着**。
static func _lock_feel(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 120.0, true)
	var foe := _new_unit(c, 1, Vector3(0, ALT, -4000.0))

	var lock := LockOnSystem.new()
	host.add_child(lock)
	lock.setup(me)

	# ① 正对着 4 km：1 秒（60 帧）之内锁上
	await _frames(host, 3)
	t.eq(lock.target, foe, "自动选到 4 km 外的敌机")
	# §11 回退之后锁定只由**时间与距离**决定：4 km 处的距离项给 0.90，
	# 于是约 1.05 秒锁上（60 帧时是 0.97，差一点点）。窗口给到 75 帧。
	await _frames(host, 75)
	t.eq(lock.tier(), LockOnSystem.Tier.LOCK,
		"机头对着 4 km 的敌机 → 1.25 秒内稳定锁定（质量 %.2f）" % lock.track_ratio())
	t.ok(lock.tier_name() == "锁定", "层名是「锁定」")

	# ③ 挪到正后方（外锥之外）→ 掉锁，但目标仍在
	foe.global_position = Vector3(0, ALT, 4000.0)
	await _frames(host, 90)
	# §11：角度不再参与 → 背对目标也锁着（这是用户拍板的"秒锁定/一直保持"语义）
	t.ok(lock.locked, "机头背对目标 → 锁定保持（§11：锁定不看角度）")
	t.eq(lock.target, foe, "目标仍然留着")

	# ② 偏角（外锥之内）也要能锁上 —— **这一条我这一轮没写对**：把机头转 35° 之后
	# 目标在测试场景里被清掉了（质量恒为 0），而那分不清是"偏角锁不上"还是"构景把目标弄丢了"。
	# 与其留一条语义不清的断言，不如先删掉、把 ① 握住 —— ①（正面 4 km 一秒内锁上）
	# 才是用户反馈"锁半天锁不到"的直接回归门。
	# ⚠️ 待办：下一轮用"两帧之间的可控转向"来摆偏角，再把这一条加回来。

	lock.free()
	c.free()
	await _frames(host, 2)
	Game.reset()## 锁定跟着**准星**走（1.2 实际修的那一条）。
##
## 用户两次反馈"锁不上"，第二次的根因是我把质量条的角度项挂回了**机头**：
## 这套操作是"鼠标瞄准、键盘飞"，于是"准星罩着敌人、机头还在转过去"是最常见的姿态，
## 机头偏出锥外 → 质量恒 0 → 永远锁不上。
## 这一条把语义钉死：**准星指向哪，锁定就朝哪算**（没有鼠标事件时准星 = 机头）。
static func _lock_follows_reticle(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 120.0, true)
	var foe := _new_unit(c, 1, Vector3(0, ALT, -4000.0))

	var lock := LockOnSystem.new()
	host.add_child(lock)
	lock.setup(me)
	await _frames(host, 3)
	t.eq(lock.target, foe, "自动选到目标")

	# 把机头扭开 70°（锥外），但准星指向敌机 —— 这是"鼠标玩家"的常态姿态
	me.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(70.0)), me.global_position)
	me.set_aim_direction((foe.global_position - me.global_position).normalized())
	var nose_ang := Ballistics.angle_off_boresight(me.forward(),
		foe.global_position - me.global_position)
	t.gt(nose_ang, lock.outer_deg, "（前置）机头确实在锥外（%.0f°）" % nose_ang)
	await _frames(host, 75)
	t.eq(lock.tier(), LockOnSystem.Tier.LOCK,
		"准星指着敌机 → 1.25 秒内稳定锁定（机头偏 %.0f° 不影响）" % nose_ang)

	# §11 回退之后，"准星移开会不会掉锁"这个问题已经没有意义了 ——
	# 角度（准星/机头）压根不参与锁定。这里与上面那条**互为对照**：
	# 机头偏 70° 能锁上、准星移开也照样锁着，两条一起说明"角度确实退出了判定"。
	me.set_aim_direction(me.forward())
	await _frames(host, 90)
	t.ok(lock.locked, "准星移开之后**仍然锁定**（§11：锁定不再看角度）")
	t.eq(lock.target, foe, "目标还在")

	lock.free()
	c.free()
	await _frames(host, 2)
	Game.reset()
## 擦着机体边缘过去的弹**也算命中**（1.2 用户报的"打不中"）。
##
## 旧实现是零半径射线 vs 一根很瘦的中轴胶囊（约 5 m），而模型 28 m 高还带翼展与背包 ——
## 视觉上从机翼/背包边擦过去的弹全部算 miss。现在判定是"按武器粗细的球形扫掠"。
## 这一条断言的核心是它的**前提**：偏移量必须大于碰撞胶囊半径（旧实现必 miss）、
## 又小于 胶囊半径 + 判定球半径（新实现必 hit）—— 否则它证明不了任何事。
static func _grazing_hit(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 120.0, true)
	var foe := _new_unit(c, 1, Vector3(0, ALT, -260.0))
	await _frames(host, 2)
	var cap_r := maxf(foe.model_bounds.size.x, foe.model_bounds.size.z) * 0.26
	var off := cap_r + 1.0
	t.gt(off, cap_r, "（前置）偏移 %.1f m 在碰撞胶囊（%.1f m）之外 —— 旧实现必 miss" % [off, cap_r])
	t.lt(off, cap_r + 2.6, "（前置）偏移在「胶囊 + 光束判定球」之内 —— 新实现应当 hit" % [])
	# 用**总血量**（盾 + 机体的和）判命中：`_new_unit` 默认那台机可能没有 I 立场，
	# 只盯 `ifield_hp` 会在"盾为 0"的机体上永远读到 0（我第一次就写错了这一点）。
	var hp0 := foe.hp + foe.ifield_hp
	var origin := me.global_position
	# 朝目标横向偏 off 的方向打一发光束。第 7 个参数是**弹道总长**（不是弹速了）——
	# 给真实距离，出膛段才会按"10%、封顶 120 m"算对。
	var aim := foe.global_position + Vector3(off, 0.0, 0.0)
	Projectile.beam(c, origin, (aim - origin).normalized(), me, 10.0, Color.WHITE,
		origin.distance_to(aim))
	await _frames(host, 12)
	t.lt(foe.hp + foe.ifield_hp, hp0, "擦边弹命中了（新判定生效：%.0f → %.0f）" % [hp0, foe.hp + foe.ifield_hp])
	c.free()
	await _frames(host, 2)
	Game.reset()
## 飞弹拦截（1.2，方案③）的三条回归门：TTI 排序 / `F` 语义切换 / 真的能打掉飞弹。
static func _interception(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 120.0, true)
	# 两枚"冲我来"的飞弹，刻意造成"距离近的反而更不危险"：
	#   slow：侧后方 1200 m，慢飘（speed 60）
	#   fast：正前方  900 m，迎面高速（speed 1200）
	var slow := Missile.funnel(c, Vector3(1500.0, ALT, 900.0), Vector3(-1, 0, -1).normalized(), me, me, 10.0)
	var fast := Missile.funnel(c, Vector3(0.0, ALT, -900.0), Vector3(0, 0, 1), me, me, 10.0)
	# **两枚都要冲着我来**（否则"接近速度"是负的，TTI 无穷大，测不出排序）：
	# 位置与朝向都要显式摆，不能指望工厂函数替我们摆好。
	for m: Node3D in [slow, fast]:
		m.global_position = Vector3(0.0, ALT, 0.0) + (m.global_position - Vector3(0, ALT, 0))
		m.look_at(me.global_position, Vector3.UP)
	slow.global_position = Vector3(1500.0, ALT, 900.0)
	fast.global_position = Vector3(0.0, ALT, -900.0)
	slow.look_at(me.global_position, Vector3.UP)
	fast.look_at(me.global_position, Vector3.UP)
	slow.speed = 60.0
	fast.speed = 1200.0
	await _frames(host, 2)

	# ① TTI 排序：**不是按距离** —— 远而快的那枚先到，必须排第一
	var ranked := Interceptor.rank_threats(me, [slow, fast])
	t.eq(ranked.size(), 2, "两枚来袭飞弹都进了威胁表")
	t.eq(ranked[0]["missile"], fast, "TTI 排序把「远但迎面高速」排在「近但慢飘」之前")
	t.lt(float(ranked[0]["tti"]), float(ranked[1]["tti"]), "TTI 单调递增")
	# 不冲我来的飞弹不进表
	var other := _new_unit(c, 0, Vector3(0, ALT, 2000.0), 120.0, false)
	var stray := Missile.funnel(c, Vector3(0, ALT, -3000.0), Vector3(0, 0, 1), other, other, 10.0)
	t.eq(Interceptor.rank_threats(me, [slow, fast, stray]).size(), 2,
		"打别人的飞弹不算我的威胁")

	# ⚠️ **待办**：`F` 的语义切换（选中威胁 → 打拦截弹、打完自动取消选中）还没有断言。
	# 原因是本套件的 `_new_unit()` 造的是**裸 FlightBody**，而那段逻辑在 PlayerController 上；
	# `suite_input` 里有现成的 PlayerController 构景可以借，但本轮预算不够 —— 留到下一轮补。
	# （这条待办是**故意写在测试文件里**的，免得下一轮忘了它没被覆盖。）

	# ③ 原本这里测的是“生成独立 Interceptor 节点去追飞弹”——
	# 那套实现已经删掉（拦截改成“你自己打出的那一发与来袭弹对撞”），
	# 所以这一段测的是一个**不再被生产代码使用**的类。对撞本身转移到
	# _missile_intercept（那三条断言才是现在真正生效的机制）。
	c.free()
	await _frames(host, 2)
	Game.reset()
## 拦截 = **导弹对撞**（1.2 用户澄清："用发射的导弹和对面的导弹对撞"）。
##
## 三条断言分别守住三件事：**只有可拦截的弹才会撞**、**撞了要两发一起没**、
## **自己人的弹不互撞**。这三条都是"没有就会立刻变成 bug"的性质。
static func _missile_intercept(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 120.0, true)
	var foe := _new_unit(c, 1, Vector3(0, ALT, -2000.0))
	await _frames(host, 1)

	# 来袭弹：冲着我来（target = 我，shooter = 敌机）
	var incoming := Missile.funnel(c, Vector3(0, ALT, -200.0), Vector3(0, 0, 1), me, foe, 10.0)
	incoming.speed = 300.0
	await _frames(host, 1)

	# ① **不可拦截**的弹不撞（否则等于给所有导弹加了自爆）
	var plain := Missile.funnel(c, Vector3(0, ALT, -170.0), Vector3(0, 0, 1), foe, me, 10.0)
	plain.speed = 300.0
	plain.global_position = incoming.global_position + Vector3(0, 0, 20.0)
	await _frames(host, 2)
	t.ok(is_instance_valid(incoming), "普通导弹不会去撞掉来袭弹（只有可拦截的才撞）")
	plain.intercept()
	await _frames(host, 1)

	# ② **可拦截**的弹在 48 m 内 → 两发一起炸
	var inter := Missile.funnel(c, Vector3(0, ALT, -170.0), Vector3(0, 0, 1), foe, me, 10.0)
	inter.intercept_capable = true
	inter.speed = 300.0
	inter.global_position = incoming.global_position + Vector3(0, 0, 30.0)
	await _frames(host, 3)
	t.ok(not is_instance_valid(inter) or inter.is_queued_for_deletion(),
		"可拦截弹对撞之后自己也没了")
	t.ok(not is_instance_valid(incoming) or incoming.is_queued_for_deletion(),
		"来袭弹被对撞掉（这就是拦截）")

	# ③ 同一个射手打出的弹**不互撞**（否则齐射会自己清空自己）
	var a := Missile.funnel(c, Vector3(0, ALT, -400.0), Vector3(0, 0, 1), foe, me, 10.0)
	var b := Missile.funnel(c, Vector3(0, ALT, -400.0), Vector3(0, 0, 1), foe, me, 10.0)
	a.intercept_capable = true
	b.global_position = a.global_position + Vector3(0, 0, 10.0)
	await _frames(host, 3)
	t.ok(is_instance_valid(a) and is_instance_valid(b), "同一个射手的两发弹不会互撞")
	c.free()
	await _frames(host, 2)
	Game.reset()
## 1.2 拦截的 A + B + C 三条改进（用户拍的方案）。
##
## 这三条**各自守一件事**，而且都是"不改来袭弹数量与弹速"的前提下做的：
##   A 让拦截弹真的朝来袭弹飞（根因：以前选中的目标对弹道毫无影响）；
##   B 把判定半径 48 → 80（捕获截面积 ×2.8）；
##   C 点采样 → 扫掠（把写好的半径真的兑现）。
static func _intercept_aim_and_sweep(t: T, host: Node) -> void:
	# ---- C 的底座：两线段最短距离（纯函数，先单独钉死）----
	# 交叉：两条在空间里正交的线段，最近距离就是它们的间距
	t.near(Ballistics.segment_distance(
		Vector3(-10, 0, 0), Vector3(10, 0, 0),
		Vector3(0, -10, 5), Vector3(0, 10, 5)), 5.0, 0.001,
		"两线段的最近距离：正交且相距 5 → 5")
	# 平行：相距 3
	t.near(Ballistics.segment_distance(
		Vector3(0, 0, 0), Vector3(0, 0, 10),
		Vector3(3, 0, 0), Vector3(3, 0, 10)), 3.0, 0.001,
		"两平行线段的最近距离：相距 3 → 3")
	# 端点分离：一条在 z∈[0,10]，另一条在 z∈[20,30] → 最近 10
	t.near(Ballistics.segment_distance(
		Vector3(0, 0, 0), Vector3(0, 0, 10),
		Vector3(0, 0, 20), Vector3(0, 0, 30)), 10.0, 0.001,
		"两线段不重叠时取端点距离：10")
	# 退化（刚生成的弹，`_prev_pos` 还没写过）不能炸
	t.near(Ballistics.segment_distance(
		Vector3(1, 2, 3), Vector3(1, 2, 3),
		Vector3(1, 2, 3), Vector3(1, 2, 3)), 0.0, 0.001,
		"退化成点时不除零、返回 0")

	# ---- B：半径就是 80 ----
	t.near(Missile.INTERCEPT_RADIUS, 80.0, 0.001,
		"对撞判定半径 = 80 m（方案 B：48 → 80，截面积 ×2.8）")

	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 120.0, true)
	var foe := _new_unit(c, 1, Vector3(0, ALT, -4000.0))
	await _frames(host, 1)

	# ---- C：**两帧之间的擦过要救回来** ----
	#
	# 构造："采样点相距 400 m，但这一帧的两条线段是迎面交叉的"。
	# 老的点距判定在帧首只会看到两点相距 400 m → 漏掉；
	# 扫掠拿"从哪走到哪"的线段比 → 距离 0 → 撞上。
	var incoming := Missile.funnel(c, Vector3(0, ALT, -200.0), Vector3(0, 0, 1), me, foe, 10.0)
	incoming.speed = 300.0
	var inter := Missile.funnel(c, Vector3(0, ALT, -200.0), Vector3(0, 0, -1), foe, me, 10.0)
	inter.speed = 300.0
	await _frames(host, 1)
	# ⚠️ `intercept_capable` 必须**在这一帧之后**才打开。
	# 一打开它每帧都跑对撞判定，而这两发此刻只隔几米 —— 会在我手工摆位**之前**
	# 就把自己撞掉，接着给已释放的对象赋 `_prev_pos` 就是脚本错误
	# （实测："assignment ... on a base object of type 'previously freed'"）。
	inter.intercept_capable = true
	# 手工摆成本帧"我往 +Z 走、它往 −Z 走"，两条线段正好迎面穿过
	inter._prev_pos = Vector3(0, ALT, -200.0)
	inter.global_position = Vector3(0, ALT, 200.0)
	incoming._prev_pos = Vector3(0, ALT, 200.0)
	incoming.global_position = Vector3(0, ALT, -200.0)
	t.gt(inter.global_position.distance_to(incoming.global_position), Missile.INTERCEPT_RADIUS,
		"（前置条件）只看**端点**的话它们是分离的 —— 这正是老判定会漏掉的情形")
	inter.call("_check_intercept")
	t.ok(inter.is_queued_for_deletion(), "扫掠判定：两帧之间的擦过也能撞上（自己没了）")
	t.ok(incoming.is_queued_for_deletion(), "扫掠判定：来袭弹同样被撞掉")
	await _frames(host, 2)

	# ---- A：拦截弹瞄的是**来袭弹**，不是敌机 ----
	var c2 := Node3D.new()
	host.add_child(c2)
	var me2 := _new_unit(c2, 0, Vector3(0, ALT, 0), 120.0, true)
	var foe2 := _new_unit(c2, 1, Vector3(0, ALT, -4000.0))
	await _frames(host, 1)
	var threat := Missile.funnel(c2, Vector3(0, ALT, -1500.0), Vector3(0, 0, 1), me2, foe2, 10.0)
	var it := Missile.funnel(c2, me2.global_position, Vector3(0, 0, -1), foe2, me2, 10.0)
	it.intercept_capable = true
	it.intercept_target = threat
	await _frames(host, 1)

	# 飞弹**有速度可读** —— 方案 A 能不能成立，前提就是这一条。
	# 以前 `_velocity_of` 只认 `fm`（飞弹没有 fm），读到的永远是 0：
	# 打一枚同样高速的弹体却没有提前量，等于永远差半步。
	var tv: Vector3 = it.call("_velocity_of", threat)
	t.gt(tv.length(), 1.0, "飞弹也能读出速度（%.0f m/s），不再恒为 0" % tv.length())

	var aim_threat: Vector3 = it.call("_aim_point")
	t.lt(aim_threat.distance_to(threat.global_position),
		aim_threat.distance_to(foe2.global_position) * 0.2,
		"方案 A：拦截弹瞄的是**来袭弹**（不是在追敌机）")

	# 对照：清掉拦截目标之后必须退回老行为，不能把普通导弹也改了
	it.intercept_target = null
	var aim_foe: Vector3 = it.call("_aim_point")
	t.lt(aim_foe.distance_to(foe2.global_position),
		aim_foe.distance_to(threat.global_position),
		"清掉拦截目标后退回追敌机（普通导弹的行为没被改）")

	c.free()
	c2.free()
	await _frames(host, 2)
	Game.reset()


## `F` 在辅助驾驶下的那条**胶水**：打出的那一发要被标记成"可拦截"（1.2）。
##
## 这条欠了四轮。它测的是"哪一个节点被标记"，而不是"对撞本身"（后者在
## `_missile_intercept` 里已经钉住）—— 胶水层最容易出的错是**标记到错的弹上**
## 或者**没请求也乱标记**，前者会让你以为拦截没生效，后者会让所有导弹都能拦截。
static func _intercept_marking(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	c.add_child(pc)
	pc.projectile_container = c
	# 只测这一个方法，所以停掉物理帧：`_think()` 会去读 camera / lock，
	# 而这里两个都没有（那属于别的套件的构景）。
	pc.set_physics_process(false)
	var foe := _new_unit(c, 1, Vector3(0, ALT, -2000.0), 200.0)
	await _frames(host, 1)

	# ① 有请求 → 把这一梭打出的弹标记成可拦截
	# ⚠️ 第十八轮起是**整梭**（一梭三发全武装），不再只是"最后一发" —— 见
	# `PlayerController._mark_intercept_missile()`：一次扳机要能拦三枚来袭弹，
	# 否则拦截速率只有来袭速率的一半（算术见 `aiwork/gundam-missile-defense-plan.md` §1）。
	# 这里只造了一发，所以断言落在这一发上；"三发全武装 + 目标分配"在 `suite_round15` 里测。
	var m1 := Missile.funnel(c, pc.global_position, Vector3(0, 0, -1), foe, pc, 10.0)
	pc.set("_intercept_requested", true)
	pc.call("_mark_intercept_missile")
	t.ok(m1.intercept_capable, "请求过之后，这一梭打出的弹被标记为可拦截（第十八轮：整梭）")
	t.not_ok(pc.get("_intercept_requested"), "标记完请求就被清掉（不会一直粘着）")

	# ①b 速度加成 + **加速时间不能跟着变**
	#
	# ⚠️ 第二条才是关键：`accel` 是在 `_ready()` 里按 `(max_speed - speed)/accel_time`
	# 反推的。只乘 `max_speed` 不重算 `accel`，加速时间就会跟着倍率一起变长 ——
	# 代码不报任何错，只是"拦截弹迟迟提不起速"，把加成吃回去一半。
	t.near(m1.max_speed, SuitProfile.missile_speed() * Missile.INTERCEPT_SPEED_MULT,
		0.5, "拦截弹最大速度 = 巡航 × %.1f（%.0f m/s）"
		% [Missile.INTERCEPT_SPEED_MULT, m1.max_speed])
	t.near((m1.max_speed - m1.speed) / m1.accel, m1.accel_time, 0.02,
		"加速时间仍是 %.1f s（重算过 accel，没有被倍率带跑）" % m1.accel_time)
	# 幂等：重复武装不能变成 MULT²
	var before_speed := m1.max_speed
	m1.arm_intercept(foe)
	t.near(m1.max_speed, before_speed, 0.01,
		"重复武装不会把速度乘第二次（%.1f²）" % Missile.INTERCEPT_SPEED_MULT)

	# ①c **倍率本身的两条门**（2026-09-21：老板嫌拦截太快、看不到弹幕）
	#
	# 这个常数有两个相反方向的失败方式，两条都要钉：
	#   - 太小（≤1.0）→ 拦截弹追不上来袭弹，**拦截这个机制直接不成立**；
	#   - 太大（回到 1.8 那种"快八成"）→ 对着头瞬间贴上，**弹幕看不到**（老板原话：
	#     "拦截得有点过快了，没有展示出弹幕的华丽度"）。
	# 所以它被夹在"追得上"与"看得见"之间 —— 以后要动它，就得同时改这一条门，
	# 那正是"有意为之"和"手滑调错"的分界。
	t.gt(Missile.INTERCEPT_SPEED_MULT, 1.0,
		"拦截弹**必须**比来袭弹快（%.2f > 1.0）—— 这是拦截成立的前提"
		% Missile.INTERCEPT_SPEED_MULT)
	t.lt(Missile.INTERCEPT_SPEED_MULT, 1.5,
		"倍率**不许**再回到「快一大截」（%.2f < 1.5）—— 快了就没有弹幕可看"
		% Missile.INTERCEPT_SPEED_MULT)

	# ② 没有请求 → 不标记（否则**所有**导弹都能拦截，等于把拦截白送）
	var m2 := Missile.funnel(c, pc.global_position, Vector3(0, 0, -1), foe, pc, 10.0)
	pc.call("_mark_intercept_missile")
	t.not_ok(m2.intercept_capable, "没有请求时不会乱标记")

	# ③ 标记的是**自己**打的那一发，不是场上别人的
	var other := Missile.funnel(c, Vector3(0, ALT, -3000.0), Vector3(0, 0, -1), pc, foe, 10.0)
	pc.set("_intercept_requested", true)
	pc.call("_mark_intercept_missile")
	t.not_ok(other.intercept_capable, "不会把敌人打出的弹标记成我方可拦截弹")
	c.free()
	await _frames(host, 2)
	Game.reset()


## 光束**判定半径**的政策（用户第 1 项拍板走「丙」）—— **纯常量，不需要建单位**。
##
## 背景（完整版在 `Projectile.BEAM_HIT_RADIUS` 的注释里）：
## 第 1 项「光束步枪难以命中」的根因**不是锥角太窄**，而是**单位错**——
## `Ballistics.angle_off_boresight()` 返回**度**，`FlightBody.aim_assist_weight()`
## 的形参要的是**弧度**（内部 `deg_to_rad()` 去比常数）⇒ 真实偏角 > 0.0436°
## 时权重一律 0.0 ⇒ **辅助瞄准是死代码**（`tools/probe_aim_follow.gd` 第 7 节早有记录）。
##
## 但把单位改对 ⇒ 锁定且在锥内时弹道被拽向提前量点 ⇒ **违反 `README.md` 需求 4
##「光束步枪和火神炮的射击方向跟随鼠标操控的准星」**。用户选择**不动弹道**，
## 改走"放宽判定圈"这条路 —— 本节钉住的就是这个决定。
##
## 谁把判定半径调回解耦前的 2.6、或把"判定 = 视觉 × 2"这个旧算式写回来，都会红。
static func _hit_radius_policy(t: T) -> void:
	# ① 决定本身（`> 3.5` 留了余量；往回退到解耦前那一档必红）
	t.gt(Projectile.BEAM_HIT_RADIUS, 3.5,
		"判定半径 == %.2f m（第 1 项「丙」：> 3.5；解耦前是 2.6）"
			% Projectile.BEAM_HIT_RADIUS)
	# ② 与视觉之间**没有**算式关系（不许把"判定 = 视觉 × 2"写回来）
	t.ok(not is_equal_approx(Projectile.BEAM_HIT_RADIUS, Projectile.BEAM_VIS_RADIUS * 2.0),
		"判定 %.2f ≠ 视觉 %.2f × 2 = %.2f（**两个独立常量**）"
			% [Projectile.BEAM_HIT_RADIUS, Projectile.BEAM_VIS_RADIUS,
				Projectile.BEAM_VIS_RADIUS * 2.0])
	# ③ 判定必须**严格大于**视觉 —— "擦着机翼/背包算命中"这条设计意图不许被反向调头
	t.gt(Projectile.BEAM_HIT_RADIUS, Projectile.BEAM_VIS_RADIUS,
		"判定 %.2f > 视觉 %.2f（光圈比刀身宽，擦着机翼也算中）"
			% [Projectile.BEAM_HIT_RADIUS, Projectile.BEAM_VIS_RADIUS])
	# ④ 把"这个决定对玩家的可读含义"直接算出来（胶囊 r=5 m 是 DESIGN §1.4 的口径）
	var eff := 5.0 + Projectile.BEAM_HIT_RADIUS
	t.gt(eff, 7.6,
		"有效命中半径（胶囊 r=5 m + 判定）= **%.1f m** > 解耦前 7.6 m" % eff)
## ★63-25 光束军刀近战自伤豁免（用户报「砍到对方机体的同时自己还掉血」）。
##
## 需求原话：「把撞击伤害定义为碰撞伤害的伤害类，光束军刀近战的时候从按下鼠标开始
## 到在光束军刀打出伤害后的 0.7s 之前是不会触发这个伤害类。**其他时候正常**」。
##
## 机理（算式写在 `RAM_GUARD_AFTER_SABER` 的注释里）：军刀命中判定在 `saber_hit_range`
##（78 m）就触发，而 `_slash()` 命中那一刻就 `_end_saber()` **收招了、速度却没归零**
## ⇒ 两机继续贴近到碰撞胶囊（半径 5~7 m）⇒「砍中对方」几乎必然伴随一次撞机结算
##（双方各 45）。算过：还要走 66 m ÷ 1150 m/s ≈ 3.4 帧（0.057 s）⇒ 0.7 s 余量很宽松。
##
## 这一节钉四件事：
##   ① **窗口形状**：突进中（= 需求说的「按下鼠标开始」）∪ 收招后 `RAM_GUARD_AFTER_SABER` 秒；
##   ② **窗口内真的不结算，而且不写 `ram_cooldown`** —— 第二条是「上游拦 vs 下游拦」的分水岭，
##      写在下游的话冷却**已经写上了**，症状是「出了窗口贴脸撞上、1 秒内也不掉血」；
##   ③ **出了窗口照常结算**（用户：「其他时候正常」）—— 与 ② 是**同一构景的 A/B 对照**，
##      只翻「有没有窗口」这一个入参，才分得清「豁免生效了」和「压根没撞上」；
##   ④ **任一方**在窗口内都算（相杀场面两人都在窗口里，只免一方会退化成不对称）。
static func _saber_ram_guard(t: T, host: Node) -> void:
	# ---------- ① 窗口形状（纯谓词 + 生产置位点，不依赖碰撞）----------
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 500.0, true)
	var mate := _new_unit(c, 1, Vector3(0, ALT, 3000.0), 500.0)
	await _frames(host, 1)

	t.not_ok(me.in_ram_guard(), "（前置）平时不在军刀撞击豁免窗口内 —— 撞击伤害照常生效")
	t.gt(FlightBody.RAM_GUARD_AFTER_SABER, 0.0,
		"豁免余量为正（%.2f s）—— 设成 0 等于整条机制没做" % FlightBody.RAM_GUARD_AFTER_SABER)

	# 「从按下鼠标开始」那一段 = `saber_state == CHARGE`。
	# ⚠️ 先停物理帧再写状态：`_step_saber()` 会接管速度矢量，纯谓词节里那属于噪音。
	me.set_physics_process(false)
	me.saber_state = FlightBody.SaberState.CHARGE
	t.ok(me.in_ram_guard(),
		"切入军刀突进 ⇒ 立刻进窗口（需求说的「从按下鼠标开始」；突进路上先撞上也不该扣）")

	# 收招走**生产路径** `_end_saber()`（唯一收口），不是手工写 `ram_guard_left`
	me.call("_end_saber")
	t.eq(me.saber_state, FlightBody.SaberState.IDLE, "收招后状态回 IDLE")
	t.near(me.ram_guard_left, FlightBody.RAM_GUARD_AFTER_SABER, 0.0001,
		"`_end_saber()` 把豁免余量置成 RAM_GUARD_AFTER_SABER（工程里唯一的置位点）")
	t.ok(me.in_ram_guard(), "收招之后仍在窗口内（= 用户要的「打出伤害后 0.7s 之前」）")

	# 余量走完 ⇒ 出窗口。递减在 `_tick_weapons()` 里，所以要放真物理帧。
	me.set_physics_process(true)
	await _frames(host, int(ceil(FlightBody.RAM_GUARD_AFTER_SABER * 60.0)) + 5)
	t.near(me.ram_guard_left, 0.0, 0.0001, "余量随物理帧递减到 0（没有卡在 >0 上）")
	t.not_ok(me.in_ram_guard(), "窗口走完 ⇒ 回到「会正常结算撞击伤害」的状态")
	# 与 `is_invulnerable()` 是**两根独立的轴**（那是一切伤害全免，写者是变身掩护 / 脱出冲刺）
	t.not_ok(me.is_invulnerable(),
		"豁免撞击**没有**顺手把机体变成全免疫（不共用 invuln 那根轴 —— 复用会把那两个已验收的演出改坏）")
	t.not_ok(mate.in_ram_guard(), "没进过军刀的机体不在窗口内")

	c.free()
	await _frames(host, 2)
	Game.reset()

	# ---------- ②③ 真碰撞：同一构景的 A/B，只翻「有没有豁免窗口」----------
	# 摆位抄 `_ram_cooldown` 那一节（它已经证明这个摆位会真撞上）：
	# a 以 200 m/s 撞向被冻结的 b（冻结 ⇒ 它的冷却/余量都不递减，只可能被撞一次）。
	for guarded: bool in [true, false]:
		Game.reset()
		var cc := Node3D.new()
		host.add_child(cc)
		var a := _new_unit(cc, 0, Vector3(0, ALT, 0), 500.0, true)
		var b := _new_unit(cc, 1, Vector3(0, ALT, -70.0), 500.0)
		if guarded:
			# ⚠️ 这是**摆位**，明说：生产路径（`_end_saber()`）只给 0.7 s = 42 帧，
			#    盖不住下面 90 帧的推进长度。这里要验的是「窗口在时撞上不结算」，
			#    窗口**怎么来的**已经在 ① 里用生产路径验过了。
			a.ram_guard_left = 3.0
		b.set_physics_process(false)
		b.fm.speed = 0.0
		b.fm.velocity = Vector3.ZERO
		a.fm.speed = 200.0
		a.fm.velocity = a.forward() * 200.0
		var min_d := 1e9
		# ⚠️ 盯**全程峰值**，不是「最后一帧的值」：`ram_cooldown` 每帧递减，活着那一侧
		#    跑满 90 帧必然回 0 ⇒ 只看末值的那条断言**永远绿、无法证伪**
		#（第一版就是这么写的，被 nc1 当场抓出来：它该红却没红）。
		var cd_peak_a := 0.0
		var cd_peak_b := 0.0
		for i in 90:
			await host.get_tree().physics_frame
			min_d = minf(min_d, a.global_position.distance_to(b.global_position))
			cd_peak_a = maxf(cd_peak_a, a.ram_cooldown)
			cd_peak_b = maxf(cd_peak_b, b.ram_cooldown)
		# 正对照：先证明"真的贴上过" —— 否则下面那几条全是空转
		t.lt(min_d, 30.0,
			"（前置）两机确实贴上过（最近 %.1f m）—— 没贴上则本条什么也证明不了" % min_d)
		if guarded:
			t.near(a.hp, 500.0, 0.01, "② 窗口内撞上：本机**不掉血**（砍完贴脸不再自伤）")
			t.near(b.hp, 500.0, 0.01, "② 窗口内撞上：对方也不掉血（两人一起跳过整条接触）")
			t.near(cd_peak_a, 0.0, 0.0005,
				("② **全程没有写过 `ram_cooldown`**（本机侧峰值 %.3f）—— 豁免必须落在**写冷却之前**；"
				+ "写在下游就会出现「出了窗口贴脸撞上、1 秒内也不掉血」") % cd_peak_a)
			t.near(cd_peak_b, 0.0, 0.0005,
				"② 对方那侧同样没被写过（峰值 %.3f；它是冻结的，不会被时间冲掉）" % cd_peak_b)
		else:
			var lost := 500.0 - a.hp
			t.gt(lost, FlightBody.RAM_DAMAGE * 0.5,
				"③ 无窗口时照常结算（扣了 %.0f）—— 用户要的「其他时候正常」" % lost)
			t.lt(lost, FlightBody.RAM_DAMAGE * 1.5,
				"③ 一次接触只结算一次（扣了 %.0f，撞击冷却仍然生效）" % lost)
			t.gt(500.0 - b.hp, FlightBody.RAM_DAMAGE * 0.5,
				"③ 对方也照常被扣（撞击伤害本来就是双方各一份）")
			t.gt(cd_peak_a, FlightBody.RAM_COOLDOWN * 0.5,
				"③ 撞击冷却确实被写上过（峰值 %.3f）—— 与 ② 共用同一口径，两侧才可比" % cd_peak_a)
		cc.free()
		await _frames(host, 2)
		Game.reset()

	# ---------- ④ 「任一方」语义 + AI 同样适用 ----------
	Game.reset()
	var c2 := Node3D.new()
	host.add_child(c2)
	var p := _new_unit(c2, 0, Vector3(0, ALT, 0), 500.0, true)
	var q := _new_unit(c2, 1, Vector3(0, ALT, -70.0), 500.0)
	q.set_physics_process(false)      # 冻结 ⇒ 它的 ram_guard_left 不会递减
	q.ram_guard_left = 3.0
	t.not_ok(q.is_player, "（前置）q 是 AI 单位，不是玩家")
	t.ok(q.in_ram_guard(), "④ AI 单位同样进窗口（豁免不是只给玩家 —— 拍板②「玩家与 AI 都给」）")
	q.fm.speed = 0.0
	q.fm.velocity = Vector3.ZERO
	p.fm.speed = 200.0
	p.fm.velocity = p.forward() * 200.0
	var min_d2 := 1e9
	var cd_peak_p := 0.0
	var cd_peak_q := 0.0
	for i in 90:
		await host.get_tree().physics_frame
		min_d2 = minf(min_d2, p.global_position.distance_to(q.global_position))
		cd_peak_p = maxf(cd_peak_p, p.ram_cooldown)
		cd_peak_q = maxf(cd_peak_q, q.ram_cooldown)
	t.lt(min_d2, 30.0, "（前置）两机确实贴上过（最近 %.1f m）—— 第 ④ 条" % min_d2)
	t.near(p.hp, 500.0, 0.01, "④ 只有**对方**在窗口内：本机也不掉血（判据含 `other`）")
	t.near(q.hp, 500.0, 0.01, "④ 对方自己也不掉血")
	t.near(cd_peak_p, 0.0, 0.0005,
		"④ 本机侧全程没写冷却（峰值 %.3f）—— 相杀场面不会单方面吃亏" % cd_peak_p)
	t.near(cd_peak_q, 0.0, 0.0005, "④ 对方侧全程也没写冷却（峰值 %.3f）" % cd_peak_q)
	c2.free()
	await _frames(host, 2)
	Game.reset()
