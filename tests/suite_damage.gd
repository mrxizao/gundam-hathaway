class_name SuiteDamage
extends RefCounted
## 两层减伤模型的测试。
##
## ## 规则（第四轮确认版）
## **I 立场没扣完之前，机体一滴血都不能掉。** 所有伤害都先打进护盾。
## `Damage.IFIELD_EFFICIENCY` 决定的是**护盾消耗速度**，不是"漏到机体的比例"：
##
## | 伤害类型 | 效率 | 打 10 点伤害要消耗多少护盾值 | 机体掉血 |
## |---|---|---|---|
## | 光束步枪 | 1.00 | 10.0 | 0 |
## | 火神炮 | 0.70 | 14.29 | 0 |
## | 浮游导弹 | 0.70 | 14.29 | 0 |
## | 光束军刀 | 0.45 | 22.22 | 0 |
##
## 另外还要测三类边界：护盾被单发打爆时的溢出、击穿后不再恢复、主动举盾。


static func run(t: T, host: Node) -> void:
	t.suite("Damage / 护盾未破不掉血")
	await _shield_absorbs_all(t, host)
	t.suite("Damage / 各类伤害的护盾消耗速度")
	await _efficiency(t, host)
	t.suite("Damage / 击穿、溢出与不恢复")
	await _depletion(t, host)
	t.suite("Damage / 主动举盾")
	await _active_shield(t, host)
	await _shield_roster(t,host)
	t.suite("Damage / 举盾时长与冷却")
	await _shield_timing(t, host)


static func _unit(container: Node3D, suit: SuitProfile) -> FlightBody:
	var u := FlightBody.new()
	u.team = 1
	u.profile = suit
	u.projectile_container = container
	container.add_child(u)
	u.global_position = Vector3(0, 3000, 0)
	u.fm.speed = 260.0
	u.fm.throttle = 0.78
	u.fm.align_velocity(u.forward())
	return u


