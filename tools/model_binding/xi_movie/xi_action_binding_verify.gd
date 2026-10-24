extends Node3D
const PARTS = {"tripo_part_28":"Shin.L","tripo_part_66":"Shin.L","tripo_part_73":"Shin.L","tripo_part_84":"Shin.L","tripo_part_86":"Shin.L","tripo_part_17":"Chest","tripo_part_38":"Chest","tripo_part_43":"UpperArm.L","tripo_part_72":"Shin.R","tripo_part_107":"Shoulder.L"}
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
    check(bone_name==PARTS[str(mesh.name)] and weights[i]>0.999,"repaired part uses its anatomical carrier")
   var bind:int=bones[0]
   samples.append({"mesh":mesh,"bind":bind,"point":arrays[Mesh.ARRAY_VERTEX][0],"bone":sk.find_bone(PARTS[str(mesh.name)])})
 check(found==10,"all ten repaired parts present")
 for action_name in body.model_anim.actions:
  var action:String=body.model_anim.playback_name(str(action_name))
  check(body.model_anim.player.has_animation(action),"action exists "+action)
  body.model_anim.player.stop()
  sk.reset_bone_poses()
  body.model_anim.player.play(action)
  var clip:Animation=body.model_anim.player.get_animation(action)
  for frame in 31:
   body.model_anim.player.seek(clip.length*frame/30.0,true)
   body.cruise_morph=1.0 if "cruise" in action else 0.0
   if action in ["form_on","cruise_on"]:body.cruise_morph=frame/30.0
   elif action=="form_off":body.cruise_morph=1.0-frame/30.0
   body._weld_form_bones()
   sk.force_update_all_bone_transforms()
   for sample in samples:
    var mesh:MeshInstance3D=sample.mesh
    var xf:Transform3D=sk.get_bone_global_pose(sample.bone)*mesh.skin.get_bind_pose(sample.bind)
    var attached:Vector3=sk.get_bone_global_pose(sample.bone).affine_inverse()*(xf*sample.point)
    var expected:Vector3=mesh.skin.get_bind_pose(sample.bind)*sample.point
    check(attached.distance_to(expected)<0.0001,"part remains on its carrier throughout "+action)
 check(str(sk.get_bone_name(body._plume_fx[2].xi_bone))=="Shin.L","left calf plume follows repaired joint")
 print("XI_ACTION_BINDINGS ",checks-failures," PASS / ",failures," FAIL")
 body.queue_free()
 await get_tree().process_frame
 get_tree().quit(1 if failures else 0)
