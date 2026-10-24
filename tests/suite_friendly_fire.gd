class_name SuiteFriendlyFire
extends RefCounted
## **友军误伤**（1.2.1 · DESIGN §3.1）。
##
## 用户实测报的两条：「所以导致了产生友军使用军刀的时候自己使用军刀会和友军相杀」、
## 「而且为啥有自相残杀的」。
##
## ## 读码查出的真因
##
## `Projectile._physics_process()` 只 `pq.exclude = [shooter]`，**完全没有阵营概念**；
## 而 `FlightBody.take_damage()`（所有伤害的唯一入口）里也没有任何友军闸门。
## 整个工程的阵营判定只有 `is_hostile_to()` 一个真源，但它**只被用在"选目标"这条链上**
##（`live_hostiles_of` → 锁定 / AI / 军刀扫掠）—— **"伤害落地"这条链上一次都没用过它**。
##
## 所以修法是两道闸门：`take_damage()` 的白名单式闸门 + `Projectile` 命中友军只出 FX。
## 本套件把两道都钉住，**并且同时**验证"闸门没有把正常伤害一起挡掉" ——
## 那一侧的回归比"友军不掉血"更危险（症状是"打不动敌人了"，而且很难归因到闸门）。
##
## ⚠️ 文件名按**主题**命名，不按轮次：本仓库有并行会话，两侧都按轮次占号时撞过一次
##（一个套件被同名文件整个覆盖，而 runner 照样绿）。

const GATE := "FriendlyFire / 友军伤害闸门（take_damage）"
const PROJ := "FriendlyFire / 弹丸命中友军只出 FX，不结算伤害"
const CONTROL := "FriendlyFire / 白名单：敌人 / null 来源 / 自己 照常受伤"
const LEDGER := "FriendlyFire / 阵营记账（拦截计数 + 僚机损失，2026-09-22）"


static func run(t: T, host: Node) -> void:
	t.suite(GATE)
	await _gate(t, host)
	t.suite(PROJ)
	await _projectile(t, host)
	t.suite(CONTROL)
	await _control(t, host)
	t.suite(LEDGER)
	await _ledger(t, host)


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


## 单位**自己的**血 + 护盾（不含踏板）。
static func _pool(u: FlightBody) -> float:
	return u.hp + u.ifield_hp


## 单位 **+ 它那块板**（"伤害到底落在哪儿了"的完整口径）。
##
## 为什么要把板算上：骑板时 `take_damage()` 会把伤害**分流到踏板**（一板两机共用一份耐久），
## 所以"机体血没变"并不能证明"伤害没落地"。做**负面**断言（不该受伤）时要两种口径都查；
## 做**正面**断言（应该受伤）时用它才不会被"伤害跑去打板了"骗过。
static func _total(u: FlightBody) -> float:
	var sum := _pool(u)
	if u.has_method("has_pedal") and u.has_pedal():
		var board = u.pedal_owner()
		if board != null and is_instance_valid(board):
			sum += float(board.hp)
	return sum


## 把一台机**停住**：清掉速度 + 关掉它的物理步进。
##
## 为什么需要它：`Projectile` 的判定是"这一帧从 from 扫到 to"，而靶子同时也在一帧
## 飞十几米 —— 两者叠加会让"打中了没有"取决于 AI 当时想干什么。测试要的是**静止标靶**。
##（关物理在这里是安全的：被测对象是弹丸与闸门，不是这台机的机动。）
static func _hold_still(fb: FlightBody) -> void:
	fb.set_physics_process(false)
	fb.fm.velocity = Vector3.ZERO
	fb.fm.speed = 0.0
	fb.velocity = Vector3.ZERO


## 从 8 m 外朝 `victim` 打一发火神炮，并推进到命中。
##
## 8 m 是刻意的：火神炮 1400 m/s ⇒ 单帧位移 23 m，**第一帧就一定穿过**。
## `Projectile` 用的是 `cast_motion()` 扫掠（见那里的注释），
## 所以"起点还没重叠"不会导致漏判。
static func _fire_at(shooter: FlightBody, victim: FlightBody, host: Node) -> void:
	var dir := (victim.global_position - shooter.global_position).normalized()
	Projectile.vulcan(victim.get_parent(), victim.global_position - dir * 8.0,
		dir, shooter, 50.0)
	for i in 3:
		await host.get_tree().physics_frame


# ---------------------------------------------------------------- 1 闸门本体

