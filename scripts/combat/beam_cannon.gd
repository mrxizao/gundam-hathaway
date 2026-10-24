class_name BeamCannon
extends Node3D
## 阿利宙斯的**蓄力激光炮**：从炮口沿瞄准方向持续射出的超级光束柱。
##
## **弹体形状（2026-10-04 用户追补）**：柱体是一根**圆台** —— **炮口那端细、打得越远越粗**
## （末端半径 = 发射口半径 × `TIP_SCALE` = 2 倍）。改的是**画出来的粗细**，
## **不是**命中范围（那是另一个变量 `radius`，见下面的"两个半径"）。
##
## 需求（2026-09-28 用户原话）：
## > 松手会释放一发**每秒 35 伤害、持续时间 4s** 的超级激光炮
## > （**光束柱炮口需要有大量粒子飞溅**）
##
## ## 为什么它不是一颗 `Projectile`
## 弹丸是"点沿弹道飞"，判命中的方式是**逐帧扫掠射线**（`Projectile._physics_process`）。
## 这里要的是"**一道住在那儿的柱**"：4 秒里它一直贴着炮口、跟着**瞄准方向**扫过战场，
## 对柱体扫到的每个敌人持续结算。做成一颗弹丸就要它是 4 秒长——那根本不是弹。
##
## ## 判定几何
## 对场上**活的敌对单位**逐个做"点到线段距离"（`Ballistics.segment_distance`）——
## 与导弹拦截、弹丸打导弹用的是**同一个几何模型**，所以"擦着边过去算不算"在各武器间一致。
##
## ⚠️ 两个"半径"是**分开的**，不要合并：
##   - `radius`：柱自己的粗细（**按发射口那端**的视觉半径给判定倍率，与弹丸的
##     `hit_radius()` 同一条规矩）。⚠️ 柱体现在是圆台、末端更粗，但**那不放宽命中** ——
##     命中判定读的只有 `radius` 这一个标量，与柱体的形状无关；
##   - `UNIT_RADIUS`：目标机体的碰撞尺度。**刻意用一个常量近似**，不去读它的
##     碰撞体 —— 那会把"判定对着视觉给"这条规矩偷换成"判定对着物理给"，
##     而机体那根中轴胶囊只有 5 m 左右、远小于 28 m 的模型。
##
## ## ⚠️ 每帧只结算 `dps * delta`
## 不做"整段 140 伤害一次砸下去"。4 秒里敌人可以飞出柱外、也可以被你扫回来，
## 累积量才是"持续照射"的意思；一次性结算会让"扫过"和"照住"变得没有区别。

const WORLD_LAYER := 1 << 0

## 机体碰撞尺度（米）。判定用 `radius + UNIT_RADIUS` 作为"够得着"的阈值。
const UNIT_RADIUS := 7.0

## 柱的最长长度（米）。射线打不到世界几何时用它兜底。
##
## **2026-09-28 用户指定 10 km**（原文："光束大炮长度为 10km"）。原来只有 2600 m，
## 于是"打向天空 / 平射海面"时柱体在 2.6 km 处**凭空断掉** —— 画面里就是"短了一截"。
##
## 这是"**最长**"，不是"恒定"：柱体仍然**截在第一个世界几何上**（射线只打
## `WORLD_LAYER`）。不截的话它会穿山而过 —— 那才是真的坏。
## 相机远裁面 90 km（`chase_camera.gd`），所以 10 km 全程看得见，不需要动相机。
const MAX_LEN := 10000.0

## **发射口那端**的可视半径（米）：内核 3.2 / 外晕 8.6。
## ⚠️ 它们现在**只描述炮口那一端** —— 末端半径 = 这两个值 × `TIP_SCALE`（见下）。
## 两处炮口粒子读的也是 `CORE_RADIUS`（`FX.nozzle_glow(..., CORE_RADIUS * 2.4 * visual_scale)` /
## `FX.cannon_muzzle(..., CORE_RADIUS * 2.2, ...)`），它们的语义正是"炮口有多大" ⇒ **不改**。
## 判定半径由 `radius` 单独给。
const CORE_RADIUS := 3.2
const GLOW_RADIUS := 8.6

