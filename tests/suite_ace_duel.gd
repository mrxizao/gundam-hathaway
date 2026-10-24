class_name SuiteAceDuel
extends RefCounted
## 局域网**王牌战**（本轮）—— 两人各一台、没有编制也没有僚机。
##
## ## 需求原话
## 「给局域网联机模式也加入王牌战」。而用户 2026-09-21 定的规则表第一句本来就是：
## > 「玩家可以选择**王牌机对战**；也可以选择**小队模式**。」
##
## 也就是说**上一半一直是缺的** —— 那时联机只有小队战一种形态。这一套守的就是补上的那一半。
##
## ## 这一套里最要紧的两件事
## ① **两台机器必须算出同一局**。这一局是按双方选择**算**出来的（`LanPlan.build()`），
##    而两台机器上"谁是主机"正好相反 —— 所以：
##      - 投票规则 `resolve_form(a, b)` 必须**对两票对称**（与"谁是主机"无关）；
##      - 本机那一票必须来自**真的发出去的那一份**（`Net.choice_of()`），
##        不是 `Game.*`（那条链上 `active_side` / `active_lan_form` 在联机里没人写过）。
##    分叉的症状是**一边场上 2 台、另一边 14 台，而两边都不报错** —— 没有任何日志提醒你。
##
## ② **对面那台必须真的被建出来**。`main._spawn_side()` 见到"本机机体"（座位 0）
##    就**跳过不建**（那是给"本机自己那台已经在 `spawn_round()` 里建好了"写的）。
##    王牌战的两份名单里各只有一台、而且就是"这份名单的主人" ——
##    直接把它当对面撒出去，表现就是**对面那台在场上根本不存在**（不报错、没有日志，
##    只是打不到人）。所以 `enemy_lineup()` 必须把它**重标成座位 1**。
##
## ⚠️ 按**主题命名**（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。

const VOTE := "AceDuel / 投票规则：两人都选才是王牌战"
const ROSTER := "AceDuel / 名单：两边各一台，对面那台必须建得出来"
const ROW := "AceDuel / 联机页的形式那一行 + 出击闸门"
const SPAWN := "AceDuel / 一局真的撒出来只有两台"
const WIRING := "AceDuel / 跨文件接线（源码扫描）"


static func run(t: T, host: Node) -> void:
	t.suite(VOTE)
	_vote(t)
	t.suite(ROSTER)
	_roster(t)
	t.suite(ROW)
	_row(t)
	t.suite(SPAWN)
	await _spawn(t, host)
	t.suite(WIRING)
	_wiring(t)


# ---------------------------------------------------------------- 1 投票规则

static func _vote(t: T) -> void:
	var squad := LanPlan.Form.SQUAD
	var duel := LanPlan.Form.ACE_DUEL

	# ---- 下标 0 必须是 SQUAD ----
	#
	# 它是 `Choice.form` 的默认值，也就是"这一项不存在之前"联机**唯一**的行为。
	# 老用例（`suite_lan_plan` / `suite_lan_spawn` 里那些两参数的 `Choice.new(suit, side)`）
	# 就是这条的判据：默认值一改，它们全都静默变成"王牌战"。
	t.eq(int(squad), 0, "`Form.SQUAD` 是下标 0（默认值必须指向老行为）")
	t.eq(int(duel), 1, "`Form.ACE_DUEL` 是下标 1")
	t.eq(int(LanPlan.Choice.new(SuitProfile.Id.MESSER_M01,
			BattleFormation.Side.MAFTY).form), int(squad),
		"两参数构造的 `Choice` 默认打小队战（老调用方逐位不变）")
	t.eq(int(LanPlan.Choice.new(SuitProfile.Id.MESSER_M01, BattleFormation.Side.MAFTY,
			duel).form), int(duel), "三参数构造能指定形式")

	# ---- 四种投票组合 ----
	t.eq(LanPlan.resolve_form(squad, squad), squad, "两人都选小队战 ⇒ 小队战")
	t.eq(LanPlan.resolve_form(duel, duel), duel, "两人都选王牌战 ⇒ 王牌战")
	t.eq(LanPlan.resolve_form(duel, squad), squad, "只有一人选王牌战 ⇒ 小队战")
	t.eq(LanPlan.resolve_form(squad, duel), squad, "只有一人选王牌战 ⇒ 小队战（换一票在前也一样）")

	# ---- **与"谁是主机"无关**：函数对两票完全对称 ----
	#
	# ⚠️ 这条是"两台机器不会各打各的"的机械判据。若规则改成"任一人选就生效"或
	# "以主机为准"，两台机器的参数位置是**反的**（一台 `(我, 对面)`、另一台 `(对面, 我)`），
	# 于是两边算出不同的形式 —— 一边 2 台、另一边 14 台，**都不报错**。
	for a: int in [squad, duel]:
		for b: int in [squad, duel]:
			t.eq(LanPlan.resolve_form(a, b), LanPlan.resolve_form(b, a),
				"投票结果与两票的先后无关（a=%d b=%d）" % [a, b])

	# ---- 缺票（−1 = 还没收到）一律退回小队战：**不许猜** ----
	t.eq(LanPlan.resolve_form(-1, -1), squad, "两票都还没到 ⇒ 小队战（不猜）")
	t.eq(LanPlan.resolve_form(duel, -1), squad, "只有一票到 ⇒ 小队战（不猜）")
	t.eq(LanPlan.resolve_form(-1, duel), squad, "只有一票到 ⇒ 小队战（不猜）")


