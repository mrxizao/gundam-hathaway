extends RefCounted
## **低地球轨道**（`Id.LEO` / `Terrain.SPACE`）—— 剧情模式轮 B2 的新地图。
##
## ## 这一套守的是哪件事
## 老板原话：「**接货柯西那一关在近地轨道，做一个宇宙情况下的新地图**」。
## 它落地成工程里**第一张没有地表的地图**，于是有一件事必须被守住：
## **"底下有没有东西"从一个隐含前提变成一个显式的位**（`MapDef.has_ground`），
## 而不是在三处各写一个 `if map.id == Id.LEO`。
##
## ## 三件最容易静默出事的事，各有一组断言
## | # | 事 | 静默失败长什么样 |
## |---|---|---|
## | 1 | `_map_stage_terrain()` 的 `match` **有 `_` 兜底（建太平洋群岛）** | 轨道图上有一片海和几座岛。**不报错、不告警**，探针也只表现为"怎么这么蓝" |
## | 2 | `cloud_density = 0` **建不出 0 朵云**（`_build_clouds()` 把密度夹到 ≥ 0.05） | 真空里凭空挂着几朵云 |
## | 3 | `_build_ground_plane()` **顺手加一层扁平碰撞** | 无地面图上多出一层看不见的地板，"没有地面"当场变成假话 |
##
## ## ★ 一条**行为化**的判据（比读配置强得多）
## `_hits_down()`：在真世界里从出生高度**正下方**的几个点打 WORLD 层射线。
## 轨道图**必须全打空**；而**阳性对照**是一张真的铺了兜底碰撞的地表图
##（沙漠 / 城市）—— 它必须命中，否则说明这条判据本身是坏的，而不是"轨道图干净"。
##
## ## ⚠️ 首跑实测纠正了一个想当然（本轮第二个值钱的发现）
## 原以为"五张地表图底下都有兜底碰撞"。实测**太平洋图底下什么都没有**：
## `_build_islands()` 一个碰撞体都不建，它靠 `FlightBody.CRASH_ALTITUDE = 24 m`
## 判"撞海"。⇒ `has_ground` 是一个**语义**位（"这张图有没有『地表』这个概念"），
## 它**不等于**"物理世界底下有没有碰撞体"。这两件事别混。
## ⇒ 判据因此拆成「有地坪的图命中」+「轨道图四个采样点全空」两半，
##   而不是最初写的"五张图全命中"。
##
## ## ⚠️ 按**主题命名**，不占轮次号
## 本仓库有并行会话，两侧都按轮次占号时撞过一次文件（`suite_round22` 被整个覆盖）。
##
## ## ⚠️ 这套的 `run(t, host)` 需要 host + 有 await
## 第 3 节要真建一个 `WorldBuilder` 进树（物理世界 + `await physics_frame`）。

const SPACE := "SpaceMap / 低地球轨道"

static func run(t: T, host: Node) -> void:
	_data(t)
	_tod(t)
	await _build(t, host)
	_no_ground(t)
	await _orbit_floor(t, host)
	_wiring(t)


# ============================================================ ① 数据：这张图本身


static func _data(t: T) -> void:
	t.suite(SPACE + " / 地图数据")

	var m := MapDef.leo()
	t.eq(m.id, MapDef.Id.LEO, "id 是 LEO")
	t.eq(m.code, "LEO", "代号 LEO")
	t.eq(m.name_cn, "低地球轨道", "中文名（老板用词是「近地轨道」，地图名取通用缩写那套）")
	t.eq(m.terrain, MapDef.Terrain.SPACE, "地表是 SPACE")
	t.eq(m.has_ground, false, "★ 底下没有东西（本图存在的理由）")
	t.eq(m.cloud_density, 0.0, "★ 云量为 0（轨道上没有云）")
	t.ok(m.time_of_day != null, "有时段")
	t.eq(m.time_of_day.preset, TimeOfDay.Preset.SPACE, "……而且用的是新那一档")
	t.ok(m.blurb.contains("再入"), "简介说的是这件玩法（贴再入线）")
	t.ok(m.accent.b > m.accent.r, "强调色偏冷（冷白偏青）")
	t.lt(m.ground_swatch.get_luminance(), 0.06, "色板近黑（真空，不是任何地表色）")

	# ---- 枚举与登记 ----
	t.eq(MapDef.Id.LEO, 5, "Id 枚举加在末尾（既有五张图的编号一个都没动）")
	t.eq(MapDef.Terrain.SPACE, 4, "Terrain 枚举也只加在末尾")
	t.ok(MapDef.all_maps().has(MapDef.Id.LEO), "进全部地图列表（注册）")
	t.eq(MapDef.all_maps().size(), 6, "一共六张图（五张对战/剧情 + 靶场）")
	# ⚠️ **新图必须进对战列表** —— 这不是"顺手放的"，是老板已经拍过板的口径：
	# 达沃那一轮 1.3 设计书原写"新图先不进对战列表、等剧情验证过再开"，
	# 被老板推翻（"剧情模式还没做，不进对战列表就等于这张图根本看不到"）。
	# 轨道图同理：M03 在轮 C 才通，不进来它在轮 B2 就只剩探针能看见。
	t.ok(MapDef.versus_maps().has(MapDef.Id.LEO), "★ 进 1v1/编队战的地图列表（否则玩家根本选不到）")
	t.eq(MapDef.versus_maps().size(), 5, "对战可选五张")
	t.ok(not MapDef.versus_maps().has(MapDef.Id.RANGE), "靶场仍不在对战列表里（既有约定）")

	# ---- all_maps 的 id 不重复 + by_id 往返 ----
	var seen := {}
	for i: int in MapDef.all_maps():
		t.not_ok(seen.has(i), "地图 id %d 不重复" % i)
		seen[i] = true
		t.eq(MapDef.by_id(i).id, i, "by_id(%d) 往返回同一个 id" % i)

	# ---- 五张旧图**一个字都没被这一轮动过** ----
	# 这是本轮"零回归"的正面判据：新字段的默认值必须让旧图原样。
	for id: int in [MapDef.Id.PACIFIC, MapDef.Id.ULURU, MapDef.Id.RANGE,
			MapDef.Id.OENBELLI, MapDef.Id.DAVAO]:
		var old := MapDef.by_id(id)
		t.eq(old.has_ground, true, "%s：has_ground 仍是 true（默认值）" % old.code)
		# ★ 2026-09-29 新增的三个字段也必须**逐位保持默认 0** ——
		# 否则地表图会开始往外派生轨道高度（`match_player_alt()` 之外还会有别人读它）。
		t.near(old.orbit_alt, 0.0, 0.001, "%s：orbit_alt 仍是 0（这张图没有「轨道」这回事）" % old.code)
		t.near(old.body_radius, 0.0, 0.001, "%s：body_radius 仍是 0（底下不建天体）" % old.code)
		t.near(old.reentry_alt, 0.0, 0.001, "%s：reentry_alt 仍是 0（不适用）" % old.code)
		t.eq(old.time_of_day.ground_blend, GROUND_BLEND_DEFAULT,
			"%s：ground_blend 仍是 %.2f（= sky.gdshader 的默认值）"
			% [old.code, GROUND_BLEND_DEFAULT])
	t.eq(GROUND_BLEND_DEFAULT, 0.18, "……而且那个默认值就是 shader 里的原值")

	# ---- ★ 天体参数（2026-09-29：老板"近地轨道高度应该和现实高度一致"）----
	#
	# 这三个数**就是**那张图的物理设定。`WorldBuilder` 里有一组同名的编译期常量
	#（下面一整节建图代码都按它们派生），两边是**同一个源的两个副本** ⇒
	# 一致性由本节末尾那五条"跨模块"断言钉着。
	t.near(m.orbit_alt, 550000.0, 0.001, "★ 轨道高度 = 550 km（星链壳层高度，老板从三档里挑的）")
	t.near(m.body_radius, 6371000.0, 0.001, "★ 下方天体半径 = 6 371 km（地球平均半径）")
	t.near(m.reentry_alt, 100000.0, 0.001, "★ 再入线 = 100 km（卡门线 = 国际公认的大气层顶）")
	t.gt(m.reentry_alt, 0.0, "再入线在天体表面**之上**（不然「再入」这件事没有发生的地方）")
	t.lt(m.reentry_alt, m.orbit_alt, "★ 再入线在战斗高度**下面**（贴线飞这件事才有意义）")

	# ---- ★★ 跨模块：五个副本必须一起动 ----
	#
	# ⚠️ 这一组的形状与本套件既有那几条"跨模块"断言一致（`SPACE_POD_POS` ↔ `ORBIT_ALT`
	# 那一回就是这么抓出来的：两个数各自看着都对，合起来是"目标球飘在 97 km 外"）。
	t.near(m.orbit_alt, WorldBuilder.SPACE_ORBIT_ALT, 0.001,
		"★ 跨模块：`MapDef.leo().orbit_alt` == `WorldBuilder.SPACE_ORBIT_ALT`")
	t.near(m.body_radius, WorldBuilder.SPACE_BODY_R, 0.001,
		"★ 跨模块：`body_radius` == `WorldBuilder.SPACE_BODY_R`")
	t.near(m.reentry_alt, WorldBuilder.SPACE_REENTRY_ALT, 0.001,
		"★ 跨模块：`reentry_alt` == `WorldBuilder.SPACE_REENTRY_ALT`")
	t.near(MissionScript.ORBIT_ALT, WorldBuilder.SPACE_ORBIT_ALT, 0.001,
		"★ 跨模块：`MissionScript.ORBIT_ALT` == 轨道高度（M03 的目标球不能飘到空处）")
	t.near(MissionScript.REENTRY_ALT, WorldBuilder.SPACE_REENTRY_ALT, 0.001,
		"★ 跨模块：`MissionScript.REENTRY_ALT` == 再入线")


