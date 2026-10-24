extends Node3D
var checks := 0
func check(value: bool, label: String):
 checks += 1
 if not value: push_error("TAIL FAIL: "+label)
 assert(value,label)
func freeze(n):
 n.set_process(false)
 n.set_physics_process(false)
 for c in n.get_children(): freeze(c)
func _ready():
 var args=OS.get_cmdline_user_args()
 var capture=args.size()>0
 var out=args[0] if capture else ""
 if capture: DirAccess.make_dir_recursive_absolute(out)
 var u=FlightBody.new()
 u.profile=SuitProfile.xi()
 add_child(u)
 freeze(u)
 u.position=Vector3(0,100,0)
 var env=WorldEnvironment.new()
 env.environment=Environment.new()
 env.environment.background_mode=Environment.BG_COLOR
 env.environment.background_color=Color(0.07,0.10,0.15)
 env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color=Color.WHITE
 env.environment.ambient_light_energy=0.8
 add_child(env)
 var light=DirectionalLight3D.new()
 light.rotation_degrees=Vector3(-35,130,0)
 light.light_energy=2.0
 add_child(light)
 var cam=Camera3D.new()
 cam.fov=42
 add_child(cam)
 cam.current=true
 check(u._plume_fx.size()==4,"four nozzles")
 for item in u._plume_fx:
  check(item.has("xi_bone"),"new mesh binding")
 var clock:=0.0
 for pose in ["hover","flight","cruise","saber"]:
  u.fm.hovering=pose=="hover"
  u.fm.boosting=pose!="hover"
  u.cruise_morph=1.0 if pose=="cruise" else 0.0
  u.model_anim.player.play("cruise_idle" if pose=="cruise" else ("slash" if pose=="saber" else "fly"))
  u.model_anim.player.advance(0.35)
  for frame in 20:
   u._tick_effects(1.0/60)
   u._weld_form_bones()
   u._sync_xi_plumes()
   for i in u._plume_fx.size():
    var item:Dictionary=u._plume_fx[i]
    var glow:Node3D=item["glow"]
    var desired:Transform3D=u.global_transform.affine_inverse()*u._model_skel.global_transform*u._model_skel.get_bone_global_pose(item["xi_bone"])*item["xi_offset"]
    check(glow.position.distance_to(desired.origin)<0.001,"nozzle position follows actual pose")
    check((glow.basis*Vector3.BACK).normalized().dot(item["axis"])>0.9999,"exhaust axis follows pose")
    check(absf(glow.basis.determinant()-1.0)<0.001,"world size preserved")
   if capture:await get_tree().process_frame
  if capture:
   for angle in 2:
    cam.position=u.position+(Vector3(0,4,52) if angle==0 else Vector3(32,10,45))
    cam.look_at(u.position)
    await get_tree().process_frame
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png(out.path_join(pose+"_"+str(angle)+".png"))
 print("XI_PLUME ",checks," PASS / 0 FAIL")
 u.queue_free()
 await get_tree().process_frame
 get_tree().quit()
