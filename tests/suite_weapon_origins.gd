extends RefCounted
static func run(t:T,host:Node)->void:
	Settings.begin_isolated()
	var previous:=FlightBody.use_placeholder
	FlightBody.use_placeholder=false
	var stage:=Node3D.new();host.add_child(stage)
	for p in [SuitProfile.xi(),SuitProfile.xi_final(),SuitProfile.penelope(),SuitProfile.odysseus(),SuitProfile.arizeus(0),SuitProfile.arizeus(1),SuitProfile.arizeus(2),SuitProfile.gustav00_armed(),SuitProfile.messer_m01(),SuitProfile.messer_cmd(),SuitProfile.messer_f01(),SuitProfile.gp03s(),SuitProfile.regz_custom(0),SuitProfile.regz_custom(1)]:
		t.suite("Weapon origins / "+p.display_name+str(p.form))
		var u:=FlightBody.new();u.profile=p;u.projectile_container=stage;stage.add_child(u)
		u.set_physics_process(false);u.global_position=Vector3(0,3000,0)
		if u.model_anim!=null and u.model_anim.ready:u.model_anim.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var rifle:=u._rifle_muzzle_local(0)
		var head:=u._vulcan_muzzle_local(0)
		print("PORT ",p.display_name," / ",p.form," rifle=",rifle," head=",head," head geometry=",u._weapon_emitters.head_box)
		t.ok(rifle.is_finite() and head.is_finite(),"finite physical emitters")
		t.ok(head.distance_to(rifle)>1.0,"head cannon independent of rifle")
		t.ok(u._weapon_emitters.head_box.grow(.01).has_point(head),"head cannon sits on physical head bounds")
		if p.id==SuitProfile.Id.PENELOPE and p.form==0:
			t.ok(str(u._model_skel.get_bone_name(u._weapon_emitters.head_bone))=="Movie_tripo_part_50","vulcan attached to MS helmet rather than flight nose")
		var turn:=Basis(Vector3.UP,.7)
		u.spin_pivot.basis=turn
		if u._model_skel!=null:u._model_skel.force_update_all_bone_transforms()
		t.near(u._rifle_muzzle_local(0).distance_to(turn*rifle),0,.03,"rifle follows visible spin")
		t.near(u._vulcan_muzzle_local(0).distance_to(turn*head),0,.03,"head cannon follows visible spin")
		u._fire_vulcan_round()
		for child in stage.get_children():
			if child is Projectile:
				t.near(child.global_position.distance_to(u.to_global(u._vulcan_muzzle_local(1))),0,.01,"actual vulcan spawns at head")
				child.free()
		u.free();await host.get_tree().process_frame
	for beam in [true,false]:
		var shot:=Projectile.beam(stage,Vector3(0,3000,0),Vector3.FORWARD,null,46,Color.WHITE,3000,3.2) if beam else Projectile.vulcan(stage,Vector3(0,3000,0),Vector3.FORWARD,null)
		shot.set_physics_process(false)
		t.ok(not shot._tracer.visible,"no backwards streak at spawn")
		for distance in [2.0,20.0,200.0]:
			shot.travelled=distance;shot._sync_tracer()
			var mesh_box:=shot._tracer.transform*shot._tracer.mesh.get_aabb()
			t.ok(mesh_box.end.z<=distance+.001,"visible tail never extends behind original muzzle")
			t.near(mesh_box.position.z,0,.001,"visual front remains collision tip")
		shot.free()
	stage.free();FlightBody.use_placeholder=previous
	Settings.end_isolated()
