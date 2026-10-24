extends RefCounted
static func run(t: T, host: Node) -> void:
	t.suite("WASD / real models, normal and cruise thrust trim")
	Settings.begin_isolated();Game.reset()
	var previous := FlightBody.use_placeholder
	FlightBody.use_placeholder = false
	for id in [SuitProfile.Id.XI,SuitProfile.Id.PENELOPE,SuitProfile.Id.REGZ_CUSTOM]:
		for cruise in [false,true]:
			var unit := PlayerController.new()
			unit.profile = SuitProfile.by_id_form(id,1 if cruise and id==SuitProfile.Id.REGZ_CUSTOM else 0)
			unit.is_player = true;unit.controls_enabled = true
			host.add_child(unit);unit.position = Vector3(0,3000,0)
			unit.set_process(false);unit.set_physics_process(false)
			unit.translate_mode = true;unit.cruise_morph = 1.0 if cruise else 0.0
			unit._gun_recoil_clock = 10.0
			var basis_before := unit.global_basis
			var velocity_before := unit.fm.velocity
			for dir in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
				unit.translate_dir = dir
				for frame in 60:unit._input_pose.step(unit,1.0/60.0)
				var pose: Vector3 = unit._input_pose.angles
				t.gt(pose.length(),3.0,"visible response %s %s %s" % [id,cruise,dir])
				if dir.z != 0.0:t.gt(pose.x*dir.z,0.0,"forward lean / reverse brake")
				else:t.lt(pose.z*dir.x,0.0,"bank follows lateral input")
				unit.translate_dir = Vector3.ZERO
				for frame in 120:unit._input_pose.step(unit,1.0/60.0)
				t.lt(unit._input_pose.angles.length(),0.001,"release settles to authored rest")
			unit.translate_dir = Vector3.RIGHT
			for frame in 60:unit._input_pose.step(unit,1.0/60.0)
			unit._tick_effects(1.0/60.0)
			t.lt(unit.model_pivot.rotation_degrees.z,-3.0,"frame-end pose survives the normal effects pipeline")
			if unit._regz_motion != null:
				unit._regz_motion.step(1.0/60.0)
				if not cruise:
					t.gt(unit._regz_motion.joints["Thigh.R"].rotation.length(),0.01,"normal ReGZ hip responds without dash")
			t.eq(unit.global_basis,basis_before,"visual response preserves physical heading")
			t.eq(unit.fm.velocity,velocity_before,"visual response preserves flight speed")
			unit.controls_enabled = false
			t.eq(unit.InputPose.read_intent(unit),Vector2.ZERO,"disabled input cannot drive a pose")
			unit.free()
	FlightBody.use_placeholder = previous
	Settings.end_isolated();Game.reset()
