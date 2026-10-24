extends Node
var camera: Camera3D
var stage: Node3D
var out := "C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/penelope_game"
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
	unit.profile = SuitProfile.odysseus()
	unit.projectile_container = stage
	stage.add_child(unit)
	freeze(unit)
	unit.position = Vector3.ZERO
	camera.position = Vector3(-0.62,0.20,-1).normalized()*unit.profile.target_height*2.4
	camera.look_at(Vector3.ZERO)
	var anim := unit.model_anim
	anim.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.hold_rest(0.0,true)
	anim.player.advance(0.0)
	await shot("odysseus_normal")
	anim.play_once("shoot",0.0,true)
	anim.player.seek(0.20,true)
	await shot("odysseus_shoot")
	anim.play_once("slash",0.0,true)
	anim.player.seek(0.40,true)
	await shot("odysseus_saber")
	print("ODYSSEUS GPU PREVIEW PASS")
	get_tree().quit()
