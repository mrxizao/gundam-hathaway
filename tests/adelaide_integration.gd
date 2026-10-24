extends Node
func _ready() -> void:
	var world := WorldBuilder.new()
	world.defer_initial_map = true
	add_child(world)
	await world.apply_map_staged(MapDef.adelaide())
	assert(world.get_node_or_null("Terrain/Adelaide/AdelaideAirport") != null)
	assert(world.match_spawn_radius() == 81000)
	var from := Vector3(-14970,200,9000)
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(from,from-Vector3.UP*300,1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	assert(not hit.is_empty())
	assert(hit.position.y>24)
	# Six central MS departure corridors remain clear at body/shoulder height.
	for n in 6:
		var z := (1500.0+n*540)*3
		for height: float in [55,110,145]:
			var q := PhysicsRayQueryParameters3D.create(Vector3(-9480,height,z),Vector3(-9480,height,z-1080),1)
			assert(world.get_world_3d().direct_space_state.intersect_ray(q).is_empty())
	var city = world.get_node("Terrain/Adelaide")
	assert(city.get_node_or_null("RiverTorrens") != null)
	var base := city.get_node("AdelaideAirport")
	assert(base.get_node_or_null("Sign_MS_01") != null)
	var path: Path3D = base.get_node("MSSortiePath")
	for n in path.curve.point_count-1:
		var a_point := path.curve.get_point_position(n)
		var b_point := path.curve.get_point_position(n+1)
		var path_query := PhysicsRayQueryParameters3D.create(a_point+Vector3.UP*40,b_point+Vector3.UP*40,1)
		assert(world.get_world_3d().direct_space_state.intersect_ray(path_query).is_empty())

	assert(city.bridge_sites.size()>4)
	var rx := 300.0
	var rz: float = city.river_z(rx)
	var river_query := PhysicsRayQueryParameters3D.create(Vector3(rx*18,100,rz*18),Vector3(rx*18,-50,rz*18),1)
	var river_hit := world.get_world_3d().direct_space_state.intersect_ray(river_query)
	assert(not river_hit.is_empty())
	assert(river_hit.position.y<1.0)
	for x: float in city.bridge_sites:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x*18,100,city.river_z(x)*18),Vector3(x*18,-50,city.river_z(x)*18),1)
		var bridge_hit := world.get_world_3d().direct_space_state.intersect_ray(q)
		assert(not bridge_hit.is_empty() and bridge_hit.position.y>25)
	world.apply_map(MapDef.adelaide())
	assert(world.get_node("Terrain").get_child_count()==2)
	print("ADELAIDE INTEGRATION PASS staged/sync/rebuild/spawn/collision")
	get_tree().quit()
