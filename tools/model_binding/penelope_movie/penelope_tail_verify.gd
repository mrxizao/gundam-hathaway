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
 u.profile=SuitProfile.penelope()
 add_child(u)
 freeze(u)
 u.position=Vector3(0,100,0)
 var motion=u._form_weld
 check(motion._tail>=0,"real tail bone")
 check(u._model_skel.get_bone_children(motion._tail).size()>0,"tail parts attached")
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
 for form in 2:
  u.cruise_morph=float(form)
  motion.weld(float(form))
  motion._sampled=false
  motion.tail_angles=Vector3.ZERO
  motion._tail_speed=Vector3.ZERO
  u.velocity=Vector3(0,0,-500)
  motion.step_motion(1.0/60)
  var root_position=u.position
  var tail_position=u._model_skel.get_bone_pose_position(motion._tail)
  for mode in ["rest","turn","pitch","accelerate","recover"]:
   for frame in 90:
    if mode=="turn": u.rotate_y(0.025)
    if mode=="pitch": u.rotate_object_local(Vector3.RIGHT,0.016)
    if mode=="accelerate": u.velocity+=u.global_basis*Vector3(0,0,-15)
    motion.step_motion(1.0/60)
    motion.weld(float(form))
    check(motion.tail_angles.is_finite() and motion.tail_angles.length()<0.42,"bounded")
    if frame==89:
     if mode=="rest" or mode=="recover":check(motion.tail_angles.length()<0.002,"settles")
     else:check(motion.tail_angles.length()>0.03,"responds "+mode)
     check(u.position==root_position,"visual only")
     check(u._model_skel.get_bone_pose_position(motion._tail).is_equal_approx(tail_position),"root hinge fixed")
    if capture:
     cam.position=u.position+u.global_basis*Vector3(34,20,43)
     cam.look_at(u.position+Vector3(0,2,0))
     await get_tree().process_frame
     if frame%6==0:
      await RenderingServer.frame_post_draw
      get_viewport().get_texture().get_image().save_png(out.path_join("%d_%s_%02d.png"%[form,mode,frame]))
  var q=u._model_skel.get_bone_pose_rotation(motion._tail)
  for repeat in 10: motion.weld(float(form))
  check(absf(q.dot(u._model_skel.get_bone_pose_rotation(motion._tail)))>0.99999,"no accumulation")
 print("PENELOPE_TAIL ",checks," PASS / 0 FAIL")
 u.queue_free()
 await get_tree().process_frame
 get_tree().quit()
