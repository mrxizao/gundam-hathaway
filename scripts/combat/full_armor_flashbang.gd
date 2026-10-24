extends Node3D
## Guided auxiliary round with proximity/contact/range detonation; no direct damage.
const SPEED := 1800.0
const MAX_TRAVEL := 6000.0
var shooter
var velocity := Vector3.ZERO
var travelled := 0.0
var age := 0.0
var visual_only := false
var target: Node3D
var search_left := 0.0
const FUSE_RADIUS := 600.0
const TURN_RATE := 3.0

static func spawn(parent: Node3D,origin: Vector3,direction: Vector3,owner_body,remote := false) -> Node3D:
	var shot = load("res://scripts/combat/full_armor_flashbang.gd").new()
	shot.shooter = owner_body
	shot.visual_only = remote
	shot.velocity = direction.normalized()*SPEED
	parent.add_child(shot)
	shot.global_position = origin
	if direction.length_squared() > 0.01:shot.look_at(origin+direction)
	return shot

func _ready() -> void:
	name = "FullArmorFlashbang"
	add_to_group("flashbang_projectiles")
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.6
	sphere.height = 3.2
	sphere.radial_segments = 10
	sphere.rings = 6
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6,0.85,1)
	mat.emission_enabled = true
	mat.emission = Color(0.5,0.8,1)
	mat.emission_energy_multiplier = 5
	mesh.material_override = mat
	add_child(mesh)
	var tail := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.45
	cylinder.bottom_radius = 0.15
	cylinder.height = 48
	cylinder.radial_segments = 6
	tail.mesh = cylinder
	tail.material_override = mat
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tail.rotation.x = PI/2
	tail.position.z = 24
	add_child(tail)

func _seek_target() -> void:
	if is_instance_valid(target) and target.alive and not target.is_queued_for_deletion(): return
	target = null
	var nearest := MAX_TRAVEL * MAX_TRAVEL
	var systems = shooter.thunderbolt_systems
	var locked = systems.target() if systems != null else null
	if is_instance_valid(locked) and locked.alive and global_position.distance_squared_to(locked.global_position) <= nearest:
		target = locked
		return
	for unit in Game.live_hostiles_of(shooter):
		if not unit is FlightBody or not unit.alive or unit.is_queued_for_deletion(): continue
		var distance := global_position.distance_squared_to(unit.global_position)
		if distance < nearest:
			nearest = distance
			target = unit

func _detonate() -> void:
	if visual_only: return
	var systems = shooter.thunderbolt_systems
	if systems != null and systems.flash_projectile == self:
		systems.flash_detonate()
	else:
		queue_free()

func _physics_process(delta: float) -> void:
	age += delta
	if Game.phase != Game.Phase.FIGHT or not is_instance_valid(shooter) or not shooter.alive:
		queue_free()
		return
	search_left -= delta
	if search_left <= 0.0:
		search_left = 0.1
		_seek_target()
	if is_instance_valid(target) and target.alive:
		var wanted := global_position.direction_to(target.global_position)
		var current := velocity.normalized()
		var angle := current.angle_to(wanted)
		if angle > 0.001:
			var axis := current.cross(wanted)
			if axis.length_squared() < 0.0001: axis = current.cross(Vector3.UP if absf(current.y) < 0.9 else Vector3.RIGHT)
			velocity = current.rotated(axis.normalized(),minf(angle,TURN_RATE*delta))*SPEED
	if velocity.is_zero_approx(): return
	var step := velocity.normalized()*minf(velocity.length()*delta,MAX_TRAVEL-travelled)
	var destination := global_position+step
	if not visual_only and age >= 0.15 and is_instance_valid(target) and target.alive:
		var closest := Geometry3D.get_closest_point_to_segment(target.global_position,global_position,destination)
		if closest.distance_squared_to(target.global_position) <= FUSE_RADIUS*FUSE_RADIUS:
			global_position = closest
			_detonate()
			return
	var query := PhysicsRayQueryParameters3D.create(global_position,destination,1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position+hit.normal*3
		velocity = Vector3.ZERO
		_detonate()
	else:
		global_position = destination
		travelled += step.length()
		if travelled >= MAX_TRAVEL:
			velocity = Vector3.ZERO
			_detonate()

static func burst(parent: Node3D,at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "FlashbangBurst"
	parent.add_child(root)
	root.global_position = at
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 18
	sphere.height = 36
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 8
	mesh.material_override = mat
	root.add_child(mesh)
	var light := OmniLight3D.new()
	light.omni_range = 1200
	light.light_energy = 12
	light.shadow_enabled = false
	root.add_child(light)
	var tween := root.create_tween().set_parallel(true)
	tween.tween_property(mesh,"scale",Vector3.ONE*9,0.35)
	tween.tween_property(mat,"albedo_color:a",0.0,0.35)
	tween.tween_property(light,"light_energy",0.0,0.22)
	tween.chain().tween_callback(root.queue_free)
	Audio.play_3d("boom_s",at,-12,1.3,10000)
