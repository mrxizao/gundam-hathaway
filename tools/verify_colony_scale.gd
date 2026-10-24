extends Node3D
func _ready()->void:call_deferred("verify")
func verify()->void:
 var colony=load("res://assets/maps/colony_ruins/colony_ruined.scn").instantiate()
 add_child(colony)
 var heights:Array[float]=[]
 for mesh in colony.find_children("*","MeshInstance3D",true,false):
  if not str(mesh.name).begins_with("District"):continue
  var arrays=mesh.mesh.surface_get_arrays(0)
  var center:Vector3=mesh.global_transform*mesh.get_aabb().get_center()
  var radial=Vector3(center.x,center.y,0).normalized()
  var normal=Vector3.ZERO;var nearest=-1.0
  for surface in mesh.mesh.get_surface_count():
   for source_normal in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_NORMAL]:
    var candidate:Vector3=(mesh.global_basis*source_normal).normalized()
    var score=absf(candidate.dot(radial))
    if score>nearest:normal=candidate;nearest=score
  var low=INF;var high=-INF
  for surface in mesh.mesh.get_surface_count():
   var vertices=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
   for vertex in vertices:
    var dot=(mesh.global_transform*vertex).dot(normal)
    low=minf(low,dot);high=maxf(high,dot)
  heights.append(high-low)
 var total=0.0
 for height in heights:total+=height
 var mean=total/heights.size()
 print("BUILDING_HEIGHTS count=",heights.size()," mean=",mean," min=",heights.min()," max=",heights.max())
 assert(heights.size()==140 and absf(mean-137.0663)<.1,"Original building heights are restored")
 var map_scale=preload("res://scripts/world/colony_ruins.gd").MODEL_SCALE
 assert(map_scale==8.0,"Map applies the requested eightfold scale once")
 print("BUILDING_WORLD_MEAN ",mean*map_scale)
 var profile=SuitProfile.thunderbolt(false)
 var model=load(profile.model_path).instantiate()
 add_child(model)
 model.scale=Vector3.ONE*profile.target_height/profile.model_native_height
 var low=INF;var high=-INF
 for mesh in model.find_children("*","MeshInstance3D",true,false):
  if not mesh.is_visible_in_tree():continue
  for index in 8:
   var point=mesh.global_transform*mesh.get_aabb().get_endpoint(index)
   low=minf(low,point.y);high=maxf(high,point.y)
 print("FULL_ARMOR_ACTUAL_HEIGHT ",high-low)
 assert(absf(high-low-23)<.001,"Actual Full Armor geometry is 23 metres")
 var night=MapDef.pacific().time_of_day
 var colony_light=MapDef.colony_ruins().time_of_day
 assert(colony_light.sun_energy==night.sun_energy and colony_light.sun_color==night.sun_color,"Pacific moonlight matches")
 assert(colony_light.ambient_sky_contribution==0,"Star field cannot wash out the night lighting")
 print("COLONY_SCALE_LIGHTING PASS 5 FAIL 0")
 model.free();colony.free();get_tree().quit()
