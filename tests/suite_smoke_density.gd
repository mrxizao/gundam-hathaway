class_name SuiteSmokeDensity
extends RefCounted
## ★63-9 · D5「导弹拖尾白烟太挡视野了：透明度降低和密度降低 20%，**体积不变**」。
##
## 五段判据（对着设计文档 §3.5 的方案 A）：
##   ① 密度真的降了：`amount` 80→64 / 28→22，**且 `lifetime` 同步 0.16→0.128**；
##   ② 间距不变量：`v_max × lifetime ÷ amount < 1.8 × scale_max`（连成一体，
##      不许退回「一串孤立的点」—— 那正是轮 39 治好的病）；
##   ③ 透明度真的降了：烟带 `MissileRibbon.ALPHA` **低于 D5 之前的 0.55**
##      （D5 定的精确值 0.44 已被轮 63-12 取代 ⇒ 本节只留语义，
##        精确值**只在 §⑥ 钉一处**）；
##   ④ 体积不变：`HALF_W` / `scale_min` / `scale_max` / 发射盒长
##      四者**逐位不变**（`SPACING` 轮 63-12 起**移出**这张清单 —— 本轮就是改它，见 §⑥）；
##   ⑤ 性能红线（既有）：四条预算断言。
##
## ⚠️⚠️ **为什么 `amount` 必须和 `lifetime` 一起降**（本项最容易做错的一步）
##
## 摊开后的簇间距 = `弹速 × lifetime ÷ amount`：
##   · **只降 amount**（80→64，lifetime 仍 0.16）⇒ 4062.24 × 0.16 ÷ 64 = **10.156 m**
##     **> 粒子最大出生直径 1.8 × 8.5 × 0.65 = 9.945 m** ⇒ 烟团之间出现缝 ⇒
##     观感退回「一串孤立的点」，而且**当场撞红** `suite_missile_smoke.gd` 的
##     `t.lt(spacing, diam_max)`。
##   · **同比例降**（64 / 0.128）⇒ 4062.24 × 0.128 ÷ 64 = **8.124 m（逐位不变）**。
## ⇒ 「密度 −20%」只能**同比例**动这一对。§② 里那条「与旧值同口径复算完全相等」
##   就是这条的机械证明（负对照 `nc_amount_only` 专门拆它）。
##
## ⚠️ 第三条口径：**只降粒子层**的透明度会撞一条旧需求。
## 粒子色带起点 alpha `0.88 × 0.8 = 0.704 < 0.84` ⇒ 撞红
## `suite_missile_smoke.gd` 的「色带起点加浓 —— 弹幕里烟读得出来」。
## P10 拍板：**不动粒子层透明度**，只在**烟带层**降（0.55 → 0.44）⇒ 零冲突。
##
## ⚠️ 第四条口径：**柱长 650 → 520 m 不算违反「体积不变」**（P11）。
## 那 650 m 是**粒子层那一段**的长度，而**整条拖尾的长度由烟带承担**
##（12 km 交战实铺 100% 弹道）⇒ 玩家看到的拖尾长度与宽度都不变。
## ★ 轮 63-12（需求：「导弹尾迹透明度调为现在的 70%，连续性调到现在的 78%」）
## 推翻了上面这一版留下的两句：
##   · **`SPACING` 原来写着"不碰"** —— 本轮按用户口径（**连续性 = 采样间距**）
##     改成 `120 → 153.8`（×1/0.78）。判据落在 §⑥。
##   · 原先那句「现有判据对 `SPACING ∈ [120, 200]` 是盲的」**当时就不准确** ——
##     §④ 里一直有一条 `t.eq(MissileRibbon.SPACING, 120.0)`，改它当场变红。
##     ⇒ §⑥ 起改成"**钉本轮的值 + 钉住它参与的算术**"，而不是把某一轮的旧值钉死。
##
## ⚠️ 本文件 §①~§⑤ 是 **D5 那一轮的记录**，本轮**没有**推翻它们；
## 本轮新增的只有 §⑥。将来再改这两个数时，**应当变红的是 §⑥**。


