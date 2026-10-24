extends Node3D
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:
  failures+=1
  push_error(label)
func _ready():
 for id in SuitProfile.Id.values():
  var base:=SuitProfile.by_id(id)
  for form in base.form_count:
   var u=FlightBody.new()
   u.profile=SuitProfile.by_id_form(id,form)
   add_child(u)
   u.set_physics_process(false)
   var original:Vector3=u.position
   for angle in [Vector3.ZERO,Vector3(25,35,-18),Vector3(-30,-40,24)]:
    u.model_pivot.rotation_degrees=angle
    u.rotation_degrees=Vector3(12,70,0)
    u.fm.velocity=u.global_basis*Vector3(450,120,-700)
    for frame in 45:u._tick_plume_bend(1.0/60)
    u._sync_xi_plumes()
    u.PlumeMotion.sync_single(u)
    for item in u._plume_fx:
     var effect:Node3D=item["glow"]
     check(effect.transform.is_finite(),"finite effect transform")
     check(effect.position.distance_to(item["local_at"])<0.001,"source follows model")
     var native_axis:Vector3=item.get("motion_axis",Vector3.BACK)
     check((effect.basis*native_axis).normalized().dot(item["axis"])>0.999,"rotated nozzle axis")
     var wind:Vector3=u.global_basis.inverse()*(-u.fm.velocity)
     var crosswind:Vector3=wind-item["axis"]*wind.dot(item["axis"])
     var bend:Vector3=item.get("bend",u._plume_bend)
     if crosswind.length()>1:check(bend.dot(crosswind)>0,"bends downstream")
    if u._plume_fx.is_empty():
     check(u._afterburner_fx.basis.get_rotation_quaternion().angle_to(u.model_pivot.basis.get_rotation_quaternion())<0.001,"single jet follows pitch and bank")
    check(u.position==original,"visual only")
   print("PLUME_SUIT ",u.profile.display_name," form=",form," nozzles=",u._plume_fx.size())
   u.queue_free()
   await get_tree().process_frame
   await get_tree().process_frame
 print("ALL_PLUME_MOTION ",checks-failures," PASS / ",failures," FAIL")
 await get_tree().process_frame
 get_tree().quit(1 if failures>0 else 0)
