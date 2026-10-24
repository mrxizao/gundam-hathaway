class_name Flare
extends Node3D
## 干扰弹。进 "flares" 组供 Missile._maybe_break_lock() 扫描。
## 本身不参与物理：初速由发射者给，之后自由落体 + 阻力。

var velocity := Vector3.ZERO
var lifetime := 4.0
var _light: OmniLight3D


static func deploy_burst(container: Node, from: Vector3, base_velocity: Vector3, count := 6) -> void:
	for i in count:
		var f := Flare.new()
		var spread := Vector3(randf_range(-1, 1), randf_range(-0.4, 1), randf_range(-1, 1)).normalized()
		f.velocity = base_velocity + spread * randf_range(35.0, 70.0)
		container.add_child(f)
		f.global_position = from + spread * 3.0


func _ready() -> void:
	add_to_group("flares")
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.6
	sphere.height = 3.2
	sphere.radial_segments = 8
	sphere.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.75)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.35)
	m.emission_energy_multiplier = 8.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = m
	mi.mesh = sphere
	add_child(mi)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.5)
	_light.light_energy = 12.0
	_light.omni_range = 90.0
	add_child(_light)


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	velocity += Vector3.DOWN * 14.0 * delta
	velocity *= 1.0 - minf(1.8 * delta, 1.0)
	global_position += velocity * delta
	if _light != null:
		_light.light_energy = 12.0 * randf_range(0.6, 1.0)
