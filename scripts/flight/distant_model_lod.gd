extends Node
## Distant views use the real model silhouette merged into one colored surface.
## Range checks are performed per camera: the magnifier still sees the full model.
var meshes:Array[GeometryInstance3D]=[]
var saved_ends:Array[float]=[]
var saved_margins:Array[float]=[]
var lod:MeshInstance3D
var last_mode := false
var clock := 0.0
func setup(body:FlightBody) -> void:
 var path:="res://assets/models/distant_lod/"+body.profile.model_path.md5_text()+".res"
 if not ResourceLoader.exists(path):return
 for node in body.model_root.find_children("*","MeshInstance3D",true,false):
  if not body.rig.is_ancestor_of(node):
   meshes.append(node);saved_ends.append(node.visibility_range_end);saved_margins.append(node.visibility_range_end_margin)
 lod=MeshInstance3D.new();lod.name="DistantRealModel"
 lod.mesh=load(path);lod.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 lod.visibility_range_begin=1200.0
 body.model_root.add_child(lod)
 _apply()
func _process(delta:float) -> void:
 clock+=delta
 if clock<.25:return
 clock=0.0
 if last_mode!=Settings.low_end_60:_apply()
func _apply() -> void:
 last_mode=Settings.low_end_60
 if lod==null:return
 lod.visible=last_mode
 for i in meshes.size():
  if is_instance_valid(meshes[i]):
   meshes[i].visibility_range_end=1200.0 if last_mode else saved_ends[i]
   # Preserve the paired low-end silhouette boundary; restore fine-detail hysteresis on exit.
   meshes[i].visibility_range_end_margin=0.0 if last_mode else saved_margins[i]
