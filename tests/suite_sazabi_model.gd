extends RefCounted
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset();Game.rifle_metrics_test_mode=true
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=false
	t.suite("Sazabi / portable assets and real articulated equipment")
	for file in ["normal","shotgun","sniper","shield","state"]:
		var path:String="res://data/sazabi_models/"+file+(".res" if file=="state" else ".scn")
		t.ok(ResourceLoader.exists(path),file+" is packaged inside the project")
		t.eq(ResourceLoader.get_dependencies(path).size(),0,file+" has no external model or texture dependencies")
	var stage:=Node3D.new();host.add_child(stage)
	var p:=PlayerController.new();p.profile=SuitProfile.sazabi();p.is_player=true;p.team=0;p.position=Vector3(0,5000,0);stage.add_child(p);p.set_physics_process(false);p.controls_enabled=true
	var s=p.sazabi_systems;var m=s.motion
	t.eq(m.joints.size(),20,"twenty mechanical joints retain the real suit")
	t.eq(m.docks.size(),6,"six real funnel docks are present")
	t.eq(m.belly_muzzle.get_parent(),m.joints.Torso,"abdominal cannon port follows the torso joint")
	t.lt((p.global_transform*p.cannon_muzzles()[0]).distance_to(m.belly_muzzle.global_position),.001,"real cannon emitter matches the waist marker")
	t.near(p.model_bounds.size.y,23,.001,"suit height is scaled to 23 metres")
	t.lt((m.shotgun.global_transform*Vector3(0,-.13,-.20)).distance_to(m.joints.Hand_R.global_position),.001,"shotgun grip meets the actual right palm")
	t.gt(m.shotgun.global_basis.z.normalized().dot(p.forward()),.99,"shotgun muzzle faces forward")
	p.weapon_index=1;m.step(0)
	t.lt((m.sniper.global_transform*Vector3(0,-.075,-.265)).distance_to(m.joints.Hand_R.global_position),.001,"sniper grip also meets the right palm")
	t.lt((p.global_transform*m.muzzle_local()).distance_to(m.sniper.global_transform*Vector3(0,.02,.49)),.001,"emitter follows the selected rifle tip")
	p.shield_up=true;m.step(0)
	t.ok(m.shield.get_parent()==m.joints.Hand_L,"shield is attached to the left hand")
	p.weapon_index=2;m.step(0);t.ok(m.saber.visible,"melee mode equips its own green sword")
	p._show_blade();t.eq(p._blade_anchor,null,"native placeholder blade cannot duplicate the held sword")
	FlightBody.use_placeholder=true
	var foe:=FlightBody.new();foe.profile=SuitProfile.xi();foe.team=1;foe.position=p.position+Vector3(200,0,-1000);stage.add_child(foe);foe.set_physics_process(false);foe.ifield_hp=0;foe.ifield_max=0;foe.hp=10000;foe.max_hp=10000
	var lock:=LockOnSystem.new();stage.add_child(lock);lock.setup(p);lock.select_target(foe);lock.force_lock();lock.set_physics_process(false)
	var cam:=ChaseCamera.new();stage.add_child(cam);cam.set_physics_process(false);cam.make_current();p.setup_refs(lock,cam);cam.set_target(p)
	p.shield_up=false;p.weapon_index=1;m.step(0);s.scoped=true;s.selected=foe
	t.ok(s.fire_primary(),"real sniper can fire while scoped")
	var cannon=p.active_cannon;cannon.set_physics_process(false)
	var origin:Vector3=p.global_transform*m.muzzle_local()
	var expected:Vector3=origin.direction_to(p.rifle_aim_point(origin,foe,true))
	t.gt(cannon._aim_dir(origin).dot(expected),.9999,"sustained sniper follows the precision solution")
	var hp_before:float=foe.hp
	cannon._apply_damage(origin,foe.global_position+expected*100,.2)
	t.lt(foe.hp,hp_before,"sustained beam actually damages a unit along the rifle ray")
	cannon.queue_free();p.active_cannon=null
	s.scoped=false;t.ok(s.launch(),"actual back-mounted funnels deploy")
	for drone in s.drones:
		drone.set_physics_process(false)
		t.gt(drone.visual.find_children("*","MeshInstance3D",true,false).size(),0,"launched funnel uses real backpack geometry")
		t.not_ok(m.docks[drone.slot].visible,"deployed funnel is removed from its own dock")
	var drone=s.drones[0];drone.global_position=foe.position;drone.global_basis=Basis(Vector3.UP,1.3)
	s.recall();s.return_age=2.999;drone.step(.001)
	t.lt(drone.global_position.distance_to(s.home(0)),1,"return converges onto the moving physical dock")
	t.lt(drone.global_basis.get_rotation_quaternion().angle_to(m.docks[0].global_basis.orthonormalized().get_rotation_quaternion()),.003,"return aligns orientation with the backpack")
	s.step(3);await host.get_tree().process_frame
	t.suite("Sazabi / GP03 cockpit, own name and line art, no graduations")
	var hud:=FlightHUD.new();stage.add_child(hud);hud.size=Vector2(1600,900);hud.setup(p,cam,lock)
	Settings.first_person=true;Settings.dash_screen_mode=Settings.DASH_SCREEN_SILHOUETTE;cam.first_person=true;cam.set_target(p);Game.phase=Game.Phase.FIGHT
	hud._cockpit_3d._process(.1)
	t.eq(hud._cockpit_3d.last_family,3,"Sazabi uses the GP03 instrument family")
	t.not_ok(hud.cockpit_has_graduations(),"all cockpit HUD graduation layers are disabled")
	t.ok(hud._cockpit_3d.panorama.no_graduations,"panoramic calibration ladders are disabled")
	t.not_ok(hud._cockpit_3d.panorama.horizon.visible,"world rail layer is hidden")
	t.eq(preload("res://scripts/ui/gp03_cockpit_surface.gd").instrument_title(p.profile.id),"MSN-04  /  SAZABI","instrument title identifies Sazabi")
	t.eq(FlightHUD.silhouette_key(p.profile.id,0),8,"own line-art key replaces GP03 imagery")
	t.ok(preload("res://scripts/ui/cockpit_surface.gd").STATE_TEXTURES.has(8),"own packaged line art is available to the instruments")
	t.eq(preload("res://scripts/ui/cockpit_3d.gd").cockpit_family(SuitProfile.Id.GP03D),3,"original GP03 instrument family is preserved")
	Settings.first_person=false;t.ok(hud.cockpit_has_graduations(),"third-person flight rulers remain available")
	t.ok(MainMenu.SUITS.has(p.profile.id) and MainMenu.ENEMY_SUITS.has(p.profile.id),"player and opponent menus both list Sazabi")
	stage.queue_free();await host.get_tree().process_frame;await host.get_tree().process_frame
	Game.reset();FlightBody.use_placeholder=old;Settings.end_isolated()
