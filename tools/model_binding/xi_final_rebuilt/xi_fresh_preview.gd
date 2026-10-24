extends Node
var camera: Camera3D
var stage: Node3D
var out := "C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/xi_fresh_rig"
func freeze(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)
	for child in n.get_children(): freeze(child)
func shot(key: String) -> void:
	for unused in 2: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(key+".png"))
func _ready() -> void:
	Settings.begin_isolated()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1000,700))
	stage = Node3D.new()
	add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055,0.075,0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8,0.85,1)
	env.ambient_light_energy = 0.5
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	for angle in [Vector3(-40,-35,0),Vector3(-15,140,0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = angle
		light.light_energy = 0.85
		stage.add_child(light)
	camera = Camera3D.new()
	camera.fov = 40
	stage.add_child(camera)
	camera.make_current()
	FlightBody.use_placeholder = false
	var unit := PlayerController.new()
	unit.profile = SuitProfile.xi_final()
	unit.projectile_container = stage
	stage.add_child(unit)
	freeze(unit)
	for mesh in unit.find_children("*","MeshInstance3D",true,false):
		if mesh.skin == null: mesh.visible=false
	for particles in unit.find_children("*","GPUParticles3D",true,false):
		particles.visible=false
		particles.emitting=false
	unit.position = Vector3.ZERO
	camera.position = Vector3(-0.62,0.20,-1).normalized()*unit.profile.target_height*2.4
	camera.look_at(Vector3.ZERO)
	var anim := unit.model_anim
	anim.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.player.play(ModelAnimator.REST_CLIP,0.0)
	anim.player.advance(0.0)
	await shot("01_complete_bind_pose")
	var sk := unit._model_skel
	var overlay := Node3D.new()
	stage.add_child(overlay)
	var material := StandardMaterial3D.new()
	material.albedo_color=Color(1.0,0.70,0.12)
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test=true
	for name in ["Hips","Spine","Chest","Neck","Head","Shoulder.L","UpperArm.L","LowerArm.L","Hand.L","Shoulder.R","UpperArm.R","LowerArm.R","Hand.R","Thigh.L","Shin.L","Foot.L","Thigh.R","Shin.R","Foot.R","Wing.L","Wing.R"]:
		var index := sk.find_bone(name)
		var parent := sk.get_bone_parent(index)
		if parent<0:continue
		var a := sk.global_transform*sk.get_bone_global_pose(parent).origin
		var b := sk.global_transform*sk.get_bone_global_pose(index).origin
		if a.distance_to(b)<0.04:continue
		var line := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius=.075;mesh.bottom_radius=.075;mesh.height=a.distance_to(b);mesh.material=material
		line.mesh=mesh;line.position=(a+b)*.5;line.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()))
		overlay.add_child(line)
	await shot("02_skeleton_overlay")
	overlay.visible=false
	for pair in [["LowerArm.R",12.0],["Hand.R",10.0],["Shin.L",12.0],["Shin.R",12.0]]:
		anim.player.seek(0.0,true)
		var i := sk.find_bone(pair[0])
		sk.set_bone_pose_rotation(i,Quaternion(Vector3.RIGHT,deg_to_rad(pair[1]))*sk.get_bone_rest(i).basis.get_rotation_quaternion())
		sk.force_update_all_bone_transforms()
		await shot("fk_"+str(pair[0]).replace(".","_"))
	anim.player.seek(0.0,true)
	anim.hold_rest(0.0,true);anim.player.advance(0.0)
	await shot("03_ready")
	anim.play_once("shoot",0.0,true);anim.player.seek(.2,true)
	await shot("04_shoot")
	unit.position.y=3000
	camera.position.y+=3000
	unit.try_saber(null)
	anim.play_once("slash",0.0,true);anim.player.seek(.40,true)
	unit._saber_visual_clock=.4;unit._sync_blade_anchor()
	await shot("05_saber")
	unit._hide_blade()
	for flight in ["fly_f","fly_b","fly_l","fly_r"]:
		anim.play_loop(flight,0.0,true);anim.player.advance(0.0);anim.player.seek(.7,true)
		await shot(flight)
	for direction in ["f","b","l","r","u","d"]:
		anim.play_once("dash_"+direction,0.0,true);anim.player.seek(.20,true)
		await shot("dash_"+direction)
	for direction in ["f","b","l","r"]:
		anim.play_once("dash_cruise_"+direction,0.0,true);anim.player.advance(0.0);anim.player.seek(.20,true)
		unit.cruise_morph=1.0;unit._form_weld.weld(1.0)
		await shot("cruise_dash_"+direction)
	anim.hold_cruise(0.0,true);anim.player.advance(0.0)
	unit.cruise_morph=1.0;unit._form_weld.weld(1.0)
	await shot("06_reference_cruise")
	print("FRESH RIG GPU CHECK COMPLETE")
	get_tree().quit()
