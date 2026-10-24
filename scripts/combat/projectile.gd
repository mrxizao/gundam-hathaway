class_name Projectile
extends Node3D
## 机炮（火神炮）与光束步枪的弹丸。
##
## 关键点：**逐帧做线段射线检测**，而不是"移动到位再查重叠"。
## 弹速 1400 m/s、60Hz ⇒ 单帧位移 23 m，比一架 MS 的碰撞体还大，
## 用重叠检测会直接穿过去（tunneling）。这里用 from→to 的扫掠射线保证不漏判。
##
## 两种外观共用一个类，只是网格尺寸与材质不同：
##   - 火神炮：细长曳光弹（高速、低伤、高射速）
##   - 光束步枪：粗长的粉白色光柱（高伤、低射速）
## 伤害类型随弹丸走（见 Damage.Type），由 I 立场护盾决定减伤。
##
## ⚠️ 弹速**不要在调用点之外写死**：光束的速度来自 `SuitProfile.rifle_speed`
## （`FlightBody.fire_beam()` 传进来），因为 HUD 的提前量圈与 AI 的解算读的是同一个数。
## 弹速改了而这里写死的另一份没改，就会出现"准星算出来的提前量点和实际弹道对不上"。

const WORLD_LAYER := 1 << 0
const UNIT_LAYER := 1 << 1
const FIN_HIT_LAYER := preload("res://scripts/data/nu_spec.gd").FIN_HIT_LAYER

## 弹丸能不能打掉**来袭导弹**（第十八轮）。
## 用户原话：「火神炮和光束步枪也可以对导弹生效」。
##
## ⚠️ **为什么用显式线段判定，而不是给导弹加碰撞体 / 碰撞层**：
## 导弹一旦进了 `UNIT_LAYER`，它就会同时出现在 **AI 的视线 raycast**（也查 UNIT）里 ——
## 那等于"导弹会挡住 AI 的视线"，是静默改变 AI 行为的一类副作用
## （本工程为"加粗机体胶囊去修命中率"栽过同款，README §14 有记账）。另开一层又要动全局掩码。
## 这里直接复用**拦截判定那一套** `Ballistics.segment_distance`：只读导弹自己的
## `_prev_pos → global_position` 线段 —— 和拦截弹对撞用的是**同一个几何模型**，
## 于是"对撞能打掉"和"子弹能打掉"的判定天然一致。
##
## 代价是 O(弹丸 × 导弹)：百发齐射 + 火神炮扫射时最坏每帧几千次线段距离，可接受
## （要压的话先做一次中点距离预筛，别去动碰撞层）。
const MISSILE_HIT_RADIUS := 1.6

## 回退扫描的**采样数上限**（1.3 批 M；★ 轮 58 起它管的是「两段式」的 ②b 那一层）。
##
## 只在"`cast_motion()` 的比例与 `intersect_shape()` 对不上"这条**罕见**路径上用
##（见 `_physics_process()` 里那段 ⚠️⚠️）。步长取 `hit_radius()`（保证不会从碰撞体
## 中间穿过去），而这个上限是**防御性**的：没有它，整段扫描在光束那边会退化成
## 几百次查询，而那是**每帧**都要付的成本。
##
## ★ 轮 58 口径变了两次，必须一起读（不然会按旧数字误判精度）：
##   · **旧版**扫的是 `[0, cast[1]]`（注释里记的实测约 16 m）⇒ 24 步 ≈ 0.7 m/步，很细；
##   · **现在 ②b** 扫的是**整段 `[0, 1]`** ⇒ 火神炮 35 m/帧 ⇒ 24 步 ≈ 1.5 m/步
##     （仍细，远小于机体胶囊直径约 10 m）；
##   · ★ **但光束快段 1500 m/帧 ⇒ 62 m/步，粗到会跳过机体**。
##   ⇒ 所以光束的精度**不靠这一层**，靠 ②a 那个 `hit_radius() * 4` 的细窗口
##     （窗口只有 ~20 m ⇒ ~2.6 m/步）。②b 只是"比例报错得离谱"时的最后兜底。
const MAX_SWEEP_PROBES := 24

