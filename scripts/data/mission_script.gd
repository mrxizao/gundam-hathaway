class_name MissionScript
extends RefCounted
## 剧情模式的**任务数据层**（DESIGN §5 · 轮 A）：一座战役 = 8 个 `Mission`，
## 每一关 = 若干 `Objective`（目标）+ 一张 `Trigger` 表（事件）+ 若干 `Zone`（区域）。
##
## ⚠️ **本文件是纯数据 + 纯函数**：不读节点、不读时间、不读存档、不存运行时状态。
## 这条与 `MissionRating` / `UILayout` / `ChaseCamera.shield_hit_ratio()` 是同一条工程规矩
## （`mission_rating.gd` 头部那段话写得最清楚）：
##   「评价是**算出来**的，不是从现场抄的，所以必须能被单测直接喂一个字典来断言。」
## 于是 `Trigger.eval("elapsed>=90", {"elapsed": 89.9})` 必须**当场**给出 `false`，
## 而不是"跑一万次看分布"。⇒ 本文件整份可以被 `tests/suite_campaign.gd` 在**不进游戏**的
## 情况下验完。
##
## ## 与 `ChallengeScript` 的关系：**升级，不是另写一套**（DESIGN §5.1）
## `Encounter` 的字段**一个都没浪费** —— `story` 就是简报/电台的现成文案位，
## `waves` 直接就是 `ChallengeScript.Wave`（本文件**复用**它，不复制一份）。
## M04 / M07 的波次**逐字引用**现有的 `xi_vs_penelope()` / `xi_vs_arizeus()`
## （DESIGN §4.3 的"复用清单"）⇒ 现有那 4 场遭遇的测试天然变成这 7 关的回归门。
## ⚠️ `ChallengeScript` 本身**一个字都不改**（**轮 B 的结论**：它保留为**数据源**，
## 4 场遭遇的 `Mission` 形态由文件末尾那一节**派生**出来，见那里的理由）。
## 真正的"壳化"（把数据搬进本文件）留到**轮 C** 出击循环只读 `Mission` 的时点。
##
## ## 本文件里三处"刻意留的坑标"
## 1. `arena` 存**字符串**而不是 `MapDef.Id` —— 见 `map_id_for()` 上面那段（M03 要一张
##    还不存在的图，且**不能**先写成别的图）。
## 2. `Mission.pending` 非空 = 这一关的数据**还会变**（老板还没拍板）。`suite_campaign`
##    钉着"哪些关是暂定的"，拍板后不清掉就会红。
## 3. `Trigger` **不存 `fired`** —— 数据对象是被 7 关共享的，运行时的"已触发"状态写在
##    数据里就是铁律 6 那个"两个写者"的变体（第二局会带着第一局的触发记录）。
##
## ⚠️ 命名按**主题**，不占轮次号 —— 见 `test_runner.gd` 注册表里的红字：
## 本仓库有并行会话，两边都按轮次占号时撞过一次，一个套件被同名文件**整个覆盖**而 runner 照样绿。

# ============================================================ 场地解析
#
# 场地 id（字符串）→ `MapDef.Id`。
#
# ⚠️ **为什么 `Mission` 存字符串 `arena`，而不是直接存 `MapDef.Id`：**
# M03「接货」按 DESIGN §4.2 / §4.8 要落在**低地球轨道**（一张轮 B2 才新建的图）。
# 数据里必须能写"**我指向一张还不存在的图**"，而**不能**先写成别的图凑合 ——
# 后者会在轮 B2 忘了改的时候**静默地跑在太平洋上**：画面不对、玩法不对，**但一处都不报错**
# （这跟 `world_builder` 那个 `match` 的 `_` 兜底是同一类静默失败）。
# ⇒ `map_id_for()` 对**不存在**的场地返回 `-1`，`suite_campaign` 断言
# "`ARENA_PENDING` 里的每一个都还是 `-1`"。轮 B2 一加上 `MapDef.Id.LEO`，
# 那条断言就**变红**，强制回来清账（这是本工程惯用的"用断言逼人回来收口"）。
const ARENA_MAP := {
	"PACIFIC": MapDef.Id.PACIFIC,
	"DAVAO": MapDef.Id.DAVAO,
	"ADELAIDE": MapDef.Id.ADELAIDE,
	"OENBELLI": MapDef.Id.OENBELLI,
	"ULURU": MapDef.Id.ULURU,
	"RANGE": MapDef.Id.RANGE,
	# ★ 轮 B2 清账：低地球轨道**已经建出来了**（`MapDef.Id.LEO` / `Terrain.SPACE`）。
	"LEO": MapDef.Id.LEO,
}
## 还没建出来的场地。**轮 B2 清空了它** —— 清空的那一刻，
## `suite_campaign` 那条"待建场地恰好 1 个"的断言当场变红，强制回来改 M03 的
## `map_id()` / 图名那两条（本工程惯用的"用断言逼人回来收口"）。
##
## ⚠️ 这个常量**保留不删**：它是"数据可以指向一张还不存在的图、但不许先写成别的图凑合"
## 这条规矩的载体。下一张待建图（剧情第二/三章如果有新场地）往这里加一个串就行。
const ARENA_PENDING := []

## 场地 id → `MapDef.Id`；**不存在的场地返回 `-1`**（不许兜到别的图上）。
static func map_id_for(arena: String) -> int:
	if ARENA_MAP.has(arena):
		return int(ARENA_MAP[arena])
	return -1


## 本场地**现在**解析不出图吗？（-1 ⇒ 数据指向一张还不存在的图）
static func is_arena_pending(arena: String) -> bool:
	return map_id_for(arena) < 0


# ============================================================ 渲染期的文本规范化

## ★ **把数据里的 `**强调**` 标记去掉** —— 全工程**唯一**一处做这件事的地方。
##
## ## 为什么数据里会有 `**`
## `Objective.label` 与 `Mission.story` 是按设计稿的口气写的，而设计稿是 Markdown
## ⇒ 「**不得击毙**」这种强调标记**原样落在了字符串里**（轮 A 落数据时带进来的）。
##
## ## 为什么是"渲染时去掉"而不是"改数据"
## 1. 改数据 = 丢掉作者的强调意图。将来真要做富文本（`RichTextLabel` 或自绘粗体）
##    还得把标记加回来 —— 那时就会有人按"现在屏幕上没有 `**`"为理由删掉它。
## 2. 改数据要动 7 关的每一条 `label`/`story`，而这是**纯表现**问题，
##    不该让数据层承担（本文件开头那条"纯数据 + 纯函数"的边界）。
##
## ## 为什么必须**只有一处**
## 同一个函数会被**三个**地方调：简报页的目标清单、简报页的电台预告、
## 战役图脚注的目标摘要（轮 D 的 HUD 目标栏也会）。谁另写一遍 `replace("**", "")`，
## 谁就制造出"有的页面干净、有的页面带着星号"这种**只在某个入口才出现**的难看。
##
## ⚠️ `draw_string()` **没有内联标记**（不是 `RichTextLabel`），所以只有两条路：
## 去掉标记（本函数），或者原样画出星号。本工程选前者。
static func plain(s: String) -> String:
	return s.replace("**", "")


# ============================================================ 尺度常量
#
# 轨道图（`Id.LEO`，轮 B2）用到的两条高度。放在这里而不是 `map_def.gd`：
# 轮 A 只出**数据**，`map_def.gd` 的枚举到轮 B2 才动（DESIGN §9.2 的硬约束：
# 五张旧图的每一个字段都被 `suite_gfx_map` / `suite_round20` 逐图钉着）。
#
# ## ⚠️⚠️ **下面那套"相对参考面"的口径已于 2026-09-29 被推翻**
#
# 老板当天三条：「**近地轨道高度应该和现实高度一致**」「**要能分辨出脚底下是地球**」
# 「**近地轨道没有撞地这种情况**，超出地下边界了就应该强制机体回到近地轨道上」。
#
# ⇒ 轨道图换成**真实高度体系**：地球球顶 = `y = 0`（真地表）、再入线 = **100 km 卡门线**、
#    战斗高度 = **550 km**。下面那段"轮 B2 定稿"**保留作历史** —— 它记着当时为什么把
#    `ORBIT_ALT` 从 100 000 改成 3 200，那个推理本身自洽，只是它建立在
#    "y 是相对参考面"这个前提上；前提一换，结论就得换。
#
# ★ 有两件事**一个字都没变**：
#   · **跨模块**那几条断言继续生效（它们钉的是"两个数必须一起动"，与数是多少无关）；
#   · 三条既有阈值（`CRASH_ALTITUDE` / `PULL_UP_ALTITUDE` / `SAFE_ALTITUDE`）在
#     轨道图上**仍然全部成立** —— 只是现在靠的是"550 km 远高于它们"，
#     而不是"y = 0 就是那条线"。
#
# ## ★ 轮 B2 定稿：这两条数**不是**绝对轨道高度，而是"相对参考面"的高度
#
# 轮 A 按 DESIGN §4.8.4 的字面把它们写成 100 km / 60 km（"轨道高度"），
# 并在 §13 第 14 条挂了"待实测"：**太低 = 永远够不着、太高 = 一开局就一直报警**。
# 轮 B2 真建图时实测出真正的口径 —— **本工程的世界坐标 y 是相对参考面的**：
# 五张图的 `y = 0` 就是海平面 / 地表，而轨道图把 `y = 0` 定义成**再入线**。
#（**不是**"y = 几十万米 = 绝对轨道高度"；完整口径差异见 `MapDef.has_ground`
#  的"语义同构"那段与 DESIGN §10.4。）
#
# 于是在轨道图上：
#   · **再入线 = `y = 0`** —— 它与 `FlightBody.CRASH_ALTITUDE = 24 m` 是同一条线的两面；
#   · **战斗高度 = `WorldBuilder.PLAYER_START_ALT = 3200 m`** —— 那也正是碎片带、
#     大件残骸与运输仓（`WorldBuilder.SPACE_POD_POS`）所在的高度带。
#
# ## ★ 定稿之后"一个数都不用新增"才是重点
# 三条既有阈值**全部自动成立**（它们本来就是相对 `y = 0` 的）：
#   · `FlightBody.CRASH_ALTITUDE = 24`      → "撞海" 与 "再入烧毁" 是同一条线、只换文案
#   · `FlightHUD.PULL_UP_ALTITUDE = 420`    → 出生高度 3200 m 上余量充足，**不会全程报警**
#   · `BanditAI.SAFE_ALTITUDE = 1600`       → 出生高度在安全线之上，敌机**不会一路爬升**
# ⇒ 玩家在轨道图上"贴线飞"的手感，与在海面上"贴海飞"是**同一套阈值**。
#   `suite_space_map` 第 ④ 节把这三条逐条钉住。
#
# ⚠️ 保持**字面数字**（不写 `WorldBuilder.CRASH_ALTITUDE`）是为了本文件**不依赖任何
# `class_name` / autoload**，好在无头下被单独喂断言 —— 与下面 `EARTH_ALT` 同一个理由。
# 三者的绑定由 `suite_campaign` 的**跨模块断言**钉着（`MS.EARTH_ALT ==
# WorldBuilder.PLAYER_START_ALT`、`REENTRY_ALT == 0.0`）。

## 四张地球图的标准交战高度（= `WorldBuilder.PLAYER_START_ALT`，写死在这里是为了
## 让波次数据**不依赖 autoload**，本文件才好在无头下被单独喂断言）。
const EARTH_ALT := 3200.0
## 轨道图的战斗高度（米）= 碎片带 / 大件残骸 / 运输仓所在的高度带。
##
## ★ 2026-09-29：从 `EARTH_ALT`（3 200）改成 **550 000**（= 星链壳层高度，老板选的）。
## ⚠️ **它不能再是 `EARTH_ALT` 的别名** —— 那两个数从这天起不是一回事了
##（地表图的交战高度是 3.2 km，轨道图是 550 km）。
## 与 `WorldBuilder.SPACE_ORBIT_ALT` 的一致性由 `suite_campaign` 的跨模块断言钉着。
const ORBIT_ALT := 550000.0
## 轨道图的**下边界** = 再入线（米）：越过它**不再判死**，而是被推回战斗高度带。
##
## ★ 2026-09-29：从 `0.0`（= `y = 0`，那套"相对参考面"口径）改成 **100 000**
##（= **卡门线**，国际公认的大气层顶）。
##
## ⚠️ **语义也跟着变了**：改前越过它 = `destroy("再入烧毁")`（一样是死，只换了文案）；
## 改后 `FlightBody._check_ceiling()` 在无地面图上走 `_enforce_orbit_floor()` ——
## **不判死**，把机体推回 `ORBIT_ALT`。老板原话：
## 「近地轨道没有撞地这种情况，超出地下边界了就应该强制机体回到近地轨道上」。
const REENTRY_ALT := 100000.0


# ============================================================ 区域（Zone）
#
## 关卡机制：**纯几何体**，只做两件事 —— **判定进入**、**画个边界**（DESIGN §5.4）。
##
## ⚠️ **不进物理世界、不做碰撞体**：每帧只测 `player.global_position` 与它的包含关系。
## 判据是"玩家**中心**在不在里面"，不是"机体有没有碰到边" ——
## 前者可测（一条纯函数），后者是手感（要开游戏才知道）。
class Zone extends RefCounted:
	enum Shape { SPHERE, BOX }
	## 用途标签，只影响**画什么**（不参与任何判定）。
	## `objective` = 目标区 / `danger` = 危险区 / `salvage` = 打捞区 /
	## `extract` = 撤离点 / `trigger` = 只给触发器用（**不画**，见 `visible`）。
	enum Use { OBJECTIVE, DANGER, SALVAGE, EXTRACT, TRIGGER }
	enum Axis { X, Y, Z }

	var id := ""
	## HUD 上那一行（玩家看到的唯一文案）。
	var label := ""
	var shape: int = Shape.SPHERE
	## 用途（§5.4 那张表的三行：目标区 / 危险区 / 演出触发）。
	var use: int = Use.OBJECTIVE
	var center := Vector3.ZERO
	## SPHERE 用。
	var radius := 0.0
	## BOX 用（**全边长**，不是半长 —— 读的时候别再乘 2）。
	var size := Vector3.ZERO
	## 画不画边界。"演出触发"那一类**不画**（§5.4 的表）。
	var visible := true
	## 附带的高度语义（轨道图的"高度带"用；`Axis.Y` = 这是个高度带，
	## 关心的是 y 而不是水平距离）。留空 = 就是普通的球 / 盒。
	var axis: int = -1

	func _init(zid := "", zlabel := "") -> void:
		id = zid
		label = zlabel

	## 球形：**空中点位**用这个（DESIGN §5.2 的 `REACH`「可以是空中的某个点位」）。
	static func sphere(zid: String, zlabel: String, c: Vector3, r: float,
			zuse := Use.OBJECTIVE, zvisible := true) -> Zone:
		var z := Zone.new(zid, zlabel)
		z.shape = Shape.SPHERE
		z.center = c
		z.radius = r
		z.use = zuse
		z.visible = zvisible
		return z

	## 盒形：**目标区 / 高度带**用这个。
	static func box(zid: String, zlabel: String, c: Vector3, s: Vector3,
			zuse := Use.OBJECTIVE, zvisible := true, zaxis := -1) -> Zone:
		var z := Zone.new(zid, zlabel)
		z.shape = Shape.BOX
		z.center = c
		z.size = s
		z.use = zuse
		z.visible = zvisible
		z.axis = zaxis
		return z

	## 玩家中心在不在里面。
	func contains(p: Vector3) -> bool:
		return clearance(p) >= 0.0

	## 到边界的**带符号**余量：> 0 = 在里面（还差这么多），< 0 = 在外面（还差这么多）。
	##
	## 这么设计是为了两边都能用：`contains()` 只看符号（判定进入），
	## HUD 的距离读数直接读它（"距目标 1.2 km"），**不需要第二个函数**。
	func clearance(p: Vector3) -> float:
		var d := p - center
		if shape == Shape.SPHERE:
			return radius - d.length()
		# 盒：取三条轴里最紧的那一条（= 最大内接球的余量）。
		# ⚠️ 用 `min` 而不是"欧氏距离到边" —— 后者在角上会给出正数但实际已经在外面，
		# 而这一关要的是"玩家在不在盒里"，不是"离边的解析距离"。
		var m := minf(size.x * 0.5 - absf(d.x), minf(size.y * 0.5 - absf(d.y),
			size.z * 0.5 - absf(d.z)))
		return m

	## 外接半径（场地越界自检用：`center.length() + outer_radius()` 不许超过 `ARENA_RADIUS`）。
	func outer_radius() -> float:
		if shape == Shape.SPHERE:
			return radius
		return size.length() * 0.5

	func is_height_band() -> bool:
		return shape == Shape.BOX and axis == Axis.Y

	func shape_name() -> String:
		return "球" if shape == Shape.SPHERE else "盒"

	func use_name() -> String:
		match use:
			Use.DANGER:
				return "危险区"
			Use.SALVAGE:
				return "打捞区"
			Use.EXTRACT:
				return "撤离点"
			Use.TRIGGER:
				return "演出触发"
			_:
				return "目标区"


