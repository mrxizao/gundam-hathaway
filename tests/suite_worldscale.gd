class_name SuiteWorldScale
extends RefCounted
## 第二十二轮：**地图范围整体放大 2.3 倍**。
##
## ⚠️ **文件名/类名为什么不叫 `suite_round22`**：这个工程**有另一个会话在并行编辑**，
## 而两边都习惯按"轮次"占编号 —— 我的第一版正好叫 `suite_round22.gd`，
## 于是把对方同一编号的套件**整个覆盖掉了**（真发生过，对方只好改成
## `suite_tutorial.gd` 才绕开；见那套文件头的记录）。
## 改成按主题命名（`suite_worldscale`）之后，编号就不会再撞。
##
## 用户原话：「包括奥恩贝利在内，现在**所有的地图范围都太小了**，需要再扩大 2-3 倍」，
## 并在被问到"速度要不要跟着放大"时选了 **只放大空间、机体数值一律不动**，
## 倍数取 **2.3×**。
##
## ## 这一套守的是什么
## 放大地图**不是把一两个数字乘 2.3** —— `ARENA_RADIUS` 有四个连带项
##（出击距离 / 地表尺寸 / 云场跨度 / 云带半径），而"速度不动"这条决定
## 又是**用一组"不变"来定义的**（那种断言最容易在以后被无意改掉）。
## 所以这套分三段：
##
## | 组 | 钉住的东西 |
## |---|---|
## | **比例** | 出击点 / 训练半径 / 城市各坐标都跟着 `MAP_SCALE` 同倍放大 |
## | **连带项** | 海面 / 地坪 / 细分网格 / 云场跨度必须比竞技场大出一截 |
## | **不变量** | **机体速度、槽时长、导弹倍率一个字都没动**（这才叫"只放大空间"） |
##
## ⚠️ 第三组是这套里最要紧的：它把"方案 B"写成了可执行的判据。
## 以后谁想在地图变大的同时顺手把机体调快，就必须先来这里删掉一条断言 ——
## 而不是让它在没人注意的时候悄悄漂掉。

const SCALE := "Round22 / 地图放大：比例一致"
const ENVELOPE := "Round22 / 地图放大：地表与云场的连带项"
const INVARIANT := "Round22 / 地图放大：机体数值一个都没动"

## ## ⚠️⚠️ 2026-09-27（达沃重制）：**这一列有了两种语义**，这是刻意的
##
## | 常量 | 它是什么 | 断言怎么用它 |
## |---|---|---|
## | `OLD_ARENA` / `OLD_SPAWN` / `OLD_TRAINING` | **对局尺度**的上一档 | `现值 = 旧值 × MAP_SCALE`（比例一致） |
## | `OLD_MONORAIL_R` / `OLD_PLAZA_R` | **奥恩贝利的城域坐标现值** | `现值 == 旧值`（**它没有跟着对局尺度走**） |
##
## ## 为什么要拆
## 上一轮（2.3×）时"岛和竞技场一起变大"，所以两组数被绑在一起同倍放大是对的。
## 但 2026-09-27 这一轮**竞技场又 ×2.25，而城域坐标一个字没动**
##（达沃的城域坐标由 `WorldBuilder.CITY_SHAPE` 按图给，奥恩贝利 = 现值）——
## 不拆的话那五条会各差 **2%** 而全红，**而红的原因跟要改的东西（达沃）毫无关系**。
##
## ⚠️ 所以下面 `_scale()` 里，前半段是"跟 MAP_SCALE 走"，
## 后半段（城域）反转为"**与原值相等**"—— 那才是"奥恩贝利的城一个像素都不动"
## 这句话的可执行形式。
##
## ## ⚠️⚠️ 2026-09-28：这一列**又少了两项**（`OLD_BAY_Z` / `OLD_CANAL_X` / `OLD_CANAL_HALF`）
## 四块人工岛那一轮**主动改掉了奥恩贝利的城域坐标**，而理由是**几何**、不是尺度：
##   · `CITY_BAY_Z 29 900 → 38 000`：四块岛的最外一排到了 `z = 32 200`，
##     旧岸线**正好落进岛里** ⇒ 海湾线必须外移（余量 1 103 m）；
##   · `CITY_CANAL_X / _HALF / _END_Z` **三个常量整个删掉了**：
##     运河从"一条写死的直槽"改成"**四块岛的补集**"（`OENB_BLOCKS`，详规 §B.4）——
##     它不再有唯一值，所以**没有"现值"可比**。
## ⇒ 继续断言"`CITY_BAY_Z == 29 900`"会拦住一次**正确的**改动；
##   继续引用 `CITY_CANAL_*` 则**连编译都过不去**。
##   这两件事现在由 `suite_round20` 的"四块岛"那一节守着（那里判的是几何，
##   不是"跟旧值相等"）—— 那才是它们该在的地方。
const OLD_ARENA := 64400.0
const OLD_SPAWN := 20700.0
const OLD_TRAINING := 11960.0
const OLD_MONORAIL_R := 27600.0   ## ⚠️ 奥恩贝利的**城域坐标现值**（不是"上一档"）
const OLD_PLAZA_R := 11960.0      ## ⚠️ 同上


