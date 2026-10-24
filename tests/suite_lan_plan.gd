class_name SuiteLanPlan
extends RefCounted
## 多人（局域网）玩法规则 —— 用户 2026-09-21 定的那张表。
##
## ⚠️ 文件名/类名按**主题**命名（不按轮次占号）：这个仓库有另一个会话在并行编辑，
## 双方都按"轮次"编号时撞过一次（`suite_round22` 那次）。详见 `suite_worldscale` 的注释。
##
## ## 规则（用户原话 → 代码）
## > 「玩家可以选择王牌机对战；也可以选择小队模式。小队模式如果选择**统一阵营**的情况下，
## > 又都选择了**量产机**，那就**一起乘坐同一台踏板出击**，系统补一个 AI ACE。
## > 如果没有都选择量产机，那么都做选择量产机的正常出战，选择王牌机的也正常出战。
## > 如果没有选择同一阵营也没有选择都选择量产机，就正常王牌机对打。」
##
## 四种组合里只有**一种**是特例：
##
## | # | 阵营 | 两人机体 | 期望 |
## |---|---|---|---|
## | 1 | 同阵营 | 都是量产机 | **同乘一块踏板**（主机驾驶 / 加入方后座）|
## | 2 | 同阵营 | 一台量产 + 一台 ACE | 各自正常出战 |
## | 3 | 不同阵营 | 都是量产机 | 正常王牌机对打（不同队，各自出战）|
## | 4 | 不同阵营 | 都是 ACE | 正常王牌机对打 |
##
## 另外两条**结构性**要求，每组都要成立：
##   - 每一组的编制都恒定为 **3 编队 × 2 台 + 1 ACE**（玩家占槽，不是额外加人）；
##   - 每一边**恰好一台 ACE**（用户："对面也肯定最多有一个最少有一个 ace 机"）。

const RULES := "LanPlan / 规则表：四种组合"
const ROSTER := "LanPlan / 编制恒等与 ACE 兜底"
const SEATS := "LanPlan / 同乘座位：主机驾驶、加入方后座"


static func run(t: T, host: Node) -> void:
	t.suite(RULES)
	_rules(t)
	t.suite(ROSTER)
	_roster(t)
	t.suite(SEATS)
	_seats(t)
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 1 规则表

static func _rules(t: T) -> void:
	var maf := BattleFormation.Side.MAFTY
	var fed := BattleFormation.Side.FEDERATION
	var mp_mafty := SuitProfile.Id.MESSER_M01        # 马夫蒂的量产机
	var ace_mafty := SuitProfile.Id.XI               # 马夫蒂的 ACE
	var mp_fed := SuitProfile.Id.GUSTAV00            # 联邦的量产机
	var ace_fed := SuitProfile.Id.PENELOPE           # 联邦的 ACE

	# ---- ① 同阵营 + 都是量产机 ⇒ 同乘 ----
	var p1 := LanPlan.build(
		LanPlan.Choice.new(mp_mafty, maf), LanPlan.Choice.new(mp_mafty, maf))
	t.eq(p1.kind, LanPlan.Kind.SHARED_PEDAL, "①同阵营+都量产 ⇒ 同乘一块踏板")
	t.ok(p1.same_team, "①两人同队")
	t.ok(p1.is_shared_pedal(), "① is_shared_pedal() 为真")

	# ---- ② 同阵营 + 一台量产、一台 ACE ⇒ 各自正常出战 ----
	var p2 := LanPlan.build(
		LanPlan.Choice.new(mp_mafty, maf), LanPlan.Choice.new(ace_mafty, maf))
	t.eq(p2.kind, LanPlan.Kind.VERSUS, "②同阵营但有人选 ACE ⇒ 不同乘")
	t.ok(p2.same_team, "②两人仍然同队（同阵营就是同队）")

	# ---- ③ 不同阵营 + 都量产 ⇒ 正常对打 ----
	var p3 := LanPlan.build(
		LanPlan.Choice.new(mp_mafty, maf), LanPlan.Choice.new(mp_fed, fed))
	t.eq(p3.kind, LanPlan.Kind.VERSUS, "③不同阵营 ⇒ 不同乘（哪怕都选了量产机）")
	t.ok(not p3.same_team, "③两人不同队")

	# ---- ④ 不同阵营 + 都是 ACE ⇒ 正常对打 ----
	var p4 := LanPlan.build(
		LanPlan.Choice.new(ace_mafty, maf), LanPlan.Choice.new(ace_fed, fed))
	t.eq(p4.kind, LanPlan.Kind.VERSUS, "④不同阵营 + 双 ACE ⇒ 正常王牌机对打")
	t.ok(not p4.same_team, "④两人不同队")

	# ---- 非法选择（跨阵营的机体）绝不能触发同乘 ----
	# 判据：机体不属于他选的阵营时 `is_valid()` 为假 ⇒ `same_team` 为假 ⇒ 不同乘。
	var bad := LanPlan.Choice.new(ace_fed, maf)      # 联邦的 ACE 却选了马夫蒂
	t.not_ok(bad.is_valid(), "跨阵营的选择被判为非法")
	var p5 := LanPlan.build(bad, LanPlan.Choice.new(mp_mafty, maf))
	t.eq(p5.kind, LanPlan.Kind.VERSUS, "有非法选择时退回正常对打（不会同乘）")
	t.ok(not p5.same_team, "非法选择 ⇒ 不认作同队")