# ============================================================ 打捞物（Collectible）
#
## 打捞物：**有耐久的单位**，不是"捡起来的道具"（DESIGN §5.2 的 `SALVAGE` 三条要点）。
##
## ⚠️ 它**不进物理世界**（§5.4）—— 判定是一条距离比较，不是抓取。
## 玩家开火会**打坏它**（`broken`），于是这一关天然有"打得准"的压力：
## 与 `DESTROY_ZONE` 的"打得狠"**正相反**。
## ⚠️ 轮 56 删掉 M04「打捞」之后，**没有任何关卡在用** `SALVAGE` —— 机制按老板口径
## 留着（`Collectible` / `Zone.Use.SALVAGE` 都在），但它是**死的**。
class Collectible extends RefCounted:
	var id := ""
	var label := ""
	## 归属的打捞区（`Zone.id`）。
	var zone := ""
	## 耐久 0..1；掉到 0 就是**打坏了**。
	var hp := 1.0
	## 已经被捞上来。
	var collected := false
	## 已经被打坏（打坏的不算数）。
	var broken := false

	func _init(cid := "", clabel := "", czone := "", chp := 1.0) -> void:
		id = cid
		label = clabel
		zone = czone
		hp = chp

	static func make(cid: String, clabel: String, czone: String, chp := 1.0) -> Collectible:
		return Collectible.new(cid, clabel, czone, chp)

	## 算不算数（捞上来了**且**没打坏）。
	func counts() -> bool:
		return collected and not broken

	func state_name() -> String:
		if broken:
			return "已损坏"
		if collected:
			return "已回收"
		return "待打捞"

	## 纯函数：一批打捞物里"算数的"有几件 —— 打捞关的目标判定就是它。
	## ⚠️ 轮 56 起没有关卡再用它（M04「打捞」已下架）；留着是给以后可能回来的打捞关。
	## ⚠️ 特意做成**静态**的：判定不依赖任何实例状态，测试可以直接喂
	## `[{collected:true, broken:false}, {collected:true, broken:true}]` 得到 1。
	static func count_ok(items: Array) -> int:
		var n := 0
		for c: Collectible in items:
			if c.counts():
				n += 1
		return n


# ============================================================ 目标（Objective）
#
## 一关的目标（DESIGN §5.2）。老板原话：「任务小目标**不一定得是击毁全部机体**，
## 也可以是**打捞物资**或者是**破坏目标区域**，或者是**到达某些区域**（可以是空中的某个点位）。」
## ⇒ 10 种 `Kind` 就是照着这句话长出来的，其中 `SALVAGE` / `DESTROY_ZONE` / `REACH`
## 三种是老板原话直接点名的新增。
##
## ⚠️ **每一种 `Kind` 的判定都是一条静态纯函数**（`xxx_done(...)`），
## `done()` 只是按 kind 的**分派**。理由：分派会随 kind 增加而变，而每条判定
## 本身是稳定的 —— 测试钉住的是后者（`suite_campaign` 逐种各一组断言）。
class Objective extends RefCounted:
	## ⚠️ **新 kind 一律往末尾加** —— 枚举值是存档与 `objective:<下标>` 触发器认的东西，
	## 中间插一个会把已有的那些整体后移一格（而且一处都不报错）。
	## `STRIKE`（轮 50）就是这么加进来的。
	enum Kind { DESTROY_ALL, DESTROY_TARGET, DESTROY_ZONE, SURVIVE, REACH,
				ESCORT, PROTECT, INTERCEPT, LIMIT, SALVAGE, STRIKE, EVENT }

	var kind: int = Kind.DESTROY_ALL
	## 主要 / 次要。**次要目标没完成不算失败**，只影响评价与军资的观感。
	var required := true
	## HUD 上那一行（玩家看到的唯一文案）。
	var label := ""
	## 目标指向什么：`"wave:2"` / `"unit:gawman"` / `"zone:meeting_hall"` / `"salvage:3"`。
	var target := ""
	## `DESTROY_ALL` 的 N / `INTERCEPT` 的 N / `SALVAGE` 的件数 / `PROTECT` 的架数。
	var count := 0
	## `SURVIVE` 的时长（秒）。
	var secs := 0.0
	## `DESTROY_ZONE` 要破坏的**比例**（0..1）。
	var ratio := 0.0
	## `LIMIT`：要**压到**这条线或以下才算达成（<= 0 表示"不要求压血量"）。
	var min_hp := 0.0
	## `LIMIT`：**不许跌破**这条线（跌破 = 违规）。
	## 0.0 = 只要不击坠就行；> 0 = 连"打到快炸"都不许（M05 的"生俘"）。
	var floor_hp := 0.0
	## `LIMIT`：违规是否**立即判失败**。
	var fail_on_violation := true

	func _init(k := Kind.DESTROY_ALL, klabel := "") -> void:
		kind = k
		label = klabel

	# ---------------------------------------------------------- 工厂
	static func destroy_all(n: int, l: String, req := true) -> Objective:
		var o := Objective.new(Kind.DESTROY_ALL, l)
		o.count = n
		o.required = req
		o.target = "wave:*"
		return o

	static func destroy_target(t: String, l: String, req := true) -> Objective:
		var o := Objective.new(Kind.DESTROY_TARGET, l)
		o.target = t
		o.required = req
		return o

	static func destroy_zone(z: String, r: float, l: String, req := true) -> Objective:
		var o := Objective.new(Kind.DESTROY_ZONE, l)
		o.target = z
		o.ratio = r
		o.required = req
		return o

	static func survive(s: float, l: String, req := true) -> Objective:
		var o := Objective.new(Kind.SURVIVE, l)
		o.secs = s
		o.required = req
		return o

	static func reach(z: String, l: String, req := true) -> Objective:
		var o := Objective.new(Kind.REACH, l)
		o.target = z
		o.required = req
		return o

	static func escort(t: String, l: String, req := true) -> Objective:
		var o := Objective.new(Kind.ESCORT, l)
		o.target = t
		o.count = 1
		o.required = req
		return o

	static func protect(t: String, n: int, l: String, req := true) -> Objective:
		var o := Objective.new(Kind.PROTECT, l)
		o.target = t
		o.count = n
		o.required = req
		return o

	static func intercept(n: int, l: String, req := false) -> Objective:
		var o := Objective.new(Kind.INTERCEPT, l)
		o.count = n
		o.required = req
		return o

	## ★ `LIMIT` 是本设计里最有戏的一种目标（DESIGN §5.2）：它是"剧情"真正进入"玩法"的地方 ——
	## "打赢"反而**是失败**（M04 加乌曼在座舱里；M05 要**生俘**金伯利）。
	static func limit(t: String, min_hp_v: float, floor_hp_v: float, l: String,
			req := true) -> Objective:
		var o := Objective.new(Kind.LIMIT, l)
		o.target = t
		o.min_hp = min_hp_v
		o.floor_hp = floor_hp_v
		o.required = req
		return o

	static func salvage(z: String, n: int, l: String, req := true) -> Objective:
		var o := Objective.new(Kind.SALVAGE, l)
		o.target = z
		o.count = n
		o.required = req
		return o

	## ★ **轮 50 · 2026-09-30**：`STRIKE` —— **对一座指定的建筑开火命中即达成**。
	##
	## 老板原话（M01）：「任务目标应该是对着**联邦内阁下榻的酒店**使用光束步枪射击，
	## 就算完成任务了。」
	## ⇒ 它既不是 `DESTROY_ZONE`（那片区域里**没有**可破坏物，它是纯几何），
	## 也不是 `DESTROY_TARGET`（酒店是**建图里的地标**，不在 `units` 里、
	## 没有 `take_damage()`）—— 判定对象是**打在标记地标上的命中数**。
	##
	## ⚠️ `target` 存的是**组名**（`"davao_hotel"`），不是 `Zone` 的 id：
	## 那座塔的坐标归 `world_builder`（它是几何的唯一真源），数据层再抄一份必然漂移。
	## 组名与建图时 `add_to_group()` 的那个名字**逐字相同** —— `suite_campaign`
	## 有一条跨模块断言把两边钉在一起。
	static func strike(t: String, l: String, req := true) -> Objective:
		var o := Objective.new(Kind.STRIKE, l)
		o.target = t
		o.count = 1
		o.required = req
		return o
	# ---------------------------------------------------------- 逐种纯判定
	## 每一种都只吃**数字**，不吃字典、不吃字典以外的东西 ⇒ 可以逐点验。

	static func destroy_all_done(killed: int, total: int) -> bool:
		if total <= 0:
			return false
		return killed >= total

	static func destroy_target_done(destroyed: bool) -> bool:
		return destroyed

	static func destroy_zone_done(destroyed: int, total: int, ratio: float) -> bool:
		if total <= 0:
			return false
		return float(destroyed) / float(total) >= ratio

	static func survive_done(elapsed: float, secs: float) -> bool:
		return elapsed >= secs

	## ⚠️ `REACH` 不要求"停在里面"：**碰到一次即达成**（否则就是"必须盘旋"，
	## 那是另一种目标，而 DESIGN §5.2 写的是"到达"）。
	static func reach_done(in_zone: bool) -> bool:
		return in_zone

	## `REACH` 的**判定入口**：先查目标自己指向的那个 zone，再退回聚合键。
	##
	## ⚠️ 为什么需要它：`reach_done()` 只吃一个布尔，而 `st["zones"]` 是
	## “zone id → 到过没有”。M03 只有一个 `REACH` 目标时两者等价；但一关有**两个**
	## `REACH` 目标时，单布尔会把“到过 A”当成“到过 B” —— 那是**静默**的错误
	##（目标提前成立，一处都不报错）。⇒ 按 `o.target` 精确查。
	##
	## ⚠️ 字典里没有这个 id ⇒ 退回 `in_zone`：那是给“只喂单键”的调用点留的兼容路径
	##（`suite_campaign` 里就有一条 `{"in_zone": true}`）；运行时 `_end_state()`
	## 喂的**永远是** `zones`。
	static func _reach_hit(o: Objective, st: Dictionary) -> bool:
		var zs: Dictionary = st.get("zones", {})
		if not o.target.is_empty() and zs.has(o.target):
			return bool(zs[o.target])
		return _b(st, "in_zone")

	static func protect_done(alive: int, need: int) -> bool:
		return alive >= need

	static func intercept_done(intercepted: int, need: int) -> bool:
		return intercepted >= need

	static func salvage_done(counted: int, need: int) -> bool:
		return counted >= need

	## `STRIKE`：打够 `need` 发即达成。
	## ⚠️ `need <= 0` ⇒ **假**（"没要求"不等于"已完成"，与 `destroy_all_done(0, 0)`
	## 是同一条纪律：数据写漏要表现成"通不了关"，而不是"一开局就通关"）。
	static func strike_done(hits: int, need: int) -> bool:
		if need <= 0:
			return false
		return hits >= need
	## `LIMIT` 的**违规面**：打死了，或血跌破了下限。
	static func limit_violated(destroyed: bool, hp_ratio: float, floor_hp_v: float) -> bool:
		if destroyed:
			return true
		return hp_ratio < floor_hp_v

	## `LIMIT` 的**达成面**：没违规 **且** 已经把血压到线内。
	## ⚠️ `min_hp <= 0` 时只要求"没被打死" —— 那表示这一关的 `LIMIT`
	## 是纯约束（"别打死它"），不要求打伤。
	static func limit_done(destroyed: bool, hp_ratio: float, min_hp_v: float) -> bool:
		if destroyed:
			return false
		if min_hp_v <= 0.0:
			return true
		return hp_ratio <= min_hp_v

	# ---------------------------------------------------------- 分派
	## `st` 的键（**全部可选，缺的按"还没发生"算**）：
	##   killed / total / destroyed（目标单位已毁）/ zone_destroyed / zone_total /
	##   elapsed / in_zone / protected_alive / protected_need / intercepted /
	##   salvaged / hp_ratio / target_hp_ratio / landmark_hits（`STRIKE` 用）
	static func done(o: Objective, st: Dictionary) -> bool:
		match o.kind:
			Kind.DESTROY_ALL:
				return destroy_all_done(_i(st, "killed"), _i(st, "total"))
			Kind.DESTROY_TARGET:
				return destroy_target_done(_b(st, "destroyed"))
			Kind.DESTROY_ZONE:
				return destroy_zone_done(_i(st, "zone_destroyed"), _i(st, "zone_total"), o.ratio)
			Kind.SURVIVE:
				return survive_done(_f(st, "elapsed"), o.secs)
			Kind.REACH:
				# ★ 轮 55：**优先按目标自己指的那个 zone 查**（`zones` 字典，key = zone id）。
				# 一关有两个 `REACH` 目标时，把两件事聚合成一个布尔会把“到过 A”当成
				# “到过 B” —— 那种错**不会报错**，只会让目标提前成立。
				# ⚠️ 字典里没有这个 id ⇒ 退回聚合键 `in_zone`（只喂单键的老调用点走的兼容路径）。
				return reach_done(_reach_hit(o, st))
			Kind.ESCORT, Kind.PROTECT:
				return protect_done(_i(st, "protected_alive"),
					o.count if o.count > 0 else _i(st, "protected_need"))
			Kind.INTERCEPT:
				return intercept_done(_i(st, "intercepted"), o.count)
			Kind.SALVAGE:
				return salvage_done(_i(st, "salvaged"), o.count)
			Kind.EVENT:
				return bool(st.get("mission_events", {}).get(o.target, false))
			Kind.STRIKE:
				return strike_done(_i(st, "landmark_hits"), o.count)
			Kind.LIMIT:
				return limit_done(_b(st, "destroyed"), _hp(st, "target_hp_ratio"), o.min_hp)
			_:
				return false

	## `LIMIT` 违规了没有。别的 kind 永远是 false（违规只对 `LIMIT` 有意义）。
	static func violated(o: Objective, st: Dictionary) -> bool:
		if o.kind != Kind.LIMIT:
			return false
		return limit_violated(_b(st, "destroyed"), _hp(st, "target_hp_ratio"), o.floor_hp)

	static func kind_name(k: int) -> String:
		match k:
			Kind.DESTROY_ALL:
				return "击毁全部"
			Kind.DESTROY_TARGET:
				return "击毁指定"
			Kind.DESTROY_ZONE:
				return "破坏区域"
			Kind.SURVIVE:
				return "坚持"
			Kind.REACH:
				return "抵达"
			Kind.ESCORT:
				return "护航"
			Kind.PROTECT:
				return "保护"
			Kind.INTERCEPT:
				return "拦截"
			Kind.LIMIT:
				return "限制"
			Kind.SALVAGE:
				return "打捞"
			Kind.EVENT:
				return "战术目标"
			Kind.STRIKE:
				return "射击"
			_:
				return "?"

	static func _i(st: Dictionary, k: String) -> int:
		return int(st.get(k, 0))

	static func _f(st: Dictionary, k: String) -> float:
		return float(st.get(k, 0.0))

	## ⚠️ `hp_ratio` / `target_hp_ratio` 的缺省值是 **1.0（满血）**，不是 `_f()` 的 0.0。
	## 缺省 0 会让"什么都没喂"的字典看起来像"目标血已经被打光了"，
	## 于是 `LIMIT` 的"压到线内 ⇒ 达成"会在**这一关刚开始**就无端成立 ——
	## 与 `Trigger._value()` 里那条注释是同一件事，两处必须一致。
	static func _hp(st: Dictionary, k: String) -> float:
		return float(st.get(k, 1.0))

	static func _b(st: Dictionary, k: String) -> bool:
		return bool(st.get(k, false))


