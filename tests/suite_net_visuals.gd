extends RefCounted
static func fixture(host: Node) -> Dictionary:
	var old := FlightBody.use_placeholder
	FlightBody.use_placeholder=true
	var stage:=Node3D.new();host.add_child(stage)
	var main=load("res://scripts/main.gd").new()
	main.units_root=Node3D.new();stage.add_child(main.units_root)
	main.projectiles=Node3D.new();stage.add_child(main.projectiles)
	var player:=PlayerController.new();player.profile=SuitProfile.xi();main.units_root.add_child(player)
	player.set_process(false);player.set_physics_process(false);player.is_player=true
	player.position=Vector3(0,1000,500);player.projectile_container=main.projectiles
	main.player=player
	var proxy: NetProxyBody=main._spawn_remote_player(SuitProfile.Id.NEUE_ZIEL,Vector3(0,1000,-500),player.global_position,"Remote",1)
	proxy.set_process(false);proxy.set_physics_process(false)
	for side in ["L","R"]:
		var anchor:=Node3D.new();anchor.name="Mount_WireArm_"+side;proxy.add_child(anchor)
		var arm:=Node3D.new();arm.name="WireArm_"+side;proxy.add_child(arm)
		var tip:=Node3D.new();tip.name="CannonTip";arm.add_child(tip)
	FlightBody.use_placeholder=old
	return {"main":main,"stage":stage,"proxy":proxy,"player":player}
static func run(t: T, host: Node) -> void:
	t.suite("NetVisuals / actual remote weapon creation")
	var f:=fixture(host);var main=f.main;var proxy: NetProxyBody=f.proxy
	t.ok(main.remote_proxy==proxy,"Spawn assigns legacy remote reference")
	# Existing state wiring must not suppress the independent fire connection.
	Net.remote_state.connect(main._on_net_state)
	main._wire_net("test")
	t.ok(Net.remote_fire.is_connected(main._on_net_fire),"Fire connects even when state was already connected")
	var origin:=proxy.global_position+Vector3(0,0,40)
	for kind in ["beam","gun","funnel","missile","bazooka","gp03s_bazookas","cannon","pod","wire"]:
		var before: int=main.projectiles.get_child_count()
		Net.remote_fire.emit(kind,origin,Vector3.BACK)
		t.ok(main.projectiles.get_child_count()>before,kind+" creates a real remote effect")
		for node in main.projectiles.get_children().slice(before):
			node.set_process(false);node.set_physics_process(false)
			if node is Projectile:
				t.ok(node.damage==0.0 and node.visual_only,kind+" is visual-only")
			if node is Missile:
				t.eq(node.damage,0.0,kind+" cannot double damage")
	var rifle: Projectile=main.projectiles.get_child(0)
	t.near(rifle.size_mul,proxy.profile.rifle_scale,0.001,"Remote beam retains suit size")
	t.near(rifle.steady_speed,proxy.profile.rifle_steady_speed,0.001,"Remote beam retains suit speed")
	t.ok(rifle.get_child(0) is MeshInstance3D,"Beam contains a visible mesh")
	var arms=main.projectiles.get_child(main.projectiles.get_child_count()-1)
	var before: int=main.projectiles.get_child_count()
	arms._physics_process(1.1)
	t.eq(main.projectiles.get_child_count()-before,2,"Remote wire arms actually emit both beams")
	for node in main.projectiles.get_children().slice(before):
		node.set_physics_process(false)
		t.ok(node.damage==0.0 and node.visual_only,"Wire beam never damages or intercepts")
	# The authoritative missiles must survive a replica beam passing through them.
	var missile:=Missile.spawn(main.projectiles,origin+Vector3(0,0,10),Vector3.BACK,proxy,f.player,26.0)
	missile.set_physics_process(false)
	rifle.global_position=origin;rifle.direction=Vector3.BACK;rifle.steady_speed=1000.0
	rifle._physics_process(0.05)
	t.not_ok(missile.is_queued_for_deletion(),"Visual beam does not shoot down real missiles")
	var real:=Projectile.beam(main.projectiles,origin,Vector3.BACK,proxy,22.0,Color.WHITE,1000.0,1.0,1000.0)
	t.not_ok(real.visual_only,"Local shots retain gameplay authority")
	real._physics_process(0.05)
	t.ok(missile.is_queued_for_deletion(),"Local beam still intercepts hostile missiles")
	proxy.profile=SuitProfile.regz_custom(1)
	before=main.projectiles.get_child_count()
	Net.remote_fire.emit("regz_battery",origin,Vector3.BACK)
	t.eq(main.projectiles.get_child_count()-before,5,"ReGZ remote event creates five beams")
	for node in main.projectiles.get_children().slice(before):
		t.eq(node.dps,0.0,"ReGZ remote beams cannot double damage")
		t.eq(node.color,Color(1.0,0.83,0.12),"ReGZ remote beam color retained")
	main.remote_proxy=null
	before=main.projectiles.get_child_count();main._on_net_fire("beam",origin,Vector3.BACK)
	t.eq(main.projectiles.get_child_count(),before+1,"Proxy list fallback works if alias is absent")
	main.remote_proxies.clear();Net.squad_bodies["visual_test"]=proxy
	before=main.projectiles.get_child_count();main._on_net_fire("ai|visual_test|beam",origin,Vector3.BACK)
	t.eq(main.projectiles.get_child_count(),before+1,"AI event works without human proxy alias")
	Net.squad_bodies.erase("visual_test")
	before=main.projectiles.get_child_count();main._on_net_fire("beam",origin,Vector3.BACK)
	t.eq(main.projectiles.get_child_count(),before,"Missing shooter exits safely")
	main.free();f.stage.queue_free();await host.get_tree().process_frame
