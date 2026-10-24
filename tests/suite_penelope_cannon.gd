class_name SuitePenelopeCannon
extends RefCounted
## 佩涅罗佩的**蓄力激光炮** + 「**保住连发**」的输入路由（2026-09-29 用户指定）。
##
## ## 需求原文
## > 把阿利宙斯的光束大炮也给佩涅罗佩
##
## 追问口径时用户拍板：**保住连发** —— 只在「按下那一刻 `cannon_ready()`」的
## 那一次按住里**抑制开火、改为蓄力**；其余按次（弹匣不满 / 冷却中 / 过热中）
## 按住仍然照旧**连发**。
##
## ## 为什么不能「照阿利宙斯原样」（连 `rifle_fire_on_release` 也设 true）
## 她的步枪是 **1 门 / 6 发 / 0.82 s / 每发 7 伤害**的洒水枪 ⇒
## 改成「点一下才打一发」等于把连射废掉。
## 而 `rifle_fire_on_release` 又**必须**与蓄力绑定（否则按下先打一发、
## 按满 1.7 s 时弹匣已不满 ⇒ 大炮**结构上放不出来、而且不报错**）——
## 所以本轮给佩涅罗佩换了一条**只在她身上生效**的路由：`rifle_press_route()`。
##
## ## 分六组，因为它们坏起来的样子完全不同
##
## | 组 | 坏了会怎样 |
## |---|---|
## | 数据层 | 她没有炮；或被人「顺手」设成松手单发（连射没了）；或匀速弹速外溢给她 |
## | 路由判定 | 没炮的机体也拿到炮；或「有大炮」却不看满弹匣 / 冷却 |
## | 锁存 | 按下那一刻定的路由在半途被重判 ⇒ 按着不动、枪自己开始响（或反过来） |
## | 门禁 | 「满弹匣」那条硬门槛被按阿利宙斯的 2 发判，而不是按她自己的 6 发 |
## | 输入层 A/B | 看不出「满弹匣不洒水 / 不满照旧连发」这条分界到底存不存在 |
## | 接线 | 代码全对但**没有人读它** —— 症状与「需求没做」**一模一样** |
##
## ⚠️ 最后一组是本工程栽得最多的地方（「方法都写好了、却没有读取点」），
## 所以那里扫的是**源码位置关系**，不只看「函数存不存在」。
##
## ## 本套件**不做**的两件事（各有更合适的取证手段）
##   1. **真实输入端到端**（按下 → 蓄力 → 松手 → 柱子出现）：无头下
##      `just_pressed` / `just_released` 的帧戳不可靠（`tutorial_director.gd:47`），
##      那条链走的是**非无头探针**（`tools/penelope_cannon_shot.gd`）。
##   2. 大炮的**通用**门禁（冷却 20 / 过热 15 / 柱体 4 s × 35 dps）——
##      那套已经在 `suite_arizeus_cannon.gd` 逐条钉过；本套件只补她**独有**的那条：
##      「满弹匣」按**她自己的容量**判。

const PLAYER_PATH := "res://scripts/flight/player_controller.gd"
const PROFILE_PATH := "res://scripts/data/suit_profile.gd"

## 模拟「按住」的物理帧数。120 帧 = 2.0 s > 蓄力门槛 1.7 s。
const HOLD_FRAMES := 120
const DT := 1.0 / 60.0


static func run(t: T, host: Node) -> void:
	t.suite("PenelopeCannon / 数据层（有炮 · 不走松手单发 · 数值与阿利宙斯同源）")
	_data(t)
	t.suite("PenelopeCannon / 路由判定（谁有炮 · 有炮的看什么）")
	_route(t, host)
	t.suite("PenelopeCannon / 锁存（按下那一刻定、整个按次不再重判）")
	_latch(t, host)
	t.suite("PenelopeCannon / 门禁（「满弹匣」按她自己的容量判）")
	await _gates(t, host)
	t.suite("PenelopeCannon / 输入层 A/B（满弹匣不洒水 · 不满照旧连发）")
	await _behavior(t, host)
	t.suite("PenelopeCannon / 接线（源码位置关系）")
	_wiring(t)


# ------------------------------------------------------------ ① 数据层

