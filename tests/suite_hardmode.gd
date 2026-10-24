class_name SuiteHardMode
extends RefCounted
## **困难模式的难度**（1.2 第二十七轮）。
##
## 用户原话：「增加困难模式的难度，现在**有了全弹发射之后**，
## 佩涅罗佩和阿利宙斯的困难模式变得**特别容易通关**了」。
##
## ## 这一轮改了什么、以及为什么不是"提数值"
##
## 全弹发射是**一次 100 发**，AI 挨上基本必死。所以真正的杠杆不是
## "敌机血更厚/更快"，而是**它会不会对大规模来袭做出反应**。
##
## ⚠️ **不能靠提 `speed_mult`**：`suite_round` / `suite_round14` 有一条回归门
## "敌机极速 ≤ 玩家加力 × 0.92" —— 那是"追不上的对手"的防线，动不得。
## 所以难度落在**行为**上：困难档走"确定性反应"（来袭到阈值就放干扰弹，
## 不吃概率）。
##
## ## 本套件钉得住的 / 钉不住的（如实说明）
##
## 钉得住：三档的 `missile_defense` 取值与单调性、以及"速度那条回归门没被动过"。
##
## ⚠️ **钉不住**：`_drive_flares()` 里"≥4 发来袭就立即放"那一段**没有单测** ——
## 它要真的把几发导弹发射到某个 AI 的追踪列表里才算数，而那要起一整局
## 加上时间推进（本工程的测试里没有现成的"朝 AI 打一梭"的夹具）。
## 所以那一段目前**只有代码审查覆盖**；真要验，得先写一个"导弹夹具"。
## 记在这里，别以为它是被验过的。

const KNOBS := "HardMode / 难度旋钮：导弹防御积极度"
const GUARD := "HardMode / 改动边界：没有动速度与伤害"
const PERSUIT := "HardMode / 困难强度**跟着玩家选的机体**走"
const PRESSURE := "HardMode / 王牌机强制进攻节拍（63-9 改口：12s → 9s）"
const NO_REGEN := "HardMode / 重算难度**不许把血补满**（回归门）"


static func run(t: T, host: Node) -> void:
	t.suite(KNOBS)
	_knobs(t)
	t.suite(GUARD)
	_guard(t)
	t.suite(PERSUIT)
	_per_suit(t)
	t.suite(PRESSURE)
	await _pressure(t, host)
	t.suite(NO_REGEN)
	await _no_regen(t, host)


## ⚠️ **回归门**：这一条对应用户实测报的那个严重 bug。
##
## 用户原话：「**敌方机体的 I 立场护盾和血量都会自动回复，完全打不掉**」。
##
## 真因不是"敌机自带回血"，而是**重算难度时顺手把血补满了**：
## `_apply_difficulty()` 会被 `_drive_form()` 在**每次形态切换成功**时调用，
## 而它第一版写的是 `hp = max_hp` / `ifield_hp = ifield_max`。
## 于是**阿利宙斯每变一次形态就回满一次** —— 表现完全像"自动回血"。
##
## 本组钉三件事：
##   ① 重算难度**保留当前比例**（不白送血）；
##   ② `max_hp` 幂等（重复调不连乘）；
##   ③ 出生时仍然是满的（别修过头，让敌人一出生就残血）。
static func _no_regen(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var foe := _mk(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL), 1)
	await host.get_tree().physics_frame

	# ---- ③ 出生是满的 ----
	t.near(foe.hp, foe.max_hp, 0.001, "刚出生是**满血**")
	t.near(foe.ifield_hp, foe.ifield_max, 0.001, "刚出生 I 立场是**满的**")
	var base_max: float = foe.max_hp
	var base_ifield_max: float = foe.ifield_max

	# ---- ① 打掉一半，再重算难度（= 模拟一次变形）----
	foe.hp = foe.max_hp * 0.5
	foe.ifield_hp = foe.ifield_max * 0.25
	foe._apply_difficulty()
	t.near(foe.hp, foe.max_hp * 0.5, 0.001,
		"**重算难度不会把血补满**（实测 %.1f / %.1f）" % [foe.hp, foe.max_hp])
	t.near(foe.ifield_hp, foe.ifield_max * 0.25, 0.001,
		"**I 立场也不回**（实测 %.1f / %.1f）" % [foe.ifield_hp, foe.ifield_max])

	# 反复重算（模拟连续变形）也不能回血 —— 这正是用户看到的现象
	for i in 5:
		foe._apply_difficulty()
	t.near(foe.hp, foe.max_hp * 0.5, 0.001,
		"连调 6 次仍然只有一半血（这就是「完全打不掉」那条的判据）")

	# ---- ② max_hp 幂等：不连乘 ----
	t.near(foe.max_hp, base_max, 0.001, "`max_hp` 幂等（重复调**不连乘**）")
	t.near(foe.ifield_max, base_ifield_max, 0.001, "`ifield_max` 同理")

	# ---- 打空之后重算，仍然是空的 ----
	foe.hp = 1.0
	foe.ifield_hp = 0.0
	foe._apply_difficulty()
	t.lt(foe.hp, foe.max_hp * 0.05, "残血重算后仍然是残血")
	t.near(foe.ifield_hp, 0.0, 0.001, "I 立场仍是 0")

	c.queue_free()
	await host.get_tree().physics_frame


