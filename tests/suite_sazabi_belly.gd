extends RefCounted
const Router=preload("res://scripts/combat/sazabi_network.gd")
class MatchScene extends Node3D:
	var player:PlayerController
	func projectile_container()->Node3D:return self
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset();Game.rifle_metrics_test_mode=true
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	var stage:=MatchScene.new();host.add_child(stage)
	var p:=PlayerController.new();p.profile=SuitProfile.sazabi();p.is_player=true;p.team=0;p.position=Vector3(0,5000,0);stage.player=p;stage.add_child(p);p.set_physics_process(false);p.controls_enabled=true
	var foe:=FlightBody.new();foe.profile=SuitProfile.xi();foe.team=1;foe.position=p.position+Vector3(0,3.4,-600);stage.add_child(foe);foe.set_physics_process(false);foe.hp=10000;foe.max_hp=10000;foe.ifield_hp=0;foe.ifield_max=0
	var lock:=LockOnSystem.new();stage.add_child(lock);lock.setup(p);lock.select_target(foe);lock.set_physics_process(false);p.setup_refs(lock,null)
	var s=p.sazabi_systems
	t.suite("Sazabi belly / native hold-release weapon and independent cooldown")
	t.ok(p.cannon_available(),"Sazabi has its abdominal cannon")
	t.eq(p.profile.weapon_slots(),["rifle","sniper","saber","cannon"],"belly cannon has a dedicated switchable slot")
	t.ok(p.profile.cannon_color().r>.99 and p.profile.cannon_color().g>.8 and p.profile.cannon_color().b<.1,"abdominal beam is yellow")
	t.ok(p.profile.beam_color().g>.9 and p.profile.beam_color().r<.8,"rifle and sniper beams remain green")
	t.not_ok(p.rifle_press_route(),"ordinary rifle press does not start belly charging")
	p.weapon_index=3
	t.eq(p.weapon_name(),"腹部蓄力炮","weapon label identifies belly cannon")
	p.rifle_mag=1;p.rifle_reloading=true;t.ok(p.cannon_ready(),"belly cannon is independent of gun ammunition and reloads");p.rifle_reloading=false
	await host.get_tree().process_frame
	Input.action_press("fire_primary");s.input(.2)
	await host.get_tree().process_frame
	Input.action_release("fire_primary");s.input(.01)
	t.not_ok(is_instance_valid(p.active_cannon),"short press cannot fire an uncharged cannon")
	t.eq(s.ammo,[18,8],"uncharged press cannot spend shotgun or sniper ammunition")
	await host.get_tree().process_frame
	Input.action_press("fire_primary");s.input(1.69)
	t.not_ok(p.cannon_charging(),"charge waits until the native 1.7-second threshold")
	await host.get_tree().process_frame
	s.input(.02);t.ok(p.cannon_charging(),"holding beyond 1.7 seconds completes charge")
	t.eq(s.cannon_status(),"松手发射","HUD confirms release to fire")
	Input.action_release("fire_primary");s.input(.01)
	var beam=p.active_cannon
	t.ok(is_instance_valid(beam),"releasing charged trigger launches the real beam")
	if is_instance_valid(beam):
		beam.set_physics_process(false)
		t.ok(beam.sazabi_belly,"beam tracks abdominal emitter instead of the rifle")
		t.eq(beam.color,p.profile.cannon_color(),"real beam uses the yellow cannon color")
		t.near(beam.duration,4,.001,"native cannon irradiates for four seconds")
		t.near(p.cannon_cd_left,20,.001,"firing starts the native 20-second cooldown")
		t.not_ok(p.rifle_reloading,"belly firing does not overheat the independent guns")
		t.eq(s.ammo,[18,8],"belly firing does not consume either gun magazine")
		var origin:Vector3=p.global_transform*p.cannon_muzzles()[0]
		t.lt(beam.global_position.distance_to(origin),.001,"beam begins at the abdominal port")
		p.set_aim_direction(Vector3(0,.2,-1).normalized())
		t.gt(beam._aim_dir(origin).dot(p.aim_forward()),.9999,"belly beam follows the cannon cursor")
		var hp:float=foe.hp;beam._apply_damage(origin,foe.global_position+Vector3(0,0,-100),.1)
		t.lt(foe.hp,hp,"abdominal beam actually damages a hostile on its ray")
		t.not_ok(p.fire_cannon(foe),"cooldown prevents repeated cannon shots")
		Input.action_press("switch_weapon");s.input(.01);Input.action_release("switch_weapon")
		t.eq(p.current_slot(),"rifle","switch cycles from belly cannon back to shotgun")
		t.ok(beam.is_queued_for_deletion(),"switching away ends active abdominal irradiation")
	p.cannon_cd_left=0;p.weapon_index=3
	await host.get_tree().process_frame
	Input.action_press("fire_primary");s.input(1.8)
	t.ok(p.cannon_charging(),"another charge can begin after cooldown")
	Input.action_press("switch_weapon");s.input(.01);Input.action_release("switch_weapon");Input.action_release("fire_primary")
	t.not_ok(p.cannon_charging(),"switching cancels a pending charge")
	t.near(p.cannon_hold_ratio(),0,.001,"canceled charge clears HUD progress")
	t.suite("Sazabi belly / remote yellow beam keeps zero damage authority")
	var proxy:=NetProxyBody.new();proxy.profile=SuitProfile.sazabi();proxy.team=1;proxy.position=foe.position;stage.add_child(proxy);proxy.set_physics_process(false)
	Router.receive(stage,proxy,"sazabi_slot_cannon",Vector3.ZERO,Vector3.FORWARD)
	t.eq(proxy.sazabi_systems.slot(),"cannon","remote weapon selection supports belly slot")
	Router.receive(stage,proxy,"sazabi_belly",proxy.position,Vector3.FORWARD)
	t.ok(proxy.active_cannon.sazabi_belly,"remote cannon also tracks the abdominal emitter")
	t.eq(proxy.active_cannon.color,p.profile.cannon_color(),"remote beam has the same yellow color")
	t.near(proxy.active_cannon.dps,0,.001,"remote visual does not apply double damage")
	stage.queue_free();await host.get_tree().process_frame;await host.get_tree().process_frame
	FlightBody.use_placeholder=old;Game.reset();Settings.end_isolated()
