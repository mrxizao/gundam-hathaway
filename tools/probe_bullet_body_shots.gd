extends Node
## 判据出图探针：**弹体（网格）到底有没有躺在自己的弹道上**。
##
## ## 为什么不能只靠数字
##
## `probe_bullet_body.gd` 已经量出「网格长轴与飞行方向夹角 = 180.000°」——
## 那是**共线但反向**。对圆柱 / 正方截面的盒子来说反向看不出来，所以数字上说"对"，
## 可用户看的是**画面**。本探针把三者放进同一张图：
##
##   ① 串绿球 = **弹道本身**（只由 `Projectile.direction` 算出来，与任何网格无关）；
##   ② 弹丸  = 真正被渲染的那个网格；
##   ③ 机体  = 机头 / 枪管朝哪儿。
##
## 判据（可证伪）：
##   · 弹丸那条光柱 **躺在绿球串上** ⇒ 弹体朝向 = 飞行方向，对；
##   · 光柱 **横切** / 立着 / 与绿球串成夹角 ⇒ 弹体朝向错，一眼可见。
##
## ## 手动接管弹丸的位移
##
## 真开火之后立刻 `set_physics_process(false)`，再用
## `global_position = from + dir * BULLET_AT` 把它**停在弹道中途**。
## 理由：光束出膛段 0.3 s 后就切到接近光速（一帧几百米），不接管的话
## 相机根本框不住它。接管只动位置，**不动旋转** —— 朝向仍是 `spawn()` 里定的那个。
##
## ## 跑法（⚠️ **不能加 `--headless`**：无头下 RenderingServer 是 dummy，出不了像素）
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       res://tools/probe_bullet_body_shots.tscn -- <输出目录>

const SHOT_W := 1600
const SHOT_H := 900
## 机体高度。⚠️ 不能放 y=0：`CRASH_ALTITUDE = 24`，第一帧就撞海自毁（`alive=false`）。
const ALT := 3000.0
## 弹道参考球的间隔（m）与个数。
const MARK_EVERY := 150.0
const MARK_N := 9
## 两种弹**分别**停在这些距离上（m）。刻意错开：同一位置会让两条光柱完全重叠，
## 图上分不清哪根是谁的（第一版就是这么拍的，白拍了一次）。
const BEAM_AT := 420.0
const VULCAN_AT := 900.0

var _out := "user://pbb_shots"
var _host: Node3D = null
var _cont: Node3D = null
var _pc: PlayerController = null
var _log: Array[String] = []


func _ready() -> void:
	_run()


func _say(s: String) -> void:
	_log.append(s)
	print("[bb] " + s)


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

	# ---- 一个最小环境：只为了让机体有光，弹丸/参考球是自发光的，本来就看得到 ----
	_host = Node3D.new()
	_host.name = "Host"
	add_child(_host)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.06, 0.11)
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

	# ---- 准星与机头拉开约 25°，两者在图上才分得开 ----
	#
	# ⚠️ **不能只靠注入鼠标事件**：窗口模式下真鼠标每帧都在动，`_think()` →
	# `_read_aim_input()` 会拿真实光标把我注入的准星覆盖掉（实测 `aim_forward()`
	# 直接等于机头，夹角 0.000°，图就白拍了）。
	# 所以这里直接写 `set_aim_direction()`，**并且在同一帧内立刻开火**（中间没有 await）
	# —— `_think()` 没有机会插进来覆盖。读数与图用的是同一个方向。
	var vs := get_viewport().get_visible_rect().size
	var nose := _pc.forward()
	var want_aim := (nose + _pc.right() * 0.60).normalized()
	_pc.set_aim_direction(want_aim)
	var aim := _pc.aim_forward()
	_say("准星方向 aim_forward = %s" % _fmt3(aim))
	_say("机头方向 forward     = %s   两者夹角 %.3f°" % [_fmt3(nose), _ang(aim, nose)])
	if _ang(aim, nose) < 5.0:
		_say("❌ 准星没和机头分开（%.3f°）—— 图会看不出差别" % _ang(aim, nose))

	var muzzles: Array = _pc.get("_muzzle_local")
	var origin: Vector3 = _pc.global_transform * (muzzles[0] as Vector3)
	_say("炮口 = %s   光束停在弹道 %.0f m、火神炮停在 %.0f m（错开，别重叠）"
		% [_fmt3(origin), BEAM_AT, VULCAN_AT])

	# ---- 开火（真路径），拿到弹丸。**与上面的 set_aim_direction 同一帧** ----
	var beam := _fire("beam")
	var vul: Node3D = _fire("vulcan")
	if beam == null or vul == null:
		_say("❌ 有一发没打出来（beam=%s vulcan=%s）" % [str(beam), str(vul)])
		get_tree().quit(4)
		return

	# ---- 把弹丸钉在弹道中途，并量三者的朝向 ----
	var bd: Vector3 = beam.get("direction")
	var vd: Vector3 = vul.get("direction")
	_park(beam, origin, bd, BEAM_AT)
	_park(vul, origin, vd, VULCAN_AT)

	_say("")
	_say("--- 读数（网格长轴 vs 自己的飞行方向）---")
	_measure("光束", beam, true, bd, nose)
	_measure("火神炮", vul, false, vd, nose)

	# ---- 参考球：只由 direction 算出，和网格没有关系 ----
	_markers(origin, bd, Color(0.25, 1.0, 0.45), 0.0)
	_markers(origin, nose, Color(0.35, 0.62, 1.0), 40.0)

	await _shots(origin, bd, nose)
	_say("")
	_say("读法：绿球串 = 光束自己的弹道；蓝球串 = 机头方向（错开 40 m 摆的，不重叠）。")
	_say("      光束光柱若**躺在绿球串上** ⇒ 弹体朝向对；横着 / 立着 ⇒ 错。")
	get_tree().quit(0)


