class_name LanPlan
extends RefCounted
## **多人（局域网）对局部署规则** —— 用户 2026-09-21 定的玩法。
##
## ## 规则原文（用户原话，逐条落到代码）
## > 「玩家可以选择王牌机对战；也可以选择小队模式。小队模式如果选择**统一阵营**的情况下，
## > 又都选择了**量产机**，那就**一起乘坐同一台踏板出击**，系统补一个 AI ACE。
## > 如果没有都选择量产机，那么都做选择量产机的正常出战，选择王牌机的也正常出战。
## > 如果没有选择同一阵营也没有选择都选择量产机，就正常王牌机对打。」
##
## 整理成一句话：**只有"同一阵营 + 两人都挑量产机"这一种情况才会同乘**，
## 其余全部按常规出战。于是四种组合里只有一种是特例：
##
## | 阵营 | 两人机体 | 结果 |
## |---|---|---|
## | **同阵营** | **都是量产机** | **同乘一块踏板**（主机驾驶 / 加入方后座）＋ 对面补 AI ACE |
## | 同阵营 | 有一人选了 ACE | 各自正常出战（选量产机的正常骑板，选 ACE 的正常单飞） |
## | 不同阵营 | 任意 | 正常王牌机对打 |
##
## ## 对战形式（本轮补上的那一半）
## 上面那张表是**小队战**（`Form.SQUAD`）内部的规则。用户原话第一句
##「玩家可以选择**王牌机对战**；也可以选择小队模式」里的**王牌战**（`Form.ACE_DUEL`）
## 原来是缺的 —— 那时联机只有小队战一种形态。现在两人都选「王牌战」就进这一形态：
## **一人一台、没有编制、没有僚机**，与单机的王牌战（`MatchMode.VERSUS`）同一件事。
##
## ⚠️ 两个形态**不能混着算**：形式由 `resolve_form()` 从两人的票算出，两台机器结果必然相同
##（理由见那个函数）。王牌战里不看阵营、不看是不是量产机。
##
## ## 为什么"同乘"必须限定在同一阵营
## 同乘的两个人**在同一块板上、同一个队里**。不同阵营的两个人当然不可能坐同一块板 ——
## 而"同一阵营"也正是"对面需要补一个 AI ACE"的原因：两人同队 ⇒ 对面没有真人 ⇒
## 必须有个东西可打，否则这一局没有对手。
##
## ## 每边的编制是恒定的
## 沿用 `BattleFormation` 的编制：每边 **3 个量产编队 × 2 台 + 1 台 ACE**。
## 两个真人玩家**占掉自己那一边的两个槽位**（不是额外加人）：
##   - 同乘时：主机 = 0 号编队领机（slot 0，**他驾驶**），加入方 = 0 号编队后座（slot 1）；
##   - 否则：两人各占一个量产编队领机位（或各自占 ACE 位，如果他们选的是 ACE）。
## 于是"编制"依旧是恒定的、可断言的 —— 玩家选什么机不会改编制平衡。

## 部署形态。
enum Kind {
	## 正常王牌机对打（不同阵营，或同阵营但有人选 ACE）。
	VERSUS,
	## 同阵营 + 都是量产机 ⇒ 两人同乘一块踏板。
	SHARED_PEDAL,
	## **王牌战**：两人各一台、**没有编制也没有僚机**，纯 1v1。
	##
	## 由**对战形式**这一个显式选择决定（见 `Form` / `resolve_form()`），
	## **不再看两人选了什么机体** —— 那是 `VERSUS` / `SHARED_PEDAL` 的判据。
	## 也就是说：两人都选量产机、都选同阵营，也可以打王牌战。
	ACE_DUEL,
}

## **对战形式** —— 用户 2026-09-21 那句原话里的两半：
## > 「玩家可以选择**王牌机对战**；也可以选择**小队模式**。」
##
## ⚠️ **下标 0 必须是 `SQUAD`**：`Choice.form` 的默认值就是它。
## 理由：1.2 起联机只有小队战这一种形态，默认值必须让"没传 form 的路径"
## **逐位保持原行为** —— `suite_lan_plan` / `suite_lan_spawn` 里那些老用例
##（`Choice.new(suit, side)` 两参数）就是这条的判据。
enum Form { SQUAD, ACE_DUEL }