static func _gate(t: T, host: Node) -> void:
	var m := _spawn_squad(host)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 16:
		await host.get_tree().physics_frame

	var s := _troops(m)
	var player: FlightBody = s["player"]
	var wing: FlightBody = s["wing"]
	t.ok(player != null, "编队战局建起来了（拿到玩家）")
	if player == null or wing == null:
		t.ok(false, "**一个同队队友都没找到** —— 这个套件的前提不成立")
		m.queue_free()
		await host.get_tree().physics_frame
		return
	t.eq(wing.team, player.team, "队友与玩家同队（team 相等）")
	t.ok(wing != player, "队友不是玩家自己")

	# ① 玩家打队友：一点都不能变（机体血、护盾、踏板耐久**三样**一起查）
	#
	# ⚠️ `take_damage(amount, source, type)` 里**接收者才是受害者**。
	# 第一版写反了（`player.call("take_damage", 50.0, wing, ...)` = 玩家挨打），
	# 于是"队友血没变"**恒为真** —— 一条自测自绿、其实什么都没测的断言。
	# 正确的摆法是：受害者 = 队友、来源 = 玩家。
	var before_pool := _pool(wing)
	var before_total := _total(wing)
	wing.call("take_damage", 50.0, player, Damage.Type.VULCAN)
	t.near(_pool(wing), before_pool, 0.0001, "玩家→队友 火神炮：队友 hp+ifield 一点没变")
	t.near(_total(wing), before_total, 0.0001, "玩家→队友：**连踏板耐久也没变**（分流整条没走）")

	wing.call("take_damage", 90.0, player, Damage.Type.BEAM)
	t.near(_total(wing), before_total, 0.0001, "玩家→队友 光束：同样的结论")

	# ② 队友打玩家：反向也要成立 —— 只修一个方向会变成"只有玩家有特权的单向闸门"
	var p_pool := _pool(player)
	var p_total := _total(player)
	player.call("take_damage", 50.0, wing, Damage.Type.VULCAN)
	t.near(_pool(player), p_pool, 0.0001, "队友→玩家 火神炮：玩家 hp+ifield 一点没变")
	t.near(_total(player), p_total, 0.0001, "队友→玩家：连踏板耐久也没变")

	# ③ 友军的弹**不该打断修复**（闸门放在 `_repair_left` 之前是刻意的）
	#
	# 否则僚机扫一梭就把玩家的修复包白吃了 —— 那是"友军误伤"的另一种形态。
	player.set("_repair_left", 3.0)
	wing.call("take_damage", 50.0, player, Damage.Type.VULCAN)
	t.near(float(player.get("_repair_left")), 3.0, 0.0001,
		"友军命中**不打断修复**（闸门在 `_repair_left` 之前）")
	player.set("_repair_left", 0.0)

	# ④ 信号层也不能发 `damaged` —— HUD 的告警与镜头抖动都挂在它上面
	var fired := [0]
	var cb := func(_a: float, _s: Node3D, _d: int) -> void:
		fired[0] += 1
	wing.damaged.connect(cb)
	# 受害者 = 队友、来源 = 玩家（同一处 `this`/`source` 的坑，见 ①）
	wing.call("take_damage", 50.0, player, Damage.Type.VULCAN)
	t.eq(fired[0], 0, "友军命中**不发 `damaged` 信号**（告警 / 镜头抖动都不会被误触）")
	# 反证：同一条路径在**敌方**命中时必须照常落地，否则"没反应"可能只是因为接错了对象。
	#
	# ⚠️ 判据**不能**用 `damaged` 信号：敌机 I 立场满的时候这一发会被护盾整根吃掉，
	# 而 `_apply_damage()` 在 `to_hull <= 0` 时**按设计**提前 return（"零伤害不该抖镜头"）
	# —— 信号本来就不该发。要看的是"伤害有没有落地"，所以用 `hp + ifield` 的口径
	#（护盾吃下也算落地）。第一版这里断言 `fired[0] == 1`，是一条必然红的断言。
	var foe: FlightBody = s["foe"]
	if foe != null:
		t.ok(player.is_hostile_to(foe), "（前提）敌机与自己**不同队**")
		var foe_before := _total(foe)
		foe.call("take_damage", 50.0, player, Damage.Type.VULCAN)
		t.ok(_total(foe) < foe_before - 0.0001,
			"**敌方**命中照常落地（证明上面那条的「没反应」不是把对象接错了）")
	wing.damaged.disconnect(cb)

	m.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 2 弹丸那一侧

