class_name SuiteRound15
extends RefCounted
## 第十五轮（手柄拦截）：把"拦截飞弹"从**鼠标专属**变成**两种设备都能做**。
##
## 分七半测，因为这七半坏起来的样子完全不同：
##
##   1. **键位**（查表 + 查运行时 map）—— 手柄 16 个入口全满，这一轮做的是**三处轮换**
##      （R1 火神炮 / R2 使用当前武器 / L1 拦截）。"只换了一半"是最典型的事故：
##      旧归属没剪掉 → 一个键属于两个动作 → 玩家按一下同时触发两件事。
##   2. **说明书**（查表）—— `HELP_SECTIONS` / `PAD_GLYPH` 必须与新绑定一致。
##      本工程为"说明书印着一个按不出来的键"栽过至少两次（§20.6 的右键、第十五轮的 R2）。
##   3. **状态机**（纯函数 `InterceptAuto`）—— 点按立刻发 / 长按进自动 / 放弃 / 恢复。
##   4. **射速**（`_cadence`）—— 自动拦截的 0.2 s 发射间隔与放弃计数。
##      （第十五轮曾要求"间隔必须快过专用冷却"，批 21 拦截弹 CD=0 后冷却已退役。）
##   5. **选目标**（纯函数 `Interceptor.pick_available`）—— 不重复打同一枚。
##   6. **设备判据**（`_intercept_pad_mode()`）—— 一个动作两种读法，判据只能有一处。
##   7. **回归门**（`FlightHUD.threat_layer_visible`）—— 威胁层必须与鼠标解耦。
##      它曾经整个长在 `_draw_aim_cursor()` 的 `cursor_seen` 门控之后，
##      于是**手柄玩家一个飞弹框都看不见、也看不见 TTI 和当前选中**。
##
## ⚠️ 为什么单独一个文件而不是塞进 `suite_combat.gd`：第十五轮与第十四/十六轮
## 是**并行的会话**在落地，一个 round 号一个文件能把冲突面压到最小
## （`suite_round14.gd` / `suite_round16.gd` 也是这么来的）。


static func run(t: T, host: Node) -> void:
	t.suite("Round15 / 手柄键位：右手武器 · 左手导弹")
	_bindings(t)
	t.suite("Round15 / 说明书与新键位一致")
	_help(t)
	t.suite("Round15 / L1 双模状态机")
	_state_machine(t)
	t.suite("Round15 / 射速：5 枚/秒与三条大小关系")
	_cadence(t)
	t.suite("Round15 / 专用冷却真的落到了发射器上（机制级）")
	_salvo(t, host)
	t.suite("Round15 / 自动拦截不重复打同一枚")
	_pick(t)
	t.suite("Round15 / 设备判据")
	_device(t)
	t.suite("Round15 / 威胁层与鼠标解耦（回归门）")
	_threat_layer(t)
	t.suite("Round15 / ★63-23 拦截射速回路（salvo 的零冷却判据）")
	_salvo_rate_guard(t)
	t.suite("导弹防御 / 一梭三发全部武装")
	await _salvo_arming(t, host)
	t.suite("导弹防御 / 全弹发射（100 发）")
	await _full_salvo(t, host)
	t.suite("导弹防御 / 机炮与光束打掉来袭弹")
	await _gun_vs_missile(t, host)
	t.suite("导弹防御 / 干扰弹 = 确定性清屏")
	await _flare_clear(t, host)
	# ⚠️ 这一段与第十五轮的手柄无关，是 **小队战的 ACE 规则**（老板 2026-09-21 要求）。
	# 落在这个文件里是因为它改的 `BanditAI._pick_target()` 是**我这一轮动过的函数**
	#（旁边那个会话在改 `suite_round17..21`，不往他们的文件里塞东西）。
	t.suite("小队战 / ACE 优先咬对面的 ACE")
	await _ace_priority(t, host)
	t.suite("小队战 / 系统补的 ACE 只能是同阵营的")
	_ace_faction(t)
	t.suite("古斯塔夫 / 腕部榴弹炮（备弹 5 · 伤害 70）")
	await _grenade(t, host)
	t.suite("僚机 / 不集火：优先挑没人咬的目标")
	await _no_focus_fire(t, host)


# ---------------------------------------------------------------- 1 键位

static func _bindings(t: T) -> void:
	# 三处轮换
	t.ok(_pad_has("fire_gun", JOY_BUTTON_RIGHT_SHOULDER), "手柄表：R1 = 火神炮（按住连发）")
	t.ok(_axis_pair("fire_primary", JOY_AXIS_TRIGGER_RIGHT, 1.0), "手柄轴表：R2 = 使用当前武器")
	t.ok(_pad_has("fire_secondary", JOY_BUTTON_LEFT_SHOULDER), "手柄表：L1 = 拦截来袭飞弹")
	t.ok(_axis_pair("fire_missile", JOY_AXIS_TRIGGER_LEFT, 1.0), "手柄轴表：L2 = 浮游导弹（没动）")

	# 旧归属必须**剪掉**（两张表是互补的：一个动作只能出现在一张里）
	t.not_ok(InputSetup.PAD_BINDINGS.has("fire_primary"),
		"`fire_primary` 已不在**按键**表里（不许同时出现在两张表）")
	t.not_ok(_axis_pair("fire_secondary", JOY_AXIS_TRIGGER_RIGHT, 1.0),
		"R2 轴上**不再**属于拦截")
	t.not_ok(_pad_has("fire_gun", JOY_BUTTON_LEFT_SHOULDER), "L1 不再属于火神炮")

	# 运行时 map 也得真的跟上（`InputSetup.ensure_all()` 会剪多余绑定）
	t.ok(_map_pad("fire_gun", JOY_BUTTON_RIGHT_SHOULDER), "运行时 map：R1 真的挂在火神炮上")
	t.ok(_map_pad("fire_secondary", JOY_BUTTON_LEFT_SHOULDER), "运行时 map：L1 真的挂在拦截上")
	t.ok(_map_axis("fire_primary", JOY_AXIS_TRIGGER_RIGHT), "运行时 map：R2 真的挂在当前武器上")
	t.not_ok(_map_axis("fire_secondary", JOY_AXIS_TRIGGER_RIGHT), "运行时 map：R2 上没有拦截了")
	t.not_ok(_map_pad("fire_primary", JOY_BUTTON_RIGHT_SHOULDER), "运行时 map：R1 上没有当前武器了")
	# 一共 15 个按键入口 + 2 条扳机轴，一个都不许变成孤儿
	for a: String in ["fire_gun", "fire_secondary", "shield", "reload", "boost", "hover",
			"transform", "switch_target", "flares", "missile_mode", "switch_weapon",
			"look_back", "confirm", "menu_back", "pause"]:
		t.ok(InputSetup.PAD_BINDINGS.has(a), "手柄入口 %s 还在" % a)