static func _data(t: T) -> void:
	var p := SuitProfile.penelope()
	var a := SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)

	t.ok(p.cannon_enabled,
		"佩涅罗佩有蓄力激光炮（用户：「把阿利宙斯的光束大炮也给佩涅罗佩」）")
	# ★ 本套件最要紧的一条：她**不是**「照阿利宙斯原样」。
	t.not_ok(p.rifle_fire_on_release,
		"★ 她的 `rifle_fire_on_release` 仍是 **false** —— 用户拍板「保住连发」；"
		+ "改成松手单发会把 1 门 / 6 发 / 0.82 s 的连射废掉")
	t.near(p.rifle_steady_speed, 0.0, 0.001,
		"匀速弹速（10900 m/s）是阿利宙斯专属，**不外溢**给她（那是另一件事）")

	# 数值同源：用户说的是「也**给**」，不是「给一门不一样的」。
	var names := ["蓄力门槛", "柱每秒伤害", "柱持续时间", "大炮冷却", "过热换弹"]
	var pv := [p.cannon_charge_time, p.cannon_dps, p.cannon_duration,
		p.cannon_cooldown, p.cannon_overheat_reload]
	var av := [a.cannon_charge_time, a.cannon_dps, a.cannon_duration,
		a.cannon_cooldown, a.cannon_overheat_reload]
	for i in names.size():
		t.near(pv[i], av[i], 1e-9, "%s 与阿利宙斯**同源**（%.2f）" % [names[i], pv[i]])

	# 前提：她的弹匣不止一发 ⇒ 下面「满弹匣按自己的容量判」那条才有区分度。
	t.gt(float(p.rifle_magazine), 2.0,
		"她的弹匣 %d 发（> 阿利宙斯的 2 发 ⇒ 「满弹夹」必须读字段，不能照抄常量）"
			% p.rifle_magazine)
	t.gt(p.rifle_interval, 0.0, "她的步枪有射速 %.2f s（连发才有意义）" % p.rifle_interval)


# ------------------------------------------------------------ ② 路由判定

## 造一台**可单测路由**的玩家机。
##
## ★ `controls_enabled` 保持默认 **false** ⇒ `_think()` 在第一行就 return，
##   60 Hz 的框架循环**不会**碰 `_read_weapon_input()` 与路由锁存值。
##   本套件要的是「某个**确定的**按次走哪条路」，所以由测试自己手动调
##   `_read_weapon_input()`（**生产入口**）—— 不是绕过它。
static func _make(host: Node, suit: SuitProfile, tag: String) -> PlayerController:
	var holder := Node3D.new()
	holder.name = "PenCannon_" + tag
	host.add_child(holder)
	var box := Node3D.new()
	box.name = "PenCannonBox_" + tag
	holder.add_child(box)
	var pc := PlayerController.new()
	pc.name = "PenCannonPC_" + tag
	pc.profile = suit
	pc.team = 0
	pc.projectile_container = box
	holder.add_child(pc)
	# 抬离海面：`CRASH_ALTITUDE` 会在贴海时 destroy()，此后每次读字段都是一条
	# `previously freed` 脚本错误（把「机体没活下来」伪装成「逻辑坏」）。
	pc.global_position = Vector3(0.0, 3000.0, 0.0)
	return pc


static func _drop(pc: PlayerController) -> void:
	if not is_instance_valid(pc):
		return
	var holder := pc.get_parent()
	if holder != null and is_instance_valid(holder):
		holder.queue_free()


static func _count_projectiles(pc: PlayerController) -> int:
	var box := pc.projectile_container
	if box == null:
		return 0
	var n := 0
	for ch in box.get_children():
		if ch is Projectile:
			n += 1
	return n