## 用户原话：「**增加对方王牌机的进攻欲望，每 12 秒强制进攻一次**」。
##
## ★ 轮 63-9 · B5（用户 2026-10-04 改口）：「阿利宙斯偶尔会一直跑路，
## 需要让他进攻欲望增强。」⇒ 周期 **12 → 9**、窗口 **4 → 5**
##（占空比 33.3% → 55.6%）。下面这条断言就是那次改口的**唯一真源**。
##
## 这条不是"更凶一点"，而是**给进攻加一个下限**：
## 状态机是"条件满足才打"（`dist < engage_dist() and ang < 75`），
## 双方互相绕圈时 ACE 会一直卡在 `SEEK`/`EXTEND` 里**什么都不做** ——
## 玩家看到的是"敌机在发呆"。
static func _pressure(t: T, host: Node) -> void:
	t.near(BanditAI.ACE_ATTACK_PERIOD, 9.0, 0.001,
		"强制进攻周期 = **9 秒**（63-9 用户改口；原稿的 12 秒也是用户自己定的）")
	t.gt(BanditAI.ACE_COMMIT_WINDOW, 0.0, "有不许脱战的窗口（否则强制进攻会被下一帧推翻）")
	t.lt(BanditAI.ACE_COMMIT_WINDOW, BanditAI.ACE_ATTACK_PERIOD,
		"窗口比周期短（否则它一直在进攻、从不脱离，变成无脑冲）")

	# ---- 占空比：把"想让它多凶"变成一个可算的数 ----
	#
	# `probe_aggression` 量的就是这件事的真机读数；这里钉的是**纯函数级**下界
	#（真机绝对值随态势变，探针自己那头也写了这条）。
	var duty: float = BanditAI.ACE_COMMIT_WINDOW / BanditAI.ACE_ATTACK_PERIOD
	t.ok(duty >= 0.5,
		"强制进攻占空比不低于 0.5（63-9 之后；改动前是 0.333），实测 " + str(snappedf(duty, 0.001)))
	t.ok(duty < 1.0, "占空比仍小于 1（还留得出脱离的时间）")

	var c := Node3D.new()
	host.add_child(c)
	# 一台 ACE（柯西）+ 一台量产机（梅萨），都朝同一个敌人。
	var ace := _mk(c, SuitProfile.xi(), 1)
	var mp := _mk(c, SuitProfile.messer_m01(), 1)
	await host.get_tree().physics_frame
	var foe := _mk(c, SuitProfile.messer_m01(), 0)
	await host.get_tree().physics_frame
	foe.global_position = Vector3(0.0, 3200.0, -4000.0)
	ace.global_position = Vector3(0.0, 3200.0, 0.0)
	mp.global_position = Vector3(0.0, 3200.0, 0.0)
	ace._target = foe
	mp._target = foe
	ace._ace_pressure = 0.0
	mp._ace_pressure = 0.0
	ace.set_state(BanditAI.State.SEEK)
	mp.set_state(BanditAI.State.SEEK)

	# ---- ① 量产机**没有**这个节拍 ----
	mp._tick_ace_pressure(BanditAI.ACE_ATTACK_PERIOD + 1.0)
	t.eq(mp.state, BanditAI.State.SEEK,
		"量产机**不做**强制进攻（用户说的是「对方**王牌机**」）")
	t.near(mp._ace_pressure, 0.0, 0.001, "量产机的压力计时不累加")

	# ---- ② 没到一个周期不强制 ----
	ace._tick_ace_pressure(BanditAI.ACE_ATTACK_PERIOD - 1.0)
	t.eq(ace.state, BanditAI.State.SEEK, "还没到一个周期 ⇒ 不强制")
	t.gt(ace._ace_pressure, 0.0, "但压力在累加")

	# ---- ③ 满了周期 ⇒ 强制进 ATTACK ----
	ace._tick_ace_pressure(2.0)
	t.eq(ace.state, BanditAI.State.ATTACK,
		"**满一个周期 ⇒ 强制进攻**（这就是用户要的那一条）")
	t.near(ace._ace_pressure, 0.0, 0.001, "计时归零、重新开始数")
	t.gt(ace._ace_commit, 0.0, "进入不许脱战窗口")

	# ---- ④ 窗口内**不许**脱战 ----
	#
	# 判据走真实的 `_decide_desired_direction()`：把距离压到 `break_dist()` 以内
	#（正常会切 EXTEND）再看状态有没有被切走。
	#
	# ⚠️ **必须同时钉住 `_lag_pos`**：`_decide_desired_direction()` 用的是
	# `_aim_pos()`，而那是**滞后**的瞄准位置（AI 的反应延迟正体现在这里）。
	# 只挪 `foe.global_position` 而不同步 `_lag_pos` 的话，距离是拿"旧位置"量的
	# —— 第一版就是这么红的，看着像"窗口没生效"。
	ace.global_position = foe.global_position + Vector3(0.0, 0.0, 100.0)
	ace._lag_pos = foe.global_position
	ace._state_time = 99.0
	ace._decide_desired_direction()
	t.eq(ace.state, BanditAI.State.ATTACK,
		"在窗口里贴到脸上了**也不脱离**（否则强制进攻形同虚设）")

	# ---- ⑤ 窗口走完之后恢复正常判断 ----
	ace._tick_ace_pressure(BanditAI.ACE_COMMIT_WINDOW + 0.5)
	ace._lag_pos = foe.global_position
	ace._decide_desired_direction()
	t.eq(ace.state, BanditAI.State.EXTEND,
		"窗口过了 ⇒ 贴脸时**恢复**正常的脱离判断")

	# ---- ⑥ 没有目标时不做强制进攻 ----
	ace._target = null
	ace.set_state(BanditAI.State.SEEK)
	ace._ace_pressure = 0.0
	ace._tick_ace_pressure(BanditAI.ACE_ATTACK_PERIOD + 1.0)
	t.eq(ace.state, BanditAI.State.SEEK,
		"没有目标 ⇒ **不**强制进攻（没有「进攻」可言）")

	c.queue_free()
	await host.get_tree().physics_frame