# ---------------------------------------------------------------- 2 说明书

static func _help(t: T) -> void:
	var weapons: Array = []
	for sec: Dictionary in InputSetup.HELP_SECTIONS:
		if str(sec["title"]) == "武器":
			weapons = sec["items"]
	t.gt(weapons.size(), 0, "帮助表里有'武器'分组")
	var pad_of := {}
	for it: Array in weapons:
		pad_of[InputSetup.help_text(it)] = str(it[2]) if it.size() > 2 else ""
	t.eq(str(pad_of.get("鼠标左键", "")), "R2", "说明书：使用当前武器 → R2")
	t.eq(str(pad_of.get("空格", "")), "R1", "说明书：火神炮 → R1")
	t.eq(str(pad_of.get("鼠标右键", "")), "L1", "说明书：拦截来袭飞弹 → L1")
	t.eq(str(pad_of.get("F", "")), "L2", "说明书：浮游导弹 → L2")
	t.ok(pad_of.has("L1 按住"),
		"说明书：'按住 = 自动拦截'单独一行（第一列只有 112 px，长句会叠到描述上）")
	# HUD 右下角那一列（`FlightHUD._key()` 读它）
	t.eq(str(FlightHUD.PAD_GLYPH.get("fire_secondary", "")), "L1", "HUD 装备行：拦截显示 L1")
	t.eq(str(FlightHUD.PAD_GLYPH.get("fire_gun", "")), "R1", "HUD 装备行：火神炮显示 R1")
	t.eq(str(FlightHUD.PAD_GLYPH.get("fire_primary", "")), "R2", "HUD 装备行：当前武器显示 R2")
	t.eq(str(FlightHUD.PAD_GLYPH.get("flares", "")), "十字键 ↓",
		"HUD 装备行：干扰弹 = 十字键 ↓（修掉了过时的 L3 —— 照抄那行会按到变形）")


# ---------------------------------------------------------------- 3 状态机

static func _state_machine(t: T) -> void:
	var dt := 0.02
	var a := InterceptAuto.new()
	t.eq(a.update(dt, true, true), 1, "按下 L1 **立刻**出手一发（不等松手）")

	var acc := dt
	while acc < 0.4:
		a.update(dt, true, true)
		acc += dt
	t.not_ok(a.active, "0.4 秒时还没进自动模式（阈值 0.45）")

	var shots := 1
	while acc < 0.56:
		shots += a.update(dt, true, true)
		acc += dt
	t.ok(a.active, "按住 0.45 秒之后进入自动模式")
	t.eq(shots, 2, "到 0.5 秒只多出一发（自动模式 0.45 才开，下一发在 0.87）")

	t.eq(a.update(dt, false, true), 0, "松手不再出手")
	t.not_ok(a.active, "松手立即退出自动模式")

	# 自动模式的节奏：进模式那一下立刻出一发，之后每 SHOT_INTERVAL 一发
	var d := InterceptAuto.new()
	var step := 0.01
	var now := 0.0
	var first_auto := -1.0
	var auto_shots := 0
	d.update(step, true, true)          # 按下沿那一发
	while now < 1.01:
		var got := d.update(step, true, true)
		now += step
		if got > 0:
			auto_shots += 1
			if first_auto < 0.0:
				first_auto = now
	t.near(first_auto, InterceptAuto.HOLD_ENTER, 0.03,
		"进自动模式的那一刻就出第一发（不白等一个间隔）")
	t.eq(auto_shots, 2, "0.45→1.0 秒之间共 2 发（0.45 / 0.87 = 与浮游飞弹同间隔 0.42 s）")

	# 发不出去 → 放弃，而且**这一次按住**只放弃一次
	var b := InterceptAuto.new()
	var acc2 := 0.0
	while acc2 < 1.2:
		b.update(dt, true, false)
		acc2 += dt
	t.ok(b.exhausted, "连续两发发不出去 → 放弃（调用方要据此提示玩家）")
	t.not_ok(b.active, "放弃之后退回非自动模式")
	b.clear_exhausted()
	t.eq(b.update(dt, true, true), 0, "放弃之后**按住不放**也不再试（否则提示会反复弹）")
	b.update(dt, false, true)
	t.eq(b.update(dt, true, true), 1, "松手再按 → 恢复（还是按下沿那一发）")

	# 进度条（HUD 画"按住 L1 = 自动拦截"用）
	var c := InterceptAuto.new()
	t.near(c.progress(), 0.0, 0.001, "没按的时候进度是 0")
	c.update(0.3, true, true)
	t.near(c.progress(), 0.3 / InterceptAuto.HOLD_ENTER, 0.01, "进度 = 按住时长 ÷ 阈值")
	c.reset()
	t.near(c.progress(), 0.0, 0.001, "reset() 之后进度归零")


# ---------------------------------------------------------------- 4 射速

