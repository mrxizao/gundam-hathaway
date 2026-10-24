extends BeamCannon
var emitter:Node3D
func _physics_process(delta:float)->void:
	if is_instance_valid(emitter) and is_instance_valid(shooter):local_offset=shooter.to_local(emitter.global_position)
	super._physics_process(delta)
