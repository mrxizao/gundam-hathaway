extends Node
const Timeline:=preload("res://scripts/data/m09_launch_script.gd")
class Runtime:
	extends "res://scripts/main.gd"
	func _ready()->void:
		set_process(false);set_physics_process(false)
class Pilot extends PlayerController:
	func _ready()->void:pass
var output:="C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/m09_launch"
var failures:=0
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
func shot(name:String)->void:
	for i in 8:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name+".png"))
func _ready()->void:
	Settings.begin_isolated();Game.reset();Game.set_phase(Game.Phase.INTRO);AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1200,720))
	var main:=Runtime.new();add_child(main)
	main.world=WorldBuilder.new();main.world.defer_initial_map=true;main.add_child(main.world)
	main.world.time_of_day=TimeOfDay.night()
	main.units_root=Node3D.new();main.projectiles=Node3D.new();main.add_child(main.units_root);main.add_child(main.projectiles)
	main.player=Pilot.new();main.player.profile=SuitProfile.penelope();main.player.max_hp=300;main.player.hp=300;main.units_root.add_child(main.player)
	main.chase=ChaseCamera.new();main.add_child(main.chase);main.chase.set_physics_process(false)
	main.hud=FlightHUD.new();main.hud.player=main.player;main.hud.camera=main.chase;main.add_child(main.hud)
	main._campaign_mission_id="M09";Game.active_mission=preload("res://scripts/data/mission_script.gd").m09();Game.match_mode=Game.MatchMode.CHALLENGE
	main._begin_sortie_or_fight(true)
	var director=main._sortie_director
	check(director.get_script().resource_path.ends_with("m09_launch_director.gd"),"M09 selects custom cinematic")
	check(not main.player.controls_enabled,"control locked during cinematic")
	for cue in [["01_cockpit_ready",2.0],["02_hangar",5.2],["03_impact_external",6.8],["04_impact_cockpit",9.4],["05_fade",12.2],["06_full_black",13.5],["07_base_ignition",14.5],["08_ascent",18.3],["09_sky_zoom",21.8],["10_side",22.1],["11_rear_hold",27.2]]:
		director.time=cue[1];director.pose(.016);await shot(cue[0])
		check(not main.player.controls_enabled,"controls remain gated at "+cue[0])
	var relative:Transform3D=director.camera.transform
	director.time=28.8;director.pose(.016)
	check(director.camera.transform.is_equal_approx(relative),"final rear camera holds for three seconds")
	director.step(.3)
	check(main.phase==main.Phase.FIGHT and main.player.controls_enabled,"control restored after full rear hold")
	check(absf(main.player.global_position.y*FlightHUD.ALT_DISPLAY_SCALE-700)<.01,"handoff HUD altitude is 700m")
	check(main.hud.visible,"HUD restored after blackout")
	print("M09_LAUNCH_GPU ","PASS" if failures==0 else "FAIL "+str(failures))
	if OS.get_cmdline_user_args().has("--realtime"):
		main._begin_sortie_or_fight(true)
		director=main._sortie_director
		var path:=output.path_join("frames");DirAccess.make_dir_recursive_absolute(path)
		var last:int=Time.get_ticks_msec();var start:int=last;var capture:=0
		while not director.cleaned:
			await get_tree().process_frame
			var now:int=Time.get_ticks_msec();var delta:float=minf((now-last)/1000.0,.1);last=now
			director.step(delta)
			if not director.cleaned and director.time>=float(capture)*.1:
				await RenderingServer.frame_post_draw
				var frame:=get_viewport().get_texture().get_image();frame.resize(960,576)
				frame.save_png(path.path_join("frame_%04d.png"%capture));capture+=1
		check(main.phase==main.Phase.FIGHT and main.player.controls_enabled,"realtime run hands over control")
		check(director.played.has("hit") and director.played.has("replay") and director.played.has("ignition"),"all timed sound cues fired")
		print("M09_LAUNCH_REALTIME ","PASS" if failures==0 else "FAIL", " wall_seconds=",(Time.get_ticks_msec()-start)/1000.0," frames=",capture)

	main._clear_match();main.free();Settings.end_isolated()
	await get_tree().process_frame
	get_tree().quit(0 if failures==0 else 1)