# ============================================================ 事件触发器（Trigger）
#
## 让一局**像一场戏**（DESIGN §5.3），这是"像王牌空战"的技术核心。
##
## 现状是硬编码的 `if`（`main.gd`：`if Game.challenge_wave + 1 < ...: 刷下一波`）；
## 这里把它变成**数据 + 纯函数**：`when` 求值只吃一个字典
## （`{elapsed, kills, hp_ratio, waves_cleared, zones, all_done}`）
## ⇒ 可以逐点验"`elapsed=89.9` 不触发、`90.0` 触发"。
##
## ⚠️ **本类不存 `fired`**：`Trigger` 是**数据**（被 7 关共享、被反复读），
## 把"已触发"写在数据里 = 第二局带着第一局的触发记录（铁律 6 的变体）。
## 运行时自己拿一个 `{mission_id: [已触发的下标]}` 去重（轮 E）。
class Trigger extends RefCounted:
	## 可选标识（日志与"哪一条没触发"的排查用）。
	var id := ""
	## 条件表达式。支持的写法见 `eval()`。
	var when := ""
	## 动作。支持的写法见 `ACTION_KINDS`。
	var do_what := ""
	## 只触发一次（默认）。`false` = 满足条件期间**每帧都算**（音乐/闪烁这类幂等动作用）。
	var once := true

	func _init(w := "", d := "", o := true, tid := "") -> void:
		when = w
		do_what = d
		once = o
		id = tid

	# ---------------------------------------------------------- 条件
	## 支持的 `when` 写法（**全部是纯函数，逐点可验**）：
	##   `elapsed>=90` / `elapsed>90` / `elapsed<=90` / `elapsed<90` / `elapsed==90`
	##   `kills>=2` / `hp<0.5` / `salvaged>=3` / `intercepted>=6` / `zone_ratio>=0.6`
	##   `landmark_hits>=1`   —— 玩家打中**命名地标**（M01 的内阁下榻酒店）的命中数
	##   `wave_cleared:0`      —— 第 0 波**已清空**（= 已清波数 > 0）
	##   `enter:meeting_hall`  —— 玩家进过某个 `Zone`
	##   `all_done`            —— 全部目标达成（运行时算好放进字典）
	##   `all_of:a,b` / `any_of:a,b` —— 组合（**逐点验短路**：`all_of` 里第一个假就返回）
	##   `all_of:(any_of:a,b),c` —— **嵌套要带括号**。不带括号的话逗号有二义
	##                              （分不清"嵌套内部的逗号"与"外层的逗号"），
	##                              ⇒ `eval` 判假、`check_condition` 当场点名，**绝不算一半**。
	##
	## ⚠️ **不支持的写法一律返回 `false`，并且不报错**（纯函数不许崩）。
	## 但"数据里写了不支持的写法"是**要当场抓出来**的 —— 那是 `validate()` 的活。
	static func eval(when: String, st: Dictionary) -> bool:
		var e := when.strip_edges()
		if e.is_empty():
			return false
		if e == "all_done":
			return bool(st.get("all_done", false))
		if e.begins_with("all_of:"):
			var parts := _split_top(e.substr(7))
			if parts.is_empty():
				return false
			for p: Dictionary in parts:
				if not _nested_ok(p):
					return false
				if not eval(str(p["text"]), st):
					return false
			return true
		if e.begins_with("any_of:"):
			var parts2 := _split_top(e.substr(7))
			if parts2.is_empty():
				return false
			for p2: Dictionary in parts2:
				if not _nested_ok(p2):
					return false
				if eval(str(p2["text"]), st):
					return true
			return false
		if e.begins_with("enter:"):
			var zone := e.substr(6).strip_edges()
			# ⚠️ 没给区名 ⇒ 假。否则 `enter:` 会去查 `zones[""]`，
			# 而那个键在运行时的字典里通常是缺省 false —— 看着"对"，其实是无意义条件。
			if zone.is_empty():
				return false
			var zones: Dictionary = st.get("zones", {})
			return bool(zones.get(zone, false))
		if e.begins_with("wave_cleared:"):
			# "第 N 波已清空" = 已清波数 > N（清波数是**计数**，不是下标）。
			# ⚠️ 参数必须是整数：`int("x")` 在 GDScript 里是 **0**（不报错），
			# 于是 `wave_cleared:x` 会变成 `已清 > 0` —— 一个看着合理、其实无意义的条件。
			var n := e.substr(13).strip_edges()
			if not n.is_valid_int():
				return false
			return _i(st, "waves_cleared") > n.to_int()
		var op := _operator_of(e)
		if op.is_empty():
			return false
		var key := e.substr(0, e.find(op)).strip_edges()
		var rhs := e.substr(e.find(op) + op.length()).strip_edges()
		# ⚠️ 键必须在白名单里。否则 `hp_ratios>=0.5`（打错一个字母）会落到 `_value()` 的
		# 缺省分支读到 0.0，然后**静默地恒为假** —— 表现就是"这一关少了半场戏"。
		# 语法不认识要 fail-closed，键不认识同理（这是同一条规矩的两半）。
		if not KEYS.has(key):
			return false
		if not _is_number(rhs):
			return false
		var lv := _value(st, key)
		var rv := rhs.to_float()
		match op:
			">=":
				return lv >= rv
			"<=":
				return lv <= rv
			"==":
				return is_equal_approx(lv, rv)
			">":
				return lv > rv
			"<":
				return lv < rv
		return false

	# ---------------------------------------------------------- 动作
	## 支持的 `do_what`（`kind:arg`）。⚠️ 这张表是**白名单**：
	## 数据里写了一个不在这儿的动作，`validate()` 会点名 ——
	## 否则那个动作会**静默地什么都不做**（一波敌人永远不刷、一句台词永远不说）。
	const ACTION_KINDS := [
		"spawn_wave",   # spawn_wave:2        —— 刷第 2 波
		"spawn",        # spawn:messer:2      —— 临时补一批（不推进波次）
		"radio",        # radio:ken_11        —— 电台台词（轮 E）
		"objective",    # objective:1         —— 把第 1 个目标切成"当前"
		"zone",         # zone:net_close      —— 打开/关闭一个区域（危险区）
		"cutscene",     # cutscene:m04_mid_01 —— 战斗中途播片（暂停 → 播 → 恢复，轮 G）
		"music",        # music:climax        —— 切音乐
		"end",          # end:win / end:lose  —— 结束任务
	]
	## `end:` 只认这两个参数（写错 = 一局永远不结束）。
	const END_ARGS := ["win", "lose"]
	## 允许出现的**数值键**（空字符串 = 这是个特殊形式，不走比较）。
	##
	## ⚠️ `zone_ratio` 是**比例**（0..1），不是"打掉几个"。理由：
	## 一个 `Zone` 里有多少个可破坏物，是**建图时才知道**的（轮 B2/D），
	## 数据里写死"打掉 4 个"会在换一张图之后**静默地永远不成立**。
	## ★ `landmark_hits`（轮 50）：打在命名地标上的**命中数**。缺省 0（`_value()` 的
	## 默认分支）—— 缺省写成 1 会让 `landmark_hits>=1` 在没有地标的关卡里无条件成立。
	const KEYS := ["elapsed", "kills", "hp", "hp_ratio", "waves_cleared", "salvaged",
		"intercepted", "zone_destroyed", "zone_ratio", "protected_alive",
		"target_hp_ratio", "landmark_hits"]

	static func action_kind(do_what: String) -> String:
		var i := do_what.find(":")
		if i < 0:
			return do_what.strip_edges()
		return do_what.substr(0, i).strip_edges()

	static func action_arg(do_what: String) -> String:
		var i := do_what.find(":")
		if i < 0:
			return ""
		return do_what.substr(i + 1).strip_edges()

	## 取 `when` 里某个前缀形式的参数（`when_arg("enter:meeting_hall", "enter:")` → `"meeting_hall"`）。
	## 不是那个前缀就返回空串。给"数据自检"用（`enter:X` 的 X 必须真的存在）。
	static func when_arg(when: String, prefix: String) -> String:
		var e := when.strip_edges()
		if not e.begins_with(prefix):
			return ""
		return e.substr(prefix.length()).strip_edges()

	## 一条 `when` **依赖哪些状态键**（递归展开 `all_of:` / `any_of:` / 圆括号）。
	##
	## ★ **存在的理由**：`eval()` 对"状态字典里没有的键"**不是中性的** ——
	## `>=` 形态缺省 0 ⇒ 恒假（安全的半边），而 `<` 形态缺省 0 ⇒ **恒真**（危险的那半边）。
	## 喂状态的那一方必须能问一句"这条条件依赖的东西我到底有没有"，否则
	## **接线这个动作本身**会把"我还没接"变成"它无条件成立"。
	## 具体是哪一条：M06/M07 的 `protected_alive<1`（全工程没有任何地方统计
	## 受保护单位 ⇒ 缺省 0 ⇒ 一接线那两关**开局即判负**，而且一处都不报错）。
	##
	## 返回的名字一律是 `KEYS` 里的名字，且：
	##   · `hp` **归一成 `hp_ratio`**（`_value()` 就是这么读的：两个名字读同一个键）；
	##   · 特殊形式折成它真正读的那个键 —— `all_done` → `all_done`、
	##     `enter:X` → `zones`、`wave_cleared:N` → `waves_cleared`；
	##   · 看不懂的写法、空串 ⇒ 返回空数组（同 `eval()` 的"不认识就 fail-closed"）。
	static func keys_of(when: String) -> PackedStringArray:
		var out := PackedStringArray()
		_collect_keys(when.strip_edges(), out)
		return out

	static func _collect_keys(e: String, out: PackedStringArray) -> void:
		if e.is_empty():
			return
		if e == "all_done":
			_push_key(out, "all_done")
			return
		# ⚠️ 两个前缀都是 **7** 个字符（`all_of:` / `any_of:`），与 `eval()` 里的
		# `substr(7)` 必须一致 —— 这里对不上的话"依赖哪些键"就会算少（静默）。
		if e.begins_with("all_of:") or e.begins_with("any_of:"):
			# 括号项与裸项都只是"继续往下拆"，`_split_top()` 已经把括号去掉了
			#（`grouped = true` 那一支的 `text` 就是括号里的内容）。
			for p: Dictionary in _split_top(e.substr(7)):
				_collect_keys(str(p.get("text", "")), out)
			return
		if e.begins_with("enter:"):
			_push_key(out, "zones")
			return
		if e.begins_with("wave_cleared:"):
			_push_key(out, "waves_cleared")
			return
		var op := _operator_of(e)
		if op.is_empty():
			return
		var key := e.substr(0, e.find(op)).strip_edges()
		if key == "hp":
			key = "hp_ratio"
		_push_key(out, key)

	static func _push_key(out: PackedStringArray, k: String) -> void:
		if k.is_empty() or out.has(k):
			return
		out.append(k)

	# ---------------------------------------------------------- 数据自检
	## 数据对不对 —— **返回 "" = 这条触发器是好的**，否则返回一句人话。
	##
	## ⚠️ 存在的理由：`eval()` 遇到看不懂的写法**返回 false 而不报错**（纯函数不许崩），
	## 于是"条件永远不成立"会表现成"这一关少了半场戏"，而**没有任何一处报错**。
	## ⇒ 必须有一个地方把坏数据**当场说出来**，`suite_campaign` 逐关调用它。
	static func validate(tr: Trigger) -> String:
		if tr.when.strip_edges().is_empty():
			return "when 是空的（这条永远不触发）"
		if tr.do_what.strip_edges().is_empty():
			return "do_what 是空的（这条触发了也什么都不做）"
		var bad := check_condition(tr.when)
		if not bad.is_empty():
			return "when 写法不认识：%s" % bad
		var k := action_kind(tr.do_what)
		if not ACTION_KINDS.has(k):
			return "do_what 的动作 `%s` 不在白名单里（会静默地什么都不做）" % k
		var arg := action_arg(tr.do_what)
		if arg.is_empty():
			return "do_what 少了参数（`%s:` 后面是空的）" % k
		if k == "end" and not END_ARGS.has(arg):
			return "end 只认 win / lose，写的是 `%s`（写错 = 这一局永远不结束）" % arg
		if (k == "objective" or k == "spawn_wave") and not _is_number(arg):
			return "`%s` 的参数必须是整数，写的是 `%s`" % [k, arg]
		return ""

	## 条件写法自检：返回 "" = 认识，否则返回"不认识的那一段"。
	static func check_condition(when: String) -> String:
		var e := when.strip_edges()
		if e == "all_done":
			return ""
		for pre: String in ["all_of:", "any_of:"]:
			if e.begins_with(pre):
				var inner := e.substr(pre.length()).strip_edges()
				var parts := _split_top(inner)
				# 空的组合，或**括号不配对** —— 两种都是坏数据（`_split_top` 都返回空）。
				if parts.is_empty():
					return e
				for p: Dictionary in parts:
					var txt := str(p["text"])
					if not _nested_ok(p):
						return txt
					var bad := check_condition(txt)
					if not bad.is_empty():
						return bad
				return ""
		for pre2: String in ["enter:", "wave_cleared:"]:
			if e.begins_with(pre2):
				var a := e.substr(pre2.length()).strip_edges()
				if a.is_empty():
					return e
				if pre2 == "wave_cleared:" and not a.is_valid_int():
					return a
				return ""
		var op := _operator_of(e)
		if op.is_empty():
			return e
		var key := e.substr(0, e.find(op)).strip_edges()
		var rhs := e.substr(e.find(op) + op.length()).strip_edges()
		if not KEYS.has(key):
			return key
		if not _is_number(rhs):
			return rhs
		return ""

	# ---------------------------------------------------------- 内部
	## 按**顶层逗号**切分，每个元素是 `{"text": String, "grouped": bool}`。
	##
	## ⚠️ 存在的理由：`all_of:a,b` 与 `all_of:(any_of:c,d),e` 里的逗号**不同义**。
	## 光按逗号切，嵌套那一项会被切碎 —— `any_of:c` 被当成一条完整条件去求值、
	## `d` 被提到外层，**整条表达式静默地算错，且一处不报错**。
	## ⇒ 规矩：**嵌套必须带括号**；没带括号的嵌套由 `_nested_ok()` 拒掉。
	##
	## 括号不配对 / 组合是空的 ⇒ 返回空数组（`eval` 当假、`check_condition` 当坏数据）。
	static func _split_top(csv: String) -> Array:
		var parts: Array = []
		var buf := ""
		var depth := 0
		var bad := false
		for i in csv.length():
			var c := csv[i]
			if c == "(":
				depth += 1
				buf += c
			elif c == ")":
				depth -= 1
				if depth < 0:
					bad = true
					depth = 0
				buf += c
			elif c == "," and depth == 0:
				parts.append(buf)
				buf = ""
			else:
				buf += c
		parts.append(buf)
		if depth != 0:
			bad = true
		if bad:
			return []
		var out: Array = []
		for raw: String in parts:
			var t := raw.strip_edges()
			if t.is_empty():
				continue
			if t.begins_with("(") and t.ends_with(")"):
				var inner := t.substr(1, t.length() - 2).strip_edges()
				if not inner.is_empty():
					out.append({"text": inner, "grouped": true})
			else:
				out.append({"text": t, "grouped": false})
		return out

	static func _is_combo(e: String) -> bool:
		return e.begins_with("all_of:") or e.begins_with("any_of:")

	## 组合里的**一项**能不能用：嵌套必须带括号。
	##
	## `all_of:any_of:kills>=1,elapsed>=1` 会被逗号切碎 ⇒ 拒绝，
	## 而不是"只算出前一半、后一半悄悄提到外层"。正确写法是 `all_of:(any_of:kills>=1,elapsed>=1)`。
	static func _nested_ok(it: Dictionary) -> bool:
		if bool(it.get("grouped", false)):
			return true
		return not _is_combo(str(it.get("text", "")))

	## 找比较运算符。⚠️ **先找两字符的**（`>=` 必须在 `>` 之前找）——
	## 反过来会把 `elapsed>=90` 切成键 `elapsed>`、值 `=90`，然后静默返回 false。
	static func _operator_of(e: String) -> String:
		for op: String in [">=", "<=", "=="]:
			if e.find(op) >= 0:
				return op
		for op2: String in [">", "<"]:
			if e.find(op2) >= 0:
				return op2
		return ""

	static func _is_number(s: String) -> bool:
		if s.is_empty():
			return false
		var t := s
		if t.begins_with("-"):
			t = t.substr(1)
		if t.is_empty():
			return false
		var dot := 0
		for i in t.length():
			var c := t[i]
			if c == ".":
				dot += 1
				if dot > 1:
					return false
				continue
			if c < "0" or c > "9":
				return false
		return true

	## 取某个键的值。⚠️ `hp` / `hp_ratio` 是**同一个东西的两个名字**（前者是设计稿里的写法，
	## 后者是本文件的规范名），且**缺省值是 1.0（满血）而不是 0.0** ——
	## 缺省 0 会让"没喂血量的字典"看起来像"血被打光了"，于是 `hp<0.5` 无端成立。
	static func _value(st: Dictionary, key: String) -> float:
		match key:
			"hp", "hp_ratio":
				return float(st.get("hp_ratio", 1.0))
			"target_hp_ratio":
				return float(st.get("target_hp_ratio", 1.0))
			"zone_ratio":
				return float(st.get("zone_ratio", 0.0))
			_:
				return float(st.get(key, 0.0))

	static func _i(st: Dictionary, k: String) -> int:
		return int(st.get(k, 0))


