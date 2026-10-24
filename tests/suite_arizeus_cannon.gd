class_name SuiteArizeusCannon
extends RefCounted
## 阿利宙斯的**匀速弹速 + 蓄力激光炮**（2026-09-28 用户指定）。
##
## ## 需求原文
## > 阿利宙斯光束步枪弹速一致：很快但是能被肉眼可见：大约速度为机体的 7 倍。
## > 然后光束步枪模式下长按鼠标左键 1.7s 进入蓄力模式，蓄力模式可以一直蓄力
## > （伤害和光束大炮的时间不变），松手会释放一发每秒 35 伤害、持续时间 4s 的
## > 超级激光炮（光束柱炮口需要有大量粒子飞溅），光束大炮冷却时间 20s，
## > 使用光束大炮之后光束步枪会过热，进入一个 15s 的换弹 cd。
## > 光束大炮只能在弹夹全满的时候使用。
##
## ## 追补（2026-09-28 第二轮）
## > 光束大炮锁定有点太死了：光束大炮长度为 10km，
## > 发射方向和火神炮差不多，都是跟随着鼠标方向走的。
## ⇒ 柱长 2600 → **10000 m**；朝向不再读 `lock.target`，改读 `aim_forward()`
## （与火神炮 / 光束步枪 / 准星同一个真源）。判据在第六组。
##
## ## 拍板时的两个补充
##   - 弹速基准：**固定值 10900 m/s**（不是"每台机各自 ×7"）；
##   - 范围：大炮**三个形态都有**（★63-14 起核心 · 量产型ν高达也有）；
##   - 开火逻辑：「阿利宙斯的开枪逻辑从**按下鼠标发射**变为**松开鼠标发射**」。
##
## ## 分六组，因为它们坏起来的样子完全不同
##
## | 组 | 坏了会怎样 |
## |---|---|
## | 数据层 | 三形态数值不一致 / 核心的炮**没接上路由**（或反过来把它的连发废掉） |
## | 弹道层 | "匀速"名不副实（还在分段）；或把**别的机体**也改成匀速 |
## | 门禁与副作用 | 弹夹不满也能放；放过之后冷却/过热没上 |
## | 激光柱 | 伤害不是"每秒 35"；或 4 秒之后柱不消失 |
## | 输入层接线 | 代码全对但**没有人读它** —— 症状与需求没做**一模一样** |
## | 长度与朝向 | 柱长还停在 2600（天上断一截）；或朝向被锁定拽走（准星指 A、柱子扎 B，**全绿**） |
## | 弹体形状 | 还是等粗圆柱（"没做"）；或**粗的那端朝着炮口**（炮口成喇叭 —— 半径全合法、**全绿**） |
##
## ⚠️ **最后那一组是本工程栽得最多的地方**："方法都写好了、却没有读取点"
## （1.2 的 `switch_weapon` 就是这么废掉的），所以这里扫**源码位置关系**，
## 不只看"函数存不存在"。

const PLAYER_PATH := "res://scripts/flight/player_controller.gd"
const BODY_PATH := "res://scripts/flight/flight_body.gd"
const CANNON_PATH := "res://scripts/combat/beam_cannon.gd"
const PROFILE_PATH := "res://scripts/data/suit_profile.gd"


static func run(t: T, host: Node) -> void:
	t.suite("ArizeusCannon / 数据层（匀速弹速 / 大炮参数 / 适用形态）")
	_data(t)
	t.suite("ArizeusCannon / 匀速弹道（飞行时间与等效速度）")
	_ballistics(t)
	t.suite("ArizeusCannon / 门禁与副作用（满弹夹 / 20s 冷却 / 15s 过热）")
	await _gates(t, host)
	t.suite("ArizeusCannon / 激光柱（持续伤害 / 4 秒寿命）")
	await _beam(t, host)
	t.suite("ArizeusCannon / 接线（松手发射 / 蓄力门槛 / 提示与 HUD）")
	_wiring(t)
	t.suite("ArizeusCannon / 光束柱的长度与朝向（10 km / 跟随鼠标）")
	await _aim(t, host)
	t.suite("ArizeusCannon / 弹体形状（圆台：炮口细、末端 ×2）")
	await _taper(t, host)


# ------------------------------------------------------------ ① 数据层

