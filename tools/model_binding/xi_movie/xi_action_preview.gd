extends Node3D
func freeze(n):
 n.set_process(false);n.set_physics_process(false)
 for c in n.get_children():freeze(c)
func _ready():
 var args=OS.get_cmdline_user_args()
 var out:String=args[0]
 DirAccess.make_dir_recursive_absolute(out)
 var u=FlightBody.new()
 u.profile=SuitProfile.xi()
 add_child(u)
 freeze(u)
 var env=WorldEnvironment.new()
 env.environment=Environment.new()
 env.environment.background_mode=Environment.BG_COLOR
 env.environment.background_color=Color(0.055,0.075,0.1)
 env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color=Color.WHITE
 env.environment.ambient_light_energy=0.8
 add_child(env)
 var light=DirectionalLight3D.new()
 light.rotation_degrees=Vector3(-35,130,0);light.light_energy=2
 add_child(light)
 var cam=Camera3D.new();cam.fov=38;cam.current=true;add_child(cam)
 for action in ["fly","shoot","slash","dash_f","dash_u","dash_cruise_r","burst_cruise","form_on"]:
  u.model_anim.player.stop();u._model_skel.reset_bone_poses()
  var actual:String=u.model_anim.playback_name(action)
  u.model_anim.player.play(actual)
  var clip:Animation=u.model_anim.player.get_animation(actual)
  u.model_anim.player.seek(clip.length*0.4,true)
  u.cruise_morph=1.0 if "cruise" in action else (0.4 if action=="form_on" else 0.0)
  u._weld_form_bones()
  for side in 2:
   cam.position=u.position+Vector3(32,3,52 if side==0 else -52)
   cam.look_at(u.position)
   await get_tree().process_frame
   await RenderingServer.frame_post_draw
   get_viewport().get_texture().get_image().save_png(out.path_join(action+"_"+str(side)+".png"))
 print("XI_ACTION_PREVIEW_PASS")
 u.queue_free()
 await get_tree().process_frame
 get_tree().quit()