## 末端半径 = 发射口半径 × 这个倍数 —— 弹体是一根**圆台**（炮口细、打得越远越粗）。
##
## 用户原话（2026-10-04）：
## > 调大光束大炮的弹体（前小后大：发射口和现在一样，末端调大200%）
## 拍板口径：**末端 ×2**（"调到 200%"）⇒ 发射口一个数都没动，末端翻倍。
##
## ⚠️ **哪一端是"末端"不是猜的**：`_place()` 把网格的**局部 +Y** 对齐 `dir`，
## 而 `CylinderMesh.top_radius` 是 +Y 那端、`bottom_radius` 是 −Y 那端 ⇒
## `top_radius` = 打到远处的那端、`bottom_radius` = 炮口那端。
## **写反了炮口就成了喇叭口**（近处粗、远处细），而且它**一条断言都不会红**：
## 两个半径都合法、柱子照画不误。所以 `suite_arizeus_cannon.gd` 第七组把"半径"与
## "那一端落在世界哪儿"接起来量（还直接量了网格顶点），真机图再按像素量一遍"越远越粗"。
##
## ⚠️ 判定粗细是另一个变量（`var radius := 12.0`），与本常量**无关** ——
## 这次"调大"纯粹是视觉，命中范围一米都没变。
const TIP_SCALE := 2.0

var shooter: Node3D = null
## 炮口在 `shooter` 本地坐标系里的位置（**可以有多个**：阿利宙斯是双联炮）。
## 柱体从这些点的**中点**射出（一发激光炮就是一条柱），
## 但**每一处炮口都会喷一簇飞溅粒子** —— 用户要的正是"炮口大量粒子飞溅"。
var offsets: Array[Vector3] = []
## 上述炮口的中点（`launch()` 时算一次，柱体每帧用它算世界坐标）。
var local_offset := Vector3.ZERO
## **兜底**瞄准目标（正常情况下为 null —— 朝向真源是 `cannon_aim_dir()`，见 `_aim_dir()`）。
var target: Node3D = null
var dps := 35.0
var duration := 4.0
## 判定"柱有多粗"（米）：`radius + UNIT_RADIUS` 之内的敌人会被持续结算。
var radius := 12.0
var color := Color(0.68, 0.32, 1.0)

const PENELOPE_FAN_ANGLE := deg_to_rad(12.0)
var fan_yaw := 0.0
var emitter_index := -1
var source_form := -1
var visual_scale := 1.0
var sazabi_belly := false
var _life := 0.0
var _strike_noted := false
var _core: MeshInstance3D = null
var _glow: MeshInstance3D = null
var _flare: Node3D = null
var _pq: PhysicsRayQueryParameters3D = null