static func _data(t: T) -> void:
	var names := ["巡航", "常态", "核心"]
	var forms := [SuitProfile.ArizeusForm.CRUISE, SuitProfile.ArizeusForm.NORMAL,
		SuitProfile.ArizeusForm.CORE_NU]

	# 用户拍的数：固定值 10900
	t.near(SuitProfile.ARIZEUS_RIFLE_STEADY_SPEED, 10900.0, 0.001,
		"用户指定：匀速弹速 = **固定值 10900 m/s**")

	# 三个形态统一（用户说的是"阿利宙斯"，不是某个形态）
	for i in forms.size():
		var p := SuitProfile.arizeus(forms[i])
		t.near(p.rifle_steady_speed, SuitProfile.ARIZEUS_RIFLE_STEADY_SPEED, 0.001,
			"%s：匀速弹速 = %.0f m/s" % [names[i], p.rifle_steady_speed])

	# 大炮只在常态 / 巡航
	t.ok(SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL).cannon_enabled,
		"常态形态有蓄力激光炮")
	t.ok(SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).cannon_enabled,
		"巡航形态有蓄力激光炮")
	t.ok(SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU).cannon_enabled,
		"★63-14：核心 · 量产型ν高达**也有**蓄力激光炮（用户追补）")

	# 松手发射与"有大炮"绑定（用户指定）
	for i in [0, 1]:
		var p := SuitProfile.arizeus(forms[i])
		t.ok(p.rifle_fire_on_release,
			"%s：开枪逻辑是**松开左键才发射**" % names[i])
	t.not_ok(SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU).rifle_fire_on_release,
		"★63-14 核心也有炮之后**仍保持**按下连发（8 发 / 0.62 s 的连发枪，改松手会废掉连射）")

	# 五个数
	var n := SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)
	t.near(n.cannon_charge_time, 1.7, 0.001, "进入蓄力的门槛 = 1.7 s")
	t.near(n.cannon_dps, 35.0, 0.001, "激光柱每秒伤害 = 35")
	t.near(n.cannon_duration, 4.0, 0.001, "激光柱持续时间 = 4 s")
	t.near(n.cannon_cooldown, 20.0, 0.001, "大炮冷却 = 20 s")
	t.near(n.cannon_overheat_reload, 15.0, 0.001, "用过之后步枪过热换弹 = 15 s")

	# 别的机体**一个字段都不该被带偏**
	#
	# ⚠️ **佩涅罗佩 2026-09-29 从这张表里移除**（用户：「把阿利宙斯的光束大炮也给佩涅罗佩」）：
	#    她的 `cannon_enabled` 现在是**故意**的 true，所以"她不改"这条不能写在这儿。
	#    但**匀速弹速与松手单发仍必须不外溢** —— 她走的是 `PlayerController.rifle_press_route()`
	#    那条**条件路由**（满弹匣才蓄力、其余照旧连发），不是阿利宙斯这条常开的松手路。
	#    她那门炮的判据在 `suite_penelope_cannon.gd`。
	#    ⛔ 别把她整条加回来：本循环断言的是"**阿利宙斯的匀速弹速与松手发射不外溢**"。
	for p: SuitProfile in [SuitProfile.xi(), SuitProfile.messer_m01()]:
		t.near(p.rifle_steady_speed, 0.0, 0.001,
			"%s 仍走全局两段制（匀速是阿利宙斯专属）" % p.display_name)
		t.not_ok(p.cannon_enabled, "%s 没有蓄力激光炮" % p.display_name)
		t.not_ok(p.rifle_fire_on_release, "%s 仍是按下连发" % p.display_name)
	var pen := SuitProfile.penelope()
	t.near(pen.rifle_steady_speed, 0.0, 0.001,
		"佩涅罗佩仍走全局两段制（匀速弹速不外溢）")
	t.not_ok(pen.rifle_fire_on_release,
		"★ 佩涅罗佩**不是**松手单发（用户拍板「保住连发」）——她的路由见 suite_penelope_cannon")


# ------------------------------------------------------------ ② 弹道层

static func _ballistics(t: T) -> void:
	var sp := SuitProfile.ARIZEUS_RIFLE_STEADY_SPEED
	var d := 1000.0

	# 匀速的字面含义：时间与距离成正比
	t.near(SuitProfile.rifle_flight_time(d, sp), d / sp, 1e-9,
		"匀速：1 km 用 %.4f s" % (d / sp))
	t.near(SuitProfile.rifle_effective_speed(d, sp), sp, 0.001,
		"匀速：等效弹速就是那个速度本身")
	var t1 := SuitProfile.rifle_flight_time(300.0, sp)
	var t2 := SuitProfile.rifle_flight_time(3000.0, sp)
	t.near(t2 / t1, 10.0, 1e-6,
		"距离 ×10 ⇒ 时间 ×10（全程同一个速度 —— “弹速一致”的字面判据，两段制下这条不成立）")

	# 观感判据：快到"打出去就到了"就看不见，慢到"和机体并排"又读不出射出去
	var flight := d / sp
	t.between(flight, 0.05, 0.15,
		"1 km 飞 %.3f s（≈ %.1f 帧 @60）—— 很快，但眼睛跟得上" % [flight, flight * 60.0])
	# 而上限是"机体不能飞过自己的弹"（本工程反复栽过）
	var fastest := SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).player_boost_speed()
	t.gt(sp, fastest,
		"匀速弹速 %.0f m/s > 最快的加力极速 %.0f m/s（机体飞不过自己的弹）" % [sp, fastest])

	# ⚠️ 回归保护：**默认参数一个字都没变**（别的机体不受影响）
	t.near(SuitProfile.rifle_flight_time(d), SuitProfile.rifle_flight_time(d, 0.0), 1e-12,
		"省略 steady 时仍是老的两段制（既有调用方无需改动）")
	# ⚠️ **不要写“匀速一定比老弹道快”** —— 1 km 内恰恰相反：
	#    两段制的“慢”全在出膛那 30%（2880 m/s 走完 300 m）0.104 s），
	#    而后 70% 是 90000 m/s —— 于是平均下来 1 km 只要 0.1119 s；
	#    匀速 10900 反而更快（0.0917 s）。交叉点约 3.6 km。
	var t_steady := SuitProfile.rifle_flight_time(d, sp)
	var t_two := SuitProfile.rifle_flight_time(d)
	t.lt(t_steady, t_two,
		"1 km：匀速 %.4f s **快于**两段制 %.4f s（老弹道的“肉眼可见”全在出膛 30%%）"
			% [t_steady, t_two])
	t.lt(SuitProfile.rifle_flight_time(6000.0), SuitProfile.rifle_flight_time(6000.0, sp),
		"6 km：两段制反超匀速（交叉点约 3.6 km）—— 远处的 90000 m/s 才显出来")
	t.lt(SuitProfile.RIFLE_LAUNCH_SPEED, sp,
		"匀速 %.0f 比出膛段 %.0f 快（阿利宙斯的第一段也是“很快”的那一档）" % [sp, SuitProfile.RIFLE_LAUNCH_SPEED])