# ---------------------------------------------------------------- 2 名单

static func _roster(t: T) -> void:
	var duel := LanPlan.Form.ACE_DUEL
	var squad := LanPlan.Form.SQUAD
	var maf := BattleFormation.Side.MAFTY
	var fed := BattleFormation.Side.FEDERATION
	var xi := SuitProfile.Id.XI
	var pen := SuitProfile.Id.PENELOPE

	var p := LanPlan.build(
		LanPlan.Choice.new(xi, maf, duel), LanPlan.Choice.new(pen, fed, duel))
	t.eq(p.kind, LanPlan.Kind.ACE_DUEL, "两人都投王牌战 ⇒ `Kind.ACE_DUEL`")
	t.ok(p.is_ace_duel(), "`is_ace_duel()` 为真")
	t.not_ok(p.is_shared_pedal(), "王牌战不是同乘")
	t.not_ok(p.same_team, "王牌战里没有「同队」这回事（否则对面一台敌机都没有）")

	# ---- 编制：两边各**一台**，不是 `unit_count_per_side()`（7）----
	t.eq(p.host_team.size(), 1, "主机那份名单只有一台")
	t.eq(p.client_team.size(), 1, "加入方那份名单只有一台")
	t.eq(BattleFormation.unit_count_per_side(), 7, "（对照）小队战每边 7 台")
	t.eq(p.host_team[0].suit, xi, "主机那台就是主机选的机体")
	t.eq(p.client_team[0].suit, pen, "加入方那台就是加入方选的机体")
	for u: BattleFormation.Unit in [p.host_team[0], p.client_team[0]]:
		t.ok(u.is_ace, "王牌战的机体不骑飞行踏板（`is_ace` = true，没有编队）")

	# ---- **两台机器各自看到的那一台** ----
	#
	# 这是"两台机器算同一局"的可验证形式：同一份 `Plan`，`local_is_host` 一翻，
	# `local_team()` / `enemy_lineup()` 必须各自给出「自己 / 对面」。
	for local_host: bool in [true, false]:
		p.local_is_host = local_host
		var mine: Array = p.local_team()
		var foe: Array = p.enemy_lineup()
		var tag := "主机" if local_host else "加入方"
		t.eq(mine.size(), 1, "%s：本机名单一台" % tag)
		t.eq(foe.size(), 1, "%s：对面名单也一台" % tag)
		t.eq(mine[0].suit, xi if local_host else pen, "%s：本机那台 = 自己选的机" % tag)
		t.eq(foe[0].suit, pen if local_host else xi, "%s：对面那台 = 对面选的机" % tag)
		t.ok(foe[0].is_ace, "%s：对面那台也不骑板" % tag)
		# ⚠️ 座位号必须是 1（远端）。`_spawn_side()` 见到座位 0 就**跳过不建** ——
		# 直接交 `foe_team()` 会让对面在场上根本不存在（不报错、没有日志，只是打不到人）。
		t.ok(foe[0].owner_is_client, "%s：对面那台标着「远端玩家」（座位 1）" % tag)
		t.not_ok(foe[0].owner_is_player,
			"%s：对面那台**不能**标成本机（那会让它根本不被建出来）" % tag)
		t.ok(foe[0].has_human(), "%s：对面那台是真人机体（不是 AI）" % tag)

	# ---- 王牌战**不看**你选了谁、也不看阵营 ----
	#
	# "同阵营 + 都量产机 ⇒ 同乘"是 `SHARED_PEDAL` 的判据；形式那一票是**另一件事**，
	# 先判它、且互斥 ⇒ 两人都投王牌战时它一律作废。
	var p2 := LanPlan.build(
		LanPlan.Choice.new(SuitProfile.Id.MESSER_M01, maf, duel),
		LanPlan.Choice.new(SuitProfile.Id.MESSER_M01, maf, duel))
	t.ok(p2.is_ace_duel(), "同阵营 + 都量产机，只要都投王牌战就是王牌战（不是同乘）")
	t.not_ok(p2.same_team, "……而且不会被误判成同队")

	# ---- 有一人不投 ⇒ 整条规则退回小队战那一套 ----
	var p3 := LanPlan.build(
		LanPlan.Choice.new(SuitProfile.Id.MESSER_M01, maf, duel),
		LanPlan.Choice.new(SuitProfile.Id.MESSER_M01, maf, squad))
	t.not_ok(p3.is_ace_duel(), "一人投王牌战 ⇒ 不是王牌战")
	t.ok(p3.is_shared_pedal(), "……而是按小队战的规则判（同阵营 + 都量产 ⇒ 同乘）")
	t.eq(p3.host_team.size(), BattleFormation.unit_count_per_side(), "……而且编制是满编 7 台")
	# 两票顺序调换（= 另一台机器上参数的摆法）必须得到同一个 kind
	var p4 := LanPlan.build(
		LanPlan.Choice.new(SuitProfile.Id.MESSER_M01, maf, squad),
		LanPlan.Choice.new(SuitProfile.Id.MESSER_M01, maf, duel))
	t.eq(p4.kind, p3.kind, "两票顺序调换后 kind 不变（两台机器不会各打各的）")

	# ---- 非法选择（跨阵营）在王牌战里也不再是"同队" ----
	var bad := LanPlan.Choice.new(pen, maf, duel)     # 联邦的 ACE 却选了马夫蒂
	t.not_ok(bad.is_valid(), "跨阵营的选择被判为非法")
	t.ok(LanPlan.build(bad, LanPlan.Choice.new(xi, fed, duel)).is_ace_duel(),
		"王牌战不看阵营 ⇒ 非法选择照样能打王牌战（不会掉回编制那一套）")