# ============================================================ ② 时段：`TimeOfDay.space()`


static func _tod(t: T) -> void:
	t.suite(SPACE + " / 时段（TimeOfDay.space）")

	var s := TimeOfDay.space()
	t.eq(s.preset, TimeOfDay.Preset.SPACE, "预设编号是新那一档")
	t.ok(s.name_cn != "", "有中文名")
	# ---- ★ 雾必须清零（这是这一档第二重要的一行）----
	t.eq(s.fog_density, 0.0,
		"★ fog_density = 0（那层雾是**大气**雾；轨道上没有大气，不清零整个背景蒙一层灰）")
	t.eq(s.fog_sky_affect, 0.0, "……天空那一路也一起关掉")
	# ---- 临边亮带：本工程新提出来的那一行 ----
	t.gt(s.ground_blend, GROUND_BLEND_DEFAULT,
		"★ ground_blend %.2f > 默认 %.2f（地球临边要读成一条有厚度的亮带）"
			% [s.ground_blend, GROUND_BLEND_DEFAULT])
	t.gt(s.sky_ground.get_luminance(), s.sky_horizon.get_luminance(),
		"地平线以下比地平线亮（往下看是**地球本体**，不是更黑）")
	t.lt(s.sky_zenith.get_luminance(), s.sky_horizon.get_luminance(),
		"天顶比地平线暗（真空黑）")
	t.gt(s.star_amount, 0.5, "星空是主画面（star_amount %.2f）" % s.star_amount)
	t.gt(s.sun_energy, TimeOfDay.night().sun_energy,
		"太阳比月光强（真空里没有大气衰减）")
	# ---- ★ 不登记进 all_presets ----
	t.eq(TimeOfDay.all_presets().size(), 3, "★ 仍是三个时段（Space 不登记）")
	t.not_ok(TimeOfDay.all_presets().has(TimeOfDay.Preset.SPACE),
		"★ Space 不在 all_presets() 里 —— 它是「一张图」，不是一个「时刻」")
	t.eq(TimeOfDay.make(TimeOfDay.Preset.SPACE).preset, TimeOfDay.Preset.DAY,
		"……所以 make(SPACE) 也取不到它（走 day 兜底，这正是「不登记」的语义）")
	# ---- 云的三带数组必须给满 3 项（哪怕本图不建云）----
	t.eq(s.cloud_tints.size(), 3, "cloud_tints 给满 3 项（apply_time_of_day 按创建顺序取）")
	t.eq(s.cloud_shades.size(), 3, "cloud_shades 同上")
	t.eq(s.cloud_tints[0].a, 0.0, "……而且全透明（本图没有云）")
	# ---- 其余四档一个字没动 ----
	for tod: TimeOfDay in [TimeOfDay.day(), TimeOfDay.dusk(), TimeOfDay.night(),
			TimeOfDay.dusk_overcast()]:
		t.eq(tod.ground_blend, GROUND_BLEND_DEFAULT,
			"%s：ground_blend 仍是默认值" % tod.name_cn)
	t.near(MapDef.oenbelli().time_of_day.ambient_sky_contribution, 0.0, 0.0001,
		"奥恩贝利仍是 sky_contribution = 0（那一档靠填充光，没被这一轮碰过）")
	t.near(s.ambient_sky_contribution, 1.0, 0.0001,
		"轨道档的 sky_contribution 也保持 1.0（与其余三档一致）")


# ============================================================ ③ 建图：真建一次