# ------------------------------------------------------------ ③ 门禁与副作用

static func _make(container: Node3D, suit: SuitProfile, team: int,
		as_player := false) -> FlightBody:
	var u := FlightBody.new()
	u.team = team
	u.is_player = as_player
	u.profile = suit
	u.projectile_container = container
	container.add_child(u)
	u.global_position = Vector3(0, 3000, 0)
	return u


static func _cannon_count(container: Node) -> int:
	var n := 0
	for ch in container.get_children():
		if ch is BeamCannon:
			n += 1
	return n


static func _first_cannon(container: Node) -> Node3D:
	for ch in container.get_children():
		if ch is BeamCannon:
			return ch
	return null


static func _gates(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _make(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL), 0)

	# 满弹夹 = 可放
	t.eq(u.rifle_mag, u.profile.rifle_magazine, "出场弹匣是满的（%d 发）" % u.profile.rifle_magazine)
	t.ok(u.cannon_available(), "常态形态有大炮")
	t.ok(u.cannon_ready(), "满弹夹 + 无冷却 ⇒ 可以放")

	# ---- 用户点名的硬门槛：只能在弹夹全满时使用 ----
	u.rifle_cooldown = 0.0
	t.ok(u.fire_beam(true, null), "先打一发普通光束")
	await host.get_tree().physics_frame
	t.eq(u.rifle_mag, u.profile.rifle_magazine - 1, "弹匣掉了一发")
	t.not_ok(u.cannon_ready(), "弹夹不满 ⇒ 大炮不可用")
	t.not_ok(u.fire_cannon(null), "弹夹不满时 fire_cannon 被拒绝")
	t.near(u.cannon_cd_left, 0.0, 0.001, "被拒绝时**不产生**任何副作用（冷却没有被误启动）")
	t.not_ok(u.rifle_reloading, "被拒绝时也不会误触发过热换弹")

	# 补满 ⇒ 又能放
	u.rifle_mag = u.profile.rifle_magazine
	t.ok(u.cannon_ready(), "补满弹匣之后又能放")

	# ---- 真的放 ----
	var before := _cannon_count(c)
	t.ok(u.fire_cannon(null), "发射成功")
	# ⚠️ **先读数、再 await**：`fire_cannon()` 只在发射那一瞬间把冷却/换弹置满，
	#    等一帧的话 `_tick_weapons()` 会把两者各减 1/60 s，
	#    读数就从 20.0000 / 15.0000 变成 19.9833 / 14.9833 —— 1/60 的假失败（本套件栽过一次）。
	t.near(u.cannon_cd_left, u.profile.cannon_cooldown, 0.001,
		"大炮冷却 = %.0f s（从发射那一刻起算）" % u.profile.cannon_cooldown)
	t.ok(u.rifle_reloading, "光束步枪**立刻进入换弹**（用户指定“用过之后过热”）")
	t.near(u.reload_timer, u.profile.cannon_overheat_reload, 0.001,
		"过热换弹时长 = 15 s")
	t.eq(u.rifle_mag, u.profile.rifle_magazine,
		"大炮**不消耗弹匣**（用户只说“用过之后过热换弹”，没说吃子弹）")
	t.not_ok(u.fire_beam(true, null), "过热换弹期间连普通步枪也打不出（这就是“过热”的意思）")
	t.eq(u.cannon_cd_ratio(), 0.0,
		"刚打完：冷却进度 0（`cannon_cd_ratio()` 是**已走**的比例，1 = 转好）")
	# ↑ 这条也必须在 await 之前：走一帧就是 1/1200 而不是 0。
	await host.get_tree().physics_frame
	t.eq(_cannon_count(c) - before, 1, "场上多出**一条**激光柱")
	u.cannon_cd_left = u.profile.cannon_cooldown * 0.5
	t.near(u.cannon_cd_ratio(), 0.5, 0.001, "过半：冷却进度 0.5")
	u.cannon_cd_left = 0.0
	t.eq(u.cannon_cd_ratio(), 1.0, "走完：冷却进度 1")

	# ---- 冷却走完 + 弹匣满 ⇒ 又能放；但过热还在 ⇒ 仍然不行 ----
	u.rifle_mag = u.profile.rifle_magazine
	t.not_ok(u.cannon_ready(), "冷却好了、但**过热换弹还没走完** ⇒ 依然放不出")
	u.reload_timer = 0.0
	u.rifle_reloading = false
	t.ok(u.cannon_ready(), "过热也走完 ⇒ 恢复可用")

	# ---- ★63-14：核心形态**也有一门炮** ----
	#
	# 用户原话：「给量产型牛高达增加光束军刀和光束大炮」。
	# ⚠️ 本段在 ★63-14 之前写的是"核心连门都没有"（三条 not_ok）。现在正好反过来，
	#    但**硬门槛一条都没松**：弹夹不满照样放不出（下面那一对 not_ok 盯的就是它）。
	# ⚠️ 出厂时弹匣是**满的**（`FlightBody` 按 profile 容量灌满）—— 别先断言"空的"，
	#    本段第一版就是这么红的。
	var core := _make(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU), 0)
	t.ok(core.cannon_available(), "核心形态 cannon_available() 为 true（★63-14）")
	t.ok(core.cannon_ready(), "★ 出场即就绪（满弹匣 %d 发 + 无冷却 + 不换弹）"
		% core.profile.rifle_magazine)
	t.ok(core.fire_cannon(null), "★ 核心发射成功")
	# 打完那三条副作用照旧上（与常态 / 巡航走的是同一段代码）
	# ⚠️ 这两条必须**紧跟在发射后面** —— 下面那几行会把冷却 / 过热清掉，
	#    排到后面去就会读到被清过的值（本段第二版就是这么红的）。
	t.gt(core.cannon_cd_left, 0.0, "★ 核心：放完进冷却")
	t.ok(core.rifle_reloading, "★ 核心：放完步枪过热换弹")
	# ★ 反向：把冷却与过热都清掉、弹匣打剩一发 ⇒ 又放不出（硬门槛是「全满」）
	core.cannon_cd_left = 0.0
	core.rifle_reloading = false
	core.reload_timer = 0.0
	core.rifle_mag = core.profile.rifle_magazine - 1
	t.not_ok(core.cannon_ready(), "★ 弹夹不满 ⇒ 就绪不了（硬门槛是「全满」）")
	t.not_ok(core.fire_cannon(null), "★ 弹夹不满时 fire_cannon 被拒绝")
	core.rifle_mag = core.profile.rifle_magazine
	t.ok(core.cannon_ready(), "★ 再补满 ⇒ 又就绪")
	# 而它的普通步枪照样能打
	core.rifle_reloading = false
	core.reload_timer = 0.0
	core.rifle_mag = 1
	core.rifle_cooldown = 0.0
	t.ok(core.fire_beam(true, null), "核心形态的光束步枪不受影响")

	# ---- 巡航形态同样能放（不是只有常态） ----
	var cruise := _make(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE), 0)
	cruise.rifle_mag = cruise.profile.rifle_magazine
	t.ok(cruise.cannon_ready(), "巡航形态也能放（用户答“常态 + 巡航”）")
	t.ok(cruise.fire_cannon(null), "巡航形态发射成功")

	c.free()
	await host.get_tree().physics_frame