# ============================================================ 任务（Mission）
#
## 一关 = `Encounter` 的全部字段（一个都没浪费）+ 章节/目标/触发器/播片/军资。
## `DESIGN §5.1` 的原话：「升级，不是重写」。
class Mission extends RefCounted:
	## `"M01"`..`"M12"`。
	var id := ""
	## 章节号（1 / 2 / 3）。序章是**播片**、不是任务，所以没有它的 `Mission`。
	var chapter := 1
	## 章内序号（从 1 开始，HUD 上显示 `MISSION 04`）。
	var index := 1
	var title := ""
	var brief := ""
	## 简报里那句话（`Encounter.story` 的位子）。
	var story := ""
	var player_form := -1
	var player_start_hull_ratio := 1.0
	var player_no_ifield := false
	var enemy_roster: Array[int] = []
	var ally_roster: Array[int] = []
	var chapter_three_mode := ""
	var player_suit: int = SuitProfile.Id.XI
	var enemy_suit: int = SuitProfile.Id.PENELOPE
	## ★ 本关敌机的**速度乘子**（轮 63-9 · D1）。**默认 1.0 ⇒ 其余全部关卡逐位不变。**
	##
	## 为什么需要它：敌机极速有一条跨轮次的回归门 ——「≤ 玩家加力 × 0.92」
	##（`ENEMY_SPEED_CEILING_RATIO`，`suite_round14` 的 27 种组合钉着它）。
	## m02 的玩家机 = **古斯塔夫 00 武装版**（`SuitProfile.by_id(GUSTAV00)` ⇒
	## `gustav00_armed()`，`speed_scale 0.85`；⚠️ **不是**训练靶机那副 0.55 的面孔），
	## 敌机是梅萨（0.92）⇒ 玩家巡航 856.8，而敌机极速被那条门钉在 1182.384
	##（中等 / 困难；简单档敌机自己只有 927.36）⇒ **不按加力永远追不上**。
	##
	## ⚠️ 直接削 `messer_m01().speed_scale` 是**全局**的：小队战 / 对战 / 联机里的
	## 梅萨会一起变慢，而且会动到那张 27 组合不变量表 ⇒ **只能按关削**，所以留这个字段。
	# Per-mission player-only weapon multipliers, applied to a fresh profile.
	var player_saber_damage_mult := 1.0
	## Optional enemy maximum hull fraction; excludes I-field durability.
	var player_saber_enemy_hull_ratio := 0.0
	var player_rifle_damage_mult := 1.0
	var player_rifle_damage_override := 0.0
	var enemy_speed_mult := 1.0
	## 场地 id（**字符串**，理由见 `map_id_for()` 上面那段）。
	var arena := ""
	## 时段预设名：`"night"` / `"dusk_overcast"` / `"space"` / `""`(= 用地图自带的)。
	var time_key := ""
	## 玩家**是谁**（POV 切换关用）。`== ""` ⇒ 哈萨维。
	var pov := ""
	## ★ 本关有没有**发射段演出**（剧情模式 2026-09-30 新增）。
	##
	## `true` ⇒ 出击时**不直接进本关的战场**，而是先播一段
	## "从太平洋的**海面**发射到近地轨道"（2026-09-30：老板砍掉了海上平台，
	## 火箭改从水里升起来 —— 见 `LaunchScript.launch_pos()` / `rest_alt()`），
	## 落到离运输仓 200 km 处，
	## 再把操控交给正常的战斗流程。
	##
	## ## 为什么它必须是**数据**，而不是 `main.gd` 里写 `if id == "M03"`
	## "哪几关有发射段"是**策划决定**，而 `main.gd` 是流程代码。
	## 写死在 main 里的后果是：将来给另一关也加一段（比如"从达沃的机场起飞"）
	## 就得去改流程代码 —— 而流程代码恰恰是最容易改出**静默故障**的地方。
	##
	## ⚠️ 发射段的**起点图**目前是写死的太平洋（`LaunchScript.PAD_*` 那套坐标
	## 只在那张图上有意义）。将来要支持别的起点图，得连带把
	## "起点图 + 起点平台坐标"一起变成数据 —— 现在只有一关用到，不做过度抽象。
	var launch_prologue := false
	## 波次（`ChallengeScript.Wave`）。前一波清空才刷下一波。
	var waves: Array = []
	## 波次推进**由运行时自动做**（前一波清空 ⇒ 刷下一波）。
	##
	## ⚠️ 这条是从现有实现里"升"上来的一个重要语义（DESIGN §5.3）：
	## 现状是 `main.gd` 里一句硬编码的 `if Game.challenge_wave + 1 < wave_count: 刷下一波`。
	## 轮 E 会把它**变成一条默认触发器**（`wave_cleared:N → spawn_wave:N+1`），
	## 于是"不规则的波次"（增援、伏击）就只是"**不注入那条默认触发器**"而已。
	##
	## ⇒ `waves_auto == false` 的关**必须**自带 `spawn_wave:` 触发器，否则第二波永远不出现
	##   （而这一处**不会报错** —— 只会表现成"这一关少了半场"）。`suite_campaign` 双向钉着它。
	var waves_auto := true
	var objectives: Array = []
	var triggers: Array = []
	var zones: Array = []
	## `SALVAGE` 关才有。
	var collectibles: Array = []
	## 本关的基础军资（DESIGN §6.3 的 `Base`）。
	var base_reward := 0
	## 任务自带的目标时间（秒）。`0` ⇒ 用 `MissionRating.par_secs()`。
	var par_secs := 0.0
	## 播片槽位（DESIGN §7.5.1）：`prologue` / `brief` / `mid` / `debrief`。
	## ⚠️ 这里只存**片目 id**，不存文件路径 —— 路径归 `cutscene_script.gd`（轮 G）。
	## 于是"老板的片子还没给"这件事**不会卡住代码**（缺片就静默跳过）。
	var cutscenes := {}

	## ★ 本关的胜利条件是不是"**清场**"（把所有敌机打光）。
	##
	## ⚠️⚠️ **没有敌人、或者胜利条件不是"打光"的关必须显式写 `false`**：
	## `Game._evaluate_end()` 的判胜 = "场上没有敌对单位 + 没有待刷波次"，
	## 而**没有敌人的关开局就满足前半条** —— 此时只要有任何一台单位被销毁
	##（哪怕只是僚机自己撞地）触发 `note_unit_destroyed() → _evaluate_end()`，
	## 这一局就会被**当成打赢**（表现为结算页在没有完成目标时自己跳出来）。
	## ⇒ 这类关的胜负由**目标**给（M01 是"打中酒店"），不由清场给。
	var win_on_clear := true
	## 本关的**友军阵营**（`BattleFormation.Side.*`）。`-1` = 自己一架出击。
	##
	## ★ M01 用它拿到"三块马夫蒂踏板"（老板："开局应该是三台马夫蒂踏板登场的"）——
	## `allies()` 直接复用 `BattleFormation.lineup()`，挂位 / 谁骑板 / 玩家占哪一格
	## 全在那边，这里不另写一套编制。
	var ally_side := -1
	## 友军编队里带**几台 ACE**。
	##
	## ⚠️ 剧情模式默认 **0**：`lineup()` 恒会补一台本阵营 ACE（马夫蒂侧就是柯西），
	## 而第一章 Ξ 还没到手（M01 的台词写着"Ξ 还没到手，今晚飞的是梅萨"）——
	## 让柯西出现在夜色里，等于把 M03「接货」整关的戏提前花掉。
	var ally_aces := 0
	## 玩家出击点的**方位角**（度）：`WorldBuilder.spawn_point()` 那一圈上的极角。
	##
	## ★ M01 / M02 的"镜像"就是靠它（老板："M02 的古斯塔夫出生位置要和 M01 的
	## 梅萨出生位置在**地图的镜像位置**，也就是在地图的另一边"）：
	## 两关一个从这边进、一个从对面进 ⇒ `M02 = M01 ± 180°`（关于图心**点对称**）。
	##
	## 默认 `-95.0` **就是**工程本来写死在 `main.spawn_round()` 里的那个角度 ⇒
	## 不写它的关、以及四种现有模式，出击点**逐位不变**。
	var spawn_angle_deg := -95.0
	## 本关的**命名地标**（要打的那座建筑）在 `world_builder` 里的**组名**。
	## `""` = 这一关没有这类目标。
	##
	## ⚠️ 与建图时 `add_to_group()` 的那个名字**逐字相同**（`suite_campaign` 跨模块钉着）——
	## 打错一个字母的表现是"打中了但目标永远不完成"，**一处都不报错**。
	var landmark_group := ""
	var landmark_beacon_group := "hotel_target"

	## ★ 本关的**开场演出**：佩涅罗佩用光束大炮轰柯西运输仓（2026-09-30 老板原话）。
	##
	## > 「重力这一关我说要先做佩涅罗佩使用光束大炮攻击柯西运输仓，
	## >  然后再是玩家操控柯西和佩涅罗佩对决。」
	##
	## `true` ⇒ 出击时**不直接把操控交给玩家**：镜头先交给运输仓那一侧，
	## 演一段「佩涅罗佩压进攻击位 → 蓄力 → 光束柱照上去 → 仓体起火」，
	## 演完再把操控交给玩家（柯西从原位置出发应战）。时间线在 `PodStrikeScript`。
	##
	## ## 为什么它与 `launch_prologue` 是**两个字段**、不是一个枚举
	## 两段是不同形状的演出：发射段**换图**、玩家操控火箭；这一段不换图、玩家不能动。
	## 合成一个枚举的代价是"这一段到底是哪一种"要去看别处的分支 ——
	## 而 `Mission` 里宁可多一个布尔，也不愿在流程代码里写 `if id == "M04"`。
	##
	## ## ⚠️ 它**不改胜负**（老板 2026-09-30：「不算，只推进剧情」）
	## 运输仓保持「可显示但不可被攻击」（见 `WorldBuilder._build_transport_pod()`）——
	## 演出里的火光与命中是**表演**，不进伤害系统，不产生任何结算读数。
	## ⇒ 所以"运输仓被打爆 = 任务失败"这条**刻意不做**：它没有判定对象。
	var centered_player_pedal := false
	var davao_intro := false
	var pod_strike := false

	## 酒店那条**只读信标**在 `world_builder` 里的组名。
	##
	## ⚠️⚠️ 它是**显示组**，与 `landmark_group`（**打中组**）**不是同一个字符串**：
	##   · `landmark_group` = `"davao_hotel"` —— 塔身那 5 件几何（**能被打中**的那一组）；
	##   · 本常量        = `"hotel_target"` —— 塔尖顶上那只**没有网格**的 `Marker3D`。
	## 两者刻意分开（`suite_landmark` 钉着 `HOTEL_TAG_GROUP != HOTEL_GROUP`）：
	## 合起来的话"显示锚点"就会用**打中判定那组的组员坐标**，框会画在塔腰上乱跳。
	## ⇒ 所以下面 `beacon_groups()` 里**不能**直接把 `landmark_group` 当成组名用。
	const HOTEL_TAG_GROUP := "hotel_target"

	## 运输仓那条**只读信标**在 `world_builder` 里的组名。
	##
	## ⚠️ 与 `WorldBuilder.POD_TAG_GROUP` **逐字相同**（`suite_landmark` 跨模块钉着）。
	## 写错一个字母的表现是"**屏幕上什么都不画**"，一处都不报错 —— 与上面那条同一条陷阱。
	const POD_TAG_GROUP := "pod_target"

	## ★ 本关要不要把**运输仓**标在 HUD / 雷达上（只读信标）。
	##
	## ## 老板口径（2026-10-01）
	## > 「**运输仓只在 M04 和 M03 加进来就好了，其他时候就不要标在地图里**」
	## > 「包括**迪拜塔 M01 的标记，不要在 M02 加进来**」
	##
	## ⇒ 信标从"**按图**显示"改成"**按关**显示"。改前只要那张图上建了信标节点就会画，
	##   于是 **M02**（达沃图）跟着 M01 一起画了酒店、**M06**（太平洋图）跟着 M04
	##   一起画了运输仓 —— 那两处正是老板要拿掉的。
	##
	## ## 为什么是**两个**字段（这个 + `landmark_group`），而不是一张组名表
	## 酒店那一支**不用这个字段**：它的真源是 `landmark_group`（M01 里那个 STRIKE
	## 目标的组名），"打得到的那座建筑"与"要标出来的那座"本来就是同一座 ⇒
	## 再来一张表就是把同一件事写两遍，迟早分家（见 `beacon_groups()`）。
	## 运输仓**没有**这种现成字段：它在 M04 里只是**演出道具**（`pod_strike`）、
	## 在 M03 里是 `Objective.reach("orbit_cargo")` 但目标存的是 **Zone id**
	## （`"orbit_cargo"`）而不是组名 ⇒ 推不出来，只能显式写。
	##
	## ⚠️ 与"**这张图上有没有运输仓**"是两件事：建图侧**一个字没改**
	##（运输仓那件几何照样按图建，LEO / 太平洋各一处）。这里管的是"画不画那个框"，
	## 不是"那件东西在不在" —— 把它绑到地形上就等于让 HUD 的策划需求去改地形数据，
	## 六种模式（对战 / 挑战 / 训练 / LAN…）都得跟着审一遍。
	var pod_beacon := false

	## ★ 本关的**开场曲**（`SoundBank.BGM` 的键；`""` = 照常走战斗曲轮换）。
	##
	## ## 老板口径（2026-10-01）
	## > 「car5p3/PENELOPE 演出 11 秒播放，**然后也作为本关的 bgm**」
	##
	## ⇒ 它不是「再加一首曲子」，而是「**这一关从头到尾就是这一首**」：
	## 开场演出的 11 秒放它，演完不切歌、继续放到战斗结束。
	##
	## ## 为什么是**数据**而不是在流程里写 `if id == "M04"`
	## 与 `pod_strike` / `launch_prologue` 同一条规矩：「哪一关用哪首曲子」是策划决定，
	## 而 `main.gd` 是流程代码。写死的代价是下次给别的关配曲子要去改流程代码 ——
	## 而流程代码恰恰是最容易改出**静默故障**的地方。
	##
	## ## 消费者（**两种舞台，一个字段**）
	## · `main._begin_pod_strike()` —— **有开场演出的关**（M04）：演出**一开始**就起歌，
	##   并且 `Audio.lock_battle_track()` 锁住整关；演完 `_start_fight()` **不重起**
	##   （见那边的 `_strike_bgm_live` 闸门）。
	## · `main._start_fight()` —— **一切没有开场演出的关**（M01/M02/M05…）：
	##   同样是「锁整关 + 起歌」，只是没有演出那 11 秒。
	## 两条路都经 `AudioDirector.lock_battle_track()` ⇒ **整关就这一首**（循环）。
	##
	## ⚠️ 优先级：**本字段 > 设置页「战斗BGM」自选**（关卡作者指定盖过玩家偏好，
	## 否则玩家把设置选成别的、这一关的曲子就没了）。
	## ⚠️ 曲子名走 `SoundBank.BGM` 的键，不在这里写文件名；写了个**池子里没有**的名字
	## 不会静音，只会**锁不上**（退回随机轮换，见 `AudioDirector.bgm_name`）。
	var bgm := ""

	## 这一关里**还没拍板**的点（DESIGN §13）。非空 = 数据还会变。
	## `suite_campaign` 钉着"哪几关是暂定的" —— 拍板后不清掉就会红。
	var pending := ""

	func _init(mid := "", mtitle := "") -> void:
		id = mid
		title = mtitle
		cutscenes = {"prologue": [], "brief": [], "mid": [], "debrief": []}

	# ---------------------------------------------------------- 派生
	func map_id() -> int:
		# ⚠️ 直接读外层常量表，**不走 `MissionScript.map_id_for()`**：
		# 嵌套类按 `class_name` 引用外层类名时，依赖"这个类已经登记进全局类缓存"，
		# 而本仓库是**并行编辑**的 —— 新加的 `class_name` 在编辑器重新扫描之前
		# **不在缓存里**，那一行会当场编译失败（而外层**常量**对嵌套类是可见的，实测过）。
		return int(ARENA_MAP.get(arena, -1))

	func map_name() -> String:
		var mid := map_id()
		return MapDef.by_id(mid).name_cn if mid >= 0 else "（待建）%s" % arena

	func make_player_profile() -> SuitProfile:
		var profile := SuitProfile.by_id_form(player_suit,player_form) if player_form >= 0 else SuitProfile.by_id(player_suit)
		if player_no_ifield: profile.ifield_hp = 0.0
		profile.saber_damage *= player_saber_damage_mult
		if player_saber_enemy_hull_ratio > 0.0:
			profile.saber_damage = SuitProfile.by_id(enemy_suit).hull_hp * player_saber_enemy_hull_ratio
		profile.rifle_damage *= player_rifle_damage_mult
		if player_rifle_damage_override > 0.0:
			profile.rifle_damage = player_rifle_damage_override
		return profile


	func player_suit_name() -> String:
		return make_player_profile().display_name

	func enemy_suit_name() -> String:
		if not enemy_roster.is_empty():
			var counts := {}
			for sid: int in enemy_roster: counts[sid] = int(counts.get(sid,0))+1
			var names: Array[String] = []
			for sid in counts: names.append("%s ×%d" % [SuitProfile.by_id(sid).display_name,counts[sid]])
			return " / ".join(names)
		return SuitProfile.by_id(enemy_suit).display_name

	func wave_count() -> int:
		return waves.size()

	func total_enemies() -> int:
		var n := 0
		for w: ChallengeScript.Wave in waves:
			n += w.count
		return n

	## 玩家不是哈萨维的一关（DESIGN §4.4 的 POV 分配表）。
	func is_pov() -> bool:
		return not pov.is_empty()

	## **POV 还没定**的关。判据是 `pending` 里写的是"玩家机位 / 视角 / POV"这类事。
	##
	## ⚠️ 存在的理由：DESIGN §4.4 那句"哈萨维本人 **4** 关"要把还没定的摘出去，
	## 但**不能简单地用 `pending.is_empty()`** —— `pending` 是个通用字段，
	## M03 的 pending 是"**图**（LEO）待轮 B2 新建"，与 POV 毫无关系，
	## 用它筛会把 M03 一起筛掉（套件当场抓到过：数出来 3 关而不是 4 关）。
	func pov_pending() -> bool:
		return pending.contains("POV") or pending.contains("玩家机位") \
			or pending.contains("视角")

	## 本关**有没有敌机**（波次表空 ⇒ 一架都不刷）。
	##
	## ⚠️ 存在的理由：简报页原来无条件写「敌方：<机型>」，M01 改成纯突袭关之后
	## 那一行会**撒谎**（列出根本没出场的古斯塔夫）。
	func has_enemies() -> bool:
		return not waves.is_empty()

	## 本关的**友军编队**（"你不是一个人出击"）。`ally_side < 0` ⇒ 空表。
	##
	## 复用 `BattleFormation.lineup()` —— 编制规模 / 挂位 / "玩家占哪一格"
	## 全在那边，这里只做两件事：**去掉多带的 ACE**、把结果按 (squad, slot) 顺序交出去。
	## ⇒ `main` 拿到的就是现成的 `Array[BattleFormation.Unit]`，可以直接喂给
	##    `_spawn_side()`（与小队战**同一条撒人路径**，一行新代码都不用写）。
	func allies() -> Array:
		if ally_side < 0:
			return []
		var out: Array = []
		var aces := 0
		for u: BattleFormation.Unit in BattleFormation.lineup(ally_side, player_suit):
			if u.is_ace:
				if aces < ally_aces:
					aces += 1
					out.append(u)
				continue
			out.append(u)
		return out

	## 本关有没有友军编队。
	func has_allies() -> bool:
		return ally_side >= 0 or not ally_roster.is_empty()

	## 本关要在 HUD / 雷达上标出来的**只读信标**组名（`[]` = 这一关一条都不标）。
	##
	## ⚠️ 这是**派生**，不是第二份数据 —— 两条的"要不要"各由本关已经存在的字段给：
	##   · 酒店：`landmark_group` 非空 ⇒ 标。**同一件事的两面**
	##     （"打得到的那座建筑"就是"要标出来的那座"）；分家的表现是最难查的一类：
	##     "**框在那儿、目标却不走**"。
	##   · 运输仓：显式的 `pod_beacon`（它在 M04 里只是演出道具 ⇒ 推不出来）。
	##
	## ⚠️ 组名走**常量**、不直接回读 `landmark_group`：后者是**打中组**的名字，
	## 与本表要的**显示组**名字不同（见上面 `HOTEL_TAG_GROUP` 的注释）。
	##
	## 消费者是 `hud.gd._beacon_shown()`（主视图的框 + 雷达上的方框**共用**它）。
	func beacon_groups() -> PackedStringArray:
		var out := PackedStringArray()
		if not landmark_group.is_empty():
			out.append(landmark_beacon_group)
		if pod_beacon:
			out.append(POD_TAG_GROUP)
		return out

	## 本关要不要在 HUD / 雷达上标出 `group` 这条只读信标。
	##
	## ⚠️ **不是**"这张图上有没有它" —— 见 `pod_beacon` 那段。
	func shows_beacon(group: String) -> bool:
		return beacon_groups().has(group)

	func required_objectives() -> Array:
		var out: Array = []
		for o: Objective in objectives:
			if o.required:
				out.append(o)
		return out

	func zone(zid: String) -> Zone:
		for z: Zone in zones:
			if z.id == zid:
				return z
		return null

	## 本关的目标时间：**任务自带优先**，否则退回 `MissionRating` 的现成分支。
	## ⚠️ `MissionRating.par_secs()` 的四个分支（35/45/55/120）**一个字都没改**
	## （`suite_mission_rating` 钉着它们）—— 本函数只是"自带有就用自带的"。
	## 本关的**全部必做目标**是不是都达成了（= 这一关的胜利条件）。
	##
	## ⚠️ 判定**复用 `Objective.done()`**，不另写一套（"两个写者"那条铁律）；
	## ⚠️ **没目标 ⇒ 没达成**（不是"达成了"）：数据写漏要表现成"通不了关"，
	##    而不是"一开局就通关"——后者是本工程最恨的那类静默失败。
	func all_required_done(st: Dictionary) -> bool:
		var req := required_objectives()
		if req.is_empty():
			return false
		for o: Objective in req:
			if not Objective.done(o, st):
				return false
		return true

	func par() -> float:
		if par_secs > 0.0:
			return par_secs
		return MissionRating.par_secs(Game.MatchMode.CHALLENGE, total_enemies())

	## 某个播片槽位的片目 id（**只读副本**）。
	func slot(slot_name: String) -> Array:
		var v: Variant = cutscenes.get(slot_name, [])
		return v if v is Array else []

	func cutscene_count() -> int:
		var n := 0
		for k: String in cutscenes.keys():
			n += slot(k).size()
		return n


