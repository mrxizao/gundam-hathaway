class_name SuiteRound19
extends RefCounted
## 第十九轮：**大战场 + 燃料槽 + 骑板放行军刀**。
##
## 老板原话：「扩大游戏地图战场，玩家需要先飞 20 秒左右才能到战场，同时给梅萨和
## 古斯塔夫加入**燃料槽系统**，他们的加速键按 shift 会有燃料槽作为**时间限制**，
## **必须依靠飞行踏板才能赶到战场**」＋「只有量产机有」。
##
## ## 这一轮的核心是一条**算术一致性**
## 三个数必须互相咬合，任何一个单独改了都会让机制静默失效：
##   `WorldBuilder.SPAWN_RADIUS`（要飞多远）× 量产机极速（飞多快）
##   × `SuitProfile.jet_seconds`（能加速多久）
##
## 下面第二组就是把这组不等式**钉成断言**：
##   - 飞得完吗？（出击距离 ÷ 极速 ≤ 20 s 量级 —— 不然"先飞 20 秒"是空话）
##   - 不骑板到得了吗？（槽时长 × 极速 < 出击距离的一半 ⇒ 必须靠板）
##   - 出击点在竞技场里吗？（否则一出生就被"回界"推着走）
##
## 分四组测：
##   1. **槽本身**（数据 + 消耗 / 回充 / 见底裁决）
##   2. **算术一致性**（上面那三条不等式）
##   3. **只有量产机有槽**（ACE 机不受限）
##   4. **骑板放行军刀** + 骑板仍不能悬停（踏板的取舍还在）

const GAUGE := "Round19 / 燃料槽：消耗与回充"
const MATH := "Round19 / 算术一致性：航程 × 极速 × 槽时长"
const WHO := "Round19 / 只有量产机有槽"
const TRADEOFF := "Round19 / 踏板的取舍：放开军刀、仍禁悬停"
const ASSIST := "Round19 / 辅助驾驶模式下的槽（槽空也要能回来）"


static func run(t: T, host: Node) -> void:
	t.suite(GAUGE)
	await _gauge(t, host)
	t.suite(MATH)
	_math(t)
	t.suite(WHO)
	_who(t)
	t.suite(TRADEOFF)
	await _tradeoff(t, host)
	t.suite(ASSIST)
	await _assist(t, host)


# ---------------------------------------------------------------- 1 槽本身