static func _build(t: T, host: Node) -> void:
	t.suite(SPACE + " / 建图（_build_space）")

	var root := Node3D.new()
	root.name = "SpaceMapProbe"
	host.add_child(root)
	var w := WorldBuilder.new()
	root.add_child(w)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame

	# ---- ★ 行为判据：SPACE **没有**落进 `_` 兜底 ----
	# `_map_stage_terrain()` 的 `_` 分支是 `_build_islands()`。落进去的话
	# 这里会长出 `Islands` 与海面 —— 而那是**静默**的。
	await _apply(w, host, MapDef.leo())
	var terrain: Node = w.get("_terrain_root")
	t.ok(terrain != null, "有 `_terrain_root`")
	t.ok(terrain.find_child("Islands", true, false) == null,
		"★ 没有 `Islands`（没落进 `_` 兜底分支）")
	t.ok(w.get("ocean") == null, "★ 没有海面")
	t.ok(terrain.find_child("GroundFar", true, false) == null,
		"★ 没有远景地坪（`_build_ground_plane()` 不调）")
	t.ok(terrain.find_child("GroundCollision", true, false) == null,
		"★★ 没有扁平碰撞地板 ——「没有地面」这件事不能只写在字段里")
	t.gt(float(terrain.get_child_count()), 1.0,
		"地表搭出来了（%d 个节点）—— 不是一片空白" % terrain.get_child_count())

	# ---- 人造物：尺度参照（在轨道图上它不是装饰，是玩法前提）----
	t.ok(terrain.find_child("SpaceDebris", true, false) != null,
		"有碎片带（纯视觉 MultiMesh）")
	# ---- ★ 尺度参照的两条常量（它们不再只是"好看不好看"）----
	#
	# `tools/_b2_leo_shots.gd` 量过"飞行 4 km 画面变多少像素"：**噪声底为 0**，
	# 而 **1990** 个变化像素里有约 **1747** 来自碎片带（大件残骸只占 ~243）——
	# 也就是说"读得出我在动"这件事**主要压在这 48 件碎片上**。
	# ⇒ 改这两个数就是改玩法读数，不是改装饰 ⇒ 在这里钉住，改的人必须有意。
	t.eq(WorldBuilder.SPACE_BELT_R, WorldBuilder.SPAWN_RADIUS,
		"★ 碎片带铺在**出击环**上（玩家与敌机出生即在一片碎片里 —— 这是它当参照物的前提）")
	t.eq(WorldBuilder.SPACE_BELT_N, 48,
		"★ 碎片 48 件（均距 6 km）；改这个数会直接改『读得出速度』那条读数")
	t.lt(WorldBuilder.SPACE_DEBRIS_MIN, WorldBuilder.SPACE_DEBRIS_MAX, "碎片尺寸有区间")
	t.gt(WorldBuilder.SPACE_DEBRIS_MIN, 20.0,
		"最小碎片 > 20 m（再小就只剩一两个像素，不是参照物）")
	t.ok(terrain.find_child("SpaceWreck0", true, false) != null, "有大件残骸")
	t.ok(terrain.find_child("PodBody", true, false) is StaticBody3D,
		"★ 有运输仓**本体**（M03 的目标；真模型挂在一只 `StaticBody3D` 上）")
	t.ok(terrain.find_child("PodHull", true, false) != null,
		"★ 有运输仓**真模型**（Tripo 整件 GLB 实例化出来的 `PodHull`）")
	# ---- 反面：旧的**程序化壳式方筒**必须一件不剩 ----
	#
	# ⚠️ 为什么需要这一条：`world_builder` 里"新件建了、旧件没删"是**静默**的 ——
	# 两份几何同时在场，表现只是"仓看着有两层壳"，而上面两条断言**照样全绿**。
	# 它同时是"批① 真的替掉了旧实现"的证据。
	for old_name in ["PodFloor", "PodRoof", "PodWall0", "PodWall1", "PodAft", "PodNozzle0",
			"PodFairing0", "PodFairing3", "PodRibT", "PodRibS0", "PodBeacon"]:
		t.ok(terrain.find_child(old_name, true, false) == null,
			"旧的程序化件 `%s` 已不在场景里（真件优先，不留两套口径）" % old_name)

	# ---------------- ★★ 运输仓的**尺度**（2026-09-29 轮 46：换成**真模型**）
	#
	# ## 口径演进（三轮，前两轮都在"用错的量逼近需求"）
	#
	# | 轮次 | 用户原话 | 当时的做法 | 结果 |
	# |---|---|---|---|
	# | 轮 44 | 「比柯西本体要大 2.3 倍左右」 | **最长边** × 2.3 | 长 64.4 m、高只有 17.69 m ⇒ 露头露脚 |
	# | 轮 45 | 「**仓要把一架 MS 整个包住**」 | **逐轴** × 2.3（程序化方筒） | 方筒能凑出"逐轴 2.3"，但那是**替身** |
	# | 轮 46 | 给了**真模型**（曲面筒） | **逐轴无解** ⇒ 改问需求本身 | **装得下 + 5% 余量** |
	#
	# ## 为什么"逐轴 × 2.3"在真件上**无解**
	# 等比缩放时三轴倍率必然**相同**；要让圆柱分别达到柯西三轴的 2.3 倍，需要
	# `kx 48.8 / ky 158.3 / kz 110.6` —— 非等比缩放会把筒压成扁鼓、外形崩掉。
	# ⇒ 换个**能直接测**的口径：**柯西的每个顶点是不是都在仓的外表面之内？**
	#（`tools/pod_fit_check.py`：仓轴心向外打 87 120 条射线得外缘半径图
	#  `R(x, theta)`，再拿柯西 `xi_fly.glb` 的 **7948 个真实顶点**逐点查表。）
	#
	# ## ⚠️ 为什么"引擎侧量 AABB"**不能**代替那条判据
	# 筒壁**不是圆的**：中段外缘半径 0.14044 … 0.19907 ⇒ 最窄/最宽 = **0.705**。
	# 柯西 28 m 高**装不进最窄的那个方向**（21.2 m），它是**斜着躺**进去的。
	# 拿 AABB 半宽当"内腔半径"会算出"装不下"的**假红**；
	# 反过来只量外框又只能证明"框够大"，证明不了装得下。
	# ⇒ 逐顶点覆盖那条判据**只能在 Blender 里跑**，引擎侧跑不了。
	# 所以本组改成守**三件在引擎侧真能证伪的事**：
	#   ① **派生链**：`POD_SCALE == POD_FIT_MIN × POD_CLEARANCE × POD_BOOST`（改一处漏一处会红）；
	#   ② **实建几何**：量出来的 AABB ≈ `POD_RAW_BOX × POD_SCALE`
	#     （换模型不改常量、或忘设节点 scale，都会红）；
	#   ③ 用户最初那句「大 2.3 倍左右」现在是一条**推论**：最长边 / 柯西全高 ≥ 2.3。
	# ⚠️ 本仓库的测试运行器**只在失败时打标签**（工程规矩）⇒ 要人复核的读数必须显式打。
	var pod_box := _pods_aabb(terrain)
	var xi_h: float = SuitProfile.xi().target_height
	var xi_box := WorldBuilder.XI_BOX
	var raw_box := WorldBuilder.POD_RAW_BOX
	var want := WorldBuilder.POD_BOX
	var pc := pod_box.position + pod_box.size * 0.5
	print("[运输仓] 模型 AABB %.5f × %.5f × %.5f m   × 缩放 %.3f"
		% [raw_box.x, raw_box.y, raw_box.z, WorldBuilder.POD_SCALE])
	# ⚠️ **机体是躺着放进筒里的**（身高轴沿仓的长轴）—— 站着放**装不下**：
	# 探针实测站着最优覆盖只有 0.9926，要 k = 91.53（躺着的 1.27 倍）。
	# ★ 2026-10-01（轮 58）：仓**立起来了**（`PodHull.rotation_degrees.z = POD_STAND_DEG`）
	# ⇒ 世界 AABB 的 X / Y 两轴**对调**。`want` 是「模型坐标」下的盒子，
	# 而量出来的是「世界坐标」下的 ⇒ X 要拿 `want.y` 比、Y 要拿 `want.x` 比。
	var want_world := Vector3(want.y, want.x, want.z)
	print("[运输仓] 实建 AABB X=%.2f Y=%.2f Z=%.2f m   目标（立起来后 = 模型盒换 X/Y）%.2f × %.2f × %.2f"
		% [pod_box.size.x, pod_box.size.y, pod_box.size.z,
		   want_world.x, want_world.y, want_world.z])
	# ⚠️ **别拿三轴和柯西逐轴同序比** —— 机体是**沿筒的长轴**摆放的，
	# 而筒现在**立着** ⇒ 正确配对应是 仓Y↔柯西身高、仓X↔柯西X、仓Z↔柯西Z。
	# 第一版按同序轴比，打出"仓高只有机体的 **1.098** 倍" —— 读起来像露头露脚，
	# 而它**什么也没说明**（真正决定"装不装得下"的是那条逐顶点覆盖判据）。
	print("[运输仓] 配对（仓立着 · 机体沿筒轴）仓Y/柯西身高 %.3f ｜ 仓X/柯西X %.3f ｜ 仓Z/柯西Z %.3f"
		% [pod_box.size.y / xi_h, pod_box.size.x / xi_box.x, pod_box.size.z / xi_box.z])
	print("[运输仓] 立姿 %.1f°（绕 Z）  摆位滚转 φ = %.1f°   缩放 %.3f = 最小 %.2f × 余量 %.2f × 放大 %.2f"
		% [WorldBuilder.POD_STAND_DEG, WorldBuilder.POD_CARGO_ROLL_DEG, WorldBuilder.POD_SCALE,
		   WorldBuilder.POD_FIT_MIN, WorldBuilder.POD_CLEARANCE, WorldBuilder.POD_BOOST])
	print("[运输仓] 最长边 / 柯西全高 = %.3f   （用户最初口径「大 2.3 倍左右」）"
		% (maxf(maxf(pod_box.size.x, pod_box.size.y), pod_box.size.z) / xi_h))
	print("[运输仓] 世界中心 (%.2f, %.2f, %.2f)   相对场地中心偏移 (%.2f, %.2f, %.2f)"
		% [pc.x, pc.y, pc.z, pc.x - WorldBuilder.SPACE_POD_POS.x,
		   pc.y - WorldBuilder.SPACE_POD_POS.y, pc.z - WorldBuilder.SPACE_POD_POS.z])
	# ---- ① 派生链 ----
	t.near(WorldBuilder.POD_SCALE,
		WorldBuilder.POD_FIT_MIN * WorldBuilder.POD_CLEARANCE * WorldBuilder.POD_BOOST, 0.001,
		"★ 缩放是**派生量**（`POD_SCALE == POD_FIT_MIN × POD_CLEARANCE × POD_BOOST`）")
	# ★ 2026-10-01（轮 58）：老板「柯西运输仓的大小**再调大 180%**」。
	#
	# ⚠️⚠️ 它必须是**独立的第三个因子** —— 手写进 `POD_SCALE`（断了派生链）
	# 或去改 `POD_FIT_MIN`（它的语义是「装得下柯西的**实测最小**缩放」，
	# 下次重跑 `pod_fit_check.py` 会把 2.8 覆盖掉）都是错的，而两者**都不会报错**。
	t.near(WorldBuilder.POD_BOOST, 2.8, 0.0001,
		"★★ 放大系数 = 2.8（= 1 + 180%，老板「再调大 180%」）")
	t.gt(WorldBuilder.POD_BOOST, 1.0, "★ 放大系数 > 1（不许把「调大」写成缩小）")
	t.ok(WorldBuilder.POD_CLEARANCE >= 1.0,
		"★ 余量系数 %.3f ≥ 1（不许在实测最小值上再收紧 —— 探针是 7948 点采样）"
			% WorldBuilder.POD_CLEARANCE)
	t.near(WorldBuilder.POD_FIT_MIN, 71.95, 0.005,
		"★ `POD_FIT_MIN` = `pod_fit_check.py` 实测 71.9219x **向上取整**到 0.05 = 71.95"
			+ "（改它必须连同那支探针一起改；⚠️ 别抄打印出来的 71.92 —— 那只有 0.9996）")
	# ⚠️ 滚转角也是**真源**：k_min 是在"把这个角扫到最优"之后才二分出来的。
	# 随手改它 ⇒ 覆盖面立刻缩水（探针的「滚转窗口」一节量过：工程 k 下并非
	# 每个 φ 都满分）⇒ 出图与判据都会落在一个**没被验证过**的方位上。
	t.near(WorldBuilder.POD_CARGO_ROLL_DEG, 50.0, 0.001,
		"★ 柯西在仓内的摆位滚转角 = 50°（`pod_fit_check.py` 实测最优 φ）")
	# ---- ② 实建几何 ----
	t.near(xi_h, 28.0, 0.001, "柯西游戏内全高 = 28.0 m（本组判据的基准）")
	t.gt(pod_box.size.x, 0.0, "量到了运输仓（AABB %.2f × %.2f × %.2f m）"
		% [pod_box.size.x, pod_box.size.y, pod_box.size.z])
	t.ok(raw_box.x > raw_box.y and raw_box.x > raw_box.z,
		"★ 模型的长轴是 X（筒是**躺着**摆的；转成竖的会立刻红）")
	# 容差 0.05 m：`MeshInstance3D.get_aabb()` 是 float32，且 GLB 导入后 AABB 有量化。
	# 实测这条差值 < 0.01 m，留 5 倍余量。
	t.near(pod_box.size.x, want_world.x, 0.05,
		"★★ X 实建 %.2f == 目标 %.2f m（= 模型 **Y** × 缩放）" % [pod_box.size.x, want_world.x])
	t.near(pod_box.size.y, want_world.y, 0.05,
		"★★ Y 实建 %.2f == 目标 %.2f m（= 模型 **X** × 缩放 ⇒ 筒高 207 m）"
			% [pod_box.size.y, want_world.y])
	t.near(pod_box.size.z, want_world.z, 0.05,
		"★★ Z 实建 %.2f == 模型Z × 缩放 %.2f m（绕 Z 转 ⇒ 这一轴不受影响）"
			% [pod_box.size.z, want_world.z])
	t.gt(pod_box.size.y, pod_box.size.x,
		"★★ 立着 ⇒ 世界 Y（%.2f）> 世界 X（%.2f）—— 这一条在躺着的时候是反的"
			% [pod_box.size.y, pod_box.size.x])
	# 量到实建 AABB **还不够**：节点 scale 忘写时 AABB 恰是模型原尺寸（0.98 m），
	# 上面三条会红；但如果谁把 scale 写进 mesh 顶点、又去改常量，就会两边一起漂。
	# 所以再直接量一次**节点上的缩放**，把"缩放写在节点上"这条设计钉住。
	var hull := terrain.find_child("PodHull", true, false) as Node3D
	t.ok(hull != null, "找得到 `PodHull` 量它的缩放")
	if hull != null:
		t.near(hull.scale.x, WorldBuilder.POD_SCALE, 0.001,
			"★ 缩放写在**节点**上（%.3f）⇒ 与 `POD_SCALE` 同一个真源" % hull.scale.x)
		t.near(hull.scale.y, hull.scale.z, 0.0001, "★ 是**等比**缩放（筒不能被压扁）")
		t.gt(float(_mesh_count(hull)), 0.0,
			"★ `PodHull` 底下真有网格（%d 个 `MeshInstance3D`）" % _mesh_count(hull))
		# ★★ 2026-10-01（轮 58）· R4：仓**立起来**了（长轴从世界 X 转到世界 Y）。
		#
		# ⚠️ 姿态必须写在 `PodHull`（**子**）上：`main._tick_pod_strike()` 每帧写的是
		# `_strike_pod.rotation = Vector3(0, 0, tilt_rad(t))` —— `Node3D.rotation` **整体覆盖**
		# 三个欧拉角 ⇒ 写在父（`PodBody`）上会在起火那一帧被抹掉、
		# **仓瞬间躺回**，而一处都不报错。这条同时钉住了「写在哪个节点上」。
		#
		# 取负号是**实测**定的：局部 +X（推进簇）端外缘半径 0.17450＞
		# 局部 −X（舱门面）端 0.15100（`tools/pod_end_probe.tscn` 实测）
		# ⇒ 大的那一端就是 +X，而老板口径是「圆的面积大的是底面」。
		t.near(fmod(hull.rotation_degrees.z, 360.0), WorldBuilder.POD_STAND_DEG, 0.5,
			"★★ 仓**立着**（`PodHull.rotation_degrees.z` = %.1f°）" % WorldBuilder.POD_STAND_DEG)
		t.ok(absf(hull.rotation_degrees.x) < 0.5 and absf(hull.rotation_degrees.y) < 0.5,
			"★ 只绕 Z 转（X / Y 都是 0）—— 免得「立起来」顺手带出了侧倾")
	# ---- ③ 碰撞（glTF 导入**不带**碰撞，必须自己给）----
	var body := terrain.find_child("PodBody", true, false)
	t.ok(body is StaticBody3D, "`PodBody` 是 `StaticBody3D`")
	if body is StaticBody3D:
		# ⚠️ **别写 `get_child(0)`**：实际子节点顺序是 `PodHull` 在前、碰撞体在后。
		# 靠**类型**去找 —— 将来谁在中间插一个节点，写死下标的版本会静默量错件。
		var shape: CollisionShape3D = null
		for ch in (body as StaticBody3D).get_children():
			if ch is CollisionShape3D:
				shape = ch as CollisionShape3D
				break
		t.ok(shape != null and shape.shape is CylinderShape3D,
			"★★ 碰撞体是一只 `CylinderShape3D`（不加的话玩家**直接穿过去**）")
		if shape != null and shape.shape is CylinderShape3D:
			var cyl := shape.shape as CylinderShape3D
			t.near(cyl.height, raw_box.x * WorldBuilder.POD_SCALE, 0.05,
				"碰撞长 %.2f 由 `POD_RAW_BOX.x × POD_SCALE` 派生（不与外观分家）" % cyl.height)
			t.near(cyl.radius, raw_box.y * 0.5 * WorldBuilder.POD_SCALE, 0.05,
				"碰撞半径 %.2f 同源派生" % cyl.radius)
			# ★★ 2026-10-01（轮 58）：仓立起来之后碰撞圆柱**不再转**。
			# `CylinderShape3D` 的轴是**局部 Y** ⇒ 不转就是世界 Y，恰好就是立起来的长轴。
			# ⚠️ 这一条与外观的立姿是**一对**：只改一边就会出现「贴图立着、碰撞躺着」
			# 而一处都不报错 —— 玩家直接从空处穿过去。
			t.near(fmod(shape.rotation_degrees.z, 180.0), 0.0, 0.5,
				"★★ 圆柱轴不转（局部 Y = 世界 Y = 立起来的长轴）")
	# ---- ④ AABB 包络：**必要条件**，不是充分条件 ----
	#
	# ⚠️ 上面三条 `t.near(AABB, POD_RAW_BOX × POD_SCALE)` 是**派生量自比** ——
	# `POD_SCALE` 一改两边一起动 ⇒ 它们永远绿，抓不到"仓被改小"。
	# 这里补三条与 `POD_SCALE` **无关**的：机体躺着时三轴的包络够不够。
	#
	# ⚠️ 但它们**只是必要条件** —— AABB 逐轴包住机体 **不等于**装得下
	#（筒壁不是圆的、机体是斜着躺进去的）。真正的判据只有逐顶点覆盖那一条，
	# 它在 `tools/pod_fit_check.py` 里。这几条的价值是**便宜**：
	# 换模型、把仓改小一半之类，它们立刻红。
	#
	# 配对（仓立着 · 机体沿筒的长轴）：仓Y ↔ 柯西身高，仓X / 仓Z ↔ 柯西的 X 与 Z。
	#
	# ★ 实测（负对照 N1，把 `POD_FIT_MIN` 退回「最长边 x 2.3」口径 k = 65.73）：
	#   **这三条 + 上面三条派生自比 全部绿**（仓 64.40 x 26.75 x 29.60 仍然逐轴包住
	#   躺着的柯西），整组只有 `POD_FIT_MIN` 那条 latch 变红 ⇒ **"装得下"这件事
	#   在引擎侧没有便宜的判据**，别把这几条当成它的替代品。
	t.ok(pod_box.size.y >= xi_h,
		"★ 仓高（世界Y）%.2f ≥ 柯西身高 %.2f（机体沿筒的长轴，筒立着 ⇒ 走世界 Y）"
			% [pod_box.size.y, xi_h])
	t.ok(pod_box.size.x >= maxf(xi_box.x, xi_box.z),
		"★ 仓X %.2f ≥ 柯西截面 %.2f" % [pod_box.size.x, maxf(xi_box.x, xi_box.z)])
	t.ok(pod_box.size.z >= maxf(xi_box.x, xi_box.z),
		"★ 仓Z %.2f ≥ 柯西截面 %.2f" % [pod_box.size.z, maxf(xi_box.x, xi_box.z)])
	# ---- ⑤ 用户最初口径作为**推论** ----
	# ★ 「最长边」在立起来之后是**世界 Y**（模型的 X）⇒ 不能再写死 `size.x`。
	var pod_long := maxf(maxf(pod_box.size.x, pod_box.size.y), pod_box.size.z)
	t.ok(pod_long / xi_h >= 2.3,
		"★★ 最长边 / 柯西全高 = %.3f ≥ 2.3（用户最初那句「大 2.3 倍左右」现在是被推出来的）"
			% (pod_long / xi_h))

	# ---------------- ★★ HUD 运输仓信标：**可显示，但不可被攻击**
	#（2026-09-29 用户：「做一个锁定显示功能（类似正常的索敌系统，但是不能被攻击）」）
	#
	# 本组钉的是**三条结构性证据**，而不是"我加了个开关"：
	#   ① 在 `pod_target` 组 —— HUD 靠它找到信标；
	#   ② **不在 `units` 组** —— `Game.live_hostiles_of()` 的建表源就是 `units`，
	#      进了组就等于"进锁定候选表" ⇒ AI 会咬它、玩家会锁它，而那正是用户
	#      明确要排除的（「不能被攻击」）；
	#   ③ **没有 `take_damage` / `is_hostile_to`** —— `Projectile` 命中时优先找
	#      "能受伤的机体"（`has_method("take_damage")`），没有它就落进"世界几何"
	#      分支 ⇒ 撞得上、打不掉。
	#
	# ⚠️ 三条缺一条就会漏：只断 ① 的话，「锁得上但能打掉」照样绿。
	var tag := terrain.find_child("CargoTarget", true, false)
	t.ok(tag != null, "★ 有 HUD 运输仓信标（`CargoTarget`）")
	if tag != null:
		t.ok(tag.is_in_group("pod_target"), "★ 信标在 `pod_target` 组（HUD 靠它找到）")
		t.ok(not tag.is_in_group("units"),
			"★★ 信标**不在** `units` 组（⇒ 不进锁定候选表）")
		t.ok(not tag.has_method("take_damage"), "★★ 信标没有 `take_damage`（⇒ 打不掉）")
		t.ok(not tag.has_method("is_hostile_to"),
			"★★ 信标没有 `is_hostile_to`（⇒ 不会被当敌人）")
	var pod_in_units := 0
	for u: Node in host.get_tree().get_nodes_in_group("units"):
		if str(u.name).begins_with("Pod") or str(u.name) == "CargoTarget":
			pod_in_units += 1
	t.eq(pod_in_units, 0, "★★ `units` 组里没有任何运输仓节点（实建场景里数一遍）")
	t.ok(terrain.find_child("*SatBus*", true, false) != null, "有卫星")
	var sat := terrain.find_child("*SatPanel*", true, false)
	t.ok(sat != null, "有太阳能板")
	# 碎片带是**零碰撞**的：它的 parent 必须是 MultiMeshInstance3D 而不是 StaticBody3D。
	var debris := terrain.find_child("SpaceDebris", true, false)
	t.ok(debris is MultiMeshInstance3D, "碎片带走 MultiMesh（一次 draw call）")
	if debris is MultiMeshInstance3D:
		var mm := (debris as MultiMeshInstance3D).multimesh
		t.ok(mm != null, "★ MultiMesh 不为 null（`_city_cube` 只有城市图才建，这里必须自带网格）")
		if mm != null:
			t.gt(float(mm.instance_count), 20.0,
				"碎片件数 %d（够摊成一条带）" % mm.instance_count)
			t.ok(mm.mesh != null, "……而且真的挂着网格")

	# ---- ★ 0 云量 ⇒ 一朵云都不建 ----
	t.eq((w.get("_cloud_root") as Node).get_child_count(), 0,
		"★ 云层数 = 0（`_build_clouds()` 会把密度夹到 0.05，所以必须走「不建」那条路）")
	t.eq((w.get("_cloud_mats") as Array).size(), 0, "`_cloud_mats` 清空")
	t.ok(w.get("_cloud_shade_tex") == null,
		"★ 云影覆盖图也清掉（那是上一次建图烘的，不清会跟着换到新图上）")

	# ---- ★ 行为判据：正下方那几条射线 ----
	#
	# ⚠️ 采样点**必须避开运输仓**：`SPACE_POD_POS` 就在场地中心、高度恰好是
	# `PLAYER_START_ALT`。从仓心往下打，射线是**从盒体内部出发**的，而
	# `intersect_ray` 默认 `hit_from_inside = false` ⇒ 底下就算真有东西也可能读成"打空"。
	# ⇒ 取半径 13 km 的四个正交方向（碎片带 46.6 km、大件残骸 39.1 km、
	#    卫星 25.6 km、运输仓 0 —— 都在它**外面**），那里是空的，读数才干净。
	t.ok(_hits_down(w, _probe_spots()) == false,
		"★ 轨道图：出生高度正下方 4 个采样点 —— **全打空**（底下真的没有东西）")

	# ---- 阳性对照：先证明这条判据**能测到"有东西"** ----
	# 沙漠图（艾尔斯岩）调了 `_build_ground_plane()`，那函数顺手加一层 `GroundCollision`。
	await _apply(w, host, MapDef.uluru())
	t.ok(_hits_down(w, _probe_spots()) == true,
		"阳性对照：艾尔斯岩图同一批射线**命中**（`_build_ground_plane()` 的兜底碰撞）")
	t.ok(terrain.find_child("GroundFar", true, false) != null,
		"阳性对照：远景地坪也在（沙漠图确实调了 `_build_ground_plane()`）")
	t.ok(w.get("ocean") == null, "换到沙漠图：海面被清掉了")
	t.gt(float((w.get("_cloud_root") as Node).get_child_count()), 0.0,
		"对照：云层回来了（换图真的重建了云）")

	# 城市图（达沃）同理 —— 两条不同的建图路径落到同一条兜底碰撞上。
	await _apply(w, host, MapDef.davao())
	t.ok(_hits_down(w, _probe_spots()) == true, "阳性对照：达沃（城市）也一样命中")
	t.ok(w.get("ocean") != null, "……而且城市图的海湾（水面）建出来了")

	# ---- ⚠️ 记录一个**既有**事实（不是本轮引入的）----
	# 太平洋图底下**也没有任何碰撞**：`_build_islands()` 一个碰撞体都不建，
	# 它靠 `FlightBody.CRASH_ALTITUDE = 24 m` 判"撞海"。
	# ⇒ `has_ground` 是**语义**位（"有没有『地表』这个概念"），不是"有没有碰撞"。
	await _apply(w, host, MapDef.pacific())
	t.ok(_hits_down(w, _probe_spots()) == false,
		"⚠️ 太平洋图底下同样没有碰撞体（`_build_islands()` 不建；靠 CRASH_ALTITUDE 判撞海）")
	t.ok(w.get("ocean") != null, "……但它的**海面**在 —— 所以它仍然有「地面」这个概念")
	t.near(w.match_player_alt(), WorldBuilder.PLAYER_START_ALT, 0.001,
		"阳性对照：太平洋图的出生标高仍是 3 200 m（`match_player_alt()` 没污染地表图）")

	# ---- 再切回轨道图：不残留上一张图的东西 ----
	await _apply(w, host, MapDef.leo())
	t.ok(w.get("ocean") == null, "再切回轨道图：海面没留下")
	t.ok(terrain.find_child("GroundFar", true, false) == null, "再切回：远景地坪没留下")
	t.eq((w.get("_cloud_root") as Node).get_child_count(), 0, "再切回：云没留下")
	t.ok(_hits_down(w, _probe_spots()) == false, "再切回：那批射线又全打空了")

	# ---- ★ 地球：脚下那颗**实体**天体（2026-09-29 · 老板"要能分辨出脚底下是地球"）----
	#
	# ⚠️ 这一组钉的是"**它真的是一个实体球，而且不参与物理**"。两件事各有硬理由：
	#   · **零碰撞**：`BanditAI._probe_terrain()` 打的是 WORLD 层**前向射线** ——
	#     地球一旦带碰撞体，**每一架敌机的正下方就永远有东西**，它们会把期望方向
	#     一路 `lerp` 到 `Vector3.UP`，战局变成"敌机全在爬升"（`_build_space()` 的注释
	#     记着同一条理由：碎片带不带碰撞也是因为它）；
	#   · **不投影**：半径 6 371 km 的投影体等于把整个场景盖进阴影里 ——
	#     看起来像"天黑"，不报错、不崩。
	# 而"向下看能不能**认出**它是地球"是**像素**问题 ⇒ 那条在出图探针里（见交付说明）。
	var earth := terrain.find_child("Earth", true, false)
	t.ok(earth != null, "★ 有地球（`_build_space()` 建的实体天体）")
	if earth != null:
		t.ok(earth is MeshInstance3D, "地球是 `MeshInstance3D`")
		t.ok(not (earth is StaticBody3D),
			"★★ ……而且**不是**物理体（带碰撞 ⇒ 每架敌机正下方永远有东西 ⇒ 敌机全在爬升）")
		if earth is MeshInstance3D:
			var mi := earth as MeshInstance3D
			var sph: SphereMesh = mi.mesh
			t.ok(sph != null, "地球挂着网格")
			if sph != null:
				t.near(sph.radius, WorldBuilder.SPACE_BODY_R, 4.0, "★ 球半径 = 6 371 km")
				t.near(sph.height, WorldBuilder.SPACE_BODY_R * 2.0, 8.0,
					"★ `height = 2 × radius`（只给 radius ⇒ 得到一个压扁的饼，而它照样渲染）")
				t.gt(float(sph.radial_segments), 64.0,
					"分段 %d 够把剪影做成圆（128 段的剪影偏差 ≈ 1.9 km，在 550 km 外是 0.04°）"
						% sph.radial_segments)
			t.near(mi.position.y, -WorldBuilder.SPACE_BODY_R, 4.0,
				"★★ 球心在 −R ⇒ **球顶正好落在 `y = 0`**（「五图的 y=0 是地表」在轨道图上继续成立）")
			t.eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"★ 不投影（6 371 km 的投影体等于把全场调成夜战）")
			var emat := mi.material_override
			t.ok(emat is ShaderMaterial, "地球用着色器材质（程序化海/陆/云，零贴图依赖）")
			if emat is ShaderMaterial:
				t.ok((emat as ShaderMaterial).shader != null, "……而且着色器真的挂上了")
				# ---- ★ 太阳方向的**符号**（本轮新钉）----
				#
				# 着色器算的是 `dot(NORMAL, sun_dir)` ⇒ 要在**日照侧**得到 1，
				# `sun_dir` 必须是"**从地表指向太阳**"的方向 = 主光的 `+Basis.z`
				#（`DirectionalLight3D` 是沿自己的 `-Basis.z` 照射的）。
				#
				# ⚠️ 传成 `-Basis.z` 会得到一个**昼夜线正好相反**的地球：不报错、不崩，
				# 在一个程序化球面上肉眼几乎看不出来（本轮做 pixel 判据时才从符号上发现）。
				# ⇒ 这里钉一条**可证伪的物理读数**：本图 `sun_rotation_deg.x = -24°`
				# ⇒ 太阳在水平面**之上** 24° ⇒ `sun_dir.y = sin(24°) = +0.4067`
				#（传反了就是 −0.4067）。负对照 = 把 `_earth_material()` 换回 `-b.z`。
				var sd: Vector3 = (emat as ShaderMaterial).get_shader_parameter("sun_dir")
				t.near(sd.y, 0.4067, 0.005,
					"★ 地球 `sun_dir.y = +sin(24°) = %.4f`（太阳在水平面上方 24 度；传反了是 -0.4067）"
						% sd.y)
				t.near(sd.length(), 1.0, 0.001, "……而且是单位向量")

	# ---- ★ 参照物都在 550 km 那一层（"高度和现实一致"的落地）----
	#
	# ⚠️ 这一组不是"好不好看"：`tools/_b2_leo_shots.gd` 量过"飞行 4 km 画面变多少像素"——
	# 噪声底为 **0**，而 1990 个变化像素里约 **1747** 来自碎片带。
	# 参照物**不在玩家那一层**的话，这张图赖以存在的"读得出我在动"会整个落空，
	# 而且**一处都不报错**（玩家只看到一片空旷的星空）。
	t.near(WorldBuilder.SPACE_POD_POS.y, WorldBuilder.SPACE_ORBIT_ALT, 0.001,
		"★ 运输仓在轨道高度上（M03 的目标点不能飘）")
	t.near(w.match_player_alt(), WorldBuilder.SPACE_ORBIT_ALT, 0.001,
		"★ 轨道图的**出生标高** = 轨道高度（不然玩家一出击就在所有参照物下方 546 km）")
	# ⚠️ **必须在这里重新取一次 `SpaceDebris`**：上面那个 `debris` 是中途（轨道图建图
	# 那一小段）取的引用，而之后 `_apply(w, host, ...)` 换过三张图 ——
	# `_map_stage_free()` 会把 `_terrain_root` 的子节点全部 `free()` ⇒
	# 旧引用变成**已释放实例**，`debris is MultiMeshInstance3D` 会报
	# "Left operand of 'is' is a previously freed instance"（无声、但会刷屏）。
	# ---- ⚠️ 碎片带为什么**不在无头下测** ----
	#
	# `MultiMesh` 的实例数据存在 RenderingServer 那一侧，而 `--headless` 是 dummy 驱动：
	# `set_instance_transform()` 变成 no-op、`get_instance_transform()` 恒返回**单位变换**。
	# 实测：`count = 48` / `format = TRANSFORM_3D` / `visible = -1` 全对，
	# 而 48 个实例的位置**全是 (0, 0, 0)** —— 一条"看起来很硬"的判据，
	# 实际在测渲染器的一份空实现。
	# ⇒ 这里改用**场景节点**（残骸 / 运输仓 / 卫星，位置由 `Node3D` 存取，无头下是真的）；
	#   碎片带那条留给真机出图探针，以及 `_wiring` 里的源码扫描。
	var wrecks := 0
	for c in terrain.get_children():
		if String(c.name).begins_with("SpaceWreck"):
			wrecks += 1
	t.eq(wrecks, 6, "六件大件残骸都挂在 `_terrain_root` 下")
	var wreck := terrain.find_child("SpaceWreck0", true, false)
	if wreck is Node3D:
		t.near((wreck as Node3D).position.y, WorldBuilder.SPACE_ORBIT_ALT, 2000.0,
			"★ 大件残骸也在那一层（%.0f m）" % (wreck as Node3D).position.y)
	var sat2 := terrain.find_child("*SatBus*", true, false)
	if sat2 is Node3D:
		t.gt((sat2 as Node3D).position.y, WorldBuilder.SPACE_ORBIT_ALT - 1.0,
			"★ 卫星在那一层**之上**（%.0f m；原来是 3 200 + 2 200…）" % (sat2 as Node3D).position.y)

	root.free()
	await host.get_tree().process_frame


