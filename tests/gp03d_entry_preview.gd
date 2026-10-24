extends "res://tests/gp03d_entry_probe.gd"
var preview:Node
const CAPTURE_FPS:=60.0
var frames:=0
var samples:Array[Dictionary]=[]
func _ready()->void:
 Settings.begin_isolated();Settings.low_end_60=false
 var main:=FakeMain.new();add_child(main)
 main.units_root=Node3D.new();main.add_child(main.units_root)
 main.projectiles=Node3D.new();main.add_child(main.projectiles)
 main.chase=ChaseCamera.new();main.add_child(main.chase);main.chase.set_physics_process(false)
 main.hud=Control.new();main.add_child(main.hud)
 main.world=FakeWorld.new();main.add_child(main.world)
 FlightBody.use_placeholder=true
 main.player=PlayerController.new();main.player.profile=SuitProfile.gp03d();main.units_root.add_child(main.player)
 main.player.set_physics_process(false);main.player.set_process(false)
 FlightBody.use_placeholder=false
 preview=preload("res://scripts/cinematics/gp03d_entry_director.gd").new()
 preview.setup(main);main.add_child(preview)
func _process(_delta:float)->void:
 if preview==null:return
 preview.time=minf(float(frames)/CAPTURE_FPS,preview.Sequence.DURATION)
 preview.pose(1.0/CAPTURE_FPS)
 samples.append({"frame":frames,"time":preview.time,"camera":var_to_str(preview.camera.position),"fov":preview.camera.fov,"eye":var_to_str(preview.camera.unproject_position(preview.eye_marker.global_position)),"shot":preview.last_shot})
 if frames==214:
  var head:MeshInstance3D=preview.actor.model_root.find_child("tripo_part_35",true,false)
  print("PIVOT ",preview.actor.model_pivot.rotation_degrees," HEAD CENTER ",preview.actor.to_local(head.global_transform*head.mesh.get_aabb().get_center()))
 frames+=1
 if frames>int(preview.Sequence.DURATION*CAPTURE_FPS)+1:
  var report:=FileAccess.open("C:/Users/MSIPC/Documents/Codex/2026-10-07/c-users-msipc-documents-gundam-2/work/gp03d_frame_review/frame_metrics.json",FileAccess.WRITE)
  report.store_string(JSON.stringify(samples))
  if is_instance_valid(preview.music):preview.music.stop();preview.music.stream=null
  print("GP03D PREVIEW MOVIE: ",frames," frames")
  get_tree().quit()
