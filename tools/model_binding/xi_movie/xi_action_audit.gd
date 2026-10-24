extends Node3D
func freeze(node):
 node.set_process(false)
 node.set_physics_process(false)
 for child in node.get_children():freeze(child)
func matrix(t:Transform3D)->Array:
 return [t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z,0,0,0,1]
func _ready():
 var body=FlightBody.new()
 body.profile=SuitProfile.xi()
 add_child(body)
 freeze(body)
 var sk:Skeleton3D=body._model_skel
 var result:Dictionary={"bones":[],"rest":[],"actions":{},"runtime":{ }}
 for i in sk.get_bone_count():
  result.bones.append(str(sk.get_bone_name(i)))
  result.rest.append(matrix(sk.get_bone_global_rest(i)))
 for action in body.model_anim.actions:
  result.runtime[str(action)]=body.model_anim.playback_name(str(action))
 for action in body.model_anim.player.get_animation_list():
  if action=="RESET":continue
  var clip:Animation=body.model_anim.player.get_animation(action)
  var frames:Array=[]
  body.model_anim.player.stop()
  sk.reset_bone_poses()
  body.model_anim.player.play(action)
  for frame in 9:
   body.model_anim.player.seek(clip.length*frame/8.0,true)
   body.cruise_morph=1.0 if "cruise" in action else 0.0
   if action in ["form_on","cruise_on"]:body.cruise_morph=frame/8.0
   elif action=="form_off":body.cruise_morph=1.0-frame/8.0
   body._weld_form_bones()
   sk.force_update_all_bone_transforms()
   var poses:Array=[]
   for i in sk.get_bone_count():poses.append(matrix(sk.get_bone_global_pose(i)))
   frames.append(poses)
  result.actions[str(action)]=frames
 var args=OS.get_cmdline_user_args()
 var file=FileAccess.open(args[0],FileAccess.WRITE)
 file.store_string(JSON.stringify(result))
 print("XI_ACTION_AUDIT ",result.actions.size()," clips / ",sk.get_bone_count()," bones")
 body.queue_free()
 await get_tree().process_frame
 get_tree().quit()