static func _apply(w: WorldBuilder, host: Node, m: MapDef) -> void:
	w.apply_map(m)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame


## 四个采样点：半径 13 km 的四个正交方向，高度取出生高度。
##
## 半径 13 km 那圈是**空的** —— 运输仓在中心（0）、卫星 25.6 km、
## 大件残骸 39.1 km、碎片带 46.6 km，全在它外面（见 `_build_space()` 的常量）。
## 刻意避开场地中心：那里正好是运输仓，从盒体内部出发的射线读不准（见 `_hits_down()`）。
static func _probe_spots() -> Array[Vector3]:
	var y := WorldBuilder.PLAYER_START_ALT
	var r := 13000.0
	var out: Array[Vector3] = []
	out.append(Vector3(r, y, 0.0))
	out.append(Vector3(-r, y, 0.0))
	out.append(Vector3(0.0, y, r))
	out.append(Vector3(0.0, y, -r))
	return out


## 从 [param spots] 每个点正下方打一条 WORLD 层射线；**任意一条命中**就返回 true。
##
## 这就是"没有地面"那条字段的**行为化**判据：它不读 `has_ground`，只问物理世界。
## ⇒ 谁要是把 `GroundCollision` 留在轨道图上，这条立刻红。
##
## 取"任意命中"而不是"全部命中"：地表图上只要有一条碰到地坪就足以证明"底下有东西"；
## 而轨道图上要**四条全空**才算"底下真的没有"。
static func _hits_down(w: WorldBuilder, spots: Array[Vector3]) -> bool:
	var st := w.get_world_3d().direct_space_state
	for s: Vector3 in spots:
		var q := PhysicsRayQueryParameters3D.create(s, s + Vector3.DOWN * 8000.0)
		q.collision_mask = FlightBody.WORLD_LAYER
		if not st.intersect_ray(q).is_empty():
			return true
	return false