const VULCAN_COLOR := Color(1.0, 0.62, 0.62, 0.95)
const BEAM_COLOR := Color(1.0, 0.42, 0.78, 0.96)
## 光束弹体的**视觉半径**（米，尺寸倍率 1.0 时）。它是**圆柱**的半径。
##
## ⚠️ 2026-10-03（轮 63）**解耦**：在这之前只有一个 `BEAM_RADIUS`，它同时管
##   ① 视觉粗细 ② 判定半径 ③ 阿利宙斯背部双炮的间距 —— 三件事一根旋钮。
##   用户第 3 项要求"子弹体积应该调大"，而**调大必然顺手改掉判定与炮口几何**
##   （本工程已经因为 `rifle_scale` 这种"一个常量管三件事"吃过一次亏，
##    见 `SuitProfile` 里 `rifle_scale` 的注释）。
##   现在拆成两个常量：**改粗细不再连带改命中**（判定见 `BEAM_HIT_RADIUS`）。
##
## ⚠️ **炮口间距仍然按"可视半径"算**（用户指定的规则：半间距 = 可视半径 × 3，
##   见 `FlightBody.BACK_MUZZLE_GAP_MUL`）。这条规则的本意就是"光束一大、
##   炮口自动往外挪、两道光不许糊成一道" —— 所以间距跟**这个**常量走是对的，
##   跟判定半径走才是错的（那会算出比整台机还宽的轴距）。
##
## 数值：旧 `BEAM_RADIUS` = 1.3 m ⇒ **1.6 m（+23%）**。
## 要更粗/更细，只改这一个数；想要"更容易命中"改 `BEAM_HIT_RADIUS`，别改它。
const BEAM_VIS_RADIUS := 1.6
## 光束弹体的**判定半径**（米，尺寸倍率 1.0 时）。
##
## 它刻意比视觉半径大：机体那根中轴胶囊只有 5 m 左右，而模型 28 m 高、
## 还带翼展与背包 —— 要在胶囊之外再补一圈余量，让"擦着机翼/背包过去"的弹
## 也算命中（见 `hit_radius()` 与 `_physics_process` 里的判定说明）。
##
## ⚠️ **它与 `BEAM_VIS_RADIUS` 之间没有算式关系** —— 想让"看着擦到"
##   更容易算命中，只改这一个数。
##
## ⚠️⚠️ 2026-10-03（轮 63-4）**2.6 → 4.0**（用户拍板：「丙 · 只放宽判定」）。
##
## 第 1 项「光束步枪难以命中」的根因**不是锥角太窄**，而是**单位错**：
## `Ballistics.angle_off_boresight()` 返回**度**，`FlightBody.aim_assist_weight()`
## 的形参要的是**弧度**（内部拿 `deg_to_rad()` 去比常数）⇒ 真实偏角 > 0.0436°
## 时权重一律 0.0 ⇒ **辅助瞄准是死代码**。
##
## 但把单位改对 ⇒ 锁定且在锥内时弹道被拽向提前量点 ⇒ **违反 README 需求 4
##「光束步枪和火神炮的射击方向跟随鼠标操控的准星」**。用户选择**不修单位错**，
## 改走这条"既不碰弹道、又能降低**擦过不判中**"的路：
##
##   有效命中半径 = 目标胶囊半径 + 本值。胶囊 r=5 m 时 7.6 → **9.0 m（+18.4%）**；
##   r=11 m 时 13.6 → 15.0 m。
##
## 代价要认（两条，都写在这里免得以后忘）：
##   ① **敌我双方都更容易命中** —— 等于动平衡，不是"只帮玩家"；
##   ② `_missile_in_path()` 也读本值（`reach = hit_radius() + MISSILE_HIT_RADIUS`）
##      ⇒ 光束**打掉导弹**也更容易。
##
## 觉得太松/太紧，**只改这一个数**（全工程没有第二处需要同步）。
const BEAM_HIT_RADIUS := 6.0
## 光束弹体的**长度**（米，尺寸倍率 1.0 时）。
const BEAM_LENGTH := 52.0
# Presentation-only width: preserve projectile length, flight and hit radius.
const FIN_VISUAL_WIDTH := 2.0
# Fixed length cylinder: sqrt(3) radius gives +200% visual volume.
const SAZABI_PELLET_VISUAL_WIDTH := 1.7320508075688772

var speed := 1400.0
## Remote fire replicas must never intercept authoritative missiles or hit units.
var visual_only := false
var damage := 4.0
var damage_type := Damage.Type.VULCAN
var lifetime := 1.6
var shooter: Node3D = null
var emitter: CollisionObject3D = null
var direction := Vector3.FORWARD
## 弹体尺寸倍率（1.0 = 老尺寸）。来自 `SuitProfile.rifle_scale`。
## ⚠️ 它**同时**放大视觉与判定半径，见 `hit_radius()`。
var size_mul := 1.0
## 本发弹的**弹道总长**（米）。**只被光束用**：它决定"出膛慢速段"有多长
##（见 `SuitProfile` 里那张三段式弹道的图）。
##
## 由调用方在开火时按"炮口 → 瞄准点"的距离传进来（`FlightBody.fire_beam`）。
## 0 = 没人指定 ⇒ 用 `SuitProfile.RIFLE_DEFAULT_RANGE` 兜底
## （玩家朝空气开枪时确实没有"瞄准点"这个数）。
var traj_range := 0.0
## **匀速弹速**（m/s）。> 0 ⇒ 整条弹道恒定在这个速度上，两段制不参与。
##
## 来源是 `SuitProfile.rifle_steady_speed`（阿利宙斯专属；别的机体是 0 = 老行为）。
## 见 `SuitProfile` 里 `ARIZEUS_RIFLE_STEADY_SPEED` 的说明。
var steady_speed := 0.0
## 已经飞过的距离（米）。光束靠它判"还在出膛段、还是已经进入接近光速段"。
var travelled := 0.0
var _tracer: MeshInstance3D
var _tracer_length := 0.0
## 本发弹自己的物理查询参数（批 10）：**建一次、每帧改字段**，
## 不再每帧 new 一个 `PhysicsShapeQueryParameters3D`。形状是共享的 `_sweep_shape`。
var _pq: PhysicsShapeQueryParameters3D

