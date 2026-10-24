extends Node
## 轮 40 补充判据：准星在屏幕**四个方向**上都动，弹道跟不跟。
##
## ## 为什么必须补这一个
##
## `tools/probe_aim_follow.gd` 只把准星在**水平**方向来回甩（`vs.y * 0.5` 恒不动）。
## 于是"弹道跟不跟准星"这件事在**俯仰**方向上**从来没被测过** ——
## 用户报的"子弹角度不变"，完全可能是垂直方向的那一半。
##
## 本探针把准星放到 9 个位置（上/下/左/右/四个角/正中），每个位置真开一发光束 +
## 一发火神炮，读**弹丸自己的 `direction`**，报：
##   - 与「准星方向 aim_forward」的夹角（0 = 完全跟准星）
##   - 与「机头方向 forward」的夹角（0 = 完全跟机头）
##   - 弹道的**俯仰角**（°）与**方位角**（°）——这两个数直接回答"角度会不会变"
##
## ⚠️ 同 `probe_aim_follow.gd`：机体必须放在 `CRASH_ALTITUDE` 之上，
##    否则 `alive=false` ⇒ `_think()` 不跑 ⇒ 整节读数是废的（而且看起来"全绿"）。
##
## 用法：
##   ".../Godot_v4.7.1-stable_win64_console.exe" --headless --path . res://tools/_r40_axis_probe.tscn

const ALT := 3000.0

var _pc: PlayerController = null
var _cont: Node3D = null
var _cam: Camera3D = null
var _log: Array[String] = []


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


## 俯仰角（°）：方向与水平面的夹角，抬头为正。
func _pitch(d: Vector3) -> float:
	if d.length_squared() < 1e-9:
		return -999.0
	return rad_to_deg(asin(clampf(d.normalized().y, -1.0, 1.0)))


## 方位角（°）：方向在水平面上的偏角，向右为正（相对机体 +X）。
func _yaw(d: Vector3) -> float:
	if d.length_squared() < 1e-9:
		return -999.0
	var lat := d.normalized().dot(_pc.right().normalized())
	var lon := d.normalized().dot(_pc.forward().normalized())
	return rad_to_deg(atan2(lat, lon))


func _fmt3(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]


func _fire_dir(kind: String) -> Vector3:
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
		return Vector3.ZERO
	var d: Variant = _cont.get_child(after - 1).get("direction")
	return d if d is Vector3 else Vector3.ZERO


func _clear_shots() -> void:
	for c: Node in _cont.get_children():
		c.queue_free()


## 注入真鼠标事件并**回读**自检；补偿失效就退回直接赋值（不静默给假读数）。
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


func _run() -> void:
	_say("")
	_say("################################################################")
	_say("#  轮 40 补充：准星在**四个方向**上，弹道跟不跟")
	_say("################################################################")

	Game.reset()
	var host := Node3D.new()
	add_child(host)
	_cont = Node3D.new()
	_cont.name = "Shots"
	host.add_child(_cont)
	_cam = Camera3D.new()
	host.add_child(_cam)
	_cam.current = true

	_pc = PlayerController.new()
	_pc.team = 0
	_pc.is_player = true
	_pc.profile = SuitProfile.xi()
	_pc.projectile_container = _cont
	host.add_child(_pc)
	_pc.global_position = Vector3(0.0, ALT, 0.0)
	_pc.max_hp = 600.0
	_pc.hp = 600.0
	_pc.ifield_max = 0.0
	_pc.ifield_hp = 0.0
	_pc.fm.speed = 260.0
	_pc.fm.throttle = 0.78
	_pc.fm.align_velocity(_pc.forward())
	await get_tree().process_frame
	_pc.controls_enabled = true
	_pc.debug_input_enabled = true
	_pc.debug_input = Vector3.ZERO
	_pc.debug_throttle = 0.8
	_pc.mouse_lock_enabled = true
	_pc.cursor_seen = false
	_pc.set_aim_direction(Vector3.ZERO)
	_cam.global_position = _pc.global_position + Vector3(0.0, 0.0, 120.0)
	_cam.look_at(_pc.global_position, Vector3.UP)
	await _phys(4)

	var vs := get_viewport().get_visible_rect().size
	var think_ran := absf(_pc.fm.throttle - 0.8) < 0.001
	_say("")
	_say("--- 0 前置自检 ---")
	_say("  pc.alive          = %s" % str(_pc.alive))
	_say("  _think() 在跑      = %s （判据 fm.throttle = %.3f）" % [str(think_ran), _pc.fm.throttle])
	_say("  camera_3d() 非空   = %s" % str(get_viewport().get_camera_3d() != null))
	_say("  viewport 可见尺寸   = %.0f x %.0f" % [vs.x, vs.y])
	_say("  机头 forward       = %s   俯仰 %+.3f°  方位 %+.3f°"
		% [_fmt3(_pc.forward()), _pitch(_pc.forward()), _yaw(_pc.forward())])
	if not _pc.alive or not think_ran or get_viewport().get_camera_3d() == null:
		_say("  ❌ 自检没过 —— 下面所有读数无效")
		return

	# 九个位置：fx / fy 都是 0..1 的屏幕比例
	var spots: Array = [
		["正中", 0.50, 0.50],
		["右", 0.92, 0.50],
		["左", 0.08, 0.50],
		["上", 0.50, 0.12],
		["下", 0.50, 0.88],
		["右上", 0.85, 0.20],
		["右下", 0.85, 0.80],
		["左上", 0.15, 0.20],
		["左下", 0.15, 0.80],
	]

	_say("")
	_say("--- 1 九个准星位置：准星方向 与 弹道方向 ---")
	_say("")
	_say("   位置    准星方位  准星俯仰 | 光束方位  光束俯仰 | 与准星夹角  与机头夹角 | 火神炮与准星夹角")
	_say("   ------  --------  -------- | --------  -------- | ----------  ---------- | ----------------")
	for s: Array in spots:
		await _aim_at(Vector2(vs.x * float(s[1]), vs.y * float(s[2])))
		var aim := _pc.aim_forward()
		var b := _fire_dir("beam")
		var v := _fire_dir("vulcan")
		_say("   %-6s  %+8.3f  %+8.3f | %+8.3f  %+8.3f | %9.3f°  %9.3f° | %15.3f°"
			% [str(s[0]), _yaw(aim), _pitch(aim), _yaw(b), _pitch(b),
				_ang(b, aim), _ang(b, _pc.forward()), _ang(v, aim)])
		_clear_shots()
		await _phys(2)

	_say("")
	_say("读法（判据）")
	_say("  · 每一行的『与准星夹角』≈ 0  ⇒ 该方向上弹道跟着准星")
	_say("  · 每一行的『准星方位 / 准星俯仰』必须**各不相同** ⇒ 准星真的摆在九个位置")
	_say("  · 『光束方位 / 光束俯仰』两列必须跟着准星那两列一起变 ⇒ 弹道在动")
	_say("  · 若某一行『与机头夹角』≈ 0 而『与准星夹角』很大 ⇒ 那个方向没跟准星（缺陷）")

	_cam.free()
	_pc.free()
	_cont.free()
	host.free()
	await get_tree().process_frame
	Game.reset()
	_say("")
