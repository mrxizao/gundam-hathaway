extends RefCounted
static func run(t: T, host: Node) -> void:
	t.suite("Neue Ziel / forearms and six sabers")
	var profile := SuitProfile.by_id(SuitProfile.Id.NEUE_ZIEL)
	t.ok(profile.cannon_color().g > profile.cannon_color().r, "Neue cannon green")
	t.ok(profile.saber_beam_color.g > profile.saber_beam_color.r, "Neue sabers green")
	t.eq(SuitProfile.gp03d().cannon_color(), Color(1.0,0.90,0.18), "GP03 cannon yellow")
	t.eq(profile.id_name(),"NEUE_ZIEL","Stable appended ID")
	t.ok(profile.is_ace() and not profile.can_ride_pedal(),"Heavy MA has no pedal")
	t.ok(not profile.cannon_only and not SuitProfile.gp03d().cannon_only,"Both MA have independent normal fire")
	t.ok(not PlayerController.assist_uses_translation(profile),"Cruise assist controls")
	t.ok(not profile.has_dash_limit(),"Super acceleration available")
	var menu := preload("res://scripts/ui/main_menu.gd").new()
	menu.select_mode(Game.MatchMode.VERSUS)
	for ma in [SuitProfile.Id.GP03D, SuitProfile.Id.NEUE_ZIEL]:
		menu.suit_index = menu.active_suit_list().find(ma)
		t.ok(menu.enemy_pool() == [SuitProfile.Id.GP03D, SuitProfile.Id.NEUE_ZIEL], "MA opponent limited to mirror/counterpart")
		t.ok(menu.active_map_list() == [MapDef.Id.LEO], "MA restricted to orbit")
		menu.map_index = 99
		t.eq(menu.selected_map(), MapDef.Id.LEO, "Stale ground map selection clamps to orbit")
	menu.suit_index = 0
	t.ok(not menu.enemy_pool().has(SuitProfile.Id.GP03D), "Normal suits cannot face MA")
	for mode in [Game.MatchMode.TRAINING, Game.MatchMode.CHALLENGE, Game.MatchMode.ENDLESS, Game.MatchMode.SQUAD]:
		menu.select_mode(mode)
		t.ok(not menu.active_suit_list().has(SuitProfile.Id.GP03D) and not menu.active_suit_list().has(SuitProfile.Id.NEUE_ZIEL), "MA restricted to duel mode")
	t.ok(not BattleFormation.federation().all_suits().has(SuitProfile.Id.GP03D), "GP03 excluded from squad roster")
	menu.free()
	var parent := Node3D.new()
	host.add_child(parent)
	var p := PlayerController.new()
	p.profile=profile
	p.team=0
	parent.add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	t.ok(not p.rifle_press_route(),"Ready belly cannon never hijacks shoulder trigger")
	t.ok(profile.weapon_slots().has("cannon"),"Separate belly charge slot")
	t.ok(not profile.weapon_slots().has("rifle"),"Shoulder battery excluded from weapon selection")
	t.eq(p.current_slot(),"cannon","Primary weapon defaults to belly charge cannon")
	t.near(profile.rifle_interval,0.30,0.001,"Shoulder four-cannon cadence accelerated")
	t.near(p.fm.pitch_rate,FlightModel.PITCH_RATE_BASE*.40,.0001,"Heavy MA pitch rate reduced")
	t.near(p.model_bounds.size.y,76.6,0.1,"Scaled mesh height")
	t.near(p.model_bounds.size.x,73.6,0.1,"User specified full width")
	t.near(p.fm.thrust_accel_limit,4.80*9.81,0.001,"Physical 4.80G thrust limit")
	p.fm.speed=200.0
	p.fm.throttle=1.0
	p.fm.boosting=true
	p.fm.super_boost=true
	p.fm._step_speed(1.0,Vector3.FORWARD)
	t.near(p.fm.speed-200.0,4.8*9.81,0.001,"Super boost preserves real maximum thrust")
	t.eq(profile.loaded_mass_t,403.5,"Full mass in tonnes")
	t.eq(profile.engine_plumes.size(),13,"13 propulsion nozzles")
	var arms: Array[Node3D] = []
	var homes: Array[Transform3D] = []
	for side in ["L","R"]:
		var arm := p.find_child("WireArm_"+side,true,false) as Node3D
		arms.append(arm)
		homes.append(arm.transform)
		t.ok(arm!=null,"Actual imported forearm "+side)
		t.eq(arm.get_child_count(),7,"Forearm plus wrist/claws/socket/tip "+side)
	p.control_input = Vector3(0.5, 1.0, 0.0)
	p._tick_effects(0.25)
	t.ok(p._neue_motion.z > 0.0 and p._neue_motion.x < 0.0, "Heavy MA leans into turn and pitch")
	var bank_before := p._neue_motion.z
	p.control_input = Vector3.ZERO
	p._tick_effects(0.25)
	t.ok(p._neue_motion.z > 0.0 and p._neue_motion.z < bank_before, "Heavy MA settles gradually")
	p.rifle_cooldown=0.0
	p.rifle_reloading=false
	p.rifle_mag=profile.rifle_magazine
	p.projectile_container=parent
	t.ok(p.fire_gun(true), "Vulcan action fires shoulder MEGA volley")
	t.eq(p.rifle_mag, profile.rifle_magazine-1, "Shoulder volley consumes one own round")
	p.rifle_cooldown=0.0
	p._show_blade()
	t.eq(p._blade_anchor.limbs.size(),4,"Four separate articulated auxiliary arms")
	t.eq(p._blade_anchor.claw_blades.size(),2,"Both forearms also carry sabers")
	for blade: Node3D in p._blade_anchor.claw_blades:
		t.near(blade.global_basis.x.length(),5.4,0.001,"Forearm blade width enlarged")
		t.near(blade.global_basis.y.length(),5.4,0.001,"Forearm blade thickness enlarged")
		t.near(blade.global_basis.z.length(),3.0,0.001,"Forearm blade length tripled")
	p._hide_blade()
	await host.get_tree().process_frame
	var foe := FlightBody.new()
	foe.profile=SuitProfile.gustav00()
	foe.team=1
	parent.add_child(foe)
	foe.position=Vector3(0,0,-300)
	foe.set_physics_process(false)
	foe.set_process(false)
	t.ok(p.fire_wire_arms(foe),"Launch actual forearms")
	var volley = p.active_wire_arms
	volley.set_physics_process(false)
	volley._physics_process(1.3)
	for i in arms.size():
		t.ok(arms[i].transform.origin.distance_to(homes[i].origin)>30,"Forearm physically leaves body")
		t.eq(arms[i].get_child_count(),7,"Claws travel with forearm")
	t.ok(volley.cable_mesh.get_surface_count()==1,"Visible 3D control cables")
	t.ok(not p.fire_wire_arms(foe),"No duplicate volley during deployment")
	p._show_blade()
	t.eq(p._blade_anchor.claw_blades.size(),0,"Deployed forearms cannot duplicate docked sabers")
	t.eq(p._blade_anchor.limbs.size(),4,"Auxiliary arms still work while forearms deployed")
	p._hide_blade()
	volley._physics_process(3.0)
	volley._physics_process(1.3)
	await host.get_tree().process_frame
	for i in arms.size():
		t.ok(arms[i].transform.is_equal_approx(homes[i]),"Forearm + claws return to original joint")
	p.wire_cd_left=0.0
	foe.position=Vector3(0,0,-6001)
	t.ok(not p.fire_wire_arms(foe),"6km launch gate rejects out-of-range target")
	foe.position=Vector3(0,0,-5990)
	t.ok(p.fire_wire_arms(foe),"Wire arms can launch to nearly 6km")
	var far_volley=p.active_wire_arms
	far_volley.set_physics_process(false)
	far_volley._physics_process(1.3)
	for i in arms.size():
		t.ok(arms[i].global_position.distance_to(far_volley.anchors[i].global_position)>5000,"Forearm travels beyond former 1800m cap")
		t.ok(arms[i].global_position.distance_to(far_volley.anchors[i].global_position)<=6000.1,"Cable deployment respects 6km cap")
	far_volley.free()
	foe.position=Vector3(0,0,-300)
	p._show_blade()
	t.eq(p._blade_anchor.claw_blades.size(),2,"Six sabers restored after return")
	p._hide_blade()
	var pivot := p.model_bounds.get_center()
	p.control_input=Vector3(1,0,0)
	var forward_jet := p.neue_nozzle_drive(pivot+Vector3(0,0,-20),Vector3.DOWN)
	var reverse_jet := p.neue_nozzle_drive(pivot+Vector3(0,0,-20),Vector3.UP)
	t.ok(forward_jet>reverse_jet,"Pitch-up activates correct torque jet")
	p.control_input=Vector3(-1,0,0)
	t.ok(p.neue_nozzle_drive(pivot+Vector3(0,0,-20),Vector3.UP)>p.neue_nozzle_drive(pivot+Vector3(0,0,-20),Vector3.DOWN),"Pitch-down reverses jets")
	var shots_before := parent.get_child_count()
	t.ok(p.fire_beam(true,foe),"Shoulder cannons use normal primary fire")
	t.eq(parent.get_child_count()-shots_before,4,"Four shoulder shots emitted simultaneously")
	t.eq(p._muzzle_local.size(),4,"Four separate shoulder cannon origins")
	p.rifle_reloading=true
	p.rifle_mag=0
	t.ok(p.cannon_ready(),"Empty/reloading shoulder magazine cannot block belly cannon")
	t.ok(p.fire_cannon(foe),"Belly MEGA cannon fires")
	t.eq(p.active_cannon.offsets.size(),1,"Belly cannon uses one abdominal aperture")
	t.ok(p.active_cannon.offsets[0].distance_to(p.rig_anchor("muzzle_L"))<.001,"Belly uses circled aperture, never shoulder origins")
	t.ok(p.rifle_reloading,"Firing cannon does not modify existing shoulder reload")
	p.rifle_reloading=false
	p.rifle_mag=profile.rifle_magazine
	p.rifle_cooldown=0.0
	t.ok(p.fire_beam(true,foe),"Shoulder cannons fire while belly cannon active/cooling")
	var battery: Node3D
	for child in parent.get_children():
		if child.get_script()==preload("res://scripts/combat/neue_battery.gd"):
			battery=child
	t.ok(battery.get_script()==preload("res://scripts/combat/neue_battery.gd"),"Shoulder/rear battery connected")
	t.eq(battery.barrels.size(),0,"Belly cannon cannot take control of shoulder emitters")
	battery.set_physics_process(false)
	var count := parent.get_child_count()
	battery._physics_process(0.1)
	t.eq(parent.get_child_count()-count,0,"Belly cannon never automatically fires shoulder battery")
	foe.position=Vector3(0,0,300)
	count=parent.get_child_count()
	battery._physics_process(1.0)
	t.eq(parent.get_child_count()-count,5,"Five skirt cannons cover rear")
	var before := p.funnel_count
	t.ok(p.fire_funnel(foe),"Ordinary missile launch")
	t.eq(before-p.funnel_count,4,"Four missiles per trigger")
	for child in parent.get_children():
		if child is Missile:
			t.near(child.turn_rate,2.1,0.001,"Ordinary missile steering")
	parent.queue_free()
	await host.get_tree().process_frame
