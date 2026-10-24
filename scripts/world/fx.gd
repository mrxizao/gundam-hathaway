class_name FX
extends RefCounted

## 近距离淡出的两个锚点**唯一真源在 `missile_ribbon.gd`**（那里有公式与真机读数）。
## 两层（烟带 + 粒子）共用同一条斜坡 ⇒ 改一处两层一起变。
## ⚠️ 跨文件引用走 `preload`、**不走 `class_name`**（理由见 `producer.gd` 文件头）。
const _RIBBON := preload("res://scripts/world/missile_ribbon.gd")
## 程序化特效工厂 —— 本项目没有任何美术资源，所有爆炸/尾焰/凝结尾都是代码生成的。
##
## 所有 build_* 都返回新建节点（已挂到 parent 下），调用方不用管释放：
## 粒子靠 one_shot + finished 自毁，常驻特效挂在单位身上随单位一起销毁。
##
## ## 粒子密度（轮 15，用户：「粒子特效数量太少了」）
##
## 每个发射器的粒子数就是**可见密度**，它在本文件里是**字面量**（没有全局缩放旋钮）。
## 本轮把"看得见的"那些统一抬约 **×1.8**（逐处比值 1.78 ~ 2.00，13 处**全部**落在这条带里；
## 16 喷口预算另有 1.67，见下表末行 —— 那一处贴着性能翻车线抬，不能照抄 1.8），
## 并**有意留下三处不动**——
## 那三处都有比"好看"更硬的理由，动它们会连带改别的东西：
##
## ⚠️ 这张表与 `suite_fx_plume.gd` 第 ⑨ 节**必须一一对应**：13 处改动逐处有 `t.eq` 钉住
## 新值 + `t.between` 钉住倍率，3 处"不动"逐处有断言。
## （第一版收尾时这张表写了 13 处、断言只钉了 10 处 —— 漏的正是 `qb_burst` /
## `form_flash` / `smoke_burst`，见第 ⑨ 节的"复核时补上的"那一段。）
##
##   | 发射器 | 改前 | 改后 | 为什么是这个数 |
##   |---|---|---|---|
##   | `explosion` 火星 | 90 | **160** | 一眼要能读出"爆" |
##   | `explosion` 碎片 | 16 | **30** | 同上（lifetime 1.3 ≤ 火星 1.4，别超） |
##   | `hit_spark` | 18 | **34** | 命中反馈的底噪 |
##   | `beam_impact` | 26 | **48** | 光束打上去要有"溅" |
##   | `clash_shockwave` 火花 | 30 | **56** | 拼刀是"硬碰硬"，碎屑是主要读法 |
##   | `impact_flash` 火星 | 14 | **26** | 同上 |
##   | `qb_burst` 火星 | 20 | **36** | 同上 |
##   | `afterburner`（**单喷口**） | 40 | **80** | 见函数头：24→40 就是为"别像一串泡泡" |
##   | `afterburner_dash` | 110 | **200** | 函数头写着"必须够大才连成一条" |
##   | `exhaust_smoke` | 10 | **20** | 尾气要成柱 |
##   | `form_flash` 剥离粒子 | 40 | **72** | "旧壳在脱落"要看得见 |
##   | `smoke_burst`（默认） | 150 | **270** | 一大团烟 |
##   | `damage_smoke` | 48 | **88** | 受损黑烟 |
##   | 16 喷口加力预算（`FlightBody`） | 192 | **320** | **贴着天花板**抬：16×34=544 是历史翻车线 |
##
##   **不动的三处**（都不是"忘了"，是各有更硬的理由）：
##   · `dash_rings.amount = 5` —— 它**不是密度**，是**节拍**：
##     环间距 = `velocity × lifetime / amount`，改它就是改马赫环的疏密与"射程配套"
##     （见那个函数头，测试 §③ 也在核这条）。
##   · `missile_trail` HIGH/LOW = 80/28 —— **性能红线**：`suite_missile_smoke._budget()`
##     卡着"普通扳机 < 300 粒子"，而且全弹发射是 **100 发**一次（×40 就是 4000）。
##   · 喷口**尺寸**曲线 —— 每颗粒子多大是另一根轴；本轮只动**数量**，
##     不跟着动 `scale`，因为"更多 + 更小"会把这点增量又还回去（看不到变化）。


## ParticleProcessMaterial.color_ramp 要的是 Texture2D，不是 Gradient，必须包一层。
static func _ramp(g: Gradient) -> GradientTexture1D:
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## `scale_curve` / `turbulence_influence_over_life` / `angular_velocity_curve` 要的都是
## `Texture2D`，而 `Curve` 不是 —— 必须包一层 `CurveTexture`（与 `_ramp` 同一件事）。
##
## ⚠️ **Godot 4 的 `Curve` 默认 `max_value = 1.0`，超过 1 的点会被静默钳制。**
## 首轮给导弹尾迹做"随龄扩散到 1.3"时踩到：代码里明明写着 `add_point(1.0, 1.30)`，
## 运行时读回却是 1.0，曲线整条被压平 —— 不报错、不红任何断言，只是"越飘越大"这件事
## **根本没发生**。所以这里统一把 `max_value` 抬到 **2.5**（本项目所有"膨胀"类的终点
## 都在 2.2 以内），再给点。
##
## `pts` 是按 x 递增给的 `Vector2(x 归一化寿命, y 系数)` 列表。
static var _curve_cache:Dictionary={}
static func _curve(pts: Array) -> CurveTexture:
	var cache_key:=var_to_str(pts)
	if _curve_cache.has(cache_key):return _curve_cache[cache_key]
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 2.5
	for p in pts:
		var v: Vector2 = p
		c.add_point(v)
	var tex := CurveTexture.new()
	tex.curve = c
	if _curve_cache.size()>=64:_curve_cache.erase(_curve_cache.keys()[0])
	_curve_cache[cache_key]=tex
	# 采样宽度：默认 2048 是为了"曲线也能当贴图素材"那种用法；
	# 这里只当尺寸/强度的查表用，64 个采样点足够，一份省 8 KB 显存 × 十几份。
	tex.width = 64
	return tex


static func _additive(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	return m


static func _billboard(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := _additive(color, energy)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	return m


## 一发爆炸：粒子 + 闪光 + 冲击环。scale=1 约对应一架 MS 的体积。
static func explosion(parent: Node, at: Vector3, scale := 1.0, color := Color(1.0, 0.62, 0.18)) -> Node3D:
	var root := Node3D.new()
	root.name = "Explosion"
	root.top_level = true
	parent.add_child(root)
	if not preload("res://scripts/world/transient_fx_budget.gd").track(root,2.0,true):return root
	root.global_position = at

	# --- 火星 ---
	var p := GPUParticles3D.new()
	p.amount = 160
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 3.0 * scale
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 25.0 * scale
	pm.initial_velocity_max = 95.0 * scale
	pm.gravity = Vector3(0, -16.0, 0)
	pm.damping_min = 8.0
	pm.damping_max = 26.0
	pm.scale_min = 0.9 * scale
	pm.scale_max = 2.4 * scale
	# 火星**沿速度拉成一丝**（`align_y` + 细长椭球）—— 这是"爆炸"与"一团橙雾"
	# 在近处的分界：圆点是"粒子"，一丝一丝才是"被炸飞的碎屑在燃烧"。
	pm.particle_flag_align_y = true
	# 越飞越细（1.0 → 0.4）：火星在冷却、在耗掉自己。
	pm.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(0.5, 0.72), Vector2(1.0, 0.40)])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 2.6
	pm.turbulence_noise_speed = Vector3(1.4, 1.4, 1.4)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 0.85))
	ramp.set_color(1, Color(1, 0.25, 0.05, 0.0))
	ramp.add_point(0.25, Color(1, 0.75, 0.2))
	pm.color_ramp = _ramp(ramp)
	p.process_material = pm

	var spark := SphereMesh.new()
	# 4:1 的细长椭球：配合上面的 `align_y` 才拉得出"一丝"。原先是 2:1，
	# 拉出来还是一颗"豆子"。
	spark.radius = 0.7
	spark.height = 2.8
	spark.radial_segments = 6
	spark.rings = 3
	var sm := _additive(Color(1.0, 0.8, 0.4), 6.0)
	spark.material = sm
	p.draw_pass_1 = spark
	root.add_child(p)
	p.finished.connect(root.queue_free)
	p.emitting = true

	# --- 碎片（被炸开的蒙皮）---
	#
	# 只有火星 + 闪光的爆炸在画面上是"一团亮雾"：没有**实心的、会翻滚的**东西，
	# 眼睛读不出"有东西被炸碎了"。碎片补的就是这一层。
	# ⚠️ 它挂在**火星**之后 add，而 root 的 free 挂在火星的 `finished` 上（lifetime 1.4 s）
	# —— 碎片的 lifetime 必须 ≤ 1.4，否则会被腰斩。
	var debris := GPUParticles3D.new()
	debris.name = "ExplosionDebris"
	debris.amount = 30
	debris.lifetime = 1.30
	debris.one_shot = true
	debris.explosiveness = 0.95
	debris.local_coords = false
	var dpm := ParticleProcessMaterial.new()
	dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	dpm.emission_sphere_radius = 2.4 * scale
	dpm.direction = Vector3.UP
	dpm.spread = 180.0
	dpm.initial_velocity_min = 30.0 * scale
	dpm.initial_velocity_max = 110.0 * scale
	dpm.gravity = Vector3(0, -22.0, 0)
	dpm.damping_min = 2.0
	dpm.damping_max = 8.0
	dpm.scale_min = 0.25 * scale
	dpm.scale_max = 0.90 * scale
	# ⚠️ **自转只在这一层有意义**：它的 `draw_pass` 是**方块**（不对称），
	# 转起来画面上真的不同。给球体 / 圆盘（尾焰、光晕、烟）加 `angular_velocity`
	# 是纯噪音——它们转与不转在屏幕上逐像素一样。
	dpm.angular_velocity_min = -520.0
	dpm.angular_velocity_max = 520.0
	var dramp := Gradient.new()
	dramp.set_color(0, Color(1, 1, 1, 1))
	dramp.set_color(1, Color(0.55, 0.5, 0.48, 1))
	dpm.color_ramp = _ramp(dramp)
	debris.process_material = dpm
	var dm := BoxMesh.new()
	dm.size = Vector3(1.7, 0.5, 1.1)
	# 碎片是**受光的实心块**：材质上与火星（additive 自发光）和烟（alpha 暗色）
	# 都不一样，三种东西叠在一起才有层次。再给一点暗红自发光，暗示"刚被炸出来还热着"。
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.28, 0.29, 0.32)
	dmat.metallic = 0.65
	dmat.roughness = 0.45
	dmat.emission_enabled = true
	dmat.emission = Color(0.30, 0.12, 0.04)
	dmat.emission_energy_multiplier = 1.0
	dmat.vertex_color_use_as_albedo = true
	dm.material = dmat
	debris.draw_pass_1 = dm
	root.add_child(debris)
	debris.emitting = true

	# --- 闪光 ---
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 28.0 * scale
	light.omni_range = 220.0 * scale
	root.add_child(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45)

	# --- 冲击环 ---
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 4.0 * scale
	torus.outer_radius = 4.6 * scale
	torus.rings = 24
	torus.ring_segments = 6
	torus.material = _additive(color, 4.0)
	ring.mesh = torus
	root.add_child(ring)
	var rt := ring.create_tween()
	rt.set_parallel(true)
	rt.tween_property(ring, "scale", Vector3.ONE * 9.0 * scale, 0.7)
	rt.tween_property(ring, "transparency", 1.0, 0.7)

	return root


## 命中火花（小一圈的爆点）。
static func hit_spark(parent: Node, at: Vector3, scale := 0.35) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	if not preload("res://scripts/world/transient_fx_budget.gd").track(root,0.8):return
	root.global_position = at
	var p := GPUParticles3D.new()
	p.amount = 34
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 10.0 * scale
	pm.initial_velocity_max = 34.0 * scale
	pm.gravity = Vector3(0, -20, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	# 命中火花也**拉成一丝**：被打中的瞬间飞出来的应该是"被剐下来的碎屑"，
	# 一颗颗圆点在近处看像撒了一把糖。
	pm.particle_flag_align_y = true
	pm.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(0.6, 0.65), Vector2(1.0, 0.35)])
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 0.95, 0.7))
	ramp.set_color(1, Color(1, 0.5, 0.1, 0.0))
	pm.color_ramp = _ramp(ramp)
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = 0.30
	m.height = 1.60
	m.radial_segments = 5
	m.rings = 2
	m.material = _additive(Color(1, 0.85, 0.5), 3.8)
	p.draw_pass_1 = m
	root.add_child(p)
	p.finished.connect(root.queue_free)
	p.emitting = true


## 光束命中：比普通火花大一档的粉白色爆点 + 短促闪光。
static func beam_impact(parent: Node, at: Vector3) -> void:
	var root := Node3D.new()
	root.top_level = true
	parent.add_child(root)
	if not preload("res://scripts/world/transient_fx_budget.gd").track(root,1.2):return
	root.global_position = at

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.85)
	light.light_energy = 6.0
	light.omni_range = 90.0
	root.add_child(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.20)
	tw.tween_callback(light.queue_free)

	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 0.4
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 42.0
	pm.gravity = Vector3(0, -8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	# 与 `hit_spark` 同一套：拉丝 + 越飞越细。光束命中点飞出来的是**熔融的溅射**，
	# 它和普通弹着火花（橙黄）的区别主要在颜色（粉白）与量级，形态是同一类东西。
	pm.particle_flag_align_y = true
	pm.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(0.6, 0.68), Vector2(1.0, 0.38)])
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 1.0))
	ramp.set_color(1, Color(1.0, 0.35, 0.75, 0.0))
	pm.color_ramp = _ramp(ramp)
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = 0.42
	m.height = 2.10
	m.radial_segments = 6
	m.rings = 3
	m.material = _additive(Color(1.0, 0.6, 0.9), 4.8)
	p.draw_pass_1 = m
	root.add_child(p)
	p.emitting = true
	# Light fades first, sparks finish next, residual smoke owns final cleanup.
	if Settings.effects_quality>0:
		var smoke:=_beam_contact_smoke(root)
		smoke.finished.connect(root.queue_free)
	else:
		p.finished.connect(root.queue_free)
	# GPU-finished can be delayed while culled; bound lifetime independently of visibility.
	var cleanup:=root.create_tween()
	cleanup.tween_interval(0.80 if Settings.effects_quality>0 else 0.55)
	cleanup.tween_callback(root.queue_free)


## 被丢弃的光束步枪：一支翻滚着飞出去掉向海面的枪。
static func jettisoned_rifle(parent: Node, at: Vector3, velocity: Vector3) -> void:
	var root := Node3D.new()
	root.name = "JettisonedRifle"
	parent.add_child(root)
	root.global_position = at

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.9, 9.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.33, 0.38)
	mat.metallic = 0.7
	mat.roughness = 0.4
	box.material = mat
	mi.mesh = box
	root.add_child(mi)

	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "global_position", at + velocity * 3.2, 3.2)
	tw.tween_property(root, "rotation", Vector3(TAU * 1.4, TAU * 0.9, TAU * 0.5), 3.2)
	tw.chain().tween_callback(root.queue_free)