# ============================================================ ④ 没有地面：三处读数


static func _no_ground(t: T) -> void:
	t.suite(SPACE + " / 无地面（三处隐含前提的落地读数）")

	var keep := Game.active_map
	var keep_suit := Game.active_suit

	# ---- ① 死因文案 ----
	Game.active_map = MapDef.leo()
	t.not_ok(FlightBody.map_has_ground(), "★ 轨道图：`map_has_ground()` 为假")
	Game.active_map = MapDef.pacific()
	t.ok(FlightBody.map_has_ground(), "太平洋图：为真")
	Game.active_map = null
	t.ok(FlightBody.map_has_ground(),
		"★ `active_map` 为空（单测 / 还没开局）时按**有地面**算 —— 那是旧行为与字段默认值")

	# ---- ② HUD 底下那条线叫什么 ----
	var hud := FlightHUD.new()
	Game.active_map = MapDef.leo()
	t.eq(str(hud.call("_ground_word")), "再入线",
		"★ 轨道图：高度带底下那条线叫「再入线」（不是「地面」）")
	Game.active_map = MapDef.pacific()
	t.eq(str(hud.call("_ground_word")), "海面", "太平洋图：仍叫「海面」")
	Game.active_map = MapDef.uluru()
	t.eq(str(hud.call("_ground_word")), "地面", "艾尔斯岩：仍叫「地面」")
	Game.active_map = null
	t.eq(str(hud.call("_ground_word")), "地面", "没有地图时兜底「地面」")
	hud.free()

	# ---- ③ 设计稿担心的"全程 PULL UP"在相对坐标下**不成立** ----
	#
	# 判据用**纯函数**（`pull_up_clearance()`），不读 HUD 状态机：
	# 轨道图 `y = 0` 就是再入线 ⇒ 出生高度的"余量"就是 `PLAYER_START_ALT`（3 200 m），
	# 远高于 `PULL_UP_ALTITUDE = 420` ⇒ **不会报警**。
	# （设计稿 §4.8.4 第 2 条假设轨道图的 y 是几十万米的**绝对**高度；
	#   本工程的 y 是**相对参考面**的 —— 完整口径差异见设计文档 §10.4。）
	# ★ 2026-09-29：`y = 0` **不再是再入线**（它现在是**地球表面**）——
	# "到再入线的余量"因此变成 `轨道高度 − 再入线` = 450 km，不再是 3 200 m。
	var spawn_y := WorldBuilder.SPACE_ORBIT_ALT
	var margin := WorldBuilder.SPACE_ORBIT_ALT - WorldBuilder.SPACE_REENTRY_ALT
	t.gt(FlightHUD.pull_up_clearance(margin, 0.0), FlightHUD.PULL_UP_ALTITUDE * 2.0,
		"★ 轨道图出生高度上的预测余量 %.0f m ≫ 告警线 %.0f m（不会「全程报警」）"
			% [FlightHUD.pull_up_clearance(margin, 0.0), FlightHUD.PULL_UP_ALTITUDE])
	# 反过来：**贴到再入线附近时它照样会报** —— 而且那条告警在这里比在别的图上更有意义
	#（"再不拉升就要烧了"）。这正是"不关掉它"的理由。
	t.lt(FlightHUD.pull_up_clearance(300.0, -80.0), FlightHUD.PULL_UP_ALTITUDE,
		"……而贴到再入线附近时它照旧会报（这是**要留着**它的原因）")

	# ---- ④ 设计稿担心的"敌机全在爬升"也不成立 ----
	# `BanditAI` 的安全线（SAFE_ALTITUDE / CRITICAL_ALTITUDE）本来就是**相对 `y = 0`** 的。
	# 轨道图把 `y = 0` 定义成再入线之后，那两条线自动有了正确的含义：
	# 在出生高度上，"低空拉起"那一档的紧迫度算出来是 **0**。
	var predicted := spawn_y          # 平飞（vs = 0）
	var urgency := clampf((BanditAI.SAFE_ALTITUDE - predicted) / BanditAI.SAFE_ALTITUDE,
		0.0, 1.0)
	t.eq(urgency, 0.0,
		"★ 出生高度 %.0f m > SAFE_ALTITUDE %.0f m ⇒ 低空拉起档的紧迫度 = 0（敌机不会一路爬升）"
			% [predicted, BanditAI.SAFE_ALTITUDE])
	t.gt(spawn_y, BanditAI.SAFE_ALTITUDE, "……前提：出生高度确实在安全线之上")
	# 而它的**地形探头**在轨道图上没有地形可探 —— `BanditAI._probe_terrain()` 打的是
	# WORLD 层前向射线，轨道图上那层什么都没有 ⇒ 返回 INF、不产生规避项。
	# 这一条**不另写断言**：它就是上面"正下方 4 点全打空"那条射线判据的同一件事，
	# 再写一遍只会多一条恒真断言。（`_build_space()` 的注释记着为什么碎片带不能带碰撞。）

	Game.active_map = keep
	Game.active_suit = keep_suit


