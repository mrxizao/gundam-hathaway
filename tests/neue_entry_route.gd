extends Node3D
class EntryMain extends "res://scripts/main.gd":
 func _ready()->void:pass
func _ready()->void:
 Settings.begin_isolated();Game.reset();Game.match_mode=Game.MatchMode.VERSUS
 var main:=EntryMain.new();add_child(main);main.set_process(false);main.set_physics_process(false)
 main.world=WorldBuilder.new()
 main.units_root=Node3D.new();main.add_child(main.units_root)
 main.projectiles=Node3D.new();main.add_child(main.projectiles)
 main.chase=ChaseCamera.new();main.add_child(main.chase);main.chase.set_physics_process(false)
 FlightBody.use_placeholder=false
 main.player=PlayerController.new();main.player.profile=SuitProfile.neue_ziel();main.units_root.add_child(main.player)
 main.player.set_process(false);main.player.set_physics_process(false)
 main.hud=FlightHUD.new();main.hud.player=main.player;main.hud.camera=main.chase;main.add_child(main.hud)
 var position:=main.player.position
 main._begin_sortie_or_fight(true)
 assert(main.phase==main.Phase.SORTIE and Game.phase==Game.Phase.INTRO)
 assert(main._sortie_director.get_script()==preload("res://scripts/cinematics/neue_entry_director.gd"))
 assert(not main.player.controls_enabled)
 main._sortie_director.step(16.0)
 assert(main.phase==main.Phase.FIGHT and Game.phase==Game.Phase.FIGHT)
 assert(main.player.controls_enabled and main.hud.visible)
 assert(main.player.position==position)
 await get_tree().process_frame
 assert(main._sortie_director==null)
 main.world.free();main.world=null
 main.queue_free();await get_tree().process_frame
 for child in Audio.get_children():
  if child is AudioStreamPlayer:child.stop();child.stream=null
 for frame in 4:await get_tree().process_frame
 Settings.end_isolated()
 print("NEUE REAL ENTRY ROUTING / NATURAL FINISH: PASS")
 get_tree().quit()
