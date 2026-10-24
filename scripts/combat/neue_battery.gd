extends Node3D
## Fixed shoulder/rear particle cannons support the belly MEGA cannon.
var shooter: Node3D
var target: Node3D
var include_shoulders := true
var age := 0.0
var cadence := 0.0
var barrels: Array[Node3D] = []
const SOURCE_SCALE := Vector3(106.88217833812728,106.88217833812728,74.76474096879554)
const PORTS := [Vector3(.149,.319,-.173375),Vector3(.149,.319,.173375),
	Vector3(.159,.300883,-.11875),Vector3(.159,.300883,.11875),
	Vector3(-.205,-.13,-.09),Vector3(-.205,-.13,-.045),Vector3(-.205,-.10,0),
	Vector3(-.205,-.13,.045),Vector3(-.205,-.13,.09)]
func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.16,.19,.16)
	material.metallic = .7
	material.roughness = .45
	for i in (4 if include_shoulders else 0):
		var pivot := Node3D.new()
		pivot.name = "ShoulderDeflectionCannon%d" % i
		var barrel := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = .34
		cylinder.bottom_radius = .46
		cylinder.height = 1.1
		cylinder.radial_segments = 12
		cylinder.material = material
		barrel.mesh = cylinder
		barrel.rotation_degrees.x = 90.0
		barrel.position.z = -.5
		pivot.add_child(barrel)
		add_child(pivot)
		barrels.append(pivot)
	_update_barrels()

func _update_barrels() -> void:
	var axis := Basis(Vector3.UP,PI*.5)
	for i in barrels.size():
		var origin: Vector3 = shooter.global_transform * (axis * (PORTS[i]*SOURCE_SCALE))
		var forward: Vector3 = shooter.forward()
		var dir := origin.direction_to(target.global_position)
		if forward.dot(dir)<.45:
			dir = forward
		var up: Vector3 = shooter.up()
		if absf(up.dot(dir))>.99:
			up = shooter.right()
		barrels[i].global_transform = Transform3D(Basis.looking_at(dir,up),origin)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter) or not shooter.alive or not is_instance_valid(target) or not target.alive:
		queue_free()
		return
	_update_barrels()
	age += delta
	if age > shooter.profile.cannon_duration:
		queue_free()
		return
	cadence -= delta
	if cadence>0.0:
		return
	cadence = 0.85
	var axis := Basis(Vector3.UP,PI*0.5)
	for i in PORTS.size():
		if i<4 and not include_shoulders:
			continue
		var local: Vector3 = axis * (PORTS[i] * SOURCE_SCALE)
		var origin: Vector3 = shooter.global_transform * local
		var dir: Vector3 = origin.direction_to(target.global_position)
		var facing: Vector3 = shooter.forward() if i<4 else -shooter.forward()
		if facing.dot(dir)<0.45:
			continue
		Projectile.beam(shooter.projectile_container,origin+dir*1.1,dir,shooter,4.0*shooter.damage_mult,shooter.profile.beam_color(),0.0,1.2,5000.0)