static func run(t: T, _host: Node) -> void:
	t.suite("SmokeDensity / 密度真的降了（D5）")
	_density(t)
	t.suite("SmokeDensity / 间距不变量：仍然连成一体（D5）")
	_spacing(t)
	t.suite("SmokeDensity / 透明度：烟带低于 0.55（D5 的残留口径）")
	_alpha(t)
	t.suite("SmokeDensity / 体积不变：四个量逐位不动（D5）")
	_volume(t)
	t.suite("SmokeDensity / 性能红线（D5）")
	_budget(t)
	# ⚠️ **新增节必须挂 `run()` 最末**（`t.suite()` 会结算之前累积的断言）。
	t.suite("SmokeDensity / 轮 63-12：烟带连续性 ×0.78 + 透明度 ×0.70")
	_r6312(t)


# ================================================================ ① 密度
static func _density(t: T) -> void:
	t.eq(FX.TRAIL_HIGH_AMOUNT, 64, "HIGH 档 = 80 × 0.8 = 64")
	t.eq(FX.TRAIL_LOW_AMOUNT, 22, "LOW 档 = 28 × 0.8 = 22")
	t.eq(Missile.trail_amount(Missile.Trail.HIGH), 64, "产品读到的 HIGH 也是 64")
	t.eq(Missile.trail_amount(Missile.Trail.LOW), 22, "产品读到的 LOW 也是 22")

	# ⚠️ 走**产品那条路**：造一个真的粒子系统，读它的 `amount` / `lifetime`。
	var st := _stage()
	var tr: GPUParticles3D = st.get_child(0)
	var pm := tr.process_material as ParticleProcessMaterial
	t.eq(tr.amount, 64, "真粒子系统的 amount = 64")
	t.near(tr.lifetime, 0.128, 0.0005, "lifetime 同步降到 0.16 × 0.8 = 0.128")
	t.near(tr.lifetime / float(tr.amount), 0.16 / 80.0, 0.000000001,
		"★ lifetime ÷ amount **逐位不变**（0.002）—— 这就是「同比例降」的定义")
	st.free()


# ================================================================ ② 间距不变量
static func _spacing(t: T) -> void:
	var st := _stage()
	var tr: GPUParticles3D = st.get_child(0)
	var pm := tr.process_material as ParticleProcessMaterial
	var v_max := SuitProfile.missile_speed()
	var spacing := v_max * tr.lifetime / float(tr.amount)
	var diam_max := 1.8 * pm.scale_max

	t.gt(v_max, 4000.0, "峰值弹速 %.1f m/s（前提：它决定间距那条算式）" % v_max)
	t.lt(spacing, diam_max,
		"摊开后间距 %.3f m < 粒子最大直径 %.3f m ⇒ **连成一体**" % [spacing, diam_max])
	t.near(spacing, 8.1245, 0.01, "间距仍是 8.124 m")
	t.near(v_max * 0.16 / 80.0, spacing, 0.000001,
		"★ **与改动前同口径复算：完全相等** —— 这就是「同比例降」的机械证明")

	var col := v_max * tr.lifetime
	t.near(col, 519.97, 0.5, "粒子柱长 650 → 520 m（那一层 −20%，**不算破坏体积**）")
	t.lt(col, 900.0, "柱长仍在 < 900 的老红线内")
	t.gt(col, 200.0, "也仍 > 200（还能看出「一道烟」）")
	st.free()


# ================================================================ ③ 透明度
static func _alpha(t: T) -> void:
	# ⚠️ D5 定的精确值 0.44 已被轮 63-12 取代（→ 0.308）。**精确值只在 §⑥ 钉一处**
	#（同一根轴两处钉死 ⇒ 将来改哪边都要改两处，且会出现"两处不一致"）。本节只留语义。
	# ⚠️ 这正是一条「定值断言会在**正确**的改动上变红」的实例：本轮改 `ALPHA` 时
	# 这里当场报红，红的是**正确改动**（见 `godot-headless-test-verify` v6.1 ②）。
	t.lt(MissileRibbon.ALPHA, 0.55, "确实低于 D5 之前的 0.55")
	t.gt(MissileRibbon.ALPHA, 0.20, "……但仍没淡到看不见")
	# ⚠️ 粒子层**故意不动**（P10）：那条色带起点 alpha 必须还是 0.88。
	var st := _stage()
	var tr: GPUParticles3D = st.get_child(0)
	var pm := tr.process_material as ParticleProcessMaterial
	var r0 := (pm.color_ramp as GradientTexture1D).gradient.get_color(0)
	t.near(r0.a, 0.88, 0.01, "粒子层色带起点 **仍是 0.88**（P10：不动它，否则撞旧需求）")
	st.free()


