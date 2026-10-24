extends Node
const MAIN:=preload("res://scripts/main.gd")
class Runtime:
	extends "res://scripts/main.gd"
	func _ready()->void:
		staged_startup=true
		_build_world()
		_build_camera()
		_build_ui()
		set_process(false)
		set_physics_process(false)
var fails:=0
func check(value:bool,label:String)->void:
	if not value:
		fails+=1
		push_error(label)
func freeze(n:Node)->void:
	n.set_process(false)
	n.set_physics_process(false)
	for child in n.get_children():freeze(child)
func _ready()->void:
	Settings.begin_isolated()
	AudioServer.set_bus_mute(0,true)
	Game.reset()
	var app:=Runtime.new()
	add_child(app)
	check(app._resolve_campaign_match("M03"),"M03 resolves")
	app._begin_launch()
	freeze(app)
	check(Audio.current_bgm_track()=="car5p3","launch track is PENELOPE")
	check(app._strike_bgm_live,"launch carry flag set")
	var index:int=Audio._bgm_active
	var player:AudioStreamPlayer=Audio._bgm_players[index]
	var stream:AudioStream=player.stream
	player.seek(32.0)
	await get_tree().create_timer(.15).timeout
	var progress:float=player.get_playback_position()
	check(progress>30.0,"nonzero launch playback position")
	print("M03_MUSIC_LAUNCH seconds=",progress," player=",index)
	await app._swap_to_orbit()
	check(app._orbit_swap_done,"real LEO map transition completed")
	check(Audio._bgm_active==index and player.stream==stream,"map transition keeps the same player and stream")
	check(player.get_playback_position()>=progress-.05,"map transition does not rewind")
	progress=player.get_playback_position()
	print("M03_MUSIC_ORBIT seconds=",progress," player=",Audio._bgm_active)
	app._finish_launch()
	freeze(app)
	check(app.phase==MAIN.Phase.FIGHT,"actual flight handoff completed")
	check(Audio._bgm_active==index and player.stream==stream,"spawn and flight handoff keep the player and stream")
	check(player.get_playback_position()>=progress-.05,"flight handoff does not rewind")
	check(Audio.battle_track_locked()=="car5p3","mission retains PENELOPE lock")
	check(not app._strike_bgm_live,"carry flag consumed once")
	print("M03_MUSIC_FLIGHT seconds=",player.get_playback_position()," player=",Audio._bgm_active)
	app._clear_match()
	app.free()
	Audio.stop_bgm(0.0)
	for p:AudioStreamPlayer in Audio._bgm_players:p.stream=null
	Settings.end_isolated()
	print("M03_CONTINUOUS_MUSIC ","PASS" if fails==0 else "FAIL "+str(fails))
	get_tree().quit(0 if fails==0 else 1)
