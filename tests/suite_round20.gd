class_name SuiteRound20
extends RefCounted
## 第二十轮：**编队战**（1.2）。
##
## 老板原话：「战斗编队方案是**三个量产机编队（三台飞行踏板 + 六台量产机）
## + 一台 ace 机**（柯西 / 佩涅罗佩 / 阿利宙斯 / 灵格斯改），玩家可以自己选择
## 阵营的机型配置（**1.2 版本就做**，但是两边的量产机都只给现在只有的这各自一种）」
## ＋「**两边都有**（ACE 机）」。
##
## 分四组测：
##   1. **编制表**（`BattleFormation`）—— 3 编队 × 2 台 + 1 ACE，两侧对称。
##   2. **阵营池** —— 马夫蒂 / 联邦各有哪些机；量产机各只有一种。
##   3. **名单生成** —— 玩家选 ACE 与选量产机，名单都必须是同一份编制。
##   4. **真局**（起主场景）—— 场上真有 7 台一边，且**僚机是 team 0**（不打自己人）。

const TABLE := "Round20 / 编制表：3 编队 × 2 台 + 1 ACE"
const ROSTER := "Round20 / 阵营池：两边各有什么"
const LINEUP := "Round20 / 名单生成：选 ACE 与选量产机都是同一份编制"
const LIVE := "Round20 / 真局：编队真的撒得出来"


static func run(t: T, host: Node) -> void:
	t.suite(TABLE)
	_table(t)
	t.suite(ROSTER)
	_roster(t)
	t.suite(LINEUP)
	_lineup(t)
	t.suite(LIVE)
	await _live(t, host)
	t.suite(CITY)
	_city(t)


# ---------------------------------------------------------------- 1 编制表

static func _table(t: T) -> void:
	# 老板给的三个数：编队数 3、每编队机体 2、每边 ACE 1。
	t.eq(BattleFormation.SQUADS_PER_SIDE, 3, "每边 **3 个量产编队**")
	t.eq(BattleFormation.UNITS_PER_SQUAD, 2, "每个编队 **2 台机体**（= 一块踏板）")
	t.eq(BattleFormation.ACES_PER_SIDE, 1, "每边 **1 台 ACE**")
	# 派生值：必须与老板的"六台量产机 + 一台 ACE"逐字对上。
	t.eq(BattleFormation.SQUADS_PER_SIDE * BattleFormation.UNITS_PER_SQUAD, 6,
		"量产机总数 = 3 × 2 = **6 台**")
	t.eq(BattleFormation.unit_count_per_side(), 7, "每边合计 **7 台**（6 量产 + 1 ACE）")
	# 踏板数 = 编队数（每个量产编队一块；ACE 不骑板 —— 用户定过 ACE 不可骑）。
	t.eq(BattleFormation.pedal_count_per_side(), 3, "每边 **3 块踏板**（= 三个编队）")
	t.eq(BattleFormation.pedal_count_per_side() * 2, 6, "两边合计 6 块踏板 = 「三台…」×2")
	t.eq(BattleFormation.unit_count_per_side() * 2, 14, "两边合计 **14 台**单位（含玩家）")


# ---------------------------------------------------------------- 2 阵营池

static func _roster(t: T) -> void:
	var m := BattleFormation.mafty()
	var f := BattleFormation.federation()
	t.eq(m.name_cn, "马夫蒂", "马夫蒂阵营名")
	# ⚠️ 第二十四轮用户要求「把阵营选择里面**地球联邦军**的后缀加入**喀耳刻部队**」，
	# 所以显示名带上了部队番号。
	t.eq(f.name_cn, "地球联邦军·喀耳刻部队", "联邦阵营名（带喀耳刻部队番号）")
	t.ok(f.name_cn.contains("喀耳刻"), "名字里含「喀耳刻部队」")

	# 量产机的**种数**（老板当年："两边的量产机都只给现在只有的这各自一种"）。
	#
	# ⚠️ 2026-09-29 马夫蒂侧变成 **3 种**：老板要求「把梅萨指挥官型和梅萨f01型
	# 导入游戏里面，在**小队战的马夫蒂**里面能选」⇒ 池子 = M01 ＋ 指挥官型 ＋ F01型。
	# 联邦侧**仍是 1 种**（那一边没有加机的需求）。
	#
	# ★ 要紧的是下面这两件事自本轮起**不再是同一个数**，所以这一节把它分开钉：
	#     `mass_production.size()` = **玩家能选几种**（3）
	#     `m.mp()`                  = **场上编队里那种**（恒为 `mass_production[0]` = M01）
	#   混淆两者的后果是"以为加了一台可选机就会改编制"—— 不会，也不该。
	t.eq(m.mass_production.size(), 3,
		"马夫蒂的量产机有 3 种（M01 ＋ 指挥官型 ＋ F01型）—— 2026-09-29 加后两台")
	t.eq(f.mass_production.size(), 1, "联邦的量产机仍只有一种")
	t.eq(m.mp(), SuitProfile.Id.MESSER_M01,
		"★ 编制用的那台仍是 M01（`mp()` = `mass_production[0]`）：**加池子不改编制**")
	t.eq(f.mp(), SuitProfile.Id.GUSTAV00, "联邦的量产机 = 古斯塔夫00")
	# 马夫蒂的三台量产机**都是梅萨系**（免得有人把一台 ACE 顺手塞进量产池）
	for id: int in m.mass_production:
		t.ok(SuitProfile.by_id(id).display_name.begins_with("梅萨"),
			"马夫蒂的量产机 %s 是梅萨系" % SuitProfile.by_id(id).display_name)

	# ⚠️ **量产机必须骑得了板**：编制的核心就是"三个编队 = 三块板"，
	# 而板是靠量产机骑的。哪天有人把某台量产机标成 ACE，这里会红。
	for r: BattleFormation.Roster in [m, f]:
		for id: int in r.mass_production:
			var p := SuitProfile.by_id(id)
			t.ok(p.can_ride_pedal(), "%s 的量产机 %s 骑得了板" % [r.name_cn, p.display_name])
			t.not_ok(p.is_ace(), "%s 的量产机 %s 不是 ACE 机" % [r.name_cn, p.display_name])

	# ACE 机**不能**骑板（同一个判据的反面）。
	for r: BattleFormation.Roster in [m, f]:
		for id: int in r.aces:
			var p := SuitProfile.by_id(id)
			t.ok(p.is_ace(), "%s 的 ACE %s 是 ACE 机" % [r.name_cn, p.display_name])
			t.not_ok(p.can_ride_pedal(), "%s 的 ACE %s **不可**骑板" % [r.name_cn, p.display_name])

	# 两侧的机体池**不重叠**（同一台机不能既属马夫蒂又属联邦）。
	for a: int in m.all_suits():
		t.not_ok(f.all_suits().has(a),
			"%s 不在联邦的池子里（阵营互斥）" % SuitProfile.by_id(a).display_name)

	# 玩家在编队战里能选的机体 = 本方池子（"不同阵营能选不同机体"）。
	t.gt(m.all_suits().size(), 0, "马夫蒂有可选的机")
	t.gt(f.all_suits().size(), 0, "联邦有可选的机")


# ---------------------------------------------------------------- 3 名单生成

static func _lineup(t: T) -> void:
	for side: int in [BattleFormation.Side.MAFTY, BattleFormation.Side.FEDERATION]:
		var r := BattleFormation.roster_of(side)
		# ---- 玩家开 ACE ----
		var ace_pick: int = r.ace()
		var a_line := BattleFormation.lineup(side, ace_pick)
		t.eq(a_line.size(), BattleFormation.unit_count_per_side(),
			"%s：玩家开 ACE 时名单仍是 7 台" % r.name_cn)
		var a_mp := 0
		var a_aces := 0
		var a_player := 0
		for u: BattleFormation.Unit in a_line:
			if u.is_ace:
				a_aces += 1
			else:
				a_mp += 1
			if u.owner_is_player:
				a_player += 1
		t.eq(a_mp, 6, "%s：量产机 6 台" % r.name_cn)
		t.eq(a_aces, 1, "%s：ACE 1 台" % r.name_cn)
		t.eq(a_player, 1, "%s：名单里**恰好一台**归玩家" % r.name_cn)

		# ---- 玩家开量产机 ----
		var b_line := BattleFormation.lineup(side, r.mp())
		t.eq(b_line.size(), BattleFormation.unit_count_per_side(),
			"%s：玩家开量产机时名单也是 7 台（编制不变）" % r.name_cn)
		var b_aces := 0
		var b_player_ace := false
		var b_player_mp := false
		for u: BattleFormation.Unit in b_line:
			if u.is_ace:
				b_aces += 1
			if u.owner_is_player:
				if u.is_ace:
					b_player_ace = true
				else:
					b_player_mp = true
		t.eq(b_aces, 1, "%s：玩家开量产机时**仍有 1 台 ACE**（AI 开）" % r.name_cn)
		t.not_ok(b_player_ace, "%s：玩家那台不是 ACE" % r.name_cn)
		t.ok(b_player_mp, "%s：玩家那台是量产机" % r.name_cn)

		# ---- 编队结构：3 个编队各 2 台，slot 是 0/1 ----
		var by_squad := {}
		for u: BattleFormation.Unit in a_line:
			if u.is_ace:
				continue
			if not by_squad.has(u.squad):
				by_squad[u.squad] = []
			by_squad[u.squad].append(u.slot)
		t.eq(by_squad.size(), 3, "%s：量产机分成 **3 个编队**" % r.name_cn)
		for sq: int in by_squad:
			var slots: Array = by_squad[sq]
			t.eq(slots.size(), 2, "%s：编队 %d 有 2 台" % [r.name_cn, sq])
			t.ok(slots.has(0) and slots.has(1),
				"%s：编队 %d 的挂位是 0 与 1（一个领机一个后座）" % [r.name_cn, sq])

		# ---- "没有玩家"那一边（传 −1）也必须能生成 ----
		var c_line := BattleFormation.lineup(side, -1)
		t.eq(c_line.size(), BattleFormation.unit_count_per_side(),
			"%s：传 −1（这方没玩家）也能生成满编名单" % r.name_cn)
		for u: BattleFormation.Unit in c_line:
			t.not_ok(u.owner_is_player, "%s：传 −1 时没有任何一台归玩家" % r.name_cn)


# ---------------------------------------------------------------- 4 真局

static func _live(t: T, host: Node) -> void:
	Game.reset()
	Game.active_suit = SuitProfile.Id.MESSER_M01
	Game.active_side = BattleFormation.Side.MAFTY
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main_scene)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame

	main_scene.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 14:
		await host.get_tree().physics_frame

	var player = main_scene.get("player")
	t.ok(player != null, "编队战局建起来了")
	t.eq(Game.squad_units_per_side, 7, "本局每边 7 台（写进了 Game）")

	var foes := Game.live_hostiles_of(player)
	var allies: Array = []
	for u: Node3D in Game.units:
		if u == player or not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if not u.has_method("is_alive") or not u.is_alive():
			continue
		if u.has_method("is_hostile_to") and not u.is_hostile_to(player):
			allies.append(u)
	# 每边 7 台（6 量产 + 1 ACE），所以对面是 **7 架敌机**、己方僚机 **6 台**。
	t.eq(foes.size(), 7, "敌机 7 台（对面满编：6 量产 + 1 ACE）")
	t.eq(allies.size(), 6, "僚机 6 台（我方 7 台减去玩家自己）")
	t.eq(allies.size(), 6, "僚机 6 台（我方 7 台减去玩家自己）")

	# ⚠️ **僚机必须是 team 0**：`is_hostile_to()` 判的是 "team 不等"，
	# 所以跨队伤害天然被挡住。若僚机错成 team 1，玩家一开局就在跟 6 台"自己人"对打。
	for a in allies:
		t.eq(a.team, 0, "僚机 %s 的 team 是 0（不是敌机）" % a.name)

	# 踏板数：每边 3 块（ACE 不骑板）⇒ 场上 6 台骑在板上。
	#
	# ---- 踏板数与**骑手数**（1.2 第二十六轮改过判据）----
	#
	# ⚠️ 这里原来钉的是"场上 **6 台**骑在板上（两边各 3 台领机）"，
	# 因为当时后座只是**靠转向跟着领机飞**、并没有真的上板。
	# 用户实测报「开局六台量产机，**只有三台是在踏板上的**」之后，
	# 后座改成 `set_carried_by()` **真正被载**，于是：
	#   - 只算"有板的人" → **12 台**（每台量产机都在某块板上）；
	#   - 真正的**板**只有 **6 块**（每边 3 个领机）。
	# 判据因此要分开数，见 `suite_squad_ride`（那里钉得更细）。
	var riders_on := 0
	var own_boards := 0
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if not u.has_method("pedal_owner"):
			continue
		if u.pedal_owner() != null:
			riders_on += 1
		if u.get("pedal") != null:
			own_boards += 1
	t.eq(riders_on, 12,
		"**12 台骑在板上**（两边各 6 台量产机，每台都在某块板上）")
	t.eq(own_boards, 6, "真正的**板是 6 块**（两边各 3 个领机各带一块）")

	# 后座是**被载**（不是靠转向跟飞）：挑一台僚机看它的 `carried_by`。
	var wing_found := false
	for a in allies:
		if a is BanditAI and a.is_carried():
			wing_found = true
			break
	t.ok(wing_found, "至少有一台僚机是**被载**的（`carried_by` 不是 null）")

	main_scene.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 5 奥恩贝利（死城 / 阴天黄昏）

const CITY := "Round20 / 奥恩贝利：死城地图"


