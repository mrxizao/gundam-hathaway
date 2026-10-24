extends RefCounted
const Wake := preload("res://scripts/world/sea_flight_wake.gd")
static func run(t: T, host: Node) -> void:
	t.suite("SeaFlightWake / altitude, propulsion and bounded world-space wakes")
	var low := Wake.influence(35,26,900,true,false)
	t.gt(low,0.75,"low fast flight produces a strong disturbance")
	t.lt(Wake.influence(100,26,900,true,false),low,"disturbance fades with height")
	t.near(Wake.influence(300,26,1200,true,true),0,0.0001,"high flight produces no wake")
	t.near(Wake.influence(-10,26,1200,true,true),0,0.0001,"submerged or crashed units cannot disturb the surface")
	t.gt(Wake.influence(40,26,0,true,false),0,"powered hovering creates downwash")
	t.near(Wake.influence(40,26,0,false,false),0,0.0001,"unpowered stationary bodies do not create spray")
	t.gt(Wake.influence(60,26,400,true,true),Wake.influence(60,26,400,true,false),"boost strengthens the wake")
	t.gt(Wake.influence(150,26,900,true,false),0.15,"150 metres already has a visible wake")
	t.near(Wake.influence(150.01,80,1200,true,true),0,0.0001,"all suits use the same 150 metre trigger ceiling")
	var stage := Node3D.new()
	host.add_child(stage)
	var world := WorldBuilder.new()
	world.defer_initial_map = true
	stage.add_child(world)
	world.set_process(false)
	world.map = MapDef.pacific()
	var sea := MeshInstance3D.new()
	sea.mesh = PlaneMesh.new()
	world.add_child(sea)
	world.ocean = sea
	var wake := world.get_node("SeaFlightWake")
	wake.set_physics_process(false)
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80,10,80)
	shape.shape = box
	obstacle.add_child(shape)
	stage.add_child(obstacle)
	obstacle.position = Vector3(0,15,0)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	t.ok(not wake.water_at(Vector3(0,45,0)),"land or bridge blocks downwash before it reaches water")
	t.ok(wake.water_at(Vector3(0,5,0)),"an overhead bridge does not block a jet already below the deck")
	obstacle.free()
	await host.get_tree().physics_frame
	t.ok(wake.water_at(Vector3(0,45,0)),"open sea accepts downwash")
	world.map = MapDef.uluru()
	t.ok(not wake.water_at(Vector3(0,45,0)),"desert rejects water effects")
	world.map = MapDef.leo()
	t.ok(not wake.water_at(Vector3(0,45,0)),"space rejects water effects even with a stale ocean reference")
	for city in [MapDef.oenbelli(),MapDef.davao()]:
		world.map = city
		var wet := 0
		var dry := 0
		for x in range(-30000,30001,10000):
			for z in range(-30000,30001,10000):
				var planned := WorldBuilder.is_water_at(x,z,city.city_layout) and not WorldBuilder.city_is_dry(x,z,city.city_layout)
				t.eq(wake.water_at(Vector3(x,45,z)),planned,"city shoreline matches the authoritative water and ground masks")
				if planned: wet += 1
				else: dry += 1
		t.gt(wet,0,"city checks include actual sea or canal water")
		t.gt(dry,0,"city checks include dry land")
	world.map = MapDef.pacific()
	var old_placeholder := FlightBody.use_placeholder
	FlightBody.use_placeholder = true
	var unit := FlightBody.new()
	unit.profile = SuitProfile.xi()
	unit.is_player = true
	stage.add_child(unit)
	unit.set_physics_process(false)
	unit.global_position = Vector3(0,40,0)
	unit.fm.velocity = Vector3(0,0,-800)
	unit.fm.boosting = true
	wake.step(0.1)
	t.gt(wake.emitted_packets,0,"real units produce surface stamps")
	t.eq(wake.emitters.size(),1,"spray is attached to the active source")
	t.ok(wake.emitters[unit.get_instance_id()]["spray"].local_coords == false,"spray droplets move in world space")
	var stamp_position: Vector3 = wake.packets[0]["mesh"].global_position
	unit.global_position += Vector3(0,0,-100)
	wake.step(0.1)
	t.near(wake.packets[0]["mesh"].global_position.distance_to(stamp_position),0,0.001,"old waves remain in world space instead of following the suit")
	for i in 150: wake.stamp(Vector3(i,1,0),Vector3.FORWARD*900,26,0.8)
	t.ok(wake.packets.size()<=48,"wave pool stays bounded under repeated passes")
	for profile in [SuitProfile.xi(),SuitProfile.penelope(),SuitProfile.arizeus(),SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)]:
		wake.clear_effects()
		unit.profile = profile
		unit.global_position = Vector3(0,150,0)
		unit.fm.velocity = Vector3(0,0,-profile.player_boost_speed())
		for frame in 8:
			unit.global_position += unit.fm.velocity / 60.0
			wake.step(1.0/60)
			var wash: MeshInstance3D = wake.emitters[unit.get_instance_id()]["wash"]["mesh"]
			t.near(Vector2(wash.global_position.x,wash.global_position.z).distance_to(Vector2(unit.global_position.x,unit.global_position.z)),0,0.001,"live water footprint follows full boost speed without lag: " + profile.display_name)
		t.gt(wake.packets.size(),1,"full-speed pass emits detached water history: " + profile.display_name)
		var history: Dictionary = wake.emitters[unit.get_instance_id()]
		t.gt(history["points"].size(),1,"high-speed history forms a connected foam trail")
		t.ok(history["trail"].mesh != null,"connected trail has rendered geometry independent of the ring pool")
		var old_point: Vector3 = history["points"][0]["point"]
		wake.step(0.5)
		t.near(history["points"][0]["point"].distance_to(old_point),0,0.001,"tail remains at its world-space flight path")
		unit.global_position += unit.fm.velocity / 60.0
		wake.step(1.0/60)
		t.ok(history["head"].mesh != null,"live trail head bridges the frame between history samples")
		var vertices: PackedVector3Array = history["head"].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		t.near(Vector2(vertices[-1].x,vertices[-1].z).distance_to(Vector2(unit.global_position.x,unit.global_position.z)),0,0.001,"foam trail ends at the current footprint even at full boost")
		for i in range(2,wake.packets.size()):
			var gap: float = wake.packets[i]["mesh"].global_position.distance_to(wake.packets[i-1]["mesh"].global_position)
			var radius: float = wake.packets[i]["material"].get_shader_parameter("initial_radius")
			t.lt(gap,radius*2.32+1,"speed-scaled footprints overlap instead of leaving gaps")
		unit.global_position = Vector3(50000,150,-50000)
		wake.step(0.1)
		var teleported_radius: float = wake.packets[-1]["material"].get_shader_parameter("initial_radius")
		t.lt(teleported_radius,100,"teleports cannot create a map-sized wave")
	unit.global_position.y = 600
	var before: int = wake.emitted_packets
	wake.step(0.2)
	t.eq(wake.emitted_packets,before,"climbing away stops new wave emission")
	t.ok(not wake.emitters[unit.get_instance_id()]["spray"].emitting,"climbing stops the water jets")
	unit.global_position.y = 40
	unit.alive = false
	wake.step(0.1)
	t.eq(wake.emitted_packets,before,"destroyed units cannot emit new surface waves")
	wake.step(4.0)
	t.eq(wake.emitters.size(),0,"spray source is released after droplets drain")
	for entry in wake.packets: t.ok(not entry["mesh"].visible,"existing waves fade and expire")
	world.ocean = null
	wake.step(0.1)
	t.eq(wake.packets.size(),0,"map removal clears all old surface waves")
	unit.free()
	stage.free()
	FlightBody.use_placeholder = old_placeholder
	await host.get_tree().process_frame
