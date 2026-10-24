class_name SuiteMissileSmoke
extends RefCounted
## **导弹烟幕**（1.2.1 · 批 3 · DESIGN §4.4）。
##
## ## 需求原话与它的真实含义
##
## 「也不用搞多华丽，得搞点烟幕」「导弹后面的烟幕能增加代入感」。
## ⇒ 这条需求**不是加光效**，而是**把尾迹从"光点"换成"烟"**。
## 所以本套件最要紧的一节不是"粒子数对不对"，而是
## **② 尾迹的材质还算不算「烟」** —— 它一旦变回自发光/加色，需求就整个做反了。
##
## ## 七节
##
##   ① 档位映射 `trail_amount()`：LOW / HIGH / 未知值兜底
##   ② **尾迹是烟不是火**：混合模式 / 不自发光 / 色带方向 / 柔边遮罩
##   ③ 档位真的**到得了发射器**（不是只存在字段里）
##   ④ 帧率防线：3 发与 100 发的粒子数都在账内
##   ⑤ 挂架弹射的一小团烟（每发一次，粒子数被压过）
##   ⑥ 全弹发射的 100 发走 LOW、且**不放**弹射烟（真路径，经 PlayerController）
##   ⑦ **载机速度继承**（轮 13：让"导弹从机体上发射出去"真的看得见）
##
## ## ⚠️ 为什么②要读材质而不是读常量
##
## 设计文档 §4.4 的表格里写着「材质：白色加色 billboard → `_soft_smoke_mat()`」。
## 那句话的**可观察含义**只有三条：普通 alpha 混合、不自发光、色带往下走（越叠越暗）。
## 断言这三条就等于断言了那张表格；而断言"某个常量 == 某个值"什么都不证明。

const ALT := 3000.0


static func run(t: T, host: Node) -> void:
	t.suite("MissileSmoke / 档位映射")
	_levels(t)
	t.suite("MissileSmoke / 尾迹是「烟」不是「火」，也是「体」不是「面」")
	await _is_smoke(t, host)
	t.suite("MissileSmoke / 档位到得了发射器")
	await _level_reaches_emitter(t, host)
	t.suite("MissileSmoke / 帧率防线（粒子数账目）")
	_budget(t)
	t.suite("MissileSmoke / 挂架弹射的一小团烟")
	await _launch_puff(t, host)
	t.suite("MissileSmoke / 全弹发射走 LOW（真路径）")
	await _full_salvo(t, host)
	t.suite("MissileSmoke / 载机速度继承（轮 13：看得见的发射）")
	await _inherit_velocity(t, host)
	t.suite("MissileSmoke / 尾迹改受光之后：材质分工与零回归（轮 38）")
	_material_split(t)
	t.suite("MissileSmoke / 尾迹浓密度：簇与间距（轮 39）")
	_density(t)
	t.suite("MissileSmoke / 连续烟带：长度（轮 40）")
	await _ribbon(t, host)
	t.suite("MissileSmoke / 烟带渲染抽稀（轮 41）")
	await _ribbon_lod(t, host)
	t.suite("MissileSmoke / 近距离淡出：贴着镜头那段透明（★63-21）")
	_near_fade(t)


# ============================================================ 工具

static func _new_unit(container: Node3D, team: int, pos: Vector3, hp := 400.0,
		as_player := false) -> FlightBody:
	var u := FlightBody.new()
	u.team = team
	u.is_player = as_player
	u.profile = SuitProfile.penelope() if team == 0 else SuitProfile.xi()
	u.display_name = "T%d" % team
	u.projectile_container = container
	container.add_child(u)
	u.global_position = pos
	u.max_hp = hp
	u.hp = hp
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	u.fm.speed = 260.0
	u.fm.throttle = 0.78
	u.fm.align_velocity(u.forward())
	return u