# ============================================================ ⑤ 越界：强制回轨


## **近地轨道没有"撞地"这回事。**
##
## 老板原话：「**近地轨道没有撞地这种情况**，超出地下边界了就应该强制机体回到近地轨道上」
## —— 而且他在"抬回边界 / 推回战斗高度带 / 送回出生点"里挑的是**推回战斗高度带**。
##
## ## 判据为什么必须落在**行为**上
## 这条需求改的是一个**互斥分支**：`_check_ceiling()` 从"判死"变成"推回"。
## 只断言"源码里有 `_enforce_orbit_floor()`"证明不了什么 —— 把 `destroy()` 也留在旁边
## 一样能过。⇒ 四条行为读数，缺一不可：
##   ① 被推回的高度**正好是战斗高度带**（不是"没死"就算过）；
##   ② `orbit_returns` 真的**加了 1**（证明这条路走过，而不是"恰好没越线"）；
##   ③ 机体**还活着**（那才是"没有撞地"）；
##   ④ 水平速度**留着**（否则"贴再入线飞"会变成急刹车）。
static func _orbit_floor(t: T, host: Node) -> void:
	t.suite(SPACE + " / 越界回轨（没有撞地这回事）")

	var keep := Game.active_map

	# ---- ① 下边界的高度：轨道图 = 卡门线；有地面图 = 照旧 24 m ----
	Game.active_map = MapDef.leo()
	t.near(FlightBody.orbit_floor_alt(), WorldBuilder.SPACE_REENTRY_ALT, 0.001,
		"★ 轨道图的下边界 = 再入线（100 km 卡门线）")
	Game.active_map = MapDef.pacific()
	t.near(FlightBody.orbit_floor_alt(), FlightBody.CRASH_ALTITUDE, 0.001,
		"阳性对照：太平洋图的下边界仍是 `CRASH_ALTITUDE`（24 m —— 撞海那条线没动）")
	Game.active_map = null
	t.near(FlightBody.orbit_floor_alt(), FlightBody.CRASH_ALTITUDE, 0.001,
		"没有地图时按**有地面**算（与 `map_has_ground()` 同一条规矩）")

	# ---- ② 真机：把机体按到线下，看它被推到哪 ----
	#
	# ⚠️⚠️ **机体必须真的进树**：`Node3D.global_position` 的 setter 在
	# `is_inside_tree()` 为假时**直接返回**（Godot 的 `ERR_FAIL_COND`）——
	# 裸建的机体设了位置也是 0，于是每一条判据都在测一个"停在原点"的机体。
	# （这一版就是这么红的：线上方的断言误触发回轨、地表图的断言真的撞海判死，
	#   三条红看起来像实现坏了，其实是判据自己没把机体放进世界。）
	var hold := Node3D.new()
	hold.name = "OrbitFloorProbe"
	host.add_child(hold)
	var fb := FlightBody.new()
	fb.profile = SuitProfile.xi()
	hold.add_child(fb)
	Game.active_map = MapDef.leo()
	fb.global_position = Vector3(0.0, 50000.0, 0.0)      # 远低于 100 km 的再入线
	fb.fm.velocity = Vector3(1200.0, -2600.0, 0.0)       # 正在俯冲（垂直速度是负的）
	var before := fb.orbit_returns
	fb.call("_check_ceiling")
	t.near(fb.global_position.y, WorldBuilder.SPACE_ORBIT_ALT, 0.001,
		"★ 被推回**战斗高度带**（550 km）—— 不是随便抬一下")
	t.eq(fb.orbit_returns, before + 1,
		"★ 回轨计数 +1（证明这条路真的走过，不是「恰好没越线」）")
	t.ok(fb.alive, "★★ **没有判死** —— 「近地轨道没有撞地这种情况」")
	t.near(fb.fm.velocity.y, 0.0, 0.001,
		"★ 垂直速度被清零（不清的话下一帧立刻又掉下去 ⇒ 每帧回轨、计数疯涨）")
	t.near(fb.fm.velocity.x, 1200.0, 0.001,
		"★ 水平速度原样留着（被顶回来的是**垂直**那一维；否则贴线飞会变成急刹车）")

	# ---- ③ 边界**之内**不该触发 ----
	fb.global_position = Vector3(0.0, WorldBuilder.SPACE_ORBIT_ALT - 5000.0, 0.0)
	var c2 := fb.orbit_returns
	fb.call("_check_ceiling")
	t.eq(fb.orbit_returns, c2,
		"★ 在战斗高度带里（再入线上方 445 km）**不触发** —— 否则就是把整层空间都当边界")

	# ---- ④ 反面：地表图上**根本不走这条路** ----
	#
	# ⚠️ 这里**故意不把机体按到撞海线以下**：那会真的调 `destroy()` ⇒
	# 未进树的机体没有子节点，`_end_saber()` / `FX` 那一路会在无头下引入噪声。
	# "低于 24 m 会判死"是**既有行为**（别的套件钉着），不必在这里重测；
	# 这里要证的是**两种行为互斥** —— 地表图上那条路不该被走到。
	Game.active_map = MapDef.pacific()
	fb.global_position = Vector3(0.0, 30.0, 0.0)      # 撞海线上方 6 m
	var c3 := fb.orbit_returns
	fb.call("_check_ceiling")
	t.ok(fb.alive, "反面：太平洋图在撞海线上方 ⇒ 照旧相安无事")
	t.eq(fb.orbit_returns, c3,
		"★ ……而且**没有**走回轨那条路（两种行为互斥 —— 这正是上面要证明的）")

	hold.free()
	Game.active_map = keep