# ---------------------------------------------------------------- 2 编制恒等

static func _roster(t: T) -> void:
	var maf := BattleFormation.Side.MAFTY
	var fed := BattleFormation.Side.FEDERATION
	var mp := SuitProfile.Id.MESSER_M01
	var ace := SuitProfile.Id.XI
	var mp_fed := SuitProfile.Id.GUSTAV00
	var ace_fed := SuitProfile.Id.PENELOPE
	var want := BattleFormation.unit_count_per_side()

	var cases := [
		["同阵营+都量产", mp, maf, mp, maf],
		["同阵营+一量一 ACE", mp, maf, ace, maf],
		["不同阵营+都量产", mp, maf, mp_fed, fed],
		["不同阵营+双 ACE", ace, maf, ace_fed, fed],
	]
	for c: Array in cases:
		var label := str(c[0])
		var p := LanPlan.build(
			LanPlan.Choice.new(int(c[1]), int(c[2])),
			LanPlan.Choice.new(int(c[3]), int(c[4])))
		# 每一组的编制都恒定 —— 玩家**占槽**，不是额外加人。
		t.eq(p.host_team.size(), want, "%s：主机阵营编制 = %d 台" % [label, want])
		t.eq(p.client_team.size(), want, "%s：加入方阵营编制 = %d 台" % [label, want])
		# 每一边**恰好一台 AI ACE**，而且它必须是本阵营的（老板铁律：
		# "每个系统补充的王牌机只能是同阵营的"）。
		#
		# ⚠️ 判据是"**AI 的** ACE 恰好一台"，不是"ACE 恰好一台"：
		# 真人自己开 ACE 时（如"主机选柯西"），那台 ACE 归真人 —— 于是这一边是
		# "1 台真人 ACE + 1 台 AI ACE"？？不：**ACE 位只有一个**，
		# 所以那种情况下这一边**没有 AI ACE**（0 台），下面分别断言。
		#
		# ⚠️ 还要按 `human_seat` 排掉"对面玩家的代理槽"：不同队时本方名单里
		# 那台 `owner_is_client` 是**敌阵营**的机体，不该拿本阵营的口径去量。
		for pair: Array in [[p.host_team, p.host_side, "主机"], [p.client_team, p.client_side, "加入方"]]:
			var team: Array = pair[0]
			var side: int = pair[1]
			var ai_aces := 0
			var human_aces := 0
			for u: BattleFormation.Unit in team:
				if not u.is_ace:
					continue
				# 对面玩家的代理槽：它是**敌阵营**的机体，本阵营的口径不适用。
				if u.human_seat == 1 and not BattleFormation.belongs_to(side, u.suit):
					continue
				if u.human_seat >= 0:
					human_aces += 1
					t.ok(BattleFormation.belongs_to(side, u.suit),
						"%s/%s：真人开的 ACE 是本阵营的（%s）" % [label, pair[2], u.display_name()])
				else:
					ai_aces += 1
					t.ok(BattleFormation.belongs_to(side, u.suit),
						"%s/%s：AI ACE 是同阵营的（%s）" % [label, pair[2], u.display_name()])
			t.eq(ai_aces + human_aces, 1, "%s/%s：ACE 位恰好一台" % [label, pair[2]])
			t.lt(human_aces, 2, "%s/%s：真人开的 ACE 最多一台" % [label, pair[2]])
		# 本方**自己的**机体都属于本方阵营（不许跨阵营混进名单）。
		for pair2: Array in [[p.host_team, p.host_side, "主机"], [p.client_team, p.client_side, "加入方"]]:
			for u2: BattleFormation.Unit in pair2[0]:
				if u2.human_seat == 1:
					continue          # 远端玩家的槽位（不同队时它是敌机，理应对面阵营）
				t.ok(BattleFormation.belongs_to(pair2[1], u2.suit),
					"%s/%s：本方机体是同阵营的（%s）" % [label, pair2[2], u2.display_name()])

	# ---- 两个真人各占一个槽：同队时同一份名单里两个标记都在 ----
	var p_shared := LanPlan.build(
		LanPlan.Choice.new(mp, maf), LanPlan.Choice.new(mp, maf))
	var n_player := 0
	var n_client := 0
	for u: BattleFormation.Unit in p_shared.host_team:
		if u.owner_is_player:
			n_player += 1
		if u.owner_is_client:
			n_client += 1
	t.eq(n_player, 1, "同队名单里恰有一台标着 owner_is_player（主机）")
	t.eq(n_client, 1, "同队名单里恰有一台标着 owner_is_client（加入方）")

	# 不同队时：**两份名单里各自都是"1 个本机 + 1 个对面代理"**。
	#
	# ⚠️ 这一条改过（第二十二轮下半）：原来是"加入方名单里不该出现加入方的标记"，
	# 那是把 `Plan` 当成"两台机器各看自己那一半"了。实际不是 ——
	# `Plan` 是**主机视角的一份完整对局**，而每台机器用它的时候都要知道自己那份名单里
	# **对面那台归谁开**（否则代理机体建不出来：探针实测 `remote_proxies` 为空）。
	# 所以两份名单都带远端标记，只是标的**人**不同（主机那份标加入方、反之亦然）。
	var p_pair := LanPlan.build(
		LanPlan.Choice.new(mp, maf), LanPlan.Choice.new(mp_fed, fed))
	var pair_labels := ["主机名单", "加入方名单"]
	for i in 2:
		var team: Array = p_pair.host_team if i == 0 else p_pair.client_team
		var np := 0
		var nc := 0
		var foe_side_of_this := BattleFormation.Side.FEDERATION if i == 0 \
			else BattleFormation.Side.MAFTY
		for u3: BattleFormation.Unit in team:
			if u3.owner_is_player:
				np += 1
			if u3.owner_is_client:
				nc += 1
				# 这一台是**对面那个真人**的代理槽 ⇒ 必须是敌阵营的机体
				t.ok(BattleFormation.belongs_to(foe_side_of_this, u3.suit),
					"%s：远端标记落在**敌阵营**机体上（%s）" % [pair_labels[i], u3.display_name()])
		t.eq(np, 1, "%s：恰有一台是本机的机体" % pair_labels[i])
		t.eq(nc, 1, "%s：恰有一台是**对面那个真人**的代理槽" % pair_labels[i])

	# 对面（`enemy_lineup()`）才是"打谁"的真源：不同队时它就是那份含代理的名单，
	# 而且要能建出**恰好一台**代理（多一台就会多一个远端机体）。
	var foe_lineup: Array = p_pair.enemy_lineup()
	var proxies := 0
	var aces_foe := 0
	for u4: BattleFormation.Unit in foe_lineup:
		if u4.owner_is_client:
			proxies += 1
		if u4.is_ace and u4.human_seat != 1:
			aces_foe += 1
	t.eq(foe_lineup.size(), BattleFormation.unit_count_per_side(),
		"对面名单编制 = %d 台" % BattleFormation.unit_count_per_side())
	t.eq(proxies, 1, "对面**恰好一台**是远端玩家的代理（不同队时）")
	t.eq(aces_foe, 1, "对面恰好一台 AI ACE（ACE 位没被代理占掉时）")


