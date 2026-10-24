class_name SuiteGroundGuard
extends RefCounted
## 2026-10-08: legacy fallback unit checks remain; live flight now also exercises
## predictive protection. The former expected deep-dive crash must now survive.
## ★63-9 · B3「防撞地未生效」。
##
## ## 用户原话
## 「防撞地未生效。」
##
## ## 根因（结构性缺失）
##
## `PlayerController._tick_assist()` 在 `if translate_mode: return` 处早退，而
## `_assist.update()` 与整段「松手改出」都在它**后面** ⇒ 辅助驾驶下只要走平移模式
##（绝大多数机体在辅助下的默认路，见 `assist_uses_translation`），
## **防撞地一次都不执行**。
##
## ## ⚠️ 「把代码挪上来」不够：平移模式**没有俯仰杆**
##
## `FlightBody._apply_translate()` 直接改 `fm.velocity`，**一个字都不读 `control_input`**
## ⇒ 在平移模式下写 `control_input = Vector3(1.0, ...)` 等于什么都没做。观感是
##「提示弹了、机体照样扎进地里」—— 本工程最忌讳的那一类"看着对、其实空转"。
##
## 平移模式真正的抬头旋钮是**升降（Q/E）**，也就是 `translate_dir` 的 y 分量
##（`_read_translate_input()` 里唯一带 y 的那一项，而它自己每帧把 `control_input` 清零）。
## 所以「玩家有没有在压杆」这条口径在平移模式下必须换成 `translate_dir.y` ——
## 传 `control_input.x`（恒 0）等于告诉辅助「玩家永远没在压杆」，
## 于是「按着 E 往地里扎」也会被夺杆，正好是老板点名不许的那件事。
##
## ## 五段判据
##
##   ① 结构：平移模式下 `_assist` 每帧真的被更新过（`ground_time` 从 INF 变有限值）；
##   ② 口径：「松手 / 压杆」在平移模式下读 `translate_dir.y`，**不是** `control_input.x`；
##   ③ 夺杆：三个写点按模式分家（`translate_dir = UP` / `translate_fwd = ZERO` /
##      `face_target = null`）+ `fm.boosting = false`，且**不碰** `control_input`；
##   ④ 老路未变：飞行操纵那一支仍是「满抬头 + 压平坡度」（`1.0` / `0.4`）；
##   ⑤ 真机：锁着一台**下方**目标、松手 ⇒ **真的爬起来了**（改前会一路扎下去）。
##
## ## ⚠️ 第 ③ 段里 `face_target = null` 那一笔：**必要性只能用算式证**
##
## 有目标时 `_apply_translate()` 的底速方向是**朝目标的全 3D 机头**，接管期间的净垂速
## = `(TRANSLATE_OFFSET − sin θ) · v`（θ = 目标在水平线下的夹角）：
## θ = 10° ⇒ +0.48 v；30° ⇒ +0.15 v；40° ⇒ **+0.007 v ≈ 0**。
## 清掉它 ⇒ 底速退回机头水平投影，净垂速恒 `+0.65 v`。
##
## **但它在真机上测不出来**：平移模式极速下，`GROUND_GUARD_ALT = 50 m` 这条门槛意味着
## 拉起窗口只有 `26 m / (v · sinθ)` —— v = 2268 时 θ = 15° 只有 **0.044 s**（2.6 帧）。
## 任何"俯角大到让这一笔起作用"的俯冲都来不及拉起来。⇒ 只断言**结构**，
## 并把这条**记成「下一步该动阈值」的证据**（设计文档 §2.3 第二步）。
##
## ⚠️ 平移模式**不锁目标时根本不会俯冲**：`_apply_translate()` 在无目标时把底速的
## y 分量强制归零（`fwd.y = 0`）⇒ 唯一会撞地的场景就是「锁着一台下方目标」。
## ⑤ 段因此**必须**有锁定目标 —— 这也是 `face_target = null` 那一笔存在的理由。