static var _vulcan_mesh: BoxMesh
static var _beam_mesh: CylinderMesh
static var _base_mat: StandardMaterial3D
## 弹丸材质缓存（批 10 性能优化）：键 = "类型|颜色|发光能量"。
##
## 原来**每一发**弹都 `_base_mat.duplicate()` 一份材质 —— 弹丸生灭极快，
## 一场编队战下来几千份短命材质实例，全是渲染端的分配/释放抖动。
## 实际上颜色 × 类型的组合屈指可数（曳光弹一种、光束按机体 accent 几种），
## 缓存之后全场共享几份材质。⚠️ 共享意味着**没人可以在生成后再改材质** ——
## 目前的调用方（vulcan/beam/funnel）都只在 spawn 时定颜色，成立。
static var _mat_cache: Dictionary = {}
## 扫掠判定的共享球形（批 10 性能优化）。
##
## 原来**每发弹每物理帧**都 `SphereShape3D.new()` + `PhysicsShapeQueryParameters3D.new()`
## —— 物理查询是同步的，一帧内几百发弹就是几百次形状资源分配。
## 球半径在使用前统一赋值（见 `_physics_process`），查询又是**同步**完成的，
## 共享一个形状资源在单线程物理下是安全的。
static var _sweep_shape: SphereShape3D


static func _ensure_assets() -> void:
	if _vulcan_mesh != null:
		return
	_vulcan_mesh = BoxMesh.new()
	_vulcan_mesh.size = Vector3(0.55, 0.55, 16.0)
	# 光束是**圆柱**（用户："光束得是圆柱体啊"）。用 BoxMesh 的时候斜着看是两片平板。
	#
	# ⚠️ 圆柱的默认轴是 **Y**，而弹丸的飞行轴是 **−Z** —— 差 90°，
	# 这个旋转在 `spawn()` 里对 MeshInstance3D 施加（网格资源本身没有"轴"这个属性）。
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = BEAM_VIS_RADIUS
	_beam_mesh.bottom_radius = BEAM_VIS_RADIUS
	_beam_mesh.height = BEAM_LENGTH
	_beam_mesh.radial_segments = 16
	_beam_mesh.rings = 1
	_base_mat = StandardMaterial3D.new()
	_base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_base_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_base_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_base_mat.emission_enabled = true
	_base_mat.disable_receive_shadows = true
	_base_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 扫掠判定的共享球（批 10）：半径每帧按需赋值，见 `_physics_process`。
	_sweep_shape = SphereShape3D.new()


## 通用生成。多数情况下请用 vulcan() / beam() 这两个语义化入口。
static func spawn(container: Node, from: Vector3, dir: Vector3, shooter_unit: Node3D,
		damage_amount := 4.0, color := VULCAN_COLOR,
		damage_kind := Damage.Type.VULCAN, speed_value := 1400.0,
		elongation := 1.0, size_mul := 1.0, traj_range_value := 0.0,
		steady_value := 0.0) -> Projectile:
	_ensure_assets()
	var p := Projectile.new()
	p.shooter = shooter_unit
	p.direction = dir.normalized()
	p.damage = damage_amount
	p.damage_type = damage_kind
	p.speed = speed_value
	p.size_mul = maxf(size_mul, 0.05)
	p.traj_range = maxf(traj_range_value, 0.0)
	p.steady_speed = maxf(steady_value, 0.0)
	container.add_child(p)
	p.global_position = from

	var mi := MeshInstance3D.new()
	mi.mesh = _beam_mesh if damage_kind == Damage.Type.BEAM else _vulcan_mesh
	# 材质走缓存（批 10）：颜色 × 类型组合就那几种，全场共享，
	# 不再每发弹 duplicate 一份短命材质（见 `_mat_cache` 的注释）。
	var energy := 6.0 if damage_kind == Damage.Type.BEAM else 5.0
	var mat_key := "%d|%s|%.1f" % [int(damage_kind), color, energy]
	var mat: StandardMaterial3D = _mat_cache.get(mat_key)
	if mat == null:
		mat = _base_mat.duplicate() as StandardMaterial3D
		mat.albedo_color = color
		mat.emission = Color(color.r, color.g * 0.75, color.b * 0.9)
		mat.emission_energy_multiplier = energy
		_mat_cache[mat_key] = mat
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 尺寸倍率（`elongation` 只拉长轴，是给别的用途留的）。
	#
	# ⚠️ **缩放必须在网格自己的坐标系里给**：Godot 的 basis = R·S（**先缩放、后旋转**），
	# 而光束圆柱的轴是它的**局部 Y**。所以"沿飞行方向拉长"要乘在旋转之前的 Y 上 ——
	# 乘在 Z 上只会把圆柱**变粗**，看起来像"半径没对上线"。
	var axial := p.size_mul * elongation
	if damage_kind == Damage.Type.BEAM:
		mi.rotation_degrees.x = 90.0        # 圆柱躺下：局部 Y → 父节点 −Z（飞行方向）
		mi.scale = Vector3(p.size_mul, axial, p.size_mul)
	else:
		mi.scale = Vector3(p.size_mul, p.size_mul, axial)
	p.add_child(mi)
	p._tracer=mi
	p._tracer_length=(BEAM_LENGTH if damage_kind==Damage.Type.BEAM else 16.0)*axial
	p._sync_tracer()
	# 让 −Z（Box 的长轴）指向飞行方向
	p.look_at(from + p.direction, Vector3.UP)
	return p


