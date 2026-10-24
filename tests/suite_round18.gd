class_name SuiteRound18
extends RefCounted
## 第十八轮：**军刀相杀**（1.2 用户指定）。
##
## 需求原话：「近战系统要加入相杀（**在同一段时间判定窗口内都使用了光束军刀攻击，
## 则触发相杀**，相杀之后会**暂时失去双方的锁定**，并且**强制弹开一段距离**）」。
##
## ⚠️ 这一轮最要紧的一条设计是**判定顺序**：相杀的判定距离（100 m）**大于**
## 军刀的命中距离（78 m），而且 `_step_saber()` 里**先查相杀、再查命中**。
## 反过来的话"双方对冲"永远先判命中、相杀只在"偏偏没砍中"时才出现 ——
## 那等于没做这个机制。下面第二组专门钉这一条。
##
## 分五组测，因为坏起来的样子完全不同：
##   1. **常量契约** —— 判定距离必须 > 命中距离；冷却必须 > 失锁时长。
##   2. **触发条件** —— 双方都突进 + 敌对 + 贴到范围内；少一条都不触发。
##   3. **相杀的后果** —— 不掉血 / 双方脱锁 / 互相锁不上 / 被弹开。
##   4. **冷却** —— 冷却期内再冲不会二次相杀（防"相杀死循环"）。
##   5. **与踏板联动** —— 被相杀强制脱板，且**不吃伤害**。

const CONTRACT := "Round18 / 相杀：常量契约"
const TRIGGER := "Round18 / 相杀：触发条件"
const EFFECT := "Round18 / 相杀：后果（不掉血 / 脱锁 / 弹开）"
const COOLDOWN := "Round18 / 相杀：冷却防死循环"
const PEDAL := "Round18 / 相杀与踏板联动"


static func run(t: T, host: Node) -> void:
	t.suite(CONTRACT)
	_contract(t)
	t.suite(TRIGGER)
	await _trigger(t, host)
	t.suite(EFFECT)
	await _effect(t, host)
	t.suite(COOLDOWN)
	await _cooldown(t, host)
	t.suite(PEDAL)
	await _pedal(t, host)


# ---------------------------------------------------------------- 1 常量契约

static func _contract(t: T) -> void:
	# ⚠️ **判定距离必须大于命中距离**。这条不是"手感调优"，是"机制存不存在"：
	# 若相杀窗口比命中窗口小，双方对冲永远先在命中距离处结算伤害，
	# 相杀只在"两边都打偏"时才出现 —— 而那正是需求**不**想要的情况。
	var hit := SuitProfile.xi().saber_hit_range
	t.gt(FlightBody.CLASH_RANGE, hit,
		"相杀判定距离（%.0f m）> 军刀命中距离（%.0f m）—— 否则相杀永远轮不到"
			% [FlightBody.CLASH_RANGE, hit])

	# ⚠️ **冷却必须比失锁时长长**，否则"刚能重新锁定就又对撞"，
	# 贴脸缠斗会变成相杀死循环（谁也没法真正进入伤害交换）。
	t.gt(FlightBody.CLASH_COOLDOWN, FlightBody.CLASH_UNLOCKABLE,
		"相杀冷却（%.1f s）> 失锁时长（%.1f s）—— 否则会相杀死循环"
			% [FlightBody.CLASH_COOLDOWN, FlightBody.CLASH_UNLOCKABLE])

	t.gt(FlightBody.CLASH_PUSH_SPEED, 100.0, "弹开速度是个「真的把人推开」的量级")

	# 判定窗口：军刀突进本身就有 1.5~2.4 s，两边都在突进 = 窗口重叠。
	# 断言"窗口比一次突进短" —— 否则"两边都在突进"就没有窗口意义了。
	var dash := SuitProfile.xi().saber_dash_time
	t.gt(dash, 0.0, "军刀突进有持续时间（%.1f s）—— 相杀的「判定窗口」就是它" % dash)

	# `SaberState` **不该有 CLASH 档**：相杀是瞬时事件，双方立刻回 IDLE。
	t.eq(FlightBody.SaberState.size(), 2,
		"SaberState 只有 IDLE / CHARGE 两档（相杀是瞬时的，不驻留状态）")


