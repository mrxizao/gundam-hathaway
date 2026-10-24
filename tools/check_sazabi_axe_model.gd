extends Node3D
func _ready()->void:
	Settings.begin_isolated();Game.reset();FlightBody.use_placeholder=false
	var t:=T.new();t.suite("Sazabi / supplied beam axe, grip and thrown orientation")
	var p:=PlayerController.new();p.profile=SuitProfile.sazabi();p.is_player=true;add_child(p);p.set_physics_process(false);p.set_process(false);p.weapon_index=2
	var motion=p.sazabi_systems.motion;p.sazabi_systems.axe_held=.2;motion.step(0)
	t.gt(motion.axe.find_children("*","MeshInstance3D",true,false).size(),0,"actual supplied geometry is held")
	t.eq(ResourceLoader.get_dependencies("res://data/sazabi_models/axe.scn").size(),0,"asset is fully bundled")
	var grip:Marker3D=motion.axe.find_child("Grip",true,false)
	t.lt(grip.global_position.distance_to(motion.joints.Hand_R.global_position),.001,"axe grip meets right palm")
	t.ok(motion.axe.visible,"held axe shown in melee mode")
	var axe:=preload("res://scripts/combat/sazabi_axe.gd").new();axe.shooter=p;axe.direction=Vector3(1,.2,-1).normalized();axe.model=motion.make_blade(true);axe.model.scale=Vector3.ONE*p.profile.target_height/p.profile.model_native_height
	add_child(axe);axe.set_physics_process(false);axe.global_position=grip.global_position
	t.gt((-axe.global_basis.z).dot(axe.direction),.999,"thrown weapon faces flight direction")
	t.gt(axe.model.find_children("*","MeshInstance3D",true,false).size(),0,"throw uses same supplied axe")
	axe.free()
	if DisplayServer.get_name()!="headless":
		var cam:=Camera3D.new();add_child(cam);cam.position=Vector3(27,12,-42);cam.look_at(Vector3.ZERO);cam.fov=42;cam.make_current()
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-40,0);light.light_energy=1.8;add_child(light)
		var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.06,.08,.105);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.7,.75,.85);env.ambient_light_energy=.8;environment.environment=env;add_child(environment)
		for i in 25:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/work/sazabi_axe_held.png")
		p.sazabi_systems.axe_swing=true;p.saber_state=p.SaberState.CHARGE;p._saber_visual_clock=.5;motion.step(0)
		for i in 4:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/work/sazabi_axe_cut.png")
	p.free();Settings.end_isolated();FlightBody.use_placeholder=true
	for suite in ["sazabi","sazabi_network"]:await t.run_suite("res://tests/suite_"+suite+".gd",suite,self,true,true)
	t.report();get_tree().quit(1 if t.failed>0 else 0)
