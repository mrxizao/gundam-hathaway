extends Node
## 浮游导弹尾迹**浓密度**出图探针（轮 39）。
##
## ## 症状（用户原话）
## 「浮游导弹飞行过程中的烟雾能不能浓密一点，是不是烟雾是按时间生成的
##   现在浮游导弹飞行速度加快了导致烟雾的飞行轨迹变得那么稀疏。」
##
## ## 与上一个探针（`probe_trail_volume.gd`，轮 38）的关键区别
##
## 那一个用的是 **`SPEED = 80 m/s` 的手动匀速** —— 那是浮游导弹**出膛自航速度**
## 的量级（`Missile.funnel()` 里的 `speed = 90`）。但弹体在**世界**里根本不是这个速度：
##
##   · `max_speed = SuitProfile.missile_speed()` ≈ 4062 m/s（`accel_time = 1.7 s` 爬上去）；
##   · 轮 13 的**载机速度继承**让离架瞬间再叠上 1562 m/s（加力 2343），1.6 s 线性衰减。
##
## **用 80 m/s 拍，间距只有 2.8 m —— 恰好把"稀疏"这个症状整个藏起来了。**
## 本轮把速度换成实测的真实巡航量级（见 `SPEED`），柱长随之从 224 m 变成数千米。
##
## ## 机位为什么要"只框一小段"
##
## 旧版柱长 = 速度 × 2.8 s ≈ **10 km**，新版柱长 ≈ 600 m —— 两者差 17 倍，
## **没有哪个机位能把两版同框对比**（框住 10 km 的话，600 m 那版只剩一个像素）。
##
## 所以改成**同一个 610 m 的窗口**、都取**柱的尾段**（`[p_end − 610, p_end]`）：
##   · 旧版：这 610 m 里只有 4 颗间距 142 m 的孤立球 ⇒ 大量空白；
##   · 新版：整条 600 m 的柱都落在窗口内 ⇒ 连续。
## 窗口一样、取的都是"弹体刚飞过的那一段"，对照是公平的。
##
## ## 跑法（⚠️ **不能加 `--headless`**：无头下 RenderingServer 是 dummy，出不了像素）
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       res://tools/probe_trail_density_shots.tscn -- <输出目录>

const MAIN_SCENE := "res://scenes/main.tscn"
const SHOT_W := 1600
const SHOT_H := 900

## 弹体的**世界**速度（m/s）。取**峰值巡航** = `SuitProfile.missile_speed()` ≈ 4062，
## 不是 `probe_trail_density.gd` 实测的平均值 2707 —— 理由是**本探针的相机看的是柱的尾段**，
## 而尾段正是弹体以峰值速度飞过的那一段（老粒子出生时弹速低，落在更远端）。
## 用 4062 标定时，窗口内的间距与实测峰值 142.2 m **逐位一致**，是最忠实的口径。
const SPEED := 4062.2
## 走满一个寿命，让柱的"稳态"完全展开。
const FLY_T := 2.8
## 相机一屏框住的柱长（m）。由 fov 与相机距离反推：
## 距离 330 m、垂直 fov 55°、宽高比 16:9 ⇒ 水平覆盖
## `2 × 330 × tan(27.5°) × 16/9 ≈ 610 m`。
const BOX := 610.0

var _main: Node = null
var _out := "user://probe_density"
var _c: Node = null
var _m: Missile = null
var _shooter: FlightBody = null
var _t := 0.0
var _p0 := Vector3.ZERO
var _dir := Vector3.FORWARD
var _mid := Vector3.ZERO
## > 0 时覆盖尾迹的 `lifetime`（参数扫描用，见 `_run()`）。
var _lifetime_override := 0.0
## >= 0 时覆盖发射盒的长度（0 = 退回默认的点发射）；-1 = 不动。
var _span_override := -1.0


