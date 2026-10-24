extends Node3D
## Move the actual imported forearms, including their original wrist/claw meshes.
const MAX_CABLE := 6000.0
var shooter: Node3D
var target: Node3D
var arms: Array[Node3D] = []
var homes: Array[Transform3D] = []
var anchors: Array[Node3D] = []
var age := 0.0
var shot_clock := 0.0
var retracting := false
var retract_age := 0.0
var return_from: Array[Transform3D] = []
var cable_mesh := ImmediateMesh.new()
var cable_mat := StandardMaterial3D.new()
## **联机远端复制专用：只走视觉** —— 臂、缆、光束及声音照常，伤害和拦截关闭。
##
## ⚠️ 为什么必须有这个开关：下面那一发 `Projectile.beam(..., shooter, 10.0*damage_mult, ...)`
## 是**在本地就地结算伤害**的（`shooter` 在这边是代理机体 ⇒ 打的就是本机玩家）。
## 而联机的命中已经由**开枪方**算过一遍并回传（`NetSession` 的 `_rpc_damage`）——
## 远端再发一次就是**双倍伤害**，而且这件事**不报任何错**。
var visual_only := false

func configure(body: Node3D, mark: Node3D) -> bool:
	shooter = body
	target = mark
	for side in ["L","R"]:
		var arm := body.find_child("WireArm_"+side,true,false) as Node3D
		var anchor := body.find_child("Mount_WireArm_"+side,true,false) as Node3D
		if arm == null or anchor == null:
			return false
		arms.append(arm)
		homes.append(arm.transform)
		anchors.append(anchor)
	return true

func _ready() -> void:
	name = "NeueWireArms"
	var cable := MeshInstance3D.new()
	cable.name = "ControlCables"
	cable.mesh = cable_mesh
	cable_mat.albedo_color = Color(0.20,0.23,0.25)
	cable_mat.roughness = 0.75
	cable_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(cable)
	Audio.play_3d("funnel_fire",shooter.global_position,-3.0)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter) or shooter.get("hp") <= 0:
		queue_free()
		return
	age += delta
	if not retracting and (age >= 4.0 or not is_instance_valid(target) or target.get("hp") <= 0):
		retracting = true
		for arm in arms:
			return_from.append(arm.global_transform)
	if retracting:
		retract_age += delta
	shot_clock -= delta
	cable_mesh.clear_surfaces()
	cable_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,cable_mat)
	for i in arms.size():
		var arm := arms[i]
		if not is_instance_valid(arm) or not is_instance_valid(anchors[i]):
			continue
		var home: Transform3D = arm.get_parent().global_transform * homes[i]
		if retracting:
			arm.global_transform = return_from[i].interpolate_with(home,smoothstep(0.0,1.2,retract_age))
		else:
			var side := -1.0 if i==0 else 1.0
			var center: Vector3 = target.global_position
			var radial := shooter.global_position.direction_to(center)
			var lateral := radial.cross(Vector3.UP).normalized()
			if lateral.is_zero_approx():
				lateral = Vector3.RIGHT
			var orbit := center + lateral * side * (65.0+sin(age*1.8)*25.0) + Vector3.UP*(30.0+cos(age*1.5+float(i))*25.0)
			orbit = home.origin + (orbit-home.origin).limit_length(MAX_CABLE)
			var pos := home.origin.lerp(orbit,smoothstep(0.0,1.0,age))
			var dir := pos.direction_to(center)
			if absf(dir.dot(Vector3.UP)) > 0.99:
				dir = (dir+Vector3.RIGHT*0.02).normalized()
			arm.global_transform = Transform3D(Basis.looking_at(dir,Vector3.UP),pos)
			if age > 1.0 and shot_clock <= 0.0:
				var tip := arm.get_node("CannonTip") as Node3D
				# Replicate the actual beam; a visual replica cannot deal or intercept damage.
				var shot := Projectile.beam(shooter.projectile_container,tip.global_position,tip.global_position.direction_to(center),shooter,0.0 if visual_only else 10.0*shooter.damage_mult,shooter.profile.beam_color(),0.0,1.4,5000.0)
				shot.visual_only = visual_only
				Audio.play_3d("beam_rifle",tip.global_position,-8.0)
		_draw_cable(anchors[i].global_position,arm.global_position)
	cable_mesh.surface_end()
	if shot_clock <= 0.0:
		shot_clock = 0.55
	if retracting and retract_age >= 1.2:
		queue_free()

func _draw_cable(a: Vector3, b: Vector3) -> void:
	var last := a
	var slack := minf(12.0,a.distance_to(b)*0.02)
	for j in range(1,17):
		var u := float(j)/16.0
		var point := a.lerp(b,u) + Vector3.DOWN*sin(u*PI)*slack
		var tangent := (point-last).normalized()
		var side := tangent.cross(Vector3.UP).normalized()*0.16
		if side.is_zero_approx():
			side = Vector3.RIGHT*0.16
		for vertex in [last-side,last+side,point+side,last-side,point+side,point-side]:
			cable_mesh.surface_add_vertex(to_local(vertex))
		last = point

func _exit_tree() -> void:
	for i in arms.size():
		if is_instance_valid(arms[i]):
			arms[i].transform = homes[i]
