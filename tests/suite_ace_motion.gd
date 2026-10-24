extends RefCounted
const Motion:=preload("res://scripts/flight/ace_motion.gd")
const Gun:=preload("res://scripts/flight/gun_motion.gd")
static func rotations(sk: Skeleton3D) -> Array[Quaternion]:
	var out: Array[Quaternion]=[]
	for bone in sk.get_bone_count(): out.append(sk.get_bone_pose_rotation(bone))
	return out
static func span(a: Array[Quaternion],b: Array[Quaternion]) -> float:
	var maximum:=0.0
	for i in a.size(): maximum=maxf(maximum,absf(rad_to_deg(a[i].angle_to(b[i]))))
	return maximum
static func run(t: T,host: Node) -> void:
	Game.reset()
	var previous:=FlightBody.use_placeholder;FlightBody.use_placeholder=false
	var stage:=Node3D.new();host.add_child(stage)
	for p in [SuitProfile.xi(),SuitProfile.penelope()]:
		t.suite("AceMotion / "+p.display_name)
		var u:=FlightBody.new();u.profile=p;u.projectile_container=stage;stage.add_child(u)
		u.set_physics_process(false);u.set_process(false);u.global_position=Vector3(0,3000,0)
		var sk:=u._model_skel;var anim:=u.model_anim
		anim.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		t.ok(Motion.supports(p),"target suit opted in")
		var library:=anim.player.get_animation_library(ModelAnimator.DEFAULT_LIBRARY)
		var poses: Dictionary={}
		for dir in FlightBody.DASH_DIR_NAMES:
			var action: String="dash_"+dir
			t.near(anim.player.get_animation(action).length,0.4,0.001,"authored form baseline preserved: "+dir)
			var clip:=anim.player.get_animation(anim.playback_name(action))
			t.near(clip.length,0.52,0.001,"new thrust envelope wired to playback: "+dir)
			t.eq(clip.loop_mode,Animation.LOOP_NONE,"thrust does not periodically restart: "+dir)
			anim.play_loop(action,0.0,true);anim.player.advance(0.0);anim.player.seek(0.3,true)
			poses[dir]=rotations(sk)
			for name in ["Hips","Chest","UpperArm.L","UpperArm.R","Thigh.L","Thigh.R","Shin.L","Shin.R"]:
				var bone:=sk.find_bone(name)
				t.near(sk.get_bone_pose_position(bone).distance_to(sk.get_bone_rest(bone).origin),0.0,0.001,"rigid joint length retained: "+dir+"/"+name)
				t.ok(sk.get_bone_global_pose(bone).is_finite(),"finite thrust pose: "+dir+"/"+name)
		t.gt(span(poses["f"],poses["b"]),15.0,"forward thrust and reverse braking have distinct silhouettes")
		t.gt(span(poses["l"],poses["r"]),8.0,"left/right thrust has lateral bracing")
		if p.id==SuitProfile.Id.PENELOPE:
			u._start_dash_anim(Vector3.UP)
			t.eq(u._dash_anim_dir,"u","vertical ascent is routed from actual quick boost input")
			u._start_dash_anim(Vector3.DOWN)
			t.eq(u._dash_anim_dir,"d","vertical descent is routed from actual quick boost input")
			anim.play_loop("dash_u",0.0,true);anim.player.advance(0.0);anim.player.seek(0.30,true)
			var up:=rotations(sk)
			anim.play_loop("dash_d",0.0,true);anim.player.advance(0.0);anim.player.seek(0.30,true)
			t.gt(span(up,rotations(sk)),15.0,"ascent tucks legs; descent extends them")
		if p.id==SuitProfile.Id.XI:
			var clip:=anim.player.get_animation(anim.playback_name("fly_f"))
			anim.play_loop("fly_f",0.0,true);anim.player.advance(0.0)
			var first:=rotations(sk);anim.player.seek(clip.length,true)
			t.lt(span(first,rotations(sk)),0.1,"steady flight loops without leg pumping")
		# Fire from a reverse thrust stance: knees stay committed and barrel stays aimed.
		anim.play_loop("dash_b",0.0,true);anim.player.advance(0.0);anim.player.seek(0.3,true)
		var stance:=rotations(sk)
		var thigh:=sk.find_bone("Thigh.R")
		var began:=Time.get_ticks_usec()
		anim.play_once("shoot",0.12,true)
		var build_ms: float=(Time.get_ticks_usec()-began)/1000.0
		anim.player.advance(0.0)
		t.lt(span(stance,rotations(sk)),0.1,"shoot transition begins at evaluated current pose")
		for frame in 10: anim.player.advance(1.0/60.0)
		t.lt(absf(rad_to_deg(stance[thigh].angle_to(sk.get_bone_pose_rotation(thigh)))),0.1,"gun recoil preserves current leg stance")
		var root:=u.global_transform.affine_inverse()*sk.global_transform
		var axis:=Vector3.FORWARD
		if p.id==SuitProfile.Id.XI:
			axis=(root.basis*sk.get_bone_global_pose(sk.find_bone("Hand.R")).basis*u._gun_barrel_in_hand).normalized()
		else:
			var elbow:=root*sk.get_bone_global_pose(sk.find_bone("LowerArm.R")).origin
			var tip:=root*sk.get_bone_global_pose(sk.find_bone("muzzle_R")).origin
			axis=elbow.direction_to(tip)
		t.lt(rad_to_deg(axis.angle_to(Vector3.FORWARD)),6.0,"body recoil does not divert muzzle")
		print("[ACE_CONTEXT_SHOT] ",p.display_name," build_ms=",build_ms)
		# A completed non-looping dash still supplies a continuous blend source.
		anim.play_loop("dash_f",0.0,true);anim.player.advance(0.0);anim.player.seek(0.52,true)
		var outgoing:=rotations(sk)
		anim.play_loop("fly_b",0.18,true);anim.player.advance(0.0)
		t.lt(span(outgoing,rotations(sk)),0.1,"completed dash blends from final evaluated pose")
		var max_step:=0.0;var last:=rotations(sk)
		for frame in 20:
			anim.player.advance(1.0/60.0)
			var now:=rotations(sk);max_step=maxf(max_step,span(last,now));last=now
		t.lt(max_step,15.0,"dash-to-flight transition has no single-frame snap")
		for name in ["trans_fly_to_slash","trans_slash_to_fly"]:
			var clip:=anim.player.get_animation(anim.playback_name(name))
			t.gt(clip.length,0.29,"melee transition gets a deliberate recovery interval")
			anim.play_once(name,0.12,true);anim.player.advance(0.0)
			anim.player.seek(clip.length-0.01,true)
			t.not_ok(anim.finished(),"completion follows actual playback alias length")
		# Aim remains stable when shots originate from any directional thrust.
		for dir in FlightBody.DASH_DIR_NAMES:
			anim.play_loop("dash_"+dir,0.0,true);anim.player.advance(0.0);anim.player.seek(0.30,true)
			anim.play_once("shoot",0.0,true);anim.player.advance(0.14)
			var aim:=Vector3.FORWARD
			if p.id==SuitProfile.Id.XI:
				aim=(root.basis*sk.get_bone_global_pose(sk.find_bone("Hand.R")).basis*u._gun_barrel_in_hand).normalized()
			else:
				aim=(root*sk.get_bone_global_pose(sk.find_bone("LowerArm.R")).origin).direction_to(root*sk.get_bone_global_pose(sk.find_bone("muzzle_R")).origin)
			t.lt(rad_to_deg(aim.angle_to(Vector3.FORWARD)),6.0,"directional thrust does not divert firing aim: "+dir)
		# Generated contextual clips cannot accumulate one resource per trigger.
		for i in 8:
			anim.play_once("shoot",0.0,true);anim.player.advance(0.02)
		t.ok(library.has_animation("__ace_live_shoot"),"one reusable live shot alias")
		var dynamic_count:=0
		for n in library.get_animation_list():
			if str(n).begins_with("__ace_live"): dynamic_count+=1
		t.eq(dynamic_count,1,"repeated shooting does not grow the animation library")
		u.free();await host.get_tree().process_frame
	t.suite("AceMotion / full humanoid roster directional dash")
	for p in [SuitProfile.odysseus(),SuitProfile.arizeus(),SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU),SuitProfile.gustav00_armed(),SuitProfile.messer_m01(),SuitProfile.messer_cmd(),SuitProfile.messer_f01()]:
		var body := FlightBody.new()
		body.profile=p;body.projectile_container=stage;stage.add_child(body)
		body.set_process(false);body.set_physics_process(false)
		body.position=Vector3(0,3000,0)
		var sk := body._model_skel
		var anim := body.model_anim
		t.ok(sk != null and anim.ready,"real animated model present: "+p.display_name)
		if sk == null or not anim.ready:
			body.free()
			continue
		anim.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var poses := {}
		for dir in FlightBody.DASH_DIR_NAMES + ["u","d"]:
			var action: String="dash_"+dir
			t.ok(anim.has(action),"direction installed: "+p.display_name+"/"+dir)
			var clip := anim.player.get_animation(anim.playback_name(action))
			t.eq(clip.loop_mode,Animation.LOOP_NONE,"dash never pumps as a flight loop")
			anim.play_loop(action,0.0,true);anim.player.advance(0.0)
			var last := rotations(sk)
			var max_step := 0.0
			for frame in range(1,33):
				anim.player.seek(minf(frame/60.0,clip.length),true)
				var now := rotations(sk)
				max_step=maxf(max_step,span(last,now));last=now
				if frame==18: poses[dir]=now
			t.lt(max_step,20.0,"continuous dash: "+p.display_name+"/"+dir)
			for bone in ["Hips","Thigh.L","Shin.R"]:
				var i := sk.find_bone(bone)
				t.near(sk.get_bone_pose_position(i).distance_to(sk.get_bone_rest(i).origin),0.0,0.001,"dash keeps joint lengths")
		t.gt(span(poses.f,poses.b),12.0,"forward/back silhouettes differ: "+p.display_name)
		t.gt(span(poses.l,poses.r),8.0,"left/right silhouettes differ: "+p.display_name)
		t.gt(span(poses.u,poses.d),12.0,"vertical silhouettes differ: "+p.display_name)
		body.free()
		await host.get_tree().process_frame
	t.suite("AceMotion / rigid hull dash and recovery")
	for p in [SuitProfile.gp03d(),SuitProfile.neue_ziel(),SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)]:
		var body := FlightBody.new()
		body.profile=p;body.projectile_container=stage;stage.add_child(body)
		body.set_process(false);body.set_physics_process(false)
		body.position=Vector3(0,3000,0)
		body._tick_effects(0.0)
		var neutral := body.model_pivot.rotation_degrees
		var poses := {}
		for dir in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN]:
			body._qb_dir=dir
			body._qb_timer=FlightBody.QB_TIME-0.20
			body._tick_effects(0.0)
			poses[dir]=body.model_pivot.rotation_degrees
			t.gt(neutral.distance_to(poses[dir]),1.0,"rigid hull participates in thrust: "+p.display_name)
			t.lt(neutral.distance_to(poses[dir]),12.0,"large hull trim stays controlled")
			body._qb_timer=0.0
			body._tick_effects(0.0)
			t.near(body.model_pivot.rotation_degrees.distance_to(neutral),0.0,0.001,"hull returns without residual bank")
		t.gt(poses[Vector3.LEFT].distance_to(poses[Vector3.RIGHT]),8.0,"rigid hull differentiates lateral thrust")
		body.free()
		await host.get_tree().process_frame
	t.not_ok(Motion.supports(SuitProfile.gp03s()),"GP03S articulation remains separately owned")
	FlightBody.use_placeholder=previous
	stage.queue_free();await host.get_tree().process_frame