static func _city(t: T) -> void:
	var m := MapDef.oenbelli()
	# ---- 地图本身 ----
	t.eq(m.id, MapDef.Id.OENBELLI, "地图 id 是 OENBELLI")
	t.eq(m.terrain, MapDef.Terrain.CITY, "地表是 CITY（不是落进 ISLANDS 的默认分支）")
	t.eq(m.name_cn, "奥恩贝利", "中文名")
	# ⚠️ 第二十二轮下半：**从"夜城"改成"死城 / 阴天黄昏"**（用户新给的设定）。
	# 这一组断言就是那次改动的契约：它不是夜战，而是**没有太阳也没有星**的阴天。
	t.eq(m.time_of_day.preset, TimeOfDay.Preset.DUSK, "时段是黄昏（不是夜战）")
	t.eq(m.time_of_day.name_cn, "阴天黄昏", "用的是阴天黄昏那一档")
	t.eq(m.time_of_day.star_amount, 0.0, "阴天：一颗星都没有")
	t.eq(m.time_of_day.disc_amount, 0.0, "阴天：太阳（天体）完全不出现")
	t.lt(m.time_of_day.sun_energy, 0.45, "直射光被云吃掉（< 0.45）")
	t.gt(m.time_of_day.ambient_energy, 0.9, "但环境光顶上来（> 0.9，散射光天下）")
	# ⚠️⚠️ 2026-09-23（批 K · 轮 1②）：**上面那条断言单独是不够的，实测栽过。**
	# 引擎语义：`ambient_light_sky_contribution == 1.0` 时环境光**整份用天空辐射**，
	# `ambient_color × ambient_energy` 的权重是 **0** ⇒ `ambient_energy` 是个**死旋钮**。
	# 实测（pixprobe）：`--amb=0.0 / 2.0 / 3.0` 三档与不拧的图 **md5 逐位相同**。
	# 后果就是这一张图**全帧 36.04% 的像素低于 4/255**、地面整条纯黑、楼全是黑剪影。
	# ⇒ 所以契约要写全：**要填充光，就必须同时把 `sky_contribution` 压到 1 以下**。
	# 这条断言才是"环境光真的进画面了"的机械表达；只断言 `energy > 0.9` 会让
	# "energy 写成了 1.8 但权重为 0"这个 bug 一路绿到底。
	t.lt(m.time_of_day.ambient_sky_contribution, 1.0,
		"环境光**同时**压掉了天空占比（< 1.0）—— 否则 `ambient_energy` 是死旋钮（权重为 0）")
	t.gt(m.time_of_day.ambient_energy, 1.0,
		"填充光的强度确实提上去了（> 1.0；实测选 1.8 是暗面可读性与亮度两条线的交点）")

	# ---- ⚠️ 其余时段**必须保持 `sky_contribution == 1.0`（夜间三图的零回归的机制证明）----
	#
	# `apply_time_of_day()` 现在无条件写三行（`sky_contribution` / `color` / `energy`）。
	# 只要非 `dusk_overcast` 的档位保持 `sky_contribution == 1.0`，
	# 引擎就会**整份用天空辐射**、把 `ambient_color` 完全忽略 ⇒
	# 那三张图（太平洋 ×2、艾尔斯岩夜战）在这一改前后**逐位相同**。
	#
	# ⚠️ 这是"逻辑隔离"而不是"实测没差别"：后者只能是"这一次没差别"，
	#    前者是"**不可能**有差别"。（同一条思路用在城市图的 `veg_amount == 0` 上。）
	t.eq(TimeOfDay.make(TimeOfDay.Preset.NIGHT).ambient_sky_contribution, 1.0,
		"夜间档：天空占比 = 1.0 ⇒ `ambient_color` 被引擎忽略，夜战三图不受这一改影响")
	t.eq(TimeOfDay.make(TimeOfDay.Preset.DAY).ambient_sky_contribution, 1.0,
		"白天档：同上")
	t.eq(TimeOfDay.make(TimeOfDay.Preset.DUSK).ambient_sky_contribution, 1.0,
		"普通黄昏档：同上（**只有** `dusk_overcast()` 才刻意压到 0）")
	t.eq(TimeOfDay.dusk_overcast().ambient_sky_contribution, 0.0,
		"阴天黄昏：天空占比 ~ 0 ⇒ 完全用 `ambient_color × ambient_energy`（这是它的设计意图）")
	# ⚠️ **云量这一条与上半轮相反**：上半轮是"云要少（楼是地标）"，
	# 现在是"阴天"——云是这张图天空的主角，所以**要够多**，只是不能多到把城市盖掉。
	t.gt(m.cloud_density, 1.0, "云量高于 1.0（阴天要够厚）")
	t.lt(m.cloud_density, 1.6, "但没厚到把整座城盖掉（>1.6 时俯瞰只剩云）")

	# ---- 进对战地图列表（不然玩家根本选不到）----
	t.ok(MapDef.versus_maps().has(MapDef.Id.OENBELLI), "进 1v1/编队战的地图列表")
	t.ok(MapDef.all_maps().has(MapDef.Id.OENBELLI), "进全部地图列表")
	t.not_ok(MapDef.versus_maps().has(MapDef.Id.RANGE), "靶场仍不在对战列表里（既有约定）")
	var seen := {}
	for i: int in MapDef.all_maps():
		t.not_ok(seen.has(i), "地图 id %d 不重复" % i)
		seen[i] = true
	t.eq(MapDef.all_maps().size(), 6, "一共六张图（五张对战/剧情 + 靶场；轮 B2 加了低地球轨道）")
	t.eq(MapDef.versus_maps().size(), 5, "对战可选五张")

	# ---- 尺度：城市网格必须真的铺在竞技场里 ----
	t.eq(WorldBuilder.CITY_GRID % 2, 0, "网格数是偶数")
	t.gt(WorldBuilder.CITY_GRID, 0, "有网格")
	t.lt(WorldBuilder.CITY_FILL, 1.0, "楼底占地 < 街区（否则街道宽为零）")
	t.gt(WorldBuilder.CITY_FILL, 0.0, "楼底占地 > 0（否则没有楼）")
	# 街道宽度必须留够：机体转弯半径按 km 计，窄了就只能直着飞。
	var block := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var street := block * (1.0 - WorldBuilder.CITY_FILL)
	t.gt(street, 300.0, "街道宽 %.0f m（> 300 m，俯冲穿插够用）" % street)

	# ---------------------------------------------------------------- 第二十二轮：台场版精细化
	#
	# 这一节钉住的是"**重做之后城市还在不在**"。上一版是一张均质方盒网格，
	# 判据只需要"网格是偶数 / 街道够宽"；这一版多了海湾、运河、三个地标和
	# 单轨，任何一件写坏了都必须是**红的**，而不是等试玩才发现。

	# ---- 海湾 / 运河：地形高度函数的纯函数性质 ----
	# ⚠️ 取样点**必须跟着城市自己的常量走**，不能写死米数：
	# 第二十二轮把整张图放大 2.3 倍时，城市的海湾/运河/广场坐标一起被放大，
	# 写死的 `6000`/`-9000` 会从"海里"变成"陆地上"，于是这几条断言会
	# 因为**取样点过时**而红 —— 那不是地形坏了，是测试在测一个旧坐标。
	var bay := WorldBuilder.CITY_BAY_Z
	var wave := WorldBuilder.CITY_BAY_WAVE
	# ⚠️⚠️ 2026-09-28：`CITY_CANAL_X`（以及 `_HALF` / `_END_Z`）**已经没有这个常量了**
	# —— 奥恩贝利的运河从"一条写死的直槽"改成"**四块人工岛的补集**"（详规 §B.4），
	# 于是那三个数不再有唯一值。取样点改由**块表**算出来（唯一真源还是 `OENB_BLOCKS`）：
	# `gx = -7` 那一格的中线 = `(-7 + 0.5) × 4 025 = -26 162.5`。
	# ⚠️ 继续引用旧常量会**直接编译不过**（常量不存在），不是红一条断言那种红。
	var cblk := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var cx := -6.5 * cblk
	# 水面必须真的被"挖"下去（海湾是海面以下的地形，不是贴一层蓝漆）。
	t.lt(WorldBuilder._city_landform(0.0, bay + wave * 2.0), -60.0,
		"海湾中心挖到水下")
	t.lt(WorldBuilder._city_landform(cx, -wave * 2.0), -60.0,
		"运河中央挖到水下（`gx = -7` 那一格的中线，由块表算出）")
	# 而建成区必须是平的、在 0 附近 —— 楼才不会悬空或陷进去。
	t.between(WorldBuilder._city_landform(0.0, 0.0), -24.0, 24.0, "市中心地面在 0 附近（不悬空）")
	var inland := WorldBuilder.CITY_PLAZA_R * 0.8
	t.between(WorldBuilder._city_landform(-inland, -inland), -24.0, 24.0,
		"西北角地面在 0 附近")
	# ⚠️ 同一坐标问两次必须同一个答案：地形网格是逐顶点采样这个函数的，
	# 函数一旦带状态（比如用 `_rng`），海岸线就会裂成锯齿。
	t.eq(WorldBuilder._city_landform(inland * 0.7, -inland * 0.4),
		WorldBuilder._city_landform(inland * 0.7, -inland * 0.4),
		"地形高度是纯函数（两次采样同一个值）")
	# ⚠️ **水面不能用一条直线判据**：海湾岸线是一条正弦，相位决定"哪里先入水"。
	# 这里刻意**不手算相位**（第一版就是手算错了，把 +8000 当成波谷 —— 断言自己先红）。
	# 判据只依赖"岸线是弯的"这件可观察的事实：同一个 z、两个不同的 x，
	# 必然一个在水里、一个不在 —— 岸线如果是一条直线，这一对不可能同时成立。
	t.ok(WorldBuilder.is_water_at(0.0, bay + wave * 1.3),
		"海湾：基准线以北在水里")
	t.not_ok(WorldBuilder.is_water_at(0.0, bay - wave * 2.0),
		"海湾：基准线以南还在陆上（岸线有位置）")
	# ⚠️⚠️ 2026-09-28：原来这里有一条「同一个 z 换个 x 就进水了 —— 岸线是弯的
	#（正弦在起作用）」，取样点是 `ARENA_RADIUS * 0.9`。这一轮把它改到 10 km 时
	# **查出一件真事**，所以这一条被**换掉**而不是改数：
	#
	#   `OENB_BOX` 的 +Z 边是 `gz = 10` ⇒ `z = 44 275`，而岸线的**波峰**只有
	#   `CITY_BAY_Z + CITY_BAY_WAVE = 41 450` ⇒ **整条正弦岸线落在盒内**，
	#   而盒内非岛的格一律是水 ⇒ **水/陆由盒子裁，不由正弦裁**。
	#   ⇒ 对奥恩贝利来说，`CITY_BAY_Z` / `CITY_BAY_WAVE` 在 `is_water_at()` 里
	#     **没有任何可观察的效果**（这条断言无论取哪个 x 都是"水"）。
	#
	# 所以：① 把"岸线是弯的"这条判据**挪到达沃**（那边没有盒子，正弦是唯一判据）；
	#       ② 把"奥恩贝利被遮蔽"这件事本身**钉住**（它是"海湾岸线读不出来"的根因，
	#          属于最容易在重构里静默过期的那类知识）。
	var box_z1 := (float(int(WorldBuilder.OENB_BOX[3])) + 1.0) * cblk
	t.gt(box_z1, bay + wave,
		"⚠️ 已知遮蔽：盒 +Z 边 %.0f > 岸线波峰 %.0f ⇒ 奥恩贝利的水/陆由盒子决定" % [
			box_z1, bay + wave])
	t.ok(WorldBuilder.is_water_at(0.0, bay + wave * 0.7),
		"同一个 z 在 x = 0 是水（盒内非岛）")
	t.ok(WorldBuilder.is_water_at(10000.0, bay + wave * 0.7),
		"⚠️ 换个 x **还是水** ⇒ 正弦在这里确实不起作用（盒边比波峰还靠海，见上）")
	# ⚠️ 「岸线是弯的」这条判据的**新家**：达沃。它 `bay_side = −1`、没有盒子，
	# `is_water_at()` 里除了运河就只剩这条正弦 ⇒ 取样点能真正读出海湾岸线。
	# 顺带也守住了"两座城的海湾参数是各自的"这件事（共用一组数就会在这里红）。
	var dv_bay := -26000.0
	var dv_wave := 3500.0
	# ⚠️ x 取 48 800：`sin(48 800 / 10 400) = sin(4.6923) ≈ −0.9998` ⇒ 岸线在
	# 那儿被压到 `−29 499`，比取样点 `−28 450` **更靠海** ⇒ 同 z 变成陆地。
	#（取 15 000 是不行的：那儿的 `sin ≈ +0.99` ⇒ 岸线抬到 `−22 528`，还是水。）
	t.ok(WorldBuilder.is_water_at(0.0, dv_bay - dv_wave * 0.7, MapDef.CityLayout.DAVAO),
		"达沃：基准线以南在水里")
	t.not_ok(WorldBuilder.is_water_at(48800.0, dv_bay - dv_wave * 0.7,
			MapDef.CityLayout.DAVAO),
		"达沃：同一个 z 换个 x 就是陆 —— 岸线是弯的（正弦在起作用）")
	t.not_ok(WorldBuilder.is_water_at(0.0, 0.0), "市中心不是水")

	# ---- 径向门：**水只在 `CITY_WATER_R` 之内**（2026-09-28 · 用户「改成四面环山」）----
	#
	# 这三条是这一轮**新增语义**的判据。门本身在 `CITY_WATER_R` 那段注释里；
	# 这里只钉行为：
	t.ok(WorldBuilder.is_water_at(0.0, WorldBuilder.CITY_WATER_R - 1000.0),
		"门内（77 km，还在海湾那一侧）仍然是水")
	t.not_ok(WorldBuilder.is_water_at(0.0, WorldBuilder.CITY_WATER_R + 1000.0),
		"门外（79 km）是**陆地** —— 海湾有了对岸")
	t.not_ok(WorldBuilder.is_water_at(WorldBuilder.ARENA_RADIUS * 0.9,
			bay + wave * 0.7),
		"⚠️ 门之外**永远**是陆地（旧版这里是水 —— 这正是「只有三面有山」的根因）")

	# ---- 四面环山：环带的**四个方位**都要真的长出山 ----
	#
	# ⚠️ 这一节守的就是用户那句「改成四面环山」。注意它守的**不是**"环带公式在不在"
	#（公式一直是径向的、四个方向都有），而是"**公式算出来的山有没有被别的东西乘掉**"：
	# 旧版在这四个方位里挑 `+Z` 那一个，读数恒为 **−480 m**（海底）——
	# 因为海湾那一支把丘陵整个乘了 `(1 − sw)`。
	var dirs := {
		"−Z（内陆侧 · 旧版就有）": Vector2(0.0, -1.0),
		"+Z（**海湾对岸** · 2026-09-28 才长出来）": Vector2(0.0, 1.0),
		"−X（旧版就有）": Vector2(-1.0, 0.0),
		"+X（旧版就有）": Vector2(1.0, 0.0),
	}
	for label: String in dirs:
		var d: Vector2 = dirs[label]
		var best := -1.0e9
		for i in 33:
			var rr := WorldBuilder.CITY_HILL_IN \
				+ (WorldBuilder.CITY_HILL_OUT - WorldBuilder.CITY_HILL_IN) \
				* float(i) / 32.0
			best = maxf(best, WorldBuilder._city_landform(d.x * rr, d.y * rr))
		t.gt(best, 2000.0, "环带在 %s 方位有山（该方位最高 %.0f m）" % [label, best])

	# ---- 岛：建成区、岛外留白 ----
	t.ok(WorldBuilder.city_is_land(0.0, 0.0), "市中心在岛上")
	t.ok(not WorldBuilder.city_is_land(0.0, 12.0),
		"正南 12 格是水面（海湾那一侧不能长楼）")
	t.eq(WorldBuilder.city_is_land(1.25, -3.5), WorldBuilder.city_is_land(1.25, -3.5),
		"岛缘抖动是格坐标的确定性哈希（同一格永远同一片陆/水）")

	# ---- 四块人工岛（2026-09-28 · 用户"照详规做四块岛"）----
	#
	# ⚠️ 这一节钉的是详规 §B.2 最后那两条"为什么是这几个数"：
	#   ① **外角点必须留在山陵内缘之内** —— 丘陵是径向环带，角点一旦越过
	#      `CITY_HILL_IN`，**有明 / 青海 / 东八潮的远端会长出一片 6 600 m 的山**；
	#   ② **必须落在细节网格之内** —— 越界的那一段会被直接切成平地（不报错）。
	# 两件事都是"改一格就破、而画面上只表现为'那块岛上没有楼'"的那种错。
	var blocks: Array = WorldBuilder.OENB_BLOCKS
	var b_cells := 0
	var far_corner := 0.0
	var far_edge := 0.0
	for b: Array in blocks:
		var bgx0 := int(b[0])
		var bgx1 := int(b[1])
		var bgz0 := int(b[2])
		var bgz1 := int(b[3])
		t.ok(bgx0 <= bgx1 and bgz0 <= bgz1,
			"块 %s 的格区间是有序的（写反了会静默变成空地）" % [b])
		b_cells += (bgx1 - bgx0 + 1) * (bgz1 - bgz0 + 1)
		for cx4: float in [float(bgx0) * cblk, (float(bgx1) + 1.0) * cblk]:
			for cz4: float in [float(bgz0) * cblk, (float(bgz1) + 1.0) * cblk]:
				far_corner = maxf(far_corner, sqrt(cx4 * cx4 + cz4 * cz4))
				far_edge = maxf(far_edge, maxf(absf(cx4), absf(cz4)))
	# 详规 §B.3 的面积账：195 + 104 + 144 + 144 = **587 格**（1 格² = 16.2 km²）。
	t.eq(b_cells, 587, "四块岛合计 %d 格（详规 §B.3 的账：195+104+144+144）" % b_cells)
	t.lt(far_corner, WorldBuilder.CITY_HILL_IN,
		("四块岛最远角点 %.0f m < 山陵内缘 %.0f m（余 %.0f m）⇒ **城里长不出山**"
			+ "（这一条红了就说明该把 `CITY_HILL_IN/OUT` 再往外搬，不是把块改小）")
			% [far_corner, WorldBuilder.CITY_HILL_IN,
				WorldBuilder.CITY_HILL_IN - far_corner])
	t.lt(far_edge, WorldBuilder.TERRAIN_DETAIL_SIZE * 0.5,
		"四块岛最远边 %.0f m < 细节网格半宽 %.0f m ⇒ 远处不会因越界被切成平地"
			% [far_edge, WorldBuilder.TERRAIN_DETAIL_SIZE * 0.5])
	# ⚠️ 主岛必须**含图心**：中央广场是以原点为圆心判的
	#（`_build_city_blocks()` 里的 `pos.length() < shape.plaza_r`）——
	# 主岛不含原点，广场会落到水里。
	t.ok(WorldBuilder.city_is_land(0.0, 0.0, MapDef.CityLayout.OENBELLI),
		"主岛含图心 (0,0)（中央广场因此落在岛上）")

	# ---- 出生点搬到**丘陵上面**（2026-09-28 · 用户："奥恩贝利的出生点放到丘陵上面"）----
	#
	# ⚠️⚠️ 这一节是**那条要求的可执行形式**，两条判据缺一不可：
	#   ① 出击环必须落在**丘陵环带之内**（`CITY_HILL_IN … CITY_HILL_OUT`）——
	#      环带之外就没有山，"丘陵上面"无从谈起；
	#   ② 出击环必须在**四块岛之外** ——
	#      旧值 `SPAWN_RADIUS = 46 575` 现在落在**城里**（东八潮岛上，`gz ≈ −11.5`），
	#      玩家等于在楼群里出生。
	# ①+② 合起来把新值钉成一个**区间**（山陵内缘之上、外缘之内），而不是一个数。
	#
	# ⚠️ 读的是 `CITY_SHAPE[OENBELLI].spawn_r`（**按图给**），不是全局 `SPAWN_RADIUS`：
	# 后者仍然是**非城市图**（沙漠 / 海洋 / 岛屿）的出击半径，而且是
	# `DESERT_OASIS_R = SPAWN_RADIUS × 1.16` 的派生源 —— 一个字都不能动
	#（动它会把沙漠图的绿洲撑出图幅）。详见 `match_spawn_radius()` 的注释。
	var oe_spawn_r: float = float(
		WorldBuilder.CITY_SHAPE[MapDef.CityLayout.OENBELLI].spawn_r)
	t.gt(oe_spawn_r, WorldBuilder.CITY_HILL_IN,
		("出击环 %.0f m 在**山陵内缘** %.0f m 之外 ⇒ 环下真的是丘陵"
			+ "（否则「出生点在丘陵上面」无从谈起，脚下只有平地）")
			% [oe_spawn_r, WorldBuilder.CITY_HILL_IN])
	t.lt(oe_spawn_r, WorldBuilder.CITY_HILL_OUT,
		"出击环 %.0f m 仍在**山陵外缘** %.0f m 之内（越过去就飞出丘陵带、又回到平地了）"
			% [oe_spawn_r, WorldBuilder.CITY_HILL_OUT])
	t.gt(oe_spawn_r, far_corner,
		("出击环 %.0f m 在四块岛最远角点 %.0f m 之外 ⇒ 玩家**不在楼群里出生**"
			+ "（旧值 46 575 落在东八潮岛上，这一条就是为它写的）")
			% [oe_spawn_r, far_corner])
	# ③ **环下真的压着丘陵**：绕环 72 个方位量一遍地形。
	#    ⚠️ 不能断言"整圈都是山" —— 环有**约四成在海上**（海湾在 +Z，
	#    而且过了岸线一路是海底）。可执行的形式是**集合量**：最高地形要显著高，
	#    且"地形 + 余量 高过写死的 `PLAYER_START_ALT`"的方位要真的存在
	#    —— 那些方位才是 `SPAWN_CLEARANCE` 抬升**被触发**的地方。
	var ring_peak := -1e9
	var ring_hi := 0
	for k in 72:
		var ang := TAU * float(k) / 72.0
		var gk := WorldBuilder._city_landform(cos(ang) * oe_spawn_r,
			sin(ang) * oe_spawn_r, MapDef.CityLayout.OENBELLI)
		ring_peak = maxf(ring_peak, gk)
		if gk + WorldBuilder.SPAWN_CLEARANCE > WorldBuilder.PLAYER_START_ALT:
			ring_hi += 1
	t.gt(ring_peak, 1000.0,
		"出击环上最高地形 %.0f m ⇒ 环下**真的有丘陵**（不是绕城一圈平地）" % ring_peak)
	t.gt(ring_hi, 0,
		("环上 %d / 72 个方位的「地形 + 余量」高过写死的 `PLAYER_START_ALT` ⇒ "
			+ "`SPAWN_CLEARANCE` 的抬升**真的被触发**"
			+ "（红了是两件事之一：丘陵被调矮、或出生环被搬回了平地 —— "
			+ "两种都得回来看这个余量还成不成立，别直接删这条）") % ring_hi)
	# ④ 开局方位（`main.gd` 传的 **−95°**）脚下：**不是水、而且是山**。
	#    ⚠️ 这里与 `main.gd` 的开局方位**耦合**（−95° 在陆地那一侧）。
	#    谁改那个方位、而这里红了，那是提醒不是假红 ——
	#    "出生点在丘陵上面"只在**陆地**那一侧成立（环的 +Z 半边在海面上）。
	var sa := deg_to_rad(-95.0)
	var sx := cos(sa) * oe_spawn_r
	var sz := sin(sa) * oe_spawn_r
	t.not_ok(WorldBuilder.is_water_at(sx, sz, MapDef.CityLayout.OENBELLI),
		"开局出生点 (%.0f, %.0f) 落在**陆地**上（不在海面）" % [sx, sz])
	t.gt(WorldBuilder._city_landform(sx, sz, MapDef.CityLayout.OENBELLI), 1000.0,
		"开局出生点脚下地形 %.0f m ⇒ 它真在**山坡上**（不是平地）"
			% WorldBuilder._city_landform(sx, sz, MapDef.CityLayout.OENBELLI))

	# ---- 楼群：真的要落在岛上、真的挡得住路 ----
	#
	# ⚠️⚠️ 1.3 批 M：城市**参数化**了（种子 / 地标表 / 配色按图给）。
	# 于是这一节必须**显式指名测的是哪座城** —— 传进去的种子/布局全部走
	# "奥恩贝利"（`_city_lot_seed` 的 `seed_value` 默认 `CITY_SEED`、
	# `_city_landmark_cell` 的 `layout` 默认 `OENBELLI`，这里再显式写一遍）。
	# 不指名的话这套断言测的是"**最后被 apply 的那张图**"，
	# 而那是由**测试执行顺序**决定的 —— 最难查的一类不稳定（设计书 §3.6）。
	var oe_seed: int = MapDef.oenbelli().city_seed
	var lots := 0
	var tall := 0
	var rng := RandomNumberGenerator.new()
	# ⚠️ `CITY_GRID / 2` 是 **int / int = int**（16/2=8，这里恰好对），
	# 但把它当边界用时必须显式取整 —— 网格数一旦改成奇数，`range()` 会静默少跑一格。
	var half := int(WorldBuilder.CITY_GRID) / 2
	for gx in range(-half, half):
		for gz in range(-half, half):
			if not WorldBuilder.city_is_land(gx + 0.5, gz + 0.5):
				continue
			rng.seed = WorldBuilder._city_lot_seed(gx, gz, oe_seed)
			var lot: Dictionary = WorldBuilder.city_lot_for(gx, gz, rng, oe_seed)
			lots += 1
			# 楼高：第一版是 420~1900。现在低层住宅可以矮到 160 m（也够挡路 ——
			# 机体才 22~28 m 高），但**不能低于机体的两倍**，否则贴楼飞像在平地上。
			t.gt(lot.h, 150.0, "地块 (%d,%d) 的楼高 %.0f m 至少是机体的若干倍" % [gx, gz, lot.h])
			if lot.zone == "downtown":
				t.gt(lot.h, 1300.0, "市中心地块 (%d,%d) 是高层" % [gx, gz])
			if lot.h > 2200.0:
				tall += 1
	# ⚠️ 岛太小 / 分区写反都会让这两条立刻红。
	t.gt(lots, 60, "岛上有 %d 个地块（地图不是一片空地）" % lots)
	t.gt(tall, 0, "至少有 %d 栋超高塔（航空障碍灯的判据用得上）" % tall)

	# ---- 地标占的格必须是独一无二的、而且在岛上（**奥恩贝利**）----
	# ⚠️⚠️ 2026-09-28：格表从 **4 格扩到 7 格**（详规 §E.4 的 6 格 + 塔自己那一格，
	# 见 `_city_landmark_cell()` 里那条 ⚠️）。**这张断言表必须与格表逐格对得上** ——
	# 它守的是"几何与格表不分叉"这件事，所以格表改一次这里就要改一次。
	var marks: Array[Vector2i] = [
		Vector2i(-4, 6),    # ⚠️ 自由女神**已删**（2026-09-28）—— 这一格现在**占格但空地**，
		                    #    用户选的是「保持空地」，所以它**留在格表里**（不长楼）
		Vector2i(-3, 1),    # 富士电视台
		Vector2i(4, 2),     # 地面停车场（原独角兽立像位）
		Vector2i(-12, -3),  # 东京国际展示场
		Vector2i(-1, -5), Vector2i(0, -5), Vector2i(1, -5)]  # 中央塔 + 两侧空地
	var mark_seen := {}
	for m2: Vector2i in marks:
		t.ok(not mark_seen.has(m2), "地标格 %s 不重复" % m2)
		mark_seen[m2] = true
		t.ok(WorldBuilder._city_landmark_cell(m2.x, m2.y),
			"地标格 %s 被识别出来" % m2)
		t.ok(WorldBuilder.city_is_land(m2.x + 0.5, m2.y + 0.5),
			"地标格 %s 在岛上（不然地标立在海上）" % m2)
	t.not_ok(WorldBuilder._city_landmark_cell(7, 7), "普通地块不会被误判成地标")
	# ⚠️ **反过来的那一条**：格表里**不该有**的格，一个案例一个（这类"表大了"的错
	# 只会表现为"某几格忽然不长楼了"，画面上几乎看不出来）。
	# 旧表的四格全部要**不再是**地标 —— 它们现在是四块岛上的普通地块。
	for old_m: Vector2i in [Vector2i(-2, -2), Vector2i(0, 3),
			Vector2i(-4, -5), Vector2i(0, -2)]:
		t.not_ok(WorldBuilder._city_landmark_cell(old_m.x, old_m.y),
			"旧地标格 %s 已归还给住宅地块（格表改了、几何没跟着改会在这里红）"
				% old_m)

	# ---------------------------------------------------------------- 达沃：城市参数化
	#
	# 设计书 §3.6 点名要求的"达沃专属门"。防的是两件**相反**的事：
	#   ① "改着改着把两座城悄悄合并成一座" —— 地块表/楼高必须**因病而异地不同**；
	#   ② "顺手把共用的东西也摇掉了" —— 海岸线（`city_is_land`，一个**不认种子**的
	#      纯函数）必须逐格相同，否则"加了第二座城"变成"改了第一座城"。
	var dv_seed: int = MapDef.davao().city_seed
	t.ok(dv_seed != oe_seed, "两座城的 `city_seed` 不同（否则是同一批地块换滤镜）")
	# ⚠️⚠️ 2026-09-28 v3：`city_lights` 从 `bool` 改成**枚举**（`CityLights`）。
	# 旧写法 `t.ok(...)` / `t.not_ok(...)` 在枚举上是**假绿** ——
	# `t.ok(1)`（POSTS_ONLY）与 `t.ok(2)`（FULL）**都真**，
	# 也就是"奥恩贝利不点灯"这条断言在**改完之后不再守任何东西**。
	t.eq(MapDef.davao().city_lights, MapDef.CityLights.FULL,
		"达沃点灯（活城，全亮）")
	t.eq(MapDef.oenbelli().city_lights, MapDef.CityLights.POSTS_ONLY,
		"奥恩贝利是 `POSTS_ONLY`（死城：灯杆与灯头都建、**光全关**）")
	# ⚠️ 补一条"不许写 bool"的钉子：字段必须是 `int`（枚举），
	# 写 `true` 会**静默变成 1**，而 1 恰好是 POSTS_ONLY ⇒ 达沃会静默变死城。
	t.ok(typeof(MapDef.davao().city_lights) == TYPE_INT,
		"`city_lights` 是枚举（int）而不是 `bool`（bool 赋值会静默错档）")
	t.ok(MapDef.davao().city_layout != MapDef.oenbelli().city_layout,
		"两座城的 `city_layout` 不同（地标表必须分开）")

	# ① 同一份种子建两次 → 地块表**完全相同**（确定性）
	var tbl_a := _lot_table(oe_seed)
	var tbl_a2 := _lot_table(oe_seed)
	t.eq(tbl_a, tbl_a2, "同一份 `city_seed` 建两次 → 地块表**完全相同**")
	# ② 两份不同的种子 → 地块表**不同**（真的换了一座城）
	var tbl_b := _lot_table(dv_seed)
	t.ok(tbl_a != tbl_b, "两份不同的 `city_seed` → 地块表**不同**")
	# ③ 而海岸线**不认种子** —— `city_is_land()` 必须是 `static`、且源码里
	#    不出现 `map` / `city_seed`。这是"参数化"与"重新设计地形"的分界线：
	#    谁把种子喂进了岸线函数，两座城就不再是"同一片海岸上的两座城"，
	#    而是两张各自长出来的地图 —— 那时"共用 `Terrain.CITY` 管线"这个前提就没了。
	var cs := _coast_src()
	t.gt(cs.length(), 0, "找到 `city_is_land()` 的源码块（且它是 `static func`）")
	t.not_ok(cs.contains("map") or cs.contains("city_seed"),
		"`city_is_land()` 不引用 `map` / `city_seed` ⇒ 海岸线不认种子（两座城共用一条）")

	# ④ 达沃的地标格：在岛上、与奥恩贝利**互不重叠**
	var dmarks: Array[Vector2i] = []
	for gx in range(-half, half):
		for gz in range(-half, half):
			if WorldBuilder._city_landmark_cell(gx, gz, MapDef.CityLayout.DAVAO):
				dmarks.append(Vector2i(gx, gz))
	t.eq(dmarks.size(), 8, "达沃有 8 个地标格（双塔连船 3 + 针塔 1 + 港区 4）")
	# ⚠️⚠️ 2026-09-28：这条从「重叠数 **= 0**」改成「重叠**恰好**是 `{(4,2)}`」。
	#
	# 旧口径（= 0）在四块岛这一轮**必红**，而红的原因**不是**"有人把两张表抄成一张"：
	#   · 台场的停车场按详规 §E.1 #4 落在 `(4, 2)`（原独角兽立像位，见 `_city_landmark_cell()`）；
	#   · 达沃的集装箱港区是 `gx 4..5 × gz 1..2` 四格（它要的是一整片**场地**）。
	# 两张**互相独立**的表在 `(4,2)` 上撞了一格 —— **纯巧合**。
	# 两城各自的 `city_layout` 不同（上面那条断言），运行时任何一处都**不会同时读两张表**，
	# 所以这一格重叠在几何上无后果。
	#
	# ⇒ 判据换成 **allowlist**：重叠集合必须**正好**等于 `{(4,2)}`。
	#   **这比原来的 `= 0` 更严** —— 它把这次巧合也钉住了：
	#   谁再往任一张表里加一格、或把两张表合并，重叠集合立刻变化，这里就红。
	var share: Array[Vector2i] = []
	for m3: Vector2i in dmarks:
		t.ok(WorldBuilder.city_is_land(m3.x + 0.5, m3.y + 0.5),
			"达沃地标格 %s 在岛上（不然地标立在海上）" % m3)
		if WorldBuilder._city_landmark_cell(m3.x, m3.y):
			share.append(m3)
	t.eq(share.size(), 1,
		"两城地标格**恰好共享 1 格**（共享 0 格 ⇒ 这条判据退化；≥2 格 ⇒ 两张表被抄成一张了）")
	if share.size() == 1:
		t.eq(share[0], Vector2i(4, 2),
			"共享的那一格必须是 `(4, 2)` —— 台场停车场 vs 达沃港区一角的巧合。"
				+ "谁把台场停车场的格号挪走，这里会红，那时请**同步更新这条**")

	# ---- 达沃：楼体量（1.3 批 M · 轮 2；2026-09-28 方向翻转）----
	#
	# 这两个倍率加在 `MapDef` 上。这一组守的是两件**相反**的事：
	#   ① 默认值必须是 1.0 ⇒ 奥恩贝利的几何**逐位不变**。
	#      它是老板已经点头过的那张图（`suite_gfx_map` 里还围着它一圈断言）。
	#      谁为了让达沃好看一点而"顺手把默认值也调了"，这里立刻红 ——
	#      而且红在**一个不需要建场景的纯数据断言**上，比等真渲染图出来才发现便宜得多。
	#   ② 达沃必须真的带着**自己的**一个方向。方向本身翻过一轮：
	#      | 轮次 | `tower_w` | `height_mul` | 高宽比 | 触发 |
	#      |---|---|---|---|---|
	#      | 1.3 批 M 轮 2 | 0.62 收窄 | 1.15 拔高 | ≈ 21:1 | 用户："更高的摩天大楼" |
	#      | **本轮** | **1.55 加粗** | **0.92 压低** | ≈ 6.7:1 | 用户：**"房子太细了"** |
	#
	# ⚠️ 下面三条钉的是**方向**，不是字面量剂量：只要"加粗 + 压低"这个方向还在，
	# 具体取 1.55 / 0.92 还是别的数都不用改测试。上一版这里钉的也正是
	# 方向（`< 0.95` / `> 1.05` / `slim > 1.5`），所以这一轮翻方向时它
	# **如实地红了三条** —— 那正是它存在的意义（提醒"这是有人拍板过的事"）。
	#
	# ⚠️ 与 `suite_gfx_map._built_maps()` 那组是**分工**、不是重复：
	# 那边量的是**建出来的盒子**（"倍率有没有真的落在几何上"），
	# 这边量的是**数据**（"倍率本身是不是按图给的"）。
	# 少了这边，一个"改了默认值"的错要先建两座城才会红；少了那边，
	# 一个"倍率没接进 `_city_block_at()`"的错则永远不红。
	var oe_map := MapDef.oenbelli()
	t.near(oe_map.city_tower_w, 1.0, 0.0001,
		"奥恩贝利的 `city_tower_w` 是默认值 1.0（塔身平面尺寸一字不动）")
	t.near(oe_map.city_height_mul, 1.0, 0.0001,
		"奥恩贝利的 `city_height_mul` 是默认值 1.0（楼高一字不动）")
	var dv_map := MapDef.davao()
	t.gt(dv_map.city_tower_w, 1.20,
		"达沃塔身平面被**加粗**（%.2f > 1.20）" % dv_map.city_tower_w)
	t.lt(dv_map.city_height_mul, 1.00,
		"达沃楼高被**压低**（%.2f < 1.00）" % dv_map.city_height_mul)
	# 高宽比 = 高度 ÷ 平面宽 ⇒ 这一对倍率对它的作用是 `height_mul / tower_w`。
	# 断言的是**比值**而不是两个数各自的大小：只有"又粗又矮"才叫敦实，
	# 单看一个方向（比如只加粗平面）也能过前两条，但那只是把牙签搓成擀面杖。
	var slim := dv_map.city_height_mul / dv_map.city_tower_w
	t.lt(slim, 0.85,
		"达沃全城高宽比倍率 %.2f < 0.85 ⇒ 真从「细高」翻到了「敦实」" % slim)

	# ---- ⚠️ 新不变量：塔楼**恒在裙房之内**（2026-09-28 加粗塔楼时立的）----
	#
	# ## 为什么这条值得单独立一条断言
	# 塔宽 = 子地块 × `[0.30, 0.46]` × `city_tower_w`，裙房 = 子地块 × `[0.72, 0.96]`
	# ⇒ 只要 **`0.46 × city_tower_w < 0.72`**，塔就不可能探到裙房外面。
	# 这一轮把 `city_tower_w` 从 0.62 提到 1.55，**正好把这条不等式吃到只剩 1% 余量**
	# （0.713 vs 0.72）—— 下次谁再想"再胖一点"，越过 0.72 之后塔楼会突出去。
	# ⚠️ 那种失效**靠看图很难发现**：塔有几千米高，悬挑几十米在俯视图上只是一圈亮边，
	# 在贴地视角却是**一整面悬空的墙**。⇒ 用一条纯数据断言挡在门口。
	var cab := _src_body(_city_src(), "_city_block_at(")
	var rr_lot: Array[float] = [0.30, 0.46, 0.72, 0.96]
	t.ok(cab.contains("randf_range(0.30, 0.46)")
			and cab.contains("randf_range(0.72, 0.96)"),
		("`_city_block_at()` 里那两对系数仍在（塔 `0.30~0.46` / 裙房 `0.72~0.96`）"
			+ " —— 下面两条不等式是从它们算的，它们一变这里必须跟着红"))
	for pair: Array in [[oe_map, "奥恩贝利"], [dv_map, "达沃"]]:
		var mp: MapDef = pair[0]
		var cap := rr_lot[1] * mp.city_tower_w
		t.lt(cap, rr_lot[2],
			("%s 塔宽上限 %.3f < 裙房下限 %.2f ⇒ 塔楼恒在裙房内（%.2f × %.2f）"
				% [pair[1], cap, rr_lot[2], rr_lot[1], mp.city_tower_w]))

	# 2026-10-08: both cities now use variable two-axis blocks and unequal
	# parcels. Replace the old "Oenbelli unchanged / x-only merge" assertions
	# with ownership, reserved-cell, access and non-overlap checks.
	preload("res://tests/suite_city_urban_layout.gd").run(t)
	t.suite("Round20 / 双城布局接线与环境")

	# ---- 达沃：夜城的填充光（1.3 批 M · 轮 3）----
	#
	# ## 这一组守的是一个**引擎语义级**的坑
	# `ambient_light_color × ambient_light_energy` 在
	# `ambient_light_sky_contribution = 1.0`（默认）下的权重是 **0** ——
	# 写了等于没写。第 2 轮的真渲染量出来：达沃 `--citycam=2500` 整帧 94.6%
	# 的像素低于 0.15 亮度 ⇒ 楼群是一片黑。修法就是把那条支路**显式打开**。
	#
	# 所以这里断言的是"那一项是否真的开着"，而不是"某个能量值是不是 2.0" ——
	# 后者是一条**会在有人重新调剂量时误报**的字面量断言，
	# 而前者正好是那个坑唯一的、与剂量无关的表征。
	var dv_tod: TimeOfDay = dv_map.time_of_day
	t.ok(dv_tod != null, "达沃有自己的时段对象（`_davao_night()`）")
	if dv_tod != null:
		t.lt(dv_tod.ambient_sky_contribution, 0.5,
			("达沃的 `ambient_sky_contribution` = %.2f < 0.5 ⇒ 填充光那条支路真的开着"
				+ "（= 1.0 时它被天空辐射整体替换、能量写了也白写，夜城会黑成一片）")
				% dv_tod.ambient_sky_contribution)
		t.gt(dv_tod.ambient_energy, 1.0,
			"达沃的填充光能量 %.2f > 1.0（剂量表见 `_davao_night()` 里那张表）"
				% dv_tod.ambient_energy)
	# ⚠️ 另一半：**共用预设一个字都不能动**。
	# `TimeOfDay.night()` 是太平洋 / 乌卢鲁 / 靶场三张图共用的那一档；
	# 为了让达沃亮起来而顺手把它一起改了，是这类改动最容易犯、
	# 也最难看出来的错（那三张图上只会"整体亮一点"，谁都说不清是不是回归）。
	var shared_night := TimeOfDay.night()
	t.near(shared_night.ambient_sky_contribution, 1.0, 0.0001,
		"共用预设 `TimeOfDay.night()` 的 `ambient_sky_contribution` 仍是默认 1.0（没被动过）")
	t.near(MapDef.pacific().time_of_day.ambient_sky_contribution, 1.0, 0.0001,
		"太平洋那张夜图的填充光支路仍然关着（达沃的改动没有漏到别的图）")

	# ---- 台场的骨架：桥跨海湾、单轨在竞技场内、塔顶高过桥面 ----
	t.gt(WorldBuilder.CITY_BAY_Z, WorldBuilder.CITY_PLAZA_R * 2.0,
		"海湾在市中心之外（城市有纵深，不是一面临海）")
	# ⚠️⚠️ 2026-09-28：这条从「桥位 > `CITY_BAY_Z`」改成**两条几何判据**。
	#
	# 旧口径是按"两座城**共用**一个 `CITY_BAY_Z`"写的 —— 那时它是 29 900，
	# 详规 §E.1 #1 因此把桥位给到 59 400。四块岛之后海湾基准回到**台场自己的**
	# 38 000（"共用"这个约束随 `CITY_SHAPE[·].bay_z` 按图给而消失，理由见常量注释），
	# 桥位按"真的跨在水上"给到 **36 400** ⇒ `36 400 > 38 000` 必红，
	# **可桥一点问题都没有**：判"桥在水上"要看**岸线最低点**，不是基准值。
	t.gt(WorldBuilder.CITY_BRIDGE_Z,
		WorldBuilder.CITY_BAY_Z - WorldBuilder.CITY_BAY_WAVE,
		("桥位 %.0f m 在岸线最低点 %.0f m 之外（不然桥会架在主岛最外一排的岸上 —— "
			+ "旧值 32 200 就正好压在岛缘上）")
			% [WorldBuilder.CITY_BRIDGE_Z,
				WorldBuilder.CITY_BAY_Z - WorldBuilder.CITY_BAY_WAVE])
	# ⚠️ 与之互补的那一条：桥**中段下面真的是水**。
	# 桥面是 `z = const` 的一条线（`_build_city_bridge()`，跨 ±0.82R），
	# 两端最终落到 ±64 km 之外的城郊地面上；判"它跨的是水"就在**桥心**取一点问
	# `is_water_at()` —— 那是全工程唯一会同时考虑"海湾"与"四块岛补集"的判据，
	# 所以这一条同时钉住了两件事：桥位在岛外、且落在水域（运河/外圈）上。
	t.ok(WorldBuilder.is_water_at(0.0, WorldBuilder.CITY_BRIDGE_Z),
		"桥心 `(0, %.0f)` 是**水**（`is_water_at()` 说的）⇒ 桥不是架在干地上"
			% WorldBuilder.CITY_BRIDGE_Z)
	t.lt(WorldBuilder.CITY_BRIDGE_DECK_Y, WorldBuilder.CITY_BRIDGE_TOWER_Y,
		"桥面低于主塔顶（塔才有意义）")
	# ⚠️ **桥下必须能飞过去**：这是一处真实的机动选项，不是背景板。
	t.gt(WorldBuilder.CITY_BRIDGE_DECK_Y, 240.0,
		"桥面 %.0f m 高于贴地线，机体能从桥下穿过" % WorldBuilder.CITY_BRIDGE_DECK_Y)
	t.lt(WorldBuilder.CITY_MONORAIL_R, WorldBuilder.ARENA_RADIUS,
		"单轨环线在竞技场内（玩家能绕它飞）")
	t.gt(WorldBuilder.CITY_MONORAIL_Y, 240.0, "单轨梁高于贴地线，也能从底下穿")

	# ============ R1 / R2 / R3（2026-09-27 老板报的三条）============
	#
	# 老板原话（同一条消息里的三点，这里按 R1 / R2 / R3 编号）：
	#   R1「达沃和奥恩贝利**公路还是没建出来**，不仅需要做公路**还需要做一些高架桥**」
	#   R2「达沃和奥恩贝利**房子没有做到错落有致**，**达沃需要更高的摩天大楼**」
	#   R3「达沃和奥恩贝利**还是有些房子在水上**，房子路灯公路都别在水上」
	#
	# ⚠️ 下面三块里**每一条都对着一个已经定位的根因**，不是"顺手多写几条"。
	#    根因写在各块开头 —— 那才是这些断言存在的理由（判据要能拦住那个错）。
	_city_r1_roads_and_viaducts(t)
	_city_r2_skyline(t)
	_city_r3_no_structure_on_water(t)
	_city_r4_parking_and_hills(t)