## 这一组守的是**发射节奏**的不变量：状态机的发射间隔与放弃计数。
## （批 21 起拦截弹 CD = 0、第十五轮的"专用冷却"退役 —— 冷却不再是节奏的一环，
## 需要防的故障从"一半的发射凭空消失"变成了"连发被换弹 / 变形闸拦住"。）
static func _cadence(t: T) -> void:
	t.near(InterceptAuto.SHOT_INTERVAL, 0.42, 0.0001, "自动拦截每 0.42 秒一次扳机")
	t.near(InterceptAuto.SHOT_INTERVAL, float(SuitProfile.xi().funnel_interval), 0.001,
		"自动拦截节奏与浮游飞弹的发射间隔**一致**（批 26 用户指定：不许比浮游飞弹快）")
	t.near(InterceptAuto.shots_per_second(), 1.0 / 0.42, 0.01,
		"自动拦截 ≈ 每秒 2.4 发（批 26 从 5 枚/秒撤回：实机观感\"一秒射很多\"）")
	t.eq(InterceptAuto.GIVE_UP_SHOTS, 2, "连续两发发不出去才放弃")
	# 接线扫描（批 26）：玩家路径的分岔不许再退化成"全部传 0"（长按连发事故的回归门）。
	#
	# ⚠️ ★63-23（2026-10-08 用户实测报「按住拦截时会突然发射特别多的导弹」）**换过判据**：
	#    原来钉的是 `0.0 if _intercept_auto.active else -1.0` —— 那是"**自动模式开着**"。
	#    实测证明它把 `fire_missile` 那一支的**手动按住**也变成零冷却
	#    ⇒ `fire_funnel()` 里 `funnel_cooldown = 0.0` ⇒ 每帧一梭（按住 L1 时 1 秒 60 扳机 / 180 发）。
	#    现在判据 = `_intercept_auto_shot`（"**这一帧这一发来自自动整拍**"）：
	#    **语义不变、范围收紧**，批 26 要的那条分岔照样成立。
	#    （取证与完整回归闸见本文件末尾 `_salvo_rate_guard()` 与 `tests/_probe_overfire.tscn`。）
	var pc_src := SuiteUiStyle._code("scripts/flight/player_controller.gd")
	t.ok(pc_src.contains("0.0 if _intercept_auto_shot else -1.0"),
		"玩家拦截弹：**自动整拍那一发**传 0（节奏归状态机）、其余一律走通用冷却（-1）")
	t.not_ok(pc_src.contains("_intercept_auto.active else -1.0"),
		"★ 判据不许回到 `_intercept_auto.active`（\"模式开着\" ≠ \"这一发来自整拍\"）—— 那是每帧一梭")
	t.not_ok(pc_src.contains("var salvo := 0.0\n"),
		"不许出现\"所有拦截弹一律 CD=0\"的旧写法（批 21 事故）")


# ---------------------------------------------------------------- 5 选目标

static func _pick(t: T) -> void:
	var a := Node3D.new()
	var b := Node3D.new()
	var c := Node3D.new()
	var ranked: Array = [
		{"missile": a, "tti": 1.0, "dist": 100.0},
		{"missile": b, "tti": 2.0, "dist": 200.0},
		{"missile": c, "tti": 3.0, "dist": 300.0},
	]
	t.eq(Interceptor.pick_available(ranked, []), a, "没有已咬住的目标 → 挑最危险的那一枚")
	t.eq(Interceptor.pick_available(ranked, [a]), b, "最危险的已被咬住 → 跳到下一枚")
	t.eq(Interceptor.pick_available(ranked, [a, b]), c, "前两枚都被咬住 → 挑第三枚")
	t.eq(Interceptor.pick_available(ranked, [a, b, c]), null, "全被咬住 → 没有了")
	t.eq(Interceptor.pick_available([], []), null, "空表 → null（点按那一下要能安全地什么都不做）")

	# 已释放的实例要跳过：飞弹随时会在半空自爆，而缓存是上一帧建的
	var d := Node3D.new()
	var ranked2: Array = [{"missile": d, "tti": 0.5, "dist": 50.0},
		{"missile": b, "tti": 2.0, "dist": 200.0}]
	d.free()
	t.eq(Interceptor.pick_available(ranked2, []), b, "已释放的那一枚被跳过，且不崩")

	a.free()
	b.free()
	c.free()


# ---------------------------------------------------------------- 6 设备判据

static func _device(t: T) -> void:
	var pc := PlayerController.new()
	var old := InputSetup.using_gamepad

	InputSetup.using_gamepad = true
	pc.cursor_seen = true
	t.ok(pc._intercept_pad_mode(), "最近一次输入来自手柄 → 手柄路径（哪怕光标见过）")

	InputSetup.using_gamepad = false
	pc.cursor_seen = false
	t.ok(pc._intercept_pad_mode(), "从未见过鼠标 → 手柄路径（手柄玩家 cursor_seen 恒为 false）")

	pc.cursor_seen = true
	t.not_ok(pc._intercept_pad_mode(), "键鼠玩家（见过光标 + 非手柄模式）→ 鼠标路径")

	InputSetup.using_gamepad = old
	pc.free()


# ---------------------------------------------------------------- 7 威胁层回归门

## 这一组的**唯一目的**：钉死"给手柄看的信息不许长在鼠标分支里"。
##
## 它修的是一个真 bug：飞弹框 / TTI / "当前选中"整段都画在 `_draw_aim_cursor()` 里，
## 而那个函数第一行是 `if ... or not player.cursor_seen: return`。
## 手柄不产生鼠标移动事件 ⇒ `cursor_seen` 恒为 false ⇒ **手柄玩家看不见任何飞弹信息**。
## 而屏幕不是空的（`MISSILE ALERT` 在闪、敌机锁定框也在），所以这个 bug
## **靠看截图发现不了** —— 必须让判定成为一个可断言的纯函数。
static func _threat_layer(t: T) -> void:
	var pc := PlayerController.new()
	t.not_ok(FlightHUD.threat_layer_visible(null), "没有玩家 → 不画（也不崩）")
	t.not_ok(FlightHUD.threat_layer_visible(pc), "既没有威胁、也没有选中 → 不画")

	pc.cursor_seen = false                       # ← 手柄玩家的常态
	var dummy := Node3D.new()
	pc.set("_threats_cache", [{"missile": dummy, "tti": 1.5, "dist": 150.0}])
	t.ok(FlightHUD.threat_layer_visible(pc),
		"手柄玩家（cursor_seen = false）**照样有**威胁层 —— 第 2.3 节那个 bug 的回归门")

	pc.cursor_seen = true
	t.ok(FlightHUD.threat_layer_visible(pc), "键鼠玩家当然也有（这一轮不许把它改坏）")

	pc.set("_threats_cache", [])
	t.not_ok(FlightHUD.threat_layer_visible(pc), "威胁全没了、也没选中 → 收起来")

	dummy.free()
	pc.free()


# ---------------------------------------------------------------- 8 拦截弹 CD=0（机制级）

