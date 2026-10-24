extends RefCounted
static func carrier(n:Node)->bool:
	return str(n.name).begins_with("FunnelPart_3_") or str(n.name).begins_with("FunnelPart_9_")
static func run(t:T,host:Node)->void:
	t.suite("Sazabi funnels / six red canisters, two permanent black carriers")
	Settings.begin_isolated();Game.reset()
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=false
	var stage:=Node3D.new();host.add_child(stage)
	var raw:Node3D=load("res://data/sazabi_models/normal.scn").instantiate()
	var original:Dictionary={}
	for i in 6:
		var dock:Node3D=raw.find_child("FunnelDock%d"%i,true,false)
		for part:Node3D in dock.get_children():
			if carrier(part):original[str(part.name)]=dock.transform*part.transform
	raw.free()
	var p:=PlayerController.new();p.profile=SuitProfile.sazabi();p.is_player=true;p.team=0;stage.add_child(p);p.set_physics_process(false)
	var s=p.sazabi_systems;var m=s.motion
	var backpack:Node3D=m.joints.Backpack
	var fixed:Array[Node3D]=[]
	for n:Node3D in backpack.get_children():
		if carrier(n):
			fixed.append(n)
			t.eq(n.transform,original[str(n.name)],"carrier reparent preserves exact original placement")
	t.eq(fixed.size(),6,"six imported carrier slices stay attached, forming the two black packs")
	t.eq(m.docks.size(),6,"six original canister launch positions remain")
	for dock:Node3D in m.docks:
		t.gt(dock.get_child_count(),0,"red canister retains its actual geometry")
		for n in dock.get_children():t.not_ok(carrier(n),"fixed pack excluded from detachable dock")
	FlightBody.use_placeholder=true
	var foe:=FlightBody.new();foe.profile=SuitProfile.xi();foe.team=1;foe.position=Vector3(0,0,-500);stage.add_child(foe);foe.set_physics_process(false)
	s.target=foe;t.ok(s.launch(),"six red canisters deploy")
	t.eq(s.drones.size(),6,"launch makes six independent weapons")
	for drone in s.drones:
		drone.set_physics_process(false)
		t.not_ok(m.docks[drone.slot].visible,"only the launched red canister is hidden on the suit")
		t.gt(drone.visual.get_child_count(),0,"deployed visual has the original red canister meshes")
		for n in drone.visual.get_children():t.not_ok(carrier(n),"no black launch container is duplicated into a projectile")
	for n in fixed:t.ok(n.is_visible_in_tree(),"black carrier stays visible during deployment")
	s.drones[0].take_damage(20,foe)
	await host.get_tree().process_frame
	s.recall();s.step(3.01)
	await host.get_tree().process_frame
	t.not_ok(m.docks[0].visible,"destroyed canister remains absent")
	for i in range(1,6):t.ok(m.docks[i].visible,"surviving canister returns to its own dock")
	for n in fixed:t.ok(n.is_visible_in_tree(),"black carrier stays visible after loss and recall")
	s.repair_left=.01;s.step(.02)
	for dock in m.docks:t.ok(dock.visible,"repair restores all six red canisters")
	for n in fixed:t.eq(n.transform,original[str(n.name)],"repair never moves fixed carrier geometry")
	stage.queue_free();await host.get_tree().process_frame;await host.get_tree().process_frame
	FlightBody.use_placeholder=old;Game.reset();Settings.end_isolated()