## ---- 光束军刀配色（2026-09-29：改成按机体可指定）----
##
## 老行为是**写死的粉白**，所有机体共用一刀同色。用户要求柯西的光束军刀是**绿色**，
## 于是把颜色做成可选参数：`tint.a <= 0` = 「没指定」⇒ 逐位退回下面这套老粉白
## （其余机体**一个字节都不变**）；指定了 ⇒ 内芯 / 残影 / 点光**都由主色推**。
##
## ⚠️ 为什么必须「由主色推」：老粉白是一套**三个不同的粉**（刃 0.45 绿通道、
## 内芯近白、残影 0.72）。只换主色、内芯仍用老近白的话，绿刀会配出一圈**发粉**的芯
## —— 在 additive 混合下尤其明显（叠加会把色偏叠出来）。
const SABER_TINT := Color(1.0, 0.45, 0.9)
const SABER_CORE := Color(1.0, 0.92, 1.0)
const SABER_GHOST := Color(1.0, 0.72, 0.96)
const SABER_LIGHT := Color(1.0, 0.6, 0.95)

## 「没指定」的判据只有一处（`a <= 0`），四处取色都走这几个助手，避免判据分家。
## 顺序：主色 → 内芯（最白）→ 残影（中）→ 点光（略白）。
static func saber_tint_of(tint: Color) -> Color:
	return SABER_TINT if tint.a <= 0.0 else Color(tint.r, tint.g, tint.b, 1.0)


static func saber_core_of(tint: Color) -> Color:
	return SABER_CORE if tint.a <= 0.0 else saber_tint_of(tint).lerp(Color.WHITE, 0.72)


static func saber_ghost_of(tint: Color) -> Color:
	return SABER_GHOST if tint.a <= 0.0 else saber_tint_of(tint).lerp(Color.WHITE, 0.45)


static func saber_light_of(tint: Color) -> Color:
	return SABER_LIGHT if tint.a <= 0.0 else saber_tint_of(tint).lerp(Color.WHITE, 0.10)


## 光束军刀劈砍命中：一道扇形斩击弧 + 白闪。
##
## `tint` = 主色，**`alpha = 0` 表示「没指定」**（语义见上面那组常量）。
static func saber_slash(parent: Node, at: Vector3, facing: Vector3, up: Vector3,
		tint := Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var root := Node3D.new()
	root.name = "SaberSlash"
	parent.add_child(root)
	root.global_position = at
	root.look_at(at + facing.normalized(), up if absf(facing.normalized().dot(up)) < 0.95 else Vector3.RIGHT)

	var arc := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 12.0
	torus.outer_radius = 15.5
	torus.rings = 28
	torus.ring_segments = 5
	torus.material = _additive(saber_tint_of(tint), 9.0)
	arc.mesh = torus
	arc.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(arc)

	# ---- 残影弧：跟在同一道斩击后面、细一档、慢一拍 ----
	# 单道弧抹过去只像"一道光扫过"；加一道**慢半拍**的细弧，眼睛才读得出
	# "刀锋**掠过**"这个过程（而不是一次闪现）。
	var ghost := MeshInstance3D.new()
	var gtorus := TorusMesh.new()
	gtorus.inner_radius = 10.4
	gtorus.outer_radius = 11.6
	gtorus.rings = 28
	gtorus.ring_segments = 4
	gtorus.material = _additive(saber_ghost_of(tint), 5.0)
	ghost.mesh = gtorus
	ghost.rotation_degrees = Vector3(90, 0, 0)
	# 初始全透明 ⇒ 前 0.06 s 不可见，然后"点亮"再淡出。
	ghost.transparency = 1.0
	root.add_child(ghost)
	var gt := ghost.create_tween()
	gt.tween_interval(0.06)
	gt.tween_property(ghost, "transparency", 0.0, 0.02)
	gt.tween_property(ghost, "transparency", 1.0, 0.30)

	var scale_tw := root.create_tween()
	scale_tw.set_parallel(true)
	scale_tw.tween_property(root, "scale", Vector3.ONE * 2.2, 0.35)
	scale_tw.tween_property(arc, "transparency", 1.0, 0.35)
	scale_tw.chain().tween_callback(root.queue_free)

	var light := OmniLight3D.new()
	light.light_color = saber_light_of(tint)
	light.light_energy = 14.0
	light.omni_range = 140.0
	root.add_child(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.3)


## 光束军刀**刀刃**：挂在手部锚点上的发光刃，突进期间可见（批 10 打击感）。
## 之前挥刀全程模型上没有刀 —— 「我在用军刀」这件事只有音效在说，
## 远处看两机对冲根本分不清谁在劈砍。**颜色与斩击弧同源**（同一套 `saber_*_of()`）。
##
## `tint` = 主色，**`alpha = 0` 表示「没指定」**（语义见上面那组常量）。
## 返回根节点（指向 -Z = 机头方向），调用方负责挂载与销毁。
## ⚠️ 2026-10-03（轮 63-4）：本函数退化成**薄壳**（单头剑 = 后刃长 0），
## 双头剑走 `beam_blade_pair()`。**签名保持不变** ⇒ 既有调用点与老机体逐位不变。
static func beam_blade(length := 15.0, tint := Color(0.0, 0.0, 0.0, 0.0)) -> Node3D:
	return beam_blade_pair(length, 0.0, tint)


## 光束军刀**双头剑**：`front` = 前/上刃（沿 −Z = 机头；用户说的"长"），
## `rear` = 后/下刃（沿 +Z = 机尾；用户说的"短"）。
##
## **`rear <= 0.0` ⇒ 只有前刃**，输出与 `beam_blade(front, tint)` **逐位一致**
##（老机体的画面因此一个像素都不变）。
##
## 用户原话：「光束军刀刀身在游戏内不显示（柯西是双头剑，上长下短）」
## ⇒ 长度来自 `SuitProfile.saber_blade_front / saber_blade_rear`，不再写死在调用点。
static func beam_blade_pair(front := 15.0, rear := 0.0,
		tint := Color(0.0, 0.0, 0.0, 0.0)) -> Node3D:
	var root := Node3D.new()
	root.name = "SaberBlade"
	_add_blade_half(root, front, tint, -1.0)      # 前刃：沿 −Z
	if rear > 0.0:
		_add_blade_half(root, rear, tint, 1.0)    # 后刃：沿 +Z
	return root


## 造**一半**刀刃（外层刃 + 内层芯）并挂进 `root`。
##
## `dir` = 刀身指向：**−1 = 前刃**（−Z，机头）、**+1 = 后刃**（+Z，机尾）。
## 两半都是**刃尖朝外、粗端在握把一侧** —— 靠 `rotation_degrees.x = −90·dir`
## 把圆柱的 +Y（粗端 = `top_radius`）翻到握把那侧实现（圆柱默认沿 Y）。
##
## ⚠️ 这条"刃尖朝外"不是装饰：`top_radius` 0.42 / `bottom_radius` 0.16 是
## 靠着**收细的那一端**去读"刀往哪边劈"的（见上面 `beam_blade` 的老注释）。
## 前后两半如果都朝同一侧收细，双头剑看起来就是"两根长短不一的棍子连着"。
static func _add_blade_half(root: Node3D, length: float, tint: Color, dir: float) -> void:
	# 外层刃：主色半透明，粗——远处也读得出「一道光刃」。
	# 「没指定」时 `saber_tint_of()` 返回老粉白，所以老机体的画面逐位不变。
	var blade := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.16        # 刃尖收细，读出"劈砍方向"
	cyl.height = length
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.material = _additive(saber_tint_of(tint), 7.0)
	blade.mesh = cyl
	# 圆柱默认沿 Y；转到 Z 轴并沿 `dir` 从握把向外伸出
	blade.rotation_degrees = Vector3(-90.0 * dir, 0, 0)
	blade.position = Vector3(0, 0, dir * (length * 0.5 + 1.5))
	root.add_child(blade)
	# 内层芯：近白的细芯 —— 「高温」惯例，让刃有体积感而不是一条纸片。
	# 指定了主色时它由主色推（lerp 到白 0.72），不会串出粉边。
	var core := MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.18
	core_mesh.bottom_radius = 0.06
	core_mesh.height = length * 0.94
	core_mesh.radial_segments = 6
	core_mesh.rings = 1
	core_mesh.material = _additive(saber_core_of(tint), 12.0)
	core.mesh = core_mesh
	core.rotation_degrees = blade.rotation_degrees
	core.position = blade.position
	root.add_child(core)


## 相杀**冲击波**：拼刀点的扩散白环 + 白闪核心 + 一盏爆亮的光（批 10 打击感）。
## 相杀是整局最重的一记"碰撞"，之前只有 hit_spark —— 玩家读不出"拼开了"的分量。
static func clash_shockwave(parent: Node, at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "ClashShockwave"
	parent.add_child(root)
	root.global_position = at

	# 扩散环：白青色，从 0 摊开到 5 倍后消散
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 9.0
	torus.outer_radius = 11.0
	torus.rings = 32
	torus.ring_segments = 6
	torus.material = _additive(Color(0.85, 0.97, 1.0), 9.0)
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(ring)
	var ring_tw := ring.create_tween()
	ring_tw.set_parallel(true)
	ring_tw.tween_property(ring, "scale", Vector3.ONE * 5.0, 0.5).set_ease(Tween.EASE_OUT)
	ring_tw.tween_property(ring, "transparency", 1.0, 0.5)
	# ---- 拼刀溅出的火花 ----
	# 相杀是"两把刀撞在一起"：有冲击波、有白闪，但**没有碎屑**的话，
	# 它读起来像一次"能量弹开"，而不是"硬碰硬"。
	var sparks := GPUParticles3D.new()
	sparks.name = "ClashSparks"
	sparks.amount = 56
	sparks.lifetime = 0.45
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3.UP
	spm.spread = 180.0
	spm.initial_velocity_min = 55.0
	spm.initial_velocity_max = 175.0
	spm.gravity = Vector3(0, -26.0, 0)
	spm.damping_min = 5.0
	spm.damping_max = 15.0
	spm.scale_min = 0.38
	spm.scale_max = 0.95
	spm.particle_flag_align_y = true
	spm.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(0.6, 0.70), Vector2(1.0, 0.32)])
	var sramp := Gradient.new()
	sramp.set_color(0, Color(0.98, 1.0, 1.0, 0.95))
	sramp.add_point(0.35, Color(0.70, 0.88, 1.0, 0.80))
	sramp.set_color(1, Color(0.55, 0.75, 1.0, 0.0))
	spm.color_ramp = _ramp(sramp)
	sparks.process_material = spm
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 1.30
	sm.radial_segments = 5
	sm.rings = 2
	sm.material = _additive(Color(0.88, 0.97, 1.0), 7.0)
	sparks.draw_pass_1 = sm
	root.add_child(sparks)
	sparks.emitting = true

	# ⚠️ 收口改挂**最长**的那一层（火星 0.45 s / 环 0.5 s ⇒ 取 0.62 s）。
	# 原先挂环的 0.5 s chain，加了火星就正好把它腰斩在最后 0.05 s。
	var kt := root.create_tween()
	kt.tween_interval(0.62)
	kt.tween_callback(root.queue_free)

	# 白闪核心：一记即逝的亮球
	var flash := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 6.0
	sph.height = 12.0
	sph.radial_segments = 12
	sph.rings = 6
	sph.material = _additive(Color(1.0, 1.0, 1.0), 14.0)
	flash.mesh = sph
	root.add_child(flash)
	var flash_tw := flash.create_tween()
	flash_tw.set_parallel(true)
	flash_tw.tween_property(flash, "scale", Vector3.ONE * 2.4, 0.18)
	flash_tw.tween_property(flash, "transparency", 1.0, 0.18)

	var light := OmniLight3D.new()
	light.light_color = Color(0.85, 0.95, 1.0)
	light.light_energy = 22.0
	light.omni_range = 200.0
	root.add_child(light)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.45)


## 命中**白闪**：命中点一记即逝的白热小球（批 10 打击感）。
## 军刀砍在肉上之前只有火花粒子 —— 火花是"碎屑"，缺的是"接触面被烧亮"的那一瞬。
static func impact_flash(parent: Node, at: Vector3, color := Color(1, 1, 1)) -> void:
	var root := Node3D.new()
	root.name = "ImpactFlash"
	parent.add_child(root)
	root.global_position = at
	var flash := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 4.5
	sph.height = 9.0
	sph.radial_segments = 10
	sph.rings = 5
	sph.material = _additive(color, 12.0)
	flash.mesh = sph
	root.add_child(flash)
	var tw := flash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 1.9, 0.14)
	tw.tween_property(flash, "transparency", 1.0, 0.14)

	# ---- 扩散环：白闪之外再加一圈"被打出来的"环 ----
	# 只有一记亮球，玩家读到的是"那里亮了一下"；环才读出**接触面的冲击**。
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.4
	torus.outer_radius = 4.4
	torus.rings = 22
	torus.ring_segments = 5
	torus.material = _additive(color, 6.0)
	ring.mesh = torus
	root.add_child(ring)
	var rt := ring.create_tween()
	rt.set_parallel(true)
	rt.tween_property(ring, "scale", Vector3.ONE * 2.8, 0.26).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "transparency", 1.0, 0.26)

	# ---- 溅射火星：命中点上飞出来的碎屑（拉丝）----
	var sparks := GPUParticles3D.new()
	sparks.name = "ImpactSparks"
	sparks.amount = 26
	sparks.lifetime = 0.34
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 70.0
	pm.gravity = Vector3(0, -24.0, 0)
	pm.damping_min = 4.0
	pm.damping_max = 12.0
	pm.scale_min = 0.28
	pm.scale_max = 0.62
	pm.particle_flag_align_y = true
	pm.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.35)])
	var sramp := Gradient.new()
	sramp.set_color(0, Color(minf(color.r + 0.20, 1.0), minf(color.g + 0.20, 1.0),
		minf(color.b + 0.20, 1.0), 0.95))
	sramp.set_color(1, Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, 0.0))
	pm.color_ramp = _ramp(sramp)
	sparks.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 1.0
	sm.radial_segments = 5
	sm.rings = 2
	sm.material = _additive(color, 6.0)
	sparks.draw_pass_1 = sm
	root.add_child(sparks)
	sparks.emitting = true

	# ⚠️ 收口挂在**最长**的那一层（火星 0.34 s）。原先挂闪光的 0.14 s，
	# 那样环与火星会在中途被一起 free —— 症状是"明明加了特效却看不见"。
	var kt := root.create_tween()
	kt.tween_interval(0.36)
	kt.tween_callback(root.queue_free)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 10.0
	light.omni_range = 110.0
	root.add_child(light)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.2)