## **机制级**断言：不光测语义，还要证明 `fire_funnel(target, salvo_cooldown)` 真的把冷却
## 压成了传进来的那个值。
##
## 为什么非要有这一组：只看代码的话，"参数没被用上 / 哨兵语义改错"这种错会一路溜到实机。
## 批 26（2026-09-22 用户指定）定稿：**自动拦截路径传 0 → 冷却恰好 0**（节奏由状态机
## `SHOT_INTERVAL` 管）；**不传参 → 通用 0.42**（键鼠 F / 右键与 AI 走这条，
## 与浮游飞弹同闸 —— 批 21 的"全部传 0"因长按连发被撤回）。机体的搭法与 `suite_abilities._unit()` 一致。
static func _salvo(t: T, host: Node) -> void:
	var c := Node3D.new()
	host.add_child(c)
	var u := FlightBody.new()
	u.team = 1
	u.profile = SuitProfile.xi()
	u.projectile_container = c
	c.add_child(u)
	u.global_position = Vector3(0, 3000, 0)
	u.fm.speed = 260.0
	u.fm.throttle = 0.78
	u.fm.align_velocity(u.forward())
	var foe := Node3D.new()
	c.add_child(foe)
	foe.global_position = Vector3(0, 3000, -500)

	# ① 自动拦截那一发（传 0，节奏由状态机 SHOT_INTERVAL 管）：冷却恰好为 0
	t.ok(u.fire_funnel(foe, 0.0), "自动拦截那一发能打出去")
	t.near(u.funnel_cooldown, 0.0, 0.0001,
		"传 0 → **零冷却**（自动拦截的节奏由状态机管，不吃冷却/扳机的浮点赛跑）")

	# ② 不传参（键鼠 F / 右键 / AI 走的就是这条）：通用冷却 = 浮游飞弹同闸
	t.ok(u.fire_funnel(foe), "不传参时照旧能打（键鼠 F / 右键 / AI 走的就是这条）")
	t.near(u.funnel_cooldown, float(SuitProfile.xi().funnel_interval), 0.001,
		"不传参 → 通用发射器冷却 0.42 s：拦截弹与浮游飞弹**同一条闸**（批 26 定稿）")

	u.free()
	foe.free()
	c.free()


# ---------------------------------------------------------------- 9 拦截吞吐（第十八轮）

## 造一个"玩家 + 一梭三发 + 若干来袭弹"的场地。
static func _arena(host: Node) -> Dictionary:
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.team = 1
	pc.is_player = true
	pc.profile = SuitProfile.xi()
	pc.projectile_container = c
	c.add_child(pc)
	pc.global_position = Vector3(0, 3000, 0)
	pc.fm.speed = 260.0
	pc.fm.throttle = 0.78
	pc.fm.align_velocity(pc.forward())
	# 只测这些方法：停掉物理帧（`_think()` 要 camera / lock，这里没有）
	pc.set_physics_process(false)
	var foe := Node3D.new()
	c.add_child(foe)
	foe.global_position = Vector3(0, 3000, -3000)
	return {"c": c, "pc": pc, "foe": foe}


## 一枚"冲着我来"的来袭弹，摆在世界坐标 `at`。
static func _threat(c: Node3D, pc: Node3D, foe: Node3D, at: Vector3) -> Missile:
	var th := Missile.new()
	th.shooter = foe
	th.target = pc
	th.speed = 800.0
	c.add_child(th)
	th.global_position = at
	return th


## **"拦不完"的根**：老实现一次扳机只武装**最后一发**，而来袭弹是按梭（3 发/0.42 s）来的。
## 这一组钉住"一梭三发全武装 + 一发对一枚 + 显式选择优先"。
static func _salvo_arming(t: T, host: Node) -> void:
	var a := _arena(host)
	var c: Node3D = a["c"]
	var pc: PlayerController = a["pc"]
	var foe: Node3D = a["foe"]

	var threats: Array = []
	for i in 3:
		threats.append(_threat(c, pc, foe, Vector3(-500.0 + 500.0 * float(i), 3000.0, -1500.0)))
	# ⚠️ **必须填威胁缓存**：`_salvo_threats()` 的目标表来自 `_threats_cache`
	# （生产路径由 `_refresh_threats()` 每帧填，见 `_think`）。
	# 不填的话它只认得到"玩家显式选的那一枚"，于是三发全咬同一枚 —— 这一条我第一版就写漏了。
	var cache: Array = []
	for i in 3:
		cache.append({"missile": threats[i], "tti": 1.0 + float(i), "dist": 1500.0})
	pc.set("_threats_cache", cache)

	# 一梭三发（扇开），并**手动写下快照** —— 生产路径里这一行紧挨着 `fire_funnel()`
	var salvo: Array = []
	var from := c.get_child_count()
	for i in 3:
		salvo.append(Missile.funnel(c, pc.global_position, Vector3(0, 0, -1), foe, pc, 3.0))
	pc.set("_salvo_from", from)
	pc.set("_intercept_pending", threats[0])
	pc.set("_intercept_requested", true)
	pc.call("_mark_intercept_missile")

	var armed := 0
	for m in salvo:
		if (m as Missile).intercept_capable:
			armed += 1
	t.eq(armed, 3, "一梭三发**全部**被武装成可对撞（第十八轮：老实现只有 1 发）")
	t.not_ok(pc.get("_intercept_requested"), "标记完请求就被清掉（不会一直粘着）")
	var hit_primary := false
	for m in salvo:
		if (m as Missile).intercept_target == threats[0]:
			hit_primary = true
	t.ok(hit_primary, "玩家**显式选中**的那一枚一定有弹去咬（显式选择优先）")
	var used := {}
	for m in salvo:
		var tg = (m as Missile).intercept_target
		if tg != null:
			used[tg] = int(used.get(tg, 0)) + 1
	t.eq(used.size(), 3, "目标够 3 枚时，一发对一枚（不重复咬同一枚）")

	# 目标数为 1 时：三发一起去咬它（而不是空放）
	var only: Array = [threats[0]]
	var pairs := Interceptor.assign_targets(salvo, only)
	t.eq(pairs.size(), 3, "只有一枚来袭弹时，三发都派给它（不空放）")
	# 空目标：分配为空（调用方退化成"只标记可对撞"，见 `_mark_intercept_missile`）
	t.eq(Interceptor.assign_targets(salvo, []).size(), 0, "没有目标时分配为空（不崩）")

	Game.reset()
	c.free()
	await host.get_tree().process_frame


