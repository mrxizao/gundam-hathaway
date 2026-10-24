class_name SuiteMultiLock
extends RefCounted
## **多目标锁定（锁定组）**（1.2.1 · 批 1 · DESIGN §4.1.7）。
##
## ## 用户要的东西，一句话
##
## 「锁定组最多 3 个槽位；每次扳机的导弹按**已稳定锁定**的成员数平分，
## 于是锁定多个目标 = **压制面更广、单点杀伤更薄**。」
##
## 这个套件把上面那句话拆成**四条可断言的东西**（对应下面六节）：
##
##   ① 锁定组的不变量：≤3 / 组 0 号是锁定对象（`target`）/ 无重复 / 全敌对 / 全存活 / 空组 ⇒ null
##      ⚠️ **轮 36 起多一条**：锁定对象**可以为空而组非空** ——
##      那时组 0 号**不是** `target`（它是"下一个顺位"）。见 `_invariants()` 里
##      「主目标被击坠」那一段的注释。
##   ② `salvo_split()` 的分配表：1→3、2→2/1、3→1/1/1，余数补给靠前的
##   ③ **K = 1 与改动前逐位相同** —— 本批最重要的一条，零回归的唯一证明点
##   ④ 发射反馈按「发」计、与 K 无关（镜头抖动不是「每次扳机一次」）
##
## 外加两条「顺手就该一起钉住」的集成检查：
##   ⑤ 真打出去时，弹**确实**分到了不同的人身上（不只看分配表）
##   ⑥ 全弹发射的 100 发同样按组分散（`_build_full_salvo_spread`）
##
## ## ⚠️ 为什么 K=1 那一条要单独一节
##
## `target` / `quality` / `locked` 这三个字段在旧版是**状态**，新版是**派生量**
## （真源在 `lock_group` 与 `_members`）。改派生量最容易出的事，是
## 「组里只有一个人时读出来跟以前不一样」—— 而全部 5 处调用点（玩家侧导弹/军刀门禁、
## AI 的 `_is_locked_by_player()`、HUD、main）都读它。所以这里不比对旧代码
##（旧代码已经不在仓库里了），而是钉住它**在行为上的可观察等价物**：
## 单成员时的分配表必须与「根本没有锁定组」那条退化路径**逐位相同**。
##
## ## ⚠️ 另一条容易漏的：K 取的是 `locked_in_group()`，不是 `lock_group.size()`
##
## 否则「长按 Tab 一口气填满 3 个名额」= 白送一次按 3 人分的齐射，
## 而「火力分散」这个代价本来是要求玩家先把三个人都跟到 LOCK 的。
## `_funnel_plan()` 的边界② 与 `_build_full_salvo_spread()` 都在钉这件事。

const ALT := 3000.0


static func run(t: T, host: Node) -> void:
	t.suite("MultiLock / 锁定组的不变量")
	await _invariants(t, host)
	t.suite("MultiLock / salvo_split 分配表")
	_split_table(t)
	t.suite("MultiLock / K=1 与改动前逐位相同")
	await _k1_equivalence(t, host)
	t.suite("MultiLock / 火力按锁定组分散（真发射）")
	await _spread(t, host)
	t.suite("MultiLock / 发射反馈按「发」计，与 K 无关")
	await _launch_feedback(t, host)
	t.suite("MultiLock / 全弹发射的 100 发也按组分散")
	await _full_salvo(t, host)


# ============================================================ 工具

## 一台可被打的机体（与 `suite_combat._new_unit()` 同构）。
##
## `is_player` / `profile` / `team` **必须在 `add_child()` 之前**设好 ——
## `FlightBody._ready()` 会读它们决定进哪个分组、加载哪个模型、血量多少。
## I 立场关掉（`ifield_max = 0`），让断言直接落在机体血上（护盾由 suite_damage 测）。
static func _new_unit(container: Node3D, team: int, pos: Vector3, hp := 400.0,
		as_player := false) -> FlightBody:
	var u := FlightBody.new()
	u.team = team
	u.is_player = as_player
	u.profile = SuitProfile.penelope() if team == 0 else SuitProfile.xi()
	u.display_name = "T%d" % team
	u.projectile_container = container
	container.add_child(u)
	u.global_position = pos
	u.max_hp = hp
	u.hp = hp
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	u.fm.speed = 260.0
	u.fm.throttle = 0.78
	u.fm.align_velocity(u.forward())
	return u