const GUARD_FRAMES := 40
## 目标在水平线下约 6°：浅到来得及拉起（0.13 s 窗口），又足够触发（下坠 > 40 m/s）。
const FOE_DIST := 40000.0
const FOE_DROP_DEG := 6.0


static func run(t: T, host: Node) -> void:
	t.suite("GroundGuard / ① 结构：平移模式下 `_assist` 真的在跑（B3）")
	await _structure(t, host)
	t.suite("GroundGuard / ② 口径：压杆读 translate_dir.y 而不是 control_input.x（B3）")
	await _pitch_source(t, host)
	t.suite("GroundGuard / ③ 夺杆：三个写点按模式分家（B3）")
	await _command(t, host)
	t.suite("GroundGuard / ④ 老路未变：飞行操纵那一支逐字不动（B3）")
	await _legacy(t, host)
	t.suite("GroundGuard / ⑤ 真机：锁着下方目标松手 ⇒ 真的爬起来了（B3）")
	await _live(t, host)
	t.suite("GroundGuard / ⑥ 深俯冲（33°）提前自动拉升")
	await _deep_dive(t, host)
	t.suite("GroundGuard / ⑦ 纯函数：地形告警的门随垂速缩放（★63-15）")
	_warn_fn(t, host)


# ================================================================ 舞台

## 造一块**顶面正好在 y = 0** 的地（与 `suite_round14._assist_ground_guard` 同一口径）
## + 一个玩家机。返回 `{c, pc, ground}`。
##
## ⚠️ 必须 await：碰撞体要过一帧物理才进空间，射线才打得到。
static func _stage(host: Node, pos: Vector3) -> Dictionary:
	Game.reset()
	var c := Node3D.new()
	c.name = "GroundGuardStage"
	host.add_child(c)
	var ground := StaticBody3D.new()
	ground.collision_layer = FlightBody.WORLD_LAYER
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12000.0, 40.0, 12000.0)
	cs.shape = box
	ground.add_child(cs)
	c.add_child(ground)
	ground.global_position = Vector3(0, -20.0, 0)
	var pc := PlayerController.new()
	pc.name = "GuardProbe"
	# 柯西：辅助开 + 没骑板 + 非巡航形态 ⇒ **平移模式**（`assist_uses_translation`）。
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.projectile_container = c
	c.add_child(pc)
	# 关掉物理帧：`_think()` 就不跑 ⇒ `translate_mode` / `translate_dir` /
	# `control_input` 全由测试精确摆布（与 `suite_round14` 同一手法）。
	pc.set_physics_process(false)
	pc.assist_on = true
	pc.translate_mode = true
	pc.global_position = pos
	await host.get_tree().physics_frame
	return {"c": c, "pc": pc, "ground": ground}


## 摆一个"低空下坠"的初态：离地 40 m、垂速 -200 m/s。
static func _low_dive(pc: PlayerController) -> void:
	pc.global_position = Vector3(0, 40.0, 0)
	pc.fm.speed = 900.0
	pc.fm.velocity = Vector3(0.0, -200.0, -800.0)


static func _teardown(host: Node, st: Dictionary) -> void:
	(st["c"] as Node).free()
	await host.get_tree().process_frame
	Game.reset()


# ================================================================ ① 结构