# ============================================================ 七关数据
#
# ## 数据从哪来（**每一个字都来自老板的口述**，不是我的推断）
# 关次与顺序：DESIGN §4.1 / §4.2（"达沃空袭在太平洋群岛前面啊" + 三章清单）。
# POV：DESIGN §4.4（"偶尔也要扮演雷恩艾姆和加乌曼，或者是一些古斯塔夫的无名驾驶员"）。
# 目标类型：DESIGN §5.2（"不一定是击毁全部机体……打捞物资……破坏目标区域……到达某些区域"）。
# 播片配额：DESIGN §4.2 的 `播片 B/M/D` 一列（**配额建议，不是素材清单**）。
#
# ## ⚠️⚠️ M01 / M02 **不再共用波次**（轮 50 · 2026-09-30，老板推翻）
#
# 原来这两关是「同一场达沃空袭、两个座舱」：波次形状**逐字段相等**（只差机型），
# 于是 "M01 里你打的敌机 = M02 里你开的机" 这件事由**构造**保证，不靠约定。
#
# **现在不是了**。老板两句话把两关拆成两种玩法：
#   · M01 = **纯突袭**（一架敌机都没有，见 `m01()`）；
#   · M02 = 拦截（一架梅萨）。
# ⇒ 两关的波次**故意不同**，共用常量跟着拆掉。
#
# ⚠️ 旧常量 `DAVAO_WAVE_SHAPE` **不保留**：留着它，下一个人（或下一次评审）
# 会以为"两关共用波次"这条口径还在 —— 本仓库最恨的就是这种"注释说还在"。
# ⚠️ 同理，两关的"玩家机 ↔ 敌机互换"那两条断言**照旧成立**（`player_suit` /
# `enemy_suit` 一个字没动，M01 只是不把敌机撒出来而已）——
# 所以 `suite_campaign` 里那两条留着，被删掉的只有"波次同形"那一段。

## M02 那一波梅萨的形状（不含机型）：**只出 1 架**。
## 老板原话：「古斯塔夫的任务就是**击溃一台梅萨**了。」
##
## ⚠️ `aggr` 从 `false` 改成 `true`（轮 63-9 · D1 的「增强一点他的进攻欲望」）。
## `true` ⇒ `main._spawn_wave()` 里那行 `if wave.aggressive: ai.set_state(ATTACK)`
## 会命中：它**一出场就压下来打**，而不是在高空慢慢悠悠转一圈才俯冲
##（`bandit_ai.gd` 的用法见 `main.gd` 撒机处那段注释）。
## 同一轮里本关还削了速度（`Mission.enemy_speed_mult = 0.75`）——
## 两件事**同向**：追得上 + 它主动来。
const DAVAO_INTERCEPT_SHAPE := [
	{"count": 1, "alt": EARTH_ALT, "spread": 62.0, "aggr": true},
]