## 两人各选一种形式之后，**这一局实际打哪一种**。
##
## ⚠️ 规则是「**两人都选王牌战，才是王牌战**；否则小队战」。不是"任一人选就生效"，
## 也不是"以主机为准" —— 后两种规则都要用到"谁是主机"，而两台机器上这个答案
## 正好相反：**只要有一台没收到对方的选择**（或者两人选得不一样），
## 两台机器就会各打各的（一边场上 2 台、另一边 14 台），**而两边都不报错**。
## 这正是本设计反复提防的那类静默失败。
##
## 现在这条规则只依赖"两人的选择"这两个数，与"谁是主机"无关 ⇒ **不可能分叉**。
## 菜单与 `main` 都只调它，谁也不许自己再写一份判断。
static func resolve_form(a: int, b: int) -> int:
	return Form.ACE_DUEL if (a == Form.ACE_DUEL and b == Form.ACE_DUEL) else Form.SQUAD


## 一个玩家在这一局里的选择。
class Choice extends RefCounted:
	var suit: int = SuitProfile.Id.XI
	## 阵营（`BattleFormation.Side`）。−1 = 还没选。
	var side := -1
	## 他选的**对战形式**（`Form`）。⚠️ 这只是**他自己那一票**，
	## "这一局实际打哪种"由两人的票算出 —— 见 `resolve_form()`。
	##
	## ⚠️ 这里写 `Form.SQUAD`（**光名字**，不写 `LanPlan.Form`）：
	## 嵌套类按 `class_name` 引用**外层类名**在 GDScript 里编译不过
	##（本工程实测过，见 `mission_script.gd` 里 `Mission.map_id()` 的注释）；
	## 外层枚举对嵌套类是可见的。
	var form: int = Form.SQUAD

	func _init(s := SuitProfile.Id.XI, sd := -1, f := Form.SQUAD) -> void:
		suit = s
		side = sd
		form = f

	## 他选的是不是**量产机**（按"阵营编制里的 mass_production"判，不是靠 id 猜）。
	func is_mass_production() -> bool:
		if side < 0:
			return false
		return BattleFormation.roster_of(side).mass_production.has(suit)

	## 他的机体**属于他选的那个阵营**吗 —— 跨阵营的选择一律不算数（见 `belongs_to`）。
	func is_valid() -> bool:
		return side >= 0 and BattleFormation.belongs_to(side, suit)


