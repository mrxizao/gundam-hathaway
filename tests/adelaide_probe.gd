extends Node3D
func _ready() -> void:
	assert(MapDef.Id.ADELAIDE in MapDef.versus_maps())
	assert(MapDef.by_id(MapDef.Id.ADELAIDE).terrain == MapDef.Terrain.ADELAIDE)
	var city = load("res://scripts/world/adelaide_builder.gd").new()
	add_child(city)
	await city.build_staged()
	assert(city.buildings.size()>700)
	assert(city.damaged_buildings>20)
	assert(city.get_node("AdelaideAirport/MSStand01").position == Vector3(-9480,27,4410))
	assert(city.MAP_SCALE/city.HORIZONTAL_SCALE == 3.0)
	assert(city.CITY_SCALE/city.HORIZONTAL_SCALE == 6.0)
	var reserve := Rect2(city.AIRPORT.position/6.0,city.AIRPORT.size/6.0)
	for road: Rect2 in city.roads:
		assert(not road.intersects(reserve.grow(-0.001)))
	for parcel: Rect2 in city.buildings: assert(city.parcel_clear(parcel))
	assert(city.get_node("AdelaideAirport/MSSortiePath").curve.point_count == 5)
	assert(city.get_node_or_null("AdelaideAirport/MSStand06") != null)
	assert(city.get_node_or_null("AdelaideAirport/CameraDeparture") != null)
	assert(city.get_node_or_null("AdelaideCollision") != null)
	print("ADELAIDE PASS buildings=",city.buildings.size()," damaged=",city.damaged_buildings," batches=",city.serial)
	if "--visual" in OS.get_cmdline_user_args():
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.60,0.57,0.50)
		env.environment.fog_enabled = true
		env.environment.fog_light_color = Color(0.56,0.53,0.46)
		env.environment.fog_density = 0.000008
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.54,0.52,0.46)
		env.environment.ambient_light_energy = 0.9
		add_child(env)
		var sun := DirectionalLight3D.new()
		sun.light_color = Color(1.0,0.88,0.72)
		sun.rotation_degrees = Vector3(-55,-30,0)
		add_child(sun)
		var camera := Camera3D.new()
		camera.far = 150000
		camera.near = 20
		add_child(camera)
		camera.position = Vector3(-25500,13000,31500)
		camera.look_at(Vector3(-3000,0,3600))
		camera.current = true
		await get_tree().create_timer(1).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/adelaide_overview.png")
		camera.position = Vector3(-17400,2400,17100)
		camera.look_at(Vector3(-10500,70,9000))
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/adelaide_airport.png")
		camera.position = Vector3(-10100,220,2900)
		camera.look_at(Vector3(-9480,105,4500))
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/adelaide_hangar_detail.png")
		camera.position = Vector3(-19000,2800,-20000)
		camera.look_at(Vector3(0,0,-26000))
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/adelaide_building_detail.png")
		var parcel: Rect2 = city.buildings[100]
		var target := Vector3(parcel.get_center().x*18,200,parcel.get_center().y*18)
		camera.position = target+Vector3(-850,450,-1100)
		camera.look_at(target)
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/adelaide_facade_detail.png")
		camera.position = Vector3(-6000,1100,0)
		camera.look_at(Vector3(-4680,25,1440))
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/adelaide_roads_detail.png")
	get_tree().quit()
