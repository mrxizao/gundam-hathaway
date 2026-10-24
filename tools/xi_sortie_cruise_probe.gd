extends Node
const Suite = preload("res://tests/suite_sortie_launch.gd")
const Timeline = preload("res://scripts/data/sortie_script.gd")
const Director = preload("res://scripts/cinematics/sortie_director.gd")
func _ready():
 Settings.begin_isolated();Game.reset();Game.set_phase(Game.Phase.INTRO)
 AudioServer.set_bus_mute(0,true)
 var out:String=OS.get_cmdline_user_args()[0]
 DirAccess.make_dir_recursive_absolute(out)
 for night in [false,true]:
  var owner=Suite.Owner.new();add_child(owner)
  owner.world=Suite.LaunchWorld.new();owner.world.time_of_day=TimeOfDay.night() if night else TimeOfDay.day();owner.add_child(owner.world)
  owner.units_root=Node3D.new();owner.add_child(owner.units_root)
  owner.projectiles=Node3D.new();owner.add_child(owner.projectiles)
  owner.chase=Camera3D.new();owner.add_child(owner.chase)
  owner.hud=Control.new();owner.add_child(owner.hud)
  owner.player=PlayerController.new();owner.player.profile=SuitProfile.xi();owner.player.is_player=true
  owner.units_root.add_child(owner.player);owner.player.set_physics_process(false)
  var director=Director.new();director.setup(owner,night);owner.add_child(director)
  for time in [4.8,5.3,5.9,6.5,7.3]:
   director.time=time;director.pose(0.0)
   assert(absf(director.actor.cruise_morph-Timeline.sample(owner.player.profile,time).cruise_morph)<.0001)
   if time<=6.5:assert(absf(director.actor.position.z-director.origin.z)<.001)
   if time>=5.3:assert(director.actor.position.y-director.origin.y>=64.9)
   for i in 3:await RenderingServer.frame_post_draw
   get_viewport().get_texture().get_image().save_png(out.path_join(("night" if night else "day")+"_"+str(time)+".png"))
  director.finish()
  assert(owner.player.cruise_morph==1.0)
  owner.free()
  await get_tree().process_frame
 print("XI_SORTIE_CRUISE_DAY_NIGHT_PASS")
 get_tree().quit()