## 一局多人对局的完整部署方案。
class Plan extends RefCounted:
	var kind: int = Kind.VERSUS
	## **这一局实际打哪一种形式**（`Form`）。
	##
	## ⚠️ 注意它是**两人投票的结果**（`resolve_form()`），不是"本机选的那个"。
	## 两台机器各自算一遍 `Plan`，这个字段必然相同 —— 出生之后再改就得重建整场，
	## 所以"两台机器必须对打哪种达成一致"这件事，只能靠**算法**保证。
	var form: int = Form.SQUAD
	## 两人是不是同队（同阵营）。同队 ⇒ 对面只有 AI。
	var same_team := false
	## 同乘时**由谁驾驶**：0 = 主机（host），1 = 加入方。非 `SHARED_PEDAL` 时忽略。
	var pilot_is_host := true
	## 主机 / 加入方各自的阵营（`BattleFormation.Side`）。
	var host_side := BattleFormation.Side.MAFTY
	var client_side := BattleFormation.Side.FEDERATION
	## 两边的出战名单（`Array[BattleFormation.Unit]`）。
	## 主机与加入方在**自己那一边**的名单里已经被标成 `owner_is_player` / `owner_is_client`。
	var host_team: Array = []
	var client_team: Array = []

	func is_shared_pedal() -> bool:
		return kind == Kind.SHARED_PEDAL

	## 这一局是不是**王牌战**（两人各一台、没有编制也没有僚机）。
	func is_ace_duel() -> bool:
		return kind == Kind.ACE_DUEL

	## 人类玩家一共几个（恒为 2：这一局就是两个人打的）。
	func human_count() -> int:
		return 2

	## **本机是不是主机**（`Net.local_team == 0`）。`spawn_lan()` 用它选名单。
	## 这个字段由 `build()` 之外的调用方设置（`main` 知道本机是哪一边）。
	var local_is_host := true

	## 本机那一边的名单。
	func local_team() -> Array:
		return host_team if local_is_host else client_team

	## 对面（敌人）那一边的名单。
	##
	## ⚠️ **不能拿 `client_team` 当对面**：同队时两份名单都是玩家这边
	##（两台机器各自的视角），对面得另算 —— 见 `foe_team()`。
	func foe_team() -> Array:
		return client_team if local_is_host else host_team

	## 对面的阵营。
	func foe_side() -> int:
		return client_side if local_is_host else host_side

	## 对面的**完整 AI 名单**（同队时用它：对面全是 AI，含恰好一台 ACE）。
	##
	## 同队时 `foe_team()` 那份名单里其实也有"远端玩家的标记"（那是给另一台机器看的），
	## 而本机这边**对面一台真人都没有** —— 所以按"敌阵营 + 没有真人"重新生成一份。
	##
	## ⚠️ **不同队时不要用它取"对面"**：那会把两个真人（我 + 远端）都放进同一份名单，
	## 于是对面出现两台 `owner_is_client` 的代理（探针实测：`remote_proxies` 给了 2 个）。
	## 对面在本机名单里就是 `foe_team()` —— 它里面**只标了远端那一个**。
	##
	## ⚠️ **王牌战**（`is_ace_duel()`）是第三种情形：对面就**那一个真人**、也只有一台。
	## 它必须在这里**重新标座位号**（1 = 远端 ⇒ `owner_is_client`），
	## 不能直接把 `foe_team()` 交出去 —— 见下面的实现说明。
	func enemy_lineup() -> Array:
		if is_ace_duel():
			return _duel_foe_lineup()
		return BattleFormation.lineup(foe_side(), -1) if same_team else foe_team()

	## 王牌战里"对面那台"的名单（**一台**）。
	##
	## ⚠️ 必须重标座位号，理由是 `main._spawn_side()` 的一条硬规则：
	## 它见到 `owner_is_player`（座位 0）就**跳过不建**（那条是给"本机自己那台
	## 已经在 `spawn_round()` 里建好了"写的）。而 `host_team` / `client_team` 里的
	## 0 号位恰恰是"**那份名单的主人**"——直接把它当对面撒出去，
	## 表现是**对面那台在场上根本不存在**：不报错、没有日志，只是打不到人。
	func _duel_foe_lineup() -> Array:
		var src: Array = client_team if local_is_host else host_team
		var out: Array = []
		for u: BattleFormation.Unit in src:
			var v := BattleFormation.Unit.new(u.suit, true, -1, 0)
			v.set_human_seat(1)
			out.append(v)
		return out