## **QB 起跑 · 喷口爆闪**（批 11 手感）：闪避冲刺起跑那一瞬，尾部一记
## 沿冲刺方向拉长的亮斑 + 短促的光 —— "引擎在这一刻点火了"。
## 与 `clash_shockwave` / `impact_flash` 同一套即弃节点 + tween 收口的路数。
##
## `at` = 尾喷口世界坐标；`dir` = **冲刺方向**（爆闪沿它拉长，读作"朝那里弹出去"）。
## 零向量不炸（守一下：测试可能喂零向量的机）。
static func qb_burst(parent: Node, at: Vector3, dir: Vector3,
		color := Color(0.62, 0.85, 1.0)) -> void:
	var root := Node3D.new()
	root.name = "QbBurst"
	# ⚠️ force_readable_name = true：同帧同父节点来第二个爆闪时，Godot 的
	# 默认改名是按**类名**生成（"@Node3D@5"，原名整个丢掉）—— 连"QbBurst2"
	# 都认不出、调试与测试都没法按名找节点。强制可读名后冲突自动变 "QbBurst2"。
	parent.add_child(root, true)
	root.global_position = at
	var flash := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 3.0
	sph.height = 6.0
	sph.radial_segments = 10
	sph.rings = 5
	sph.material = _additive(color, 12.0)
	flash.mesh = sph
	# 拉长轴 = 本地 Z；looking_at(dir) 让 -Z 对准冲刺方向 —— 缩放 Z 就是沿冲刺方向拉伸。
	if dir.length_squared() > 0.0001:
		flash.basis = Basis.looking_at(dir.normalized(), Vector3.UP)
	flash.scale = Vector3(0.8, 0.8, 2.6)
	root.add_child(flash)
	var tw := flash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3(1.4, 1.4, 4.8), 0.16)
	tw.tween_property(flash, "transparency", 1.0, 0.16)

	# ---- 定向冲击环：从喷口**朝冲刺方向**推出去的一圈 ----
	# 闪光只说明"这里亮了一下"，环才说明"**朝那个方向**喷出去了" ——
	# QB 是位移技能，画面上必须把方向说出来。
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 2.9
	torus.rings = 20
	torus.ring_segments = 5
	torus.material = _additive(color, 5.0)
	ring.mesh = torus
	if dir.length_squared() > 0.0001:
		# `TorusMesh` 的轴是 Y；先绕 X 转 -90° 把轴掰到 -Z，再用 `looking_at`
		# 把 -Z 对准冲刺方向 ⇒ 环面垂直于冲刺方向（一圈"推出去"的激波）。
		ring.basis = Basis.looking_at(dir.normalized(), Vector3.UP) \
			* Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	root.add_child(ring)
	var rt := ring.create_tween()
	rt.set_parallel(true)
	rt.tween_property(ring, "scale", Vector3.ONE * 2.3, 0.24).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "transparency", 1.0, 0.24)

	# ---- 火星：被喷出去的一把碎屑 ----
	var sparks := GPUParticles3D.new()
	sparks.name = "QbSparks"
	sparks.amount = 36
	sparks.lifetime = 0.22
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	var spm := ParticleProcessMaterial.new()
	# ⚠️ 零向量守卫（与上面那处同款）：测试会喂零向量的机，`normalized()` 零向量会变 NaN，
	# NaN 进 `direction` 会让整个粒子系统不发射（不报错，就是"没效果"）。
	spm.direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	spm.spread = 38.0
	spm.initial_velocity_min = 40.0
	spm.initial_velocity_max = 130.0
	spm.gravity = Vector3(0, -10.0, 0)
	spm.damping_min = 6.0
	spm.damping_max = 16.0
	spm.scale_min = 0.22
	spm.scale_max = 0.55
	spm.particle_flag_align_y = true
	spm.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.35)])
	var sramp := Gradient.new()
	sramp.set_color(0, Color(1.0, 0.96, 0.80, 0.95))
	sramp.set_color(1, Color(0.85, 0.45, 0.20, 0.0))
	spm.color_ramp = _ramp(sramp)
	sparks.process_material = spm
	var spm_mesh := SphereMesh.new()
	spm_mesh.radius = 0.14
	spm_mesh.height = 0.9
	spm_mesh.radial_segments = 5
	spm_mesh.rings = 2
	spm_mesh.material = _additive(Color(1.0, 0.86, 0.6), 5.0)
	sparks.draw_pass_1 = spm_mesh
	root.add_child(sparks)
	sparks.emitting = true

	# ⚠️ 收口挂在**最长**的那一层上（环 0.24 s）：原先挂闪光的 0.16 s，
	# 加了环与火星之后会把它们**中途一起 free 掉**。
	var kt := root.create_tween()
	kt.tween_interval(0.26)
	kt.tween_callback(root.queue_free)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 9.0
	light.omni_range = 90.0
	root.add_child(light)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.18)


## 加力尾焰**形态 A · 巡航焰**：挂在单位身上，跟着走。返回的节点可 set_emitting 开关。
##
## `tint` = 尾焰主色。默认蓝白（原来写死的值）；**阿利宙斯巡航态的 16 个喷口用淡紫**。
## 颜色只在这里给，调用方不用知道色带怎么配。
##
## ⚠️ `amount` 是**每个喷口**的粒子数。默认值 24 是给"整机一个尾焰"调的；
## 多喷口必须**成比例调小** —— 16 个喷口各 34 个就是 544 个加色粒子堆在一起，
## 实测整块后机身糊成一团白（照片为证），不是"引擎在喷"而是"一团云"。
##
## ## 它的读法（与形态 B 的分界，见 `afterburner_dash` 的对照表）
##
## A 是**"引擎在烧"**：一团正在膨胀的气体。所以——
##   - 锥角 7°（散开），粒子**沿龄膨胀**（0.82 → 1.28）；
##   - 沿速度**不**拉伸（是一颗颗圆团，不是一丝一丝）；
##   - 寿命 0.30 s、初速 45–80（慢慢地被推出去）。
## 形态 B（冲刺）把这三条全部反过来。**改这里的曲线之前先看那张表**——
## 两者一旦调成同一种读法，"普通加速 / 辅助冲刺"在屏幕上就再也分不出来了。
static func afterburner(parent: Node3D, offset: Vector3, dir: Vector3, radius := 2.2,
		tint := Color(0.55, 0.80, 1.0), amount := 80) -> GPUParticles3D:
	var p := preload("res://scripts/world/jet_envelope.gd").new()
	p.name = "Afterburner"
	# ⚠️ 24 → 40（轮 14）→ **80**（轮 15）：同时把出生尺寸压小一档（0.5–1.05 → 0.44–0.88）。
	# 原参数下**能数出一颗颗圆球**（billboard 球在轮廓上就是一个个圆），
	# 读起来像"一串泡泡"而不是"一团火"。粒子更多 + 每颗更小 ⇒ 轮廓的锯齿变密，
	# 合并成一整团。**两条要一起看**：只加数量不压尺寸，就是"更多泡泡"。
	p.amount = amount
	p.lifetime = 0.30
	# ---- ⚠️⚠️ `local_coords = **true**`：尾焰必须**跟随机体**（2026-09-25 修）----
	#
	# ## 病征
	# 用户原话：「尾焰粒子特效现在跟不上机体速度」。
	#
	# ## 根因：粒子在世界空间，出生之后**不再跟着喷口走**
	# `local_coords = false` 时，粒子从喷口出生后就**钉在世界坐标**上（它的初速 45–80 m/s
	# 是相对**地面**给的），而喷口以机体速度整体平移：
	#
	#   | | 自己的行程 | 同一 lifetime 内机体走的距离 | 倍数 |
	#   |---|---|---|---|
	#   | 形态 A（0.30 s / 45–80，带阻尼 14–28） | ≈ 5 m | 2414 × 0.30 = **724 m** | 145× |
	#   | 形态 B（0.26 s / 240–280） | ≈ 29 m | 2414 × 0.26 = **628 m** | 22× |
	#   | 马赫环（0.26 s / 120） | ≈ 31 m | 628 m | 20× |
	#
	# 于是本该"贴在喷口上的一团火"被抹成一道**600~700 m 长的稀薄虚线**，
	# 而相机是跟随机体的 ⇒ 屏幕上看到的就是"尾焰被甩在后面、跟不上"。
	# 一个物理帧（60 Hz）机体就走 **40 m**，而形态 A 整团火只有 5 m 长。
	#
	# ## 为什么不能"给粒子加上载机速度"
	# `ParticleProcessMaterial` 的初速是**静态配置**；GPU 粒子也没有"继承节点线速度"
	# 这种机制（世界空间粒子只按自己的初速走）。**局部空间就是那个机制** ——
	# 改成 `true` 之后粒子的坐标在机体空间里，"初速"自动变成**相对喷口**的速度。
	# 真实发动机尾焰本来就是这个意思：气体随载体一起走，只有相对速度那几十 m/s。
	#
	# ## 为什么这条一直没被发现（比结论更值得记）
	# 轮 11 的取证机位 `tools/plume_shot.gd` **逐帧把机体位置回钉**（为了两张图背景一致）。
	# 回钉之后"世界空间"与"局部空间"的读数**逐像素相同** ⇒ 那个机位在原理上**看不见**
	# 任何与"机体在动"有关的缺陷。而参数（束长 ≈ 1.8·v₀/damping = 29 m、
	# 与马赫环 31 m 射程配套）本来就是按**相对**几何调的 —— 换句话说：
	# 改成 `true` 是把屏幕退回**轮 11 验收过的那一版**，不是发明一种新形态。
	#
	# ## 谁**不该**跟着改（同文件里还有 **13 处** `local_coords = false`，逐条核对过，全是对的）
	# `exhaust_smoke()` / `damage_smoke()` / `missile_trail()` / `smoke_burst()` 的烟、
	# `form_flash()` 的脱壳点、以及爆炸 / 命中 / 军刀的火花 —— 它们要的正是"留在世界空间"：
	# 烟柱留在飞过的地方才看得出"一道尾迹"，脱壳的光点留在身后才是"旧壳在脱落"，
	# 火花留在弹着点上才对。**判据是"这个现象是相对喷口的，还是相对世界的"。**
	p.local_coords = true
	p.position = offset
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 7.0
	pm.initial_velocity_min = 45.0
	pm.initial_velocity_max = 80.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.44
	pm.scale_max = 0.88
	pm.damping_min = 14.0
	pm.damping_max = 28.0
	# 起点不是几何意义上的一个点：喷口有直径，粒子从**一个小球壳**里出来，
	# 近处看才不是"从针尖喷出的一根线"。
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.16
	# **越飞越散**（终点 1.28）。与冲刺焰那条收束曲线正好相反 —— 这是两者的第一眼区别。
	pm.scale_curve = _curve([Vector2(0.0, 0.82), Vector2(0.45, 1.00), Vector2(1.0, 1.28)])
	# 乱流让火焰**摆**起来。纯球沿直线排队会像"一串珠子"。
	# ⚠️ 强度压得很低（0.22）：火焰要抖，但不能抖成一条毛毛虫。
	#
	# ⚠️⚠️ **`turbulence_noise_speed` 是 `Vector3`，不是 float**（三个轴各给一条速度）。
	# 与它相邻的 `turbulence_noise_strength` / `turbulence_noise_scale` 都是 float ——
	# 三个名字长得几乎一样、类型却不同，写成标量会直接 `Parse Error`（本项目实测过一次：
	# 同一批 7 处全红）。写法固定为 `Vector3(v, v, v)`（各向同性）。
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.22
	pm.turbulence_noise_scale = 2.2
	pm.turbulence_noise_speed = Vector3(1.1, 1.1, 1.1)
	# 色带：核心近白 → 主色 → 透明。核心那一点点白是"高温"的视觉惯例，
	# 不加会像一根染色的塑料棒。
	var hot := Color(minf(tint.r + 0.28, 1.0), minf(tint.g + 0.26, 1.0),
		minf(tint.b + 0.14, 1.0), 0.70 * tint.a)
	var ramp := Gradient.new()
	ramp.set_color(0, hot)
	ramp.set_color(1, Color(tint.r * 0.45, tint.g * 0.45, tint.b * 0.55, 0.0))
	ramp.add_point(0.35, Color(tint.r, tint.g, tint.b, 0.30 * tint.a))
	pm.color_ramp = _ramp(ramp)
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = radius * 0.62
	m.height = radius * 1.24
	m.radial_segments = 12
	m.rings = 6
	m.material = jet_flame_material(true)
	p.draw_pass_1 = m
	_attach_jet_envelope(p, dir, radius, tint, false)
	parent.add_child(p)
	return p


## 蓄力激光炮的**炮口飞溅**（2026-09-28 用户点名："光束柱炮口需要有大量粒子飞溅"）。
##
## 骨架与 `afterburner()` 同源（局部空间的一团粒子），三处刻意不同：
##
## | | `afterburner()` 尾焰 | 本函数 炮口飞溅 |
## |---|---|---|
## | 锥角 `spread` | 7°（收成一团火） | **58°**（四散） |
## | 初速 | 45~80 m/s | **70~300 m/s**（喷出去的火星） |
## | 数量 | 80 | **320**（用户要"大量"） |
## | 寿命 | 0.30 s | **0.42 s**（飞得更远才散完） |
## | 尺寸随龄 | 0.82 → 1.28（胀） | **1.25 → 0.35**（飞散后收细） |
##
## ⚠️ **`spread` 是本函数存在的全部理由**：拿 `afterburner()` 参数去当炮口火，
## 屏幕上读出来是"炮口挂了一根尾焰"，而不是"柱子的根部在炸开"。
##
## ⚠️ `local_coords = true` —— 与尾焰同一条理由（见 `afterburner()` 的长注释）：
## 机体以 1600 m/s 飞时，世界空间粒子一个 lifetime 就被甩出 600 多米，
## "炮口飞溅"会当场变成"身后一条稀薄的虚线"。局部空间才是"贴在炮口上"。
static func cannon_muzzle(parent: Node3D, offset: Vector3, dir: Vector3, radius := 7.0,
		tint := Color(0.68, 0.32, 1.0), amount := 320) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "CannonMuzzle"
	p.amount = amount
	p.lifetime = 0.42
	p.local_coords = true
	p.position = offset
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 58.0
	pm.initial_velocity_min = 70.0
	pm.initial_velocity_max = 300.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.55
	pm.scale_max = 1.35
	pm.damping_min = 55.0
	pm.damping_max = 110.0
	# 从小球壳里出来（半径给得比尾焰大）：炮口本身有口径，"从针尖喷出一根线"是假象。
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = maxf(radius * 0.30, 0.4)
	pm.scale_curve = _curve([Vector2(0.0, 1.25), Vector2(0.35, 0.90), Vector2(1.0, 0.35)])
	# 乱流：不加就是"一圈整整齐齐的火星"，加一点点才像炸开。
	# ⚠️ `turbulence_noise_speed` 是 Vector3（三个轴各一条），写标量直接 Parse Error。
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.45
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_noise_speed = Vector3(1.6, 1.6, 1.6)
	var hot := Color(minf(tint.r + 0.30, 1.0), minf(tint.g + 0.42, 1.0),
		minf(tint.b + 0.22, 1.0), 0.92 * tint.a)
	var ramp := Gradient.new()
	ramp.set_color(0, hot)
	ramp.set_color(1, Color(tint.r * 0.55, tint.g * 0.55, tint.b * 0.75, 0.0))
	ramp.add_point(0.30, Color(tint.r, tint.g, tint.b, 0.55 * tint.a))
	pm.color_ramp = _ramp(ramp)
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = radius * 0.26
	m.height = radius * 0.52
	m.radial_segments = 6
	m.rings = 3
	m.material = _billboard(Color(tint.r, tint.g, tint.b), 2.4)
	p.draw_pass_1 = m
	parent.add_child(p)
	return p


