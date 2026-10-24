extends Node3D
func _ready()->void:
	Settings.begin_isolated();Game.reset();FlightBody.use_placeholder=false
	var cam:=Camera3D.new();add_child(cam);cam.position=Vector3(28,10,-43);cam.look_at(Vector3(0,0,0));cam.fov=42;cam.make_current()
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-35,0);light.light_energy=1.8;add_child(light)
	var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.06,.08,.105);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.7,.75,.85);env.ambient_light_energy=.6;environment.environment=env;add_child(environment)
	var out:="C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/work/nu_sazabi_visual"
	DirAccess.make_dir_recursive_absolute(out)
	for profile in [SuitProfile.nu_gundam(),SuitProfile.sazabi()]:
		var p:=PlayerController.new();p.profile=profile;p.is_player=true;add_child(p);p.set_physics_process(false);p.set_process(false)
		var heavy:bool=profile.id==SuitProfile.Id.SAZABI
		var prefix:="sazabi" if heavy else "nu"
		for mode in ["idle","flight","boost","forward","back","left","right","up","down","rifle","windup","cut","rear","throw_windup","throw_release","throw_recover"]:
			p._qb_timer=0;p.saber_state=p.SaberState.IDLE;p._saber_visual_tail=0;p._gun_recoil_clock=2;p.weapon_index=0;p.fm.speed=profile.player_top_speed()*.6
			p.fm.boosting=mode=="boost"
			if mode=="idle":p.fm.speed=0
			if heavy:
				p.sazabi_systems.axe_swing=mode in ["windup","cut"];p.sazabi_systems.axe_held=0;p.sazabi_systems._axe_thrown=false;p.sazabi_systems.motion.throw_age=10
				if mode.begins_with("throw"):
					p.weapon_index=2;p.sazabi_systems.axe_held=.25 if mode=="throw_windup" else .4
					if mode!="throw_windup":p.sazabi_systems._axe_thrown=true
			cam.position=Vector3(28,10,-43) if mode!="rear" else Vector3(24,-4,45);cam.look_at(Vector3.ZERO)
			var dirs:={"forward":Vector3.FORWARD,"back":Vector3.BACK,"left":Vector3.LEFT,"right":Vector3.RIGHT,"up":Vector3.UP,"down":Vector3.DOWN}
			if dirs.has(mode):p._qb_timer=p.QB_TIME-.14;p._qb_dir=dirs[mode]
			if mode=="rifle":p._gun_recoil_clock=.07
			if mode in ["windup","cut"]:
				p.weapon_index=2 if heavy else 1;p.saber_state=p.SaberState.CHARGE;p._saber_visual_clock=.2 if mode=="windup" else .5;p._show_blade()
			if mode=="rear":p.fm.boosting=true;p.fm.throttle=1
			for i in 24:
				if heavy and mode.begins_with("throw") and mode!="throw_windup":p.sazabi_systems.motion.throw_age=.12 if mode=="throw_release" else .5
				if heavy:p.sazabi_systems.motion.step(1.0/60)
				p._sync_xi_plumes()
				if mode=="rear":
					for fx in p._plume_fx:
						if is_instance_valid(fx.ab):fx.ab.emitting=true
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out+"/"+prefix+"_"+mode+".png")
			print("MOTION_VISUAL ",prefix," ",mode)
		p.free();await get_tree().process_frame
	Settings.end_isolated();get_tree().quit()