# ---------------------------------------------------------------- 3 联机页那一行

static func _row(t: T) -> void:
	var m := MainMenu.new()

	# ---- 行位置：**行下标只有一处真源**（轮 63-6 批 4 §六）----
	#
	# 历史：地址 / 端口那两行的下标 2 / 3 曾在 `_read_lan_input()` 与 `_input()`
	#（原始字符输入）里**各写了一遍**，插一行就得同时改两处，
	# 而"改漏一处"的症状是**那一栏收不到键盘**（页面上完全看不出来）。
	# 现在那两个下标已经被 `MainMenu.LAN_FIELD_*` + `_lan_field()` 取代 ——
	# 于是这条断言的重心从"别把下标挤走"变成"别把命名常量改回去"。
	# ⚠️ 2026-10-11（用户：「**先创建房间之后，再在房间里面决定对战模式和机体**」）：
	# 联机页**不再有「对战形式」那一行** —— 形式与机体都搬进了房间界面（`LOBBY_ROWS`）。
	# 下面这几条钉的是"搬走了"这件事本身：少了它们，谁把那一行加回来也没人拦。
	t.not_ok(str(MainMenu.LAN_ROWS).contains("对战形式"),
		"联机页**没有**「对战形式」行（形式在房间里决定）")
	t.eq(int(MainMenu.LAN_ROW_ADV), MainMenu.LAN_ROWS.size() - 1,
		"「高级」仍然是最后一行（行序没乱）")
	t.eq(MainMenu.LAN_ROWS.size(), 6,
		"联机页 6 行（建房 / 加入 / 房间号 / 密码 / 搜索 / 高级）")

	# ---- 两种形式 ----
	t.eq(MainMenu.LAN_FORMS.size(), 2, "联机只有两种形式（小队战 / 王牌战）")
	t.eq(int(MainMenu.LAN_FORMS[0]), int(LanPlan.Form.SQUAD), "下标 0 是小队战（默认）")
	t.eq(int(MainMenu.LAN_FORMS[1]), int(LanPlan.Form.ACE_DUEL), "下标 1 是王牌战")
	t.eq(int(m.get("lan_form_choice")), 0, "默认停在**小队战**上（这一项不存在之前的行为）")
	for i in MainMenu.LAN_FORMS.size():
		m.set("lan_form_choice", i)
		var form := m.selected_lan_form()
		t.eq(form, int(MainMenu.LAN_FORMS[i]), "选中第 %d 项 ⇒ 形式就是它" % i)
		t.gt(float(MainMenu.lan_form_label(form).length()), 0.0, "第 %d 项有显示名" % i)
	# 越界的下标要钳住（不要取到"最后一个"之外的怪值）
	m.set("lan_form_choice", 99)
	t.eq(m.selected_lan_form(), int(MainMenu.LAN_FORMS[MainMenu.LAN_FORMS.size() - 1]),
		"越界下标钳到最后一项")
	m.set("lan_form_choice", 0)

	# 两个显示名必须**各不相同**且各自带关键词（写错一个就分不出哪种形式）
	var l0 := MainMenu.lan_form_label(LanPlan.Form.SQUAD)
	var l1 := MainMenu.lan_form_label(LanPlan.Form.ACE_DUEL)
	t.not_ok(l0 == l1, "两种形式的显示名不一样")
	t.ok(l0.contains("小队战"), "小队战那一项的显示名带「小队战」")
	t.ok(l1.contains("王牌战"), "王牌战那一项的显示名带「王牌战」")

	# ---- 出击闸门：三样选择**都到齐** + 连上 ----
	#
	# ⚠️ 少任何一样都会让 `LanPlan` 退到兜底值 ⇒ 两台机器各算出一局不同的对局。
	# 这就是"这一条断言为什么必须逐个字段钉"。
	# 判据本体是 `NetSession.launch_ready()`（纯 static）—— 菜单与网络层都只调它，
	# 不各写一份（两份分家正是那条静默失败最常见的来源）。
	t.not_ok(Net.launch_ready(false, 0, 0, 0), "没连上 ⇒ 不能出击")
	t.not_ok(Net.launch_ready(true, -1, 0, 0), "对面的机体还没到 ⇒ 不能出击")
	t.not_ok(Net.launch_ready(true, 0, -1, 0), "对面的阵营还没到 ⇒ 不能出击")
	t.not_ok(Net.launch_ready(true, 0, 0, -1),
		"对面的**形式**还没到 ⇒ 不能出击（丢了这一条 = 两台机器各打各的）")
	t.ok(Net.launch_ready(true, 0, 0, 0), "三样都到齐 + 连上了 ⇒ 可以出击")
	t.ok(Net.launch_ready(true, SuitProfile.Id.XI, BattleFormation.Side.MAFTY,
		LanPlan.Form.ACE_DUEL), "王牌战形态下同样成立（形式是 1 不是 −1）")

	# ---- 本机那一票怎么交给网络层 ----
	#
	# ⚠️ 必须还原：`Net` 是 autoload，`_choice` 会**跨套件**留着 ——
	# 污染它会让 `suite_lan_spawn` 那几条（靠 `_choice` 为空而退回 `Game.*`）静默变红。
	var saved: Dictionary = Net.get("_choice")
	Net.announce_choice(SuitProfile.Id.XI, BattleFormation.Side.MAFTY, LanPlan.Form.ACE_DUEL)
	t.eq(Net.choice_of("suit", -1), int(SuitProfile.Id.XI), "本机「机体」那一票读得出来")
	t.eq(Net.choice_of("side", -1), int(BattleFormation.Side.MAFTY), "本机「阵营」那一票读得出来")
	t.eq(Net.choice_of("form", -1), int(LanPlan.Form.ACE_DUEL), "本机「形式」那一票读得出来")
	t.eq(Net.choice_of("nope", 7), 7, "没有这一项时退回兜底值（不走菜单的路径靠它）")
	Net.set("_choice", saved)

	m.queue_free()


