extends Node3D
var checks:=0
func check(ok:bool,label:String):
 checks+=1
 assert(ok,label)
func _ready():
 var u=FlightBody.new()
 u.profile=SuitProfile.penelope()
 add_child(u)
 u.set_physics_process(false)
 var m=u._form_weld
 for form in [0.0,1.0]:
  m.weld(form)
  for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN,Vector3(-1,1,-1).normalized()]:
   u._qb_timer=0.25
   u._qb_dir=direction
   var target:Vector3=m.motion_target(u,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,0,form)
   check(target.length()>0.08,"all dash directions respond")
   check(Vector3(target.x/0.56,target.y/0.42,target.z/0.16).length()<=1.001,"combined limits")
   if absf(direction.y)>0.9:check(signf(target.x)==-signf(direction.y),"vertical direction")
   elif absf(direction.x)>0.9:check(signf(target.y)==-signf(direction.x),"lateral direction")
  u._qb_timer=0
  var rest:Vector3=m.motion_target(u,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,0,form)
  check(rest.length()<0.001,"steady flight settles")
  var slip:Vector3=m.motion_target(u,Vector3.ZERO,Vector3.ZERO,Vector3(400,0,-600),0,form)
  check(slip.y< -0.03,"side slip")
  var tilt:Vector3=m.motion_target(u,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,4,form)
  check(tilt.x< -0.09,"visible hull pitch lag")
  u._gun_recoil_clock=0
  check(m.motion_target(u,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,0,form).x< -0.03,"gun response")
  u._gun_recoil_clock=1
  u.saber_state=u.SaberState.CHARGE
  u._saber_visual_clock=0.26
  var windup:Vector3=m.motion_target(u,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,0,form)
  u._saber_visual_clock=0.44
  var slash:Vector3=m.motion_target(u,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,0,form)
  check(windup.y>0.08 and slash.y< -0.10,"windup reverses into cut")
  u.saber_state=u.SaberState.IDLE
  u._saber_visual_tail=0
  for hz in [30,60,120]:
   m.tail_angles=Vector3.ZERO
   m._tail_speed=Vector3.ZERO
   m._sampled=false
   u._qb_dir=Vector3.RIGHT
   u._qb_timer=0.25
   for frame in hz/2:
    m.step_motion(1.0/hz)
    m.weld(form)
    check(m.tail_angles.is_finite() and absf(m.tail_angles.y)<0.44,"stable real spring")
   check(absf(m.tail_angles.y)>0.20,"visible lateral dash")
   u._qb_timer=0
   for frame in hz*2:m.step_motion(1.0/hz)
   check(m.tail_angles.length()<0.001,"damped recovery")
 print("PENELOPE_TAIL_ACTIONS ",checks," PASS / 0 FAIL")
 u.queue_free()
 await get_tree().process_frame
 get_tree().quit()