# ------------------------------------------------------------ ④ 激光柱

static func _beam(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	# attacker 当"玩家" ⇒ `Game.damage_dealt` / `ifield_dealt` 才会记账
	#（`_apply_damage()` 里那两个统计都要求 `source == Game.player`）。
	var attacker := _make(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL), 0, true)
	t.ok(Game.player == attacker, "attacker 已登记为玩家（伤害统计才有口径）")
	attacker.global_position = Vector3(0, 3000, 0)
	attacker.fm.align_velocity(attacker.forward())

	var victim := _make(c, SuitProfile.xi(), 1)
	victim.global_position = attacker.global_position + attacker.forward() * 400.0
	victim.fm.align_velocity(victim.forward())

	# ⚠️ **两个机体都冻住，并把瞄准方向钉在靶机上**（2026-09-28 改）。
	#
	# 这一条是实测出来的，不是"保险起见"：柱体改成跟 `aim_forward()` 之后
	#（用户："发射方向……跟随着鼠标方向走的"），`attacker` 空载时**机头每帧继续下俯
	# 0.55°**（飞行模型的自然姿态，实测 `dir.y` 逐帧 −0.00917），
	# 于是柱子 8 帧之后就扫到靶机下方去了 —— "每秒 35" 变成实测 **4.7**、第二秒 0。
	#
	# 那不是 bug，恰恰是"跟着准星"的**必然结果**（老版本追着 `target` 转，所以看不出来）。
	# 要钉住的是**测试自己**：断"每秒 35 的持续照射"，就必须让准星一直指着靶机 ——
	# 准星会飘的那种量法，量到的是"扫过"而不是"照住"。
	# "准星能带着柱子扫"另有判据，在第六组（那里只等 2 帧，不量伤害）。
	attacker.set_aim_direction((victim.global_position - attacker.global_position).normalized())
	attacker.set_physics_process(false)
	victim.set_physics_process(false)

	attacker.rifle_mag = attacker.profile.rifle_magazine
	var dealt0 := Game.damage_dealt + Game.ifield_dealt
	t.ok(attacker.fire_cannon(victim), "朝目标发射激光柱")
	var node := _first_cannon(c)
	t.ok(node != null, "柱体已生成")
	t.near(node.duration, 4.0, 0.001, "柱体自己的寿命参数 = 4 s")
	t.near(node.dps, 35.0, 0.001, "柱体自己的每秒伤害 = 35")

	# 跑 1 秒（60 物理帧）：累计伤害应落在 35 附近（统计在**减伤之前**记账，
	# 所以不受 I 立场 / 举盾的影响 —— 这里量的是"柱体给了多少"）。
	for i in 60:
		await host.get_tree().physics_frame
	var dealt := (Game.damage_dealt + Game.ifield_dealt) - dealt0
	t.gt(dealt, 0.0, "被照到 1 秒，确实在掉血（累计 %.1f）" % dealt)
	t.between(dealt, 25.0, 45.0, "≈ 每秒 35 伤害（实测 %.1f）" % dealt)

	# 伤害是**逐帧累积**的（不是一次砸 140）：再跑一秒应该再涨一截
	var dealt1 := Game.damage_dealt + Game.ifield_dealt
	for i in 60:
		await host.get_tree().physics_frame
	var dealt2 := (Game.damage_dealt + Game.ifield_dealt) - dealt1
	t.gt(dealt2, 0.0, "第二秒仍在持续结算（+%.1f）—— 是“持续照射”而不是“一发打光”"
		% dealt2)

	# 4 秒到点：柱自己消失（不真等 4 秒，直接把它的寿命推到边沿）
	node.set("_life", node.duration - 0.01)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	t.eq(_cannon_count(c), 0, "寿命走完 ⇒ 柱自己销毁（不会一直挂在场上）")

	c.free()
	await host.get_tree().physics_frame