## 全弹发射：扣 100 发、起冷却、分批涌出、每发都可对撞。
static func _full_salvo(t: T, host: Node) -> void:
	var a := _arena(host)
	var c: Node3D = a["c"]
	var pc: PlayerController = a["pc"]
	var foe: Node3D = a["foe"]
	pc.funnel_count = 200

	t.eq(PlayerController.FULL_SALVO_COUNT, 100, "一次「全弹发射」是 100 发（老板指定）")
	t.eq(PlayerController.FULL_SALVO_COOLDOWN, 30.0, "冷却 30 s（批 14 用户指定，原 60 s）")
	# ⚠️ 老板原话："全弹发射有内置 20s 的 cd，**切换模式不影响 cd 运转**" ——
	# 这条是那半句话的回归门：冷却在**拦截模式**下也必须照常递减。
	t.eq(int(pc.missile_mode), int(PlayerController.MissileMode.INTERCEPT), "默认是拦截模式")
	t.eq(pc.missile_mode_name(), "拦截", "默认模式名是「拦截」")
	pc.missile_mode = PlayerController.MissileMode.FULL_SALVO
	t.eq(pc.missile_mode_name(), "全弹发射", "切到全弹发射模式后名字跟着变（HUD 常驻显示它）")
	t.ok(pc.missile_mode_hint().contains("全弹发射"), "该模式的提示说清了右键 / L1 干什么")
	t.ok(pc.full_salvo_ready(), "弹药充足 + 无冷却 → 就绪")
	var before := pc.funnel_count
	t.ok(pc.fire_full_salvo(foe), "全弹发射放得出去")
	t.eq(pc.funnel_count, before - 100, "扣掉 100 发")
	t.gt(pc.full_salvo_cooldown, 0.0, "进入冷却")
	t.not_ok(pc.full_salvo_ready(), "冷却期间不再就绪（HUD 靠它画状态）")
	t.not_ok(pc.fire_full_salvo(foe), "冷却期间再按无效（不会白扣弹药）")
	var cd_before := pc.full_salvo_cooldown
	pc.missile_mode = PlayerController.MissileMode.INTERCEPT
	pc.call("_tick_full_salvo", 1.0)
	t.lt(pc.full_salvo_cooldown, cd_before, "**切回拦截模式冷却照样递减**（老板：换模式不影响 cd）")
	pc.missile_mode = PlayerController.MissileMode.FULL_SALVO

	# 分批涌出：每帧 5 发 → 100 发约 20 批
	var guard := 0
	while pc.get("_full_salvo_left") > 0 and guard < 400:
		pc.call("_tick_full_salvo", 0.05)
		guard += 1
	t.eq(int(pc.get("_full_salvo_left")), 0, "分批放完（100 发 / 每帧 5 发）")
	var mine := 0
	var armed := 0
	for ch in c.get_children():
		var m := ch as Missile
		if m != null and m.shooter == pc:
			mine += 1
			if m.intercept_capable:
				armed += 1
	t.eq(mine, 100, "容器里真的多了 100 发（分批而不是一帧全出）")
	t.eq(armed, 100, "这一波**同时**是一堵拦截墙（全部可对撞）")
	t.lt(float(guard), 60.0, "放完用的批数不至于失控（%d 批）" % guard)

	# 弹药不足 → 明确拒绝，且**扣不动弹药**
	pc.funnel_count = 40
	t.not_ok(pc.full_salvo_ready(), "不足 100 发时不就绪")
	var left := pc.funnel_count
	t.not_ok(pc.fire_full_salvo(foe), "不足时按了不放")
	t.eq(pc.funnel_count, left, "不放就不扣弹药")

	Game.reset()
	c.free()
	await host.get_tree().process_frame


## 机炮 / 光束打掉来袭弹（用户第十八轮要求）。
static func _gun_vs_missile(t: T, host: Node) -> void:
	var a := _arena(host)
	var c: Node3D = a["c"]
	var pc: PlayerController = a["pc"]
	var foe: Node3D = a["foe"]

	# 敌方弹：摆在"我正前方 800 m"的弹道上
	var enemy_m := _threat(c, pc, foe, Vector3(0, 3000, -800))
	enemy_m._prev_pos = Vector3(0, 3000, -830)
	var p := Projectile.vulcan(c, Vector3(0, 3000, 0), Vector3(0, 0, -1), pc)
	p.set_physics_process(false)      # 只借它的判定函数，不让它真的飞出去打中别的
	t.eq(p._missile_in_path(Vector3(0, 3000, 0), Vector3(0, 3000, -1100)), enemy_m,
		"弹道上的**敌方**来袭弹会被认出来（机炮/光束因此能打掉它）")
	# 自家弹：同一条弹道上也不该被打
	var own := Missile.funnel(c, Vector3(0, 3000, -700), Vector3(0, 0, -1), foe, pc, 3.0)
	own._prev_pos = Vector3(0, 3000, -730)
	own.global_position = Vector3(0, 3000, -700)
	enemy_m.global_position = Vector3(0, 3000, -4000)     # 把敌方的挪开
	var got = p._missile_in_path(Vector3(0, 3000, -650), Vector3(0, 3000, -760))
	t.not_ok(got == own, "**不打自己的导弹**（一梭三发是扇开的，正前方经常有自家的弹）")
	# `shot_down()`：打爆要有动静，但**不结算伤害**（否则"打掉一颗弹反而扣了血"）
	var hp_before := pc.hp
	enemy_m.global_position = Vector3(0, 3000, -100)
	enemy_m.shot_down()
	await host.get_tree().process_frame
	t.not_ok(is_instance_valid(enemy_m), "被打掉的弹消失")
	t.eq(pc.hp, hp_before, "打掉来袭弹**不会**顺带扣血（`hurt = false`）")

	Game.reset()
	c.free()
	await host.get_tree().process_frame


## 干扰弹 = 确定性清屏（用户第十八轮要求；第十一轮的设计终于落地）。
static func _flare_clear(t: T, host: Node) -> void:
	var a := _arena(host)
	var c: Node3D = a["c"]
	var pc: PlayerController = a["pc"]
	var foe: Node3D = a["foe"]

	# 一发冲着 pc 来的弹：位置在干扰弹**前方**（于是干扰源落在它的正后方）
	var m := Missile.funnel(c, Vector3(0, 3000, -1000), Vector3(0, 0, -1), pc, foe, 3.0)
	m.global_position = Vector3(0, 3000, -1000)
	m.look_at_from_position(m.global_position, m.global_position + Vector3(0, 0, -1), Vector3.UP)
	Flare.deploy_burst(c, Vector3(0, 3000, -400), Vector3.ZERO, 2)

	# ① 目标**没有**在撒干扰弹 → 不该被诱骗（老行为保持不变）
	pc.flare_active = 0.0
	m.decoy = null
	m._maybe_break_lock()
	t.eq(m.decoy, null, "目标没撒干扰弹时不被诱骗（不能变成「自动防御」）")

	# ② 目标**正在**撒干扰弹 → **无条件**被诱骗，哪怕干扰源在它的背后
	#    （老代码要求机头 ±36.9° 锥内，这一发必红 —— 而"侧后方来的弹骗不掉"
	#     正是被弹幕糊脸时最没出路的那种情况）
	pc.flare_active = 3.0            # = `FlightBody.FLARE_ACTIVE_TIME`
	m._maybe_break_lock()
	t.ok(m.decoy != null, "目标撒干扰弹期间，**背后方向**来的弹也被无条件诱骗（第十八轮）")

	Game.reset()
	c.free()
	await host.get_tree().process_frame