## **规则本体**：两个人的选择 → 一份部署方案。
##
## 纯函数（不读全局、不碰场景）⇒ 可以直接单测，测试见 `suite_lan_plan`。
##
## ## ⚠️ "同队"的定义：同阵营 **且** 两人的机体都在那个阵营的池子里
## 这一条是**踩出来**的：菜单给玩家列的机体表（`MainMenu.SUITS`）是**三台 ACE 不分阵营**，
## 而"联邦的 ACE（佩涅罗佩）"并不在"马夫蒂"的编制池子里。
## 于是"两人都选马夫蒂、但客户端选佩涅罗佩"这种情况，在编制层是**自相矛盾**的：
## 客户端那台不属于它自己选的阵营。
## 第一版没管这件事，结果 `_lineup_two()` 里 `me.is_valid()` 为假、
## 客户端被当成量产机兜底，一份名单里冒出两台"本机机体"（被断言当场拦下）。
##
## 处置：**同队要求机体也同阵营**（`Choice.is_valid()`）。不满足就退回"正常对打"——
## 与用户那句"如果没有选择同一阵营也没有选择都选择量产机，就正常王牌机对打"一致。
## 菜单侧另有一条（`BattleFormation.belongs_to`）保证不会给出跨阵营的选择。
static func build(host: Choice, client: Choice) -> Plan:
	var p := Plan.new()
	p.host_side = host.side if host.side >= 0 else BattleFormation.Side.MAFTY
	p.client_side = client.side if client.side >= 0 else BattleFormation.Side.FEDERATION
	p.same_team = host.is_valid() and client.is_valid() and host.side == client.side
	# ---- 第一条分支：**两人都选了王牌战** ⇒ 王牌战（一人一台，没有编制）----
	#
	# ⚠️ 它与下面两条是**互斥**的，所以必须先判它：王牌战里"同阵营 / 量产机"统统不作数 ——
	# 两人各开一台单挑，"同队"这件事压根没有意义（所以 `same_team` 强制为假，
	# 免得"两人恰好选了同一阵营的机"被下游当成队友：那时对面会一台敌机都没有）。
	p.form = resolve_form(host.form, client.form)
	if p.form == Form.ACE_DUEL:
		p.kind = Kind.ACE_DUEL
		p.same_team = false
		# 两份名单各只有"这份名单的主人"那一台（座位号 0）。
		# "对面那台"由 `enemy_lineup()` 现标成座位 1 —— 不在这里混进名单，
		# 是为了让"我方名单"和"对面名单"各自只有一种含义。
		p.host_team = [_duel_unit(host.suit, 0)]
		p.client_team = [_duel_unit(client.suit, 0)]
		return p
	# ---- 唯一的特例：同阵营 + 两人都是量产机 ⇒ 同乘 ----
	if p.same_team and host.is_mass_production() and client.is_mass_production():
		p.kind = Kind.SHARED_PEDAL
		p.pilot_is_host = true          # 用户选的是"主机驾驶、加入方后座"
	else:
		p.kind = Kind.VERSUS
	# ---- 名单 ----
	#
	# ## ⚠️ 每一份名单都要同时表达**两台机器上的信息**
	# `Plan` 会被**两台机器各用一次**，所以一份名单必须能让两台都找到各自的机体：
	#   - `me`（0 号真人）= **本机** → `set_human_seat(0)` → `owner_is_player`
	#   - `foe`（1 号真人）= **对面那个真人** → `set_human_seat(1)` → `owner_is_client`
	#
	# 不同队时每边只有一个真人：**自己那一边**的名单里
	#   `me` = 我、`foe` = 对面那台的代理（它在我这份名单里是敌人，但归真人开）。
	# 这个 `foe` 参数就是第一版缺的那一块 —— 少了它，`spawn_lan()`
	# 在两份名单里都找不到"对面那台"，于是**代理机体根本建不出来**
	#（探针实测：`remote_proxies` 是空的）。
	#
	# 同队时两人同阵营，`foe` 就是我们自己这边的另一个人（队友代理）。
	p.host_team = _lineup_two(p.host_side, host, client, p.same_team,
		p.is_shared_pedal(), client.side != p.host_side)
	p.client_team = _lineup_two(p.client_side, client, host, p.same_team,
		p.is_shared_pedal(), host.side != p.client_side)
	return p


## **某一边、没有真人**的一份标准名单（用于"对面"）。
##
## 就是 `BattleFormation.lineup(side, -1)` 的语义：全部归 AI。
## 单独开一个入口是为了让"对面"这件事**只有一种写法** ——
## 测试与 `main` 都调它，免得有人自己拼一份"差不多的名单"出来（那正是跨阵营混编的来源）。
static func lineup_for(side: int, _unused: Choice = null) -> Array:
	return BattleFormation.lineup(side, -1)


## 王牌战里"某一边"的一台机体（座位号由参数给：0 = 这份名单的主人、1 = 远端）。
##
## ⚠️ `is_ace = true`：这一位**不骑飞行踏板**（`main._spawn_side()` 按它决定要不要挂板）。
## 王牌战里两人都是一人一机自己飞，谁也不该被塞进某个编队 ——
## 传 `false` 会让下游去找"他属于哪个编队 / 谁的板载着他"，那是小队战才有的结构。
static func _duel_unit(suit_id: int, seat: int) -> BattleFormation.Unit:
	var u := BattleFormation.Unit.new(suit_id, true, -1, 0)
	u.set_human_seat(seat)
	return u


