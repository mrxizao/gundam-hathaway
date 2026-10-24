extends RefCounted
const Motion := preload("res://scripts/flight/fly_motion.gd")
const Sample := preload("res://scripts/flight/gun_motion.gd")

static func profiles() -> Array[SuitProfile]:
	return [SuitProfile.messer_m01(),SuitProfile.messer_cmd(),SuitProfile.messer_f01(),SuitProfile.gustav00_armed(),SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU)]

static func run(t: T, host: Node) -> void:
	Game.reset()
	var previous := FlightBody.use_placeholder
	FlightBody.use_placeholder = false
	var stage := Node3D.new()
	host.add_child(stage)
	for p in profiles():
		t.suite("FlyMotion / " + p.display_name + " continuous directional flight")
		var unit := FlightBody.new()
		unit.profile = p
		unit.projectile_container = stage
		stage.add_child(unit)
		unit.set_physics_process(false)
		unit.set_process(false)
		unit.global_position = Vector3(0,3000,0)
		var sk := unit._model_skel
		var anim := unit.model_anim
		anim.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		t.ok(Motion.supports(p),"requested model is supported")
		t.eq(p.model_anim_idle,"","static idle preference is retained")
		var root := unit.global_transform.affine_inverse() * sk.global_transform
		var rest := Sample._sample(sk,null,0)
		var restposes := Motion.Math._globals(sk,rest["r"],rest["p"],rest["s"],root)
		var count := 0
		for key in anim.actions:
			var name := str(key)
			if not (name.begins_with("fly_") or name.begins_with("dash_") or name.begins_with("turn_")): continue
			count += 1
			var clip := anim.player.get_animation(name)
			t.eq(clip.loop_mode,Animation.LOOP_LINEAR,"direction clip loops without re-entry pulses: " + name)
			var start := Sample._sample(sk,clip,0)
			var end := Sample._sample(sk,clip,clip.length)
			var peak_step := 0.0
			var last := start
			for frame in range(1,ceili(clip.length * 30) + 1):
				var now := Sample._sample(sk,clip,minf(frame / 30.0,clip.length))
				for bone in ["Hips","Spine","Chest","Thigh.L","Thigh.R","Shin.L","Shin.R","Head"]:
					var i := sk.find_bone(bone)
					peak_step = maxf(peak_step,absf(rad_to_deg(now["r"][i].angle_to(last["r"][i]))))
				last = now
			t.lt(peak_step,1.0,"continuous thrust has only gentle trim, no flapping: " + name)
			for bone in sk.get_bone_count():
				t.near(start["r"][bone].angle_to(end["r"][bone]),0,0.001,"loop seam is closed: " + name)
				t.near(start["p"][bone].distance_to(rest["p"][bone]),0,0.0001,"no bone translations or root motion: " + name)
			anim.play_loop(name,0,true)
			anim.player.advance(0.2)
			for side in ["L","R"]:
				var hip := sk.find_bone("Thigh." + side)
				var knee := sk.find_bone("Shin." + side)
				var foot := sk.find_bone("Foot." + side)
				var expected := restposes[hip].origin.distance_to(restposes[knee].origin) + restposes[knee].origin.distance_to(restposes[foot].origin)
				var actual := sk.get_bone_global_pose(hip).origin.distance_to(sk.get_bone_global_pose(knee).origin) + sk.get_bone_global_pose(knee).origin.distance_to(sk.get_bone_global_pose(foot).origin)
				t.near(actual * root.basis.get_scale().x,expected,0.001,"knees bend without stretching: " + name)
			for bone: int in unit._gun_grip_bind:
				var grip := sk.get_bone_global_pose(sk.find_bone("Hand.R")).affine_inverse() * sk.get_bone_global_pose(bone)
				var expected: Transform3D = unit._gun_grip_bind[bone]
				t.near(grip.origin.distance_to(expected.origin),0,0.001,"gun and muzzle remain attached during " + name)
		t.eq(count,24,"eight flight, ten dash including vertical, and six turn source clips retained")
		var hips := sk.find_bone("Hips")
		var neutral_basis: Basis = restposes[hips].basis.orthonormalized()
		for request in [["fly_f",Vector3(0,0,-1)],["fly_b",Vector3(0,0,1)],["fly_l",Vector3(-1,0,0)],["fly_r",Vector3(1,0,0)]]:
			var values := Motion.pose(sk,root,p,request[0],0)
			var poses := Motion.Math._globals(sk,values["r"],values["p"],values["s"],root)
			var up := (poses[hips].basis.orthonormalized() * neutral_basis.inverse()) * Vector3.UP
			t.gt(up.dot(request[1]),0.02,"body lean follows the requested thrust direction: " + request[0])
		# Exercise real state changes and the weapon interruption at 60 Hz.
		unit.model_fsm.stop()
		anim.player.advance(0)
		var before := sk.get_bone_pose_rotation(sk.find_bone("Hips"))
		var max_step := 0.0
		for request in ["f","l","b","r",""]:
			unit.model_fsm.set_fly_dir(request)
			for frame in 24:
				unit.model_fsm.tick(1.0 / 60)
				anim.player.advance(1.0 / 60)
				var now := sk.get_bone_pose_rotation(sk.find_bone("Hips"))
				max_step = maxf(max_step,absf(rad_to_deg(before.angle_to(now))))
				before = now
		t.lt(max_step,6,"real direction changes blend smoothly")
		t.eq(unit.model_fsm.desyncs,0,"flight and ready aliases stay synchronized with FSM")
		unit.model_fsm.set_fly_dir("f")
		unit.model_fsm.tick(0.2)
		anim.player.advance(0.2)
		t.ok(unit.fire_beam(true),"firing interrupts flight through the real weapon entry")
		t.eq(unit.model_fsm.current_action(),"shoot","optimized shooting remains available")
		unit.free()
		await host.get_tree().process_frame
	for p in [SuitProfile.xi(),SuitProfile.penelope(),SuitProfile.arizeus(),SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)]:
		t.ok(not Motion.supports(p),"unrequested model excluded: " + p.display_name)
	stage.free()
	FlightBody.use_placeholder = previous
	await host.get_tree().process_frame
