extends Node
## 判据探针：**给 MeshInstance3D 设朝向之后，再设 `scale` 会不会把朝向冲掉**。
##
## ## 为什么怀疑这一条
##
## 工程里有两处"先给朝向、再给缩放"的写法，而且**顺序不同**：
##
##   · `Projectile.spawn()`：先 `mi.rotation_degrees.x = 90`，再 `mi.scale = ...`
##     —— 两个都走"向量 setter"，Godot 会用它自己的 `_update_local_transform()` 合成。
##   · `BeamCannon._place()`：先 `mi.global_transform = Transform3D(basis, pos)`，
##     再 `mi.scale = Vector3(1.0, length, 1.0)` —— **`global_transform` 不经过向量 setter**。
##
## 如果 "设 scale" 那一步是拿**缓存的欧拉角**重建局部变换，那么第二种写法里
## 刚设好的 `basis` 会被**整个丢掉**，光柱就会变成沿**世界 Y** 拉长的竖直柱 ——
## 也就是用户说的「弹体方向还是直挺挺的朝着飞行方向的其他地方」。
##
## 本探针把三种写法放在同一个环境里，直接读回 `basis.y` 与期望方向的夹角：
##   A = 先 `global_transform` 再 `scale`（`BeamCannon._place` 的顺序）
##   B = 先 `rotation_degrees` 再 `scale`（`Projectile.spawn` 的顺序）
##   C = 真跑一次 `FlightBody.fire_cannon()`，读 `BeamCannon` 那两根柱的实际朝向
##
## 用法（**不需要窗口**，纯变换数学 + 一次真开炮）：
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       res://tools/probe_basis_scale.tscn

const ALT := 3000.0
## 想让它当"局部 Y"的方向：故意取一个**既不是世界 Y、也不是 −Z** 的斜方向，
## 这样"有没有被冲掉"一眼可辨（被冲掉 ⇒ 结果会是接近世界 Y 的 (0,1,0)）。
const WANT_Y := Vector3(0.30, 0.52, -0.80)


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("=== 探针结束 ===")
	get_tree().quit()


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ang(a: Vector3, b: Vector3) -> float:
	if a.length_squared() < 1e-9 or b.length_squared() < 1e-9:
		return -1.0
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


func _f3(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]


## 返回一个"局部 Y = want"的正交基（与 `BeamCannon._place()` 同一套构造）。
func _basis_with_y(want: Vector3) -> Basis:
	var y := want.normalized()
	var up := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


