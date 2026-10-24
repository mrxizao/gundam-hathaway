extends Node3D
class FakeWorld extends Node3D:
 var time_of_day:TimeOfDay
class FakeMain extends Node3D:
 var units_root:Node3D
 var projectiles:Node3D
 var chase:ChaseCamera
 var hud:Control
 var player:PlayerController
 var world:FakeWorld
var checks:=0
func check(value:bool,label:String)->void:
 if not value:push_error(label);get_tree().quit(1)
 assert(value,label)
 checks+=1
func _ready()->void:
 Settings.begin_isolated();Settings.low_end_60=true
 var main:=FakeMain.new();add_child(main)
 main.units_root=Node3D.new();main.add_child(main.units_root)
 main.projectiles=Node3D.new();main.add_child(main.projectiles)
 main.chase=ChaseCamera.new();main.add_child(main.chase);main.chase.set_physics_process(false)
 main.hud=Control.new();main.add_child(main.hud)
 main.world=FakeWorld.new();main.add_child(main.world)
 FlightBody.use_placeholder=true
 main.player=PlayerController.new();main.player.profile=SuitProfile.gp03d();main.units_root.add_child(main.player)
 main.player.set_physics_process(false);main.player.set_process(false);main.player.position=Vector3(500,1000,200);main.player.controls_enabled=true
 FlightBody.use_placeholder=false
 var old_track:=Audio.current_bgm_track()
 var previous_position:=main.player.position
 var director:=preload("res://scripts/cinematics/gp03d_entry_director.gd").new()
 director.setup(main);main.add_child(director)
 check(director.actor.model_root.find_child("GP03D_V2",true,false)!=null,"New model used by cinematic actor")
 check(director.music.playing and director.music.stream==load(SoundBank.bgm_path("men_of_destiny")),"MEN OF DESTINY plays during the cinematic")
 check(director.eye_marker.get_parent().name=="tripo_part_48_001","Glow bound to the user-marked eye mesh")
 check(director.music.bus==Settings.BUS_BGM,"Music respects BGM volume")
 check(not main.player.controls_enabled and not main.hud.visible,"Combat controls and HUD suspended")
 check(main.units_root.process_mode==Node.PROCESS_MODE_DISABLED,"AI and combat units paused")
 check(director.stage.get_child_count()<8,"No airport/city built for space insert")
 var timeline=preload("res://scripts/data/sortie_script.gd")
 check(timeline.supported(SuitProfile.gp03d()),"GP03D included in launch roster")
 check(not timeline.supported(SuitProfile.gp03s()),"GP03S does not incorrectly inherit MA intro")
 check(is_equal_approx(timeline.duration(SuitProfile.gp03d()),12.0),"Reference duration")
 check(timeline.version(SuitProfile.gp03d(),false).size()==4,"Four reference phases")
 check(timeline.stage_at(SuitProfile.gp03d(),6.9)==2,"Shared timeline agrees with core shot")
 check(is_equal_approx(timeline.duration(SuitProfile.xi()),9.7),"Existing Xi duration unchanged")
 check(is_equal_approx(timeline.duration(SuitProfile.penelope()),16.0),"Existing runway duration unchanged")
 var sequence=preload("res://scripts/data/gp03d_entry_script.gd")
 for sample_time in [0.0,2.0,3.5,4.15,4.85,5.2,6.2,6.6,7.12,10.8,12.0]:
  director.time=sample_time;director.pose(.016)
  var sample:Dictionary=sequence.sample(sample_time)
  if sample.shot==1:check(sample.camera.y<sample.target.y,"Low angle nozzle shot stays beneath engine cluster")
  if sample.shot==1:check(sample.camera.x< -20.0 and sample.camera.x<sample.target.x-20.0,"Nozzle shot remains on the machine left side")
  check(director.last_shot==sample.shot,"Shot dispatch at %.2f"%sample_time)
  check(director.camera.position.is_finite() and director.actor.position.is_finite(),"Finite transforms")
  if DisplayServer.get_name()!="headless" and sample_time in [2.0,3.5,4.85,7.12,10.8]:
   for frame in 12:await get_tree().process_frame
   await RenderingServer.frame_post_draw
   get_viewport().get_texture().get_image().save_png("C:/Users/MSIPC/Documents/Codex/2026-10-07/c-users-msipc-documents-gundam-2/work/gp03d_entry/shot_%.1f.png"%sample_time)
 check(director.actor.model_root.find_child("DistantRealModel",true,false).visible==false,"Detailed close-up on low preset")
 for t in [0.0,1.0,2.0,3.14]:check(is_zero_approx(sequence.sample(t).streaks),"No speed lines before central line")
 for sample_time in [5.15,5.35,5.6]:
  check(sequence.sample(sample_time+.1).camera.distance_to(sequence.sample(sample_time).camera)>.5,"No two-second nozzle stop")
 for sample_time in [8.9,10.0,11.5,12.0]:
  var value:Dictionary=sequence.sample(sample_time)
  check(value.camera.y<value.target.y-30.0,"Final camera looks up from beneath GP03")
 check(sequence.sample(11.5).camera.y<sequence.sample(9.0).camera.y-15.0,"Final shot pulls the camera downward")
 for key in sequence.KEYS:
  var t:float=key[0]
  if t<=sequence.REVEAL or t>=sequence.DURATION:continue
  var a:Dictionary=sequence.sample(t-.0001);var b:Dictionary=sequence.sample(t+.0001)
  check(a.camera.distance_to(b.camera)<.04,"Uncut camera path across key %.2f"%t)
  check(a.target.distance_to(b.target)<.04,"Continuous look target")
 check(sequence.sample(4.85).camera.distance_to(Vector3(-38,-20,66))<.001,"Camera reaches nozzle side in 0.7 seconds")
 # Sample every rendered frame at 30, 60 and 144 Hz, rather than only keyframes.
 for fps in [30,60,144]:
  var continuous:=true
  var previous:Dictionary=sequence.sample(sequence.REVEAL)
  for frame in range(ceili(sequence.REVEAL*fps)+1,int(sequence.DURATION*fps)+1):
   var value:Dictionary=sequence.sample(float(frame)/fps)
   var direction:Vector3=(value.target-value.camera).normalized()
   var old_direction:Vector3=(previous.target-previous.camera).normalized()
   continuous=continuous and value.camera.is_finite() and value.target.is_finite() and value.fov>=29.0 and value.fov<=53.0
   continuous=continuous and value.camera.distance_to(previous.camera)<360.0/fps and absf(value.fov-previous.fov)<80.0/fps
   continuous=continuous and direction.angle_to(old_direction)<deg_to_rad(360.0/fps)
   previous=value
  check(continuous,"Every-frame camera continuity at %d FPS"%fps)
 var count:=[0]
 director.finished.connect(func():count[0]+=1)
 director.finish();director.finish()
 check(not director.music.playing,"Cinematic music stops after cleanup")
 check(Audio.current_bgm_track()==old_track,"Existing battle/menu track state unchanged")
 check(count[0]==1,"Completion signal exactly once")
 check(main.player.controls_enabled and main.hud.visible,"Control/HUD restored after finish or skip")
 check(main.units_root.process_mode==Node.PROCESS_MODE_INHERIT,"AI resumes")
 check(main.player.position==previous_position,"Cinematic leaves actual map spawn untouched")
 director.queue_free();await get_tree().process_frame
 var skipped:=preload("res://scripts/cinematics/gp03d_entry_director.gd").new()
 skipped.setup(main);main.add_child(skipped);skipped.time=.8
 var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_SPACE
 skipped._unhandled_input(key)
 check(skipped.cleaned and main.player.controls_enabled,"Space skip cleans up and returns control")
 skipped.queue_free();main.queue_free()
 for frame in 4:await get_tree().process_frame
 Settings.end_isolated()
 print("GP03D ENTRY: ",checks," PASS")
 get_tree().quit()
