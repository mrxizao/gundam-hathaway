extends Node
var main: Node
var hud: Control
var out := ""
func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func freeze(n: Node) -> void:
	if n == hud:
		return
	n.set_process(false)
	n.set_physics_process(false)
	for child in n.get_children():
		freeze(child)
func shot(tag: String) -> void:
	hud.queue_redraw()
	await frames(3)
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(out.path_join(tag + ".png"))
	print("SHOT ", tag, " error=", err)
func _ready() -> void:
	out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://third_person_hud_preview"
	var dir_error := DirAccess.make_dir_recursive_absolute(out)
	if dir_error != OK:
		push_error("Cannot create capture directory: %s" % dir_error)
		get_tree().quit(1)
		return
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	Settings.first_person = false
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY, MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, SuitProfile.Id.PENELOPE)
	await frames(30)
	main.call("_start_fight")
	await frames(60)
	hud = main.get("hud")
	freeze(main)
	hud.set_process(false)
	InputSetup.using_gamepad = false
	hud.set("_notices", [])
	var pc = main.get("player")
	var enemy = main.get("enemy")
	if enemy != null:
		enemy.global_position = pc.global_position + pc.forward() * 2400.0 + Vector3(600, 200, 0)
		hud.lock.target = enemy
	pc.cursor_seen = true
	pc.aim_cursor = Vector2(800, 450)
	await shot("cruise")
	pc.hp = pc.max_hp * 0.2
	hud.set("_system_event_seen", "地形警告 · 拉起")
	hud.set("_system_event_timer", 10.0)
	hud.set_process(false)
	await shot("warning")
	pc.rifle_reloading = true
	pc.reload_timer = 1.0
	pc.funnel_reload_left = 2.0
	pc.vulcan_overheated = true
	pc.vulcan_heat = 1.0
	await shot("reload")
	var backing := ColorRect.new()
	backing.color = Color(0.86, 0.88, 0.91)
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.get_parent().add_child(backing)
	hud.get_parent().move_child(backing, 0)
	await shot("bright_background")
	backing.hide()
	Settings.first_person = true
	await shot("first_person")
	Settings.first_person = false
	DisplayServer.window_set_size(Vector2i(1280, 800))
	await frames(8)
	await shot("aspect_16_10")
	pc.rifle_reloading = false
	pc.funnel_reload_left = 0.0
	pc.vulcan_overheated = false
	pc.vulcan_heat = 0.0
	for suit in [SuitProfile.Id.PENELOPE, SuitProfile.Id.ARIZEUS, SuitProfile.Id.GUSTAV00, SuitProfile.Id.MESSER_M01]:
		pc.profile = SuitProfile.by_id(suit)
		pc.weapon_index = 0
		await shot("profile_%d" % suit)
		pc.weapon_index = 1
		await shot("alternate_%d" % suit)
	get_tree().quit()

