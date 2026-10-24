extends Node
## 判据出图探针（**特写版**）：弹体到底躺在不躺在自己的弹道上 —— 看得见的那种。
##
## ## 为什么还要再出一版
##
## 上一版 `probe_bullet_body_shots.gd` 把相机放到 1500 m 外，弹丸在图上只有
## 十几个像素 —— 数字说得再对，**眼睛看不见就没法服人**（那四张图里弹丸是几个点）。
## 这一版把相机压到 55~230 m，弹体占画面 1/4 以上，判据是"看图就完了"。
##
## ## 判据（可证伪，且**不循环论证**）
##
## 每一发弹在它自己的弹道上打两个**参考球**，位置是
##   `p.global_position ± dir × (弹体半长)`
## —— 注意这两个球**只由 `Projectile.direction` 算**，和网格的朝向没有关系。
##
##   · 弹体的两个端面 **各自罩住一个参考球** ⇒ 弹体长轴 = 飞行方向，对；
##   · 参考球**飘在弹体侧面 / 端面之外** ⇒ 弹体长轴与飞行方向有夹角，错。
##     偏离量在数值上就是 `半长 × sin(夹角)` —— 对 52 m 的光束，差 10° 就是 4.5 m，
##     在 95 m 机位下约为画面宽度的 5%，肉眼可见。
##
## 数值那一列还会直接印「弹体端面 vs 参考球 的距离（m）」，对齐时应 ≈ 0。
##
## ## 三种弹体，一次拍全
##
##   A 柯西的光束（真开火路径）—— 1.0× 尺寸
##   B 柯西的火神炮（真开火路径）—— 细长盒子
##   C **阿利宙斯弹体尺寸**（`rifle_scale = 3.2` ⇒ 166 m 长）手造一发
##     —— 这是全工程在屏幕上最长的一根，最能看出朝向问题
##
## ## 跑法（⚠️ **不能加 `--headless`**：无头下 RenderingServer 是 dummy）
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       res://tools/probe_bullet_closeup_shots.tscn -- <输出目录>

const SHOT_W := 1600
const SHOT_H := 900
## ⚠️ 不能放 y=0：`CRASH_ALTITUDE = 24`，第一帧就撞海自毁 ⇒ `_think()` 不跑 ⇒ 全是废读数。
const ALT := 3000.0
## 弹丸停在弹道的这个距离上（m）。
const PARK_AT := 200.0
## 三条"车道"的横向错位（m）—— 同一位置会让三根光柱叠在一起，图上分不清谁是谁。
const LANE_A := 0.0
const LANE_B := 78.0
const LANE_C := -250.0
## 阿利宙斯常态/巡航的弹体尺寸倍率（`SuitProfile.rifle_scale`）。
const BIG_SCALE := 3.2
## 负对照的倾斜角（°）。取 30，**刻意等于机头与准星的实测夹角**：
## "如果把弹体歪成机头那样，判据会不会红？"
const TILT_DEG := 30.0
## 负对照专用车道（m）。
const LANE_D := 250.0

var _out := "user://pbc_shots"
var _host: Node3D = null
var _cont: Node3D = null
var _pc: PlayerController = null
var _log: Array[String] = []


func _ready() -> void:
	_run()


func _say(s: String) -> void:
	_log.append(s)
	print("[bc] " + s)


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _fmt3(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]


