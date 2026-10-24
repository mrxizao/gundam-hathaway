extends Node
## 判据探针：光束步枪 / 火神炮的**真实弹道方向**到底跟不跟鼠标准星。
##
## ## 为什么必须另写一个探针
##
## `tests/suite_input.gd::_mouse_reticle()` 也是测"准星 → 弹道"，但它
## **直接赋值 `pc.aim_cursor`、再直接 `pc.call("_read_aim_input")`** ——
## 于是它只证明了"那个纯函数算得对"，对下面两件事**一概不覆盖**：
##
##   ① 真鼠标事件有没有落到 `PlayerController._input()` 上（事件通道）；
##   ② 武器开火时真正用的那条解算 `FlightBody.aim_point()` 读的是谁 ——
##      它**不是**直接读 `aim_forward()`，中间还夹着"有没有目标"的分支，
##      以及那条会把弹道往目标拽的**辅助瞄准**（`aim_assist_weight`）。
##
## 用户报的正是 ② 这一类。所以本探针**不手工调用 `_read_aim_input()`**：
## 让 `_think()` 自己走完整链路；再用 `fire_beam()` / `fire_gun()` 真开火，
## 读**弹丸自己的 `direction`**。
##
## ## 两个已经把探针自己坑掉的雷（都做成了自检，别再踩）
##
##   ① **机体不能放在 y=0**：`CRASH_ALTITUDE = 24`，第一个物理帧就 `destroy("撞海")`，
##      `alive=false` ⇒ `_physics_process` 直接 return ⇒ `_think()` 永不跑 ⇒
##      `aim_dir` 恒 ZERO ⇒ **"跟准星 0°"和"跟机头 0°"会同时成立**，整节读数是废的。
##      本探针用 `_think 在跑` 这条自检把它挡在读数之前（判据：`fm.throttle == 0.800`）。
##   ② **注入的鼠标坐标要过视口变换**：`_input()` 里拿到的 `mm.position` 与
##      HUD 画准星用的 `size` 差一个 content-scale（headless 实测 **25 倍**）。
##      本探针注入后**回读 `aim_cursor` 比对**，补偿失效就明说并退回直接赋值。
##
## 用法：
##   "C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" \
##     --headless --path . res://tools/probe_aim_follow.tscn

const ALT := 3000.0

var _host: Node3D = null
var _cont: Node3D = null
var _pc: PlayerController = null
var _cam: Camera3D = null
var _foe: FlightBody = null
var _lock: LockOnSystem = null
var _log: Array[String] = []
var _chan_ok := false


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	for l: String in _log:
		print(l)
	print("=== 探针结束 ===")
	get_tree().quit()


func _say(s: String) -> void:
	_log.append(s)


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ang(a: Vector3, b: Vector3) -> float:
	if a.length_squared() < 1e-9 or b.length_squared() < 1e-9:
		return -1.0
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


func _fmt3(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]


## 打一发真弹，返回**弹丸自己**的方向（不是我们算的那条）。
func _fire_and_dir(kind: String, target: Node3D) -> Vector3:
	var before := _cont.get_child_count()
	if kind == "beam":
		_pc.rifle_cooldown = 0.0
		_pc.rifle_reloading = false
		_pc.rifle_count = maxi(_pc.rifle_count, 3)
		_pc.rifle_mag = maxi(_pc.rifle_mag, 20)
		_pc.fire_beam(true, target)
	else:
		_pc.gun_cooldown = 0.0
		_pc.vulcan_overheated = false
		_pc.fire_gun(true, target)
	var after := _cont.get_child_count()
	if after <= before:
		return Vector3.ZERO
	var d: Variant = _cont.get_child(after - 1).get("direction")
	return d if d is Vector3 else Vector3.ZERO


func _clear_shots() -> void:
	for c: Node in _cont.get_children():
		if c != _pc and c != _foe:
			c.queue_free()


## 取「第 before 个之后新增的那个」子节点的 direction（弹丸自己的方向）。
func _last_from(before: int) -> Vector3:
	var after := _cont.get_child_count()
	if after <= before:
		return Vector3.ZERO
	var d: Variant = _cont.get_child(after - 1).get("direction")
	return d if d is Vector3 else Vector3.ZERO


