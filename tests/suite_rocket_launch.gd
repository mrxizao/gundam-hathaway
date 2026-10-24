extends RefCounted
## 马夫蒂火箭发射段（2026-09-30）。
##
## 老板原话：
## > 「把马夫蒂的火箭加入游戏中，马夫蒂的火箭是剧情模式的演出之一，
## >  玩家需要操控火箭从太平洋发射到近地轨道，中间需要做无缝切换房间，
## >  可以在发射过程中做切换，通过云层来挡住玩家视线，然后在后台偷偷加载切换房间，
## >  然后切换到近地轨道中离柯西运输仓 200 km 的地方。」
##
## ## 这一套钉什么
## | 节 | 钉的是 | 为什么必须有 |
## |---|---|---|
## | ① 曲线（纯函数） | 端点逐位相同 / 三轴单调 / 航迹角单调 | 抵达点"精确"必须是**构造性**的，不是调出来的 |
## | ② 时间线对账 | 云底 14 s、全遮 15.8 s、卡门线 37.6 s | 三个高度判据必须与**曲线**自洽（改一个常量会连带破另外两个） |
## | ③ 朝向 | `upright_basis()` 机头朝上；`model_basis()` **三根轴各落在哪儿** | 长轴对 ≠ 朝向对（滚转错了两个助推器会上下叠着，不报错） |
## | ④ 制导 | 零输入飞 60 s 的**最大跟踪误差 / 安全绳次数 / 终位** | 这是"真实力积分"这句话**唯一**的证伪点 |
## | ⑤ 云幕状态机 | `request_reveal()` 只能从 HOLD 出来；`veil` / `solid` 两条通道 | 建图没做完就揭开 = 露出正在渐变的幕布边缘；而"少 70%"与"换图不透风"是两件事 |
## | ⑥ 无缝换房间 | 三道结构性保证 + 真的换成了 LEO | "无缝"就是这三条，缺一条就是"有缝只是没人看见" |
## | ⑦ 发射点接线 | 太平洋图有 `launch_splash`（出水特效），别的图没有 | 漏了清理就是**指向已释放节点**（换图不报错） |
## | ⑧ 数据与接线 | M03 的 `launch_prologue`、`main.gd` 的容器与交还路径 | 数据/流程分家的地方最容易静默失效 |
## | ⑨ 出水与发射段机位 | `SeaSplash` 状态机 + `ChaseCamera.set_launch_eye()` | 「从海里出来」没泡沫/烟 = 穿模；相机沉到海面下或落不进舱 = 这一段演出整个没了 |
## | ⑨′ 舱外档**锁距** | 100 步内（每步瞬移 8 km）离箭**恒 80.92 m** | 「相机要一直和火箭保持一个距离」——旧版弹簧在 8 km/s 时落后 1 231 m，而那**看起来像功能** |
## | ⑩ 座舱（全周天）+ 火焰 | 仪表读数纯函数（高度/时速/燃料/阶段）、`hud.cockpit_*` 三个开关、三层焰的几何朝向与材质分家 | 老板否掉了第一版 3D 舱（「**你驾驶舱做的好丑，直接用全周天驾驶舱的代码吧**」）⇒ 现在舱内 = HUD 那一层，读数**一个字段都不许读 `player`**（发射段 `player` 是 null）；三层焰共用一份材质会被最后一次写参数悄悄改掉 |
##
## ⚠️ 本套件有 `await`（⑥ 节要真建两张图、⑦ 节要等一帧让世界进树）
## ⇒ `SUITES` 表的第 3 列必须是 `true`。
## ⚠️⚠️ 而且**每一节有 `await` 的函数都必须被 `await` 地调用** —— 漏一个，
## 那一节会在第一个 `await` 处永久挂起、断言一条都不跑，报告里只留一个**空壳**
##（条数栏显示 `0`）。实测漏掉过 `_launch_site()`，那一节静默失效了一整轮。

## 任务数据表。按仓库惯例走 `preload`（见 `suite_campaign` 那一段的说明）——
## `class_name MissionScript` 要等编辑器重新扫描才进全局类缓存，而本仓库是并行编辑的。
const MS := preload("res://scripts/data/mission_script.gd")
## 座舱仪表台那节要读 HUD 的源码（判"读数到底读了谁"）。
const HUD_SRC := "res://scripts/ui/hud.gd"


static func run(t: T, host: Node) -> void:
	_curve(t)
	_timeline(t)
	_orientation(t)
	_guidance(t, host)
	# ★ ⑨ 两节都是**纯状态**（不建图、不 await）⇒ 同步调，不加 `await`。
	_splash(t, host)
	_launch_view(t, host)
	# ★ ⑩ 两节同理（只新建节点，不建图）。
	_cockpit_hud(t, host)
	_flame(t, host)
	# ⚠️ 这个 `await` **不能省**：`_swap()` 里有 `await`（真的建两张图）。
	# 少写一个 `await`，GDScript 会在第一个 `await` 处把协程挂起、而**没有人等它**
	# ⇒ 那一节永久停在那里，断言一条都不执行，报告里只留一个**空壳**
	#（条数栏显示 `0`，而"0 条"既不是 PASS 也不是 FAIL ⇒ 整节静默失效）。
	await _swap(t, host)
	# ⚠️ 这个 `await` **不能省**：`_launch_site()` 里有 `await process_frame`。
	# 少写一个 `await`，GDScript 会在第一个 `await` 处把协程挂起、而**没有人等它**
	# ⇒ 那一节永久停在那里，断言一条都不执行，报告里只留一个**空壳**（实测：
	# 条数栏显示 `0`，而"0 条"既不是 PASS 也不是 FAIL ⇒ 整节静默失效）。
	# 这一节是"出水特效建出来了吗 / 有没有被清理"的唯一判据，漏掉等于没钉。
	await _launch_site(t, host)
	await _data_and_wiring(t, host)


# ============================================================ ① 上升曲线

static func _curve(t: T) -> void:
	t.suite("RocketLaunch / 上升曲线（纯函数）")

	# ★ 端点①：起点 == 火箭**浸在水里**的静置位置。
	#
	# ⚠️ 这一条不是"顺便钉一下"：曲线与出生点若不同源，
	# 位置环在 t = 0 就带着一个几十米的初始误差起步，
	# 画面表现为"点火瞬间弹一下"，而它**不报任何错**。
	var p0 := LaunchScript.ascent_pos(0.0)
	var rest := LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0)
	t.near(p0.distance_to(rest), 0.0, 1e-6,
		"ascent_pos(0) 与火箭浸在水里的静置位置**逐位相同**（不是差不多）")

	# ★ 端点②：终点 == 抵达点。`lerpf` 的端点性质保证它是构造性的。
	t.near(LaunchScript.ascent_pos(1.0).distance_to(LaunchScript.arrival_pos()), 0.0, 1e-6,
		"ascent_pos(1) 与 arrival_pos() **逐位相同**（抵达点精确是构造性的）")

	# ★ 老板要的那个数。
	t.near(LaunchScript.arrival_distance(), 200000.0, 0.5,
		"抵达点离运输仓 200 km（老板原话）")
	t.near(LaunchScript.pod_pos().y, LaunchScript.ORBIT_ALT, 0.001,
		"运输仓在 550 km 轨道高度上")

	# ★ 三轴单调：抽样 400 点，任何一次回退都算红。
	#
	# ⚠️ z 那一条第一版写的是"横向恒为 LAUNCH_Z（没有横移）"—— 那是**照着当时那版代码
	# 写的判据**，而那一版恰好是错的：平台在 `z = +20 km`、抵达点在 `z = 0`，
	# 于是 `ascent_pos(1)` 与 `arrival_pos()` 差 20 km。
	# ⇒ 判据要跟着**需求**走（"必须落到抵达点"），不是跟着当时的实现走。
	var bad_alt := 0
	var bad_x := 0
	var bad_z := 0
	var prev := LaunchScript.ascent_pos(0.0)
	for i in range(1, 401):
		var p := LaunchScript.ascent_pos(float(i) / 400.0)
		if p.y < prev.y - 1e-6:
			bad_alt += 1
		if p.x > prev.x + 1e-6:
			bad_x += 1
		if p.z > prev.z + 1e-6:
			bad_z += 1
		prev = p
	t.eq(bad_alt, 0, "高度全程单调不降（没有一次「往下掉」）")
	t.eq(bad_x, 0, "下射程全程单调（沿 −X 一路走到底，不回头）")
	t.eq(bad_z, 0, "横向（z）也单调：从 LAUNCH_Z 一路收到抵达点的 0（不再写死）")

	# ★ 航迹角：由 `ascent_velocity()` 反解，必须单调不增。
	#
	# ⚠️ 这一条抓的是**第一版那个错**：那时另写了一条 `assist_pitch_deg()`，
	# 它说末段 8°，而曲线真实航迹角是 70.6° —— 差 62°，机头会横过来。
	var a0 := LaunchScript.ascent_pitch_deg(0.02)
	var a1 := LaunchScript.ascent_pitch_deg(0.5)
	var a2 := LaunchScript.ascent_pitch_deg(1.0)
	# ⚠️ `u = 0` 才是正 90°（那里速度为零，走的是回退分支）。
	# 到 `u = 0.02` 时航迹角已经肉眼可见地转过去了 —— 因为
	# `tanθ ∝ u^(ALT_SHAPE − DOWNRANGE_SHAPE) = u^−0.36`，它在 `u → 0⁺` 处**不发散但不慢**：
	# 实测 `u = 0.02 ⇒ 81.5°`。第一版拿 90° ± 4 去钉 0.02，是**期望值挑错了采样点**，
	# 不是曲线错了（曲线在 `u = 0` 处逐位给 90°）。
	t.near(LaunchScript.ascent_pitch_deg(0.0), 90.0, 1e-9,
		"u = 0 是**正垂直**（90°，由零速度的回退分支给出）")
	t.between(a0, 70.0, 89.0,
		"u = 0.02 已经转过一小截（实测 %.1f° —— 重力转弯从这里就开始了）" % a0)
	t.between(a2, 60.0, 80.0,
		"终端航迹角在 60°~80°（**陡升弹道**，不是入轨剖面）—— 实测 %.1f°" % a2)
	t.gt(a0, a1, "航迹角单调下降（0.02 → 0.5）")
	t.gt(a1, a2, "航迹角单调下降（0.5 → 1.0）")

	# ★ 下射程指数必须 > 高度指数，否则航迹角不单调（见 `DOWNRANGE_SHAPE` 的推导）。
	t.gt(LaunchScript.DOWNRANGE_SHAPE, LaunchScript.ALT_SHAPE,
		"DOWNRANGE_SHAPE > ALT_SHAPE（否则末段机头会重新抬起来）")

	# ---- ★ 参考速度 / 加速度：**解析式**，不是差分 ----
	#
	# 这一组是这套东西里最贵的一课：第一版用中心差分，前 3/4 段全对、末段塌掉，
	# 而且不报错。根因是 `ascent_pos()` 返回 float32 的 `Vector3`，
	# 末段高度 ~5.5e5 的 ulp 是 0.0625 m，而二阶差分只有 ~0.04 m ⇒ 噪声比信号大。
	# 实测差分版在 `u = 1.0` 给出 `ascent_accel().y == 0.0`（真值 1468）。
	# ⇒ 下面这两条就是"必须解析"的判据，改回差分立刻变红。
	t.near(LaunchScript.ascent_accel(1.0).y, 1468.0, 3.0,
		"★ u = 1 的参考加速度 y = 1468 m/s²（差分版本在这里会算出 **0.0**）—— 实测 %.1f"
			% LaunchScript.ascent_accel(1.0).y)
	t.near(LaunchScript.ascent_accel(1.0).x, -586.7, 2.0,
		"★ u = 1 的参考加速度 x = −586.7 m/s²（差分版本给的是 −217）—— 实测 %.1f"
			% LaunchScript.ascent_accel(1.0).x)
	t.near(LaunchScript.ascent_accel(0.0).length(), 0.0, 1e-6,
		"u = 0 的参考加速度是零向量（起飞第一帧静止，不是被推出去）")
	t.near(LaunchScript.ascent_velocity(0.0).length(), 0.0, 1e-9,
		"u = 0 的参考速度是零向量")

	# ★ 解析导数必须与曲线**自洽** —— 拿一个步长够大（1e-3，不被 float32 吃掉）
	# 的中心差分交叉验一遍。这一条挡的是"解析式抄错一个指数"。
	var hh := 1e-3
	for uu in [0.3, 0.6, 0.9]:
		var fd := (LaunchScript.ascent_pos(uu + hh) - LaunchScript.ascent_pos(uu - hh)) \
			/ (2.0 * hh) / LaunchScript.ASCENT_SPAN
		var d := LaunchScript.ascent_velocity(uu).distance_to(fd)
		t.lt(d, 2.0, "ascent_velocity(%.1f) 与曲线的中心差分一致（差 %.3f m/s）" % [uu, d])

	# ★ 大气 / 重力两条纯函数。
	t.near(LaunchScript.gravity_at(0.0), 9.82, 0.05, "海平面重力 9.82 m/s²")
	t.lt(LaunchScript.gravity_at(100000.0), LaunchScript.gravity_at(0.0),
		"100 km 处重力更小（卡门线之上已经开始「变轻」）")
	t.lt(LaunchScript.air_density(LaunchScript.ORBIT_ALT), 1e-12,
		"550 km 处的大气密度可忽略（**不是** == 0：指数模型给的是 1e-29）")
	t.near(LaunchScript.air_density(0.0), 1.225, 0.001, "海平面大气密度 1.225 kg/m³")
	t.gt(LaunchScript.air_density(0.0), LaunchScript.air_density(20000.0),
		"密度随高度下降")

	# ★ 阶段判据（HUD 与测试读同一个纯函数）。
	#
	# ⚠️ 2026-09-30 平台删掉之后，「在不在台上」改成了「**在不在水里**」，
	# 并**多出一档 `BREACH`（出水）** —— 水面是一个真实的分界（`BREACH_ALT` = 0 就是海面）：
	#   PAD    = 箭底 ≤ `rest_alt()`（浸在水面之下 34 m）
	#   BREACH = 箭底在 `rest_alt()` 与海面之间 ← 这一段挂着出水特效与「出水」播报
	# ⇒ 原来那条「高度 0 ⇒ 发射台」是**平台时代的旧期望**（那时台面是一个正值标高）。
	#   0 现在是**海面本身**，也就是 `BREACH` 的右端点。
	t.eq(LaunchScript.leg_for(LaunchScript.rest_alt(), false), LaunchScript.Leg.PAD,
		"高度 = rest_alt()（浸在水里）⇒ 待发（倒计时中）")
	t.eq(LaunchScript.leg_for(0.0, false), LaunchScript.Leg.BREACH,
		"高度 0（刚好到海面）⇒ 出水 —— 这一档是出水特效与播报的挂点，别让它静默消失")
	t.eq(LaunchScript.leg_for(LaunchScript.BREACH_ALT + 1.0, false), LaunchScript.Leg.LIFTOFF,
		"越过海面 ⇒ 离水")
	t.eq(LaunchScript.leg_for(LaunchScript.CLOUD_BASE_ALT + 1.0, false), LaunchScript.Leg.CLOUD,
		"云底之上 ⇒ 云中")
	t.eq(LaunchScript.leg_for(LaunchScript.REVEAL_ALT + 1.0, true), LaunchScript.Leg.VACUUM,
		"换图之后、卡门线之上 ⇒ 真空段")
	t.eq(LaunchScript.leg_for(LaunchScript.ORBIT_ALT, true), LaunchScript.Leg.COAST,
		"到 550 km ⇒ 入轨滑行")
	t.eq(LaunchScript.leg_name(LaunchScript.Leg.CLOUD), "穿云 · 制导接管",
		"阶段名是唯一真源（HUD 里不许再写一份 match）")


# ============================================================ ② 时间线对账