# ================================================================ ④ 体积不变
static func _volume(t: T) -> void:
	var st := _stage()
	var tr: GPUParticles3D = st.get_child(0)
	var pm := tr.process_material as ParticleProcessMaterial
	# 「体积」写成五条可证伪的断言：宽度（烟带半宽 / 粒子出生直径）、长度（盒长）。
	t.eq(MissileRibbon.HALF_W, 6.0, "烟带半宽 6.0（**宽度**，不动）")
	t.near(pm.scale_min, 3.2 * 0.65, 0.000001, "粒子出生尺寸下限 = 3.2 × 0.65（不动）")
	t.near(pm.scale_max, 8.5 * 0.65, 0.000001, "粒子出生尺寸上限 = 8.5 × 0.65（不动）")
	t.near(pm.emission_box_extents.z * 2.0, 135.4, 0.001,
		"发射盒长 = EMIT_SPAN 135.4（**长度**，不动）")
	t.near(pm.emission_shape_offset.z, pm.emission_box_extents.z, 0.001,
		"盒偏移 = 半长（↑这条一起盯住）")
	# ⚠️ `SPACING` 原在这张「没碰」清单里，**轮 63-12 起移出**（本轮就是改它）——
	# 它的值与它参与的算术一律改到 §⑥ 钉。这张清单从此只含**四**项。
	t.eq(MissileRibbon.MAX_POINTS, 512, "采样点上限 512（没碰）")
	t.near(MissileRibbon.FADE_TIME, 1.6, 0.001, "淡出时间 1.6 s（没碰）")
	st.free()


# ================================================================ ⑤ 性能红线
static func _budget(t: T) -> void:
	t.lt(3.0 * float(FX.TRAIL_HIGH_AMOUNT), 300.0,
		"3 发 × HIGH = %d < 300" % (3 * FX.TRAIL_HIGH_AMOUNT))
	t.lt(float(PlayerController.FULL_SALVO_COUNT) * float(FX.TRAIL_LOW_AMOUNT), 3000.0,
		"100 发 × LOW = %d < 3000" % (PlayerController.FULL_SALVO_COUNT * FX.TRAIL_LOW_AMOUNT))
	t.gt(float(FX.TRAIL_HIGH_AMOUNT), float(FX.TRAIL_LOW_AMOUNT) * 2.0,
		"两档仍拉得开（HIGH %d > LOW %d × 2）" % [FX.TRAIL_HIGH_AMOUNT, FX.TRAIL_LOW_AMOUNT])
	t.lt(float(FX.TRAIL_LOW_AMOUNT), float(FX.TRAIL_HIGH_AMOUNT), "LOW < HIGH（档位还在）")
	t.gt(float(FX.TRAIL_LOW_AMOUNT), 0.0, "LOW 也不是 0（全弹发射仍看得见烟）")


# ================================================================ 工具
## 造一个**真的**导弹尾迹粒子系统（走产品那条路），返回它的父节点。
## ⚠️ `scale` 必须与生产一致：`missile.gd:363` 调的是 `FX.missile_trail(self, 0.65, …)`。
## 写成默认 0.5 会得到一个**更小**的粒子球（`scale_max 4.25` 而不是 5.525），
## 于是 `1.8 × scale_max = 7.65 < 8.124` ⇒ 那条「连成一体」的不变量会**假红**。
## ⚠️ 用完 `st.free()` —— 它连带把粒子系统一起释放（不 leak）。
static func _stage() -> Node3D:
	var parent := Node3D.new()
	FX.missile_trail(parent, 0.65)
	return parent

