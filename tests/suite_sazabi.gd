extends RefCounted
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset();Game.rifle_metrics_test_mode=true
	var old_placeholder:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	var map_before:=Game.active_map
	var profile:=SuitProfile.sazabi()
	t.suite("Sazabi / roster, controls and environmental speed")
	t.eq(SuitProfile.by_id(SuitProfile.Id.SAZABI).id,SuitProfile.Id.SAZABI,"id resolves to Sazabi")
	t.eq(profile.weapon_slots(),["rifle","sniper","saber","cannon"],"four switchable weapon modes including belly cannon")
	t.eq(SuitProfile.forms_of(profile.id),[0],"no transformation")
	t.not_ok(profile.has_vulcan(),"no vulcan cannon")
	t.not_ok(profile.has_missiles,"funnels are not missile ammunition")
	t.ok(profile.is_ace(),"Sazabi is an ace machine")
	Game.active_map=MapDef.new();Game.active_map.has_ground=true
	t.near(profile.player_top_speed(),SuitProfile.messer_m01().player_top_speed(),.001,"ground speed matches Messer")
	Game.active_map.has_ground=false
	t.near(profile.player_top_speed(),SuitProfile.xi().player_top_speed(),.001,"space speed matches Xi")
	var stage:=Node3D.new();host.add_child(stage)
	var p:=PlayerController.new();p.profile=profile;p.team=0;p.is_player=true;p.position=Vector3(0,5000,0)
	stage.add_child(p);p.set_physics_process(false);p.controls_enabled=true
	var foe:=FlightBody.new();foe.profile=SuitProfile.xi();foe.team=1;foe.position=Vector3(0,5000,-600)
	stage.add_child(foe);foe.set_physics_process(false);foe.ifield_hp=0;foe.ifield_max=0;foe.hp=10000;foe.max_hp=10000
	var lock:=LockOnSystem.new();stage.add_child(lock);lock.setup(p);lock.set_physics_process(false);p.setup_refs(lock,null)
	var s=p.sazabi_systems
	t.ok(p.assist_on,"assisted flight is the default movement mode")
	t.eq(lock.auto_engage_limit,0,"target acquisition remains explicitly commanded")
	Input.action_press("flight_assist");p._tick_assist_toggle(.5);Input.action_release("flight_assist");p._tick_assist_toggle(.01)
	t.eq(lock.target,foe,"holding G acquires a scanned enemy")
	Input.action_press("flight_assist");p._tick_assist_toggle(.5);Input.action_release("flight_assist");p._tick_assist_toggle(.01)
	t.eq(lock.target,null,"holding G again unlocks")
	t.ok(p.assist_on,"G does not turn off the default assisted movement")
	lock.select_target(foe);lock.force_lock()
	t.suite("Sazabi / actual shotgun, sustained sniper and precision view")
	t.ok(s.fire_primary(),"shotgun fires")
	var pellets:=stage.get_children().filter(func(n):return n is Projectile and n.shooter==p)
	t.eq(pellets.size(),12,"shotgun produces twelve real beam projectiles")
	t.eq(s.ammo[0],17,"one shotgun trigger spends one shell")
	t.not_ok(s.fire_primary(),"slow shotgun fire rate is enforced")
	for pellet in pellets:pellet.free()
	Input.action_press("fire_secondary");s.input(.01)
	t.ok(p.precision_view_active(),"shotgun supports the precision camera")
	p.weapon_index=1;s.input(.01)
	t.ok(p.precision_view_active(),"sniper supports the same precision camera")
	Input.action_release("fire_secondary");s.input(.01)
	t.not_ok(p.precision_view_active(),"releasing right button exits precision view")
	s.fire_cd=0;t.ok(s.fire_primary(),"long-distance rifle fires")
	t.ok(is_instance_valid(p.active_cannon),"sniper creates a real sustained beam cannon")
	t.near(p.active_cannon.duration,1.5,.0001,"each sniper beam lasts 1.5 seconds")
	t.eq(s.ammo[1],7,"sniper uses a separate ammunition pool")
	p.active_cannon.queue_free();p.active_cannon=null
	t.suite("Sazabi / six independent funnels, energy, return and repair")
	t.ok(s.launch(),"F launches funnels")
	t.eq(s.drones.size(),6,"all six launch together")
	for drone in s.drones:drone.set_physics_process(false)
	s.step(1);t.near(s.energy,.94,.0001,"sequence consumes 6 percent per second")
	s.toggle_mode();s.step(1);t.near(s.energy,.84,.0001,"volley consumes 10 percent per second")
	t.ok(s.recall(),"second F recalls")
	s.step(2.9);t.eq(s.state,s.State.RETURNING,"return is not instant")
	s.step(.1);t.eq(s.state,s.State.DOCKED,"return finishes within three seconds")
	s.step(1);t.near(s.energy,.89,.0001,"docked charging is 5 percent per second")
	await host.get_tree().process_frame
	s.mode=s.Mode.SEQUENCE;s.energy=1;s.launch()
	for drone in s.drones:drone.set_physics_process(false)
	var d=s.drones[0];d.global_position=foe.global_position+Vector3(500,150,0);d.age=d.next_shot-.05
	d.step(.001);var frozen:Vector3=d.global_position
	d.step(.049);t.eq(d.fired_count,0,"each funnel pauses before firing")
	d.step(.002);t.eq(d.fired_count,1,"funnel fires after its 0.05 second pause")
	t.eq(d.global_position,frozen,"firing pause stays fixed in world space")
	t.near(d.next_shot-d.age,3,.001,"each funnel repeats at three-second intervals")
	d.step(.09);t.eq(d.global_position,frozen,"post-shot pause lasts 0.1 seconds")
	d.step(.011);d.step(.1);t.gt(d.global_position.distance_to(frozen),.1,"funnel resumes orbit after firing")
	s.toggle_mode();var counts:Array=[]
	for drone in s.drones:counts.append(drone.fired_count)
	s.step(3.7);s.step(.049)
	for i in 6:t.eq(s.drones[i].fired_count,counts[i],"volley waits through its firing preparation")
	s.step(.002)
	for i in 6:t.eq(s.drones[i].fired_count,counts[i]+1,"six funnels fire simultaneously")
	d=s.drones[0];d.take_damage(19,foe)
	t.near(d.hp,1,.001,"each funnel has its own 20 HP")
	d.take_damage(1,p);t.near(d.hp,1,.001,"friendly damage cannot destroy a funnel")
	d.take_damage(1,foe);s.drones[1].take_damage(20,foe)
	t.eq(s.lost.size(),2,"two independent funnel losses recorded")
	t.eq(s.state,s.State.RETURNING,"two losses recall the whole fleet")
	t.near(s.repair_left,20,.001,"two losses start a 20-second cooldown")
	t.not_ok(s.toggle(),"cannot redeploy during repair")
	s.step(3);s.step(17);await host.get_tree().process_frame
	t.eq(s.lost.size(),0,"cooldown restores all six funnel slots")
	t.ok(s.launch(),"restored fleet can deploy again")
	t.eq(s.drones.size(),6,"all six return after repair")
	for drone in s.drones:drone.set_physics_process(false)
	s.energy=.001;s.step(.1);t.eq(s.state,s.State.RETURNING,"empty energy automatically recalls")
	s.step(3);await host.get_tree().process_frame
	t.suite("Sazabi / axe damage, impact stun and actual thrown hit")
	for projectile in stage.get_children():
		if projectile is Projectile:projectile.free()
	p.weapon_index=2;p.saber_cooldown=0;foe.melee_guard.impact_left=0;foe._stagger_timer=0
	foe.hp=10000;s.axe_swing=false;p._slash(foe);var sword_damage:float=10000-foe.hp
	foe.hp=10000;foe.melee_guard.impact_left=0;foe._stagger_timer=0;s.axe_swing=true;p._slash(foe)
	t.near(10000-foe.hp,sword_damage*3,.001,"axe swing deals three times sword damage")
	t.near(foe.melee_guard.impact_left,6.5,.001,"axe swing causes 6.5 seconds of impact stun")
	t.near(foe._stagger_timer,6.5,.001,"weapon and movement recovery use the same stun duration")
	s.axe_cd=0;p.saber_cooldown=0;p._end_saber();foe.hp=10000;foe.melee_guard.impact_left=0;foe._stagger_timer=0
	await host.get_tree().physics_frame;await host.get_tree().physics_frame
	t.ok(s.axe_attack(true),"long right-button route throws an axe")
	var thrown=stage.get_children().filter(func(n):return n.get_script()==preload("res://scripts/combat/sazabi_axe.gd"))[0]
	thrown.set_physics_process(false)
	for i in 12:
		if not thrown.is_queued_for_deletion():thrown._physics_process(1.0/60.0)
	t.near(10000-foe.hp,sword_damage*3,.001,"thrown axe hits through actual physics ray and deals triple sword damage")
	t.near(foe.melee_guard.impact_left,6.5,.001,"thrown axe applies the same 6.5 second stun")
	stage.queue_free();await host.get_tree().process_frame
	Game.reset();Game.active_map=map_before;FlightBody.use_placeholder=old_placeholder;Settings.end_isolated()