static func _timeline(t: T) -> void:
	t.suite("RocketLaunch / 时间线对账")
	# ⚠️ 这一节的意义：`ALT_SHAPE` / `CLOUD_BASE_ALT` / `REVEAL_ALT` / `ASCENT_SPAN`
	# 几个数**互相牵制**。只改其中一个（比如把换图触发高度从云底挪到 300 km）
	# 会让"换图"那一段跑到抵达之后 —— 而画面上只是"没看见地球"，不报错。
	# 所以这里把它们**互相**钉住，而不是各钉各的。
	#
	# ★ 2026-09-30：从前这里钉的是"云幕淡入 14 s / 全遮 15.8 s / 揭开 37.6 s"。
	# 幕布删掉之后，**换图那一下**（锁座舱档 → 建图 → 放锁）才是唯一需要卡时机的事件。
	var span := LaunchScript.ASCENT_SPAN
	t.near(t_of(LaunchScript.CLOUD_BASE_ALT), 14.0, 1.5,
		"★ 换图在**云底**触发，落在 14 s 附近 —— 低空可见段该有的长度")
	# ★★ 换图**必须在云里做**：幕布没了之后，换图那几帧玩家仍透过风挡看得见天，
	# 在云里意味着外面本来就是一片糊的云，而不是"干净的星空忽然变密"。
	# 这条把"触发点落在主积云带内"钉死 —— 挪到带外就变红。
	var lo := WorldBuilder.CLOUD_MAIN_LO
	var hi := WorldBuilder.CLOUD_MAIN_HI
	t.between(LaunchScript.CLOUD_BASE_ALT, lo, hi,
		"★★ 换图触发高度落在**主积云带**里（%.0f~%.0f m）—— 换图那几帧外面是云，不是干净星空"
			% [lo, hi])
	# `CLOUD_FULL_ALT` 现在只管一件事：把 `Leg.CLOUD` 切成 `Leg.VACUUM`。
	# 它仍必须在主积云带里（否则"穿云"这一段会在云外面读出来）。
	t.between(LaunchScript.CLOUD_FULL_ALT, lo, hi,
		"★ 云段→真空段的切换高度也在主积云带里（%.0f~%.0f m）" % [lo, hi])
	t.gt(LaunchScript.CLOUD_FULL_ALT, LaunchScript.CLOUD_BASE_ALT,
		"  而且它在云底之上（先穿云、再真空，次序不能反）")
	t.gt(t_of(LaunchScript.REVEAL_ALT), t_of(LaunchScript.CLOUD_BASE_ALT) + 10.0,
		"卡门线比换图晚得多（换图在 14 s、卡门线在 37.6 s —— 中间二十几秒是爬升段）")
	t.lt(t_of(LaunchScript.REVEAL_ALT), span - 5.0,
		"卡门线在抵达之前 —— 留出「看地球退远」的时间（实测 %.1f s / %.1f s）"
			% [t_of(LaunchScript.REVEAL_ALT), span])
	t.near(t_of(LaunchScript.ORBIT_ALT), span, 0.01, "曲线终点就是 ASCENT_SPAN 秒")

	# ⚠️ "两个云高度都落在主积云带里"那两条已经挪到上面（与"换图在云里"同处）——
	# 写在这里会**重复声明** `lo` / `hi`，而 GDScript 里同函数重复 `var` 是 Parse Error
	#（整个套件一条都跑不了，报告里只显示"0 PASS"）。

	# 卡门线 = 本工程自己那条"空间/大气"分界。
	var leo := MapDef.leo()
	t.near(LaunchScript.REVEAL_ALT, leo.reentry_alt, 0.01,
		"揭幕高度 == 卡门线 == MapDef.leo().reentry_alt（有名字的判据，不是凑的数）")

	# ★ 无缝的**全部前提**：五张地表图与轨道图共用同一条高度原点（y = 0 = 地球表面）。
	#
	# ⚠️ 谁把轨道图的地球球心挪一格，整个演出就会在切换那一刻**跳一下**，
	# 而且**不报任何错**。这一条就是那条守护线。
	t.near(leo.body_radius + 0.0, LaunchScript.BODY_R, 0.01,
		"轨道图的地球半径 == LaunchScript.BODY_R")
	t.near(LaunchScript.ORBIT_ALT, WorldBuilder.SPACE_ORBIT_ALT, 0.01,
		"轨道高度 == WorldBuilder.SPACE_ORBIT_ALT")
	t.near(LaunchScript.pod_pos().distance_to(WorldBuilder.SPACE_POD_POS), 0.0, 0.5,
		"运输仓位置 == WorldBuilder.SPACE_POD_POS")
	# 球顶落在 y = 0 ⇒ 地表图的 y 与轨道图的 y 是同一个量。
	t.near(WorldBuilder.SPACE_ORBIT_ALT - leo.body_radius, LaunchScript.ORBIT_ALT - LaunchScript.BODY_R,
		0.01, "球顶（y = 0）在两套坐标里是同一个面 —— 这是「切换前后位置连续」的前提")


## 高度 → 时间（秒）。**反解** `ascent_pos()` 的高度分量。
static func t_of(alt: float) -> float:
	var g := (alt - LaunchScript.rest_alt()) / (LaunchScript.ORBIT_ALT - LaunchScript.rest_alt())
	if g <= 0.0:
		return 0.0
	return LaunchScript.ASCENT_SPAN * pow(g, 1.0 / LaunchScript.ALT_SHAPE)


# ============================================================ ③ 朝向

static func _orientation(t: T) -> void:
	t.suite("RocketLaunch / 朝向（两根轴都要钉）")

	# ★ 机头朝上：`upright_basis()` 把机体的 −Z（机头）送到世界 +Y。
	#
	# ⚠️ 写反一次就会让火箭**头朝下发射**（`θ = −90°` 给 `(0, −1, 0)`）。
	# 这个断言存在的意义就是把那一次变成红的。
	#
	# ⚠️ 写法上踩过一次：`bool(vec)` 在 GDScript 里**没有**这个重载
	#（`bool(Vector3)` 不成立）—— 想把向量比较的结果转成 bool 要**先判再转**，
	# 或者直接拿 `Vector3.is_equal_approx()` 当 `t.ok()` 的条件。
	var nose_up := RocketBody.upright_basis() * Vector3.FORWARD
	t.ok(nose_up.is_equal_approx(Vector3.UP),
		"upright_basis() 把机头（局部 −Z）送到世界 +Y（= 立起来，不是倒插）")
	t.near(nose_up.distance_to(Vector3.UP), 0.0, 1e-5, "  （逐分量：%.4f, %.4f, %.4f）"
		% [nose_up.x, nose_up.y, nose_up.z])

	# ★★ 资产朝向要钉**三根轴各落到哪儿**，不能只钉长轴。
	#
	# 实测（`tools/_rocket_family_probe.gd`）：模型的长轴是 +Y（0.8048），
	# 但横截面是 X 0.1736 × **Z 0.3079** —— Z 那根明显宽（两个助推器沿模型 Z 排开）。
	# 只转 X −90° 的话模型 +Z 落到机体 **+Y**，也就是**两个助推器上下叠着**；
	# 再绕机体 Z 滚 −90° 才能让它们**左右并排**。两种都不报错。
	var b := RocketBody.model_basis()
	var my := b * Vector3.UP        # 模型 +Y（长轴 / 机头方向）
	var mz := b * Vector3.BACK      # 模型 +Z（助推器排开的方向）
	# ⚠️ 这条期望值我写错过一次：写的是 `Vector3.BACK`。
	# **机头 = 机体 −Z = `Vector3.FORWARD`**（`ChaseCamera._desired_position()` 把镜头
	# 放在 +Z 侧 ⇒ 前方朝 −Z）。`BACK` 是 (0,0,+1)，正好是机头的**反面** ——
	# 拿它当期望值等于把"箭尾朝上发射"判成对。
	t.near(my.distance_to(Vector3.FORWARD), 0.0, 1e-5,
		"模型 +Y（长轴）→ 机体 −Z（机头 = `Vector3.FORWARD`，不是 `BACK`）")
	t.near(mz.distance_to(Vector3.RIGHT), 0.0, 1e-5,
		"模型 +Z（**助推器排开的方向**）→ 机体 +X（水平）—— 滚转对了，助推器才是左右并排")
	t.ok(b.determinant() > 0.99,
		"model_basis() 是**正当的旋转**（行列式 +1，不是镜像 —— 镜像会让模型内外翻转）")

	# 尺寸换算：58 m 的箭，横截面应当"宽 > 厚"（与上面那条互为佐证）。
	t.near(RocketBody.ROCKET_HEIGHT_M, 58.0, 0.001, "火箭在游戏里高 58 m")


# ============================================================ ④ 制导（真实力积分）

static func _guidance(t: T, host: Node) -> void:
	t.suite("RocketLaunch / 制导：零输入飞完 60 s 能不能飞准")
	# ⚠️ 这一节是"位置真的是力积分出来的"这句话**唯一**的证伪点。
	# 如果 `leash_count > 0` 或跟踪误差很大，那说明"制导"其实变成了"安全绳拖尸" ——
	# 代码里的"真实力积分"就成了一句空话。
	#
	# 它同时也是**唯一能在无头环境里跑完整段上升**的地方：
	# 真机上这一段要玩家飞 60 s，而这里 60 秒的物理在一帧里算完。
	var rb := RocketBody.new()
	rb.name = "GuidanceProbe"
	host.add_child(rb)
	rb.configure(LaunchScript.ASCENT_SPAN)
	rb.place_at_launch(LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))

	var dt := 1.0 / 60.0
	var steps := int(ceil(LaunchScript.ASCENT_SPAN / dt)) + 8
	var prev_alt := rb.global_position.y
	var alt_bad := 0
	# ★ 姿态跟踪误差（度）：**机身实际仰角 vs 制导想要的推力仰角**。
	#
	# ⚠️ 第一版这里比的是 `ascent_pitch_deg(u)`（**速度方向**），全程差 53° 被判红 ——
	# 而那是**判据错了**，不是飞控错了：机身对着的是**推力方向**，
	# 推力除了跟随速度还得先抵掉重力，于是它比速度**更偏水平**
	#（实测中段 u = 0.2：推力 52°、速度 79°，两者都对）。
	# 真源是 `RocketBody.cmd_pitch_deg`（上一步 `thrust_dir` 的高度角）。
	var pitch_err_max := 0.0
	var pitch_min := 999.0
	var pitch_max := -999.0
	var pitch_err_at := Vector3.ZERO   # (u, 机身仰角, 制导指令仰角) —— 误差最大的那一刻
	var pitch_err_u := -1.0
	# 分段误差读数：跟踪误差是"一直在长"还是"最后几秒崩"，靠这一行分得清。
	var marks: Array[float] = [0.25, 0.5, 0.75, 1.0]
	var seg: Array[String] = []
	var mi := 0
	for i in steps:
		rb.step(dt, 0.0, 0.0, 0.0)
		if rb.global_position.y < prev_alt - 1e-3:
			alt_bad += 1
		prev_alt = rb.global_position.y
		var pe := absf(rb.pitch_deg() - rb.cmd_pitch_deg)
		if pe > pitch_err_max:
			pitch_err_max = pe
			pitch_err_at = Vector3(rb.u, rb.pitch_deg(), rb.cmd_pitch_deg)
		pitch_min = minf(pitch_min, rb.pitch_deg())
		pitch_max = maxf(pitch_max, rb.pitch_deg())
		while mi < marks.size() and rb.u >= marks[mi]:
			seg.append("u=%.2f: 误差%.0fm 机身%.1f°/指令%.1f°" % [marks[mi],
				LaunchScript.ascent_pos(rb.u).distance_to(rb.global_position),
				rb.pitch_deg(), rb.cmd_pitch_deg])
			mi += 1
		# 末帧诊断：`u = 1.0` 那一帧曾经因为"差分的加速度"塌成 0，
		# 于是指令仰角从 72° 掉到 4.8°。这一行留着 —— 它当场就能分辨
		# "参考量的端点出问题"与"反馈真的这么大"。
		if i == steps - 1:
			var rp := LaunchScript.ascent_pos(rb.u)
			var rv := LaunchScript.ascent_velocity(rb.u)
			var ra := LaunchScript.ascent_accel(rb.u)
			print("      [末帧] u=%.6f err=(%.1f,%.1f,%.1f) vel=(%.1f,%.1f,%.1f) "
				% [rb.u, (rp - rb.global_position).x, (rp - rb.global_position).y,
					(rp - rb.global_position).z, rb.velocity.x, rb.velocity.y, rb.velocity.z]
				+ "refv=(%.1f,%.1f,%.1f) refa=(%.1f,%.1f,%.1f) 指令%.2f°"
				% [rv.x, rv.y, rv.z, ra.x, ra.y, ra.z, rb.cmd_pitch_deg])

	var err := rb.max_track_err
	var d_arr := rb.global_position.distance_to(LaunchScript.arrival_pos())
	print("    [读数] 最大跟踪误差 %.0f m / 安全绳 %d 次 / 终位差 %.0f m / 末速 %.0f m/s / 姿态误差 max %.2f°"
		% [err, rb.leash_count, d_arr, rb.speed(), pitch_err_max])
	print("    [分段] %s" % ", ".join(seg))
	print("    [姿态] 最大偏差 %.2f° 出现在 u = %.4f（机身 %.2f° / 指令 %.2f°）；终端 机身 %.2f° / 指令 %.2f°"
		% [pitch_err_max, pitch_err_at.x, pitch_err_at.y, pitch_err_at.z,
			rb.pitch_deg(), rb.cmd_pitch_deg])

	t.gt(rb.u, 0.999, "曲线进度跑满（u = %.3f）" % rb.u)
	t.eq(alt_bad, 0, "高度全程单调（没有靠安全绳来回拉）")
	t.lt(err, 2000.0,
		"最大跟踪误差 < 2 km（实测 %.0f m —— 大半是末段 1.5 km/s² 曲线加速度带来的稳态滞后，见 `ascent_accel`）"
			% err)
	t.eq(rb.leash_count, 0,
		"★ 安全绳**一次都没触发**（它是保险丝，不是主回路；实测 %d 次）" % rb.leash_count)
	t.lt(d_arr, 2000.0, "终位离抵达点 < 2 km（实测 %.0f m —— 剩下的由位置环在尾巴上收）" % d_arr)
	t.gt(rb.speed(), 20000.0, "末速 > 20 km/s（这一段的尺度决定的，见 ALT_SHAPE 的长注释）")
	t.lt(rb.fuel, RocketBody.FUEL0, "燃料真的在掉（%.0f%%）" % (rb.fuel_fraction() * 100.0))
	t.between(rb.pitch_deg(), 55.0, 90.0,
		"终端机头仍然抬着（陡升弹道，**不是**被摆平）—— 实测 %.1f°" % rb.pitch_deg())

	# ★ 姿态真的跟上了制导指令（不是"力对了但机头乱指"）。
	#
	# ⚠️ 这里第一版写的是 `t.ok(true, ...)` 的空断言 —— 那等于没钉。
	# 空断言比不写更坏：它在报告里占一行 PASS，让人以为"姿态有覆盖"。
	t.lt(pitch_err_max, 3.0,
		"★ 全程机身仰角跟住**制导指令**（最大偏差 %.2f°；姿态环 ATT_GAIN 3.2 / MAX_RATE 31.5°/s）"
			% pitch_err_max)

	# ★ 另钉一条"全程没有横过来 / 没有倒过来"：机身仰角必须一直留在 45°~95°。
	# 它抓的是"姿态环整个失灵"那一类 —— 那时上面那条（跟住指令）**可能还是绿的**
	#（指令本身算错、机身忠实地跟着错），这一条会把结果挡下来。
	t.between(pitch_min, 45.0, 95.0, "全程机身仰角下界 ≥ 45°（实测最低 %.1f°）" % pitch_min)
	t.between(pitch_max, 45.0, 95.0, "全程机身仰角上界 ≤ 95°（实测最高 %.1f°）" % pitch_max)

	# ★ 无输入时两根配平杆必须回中（回不了中就等于制导被永久偏置）。
	t.near(rb.trim_deg.length(), 0.0, 0.02, "零输入 ⇒ 配平回中")

	# ★ 抵达之后**冻住**：上面那个循环多跑了 8 帧（`steps` 里的 `+ 8`），
	# 而在"冻结"这条落地之前，那 8 帧正是把误差从 612 m 抬到 5 311 m、
	# 把机身仰角从 +70° 拽到 −60° 的原因。现在它必须一动不动。
	var arrived_pos := rb.global_position
	var arrived_u := rb.u
	for i in 8:
		rb.step(dt, 0.0, 0.0, 0.0)
	t.near(rb.global_position.distance_to(arrived_pos), 0.0, 1e-6,
		"★ 抵达（u = 1.0）之后**冻结**：再多跑 8 帧位置一动不动")
	t.near(rb.u, arrived_u, 1e-9, "  （u 也不再推进）")

	# ★ 断电后必须真的停住（`_finish_launch()` 依赖这条）。
	#
	# ⚠️ 判据是"**不再被推着跑**"，不是"位置一动不动"：
	# 制导关掉之后这一帧只剩重力（`g⃗` 在 `step()` 里是无条件施加的），
	# 一帧自由落体是 `8.3 × (1/60)² ≈ 2.3 mm` —— 而第一版这里拿 `1e-3` 去比，
	# 于是**正确行为被判红**。阈值必须容得下这一帧自由落体，同时小到能抓住
	# "推力没关掉"（那会是几米的量级）。
	#
	# ⚠️ 而且必须先把 `u` 退回中段：`step()` 在 `u >= 1.0` 时**提前返回**，
	# 在 1.0 上做这条断言等于"在一条永远返回的路径上量漂移"——恒 0 的假绿。
	rb.u = 0.5
	rb.assist = false
	rb.base_throttle = 0.0
	rb.velocity = Vector3.ZERO
	var hold := rb.global_position
	rb.step(dt, 0.0, 0.0, 0.0)
	var drift := rb.global_position.distance_to(hold)
	t.lt(drift, 0.05,
		"断电之后不再被推着跑（一帧只剩自由落体 %.4f m —— 推力若没关会是米级）" % drift)

	rb.free()


# ============================================================ ⑤ 换图（锁座舱档，无幕布）

