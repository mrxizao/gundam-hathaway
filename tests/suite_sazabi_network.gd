extends RefCounted
const Router=preload("res://scripts/combat/sazabi_network.gd")
class MatchScene extends Node3D:
	var player:PlayerController
	func projectile_container()->Node3D:return self
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset();Game.rifle_metrics_test_mode=true
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	var stage:=MatchScene.new();host.add_child(stage)
	var p:=PlayerController.new();p.profile=SuitProfile.sazabi();p.is_player=true;p.team=0;p.position=Vector3(0,5000,0);stage.player=p;stage.add_child(p);p.set_physics_process(false)
	var remote:=NetProxyBody.new();remote.profile=SuitProfile.sazabi();remote.team=1;remote.position=p.position+Vector3(0,0,-1000);stage.add_child(remote);remote.set_physics_process(false)
	var lock:=LockOnSystem.new();stage.add_child(lock);lock.setup(p);lock.set_physics_process(false);lock.select_target(remote);p.setup_refs(lock,null)
	t.suite("Sazabi / authoritative remote funnel events and zero-damage visuals")
	var s=remote.sazabi_systems
	t.ok(s.visual_only,"network proxy has presentation-only systems")
	Router.receive(stage,remote,"sazabi_launch",Vector3.ZERO,Vector3.FORWARD)
	t.eq(s.drones.size(),6,"remote deploy event recreates all six funnels")
	for drone in s.drones:drone.set_physics_process(false)
	var before:=stage.get_child_count();s.drones[0].fire()
	t.eq(stage.get_child_count(),before,"remote funnel does not create an extra damaging projectile")
	Router.receive(stage,remote,"sazabi_mode_1",Vector3.ZERO,Vector3.FORWARD)
	t.eq(s.mode,s.Mode.VOLLEY,"remote mode event is applied")
	Router.receive(stage,remote,"sazabi_slot_sniper",Vector3.ZERO,Vector3.FORWARD)
	t.eq(s.slot(),"sniper","remote weapon change selects the proper held gun")
	Router.receive(stage,remote,"sazabi_sniper",remote.position,Vector3.FORWARD)
	t.near(remote.active_cannon.dps,0,.001,"remote sustained beam has zero authority damage")
	t.near(remote.active_cannon.duration,1.5,.001,"remote sniper keeps its 1.5-second duration")
	remote.active_cannon.queue_free();remote.active_cannon=null
	Router.receive(stage,remote,"sazabi_throw",remote.position,Vector3.FORWARD)
	var axes:=stage.get_children().filter(func(n):return n.get_script()==preload("res://scripts/combat/sazabi_axe.gd"))
	t.eq(axes.size(),1,"remote throwing event recreates the axe")
	t.ok(axes[0].visual_only,"remote axe cannot apply damage twice")
	var own=p.sazabi_systems;own.launch()
	for drone in own.drones:drone.set_physics_process(false)
	Router.receive(stage,remote,"sazabi_damage:player:0:19",Vector3.ZERO,Vector3.FORWARD)
	t.near(own.drones[0].hp,1,.001,"reported funnel damage is applied by its owning peer")
	Router.receive(stage,remote,"sazabi_damage:player:0:1",Vector3.ZERO,Vector3.FORWARD)
	t.ok(own.lost.has(0),"owner records the destroyed slot")
	Router.receive(stage,remote,"sazabi_lost_0",Vector3.ZERO,Vector3.FORWARD)
	t.ok(s.lost.has(0),"destroyed slot is mirrored to the remote backpack")
	Router.receive(stage,remote,"sazabi_recall",Vector3.ZERO,Vector3.FORWARD)
	t.eq(s.state,s.State.RETURNING,"remote recall begins the same three-second return")
	p.shield_up=true;Router.receive(stage,remote,"sazabi_stun:player",Vector3.ZERO,Vector3.FORWARD)
	t.near(p._stagger_timer,0,.001,"raised shield blocks remote axe stun")
	p.shield_up=false;Router.receive(stage,remote,"sazabi_stun:player",Vector3.ZERO,Vector3.FORWARD)
	t.near(p._stagger_timer,6.5,.001,"landed remote axe applies its 6.5-second stun")
	stage.queue_free();await host.get_tree().process_frame;await host.get_tree().process_frame
	Game.reset();FlightBody.use_placeholder=old;Settings.end_isolated()