## 加力尾焰**形态 B · 冲刺焰**：一条被拉直的近白细束。**与 `afterburner()` 是两种东西。**
##
## ## 为什么要分成两种（用户原话）
##
## > "尾焰在正常加速的时候和辅助驾驶模式时候冲刺的尾焰形态不同，要做区分"
##
## 触发它的是"辅助驾驶的冲刺"：平移模式下**点按 Shift** 的闪避冲刺（QB，0.45 s 窗口）
## 与阿利宙斯的**超级加速**。普通加力（不辅助时按住 Shift）走的仍是形态 A。
##
## ## 对照表（这张表就是"形态"二字的内容）
##
## | | 形态 A `afterburner()` | 形态 B 本函数 |
## |---|---|---|
## | 何时 | 普通加力（非辅助 Shift） | 辅助冲刺 QB / 超级加速 |
## | 锥角 `spread` | 7.0°（散成一团） | **1.4°**（收成一条） |
## | 尺寸随龄 | **膨胀** 0.82 → 1.28 | **收束** 1.00 → 0.42 |
## | 沿速度拉伸 | 否（圆团） | **是**（`particle_flag_align_y` ⇒ 一丝一丝） |
## | 材质朝向 | billboard（永远面向相机） | **不 billboard**（椭球真的朝速度方向躺下） |
## | 寿命 / 初速 | 0.30 s / 45–80 | **0.26 s / 240–280** |
## | 粒子数 | 24 | **110**（密到纵向重叠才连成一条） |
## | 束长 ≈ 1.8·v₀/damping | 5 m | **29 m**（与马赫环的 31 m 射程配套） |
## | 乱流 | 开（0.22，让火摆起来） | **关**（一抖末梢就散成碎纸） |
## | 色 | 蓝白（跟着 `tint`） | **近白炽**（更白、更冷） |
##
## 读法上的差别才是重点：A 是"引擎在烧"，B 是"**机子被弹出去**"。
##
## ## ⚠️ 为什么这里**故意不用 billboard**
##
## 第一版给 B 也套了 `_billboard()`，结果 `particle_flag_align_y` **完全没生效**——
## Godot 的 billboard 是在顶点着色器里**根据相机重建基**的，它会把粒子自身的旋转
## 整个覆盖掉。也就是说："沿速度拉成一丝"这件事在 billboard 材质上从原理上做不到。
## 所以 B 用的是**普通加色材质 + 椭球 mesh**：椭球自己躺到速度方向上，
## 侧面看是一段一段的光丝，正面看是一束叠在一起的圆点。
static func afterburner_dash(parent: Node3D, offset: Vector3, dir: Vector3, radius := 2.2,
		tint := Color(0.78, 0.93, 1.0), amount := 200) -> GPUParticles3D:
	var p := preload("res://scripts/world/jet_envelope.gd").new()
	p.name = "AfterburnerDash"
	# ⚠️ 粒子数**必须够大**才连成"一条"。第一版给 32，实测在 118 m 机位下
	# 是一撮各自独立的白色扁片（像碎纸），读不出"丝"——因为相邻粒子之间有空档。
	# 单个粒子长 3–7 m，而 32 个铺在 ~30 m 上 ⇒ 每 1 m 才一个，横向一抖就散开。
	# 110 个 ⇒ 每 0.27 m 一个，纵向**重叠**成一条连续的带。
	# **轮 15：110 → 200**（用户「粒子特效数量太少了」）⇒ 每 0.15 m 一个，重叠更厚。
	p.amount = amount
	# 比 A（0.30 s）更短：粒子在**更窄的一段**里出没，束才"绷得住"。
	p.lifetime = 0.26
	# ⚠️ `true` = 跟随机体。理由与整张对照表见 `afterburner()` 的那段长注释
	#（若用世界坐标，这把 29 m 的束会被机体 628 m / 0.26 s 的行进抹成一条稀薄虚线）。
	p.local_coords = true
	p.position = offset
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 1.4
	# ⚠️ 初速区间**收窄**（第一版 190–300）：区间一宽，粒子的行程就拉开成一片，
	# 侧面看是"一撮散沙"而不是"一条束"。240–280 让它们排在同一段上。
	#
	# ⚠️ 写成 `DASH_BEAM_V0 ± DASH_BEAM_V0_SPAN` 而不是字面量：这个中点**是马赫环
	# 弯曲系数的分母**（`PLUME_RING_BEND_RATIO` 的推导）。两处各写一份字面量，
	# 某天只改了这里、环的系数就静默错配 —— 而且错配的症状只是"环有点飘"，看不出来。
	pm.initial_velocity_min = DASH_BEAM_V0 - DASH_BEAM_V0_SPAN
	pm.initial_velocity_max = DASH_BEAM_V0 + DASH_BEAM_V0_SPAN
	pm.gravity = Vector3.ZERO
	# 出生尺寸比 A 还小一档：细，才是"束"。
	pm.scale_min = 0.70
	pm.scale_max = 1.06
	# ⚠️⚠️ **damping 决定"束有多长"** —— 这条是量出来的，不是猜的：
	#
	#     束长 ≈ 1.8 · v₀ / damping
	#
	# （v₀=240、damping=55 时实测亮束约 8 m，代入得 1.8·240/55 ≈ 7.9 —— 对得上。）
	# 所以第一版的 70–120 只给出 3–5 m：粒子很快停住堆在喷口，是"一撮羽毛"；
	# 第二版的 40–70 给出 ~8 m，束**短于**马赫环的射程（30 m），
	# 于是屏幕上"一段亮束 + 一串飘在空处的孤环"——环离开了束，就读不出激波串了。
	# 12–20 ⇒ 1.8·260/16 ≈ 29 m，正好与环的 31 m 射程配套。
	pm.damping_min = 12.0
	pm.damping_max = 20.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.10
	# **收束**（1.00 → 0.42）：粒子越远越小 ⇒ 眼睛读成"一条**越拉越细**的直线"。
	pm.scale_curve = _curve([Vector2(0.0, 1.00), Vector2(0.35, 0.78), Vector2(1.0, 0.42)])
	# 沿速度方向拉成丝 —— B 与 A 在像素上最直接的分界。关掉这行，B 立刻退回"一串小球"。
	pm.particle_flag_align_y = true
	# ⚠️ **形态 B 不开乱流**（A 开 0.22）。
	# 乱流给的是"横向位移"，而它的量级与**当时的**速度无关 —— 粒子被 damping 减速之后
	# 速度变小，乱流的横向位移就相对放大，于是束的末梢散成一团。
	# 实测：0.10 强度下末梢横向散开 ±3 m，那些"碎纸片"就是它。B 要"绷直"，所以关掉。
	pm.turbulence_enabled = false
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.96, 0.99, 1.0, 0.92))
	ramp.add_point(0.30, Color(tint.r, tint.g, tint.b, 0.60))
	ramp.set_color(1, Color(tint.r * 0.50, tint.g * 0.55, tint.b * 0.70, 0.0))
	pm.color_ramp = _ramp(ramp)
	p.process_material = pm
	var m := SphereMesh.new()
	# 细长椭球（11:1）：配合 `align_y` 出来的就是"一丝"，而不是"一颗"。
	# 拉得越长，纵向越连贯（粒子之间的空档被丝自己填掉）。
	m.radius = radius * 0.30
	m.height = radius * 3.40
	m.radial_segments = 12
	m.rings = 6
	# ⚠️ 这里**不能**用 `_billboard()`，见函数头那段说明。
	# 能量 3.4 是第二版调上去的：束要"发亮"才压得住后面那串马赫环（否则环比束显眼，读反了）。
	m.material = jet_flame_material(false)
	p.draw_pass_1 = m
	_attach_jet_envelope(p, dir, radius, tint, true)
	parent.add_child(p)
	return p


## 冲刺焰的**马赫环**（激波串）：沿束周期性出现的一圈圈淡青白盘。
##
## ## 为什么形态 B 还需要它
##
## 真实的超音速喷流在喷口后方是一串**钻石状激波**（Mach diamonds）。
## 只给"一条白束"的话，观感是一道**光**，而不是"一柱被喷出去的气"——
## 环把这条束**分段**，眼睛才读得出"它在以极高的速度冲出去"。
##
## ## "一串"是怎么来的（不手写位置）
##
## 靠 `lifetime / amount` 的自然节拍：`amount = 5`、`lifetime = 0.26 s`
## ⇒ 每 **52 ms** 出生一个环；环以 120 m/s 沿束飞出 ⇒ 相邻环间隔约 **6.2 m**。
## `scale_curve` 让每个环自己从 1.0 **张到 1.7**（激波面在扩散）—— 这就是"钻石"的观感来源。
##
## ## ⚠️ 环的三个数必须**互相配套**（这一条是量出来的）
##
##   · **射程** = `initial_velocity × lifetime` = 120 × 0.26 = **31 m**。
##     它必须**约等于束的长度**（束长 ≈ 1.8·v₀/damping ≈ 29 m，见 `afterburner_dash`）。
##     第一版环的射程是 240×0.34 = 82 m，而束只有 8 m —— 屏幕上读到的是
##     "一段亮束 + 远处几个孤零零的环"，环一旦离开束，激波串的读法就没了。
##   · **节拍** = `velocity × lifetime / amount` = 6.2 m。它必须**略大于环自身的直径**
##     （2·radius·scale·曲线峰值 = 2·2.4·0.66·1.7 ≈ 5.4 m），否则相邻环互相叠住，
##     一团白糊 —— 看不到"分界"就等于没有环。
##   · **直径** 5.4 m vs 束的粗细 1.4 m ≈ 3.9 倍：环比束粗，才读得成"一圈箍在束上"。
##
## ## ⚠️ 别把环做得比束还显眼
##
## 第一版给的是 `radius*0.85~1.15`、曲线张到 2.2 —— 单环直径到 12 m，比机体还大，
## 屏幕上一排竖白椭圆，读成"机尾掉了几个呼啦圈"，而且把束整个盖住了
## （**主次颠倒**：环是给束分段的配角）。现在是 `radius*0.42~0.66`、曲线张到 1.7。
##
## ⚠️ 它与 `afterburner_dash` 同点、同向，**必须同开同关**：
## 只亮环会像"机尾掉了几个呼啦圈"，只亮束则退化成一道光。
static func dash_rings(parent: Node3D, offset: Vector3, dir: Vector3, radius := 2.2,
		amount := 5) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "DashRings"
	p.amount = amount
	p.lifetime = 0.26
	# ⚠️ `true` = 跟随机体。环是**束的分段标记**（射程 31 m 与束的 29 m 配套，见函数头），
	# 用世界坐标会被 628 m / 0.26 s 的机体行进甩成"机尾后面几个孤立的环"。
	p.local_coords = true
	p.position = offset
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 0.0
	# 120 m/s（第一版 240）：**射程要跟着束走**，见函数头"三个数互相配套"。
	# ⚠️ 走常量而不是字面量：它是 `PLUME_RING_BEND_RATIO` 的**分子**（见那一处的推导）。
	pm.initial_velocity_min = RING_V0
	pm.initial_velocity_max = RING_V0
	pm.gravity = Vector3.ZERO
	# mesh 是半径为 1 的薄盘，尺寸全由 scale 给 ⇒ `radius` 参数直接控制环的大小。
	# ⚠️ 这里的**倍率就是"环有多大"**（见函数头那段：第一版太大、主次颠倒）。
	pm.scale_min = radius * 0.42
	pm.scale_max = radius * 0.66
	pm.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(0.45, 1.35), Vector2(1.0, 1.7)])
	# 盘的轴（Y）对齐速度 ⇒ 盘面垂直于束。没有这行，环会**侧躺**在束上。
	pm.particle_flag_align_y = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.86, 1.0, 0.0))
	ramp.add_point(0.18, Color(0.72, 0.92, 1.0, 0.32))
	ramp.set_color(1, Color(0.55, 0.80, 1.0, 0.0))
	pm.color_ramp = _ramp(ramp)
	p.process_material = pm
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	# 极薄：环要读成"一圈"，厚了就变成"一个饼"。
	m.height = 0.07
	m.radial_segments = 16
	m.rings = 1
	# 亮度给得很低：一圈叠一圈，单个亮就会糊成一团白雾，
	# 那正好把"分段"这件事抹掉（环的意义全在分界上）。
	# ⚠️ 1.05 / 峰值 0.32 是第三版：第二版的 0.80 / 0.22 实测在屏幕上只剩两个小竖条，
	# 那就是"环太小 + 太暗 + 太稀"三重叠加，和"没有环"没区别。
	m.material = _additive(Color(0.70, 0.90, 1.0), 1.05)
	p.draw_pass_1 = m
	parent.add_child(p)
	return p


# ============================================================ 尾焰的横风形变（轮 17）

## 冲刺焰（形态 B）的**轴向特征速度**：`initial_velocity_min/max` 的中点（240–280）。
## 抽成常量只为一件事：让**马赫环该弯多少**能从它推出来，而不是另写一个魔数
##（见 `PLUME_RING_BEND_RATIO`）。`DASH_BEAM_V0_SPAN` 是区间半宽。
const DASH_BEAM_V0 := 260.0
const DASH_BEAM_V0_SPAN := 20.0

## 马赫环的轴向速度（`dash_rings` 里的 120，两头一样 ⇒ 没有区间）。
const RING_V0 := 120.0

## 马赫环拿到的横风加速度 = 束的 × 这个系数。
##
## ## 为什么不能"同点同向"就完事
## 环是**束的分段标记**（射程 31 m 与束长 29 m 配套，见 `dash_rings` 函数头）。
## 横风给的是**加速度**，而横向偏移随轴向距离的公式是 `½·g·s²/v²` ——
## **v 在分母上**。环的轴向速度只有束的 120/260 ≈ 0.46 倍，同一个 `g` 下
## 它在同一段轴向距离上会被吹歪 `1/0.46² ≈ 4.7` 倍 ⇒ 环直接飞出束外。
## 屏幕上读到的是"一段弯束 + 旁边一串孤零零的环"，激波串的读法当场没了
##（这正是 `dash_rings` 函数头记着的老毛病，只是这次换了个成因）。
##
## ## 系数怎么推
## 让"横向偏移随轴向距离 s 的曲线"两边一致：
##   `½·g_束·s²/v_束² = ½·g_环·s²/v_环²`  ⇒  `g_环 = g_束 · (v_环 / v_束)²`
## 代入 120 / 260 ⇒ **0.213**。写成**从常量推出来的表达式**而非 0.213 这个数：
## 以后谁调了束或环的速度，这里自动跟着走。
const PLUME_RING_BEND_RATIO := (RING_V0 / DASH_BEAM_V0) * (RING_V0 / DASH_BEAM_V0)

## `set_plume_bend()` 的**跳写阈值**（m/s²）。
## `gravity` 一变，GPU 粒子那一整批 uniform 就要重传 —— 每帧给 30 多个材质
## 刷同一个值（哪怕只差 0.001）是纯浪费，而屏幕上完全看不出来。
const PLUME_BEND_EPSILON := 0.5


## 把**相对气流**投影成**垂直于喷口轴**的那一半（"横风"）。
##
## ## 这是干什么用的（用户原话）
##
## > "在向着不同方向冲刺的时候尾焰能不能别那么直，来点物理形变"
##
## ## 病根：`local_coords = true` 是一把双刃剑
##
## 轮 15 把尾焰改成局部空间（理由见 `afterburner()` 那段长注释）之后，
## 尾焰**贴着机体**了 —— 但它同时变成"永远沿机体本地 +Z 直直射出的一根锥"：
## 侧向 / 向上冲刺时，屏幕上那条焰仍然笔直拖在机尾，**看不出"我在往哪个方向冲"**。
##
## 真实的物理是：喷口轴**固定在机体上**（气确实沿轴出去），
## 但机体坐标系里的**相对气流**（"横风"）会把焰往气流下游吹 —— 越远越弯。
## 所以病不是"方向错了"，而是**缺了这层形变**。
##
## ## 为什么用 `gravity` 而不是"把发射器转一个角度"
##
## `gravity` 是**均匀加速度**：对刚出喷口的粒子几乎没影响、对老粒子影响 ∝ t²。
## ⇒ 焰的根那段**仍然贴着喷口轴**，越往外越被吹弯 —— 这正是"**弯曲**"。
## 而旋转发射器只会得到"一条被扳歪的**直**锥"：用户要的"别那么直"没做到，
## 而且焰根会从喷口上翘起来，像喷口装歪了。
##
## ## 为什么只取横分量（沿轴的那一半**故意丢掉**）
##
## 沿轴的风（顺飞时的迎面气流）只会**压缩 / 拉长**焰长，而焰长是本项目量出来的：
## 束长 ≈ 1.8·v₀/damping ≈ 29 m，且与马赫环 31 m 的射程**配套**
##（见 `afterburner_dash` / `dash_rings` 的函数头）。
## 让速度偷偷改焰长会把那套标定整个掀掉 ⇒ 只留垂直于喷口轴的分量。
##
## 附带的好处：**直着往前冲时横分量本来就是 0** ⇒ 焰仍然是直的（符合直觉，
## 也意味着"这次的改动不会动到顺飞时那条验收过的焰"）。
##
## ## 边界
## `axis_local` 给零向量（将来喷口轴做成逐口的表、某一项漏填）时兜底到 +Z：
## `normalized()` 对零向量返回零向量，若不兜底，`wind - 0` 会变成"整矢量都算横风"，
## 在顺飞时凭空弯一下 —— 一个只在异常数据下出现的假动作，比直接兜底难查得多。
static func plume_bend_vector(wind_local: Vector3, axis_local: Vector3) -> Vector3:
	var a := axis_local.normalized()
	if a.length_squared() < 0.5:
		a = Vector3(0, 0, 1)
	return wind_local - a * wind_local.dot(a)


