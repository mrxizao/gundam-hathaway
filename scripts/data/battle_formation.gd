class_name BattleFormation
extends RefCounted
## **战斗编队**（1.2 第二十轮）—— "这一场谁对谁、双方各出多少人"的唯一真源。
##
## ## 老板定的编制（原话）
## 「战斗编队方案是**三个量产机编队（三台飞行踏板 + 六台量产机）+ 一台 ace 机**
## （柯西 / 佩涅罗佩 / 阿利宙斯 / 灵格斯改），玩家可以自己选择阵营的机型配置
## （**1.2 版本就做**，但是两边的量产机都只给现在只有的这各自一种）。」
##
## 所以一场团的构成是：
##   3 个编队 × 每个 2 台量产机 = **6 台量产机 / 3 块踏板**
##   ＋ **1 台 ACE 机**（不骑踏板 —— 用户定过 ACE 机不可骑）
##   两边各一套 ⇒ 场上最多 **14 台单位**。
##
## ## 为什么单独一个文件
## "哪边有哪些机"是一张**表**，不是散布在 `main` 里的 if。
## 加机体、改编制、按阵营换配置都只动这里；`main` 只负责"照表撒人"。
##
## ## 两侧的机体池（按阵营，见 `FlightPedal.kind_for_suit`）
##   **马夫蒂**：ACE = 柯西；量产 = 梅萨M01 / **梅萨指挥官型** / **梅萨F01型**（2026-09-29 加后两台）
##   **联邦·喀耳刻**：ACE = 佩涅罗佩 / **阿利宙斯**；量产 = 古斯塔夫00
## ⚠️ 阿利宙斯**属于喀耳刻部队**（剧场版第二章），原来误放在马夫蒂侧，2026-09-20 已改正。
## ⚠️ 灵格斯改**还没接**（老板："先不做"），所以两侧的 ACE 数量暂时不对称（1 / 2）。
##
## ## ⚠️ 池子变大**不改编制**（2026-09-29 加梅萨指挥官 / F01 时确认）
## `lineup()` 里 AI 队友一律走 `r.mp()`，而 `mp()` 取的是 `mass_production[0]`
## ⇒ **加进池子只是"玩家多两个可选"，编制仍是 3 编队 × 2 台 ＋ 1 ACE**。
## 所以马夫蒂侧现在 **4 台可选**（1 ACE ＋ 3 量产），联邦侧仍是 3 台。
## 这条差异会撞主菜单的机体卡版式（见 `MainMenu.CARD_MIN_W` 与 `suit_window`）——
## 4 台在那里必须靠**横向窗口**才排得下。
##
## ## 铁律：补充进来的机体只能是**同阵营**的（老板 2026-09-21）
##
## 「每个系统补充的王牌机只能是同阵营的。」
##
## 这条覆盖**所有**"系统替玩家补一台"的路径：编制补 ACE、名单兜底、
## 某个阵营池子暂时为空、将来新加的模式。判据只有一个 —— `belongs_to(side, suit)`；
## `lineup()` 在写进 ACE 槽之前还会再兜一次底。
##
## 为什么值得单列成铁律：**跨阵营不会报任何错**。名单里混进一台敌机，游戏照常跑完，
## 只有玩家在战场上看见"自己人被对面开" —— 靠日志和崩溃都发现不了，
## 只能靠"把不变量写成测试"（见 `suite_round15` 的「ACE 只补同阵营」一组）。

enum Side { MAFTY, FEDERATION, ZEON }

