extends RefCounted
static func frames(host:Node)->void:
	for i in 3:await host.get_tree().process_frame
static func run(t:T,host:Node)->void:
	t.suite("NuGundam / supplied model, mounts and weapon pose")
	Settings.begin_isolated();Settings.first_person=false;Game.reset()
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=false
	var stage:=Node3D.new();host.add_child(stage)
	var unit:=PlayerController.new();unit.profile=SuitProfile.nu_gundam();unit.team=0;unit.is_player=true;unit.controls_enabled=true;stage.add_child(unit)
	unit.set_process(false);unit.set_physics_process(false);unit.nu_systems.set_physics_process(false);unit.position=Vector3(0,4000,0)
	var sk:=unit._model_skel
	t.ok(sk!=null,"new model has working skeleton")
	t.eq(sk.get_bone_count(),48,"all mechanical bindings loaded")
	t.eq(unit.model_root.find_children("NuDock*_*","MeshInstance3D",true,false).size(),38,"six authored funnel groups preserved")
	for i in 6:t.ok(unit.model_root.find_child("Mount_nu_dock"+str(i),true,false)!=null,"each backpack funnel has launch marker")
	for name in ["fly","shoot","shield","slash","dash_f","dash_b","dash_l","dash_r","dash_u","dash_d"]:
		t.ok(unit.model_anim.has(name),"combat animation present: "+name)
	unit.regz_weapons.held=true;unit.set_aim_direction(Vector3.FORWARD);await frames(host)
	var marker:Node3D=unit.model_root.find_child("Mount_muzzle_R",true,false)
	t.lt(unit._rifle_origin().distance_to(marker.global_position),.02,"rifle muzzle uses actual moving marker")
	var grip:int=sk.find_bone("NuRifle")
	var axis:Vector3=(sk.global_basis*(unit.nu_motion.final_poses["NuRifle"] as Transform3D).basis*Vector3(.012,-.9803,-.1971)).normalized()
	t.gt(axis.dot(Vector3.FORWARD),.999,"precision barrel points along real aim direction")
	unit.weapon_index=2;await frames(host)
	var barrel:int=sk.find_bone("NuBazooka")
	axis=(sk.global_basis*(unit.nu_motion.final_poses["NuBazooka"] as Transform3D).basis*Vector3(.0014,-.9998,-.0219)).normalized()
	t.gt(axis.dot(Vector3.FORWARD),.999,"bazooka barrel points along aim")
	unit.shield_cooldown=0;t.ok(unit.raise_shield(),"physical shield raises");await frames(host)
	unit.nu_systems.discard_equipment();await frames(host)
	for prefix in ["NuBazooka_*","NuShield_*"]:
		for mesh in unit.model_root.find_children(prefix,"MeshInstance3D",true,false):t.not_ok(mesh.visible,"discard hides actual equipment")
	t.eq(stage.get_children().filter(func(n):return n.get_script()==preload("res://scripts/combat/nu_jettison.gd")).size(),2,"two actual equipment debris objects")
	unit.nu_systems.tick(15.01);await frames(host)
	for prefix in ["NuBazooka_*","NuShield_*"]:
		for mesh in unit.model_root.find_children(prefix,"MeshInstance3D",true,false):t.ok(mesh.visible,"cooldown restores model parts")
	unit.nu_systems.mode=2;unit.nu_systems.deploy()
	for i in 250:unit.nu_systems.tick(.01)
	t.ok(unit.nu_systems.barrier_active(),"real six funnel models support barrier")
	var mat:StandardMaterial3D=unit.nu_systems.barrier.mesh.surface_get_material(0)
	t.gt(mat.albedo_color.r,mat.albedo_color.g,"barrier pink red component")
	t.gt(mat.albedo_color.b,mat.albedo_color.g,"barrier pink blue component")
	t.suite("NuGundam / GP03 cabin without graduations and Nu state diagram")
	Settings.first_person=true;Settings.dash_screen_mode=Settings.DASH_SCREEN_SILHOUETTE;Game.set_phase(Game.Phase.FIGHT)
	var camera:=ChaseCamera.new();stage.add_child(camera);camera.target=unit;camera.first_person=true;camera.set_physics_process(false)
	var lock:=LockOnSystem.new();stage.add_child(lock);lock.setup(unit);unit.setup_refs(lock,camera)
	var hud:=FlightHUD.new();stage.add_child(hud);hud.setup(unit,camera,lock)
	await frames(host)
	var cabin=hud._cockpit_3d
	t.ok(cabin.visible,"Nu panoramic cabin enabled")
	t.eq(cabin.last_family,3,"uses same modular cabin as GP03")
	t.eq(load("res://scripts/ui/cockpit_3d.gd").cockpit_family(SuitProfile.Id.GP03D),3,"GP03 unchanged")
	t.ok(cabin.panorama.no_graduations,"calibration ladders disabled")
	t.eq(cabin.panorama.horizon.mesh,null,"world attitude rails absent")
	t.eq(cabin.surface._state_image.texture.resource_path,"res://assets/models/nu_gundam/state_1.res","deployed line drawing is Nu's own resource")
	for index in 4:t.ok(load("res://assets/models/nu_gundam/state_%d.res"%index)!=null,"all equipment diagram states available")
	stage.free();clean_audio(host);await frames(host);Settings.end_isolated();FlightBody.use_placeholder=old;Game.reset()

static func clean_audio(host:Node)->void:
	for parent in [host,Audio]:
		for child in parent.get_children():
			if (child is AudioStreamPlayer or child is AudioStreamPlayer3D) and child.has_node("AutoFree"):
				child.stop();child.stream=null;child.queue_free()
