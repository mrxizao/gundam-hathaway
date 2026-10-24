extends RefCounted
const Motion := preload("res://scripts/flight/gun_motion.gd")
const Fleet := preload("res://tests/suite_saber_motion.gd")

static func _unit(host: Node, p: SuitProfile) -> FlightBody:
	var u := FlightBody.new()
	u.profile = p
	u.projectile_container = host
	host.add_child(u)
	u.set_physics_process(false)
	u.global_position = Vector3(0,3000,0)
	if u.model_anim != null and u.model_anim.ready:
		u.model_anim.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return u

static func run(t: T, host: Node) -> void:
	Game.reset()
	var previous := FlightBody.use_placeholder
	FlightBody.use_placeholder = false
	var stage := Node3D.new()
	host.add_child(stage)
	for p in Fleet.profiles():
		t.suite("GunMotion / " + p.display_name + " weapon handling")
		var u := _unit(stage,p)
		var s := Motion.style(p)
		if u._model_skel == null:
			t.ok(not u._gun_pose_ready,"unskinned flight form uses its cannon hardpoints")
			var before := u._muzzle_local.duplicate()
			t.ok(u.fire_beam(true),"flight cannons can fire")
			t.near(u._gun_recoil_clock,0,0.001,"flight cannon shot starts body recoil")
			t.eq(u._muzzle_local,before,"back-mounted cannon hardpoints are retained")
			for child in stage.get_children():
				if child is Projectile: child.free()
			u.free()
			await host.get_tree().process_frame
			continue
		t.ok(u._gun_pose_ready,"model-specific gun clips installed")
		var sk := u._model_skel
		var anim := u.model_anim
		t.near(anim.player.get_animation("shoot").length,s["duration"],0.001,"per-model firing tempo")
		var upper := sk.find_bone("UpperArm.R")
		var lower := sk.find_bone("LowerArm.R")
		var wrist := sk.find_bone("Hand.R")
		var root := u.global_transform.affine_inverse() * sk.global_transform
		var neutral := Motion._sample(sk,null,0)
		var bind := Motion.Math._globals(sk,neutral["r"],neutral["p"],neutral["s"],root)
		var arm_length := bind[upper].origin.distance_to(bind[lower].origin) + bind[lower].origin.distance_to(bind[wrist].origin)
		var max_step := 0.0
		var last_q := Quaternion.IDENTITY
		var first_hand := Vector3.ZERO
		var max_hand := 0.0
		var directions: Array[Vector3] = []
		anim.player.play("shoot",0)
		anim.player.advance(0)
		for frame in range(ceili(float(s["duration"]) * 60) + 1):
			var time := minf(frame / 60.0,float(s["duration"]))
			anim.player.seek(time,true)
			var poses := sk.get_bone_global_pose(upper).origin.distance_to(sk.get_bone_global_pose(lower).origin) + sk.get_bone_global_pose(lower).origin.distance_to(sk.get_bone_global_pose(wrist).origin)
			# Skeleton-local lengths are converted by the uniform model scale.
			t.near(poses * root.basis.get_scale().x,arm_length,0.001,"shooting never stretches arm bones")
			var q := sk.get_bone_pose_rotation(wrist)
			if frame > 0: max_step = maxf(max_step,absf(rad_to_deg(q.angle_to(last_q))))
			last_q = q
			var hand := sk.get_bone_global_pose(wrist).origin
			if frame == 0: first_hand = hand
			max_hand = maxf(max_hand,hand.distance_to(first_hand) * root.basis.get_scale().x)
			if not p.rifle_back_mount:
				var ref_idx := sk.find_bone("LowerArm.R" if p.id == SuitProfile.Id.PENELOPE else "hand_R")
				var tip_idx := sk.find_bone("muzzle_R")
				var reference := root * sk.get_bone_global_pose(ref_idx).origin
				var tip := root * sk.get_bone_global_pose(tip_idx).origin
				var direction := reference.direction_to(tip)
				if p.id != SuitProfile.Id.PENELOPE:
					direction = (root.basis * sk.get_bone_global_pose(wrist).basis * u._gun_barrel_in_hand).normalized()
				directions.append(direction)
				t.lt(rad_to_deg(direction.angle_to(Vector3.FORWARD)),6,"barrel aims ahead with only controlled recoil")
				if p.id != SuitProfile.Id.PENELOPE:
					for name in ["hand_R","Weapon.R","muzzle_L","muzzle_R"]:
						var bone := sk.find_bone(name)
						if bone < 0 or name.begins_with("muzzle"): continue
						var grip_now := sk.get_bone_global_pose(wrist).affine_inverse() * sk.get_bone_global_pose(bone)
						var grip_bind := bind[wrist].affine_inverse() * bind[bone]
						t.near(grip_now.origin.distance_to(grip_bind.origin),0,0.0001,"weapon and emitter retain their palm grip offset")
			t.near(u._model_skel.get_bone_pose_position(upper).distance_to(sk.get_bone_rest(upper).origin),0,0.001,"shoulder joint remains connected")
		t.lt(max_step,12,"firing has no wrist snapping between frames")
		t.gt(max_hand,0.01,"firing has visible recoil and recovery")
		print("[GUN_POSE] ",p.display_name," duration=",s["duration"]," wrist_step_deg=",max_step," hand_recoil_m=",max_hand)
		# Ready pose is more relaxed than firing; the cruise stow clip remains
		# owned by the existing form system, avoiding unwanted raised arms.
		anim.hold_rest(0,true)
		anim.player.seek(0,true)
		if not p.rifle_back_mount:
			var ref_idx := sk.find_bone("LowerArm.R" if p.id == SuitProfile.Id.PENELOPE else "hand_R")
			var axis := (root * sk.get_bone_global_pose(ref_idx).origin).direction_to(root * sk.get_bone_global_pose(sk.find_bone("muzzle_R")).origin)
			if p.id != SuitProfile.Id.PENELOPE: axis = (root.basis * sk.get_bone_global_pose(wrist).basis * u._gun_barrel_in_hand).normalized()
			t.gt(-axis.y,0.20,"ready gun is lowered rather than always held at eye level")
			var live := u._live_weapon_anchor("muzzle_L")
			if p.id==SuitProfile.Id.PENELOPE and p.form==0:
				live=u._weapon_emitters.rifle_local()
			t.near(u._rifle_muzzle_local(0).distance_to(live),0,0.001,"rifle origin reads the actual animated emitter")
		if not p.rifle_back_mount and p.id != SuitProfile.Id.PENELOPE:
			for action in ["slash","shield","shoot"]:
				anim.player.play(action,0)
				anim.player.seek(anim.player.get_animation(action).length * 0.4,true)
				for bone: int in u._gun_grip_bind:
					var relative := sk.get_bone_global_pose(wrist).affine_inverse() * sk.get_bone_global_pose(bone)
					var expected: Transform3D = u._gun_grip_bind[bone]
					t.near(relative.origin.distance_to(expected.origin),0,0.001,"grip and barrel stay attached through " + action)
			anim.hold_rest(0,true)
			anim.player.seek(0,true)
		if not p.rifle_back_mount:
			for logical in [str(ModelAnimator.REST_CLIP),p.model_anim_idle,"fly_f","dash_l","turn_yaw_L"]:
				if not anim.pose_overrides.has(logical): continue
				var source_name: String="__ace_"+logical if anim.player.has_animation("__ace_"+logical) else logical
				var original := anim.player.get_animation(source_name)
				anim.player.play(anim.playback_name(logical),0)
				anim.player.seek(original.length * 0.4,true)
				var expected := Motion._sample(sk,original,original.length * 0.4)
				for name in ["Head","Thigh.L","Thigh.R","Foot.R"]:
					var bone := sk.find_bone(name)
					if bone < 0: continue
					t.near(sk.get_bone_pose_rotation(bone).angle_to(expected["r"][bone]),0,0.002,"ready pose preserves other body animation in " + logical)
				var length := sk.get_bone_global_pose(upper).origin.distance_to(sk.get_bone_global_pose(lower).origin) + sk.get_bone_global_pose(lower).origin.distance_to(sk.get_bone_global_pose(wrist).origin)
				t.near(length * root.basis.get_scale().x,arm_length,0.001,"ready pose preserves arm length in " + logical)
			anim.hold_rest(0,true)
			anim.player.seek(0,true)
		var magazine := u.rifle_mag
		var before_count := stage.get_child_count()
		t.ok(u.fire_beam(true),"AI/base successful fire starts animation through the real weapon entry")
		t.eq(u.model_fsm.current_action(),"shoot","NPC and player share shooting action")
		t.eq(u.rifle_mag,magazine if p.rifle_ammo_infinite else magazine - 1,"ammo consumption unchanged")
		t.eq(stage.get_child_count() - before_count,p.rifle_pellets,"same number of projectiles")
		var bullets := []
		for child in stage.get_children():
			if child is Projectile: bullets.append(child)
		for i in bullets.size():
			var origin := u.global_transform * u._rifle_muzzle_local(i)
			t.near(bullets[i].global_position.distance_to(origin),0,0.002,"projectile originates at the posed gun muzzle")
			bullets[i].free()
		var action_count := u.model_fsm.history().size()
		t.ok(not u.fire_beam(true),"cooldown refuses another shot")
		t.eq(u.model_fsm.history().size(),action_count,"rejected fire cannot restart animation")
		u.free()
		await host.get_tree().process_frame
	t.suite("GunMotion / training target stays unarmed")
	var drone := _unit(stage,SuitProfile.gustav00())
	t.ok(not drone._gun_pose_ready,"training drone gets no armed pose override")
	t.ok(not drone.fire_beam(true),"training drone remains unable to shoot")
	stage.free()
	FlightBody.use_placeholder = previous
	await host.get_tree().process_frame
