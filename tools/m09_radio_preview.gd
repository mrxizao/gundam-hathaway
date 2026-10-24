extends Node
## Isolated GPU verification of cinematic captions and uninterrupted mission BGM.
const Dialogue:=preload("res://scripts/data/m09_dialogue.gd")
class Runtime:
	extends "res://scripts/main.gd"
	func _ready()->void:
		set_process(false);set_physics_process(false)
class Pilot extends PlayerController:
	func _ready()->void:pass
var output:="C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/m09_radio"
var failures:=0
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
func shot(name:String)->Image:
	for i in 8:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frame:=get_viewport().get_texture().get_image()
	frame.save_png(output.path_join(name+".png"))
	return frame
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
	check(Audio.current_bgm_track()=="car5p3","M09 cinematic starts car5p3")
	check(Audio.battle_track_locked()=="car5p3","M09 mission BGM locked")
	for cue in [["01_hangar_radio",5.2],["02_impact_radio",6.8],["03_cockpit_radio",9.4],["04_fade_radio",12.2],["05_full_black",13.5],["06_ignition_radio",14.5],["07_ascent_radio",21.8],["08_rear_radio",27.2]]:
		director.time=cue[1];director.pose(.016)
		var frame:Image=await shot(cue[0])
		check(not main.player.controls_enabled,"controls gated at "+cue[0])
		if cue[0]=="05_full_black":
			var maximum:=0.0
			for y in frame.get_height():
				for x in frame.get_width():
					var pixel:=frame.get_pixel(x,y);maximum=maxf(maximum,maxf(pixel.r,maxf(pixel.g,pixel.b)))
			check(maximum==0,"blackout hides every UI pixel")
			print("M09_BLACK_RGB_MAX ",maximum)
	# Exercise the longest imported reflection in the real result card renderer.
	var long_line:Dictionary=Dialogue.packet(50);long_line["alpha"]=1.0
	var rows:Array[Dictionary]=[long_line]
	director.radio_panel.rows=rows;director.radio_panel.cockpit_view=false;director.radio_panel.queue_redraw()
	await shot("09_long_reflection")
	check(UILayout.wrap(ThemeDB.fallback_font,long_line.text,minf(860,director.radio_panel.size.x*.78)-36,20,4).size()<4,"long reflection fits without four-line truncation")
	var playback:AudioStreamPlayer=Audio._bgm_players[Audio._bgm_active]
	var stream:AudioStream=playback.stream;var index:int=Audio._bgm_active
	playback.seek(35.0)
	for i in 3:await get_tree().process_frame
	var before:float=playback.get_playback_position()
	director.time=28.8;director.step(.3)
	for i in 3:await get_tree().process_frame
	var after:float=playback.get_playback_position()
	check(main.phase==main.Phase.FIGHT and main.player.controls_enabled,"cinematic hands over control")
	check(Audio._bgm_active==index and playback.stream==stream,"handoff retains BGM player and stream")
	check(before>=35 and after>=before,"handoff continues playback instead of restarting")
	print("M09_BGM_CONTINUITY before=",before," after=",after," track=",Audio.current_bgm_track())
	print("M09_RADIO_GPU ","PASS" if failures==0 else "FAIL "+str(failures))
	main._clear_match();main.free();Settings.end_isolated()
	await get_tree().process_frame
	get_tree().quit(0 if failures==0 else 1)