static func _structure(t: T, host: Node) -> void:
	var st: Dictionary = await _stage(host, Vector3(0, 600.0, 0))
	var pc: PlayerController = st["pc"]
	_low_dive(pc)
	pc.translate_dir = Vector3.ZERO
	var asst: FlightAssist = pc.get("_assist")
	# 前置：改前这里恒为 INF（平移模式根本没跑过 `update()`）
	t.ok(not is_finite(asst.ground_time), "前置：还没跑过 `_tick_assist` ⇒ ground_time 是 INF")

	pc.call("_tick_assist", 0.016)
	t.ok(is_finite(asst.ground_time),
		"★ 平移模式下 `_assist.update()` 真的跑了：ground_time = %.4f s" % asst.ground_time)
	t.ok(is_finite(asst.ground_dist), "对地高度也拿到了：%.2f m" % asst.ground_dist)
	t.near(asst.ground_dist, 40.0, 1.0, "对地高度就是摆的 40 m（地面顶面在 y = 0）")
	t.not_ok(pc.get("_auto_pull_up"),
		"只跑一帧不够宽限期（%.2f s）⇒ 还没接管" % FlightAssist.RELEASE_GRACE)

	for i in GUARD_FRAMES:
		pc.translate_dir = Vector3.ZERO
		pc.call("_tick_assist", 0.05)
	print("[GroundGuard] 结构读数: ground_time=%.4f  ground_dist=%.2f  system_event=%s"
		% [asst.ground_time, asst.ground_dist, str(pc.system_event)])
	t.ok(pc.get("_auto_pull_up"),
		"松手 + 下坠 -200 m/s + 离地 40 m ⇒ **接管**（改前：一次都不会发生）")
	t.ok(str(pc.system_event).contains("接管"), "接管有提示：%s" % str(pc.system_event))
	t.ok(str(pc.system_event).contains("自动改出"), "提示走的是「自动改出」那条系统提示行")
	# 与老路同源的常数：触发窗口 = 地面探头视界（两套数不一致就会出现"探头看见了却不拉"）
	t.near(FlightAssist.RELEASE_PULL_TIME, FlightAssist.GROUND_TIME, 0.001,
		"触发窗口与地面探头视界同源（%.2f s）" % FlightAssist.RELEASE_PULL_TIME)
	await _teardown(host, st)


# ================================================================ ② 口径

static func _pitch_source(t: T, host: Node) -> void:
	var st: Dictionary = await _stage(host, Vector3(0, 600.0, 0))
	var pc: PlayerController = st["pc"]
	_low_dive(pc)

	# ---- ① 压杆 = `translate_dir.y = -1`（按 E 下降）⇒ 一点不干预 ----
	pc.control_input = Vector3.ZERO
	for i in GUARD_FRAMES:
		pc.translate_dir = Vector3.DOWN
		pc.call("_tick_assist", 0.05)
	t.not_ok(pc.get("_auto_pull_up"),
		"按着 E 往地里扎（translate_dir.y = -1）⇒ **不接管**（主动撞地是玩家的自由）")

	# ---- ② `control_input.x = -1` **不算**压杆 ----
	#
	# ⚠️ 这一条就是"误把 `control_input.x` 当压杆"那个写法的牙齿：
	# 平移模式下 `control_input` 每帧被 `_read_translate_input()` 清零（`:734`），
	# 它是**死值**。若实现读它，下面这帧 `control_input.x = -1` 会让它**不接管** ⇒ 红。
	pc.translate_dir = Vector3.ZERO
	pc.control_input = Vector3(-1.0, 0.0, 0.0)
	for i in GUARD_FRAMES:
		pc.translate_dir = Vector3.ZERO
		pc.control_input = Vector3(-1.0, 0.0, 0.0)
		pc.call("_tick_assist", 0.05)
	t.ok(pc.get("_auto_pull_up"),
		"`translate_dir.y = 0` ⇒ 算「松手」⇒ 接管 —— **与 `control_input.x` 无关**")
	t.near(pc.control_input.x, -1.0, 0.0001,
		"而且接管**没把 `control_input` 掰成 1.0**（那会暴露走错支路）")

	# ---- ③ 另一半：`translate_dir.y` 一旦有值就不接管 ----
	# 把 `_auto_pull_up` 复位到"未接管"，再确认"轻按一下 E"同样不接管。
	pc.set("_auto_pull_up", false)
	for i in 6:
		pc.translate_dir = Vector3(0.0, -0.9, 0.0)
		pc.call("_tick_assist", 0.05)
	t.not_ok(pc.get("_auto_pull_up"),
		"只按了 0.9 杆的 E（translate_dir.y = -0.9）⇒ 同样不接管")
	await _teardown(host, st)


# ================================================================ ③ 夺杆

