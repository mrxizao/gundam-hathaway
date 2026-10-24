extends Node
func _ready() -> void:
	Settings.begin_isolated();Settings.first_person=false
	Game.phase=Game.Phase.FIGHT
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	var stage:=Node3D.new();add_child(stage)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.04,.07,.10);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.6
	var world:=WorldEnvironment.new();world.environment=env;stage.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-30,0);stage.add_child(sun)
	FlightBody.use_placeholder=false
	var p:=PlayerController.new();p.profile=SuitProfile.regz_custom();p.is_player=true;p.team=0;p.assist_on=true;p.controls_enabled=true;p.projectile_container=stage;stage.add_child(p);p.set_process(false);p.set_physics_process(false);p.position=Vector3(0,3000,0)
	var l:=LockOnSystem.new();stage.add_child(l);l.setup(p);l.set_physics_process(false)
	var cam:=ChaseCamera.new();stage.add_child(cam);cam.target=p;cam.set_physics_process(false);cam.make_current();p.setup_refs(l,cam)
	FlightBody.use_placeholder=true
	var foe:=FlightBody.new();foe.team=1;foe.profile=SuitProfile.gustav00();stage.add_child(foe);foe.set_process(false);foe.set_physics_process(false);foe.position=p.position+Vector3(1200,150,-600)
	FlightBody.use_placeholder=false;l.select_target(foe);cam.aim_target=foe
	var hud:=FlightHUD.new();add_child(hud);hud.setup(p,cam,l)
	var out:="C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/regz_precision_tracking";DirAccess.make_dir_recursive_absolute(out)
	for form in [0,1]:
		if p.profile.form != form:p.switch_form(form)
		p.regz_weapons.irradiation=false;p.regz_weapons.held=true
		p.global_basis=Basis.IDENTITY;p.translate_mode=form==0
		var origin:=p.position
		for frame in 90:
			if form==0:
				p._apply_translate(1.0/60.0);p.position=origin;p.fm.velocity=Vector3.ZERO
			p._tick_effects(1.0/60.0);cam.step_now(1.0/60.0)
		hud.push_notice("常态：机体与镜头跟随" if form==0 else "巡航：仅镜头跟随",3.0)
		for mesh in stage.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh is PrimitiveMesh and not foe.model_root.is_ancestor_of(mesh): mesh.visible=false
		for frame in 4:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out+"/form_"+str(form)+".png")
	p.regz_weapons.cancel()
	for frame in 90:cam.step_now(1.0/60.0)
	for frame in 4:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out+"/released.png")
	Settings.end_isolated();print("REGZ TRACKING PREVIEW COMPLETE");get_tree().quit()