static func _route(t: T, host: Node) -> void:
	# ---- 没炮的三台：路由恒 false，哪怕弹匣满、冷却好了 ----
	# ⚠️ ★63-14：**阿利宙斯核心形态从这张名单里移除**（用户：「给量产型牛高达增加
	#    光束军刀和光束大炮」）⇒ 它现在走**条件路由**，判据紧跟在佩涅罗佩那一段后面。
	var others: Array[SuitProfile] = [SuitProfile.xi(), SuitProfile.messer_m01(),
		SuitProfile.gustav00()]
	for o: SuitProfile in others:
		var pc := _make(host, o, "none_%d" % o.id)
		t.not_ok(pc.cannon_available(), "%s 没有蓄力激光炮" % o.display_name)
		t.not_ok(pc.rifle_press_route(),
			"★ %s：按下那一刻的路由是**老路**（按住连发）—— 没炮就不该抢左键"
				% o.display_name)
		_drop(pc)

	# ---- 阿利宙斯：恒走「松手发射 / 蓄力」那条（弹匣 2 发 / 间隔 5 s，本来不是连发武器）----
	var forms := [SuitProfile.ArizeusForm.NORMAL, SuitProfile.ArizeusForm.CRUISE]
	var fnames := ["常态", "巡航"]
	for i in forms.size():
		var pc := _make(host, SuitProfile.arizeus(forms[i]), "ar_%d" % i)
		t.ok(pc.rifle_press_route(),
			"阿利宙斯 · %s：**恒**走松手路（他的 `rifle_fire_on_release`）" % fnames[i])
		# 连冷却中也是（那是他自己的手感，与「这一发能不能放」无关）
		pc.cannon_cd_left = 9.0
		t.ok(pc.rifle_press_route(),
			"阿利宙斯 · %s：**冷却中**也仍走那条路（路由不等于「这一发能不能放」）"
				% fnames[i])
		_drop(pc)

	# ---- 佩涅罗佩：条件路由 —— 只看「按下这一刻 `cannon_ready()`」----
	var pen := _make(host, SuitProfile.penelope(), "pen_route")
	t.ok(pen.cannon_available(), "佩涅罗佩有炮")
	t.ok(pen.cannon_ready(), "出场即**就绪**（满弹匣 %d 发 + 无冷却 + 不换弹）"
		% pen.profile.rifle_magazine)
	t.ok(pen.rifle_press_route(), "★ 就绪 ⇒ 这一按次走蓄力路")

	pen.rifle_mag = pen.profile.rifle_magazine - 1
	t.not_ok(pen.rifle_press_route(),
		"★ **弹匣少一发** ⇒ 走老路（按住照旧连发）—— 这就是用户选的「保住连发」")
	pen.rifle_mag = pen.profile.rifle_magazine

	pen.cannon_cd_left = 5.0
	t.not_ok(pen.rifle_press_route(), "★ **冷却中** ⇒ 走老路")
	pen.cannon_cd_left = 0.0

	pen.rifle_reloading = true
	t.not_ok(pen.rifle_press_route(),
		"★ **过热换弹中** ⇒ 走老路（那时连普通步枪都打不出）")
	pen.rifle_reloading = false

	# 三条复位 ⇒ 立刻恢复蓄力路（证明上面各条各由自己的原因触发，不是被别的状态卡住）
	t.ok(pen.rifle_press_route(), "★ 三条复位之后**立刻**恢复蓄力路")
	_drop(pen)

	# ---- ★63-14：**阿利宙斯核心形态 · 量产型ν高达**也走这条条件路由 ----
	#
	# 用户原话：「给量产型牛高达增加光束军刀和光束大炮」。
	# ⚠️ 它**不是**阿利宙斯常态 / 巡航那条"恒走松手路"—— 它的
	#    `rifle_fire_on_release` 仍是 `false`（8 发 / 0.62 s 的连发枪，不能废掉连射）。
	#    所以它与佩涅罗佩**同路**，本段也就照她那四条门槛逐条钉一遍。
	var nu_core := _make(host, SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU), "core_route")
	t.ok(nu_core.cannon_available(), "★ 核心 · 量产型ν高达有大炮了")
	t.ok(nu_core.cannon_ready(), "★ 出场即就绪（满弹匣 %d 发 + 无冷却 + 不换弹）"
		% nu_core.profile.rifle_magazine)
	t.ok(nu_core.rifle_press_route(), "★ 就绪 ⇒ 这一按次走蓄力路")
	nu_core.rifle_mag -= 1
	t.not_ok(nu_core.rifle_press_route(), "★ 弹匣少一发 ⇒ 走老路（连发保住）")
	nu_core.rifle_mag = nu_core.profile.rifle_magazine
	nu_core.cannon_cd_left = 5.0
	t.not_ok(nu_core.rifle_press_route(), "★ 冷却中 ⇒ 走老路")
	nu_core.cannon_cd_left = 0.0
	nu_core.rifle_reloading = true
	t.not_ok(nu_core.rifle_press_route(), "★ 过热换弹中 ⇒ 走老路")
	nu_core.rifle_reloading = false
	t.ok(nu_core.rifle_press_route(), "★ 三条复位之后**立刻**恢复蓄力路")
	t.not_ok(nu_core.profile.rifle_fire_on_release,
		"★ 它的 `rifle_fire_on_release` 仍是 false（走条件路由，不是常开松手）")
	_drop(nu_core)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame


