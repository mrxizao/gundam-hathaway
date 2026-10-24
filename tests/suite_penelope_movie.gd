extends RefCounted
static func run(t: T,host: Node) -> void:
	t.suite("PenelopeMovie / imported geometry and rebound motion")
	var previous := FlightBody.use_placeholder
	FlightBody.use_placeholder = false
	var stage := Node3D.new()
	host.add_child(stage)
	var body := PlayerController.new()
	body.is_player = true
	body.profile = SuitProfile.penelope()
	body.projectile_container = stage
	stage.add_child(body)
	body.set_process(false)
	body.set_physics_process(false)
	body.position.y = 3000
	body.fm.throttle = 1.0
	for frame in 90:
		body.fm.boosting = frame>=15
		body.fm.super_boost = frame>=45 and frame<70
		body.fm.velocity = Vector3(9000,-6000,-9000) if frame<55 else Vector3(-9000,6000,-9000)
		body._tick_effects(1.0/60.0)
		for item: Dictionary in body._plume_fx:
			t.ok((item["ab"] as GPUParticles3D).emitting,"continuous nozzle core survives acceleration mode changes")
			t.not_ok((item["dash"] as GPUParticles3D).emitting,"no second emitter interrupts the stream")
			t.lt((item.get("bend",Vector3.ZERO) as Vector3).length(),80.001,"nozzle bend stays bounded under extreme crosswind")
			var flame := (item["ab"] as Node).get_node("JetEnvelope") as MeshInstance3D
			var material := flame.mesh.surface_get_material(0) as ShaderMaterial
			var length: float = material.get_shader_parameter("length_m")
			t.lt(flame.position.distance_to((item["axis"] as Vector3)*length*flame.scale.y*0.5),0.0001,"length changes keep the flame root on its nozzle")
	body.fm.super_boost = false
	body.fm.velocity = Vector3.ZERO
	var anim := body.model_anim
	var sk := body._model_skel
	anim.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	t.ok(body.profile.model_path.ends_with("penelope_movie_rigged.scn"),"default Penelope loads new movie asset")
	t.eq(ResourceLoader.get_dependencies(body.profile.model_path).size(),0,"runtime model embeds meshes and textures for portability")
	t.eq(sk.get_bone_count(),215,"39 combat joints plus 176 rigid mechanical joints")
	t.near(body.model_bounds.size.y,32.5,0.15,"official model height retained")
	var meshes: Dictionary = {}
	for mesh: MeshInstance3D in body.model_root.find_children("*","MeshInstance3D",true,false):
		if mesh.skin != null: meshes[str(mesh.name)] = mesh
	t.eq(meshes.size(),176,"only the new geometry is rendered")
	t.ok(anim.has("shoot") and anim.has("slash") and anim.has("shield"),"combat clips rebound")
	for direction in body.DASH_DIR_NAMES:
		t.ok(anim.has("dash_"+direction),"normal dash installed "+direction)
		t.ok(anim.has("dash_cruise_"+direction),"cruise dash installed "+direction)
	# Exercise the real input action through the hold/tap consumer and flight commit.
	body.translate_mode = true
	body.fm.boosting = true
	body.penelope_cruise_enabled = true
	var charge := body.dash_charge
	Input.action_press("boost")
	for frame in 20: body._tick_penelope_shift(1.0/60.0)
	t.ok(body.fm.super_boost,"held Shift enters super boost")
	t.not_ok(body._qb_pending,"long hold never queues a dash")
	t.near(body.dash_charge,charge,0.00001,"long hold never spends dash charge")
	Input.action_release("boost")
	body._tick_penelope_shift(1.0/60.0)
	t.not_ok(body.fm.super_boost,"release exits super boost")
	t.not_ok(body._qb_pending,"release after long hold is not a tap")
	Input.action_press("boost")
	body._tick_penelope_shift(0.08)
	Input.action_release("boost")
	body._tick_penelope_shift(0.016)
	t.ok(body._qb_pending,"short Shift queues exactly one dash")
	body.penelope_cruise_enabled = false
	t.eq(body._penelope_dash_direction(Vector3.BACK),Vector3.BACK,"normal form back dash remains backward")
	body._start_dash_spin(Vector3.BACK)
	t.not_ok(body._penelope_backflip or body._dash_spin_t > 0.0,"normal back dash does not somersault")
	body.penelope_cruise_enabled = true
	body.translate_dir = Vector3.BACK
	body._apply_translate(0.016)
	t.gt(body._qb_dir.y,0.99,"backward dash is remapped upward")
	t.ok(body._penelope_backflip and body._dash_spin_t>0.0,"upward evasion commits a full somersault window")
	t.eq(body._dash_anim_dir,"u","upward evasion uses ascent animation")
	t.lt(body.dash_charge,charge,"short dash spends charge once")
	body.cruise_morph = 1.0
	body._tick_cruise_morph(0.25)
	t.near(body.cruise_morph,0.0,0.0001,"spin retracts cruise armor to normal")
	body._apply_translate(0.5)
	body._tick_cruise_morph(2.4)
	t.near(body.cruise_morph,1.0,0.0001,"spin completion restores requested cruise shape")
	body._penelope_dash_direction(Vector3.RIGHT)
	body._start_dash_spin(Vector3.RIGHT)
	t.ok(not body._penelope_backflip and body._dash_spin_t>0.0,"side dash commits horizontal full spin")
	body.penelope_cruise_enabled = false
	body._dash_spin_t=0.0
	body._tick_cruise_morph(2.4)
	t.near(body.cruise_morph,0.0,0.0001,"normal form persists independently of automatic acceleration")
	body.translate_mode = false
	body.translate_dash = false
	body._qb_timer=0.0
	Input.action_press("boost")
	body._tick_penelope_shift(0.08)
	Input.action_release("boost")
	body._tick_penelope_shift(0.016)
	t.ok(body._qb_pending and body.fm.boosting,"manual flight also supports short dash")
	body._qb_pending=false
	# Z's target is announced immediately; both visible shape and FORM finish in budget.
	body._dash_spin_t=0.0
	body._dash_anim_dir=""
	body.model_fsm=ModelAnimFSM.create(anim,false)
	for requested in [true,false]:
		body.penelope_cruise_enabled=requested
		for frame in 42:
			body._tick_cruise_morph(1.0/60.0)
			body._tick_model_anim(1.0/60.0)
			anim.player.advance(1.0/60.0)
		body._tick_model_anim(0.0)
		t.near(body.cruise_morph,1.0 if requested else 0.0,0.0001,"Z finishes mechanical transformation within 0.7 seconds")
		t.ok(body.model_fsm.state!=ModelAnimFSM.State.FORM,"no lingering form animation after 0.7 seconds")
	var curve := anim.player.get_animation("form_on")
	for progress in [0.0,0.2,0.5,0.85,1.0]:
		body.cruise_morph = progress
		for action in ["fly","dash_f","dash_cruise_f","shoot","slash"]:
			anim.play_loop(action,0.0,true)
			anim.player.advance(0.0)
			anim.player.seek(0.15,true)
			anim.player.advance(0.0)
			for track in curve.get_track_count():
				var path := curve.track_get_path(track)
				if path.get_subname_count()!=1 or not str(path.get_subname(0)).begins_with("Movie_"): continue
				var bone := sk.find_bone(path.get_subname(0))
				var time: float = curve.length*progress
				if curve.track_get_type(track)==Animation.TYPE_ROTATION_3D:
					t.lt(rad_to_deg(sk.get_bone_pose_rotation(bone).normalized().angle_to(curve.rotation_track_interpolate(track,time).normalized())),0.1,"authored panel rotation survives combat mixer")
				elif curve.track_get_type(track)==Animation.TYPE_POSITION_3D:
					t.lt(sk.get_bone_pose_position(bone).distance_to(curve.position_track_interpolate(track,time)),0.0001,"authored panel position survives combat mixer")
				t.ok(sk.get_bone_global_pose(bone).is_finite(),"mechanical joint remains finite")
	body.cruise_morph=1.0
	body._weld_form_bones()
	t.lt(body._form_weld.residual_deg(),0.1,"cruise terminal shape retained")
	t.lt(body._form_weld.residual_pos(),0.0001,"cruise terminal offsets retained")
	# Both threshold crossing and an overkill hit must escape once, never resurrect twice.
	for lethal in [false,true]:
		var escape := PlayerController.new()
		escape.is_player = true
		escape.profile = SuitProfile.penelope()
		escape.projectile_container = stage
		stage.add_child(escape)
		escape.set_process(false)
		escape.set_physics_process(false)
		escape.ifield_hp = 0.0
		escape._apply_damage(escape.max_hp*(2.0 if lethal else 0.995),null,Damage.Type.BEAM)
		t.ok(escape.alive and escape._transformed,"1 percent or overkill triggers protected escape")
		escape._tick_transform(SuitProfile.TRANSFORM_COVER+0.01)
		t.eq(escape.profile.form,1,"escape swaps to Odysseus form")
		t.ok(escape.profile.model_path.ends_with("odysseus_rigged.scn"),"escape loads new core geometry")
		t.not_ok(escape.profile.has_missiles,"core cannot fire funnel missiles")
		t.eq(escape.funnel_count,0,"core missile inventory cleared")
		t.ok(escape.profile.can_ride_pedal(),"core is eligible to summon a flight pedal")
		t.ok(escape.model_anim.has("shoot") and escape.model_anim.has("slash"),"core combat animations rebound")
		var skel := escape._model_skel
		var wrist := skel.find_bone("Hand.R")
		var palm_bone := skel.find_bone("Movie_tripo_part_18")
		var finger_bone := skel.find_bone("Movie_tripo_part_42")
		t.eq(skel.get_bone_parent(palm_bone),wrist,"palm follows wrist rather than forearm")
		t.eq(skel.get_bone_parent(finger_bone),wrist,"fingers follow the same gripping wrist")
		var wrist_rest := skel.get_bone_global_rest(wrist)
		var palm_rest := skel.get_bone_global_rest(palm_bone)
		var finger_rest := skel.get_bone_global_rest(finger_bone)
		var grip := Vector3(0.13146714*1.02,0.5-0.08940094*1.02,-0.04122531*1.02)
		escape.model_anim.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for action in ["shoot","slash","dash_f","dash_l","dash_r"]:
			escape.model_anim.play_once(action,0.0,true)
			for moment in [0.0,0.2,0.4]:
				escape.model_anim.player.seek(moment,true)
				escape.model_anim.player.advance(0.0)
				var gun_at := skel.get_bone_global_pose(wrist)*wrist_rest.affine_inverse()*grip
				var palm_at := skel.get_bone_global_pose(palm_bone)*palm_rest.affine_inverse()*grip
				var fingers_at := skel.get_bone_global_pose(finger_bone)*finger_rest.affine_inverse()*grip
				t.lt(gun_at.distance_to(palm_at),0.00001,"rifle and palm retain a shared grip in "+action)
				t.lt(gun_at.distance_to(fingers_at),0.00001,"rifle stays inside fingers in "+action)
		t.ok(escape.fire_beam(true),"core can use its carried beam rifle")
		var board := escape.configure_pedal(-1,false)
		t.ok(board != null and escape.has_pedal(),"core can actually mount the pedal")
		t.near(escape.fm.ab_speed,SuitProfile.xi().player_top_speed(),0.01,"mounted top speed equals Xi normal cruise maximum")
		escape.release_pedal()
		t.lt(escape.fm.ab_speed,SuitProfile.xi().player_top_speed(),"dismount removes the dedicated pedal speed")
		escape._apply_damage(escape.max_hp*2.0,null,Damage.Type.BEAM)
		t.not_ok(escape.alive,"second lethal hit destroys core without another escape")
		escape.free()
	await host.get_tree().process_frame
	stage.free()
	await host.get_tree().process_frame
	FlightBody.use_placeholder=previous