# ------------------------------------------------------------ ⑥ 长度与朝向

## 用户 2026-09-28 追补的两条，**坏起来都不报错**，只能靠量：
##   · 柱长还停在 2600 ⇒ 打向天空时柱体在 2.6 km 处凭空断掉（画面里就是"短一截"）；
##   · 朝向还锁在 `lock.target` 上 ⇒ 准星指着 A、柱子扎在 B 身上，而**测试全绿**。
static func _aim(t: T, host: Node) -> void:
	# ---- ① 常量 ----
	t.near(BeamCannon.MAX_LEN, 10000.0, 0.001,
		"用户指定：柱体最长 10 km（原来是 2600 m）")

	# ---- ② 长度：真的量到 ----
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	# ⚠️ 量长度时**场上不能有别的碰撞体**：靶机自己就是 WORLD_LAYER 上的碰撞体，
	#    射线会在它身上截断 —— 那量出来的是"靶机有多远"（400 m），
	#    而这条断言会以为自己在验"柱长"。会撒谎的量法比不量更坏。
	var lone := _make(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL), 0, true)
	lone.global_position = Vector3(0, 3000, 0)
	lone.rifle_mag = lone.profile.rifle_magazine
	t.ok(lone.fire_cannon(null), "（场上只有它一台）发射")
	var n1 := _first_cannon(c)
	t.ok(n1 != null, "柱体已生成")
	# 展开口 0.12 s ⇒ 跑 12 帧之后 `vis == length`
	for i in 12:
		await host.get_tree().physics_frame
	var core: MeshInstance3D = null
	if n1 != null:
		core = n1.get("_core") as MeshInstance3D
	t.ok(core != null, "内核柱体存在（长度只能从它身上量）")
	if core != null:
		t.near(core.scale.y, BeamCannon.MAX_LEN, 1.0,
			"打向天空：柱体拉满到 %.0f m（实测 %.1f）" % [BeamCannon.MAX_LEN, core.scale.y])

	# ---- ③ 朝向：跟着准星走，不再被锁定拽走 ----
	#
	# 布置：靶机就在**机头正前方 400 m**，而准星指到**偏 40°** 的方向去。
	# 两种实现差 40°，一眼分得开：
	#   还锁着目标 ⇒ dir ≈ 机头（dot(forward) = 1.00，下面第二条会红）；
	#   真跟准星走 ⇒ dir ≈ 准星（dot(aim) = 1.00）。
	var victim := _make(c, SuitProfile.xi(), 1)
	victim.global_position = lone.global_position + lone.forward() * 400.0
	var fwd := Vector3(0.0, 0.0, -1.0)
	var aim := Vector3(sin(deg_to_rad(40.0)), 0.0, -cos(deg_to_rad(40.0))).normalized()
	lone.set_aim_direction(aim)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	if core != null:
		var dir := core.global_transform.basis.y.normalized()
		t.gt(dir.dot(aim), 0.999,
			"柱体朝向 = 准星方向（dot %.4f）—— 每帧重算，所以能扫" % dir.dot(aim))
		t.lt(dir.dot(fwd), 0.95,
			"而且它**确实偏离了机头**（dot %.4f）—— 锁定目标就在机头上，柱子没被拽回去"
				% dir.dot(fwd))
		# 再扭一下准星：柱子要跟着转（"跟随鼠标"的动态判据）
		var aim2 := Vector3(-sin(deg_to_rad(55.0)), 0.0, -cos(deg_to_rad(55.0))).normalized()
		lone.set_aim_direction(aim2)
		await host.get_tree().physics_frame
		var dir2 := core.global_transform.basis.y.normalized()
		t.gt(dir2.dot(aim2), 0.999,
			"准星再扭到另一侧，柱子跟着转（dot 新方向 %.4f）" % dir2.dot(aim2))

	# ---- ④ 源码侧：真源与位置关系 ----
	var body := _code(BODY_PATH)
	var bc := _code(CANNON_PATH)
	var i_fn := body.find("func cannon_aim_dir")
	t.gt(i_fn, 0, "`FlightBody.cannon_aim_dir()` 存在")
	if i_fn > 0:
		t.ok(body.substr(i_fn, 240).contains("aim_forward()"),
			"它返回 `aim_forward()` —— 与火神炮 / 光束步枪 / 准星**同一个真源**")
	var i_use := bc.find("cannon_aim_dir()")
	var i_tgt := bc.find("target.global_position")
	t.gt(i_use, 0, "柱体每帧取 `cannon_aim_dir()`")
	t.gt(i_tgt, i_use,
		"位置关系：先取准星方向，`target` 只作兜底 —— 顺序换回去就退回“锁定有点太死了”")
	t.ok(bc.contains("from + dir * MAX_LEN"),
		"射线长度用的是 MAX_LEN（不是另写一个数）")

	c.free()
	await host.get_tree().physics_frame


