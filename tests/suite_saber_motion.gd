extends RefCounted
const Motion := preload("res://scripts/flight/saber_motion.gd")

static func profiles() -> Array[SuitProfile]:
	return [SuitProfile.xi(),SuitProfile.penelope(),SuitProfile.arizeus(),SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU),SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE),SuitProfile.gustav00_armed(),SuitProfile.messer_m01(),SuitProfile.messer_cmd(),SuitProfile.messer_f01()]

static func _unit(host: Node, p: SuitProfile, team := 0) -> FlightBody:
	var u := FlightBody.new()
	u.profile = p
	u.team = team
	u.is_player = true
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
	for p in profiles() + [SuitProfile.odysseus()]:
		t.suite("SaberMotion / " + p.display_name + " physical swing and visible blade")
		var u := _unit(stage,p)
		t.ok(u.try_saber(null),"combat variant can start melee")
		t.ok(u._blade != null and u._blade.is_visible_in_tree(),"blade is visible, including unskinned flight form")
		t.ok(not u.rig.is_ancestor_of(u._blade),"blade is independent of hidden placeholder")
		var directions: Array[Vector3] = []
		var tips: Array[Vector3] = []
		var hands: Array[Vector3] = []
		var max_step := 0.0
		var max_upper_step := 0.0
		var min_length := INF
		var max_length := 0.0
		var old_upper := Quaternion.IDENTITY
		var s := Motion.style(p)
		var duration: float = s["duration"]
		var steps := ceili(duration * 60)
		var rotations_before := {}
		if u._model_skel != null:
			t.ok(u.model_anim.has("slash"),"optimized clip is wired to the real melee action")
			t.near(u.model_anim.player.get_animation("slash").length,duration,0.001,"per-model action timing installed")
			u.model_anim.player.play("slash",0)
			u.model_anim.player.advance(0)
			rotations_before = u.model_anim.rotations_at("slash",0)
		for frame in range(steps + 1):
			var time := minf(frame / 60.0,duration)
			u._saber_visual_clock = time
			if u._model_skel != null:
				u.model_anim.player.seek(time,true)
				u._model_skel.force_update_all_bone_transforms()
				var hand := u._model_skel.global_transform * u._model_skel.get_bone_global_pose(u._bone_index("hand_L"))
				t.near(u._blade_anchor.global_position.distance_to(hand.origin),0,0.002,"mixer callback keeps blade attached in the same frame")
				hands.append(hand.origin - u.global_position)
				var sk := u._model_skel
				var upper := sk.find_bone("UpperArm.L")
				var lower := sk.find_bone("LowerArm.L")
				var wrist := sk.find_bone("Hand.L")
				var length := sk.get_bone_global_pose(upper).origin.distance_to(sk.get_bone_global_pose(lower).origin) + sk.get_bone_global_pose(lower).origin.distance_to(sk.get_bone_global_pose(wrist).origin)
				min_length = minf(min_length,length)
				max_length = maxf(max_length,length)
				var q := sk.get_bone_pose_rotation(upper)
				if frame > 0: max_upper_step = maxf(max_upper_step,absf(rad_to_deg(q.angle_to(old_upper))))
				old_upper = q
			else:
				u._sync_blade_anchor()
			var direction := -u._blade_anchor.global_basis.z.normalized()
			if frame > 0:
				var step := rad_to_deg(direction.angle_to(directions[-1]))
				max_step = maxf(max_step,step)
				if step > 35: print("[SABER_SNAP] ",p.display_name," frame=",frame," t=",time," deg=",step," from=",directions[-1]," to=",direction)
			directions.append(direction)
			tips.append(u._blade_anchor.global_position - u.global_position + direction * p.saber_blade_front)
		var direction_span := 0.0
		var tip_span := 0.0
		var hand_span := 0.0
		for i in directions.size():
			for j in range(i + 1,directions.size()):
				direction_span = maxf(direction_span,rad_to_deg(directions[i].angle_to(directions[j])))
				tip_span = maxf(tip_span,tips[i].distance_to(tips[j]))
				if not hands.is_empty(): hand_span = maxf(hand_span,hands[i].distance_to(hands[j]))
		print("[SABER_MOTION] ",p.display_name," direction=",direction_span," tip_m=",tip_span," hand_m=",hand_span," max_step=",max_step," upper_step=",max_upper_step)
		t.ok(direction_span > 45,"blade sweeps a real arc instead of staying along the nose")
		t.ok(tip_span > p.target_height * 0.30,"blade tip has a readable full-size sweep")
		t.ok(max_step < 35,"blade direction has no adjacent-frame snap")
		if u._model_skel != null:
			t.ok(hand_span > p.target_height * 0.12,"real left hand moves through a readable arc")
			t.near(max_length,min_length,0.0001,"IK does not stretch the arm")
			t.ok(max_upper_step < 30,"arm pose has no adjacent-frame snap")
			var contact_pose := u.model_anim.rotations_at("slash",s["impact"])
			var torso_turn := 0.0
			for bone in ["Hips","Chest"]:
				if contact_pose.has(bone) and rotations_before.has(bone):
					torso_turn += (rotations_before[bone] as Quaternion).angle_to(contact_pose[bone])
			t.ok(torso_turn > deg_to_rad(4.0),"contact carries visible torso commitment, not only a moving blade")
			var rotations_after := u.model_anim.rotations_at("slash",duration)
			var seam := 0.0
			for bone in rotations_before:
				seam = maxf(seam,absf(((rotations_before[bone] as Quaternion).inverse() * (rotations_after[bone] as Quaternion)).normalized().get_angle()))
			t.near(seam,0,0.001,"complete action returns to its own neutral pose")
		u.abort_saber()
		t.ok(u._blade == null,"explicit cancel cleans up blade")
		u.free()
		await host.get_tree().process_frame
	t.suite("SaberMotion / GP03D stationary hull exception")
	var dendrobium := _unit(stage,SuitProfile.gp03d())
	dendrobium.try_saber(null)
	dendrobium._tick_effects(0.0)
	dendrobium._sync_blade_anchor()
	var blade_before := -dendrobium._blade_anchor.global_basis.z
	var hull_before := dendrobium.model_pivot.transform
	dendrobium._saber_visual_clock = Motion.style(dendrobium.profile)["follow"]
	dendrobium._tick_effects(0.0)
	dendrobium._sync_blade_anchor()
	t.ok(dendrobium.model_pivot.transform.is_equal_approx(hull_before),"GP03D hull remains stationary throughout slash")
	t.ok(blade_before.angle_to(-dendrobium._blade_anchor.global_basis.z) > deg_to_rad(30.0),"GP03D blades sweep while hull remains stationary")
	dendrobium.free()
	t.suite("SaberMotion / anticipation, contact follow-through and interruption")
	var a := _unit(stage,SuitProfile.xi())
	var b := _unit(stage,SuitProfile.penelope(),1)
	b.global_position = a.global_position + Vector3(0,0,-1200)
	t.ok(a.try_saber(b),"long dash starts")
	a.model_anim.player.seek(0.22,true)
	a._tick_saber_visual(1.0 / 60)
	t.ok(a.model_anim.saber_holding,"long approach holds the prepared pose")
	t.ok(not a.model_anim.finished(),"held anticipation remains an active action")
	a.model_fsm.tick(0.1)
	t.eq(a.model_fsm.state,ModelAnimFSM.State.ACTION,"FSM cannot discard the held swing")
	b.global_position = a.global_position + Vector3(0,0,-150)
	a._tick_saber_visual(1.0 / 60)
	t.ok(not a.model_anim.saber_holding,"near contact releases the swing")
	var resumed := a.model_anim.player.current_animation_position
	t.ok(resumed >= 0.19 and resumed <= 0.23,"release resumes at preparation instead of restarting")
	a.model_anim.player.advance(0.05)
	t.ok(a.model_anim.player.current_animation_position > resumed,"released clip actually advances")
	b.ifield_hp = 0
	var hp := b.hp
	a._slash(b)
	t.near(hp - b.hp,a.profile.saber_damage * a.damage_mult,0.001,"damage amount is unchanged")
	t.ok(not a.saber_active(),"gameplay exits charge at the original contact")
	t.ok(a._blade != null and a._saber_visual_tail > 0,"visual blade survives long enough for follow-through")
	var hit_hp := b.hp
	for frame in 50:
		a.model_anim.player.advance(1.0 / 60)
		a._tick_saber_visual(1.0 / 60)
	t.ok(a._blade == null,"follow-through blade is removed after its short tail")
	t.near(b.hp,hit_hp,0.001,"visual follow-through never applies extra damage")
	a.saber_cooldown = 0
	b.global_position = a.global_position + Vector3(0,0,-1200)
	a.try_saber(b)
	a.model_anim.player.seek(0.22,true)
	a._tick_saber_visual(1.0 / 60)
	a.abort_saber()
	t.ok(not a.model_anim.saber_holding and a._blade == null,"cancel releases paused animation and removes blade")
	a.saber_cooldown = 0
	a.try_saber(null)
	a._end_saber(true)
	a.play_model_action("shoot")
	a._tick_saber_visual(1.0 / 60)
	t.ok(a._blade == null and not a.model_anim.saber_holding,"shoot interruption cannot retain a stale blade or paused clip")
	var target := _unit(stage,SuitProfile.gustav00())
	t.ok(not target.try_saber(a) and target._blade == null,"unarmed training target remains unarmed")


	t.suite("SaberMotion / Xi cruise wing compatibility")
	var cruise := _unit(stage,SuitProfile.xi())
	cruise.cruise_morph = 1.0
	cruise.try_saber(null)
	cruise.model_anim.player.play("slash",0)
	for i in 20:
		cruise.model_anim.player.seek(1.08 * i / 19.0,true)
		t.near(cruise._form_weld.residual_deg(),0,0.01,"cruise wings keep their rotation during melee")
		t.near(cruise._form_weld.residual_pos(),0,0.0001,"cruise wings keep their position during melee")
		t.ok(cruise._blade.is_visible_in_tree(),"cruise melee blade remains visible")
	cruise.free()
	await host.get_tree().process_frame
	t.suite("SaberMotion / Gustav shoulder shield mount")
	for p: SuitProfile in [SuitProfile.gustav00_armed(),SuitProfile.gustav00()]:
		var g := _unit(stage,p)
		var sk := g._model_skel
		var shoulder := sk.find_bone("Shoulder.L")
		var armor := sk.find_bone("Shield.L")
		var anchor := sk.find_bone("shield_L")
		var bind := sk.get_bone_global_rest(shoulder).affine_inverse() * sk.get_bone_global_rest(armor)
		var anchor_bind := sk.get_bone_global_rest(shoulder).affine_inverse() * sk.get_bone_global_rest(anchor)
		for action in ["slash","shoot","shield","dash_l","turn_yaw_L"]:
			if not g.model_anim.has(action): continue
			g.model_anim.player.play(action,0)
			var clip := g.model_anim.player.get_animation(action)
			for i in 12:
				g.model_anim.player.seek(clip.length * i / 11.0,true)
				var relative := sk.get_bone_global_pose(shoulder).affine_inverse() * sk.get_bone_global_pose(armor)
				var relative_anchor := sk.get_bone_global_pose(shoulder).affine_inverse() * sk.get_bone_global_pose(anchor)
				t.near(relative.origin.distance_to(bind.origin),0,0.0001,"armor stays at shoulder through " + action)
				t.near(relative.basis.get_rotation_quaternion().angle_to(bind.basis.get_rotation_quaternion()),0,0.001,"armor orientation follows shoulder through " + action)
				t.near(relative_anchor.origin.distance_to(anchor_bind.origin),0,0.0001,"gameplay shield anchor follows corrected shoulder armor")
		# Move the wrist separately: shoulder geometry must be independent.
		var before := sk.get_bone_global_pose(armor)
		sk.set_bone_pose_rotation(sk.find_bone("Hand.L"),Quaternion(Vector3.RIGHT,1.2))
		g._sync_shoulder_armor()
		t.near(sk.get_bone_global_pose(armor).origin.distance_to(before.origin),0,0.0001,"wrist cannot drag shoulder armor")
		g.free()
		await host.get_tree().process_frame
	stage.free()
	FlightBody.use_placeholder = previous
	await host.get_tree().process_frame
