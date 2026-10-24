class_name SuiteCampaign
extends RefCounted
## 剧情模式（轮 0 存档 + 轮 A 数据层）的断言。
##
## ⚠️ **独立文件**，不塞进别人的 suite —— 本仓库有并行会话，塞进别人的文件等于
## 在别人的地盘上写（那正是"两个写者"那条铁律的反面教材）。
## ⚠️ **按主题命名，不占轮次号**：见 `test_runner.gd` 注册表里的红字。
##
## ## 这一套钉的是什么（对着 DESIGN §11.1 的清单逐条落）
##   1. **表结构**：7 关、两章、序章不进序列、`MASK_ORDER` 与 `MS.all()` 顺序一致
##      （错位 = 老存档进度对不上关卡，**一处都不报错**）；
##   2. **纯函数逐点验**：`Objective` 十种判定 + `Trigger.eval` 的边界（`89.9` / `90.0`）
##      —— 这是本设计里最大的一块，也是唯一"算错了看不出来"的地方；
##   3. **数据自检**：坏触发器**不报错只静默失效**（`eval` 返回 false），
##      所以必须有一条断言把坏数据**当场点名**；
##   4. **军资三条硬约束**（只加不减 / 从已有读数算 / 重打只补差额）；
##   5. **存档往返 + 还原**：⚠️ 本工程栽过一次"测试把玩家的设置写花了"，
##      所以这里**逐字节**核对真实存档没被动过；
##   6. **兼容门**：现有 4 场遭遇、`MissionRating` 的四个 par 分支、两种模式枚举都不许变。
##
## ⚠️ **跨文件引用走 `preload`，不走 `class_name`**（理由同 `campaign.gd` 里那段）：
## 新加的 `class_name` 在编辑器重新扫描之前**不在全局类缓存里**，
## 无头跑测试时没有人会去刷新它 ⇒ `MissionScript.xxx` 会当场编译失败。

const MS := preload("res://scripts/data/mission_script.gd")
const CS := preload("res://scripts/data/campaign.gd")

## 套件自己的临时档案（**绝不碰** `user://campaign.cfg`）。
const TMP := "user://campaign_suite_tmp.cfg"

## §4.2 的「播片 B/M/D」一列，逐关照抄。
const CUT_QUOTA := {
	# Chapter III uses the in-engine title card and adapted radio, without video placeholders.
	"M08": [0,0,0], "M09": [0,0,0], "M10": [0,0,0], "M11": [0,0,0], "M12": [0,0,0],
	"M01": [1, 0, 1], "M02": [1, 1, 0], "M03": [1, 1, 0],
	"M04": [1, 2, 1], "M05": [1, 1, 1], "M06": [1, 0, 0], "M07": [1, 1, 1],
}

## 现在是"暂定"的关（DESIGN §13 的 16 条待拍板里，落在数据上的那几关）。
## 拍板后要把它从 `Mission.pending` 里清掉 —— 不清就会红。
##
## ⚠️ 剧情模式轮 B2：**M03 出列**。它原来挂着两条"还会变"的理由
##（"图（LEO）待轮 B2 新建" + "波次高度与再入线高度待实测"），轮 B2 两件都做完了
## ⇒ `m.pending` 清空、这里同步删掉。
##
## ⚠️⚠️ 这个常量原本**声明了却没人用**（`_struct` 里没有对应的断言）——
## 于是它只是一句注释，上面那句"不清就会红"是**假的**。轮 B2 把它接上了 `_struct`。
# M06 player and objectives confirmed: Arizeus, two Messers, Valiant strike.
const PENDING_NOW := []


static func run(t: T) -> void:
	t.suite("Campaign / M06 Arizeus raid against Valiant")
	var sea=MS.m06()
	t.eq(sea.player_suit,SuitProfile.Id.ARIZEUS,"M06 player is Arizeus")
	t.eq(sea.total_enemies(),2,"M06 exactly two enemy Messers")
	t.eq(sea.enemy_suit,SuitProfile.Id.MESSER_M01,"M06 enemy Messer")
	t.not_ok(sea.win_on_clear,"M06 requires ship strike as well as kills")
	t.not_ok(sea.all_required_done({"killed":2,"total":2,"landmark_hits":0}),"kills alone insufficient")
	t.not_ok(sea.all_required_done({"killed":0,"total":2,"landmark_hits":1}),"ship strike alone insufficient")
	t.ok(sea.all_required_done({"killed":2,"total":2,"landmark_hits":1}),"both goals win in either order")
	t.ok(sea.shows_beacon("valiant_target"),"M06 shows Valiant")
	t.not_ok(sea.shows_beacon("hotel_target"),"M06 does not show Davao hotel")
	t.eq(sea.zones.size(),0,"old escort zone removed")
	t.eq(sea.pending,"","M06 player and objectives decided")
	t.suite("Campaign / M02 player weapon damage isolation")
	var mission = MS.m02()
	var base := SuitProfile.by_id(mission.player_suit)
	var boosted := mission.make_player_profile()
	t.near(boosted.saber_damage, SuitProfile.by_id(mission.enemy_suit).hull_hp * 0.30, 0.001, "M02 player saber is thirty percent of enemy maximum hull")
	t.near(boosted.rifle_damage, 50.0, 0.001, "M02 player rifle is fixed at 50")
	t.near(boosted.vulcan_damage, base.vulcan_damage, 0.001, "other weapons unchanged")
	t.near(boosted.hull_hp, base.hull_hp, 0.001, "player hull unchanged")
	t.near(boosted.saber_damage, 144.0, 0.001, "480 hull gives 144 saber damage, excluding 752 I-field")
	t.near(base.hard_enemy_reinforce, 1.0, 0.001, "M02 enemy maximum hull unaffected by hard reinforcement")
	var retry := mission.make_player_profile()
	t.near(retry.saber_damage, boosted.saber_damage, 0.001, "retry does not compound saber multiplier")
	t.near(retry.rifle_damage, boosted.rifle_damage, 0.001, "retry does not compound rifle multiplier")
	t.near(SuitProfile.by_id(mission.player_suit).saber_damage, base.saber_damage, 0.001, "global suit profile unchanged")
	for other in MS.all():
		if other.id == "M02": continue
		var unchanged: SuitProfile = other.make_player_profile()
		var factory := SuitProfile.by_id(other.player_suit)
		t.near(unchanged.saber_damage, factory.saber_damage, 0.001, other.id + " saber unchanged")
		t.near(unchanged.rifle_damage, factory.rifle_damage, 0.001, other.id + " rifle unchanged")

	_struct(t)
	_arenas(t)
	_pov(t)
	_cutscenes(t)
	_objectives(t)
	_triggers_eval(t)
	_triggers_data(t)
	_zones(t)
	_collectibles(t)
	_credits(t)
	_unlock(t)
	_settle(t)
	_save(t)
	_compat(t)
	_migrate(t)
	_source(t)
	_r50(t)
	_pod_strike(t)


# ============================================================ 1 表结构
static func _struct(t: T) -> void:
	t.suite("剧情模式 / 表结构（12 关 · 三章）")
	var all := MS.all()
	t.eq(all.size(), 12, "战役十二关，第三部追加五关")

	var ids: Array = []
	for m in all:
		ids.append(m.id)
	t.eq(",".join(ids), ",".join(CS.MASK_ORDER),
		"`MS.all()` 的顺序 == `CS.MASK_ORDER`（错位会让老存档的进度对不上关卡，且一处都不报错）")
	t.eq(",".join(CS.mission_ids()), ",".join(CS.MASK_ORDER), "`mission_ids()` 与位掩码顺序同源")

	# ---- ★ "待拍板"标记必须与 `PENDING_NOW` 逐项相等 ----
	#
	# ⚠️ 轮 B2 之前这个常量**没有任何断言用**，所以它上面那句
	# "拍板后要把它从 `Mission.pending` 里清掉 —— 不清就会红"是**假的**
	#（真实情况：清了也不会红、忘了清也不会红，那它就只是一句注释）。
	# 现在两侧都钉住 —— 哪边漏了都会红：
	#   · 数据侧清了 `pending` 而常量没删 ⇒ 这里报"数据侧少了一个"；
	#   · 数据侧新写了个 `pending` 而常量没加 ⇒ 报"多了一个"。
	var pend: Array = []
	for m in all:
		if not m.pending.is_empty():
			pend.append(m.id)
	t.eq(",".join(pend), ",".join(PENDING_NOW),
		"★ 挂着「待拍板」的关与 `PENDING_NOW` 逐项一致（轮 B2 清了 M03）")

	var c1: Array = []
	var c2: Array = []
	for m in all:
		if m.chapter == 1:
			c1.append(m.id)
		elif m.chapter == 2:
			c2.append(m.id)
	t.eq(",".join(c1), "M01,M02,M03,M04", "第一章 4 关（老板：\"总共五个任务\"）")
	t.eq(",".join(c2), "M05,M06,M07", "第二章 3 关（老板：\"总共三个任务\"）")
	t.eq(CS.CHAPTERS.size(), 3, "第三章已加入战役表")
	t.eq(str(CS.CHAPTERS[0]["title"]), "正当的预言之王", "第一章章名")
	t.eq(str(CS.CHAPTERS[1]["title"]), "喀耳刻的魔女", "第二章章名（译名统一成「喀耳刻」）")
	t.eq(CS.chapter_title(1), "正当的预言之王", "chapter_title(1) 取得到")
	t.eq(CS.chapter_title(2), "喀耳刻的魔女", "chapter_title(2) 取得到")
	t.eq(CS.chapter_title(3), "闪光的哈萨维", "第三章标题")

	# 序章是**播片**、不是任务（老板：「豪泽恩号上的事情可以只用播片结束」）。
	t.eq(MS.by_id("M00"), null, "没有 M00 这一关（序章不是任务）")
	t.not_ok(CS.has_mission("M00"), "序章不在战役序列里（位掩码也没它）")
	t.not_ok(CS.has_mission(""), "空 id 不在序列里")
	t.eq(str(CS.PROLOGUE["key"]), "PROLOGUE", "序章有自己的 key（播片槽位 P 用它）")

	# 章内序号连续、标题/文案都不空。
	var idx1: Array = []
	var idx2: Array = []
	for m in all:
		if m.chapter == 1:
			idx1.append(m.index)
		elif m.chapter == 2:
			idx2.append(m.index)
	t.eq(",".join(idx1), "1,2,3,4", "第一章章内序号 1..4 连续")
	t.eq(",".join(idx2), "1,2,3", "第二章章内序号 1..3 连续")

	var blank: Array = []
	var poor: Array = []
	for m in all:
		if m.title.strip_edges().is_empty() or m.brief.strip_edges().is_empty() \
				or m.story.strip_edges().is_empty():
			blank.append(m.id)
		if m.base_reward <= 0:
			poor.append(m.id)
	t.eq(blank.size(), 0, "每关的标题/简报/剧情文案都不空（简报页会直接画出来）。空的：%s" % str(blank))
	t.eq(poor.size(), 0, "每关的基础军资都 > 0。没给的：%s" % str(poor))

	t.eq(MS.for_chapter(1).size(), 4, "`for_chapter(1)` 4 关")
	t.eq(MS.for_chapter(2).size(), 3, "`for_chapter(2)` 3 关")
	t.eq(MS.for_chapter(3).size(), 5, "第三章五关")

	# par：任务自带优先，否则退回 MissionRating 的现成分支。
	var m04 := MS.by_id("M04")
	t.near(m04.par(), 240.0, 0.001, "M04 自带 par（两阶段的关不该按'台数 × 45 s'算）")
	var m01 := MS.by_id("M01")
	t.near(m01.par(), MissionRating.par_secs(Game.MatchMode.CHALLENGE, m01.total_enemies()),
		0.001, "不自带 par 的关退回 `MissionRating.par_secs()`（不新增一套算法）")


# ============================================================ 2 场地
static func _arenas(t: T) -> void:
	t.suite("剧情模式 / 场地（六张图全部解析得出）")
	for a: String in ["PACIFIC", "DAVAO", "OENBELLI", "ULURU", "RANGE", "LEO"]:
		# ⚠️ 用 `>= 0` 不是 `> 0`：`MapDef.Id` 的第 0 项就是 PACIFIC（枚举从 0 起）。
		t.ok(MS.map_id_for(a) >= 0, "六张图都解析得出（%s）" % a)
	t.eq(MS.map_id_for("NOT_A_MAP"), -1, "不认识的场地返回 −1（**不兜到别的图上**）")
	t.eq(MS.map_id_for(""), -1, "空场地返回 −1")

	# ⚠️ ★ 轮 B2 清账 —— 这两条**就是**当初挂在这里的那道门。
	# 轮 A 留下的原话：「轮 B2 一加上 `MapDef.Id.LEO`，下面这行就会红 ——
	# 那时把 "LEO" 从 ARENA_PENDING 挪进 ARENA_MAP 即可」。
	# 它红过，现在按那句话改完了：待建表**空**，而 LEO 在正表里。
	t.eq(MS.ARENA_PENDING.size(), 0,
		"★ 待建场地清空（轮 B2 把低地球轨道建出来了）")
	t.eq(MS.map_id_for("LEO"), MapDef.Id.LEO,
		"★ LEO 从「待建」挪进了正表 —— 解析出的是真的那张图")
	t.ok(not MS.is_arena_pending("LEO"), "……所以它不再是 pending")
	# 这条循环在表非空时才有断言，但**留着**：下一张待建图加进来时自动被它管住。
	for a2: String in MS.ARENA_PENDING:
		t.eq(MS.map_id_for(a2), -1, "待建场地 %s 现在解析不出图（不许指向别的图）" % a2)
		t.ok(MS.is_arena_pending(a2), "is_arena_pending(%s) 为真" % a2)

	var unknown: Array = []
	for m in MS.all():
		if m.arena.strip_edges().is_empty():
			unknown.append("%s(空)" % m.id)
		elif m.map_id() < 0 and not MS.ARENA_PENDING.has(m.arena):
			unknown.append("%s(%s)" % [m.id, m.arena])
	t.eq(unknown.size(), 0, "每关的场地要么在表里、要么在待建表里。异常的：%s" % str(unknown))

	t.eq(MS.by_id("M03").arena, "LEO", "M03「接货」在低地球轨道（老板：\"接货柯西那一关在近地轨道\"）")
	t.eq(MS.by_id("M03").map_id(), MapDef.Id.LEO,
		"★ 轮 B2 之后 M03 的图**建出来了**（不再是 −1）")
	t.eq(MS.by_id("M03").map_name(), MapDef.leo().name_cn,
		"……而且图名是那张图的中文名，不再是「（待建）LEO」")
	t.eq(MS.by_id("M01").arena, "DAVAO", "M01 在达沃（老板：\"达沃空袭在太平洋群岛前面\"）")
	t.eq(MS.by_id("M02").arena, "DAVAO", "M02 也在达沃 —— 与 M01 是同一场战斗的两个座舱")
	t.eq(MS.by_id("M04").arena, "PACIFIC", "M04 重力在太平洋")
	t.eq(MS.by_id("M05").arena, "OENBELLI", "M05 在奥恩贝利")
	t.eq(MS.by_id("M07").arena, "ULURU", "M07 在艾尔斯岩")

	# 每一张"不能白画"的图都要至少进一关（DESIGN §4.2 的覆盖面自检）。
	# ★ 轮 B2 之后是**五张**：四张地球图 + 轨道图（M03 用掉它）。
	var used: Dictionary = {}
	for m in MS.all():
		used[m.arena] = true
	var unused: Array = []
	for a3: String in ["PACIFIC", "DAVAO", "OENBELLI", "ULURU", "LEO"]:
		if not used.has(a3):
			unused.append(a3)
	t.eq(unused.size(), 0, "五张图每张至少进一关。没进的：%s" % str(unused))
	t.not_ok(used.has("RANGE"), "靶场（RANGE）不进战役 —— 它是训练图（DESIGN §13 第 6 条）")

	# ---- 轨道图的两条高度：★ 轮 B2 定稿 ----
	#
	# ⚠️ 轮 A 当初按 DESIGN §4.8.4 的字面把它们写成 100 km / 60 km（"绝对轨道高度"），
	# 并挂了"待实测"。轮 B2 真建图时实测出真正的口径：**本工程的 y 是相对参考面的**，
	# 轨道图的 `y = 0` **就是再入线**（与五张图的 `y = 0` = 海平面 / 地表同构）。
	# ⇒ 这两条不再是"待实测"，而是被**跨模块**钉死：它们必须等于 `WorldBuilder` 里
	#    那两个真源，否则 M03 的目标球会飘在离运输仓 97 km 的空处。
	t.eq(MS.EARTH_ALT, WorldBuilder.PLAYER_START_ALT,
		"地球图交战高度 = `WorldBuilder.PLAYER_START_ALT`（%.0f m）" % WorldBuilder.PLAYER_START_ALT)
	# ★ 2026-09-29：轨道图换成真实高度之后，`ORBIT_ALT` **不再是** `EARTH_ALT` 的别名
	#（地表图交战高度 3.2 km、轨道图 550 km）。改钉到 `WorldBuilder.SPACE_ORBIT_ALT` ——
	# 那才是"两个数必须一起动"的那一对。
	t.eq(MS.ORBIT_ALT, WorldBuilder.SPACE_ORBIT_ALT,
		"★ 轨道图战斗高度 = 地球图交战高度（**数值同构**：同一套阈值在两处都成立）")
	t.eq(MS.REENTRY_ALT, WorldBuilder.SPACE_REENTRY_ALT,
		"★ 再入线 = 卡门线（超下去**不判死**，被推回轨道 —— 见 `_enforce_orbit_floor()`）")
	t.lt(MS.REENTRY_ALT, MS.ORBIT_ALT, "再入线在战斗高度**下面**（贴线飞这件事才有意义）")
	# ★ 最强的一条：**目标球必须真的罩住运输仓**。
	# 只钉"等于某个常量"是自说自话；这条把任务数据和建图数据对起来 ——
	# 谁改了 `SPACE_POD_POS` 或 `ORBIT_ALT` 而没改另一个，这里立刻红。
	t.ok(MS.by_id("M03").zone("orbit_cargo").contains(WorldBuilder.SPACE_POD_POS),
		"★★ M03 的目标球罩住运输仓本体（%s）—— 任务数据与建图数据对得上"
			% str(WorldBuilder.SPACE_POD_POS))
	t.lt(MS.by_id("M03").zone("reentry_line").center.y, MS.ORBIT_ALT,
		"再入线那一层危险区在战斗高度之下")

	# 地形越界自检：Zone 是整个画在场地里的。
	#
	# ⚠️⚠️ **只算水平距离** —— `ARENA_RADIUS` 是那座圆形场地的**水平**半径；
	# 地图是一张平铺在地上的圆盘，不是一颗球，高度（y）不受它约束。
	# 改前那是 `z.center.length()`（含 y），它之所以一直绿，是因为
	# **所有 Zone 的 y 都不超过 3 200 m** —— 一个没人写下来的隐含前提。
	# 2026-09-29 轨道图搬到 550 km 之后它立刻变红：M03 的 `orbit_cargo` /
	# `reentry_line` 两个 Zone 被判"越界"，而它们在水平方向上就在场地**正中心**。
	# ⇒ 这不是"放宽判据"：判据原来那句的**语义**就是错的（拿高度去比水平半径）；
	#   改后它反而更严（`flat` 永远 ≤ `length()`，任何真的水平越界照样红）。
	var outside: Array = []
	for m in MS.all():
		for z in m.zones:
			var flat := Vector2(z.center.x, z.center.z).length()
			if flat + z.outer_radius() > WorldBuilder.ARENA_RADIUS:
				outside.append("%s/%s" % [m.id, z.id])
	t.eq(outside.size(), 0,
		"每个 Zone 都落在场地半径（%.0f m）之内。越界的：%s"
			% [WorldBuilder.ARENA_RADIUS, str(outside)])

	# 时段名：只允许用工程里真有的预设 + 轨道的 space。
	var bad_time: Array = []
	for m in MS.all():
		if not ["night", "dusk_overcast", "space", ""].has(m.time_key):
			bad_time.append("%s(%s)" % [m.id, m.time_key])
	t.eq(bad_time.size(), 0, "时段名都在已知集合里。异常的：%s" % str(bad_time))
	t.eq(MS.by_id("M03").time_key, "space", "M03 是轨道 ⇒ 无昼夜（用 space 预设）")
	t.eq(MS.by_id("M05").time_key, "dusk_overcast", "M05 是阴天黄昏（DESIGN §4.2）")