static func run(t: T, host: Node) -> void:
	t.suite(SCALE)
	_scale(t)
	t.suite(ENVELOPE)
	_envelope(t)
	t.suite(INVARIANT)
	_invariant(t)
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 1 比例一致

static func _scale(t: T) -> void:
	# ---- 放大系数本身 ----
	t.near(WorldBuilder.MAP_SCALE, 2.25, 0.001,
		"放大系数是 2.25（2026-09-27 达沃重制这一档）")
	t.near(WorldBuilder.ARENA_RADIUS, OLD_ARENA * WorldBuilder.MAP_SCALE, 1.0,
		"竞技场半径 = 上一档 × MAP_SCALE（%.1f km）" % (WorldBuilder.ARENA_RADIUS / 1000.0))
	# ---- 新加：格距必须仍是 4025 ----
	#
	# ⚠️ 它是"城市要素**绝对尺寸**"的**分母**（楼 1 400~4 900 m / 龙门吊腿 720 m /
	# 单轨 420 m 全是相对它给的）。`ARENA_RADIUS` 与 `CITY_GRID` 必须**同步**改，
	# 否则全城的楼、街、广场会一起缩放 —— 而那种错**画面上不明显**，
	# 只表现为"看起来哪里不对"。这条断言是"**只加格数、不加格距**"
	# 那句设计决定的唯一可执行形式。
	var cell_block := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	t.near(cell_block, 4025.0, 0.5,
		"城市格距仍是 %.1f m ⇒ 全城的楼 / 街 / 广场比例一个字没动" % cell_block)

	# ---- 出击点：**按比例**跟上去（而不是原地不动）----
	# ⚠️ 这两条是"地图变大"与"出击点不动"两种做法的分水岭：
	# 原地不动的话，出击点会从半径的 32% 缩到 14% —— 玩家等于在战场中心出生，
	# "赶路 → 接战"的节奏就没了（README 第十九轮那一整节讲的就是这件事）。
	var old_ratio := OLD_SPAWN / OLD_ARENA
	var new_ratio := WorldBuilder.SPAWN_RADIUS / WorldBuilder.ARENA_RADIUS
	t.near(new_ratio, old_ratio, 0.02,
		"出击点占半径的比例没变（%.3f，旧值 %.3f）" % [new_ratio, old_ratio])
	t.lt(WorldBuilder.SPAWN_RADIUS, WorldBuilder.ARENA_RADIUS * 0.75,
		"出击点仍留了余量（不贴出界线）")

	# ---- 训练靶场半径：同一个比例 ----
	t.near(WorldBuilder.TRAINING_PATROL_RADIUS / WorldBuilder.ARENA_RADIUS,
		OLD_TRAINING / OLD_ARENA, 0.02, "训练靶场半径占半径的比例也没变")

	# ---- 城市自己的坐标：**这一轮它们不跟对局尺度走** ----
	#
	# ⚠️⚠️ 2026-09-27（达沃重制）把这一组**反转**了，这是本轮最容易误读的一处。
	#
	# 上一轮（2.3×）时"岛和竞技场一起变大"，所以同倍放大是对的。但这一轮
	# **竞技场又 ×2.25，而奥恩贝利的城域坐标一个字没动** —— 它们从"跟着
	# `MAP_SCALE` 走的常量"搬进了 `CITY_SHAPE`（按图给，`[0]` 直接引用常量，
	# 保证与现值逐位相同）。达沃有自己的一整套（rx 15 / bay_z −26 000 / …）。
	#
	# ⇒ 判据从「= 旧值 × MAP_SCALE」换成「**= 现值**」。后者才是
	#   "奥恩贝利的城一个像素都不动"这句话的**可执行形式**。
	#   如果继续乘 MAP_SCALE，这五条会各差 **2%** 而全红 ——
	#   而红的原因跟要改的东西（达沃）毫无关系，那是最难查的一类红。
	t.near(WorldBuilder.CITY_MONORAIL_R, OLD_MONORAIL_R, 1.0,
		"单轨环线半径**没跟对局尺度走**（它现在按图给：奥恩贝利 27.6 km / 达沃 0）")
	t.near(WorldBuilder.CITY_PLAZA_R, OLD_PLAZA_R, 1.0,
		"中央广场半径**没跟对局尺度走**")
	# ⚠️ 2026-09-28：`CITY_BAY_Z` / `CITY_CANAL_*` 三条**已删**（理由见文件头）。
	# 代它们的是下面两条**几何**判据 —— 都用**格索引**算，一个米数字面量都不抄。
	#
	# ## ⚠️⚠️ 这两条的第一版**判错了方向**，记在这里免得再犯
	# 第一版写的是 `bay_z − wave > max(|gx0|, |gx1+1|, |gz0|, |gz1+1|)`（**四边取绝对值**）。
	# 它必红，而拿到的是 `64 400`（青海块的 `gx1+1 = 16` ⇒ ±X 的 64 400）。
	# 错在两处：
	#   · **方向**：海湾在 **+Z**（`bay_side = +1`）⇒ 只有 **+Z 的岛缘**可能被岸线切到；
	#     ±X 与 −Z 的岛缘离岸线再远也没关系（那边是"盒外 ⇒ 陆地"，没有岸线）。
	#   · **口径**：判"岸线切不到岛"要比的是**裙房外缘**，不是格线。
	#     `CITY_FILL = 0.62` 的地块占地会往外溢出格线 `cell_block × 0.62 ÷ 2`。
	#
	# ① **岸线最低点 > 岛缘 + 半裙房** —— 岸线是一条正弦，要用它的**最低点**
	#    （`bay_z − wave`）来判，不然波谷那半张图会把最外一排啃掉。
	var max_z := 0.0
	for b: Array in WorldBuilder.OENB_BLOCKS:
		max_z = maxf(max_z, (float(int(b[3])) + 1.0) * cell_block)
	var reach := max_z + cell_block * WorldBuilder.CITY_FILL * 0.5
	t.gt(WorldBuilder.CITY_BAY_Z - WorldBuilder.CITY_BAY_WAVE, reach,
		("海湾线最低点 %.0f m > 四块岛最外缘 + 半裙房 %.0f m（余 %.0f m）⇒ 岸线切不到岛"
			+ "（四块岛那一轮把 `CITY_BAY_Z` 从 29 900 抬到 38 000 就是为了这一条；"
			+ "注意 `CITY_BAY_Z` 本身 = 38 000 **小于** 详规 §B.5 的 58 000，理由见常量注释）")
			% [WorldBuilder.CITY_BAY_Z - WorldBuilder.CITY_BAY_WAVE, reach,
				WorldBuilder.CITY_BAY_Z - WorldBuilder.CITY_BAY_WAVE - reach])
	# ② **盒子 +Z 边 > 岸线最高点**。
	#    `is_water_at()` 里"盒外 ⇒ 城郊陆地"这一支是**无条件**的：
	#    盒子若盖不住波峰（`bay_z + wave`），波峰之外那一条会判成**陆地** ——
	#    画面上就是海中间横出一条假海岸，而这条错**不会报任何警告**
	#    （它是"某一块本该是水的地方变成了地"，不触发任何断言）。
	#    这也正是 `OENB_BOX[3] = 10`（比详规草案的 8 多两格）那个决定的可执行形式。
	var box_z1 := (float(int(WorldBuilder.OENB_BOX[3])) + 1.0) * cell_block
	t.gt(box_z1, WorldBuilder.CITY_BAY_Z + WorldBuilder.CITY_BAY_WAVE,
		("盒子 +Z 边 %.0f m 盖过岸线波峰 %.0f m ⇒ 波峰之外不会出现「盒外 ⇒ 陆地」的假海岸")
			% [box_z1, WorldBuilder.CITY_BAY_Z + WorldBuilder.CITY_BAY_WAVE])
	# ⚠️ 而"城域坐标确实搬进了表里"这件事要**另外**钉一条 —— 不然上面五条
	# 在"有人把表删了、函数回去引用旧常量"时照样绿。
	var oe_shape: Dictionary = WorldBuilder.CITY_SHAPE[MapDef.CityLayout.OENBELLI]
	t.near(float(oe_shape.bay_z), WorldBuilder.CITY_BAY_Z, 0.001,
		"表 `[0]` 的海湾基准 z 引用的是常量本身（不是抄来的字面量）")
	var dv_shape: Dictionary = WorldBuilder.CITY_SHAPE[MapDef.CityLayout.DAVAO]
	t.ok(absf(float(dv_shape.bay_z) - WorldBuilder.CITY_BAY_Z) > 1000.0,
		"达沃的海湾基准 z（%.0f）与奥恩贝利差得开 ⇒ 表真的按图给了不同坐标"
			% float(dv_shape.bay_z))
	# 街区块：由 `ARENA_RADIUS / CITY_GRID` 推出来，所以自动跟着放大 —— 这里只断言结论。
	var block := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	t.gt(block, 3800.0, "街区块边长 %.0f m（放大后 ≈4025）" % block)
	# 而**建筑高度不跟着放大**（高度是垂直方向的量，与地图大小无关）：
	# 市中心最高一档仍在 2500~3050 m，没有被 2.3 倍带成 6000 m。
	var probe := RandomNumberGenerator.new()
	probe.seed = WorldBuilder._city_lot_seed(0, 0)
	var lot := WorldBuilder.city_lot_for(0, 0, probe)
	t.gt(lot.h, 1300.0, "市中心楼高下限没缩水")
	t.lt(lot.h, 3200.0, "市中心楼高也没有被地图放大带高（%.0f m）" % lot.h)