## 把算好的**横向加速度**写进某个尾焰发射器。返回是否真的写了（诊断 / 断言用）。
##
## ⚠️ **发射器与机体同基**：`afterburner()` / `afterburner_dash()` / `dash_rings()`
## 都没转过发射器节点（只设了 `position`），所以"机体本地的横风"可以直接当
## "发射器本地的 gravity"用。将来若按喷口轴旋转发射器（佩涅罗佩那两个口的
## 真实朝向见 `FlightBody.PLUME_AXIS` 的注释），这里要跟着做一次基变换。
## 就地把它钉住比"以后记得改"可靠。
static func set_plume_bend(p: GPUParticles3D, bend: Vector3) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	var pm := p.process_material as ParticleProcessMaterial
	if pm == null:
		return false
	if pm.gravity.distance_to(bend) < PLUME_BEND_EPSILON:
		return false
	pm.gravity = bend
	return true


## ## 谁**不**吃这层形变（三处，都是"故意的"）
##
##   · `exhaust_smoke()` 尾气 —— 它是 `local_coords = **false**`（世界空间）。
##     机体以 1000+ m/s 飞走，烟出生就落在原地 ⇒ 屏幕上它**本来就是"被甩在身后的
##     一串烟"**，方向感已经由"世界空间"这件事给足了。再给世界空间的粒子喂一个
##     机体本地的 `gravity` 是**坐标系错误**（相机会看到烟往一个凭空的方向斜着掉）。
##   · `nozzle_glow()` 光晕 —— 一片贴在喷口上的 billboard 圆盘，没有长度可言。
##   · `missile_trail()` / `damage_smoke()` / `smoke_burst()` —— 不是尾焰，不参与。


## 尾气（推进器喷出的**烟**）：**透明、暗色、不发光的烟雾**
## （用户指定："尾气是透明烟雾暗色，不是紫色"）。
##
## ⚠️ 和 `afterburner()` 的区别**不只是颜色，而是混合模式**：
##   - 尾焰（afterburner）：`BLEND_MODE_ADD` + 自发光 —— 越叠越亮，是"火"；
##   - 尾气（这个）：普通 alpha 混合 + `energy = 0` **不自发光** —— 越叠越暗，是"烟"。
## 用加色去做烟，**颜色调得再暗也只会把背景照亮**，看上去仍然是发光的，只是深一点的紫。
## 材质配方与 `damage_smoke()` 保持一致，这样两种烟在画面里是同一种质感。
##
## ⚠️ 它也**不吃** `SuitProfile.engine_plume_color`：那个颜色只管喷口的**光晕**
## （淡紫），尾气是暗灰 —— 两者是两种东西，混用会把烟染成紫的。
static func exhaust_smoke(parent: Node3D, offset: Vector3, dir: Vector3, radius := 1.4,
		amount := 20) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "ExhaustSmoke"
	p.amount = amount
	p.lifetime = 0.14
	p.local_coords = true
	p.position = offset
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 1.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 16.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.damping_min = 3.0
	pm.damping_max = 7.0
	# 从喷口的一个**小面**上冒出来。点发射会让 16 个喷口的尾气都变成"一根细线"。
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.5
	# **随龄膨胀**（0.85 → 1.65）：烟离开喷口之后会散开，这是它与尾焰最明显的区别。
	# 静态尺寸的烟永远像"一串灰球挂在机尾"。
	pm.scale_curve = _curve([Vector2(0.0, 0.85), Vector2(0.40, 1.15), Vector2(1.0, 1.65)])
	# Keep only a brief attached haze; no independently twisting smoke strands.
	pm.turbulence_enabled = false
	pm.turbulence_noise_strength = 0.0
	pm.turbulence_noise_scale = 1.8
	pm.turbulence_noise_speed = Vector3(0.8, 0.8, 0.8)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.17, 0.16, 0.19, 0.16))
	ramp.set_color(1, Color(0.06, 0.06, 0.07, 0.0))
	pm.color_ramp = _ramp(ramp)
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = radius * 0.6
	m.height = radius * 1.2
	m.radial_segments = 5
	m.rings = 3
	m.material = _soft_smoke_mat()
	p.draw_pass_1 = m
	m.radial_segments = 12
	m.rings = 6
	p.material_override = cinematic_smoke_material()
	parent.add_child(p)
	return p


## 烟雾用的柔边材质：**暗色、不发光、普通 alpha 混合**，边缘用径向渐变化开。
##
## ⚠️ 直接拿球体当烟会是**硬边圆盘**（近处看就是一枚"黑硬币"，实测）。
## 用 `GradientTexture2D` 的径向填充当遮罩把边缘淡出，才像烟。
## `energy = 0` 是关键：一发自发光就变回"火"，那就不是烟了。
##
## ---- 2026-09-21：改成 **static 缓存**（只建一份）----
##
## 原因：导弹尾迹也改用它了，而全弹发射一次要建 **100 发**尾迹。
## 逐发新建一个材质 + 一张 48×48 的 `GradientTexture2D` 是纯浪费 ——
## 而烟的外观在三种用法（尾气 / 尾迹 / 一次性烟团）里**本来就是同一份配方**。
##
## ⚠️ **它是共享的，调用方只许把它挂到 mesh 上，不许就地改它**。
## 将来若要给某一种烟单独换外观（比如"受损黑烟再黑一点"），
## **加参数另开一份缓存**，不要 mutate 返回值 —— 那会把另外两种烟一起改掉。
##
## ---- 2026-09-28：**尾迹已迁出**，改用 `_trail_smoke_mat() ----
##
## 用户（2026-09-28）：「浮游导弹的尾迹烟雾还是不够厚，现在看还是没有体积感」。
## 根因就在本函数下面那两行开关（`SHADING_MODE_UNSHADED` + `BILLBOARD_ENABLED`）——
## 它们对**尾气 / 一次性烟团 / 受损黑烟**是合适的（那三种场合要读的是"**一片**烟"），
## 但对**尾迹**不合适（尾迹要读的是"**一根有造型的烟柱**"）。
##
## **按本函数注释里早就写好的规矩办：另开一份缓存，不动这一份。**
## ⇒ `exhaust_smoke()` / `smoke_burst()` / `damage_smoke()` 三处调用**逐位不变**，
##    `suite_missile_smoke` 里针对它们的断言没有一条需要改口径。
static var _smoke_mat_cache: StandardMaterial3D = null


static func _soft_smoke_mat() -> StandardMaterial3D:
	if _smoke_mat_cache != null:
		return _smoke_mat_cache
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_color = Color(1, 1, 1, 0.55)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 48
	tex.height = 48
	m.albedo_texture = tex
	# ⚠️ **必须有这一行**：粒子的颜色来自 `process_material.color_ramp`，
	# 而它只有在这个开关打开时才会乘进 albedo —— 漏了的话烟会渲染成材质的**白色**，
	# 变成一团白棉花（实测踩过）。`_additive()` 里也有同一行，是同一件事。
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	_smoke_mat_cache = m
	return m


## 尾迹粒子表面用的贴图：**絮状斑驳 + 上下柔边**（工程规矩：一张美术资源都不带）。
##
## ## 为什么要换掉"径向渐变圆盘"
## `_soft_smoke_mat()` 用 `GradientTexture2D` 的**径向填充**做柔边遮罩 —— 那是给
## **quad** 用的（u/v 就是屏幕的横竖两个方向，径向渐变正好是个柔边圆）。
## 但球体的 UV 是**球面展开**（u 绕经度一圈、v 从北极到南极）：
##   · 径向圆盘贴上去会变成"一堆竖条纹"；
##   · 而且它**一点都柔不了边**（理由见下面 ②）。
## ⇒ 换成"絮状噪声"，叠加后读成"烟絮"而不是"光滑泡泡"。
##
## ## 为什么不是直接用 `NoiseTexture2D`
## 需求有两条，`NoiseTexture2D` 只满足①：
##   ① **表面有絮状斑驳** —— 否则叠加出来是一串光滑泡泡；
##   ② **球的上下边缘要淡出** —— ⭐ 这是"珠串感"的解药。
## 实测（补丁 A 之后）：球成了**硬边实心球**，近景读成"一串珠子"，不像烟。
## 根因：**球的屏幕轮廓（法线 ⟂ 视线处）不是 UV 边界**，贴图在原理上够不着它。
## 唯一能借的上力是 **v（纬度）方向** —— 相机水平看球时，**纬度的两极正好落在
## 球的上下边缘**。所以这里自己在 RGBA 的 **alpha 通道**上做 v 方向淡出：
##   `vfade = smoothstep(0,0.20,v) × smoothstep(1,0.80,v)` ⇒ 两端各柔掉 20%。
## （更彻底的做法：自定义 shader 里按视空间 `NORMAL.z` 做 fresnel 淡出，与视角无关。
##   但那要换掉 `StandardMaterial3D`、把整套材质断言重写 —— 本轮不走，记在这里备查。）
##
## ## ⚠️ 三个坑
##   · **噪声平均灰度会乘进 albedo**。纯 0~1 的噪声平均 ≈0.5 ⇒ 烟直接暗一半。
##     所以把范围压到 **0.68~1.0**（平均 ≈0.84）：只做斑驳，不压亮度。
##   · **u 是"绕球一圈"**：直接拿 (x,y) 采 2D 噪声会在球上留一条竖直硬缝。
##     把 u 映射到**圆柱面**上再取 3D 噪声 ⇒ 天然无缝（这是标准做法）。
##   · 必须在**手拼图**这一步就 static 缓存住：全弹发射 100 发只触发**一次**生成，
##     否则那一帧要跑 100 次 96×96 的逐像素循环。
static var _smoke_grain_cache: Texture2D = null


static func _smoke_grain_tex() -> Texture2D:
	if _smoke_grain_cache != null:
		return _smoke_grain_cache
	const N := 96
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.18
	noise.fractal_octaves = 3
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		var v := float(y) / float(N - 1)
		# v = 北极 → 南极。两端各柔掉 20%，中段完全不透明。
		var vfade := smoothstep(0.0, 0.20, v) * smoothstep(1.0, 0.80, v)
		for x in N:
			# u 绕球一圈 ⇒ 映射到圆柱面采样，保证经度接缝无缝。
			var ang := float(x) / float(N) * TAU
			var n := noise.get_noise_3d(cos(ang) * 6.0, sin(ang) * 6.0, v * 6.0) * 0.5 + 0.5
			var g := lerpf(0.68, 1.0, n)
			img.set_pixel(x, y, Color(g, g, g, vfade))
	_smoke_grain_cache = ImageTexture.create_from_image(img)
	return _smoke_grain_cache


## 尾迹专用烟材质：**受光 + 真 3D 球**。（与 `_soft_smoke_mat()` 是两份独立缓存。）
##
## ## 为什么尾迹不能再用 `_soft_smoke_mat()`
## 用户原话的后半句是「**没有体积感**」—— 那是一个**质**的问题，与前半句「不够厚」（量）
## **正交**：往量上加料（粒子数 / 尺寸 / alpha，2026-09-22 那一轮全加过了）解决不了它。
##
## 根因是 `_soft_smoke_mat()` 上那两行开关**互相抵消**：
##
##   | 开关 | 单独看是对的 | 合起来发生了什么事 |
##   |---|---|---|
##   | `SHADING_MODE_UNSHADED` | "烟不是火"⇒ 不给自发光 | 球面**没有明暗梯度** |
##   | `BILLBOARD_ENABLED`    | 柔边圆盘要正对相机 | 球体被**拍平成一枚圆盘** |
##
## 于是不管 `_trail_mesh()` 给的是不是 `SphereMesh`，屏幕上永远是
## **朝向一致 + 颜色一致 + 边缘一致**的一枚柔边圆斑。一堆这样的圆斑叠起来，
## 只可能读成"一层薄雾 / 一张贴纸"——**体积感的物理来源（同一物体上的明暗层次），
## 在这两行开关下根本不存在**。所以这是**原理性**问题，不是参数不够大。
##
## ## 实测证据（`tools/probe_trail_volume.gd`）
## 把 `world.sun.visible` 关掉，同一帧抓图：
##   · 老材质（unshaded）⇒ 尾迹像素 **逐位不变**（`diff = 0`），而地面整个黑掉；
##   · 新材质（受光）  ⇒ 尾迹像素随主光变化 —— 这是"它是个东西"的最小证据。
##
## ## 这份配方做了三件事
##   ① `SHADING_MODE_PER_PIXEL` —— 每颗球有自己的迎光面 / 背光面。
##      这是体积感的**第一来源**，也是唯一**可证伪**的来源（判据：开关主光必须变）。
##   ② `BILLBOARD_DISABLED` —— 球真的是球。粒子在世界空间里的朝向是固定的，
##      相机绕着它转时明暗会重排 ⇒ 读成"它是个东西"而不是"它是个贴片"。
##   ③ 絮状噪声替掉径向圆盘（理由见 `_smoke_grain_tex()`）。
##
## ## ⚠️ 仍然守住的契约（一条都没松）
##   · `BLEND_MODE_MIX`（不是加色）+ **不自发光** —— 这是"烟"与"火"的分界，
##     `suite_missile_smoke` 的三条守卫继续有效。夜战里它的亮度来自**场景主光与环境光**，
##     而"能不能被照亮"正是本轮要买的东西。
##   · `vertex_color_use_as_albedo = true` —— 否则 `color_ramp` 被忽略、烟渲染成白色。
##   · `cull_mode = CULL_DISABLED` —— 粒子是空壳，只画正面会很假。
##
## ## 性能
## 受光 + alpha 混合 ⇒ 每像素要算光照、且拿不到 early-Z，比 unshaded 贵。
## 对策有两条（都在别处）：
##   · `_trail_mesh()` 的细分**故意开得很低**（烟柱在画面里本来就会被糊掉）；
##   · LOW 档（全弹 100 发）的粒子数由 `suite_missile_smoke._budget()` 那条红线单独看着。
static var _trail_smoke_mat_cache: StandardMaterial3D = null