# ---------------------------------------------------------------- R1：公路 + 高架桥

## R1 的三个根因（全在 `_build_city_street_infra()` 与"高架桥不存在"上）：
##
## | # | 根因 | 老板看到的是 |
## |---|---|---|
## | ① | 路面标高**写死 `y = 0.6`**，而 `_city_landform()` 起伏 −7.9…+7.9 m | 路面被地形埋掉 ⇒「**公路还是没建出来**」 |
## | ② | 37 条线**全是同宽 170 m**（一个常量） | 读不出路网等级 |
## | ③ | **高架桥根本不存在** | 只能再提一次需求 |
static func _city_r1_roads_and_viaducts(t: T) -> void:
	# ---- ① 路网分三档（`city_road_width()` 是纯函数，可直测）----
	t.eq(WorldBuilder.city_road_width(0), WorldBuilder.CITY_ROAD_W_TRUNK,
		"格线 0（十字中心）= 主干道")
	t.eq(WorldBuilder.city_road_width(5), WorldBuilder.CITY_ROAD_W_ARTERIAL,
		"格线 5 = 次干道（每 5 格一条）")
	t.eq(WorldBuilder.city_road_width(1), WorldBuilder.CITY_ROAD_W_LOCAL,
		"格线 1 = 支路（其余格线）")
	# ⚠️ 上面三条 `eq` **单独是不够的**：它们右边也是那三个常量，
	# 把三个常量改成同一个数，三条照样绿（"分档"这件事一起没了）。
	# ⇒ 必须再钉**序**与**极差** —— 那才是"能读出等级"的机械表达。
	t.gt(WorldBuilder.CITY_ROAD_W_TRUNK, WorldBuilder.CITY_ROAD_W_ARTERIAL,
		"主干道宽于次干道")
	t.gt(WorldBuilder.CITY_ROAD_W_ARTERIAL, WorldBuilder.CITY_ROAD_W_LOCAL,
		"次干道宽于支路")
	var w_ratio := WorldBuilder.CITY_ROAD_W_TRUNK / WorldBuilder.CITY_ROAD_W_LOCAL
	t.gt(w_ratio, 2.5,
		("三档极差 %.2f 倍 ≥ 2.5（空中一眼能读出等级；旧版 37 条同宽 170 m 时"
			+ "这个比值是 1.00）") % w_ratio)

	# ---- ② 路面是"体"不是"纸"：厚度够、且抬离地形 ----
	t.gt(WorldBuilder.CITY_ROAD_T, 4.0,
		"路面板厚 %.0f m > 4（两端按地形俯仰之后，中间段仍不会悬空）"
			% WorldBuilder.CITY_ROAD_T)
	t.gt(WorldBuilder.CITY_ROAD_LIFT, 0.0,
		"路面抬离地形 %.1f m > 0（不抬的话起伏会把沥青切成碎片）"
			% WorldBuilder.CITY_ROAD_LIFT)

	# ---- ③ 高架桥 ----
	# ⚠️⚠️ 2026-09-28 v3：**旧判据 `t.lt(CITY_VIA_DECK_Y, 1000)` 已删** ——
	# `CITY_VIA_DECK_Y` 现在**已弃用**（桥面不再是常量，改成沿线剖面），
	# 而达沃的剖面本来就到 **5 900 m**（downtown 最高楼 5 613 + 净空 200）
	# ⇒ 那条上界在 v3 之后**是错的判据**（留着它会把正确的做法判红）。
	# 剖面的**实测** min/max 由建城日志打印，与两个探针一起核（文档 §K）。
	# ⚠️ 2026-09-28：原本写成 `t.ge()` / `t.le()` —— 框架上**没有**这两个方法
	#（只有 ok / not_ok / near / eq / lt / gt / between）⇒ 那两条断言**根本没执行**，
	# 而断言总数悄悄掉了 7（假绿）。改用显式比较，让"跑没跑"在计数上看得见。
	var via_lo: float = WorldBuilder.CITY_VIA_MIN_Y
	t.ok(via_lo >= 240.0,
		("高架桥面**下界** %.0f m ≥ 240 m 贴地线（与彩虹桥 / 单轨同一条判据："
			+ "机体必须能从底下钻过去）") % via_lo)
	t.ok(via_lo <= 400.0,
		("高架桥面**下界** %.0f m ≤ 400 m（再高的话运河线上的高架会凭空抬起来，"
			+ "读成「一座跨海的天桥」）") % via_lo)
	t.gt(WorldBuilder.CITY_VIA_CLEARANCE, 0.0,
		"剖面净空 %.0f m > 0（楼顶之上必须留出机体高度）"
			% WorldBuilder.CITY_VIA_CLEARANCE)
	t.lt(WorldBuilder.CITY_VIA_MAX_GRADE, 0.08,
		"限坡 %.1f%% < 8%%（再陡剖面就成楼梯了）"
			% (WorldBuilder.CITY_VIA_MAX_GRADE * 100.0))
	t.gt(WorldBuilder.CITY_VIA_PIER_W, 0.0,
		"桥墩有截面 %.0f m（0 就成了一条撞不到的线）" % WorldBuilder.CITY_VIA_PIER_W)
	t.gt(WorldBuilder.CITY_VIA_RING_SEGS, 8,
		"环线分段 %d > 8（再少就是个多边形）" % WorldBuilder.CITY_VIA_RING_SEGS)
	# ---- ⚠️ B6（2026-09-28）：桥墩的两条"不许退化"判据 ----
	# ① **最坏无墩跨**（= 环线段弧长 × (`RING_PIER_EVERY` + 2 × 挪位上限)）不许超过 3 格。
	#    这是 B5 量出来的那条硬伤的唯一机械表达：旧值（EVERY 4 + 落楼丢墩）
	#    实测最长无墩跨 **38 537 m（奥恩贝利）/ 78 540 m（达沃）** ——
	#    420 m 宽的桥面凌空四万米，一眼就假。
	for li: int in [MapDef.CityLayout.OENBELLI, MapDef.CityLayout.DAVAO]:
		var ring_r: float = WorldBuilder.CITY_SHAPE[li].via_ring_r
		if ring_r <= 0.0:
			continue
		var arc := TAU * ring_r / float(WorldBuilder.CITY_VIA_RING_SEGS)
		var worst := arc * (float(WorldBuilder.CITY_VIA_RING_PIER_EVERY)
			+ 2.0 * WorldBuilder.CITY_VIA_PIER_SLIDE)
		t.lt(worst, WorldBuilder.CITY_CBLOCK * 3.0,
			("CityLayout[%d] 环线**最坏无墩跨** %.0f m < 3 格（%.0f m）"
				+ "（弧长 %.0f × (EVERY %d + 2 × 挪位 %.2f)）")
				% [li, worst, WorldBuilder.CITY_CBLOCK * 3.0, arc,
					WorldBuilder.CITY_VIA_RING_PIER_EVERY, WorldBuilder.CITY_VIA_PIER_SLIDE])
	# ② 避楼必须是"挪"而不是"丢" —— 上限 0 就等于旧的"落楼不建墩"。
	t.gt(WorldBuilder.CITY_VIA_PIER_SLIDE, 0.0,
		("墩位避楼的**沿弦挪位上限** = 段长的 %.0f%% > 0（0 就退回「落楼不建墩」，"
			+ "实测那样会丢掉 39~44%% 的环线墩）") % (WorldBuilder.CITY_VIA_PIER_SLIDE * 100.0))
	# 环线半径**按图给**，两张城都必须有（环线是这个体系的必需件，不是可选项）。
	for li: int in [MapDef.CityLayout.OENBELLI, MapDef.CityLayout.DAVAO]:
		var vr: float = WorldBuilder.CITY_SHAPE[li].via_ring_r
		t.gt(vr, 0.0, "CityLayout[%d] 的环线高架半径 %.0f km > 0" % [li, vr / 1000.0])
	# ⚠️ 达沃的环线**必须跨在海湾上** —— 它的南弧就是夜袭进场的导航线。
	var dvs: Dictionary = WorldBuilder.CITY_SHAPE[MapDef.CityLayout.DAVAO]
	var dv_ring: float = dvs.via_ring_r
	var dv_bay: float = absf(dvs.bay_z)
	t.gt(dv_ring, dv_bay,
		"达沃环线半径 %.0f km > 海湾 |z| %.0f km ⇒ 南弧真的落在海湾上"
			% [dv_ring / 1000.0, dv_bay / 1000.0])
	# ---- ⚠️ B7（2026-09-28）：环线桥面是**连续曲面带**，不是 72 块直板 ----
	#
	# 用户原话：
	#   「**你的高架桥为什么是一堆直着的桥面按照摆了一个圈**，你要不试试这样摆能不能通车」
	#
	# 根因是"每段一块独立直板 + 各自一个 yaw" ⇒ 轮廓是 72 边形、每个顶点一道折角。
	# 判据用**弦高误差**（多边形逼近圆的偏差 `R(1 − cos(π/N))`）：
	#   · 旧写法 N = 72 ⇒ **26.2 m**（420 m 宽的桥面上一道 26 m 的折痕，俯视一眼可见）
	#   · 新写法 N = 72 × `CITY_VIA_RING_SUB` ⇒ 要 < 2 m
	t.gt(WorldBuilder.CITY_VIA_RING_SUB, 1,
		"环线曲面带的**每段细分数** %d > 1（= 1 就退回“每段一块直板”）"
			% WorldBuilder.CITY_VIA_RING_SUB)
	for li: int in [MapDef.CityLayout.OENBELLI, MapDef.CityLayout.DAVAO]:
		var ring_rr: float = WorldBuilder.CITY_SHAPE[li].via_ring_r
		if ring_rr <= 0.0:
			continue
		var samples := WorldBuilder.CITY_VIA_RING_SEGS * WorldBuilder.CITY_VIA_RING_SUB
		var sag := ring_rr * (1.0 - cos(PI / float(samples)))
		t.lt(sag, 2.0,
			("CityLayout[%d] 环线**弦高误差** %.2f m < 2 m（%d 段 × %d 细分 = %d 个断面）"
				+ "—— 旧写法 72 段 ⇒ %.1f m，那就是用户看到的“折角”")
				% [li, sag, WorldBuilder.CITY_VIA_RING_SEGS,
					WorldBuilder.CITY_VIA_RING_SUB, samples,
					ring_rr * (1.0 - cos(PI / float(WorldBuilder.CITY_VIA_RING_SEGS)))])
	t.gt(WorldBuilder.CITY_VIA_MARK_W, 0.0,
		"桥面中线标线宽 %.0f m > 0（桥面在 240 m 以上，没有标线读不出“这是一条路”）"
			% WorldBuilder.CITY_VIA_MARK_W)
	# ---- ⚠️ B7：**路面**的三个构造层 + 切段长度（治"看不到公路路面"）----
	#
	# 用户原话：「**路面和地面依旧没做区分还是没做出来，现在还是看不到公路路面**」
	#
	# ⚠️ 亮度台阶**比通道值**：`albedo` 的语义是**线性亮度**，而城市地面
	# `city_land_street` 是**顶点色**（本来就是线性）⇒ 两者可以直接比。
	t.gt(WorldBuilder.CITY_ROAD_PIECE, 0.0,
		"路面切段长度 %.0f m > 0" % WorldBuilder.CITY_ROAD_PIECE)
	t.lt(WorldBuilder.CITY_ROAD_PIECE, WorldBuilder.CITY_CBLOCK * 0.5,
		("路面切段 %.0f m < 半格（%.0f m）—— 一格一段（4 025 m）时弦-地形偏差可达 ±8 m，"
			+ "而板顶只比中点地形高 %.1f m ⇒ 路面会在中间**整段被地形吃掉**")
			% [WorldBuilder.CITY_ROAD_PIECE, WorldBuilder.CITY_CBLOCK * 0.5,
				WorldBuilder.CITY_ROAD_LIFT + WorldBuilder.CITY_ROAD_T * 0.5])
	var land_lum: float = MapDef.oenbelli().city_land_street.get_luminance()
	var shoulder_lum: float = WorldBuilder.CITY_ROAD_SHOULDER_ALBEDO.get_luminance()
	var mark_lum: float = WorldBuilder.CITY_ROAD_MARK_ALBEDO.get_luminance()
	var asphalt_lum := Color(0.055, 0.053, 0.052).get_luminance()
	t.gt(shoulder_lum, land_lum * 1.6,
		("路肩亮度 %.3f > 地面 %.3f × 1.6 ⇒ 路肩是**比地更亮**的一档"
			+ "（这是“路面两侧有边界”这件事的全部依据）") % [shoulder_lum, land_lum])
	t.gt(mark_lum, shoulder_lum * 1.15,
		"标线亮度 %.3f > 路肩 %.3f × 1.15（标线要比路肩再亮一档才读得出）"
			% [mark_lum, shoulder_lum])
	t.gt(land_lum / maxf(asphalt_lum, 0.0001), 2.5,
		("地面 %.3f ÷ 沥青 %.3f = %.1f 倍 > 2.5 ⇒ 沥青是**比地更暗**的一档")
			% [land_lum, asphalt_lum, land_lum / maxf(asphalt_lum, 0.0001)])
	t.gt(WorldBuilder.CITY_ROAD_SHOULDER_H, 0.0,
		"路肩抬离沥青 %.0f m > 0（0 的话“路缘”在 4 km 一格的城市里是 0.004 px = 不存在）"
			% WorldBuilder.CITY_ROAD_SHOULDER_H)
	# ---- ⚠️ B7：城市肌理"大格 / 小格不均匀分布、大格 7~8 栋、小格 2~3 栋" ----
	#
	# 用户原话：
	#   「**不要田字格建城市，至少是大格子小格子不均匀分布吧，
	#    大格子里面七八栋楼，小个子的话就三二栋楼吧**」
	#
	# 判据全部挂在 `city_block_grade()`（**纯函数**、由格坐标哈希定）上 ——
	# 不依赖建城、也不依赖"最后被 apply 的是哪张图"。
	var g_a: Dictionary = WorldBuilder.city_block_grade(7, -3)
	var g_b: Dictionary = WorldBuilder.city_block_grade(7, -3)
	t.ok(bool(g_a["big"]) == bool(g_b["big"]) and int(g_a["n"]) == int(g_b["n"]) \
			and is_equal_approx(float(g_a["fill"]), float(g_b["fill"])),
		"`city_block_grade()` 是**纯函数**（同一格号两次同答案）⇒ 城市可复现")
	var big_f_lo := 9.0
	var big_f_hi := 0.0
	var sm_f_lo := 9.0
	var sm_f_hi := 0.0
	var big_n_lo := 99
	var big_n_hi := 0
	var sm_n_lo := 99
	var sm_n_hi := 0
	var n_big := 0
	var n_small := 0
	for gi in 160:
		for gj in 160:
			var gr: Dictionary = WorldBuilder.city_block_grade(gi - 80, gj - 80)
			var fv := float(gr["fill"])
			var cv := int(gr["n"])
			if bool(gr["big"]):
				n_big += 1
				big_f_lo = minf(big_f_lo, fv)
				big_f_hi = maxf(big_f_hi, fv)
				big_n_lo = mini(big_n_lo, cv)
				big_n_hi = maxi(big_n_hi, cv)
			else:
				n_small += 1
				sm_f_lo = minf(sm_f_lo, fv)
				sm_f_hi = maxf(sm_f_hi, fv)
				sm_n_lo = mini(sm_n_lo, cv)
				sm_n_hi = maxi(sm_n_hi, cv)
	t.gt(n_big, 0, "**大格**存在（160×160 格样本里 %d 个）" % n_big)
	t.gt(n_small, 0, "**小格**存在（%d 个）——「不均匀分布」的另一半" % n_small)
	t.near(float(n_big) / float(n_big + n_small), WorldBuilder.CITY_BLOCK_BIG_P, 0.05,
		"大格占比 %.0f%% ≈ `CITY_BLOCK_BIG_P` %.0f%%"
			% [100.0 * float(n_big) / float(n_big + n_small),
				WorldBuilder.CITY_BLOCK_BIG_P * 100.0])
	t.gt(big_f_lo, sm_f_hi + 0.02,
		("大格的铺满比下限 %.2f **大于**小格的上限 %.2f ⇒ 两类的**块尺寸**真分开了"
			+ "（只改栋数不改块大小的话，俯视还是「田字格 + 空」，那不叫大格小格）")
			% [big_f_lo, sm_f_hi])
	t.ok(big_n_lo >= WorldBuilder.CITY_BLOCK_BIG_N.x \
			and big_n_hi <= WorldBuilder.CITY_BLOCK_BIG_N.y,
		"大格每格 **%d~%d 栋** ∈ [%d, %d]（用户：“大格子里面七八栋楼”）"
			% [big_n_lo, big_n_hi, WorldBuilder.CITY_BLOCK_BIG_N.x,
				WorldBuilder.CITY_BLOCK_BIG_N.y])
	t.ok(sm_n_lo >= WorldBuilder.CITY_BLOCK_SMALL_N.x \
			and sm_n_hi <= WorldBuilder.CITY_BLOCK_SMALL_N.y,
		"小格每格 **%d~%d 栋** ∈ [%d, %d]（用户：“小个子的话就三二栋楼”）"
			% [sm_n_lo, sm_n_hi, WorldBuilder.CITY_BLOCK_SMALL_N.x,
				WorldBuilder.CITY_BLOCK_SMALL_N.y])
	t.gt(big_f_lo / maxf(sm_f_hi, 0.0001), 1.3,
		"大格 / 小格的**块边长**比 %.2f > 1.3 ⇒ 两类块不是“一样大、只是楼多楼少”"
			% (big_f_lo / maxf(sm_f_hi, 0.0001)))
	# ---- ⚠️ B7：**定义了的函数真的被调用**（否则又是"全是接线断言"）----
	var b7_src := _city_src()
	var blk_src2 := _src_body(b7_src, "_build_city_blocks(")
	var prepare_src := _src_body(b7_src, "_city_prepare_placement(")
	var city_src := _src_body(b7_src, "_build_city(")
	t.ok(blk_src2.contains("city_block_plan(") and blk_src2.contains("_city_urban_cache[")
		and prepare_src.contains("CityUrbanPlan.make(") and prepare_src.contains("_city_urban_cache[")
		and city_src.find("\n\t_city_prepare_placement()") >= 0
		and city_src.find("\n\t_city_prepare_placement()") < city_src.find("\n\t_build_city_blocks()"),
		"道路预规划先缓存街廓，建筑消费同一份非等分地块规划")
	t.ok(blk_src2.contains("CITY_SUB_SLOTS"),
		"子地块的种子按 `格 × CITY_SUB_SLOTS + 子序号` 派生（不乘的话相邻格会撞种子）")
	var st_src := _src_body(b7_src, "_build_city_street_infra(")
	t.ok(st_src.contains("_emit_road_pieces("),
		"`_build_city_street_infra()` 走 `_emit_road_pieces()`（**切段**，不再一格一段）")
	for nm: String in ["CityRoadKerbs", "CityRoadMarks"]:
		t.ok(st_src.contains(nm),
			"路网建出 `%s`（`CityRoads` 沥青之外的两个构造层）" % nm)
	var via_src2 := _src_body(b7_src, "_build_city_viaducts(")
	t.ok(via_src2.contains("_via_ring_ribbon("),
		"`_build_city_viaducts()` 的环线走 `_via_ring_ribbon()`（连续带），不再逐段出直板")
	t.not_ok(via_src2.contains("i % CITY_VIA_RING_PIER_EVERY == 0, slid)"),
		"环线那一路**已经不再**调 `_append_via_seg()` 出桥面（墩位另算）")

	# ---- ⚠️ 结构性判据：公路 / 高架**真的被建出来**的调用必须在源码里 ----
	#
	# 运行时钉不住它们：路面 / 桥面 / 护栏全是 MultiMesh，而无头环境的
	# `MultiMesh.get_instance_transform()` 读回来**全是单位变换**
	#（渲染服务器没起来，实例数据不回读）⇒ 只能读源码。
	var src := _city_src()
	for fn: String in ["_build_city_street_infra", "_build_city_viaducts"]:
		t.gt(src.find("func " + fn + "("), 0, "源码里有 `%s()`" % fn)
	var build := _src_body(src, "_build_city(")
	# ⚠️ 有函数不调用 = 一样"没建出来"，所以还要钉**调用**。
	t.ok(build.contains("_build_city_street_infra()"),
		"`_build_city()` 调用了 `_build_city_street_infra()`")
	t.ok(build.contains("_build_city_viaducts()"),
		"`_build_city()` 调用了 `_build_city_viaducts()`")
	# 宽度必须走 `city_road_width()`（不能再写死一个数）。
	t.ok(_src_body(src, "_build_city_street_infra(").contains("city_road_width("),
		"`_build_city_street_infra()` 的宽度取自 `city_road_width()`（三档真的被用上）")