# ============================================================ 3 POV
static func _pov(t: T) -> void:
	t.suite("剧情模式 / POV 分配（老板要的\"偶尔扮演别人\"）")
	var povs: Array = []
	for m in MS.pov_missions():
		povs.append(m.id)
	t.eq(",".join(povs), "M01,M02,M06,M09,M12", "已确定的 POV 关包含 M06 阿利宙斯突袭")

	t.eq(MS.by_id("M01").pov, "加乌曼·诺比尔", "M01 玩家是加乌曼（开梅萨，进攻方）")
	t.eq(MS.by_id("M02").pov, "喀耳刻部队的无名驾驶员",
		"M02 玩家是联邦的无名驾驶员（老板原话点名的\"古斯塔夫的无名驾驶员\"）")
	# ⚠️ 原 M04「打捞」的 POV（艾姆拉尔妲·祖宾）随关卡下架 —— 见 `mission_script.gd` 的墓碑。
	t.eq(MS.by_id("M03").pov, "", "M03 是哈萨维本人")
	t.not_ok(MS.by_id("M03").is_pov(), "M03 不是 POV 切换关")

	var hassan: Array = []
	var undecided: Array = []
	for m in MS.all():
		if m.is_pov():
			continue
		# ⚠️ **不能用 `pending.is_empty()` 当判据**：`pending` 是通用字段，
		# M03 的 pending 是"图（LEO）待轮 B2 新建"，与 POV 无关 ——
		# 用它筛会把 M03 一起筛掉，数出来 3 关而不是设计里的 4 关（本套件抓到过）。
		if m.pov_pending():
			undecided.append(m.id)
		else:
			hassan.append(m.id)
	t.eq(",".join(hassan), "M03,M04,M05,M07,M08,M10,M11", "哈萨维本人 4 关（DESIGN §4.4 的统计）")
	t.eq(",".join(undecided), "",
		"所有关卡的玩家视角均已确定")
	t.not_ok(MS.by_id("M03").pov_pending(), "M03 的 pending 与 POV 无关")
	t.not_ok(MS.by_id("M06").pov_pending(), "M06 阿利宙斯玩家视角已确定")
	t.eq(MS.by_id("M06").pov, "喀耳刻部队的阿利宙斯驾驶员", "M06 玩家为阿利宙斯驾驶员")
	t.ok(MS.by_id("M06").pending.is_empty(),
		"M06 已完成玩家机位和目标配置")

	# M01 / M02 是同一场战斗的两个座舱：玩家机与敌机**互换**。
	t.eq(MS.by_id("M01").player_suit, MS.by_id("M02").enemy_suit,
		"M01 的玩家机 == M02 的敌机（上一关你开的，这一关是你的敌人）")
	t.eq(MS.by_id("M02").player_suit, MS.by_id("M01").enemy_suit,
		"M02 的玩家机 == M01 的敌机")
	t.eq(MS.by_id("M01").player_suit, SuitProfile.Id.MESSER_M01, "M01 玩梅萨 M01")
	t.eq(MS.by_id("M01").enemy_suit, SuitProfile.Id.GUSTAV00, "M01 的敌人是古斯塔夫 00")
	# ★ 2026-10-01（轮 59）老板：「TRACER 作为 M01 的 bgm」。
	# 曲子名走 `SoundBank.BGM` 的键；**锁曲**那半边的判据在 `suite_mission_bgm`。
	t.eq(MS.by_id("M01").bgm, "tracer", "★ M01 的战斗曲是 TRACER")
	t.eq(MS.by_id("M02").player_suit, SuitProfile.Id.GUSTAV00, "M02 玩古斯塔夫 00")

	# ★★ 轮 50：M01「夜袭达沃」**一架敌机都没有** ——
	# 原来这里钉的是“两关波次形状逐字段相等”（同一场战斗的两个座舱）。现在：
	#   M01 = 纯突袭（0 波），M02 = 迎击（1 波 1 台）。
	# ⚠️ 那四条旧断言（波数相同 / 逐字段相等 / `objectives[1]` 镜像）
	# **不是“失效”，是把关对象变了** ⇒ 换成两组新的：
	#   ① M01 没有波次、M02 恰好一波；② 两关出击点关于图心**点对称**。
	var w1: Array = MS.by_id("M01").waves
	var w2: Array = MS.by_id("M02").waves
	t.eq(w1.size(), 0, "★ M01 一架敌机都没有（`waves` 为空 —— 老板要的「不应该设置敌人」）")
	t.eq(w2.size(), 1, "M02 仍然出一波")
	t.eq(w2[0].count, 1, "M02 这一波只有 1 台（「击溃一台梅萨」）")
	t.eq(w2[0].suit, MS.by_id("M02").enemy_suit, "M02 的第一波用的是它自己的敌机")

	# ★ 轮 50：两关的**出击点镜像**（关于图心点对称 ⇒ 角差整 180°）。
	# ⚠️ 判据写在**数据层**（两个角度）而不是“算出来的世界坐标”——
	# 坐标还要过 `match_spawn_radius()` 与城市地形抬高，读数会带上无关变量。
	t.near(MS.by_id("M02").spawn_angle_deg - MS.by_id("M01").spawn_angle_deg,
		180.0, 0.001, "★ M02 的出击点是 M01 的镜像（关于图心点对称 ⇒ 角差整 180°）")
	t.near(MS.by_id("M01").spawn_angle_deg, -95.0, 0.001,
		"M01 的出击角 == 工程原来硬编码的那个值（⇒ M01 的出生点逐位不变）")
	t.near(MS.by_id("M02").spawn_angle_deg, 85.0, 0.001, "M02 的出击角")


# ============================================================ 4 播片配额
static func _cutscenes(t: T) -> void:
	t.suite("剧情模式 / 播片槽位（每关都要有，DESIGN §4.2）")
	var seen: Dictionary = {}
	var missing_brief: Array = []
	var bad_id: Array = []
	for m in MS.all():
		var quota: Array = CUT_QUOTA.get(m.id, [])
		t.eq(m.slot("brief").size(), int(quota[0]), "%s 的任务前播片：%d 支" % [m.id, quota[0]])
		t.eq(m.slot("mid").size(), int(quota[1]), "%s 的任务中播片：%d 支" % [m.id, quota[1]])
		t.eq(m.slot("debrief").size(), int(quota[2]), "%s 的任务后播片：%d 支" % [m.id, quota[2]])
		t.eq(m.slot("prologue").size(), 0,
			"%s 的序章槽位是空的（序章播片是**另一条**路径，只管第一次进战役，§7.5.5）" % m.id)
		if m.slot("brief").is_empty() and m.chapter != 3:
			missing_brief.append(m.id)
		for k: String in ["brief", "mid", "debrief"]:
			for cid: String in m.slot(k):
				if seen.has(cid):
					bad_id.append("%s 重复" % cid)
				seen[cid] = true
				if not cid.begins_with(m.id.to_lower()):
					bad_id.append("%s 命名不像属于 %s" % [cid, m.id])
	t.eq(missing_brief.size(), 0, "每一关都有任务前播片（老板：\"每个任务都会有一些穿插播片\"）")
	t.eq(bad_id.size(), 0, "片目 id 全局唯一且带关卡前缀。有问题的：%s" % str(bad_id))
	t.gt(float(seen.size()), 0.0, "全战役至少有一支片（现在是 %d 支，**零素材也不影响**）" % seen.size())

	# 每关的中途播片条数要克制（DESIGN §13 第 9 条：太多会把一场战斗切碎）。
	var too_many: Array = []
	for m in MS.all():
		if m.slot("mid").size() > 2:
			too_many.append(m.id)
	t.eq(too_many.size(), 0, "没有哪一关的中途播片超过 2 支。超的：%s" % str(too_many))


