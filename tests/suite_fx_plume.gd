class_name SuiteFxPlume
extends RefCounted

static func _jet_core(t: T, host: Node) -> void:
	var stage := Node3D.new()
	host.add_child(stage)
	var jet := FX.afterburner(stage, Vector3.ZERO, Vector3.DOWN, 2.0)
	var core := jet.get_node("JetEnvelope") as MeshInstance3D
	t.not_ok(core.visible, "unlit nozzle has no persistent flame")
	jet.emitting = true
	await host.get_tree().create_timer(0.2).timeout
	t.ok(core.visible, "continuous core ignites with particles")
	t.near(core.basis.y.dot(Vector3.DOWN),1.0,0.001,"core follows angled nozzle axis")
	jet.emitting = false
	await host.get_tree().create_timer(0.2).timeout
	t.not_ok(core.visible, "core extinguishes after thrust ends")
	jet.emitting = true
	await host.get_tree().create_timer(0.2).timeout
	t.ok(core.visible, "core can reignite")
	stage.queue_free()
	await host.get_tree().process_frame
## **尾焰形态与特效细节**（2026-09-25 · 用户要求）。
##
## ## 需求原话
##
## > "所有的特效都优化 / 烟雾粒子特效，尾焰粒子特效等等 / 细节更加丰富优化 /
## >  尾焰在正常加速的时候和辅助驾驶模式时候冲刺的尾焰形态不同，要做区分"
##
## ## 这一套在测什么（以及为什么这样测）
##
## "两种形态要区分"这句话，中心词是**形态**。所以判据**不能**是"某个常量等于某个值"，
## 而必须是**两个发射器在运行期的可观测量真的分开了**：锥角、尺寸随龄的方向
##（膨胀 vs 收束）、是否沿速度拉丝、材质是不是 billboard、初速与寿命的量级。
## 这几条一旦被改回同一种读数，"两种形态"就在屏幕上消失 —— 而那时必须有人喊出来。
##
## 第六节测烟的**层次**（随龄膨胀、烟团两层、余烬不比主烟活得久），
## 第七节测**收口时机**（加了子层之后 root 的 free 不能提前）。
##
## ## 十三节
##   ① `_curve()` 不被 `Curve.max_value` 静默钳制（历史坑）
##   ② 尾焰两种形态的可观测差异（逐条对照）
##   ③ 冲刺马赫环：扩张 / 垂直 / 恒定节拍
##   ④ 机体真的按状态二选一（真路径，跑物理帧）—— **空喷口表**那一支（机尾单点）
##   ⑤ 冲刺的起跑包络（`amount_ratio` 两档）
##   ⑥ 烟雾：随龄膨胀 + 烟团的两层结构
##   ⑦ 收口时机（加了子层之后 free 不能提前）
##   ⑧ 喷口族的**坐标系归属**（尾焰/冲刺焰/马赫环在机体局部空间，烟在世界空间）
##   ⑨ **粒子密度**（轮 15：抬了一档 + 三处有意不动）
##   ⑩ **多喷口的形状层**（2026-09-25 起两形逐口铺开；2026-09-27 柯西 2 → 4 个口）
##   ⑪ **三台机体的尾焰颜色要拉开**（黄 / 紫 / 蓝）
##   ⑫ **冲刺方向的尾焰形变**（轮 17：横风把焰吹弯，顺飞仍然直）
##   ⑬ **喷口的开口朝向**（轮 18：佩涅罗佩那两个口朝下外方，不能再写死 +Z）

const ALT := 3000.0


static func run(t: T, host: Node) -> void:
	t.suite("FxPlume / continuous jet ignition and extinction")
	await _jet_core(t, host)
	t.suite("FxPlume / _curve 不被 max_value 静默钳制")
	_curve_guard(t)
	t.suite("FxPlume / 尾焰两种形态的可观测差异")
	_two_forms(t, host)
	t.suite("FxPlume / 冲刺马赫环")
	_rings(t, host)
	t.suite("FxPlume / 机体按状态二选一（真路径）")
	await _switching(t, host)
	t.suite("FxPlume / 冲刺的起跑包络")
	# ⚠️ 必须 `await`：`_envelope()` 里有 `await physics_frame`，它是个**协程**。
	# 漏掉 await 不会报错 —— 协程会照跑，只是它的断言在**后面某一节**的标题下才恢复执行，
	# 于是这一节显示 0 条、而别的节凭空多出几条。实测踩过：本节 0 条，
	# 那 5 条全被记进第七节（收口时机 8 = 2 + 5 + 1）。**节标题必须等于它实际测的东西。**
	await _envelope(t, host)
	t.suite("FxPlume / 烟雾的层次")
	_smoke(t, host)
	t.suite("FxPlume / 收口时机")
	await _cleanup(t, host)
	t.suite("FxPlume / 喷口族的坐标系（跟着机体走）")
	_nozzle_space(t, host)
	t.suite("FxPlume / 粒子密度（抬了一档）")
	_density(t, host)
	t.suite("FxPlume / 多喷口的形状层（柯西 4 个口 / 佩涅罗佩 2 个口）")
	await _multi_nozzle(t, host)
	t.suite("FxPlume / 三台机体的尾焰颜色（黄 / 紫 / 蓝）")
	_plume_colors(t)
	t.suite("FxPlume / 冲刺方向的尾焰形变（横风）")
	await _bend(t, host)
	t.suite("FxPlume / 喷口的开口朝向（佩涅罗佩那两个口朝下外方）")
	await _nozzle_dir(t, host)


# ============================================================ 工具

static func _stage(host: Node) -> Node3D:
	var n := Node3D.new()
	n.name = "FxStage"
	host.add_child(n)
	return n


static func _count(parent: Node, key: String) -> int:
	var n := 0
	for ch: Node in parent.get_children():
		if String(ch.name).contains(key):
			n += 1
	return n


static func _unit(container: Node3D, pos: Vector3, suit: SuitProfile = null) -> FlightBody:
	var u := FlightBody.new()
	u.team = 0
	u.is_player = true
	u.profile = suit if suit != null else SuitProfile.xi()
	u.display_name = "FxProbe"
	u.projectile_container = container
	container.add_child(u)
	u.global_position = pos
	u.max_hp = 400.0
	u.hp = 400.0
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	return u


## 一台**没有多喷口**的机体（把柯西档案里的喷口表清掉）。
##
## ⚠️ 第四、五节测的是"**机尾单点那一套**形状层"（`_afterburner_fx` / `_dash_fx` /
## `_dash_rings`），那是 `engine_plumes` **为空**时才走的分支。
## 2026-09-25 柯西接上背包喷口之后，默认档案不再是空表 ⇒ 那两节必须显式要一台空表的机，
## 否则它们测的就变成了"多喷口分支"，而机尾那一套会**因为退场而全红**
##（本次改动实测：4 条红，全是"形态 A/B/环该亮却没亮"）。
## 反过来也说明：**这两节原来一直在测机尾那一套，措辞没变、被测对象悄悄变了** ——
## 所以"改档案"必须连着看"哪些测试拿它当默认"。
static func _plain_unit(container: Node3D, pos: Vector3) -> FlightBody:
	var p := SuitProfile.xi()
	p.engine_plumes = [] as Array[Vector3]
	return _unit(container, pos, p)


# ============================================================ ① 曲线钳制

## `Curve` 默认 `max_value = 1.0`，超过 1 的点会被**静默钳制**。
##
## 这是首轮给导弹尾迹做"随龄扩散到 1.3"时踩到的：代码里 `add_point(1.0, 1.30)` 写得
## 明明白白，运行时 `sample(1.0)` 读回 **1.0**，整条曲线被压平 —— 不报错、不红任何断言，
## 只是"越飘越大"这件事**根本没发生**。所以 `_curve()` 把上限统一抬到 2.5，
## 而这里就是钉住它的那道门。
static func _curve_guard(t: T) -> void:
	var ct := FX._curve([Vector2(0.0, 0.6), Vector2(1.0, 1.6)])
	var c := ct.curve
	t.near(c.sample(1.0), 1.6, 0.02,
		"终值 1.6 真的读得回来（没有被钳到 max_value）")
	t.near(c.sample(0.0), 0.6, 0.02, "起点 0.6 也在")
	t.gt(c.max_value, 2.0, "max_value 被抬到 %.1f（留出余量给“膨胀”类曲线）" % c.max_value)


# ============================================================ ② 两种形态

