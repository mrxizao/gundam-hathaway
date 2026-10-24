extends Node3D
const Frame = preload("res://scripts/flight/flight_frame.gd")
var checks:=0
var failures:=0
func check(ok:bool, label:String):
 checks+=1
 if not ok:
  failures+=1
  push_error(label)
func _ready():
 Settings.begin_isolated()
 Game.active_map=null
 for hz in [30,60,120]:
  var previous:=Basis.IDENTITY
  for i in hz*4:
   var pitch:=deg_to_rad(-120.0*float(i)/(hz*4-1))
   var direction:=Basis(Vector3.RIGHT,pitch)*Vector3.FORWARD
   var next:Basis=Frame.facing(direction,previous,Vector3.UP,1.0/hz)
   check(next.is_finite() and absf(next.determinant()-1.0)<0.001,"finite vertical frame")
   check((-next.z).dot(direction)>0.9999,"nose follows across downward pole")
   check(previous.get_rotation_quaternion().angle_to(next.get_rotation_quaternion())<0.25,"no pole flip")
   previous=next
 for id in [SuitProfile.Id.XI,SuitProfile.Id.PENELOPE,SuitProfile.Id.ARIZEUS,SuitProfile.Id.REGZ_CUSTOM]:
  var body=PlayerController.new()
  body.profile=SuitProfile.by_id(id)
  body.placeholder_only=true
  add_child(body)
  body.set_physics_process(false)
  body.assist_on=true
  body.controls_enabled=true
  var basis:=Basis(Vector3.RIGHT,deg_to_rad(-60.0))
  body.global_basis=basis
  for altitude in [300.0,100.0,40.0]:
   body.position=Vector3(0,altitude,0)
   body.fm.velocity=Vector3(0,-200,0)
   check(not body._rescue_ground(1.0/60),"no early ground takeover")
   check(body.fm.velocity.y==-200,"descent remains available")
  body.position=Vector3(0,30,0)
  for i in 120:
   body.fm.velocity=Vector3(500,-200,0)
   check(body._rescue_ground(1.0/60),"floor protection applies")
   check(body.fm.velocity.y==0 and body.fm.velocity.x==500,"floor slides without forced ascent")
   check(body.global_basis.is_equal_approx(basis),"ground never tilts nose")
  body.position.y=300
  body.fm.velocity=Vector3(0,-10000,0)
  check(body._rescue_ground(0.05),"high speed boundary step limited")
  check(absf(body.position.y+body.fm.velocity.y*0.05-30)<0.01,"high speed lands at boundary")
  var cam=ChaseCamera.new()
  add_child(cam)
  cam.set_physics_process(false)
  cam.target=body
  cam._fpv_blend=1.0
  cam.roll_blend=0.0
  cam.global_basis=Basis.IDENTITY
  for degree in 121:
   body.global_basis=Basis(Vector3.RIGHT,deg_to_rad(-float(degree)))
   var next:Basis=cam._desired_basis()
   check(next.is_finite(),"camera remains finite in dive")
   check(cam.global_basis.get_rotation_quaternion().angle_to(next.get_rotation_quaternion())<0.25,"camera does not flip at vertical")
   cam.global_basis=next
  cam.free()
  body.queue_free()
 await get_tree().process_frame
 print("LOW_PITCH ",checks-failures," PASS / ",failures," FAIL")
 get_tree().quit(1 if failures else 0)