static func _trail_smoke_mat() -> StandardMaterial3D:
	if _trail_smoke_mat_cache != null:
		return _trail_smoke_mat_cache
	var m := StandardMaterial3D.new()
	# ① 受光 —— 与 `_soft_smoke_mat()` 的分界就在这里。
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# ② 真 3D 球，不拍平。
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	# ---- 近距离淡出（★63-21）：与烟带层**同一条斜坡**（锚点在 `missile_ribbon.gd`）----
	#
	# ⚠️ 这份材质**只有 `_trail_mesh()` 一个用户**，而 `_trail_mesh()` **只有
	# `missile_trail()` 一个用户** ⇒ 给它加淡出**零连带**：尾气 / 一次性烟团 /
	# 受损黑烟走的是另一份 `_soft_smoke_mat()`，一个字节都不动。
	# ⚠️ 也必须**逐片元**：一柱粒子沿弹道铺开几百米，只有逐片元才能做到
	# "贴着镜头那几颗淡、远处那几颗照旧"。
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = _RIBBON.FADE_NEAR_M
	m.distance_fade_max_distance = _RIBBON.FADE_FULL_M
	# ---- 亮度标定：这两个数是**实测**标出来的，不是拍的 ----
	#
	# 补丁 A 做成"纯受光"之后，真机量测（`tools/probe_trail_volume.gd` + 像素统计）：
	#   烟平均亮度 **32.8**、B/R **1.69**（偏蓝紫）；同帧**无烟处地面只有 17.4**。
	# 两个数在物理上都站得住：NIGHT 预设是 `sun_color = (0.62, 0.72, 1.0)`（冷蓝）
	# + `sun_energy = 0.44`（很低）⇒ "白烟在月光下就是又暗又蓝"，一点没错。
	# ⚠️ **但观感不对**：用户要的是"厚"，而 1.9× 地面的亮度在 900p 里几乎读不出来。
	# （老版本 UNSHADED 是 **136.8** —— 不吃光反而比地面亮 **7.9 倍**。那正是"贴纸"的
	#   破绽所在，但它至少醒目。所以本轮不是"回到老版本"，是**两个都要**。）
	#
	# ⇒ 一半靠 HDR albedo、一半靠一点点 emission，各司其职：
	#   · `albedo_color` 走 **HDR（> 1）**：受光项整体 ×≈2.07，**明暗幅度也跟着 ×2.07**
	#     ⇒ 亮度和层次**同向**变化，不会被稀释（这是它比"加 emission"更值的地方）；
	#     顺便略微偏暖 (2.20, 2.12, 1.92)，把月光的蓝往中性拉一点。
	#   · `emission` 只补底（见下），不抢层次。
	m.albedo_color = Color(2.20, 2.12, 1.92)
	m.albedo_texture = _smoke_grain_tex()
	m.vertex_color_use_as_albedo = true
	# ⚠️ 这里**开了 emission**，与 `_soft_smoke_mat()` 的 "energy = 0" 不一致 —— 故意的。
	# 而且"烟不是火"那条分界并没有破：
	#   · 能量 **0.15**（老版加色 billboard 是 `energy = 2.0`，差一个数量级以上）；
	#   · 颜色 **中性偏冷 (0.90, 0.90, 0.93)**，不是暖橙 —— 暖色才读成"火"。
	#
	# ⚠️ 0.15 是**标定出来的**，不是拍的。固定口径（`a_side`，ROI x[560,1040]
	# y[400,500]，亮度阈 72 分位）的实测表：
	#     before（UNSHADED）                    82.0
	#     after （纯受光，albedo 1.0）          23.8
	#     after2（albedo 2.20 + emission 0.28）121.7
	#     calib （albedo 2.20 + emission 0  ）  69.8
	#   ⇒ emission 0.28 单独贡献 **+51.9**；要落在 ~95 就取 0.15。
	#   为什么是"高 albedo + 低 emission"而不是反过来：受光项 69.8 占总亮度 ~73%，
	#   **明暗层次仍然是亮度结构的主体**，emission 只补底、不抢层次。
	# 物理上它对应的是：烟是**半透明体积**，光在内部反复散射 ⇒ 有一个整体亮度底噪，
	# 不会像固体表面那样背光面全黑。少了这一层，夜战里烟就是"只在迎光面出现的暗斑"。
	m.emission_enabled = true
	m.emission = Color(0.90, 0.90, 0.93)
	m.emission_energy_multiplier = 0.15
	# 漫反射、不反光：烟的表面不该有高光（有高光就成了"塑料球"）。
	m.metallic = 0.0
	m.metallic_specular = 0.0
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 不接收阴影：烟不该在自己身上打出投影（那是固体才有的读法）。
	m.disable_receive_shadows = true
	_trail_smoke_mat_cache = m
	return m


## 喷口"常亮"光晕的**共用材质**：自发光 + 面向相机的**柔边圆盘**。
##
## ⚠️ 为什么不是直接用 `QuadMesh`：四边形贴出来是**方块**（用户实测："正方形改成圆形"）。
## 这里用 `GradientTexture2D` 的**径向填充**当遮罩 —— 中心不透明、边缘全透明，
## 于是同一个四边形上画出来就是一个柔边圆。用程序生成、不需要任何贴图文件
## （工程规矩：地形、天空、HUD 全程序化，一张美术资源都不带）。
##
## 为什么要共用一份：16 个喷口的亮度要**一起**随油门变，逐个改材质既慢又容易漏；
## 而且共用能把 draw call 压下来。
static func plume_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	# 亮度：**别给高**。16 个喷口是加色叠加，单个亮一点整体就糊成一片白
	# （第一版 1.5 实测就是一团白，用户要求"光暗一点"）。
	m.emission_energy_multiplier = 0.55
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 柔边圆形遮罩（程序生成）
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	m.albedo_texture = tex
	m.emission_texture = tex
	# 面向相机：从任何角度看都是一个圆盘，而不是一片转过去的板子
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	return m


## 三渲二（批 17/18）：把一份**受光** StandardMaterial3D 切成内置 TOON 着色。
##
## **单一真源** —— 机体（FlightBody 的模型）与踏板（FlightPedal 自带的
## 梅萨/古斯塔夫烤制模型）都从这里走：两边风格必须完全一致，
## 色阶/边缘光参数的任何改动只动这一处。
##
## 只切**受光**材质：FX 的 additive/unshaded（尾焰、爆闪、光晕）靠自发光吃饭，
## 套 TOON 会把光效压暗 —— 这里再兜一道底（unshaded 直接原样返回）。
## 幂等：重复调用结果相同（踏板每次换载人状态都会重建模型再走一遍）。
static func toonify(mat: StandardMaterial3D) -> void:
	if mat == null or mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	# 边缘光：动漫渲染的"描边在光里"那一半（屏幕空间的物理描边在 cel_post）。
	# rim=0.35 压得很低 —— 只在剪影边缘给一圈亮，不抢主光的色阶。
	mat.rim_enabled = true
	mat.rim = 0.35
	mat.rim_tint = 0.55


## 一个喷口的常亮光晕（面向相机的发光圆盘）。`mat` 由 `plume_material()` 建，多个喷口共用。
static func nozzle_glow(parent: Node3D, offset: Vector3, mat: StandardMaterial3D,
		radius := 1.6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "NozzleGlow"
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.material = mat
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = offset
	parent.add_child(mi)
	return mi


## 变形闪光：一颗包住机体的自发光光球（1.1：阿利宙斯 巡航 ↔ 常态 换模型时用）。
##
## 用户要求："在变形切换模型的时候增加闪光特效（遮挡模型，但是不遮挡屏幕，
## 可以只是在模型上覆盖闪光光球）"，随后又补了两条：
##   - **"特效跟着机体走"** → 所以 `parent` 传**机体自己**（不是弹丸容器），
##     且这里是 `top_level = false` 的普通子节点：光球跟着机体一起平飞，
##     不会留在原地变成一个"机体已经飞走了、闪光还在后面"的残影；
##   - **"半径再大一点"** → 半径由调用方给（`FlightBody.model_flash_radius()`，70% → 95%）。
##
## ⚠️ 它**不是全屏白闪**：光球只在世界空间里占机体那么大一块。
## 真正"只存在于机体像素上"的那层遮罩是 `FlightBody._flash_model()`（把模型自己刷白），
## 两层叠起来才是"看得到闪光、但屏幕没被糊住"。
static func form_flash(parent: Node3D, at_local := Vector3.ZERO, radius := 20.0,
		color := Color(0.62, 0.88, 1.0)) -> Node3D:
	var root := Node3D.new()
	root.name = "FormFlash"
	parent.add_child(root)
	root.position = at_local

	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = maxf(radius, 0.5)
	sphere.height = maxf(radius, 0.5) * 2.0
	sphere.radial_segments = 18
	sphere.rings = 9
	var mat := _additive(color, 2.4)
	mat.albedo_color = Color(color.r, color.g, color.b, 0.80)
	sphere.material = mat
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * 0.74
	root.add_child(mi)

	# ---- 剥离粒子：从机体表面向外飘走的光点 ----
	# 变形是"外壳被换掉"，所以要有**东西离开机体**。光球只说明"机体变亮了"，
	# 说不出"旧的壳在脱落"。
	# ⚠️ 它挂在 `root`（跟随机体）下、但 `local_coords = false` ⇒ 出生后留在世界空间，
	# 于是机体往前飞、光点往后拖 —— 这正是"剥离"的读法。
	var peel := GPUParticles3D.new()
	peel.name = "FormPeel"
	peel.amount = 72
	peel.lifetime = 0.50
	peel.one_shot = true
	peel.explosiveness = 0.9
	peel.local_coords = false
	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_sphere_radius = maxf(radius, 0.5) * 0.72
	ppm.direction = Vector3.UP
	ppm.spread = 180.0
	ppm.initial_velocity_min = 12.0
	ppm.initial_velocity_max = 46.0
	ppm.gravity = Vector3(0, -4.0, 0)
	ppm.damping_min = 4.0
	ppm.damping_max = 12.0
	ppm.scale_min = 0.30
	ppm.scale_max = 0.85
	ppm.particle_flag_align_y = true
	ppm.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.30)])
	var pramp := Gradient.new()
	pramp.set_color(0, Color(minf(color.r + 0.3, 1.0), minf(color.g + 0.25, 1.0),
		minf(color.b + 0.15, 1.0), 0.92))
	pramp.set_color(1, Color(color.r * 0.5, color.g * 0.6, color.b * 0.8, 0.0))
	ppm.color_ramp = _ramp(pramp)
	peel.process_material = ppm
	var pm_mesh := SphereMesh.new()
	pm_mesh.radius = 0.22
	pm_mesh.height = 1.10
	pm_mesh.radial_segments = 5
	pm_mesh.rings = 2
	pm_mesh.material = _additive(color, 6.5)
	peel.draw_pass_1 = pm_mesh
	root.add_child(peel)
	peel.emitting = true

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 11.0
	light.omni_range = radius * 5.0
	root.add_child(light)

	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.18, 0.42)
	tw.tween_property(mi, "transparency", 1.0, 0.42)
	tw.tween_property(light, "light_energy", 0.0, 0.30)
	# ⚠️ 收口延到 0.54 s：剥离粒子的 lifetime 是 0.50 s，挂在原来的 0.42 s 上
	# 会把它的最后 0.08 s 削掉 —— 症状是"光点刚要飘远就凭空没了"。
	var kt := root.create_tween()
	kt.tween_interval(0.54)
	kt.tween_callback(root.queue_free)
	return root


## 一大团一次性浓烟（1.1：阿利宙斯"在烟雾中切换形态"用它）。
##
## 和 `damage_smoke` 的区别：这个是**世界空间里放一次就走**的一次性烟团，
## 不挂在单位身上（形态切换的瞬间单位还在动，烟要留在原地，
## 否则烟跟着机体跑，玩家根本看不清"壳是从哪儿掉的"）。
## `life`：这个烟团活多久。默认 2.6 s 是"爆壳"那类场合够用的值；
## ⚠️ **干扰弹要传 ≥ 3.0**（`FLARE_ACTIVE_TIME`）：第十八轮起"干扰弹 = 确定性清屏"，
## 来袭弹会被诱进烟里自爆（`Missile.SMOKE_KILL_RADIUS`）—— 如果烟比有效期先散，
## 玩家看到的就是"提示说在骗弹，可烟早没了"，那是**视觉承诺没兑现**。
##
## `amount`（2026-09-21 追加）：这个烟团放多少粒子。**默认是 `SMOKE_BURST_AMOUNT`＝"一大团"的值**。
## 小规模的场合必须往下调 —— 比如导弹**挂架弹射**的那一小团
## （`MISSILE_LAUNCH_PUFF` = 18，见 `missile_trail` 那一段的说明）和
## **骗弹自爆**叠的那一层（`MISSILE_SMOKE_KILL_PUFF` = 70）。
## ⚠️ 不调就会变成"掩体弹幕顺带把屏幕糊白"：一次扳机 3 发 = 3 × 270 = 810 粒子，
## 而它们要的只是"挂架那儿冒一小股烟"。
##
## 2026-09-25（轮 15）：默认值 150 → **270**，与其余 12 处一样是**一档 ×1.80**。
## 提成常量（而不是继续写字面量）是为了让 `suite_missile_smoke` 那条
## "弹射烟必须远小于默认值"的断言**引用同一个真源** —— 之前它把 150 写死在
## 断言里，本轮的抬升就会让那句说明变成假话（而断言自己仍然绿）。
const SMOKE_BURST_AMOUNT := 270

## Immutable smoke templates, bounded even when callers supply arbitrary scales.
## Lifetime, amount, transform and emission state remain per particle instance.
static var _burst_template_cache: Dictionary = {}
const MAX_BURST_TEMPLATES := 16
static func _smoke_burst_assets(scale: float) -> Array:
	if _burst_template_cache.has(scale):
		return _burst_template_cache[scale]
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 8.0 * scale
	pm.direction = Vector3.UP
	pm.spread = 62.0
	pm.initial_velocity_min = 10.0 * scale
	pm.initial_velocity_max = 40.0 * scale
	pm.gravity = Vector3(0, 5.0, 0)
	pm.scale_min = 3.0 * scale
	pm.scale_max = 9.0 * scale
	pm.damping_min = 4.0
	pm.damping_max = 12.0
	# **随龄膨胀**（0.75 → 1.45）：一大团烟如果没有"越散越大"这一层，
	# 就只是一堆尺寸不同的球各自淡出 —— 缺的正是"云在长"这个动作。
	pm.scale_curve = _curve([Vector2(0.0, 0.75), Vector2(0.35, 1.05), Vector2(1.0, 1.45)])
	# 乱流：这是"浓烟"与"灰球"在近处的分界。强度给到 0.65（本项目最高的一档）——
	# 烟团本来就该是**没有形状**的，越乱越对。速度压低（0.6）让翻涌是"慢滚"而不是"抖"。
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.65
	pm.turbulence_noise_scale = 1.5
	pm.turbulence_noise_speed = Vector3(0.6, 0.6, 0.6)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.55, 0.58, 0.92))
	ramp.set_color(1, Color(0.10, 0.10, 0.12, 0.0))
	ramp.add_point(0.35, Color(0.30, 0.30, 0.34, 0.70))
	pm.color_ramp = _ramp(ramp)
	var m := SphereMesh.new()
	m.radius = 2.0
	m.height = 4.0
	m.radial_segments = 5
	m.rings = 3
	# ⚠️ **必须是 `_soft_smoke_mat()`（普通 alpha 混合），不是 `_billboard()`（加色）。**
	# 这里原先写的是 `_billboard(白, energy = 0)`：`energy = 0` 确实让它"不自发光"，
	# 但**混合模式仍然是加色** —— 而加色 + 再暗的颜色也只会把背景**照亮**，
	# 看上去是一团发光的雾，不是烟。这条判据在 `exhaust_smoke()` 的注释里写得很清楚
	#（原话："用加色去做烟，颜色调得再暗也只会把背景照亮"），2026-09-25 补上这两处漏改。
	m.material = _soft_smoke_mat()
	m.radial_segments = 12
	m.rings = 6
	var epm := ParticleProcessMaterial.new()
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	epm.emission_sphere_radius = 6.0 * scale
	epm.direction = Vector3.UP
	epm.spread = 180.0
	epm.initial_velocity_min = 18.0 * scale
	epm.initial_velocity_max = 55.0 * scale
	# 负得更狠：火星要**掉下来**，才和"一直往上飘的烟"分开读。
	epm.gravity = Vector3(0, -14.0, 0)
	epm.scale_min = 0.35
	epm.scale_max = 0.85
	epm.damping_min = 2.0
	epm.damping_max = 6.0
	epm.particle_flag_align_y = true
	var eramp := Gradient.new()
	eramp.set_color(0, Color(1.0, 0.92, 0.66, 0.95))
	eramp.add_point(0.4, Color(1.0, 0.55, 0.18, 0.80))
	eramp.set_color(1, Color(0.9, 0.25, 0.05, 0.0))
	epm.color_ramp = _ramp(eramp)
	var em := SphereMesh.new()
	em.radius = 0.16
	em.height = 1.1
	em.radial_segments = 5
	em.rings = 2
	em.material = _additive(Color(1.0, 0.72, 0.32), 5.0)
	var assets: Array = [pm, m, epm, em]
	while _burst_template_cache.size() >= MAX_BURST_TEMPLATES:
		_burst_template_cache.erase(_burst_template_cache.keys()[0])
	_burst_template_cache[scale] = assets
	return assets