func _ready() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	# 可选第 2 个参数：**临时覆盖 lifetime**（只用于参数扫描实验，不落盘到 fx.gd）。
	# 目的：确认"摊开后的间距"是否真的 = 弹速 × lifetime / amount，
	# 还是另有机制在限制（实测曾出现理论 8.1 m / 实测 18.7 m 的 2.3 倍偏差）。
	if args.size() > 1:
		_lifetime_override = float(args[1])
	# 可选第 3 个参数：**发射盒长度**。`-1`（默认）= 用 fx.gd 里的值；
	# `0` = **禁用发射盒**（退回默认的点发射）—— 专门用来证明
	# "只把 lifetime 砍短、不加发射盒"是白改的（见下）。
	if args.size() > 2:
		_span_override = float(args[2])
	DirAccess.make_dir_recursive_absolute(_out)
	print("[ds] 输出目录 = ", _out)
	if _lifetime_override > 0.0:
		print("[ds] ⚠️ lifetime 被临时覆盖为 %.4f s（实验用，不改 fx.gd）" % _lifetime_override)
	if _span_override >= 0.0:
		print("[ds] ⚠️ 发射盒被临时覆盖为 %.1f m（实验用，0 = 禁用）" % _span_override)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await get_tree().process_frame
	await get_tree().process_frame

	var ps := load(MAIN_SCENE) as PackedScene
	if ps == null:
		push_error("[ds] 加载主场景失败")
		get_tree().quit(4)
		return
	_main = ps.instantiate()
	add_child(_main)
	for i in 3:
		await get_tree().process_frame

	_main._on_start_match(0, 0, MapDef.Id.ULURU, Game.MatchMode.VERSUS)
	# 建图是协程（`apply_map_staged` 里夹着 await），不等够帧 `world.sun` 还是 null。
	for i in 20:
		await get_tree().process_frame
	if _main.world == null:
		push_error("[ds] world 为空 —— 没进 ULURU 图？")
		get_tree().quit(5)
		return

	_setup()
	await _fly()
	_freeze()
	await _shots()
	get_tree().quit(0)


# ------------------------------------------------------------ 造一条真尾迹

## ⚠️ 用**真** `Missile.funnel()`（不是手工 `FX.missile_trail()`）：
## 尾迹的 `scale` 参数（0.65）写在 `Missile._ready()` 里，手工调就会漏掉那一层，
## 那样量到的就不是玩家看到的东西。
func _setup() -> void:
	Game.reset()
	_c = _main.projectiles
	if _c == null:
		_c = Node3D.new()
		_c.name = "TrailProbeBox"
		_main.add_child(_c)

	# 载机：只当"发射者"用，立刻停掉物理。
	_shooter = FlightBody.new()
	_shooter.team = 0
	_shooter.is_player = false
	_shooter.profile = SuitProfile.penelope()
	_shooter.display_name = "TrailShooter"
	_shooter.projectile_container = _c
	_c.add_child(_shooter)
	_p0 = Vector3(0.0, 3000.0, 0.0)
	_shooter.global_position = _p0
	_shooter.set_physics_process(false)
	_shooter.set_process(false)

	_dir = Vector3.FORWARD
	_m = Missile.funnel(_c, _p0, _dir, null, _shooter, 10.0)
	# 关掉弹体自己的物理与制导 —— 位移由探针手动给，这样柱长与朝向完全可控。
	_m.set_physics_process(false)
	_m.set_process(false)
	_m.global_position = _p0
	var tr := _m.get_node_or_null("MissileTrail") as GPUParticles3D
	if tr != null:
		print("[ds] 尾迹 amount=%d  lifetime=%.4f s  ⇒ 柱长 = %.0f × %.4f = %.0f m"
			% [tr.amount, tr.lifetime, SPEED, tr.lifetime, SPEED * tr.lifetime])
		print("[ds] ⇒ 间距 = 速度 × lifetime / amount = %.2f m"
			% (SPEED * tr.lifetime / float(tr.amount)))
		# ⚠️ 这两个必须打出来：`fixed_fps` 决定**簇间距**（弹速 ÷ fixed_fps），
		# 发射盒决定每簇**摊开多长**。它们不生效的话，改 lifetime 是白改的
		#（补丁 A 就是这么白改了一次：簇间距 129.9 → 124.3 m，纹丝不动）。
		var pm0 := tr.process_material as ParticleProcessMaterial
		print("[ds] fixed_fps=%d  簇间距 = %.1f / %d = %.1f m"
			% [tr.fixed_fps, SPEED, tr.fixed_fps, SPEED / maxf(float(tr.fixed_fps), 1.0)])
		if pm0 != null:
			print("[ds] emission_shape=%d（BOX=%d）  box_extents=%s  shape_offset=%s"
				% [pm0.emission_shape, ParticleProcessMaterial.EMISSION_SHAPE_BOX,
					str(pm0.emission_box_extents), str(pm0.emission_shape_offset)])
		# 参数扫描：只覆盖 lifetime（发射盒的 135.4 m 是"簇间距"，与 lifetime 无关，
		# 所以不该跟着动）。覆盖后发射率 = amount / lifetime 会变。
		if _lifetime_override > 0.0:
			tr.lifetime = _lifetime_override
			print("[ds] ⇒ 覆盖后：lifetime=%.4f  发射率=%.1f 粒/秒  柱长=%.0f m  理论间距=%.2f m"
				% [tr.lifetime, float(tr.amount) / tr.lifetime, SPEED * tr.lifetime,
					SPEED * tr.lifetime / float(tr.amount)])
		# 发射盒：`0` = 退回默认的点发射（拿来做"只有 lifetime 改动"的对照）。
		if _span_override >= 0.0 and pm0 != null:
			if _span_override <= 0.0:
				pm0.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
				pm0.emission_box_extents = Vector3.ZERO
				pm0.emission_shape_offset = Vector3.ZERO
				print("[ds] ⇒ 发射盒已禁用（退回点发射）：每簇挤在一个点上")
			else:
				pm0.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
				pm0.emission_box_extents = Vector3(0.0, 0.0, _span_override * 0.5)
				pm0.emission_shape_offset = Vector3(0.0, 0.0, _span_override * 0.5)
				print("[ds] ⇒ 发射盒覆盖为 %.1f m" % _span_override)
			print("[ds] 覆盖后 emission_shape=%d  box_extents=%s  shape_offset=%s"
				% [pm0.emission_shape, str(pm0.emission_box_extents), str(pm0.emission_shape_offset)])
	else:
		push_error("[ds] 尾迹节点没找到")


