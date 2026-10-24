extends Node
var camera: Camera3D
var stage: Node3D
var out := "C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/arizeus_cruise_nozzles"
func freeze(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)
	for child in n.get_children(): freeze(child)
func shot(key: String) -> void:
	for unused in 2: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(key+".png"))
func _ready() -> void:
	Settings.begin_isolated()
	AudioServer.set_bus_mute(0,true)
	Game.reset()
	Game.set_phase(Game.Phase.INTRO)
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1000,700))
	stage = Node3D.new()
	add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055,0.075,0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8,0.85,1)
	env.ambient_light_energy = 0.5
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	for angle in [Vector3(-40,-35,0),Vector3(-15,140,0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = angle
		light.light_energy = 0.85
		stage.add_child(light)
	camera = Camera3D.new()
	camera.fov = 40
	stage.add_child(camera)
	camera.make_current()
	FlightBody.use_placeholder = false
	var unit := PlayerController.new()
	unit.profile = SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
	unit.projectile_container = stage
	stage.add_child(unit)
	freeze(unit)
	unit.position = Vector3.ZERO
	camera.position = Vector3(0,0.05,1).normalized()*unit.profile.target_height*2.4
	camera.look_at(Vector3.ZERO)
	unit.position.y=3000
	for entry in [
		["cruise_level",SuitProfile.ArizeusForm.CRUISE,Vector3.ZERO,Vector3.ZERO],
		["cruise_turn",SuitProfile.ArizeusForm.CRUISE,Vector3(32,55,-27),Vector3(10,-8,19)],
		["normal_after_switch",SuitProfile.ArizeusForm.NORMAL,Vector3(-18,-40,22),Vector3(-8,4,-12)],
		["cruise_after_switch",SuitProfile.ArizeusForm.CRUISE,Vector3(-35,130,42),Vector3(8,5,-14)]]:
		if unit.profile.form!=entry[1]:
			unit.switch_form(entry[1])
			freeze(unit)
		unit.fm.boosting=true
		unit.fm.velocity=unit.global_basis*Vector3(180,40,-850)
		for frame in 35:
			unit._tick_effects(1.0/60)
			unit.rotation_degrees=entry[2]
			unit.model_pivot.rotation_degrees=entry[3]
			unit.spin_pivot.rotation_degrees=Vector3(0,12,-5)
			unit._tick_plume_bend(1.0/60)
			await get_tree().process_frame
		camera.position=unit.position+unit.global_basis*Vector3(.36,.25,1).normalized()*92
		camera.look_at(unit.position)
		await shot(entry[0])
		print("ARIZEUS_PLUME_CAPTURE ",entry[0]," count=",unit._plume_fx.size())
	print("ARIZEUS_CRUISE_NOZZLE_GPU_PASS")
	get_tree().quit()