# ============================================================ 5 目标（纯函数）
static func _objectives(t: T) -> void:
	t.suite("剧情模式 / 目标判定（十一种，逐点验）")
	var K: Dictionary = MS.Objective.Kind

	# ---- DESTROY_ALL
	t.ok(MS.Objective.destroy_all_done(3, 3), "击毁 3/3 ⇒ 完成")
	t.not_ok(MS.Objective.destroy_all_done(2, 3), "击毁 2/3 ⇒ 没完成")
	t.not_ok(MS.Objective.destroy_all_done(0, 0), "0/0 不算完成（没目标 ≠ 已完成）")
	t.not_ok(MS.Objective.destroy_all_done(4, 0), "total=0 也不算完成")

	# ---- DESTROY_TARGET
	t.ok(MS.Objective.destroy_target_done(true), "指定目标已毁 ⇒ 完成")
	t.not_ok(MS.Objective.destroy_target_done(false), "指定目标还在 ⇒ 没完成")

	# ---- DESTROY_ZONE（比例判定）
	t.ok(MS.Objective.destroy_zone_done(3, 4, 0.75), "3/4 == 0.75 ⇒ 踩线即完成")
	t.not_ok(MS.Objective.destroy_zone_done(2, 4, 0.75), "2/4 < 0.75 ⇒ 没完成")
	t.not_ok(MS.Objective.destroy_zone_done(1, 0, 0.5), "区域里没有可破坏物 ⇒ 不算完成")
	t.ok(MS.Objective.destroy_zone_done(4, 4, 0.75), "全毁 ⇒ 完成")

	# ---- SURVIVE（边界：89.9 / 90.0）
	t.not_ok(MS.Objective.survive_done(89.9, 90.0), "坚持 89.9 s（差一点）⇒ 没完成")
	t.ok(MS.Objective.survive_done(90.0, 90.0), "坚持 90.0 s（正好）⇒ 完成")
	t.ok(MS.Objective.survive_done(120.0, 90.0), "撑过头 ⇒ 完成")

	# ---- REACH（**碰到一次即达成**）
	t.ok(MS.Objective.reach_done(true), "进过那个区 ⇒ 完成")
	t.not_ok(MS.Objective.reach_done(false), "没进过 ⇒ 没完成")

	# ---- PROTECT
	t.ok(MS.Objective.protect_done(1, 1), "受保护目标 1/1 存活 ⇒ 完成")
	t.not_ok(MS.Objective.protect_done(0, 1), "受保护目标没了 ⇒ 没完成")
	t.ok(MS.Objective.protect_done(2, 1), "多活一个也算完成")

	# ---- INTERCEPT
	t.ok(MS.Objective.intercept_done(6, 6), "拦下 6/6 ⇒ 完成")
	t.not_ok(MS.Objective.intercept_done(5, 6), "拦下 5/6 ⇒ 没完成")

	# ---- SALVAGE
	t.ok(MS.Objective.salvage_done(3, 3), "捞够 3 件 ⇒ 完成")
	t.not_ok(MS.Objective.salvage_done(2, 3), "只捞 2 件 ⇒ 没完成")

	# ---- LIMIT（**双向**：越界即失败 / 压到线内即达成）
	t.ok(MS.Objective.limit_violated(true, 0.5, 0.0), "击坠了 ⇒ 违规（不管血还剩多少）")
	t.not_ok(MS.Objective.limit_violated(false, 0.5, 0.0), "活着 ⇒ 没违规")
	t.not_ok(MS.Objective.limit_violated(false, 0.30, 0.30), "血量正好在下限上 ⇒ 没违规（`<` 不是 `<=`）")
	t.ok(MS.Objective.limit_violated(false, 0.29, 0.30), "跌破下限 ⇒ 违规")
	t.ok(MS.Objective.limit_violated(false, 0.04, 0.05), "M05 的\"打到快炸\"也算违规（要生俘）")

	t.ok(MS.Objective.limit_done(false, 0.30, 0.30), "\"压到 ≤0.30\"且血正好 0.30 ⇒ 达成")
	t.not_ok(MS.Objective.limit_done(false, 0.31, 0.30), "血 0.31 还没压到位 ⇒ 没达成")
	t.not_ok(MS.Objective.limit_done(true, 0.0, 0.30), "打死了 ⇒ 不算达成（这是失败，不是完成）")
	t.ok(MS.Objective.limit_done(false, 0.9, 0.0), "min_hp<=0 ⇒ 只要求\"没被打死\"")
	t.not_ok(MS.Objective.limit_done(true, 0.0, 0.0), "min_hp<=0 但打死了 ⇒ 仍不算达成")

	# ---- STRIKE（★ 轮 50 新增：对**地标**开一枪即完成任务）
	t.not_ok(MS.Objective.strike_done(0, 1), "一枪都没打中 ⇒ 没完成")
	t.ok(MS.Objective.strike_done(1, 1), "打中 1 枪（正好）⇒ 完成")
	t.ok(MS.Objective.strike_done(3, 1), "打中好几枪也算完成")
	t.not_ok(MS.Objective.strike_done(5, 0), "need<=0 ⇒ 永远不算完成（没目标 ≠ 已完成）")

	# ---- 分派：`done()` 按 kind 走，缺键按"还没发生"算
	t.ok(MS.Objective.done(MS.Objective.destroy_all(3, "x"), {"killed": 3, "total": 3}),
		"done(DESTROY_ALL) 分派正确")
	t.not_ok(MS.Objective.done(MS.Objective.destroy_all(3, "x"), {}),
		"缺键的字典：DESTROY_ALL 判\"还没完成\"（而不是崩 / 也不是无端成立）")
	t.ok(MS.Objective.done(MS.Objective.reach("z", "x"), {"in_zone": true}),
		"done(REACH) 分派正确（**兼容路径**：只喂聚合键 `in_zone` 的老调用点）")
	# ★ 轮 55：运行时喂的是 `zones`（zone id → 到过没有），**按目标自己的 id 精确查**。
	# ⚠️ 为什么必须精确：一关有**两个** `REACH`目标时，单布尔会把「到过 A」当成「到过 B」
	# —— 目标提前成立，**一处都不报错**。下面三条把这个区别钉死。
	t.ok(MS.Objective.done(MS.Objective.reach("orbit_cargo", "x"), {"zones": {"orbit_cargo": true}}),
		"★ 精确路径：`zones` 里**正是**目标指的那个 id ⇒ 完成")
	t.not_ok(MS.Objective.done(MS.Objective.reach("orbit_cargo", "x"), {"zones": {"reentry_line": true}}),
		"★★ 到过的是**别的** zone ⇒ 不完成（聚合成一个布尔时这里会假绿）")
	t.not_ok(MS.Objective.done(MS.Objective.reach("orbit_cargo", "x"), {"zones": {}}),
		"★ `zones` 在但没这个 id ⇒ 不完成（不是「字典非空就算」）")
	t.ok(MS.Objective.done(MS.Objective.salvage("z", 2, "x"), {"salvaged": 2}),
		"done(SALVAGE) 分派正确")
	t.ok(MS.Objective.done(MS.Objective.survive(60.0, "x"), {"elapsed": 60.0}),
		"done(SURVIVE) 分派正确")
	t.ok(MS.Objective.done(MS.Objective.protect("z", 1, "x"), {"protected_alive": 1}),
		"done(PROTECT) 分派正确")
	t.ok(MS.Objective.done(MS.Objective.intercept(4, "x"), {"intercepted": 4}),
		"done(INTERCEPT) 分派正确")
	t.ok(MS.Objective.done(MS.Objective.destroy_zone("z", 0.5, "x"), {"zone_destroyed": 1, "zone_total": 2}),
		"done(DESTROY_ZONE) 分派正确")
	t.ok(MS.Objective.done(MS.Objective.destroy_target("u", "x"), {"destroyed": true}),
		"done(DESTROY_TARGET) 分派正确")
	t.ok(MS.Objective.done(MS.Objective.limit("u", 0.3, 0.0, "x"), {"target_hp_ratio": 0.25}),
		"done(LIMIT) 分派正确")
	t.not_ok(MS.Objective.done(MS.Objective.limit("u", 0.3, 0.0, "x"), {}),
		"缺键的字典：LIMIT 的血量缺省是按**满血**算（缺省 0 会无端成立）")
	t.ok(MS.Objective.done(MS.Objective.strike("g", "x"), {"landmark_hits": 1}),
		"done(STRIKE) 分派正确")
	t.not_ok(MS.Objective.done(MS.Objective.strike("g", "x"), {}),
		"缺键的字典：STRIKE 判\"还没完成\"（缺省 0 ⇒ 恒假，不会无端成立）")
	t.not_ok(MS.Objective.done(MS.Objective.strike("g", "x"), {"landmark_hits": 0}),
		"打中 0 次 ⇒ 没完成")
	t.not_ok(MS.Objective.violated(MS.Objective.limit("u", 0.3, 0.0, "x"), {}),
		"缺键的字典：LIMIT 判\"没违规\"")
	t.not_ok(MS.Objective.violated(MS.Objective.destroy_all(3, "x"), {"destroyed": true}),
		"非 LIMIT 的目标永远不会\"违规\"（违规只对 LIMIT 有意义）")

	# ---- 十种 kind 都要有名字（HUD 上会画）
	var unnamed: Array = []
	for k in range(0, K.size()):
		if MS.Objective.kind_name(k).strip_edges().is_empty() or MS.Objective.kind_name(k) == "?":
			unnamed.append(str(k))
	t.eq(unnamed.size(), 0, "每一种目标都有中文名。缺的：%s" % str(unnamed))
	t.eq(K.size(), 12, "目标类型十二种（含战术事件）（DESIGN §5.2 + 轮 50 的 STRIKE）")
	t.eq(K.STRIKE, 10,
		"★ STRIKE 落在**枚举末尾**（`objective:<下标>` 是存档认的东西 —— 中间插入会让已有的整体后移一格且不报错）")

	# ---- 每关的目标本身要合法
	var no_req: Array = []
	var bad_pair: Array = []
	var bad_limit: Array = []
	var bad_count: Array = []
	for m in MS.all():
		if m.required_objectives().is_empty():
			no_req.append(m.id)
		for o in m.objectives:
			if o.label.strip_edges().is_empty():
				bad_pair.append("%s/%s(空 label)" % [m.id, MS.Objective.kind_name(o.kind)])
			if o.kind == K.LIMIT:
				if not (0.0 <= o.floor_hp and o.floor_hp <= o.min_hp and o.min_hp <= 1.0):
					bad_limit.append("%s(min=%.2f floor=%.2f)" % [m.id, o.min_hp, o.floor_hp])
			if o.kind == K.DESTROY_ALL:
				if o.count > m.total_enemies():
					bad_count.append("%s(要 %d 台，只有 %d 台)" % [m.id, o.count, m.total_enemies()])
				if o.required and o.count != m.total_enemies():
					bad_count.append("%s(主要目标 %d ≠ 敌机总数 %d)" % [m.id, o.count, m.total_enemies()])
	t.eq(no_req.size(), 0, "每关至少有一个主要目标。没有的：%s" % str(no_req))
	t.eq(bad_pair.size(), 0, "每个目标都有文案。缺的：%s" % str(bad_pair))
	t.eq(bad_limit.size(), 0, "LIMIT 的三条线满足 0 ≤ floor_hp ≤ min_hp ≤ 1。异常的：%s" % str(bad_limit))
	t.eq(bad_count.size(), 0, "DESTROY_ALL 的数量与敌机总数自洽（主要目标必须等于全灭）。异常的：%s" % str(bad_count))


# ============================================================ 6 触发器求值
static func _triggers_eval(t: T) -> void:
	t.suite("剧情模式 / 触发器求值（纯函数，逐点验）")
	# ---- 时间门：这是整条需求里最典型的边界
	t.not_ok(MS.Trigger.eval("elapsed>=90", {"elapsed": 89.9}), "elapsed=89.9 ⇒ elapsed>=90 不触发")
	t.ok(MS.Trigger.eval("elapsed>=90", {"elapsed": 90.0}), "elapsed=90.0 ⇒ 触发")
	t.ok(MS.Trigger.eval("elapsed>=90", {"elapsed": 90.1}), "elapsed=90.1 ⇒ 触发")
	t.not_ok(MS.Trigger.eval("elapsed>90", {"elapsed": 90.0}), "elapsed=90.0 ⇒ elapsed>90 不触发")
	t.ok(MS.Trigger.eval("elapsed>90", {"elapsed": 90.001}), "elapsed=90.001 ⇒ elapsed>90 触发")
	t.ok(MS.Trigger.eval("elapsed<=90", {"elapsed": 90.0}), "elapsed<=90 在 90.0 成立")
	t.not_ok(MS.Trigger.eval("elapsed<=90", {"elapsed": 90.1}), "elapsed<=90 在 90.1 不成立")
	t.ok(MS.Trigger.eval("elapsed<90", {"elapsed": 89.999}), "elapsed<90 成立")
	t.ok(MS.Trigger.eval("elapsed==90", {"elapsed": 90.0}), "elapsed==90 成立")
	t.not_ok(MS.Trigger.eval("elapsed==90", {"elapsed": 90.5}), "elapsed==90 在 90.5 不成立")

	# ---- 运算符优先级：`>=` 必须整体识别（先把 `>` 认出来会切成键 `elapsed>`、值 `=90`）
	t.ok(MS.Trigger.eval("elapsed>=90", {"elapsed": 90.0}),
		"`>=` 被当成一个运算符（不是 `>` + 值 `=90`）—— 切错了这条会静默返回 false")
	t.ok(MS.Trigger.eval("kills>=2", {"kills": 2}), "`kills>=2` 同样正确")
	t.not_ok(MS.Trigger.eval("kills>=2", {"kills": 1}), "kills=1 ⇒ 不触发")

	# ---- 血量：缺省按**满血**算（缺省 0 会让"没喂血量的字典"看起来像"被打光了"）
	t.not_ok(MS.Trigger.eval("hp<0.5", {}), "没喂血量 ⇒ 按满血算 ⇒ hp<0.5 不成立")
	t.ok(MS.Trigger.eval("hp<0.5", {"hp_ratio": 0.4}), "血 0.4 ⇒ 触发")
	t.not_ok(MS.Trigger.eval("hp<0.5", {"hp_ratio": 0.5}), "血正好 0.5 ⇒ 不触发（严格小于）")
	t.ok(MS.Trigger.eval("hp_ratio<0.5", {"hp_ratio": 0.4}), "`hp_ratio` 与 `hp` 是同一个键的两个名字")
	t.ok(MS.Trigger.eval("target_hp_ratio<0.3", {"target_hp_ratio": 0.29}), "目标血量键可用")
	t.not_ok(MS.Trigger.eval("target_hp_ratio<0.3", {}), "没喂目标血量 ⇒ 按满血算")

	# ---- 区域破坏用的是**比例**，不是"打掉几个"（换图之后计数会变）
	t.ok(MS.Trigger.eval("zone_ratio>=0.6", {"zone_ratio": 0.6}), "区域毁伤到 0.6 ⇒ 触发")
	t.not_ok(MS.Trigger.eval("zone_ratio>=0.6", {"zone_ratio": 0.59}), "0.59 ⇒ 不触发")
	t.not_ok(MS.Trigger.eval("zone_ratio>=0.6", {}), "没喂比例 ⇒ 0.0 ⇒ 不触发")

	# ---- 计数类
	t.ok(MS.Trigger.eval("salvaged>=3", {"salvaged": 3}), "打捞计数")
	t.ok(MS.Trigger.eval("intercepted>=6", {"intercepted": 6}), "拦截计数")
	t.ok(MS.Trigger.eval("protected_alive<1", {"protected_alive": 0}), "受保护单位数（<1 = 没了）")

	# ---- waves_cleared：清波数是**计数**，`wave_cleared:0` = 第 0 波已清完
	t.not_ok(MS.Trigger.eval("wave_cleared:0", {"waves_cleared": 0}), "一波都没清完 ⇒ 不触发")
	t.ok(MS.Trigger.eval("wave_cleared:0", {"waves_cleared": 1}), "第 0 波清完 ⇒ 触发")
	t.ok(MS.Trigger.eval("wave_cleared:0", {"waves_cleared": 2}), "清得更多也仍然成立")
	t.ok(MS.Trigger.eval("wave_cleared:1", {"waves_cleared": 2}), "`wave_cleared:1` = 已清 > 1")
	t.not_ok(MS.Trigger.eval("wave_cleared:1", {"waves_cleared": 1}), "只清完第 0 波 ⇒ wave_cleared:1 不成立")

	# ---- enter:（玩家进过某个 Zone）
	t.ok(MS.Trigger.eval("enter:meeting_hall", {"zones": {"meeting_hall": true}}), "进过 ⇒ 触发")
	t.not_ok(MS.Trigger.eval("enter:meeting_hall", {"zones": {"meeting_hall": false}}), "没进过 ⇒ 不触发")
	t.not_ok(MS.Trigger.eval("enter:meeting_hall", {}), "没有 zones 字典 ⇒ 不触发")
	t.not_ok(MS.Trigger.eval("enter:other", {"zones": {"meeting_hall": true}}), "别的区不影响")

	# ---- all_done
	t.ok(MS.Trigger.eval("all_done", {"all_done": true}), "全部目标达成 ⇒ 触发")
	t.not_ok(MS.Trigger.eval("all_done", {}), "没喂 ⇒ 不触发")

	# ---- 组合与短路
	t.ok(MS.Trigger.eval("all_of:kills>=2,elapsed>=10", {"kills": 2, "elapsed": 10}), "all_of 全真 ⇒ 真")
	t.not_ok(MS.Trigger.eval("all_of:kills>=2,elapsed>=10", {"kills": 2, "elapsed": 9}), "all_of 一假 ⇒ 假")
	# ★ 短路证据：把第二个条件写成**看不懂的写法**。若它被求值就会返回 false，
	# 而"第一个条件已经假"时应当直接返回 —— 于是两条断言一起证明了短路真的发生。
	t.not_ok(MS.Trigger.eval("all_of:elapsed>=1,garbage", {"elapsed": 0}), "all_of 首项假 ⇒ 整条假")
	t.not_ok(MS.Trigger.eval("all_of:elapsed>=1,garbage", {"elapsed": 5}),
		"首项真 ⇒ 才会去算第二项（看不懂 ⇒ 假）—— 这一对断言证明 all_of 是短路的")
	t.ok(MS.Trigger.eval("any_of:kills>=5,elapsed>=10", {"kills": 0, "elapsed": 10}), "any_of 一真 ⇒ 真")
	t.not_ok(MS.Trigger.eval("any_of:kills>=5,elapsed>=10", {"kills": 0, "elapsed": 9}), "any_of 全假 ⇒ 假")
	t.ok(MS.Trigger.eval("any_of:elapsed>=1,garbage", {"elapsed": 5}), "any_of 首项真 ⇒ 不回看第二项")
	t.not_ok(MS.Trigger.eval("any_of:elapsed>=1,garbage", {"elapsed": 0}), "any_of 首项假 ⇒ 回看第二项 ⇒ 假")
	t.ok(MS.Trigger.eval("all_of:(any_of:kills>=1,elapsed>=1),hp<0.5",
		{"kills": 5, "elapsed": 0, "hp_ratio": 0.4}), "嵌套组合可用（**嵌套要带括号**）")
	# ★ 不带括号的嵌套：逗号有二义（分不清嵌套内部的逗号与外层的逗号）。
	# 宁可判假、并在 `check_condition()` 里当场点名，**也不算一半**。
	t.not_ok(MS.Trigger.eval("all_of:any_of:kills>=1,elapsed>=1", {"kills": 5, "elapsed": 1}),
		"★ 不带括号的嵌套**判假**（否则会只算前一半、后一半悄悄提到外层）")
	t.not_ok(MS.Trigger.check_condition("all_of:any_of:kills>=1,elapsed>=1").is_empty(),
		"★ 不带括号的嵌套被 `check_condition()` 当场点名")
	t.eq(MS.Trigger.check_condition("all_of:(any_of:kills>=1,elapsed>=1),hp<0.5"), "",
		"带括号的嵌套写法合法")
	t.not_ok(MS.Trigger.eval("all_of:(kills>=1", {"kills": 5}), "括号不配对 ⇒ 假")
	t.not_ok(MS.Trigger.check_condition("all_of:(kills>=1").is_empty(), "括号不配对被点名")
	t.not_ok(MS.Trigger.eval("all_of:", {"elapsed": 1}), "空的 all_of ⇒ 假（不当成'无条件成立'）")
	t.not_ok(MS.Trigger.eval("any_of:", {}), "空的 any_of ⇒ 假")
	# ★ 组合里的每一项都要过**白名单**（嵌套那一项递归下去也一样）。
	t.not_ok(MS.Trigger.eval("all_of:kills>=1,bogus>=1", {"kills": 5, "bogus": 5}),
		"★ 组合里的白名单检查同样生效（`bogus` 不在 KEYS 里 ⇒ 整条假）")
	t.not_ok(MS.Trigger.eval("all_of:(bogus>=1)", {"bogus": 5}),
		"★ 括号组里的白名单检查也生效")

	# ---- 坏写法：**一律返回 false，绝不崩**（纯函数不许崩）
	t.not_ok(MS.Trigger.eval("", {}), "空条件 ⇒ 假")
	t.not_ok(MS.Trigger.eval("   ", {}), "只有空格 ⇒ 假")
	t.not_ok(MS.Trigger.eval("elapsed", {}), "没有运算符 ⇒ 假（而不是把 elapsed 当布尔）")
	t.not_ok(MS.Trigger.eval("elapsed>=", {"elapsed": 9}), "右边是空的 ⇒ 假")
	t.not_ok(MS.Trigger.eval("elapsed>=abc", {"elapsed": 9}), "右边不是数 ⇒ 假")
	t.not_ok(MS.Trigger.eval("bogus>=1", {"bogus": 9}), "不认识的键 ⇒ 假")
	t.not_ok(MS.Trigger.eval("enter:", {"zones": {"": true}}), "enter 没给区名 ⇒ 假")
	t.not_ok(MS.Trigger.eval("wave_cleared:x", {"waves_cleared": 9}), "清波数不是整数 ⇒ 假")
	t.ok(MS.Trigger.eval("elapsed>-5", {"elapsed": 0.0}), "右值是负数也能解析")

	# ---- 动作解析
	t.eq(MS.Trigger.action_kind("spawn_wave:2"), "spawn_wave", "动作类型解析")
	t.eq(MS.Trigger.action_arg("spawn_wave:2"), "2", "动作参数解析")
	t.eq(MS.Trigger.action_kind("end:win"), "end", "无冒号参数的动作")
	t.eq(MS.Trigger.action_arg("end:win"), "win", "`end:` 的参数")
	t.eq(MS.Trigger.action_arg("end"), "", "没有冒号 ⇒ 参数是空串（validate 会点名）")
	t.eq(MS.Trigger.action_kind("radio:ken_01"), "radio", "电台动作用 `_` 拼 id")
	t.eq(MS.Trigger.action_arg(" cutscene:m04_mid_01 "), "m04_mid_01", "两端空格会被 strip")