# ---------------------------------------------------------------- R2：错落 + 更高的摩天大楼

## R2 的根因**不是**"分带不够多"，而是**分带是圆的**：
## `city_lot_for()` 里 `d = sqrt(u²+v²)` 直接进分区判断 ⇒ 分区是**严格同心圆**
## ⇒ 同一圈上的楼抽同一个 `[h_min, h_max]`，**从任何方位看天际线剖面都一样**。
##
## 两处修法各自对应一条判据：**方位调制**（分区不再是圆）+ **格点噪声**（邻居不同高）。
static func _city_r2_skyline(t: T) -> void:
	var oen: Dictionary = WorldBuilder.CITY_SHAPE[MapDef.CityLayout.OENBELLI]
	var dv: Dictionary = WorldBuilder.CITY_SHAPE[MapDef.CityLayout.DAVAO]
	# ---- 表：奥恩贝利必须**逐位不变**（"新参数默认 = 现值"这条约定）----
	t.eq(oen.dir_ph1, 0.0, "奥恩贝利谐波相位 1 = 0（旧行为原样）")
	t.eq(oen.dir_ph2, 0.0, "奥恩贝利谐波相位 2 = 0（旧行为原样）")
	t.eq(oen.dt_mul, 1.0, "奥恩贝利市中心倍率 = 1.0（原样；「更高的摩天大楼」只给达沃）")
	t.eq(oen.needle_mul, 1.0, "奥恩贝利针塔倍率 = 1.0（原样）")
	# ---- 表：达沃真的被抬高了 ----
	t.gt(absf(dv.dir_ph1) + absf(dv.dir_ph2), 0.5,
		"达沃的两个谐波相位都不为 0（分区形状与奥恩贝利**不同**，不是同一座城换滤镜）")
	var dt: float = dv.dt_mul
	t.gt(dt, 1.0,
		"达沃市中心楼高倍率 %.2f > 1.0（老板：「达沃需要更高的摩天大楼」）" % dt)
	var nm: float = dv.needle_mul
	t.gt(nm, dt,
		("达沃针塔倍率 %.2f > 市中心倍率 %.2f ⇒ 针塔的**相对**高度没有被楼群吃掉"
			+ "（它是这张图的方位锚点）") % [nm, dt])

	# ---- ⚠️ 核心判据：分区**不是圆的** ----
	#
	# ⚠️ 为什么"同区高度极差 / 中位数"那条是**不够**的：旧的同心圆实现里，
	# 每个地块仍然各自独立抽一次 `randf_range(h_min, h_max)` ⇒ 极差本来就大，
	# 那条判据对**旧实现照样绿**（拦不住这个 bug —— 我第一次就差点只写它）。
	# 真正能把它拦下来的是：「**同一个半径圈上出现了两个不同的分区**」。
	# 旧实现下分区是半径的函数 ⇒ 每圈只有一个 zone ⇒ 这条**必然红**。
	var oen_scan := _city_scan(MapDef.CityLayout.OENBELLI)
	var dv_scan := _city_scan(MapDef.CityLayout.DAVAO)
	var scans := {MapDef.CityLayout.OENBELLI: oen_scan, MapDef.CityLayout.DAVAO: dv_scan}
	for li: int in [MapDef.CityLayout.OENBELLI, MapDef.CityLayout.DAVAO]:
		var sc: Dictionary = scans[li]
		var cells: int = sc.cells
		var mixed: int = sc.ring_mixed
		# ⚠️ 下界给 100（实测奥恩贝利 **149**、达沃 **400+**）：`_city_scan()` 是**按格**遍历
		# （最多 `CITY_GRID² = 1 296` 个），比 `suite_round` 里那种 96×96 连续采样**粗**
		# —— 它要的是"每格一栋楼"的真实读数，不是密度图。下界只要拦住"筛空了"。
		t.gt(float(cells), 100.0,
			"CityLayout[%d] 扫到 %d 个规划陆地格（采样没跑空）" % [li, cells])
		t.gt(float(mixed), 2.0,
			("CityLayout[%d]：有 %d 个半径圈上出现了 ≥2 个分区 ⇒ 分区边界不是同心圆"
				+ "（旧的 `d = sqrt(u²+v²)` 实现下这里恒为 0）") % [li, mixed])
		# 错落（同区内部的极差）：这条是**守卫**，不是主判据 —— 见上面的 ⚠️。
		var by_zone: Dictionary = sc.heights
		for zk in by_zone.keys():
			var hs: Array = by_zone[zk]
			if hs.size() < 12:
				continue
			hs.sort()
			var lo := float(hs[0])
			var hi := float(hs[hs.size() - 1])
			var med := float(hs[hs.size() / 2])
			var spread := (hi - lo) / maxf(med, 1.0)
			t.gt(spread, 0.35,
				("CityLayout[%d] / %s：高度极差 ÷ 中位 = %.2f ≥ 0.35（同一分区内也不是一刀平）"
					% [li, String(zk), spread]))

	# ---- 观测：达沃市中心真的更高 ----
	var oen_med := _median(oen_scan.heights.get("downtown", []))
	var dv_med := _median(dv_scan.heights.get("downtown", []))
	t.gt(oen_med, 1300.0,
		"奥恩贝利市中心楼高中位 %.0f m（仍是市中心，不是矮房）" % oen_med)
	var med_ratio := dv_med / maxf(oen_med, 1.0)
	t.gt(med_ratio, 1.25,
		("达沃市中心楼高中位 %.0f m ÷ 奥恩贝利 %.0f m = %.2f 倍 > 1.25"
			+ "（`dt_mul` 的直接读数）") % [dv_med, oen_med, med_ratio])
	# ---- 针塔仍然是达沃最高的东西 ----
	# `_city_needle_tower()`：四段塔身 1250+1300+1050+600 = 4200 m，加针 700 m ⇒ **4900 m**，
	# 整体再乘 `needle_mul`。这里与整城楼高倍率 `city_height_mul` 对账。
	var dv_h_mul := MapDef.davao().city_height_mul
	var needle_h := 4900.0 * nm
	var tallest := _arr_max(dv_scan.heights.get("downtown", [])) * dv_h_mul
	var needle_ratio := needle_h / maxf(tallest, 1.0)
	t.gt(needle_ratio, 1.15,
		("达沃针塔 %.0f m ÷ 最高楼 %.0f m = %.2f 倍 > 1.15 ⇒ 它还是最好认的那根柱子"
			+ "（⚠️ 4900 是 `_city_needle_tower()` 的 segs + 针的合约值）")
			% [needle_h, tallest, needle_ratio])

	# ---- ⚠️ 两处修法必须在源码里（防"参数加了但没用上"）----
	var lot_src := _src_body(_city_src(), "city_lot_for(")
	t.ok(lot_src.contains("atan2("), "`city_lot_for()` 里有方位调制（`atan2`）")
	t.ok(lot_src.contains("nrng.seed = _city_lot_seed("),
		("`city_lot_for()` 的格点噪声用**派生的独立 rng**（`nrng`）——"
			+ "⛔ 不能去抽那条整城共享的顺序序列 `rng`，否则全城楼高序整体移位"))
	t.ok(lot_src.contains("dt_mul"), "`city_lot_for()` 真的用了 `dt_mul`")