## 手动匀速直线推进：`Missile._physics_process` 已停，位置只由这里给。
##
## ⚠️ 位置写成 `_p0 + _dir × (SPEED × _t)` 这个**绝对式**，不是逐帧 `+=`：
## 逐帧累加会跟着帧率漂（每帧的 `dt` 抖动被积分进去），柱长就不精确等于 `SPEED × FLY_T`。
func _fly() -> void:
	while _t < FLY_T:
		await get_tree().process_frame
		_t += get_process_delta_time()
		_m.global_position = _p0 + _dir * (SPEED * _t)
	_m.global_position = _p0 + _dir * (SPEED * FLY_T)
	print("[ds] 飞完 %.2f s：柱长 %.0f m" % [_t, SPEED * FLY_T])


## 冻结画面。
## ⚠️ `emitting = false` **不够**（只停新生），必须 `speed_scale = 0.0` 把演化也停住，
## 否则抓 A 图与抓 B 图之间那些已经存在的粒子会自己继续飘/继续淡 —— 判据就成了噪声。
func _freeze() -> void:
	_m.set_physics_process(false)
	_shooter.set_physics_process(false)
	get_tree().paused = true
	for p in _all_particles(_c):
		p.emitting = false
		p.speed_scale = 0.0
	print("[ds] 冻结：粒子发射器 %d 个，speed_scale 全部置 0" % _all_particles(_c).size())


func _all_particles(root: Node) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	if root == null:
		return out
	for ch in root.get_children():
		if ch is GPUParticles3D:
			out.append(ch as GPUParticles3D)
		out.append_array(_all_particles(ch))
	return out


## 成批显隐 `_c` 底下**所有**粒子发射器（外加弹体本身）。
## 拍背景图用 —— 见 `_shots()` 里那段说明：判据走 `fg − bg` 差分，背景就不参与。
func _show_particles(v: bool) -> void:
	for p in _all_particles(_c):
		p.visible = v
	if _m != null and is_instance_valid(_m):
		_m.visible = v


# ------------------------------------------------------------ 出图