# ============================================================ 7 触发器数据自检
static func _triggers_data(t: T) -> void:
	t.suite("剧情模式 / 触发器数据自检（坏数据要当场点名）")
	var bad: Array = []
	for m in MS.all():
		for tr in m.triggers:
			var why := MS.Trigger.validate(tr)
			if not why.is_empty():
				bad.append("%s/%s: %s" % [m.id, tr.id, why])
	t.eq(bad.size(), 0, "7 关里每一条触发器都是合法的。有问题的：%s" % str(bad))

	# 坏数据必须被抓住 —— 一条一条造出来验。
	t.ok(MS.Trigger.validate(MS.Trigger.new("", "end:win")).contains("when"),
		"空 when 被点名")
	t.ok(MS.Trigger.validate(MS.Trigger.new("elapsed>=1", "")).contains("do_what"),
		"空 do_what 被点名")
	t.ok(MS.Trigger.validate(MS.Trigger.new("bogus>=1", "end:win")).contains("when"),
		"不认识的键被点名")
	t.ok(MS.Trigger.validate(MS.Trigger.new("elapsed>=abc", "end:win")).contains("when"),
		"右边不是数被点名")
	t.ok(MS.Trigger.validate(MS.Trigger.new("elapsed>=1", "teleport:1")).contains("白名单"),
		"不在白名单的动作被点名（否则它会**静默地什么都不做**）")
	t.ok(MS.Trigger.validate(MS.Trigger.new("elapsed>=1", "end:draw")).contains("win"),
		"`end:` 的参数只能是 win / lose")
	t.ok(MS.Trigger.validate(MS.Trigger.new("elapsed>=1", "objective:x")).contains("整数"),
		"objective 的参数必须是整数")
	t.ok(MS.Trigger.validate(MS.Trigger.new("elapsed>=1", "radio:")).contains("参数"),
		"动作少了参数被点名")
	t.eq(MS.Trigger.validate(MS.Trigger.new("elapsed>=1", "end:win")), "",
		"合法的触发器返回空串")
	t.eq(MS.Trigger.validate(MS.Trigger.new("enter:x", "radio:y")), "", "enter 形式合法")
	# ⚠️ 组合里的项要用**白名单里的键**（`kills` / `elapsed`），
	# 不能用 `a` / `b` 这种假键 —— `eval` 与 `check_condition` 都按 `KEYS` 判，假键会被点名。
	t.eq(MS.Trigger.validate(MS.Trigger.new("all_of:kills>=1,elapsed>=1", "end:win")), "",
		"组合形式合法")
	t.eq(MS.Trigger.validate(MS.Trigger.new("wave_cleared:0", "radio:y")), "", "清波形式合法")
	t.ok(not MS.Trigger.check_condition("all_of:garbage").is_empty(), "组合里的坏项也会被查出来")

	# 波形自检：`spawn_wave:N` 必须在波数范围内；`waves_auto` 两个方向都要对。
	var bad_wave: Array = []
	var manual_no_spawn: Array = []
	var auto_with_spawn: Array = []
	for m in MS.all():
		for tr in m.triggers:
			if MS.Trigger.action_kind(tr.do_what) == "spawn_wave":
				var n := MS.Trigger.action_arg(tr.do_what).to_int()
				if n < 0 or n >= m.wave_count():
					bad_wave.append("%s(spawn_wave:%d，共 %d 波)" % [m.id, n, m.wave_count()])
				if m.waves_auto:
					auto_with_spawn.append(m.id)
		if not m.waves_auto and not _has_spawn_wave(m):
			manual_no_spawn.append(m.id)
	t.eq(bad_wave.size(), 0, "`spawn_wave:N` 的 N 都在波数范围内。越界的：%s" % str(bad_wave))
	t.eq(manual_no_spawn.size(), 0,
		"关掉自动推进的关**必须**自带 spawn_wave（否则第二波永远不出现，且不报错）。缺的：%s"
			% str(manual_no_spawn))
	t.eq(auto_with_spawn.size(), 0,
		"开着自动推进的关**不该**再手写 spawn_wave（会和自动推进抢同一个波次）。多的：%s"
			% str(auto_with_spawn))
	t.not_ok(MS.by_id("M05").waves_auto, "M05 的增援是事件驱动的（打到一半才压上来）")
	t.gt(float(MS.by_id("M05").wave_count()), 1.0, "M05 有两波（第一波 + 事件触发的增援）")
	t.ok(MS.by_id("M01").waves_auto, "M01 走的是原来的自动推进（一波清完再出下一波）")

	# 每关都要有出口（否则这一局永远打不完）。
	var no_exit: Array = []
	for m in MS.all():
		var has_win := false
		var has_lose := false
		for tr in m.triggers:
			if tr.do_what == "end:win":
				has_win = true
			elif tr.do_what == "end:lose":
				has_lose = true
		if not has_win or not has_lose:
			no_exit.append(m.id)
	t.eq(no_exit.size(), 0, "每关都有 end:win 与 end:lose。缺的：%s" % str(no_exit))

	# 触发器 id 全局唯一（日志里靠它定位"哪一条没触发"）。
	var seen: Dictionary = {}
	var dup: Array = []
	for m in MS.all():
		for tr in m.triggers:
			if tr.id.strip_edges().is_empty():
				dup.append("%s(空 id)" % m.id)
			elif seen.has(tr.id):
				dup.append("%s 重复" % tr.id)
			seen[tr.id] = true
	t.eq(dup.size(), 0, "触发器 id 全局唯一且非空。有问题的：%s" % str(dup))

	# 引用的东西必须真的存在（Zone / 片目 / 目标下标）。
	var dangling: Array = []
	for m in MS.all():
		for o in m.objectives:
			var k: int = o.kind
			if [MS.Objective.Kind.REACH, MS.Objective.Kind.DESTROY_ZONE,
					MS.Objective.Kind.SALVAGE, MS.Objective.Kind.PROTECT].has(k):
				if m.zone(o.target) == null:
					dangling.append("%s 目标指向不存在的区 %s" % [m.id, o.target])
		for tr in m.triggers:
			var w := MS.Trigger.when_arg(tr.when, "enter:")
			if not w.is_empty() and m.zone(w) == null:
				dangling.append("%s 触发器指向不存在的区 %s" % [m.id, w])
			if MS.Trigger.action_kind(tr.do_what) == "cutscene":
				var cid := MS.Trigger.action_arg(tr.do_what)
				if not _has_cutscene(m, cid):
					dangling.append("%s 播片 id 不在本关表里：%s" % [m.id, cid])
			if MS.Trigger.action_kind(tr.do_what) == "objective":
				var oi := MS.Trigger.action_arg(tr.do_what).to_int()
				if oi < 0 or oi >= m.objectives.size():
					dangling.append("%s objective:%d 越界（共 %d 个目标）"
						% [m.id, oi, m.objectives.size()])
	t.eq(dangling.size(), 0, "触发器/目标引用的 Zone、片目、目标下标都存在。悬空的：%s" % str(dangling))


static func _has_spawn_wave(m) -> bool:
	for tr in m.triggers:
		if MS.Trigger.action_kind(tr.do_what) == "spawn_wave":
			return true
	return false


static func _has_cutscene(m, cid: String) -> bool:
	for k: String in ["prologue", "brief", "mid", "debrief"]:
		if m.slot(k).has(cid):
			return true
	return false


# ============================================================ 8 区域几何
static func _zones(t: T) -> void:
	t.suite("剧情模式 / 区域几何（球 / 盒，纯几何）")
	var s = MS.Zone.sphere("z", "球", Vector3(0.0, 1000.0, 0.0), 500.0)
	t.ok(s.contains(Vector3(0.0, 1000.0, 0.0)), "球心在里面")
	t.ok(s.contains(Vector3(0.0, 1500.0, 0.0)), "正好在球面上 ⇒ 算在里面（≥ 0）")
	t.not_ok(s.contains(Vector3(0.0, 1500.1, 0.0)), "出球面一点点 ⇒ 不在")
	t.near(s.clearance(Vector3(0.0, 1000.0, 0.0)), 500.0, 0.001, "球心的余量 = 半径")
	t.near(s.clearance(Vector3(0.0, 1600.0, 0.0)), -100.0, 0.001, "球外的余量是负的（HUD 的距离读数直接用它）")
	t.near(s.outer_radius(), 500.0, 0.001, "球的外接半径 = 半径")
	t.eq(s.shape_name(), "球", "形状名")
	t.eq(s.use_name(), "目标区", "用途名")
	t.not_ok(s.is_height_band(), "球不是高度带")

	var b = MS.Zone.box("b", "盒", Vector3(0.0, 0.0, 0.0), Vector3(2000.0, 1000.0, 4000.0))
	t.ok(b.contains(Vector3(0.0, 0.0, 0.0)), "盒心在里面")
	t.ok(b.contains(Vector3(1000.0, 500.0, 2000.0)), "正好在角上 ⇒ 算在里面")
	t.not_ok(b.contains(Vector3(1000.1, 0.0, 0.0)), "越 x 面 ⇒ 不在")
	t.not_ok(b.contains(Vector3(0.0, 500.1, 0.0)), "越 y 面 ⇒ 不在")
	t.not_ok(b.contains(Vector3(0.0, 0.0, 2000.1)), "越 z 面 ⇒ 不在")
	t.near(b.clearance(Vector3(0.0, 0.0, 0.0)), 500.0, 0.001,
		"盒心的余量 = 最紧那条轴（y：1000/2）—— 不是欧氏距离")
	t.near(b.outer_radius(), 0.5 * Vector3(2000.0, 1000.0, 4000.0).length(), 0.001,
		"盒的外接半径 = 体对角线的一半")
	t.near(b.size.y, 1000.0, 0.001, "`size` 是**全边长**，读的时候不要再乘 2")
	t.eq(b.shape_name(), "盒", "形状名")
	t.not_ok(b.is_height_band(), "没标轴的盒不是高度带")

	var band = MS.Zone.box("band", "带", Vector3(0.0, 60000.0, 0.0),
		Vector3(120000.0, 2000.0, 120000.0), MS.Zone.Use.DANGER, true, MS.Zone.Axis.Y)
	t.ok(band.is_height_band(), "标了 Y 轴的盒是高度带（轨道图的\"再入线\"用它）")
	t.eq(band.use_name(), "危险区", "用途名（危险区）")
	t.eq(band.use, MS.Zone.Use.DANGER, "用途枚举")

	var tz = MS.Zone.sphere("tz", "触发", Vector3.ZERO, 100.0, MS.Zone.Use.TRIGGER, false)
	t.not_ok(tz.visible, "演出触发的区**不画**（DESIGN §5.4 的表）")
	t.eq(tz.use_name(), "演出触发", "用途名（演出触发）")
	t.ok(MS.Zone.sphere("e", "", Vector3.ZERO, 1.0, MS.Zone.Use.EXTRACT).use_name() == "撤离点",
		"用途名（撤离点）")
	t.ok(MS.Zone.sphere("sv", "", Vector3.ZERO, 1.0, MS.Zone.Use.SALVAGE).use_name() == "打捞区",
		"用途名（打捞区）")

	# 每关的 Zone id 唯一、都有区名（HUD 会画）。
	var dup: Array = []
	var unnamed: Array = []
	for m in MS.all():
		var seen: Dictionary = {}
		for z in m.zones:
			if seen.has(z.id):
				dup.append("%s/%s" % [m.id, z.id])
			seen[z.id] = true
			if z.label.strip_edges().is_empty():
				unnamed.append("%s/%s" % [m.id, z.id])
	t.eq(dup.size(), 0, "同一关里的 Zone id 唯一。重复的：%s" % str(dup))
	t.eq(unnamed.size(), 0, "每个 Zone 都有区名。缺的：%s" % str(unnamed))

	# ★★ 轮 50：M01 / M02 的 Zone **整批撤掉了** ——
	# 原来那两条（`zone("davao_port") != null` / “达沃港不是高度带”）钉的是
	# `destroy_zone` / `protect` 两条目标，而它们已被老板改成
	# “对酒店开一枪” / “击溃一台梅萨” ⇒ 留着 `davao_port` 就是一块
	# “写着目标区、却没有任何目标指向它”的假数据。
	# ⇒ 换成“**没有 Zone 是一个可断言的事实**”（而不是“拿不到”）。
	var m1 = MS.by_id("M01")
	var m2 = MS.by_id("M02")
	t.eq(m1.zones.size(), 0, "★ M01 没有 Zone（唯一的目标是对地标开枪，不需要区）")
	t.eq(m2.zones.size(), 0, "★ M02 没有 Zone（唯一的目标是击溃一台梅萨）")
	t.eq(m1.zone("davao_port"), null, "旧目标区 `davao_port` **已撤**（找得到才算回归）")
	t.eq(m1.zone("nope"), null, "找不到返回 null（不崩）")

	var m3 = MS.by_id("M03")
	t.ok(m3.zone("reentry_line") != null and m3.zone("reentry_line").is_height_band(),
		"M03 的『再入线』是高度带（DESIGN §4.8 / §13 第 14 条）")
	t.near(m3.zone("reentry_line").center.y, MS.REENTRY_ALT, 0.001, "再入线的高度就是那个常量")
	t.near(m3.zone("orbit_cargo").center.y, MS.ORBIT_ALT, 0.001, "运输仓接收点在轨道高度上")
	t.eq(m3.zone("orbit_cargo").shape, MS.Zone.Shape.SPHERE,
		"空中的接收点是**球**（DESIGN §5.2 的\"可以是空中的某个点位\"）")
	# ★ 轮 55：半径 4000 → **600 m**（老板：「靠近柯西收纳仓 0.6 km 内就可以视作任务成功」）。
	# ⚠️ 这一条钉的是**数字本身**；球心与 `WorldBuilder.SPACE_POD_POS` **逐位相同**（上面那一条），
	# 所以「0.6 km」读作「离运输仓 0.6 km」。判据**能变红**（把 600 改回 4000 就红）。
	t.near(m3.zone("orbit_cargo").outer_radius(), 600.0, 0.001,
		"★ M03 的接收球半径 = 600 m（老板口径：0.6 km 内算任务成功）")
	t.not_ok(m3.zone("orbit_cargo").is_height_band(),
		"★ 同一关里的\"接收点\"**不是**高度带（只有 `reentry_line` 是）—— 这一条接替了原来用 `davao_port` 写的那条反差")