# ------------------------------------------------------------ 工具

func _aim_at(p: Vector2) -> bool:
	var f := get_viewport().get_final_transform()
	var ev := InputEventMouseMotion.new()
	ev.position = f * p
	ev.global_position = ev.position
	ev.relative = Vector2.ZERO
	Input.parse_input_event(ev)
	await _phys(2)
	if _pc.aim_cursor.distance_to(p) <= 1.0:
		return true
	_pc.cursor_seen = true
	_pc.aim_cursor = p
	await _phys(2)
	return false


## 走**真**开火路径，返回那一发弹丸节点。
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


## 接管一发弹丸：停掉它的物理，钉在弹道中途。**只动位置，不动旋转。**
func _park(p: Node3D, from: Vector3, dir: Vector3, at: float) -> void:
	p.set_physics_process(false)
	p.global_position = from + dir.normalized() * at


func _measure(tag: String, p: Node3D, is_beam: bool, dir: Vector3, nose: Vector3) -> void:
	var mi := p.get_child(0) as MeshInstance3D
	var mesh_axis := Vector3.ZERO
	var which := ""
	if mi != null:
		if is_beam:
			mesh_axis = mi.global_transform.basis.y
			which = "网格局部 Y（圆柱轴）"
		else:
			mesh_axis = mi.global_transform.basis.z
			which = "网格局部 Z（盒长轴）"
	_say("  %-8s ① 飞行方向 %s" % [tag, _fmt3(dir)])
	_say("           ② −(p.basis.z) %s  与① %7.3f°" % [_fmt3(-p.global_transform.basis.z), _ang(-p.global_transform.basis.z, dir)])
	_say("           ③ 网格长轴    %s  与① %7.3f°  [%s]" % [_fmt3(mesh_axis), _ang(mesh_axis, dir), which])
	_say("              与机头 %7.3f°     网格 scale=%s" % [_ang(mesh_axis, nose),
		_fmt3(mi.scale) if mi != null else "-"])


## 沿 `dir` 从 `from` 撒一串自发光小球。`lateral` = 整体侧移（避免两组球重叠）。
func _markers(from: Vector3, dir: Vector3, tint: Color, lateral: float) -> void:
	var d := dir.normalized()
	var side := d.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 4.0
	mat.disable_receive_shadows = true
	for k in range(1, MARK_N + 1):
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 7.0
		s.height = 14.0
		s.radial_segments = 10
		s.rings = 6
		s.material = mat
		mi.mesh = s
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cont.add_child(mi)
		mi.global_position = from + d * (MARK_EVERY * float(k)) + side * lateral


# ------------------------------------------------------------ 出图

func _shot(name: String) -> void:
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	_say("出图 %s  %dx%d" % [path, img.get_width(), img.get_height()])


func _make_cam() -> Camera3D:
	var c := Camera3D.new()
	c.fov = 60.0
	c.far = 90000.0
	_host.add_child(c)
	c.current = true
	return c


func _shots(origin: Vector3, dir: Vector3, nose: Vector3) -> void:
	var d := dir.normalized()
	var side := d.cross(Vector3.UP).normalized()
	var mid := origin + d * ((BEAM_AT + VULCAN_AT) * 0.5)

	# ---- 机位 1：侧上方（弹道横贯画面，最容易看出"躺在不躺在线上"）----
	var c1 := _make_cam()
	c1.global_position = mid + side * 1250.0 + Vector3.UP * 520.0 - d * 200.0
	c1.look_at(mid, Vector3.UP)
	await _shot("01_侧上方_弹道对照")

	# ---- 机位 2：正侧方（把"机头"和"弹道"的分叉拍出来）----
	var c2 := _make_cam()
	c2.global_position = origin + side * 1600.0 + Vector3.UP * 70.0 + d * 620.0
	c2.look_at(origin + d * 700.0, Vector3.UP)
	await _shot("02_正侧方_机头vs弹道")

	# ---- 机位 3：机后跟随（玩家视角；看弹丸从炮口出去时的样子）----
	var c3 := _make_cam()
	c3.global_position = _pc.global_position - nose * 190.0 + Vector3.UP * 55.0
	c3.look_at(origin + d * (VULCAN_AT * 0.75), Vector3.UP)
	await _shot("03_机后跟随")

	# ---- 机位 4：俯视（弹道的水平分叉看得最清）----
	var c4 := _make_cam()
	var ctr := origin + d * ((BEAM_AT + VULCAN_AT) * 0.5)
	c4.global_position = ctr + Vector3.UP * 1700.0
	c4.look_at(ctr, Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT)
	await _shot("04_俯视")
