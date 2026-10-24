extends RefCounted
## One continuous core per nozzle; acceleration changes its length, not its source.
const MAX_BEND := 80.0
static func supports(profile: SuitProfile) -> bool:
	return profile.id == SuitProfile.Id.PENELOPE and profile.form == 0
static func configure(item: Dictionary) -> void:
	for key in ["ab","dash","fx"]:
		var p := item.get(key) as GPUParticles3D
		if p == null: continue
		p.fixed_fps = 60 if key != "fx" else 0
		p.fract_delta = true
		var material := p.process_material as ParticleProcessMaterial
		if material != null:
			material.turbulence_enabled = false
			if key == "fx": material.spread = 1.0
		if key == "fx":
			# Keep the short nozzle haze attached, rather than drawing a long curled wake.
			p.local_coords = true
			p.lifetime = 0.18
			p.amount = mini(p.amount,12)
		elif key == "ab":
			p.lifetime = 0.22
			p.preprocess = 0.22
	item["jet_length"] = 1.0
static func update(item: Dictionary, active: bool, boosting: bool, dashing: bool, delta: float) -> void:
	var p := item.get("ab") as GPUParticles3D
	if p == null: return
	var dash := item.get("dash") as GPUParticles3D
	if dash != null: dash.emitting = false
	p.emitting = active
	p.amount_ratio = 1.0
	var target := 2.35 if dashing else (1.35 if boosting else 1.0)
	var length: float = lerpf(item["jet_length"],target,1.0-exp(-8.0*delta))
	# Keep the restored streaks moving through the full extended jet.
	p.speed_scale = length
	item["jet_length"] = length
	var flame := p.get_node_or_null("JetEnvelope") as MeshInstance3D
	if flame != null:
		var material := flame.mesh.surface_get_material(0) as ShaderMaterial
		var base_length: float = material.get_shader_parameter("length_m")
		flame.scale = Vector3(1.0,length,1.0)
		var local_axis: Vector3 = (p.process_material as ParticleProcessMaterial).direction
		flame.position = local_axis*base_length*length*0.5
		flame.set_instance_shader_parameter("brightness",0.75+0.35*(length-1.0))