# ---------------------------------------------------------------- 4 真撒一局

## 走**真正的开局入口** `_on_start_match()`（玩家机体是开局流程里建的，
## 跳过它只会得到 `player == null`），然后数场上到底有几台。
##
## ⚠️ 两台机器才能验的部分（另一台机器上 `local_is_host` 的另一半）**不在这里** ——
## 那一半在 `_roster()` 里用"同一份名单翻 `local_is_host`"验。
static func _spawn(t: T, host: Node) -> void:
	# 先把全局状态记下来，结束时**逐项还原**（autoload 会跨套件留着）
	var saved_choice: Dictionary = Net.get("_choice")
	var saved_role: int = Net.role
	var saved_team: int = Net.local_team
	var saved_suit: int = Net.remote_suit
	var saved_side: int = Net.remote_side
	var saved_form: int = Net.remote_form

	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(m)
	await host.get_tree().physics_frame

	# 手工摆出"两人都选了王牌战"：本机（主机）开柯西，对面开佩涅罗佩。
	Game.match_mode = Game.MatchMode.LAN
	Game.active_suit = SuitProfile.Id.XI
	Game.active_side = BattleFormation.Side.MAFTY
	Game.active_lan_form = LanPlan.Form.ACE_DUEL
	Net.role = Net.Role.HOST
	Net.local_team = 0
	Net.remote_suit = SuitProfile.Id.PENELOPE
	Net.remote_side = BattleFormation.Side.FEDERATION
	Net.remote_form = LanPlan.Form.ACE_DUEL
	Net.announce_choice(SuitProfile.Id.XI, BattleFormation.Side.MAFTY, LanPlan.Form.ACE_DUEL)

	var plan: LanPlan.Plan = m.call("_lan_plan_now")
	t.ok(plan != null, "算出了部署方案")
	if plan == null:
		m.queue_free()
		return
	t.ok(plan.is_ace_duel(), "两人都选王牌战 ⇒ 这一局是王牌战")

	m.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.OENBELLI, Game.MatchMode.LAN, -1)
	for i in 14:
		await host.get_tree().physics_frame

	# ---- 编制规模：1（不是 7）----
	t.eq(Game.squad_units_per_side, 1, "王牌战的编制规模 = 1（不是小队战的 7）")

	# ---- 场上就两台 ----
	var mine := 0
	var foe := 0
	var proxies := 0
	var aces := 0
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if u.get("team") == 0:
			mine += 1
		elif u.get("team") == 1:
			foe += 1
		if u is NetProxyBody:
			proxies += 1
		if u.has_method("has_pedal") and u.has_pedal():
			aces += 1      # 王牌战里**没有踏板**，这个数必须是 0
	t.eq(mine, 1, "我方一台（就是本机自己）—— 没有僚机")
	t.eq(foe, 1, "对面一台（就是远端那位玩家）—— 没有 AI 僚机也没有 AI ACE")
	t.eq(proxies, 1, "对面那台是 `NetProxyBody`（不是 AI 敌机）")
	t.eq(aces, 0, "王牌战里一块飞行踏板都没有（没有编制就没有板）")
	t.eq(m.get("remote_proxies").size(), 1, "只建了一台远端代理（多一台就会多一个敌人）")

	# ---- 两台开的是**各自选的机** ----
	t.ok(m.player != null, "玩家机体建出来了")
	if m.player != null:
		t.eq(m.player.profile.id, SuitProfile.Id.XI, "本机开的是本机选的柯西")
	var proxies_arr: Array = m.get("remote_proxies")
	if proxies_arr.size() >= 1:
		var proxy: NetProxyBody = proxies_arr[0]
		t.eq(proxy.profile.id, SuitProfile.Id.PENELOPE, "对面那台开的是对面选的佩涅罗佩")
		t.eq(proxy.team, 1, "对面那台是敌对阵营（team 1）")
		t.not_ok(proxy.is_carried(), "对面那台没被谁载着（王牌战不是同乘）")

	m.queue_free()
	await host.get_tree().physics_frame
	Game.reset()

	# ---- 还原全局状态（autoload 会跨套件留着）----
	Net.set("_choice", saved_choice)
	Net.role = saved_role
	Net.local_team = saved_team
	Net.remote_suit = saved_suit
	Net.remote_side = saved_side
	Net.remote_form = saved_form