# ------------------------------------------------------------ ⑤ 接线（源码）

## 剥掉注释行之后的源码。**必须剥** —— 本轮的说明文字里到处写着
## `_read_release_rifle` / `rifle_fire_on_release` 这些名字，
## 不剥的话"名字出现过"与"代码真的调用它"分不开（假绿）。
static func _code(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	var out := ""
	for line in txt.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#"):
			continue
		out += line + "\n"
	return out


static func _wiring(t: T) -> void:
	var pc := _code(PLAYER_PATH)
	var body := _code(BODY_PATH)
	var prof := _code(PROFILE_PATH)
	var bc := _code(CANNON_PATH)

	t.ok(pc != "", "读到了 player_controller.gd")
	t.ok(body != "", "读到了 flight_body.gd")

	# ---- 分派：老路必须还在（绝大多数机体仍走它）----
	t.ok(pc.contains("profile.rifle_fire_on_release"),
		"左键按机体表字段分派（不是拿 id 现判）")
	var i_disp := pc.find("profile.rifle_fire_on_release")
	var i_old := pc.find('elif Input.is_action_pressed("fire_primary")')
	t.gt(i_old, i_disp,
		"老路（按住连发）挂在 **elif** 上 —— 新分支没有把它挤掉")

	# ---- 松手发射 + 蓄力 ----
	t.ok(pc.contains('is_action_just_released("fire_primary")'),
		"松手那一帧真的被读了（只写 `is_action_pressed` 的话就退化成“按住连发”）")
	t.ok(pc.contains("func _read_release_rifle"),
		"松手发射有自己的函数（不是塞进老分支里改条件）")
	t.ok(pc.contains("_fire_hold >=") or pc.contains("_fire_hold >="),
		"蓄力靠“按住秒数超过门槛”判定")
	t.ok(pc.contains("profile.cannon_charge_time"),
		"门槛读的是 profile（不是写死 1.7）")
	t.ok(pc.contains("cannon_ready()"),
		"进蓄力之前查 `cannon_ready()` —— 与真正发射用的是**同一个判据**")
	# 位置：进蓄力（cannon_ready）必须在松手放炮（fire_cannon）之前
	var i_ready := pc.find("if cannon_ready():")
	var i_fire := pc.find("if not fire_cannon(target):")
	t.gt(i_fire, i_ready, "先判“能不能蓄”，再判“松手放不放得出去”")

	# ---- 取消路径 ----
	t.ok(pc.contains("_cancel_cannon_charge"),
		"切走武器 / 形态变了能取消蓄力（不然会打出一发玩家没在瞄的炮）")

	# ---- 提示：每一条门禁都有对应的一句话 ----
	t.ok(pc.contains("func cannon_blocked_reason"),
		"蓄不了的时候有**人话**说明原因（静默失败是本工程的头号教训）")
	for key: String in ["大炮冷却", "过热", "弹夹不满", "没有蓄力激光炮"]:
		t.ok(pc.contains(key), "提示覆盖了这一条原因：%s" % key)

	# ---- FlightBody 侧 ----
	t.ok(body.contains("func cannon_ready"), "门禁有**唯一**实现（`cannon_ready`）")
	t.ok(body.contains("rifle_mag >= profile.rifle_magazine"),
		"“弹夹全满”的判据写在门禁里")
	t.ok(body.contains("reload_timer = profile.cannon_overheat_reload"),
		"过热借的是既有换弹通道（HUD 读条 / 弹匣门槛 / 换完满夹全部自动对上）")
	t.ok(body.contains("cannon_cd_left = maxf(cannon_cd_left - delta"),
		"冷却与其它冷却在**同一处**递减")
	t.ok(body.contains("_muzzle_local"),
		"炮口沿用既有的 `_muzzle_local`（不从别处再取一套）")
	t.ok(body.contains("_on_cannon_fired"),
		"镜头抖动走钩子（`FlightBody` 上没有 `camera`，写上去是整个类编译不过）")

	# ---- 柱体 ----
	t.ok(bc.contains("Ballistics.segment_distance"),
		"柱体的命中几何复用 `segment_distance`（与拦截、弹丸打导弹同一套）")
	t.ok(bc.contains("Game.live_hostiles_of"),
		"只打敌对单位（友军过滤走既有真源，不自己比较 team）")
	t.ok(bc.contains("dps * delta"),
		"伤害是**逐帧 `dps × delta`**，不是一次砸满 —— “持续照射”的字面实现")
	t.ok(bc.contains("FX.cannon_muzzle"),
		"炮口挂了飞溅粒子（用户点名“大量粒子飞溅”）")

	# ---- HUD ----
	var hud := _code("res://scripts/ui/hud.gd")
	t.ok(hud.contains("_draw_cannon_charge_ring"), "准星上有蓄力环")
	t.ok(hud.contains("player.cannon_available()"),
		"没有这门炮的机体**整行/整环不画**（不画一行恒为“无”的东西）")

	# ---- 源码里不该出现的东西 ----
	t.not_ok(prof.contains("rifle_steady_speed = 10900") ,
		"10900 只在常量里定义一次（不在赋值处再写一遍字面量）")


# ------------------------------------------------------------ ⑦ 弹体形状

## 用户 2026-10-04："调大光束大炮的弹体（前小后大：发射口和现在一样，末端调大 200%）"。
## 拍板口径 = **末端 ×2**。
##
## ## 这一组的三种坏法**没有一种会报错**
##   ① 根本没做（仍是等粗圆柱）⇒ 倍率还是 1.0、两端半径相等；
##   ② 倍率抄错（1.5 / 2.5）⇒ 只有"比值/半径"那几条红；
##   ③ **粗的那端朝着炮口**（把 `top_radius` / `bottom_radius` 两行互换）⇒ 半径全合法、
##      柱子照画不误，只是炮口成了喇叭口（近粗远细）。
##
## ②③ 必须各有牙齿 ⇒ 下面分四层：**常量**（用户拍的两个数）、**字段**（两端半径与比值）、
## **顶点**（不依赖 `top_radius` 这个字段名，直接量引擎真正的三角化 —— "字段名骗人"的解药）、
## **世界朝向**（粗的那端落在 `dir × length` 上，不是落在炮口上）。
static func _taper(t: T, host: Node) -> void:
	# ---- ① 用户拍的两个数 ----
	t.near(BeamCannon.TIP_SCALE, 2.0, 0.001,
		"用户指定：末端 = 发射口的 **2 倍**（“末端调大 200%”）")
	t.near(BeamCannon.CORE_RADIUS, 3.2, 0.001,
		"发射口内核半径 = 3.2（“发射口和现在一样” ⇒ 这个数一个都没动）")
	t.near(BeamCannon.GLOW_RADIUS, 8.6, 0.001,
		"发射口外晕半径 = 8.6（同上）")
	t.gt(BeamCannon.TIP_SCALE, 1.0,
		"倍率 > 1 ⇒ 真的“前小后大”（= 1.0 就退回等粗圆柱，那正是负对照 nc1 干的）")

	# ---- ② 跑一条真的柱体，量它的网格字段 ----
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _make(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL), 0, true)
	u.global_position = Vector3(0, 3000, 0)
	u.fm.velocity = Vector3.ZERO
	u.fm.align_velocity(u.forward())
	# 钉住瞄准方向（与第六组同法）：不钉的话机头每帧继续下俯，
	# 后面"粗端落在 dir×length 上"那条会读到一帧的角差。
	u.set_aim_direction(Vector3(0.0, 0.0, -1.0))
	u.rifle_mag = u.profile.rifle_magazine
	t.ok(u.fire_cannon(null), "发射一条柱体")
	var n := _first_cannon(c)
	t.ok(n != null, "柱体已生成")
	if n == null:
		c.free()
		return
	var core := n.get("_core") as MeshInstance3D
	var glow := n.get("_glow") as MeshInstance3D
	t.ok(core != null and glow != null, "内核柱 / 外晕柱都在")
	if core == null or glow == null:
		c.free()
		return
	var cm := core.mesh as CylinderMesh
	var gm := glow.mesh as CylinderMesh
	t.ok(cm != null and gm != null,
		"两条柱都用 `CylinderMesh`（只有 `top_radius ≠ bottom_radius` 才做得成圆台）")
	if cm == null or gm == null:
		c.free()
		return

	# ⚠️ 这里写**字面数**（6.4 / 3.2 / 17.2 / 8.6 / 2.0），**不**写 `CORE_RADIUS * TIP_SCALE`：
	#    拿常量去比常量，常量本身错了这条还是会 PASS —— 自指的判据就是假绿。
	t.near(cm.top_radius, 6.4, 0.001, "内核末端半径 = 3.2 × 2 = 6.4 m（字面数）")
	t.near(cm.bottom_radius, 3.2, 0.001, "内核发射口半径仍是 3.2 m")
	t.near(cm.top_radius / cm.bottom_radius, 2.0, 0.001,
		"内核末端 / 发射口 = %.2f —— “200%%”的字面比值" % (cm.top_radius / cm.bottom_radius))
	t.near(gm.top_radius, 17.2, 0.001, "外晕末端半径 = 8.6 × 2 = 17.2 m（字面数）")
	t.near(gm.bottom_radius, 8.6, 0.001, "外晕发射口半径仍是 8.6 m")
	t.near(gm.top_radius / gm.bottom_radius, 2.0, 0.001,
		"外晕末端 / 发射口 = %.2f" % (gm.top_radius / gm.bottom_radius))
	t.near(cm.height, 1.0, 1e-9,
		"网格高度仍是 1.0 —— `_place()` 靠 `scale.y = length` 把它拉长，这个契约没被动")

	# ⚠️ 判定粗细是**另一根轴**：这轮改的是"画出来的形状"，命中范围不许跟着动。
	t.near(n.radius, 12.0, 0.001,
		"判定半径仍是 12.0（`launch()` 依旧不传它）—— 弹体变粗**不**放宽命中")

	# ---- ③ ★ 直接量网格顶点：不吃 `top_radius` 这个字段名的字面意思 ----
	#
	# `top_radius` 只说明"这是 top 那一端"，而 top 落在**局部 +Y 还是 −Y** 是引擎的
	# 实现约定。量顶点就没有约定可骗：y > 0 那圈顶点的半径是几，就是几。
	var arr: Array = cm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var r_plus := 0.0
	var r_minus := 0.0
	var y_hi := -INF
	var y_lo := INF
	for v: Vector3 in verts:
		var rr := Vector2(v.x, v.z).length()
		y_hi = maxf(y_hi, v.y)
		y_lo = minf(y_lo, v.y)
		if v.y > 0.4:
			r_plus = maxf(r_plus, rr)
		elif v.y < -0.4:
			r_minus = maxf(r_minus, rr)
	t.gt(verts.size(), 10, "网格顶点取到了（%d 个）" % verts.size())
	t.near(y_hi, 0.5, 0.001, "顶点 y 的上界 = +0.5（高度 1.0 的一半）")
	t.near(y_lo, -0.5, 0.001, "顶点 y 的下界 = −0.5")
	t.near(r_plus, 6.4, 0.001,
		"★ 局部 **+Y** 那圈顶点的半径 = 6.4 m —— 粗的那端在 y > 0（不靠字段名）")
	t.near(r_minus, 3.2, 0.001, "局部 **−Y** 那圈 = 3.2 m —— 细的那端在 y < 0")

	# ---- ④ 世界朝向：粗的那端必须落在 `dir × length` 上，不是落在炮口上 ----
	#
	# ②③ 全绿也可能是"粗端朝着炮口"。必须把**半径**和**它落在世界哪儿**接起来量。
	#
	# ⚠️ 必须等**展开动画**跑完（`grow = clampf(_life / 0.12, 0, 1)`）再读长度：
	#    实测只等 3 帧时读到 4166.67 = 10000 × 3/7.2 —— 那是"展开到 41.7%"，
	#    **不是柱长**。第六组用的是 12 帧，这里给 14 帧留余量。
	for i in 14:
		await host.get_tree().physics_frame
	var bnorm: Vector3 = core.global_transform.basis.y.normalized()
	var bx: Vector3 = core.global_transform.basis.x.normalized()
	var len_y := core.scale.y
	var tip_pt := core.global_position + bnorm * (len_y * 0.5)
	var base_pt := core.global_position - bnorm * (len_y * 0.5)
	var mz_from: Vector3 = u.global_transform * n.local_offset
	var bdir: Vector3 = u.cannon_aim_dir()
	t.gt(bnorm.dot(bdir), 0.999,
		"柱体局部 +Y 就是 `dir`（dot %.4f）⇒ +Y 那端 = 远处那端" % bnorm.dot(bdir))
	t.near(base_pt.distance_to(mz_from), 0.0, 1.0,
		"**细**的那端（3.2 m）落在炮口 `from` 上（差 %.2f m）" % base_pt.distance_to(mz_from))
	t.near(tip_pt.distance_to(mz_from), len_y, 2.0,
		"**粗**的那端（6.4 m）落在 `dir × length` 上（%.1f vs %.1f m）"
			% [tip_pt.distance_to(mz_from), len_y])
	t.gt(tip_pt.distance_to(mz_from), base_pt.distance_to(mz_from),
		"⇒ 结论：**炮口细、越远越粗**（这正是真机图上要按像素量出来的方向）")
	t.lt(cm.bottom_radius, cm.top_radius,
		"而 `bottom_radius` 才是落在炮口那一端的那个字段（`bottom < top`）")
	# 顺手把第六组钉过的两件事再挂一次，免得"改形状"把摆位/长度一起改坏：
	t.near(len_y, BeamCannon.MAX_LEN, 1.0, "改形状没有动长度：仍是 %.0f m" % len_y)
	t.near(bx.dot(bnorm), 0.0, 0.001, "局部 X ⊥ 局部 Y（右手基没被写坏：`x × y = z`）")

	# ---- ⑤ 源码侧：两端各自绑到哪个半径 ----
	var bc := _code(CANNON_PATH)
	t.ok(bc.contains("mesh.top_radius = r * TIP_SCALE"),
		"源码里 `top_radius` 明确乘 `TIP_SCALE`（+Y 端 = 末端）")
	var i_bot := bc.find("mesh.bottom_radius")
	t.ok(i_bot > 0, "找到了 `bottom_radius` 的赋值点")
	if i_bot > 0:
		var seg := bc.substr(i_bot, 40).split("\n")[0]
		t.not_ok(seg.contains("TIP_SCALE"),
			"而 `bottom_radius` 那一行**不含** `TIP_SCALE`（炮口端不给倍率）—— 两行互换就红")

	c.free()
	await host.get_tree().physics_frame
