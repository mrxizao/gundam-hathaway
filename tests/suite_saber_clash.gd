class_name SuiteSaberClash
extends RefCounted
## **军刀相杀**（1.2.1 · DESIGN §3.2 / §3.3）。
##
## 需求原文：「近战系统要加入相杀（在同一段时间判定窗口内都使用了光束军刀攻击，
## 则触发相杀，相杀之后会暂时失去双方的锁定，并且**强制弹开一段距离**）」。
##
## 用户实测报的：「但是我**好像忘记加限定**了」+「导致了产生友军使用军刀的时候
## 自己使用军刀会和友军相杀」。
##
## ## 读码查出的两个真 bug（都不是"数值不对"，是**逻辑缺项**）
##
## **① 只弹开一方**：`_begin_clash(other)` 的注释写着"弹开：**各自**背向"，
## 代码里却只有 `_push_back_from(other)` —— `other` 从头到尾没被弹开。
## 而"只触发一次"是靠掐掉对方的 `CHARGE` 实现的，所以 `_begin_clash` 只会被调用一次
## ⇒ 表现是**谁先扫到对方谁被弹开**，另一个人的速度一点没变。
## 相杀于是从"谁也没占便宜"变成了"先检测到的一方吃亏"。
##
## **② 缺三类限定**：显式阵营复检、接近率窗口（背向拉开也算拼刀）、对手冷却。
##
## 本套件把①②都钉死，并且**顺带锁住"相杀之后的失锁与冷却"**——
## 那是需求里"暂时失去双方的锁定"那一半，改动 `_begin_clash` 时最容易碰坏。

const SYMMETRY := "SaberClash / 双方都被弹开（对称性）"
const LIMITS := "SaberClash / 三条限定（阵营 / 接近率 / 距离）"


static func run(t: T, host: Node) -> void:
	t.suite(SYMMETRY)
	await _symmetry(t, host)
	t.suite(LIMITS)
	await _limits(t, host)


# ---------------------------------------------------------------- 工具

static func _spawn_squad(host: Node) -> Node:
	Game.reset()
	Game.active_suit = SuitProfile.Id.MESSER_M01
	Game.active_side = BattleFormation.Side.MAFTY
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main_scene)
	return main_scene


static func _troops(m: Node) -> Dictionary:
	var player: FlightBody = m.get("player")
	var wing: FlightBody = null
	var foe: FlightBody = null
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if not u.has_method("is_alive") or not u.is_alive():
			continue
		var fb := u as FlightBody
		if fb == null or fb == player:
			continue
		if fb.team == player.team and wing == null:
			wing = fb
		elif fb.team != player.team and foe == null:
			foe = fb
	return {"player": player, "wing": wing, "foe": foe}


## 把两台摆成"对冲 + 双方都在军刀突进态"。
##
## ⚠️ **直接写 `saber_state` 而不是调 `try_saber()`**：
## `try_saber()` 会顺手把 `saber_cooldown` 压成 `saber_interval`，
## 于是"刚相杀完的冷却"那条限定根本测不出来（冷却被测试自己重置掉了）。
## 这里要的是"窗口重叠"这个**前置条件**，不是"玩家怎么按出来的"。
##
## `closing = false` 时摆成**背向拉开**（用来测接近率窗口）。
static func _arm(a: FlightBody, b: FlightBody, gap: float, closing := true) -> void:
	a.global_position = Vector3(0.0, 3000.0, 0.0)
	b.global_position = Vector3(gap, 3000.0, 0.0)
	var s := 1.0 if closing else -1.0
	var v := 400.0 * s
	a.fm.velocity = Vector3(v, 0.0, 0.0)
	b.fm.velocity = Vector3(-v, 0.0, 0.0)
	a.saber_state = FlightBody.SaberState.CHARGE
	b.saber_state = FlightBody.SaberState.CHARGE
	a.clash_count = 0
	b.clash_count = 0
	a.saber_cooldown = 0.0
	b.saber_cooldown = 0.0


# ---------------------------------------------------------------- 1 对称性

static func _symmetry(t: T, host: Node) -> void:
	var m := _spawn_squad(host)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 16:
		await host.get_tree().physics_frame

	var s := _troops(m)
	var a: FlightBody = s["player"]
	var b: FlightBody = s["foe"]
	if a == null or b == null:
		t.ok(false, "**找不到敌机** —— 相杀套件的前提不成立")
		m.queue_free()
		await host.get_tree().physics_frame
		return

	# 60 m：既在 `CLASH_RANGE`(100) 内，也在 `saber_hit_range`(78) 内 ——
	# 而 `_step_saber()` 是**先查相杀、再查命中**（CLASH_RANGE 的注释解释了为什么），
	# 所以真实对局里这个距离也是相杀优先。这里直接调 `_try_clash()` 让它更确定。
	_arm(a, b, 60.0)
	var to_foe := b.global_position - a.global_position
	var hit: bool = a.call("_try_clash", 0.0)
	t.ok(hit, "双方对冲进入 100 m 内 → 触发相杀")
	t.eq(a.clash_count, 1, "发起方 clash_count +1")
	t.eq(b.clash_count, 1, "对方 clash_count 也 +1")

	# ---- 这两条就是 BUG-2 ----
	#
	# ⚠️ 断言**方向 + 量级**，**不**断言"恰好等于 `CLASH_PUSH_SPEED`"。
	# 第一版就是这么写的，实测拿到 240 而不是 600 —— 因为机体在真实场景里跑着物理帧，
	# `FlightModel._step_speed()` 会把速度钳到 `ab_speed * 1.25`（梅萨正好 = 240）。
	# 那是飞行模型的**正常职责**，拿它做断言等于在测"引擎有没有跑帧"，非常脆。
	# 判据应该是"两边都被**抛出量级**的速度推向相反方向" —— 这才钉得住"只弹开一方"那个 bug。
	t.gt(a.fm.velocity.length(), 50.0,
		"发起方被弹开（抛出量级：%.0f m/s）" % a.fm.velocity.length())
	t.gt(b.fm.velocity.length(), 50.0,
		"**对方也被弹开** —— 原来没有这一条（相杀只弹开一方）")

	# 方向：两边沿**同一条连线**反向分离（夹角都 > 90°）
	t.lt(a.fm.velocity.dot(to_foe), 0.0, "发起方的速度背向对方")
	t.gt(b.fm.velocity.dot(to_foe), 0.0, "对方的速度背向发起方（同一连线的反向）")

	# ---- 相杀的另一半：失锁 + 冷却 ----
	t.not_ok(a.saber_active(), "相杀后发起方退出军刀突进态")
	t.not_ok(b.saber_active(), "相杀后对方也退出突进态")
	t.gt(a.clash_cooldown_left(), 0.0, "发起方进入相杀冷却")
	t.gt(b.clash_cooldown_left(), 0.0, "对方也进入相杀冷却（对称）")
	t.ok(float(FlightBody.CLASH_COOLDOWN) > float(FlightBody.CLASH_UNLOCKABLE),
		"不变量：相杀冷却 > 失锁时长（防「贴脸缠斗变成相杀死循环」，注释点名过）")

	m.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 2 三条限定

