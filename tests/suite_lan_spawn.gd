class_name SuiteLanSpawn
extends RefCounted
## 多人（局域网）**出生逻辑**的单机验证。
##
## 规则层（谁和谁一队、谁开哪台机）在 `suite_lan_plan`；这里验的是
## "名单 → 场上的机体"这一段 —— 把 `LanPlan` 算出来的名单真的撒到场上，然后量：
##   ① 同乘：主机的板**载着两台**（`riders.size() == 2`）；
##   ② 同乘：加入方那台**不做气动**（`is_carried()` 为真）；
##   ③ 两边**各恰好一台 ACE**；
##   ④ 常规出战：编制与踏板数都按方案来（**期望值从方案反推，不写死**）。
##
## ⚠️ 走**真正的开局入口** `_on_start_match()`（而不是直接调 `spawn_lan()`）：
## 玩家机体是开局流程里建的，跳过它只会得到 `player == null`。
##
## ⚠️ 需要第二台机器的部分（快照同步、后座控制中转）**不在这里** —— 那些只能在
## 两台机器上真跑才能验。

const MAFTY := BattleFormation.Side.MAFTY
const FEDERATION := BattleFormation.Side.FEDERATION


static func run(t: T, host: Node) -> void:
	t.suite("LanSpawn / 同乘：一块板载两台")
	await _shared_pedal(t, host)
	t.suite("LanSpawn / 常规：两边满编")
	await _normal(t, host)


static func _new_main(host: Node) -> Node:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	host.add_child(m)
	return m


## 数**不重复的踏板**（每台机都可能"在某块板上"，但只有领机是板的 owner）。
## 数一份名单里用到了几个量产编队（由方案反推，不写死）。
static func _squads_of(units: Array) -> int:
	var seen := {}
	for u: BattleFormation.Unit in units:
		if not u.is_ace:
			seen[u.squad] = true
	return seen.size()


## 数一份名单里有几个"远端玩家的代理槽"。
## 代理**不带板**：它只是"本机名单里对面那个真人的槽位"，
## 本机这边不替它造板（板在它自己的机器上）——所以板数与骑手数都要减掉它。
static func _count_proxies_in(units: Array) -> int:
	var n := 0
	for u: BattleFormation.Unit in units:
		if u.owner_is_client:
			n += 1
	return n


static func _count_pedals(m: Node, team: int) -> int:
	var seen := {}
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if u.get("team") != team:
			continue
		if not u.has_method("has_pedal") or not u.has_pedal():
			continue
		var b = u.call("pedal_owner")
		if b != null:
			seen[b.get_instance_id()] = true
	return seen.size()


## 数"骑在某块板上的人"（含被载的后座）。
static func _count_riders(m: Node, team: int) -> int:
	var n := 0
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if u.get("team") != team:
			continue
		if u.has_method("has_pedal") and u.has_pedal():
			n += 1
	return n


static func _count_aces(m: Node, team: int) -> int:
	var n := 0
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if u.get("team") != team:
			continue
		var p = u.get("profile")
		if p != null and p.id in [SuitProfile.Id.XI, SuitProfile.Id.PENELOPE, SuitProfile.Id.ARIZEUS]:
			n += 1
	return n


static func _shared_pedal(t: T, host: Node) -> void:
	var m := _new_main(host)
	await host.get_tree().physics_frame
	# 手工摆出"同阵营 + 都选量产机"的局面（马夫蒂 + 梅萨）
	Game.match_mode = Game.MatchMode.LAN
	Game.active_suit = SuitProfile.Id.MESSER_M01
	Game.active_side = MAFTY
	Net.role = Net.Role.HOST
	Net.local_team = 0
	Net.remote_suit = SuitProfile.Id.MESSER_M01
	Net.remote_side = MAFTY
	var plan: LanPlan.Plan = m.call("_lan_plan_now")
	t.ok(plan != null, "算出了部署方案")
	if plan == null:
		m.queue_free()
		return
	t.ok(plan.is_shared_pedal(), "同阵营 + 都量产机 ⇒ 判定为同乘")

	# ⚠️ 走**真正的开局入口**（`_on_start_match`）：它会摆好 world / 菜单 / 开局阶段，
	# 然后按 `match_mode` 分派到 `spawn_lan()`。
	# 直接调 `spawn_lan()` 是不行的 —— 玩家机体（`player`）是开局流程里建的，
	# 跳过它只会得到 `player == null`（第一版探针就是这么白跑的）。
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.OENBELLI, Game.MatchMode.LAN, -1)
	for i in 14:
		await host.get_tree().physics_frame

	# ① 玩家（= 主机 = 驾驶）那台有板，而且**板上登记着两台**
	t.ok(m.player != null, "玩家机体建出来了")
	var board: FlightPedal = null
	if m.player.has_method("pedal_owner"):
		board = m.player.pedal_owner()
	t.ok(board != null, "驾驶方（主机）身上挂着踏板")
	if board != null:
		t.eq(board.riders.size(), 2, "同乘：板上**登记着两台**（领机 + 后座）")

	# ② 远端玩家那台是**后座**：被载、不做气动
	var mate: NetProxyBody = null
	for p: NetProxyBody in m.get("remote_proxies"):
		mate = p
		break
	t.ok(mate != null, "远端玩家的代理机体建出来了")
	if mate != null:
		t.eq(mate.team, 0, "远端玩家与主机**同队**（同乘的前提）")
		t.ok(mate.is_carried(), "远端玩家被载（carried_by 已设）—— 他不自己做气动")
		if board != null:
			t.ok(board.riders.has(mate), "远端玩家登记在这块板上")

	# ③ 两边各恰好一台 ACE
	t.eq(_count_aces(m, 0), 1, "我方（含远端）恰好一台 ACE")
	t.eq(_count_aces(m, 1), 1, "对面（全 AI）恰好一台 ACE")

	m.queue_free()
	await host.get_tree().physics_frame