## 工厂：建一条激光柱。**flight_body 走这个入口**（不直接 `new()`）——
## 所有"发射时要定下来的东西"都在这里一次给完，免得调用点漏一个参数就静默用默认值。
static func launch(container: Node, shooter_unit: Node3D, muzzle_offsets: Array[Vector3],
		aim_target: Node3D, dps_value: float, duration_value: float,
		tint: Color, radius_value: float = 12.0, size_scale: float = 1.0, yaw_offset: float = 0.0, fan_branch: bool = false, belly_barrel: bool = false) -> BeamCannon:
	var c := BeamCannon.new()
	c.fan_yaw = yaw_offset
	c.shooter = shooter_unit
	c.offsets = muzzle_offsets
	c.local_offset = _midpoint(muzzle_offsets)
	c.target = aim_target
	c.dps = dps_value
	c.duration = duration_value
	c.color = tint
	# ★63-24：判定半径可由调用方给（默认 = 原来的硬编码 12.0）
	# —— C4「加粗光柱」卡改的就是 `profile.beam_cannon_radius`。
	c.radius = radius_value
	c.sazabi_belly = belly_barrel
	c.visual_scale = size_scale * (0.22 if belly_barrel else 1.0)
	var shooter_profile = shooter_unit.get("profile")
	if shooter_profile != null and shooter_profile.id in [SuitProfile.Id.REGZ_CUSTOM,SuitProfile.Id.PENELOPE]: c.source_form = shooter_profile.form
	container.add_child(c)
	# ⚠️ `add_child` 之后才定位：`global_transform` 在有父节点之前是**本地矩阵**，
	# 先算位置会把它当世界坐标用（整条柱会偏到世界的原点附近去）。
	c.global_position = shooter_unit.global_transform * c.local_offset
	# Side beams belong to the central beam: cancelling it also removes the fan.
	if not fan_branch and shooter_profile != null and shooter_profile.id == SuitProfile.Id.PENELOPE and shooter_profile.form == 0:
		for angle in [-PENELOPE_FAN_ANGLE,PENELOPE_FAN_ANGLE]:
			launch(c,shooter_unit,muzzle_offsets,aim_target,dps_value,duration_value,tint,radius_value,size_scale,angle,true)
	return c


## 多个炮口的中点（空表 ⇒ 机体原点上方 60% 高，与 `_collect_muzzles()` 的兜底同向）。
static func _midpoint(pts: Array[Vector3]) -> Vector3:
	if pts.is_empty():
		return Vector3(0.0, 0.0, 0.0)
	var mid := Vector3.ZERO
	for p: Vector3 in pts:
		mid += p
	return mid / float(pts.size())


func _ready() -> void:
	# ---- 内核 + 外晕：两条同轴的圆柱，用 alpha 分层（不用粗细分层）----
	_core = _make_cylinder(CORE_RADIUS * visual_scale, 1.0, color, 1.0)
	_glow = _make_cylinder(GLOW_RADIUS * visual_scale, 1.0, Color(color.r, color.g, color.b, 0.08 if source_form >= 0 else 0.22), 0.25 if source_form >= 0 else 0.55)
	# ---- 炮口光晕：一个加色小球，跟着柱一起走 ----
	_flare = FX.nozzle_glow(self, Vector3.ZERO, _additive_mat(color, 1.6), CORE_RADIUS * 2.4 * visual_scale)
	if _flare != null:
		_flare.name = "CannonFlare"
	# ---- 炮口粒子飞溅（用户点名"大量粒子飞溅"）----
	#
	# ⚠️ 粒子挂成 `self` 的子节点，而 `self` 的原点 = 柱的起点 = **炮口中点** ——
	# 所以每一簇要按"相对中点的偏移"摆回**它自己那个炮口**去，
	# 否则双联炮的两簇会叠在中点上、看起来只有一个炮口在喷。
	#
	# 方向取**发射那一刻机体的前方**：粒子本身 spread 58°（四散），
	# 基础方向只决定散开的重心，寿命 0.42 s 内机体转不了多少。
	var fwd := -shooter.global_transform.basis.z
	if offsets.is_empty():
		offsets = [Vector3.ZERO]
	for off: Vector3 in offsets:
		var jet := FX.cannon_muzzle(self, off - local_offset, fwd,
			CORE_RADIUS * 2.2 * visual_scale, color, maxi(64,int(320*visual_scale)))
		if jet != null:
			if sazabi_belly:
				# Small waist port: keep sparks near the nozzle and clear of the camera.
				jet.lifetime=0.22
				var sparks:=jet.process_material as ParticleProcessMaterial
				sparks.spread=24.0;sparks.initial_velocity_min=6.0;sparks.initial_velocity_max=18.0
				sparks.damping_min=20.0;sparks.damping_max=40.0
				sparks.scale_min*=0.45;sparks.scale_max*=0.45;sparks.turbulence_noise_strength=0.10
			elif source_form >= 0:
				var vapor := jet.process_material as ParticleProcessMaterial
				vapor.initial_velocity_min *= visual_scale * 0.5
				vapor.initial_velocity_max *= visual_scale * 0.5
				vapor.scale_min *= 0.45
				vapor.scale_max *= 0.45
			jet.emitting = true