# ============================================================ 9 打捞物
static func _collectibles(t: T) -> void:
	t.suite("剧情模式 / 打捞物（打坏的不算数）")
	var a = MS.Collectible.make("a", "A", "z", 1.0)
	var b = MS.Collectible.make("b", "B", "z", 1.0)
	var c = MS.Collectible.make("c", "C", "z", 1.0)
	c.collected = true
	t.eq(MS.Collectible.count_ok([a, b, c]), 1, "只有捞上来的才算数")
	t.eq(MS.Collectible.count_ok([]), 0, "空表 ⇒ 0")
	c.broken = true
	t.eq(MS.Collectible.count_ok([a, b, c]), 0, "★ 捞上来了但**打坏了** ⇒ 不算数（这是「打捞」机制本身的规矩）")
	t.eq(c.state_name(), "已损坏", "损坏态的名字")
	var d = MS.Collectible.make("d", "D", "z")
	t.eq(d.state_name(), "待打捞", "默认是待打捞")
	d.collected = true
	t.eq(d.state_name(), "已回收", "捞上来之后是已回收")
	t.ok(not a.counts(), "没捞上来的不算数")

	# 数据侧：SALVAGE 关必须有足够的打捞物。
	var bad: Array = []
	for m in MS.all():
		for o in m.objectives:
			if o.kind == MS.Objective.Kind.SALVAGE:
				if m.collectibles.size() < o.count:
					bad.append("%s(要 %d 件，场上只有 %d 件)" % [m.id, o.count, m.collectibles.size()])
				if m.zone(o.target) == null:
					bad.append("%s 打捞区不存在：%s" % [m.id, o.target])
	t.eq(bad.size(), 0, "打捞目标与场上的打捞物自洽（不然是**不可能完成**的关）。异常的：%s" % str(bad))
	# ⚠️ 轮 56：原 M04「打捞」整关下架 ⇒ 场上**一件打捞物都没有**。
	# 机制全部留着（`Collectible` / `Zone.Use.SALVAGE`），但没有消费者——
	# 上面那条 `bad` 自检从此**空转**（循环体一次都不进）⇒ 这里把"空转"本身钉住。
	var with_salvage: Array = []
	for m2: MS.Mission in MS.all():
		if m2.collectibles.size() > 0:
			with_salvage.append(m2.id)
	t.eq(with_salvage.size(), 0, "★ 轮 56 起没有任何关卡放打捞物（打捞机制空转）")
	# ★ 2026-09-30 · 轮 53：老板把 M04 的目标从「打伤不得击坠 + 救回加乌曼」
	#   改成「**击败佩涅罗佩**」⇒ 加乌曼被俘的设定作废，那件打捞物（当时唯一一件）**整条撤销**。
	t.eq(MS.by_id("M04").collectibles.size(), 0, "M04 不再有打捞物（救加乌曼已作废）")
	var mm05: MS.Mission = MS.by_id("M04")
	t.eq(mm05.objectives.size(), 1, "★ M04 只剩一条目标")
	t.eq((mm05.objectives[0] as MS.Objective).kind, MS.Objective.Kind.DESTROY_ALL,
		"★ 且它是 DESTROY_ALL（击坠即达成，不再是「不得击坠」的 LIMIT）")
	t.eq(MS.plain((mm05.objectives[0] as MS.Objective).label), "击败佩涅罗佩",
		"★ 老板截图指定的文案：击败佩涅罗佩")
	t.eq(mm05.zones.size(), 1, "M04 只剩贴海窗口那一个区")
	t.eq(mm05.zone("sea_window") != null, true, "而它就是 sea_window")
	var m05o: Array = MS.by_id("M05").objectives
	t.eq(MS.plain((m05o[0] as MS.Objective).label), "摧毁奥恩贝利火力点",
		"★ 老板截图指定的文案：摧毁奥恩贝利火力点")
	t.eq(MS.plain((m05o[1] as MS.Objective).label), "使金伯利无力化",
		"★ 且去掉了「（不得击毙）」括注（判定一个数都没动）")
	t.near((m05o[1] as MS.Objective).floor_hp, 0.05, 0.0001,
		"★ 「不得击毙」的判定仍在（floor_hp = 0.05）—— 老板选的是“只改文案”")


# ============================================================ 10 军资
static func _credits(t: T) -> void:
	t.suite("剧情模式 / 军资（只加不减 · 重打只补差额）")
	var g: Array = ["S", "A", "B", "C", "D"]
	var prev := 1 << 30
	for grade: String in g:
		var v: int = CS.GRADE_BONUS[grade]
		t.lt(float(v), float(prev), "评价加成递减：%s → %d" % [grade, v])
		prev = v
	t.eq(CS.GRADE_BONUS["S"], 400, "S 的评价加成（军资表的锚点）")
	t.eq(CS.GRADE_BONUS["D"], 40, "D 也有加成（打完了就该有钱）")
	t.eq(CS.GRADE_BONUS.has(MissionRating.NO_GRADE), false,
		"`NO_GRADE`（失败）**不在**加成表里 —— 失败不给评价钱")

	t.eq(CS.reward_for({"base": 100}), 100, "只给 base ⇒ 就是 base")
	t.eq(CS.reward_for({"base": 100, "grade": "S"}), 500, "base + S")
	t.eq(CS.reward_for({"base": 100, "grade": "D"}), 140, "base + D")
	t.eq(CS.reward_for({"base": 100, "grade": MissionRating.NO_GRADE}), 100,
		"失败（NO_GRADE）只拿 base，拿不到评价加成")
	t.eq(CS.reward_for({"base": 100, "grade": "Z"}), 100, "不认识的评价不崩、也不给钱")
	t.eq(CS.reward_for({"base": 100, "grade": "S", "kills": 3}), 590, "再 + 逐机击坠")
	t.eq(CS.reward_for({"base": 0, "grade": "S", "kills": 1, "named_kills": 1}),
		400 + 30 + 120, "命名王牌更值钱（+120/台）")
	t.eq(CS.reward_for({"base": 0, "grade": "S", "kills": 1, "named_kills": 5}),
		400 + 30 + 120, "named_kills 被夹到 ≤ kills（不许多报）")

	# ★ 硬约束 1「只加不减」：任何输入都算出非负整数。
	var neg: Array = [
		{"base": -500}, {"base": 100, "kills": -9}, {"base": -1, "grade": "S", "kills": -1},
		{"base": 0, "grade": "", "kills": 0, "named_kills": -3}, {},
	]
	var bad: Array = []
	for st: Dictionary in neg:
		if CS.reward_for(st) < 0:
			bad.append(str(st))
	t.eq(bad.size(), 0, "没有任何输入能算出负数军资。出负的：%s" % str(bad))
	t.eq(CS.reward_for({}), 0, "空输入 ⇒ 0")

	# 单调性：击坠更多 / 评价更好，钱都不变少。
	var mono := true
	for n in range(0, 8):
		if CS.reward_for({"base": 100, "grade": "A", "kills": n}) > \
				CS.reward_for({"base": 100, "grade": "A", "kills": n + 1}):
			mono = false
	t.ok(mono, "击坠数增加 ⇒ 军资不减（单调）")
	t.gt(float(CS.reward_for({"base": 100, "grade": "S"})),
		float(CS.reward_for({"base": 100, "grade": "C"})), "评价更好 ⇒ 军资更多")

	# ★ 硬约束 3「重打只补差额」
	t.eq(CS.reward_delta(87, 92), 5, "更好 ⇒ 只补差额")
	t.eq(CS.reward_delta(92, 87), 0, "更差 ⇒ 0（**不是负数**）")
	t.eq(CS.reward_delta(90, 90), 0, "一样 ⇒ 0")
	t.eq(CS.reward_delta(0, 500), 500, "从 0 开始 ⇒ 全额")
	t.eq(CS.reward_delta(-5, 10), 15, "基准是负的（异常档）也不会算出负数以外的怪值")
	t.eq(CS.credit_delta(false, 0, 500), 500, "★ **首通拿全额**")
	t.eq(CS.credit_delta(true, 500, 500), 0, "首通之后再拿一样的成绩 ⇒ 0")
	t.eq(CS.credit_delta(true, 500, 620), 120, "重打更好 ⇒ 只补差额")

	# 全战役理论上界：`campaign_shop` 的定价要拿它当分母（§13 第 10 条）。
	var manual := 0
	for m in MS.all():
		manual += CS.reward_for({"base": m.base_reward, "grade": "S",
			"kills": m.total_enemies(), "named_kills": 0})
	t.eq(CS.max_reward(), manual, "max_reward() == 逐关累加（不是另一个算法）")
	t.gt(float(CS.max_reward()), 0.0, "全战役上界是正数（现在是 %d 军资）" % CS.max_reward())


# ============================================================ 11 解锁
static func _unlock(t: T) -> void:
	t.suite("剧情模式 / 解锁与进展")
	var p := CS.new_progress()
	t.eq(CS.index_of("M01"), 0, "M01 是第 0 位")
	t.eq(CS.index_of("M07"), 6, "M07 是第 6 位")
	t.eq(CS.index_of("M00"), -1, "序章不在序列里 ⇒ −1")
	t.eq(CS.index_of("M99"), -1, "不存在的关 ⇒ −1")
	t.eq(CS.bit_of("M01"), 1, "第 0 关的位是 1")
	t.eq(CS.bit_of("M07"), 64, "第 6 关的位是 64")
	t.eq(CS.bit_of("M00"), 0, "序章不占位")

	t.ok(CS.is_unlocked(p, "M01"), "第一关永远开着")
	t.not_ok(CS.is_unlocked(p, "M02"), "★ 跳关被拒：没通 M01 时 M02 锁着")
	t.not_ok(CS.is_unlocked(p, "M07"), "最后一关当然也锁着")
	t.not_ok(CS.is_unlocked(p, "M00"), "序章不是可打的关")
	t.not_ok(CS.is_unlocked(p, "M99"), "不存在的关 ⇒ 锁着")

	var p1 := CS.new_progress()
	p1["cleared_mask"] = CS.bit_of("M01")
	t.ok(CS.is_unlocked(p1, "M02"), "通了 M01 ⇒ M02 开")
	t.not_ok(CS.is_unlocked(p1, "M03"), "★ 只通了 M01，M03 仍然锁着（顺序解锁的传递闭包，不需要额外的跳关检测）")
	t.eq(CS.next_id("M01"), "M02", "M01 的下一关")
	t.eq(CS.next_id("M07"), "M08", "第二章结束后进入第三章")
	t.eq(CS.next_id("M00"), "", "序章没有下一关")

	var p2 := CS.new_progress()
	var mask := 0
	for i: String in ["M01", "M02", "M03", "M04"]:
		mask |= CS.bit_of(i)
	p2["cleared_mask"] = mask
	t.eq(CS.cleared_count(p2), 4, "四关通关计数")
	t.ok(CS.is_unlocked(p2, "M05"), "★ 跨章边界可过：第一章全通 ⇒ M05 开（不需要额外条件）")
	t.not_ok(CS.is_unlocked(p2, "M06"), "但 M06 还锁着（要先通 M05）")
	t.eq(CS.current_id(p2), "M05", "当前该打的是 M05")
	t.eq(CS.current_id(CS.new_progress()), "M01", "新档从 M01 开始")

	var p3 := CS.new_progress()
	p3["cleared_mask"] = (1 << 12) - 1
	t.eq(CS.current_id(p3), "", "全通 ⇒ 没有'当前关'")
	t.eq(CS.cleared_count(p3), 12, "全通计数十二")

	t.eq(",".join(CS.ids_of_chapter(1)), "M01,M02,M03,M04", "第一章的 id 列表")
	t.eq(",".join(CS.ids_of_chapter(2)), "M05,M06,M07", "第二章的 id 列表")
	t.eq(CS.chapter_of("M04"), 1, "M04 属第一章")
	t.eq(CS.chapter_of("M05"), 2, "M05 属第二章")
	t.eq(CS.chapter_of("M00"), 0, "序章的章号是 0（不是任何一章）")

	# 存档里的位掩码超界要能被裁掉（老档 / 手改档）。
	var weird := CS.new_progress()
	weird["cleared_mask"] = 0xFFFF
	t.ok(CS.save_progress(weird, TMP) == OK, "写档成功（临时路径）")
	var back := CS.load_progress(TMP)
	t.eq(int(back["cleared_mask"]), 4095, "位掩码被裁到12位（不然会数出'通关 16 关'）")
	CS.erase(TMP)


# ============================================================ 12 结算
static func _settle(t: T) -> void:
	t.suite("剧情模式 / 结算（落进进度）")
	var p := CS.new_progress()
	var res := {"win": true, "grade": "A", "score": 88.0, "kills": 3, "named_kills": 0, "base": 260}
	var out := CS.settle(p, "M01", res)
	var reward := CS.reward_for(res)
	t.eq(int(out["reward"]), reward, "结算出的 reward 就是军资公式的结果")
	t.eq(int(out["delta"]), reward, "★ 首通 ⇒ 全额到账")
	var p_after: Dictionary = out["progress"]
	t.eq(int(p_after["credits"]), reward, "军资进钱包")
	t.eq(CS.is_cleared(p_after, "M01"), true, "M01 被点亮")
	t.eq(str(p_after["best_grade"]["M01"]), "A", "最好评价记下来了")
	t.near(float(p_after["best_score"]["M01"]), 88.0, 0.001, "最高分记下来了")
	t.eq(int(p_after["best_reward"]["M01"]), reward, "军资基准记下来了")
	t.eq(int(p_after["chapter"]), 1, "当前章被推到 1")
	t.eq(int(p["cleared_mask"]), 0, "★ 传进去的那一份**没被改**（settle 是纯函数）")
	t.eq(int(p["credits"]), 0, "钱包也没被改")

	# 重打更好：只补差额。
	var better := {"win": true, "grade": "S", "score": 95.0, "kills": 3, "base": 260}
	var out2 := CS.settle(p_after, "M01", better)
	t.eq(int(out2["delta"]), CS.reward_for(better) - reward, "★ 重打更好 ⇒ 只补差额")
	t.eq(int(out2["progress"]["credits"]), CS.reward_for(better), "钱包 = 原来 + 差额")
	t.eq(str(out2["progress"]["best_grade"]["M01"]), "S", "最好评价被刷新")
	t.near(float(out2["progress"]["best_score"]["M01"]), 95.0, 0.001, "最高分被刷新")
	t.eq(int(out2["progress"]["best_reward"]["M01"]), CS.reward_for(better), "军资基准被刷新")

	# 重打更差：给 0，且最好成绩不被拉低。
	var worse := {"win": true, "grade": "D", "score": 40.0, "kills": 1, "base": 260}
	var out3 := CS.settle(out2["progress"], "M01", worse)
	t.eq(int(out3["delta"]), 0, "★ 重打更差 ⇒ 给 0")
	t.eq(int(out3["progress"]["credits"]), int(out2["progress"]["credits"]), "钱包不动")
	t.eq(str(out3["progress"]["best_grade"]["M01"]), "S", "最好评价不倒退")
	t.near(float(out3["progress"]["best_score"]["M01"]), 95.0, 0.001, "最高分不倒退")

	# 幂等：同一份成绩结算两次，第二次给 0（刷简单关拿不到钱）。
	var out4 := CS.settle(out3["progress"], "M01", better)
	t.eq(int(out4["delta"]), 0, "★ 同一成绩再结算一次 ⇒ 0（防刷关）")

	# 失败：不进钱、不点亮、不留成绩。
	var p_fresh := CS.new_progress()
	var lose := {"win": false, "grade": MissionRating.NO_GRADE, "score": 61.0,
		"kills": 2, "base": 260}
	var out5 := CS.settle(p_fresh, "M01", lose)
	t.gt(float(out5["reward"]), 0.0,
		"打输了也有战果读数（reward 仍是 base + 击坠）—— 结算页要显示它")
	t.eq(int(out5["delta"]), 0, "但**不进钱包**")
	t.eq(int(out5["progress"]["credits"]), 0, "钱包还是 0")
	t.not_ok(CS.is_cleared(out5["progress"], "M01"), "失败不点亮这一关")
	t.eq(out5["progress"]["best_grade"].has("M01"), false, "★ 失败**不留成绩**（否则'最好成绩'会变成'打输过'）")
	t.eq(int(out5["progress"]["cleared_mask"]), 0, "位掩码不动")

	# 图鉴：去重。
	var p6 := CS.new_progress()
	var r6 := {"win": true, "grade": "B", "score": 70.0, "kills": 2, "base": 100,
		"aces_down": ["lane", "lane", "kimberly"], "aces_seen": ["lane"]}
	var out6 := CS.settle(p6, "M01", r6)
	t.eq(",".join(out6["progress"]["aces_down"]), "lane,kimberly", "已击坠的命名王牌去重")
	t.eq(",".join(out6["progress"]["aces_seen"]), "lane", "见过的图鉴条目单独记（见 ≠ 击坠）")

	# 全流程：七关全通 ⇒ 解锁到底、军资单调增。
	var pr := CS.new_progress()
	var prev_credits := 0
	var monotone := true
	for m in MS.all():
		var st := {"win": true, "grade": "S", "score": 96.0, "kills": m.total_enemies(),
			"base": m.base_reward}
		var r := CS.settle(pr, m.id, st)
		pr = r["progress"]
		if int(pr["credits"]) < prev_credits:
			monotone = false
		prev_credits = int(pr["credits"])
	t.ok(monotone, "★ 七关走完，军资**一路不降**（只增不减）")
	t.eq(CS.cleared_count(pr), 12, "十二关全通")
	t.eq(CS.current_id(pr), "", "全通之后没有'当前关'")
	t.eq(int(pr["credits"]), CS.max_reward(), "全 S 全击坠 ⇒ 打满理论上界")


