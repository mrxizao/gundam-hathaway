extends Node3D
var shooter: FlightBody
var victim: FlightBody
var age := 0.0
var start := Vector3.ZERO
var attached := false
func _ready() -> void:
	start = shooter.global_position
	victim.abort_saber()
	victim.gp03_grab_owner = self
func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter) or not is_instance_valid(victim) or not shooter.alive or not victim.alive:
		queue_free()
		return
	age += delta
	if not attached:
		var mouth: Vector3 = shooter.global_transform * shooter.cannon_muzzles()[0]
		var destination := victim.global_position - (mouth - shooter.global_position) - shooter.forward() * 8.0
		shooter.global_position = start.lerp(destination, smoothstep(0.0, 0.35, age))
		if age >= 0.35:
			attached = true
			age = 0.0
	if attached:
		victim.global_position = shooter.global_transform * shooter.cannon_muzzles()[0] + shooter.forward() * 8.0
		victim.velocity = shooter.velocity
		if age >= 4.0:
			queue_free()
func _exit_tree() -> void:
	if is_instance_valid(victim) and victim.gp03_grab_owner == self:
		victim.gp03_grab_owner = null
