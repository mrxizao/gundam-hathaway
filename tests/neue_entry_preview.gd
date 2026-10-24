extends "res://tests/neue_entry_probe.gd"
var preview:Node
const CAPTURE_FPS:=60.0
var frames:=0
func _ready()->void:
 Settings.begin_isolated();Settings.low_end_60=false
 var main:=owner_scene()
 preview=preload("res://scripts/cinematics/neue_entry_director.gd").new();preview.setup(main);main.add_child(preview)
func _process(_delta:float)->void:
 if preview==null:return
 preview.time=minf(float(frames)/CAPTURE_FPS,preview.Sequence.DURATION);preview.pose(1.0/CAPTURE_FPS);frames+=1
 if frames>int(preview.Sequence.DURATION*CAPTURE_FPS)+1:
  if is_instance_valid(preview.music):preview.music.stop();preview.music.stream=null
  print("NEUE PREVIEW: ",frames," frames");get_tree().quit()