func _ang(a: Vector3, b: Vector3) -> float:
	if a.length_squared() < 1e-9 or b.length_squared() < 1e-9:
		return -1.0
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_say("输出目录 = %s" % _out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await get_tree().process_frame
	await get_tree().process_frame

	_host = Node3D.new()
	_host.name = "Host"
	add_child(_host)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.05, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.88)
	env.ambient_light_energy = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	_host.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-34.0, -128.0, 0.0)
	_host.add_child(sun)

	_cont = Node3D.new()
	_cont.name = "Projectiles"
	_host.add_child(_cont)

	_pc = PlayerController.new()
	_pc.name = "PC"
	_pc.team = 0
	_pc.is_player = true
	_pc.profile = SuitProfile.xi()
	_pc.display_name = "PC"
	_pc.projectile_container = _cont
	_cont.add_child(_pc)
	_pc.global_position = Vector3(0.0, ALT, 0.0)
	_pc.max_hp = 600.0
	_pc.hp = 600.0
	_pc.ifield_max = 0.0
	_pc.ifield_hp = 0.0
	_pc.fm.speed = 260.0
	_pc.fm.throttle = 0.78
	_pc.fm.align_velocity(_pc.forward())
	await get_tree().process_frame
	await _phys(3)

	_pc.controls_enabled = true
	_pc.debug_input_enabled = true
	_pc.debug_input = Vector3.ZERO
	_pc.debug_throttle = 0.8
	_pc.mouse_lock_enabled = true
	_pc.cursor_seen = false
	_pc.set_aim_direction(Vector3.ZERO)
	await _phys(4)

	if not _pc.alive or absf(_pc.fm.throttle - 0.8) > 0.001:
		_say("❌ 自检没过（alive=%s throttle=%.3f）—— 下面的图与读数都无效"
			% [str(_pc.alive), _pc.fm.throttle])
		get_tree().quit(3)
		return

	# ---- 准星与机头拉开 ~31°，两者在图上才分得开 ----
	# ⚠️ 不能只靠注入鼠标事件：窗口模式下真鼠标每帧覆盖注入值。直接写
	# `set_aim_direction()` 并且**同一帧内立刻开火**（中间没有 await）。
	var nose := _pc.forward()
	var want_aim := (nose + _pc.right() * 0.60).normalized()
	_pc.set_aim_direction(want_aim)
	var aim := _pc.aim_forward()
	_say("准星 aim_forward = %s" % _fmt3(aim))
	_say("机头 forward     = %s   **夹角 %.3f°** ← 这段夹角就是「弹体看着不对」的全部来源"
		% [_fmt3(nose), _ang(aim, nose)])
	if _ang(aim, nose) < 5.0:
		_say("❌ 准星没和机头分开（%.3f°）—— 图会看不出差别" % _ang(aim, nose))

	var muzzles: Array = _pc.get("_muzzle_local")
	var origin: Vector3 = _pc.global_transform * (muzzles[0] as Vector3)
	_say("炮口 = %s   三种弹都停在沿弹道 %.0f m 处" % [_fmt3(origin), PARK_AT])
	_say("柯西 rifle_scale = %.2f   （C 号弹刻意用阿利宙斯的 %.1f×）"
		% [_pc.profile.rifle_scale, BIG_SCALE])

	# ---- A / B：走真开火路径 ----
	var beam := _fire("beam")
	var vul: Node3D = _fire("vulcan")
	if beam == null or vul == null:
		_say("❌ 有一发没打出来（beam=%s vulcan=%s）" % [str(beam), str(vul)])
		get_tree().quit(4)
		return

	# ---- C：手造一发阿利宙斯尺寸的光束（同样的 `Projectile.beam` 入口，只改 size_mul）----
	var from_c := origin + _side(aim) * LANE_C
	var big: Node3D = Projectile.beam(_cont, from_c, aim, _pc,
		_pc.profile.rifle_damage, Color(0.68, 0.32, 1.0, 0.96),
		PARK_AT + 400.0, BIG_SCALE, 0.0)

	# ---- D：**负对照** —— 一个故意歪 TILT_DEG° 的同尺寸盒子 ----
	# 它不参与任何判定，只用来证明「④ 端点偏差」这个量**能**变红。
	# 没有负对照的判据很可能是永真的假判据（本工程的常见翻车方式之一）。
	var tilt: Node3D = _tilted_box(aim, TILT_DEG, origin + _side(aim) * LANE_D + aim * PARK_AT)

	var bd: Vector3 = beam.get("direction")
	var vd: Vector3 = vul.get("direction")
	var cd: Vector3 = big.get("direction")
	_park(beam, origin + _side(aim) * LANE_A, bd, PARK_AT)
	_park(vul, origin + _side(aim) * LANE_B, vd, PARK_AT)
	_park(big, from_c, cd, PARK_AT)

	# ---- 端点参考球（只由 dir 算，与网格无关）+ 读数 ----
	_say("")
	_say("--- 读数：弹体长轴 vs 飞行方向 vs 机头；端点参考球偏差 ---")
	var dev_a := _report("A 光束", beam, bd, nose, Color(1.0, 0.15, 0.15))
	var dev_b := _report("B 火神炮", vul, vd, nose, Color(0.15, 0.85, 1.0))
	var dev_c := _report("C 阿利宙斯尺寸", big, cd, nose, Color(1.0, 1.0, 1.0))
	var dev_d := _report("D 负对照歪%.0f°" % TILT_DEG, tilt, cd, nose, Color(1.0, 0.55, 0.0))
	_say("")
	_say("端点参考球偏差（m，对齐时应 ≈ 0）：A %.3f   B %.3f   C %.3f"
		% [dev_a, dev_b, dev_c])
	_say("负对照 D（故意歪 %.0f°）偏差 %.3f m ← **判据能变红**，不是永真的"
		% [TILT_DEG, dev_d])

	await _shots(origin, aim, nose, beam, vul, big, tilt)
	_say("")
	_say("参考球颜色：A 光束=红   B 火神炮=青   C 阿利宙斯尺寸=白   D 负对照=橙   机头链=蓝")
	_say("读法：每根光柱两端的亮球是**由飞行方向算出来的参考点**（与网格朝向无关）。")
	_say("      A/B/C 的亮球罩在光柱两个端面上 ⇒ 弹体朝向 = 飞行方向；")
	_say("      07 图那根 D 是**故意歪 %.0f°** 的对照，亮球明显不在它端面上 ⇒ 判据能变红。" % TILT_DEG)
	_say("      机头方向与弹道差 %.1f° —— 这是全工程唯一「看着不跟准星」的东西。" % _ang(aim, nose))
	get_tree().quit(0)


