extends RefCounted
static func freeze(n: Node) -> void:
	n.set_process(false);n.set_physics_process(false)
	for child in n.get_children(): freeze(child)
static func run(t: T, host: Node) -> void:
	t.suite("OdysseusPedal / escape gate, dedicated model and dismount")
	Settings.begin_isolated()
	for path in ["res://assets/models/odysseus_pedal/empty.scn","res://assets/models/odysseus_pedal/mounted.scn"]:
		t.eq(ResourceLoader.get_dependencies(path).size(),0,"portable embedded model: "+path)
	var previous := FlightBody.use_placeholder
	FlightBody.use_placeholder=false
	var stage := Node3D.new();host.add_child(stage)
	var body := PlayerController.new()
	body.profile=SuitProfile.penelope();body.is_player=true;body.projectile_container=stage
	stage.add_child(body);freeze(body);body.position=Vector3(0,3000,0)
	t.not_ok(body.mount_pedal(),"Penelope cannot call the dedicated platform before escape")
	t.eq(body.configure_pedal(FlightPedal.Kind.ODYSSEUS,true),null,"forced configuration cannot bypass escape gate")
	body.ifield_hp=0.0
	body._apply_damage(body.max_hp*.995,null,Damage.Type.BEAM)
	body._tick_transform(SuitProfile.TRANSFORM_COVER+.01)
	freeze(body)
	t.eq(body.profile.form,1,"actual low-hull escape produces Odysseus")
	t.ok(body.profile.can_ride_pedal(),"escaped core can call platform")
	t.eq(FlightPedal.kind_for_profile(body.profile),FlightPedal.Kind.ODYSSEUS,"escaped profile selects supplied model")
	t.not_ok(body.profile.has_missiles,"mounted core does not regain funnel missiles")
	t.ok(body.mount_pedal(),"core can summon platform")
	var board := body._inbound_pedal
	t.ok(board != null,"call creates a platform in flight")
	freeze(board)
	t.eq(board.kind,FlightPedal.Kind.ODYSSEUS,"incoming platform is dedicated Odysseus type")
	t.eq(board.slot_count(),1,"single rider model cannot admit a second unit")
	var rider_meshes := 0
	for mesh in board._model.find_children("*","MeshInstance3D",true,false):
		if mesh.get_meta("odysseus_rider",false): rider_meshes+=1
	t.eq(rider_meshes,0,"summoned empty platform has no ghost pilot")
	board._arrive();freeze(board)
	t.ok(body.has_pedal(),"arrival mounts core")
	t.gt((-board.global_basis.z).normalized().dot(body.forward()),.999,"arrival discards inbound orientation and follows pilot heading")
	t.ok(body.rider_hidden,"supplied model replaces original rider without double geometry")
	t.ok(board._model.find_child("Penelope_Rifle",true,false)!=null,"mounted model retains Penelope rifle")
	var rifle:=board._model.find_child("Penelope_Rifle",true,false) as MeshInstance3D
	var center:Vector3=rifle.to_global(rifle.mesh.get_aabb().get_center())
	var muzzle:Vector3=body.to_global(body._rifle_muzzle_local(0))
	t.ok(rifle.mesh.get_aabb().grow(.05).has_point(rifle.to_local(muzzle)),"rifle emitter remains on actual weapon after mounted orientation correction")
	var heading:=body.basis
	body.rotate_y(.65)
	center=rifle.to_global(rifle.mesh.get_aabb().get_center());muzzle=body.to_global(body._rifle_muzzle_local(0))
	t.ok(rifle.mesh.get_aabb().grow(.05).has_point(rifle.to_local(muzzle)),"rifle emitter follows visible weapon after pilot turns")
	body.basis=heading
	rider_meshes=0
	for mesh in board._model.find_children("*","MeshInstance3D",true,false):
		if mesh.get_meta("odysseus_rider",false): rider_meshes+=1
	t.eq(rider_meshes,53,"mounted model contains supplied 52 core parts plus rifle")
	t.near(body.fm.max_speed,SuitProfile.xi().player_top_speed(),.001,"platform reaches ordinary Xi cruise speed")
	var intruder := FlightBody.new();intruder.profile=SuitProfile.gustav00();stage.add_child(intruder);freeze(intruder)
	t.not_ok(board.can_rider_ride(intruder),"another suit cannot use Odysseus-specific mode")
	board.add_rider(intruder)
	t.eq(board.riders.size(),1,"second rider is rejected without hiding them")
	t.not_ok(intruder.rider_hidden,"rejected rider remains visible")
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1000,700))
		var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.04,.06,.09);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.65
		var world:=WorldEnvironment.new();world.environment=env;stage.add_child(world)
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);light.light_energy=1.1;stage.add_child(light)
		var camera:=Camera3D.new();camera.fov=43;stage.add_child(camera);camera.make_current()
		intruder.visible=false
		for mesh in stage.find_children("*","MeshInstance3D",true,false):
			if not board._model.is_ancestor_of(mesh): mesh.visible=false
		for particles in stage.find_children("*","GPUParticles3D",true,false): particles.visible=false;particles.emitting=false
		var out:="C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/odysseus_pedal";DirAccess.make_dir_recursive_absolute(out)
		for angle in ["front","rear"]:
			camera.position=body.position+Vector3(-48,18,-75 if angle=="front" else 75)
			camera.look_at(body.position)
			for frame in 3: await host.get_tree().process_frame
			await RenderingServer.frame_post_draw
			host.get_viewport().get_texture().get_image().save_png(out+"/mounted_"+angle+".png")
	t.ok(body.dismount_pedal(),"voluntary dismount succeeds")
	t.not_ok(body.has_pedal(),"core is no longer mounted")
	t.not_ok(body.rider_hidden,"dismount restores original animated core")
	t.near(body.fm.max_speed,body.profile.player_top_speed(),.001,"dismount restores core flight speed")
	rider_meshes=0
	for mesh in board._model.find_children("*","MeshInstance3D",true,false):
		if mesh.get_meta("odysseus_rider",false): rider_meshes+=1
	t.eq(rider_meshes,0,"departing empty board does not retain a phantom core")
	t.ok(body.mount_pedal(),"core can call again after voluntary dismount")
	var second := body._inbound_pedal
	second._arrive();freeze(second)
	var destroyed := second.take_damage(second.max_hp+1.0)
	t.ok(destroyed,"platform destruction is handled")
	if destroyed: second.break_off(true)
	t.not_ok(body.has_pedal(),"destroyed platform releases core")
	t.not_ok(body.rider_hidden,"destruction restores animated core visibility")
	stage.free();FlightBody.use_placeholder=previous;Settings.end_isolated()