## 造一根柱体网格。`r` = **炮口那端**的半径；末端（局部 +Y）半径 = `r * TIP_SCALE`。
##
## ⚠️ 这两个赋值**不再对称**（2026-10-04 之前是 `top = bottom = r`）。别"顺手"改回去：
## 等粗圆柱正是本轮要修掉的东西，而"又改回去了"这件事只有第七组抓得住。
func _make_cylinder(r: float, alpha: float, tint: Color, energy: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r * TIP_SCALE
	mesh.bottom_radius = r
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _additive_mat(Color(tint.r, tint.g, tint.b, alpha), energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _additive_mat(tint: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = tint
	m.emission_enabled = true
	m.emission = Color(tint.r, tint.g, tint.b)
	m.emission_energy_multiplier = energy
	return m


func _physics_process(delta: float) -> void:
	_life += delta
	if _life >= duration:
		queue_free()
		return
	if shooter == null or not is_instance_valid(shooter):
		queue_free()
		return

	if shooter is FlightBody and shooter.sazabi_systems!=null and not shooter.alive:
		queue_free();return
	if source_form >= 0 and (not shooter.alive or shooter.profile.form != source_form):
		queue_free()
		return

	# ---- 炮口 + 方向：**每帧重算**（柱跟着机体转向 ⇒ 能用它扫射）----
	if emitter_index >= 0 and shooter._regz_motion != null and shooter._regz_motion.ready:
		local_offset = shooter._regz_motion.port_local(emitter_index)
	if shooter is FlightBody and shooter.sazabi_systems!=null:
		local_offset=shooter.sazabi_systems.motion.belly_muzzle_local() if sazabi_belly else shooter.sazabi_systems.motion.muzzle_local()
	var from: Vector3 = shooter.global_transform * local_offset
	var dir := _aim_dir(from)
	global_position = from

	# 长度：打到世界几何就截在那里，否则用兜底长（打向天空时柱体一路射出画面）
	var length := MAX_LEN
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null:
		if _pq == null:
			_pq = PhysicsRayQueryParameters3D.new()
		_pq.from = from
		_pq.to = from + dir * MAX_LEN
		_pq.collision_mask = WORLD_LAYER
		_pq.exclude = [shooter.get_rid()]
		var hit := space.intersect_ray(_pq)
		if hit.has("position"):
			var collider = hit.get("collider")
			if not _strike_noted and _life >= 0.12 and collider is Node3D and Game.is_strike_target(collider,shooter):
				_strike_noted=true
				Game.note_landmark_hit(collider,shooter)
			length = maxf(from.distance_to(hit["position"]), 1.0)

	# ---- 视觉：一条从炮口射出的柱（局部 Y 轴对齐 `dir`）----
	# 进出各有 0.12 s 的展/收，避免"凭空出现一个大圆柱"。
	var grow := clampf(_life / 0.12, 0.0, 1.0)
	var fade := clampf((duration - _life) / 0.16, 0.0, 1.0)
	var vis := length * grow
	_place(_core, from, dir, vis, 1.0 + 0.10 * sin(_life * 41.0))
	_place(_glow, from, dir, vis, 0.85 + 0.12 * sin(_life * 27.0))
	if _core != null:
		_core.visible = fade > 0.01
	if _glow != null:
		_glow.visible = fade > 0.01

	_apply_damage(from, from + dir * vis, delta)


## 这一帧该朝哪射。
##
## **2026-09-28 用户追补**（原文）：
## > 光束大炮锁定有点太死了：光束大炮长度为 10km，
## > 发射方向和火神炮差不多，都是**跟随着鼠标方向走的**。
##
## 所以真源从"锁定目标"换成了"**机体当前瞄着哪边**"（`FlightBody.cannon_aim_dir()`
## → `aim_forward()`）。对玩家来说那条方向就是**鼠标准星方向**，与火神炮、光束步枪、
## HUD 准星读的是**同一个** `FlightBody.aim_dir` —— 于是"准星指哪、柱子扫哪"必然一致，
## 不会出现"机枪跟鼠标、激光扎在被锁的那台机上"这种两套口径。
##
## ⚠️ `target` **只作兜底**（shooter 不是 `FlightBody` 时才用得上）。
## 别把顺序换回去：那个版本的柱子会**拽着准星走**，而这**一条测试都抓不到** ——
## 它只是把"打哪儿"从玩家手里拿回去了。
func _aim_dir(from: Vector3) -> Vector3:
	if shooter is FlightBody and shooter.sazabi_systems!=null:
		return shooter.cannon_aim_dir() if sazabi_belly else shooter.sazabi_systems.beam_direction(from)
	var fb := shooter as FlightBody
	if fb != null:
		var d := fb.cannon_aim_dir()
		if d.length_squared() > 0.25:
			return _fan_direction(d.normalized())
	if target != null and is_instance_valid(target):
		var to := target.global_position - from
		if to.length_squared() > 0.01:
			return _fan_direction(to.normalized())
	return _fan_direction(-shooter.global_transform.basis.z)


func _fan_direction(direction: Vector3) -> Vector3:
	var axis: Vector3 = shooter.global_basis.x.cross(direction)
	if axis.length_squared()<0.0001: axis=shooter.global_basis.y
	return direction.rotated(axis.normalized(),fan_yaw).normalized()

## 把一条圆柱摆到 `from → from + dir * length` 上，并把半径缩放到 `r`。
##
## ⚠️ 圆柱网格的轴是**局部 Y**，而激光的轴是 `dir` —— 所以这里**不用**
## `Basis.looking_at()`（它对齐的是 −Z，还得再绕 90°，而"绕哪根轴、符号朝哪边"
## 在斜射时最容易写反）。直接按定义构造正交基：局部 Y = `dir`。
## 判据是右手系 `x × y = z`（`x = up × dir`，`z = x × dir`）。
func _place(mi: MeshInstance3D, from: Vector3, dir: Vector3, length: float,
		energy_scale: float) -> void:
	if mi == null:
		return
	var y := dir.normalized()
	var up := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(y).normalized()
	var z := x.cross(y)
	# 半径只由网格自己的常量决定（炮口端 = `CORE_RADIUS` / `GLOW_RADIUS`，
	# 末端 = 它们 × `TIP_SCALE`）—— 这里的 `scale.y` **只**缩放 Y，半径不会被它放大；
	# `energy_scale` 调制发光能量 —— 让柱子"呼吸"，静止的光柱读起来像塑料棒。
	var basis := Basis(x, y, z)
	mi.global_transform = Transform3D(basis, from + y * (length * 0.5))
	mi.scale = Vector3(1.0, length, 1.0)
	var m := mi.material_override as StandardMaterial3D
	if m != null:
		m.emission_energy_multiplier = energy_scale * (1.0 if mi == _core else 0.55)


func _apply_damage(from: Vector3, to: Vector3, delta: float) -> void:
	var fb := shooter as FlightBody
	if fb == null:
		return
	var amount := dps * delta
	if amount <= 0.0:
		return
	for u: Node3D in Game.live_hostiles_of(fb):
		if not is_instance_valid(u):
			continue
		var p: Vector3 = u.global_position
		if Ballistics.segment_distance(from, to, p, p) <= radius + UNIT_RADIUS:
			u.take_damage(amount, shooter, Damage.Type.BEAM_CANNON)
	for funnel in Game.group_snapshot(get_tree(),"sazabi_funnels"):
		if not is_instance_valid(funnel) or funnel.is_queued_for_deletion():continue
		if Ballistics.segment_distance(from,to,funnel.global_position,funnel.global_position)<=radius+2.0:
			funnel.take_damage(amount,shooter,Damage.Type.BEAM_CANNON)
