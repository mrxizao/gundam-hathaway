extends Node
var writes := 0
func _ready():
 var u=FlightBody.new()
 u.profile=SuitProfile.penelope()
 add_child(u)
 u.set_physics_process(false)
 var m=u._form_weld
 u.model_anim.player.mixer_applied.connect(func():
  if m.tail_angles.length()>0.03:
   var q=u._model_skel.get_bone_pose_rotation(m._tail)
   assert(absf(q.dot(m._tail_rest))<0.9999,"animation overwrote tail")
   writes+=1
 )
 for form in 2:
  u.cruise_morph=float(form)
  for frame in 100:
   u.rotate_y(0.025)
   u._tick_effects(1.0/60)
   await get_tree().process_frame
 assert(writes>100,"mixer actually applied moving tail")
 print("PENELOPE_TAIL_LIVE ",writes," moving mixer frames PASS")
 u.queue_free()
 await get_tree().process_frame
 get_tree().quit()