# ------------------------------------------------------------ ③ 锁存

## ★★ 本组的全部意义：路由**只在按下那一帧取一次**，之后整个按次不再重判。
##
## 坏了会怎样（两个方向都不报错，只是手感错）：
##   · 逐帧重算 ⇒ 满弹匣按住蓄力的玩家，在**弹匣被换满那一刻**（或冷却走完那一刻）
##     会看到枪**自己开始响** —— 而他按着不动、那时人已经在蓄力态里；
##   · 反过来：弹匣不满按住连发的玩家，会中途**突然变成蓄力**、连发断掉。
static func _latch(t: T, host: Node) -> void:
	# ---- 正向：就绪按下 ⇒ 锁在蓄力路，之后状态怎么变都不动摇 ----
	var a := _make(host, SuitProfile.penelope(), "latch_a")
	t.not_ok(a.rifle_press_is_cannon(), "初值 false（这一按次还没取过路由）")
	a.latch_rifle_route(true)
	t.ok(a.rifle_press_is_cannon(), "按下那一刻（就绪）⇒ 锁在蓄力路")

	# 按下之后把两个门槛都破坏掉，再连调 10 帧「非按下帧」
	a.rifle_mag = 0
	a.cannon_cd_left = 20.0
	for i in 10:
		a.latch_rifle_route(false)
	t.ok(a.rifle_press_is_cannon(),
		"★ 之后把弹匣打空 + 灌满冷却、连过 10 帧**仍锁在蓄力路**"
		+ "（逐帧重判的话这里会翻成 false）")

	# ---- 反向：不满按下 ⇒ 锁在老路，之后补满也不动摇 ----
	var b := _make(host, SuitProfile.penelope(), "latch_b")
	b.rifle_mag = b.profile.rifle_magazine - 1
	b.latch_rifle_route(true)
	t.not_ok(b.rifle_press_is_cannon(), "按下那一刻**不满** ⇒ 锁在老路")
	b.rifle_mag = b.profile.rifle_magazine
	b.cannon_cd_left = 0.0
	for i in 10:
		b.latch_rifle_route(false)
	t.not_ok(b.rifle_press_is_cannon(),
		"★ 之后把弹匣补满、冷却清零、连过 10 帧**仍锁在老路**"
		+ "（不会中途变成蓄力、把连发断掉）")

	# ---- 非按下帧不会自己取路由 ----
	var c := _make(host, SuitProfile.penelope(), "latch_c")
	c.latch_rifle_route(false)
	t.not_ok(c.rifle_press_is_cannon(),
		"从没按下过 ⇒ 恒 false（`press_frame` 为假时不取路由）")

	_drop(a)
	_drop(b)
	_drop(c)
	await host.get_tree().physics_frame


# ------------------------------------------------------------ ④ 门禁（她独有的那条）

