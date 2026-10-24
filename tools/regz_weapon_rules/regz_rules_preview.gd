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
	var p:=PlayerController.new();p.profile=SuitProfile.regz_custom();p.is_player=true;p.controls_enabled=true;p.projectile_container=stage;stage.add_child(p);p.set_process(false);p.set_physics_process(false);p.position=Vector3(0,3000,0)
	var l:=LockOnSystem.new();stage.add_child(l);l.setup(p);l.set_physics_process(false)
	var cam:=ChaseCamera.new();stage.add_child(cam);cam.target=p;cam.set_physics_process(false);cam.make_current();p.setup_refs(l,cam)
	var hud:=FlightHUD.new();add_child(hud);hud.setup(p,cam,l)
	var out:="C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/regz_weapon_rules";DirAccess.make_dir_recursive_absolute(out)
	for form in [0,1]:
		if p.profile.form != form:p.switch_form(form)
		p.regz_weapons.irradiation=true;p.regz_weapons.tick(p,1.25,true,false,false)
		for frame in 90: p._regz_motion.step(1.0/60.0);cam.step_now(1.0/60.0)
		p.mount_pedal()
		hud.push_notice(p.pedal_fail_reason(),3.0)
		for frame in 4:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out+"/form_"+str(form)+".png")
	Settings.end_isolated();print("REGZ UI PREVIEW COMPLETE");get_tree().quit()
