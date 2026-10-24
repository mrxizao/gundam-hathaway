extends RefCounted
const Spec:=preload("res://scripts/data/nu_spec.gd")
static func step(system,seconds:float)->void:
	for i in ceili(seconds*100):system.tick(.01)
static func run(t:T,host:Node)->void:
	t.suite("NuGundam / flight, deployment and repeat F notice")
	Settings.begin_isolated();Game.reset()
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	var stage:=Node3D.new();host.add_child(stage)
	var unit:=PlayerController.new();unit.profile=SuitProfile.nu_gundam();unit.is_player=true;unit.team=0;stage.add_child(unit)
	unit.set_physics_process(false);unit.set_process(false);unit.position=Vector3(0,4000,0);unit.controls_enabled=true
	var foe:=FlightBody.new();foe.profile=SuitProfile.gustav00();foe.team=1;stage.add_child(foe)
	foe.set_physics_process(false);foe.set_process(false);foe.position=unit.position+Vector3(0,0,-3000);foe.ifield_hp=0;foe.hp=10000;foe.max_hp=10000
	var lock:=LockOnSystem.new();stage.add_child(lock);lock.setup(unit);unit.lock=lock;lock.select_target(foe)
	var sys=unit.nu_systems;sys.set_physics_process(false)
	t.ok(unit.assist_on,"normal flight starts assisted")
	t.eq(unit.profile.weapon_slots(),["rifle","saber","bazooka"],"three primary weapons")
	t.eq(SuitProfile.forms_of(unit.profile.id).size(),1,"no transformation")
	t.eq(unit.profile.speed_scale,SuitProfile.gustav00_armed().speed_scale,"Gustav equivalent Earth speed")
	Game.active_map=MapDef.leo()
	t.eq(unit.profile.player_top_speed(),SuitProfile.xi().player_top_speed(),"orbital cruise speed equals Xi")
	t.eq(unit.profile.player_boost_speed(),SuitProfile.xi().player_boost_speed(),"orbital boosted speed equals Xi")
	Game.active_map=null
	t.eq(unit.profile.player_top_speed(),SuitProfile.gustav00_armed().player_top_speed(),"Earth cruise speed equals armed Gustav")
	t.eq(sys.fins.size(),6,"six independent funnels")
	var notices:Array[String]=[];unit.notice.connect(func(s:String,_seconds:float):notices.append(s))
	t.ok(sys.deploy(foe),"F deploys group")
	t.not_ok(sys.deploy(foe),"second F cannot redeploy")
	t.eq(notices.back(),"浮游炮已经发射","exact repeat F notice")
	step(sys,2.1)
	for fin in sys.fins:
		t.ok(fin.deployed and fin.alive,"all six launch")
		t.eq(fin.hp,20.0,"individual health twenty")
	t.eq(sys.state,sys.State.ACTIVE,"deployment ends active")
	t.suite("NuGundam / global three-second sequence and firing hold")
	sys.shot_log.clear();sys.shot_left=0;sys.next_fin=0
	for f in sys.fins:f.cancel_shot()
	step(sys,9.5)
	t.eq(sys.shot_log.size(),4,"one group shot each three seconds")
	for i in 4:t.eq(sys.shot_log[i].index,i,"rotating funnel selection")
	for i in range(1,4):t.near(sys.shot_log[i].time-sys.shot_log[i-1].time,3.0,.025,"group cadence")
	var fin=sys.fins[5];fin.cancel_shot();fin.prepare(foe);var at:Vector3=fin.global_position
	sys.shot_left=100;step(sys,.08)
	t.eq(fin.global_position,at,"pre-fire hold stays still")
	step(sys,.02);t.ok(fin.post_left>0,"post-fire hold starts")
	step(sys,.07);t.eq(fin.global_position,at,"post-fire hold stays still")
	t.suite("NuGundam / volley and energy cooldown")
	sys.cycle_mode();sys.shot_log.clear();sys.energy=100;step(sys,4.3)
	t.eq(sys.shot_log.size(),6,"simultaneous six-beam volley")
	for shot in sys.shot_log:t.near(shot.time,sys.shot_log[0].time,.001,"volley synchronized")
	t.near(sys.energy,78.5,.02,"volley drains five percent per second")
	sys.energy=.01;sys.tick(.01)
	t.eq(sys.state,sys.State.WAITING,"energy loss leaves funnels in air")
	t.near(sys.cooldown_left,25,.001,"ordinary cooldown twenty five seconds")
	var points:Array[Vector3]=[]
	for f in sys.fins:points.append(f.global_position)
	step(sys,24.9);t.eq(sys.energy,0.0,"no gradual energy regeneration")
	for i in 6:t.eq(sys.fins[i].global_position,points[i],"waiting world positions unchanged")
	t.not_ok(sys.deploy(foe),"waiting F remains already launched")
	t.eq(notices.back(),"浮游炮已经发射","waiting repeat F same notice")
	step(sys,.11);t.gt(sys.energy,99.8,"atomic restore at cooldown end")
	t.eq(sys.state,sys.State.ACTIVE,"group resumes outside backpack")
	t.suite("NuGundam / defensive barrier and two destroyed recall")
	sys.cycle_mode();sys.energy=100;step(sys,.5)
	t.ok(sys.barrier_active(),"six fins enclose pilot")
	var hp:=unit.hp
	for kind in Damage.Type.values():unit.take_damage(100,foe,kind)
	t.eq(unit.hp,hp,"all damage types blocked inside barrier")
	sys.shot_log.clear();step(sys,1)
	t.eq(sys.shot_log.size(),0,"defense never attacks")
	t.near(sys.energy,88,.1,"defense drains eight percent per second")
	sys.energy=.01;sys.tick(.01)
	t.near(sys.cooldown_left,33,.001,"defense exhaustion thirty three second cooldown")
	t.not_ok(sys.barrier_active(),"barrier ends immediately on exhaustion")
	step(sys,33.01);sys.mode=sys.Mode.SEQUENCE
	sys.fins[0].take_damage(20,foe);t.eq(sys.destroyed_count,1,"first independent fin destroyed")
	t.eq(sys.state,sys.State.ACTIVE,"one loss does not recall")
	sys.fins[1].take_damage(20,foe);t.eq(sys.state,sys.State.RETURNING,"second loss recalls whole group")
	t.eq(sys.cooldown_left,25.0,"two losses ordinary cooldown")
	step(sys,1.1);t.eq(sys.state,sys.State.COOLDOWN_DOCKED,"return reaches backpack")
	step(sys,23.91);t.eq(sys.state,sys.State.DOCKED,"recall cooldown stays docked")
	for f in sys.fins:t.eq(f.hp,20.0,"all fins restored together")
	t.suite("NuGundam / bazooka reload and precision route")
	sys.energy=100
	for i in 10:t.ok(sys.fire_bazooka(foe),"bazooka fires");step(sys,.81)
	t.eq(sys.bazooka_mag,0,"ten round magazine empties after ten shots")
	t.near(sys.bazooka_reload_left,7.69,.03,"reload starts after last shot")
	t.not_ok(sys.fire_bazooka(foe),"reload blocks firing")
	step(sys,7.7);t.eq(sys.bazooka_mag,10,"reload restores ammunition after eight point five seconds")
	unit.regz_weapons.held=true;t.ok(unit.precision_view_active(),"Nu uses precision camera")
	t.suite("NuGundam / hold G, equipment jettison and network state")
	Input.action_press("flight_assist");unit._tick_assist_toggle(.46);Input.action_release("flight_assist");unit._tick_assist_toggle(.01)
	t.eq(lock.target,null,"hold G drops lock")
	t.ok(unit.assist_on,"unlock does not disable assisted flight")
	Input.action_press("flight_assist");unit._tick_assist_toggle(.46);Input.action_release("flight_assist");unit._tick_assist_toggle(.01)
	t.eq(lock.target,foe,"hold G searches again")
	unit.shield_cooldown=0;unit.raise_shield()
	var guns:=unit.rifle_count
	Input.action_press("reload");unit._tick_holds(.61);Input.action_release("reload");unit._tick_holds(.01)
	t.eq(sys.equipment_cd,15.0,"hold R discards both with fifteen second cooldown")
	t.eq(unit.rifle_count,guns,"jettison retains rifle")
	t.not_ok(unit.shield_up,"discard ends raised shield")
	t.not_ok(unit.raise_shield(),"no shield during equipment cooldown")
	t.not_ok(sys.fire_bazooka(foe),"no bazooka during equipment cooldown")
	t.ok(unit.is_unlockable(),"Xi decoy lock protection active")
	t.not_ok(sys.discard_equipment(),"no repeated jettison during cooldown")
	step(sys,14.99);t.gt(sys.equipment_cd,0,"equipment unavailable before cooldown end")
	step(sys,.02);unit._tick_shield(15.01)
	t.eq(sys.equipment_cd,0.0,"equipment returns after fifteen seconds")
	t.ok(unit.can_raise_shield(),"restored shield usable")
	t.eq(sys.bazooka_mag,10,"restored bazooka usable")
	var proxy:=NetProxyBody.new();proxy.profile=SuitProfile.nu_gundam();proxy.team=1;stage.add_child(proxy);proxy.set_physics_process(false);proxy.set_process(false)
	var packet:=Net.unpack_state(Net.state_dict(unit));proxy.apply_state(packet)
	t.ok(proxy.nu_systems.visual_only,"remote funnels never simulate extra attacks")
	t.eq(proxy.nu_systems.energy,sys.energy,"network transfers shared energy")
	t.eq(proxy.nu_systems.state,sys.state,"network transfers launch/cooldown state")
	for i in 6:t.eq(proxy.nu_systems.fins[i].hp,sys.fins[i].hp,"network transfers individual HP")
	t.ok(load("res://scripts/main.gd").can_instantiate(),"main combat integration compiles")
	proxy.free()
	t.suite("NuGundam / actual beam collision against independent funnel")
	sys.state=sys.State.ACTIVE;sys.mode=sys.Mode.SEQUENCE;sys.energy=100;sys.cooldown_left=0
	for f in sys.fins:f.reset(true)
	var victim=sys.fins[0];victim.reset(false);victim.global_position=unit.position+Vector3(100,0,0)
	await host.get_tree().physics_frame
	var shot:=Projectile.beam(stage,unit.position+Vector3(60,0,0),Vector3.RIGHT,foe,20.0,Color.YELLOW,0,1,5000)
	Game.set_phase(Game.Phase.FIGHT)
	for frame in 8:await host.get_tree().physics_frame
	t.not_ok(victim.alive,"real hostile beam destroys twenty HP funnel")
	t.eq(sys.destroyed_count,1,"funnel collision recorded independently")
	for child in stage.get_children():
		if child is Projectile or child is Missile:child.queue_free()
	await host.get_tree().physics_frame
	victim.reset(false);sys.destroyed_count=0;sys.mode=sys.Mode.SEQUENCE
	foe.position=victim.global_position+Vector3(100,0,0);foe.hp=10000;foe.ifield_hp=0
	victim.global_basis=Basis.looking_at(Vector3.RIGHT,Vector3.UP);victim.selected=foe
	await host.get_tree().physics_frame
	victim.fire()
	for frame in 22:await host.get_tree().physics_frame
	t.eq(foe.hp,9973.0,"real funnel shot passes its own collider and deals twenty seven damage")
	t.eq(victim.hp,20.0,"emitter cannot shoot itself")
	stage.free();clean_audio(host);await host.get_tree().process_frame
	FlightBody.use_placeholder=old;Settings.end_isolated();Game.reset()

static func clean_audio(host:Node)->void:
	for parent in [host,Audio]:
		for child in parent.get_children():
			if (child is AudioStreamPlayer or child is AudioStreamPlayer3D) and child.has_node("AutoFree"):
				child.stop();child.stream=null;child.queue_free()