static func smoke_burst(parent: Node, at: Vector3, scale := 1.0, life := 2.6,
		amount := SMOKE_BURST_AMOUNT) -> Node3D:
	var root := Node3D.new()
	root.name = "SmokeBurst"
	root.top_level = true
	parent.add_child(root)
	root.global_position = at
	# Off-screen one-shot particles may not emit finished; bound both burst creation and lifetime.
	if not preload("res://scripts/world/transient_fx_budget.gd").track(root,maxf(life,.1)+.25,false,&"SmokeBurstBudget"):
		return root

	var assets := _smoke_burst_assets(scale)
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.process_material = assets[0]
	p.draw_pass_1 = assets[1]
	p.material_override = cinematic_smoke_material()
	root.add_child(p)

	# ---- 余烬层：烟团里溅出来的火星 ----
	#
	# ⚠️ **必须在主烟之后 `add_child`**：`suite_missile_smoke._burst_emitter()` 取的是
	# 根节点下**第一个** `GPUParticles3D`（它拿它的 `amount` 去核 `MISSILE_LAUNCH_PUFF`）。
	# 把余烬插到前面，那条断言就会读到余烬的量，症状看起来像"弹射烟团变小了"。
	#
	# ⚠️ 寿命**不能超过主烟**：`root` 挂在主烟的 `finished` 上，主烟一结束整团
	#（含余烬）就被 `queue_free`。余烬设得更长只会被**腰斩**，
	# 看起来像"火星飞到一半凭空消失"。
	#
	# 它给的是"这团东西是**热的**"这一条信息 —— 只有烟的话，
	# 一次爆炸和一次扬尘在画面上是同一件事。
	var embers := GPUParticles3D.new()
	embers.name = "SmokeEmbers"
	# 1/8 的量、上限 16 颗：烟是主角，火星只是暗示。
	embers.amount = clampi(amount / 8, 4, 16)
	embers.lifetime = minf(life * 0.6, 1.4)
	embers.one_shot = true
	embers.explosiveness = 1.0
	embers.local_coords = false
	embers.process_material = assets[2]
	embers.draw_pass_1 = assets[3]
	root.add_child(embers)

	p.finished.connect(root.queue_free)
	p.emitting = true
	embers.emitting = true
	return root


## 受损黑烟：血量低时开启。
static func damage_smoke(parent: Node3D, offset: Vector3, scale := 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "DamageSmoke"
	p.amount = 88
	p.lifetime = 2.2
	p.local_coords = false
	p.position = offset
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 22.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 18.0
	pm.gravity = Vector3(0, 3.0, 0)
	pm.scale_min = 1.5 * scale
	pm.scale_max = 4.0 * scale
	pm.damping_min = 2.0
	pm.damping_max = 6.0
	# 从机体的**一小片体积**上冒（而不是一个点）：受损烟是从装甲缝里渗出来的，
	# 点发射会让它像"机身上插了一根烟囱"。
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 2.2 * scale
	# 随龄膨胀 + 乱流：和 `smoke_burst` 同一套读法（"烟是没有形状的"），
	# 只是强度低一档 —— 它是常驻的，开着加力时还要和尾焰抢注意力。
	pm.scale_curve = _curve([Vector2(0.0, 0.80), Vector2(0.45, 1.15), Vector2(1.0, 1.50)])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.45
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_noise_speed = Vector3(0.7, 0.7, 0.7)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.16, 0.16, 0.18, 0.85))
	ramp.set_color(1, Color(0.05, 0.05, 0.06, 0.0))
	pm.color_ramp = _ramp(ramp)
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 5
	m.rings = 2
	# 与 `smoke_burst` / `exhaust_smoke` 同一条腿（详见 `smoke_burst` 里那段说明）：
	# 受损黑烟如果用加色画，夜里会变成"机体后面挂着一团发光的雾"。
	m.material = _soft_smoke_mat()
	p.draw_pass_1 = m
	m.radial_segments = 12
	m.rings = 6
	p.material_override = cinematic_smoke_material()
	parent.add_child(p)
	return p


## 导弹**挂架弹射**那一小团烟的粒子数（DESIGN §4.4「另加两处小东西」①）。
## ⚠️ 远小于 `smoke_burst` 的默认值 150 —— 见那个函数 `amount` 那一段的账。
const MISSILE_LAUNCH_PUFF := 18

## 被干扰弹骗走的弹，在烟里自爆时**多叠的那一层烟**的粒子数（DESIGN §4.4 另加②）。
## 比弹射那团大、比一整团掩体烟小：它的作用是"把已有的烟搅大一圈"，
## 而不是"另放一团新烟"（那一团本来就在场上了）。
const MISSILE_SMOKE_KILL_PUFF := 70

## 尾迹用的球体**只建一份**：它每一发都一样（尺寸靠 `pm.scale_*` 给），
## 而全弹发射一次要建 100 个 —— 共用省掉 100 次 mesh 分配。
static var _trail_mesh_cache: SphereMesh = null


static func _trail_mesh() -> SphereMesh:
	if _trail_mesh_cache != null:
		return _trail_mesh_cache
	var m := SphereMesh.new()
	m.radius = 0.9
	m.height = 1.8
	# ⚠️ 2026-09-28：细分 **5×2 → 8×6**，是跟着"材质改成受光"一起来的，不是随便加的。
	# `rings = 2` 在 unshaded 下看不出来（球反正是被拍平成圆盘的），
	# 一旦受光，球面就只有两层纬线 ⇒ 明暗梯度会**折断成一块块的棱**，像个多面体。
	# 8×6 ≈ 96 三角/粒子（老值 5×2 ≈ 20）—— 这是本轮唯一涨了的地方，理由在下面。
	m.radial_segments = 8
	m.rings = 6
	m.material = _trail_smoke_mat()
	_trail_mesh_cache = m
	return _trail_mesh_cache


## 尾迹档位的**每发**粒子数（DESIGN §4.4「性能」）。**这两个数是唯一的真源** ——
## `Missile.trail_amount()` 读它们，别在弹丸层再写一份。
##   - `HIGH` = 80：正常扳机 3 发 ⇒ 合计 240；
##   - `LOW`  = 28：全弹发射 100 发 ⇒ 合计 2800。
## ⚠️ 老值 90 在 100 发时是 **9000 粒子/秒**，叠上爆炸 / 尾焰 / 受损黑烟会打掉帧率。
## 而弹幕的观感本来就是"一整片烟"，单发看得清与看不清并不影响它。
## 2026-09-22 增厚：70 → 80；LOW 不动（100 × 28 = 2800 < 3000）。
## "厚"的主力不在粒子数 —— 在几何（scale / spread / 随龄扩散 / 色带加浓）。
##
## ---- 2026-09-28（轮 40）：**这两个数一个都没动**，长度改由 `MissileRibbon` 负责 ----
##
## 需求原话：「把浮游飞弹的飞行轨迹加长，现在的浮游飞弹的拖尾太短了，
##            拖尾要和飞行轨迹一样长」。
##
## 实测（`tools/probe_missile_ballistic.gd`，逐帧差分 `global_position`）：
##     2 km 贴身交战（弹道 3052.9 m / 1.98 s）
##     12 km 交战（工程靶机基准 11960 m）⇒ 弹道 **16651.7 m / 5.35 s**
## 而轮 39 砍出来的柱长只有 **650 m** ⇒ 12 km 交战时粒子只盖住弹道的 **4%**，
## 屏幕上就是"弹飞过去了，后面没留下什么"。
##
## ⚠️ **但"盖住整条弹道"这件事不归粒子管。** 粒子尾迹的账是死的：
##
##     柱长 = 世界速度 × lifetime          间距 = 柱长 ÷ amount
##
## 要让**粒子柱**盖住 16.7 km 且不留缝（间距 ≤ 球出生直径 9.95 m），一次扳机 3 发
## 需要 **约 5200 颗** —— 而全弹发射 100 发才 2800。那是量级之外，往 `amount`
## 上加料解决不了。所以轮 40 另加了 `MissileRibbon`（沿弹道的连续烟带，
## **没有"间距"这个量**、长度只取决于采样点数），**长度整件归它**
##（用户 2026-09-28 选定：「烟带 + 烟团都做」）。
##
## **粒子这一层继续只管"近端要多厚"** —— 于是这里的两个数、两条红线
##（`3 × HIGH < 300`、`100 × LOW < 3000`）本轮**一个字都没改**：
##
##     间距 = 4062 × 0.16 ÷ 80 = **8.12 m** < 球出生直径 9.95 m ⇒ 无缝（轮 39 原样）
##     柱长 = 4062 × 0.16       = **650 m**  < 900（`_density()` 守着，也没动）
##
## ★ 轮 63-9 · D5 起这一对**同比例降到 0.128 / 64**：间距 **8.124 m（逐位不变）**、
##   柱长 **520 m** ⇒ 两条红线仍然全过（见上面 `TRAIL_HIGH_AMOUNT` 那段）。
##
## ⚠️ **别为了"更长的拖尾"回来加这两个数。** 长度已由烟带满足；而粒子柱拉长
## 必然撞上 `_density()` 的 `col < 900`，或者为了保住"间距 ≤ 球直径"不得不把
## 粒子数按比例抬到 520（3 发 1560，五倍开销），换来的只是把"厚"多延伸几百米。
## 分工是清楚的：**烟带给长度，粒子给厚度**，各守各的既有承诺。
##
## ---- ★ 轮 63-9 · D5：「拖尾白烟太挡视野了，透明度降低和密度降低 20%：体积不变」----
##
## `amount` = **密度**唯一的旋钮（粒子层每发几颗）：80 → **64**、28 → **22**（各 ×0.8）。
##
## ⚠️⚠️ **必须与 `p.lifetime` 同比例降**（0.16 → 0.128）。
## 摊开后间距 = `弹速 × lifetime ÷ amount`：
##   · **只降 amount**（80→64，lifetime 仍 0.16）⇒ 4062.24 × 0.16 / 64 = **10.156 m**
##     **> 球最大出生直径 1.8 × 8.5 × 0.65 = 9.945 m** ⇒ 烟团之间出现缝 ⇒
##     观感退回「一串孤立的点」（**正是轮 39 治好的那个病**），而且**当场撞红**
##     `suite_missile_smoke.gd` 的 `t.lt(spacing, diam_max)`。
##   · **同比例降**（64 / 0.128）⇒ 4062.24 × 0.128 / 64 = **8.124 m（逐位不变）** ⇒ 仍然无缝。
## ⇒「密度 −20%」只能**同比例**动这一对，不能只动 `amount`。
##
## 连带：粒子柱长 `弹速 × lifetime` 650 → **520 m**（−20%）。
## ⚠️ 这**不算违反「体积不变」**（设计文档 P11）：整条拖尾的长度由烟带承担
##（12 km 交战实铺 100.0% 弹道），玩家看到的拖尾长度与宽度都不变。
const TRAIL_HIGH_AMOUNT := 64
const TRAIL_LOW_AMOUNT := 22