func _shots() -> void:
	if _main.canvas != null:
		_main.canvas.visible = false
	var wbx: Node = _main.world
	if wbx != null:
		var cr: Node = wbx.get("_cloud_root")
		if cr is Node3D:
			(cr as Node3D).visible = false
	var chase: Camera3D = _main.chase
	if chase == null:
		print("[ds] ⚠️ 没有 chase 相机")
		return
	chase.set_target(null)
	chase.set_physics_process(false)
	chase.set_process(false)
	chase.fov = 55.0
	chase.far = 30000.0
	chase.near = 1.0

	var sun: DirectionalLight3D = wbx.get("sun") if wbx != null else null

	# 柱的尾段：相机看的是"弹体刚飞过的那 610 m"。
	var p_end := _p0 + _dir * (SPEED * FLY_T)
	_mid = p_end - _dir * (BOX * 0.5)

	# 正侧视：视线 ⟂ 柱轴（柱沿 ±Z ⇒ 相机放到 +X 侧、与柱同高再抬 70 m）。
	_aim(_mid + Vector3(330.0, 70.0, 0.0), _mid)

	# ---- 背景对照（判据的地基）----
	#
	# ⚠️ 这个机位与柱**同高侧视**，视线俯 12° ⇒ 柱落在**地平线以下**，
	# 后面压着的是 ULURU 的红棕地面（有山有纹理）。若判据直接用亮度阈值，
	# 地面的明暗会被算进"烟的覆盖率"里 —— 而那跟烟浓不浓**毫无关系**。
	# 所以每个"带烟"的机位都配一张**同机位、藏掉所有粒子**的背景图，
	# 判据一律走 `fg − bg` 差分：地面、山、星空在这一步就整个退场了。
	#
	# ⚠️ 藏的不只是 `_m`：`_c` 底下有 11 个发射器（尾焰、别处的烟团…），
	# 只藏导弹自己的话差分完还会剩一堆杂点。整批一起藏。
	_show_particles(false)
	await _shot("z_bg")
	_show_particles(true)
	await _shot("a_side")

	# 关主光的配对图：复测轮 38 的"体积感"口径有没有被本轮的改动破坏。
	# 同样配一张**关着主光**的背景图 —— 关灯时背景自己也会变暗，
	# 不配的话"变暗了多少"里会混进背景的贡献。
	if sun != null:
		var was := sun.visible
		sun.visible = false
		_show_particles(false)
		await _shot("z_bg_nolight")
		_show_particles(true)
		await _shot("b_side_nolight")
		sun.visible = was
		print("[ds] 主光开关判据：sun.visible %s → false → %s（图 a/b，各有自己的 bg）"
			% [str(was), str(was)])

	# 沿柱轴方向再退一点，把柱放在画面中央更"正"一点（给人看的英雄图）。
	_aim(_mid + Vector3(300.0, 30.0, -40.0), _mid)
	await _shot("c_hero")

	print("[ds] viewport 逻辑尺寸=%s  窗口尺寸=%s  出图尺寸=%dx%d"
		% [str(get_viewport().get_visible_rect().size), str(DisplayServer.window_get_size()),
			SHOT_W, SHOT_H])


func _aim(pos: Vector3, look: Vector3) -> void:
	var chase: Camera3D = _main.chase
	chase.global_position = pos
	# ⚠️ 用 `Basis.looking_at` 而不是手写欧拉：本探针的机位都是近水平的，
	# 视线与 UP 不可能共线，不会踩到 `look_at` 的退化。
	chase.global_transform.basis = Basis.looking_at(look - pos, Vector3.UP)
	chase.current = true
	# ⚠️ 每个机位都把**窗口两端**（`_mid ± BOX/2`）的屏幕投影打出来 —— 判据脚本据此裁 ROI。
	# 上一轮我凭印象填 ROI，结果框在了纯星空上（ROI 里只有 286 个像素、
	# 而且 before/after 数字逐位相同 ⇒ 那一格根本没烟）。**别猜像素坐标。**
	var a := _mid - _dir * (BOX * 0.5)
	var b := _mid + _dir * (BOX * 0.5)
	print("[ds] cam@%s  窗口近端(%s)→%s  窗口远端(%s)→%s"
		% [str(pos.round()), str(a.round()), str(chase.unproject_position(a).round()),
			str(b.round()), str(chase.unproject_position(b).round())])


func _shot(name: String) -> void:
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	print("[ds] 出图 %s  %dx%d" % [path, img.get_width(), img.get_height()])