static func _davao_waves(enemy: int) -> Array:
	var out: Array = []
	for s: Dictionary in DAVAO_INTERCEPT_SHAPE:
		out.append(ChallengeScript.Wave.new(int(s["count"]), enemy, float(s["alt"]),
			float(s["spread"]), bool(s["aggr"])))
	return out


static func all() -> Array:
	return [m01(), m02(), m03(), m04(), m05(), m06(), m07(), m08(), m09(), m10(), m11(), m12()]


static func by_id(id: String) -> Mission:
	for m: Mission in all():
		if m.id == id:
			return m
	return null


static func for_chapter(chapter: int) -> Array:
	var out: Array = []
	for m: Mission in all():
		if m.chapter == chapter:
			out.append(m)
	return out


## 玩家不是哈萨维的关（DESIGN §4.4）。
static func pov_missions() -> Array:
	var out: Array = []
	for m: Mission in all():
		if m.is_pov():
			out.append(m)
	return out


## 数据里还留着"待拍板"标记的关（见 `Mission.pending`）。
static func pending_missions() -> Array:
	var out: Array = []
	for m: Mission in all():
		if not m.pending.is_empty():
			out.append(m.id)
	return out


# ------------------------------------------------------------ M01 夜袭达沃
#
# ★★ **轮 50 · 2026-09-30：老板把这一关整个改了**（原话）：
#   「第一张夜袭达沃**不应该设置敌人**，夜袭达沃，开局应该是**三台马夫蒂踏板登场**的
#     （玩家的加乌曼是其中一台）。任务目标应该是**对着联邦内阁下榻的酒店使用光束步枪
#     射击**，就算完成任务了。」「可以是达沃中心最高的楼，就是我让你参考迪拜塔建的那个。」
#
# ⇒ 三件事**必须一起变**，缺一条这一关就不成立：
#   ① **一架敌机都没有**（`waves = []`）—— 原来那"三台古斯塔夫 00"整批删掉；
#   ② **友军编队** = 马夫蒂 3 块踏板 × 每块 2 台梅萨（`ally_side` + `ally_aces = 0`），
#      玩家占其中一块的**领机位**（`BattleFormation.lineup()` 保证他骑得到板）；
#   ③ **胜利条件不是清场**（`win_on_clear = false`）—— 由 `STRIKE` 目标给：
#      对**达沃中央针塔**（= 内阁下榻的酒店、`world_builder` 里那座迪拜塔式尖塔，
#      全图最高的东西）开一发光束步枪，这一关就完了。
#
# ⚠️ 原来那两条目标（击毁三台古斯塔夫 / 撤出达沃空域）**都撤掉了**：
# 老板说的是"射击就算完成"，多留一条**必做**目标等于"打中酒店还通不了关"。
# ⚠️ `enemy_suit` **留着不动**：它是"今夜对面是谁"的资料栏读数，而且是
# `suite_campaign` 那两条"两个座舱"断言（M01 玩家机 == M02 敌机）的一半 ——
# 删掉它会让那两条**静默地变成自我比较**（永远绿）。
static func m01() -> Mission:
	var m := Mission.new("M01", "夜袭达沃")
	m.davao_intro = true
	m.chapter = 1
	m.index = 1
	m.arena = "DAVAO"
	m.time_key = "night"
	m.player_suit = SuitProfile.Id.MESSER_M01
	m.enemy_suit = SuitProfile.Id.GUSTAV00
	m.pov = "加乌曼·诺比尔"
	m.brief = "达沃 · 夜间突袭 · 梅萨队"
	m.story = "三块板，六台梅萨，贴着海面压进达沃。" \
		+ "今夜的活口令只有一句：内阁下榻的那座塔，打它一枪。"
	# ---- ① 没有敌人 ----
	# ⚠️ **不是"波次是空的"这么简单**：`MissionScript.to_encounter()` 拿走的
	# `waves` 也是空的 ⇒ `main.spawn_challenge()` 一架都不撒（见那里的注释）。
	m.waves = []
	# ---- ② 胜利条件不是清场 ----
	m.win_on_clear = false
	# ---- ③ 友军编队：马夫蒂 3 块踏板（玩家在其中一块上）----
	m.ally_side = BattleFormation.Side.MAFTY
	m.ally_aces = 0
	# ---- ④ 要打的那座建筑（组名与 `world_builder.HOTEL_GROUP` 逐字相同）----
	m.landmark_group = "davao_hotel"
	m.objectives = [
		Objective.strike("davao_hotel", "用光束步枪射击内阁下榻的酒店"),
	]
	# ⚠️ 这一关**没有 Zone**：原来那个 `davao_port`（港口目标区）是给
	# `destroy_zone` 目标用的，而那条目标已经撤了 —— 留着它就是一块
	# "写着目标区、却没有任何目标指向它"的假数据。
	m.zones = []
	m.triggers = [
		Trigger.new("elapsed>=4", "radio:davao_sibet_01", true, "m01_open"),
		# 舰桥放飞"高尔夫/芬萨"那一对 —— 原片 07-01 的出击呼叫（`h1:0622`）。
		Trigger.new("elapsed>=20", "radio:davao_bridge_01", true, "m01_hail"),
		# 加乌曼（= 玩家自己）"傻子才把7名阁僚留在达沃睡觉觉"（`h1:0613`）——
		# **这一句点着这一关的目标**：酒店里那 7 名阁僚。
		Trigger.new("elapsed>=45", "radio:davao_gawman_01", true, "m01_gawman"),
		# ★ 命中那一刻：他对着被炸的那座塔说「向诸位陪葬者的在天之灵表示哀悼」（`h1:0623`）。
		Trigger.new("landmark_hits>=1", "radio:davao_gawman_02", true, "m01_hit"),
		Trigger.new("all_done", "end:win", true, "m01_win"),
		Trigger.new("hp<0.25", "end:lose", true, "m01_lose"),
	]
	m.cutscenes = {"prologue": [], "brief": ["m01_brief_01"], "mid": [],
		"debrief": ["m01_debrief_01"]}
	# ★ 2026-10-01（轮 59）老板：「TRACER 作为 M01 的 bgm」。
	# M01 开场由 `davao_intro` 接管，演出与战斗连续使用本关曲；
	# 靠 `AudioDirector.lock_battle_track()` 锁**整关**（循环、不换曲）。
	# ⚠️ 曲子名必须在 `SoundBank.STORY_BATTLE_TRACKS` 里 —— 不在池里
	# 只会**锁不上**（退回随机），且一行报错都没有（`suite_mission_bgm` 钉着这条）。
	m.bgm = "tracer"
	m.base_reward = 260
	return m


# ------------------------------------------------------------ M02 喀耳刻出击
#
# ★★ **轮 50 · 2026-09-30：老板两句改动**（原话）：
#   「M02 的古斯塔夫出生位置要和 M01 的梅萨出生位置在**地图的镜像位置**，
#     也就是在地图的另一边，古斯塔夫的任务就是**击溃一台梅萨**了。」
# ⇒ ① `spawn_angle_deg = 85.0`（= M01 的 −95° 关于图心**点对称**，正好差 180°）；
#    ② 波次 3 台 → **1 台**，目标从"迎击梅萨队 + 守住达沃港"减成一条
#       **"击溃一台梅萨"**。
#
# ⚠️ "守住达沃港"（`protect`）**撤掉了**：老板说的是"任务就是击溃一台梅萨"。
# 多留一条必做目标 = "打掉那台梅萨却不给过关"，与 M01 那边同一条理由。
static func m02() -> Mission:
	var m := Mission.new("M02", "喀耳刻出击")
	m.player_saber_enemy_hull_ratio = 0.30
	m.player_rifle_damage_override = 50.0
	m.chapter = 1
	m.index = 2
	m.arena = "DAVAO"
	m.time_key = "night"
	m.player_suit = SuitProfile.Id.GUSTAV00
	m.centered_player_pedal = true
	m.enemy_suit = SuitProfile.Id.MESSER_M01
	m.pov = "喀耳刻部队的无名驾驶员"
	m.brief = "达沃 · 夜间防空 · 喀耳刻部队"
	m.story = "对面那支马夫蒂的板队从城市的另一头进来了。" \
		+ "你从这一头迎着压上去——打掉一台就够。"
	# ★ 轮 63-9 · D1：本关专属的速度削弱（P5 拍板 ×0.75）。
	#
	# 玩家 = 古斯塔夫 00 武装版（`speed_scale 0.85`）：巡航 **856.8**、加力 **1285.2**。
	# 天花板 = 1285.2 × 0.92 = **1182.384**。
	# 敌机极速 = min(梅萨自身 927.36 × 难度倍率, 1182.384)：
	#   简单 **927.36**（敌机自己的上限先咬住）· 中等 / 困难 **1182.384**（天花板咬住）
	#   ⇒ 相对玩家巡航 = 1.082 / **1.380** / 1.380 倍 —— 这就是「追不上」的根。
	# ×0.75 后：**695.52 / 886.788 / 886.788** ⇒ 相对巡航 0.812 / **1.035** / 1.035 倍。
	# 加力接近速度（中等 / 困难）：**102.8 → 398.4 m/s（3.87 倍）**；
	#   以 39.6 km 的出生间距算，纯追击最坏情况 **385 s → 99 s**。
	#
	# ⚠️ 为什么不是削 `messer_m01().speed_scale`：那是**全局**的（见字段注释）。
	m.enemy_speed_mult = 0.75
	m.waves = _davao_waves(m.enemy_suit)
	# ★ 出击点 = M01 的**镜像**（关于图心点对称）。两关一个从这边进、一个从对面进。
	m.spawn_angle_deg = 85.0
	m.objectives = [
		Objective.destroy_all(1, "击溃一台梅萨"),
	]
	# ⚠️ 这一关也**没有 Zone** 了：唯一那个 `davao_port`（守备区）是给 `protect`
	# 目标用的，而那条目标已撤 —— 留着它就是"写着目标区、没有目标指向它"的假数据。
	m.zones = []
	m.triggers = [
		Trigger.new("elapsed>=4", "radio:davao_ken_01", true, "m02_open"),
		# 对面那台梅萨在喊 —— 按原片，达沃这一夜被打下来的正是加乌曼（`h1:0688`）。
		Trigger.new("elapsed>=20", "radio:davao_gawman_03", true, "m02_messer"),
		Trigger.new("elapsed>=40", "cutscene:m02_mid_01", true, "m02_mid"),
		# 击溃之后：凯奈斯那句「这可是第一个马夫蒂的俘虏」（`h1:0743`）——
		# 它同时把 M04 连上（那个俘虏就是后来佩涅罗佩座舱里的人质）。
		Trigger.new("kills>=1", "radio:davao_ken_02", true, "m02_ken"),
		Trigger.new("all_done", "end:win", true, "m02_win"),
		Trigger.new("hp<0.2", "end:lose", true, "m02_lose"),
	]
	m.cutscenes = {"prologue": [], "brief": ["m02_brief_01"], "mid": ["m02_mid_01"],
		"debrief": []}
	m.base_reward = 260
	return m