## 导弹尾迹：**烟柱**，不是光点（DESIGN §4.4）。
##
## ---- 2026-09-21 从「白色加色 billboard」改成「暗色普通 alpha 烟」----
##
## 老版本是 `_billboard(白, energy = 0)` + 90 粒子 + `lifetime 1.6`。
## 问题**不在于"不够华丽"，而在于读错了**：白色 billboard 在夜景里是一串**发光点**。
## 需求原话是「也不用搞多华丽，得搞点烟幕」「导弹后面的烟幕能增加代入感」——
## 所以这是一次**换材质**，不是加光效。
##
## 材质用 `_trail_smoke_mat()`（**受光 + 真 3D 球**）—— 2026-09-28 从
## `_soft_smoke_mat()` **迁出**，那是本轮"没有体积感"的修复，理由写在那份材质自己的注释里。
## 但"烟不是火"那条分界**一条都没松**：仍然普通 alpha 混合、仍然不自发光。
##
## `amount` = **每发**粒子数，由 `Missile.trail_amount()` 按档位给
## （`TRAIL_HIGH_AMOUNT` / `TRAIL_LOW_AMOUNT`，见上面那两个常量的说明）。
## ⚠️ **档位不是美化，是帧率防线**，设计文档里是写明"必须做"的。
static func missile_trail(parent: Node3D, scale := 0.5,
		amount := TRAIL_HIGH_AMOUNT) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "MissileTrail"
	p.amount = maxi(amount, 1)
	# ---- ⚠️ 2026-09-28（轮 40）：**保持 0.16 s**，它只管"近端有多厚" ----
	#
	# 本轮需求是「拖尾要和飞行轨迹一样长」，**但长度不归这个参数管**（见下）。
	# 实测 12 km 交战时弹道 16651.7 m，而这里给出的柱长是
	#
	#     柱长 = 弹速 × lifetime = 4062 × 0.16 = **650 m**
	#
	# 只盖住那条弹道的 4%。可粒子尾迹的账是死的：要让**粒子柱**盖住 16.7 km 且
	# 不留缝（间距 ≤ 球出生直径 9.95 m），一次扳机 3 发要 **约 5200 颗**，
	# 而全弹发射 100 发才 2800（账见 `TRAIL_HIGH_AMOUNT` 那一段）。
	# 所以轮 40 另加了 `MissileRibbon`（沿弹道的连续烟带，**没有"间距"这个量**）
	# 负责**长度**，这里只管**厚度** —— 也正因如此**一个数都没改**：
	#
	#     间距 = 弹速 × lifetime ÷ amount = 4062 × 0.16 ÷ 80 = **8.12 m**
	#     球出生直径 1.8 × 8.5 × 0.65 = 9.95 m ⇒ 间距 < 直径，**无缝**（轮 39 原样）
	#
	# ⚠️ **"把粒子柱拉长"这条路试算过、走不通**：按"间距 ≤ 球直径"反解，
	# lifetime 涨到 1.2 s 就得把 amount 同比例抬到 520（3 发 1560 = 五倍开销），
	# 而且柱长 4874 m 会立刻撞上 `suite_missile_smoke._density()` 的 `col < 900`。
	# 分工是清楚的：**烟带给长度，粒子给厚度。**
	#
	# ---- 2026-09-28（轮 39）：2.8 s → **0.16 s**（治"稀疏"；数值沿用至今） ----
	#
	# 用户原话：「烟雾能不能浓密一点，是不是烟雾是按时间生成的，
	#            现在浮游导弹飞行速度加快了导致烟雾的飞行轨迹变得那么稀疏」。
	#
	# **他的判断是对的，而且这件事可以直接算。** `GPUParticles3D` 的发射率就是
	# `amount / lifetime`，单位是**粒/秒**，与速度无关 —— 这正是"按时间生成"的含义。于是
	#
	#     间距 = 世界速度 ÷ 发射率 = 世界速度 × lifetime ÷ amount
	#
	# 而弹体的**世界**速度远不止 `funnel()` 里写着的 `speed = 90`：
	#   · `max_speed = SuitProfile.missile_speed()` = 佩涅罗佩巡航 × 2.6 ≈ **4062 m/s**
	#     （`accel_time = 1.7 s` 爬上去）；
	#   · 再叠上轮 13 的**载机速度继承**（`launch_vel`，1.6 s 线性衰减到 0）。
	# 实测（`tools/probe_trail_density.gd`，逐帧读 `global_position` 差分）：
	#   **平均 2707 m/s、峰值 4062 m/s** ⇒ **间距 94.7 ~ 142.2 m**。
	# 而粒子出生直径只有 3.7~9.9 m ⇒ **间距是粒径的 25 倍**，屏幕上就是"一串孤立的点"。
	#
	# ⚠️ **这不是"量"的问题，往 `amount` 上加料解决不了。** 预算红线是 `3 × HIGH < 300`
	#（`suite_missile_smoke._budget()` 钉着），就算把 HIGH 顶满到 99，
	# 巡航时的间距仍有 115 m。真正的杠杆是 **lifetime 与速度成反比**：
	#
	#     柱长 = 世界速度 × lifetime        ← 缩短 lifetime 会让柱长变短
	#     间距 = 柱长 ÷ amount             ← 但间距**同步**变密
	#
	# 老值 2.8 s 是在弹速还是 1134 m/s 的年代定的（那时柱长 3.2 km），速度涨到 4 倍之后
	# 柱长变成 **11.4 km** —— 相机根本看不完，而 80 颗粒子全撒在那 11 km 上。
	# **"柱长 11 km"本身就是一个荒谬的数**，所以砍它几乎不亏。
	#
	# ⚠️ 轮 39 留下的方法论结论，照旧不许违反：
	#   **不做"按当前速度动态调 lifetime"** —— 那会杀掉已出生的粒子（它们的 `age`
	#   已经大于新 lifetime ⇒ 立刻死），尾迹会一截一截地断。`lifetime` 是常量。
	# 轮 39 当时的读数（**就是现值**，轮 40 没动它）：峰值 4062 ⇒ 间距 8.1 m、
	# 平均 2707 ⇒ 5.4 m。
	#
	# 轮 40 对**这个参数**的连带影响：**没有** —— 柱长仍是 0.65 km、间距仍是 8.1 m，
	# 粒子这一层逐位不变（`fx.gd` 本轮只有注释改过）。本轮多出来的是叠在它上面的
	# 那条连续烟带（`MissileRibbon`），负责**长度**，不碰这里任何几何：
	#     2 km  交战（弹道 3052.9 m）⇒ 烟带实铺 3049.7 m = **99.9%**
	#     12 km 交战（弹道 16651.7 m）⇒ 烟带实铺 16648.7 m = **100.0%**
	# 数字由 `tools/probe_missile_ballistic.gd` 给，**观感只能真机出图看**
	#（本工程有"逐位 diff 只答改没改、不答看不看得见"的记录）。
	# ★ 轮 63-9 · D5：0.16 → **0.128**（与 `TRAIL_HIGH_AMOUNT` 同比例 −20%）。
	# ⚠️ **必须一起动**——理由见 `TRAIL_HIGH_AMOUNT` 上面那段：只降 amount 会让
	# 间距从 8.124 涨到 10.156 m、超过球直径 9.945 m ⇒ 破掉 `spacing < diam_max`。
	# 同比例降 ⇒ 间距 **8.124 m 逐位不变**（仍无缝），柱长 650 → 520 m。
	p.lifetime = 0.128
	# ⚠️ **显式写出来**（默认值就是 30）：下面 `EMIT_SPAN` 那 135.4 m 是
	# `峰值弹速 ÷ 这个数` 算出来的 —— 它是"簇间距"公式里的另一个因子，
	# 两处必须一起看。Godot 若哪天改了默认值，这一行能让它当场暴露。
	p.fixed_fps = 30
	p.local_coords = false
	p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	# ---- ⚠️⚠️ 2026-09-28（轮 39）：**发射盒 —— 这才是"稀疏"的真正开关** ----
	#
	# 同一轮里先把 `lifetime` 从 2.8 砍到 0.16（柱长 11.4 km → 650 m），
	# 重拍后**图上球的数量一个没变**（量出来 before 5 团 / after 5 团，
	# 平均簇间距 129.9 vs 124.3 m、比值 0.96）—— 只有球变得更实。实测把这条路堵死了：
	#
	#     `GPUParticles3D` 的发射是**按 `fixed_fps` 量化**的（默认 **30**）——
	#     每个 1/30 s 吐一次，一次 `amount / lifetime / fixed_fps` 个粒子，
	#     而它们**出生在同一个点**（发射器此刻的位置）。于是
	#
	#         簇间距 = 弹速 ÷ fixed_fps = 4062 ÷ 30 = **135.4 m**   ← 与 lifetime 无关
	#
	# 配 4~10 m 的球，屏幕上就是一串孤立的点。**用户说的"按时间生成"是对的，
	# 只是那个"时间粒度"不是 lifetime，而是 1/fixed_fps。**
	#
	# 修法**不是**去提 `fixed_fps`：要压到 10 m 得 406 Hz，而全弹发射
	# 100 发 × 28 粒子 = 2800 个粒子，模拟开销 ×13.5 —— 那是拿帧率换。
	# 改成**把每一簇沿弹轴摊开**：用一个只有 Z 方向长度的发射盒，长度正好等于簇间距，
	# 于是每簇的那些粒子被平铺在"这一簇本该覆盖的 135 m"上，簇与簇首尾相接。
	# **模拟频率一点没动，零额外开销。**
	#
	# 摊开之后的间距才回到 `lifetime = 0.16` 所依据的那条式子：
	#
	#     间距 = 弹速 × lifetime ÷ amount = 4062 × 0.16 ÷ 80 = **8.12 m**
	#（< 球出生直径 9.95 m ⇒ 相邻烟团重叠、连成一道。轮 40 两个因子都没动。）
	#
	# ⚠️ 盒子沿 **+Z** = 弹的**后方**。`Missile` 用 `look_at_from_position` 定向，
	# 前进方向是 −Z（见它自己的 `forward_dir()`），所以烟必须撒在 +Z 那侧 ——
	# 反过来写的话烟会跑到弹的前面去。
	# ⚠️ 半长与偏移都取 `簇间距 / 2` ⇒ 盒子覆盖弹后方 `[0, 簇间距]`。
	# ⚠️ 按**峰值速度**标定：弹速低时盒子比实际簇距长，相邻簇会交错重叠 ——
	# 那只会更密、不会更稀，方向是安全的（与 `lifetime` 那条同一个道理）。
	const EMIT_SPAN := 135.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.0, 0.0, EMIT_SPAN * 0.5)
	pm.emission_shape_offset = Vector3(0.0, 0.0, EMIT_SPAN * 0.5)
	# 2026-09-22 增厚：12° → 18°。锥角放宽 = 烟柱从"一条细线"变成"一根柱"，
	# 弹幕（一梭 3 发 / 全弹 100 发）的烟才会连成一片。
	pm.spread = 18.0
	# 初速 2–8 → 1–4，damping 3–8 → 5–10：让它**挂在弹后**而不是被弹体甩开。
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, 4.0, 0)
	# 2026-09-22 增厚：出生尺寸 2.0–5.5 → 3.2–8.5（× scale 参数，约 +55%）。
	# 这是"增厚"的主力：粒子数被预算红线卡死，几何尺寸才是免费的大头。
	pm.scale_min = 3.2 * scale
	pm.scale_max = 8.5 * scale
	pm.damping_min = 5.0
	pm.damping_max = 10.0
	# 烟团**随年龄扩散**：`scale_min/max` 给的是"出生尺寸"，这条曲线负责"越飘越大"。
	# 2026-09-22 增厚：终点 1.0 → 1.3 —— 老烟比新烟大 30%，弹幕的烟云会自己长胖。
	# ⚠️ Godot 4 的 `Curve` 默认 `max_value = 1.0`，**超过会被静默钳制**
	#（首轮回归抓到：终点写 1.30 实测读回 1.0）。现在统一走 `_curve()`——
	# 它已经把上限抬到 2.5，这条坑不会再复现（见那个函数的说明）。
	pm.scale_curve = _curve([Vector2(0.0, 0.55), Vector2(0.35, 0.90), Vector2(1.0, 1.30)])
	# 乱流：尾迹是**被拉在弹后的一柱**，气流一路都在搅它。
	# ⚠️ 强度比其它烟低（0.35）：弹幕是全弹发射 100 发同屏的场合，
	# 每柱各自乱摆会让整片烟糊掉方向感 —— 而"它从哪飞来"正是尾迹要说的那件事。
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 2.0
	pm.turbulence_noise_speed = Vector3(0.9, 0.9, 0.9)
	# 色带：浅灰 → 中灰，alpha 慢慢掉、最后归零。
	# ⚠️ 方向与加色**相反** —— 烟是"越叠越暗"，所以色带是往下走的，不是往上亮的。
	# 2026-09-22 增厚：alpha 0.80 → 0.88 / 0.48 → 0.56 —— 弹幕里烟要读得出来，
	# 但仍不许到 1.0（叠满一屏就糊了；suite 的"起点 < 0.95"守卫也卡着）。
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.86, 0.86, 0.89, 0.88))
	ramp.add_point(0.45, Color(0.74, 0.74, 0.78, 0.56))
	ramp.set_color(1, Color(0.62, 0.62, 0.67, 0.0))
	pm.color_ramp = _ramp(ramp)
	p.process_material = pm
	p.draw_pass_1 = _trail_mesh()
	parent.add_child(p)
	return p



## Lit, soft-edged volume appearance for burst/exhaust/damage smoke.
## The legacy StandardMaterial remains the draw-pass fallback; missile trails keep theirs.
static var _cinematic_smoke_cache: ShaderMaterial = null
static func cinematic_smoke_material() -> ShaderMaterial:
	if _cinematic_smoke_cache!=null: return _cinematic_smoke_cache
	var material:=ShaderMaterial.new()
	material.shader=preload("res://shaders/cinematic_smoke.gdshader")
	material.set_shader_parameter("grain",_smoke_grain_tex())
	_cinematic_smoke_cache=material
	return material

static func _beam_contact_smoke(parent: Node3D) -> GPUParticles3D:
	var smoke:=GPUParticles3D.new()
	smoke.name="BeamContactSmoke"
	smoke.amount=12
	smoke.lifetime=0.65
	smoke.one_shot=true
	smoke.explosiveness=0.92
	smoke.local_coords=false
	var process:=ParticleProcessMaterial.new()
	process.direction=Vector3.UP
	process.spread=65.0
	process.initial_velocity_min=3.0
	process.initial_velocity_max=12.0
	process.gravity=Vector3(0,1.5,0)
	process.damping_min=4.0
	process.damping_max=8.0
	process.scale_min=1.3
	process.scale_max=3.0
	process.scale_curve=_curve([Vector2(0,0.5),Vector2(0.45,1.0),Vector2(1,1.4)])
	var ramp:=Gradient.new()
	ramp.set_color(0,Color(0.50,0.48,0.50,0.72))
	ramp.add_point(0.30,Color(0.30,0.32,0.36,0.50))
	ramp.set_color(1,Color(0.22,0.25,0.29,0))
	process.color_ramp=_ramp(ramp)
	smoke.process_material=process
	var mesh:=SphereMesh.new()
	mesh.radius=1.2
	mesh.height=2.4
	mesh.radial_segments=12
	mesh.rings=6
	mesh.material=_soft_smoke_mat()
	smoke.draw_pass_1=mesh
	smoke.material_override=cinematic_smoke_material()
	parent.add_child(smoke)
	smoke.emitting=true
	return smoke

static var _jet_materials: Dictionary = {}
static func jet_flame_material(billboard: bool) -> ShaderMaterial:
	if _jet_materials.has(billboard):
		return _jet_materials[billboard]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/jet_exhaust.gdshader")
	mat.set_shader_parameter("billboard", billboard)
	mat.set_shader_parameter("gain", 1.05 if billboard else 1.40)
	mat.set_shader_parameter("flow_speed", 6.0 if billboard else 11.0)
	mat.set_shader_parameter("turbulence", 0.55 if billboard else 0.25)
	_jet_materials[billboard] = mat
	return mat


static func _attach_jet_envelope(p: GPUParticles3D, dir: Vector3, radius: float, tint: Color, dash: bool) -> void:
	# The envelope supplies the core; narrow fast particles reveal outward motion.
	# Keep the existing per-nozzle particle budget and local-space anchoring.
	p.material_override = jet_flame_material(false)
	p.fixed_fps = 60
	p.preprocess = p.lifetime
	var process := p.process_material as ParticleProcessMaterial
	if process != null:
		process.turbulence_enabled = false
		process.spread = 2.2 if dash else 4.0
		process.particle_flag_align_y = true
		process.initial_velocity_min = radius * (100.0 if dash else 48.0)
		process.initial_velocity_max = radius * (125.0 if dash else 66.0)
		process.damping_min = 0.0
		process.damping_max = 2.0
		process.emission_sphere_radius = radius * 0.24
		process.scale_min = 0.45
		process.scale_max = 0.85
		process.scale_curve = _curve([Vector2(0.0, 0.45), Vector2(0.18, 1.0), Vector2(1.0, 0.12)])
	var streak := SphereMesh.new()
	streak.radius = radius * (0.07 if dash else 0.09)
	streak.height = radius * (2.8 if dash else 1.6)
	streak.radial_segments = 6
	streak.rings = 3
	streak.material = jet_flame_material(false)
	p.draw_pass_1 = streak

	var flame := MeshInstance3D.new()
	flame.name = "JetEnvelope"
	var length_m := radius * (20.0 if dash else 8.0)
	var mesh := CylinderMesh.new()
	mesh.height = length_m
	mesh.bottom_radius = radius * (0.48 if dash else 0.52)
	mesh.top_radius = radius * 0.045
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.radial_segments = 16
	mesh.rings = 48
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/jet_envelope.gdshader")
	material.set_shader_parameter("length_m", length_m)
	material.set_shader_parameter("exhaust_speed", DASH_BEAM_V0 if dash else 65.0)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("shocks", 1.0 if dash else 0.4)
	mesh.material = material
	flame.mesh = mesh
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.quaternion = Quaternion(Vector3.UP, dir.normalized())
	flame.position = dir.normalized() * length_m * 0.5
	flame.visible = false
	p.add_child(flame)
	p.set("flame", flame)
	p.set_instance_shader_parameter("age_end", clampf(length_m / (radius * (112.0 if dash else 57.0) * p.lifetime), 0.05, 1.0))