static func _command(t: T, host: Node) -> void:
	var st: Dictionary = await _stage(host, Vector3(0, 600.0, 0))
	var pc: PlayerController = st["pc"]
	var c: Node3D = st["c"]
	var foe := Node3D.new()
	c.add_child(foe)
	_low_dive(pc)
	# 钉住"玩家手里那几样"：接管只许动它自己那三笔
	pc.control_input = Vector3(-0.4, 0.2, 0.9)
	pc.translate_dir = Vector3.ZERO
	pc.translate_fwd = Vector3.FORWARD
	pc.face_target = foe
	for i in GUARD_FRAMES:
		pc.control_input = Vector3(-0.4, 0.2, 0.9)
		pc.translate_dir = Vector3.ZERO
		pc.call("_tick_assist", 0.05)
	t.ok(pc.get("_auto_pull_up"), "前置：已经接管")

	# ① 抬头 = 满杆上升
	t.ok(pc.translate_dir == Vector3.UP,
		"① `translate_dir = UP`（%s）—— 平移模式的「满杆抬头」就是满杆 Q" % str(pc.translate_dir))
	# ② 清掉 W 那一份留档
	t.ok(pc.translate_fwd == Vector3.ZERO,
		"② `translate_fwd = ZERO`（留着旧值，那个减法会把上升这一份也当「前进」削掉 85%%）")
	# ③ 摘掉朝向
	t.ok(pc.face_target == null,
		"③ `face_target = null` —— 不清它，朝目标飞的底速会继续往下扎")
	# ④ 不加速
	t.not_ok(pc.fm.boosting, "接管期间不保持加速（加速会把拉升半径撑大）")
	# ⑤ 不碰 control_input（证明走的是平移那一支、不是老路）
	t.near(pc.control_input.x, -0.4, 0.0001,
		"⑤ `control_input.x` 一个分量都没被写（老路才会写它）")
	t.near(pc.control_input.z, 0.9, 0.0001, "⑤ `control_input.z` 也没被压平（老路会 clampf 到 0.4）")

	# ⑥ 只清 `face_target`，**不动**测试通道 `face_target_override`
	var ov := Node3D.new()
	c.add_child(ov)
	pc.face_target_override = ov
	for i in 6:
		pc.translate_dir = Vector3.ZERO
		pc.call("_tick_assist", 0.05)
	t.ok(pc.face_target_override == ov,
		"⑥ `face_target_override`（测试/调试通道，优先级更高）**不许被清**")
	await _teardown(host, st)


# ================================================================ ④ 老路

static func _legacy(t: T, host: Node) -> void:
	var st: Dictionary = await _stage(host, Vector3(0, 600.0, 0))
	var pc: PlayerController = st["pc"]
	# 阿利宙斯巡航形态 / 骑板那一支：`translate_mode = false`
	pc.translate_mode = false
	_low_dive(pc)
	pc.translate_dir = Vector3.FORWARD          # 老路**不许**碰它
	for i in GUARD_FRAMES:
		pc.control_input = Vector3(0.0, 0.0, 0.9)
		pc.translate_dir = Vector3.FORWARD
		pc.call("_tick_assist", 0.05)
	t.ok(pc.get("_auto_pull_up"), "老路：松手 + 下坠 + 离地 40 m ⇒ 接管（行为一字未变）")
	t.near(pc.control_input.x, 1.0, 0.0001, "老路接管 = `control_input.x = 1.0`（满抬头）")
	t.near(pc.control_input.z, 0.4, 0.001, "老路顺带压平坡度（`clampf(z, -0.4, 0.4)`）")
	t.not_ok(pc.fm.boosting, "老路接管期间也不加速")
	t.ok(pc.translate_dir == Vector3.FORWARD,
		"老路**不碰** `translate_dir`（模式分家的另一面）")
	await _teardown(host, st)


# ================================================================ ⑤ 真机

