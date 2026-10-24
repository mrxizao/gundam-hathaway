extends RefCounted
const Motion := preload("res://scripts/flight/ace_motion.gd")
const Sample := preload("res://scripts/flight/gun_motion.gd")
static func run(t: T,host: Node) -> void:
	t.suite("Xi / cruise dash and firing integration")
	Game.reset()
	var old := FlightBody.use_placeholder
	FlightBody.use_placeholder = false
	var stage := Node3D.new()
	host.add_child(stage)
	var body := PlayerController.new()
	body.profile = SuitProfile.xi()
	body.projectile_container = stage
	stage.add_child(body)
	body.set_physics_process(false)
	body.set_process(false)
	body.position.y = 3000
	body.cruise_morph = 1.0
	body.fm.boosting = true
	var anim := body.model_anim
	var sk := body._model_skel
	anim.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	t.ok(Motion.cruise_ready(body),"cruise variants installed on real Xi")
	anim.hold_cruise(0.0,true)
	anim.player.advance(0.0)
	var ref := Sample._sample(sk,anim.player.get_animation(ModelAnimator.CRUISE_HOLD_CLIP),0.0)
	var poses: Dictionary = {}
	for direction in FlightBody.DASH_DIR_NAMES:
		body.model_fsm = ModelAnimFSM.create(anim,true)
		body._dash_anim_dir = direction
		body._tick_model_anim(1.0/60)
		t.eq(body.model_fsm.state,ModelAnimFSM.State.DASH,"real host routes cruise dash: "+direction)
		t.eq(anim.current,"dash_cruise_"+direction,"FSM selects cruise baseline: "+direction)
		anim.player.advance(0.12)
		anim.player.seek(0.26,true)
		anim.player.advance(0.0)
		poses[direction] = sk.get_bone_pose_rotation(sk.find_bone("Hips"))
		for bone_name in ["UpperArm.R","LowerArm.R","Hand.R"]:
			var bone := sk.find_bone(bone_name)
			t.lt(rad_to_deg((ref["r"][bone] as Quaternion).angle_to(sk.get_bone_pose_rotation(bone))),0.1,"dash does not raise rifle: "+direction+"/"+bone_name)
		t.lt(body._form_weld.residual_deg(),0.1,"wings remain unfolded: "+direction)
		t.lt(body._form_weld.residual_pos(),0.001,"wing joints keep cruise offsets: "+direction)
		t.ok(sk.get_bone_global_pose(sk.find_bone("Thigh.R")).is_finite(),"valid joint transforms: "+direction)
	t.gt(rad_to_deg((poses["f"] as Quaternion).angle_to(poses["b"])),8.0,"forward/reverse torso motion survives frame-end form lock")
	body.rifle_cooldown = 0.0
	t.ok(body.fire_beam(true),"actual beam fire succeeds during cruise dash")
	t.eq(body.model_fsm.state,ModelAnimFSM.State.ACTION,"shot owns FSM above dash")
	t.eq(anim.current,"shoot","actual gameplay event starts shot")
	anim.player.advance(0.0)
	for frame in 10: anim.player.advance(1.0/60)
	var root := body.global_transform.affine_inverse()*sk.global_transform
	var axis := (root.basis*sk.get_bone_global_pose(sk.find_bone("Hand.R")).basis*body._gun_barrel_in_hand).normalized()
	t.lt(rad_to_deg(axis.angle_to(Vector3.FORWARD)),6.0,"cruise recoil does not divert barrel")
	var upper := sk.find_bone("UpperArm.R")
	t.gt(rad_to_deg((ref["r"][upper] as Quaternion).angle_to(sk.get_bone_pose_rotation(upper))),10.0,"rifle visibly raises when firing")
	body._dash_anim_dir = ""
	body.stow_idle = 3.0
	for frame in 240:
		body._tick_model_anim(1.0/60)
		anim.player.advance(1.0/60)
	t.eq(body.model_fsm.state,ModelAnimFSM.State.IDLE,"shot and stow return to cruise idle")
	t.lt(rad_to_deg((ref["r"][upper] as Quaternion).angle_to(sk.get_bone_pose_rotation(upper))),0.1,"rifle restores cruise carry pose")
	t.lt(body._form_weld.residual_deg(),0.1,"wings remain cruise after recovery")
	stage.free()
	FlightBody.use_placeholder = old