## 编队里每台机体要带的信息。`is_ace` 决定"要不要给他配踏板"。
class Unit extends RefCounted:
	var suit: int = SuitProfile.Id.MESSER_M01
	var is_ace := false
	## 同一编队内的第几位（0 = 领机，1 = 后座）。`main` 用它摆挂位。
	var slot := 0
	## 这个编队的编号（0/1/2）。ACE 用 −1（它不属于任何量产编队）。
	var squad := 0
	## **这一台由玩家开吗**。
	##
	## ⚠️ 必须是正经声明的字段，不能事后往 `RefCounted` 上挂 ——
	## 第一版我写了个 `u.owner_is_player = true` 的赋值，而类里没这个字段，
	## GDScript 会在**运行时**才报错（静态检查查不到），
	## 表现是"名单生成到一半整个函数炸掉"。
	var owner_is_player := false
	## **这一台由联机里的"另一个人"（加入方）开吗**（多人模式，2026-09-21）。
	##
	## ⚠️ 它是 `human_seat` 的**派生量**，不要单独赋值（见下面的说明）。
	var owner_is_client := false
	## **这一台归哪个真人开**：−1 = AI，0 = 本机，1 = 远端（加入方）。
	##
	## ## 为什么要有这个字段（而不是两个布尔量各写各的）
	## 第一版给同一台机体**同时**写了 `owner_is_player = true` 和
	## `owner_is_client = true`（同队时"两个真人"都落在这一台上），
	## 结果一份名单里出现"一台机体同时是两个玩家"——自己写的断言当场就拦住了。
	## 改成**只存一个座位号**，两个布尔量由它派生：物理上不可能同时成立。
	##
	## 赋值请用 `set_human_seat()`，它会同时维护那两个派生量。
	var human_seat := -1
	## 本机（开这一台的是"我这台机器"）。与 `human_seat == 0` 等价。
	func is_local_human() -> bool:
		return human_seat == 0
	## 远端玩家（联机里的另一个人）。与 `human_seat == 1` 等价。
	func is_remote_human() -> bool:
		return human_seat == 1
	## 有没有真人开它。
	func has_human() -> bool:
		return human_seat >= 0
	## 唯一的写入点：座位号 + 两个派生量一起维护。
	func set_human_seat(seat: int) -> void:
		human_seat = seat
		owner_is_player = (seat == 0)
		owner_is_client = (seat == 1)

	func _init(s: int, ace: bool, sq: int, sl: int) -> void:
		suit = s
		is_ace = ace
		squad = sq
		slot = sl

	func display_name() -> String:
		return SuitProfile.by_id(suit).display_name


## 一个阵营能拿出什么。
class Roster extends RefCounted:
	var side: int = Side.MAFTY
	var name_cn := ""
	## Reserved factions have data but no selection or deployment entry.
	var selectable := true
	## 阵营标志（透明底 PNG，由 `tools/make_faction_logos.gd` 从用户给的截图抠出来）。
	##
	## ⚠️ **不要直接把用户给的原始截图挂进来**：那两张是**满底色**的
	##（马夫蒂红底、联邦蓝底），铺在深色菜单上就是两块大色块。
	## 抠图脚本会把底色变成透明、并把笔画提亮（详见那个脚本的文件头）。
	var logo_path := ""
	## 这个阵营的 ACE 机（可能多选，玩家挑一台）。
	var aces: Array[int] = []
	## 这个阵营的**量产机**。1.2 只有一种（老板："两边的量产机都只给现在只有的这各自一种"）。
	var mass_production: Array[int] = []

	## 这个阵营的**代表 ACE**（编制补出来的那一台）。
	##
	## ⚠️ **硬约束：返回的机体必须是本阵营的**（老板 2026-09-21：
	## 「每个系统补充的王牌机只能是同阵营的」）。
	##
	## 原来这里写死 `SuitProfile.Id.XI`（柯西）当兜底 —— 而柯西是**马夫蒂**的 ACE，
	## 于是联邦侧只要出现"没有 ACE"的名单，系统就会给联邦补一台**敌阵营的柯西**。
	## 兜底也不许跨阵营：先退到自己的量产机，再退到"按 `side` 认的那台量产机"。
	func ace() -> int:
		if not selectable:
			return -1
		if not aces.is_empty():
			return aces[0]
		if not mass_production.is_empty():
			return mass_production[0]
		return SuitProfile.Id.MESSER_M01 if side == BattleFormation.Side.MAFTY \
			else SuitProfile.Id.GUSTAV00

	## 这个阵营的量产机（撑满 3 编队 × 2 台的那种）。
	## ⚠️ 兜底同理**不许跨阵营**：原来写死的梅萨M01 是马夫蒂的机。
	func mp() -> int:
		if not selectable:
			return -1
		if not mass_production.is_empty():
			return mass_production[0]
		if not aces.is_empty():
			return aces[0]
		return SuitProfile.Id.MESSER_M01 if side == BattleFormation.Side.MAFTY \
			else SuitProfile.Id.GUSTAV00

	## 这个阵营能选的**全部**机体（ACE ＋ 量产），供菜单列出来。
	func all_suits() -> Array[int]:
		var out: Array[int] = []
		out.append_array(aces)
		out.append_array(mass_production)
		return out