# ---------------------------------------------------------------- 2 连带项

static func _envelope(t: T) -> void:
	# ⚠️ 地表与云场是"地图尺寸"的**必要条件**：它们不跟上的话，
	# 玩家飞到竞技场边缘会看见一张纯色平面 —— 那种"世界到头了"的观感
	# 正是这一轮要消灭的东西。
	var r := WorldBuilder.ARENA_RADIUS
	t.gt(WorldBuilder.OCEAN_SIZE, r * 4.0, "海面远大于竞技场直径")
	t.gt(WorldBuilder.LAND_SIZE, r * 4.0, "陆地远景地坪远大于竞技场直径")
	# ⚠️⚠️ 2026-09-27：这一条的口径**从「比竞技场」改成「比城域」**。
	#
	# 旧判据 `TERRAIN_DETAIL_SIZE > ARENA × 1.5` 是"地表要铺满整张图"的代理，
	# 而这一轮 `ARENA_RADIUS` 里**有 65 km 是外海**（达沃的出生点就在岛外海上）。
	# 按旧口径要铺满 217 km，而细分网格真正的职责只是"盖住**城市要素**所在的那一块"
	#（城外的海面归 `OCEAN_SIZE` 那张平面，远景归 `LAND_SIZE`）。
	#
	# ⇒ 新口径：**覆盖两座城里最大的城域半宽**。这才是"铺满了"的可执行含义，
	#   也顺带省下一大块顶点（详见设计文档 §J.3）。
	var cblock := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var city_half := 0.0
	for p: Dictionary in WorldBuilder.CITY_SHAPE:
		# 岛的最远点：横向取 rx，纵向取 |岛心| + rz（达沃岛心北移 5 格，北缘最远）
		city_half = maxf(city_half, maxf(absf(float(p.rx)),
			absf(float(p.cz)) + float(p.rz)) * cblock)
	t.gt(WorldBuilder.TERRAIN_DETAIL_SIZE * 0.5, city_half,
		"地表细分网格盖住最大的城域（半宽 %.1f km > 城域 %.1f km）"
			% [WorldBuilder.TERRAIN_DETAIL_SIZE * 0.5 / 1000.0, city_half / 1000.0])
	# 云影覆盖图的跨度是**变量**（`_ready` 之前按常量算好），所以读一个实例来验。
	var w := WorldBuilder.new()
	t.near(w.cloud_field_span, r * 2.0, 1.0, "云影覆盖图的跨度 = 竞技场直径")
	# 城市地面细分段数：放大 2.3 倍之后仍要够细（每格别超过 320 m）。
	var per_cell := WorldBuilder.TERRAIN_DETAIL_SIZE / float(WorldBuilder.CITY_GROUND_SEG)
	t.lt(per_cell, 320.0, "城市地面每格 %.0f m（海岸线/运河壁不会糊成锯齿）" % per_cell)
	w.free()