# ============================================================ 13 存档
static func _save(t: T) -> void:
	t.suite("剧情模式 / 存档（往返 · 还原 · 不碰真实档）")
	# ⚠️ 先量一下**真实存档**的状态：这一套跑完它必须逐字节不变。
	# 本工程栽过一次"测试把玩家的设置写花了"（`Settings` 那边照着错值还原并写进文件）。
	var real := CS.PATH
	var real_had := FileAccess.file_exists(real)
	var real_md5 := FileAccess.get_md5(real) if real_had else ""
	t.eq(real, "user://campaign.cfg", "真实存档路径没被改过（还是 user://campaign.cfg）")
	t.eq(CS.save_progress(CS.new_progress(), TMP), OK, "临时档可写")
	t.ok(FileAccess.file_exists(TMP), "临时档真的落在盘上")

	# ---- 往返：逐项比（不用字典 ==，免得踩到比较语义的坑）
	var p := CS.new_progress()
	p["cleared_mask"] = CS.bit_of("M01") | CS.bit_of("M02") | CS.bit_of("M03")
	p["credits"] = 1234
	p["chapter"] = 2
	p["best_grade"] = {"M01": "S", "M02": "B", "M03": "C"}
	p["best_score"] = {"M01": 92.4, "M02": 71.0}
	p["best_reward"] = {"M01": 700, "M02": 420}
	p["aces_down"] = ["lane", "kimberly"]
	p["aces_seen"] = ["lane", "ken"]
	p["upgrades"] = {"suit_0": {"up": ["multi_lock"], "down": ["thrust_6", "thrust_6"]}}
	t.eq(CS.save_progress(p, TMP), OK, "写档成功")
	var q := CS.load_progress(TMP)
	t.eq(int(q["cleared_mask"]), int(p["cleared_mask"]), "位掩码往返一致")
	t.eq(int(q["credits"]), 1234, "军资往返一致")
	t.eq(int(q["chapter"]), 2, "当前章往返一致")
	t.eq(str(q["best_grade"]["M01"]), "S", "最好评价往返一致")
	t.eq(str(q["best_grade"]["M03"]), "C", "第三章的最好评价也在")
	t.eq(q["best_grade"].has("M04"), false, "没打过的关不写成绩")
	t.near(float(q["best_score"]["M01"]), 92.4, 0.0001, "最高分往返一致（保留 4 位）")
	t.eq(int(q["best_reward"]["M01"]), 700, "军资基准往返一致")
	t.eq(",".join(q["aces_down"]), "lane,kimberly", "已击坠列表往返一致（顺序也保留）")
	t.eq(",".join(q["aces_seen"]), "lane,ken", "见过列表往返一致")
	var lo: Dictionary = q["upgrades"].get("suit_0", {})
	t.eq(",".join(CS._str_list(lo.get("up", []))), "multi_lock", "改装：上级槽往返一致")
	t.eq(",".join(CS._str_list(lo.get("down", []))), "thrust_6,thrust_6",
		"改装：下级槽往返一致（同一词条两份是**允许**的）")

	# ---- 空档往返
	t.eq(CS.save_progress(CS.new_progress(), TMP), OK, "写空档")
	var e := CS.load_progress(TMP)
	t.eq(int(e["cleared_mask"]), 0, "空档：没有进度")
	t.eq(int(e["credits"]), 0, "空档：没有军资")
	t.eq(e["upgrades"].size(), 0, "空档：没有任何改装")

	# ---- 读一个不存在的档 ⇒ 空档，不崩
	var ghost := CS.load_progress("user://campaign_definitely_absent.cfg")
	t.eq(int(ghost["cleared_mask"]), 0, "档不存在 ⇒ 退化成空档（第一次运行走的就是这一支）")
	t.eq(int(ghost["credits"]), 0, "空档没有军资")

	# ---- 损坏档：写一堆越界值进去，读回来必须已经被裁好
	var broken := CS.new_progress()
	broken["cleared_mask"] = 0xFFFF
	broken["credits"] = -999
	broken["chapter"] = 99
	broken["best_grade"] = {"M01": "Z", "M02": "S", "NOPE": "A"}
	broken["best_score"] = {"M01": -50.0, "M02": 60.0}
	broken["best_reward"] = {"M01": -3, "M02": 200}
	broken["upgrades"] = {"suit_0": {"up": ["a", "b"], "down": ["x", "x", "x", "y", "z"]}}
	t.eq(CS.save_progress(broken, TMP), OK, "把损坏档写出去")
	var fixed := CS.load_progress(TMP)
	t.eq(int(fixed["cleared_mask"]), 4095, "越界的位掩码被裁到12位")
	t.eq(int(fixed["credits"]), 0, "负军资被归 0")
	t.eq(int(fixed["chapter"]), 3, "越界的章号被夹到最后一章")
	t.eq(fixed["best_grade"].has("M01"), false, "不认识的评价字母被丢掉")
	t.eq(str(fixed["best_grade"]["M02"]), "S", "合法的评价保留")
	t.eq(fixed["best_grade"].has("NOPE"), false, "不在战役里的关的成绩被丢掉")
	t.eq(fixed["best_score"].has("M01"), false, "负分被丢掉")
	t.near(float(fixed["best_score"]["M02"]), 60.0, 0.0001, "合法分数保留")
	t.eq(fixed["best_reward"].has("M01"), false, "负的军资基准被丢掉")
	t.eq(int(fixed["best_reward"]["M02"]), 200, "合法基准保留")
	var lo2: Dictionary = fixed["upgrades"]["suit_0"]
	t.eq(CS._str_list(lo2["up"]).size(), CS.UPGRADE_SLOTS_UP,
		"★ 上级槽被裁到 %d 个（存档里写了 2 个）" % CS.UPGRADE_SLOTS_UP)
	t.eq(CS._str_list(lo2["down"]).size(), CS.UPGRADE_SLOTS_DOWN,
		"★ 下级槽被裁到 %d 个（存档里写了 5 个）" % CS.UPGRADE_SLOTS_DOWN)
	t.eq(",".join(CS._str_list(lo2["down"])), "x,x,y",
		"★ 同一词条最多 %d 份（三份 x 里丢一份），槽位不够的后面直接不要"
			% CS.MAX_STACK_PER_ENTRY)

	# ---- clamp_loadout 是幂等的（裁过的不该再变）
	var once := CS.clamp_loadout(lo2)
	var twice := CS.clamp_loadout(once)
	t.eq(",".join(CS._str_list(twice["up"])), ",".join(CS._str_list(once["up"])), "clamp 幂等（上级）")
	t.eq(",".join(CS._str_list(twice["down"])), ",".join(CS._str_list(once["down"])), "clamp 幂等（下级）")
	t.eq(CS.slots_left(CS.empty_loadout(), "up"), CS.UPGRADE_SLOTS_UP, "空挂载：上级槽是满的")
	t.eq(CS.slots_left(CS.empty_loadout(), "down"), CS.UPGRADE_SLOTS_DOWN, "空挂载：下级槽是满的")
	t.eq(CS.slots_left(once, "down"), 0, "裁满之后没有空位")
	t.eq(CS.slots_left(once, "up"), 0, "上级也不该有空位（存档里写了两件）")
	t.eq(CS.loadout_of(CS.new_progress(), 0)["down"].size(), 0, "没记录的机体 ⇒ 空挂载")

	# ---- 删档只删自己那一个文件
	t.ok(FileAccess.file_exists(TMP), "删之前临时档在")
	CS.erase(TMP)
	t.not_ok(FileAccess.file_exists(TMP), "erase 把它删了")

	# ⚠️ 最重要的一条：本套件跑完，**玩家真实的存档逐字节没变**。
	t.eq(FileAccess.file_exists(real), real_had,
		"★ 真实存档的存在性没被改动（测试用了注入路径，没碰 user://campaign.cfg）")
	if real_had:
		t.eq(FileAccess.get_md5(real), real_md5, "★ 真实存档的内容逐字节没变")
	else:
		t.ok(not FileAccess.file_exists(real), "★ 本套件全程没有创建过真实存档")


# ============================================================ 14 兼容门
static func _compat(t: T) -> void:
	t.suite("剧情模式 / 兼容门（现有系统一个字都不许变）")
	# 现有 4 场遭遇还在、字段没变（M04 / M07 直接靠它们）。
	var cs := ChallengeScript.all()
	t.eq(cs.size(), 4, "现有 4 场遭遇一场没少（轮 B 的迁移是**派生**，没动它）")
	var ids: Array = []
	for e in cs:
		ids.append(e.id)
	t.eq(",".join(ids), "XI_VS_PENELOPE,XI_VS_ARIZEUS,PENELOPE_VS_XI,ARIZEUS_VS_XI",
		"4 场遭遇的 id 与顺序都没变（菜单顺序就是它）")
	t.eq(ChallengeScript.wave_count(ChallengeScript.xi_vs_penelope()), 1, "xi_vs_penelope 仍是 1 波")
	t.eq(ChallengeScript.wave_count(ChallengeScript.xi_vs_arizeus()), 2, "xi_vs_arizeus 仍是 2 波")
	t.eq(ChallengeScript.total_enemies(ChallengeScript.xi_vs_arizeus()), 4,
		"xi_vs_arizeus 仍是 3 台古斯塔夫 + 1 台阿利宙斯")

	# ★ M04 / M07 直接搬现有遭遇 ⇒ 逐字段相等（这是"复用"的判据）。
	t.ok(_same_waves(MS.by_id("M04").waves, ChallengeScript.xi_vs_penelope().waves),
		"★ M04 的波次与 `xi_vs_penelope()` **逐字段相等**（复用的证据）")
	t.ok(_same_waves(MS.by_id("M07").waves, ChallengeScript.xi_vs_arizeus().waves),
		"★ M07 的波次与 `xi_vs_arizeus()` **逐字段相等**（3 台古斯塔夫 + 阿利宙斯从上方入场）")
	t.eq(MS.by_id("M04").player_suit, SuitProfile.Id.XI, "M04 玩家开柯西")
	t.eq(MS.by_id("M04").enemy_suit, SuitProfile.Id.PENELOPE, "M04 的对手是佩涅罗佩")
	t.eq(MS.by_id("M04").arena, "PACIFIC", "M04 在太平洋")
	t.eq(MS.by_id("M07").arena, "ULURU", "M07 在艾尔斯岩")

	# `MissionRating.par_secs` 的四个现有分支**逐位不变**。
	t.near(MissionRating.par_secs(Game.MatchMode.TRAINING, 1), 35.0, 0.0001, "TRAINING 分支 35 s")
	t.near(MissionRating.par_secs(Game.MatchMode.CHALLENGE, 1), 45.0, 0.0001, "CHALLENGE 分支 45 s")
	t.near(MissionRating.par_secs(Game.MatchMode.SQUAD, 1), 55.0, 0.0001, "SQUAD 分支 55 s")
	t.near(MissionRating.par_secs(Game.MatchMode.VERSUS, 1), 120.0, 0.0001, "其余分支 120 s")
	t.near(MissionRating.par_secs(Game.MatchMode.CHALLENGE, 4), 180.0, 0.0001,
		"按台数缩放（4 台 × 45 s）—— 编队战不会因为固定 par 永远拿不到 S")
	t.near(MissionRating.par_secs(Game.MatchMode.CHALLENGE, 0), 45.0, 0.0001,
		"台数是 0 时按 1 台算（不除零）")

	# 评价体系三个权重与四个门限原样。
	t.near(MissionRating.W_OBJECTIVE, 0.45, 0.0001, "权重：战果 0.45")
	t.near(MissionRating.W_SURVIVAL, 0.35, 0.0001, "权重：存续 0.35")
	t.near(MissionRating.W_TEMPO, 0.20, 0.0001, "权重：效率 0.20")
	t.near(float(MissionRating.GRADE_TABLE[0]["min"]), 90.0, 0.0001, "S 的门限 90")
	t.near(float(MissionRating.GRADE_TABLE[1]["min"]), 74.0, 0.0001, "A 的门限 74")
	t.near(float(MissionRating.GRADE_TABLE[2]["min"]), 55.0, 0.0001, "B 的门限 55")
	t.near(float(MissionRating.GRADE_TABLE[3]["min"]), 30.0, 0.0001, "C 的门限 30")
	t.eq(MissionRating.NO_GRADE, "—", "失败不给字母（`NO_GRADE`），分项照常显示")

	# 地图：五张旧图仍在、关键字段没变，而**轮 B2 新加的那张排在最后**。
	# ⚠️ `MapDef.all_maps()` 返回的是 **Id（int）**，不是 MapDef 对象 —— 要经 `by_id()` 取。
	var map_ids := MapDef.all_maps()
	t.eq(map_ids.size(), 7, "五张旧图一张没少，另加轮 B2 的低地球轨道")
	var id_strs: Array = []
	for mid0: int in map_ids:
		id_strs.append(str(mid0))
	t.eq(",".join(id_strs), "0,1,2,3,4,5,6",
		"★ 编号与顺序都没变（0=PACIFIC … 4=DAVAO，新图**追加在末尾** 5=LEO）")
	var mnames: Array = []
	for mid: int in map_ids:
		mnames.append(MapDef.by_id(mid).name_cn)
	t.eq(mnames.has("达沃"), true, "达沃图还在")
	t.eq(mnames.has("奥恩贝利"), true, "奥恩贝利图还在")
	t.eq(mnames.has("艾尔斯岩"), true, "艾尔斯岩图还在")
	t.eq(mnames.has("太平洋群岛"), true, "太平洋群岛图还在")
	t.eq(mnames.has("低地球轨道"), true, "★★ 低地球轨道（轮 B2）在")
	t.eq(MapDef.by_id(MapDef.Id.DAVAO).city_layout, MapDef.CityLayout.DAVAO,
		"达沃城的布局没被改过（换城池会牵动整条城市管线）")

	# `IntroPlaylist`（开场动画）一个字都没动 —— 它管"开场随机抽一支"，与剧情播片两条管线。
	t.eq(IntroPlaylist.CLIPS.size(), 2, "开场片目仍是 2 支（剧情播片走另一条表，§7.5.5）")
	t.near(IntroPlaylist.total_weight(), 1.0, IntroPlaylist.WEIGHT_EPS, "开场权重和仍是 1.0")
	t.near(float(IntroPlaylist.CLIPS[1]["weight"]), 0.20, IntroPlaylist.WEIGHT_EPS,
		"马夫蒂那支仍是 20%")


