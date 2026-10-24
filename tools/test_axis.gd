extends Node
var checks:=0
func check(ok: bool,label: String) -> void:
	if not ok: push_error("AXIS FAILED "+label);get_tree().quit(1)
	else: checks+=1;print("PASS ",label)
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void:
	Settings.begin_isolated();Game.phase=Game.Phase.FIGHT;Game.active_map=MapDef.axis()
	check(MapDef.versus_maps().has(MapDef.Id.AXIS),"Map is selectable")
	check(Game.active_map.has_ground and not FlightBody.map_ground_damaging(),"Solid ground has explicit impact immunity")
	check(Game.active_map.cloud_density==0,"No atmospheric clouds")
	var world:=WorldBuilder.new();world.initial_map=MapDef.Id.AXIS;add_child(world);world.set_process(false)
	var axis=world.find_child("AxisSurface",true,false)
	check(axis!=null,"Actual Axis terrain built")
	check(world.ocean==null,"No sea generated")
	check(world.get_tree().get_nodes_in_group("axis_ground").size()>=256,"Tiled terrain has solid collision")
	check(axis.find_child("AxisEarth",true,false)!=null,"Visible Earth mesh exists")
	var battle=axis.find_child("AxisDistantBattle",true,false)
	check(battle!=null and battle.streaks.instance_count==64 and battle.flashes.instance_count==24,"Continuous background fire and round flashes")
	check(battle.find_children("*","CollisionObject3D",true,false).is_empty(),"Background effects have no collisions or damage")
	var old_path: Transform3D=battle.streaks.get_instance_transform(0)
	battle._process(0.2)
	check(battle.streaks.get_instance_transform(0)!=old_path,"Background fire moves continuously")
	var old_ring: Transform3D=battle.flashes.get_instance_transform(0)
	battle._process(0.2)
	check(battle.flashes.get_instance_transform(0)!=old_ring,"Round explosions expand and recycle")
	var spawn: Vector3=world.spawn_point(-95,world.match_spawn_radius(),world.match_player_alt())
	check(spawn.y>axis.height_at(spawn.x,spawn.z)+500,"Safe spawn clearance")
	FlightBody.use_placeholder=true
	var body:=FlightBody.new();body.profile=SuitProfile.xi();add_child(body);body.set_process(false);body.set_physics_process(false)
	FlightBody.use_placeholder=false;body.ifield_hp=0;body.invuln_until=-1
	var height: float=axis.height_at(0,0);body.global_position=Vector3(0,height+200,0)
	var hp:=body.hp;var contact:=false
	for i in 30:
		await get_tree().physics_frame
		body.velocity=Vector3(0,-1500,0);body.move_and_slide()
		if body.get_slide_collision_count()>0: contact=true
		body._check_collisions();body._check_ceiling()
	check(contact,"Real body physically contacts terrain")
	check(body.alive and body.hp==hp,"Ground contact neither damages nor explodes the suit")
	check(body.global_position.y>=height,"Solid floor blocks penetration")
	body.global_position.y=0;body._check_ceiling();check(body.alive,"Low altitude does not invoke instant destruction")
	body.global_position.y=height+300;body.take_damage(15,null,Damage.Type.BEAM)
	check(body.hp<hp,"Weapon damage still functions")
	var cam:=Camera3D.new();cam.near=2.0;cam.far=1500000;add_child(cam);cam.current=true
	if DisplayServer.get_name()!="headless":
		var out:=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(out)
		var poses: Array[Vector3]=[Vector3(0,1100,6500),Vector3(5000,1400,8500),Vector3(-1500,450,4000)]
		for i in poses.size():
			cam.position=poses[i];cam.look_at(Vector3(1800,650,-5000))
			await frames(25);await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(out.path_join("axis_%d.png" % i))==OK,"Rendered landscape "+str(i))
		cam.position=Vector3(0,1700,0);cam.look_at(Vector3(0,36000,-45000))
		await frames(30);await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(out.path_join("axis_sky.png"))==OK,"Rendered distant fire and flashes")
	Game.active_map=MapDef.pacific();check(FlightBody.map_ground_damaging(),"Other maps keep impact damage")
	body.global_position.y=0;body._check_ceiling();check(not body.alive,"Other maps still enforce ground crash destruction")
	world.queue_free();body.queue_free();Settings.end_isolated();await frames(2)
	print("AXIS_DONE ",checks," PASS / 0 FAIL");get_tree().quit()