static func _frames(host: Node, n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame


## 一台**只在发射时给反馈**的机体：把 `_on_funnel_launch()` 覆写成计数器。
##
## 这是 `PlayerController._on_funnel_launch()` 的替身（那边是
## `camera.add_launch_shake(...)`）。用它就能把「镜头每次扳机被推了几下」
## 变成一个**能断言的整数**，不必真的架一台相机。
class CountingBody extends FlightBody:
	var launches := 0

	func _on_funnel_launch() -> void:
		launches += 1


## 未类型化 → `Array[FlightBody]`。
##
## ⚠️ 必须显式转：`LockOnSystem.lock_group` 是 `Array[FlightBody]`，
## 直接赋一个字面量数组，在元素类型对不上时会（在运行时）插入 null
## 而不是报错 —— 于是后面 `locked_in_group()` 会拿着 null 去问 `_tier_of()`。
static func _typed(items: Array) -> Array[FlightBody]:
	var out: Array[FlightBody] = []
	for it in items:
		out.append(it as FlightBody)
	return out


## 未类型化 int 数组（`Array[int]` 与字面量数组的 `==` 我不想赌）。
static func _plain(a: Array) -> Array:
	var out := []
	for v: int in a:
		out.append(v)
	return out


## 把锁定组直接摆成「**这些人都已经稳定锁定**」。
##
## ⚠️ 为什么直接写状态、而不去等 0.85 s 的真实累积：
## 本套件要验的是**组与分配**，不是质量条的累积速度（那在 `suite_combat` 里）。
## 把 `locked_in_group()` 的输入直接摆好，测试才确定、快、且只测一件事。
static func _pin_group(lk: LockOnSystem, members: Array) -> void:
	var g: Array[FlightBody] = []
	for m in members:
		var fb := m as FlightBody
		g.append(fb)
		lk._set_q_of(fb, 1.0)
		lk._set_tier_of(fb, LockOnSystem.Tier.LOCK)
	lk.lock_group = g


## `from_idx` 之后新进容器的、**自己打出去的**那些弹各自瞄着谁。
##
## 用「调用前后数一次 child 数」定位这一梭（与 `suite_round15` 同一套写法，
## 理由见 `PlayerController._salvo_from` 的注释）。
static func _targets_from(c: Node, shooter: FlightBody, from_idx: int) -> Array:
	var out := []
	var kids := c.get_children()
	for i in range(from_idx, kids.size()):
		var m := kids[i] as Missile
		if m != null and m.shooter == shooter:
			out.append(m.target)
	return out


static func _count_of(list: Array, who: Node3D) -> int:
	var n := 0
	for v in list:
		if v == who:
			n += 1
	return n


# ============================================================ ① 不变量

static func _invariants(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	# 四架在正前方（宽锥之内）的敌机，距离依次拉开 ⇒ 候选表的先后是确定的
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 400.0, true)
	var e1 := _new_unit(c, 1, Vector3(0, ALT, -2000.0))
	var e2 := _new_unit(c, 1, Vector3(0, ALT, -3000.0))
	var e3 := _new_unit(c, 1, Vector3(0, ALT, -4000.0))
	var e4 := _new_unit(c, 1, Vector3(0, ALT, -5000.0))
	# **射程内、但在宽锥（55°）之外**：永不进候选表 ⇒ 层级永远停在 NONE。
	# 这是「没建立航迹就加不进组」那条门槛唯一**确定**的构造方式
	#（靠「还没飞够 0.85 秒」去构造，就是在测「我等了几帧」）。
	var side := _new_unit(c, 1, Vector3(3000.0, ALT, 0.0))
	# 同一个阵营：不该被锁
	var buddy := _new_unit(c, 0, Vector3(0, ALT, -2500.0))

	var lk := LockOnSystem.new()
	lk.lock_time = 0.05          # 3 帧就能锁上；测试不必等真实的 0.85 s
	host.add_child(lk)
	lk.setup(me)

	# ---- 空组的定义 ----
	t.eq(LockOnSystem.MAX_LOCKS, 3, "同时锁定的上限就是 3 个（用户指定）")
	t.ok(lk.lock_group.is_empty(), "初始锁定组为空")
	t.eq(lk.target, null, "空组 ⇒ 主目标为 null")
	t.eq(lk.tier(), LockOnSystem.Tier.NONE, "空组 ⇒ 层级 NONE")
	t.not_ok(lk.locked, "空组 ⇒ 未锁定")
	t.not_ok(lk.is_locked(), "空组 ⇒ is_locked() 也是假")
	t.ok(lk.locked_in_group().is_empty(), "空组 ⇒ 能分到火力的成员数为 0")
	t.eq(lk.group_index(me), -1, "不在组里的目标 ⇒ group_index() 返回 -1")

	# ---- 自动接战：只进一个人（不做自动补位）----
	await _frames(host, 3)
	t.eq(lk.lock_group.size(), 1, "自动接战只把**一个**人放进组（不做自动补位）")
	t.eq(lk.target, lk.lock_group[0], "元素 0 恒等于 target（target 是派生量）")
	t.ok(lk.is_main(lk.target), "is_main() 与元素 0 一致")
	t.eq(lk.target, e1, "接战的是正前方最近的敌机")
	t.eq(lk.group_index(e1), 0, "主目标的槽位是 0")
	t.eq(lk.quality_of(e1), lk.quality, "quality_of(主目标) 与派生量 quality 是同一个数")

	# ---- 门槛：只有**已经建立航迹**（TRACK）的敌人能被加进来 ----
	t.eq(side.team, 1, "（前提）side 是敌方")
	t.lt(me.global_position.distance_to(side.global_position), lk.seeker_range,
		"（前提）side 在锁定射程之内 —— 挡住它的不是距离")
	t.eq(lk.tier_of(side), LockOnSystem.Tier.NONE,
		"宽锥之外的敌机不在候选表里 ⇒ 层级永远是 NONE")
	t.not_ok(lk.add_lock(side),
		"**没建立航迹的敌人加不进锁定组**（锁定是要挣的，不是按一下白送）")
	t.not_ok(lk.lock_group.has(side), "……而且它真的不在组里")

	# ---- 门槛：只有敌对目标 ----
	t.not_ok(lk.add_lock(buddy), "友军加不进锁定组（全敌对不变量）")
	t.not_ok(lk.lock_group.has(buddy), "……而且它真的不在组里")

	# ---- 加人成功 + 防「一口气填满」----
	t.ok(lk.add_lock(e2), "已经建立航迹的敌人可以加入锁定组")
	t.eq(lk.lock_group.size(), 2, "组内两人")
	t.eq(lk.target, e1, "**加人不改主目标**（元素 0 没动）")
	t.not_ok(lk.add_lock(e3), "加入后有冷却 ⇒ 不能一口气把 3 个名额填满")

	await _frames(host, 30)       # 0.5 s ≫ ADD_LOCK_COOLDOWN
	t.not_ok(lk.add_lock(e2), "同一个目标不会进组两次（无重复不变量）")
	t.eq(lk.lock_group.size(), 2, "重复请求不改组大小")
	t.ok(lk.add_lock(e3), "换一个没进组的则能加进去（不是冷却没到就永远哑了）")
	t.eq(lk.lock_group.size(), 3, "组内三人 = 上限")
	t.not_ok(lk.add_lock(e4), "组满之后第 4 个加不进来（≤3 不变量）")
	t.eq(lk.lock_group.size(), LockOnSystem.MAX_LOCKS, "组大小停在 MAX_LOCKS")
	t.not_ok(lk.add_lock_nearest(), "组满时 add_lock_nearest() 也加不进来")

	# ---- 组本身的四条不变量 ----
	_sweep(t, lk, me, "加满之后")
	t.eq(lk.lock_group[0], e1, "元素 0 仍是 e1（加人不会把主目标挤走）")
	t.ok(lk.locked, "三个成员都锁上了 ⇒ 主目标是稳定锁定层")
	t.eq(lk.locked_in_group().size(), 3, "三个成员都已稳定锁定（火力会按 3 个人分）")
	t.eq(lk.tier_of(e2), LockOnSystem.Tier.LOCK, "2 号的层级是**独立**的（每个成员各自一条质量条）")
	t.eq(lk.tier_of(e3), LockOnSystem.Tier.LOCK, "3 号同理")

	# ---- 被击坠 ⇒ 只移出**那一个**（旧版是「整个锁定作废」）----
	e2.take_damage(9999.0, me)
	t.not_ok(e2.alive, "（前提）e2 被击坠")
	await _frames(host, 3)
	t.not_ok(lk.lock_group.has(e2), "被击坠的成员从锁定组里移出")
	t.eq(lk.lock_group.size(), 2, "组里剩两人（不是整个组清空）")
	t.eq(lk.target, e1, "移出的不是主目标 ⇒ 主目标不变")

	# ---- 主目标被击坠 ⇒ **不补位**（轮 36 改口径）----
	#
	# ⚠️ 这一段在本轮**改了口径**。旧断言是「2 号顺位补成主目标」，
	# 而那正是用户点名要禁掉的"自动切换锁定对象"：
	#     「锁定系统重修，除非玩家手动切换锁定，不然不会自动切换锁定对象」。
	#
	# 新口径：组内其余成员与它们的**进度一个都不动**，只是**锁定对象变空**；
	# 玩家按一下 Tab（`cycle_target()`）就把队首顶上来 —— 因为进度是现成的，
	# 切过去是**瞬间**的，不必重锁一遍。
	e1.take_damage(9999.0, me)
	await _frames(host, 3)
	t.eq(lk.lock_group.size(), 1, "主目标被击坠 ⇒ 组里剩一人（其余成员不跟着掉）")
	t.eq(lk.target, null, "**不自动补位**：锁定对象变成空（轮 36 的需求）")
	t.not_ok(lk.locked, "没有锁定对象 ⇒ locked 为假（导弹 / 军刀门禁跟着关）")
	t.eq(lk.lock_group[0], e3, "组里剩下的是 e3 —— 成员与它的进度都留着")
	t.eq(lk.tier_of(e3), LockOnSystem.Tier.LOCK,
		"e3 的层级仍是 LOCK（没有因为「没人看它」就掉档）")
	t.not_ok(lk.is_main(e3), "e3 在组里、却**不是**锁定对象（is_main 不再等于「组 0 号」）")
	# 玩家**亲手**按一下 Tab ⇒ 队首那个立刻顶上
	lk.cycle_target()
	t.eq(lk.target, e3, "按一下 Tab ⇒ 队首的 e3 立刻成为锁定对象")
	t.eq(lk.lock_group.size(), 1, "……而且组没被清（切过去是瞬间的，不必重锁）")
	t.ok(lk.is_main(e3), "此时 is_main() 才为真")
	t.ok(lk.locked, "……并且立刻就是稳定锁定（进度是现成的）")

	# ---- 全部失效 ⇒ 空组 ⇒ null ----
	e3.take_damage(9999.0, me)
	e4.take_damage(9999.0, me)
	await _frames(host, 3)
	t.ok(lk.lock_group.is_empty(), "全部成员失效 ⇒ 组空")
	t.eq(lk.target, null, "空组 ⇒ target 为 null")
	t.not_ok(lk.locked, "空组 ⇒ 未锁定")
	t.eq(lk.tier(), LockOnSystem.Tier.NONE, "空组 ⇒ 层级 NONE")

	# ⚠️ 这三条是**写这个套件时揪出来的一个真 BUG 的回归门**，别删。
	#
	# 真因不在 `_validate_group()`，在 `_refresh_candidates()` 末尾那段
	# 「鼠标选中的目标也可能不在宽锥里」的补录：它当时只查
	# `is_instance_valid` / `is_unlockable` / 射程，**没查 `alive`**。
	# 而候选表同时是**自动接战的取人头**（`_set_main(candidates[0])`），
	# 且 `_refresh_candidates()` 排在 `_validate_group()` **前面** ——
	# 于是主目标爆掉的那一帧它还是个有效的 `target`，会被塞回候选表，
	# 下一帧又被移出组、再被塞回……**锁定框永远停在一具残骸上，组永远清不空**。
	#
	# 生产路径上 `FlightBody.destroy()` 会先同步调 `Game.forget_locks_of(self)`，
	# 所以这个洞平时不显形（本套件造的是**没注册**的 `LockOnSystem`，
	# 与 `suite_combat` 同一种构造）—— 但「组内全存活」这条不变量
	# 不该依赖「外面有没有人帮你清」。
	t.eq(lk.candidates.size(), 0,
		"候选表为空（场上只剩宽锥之外的那架敌机）")
	t.not_ok(lk.candidates.has(e3), "被击坠的主目标**不会被塞回候选表**（残骸不该被接战）")
	t.not_ok(lk.candidates.has(e4), "被击坠的 3 号同理")

	lk.free()
	c.free()
	await _frames(host, 2)
	Game.reset()


## 组本身的四条不变量：≤3 / 无重复 / 全敌对 / 全存活。
static func _sweep(t: T, lk: LockOnSystem, me: FlightBody, when: String) -> void:
	t.ok(lk.lock_group.size() <= LockOnSystem.MAX_LOCKS, "%s：组大小 ≤ MAX_LOCKS" % when)
	var seen := {}
	for fb: FlightBody in lk.lock_group:
		t.ok(fb.alive, "%s：组内成员都活着（全存活不变量）" % when)
		t.ok(fb.is_hostile_to(me), "%s：组内成员都是敌对目标（全敌对不变量）" % when)
		t.ok(not seen.has(fb), "%s：组内无重复（%s）" % [when, fb.display_name])
		seen[fb] = true
	t.eq(seen.size(), lk.lock_group.size(), "%s：去重后的个数 = 组大小" % when)


# ============================================================ ② 分配表

## `salvo_split()` 是**纯静态函数**：不依赖场景、不依赖帧 —— 所以这一节是同步的。
##
## 分配表的形状 = 需求里「火力分散」的**全部数学**：
##   3 发打一个目标 ⇒ 近炸引信有 3 次命中机会、覆盖一片；
##   1 发打一个目标 ⇒ 只有 1 次机会。
## 总弹量不变 ⇒ 单位目标的期望伤害降为 1/K 量级。**不需要再额外加惩罚**
##（再加一层，K=3 就永远不划算 = 这个机制白做）。
static func _split_table(t: T) -> void:
	t.eq(_plain(LockOnSystem.salvo_split(3, 1)), [3], "K=1 → 3 发全给主目标（现状，零回归）")
	t.eq(_plain(LockOnSystem.salvo_split(3, 2)), [2, 1], "K=2 → 2 / 1")
	t.eq(_plain(LockOnSystem.salvo_split(3, 3)), [1, 1, 1], "K=3 → 1 / 1 / 1")
	t.eq(_plain(LockOnSystem.salvo_split(100, 2)), [50, 50], "100 发按 2 人分 → 50 / 50")
	t.eq(_plain(LockOnSystem.salvo_split(100, 3)), [34, 33, 33],
		"100 发按 3 人分 → 34 / 33 / 33（余数补给靠前的）")
	t.eq(_plain(LockOnSystem.salvo_split(5, 3)), [2, 2, 1], "5 发按 3 人分 → 2 / 2 / 1")
	t.eq(_plain(LockOnSystem.salvo_split(1, 3)), [1, 0, 0],
		"余额不足时照样平分，分到 0 发的成员跳过（沿用旧版「把剩下的打完，不制造死角」）")
	t.eq(_plain(LockOnSystem.salvo_split(4, 0)), [], "K=0 → 空表（不崩）")
	t.eq(_plain(LockOnSystem.salvo_split(4, -1)), [], "K<0 → 空表（不崩）")

	# ---- 跨全表的不变量：总额守恒 / 槽位数 = K / 极差 ≤ 1 / 余数在前 ----
	for k: int in [1, 2, 3, 4]:
		for total: int in [3, 7, 100]:
			var parts := LockOnSystem.salvo_split(total, k)
			var sum := 0
			var mx := 0
			var mn := 999999
			for v: int in parts:
				sum += v
				mx = maxi(mx, v)
				mn = mini(mn, v)
			t.eq(parts.size(), k, "salvo_split(%d, %d) 槽位数 = K" % [total, k])
			t.eq(sum, total,
				"salvo_split(%d, %d) 总额守恒（火力分散只改分配、不改总弹量）" % [total, k])
			t.ok(mx - mn <= 1, "salvo_split(%d, %d) 极差 ≤ 1（真的是平分）" % [total, k])
			t.ok(parts[k - 1] <= parts[0],
				"salvo_split(%d, %d) 余数补给**靠前的**（顺序 = 离机头最近，不能随机）"
					% [total, k])


# ============================================================ ③ K=1 等价

static func _k1_equivalence(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 400.0, true)
	var foe := _new_unit(c, 1, Vector3(0, ALT, -2000.0))

	var lk := LockOnSystem.new()
	host.add_child(lk)
	lk.setup(me)
	lk.set_physics_process(false)     # 组的状态由测试自己摆，别让物理帧改它
	Game.register_lock(me, lk)

	me.funnel_count = 30
	me.funnel_cooldown = 0.0
	var shots := SuitProfile.MISSILE_PER_SHOT

	# ---- ① 没有锁定组：AI 侧 / 拦截弹 / 没注册火控的机体 ----
	var plan_none: Array = me._funnel_plan(foe)
	t.eq(plan_none.size(), 1, "没有锁定组 ⇒ 分配表只有一项")
	t.eq(plan_none[0]["unit"], foe, "……而且全给 primary（与改动前逐位相同）")
	t.eq(int(plan_none[0]["shots"]), shots, "……发数是完整的一梭（%d 发）" % shots)

	# ---- ② 组里有个人，但它还没锁上（层级停在 TRACK）----
	lk.lock_group = _typed([foe])
	lk._set_q_of(foe, 0.5)
	lk._set_tier_of(foe, LockOnSystem.Tier.TRACK)
	t.not_ok(lk.locked_in_group().has(foe), "（前提）它还没到 LOCK 层")
	var plan_track: Array = me._funnel_plan(foe)
	t.eq(plan_track.size(), 1, "组里没人锁上 ⇒ 仍然只有一项")
	t.eq(plan_track[0]["unit"], foe,
		"……仍然全给 primary（长按 Tab 白嫖一次齐射这条路被堵死）")

	# ---- ③ 一个成员、已稳定锁定 = K=1 ----
	_pin_group(lk, [foe])
	t.eq(lk.locked_in_group().size(), 1, "（前提）组里只有一个人稳定锁定")
	var plan_k1: Array = me._funnel_plan(foe)
	t.eq(plan_k1.size(), 1, "K=1 ⇒ 分配表只有一项")
	t.eq(plan_k1[0]["unit"], foe, "K=1 ⇒ 全部给主目标")
	t.eq(int(plan_k1[0]["shots"]), shots, "K=1 ⇒ 发数不变")
	t.eq(plan_k1, plan_none,
		"**K=1 的分配表与「没有锁定组」的那张逐位相同** —— 这就是零回归的落点")

	# ---- ④ 真发射也算一遍（不是只看分配表）----
	var n0 := c.get_child_count()
	me.funnel_cooldown = 0.0
	t.ok(me.fire_funnel(foe), "K=1 打得出去")
	var hits := _targets_from(c, me, n0)
	t.eq(hits.size(), shots, "一梭 %d 发" % shots)
	t.eq(_count_of(hits, foe), shots, "**每一发都瞄同一个目标**（旧行为，不是按组分散）")

	lk.free()
	c.free()
	await _frames(host, 2)
	Game.reset()


# ============================================================ ⑤ 真发射分散

static func _spread(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 400.0, true)
	# 第二台**不注册火控**的机体：用来验证「没有锁定组」的退化路径（边界①）
	var solo := _new_unit(c, 0, Vector3(0, ALT, 0))
	var e1 := _new_unit(c, 1, Vector3(0, ALT, -2000.0))
	var e2 := _new_unit(c, 1, Vector3(0, ALT, -3000.0))
	var e3 := _new_unit(c, 1, Vector3(0, ALT, -4000.0))

	var lk := LockOnSystem.new()
	host.add_child(lk)
	lk.setup(me)
	lk.set_physics_process(false)
	Game.register_lock(me, lk)

	var shots := SuitProfile.MISSILE_PER_SHOT
	var mark := 0

	# ---- 边界①：没有锁定组 ⇒ 全给 primary ----
	mark = c.get_child_count()
	t.ok(solo.fire_funnel(e1), "没有火控的机体照样能打（分配退化）")
	var none_hits := _targets_from(c, solo, mark)
	t.eq(none_hits.size(), shots, "还是 %d 发" % shots)
	t.eq(_count_of(none_hits, e1), shots, "**全给 primary**（没有锁定组 ⇒ 与改动前逐位相同）")

	# ---- K = 1 ----
	_pin_group(lk, [e1])
	me.funnel_count = 60
	me.funnel_cooldown = 0.0
	mark = c.get_child_count()
	t.ok(me.fire_funnel(e1), "K=1 打得出去")
	var k1 := _targets_from(c, me, mark)
	t.eq(k1.size(), shots, "K=1：一次扳机还是 %d 发（总弹量不变）" % shots)
	t.eq(_count_of(k1, e1), shots, "K=1：%d 发全给主目标" % shots)
	t.eq(_count_of(k1, e2), 0, "K=1：别人一发都拿不到")

	# ---- K = 2 ----
	_pin_group(lk, [e1, e2])
	me.funnel_cooldown = 0.0
	mark = c.get_child_count()
	t.ok(me.fire_funnel(e1), "K=2 打得出去")
	var k2 := _targets_from(c, me, mark)
	t.eq(k2.size(), shots, "K=2：还是 %d 发（总弹量不变）" % shots)
	t.eq(_count_of(k2, e1), 2, "K=2：主目标 2 发（余数补给靠前的）")
	t.eq(_count_of(k2, e2), 1, "K=2：2 号 1 发")

	# ---- K = 3 ----
	_pin_group(lk, [e1, e2, e3])
	me.funnel_cooldown = 0.0
	mark = c.get_child_count()
	t.ok(me.fire_funnel(e1), "K=3 打得出去")
	var k3 := _targets_from(c, me, mark)
	t.eq(k3.size(), shots, "K=3：还是 %d 发（总弹量不变）" % shots)
	t.eq(_count_of(k3, e1), 1, "K=3：主目标只拿 1 发（**单点杀伤变薄**）")
	t.eq(_count_of(k3, e2), 1, "K=3：2 号 1 发")
	t.eq(_count_of(k3, e3), 1, "K=3：3 号 1 发")
	t.eq(_count_of(k3, e1) + _count_of(k3, e2) + _count_of(k3, e3), shots,
		"K=3：三发不重不漏，正好一梭")

	# ---- 边界②：三个人在组里，但只有一个锁上 ⇒ 全给那一个 ----
	lk.lock_group = _typed([e1, e2, e3])
	lk._set_q_of(e1, 1.0)
	lk._set_tier_of(e1, LockOnSystem.Tier.LOCK)
	lk._set_q_of(e2, 0.4)
	lk._set_tier_of(e2, LockOnSystem.Tier.TRACK)
	lk._set_q_of(e3, 0.4)
	lk._set_tier_of(e3, LockOnSystem.Tier.TRACK)
	t.eq(lk.lock_group.size(), 3, "（前提）组里有三个人")
	t.eq(lk.locked_in_group().size(), 1, "（前提）只有一个人稳定锁定")
	me.funnel_cooldown = 0.0
	mark = c.get_child_count()
	t.ok(me.fire_funnel(e1), "这种情况也打得出去")
	var partial := _targets_from(c, me, mark)
	t.eq(_count_of(partial, e1), shots,
		"**K 取的是「已稳定锁定」的成员数，不是组大小** —— 刚加进来还没锁上的不配分弹")
	t.eq(_count_of(partial, e2), 0, "……2 号一发都没有")
	t.eq(_count_of(partial, e3), 0, "……3 号一发都没有")

	lk.free()
	c.free()
	await _frames(host, 2)
	Game.reset()


# ============================================================ ④ 发射反馈

## 「发射抖动与 K 无关」。
##
## 起因：`_on_funnel_launch()` 曾经是**每次扳机一次**（三发同帧出去、只抖一下），
## 于是「扳机感」和实际发射的数量脱节（DESIGN §4.10.1 缺口 1）；
## 现在它是**每一发离架调一次**。这条性质在改成多目标之后必须**保持不变** ——
## 否则锁定的人一多，镜头抖动就会突然变轻（或变重），
## 而玩家完全看不出「为什么这次开火没感觉」。
static func _launch_feedback(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var body := CountingBody.new()
	body.team = 0
	body.is_player = true
	body.profile = SuitProfile.penelope()
	body.display_name = "C0"
	body.projectile_container = c
	c.add_child(body)
	body.global_position = Vector3(0, ALT, 0)
	body.max_hp = 400.0
	body.hp = 400.0
	body.ifield_max = 0.0
	body.ifield_hp = 0.0
	body.fm.speed = 260.0
	body.fm.throttle = 0.78
	body.fm.align_velocity(body.forward())
	# 位置由测试摆：跑起物理帧它就会飞走，而这条测的是「扳机与反馈的对应关系」
	body.set_physics_process(false)

	var e1 := _new_unit(c, 1, Vector3(0, ALT, -2000.0))
	var e2 := _new_unit(c, 1, Vector3(0, ALT, -3000.0))
	var e3 := _new_unit(c, 1, Vector3(0, ALT, -4000.0))

	var lk := LockOnSystem.new()
	host.add_child(lk)
	lk.setup(body)
	lk.set_physics_process(false)
	Game.register_lock(body, lk)

	var shots := SuitProfile.MISSILE_PER_SHOT

	# ---- K = 1 ----
	_pin_group(lk, [e1])
	body.funnel_count = 60
	body.funnel_cooldown = 0.0
	var ammo_before := body.funnel_count
	t.ok(body.fire_funnel(e1), "K=1 打得出去")
	var n1 := body.launches
	t.eq(n1, shots,
		"K=1：离架反馈被调 %d 次 = 一梭的发数（**每发一次**，不是每扳机一次）" % n1)
	t.eq(ammo_before - body.funnel_count, shots, "……弹药也按发扣")

	# ---- K = 2 ----
	_pin_group(lk, [e1, e2])
	body.funnel_cooldown = 0.0
	t.ok(body.fire_funnel(e1), "K=2 打得出去")
	var n2 := body.launches - n1
	t.eq(n2, shots, "K=2：反馈次数同样是 %d" % n2)

	# ---- K = 3 ----
	_pin_group(lk, [e1, e2, e3])
	body.funnel_cooldown = 0.0
	t.ok(body.fire_funnel(e1), "K=3 打得出去")
	var n3 := body.launches - n1 - n2
	t.eq(n3, shots, "K=3：反馈次数同样是 %d" % n3)

	t.eq(n1, n2, "K=1 与 K=2 的离架反馈次数相同")
	t.eq(n2, n3, "K=2 与 K=3 的离架反馈次数相同")
	t.eq(n3, shots,
		"**发射抖动与 K 无关**：每次扳机镜头被推 %d 下，与锁了几个人无关" % n3)

	# ---- 三次扳机的账：总弹量不变、单点越来越薄 ----
	var all := _targets_from(c, body, 0)
	t.eq(all.size(), shots * 3, "三次扳机共 %d 发（每次都是一梭）" % (shots * 3))
	t.eq(_count_of(all, e1), 3 + 2 + 1, "e1 累计 6 发 = 3(K=1) + 2(K=2) + 1(K=3)")
	t.eq(_count_of(all, e2), 1 + 1, "e2 累计 2 发 = 1(K=2) + 1(K=3)")
	t.eq(_count_of(all, e3), 1, "e3 累计 1 发 = 只出现在 K=3 那一梭")

	lk.free()
	c.free()
	await _frames(host, 2)
	Game.reset()


# ============================================================ ⑥ 全弹发射

## 100 发也是「一次扳机」，所以同样按组分散 —— 而且**分配表在按下时就一次算完**。
##
## ⚠️ 为什么「一次算完」要专门钉：逐发按当时发现的组重算的话，
## 「组中途掉了一个人」会把分配抖散 —— 前 30 发按 3 人分、后 70 发按 2 人分，
## 而且总数还对不上 100。表算一次、发的时候按序号查，才是确定的。
static func _full_salvo(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.team = 0
	pc.is_player = true
	pc.profile = SuitProfile.penelope()
	pc.projectile_container = c
	c.add_child(pc)
	pc.global_position = Vector3(0, ALT, 0)
	pc.fm.speed = 260.0
	pc.fm.throttle = 0.78
	pc.fm.align_velocity(pc.forward())
	# 裸实例没有 camera / 输入 ⇒ `_think()` 跑不了。这一节只测全弹发射的分配。
	pc.set_physics_process(false)

	var e1 := _new_unit(c, 1, Vector3(0, ALT, -2000.0))
	var e2 := _new_unit(c, 1, Vector3(0, ALT, -3000.0))
	var e3 := _new_unit(c, 1, Vector3(0, ALT, -4000.0))

	var lk := LockOnSystem.new()
	host.add_child(lk)
	lk.setup(pc)
	lk.set_physics_process(false)
	pc.lock = lk

	var total := PlayerController.FULL_SALVO_COUNT
	var mark := 0
	var guard := 0
	t.eq(total, 100, "（前提）全弹发射是 100 发")

	# ---- K = 3 ----
	_pin_group(lk, [e1, e2, e3])
	pc.funnel_count = 200
	t.ok(pc.fire_full_salvo(e1), "3 个已稳定锁定成员时全弹发射放得出去")
	t.eq(pc._full_salvo_spread.size(), 3, "分配表有 3 项（一人一项）")
	t.eq(_plain(pc._full_salvo_parts), [34, 33, 33], "100 发按 3 人平分 → 34 / 33 / 33")
	t.gt(float(int(pc.get("_full_salvo_left"))), 0.0, "分批涌出的余量还在（不是一帧全出）")

	# ⚠️ 表算一次就定死：把组改成 1 人，已经算好的分配**不该**跟着变
	_pin_group(lk, [e1])
	t.eq(_plain(pc._full_salvo_parts), [34, 33, 33],
		"组中途变化**不会**把已经算好的分配抖散（表一次算完、发的时候按序号查）")

	guard = 0
	while int(pc.get("_full_salvo_left")) > 0 and guard < 400:
		pc.call("_tick_full_salvo", 0.05)
		guard += 1
	t.eq(int(pc.get("_full_salvo_left")), 0, "分批放完（100 发 / 每批 5 发）")
	var all := _targets_from(c, pc, 0)
	t.eq(all.size(), total, "容器里真的多了 %d 发" % total)
	t.eq(_count_of(all, e1), 34, "主目标 34 发（余数补给靠前的）")
	t.eq(_count_of(all, e2), 33, "2 号 33 发")
	t.eq(_count_of(all, e3), 33, "3 号 33 发")
	t.eq(_count_of(all, e1) + _count_of(all, e2) + _count_of(all, e3), total,
		"总额守恒：火力分散只改分配，不改总弹量")

	# ---- K = 1：与改动前逐位相同（表里只有一项，全给主目标）----
	pc.full_salvo_cooldown = 0.0
	pc.funnel_count = 200
	_pin_group(lk, [e1])
	mark = c.get_child_count()
	t.ok(pc.fire_full_salvo(e1), "K=1 全弹发射放得出去")
	t.eq(pc._full_salvo_spread.size(), 1, "K=1：分配表只有一项")
	t.eq(_plain(pc._full_salvo_parts), [total], "K=1：100 发全给主目标（旧行为）")
	t.eq(pc._full_salvo_target_for(0), e1, "第 0 发打主目标")
	t.eq(pc._full_salvo_target_for(total - 1), e1, "最后一发也打主目标")
	t.eq(pc._full_salvo_target_for(total), e1, "越界的序号回落到主目标（不崩、不错人）")

	guard = 0
	while int(pc.get("_full_salvo_left")) > 0 and guard < 400:
		pc.call("_tick_full_salvo", 0.05)
		guard += 1
	var k1 := _targets_from(c, pc, mark)
	t.eq(_count_of(k1, e1), total, "K=1：100 发全落在主目标身上")
	t.eq(_count_of(k1, e2) + _count_of(k1, e3), 0, "K=1：别人一发都没有")

	# ---- K = 2：按序号查表，前 50 发主目标、后 50 发 2 号 ----
	pc.full_salvo_cooldown = 0.0
	pc.funnel_count = 200
	_pin_group(lk, [e1, e2])
	mark = c.get_child_count()
	t.ok(pc.fire_full_salvo(e1), "K=2 全弹发射放得出去")
	t.eq(_plain(pc._full_salvo_parts), [50, 50], "K=2：100 发按 50 / 50 分")
	t.eq(pc._full_salvo_target_for(0), e1, "第 0 发 → 主目标")
	t.eq(pc._full_salvo_target_for(49), e1, "第 49 发 → 主目标（前 50 发那一份）")
	t.eq(pc._full_salvo_target_for(50), e2, "第 50 发 → 2 号（序号查表，不是按发现算）")
	t.eq(pc._full_salvo_target_for(99), e2, "最后一发 → 2 号")
	guard = 0
	while int(pc.get("_full_salvo_left")) > 0 and guard < 400:
		pc.call("_tick_full_salvo", 0.05)
		guard += 1
	var k2 := _targets_from(c, pc, mark)
	t.eq(_count_of(k2, e1), 50, "K=2：主目标吃到 50 发")
	t.eq(_count_of(k2, e2), 50, "K=2：2 号吃到 50 发")

	# ---- 组里没人锁上（刚从拦截模式切过来）：退化回「全给 primary」 ----
	pc.full_salvo_cooldown = 0.0
	pc.funnel_count = 200
	lk.lock_group = _typed([e1, e2])
	lk._set_q_of(e1, 0.4)
	lk._set_tier_of(e1, LockOnSystem.Tier.TRACK)
	lk._set_q_of(e2, 0.4)
	lk._set_tier_of(e2, LockOnSystem.Tier.TRACK)
	t.ok(lk.locked_in_group().is_empty(), "（前提）组里一个人都没锁上")
	mark = c.get_child_count()
	t.ok(pc.fire_full_salvo(e1), "这种状态也放得出去")
	t.eq(pc._full_salvo_spread.size(), 1, "没锁上 ⇒ 分配表退化成一项")
	t.eq(_plain(pc._full_salvo_parts), [total],
		"**K 取的是「已稳定锁定」的成员数** —— 没锁上就 100 发全给 primary")
	guard = 0
	while int(pc.get("_full_salvo_left")) > 0 and guard < 400:
		pc.call("_tick_full_salvo", 0.05)
		guard += 1
	var deg := _targets_from(c, pc, mark)
	t.eq(_count_of(deg, e1), total, "退化路径：100 发全落在 primary 身上")

	lk.free()
	c.free()
	await _frames(host, 2)
	Game.reset()
