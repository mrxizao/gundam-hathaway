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
	var start:=Time.get_ticks_msec()
	var last:=start
	var next_capture:=0.0
	var index:=0
	while true:
		var now:=Time.get_ticks_msec()
		var time:=minf((now-start)/1000.0,PS.TOTAL)
		director.step(time,(now-last)/1000.0)
		last=now
		assert(main.chase.global_transform.is_finite())
		assert(not main.player.controls_enabled)
		assert(main.player.global_position.y>3000)
		await RenderingServer.frame_post_draw
		if time>=next_capture:
			var shot:=get_viewport().get_texture().get_image()
			shot.resize(800,450,Image.INTERPOLATE_LANCZOS)
			shot.save_png(folder.path_join("frame_%04d.png" % index))
			index+=1;next_capture+=0.125
		if time>=PS.TOTAL:break
	print("M04_REALTIME_90 seconds=",(Time.get_ticks_msec()-start)/1000.0," captures=",index)
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