static func _live(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	c.name = "GroundGuardLive"
	host.add_child(c)
	var ground := StaticBody3D.new()
	ground.collision_layer = FlightBody.WORLD_LAYER
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60000.0, 40.0, 60000.0)
	cs.shape = box
	ground.add_child(cs)
	c.add_child(ground)
	ground.global_position = Vector3(0, -20.0, 0)

	var pc := PlayerController.new()
	pc.name = "GuardLive"
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.projectile_container = c
	c.add_child(pc)
	pc.controls_enabled = true
	pc.assist_on = true

	# ⚠️ 目标**必须在下方**：平移模式无目标时底速的 y 被强制归零（`fwd.y = 0`）
	# ⇒ 不锁目标根本不会俯冲，也就没有"撞地"这回事。
	var foe := BanditAI.new()
	foe.name = "GuardFoe"
	foe.team = 1
	foe.profile = SuitProfile.messer_m01()
	foe.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	foe.projectile_container = c
	c.add_child(foe)
	foe.set_physics_process(false)              # 静止靶
	foe.global_position = Vector3(0.0, 200.0 - FOE_DIST * tan(deg_to_rad(FOE_DROP_DEG)), -FOE_DIST)
	var lk := LockOnSystem.new()
	c.add_child(lk)
	pc.lock = lk
	lk.target = foe

	pc.global_position = Vector3(0, 200.0, 0)
	pc.look_at(foe.global_position, Vector3.UP)
	pc.fm.speed = pc.profile.player_top_speed()
	pc.fm.align_velocity(pc.forward())
	await host.get_tree().physics_frame

	var triggered := false
	var climbed := false
	var min_y := 1.0e9
	var frames := 0
	for i in 900:
		await host.get_tree().physics_frame
		frames += 1
		if not pc.alive:
			break
		min_y = minf(min_y, pc.global_position.y)
		if pc.assist_state()["auto_pull"]:
			triggered = true
			if pc.fm.velocity.y > 0.0:
				climbed = true
				break
	print("[GroundGuard] 真机读数: frames=%d  min_y=%.1f m  vy=%.1f m/s  y_end=%.1f m  alive=%s"
		% [frames, min_y, pc.fm.velocity.y, pc.global_position.y, str(pc.alive)])
	t.ok(pc.alive,
		"一路没撞地（最低 %.1f m；`CRASH_ALTITUDE` = %.0f）" % [min_y, FlightBody.CRASH_ALTITUDE])
	t.ok(triggered,
		"★ 低空下坠 + 松手 ⇒ 防撞地**真的接管了**（%d 帧后）" % frames)
	t.ok(climbed,
		"接管之后垂速转正 ⇒ **真的在爬升**，不是「提示弹了但照样扎下去」")
	t.gt(pc.fm.velocity.y, 0.0, "垂速 %.1f m/s > 0" % pc.fm.velocity.y)
	t.gt(min_y, FlightBody.CRASH_ALTITUDE + 20.0,
		"预测防撞地在死亡线之前保留余量（最低 %.1f m）" % min_y)

	# 再跑一段，确认高度**持续**上升（不是抽搐一下）
	var y0 := pc.global_position.y
	for i in 40:
		await host.get_tree().physics_frame
	t.gt(pc.global_position.y, y0 + 10.0,
		"再跑 40 帧高度继续上升：%.1f → %.1f m" % [y0, pc.global_position.y])

	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ================================================================ ⑥ B3-2 现场

## ⑥ 深俯冲的俯角：取 `TRANSLATE_OFFSET = 0.65` 的 `atan` = **33°**。
##
## 为什么是这个数：平移模式下「往下」这个动作落在 `translate_dir.y = -1`（E 键），
## 而 `FlightBody.translate_offset_vec()` 给它的权重就是 `TRANSLATE_OFFSET`；
## 底速朝目标、修正量朝下，两者叠加后的净俯角 = `atan(0.65)` = **33.0°**。
## ⇒ 这不是我挑的一个“很斜”的极端值，它就是**E 键的实测角**。
const DEEP_DROP_DEG := 33.0
## 起始高度（米）：33° 俯冲下 4000 m 只够跑 3.2 s，观察窗足够。
const DEEP_Y := 4000.0
## 目标距离（米）：**放得很远** —— 方向只要落在 33° 俯下就行。
## ⚠️ 别把它拉近：近目标会让机头在**目标那个高度**上停住（实测 5 km 时 `min_y` 卡在
## 759.6 m、跑满 1200 帧都没到地）。40 km ⇒ `y ≈ -22 km`（**目标落在地下，刻意如此**：
## 这一节只借它的**方向**，机体得一路俯冲到真正的（y = 0 的）地面）。
const DEEP_DIST := 40000.0