static func _projectile(t: T, host: Node) -> void:
	var m := _spawn_squad(host)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 16:
		await host.get_tree().physics_frame

	var s := _troops(m)
	var player: FlightBody = s["player"]
	var wing: FlightBody = s["wing"]
	var enemy: FlightBody = s["foe"]
	if player == null or wing == null:
		t.ok(false, "**缺少队友** —— 弹丸那条测不了")
		m.queue_free()
		await host.get_tree().physics_frame
		return

	# ---- 摆位：队友与敌机**同一套**，只有阵营不同（这才是干净的对照）----
	#
	# ⚠️ 第一版在这里踩了两个坑，两条断言一条假绿、一条假红：
	#   ① 靶子**还在被 AI 驱动**：500 m/s × 1/60 s ≈ 8 m/帧的漂移，足以让 15 m 外
	#      的直线弹道擦过去（命中半径 1.5 + 机体胶囊 ~5 m，余量本来就只有几米）。
	#   ② 于是"队友没掉血"通过了（其实压根没打中），"敌机该掉血"失败了。
	# 干净的做法是把靶子**停住**：关掉物理步进之后它不再机动，
	# 弹道与目标双双不动，命中与否只取决于那道闸门。
	#（这里关物理是安全的：被测对象是**弹丸与闸门**，靶子只是个静止标靶。）
	player.global_position = Vector3(0.0, 3000.0, 0.0)
	wing.global_position = Vector3(150.0, 3000.0, 0.0)
	_hold_still(player)
	_hold_still(wing)
	if enemy != null:
		enemy.global_position = Vector3(9000.0, 3000.0, 0.0)
		_hold_still(enemy)
	await host.get_tree().physics_frame

	# ① 队友：同一套弹丸扫过去，一点血都不能掉
	var before := _total(wing)
	await _fire_at(player, wing, host)
	t.near(_total(wing), before, 0.0001,
		"**弹丸扫过队友不掉血**（原来这里会掉 —— 用户报的「自相残杀」）")

	# ② 反证：**同一套弹丸**打敌人必须照常掉血 ——
	# 否则"队友没掉血"可能只是因为弹丸压根没飞对（那是假绿，比红更坏）
	#
	# ★★ 轮 58：这条断言**还有第二重身份** —— 它是「弹丸扫掠判定」唯一的端到端判据。
	#   它长期红过（`29 PASS / 1 FAIL`），根因**不在闸门**，而在 `Projectile` 的
	#   兜底扫描：临界接触时 `cast_motion()` 报的比例落在「球面刚相切」那一刻，
	#   而 `intersect_shape()` 认的「重叠」在**它之后** ⇒ 旧兜底区间 `[0, cast[1]]`
	#   压根装不下接触点 ⇒ 这一发未命中就继续飞，56 m/帧 一帧越过目标 ⇒ **永久作废**。
	#   轮 58 已修（`scripts/combat/projectile.gd` 改成两段式兜底：细窗口 + 整段），
	#   本条随之转绿。
	#
	# ⚠️ **本条几何是被挑选过的**：`from = 9000 − 8 m`、靶在 `(9000, 3000, 0)`、
	#   机体速度 ×1.5 ⇒ 单帧位移 56 m —— 这组数字恰好落在「临界接触」上，
	#   才区分得出新旧两版。**动这些数字之前先读 `README.md` §30**，
	#   否则这条断言会退化成「两版都绿」的装饰。
	if enemy != null:
		var e_before := _total(enemy)
		await _fire_at(player, enemy, host)
		t.ok(_total(enemy) < e_before - 0.0001,
			"同一套弹丸打**敌人**照常掉血（防「闸门把弹丸一起挡了」）")

	m.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 3 白名单