## 火神炮：细长曳光弹。
##
## ⚠️ 弹速走 `SuitProfile.vulcan_speed()`（**全工程唯一真源**），不在这里写死。
## 2026-09-25 机体实际速度 ×1.5 之后，火神炮也必须同步 —— 否则加力 1418 m/s
## 比自己的机炮（1400）还快，子弹会落在飞机后面。
static func vulcan(container: Node, from: Vector3, dir: Vector3, shooter_unit: Node3D,
		damage_amount := 4.0, color := VULCAN_COLOR) -> Projectile:
	return spawn(container, from, dir, shooter_unit, damage_amount, color,
		Damage.Type.VULCAN, SuitProfile.vulcan_speed())


## 光束步枪：粗长光柱。
##
## ## ⚠️ 弹速不是"一个数"了（2026-09-25）
## 弹道分两段：**出膛段慢（`RIFLE_LAUNCH_SPEED`）→ 接近光速（`RIFLE_FAST_SPEED`）**，
## 见 `SuitProfile` 里那张图。所以这里不再收"弹速"，而是收**弹道总长**
## `traj_range_m`（炮口 → 瞄准点的距离）—— 弹丸自己按"飞了多远"决定当前是哪一段。
##
## `traj_range_m <= 0` ⇒ 用 `SuitProfile.RIFLE_DEFAULT_RANGE` 兜底。
static func beam(container: Node, from: Vector3, dir: Vector3, shooter_unit: Node3D,
		damage_amount := 46.0, color := BEAM_COLOR, traj_range_m := 0.0,
		size_mul := 1.0, steady := 0.0) -> Projectile:
	return spawn(container, from, dir, shooter_unit, damage_amount, color,
		Damage.Type.BEAM, SuitProfile.RIFLE_LAUNCH_SPEED, 1.0, size_mul, traj_range_m,
		steady)


## 这一发弹丸的"判定粗细"（**半径**，米）。
##
## ⚠️ 它刻意是**视觉半径的 1.6 倍左右**（视觉 = `BEAM_VIS_RADIUS` = 1.6 m，
## 判定 = `BEAM_HIT_RADIUS` = 2.6 m；火神炮固定 1.5 m）：
## 机体那根中轴胶囊只有 5 m 左右，而模型 28 m 高、还带翼展与背包 ——
## 所以要在胶囊之外再补一圈余量，让"擦着机翼/背包过去"的弹也算命中
## （见 `_physics_process` 里的判定说明）。
##
## ⚠️ **2026-10-03 起判定与视觉是**两个独立常量**：不再有 `BEAM_RADIUS × 2` 这个算式。
## 想调命中宽松度改 `BEAM_HIT_RADIUS`；调视觉粗细改 `BEAM_VIS_RADIUS` —— 互不牵连。
##
## ⚠️ **必须乘 `size_mul`**：弹体视觉放大、判定半径却不放大，就会出现
## "明明从机体上穿过去了却不算命中" —— 比弹丸偏小更难查，因为看上去是打中了。
func set_beam_visual_width(multiplier: float) -> void:
	if damage_type != Damage.Type.BEAM or not is_instance_valid(_tracer): return
	_tracer.scale.x = size_mul * maxf(multiplier, 0.05)
	_tracer.scale.z = size_mul * maxf(multiplier, 0.05)

func hit_radius() -> float:
	return (BEAM_HIT_RADIUS if damage_type == Damage.Type.BEAM else 1.5) * size_mul


var rifle_recorder = null
var rifle_record_id := 0

func _settle_rifle(outcome: String, hull_loss := 0.0, field_loss := 0.0,
		contact := false, hostile_alive := false) -> void:
	if rifle_recorder != null and rifle_record_id > 0:
		rifle_recorder.settle(rifle_record_id, outcome, hull_loss, field_loss, contact, hostile_alive)
		rifle_record_id = 0

func _exit_tree() -> void:
	_settle_rifle("scene_exit")
	if rifle_recorder != null and rifle_recorder != Game.rifle_stats:
		rifle_recorder.save_report()

func _ready() -> void:
	# 少量随机化，避免连发时完全重叠
	lifetime += randf() * 0.2
	if damage_type == Damage.Type.BEAM:
		lifetime = 2.2