# ---- 编制规模 ----
## 一场团里每边的**量产编队数**（老板：三个）。
const SQUADS_PER_SIDE := 3
## 每个编队几台（老板：一台踏板 + 两台机体）。
const UNITS_PER_SQUAD := 2
## 每边几台 ACE（老板："两边都有"）。
const ACES_PER_SIDE := 1


static func mafty() -> Roster:
	var r := Roster.new()
	r.side = Side.MAFTY
	r.name_cn = "马夫蒂"
	r.logo_path = "res://assets/ui/faction/mafty.png"
	# ⚠️ **阿利宙斯原来被放在这里，是错的**（老板 2026-09-20 指出）：
	# 「阿利宙斯居然在马夫蒂里面，问题是阿利宙斯是**喀耳刻部队**的」。
	# 它是剧场版第二章（キルケーの魔女）里喀耳刻部队的机体，所以归联邦侧。
	# 于是马夫蒂这边**只剩柯西一台 ACE**。
	r.aces = [SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL]
	# 量产机三台（2026-09-29）。老板原话：「把梅萨指挥官型和梅萨f01型导入游戏里面，
	# 在**小队战的马夫蒂**里面能选」⇒ 加进**本阵营的量产池**。
	#
	# ⚠️ 两个"不加"要写清楚，否则下一个人会以为这里漏了：
	#   - **不加进 `aces`**：三台都是量产机，柯西仍是马夫蒂唯一的 ACE
	#     （`ACES_PER_SIDE = 1`，加进去会变成"谁当 ACE"的额外语义）；
	#   - **不改编制**：`lineup()` 里 AI 队友走 `r.mp()` = `mass_production[0]` = M01，
	#     所以场上编制一格没变，玩家以外的队友仍是 M01（"选什么就全是那一台"
	#     从来没实现过，也不需要）。
	# ⇒ 池子从 2 台变 4 台，**只影响"玩家能选什么"**。
	r.mass_production = [SuitProfile.Id.MESSER_M01, SuitProfile.Id.MESSER_CMD,
		SuitProfile.Id.MESSER_F01]
	return r


static func federation() -> Roster:
	var r := Roster.new()
	r.side = Side.FEDERATION
	# 用户要求：「把阵营选择里面**地球联邦军**的后缀加入**喀耳刻部队**」。
	# 所以显示名带上部队番号 —— 它也是那两台 ACE（佩涅罗佩 / 阿利宙斯）与量产机
	#（古斯塔夫00）的实际所属，三者在作品里都是喀耳刻部队的机体。
	r.name_cn = "地球联邦军·喀耳刻部队"
	# 用户给的文件夹叫"喀耳刻部队logo"，而图里是 **E.F.S.F.（Earth Federation
	# Space Force）** 的正式徽记 —— 所以这份标志同时代表联邦军与喀耳刻部队。
	r.logo_path = "res://assets/ui/faction/kilce.png"
	# 联邦侧的 ACE：佩涅罗佩（凯奈斯机）＋ **阿利宙斯**（喀耳刻部队机，见上）。
	# ⚠️ 灵格斯改（老板提过）**还没接**，接进来时加到这个数组即可 ——
	# 这正是把"阵营有哪些机"做成数据的好处。
	r.aces = [SuitProfile.Id.PENELOPE, SuitProfile.Id.ARIZEUS, SuitProfile.Id.REGZ_CUSTOM, SuitProfile.Id.NU_GUNDAM]
	r.mass_production = [SuitProfile.Id.GUSTAV00]
	return r


## 吉翁已登记，待机体与玩法准备完成后再开放入口。
static func zeon() -> Roster:
	var r := Roster.new()
	r.side = Side.ZEON
	r.name_cn = "吉翁"
	r.logo_path = "res://assets/ui/faction/zeon.png"
	r.selectable = false
	r.aces = [SuitProfile.Id.NEUE_ZIEL]
	return r


static func roster_of(side: int) -> Roster:
	match side:
		Side.FEDERATION:
			return federation()
		Side.ZEON:
			return zeon()
	return mafty()


static func selectable_sides() -> Array[int]:
	return [Side.MAFTY, Side.FEDERATION]


static func side_name(side: int) -> String:
	return roster_of(side).name_cn