# ------------------------------------------------------------ 工具

func _side(dir: Vector3) -> Vector3:
	var s := dir.normalized().cross(Vector3.UP)
	if s.length_squared() < 1e-6:
		s = Vector3.RIGHT
	return s.normalized()


## **负对照**：一个与火神炮弹体同尺寸、但长轴**故意歪 `deg`°** 的盒子。
##
## 它不参与任何结论，只回答一个问题：「④ 端点偏差」这个量**能**变红吗？
## 一个从来没红过的判据，和没有判据是一回事。
func _tilted_box(dir: Vector3, deg: float, at: Vector3) -> Node3D:
	var holder := Node3D.new()
	_cont.add_child(holder)
	holder.global_position = at
	var d := dir.normalized()
	var axis := d.rotated(_side(d), deg_to_rad(deg))
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	holder.look_at(holder.global_position + axis, up)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.0)
	mat.emission_energy_multiplier = 4.0
	mat.disable_receive_shadows = true
	var bx := BoxMesh.new()
	bx.size = Vector3(0.55, 0.55, 16.0)
	var mi := MeshInstance3D.new()
	mi.mesh = bx
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	return holder


func _fire(kind: String) -> Node3D:
	var before := _cont.get_child_count()
	if kind == "beam":
		_pc.rifle_cooldown = 0.0
		_pc.rifle_reloading = false
		_pc.rifle_count = maxi(_pc.rifle_count, 3)
		_pc.rifle_mag = maxi(_pc.rifle_mag, 20)
		_pc.fire_beam(true, null)
	else:
		_pc.gun_cooldown = 0.0
		_pc.vulcan_overheated = false
		_pc.fire_gun(true, null)
	var after := _cont.get_child_count()
	if after <= before:
		return null
	return _cont.get_child(after - 1) as Node3D


## 接管一发弹丸：停掉物理、钉在弹道中途。**只动位置，不动旋转**（朝向仍是 `spawn()` 定的）。
func _park(p: Node3D, from: Vector3, dir: Vector3, at: float) -> void:
	p.set_physics_process(false)
	p.global_position = from + dir.normalized() * at


## 弹体**实际**的最长局部轴：运行期读网格资源尺寸 × 节点 scale，不靠记忆。
## 返回 [世界单位方向, 说明, 世界半长(m)]。
func _long_axis(p: Node3D) -> Array:
	var mi := p.get_child(0) as MeshInstance3D
	if mi == null:
		return [Vector3.ZERO, "**没有网格子节点**", 0.0]
	if mi.mesh is BoxMesh:
		var sz := (mi.mesh as BoxMesh).size
		var sg := mi.scale
		var ext := Vector3(sz.x * absf(sg.x), sz.y * absf(sg.y), sz.z * absf(sg.z))
		var ai := 0
		if ext.y > ext[ai]:
			ai = 1
		if ext.z > ext[ai]:
			ai = 2
		var loc := Vector3.ZERO
		loc[ai] = 1.0
		return [(mi.global_transform.basis * loc).normalized(),
			"BoxMesh 最长轴 = 局部 %s，世界长 %.1f m（size=%s × scale=%s）"
				% ["XYZ"[ai], ext[ai], _fmt3(sz), _fmt3(sg)],
			ext[ai] * 0.5]
	if mi.mesh is CylinderMesh:
		var cm := mi.mesh as CylinderMesh
		var ln := cm.height * absf(mi.scale.y)
		return [mi.global_transform.basis.y.normalized(),
			"CylinderMesh 轴 = 局部 Y，世界长 %.1f m（height=%.1f × scale.y=%.2f）"
				% [ln, cm.height, mi.scale.y],
			ln * 0.5]
	return [mi.global_transform.basis.z.normalized(), "未知网格，退回局部 Z", 0.0]


