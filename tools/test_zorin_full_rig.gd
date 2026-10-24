extends Node3D
var checks:=0
var fails:=0
func check(ok:bool,label:String)->void:
	if ok:checks+=1;print("PASS ",label)
	else:fails+=1;push_error("FAIL "+label)
func frames(n:int)->void:
	for i in n:await get_tree().process_frame
func _ready()->void:
	await get_tree().process_frame
	Settings.begin_isolated();Game.reset();Game.phase=Game.Phase.FIGHT;FlightBody.use_placeholder=false
	var p:=PlayerController.new();p.profile=SuitProfile.zorin_soul();p.team=0;add_child(p);p.set_physics_process(false);p.set_process(false);p.nu_systems.set_physics_process(false)
	var rig=p.model_root.find_child("ZorinSoul",true,false);rig.set_process(false)
	var sk:Skeleton3D=rig.skeleton
	check(sk.get_bone_count()==26,"Complete 26-bone hierarchy")
	check(sk.get_bone_parent(sk.find_bone("shin-1"))==sk.find_bone("leg-1") and sk.get_bone_parent(sk.find_bone("foot-1"))==sk.find_bone("shin-1"),"Hip knee ankle linked in order")
	sk.reset_bone_poses();sk.force_update_all_bone_transforms()
	var rest_ok:=true
	for i in sk.get_bone_count():
		if sk.get_bone_pose_position(i).distance_to(sk.get_bone_rest(i).origin)>.000001:rest_ok=false
	check(rest_ok,"Standing pose retains every rest translation")
	check(sk.get_bone_global_pose(sk.find_bone("foot-1")).origin.y< -.42,"Feet remain below knees, separated from skirt")
	var mounts:Dictionary=p._model_mounts
	check(mounts.has("saber_R") and mounts.saber_R.get_parent().bone_name=="hand-1","Saber attached to left wrist")
	check(mounts.muzzle_L.get_parent().bone_name=="hand1","Rifle attached to right wrist")
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=1.4;add_child(light)
	var we:=WorldEnvironment.new();we.environment=Environment.new();we.environment.background_mode=Environment.BG_COLOR;we.environment.background_color=Color(.04,.055,.08);we.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;we.environment.ambient_light_color=Color(.75,.82,1);we.environment.ambient_light_energy=.65;add_child(we)
	var cam:=Camera3D.new();cam.near=2;cam.far=10000;cam.fov=45;add_child(cam);cam.position=Vector3(23,6,-46);cam.look_at(Vector3.ZERO);cam.current=true
	for node in p.find_children("*","GPUParticles3D",true,false):node.emitting=false
	for node in p.find_children("NavLight*","MeshInstance3D",true,false):node.hide()
	if is_instance_valid(p._nav_strobe):p._nav_strobe.hide()
	var out:=OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	if DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(out);p.model_pivot.rotation=Vector3.ZERO
		await frames(15);await RenderingServer.frame_post_draw;get_viewport().get_texture().get_image().save_png(out.path_join("01_standing.png"))
		var mesh:=ImmediateMesh.new();var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.no_depth_test=true;mat.albedo_color=Color(.1,1,.75)
		mesh.surface_begin(Mesh.PRIMITIVE_LINES,mat)
		for i in sk.get_bone_count():
			var parent:=sk.get_bone_parent(i)
			if parent>=0:mesh.surface_add_vertex(sk.get_bone_global_pose(parent).origin);mesh.surface_add_vertex(sk.get_bone_global_pose(i).origin)
		mesh.surface_end();var lines:=MeshInstance3D.new();lines.mesh=mesh;sk.add_child(lines)
		for i in sk.get_bone_count():
			var dot:=MeshInstance3D.new();var ball:=SphereMesh.new();ball.radius=.004;ball.height=.008;dot.mesh=ball;dot.material_override=mat;sk.add_child(dot);dot.position=sk.get_bone_global_pose(i).origin
		await frames(5);await RenderingServer.frame_post_draw;get_viewport().get_texture().get_image().save_png(out.path_join("02_skeleton.png"))
		lines.queue_free()
		for node in sk.get_children():
			if node is MeshInstance3D and node.mesh is SphereMesh:node.queue_free()
	p.translate_mode=true;p.fm.speed=p.profile.player_top_speed()*.6;p.model_pivot.rotation=Vector3.ZERO
	var dirs:Dictionary={"W":Vector3.FORWARD,"S":Vector3.BACK,"A":Vector3.LEFT,"D":Vector3.RIGHT,"up":Vector3.UP,"down":Vector3.DOWN}
	for mode in ["W","S","A","D","dash_W","dash_S","dash_A","dash_D","dash_up","dash_down","shield","windup","cut","follow","rear"]:
		p._qb_timer=0;p.translate_dir=Vector3.ZERO;p.shield_up=false;p.saber_state=p.SaberState.IDLE;p._saber_visual_tail=0;p._hide_blade()
		if dirs.has(mode):p.translate_dir=dirs[mode]
		if mode.begins_with("dash_"):p._qb_timer=.3;p._qb_dir=dirs[mode.trim_prefix("dash_")]
		if mode=="shield":p.shield_up=true
		if mode in ["windup","cut","follow"]:
			p.saber_state=p.SaberState.CHARGE;p._saber_visual_clock=.2 if mode=="windup" else (.38 if mode=="cut" else .54);p._show_blade()
		rig.step(1)
		var lengths_ok:=true
		for i in sk.get_bone_count():
			var parent:=sk.get_bone_parent(i)
			if parent>=0 and absf(sk.get_bone_global_pose(i).origin.distance_to(sk.get_bone_global_pose(parent).origin)-sk.get_bone_rest(i).origin.length())>.00001:lengths_ok=false
		check(lengths_ok,"Bone lengths preserved "+mode)
		if mode in ["windup","cut","follow"]:
			check(p._blade_anchor.global_position.distance_to(p._zorin_mount_world("saber_R").origin)<.001,"Left blade follows current wrist "+mode)
			check(rig.rifle.visible,"Right hand keeps rifle "+mode)
			check(is_equal_approx(p._blade_anchor.global_basis.get_scale().x,1.0),"Blade size stays independent of model scale "+mode)
		if DisplayServer.get_name()!="headless":
			cam.position=Vector3(23,6,-46)
			if mode=="rear":cam.position=Vector3(-23,6,46)
			cam.look_at(Vector3.ZERO);await frames(5);await RenderingServer.frame_post_draw;get_viewport().get_texture().get_image().save_png(out.path_join(mode+".png"));print("SHOT ",mode)
	print("FULL_RIG_DONE ",checks," PASS / ",fails," FAIL")
	Settings.end_isolated();get_tree().quit(1 if fails else 0)
