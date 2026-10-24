extends Node3D
func _ready() -> void:
 Settings.begin_isolated()
 Settings.low_end_60=false
 var profiles:Array[SuitProfile]=[SuitProfile.gp03d()]
 DirAccess.make_dir_recursive_absolute("res://assets/models/distant_lod")
 for profile in profiles:
  var unit:=FlightBody.new();unit.profile=profile;add_child(unit)
  unit.set_physics_process(false);unit.set_process(false)
  var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var colors:=PackedColorArray();var indices:=PackedInt32Array()
  for node in unit.model_root.find_children("*","MeshInstance3D",true,false):
   var mi:=node as MeshInstance3D
   if unit.rig.is_ancestor_of(mi) or mi.name=="DistantRealModel" or mi.mesh==null:continue
   var transform:Transform3D=unit.model_root.global_transform.affine_inverse()*mi.global_transform
   var normal_basis:=transform.basis.inverse().transposed()
   for surface in mi.mesh.get_surface_count():
    var arrays:=mi.mesh.surface_get_arrays(surface)
    if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX]==null:continue
    var source_vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
    var source_normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
    var material:=mi.get_active_material(surface) as StandardMaterial3D
    var color:=Color(.65,.70,.74)
    if material!=null:
     color=material.albedo_color
     if material.albedo_texture!=null:
      var image:=material.albedo_texture.get_image()
      if image!=null:
       if image.is_compressed():image.decompress()
       image.resize(1,1,Image.INTERPOLATE_TRILINEAR)
       color*=image.get_pixel(0,0)
    color.a=1.0
    var offset:=vertices.size()
    for i in source_vertices.size():
     vertices.append(transform*source_vertices[i])
     normals.append((normal_basis*source_normals[i]).normalized() if i<source_normals.size() else Vector3.UP)
     colors.append(color)
    var source_indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
    if source_indices.is_empty():
     for i in source_vertices.size():indices.append(offset+i)
    else:
     for index in source_indices:indices.append(offset+index)
  var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
  arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
  var mat:=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.roughness=.8
  var importer:=ImporterMesh.new();importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},mat)
  importer.generate_lods(25.0,60.0,[])
  var chosen:=indices
  for level in importer.get_surface_lod_count(0):
   var candidate:PackedInt32Array=importer.get_surface_lod_indices(0,level)
   if candidate.size()>=9000 and candidate.size()<chosen.size():chosen=candidate
  var compact_vertices:=PackedVector3Array();var compact_normals:=PackedVector3Array();var compact_colors:=PackedColorArray();var compact_indices:=PackedInt32Array()
  var remap:Dictionary={}
  for index in chosen:
   if not remap.has(index):
    remap[index]=compact_vertices.size()
    compact_vertices.append(vertices[index]);compact_normals.append(normals[index]);compact_colors.append(colors[index])
   compact_indices.append(remap[index])
  arrays[Mesh.ARRAY_VERTEX]=compact_vertices;arrays[Mesh.ARRAY_NORMAL]=compact_normals;arrays[Mesh.ARRAY_COLOR]=compact_colors;arrays[Mesh.ARRAY_INDEX]=compact_indices
  var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,mat)
  var path:="res://assets/models/distant_lod/"+profile.model_path.md5_text()+".res"
  assert(ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)==OK)
  print("LOD built ",profile.id_name()," vertices=",compact_vertices.size()," path=",path)
  unit.queue_free();await get_tree().process_frame
 Settings.end_isolated();print("Distant LOD build PASS");get_tree().quit()
