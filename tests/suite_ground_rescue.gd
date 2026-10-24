extends RefCounted
static func run(t: T, host: Node) -> void:
	t.suite("Ground rescue / held dive, skipped threshold and death boundary")
	Settings.begin_isolated();Game.reset()
	var old_map = Game.active_map
	Game.active_map = null
	var previous := FlightBody.use_placeholder
	FlightBody.use_placeholder = false
	for id in [SuitProfile.Id.XI,SuitProfile.Id.PENELOPE,SuitProfile.Id.REGZ_CUSTOM,SuitProfile.Id.ARIZEUS]:
		for cruise in [false,true]:
			var unit := PlayerController.new()
			unit.profile = SuitProfile.by_id_form(id,1 if cruise and id in [SuitProfile.Id.REGZ_CUSTOM,SuitProfile.Id.ARIZEUS] else 0)
			unit.is_player = true;unit.controls_enabled = true;unit.assist_on = true
			host.add_child(unit);unit.set_physics_process(false);unit.set_process(false)
			unit.cruise_morph = 1.0 if cruise else 0.0
			t.eq(unit.profile.id,id,"actual requested suit profile is loaded")
			unit.position = Vector3(0,35,0)
			unit.fm.velocity = Vector3(0,-3000,-400)
			var hp_before := unit.hp
			t.ok(unit._before_flight_move(1.0/60.0),"35m fast dive cannot skip the 30m gate")
			t.lt(unit.fm.velocity.y,0.0,"crossing frame limits descent without high-altitude ascent")
			unit.position += unit.fm.velocity/60.0;unit._check_ceiling()
			t.ok(unit._before_flight_move(1.0/60.0),"boundary frame starts the actual ascent")
			t.gt(unit.fm.velocity.y,0.0,"ascent starts at the boundary")
			t.ok(unit.alive,"rescue happens before sea death")
			unit.translate_mode = true;unit.translate_dir = Vector3.DOWN
			for frame in 90:
				unit._apply_flight(1.0/60.0)
				t.ok(unit.alive,"held descent remains protected")
				t.gt(unit.position.y,24.0,"held descent cannot cross explosion line")
			t.eq(unit.hp,hp_before,"ground protection does not inflict damage")
			unit.position.y = 23.0;unit.fm.velocity = Vector3(0,-2000,0)
			unit._check_ceiling()
			t.ok(unit.alive,"last death check also rescues an assisted player")
			t.gt(unit.position.y,24.0,"death-boundary rescue raises hull")
			unit._assist.terrain_warn = true;unit._terrain_warn_on = false
			unit._tick_terrain_warn()
			t.not_ok(unit._terrain_warn_on,"no low-nose terrain warning")
			unit.assist_on = false;unit.position.y = 23.0;unit._check_ceiling()
			t.not_ok(unit.alive,"manual flight retains normal crash death")
			unit.free()
	var ground := StaticBody3D.new();ground.collision_layer = 1;ground.collision_mask = 0
	ground.add_to_group("avoidance_ground");host.add_child(ground)
	ground.position = Vector3(2000,500,0)
	var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size = Vector3(1000,2,1000)
	shape.shape = box;ground.add_child(shape)
	var terrain_unit := PlayerController.new();terrain_unit.profile = SuitProfile.xi()
	terrain_unit.is_player = true;terrain_unit.controls_enabled = true;terrain_unit.assist_on = true
	host.add_child(terrain_unit);terrain_unit.set_process(false);terrain_unit.set_physics_process(false)
	await host.get_tree().physics_frame
	for hz in [30.0,60.0,120.0]:
		terrain_unit.position = Vector3(2000,536,0);terrain_unit.fm.velocity = Vector3(0,-3000,0)
		t.ok(terrain_unit._before_flight_move(1.0/hz),"raised terrain fast-dive rescue %sHz" % hz)
		t.lt(terrain_unit.fm.velocity.y,0.0,"raised terrain crossing frame limits descent")
	terrain_unit.position = Vector3(2000,505,0);terrain_unit.fm.velocity = Vector3.DOWN*500
	t.ok(terrain_unit._prevent_ground_crash(),"terrain contact death hook is rescued")
	t.gt(terrain_unit.position.y,530.0,"rescue respects terrain elevation, not sea altitude")
	terrain_unit.position = Vector3(0,200,0);terrain_unit.fm.velocity = Vector3(0,-1000,0)
	t.not_ok(terrain_unit._before_flight_move(1.0/60.0),"no early takeover at high altitude")
	t.eq(terrain_unit.fm.velocity,Vector3(0,-1000,0),"high dive preserves player descent")
	Game.active_map = MapDef.leo();terrain_unit.position = Vector3(0,25,0)
	t.not_ok(terrain_unit._rescue_ground(1.0/60.0),"space has no invented ground rescue")
	terrain_unit.free();ground.free()
	FlightBody.use_placeholder = previous;Game.active_map = old_map
	Settings.end_isolated();Game.reset()