static func _control(t: T, host: Node) -> void:
	var m := _spawn_squad(host)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 16:
		await host.get_tree().physics_frame

	var s := _troops(m)
	var player: FlightBody = s["player"]
	var foe: FlightBody = s["foe"]
	if player == null or foe == null:
		t.ok(false, "**找不到敌机** —— 白名单那几条测不了")
		m.queue_free()
		await host.get_tree().physics_frame
		return

	# ① 敌机照常受伤
	#
	# ⚠️ 受害者是**敌机**，所以接收者必须是 `foe`。第一版写成 `player.call(...)`，
	# 那是"玩家挨敌机的打"，而断言查的是敌机的血 ⇒ 必然红（而且红得没道理）。
	var b := _total(foe)
	foe.call("take_damage", 60.0, player, Damage.Type.BEAM)
	t.ok(_total(foe) < b - 0.0001, "敌机仍然受伤（闸门只拦友军）")

	# ② `source == null`（撞地 / 撞海 / 世界几何）**必须放行**
	#
	# ⚠️ 这一条是**最容易写错**的：把闸门写成"来源不是自己就拦"，
	# 会顺手把撞海一起挡掉 —— 而那是一条独立的伤害来源。
	b = _total(foe)
	foe.call("take_damage", 60.0, null, Damage.Type.RAM)
	t.ok(_total(foe) < b - 0.0001, "`source == null` 放行（撞地 / 撞海仍掉血）")

	# ③ 来源是自己（变形自伤 / 踏板爆裂抛出）也要放行
	b = _total(foe)
	foe.call("take_damage", 30.0, foe, Damage.Type.RAM)
	t.ok(_total(foe) < b - 0.0001, "`source == self` 放行（自伤类伤害不在闸门管辖内）")

	# ④ 白名单判据本身（纯函数级）—— 直接问 `is_friendly_fire()`
	var wing: FlightBody = s["wing"]
	if wing != null:
		t.ok(player.is_friendly_fire(wing), "`is_friendly_fire(队友)` = true")
		t.not_ok(player.is_friendly_fire(foe), "`is_friendly_fire(敌机)` = false")
		t.not_ok(player.is_friendly_fire(null), "`is_friendly_fire(null)` = false")
		t.not_ok(player.is_friendly_fire(player), "`is_friendly_fire(自己)` = false")
		t.not_ok(player.is_friendly_fire(m.get("chase")), "`is_friendly_fire(非机体)` = false")

	m.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 4 记账

## 闸门"拦下了"不该是无声的：结算页的「友军拦截 · 僚机损失」读的就是这两个计数。
## 本节把计数口径钉死：**谁记、谁不记、僚机损失按什么判**。
static func _ledger(t: T, host: Node) -> void:
	var m := _spawn_squad(host)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 16:
		await host.get_tree().physics_frame

	var s := _troops(m)
	var player: FlightBody = s["player"]
	var wing: FlightBody = s["wing"]
	var foe: FlightBody = s["foe"]
	if player == null or wing == null or foe == null:
		t.ok(false, "**缺队友或敌机** —— 记账那几条测不了")
		m.queue_free()
		await host.get_tree().physics_frame
		return

	t.eq(int(Game.friendly_fire_blocked), 0, "（前置）拦截计数清零")
	t.eq(int(Game.allies_lost), 0, "（前置）僚机损失清零")

	# ① 闸门每拦一次记一笔 —— 弹丸直调与军刀共用 `take_damage` 这一个入口
	var b0 := int(Game.friendly_fire_blocked)
	var wing_pool := _pool(wing)
	wing.call("take_damage", 50.0, player, Damage.Type.VULCAN)
	t.eq(int(Game.friendly_fire_blocked), b0 + 1, "玩家→队友：拦截计数 +1")
	t.near(_pool(wing), wing_pool, 0.0001, "（对照）队友仍然没掉血")

	# ② 敌方命中**不**进拦截计数（闸门没拦它，它走的是正常伤害）
	player.call("take_damage", 30.0, foe, Damage.Type.VULCAN)
	t.eq(int(Game.friendly_fire_blocked), b0 + 1, "敌机→玩家：正常伤害，拦截计数不动")

	# ③ 僚机损失：判据是"相对玩家同队"，跟谁开的手无关 ——
	# 僚机撞地自毁、被流弹蹭死都算。这里让敌机击坠僚机。
	var l0 := int(Game.allies_lost)
	wing.call("take_damage", 99999.0, foe, Damage.Type.BEAM)
	await host.get_tree().physics_frame
	t.eq(int(Game.allies_lost), l0 + 1, "僚机被敌机击坠：allies_lost +1")
	t.eq(int(Game.friendly_fire_blocked), b0 + 1, "（对照）击坠本身不产生拦截计数")

	# ④ 敌机被击坠**不**动僚机损失（敌方不是"玩家的友军"）
	var l1 := int(Game.allies_lost)
	foe.call("take_damage", 99999.0, player, Damage.Type.BEAM)
	await host.get_tree().physics_frame
	t.eq(int(Game.allies_lost), l1, "敌机被击坠：僚机损失不动")

	m.queue_free()
	await host.get_tree().physics_frame