# ------------------------------------------------------------ M03 接货
static func m03() -> Mission:
	var m := Mission.new("M03", "接货")
	m.chapter = 1
	m.index = 3
	m.arena = "LEO"
	m.time_key = "space"
	m.bgm = "car5p3"
	m.player_suit = SuitProfile.Id.MESSER_CMD
	# ★★ 2026-09-30 · 轮 52：老板
	# > 「**上太空之后开的是指挥官型梅萨，不是柯西 / 柯西还在运输仓里面，
	# >   怎么开，应该开的是指挥官型梅萨**」
	# ⇒ 玩家机 `Id.XI` → `Id.MESSER_CMD`，连带 `brief` / `story` / 台词一起改
	#（原来那三处都在说"Ξ 第一次启动"，而那正是这一关**做完的事**，
	# 不是**开去做的事**：柯西在运输仓里，玩家是开梅萨上去把它接回来的）。
	#
	# ⚠️ 这条同时修掉一个叙事矛盾：这一关的目标是
	# `Objective.reach("orbit_cargo")`（**抵达**运输仓接收点）。
	# ★ 轮 55 起**只剩这一条** —— 原来并列的“击退一台古斯塔夫00”随敌机一起撤了。
	# 让玩家开着柯西去"接柯西"是说不通的 —— 运输仓里那台才是柯西。
	#
	# ★ 2026-09-30 · 轮 51：老板口径「敌人配置里不要有王牌机（佩涅罗佩和阿利宙斯）」
	#   （⚠️ 他口述的关号与代码 id 差一位 ⇒ 实际清的是**当时**的 M03 / M07；
	#    换到轮 56 顺位后的编号就是 M03 / M06，也就是这里写的这两个）
	# ⇒ 本关的对手从**佩涅罗佩**换成量产机：数量、高度、目标形状**一个字没动**，只换 `suit`。
	# ⚠️ M04「重力」的佩涅罗佩**保留**（那是宿敌正戏），M07 的阿利宙斯也不动 ——
	#    那个白名单的可执行形式在 `tests/suite_mission_aces.gd`。
	# ★ 轮 55 追加（老板原话）：「**接货这一关不要设置敌人，将机体靠近柯西收纳仓
	#   0.6 km 内就可以视作任务成功**」⇒ 本关现在**零敌机**（`waves = []`）。
	#   ⚠️ `enemy_suit` 这个字段**按 M01 的惯例留着**：它是“这一关的对手是谁”的元数据，
	#   而 `mission_brief` 按 `has_enemies()`（= 波次表非空）判空 ⇒ 屏幕上**不会**
	#   出现“敌方：古斯塔夫00”这种假话。字段本身不再有任何运行时行为。
	m.enemy_suit = SuitProfile.Id.GUSTAV00
	m.brief = "低地球轨道 · 无重力 · 接驳柯西运输仓"
	# ★ 2026-09-30：本关**多了一段前置演出** —— 玩家要自己把马夫蒂火箭
	# 从太平洋的**海面**开到近地轨道（发射段：越过卡门线时在后台把图换成轨道图），
	# 落到离运输仓 200 km 处，再从那里飞过去。
	#
	# ⚠️ 它顺带把这一关**本来就有的结构**讲圆了：`orbit_cargo` 是
	# `Objective.reach()` + `Zone.Use.EXTRACT`（**抵达**运输仓接收点），
	# 也就是说玩家本来就该"从别处飞过来"。200 km 的进场距离正是这件事要的尺度
	#（改前玩家在 46.6 km 外出生，"飞过去"只有十几秒，读起来像"出生就贴脸"）。
	m.launch_prologue = true
	# ⚠️ 原来那句“另一台古斯塔夫00 也已经把热源锁上了”**随敌机一起下架** ——
	#    留着它就是让简报页**撒谎**（说了有敌人，场上一个字都没有）。
	m.story = "运输仓从再入线外侧掠过。柯西就在里面 —— 贴着它飞过去，就算接上了。"
	# ---- ① 没有敌人 ----
	# 老板原话（轮 55）：「**接货这一关不要设置敌人**」。
	# 与 M01 同一条：**不是“波次是空的”这么简单** —— `to_encounter()` 拿走的
	# `waves` 也是空的 ⇒ `main.spawn_challenge()` 一架都不撒。
	#
	# ⚠️ 轮 51 那句“这一波出量产机、数量 1、与 `destroy_all(1, …)` 自洽”**整段作废**：
	#    它描述的是一支已经不存在的部队（`suite_mission_aces` 里那几条波次断言同步改了）。
	m.waves = []
	# ---- ② 胜利条件不是清场 ----
	# ⚠️⚠️ 这一行是**必须**的：没有敌人的关开局就满足“场上无敌对单位”，
	# 此时任何一台单位被销毁（哪怕僚机自己撞地）都会触发
	# `note_unit_destroyed() → _evaluate_end()` 把这一局**当成打赢**
	#（表现：结算页在没完成目标时自己跳出来）。⇒ 这一关的胜负改由**目标**给。
	m.win_on_clear = false
	# ---- ③ 目标只剩一条：飞到运输仓跟前 ----
	# ⚠️ `destroy_all(1, "击退古斯塔夫00")` 随敌机一起撤 —— 留一条“打掉一台根本
	#    不存在的敌机”的**必做**目标 = 这一关**永远打不赢**，而且一处都不报错。
	m.objectives = [
		Objective.reach("orbit_cargo", "抵达运输仓接收点"),
	]
	# ★ 2026-10-01 老板：「**运输仓只在 M04 和 M03 加进来就好了，其他时候就不要
	#   标在地图里**」⇒ 这一关是两关之一，标。
	# ⚠️ 别拿"图是 LEO"当判据 —— 自由挑战 / 训练也可能落在 LEO 上，
	#   而那些局里没有任何一关在"接这只仓"（见 `Mission.pod_beacon`）。
	m.pod_beacon = true
	m.zones = [
		# ★ 轮 55：半径 **4000 → 600**（老板：「靠近柯西收纳仓 **0.6 km** 内就可以
		#   视作任务成功」）。球心 `Vector3(0, ORBIT_ALT, 0)` 与建图的
		#   `WorldBuilder.SPACE_POD_POS` **逐位相同** ⇒ “0.6 km”读作“离运输仓 0.6 km”。
		# ⚠️ 判定是“**到过**”（锁存），不是“停在里面”：玩家以 600+ km/h 掠过时，
		#   锁存让“进去那一帧”不会被帧相位吃掉（口径见 `Game.zone_reached`）。
		Zone.sphere("orbit_cargo", "运输仓接收点", Vector3(0.0, ORBIT_ALT, 0.0),
			600.0, Zone.Use.EXTRACT),
		Zone.box("reentry_line", "再入线", Vector3(0.0, REENTRY_ALT, 0.0),
			Vector3(120000.0, 2000.0, 120000.0), Zone.Use.DANGER, true, Zone.Axis.Y),
	]
	m.triggers = [
		Trigger.new("elapsed>=6", "radio:leo_ira_01", true, "m03_open"),
		Trigger.new("enter:orbit_cargo", "radio:leo_raymond_01", true, "m03_dock"),
		Trigger.new("enter:orbit_cargo", "cutscene:m03_mid_01", true, "m03_mid"),
		# ★ 轮 55：原来这条是「联邦巡逻机」在喊（自编台词）。剧本 07-17 那一场
		# **没有联邦侧的台词**，报敌情的是哈萨维（`h1:1117`）—— 换成他的原话。
		# ⚠️ 老板那条口径（M03/M06 敌方不许出现王牌机）不受影响：这是**我方**的通话。
		Trigger.new("elapsed>=60", "radio:leo_hathaway_01", true, "m03_warn"),
		Trigger.new("all_done", "end:win", true, "m03_win"),
		Trigger.new("hp<0.2", "end:lose", true, "m03_lose"),
	]
	m.cutscenes = {"prologue": [], "brief": ["m03_brief_01"], "mid": ["m03_mid_01"],
		"debrief": []}
	m.base_reward = 320
	# ★ 轮 B2 **清账**：原来这行写着
	# "图（LEO）待轮 B2 新建；波次高度与再入线高度待实测（DESIGN §13 第 12/14 条）"。
	# 轮 B2 把两件事都做完了 ——
	#   ① `MapDef.leo()` / `WorldBuilder._build_space()` 把低地球轨道建出来了；
	#   ② `ORBIT_ALT` / `REENTRY_ALT` 定稿（不再是绝对轨道高度，见那两个常量的推导），
	#      而且**波次高度与运输仓所在的高度带对上了**（`suite_campaign` 用
	#      "目标球罩住 `WorldBuilder.SPACE_POD_POS`" 这条跨模块断言钉着）。
	# ⇒ 这一关**不再"还会变"**，`pending` 清空（`PENDING_NOW` 那条门会自动跟着收口）。
	# ⚠️ 剩下的"待拍板"只与玩法细节有关（第三阶段演出），要另立待办时**再写回来**，
	#    不要留一个"因为已经做完了"而变成谎话的 pending。
	m.pending = ""
	return m


# ------------------------------------------- （原 M04「打捞」· 2026-09-30 轮 56 删除）
#
# ★ 老板原话：「**把 M04 删掉，M05 改名「重力」然后包括后面的 M05 M06 M07 编号都要
#   顺位往前**」。⇒ 这一关（太平洋海面 · 打捞 Ξ 的整备物资）**整个下架**，
#   后面的关号一律前移一位（旧 M05→M04、旧 M06→M05、旧 M07→M06、旧 M08→M07）。
#
# ⚠️ 打捞这套**机制**按老板口径**保留**（`Objective.salvage()` / `Collectible` /
#   `Zone.Use.SALVAGE`「打捞区」）—— 但轮 56 起**没有任何关卡在用它们**。
#   `suite_campaign` 那条"打捞关的场上打捞物要够"的自检因此**空转**（见那里的注释）。
# ⚠️ 这一关自己的东西**随关卡一起下架**（留着就是孤儿，`suite_comms` 会红）：
#   · 电台 `sea_ira_01`（"Ξ的后备组件只回收了一半" `h1:1256`）
#     `sea_ira_02`（"朱莉娅 应该先整理备件吧" `h1:1233`）
#   · 过场槽位 `m04_brief_01` / `m04_mid_01` —— ⚠️ 这两个 id **已被新的 M04「重力」接管**
#     （它是老 M05 顺位上来的，槽位名天生就是 `m04_*`）⇒ 没有留白，只是换了主人。
#   两句台词正文与出处抄在交付说明里 —— 将来若要复活打捞关可以直接取回。
# ⚠️ 它的 `pending`（"POV 驾驶员（艾姆拉尔妲）待老板拍板"，DESIGN §13 第 1 条）
#   随之作废：没有这一关，就没有"这一关的驾驶员是谁"这个问题。
# ------------------------------------------------------------ M04 重力
static func m04() -> Mission:
	var m := Mission.new("M04", "重力")
	m.chapter = 1
	m.index = 4
	m.arena = "PACIFIC"
	m.time_key = "night"
	m.player_suit = SuitProfile.Id.XI
	m.enemy_suit = SuitProfile.Id.PENELOPE
	m.brief = "太平洋 · 高空拦截 · 加乌曼在他们手里"
	# ★ 2026-09-30 · 轮 53：老板（截图）「这个描述改一下，改成 **击败佩涅罗佩**」，并在追问里拍板「**文案 + 判定一起改**」
	# ⇒ 原来那条 `Objective.limit`（压到 30% 以下、**不得击坠**）连同“加乌曼在那台机里”的设定一起作废。
	# ★ 2026-10-01：运输仓升到 10 000 m（`WorldBuilder.PACIFIC_POD_POS`）之后，
	# 原句「**贴着海面飞**」与画面矛盾（仓在云顶之上、玩家在低空）
	# ⇒ 这一关的口径从「贴海」改成「**高空拦截**」。
	m.story = "Ξ 从云下顶上来。运输仓在头顶挨了一炮 —— " \
		+ "对面那台灰色的就是佩涅罗佩，把它打下去。"
	# ★ M04 的波次 = 现有那场遭遇，**逐字搬**（DESIGN §4.3）。
	m.waves = ChallengeScript.xi_vs_penelope().waves
	# ★ 2026-10-01 老板：「运输仓**只在 M04 和 M03** 加进来就好了」⇒ 这一关是另一关。
	# ⚠️ 这一关的运输仓**不是目标**（它是 `pod_strike` 那段演出的道具、不可被攻击）
	#   ⇒ 它**只能**靠这个字段说"要把我标出来" —— 目标表里一个字都没有它。
	# ⚠️ 别改成按图判：太平洋图还被 M06「海上袭击」用着，而那一关**不**该有这只仓
	#   （老板同一句里的"其他时候就不要标"）。
	m.pod_beacon = true
	# ★ 轮 53：一条目标，且判定真的是“击坠即达成”。
	m.objectives = [
		Objective.destroy_all(1, "击败佩涅罗佩"),
	]
	# ⎠ `rescue_point`（EXTRACT）已随那条 SALVAGE 目标一并撤掉。
	m.zones = [
		# ★ 2026-10-01：名字里的「贴海」随同一口径撤掉（id 与球心/半径**不动** ——
		# 它管的是"玩家低空穿过时触发电台"，与运输仓的高度是两件事）。
		Zone.sphere("sea_window", "低空交战空域", Vector3(0.0, 200.0, 0.0),
			4000.0, Zone.Use.TRIGGER, false),
	]
	m.triggers = [
		Trigger.new("elapsed>=20", "radio:duel_lane_01", true, "m04_lane"),
		Trigger.new("elapsed>=45", "cutscene:m04_mid_01", true, "m04_mid1"),
		Trigger.new("enter:sea_window", "radio:duel_lane_02", true, "m04_lane2"),
		# ⚠️ 加乌曼**确实**被绑在那台佩涅罗佩的座舱里（`h1:1185` 哈萨维问"是叛变还是被当做挡箭牌"、
		# `h1:1194` "没有人质就无法战斗的可怜虫"）⇒ 这一拍是他喊的，不是改编。
		# ⚠️ 但 `target_hp_ratio` 这个键**当前没有源**（`Game.trigger_keys_sourced()` 里故意不声明）
		# ⇒ 这条触发器现在会**整条跳过 + push_warning**。台词本身是对的，缺的是"血量读数"那条线。
		Trigger.new("target_hp_ratio<0.35", "radio:duel_gawman_01", true, "m04_gawman"),
		Trigger.new("elapsed>=120", "cutscene:m04_mid_02", true, "m04_mid2"),
		Trigger.new("all_done", "end:win", true, "m04_win"),
		Trigger.new("hp<0.2", "end:lose", true, "m04_lose"),
	]
	m.cutscenes = {"prologue": [], "brief": ["m04_brief_01"],
		"mid": ["m04_mid_01", "m04_mid_02"], "debrief": ["m04_debrief_01"]}
	# ★ 2026-09-30 · 轮 57：开场演出（老板：「先做佩涅罗佩使用光束大炮攻击柯西运输仓，
	# 然后再是玩家操控柯西和佩涅罗佩对决」）。时间线在 `PodStrikeScript`。
	# ⚠️ 它**不改胜负**：运输仓不可被攻击，火光只是表演 —— 见该字段的注释。
	m.pod_strike = true
	# ★ 2026-10-01 老板：「car5p3/PENELOPE 演出 11 秒播放，然后**也作为本关的 bgm**」
	# ⇒ 演出与之后的战斗是**同一首**（`main._start_fight()` 里有一道闸门拦住重起）。
	m.bgm = "car5p3"
	m.base_reward = 420
	m.par_secs = 240.0
	return m


# ------------------------------------------------------------ M05 出击奥恩贝利
static func m05() -> Mission:
	var m := Mission.new("M05", "出击奥恩贝利")
	m.chapter = 2
	m.index = 1
	m.arena = "OENBELLI"
	m.time_key = "dusk_overcast"
	m.player_suit = SuitProfile.Id.XI
	# 柯西与三组双人梅萨踏板共同出击。
	m.ally_side = BattleFormation.Side.MAFTY
	m.ally_aces = 1
	m.enemy_suit = SuitProfile.Id.GUSTAV00
	m.brief = "奥恩贝利 · 阴天黄昏 · 制止屠杀"
	m.story = "街道上还有人在跑。金伯利的部队把炮口对着他们 ——" \
		+ "**制止它，而且要活的**。"
	# ★ 这一关**不自动推进波次**：增援是**事件驱动**的（见下面的 `spawn_wave:1`）——
	# 打到一半火力点、金伯利的直属机才压上来。这是 `waves_auto` 这个语义存在的理由
	# （"什么时候出下一波"本身就是一个叙事手段，不该只有"清完上一波"一种）。
	m.waves_auto = false
	m.waves = [
		ChallengeScript.Wave.new(3, SuitProfile.Id.GUSTAV00, EARTH_ALT, 55.0, true),
		ChallengeScript.Wave.new(1, SuitProfile.Id.GUSTAV00, EARTH_ALT + 900.0, 0.0, true),
	]
	m.objectives = [
		Objective.destroy_zone("oenbelli_guns", 0.75, "摧毁奥恩贝利火力点"),
		# ★ floor_hp > 0 = 连"打到快炸"都不许 —— 这是"**生俘**"这条剧情要求的落点。
		Objective.limit("kimberly", 0.25, 0.05, "使金伯利无力化"),
	]
	m.zones = [
		Zone.box("oenbelli_guns", "火力点区", Vector3(0.0, 600.0, 0.0),
			Vector3(8000.0, 1200.0, 8000.0), Zone.Use.OBJECTIVE),
	]
	m.triggers = [
		Trigger.new("elapsed>=6", "radio:oenbelli_fabio_01", true, "m05_fabio"),
		Trigger.new("elapsed>=25", "radio:oenbelli_ira_01", true, "m05_ira"),
		Trigger.new("elapsed>=35", "cutscene:m05_mid_01", true, "m05_mid"),
		Trigger.new("zone_ratio>=0.25", "radio:oenbelli_kimberly_01", true, "m05_kim"),
		# ★ 事件驱动的增援（`waves_auto == false` 时**必须**有这样一条，否则第 2 波永不出现）。
		Trigger.new("zone_ratio>=0.5", "spawn_wave:1", true, "m05_reinforce"),
		# ⚠️ 轮 55：原来这条是自编的「SPTV 播报」。剧本里**没有 SPTV 的播报原文**，
		# ⇒ 换成金伯利对记者的公开讲话（`h2:1448`，原句）。播报兰照样有内容。
		Trigger.new("kills>=2", "radio:oenbelli_broadcast_01", true, "m05_press"),
		Trigger.new("all_done", "end:win", true, "m05_win"),
		Trigger.new("hp<0.2", "end:lose", true, "m05_lose"),
	]
	m.cutscenes = {"prologue": [], "brief": ["m05_brief_01"], "mid": ["m05_mid_01"],
		"debrief": ["m05_debrief_01"]}
	m.base_reward = 380
	return m