## 生成**某一边**的名单（本机视角）。
## ⚠️ 这里**不调用 `BattleFormation.lineup()`**：那个函数只支持"一边一个玩家"，
## 而本项的核心恰恰是"一边可能有**两个**玩家"（同队时本机 + 远端代理）。
## 编制规模、槽位顺序、ACE 兜底规则都照抄它，玩家占位改成"按两个玩家的选择各占一个槽"。
##
## [param me] = **本机**（这份名单是它的机器看的）→ 座位号 0；
## [param other] = 另一个真人 → 座位号 1。
## [param other_absent] = `true` 表示另一个真人在**对面**（两人不同阵营）：
##   他不在"我这边"的编制里，但**他在我这份名单里确实要出现** ——
##   以"对面那台代理机体"的身份。缺了这个参数，两份名单里都没有一台标着
##   `owner_is_client`，`spawn_lan()` 于是**建不出远端代理**
##（探针实测：`remote_proxies` 是空的）。
static func _lineup_two(side: int, me: Choice, other: Choice,
		same_team: bool, shared: bool, other_absent: bool) -> Array:
	var r := BattleFormation.roster_of(side)
	var out: Array = []
	# 这一边有几个真人玩家：同队时两个都在这一边，否则只有 `me`。
	# ⚠️ **顺序固定为 [本机, 远端]** —— `_occupant_at()` 返回的下标就是按它算的，
	# 而"谁是本机"由**参数位置**决定：`me` 恒为本机（见函数头）。
	var humans: Array = [me]
	if same_team:
		humans.append(other)

	# ---- 先把"真人各坐哪个槽"排出来 ----
	# ⚠️ **座位号必须显式写出来，不能靠数组下标暗示**（这是踩过的坑）：
	# 两个人的先后顺序在**两台机器上是不一样的** ——
	# 主机那份名单里「主机、客户端」，客户端那份里「客户端、主机」。
	# 第一版用 `mp_seats[i]` 的下标当座位号，于是客户端的名单里
	# "远端（主机）"落在 `mp_seats[1]`，被"只有同乘的第 1 项才是后座"那条规则排除掉，
	# 表现是**主机那台机凭空消失**（名单少一台，且 `me` 之外的那个人完全没被排进去）。
	# 现在每一项都是 `[座位号, 编队号]`，座位号由**人**决定，不由顺序决定。
	var seats: Array = []                 # 每项 = [seat(0=本机/1=远端), squad]
	var ace_owner := -1                   # 真人里选 ACE 那一位的**座位号**（−1 = 没有）
	# ⚠️ **编队号由座位号决定，不能按"第几个被排到"递增**：
	# 同队时两台机器上"我 / 远端"的顺序是**反的**（`humans` 的 0 号是自己的机器），
	# 按顺序递增会让两边算出**不同的名单** —— 一台机器把远端放在 0 号编队、
	# 另一台放在 1 号，于是"谁和谁一块板"对不上，代理机体也会被挤掉。
	# 判据（`suite_lan_plan`）：同队的同一份编制，在两台机器上必须一致。
	#
	# 约定：
	#   - 非 ACE 的本机真人 → **0 号编队领机**；
	#   - 非 ACE 的远端真人 → 同乘时 **0 号编队后座**（一块板载两台）；
	#                        各自出战时 **1 号编队领机**；
	#   - "对面那个真人"（不同队时在本方名单里的代理槽）→ **2 号编队领机**。
	var fo_seat := -1                     # 这份名单里"对面那个真人"的座位（−1 = 不在）
	for i in humans.size():
		var c: Choice = humans[i]
		var seat := i                     # `humans` 的顺序：0 = 本机、1 = 远端
		if c.is_valid() and r.aces.has(c.suit):
			if ace_owner < 0:
				ace_owner = seat
			continue
		# 量产机（或非法选择 ⇒ 按量产机兜底）
		if shared and seat == 1:
			seats.append([seat, 0])       # 同乘的后座：与领机同一个编队（0 号）
		else:
			seats.append([seat, seat])    # 本机 → 0 号；远端 → 1 号
	# **另一个真人在对面**（不同队）：他占 **2 号编队的领机位** ——
	# 那正是他在**这份名单里**的代理机体该站的地方。
	#
	# ⚠️ 这里必须**补进 `seats`**，否则这份名单里一台 `owner_is_client` 都没有，
	# 代理机体就建不出来（玩家视角下"对面那台机凭空消失"）。
	if other_absent:
		var foe_sq := 2
		fo_seat = 1
		seats.append([fo_seat, foe_sq])

	# ---- 三组量产编队 ----
	for sq in BattleFormation.SQUADS_PER_SIDE:
		for sl in BattleFormation.UNITS_PER_SQUAD:
			var occupant := _occupant_at(sq, sl, seats, shared)
			if occupant >= 0:
				var seat := occupant
				# 机体按"开它的那个人"给：0 = 本机（`humans[0]`）、
				# 1 = 远端（同队时 `humans[1]`；不同队时就是**对面那个真人** `other`）。
				var suit: int
				if seat == 1 and other_absent:
					suit = other.suit if other.is_valid() else r.mp()
				else:
					var c: Choice = humans[seat]
					suit = c.suit if c.is_valid() else r.mp()
				var u := BattleFormation.Unit.new(suit, false, sq, sl)
				# ⚠️ 标"归谁开"必须**核对机体 id**（照抄 `BattleFormation._mark_player`
				# 的教训 —— 第一版只看槽位，结果敌人的 0 号位被标成玩家、整台不建）。
				# 座位号用 `set_human_seat()` 写，它同时维护那两个派生布尔量。
				u.set_human_seat(seat)
				out.append(u)
			else:
				out.append(BattleFormation.Unit.new(r.mp(), false, sq, sl))
	# ---- ACE ----
	for i in BattleFormation.ACES_PER_SIDE:
		if ace_owner >= 0:
			var c2: Choice = humans[ace_owner]
			var u2 := BattleFormation.Unit.new(c2.suit, true, -1, 0)
			u2.set_human_seat(ace_owner)
			out.append(u2)
		elif other_absent and other.is_valid() and r.aces.has(other.suit):
			# 对面那个真人开的是本阵营的 ACE ⇒ 这台 ACE 归他（代理机体占这个槽）
			var u3 := BattleFormation.Unit.new(other.suit, true, -1, 0)
			u3.set_human_seat(1)
			out.append(u3)
		else:
			# ⚠️ **同阵营兜底**：补进来的 ACE 必须来自**这一边**的阵营
			#（老板 2026-09-21：「每个系统补充的王牌机只能是同阵营的」）。
			# 这一条在 `BattleFormation.lineup()` 里也有一份，规则同源。
			out.append(BattleFormation.Unit.new(r.ace(), true, -1, 0))
	# 占位判定用的是"0 号 = 本机"（`humans` 的顺序约定，见函数头）。
	# 这里留一个断言式的自检：**一份名单里最多一个本机标记** ——
	# 多了就会"多建一台自有玩家机体"（第一版就是这么错的，靠这条自检抓住）。
	var mine := 0
	for u3: BattleFormation.Unit in out:
		if u3.is_local_human():
			mine += 1
	assert(mine <= 1, "一份名单里最多只能标一台'本机机体'")
	return out


## 某个量产槽位由**哪个真人**坐（−1 = 没人坐，留给 AI）。返回的是**座位号**。
##
## [param seats] 每项 = `[座位号, 编队号]`（座位号 0 = 本机、1 = 远端）。
##
## 同乘时：0 号编队的 slot 0 归领机（本机）、slot 1 归后座（远端）。
## 否则：每个被占编队的领机位（slot 0）坐一个真人，后座留给 AI。
static func _occupant_at(sq: int, sl: int, seats: Array, shared: bool) -> int:
	for item: Array in seats:
		var seat: int = item[0]
		var seat_squad: int = item[1]
		if seat_squad != sq:
			continue
		if shared:
			# 同乘：seat 0（本机 / 驾驶）坐 slot 0，seat 1（远端 / 后座）坐 slot 1
			if (seat == 0 and sl == 0) or (seat == 1 and sl == 1):
				return seat
		elif sl == 0:
			return seat
	return -1