static func _normal(t: T, host: Node) -> void:
	var m := _new_main(host)
	await host.get_tree().physics_frame
	# 不同阵营（联邦 vs 马夫蒂）⇒ 常规出战
	Game.match_mode = Game.MatchMode.LAN
	Game.active_suit = SuitProfile.Id.GUSTAV00
	Game.active_side = FEDERATION
	Net.role = Net.Role.HOST
	Net.local_team = 0
	Net.remote_suit = SuitProfile.Id.MESSER_M01
	Net.remote_side = MAFTY
	var plan: LanPlan.Plan = m.call("_lan_plan_now")
	t.ok(plan != null, "算出了部署方案（常规）")
	if plan != null:
		t.not_ok(plan.is_shared_pedal(), "不同阵营 ⇒ **不是**同乘")
	m.call("_on_start_match", SuitProfile.Id.GUSTAV00, Difficulty.Level.NORMAL,
		MapDef.Id.OENBELLI, Game.MatchMode.LAN, -1)
	for i in 14:
		await host.get_tree().physics_frame

	# ⚠️ **期望值从方案反推，不要写死**：
	# 不同队时每边只有"一个真人 + 对面那台的代理"占掉编队位，
	# 所以量产编队**不是** `SQUADS_PER_SIDE`（那个数是"满编 AI"时的）。
	# 写死期望值会让这条断言在"谁是真人"变化时无意义地红。
	var lineups: Dictionary = m.call("_lan_canonical_lineups",plan)
	var squads_0 := _squads_of(lineups["mine"])
	var squads_1 := _squads_of(lineups["theirs"])
	# ⚠️ **代理机体不带板**：它只是"本机名单里对面那个真人的槽位"，
	# 本机这边不替它造板（板在它自己的机器上）。所以板数与骑手数都要减掉它。
	var proxies_0 := _count_proxies_in(lineups["mine"])
	var proxies_1 := _count_proxies_in(lineups["theirs"])
	t.eq(_count_pedals(m, 0), squads_0 - proxies_0,
		"我方 %d 块板（%d 编队 − %d 代理）" % [squads_0 - proxies_0, squads_0, proxies_0])
	t.eq(_count_pedals(m, 1), squads_1 - proxies_1,
		"对面 %d 块板（%d 编队 − %d 代理）" % [squads_1 - proxies_1, squads_1, proxies_1])
	# ⚠️ 判据是"**骑手**数"（含被载的后座）而不是"板的 owner 数"：
	# 后座也骑在板上（1.2 第二十六轮起后座是真正被载的），每边 = 编队数 × 2 − 代理数。
	# ⚠️ **有板的骑手** = `(编队数 − 代理数) × 2`：
	#   - 代理占掉的那个编队**没有板**（代理不带板），但它的**后座 AI 照常生成**
	#     并站在别的板上 —— 所以那个编队是"1 个有板的骑手"；
	#   - 其余编队各 2 台都有板（领机 + 被载的后座）。
	# 这条式子与 `_count_pedals`（板数 = 编队数 − 代理数）是同一件事的两种量法。
	t.eq(_count_riders(m, 0),
		(squads_0 - proxies_0) * BattleFormation.UNITS_PER_SQUAD,
		"我方 %d 台有板（%d 编队 − %d 代理，每队 2 台）"
			% [(squads_0 - proxies_0) * BattleFormation.UNITS_PER_SQUAD, squads_0, proxies_0])
	t.eq(_count_aces(m, 0), 1, "我方恰好一台 ACE")
	t.eq(_count_aces(m, 1), 1, "对面恰好一台 ACE")

	# 不同队 ⇒ **两边各有一台**远端玩家的代理（对面那台归真人开）
	var proxies: int = m.get("remote_proxies").size()
	t.eq(proxies, 1, "不同队时仅一台远端玩家代理")

	m.queue_free()
	await host.get_tree().physics_frame