func _ball(pos: Vector3, tint: Color, r: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 5.0
	mat.disable_receive_shadows = true
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	s.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cont.add_child(mi)
	mi.global_position = pos


## 打印一发弹的读数，并在它两个"应该在哪"的端点放参考球。返回端点偏差（m）。
func _report(tag: String, p: Node3D, dir: Vector3, nose: Vector3, tint: Color) -> float:
	var d := dir.normalized()
	var got := _long_axis(p)
	var axis: Vector3 = got[0]
	var half: float = got[2]
	_say("  %-14s ① 飞行方向 %s" % [tag, _fmt3(d)])
	_say("                ② −(p.basis.z) %s  与① %7.3f°"
		% [_fmt3(-p.global_transform.basis.z), _ang(-p.global_transform.basis.z, d)])
	_say("                ③ 弹体长轴    %s  与① %7.3f°   与机头 %7.3f°"
		% [_fmt3(axis), _ang(axis, d), _ang(axis, nose)])
	_say("                   [%s]" % got[1])
	# 参考球：位置**只由 dir 与半长算**，与 axis 无关（否则就是循环论证）
	var ep := p.global_position + d * half
	var em := p.global_position - d * half
	_ball(ep, tint, 3.0)
	_ball(em, tint, 3.0)
	var a1 := p.global_position + axis * half
	var a2 := p.global_position - axis * half
	# ⚠️ 取「每个端点到**最近**那颗参考球」的距离：盒 / 圆柱**两端不可区分**，
	# 共线反向（axis = −d）时"远端"恰好落在**另一颗**参考球上 ——
	# 直接配 `a1↔ep` 会报出 2×半长 的虚警（第一版就是，光束报了 52.000 m）。
	var dev := maxf(minf(a1.distance_to(ep), a1.distance_to(em)),
		minf(a2.distance_to(ep), a2.distance_to(em)))
	_say("                ④ 弹体端面 vs 参考球 偏差 %7.3f m   （= 半长 %.1f m × sin 夹角）"
		% [dev, half])
	return dev


# ------------------------------------------------------------ 出图

func _shot(name: String) -> void:
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	_say("出图 %s  %dx%d" % [path, img.get_width(), img.get_height()])


func _cam() -> Camera3D:
	var c := Camera3D.new()
	c.fov = 60.0
	c.far = 90000.0
	_host.add_child(c)
	c.current = true
	return c


func _shots(origin: Vector3, aim: Vector3, nose: Vector3,
		beam: Node3D, vul: Node3D, big: Node3D, tilt: Node3D) -> void:
	var d := aim.normalized()
	var side := _side(aim)
	var mid_ab := (beam.global_position + vul.global_position) * 0.5

	# ① A+B 同框侧视
	var c1 := _cam()
	c1.global_position = mid_ab + side * 200.0 + Vector3.UP * 60.0
	c1.look_at(mid_ab, Vector3.UP)
	await _shot("01_侧视_光束与火神炮同框")

	# ② 光束特写（垂直弹道 95 m）
	var c2 := _cam()
	c2.global_position = beam.global_position + side * 95.0 + Vector3.UP * 26.0
	c2.look_at(beam.global_position, Vector3.UP)
	await _shot("02_特写_光束")

	# ③ 火神炮特写（垂直弹道 46 m）
	var c3 := _cam()
	c3.global_position = vul.global_position + side * 46.0 + Vector3.UP * 13.0
	c3.look_at(vul.global_position, Vector3.UP)
	await _shot("03_特写_火神炮")

	# ④ 阿利宙斯尺寸（166 m）特写
	var c4 := _cam()
	c4.global_position = big.global_position + side * 260.0 + Vector3.UP * 70.0
	c4.look_at(big.global_position, Vector3.UP)
	await _shot("04_特写_阿利宙斯尺寸166m")

	# ⑤ 顺弹道看：对齐时弹体缩成一个小端面；横着的话是一条横线
	var c5 := _cam()
	c5.global_position = beam.global_position - d * 130.0 + Vector3.UP * 1.0
	c5.look_at(beam.global_position, Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT)
	await _shot("05_顺弹道看_光束端面")

	# ⑥ 机头 vs 弹道：相机放在**弹道与机头所在平面的法线上**（`side` 轴），
	#    这样分叉不会被透视压扁 —— 站在斜面看，31° 会缩成十几度。
	#    ⚠️ 视线**瞄准两条线的中分线**上 150 m 处，否则两条线会被画面裁掉一头
	#    （上一版瞄 `(nose+d)/2` 的 95 m 处、机位 210 m，结果弹道整条出画）。
	var c6 := _cam()
	c6.global_position = origin + (nose + d).normalized() * 150.0 + side * 260.0 + Vector3.UP * 85.0
	c6.look_at(origin + (nose + d).normalized() * 150.0, Vector3.UP)
	for k in range(0, 6):
		_ball(origin + nose * (40.0 * float(k + 1)), Color(0.35, 0.62, 1.0), 6.0)
	await _shot("06_侧视_机头vs弹道")

	# ⑦ **负对照特写**：故意歪 30° 的那根 —— 参考球明显不在它端面上
	var c7 := _cam()
	c7.global_position = tilt.global_position + side * 52.0 + Vector3.UP * 20.0
	c7.look_at(tilt.global_position, Vector3.UP)
	await _shot("07_负对照_故意歪30度")
