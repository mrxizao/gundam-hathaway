extends Node
const PS := preload("res://scripts/data/pod_strike_script.gd")
var folder := "res://_m04_camera"
func _ready() -> void:
	Settings.begin_isolated()
	Settings.first_person=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): folder=arg.substr(6)
		if arg=="--fp=1": Settings.first_person=true
	DirAccess.make_dir_recursive_absolute(folder)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	assert(main._resolve_campaign_match("M04"))
	main.world.pin_anim_time(50.0)
	main._begin_pod_strike()
	var director = main._strike_director
	assert(is_instance_valid(director.pod))
	assert(Audio.current_bgm_track()=="xi")
	var paused_time:float=main._strike_t
	main._set_paused(true)
	main._process(.5)
	assert(main._strike_t==paused_time)
	for audio in Audio._bgm_players:assert(audio.stream_paused)
	main._set_paused(false)
	for audio in Audio._bgm_players:assert(not audio.stream_paused)
	print("M04_PAUSE_RESUME_OK")
	var points := [[8.0,"01_orbit"],[19.0,"02_inside"],[26.0,"03_cloud"],[37.0,"04_burn"],[44.0,"05_intercept"],[49.0,"06_aim"],[51.5,"07_charge"],[52.4,"08_hit"],[56.0,"09_damage"],[63.0,"10_enemy_push"],[68.0,"11_enemy_eye"],[73.0,"12_escape"],[76.0,"13_flyout"],[81.0,"14_cloud_rush"],[86.0,"15_orbit_back"],[89.9,"16_handoff"]]
	for point in points:
		var time:float=point[0]
		director.step(time,0.0)
		assert(main.chase.global_transform.is_finite())
		assert(main.player.global_position.y>3000)
		assert(not main.player.controls_enabled)
		for frame in 3: await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(folder.path_join(point[1]+".png"))==OK)
		print("M04_FRAME ",point[1]," at=",time," camera=",main.chase.global_position)
	director.step(PS.TOTAL,0.0)
	var before:Transform3D=main.chase.global_transform
	main._strike_t=PS.TOTAL
	main._finish_pod_strike()
	assert(before.origin.distance_to(main.chase.global_position)<0.01)
	assert(before.basis.get_rotation_quaternion().angle_to(main.chase.global_basis.get_rotation_quaternion())<0.001)
	assert(main.player.controls_enabled and main.player.is_physics_processing())
	assert(not main.chase.first_person and not main.chase.externally_stepped)
	assert(Audio.current_bgm_track()=="car5p3")
	print("M04_90_INTEGRATION_OK controls=true music=car5p3")
	main.free()
	get_tree().quit()