# ============================================================ ⑥ 接线（源码事实）


static func _wiring(t: T) -> void:
	t.suite(SPACE + " / 接线扫描")

	var wb := _src("res://scripts/world/world_builder.gd")
	var stage := _body(wb, "func _map_stage_terrain(")
	t.ok(stage.contains("MapDef.Terrain.SPACE:"),
		"★ `_map_stage_terrain()` 里**真的有一条 SPACE 分支**（否则静默建成群岛）")
	t.ok(stage.contains("_build_space()"), "……而且它建的是 `_build_space()`")
	t.ok(stage.contains("_build_islands(ISLAND_COUNT)"),
		"……`_` 兜底分支仍在（既有四张图靠它）")
	t.ok(stage.contains("_rng.seed = 20260917"),
		"……建图随机种子一个字没动（旧图的布点靠它逐位不变）")

	var clouds := _body(wb, "func _rebuild_clouds(")
	t.ok(clouds.contains("if density <= 0.0:"),
		"★ `_rebuild_clouds()` 有「云量为 0 ⇒ 不建」那条路")
	t.ok(clouds.contains("_cloud_shade_tex = null"),
		"……而且把云影覆盖图也清掉")
	t.ok(clouds.contains("return"), "……那条路会提前返回")

	var tod := _body(wb, "func apply_time_of_day(")
	t.ok(tod.contains("set_shader_parameter(\"ground_blend\""),
		"★ `apply_time_of_day()` 真的把 `ground_blend` 灌进天空材质")
	t.ok(tod.contains("tod.ground_blend"), "……值取自 `TimeOfDay.ground_blend`")

	var fb := _src("res://scripts/flight/flight_body.gd")
	t.ok(fb.contains("static func map_has_ground()"),
		"★ `FlightBody.map_has_ground()` 存在（唯一的判据）")
	# ★ 2026-09-29：轨道图从"越过再入线就**烧毁**"改成"**推回战斗高度带**"
	#（老板：「近地轨道没有撞地这种情况」）。这条断言跟着换口径 ——
	# 它钉的是"两条路互斥"，而不是某一句文案。
	t.ok(_body(fb, "func _check_ceiling(").contains("_enforce_orbit_floor()"),
		"★ `_check_ceiling()` 在无地面图上走**推回轨道**那条路（不再判死）")
	t.ok(_body(fb, "func _check_ceiling(").contains("map_has_ground()"),
		"★ ……而且分路判的是 `has_ground` 这一位")
	t.ok(_body(fb, "func _check_collisions(").contains("撞毁"),
		"★ `_check_collisions()` 的兜底文案同理")
	t.ok(not _body(fb, "func _check_ceiling(").contains("Id.LEO"),
		"……而且它**不认地图 id**（认的是 `has_ground` 这一位）")

	# ---- ★ 地球与远裁面（2026-09-29）----
	var wb2 := _src("res://scripts/world/world_builder.gd")
	t.ok(wb2.contains("func _build_earth()"), "★ `_build_earth()` 存在")
	var eb := _body(wb2, "func _build_earth(")
	t.ok(eb.contains("SHADOW_CASTING_SETTING_OFF"),
		"★ ……它把投影关掉了（6 371 km 的投影体 = 全场夜战）")
	t.ok(eb.contains("Vector3(0.0, -SPACE_BODY_R, 0.0)"),
		"★★ 球心在 −R ⇒ 球顶 = `y = 0`（「五图的 y=0 是地表」在轨道图上继续成立）")
	t.ok(not eb.contains("StaticBody3D"),
		"★ 地球**不是**物理体（带碰撞 ⇒ 每架敌机正下方永远有东西 ⇒ 敌机全在爬升）")
	t.ok(wb2.contains("res://scripts/world/earth.gdshader"), "地球着色器的路径在")
	t.ok(_src("res://scripts/world/earth.gdshader").length() > 500,
		"★ `earth.gdshader` 真的存在且非空")
	t.ok(wb2.contains("func match_player_alt()"),
		"★ `match_player_alt()` 存在（出生标高按图给）")
	t.ok(_body(wb2, "func _build_space(").contains("_build_earth()"),
		"★ `_build_space()` 真的调了它（建了不调 = 图里没有地球）")
	# ---- ★ 碎片带的高度带：**源码扫描**（为什么不能在无头下读 MultiMesh 见 `_build`）----
	var bs := _body(wb2, "func _build_space(")
	t.ok(bs.contains("SPACE_ORBIT_ALT + 1200.0 * sin"),
		"★ 碎片带的高度带按 `SPACE_ORBIT_ALT` 派生（不是还写死在 3 200 m）")
	t.ok(not bs.contains("PLAYER_START_ALT"),
		"★★ ……而且这个函数里**一处 `PLAYER_START_ALT` 都不剩** —— "
			+ "'忘了改其中某一处'就是这个形态（改前那一版四处全是它）")

	var cam := _src("res://scripts/flight/chase_camera.gd")
	# ⚠️ 2026-09-30：这条原来钉的是字面量 `const ORBIT_FAR := 1.0e7`，
	#   而那个值**必须**改（`near 0.35 × far 1e7` ⇒ `create_frustum_points` 失败 ⇒
	#   整个 3D 场景不被点亮，见 `ORBIT_FAR` 里那 14 张定点扫描表）——
	#   字面量钉子当场变成假红。改成钉**不变式**：有独立常量、比地面档远一个量级、
	#   但仍在渲染管线吃得下的区间里。
	t.ok(cam.contains("const ORBIT_FAR :="), "★ 相机有一个**轨道图专用**的远裁面")
	t.ok(ChaseCamera.ORBIT_FAR > ChaseCamera.GROUND_FAR * 10.0,
		"★ ……而且比地面档**远一个量级**（地球切线圆离相机 ≈ 2 703 km，实测 %.0f km）"
			% (ChaseCamera.ORBIT_FAR / 1000.0))
	t.ok(ChaseCamera.ORBIT_FAR <= 7.0e6,
		"★★ ……但不能越过 7 000 km：`far = 1e7` 那一档会把整场景点不亮（实测 %.0f km）"
			% (ChaseCamera.ORBIT_FAR / 1000.0))
	t.ok(_body(cam, "func _sync_depth_range(").contains("not m.has_ground"),
		"★ ……而且它按 `has_ground` 切换（不认地图 id）")
	t.ok(cam.contains("\t_sync_depth_range()"), "……并且真的被调了（不只是定义在那儿）")

	var hud := _src("res://scripts/ui/hud.gd")
	var gw := _body(hud, "func _ground_word(")
	t.ok(gw.contains("再入线"), "★ HUD 的 `_ground_word()` 认「再入线」")
	t.ok(gw.find("not m.has_ground") < gw.find("Terrain.ISLANDS"),
		"★ ……而且「没有地面」那一条**排在海/地之前**（顺序写反会落进兜底「地面」）")

	var mp := _src("res://tests/pixprobe.gd")
	t.ok(mp.contains("\"leo\""), "pixprobe 的 `--map=` 通道登记了 leo（否则静默回落太平洋）")

	var runner := _src("res://tests/test_runner.gd")
	t.ok(runner.contains("suite_space_map.gd"), "本套件已注册进 test_runner")