# ---------------------------------------------------------------- 5 跨文件接线

static func _wiring(t: T) -> void:
	var plan_src := SuiteUiStyle._code("scripts/data/lan_plan.gd")
	var menu_src := SuiteUiStyle._code("scripts/ui/main_menu.gd")
	var main_src := SuiteUiStyle._code("scripts/main.gd")
	var net_src := SuiteUiStyle._code("scripts/autoload/net_session.gd")

	# ---- ① `spawn_lan()` 必须先判王牌战 ----
	#
	# 它是"按编制撒人"那条路的**例外**：不先判就会按 3 编队 × 2 台 + 1 ACE
	# 撒出 7 台（对面 7 台），而王牌战只有一台 —— 而且这不会报任何错。
	var spawn_body := SuiteMenuFrame._func_body(main_src, "func spawn_lan(")
	t.ok(spawn_body.contains("is_ace_duel()"), "`spawn_lan()` 里王牌战**先判**")
	t.ok(spawn_body.contains("_spawn_lan_duel("), "         …并交给 `_spawn_lan_duel()`")
	t.ok(spawn_body.contains("_wire_net("), "         …两条形式共用 `_wire_net()`（网络接线只有一份）")
	var duel_body := SuiteMenuFrame._func_body(main_src, "func _spawn_lan_duel(")
	t.ok(duel_body.contains("enemy_lineup()"),
		"`_spawn_lan_duel()` 撒的是 `enemy_lineup()`（座位号已重标成远端）")
	t.ok(duel_body.contains("squad_units_per_side = 1"), "         …并把编制规模改成 1")

	# ---- ② 两台机器算同一局：本机那一票走 `Net.choice_of()` ----
	var plan_body := SuiteMenuFrame._func_body(main_src, "func _lan_plan_now(")
	t.ok(plan_body.contains("Net.choice_of("),
		"`_lan_plan_now()` 读本机那一票走 `Net.choice_of()`（= 真的发出去的那一份）")
	t.not_ok(plan_body.contains("Choice.new(Game.active_suit, Game.active_side"),
		"         …不再直接拿 `Game.*` 组本机那一票（联机这条路里它没人写过）")
	t.ok(plan_body.contains("plan.local_is_host ="),
		"         …王牌战里把它自己是不是主机写进方案（`local_is_host`）")
	t.ok(net_src.contains("func choice_of("), "`NetSession.choice_of()` 存在（本机那一票的唯一真源）")

	# ---- ③ 出击那一刻把形式落进 `Game` ----
	t.ok(SuiteMenuFrame._func_body(menu_src, "func _launch(").contains("Game.active_lan_form ="),
		"菜单出击时把选中的形式落进 `Game.active_lan_form`")

	# ---- ④ 等待态：出击判据是"选择到齐"，退出判据是**角色** ----
	var lan_body := SuiteMenuFrame._func_body(menu_src, "func _read_lan_room_input(")
	t.ok(lan_body.contains("Net.start_committed"), "准备房间仅在主机提交后出击")
	# ★63-9 · B2（联机等待态加退出与超时）把这段次序本体抽成了
	# `NetSession.wait_exit()`（纯 static、可单测）⇒ **「退出判据是角色」这句话的
	# 真源搬到了 `net_session.gd`**。这条断言跟着搬，**原意一字不改**：
	# 仍然盯「判据是角色、不是 `is_online()`」，只是分两处量 ——
	# 页面那侧负责把 `Net.role` 喂进去、且不许自己用 `is_online()`；
	# 次序本体那侧负责真的比 `Role.NONE`。
	# （不跟着搬的话，这条断言会在下一个反射重构里变成假红 —— 本轮就是这么发现它的）
	t.ok(lan_body.contains("Net.role"),
		"等待态把 `Net.role`（**角色**）喂进退出判定")
	t.not_ok(lan_body.contains("is_online()"),
		"⚠️ 页面这侧**不许**拿 `is_online()` 当退出判据"
			+ "（peer 已建、还没握手那一帧它也是 false）")
	var wait_body := SuiteMenuFrame._func_body(net_src, "static func wait_exit(")
	t.gt(wait_body.length(), 200,
		"取到了 `NetSession.wait_exit()` 的函数体（%d 字符）" % wait_body.length())
	t.ok(wait_body.contains("role_now == Role.NONE"),
		"★ 退出判据的真源 = `wait_exit()` 里的 `role_now == Role.NONE`")
	t.not_ok(wait_body.contains("is_online()"),
		"★ 次序本体那侧也不许出现 `is_online()`")
	# 规则本体只有一份：`NetSession.launch_ready()`（纯 static ⇒ 可单测）；
	# `choices_ready()` 只是把本机状态填进去，菜单只调不重写。
	t.ok(net_src.contains("static func launch_ready("), "规则本体在 `NetSession.launch_ready()`（纯 static）")
	var ready_body := SuiteMenuFrame._func_body(net_src, "func choices_ready(")
	t.ok(ready_body.contains("launch_ready(is_online(), remote_suit, remote_side, remote_form)"),
		"`choices_ready()` 是那条规则 + 本机状态（不是第二份判断）")
	# 菜单那一头**不许**再有一份自己的判断（历史形态就是一份 `_lan_can_launch()`）：
	# 两份判断分家 = "判据少一样 ⇒ 退到兜底值 ⇒ 两台机器各算一局、两边都不报错"。
	t.not_ok(menu_src.contains("func _lan_can_launch("),
		"菜单里没有第二份出击判断（`_lan_can_launch()` 已删，只留 `Net.choices_ready()`）")
	t.ok(SuiteMenuFrame._func_body(menu_src, "func _launch(").contains("Net.choice_of("),
		"菜单不直读 `Net.remote_*` 拼规则（本机状态由 `choices_ready()` 自己填）")
	# 形式那一条握手 RPC 是**分开的一条**（老协议不能被塞进带默认值的新字段）
	t.ok(net_src.contains("func _rpc_hello_form("), "形式是**单独一条**握手 RPC")
	t.ok(net_src.contains("func announce_choice("), "菜单写选择走 `announce_choice()`")
	t.ok(net_src.contains("_send_hello()"), "         …加入方也主动握手（不能只等主机的）")
	# `close()` **不许**清 `_choice`：`host_game()` 第一件事就是调它
	var close_body := SuiteMenuFrame._func_body(net_src, "func close(")
	t.not_ok(close_body.contains("_choice.clear()"),
		"`close()` 不清 `_choice`（`host_game()` 第一件事就是调它）")

	# ---- ⑤ 投票规则只有一份 ----
	t.ok(plan_src.contains("static func resolve_form("), "投票规则在 `LanPlan.resolve_form()`")
	for pair: Array in [["scripts/ui/main_menu.gd", menu_src], ["scripts/main.gd", main_src]]:
		t.not_ok(str(pair[1]).contains("Form.ACE_DUEL and"),
			"%s 没有再写一份投票规则（唯一真源是 `resolve_form()`）" % str(pair[0]))
	# `is_ace_duel()` 是"这一局是不是王牌战"的唯一判据（不许拿 `kind ==` 直接比）
	t.not_ok(main_src.contains("kind == LanPlan.Kind.ACE_DUEL"),
		"`main` 里用 `is_ace_duel()` 而不是直接比 `kind`（判据只留一个名字）")