# ============================================================ 15 迁移（轮 B）
#
# DESIGN §10 轮 B 的判据原话是「**零行为变化**：波次 / 敌数 / 高度 / 结算读数**逐项相同**」。
# 本节把它**形式化**成三条：
#   ① 正向映射 `Encounter → Mission`：`Encounter` 的字段**一个都没丢**；
#   ② 反向 + 往返 `Mission → Encounter`：逐字段回到原样（这正是"同一份数据"的证据）；
#   ③ `par()` 走的是**现有那条分支**（结算读数不是"照抄"，是**算出来一样**）。
# ⚠️ 还有一条跑不掉的前提：`_compat` 里那几行（4 场遭遇的 id / 顺序 / 波次数）
# 与 `suite_round.gd` 的既有断言 —— 它们才是"迁移前 vs 迁移后"的对照面。
static func _migrate(t: T) -> void:
	t.suite("剧情模式 / 轮 B 迁移（4 场 Encounter ⇄ Mission · 零行为变化）")

	# ---- ① 场地反查与正查**严格互逆**（5 张图全覆盖）
	for mid: int in MapDef.all_maps():
		var a := MS.arena_for(mid)
		t.not_ok(a.is_empty(), "MapDef.Id %d 有对应的 arena 串（%s）" % [mid, a])
		t.eq(MS.map_id_for(a), mid, "★ `map_id_for(arena_for(%d)) == %d`（正反互逆）" % [mid, mid])
	t.eq(MS.arena_for(9999), "", "认不出的 map_id ⇒ 空串（**不兜到别的图上**）")
	t.ok(MS.is_arena_pending(MS.arena_for(9999)),
		"空串 arena 被当成'图待新建'（fail-closed，不会静默跑在太平洋上）")

	# ---- ② 4 场一一对应，id 与顺序一致
	var fe := MS.free_all()
	var ce := ChallengeScript.all()
	t.eq(fe.size(), 4, "自由遭遇恰好 4 场（= 现有遭遇数）")
	t.eq(ce.size(), 4, "对照：`ChallengeScript.all()` 仍是 4 场（本轮没动它）")
	var fids: Array = []
	for m in fe:
		fids.append(m.id)
	t.eq(",".join(fids), "XI_VS_PENELOPE,XI_VS_ARIZEUS,PENELOPE_VS_XI,ARIZEUS_VS_XI",
		"★ id 与顺序与 `ChallengeScript.all()` 完全一致（菜单顺序就是它）")
	t.eq(MS.free_by_id("M01"), null, "自由遭遇表里没有 M01（两张表不混）")

	# ---- ③ 正向映射：`Encounter` 的字段一个都没丢
	for i in ce.size():
		var e = ce[i]
		var m = fe[i]
		t.eq(m.player_suit, e.player_suit, "%s 玩家机" % e.id)
		t.eq(m.enemy_suit, e.enemy_suit, "%s 敌机" % e.id)
		t.eq(m.map_id(), e.map_id, "%s 图（arena ⇒ MapDef.Id）" % e.id)
		t.eq(m.title, e.title, "%s 标题" % e.id)
		t.eq(m.brief, e.brief, "%s 简报" % e.id)
		t.eq(m.story, e.story, "%s 剧情文案（`story` 这个位子没浪费）" % e.id)
		t.ok(_same_waves(m.waves, e.waves), "%s 波次逐字段相等" % e.id)
		t.eq(m.chapter, 0, "%s 不属于战役（chapter 0 ⇒ `for_chapter` 筛不到）" % e.id)
		t.eq(m.index, 0, "%s 章内序号 0" % e.id)
		t.eq(m.waves_auto, true, "%s 波次自动推进（= 现状行为）" % e.id)
		t.eq(m.objectives.size(), 1, "%s 恰好一个目标" % e.id)
		t.eq(m.objectives[0].kind, MS.Objective.Kind.DESTROY_ALL, "%s 目标是 DESTROY_ALL" % e.id)
		t.eq(m.objectives[0].count, ChallengeScript.total_enemies(e),
			"%s 目标台数 = 现有遭遇的总敌数（%d）" % [e.id, ChallengeScript.total_enemies(e)])
		t.eq(m.objectives[0].required, true, "%s 这个目标是主要目标" % e.id)

	# ---- ④ 反向映射 + 往返：逐字段回到原样
	for i in ce.size():
		var e2 = ce[i]
		var back = MS.to_encounter(fe[i])
		t.ok(back != null, "%s 能转回 Encounter" % e2.id)
		if back == null:
			continue
		t.eq(back.id, e2.id, "%s id 往返" % e2.id)
		t.eq(back.player_suit, e2.player_suit, "%s 玩家机往返" % e2.id)
		t.eq(back.enemy_suit, e2.enemy_suit, "%s 敌机往返" % e2.id)
		t.eq(back.map_id, e2.map_id, "%s 图往返" % e2.id)
		t.eq(back.title, e2.title, "%s 标题往返" % e2.id)
		t.eq(back.brief, e2.brief, "%s 简报往返" % e2.id)
		t.eq(back.story, e2.story, "%s 剧情文案往返" % e2.id)
		t.ok(_same_waves(back.waves, e2.waves), "%s 波次往返" % e2.id)
		t.eq(ChallengeScript.wave_count(back), ChallengeScript.wave_count(e2), "%s 波次数往返" % e2.id)
		t.eq(ChallengeScript.total_enemies(back), ChallengeScript.total_enemies(e2),
			"%s 总敌数往返" % e2.id)

	# ---- ⑤ 结算读数：par 走的是现有那条分支（"逐项相同"的形式化）
	t.near(MS.free_by_id("XI_VS_PENELOPE").par(),
		MissionRating.par_secs(Game.MatchMode.CHALLENGE, 1), 0.0001,
		"★ xi_vs_penelope 的 par = 现有挑战模式的 1 台档（45 s）")
	t.near(MS.free_by_id("XI_VS_ARIZEUS").par(),
		MissionRating.par_secs(Game.MatchMode.CHALLENGE, 4), 0.0001,
		"★ xi_vs_arizeus 的 par = 4 台档（= 现有结算读数）")
	t.near(MS.free_by_id("XI_VS_ARIZEUS").par(), 180.0, 0.0001, "4 台 × 45 s = 180 s")

	# ---- ⑥ 派生**不缓存**：两次调用是两个对象、但字段一致（不许共享可变状态）
	var again := MS.free_all()
	t.not_ok(again[0] == fe[0], "★ 每次派生都是新对象（不缓存 ⇒ 源改了视图跟着变）")
	t.eq(again[0].title, fe[0].title, "两次派生的标题一致")
	t.eq(again[0].arena, fe[0].arena, "两次派生的场地一致")

	# ---- ⑦ "共享"指的是**同一条调用链内**的共享
	# ⚠️ 这条断言第一版写错了，值得记下来：`ChallengeScript.all()` 的每个工厂
	# 都 `Encounter.new()` / `Wave.new()` —— **每次调用都是新对象**。
	# 所以拿 `all()` 的结果去和 `free_all()` 内部**再调一次** `all()` 的结果比 `==`，
	# 必然为假（首轮 4 条 FAIL 全是这一条）。
	# ⇒ 同一性只能在**同一条调用链**上验：给 `free_from_encounter()` 喂哪个 `e`，
	#   它的 `waves` 就与**那个 `e`** 共享。
	# ⚠️ 另：`Array` 的 `==` 是**逐元素比较**（元素相同就为真）⇒ 它**证明不了**引用共享；
	#   要判"是不是同一个数组"必须用 `is_same()`（身份比较）。
	var e_one = ChallengeScript.xi_vs_penelope()
	var m_one = MS.free_from_encounter(e_one)
	t.ok(is_same(m_one.waves, e_one.waves),
		"★ `waves` 是**同一个数组**（`is_same` 身份比较，不是元素比较）")
	t.ok(m_one.waves[0] == e_one.waves[0],
		"★ 第一波是**同一个 Wave 对象**（Object 的 `==` 就是身份比较）")
	t.not_ok(is_same(ChallengeScript.xi_vs_penelope().waves, e_one.waves),
		"对照：`all()` 每次新建 ⇒ 两条调用链的 waves 不是同一个数组")

	# ---- ⑧ `map_id() < 0` 的关**不许**造出指向不存在图的 Encounter
	#
	# ⚠️ 轮 B2 换了样本。原来这条用 M03 当例子（当时 LEO 未建 ⇒ `map_id() = −1`），
	# 而 M03 现在**建出来了** —— 它转得出 Encounter 了，这正是本轮要做成的事。
	# 但"不静默兜到别的图上"这条不变量**不能跟着消失**，于是在这里
	# 用一个**人造的** Mission（`arena` 指向一个不存在的场地）继续守着它 ——
	# 这样它就不再依赖"恰好有一关没建图"这种时代偶然。
	# ⚠️ 那条"真实存在的关"的分支也没丢：还有一关挂着 pending（就是 POV 待拍板那一关），
	# 但它们的 `arena` 都是现成的图（`ARENA_PENDING` 是空的），所以真实样本
	# 暂时只剩人造这一个 —— 见 `_source()` 里对 `ARENA_PENDING` 的源码断言。
	var ghost := MS.Mission.new("GHOST", "幽灵关")
	ghost.arena = "NOT_A_MAP"
	t.eq(ghost.map_id(), -1, "人造样本：指向不存在场地的 Mission ⇒ `map_id() = −1`")
	t.eq(MS.to_encounter(ghost), null,
		"★ `map_id() < 0` ⇒ null（**不造指向不存在图的 Encounter**）")
	t.eq(MS.to_encounter(null), null, "null 进 ⇒ null 出（不崩）")
	t.ok(MS.to_encounter(MS.by_id("M03")) != null,
		"★ M03（LEO 轮 B2 已建）**现在**转得出 Encounter 了")
	t.ok(MS.to_encounter(MS.by_id("M04")) != null, "M04（图已建）也能转回 Encounter")

	# ---- ⑨ 自由遭遇的 id 不占用战役关号
	for m2 in fe:
		t.eq(MS.by_id(m2.id), null, "自由遭遇 id `%s` 不撞战役关号" % m2.id)
	for m3 in MS.for_chapter(1):
		t.gt(float(m3.chapter), 0.0, "第一章里只有战役关（%s）" % m3.id)
	for m4 in MS.for_chapter(2):
		t.gt(float(m4.chapter), 0.0, "第二章里只有战役关（%s）" % m4.id)