## 把 `u` 标成"归玩家开" —— **但必须核对机体 id**。
##
## ## 这里踩过一个很难看的坑（第二十轮实测）
##
## 原先我只看"这一边有没有玩家"来决定玩家占哪个槽位，于是**敌人那一边**也被算成
## "有玩家"：因为 `main` 调 `lineup(foe_side, -1)` 时我本想用 −1 表示"没玩家"，
## 而 `has_player = player_suit >= 0` 确实把它判成了 false ——
## 问题出在**生成之后没人再核对"这台到底是不是玩家的机体"**，
## 而 `owner_is_player` 是**按槽位**（sq==0/sl==0）写的，跟机体 id 无关。
## 结果：敌人名单里第一个槽位被标成玩家 ⇒ `_spawn_side()` 认为"玩家已经建好了"
## ⇒ **整台不建**（表现是"敌人少一台"），而我方那台本该是玩家的 0 号位
## 反而被当成 AI 建了出来（表现是"玩家不见了 / 多了个 AI"）。
##
## 修法：**标记必须同时满足"有玩家"与"这台机体就是玩家选的那台"**。
## 这样 `player_suit = -1`（敌人那一边）时，任何机体都不可能与它相等，
## 于是不可能被误标。
static func _mark_player(u: Unit, player_suit: int, slot_is_player: bool) -> void:
	if slot_is_player and player_suit >= 0 and u.suit == player_suit:
		u.owner_is_player = true


## 玩家选一台机体之后，**这一边的完整出战名单**。
##
## ## 玩家选 ACE 还是选量产机，名单不一样
## 这是本项最容易搞混的一处，所以说死：
##   - 玩家选 **ACE** ⇒ 那台 ACE 是玩家；AI 出 **6 台量产机（3 编队）**；
##   - 玩家选 **量产机** ⇒ 玩家占掉**某一个编队的 0 号位**；
##     AI 出 3 个编队里**剩下的 5 台** ＋ **1 台 ACE**。
##
## 无论哪种，**每边都是 3 编队 × 2 台 ＋ 1 台 ACE**，只是其中一台由玩家开。
## 这样"编制"是恒定的、可断言的，而玩家开什么机不改编制平衡。
##
## `player_suit` 必须属于 `side` 的池子（菜单的 roster 已经保证了这一点）。
##
## ⚠️ `player_suit` 传 **−1** 表示"这一边没有玩家"（敌人的那一边就是这么调的）。
## 别传 0 当"没有" —— 0 是 `SuitProfile.Id.XI`，传 0 会让"玩家开柯西"时
## 敌人也以为玩家开柯西，名单因此错位。
static func lineup(side: int, player_suit: int, ace_override: int = -1) -> Array:
	if player_suit in [SuitProfile.Id.GP03D, SuitProfile.Id.NEUE_ZIEL]:
		return []
	var r := roster_of(side)
	if not r.selectable:
		return []
	if r.mass_production.is_empty():
		var single := Unit.new(r.ace(),true,-1,0)
		_mark_player(single,player_suit,true)
		return [single]
	var has_player := player_suit >= 0
	var player_is_ace := has_player and r.aces.has(player_suit)
	var out: Array = []
	# ---- 三组量产编队 ----
	for sq in SQUADS_PER_SIDE:
		for sl in UNITS_PER_SQUAD:
			# 玩家开量产机时占掉**第一个编队的 0 号位**（领机位）——
			# 那是"看得见、能带队"的位置，也免得玩家一开局就发现自己在后座。
			#
			# ⚠️ 必须带 `has_player` 这个前提：这一边**没有玩家**时（敌人那一边，
			# `player_suit = -1`）不该有任何一台被标成玩家的 —— 第一版漏了这个前提，
			# 于是敌人的 0 号位被标成"玩家开"，`_spawn_side()` 会把它**跳过不建**，
			# 表现是"敌人少一台、而且那台永远不出现"。
			var is_player_slot: bool = has_player and not player_is_ace and sq == 0 and sl == 0
			# ★ 2026-09-29 修：玩家占的那一格要建成**玩家选的那台**，不是 `r.mp()`。
			#
			# ## 为什么原来写 `r.mp()` 也能"跑通"（以及它怎么坏的）
			# 第二十轮写下这一行时，**每个阵营的池子里只有一台量产机**
			#（马夫蒂只有 M01、联邦只有 GUSTAV00）⇒ `r.mp()` 与 `player_suit`
			# 在"玩家选量产机"这条路径上**恒等**，两者看起来可以互换。
			#
			# 2026-09-29 马夫蒂加进梅萨指挥官型 / F01型（池子 3 台量产机）之后
			# **这个巧合破了**，而坏法是完全静默的：
			# `_mark_player()` 要核对 `u.suit == player_suit`（那条核对本身是对的，
			# 它防的是"跨阵营误标"），而这一格建的是 M01、玩家选的是指挥官型
			# ⇒ **一台都标不上玩家** ⇒ 编队里那台本该由玩家开的机被当成 AI 建了出来，
			# 玩家那台则变成编制外的第八台（每边应当恒为 7 台）。
			#
			# ⇒ 正解是**这一格按玩家选的机型建**：`_mark_player()` 的核对随后自然成立，
			#   不需要放宽它（放宽 = 把"跨阵营不许混"这条铁律也一起放宽）。
			var slot_suit: int = player_suit if is_player_slot else r.mp()
			var u := Unit.new(slot_suit, false, sq, sl)
			# ⚠️ 交给 `_mark_player()` 统一判定（它会核对机体 id）——
			# 直接写 `u.owner_is_player = is_player_slot` 就是上面那个坑。
			_mark_player(u, player_suit, is_player_slot)
			out.append(u)
	# ---- 每边的 ACE ----
	for i in ACES_PER_SIDE:
		# 玩家开 ACE 时，那台就是玩家的；否则全是 AI。
		var is_player_ace := player_is_ace and i == 0
		# ★63-9 B4：**敌方那台 ACE 可以由外面点名**（编队战里玩家在菜单里挑对面开哪台）。
		# 默认 `-1` ⇒ 走 `r.ace()`，**旧行为逐位不变**（联机与 `lan_plan` 那些调用点
		# 都不传第三参）。
		# ⚠️ 与「玩家自己开 ACE」那一路**互斥**：`is_player_ace` 为真时玩家那台优先。
		# ⚠️ 跨阵营的 `ace_override` 由下面那段「同阵营兜底」接住（退到 `r.mp()`）——
		#    这里**不要**再写一遍判断，否则两处门迟早分家。
		var ace_suit: int = player_suit if is_player_ace \
			else (ace_override if ace_override >= 0 else r.ace())
		# ---- 同阵营兜底（老板 2026-09-21：「每个系统补充的王牌机只能是同阵营的」）----
		#
		# 正常路径下这一句**永远不会触发**：`is_player_ace` 只在
		# `r.aces.has(player_suit)` 成立时为真，而 `r.ace()` 本来就取自本阵营。
		# 留着它是因为**跨阵营不会报错**：名单里混进一台敌机，游戏照常跑完，
		# 只有玩家在战场上看见"自己人被对面开"。
		# 真触发（将来谁把 `Roster.ace()` 的兜底又写成别的阵营）时的处置是
		# **宁可让 ACE 换成自己这边的量产机**，也不要一台敌机顶着 ACE 的位置。
		if not r.all_suits().has(ace_suit):
			ace_suit = r.mp()
			is_player_ace = false
		var a := Unit.new(ace_suit, true, -1, 0)
		_mark_player(a, player_suit, is_player_ace)
		out.append(a)
	return out