func _sync_tracer() -> void:
	if not is_instance_valid(_tracer):return
	var length:=minf(_tracer_length,maxf(travelled,0.0))
	_tracer.visible=length>.0001
	if damage_type==Damage.Type.BEAM:
		_tracer.scale.y=maxf(length/BEAM_LENGTH,.00001)
	else:
		_tracer.scale.z=maxf(length/16.0,.00001)
	_tracer.position=Vector3(0,0,length*.5)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		_settle_rifle("expired")
		queue_free()
		return

	# Integrate the remaining launch time before spending the rest of this frame
	# at cruise speed. Both legs are collinear, so one sweep covers their union.
	var distance := speed * delta
	if damage_type == Damage.Type.BEAM:
		if steady_speed > 0.0:
			distance = steady_speed * delta
		else:
			var span := traj_range if traj_range > 0.0 else SuitProfile.RIFLE_DEFAULT_RANGE
			var remaining := maxf(SuitProfile.rifle_launch_len(span) - travelled, 0.0)
			var slow_time := minf(delta, remaining / SuitProfile.RIFLE_LAUNCH_SPEED)
			distance = slow_time * SuitProfile.RIFLE_LAUNCH_SPEED + (delta - slow_time) * SuitProfile.RIFLE_FAST_SPEED
	var from := global_position
	var to := from + direction * distance if damage_type == Damage.Type.BEAM else from + direction * speed * delta
	travelled += distance if damage_type == Damage.Type.BEAM else (to - from).length()
	_sync_tracer()

	# --- 打掉来袭导弹（第十八轮）---
	# 放在物理扫掠**之前**：弹丸优先打"正在飞来的弹"，这样机炮当近防炮用时手感可靠
	# （否则一发弹擦过导弹、同时又撞到远处的山，会先算撞山）。
	var shot := _missile_in_path(from, to) if not visual_only else null
	if shot != null:
		var where := shot.global_position
		var fx_parent := get_parent()
		if fx_parent != null:
			if damage_type == Damage.Type.BEAM:
				FX.beam_impact(fx_parent, where)
			else:
				FX.hit_spark(fx_parent, where, 0.45)
		shot.shot_down()
		_settle_rifle("missile_intercept")
		queue_free()
		return

	var space := get_world_3d().direct_space_state
	var motion := to - from

	# ---- 命中判定：**按武器粗细的球形扫掠**，不是零半径射线 ----
	#
	# 起因（用户："玩家现在就在打不中"）：旧实现是 `intersect_ray`（零半径），
	# 而机体碰撞体是一根很瘦的**中轴胶囊**（`cap.radius = max(宽,厚) × 0.26`，
	# 柯西约 5 m），模型却有 28 m 高、还带翼展与背包 ——
	# 视觉上从机翼 / 背包 / 腿边擦过去的弹**全部算 miss**。
	#
	# 两条必须遵守的（方案里点名的警告）：
	#   1. `intersect_shape()` **不理会 `motion` 属性** —— 必须先 `cast_motion()`
	#      求出接触比例，再在**接触点**做形状查询。只调后者会退化成
	#      "起点有没有重叠"，比原来的射线更糟。
	#   2. **不要靠加粗机体碰撞体**来解决：那根胶囊同时被撞击伤害、导弹近炸、
	#      以及 AI 的视线 raycast 使用，加粗等于"AI 更容易看见你" ——
	#      这是一个跨系统的副作用，不能为了弹丸判定去动它。
	# ---- 扫掠判定（批 10：形状与查询参数**复用**，不再每帧 new）----
	# 共享球的半径按本发弹的判定粗细赋值 —— 物理查询是同步的，
	# "改半径 → 查询"之间不会被打断，单线程下共享是安全的。
	if _sweep_shape != null:
		_sweep_shape.radius = hit_radius()
	if _pq == null:
		_pq = PhysicsShapeQueryParameters3D.new()
		_pq.shape = _sweep_shape
		_pq.collision_mask = WORLD_LAYER if visual_only else WORLD_LAYER | UNIT_LAYER | FIN_HIT_LAYER
	_pq.transform = Transform3D(Basis(), from)
	_pq.motion = motion
	if shooter != null and is_instance_valid(shooter):
		_pq.exclude = [shooter.get_rid()]
	else:
		_pq.exclude = []
	if is_instance_valid(emitter):
		var excluded:=_pq.exclude
		excluded.append(emitter.get_rid());_pq.exclude=excluded
	var cast := space.cast_motion(_pq)
	if cast.size() < 2 or cast[1] >= 1.0:
		global_position = to
		return
	# ---- 接触点解析（1.3 批 M：`cast_motion()` 的比例**不再被无条件信任**）----
	#
	# ⚠️⚠️ `cast_motion()` 报的比例**可能是假的**（2026-09-25 实测，全量回归抓到的）。
	#
	# 现象（一发火神炮）：`from = 8992 m`、`motion = +35 m`，目标 `Bandit0_0` 的碰撞体
	# 在 **8994.25 m** 处（0.25 m 步长的逐点 `intersect_shape` 扫描确认），
	# 而 `cast_motion()` 报的"不安全比例"是 **0.4566 ⇒ 9008 m** ——
	# 在那个位置用**同一个 shape、同一个 `collision_mask`、同一个 `exclude`**
	# 做 `intersect_shape()`，**一个碰撞体都查不到**。两个 API 直接矛盾。
	#（这不是我传错了参数：把 shape/掩码/起点/位移逐项复刻一遍，两个 API 依然对不上。
	#  一次扫掠**穿过多个碰撞体**时最容易被撞见 —— 那一段路上有三个。）
	#
	# 旧实现在这里 `hits` 为空 ⇒ `collider == null` ⇒ `queue_free()`，
	# 于是弹丸**无声消失**：不结算伤害、不出火花、不留任何痕迹。
	# 玩家侧的表现是"明明打过去了却什么都没发生"——既不像"没打中"，也不像"打掉了"，
	# 是最难归因的一类症状（这一条是全量回归里"打敌人照常掉血"那条红抓出来的，
	#  而它之所以红，只是因为机体速度 ×1.5 把那条弹道的几何挪了一点点）。
	#
	# ⇒ 三层处理，**任何一层都不允许"销毁弹丸"成为默认结局**：
	#   ① 先信 `cast_motion()`：在它报的位置查重叠。绝大多数字弹走这一层就返回了。
	#   ② 对不上 ⇒ ★★ **轮 58 改**：分两段扫。
	#      ②a 先在 `cast[1]` **附近的细窗口**里逐点扫（覆盖「临界接触」：真接触
	#         可能落在比例**之后**，但只差几个判定半径）；
	#      ②b 还空 ⇒ **从起点往前扫整段**（覆盖「比例完全报错」）。
	#      旧版只有「在 `[0, 该比例]` 上**从末端往回**扫」—— 见下方「被推翻」段。
	#   ③ 还是对不上 ⇒ 那个比例是假的 ⇒ **继续飞到 `to`**，绝不销毁。
	#      宁可漏一发（下一帧还会再判），也不能让弹丸凭空消失。
	#
	# ★★ 轮 58：② 的区间是**被推翻后改的**（旧版 = `[0, cast[1]]`，且从末端往回扫）。
	#
	# 旧版的立论是「不安全比例按定义**不该早于**首次接触 ⇒ 真接触必然落在 `[0, cast[1]]`」。
	# 前半句**没错**。问题出在它把「接触」当成了**一个**概念 —— 实际有**两个**：
	#   · `cast_motion()` 认的「接触」= **球面刚好碰到**目标表面（几何相切）；
	#   · `intersect_shape()` 认的「重叠」= 球与目标**真的相交**到它能查出来的程度。
	# 前者比后者**早**一点点（相切只是「碰到」，还不是「相交」）。于是在相切（临界）时：
	#   · `_probe_at(cast[1] 那点)` = 空（这一刻还没「重叠够」）；
	#   · 旧版往回扫 `[0, cast[1]]` = 空 —— ★ 而且**不是方向的问题**：区间的上界
	#     （`cast[1]`）本身就是那个「还没重叠够」的比例，真接触在**它之后**
	#     ⇒ 接触点压根**不在 `[0, cast[1]]` 里**，从哪一头扫都扫不到。
	#     （旧注释的假设「真接触早于不安全比例」在这里**恰好反了**。）
	# 这也不是参数传错 —— 逐项复刻 shape / 掩码 / 起点 / 位移，两个 API 依然对不上，
	# 因为它们是**两个不同的判定谓词**，不是同一个问题的两次查询。
	# ⇒ 三层全空 ⇒ 按设计「继续飞到 `to`」。而**高速弹丸一帧位移 56 m**
	#   （实测读数，不是按 60 Hz 估的 23 m）**远大于目标纵深** ⇒ 下一帧已越过目标
	#   ⇒ **这一发永久作废**：不掉血、不出火花、不留痕迹（弹丸还不销毁，更难看）。
	#   标本 = `tests/suite_friendly_fire.gd` 的反证断言「同一套弹丸打**敌人**照常掉血」：
	#   它长期红就是因为这个 —— 打队友那发擦得更近、比例更稳，反而判中了。
	#
	# 改法：**两段式** ——
	#   ②a **细窗口**：以 `cast[1]` 为中心、半径 `hit_radius() * 4`（几个判定半径的量级，
	#       正是「球与表面相切」可能造成的误差量级）⇒ 窗口长度几米到几十米，
	#       步长 `maxf(hit_radius(), 0.5)` ⇒ **细**，能抓住「真接触在比例之后」这一种。
	#   ②b **整段**：`[0, 1]` 从起点往前扫，覆盖「比例报错、且错得比真接触早很多」的一般情形。
	#   ★ **方向**顺带从「从末端往回」改成「从起点往前」—— 这不是本轮漏判的根因
	#     （根因是**区间上界**），但语义上更对：弹丸该打**路上最先碰到**的东西。
	#     副作用 = 区间里有多个物体时，取的是**最先**那个而不是最后的（更正确）。
	#
	# ★ 为什么不能「只整段扫」：光束快段一帧 **1500 m**（`RIFLE_FAST_SPEED` = 9×10⁴ m/s），
	#   整段只给 `MAX_SWEEP_PROBES`(24) 个采样 ⇒ 步长 **62 m** ≫ 机体胶囊直径（约 10 m）
	#   ⇒ **会跳过目标**。`suit_profile.gd` 里那句「回退扫描会退化」讲的就是这件事，
	#   那里**有意**把每帧扫掠长度压在 1.5 km 以内 —— 这里必须顺着那个约束设计，
	#   不能靠「把采样数调大」硬扛（那会让每帧的物理查询成本线性膨胀）。
	# ★ 成本：两段仍是**极端兜底路径**（绝大多数子弹在第①层就返回）。②a 约 8 次查询、
	#   ②b 至多 25 次 ⇒ 最坏 ~33 次，且只在「两个 API 打架」时发生。
	_pq.motion = Vector3.ZERO
	var point := from + motion * cast[1]
	var hits := _probe_at(space, point)
	if hits.is_empty():
		# ★★ 轮 58：兜底改成**两段式**（旧版 = 「`[0, cast[1]]` + 从末端往回」，见上方「被推翻」段）。
		#   ②a 细窗口（以 `cast[1]` 为中心，覆盖临界接触）；②b 整段（覆盖比例完全报错）。
		#   `_scan_overlap()` 的第四参数缺省即 `false`（从起点往前），两段都走这个方向。
		var span_len := maxf(motion.length(), 0.001)
		var guard := hit_radius() * 4.0 / span_len
		var lo := maxf(0.0, cast[1] - guard)
		var hi := minf(1.0, cast[1] + guard)
		var found := _scan_overlap(space, from + motion * lo, motion * (hi - lo))
		if found["hits"].is_empty():
			found = _scan_overlap(space, from, motion)
		point = found["point"]
		hits = found["hits"]
	if hits.is_empty():
		global_position = to
		return
	# 优先取"能受伤的机体"，其次才是世界几何
	var collider: Object = null
	for h: Dictionary in hits:
		var cand: Object = h.get("collider")
		if cand is Node3D and (cand as Node3D).has_method("take_damage"):
			collider = cand
			break
		if collider == null:
			collider = cand
	if collider == null:
		_settle_rifle("unresolved_contact")
		queue_free()
		return

	var is_unit := collider is Node3D and (collider as Node3D).has_method("take_damage")
	# ★ 轮 50：打在**剧情地标**上（“夜袭达沃”：往内阁下榻的酒店开一枪）。
	#
	# ⚠️ 这段必须在 `if is_unit:` **之外**：地标是 `world_builder` 的静态几何，
	# 没有 `take_damage()` ⇒ `is_unit` 为假 ⇒ 走的是“静默 `queue_free()`”那条路。
	#
	# ⚠️ `src` 只在 `is_unit` 分支里定义 ⇒ 这里必须**自己**解析射手的有效引用
	#（同一个理由：已释放的引用传进类型化参数会在进函数前就报错）。
	#
	# ★ 口径：只认**玩家那一台**打中的；**不**限“用什么打的”。
	# 理由：武器分类（光束/机炮）会随改装与换装变，拿它当胜利条件
	# 会让一次改装**静默地把这一关变成打不赢**；而“玩家自己打中的”对改装完全免疫。
	if not is_unit and collider is Node3D \
			and Game.is_strike_target(collider as Node3D, shooter if is_instance_valid(shooter) else null):
		var hitter: Node3D = shooter if (shooter != null and is_instance_valid(shooter)) else null
		if hitter == Game.player:
			Game.note_landmark_hit(collider as Node3D, hitter)
	if is_unit:
		# shooter 可能已经被销毁；已释放的引用传进类型化参数会在进入函数前就报错
		var src: Node3D = shooter if (shooter != null and is_instance_valid(shooter)) else null
		var victim := collider as Node3D
		# ---- 友军：**照常出火花，但不结算伤害**（2026-09-21）----
		#
		# 起因："而且为啥有自相残杀的" —— 判定链上一直**没有阵营过滤**，
		# 玩家的机炮扫过僚机，僚机就掉血。闸门的**真源在 `FlightBody.is_friendly_fire()`**
		#（`take_damage()` 的第一道闸门也调同一个函数），这里刻意不另写一份 `team` 比较。
		#
		# ⚠️ 刻意**不做"穿过去继续飞"**：那在军事题材里会读成"子弹会拐弯"，
		# 可信度反而更低。弹丸照常消失、特效照常放 —— 玩家看不出这是被拦下的。
		#
		# ⚠️ 也**不放在碰撞层解决**：`UNIT_LAYER` 是敌我弹药共用的，
		# 而碰撞层同时被撞击伤害、导弹近炸、AI 视线 raycast 使用，
		# 动它等于静默改变 AI 行为（本文件头就点名过这件事）。
		var hull_before: float = victim.hp if victim is FlightBody else 0.0
		var field_before: float = victim.ifield_hp if victim is FlightBody else 0.0
		var hostile_alive: bool = victim is FlightBody and victim.alive and src != null and victim.is_hostile_to(src)
		var friendly := victim is FlightBody and (victim as FlightBody).is_friendly_fire(src)
		if not friendly:
			victim.take_damage(damage, src, damage_type)
			if src != null and src == Game.player:
				Game.hits += 1
		var hull_loss: float = maxf(hull_before - victim.hp, 0.0) if victim is FlightBody else 0.0
		var field_loss: float = maxf(field_before - victim.ifield_hp, 0.0) if victim is FlightBody else 0.0
		_settle_rifle("friendly" if friendly else ("effective_hit" if hostile_alive and (hull_loss > 0.0 or field_loss > 0.0) else "zero_effect"),
			hull_loss, field_loss, true, hostile_alive)
		var fx_parent := get_parent()
		if fx_parent != null:
			# 这里**刻意不放爆炸音**：用户给的三条 boom 分别是"近处导弹 / 远处导弹 / 机体"，
			# 没有一条是"弹丸打在装甲上"。硬套一个上去只会让导弹和机炮听起来一样。
			# 命中反馈目前只有视觉（命中特效）与镜头抖动；要听觉反馈需要再加一个音效素材。
			if damage_type == Damage.Type.BEAM:
				FX.beam_impact(fx_parent, point)
			else:
				FX.hit_spark(fx_parent, point, 0.45)
	if not is_unit:
		_settle_rifle("terrain")
	queue_free()