# ---------------------------------------------------------------- R3：构件不许在水上

## R3 的根因**不是"筛选漏了"，是地面本身在水下**：
## 水面原先铺在 `y = +0.2`，而 `_city_landform()` 的四层起伏实测范围 **−7.9 … +7.9 m**
## ⇒ **53.0% 的陆地比水面低** ⇒ 无论怎么筛，都有一半的城"泡在浅水里"。
##
## 修法两件：水面降到 `CITY_WATER_Y = −12`（低于陆地最低点）+ 一道**地形干燥闸门**
## `city_is_dry()`（房子 / 路灯 / 公路三处都要过）。
static func _city_r3_no_structure_on_water(t: T) -> void:
	t.lt(WorldBuilder.CITY_WATER_Y, 0.0,
		"城市水面标高 %.1f m < 0（原来是 +0.2）" % WorldBuilder.CITY_WATER_Y)
	t.gt(WorldBuilder.CITY_DRY_MARGIN, 0.0,
		"干燥裕量 %.1f m > 0（不然「刚好等于水面」的格子判据会抖）"
			% WorldBuilder.CITY_DRY_MARGIN)

	# ---- ⚠️ 核心判据：水面必须低于**纯内陆的最低点** ----
	#
	# 这正是一条注释里写着的根因判据：「陆地起伏 −7.9 … +7.9 m，而水面是 +0.2」
	# ⇒ 53% 的陆地比水面低。反过来写就是这条不变量：**水面 < 内陆最低点**。
	#
	# ⚠️ 为什么**必须只在"纯内陆"格上取最低点**（第一版栽在这儿）：
	# `_city_landform()` 对**海湾两侧各约 1.3 km**（渐降 480 m）与
	# **运河两侧各 340 m**（渐降 110 m）的带返回的是**很负的数** ——
	# 而那不是"地面泡在水里"，那是**边坡**。第一版在全陆地格上取**分位数**，
	# 达沃量到 p5 = **−63 m**（正好落在运河坡上）⇒ 判据当场红，而红的原因
	# 跟"水有没有把城淹掉"毫无关系。⇒ 只取"两条挖方支路都走不到"的格。
	# ⚠️ 也不能用"水面 < 陆地最低点"但**不筛**：岸线过渡带里
	# "判据说陆、地形已在水下"是**设计如此**的（`city_is_dry()` 的文档讲了）。
	for li: int in [MapDef.CityLayout.OENBELLI, MapDef.CityLayout.DAVAO]:
		var sc := _city_scan(li)
		var ig: Array = sc.inland
		t.gt(float(ig.size()), 60.0,
			"CityLayout[%d] 采到 %d 个纯内陆高度样本（把边坡剔掉之后还剩多少）"
				% [li, ig.size()])
		var ig_min := _arr_min(ig)
		var ig_max := _arr_max(ig)
		t.gt(ig_min, WorldBuilder.CITY_WATER_Y,
			("CityLayout[%d]：内陆最低点 %.2f m > 水面 %.1f m ⇒ 没有一片内陆天然泡在水里"
				+ "（水面还在 +0.2 m 时这一条必红；实测内陆范围 %.2f … %.2f m）")
				% [li, ig_min, WorldBuilder.CITY_WATER_Y, ig_min, ig_max])

	# ---- ⚠️ 三道闸门必须**同时**在源码里 ----
	#
	# "房子别在水上 / 路灯别在水上 / 公路别在水上"是**同一个** `city_is_dry()`
	# 的三处调用 —— 而老板正好把这三类各点了一次名。
	# 漏掉任何一处，那一类构件就会浮在水面上。运行时钉不住（MultiMesh 不回读），
	# 所以读源码。
	var src := _city_src()
	for fn: String in ["_build_city_blocks", "_build_city_street_infra",
			"_build_city_street_lamps"]:
		t.gt(src.find("func " + fn + "("), 0, "源码里有 `%s()`" % fn)
	# ⚠️⚠️ 2026-09-28 v3：路灯**不再自己判干燥** —— 它消费 C1 产出的
	# `_city_dry_spans`（"唯一真源"，F2）⇒ 判据放宽成**两条合法路径**之一。
	# ⚠️ 但"同源"这件事本身**必须**钉住：旧做法里路面用三点全干判、灯用三点
	# 各判一点 ⇒ 两套判据本来就不一致；C1 一改成段内裁剪，灯就会在路已收口的
	# 地方继续排（灯站在水里 / 岸上）。
	var lamp_src := _src_body(src, "_build_city_street_lamps(")
	t.ok(lamp_src.contains("city_is_dry(") or lamp_src.contains("_city_dry_spans"),
		"`_build_city_street_lamps()` 与路面**同源**（直接判干燥，或消费 `_city_dry_spans`）")
	t.ok(lamp_src.contains("_city_dry_spans"),
		"⚠️ 而且走的是**同源那条路**（C1 的 `_city_dry_spans`，而不是自己再判一次）")
	# C1 的判据真源：`_city_road_ok()` 必须调 `city_is_dry()`
	t.ok(_src_body(src, "_city_road_ok(").contains("city_is_dry("),
		"`_city_road_ok()` 里调用了 `city_is_dry()`（C1 的干燥判据真源）")
	t.ok(_src_body(src, "_build_city_street_infra(").contains("_city_road_ok("),
		"`_build_city_street_infra()` 用的是那个真源（不是另写一套）")
	for fn2: String in ["_build_city_blocks"]:
		t.ok(_src_body(src,fn2+"(").contains("_city_fit_parcel(")
			and _src_body(src,"_city_fit_parcel(").contains("_city_surface_rect_clear(")
			and _src_body(src,"_city_surface_rect_clear(").contains("city_is_dry("),
			"建筑落位通过完整占地检查，复用地形和水域判据")
	# ---- 城市边界门：两档都要在（`RADIAL` 用 `CITY_ROAD_R`，`ISLAND` 用 `city_is_land`）----
	t.gt(WorldBuilder.CITY_ROAD_R, WorldBuilder.CITY_HILL_IN - WorldBuilder.CITY_CBLOCK * 2.0,
		"城市边界门 %.0f m 不早于「山脚退一格」（否则最外一圈路会贴着坡脚断掉）"
			% WorldBuilder.CITY_ROAD_R)
	var gate_src := _src_body(src, "_city_road_ok(")
	t.ok(gate_src.contains("CITY_ROAD_R") and gate_src.contains("city_is_land"),
		"边界门两档都在源码里（`RADIAL` → `CITY_ROAD_R` / `ISLAND` → `city_is_land`）")
	# ---- `city_is_dry()` 本身：纯函数、只认地形 ----
	var dry_src := _src_body(src, "city_is_dry(")
	t.gt(float(dry_src.length()), 40.0,
		"切到了 `city_is_dry()` 的源码块（切空了会让下面两条自动绿）")
	t.ok(dry_src.contains("_city_landform("),
		"`city_is_dry()` 判定的是**地形**（`_city_landform`）")
	t.not_ok(dry_src.contains("rng"),
		"`city_is_dry()` 不认识 rng ⇒ 同一坐标永远同一个答案")
	# ---- 楼底标高：过了闸门的楼，地面一定高于水面 ----
	# 闸门要求每个采样点都干燥，而落位取采样点的**最大值** ⇒ 楼底 ≥ 水面 + 裕量。
	#
	# ⚠️ B7（2026-09-28）：判据的**落点**从"整格取 3×3 九点、结果存一个 `ground`"
	# 下移到"**每个子地块**取 1 中心 + 4 角、结果存 `gy`" —— 因为一格现在是 2~8 栋，
	# 整格丢会把岸线附近整片削光。**"楼落在真实地形上"这件事没变**，变的只是粒度。
	# 断言因此改成钉"落位标高来自 `_city_landform()`"＋"每栋各自算一个 `gy`"。
	var blk_src := _src_body(src, "_build_city_blocks(")
	t.ok(blk_src.contains("_city_landform("),
		"`_build_city_blocks()` 的落位标高来自 `_city_landform()`，不是写死 y = 0")
	t.ok(blk_src.contains("gy"),
		"`_build_city_blocks()` 给**每个子地块**各算一个落位标高 `gy`（B7：一格 N 栋）")