## ★★ 2026-09-30：老板砍掉了整屏云幕，换图改由「把玩家按进座舱」盖住。
##
## 原话：「**不需要云层了**」→「**把玩家视角跳到座舱内，然后星空盒都是同一片的情况下
## 可以直接换**」。
## ⇒ `RoomCurtain` / `RoomStreamer` 两个类 + `shaders/room_curtain.gdshader`
## **整个删除**（本节原先钉的是那两套状态机）。
##
## ## 这一节现在钉什么
## ① **旧东西真的没了**（三个文件 + `LaunchScript.CURTAIN_*` 三个常量）——
##    幕布复活是这类改动最典型的回归方式，而它不会让任何画面对不上；
## ② **换图本身还行得通**：`apply_map_staged()` 真的换到 LEO、旧图的东西被清干净
##   （`launch_splash` / `launch_cloud_root` 都成 null，不清就是指向已释放节点）；
## ③ **新做法的三处接线都在**（源码事实）：锁座舱档 → 建图 → 放锁，
##    而且"锁"必须进 `_apply_camera_settings()` 那个每帧分支（否则被顶回去）。
static func _swap(t: T, host: Node) -> void:
	t.suite("RocketLaunch / 换图（锁座舱档，无幕布）")

	# ---- ① 幕布确实被删干净了 ----
	for p in ["res://scripts/world/room_curtain.gd", "res://scripts/world/room_streamer.gd",
			"res://shaders/room_curtain.gdshader"]:
		t.not_ok(FileAccess.file_exists(p), "★ 幕布文件已删除：%s" % p)
	# ⚠️ 判据读**源码**而不是 `LaunchScript.get("CURTAIN_IN")`：那三个常量已经不存在，
	# 写成 `LaunchScript.CURTAIN_IN` 会**编译失败**（整个套件一条都跑不了），
	# 而 `Object.get()` 是非静态方法、**不许在类上调用**。
	# 查 `const CURTAIN_` 而不是 `CURTAIN_`：头注里刻意留着一段"这三个常量已删除"的说明，
	# 查裸词会把那段说明本身判成"幕布还在"。
	var lsrc := FileAccess.get_file_as_string("res://scripts/data/launch_script.gd")
	t.not_ok(lsrc.contains("const CURTAIN_"),
		"★ `LaunchScript` 里不再有 `const CURTAIN_*`（幕布的时长常数已随幕布删除）")

	# ---- ② 换图本身（真的建两张图）----
	var w := WorldBuilder.new()
	w.name = "SwapProbe"
	w.initial_map = MapDef.Id.PACIFIC
	host.add_child(w)
	await host.get_tree().process_frame
	t.eq(w.map.id, MapDef.Id.PACIFIC, "起手是太平洋图")
	t.ok(w.get("launch_splash") != null,
		"★ 太平洋图建出了出水特效（换图之后它必须被清掉）")

	await w.apply_map_staged(MapDef.leo())
	t.eq(w.map.id, MapDef.Id.LEO, "★ `apply_map_staged()` 之后 `world.map` 是 LEO")
	t.eq(w.map.terrain, MapDef.Terrain.SPACE,
		"  而且地表种类是 SPACE（不是落进了 ISLANDS 兜底）")
	t.eq(w.get("launch_splash"), null,
		"★★ 换到 LEO 之后 `launch_splash` 被清成 null（不清就是指向已释放节点）")
	t.eq(w.get("launch_cloud_root"), null,
		"★★ 换到 LEO 之后 `launch_cloud_root` 也被清成 null（同一条理由 —— 两个都在 `_map_stage_free()` 里）")

	w.free()
	await host.get_tree().process_frame

	# ---- ③ 新做法的接线（源码事实）----
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	t.ok(src.contains("func _swap_to_orbit() -> void:"),
		"★ 换图走 `main._swap_to_orbit()`（一个显式命名的协程，不是散在 `_tick_launch()` 里的三行）")
	t.ok(src.contains("_swap_eye_lock = true"), "★ 换图前**闩上**座舱档")
	t.ok(src.contains("await world.apply_map_staged(MapDef.leo())"),
		"★ 换的是 LEO 图，而且 await 到建完")
	t.ok(src.contains("_orbit_swap_done = true"),
		"★ 建完有一个显式的位（`_finish_launch()` 靠它，不能只看启动位）")
	# ⚠️ 2026-09-30：眼位档的来源从 `Settings.first_person` 换成**发射段自己那一位**
	#（`_launch_eye_cockpit`，由 F1 翻 —— 老板：「可以随便按F1切换火箭时候仓内的
	# 第一人称视角」）。判据跟着改，**但"必须进每帧分支"这条不变**。
	t.ok(src.contains("_launch_eye_cockpit or _swap_eye_lock"),
		"★★ 锁**必须**进 `_apply_camera_settings()` 那个每帧分支 —— 只调一次 `set_launch_eye()` 会被下一帧顶回去，而「遮住换图」就静默失效了")
	t.ok(src.contains("if phase == Phase.LAUNCH") and src.contains("_launch_eye_cockpit = not _launch_eye_cockpit"),
		"★★ F1 在发射段也生效（`_handle_global_input()` 里，**在 `phase != Phase.FIGHT` 早退之前**）")
	t.ok(src.contains("chase.externally_stepped = true"),
		"★★ 发射段接管相机的时钟（相机与火箭同一个钟，见 `ChaseCamera.step_now()` 头注）")
	t.not_ok(src.contains("RoomStreamer"),
		"★★ `main.gd` 里不再有任何幕布引用（复活回归会在这里变红）")
	t.not_ok(src.contains("RoomCurtain"),
		"  同一个判据的另一半")
	# ⚠️ 别只查"有没有这个词"：注释里提一句也会命中。上面两条查的是**全文件**，
	# 所以源码注释里也不许留着这两个类名（`grep` 得到的东西才是判据的真源）。
	# ⚠️ 右边界取**下一个函数**，不写死字符数：这里原来写死 2000，
	# 而注释越写越长，目标行一路滑到 2031 ⇒ 那条断言变成"永远不红也不绿"
	#（`[]` 之间静默截断，没有任何提示）。
	var tick0 := src.find("func _tick_launch(")
	var tick := src.substr(tick0, src.find("func _finish_launch(") - tick0)
	t.ok(tick.contains("not _orbit_swap_started"),
		"★ 换图只启动一次（`_tick_launch()` 里那个守卫）")
	t.ok(tick.contains("if _orbit_swap_done and rocket.u >= 1.0:"),
		"★ 交还操控的条件是「建完 **且** 抵达」，不是「启动过」")



# ============================================================ ⑦ 发射点（出水特效）

## ⚠️ 这一节原来钉的是「海上发射平台」（`launch_pad_root` / `PAD_RADIUS` / `pad_pos()`）。
## 平台已于 2026-09-30 被老板砍掉（「不需要用发射平台，直接从海里面出来就行了」）
## ⇒ 发射点上**一件实体几何都没有**，只剩水与出水特效 `SeaSplash`。
## 那几条断言钉的对象已经不存在（`pad_pos()` / `PAD_RADIUS` 名字都找不到 ⇒
## 整个套件 Parse Error、一条都跑不了），所以整节改成钉**出水特效的接线** ——
## 它现在是发射点上唯一的那件东西。

static func _launch_site(t: T, host: Node) -> void:
	t.suite("RocketLaunch / 海上发射点（出水特效接线）")
	var w := WorldBuilder.new()
	w.name = "LaunchSiteProbe"
	w.initial_map = MapDef.Id.PACIFIC
	host.add_child(w)
	await host.get_tree().process_frame

	var sp: SeaSplash = w.launch_splash
	t.ok(sp != null, "太平洋图建出了 `launch_splash`（出水特效 —— 平台删掉后发射点唯一的实体）")
	if sp != null:
		# ★ 它与火箭**读同一个函数** `LaunchScript.launch_pos()`。
		# ⚠️ 两边分家不报任何错，画面读到的是「火箭从这儿出水、水面在几百米外冒泡」。
		t.near(sp.position.distance_to(LaunchScript.launch_pos()), 0.0, 1e-3,
			"出水特效**正好落在** `LaunchScript.launch_pos()`（与火箭出生点同源）")
		# ★ 刚建好必须是**熄的**：静置 / 倒计时期间海面就冒水是错的，点火由 `begin()` 给。
		t.not_ok(sp.active, "刚建好时特效是熄的（点火由 `begin()` 给，不是一建好就喷）")

	# ★ 发射点在图的**外圈**：航道浮标与灯塔平台都在 40 km 之外，
	# 火箭起飞不会一头撞进已有的那两件人造物里。
	t.gt(LaunchScript.launch_pos().length(), WorldBuilder.ARENA_RADIUS * 0.15,
		"发射点离图心 %.1f km（远于大多战斗发生的那一圈）" % (LaunchScript.launch_pos().length() / 1000.0))

	# ---- ★ 发射点上空那垛**真云几何**（老板：「云层贴图过于敷衍了，需要用模型遮挡」）----
	#
	# ## 这一段为什么是"结构判据"而不是"几何判据"
	# 高度那一列（`CLOUD_FLOOR` 硬地板 / 每片云底 ≥ 1500 m）**只能在带窗口的探针里量**：
	# ⚠️ 无头环境下 `MultiMesh.get_instance_transform()` 一律回**单位变换**
	#（`instance_count` 却是准的）⇒ 在这里量高度会得到一片"全部堆在原点"的假读数，
	# 而那种读数**看起来还很有条理**（正好能"证明"云都在海拔 0 m）。
	# ⇒ 真几何读数归 `tools/_rocket_shots.gd`（带窗口），这里只钉**接线与不变量**。
	var cr: Node3D = w.get("launch_cloud_root")
	t.ok(cr != null, "太平洋图建出了 `launch_cloud_root`（发射点上空的云垛）")
	if cr != null:
		var layers: Array[MultiMeshInstance3D] = []
		for c in cr.get_children():
			var mm := c as MultiMeshInstance3D
			if mm != null:
				layers.append(mm)
		t.eq(layers.size(), 1, "云垛是**一层** MultiMesh（%d 层）" % layers.size())
		var total := 0
		for mm in layers:
			t.ok(mm.multimesh != null, "层 `%s` 有 MultiMesh" % mm.name)
			if mm.multimesh != null:
				total += mm.multimesh.instance_count
		# 26 团 × 34~58 盘 = 884~1508。给一个宽但**能挡住"忘了建"**的下界。
		t.between(total, 800, 1600,
			"云垛一共 %d 片（26 团 × 34~58 盘 —— 这个量级才读得出「一垛有体积的积云」）" % total)
		# ★ 材质必须**复用主积云那一份**：不复用的话这一垛不会跟着
		# `apply_time_of_day()` 换色 —— 夜图里它会是一垛白得发光的云，
		# 而"别的云都对，就这一垛不对"很难被归因到材质上。
		var mid: ShaderMaterial = w.get("_cloud_mat_mid")
		t.ok(mid != null, "`_cloud_mat_mid` 存住了（主积云材质，供云垛复用）")
		if layers.size() > 0 and layers[0].multimesh != null and mid != null:
			t.eq(layers[0].multimesh.mesh.material, mid,
				"★ 云垛复用**主积云材质**（同一份 ⇒ 跟着时段换色，不会夜里白得发光）")
		# ★ 不许挂进 `islands_root`：那是一条"老板要求删岛"的守护线（同平台那次的坑）。
		var ir: Node = w.get("islands_root")
		t.ok(ir != null, "islands_root 仍然建出来（空容器）")
		if ir != null:
			t.eq(ir.get_child_count(), 0,
				"★ 云垛**不在** `islands_root` 里（那会顶红「一座岛都没有」那条守护线）")

	# ★ `CLOUD_FLOOR` 硬地板：这里只能钉**源码事实**（真几何见上面那段说明）。
	# 它挡的是"谁把那一行 `maxf(at.y, CLOUD_FLOOR + ...)` 顺手删掉" ——
	# 删掉之后会有一片云垂到海面上，而那只在**带窗口的探针图**上看得出来。
	var wsrc := FileAccess.get_file_as_string("res://scripts/world/world_builder.gd")
	t.ok(wsrc.contains("at.y = maxf(at.y, CLOUD_FLOOR + s * 0.62 * 0.5)"),
		"★ 云垛那层守着 `CLOUD_FLOOR` 硬地板（与 `_lay_cloud_band()` 逐字同一条不变量）")
	t.ok(wsrc.contains("func _build_launch_pad") == false,
		"★ 海上平台**已经不存在**（老板：「不需要用发射平台，直接从海里面出来就行了」）")

	w.free()
	await host.get_tree().process_frame


# ============================================================ ⑨ 出水特效 / 发射段机位

## `SeaSplash` —— **老板砍掉平台之后，这件东西就是"从海里出来"的全部可读性**。
##
## ## 2026-09-30 第二版：水柱 → **烟雾**（老板原话）
## > 「**发射时候的周围环绕的东西做成风压太丑陋了，还不如做成烟雾呢**」
##
## 第一版的第二件是一根圆柱壳（`SplashColumn`：半径 62~96 m、与箭**同 XZ**）。
## 真机像素实测 `02_breach_side` 亮 0.9416 / 均值 167.7、`04_rocket_side` **整幅 255** ——
## 那不是"水"，是一层**包住箭体的白壳**（老板说的"风压"）。
## 现在两件：**泡沫环**（水面的反应）+ **72 团在环上向外滚的球**（烟）。
##
## ## ⚠️ 它的读数是**两个不同的自变量**（刻意的，也是判据要分开钉的原因）
##   · **几何 / 浓度** ← 箭底高度：环半径、烟环半径、球大小、引擎火光
##   · **透明度** ← 时间 `_t`（淡入 0.18 s、环的寿命 9.5 s）
## ⇒ 环会先没了烟还在、烟没了环还在 —— 两件各自能单独关（两条断言各钉一边）。
##
## ## ★★ 半径**必须**跟高度走，不能跟时间走（这一节最贵的一条）
## `LaunchScript.ALT_SHAPE = 3.64` 是"前段极缓"的曲线：点火后 `t = 2 s` 箭底才 −31.7 m、
## **`t = 4.19 s` 才越过海面**。半径若按时间扩散，出水那一刻环已经涨到 **798 / 860 m**
## ⇒ 画面是「火星一响，海面先自己炸开一圈 800 m 白环，然后干等 4 秒才有箭冒出来」——
## 环与箭**两件不相干的事**。第一版正是这个，而它在图上"看着还挺壮观"，
## 只有把半径当读数量出来才看得出是错的。
##
## ## ★★ 烟为什么必须"球心不在轴上"
## 第一版被砍掉的那根白筒之所以是筒，就因为**它与箭同轴**。而 72 个球心若都落在轴上，
## 会叠出**一模一样**的一根新白柱 —— 绕一圈又回到原处。所以这一节直接量
## `puff_transform()` 里每一团**离中轴的距离**（`min_off > 箭体半径 11.1 m`）。

## 把 `_t` 推到**过了烟的时间闸门**之后（老板 2026-09-30 加的 4 s 门槛）。
##
## ## ⚠️ 为什么必须有这个 helper
## `smoke_alpha = 淡入（`_t`）× 时间闸门（`_t`）× 高度剖面（`alt`）` —— 三个因子。
## 凡是"只按高度验烟"的地方（例如「低于 `SMOKE_FADE_LO` ⇒ 烟最浓」），
## 若不先把 `_t` 推过 4 s，读到的 alpha 恒为 0，而那个 0 看起来像"烟没了"，
## 真原因却是**门槛没过**。加门槛那天这个套件里 4 条断言一起红，就是这么红的。
static func _warm_smoke(s: SeaSplash, alt: float, dt: float) -> void:
	var need := SeaSplash.SMOKE_DELAY + SeaSplash.SMOKE_RAMP + 0.5 - float(s.get("_t"))
	for i in int(ceil(maxf(need, 0.0) / dt)):
		s.update(alt, dt)


