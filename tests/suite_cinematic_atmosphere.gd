extends RefCounted
const CLOUD:=preload("res://scripts/world/local_cloud_volume.gd")
static func run(t: T,host: Node) -> void:
	t.suite("CinematicAtmosphere / continuous bounded overlapping cloud fog")
	var clouds:=CLOUD.new()
	var transforms: Array[Transform3D]=[]
	for i in 12:
		transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(2200,1400,2200)),Vector3(i*25,5000,0)))
	clouds.configure([transforms,[],[]])
	host.add_child(clouds);clouds.set_process(false)
	var previous:=0.0
	for frame in 60:
		clouds.step_near_camera(Vector3(0,5000,0),1.0/60.0)
		var sum:=0.0
		for fog in clouds.fogs: sum+=float((fog.material as ShaderMaterial).get_shader_parameter("density_scale"))
		t.ok(sum<=CLOUD.DENSITY_BUDGET+0.00000001,"overlap does not multiply local fog density")
		t.ok(absf(sum-previous)<0.00003,"camera entry changes fog continuously")
		previous=sum
	t.gt(previous,0.0,"inside-cloud fog remains visible")
	t.eq(clouds.fogs.size(),4,"only four local fog slots")
	for frame in 60: clouds.step_near_camera(Vector3(90000,5000,0),1.0/60.0)
	for fog in clouds.fogs: t.not_ok(fog.visible,"leaving clouds clears fog after fade")
	for frame in 8: clouds.step_near_camera(Vector3(0,5000,0),1.0/60.0)
	clouds.configure([])
	t.eq(clouds.selected,[-1,-1,-1,-1],"reconfiguration clears previous indices")
	for fog in clouds.fogs:
		t.not_ok(fog.visible,"reconfiguration hides old fog")
		t.near(float((fog.material as ShaderMaterial).get_shader_parameter("density_scale")),0.0,.00000001,"reconfiguration clears old density")
	clouds.step_near_camera(Vector3.ZERO,1.0/60.0)
	clouds.free()
	t.suite("CinematicAtmosphere / common jet anchoring, forms and color")
	var stage:=Node3D.new();host.add_child(stage)
	var direction:=Vector3(0.4,-0.3,0.8).normalized()
	for tint: Color in [Color(1,0.8,0.2),Color(0.6,0.3,1),Color(0.3,0.65,1)]:
		var regular:=FX.afterburner(stage,Vector3(6,2,-3),direction,2.0,tint,24)
		var dash:=FX.afterburner_dash(stage,Vector3(6,2,-3),direction,2.0,tint,24)
		var a: MeshInstance3D=regular.get_node("JetEnvelope")
		var b: MeshInstance3D=dash.get_node("JetEnvelope")
		t.near(a.basis.y.dot(direction),1.0,.0001,"regular envelope follows actual nozzle direction")
		t.near(b.basis.y.dot(direction),1.0,.0001,"dash envelope follows actual nozzle direction")
		t.eq(regular.position,Vector3(6,2,-3),"nozzle mount is preserved")
		t.ok(regular.local_coords and dash.local_coords,"jet follows moving aircraft")
		t.gt((b.mesh as CylinderMesh).height,(a.mesh as CylinderMesh).height,"dash remains visibly longer")
		t.eq((a.mesh.surface_get_material(0) as ShaderMaterial).get_shader_parameter("tint"),tint,"machine exhaust tint preserved")
		t.eq(regular.amount,24,"per-nozzle particle budget retained")
		regular.free();dash.free()
	t.suite("CinematicAtmosphere / lit smoke and impact phase cleanup")
	var smoke:=FX.smoke_burst(stage,Vector3.ZERO,1.0,2.6,40)
	var emitter: GPUParticles3D=smoke.get_child(0)
	t.ok(emitter.material_override is ShaderMaterial,"actual smoke renderer uses lit shader override")
	var code: String=(emitter.material_override as ShaderMaterial).shader.code
	t.not_ok(code.contains("unshaded"),"smoke receives scene lighting")
	t.not_ok(code.contains("blend_add"),"smoke does not add light to background")
	t.not_ok(code.contains("EMISSION"),"smoke is not emissive")
	t.eq(emitter.amount,40,"burst particle budget unchanged")
	t.near(emitter.lifetime,2.6,.001,"smoke lifetime unchanged")
	t.not_ok(emitter.local_coords,"smoke stays in world space")
	smoke.free()
	var saved_quality: int=Settings.effects_quality
	Settings.effects_quality=2
	FX.beam_impact(stage,Vector3.ZERO)
	var impact: Node=stage.get_child(stage.get_child_count()-1)
	var total:=0
	for child in impact.get_children():
		if child is GPUParticles3D: total+=child.amount
	t.ok(total<=60,"beam impact remains within 60 particles")
	t.ok(impact.has_node("BeamContactSmoke"),"high-quality impact has brief residual smoke")
	await host.get_tree().create_timer(0.32).timeout
	t.ok(is_instance_valid(impact),"light extinction does not prematurely delete sparks and smoke")
	await host.get_tree().create_timer(0.8).timeout
	t.not_ok(is_instance_valid(impact),"impact frees after its last phase")
	Settings.effects_quality=0
	FX.beam_impact(stage,Vector3.ZERO)
	impact=stage.get_child(stage.get_child_count()-1)
	t.not_ok(impact.has_node("BeamContactSmoke"),"low effects avoids residual-smoke cost")
	await host.get_tree().create_timer(0.8).timeout
	t.not_ok(is_instance_valid(impact),"low effects impact also cleans up")
	Settings.effects_quality=saved_quality
	stage.free();await host.get_tree().process_frame
