extends Node
const CATALOG="res://assets/models/low_spec/catalog.json"
const DIR="res://assets/models/low_spec/"
const LIMIT=1024
var resized:Dictionary={}
var visited:Dictionary={}
var records:Array=[]
func shrink_material(material:Material)->void:
 if material==null or visited.has(material.get_instance_id()):return
 visited[material.get_instance_id()]=true
 for property in material.get_property_list():
  if property.type!=TYPE_OBJECT:continue
  var value=material.get(property.name)
  if value is Texture2D and maxi(value.get_width(),value.get_height())>LIMIT:
   var key:int=value.get_instance_id()
   if not resized.has(key):
    var image:Image=value.get_image()
    assert(image!=null,"cannot read "+str(value.resource_path))
    if image.is_compressed():assert(image.decompress()==OK)
    var ratio:float=float(LIMIT)/maxi(image.get_width(),image.get_height())
    image.resize(maxi(1,int(image.get_width()*ratio)),maxi(1,int(image.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
    image.generate_mipmaps(str(property.name).contains("normal"))
    assert(image.compress(Image.COMPRESS_S3TC)==OK,"offline S3TC compressor unavailable")
    resized[key]=ImageTexture.create_from_image(image)
   material.set(property.name,resized[key])
  elif value is Material:shrink_material(value)
var clean_seen:Dictionary={}
func clean_resource_paths(value)->void:
 if value is Resource:
  if value is Script or clean_seen.has(value.get_instance_id()):return
  clean_seen[value.get_instance_id()]=true
  value.resource_path=""
  for property in value.get_property_list():
   if int(property.usage)&PROPERTY_USAGE_STORAGE:clean_resource_paths(value.get(property.name))
 elif value is Array:
  for item in value:clean_resource_paths(item)
 elif value is Dictionary:
  for item in value.values():clean_resource_paths(item)
func signature(root:Node)->Dictionary:
 var meshes:Array=[];var bones:Dictionary={};var animations:Dictionary={}
 var max_texture:=0
 for node in root.find_children("*","",true,false):
  if node is MeshInstance3D and node.mesh!=null:
   var surfaces:Array=[]
   for surface in node.mesh.get_surface_count():
    surfaces.append([node.mesh.surface_get_array_len(surface),node.mesh.surface_get_array_index_len(surface)])
    var material:Material=node.mesh.surface_get_material(surface)
    if material!=null:
     for property in material.get_property_list():
      if property.type==TYPE_OBJECT:
       var tex=material.get(property.name)
       if tex is Texture2D:max_texture=maxi(max_texture,maxi(tex.get_width(),tex.get_height()))
   meshes.append([str(root.get_path_to(node)),surfaces])
  elif node is Skeleton3D:
   var names:Array=[]
   for index in node.get_bone_count():names.append([node.get_bone_name(index),node.get_bone_parent(index),str(node.get_bone_rest(index))])
   bones[str(root.get_path_to(node))]=names
  elif node is AnimationPlayer:
   var clips:Dictionary={}
   for name in node.get_animation_list():
    var anim:Animation=node.get_animation(name);var paths:Array=[]
    for track in anim.get_track_count():paths.append(str(anim.track_get_path(track)))
    clips[name]=[anim.length,paths]
   animations[str(root.get_path_to(node))]=clips
 return {"meshes":meshes,"bones":bones,"animations":animations,"max_texture":max_texture}
func _ready()->void:
 DirAccess.make_dir_recursive_absolute(DIR)
 var paths:Dictionary={}
 for id in SuitProfile.Id.values():
  var profile:=SuitProfile.by_id(id)
  for form in maxi(profile.form_count,1):
   var item:=SuitProfile.by_id_form(id,form)
   if item.model_path!="":paths[item.model_path]=true
 for source:String in paths:
  resized.clear();visited.clear()
  var packed:PackedScene=load(source)
  assert(packed!=null,"missing model "+source)
  var inst:Node3D=packed.instantiate()
  var before:=signature(inst)
  for node in inst.find_children("*","MeshInstance3D",true,false):
   if node.mesh!=null:
    for surface in node.mesh.get_surface_count():shrink_material(node.mesh.surface_get_material(surface))
    shrink_material(node.material_override)
    for surface in node.mesh.get_surface_count():shrink_material(node.get_surface_override_material(surface))
  if resized.is_empty():
   print("LOW_ASSET_SKIP ",source)
   inst.free();await get_tree().process_frame;continue
  var after:=signature(inst)
  assert(before.meshes==after.meshes and before.bones==after.bones and before.animations==after.animations)
  clean_seen.clear()
  for node in [inst]+inst.find_children("*","",true,false):
   for property in node.get_property_list():
    if int(property.usage)&PROPERTY_USAGE_STORAGE:clean_resource_paths(node.get(property.name))
  inst.scene_file_path=""
  var result:=PackedScene.new();assert(result.pack(inst)==OK)
  var target:=DIR+source.md5_text()+".scn"
  assert(ResourceSaver.save(result,target,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK)
  var loaded:PackedScene=ResourceLoader.load(target,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
  var check:Node3D=loaded.instantiate()
  var roundtrip:=signature(check)
  assert(after==roundtrip,"roundtrip changed "+source)
  assert(roundtrip.max_texture<=LIMIT,"oversized texture remained")
  var dependencies:=ResourceLoader.get_dependencies(target)
  for dependency in dependencies:assert(not str(dependency).contains(source.trim_prefix("res://")),"original dependency "+str(dependency))
  records.append({"source":source,"source_sha256":FileAccess.get_sha256(source),"target":target,"textures_resized":resized.size(),"before_max_texture":before.max_texture,"after_max_texture":roundtrip.max_texture,"mesh_bone_animation_signature_identical":true,"dependencies":dependencies,"bytes":FileAccess.get_file_as_bytes(target).size()})
  print("LOW_ASSET_OK ",source," textures=",resized.size()," max=",roundtrip.max_texture)
  var f:=FileAccess.open(CATALOG,FileAccess.WRITE);f.store_string(JSON.stringify(records,"  "));f.close()
  check.free();inst.free();await get_tree().process_frame
 print("DAY7_LOW_ASSETS_OK count=",records.size());get_tree().quit()