## **B3-2 现场**：与 ⑤ 同一张舞台，**只改两件事** —— 俯角 6° → **33°**、起始高度 200 m → **4000 m**。
##
## 为什么这一节在改动前**必然红**（设计文档 §2.3「修正 4」）：
##   · 接管门 = `GROUND_GUARD_ALT = 50 m`，判死线 = `CRASH_ALTITUDE = 24 m`
##     ⇒ 两者之间只有 **26 m**；
##   · 而平移模式**恒加力**（`_read_translate_input()` 里 `fm.boosting = true`）
##     ⇒ 加力极速下 33° 的垂速 ≈ **1235 m/s**；
##   · ⇒ 拉起窗 = 26 / 1235 = **0.021 s**（1.3 帧）。任何拉杆都来不及。
##
## ⇒ 这一节就是 B3-2 的**负对照**：改动前它必须红，改完必须绿。
##
## ⚠️ 不要用“抬高起始高度”去把它刷绿：4000 m 只是拉长观察窗，
## 决定结局的是 `50 → 24` 那 26 m，与起始高度无关。
static func _deep_dive(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	c.name = "GroundGuardDeep"
	host.add_child(c)
	var ground := StaticBody3D.new()
	ground.collision_layer = FlightBody.WORLD_LAYER
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60000.0, 40.0, 60000.0)
	cs.shape = box
	ground.add_child(cs)
	c.add_child(ground)
	ground.global_position = Vector3(0, -20.0, 0)

	var pc := PlayerController.new()
	pc.name = "GuardDeep"
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.projectile_container = c
	c.add_child(pc)
	pc.controls_enabled = true
	pc.assist_on = true

	# ⚠️ 目标**必须在下方**：平移模式无目标时底速的 y 被强制归零（`fwd.y = 0`）
	# ⇒ 不锁目标根本不会俯冲，也就没有“撞地”这回事。
	var foe := BanditAI.new()
	foe.name = "GuardDeepFoe"
	foe.team = 1
	foe.profile = SuitProfile.messer_m01()
	foe.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	foe.projectile_container = c
	c.add_child(foe)
	foe.set_physics_process(false)
	foe.global_position = Vector3(0.0, DEEP_Y - DEEP_DIST * tan(deg_to_rad(DEEP_DROP_DEG)), -DEEP_DIST)
	var lk := LockOnSystem.new()
	c.add_child(lk)
	pc.lock = lk
	lk.target = foe

	pc.global_position = Vector3(0, DEEP_Y, 0)
	pc.look_at(foe.global_position, Vector3.UP)
	pc.fm.speed = pc.profile.player_boost_speed()
	pc.fm.align_velocity(pc.forward())
	await host.get_tree().physics_frame

	var triggered := false
	## 地形告警**第一次出现**时的高度 —— 本轮唯一要证的"在 50 m 之上"就靠它。
	var warn_y := -1.0
	var min_y := 1.0e9
	var frames := 0
	var climbing_frames := 0
	for i in 1200:
		await host.get_tree().physics_frame
		frames += 1
		if not pc.alive:
			break
		min_y = minf(min_y, pc.global_position.y)
		if warn_y < 0.0 and pc.assist_state()["auto_pull"]:
			warn_y = pc.global_position.y
		if pc.assist_state()["auto_pull"]:
			triggered = true
		if triggered and pc.fm.velocity.y > 10:
			climbing_frames += 1
		if climbing_frames >= 60:
			break
	var msg := "[GroundGuard] 深俯冲读数: drop=%.0f deg  y0=%.0f m  frames=%d  min_y=%.1f m  vy=%.1f m/s  warn_y=%.1f m  grounded=%s"
	print(msg % [DEEP_DROP_DEG, DEEP_Y, frames, min_y, pc.fm.velocity.y, warn_y,
		str(not pc.alive)])

	# 2026-10-08: predictive protection replaces the former accepted crash case.
	t.ok(warn_y > FlightAssist.GROUND_GUARD_ALT,
		"预测接管发生在旧 50 m 门槛之上（y = %.1f m）" % warn_y)
	t.ok(triggered,
		"高速深俯冲触发自动拉升（%d 帧）" % frames)

	# New acceptance: intervene early and survive, rather than preserve a crash.
	t.ok(pc.alive and climbing_frames >= 60,
		"极速深俯冲自动改出并持续爬升（最低 %.1f m）" % min_y)
	t.gt(min_y, FlightBody.CRASH_ALTITUDE + 20.0,
		"拉升全程保留物理净空（最低 %.1f m）" % min_y)

	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ================================================================ ⑦ 纯函数