# ------------------------------------------------------------ M06 海上袭击
static func m06() -> Mission:
	var m := Mission.new("M06", "海上袭击")
	m.chapter = 2
	m.index = 2
	m.arena = "PACIFIC"
	m.time_key = "night"
	m.player_suit = SuitProfile.Id.ARIZEUS
	m.pov = "喀耳刻部队的阿利宙斯驾驶员"
	m.enemy_suit = SuitProfile.Id.MESSER_M01
	m.brief = "太平洋群岛 · 夜 · 袭击英勇号"
	m.story = "前往太平洋群岛，突破两台梅萨的护卫，并攻击英勇号。"
	m.waves = [ChallengeScript.Wave.new(2, SuitProfile.Id.MESSER_M01, EARTH_ALT, 25.0)]
	m.win_on_clear = false
	m.landmark_group = "valiant_hull"
	m.landmark_beacon_group = "valiant_target"
	m.objectives = [
		Objective.destroy_all(2, "击落两台梅萨"),
		Objective.strike("valiant_hull", "用光束武器命中英勇号"),
	]
	m.triggers = [
		# Enemy-side calls from the existing Pacific dialogue bank.
		Trigger.new("elapsed>=6", "radio:escort_sibet_01", true, "m06_open"),
		Trigger.new("elapsed>=16", "radio:escort_bridge_01", true, "m06_contact"),
		Trigger.new("hp_ratio<0.01", "end:lose", true, "m06_lose"),
		Trigger.new("all_done", "end:win", true, "m06_win"),
	]
	m.cutscenes = {"prologue": [], "brief": ["m06_brief_01"], "mid": [], "debrief": []}
	m.base_reward = 300
	return m


# ------------------------------------------------------------ M07 艾尔斯岩
static func m07() -> Mission:
	var m := Mission.new("M07", "艾尔斯岩")
	m.chapter = 2
	m.index = 3
	m.arena = "ULURU"
	m.time_key = "night"
	m.player_suit = SuitProfile.Id.XI
	m.enemy_suit = SuitProfile.Id.ARIZEUS
	m.bgm = "car5p3"
	m.brief = "艾尔斯岩 · 夜 · 掩护马夫蒂转移"
	m.story = "沙丘上还有人在往上爬。Ξ 留下来殿后 —— " \
		+ "先来的不是那个灰色的巨兽，是三台量产机。"
	# ★ M07 的波次 = 现有那场遭遇，**逐字搬**（DESIGN §4.3 的"原样"）。
	m.waves = ChallengeScript.xi_vs_arizeus().waves
	m.objectives = [
		Objective.protect("mafty_convoy", 1, "掩护马夫蒂车队完成转移"),
		# 4 = 三台古斯塔夫 + 从上方入场的阿利宙斯（`xi_vs_arizeus()` 那两波）。
		Objective.destroy_all(4, "击退联邦攻击队", false),
	]
	m.zones = [
		Zone.sphere("mafty_convoy", "车队撤离线", Vector3(0.0, 120.0, 14000.0),
			5000.0, Zone.Use.EXTRACT),
		Zone.sphere("uluru_extract", "撤离航线", Vector3(0.0, 5400.0, -26000.0),
			4000.0, Zone.Use.EXTRACT),
	]
	m.triggers = [
		# 闪哈2 场 07-15 就是本关的原片出处（管制罗韦斯特全程在场）。
		Trigger.new("elapsed>=6", "radio:uluru_rowest_01", true, "m07_open"),
		Trigger.new("wave_cleared:0", "radio:uluru_rowest_02", true, "m07_boss"),
		Trigger.new("elapsed>=45", "cutscene:m07_mid_01", true, "m07_mid"),
		Trigger.new("kills>=1", "radio:uluru_hathaway_01", true, "m07_hathaway"),
		Trigger.new("enter:uluru_extract", "radio:uluru_rowest_03", true, "m07_extract"),
		Trigger.new("all_done", "end:win", true, "m07_win"),
		Trigger.new("protected_alive<1", "end:lose", true, "m07_lose"),
	]
	m.cutscenes = {"prologue": [], "brief": ["m07_brief_01"], "mid": ["m07_mid_01"],
		"debrief": ["m07_debrief_01"]}
	m.base_reward = 460
	m.par_secs = 260.0
	return m


# ============================================================ 自由遭遇（轮 B）
#
# ## 这一节在做什么
# DESIGN §10 轮 B：「把现有 4 场 `Encounter` **迁移**成 `Mission`」；§5.1「升级，不是重写」。
# 本节给出那 4 场的 **`Mission` 形态**，并且让 `M04` / `M07` 已经引用到的那些 `Wave`
# 是**同一次构造的结果**（不是复制品）—— 这就是"字段一个都没浪费"的落地方式。
#
# ## ⚠️ 真源仍然只有一份：`challenge_script.gd`
# `free_all()` **不硬写任何数据** —— 它是 `ChallengeScript.all()` 的**派生视图**
# （`free_from_encounter()` 逐字段映射）。于是：
#   - 4 场遭遇的波次与文案**只有一个写者**（铁律 6「两个写者 = bug」的直接落实）；
#   - "改了 `challenge_script.gd` 却忘了同步这边"这种错**不可能发生**（没有第二份可忘）；
#   - 反方向由 `to_encounter()` 与 `suite_campaign::_migrate` 的**往返断言**钉着。
#
# ## ⚠️ 为什么本轮**不**把 `challenge_script.gd` 真改成壳（把数据搬过来）
# DESIGN §9.2 的原话是「升级为 `MissionScript`（保留 `ChallengeScript` 作为兼容壳）」。
# 轮 B 只做**数据侧的等价形态**，那个文件保持原样，理由是**依赖方向**：
# `mission_script.gd` 已经在用 `ChallengeScript.Wave`（本文件里 8 处），
# 若 `challenge_script.gd` 反过来引用 `MissionScript`，就构成**循环引用** ——
# `preload` 会当场报 cyclic；改用 `class_name` 互引又要依赖"新类已进全局类缓存"，
# 而本仓库是**并行编辑**的（轮 A 的教训，见文件头）。
# ⇒ 而"数据不重复"这个收益，**派生视图**已经完整拿到，代价为零。
#   真正需要搬家的时点是**轮 C**：出击循环**只读 `Mission`**、
#   `main.gd` 的 `spawn_challenge()` 不再吃 `Encounter` 的那一刻。

## 场地 id 反查：`MapDef.Id` → `arena` 字符串。**认不出来就返回空串**（不兜到别的图上）。
##
## ⚠️ 与 `map_id_for()` 严格互逆：`map_id_for(arena_for(mid)) == mid`（5 张图全覆盖，套件钉着）。
## 认不出的 `mid` ⇒ `""`，而 `map_id_for("") == -1` ⇒ `is_arena_pending("")` 为真
## ⇒ 这个 `Mission` 会被判成"指向一张还不存在的图"，**不会静默跑在太平洋上**。
static func arena_for(mid: int) -> String:
	for k: String in ARENA_MAP.keys():
		if int(ARENA_MAP[k]) == mid:
			return k
	return ""


## 任意 `Encounter` → `Mission`（**纯映射**，不改传进来的那一个）。
##
## ⚠️ `waves` 是**同一批对象**（不复制）—— 这正是"M04 / M07 直接用它们"的机制：
## 剧情关与挑战关共用同一次 `Wave.new(...)` 的结果，改一处两边一起变。
static func free_from_encounter(e: ChallengeScript.Encounter) -> Mission:
	if e == null:
		return null
	var m := Mission.new(str(e.id), str(e.title))
	# 自由遭遇**不属于战役**：章号 / 章内序号都置 0，
	# 于是 `for_chapter(1|2)` 永远筛不到它们（那两章只该有战役关）。
	m.chapter = 0
	m.index = 0
	m.arena = arena_for(int(e.map_id))
	m.player_suit = e.player_suit
	m.enemy_suit = e.enemy_suit
	m.brief = str(e.brief)
	m.story = str(e.story)
	m.waves = e.waves
	# 现有挑战模式的胜利条件就是"全部击毁"（`Game.challenge_killed >= challenge_total`）。
	# 这里把它写成**数据**（一个 `DESTROY_ALL`），而不是散在 `main.gd` 里的判定。
	m.objectives = [Objective.destroy_all(m.total_enemies(), "击毁全部敌机")]
	# `true` = 现状行为（前一波清空 ⇒ 刷下一波），由轮 E 注入那条默认触发器。
	m.waves_auto = true
	# `0.0` ⇒ `par()` 回落 `MissionRating.par_secs(CHALLENGE, 台数)` ——
	# 与现有挑战模式结算**走同一条分支**，这是"结算读数逐项相同"的保证。
	m.par_secs = 0.0
	return m


## 现有 4 场遭遇的 `Mission` 形态。**顺序与菜单一致**（= `ChallengeScript.all()` 的顺序）。
##
## ⚠️ **每次调用都重新派生，不缓存**：`Encounter` 是可变对象，
## 若缓存成一份，就会重新引入"改了源、视图还是旧的"这种静默分家
## （正是本节想消除的东西）。4 场 × 各 1~2 波的构造成本可以忽略。
static func free_all() -> Array:
	var out: Array = []
	for e in ChallengeScript.all():
		out.append(free_from_encounter(e))
	return out


static func free_by_id(id: String) -> Mission:
	for m: Mission in free_all():
		if m.id == id:
			return m
	return null


## `Mission` → `Encounter`（供现有 `main.gd` 的 `spawn_challenge()` 通道复用）。
##
## ⚠️ **指向不存在的图**（`map_id() < 0`，例如尚未建图的 M03）⇒ **返回 `null`**，
## 不造出一个 `map_id == -1` 的 `Encounter` —— 后者会在 `MapDef.by_id(-1)` 那里
## 静默兜到别的图上（与 `world_builder` 那个 `match` 的 `_` 兜底是同一类静默失败）。
static func to_encounter(m: Mission) -> ChallengeScript.Encounter:
	if m == null:
		return null
	var mid: int = m.map_id()
	if mid < 0:
		return null
	var e := ChallengeScript.Encounter.new()
	e.id = str(m.id)
	e.player_suit = m.player_suit
	e.enemy_suit = m.enemy_suit
	e.map_id = mid
	e.title = str(m.title)
	e.brief = str(m.brief)
	e.story = str(m.story)
	e.waves = m.waves
	return e


# Chapter III uses the supplied lower-volume adaptation, not fabricated film quotes.
static func _third(mid: String,title: String,pilot: int,roster: Array,mode: String) -> Mission:
	var m := Mission.new(mid,title)
	m.chapter=3; m.index=int(mid.substr(1))-7; m.arena="ADELAIDE"
	m.player_suit=pilot; m.enemy_suit=int(roster[0]); m.enemy_roster.assign(roster)
	m.chapter_three_mode=mode; m.win_on_clear=false
	m.waves=[ChallengeScript.Wave.new(roster.size(),m.enemy_suit,3500.0,12.0,true)]
	m.base_reward=500+m.index*40; m.par_secs=300.0
	m.triggers=[Trigger.new("all_done","end:win",true,mid.to_lower()+"_win"),Trigger.new("hp<0.01","end:lose",true,mid.to_lower()+"_lose")]
	return m

static func _third_event(key: String,label: String) -> Objective:
	var o := Objective.new(Objective.Kind.EVENT,label); o.target=key
	return o

static func m08() -> Mission:
	var m := _third("M08","虎口拔牙",SuitProfile.Id.XI,
		[SuitProfile.Id.GUSTAV00,SuitProfile.Id.GUSTAV00,SuitProfile.Id.GUSTAV00],"raid")
	m.brief="阿德莱德 · 首次突袭 · 柯西与梅萨小队"
	m.story="防御壁尚未完成测试。柯西从西方高速突入，梅萨后续小队进入市区；压制守备队后撤离。"
	m.ally_roster.assign([SuitProfile.Id.MESSER_CMD,SuitProfile.Id.MESSER_M01,SuitProfile.Id.MESSER_M01])
	m.objectives=[_third_event("sector","突入阿德莱德节日中心空域"),Objective.destroy_all(3,"压制三台古斯塔夫守备机")]
	return m

static func m09() -> Mission:
	var m := _third("M09","精确防御",SuitProfile.Id.PENELOPE,
		[SuitProfile.Id.XI,SuitProfile.Id.MESSER_M01,SuitProfile.Id.MESSER_CMD,SuitProfile.Id.MESSER_M01],"defend")
	# Shell depletion starts Odysseus escape; only actual player destruction loses M09.
	m.triggers = [Trigger.new("all_done","end:win",true,"m09_win")]
	m.bgm = "car5p3"
	m.pov="雷恩·艾姆"; m.brief="阿德莱德 · 迎击马夫蒂小队"
	m.story="敌机已经进入市区。雷恩驾驶佩涅罗佩升空迎击；柯西掩护撤退的梅萨，不要让后续小队突破。"
	m.objectives=[_third_event("xi_repelled","击退柯西（机体血量低于30%）"),_third_event("messer_down","击落三台梅萨")]
	return m

static func m10() -> Mission:
	var m := _third("M10","再一次",SuitProfile.Id.XI_FINAL,
		[SuitProfile.Id.REGZ_CUSTOM,SuitProfile.Id.GUSTAV00,SuitProfile.Id.GUSTAV00,SuitProfile.Id.GUSTAV00],"return")
	m.brief="同日 · 再次攻击阿德莱德 · 柯西最终决战型"
	m.story="同日，马夫蒂再次攻击阿德莱德。此次仅柯西单机突入，突破灵格斯改与古斯塔夫小队的拦截。"
	m.objectives=[_third_event("sector","再次突入阿德莱德节日中心空域"),Objective.destroy_all(4,"击败灵格斯改及三台古斯塔夫")]
	return m

static func m11() -> Mission:
	var m := _third("M11","壮志未酬·上",SuitProfile.Id.XI_FINAL,[SuitProfile.Id.PENELOPE],"duel")
	m.brief="阿德莱德南部 · 柯西对佩涅罗佩"
	m.story="两机在城市南部交锋。雷恩接到命令，要将柯西带到S18防御线；将佩涅罗佩的机体血量打至20%以下。"
	m.objectives=[_third_event("duel","使佩涅罗佩机体血量低于20%")]
	return m

static func m12() -> Mission:
	var m := _third("M12","壮志未酬·下",SuitProfile.Id.PENELOPE,[SuitProfile.Id.XI_FINAL],"lure")
	m.player_form=0; m.player_start_hull_ratio=0.8; m.player_no_ifield=true
	m.pov="雷恩·艾姆"; m.brief="S18防御线 · 佩涅罗佩诱导作战（80%耐久 · 无I立场）"
	m.story="佩涅罗佩以80%机体耐久继续作战，I立场不可用。驾驶佩涅罗佩吸引柯西追击，将柯西引入S18指定点4公里范围，或直接击毁柯西。"
	m.objectives=[_third_event("lure","引导柯西进入S18指定点4km范围，或击毁柯西")]
	m.par_secs=360.0
	return m