static func _mk(parent: Node3D, p: SuitProfile, team: int) -> BanditAI:
	var fb := BanditAI.new()
	fb.team = team
	fb.profile = p
	fb.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	fb.projectile_container = parent
	parent.add_child(fb)
	fb.global_position = Vector3(0.0, 3200.0, 0.0)
	return fb


## 用户第二轮澄清（这一条把第一版的方向整个纠正了）：
##   「**困难柯西很难**，难度可以只稍微上调 **20%**。
##     剩余的**困难佩涅罗佩和困难阿利宙斯就太简单了**，失去了困难模式的意义」。
##
## 所以系数挂在**玩家选的机体**上，含义是"我开这台机打困难时，敌人被强化几倍"。
## 第一版我把它理解成"这台机当敌人时多强"，**方向反了** ——
## 幸好这一轮还没落地就被澄清了，记在这里当教训：
## 「困难 XX」在这位用户嘴里指的是**玩家开 XX 打困难**，不是"敌人是 XX"。
static func _per_suit(t: T) -> void:
	var xi := SuitProfile.xi()
	var pen := SuitProfile.penelope()
	var ari := SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)
	# 柯西：最多 +20%（用户给的上限）
	t.lt(xi.hard_enemy_reinforce, 1.201, "困难**柯西**的强化 ≤ 1.20（用户给的上限）")
	t.gt(xi.hard_enemy_reinforce, 0.999, "柯西仍有一点强化（不是 1.0 摆着不调）")
	# 佩涅罗佩 / 阿利宙斯：用户点名的两台，必须**明显**更大
	t.gt(pen.hard_enemy_reinforce, 1.5,
		"困难**佩涅罗佩**的强化明显更大（实测 %.2f）" % pen.hard_enemy_reinforce)
	t.gt(ari.hard_enemy_reinforce, 1.5,
		"困难**阿利宙斯**的强化明显更大（实测 %.2f）" % ari.hard_enemy_reinforce)
	# 这两台要**远高于**柯西 —— 否则"失去了困难模式的意义"那条没解决
	t.gt(pen.hard_enemy_reinforce, xi.hard_enemy_reinforce * 1.4,
		"佩涅罗佩的强化**远高于**柯西（不是同一档）")
	t.gt(ari.hard_enemy_reinforce, xi.hard_enemy_reinforce * 1.4,
		"阿利宙斯的强化**远高于**柯西")
	# 量产机：这两台不参与 ACE 对局，保持 1.0（不动既有平衡）
	t.near(SuitProfile.messer_m01().hard_enemy_reinforce, 1.0, 0.001,
		"量产机（梅萨）不额外强化")
	t.near(SuitProfile.gustav00_armed().hard_enemy_reinforce, 1.0, 0.001,
		"量产机（古斯塔夫）不额外强化")