## `FlightAssist.terrain_warning()` 的边界。
##
## 这一层是 ★63-15 唯一的**新行为**（50 m 之上只报警、不改出），
## 所以它的门必须钉死：**"还能撑几秒"，不是"离地几米"**。
## ⚠️ 写成固定高度门就退回 B3-2 了 —— 那正是老板拍板**不动**的东西。
static func _warn_fn(t: T, host: Node) -> void:
	# ---- 不报的那一侧 ----
	t.not_ok(FlightAssist.terrain_warning(30.0, 0.0), "平飞（垂速 0）⇒ 不报")
	t.not_ok(FlightAssist.terrain_warning(30.0, 12.0), "在爬升 ⇒ 不报")
	t.not_ok(FlightAssist.terrain_warning(30.0, -39.0), "下坠 39 m/s < DIVE_SINK 40 ⇒ 不报")
	t.ok(FlightAssist.terrain_warning(30.0, -40.0), "正好 -40 ⇒ 报（`>` 是严格大于，等号落在「算俯冲」那一侧）")
	t.not_ok(FlightAssist.terrain_warning(INF, -1235.0), "探头打空（INF）⇒ 不报")
	t.not_ok(FlightAssist.terrain_warning(0.0, -1235.0), "离地 0 ⇒ 不报")
	# ---- 报的那一侧：门 = TERRAIN_WARN_TIME(2.5) × |垂速| ----
	t.not_ok(FlightAssist.terrain_warning(3001.0, -1200.0), "离地 3001 m > 门 3000 m ⇒ 不报（边界外）")
	t.ok(FlightAssist.terrain_warning(2999.0, -1200.0), "离地 2999 m < 门 3000 m ⇒ 报（边界内）")
	# ---- ★ 门**随垂速缩放**：这就是"平飞不碰、俯冲提前"的全部机理 ----
	t.not_ok(FlightAssist.terrain_warning(500.0, -100.0), "慢坠 100 m/s 时离地 500 m ⇒ 不报（门只有 250 m）")
	t.ok(FlightAssist.terrain_warning(200.0, -100.0), "离地 200 m < 门 250 m ⇒ 报 —— 门是时间，不是高度")
	# ---- ★ 硬门守卫：老板 2026-10-07 拍板「GROUND_GUARD_ALT 一字不动」----
	t.near(FlightAssist.GROUND_GUARD_ALT, 50.0, 0.0001,
		"★ GROUND_GUARD_ALT 仍是 50.0（本轮拍板：字面不动）")
	t.not_ok(FlightAssist.terrain_warning(1500.0, 0.0),
		"★ 平飞时哪怕只有 1500 m 也不报 ⇒ 2026-09-21「别抢杆」的本意完整保住")
