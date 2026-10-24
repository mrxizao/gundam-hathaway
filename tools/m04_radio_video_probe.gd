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
	const Dialogue = preload("res://scripts/data/pod_strike_dialogue.gd")
	assert(Dialogue.CUES.size()+Dialogue.VIDEO_CUES.size()==27)
	var ids:Dictionary={}
	for cue in Dialogue.CUES+Dialogue.VIDEO_CUES:
		assert(not Dialogue.Bank.plain_of(cue[2]).is_empty())
		assert(not ids.has(cue[2]));ids[cue[2]]=true
	assert(Dialogue.active_lines(8.99,true).is_empty())
	assert(Dialogue.active_lines(9.01,true).size()==1)
	assert(Dialogue.active_lines(10.01,true).size()==2)
	for point in [[12.2,"01_monologue"],[45.0,"02_lane"],[53.8,"03_hit_line"]]:
		director.step(point[0],0.0)
		for i in 3:await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join(point[1]+".png"))
	main._strike_t=59.95
	main._tick_pod_strike(.1)
	assert(is_equal_approx(main._strike_t,60.0) and director.insert_active)
	var captured_nine:=false
	var captured_ten:=false
	var paused_once:=false
	var wall_start:=Time.get_ticks_msec()
	while director.insert_active:
		assert(main._strike_t==60.0)
		main._tick_pod_strike(.016)
		await RenderingServer.frame_post_draw
		var video_time:float=director.insert_video.clock()
		if video_time>=3.0 and not paused_once:
			paused_once=true
			main._set_paused(true)
			var at_pause:float=director.insert_video.clock()
			await get_tree().create_timer(.3,true).timeout
			assert(absf(director.insert_video.clock()-at_pause)<.05)
			main._set_paused(false)
			print("M04_VIDEO_PAUSE_OK")
		if video_time>=9.15 and not captured_nine:
			captured_nine=true
			assert(director.radio_overlay.in_video)
			assert(Dialogue.active_lines(video_time,true)[0].speaker=="阿姆罗")
			get_viewport().get_texture().get_image().save_png(folder.path_join("04_video_9s.png"))
			print("M04_VIDEO_9S ",video_time)
		if video_time>=10.15 and not captured_ten:
			captured_ten=true
			assert(Dialogue.active_lines(video_time,true).size()==2)
			get_viewport().get_texture().get_image().save_png(folder.path_join("05_video_10s.png"))
			print("M04_VIDEO_10S ",video_time)
		assert(Time.get_ticks_msec()-wall_start<30000)
	assert(captured_nine and captured_ten and director.insert_done)
	assert(main._strike_t==60.0)
	main._tick_pod_strike(.25)
	assert(is_equal_approx(main._strike_t,60.25))
	assert(not director.radio_overlay.in_video)
	for i in 3:await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join("06_resume_60s.png"))
	director.step(84.6,0.0)
	for i in 3:await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join("07_xi_line.png"))
	director.step(PS.TOTAL,0.0)
	main._strike_t=PS.TOTAL
	main._finish_pod_strike()
	assert(main.player.controls_enabled and Audio.current_bgm_track()=="car5p3")
	print("M04_RADIO_VIDEO_PASS 27 lines; video EOF resumes at 60s; battle handoff verified")
	main.free()
	get_tree().quit()
