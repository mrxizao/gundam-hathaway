extends RefCounted
static func run(t:T,host:Node)->void:
	Settings.begin_isolated()
	var previous:=FlightBody.use_placeholder;FlightBody.use_placeholder=false
	var stage:=Node3D.new();host.add_child(stage)
	t.suite("Weapon origins / visible platform riders")
	for p in [SuitProfile.odysseus(),SuitProfile.messer_m01(),SuitProfile.gustav00_armed()]:
		print("MOUNT begin ",p.display_name)
		var u:=PlayerController.new();u.profile=p;u.projectile_container=stage;stage.add_child(u);u.set_physics_process(false);u.position=Vector3(0,3000,0)
		print("MOUNT built")
		t.ok(u.mount_pedal(),"platform summon: "+p.display_name)
		var board:FlightPedal=u._inbound_pedal
		print("MOUNT summoned")
		board._arrive();board.set_physics_process(false)
		print("MOUNT arrived")
		var rifle:=u._rifle_muzzle_local(0);var head:=u._vulcan_muzzle_local(0)
		print("VISIBLE RIFLE ",u._weapon_emitters.mounted_rifle.name if is_instance_valid(u._weapon_emitters.mounted_rifle) else "NONE")
		t.ok(is_instance_valid(u._weapon_emitters.mounted_rifle),"uses visible baked rifle: "+p.display_name)
		t.ok(is_instance_valid(u._weapon_emitters.mounted_head),"uses visible baked head: "+p.display_name)
		var previous_transform:=board.global_transform
		board.rotate_y(.4)
		var xf:=u.global_transform.affine_inverse()*board.global_transform*previous_transform.affine_inverse()*u.global_transform
		t.near(u._rifle_muzzle_local(0).distance_to(xf*rifle),0,.03,"platform rifle follows visible model")
		t.near(u._vulcan_muzzle_local(0).distance_to(xf*head),0,.03,"platform head follows visible model")
		u.free();await host.get_tree().process_frame
	stage.free();FlightBody.use_placeholder=previous;Settings.end_isolated()