# ---------------------------------------------------------------- 3 同乘座位

static func _seats(t: T) -> void:
	var maf := BattleFormation.Side.MAFTY
	var mp := SuitProfile.Id.MESSER_M01
	var p := LanPlan.build(LanPlan.Choice.new(mp, maf), LanPlan.Choice.new(mp, maf))

	# ① 主机驾驶（用户选的是"2+3"：主机开板，加入方后座且保留开火权）
	t.ok(p.pilot_is_host, "同乘时主机驾驶")

	# ② 两个真人坐在**同一个编队**的 slot 0 / slot 1 —— 那正是"一块板载两台"的槽位约定
	var lead: BattleFormation.Unit = null
	var pillion: BattleFormation.Unit = null
	for u: BattleFormation.Unit in p.host_team:
		if u.owner_is_player and not u.is_ace:
			lead = u
		if u.owner_is_client and not u.is_ace:
			pillion = u
	t.ok(lead != null, "同乘：找到主机的机体")
	t.ok(pillion != null, "同乘：找到加入方的机体")
	if lead != null and pillion != null:
		t.eq(lead.squad, pillion.squad, "两人在**同一个编队**（同乘的前提）")
		t.eq(lead.slot, 0, "主机坐 slot 0（领机 / 驾驶位）")
		t.eq(pillion.slot, 1, "加入方坐 slot 1（后座 / 被载位）")
		t.eq(lead.suit, mp, "主机开的是他选的量产机")
		t.eq(pillion.suit, mp, "加入方开的是他选的量产机")
		t.not_ok(lead.is_ace and pillion.is_ace, "同乘的两人都不是 ACE 位")

	# ③ **对面的名单**：没有真人，全是 AI（含恰好一台 ACE）——
	#    这正是"同队时对面需要一个 AI ACE 来打"的落点。
	#
	# ⚠️ 对面是**敌阵营**，不是 `p.client_team`。这里踩过一次：
	# `host_team` / `client_team` 是"**两台机器各自视角的那一份名单**"，
	# 同队时那两份**都是玩家这一边**（区别只是谁在 0 号位）——
	# 拿 `client_team` 当"对面"就会把玩家自己的僚机当成敌人来断言。
	# 对面要用 `LanPlan` 的同一套规则、按**敌阵营 + 没有真人**生成。
	var foe_side := BattleFormation.Side.FEDERATION if p.host_side == BattleFormation.Side.MAFTY \
		else BattleFormation.Side.MAFTY
	var enemies := LanPlan.lineup_for(foe_side, LanPlan.Choice.new(-1, foe_side))
	var aces := 0
	for u2: BattleFormation.Unit in enemies:
		t.not_ok(u2.has_human(), "对面每一台都是 AI（不是真人机体）")
		if u2.is_ace:
			aces += 1
	t.eq(aces, 1, "对面恰好一台 ACE（用户：最少一个、最多一个）")
	t.eq(enemies.size(), BattleFormation.unit_count_per_side(),
		"对面的编制也是满编（%d 台）" % BattleFormation.unit_count_per_side())
	# 而玩家那一边：**同队时两个真人都在这一边**（同乘就是"两人在一块板上"）。
	var mine := 0
	var theirs := 0
	for u4: BattleFormation.Unit in p.host_team:
		if u4.owner_is_player:
			mine += 1
		if u4.owner_is_client:
			theirs += 1
	t.eq(mine, 1, "玩家这边：恰有一台是本机的机体")
	t.eq(theirs, 1, "玩家这边：恰有一台是远端玩家的机体（同队 ⇒ 在一块板上）")

	# ④ 同队时两边的队号必须不同（否则"打对面"无从谈起）：
	#    主机/加入方同侧 ⇒ 对面是另一半。
	t.ok(p.host_side == p.client_side, "同队：两人在同一阵营")
	var foes := BattleFormation.Side.FEDERATION if p.host_side == BattleFormation.Side.MAFTY \
		else BattleFormation.Side.MAFTY
	t.not_ok(foes == p.host_side, "对手是另一半阵营（同队时对面 = 敌阵营）")