# ------------------------------------------------- R4：立像拆掉换停车场 + 丘陵 ×3

## 用户（2026-09-28）：
##   「中间的**独角兽立象模型可以拆了换成停车场**」
##   「**奥恩贝利的丘陵高度**改的再高 3 倍」
##
## ## ⚠️ 两块都用"**结构性判据 + 纯函数判据**"，理由与 R1~R3 相同
## 停车场与丘陵都是**几何**，而无头环境回读几何不可靠：
## `MultiMesh.get_instance_transform()` 读回来**全是单位变换**
##（R1 那一块就栽在这上面，所以路面/桥面只能读源码）。
## 于是这里的判据分三层：
##   ① **源码层**：函数在不在、调用点在不在、有没有夹带自发光；
##   ② **常量层**：幅度 / 落位格；
##   ③ **纯函数层**：**在环带上实测峰值**（这条是唯一拦得住
##      "常量改了但函数里乘的是别的数"的判据）。
static func _city_r4_parking_and_hills(t: T) -> void:
	var src := _city_src()
	# ---- ① 立像真的拆了 ----
	t.eq(src.find("func _city_gundam_statue("), -1,
		"源码里**没有** `_city_gundam_statue()` 了（立像连同它的体量一起删掉）")
	t.eq(src.find("GundamBase"), -1, "立像的底座节点 `GundamBase` 也一并消失")
	# ---- ② 停车场建出来了，而且落在**它自己的地标格**上 ----
	t.gt(src.find("func _city_parking_lot("), 0, "源码里有 `_city_parking_lot()`")
	var lm_src := _src_body(src, "_build_city_landmarks_oenbelli(")
	# ⚠️ 2026-09-28：格号 **0,3 → 4,2**。依据是详规 §E.1 #4：`(4, 2)` 是
	# **独角兽立像本来该在的位**，而这一轮用户的口径是"**拆像换成停车场**"⇒
	# 换上的是停车场、**站位不动**（"拆像"不该顺带把那一格还给住宅楼）。
	# 旧格 `(0, 3)` 已经归还给住宅地块，由上面那张"旧四格"反向断言守着。
	t.ok(lm_src.contains("_city_parking_lot(_city_cell_center(4, 2))"),
		"停车场由**格坐标**落位（`_city_cell_center(4, 2)`）—— 与 `_city_landmark_cell` "
		+ "表里压抑掉的那一格**是同一格** ⇒「楼长进停车场里」在几何上不可能发生")
	t.ok(WorldBuilder._city_landmark_cell(4, 2),
		"`(4, 2)` 在地标表里（那一格因此不长楼）")
	var lot_src := _src_body(src, "_city_parking_lot(")
	t.gt(float(lot_src.length()), 500,
		"切到了 `_city_parking_lot()` 的函数体（切空了会让下面几条自动绿）")
	# 四件构件一个都不能少：场地 / 车位线 / 车 / 灯柱。
	for part: String in ["ParkDeck", "ParkStripes", "ParkCar", "ParkMast"]:
		t.ok(lot_src.contains(part), "停车场里有 `%s`" % part)
	t.ok(lot_src.contains("_add_multimesh("),
		"车位线走 **MultiMesh**（一次 draw call、零碰撞），不是几百个 `StaticBody3D`")
	# ⚠️ 死城不许点灯：这一段**不许**出现自发光。
	# 判据不是"看看有没有亮"（渲染层的东西无头读不到），而是"这一段源码里
	# 有没有那条会点亮的路径" —— `_add_box()` 的第 8 个位置参数就是 `emissive`。
	t.not_ok(_strip_comments(lot_src).contains("emissive"),
		"停车场**不带自发光**（奥恩贝利是死城：`map.city_lights == false`）")
	# ⚠️ 也**不许**抽 `_city_rng`：那是整座城共享的顺序序列，
	# 在这里多抽一次，全城的楼高/配色会整体平移（根因在几百行之外）。
	t.not_ok(_strip_comments(lot_src).contains("_city_rng"),
		"停车场的车位/车色由**下标算术**给定，不消耗 `_city_rng`（否则全城楼高整体移位）")

	# ---- ③ 丘陵：幅度 ×3 + **形状改平滑**（V2 · 2026-09-28 用户第二轮反馈）----
	#
	# ⚠️ V1 在这里写的是"**只改幅度、不改波长**"（核四个旧频率都在）。
	# 用户第二轮说「太高了，太尖了，能不能做的一体一点并且平滑一些」之后，
	# **波长必须动** —— 旧的最短一层 λ 700 m 的脊距只有 0.58 格，在格点上
	# 就是纯噪声，那正是"一排刀锋"的成因之一。所以 V1 那两条断言要**删掉**：
	# 留着它会拦住正确的修改（断言与设计目标脱节就是这个样子）。
	t.near(WorldBuilder.CITY_HILL_AMP, 6600.0, 0.001,
		"奥恩贝利丘陵幅度 %.0f m（旧值 2 200 × 3）" % WorldBuilder.CITY_HILL_AMP)
	var hill_src := _src_body(src, "_city_hills(")
	for k: String in ["0.000104720", "0.000241661", "0.000571199"]:
		t.ok(hill_src.contains(k),
			"八度 %s 是 V2 的长波长（λ = 60 / 26 / 11 km，脊距 ≥ 9 格）" % k)
	t.not_ok(hill_src.contains("0.008980"),
		"V1 那层 λ 700 m（**脊距 0.58 格 = 纯噪声**）已从 `_city_hills()` 里删除")
	t.ok(hill_src.contains("_city_ridge_smooth("),
		"峰顶用**软绝对值** —— 硬 `absf()` 在零点的一阶折角就是「刀锋」本身")
	t.not_ok(hill_src.contains("CITY_HILL_FLOOR"),
		"**不再有「低于阈值归零」**：那一步把 22.8% 的面积压成绝对平地"
			+ "⇒ 旁边有平地做参照，任何起伏都读成「插在上面的针」")
	t.ok(src.contains("CITY_HILL_SOFT_DEN"),
		"软绝对值**做了归一化**（少了它峰顶只能到 1−EPS ⇒ 峰值被砍到 51%）")

	# ⚠️⚠️ **本轮最有价值的一条**：坡角必须**实测**，不能靠"改了形状"自证。
	# "太尖"这件事只有坡角拦得住 —— 峰值、幅度、频率都能全绿而山照样是一排针。
	# ⚠️ 步长取**渲染格距**（`TERRAIN_DETAIL_SIZE / CITY_GROUND_SEG` = 301.2 m），
	# 这样"贴奈奎斯特的层在网格上走样"会真的体现在读数里（那正是 V1 的病）。
	var hill_step := WorldBuilder.TERRAIN_DETAIL_SIZE / float(WorldBuilder.CITY_GROUND_SEG)
	var steep := 0
	var steps := 0
	for i in 120:
		var ang := TAU * float(i) / 120.0
		var cx := cos(ang)
		var cz := sin(ang)
		var rdist: float = WorldBuilder.CITY_HILL_OUT
		var prev := WorldBuilder._city_hills(cx * rdist, cz * rdist)
		for k in 40:
			rdist += hill_step
			var cur := WorldBuilder._city_hills(cx * rdist, cz * rdist)
			if rad_to_deg(atan(absf(cur - prev) / hill_step)) > 50.0:
				steep += 1
			steps += 1
			prev = cur
	var steep_pct := 100.0 * float(steep) / float(steps)
	t.lt(steep_pct, 12.0,
		"环带内坡角 > 50° 的采样占 %.1f%% ≤ 12%% ⇒ 通篇是**连续的坡面**，不是一排刀锋"
			% steep_pct)
	# 贴地面积：沿环带走一圈统计"高度低于 5% 幅度"的比例 —— "一体"的直接判据。
	# V1 实测 22.8%，V2 是 0.0%（与 `suite_gfx_map` 那条同源，采样区不同）。
	# ⚠️⚠️ 2026-09-28：**采样半径必须全部 ≥ `CITY_HILL_OUT`** —— 环带外移之后
	# 旧的 `54/62/70/80/90 km` 里只有 90 km 落在淡入已满的那一段，其余四个都
	# 落在 `r ≤ 82 km` 的**恒零区** ⇒ `h = 0 < 5% 幅度` ⇒ 贴地面积被算成 60%。
	# 那不是"山变平了"，是**取样点落在没有山的地方**。⇒ 搬到 96…100.8 km
	#（`TERRAIN_DETAIL_SIZE / 2 = 101 200` 之内）。
	var flat := 0
	var tot := 0
	for i in 720:
		var ang2 := TAU * float(i) / 720.0
		for r2: float in [96000.0, 97200.0, 98400.0, 99600.0, 100800.0]:
			tot += 1
			if WorldBuilder._city_hills(cos(ang2) * r2, sin(ang2) * r2) \
					< WorldBuilder.CITY_HILL_AMP * 0.05:
				flat += 1
	var flat_pct := 100.0 * float(flat) / float(tot)
	t.lt(flat_pct, 3.0,
		"环带贴地面积 %.1f%% ≤ 3%% ⇒ 山体**连成一体**（V1 实测 22.8%%）" % flat_pct)

	# ⚠️ 只断言"常量 == 6600"拦不住"常量改了、而函数里乘的是别的数"——
	# `_city_hills()` 若把 `p.hill_amp` 换成字面量 2 200，上面那条照样绿。
	# ⚠️ 半径取 **`CITY_HILL_OUT` 以外**：那里 `t == 1`（淡入已满），
	# 是这条环带幅度最完整的地方 —— 与 `suite_gfx_map` 那一条的采样区一致。
	# ⚠️ 2026-09-28 同上面那条：原来的 `52/62/74/88 km` 现在**全部落在恒零区**，
	# 峰值会读成 0 ⇒ 整条断言失去意义（"山上没有山"永远为真）。
	var peak := 0.0
	for i in 240:
		var ang := TAU * float(i) / 240.0
		for rr: float in [96000.0, 97500.0, 99000.0, 100500.0]:
			peak = maxf(peak, WorldBuilder._city_hills(cos(ang) * rr, sin(ang) * rr))
	t.gt(peak, 2200.0,
		"环带实测峰值 %.0f m **超过旧的 2 200 m** ⇒ ×3 真的进了几何" % peak)
	t.lt(peak, WorldBuilder.CITY_HILL_AMP + 0.001,
		"峰值 %.0f m 不超过 `CITY_HILL_AMP`（没有越界）" % peak)

	# ---- ④ 达沃的丘陵**没被连带改** ----
	# 用户说的是"**奥恩贝利的**丘陵"。达沃那一行在 `CITY_SHAPE` 里写的是**字面量**，
	# 一旦有人把它改成引用常量，改奥恩贝利就会顺带把达沃的山抬高 3 倍（静默连带改动）。
	var davao_amp: float = WorldBuilder.CITY_SHAPE[MapDef.CityLayout.DAVAO].hill_amp
	var oen_amp: float = WorldBuilder.CITY_SHAPE[MapDef.CityLayout.OENBELLI].hill_amp
	t.near(davao_amp, 2200.0, 0.001,
		"达沃的丘陵幅度仍是 2 200 m（%d 个字的改动不许越过图界）" % int(davao_amp))
	t.near(oen_amp, WorldBuilder.CITY_HILL_AMP, 0.001,
		"奥恩贝利那一行**引用常量**（不是抄字面量）⇒ 常量改了它跟着走")
	t.gt(oen_amp / davao_amp, 2.9,
		"两座城的丘陵幅度比 %.2f ≥ 3（表里真的分岔了，不是一个数抄两遍）"
			% (oen_amp / davao_amp))