static func _splash(t: T, host: Node) -> void:
	t.suite("RocketLaunch / 出水特效（SeaSplash：泡沫环 + 烟）")
	var s := SeaSplash.new()
	host.add_child(s)

	# ★ 建成即熄。**不是洁癖**：主菜单背景用的也是太平洋图
	#（`WorldBuilder._build_launch_splash()` 只有太平洋图才建），
	# 建出来就喷的话玩家会在菜单上看见远处海面自己冒泡沫。
	t.not_ok(s.active, "刚建好是熄的（点火由 `begin()` 给，不是一建好就喷）")
	t.near(s.ring_alpha, 0.0, 1e-9, "刚建好泡沫环 alpha = 0")
	t.near(s.smoke_alpha, 0.0, 1e-9, "刚建好烟 alpha = 0")
	t.not_ok(s.visible, "刚建好整件不可见（`visible = false`，一个像素都不画）")

	# ★ 未点火时 `update()` 必须是**彻底的空转**。
	# 它每帧都被 `main._tick_launch()` 调（那边只判 null，不判 active）⇒
	# 这里漏一个早退，就会变成"没点火水面也在一直算"，而且不报错。
	s.update(LaunchScript.rest_alt(), 1.0 / 60.0)
	t.not_ok(s.active, "未点火时 update() 不会把自己打开")
	t.near(s.ring_alpha, 0.0, 1e-9, "未点火时 update() 是空转（环 alpha 仍为 0）")
	t.near(s.smoke_alpha, 0.0, 1e-9, "  （烟 alpha 也仍为 0）")

	# ---- 点火：`begin()` ----
	s.begin()
	t.ok(s.active, "begin() ⇒ active")
	# ★ `begin()` 把 `_t` 归零 ⇒ **这一帧两个 alpha 都是 0**，于是 `visible` 也是 false。
	# 这**不是** bug：两件都有 0.18 s 淡入（`fade_in = _t / 0.18`），
	# 那一刻本来就没东西可画。钉它是为了挡住"把 `fade_in` 去掉"那种改动 ——
	# 去掉之后出水会**跳**出来（而且 `visible` 会立刻变 true，这条跟着红）。
	t.not_ok(s.visible, "★ 点火那一帧还不可见（淡入 0.18 s 未起，两个 alpha 都还是 0）")
	t.near(s.ring_alpha, 0.0, 1e-9, "  （环 alpha = 0）")
	t.near(s.smoke_alpha, 0.0, 1e-9, "  （烟 alpha = 0）")

	# ---- 淡入之后：静置高度下**环**已经满；**烟**按 4 s 门槛还该是 0 ----
	var dt := 1.0 / 60.0
	for i in 20:
		s.update(LaunchScript.rest_alt(), dt)
	t.gt(s.ring_alpha, 0.9,
		"0.33 s 后泡沫环已经显形（alpha = %.3f）" % s.ring_alpha)
	# ★★ 老板 2026-09-30：「**烟雾要在发射后 4s 再渐变生成**」。
	# 0.33 s 时箭底还在水下 34 m（曲线前段极缓，`t = 4.19 s` 才破水）⇒ 烟必须是 0。
	# ⚠️ 这一条**从前写的是 `> 0.9`**（"箭底还在水下烟已经起来了"），
	# 那正是老板这次要改掉的观感：海面先自己炸出一团烟，而箭还看不见。
	t.near(s.smoke_alpha, 0.0, 1e-9,
		"★ 0.33 s（箭底还在水下 %.0f m）⇒ 烟**一格都没有**（4 s 门槛未到）"
			% LaunchScript.rest_alt())
	t.ok(s.visible, "环在 ⇒ 整件仍然可见（烟没起不影响环）")

	# ---- ★★ 烟的时间闸门：点火后 4 s 才起、再用 `SMOKE_RAMP` 渐变到满 ----
	#
	# 三条一起钉：① 起势前恒 0；② 起势是**渐变**（不是"啪一下整片出现"）；
	# ③ **4 s 这个数不许晚于破水时刻** —— 晚了就是"箭已出水、烟还没起"，
	#    早了就是"箭还在水下就冒烟"。两头都是静默的观感问题，只能靠这两个数对起来判。
	t.near(SeaSplash.smoke_gate_at(0.0), 0.0, 1e-9, "t = 0 ⇒ 闸门 0")
	t.near(SeaSplash.smoke_gate_at(SeaSplash.SMOKE_DELAY), 0.0, 1e-9,
		"★ `t = SMOKE_DELAY`（%.1f s）⇒ 闸门仍是 0" % SeaSplash.SMOKE_DELAY)
	var mid := SeaSplash.smoke_gate_at(SeaSplash.SMOKE_DELAY + SeaSplash.SMOKE_RAMP * 0.5)
	t.gt(mid, 0.2, "  门槛之后就在起（%.3f > 0.2）" % mid)
	t.lt(mid, 0.8, "  而且是**渐变**不是跳变（%.3f < 0.8）" % mid)
	t.near(SeaSplash.smoke_gate_at(SeaSplash.SMOKE_DELAY + SeaSplash.SMOKE_RAMP), 1.0, 1e-9,
		"★ `DELAY + RAMP`（%.1f s）⇒ 闸门满"
			% (SeaSplash.SMOKE_DELAY + SeaSplash.SMOKE_RAMP))
	t.near(SeaSplash.smoke_gate_at(30.0), 1.0, 1e-9, "  之后恒 1（不会回落）")
	# ★★ 闸门早于破水、且贴得够近。
	var t_breach := t_of(LaunchScript.BREACH_ALT)
	t.lt(SeaSplash.SMOKE_DELAY, t_breach,
		"★★ `SMOKE_DELAY`（%.1f s）**早于**破水时刻（%.2f s）—— 晚了就是「箭已出水、烟还没起」"
			% [SeaSplash.SMOKE_DELAY, t_breach])
	t.lt(t_breach - SeaSplash.SMOKE_DELAY, 1.0,
		"  而且贴得够近（差 %.2f s < 1 s）—— 早太多会变成「箭还在水下就冒烟」"
			% (t_breach - SeaSplash.SMOKE_DELAY))
	t.gt(SeaSplash.SMOKE_RAMP, 0.0,
		"★ 有渐变段（`SMOKE_RAMP` %.1f s）；取 0 就是「啪一下整片出现」，读起来像贴图切换"
			% SeaSplash.SMOKE_RAMP)

	# ---- ★★ 泡沫环的**半径**只跟高度走（这一节最关键的一条）----
	#
	# ⚠️ 直读节点 `scale.x`：那是"环现在多大"的唯一真源（`_apply()` 每帧写它）。
	# 拿它做判据才能把"环什么时候涨开"钉住 —— 光看 alpha 是看不出来的。
	var ring := s.get_node_or_null("SplashRing") as MeshInstance3D
	t.ok(ring != null, "泡沫环节点在（`SplashRing`）")
	if ring != null:
		var r0: float = ring.scale.x
		t.near(r0, SeaSplash.RING_R0, 0.5,
			"★ 箭底还在吃水线（%.0f m）⇒ 环是**最小**的 %.0f m（还没开始扩）"
				% [LaunchScript.rest_alt(), SeaSplash.RING_R0])
		# 出水后 130 m（大约出水之后 1 s）—— 应当已经扩开一截，但**远没到最大**。
		s.update(LaunchScript.BREACH_ALT + 130.0, dt)
		var r1: float = ring.scale.x
		t.gt(r1, SeaSplash.RING_R0, "★ 箭往上升 ⇒ 环跟着扩（%.0f → %.0f m）" % [r0, r1])
		t.lt(r1, SeaSplash.RING_R1 * 0.95,
			"  而且**还没长到最大**（%.0f m < %.0f）—— 环是跟箭一起长开的，不是一炸到底"
				% [r1, SeaSplash.RING_R1])
		s.update(LaunchScript.BREACH_ALT + SeaSplash.RING_GROW_ALT, dt)
		t.near(ring.scale.x, SeaSplash.RING_R1, 0.5,
			"★ 箭底到 `RING_GROW_ALT`（%.0f m）⇒ 环长到最大 %.0f m"
				% [SeaSplash.RING_GROW_ALT, SeaSplash.RING_R1])
		s.update(LaunchScript.BREACH_ALT + 3000.0, dt)
		t.near(ring.scale.x, SeaSplash.RING_R1, 0.5, "  再高也不会超过上限（夹住）")
		# ★ 纯函数与真节点必须**同源**：无头环境下 72 个 `MultiMesh` 实例变换读不回来，
		# 所以判据的另一半（方位 / 半径）钉在纯函数上 —— 两者一旦分家，
		# "钉住了"这句话就只对纯函数成立、对画面不成立。
		s.update(LaunchScript.BREACH_ALT + 44.0, dt)
		t.near(s.ring_radius_at(LaunchScript.BREACH_ALT + 44.0), ring.scale.x, 1e-4,
			"★ `ring_radius_at()`（纯函数）与真节点 `scale.x` **逐位同源**")

	# ---- ★★ 烟：球心**不在中轴线上**（老板砍掉的"白筒"就是球心落在轴上叠出来的）----
	#
	# 第一版那根圆柱壳与箭**同 XZ** ⇒ 它必然包住箭；而"72 个球心都落在轴上"会
	# 得到**一模一样**的东西（一串球叠成一根新白柱）。所以这条必须量。
	var min_off := INF
	var max_off := 0.0
	for i in SeaSplash.SMOKE_N:
		var tr := s.puff_transform(i, LaunchScript.BREACH_ALT + 60.0, 0.0)
		var off := Vector2(tr.origin.x, tr.origin.z).length()
		min_off = minf(min_off, off)
		max_off = maxf(max_off, off)
	t.gt(min_off, 11.1,
		"★★ 每一团烟的球心离**中轴**都 > 箭体半径 11.1 m（最近的 %.1f m）—— 球心落在轴上会叠成一根新的白柱"
			% min_off)
	t.gt(max_off, min_off * 1.5,
		"★ 而且是**一圈有厚度的烟**（最近 %.1f m / 最远 %.1f m），不是一圈等距的球"
			% [min_off, max_off])
	# 球心不许沉到水面以下（烟是从水面**涌起来**的，不是从水里浮上来的）。
	# ⚠️ 判据是**球心**在水面之上，不是"球底在水面之上"：
	# 贴水涌起的烟团本来就该被水面切掉一截（切太多才会读成"水下有东西"）。
	var sunk := 0
	var min_center := INF
	var worst_cut := 0.0
	for i in SeaSplash.SMOKE_N:
		var tr2 := s.puff_transform(i, LaunchScript.BREACH_ALT + 300.0, 3.0)
		var rad: float = tr2.basis.x.length()
		min_center = minf(min_center, tr2.origin.y)
		if tr2.origin.y <= 0.0:
			sunk += 1
		worst_cut = maxf(worst_cut, (rad - tr2.origin.y) / (2.0 * rad))
	t.eq(sunk, 0, "★ 没有一团的**球心**沉到水面以下（球心在水下 ⇒ 露出来的只剩一个顶）")
	t.gt(min_center, 0.0, "  最低的球心在 +%.1f m（仍在水面之上）" % min_center)
	t.lt(worst_cut, 0.5,
		"★ 最深的一团最多被水面切掉一半（实算 %.0f%%）—— 烟是**贴水涌起**的，不是浮在水下的球"
			% (worst_cut * 100.0))
	# ★ 烟环与泡沫环**共用同一个自变量**（高度）——
	# 不然图上会出现"环已经扩到最大、烟还没起来"那种两件脱钩的照片。
	t.near(SeaSplash.SMOKE_GROW_ALT, SeaSplash.RING_GROW_ALT, 1e-9,
		"★ 烟与环共用同一个「长开」高度（两件锁在同一个自变量上）")
	t.lt(SeaSplash.SMOKE_FADE_HI, LaunchScript.CLOUD_BASE_ALT,
		"★ 烟在爬到**云底**（%.0f m）之前就散干净（%.0f m）—— 否则玩家在云里还看着脚下一片烟"
			% [LaunchScript.CLOUD_BASE_ALT, SeaSplash.SMOKE_FADE_HI])

	# ---- 烟散尽：只跟**高度**走 ----
	# ⚠️ 先把 `_t` 推过 4 s 门槛。烟的 alpha 现在是「淡入 × 时间闸门 × 高度剖面」
	# 三个因子，**只推高度推不出 alpha** —— 这一节从前就漏在这上面。
	_warm_smoke(s, LaunchScript.rest_alt(), dt)
	s.update(SeaSplash.SMOKE_FADE_LO - 10.0, dt)
	t.gt(s.smoke_alpha, 0.9,
		"箭底还没到 `SMOKE_FADE_LO` ⇒ 烟仍是最浓的（%.3f）" % s.smoke_alpha)
	s.update(SeaSplash.SMOKE_FADE_HI + 10.0, dt)
	t.near(s.smoke_alpha, 0.0, 1e-6,
		"★ 过了 `SMOKE_FADE_HI`（%.0f m）⇒ 烟散干净" % SeaSplash.SMOKE_FADE_HI)

	# ---- 泡沫环：只跟**时间**走，到寿命就散干净 ----
	# ⚠️ 高度压在烟散尽线**以下**，好让"两件是两个自变量"这条能被单独看到。
	var life_steps := int(ceil((SeaSplash.RING_LIFE + 0.5) / dt))
	for i in life_steps:
		s.update(LaunchScript.BREACH_ALT + 100.0, dt)
	t.near(s.ring_alpha, 0.0, 1e-6,
		"过了 RING_LIFE（%.1f s）泡沫环散干净" % SeaSplash.RING_LIFE)
	t.gt(s.smoke_alpha, 0.9,
		"★★ 而烟**还在**（它只跟高度走）—— 两条读数真的是两个自变量，不是同一个")
	t.ok(s.visible, "环没了但烟还在 ⇒ 整件仍然可见（两件各自能单独关）")

	# ---- `dt` 夹取：切窗口 / 卡一帧之后的 0.2 s 量级 dt ----
	# 不夹的话一帧就把环推到最大半径，"炸开"这个动作整个没了（而画面只是"快"）。
	s.begin()
	s.update(LaunchScript.rest_alt(), 5.0)
	t.near(s.get("_t"), 1.0 / 20.0, 1e-9,
		"★ update(dt = 5.0) 只吃到 1/20 s（不让一帧把整段出水跳过去）")

	# ---- `end()` ----
	s.end()
	t.not_ok(s.active, "end() ⇒ 熄灭")
	t.near(s.ring_alpha, 0.0, 1e-9, "end() 之后环 alpha = 0")
	t.near(s.smoke_alpha, 0.0, 1e-9, "end() 之后烟 alpha = 0")
	t.not_ok(s.visible, "end() 之后不可见")
	# ★ 幂等**不是**要求（重复点火 = 重新出水，那是调参时反复播同一段），
	# 但 `end()` 之后再 `update()` **不许**把它弄活 —— 发射段结束后
	# `main._tick_launch()` 已经不再跑了，可这条守卫挡的是"将来谁又接上驱动"。
	s.update(LaunchScript.rest_alt(), dt)
	t.not_ok(s.active, "★ end() 之后再 update() 不会复活（闭合状态）")

	# ---- ★ 源码事实：第一版那根"白筒"不许回来 ----
	var ssrc := FileAccess.get_file_as_string("res://scripts/world/sea_splash.gd")
	# ⚠️ 判据用**带引号**的形式：头注里那句"第一版的第二件是一根圆柱壳（`SplashColumn`）"
	# 是**历史溯源**，不该被这条挡下来。带引号的名字只在真的给节点命名时出现。
	t.ok(not ssrc.contains("\"SplashColumn\""),
		"★ 第一版那根圆柱壳（`SplashColumn` 节点）已经不存在（老板：「做成风压太丑陋了，还不如做成烟雾呢」）")
	var smsrc := FileAccess.get_file_as_string("res://shaders/sea_smoke.gdshader")
	t.ok(smsrc.contains("tint_dark") and smsrc.contains("tint_glow"),
		"★ 烟雾材质是**暗底 + 被引擎火烤亮**（不是纯白 —— 夜里冒出来的烟本来就该是暗的）")
	t.ok(smsrc.contains("MODEL_MATRIX[3].xyz"),
		"★ 逐实例种子取自实例原点（`MultiMesh` 共用一份网格 ⇒ 拿 `VERTEX` 算噪声会 72 团同一个花纹）")

	s.free()