static func _knobs(t: T) -> void:
	var easy := Difficulty.make(Difficulty.Level.EASY)
	var normal := Difficulty.make(Difficulty.Level.NORMAL)
	var hard := Difficulty.make(Difficulty.Level.HARD)

	# 三档都要有这个旋钮（不给的话 `BanditAI` 会退回默认值，
	# 于是"简单/困难"在这一条上变成同一个 AI）。
	t.gt(easy.missile_defense, -0.001, "简单档有 missile_defense")
	t.gt(normal.missile_defense, -0.001, "中等档有 missile_defense")
	t.gt(hard.missile_defense, -0.001, "困难档有 missile_defense")
	# ⚠️ **单调递增**：难度越高，对导弹越积极。
	# 写成"三个绝对值"会被后来的微调打碎，而"单调"是这条旋钮的**语义**。
	t.lt(easy.missile_defense, normal.missile_defense,
		"简单 < 中等（%.2f < %.2f）" % [easy.missile_defense, normal.missile_defense])
	t.lt(normal.missile_defense, hard.missile_defense,
		"中等 < 困难（%.2f < %.2f）" % [normal.missile_defense, hard.missile_defense])
	# 困难档必须落在"确定性反应"那一侧（`_drive_flares()` 判的是 `>= 1.0`）。
	# ⚠️ 这一条是**接线契约**：把它调到 0.9 会让困难档**悄悄退回概率触发**，
	# 表现是"这一轮改了个寂寞"，而没有任何东西会报错。
	t.gt(hard.missile_defense, 0.999,
		"困难档 = 1.0（触发**确定性**反应那条分支）")
	t.lt(normal.missile_defense, 0.999,
		"中等档 < 1.0（仍走概率触发，保留「偶尔会漏」的手感）")
	# 三档的其它旋钮仍然有别（别把难度做成一维的）
	t.lt(easy.ai_skill, hard.ai_skill, "难度仍然影响 AI 技能值")
	t.lt(easy.speed_mult, hard.speed_mult, "难度仍然影响速度倍率")


static func _guard(t: T) -> void:
	# ---- 这一轮**没有**动速度与伤害倍率 ----
	#
	# ⚠️ 第一版这里想"重算一遍速度天花板" —— **那条断言写错了**：
	# `speed_mult` 是**乘在敌机基速上的**（而敌机基速由 `SuitProfile.speed_scale`
	# 压得很低），并不是"敌机速度 ÷ 玩家速度"。所以
	# `player_boost × speed_mult < player_boost × 0.92` 在 `speed_mult > 0.92`
	# 时**恒假** —— 我那版断言在困难档（1.5）必然红。
	#
	# 真正的速度回归门在 `suite_round` / `suite_round14` 里（量的是**配置好的**
	# 敌机极速），这里不重复造一遍 —— 造错了反而会误导。
	#
	# 这里钉的是**这一轮的改动边界**：难度只加在**行为**上（导弹防御），
	# 数值一个字没动。这条断言的作用是"如果有人顺手调了速度和伤害，
	# 这里会红，逼他说明理由"。
	var hard := Difficulty.make(Difficulty.Level.HARD)
	t.near(hard.speed_mult, 1.5, 0.001,
		"困难的速度倍率**保持 1.5**（这一轮没动它 —— 难度靠行为加）")
	t.near(hard.damage_mult, 1.3, 0.001,
		"困难的伤害倍率**保持 1.3**（同上）")
	t.near(hard.ai_skill, 0.92, 0.001, "AI 技能值也保持 0.92")
	# 这三条一起说明：这一轮的难度增量**全部**来自 `missile_defense`。
	t.gt(hard.missile_defense, 0.999, "而导弹防御积极度是新加的那一条")
