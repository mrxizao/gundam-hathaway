extends RefCounted
## GP03D integration: real asset, physical size, mounts, weapons, audio and menu.
static func run(t: T, host: Node) -> void:
	t.suite("GP03D / 数据与实机")
	var profile := SuitProfile.by_id(SuitProfile.Id.GP03D)
	t.eq(profile.id_name(),"GP03D","Dispatch preserves new identity")
	t.ok(profile.is_ace() and not profile.can_ride_pedal(),"MA occupies ACE slot")
	t.ok(not BattleFormation.federation().all_suits().has(profile.id),"Excluded from Federation squad roster")
	t.ok(not BattleFormation.belongs_to(BattleFormation.Side.MAFTY,profile.id),"No cross faction")
	t.ok(MainMenu.SUITS.has(profile.id) and MainMenu.ENEMY_SUITS.has(profile.id),"Both menu pools")
	t.eq(SuitProfile.forms_of(profile.id),[0,1] as Array[int],"GP03D with escape-only GP03S form")
	t.ok(profile.features().size()>=3,"Suit-specific help")
	var c := Node3D.new()
	host.add_child(c)
	var p := PlayerController.new()
	p.profile=profile
	p.team=0
	p.is_player=true
	c.add_child(p)
	p.set_physics_process(false)
	p.set_process(false)

	t.near(p.fm.pitch_rate,FlightModel.PITCH_RATE_BASE*.48,.0001,"GP03D turn response heavier")
	t.ok(not PlayerController.assist_uses_translation(profile),"GP03D uses Arizeus cruise flight controls")
	t.ok(not profile.has_dash_limit(),"Cruise super boost has no dodge gauge")
	p.assist_on=true
	p.translate_mode=PlayerController.assist_uses_translation(profile)
	Input.action_press("boost")
	p._read_flight_input(1.0/60.0)
	p._tick_assist(1.0/60.0)
	t.ok(p.fm.super_boost and p.fm.boosting,"Shift engages super boost in assisted cruise")
	t.ok(p.super_dashing(),"Super boost drives exhaust and camera feedback")
	t.near(p.fm.max_reachable_speed(),profile.player_boost_speed()*FlightModel.SUPER_BOOST_MULT,0.01,"Same 1.35x super boost tier as Arizeus cruise")
	Input.action_release("boost")
	p._read_flight_input(1.0/60.0)
	p._tick_assist(1.0/60.0)
	t.ok(not p.fm.super_boost and p.fm.boosting,"Release Shift returns to normal assisted afterburner")
	p.fm.super_boost=true
	p.assist_on=false
	p._tick_assist(1.0/60.0)
	t.ok(not p.fm.super_boost,"Disabling assist clears super boost")
	t.ok(p.model_bounds.size.distance_to(Vector3(62,38.5,140))<0.05,"62 x 38.5 x 140 metres")
	t.eq(p._muzzle_local.size(),1,"One forward MEGA muzzle")
	var muzzle := p.rig_anchor("muzzle_L")
	t.ok(muzzle.x>10 and muzzle.z < -69,"Right-side cannon tip")
	t.eq(p._plume_fx.size(),6,"Six aft nozzles")
	for item: Dictionary in p._plume_fx:
		t.ok(item.fx.position.z>35,"Exhaust stays behind hull")
	t.ok(p._engine.stream==Audio._stream("cruise_xi",true),"Exact Xi looping engine stream")
	t.ok(p._detect_player!=null and p._detect_player.stream==Audio.get_stream_for("xi_detect"),"Xi detection beep")
	t.ok(p.get_node("Hull").shape is BoxShape3D,"Broad MA hull")
	t.ok(p.has_node("CannonHull"),"Separate narrow cannon collider")
	p._rebuild_collision()
	t.ok(p.has_node("CannonHull") and not p.has_node("CannonHull2"),"Rebuild replaces both shapes")
	var cam := ChaseCamera.new()
	cam.target=p
	c.add_child(cam)
	cam.set_physics_process(false)
	var at := cam._desired_position()
	t.ok(at.z>=120 and at.z<165 and at.y>=30,"Chase camera clears large body")
	cam._fpv_blend=1.0
	t.ok(cam._desired_position().distance_to(p.rig_anchor("head"))<2,"Cockpit eye uses model mount")
	var foe := FlightBody.new()
	foe.team=1
	foe.profile=SuitProfile.gustav00()
	c.add_child(foe)
	foe.position=Vector3(14,3,-1400)
	foe.set_physics_process(false)
	foe.set_process(false)
	await host.get_tree().physics_frame
	t.ok(not profile.cannon_only,"Normal rifle mode restored")
	t.ok(p.fire_beam(true,foe),"Normal rifle shot")
	t.ok(not is_instance_valid(p.active_cannon),"Rifle does not automatically fire cannon")
	if is_instance_valid(p.active_cannon): p.active_cannon.free()
	p.cannon_cd_left=0.0
	p.rifle_reloading=false
	p.reload_timer=0.0
	p.rifle_mag=1
	t.ok(p.cannon_ready(),"Partial rifle magazine permits cannon")
	p.rifle_reloading=true
	p.reload_timer=1.0
	t.ok(p.cannon_ready(),"Rifle reload does not block independent cannon")
	p.rifle_reloading=false
	t.ok(p.fire_cannon(foe),"Charged MEGA beam")
	t.ok(p.active_cannon!=null,"Live cannon")
	t.eq(p.rifle_mag,1,"Cannon preserves partial rifle magazine")
	t.ok(not p.rifle_reloading,"Cannon does not force rifle reload")
	if p.active_cannon!=null:
		t.ok(p.active_cannon.global_position.distance_to(p.to_global(muzzle))<0.01,"Beam starts at cannon mesh tip")
		t.eq(p.active_cannon.offsets.size(),1,"No false second barrel")
	t.ok(not p.cannon_ready(),"Cannon respects cooldown")
	var rounds := p.funnel_count
	t.ok(p.fire_funnel(foe),"Missile pod trigger")
	t.eq(rounds-p.funnel_count,profile.funnel_per_shot,"Per-shot missile count")
	t.eq(profile.funnel_count,16*3*36,"Sixteen pods of 108 missiles")
	t.eq(profile.funnel_per_shot,108,"One pod per trigger")
	t.eq(p.funnel_reload_left,10.0,"First pod starts 10 second recharge")
	var wave = p.projectile_container.get_child(p.projectile_container.get_child_count()-1)
	t.eq(wave.pods.size(),1,"One physical triangular pod")
	t.eq(wave.emitted,0,"No missiles before pod deployment")
	wave.set_physics_process(false)
	for tick in 75:
		wave._step(1.0/30.0)
	t.eq(wave.emitted,108,"Three faces release 36 missiles each")
	t.ok(wave.TURN_RATE<Missile.FUNNEL_TURN_RATE,"Ordinary missile steering weaker than funnels")
	t.ok(wave.LEAD<0.7,"Less target lead than funnels")
	t.eq(wave.bodies.instance_count,108,"Every missile has a batched visual")
	t.ok(wave.get_child_count()<5,"No per-missile scene nodes")
	t.eq(wave.smoke_amount()*2,FX.TRAIL_HIGH_AMOUNT,"GP03D smoke quantity is exactly half Xi")
	t.eq(wave.smoke.instance_count,108*wave.smoke_amount(),"Every missile gets its half-density smoke")
	t.ok(wave.smoke_texture!=null and wave.smoke_material!=null,"Batched smoke resources exist")
	t.ok(wave.smoke_image.get_pixel(0,0).a>0,"Smoke follows simulated missile positions")

	p.funnel_cooldown=0
	t.ok(p.fire_full_salvo(foe),"Unused pod fires during another pod recharge")
	t.eq(p.funnel_count,14*108,"Two pods consumed")
	t.eq(p.funnel_reload_left,10.0,"Second pod does not reset first timer")
	t.eq(p._full_salvo_left,0,"No legacy 100-funnel queue")
	p._tick_weapons(9.9)
	t.eq(p.funnel_count,14*108,"No early recharge")
	p._tick_weapons(0.2)
	t.eq(p.funnel_count,15*108,"Only first pod restored after ten seconds")
	t.ok(p.funnel_reload_left>9.8,"Second pod begins its own countdown")
	p._tick_weapons(10.0)
	t.eq(p.funnel_count,16*108,"Second pod restored after twenty seconds")
	t.eq(p.funnel_reload_left,0.0,"Full inventory stops recharge")
	foe.position=Vector3(0,10000,0)
	wave.positions[0]=foe.global_position+Vector3(0,0,20)
	wave.directions[0]=Vector3.FORWARD
	wave.ages[0]=0.5
	var enemy_field := foe.hp+foe.ifield_hp
	wave._step(1.0/30.0)
	t.ok(foe.hp+foe.ifield_hp<enemy_field,"Batched missile deals real combat damage")
	t.eq(wave.ages[0],-2.0,"Hit missile retires exactly once")

	p.funnel_count=0
	p._funnel_check_reload()
	p._tick_weapons(159.9)
	t.eq(p.funnel_count,15*108,"Sixteen empty pods recharge sequentially")
	p._tick_weapons(0.2)
	t.eq(p.funnel_count,16*108,"160 seconds restores all sixteen pods")
	p._show_blade()
	t.not_ok(p._blade_anchor.has_node("SecondClawSaber"),"Only one claw saber")
	t.ok(p._blade_anchor.position.distance_to(p.rig_anchor("hand_L"))<0.01,"First claw mount")
	t.eq(p._blade.scale,Vector3(5,5,1),"Blade diameter increases 400 percent; length unchanged")
	p._hide_blade()
	var hp := p.hp
	var field := p.ifield_hp
	p.take_damage(10,foe,Damage.Type.BEAM)
	t.eq(p.hp,hp,"Intact I-field protects hull")
	t.ok(p.ifield_hp<field,"I-field consumes incoming beam damage")
	t.ok(ResourceLoader.exists("res://assets/models/gp03d/state.res"),"M-page own artwork")
	var observer := PlayerController.new()
	observer.profile=SuitProfile.xi()
	observer.use_placeholder=true
	c.add_child(observer)
	observer.set_physics_process(false)
	observer.set_process(false)
	observer.position=foe.position
	var hud := FlightHUD.new()
	hud.player=observer
	hud.camera=cam
	c.add_child(hud)
	hud.set_process(false)
	hud._aim_magnifier_at(p)
	t.ok(hud._mag_cam.global_position.distance_to(p.global_position)>1400,"Magnifier fits 140 m target")
	t.ok(hud._mag_cam.global_position.direction_to(p.global_position).dot(-hud._mag_cam.global_basis.z)>0.999,"Magnifier still points at target")
	t.ok(hud._mag_cam.cull_mask==1<<19,"Focused rendering budget unchanged")
	# Independent bazooka magazine, cadence and reload.
	p.bazooka_mag=16
	p.bazooka_cd=0.0
	p.bazooka_reload_left=0.0
	var pods_before := p.funnel_count
	var rifle_before := p.rifle_mag
	var cannon_before := p.cannon_cd_left
	var rockets_before := c.get_child_count()
	t.ok(p.fire_gun(true, foe), "Gun key fires GP03 bazooka")
	t.eq(c.get_child_count(), rockets_before+1, "Bazooka emits exactly one normal missile")
	t.eq(p.bazooka_mag, 15, "Bazooka consumes own ammunition")
	t.eq(p.funnel_count, pods_before, "Bazooka preserves pod stock")
	t.eq(p.rifle_mag, rifle_before, "Bazooka preserves rifle stock")
	t.eq(p.cannon_cd_left, cannon_before, "Bazooka preserves cannon cooldown")
	t.ok(not p.fire_gun(true, foe), "Bazooka shot cadence enforced")
	p._tick_weapons(0.35)
	t.ok(p.fire_gun(true, foe), "Next rocket after 0.35 seconds")
	p.bazooka_mag=1
	p.bazooka_cd=0.0
	t.ok(p.fire_gun(true, foe), "Last rocket fires")
	t.near(p.bazooka_reload_left,12.0,0.001,"Independent twelve-second reload starts")
	t.ok(not p.fire_gun(true, foe), "Cannot shoot while loading")
	p._tick_weapons(11.9)
	t.eq(p.bazooka_mag,0,"No early refill")
	p._tick_weapons(0.11)
	t.eq(p.bazooka_mag,16,"Sixteen-round refill")
	# Grapple range, movement attachment, retained gun access and cleanup.
	t.ok(profile.weapon_slots().has("ram"), "Active ram selectable")
	p.global_position=Vector3.ZERO
	foe.global_position=Vector3(0,0,-1301)
	t.ok(not p.try_gp03_grapple(foe), "Grapple cannot magnet beyond 1.3km")
	foe.global_position=Vector3(0,0,-1300)
	t.ok(p.try_gp03_grapple(foe), "Grapple accepts 1.3km boundary")
	var grab := p.active_grapple
	grab.set_physics_process(false)
	t.ok(foe.gp03_grab_owner == grab, "Target movement owned by grapple")
	t.ok(not foe.try_saber(p), "Held target cannot melee")
	foe.projectile_container=c
	foe.rifle_mag=foe.profile.rifle_magazine
	foe.rifle_count=1
	foe.rifle_cooldown=0.0
	foe.rifle_reloading=false
	t.ok(foe.fire_beam(true,p), "Held target can still shoot")
	grab._physics_process(0.35)
	var hold_point: Vector3 = p.global_transform*p.cannon_muzzles()[0]+p.forward()*8.0
	t.ok(foe.global_position.distance_to(hold_point)<0.01, "Target held at actual cannon muzzle")
	p.cannon_cd_left=0.0
	p.weapon_index=profile.weapon_slots().find("ram")
	t.ok(p.grapple_charge_route(), "Grapple slot routes directly into cannon charge")
	Input.action_press("fire_primary")
	p._read_weapon_input(0.01)
	t.ok(p.cannon_cd_left>0.0, "Successful ram fires cannon immediately without charge")
	t.ok(not p._cannon_charging, "Successful ram never enters charge state")
	t.eq(p.current_slot(),"ram","Grapple slot preserved during immediate cannon fire")
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	Input.action_release("fire_primary")
	p._read_weapon_input(0.01)
	t.ok(p.cannon_cd_left>0.0, "Cannon cooldown retained after trigger release")
	t.ok(not p._cannon_charging, "Release clears charge state")
	grab._physics_process(3.9)
	t.ok(not grab.is_queued_for_deletion(), "Hold lasts four full seconds after impact")
	grab._physics_process(0.11)
	t.ok(grab.is_queued_for_deletion(), "Hold releases after four seconds")
	await host.get_tree().process_frame
	t.ok(not is_instance_valid(foe.gp03_grab_owner), "Release clears target movement/melee lock")
	c.free()
	await host.get_tree().process_frame