## `ChaseCamera.set_launch_view()` —— **发射段机位**。
##
## ## 为什么这里必须是单独一节
## 火箭是**直立**的（机头 = 机体 −Z = 世界 +Y，见 `RocketBody.upright_basis()`），
## 而默认机位 `offset = (0, 9, 53)` 的局部 +Z 落在世界 **−Y** ⇒
## 相机被放到**箭底下方 53 m**。平台还在的时候这勉强能用（箭底 +50 ⇒ 相机 −3 m）；
## 平台删掉、箭改吃水 34 m 之后 ⇒ 相机 **−87 m，在海面之下**。
## 而"相机在水下"**不报任何错**，画面上只有天空盒 —— 与"这段演出没做出来"一模一样。
## ⇒ 这一节把那个数字**量出来**，把它变成一条会变红的判据。
static func _launch_view(t: T, host: Node) -> void:
	t.suite("RocketLaunch / 发射段机位（相机不许沉到海面下）")
	var cam := ChaseCamera.new()
	cam.name = "LaunchViewProbe"
	host.add_child(cam)

	# ★ 用一串**非默认**值当"玩家的设置"。
	# ⚠️ 拿默认值去验"还原"是**假绿**：写死默认值与真还原**看不出差别**。
	cam.offset = Vector3(1.5, 9.0, 53.0)
	cam.look_ahead = 40.0
	cam.look_up = -7.0
	cam.roll_blend = 0.62

	var rk := RocketBody.new()
	host.add_child(rk)
	rk.configure(LaunchScript.ASCENT_SPAN)
	rk.place_at_launch(LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))
	# ⚠️ 顺序：`set_target()` 必须**先**给 —— `_desired_position()` 在
	# `target == null` 时直接返回 `global_position`，拿它量什么都是假的。
	cam.set_target(rk)

	t.not_ok(cam.launch_view(), "默认不在发射段机位")

	# ---- 切进发射段机位 ----
	cam.set_launch_view(true)
	t.ok(cam.launch_view(), "set_launch_view(true) 生效")
	t.eq(cam.offset, ChaseCamera.LAUNCH_OFFSET, "offset 换成 LAUNCH_OFFSET")
	t.near(cam.look_ahead, ChaseCamera.LAUNCH_LOOK_AHEAD, 1e-9, "look_ahead 换成 LAUNCH_LOOK_AHEAD")
	t.near(cam.look_up, ChaseCamera.LAUNCH_LOOK_UP, 1e-9, "look_up 换成 LAUNCH_LOOK_UP")
	t.near(cam.roll_blend, 0.0, 1e-9,
		"★ roll_blend 压到 0（箭体直立时 `want_up` 是世界 +Z ⇒ 不压的话地平线歪 ~58°）")

	# ★★ 核心判据：**相机现在在海面之上**，而且那个数**推得出来**。
	# ⚠️ `set_launch_view()` 会**立刻落位**（它就是为这件事写的：
	# 不落的话镜头会从上一套机位渐变过去，而那 0.3 s 正是倒计时第一帧）。
	var y_launch: float = cam.global_position.y
	t.gt(y_launch, LaunchScript.BREACH_ALT + 10.0,
		"★★ 切进发射段机位之后相机在**海面之上**（y = %.1f m > %.0f + 10）"
			% [y_launch, LaunchScript.BREACH_ALT])
	t.near(y_launch, LaunchScript.rest_alt() - ChaseCamera.LAUNCH_OFFSET.z, 0.5,
		"  而且正好 = `rest_alt()` + (−`LAUNCH_OFFSET.z`)（两个都是真源，不是凑出来的数）")

	# ---- ★★ 座舱档（`set_launch_eye()`）----
	#
	# 老板第一版：「**在火箭最上端加一个驾驶舱第一人称（不是全周天！）需要建模驾驶舱
	# 视角的 ui 和控制台仪表盘**」；第二版把它否掉了：
	# 「**你驾驶舱做的好丑，直接用全周天驾驶舱的代码吧**」。
	# ⇒ 现在这一档是**纯眼位**（舱内表现走 `hud.gd` 的全周天那一层）。
	# 两档的全部差别就是 `_apply_launch_eye()` 里那三行（机位 / 视线 / 滚转）
	# 外加 `first_person`。
	t.eq(cam.launch_eye(), ChaseCamera.LaunchEye.CHASE,
		"基础档是**贴近追尾**（老板先说的那句：「镜头离火箭太远了，我希望做全程跟随的」）")
	cam.set_launch_eye(ChaseCamera.LaunchEye.COCKPIT)
	t.eq(cam.launch_eye(), ChaseCamera.LaunchEye.COCKPIT, "set_launch_eye(COCKPIT) 生效")
	t.ok(cam.first_person, "★ FPV 通道打开（眼位走 `_fpv_eye_local()`）")
	# ⚠️ 容差取 1e-4 而**不是** 1e-9：`Camera3D.near` 在内核里是 **float32**。
	t.near(cam.near, ChaseCamera.LAUNCH_NEAR, 1e-4,
		"★★ 近裁面**两档相同**（都是 LAUNCH_NEAR）—— 舱改成 2D 叠层之后没有几何可切")
	# ⚠️ 这一条钉的是一个**已经修掉的渲染管线 bug**，别当成废话删掉：
	# 第一版座舱档用 `near = 0.35`，而 `far = ORBIT_FAR`。定点扫描（14 张图）证明
	# **`near ≤ 0.5` × `far = 1e7` 会让 `create_frustum_points` 直接失败**，
	# 后果是**整个 3D 场景不被点亮**（只剩天空盒的星星，亮像素占比 0.835 → 0.096）。
	# ⇒ 两道保险，各自都能独立挡住它：
	# ⚠️ 方向是 **gt**：坏的那个组合是"近裁面**太小**（≤ 0.5）+ 远裁面 1e7"，
	# 所以安全的方向是**把它抬上去**（这一条原来写成 `lt`，红得完全正确）。
	t.gt(ChaseCamera.LAUNCH_NEAR, 0.6,
		"  而且近裁面被**抬到了**安全区（%.2f > 0.5）" % ChaseCamera.LAUNCH_NEAR)
	t.ok(ChaseCamera.LAUNCH_NEAR <= 1.5,
		"  但也别抬过头：> 1.5 会把箭体自己贴近相机的那一段切掉（%.2f）" % ChaseCamera.LAUNCH_NEAR)
	t.ok(ChaseCamera.ORBIT_FAR <= 7.0e6,
		"★★ 轨道图的远裁面 ≤ 7 000 km（`far = 1e7` 那一档会把整场景点不亮，见 `ORBIT_FAR` 里那张表；实测 %.0f km）"
			% (ChaseCamera.ORBIT_FAR / 1000.0))
	# 几何上还够不够看：相机在轨高 550 km，地球切线圆离相机 ≈ 2 703 km。
	t.gt(ChaseCamera.ORBIT_FAR, 3.0e6,
		"  但也不能砍过头：地球剪影离相机 ≈ 2 703 km，远裁面得盖得住（%.0f km）"
			% (ChaseCamera.ORBIT_FAR / 1000.0))
	t.near(cam.roll_blend, ChaseCamera.COCKPIT_ROLL, 1e-9,
		"★ 滚转完全跟机体 —— 全周天那层刻度导轨钉在**世界**上，"
			+ "相机上向量若还是世界 UP，机头轴会与世界 UP 共线 ⇒ `looking_at` 退化")
	t.near(cam.look_ahead, ChaseCamera.COCKPIT_LOOK_AHEAD, 1e-9,
		"★ 视线 = **机头轴线**（不是追尾档那个「看箭体中段」的点）")

	# ★★ 相机必须**正好落在眼位**上。
	# ⚠️ 刻度导轨 / 取景框 / 仪表台全以**相机所在那一点**为原点 ——
	# 差 12 cm 在画面上就是"仪表说平飞、而导轨画的是一条歪的地平线"，
	# 而那看起来只像美术没对齐。
	var eye_local := rk.cockpit_eye_local()
	var eye_want: Vector3 = rk.global_transform * eye_local
	t.near(cam.global_position.distance_to(eye_want), 0.0, 0.5,
		"★★ 座舱档的相机**落在眼位**上（火箭局部 %s）" % str(eye_local))
	t.gt(cam.global_position.y, LaunchScript.rest_alt() + RocketBody.ROCKET_HEIGHT_M,
		"★ 眼位在**箭顶之上**（y = %.1f m > 箭底 %.0f + 箭高 %.0f）—— 取在箭高以内会落进壳体内部"
			% [cam.global_position.y, LaunchScript.rest_alt(), RocketBody.ROCKET_HEIGHT_M])
	t.near(eye_local.distance_to(rk.rig_anchor("head")
			+ Vector3(0.0, ChaseCamera.FPV_EYE_UP, -ChaseCamera.FPV_EYE_FWD)), 0.0, 1e-6,
		"★ 眼位 = 头部锚点 + `ChaseCamera.FPV_EYE_*`（与 FPV 通道**同一个算式**，不是各抄一份数）")

	cam.set_launch_eye(ChaseCamera.LaunchEye.CHASE)
	t.eq(cam.launch_eye(), ChaseCamera.LaunchEye.CHASE, "切回追尾档")
	t.near(cam.near, ChaseCamera.LAUNCH_NEAR, 1e-4, "近裁面还回 LAUNCH_NEAR")
	t.not_ok(cam.first_person,
		"★ FPV 关掉（不然切回战斗时玩家会以**座舱视角**开机体，而那是另一个舱）")
	t.eq(cam.offset, ChaseCamera.LAUNCH_OFFSET, "机位还回 LAUNCH_OFFSET")

	# ★★ 反过来量一次**默认机位** —— 这一条是这一整套 `LAUNCH_*` 常量存在的理由。
	# 切回"非发射段"时它同样会立刻落位，用的是**刚还原回来的** offset（z = 53，
	# 与真默认的 53 同值）⇒ 量出来的就是玩家在战斗段用的那个机位。
	cam.set_launch_view(false)
	var y_default: float = cam.global_position.y
	t.lt(y_default, LaunchScript.BREACH_ALT,
		"★ 而**默认机位**把相机放到 **海面之下**（y = %.1f m = 箭底 %.0f − 53）—— 这就是必须另配一套的原因"
			% [y_default, LaunchScript.rest_alt()])
	t.near(y_launch - y_default, -ChaseCamera.LAUNCH_OFFSET.z + 53.0, 1.0,
		"  两套机位相差 %.0f m（= 78 + 53）" % (y_launch - y_default))

	# ★ 最低高度保险：把箭压到"比设计的还低"（改吃水 / 改曲线起点）时那道 `maxf` 要接管。
	#
	# ⚠️ 期望值**推得出来**：箭底 −234 + 抬高量 78 = −156，
	# 而保险把它抬到 `BREACH_ALT + LAUNCH_MIN_ALT` = 14。
	# 拿"没被夹时的自然值"当反例 —— 否则这条断言在"保险根本没生效"时**也是绿的**。
	rk.global_position.y = LaunchScript.rest_alt() - 200.0
	cam.set_launch_view(true)
	var y_floor: float = cam.global_position.y
	t.near(y_floor, LaunchScript.BREACH_ALT + ChaseCamera.LAUNCH_MIN_ALT, 0.5,
		"★ 箭被压到吃水线以下 200 m 时，**保险**把相机夹在 `BREACH_ALT + LAUNCH_MIN_ALT`（%.1f m）"
			% (LaunchScript.BREACH_ALT + ChaseCamera.LAUNCH_MIN_ALT))
	var y_natural := LaunchScript.rest_alt() - 200.0 - ChaseCamera.LAUNCH_OFFSET.z
	t.gt(y_floor, y_natural,
		"  而且确实**高于**没夹时的自然值 %.1f m（保险真的动了手）" % y_natural)

	# ---- ★★ 舱外档：相机**一直和火箭保持一个距离**（老板 2026-09-30 第三次改）----
	#
	# > 「**不需要云层了，相机要一直和火箭保持一个距离**」
	#
	# ## 为什么必须真的跑 `_physics_process()` 才算数
	# `_desired_position()` 算出来的那个机位**本来就是刚性的**
	#（`target.global_transform * LAUNCH_OFFSET`）⇒ 只量它是**自证**：它当然恒定。
	# 真正会漂的是**位置跟随那一步**（`global_position.lerp(want, 1-exp(-lag·dt))`，
	# 匀速下稳态落后 `v / lag`）。所以这里真的把相机推 100 步，而且每步之间
	# 把箭**瞬移** 8 km —— 对弹簧来说"目标一帧跳 8 km"是最狠的输入，
	# 旧版会在这里露出上千 m 的落后。
	#
	# ⚠️ 手动调 `_physics_process()` 而**不是** `await physics_frame`：后者会把本函数
	# 变成协程，而 `run()` 里那一行是**同步调用**（`_launch_view(t, host)`）——
	# 少一个 `await`，整节就会在第一个 `await` 处永久挂起、断言一条都不跑，
	# 报告里只留一个空壳（本文件头注写过这个坑，代价是一整轮静默失效）。
	cam.set_launch_view(true)
	var want_d := ChaseCamera.LAUNCH_OFFSET.length()
	var d_min := INF
	var d_max := -INF
	for i in 5:
		rk.global_position = LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0)
		cam._physics_process(1.0 / 60.0)
		for k in 20:
			rk.global_position += Vector3(0.0, 8000.0, 0.0)
			cam._physics_process(1.0 / 60.0)
			var d := cam.global_position.distance_to(rk.global_position)
			d_min = minf(d_min, d)
			d_max = maxf(d_max, d)
	t.near(d_min, want_d, 0.5,
		"★★ 上升全程（含每帧 8 km 的瞬移）相机离箭**恒定** %.2f m（= `LAUNCH_OFFSET.length()`）" % want_d)
	t.near(d_max, want_d, 0.5,
		"  上界同样贴着 %.2f m（不是「先被甩开再慢慢收敛」）" % want_d)
	t.near(d_max - d_min, 0.0, 0.5,
		"  极差 %.3f m ⇒ 距离**不随速度变**（旧版弹簧在 8 km/s 时会落后 1 231 m）"
			% (d_max - d_min))

	# ---- ★★ `externally_stepped` 那道闸（2026-09-30 的核心修法）----
	#
	# ## 为什么这条必须是**行为级**、不能只查源码子串
	# 闸写错方向的症状全是**静默**的：
	#   · 开了闸而 `_physics_process()` 照样落位 ⇒ 一个渲染帧里相机被两个钟各推一次
	#     （相位反而更乱，比不修还糟）；
	#   · 闸关不掉 ⇒ 发射段的显式驱动又被物理钟盖一层。
	# 两种都只在**某一档刷新率**下显形，截图与"距离对不对"都看不出来。
	# ⇒ 这里真的调这两个函数，量相机动没动。
	cam.set_launch_view(true)
	rk.global_position = LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0)
	cam.global_position = rk.global_position + Vector3(1000.0, 0.0, 0.0)   # 故意站错 1 km
	cam.externally_stepped = true
	var pos_before: Vector3 = cam.global_position
	cam._physics_process(1.0 / 60.0)
	t.eq(cam.global_position, pos_before,
		"★★ `externally_stepped = true` 时 `_physics_process()` **一毫米都不动**"
			+ "（发射段整段让给渲染钟 —— 这就是「两个钟」那条修法）")
	cam.step_now(1.0 / 60.0)
	t.gt(cam.global_position.distance_to(pos_before), 1.0,
		"  而 `step_now()` 确实把相机推走了 ⇒ 「谁驱动」这一位真的在接线（不是只定义了变量）")
	t.near(cam.global_position.distance_to(rk.global_position), want_d, 0.5,
		"  而且**一步**就落到刚性距离 %.2f m（位置是硬落的，不是慢慢收敛）" % want_d)

	cam.externally_stepped = false
	cam.global_position = rk.global_position + Vector3(1000.0, 0.0, 0.0)
	var pos_b2: Vector3 = cam.global_position
	cam._physics_process(1.0 / 60.0)
	t.gt(cam.global_position.distance_to(pos_b2), 1.0,
		"★★ 闸放掉之后 `_physics_process()` **立刻恢复**驱动"
			+ "（战斗段一个字没动的依据：那边这一位恒为假）")
	t.near(cam.global_position.distance_to(rk.global_position), want_d, 0.5,
		"  恢复之后同样落在刚性距离 %.2f m 上" % want_d)

	# ★ 出段必须把这一位放掉 —— 两处都放（`set_launch_view(false)` 与
	# `main._finish_launch()`），任一条路径都不该被**永久锁在渲染钟**上。
	cam.externally_stepped = true
	cam.set_launch_view(false)
	t.not_ok(cam.externally_stepped,
		"★ `set_launch_view(false)` 顺手把外部驱动放掉（否则出段之后相机再也不落位）")
	cam.externally_stepped = false
	cam.set_launch_view(true)

	var csrc := FileAccess.get_file_as_string("res://scripts/flight/chase_camera.gd")
	t.ok(csrc.contains("func _rigid_chase() -> bool:"),
		"★ 舱外档有自己的刚性判据 `_rigid_chase()`（**不复用** `_rigid_eye()`："
			+ "舱内要连姿态一起硬落位，舱外只硬落**位置**、姿态仍走 slerp）")
	t.ok(csrc.contains("if _rigid_chase():"),
		"  而且 `_physics_process()` 里真的分了这一支（只定义不接线 = 距离照旧漂）")
	t.ok(csrc.contains("global_position = want_pos"),
		"  ……刚性分支里位置是**硬写**的，不是再算一次 lerp")

	# ---- 还原：四个值必须**逐位**回到"玩家设置的那一份" ----
	cam.set_launch_view(false)
	t.not_ok(cam.launch_view(), "set_launch_view(false) 生效")
	t.eq(cam.offset, Vector3(1.5, 9.0, 53.0), "offset 原样放回")
	t.near(cam.look_ahead, 40.0, 1e-9, "look_ahead 原样放回")
	t.near(cam.look_up, -7.0, 1e-9, "look_up 原样放回")
	# ⚠️ 这一条挡的是"写死一个默认值"的还原方式：那会把玩家在设置页里
	# 调过的镜头滚转**悄悄覆盖掉**，而且只在"打过一局发射段之后"才发生。
	t.near(cam.roll_blend, 0.62, 1e-9,
		"★ roll_blend 原样放回（写死一个数会覆盖玩家的无障碍设置）")

	# ★ 空转安全：`_clear_match()` **每局重开都调**它，没切过时必须是彻底的空操作。
	cam.set_launch_view(false)
	t.eq(cam.offset, Vector3(1.5, 9.0, 53.0),
		"已经不在发射段机位时再调一次是空操作（`_clear_match()` 每局都调，依赖这条）")

	# ---- ★★ ⑨″ 发射段的「FOV 速度项」（2026-09-30 晚补，两版）----
	#
	# ## 症状（一个**只看得见、量不出**的缺陷）
	# `ChaseCamera._update_fov()` 用**鸭子类型**读目标的速度：
	#     if t.has_method("speed_fov_mix"):        # 目标自报（0…1）
	#         sp = clampf(t.speed_fov_mix(), 0.0, 1.0)
	#     elif t.has_method("airspeed_kmh"):        # 通用窗口（机体域 300…1900 km/h）
	#         sp = clampf((t.airspeed_kmh() - 300.0) / 1600.0, 0.0, 1.0)
	# `RocketBody` 原本**两个都没有** ⇒ `sp` 恒 0 ⇒ **整段 60 s 上升**的 FOV
	# 恒 `base_fov` 68°，末段 35 km/s 一点广角都不张。
	#
	# ⚠️ 它不报任何错、也不动任何几何判据（距离照样精确 80.92 m）——
	# 只表现为"画面没有速度感"，而截图与距离读数一个字都抓不到它。
	#
	# ## ★★ 第二版：只加 `airspeed_kmh()` 是**不够**的
	# 通用窗口的量程是**机体域** 300…1900 km/h，而这枚箭末速 126 000 km/h
	# ⇒ `sp` 在第 **8 s** 就顶到 1.0、FOV 钉在 90°、**之后 44 s 一动不动**
	#（实测：FOV 恒 90°、箭占屏高恒定 35.8%）。
	# 那是把"速度项是死的"换成了"速度项 3/4 时间不动"，**依然没有**速度感。
	# ⇒ 出货版走 `speed_fov_mix()`：**对数**响应、渐近线 0.55 < 1 ⇒ 永不触顶。
	# 实测 FOV 68.00° → 80.09°，`t95` = 89.2%（95% 的行程铺到第 53.5 s 才走完）。
	#
	# ⇒ 这一节钉**三跳**，每一跳的失败模式都是**静默**的：
	#   ① `_update_fov()` 优先不优先问 `speed_fov_mix()`（顺序反了 = 白加）；
	#   ② `speed_fov_mix()` 会不会**顶死**（触到 1.0 = 退回第一版）；
	#   ③ 相机**真的吃到了没有**（定义了但没接线 ⇒ 一样是死的）。
	cam.set_launch_view(true)
	rk.configure(LaunchScript.ASCENT_SPAN)
	rk.place_at_launch(LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))

	# ---- ① 接线顺序（源码守卫：只能挡"接错"，挡不住"顶死"）----
	var csrc2 := FileAccess.get_file_as_string("res://scripts/flight/chase_camera.gd")
	var i_mix := csrc2.find("has_method(\"speed_fov_mix\")")
	var i_kmh2 := csrc2.find("has_method(\"airspeed_kmh\")", i_mix + 1)
	t.ok(i_mix >= 0,
		"★★ `_update_fov()` 会去问目标要 `speed_fov_mix()`（速度项那条链的第一跳）")
	t.ok(i_mix >= 0 and i_kmh2 > i_mix,
		"  ……而且排在通用窗口 `airspeed_kmh()` **之前**（`elif` 顺序反了 = 白加）")
	var rsrc2 := FileAccess.get_file_as_string("res://scripts/flight/rocket_body.gd")
	for key in ["func airspeed_kmh() -> float:", "func speed_fov_mix() -> float:",
			"LaunchScript.END_SPEED_MS"]:
		t.ok(rsrc2.contains(key),
			"★★ `RocketBody` 里有 `%s`（缺了它 ⇒ `sp` 恒 0 ⇒ 整段广角不张，且**不报错**）" % key)

	# ---- ② `sp` 整段单调不减、且**从不触到 1.0** ----
	# `rk.velocity` 直接摆到曲线速度上：`speed_fov_mix()` 只读 `speed()`。
	var prev_sp := -1.0
	var sp_min := 2.0
	var sp_max := -1.0
	var n_back := 0
	for k in range(0, 61):
		rk.velocity = LaunchScript.ascent_velocity(float(k) / 60.0)
		var sp: float = rk.speed_fov_mix()
		sp_min = minf(sp_min, sp)
		sp_max = maxf(sp_max, sp)
		if sp < prev_sp - 1e-9:
			n_back += 1
		prev_sp = sp
	t.ok(n_back == 0,
		"★★ `speed_fov_mix()` 在 u∈[0,1] 全程**单调不减**（回撤 %d 次）" % n_back)
	t.ok(sp_max < 1.0 - 1e-6,
		"★★ 峰值 %.4f **永不触到 1.0** ⇒ 相机那侧 `clampf` 一辈子不生效（触到就是「顶死」）"
			% sp_max)
	t.ok(sp_max > 0.40,
		"  同时峰值 %.4f 足够大 ⇒ 不是「加了等于没加」" % sp_max)
	t.near(sp_min, 0.0, 1e-6, "  起点速度 0 ⇒ `sp` 恰好 0（FOV 从 `base_fov` 起步，不跳）")
	t.near(rk.airspeed_kmh(), rk.speed() * 3.6, 1e-3,
		"  且 `airspeed_kmh()` 与 `FlightModel` **同一条公式**（`speed × 3.6`，不另立一份）")

	# ---- ③ 真的把箭飞起来，看相机吃没吃到 ----
	rk.velocity = Vector3.ZERO
	cam.motion_scale = 1.0
	cam.boost_amount = 0.0
	cam.fov = cam.base_fov
	for _i in range(240):
		cam._update_fov(1.0 / 60.0)
	t.near(cam.fov, cam.base_fov, 0.5,
		"  · 速度 0：FOV 稳在 `base_fov` %.1f°（速度项还没参与）" % cam.base_fov)

	var fov_before: float = cam.fov
	for i in 3000:
		rk.step(1.0 / 60.0, 0.0, 0.0, 0.0)
		cam.step_now(1.0 / 60.0)
	t.gt(rk.speed(), 10000.0,
		"  先飞到高速区当靶子：u = %.3f / 箭速 %.1f km/s" % [rk.u, rk.speed() / 1000.0])
	t.gt(cam.fov, cam.base_fov + 8.0,
		"★★ 高速段的 FOV **真的张开了**（%.2f° → %.2f°，起点 `base_fov` %.0f°）"
			% [fov_before, cam.fov, cam.base_fov])
	# ⚠️ 上界这条才是第二版的**主判据**：不许顶到 `base_fov + fov_per_speed`。
	# 顶到 = "第 8 s 之后一动不动"，而那正是被否掉的第一版 ——
	# 它同时也能抓出"忘了走 `speed_fov_mix()`、退回通用窗口"这种接错。
	t.lt(cam.fov, cam.base_fov + cam.fov_per_speed - 0.5,
		"★★ 而且**没顶到** `base_fov` %.0f° + `fov_per_speed` %.0f° = %.1f°"
			% [cam.base_fov, cam.fov_per_speed, cam.base_fov + cam.fov_per_speed]
			+ "（顶到 = FOV 8 秒走完、之后 44 s 钉死 —— 第一版的病）")
	t.near(cam.fov, cam.base_fov + cam.fov_per_speed * rk.speed_fov_mix(), 1.5,
		"  实测 %.2f° ≈ `base_fov` + `fov_per_speed` × 当前 `sp` %.4f（两跳一致，不是巧合）"
			% [cam.fov, rk.speed_fov_mix()])

	cam.set_launch_view(false)
	cam.free()
	rk.free()

	# ---- ★★ 机位在哪一侧 ↔ 操纵两个通道的符号（**两者必须成对**）----
	#
	# 老板 2026-09-30 晚：「**镜头转过去拍火箭的另外一面**」⇒ `LAUNCH_OFFSET.y`
	# 由 `+62` 变 `−62`。机位绕箭体轴转了 180° ⇒ 相机自己的 `right` 轴整体换向
	#（它由 `Basis.looking_at()` 定）⇒ 屏幕上的"左右"与"上下"**两个通道同时镜像**。
	#
	# 实测数（`tools/_launch_ctrl_probe.gd` —— 量的是"机头**单位向量**的变化量
	# 点乘相机两轴"，且**减掉了零输入基线**；第一版量屏幕投影位移是假读数，
	# 因为箭在 90 帧里一直飞）：
	# ```
	#                    offset.y = +62        offset.y = −62
	#   pitch_in = +1     sy = +0.0063（上）    sy = −0.0069（下）
	#   yaw_in   = +1     sx = −0.0171（左）    sx = +0.0171（右）
	# ```
	#
	# ⚠️ 这一对**错了不报任何错**：改机位不改符号 = 玩家按左键往右转，
	# 而它没有任何几何判据能抓（相机是"追尾硬落位"的，不是解析式）。
	# ⇒ 只能把源码里那两个符号与 `LAUNCH_OFFSET.y` 的**符号**钉在一起。
	var msrc := FileAccess.get_file_as_string("res://scripts/main.gd")
	var ia := msrc.find("func _launch_axis()")
	t.ok(ia >= 0, "`main.gd` 有 `_launch_axis()`")
	if ia >= 0:
		var body := msrc.substr(ia, 700)
		var i_ret := body.find("return Vector3(")
		var seg := body.substr(i_ret, 420) if i_ret >= 0 else ""
		var flip := ChaseCamera.LAUNCH_OFFSET.y < 0.0
		t.ok(seg != "", "  能读到那个 `return Vector3(...)`")
		var i_up := seg.find("pitch_nose_up")
		var i_dn := seg.find("pitch_nose_down")
		var i_lf := seg.find("yaw_left")
		var i_rt := seg.find("yaw_right")
		t.ok(i_up >= 0 and i_dn >= 0 and i_lf >= 0 and i_rt >= 0,
			"  两条通道都由 `pitch_nose_*` / `yaw_*` 这两对动作驱动")
		t.ok((i_dn < i_up) == flip,
			"★★ 机位在 %s 侧 ⇒ 俯仰那一根%s（探针实测：翻转机位后 `pitch_nose_up` 会把机头画到屏幕下方）"
				% ["−y（箭体对侧）" if flip else "+y",
					"**先写 `pitch_nose_down`**（取反）" if flip else "先写 `pitch_nose_up`"])
		t.ok((i_rt < i_lf) == flip,
			"★★ 同理，偏航那一根%s"
				% ["**先写 `yaw_right`**（取反）" if flip else "先写 `yaw_left`"])
		# ⚠️ 节流那一根**与机位无关**：它进的是箭体自身（`trim` / `base_throttle`），
		# 不经过相机 ⇒ 不许跟着一起翻。翻了的症状是「油门反了」，同样不报错。
		var i_thr_up := seg.find("throttle_up")
		var i_thr_dn := seg.find("throttle_down")
		t.ok(i_thr_up >= 0 and i_thr_dn >= 0 and i_thr_up < i_thr_dn,
			"★ 而节流那一根**没跟着翻**（先写 `throttle_up`）—— 它不经过相机")