## 在 `pos` 处用**本发弹自己的扫掠球**做一次重叠查询，返回命中列表。
##
## 抽出来只是为了让 `_physics_process()` 里那三层接触点解析能共用一条查询路径 ——
## `_pq` 是复用的（批 10），所以"改 transform → 查询"必须成对出现，不能散开写。
func _probe_at(space: PhysicsDirectSpaceState3D, pos: Vector3) -> Array:
	_pq.transform = Transform3D(Basis(), pos)
	return space.intersect_shape(_pq, 8)


## 在 `from → from + span` 这一段上按 `hit_radius()` 的步长逐点查重叠。
##
## `backward = true` ⇒ 从**末端往回**扫；否则从起点往前扫。
## ★ 轮 58 起**两个调用者走的都是「从起点往前」**（见 `_physics_process()` 里 ② 的说明）：
## 临界接触时真接触可能落在 `cast_motion()` 报的比例**之后**，往回扫会漏。
##
## 返回 `{"point": Vector3, "hits": Array}`；一个都没命中时 `hits` 为空、
## `point` 为 `Vector3.ZERO`（调用方据此走"继续飞"那一条）。
func _scan_overlap(space: PhysicsDirectSpaceState3D, from: Vector3,
		span: Vector3, backward := false) -> Dictionary:
	var step := maxf(hit_radius(), 0.5)
	var n := clampi(int(ceil(span.length() / step)), 1, MAX_SWEEP_PROBES)
	for i in range(n + 1):
		var k := float(i) / float(n)
		var t := (1.0 - k) if backward else k
		var pos := from + span * t
		var h := _probe_at(space, pos)
		if not h.is_empty():
			return {"point": pos, "hits": h}
	return {"point": Vector3.ZERO, "hits": []}