static func _gates(t: T, host: Node) -> void:
	var pc := _make(host, SuitProfile.penelope(), "gate")
	var mag := pc.profile.rifle_magazine

	t.eq(pc.rifle_mag, mag, "出场弹匣是满的（%d 发）" % mag)
	t.eq(pc.rifle_count, 1, "带 1 把步枪（她的 `rifle_count = 1`）")
	t.gt(float(pc.cannon_muzzles().size()), 0.0,
		"炮口取自**她自己的** `_muzzle_local`（%d 个，不是阿利宙斯的双联背包）"
			% pc.cannon_muzzles().size())
	t.ok(pc.cannon_ready(), "满弹匣 ⇒ 就绪")

	# ★ 她独有的那一层：门槛必须按 `profile.rifle_magazine` 判，不能照抄阿利宙斯的 2。
	pc.rifle_mag = mag - 1
	t.not_ok(pc.cannon_ready(),
		"★ **只少一发**（%d/%d）就不可用 —— 门槛读的是她**自己**的容量"
			% [pc.rifle_mag, mag])
	print("  [G] 少一发时 cannon_ready()=%s（挂上「少一发」前提之后应恒 false）"
		% str(pc.cannon_ready()))
	pc.rifle_mag = mag
	t.ok(pc.cannon_ready(), "补满 ⇒ 又能放")

	# 真的放一次：冷却 / 过热 / 不吃弹匣（三条都是阿利宙斯那套的**同一份**实现）
	var before := _count_projectiles(pc)
	t.ok(pc.fire_cannon(null), "发射成功")
	# ⚠️ 先读数、再 await：`fire_cannon()` 只在发射那一瞬间把冷却/换弹置满，
	#    等一帧 `_tick_weapons()` 会各减 1/60 s ⇒ 读数变成 19.9833 / 14.9833（假失败）。
	t.near(pc.cannon_cd_left, pc.profile.cannon_cooldown, 0.001,
		"大炮冷却 = %.0f s（从发射那一刻起算）" % pc.profile.cannon_cooldown)
	t.ok(pc.rifle_reloading, "光束步枪**立刻进入过热换弹**")
	t.near(pc.reload_timer, pc.profile.cannon_overheat_reload, 0.001, "过热换弹 = 15 s")
	t.eq(pc.rifle_mag, mag, "大炮**不消耗弹匣**（她自己的容量也没被动过）")
	t.not_ok(pc.cannon_ready(), "过热换弹期间不可用（这就是「过热」的意思）")
	await host.get_tree().physics_frame
	var cannons := 0
	for ch in pc.projectile_container.get_children():
		if ch is BeamCannon:
			cannons += 1
	t.eq(cannons, 1, "场上多出**一条**激光柱")
	t.eq(_count_projectiles(pc) - before, 0,
		"柱体走**另一条**通道（`BeamCannon`），不混进 `Projectile` 计数"
		+ " —— 这句给下面 A/B 的计数口径作保")

	_drop(pc)
	await host.get_tree().physics_frame


# ------------------------------------------------------------ ⑤ 输入层 A/B

