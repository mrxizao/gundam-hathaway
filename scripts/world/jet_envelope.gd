extends GPUParticles3D
var flame: MeshInstance3D
var strength := 0.0
func _process(delta: float) -> void:
	if flame == null: return
	strength = move_toward(strength, 1.0 if emitting else 0.0, delta * 12.0)
	flame.visible = strength > 0.001
	if not flame.visible: return
	flame.set_instance_shader_parameter("strength", strength)
	var pm := process_material as ParticleProcessMaterial
	if pm != null:
		var local_wind: Vector3 = flame.basis.inverse()*pm.gravity
		var material := flame.mesh.surface_get_material(0) as ShaderMaterial
		var length_m: float = material.get_shader_parameter("length_m")
		# Shape the existing nozzle flame, including fast dash beams whose short
		# particle lifetime previously left their visible envelope almost straight.
		var amount := 1.0-exp(-local_wind.length()/180.0)
		var curve := local_wind.normalized()*length_m*flame.scale.y*0.45*amount
		flame.set_instance_shader_parameter("flow_curve",curve)