static func _gauge(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var fb := _make(c, "JetMesser", 1, SuitProfile.messer_m01())
	await host.get_tree().physics_frame

	t.ok(fb.has_jet_gauge(), "梅萨有燃料槽")
	t.near(fb.jet_left, fb.profile.jet_seconds, 0.001, "开局是满槽")
	t.near(fb.jet_ratio(), 1.0, 0.001, "比例 = 1.0")

	# ---- 想加速 + 有槽 ⇒ 真的加速，且槽在掉 ----
	var before := fb.jet_left
	fb.fm.boosting = true
	var active := fb.resolve_jet_gauge(1.0)
	t.ok(active, "有槽时裁决为「可以加速」")
	t.ok(fb.fm.boosting, "裁决把 `fm.boosting` 留在 true")
	t.near(fb.jet_left, before - 1.0, 0.001, "加速 1 秒 ⇒ 槽正好掉 1 秒")

	# ---- 烧到见底 ⇒ 意愿被否掉 ----
	#
	# ⚠️ **槽要先真的清零**：上一版设成 0.05 再裁决 —— 而"还剩 0.05 s"仍然算**有槽**，
	# 裁决照旧放行（这是对的行为：最后一滴也要能用），但那不是这条断言要测的东西。
	# 正确的复现是 `jet_left = 0.0`。
	fb.jet_left = 0.0
	fb.fm.boosting = true
	var active2 := fb.resolve_jet_gauge(1.0)
	t.not_ok(active2, "槽见底 ⇒ 裁决为「不能加速」")
	t.not_ok(fb.fm.boosting, "**`fm.boosting` 被改写成 false**（这就是「时间限制」）")
	t.ok(fb.jet_empty(), "`jet_empty()` 为真（HUD 用它闪红）")
	t.near(fb.jet_left, 0.0, 0.001, "槽不会变成负数")

	# ---- 还剩一点点也必须能用（最后一滴不给用是最气人的那种失败）----
	fb.jet_left = 0.04
	fb.fm.boosting = true
	t.ok(fb.resolve_jet_gauge(1.0), "还剩 0.04 s ⇒ **仍然放行**（最后一滴能用）")
	t.near(fb.jet_left, 0.0, 0.001, "这一帧刚好烧完")

	# ---- 不加速时回充 ----
	fb.jet_left = 0.0
	fb.fm.boosting = false
	fb.resolve_jet_gauge(fb.profile.jet_recharge * 0.5)
	t.near(fb.jet_ratio(), 0.5, 0.02, "不加速半个回充周期 ⇒ 回一半")
	# 回满之后不会溢出
	fb.resolve_jet_gauge(fb.profile.jet_recharge * 2.0)
	t.near(fb.jet_left, fb.profile.jet_seconds, 0.001, "回充不会超过满槽")

	# ---- **加速期间不回充**（否则续航被拉长，等于槽更大）----
	fb.jet_left = 1.0
	fb.fm.boosting = true
	fb.resolve_jet_gauge(0.5)
	t.near(fb.jet_left, 0.5, 0.001, "加速期间**只出不进**")

	c.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 2 算术一致性

static func _math(t: T) -> void:
	# ---- ① 出击点必须在竞技场内 ----
	t.lt(WorldBuilder.SPAWN_RADIUS, WorldBuilder.ARENA_RADIUS,
		"出击点（%.0f m）在竞技场（%.0f m）之内 —— 否则一出生就被回界推着走"
			% [WorldBuilder.SPAWN_RADIUS, WorldBuilder.ARENA_RADIUS])
	# 留出余量：贴着边界不好打
	t.lt(WorldBuilder.SPAWN_RADIUS, WorldBuilder.ARENA_RADIUS * 0.75,
		"出击点还留了余量（< 竞技场 ×0.75）")

	# ---- ② "先飞 N 秒才能到战场" ----
	# 判据用**量产机里最快的那台**（梅萨）全程按死加速的理想值 ——
	# 实际会被槽限制得更久，所以这是**下限**。
	#
	# ⚠️ **这条契约已经因为"世界尺度变了"搬过三次家**（每一次都是主动改，不是绕开）：
	#   第二十二轮：地图 ×2.3、机体速度不动 ⇒ 20.7 km ÷ 579 = **35.8 s**，判据 30~45 s；
	#   2026-09-25 第一次提速（×1.5）：20.7 km ÷ 869 = **23.8 s**，下限搬到 20 s；
	#   2026-09-25 第二次提速（再 ×1.6，累计 ×2.4）：20.7 km ÷ **1391** = **14.9 s**，
	#     下限搬到这里：**13 s**。
	# 换句话说：**"地图更大"与"机体更快"是一对反向的力量**，开局赶路时间是两者的商 ——
	# 放大 2.3 倍让它多飞 20 秒，两轮提速又把它吃回去。
	# **上限 45 s 一个字不动**：它守的是另一件事（"再长就该考虑挪出击点或加机体速度"），
	# 而"变得太短"从来不是它要拦的东西 —— 那是下限的活。
	var best := 0.0
	var best_name := ""
	for id: int in [SuitProfile.Id.MESSER_M01, SuitProfile.Id.GUSTAV00]:
		var v: float = SuitProfile.by_id(id).player_boost_speed()
		if v > best:
			best = v
			best_name = SuitProfile.by_id(id).display_name
	var ideal := WorldBuilder.SPAWN_RADIUS / best
	t.gt(ideal, 13.0, "最快量产机（%s）全力飞也要 > 13 s（实测下限 %.1f s）" % [best_name, ideal])
	t.lt(ideal, 45.0, "但不到 45 s（上限：再长就该考虑挪出击点或加机体速度了）")

	# ---- ③ **必须靠踏板**：槽一口气冲不到那么远 ----
	#
	# ⚠️ 这条里其实有**两条不同强度的契约**，别把它们混为一谈：
	#   (a) `reach < SPAWN_RADIUS` —— **核心守卫**：槽一口气覆盖不了全程，
	#       所以"必须依靠飞行踏板"成立。它**一个字都没搬过家**，两轮提速后仍然成立
	#      （11.1 km < 20.7 km）。
	#   (b) `reach / SPAWN_RADIUS < 上限` —— 只是"明显短于"的**粗估**。它对
	#       "速度 / 槽时长 / 地图"三个量都敏感，所以会随提速一路漂高：
	#       71%（原始）→ 22%（地图 ×2.3）→ 34%（提速 ×1.5）→ **54%（提速 ×2.4）**。
	#       从 0.35 搬到 **0.60** 的理由是 (a) **没有被破**，而不是"红了就放宽"——
	#       若哪一天 (a) 红了，那才是真的把"必须靠踏板"做没了，届时要动的是
	#       `jet_seconds` 或出击点，**不能再搬这个数**。
	for id: int in [SuitProfile.Id.MESSER_M01, SuitProfile.Id.GUSTAV00]:
		var p := SuitProfile.by_id(id)
		t.ok(p.has_jet_gauge, "%s 有槽（判据用得到）" % p.display_name)
		var reach: float = p.jet_seconds * p.player_boost_speed()
		t.lt(reach, WorldBuilder.SPAWN_RADIUS,
			"%s 一口气冲 %.1f km < 出击距离 %.1f km ⇒ **自己飞不到**"
				% [p.display_name, reach / 1000.0, WorldBuilder.SPAWN_RADIUS / 1000.0])
		# 但也不能太短：太短就"骑了板也赶不到"，变成纯罚人。
		#
		# ⚠️ 下限从 35% 降到 **20%**（第二十二轮）：地图放大 2.3 倍而槽时长没动，
		# 槽程占比从 **71% 掉到 22%**。之后两轮提速各自把它抬一档（**方向是"升"**，
		# 别把它当成"又被放大了"）。下限仍然要守住：真要掉到 20% 以下，
		# 那就是"没踏板完全打不了"。
		# 实测值（不是估的）：梅萨 1391 m/s × 8 s = 11.1 km、古斯塔夫 1285 × 8 = 10.3 km，
		# 出击 20.7 km ⇒ 53.8% / 49.7%。
		t.gt(reach, WorldBuilder.SPAWN_RADIUS * 0.20,
			"%s 的槽也不能太短（一口气至少覆盖 20%% 的路程，否则纯罚人）" % p.display_name)
		# ⚠️ 上限的沿革写在上面那段（(a) 与 (b) 的区别）。
		# 写死成断言是为了**逼它现身**：占比每变一次，都必须有人来这一行确认
		# "核心守卫还在"，而不是让"必须靠踏板"这句话悄悄失效。
		t.lt(reach / WorldBuilder.SPAWN_RADIUS, 0.60,
			"%s 的槽程占出击距离不到 60%%（提速后约 %.0f%%）—— 仍然只能当一次冲刺用"
				% [p.display_name, reach / WorldBuilder.SPAWN_RADIUS * 100.0])

	# ---- ③b **城市图**要单独算一遍（2026-09-28 起出击半径**按图给**）----
	#
	# ⚠️⚠️ 上面 ② 与 ③ 读的都是全局 `SPAWN_RADIUS`（46 575），而它从四块岛那一轮起
	# **只是非城市图的值**：城市图走 `WorldBuilder.CITY_SHAPE[·].spawn_r`，
	# 奥恩贝利是 **90 000 m**（理由：出生点必须落在 82…96 km 的丘陵环带里，
	# 那是用户"出生点在丘陵上面"这条要求的直接后果；详见 `match_spawn_radius()`）。
	#
	# ⇒ 不补这一段，上面那两条会**绿着放过**一个翻倍的赶路时间 ——
	#   典型的"断言还在、但已经覆盖不到目标"。
	#
	# ## ⚠️ 城市图的**两条契约都被这一次搬家顶破了**，这是主动记账、不是放宽
	# | 契约 | 非城市图 | 城市图 | 处置 |
	# |---|---|---|---|
	# | 上限（"再长就该挪出击点"） | 45 s | **65 s** | 城市图单独给 **75 s** 上界 |
	# | 槽程占比下限（"没踏板也能打"） | 20% | **12%** | 城市图单独给 **10%** 下界 |
	#
	# 为什么**不改 45 s / 20% 那两条**：它们守的是非城市图（沙漠 / 海洋 / 岛屿），
	# 那些图的出生环没有被丘陵挤走，"45 s / 20%" 仍然是对的口径。
	# 而城市图为什么可以破：出生环的位置**不是**可以自由调的参数 ——
	# 它由"必须在丘陵环带里"倒推出来；要把它拉回来就得先满足"丘陵覆盖出生环"，
	# 而丘陵之所以外移到 82 km，是因为 40…54 km 那一圈被四块岛占掉了（本轮拍板）。
	# ⇒ 真要动，动的是**丘陵位置**（那是一整轮的量级），不是这里两个阈值。
	#
	# ⚠️ 核心守卫 (a) 在城市图上**更宽松**（11.1 km ≪ 90 km）⇒ "必须靠踏板"没被破。
	var city_r := float(WorldBuilder.CITY_SHAPE[MapDef.CityLayout.OENBELLI].spawn_r)
	var city_ideal := city_r / best
	print("[travel] 出击半径：非城市 %.0f m → 最快量产机 %.1f s；"
		% [WorldBuilder.SPAWN_RADIUS, ideal]
		+ "城市（奥恩贝利） %.0f m → %.1f s" % [city_r, city_ideal])
	t.gt(city_ideal, 13.0, "城市图的开局赶路 %.1f s > 13 s（没有变成「贴脸开打」）" % city_ideal)
	t.lt(city_ideal, 75.0,
		("城市图的开局赶路 %.1f s < 75 s（**这个上界是城市图专属的**，"
			+ "非城市图仍是 45 s；沿革见上面那段）") % city_ideal)
	for id: int in [SuitProfile.Id.MESSER_M01, SuitProfile.Id.GUSTAV00]:
		var pc := SuitProfile.by_id(id)
		var reach_c: float = pc.jet_seconds * pc.player_boost_speed()
		t.lt(reach_c, city_r,
			"%s 一口气 %.1f km < 城市出击距离 %.1f km ⇒ 城市图上照样**必须靠踏板**"
				% [pc.display_name, reach_c / 1000.0, city_r / 1000.0])
		t.gt(reach_c / city_r, 0.10,
			("%s 的槽程占城市出击距离 %.1f%% > 10%%（城市图的下限**刻意低于**"
				+ "非城市图的 20%%：出生环被丘陵挤到 90 km 是主动的，沿革见上）")
				% [pc.display_name, reach_c / city_r * 100.0])

	# ---- ④ 踏板必须**不烧槽**（否则骑板赶路这条也失效）----
	# 踏板给的是 `RIDE_THROTTLE_RESPONSE`（加速响应），而槽只在**按加速**时掉 ——
	# 所以"骑板 + 不按加速"应当比"不骑板 + 不按加速"更快，这段路程因此更短。
	t.gt(FlightPedal.RIDE_THROTTLE_RESPONSE, 1.0,
		"踏板给的是加速响应（>1.0）——它**不消耗燃料槽**")

	# ---- ⑤ 训练模式的靶场不受影响 ----
	t.lt(WorldBuilder.TRAINING_PATROL_RADIUS, WorldBuilder.ARENA_RADIUS,
		"训练靶场半径仍在竞技场内")
	# ⚠️ **靶机必须落在锁定范围内**（这条不变量是第二十二轮那个 bug 留下的）。
	#
	# 玩家出生在**圆心**（`main.spawn_training()`），所以"巡逻半径 > 锁定范围"
	# 就等于**出生点一架都锁不上** —— 训练模式练不了锁定，而它唯一的目的就是练这个。
	#
	# ⚠️ **这一条的两端在 2026-09-21 一起被按 `MAP_SCALE` 放大了**。
	#
	# 第二十二轮曾经把 `TRAINING_PATROL_RADIUS` 压回 5200（不放大）来保住这条不变量，
	# 而代价是 `suite_worldscale` 的「训练靶场比例一致」那条一直红 —— 两个不变量打架。
	# 拍板取 (b) 之后：巡逻半径 5200→11960、`seeker_range` 9000→20700，
	# 两边同倍放大，这条与那条**同时**成立，而且靶机距离/锁定距离的比值没变（≈0.578）。
	var seeker := LockOnSystem.new().seeker_range
	t.lt(WorldBuilder.TRAINING_PATROL_RADIUS, seeker,
		"靶机巡逻半径（%.0f m）**小于锁定范围（%.0f m）** —— 否则出生点一架都锁不上"
			% [WorldBuilder.TRAINING_PATROL_RADIUS, seeker])


# ---------------------------------------------------------------- 3 谁有槽

static func _who(t: T) -> void:
	# 用户："只有量产机有"。
	for id: int in [SuitProfile.Id.MESSER_M01, SuitProfile.Id.GUSTAV00]:
		t.ok(SuitProfile.by_id(id).has_jet_gauge,
			"%s 有燃料槽（量产机）" % SuitProfile.by_id(id).display_name)
	# ACE 机没有槽 —— 照旧想加速多久就多久
	for id: int in [SuitProfile.Id.XI, SuitProfile.Id.PENELOPE, SuitProfile.Id.ARIZEUS]:
		t.not_ok(SuitProfile.by_id(id).has_jet_gauge,
			"%s **没有**燃料槽（ACE 机不受限）" % SuitProfile.by_id(id).display_name)
	# 靶机版古斯塔夫共用基座 ⇒ 也有槽（训练模式里靶机会偶尔加速，无害）
	t.ok(SuitProfile.gustav00().has_jet_gauge, "靶机版古斯塔夫也有槽（共用基座）")

	# 运行期：ACE 机的槽裁决应当**完全放行**
	var fb := FlightBody.new()
	fb.profile = SuitProfile.xi()
	t.not_ok(fb.has_jet_gauge(), "柯西没有槽")
	t.near(fb.jet_ratio(), 1.0, 0.001, "没槽的机体 `jet_ratio()` 恒 1.0（HUD 好画）")
	fb.fm.boosting = true
	t.ok(fb.resolve_jet_gauge(10.0), "ACE 机加速 10 秒也不会被否掉")
	t.ok(fb.fm.boosting, "`fm.boosting` 保持 true")
	fb.free()


# ---------------------------------------------------------------- 4 踏板的取舍

static func _tradeoff(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var a := _make(c, "TradeA", 0, SuitProfile.messer_m01())
	await host.get_tree().physics_frame
	a.configure_pedal()
	await host.get_tree().physics_frame
	t.ok(a.has_pedal(), "骑上了板（前置条件）")

	# ---- 骑板**不再**禁军刀（第十九轮推翻了那条）----
	t.not_ok(a.pedal_restricts_melee(), "骑板不限制军刀（第十九轮改的）")
	t.ok(a.try_saber(null), "骑板时**挥得出**光束军刀")
	a.abort_saber()

	# ---- 但**仍然不能悬停**：这是踏板剩下的硬代价 ----
	#
	# 判据走真实路径 `_apply_flight()`（不是直接看常量）：
	# 骑板时哪怕把 `fm.hovering` 设成 true，跑一帧之后也必须被按回 false。
	a.fm.hovering = true
	a.control_input = Vector3.ZERO
	a._apply_flight(1.0 / 60.0)
	t.not_ok(a.fm.hovering, "**骑板时悬停被强制关掉**（走 `_apply_flight` 真实路径）")

	# 对照：脱板之后悬停应当能立住
	a.release_pedal()
	await host.get_tree().physics_frame
	t.not_ok(a.has_pedal(), "脱板了")
	a.fm.hovering = true
	a._apply_flight(1.0 / 60.0)
	t.ok(a.fm.hovering, "（对照）脱板之后悬停可以立住")

	c.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 5 辅助驾驶下的槽

## 辅助驾驶模式下的槽（2026-09-30 · 轮 44，用户点名）。
##
## 用户原话：「修改梅萨系列和古斯塔夫的燃料槽：**在辅助驾驶模式下也能恢复**，
## 恢复速度提升至柯西的 80%」。
##
## ## 为什么这一节非有不可
## 辅助驾驶期间 `PlayerController._tick_assist()` **每帧**把 `fm.boosting` 压成 true
##（那段注释写着「替你按住 Shift」）⇒ 旧代码里槽一旦烧空，就永远落在
##「想加速但没槽」那一支、**再也不回充** —— 量产机在辅助模式下等于永久失去加速。
## 这条依赖「`_think()` 先压 boosting、`resolve_jet_gauge()` 后裁决」的**同帧次序**，
## 光读代码看不出来，必须按帧跑出来。
static func _assist(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var fb := _make(c, "JetAssist", 1, SuitProfile.messer_m01())
	await host.get_tree().physics_frame

	# ⚠️ 从这里往下**不许再有 await**：一 await 就放进来一帧 `_physics_process`，
	#    AI 的 `_think()` 会把 `fm.boosting` 改掉，这些断言就测的不是我要测的东西了。
	fb.translate_mode = true
	t.ok(fb.has_jet_gauge(), "前置：梅萨有槽")
	var rate: float = fb.profile.jet_seconds / fb.profile.jet_recharge
	var full: float = fb.profile.jet_seconds

	# ---- ① 辅助模式**不豁免**消耗：槽够就照旧烧 ----
	fb.jet_left = full
	fb.fm.boosting = true
	t.ok(fb.resolve_jet_gauge(1.0), "辅助模式下槽够 ⇒ 照旧放行加力")
	t.near(fb.jet_left, full - 1.0, 0.001, "辅助模式照旧烧槽（这一条没被豁免）")

	# ---- ② 烧空 ⇒ 加力当场被撤下来 ----
	fb.jet_left = 0.0
	fb.fm.boosting = true
	t.not_ok(fb.resolve_jet_gauge(0.05), "辅助模式下槽空 ⇒ 这一帧的加力被否掉")
	t.not_ok(fb.fm.boosting, "`fm.boosting` 被改写成 false（底速当场退巡航极速）")

	# ---- ③ ★ 槽会自己涨回来 —— 本轮要的就是这一条 ----
	#
	# 模拟辅助驾驶的真实节奏：**每一帧**都有 `_tick_assist()` 把 `fm.boosting` 压回 true。
	# 旧代码下这里会一直读到 0（永远不回充）；新代码下它必须涨起来。
	var before := fb.jet_left
	fb.fm.boosting = true
	fb.resolve_jet_gauge(0.1)
	t.gt(fb.jet_left, before, "★ 辅助模式下槽空之后**会自己回充**（旧代码在这里恒为 0）")
	t.near(fb.jet_left, 0.1 * rate, 0.001, "回充速率 = 槽时长 / 回充时间（与手动模式同源）")

	# ---- ④ 滞回门：涨到门限之前，加力**不许**被放行 ----
	#
	# ⚠️ 没有这道门，槽刚过 0 的下一帧就会被放行加力、当场烧光 ⇒ 每 0.1 s 一次脉冲
	#（引擎音、尾焰、以及一切读 `jet_active` 的特效全跟着闪）。
	var door: float = full * FlightBody.JET_ASSIST_REARM
	fb.jet_left = 0.0
	fb.fm.boosting = true
	fb.resolve_jet_gauge(0.05)                      # 槽空 ⇒ 进「等回充」闩
	fb.jet_left = door - 0.1
	fb.fm.boosting = true
	t.not_ok(fb.resolve_jet_gauge(0.01),
		"槽还没回到门限（%.0f%%）⇒ 加力**仍然被否**（这就是防抖）"
			% (FlightBody.JET_ASSIST_REARM * 100.0))
	# 跨过门限 ⇒ 解锁。
	# ⚠️ **解锁那一帧仍不给加力**：门限是在回充分支里判的，判完就 return 了；
	#    加力从**下一个物理帧**起回来（差 16.7 ms，无感）。所以这条按两帧写。
	fb.jet_left = door + 0.1
	fb.fm.boosting = true
	fb.resolve_jet_gauge(0.01)                      # 这一帧清闩
	t.not_ok(fb._jet_assist_recover, "槽越过门限 ⇒ 闩被清掉")
	fb.fm.boosting = true
	t.ok(fb.resolve_jet_gauge(0.01), "下一帧起加力**重新放行**（槽空之后是能回来的）")

	# ---- ⑤ 对照：**手动模式**一个字没动 ----
	#
	# 「槽空就真的没加力、要松手才回充」是这一族机体的核心代价，也是「必须靠踏板」
	# 成立的原因。用户要的是**补回辅助模式本来不可能有的那个松手机会**，不是抹掉它。
	fb.translate_mode = false
	fb.jet_left = 0.0
	fb.fm.boosting = true
	fb.resolve_jet_gauge(0.1)
	t.near(fb.jet_left, 0.0, 0.001,
		"（对照）手动模式槽空 + 一直按着加速 ⇒ **不回充**（原行为没动）")
	fb.fm.boosting = false
	fb.resolve_jet_gauge(0.1)
	t.gt(fb.jet_left, 0.0, "（对照）手动模式松手 ⇒ 照旧回充")

	# ---- ⑥ 口径对账：回充 = 柯西冲刺条速率的 80% ----
	#
	# ⚠️ `SuitProfile.XI_DASH_REGEN` 是**抄**的一份（数据层不能反向引用 `FlightBody`，
	# 会成环）⇒ 必须有一条断言把两者钉在一起，否则两边分家时回充会**静默**变成另一个数。
	t.near(SuitProfile.XI_DASH_REGEN, FlightBody.QB_CHARGE_REGEN, 1e-6,
		"数据层那份「柯西冲刺条速率」与飞行层真源一致（%.2f /s）"
			% FlightBody.QB_CHARGE_REGEN)
	var pm := SuitProfile.messer_m01()
	t.near(pm.jet_recharge,
		1.0 / (SuitProfile.JET_RECHARGE_VS_XI * FlightBody.QB_CHARGE_REGEN), 1e-6,
		"梅萨的槽回满 %.4f s = 柯西条（%.2f/s）的 %d%% —— 用户 2026-09-30 的口径"
			% [pm.jet_recharge, FlightBody.QB_CHARGE_REGEN,
				int(SuitProfile.JET_RECHARGE_VS_XI * 100.0)])
	t.near(pm.jet_recharge, 5.6818, 0.001, "落成数就是 5.68 s（26 s → 5.68 s 是主动改平衡）")
	# 用户点名的**两族**一起吃这个值（类默认值是它们唯一的参数来源）
	for g: SuitProfile in [SuitProfile.gustav00(), SuitProfile.gustav00_armed(),
		SuitProfile.messer_cmd(), SuitProfile.messer_f01()]:
		t.near(g.jet_recharge, pm.jet_recharge, 1e-9,
			"%s 的回充与梅萨一致（同吃类默认值）" % g.display_name)
	# 槽时长**没动** —— 那三条算术守卫守的是「必须靠踏板」，这一轮不碰它
	t.near(pm.jet_seconds, 8.0, 0.001, "梅萨槽时长仍是 8 s（本轮只改回充）")
	t.near(SuitProfile.gustav00().jet_seconds, 8.0, 0.001, "古斯塔夫槽时长同上")

	c.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 工具

static func _make(parent: Node3D, node_name: String, team: int,
		p: SuitProfile = null) -> BanditAI:
	var fb := BanditAI.new()
	fb.name = node_name
	fb.team = team
	fb.profile = p if p != null else SuitProfile.xi()
	fb.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	fb.projectile_container = parent
	parent.add_child(fb)
	fb.global_position = Vector3(0.0, 3200.0, 0.0)
	return fb
