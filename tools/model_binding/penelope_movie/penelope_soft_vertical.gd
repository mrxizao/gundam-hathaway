extends Node3D
func _ready():
 var u=FlightBody.new()
 u.profile=SuitProfile.penelope()
 u.is_player=true
 add_child(u)
 u.set_physics_process(false)
 u.fm.hovering=true
 u._hover_pose=0
 u.penelope_cruise_enabled=true
 u.cruise_morph=1
 var checks:=0
 for hz in [30,60,120]:
  for direction in [-1.0,1.0]:
   var m=u._form_weld
   m._vertical_pitch=0.0
   m._vertical_pitch_speed=0.0
   u._qb_dir=Vector3.UP*direction
   var previous:=0.0
   var peak:=0.0
   var end_pitch:=0.0
   for frame in hz*2:
    var elapsed:float=frame/float(hz)
    u._qb_timer=maxf(u.QB_TIME-elapsed,0)
    u._tick_effects(1.0/hz)
    var pitch:float=u.model_pivot.rotation_degrees.x
    assert(absf(pitch-previous)*hz<225,"angular speed bounded")
    assert(pitch*direction>=-0.01,"no reverse snap")
    if elapsed>=u.QB_TIME and end_pitch==0.0:end_pitch=absf(pitch)
    peak=maxf(peak,absf(pitch))
    previous=pitch
    checks+=2
   assert(peak>40 and peak<56,"clear but softer pitch")
   assert(end_pitch>35,"return continues after dash")
   assert(absf(previous)<0.02,"settles level")
   print("SOFT hz=",hz," dir=",direction," peak=",peak," end=",end_pitch)
 print("PENELOPE_SOFT_VERTICAL ",checks," PASS / 0 FAIL")
 u.queue_free()
 await get_tree().process_frame
 get_tree().quit()
