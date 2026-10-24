extends Node3D
var kept:Array[Resource]=[]
var passed:=0
var failures:=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failures+=1;push_error("THEME_FAIL "+label)
func _ready()->void:
 Settings.begin_isolated()
 get_window().mode=Window.MODE_WINDOWED
 get_window().size=Vector2i(1600,900)
 for file in DirAccess.get_files_at("res://shaders"):
  if file.ends_with(".gdshader"):kept.append(load("res://shaders/"+file))
 Game.reset()
 Game.active_mission=null
 Settings.battle_playlist=[]
 Audio.lock_battle_track("")
 var old=load("res://tests/t.gd").new()
 load("res://tests/suite_battle_bgm_roster.gd").run(old,self)
 print("EXISTING_ROSTER PASS ",old.passed," FAIL ",old.failed)
 failures+=old.failed
 var keys=["thunderbolt_main_theme","yes_girl"]
 var suits=[SuitProfile.Id.FULL_ARMOR_TB,SuitProfile.Id.PSYCHO_ZAKU_TB]
 var main_script=load("res://scripts/main.gd")
 var main=main_script.new()
 Settings.battle_bgm_pick="tracer"
 for index in 2:
  var key:String=keys[index]
  check(SoundBank.is_battle_pick(key),"Track available for selection")
  check(SoundBank.battle_track_label(key)!=key,"Japanese title registered")
  check(Settings.toggle_playlist_track(key)==Settings.PLAYLIST_ADDED,"Track can be added to saved playlist")
  var resource:AudioStream=load(SoundBank.bgm_path(key))
  check(resource!=null and resource.get_length()>60,"MP3 decodes completely")
  print("AUDIO_DURATION ",key," ",resource.get_length())
  check(not resource.loop,"Imported source remains non-looping")
  for mode in [Game.MatchMode.VERSUS,Game.MatchMode.LAN]:
   Game.active_suit=suits[index];Game.match_mode=mode
   main.set("phase",main_script.Phase.MENU);main._start_fight()
   check(Audio.current_bgm_track()==key,"Actual battle entry selects the pilot's theme")
   check(Audio.battle_track_locked()==key,"Pilot theme stays locked for this battle")
   check(Audio._bgm_players[Audio._bgm_active].stream.loop,"Active theme loops throughout battle")
  await get_tree().create_timer(.25).timeout
  var player:AudioStreamPlayer=Audio._bgm_players[Audio._bgm_active]
  check(player.playing and player.get_playback_position()>0,"Real audio playback advances")
  print("AUDIO_PROGRESS ",key," ",player.get_playback_position())
  check(not resource.loop,"Looping did not mutate shared MP3 resource")
 Game.active_suit=SuitProfile.Id.XI;Game.match_mode=Game.MatchMode.VERSUS
 main.set("phase",main_script.Phase.MENU);main._start_fight()
 check(Audio.battle_track_locked()=="" and Audio.current_bgm_track()=="tracer","Changing to another suit restores normal selected music")
 check(not Audio._bgm_players[Audio._bgm_active].stream.loop,"Normal battle rotation is not locked")
 main.free()
 if not OS.get_cmdline_user_args().is_empty():
  var menu_script=load("res://scripts/ui/main_menu.gd")
  var menu=menu_script.new()
  add_child(menu)
  menu.stage=menu_script.Stage.BGM;menu.bgm_sub=menu_script.BGM_SUB_LIST
  menu.playlist_row=menu.bgm_pick_keys().find("thunderbolt_main_theme")
  menu._home_view.selected_only=true
  menu.set_process(false)
  for frame in 15:await get_tree().process_frame
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
  menu.queue_free()
 print("THUNDERBOLT_MUSIC PASS ",passed," FAIL ",failures)
 Audio.stop_bgm(0)
 Audio.stop_preview(0)
 for player in Audio._bgm_players:player.stop();player.stream=null
 await get_tree().create_timer(.12).timeout
 Settings.end_isolated()
 get_tree().quit(failures)