## 本帧这一段路上有没有**敌方的、够得着的**导弹。有就返回最近的那一枚，否则 null。
##
## 判据与 `Missile._check_intercept()` 完全同源（`Ballistics.segment_distance`），
## 只有两处不同：
##   1. 半径 = `hit_radius()`（弹丸自己的粗细，光束 2.6 / 火神炮 1.5）+ `MISSILE_HIT_RADIUS`；
##   2. **不打自己人**（`m.shooter == shooter` 跳过）—— 一梭三发是扇开的，正前方经常有自己的弹，
##      不筛的话玩家会觉得"我的机炮在打自己的导弹"。
func _missile_in_path(from: Vector3, to: Vector3) -> Missile:
	if shooter == null or not is_instance_valid(shooter):
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var reach := hit_radius() + MISSILE_HIT_RADIUS
	var best: Missile = null
	var best_d := INF
	# 组快照走 Game 的每物理帧缓存（批 10 性能二轮）：每弹每帧不再各自分配一份组数组
	for n: Node in preload("res://scripts/combat/missile_spatial_index.gd").query(tree,from,to,reach):
		var m := n as Missile
		if m == null or not is_instance_valid(m) or m.shooter == shooter:
			continue
		var a := m._prev_pos
		var b := m.global_position
		if a == Vector3.ZERO:
			a = b
		if not Ballistics.swept_bounds_overlap(from,to,a,b,reach):continue
		var d := Ballistics.segment_distance(from, to, a, b)
		if d <= reach and d < best_d:
			best_d = d
			best = m
	return best