static func _limits(t: T, host: Node) -> void:
	var m := _spawn_squad(host)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 16:
		await host.get_tree().physics_frame

	var s := _troops(m)
	var a: FlightBody = s["player"]
	var b: FlightBody = s["foe"]
	var ally: FlightBody = s["wing"]
	if a == null or b == null or ally == null:
		t.ok(false, "**敌机或队友缺失** —— 限定那几条测不了")
		m.queue_free()
		await host.get_tree().physics_frame
		return

	# ---- 限定 ①：阵营 ----
	#
	# 用户报的那条（"友军使用军刀会和友军相杀"）。读码结论是
	# `live_hostiles_of()` 已经把同队筛掉了 —— 但那是**隐式**保证，
	# 所以这里把 `_try_clash()` 直接调起来，专门验证它自己那道**显式**复检。
	_arm(a, ally, 60.0)
	var hit: bool = a.call("_try_clash", 0.0)
	t.not_ok(hit, "**友军对冲不触发相杀**（显式阵营复检）")
	t.eq(a.clash_count, 0, "...发起方 clash_count 不变")
	t.eq(ally.clash_count, 0, "...友军 clash_count 不变")
	t.ok(a.is_hostile_to(ally) == false, "判据：`is_hostile_to(队友)` = false")

	# ---- 限定 ②：接近率窗口 ----
	#
	# 没有这条时，两机**背向拉开**经过 100 m 内也会被判"拼刀" —— 不可解释。
	_arm(a, b, 60.0, false)
	hit = a.call("_try_clash", 0.0)
	t.not_ok(hit, "**背向拉开经过 100 m 内不算拼刀**（接近率窗口）")
	t.eq(a.clash_count, 0, "...发起方 clash_count 不变")

	# 反证：同样的距离，改成对冲就要触发（否则上一条可能只是因为别的原因失败）
	_arm(a, b, 60.0, true)
	hit = a.call("_try_clash", 0.0)
	t.ok(hit, "同样距离改成**对冲** → 触发（证明上一条拦的是「方向」而不是别的东西）")

	# ---- 限定 ③：相杀冷却期内的去重 ----
	#
	# ⚠️ 这一节原来写的是"给对手压一个冷却 → 不触发第二次"，
	# 而它测的是一条**不该存在**的机制：第一版 `_try_clash()` 里真加过
	# `if fb.in_clash_cooldown(): continue`，结果相杀**整个触发不了**
	#（`suite_round18` 红了 15 条，症状像"功能没写对"）。原因是结构性冲突：
	# `in_clash_cooldown()` 的实现是 `saber_cooldown > 0`，而 `try_saber()`
	# 在**起手那一刻**就把冷却压成 `saber_interval`（3.2 s）⇒
	# "在突进里"与"不在冷却里"**永远不能同时成立**，判定框变成空集。
	#
	# 所以去重真正的承重点在**起手**：冷却期内 `try_saber()` 直接被拒。
	# 这里就测它 —— 比原来那条"查冷却"更接近真实机制，也不会假绿。
	_arm(a, b, 60.0, true)
	b.saber_state = FlightBody.SaberState.IDLE      # 冷却期内本来就该是 IDLE
	b.saber_cooldown = FlightBody.CLASH_COOLDOWN
	t.not_ok(b.try_saber(a), "相杀冷却期内**对手起不了手**（`try_saber` 被拒）")
	hit = a.call("_try_clash", 0.0)
	t.not_ok(hit, "对手起不了手 ⇒ **不会二次相杀**（去重不靠那条死限定）")
	t.eq(a.clash_count, 0, "...发起方 clash_count 不变")

	# ---- 距离限定仍然生效（顺带确认没被上面几条短路掉）----
	_arm(a, b, FlightBody.CLASH_RANGE + 20.0, true)
	hit = a.call("_try_clash", 0.0)
	t.not_ok(hit, "超出 CLASH_RANGE 不触发（原有判据没被碰坏）")

	# ---- 可选开关：机头互指默认关 ----
	t.not_ok(FlightBody.CLASH_REQUIRE_FACING,
		"`CLASH_REQUIRE_FACING` 默认 **关**（侧向相杀保留，待试玩后再定）")

	m.queue_free()
	await host.get_tree().physics_frame