## 这台机**属不属于这个阵营** —— 编制里"不许跨阵营"的唯一判据。
##
## 抽成函数是为了让"补进来的那台到底是不是自己人"能被测试**逐台量一遍**，
## 而不是靠人肉比对两个数组（人肉比对正是这条规矩第一次被破坏的原因）。
static func belongs_to(side: int, suit_id: int) -> bool:
	return roster_of(side).all_suits().has(suit_id)


## ★63-9 B4：**对面的那个阵营**（「哪边打哪边」的唯一真源）。
##
## 编队战里这条信息有两处要用，而以前是**各写各的**：
##   · `main.spawn_squad()` 决定「撒哪一份名单」；
##   · 主菜单决定「敌方 ACE 那一页列哪几台机」。
## 两份 if 迟早会对不上，而对不上的表现是**跨阵营**（不报错，见 `belongs_to` 那段）。
static func opposing(side: int) -> int:
	return Side.MAFTY if side == Side.FEDERATION else Side.FEDERATION


## 这一边总共有几台（含玩家的那台）。两侧都应当是同一个数。
static func unit_count_per_side() -> int:
	return SQUADS_PER_SIDE * UNITS_PER_SQUAD + ACES_PER_SIDE


## 这一边需要几块踏板：**每个量产编队一块**（ACE 不骑板）。
static func pedal_count_per_side() -> int:
	return SQUADS_PER_SIDE