# ---------------------------------------------------------------- 工具（1.3 批 M）

## 一座城的**地块表指纹**：按格遍历，把每格的 分区/形态/楼高/配色/立面类别
## 打成一行字符串拼起来。
##
## ## 为什么是"指纹字符串"而不是直接比 `Dictionary`
## 失败时要能**直接印出来**。`t.eq` 打印的 diff 对"几百项嵌套字典"几乎不可读，
## 而一条长字符串至少在"第一处不同在哪一格"上还算能看。
##
## ## 判据（设计书 §3.6 的"达沃专属门"）
##   · 同一份 `seed_value` 建两次 ⇒ 指纹**完全相同**（确定性）；
##   · 两份不同的 `seed_value` ⇒ 指纹**不同**（真的换了一座城）。
## 两条必须**同时**成立：只有第一条 ⇒ 两座城一模一样；只有第二条 ⇒ 布局不可复现。
static func _lot_table(seed_value: int) -> String:
	var half := int(WorldBuilder.CITY_GRID) / 2
	var rng := RandomNumberGenerator.new()
	var out := PackedStringArray()
	for gx in range(-half, half):
		for gz in range(-half, half):
			if not WorldBuilder.city_is_land(gx + 0.5, gz + 0.5):
				continue
			rng.seed = WorldBuilder._city_lot_seed(gx, gz, seed_value)
			var lot: Dictionary = WorldBuilder.city_lot_for(gx, gz, rng, seed_value)
			out.append("%d,%d|%s|%d|%.2f|%s|%d" % [gx, gz, lot.zone, lot.shape,
				lot.h, lot.color.to_html(), lot.facade])
	return " ".join(out)