## 注入一个**真**鼠标移动事件，然后**回读** `aim_cursor` 自检补偿是否成立。
##
## 返回：读数可用时为 true（无论走的是注入还是退回直接赋值）。
func _aim_at(p: Vector2) -> bool:
	var f := get_viewport().get_final_transform()
	var ev := InputEventMouseMotion.new()
	ev.position = f * p
	ev.global_position = ev.position
	ev.relative = Vector2.ZERO
	Input.parse_input_event(ev)
	await _phys(2)
	var got := _pc.aim_cursor
	if got.distance_to(p) <= 1.0:
		return true
	# 补偿失效：明说，并退回直接赋值 —— 静默给假读数是最坏的一种
	_say("  ⚠️ 注入坐标补偿失效：实收 (%.0f, %.0f)，期望 (%.0f, %.0f)，差 %.1f px"
		% [got.x, got.y, p.x, p.y, got.distance_to(p)])
	_say("     ⇒ 本节退回「直接赋值 aim_cursor」（事件通道已在第 1 节单独验过）")
	_pc.cursor_seen = true
	_pc.aim_cursor = p
	await _phys(2)
	return false


# ------------------------------------------------------------ 主流程

func _run() -> void:
	_say("")
	_say("################################################################")
	_say("#  探针：光束步枪 / 火神炮 的弹道是否跟随鼠标准星")
	_say("################################################################")

	Game.reset()
	_host = Node3D.new()
	add_child(_host)
	_cont = Node3D.new()
	_cont.name = "Shots"
	_host.add_child(_cont)

	_cam = Camera3D.new()
	_cam.current = true
	_host.add_child(_cam)

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

	_cam.global_position = _pc.global_position + Vector3(0.0, 0.0, 120.0)
	_cam.look_at(_pc.global_position, Vector3.UP)

	_pc.controls_enabled = true
	_pc.debug_input_enabled = true
	_pc.debug_input = Vector3.ZERO
	_pc.debug_throttle = 0.8
	_pc.mouse_lock_enabled = true
	_pc.cursor_seen = false
	_pc.set_aim_direction(Vector3.ZERO)
	await _phys(4)

	var vs := get_viewport().get_visible_rect().size
	var ft := get_viewport().get_final_transform()
	var think_ran := absf(_pc.fm.throttle - 0.8) < 0.001

	_say("")
	_say("--- 0 环境自检（**先证明探针自己没坏**）---")
	_say("  viewport 可见尺寸      = %.0f x %.0f" % [vs.x, vs.y])
	_say("  窗口尺寸(DisplayServer)= %s" % str(DisplayServer.window_get_size()))
	_say("  get_final_transform()  = 缩放 %.4f  平移 (%.1f, %.1f)   ← headless 下非 1 属正常"
		% [ft.get_scale().x, ft.origin.x, ft.origin.y])
	_say("  get_camera_3d() 非空   = %s" % ("是" if get_viewport().get_camera_3d() != null else "**否**"))
	_say("  pc.alive               = %s   ← false 则 _physics_process 直接 return"
		% str(_pc.alive))
	_say("  pc.hp                  = %.0f" % _pc.hp)
	_say("  _think() 在跑          = %s   （判据 fm.throttle = %.3f，期望 0.800）"
		% [str(think_ran), _pc.fm.throttle])
	_say("  pc.aim_dir             = %s" % _fmt3(_pc.aim_dir))
	_say("  pc.aim_forward()       = %s" % _fmt3(_pc.aim_forward()))
	_say("  pc.forward()           = %s" % _fmt3(_pc.forward()))
	_say("  muzzles                = %d 个" % _pc.get("_muzzle_local").size())
	if not think_ran or not _pc.alive:
		_say("")
		_say("  ❌ **自检没过 —— 下面所有读数无效，先修探针。**")
		return

	# ---- 1 事件通道 ----
	_say("")
	_say("--- 1 事件通道：真 InputEventMouseMotion 能不能落到 _input() ---")
	var chan_real := await _aim_at(Vector2(vs.x * 0.92, vs.y * 0.5))
	_chan_ok = chan_real
	_say("  cursor_seen            = %s" % str(_pc.cursor_seen))
	_say("  aim_cursor             = (%.0f, %.0f)   期望 (%.0f, %.0f)"
		% [_pc.aim_cursor.x, _pc.aim_cursor.y, vs.x * 0.92, vs.y * 0.5])
	_say("  注入坐标补偿成立       = %s" % ("是（用的是真事件通道）" if chan_real else "否（本节退回直接赋值）"))
	var aim_r := _pc.aim_forward()
	_say("  pc.aim_dir             = %s" % _fmt3(_pc.aim_dir))
	_say("  pc.aim_forward()       = %s" % _fmt3(aim_r))
	_say("  aim_forward · 机头      = %+.4f" % aim_r.dot(_pc.forward()))
	_say("  aim_forward · right    = %+.4f   ← 准星在右 ⇒ 必须为正，否则『准星→弹道』整条就断了"
		% aim_r.dot(_pc.right()))
	var aim_deg := _ang(aim_r, _pc.forward())
	_say("  aim_forward 与机头夹角  = %.3f°" % aim_deg)

	# ---- 2 无目标开火 ----
	_say("")
	_say("--- 2 开火 · target = null（**没锁定**）---")
	var b1 := _fire_and_dir("beam", null)
	var v1 := _fire_and_dir("vulcan", null)
	_say("  光束步枪 弹丸 direction = %s" % _fmt3(b1))
	_say("  火神炮   弹丸 direction = %s" % _fmt3(v1))
	_say("  ── 与「准星方向 aim_forward」的夹角（0 = 完全跟准星）──")
	_say("     光束 %7.3f°      火神炮 %7.3f°" % [_ang(b1, aim_r), _ang(v1, aim_r)])
	_say("  ── 与「机头方向 forward」的夹角（0 = 完全跟机头）──")
	_say("     光束 %7.3f°      火神炮 %7.3f°" % [_ang(b1, _pc.forward()), _ang(v1, _pc.forward())])
	_say("  ── 侧向分量（准星在右 ⇒ 正 = 跟着准星偏右）──")
	_say("     光束 %+.4f      火神炮 %+.4f" % [b1.dot(_pc.right()), v1.dot(_pc.right())])
	_clear_shots()
	await _phys(2)

	# ---- 3 准星甩到另一边 ----
	_say("")
	_say("--- 3 准星甩到左边（同一条判据的另一半）---")
	await _aim_at(Vector2(vs.x * 0.08, vs.y * 0.5))
	var aim_l := _pc.aim_forward()
	_say("  aim_forward            = %s" % _fmt3(aim_l))
	_say("  aim_forward · right    = %+.4f   ← 准星在左 ⇒ 必须为负" % aim_l.dot(_pc.right()))
	_say("  准星自身摆动了          = %.3f°   ← 准星确实动了" % _ang(aim_r, aim_l))
	var b2 := _fire_and_dir("beam", null)
	var v2 := _fire_and_dir("vulcan", null)
	_say("  光束 弹丸 · right       = %+.4f" % b2.dot(_pc.right()))
	_say("  火神炮 弹丸 · right     = %+.4f" % v2.dot(_pc.right()))
	_say("  ── 两条弹道各自的摆动角 ──")
	_say("     光束 %7.3f°      火神炮 %7.3f°     （≈0 = 弹道没跟准星动）"
		% [_ang(b1, b2), _ang(v1, v2)])
	_clear_shots()
	await _phys(2)

	# ---- 4 有目标开火 ----
	_say("")
	_say("--- 4 开火 · 有目标（靶机在机头正前方 4000 m，准星仍甩在右边）---")
	_foe = FlightBody.new()
	_foe.name = "FOE"
	_foe.team = 1
	_foe.is_player = false
	_foe.profile = SuitProfile.xi()
	_foe.display_name = "FOE"
	_foe.projectile_container = _cont
	_cont.add_child(_foe)
	_foe.global_position = _pc.global_position + _pc.forward() * 4000.0
	_foe.hp = 600.0
	_foe.max_hp = 600.0
	_foe.fm.speed = 260.0
	_foe.fm.throttle = 0.78
	_foe.fm.align_velocity(_foe.forward())
	await _phys(4)

	await _aim_at(Vector2(vs.x * 0.92, vs.y * 0.5))
	var aim_r2 := _pc.aim_forward()
	_say("  准星 · right           = %+.4f" % aim_r2.dot(_pc.right()))
	var b4 := _fire_and_dir("beam", _foe)
	var v4 := _fire_and_dir("vulcan", _foe)
	_say("  ── 与准星夹角 ──  光束 %7.3f°   火神炮 %7.3f°" % [_ang(b4, aim_r2), _ang(v4, aim_r2)])
	_say("  ── 与机头夹角 ──  光束 %7.3f°   火神炮 %7.3f°"
		% [_ang(b4, _pc.forward()), _ang(v4, _pc.forward())])
	_say("  光束 · right %+.4f     火神炮 · right %+.4f" % [b4.dot(_pc.right()), v4.dot(_pc.right())])
	_clear_shots()
	await _phys(2)

	# ---- 4b 锁定后 · 准星在目标附近小幅推：辅助瞄准有没有"死区" ----
	#
	# 这是**最常见的姿态**（准星罩着敌机开火），也是"不跟随"最容易被玩家察觉的地方：
	# `aim_point()` 有目标时会把弹道从准星方向 `slerp` 到**提前量点**，权重由
	# `aim_assist_weight()` 给：夹角 ≤ 2.5° → 权重 1.0（**完全不听准星**）、
	# ≥ 7° → 0.0。所以准星在目标附近小幅移动时，弹道可能一动不动。
	#
	# ⚠️ 把靶机**冻住**（`set_physics_process(false)`）：这样提前量点 = 靶机位置，
	# 死区宽度是**下界**（真靶机在动时提前量点更远，角度更早越过 7°）。
	_say("")
	_say("--- 4b 锁定后 · 准星在目标附近小幅推（辅助瞄准的「死区」）---")
	_foe.set_physics_process(false)
	_foe.fm.velocity = Vector3.ZERO
	_foe.fm.speed = 0.0
	await _phys(2)
	# 把靶机放在**准星方向**上 4000 m（= "准星罩着敌机"）
	await _aim_at(Vector2(vs.x * 0.92, vs.y * 0.5))
	var aim_ref := _pc.aim_forward()
	_foe.global_position = _pc.global_position + aim_ref * 4000.0
	await _phys(3)
	_say("  靶机放在准星方向上（与首帧准星夹角 %.3f°）"
		% _ang(_pc.global_position.direction_to(_foe.global_position), aim_ref))
	_say("")
	_say("     准星 m.x    准星偏离参考    光束偏离参考    火神炮偏离参考   | 计入辅助的角度  w")
	_say("     --------    ------------    ------------    --------------   | --------------  -----")
	var ref_b := Vector3.ZERO
	var ref_v := Vector3.ZERO
	var samples: Array[float] = [0.84, 0.80, 0.72, 0.60, 0.30]
	for mi: float in samples:
		await _aim_at(Vector2(vs.x * (mi + 1.0) * 0.5, vs.y * 0.5))
		var a := _pc.aim_forward()
		# —— 把 `aim_point()` 里喂给 `aim_assist_weight()` 的那个角度**复算出来**：
		# 不然"辅助瞄准到底有没有生效"只能靠猜，而下面那两列数字就不是自明的了。
		var muzzles: Array = _pc.get("_muzzle_local")
		var origin := _pc.global_transform * (muzzles[0] as Vector3)
		var tp := _foe.global_position
		var dist := _pc.global_position.distance_to(tp)
		var boresight := _pc.global_position + a * dist
		var ang := Ballistics.angle_off_boresight(boresight - origin, tp - origin)
		var w := FlightBody.aim_assist_weight(ang)
		_pc.rifle_cooldown = 0.0
		_pc.rifle_reloading = false
		_pc.rifle_count = maxi(_pc.rifle_count, 3)
		_pc.rifle_mag = maxi(_pc.rifle_mag, 20)
		var before_b := _cont.get_child_count()
		_pc.fire_beam(true, _foe)
		var bd := _last_from(before_b)
		_pc.gun_cooldown = 0.0
		_pc.vulcan_overheated = false
		var before_v := _cont.get_child_count()
		_pc.fire_gun(true, _foe)
		var vd := _last_from(before_v)
		if ref_b.length_squared() < 1e-6:
			ref_b = bd
			ref_v = vd
		_say("     %8.2f    %10.3f°     %10.3f°      %10.3f°    | %12.3f°  %.3f"
			% [mi, _ang(a, aim_ref), _ang(bd, aim_ref), _ang(vd, aim_ref), ang, w])
		_clear_shots()
		await _phys(2)
	_say("")
	_say("  is_player = %s   ← false 的话 `aim_point()` 直接 return boresight，辅助那一段根本不进"
		% str(_pc.is_player))
	_say("  `aim_assist_weight(角度)`：≤2.5° → 1.000（完全指向提前量点，**不听准星**）；≥7° → 0.000")
	_say("  读法：准星那一列在变、弹道那两列**不动** ⇒ 弹道被辅助瞄准钉在提前量点上（死区）")
	_say("  读法：三者一起变 ⇒ 弹道跟着准星走")

	_foe.set_physics_process(true)

	# ---- 5 锁定系统会不会自动给玩家一个 target ----
	_say("")
	_say("--- 5 实战里玩家到底有没有 target ---")
	_lock = LockOnSystem.new()
	_host.add_child(_lock)
	_lock.setup(_pc)
	await _phys(45)
	_say("  lock.target 非空       = %s" % ("是 ⇒ aim_point 走「有目标」分支"
		if _lock.target != null else "否 ⇒ aim_point 走「无目标」兜底"))
	if _lock.target != null:
		_say("  lock.target            = %s，距离 %.1f m"
			% [str(_lock.target.name), _pc.global_position.distance_to(_lock.target.global_position)])
	_say("  player_controller.gd: `var target: Node3D = lock.target if lock != null else null`")

	# ---- 6 源码事实 ----
	_say("")
	_say("--- 6 源码事实：aim_point() 的无目标分支 ---")
	var src := FileAccess.get_file_as_string("res://scripts/flight/flight_body.gd")
	var key := "return origin + forward() * 4000.0"
	var i := src.find(key)
	_say("  flight_body.gd 里存在   = %s" % ("是" if i > 0 else "否"))
	if i > 0:
		var line := src.substr(0, i).count("\n") + 1
		_say("  行号                   = %d" % line)
		_say("  原文                   = %s" % key)
	_say("  （对照）有目标分支用的是 `aim_forward()` —— 两条路读的**不是同一个真源**")

	# ---- 7 单位错：辅助瞄准的权重函数吃的是**弧度**，喂进去的是**度** ----
	_say("")
	_say("--- 7 顺带查到：辅助瞄准（aim_assist_weight）的**单位错** ---")
	_say("  `Ballistics.angle_off_boresight()` 返回**度**：")
	_say("      angle_off_boresight(-Z, 偏 1° 的向量) = %.6f" % Ballistics.angle_off_boresight(
		Vector3.FORWARD, Vector3(sin(deg_to_rad(1.0)), 0.0, -cos(deg_to_rad(1.0)))))
	_say("  而 `FlightBody.aim_assist_weight(angle_rad)` 的形参名要的是**弧度**：")
	_say("      传 1.0（被当成 1 rad = 57.3°）→ w = %.6f" % FlightBody.aim_assist_weight(1.0))
	_say("      传 deg_to_rad(1.0)（真正的 1°）→ w = %.6f" % FlightBody.aim_assist_weight(deg_to_rad(1.0)))
	_say("      传 deg_to_rad(4.0)（真正的 4°，落在 2.5°~7° 之间）→ w = %.6f"
		% FlightBody.aim_assist_weight(deg_to_rad(4.0)))
	_say("  ⚠️ 所以 `aim_point()` 那一行 `aim_assist_weight(angle_off_boresight(...))`：")
	_say("     只有真实夹角 < 0.0436° 时才返回 1.0，其余**一律 0.0** ⇒ 辅助瞄准实际是**死代码**。")
	_say("     后果：有目标时 `w=0` ⇒ `to_bore.slerp(to_lead, 0) = to_bore` ⇒ 弹道**恰好**跟着准星。")
	_say("     也就是说「跟准星」这一半是**撞对**的（单位错了才没被辅助拽走），不是设计成的。")
	_say("     ⇒ **不要顺手把这个单位改对**：那会让准星在目标附近重新被拽向提前量点，")
	_say("       与用户「发射方向跟随鼠标方向」的要求正好相反。要改先问用户要哪种手感。")
	_say("")
