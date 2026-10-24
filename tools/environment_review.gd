extends Node3D
## Deterministic real-render evidence; no player save writes.
var world: WorldBuilder
var camera: Camera3D
var folder := "res://_environment_review"
var enabled := true
var map_name := "pacific"
var mode := "low"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): folder = arg.substr(6)
		if arg.begins_with("--detail="): enabled = arg.substr(9) == "1"
		if arg.begins_with("--map="): map_name = arg.substr(6)
		if arg.begins_with("--view="): mode = arg.substr(7)
	if DisplayServer.get_name() == "headless":
		push_error("Real rendering is required")
		get_tree().quit(2)
		return
	var err := DirAccess.make_dir_recursive_absolute(folder)
	if err != OK:
		push_error("Output directory error %d" % err)
		get_tree().quit(3)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	world = WorldBuilder.new()
	world.environment_detail_enabled = enabled
	var maps := {"pacific": MapDef.Id.PACIFIC, "uluru": MapDef.Id.ULURU, "davao": MapDef.Id.DAVAO, "oenbelli": MapDef.Id.OENBELLI, "range": MapDef.Id.RANGE, "leo": MapDef.Id.LEO}
	world.initial_map = maps.get(map_name, MapDef.Id.PACIFIC)
	add_child(world)
	world.pin_anim_time(50.0)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 2.0
	camera.far = 700000.0
	add_child(camera)
	camera.current = true
	if map_name == "pacific":
		camera.position = Vector3(0, 60, 1600)
		camera.look_at(Vector3(0, 0, -900), Vector3.UP)
		if mode == "high":
			camera.position = Vector3(0, 3400, 4500)
			camera.look_at(Vector3(0, 0, -3000), Vector3.UP)
		if mode == "veryhigh":
			camera.position = Vector3(0, 12000, 14000)
			camera.look_at(Vector3(0, 0, -3000), Vector3.UP)
		if mode == "cloud":
			var xf: Transform3D = world.cloud_bands[1][0]
			camera.position = xf.origin + Vector3(0, 200, 3000)
			camera.look_at(xf.origin, Vector3.UP)
		if mode == "inside":
			var xf: Transform3D = world.cloud_bands[1][0]
			camera.position = xf.origin + Vector3(0, 0, 180)
			camera.look_at(xf.origin + Vector3(0, 0, -1500), Vector3.UP)
	elif map_name == "uluru" or map_name == "range":
		camera.position = Vector3(0, 1100, 3600)
		camera.look_at(Vector3(0, 0, -500), Vector3.UP)
	else:
		camera.position = Vector3(0, 11000, 18000)
		camera.look_at(Vector3(0, 0, 0), Vector3.UP)
		if mode == "low":
			camera.position = Vector3(6000, 2500, 7000)
			camera.look_at(Vector3(0, 1200, 0), Vector3.UP)
	world.set_process(false)
	if is_instance_valid(world._local_cloud_volume):
		world._local_cloud_volume.set_process(false)
		world._local_cloud_volume.tint = world.time_of_day.cloud_tints[1]
		for i in 8: world._local_cloud_volume._process(0.25)
	for i in 90:
		await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in 180:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		samples.append(float(now - last) / 1000.0)
		last = now
	samples.sort()
	var img := get_viewport().get_texture().get_image()
	var stem := "%s_%s_%s" % [map_name, mode, "after" if enabled else "before"]
	err = img.save_png(folder.path_join(stem + ".png"))
	var stats := {"map": map_name, "view": mode, "detail": enabled, "position": str(camera.position), "basis": str(camera.basis), "size": str(img.get_size()), "frame_ms_p50": samples[90], "frame_ms_p95": samples[171], "frame_ms_p99": samples[178], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "png_error": err}
	stats["fft_active"] = world.ocean != null and world._ocean_mat.get_shader_parameter("fft_enabled") == true
	stats["fft_dispatches"] = world.ocean.get_node("FFTSea").dispatch_count if world.ocean != null and world.ocean.has_node("FFTSea") else 0
	stats["animation_time"] = float(world._ocean_mat.get_shader_parameter("wave_time")) if world.ocean != null else 0.0
	stats["camera_height"] = camera.position.y
	var file := FileAccess.open(folder.path_join(stem + ".json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(stats, "  "))
	print("ENV_REVIEW ", JSON.stringify(stats))
	get_tree().quit(0 if err == OK else 4)