## 核心规则：只要护盾还有值，任何类型的伤害都进不到机体。
static func _shield_absorbs_all(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _unit(c, SuitProfile.penelope())   # I 立场 240

	for kind: int in [Damage.Type.BEAM, Damage.Type.VULCAN, Damage.Type.FUNNEL,
			Damage.Type.SABER, Damage.Type.RAM]:
		u.ifield_hp = u.ifield_max
		var hull := u.hp
		u.take_damage(10.0, null, kind)
		t.near(u.hp, hull, 0.001, "%s：护盾未破时机体一点血都不掉" % Damage.label(kind))
		t.lt(u.ifield_hp, u.ifield_max, "%s：护盾确实被消耗了" % Damage.label(kind))

	# 连打很多发，只要护盾没空机体就不该掉血
	u.ifield_hp = u.ifield_max
	var hull0 := u.hp
	for i in 30:
		u.take_damage(4.0, null, Damage.Type.VULCAN)
	t.near(u.hp, hull0, 0.001, "连续 30 发火神炮（护盾够用时机体依然满血）")

	c.free()
	await host.get_tree().process_frame
	Game.reset()


## 效率表：同样的伤害量，效率越低消耗护盾越多。
static func _efficiency(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _unit(c, SuitProfile.penelope())

	t.near(Damage.ifield_efficiency(Damage.Type.BEAM), 1.00, 0.001, "光束步枪效率 1.00")

	var cases := [
		{"type": Damage.Type.BEAM, "cost": 10.0, "name": "光束步枪"},
		{"type": Damage.Type.VULCAN, "cost": 10.0 / 0.70, "name": "火神炮"},
		{"type": Damage.Type.FUNNEL, "cost": 10.0 / 0.70, "name": "浮游导弹"},
		{"type": Damage.Type.SABER, "cost": 10.0 / 0.45, "name": "光束军刀"},
	]
	for cs: Dictionary in cases:
		u.ifield_hp = u.ifield_max
		u.take_damage(10.0, null, cs["type"])
		var used: float = u.ifield_max - u.ifield_hp
		t.near(used, cs["cost"], 0.01,
			"%s：打 10 点伤害消耗 %.2f 点护盾值" % [cs["name"], cs["cost"]])

	# 军刀必须是破盾最快的手段（同样伤害消耗最多护盾）
	t.gt(Damage.ifield_efficiency(Damage.Type.SABER), 0.0, "军刀不再穿盾，而是效率最低")
	t.lt(Damage.ifield_efficiency(Damage.Type.SABER),
		Damage.ifield_efficiency(Damage.Type.VULCAN), "军刀破盾比火神炮还快")
	t.gt(Damage.ifield_cost(50.0, Damage.Type.SABER),
		Damage.ifield_cost(50.0, Damage.Type.BEAM), "同样伤害军刀消耗的护盾远多于光束")

	c.free()
	await host.get_tree().process_frame
	Game.reset()


static func _depletion(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _unit(c, SuitProfile.xi())   # I 立场 190

	var hull_before := u.hp
	var guard := 0
	var hull_dropped_early := false
	# 用 23 而不是 20：护盾值恰好被 20 整除时，最后一发会把护盾精确打到 0、
	# 没有任何溢出，"打爆护盾的那一发会带溢出伤害进机体"这条就测不到了。
	while u.ifield_hp > 0.0 and guard < 400:
		u.take_damage(23.0, null, Damage.Type.BEAM)
		guard += 1
		if u.ifield_hp > 0.0 and u.hp < hull_before - 0.001:
			hull_dropped_early = true
	t.ok(not u.has_ifield(), "连续光束可以把 I 立场打空（用了 %d 发）" % guard)
	t.not_ok(hull_dropped_early, "在护盾被打空的**那一刻之前**，机体血一直没有动")
	t.lt(u.hp, hull_before, "打爆护盾的那一发会把溢出伤害带进机体")
	t.near(u.ifield_hp, 0.0, 0.001, "打空后 I 立场归零")

	var hull_after_break := u.hp
	u.take_damage(30.0, null, Damage.Type.BEAM)
	t.near(u.hp, hull_after_break - 30.0, 0.001, "护盾空了之后光束全额打在机体上")
	t.near(u.ifield_hp, 0.0, 0.001, "I 立场不会恢复")

	# 护盾不足时溢出：护盾只剩 10，来一发 50 的光束
	var v := _unit(c, SuitProfile.xi())
	v.ifield_hp = 10.0
	var hv := v.hp
	v.take_damage(50.0, null, Damage.Type.BEAM)
	t.near(v.ifield_hp, 0.0, 0.001, "溢出后护盾归零")
	t.near(v.hp, hv - 40.0, 0.001, "护盾只有 10 时，50 点光束有 40 点溢出到机体")

	# 效率 < 1 的类型，溢出换算要按效率折算回去
	var w := _unit(c, SuitProfile.xi())
	w.ifield_hp = 7.0
	var hw := w.hp
	w.take_damage(20.0, null, Damage.Type.VULCAN)
	# 护盾 7 点 × 效率 0.7 = 只能吸收 4.9 点伤害 → 机体吃 15.1
	t.near(w.hp, hw - (20.0 - 7.0 * 0.70), 0.01, "火神炮溢出按效率折算（护盾 7 点只挡住 4.9 点）")

	c.free()
	await host.get_tree().process_frame
	Game.reset()


static func _active_shield(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	# ★63-9 B6：举盾免伤**全机体统一 70%**（用户指定）⇒ 下面两条吃到的都是 30。
	# ⚠️ 这里原来还有一条 `t.gt(xi, penelope)`（“柯西高于佩涅罗佩”）——
	# 统一之后它必然红，换成**“统一”这条更有用的判据**：
	# 不要求某个数与某个数比较，而是钉住**唯一真源** `SuitProfile.SHIELD_REDUCTION`，
	# 并要求所有有盾机体与它**逐位相等**。
	var pen := _unit(c, SuitProfile.penelope())
	pen.ifield_hp = 0.0
	pen.raise_shield()
	var hp0 := pen.hp
	pen.take_damage(100.0, null, Damage.Type.SABER)
	t.near(pen.hp, hp0 - 30.0, 0.5, "佩涅罗佩举盾后 100 点军刀伤害只吃到 30（免伤 70%）")

	var xi := _unit(c, SuitProfile.xi())
	xi.ifield_hp = 0.0
	xi.raise_shield()
	var hp1 := xi.hp
	xi.take_damage(100.0, null, Damage.Type.SABER)
	t.near(xi.hp, hp1 - 30.0, 0.5, "柯西举盾后 100 点军刀伤害只吃到 30（免伤 70%）")

	t.near(SuitProfile.SHIELD_REDUCTION, 0.70, 0.0001,
		"举盾免伤的唯一真源 = 0.70（用户：把撑盾的免伤改为 70%）")
	var shields: Array[SuitProfile] = [SuitProfile.xi(), SuitProfile.penelope(),
		SuitProfile.arizeus(), SuitProfile.gustav00_armed(),
		SuitProfile.messer_m01(), SuitProfile.messer_cmd(), SuitProfile.messer_f01()]
	for pr in shields:
		t.near(pr.shield_reduction, SuitProfile.SHIELD_REDUCTION, 0.0001,
			"%s 的举盾免伤 = 统一值（没有哪台被漏掉）" % pr.display_name)
	t.near(SuitProfile.gustav00().shield_reduction, 0.0, 0.0001,
		"古斯塔夫00（训练靶机）**没有盾** ⇒ 保持 0.0（不是漏改）")

	# 不举盾时吃满
	var bare := _unit(c, SuitProfile.xi())
	bare.ifield_hp = 0.0
	bare.shield_up = false
	var hp2 := bare.hp
	bare.take_damage(100.0, null, Damage.Type.SABER)
	t.near(bare.hp, hp2 - 100.0, 0.5, "不举盾时军刀伤害吃满")

	# 护盾还在 + 举盾：依然零伤害（I 立场优先级更高）
	var both := _unit(c, SuitProfile.xi())
	both.raise_shield()
	var hp3 := both.hp
	both.take_damage(80.0, null, Damage.Type.BEAM)
	t.near(both.hp, hp3, 0.001, "I 立场还在时举盾，光束依旧是零伤害")

	c.free()
	await host.get_tree().process_frame
	Game.reset()


## 举盾改成"按一次举 5 秒 + 冷却 1 秒"（用户要求）之后的规则测试。
static func _shield_timing(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _unit(c, SuitProfile.xi())

	t.eq(u.SHIELD_DURATION, 5.0, "举盾持续 5 秒")
	t.eq(u.SHIELD_COOLDOWN, 1.0, "举盾冷却 1 秒")
	t.not_ok(u.shield_up, "初始没有举盾")

	t.ok(u.raise_shield(), "按一次可以举盾")
	t.ok(u.shield_up, "举盾生效")
	t.near(u.shield_timer, 5.0, 0.001, "举盾计时从 5 秒开始")
	t.not_ok(u.can_raise_shield(), "已经在举盾时不能再举")
	t.not_ok(u.raise_shield(), "重复按不会刷新持续时间")

	# 走 4 秒：还在举
	for i in 240:
		await host.get_tree().physics_frame
	t.ok(u.shield_up, "4 秒时盾还在")
	t.near(u.shield_ratio(), 0.2, 0.05, "剩余时间约 1 秒（比例 0.2）")

	# 再走 1.5 秒：盾落，进入 1 秒冷却
	for i in 90:
		await host.get_tree().physics_frame
	t.not_ok(u.shield_up, "5 秒后盾自动落下")
	t.gt(u.shield_cooldown, 0.0, "落下后进入冷却")
	t.not_ok(u.raise_shield(), "冷却期间举不了盾")

	# 冷却走完后可以再举
	for i in 75:
		await host.get_tree().physics_frame
	t.near(u.shield_cooldown, 0.0, 0.001, "1 秒后冷却结束")
	t.ok(u.raise_shield(), "冷却结束后可以再次举盾")
	t.ok(u.shield_up, "第二次举盾生效")

	c.free()
	await host.get_tree().process_frame
	Game.reset()


static func _shield_roster(t:T,host:Node)->void:
	t.suite("Damage / whole roster 70 percent, rifle block and cannon distinction")
	Game.reset()
	var c:=Node3D.new();host.add_child(c)
	var shooter:=_unit(c,SuitProfile.xi());shooter.team=0;shooter.set_physics_process(false)
	for id in SuitProfile.Id.values():
		var base:=SuitProfile.by_id(id)
		for form in range(maxi(base.form_count,1)):
			var profile:=SuitProfile.by_id_form(id,form)
			if profile.shield_reduction<=0:continue
			var unit:=_unit(c,profile);unit.set_physics_process(false)
			unit.is_player=(id%2==0)
			unit.raise_shield();unit.ifield_hp=0
			var hp_before:=unit.hp
			unit.take_damage(100.0,shooter,Damage.Type.BEAM)
			t.near(unit.hp,hp_before,.001,"rifle fully blocked without I-field "+profile.display_name)
			unit.ifield_hp=100
			unit.take_damage(100.0,shooter,Damage.Type.BEAM)
			t.near(unit.ifield_hp,100,.001,"blocked rifle does not drain I-field "+profile.display_name)
			for kind in [Damage.Type.VULCAN,Damage.Type.FUNNEL,Damage.Type.SABER,Damage.Type.RAM,Damage.Type.BEAM_CANNON]:
				unit.ifield_hp=0;unit.hp=unit.max_hp;unit._hitstop=0
				var expected:=100.0*.30*Damage.funnel_target_multiplier(profile.id,kind)
				unit.take_damage(100.0,shooter,kind)
				t.near(unit.max_hp-unit.hp,expected,.01,"non-rifle damage receives 70 percent reduction "+profile.display_name+" "+str(kind))
			unit.shield_up=false;unit.hp=unit.max_hp;unit.ifield_hp=0
			unit.take_damage(100.0,shooter,Damage.Type.BEAM)
			t.near(unit.max_hp-unit.hp,100,.01,"lowered shield takes normal rifle damage "+profile.display_name)
			unit.free()
	c.free();await host.get_tree().process_frame;Game.reset()