# ============================================================ ⑩ 座舱（全周天） / 火焰

## **座舱改用全周天的那一层**。
##
## 老板原话（两条，后一条推翻前一条）：
## > 「**在火箭最上端加一个驾驶舱第一人称（不是全周天！）需要建模驾驶舱视角的
## >  ui 和控制台仪表盘**」
## > 「**你驾驶舱做的好丑，直接用全周天驾驶舱的代码吧**」
## > 「**正常驾驶模式的UI也使用啊，比如燃料和雷达啊高度和时速这些显示器，
## >  不需要屏幕左上角那么多白色文字了**」
## > 「**在现状没有白字的情况下，把正常驾驶机体的高度指示器和速度指示器
## >  都拿过来**」
##
## ⇒ 第一版那套 3D 舱（`scripts/flight/rocket_cockpit.gd` + `shaders/rocket_gauge.gdshader`）
## 已**从工程里删除**（归档在 relay workspace 的 `_archive_rocket_cockpit_20260930/`），
## 舱内表现改成 `hud.gd` 那三个函数 + 一个纯函数读数。
##
## ★★ 2026-09-30 晚第四改：那两块**圆表**（`AIRSPEED` / `ALTITUDE` 表盘）撤掉，
## 改用**正常驾驶那一套**：左中时速块（含油门条 / 燃料槽）、右侧高度带 + 高度块、
## 下中雷达底盘。合同从"指针位置 + 表盘文字"换成"**原样交出物理量**"。
##
## ## 这一节钉四件事，每一件的失败模式都是**静默**的
##   ① **读数纯函数**（`LaunchScript.dash_readout`）—— 高度/时速/燃料/阶段；
##      它错了画面上只是"数字不太对"，看起来像"这关本来就这么快"；
##   ①b **"拿过来"真的拿过来了** —— 发射段与正常驾驶必须走**同一块**
##      绘制函数、**同一次**显示缩放；各画一套的话屏上就有**两套单位**，
##      而两张图各自看着都正常；
##   ② **HUD 那三个开关的语义**（`cockpit_only` / `cockpit_eye` / `cockpit_readout`）——
##      `cockpit_eye` 与 `Settings.first_person` 合并的话，换图那 1.5 s 导轨会消失；
##   ③ **读数一个字段都不许读 `player`** —— 发射段 `player` 是 `null`
##      （`spawn_round()` 还没跑），读了就是空指针一屏红叉。
static func _cockpit_hud(t: T, host: Node) -> void:
	t.suite("RocketLaunch / 舱内表现（全周天座舱那一层）")

	# ---- ① 读数纯函数（倒计时档）----
	var cd := LaunchScript.dash_readout(0.0, 0.0, 0.6, 1.0, "待发", 60.0, 7.5)
	t.eq(str(cd.get("leg", "")), "待发", "倒计时期间阶段名 = 待发")
	t.ok(str(cd.get("note", "")).contains("7.5"),
		"倒计时那一行印出剩余秒数（`%s`）" % str(cd.get("note", "")))
	t.eq(str(cd.get("name", "")), "马夫蒂火箭", "雷达圆上方报的是箭名（与机体第一人称的机名同一处）")
	t.near(float(cd.get("spd_kmh", -1.0)), 0.0, 1e-6, "倒计时：时速读数归零")
	t.near(float(cd.get("alt_m", -1.0)), 0.0, 1e-6, "倒计时：高度读数归零")
	t.near(float(cd.get("thr01", -1.0)), 0.6, 1e-6,
		"★ 但**油门照报**（倒计时里箭已经带着 60% 节流等着）")
	t.near(float(cd.get("fuel01", -1.0)), 1.0, 1e-6, "倒计时：燃料 100%")

	# ---- ① 读数纯函数（飞行档）----
	#
	# ★★ 这一档钉的不是"字对不对"，而是"**交出来的还是不是原量**"：
	# 老板 2026-09-30 晚要的是"把正常驾驶机体的高度指示器与速度指示器拿过来"，
	# 而那两个显示点各自有一套**自己的显示缩放**（`ALT_DISPLAY_SCALE` /
	# `SPEED_DISPLAY_SCALE`，见 `_draw_altitude_block()` / `_draw_speed_block()`）。
	# 纯函数这一侧只要**多缩一次**，屏上数字就会整体差一个系数 —— 而它
	# 看起来"只是一个不太对的数"，没有任何断言会红。
	var mid := LaunchScript.dash_readout(LaunchScript.ORBIT_ALT * 0.5, 12000.0, 1.0, 0.4,
		"穿云", 30.0, 0.0, -12.5, 480.0, 275.0)
	t.near(float(mid.get("alt_m", -1.0)), LaunchScript.ORBIT_ALT * 0.5, 1e-3,
		"★★ 高度**原样**交出真实米（不缩放、不换 km）—— 缩放是 HUD 那一侧的事")
	t.near(float(mid.get("spd_kmh", -1.0)), 12000.0 * 3.6, 1e-3,
		"★★ 时速只做 m/s → km/h，**不乘** `SPEED_DISPLAY_SCALE`（两处各缩一次 = 两套单位）")
	t.near(float(mid.get("pitch", -99.0)), -12.5, 1e-6, "俯仰原样透传（度）")
	t.near(float(mid.get("vs", -99.0)), 480.0, 1e-6, "垂直速度原样透传（真实 m/s，向上为正）")
	t.near(float(mid.get("hdg", -1.0)), 275.0, 1e-6, "航向原样透传（度）")
	var wrap := LaunchScript.dash_readout(0.0, 0.0, 0.0, 1.0, "真空", 0.0, 0.0, 0.0, 0.0, -85.0)
	t.near(float(wrap.get("hdg", -1.0)), 275.0, 1e-6,
		"★ 航向做 0~360 归一（`−85°` 与 `+275°` 是同一条航向，屏上是同一行字）")

	var full := LaunchScript.dash_readout(LaunchScript.ORBIT_ALT, LaunchScript.END_SPEED_MS,
		1.0, 0.0, "真空", 0.0, 0.0)
	t.near(float(full.get("spd_kmh", -1.0)), LaunchScript.END_SPEED_MS * 3.6, 1e-3,
		"抵达那一刻的时速读数 = 末速 × 3.6 = %d km/h" % int(LaunchScript.END_SPEED_MS * 3.6))
	t.eq(str(full.get("leg", "")), "真空", "飞行档的阶段名走传入值（`RocketBody.leg_name()`）")

	# ---- ①b "拿过来"真的拿过来了：**同一块**绘制函数 + **同一次**显示缩放 ----
	#
	# ⚠️ 这一段只能用源码扫描：两张图（发射段 / 正常驾驶）各自看着都正常，
	# 而"屏上那个速度数字"差着一个系数 —— 那是任何截图都看不出来的。
	var hud_all := FileAccess.get_file_as_string(HUD_SRC)
	t.ok(hud_all.contains("kmh = _rd(\"spd_kmh\", 0.0)"),
		"★★ 发射段时速块的数来自 `cockpit_readout`")
	t.ok(hud_all.contains("kmh = player.airspeed_kmh()"),
		"   正常驾驶那一侧的数来自机体空速")
	t.ok(hud_all.contains("int(kmh * SPEED_DISPLAY_SCALE)"),
		"★★ 但**只有一处**施加显示缩放 —— 两处各缩一次就是两套单位")
	t.ok(hud_all.contains("func _draw_speed_block()"),
		"★ 时速只有**一个**绘制函数（不是给火箭另画一套）")
	t.ok(not hud_all.contains("func _draw_dash_rocket_speed"),
		"★ 那块 `AIRSPEED` 圆表已删")
	t.ok(not hud_all.contains("func _draw_dash_rocket_alt"),
		"★ 那块 `ALTITUDE` 圆表已删")
	t.ok(not hud_all.contains("_rd01"),
		"  ……连驱动指针的归一化读数助手 `_rd01` 也一起删了")
	t.ok(hud_all.contains("var alt := _rd(\"alt_m\", 0.0) if rocket else player.global_position.y"),
		"★★ 高度块：同一行里两个来源，**同一个变量**")
	t.ok(hud_all.contains("func _from_rocket() -> bool"),
		"★ 三个仪表面共用**一个**「数从哪来」的判据（`_from_rocket()`）")
	t.ok(hud_all.count("_from_rocket()") >= 4,
		"  而且三个函数各查了一次（%d 次）" % hud_all.count("_from_rocket()"))

	# ---- ② HUD 那三个开关：语义各不相同的证据（源码扫描）----
	var hud_src := FileAccess.get_file_as_string(HUD_SRC)
	t.ok(hud_src.contains("var cockpit_readout: Dictionary"),
		"★ HUD 有一份**发射段读数**（本文件只认归一化读数，不认识 `RocketBody`）")
	t.ok(hud_src.contains("var cockpit_only := false"),
		"★ `cockpit_only`：发射段只画全周天那一层")
	t.ok(hud_src.contains("var cockpit_eye := false"),
		"★★ `cockpit_eye` 与 `Settings.first_person` **是两个变量**"
			+ "（换图那 1.5 s 眼位被锁进座舱而设置一位没动 ⇒ 合并的话导轨会在那一秒半消失）")
	var dash_body := hud_src.substr(hud_src.find("func _draw_cockpit_dash"),
		hud_src.find("func _draw_dash_module") - hud_src.find("func _draw_cockpit_dash"))
	t.ok(dash_body.contains("not Settings.first_person and not cockpit_only"),
		"★ 仪表台的门是「设置 **或** 发射段」—— 不是把设置那一位改掉")
	t.ok(dash_body.find("not Settings.first_person") < dash_body.find("_draw_dash_module"),
		"  ……而且查在画之前（提前 return）")
	# ⚠️ 这一条是"发射段里 HUD 会不会去读 player"的唯一守卫：
	# 发射段 `player` 是 `null`（`spawn_round()` 要到 `_launch_match()` 才跑）。
	var rocket_body := dash_body.substr(dash_body.find("var rocket :="),
		dash_body.find("_draw_dash_rocket_center"))
	t.ok(rocket_body.contains("if not rocket and (player == null"),
		"★★ 先判「是不是火箭段」、**再**判 `player` —— 顺序反了会在发射段直接 return（一屏没有仪表台）")
	var draw_body := hud_src.substr(hud_src.find("func _draw()"),
		hud_src.find("func _draw_reticle") - hud_src.find("func _draw()"))
	t.ok(draw_body.contains("if cockpit_only:"),
		"★ `_draw()` 里有那个早退（不然发射段会去画准星 / 血条 / 敌机列表 —— 全部读 `player`）")
	t.ok(draw_body.find("if cockpit_only:") < draw_body.find("if player != null"),
		"  ……而且**排在玩家分支之前**")
	# ★★ 老板 2026-09-30 晚：「把正常驾驶机体的高度指示器和速度指示器都拿过来」
	# ⇒ 那一支里必须**真的**调用那三块（只是"门开着"不等于画了）。
	var co_at := draw_body.find("if cockpit_only:")
	var co := draw_body.substr(co_at, draw_body.find("if player != null") - co_at)
	t.ok(co.contains("_draw_speed_block()"), "★★ 发射段画的是**正常驾驶那块**时速块")
	t.ok(co.contains("_draw_altitude_tape()"), "★★ ……高度带")
	t.ok(co.contains("_draw_altitude_block()"), "★★ ……高度块")
	t.ok(co.find("_draw_speed_block()") < co.find("_draw_cockpit_frame()"),
		"  ……而取景框压在它们**之上**（顺序不许反）")
	var sync_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	t.ok(sync_src.contains("hud.cockpit_readout = LaunchScript.dash_readout("),
		"★★ 读数的**唯一来源**是纯函数 `LaunchScript.dash_readout()`（main 只转手）")
	t.ok(sync_src.contains("hud.cockpit_eye = chase.launch_view()"),
		"★★ 而且每帧按**眼位档**写 `cockpit_eye`（不是按设置）")
	t.ok(sync_src.contains("hud.visible = true") and sync_src.contains("hud.cockpit_only = true"),
		"★ 发射段现在**打开** HUD 并切到 `cockpit_only`（第一版是 `hud.visible = false` + 一个 Label）")
	t.ok(not sync_src.contains("launch_label"),
		"★★ 那个摆在左上角、7 行白字的 `Label` **整个删掉了**"
			+ "（老板：「不需要屏幕左上角那么多白色文字了」）")
	t.ok(not sync_src.contains("RocketCockpit"),
		"★★ 3D 舱的接线也整个拔掉了（老板：「你驾驶舱做的好丑」）")
	t.ok(not FileAccess.file_exists("res://scripts/flight/rocket_cockpit.gd"),
		"★★ 而且那个类**已经不在工程里**（不是留着当死代码）")
	t.ok(not FileAccess.file_exists("res://shaders/rocket_gauge.gdshader"),
		"  ……它那块 shader 表盘也一样")

	# ---- ③ 三种视角下"画什么"的分派（纯逻辑，不需要真相机）----
	# 用一个真的 HUD 实例量那三个开关的**默认值**：默认必须全是"关"，
	# 否则战斗 HUD 会被发射段的状态污染（而这不是任何一张截图能看出来的）。
	var h := FlightHUD.new()
	host.add_child(h)
	t.ok(not h.cockpit_only, "HUD 建出来时 `cockpit_only` 是 false（战斗 HUD 不受发射段污染）")
	t.ok(not h.cockpit_eye, "……`cockpit_eye` 也是 false")
	t.ok(h.cockpit_readout.is_empty(), "……`cockpit_readout` 是空字典（空 = 走 player 那条路）")
	t.ok(not Settings.first_person, "对照：`Settings.first_person` 默认也是 false")
	t.ok(h.cockpit_basis.is_equal_approx(Basis()),
		"★ `cockpit_basis` 默认是**单位阵**（= 不是发射段）")
	t.ok(h.launch_warn.is_empty(),
		"★ `launch_warn` 默认是**空字典**（= 这一帧没有告警，而不是「三个 0」）")
	h.free()

	# ---- ★★ ④ 发射段告警（`FlightHUD.launch_warn_state`）----
	#
	# 老板 2026-09-30 晚：「**另外开机体的UI系统也搬过来（不搬雷达系统）**」，
	# 选定的范围是「**接火箭真有的读数**」⇒ 告警块搬过来，但**判据只判火箭真有的量**。
	var nw := FlightHUD.no_warn_state()
	var lw := FlightHUD.launch_warn_state(50000.0, 900.0, 3.0)
	t.eq(lw.size(), nw.size(), "★ 键数与 `no_warn_state()` 相同（`warn_lines()` 才能吃它）")
	for k: String in FlightHUD.WARN_PRIORITY:
		t.ok(lw.has(k), "  含键 `%s`" % k)
	# ⚠️ 最要紧的一条：`ifield_down` **恒假**。
	# `warn_state()` 的判据是 `not has_ifield` —— 照抄的话，火箭"没有护盾"会被读成
	# "护盾一直被打穿" ⇒ **恒亮**。这条断言就是"没有复用它"的证据。
	t.ok(not bool(lw["ifield_down"]),
		"★★ `ifield_down` **恒假**（照抄 `warn_state()` 的话它会恒亮：火箭没有 I 力场）")
	t.ok(not bool(lw["missile"]) and not bool(lw["stall"]),
		"★ `missile` / `stall` 也恒假（发射段没有来袭导弹；火箭不是气动机体）")
	t.ok(FlightHUD.highest_warning(lw) == "",
		"★ 正常爬升（50 km / 900 m/s 上升 / 3 G）**一条告警都不成立**")
	# 拉起：火箭这一条的**门限是水面（0 m）**，不是机体的 420 m。
	t.ok(not bool(FlightHUD.launch_warn_state(300.0, 0.0, 1.0)["pull_up"]),
		"★★ 箭底 300 m、垂直速度 0 ⇒ **不报**拉起"
			+ "（机体的 `PULL_UP_ALTITUDE` 420 m 在这儿会误报 —— 火箭是从**水下**起飞的）")
	t.ok(bool(FlightHUD.launch_warn_state(-100.0, -20.0, 1.0)["pull_up"]),
		"★ 箭底 −100 m 且在下沉 ⇒ 报（=「出水失败」这一件真事）")
	# 过载：机体的 12 G 在发射段会常亮 ⇒ 阈值另定。
	t.ok(not bool(FlightHUD.launch_warn_state(50000.0, 900.0, 11.0)["over_g"]),
		"★ 11 G **不报**（机体的 12 G 阈值在发射段会从 u=0.21 起一路常亮）")
	t.ok(bool(FlightHUD.launch_warn_state(50000.0, 900.0, 60.0)["over_g"]),
		"★ 60 G 报（末段真的到 190 G）")
	t.ok(FlightHUD.LAUNCH_OVER_G > FlightHUD.OVER_G_THRESHOLD,
		"★★ 发射段那个阈值**必须大于**机体的 %.0f（相等 = 「另用一档」退化成「复用机体那一档」）"
			% FlightHUD.OVER_G_THRESHOLD)

	# ---- ⑤ 过载曲线（`LaunchScript.accel_g_estimate`）----
	#
	# 与 `ascent_accel()` / `ascent_velocity()` **同一个自变量、同一条曲线** ⇒
	# "HUD 报的 G"与"火箭真正吃的指令加速度"永远是同一个真源。
	var g0 := LaunchScript.accel_g_estimate(0.0)
	var g05 := LaunchScript.accel_g_estimate(0.05)
	var g50 := LaunchScript.accel_g_estimate(0.5)
	var g100 := LaunchScript.accel_g_estimate(1.0)
	t.near(g0, 0.0, 1e-6, "u=0 ⇒ 0 G（曲线起点导数为 0 —— `ALT_SHAPE > 2` 的必然结果）")
	t.near(g05, 1.11, 0.05, "u=0.05 ⇒ ≈1.11 G（低空段只有一倍重力）")
	t.ok(g05 < g50 and g50 < g100,
		"★★ 单调增（%.2f → %.2f → %.2f）" % [g05, g50, g100])
	t.near(g100, 190.2, 3.0,
		"★★ u=1 ⇒ ≈190 G（末速 35 km/s 除以 60 s 的必然结果，不是笔误）")
	t.ok(g100 > FlightHUD.LAUNCH_OVER_G,
		"★ 末段**一定**超过发射段那个阈值（否则那条告警一辈子不亮，等于没接）")
	t.near(LaunchScript.accel_g_estimate(5.0), g100, 1e-9,
		"  `u` 越界时夹到 1（`clampf`）—— 抵达之后残留一帧也不会算出离谱的数")

	# ---- ⑥ 三块 UI 真的被接进 `cockpit_only` 那一支（源码事实）----
	#
	# ⚠️ 查源码前**先剥掉注释行**：那三个函数名在这一支的注释里也出现过
	#（就是本轮的说明文字），不剥的话"真调用被删了、注释还在"会**假绿**。
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	# ⚠️ 锚点必须从 `func _draw()` **之后**开始找：`find("if cockpit_only:")` 会命中
	# `_process()` 里那个 `elif cockpit_only:` 的子串（"elif cockpit_only" 含 "if cockpit_only"）——
	# 第一版就是这么假红的。
	var i_draw := hsrc.find("func _draw() -> void:")
	var i_co := hsrc.find("if cockpit_only:", i_draw)
	t.ok(i_draw >= 0 and i_co > i_draw, "`hud.gd` 的 `_draw()` 里有 `cockpit_only` 那一支")
	if i_co > i_draw:
		var br := hsrc.substr(i_co, 3000)
		var i_cf := br.find("_draw_cockpit_frame()")
		var seg2 := br.substr(0, i_cf + 40) if i_cf > 0 else br
		var code := ""
		for ln in seg2.split("\n"):
			if ln.strip_edges().begins_with("#"):
				continue
			code += ln + "\n"
		for fn: String in ["_draw_attitude()", "_draw_model_tag()", "_draw_warnings()"]:
			t.ok(code.contains(fn),
				"★ 发射段那一支**真的调了** `%s`（老板：「另外开机体的UI系统也搬过来」）" % fn)
		t.ok(not code.contains("_draw_radar()") and not code.contains("_draw_contact_list()"),
			"★ 而**没有**调雷达 / 敌机列表（老板这一轮：「（不搬雷达系统）」）")
		t.ok(code.contains("_draw_cockpit_frame()"),
			"  取景框仍压在最后（它是贴在屏幕边的那一层）")
		# ⚠️⚠️ 三块的判据必须是 **`cockpit_only`**（"这一层是不是发射段的座舱"），
		# **不是** `_from_rocket()`（"这一帧有没有读数"）—— 两者不是一回事：
		# `cockpit_only` 刚打开、`_sync_cockpit_hud()` 还没喂数的那一帧（以及
		# `rocket` 被 free 之后），会出现"开关真、读数为空"的中间态，
		# 而按 `_from_rocket()` 走就会掉进 `player`（发射段是 null）⇒ 炸 Nil。
		t.ok(code.contains("if cockpit_only:"),
			"★★ `_draw()` 里那一支的判据是 `cockpit_only`")
		t.ok(not code.contains("_from_rocket()"),
			"★★ 而那一支**不用** `_from_rocket()`（它在「开关真、读数为空」的那一帧是假的）")
	t.ok(hsrc.contains("var b := cockpit_basis if cockpit_only"),
		"★★ 姿态仪换源也判 `cockpit_only`（`cockpit_basis if _from_rocket()` 会炸 Nil）")
	var i_mt := hsrc.find("_draw_model_tag_rocket()")
	t.ok(i_mt > 0 and hsrc.substr(maxi(i_mt - 220, 0), 220).contains("if cockpit_only:"),
		"★★ 机名标签的早退判据同理（它是唯一一处会读 `player.profile` 的地方）")
	t.ok(hsrc.contains("func _tick_launch_warnings("),
		"★ 发射段自己的告警状态机在（`_tick_launch_warnings()`）")
	t.ok(hsrc.contains("_warn_state = launch_warn_state("),
		"★★ 而它的状态**只能**由 `launch_warn_state()` 造（不是 `warn_state()`）")
	t.ok(hsrc.contains("_warn_held = highest_warning(_warn_state)"),
		"  边沿触发的那一位照旧维护（将来给发射段接语音时不会连播两遍）")
	t.ok(sync_src.contains("hud.launch_warn ="),
		"★ `main` 把火箭的高度 / 垂直速度 / 过载塞进 `launch_warn`")
	t.ok(sync_src.contains("hud.cockpit_basis = rocket."),
		"★ 姿态源也是 main 推的（HUD 不认识 `RocketBody`）")
	t.ok(sync_src.contains("hud.launch_warn = {}"),
		"★ 而收场时（`_begin_launch` / `_finish_launch`）会清空它")