static func _frames(host: Node, n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame


## `from_idx` 之后新进容器的、`shooter` 打出的那些弹。
static func _missiles_from(c: Node, shooter: FlightBody, from_idx: int) -> Array:
	var out := []
	var kids := c.get_children()
	for i in range(from_idx, kids.size()):
		var m := kids[i] as Missile
		if m != null and m.shooter == shooter:
			out.append(m)
	return out


## 容器里从 `from_idx` 起新增的**烟团根节点**。
##
## ⚠️ **不能按节点名找**（第一版就是那么写的，当场踩到）：
## `FX.smoke_burst()` 给根节点起的名字是 `"SmokeBurst"`，而 `fire_funnel()` 一梭三发
## **同帧**把三团烟加进**同一个容器** —— Godot 碰到重名会把第二、第三个改成
## **自动名 `@Node3D@NNNN`**（**不是** `SmokeBurst2`！
## `Node::_generate_serial_child_name()` 对"没有尾号的名字"走的是自动名那条路）。
## 结果：按名字找永远只能找到 **1** 个，症状看起来像"三发只放了一团烟"——
## 而真实行为完全正常。所以判据必须是**结构**的：
## 容器级的、**不是弹丸/机体**、且挂着 `GPUParticles3D` 的节点。
static func _smoke_bursts(c: Node, from_idx: int) -> Array:
	var out := []
	var kids := c.get_children()
	for i in range(from_idx, kids.size()):
		var ch := kids[i]
		if ch is Missile or ch is FlightBody or ch is Projectile:
			continue
		if _burst_emitter(ch) != null:
			out.append(ch)
	return out


## 一个烟团根节点里的粒子发射器。
static func _burst_emitter(root: Node) -> GPUParticles3D:
	for ch in root.get_children():
		if ch is GPUParticles3D:
			return ch as GPUParticles3D
	return null


## 一发导弹身上的尾迹发射器。
static func _trail_of(m: Missile) -> GPUParticles3D:
	return m.get_node_or_null("MissileTrail") as GPUParticles3D


## 容器里那条**连续烟带**（轮 40）。它挂在弹的**父容器**上（见 `Missile._ready()`），
## 所以只能从容器里按**类型**找 —— 按名字找的话改名时静默失配。
static func _ribbon_of(m: Missile) -> MissileRibbon:
	var holder := m.get_parent()
	if holder == null:
		return null
	for ch in holder.get_children():
		if ch is MissileRibbon:
			return ch as MissileRibbon
	return null


# ============================================================ ① 档位映射

static func _levels(t: T) -> void:
	t.eq(Missile.Trail.LOW, 0, "「Trail.LOW」是枚举第一项（存档/序列化的隐含前提）")
	t.eq(Missile.trail_amount(Missile.Trail.LOW), FX.TRAIL_LOW_AMOUNT,
		"LOW ⇒ %d 粒子/发" % FX.TRAIL_LOW_AMOUNT)
	t.eq(Missile.trail_amount(Missile.Trail.HIGH), FX.TRAIL_HIGH_AMOUNT,
		"HIGH ⇒ %d 粒子/发" % FX.TRAIL_HIGH_AMOUNT)
	t.eq(Missile.trail_amount(999), FX.TRAIL_HIGH_AMOUNT,
		"未知档位**兜底到 HIGH** —— 宁可多几个粒子，也不要静默变成「没有尾迹」")
	t.lt(FX.TRAIL_LOW_AMOUNT, FX.TRAIL_HIGH_AMOUNT,
		"LOW 一定要比 HIGH 少（否则这个档位等于不存在）")
	t.gt(FX.TRAIL_LOW_AMOUNT, 0, "LOW 也不是 0 —— 全弹发射**必须仍看得见烟**")


# ============================================================ ② 是烟不是火

static func _is_smoke(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var shooter := _new_unit(c, 0, Vector3(0, ALT, 0), 400.0, true)
	var m := Missile.spawn(c, Vector3(0, ALT, 0), Vector3.FORWARD, null, shooter, 10.0)
	var p := _trail_of(m)
	t.ok(p != null, "导弹身上挂了尾迹发射器（`FX.missile_trail` 真被调到了）")
	if p == null:
		c.free()
		return

	# ---- 材质语义：这一节的核心 ----
	var mesh := p.draw_pass_1 as SphereMesh
	t.ok(mesh != null, "尾迹用的是球体（不是 quad）")
	if mesh != null:
		var mat := mesh.material as StandardMaterial3D
		t.ok(mat != null, "球体带了材质")
		if mat != null:
			# ---- 「烟不是火」：这三条**本轮一字未改** ----
			t.eq(mat.blend_mode, BaseMaterial3D.BLEND_MODE_MIX,
				"**普通 alpha 混合** —— 加色做烟会把背景照亮，颜色调得再暗也没用")
			t.not_ok(mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD,
				"……而且确实**不是**加色（老版本就是加色，所以夜景里读成一串发光点）")
			t.ok(mat.vertex_color_use_as_albedo,
				"`vertex_color_use_as_albedo` 必须开 —— 否则色带被忽略、烟渲染成材质白色（踩过）")
			t.ok(mat.albedo_texture != null,
				"有程序生成的粒子贴图（絮状斑驳 + v 方向 alpha 柔边）—— 否则近看是硬边实心球")
			# ---- 「是体不是面」：轮 38 新增，也是本轮改动的**目的本身** ----
			#
			# ⚠️ 为什么"受光"是体积感的判据（而不是审美偏好）：
			# 体积感的物理来源是"**同一个物体上有明暗层次**"。而老材质上那两行开关
			# （`UNSHADED` + `BILLBOARD`）恰好把它抹掉了 —— 球面没有明暗梯度，
			# 而且不管 mesh 是不是球，屏幕上永远是"朝向一致的一枚柔边圆盘"。
			# 所以这两条断言**等价于**"它现在能读出体积"，不是形式主义。
			t.eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL,
				"**受光（PER_PIXEL）** —— 每颗球有自己的迎光面/背光面，这是体积感的物理来源")
			t.not_ok(mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
				"……而且确实**不是** unshaded（老版本 unshaded：关掉场景主光后尾迹像素逐位不变）")
			t.eq(mat.billboard_mode, BaseMaterial3D.BILLBOARD_DISABLED,
				"**不是 billboard** —— 球真的是球（开了 billboard 等于把球拍平成圆盘）")
			t.gt(mat.albedo_color.r, 1.0,
				"albedo 走 **HDR（> 1）** —— 夜战光弱，受光项要靠它把亮度抬回可读区间（实得 %.2f）"
					% mat.albedo_color.r)
			t.gt(mat.roughness, 0.9, "粗糙度拉满 —— 烟不该有镜面高光（有高光就成了「塑料球」）")
			# ---- 「烟不是火」的新口径：emission 从"不许有"改成"必须低 + 不暖" ----
			t.ok(mat.emission_enabled,
				"允许一点 emission：它是**多重散射的地光**（半透明体积不该像固体那样背光全黑）")
			t.gt(mat.emission_energy_multiplier, 0.0, "……但必须真的有一点（0 就不是「补底」了）")
			t.lt(mat.emission_energy_multiplier, 0.5,
				"……而且必须**很低**（实得 %.2f；老版加色 billboard 是 2.0，差一个数量级以上）"
					% mat.emission_energy_multiplier)
			t.gt(mat.emission.b, mat.emission.r,
				"emission 偏冷（B > R）—— **暖色才会读成「火」**，这是「烟不是火」的分界换了个位置")
			# ---- 几何：受光必须配够细分 ----
			t.gt(mesh.radial_segments, 7,
				"经线 %d 段 —— 受光后 5 段会看成多面体" % mesh.radial_segments)
			t.gt(mesh.rings, 5,
				"纬线 %d 段 —— 老值 2 段在 unshaded 下看不出来（反正被拍平了），一受光就折断成棱"
					% mesh.rings)
			var tris := mesh.radial_segments * mesh.rings * 2
			t.lt(tris, 200, "单颗粒子 %d 三角 —— 受光的必要代价，但不许失控" % tris)

	# ---- 色带方向：烟是「越叠越暗」 ----
	var pm := p.process_material as ParticleProcessMaterial
	t.ok(pm != null, "有粒子过程材质")
	if pm != null:
		var ramp := pm.color_ramp as GradientTexture1D
		t.ok(ramp != null, "粒子存活期内有颜色带（`color_ramp`）")
		if ramp != null:
			var col0 := ramp.gradient.get_color(0)
			var col1 := ramp.gradient.get_color(1)
			t.gt(col0.r, col1.r, "色带**由浅灰转中灰**（越叠越暗，与加色的方向相反）")
			t.lt(col0.r, 0.95, "起点是浅灰而不是纯白（纯白在夜景里仍然是发光点）")
			t.gt(col0.r, 0.80, "……但也别灰到看不见（实得 %.2f）" % col0.r)
			t.gt(col0.a, col1.a, "alpha 一路衰减（烟要散掉，不能留一个硬球）")
			t.near(col1.a, 0.0, 0.02, "末端全透明")

	# ⚠️ 轮 39 改了这条的口径：**寿命不是越长越好**。
	# 它和弹速一起决定"柱有多长"，而"浓不浓"是**另一条**算式
	#（簇间距 = 弹速 ÷ fixed_fps，以及摊开后的 弹速 × lifetime ÷ amount）。
	# 老值 2.8 s 是在弹速 1134 m/s 的年代定的；弹速涨到 4062 之后它拉出 11.4 km 的柱，
	# 而 80 颗粒子全撒在那 11 km 上 ⇒ 一串孤立的点。详见文件末的 `_density()`。
	# ★ 轮 63-9 · D5：0.16 → 0.128（与 `TRAIL_HIGH_AMOUNT` 同比例 −20%）。
	# ⚠️ 这条硬数字断言**必须跟着改** —— 它就是「谁动了这个数都得留下痕迹」的闸门。
	# 只改 amount 不改 lifetime 会破掉本文件 `_density()` 的 `spacing < diam_max`。
	t.near(p.lifetime, 0.128, 0.0005,
		"寿命 0.128 s（= 轮 39 的 0.16 s × 0.8；老版 2.8 s）—— 按**峰值弹速**标定，见 `_density()`")
	t.not_ok(p.local_coords, "`local_coords = false` —— 烟留在**原地**，不跟着弹跑")
	t.eq(p.amount, FX.TRAIL_HIGH_AMOUNT,
		"默认档位是 HIGH（%d 粒子）—— 普通扳机走的就是它" % p.amount)

	# ---- 增厚（2026-09-22 用户："增加增厚导弹弹幕烟雾拖尾"）----
	# 预算红线卡死粒子数（见 `_budget`），所以"厚"的主力是**几何**：
	# 锥角放宽 / 出生尺寸加大 / 随龄扩散 / 色带加浓。逐条钉住，防止将来被"优化"回去。
	if pm != null:
		t.gt(pm.spread, 15.0, "锥角放宽（spread > 15°）—— 烟柱从细线变成柱")
		# ⚠️ 口径：`scale_max` 是**绝对值**（8.5 × 发射端 scale 0.65 = 5.525）；
		# 老值只有 5.5 × 0.55 = 3.025 —— 阈值取 5.0，两头都拉得开。
		t.gt(pm.scale_max, 5.0, "粒子出生尺寸加大（scale_max > 5.0）—— 增厚主力")
		var gt := pm.scale_curve as CurveTexture
		if gt != null:
			# ⚠️ Godot 4.7 的 `Curve` **没有** `get_points()`（实测 SCRIPT ERROR），
			# 取终点用 `get_point_position(count - 1)`。
			var cur: Curve = gt.curve
			var end_y := cur.get_point_position(cur.get_point_count() - 1).y
			t.gt(end_y, 1.0,
				"烟团**随龄扩散**（生长曲线终点 > 1）—— 老烟比新烟大，烟云自己长胖")
		var r0 := (pm.color_ramp as GradientTexture1D).gradient.get_color(0)
		t.gt(r0.a, 0.84, "色带起点加浓（alpha > 0.84）—— 弹幕里烟读得出来")

	c.free()
	await _frames(host, 2)
	Game.reset()


# ============================================================ ③ 档位到发射器

static func _level_reaches_emitter(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var shooter := _new_unit(c, 0, Vector3(0, ALT, 0), 400.0, true)

	var hi := Missile.funnel(c, Vector3(0, ALT, 0), Vector3.FORWARD, null, shooter, 10.0)
	t.eq(hi.trail_level, Missile.Trail.HIGH, "`funnel()` 不传档位 ⇒ HIGH（默认值）")
	var hi_p := _trail_of(hi)
	t.ok(hi_p != null, "HIGH 那发也有尾迹")
	if hi_p != null:
		t.eq(hi_p.amount, FX.TRAIL_HIGH_AMOUNT, "……粒子数是 HIGH 的")

	var lo := Missile.funnel(c, Vector3(0, ALT, 0), Vector3.FORWARD, null, shooter, 10.0,
		Missile.Trail.LOW)
	t.eq(lo.trail_level, Missile.Trail.LOW, "`funnel(..., LOW)` ⇒ 字段是 LOW")
	var lo_p := _trail_of(lo)
	t.ok(lo_p != null, "LOW 那发也有尾迹")
	if lo_p != null:
		t.eq(lo_p.amount, FX.TRAIL_LOW_AMOUNT,
			"**档位真的走到了发射器** —— 只存在字段里的话，改了等于没改")

	var sp := Missile.spawn(c, Vector3(0, ALT, 0), Vector3.FORWARD, null, shooter, 10.0,
		Missile.Trail.LOW)
	var sp_p := _trail_of(sp)
	t.ok(sp_p != null, "`spawn()` 打出去的也有尾迹")
	if sp_p != null:
		t.eq(sp_p.amount, FX.TRAIL_LOW_AMOUNT, "`spawn()` 也能传档位")

	# 共用材质：尾迹、尾气、一次性烟团应当**同一份配方**（`_soft_smoke_mat()` 的 static 缓存）
	var a := (hi_p.draw_pass_1 as SphereMesh).material if hi_p != null else null
	var b := (lo_p.draw_pass_1 as SphereMesh).material if lo_p != null else null
	t.ok(a != null and a == b,
		"两档共用同一份烟材质（static 缓存）—— 100 发齐射不必建 100 个材质 + 100 张遮罩贴图")

	c.free()
	await _frames(host, 2)
	Game.reset()


# ============================================================ ④ 帧率防线

static func _budget(t: T) -> void:
	var per_shot := SuitProfile.MISSILE_PER_SHOT
	var high_total := per_shot * FX.TRAIL_HIGH_AMOUNT
	var low_total := PlayerController.FULL_SALVO_COUNT * FX.TRAIL_LOW_AMOUNT
	t.eq(per_shot, 3, "（前提）一次扳机 3 发")
	t.eq(PlayerController.FULL_SALVO_COUNT, 100, "（前提）全弹发射 100 发")
	t.lt(high_total, 300,
		"普通扳机的尾迹总量 %d 粒子（老版 3 × 90 = 270，同一量级，不该变差）" % high_total)
	t.lt(low_total, 3000, "全弹发射的尾迹总量 %d 粒子，必须 < 3000" % low_total)
	t.lt(low_total, PlayerController.FULL_SALVO_COUNT * 90,
		"……而且必须**远小于**老值（100 × 90 = 9000）—— 那条路会把帧率打下去")
	t.gt(FX.TRAIL_HIGH_AMOUNT, FX.TRAIL_LOW_AMOUNT * 2,
		"两档确实拉得开（HIGH %d > LOW %d × 2）—— 不是白分档"
			% [FX.TRAIL_HIGH_AMOUNT, FX.TRAIL_LOW_AMOUNT])


# ============================================================ ⑤ 挂架弹射的烟

static func _launch_puff(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 400.0, true)
	var foe := _new_unit(c, 1, Vector3(0, ALT, -2000.0))
	me.funnel_count = 30
	me.funnel_cooldown = 0.0

	var mark := c.get_child_count()
	t.ok(me.fire_funnel(foe), "（前提）一梭打得出去")
	var shots := SuitProfile.MISSILE_PER_SHOT
	var missiles := _missiles_from(c, me, mark)
	t.eq(missiles.size(), shots, "（前提）这一梭 %d 发" % shots)

	var bursts := _smoke_bursts(c, mark)
	var dbg := ""
	for i in range(mark, c.get_child_count()):
		var ch := c.get_child(i)
		var kids := ""
		for g in ch.get_children():
			kids += "%s(%s) " % [str(g.name), g.get_class()]
		dbg += "\n    %d:[%s](%s) isMissile=%s kids=[%s]" % [i, str(ch.name),
			ch.get_class(), str(ch is Missile), kids]
	print("  [DBG-⑤] 容器新增:", dbg)
	t.eq(bursts.size(), shots,
		"**每一发离架都有一小团烟**（%d 团，对应 %d 发）—— 挂架弹射的观感" % [bursts.size(), shots])
	for b in bursts:
		var e := _burst_emitter(b as Node)
		t.ok(e != null, "烟团里真的有粒子发射器")
		if e != null:
			t.eq(e.amount, FX.MISSILE_LAUNCH_PUFF,
				"粒子数被压到 %d（`smoke_burst` 默认 %d 是「一大团」的值）"
					% [e.amount, FX.SMOKE_BURST_AMOUNT])
			t.lt(e.amount, FX.SMOKE_BURST_AMOUNT,
				"……确实小于默认值（3 发 × %d = %d 粒子只为「一小团烟」）"
					% [FX.SMOKE_BURST_AMOUNT, 3 * FX.SMOKE_BURST_AMOUNT])

	# 对比「一大团」是什么量级：`smoke_burst` 的**默认**参数。
	# ⚠️ 两者不能混为一谈：一个是"挂架那儿冒一小股"，一个是"放一片掩体"。
	# 弹射烟必须**显式**把粒子数压下去，因为默认值不是给这个场合调的。
	var mark2 := c.get_child_count()
	FX.smoke_burst(c, Vector3(0, ALT, 0), 4.6, 3.5)
	var big := _smoke_bursts(c, mark2)
	t.eq(big.size(), 1, "（前提）默认参数下放出来的是「一大团」")
	if not big.is_empty():
		var be := _burst_emitter(big[0] as Node)
		t.ok(be != null and be.amount > FX.MISSILE_LAUNCH_PUFF * 5,
			"默认烟团（%d 粒子）比弹射烟（%d）大一个数量级 —— 所以弹射烟必须显式压小"
				% [be.amount if be != null else -1, FX.MISSILE_LAUNCH_PUFF])

	c.free()
	await _frames(host, 2)
	Game.reset()


# ============================================================ ⑥ 全弹发射走 LOW

## 走**真路径**：`PlayerController.fire_full_salvo()` → `_tick_full_salvo()` → `_emit_full_salvo_shot()`。
##
## ⚠️ 这条不能靠"读源码确认传了 LOW"结案：`Missile.funnel()` 的参数有 7 个，
## 传错位置（比如把档位塞进 `damage_amount`）照样能编译过 —— 而症状是**弹幕掉帧**，
## 只有在 100 发齐射时才看得出来。所以这里真的把 100 发打出来、逐发读档位。
static func _full_salvo(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.team = 0
	pc.is_player = true
	pc.profile = SuitProfile.penelope()
	pc.projectile_container = c
	c.add_child(pc)
	pc.global_position = Vector3(0, ALT, 0)
	pc.fm.speed = 260.0
	pc.fm.throttle = 0.78
	pc.fm.align_velocity(pc.forward())
	# 裸实例没有 camera / 输入 ⇒ `_think()` 跑不了。这一节只测全弹发射的弹与烟。
	pc.set_physics_process(false)

	var foe := _new_unit(c, 1, Vector3(0, ALT, -2000.0))
	pc.funnel_count = 200
	var total := PlayerController.FULL_SALVO_COUNT

	var mark := c.get_child_count()
	t.ok(pc.fire_full_salvo(foe), "全弹发射放得出去")
	var guard := 0
	while int(pc.get("_full_salvo_left")) > 0 and guard < 400:
		pc.call("_tick_full_salvo", 0.05)
		guard += 1
	t.eq(int(pc.get("_full_salvo_left")), 0, "分批放完")

	var missiles := _missiles_from(c, pc, mark)
	t.eq(missiles.size(), total, "容器里真的多了 %d 发" % total)
	var low := 0
	var high := 0
	var emitter_wrong := 0
	for mm in missiles:
		var m := mm as Missile
		if m.trail_level == Missile.Trail.LOW:
			low += 1
		else:
			high += 1
		var p := _trail_of(m)
		if p == null or p.amount != FX.TRAIL_LOW_AMOUNT:
			emitter_wrong += 1
	t.eq(low, total, "**100 发全部是 `Trail.LOW`**")
	t.eq(high, 0, "……一发 HIGH 都没有（这就是帧率防线本身）")
	t.eq(emitter_wrong, 0, "……而且每一发的发射器粒子数也是 LOW 的（%d）" % FX.TRAIL_LOW_AMOUNT)
	t.eq(_smoke_bursts(c, mark).size(), 0,
		"全弹发射**不放弹射烟**（100 团 × %d 粒子只为「一小团」是不划算的；弹幕的烟由尾迹自己给）"
			% FX.MISSILE_LAUNCH_PUFF)

	# 撞地/到寿要能自清（这一节把 100 发留在场上，顺手确认它们都能被释放）
	for mm in missiles:
		(mm as Missile).queue_free()
	c.free()
	await _frames(host, 2)
	Game.reset()


# ============================================================ ⑦ 载机速度继承

## 用户原话：「导弹和光束都得是从机体身上发射出去的，**现在完全看不到导弹的发射了**」。
##
## ## 根因不是"发射点画错了"，是**导弹不带载机速度**
## 浮游导弹出膛 `speed = 90 m/s` 是**相对地面**给的，而机体 `×2.4` 之后加力极速
## 是 **2268 m/s** ⇒ 离架那一瞬间，导弹相对机体以 ≈2270 m/s **向后**跑：
## 0.15 s 落后 340 m、**0.55 s（弹射段结束、刚开始制导）落后 ≈1200 m**。
## 相机是跟随机体的 ⇒ 玩家从头到尾看不见那一发弹。
##
## ## 所以这一节量四件事
##
##   ① `launch_vel` 真的等于发射那一刻的载机速度（`funnel()` 与 `spawn()` **两条路都要**）；
##   ② **载机静止时它恒为 0** —— 这是零回归点：那一发的弹道与改造前逐位相同；
##   ③ 相机参考系里的位移是「弹射」不是「掉队」（用一个"人为清零继承量"的对照发量化差距）；
##   ④ 衰减由 `inherit_factor()` 算、**到点归零**（不是指数尾巴）。
##
## ## ⚠️ ③ 凭什么能把"继承项"单独量出来
## 弹射方向取 **+X**（侧向）、载机速度取 **−Z**（机头）—— 两者**正交**。
## 于是弹体位移的 **Z 分量里只有继承项**，自航那一份（沿 +X）一点都掺不进来。
## 若两者同向（比如都取 −Z），量到的是"继承 + 自航"之和，断言只能写得很松 ——
## 那就不叫判据，叫复述实现。
static func _inherit_velocity(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var shooter := _new_unit(c, 0, Vector3(0, ALT, 0), 400.0, true)
	var boost: float = SuitProfile.penelope().player_boost_speed()

	# ---- ② 零回归点 ----
	shooter.fm.speed = 0.0
	shooter.fm.velocity = Vector3.ZERO
	var still := Missile.funnel(c, Vector3(0, ALT, 0), Vector3.RIGHT, null, shooter, 10.0)
	t.ok(still.launch_vel.is_zero_approx(),
		"载机静止 ⇒ 继承量恒为 0（**零回归点**：这一发的弹道与改造前逐位相同）")

	# ---- ① 真的继承 ----
	shooter.fm.velocity = Vector3(0.0, 0.0, -boost)
	var fast := Missile.funnel(c, Vector3(0, ALT, 0), Vector3.RIGHT, null, shooter, 10.0)
	t.near(fast.launch_vel.length(), boost, 0.5,
		"载机满加力 %.0f ⇒ 继承量 %.0f —— 弹射初速 90 只管「相对载机」那一段"
			% [boost, fast.launch_vel.length()])
	t.gt(fast.launch_vel.dot(Vector3(0.0, 0.0, -1.0)), 0.0, "方向与机头一致（不是反的）")

	var gen := Missile.spawn(c, Vector3(0, ALT, 0), Vector3.RIGHT, null, shooter, 10.0)
	t.near(gen.launch_vel.length(), boost, 0.5,
		"普通导弹 `spawn()` 走同一条 `_configure()` ⇒ 同样继承（只改 `funnel()` 会漏一半）")

	# ---- ③ 位移：跟着机体走 vs 掉队 ----
	# 对照发：同一个位置、同一个弹射方向，**人为把继承量清零** = 精确复刻改造前的行为。
	var old := Missile.funnel(c, Vector3(0, ALT, 0), Vector3.RIGHT, null, shooter, 10.0)
	old.launch_vel = Vector3.ZERO

	var p_fast := fast.global_position
	# ⚠️ 量测点取 **0.55 s = `deploy_time`**（弹射段结束、导引头刚开始接管的那一刻）——
	# 那正是老版里"已经掉出画面"的时刻，所以它是这条判据最有信息量的采样点。
	#（再往后继承在衰减、自航在加速，两者混在一起，反而不容易读。）
	await _frames(host, 33)                       # 0.55 s @60 fps
	var moved := fast.global_position - p_fast

	# 理论值：∫₀^el (1 − τ/Decay) dτ = el − el²/(2·Decay)
	var decay: float = Missile.INHERIT_DECAY_TIME
	var el := 33.0 / 60.0
	var ideal: float = -boost * (el - el * el / (2.0 * decay))
	t.near(moved.z, ideal, absf(ideal) * 0.08,
		"0.55 s（= 弹射段结束）沿机头方向位移 %.0f m ≈ 载机速度的衰减积分 %.0f m ⇒ 导弹**跟着机体走**"
			% [moved.z, ideal])

	var gap: float = fast.global_position.z - old.global_position.z
	t.gt(absf(gap), absf(ideal) * 0.7,
		"与「不继承」对照：0.55 s 就拉开 **%.0f m** —— 老版里它就是在这里掉队到相机后面的"
			% gap)
	print("  [R13] 载机 %.0f m/s · 0.55 s：新弹沿机头走了 %.0f m（理论 %.0f m）；老弹 %.0f m ⇒ 差距 %.0f m"
		% [boost, moved.z, ideal, old.global_position.z, gap])

	# ---- ④ 衰减确定、到点归零 ----
	t.eq(Missile.inherit_factor(0.0), 1.0, "刚离架：全额继承")
	t.near(Missile.inherit_factor(decay * 0.5), 0.5, 0.001, "半程恰好减半（线性，不是指数）")
	t.eq(Missile.inherit_factor(decay), 0.0, "到点**归零**")
	t.eq(Missile.inherit_factor(decay * 5.0), 0.0, "再往后仍是 0（不会变负 ⇒ 不会反向拉）")
	t.gt(Missile.inherit_factor(0.1), Missile.inherit_factor(0.5), "随龄单调递减")
	t.gt(decay, 0.55,
		"衰减时间 %.2f s **大于**弹射段 0.55 s —— 否则导引头接管那一刻会看到一次速度台阶"
			% decay)
	t.lt(decay, 3.0, "……但也不能太长（那是「导弹挂在机体旁边蹭半天」，咬尾就没有代价了）")

	c.free()
	await _frames(host, 2)
	Game.reset()


# ============================================================ ⑧ 材质分工（轮 38）

## 本轮把尾迹的材质**另开了一份**（`_trail_smoke_mat()`），没有去 mutate
## `_soft_smoke_mat()`。这一节就是钉住这件事的两面：
##   · 两面**确实是两份**（否则将来的改动会互相踩）；
##   · 另外三种烟**确实一点没变**（`exhaust_smoke` / `smoke_burst` / `damage_smoke` 继续
##     用老配方：unshaded + billboard + `energy = 0`）—— 本轮**零回归**的书面承诺。
##
## ⚠️ 第 ③ 条（三角预算）为什么值得单独钉：细分 5×2 → 8×6 是本轮**唯一涨了的开销**
## （≈20 → ≈96 三角/粒子）。而 LOW 档是全弹发射 100 发 × 28 粒子 = 2800 粒子，
## 乘上去就是 ~27 万三角 —— 不是小数目，所以要有个看得见的闸。
static func _material_split(t: T) -> void:
	var trail := FX._trail_smoke_mat()
	var shared := FX._soft_smoke_mat()
	t.ok(trail != null and shared != null, "两份材质都建得出来")
	t.ok(trail != shared,
		"尾迹用的是**自己那一份**（`_trail_smoke_mat()`），不是共用的 `_soft_smoke_mat()`")
	if trail != null and shared != null:
		t.eq(shared.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED,
			"共用的那份**仍然是 unshaded** —— 尾气/烟团/受损黑烟的观感零回归")
		t.eq(shared.billboard_mode, BaseMaterial3D.BILLBOARD_ENABLED,
			"……而且仍然面向相机（它们的柔边靠径向渐变圆盘，那个配方是对的）")
		t.not_ok(shared.emission_enabled, "……仍然 `energy = 0`（那三种烟的「不是火」守卫原样保留）")
		t.eq(trail.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL,
			"而尾迹那份是受光的（两份的分界就在这里）")
		# static 缓存：同一个对象反复取到，全弹发射不会建 100 份。
		t.ok(FX._trail_smoke_mat() == trail, "尾迹材质是 static 缓存（反复取到同一个对象）")
		t.ok(FX._soft_smoke_mat() == shared, "共用材质同样是 static 缓存")
	# ② 球体细分与三角预算（整份 mesh 只建一个，所以这里直接读它）。
	var m := FX._trail_mesh()
	t.ok(m != null, "尾迹球体建得出来")
	if m != null:
		var tris := m.radial_segments * m.rings * 2
		t.gt(tris, 0, "球体三角数 %d" % tris)
		t.lt(tris, 200, "单颗粒子三角 %d < 200（受光的必要代价，但留了上限）" % tris)
		t.eq(m.material, FX._trail_smoke_mat(),
			"球体挂的就是尾迹那一份材质（别处改错对象的话这条会红）")


# ============================================================ ⑨ 浓密度（轮 39）

## ## 用户原话
##
## 「浮游导弹飞行过程中的烟雾能不能浓密一点，是不是烟雾是按时间生成的
##   现在浮游导弹飞行速度加快了导致烟雾的飞行轨迹变得那么稀疏。」
##
## ## 他判断对了，而且这里**有两层算式**（第一版只看到第一层，等于白改了一次）
##
## `GPUParticles3D` 的发射是**按 `fixed_fps` 量化**的（Godot 默认 **30**）：
## 每个 `1/fixed_fps` 秒吐一次，一次 `amount / lifetime / fixed_fps` 个，
## 而它们**出生在同一个点**（发射器此刻的位置）。于是
##
##     ① 簇间距     = 弹速 ÷ fixed_fps              ← 屏幕上"孤立的球"之间的距离
##     ② 摊开后间距 = 弹速 × lifetime ÷ amount       ← 发射盒把每簇拉开之后才是这个
##
## 实测（`tools/probe_trail_density_shots.gd` 的 `a_side` 图，由 `diag39_blobs.py` 量）：
## 老版 `lifetime = 2.8` 与新版 `0.16` 的**簇间距分别是 129.9 / 124.3 m** ——
## 比值 0.96，**与 lifetime 无关**。所以"把 lifetime 砍短"只让球变得更实
##（亮团宽度 4.1 → 8.6 m），一点也没解决稀疏；真正让它变稀的是 ① 那 135 m 的簇距
## 配 4~10 m 的球。
##
## ## 这一节钉什么
##
##   · `fixed_fps` 被**显式**写出来（它是 ① 的分母，不许隐式依赖引擎默认值）；
##   · 发射盒真的设上了、长度**等于簇间距**、并且朝**弹的后方**（+Z）；
##   · ② 摊开后的间距 **小于粒子直径** —— 这条才是"浓密"的不变量。
##
## ⚠️ 最后一条为什么是**不变量**而不是"某个数字"：`lifetime` / `amount` / `fixed_fps`
## 都是可以随弹速改的，但"间距 < 直径 ⇒ 连成一体"永远成立。把 lifetime 调回去、
## 或把 amount 调小、或把发射盒去掉，都会让这一节先红给你看。
static func _density(t: T) -> void:
	var c := Node3D.new()
	var p := FX.missile_trail(c, 0.65, FX.TRAIL_HIGH_AMOUNT)
	t.ok(p != null, "尾迹发射器建得出来")
	if p == null:
		c.free()
		return
	var pm := p.process_material as ParticleProcessMaterial
	t.ok(pm != null, "有粒子过程材质")
	if pm == null:
		c.free()
		return

	# ---- ① 簇间距 = 弹速 ÷ fixed_fps ----
	t.eq(p.fixed_fps, 30,
		"`fixed_fps` **显式**是 30 —— 它是簇间距的分母，不许隐式依赖引擎默认值")
	var v_max := SuitProfile.missile_speed()
	var cluster := v_max / float(p.fixed_fps)
	t.gt(cluster, 100.0,
		"峰值弹速 %.0f m/s 下**簇间距 %.0f m** —— 这就是那串孤立的点之间的距离" % [v_max, cluster])

	# ---- ② 发射盒：把每一簇沿弹轴摊开 ----
	t.eq(pm.emission_shape, ParticleProcessMaterial.EMISSION_SHAPE_BOX,
		"发射形状是**盒**（默认的点会让每簇挤在一点 ⇒ 屏幕上就是一颗球）")
	var hz := pm.emission_box_extents.z
	t.gt(hz, 0.0, "盒子沿 Z 有长度（%.1f m）" % hz)
	t.near(hz * 2.0, cluster, 2.0,
		"盒长 %.1f m ≈ 簇间距 %.1f m —— 簇与簇**首尾相接**，中间不留缝" % [hz * 2.0, cluster])
	t.near(pm.emission_shape_offset.z, hz, 0.01,
		"盒子整体向 +Z 偏一个半长 ⇒ 覆盖 [0, 簇间距]")
	t.gt(pm.emission_shape_offset.z, 0.0,
		"**+Z 是弹的后方**（`Missile` 前进朝 −Z）—— 偏移写成负的，烟会跑到弹前面去")

	# ---- ③ 不变量：摊开后的间距必须小于粒子直径 ----
	var spacing := v_max * p.lifetime / float(p.amount)
	var diam_max := 1.8 * pm.scale_max
	t.lt(spacing, diam_max,
		"摊开后间距 %.2f m < 粒子最大直径 %.2f m ⇒ **连成一体**（老版 142 m）"
			% [spacing, diam_max])
	t.lt(spacing, 12.0, "……绝对间距也压在 12 m 以内（实得 %.2f m）" % spacing)

	var col := v_max * p.lifetime
	t.lt(col, 900.0,
		"柱长 %.0f m < 900 m —— 老版 11374 m：相机根本看不完，而颗粒全撒在那空里" % col)
	t.gt(col, 200.0, "……但也不能短到看不出「一道烟」（实得 %.0f m > 200）" % col)
	t.gt(col, hz * 2.0,
		"柱长（%.0f m）必须**长于**盒长（%.0f m）—— 否则摊开还没铺满一簇就到头了"
			% [col, hz * 2.0])

	c.free()


# ============================================================ ⑪ 渲染抽稀（轮 41）

## ## 为什么要有这一节
##
## 轮 41 量到「编队战 14 台 + 36 发弹」是 127 ms/帧，`--no-ribbon` 只要 32 ms
## ⇒ 烟带每帧重建 512 段（≈3000 顶点、≈9000 次 RenderingServer 调用）× 36 条。
## 修法两步：① 重建从"每物理子步"搬到"每渲染帧"；② **远端按距离抽稀**。
##
## 这一步的风险是**用"变短"换"变快"** —— 抽稀一旦动到端点，拖尾就会短一截，
## 而"拖尾和弹道一样长"正是用户提这条需求的原话。所以这里必须把
## **不变量**钉死，而不是只测"段数变少了"。
##
## ## 三条不变量
##
##   ① 链首 = 第一个采样点、链尾 = 实时末端点 ⇒ **画出来的长度与折线全同**；
##   ② 严格递增 ⇒ 不会原地打转、不会产生零长段（零长段会被 `rebuild()` 跳过，
##      极端情况下整条带子一个顶点都没有 ⇒ `No vertices were added` 刷屏）；
##   ③ `cam == null` ⇒ **不抽稀**。无头测试与无相机场景因此逐位同改动前 ——
##      这条同时保证了"测试里看到的几何"就是"没优化时的几何"。
static func _ribbon_lod(t: T, host: Node) -> void:
	# ---- ① 步长档位（纯函数 = 唯一真源）----
	var near := MissileRibbon.LOD_NEAR_M
	var far := MissileRibbon.LOD_FAR_M
	t.eq(MissileRibbon._lod_stride(0.0), 1, "贴着相机：**每点都画**")
	t.eq(MissileRibbon._lod_stride(near), 1,
		"边界 %.0f m 取**闭**区间（这一侧不抽）" % near)
	t.eq(MissileRibbon._lod_stride(near + 1.0), 2, "刚过近界：每 2 取 1")
	t.eq(MissileRibbon._lod_stride(far), 2, "边界 %.0f m 仍算中档" % far)
	t.eq(MissileRibbon._lod_stride(far + 1.0), 4, "过远界：每 4 取 1")
	t.eq(MissileRibbon._lod_stride(1.0e9), 4, "再远也只有一档（别无限放大步长）")
	t.lt(MissileRibbon.LOD_NEAR_M, MissileRibbon.LOD_FAR_M, "近界必须小于远界")

	# ---- 造一条长带子（与第 ⑩ 节同一个口径：step 100 ⇒ 实际间隔 200 m）----
	var box := Node3D.new()
	box.name = "LodBox"
	host.add_child(box)
	var r := MissileRibbon.new()
	box.add_child(r)
	r.set_physics_process(false)
	var alt: float = ALT
	var tip := Vector3(0, alt, 0)
	r.push(tip, 1.0 / 60.0)
	for i in 201:
		tip += Vector3(0, 0, -100.0)
		r.push(tip, 1.0 / 60.0)
	var n := r._poly_count()
	var full_len := r.covered_m()
	t.gt(n, 100, "带子够长（%d 点）才谈得上抽稀" % n)

	# ---- ② 没有相机 ⇒ 不抽稀 ----
	var chain := r._render_chain(null)
	t.eq(chain.size(), n,
		"⚠️ **没有相机就不抽稀**（%d 点全画）—— 无头测试因此逐位同改动前" % chain.size())
	t.eq(chain[0], 0, "链首 = 第一个采样点")
	t.eq(chain[chain.size() - 1], n - 1, "链尾 = **实时末端点**")

	# ---- ③ 有相机 ⇒ 抽稀，但首尾仍在、长度一分不少 ----
	var cam := Camera3D.new()
	# 摆到 10 万米外：带子上每个点都落在"远档"⇒ 全场步长 4。
	cam.position = Vector3(0, alt + 100000.0, 0)
	var far_chain := r._render_chain(cam)
	t.lt(far_chain.size(), chain.size(),
		"远端抽稀生效：段数 %d → %d（**同一个长度**）"
			% [chain.size() - 1, far_chain.size() - 1])
	t.eq(far_chain[0], 0, "⚠️ 抽稀**不动链首** —— 动了就是「拖尾短一截」")
	t.eq(far_chain[far_chain.size() - 1], n - 1,
		"⚠️ 抽稀**不动链尾** —— 弹那一端还在，长度才守得住")
	var inc := true
	for k in range(1, far_chain.size()):
		if far_chain[k] <= far_chain[k - 1]:
			inc = false
	t.ok(inc, "链**严格递增**（步长至少 1，不会原地打转、不会有零长段）")
	t.near(r.covered_m(), full_len, 0.0001,
		"长度读数 %.1f m 与抽稀无关（`covered_m()` 量的始终是**真值**）" % r.covered_m())
	t.gt(far_chain.size(), 1, "再抽也要留下至少两段，否则整条消失")

	# ---- ④ 无相机路径下，画出的段数就是全部段数 ----
	# ⚠️ 只断言"抽稀只在有相机时发生"，**不断言具体段数**：
	# 段数是性能参数，钉死它会让以后调 `LOD_*` 时莫名其妙变红。
	r.rebuild()
	t.eq(r.drawn_segments(), n - 1,
		"无相机时 `drawn_segments()` == 折线段数（%d）" % (n - 1))

	box.queue_free()


# ============================================================ ⑩ 连续烟带（轮 40）

## ## 用户原话
##
## 「把浮游飞弹的飞行轨迹加长，现在的浮游飞弹的拖尾太短了，拖尾要和飞行轨迹一样长」。
##
## ## 为什么这一节必须存在（而不是只靠 `_density()`）
##
## `_density()` 守的是"**每颗粒子**排得够不够密"，它对"拖尾有多长"一无所知 ——
## 实测 12 km 交战时弹道 16651.7 m，而粒子柱（`柱长 = 弹速 × lifetime`）只有 650 m。
## 也就是说**旧守卫全绿、用户的抱怨依然成立**。长度这件事需要一条新判据。
##
## ## 这一节钉的七条，每条都对应一种"漏了也不报错"的失败方式
##
##   ① HIGH 档的弹**确实带着烟带**，且挂在**弹丸容器**上。挂在弹身上也"能用"，
##      但弹一命中就 `queue_free()`，那条铺了十几公里的烟会一起消失 ——
##      那正是用户看不到轨迹的原因。只有查**父节点身份**才抓得住。
##   ② LOW 档（全弹发射）**没有**烟带 —— 100 条 × 上百采样点会把顶点数推到六位数。
##   ③ 头端**贴住弹**：`covered_m()` 覆盖到推入的累计路程。只到"最后一个采样点"
##      的话，带子永远短一个采样间隔（120~177 m）。
##   ④ 采样点数**按距离**增长（不是每帧一点），且顶不穿 `MAX_POINTS`。
##   ⑤ `release()` 幂等，且调用后**不再收点**（形状冻结 —— 烟不跟着弹跑）。
##   ⑥ 材质是**普通 alpha**（`BLEND_MODE_MIX`）不是加色；这与 `_is_smoke()` 对粒子
##      那份的要求**同义**，不因为换了渲染方式就破例。
##   ⑦ **不带 `GPUParticles3D` 子节点** —— `_smoke_bursts()` 是按"容器级、非弹丸、
##      挂发射器"来数烟团的，烟带一旦挂上粒子就会被数成"多出来的烟团"，
##      于是"三发只放了三团烟"那条判据会莫名其妙变红。
static func _ribbon(t: T, host: Node) -> void:
	# ⚠️ HIGH / LOW 各用一个**独立容器**：烟带挂在容器上，两条弹同容器时无法从
	# 容器反查它属于哪条（设计上刻意不建立那条引用 —— 弹会先死，引用必悬空）。
	var ch := Node3D.new()
	ch.name = "RibbonHighBox"
	host.add_child(ch)
	var cl := Node3D.new()
	cl.name = "RibbonLowBox"
	host.add_child(cl)

	# ---- ①② 档位：有没有烟带、挂在谁身上 ----
	var hi := Missile.new()
	hi.trail_level = Missile.Trail.HIGH
	ch.add_child(hi)
	hi.global_position = Vector3(0, ALT, 0)
	var rh := _ribbon_of(hi)
	t.ok(rh != null, "HIGH 档的弹**带着**烟带 —— 长度整件靠它")
	if rh != null:
		t.ok(rh.get_parent() == ch,
			"⚠️ 烟带挂在**弹丸容器**上，不是弹自己（挂弹身上的话弹一命中它就一起没了）")
		t.ok(rh.get_parent() != hi, "……也就是说它**不是**弹的子节点")
		t.eq(rh.point_count(), 0, "刚建好时一个采样点都没有")
		t.near(rh.covered_m(), 0.0, 0.001, "……也就没有长度")

	var lo := Missile.new()
	lo.trail_level = Missile.Trail.LOW
	cl.add_child(lo)
	lo.global_position = Vector3(0, ALT, 0)
	t.ok(_ribbon_of(lo) == null,
		"LOW 档（全弹发射 100 发）**没有**烟带 —— 100 条 × 上百点会到六位数顶点")

	# 这两条真弹后面用不着了，而它们会自己跑 `_physics_process`（没有目标 ⇒ 徒增噪声）
	# ⇒ 关掉。⚠️ 只留烟带在树里，它的淡出靠 `_process`。
	hi.set_physics_process(false)
	lo.set_physics_process(false)

	if rh == null:
		ch.queue_free()
		cl.queue_free()
		return

	# ---- ③ 头端贴弹 ----
	# 取 step = 100：采样按"≥ 120 m 记一点"进行 ⇒ 实际间隔 200 m；推 **201** 次
	# ⇒ 路程 20100 m，最后一个采样点落在 20000 m、末尾留 **100 m 残余**。
	# 有实时末端点才补得上这 100 m —— 这正是本条要区分的东西。
	var step := 100.0
	var tip := Vector3(0, ALT, 0)
	rh.push(tip, 1.0 / 60.0)                       # 出生点
	var want := 0.0
	for i in 201:
		tip += Vector3(0, 0, -step)
		want += step
		rh.push(tip, 1.0 / 60.0)
	t.near(rh.covered_m(), want, 0.5,
		"推入 %.0f m ⇒ 实铺 %.0f m：**头端贴着弹**（不是只到最后一个采样点）"
			% [want, rh.covered_m()])
	t.gt(rh.point_count(), 90, "采样点在长（现 %d 个）" % rh.point_count())
	t.lt(rh.point_count(), 130,
		"202 次 push 只落了 %d 个点 ⇒ 按**距离**采样（每 ≥ %.0f m 一个），不是每帧一个"
			% [rh.point_count(), MissileRibbon.SPACING])

	# ---- ④ 上限：再推一大截，不许顶穿 ----
	var guard := MissileRibbon.MAX_POINTS
	for i in 1000:
		tip += Vector3(0, 0, -step)
		rh.push(tip, 1.0 / 60.0)
	t.eq(rh.point_count(), guard,
		"采样点顶到上限 %d 就不再增长（顶点数因此有上界）" % guard)

	# ---- ⑤ release()：幂等 + 不再收点 ----
	t.not_ok(rh.is_released(), "还没 `release()`")
	rh.release()
	t.ok(rh.is_released(), "`release()` 之后 `is_released()` 为真")
	rh.release()
	t.ok(rh.is_released(),
		"⚠️ `release()` **幂等** —— `_detonate()` 有两条 return 出口都会调它")
	var frozen := rh.point_count()
	var froze_len := rh.covered_m()
	rh.push(tip + Vector3(0, 0, -99999.0), 1.0 / 60.0)
	t.eq(rh.point_count(), frozen, "`release()` 之后**不再收点**（弹没了，形状冻结）")
	t.near(rh.covered_m(), froze_len, 0.001, "……长度也不再变（烟不跟着弹跑）")

	# ---- ⑥ 材质：普通 alpha，不是加色 ----
	var mat := rh.material_override as BaseMaterial3D
	t.ok(mat != null, "带子有材质（`material_override`）")
	if mat != null:
		t.eq(mat.blend_mode, BaseMaterial3D.BLEND_MODE_MIX,
			"普通 alpha 混合 —— 与粒子那份同一个「烟不是火」分界")
		t.not_ok(mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "**不是**加色")
		t.eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "走 alpha 透明")
		t.ok(mat.vertex_color_use_as_albedo,
			"顶点色当 albedo —— 头浓尾淡、边缘羽化都靠它，关了就成一块死色板")
		t.ok(mat.albedo_texture != null,
			"有横向羽化遮罩（一条纯色四边形读起来是**硬边塑料片**，不是烟）")
	t.ok(rh.top_level,
		"`top_level = true`：顶点是**世界坐标**，不继承机体位移/旋转")

	# ---- ⑦ 不许带粒子子节点（否则污染 `_smoke_bursts()` 的烟团计数）----
	var emitters := 0
	for k in rh.get_children():
		if k is GPUParticles3D:
			emitters += 1
	t.eq(emitters, 0,
		"⚠️ 烟带**不带** `GPUParticles3D` 子节点 —— 带了会被 `_smoke_bursts()`"
		+ " 数成「多出来的烟团」，让「三发放三团烟」那条判据莫名其妙变红")

	# ---- 淡出后自毁（`_process` 驱动，所以弹死了它也能自己走完）----
	var budget := MissileRibbon.FADE_TIME * 2.0 + 0.6
	var waited := 0.0
	while is_instance_valid(rh) and waited < budget:
		await host.get_tree().process_frame
		waited += host.get_process_delta_time()
	t.not_ok(is_instance_valid(rh),
		"`release()` 后 %.1f s 内淡完并自毁（给了 `FADE_TIME` %.1f s 的两倍余量）"
			% [budget, MissileRibbon.FADE_TIME])

	ch.queue_free()
	cl.queue_free()


# ============================================================ ⑫ 近距离淡出（★63-21）

## ## 用户原话（两段，第二段才是关键）
##   「离镜头越近，透明度就越高，离镜头只有 3 m 的时候透明度彻底 100%」
##   「是镜头内的**部分**透明哦，不是整条透明」
##
## ## 这一节钉的是**接线**，不是"好不好看"
## 引擎的公式 `alpha = clamp((d − min)/(max − min), 0, 1)` 与"逐片元"这两件事
## 已经由真机探针（`tools/_r63_21_fade_probe.tscn`，十个距离 × 三族物体）实测坐实；
## 这里钉的是**产品有没有把它接对**。
##
## ## 四条都是"漏了也不报错"的失败方式
##   ① 模式没设 ⇒ 仍是 `DISABLED` ⇒ 一切照旧、**没有任何报错**；
##   ② 两个锚点**反着给** ⇒ 实测是"远处全没"，比不做还糟（那正是"整条透明"那一路）；
##   ③ 用了 `OBJECT_DITHER`（按对象）⇒ 整条带子一起变 ⇒ 用户明确否掉的那一种；
##   ④ 顺手加到 `_soft_smoke_mat()`（尾气 / 烟团 / 黑烟共用）⇒ 改到了用户没让改的东西。
static func _near_fade(t: T) -> void:
	var near: float = MissileRibbon.FADE_NEAR_M
	var full: float = MissileRibbon.FADE_FULL_M

	# ---- ① 两个锚点 ----
	t.eq(near, 3.0, "近端锚点 = 3 m（需求原话里那个数）")
	t.eq(full, 60.0, "远端锚点 = 60 m（≥ 此值画面与改动前逐位一致）")
	t.lt(near, full,
		"⚠️ **近端必须小于远端** —— 反着给实测得到的是「远处全没」，不是「近处淡」")

	# ---- ② 烟带层：接上了，而且逐片元 ----
	var rib := MissileRibbon._shared_mat()
	t.ok(rib != null, "烟带材质建得出来")
	if rib != null:
		t.eq(rib.distance_fade_mode, BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA,
			"烟带走**逐片元**距离淡出 —— 16 km 的带子上近处淡、远处照旧")
		t.not_ok(rib.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED,
			"⚠️ 没设的话就是 `DISABLED` ⇒ **不报错、不红、什么也没发生**")
		t.not_ok(rib.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_OBJECT_DITHER,
			"⚠️ **不是**按对象 —— 按对象就是「整条透明」，用户明确否掉的那一种")
		t.eq(rib.distance_fade_min_distance, near, "烟带：近端锚点")
		t.eq(rib.distance_fade_max_distance, full, "烟带：远端锚点")

	# ---- ③ 粒子层：与烟带共用同一条斜坡 ----
	var trail := FX._trail_smoke_mat()
	t.ok(trail != null, "尾迹粒子材质建得出来")
	if trail != null:
		t.eq(trail.distance_fade_mode, BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA,
			"粒子层同样逐片元（一柱粒子铺开几百米 ⇒ 近处那几颗淡、远处那几颗照旧）")
		t.eq(trail.distance_fade_min_distance, near, "粒子层近端锚点 —— 与烟带同一处真源")
		t.eq(trail.distance_fade_max_distance, full, "粒子层远端锚点 —— 与烟带同一处真源")

	# ---- ④ 范围守卫：别顺手改到别的烟上 ----
	var soft := FX._soft_smoke_mat()
	t.ok(soft != null, "共用烟材质建得出来")
	if soft != null:
		t.eq(soft.distance_fade_mode, BaseMaterial3D.DISTANCE_FADE_DISABLED,
			"⚠️ 尾气 / 一次性烟团 / 受损黑烟走的 `_soft_smoke_mat()` **没被动**"
			+ "（用户要的是导弹尾迹；顺手改过去 = 改了没让改的东西）")

	# ---- ⑤ 它是**外加**的乘子；且远端锚点必须远在带子之外 ----
	t.gt(MissileRibbon.ALPHA, 0.0, "`ALPHA` 仍在（距离淡出是外加乘子，不是拿它去换）")
	# ⚠️ 若远端锚点落到带子尺度上（全宽 12 m），整条带子平时就都落在斜坡里
	# ⇒ 退化成"整条一起淡"，正是用户否掉的那一种。
	var band_w: float = MissileRibbon.HALF_W * 2.0
	var msg := "远端锚点 %.1f m 必须远大于带子全宽 %.1f m" % [MissileRibbon.FADE_FULL_M, band_w]
	t.gt(MissileRibbon.FADE_FULL_M, band_w,
		msg + " —— 否则整条带子都在斜坡里，就成「整条透明」了")