# ------------------------------------------------------------- 几何辅助


## `Pod*` 全部节点**合并**后的世界系 AABB。
##
## ⚠️ 必须合并，不能逐块看：本轮改真模型之后，量的是 `PodHull` 里那只
## 111.6 万顶点的网格 —— `PodBody` 子树里同时挂着 `PodHull`（可见）与
## `CollisionShape3D`（无网格，`_subtree_aabb` 会跳过）。
## 上一轮（程序化方筒）最长边由 `PodNozzle` 前端与 `PodFairing` 后端**共同**界定。
##
## ⚠️ 也不能用 `find_child("Pod*")` —— 它只返回**第一个**匹配。
static func _pods_aabb(terrain: Node) -> AABB:
	var box := AABB()
	var found := false
	var stack: Array[Node] = [terrain]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and str(n.name).begins_with("Pod"):
			var b := _subtree_aabb(n)
			box = b if not found else box.merge(b)
			found = true
			continue
		for c in n.get_children():
			stack.append(c)
	return box


## 一棵子树里所有 `MeshInstance3D` 的世界系 AABB。
##
## ⚠️ 必须用 `global_transform`：`WorldBuilder._add_block()` 把盒体挂在
## `StaticBody3D` 上（`body.position = pos`），`MeshInstance3D` 自己的 local
## 变换是 identity ⇒ 只读 local 会得到"所有块都堆在原点"的假读数
##（那会让最长边变成一个箱体的尺寸，而不是整条仓的长度）。
static func _subtree_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var found := false
	for m in _meshes_deep(n):
		var mi := m as MeshInstance3D
		var src: AABB = mi.get_aabb()
		var xf: Transform3D = mi.global_transform
		for i in 8:
			var c := src.position + Vector3(
				src.size.x if (i & 1) else 0.0,
				src.size.y if (i & 2) else 0.0,
				src.size.z if (i & 4) else 0.0)
			var wp: Vector3 = xf * c
			if not found:
				out = AABB(wp, Vector3.ZERO)
				found = true
			else:
				out = out.expand(wp)
	return out


static func _mesh_count(n: Node) -> int:
	return _meshes_deep(n).size()


static func _meshes_deep(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes_deep(c))
	return out


# ------------------------------------------------------------- 源码辅助


static func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


## `sky.gdshader` 里 `ground_blend` 的默认值（也是 `TimeOfDay.ground_blend` 的默认值）。
## 写成常量是为了让"新旧档都没被这一轮动过"这件事有**一个**可以对着断言的数。
const GROUND_BLEND_DEFAULT := 0.18


## 取 `head` 之后到**下一行列 0 的非空行**之间的正文（GDScript 里就是下一个 `func`）。
static func _body(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var rest := src.substr(i + head.length())
	var out := ""
	var started := false
	for l in rest.split("\n"):
		var s := String(l)
		if s.begins_with("func "):
			break
		if started and s.length() > 0 and s[0] != "\t" and s[0] != " ":
			break
		started = true
		out += s + "\n"
	return out