## `RocketFlame` —— 老板：「**火箭升空的时候都没有大型火焰拖尾**」。
##
## 参考图里最扎眼的就是它：细长箭体下面挂着一条**比箭体长好几倍**的橙白色火柱。
## 这一节钉三件事：**几何朝向**（焰必须朝箭尾、喷口端在箭底）、
## **三层各拿一份材质**（共用一份 ⇒ 内芯与外圈会同时被最后一次写参数改掉）、
## 以及**熄火必须真的熄**（`_finish_launch()` 之后没人再调 `update()`）。
static func _flame(t: T, host: Node) -> void:
	t.suite("RocketLaunch / 火焰与拖尾（RocketFlame）")
	var fl := RocketFlame.new()
	host.add_child(fl)

	# ---- 三层 × 三喷口 + 三盏灯 ----
	#
	# ★★ 2026-09-30 晚：老板「**火箭下面只有一条长拖尾，但是火箭左右两边还有
	# 辅助推进器，这两条辅助推进器都需要做尾焰和拖尾**」⇒ 焰从一根变三根。
	# ⚠️ 下面这些数**不是** 4/3 了 —— 但"三层各拿一份材质""长度随高度涨"
	# "熄火即消失"这些规矩**一条都没变**，只是每一层现在有**三份**。
	t.eq(RocketFlame.LAYERS.size(), 3, "层表是三层（内芯 / 主焰 / 外圈）")
	t.eq(RocketFlame.NOZZLES.size(), 3, "★ 喷口表是三个（芯级 + 左右助推器）")
	var nz_n: int = RocketFlame.NOZZLES.size()
	var lay_n: int = RocketFlame.LAYERS.size()
	t.eq(fl.get_child_count(), nz_n * (lay_n + 1),
		"★ %d 个喷口 × （三层焰 + 一盏灯）= %d 个子节点" % [nz_n, fl.get_child_count()])
	var mats: Array = fl.get("_mats")
	t.eq(mats.size(), nz_n * lay_n, "每层、**每个喷口**各拿一份材质")
	# ★★ 侧喷口的三个几何关系（这三个数是从资产上**量出来的**，见 `NOZZLES` 的头注）：
	t.ok(float(RocketFlame.NOZZLES[1]["scale"]) > 0.0
		and float(RocketFlame.NOZZLES[1]["scale"]) < 1.0,
		"★ 侧喷口的几何倍率在 (0,1) 开区间（助推器喷管口径只有芯级的一半左右）")
	t.near(float(RocketFlame.NOZZLES[1]["scale"]), float(RocketFlame.NOZZLES[2]["scale"]), 1e-9,
		"  左右两个助推器**同倍率**（不一样的话画面上左右不对称）")
	t.near(float(RocketFlame.NOZZLES[1]["pos"].x), -float(RocketFlame.NOZZLES[2]["pos"].x), 0.10,
		"★ 左右两个喷口**关于中轴对称**（%.2f / %.2f）"
			% [RocketFlame.NOZZLES[1]["pos"].x, RocketFlame.NOZZLES[2]["pos"].x])
	t.ok(is_equal_approx(float(RocketFlame.NOZZLES[0]["pos"].x), 0.0)
			and is_equal_approx(float(RocketFlame.NOZZLES[0]["pos"].z), 0.0),
		"★ 芯级喷口仍在 `(0, 0)` —— 老板只要求「给助推器加焰」，没有要求动芯级")
	t.ok(not is_equal_approx(float(RocketFlame.NOZZLES[1]["seed"]),
			float(RocketFlame.NOZZLES[2]["seed"])),
		"★ 三条焰的湍流相位互不相同（相同的话它们逐帧同相抖动，读起来是同一根焰被复制了三份）")
	if mats.size() >= lay_n * 2:
		var s_core := float(mats[lay_n - 1].get_shader_parameter("seed"))
		var s_side := float(mats[lay_n * 1 + lay_n - 1].get_shader_parameter("seed"))
		t.ok(not is_equal_approx(s_core, s_side),
			"★ 芯级与左助推器**同层**的相位在材质里真的不同（表里不同、没写进材质的话照样同相）")
	if mats.size() >= 3:
		t.ok(mats[0] != mats[1] and mats[1] != mats[2],
			"★★ 三份材质**互不相同**（`ShaderMaterial` 是资源，共用一份的话三层会一起被改）")
		t.gt(float(mats[2].get_shader_parameter("gain")),
			float(mats[0].get_shader_parameter("gain")),
			"★ 内芯的 gain 压过外圈（%.2f > %.2f）"
				% [mats[2].get_shader_parameter("gain"), mats[0].get_shader_parameter("gain")])

	# ---- 几何：焰沿 **+Z** 伸出，喷口那一头落在**自己那个喷口的 z 平面** ----
	#
	# ⚠️ 三根焰各查一遍（而不是只查芯级）：`_layout()` 是"喷口 × 层"双层循环，
	# 内层下标写歪的话，只有侧喷口会错位 —— 而**只看芯级那一根是全绿的**。
	# ⚠️ 喷口端写成"≈ 自己那一行的 `pos.z`"而不是写死 0：
	# 三个 `pos.z` 现在全是 0（芯级量出来是 −2.97 m，取它会把焰起点埋进箭体 3 m，
	# 见 `NOZZLES` 的注释），将来谁改那个数，这条也照样能判。
	var meshes: Array = fl.get("_meshes")
	t.eq(meshes.size(), nz_n * lay_n, "网格表与材质表同长")
	for i in meshes.size():
		var mi := meshes[i] as MeshInstance3D
		if mi == null:
			continue
		var n: int = i / lay_n
		var j: int = i % lay_n
		var nz: Dictionary = RocketFlame.NOZZLES[n]
		var d: Dictionary = RocketFlame.LAYERS[j]
		var want := String(d["name"]) if n == 0 \
			else "%s_%s" % [String(nz["name"]), String(d["name"])]
		t.ok(String(mi.name) == want, "喷口 %d 的第 %d 层叫 %s" % [n, j, want])
		var cm := mi.mesh as CylinderMesh
		t.ok(cm != null, "  层 %s 是 CylinderMesh" % mi.name)
		if cm != null:
			t.ok(not cm.cap_top and not cm.cap_bottom,
				"  两端**无盖**（端盖会在尾端画出一个随相机转向的亮圆盘）")
		var ax := mi.transform.basis.y.normalized()
		t.ok(ax.dot(Vector3(0.0, 0.0, 1.0)) > 0.999,
			"★ 层 %s 的长轴指向 **+Z**（背向机头 = 喷流方向）" % mi.name)
		var half := mi.transform.basis.y.length() * 0.5
		t.near(mi.transform.origin.z - half, float(nz["pos"].z), 1e-4,
			"★ 层 %s 的**喷口端落在自己那个喷口的 z 平面**" % mi.name)
		t.near(mi.transform.origin.x, float(nz["pos"].x), 1e-4,
			"★ 层 %s 的**喷嘴横坐标 = 喷口表的 X**（%.2f）" % [mi.name, float(nz["pos"].x)])

	# ---- 熄火态 ----
	t.near(fl.strength, 0.0, 1e-9, "刚建好 strength = 0（没点火 ⇒ 一根焰都不画）")
	if mats.size() > 0:
		t.near(float(mats[0].get_shader_parameter("strength")), 0.0, 1e-9,
			"  材质里的 strength 也是 0（否则就是「改了成员、没改材质」）")

	# ---- 有推力 / 高度：两个自变量 ----
	var rk := RocketBody.new()
	host.add_child(rk)
	rk.place_at_launch(LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))
	rk.base_throttle = 1.0
	fl.update(rk)
	t.near(fl.strength, 1.0, 1e-6, "满推力 ⇒ strength = 1")
	t.near(fl.widen, 0.0, 1e-6, "★ 海面高度（箭底 %.0f m）⇒ widen 夹到 0" % LaunchScript.rest_alt())
	t.near(fl.length, RocketFlame.LEN_MIN, 1e-3,
		"  海面附近的焰长 = LEN_MIN（%.0f m）" % RocketFlame.LEN_MIN)
	if mats.size() > 1:
		t.gt(float(mats[1].get_shader_parameter("strength")), 0.99,
			"★ 材质的 strength 也跟着写进去了（只改成员变量的话画面上一根焰都没有）")
	rk.global_position.y = RocketFlame.ALT_FULL + 5000.0
	fl.update(rk)
	t.near(fl.widen, 1.0, 1e-6, "稀薄大气 ⇒ widen 打满")
	t.near(fl.length, RocketFlame.LEN_MAX, 1e-3, "★ 焰长到 LEN_MAX（%.0f m）" % RocketFlame.LEN_MAX)
	t.gt(RocketFlame.LEN_MAX, RocketBody.ROCKET_HEIGHT_M * 2.0,
		"★★ 焰长 > 箭高的两倍（%.0f m vs %.0f m）——「**大型**火焰拖尾」那个词就是这一条"
			% [RocketFlame.LEN_MAX, RocketBody.ROCKET_HEIGHT_M])

	# ---- 喷口灯 × 3（参考图里云层的顶面就是被它烤亮的）----
	var lights: Array = fl.get("_lights")
	t.eq(lights.size(), nz_n, "每个喷口各一盏灯")
	var lt := fl.get_node_or_null("NozzleLight") as OmniLight3D
	t.ok(lt != null, "主喷口那盏灯**仍叫 `NozzleLight`**（旧名字：探针与既有的找法都按它）")
	if lt != null:
		t.gt(lt.light_energy, 0.0,
			"★ 有推力时灯是亮的（energy %.1f）" % lt.light_energy)
		t.gt(lt.omni_range, 1000.0,
			"  而且范围够照到下面的云层（%.0f m）" % lt.omni_range)
		t.ok(lt.position.is_equal_approx(Vector3.ZERO),
			"  主灯在箭底轴线上（%.2f, %.2f, %.2f）" % [lt.position.x, lt.position.y, lt.position.z])
	if lights.size() >= 3:
		var l1 := lights[1] as OmniLight3D
		var l2 := lights[2] as OmniLight3D
		t.gt(l1.light_energy, 0.0,
			"★ 助推器那两盏灯也亮（不亮的话云里只有芯级那一片是暖的，而画面上三根焰一样亮）")
		t.lt(l1.light_energy, lt.light_energy,
			"  但比主灯暗（%.1f < %.1f —— 三盏同能量叠在一起会把箭底过曝成白色）"
				% [l1.light_energy, lt.light_energy])
		t.near(l1.position.x, float(RocketFlame.NOZZLES[1]["pos"].x), 1e-4,
			"  左灯摆在左喷口上（x %.2f）" % l1.position.x)
		t.near(l2.position.x, float(RocketFlame.NOZZLES[2]["pos"].x), 1e-4,
			"  右灯摆在右喷口上（x %.2f）" % l2.position.x)
		t.gt(lt.omni_range, l1.omni_range,
			"  主灯照得远、侧灯照得近（%.0f > %.0f —— 芯级那盏负责烤亮整片云底）"
				% [lt.omni_range, l1.omni_range])

	# ---- 熄火 ----
	fl.extinguish()
	t.near(fl.strength, 0.0, 1e-9, "extinguish() ⇒ strength 归零")
	t.near(fl.length, 0.0, 1e-9, "  （长度读数也归零）")
	if lt != null:
		t.near(lt.light_energy, 0.0, 1e-9, "★ 灯也灭（不灭的话箭尾永远挂着一盏灯）")
	# ⚠️ 侧灯**逐盏**查：`extinguish()` 里只 `for k in _lights` 跑一半的话，
	# 左右两条会永远留在画面上 —— 而主灯那条断言照旧全绿。
	for k in lights.size():
		t.near((lights[k] as OmniLight3D).light_energy, 0.0, 1e-9,
			"★ 第 %d 盏灯也灭（三根焰的灯必须一起收）" % k)
	for m in mats:
		t.near(float(m.get_shader_parameter("strength")), 0.0, 1e-9,
			"★ 每一层材质的 strength 都归零（只归零成员变量的话焰会冻在画面上）")

	# ---- 源码事实：加色 / 不写深度 / 熄火即消失 / 不投影 ----
	var fsh := FileAccess.get_file_as_string("res://shaders/rocket_flame.gdshader")
	t.ok(fsh.contains("blend_add"),
		"★ 焰是**加色**混合（不然会读成一根实心的橙色塑料棒：处处一样亮、没有体积）")
	t.ok(fsh.contains("depth_draw_never"), "★ 不写深度（不参与别的透明体的排序）")
	t.ok(fsh.contains("if (strength <= 0.002)") and fsh.contains("discard"),
		"★ 熄火那一帧**整根消失**（不能留一条半透明的橙带贴在箭尾，那看起来像「忘了关」）")
	var fsrc := FileAccess.get_file_as_string("res://scripts/flight/rocket_flame.gd")
	t.ok(fsrc.contains("SHADOW_CASTING_SETTING_OFF"),
		"★ 三层都不投影（投影会在地面/云上留下一道**黑色的柱影**）")

	fl.free()
	rk.free()


