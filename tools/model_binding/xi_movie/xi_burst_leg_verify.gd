extends Node3D
const PARTS = ["tripo_part_28","tripo_part_66","tripo_part_73","tripo_part_84","tripo_part_86"]
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:
  failures+=1
  push_error(label)
func freeze(node):
 node.set_process(false)
 node.set_physics_process(false)
 for child in node.get_children():freeze(child)
func _ready():
 var body=FlightBody.new()
 body.profile=SuitProfile.xi()
 add_child(body)
 freeze(body)
 var sk:Skeleton3D=body._model_skel
 var found:=0
 var samples:Array=[]
 for mesh:MeshInstance3D in body.model_root.find_children("*","MeshInstance3D",true,false):
  if not str(mesh.name) in PARTS:continue
  found+=1
  for surface in mesh.mesh.get_surface_count():
   var arrays=mesh.mesh.surface_get_arrays(surface)
   var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
   var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
   for i in range(0,bones.size(),4):
    var bind:int=bones[i]
    var bone_name:String=mesh.skin.get_bind_name(bind)
    if bone_name.is_empty():bone_name=str(sk.get_bone_name(mesh.skin.get_bind_bone(bind)))
    check(bone_name=="Shin.L" and weights[i]>0.999,"calf rigid weights belong to Shin.L")
   var bind:int=bones[0]
   samples.append({"mesh":mesh,"bind":bind,"point":arrays[Mesh.ARRAY_VERTEX][0]})
 check(found==5,"all five calf parts present")
 for action in ["burst","burst_cruise","fly","form_on","form_off","slash"]:
  check(body.model_anim.has(action),"action exists "+action)
  body.model_anim.player.play(action)
  var clip:Animation=body.model_anim.player.get_animation(action)
  for frame in 31:
   body.model_anim.player.seek(clip.length*frame/30.0,true)
   body._weld_form_bones()
   sk.force_update_all_bone_transforms()
   for sample in samples:
    var mesh:MeshInstance3D=sample.mesh
    var xf:Transform3D=sk.get_bone_global_pose(sk.find_bone("Shin.L"))*mesh.skin.get_bind_pose(sample.bind)
    var attached:Vector3=sk.get_bone_global_pose(sk.find_bone("Shin.L")).affine_inverse()*(xf*sample.point)
    var expected:Vector3=mesh.skin.get_bind_pose(sample.bind)*sample.point
    check(attached.distance_to(expected)<0.0001,"calf remains attached throughout "+action)
 check(str(sk.get_bone_name(body._plume_fx[2].xi_bone))=="Shin.L","left calf plume follows repaired joint")
 var args=OS.get_cmdline_user_args()
 if args.size()>0:
  var out:String=args[0]
  DirAccess.make_dir_recursive_absolute(out)
  var env=WorldEnvironment.new()
  env.environment=Environment.new()
  env.environment.background_mode=Environment.BG_COLOR
  env.environment.background_color=Color(0.055,0.075,0.1)
  env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
  env.environment.ambient_light_color=Color.WHITE
  env.environment.ambient_light_energy=0.9
  add_child(env)
  var light=DirectionalLight3D.new()
  light.rotation_degrees=Vector3(-35,130,0)
  light.light_energy=2.0
  add_child(light)
  var cam=Camera3D.new()
  add_child(cam)
  cam.current=true
  cam.fov=40
  cam.position=body.position+Vector3(32,5,55)
  cam.look_at(body.position)
  for action in ["burst","burst_cruise"]:
   body.model_anim.player.play(action)
   var clip:Animation=body.model_anim.player.get_animation(action)
   for frame in [0,15,30]:
    body.model_anim.player.seek(clip.length*frame/30.0,true)
    body.cruise_morph=1.0 if action=="burst_cruise" else 0.0
    body._weld_form_bones()
    body._sync_xi_plumes()
    await get_tree().process_frame
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png(out.path_join(action+"_"+str(frame)+".png"))
 print("XI_BURST_LEG ",checks-failures," PASS / ",failures," FAIL")
 body.queue_free()
 await get_tree().process_frame
 get_tree().quit(1 if failures else 0)
