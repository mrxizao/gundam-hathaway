extends Node
## 一次性诊断探针：验证"从炮口发射的光束能不能打中静止目标"。
## 跑法：godot --headless --path <工程> res://tools/probe.tscn

func _ready() -> void:
	await get_tree().process_frame
	Game.reset()
	var c := Node3D.new()
	add_child(c)

	var shooter := FlightBody.new()
	shooter.team = 0
	shooter.profile = SuitProfile.xi()
	shooter.is_player = true
	shooter.display_name = "SHOOTER"
	shooter.projectile_container = c
	c.add_child(shooter)
	shooter.global_position = Vector3(0, 3000, 0)
	shooter.fm.speed = 300.0
	shooter.fm.throttle = 0.8
	shooter.fm.align_velocity(shooter.forward())

	var victim := FlightBody.new()
	victim.team = 1
	victim.profile = SuitProfile.penelope()
	victim.display_name = "VICTIM"
	victim.projectile_container = c
	c.add_child(victim)
	victim.global_position = Vector3(0, 3000, -1000)
	victim.fm.speed = 0.0
	victim.fm.velocity = Vector3.ZERO
	victim.set_physics_process(false)

	print("--- 布置 ---")
	print("shooter pos=", shooter.global_position, " fwd=", shooter.forward())
	print("victim  pos=", victim.global_position, " 距离=", shooter.global_position.distance_to(victim.global_position))
	print("victim ifield=", victim.ifield_hp, " hp=", victim.hp)
	print("victim collision_layer=", victim.collision_layer, " shape=", victim.get_child(1).get_class() if victim.get_child_count() > 1 else "?")
	for ch in victim.get_children():
		if ch is CollisionShape3D:
			var cs := ch as CollisionShape3D
			print("  shape=", cs.shape.get_class(), " radius=", (cs.shape as CapsuleShape3D).radius if cs.shape is CapsuleShape3D else "-",
				" height=", (cs.shape as CapsuleShape3D).height if cs.shape is CapsuleShape3D else "-")

	# 手工算一次炮口与瞄准点
	var muzzles: Array = shooter.get("_muzzle_local")
	print("muzzle_local=", muzzles)
	var origin: Vector3 = shooter.global_transform * muzzles[0]
	var aim: Vector3 = shooter.aim_point(origin, victim, true, 0.0, true)
	print("origin=", origin, "  到机头轴距离=", absf((origin - shooter.global_position).dot(shooter.right())))
	print("aim=", aim, "  aim 到 victim 距离=", aim.distance_to(victim.global_position))

	var ok: bool = shooter.fire_beam(true, victim, true)
	print("fire_beam -> ", ok)

	# 复刻截图脚本的节奏：每 10 帧一发，连打 4 发，然后等 240 帧
	for shot_i in 3:
		for f in 10:
			await get_tree().physics_frame
		shooter.rifle_cooldown = 0.0
		shooter.fire_beam(true, victim, true)
		print("  补射第 %d 发" % (shot_i + 2))

	for i in 240:
		await get_tree().physics_frame
		var alive := 0
		for ch in c.get_children():
			if ch is Projectile:
				alive += 1
		if i % 30 == 0:
			print("frame %3d  弹丸=%d  shooter_pos=%s  victim_alive=%s  ifield=%.0f hp=%.0f d=%.0f"
				% [i, alive, str(shooter.global_position), str(victim.alive), victim.ifield_hp,
					victim.hp, shooter.global_position.distance_to(victim.global_position)])

	print("--- 结论 ---")
	if victim.ifield_hp < victim.ifield_max or victim.hp < victim.max_hp:
		print("HIT  ifield=", victim.ifield_hp, " hp=", victim.hp)
	else:
		print("MISS —— 没有任何伤害")
	get_tree().quit(0)