# ============================================================ ⑧ 数据与接线

static func _data_and_wiring(t: T, host: Node) -> void:
	t.suite("RocketLaunch / 数据与接线")
	# ---- M03 挂了发射段 ----
	var m03: MS.Mission = MS.by_id("M03")
	t.ok(m03 != null, "查得到 M03")
	if m03 != null:
		t.ok(m03.launch_prologue, "★ M03 的 `launch_prologue` = true（数据驱动，不是 main 里写 id）")
		t.eq(m03.arena, "LEO", "M03 的战场是 LEO（发射段的**终点**）")
		t.eq(m03.map_id(), MapDef.Id.LEO, "地图片 id 解析到 LEO")
		# ⚠️ "从 200 km 外飞过来"这件事只有在**抵达型**目标下才有意义。
		var has_reach := false
		for o in m03.objectives:
			var ob: MS.Objective = o
			if ob.kind == MS.Objective.Kind.REACH:
				has_reach = true
		t.ok(has_reach, "M03 有 REACH 型目标（「抵达运输仓」—— 这正是 200 km 进场距离的用处）")
	# 别的关**不该**带上发射段（否则每一关都先从太平洋起飞）。
	var others := 0
	for mid: String in ["M01", "M02", "M04", "M05", "M06", "M07"]:
		var mm: MS.Mission = MS.by_id(mid)
		if mm != null and mm.launch_prologue:
			others += 1
	t.eq(others, 0, "只有 M03 有发射段（其余 6 关都没有）")

	# ---- 资产真的在工程里 ----
	t.ok(ResourceLoader.exists("res://assets/models/mafty_rocket/mafty_rocket.glb"),
		"火箭资产 `mafty_rocket.glb` 在工程里（**清过名字**的那一份）")

	# ---- `main.gd` 的接线（源码事实）----
	#
	# ⚠️ 这里查源码子串是**下策**，但它抓的是"数据/流程分家"里最容易漏的那一环：
	# `_launch_match()` 的 `skip_map` 参数不传 `true` 的话，
	# 抵达那一刻会把刚建好的世界**拆了重建** —— 而画面上只是"揭开时卡了一下"。
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	# ⚠️ 2026-09-30 晚改：原来比的是**整串字面量**
	#（`enum Phase { MENU, CAMPAIGN, BRIEF, LAUNCH, FIGHT, RESULT }`）——
	# 而另一个会话在同一行尾上加了 `POD_STRIKE`（运输仓突袭），这一条就**假红**了。
	# 它的本意只是"`LAUNCH` 插在 `BRIEF` 与 `FIGHT` 之间"这个**顺序关系**，
	# 不是"枚举只能有六个值"。改成查顺序之后，将来再加阶段也不会冤枉它。
	var ph := ""
	var i0 := src.find("enum Phase {")
	if i0 >= 0:
		var i1 := src.find("}", i0)
		ph = src.substr(i0, i1 - i0) if i1 > i0 else src.substr(i0, 200)
	var p_brief := ph.find("BRIEF")
	var p_launch := ph.find("LAUNCH")
	var p_fight := ph.find("FIGHT")
	t.ok(p_launch >= 0, "`main.gd` 有 `Phase.LAUNCH`")
	t.ok(p_brief >= 0 and p_launch > p_brief and p_fight > p_launch,
		"  而且它插在 `BRIEF` 与 `FIGHT` 之间（下标 %d < %d < %d）" % [p_brief, p_launch, p_fight])
	t.ok(src.contains("_launch_match(true)"),
		"★ 发射段交还时调的是 `_launch_match(true)`（不重建刚建好的 LEO 图）")
	t.ok(src.contains("launch_root.add_child(rocket)"),
		"★ 火箭挂 `launch_root` 而不是 `units_root`（`_clear_match()` 会清空后者）")
	t.ok(src.contains("_swap_to_orbit()"),
		"★ 换图走 `_swap_to_orbit()`（幕布删掉之后，换图的入口就是它）")
	t.ok(src.contains("rocket.place_at_launch(LaunchScript.launch_pos()"),
		"出生点读 `LaunchScript`（与上升曲线 `ascent_pos(0)` 同源）")
	t.ok(not src.contains("pad_pos") and not src.contains("place_on_pad"),
		"★ `main.gd` 里再没有平台时代的名字（`pad_pos()` / `place_on_pad()`）—— 平台已整个砍掉")
	# ⚠️ 下面这几条是"接线会不会被后来的人顺手删掉"的唯一守卫。
	# 它们**都不是**可有可无的装饰：删掉每一条的症状都是"一切正常，只是少了点东西"。
	t.ok(src.contains("chase.set_launch_view(true)"),
		"★ 进发射段切到**发射段机位**（默认机位在箭底下方 53 m ⇒ 吃水 34 m 之后相机在水面下）")
	t.ok(src.contains("chase.set_launch_view(false)"),
		"★ `_clear_match()` 每局重开切回去（否则下一局从一个「离机体 175 m、抬头 4°」的机位开打）")
	t.ok(src.contains("world.launch_splash.begin()"),
		"★ 点火那一帧起出水特效（不是一建好就喷 —— 倒计时 8 s 里水该是静的）")
	t.ok(src.contains("world.launch_splash.update(rocket.global_position.y, delta)"),
		"★ 每帧拿**箭底高度**驱动出水特效（`rocket.global_position.y` 就是箭底，与 `place_at_launch()` 同一个量）")
	t.ok(src.contains("rocket.room_swapped = true"),
		"★ 换图完成后置 `rocket.room_swapped`（阶段播报靠它从「穿云」切到真空段）")
	t.ok(src.contains("world.launch_splash.end()"),
		"★ 收尾时熄掉出水特效（留着的话环会永远挂在海面上）")
	t.ok(src.contains("if chase.launch_view():"),
		"★★ `_apply_camera_settings()` 里**按发射段眼位档分流** —— 它**每帧**跑，无脑写 `roll_blend` / `first_person` 会把发射段刚压好的值顶回去")
	t.ok(src.contains("chase.set_launch_eye(ChaseCamera.LaunchEye.COCKPIT"),
		"★★ F1 在发射段切的是**火箭座舱眼位**（`set_launch_eye`），而不是直接写 `chase.first_person` —— 只写一半会让玩家「进了舱而镜头还在箭底下方 80 m」")
	t.ok(src.contains("or _swap_eye_lock"),
		"★★ 而且换图窗口会**压着座舱档不放**（同一个分支里的闩 —— 见 `_swap_eye_lock`）")
	# ---- ★ 舱内表现与火焰的接线 ----
	t.ok(src.contains("rocket.add_child(launch_flame)"),
		"★ 火焰是**箭体的子节点**（跟着箭一起转；挂在外面它不会跟着俯仰）")
	t.ok(src.contains("_sync_cockpit_hud()"),
		"★★ 舱内读数每帧推（与 `SeaSplash.update()` 同一条「显式调用」的规矩）")
	t.ok(src.contains("hud.cockpit_readout = LaunchScript.dash_readout("),
		"★★ 而读数的**唯一来源**是纯函数 `LaunchScript.dash_readout()`（main 只负责转手）")
	t.ok(src.contains("hud.cockpit_only = false"),
		"★★ 交还操控时**必须把 `cockpit_only` 关掉** —— 留着的话玩家会拿到一屏"
			+ "只有仪表台、没有准星/血条/目标框的界面（看起来像 HUD 坏了）")
	t.ok(src.find("hud.cockpit_only = false") < src.find("_launch_match(true)"),
		"  ……而且关在 `_launch_match()` **之前**（那一函数会撒机体并打开战斗 HUD）")
	t.ok(src.contains("launch_flame.update(rocket)"),
		"★ 火焰每帧推（摆在 `rocket.step()` **之后** —— 它读的 `base_throttle` 就是那一步算出来的）")
	t.ok(src.contains("launch_flame.extinguish()"),
		"★★ 收尾时**显式熄火** —— `_finish_launch()` 之后没人再调 `update()`，焰会冻在满推力上")
	t.ok(not src.contains("mafty_rocket.glb\")") or src.contains("load(ROCKET_MODEL)"),
		"资产走 `load()` 而不是 `preload()`（40 MB 的东西不该在开机时读）")