## ★★ 本组把「保住连发」逐字量出来：**同一套循环、同一个入口**，只换一个前提。
##
##   (a) 满弹匣（就绪）⇒ 按住 2 秒：**一发光束都打不出**，而是进蓄力态；
##   (b) 弹匣少一发   ⇒ 按住 2 秒：**真的在连发**（打出多发）。
##
## ⚠️ 两条必须成对：只做 (a) 的话，「打不出弹」也可能只是「根本没接上」（假绿）；
##    只做 (b) 的话，测不到大炮那条路。这是本组全部的证伪设计。
static func _behavior(t: T, host: Node) -> void:
	# ---- (a) 就绪：抑制开火、进蓄力 ----
	var a := _make(host, SuitProfile.penelope(), "beh_a")
	a.latch_rifle_route(true)
	t.ok(a.rifle_press_is_cannon(), "(a) 前提：这一按次锁在蓄力路")

	var a0 := _count_projectiles(a)
	Input.action_press("fire_primary")
	for i in HOLD_FRAMES:
		# 把射速冷却清零 ⇒ 若真的走了老路，每一帧都会打出一发（放大信噪比）
		a.rifle_cooldown = 0.0
		a._read_weapon_input(DT)
	Input.action_release("fire_primary")

	var a_shots := _count_projectiles(a) - a0
	print("  [A] 满弹匣按住 %.2f s：打出 %d 发光束 · _fire_hold=%.3f s · charging=%s"
		% [HOLD_FRAMES * DT, a_shots, a._fire_hold, str(a.cannon_charging())])
	t.eq(a_shots, 0,
		"★ (a) 满弹匣按住 2 秒**一发光束都没打出**（走了蓄力路，不是老路）")
	t.ok(a.rifle_mag >= a.profile.rifle_magazine,
		"★ 而且弹匣**一发没掉**（%d/%d）—— 这正是「按满 1.7 s 时弹匣仍然满」的前提"
			% [a.rifle_mag, a.profile.rifle_magazine])
	t.ok(a._fire_hold > 0.0, "按住时长在累计（_fire_hold = %.3f s）" % a._fire_hold)
	t.ok(a.cannon_charging(),
		"★ 按住超过门槛 %.1f s 之后进了**蓄力态**（_fire_hold = %.3f s）"
			% [a.profile.cannon_charge_time, a._fire_hold])

	# ---- (b) 不满：照旧连发 ----
	var b := _make(host, SuitProfile.penelope(), "beh_b")
	b.rifle_mag = b.profile.rifle_magazine - 1
	b.latch_rifle_route(true)
	t.not_ok(b.rifle_press_is_cannon(), "(b) 前提：这一按次锁在**老路**")

	var b0 := _count_projectiles(b)
	Input.action_press("fire_primary")
	for i in HOLD_FRAMES:
		b.rifle_cooldown = 0.0
		b._read_weapon_input(DT)
	Input.action_release("fire_primary")

	var b_shots := _count_projectiles(b) - b0
	print("  [B] 弹匣不满（%d 发）按住 %.2f s：打出 %d 发光束 · charging=%s"
		% [b.profile.rifle_magazine - 1, HOLD_FRAMES * DT, b_shots,
			str(b.cannon_charging())])
	t.gt(float(b_shots), 1.0,
		"★ (b) 弹匣不满按住 2 秒**真的在连发**（打出 %d 发 > 1）"
			% b_shots + " —— 这就是用户要的「保住连发」")
	t.not_ok(b.cannon_charging(),
		"★ 而且它**不会**进蓄力态（那时大炮本来就不该可用）")

	# ---- 两条一起看：同一套循环，唯一的差别就是「按下那一刻满不满」 ----
	t.gt(float(b_shots), float(a_shots),
		"★ A/B 分离度：连发 %d 发 vs 蓄力 %d 发（同一入口、同一帧数、同一台机体）"
			% [b_shots, a_shots])

	_drop(a)
	_drop(b)
	await host.get_tree().physics_frame


# ------------------------------------------------------------ ⑥ 接线（源码）