func _run() -> void:
	print("")
	print("################################################################")
	print("#  探针：设完朝向再设 scale，朝向还在不在？")
	print("################################################################")
	var host := Node3D.new()
	add_child(host)
	var want := WANT_Y.normalized()
	var want_deg := _ang(want, Vector3.UP)
	print("目标方向 want = %s（与世界 UP 夹角 %.2f°）" % [_f3(want), want_deg])
	print("注意：**若朝向被冲掉**，结果会变成 (0.0000, 1.0000, 0.0000) 一带 —— 与世界 UP 夹角 0°。")

	# ---- A：先 global_transform 再 scale（BeamCannon._place 的顺序）----
	print("")
	print("--- A 先 `global_transform = Transform3D(basis, pos)` 再 `scale = (1, L, 1)` ---")
	var a := Node3D.new()
	host.add_child(a)
	a.global_transform = Transform3D(_basis_with_y(want), Vector3(10.0, 20.0, 30.0))
	a.scale = Vector3(1.0, 77.0, 1.0)
	var ay := a.global_transform.basis.y
	print("   basis.y = %s   与 want 夹角 %7.3f°   与世界 UP 夹角 %7.3f°"
		% [_f3(ay), _ang(ay, want), _ang(ay, Vector3.UP)])
	print("   basis.x = %s" % _f3(a.global_transform.basis.x))
	print("   scale   = %s（读回来的）" % _f3(a.scale))
	print("   结论：%s" % ("朝向**还在**（scale 没冲掉它）"
		if _ang(ay, want) < 1.0 else "⚠️ 朝向**被冲掉了**"))

	# ---- B：先 rotation_degrees 再 scale（Projectile.spawn 的顺序）----
	print("")
	print("--- B 先 `rotation_degrees` 再 `scale`（弹丸那一路）---")
	var b := Node3D.new()
	host.add_child(b)
	var bq := Quaternion(Vector3.UP, 0.0)
	b.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	b.scale = Vector3(1.0, 52.0, 1.0)
	print("   圆柱默认轴是局部 Y；绕 X 转 +90° 后应指向 ±Z（飞行方向）")
	print("   basis.y = %s   与 +Z 夹角 %7.3f°" % [_f3(b.global_transform.basis.y),
		_ang(b.global_transform.basis.y, Vector3.FORWARD * -1.0)])
	print("   basis.z = %s   与 +Z 夹角 %7.3f°" % [_f3(b.global_transform.basis.z),
		_ang(b.global_transform.basis.z, Vector3.FORWARD * -1.0)])
	print("   rotation_degrees 读回 = %s" % _f3(b.rotation_degrees))
	print("   结论：%s" % ("旋转**还在**" if absf(_ang(b.rotation_degrees, Vector3(90, 0, 0))) < 1.0
		else "⚠️ 旋转**被冲掉了**（读回 %s）" % _f3(b.rotation_degrees)))
	if bq != null:
		pass

	host.queue_free()
	await _phys(1)

	# ---- C：真放一次光束大炮，读那两根柱的实际朝向 ----
	print("")
	print("--- C 真 `fire_cannon()`：柱体的实际朝向 vs 瞄准方向 ---")
	Game.reset()
	var root := Node3D.new()
	add_child(root)
	var cont := Node3D.new()
	cont.name = "Projectiles"
	root.add_child(cont)
	var cam := Camera3D.new()
	cam.current = true
	root.add_child(cam)

	var pc := PlayerController.new()
	pc.name = "PC"
	pc.team = 0
	pc.is_player = true
	pc.profile = SuitProfile.xi()
	pc.display_name = "PC"
	pc.projectile_container = cont
	cont.add_child(pc)
	pc.global_position = Vector3(0.0, ALT, 0.0)
	pc.max_hp = 600.0
	pc.hp = 600.0
	pc.ifield_max = 0.0
	pc.ifield_hp = 0.0
	pc.fm.speed = 260.0
	pc.fm.throttle = 0.78
	pc.fm.align_velocity(pc.forward())
	await get_tree().process_frame
	await _phys(3)
	pc.controls_enabled = true
	pc.debug_input_enabled = true
	pc.debug_input = Vector3.ZERO
	pc.debug_throttle = 0.8
	pc.mouse_lock_enabled = true
	await _phys(3)

	# 造一个**与机头明显不同**的瞄准方向（右偏 30°），这样"柱跟着谁"一眼可辨
	var nose := pc.forward()
	var aim := (nose + pc.right() * 0.60).normalized()
	pc.set_aim_direction(aim)
	await _phys(2)
	print("   机头 forward      = %s" % _f3(nose))
	print("   注入 aim_dir      = %s   与机头夹角 %.3f°" % [_f3(aim), _ang(aim, nose)])
	print("   aim_forward()     = %s   ⇒ 与注入值夹角 %.3f°"
		% [_f3(pc.aim_forward()), _ang(pc.aim_forward(), aim)])
	print("   cannon_aim_dir()  = %s" % _f3(pc.cannon_aim_dir()))
	var think_ran := absf(pc.fm.throttle - 0.8) < 0.001
	if not pc.alive or not think_ran:
		print("   ❌ 自检没过（alive=%s think=%s）—— 下面读数无效"
			% [str(pc.alive), str(think_ran)])
		return

	# 放开大炮的门槛
	pc.profile.cannon_enabled = true
	pc.cannon_cd_left = 0.0
	pc.rifle_mag = pc.profile.rifle_magazine
	pc.rifle_count = 1
	pc.rifle_reloading = false
	var ok := pc.fire_cannon(null)
	print("   fire_cannon() = %s" % str(ok))
	await _phys(3)
	var c := pc.active_cannon
	if c == null:
		print("   ❌ 没拿到 BeamCannon 实例")
		return
	print("   柱体根节点 global_position = %s" % _f3(c.global_position))
	var hits := []
	for nm: String in ["_core", "_glow"]:
		var mi: MeshInstance3D = c.get(nm)
		if mi == null:
			print("   %s = null" % nm)
			continue
		var by := mi.global_transform.basis.y
		print("   %-6s basis.y = %s" % [nm, _f3(by)])
		print("            与 `cannon_aim_dir()` 夹角 %7.3f°   ← ≈0 才对"
			% _ang(by, pc.cannon_aim_dir()))
		print("            与「世界 UP」夹角         %7.3f°   ← ≈0 就是竖直柱"
			% _ang(by, Vector3.UP))
		print("            与「机头 forward」夹角     %7.3f°" % _ang(by, nose))
		print("            scale = %s   mesh.height = %.1f"
			% [_f3(mi.scale), (mi.mesh as CylinderMesh).height if mi.mesh is CylinderMesh else -1.0])
		hits.append(_ang(by, pc.cannon_aim_dir()))
	print("")
	if hits.is_empty():
		print("   ❌ 一根柱都没读到")
	else:
		var worst := 0.0
		for h: float in hits:
			worst = maxf(worst, h)
		print("   判据：两根柱与瞄准方向的夹角最大值 = %.3f°  ⇒ %s"
			% [worst, "朝向**对**" if worst < 1.0 else "⚠️ 朝向**不对**"])
		print("   （对照：与世界 UP 的夹角若 ≈0 ⇒ 柱是**竖直**的，与瞄准无关）")
	print("")