# ---------------------------------------------------------------- 2 触发条件

static func _trigger(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	# 两台对冲的机体，面对面、相距 **85 m**：
	# **相杀圈（100 m）之内、命中圈（78 m）之外** —— 这个区间是相杀唯一能成立的地方。
	# ⚠️ 玩家队那台标 `as_player`（限定 ⑥：相杀只属于「玩家 vs 敌机」）。
	var a := _make(c, "ClashA", 0, null, true)
	var b := _make(c, "ClashB", 1)
	await host.get_tree().physics_frame
	_face_each_other(a, b, 85.0)
	await host.get_tree().physics_frame

	# ---- ① 只一方挥刀 → 不触发 ----
	a.try_saber(b)
	a._step_saber(1.0 / 60.0)
	t.eq(a.clash_count, 0, "只有一方挥刀 → **不**触发相杀")
	a.abort_saber()
	await host.get_tree().physics_frame

	# ---- ② 双方都挥刀 + 敌对 + 在相杀圈内 → 触发 ----
	a.clash_count = 0
	b.clash_count = 0
	a.saber_cooldown = 0.0
	_arm_and_step(a, b)
	t.gt(a.clash_count, 0, "双方都突进 + 在 100 m 内 → **触发相杀**（A 侧记到）")
	t.gt(b.clash_count, 0, "B 侧也记到（双方各记一次）")

	# ---- ③ 队友之间不触发 ----
	a.clash_count = 0
	b.clash_count = 0
	b.team = 0            # b 变成友军
	a.saber_cooldown = 0.0
	a.try_saber(b)
	b.try_saber(a)
	a._step_saber(1.0 / 60.0)
	t.eq(a.clash_count, 0, "**队友之间不触发相杀**（2v2 里这条很要紧）")
	b.team = 1

	# ---- ④ 距离太远不触发 ----
	a.clash_count = 0
	b.clash_count = 0
	a.saber_cooldown = 0.0
	_face_each_other(a, b, FlightBody.CLASH_RANGE + 50.0)
	await host.get_tree().physics_frame
	_arm_and_step(a, b)
	t.eq(a.clash_count, 0, "超出相杀距离 → **不**触发")

	# ---- ⑤ **AI 之间不触发相杀**（2026-09-22 限定 ⑥）----
	#
	# 用户定稿："敌人之间不能相杀 / 不能和友军相杀"。僚机（AI，玩家队）与敌机
	# （AI）是敌对对子，但相杀演出只属于玩家 —— 它们的军刀接触走普通扫掠命中。
	# 两台都**不**标 as_player，其余前置与 ② 完全一致 —— ② 能触发、⑤ 不许触发，
	# 差异只剩"有没有玩家参与"，这就把门禁钉在唯一变量上。
	var ai_a := _make(c, "ClashAiA", 0)
	var ai_b := _make(c, "ClashAiB", 1)
	await host.get_tree().physics_frame
	_face_each_other(ai_a, ai_b, 85.0)
	await host.get_tree().physics_frame
	_arm_and_step(ai_a, ai_b)
	t.eq(ai_a.clash_count, 0, "**AI 对 AI 不触发相杀**（僚机与敌机拼刀已被阵营门禁拦下）")
	t.eq(ai_b.clash_count, 0, "...双方都不记")
	ai_a.queue_free()
	ai_b.queue_free()
	await host.get_tree().physics_frame

	c.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 3 后果

static func _effect(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var a := _make(c, "EffA", 0, null, true)
	var b := _make(c, "EffB", 1)
	await host.get_tree().physics_frame
	# 85 m：相杀圈内、命中圈外（同触发组的摆位口径）
	_face_each_other(a, b, 85.0)
	await host.get_tree().physics_frame

	# 记下相杀前的状态
	var hull_a := a.hp
	var ifield_a := a.ifield_hp
	var hull_b := b.hp
	var ifield_b := b.ifield_hp
	var pos_a := a.global_position
	var pos_b := b.global_position

	a.saber_cooldown = 0.0
	_arm_and_step(a, b)

	t.gt(a.clash_count, 0, "已触发相杀（前置条件）")

	# ---- ① **不掉血**（相杀的本体）----
	t.near(a.hp, hull_a, 0.001, "相杀**不结算伤害**：A 的血没动")
	t.near(a.ifield_hp, ifield_a, 0.001, "A 的 I 立场也没动")
	t.near(b.hp, hull_b, 0.001, "B 的血没动")
	t.near(b.ifield_hp, ifield_b, 0.001, "B 的 I 立场也没动")

	# ---- ② 双方脱锁 ----
	t.ok(a.is_unlockable(), "A 进入「不可被锁定」（对应需求的「失去锁定」）")
	t.ok(b.is_unlockable(), "B 同理")
	t.near(a.unlockable_seconds_left(), FlightBody.CLASH_UNLOCKABLE, 0.3,
		"A 的失锁剩余 ≈ CLASH_UNLOCKABLE")
	t.near(b.unlockable_seconds_left(), FlightBody.CLASH_UNLOCKABLE, 0.3, "B 同理")

	# ---- ③ 军刀态结束（不再是突进中）----
	t.not_ok(a.saber_active(), "相杀后 A 的军刀突进结束")
	t.not_ok(b.saber_active(), "相杀后 B 的军刀突进结束")

	# ---- ④ 被弹开：速度方向背离对方 ----
	#
	# ⚠️ 只断言**刚相杀那一刻的速度**，不断言"跑 20 帧之后距离更大"：
	# 相杀之后两台的军刀冷却都还在（2.5 s），但 AI 会立刻重新机动、
	# 而且这边还钉着位置 —— 跑 20 帧之后的距离取决于 AI 想干什么，
	# 不是相杀的结果。**测"弹开"就测速度**，那才是相杀写进去的东西。
	var away_a := (pos_a - pos_b).normalized()
	var v_a := a.fm.velocity
	t.gt(v_a.length(), 50.0, "A 被弹开了（速度是抛出量级，实测 %.0f m/s）" % v_a.length())
	t.gt(v_a.normalized().dot(away_a), 0.3,
		"A 的速度方向**背离** B（不是被推向 B）")

	# ---- ⑤ 记进结算 ----
	# ⚠️ `Game.saber_clashes` 按"**玩家是否参与**"计（和 `saber_hits` 同一个口径：
	# 它进的是"损耗与战果"，统计的是**玩家**做过什么，不是场上发生过什么）。
	# A 已由 `_make(..., as_player=true)` 标成玩家 —— 直接触发即可。
	a.clash_count = 0
	b.clash_count = 0
	b.team = 1
	a.saber_cooldown = 0.0
	b.saber_cooldown = 0.0
	_face_each_other(a, b, 85.0)
	await host.get_tree().physics_frame
	_arm_and_step(a, b)
	t.gt(a.clash_count, 0, "（前置）玩家侧又触发了一次相杀")
	t.gt(Game.saber_clashes, 0, "相杀计入 `Game.saber_clashes`（结算页能显示）")

	c.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 4 冷却

static func _cooldown(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var a := _make(c, "CdA", 0, null, true)
	var b := _make(c, "CdB", 1)
	await host.get_tree().physics_frame
	# 85 m：相杀圈内、命中圈外（同触发组的摆位口径）
	_face_each_other(a, b, 85.0)
	await host.get_tree().physics_frame

	a.saber_cooldown = 0.0
	_arm_and_step(a, b)
	var first := a.clash_count
	t.gt(first, 0, "第一次相杀发生了")

	# 冷却期内再冲：`try_saber()` 会被冷却直接拒掉（这正是要的行为）
	var again := a.try_saber(b)
	t.not_ok(again, "冷却期内**挥不出第二刀**（被 `saber_cooldown` 拒掉）")
	# 手工再推几帧判定，确认不会二次相杀
	for i in 6:
		a._step_saber(1.0 / 60.0)
		b._step_saber(1.0 / 60.0)
	t.eq(a.clash_count, first, "冷却期内**不会二次相杀**（防死循环）")

	# 冷却剩余：**`CLASH_COOLDOWN` 是下限、不是定值**。
	#
	# ⚠️ 这条断言原来写的是"冷却应当 ≈ CLASH_COOLDOWN（2.5）"，而实测是 3.2 ——
	# 因为 `_clash_lock_out()` 用的是
	# `saber_cooldown = maxf(saber_cooldown, CLASH_COOLDOWN)`，
	# 而**挥刀本身的冷却就是 3.2 s**（`profile.saber_interval`），比下限大。
	#
	# 这条错了很久没被发现：它调的 `clash_cooldown_left()` **当时根本不存在**，
	# 调用抛异常 ⇒ 它连同后面的断言一起被跳过 ⇒ 套件照样"全绿"。
	# （第二十四轮补上访问器之后才暴露出来。）
	t.gt(a.clash_cooldown_left(), FlightBody.CLASH_COOLDOWN - 0.01,
		"相杀后冷却**不低于** CLASH_COOLDOWN（它是下限）")
	t.near(a.clash_cooldown_left(),
		maxf(a.profile.saber_interval, FlightBody.CLASH_COOLDOWN), 0.05,
		"实际值 = max(挥刀冷却, CLASH_COOLDOWN)")
	t.ok(a.in_clash_cooldown(), "`in_clash_cooldown()` 为真")
	# 而"失锁时间"是另一条（更短），两者都要有。
	t.gt(a.unlockable_seconds_left(), 0.0, "同时处在**失锁**窗口里")
	t.lt(FlightBody.CLASH_UNLOCKABLE, FlightBody.CLASH_COOLDOWN,
		"失锁窗口必须**短于**相杀冷却（否则刚能锁上就再相杀，会死循环）")

	c.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 5 与踏板联动

static func _pedal(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	# 梅萨是量产机 ⇒ 骑得了板（玩家队那台标 as_player，限定 ⑥ 要求）
	var a := _make(c, "PedA", 0, SuitProfile.messer_m01(), true)
	await host.get_tree().physics_frame
	a.configure_pedal()
	await host.get_tree().physics_frame
	t.ok(a.has_pedal(), "梅萨骑上了板（前置条件）")

	# ⚠️ 第十九轮起这条**可达了**。第十八轮时它不可达：那时"骑板时挥不了军刀"
	# （`pedal_restricts_melee()`），而相杀要求双方都在军刀突进态 ⇒
	# 骑板者永远进不了相杀。第十九轮放开那条限制（量产机要骑板赶路，
	# 禁刀会让那六台整场近战残废）之后，这条路才真的走得通。
	#
	# 现在验证的就是**完整那条路**：两台上板 → 双方拔刀对冲 → 相杀 →
	# **两台的板都被强制卸下**（`_begin_clash()` 里调 `release_pedal()`）。
	var b := _make(c, "PedB", 1, SuitProfile.messer_m01())
	await host.get_tree().physics_frame
	b.configure_pedal()
	await host.get_tree().physics_frame
	t.ok(b.has_pedal(), "第二台也骑上了板（前置条件）")

	t.ok(a.try_saber(null), "**骑板时挥得出军刀**（第十九轮放开了这条）")
	a.abort_saber()
	# ⚠️ **两台的冷却都要清**：相杀的判据是"两边都在军刀突进态"，
	# 只清一台的话另一台进不去、相杀永远不触发（第十八轮为同一件事红过两条）。
	a.saber_cooldown = 0.0
	b.saber_cooldown = 0.0

	# 摆成"相杀圈内、命中圈外"（78 m < d ≤ 100 m）—— 唯一能成立的区间
	_face_each_other(a, b, 85.0)
	await host.get_tree().physics_frame
	_arm_and_step(a, b)

	t.gt(a.clash_count, 0, "骑板的两台也能触发相杀（前置条件）")
	t.not_ok(a.has_pedal(), "被相杀 → **A 的板被强制卸下**")
	t.not_ok(b.has_pedal(), "被相杀 → **B 的板被强制卸下**")

	# ⚠️ 脱板**不吃伤害**：`release_pedal()`（相杀走这条）与"板被打爆"是两条路。
	# 这一条把两条路分开钉住 —— 否则"相杀"就成了一种免费的伤害来源。
	t.ok(a.alive and b.alive, "两台都还活着")
	t.near(a.stagger_left(), 0.0, 0.001, "相杀脱板**不进失能**（失能只属于「板被打爆」）")
	t.near(b.stagger_left(), 0.0, 0.001, "B 同理")

	# 脱板之后军刀仍然可用（不留永久副作用）
	t.not_ok(a.pedal_restricts_melee(), "脱板之后不限制军刀")

	c.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 工具

static func _make(parent: Node3D, node_name: String, team: int,
		p: SuitProfile = null, as_player := false) -> BanditAI:
	var fb := BanditAI.new()
	fb.name = node_name
	fb.team = team
	fb.profile = p if p != null else SuitProfile.xi()
	fb.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	fb.projectile_container = parent
	# ⚠️ 2026-09-22 起 `_try_clash` 有**限定 ⑥**：相杀只属于「玩家 vs 敌机」。
	# 所以所有"要触发相杀"的测试节，玩家队那台必须 `as_player = true`；
	# 反过来，"AI 对 AI 不该触发"的守卫（见 _trigger ⑤）就**不**标。
	fb.is_player = as_player
	parent.add_child(fb)
	fb.global_position = Vector3(0.0, 3200.0, 0.0)
	# ⚠️ **不要 `set_physics_process(false)`**：相杀判定长在 `_step_saber()` 里，
	# 而它由 `_physics_process → _think → _apply_flight` 驱动 ——
	# 把 AI 停掉就等于把被测对象关掉了（本轮为此红了 16 条，
	# 而且症状是"相杀根本没触发"，看起来完全像功能没写对）。
	# 判定本身由 `_arm_and_step()` 手工推一帧，不依赖 AI 的机动运气。
	return fb


## 把两台摆成**面对面、相距 `d` 米**。
static func _face_each_other(a: BanditAI, b: BanditAI, d: float) -> void:
	var pa := Vector3(-d * 0.5, 3200.0, 0.0)
	var pb := Vector3(d * 0.5, 3200.0, 0.0)
	a.global_position = pa
	b.global_position = pb
	a.velocity = Vector3.ZERO
	b.velocity = Vector3.ZERO
	# 面向对方：a 看向 +X（b 的方向），b 看向 −X
	a.look_at(pb, Vector3.UP)
	b.look_at(pa, Vector3.UP)


## 让一台机进入军刀突进态，并**手工推进一帧相杀判定**。
##
## ## 为什么要手工推、而不是等 AI 自己飞过去
## 本轮在这里连踩两次，都是**手段**的问题，值得写下来：
##
##   ① 把两台摆在命中距离（78 m）以内 ⇒ 一进突进就 `_slash()` 命中，
##      军刀态当场结束，相杀**永远轮不到**（红了 9 条，症状像"相杀没触发"）。
##   ② 为了让它俩对冲而**每帧钉住位置** ⇒ `move_and_slide()` 会把速度吃掉，
##      而"未命中"分支又会因为位置被钉住而自己结束突进 —— 连挥都挥不出去。
##
## 结论：**测判定就测判定**。把两台摆在"相杀圈内、命中圈外"，
## 双方各自进入突进，然后直接调 `_step_saber()` 让判定跑一次。
## 这样既不依赖 AI 的机动运气，也不会被物理引擎的推挤干扰。
static func _arm_and_step(a: BanditAI, b: BanditAI) -> void:
	a.try_saber(b)
	b.try_saber(a)
	# 手工跑一帧判定（正常情况下这一帧由 `_physics_process → _apply_flight` 驱动）
	a._step_saber(1.0 / 60.0)


## 推进若干帧（把两台的**位置钉住**，避免 AI 自己机动飞走）。
##
## ⚠️ 当前只有"距离太远 → 不该触发"那条用它做背景帧；
## **不要**用它去复现"对冲相杀" —— 钉住位置会让 `move_and_slide()` 吃掉速度，
## 突进自己就结束了（本轮踩过，见 `_arm_and_step` 的注释）。
static func _hold(host: Node, a: BanditAI, b: BanditAI, d: float, frames: int) -> void:
	for i in frames:
		if is_instance_valid(a):
			a.global_position = Vector3(-d * 0.5, 3200.0, 0.0)
			a.velocity = Vector3.ZERO
			a.fm.velocity = Vector3.ZERO
		if is_instance_valid(b):
			b.global_position = Vector3(d * 0.5, 3200.0, 0.0)
			b.velocity = Vector3.ZERO
			b.fm.velocity = Vector3.ZERO
		await host.get_tree().physics_frame
