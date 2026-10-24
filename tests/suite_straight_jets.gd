extends RefCounted
static func run(t:T,host:Node)->void:
	t.suite("Jets / articulated nozzles stay straight in forward flight")
	Settings.begin_isolated();Game.reset()
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=false
	for id in [SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL,SuitProfile.Id.PENELOPE,SuitProfile.Id.ARIZEUS,SuitProfile.Id.REGZ_CUSTOM]:
		var base:=SuitProfile.by_id(id)
		for form in range(maxi(base.form_count,1)):
			var unit:=PlayerController.new();unit.profile=SuitProfile.by_id_form(id,form)
			host.add_child(unit);unit.position=Vector3(0,3000,0);unit.set_process(false);unit.set_physics_process(false)
			for cruise in [false,true]:
				unit.cruise_morph=1.0 if cruise else 0.0;unit.penelope_cruise_enabled=cruise
				unit._tick_cruise_morph(1.0);unit._tick_model_anim(.016)
				if unit.model_anim!=null and unit.model_anim.ready:unit.model_anim.player.advance(0)
				unit.fm.velocity=unit.forward()*1000
				for frame in 120:unit._tick_plume_bend(1.0/60.0)
				unit.fm.throttle=1.0;unit.fm.boosting=true;unit._tick_effects(1.0/60.0)
				for item:Dictionary in unit._plume_fx:
					for key in ["ab","dash","boost"]:
						var jet:GPUParticles3D=item.get(key)
						if jet==null:continue
						t.near((jet.process_material as ParticleProcessMaterial).gravity.length(),0,.001,"live particle gravity is straight during forward thrust")
						if jet.has_method("_process"):
							jet.emitting=true;jet._process(.1)
							var core:MeshInstance3D=jet.get_node_or_null("JetEnvelope")
							if core!=null:t.near((core.get_instance_shader_parameter("flow_curve") as Vector3).length(),0,.001,"live jet envelope has a straight centreline")
					t.near((item.bend as Vector3).length(),0,.001,"forward flight straight at actual nozzle %s/%s/%s" % [id,form,cruise])
				unit.fm.velocity=unit.global_basis*Vector3(1000,0,-1000)
				for frame in 60:unit._tick_plume_bend(1.0/60.0)
				t.gt(unit._plume_bend.length(),1.0,"real lateral movement still bends the jet")
				for item:Dictionary in unit._plume_fx:
					t.lt((item.bend as Vector3).length(),120.01,"nozzle curvature remains bounded")
				unit.fm.velocity=unit.forward()*1000
				for frame in 60:unit._tick_plume_bend(1.0/60.0)
				for item:Dictionary in unit._plume_fx:
					t.near((item.bend as Vector3).length(),0,.001,"return to forward removes residual curl")
			unit.free()
	var trim=preload("res://scripts/flight/plume_motion.gd")
	for axis in [Vector3.BACK,Vector3(1,1,1).normalized(),Vector3.DOWN]:
		t.eq(trim.maneuver_bend(Vector3(0,0,1000),axis,1000,1150),Vector3.ZERO,"tilted nozzle does not invent crosswind")
	t.not_ok(trim.maneuver_trim(SuitProfile.gp03d()),"reference GP03D path is unchanged")
	FlightBody.use_placeholder=old;Settings.end_isolated();Game.reset()