static func _same_waves(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var x = a[i]
		var y = b[i]
		if x.count != y.count or x.suit != y.suit \
				or not is_equal_approx(x.altitude, y.altitude) \
				or not is_equal_approx(x.spread_deg, y.spread_deg) \
				or x.aggressive != y.aggressive:
			return false
	return true


# ============================================================ 16 源码扫描
static func _source(t: T) -> void:
	t.suite("剧情模式 / 源码扫描（别在数据层里塞运行时东西）")
	var ms_src := _read("res://scripts/data/mission_script.gd")
	var cs_src := _read("res://scripts/data/campaign.gd")
	t.gt(float(ms_src.length()), 1000.0, "读到了 mission_script.gd")
	t.gt(float(cs_src.length()), 1000.0, "读到了 campaign.gd")

	# 数据层必须是纯的：不碰节点、不读时间、不用随机。
	for pair: Array in [["mission_script.gd", ms_src], ["campaign.gd", cs_src]]:
		var name := str(pair[0])
		var src := str(pair[1])
		t.not_ok(src.contains("get_node("), "%s 不碰节点（纯数据层）" % name)
		t.not_ok(src.contains("Time.get_ticks"), "%s 不读真实时钟（用喂进来的字典）" % name)
		t.not_ok(src.contains("randi(") or src.contains("randf("),
			"%s 不用随机（概率要落在纯函数的权重里，不能落在运行时）" % name)
		t.not_ok(src.contains("preload(\"res://assets/"), "%s 不引用任何外部素材（零素材也要能开工）" % name)
		t.not_ok(src.contains("Input."), "%s 不读输入（那是 HUD / main 的事）" % name)

	# 触发器**不存**运行时状态（`fired`）—— 数据被 7 关共享，写进去就是"两个写者"。
	t.not_ok(ms_src.contains("var fired"), "Trigger 里没有 `fired` 字段（已触发状态归运行时）")
	t.ok(ms_src.contains("const ACTION_KINDS"), "动作是**白名单**常量，不是散在代码里的字符串")
	t.ok(ms_src.contains("static func validate("), "有 `validate()` 把坏数据当场点名")
	t.ok(ms_src.contains("ARENA_PENDING"), "场地解析有\"待建\"这条路（不静默兜到别的图上）")
	t.not_ok(ms_src.contains("const MASK_ORDER"),
		"位掩码顺序只在 campaign.gd 里定义一次（不两边都写 = 不会有第二份真源）")

	# 存档：读写都必须收注入路径（否则测试会把玩家真实的档写花）。
	t.ok(cs_src.contains("func save_progress(progress: Dictionary, path := PATH)"),
		"写档函数收注入路径")
	t.ok(cs_src.contains("func load_progress(path := PATH)"),
		"读档函数收注入路径")
	t.ok(cs_src.contains("func erase(path := PATH)"), "删档函数收注入路径")
	t.ok(cs_src.contains("const PATH := \"user://campaign.cfg\""), "存档路径是常量（一处真源）")

	# 不改现有模式：剧情模式**扩展** `CHALLENGE`，不新增 `MatchMode`。
	t.not_ok(cs_src.contains("MatchMode.STORY"), "没有 `MatchMode.STORY`（DESIGN §9.3：扩展不新增）")
	t.not_ok(ms_src.contains("MatchMode.STORY"), "mission_script 里也没有")
	t.not_ok(cs_src.contains("match_mode ="), "campaign 不改对局模式")
	t.not_ok(ms_src.contains("match_mode ="), "mission_script 也不改")

	# 军资的三条硬约束要写在**代码**里（不是只写在注释里）。
	t.ok(cs_src.contains("maxi(0, now_reward - best_reward)"),
		"军资差额的\"更差给 0\"是代码里的 `maxi`，不是约定")
	t.ok(cs_src.contains("maxi(base + gb"), "军资公式的返回值夹到非负")
	t.ok(cs_src.contains("clampi(int(st.get(\"named_kills\""),
		"`named_kills` 被夹到 ≤ kills（不许多报）")


static func _read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


# ============================================================ 17 轮 50（夜袭达沃 / 镜像出击）
##
## ★★ 轮 50 · 2026-09-30：老板两句改动（原话）：
##   「第一张夜袭达沃不应该设置敌人，开局应该是三台马夫蒂踏板登场的（玩家的加乌曼是其中一台）。
##      任务目标应该是**对着联邦内阁下榻的酒店使用光束步枪射击**，就算完成任务了。」
##   「M02 的古斯塔夫出生位置要和 M01 的梅萨出生位置在**地图的镜像位置**，
##      古斯塔夫的任务就是**击溃一台梅萨**了。」
##
## 口径（老板拍板）：马夫蒂这边**沿用小队编制**（3 板 × 2 台 = 6 台）；
## M01 **只留“射击”这一条目标**。
##
## ⚠️ 这一节里有一条**守门判据**（第 ⑥ 组）—— 它挡的是
## “将来有人让一关 opt-in（`win_on_clear = false`）、却忘了给
## `Game._end_state()` 补键”这一类**静默不可赢**的故障
##（缺键 ⇒ `_i()` 拿到 0 ⇒ 恒假 ⇒ 那一关永远打不赢，且一处都不报错）。
static func _r50(t: T) -> void:
	t.suite("剧情模式 / 轮 50（夜袭达沃 · 镜像出击）")
	var m1 = MS.by_id("M01")
	var m2 = MS.by_id("M02")

	# ---- ① M01：一架敌机都没有
	t.not_ok(m1.has_enemies(), "★ M01 没有敌人（`has_enemies()` == false）")
	t.eq(m1.total_enemies(), 0, "M01 敌机总数 0")
	t.eq(m1.wave_count(), 0, "M01 波数 0")

	# ---- ② M01：胜利条件不是清场，而是那唯一一条目标
	t.not_ok(m1.win_on_clear, "★ M01 的胜利条件**不是清场**（`win_on_clear == false` ⇒ 判胜改由目标把关）")
	t.eq(m1.objectives.size(), 1, "★ M01 **只留一条目标**（老板：「只留这一条」）")
	t.eq(m1.objectives[0].kind, MS.Objective.Kind.STRIKE, "那一条是 STRIKE（对地标开一枪）")
	t.ok(m1.objectives[0].required, "它是**主要**目标（不是可选）")
	t.eq(m1.objectives[0].count, 1, "打中 1 次即完成")
	t.eq(m1.objectives[0].target, m1.landmark_group,
		"目标的 `target` 存的就是本关的 `landmark_group`（**组名**，不是 Zone id）")

	# ---- ③ 地标组名**跨模块一致**（只改一边 = “打中了但目标永远不完成”，一处都不报错）
	t.eq(WorldBuilder.HOTEL_GROUP, "davao_hotel", "地标组名的真源在 `WorldBuilder`")
	t.eq(m1.landmark_group, WorldBuilder.HOTEL_GROUP,
		"★ `Mission.landmark_group` 与 `WorldBuilder.HOTEL_GROUP` **逐字相同**")

	# ---- ④ M01：友军编队（3 板 × 2 台 = 6 台，玩家占其中一块的领机位）
	t.ok(m1.has_allies(), "★ M01 有友军编队（开局三台马夫蒂踏板登场）")
	t.eq(m1.ally_side, BattleFormation.Side.MAFTY, "友军是马夫蒂那边")
	t.eq(m1.ally_aces, 0,
		"★ **不带 ACE** —— 第一章 Ξ 还没到手，多带一台柯西等于凭空发一台")
	var al: Array = m1.allies()
	t.eq(al.size(), 6, "★ 友军 6 台（沿用小队编制：3 板 × 2 台）")
	var squads: Dictionary = {}
	var mine := 0
	var aces := 0
	var leads := 0
	for u: BattleFormation.Unit in al:
		squads[u.squad] = true
		if u.owner_is_player:
			mine += 1
		if u.is_ace:
			aces += 1
		if not u.is_ace and u.slot == 0:
			leads += 1
	t.eq(squads.size(), 3, "★ 分 3 个编队（= 3 块踏板）")
	t.eq(leads, 3, "★ 3 台领机（踏板挂在领机身上）")
	t.eq(aces, 0, "一张 ACE 都没有")
	t.eq(mine, 1, "★ **恰好一台是玩家的**（加乌曼自己也是骑板的）")

	# ---- ⑤ M02：击溃一台梅萨 + 没有友军
	t.eq(m2.objectives.size(), 1, "★ M02 只留一条目标")
	t.eq(m2.objectives[0].kind, MS.Objective.Kind.DESTROY_ALL, "那一条是 DESTROY_ALL（击溃）")
	t.eq(m2.objectives[0].count, 1, "★ 只要求 1 台（老板：「击溃一台梅萨」）")
	t.eq(m2.total_enemies(), 1, "M02 全场就 1 台敌机 ⇒ 与「击溃一台」自洽")
	t.not_ok(m2.has_allies(), "M02 没有友军编队（只有 M01 是突袭关）")
	t.eq(m2.win_on_clear, true, "★ M02 的判胜路径**逐位不变**（仍然是清场）")

	# ---- ⑥ 其余各关**一个字都不许变**（这一组是“只动了 M01 / M03 这两关”的证据）
	#
	# ⚠️ 轮 55：M03 也进了“零敌机 + 目标门”这一侧（老板：「接货这一关不要设置敌人」）
	# ⇒ 免检名单从 `["M01"]` 变成 `["M01", "M03"]`，**只放行这两个**（不是删掉这一组）。
	var OPT_IN_OK := ["M01", "M03", "M06", "M08", "M09", "M10", "M11", "M12"]
	var flipped: Array = []
	var nospace: Array = []
	for m in MS.all():
		if OPT_IN_OK.has(m.id):
			continue
		if not m.win_on_clear:
			flipped.append(m.id)
		if not m.has_enemies():
			nospace.append(m.id)
	t.eq(flipped.size(), 0,
		"除 opt-in 的 %s 外每关的 `win_on_clear` 都是 true（判胜路径逐位不变）。异常的：%s"
			% [str(OPT_IN_OK), str(flipped)])
	t.eq(nospace.size(), 0,
		"除 opt-in 的 %s 外每关都有敌人。没有的：%s" % [str(OPT_IN_OK), str(nospace)])
	# 另一头也钉住：**免检的恰好是那两个**（免得将来有人往名单里塞第三关来“修红”）。
	var opt_in: Array = []
	for mm in MS.all():
		if not mm.win_on_clear or not mm.has_enemies():
			opt_in.append(mm.id)
	t.eq(",".join(opt_in), ",".join(OPT_IN_OK),
		"★ 走目标门（或零敌机）的关**恰好**是 M01 / M03 —— 名单不许悄悄变长")

	# ---- ⑦ 守门：opt-in 的关只能用 `Game._end_state()` **喂过键**的 kind
	#
	# ⚠️ 轮 55：`REACH` 进了覆盖集 —— `Game._end_state()` 现在喂 `zones`
	#（M03 的主要目标就是它：飞到运输仓 0.6 km 内）。
	# `Game._end_state()` 目前覆盖 STRIKE(landmark_hits) / DESTROY_ALL(killed,total)
	# / SURVIVE(elapsed) / REACH(zones)。其它 kind 读的键运行时**没人写** ⇒ 缺键 ⇒ 恒假。
	#
	# ⚠️ 这一条与那个函数里的注释是**一对**：那边写着
	# “将来让某一关 opt-in 时先在这里补键”，这里就是那句话的**可执行形式**。
	var covered := [MS.Objective.Kind.STRIKE, MS.Objective.Kind.DESTROY_ALL,
		MS.Objective.Kind.SURVIVE, MS.Objective.Kind.REACH, MS.Objective.Kind.EVENT]
	var uncovered: Array = []
	for m in MS.all():
		if m.win_on_clear:
			continue
		for o in m.required_objectives():
			if not covered.has(o.kind):
				uncovered.append("%s/%s" % [m.id, MS.Objective.kind_name(o.kind)])
	t.eq(uncovered.size(), 0,
		"★ 每个 opt-in 关的**主要目标**都用 `Game._end_state()` 覆盖过的 kind。没覆盖的：%s" % str(uncovered))

	# ---- ⑧ 新条件进了白名单
	t.ok(MS.Trigger.KEYS.has("landmark_hits"),
		"★ `landmark_hits` 进了 `Trigger.KEYS` 白名单（否则 `landmark_hits>=1` 会**恒假**且不报错）")

	# ---- ⑨ `Game._end_state()` 的键集（**守门判据的另一半**）----
	#
	# ⑦ 那条钉的是"opt-in 的关只能用**已覆盖**的 kind"；
	# 这一条钉的是"那个覆盖集真的在"—— 两条合起来才把
	# “改了 kind 却忘了补键”这个静默失效堵死。
	var st: Dictionary = Game._end_state()
	t.eq(st.size(), 6,
		"★ `Game._end_state()` 恰好喂6个键（多喂无害，少喂致命）")
	for k: String in ["landmark_hits", "killed", "total", "elapsed", "zones", "mission_events"]:
		t.ok(st.has(k),
			"★ `_end_state()` 里有 `%s`（少一个 ⇒ 那一类目标永远不成立、且一处都不报错）" % k)
	t.ok(st.get("zones") is Dictionary,
		"★ `zones` 是**字典**（zone id → 到过没有），不是布尔 —— 降成布尔就丢掉了“一关多目标”的分辨力")
	t.eq(st.get("landmark_hits"), Game.landmark_hits,
		"`landmark_hits` 直接取自 `Game` 上的计数（不另算一份）")

	# ---- ⑩ 每局清零：不清 ⇒ 上一局那一枪让这一关**开局即通关**
	var keep: Dictionary = {"phase": Game.phase, "player": Game.player,
		"mission": Game.active_mission, "challenge": Game.active_challenge,
		"wave": Game.challenge_wave, "hits": Game.landmark_hits,
		"zones": Game.zone_reached.duplicate()}
	Game.landmark_hits = 3
	Game.zone_reached["orbit_cargo"] = true
	Game.reset()
	t.eq(Game.landmark_hits, 0,
		"★ `Game.reset()` 把 `landmark_hits` 清零（否则上一局那一枪会让 M01 开局即通关）")
	t.eq(Game.zone_reached.size(), 0,
		"★ `Game.reset()` 把 `zone_reached` 清空（否则上一局飞过的接收区会让 M03 开局即通关）")

	# ---- ⑪ ★ 目标门的**行为**：零敌机 + 目标未达成 ⇒ **不许判胜**；打中 ⇒ 判胜
	#
	# ⚠️ 这一段**不需要场景树**：M01 走的是目标门（`win_on_clear == false`），
	# 绕开了 `live_hostiles_of()` ⇒ 一个只有 `is_alive()` 的桩机体就够了。
	# ⚠️ 动 `Game` 全局状态必须**存还原**（同 `suite_tutorial` 的先例）。
	var probe := _ProbeBody.new()
	Game.reset()
	Game.set_phase(Game.Phase.FIGHT)
	Game.player = probe
	Game.active_mission = m1
	Game.active_challenge = MS.to_encounter(m1)
	Game.challenge_wave = 0
	Game.recheck_end()
	t.eq(Game.phase, Game.Phase.FIGHT,
		"★ M01 开局：**零敌机 + 目标未达成** ⇒ 不许判胜（这正是「开局即通关」的反面）")
	# ⚠️ **这里刻意不调 `Game.note_landmark_hit()`**（虽然它才是"上报"的真入口）。
	#
	# 它会 `emit landmark_hit`，而**任何活着的 main 实例**都接着那个信号
	#（`main._ready()` 里 connect）⇒ 会真的推结算页 → `_settle_campaign()`。
	# 本套件**没有 host、自己不建 main**，但 `suite_cruise_form._mount()` 会经
	# `run_suite()` **嵌套**调起本套件 —— 那一刻它挂着自己的 main！
	# 于是全量回归里这一段会喷 3 条 SCRIPT ERROR（`campaign.gd:310` 读空词典的
	# `best_reward`、`main.gd:1190` 读空词典的 `progress`、以及 `_finish_round`
	# 之后还原 player 时的 `previously freed`），**而运行期错误不进 PASS/FAIL 账**
	# ⇒ 单跑全绿、全量里悄悄报错（轮 50 埋下、轮 54 才发现）。
	# ⇒ 行为判据改用等价的"直接置计数"，"上报那一步会自动求值"改用**源码切片**钉。
	Game.landmark_hits = 1
	Game.recheck_end()
	t.eq(Game.phase, Game.Phase.WIN,
		"★ 目标达成 ⇒ 判胜（`recheck_end()` 是推出去的那一层；上报见下面的源码切片）")

	# ---- ⑪b 源码切片：`note_landmark_hit()` 必须**自己**加计数、**自己**主动求值
	#
	# ⚠️ 为什么用源码而不是再跑一次：见上面那段（会被别处的 main 接走）。
	# 要钉的是两件事，两件都是静默失效：
	#   ① 计数 —— 它是判胜的**唯一输入**（门读的 `landmark_hits` 就来自这里）；
	#   ② **主动**调 `_evaluate_end()` —— 那个函数**全工程没有周期性调用者**
	#      （唯一调用方 `notify_destroyed()` 与你这一行）⇒ 漏了这一步的表现是
	#      「打中酒店却永远不结算」，一处都不报错。
	var gsrc := FileAccess.get_file_as_string("res://scripts/autoload/game.gd")
	var f0 := gsrc.find("func note_landmark_hit")
	var f1 := gsrc.find("\nfunc ", f0 + 1) if f0 >= 0 else -1
	t.ok(f0 >= 0 and f1 > f0, "`game.gd` 里有 `note_landmark_hit()`")
	var fbody := gsrc.substr(f0, f1 - f0) if (f0 >= 0 and f1 > f0) else ""
	t.ok(fbody.contains("landmark_hits += 1"),
		"★ 上报函数体里必须 `landmark_hits += 1`（计数是判胜的唯一输入）")
	t.ok(fbody.contains("_evaluate_end()"),
		"★★ 上报函数体里必须**主动**调 `_evaluate_end()`"
		+ "（它没有周期性调用者 —— 漏了就是「打中酒店永远不结算」且不报错）")

	# ---- ⑫ ★ 内建的**反向对照**：证明“开局不判胜”确实是**那道门在做功**
	#
	# 把这一关的 `win_on_clear` 改回 `true`（= 老的“清场即胜”），
	# **其它一切照旧** ⇒ 同一个状态下立刻判胜。不做这一步的话，
	# 上面那条“不判胜”是否真由门负责就**无从得知**。
	# ⚠️ 用 `MS.m01()` 现做一份副本，不动全局共享的那一份。
	var door: MS.Mission = MS.m01()
	door.win_on_clear = true
	Game.landmark_hits = 0
	Game.active_mission = door
	Game.set_phase(Game.Phase.FIGHT)
	Game.recheck_end()
	t.eq(Game.phase, Game.Phase.WIN,
		"★ 负对照：`win_on_clear` 改回 true（其余一切照旧）⇒ **同一状态下立刻判胜**"
		+ " —— 证明上面那条「不判胜」确实由那道门负责")

	# ---- ⑬ ★ 轮 55：M03 的目标门**行为**（与 ⑪ 同款，但走的是 `zones` 而不是 `landmark_hits`）
	#
	# M03 零敌机 + `win_on_clear == false` ⇒ 判胜的唯一入口是「进过 `orbit_cargo` 那个球」。
	# ⚠️ 同样**不需要场景树**（目标门绕开 `live_hostiles_of()`）。
	var m3: MS.Mission = MS.by_id("M03")
	Game.reset()
	Game.set_phase(Game.Phase.FIGHT)
	Game.player = probe
	Game.active_mission = m3
	Game.active_challenge = MS.to_encounter(m3)
	Game.challenge_wave = 0
	Game.recheck_end()
	t.eq(Game.phase, Game.Phase.FIGHT,
		"★ M03 开局：**零敌机 + 未进接收区** ⇒ 不许判胜")
	Game.zone_reached["orbit_cargo"] = true
	Game.recheck_end()
	t.eq(Game.phase, Game.Phase.WIN,
		"★ 进过接收区 ⇒ 判胜（`main._tick_mission_zones()` 锁存的就是这个键）")
	# 负对照：**别的** zone 不算数 —— 证明这条判胜确实由「那一个区」负责。
	Game.reset()
	Game.set_phase(Game.Phase.FIGHT)
	Game.player = probe
	Game.active_mission = m3
	Game.active_challenge = MS.to_encounter(m3)
	Game.zone_reached["reentry_line"] = true
	Game.recheck_end()
	t.eq(Game.phase, Game.Phase.FIGHT,
		"★★ 负对照：只到过 `reentry_line`（再入线）⇒ **仍然不判胜**（判据不是「进过任意一个区就算」）")

	# ---- 还原（⚠️ 先 `reset()` 把 `player` 置空，再 `free()` 桩机）
	Game.reset()
	Game.phase = keep["phase"]
	# ⚠️ 存下来的那个 `player` **可能已经被释放**：本套件会被 `suite_cruise_form._mount()`
	# 嵌套调用，那期间它的场景可能重载过 ⇒ `keep["player"]` 指向的节点已 free。
	# 不判就赋值 ⇒ `Invalid assignment … with value of type 'previously freed'`
	#（运行期错误，不进 PASS/FAIL 账，只在日志里留一行）。
	var old_player = keep["player"]
	if old_player != null and is_instance_valid(old_player):
		Game.player = old_player
	Game.active_mission = keep["mission"]
	Game.active_challenge = keep["challenge"]
	Game.challenge_wave = keep["wave"]
	Game.landmark_hits = keep["hits"]
	Game.zone_reached = keep["zones"]
	probe.free()


## ★ 轮 50：专给上面那段行为判据用的桩机体。
##
## 只实现 `Game.live_player()` 真正调用的那一个方法。
## ⚠️ 为什么不直接 `FlightBody.new()`：那个类在树外构造会带上一堆
## 与本判据无关的依赖（飞行模型 / 模型场景）；这里只想验"判胜那一条路"。
class _ProbeBody extends Node3D:
	func is_alive() -> bool:
		return true

	func is_hostile_to(_other: Node3D) -> bool:
		return false

# ============================================================ 18 轮 57（M04 开场演出 · 数据侧）
##
## ★★ 轮 57 · 2026-09-30：老板一句需求（原话）：
## > 「重力这一关我说要先做**佩涅罗佩使用光束大炮攻击柯西运输仓**，
## >  然后再是玩家操控柯西和佩涅罗佩对决。」
##
## ⚠️ 这一节只钉**数据侧**（哪个关挂着这个演出、演出不碰胜负与编制）——
## 演出的时间线、几何、接线与「不掉血」口径在 `suite_pod_strike.gd` 里
## （那边是它自己的地盘；本仓库有并行会话，别把别人的主题塞进来）。
static func _pod_strike(t: T) -> void:
	t.suite("剧情模式 / 轮 57（M04 开场演出的数据侧）")
	var m04 := MS.by_id("M04")
	t.ok(m04.pod_strike, "★ M04「重力」挂着开场演出（`pod_strike == true`）")

	var others: Array = []
	for m in MS.all():
		if m.id != "M04" and m.pod_strike:
			others.append(m.id)
	t.eq(others.size(), 0, "★ 只有 M04 挂着它（多出来的：%s）" % str(others))

	# 默认值必须是 false —— 否则"新加一关忘了关掉"会让它凭空演一段。
	t.eq(MS.Mission.new("TMP", "临时").pod_strike, false,
		"★ `Mission` 的默认 `pod_strike` 是 false（新关不会凭空带演出）")

	# 演出**不改胜负、不改编制**：还是单波一台佩涅罗佩、还是一条目标。
	t.eq(m04.objectives.size(), 1, "★ M04 仍然只有一条目标（演出**不加**新目标）")
	t.eq(m04.objectives[0].kind, MS.Objective.Kind.DESTROY_ALL,
		"……那条仍是「击败佩涅罗佩」（演出**不改**胜负条件）")
	t.eq(m04.wave_count(), 1, "★ M04 仍是单波（演出**不撒**额外机体）")
	t.eq(m04.total_enemies(), 1, "★ 场上就佩涅罗佩一台（被接管的也是它）")
	t.eq(m04.enemy_suit, SuitProfile.Id.PENELOPE, "简报里的敌方机型仍是佩涅罗佩")