## 剥掉**整行注释**后的源码。
##
## ⚠️ **必须剥** —— 本轮的说明文字里到处写着 `rifle_press_route` / `_rifle_press_cannon`
## 这些名字，不剥的话「名字出现过」与「代码真的读它」分不开（假绿）。
## 与 `suite_arizeus_cannon._code()` / `suite_fire_action._code()` 同一口径。
static func _code(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	var out := ""
	for line in txt.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out += line + "\n"
	return out


## 取 `header` 起、到**下一个顶层函数**之前的这一段（即该函数的函数体）。
##
## ⚠️ 终止符**两个都要找**：`\nfunc ` 匹配不到 `\nstatic func `（`static` 插在中间），
## 只找一个的话 `static func penelope()` 会一路吞到**下一个非 static 函数**
## —— 于是"她体内没有 `rifle_fire_on_release`"这条会读到 `arizeus()` 的内容而**假红**。
## （本轮真踩过：80 条里那唯一的 FAIL 就是这个工具函数，不是产品代码。）
static func _fn_body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var j := src.length()
	var seps: Array[String] = ["\nfunc ", "\nstatic func "]
	for sep: String in seps:
		var k := src.find(sep, i + 1)
		if k >= 0 and k < j:
			j = k
	return src.substr(i, j - i)


static func _wiring(t: T) -> void:
	var pc := _code(PLAYER_PATH)
	var prof := _code(PROFILE_PATH)
	t.ok(pc != "", "读到了 player_controller.gd 且剥掉了注释行")

	# ---- 三个函数都在 ----
	var fns := ["rifle_press_route", "latch_rifle_route", "rifle_press_is_cannon"]
	for f in fns:
		t.ok(pc.contains("func " + f), "`%s()` 存在" % f)

	# ---- 路由判定的真源：两个字段 + 一个就绪判据，全在同一个函数里 ----
	var body_route := _fn_body(pc, "func rifle_press_route")
	t.ok(body_route != "", "取到了 `rifle_press_route()` 的函数体")
	t.ok(body_route.contains("profile.rifle_fire_on_release"),
		"它读 `profile.rifle_fire_on_release`（按**机体表字段**分派，不是按 id 现判）")
	t.ok(body_route.contains("profile.cannon_enabled"), "它读 `profile.cannon_enabled`")
	t.ok(body_route.contains("cannon_ready()"),
		"★ 它读 `cannon_ready()` —— 与真正发射用的是**同一个就绪判据**"
		+ "（不是自己把门槛再写一遍）")

	# ---- 锁存：只有「按下那一帧」能改写 ----
	var body_latch := _fn_body(pc, "func latch_rifle_route")
	t.ok(body_latch != "", "取到了 `latch_rifle_route()` 的函数体")
	t.ok(body_latch.contains("if not press_frame:"),
		"★ 非按下帧**直接 return** ⇒ 锁存值整个按次不会被改写")
	t.ok(body_latch.contains("_rifle_press_cannon = "),
		"锁存值的**唯一**写入点就在这里")

	# ---- 调用点：真的有人读它（本工程栽得最多的地方） ----
	var i_rwi := pc.find("func _read_weapon_input(")
	t.gt(float(i_rwi), 0.0, "找到 `_read_weapon_input()`")
	var i_call := pc.find('latch_rifle_route(Input.is_action_just_pressed', i_rwi)
	t.gt(float(i_call), float(i_rwi),
		"★ 输入循环里**真的调了** `latch_rifle_route(Input.is_action_just_pressed(...))`"
		+ "（只写函数不接线 = 需求没做）")
	var i_br := pc.find("if _rifle_press_cannon:", i_call)
	t.gt(float(i_br), float(i_call), "紧随其后按**锁存值**分派")
	var i_rel := pc.find("_read_release_rifle(delta, target)", i_br)
	t.gt(float(i_rel), float(i_br), "★ 蓄力 / 松手那条路挂在锁存值这一支上")
	var i_old := pc.find('elif Input.is_action_pressed("fire_primary")', i_rel)
	t.gt(float(i_old), float(i_rel),
		"★ 老路（按住连发）仍挂在 **elif** 上 —— 新分支没有把它挤掉")

	# ---- 反面：输入循环里**不许**每帧重算路由 ----
	#
	# 这一条防的是「顺手把 `_rifle_press_cannon` 换成 `rifle_press_route()`」这类简化：
	# 行为测试抓不到它（本套件是**手动**调入口的，框架循环没在跑），只有源码位置能钉死。
	var body_rwi := _fn_body(pc, "func _read_weapon_input(")
	t.not_ok(body_rwi.contains("rifle_press_route()"),
		"★ `_read_weapon_input()` 里**没有**直接调 `rifle_press_route()`"
		+ "（否则就是逐帧重判 ⇒ 蓄力途中枪会自己响）")

	# ---- 反面：取消蓄力时**不许**顺手重置锁存 ----
	var body_cancel := _fn_body(pc, "func _cancel_cannon_charge")
	t.ok(body_cancel != "", "取到了 `_cancel_cannon_charge()` 的函数体")
	t.not_ok(body_cancel.contains("_rifle_press_cannon"),
		"★ 取消蓄力时**不重置**锁存值（清了的话阿利宙斯会在变形 / 硬直那一刻"
		+ "中途切进老路、按着不动枪自己响）")

	# ---- 数据侧：别把佩涅罗佩「顺手」改成松手单发 ----
	var body_pen := _fn_body(prof, "static func penelope()")
	t.ok(body_pen != "", "取到了 `penelope()` 的函数体")
	t.ok(body_pen.contains("p.cannon_enabled = true"), "她有炮这件事写在机体表里")
	t.not_ok(body_pen.contains("rifle_fire_on_release"),
		"★ `penelope()` 里**没有** `rifle_fire_on_release`（用户拍板「保住连发」）")
