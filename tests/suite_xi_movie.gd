extends RefCounted
static func run(t: T,host: Node) -> void:
	t.suite("XiMovie / imported geometry and rebound motion")
	var previous := FlightBody.use_placeholder
	FlightBody.use_placeholder = false
	var stage := Node3D.new()
	host.add_child(stage)
	var body := PlayerController.new()
	body.profile = SuitProfile.xi()
	body.projectile_container = stage
	stage.add_child(body)
	body.set_process(false)
	body.set_physics_process(false)
	body.position.y = 3000
	var anim := body.model_anim
	var sk := body._model_skel
	anim.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	t.ok(body.profile.model_path.ends_with("xi_movie_rigged.scn"),"default Xi loads new movie asset")
	t.eq(ResourceLoader.get_dependencies(body.profile.model_path).size(),0,"runtime model embeds meshes and textures for portability")
	t.eq(sk.get_bone_count(),78,"51 compatible joints plus 27 mechanical joints")
	t.near(body.model_bounds.size.y,28.0,0.15,"official model height retained")
	var meshes: Dictionary = {}
	for mesh: MeshInstance3D in body.model_root.find_children("*","MeshInstance3D",true,false):
		if mesh.skin != null: meshes[str(mesh.name)] = mesh
	t.eq(meshes.size(),113,"only the new geometry is rendered")
	for part in ["tripo_part_34","tripo_part_60","tripo_part_68","tripo_part_10","tripo_part_59","tripo_part_63"]:
		var mesh: MeshInstance3D = meshes[part]
		var arrays := mesh.mesh.surface_get_arrays(0)
		var bind: int = arrays[Mesh.ARRAY_BONES][0]
		var bone_name := str(mesh.skin.get_bind_name(bind))
		if bone_name.is_empty(): bone_name = str(sk.get_bone_name(mesh.skin.get_bind_bone(bind)))
		var expected := "Weapon.R" if part in ["tripo_part_34","tripo_part_60","tripo_part_68"] else ("LowerArm.L" if part == "tripo_part_10" else ("Hand.R" if part == "tripo_part_59" else "Hand.L"))
		t.eq(bone_name,expected,"equipment follows its own joint: "+part)
	t.ok(sk.find_bone("Movie_RightSmallWingSeparated")>=0,"separated small wing has its own binding")
	var pivot := sk.find_bone("Movie_BackWingRightRigidPivot")
	var child := sk.find_bone("Movie_RightSmallWingSeparated")
	t.eq(sk.get_bone_parent(child),pivot,"small wing follows the complete rigid wing pivot")
	var shoulder_part := sk.find_bone("Movie_tripo_part_50")
	t.eq(str(sk.get_bone_name(sk.get_bone_parent(shoulder_part))),"Shoulder.L","rear shoulder armor never follows the neck")
	var extracted := anim.load_curve_from(body.profile.model_form_curve,PackedStringArray(["Movie_BackWingRightRigidPivot"]))
	t.ok(not extracted["bones"].is_empty(),"mechanical curve extraction reads form_on from the new scene")
	var curve := anim.player.get_animation("form_on")
	for progress in [0.0,0.2,0.5,0.85,1.0]:
		body.cruise_morph = progress
		for action in ["fly","dash_f","shoot","slash"]:
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
					t.lt(rad_to_deg(sk.get_bone_pose_rotation(bone).angle_to(curve.rotation_track_interpolate(track,time))),0.1,"authored panel rotation survives combat mixer")
				elif curve.track_get_type(track)==Animation.TYPE_POSITION_3D:
					t.lt(sk.get_bone_pose_position(bone).distance_to(curve.position_track_interpolate(track,time)),0.0001,"authored panel position survives combat mixer")
				t.ok(sk.get_bone_global_pose(bone).is_finite(),"mechanical joint remains finite")
	body.cruise_morph=1.0
	body._weld_form_bones()
	t.lt(body._form_weld.residual_deg(),0.1,"cruise terminal shape retained")
	t.lt(body._form_weld.residual_pos(),0.0001,"cruise terminal offsets retained")
	stage.free()
	FlightBody.use_placeholder=previous