## `city_is_land()` 的**源码块**（从函数头到下一个空行段）。
##
## ⚠️ 为什么在测试里读源码：要钉住的是"**它不认识种子**"这条**结构性**性质 ——
## 运行时无论怎么调它，只要签名里没有种子，答案就恒定；这正是问题所在：
## 一个"看起来对"的运行时断言（比如同一坐标问两次得到同一个答案）**永远会绿**，
## 哪怕有人把 `map.city_seed` 混进了实现里。只有读源码才拦得住。
##
## ⚠️ 不剥注释也不怕：这个函数块的注释里没有 `map` / `city_seed` 这两个词
##（`_city_lot_seed()` 的注释里有，但那在别的函数块里 —— 见下面的切片边界）。
static func _coast_src() -> String:
	var s := FileAccess.get_file_as_string("res://scripts/world/world_builder.gd")
	var i := s.find("static func city_is_land(")
	if i < 0:
		return ""
	var j := s.find("\n\n\n", i)
	return s.substr(i, (j - i) if j > i else 256)


## 去掉 `#` 及其后的注释（整行与行内），用于"源码里有没有某个**调用**"这类判据。
##
## ⚠️ 不剥注释的话，"注释里写了 `_city_rng` 都不抽"会被读成"它调用了 `_city_rng`"，
## 于是**注释写得越清楚越容易红** —— 本轮的 `_city_parking_lot` 就是这么红的
##（R4 那一块第一版 450 PASS / 1 FAIL，红的正是这一条）。
## 同理 `emissive`：注释里写"不带自发光"是中英混排时最容易踩的另一种写法。
static func _strip_comments(s: String) -> String:
	var out := PackedStringArray()
	for line: String in s.split("\n"):
		var i := line.find("#")
		out.append(line if i < 0 else line.substr(0, i))
	return "\n".join(out)


## `world_builder.gd` 的全文。
##
## ⚠️ 有几条判据只能读源码（"某处调用还在不在"这类**结构性**性质）：
## 路面 / 桥面 / 护栏都是 MultiMesh，而无头环境下
## `MultiMesh.get_instance_transform()` 读回来**全是单位变换**
## ⇒ 运行时无论怎么查都查不出"它到底建了没有"。
static func _city_src() -> String:
	return FileAccess.get_file_as_string("res://scripts/world/world_builder.gd")


## 源码里 `func <decl> …` 的函数体，切到**下一个顶格 `func`** 为止。
##
## ⚠️ 必须**同时**找 `\nfunc ` 与 `\nstatic func `：`world_builder.gd` 里两种混用，
## 只找前者时，若下一个函数是 `static func`，切片会**越过它**拉到更后面 ——
## 于是"把闸门删了"也能读到别人的代码、断言照样绿。
## 这是结构性断言最容易失效的方式，所以这里单独写死。
static func _src_body(src: String, decl: String) -> String:
	var i := src.find("func " + decl)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 1)
	var k := src.find("\nstatic func ", i + 1)
	if k > i and (j < 0 or k < j):
		j = k
	if j < 0:
		j = i + 4000
	return src.substr(i, maxi(j - i, 1))


## 把一张城的**规划陆地格**扫一遍，回一份汇总（一次遍历喂 R2 / R3 的多条判据）。
##
## 返回：
##   `cells`      —— 扫到的陆地格数
##   `heights`    —— `{zone: [lot.h, ...]}`
##   `ring_mixed` —— **同一个半径圈上出现了 ≥2 个分区**的圈数
##                   （⚠️ 这是"分区不是同心圆"的唯一可观测；旧的
##                    `d = sqrt(u²+v²)` 实现下它**恒为 0**）
##   `ground`     —— 每个格心的 `_city_landform()` 高度（米）
##
## ⚠️ 取数与真实建城**同一套**：`_city_lot_seed(gx, gz, seed)` → `rng` → `city_lot_for()`，
## 所以 `lot.h` 与 `_build_city_blocks()` 读到的**逐位一致**（只差整城统一的
## `city_height_mul`，而它是常数倍率 ⇒ 不影响"错落"这类相对量）。
static func _city_scan(layout: int) -> Dictionary:
	var half := int(WorldBuilder.CITY_GRID) / 2
	var cblock := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var seed_value := WorldBuilder.CITY_SEED
	if layout == MapDef.CityLayout.DAVAO:
		seed_value = MapDef.davao().city_seed
	var p: Dictionary = WorldBuilder.CITY_SHAPE[layout]
	var hf: float = p.zone_hf
	var cz: float = p.cz
	var heights := {}
	var ground: Array[float] = []
	var inland: Array[float] = []
	var rings := {}
	var cells := 0
	for gx in range(-half, half):
		for gz in range(-half, half):
			# ⚠️ 城域坐标（与 `city_is_land()` / `city_lot_for()` **完全同一套**：
			# 格心 = 格号 + 0.5）。
			if not WorldBuilder.city_is_land(float(gx) + 0.5, float(gz) + 0.5, layout):
				continue
			var wx := (float(gx) + 0.5) * cblock
			var wz := (float(gz) + 0.5) * cblock
			if WorldBuilder.is_water_at(wx, wz, layout):
				continue                       # 规划就是水面（海湾 / 运河）
			cells += 1
			var gh := WorldBuilder._city_landform(wx, wz, layout)
			ground.append(gh)
			if _inland(p, wx, wz):
				inland.append(gh)
			var rng := RandomNumberGenerator.new()
			rng.seed = WorldBuilder._city_lot_seed(gx, gz, seed_value)
			var lot: Dictionary = WorldBuilder.city_lot_for(gx, gz, rng, seed_value, layout)
			var zone := String(lot.zone)
			if not heights.has(zone):
				heights[zone] = []
			heights[zone].append(float(lot.h))
			# 半径圈 → 该圈出现过的分区集合。⚠️ 分箱用的是**未调制**的原半径 `d0` ——
			# 那才是"同心圆"那个假设的坐标；用调制后的 `d` 分箱会把这个性质抹掉。
			var u := (float(gx) + 0.5) / hf
			var v := (float(gz) + 0.5 - cz) / hf
			var d0 := sqrt(u * u + v * v)
			var bin := int(round(d0 * 50.0))
			if not rings.has(bin):
				rings[bin] = {}
			rings[bin][zone] = true
	var ring_mixed := 0
	for b in rings.keys():
		if rings[b].size() >= 2:
			ring_mixed += 1
	return {"cells": cells, "heights": heights, "ground": ground,
		"inland": inland, "ring_mixed": ring_mixed}


## 这一点是不是**纯内陆** —— 即"海湾 / 运河那两条挖方支路都不会走到它"。
##
## ⚠️ 为什么需要它：`_city_landform()` 对**岸线两侧各约 1.3 km 的带**（海湾 smoothstep
## 渐降 480 m）与**运河两侧各 340 m 的带**（渐降 110 m）返回的是**很负的数**
## —— 而那两条带**本来就是边坡**，不是"地面泡在水里"。
## 拿它们去算"陆地最低点"，量到的是**坡**，不是地。
##
## ⇒ 判"水面低于陆地最低点"时必须只用纯内陆格：那些格上 `_city_landform()`
## 返回的就是 `grit + hills` 本身。
##
## ⚠️ 这是**刻意的重复**（同 `_lot_table()` 那句"取数与真实建城同一套"）：
## 条件必须与 `_city_landform()` 里的两条 `if` 逐字一致，否则筛出来的不是同一批格。
static func _inland(p: Dictionary, x: float, z: float) -> bool:
	var side: float = p.bay_side
	var coast: float = float(p.bay_z) + float(p.bay_wave) * sin(x / float(p.bay_lam))
	if (z - (coast - 1400.0 * side)) * side > 0.0:
		return false                       # 落进海湾的渐降带
	if p.has("canal_x"):
		# ⚠️⚠️ 2026-09-28：这一条**必须包在 `has()` 里** —— 奥恩贝利的
		# `CITY_SHAPE[0]` 里**没有** `canal_x / canal_half / canal_end_z` 三个键
		#（它的运河是"四块岛的补集"，见 `OENB_BLOCKS`）。直接取 = **运行时崩**
		#（GDScript 里字典取不存在的键不是 `null`，是错误）。
		if absf(x - float(p.canal_x)) < float(p.canal_half) + 340.0 \
				and z < float(p.canal_end_z):
			return false                   # 落进运河的渐降带
	# ⚠️ 奥恩贝利那一支**不需要**补一条运河判据，理由是一条算术：
	# 运河占**一整格**（4 025 m）宽 ⇒ 任何"格心不是水"的岛格，离块边至少
	# `7.9 / 2 × 4 025 ≈ 2 012 m`，而运河坡只有 `CITY_CANAL_RAMP = 340 m`
	# ⇒ 格心**不可能**落在坡上。（`_city_scan()` 只取格心，所以这就够了。）
	return true


## 中位数（对副本排序，不动调用方的数组）。
static func _median(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var a := xs.duplicate()
	a.sort()
	return float(a[a.size() / 2])


## 最大值（空数组回 0.0）。
static func _arr_max(xs: Array) -> float:
	var m := 0.0
	for x in xs:
		m = maxf(m, float(x))
	return m


## 最小值（空数组回 0.0）。
static func _arr_min(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var m := INF
	for x in xs:
		m = minf(m, float(x))
	return m