# ---------------------------------------------------------------- 3 不变量

static func _invariant(t: T) -> void:
	# ⚠️ **这一组才是"方案 B"的定义**：空间放大 2.3 倍，而机体/武器一个字都没改。
	# 以后谁想顺手把机体调快，必须来这里删一条断言 —— 这就是它存在的意义。
	t.near(SuitProfile.XI_REFERENCE_SPEED, 420.0, 0.001, "基准速度 420 m/s 未动")
	t.near(SuitProfile.MISSILE_SPEED_MULT, 2.6, 0.001,
		"导弹倍率 2.0 → 2.6（2026-09-22 晚，用户：导弹提速追得上 QB 后的玩家）")
	# ⚠️ **修正（2026-09-21 · 批 3）**：这里原来断言 `Interceptor.SPEED == 1500.0`。
	# 那是**一个从来没被实例化过的节点类**上的常量（设计文档 §3.5，那个类已删）——
	# 改它不影响任何东西，所以这条断言**一直是假绿的**：
	# 老板后来把拦截弹从 1.8 调到 1.1（真正在跑的是 `Missile.INTERCEPT_SPEED_MULT`），
	# 而它照样绿。现在改成断言**真正在跑的那个常数**，
	# 且判据是"**没被地图放大带跑**"而不是"等于某个数"——
	# 后者是这类断言最后沦为摆设的原因（老板每调一次手感就得来删一条）。
	t.between(Missile.INTERCEPT_SPEED_MULT, 1.0, 2.0,
		"拦截弹速度倍率 %.2f ∈ [1.0, 2.0]（若被地图放大带上，这里读到的是 %.2f）"
			% [Missile.INTERCEPT_SPEED_MULT,
				Missile.INTERCEPT_SPEED_MULT * WorldBuilder.MAP_SCALE])
	for id: int in [SuitProfile.Id.MESSER_M01, SuitProfile.Id.GUSTAV00]:
		var p := SuitProfile.by_id(id)
		t.ok(p.has_jet_gauge, "%s 仍然有燃料槽" % p.display_name)
		# ⚠️ 判据写成"与类默认值一致"，而不是写死一个数：
		# 这两个字段是**每台机各自赋值**的，写死会在别人调平衡时误红。
		t.near(p.jet_seconds, 8.0, 0.001,
			"%s 的槽时长仍是 8 s（地图放大不给它加时长）" % p.display_name)
		# ⚠️ 2026-09-30（轮 44）用户主动改了这条口径：「恢复速度提升至柯西的 80%」
		#    ⇒ 26 s → 1/(0.8 × 0.22) = 5.6818 s。**这条断言的意图一个字没变**：
		#    它守的始终是「地图放大不给槽加时长/回充」，只是参考值换成新的真源算式。
		#    写成算式而不是写死 5.68，是为了让「柯西的速率」只有一处真源。
		t.near(p.jet_recharge,
			1.0 / (SuitProfile.JET_RECHARGE_VS_XI * SuitProfile.XI_DASH_REGEN), 0.001,
			"%s 的槽回充 = 柯西冲刺条速率的 80%%（%.4f s）" % [p.display_name, p.jet_recharge])
		# 量产机极速仍是那两台（梅萨 579 / 古斯塔夫 535，显示域），不是 2.3 倍后的数字。
		#
		# ⚠️ 2026-09-25：实际速度整体 ×`SPEED_REAL_MULT`（1.5）之后，
		# 这条必须拿**显示域**的数来比 —— 它的原意是"地图放大没带快机体"，
		# 而不是"机体永远不许提速"（提速是老板这次明确要的）。
		t.lt(SuitProfile.speed_to_display(p.player_boost_speed()), 800.0,
			"%s 极速（显示域）%.0f m/s < 800（没被地图放大带快）"
				% [p.display_name, SuitProfile.speed_to_display(p.player_boost_speed())])