# ---------------------------------------------------------------- ACE 优先

## **小队战：ACE 机优先咬对面的 ACE**（老板 2026-09-21 要求）。
##
## 判据是 `SuitProfile.is_ace()`（机体自带的属性），**不是"谁在开"** ——
## 于是玩家自己开 ACE 时，对面的 ACE 也会优先来找玩家。
##
## ⚠️ 这一组的关键是**必须放一台"近得多的量产机"**：只测"ACE 打 ACE"的话，
## "因为最近所以正好打 ACE"也能全绿 —— 那等于没测"优先"。
static func _ace_priority(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	# 我方：一台 ACE（佩涅罗佩）+ 一台量产僚机（古斯塔夫00）
	var ally_ace := _make_ai(c, "AllyAce", 0, SuitProfile.penelope())
	var ally_wing := _make_ai(c, "AllyWing", 0, SuitProfile.gustav00_armed())
	# 敌方：一台**很近**的量产机（梅萨）+ 一台**很远**的 ACE（柯西）
	var foe_near := _make_ai(c, "FoeNear", 1, SuitProfile.messer_m01())
	var foe_ace := _make_ai(c, "FoeAce", 1, SuitProfile.xi())
	# ⚠️ 摆位必须在"让 AI 思考"**之前**：否则 AI 会在"四台重合"的那一帧先锁一台，
	# 之后滞回一直保持它 —— 量到的是滞回，不是优先级（`suite_round21` 踩过同一个坑）。
	ally_ace.global_position = Vector3(0.0, 3200.0, 0.0)
	ally_wing.global_position = Vector3(200.0, 3200.0, 0.0)
	foe_near.global_position = Vector3(0.0, 3200.0, -400.0)
	foe_ace.global_position = Vector3(0.0, 3200.0, -7000.0)
	ally_ace._target = null
	ally_wing._target = null
	foe_ace._target = null
	await host.get_tree().physics_frame

	# ---- 判据本身：ACE 是机体的属性 ----
	t.ok(ally_ace._is_ace(), "佩涅罗佩算 ACE")
	t.not_ok(ally_wing._is_ace(), "古斯塔夫00 不算 ACE")

	# ---- 核心：ACE 咬 ACE，哪怕对面那台量产机近了 17 倍 ----
	ally_ace._think(1.0 / 60.0)
	t.eq(ally_ace._target, foe_ace, "**ACE 优先咬对面的 ACE**（近的量产机抢不走）")

	# ---- 对照：非 ACE 仍然挑**最近的**（优先级只给 ACE，不是所有 AI）----
	ally_wing._think(1.0 / 60.0)
	t.eq(ally_wing._target, foe_near, "非 ACE 僚机仍然挑最近的敌人")

	# ---- 双方对称：把量产僚机挪到敌方 ACE 跟前，敌方 ACE 还是咬我方 ACE ----
	#（不挪的话"最近的就是我方 ACE"，这条断言根本分不出优先与就近）
	ally_wing.global_position = Vector3(0.0, 3200.0, -6900.0)
	foe_ace._think(1.0 / 60.0)
	t.eq(foe_ace._target, ally_ace, "敌方 ACE 也优先咬我方 ACE（量产机近在眼前也不例外）")
	ally_wing.global_position = Vector3(200.0, 3200.0, 0.0)

	# ---- 对面 ACE 没了 ⇒ 回去打最近的量产机 ----
	foe_ace.alive = false
	ally_ace._think(1.0 / 60.0)
	t.eq(ally_ace._target, foe_near, "对面 ACE 被击坠 ⇒ 回头打最近的量产机")

	# ---- 敌人全灭 ⇒ 不给目标（不能空指针，也绝不能退化成回头打队友）----
	foe_near.alive = false
	ally_ace._think(1.0 / 60.0)
	t.eq(ally_ace._target, null, "敌方全灭 ⇒ 目标为 null")

	# ⚠️ **清理必须和同文件里 `_flare_clear()` 的做法一致**（`Game.reset()` +
	# `c.free()` + 等一帧）：只 `queue_free()` 的话，这一组留下的四台机体会
	# 活到下一帧才消失，而后面 Round17 的挂板测试就在这一帧里挑板 ——
	# 实测过一次：不清场地时 `suite_round17.gd` 的"领机还在板上"会红。
	Game.reset()
	c.free()
	await host.get_tree().process_frame


## 测试用的 AI 机体。与 `suite_round21._make()` 同构 —— 那边是并行会话的文件，
## 不去改它：**复制 12 行小工具比制造一次冲突便宜**。
static func _make_ai(parent: Node3D, node_name: String, team: int, p: SuitProfile) -> BanditAI:
	var fb := BanditAI.new()
	fb.name = node_name
	fb.team = team
	fb.profile = p
	fb.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	fb.projectile_container = parent
	parent.add_child(fb)
	return fb


# ---------------------------------------------------------------- ACE 只补同阵营

## **系统补充的 ACE 只能是同阵营的**（老板 2026-09-21）。
##
## 这一组不测"某一台具体是什么机"，测的是**不变量**：两边 × 各种玩家机体
##（**故意把敌阵营的机体也排进去**）全跑一遍，逐台量"ACE 槽里那台是不是自己人"。
##
## ⚠️ 为什么必须逐台量：**跨阵营不会报任何错**。名单里混进一台敌机，游戏照常跑完、
## 照常结算，只有玩家在战场上能看见"自己人被对面开"。所以这条规矩只能靠不变量守。
static func _ace_faction(t: T) -> void:
	var sides: Array[int] = [BattleFormation.Side.MAFTY, BattleFormation.Side.FEDERATION]
	# 玩家机体的取值：−1（这一边没有玩家）/ 两边池子里的**每一台**（含敌阵营的）
	var all_suits: Array[int] = []
	for s: int in sides:
		all_suits.append_array(BattleFormation.roster_of(s).all_suits())
	var picks: Array[int] = [-1]
	picks.append_array(all_suits)

	for side: int in sides:
		var side_name := "马夫蒂" if side == BattleFormation.Side.MAFTY else "联邦·喀耳刻"
		for pick: int in picks:
			var the_lineup := BattleFormation.lineup(side, pick)
			var aces := 0
			for u: BattleFormation.Unit in the_lineup:
				if not u.is_ace:
					continue
				aces += 1
				# ⚠️ **玩家自己开的那台豁免**：玩家挑了什么机就开什么机（自由对战），
				# 那台不算"系统补的"。除它以外，ACE 槽必须是自己人。
				if u.owner_is_player:
					t.eq(u.suit, pick, "%s（玩家机体 %d）：玩家开的 ACE 就是他选的那台" % [side_name, pick])
					continue
				t.ok(BattleFormation.belongs_to(side, u.suit),
					"%s（玩家机体 %d）：**系统补的 ACE 是同阵营的**（实测 %s）"
					% [side_name, pick, SuitProfile.by_id(u.suit).display_name])
			t.eq(aces, BattleFormation.ACES_PER_SIDE,
				"%s（玩家机体 %d）：ACE 恰好 %d 台" % [side_name, pick, BattleFormation.ACES_PER_SIDE])

	# ---- 兜底路径：阵营池子空了也不许跨阵营 ----
	# **这才是原来真正会出事的地方**：`Roster.ace()` 写死返回柯西（马夫蒂的 ACE），
	# 于是联邦侧只要出现"没有 ACE"的名单，系统就会补出一台敌机。
	for side: int in sides:
		var empty := BattleFormation.Roster.new()
		empty.side = side
		t.ok(BattleFormation.belongs_to(side, empty.ace()),
			"空名单的兜底 ACE 仍是同阵营的（side=%d）" % side)
		t.ok(BattleFormation.belongs_to(side, empty.mp()),
			"空名单的兜底量产机仍是同阵营的（side=%d）" % side)
	var fed := BattleFormation.Roster.new()
	fed.side = BattleFormation.Side.FEDERATION
	t.ok(fed.ace() != SuitProfile.Id.XI,
		"**回归门**：联邦的空名单不再补出柯西（那是马夫蒂的 ACE）")

	# ---- 判据本身（`belongs_to` 是这条铁律的唯一真源）----
	t.ok(BattleFormation.belongs_to(BattleFormation.Side.MAFTY, SuitProfile.Id.XI),
		"判据：柯西属于马夫蒂")
	t.not_ok(BattleFormation.belongs_to(BattleFormation.Side.FEDERATION, SuitProfile.Id.XI),
		"判据：柯西不属于联邦")
	t.ok(BattleFormation.belongs_to(BattleFormation.Side.FEDERATION, SuitProfile.Id.ARIZEUS),
		"判据：阿利宙斯属于联邦·喀耳刻")
	t.not_ok(BattleFormation.belongs_to(BattleFormation.Side.MAFTY, SuitProfile.Id.ARIZEUS),
		"判据：阿利宙斯不属于马夫蒂（2026-09-20 的修正）")


# ---------------------------------------------------------------- 腕部榴弹炮

## **古斯塔夫00 的腕部榴弹炮**（1.2 第二十六轮）。
##
## 老板："给古斯塔夫加入新武器，腕部榴弹炮，**备弹 5 发**，伤害 70。"
##
## 这一组钉四件事：① 只有古斯塔夫有；② 数字就是 5 / 70；③ 它进得了"当前武器"
## 那条循环（**不新增按键** —— 手柄 17 个入口在 1.2 就满了）；④ 打一发少一发，
## 且**不随换弹恢复**（它是挂载弹药，不是弹匣）。
static func _grenade(t: T, host: Node) -> void:
	var g := SuitProfile.gustav00_armed()
	t.ok(g.has_grenade, "古斯塔夫00（武装版）有腕部榴弹炮")
	t.eq(g.grenade_count, 5, "备弹 **5 发**")
	t.near(g.grenade_damage, 70.0, 0.001, "单发伤害 70")
	t.not_ok(SuitProfile.gustav00().has_grenade, "靶机版**没有**榴弹（训练场不该出现它）")
	for p: SuitProfile in [SuitProfile.xi(), SuitProfile.penelope(), SuitProfile.messer_m01()]:
		t.not_ok(p.has_grenade, "%s 没有榴弹（这是古斯塔夫的专属武器）" % p.display_name)

	# ---- 槽位表：步枪永远 0 号，榴弹排在军刀之前 ----
	var slots := g.weapon_slots()
	t.eq(slots[0], "rifle", "0 号永远是步枪（HUD 用「是不是 0 号」判断当前武器）")
	t.ok(slots.has("grenade"), "古斯塔夫的槽位里有榴弹：%s" % str(slots))
	t.ok(slots.has("saber"), "……也有军刀")
	t.eq(SuitProfile.xi().weapon_slots().size(), 2, "柯西还是两件（步枪 / 军刀）")

	# ---- 真机：循环切得到榴弹，打一发少一发 ----
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "GrenadeProbe"
	pc.profile = g
	pc.is_player = true
	pc.team = 0
	pc.projectile_container = c
	c.add_child(pc)
	await host.get_tree().physics_frame
	pc.call("_read_weapon_input", 0.016)          # 触发备弹的懒初始化
	t.eq(int(pc.get("grenade_count")), 5, "开局备弹 5 发（懒初始化也要到位）")

	var n := (pc.profile.weapon_slots() as Array).size()
	var seen: Array[String] = []
	for i in n:
		pc.call("switch_weapon")
		seen.append(str(pc.call("current_slot")))
	t.ok(seen.has("grenade"), "循环切武器能切到榴弹：%s" % str(seen))
	t.ok(seen.has("saber"), "……也能切到军刀")
	t.eq(str(pc.call("current_slot")), "rifle", "转一圈回到步枪（循环闭合，不卡格）")

	# ---- 开火：装填间隔内只出一发 ----
	while str(pc.call("current_slot")) != "grenade":
		pc.call("switch_weapon")
	t.ok(bool(pc.call("fire_grenade", null)), "榴弹能打出去")
	t.eq(int(pc.get("grenade_count")), 4, "打一发少一发（5 → 4）")
	t.not_ok(bool(pc.call("fire_grenade", null)), "装填间隔内打不出第二发")
	pc.set("_grenade_cd", 0.0)
	t.ok(bool(pc.call("fire_grenade", null)), "装填好了就能再打")
	t.eq(int(pc.get("grenade_count")), 3, "……并且再少一发")

	# ---- 打空：切武器**跳过**它（而不是让左键变成没反应的键）----
	pc.set("grenade_count", 0)
	t.not_ok(bool(pc.call("fire_grenade", null)), "打空之后打不出（5 发就是 5 发）")
	t.not_ok(bool(pc.call("slot_available", "grenade")), "打空后榴弹槽不可用")
	pc.set("weapon_index", 0)
	pc.call("switch_weapon")
	t.eq(str(pc.call("current_slot")), "saber", "打空后切武器跳过榴弹，直接到军刀")

	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ---------------------------------------------------------------- 僚机不集火

## **同队不许都咬同一个目标**（1.2 第二十六轮）。
##
## 老板："修改一下僚机 ai 和敌人僚机 ai，**降低集火强度**：在有其他无主目标可以选的情况下，
## 就别选已经有人选过的敌人目标；如果没有其他敌人目标可以选择了，
## 那么**才可以一起集火最近的敌方**。"
##
## 三条断言对应他那句话的三段：① 先到的咬最近的；② 后到的**让开**去打无主的（哪怕更远）；
## ③ 只剩一个目标时**允许集火**（这是老板点名的后路，不是漏网）。
static func _no_focus_fire(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var a1 := _make_ai(c, "WingA", 0, SuitProfile.gustav00_armed())
	var a2 := _make_ai(c, "WingB", 0, SuitProfile.gustav00_armed())
	var near_foe := _make_ai(c, "FoeNear", 1, SuitProfile.messer_m01())
	var far_foe := _make_ai(c, "FoeFar", 1, SuitProfile.messer_m01())
	a1.global_position = Vector3(0.0, 3000.0, 0.0)
	a2.global_position = Vector3(60.0, 3000.0, 0.0)
	near_foe.global_position = Vector3(0.0, 3000.0, -600.0)
	far_foe.global_position = Vector3(0.0, 3000.0, -3000.0)
	a1._target = null
	a2._target = null
	await host.get_tree().physics_frame

	# ① 先到的咬最近的
	a1._think(1.0 / 60.0)
	t.eq(a1._target, near_foe, "僚机 A 咬最近的敌人")
	# ② 后到的**让开** —— 这就是"降低集火强度"
	a2._think(1.0 / 60.0)
	t.eq(a2._target, far_foe, "僚机 B **不抢** A 咬住的目标，去打另一个（哪怕更远）")
	t.eq(a1._target, near_foe, "A 不受影响（先到的留住 —— 否则两台会互相让来让去）")

	# ③ 只剩一个目标：允许一起集火（老板点名的后路）
	far_foe.alive = false
	a2._target = null
	a2._think(1.0 / 60.0)
	t.eq(a2._target, near_foe, "没有别的目标可选了 → **才允许一起集火**最近的")

	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ---------------------------------------------------------------- 查表小工具

static func _pad_has(action: String, btn: int) -> bool:
	return InputSetup.PAD_BINDINGS.get(action, []).has(btn)


static func _axis_pair(action: String, axis: int, sign: float) -> bool:
	for pair: Array in InputSetup.PAD_AXIS_BINDINGS.get(action, []):
		if int(pair[0]) == axis and absf(float(pair[1]) - sign) < 0.01:
			return true
	return false


static func _map_pad(action: String, btn: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev: InputEvent in InputMap.action_get_events(action):
		var jb := ev as InputEventJoypadButton
		if jb != null and jb.button_index == btn:
			return true
	return false


static func _map_axis(action: String, axis: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev: InputEvent in InputMap.action_get_events(action):
		var jm := ev as InputEventJoypadMotion
		if jm != null and jm.axis == axis:
			return true
	return false


# ============================================================ ★63-23 拦截射速回路（回归闸）

## 「**按住拦截的时候会突然发射特别多的导弹**」的回归闸（★63-23，2026-10-08 用户实测报）。
##
## 根因：`salvo` 的开关写的是 `_intercept_auto.active` —— 那是"**自动模式开着**"，
## 不是"**这一发来自自动整拍**"。自动模式一旦开着（按住 L1 ≥0.45 s 之后就一直开着），
## **任何**走 `fire_missile` 那一支的输入都拿到 0 冷却 ⇒ `fire_funnel()` 里
## `funnel_cooldown = 0.0` ⇒ **下一帧立刻又能发** ⇒ 每帧一梭。
##
## 实测取证（`tests/_probe_overfire.tscn`，直接驱动生产 `_read_weapon_input()`）：
##   A 只按拦截 2.5 s    = 6 扳机（0.42 s 节奏，对）
##   B 拦截 + 浮游 1 s    = **60 扳机**（应 ≈2.4）← 爆
##   D 自动开着 → 鼠标一动（切回键鼠）→ 松手 → **只按浮游** 1 s = **60 扳机** ← 更狠的一路
## 修后：B = 3、D = 3，且 D 的 `active` 由 `true` 变回 `false`。
##
## ⚠️ ①（那条字符串判据）放在上面 `_cadence()` 里 —— 它本来就是批 26 那道"分岔不许退化"的闸，
## 这次只是把判据同步换成 `_intercept_auto_shot`。这里守的是它守不到的两件事。
static func _salvo_rate_guard(t: T) -> void:
	var pc := SuiteUiStyle._code("scripts/flight/player_controller.gd")
	t.ok(pc.length() > 1000, "读到了 player_controller.gd 的源码（已剥整行与行尾注释）")

	# ② 该标志只有"自动整拍"一个写入点，且**同处清掉**（本帧语义，不许跨帧粘）
	t.eq(pc.count("_intercept_auto_shot = true"), 1,
		"`_intercept_auto_shot` 只有一个写入点（`_tick_pad_intercept` 的自动整拍）")
	t.eq(pc.count("_intercept_auto_shot = false"), 1,
		"它也只在一个地方被清（与 `_autofire_intercept` 同处，绝不许跨帧粘着）")

	# ③ 状态机必须能被"这一路不再被驱动"收尾（否则 `active` 卡住 = HUD 假状态）
	t.ok(pc.find("_intercept_auto.update(0.0, false, false)") >= 0,
		"不走手柄拦截分支时状态机收尾 ⇒ `active` 不会卡住在 true")