# ================================================================ ⑥ 轮 63-12
## ★ 轮 63-12 需求原话：「导弹尾迹透明度调为现在的 70%，连续性调到现在的 78%」。
##
## 口径（用户拍板 · 2026-10-04）：
##   · **透明度** = 烟带层 `MissileRibbon.ALPHA`（**只降这一层**，粒子层不动 —— P10）；
##   · **连续性** = 烟带采样间距 `MissileRibbon.SPACING`（采样密度 ×0.78）。
##
## ⚠️ 本节是**本轮需求的记录**：将来再改这两个数，本节**应当变红** ——
## 那不是回归，是"需求换了，本节该按新需求订正"。同 `godot-headless-test-verify` v6.1 ②
##（定值断言会在正确的改动上变红 ⇒ 精确值钉在**它自己那一轮**的那一节里）。
static func _r6312(t: T) -> void:
	# ---- ① 透明度：0.44 → 0.308（×0.70）----
	t.near(MissileRibbon.ALPHA, 0.308, 0.0005, "烟带头部 alpha 0.44 × 0.70 = 0.308")
	t.near(MissileRibbon.ALPHA / 0.44, 0.70, 0.002, "★ 比值 0.700 ≡「现在的 70%」")
	t.lt(MissileRibbon.ALPHA, 0.44, "确实比 D5 的 0.44 更低")
	t.gt(MissileRibbon.ALPHA, 0.20, "仍在 D5 留下的「没淡到看不见」下界之上")

	# ---- ② 连续性：采样间距 120 → 153.8（采样密度 ×0.78）----
	t.near(MissileRibbon.SPACING, 153.8, 0.05, "烟带采样间距 120 ÷ 0.78 = 153.8")
	t.near(120.0 / MissileRibbon.SPACING, 0.78, 0.003, "★ 比值 0.780 ≡「现在的 78%」")
	t.gt(MissileRibbon.SPACING, 120.0, "比旧值 120 大（采样更稀 ⇒ 连续性更低）")

	# ---- ③ 它参与的算术必须仍然成立（改这一处就要把它的算术全部重算）----
	# 转弯半径 = v / ω，ω 取**产品常量**（不抄 2.55 那个字面量 —— 只有一个真源）。
	var turn_r := SuitProfile.missile_speed() / Missile.FUNNEL_TURN_RATE
	var tick := float(Engine.physics_ticks_per_second)
	var frame_m := SuitProfile.missile_speed() / tick
	# ⚠️ 真实弦长**不是** `SPACING`：`push()` 的门是 `≥ SPACING`，而它每**物理帧**
	# 才被调一次 ⇒ 弦长落在 `[SPACING, SPACING + 每帧位移]`。
	#   · `dev`     = **理想**弦长（= SPACING）—— 源码注释里那个 1.86 m；
	#   · `dev_max` = **最坏**弦长（= SPACING + 每帧位移）—— 红线该压的是这一条。
	# 只钉理想值会把 1.86 m 当成上界，而实际最坏是它的两倍多（3.85 m）。两条都断。
	var dev := MissileRibbon.SPACING * MissileRibbon.SPACING / (8.0 * turn_r)
	var worst := MissileRibbon.SPACING + frame_m
	var dev_max := worst * worst / (8.0 * turn_r)
	t.gt(turn_r, 1000.0, "前提：转弯半径 %.0f m（它决定下面两条折角断言）" % turn_r)
	t.lt(dev, MissileRibbon.HALF_W,
		"理想弦长 %.1f m 的折线偏离圆弧 %.2f m < 半宽 %.1f m ⇒ 转弯处看不出折角"
			% [MissileRibbon.SPACING, dev, MissileRibbon.HALF_W])
	t.lt(dev_max, MissileRibbon.HALF_W,
		"★ 最坏弦长 %.1f m（间距 + 物理帧位移 %.1f m）偏离 %.2f m < 半宽 %.1f m"
			% [worst, frame_m, dev_max, MissileRibbon.HALF_W])
	var need := 14.0 * SuitProfile.missile_speed() / MissileRibbon.SPACING
	t.lt(need, float(MissileRibbon.MAX_POINTS),
		"满量程 14 s 的点数 %.0f < 上限 %d ⇒ 不会丢发射点那端" % [need, MissileRibbon.MAX_POINTS])

	# ---- ④ 宽度（体积）没被这一轮碰到 ----
	t.near(MissileRibbon.HALF_W, 6.0, 0.000001, "半宽仍 6.0 —— SPACING 与 HALF_W 是两根独立的轴")