static func _two_forms(t: T, host: Node) -> void:
	var st := _stage(host)
	var a := FX.afterburner(st, Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var b := FX.afterburner_dash(st, Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var pa := a.process_material as ParticleProcessMaterial
	var pb := b.process_material as ParticleProcessMaterial
	t.ok(pa != null and pb != null, "两个发射器都有 process_material")
	if pa == null or pb == null:
		st.queue_free()
		return

	# ---- 锥角：一团 vs 一条 ----
	t.near(pb.spread, pa.spread, 0.001,
		"两种尾焰都不随机散射（%.1f° / %.1f°），长度仍区分两种形态" % [pb.spread, pa.spread])
	t.lt(pb.spread, 4.0, "……而且是“几乎不收口的一条”（%.1f° < 4°）" % pb.spread)

	# ---- 初速 / 寿命：被弹出去 vs 慢慢推出去 ----
	t.gt(pb.initial_velocity_min, pa.initial_velocity_max,
		"冲刺焰的**最低**初速都高过巡航焰的最高初速（%.0f > %.0f）" % [
			pb.initial_velocity_min, pa.initial_velocity_max])
	t.lt(b.lifetime, a.lifetime,
		"冲刺焰寿命更短（%.2f s < %.2f s）：喷出去就没了" % [b.lifetime, a.lifetime])

	# ---- 尺寸随龄的方向：**这一条是两种形态最本质的差别** ----
	var ca := (pa.scale_curve as CurveTexture).curve
	var cb := (pb.scale_curve as CurveTexture).curve
	t.ok(ca != null and cb != null, "两形都设了 scale_curve（形态靠它区分）")
	if ca != null and cb != null:
		t.gt(ca.sample(1.0), ca.sample(0.0),
			"巡航焰**越飞越散**（%.2f → %.2f）" % [ca.sample(0.0), ca.sample(1.0)])
		t.lt(cb.sample(1.0), cb.sample(0.0),
			"冲刺焰**越飞越细**（%.2f → %.2f）" % [cb.sample(0.0), cb.sample(1.0)])

	# ---- 沿速度拉丝：只属于形态 B ----
	t.ok(pb.particle_flag_align_y, "冲刺焰沿速度拉成丝（align_y）")
	t.not_ok(pa.particle_flag_align_y, "巡航焰**不**拉丝（是一颗颗圆团）")

	# ---- 而要让 align_y 生效，材质**不能是 billboard** ----
	# Godot 的 billboard 在顶点着色器里根据相机重建基，会把粒子自身的旋转整个覆盖掉 ——
	# 也就是说"沿速度拉成一丝"在 billboard 材质上**从原理上做不到**。实测踩过。
	var ma := (a.draw_pass_1 as SphereMesh).material as ShaderMaterial
	var mb := (b.draw_pass_1 as SphereMesh).material as ShaderMaterial
	t.eq(ma.get_shader_parameter("billboard"), true,
		"巡航焰用 billboard（从任何角度看都是圆团）")
	t.ok(not bool(mb.get_shader_parameter("billboard")),
		"冲刺焰**不能**用 billboard，否则 align_y 会被顶点着色器覆盖（实测踩过）")

	# ---- 椭球细长比：B 更细 ----
	var sa := a.draw_pass_1 as SphereMesh
	var sb := b.draw_pass_1 as SphereMesh
	var ra := sa.height / maxf(sa.radius, 0.001)
	var rb := sb.height / maxf(sb.radius, 0.001)
	t.gt(rb, ra * 1.8,
		"冲刺焰的椭球更细长（%.1f:1 vs %.1f:1）" % [rb, ra])

	# ---- 色温：B 更白（"炽白"而不是"蓝白"）----
	t.gt(pb.color_ramp.gradient.sample(0.0).r, pa.color_ramp.gradient.sample(0.0).r,
		"冲刺焰的核心更白（R %.2f > %.2f）" % [
			pb.color_ramp.gradient.sample(0.0).r, pa.color_ramp.gradient.sample(0.0).r])
	st.queue_free()


# ============================================================ ③ 马赫环

static func _rings(t: T, host: Node) -> void:
	var st := _stage(host)
	var r := FX.dash_rings(st, Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var pm := r.process_material as ParticleProcessMaterial
	t.eq(pm.spread, 0.0, "环沿束方向直着走（锥角 0°）")
	t.ok(pm.particle_flag_align_y, "盘面垂直于束（轴对齐速度）—— 少了这行环会**侧躺**在束上")

	var c := (pm.scale_curve as CurveTexture).curve
	t.gt(c.sample(1.0), c.sample(0.0),
		"环随龄**扩张**（%.2f → %.2f）：激波面在扩散，这就是“钻石”的观感来源" % [
			c.sample(0.0), c.sample(1.0)])

	# 节拍：不手写位置，靠 `lifetime / amount` 的天然间隔。
	var gap := pm.initial_velocity_min * (r.lifetime / float(r.amount))
	t.between(gap, 5.0, 30.0,
		"相邻环的间距 ~%.1f m（太密糊成一道光，太疏读不出“串”）" % gap)

	var mesh := r.draw_pass_1 as CylinderMesh
	t.ok(mesh != null, "环用的是圆柱薄盘")
	if mesh != null:
		t.lt(mesh.height, mesh.top_radius * 0.2,
			"盘厚 %.3f << 半径 %.1f：是一“圈”而不是一“饼”" % [mesh.height, mesh.top_radius])
	st.queue_free()


# ============================================================ ④ 形态二选一（真路径）

static func _switching(t: T, host: Node) -> void:
	var c := Node3D.new()
	host.add_child(c)
	c.global_position = Vector3(0, ALT, 0)
	# ⚠️ **必须用空喷口表的机体**：本节测的是机尾那一套单点形状层，
	# 而柯西 2026-09-25 起有了背包喷口 ⇒ 机尾那一套会**按设计退场**，本节全红。
	var u := _plain_unit(c, Vector3(0, ALT, 0))
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame

	var ab := u.get("_afterburner_fx") as GPUParticles3D
	var dash := u.get("_dash_fx") as GPUParticles3D
	var rings := u.get("_dash_rings") as GPUParticles3D
	t.ok(ab != null and dash != null and rings != null,
		"机体上三种节点都建出来了（巡航焰 / 冲刺焰 / 马赫环）")
	if ab == null or dash == null or rings == null:
		c.queue_free()
		return

	# 同点：三者指的是**同一个喷口**。
	t.near(dash.position.distance_to(ab.position), 0.0, 0.001,
		"冲刺焰与巡航焰同点（同一个喷口，不是两簇火从不同地方喷）")
	t.near(rings.position.distance_to(ab.position), 0.0, 0.001, "马赫环也同点")

	# ---- ① 普通加力（不辅助）→ 形态 A ----
	u.translate_mode = false
	u.translate_dash = false
	u.fm.super_boost = false
	u.fm.boosting = true
	await host.get_tree().physics_frame
	t.ok(ab.emitting, "普通加力 → 形态 A（巡航焰）亮")
	t.not_ok(dash.emitting, "……形态 B 灭")
	t.not_ok(rings.emitting, "……马赫环也灭")

	# ---- ② 辅助闪避冲刺 → 形态 B ----
	# ⚠️ 必须同时把 `_qb_timer` 顶起来：`_apply_translate` 每帧用
	# `translate_dash = _qb_timer > 0` **重算**这个字段，只手写 `translate_dash`
	# 会被下一帧物理抹掉（症状：断言看到的是"从没冲过刺"）。
	u.translate_mode = true
	u.set("_qb_timer", 0.40)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	t.ok(u.translate_dash, "（前置）闪避冲刺窗口真的开着")
	t.not_ok(ab.emitting, "辅助冲刺 → 形态 A 灭")
	t.ok(dash.emitting, "……形态 B 亮")
	t.ok(rings.emitting, "……马赫环亮（与束同开同关）")

	# ---- ③ 超级加速 → 也走形态 B ----
	u.translate_mode = false
	u.translate_dash = false
	u.fm.super_boost = true
	u.fm.boosting = true
	await host.get_tree().physics_frame
	t.ok(dash.emitting, "超级加速 → 也走形态 B")
	t.not_ok(ab.emitting, "……形态 A 仍然灭")

	# ---- ④ 不在冲刺 → 两者都灭 ----
	u.fm.super_boost = false
	u.fm.boosting = false
	await host.get_tree().physics_frame
	t.not_ok(ab.emitting, "不加速、不冲刺 → 形态 A 灭")
	t.not_ok(dash.emitting, "……形态 B 也灭")
	t.not_ok(rings.emitting, "……环也灭")

	# ---- ⑤ `is_dashing()` 与内部判断必须一致（速度线读的是它）----
	u.translate_mode = true
	u.set("_qb_timer", 0.40)
	await host.get_tree().physics_frame
	t.ok(u.is_dashing(), "`is_dashing()` 在辅助冲刺时为真（屏幕速度线读它）")
	u.translate_mode = false
	u.set("_qb_timer", 0.0)
	u.translate_dash = false
	await host.get_tree().physics_frame
	t.not_ok(u.is_dashing(), "……不冲刺时为假")
	c.queue_free()


# ============================================================ ⑤ 起跑包络

static func _envelope(t: T, host: Node) -> void:
	var c := Node3D.new()
	host.add_child(c)
	c.global_position = Vector3(0, ALT, 0)
	# 同上：起跑包络挂在机尾那一条 `_dash_fx` 上，要一台空喷口表的机体。
	var u := _plain_unit(c, Vector3(0, ALT, 0))
	await host.get_tree().physics_frame
	var d := u.get("_dash_fx") as GPUParticles3D
	t.ok(d != null, "冲刺焰节点建出来了")
	if d == null:
		c.queue_free()
		return

	# 直接驱动一帧 `_tick_effects`（不走物理帧）：这样 `_qb_timer` 不会被
	# `_apply_translate` 的每帧递减改掉，两档读数才是同一份输入下的结果。
	u.translate_mode = true
	u.translate_dash = true
	u.fm.boosting = true
	u.set("_qb_timer", FlightBody.QB_TIME)
	u.call("_tick_effects", 0.016)
	t.near(d.amount_ratio, 1.0, 0.001,
		"爆冲段（窗口头 %.2f s）焰量拉满" % FlightBody.QB_BURST_TIME)
	t.gt(d.speed_scale, 1.0, "……而且粒子飞得更快（speed_scale %.2f）" % d.speed_scale)

	u.set("_qb_timer", 0.10)
	u.call("_tick_effects", 0.016)
	t.near(d.amount_ratio, 0.6, 0.001, "窗口尾段回落到 0.6 档（起跑那一记最狠）")
	t.near(d.speed_scale, 1.0, 0.001, "……速度也回落")
	c.queue_free()


# ============================================================ ⑥ 烟雾层次

static func _smoke(t: T, host: Node) -> void:
	var st := _stage(host)

	# ---- 尾气烟：随龄膨胀 ----
	var ex := FX.exhaust_smoke(st, Vector3.ZERO, Vector3(0, 0, 1), 1.4)
	var pe := ex.process_material as ParticleProcessMaterial
	t.not_ok(pe.turbulence_enabled, "喷口薄雾关闭乱流，避免扭动烟丝")
	var ce := (pe.scale_curve as CurveTexture).curve
	t.gt(ce.sample(1.0), ce.sample(0.0),
		"尾气**随龄膨胀**（%.2f → %.2f）：离开喷口之后会散开" % [ce.sample(0.0), ce.sample(1.0)])

	# ---- 受损烟：随龄膨胀 ----
	var dmg := FX.damage_smoke(st, Vector3.ZERO, 1.0)
	var pd := dmg.process_material as ParticleProcessMaterial
	var cd := (pd.scale_curve as CurveTexture).curve
	t.gt(cd.sample(1.0), cd.sample(0.0), "受损黑烟也随龄膨胀")

	# ---- 导弹尾迹：粒子数没变（预算红线），但多了乱流 ----
	var tr := FX.missile_trail(st, 0.5)
	var pt := tr.process_material as ParticleProcessMaterial
	t.eq(tr.amount, FX.TRAIL_HIGH_AMOUNT, "尾迹粒子数仍是 HIGH 档（预算红线不许动）")
	t.ok(pt.turbulence_enabled, "……同时加了乱流（气流一路在搅它）")
	var ct := (pt.scale_curve as CurveTexture).curve
	t.near(ct.sample(1.0), 1.30, 0.02,
		"……而且“终止 1.30”这次**真的生效**了（`_curve()` 抬过 max_value）")

	# ---- 烟团：两层结构 ----
	var burst := FX.smoke_burst(st, Vector3(0, 10, 0), 1.0, 2.0)
	var emitters: Array = []
	for ch in burst.get_children():
		if ch is GPUParticles3D:
			emitters.append(ch)
	t.eq(emitters.size(), 2, "烟团是**两层**：主烟 + 余烬（%d 个发射器）" % emitters.size())
	if emitters.size() == 2:
		var main_p := emitters[0] as GPUParticles3D
		var ember_p := emitters[1] as GPUParticles3D
		# ⚠️ 顺序是**接口**：`suite_missile_smoke._burst_emitter()` 取根节点下第一个
		# `GPUParticles3D` 的 `amount` 去核弹射烟团的粒子数 —— 余烬插到前面，
		# 那条断言就会读到余烬的量，症状看起来像"弹射烟团变小了"。
		t.ok(not String(main_p.name).contains("Ember"),
			"**主烟在第一个**（`_burst_emitter()` 的顺序契约）")
		t.eq(String(ember_p.name), "SmokeEmbers", "第二层是余烬")
		t.gt(main_p.amount, ember_p.amount, "主烟的量远大于余烬（%d > %d）" % [
			main_p.amount, ember_p.amount])
		t.ok(ember_p.lifetime <= main_p.lifetime,
			"余烬不比主烟活得久（%.2f <= %.2f s）—— 否则会被 root 的 free 腰斩" % [
				ember_p.lifetime, main_p.lifetime])
		t.ok(main_p.one_shot and ember_p.one_shot, "两层都是 one_shot（一次性烟团）")

		# 材质分工：主烟是"烟"（普通 alpha、不自发光），余烬是"火"（加色）。
		var mmat := (main_p.draw_pass_1 as SphereMesh).material as StandardMaterial3D
		var emat := (ember_p.draw_pass_1 as SphereMesh).material as StandardMaterial3D
		t.eq(mmat.blend_mode, BaseMaterial3D.BLEND_MODE_MIX,
			"主烟是普通 alpha 混合（越叠越暗）")
		t.not_ok(mmat.emission_enabled, "……而且不自发光（一自发光就变回“火”）")
		t.eq(emat.blend_mode, BaseMaterial3D.BLEND_MODE_ADD, "余烬是加色混合（是火星）")
		t.ok(ember_p.process_material.particle_flag_align_y, "余烬也拉丝")
	st.queue_free()


# ============================================================ ⑦ 收口时机

## 给一个特效加了子层之后，**最先要重算的就是 root 的 free 时机** ——
## 原先挂在"最短的那一层"上是够的，加了更长的一层就会把它腰斩，
## 而症状是"明明加了特效却看不见"，最难查。
static func _cleanup(t: T, host: Node) -> void:
	var before := _count(host, "ImpactFlash")
	FX.impact_flash(host, Vector3(0, ALT, 0), Color(1, 0.8, 0.9))
	t.eq(_count(host, "ImpactFlash") - before, 1, "命中白闪挂上了根节点")
	var kids := 0
	for ch: Node in host.get_children():
		if String(ch.name).contains("ImpactFlash"):
			kids = ch.get_child_count()
	t.gt(float(kids), 3.0,
		"……而且根节点下不止原来的 1 层（%d 个子节点：白闪 + 环 + 火星 + 光）" % kids)

	# ⚠️ 按**真实时间**等，不按帧数：无头环境的帧率不可控（实测 30 个 process 帧
	# 只有 ~0.2 s）。按帧数等会在 headless 下**假红**，而那是量具的问题不是特效的问题。
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 900:
		await host.get_tree().process_frame
	t.eq(_count(host, "ImpactFlash"), before,
		"……而且按时收口（环与火星都没被腰斩成残节点）")


# ============================================================ ⑧ 坐标系归属

## 「尾焰跟不上机体速度」（2026-09-25 用户报告）的**可回归判据**。
##
## ## 病根不是参数，是**坐标系归属**
## `local_coords = false` 时粒子出生就钉在世界坐标上，而喷口以机体速度整体平移 ⇒
## 本该"贴在喷口上的一团火"被抹成 **600~700 m 长的稀薄虚线**；相机跟随机体
## ⇒ 屏幕上就是"尾焰被甩在后面"。实测：形态 A 自身只有 ~5 m，而机体 0.30 s 走 724 m。
##
## ## 为什么判据里要有那个**比值**
## 只断言 `local_coords == true` 是**接线级**判据：改回 false 会红一次，但它**说不出
## 为什么必须是 true** —— 下一个人（或下一轮把机体再提速的人）看到的只是一个"魔法开关"。
## 所以这里同时钉住那个比值：**机体在一个 lifetime 内走的距离 ÷ 该效应的自身行程 > 10**
## ⇒ 世界坐标下必然被拉长一个数量级以上。机体越快，这条越成立（比值单调涨）。
static func _nozzle_space(t: T, host: Node) -> void:
	var st := _stage(host)
	var a := FX.afterburner(st, Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var b := FX.afterburner_dash(st, Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var rings := FX.dash_rings(st, Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var smoke := FX.exhaust_smoke(st, Vector3.ZERO, Vector3(0, 0, 1), 1.4)

	# ---- ① 喷口族三个都在**机体局部空间**（同点、同向、同生共死的一族）----
	t.ok(a.local_coords, "形态 A 尾焰在机体局部空间（跟随机体，不被甩掉）")
	t.ok(b.local_coords, "形态 B 冲刺焰在机体局部空间")
	t.ok(rings.local_coords, "马赫环在机体局部空间（它是束的分段标记）")

	# ---- ② 而"烟"必须**留在世界空间** —— 否则就不是"一道尾迹"了 ----
	t.ok(smoke.local_coords, "喷口薄雾跟随，保留弧形尾焰而不拉出长烟丝")

	# ---- ③ 为什么必须这样：机体一个 lifetime 走的距离 vs 效应自身行程 ----
	# 取**最快**的形态（阿利宙斯巡航）—— 比值在它身上最小仍要 > 10 才算安全。
	var fastest: float = maxf(SuitProfile.xi().player_boost_speed(),
		maxf(SuitProfile.penelope().player_boost_speed(),
			SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).player_boost_speed()))
	var rows: Array = [[a, "形态 A 尾焰"], [b, "形态 B 冲刺焰"], [rings, "马赫环"]]
	for row: Array in rows:
		var em := row[0] as GPUParticles3D
		var own := _own_travel(em)
		var ship := fastest * em.lifetime
		t.gt(ship / maxf(own, 0.001), 10.0,
			"%s：机体一个 lifetime（%.2f s）走 %.0f m，是它自身行程 %.1f m 的 %.0f 倍 ⇒ 世界坐标下必被拉长一个数量级"
			% [row[1], em.lifetime, ship, own, ship / maxf(own, 0.001)])
	print("[R14] 喷口族 / 最快机体 %.0f m/s：它在尾焰寿命 %.2f s 内走 %.0f m，而三个效应的自身行程只有 尾焰 %.1f / 束 %.1f / 环 %.1f m ⇒ 用世界坐标会被抹成 %.0f / %.0f / %.0f 倍长"
		% [fastest, a.lifetime, fastest * a.lifetime,
			_own_travel(a), _own_travel(b), _own_travel(rings),
			fastest * a.lifetime / _own_travel(a),
			fastest * b.lifetime / _own_travel(b),
			fastest * rings.lifetime / _own_travel(rings)])
	st.queue_free()


## 一个发射器"自己飞多远"（米）：`v₀` 沿初速方向能走的距离。
##
## ⚠️ 阻尼不为 0 时**不能**用 `v₀ × lifetime`：Godot 的 `damping` 是随龄的速度衰减，
## 带阻尼的粒子走不到那么远（实测形态 B 的束长按 `1.8·v₀/damping` 算才是屏幕上那一条）。
## 所以这里与 `FX` 函数头用的是同一个经验式；无阻尼时才退回 `v₀ × lifetime`。
static func _own_travel(p: GPUParticles3D) -> float:
	var pm := p.process_material as ParticleProcessMaterial
	if pm == null:
		return 0.0
	var v0 := (pm.initial_velocity_min + pm.initial_velocity_max) * 0.5
	var damp := (pm.damping_min + pm.damping_max) * 0.5
	if damp > 0.001:
		return 1.8 * v0 / damp
	return v0 * p.lifetime


## 粒子**密度**（轮 15：用户「粒子特效数量太少了」）。
##
## ## 判据的两条腿
## ① **现在是新值** —— 接线级：改了字面量/常量，有没有真的到发射器上。
## ② **相对改前抬了 1.6~2.1 倍** —— "抬了一档"而不是"随手改了个数"。
##    只断①的话，下一个人把它改回 24 也是绿的（只要有个人同步改测试）。
##
## ## 为什么还要断"有意不动"的那几处
## 本轮的改动是"统一抬密度"，最容易越界的就是**把有别的约束的地方一起抬了**。
## 每一处不动的都有比"好看"更硬的理由，所以它们必须**原样**：
##   · `dash_rings.amount` —— 它不是密度，是**节拍**（环间距 = `v·lifetime/amount`）。
##     抬它 = 环变密 = 改"马赫环的射程配套"（§③ 在核那条，两条会一起红）。
##   · `missile_trail` HIGH/LOW —— **性能红线**（100 发全弹发射走 LOW 档）。
##     这里只核"预算没被吃掉"，数额本身归 `suite_missile_smoke._budget()`。
static func _density(t: T, host: Node) -> void:
	# ---- ①+② 逐个数：每行 = [名字, 发射器, 新值, 改前] ----
	var ab := FX.afterburner(_stage(host), Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var dash := FX.afterburner_dash(_stage(host), Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var smoke := FX.exhaust_smoke(_stage(host), Vector3.ZERO, Vector3(0, 0, 1), 1.4)
	var dmg := FX.damage_smoke(_stage(host), Vector3.ZERO, 1.0)

	var rows: Array = [[ab, "尾焰形态 A", 80, 40], [dash, "尾焰形态 B（冲刺束）", 200, 110],
		[smoke, "尾气（暗色烟）", 20, 10], [dmg, "受损黑烟", 88, 48]]

	# 一次性的爆/溅：它们返回的是**根节点**，粒子在下面某一层。
	var g1 := _stage(host)
	FX.hit_spark(g1, Vector3.ZERO)
	var g2 := _stage(host)
	FX.beam_impact(g2, Vector3.ZERO)
	var g3 := _stage(host)
	FX.explosion(g3, Vector3.ZERO)
	var g4 := _stage(host)
	FX.clash_shockwave(g4, Vector3.ZERO)
	var g5 := _stage(host)
	FX.impact_flash(g5, Vector3.ZERO)
	rows.append([_parts(g1)[0], "命中火花", 34, 18])
	rows.append([_parts(g2)[0], "光束弹着", 48, 26])
	rows.append([_parts(g3)[0], "爆炸火星", 160, 90])
	rows.append([_parts(g3)[1], "爆炸碎片", 30, 16])
	rows.append([_parts(g4)[0], "拼刀火花", 56, 30])
	rows.append([_parts(g5)[0], "弹着闪光火星", 26, 14])

	# ---- 下面三处是**复核时补上的**：改动清单里有它们，但第一版断言漏了 ——
	# 「改了却没钉住」正是本轮最该防的洞（改错了没人红）。
	# ⚠️ `qb_burst()` 返回 `void`（根节点直接挂到 parent 下）⇒ 只能从 stage 里捞。
	var g6 := _stage(host)
	FX.qb_burst(g6, Vector3.ZERO, Vector3(0, 0, 1))
	var g7 := _stage(host)
	var ff := FX.form_flash(g7, Vector3.ZERO, 20.0)
	var g8 := _stage(host)
	var sb := FX.smoke_burst(g8, Vector3.ZERO)
	rows.append([_parts(g6)[0], "QB 爆闪火星", 36, 20])
	rows.append([_parts(ff)[0], "变形闪光剥离粒子", 72, 40])
	rows.append([_parts(sb)[0], "烟团（默认）", 270, 150])

	var bad := []
	var lo := 99.0
	var hi := 0.0
	for row: Array in rows:
		var em := row[0] as GPUParticles3D
		var who := str(row[1])
		var now_val := int(row[2])
		var was := int(row[3])
		if em == null:
			bad.append("%s（没造出来）" % who)
			continue
		t.eq(em.amount, now_val, "%s 的粒子数 = %d" % [who, now_val])
		var ratio := float(em.amount) / float(was)
		t.between(ratio, 1.6, 2.1, "%s 相对改前（%d）抬了 %.2f 倍 —— 是一档，不是一个数"
			% [who, was, ratio])
		lo = minf(lo, ratio)
		hi = maxf(hi, ratio)
		if absf(ratio - 1.8) > 0.31:
			bad.append(who)

	# ---- "有意不动"的 ----
	var rings := FX.dash_rings(_stage(host), Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	t.eq(rings.amount, 5,
		"马赫环的 amount 仍是 5 —— 它是**节拍**不是密度（环间距 = v·lifetime/amount），"
		+ "抬它就是把马赫环改密，属于另一条需求")
	t.lt(3 * FX.TRAIL_HIGH_AMOUNT, 300,
		"导弹尾迹 HIGH 的总量（3 发 = %d）仍在预算内 —— 本轮**没有拿尾迹来充密度**"
			% (3 * FX.TRAIL_HIGH_AMOUNT))
	t.lt(PlayerController.FULL_SALVO_COUNT * FX.TRAIL_LOW_AMOUNT, 3000,
		"100 发全弹发射的尾迹总量（%d）仍在预算内"
			% (PlayerController.FULL_SALVO_COUNT * FX.TRAIL_LOW_AMOUNT))

	# ---- 16 喷口那一路：预算**贴着历史翻车线**抬，不能超过 ----
	var per_boost := clampi(int(float(FlightBody.PLUME_BOOST_BUDGET) / 16.0), 6, 24)
	t.lt(per_boost, FlightBody.PLUME_PER_NOZZLE_MAX,
		"阿利宙斯巡航 16 喷口时每个拿 %d 个（%d / 16）< 翻车线 %d —— "
			% [per_boost, FlightBody.PLUME_BOOST_BUDGET, FlightBody.PLUME_PER_NOZZLE_MAX]
		+ "历史上 16 × 34 = 544 会把整块后机身糊成一团白")
	t.gt(FlightBody.PLUME_BOOST_BUDGET, 192,
		"……而且确实比改前（192）抬了：%d" % FlightBody.PLUME_BOOST_BUDGET)

	print("[R15] 粒子密度：抬了 %d 处（%s），倍率区间 %.2f~%.2f；有意不动 3 处（马赫环节拍 / 弹尾迹红线 / 喷口尺寸曲线）"
		% [rows.size(), ", ".join(bad) if not bad.is_empty() else "全部落在 1.8±0.3", lo, hi])


## 把一个子树里**所有** `GPUParticles3D` 按先序摊平（爆/溅类特效返回的是根节点）。
static func _parts(n: Node) -> Array:
	var out := []
	if n is GPUParticles3D:
		out.append(n)
	for ch in n.get_children():
		out.append_array(_parts(ch))
	return out

# ============================================================ ⑩ 多喷口的形状层

## 柯西 / 佩涅罗佩各 2 个喷口（2026-09-25，用户："柯西的尾焰特效也应该在背部喷口处"
## / "佩涅罗佩的尾焰特效应该在机体上的这个位置"），所以**形状层必须逐喷口铺开**，
## 而不是"多喷口就退化成每口一条加力焰" —— 后者会让"两形区分"在这两台机上凭空消失。
##
## 这一节钉三件事：
##   ① 喷口数是**表里写几个就是几个**，且**每个**口都拿得到 `ab` / `dash` 两形；
##   ② 两形真的二选一（真路径，跑物理帧），而且**机尾那一套必须退场**
##      —— 不退场就是"机尾一大团 + 喷口一堆火"同时出现；
##   ③ 形状层的挂点 = `engine_plumes` 换算出来的那个点（不是机尾骨架锚点）。
static func _multi_nozzle(t: T, host: Node) -> void:
	var c := Node3D.new()
	host.add_child(c)
	c.global_position = Vector3(0, ALT, 0)
	var u := _unit(c, Vector3(0, ALT, 0), SuitProfile.penelope())
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame

	var prof := u.profile
	var want_n := prof.engine_plumes.size()
	t.gt(want_n, 1, "（前提）佩涅罗佩的喷口表不止一个口（%d 个）" % want_n)
	var plumes: Array[Dictionary] = u.get("_plume_fx")
	t.eq(plumes.size(), want_n, "喷口数 = 表里写的那几个（%d）" % want_n)

	var ab_nodes: Array[GPUParticles3D] = []
	var dash_nodes: Array[GPUParticles3D] = []
	var boost_left := 0
	for it: Dictionary in plumes:
		var abn := it.get("ab") as GPUParticles3D
		var dsn := it.get("dash") as GPUParticles3D
		if abn != null and dsn != null:
			ab_nodes.append(abn)
			dash_nodes.append(dsn)
		if it.get("boost") != null:
			boost_left += 1
	t.eq(ab_nodes.size(), want_n,
		"**每个**喷口都备了两形（%d/%d）—— \"多喷口退化成一条加力焰\" 会在这里红"
			% [ab_nodes.size(), want_n])
	t.eq(boost_left, 0,
		"……并且腿的那条 `boost` 不再存在（两形与 boost 是**互斥**的两个分支，同时建就是双份焰")

	# 机尾那一套必须退场
	var tail_ab := u.get("_afterburner_fx") as GPUParticles3D
	var tail_dash := u.get("_dash_fx") as GPUParticles3D
	t.ok(tail_ab != null and tail_dash != null,
		"（前提）机尾那一套节点还在（只是不开火）—— 它是 `_build_attachments` 一次性建的")
	u.translate_mode = false
	u.translate_dash = false
	u.fm.super_boost = false
	u.fm.boosting = true
	await host.get_tree().physics_frame
	t.not_ok(tail_ab.emitting, "多喷口机体：**机尾单点尾焰退场**")
	await host.get_tree().physics_frame
	var ab_on := 0
	var b_off := 0
	for n: GPUParticles3D in ab_nodes:
		if n.emitting:
			ab_on += 1
	for n: GPUParticles3D in dash_nodes:
		if not n.emitting:
			b_off += 1
	t.eq(ab_on, want_n, "……而**每个**喷口自己的形态 A 亮着（%d/%d）" % [ab_on, want_n])
	t.eq(b_off, want_n, "……形态 B 全灭（%d/%d）" % [b_off, want_n])

	# 冲刺 → 每一口都换形
	u.translate_mode = true
	u.set("_qb_timer", 0.40)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var ab_off := 0
	var b_on := 0
	for n: GPUParticles3D in ab_nodes:
		if not n.emitting:
			ab_off += 1
	for n: GPUParticles3D in dash_nodes:
		if n.emitting:
			b_on += 1
	t.eq(ab_off, 0, "佩涅罗佩冲刺继续使用连续焰体（%d/%d）" % [ab_off, want_n])
	t.eq(b_on, 0, "……不启用第二套发射器（%d/%d）" % [b_on, want_n])
	t.not_ok(tail_dash.emitting, "……机尾那一条**仍然**退场")

	# 挂点 = 表里那个点换算出来的位置
	var ok_pos := 0
	var worst := 0.0
	for i in want_n:
		var want: Vector3 = u.model_bounds.position \
			+ prof.engine_plumes[i] * u.model_bounds.size
		# Recover the authored point through the inverse animated bone frame.
		var item: Dictionary = u._plume_fx[i]
		var actual := ab_nodes[i].position
		if item.has("motion_bone") and item["motion_bone"] >= 0:
			var sk := u._model_skel
			var bone: int = item["motion_bone"]
			var rest: Transform3D = u.model_pivot.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_rest(bone)
			var posed: Transform3D = u.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_pose(bone)
			actual = rest*posed.affine_inverse()*actual
		var d := actual.distance_to(want)
		worst = maxf(worst, d)
		if d < 0.05:
			ok_pos += 1
	t.eq(ok_pos, want_n, "每个形状层逆去动画后仍是 `engine_plumes` 指定的挂点（最大偏差 %.3f m）"
		% worst)
	var tail_gap := ab_nodes[0].position.distance_to(tail_ab.position)
	t.gt(tail_gap, 1.0,
		"……而且**不再是机尾那个锚点**（离机尾 %.1f m）—— 这一条才是用户要的那件事" % tail_gap)
	c.queue_free()


# ============================================================ ⑪ 三台机体的颜色要拉开

## 用户 2026-09-25 原话：「另外三台机体的尾焰特效要做区分，
## 柯西是黄色的，阿利宙斯是紫色的，佩涅罗佩是蓝色的」。
##
## 判据刻意写成**色相关系**而不是"等于某个 RGB"：具体数值当然可以调，
## 但"黄 / 紫 / 蓝"这三件事不能丢。三条各自钉住"主色是哪一档"：
##   黄 —— R、G 都明显高于 B，且 R≈G
##   蓝 —— B > G > R，且跨度够大
##   紫 —— B 与 R 都高、**G 最低**（这是"紫"与"蓝"的分界：蓝的 R 最低）
## 再加一条**两两色相角差 ≥ 40°**：否则"把三个都调成浅蓝紫"也能过前三条。
static func _plume_colors(t: T) -> void:
	var xi := SuitProfile.xi().engine_plume_color
	var pen := SuitProfile.penelope().engine_plume_color
	var ari := SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).engine_plume_color

	t.ok(xi.r > xi.b + 0.25 and xi.g > xi.b + 0.25 and absf(xi.r - xi.g) < 0.25,
		"柯西是**黄**（R %.2f / G %.2f 都明显高于 B %.2f，且 R≈G）" % [xi.r, xi.g, xi.b])
	t.ok(pen.b > pen.g and pen.g > pen.r and pen.b - pen.r > 0.35,
		"佩涅罗佩是**蓝**（B %.2f > G %.2f > R %.2f）" % [pen.b, pen.g, pen.r])
	t.ok(ari.b > ari.g + 0.25 and ari.r > ari.g + 0.05 and ari.b > ari.r,
		"阿利宙斯是**紫**（R %.2f / B %.2f 都高、G %.2f 最低 —— 蓝的 R 才是最低的）"
			% [ari.r, ari.b, ari.g])
	t.gt(_hue_gap(xi, ari), 40.0, "黄 ↔ 紫 的色相拉开 %.0f°" % _hue_gap(xi, ari))
	t.gt(_hue_gap(ari, pen), 40.0, "紫 ↔ 蓝 的色相拉开 %.0f°" % _hue_gap(ari, pen))
	t.gt(_hue_gap(pen, xi), 40.0, "蓝 ↔ 黄 的色相拉开 %.0f°" % _hue_gap(pen, xi))
	# 不透明度随喷口数反比：16 个口要淡、2 个口可以实（加色混合会叠亮度）
	t.lt(ari.a, xi.a, "16 个口的 alpha（%.2f）比柯西 4 个口的（%.2f）低" % [ari.a, xi.a])
	t.lt(ari.a, pen.a, "……也比佩涅罗佩 2 个口的（%.2f）低" % pen.a)
	t.near(xi.a, pen.a, 0.001,
		"柯西（4 口）与佩涅罗佩（2 口）仍取同一个 alpha 档 —— 每个口的口径都只有 1 m 上下，加色叠加后不至于糊；真要压一档再说")
	t.gt(xi.a, 0.0, "……而且都真的不透明（alpha %.2f > 0，光晕才看得见）" % xi.a)

	# 上限那一侧：形状层的阈值 `PLUME_SHAPE_MAX_NOZZLES` 的两边都要有真机在
	var n_ari := SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).engine_plumes.size()
	t.gt(n_ari, FlightBody.PLUME_SHAPE_MAX_NOZZLES,
		"阿利宙斯巡航 %d 个口**超过**形状层上限 %d ⇒ 它走\"每口一条加力焰\"那一支"
			% [n_ari, FlightBody.PLUME_SHAPE_MAX_NOZZLES])
	var n_xi := SuitProfile.xi().engine_plumes.size()
	var n_pen := SuitProfile.penelope().engine_plumes.size()
	# ⚠️ `tests/t.gd` **没有** `le`（只有 lt / gt）。写 `t.le` 的后果不是红，
	# 而是抛 SCRIPT ERROR + **静默吃掉同一条语句之后的断言** —— 比写错判据更隐蔽。
	t.ok(n_xi <= FlightBody.PLUME_SHAPE_MAX_NOZZLES,
		"柯西 %d 个口在上限之内 ⇒ 它走\"逐口两形\"那一支" % n_xi)
	t.ok(n_pen <= FlightBody.PLUME_SHAPE_MAX_NOZZLES,
		"佩涅罗佩 %d 个口也在上限之内" % n_pen)
	t.gt(n_xi, 1, "（而且确实不止一个口 —— 否则\"逐口\"与非\"逐口\"就分不出来了）")
	t.eq(n_xi, 4, "柯西：背包上下两个口 + 左右小腿后侧各一个（2026-09-27 增）")
	t.eq(n_pen, 2, "佩涅罗佩：FF 单元两侧吊舱各一个口")
	t.eq(SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL).engine_plumes.size(), 8,
		"阿利宙斯**常态2.0**有 8 个独立喷口 ⇒ 它走\"逐口加力焰\"那一支"
		+ "（8 > 4 上限，与巡航 16 同支）；机尾单点那一支由 `_plain_unit` 的空表机在第四、五节测")


## 两个颜色的**色相角差**（度，取 0~180 的那一半）。
static func _hue_gap(a: Color, b: Color) -> float:
	var d := absf(a.h * 360.0 - b.h * 360.0)
	return minf(d, 360.0 - d)


# ============================================================ ⑫ 冲刺方向的尾焰形变

## 用户原话（2026-09-25）：「在向着不同方向的冲刺的时候尾焰能不能别那么直，来点物理形变」。
##
## ## 为什么**不能**"把发射器转个角度"
##
## 那把戏得到的是一条**被扳歪的直锥**，而且焰根会从喷口上翘起来（像装歪了）。
## 用户要的是**弯曲**：焰根仍贴喷口轴，越往外越偏。
## 实现是把**相对气流**喂给 `ParticleProcessMaterial.gravity` ——
## 均匀加速度下位移 ∝ t²（也就是 ∝ 轴向距离的平方），这正是"抛物线"、也就是"越远越弯"。
##
## ## 只取横分量（这一节一半的断言在钉它）
##
## `bend = wind − axis·(wind·axis)`。沿喷口轴的那一份**故意丢掉**，两个理由：
##   ① 它只会把焰压短 / 拉长，而焰长是**量出来的**常数（束的射程与马赫环 31 m 的
##      射程配套）—— 动它就要重新配套；
##   ② 顺飞时横分量**本来就是 0** ⇒ 焰仍然笔直，"直着冲"的观感没被改坏。
## 若哪天有人把整矢量塞进 `gravity`，"顺飞不弯"那一条会当场红。
##
## ## 覆盖范围
##
## 机尾单点那一路（`_afterburner_fx` / `_dash_fx` / `_dash_rings`）与逐喷口那一路
## （`ab` / `dash`）共用**一份** `_plume_bend` —— 与起跑包络 `env` 同一个道理：
## 分处各算一遍就是"改一处漏一处"。尾气 `fx` **不吃**形变（它在世界空间，
## 喂它机体本地的 `gravity` 是坐标系错误，三条理由写在 `FX.set_plume_bend()` 之后）。
static func _bend(t: T, host: Node) -> void:
	_bend_geometry(t)
	_bend_scaling(t, host)
	_bend_writer(t, host)
	await _bend_path(t, host)


## 纯几何：`FX.plume_bend_vector()` 只做一件事 —— 把 wind 投影到喷口轴的**法平面**。
static func _bend_geometry(t: T) -> void:
	var axis_z := Vector3(0, 0, 1)
	# ① 纯横风：原样通过
	var side := FX.plume_bend_vector(Vector3(3, 0, 0), axis_z)
	t.near(side.x, 3.0, 1e-4, "横向相对气流原样通过（沿 X 的 3.0 → %.2f）" % side.x)
	t.near(side.length(), 3.0, 1e-4, "……大小不变")
	# ② 顺风 / 倒风：与喷口轴共线 ⇒ 整段丢掉。**这一条就是"顺飞焰仍然直"**
	var fwd := FX.plume_bend_vector(Vector3(0, 0, 900.0), axis_z)
	t.near(fwd.length(), 0.0, 1e-4,
		"顺风（沿喷口轴）被**整段丢掉**（%.4f）—— 顺飞时速度再大也不弯" % fwd.length())
	var back := FX.plume_bend_vector(Vector3(0, 0, -900.0), axis_z)
	t.near(back.length(), 0.0, 1e-4, "倒风同理（加速与减速都不弯，只有横向相对气流弯）")
	# ③ 斜风 45°：只留横分量
	var diag := FX.plume_bend_vector(Vector3(1, 0, -1).normalized() * 100.0, axis_z)
	t.near(diag.length(), 100.0 * sin(deg_to_rad(45.0)), 0.05,
		"45° 斜风只剩横分量 = |wind| · sin45°（%.1f）" % diag.length())
	t.near(diag.dot(axis_z), 0.0, 1e-4, "……结果与喷口轴正交")
	# ④ 任意喷口轴（不只是 +Z）
	var axis := Vector3(0.31, -0.52, 0.79).normalized()
	var w := Vector3(120.0, 40.0, -70.0)
	var got := FX.plume_bend_vector(w, axis)
	t.near(got.dot(axis), 0.0, 1e-3, "任意喷口轴：结果都与轴正交")
	t.near((got - (w - axis * w.dot(axis))).length(), 0.0, 1e-3,
		"……而且就是 wind 在轴法平面上的投影")
	# ⑤ 零轴兜底：不给兜底的话 `axis.normalized()` 是 NaN，焰会凭空乱弯
	t.near(FX.plume_bend_vector(Vector3(5, 0, 0), Vector3.ZERO).x, 5.0, 1e-4,
		"零轴向兜底到 +Z（不让归一化变成 NaN）")
	t.near(FX.plume_bend_vector(Vector3(0, 0, 7.0), Vector3.ZERO).length(), 0.0, 1e-4,
		"……于是「沿兜底轴的那一份」同样被丢掉")


## 数值标定：马赫环的弯曲系数必须**按轴向速度反比**缩；常量必须与发射器同源。
static func _bend_scaling(t: T, host: Node) -> void:
	# 横向偏移 ∝ ½·g·s²/v²（s = 轴向距离，v = 粒子轴向速度）⇒ v 在**分母**，
	# 所以"环与束在同一个加速度下被吹歪多少"的比值 = (v_环 / v_束)²。
	var want := (FX.RING_V0 / FX.DASH_BEAM_V0) * (FX.RING_V0 / FX.DASH_BEAM_V0)
	t.near(FX.PLUME_RING_BEND_RATIO, want, 1e-9,
		"环的弯曲系数 = (v_环 / v_束)² = %.4f" % FX.PLUME_RING_BEND_RATIO)
	t.lt(FX.PLUME_RING_BEND_RATIO, 1.0,
		"……小于 1（环只有束的 %.2f 倍轴向速度 ⇒ 同加速度下会被吹歪好几倍 ⇒ 必须按比例减）"
			% (FX.RING_V0 / FX.DASH_BEAM_V0))
	t.gt(FX.PLUME_RING_BEND_RATIO, 0.0, "……且为正（方向要跟着同一股横风）")

	# ⚠️ 这两个常量必须是**那两个发射器真用的初速** —— 直接去发射器上读回来对。
	# 它们正是那个系数的分子 / 分母；两处各写一份字面量迟早会对不上。
	var st := _stage(host)
	var b := FX.afterburner_dash(st, Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var pb := b.process_material as ParticleProcessMaterial
	t.near((pb.initial_velocity_min + pb.initial_velocity_max) * 0.5, FX.DASH_BEAM_V0, 0.6,
		"冲刺束的初速中点就是 `DASH_BEAM_V0`（%.1f）—— 那个系数的分母" % FX.DASH_BEAM_V0)
	t.near(pb.initial_velocity_max - pb.initial_velocity_min, FX.DASH_BEAM_V0_SPAN * 2.0, 0.6,
		"……速度区间的半宽就是 `DASH_BEAM_V0_SPAN`（%.0f）" % FX.DASH_BEAM_V0_SPAN)
	var r := FX.dash_rings(st, Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var pr := r.process_material as ParticleProcessMaterial
	t.near(pr.initial_velocity_min, FX.RING_V0, 0.6,
		"马赫环的初速就是 `RING_V0`（%.1f）—— 那个系数的分子" % FX.RING_V0)
	t.near(pr.initial_velocity_max, FX.RING_V0, 0.6, "……而且是单值（环不带速度抖动）")

	# 量级：满横风时焰梢偏出的距离 = ½·a·t²（t = 寿命 = 射程 / v₀）。
	# 两侧都钉：看得见（> 1 m），又没把焰吹成横的（< 0.8 × 射程）。
	var reach := FX.DASH_BEAM_V0 * b.lifetime
	var drift := 0.5 * FlightBody.PLUME_BEND_ACCEL * b.lifetime * b.lifetime
	t.gt(FlightBody.PLUME_BEND_ACCEL, 0.0,
		"弯曲加速度常量为正（%.0f m/s²，满横风时）" % FlightBody.PLUME_BEND_ACCEL)
	t.gt(drift, 1.0,
		"……满横风时焰梢偏出 %.1f m（束的射程约 %.0f m）—— 看得见" % [drift, reach])
	t.lt(drift, reach * 0.8,
		"……又没把焰吹成横的（%.1f < %.1f）⇒ 它仍然「向前喷」，只是弯了"
			% [drift, reach * 0.8])
	t.gt(FlightBody.PLUME_BEND_RESPONSE, 0.0,
		"一阶跟随速率 %.0f /s：改向时焰不会瞬跳" % FlightBody.PLUME_BEND_RESPONSE)
	st.queue_free()


## 写入器：写进去 / 差得少就跳写 / 空发射器不崩。
static func _bend_writer(t: T, host: Node) -> void:
	var st := _stage(host)
	var p := FX.afterburner_dash(st, Vector3.ZERO, Vector3(0, 0, 1), 2.2)
	var pm := p.process_material as ParticleProcessMaterial
	t.ok(FX.set_plume_bend(p, Vector3(-600, 0, 0)), "写进去返回 true")
	t.near(pm.gravity.x, -600.0, 1e-3, "……材质上读回来就是那个值")
	t.not_ok(FX.set_plume_bend(p, Vector3(-600.4, 0, 0)),
		"差小于 `PLUME_BEND_EPSILON`（%.1f）⇒ **跳写**（返回 false）"
			% FX.PLUME_BEND_EPSILON)
	t.near(pm.gravity.x, -600.0, 1e-3, "……跳写时旧值不动")
	var far := -600.0 - FX.PLUME_BEND_EPSILON * 2.0
	t.ok(FX.set_plume_bend(p, Vector3(far, 0, 0)), "超过 epsilon 就真的写")
	t.near(pm.gravity.x, far, 1e-3, "……值确实换了")
	t.not_ok(FX.set_plume_bend(null, Vector3.ONE), "传 null：返回 false，不崩")
	var bare := GPUParticles3D.new()
	st.add_child(bare)
	t.not_ok(FX.set_plume_bend(bare, Vector3.ONE),
		"没有 `process_material` 的发射器：返回 false，不崩")
	st.queue_free()


static func _bend_path(t: T, host: Node) -> void:
	var c := Node3D.new()
	host.add_child(c)
	c.global_position = Vector3(0, ALT, 0)
	var u := _plain_unit(c, Vector3(0, ALT, 0))
	var ab := u.get("_afterburner_fx") as GPUParticles3D
	var dash := u.get("_dash_fx") as GPUParticles3D
	var rings := u.get("_dash_rings") as GPUParticles3D
	var smoke := u.get("_smoke_fx") as GPUParticles3D
	t.ok(ab != null and dash != null and rings != null, "机尾单点那一套都在")
	t.eq((u.get("_plume_fx") as Array).size(), 0,
		"（前提）这一台是**空喷口表** ⇒ 形状层走机尾单点那一支")
	var ref := u.profile.player_boost_speed()
	t.gt(ref, 1.0, "（前提）档案给得出参考速度（%.0f m/s）" % ref)
	# 尾气有它**自带**的 `gravity`（一点浮力），所以"它不吃形变"不能断成"等于 0"，
	# 只能断成"**不随横风变化**" —— 先记下静止时的值。
	var smoke0 := _g(smoke)
	t.gt(smoke0.length(), 0.0,
		"（前提）尾气自带一个非零 gravity（%.1f）—— 正因为它本来就非零，所以要比「有没有变化」而不是比 0"
			% smoke0.length())

	# ---- ① 横移 ⇒ 打满，方向沿**气流下游**（机体本地 −X）----
	_drive(u, Vector3(ref, 0, 0), 90)
	var bend: Vector3 = u.get("_plume_bend")
	t.near(bend.x, -FlightBody.PLUME_BEND_ACCEL, 2.0,
		"机体向 +X 横移 ⇒ 焰被吹向 −X、且打满（%.1f）" % bend.x)
	t.near(bend.y, 0.0, 1e-3, "……没有纵向分量")
	t.near(bend.z, 0.0, 1e-3, "……也没有沿喷口轴的分量（沿轴那一份被丢掉）")
	# ⚠️ 容差就是 `PLUME_BEND_EPSILON`，不是更小：材质与 `_plume_bend` 的差
	# 一旦小于它，写入器会**按设计跳写** ⇒ 材质上留着上一帧的值（差 0.5 以内）。
	# 拿 0.01 当容差会把"跳写生效了"误报成"没喂到"。
	t.near(_g(ab).x, bend.x, FX.PLUME_BEND_EPSILON, "机尾形态 A 的 `gravity` 拿到同一份")
	t.near(_g(dash).x, bend.x, FX.PLUME_BEND_EPSILON, "机尾形态 B 的 `gravity` 拿到同一份")
	t.near(_g(rings).x, bend.x * FX.PLUME_RING_BEND_RATIO, FX.PLUME_BEND_EPSILON,
		"马赫环拿到的是**按 v² 缩放后**的那一份（%.1f = %.1f × %.3f）"
			% [_g(rings).x, bend.x, FX.PLUME_RING_BEND_RATIO])
	t.near(_g(smoke).distance_to(smoke0), 0.0, 1e-4,
		"尾气**不吃**形变（它在世界空间，喂机体本地的 gravity 是坐标系错误）")

	# ---- ② 顺飞 / 静止 ⇒ 不弯（**这就是"只取横分量"的判据**）----
	_drive(u, Vector3(0, 0, -ref), 90)
	t.near((u.get("_plume_bend") as Vector3).length(), 0.0, 1e-4,
		"顺飞（速度与喷口轴共线）⇒ 不弯 —— 有人把整矢量塞进 gravity 的话这里当场红")
	_drive(u, Vector3.ZERO, 90)
	t.near((u.get("_plume_bend") as Vector3).length(), 0.0, 1e-4, "静止 ⇒ 不弯")
	# 材质上留着的残值同样以 epsilon 为界（跳写）。
	t.lt(_g(ab).length(), FX.PLUME_BEND_EPSILON, "……形态 A 上也是 0（残值 < epsilon）")
	t.lt(_g(rings).length(), FX.PLUME_BEND_EPSILON, "……环上也是 0（残值 < epsilon）")
	t.near(_g(smoke).distance_to(smoke0), 0.0, 1e-4, "……尾气仍然一动不动")

	# ---- ③ 未饱和段随横风**线性** ----
	_drive(u, Vector3(ref * 0.4, 0, 0), 90)
	t.near((u.get("_plume_bend") as Vector3).x, -FlightBody.PLUME_BEND_ACCEL * 0.4, 2.0,
		"横风降到 0.4 倍 ⇒ 弯曲量也降到 0.4 倍")

	# ---- ④ 随 sin(夹角) 变（速度**大小不变**、只转方向）----
	# ⚠️ 用"转方向"而不是"改大小"：改大小会同时动到 sin 与归一化两处，分不清是谁生效。
	# 这里 |v| 恒等于 ref ⇒ amount 恒为 1，于是 `|bend| = ACCEL · sinθ` 是干净的一条。
	var q45 := deg_to_rad(45.0)
	_drive(u, Vector3(sin(q45), 0, -cos(q45)) * ref, 90)
	var b45: Vector3 = u.get("_plume_bend")
	t.near(b45.length(), FlightBody.PLUME_BEND_ACCEL * sin(q45), 2.0,
		"与喷口轴成 45° 的横风 ⇒ |弯曲| = ACCEL × sin45°（%.1f）" % b45.length())
	t.near(b45.x, -FlightBody.PLUME_BEND_ACCEL * sin(q45), 2.0, "……方向仍是 −X")
	_drive(u, Vector3(cos(q45), 0, -sin(q45)) * ref, 90)
	t.near((u.get("_plume_bend") as Vector3).length(),
		FlightBody.PLUME_BEND_ACCEL * cos(q45), 2.0,
		"……与轴成 45° 的另一种朝向同样成立（换个符号再验一遍）")

	# ---- ⑤ 一阶跟随：不是瞬跳 ----
	_drive(u, Vector3.ZERO, 90)
	_drive(u, Vector3(ref, 0, 0), 1)
	var one: Vector3 = u.get("_plume_bend")
	t.gt(one.length(), 0.1, "改向第一帧就开始弯（%.1f）—— 没有死区" % one.length())
	t.lt(one.length(), FlightBody.PLUME_BEND_ACCEL * 0.5,
		"……但**没有瞬跳**到满值（%.1f < 半值）：一阶跟随 %.0f /s"
			% [one.length(), FlightBody.PLUME_BEND_RESPONSE])
	_drive(u, Vector3(ref, 0, 0), 90)
	t.near((u.get("_plume_bend") as Vector3).x, -FlightBody.PLUME_BEND_ACCEL, 2.0,
		"……继续跑就收敛到满值")

	# ---- ⑥ 归一化用的是**档案给的速度**（不是写死的数）----
	# 同一速度、两台 ref 不同的机体：量的比值应当反比于 ref。
	# 取 0.5 × 较小那个 ref，两边都不饱和 —— 饱和了这条就验不出东西。
	var p2 := SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)
	var u2 := _unit(c, Vector3(0, ALT, 0), p2)
	var ref2 := p2.player_boost_speed()
	t.ok(absf(ref - ref2) > 1.0,
		"（前提）两台机的参考速度不同（%.0f vs %.0f）—— 不然这条验不出东西" % [ref, ref2])
	var slow := minf(ref, ref2) * 0.5
	_drive(u, Vector3(slow, 0, 0), 90)
	_drive(u2, Vector3(slow, 0, 0), 90)
	var b1: Vector3 = u.get("_plume_bend")
	var b2: Vector3 = u2.get("_plume_bend")
	t.gt(b1.length(), 0.1, "（前提）低速档也真的弯了（%.1f）" % b1.length())
	t.near(b2.length() / maxf(b1.length(), 1e-6), ref / ref2, 0.02,
		"同一速度、不同参考速度 ⇒ 弯曲量反比于 ref（比值 %.3f vs %.3f）"
			% [b2.length() / maxf(b1.length(), 1e-6), ref / ref2])

	# ---- ⑦ 喂给 gravity 的是**机体本地**向量 ----
	# 机头转过 90° 之后，"沿机体本地 +X 横移"这个**物理处境**没变，
	# 所以机体本地的读数必须一模一样 —— 读数若跟着世界轴走，就说明坐标系用错了。
	var q90 := deg_to_rad(90.0)
	u.global_rotation = Vector3(0, q90, 0)
	_drive(u, u.global_transform.basis * Vector3(ref, 0, 0), 90)
	var b3: Vector3 = u.get("_plume_bend")
	t.near(b3.x, -FlightBody.PLUME_BEND_ACCEL, 2.0,
		"机头转过 90° 后沿「机体本地 +X」横移 ⇒ 本地读数不变（%.1f）" % b3.x)
	t.near(b3.z, 0.0, 1e-3, "……方向仍在**机体本地** −X（不是世界 −X）")
	_drive(u, u.global_transform.basis * Vector3(0, 0, -ref), 90)
	t.near((u.get("_plume_bend") as Vector3).length(), 0.0, 1e-4,
		"……而且不管机头朝哪，**顺飞都不弯**")
	u.global_rotation = Vector3.ZERO

	# ---- ⑧ 逐喷口那一支也拿到同一份 ----
	var c2 := Node3D.new()
	host.add_child(c2)
	c2.global_position = Vector3(0, ALT, 0)
	var u3 := _unit(c2, Vector3(0, ALT, 0), SuitProfile.xi())
	var items: Array[Dictionary] = u3.get("_plume_fx")
	t.gt(items.size(), 0, "（前提）柯西有逐喷口的形状层（%d 个口）" % items.size())
	_drive(u3, Vector3(ref, 0, 0), 90, true)
	var b4: Vector3 = u3.get("_plume_bend")
	t.near(b4.x, -FlightBody.PLUME_BEND_ACCEL, 2.0, "逐喷口的机体照样打满（%.1f）" % b4.x)
	var ok_dash := 0
	for it: Dictionary in items:
		var pd := it.get("dash") as GPUParticles3D
		if pd != null and absf(_g(pd).x - b4.x) < FX.PLUME_BEND_EPSILON:
			ok_dash += 1
	t.eq(ok_dash, items.size(),
		"**每个**喷口的形态 B 都拿到同一份（%d/%d）" % [ok_dash, items.size()])
	_drive(u3, Vector3(ref, 0, 0), 90, false)
	var ok_ab := 0
	for it: Dictionary in items:
		var pa := it.get("ab") as GPUParticles3D
		if pa != null and absf(_g(pa).x - b4.x) < FX.PLUME_BEND_EPSILON:
			ok_ab += 1
	t.eq(ok_ab, items.size(), "换成形态 A 也逐口都拿到（%d/%d）" % [ok_ab, items.size()])
	var smoke_bad := 0
	for it: Dictionary in items:
		var sx := it.get("fx") as GPUParticles3D
		if sx != null and absf(_g(sx).x - smoke0.x) > 1e-4:
			smoke_bad += 1
	t.eq(smoke_bad, 0, "逐喷口的**尾气**同样不吃形变（被误写 %d 个口）" % smoke_bad)

	# ---- ⑨ 再走一遍**真物理帧** ----
	# 上面那一组是"关物理 + 按 60 Hz 手工驱动 `_tick_effects()`"（确定，数值关系
	# 能精确对）。这一组回到真 `_physics_process`，**只断言方向与零** ——
	# 飞行模型会在同一帧里改写 `fm.velocity`，所以幅度不能指望，
	# 但"横风把焰吹向哪一侧""顺飞会不会凭空弯"这两条不会被它掰过来。
	#
	# ⚠️ 横移那一档要**每帧重摆速度**：不重摆的话气动会在几十帧里把横移速度吃掉，
	# 量到的就变成"气动衰减曲线"而不是"特效层读到了本帧的速度"。
	# 这里要钉的是**顺序**（`_tick_effects` 排在 `_apply_flight` 之后，读到的是本帧的值）。
	var u4 := _plain_unit(c2, Vector3(0, ALT, 0))
	_prep_live(u4)
	for _i in 40:
		u4.fm.velocity = Vector3(ref * 2.0, 0, 0)
		u4.fm.speed = u4.fm.velocity.length()
		await host.get_tree().physics_frame
	var live: Vector3 = u4.get("_plume_bend")
	t.lt(live.x, -1.0, "真物理帧：横移 ⇒ 焰被吹向 −X（%.1f）" % live.x)
	t.near(live.y, 0.0, 1e-3, "……纵向分量为 0")
	t.near(live.z, 0.0, 1e-3, "……沿轴分量为 0")
	# 顺飞用**另一台新机体**：`_plume_bend` 是一阶跟随，同一台上的残弯要几十帧才散完，
	# 拿它直接测顺飞只会测到"上一档的尾巴"。
	var u5 := _plain_unit(c2, Vector3(0, ALT, 0))
	_prep_live(u5)
	for _i in 40:
		u5.fm.velocity = Vector3(0, 0, -ref * 2.0)
		u5.fm.speed = u5.fm.velocity.length()
		await host.get_tree().physics_frame
	t.near((u5.get("_plume_bend") as Vector3).length(), 0.0, 1e-3,
		"真物理帧：顺飞 ⇒ 不弯（速度是横风档的两倍也一样）")
	c.queue_free()
	c2.queue_free()


# ============================================================ ⑬ 喷口的开口朝向

## 佩涅罗佩 FF 单元两侧助推吊舱的那两个喷口**实际朝下偏外**
##（实测仰角 −60° / 方位 ±45°，`PENELOPE_PLUME_DIRS`），而轮 16 起所有喷口的
## 喷射方向都写死机体 +Z（正后方）⇒ 屏幕上「焰从吊舱的外壳背面出来、
## **不是**从那个口里出来」（近景正交特写里看得很清楚：沿 +Z 只看到背面白皮）。
##
## 轮 18 在档案里加了 `engine_plume_dirs`（与 `engine_plumes` 一一对应，空表 = 退回 +Z），
## 这一节把它**从头钉到尾**：
##   ① 数据层：佩涅罗佩量过、柯西 / 阿利宙斯没量过（空表）；每个朝向都是**单位向量**、
##      **不是 +Z**、而且**左右镜像**；
##   ② `plume_dir()` 的三条边界（空表 / 越界 / **两张表长度对不上**）一律给零向量 ——
##      调用点看见零向量就退回 `PLUME_AXIS`（**兜底只写在一处**）；
##   ③ 接线：机体真的把那两个方向用上了 —— 逐口的 `axis` 记账、两形的
##      `ParticleProcessMaterial.direction`、尾气的 `direction` **全都**换掉了；
##   ④ 横风形变按**各自的**轴线投影（`_tick_plume_bend()` 的第 ② 段）：拿机尾那一份
##      （按 +Z 投的）去给这两个口用，它沿该口轴向还留着四成多的分量 ——
##      那会把焰**压短 / 拉长**而且弯错方向。
##
## ## 为什么「记账」与「材质读数」两样都要断
## 只断 `item["axis"]`：接线断了（`_rebuild_plumes` 不再问 `plume_dir()`）也能过 ——
## `axis` 是那个函数自己写的。只断材质的 `direction`：反过来，有人把 `direction`
## 写回 +Z 而 `axis` 留着，形变仍按对的那根轴算，屏幕上却是
##「焰从 +Z 出去、被按另一根轴吹弯」—— 两种都是错的，而且都不报错。
static func _nozzle_dir(t: T, host: Node) -> void:
	var pe := SuitProfile.penelope()
	var dirs: Array[Vector3] = SuitProfile.PENELOPE_PLUME_DIRS

	# ---- ① 数据层 ----
	t.eq(pe.engine_plume_dirs.size(), pe.engine_plumes.size(),
		"佩涅罗佩：朝向表与喷口表**等长**（各 %d 个）—— 对不上 `plume_dir()` 会整体退回 +Z"
			% pe.engine_plume_dirs.size())
	t.eq(pe.engine_plumes.size(), dirs.size(),
		"……朝向表就是 `PENELOPE_PLUME_DIRS` 这一份（各 %d 个）" % dirs.size())
	t.ok(SuitProfile.xi().engine_plume_dirs.is_empty(),
		"柯西**留空** ⇒ 它那两个正后方圆口仍走默认 +Z（加这个字段对它们逐位无影响）")
	t.ok(SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).engine_plume_dirs.is_empty(),
		"阿利宙斯巡航（16 口）同样留空")

	var bad_len := 0
	var near_z := 0
	var downward := 0
	for d: Vector3 in dirs:
		if absf(d.length() - 1.0) > 1e-3:
			bad_len += 1
		if d.angle_to(Vector3(0, 0, 1)) < deg_to_rad(30.0):
			near_z += 1
		if d.y < -0.5:
			downward += 1
	t.eq(bad_len, 0, "表里每个朝向都是**单位向量**（长度 ≈ 1.0）")
	t.eq(near_z, 0,
		"……而且**没有一个**落在 +Z 附近（与 +Z 夹角都 > 30°）—— 否则等于把默认值抄进表里充数")
	t.eq(downward, dirs.size(),
		"……而且全都**朝下**（y < −0.5）：这就是用户说的「这两个喷口朝下偏外」那件事")

	var d0 := dirs[0]
	var d1 := dirs[1]
	t.near(d0.x, -d1.x, 1e-4, "两个口**左右镜像**：x 反号（%+.4f / %+.4f）" % [d0.x, d1.x])
	t.near(d0.y, d1.y, 1e-4, "……y 相同（%.4f）" % d0.y)
	t.near(d0.z, d1.z, 1e-4, "……z 相同（%.4f）" % d0.z)
	var off_axis := rad_to_deg(d0.angle_to(Vector3(0, 0, 1)))
	t.gt(off_axis, 60.0,
		"与 +Z 差 %.1f° —— 正是轮 16 那版「焰从背面出来」的根因（置信区间 ±10°，见 `PENELOPE_PLUME_DIRS`）"
			% off_axis)
	t.gt(d0.z, 0.0,
		"……但 z 仍为正（%+.3f）：是「下外**后**方」，不是一味向下 —— 喷气本身仍要有向后的分量"
			% d0.z)

	# ---- ② `plume_dir()` 的三条边界（调用点靠「零向量」这个信号退回 `PLUME_AXIS`）----
	t.near((SuitProfile.xi().plume_dir(0) - Vector3.ZERO).length(), 0.0, 1e-6,
		"空表：`plume_dir(0)` = 零向量 ⇒ 调用点退回 `PLUME_AXIS`")
	t.near((pe.plume_dir(0) - d0).length(), 0.0, 1e-6, "佩涅罗佩 [0] 读回来就是表里那一个")
	t.near((pe.plume_dir(1) - d1).length(), 0.0, 1e-6,
		"……[1] 也**逐口**对（两口都拿 [0] 会在这里红）")
	t.near((pe.plume_dir(-1) - Vector3.ZERO).length(), 0.0, 1e-6, "越界索引 −1：零向量，不崩")
	t.near((pe.plume_dir(99) - Vector3.ZERO).length(), 0.0, 1e-6, "越界索引 99：零向量，不崩")

	# ⚠️ 这一条是「只改了两张表里的一张」的护栏：长度对不上就**整体**退回 ——
	# 那时候「谁配谁」已经无从判断，逐个猜配对只会悄悄配错（还看不出来）。
	#
	# ⚠️ 必须**另起一台**实例再改字段：`penelope()` 每次给新实例，但
	# `PENELOPE_PLUME_DIRS` 是 const，被 `p.engine_plume_dirs = PENELOPE_PLUME_DIRS`
	# **按引用**共享 ⇒ 原地 `append()` 会改掉常量表、污染后面所有用例。
	# 下面是**整个换一个数组**给这台实例的字段，常量表不动。
	var bad := SuitProfile.penelope()
	var one: Array[Vector3] = [d0]
	bad.engine_plume_dirs = one
	t.eq(bad.engine_plumes.size(), 2,
		"（前提）这一台喷口仍是 2 个 ⇒ 下面那条不是靠越界才返回零向量")
	t.near((bad.plume_dir(0) - Vector3.ZERO).length(), 0.0, 1e-6,
		"**两张表长度对不上**（2 个口 vs 1 个朝向）⇒ `plume_dir()` 统一给零向量，不许猜配对")
	t.eq(SuitProfile.PENELOPE_PLUME_DIRS.size(), dirs.size(),
		"……而且常量表本身**没被上一条改掉**（仍 %d 个）—— 上一条改的是那一台实例的字段"
			% dirs.size())

	# ---- ③ 接线：机体真的把那两个方向用上了 ----
	var c := Node3D.new()
	host.add_child(c)
	c.global_position = Vector3(0, ALT, 0)
	var u := _unit(c, Vector3(0, ALT, 0), SuitProfile.penelope())
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var items: Array[Dictionary] = u.get("_plume_fx")
	t.eq(items.size(), dirs.size(),
		"（前提）逐喷口挂点就是表里那两个（%d）" % items.size())

	var wired := 0
	var still_z := 0
	for i in items.size():
		var axis: Vector3 = items[i].get("axis", Vector3.ZERO)
		var effect: Node3D = items[i]["glow"]
		if axis.distance_to((effect.basis*dirs[i]).normalized()) < 1e-4:
			wired += 1
		if axis.distance_to(Vector3(0, 0, 1)) < 1e-4:
			still_z += 1
	t.eq(wired, dirs.size(),
		"逐口的 `axis` = 随部件旋转后的表中方向，而且**逐口对应**（两口都是 [0] 会在这里红）")
	t.eq(still_z, 0,
		"……**没有一个**还写着 +Z —— 接线一漏，`plume_dir()` 的零向量就兜到默认轴上")

	var ab_ok := 0
	var dash_ok := 0
	var fx_ok := 0
	for i in items.size():
		var want: Vector3 = dirs[i].normalized()
		if _dir(items[i].get("ab") as GPUParticles3D).distance_to(want) < 1e-4:
			ab_ok += 1
		if _dir(items[i].get("dash") as GPUParticles3D).distance_to(want) < 1e-4:
			dash_ok += 1
		if _dir(items[i].get("fx") as GPUParticles3D).distance_to(want) < 1e-4:
			fx_ok += 1
	t.eq(ab_ok, dirs.size(),
		"形态 A 的 `ParticleProcessMaterial.direction` 真的换成了那个朝向（不只是记了一笔）")
	t.eq(dash_ok, dirs.size(), "形态 B 的 `direction` 同样换了")
	t.eq(fx_ok, dirs.size(), "尾气（世界空间那道烟）的 `direction` 也跟着换")

	# ---- ④ 横风形变按**各自的**轴线投影 ----
	var ref := u.profile.player_boost_speed()
	t.gt(ref, 1.0, "（前提）档案给得出参考速度（%.0f m/s）" % ref)
	_drive(u, Vector3(ref, 0, 0), 120)
	var tail: Vector3 = u.get("_plume_bend")
	t.near(tail.x, -FlightBody.PLUME_BEND_ACCEL, 2.0,
		"机尾那一条**没变**（仍按 +Z 投影，%.1f）—— 轮 18 改的只是逐喷口那一路" % tail.x)

	var bends: Array[Vector3] = []
	for i in items.size():
		bends.append(items[i].get("bend", Vector3.ZERO) as Vector3)
	var axis0: Vector3 = items[0].get("axis", Vector3.ZERO)
	t.gt(bends[0].length(), 20.0,
		"（前提）佩涅罗佩 [0] 那一份确实非零（%.0f）—— 否则下面那条「正交」是零向量的废话"
			% bends[0].length())
	var perp := 0
	for i in items.size():
		if absf(bends[i].dot(items[i].get("axis", Vector3.ZERO) as Vector3)) < 1.0:
			perp += 1
	t.eq(perp, items.size(),
		"每口自己的 `bend` 都与**该口轴线**正交（= 沿轴那一份被丢掉，`FX.plume_bend_vector`）")
	t.gt(absf(tail.dot(axis0)), 200.0,
		"⚠️ 而机尾那一份对**同一根轴**还留着 %.0f 的分量 —— 拿它给这个口用，焰会被压短 / 拉长且弯错方向"
			% absf(tail.dot(axis0)))
	t.lt(bends[0].length(), float(FlightBody.PLUME_BEND_ACCEL),
		"……所以逐口那一份**小于**机尾那一份（%.0f < %.0f）：有一部分沿该口轴向被丢掉了"
			% [bends[0].length(), FlightBody.PLUME_BEND_ACCEL])
	t.near(bends[0].x, bends[1].x, 2.0,
		"左右镜像：x 分量相同（%.0f / %.0f）" % [bends[0].x, bends[1].x])
	t.near(bends[0].y, -bends[1].y, 2.0,
		"……y 反号（%.0f / %.0f）—— 两口轴线镜像，同一股风的「沿轴份」相反"
			% [bends[0].y, bends[1].y])
	t.near(bends[0].z, -bends[1].z, 2.0, "……z 反号（%.0f / %.0f）" % [bends[0].z, bends[1].z])
	# ⚠️ 上面那条「与自己的轴正交」**对零向量也成立** ⇒ 必须再钉一条**非平凡**的：
	# 两个口的轴线都带 +z 分量（+0.354）⇒ 把风投到它们的法平面上会**生出 z 分量**
	# （∓a²·ACCEL = ∓144，a = 0.354）。而按 +Z 投出来的那一条 **z 恒为 0**（纯横风没有 z 份）。
	# 于是这两条同时能识破「零向量」与「其实还是按 +Z 投的」两种坏法。
	# Rotation and the Penelope bend cap change magnitude; retain a nonzero signed component.
	t.lt(bends[0].z, -0.5,
		"⚠️ [0] 的 z 是**负的**（%.0f）：只有把风投到那根**斜轴**的法平面上才会出现这个分量 —— 按 +Z 投的话 z 恒为 0"
			% bends[0].z)
	t.gt(bends[1].z, 0.5, "……镜像那一口 z 反号（%+.0f）⇒ 两口各自按自己的轴投" % bends[1].z)

	var fed := 0
	for i in items.size():
		var pd := items[i].get("dash") as GPUParticles3D
		if pd != null and (pd.basis*_g(pd)).distance_to(bends[i]) < FX.PLUME_BEND_EPSILON:
			fed += 1
	t.eq(fed, items.size(),
		"……而且**逐口**喂进了材质（喂机尾那一份会让这里红 —— 两者差 %.0f）"
			% bends[0].distance_to(tail))
	# ⚠️ 这一节是**最后一节**：`queue_free()` 只把节点挂进删除队列，
	# 而 `_update_engine_audio()` 起的那个引擎音源（`cruise_penelope.mp3`）要等
	# 一帧才真的停下来。不等这一帧的话，退出时会多出 `AudioStreamMP3` +
	# `AudioStreamPlaybackMP3` 两条「leaked instance」—— 不是断言失败，但会让
	# 「本节新增的噪音」与「真实泄漏」混在一起，以后没人分得清。
	u.set_physics_process(false)
	await host.get_tree().process_frame
	c.queue_free()
	await host.get_tree().process_frame


## 摆一档速度，然后按 60 Hz **手工**推进 `_tick_effects()`。
##
## ⚠️ 为什么手工调：飞行模型每帧都会重写 `fm.velocity`，手写的速度活不过一帧。
## 关掉物理之后没有任何人再写速度，配合"固定帧数"就得到一个**确定**的读数 ——
## 本节里要精确对数值的那些断言（线性、sinθ、环的比值、本地方向）全靠它。
## `_tick_effects()` 是生产代码里**唯一**写 `gravity` 的地方，所以这条仍是真路径，
## 不是"另写一遍算法再测自己"（`tools/plume_bend_shot.gd` 也用同一套办法）。
static func _drive(u: FlightBody, vel: Vector3, frames: int, dash := false) -> void:
	u.set_physics_process(false)
	u.translate_mode = dash
	u.translate_dash = dash
	u.set("_qb_timer", 0.40 if dash else 0.0)
	u.fm.super_boost = false
	u.fm.boosting = true
	u.fm.throttle = 1.0
	u.fm.velocity = vel
	u.fm.speed = vel.length()
	for _i in frames:
		u.call("_tick_effects", 1.0 / 60.0)


## 把一台机体摆进"在推进"的状态，但**不关物理** —— 给第 ⑨ 组用。
static func _prep_live(u: FlightBody) -> void:
	u.translate_mode = false
	u.translate_dash = false
	u.fm.super_boost = false
	u.fm.boosting = true
	u.fm.throttle = 1.0


static func _g(n: GPUParticles3D) -> Vector3:
	if n == null or not is_instance_valid(n):
		return Vector3.ZERO
	var pm := n.process_material as ParticleProcessMaterial
	return pm.gravity if pm != null else Vector3.ZERO


## 发射器**真的朝哪个方向喷**（`ParticleProcessMaterial.direction`）。
##
## ⚠️ 这是与 `item["axis"]`（那只是机体自己的记账）**互相独立**的一个读数 ——
## 「接线断了」与「材质被写回 +Z」是两种不同的坏法，第 ⑬ 节两样都要断。
## 读不到（节点没了 / 没有 `process_material`）时给零向量：任何"等于某个方向"的
## 断言都会因此红，而不是静默通过。
static func _dir(n: GPUParticles3D) -> Vector3:
	if n == null or not is_instance_valid(n):
		return Vector3.ZERO
	var pm := n.process_material as ParticleProcessMaterial
	return pm.direction if pm != null else Vector3.ZERO
