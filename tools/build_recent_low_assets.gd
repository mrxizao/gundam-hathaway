extends "res://tools/build_low_texture_models.gd"
## Extend the existing low preset to the newer Nu/Sazabi assets and held weapons.
func _ready()->void:
	var catalog:Array=[]
	if FileAccess.file_exists(CATALOG):
		var old=JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if old is Array:catalog=old
	var sources:Array[String]=[SuitProfile.nu_gundam().model_path,SuitProfile.sazabi().model_path]
	for weapon in ["shotgun","sniper","shield","axe"]:sources.append("res://data/sazabi_models/"+weapon+".scn")
	for source in sources:
		resized.clear();visited.clear();clean_seen.clear()
		var packed:PackedScene=ResourceLoader.load(source,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
		assert(packed!=null,"missing source "+source)
		var inst:Node3D=packed.instantiate();var before:=signature(inst)
		for node in inst.find_children("*","MeshInstance3D",true,false):
			if node.mesh!=null:
				for surface in node.mesh.get_surface_count():shrink_material(node.mesh.surface_get_material(surface))
			shrink_material(node.material_override)
			if node.mesh!=null:
				for surface in node.mesh.get_surface_count():shrink_material(node.get_surface_override_material(surface))
		if resized.is_empty():print("RECENT_LOW_SKIP ",source);inst.free();continue
		var after:=signature(inst)
		assert(before.meshes==after.meshes and before.bones==after.bones and before.animations==after.animations,"geometry/rig changed")
		for node in [inst]+inst.find_children("*","",true,false):
			for property in node.get_property_list():
				if int(property.usage)&PROPERTY_USAGE_STORAGE:clean_resource_paths(node.get(property.name))
		inst.scene_file_path=""
		var result:=PackedScene.new();assert(result.pack(inst)==OK)
		var target:=DIR+source.md5_text()+".scn"
		assert(ResourceSaver.save(result,target,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK)
		var loaded:PackedScene=ResourceLoader.load(target,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
		var check:Node3D=loaded.instantiate();var final:=signature(check)
		assert(final==after and final.max_texture<=LIMIT,"saved variant changed")
		var dependencies:=ResourceLoader.get_dependencies(target)
		assert(dependencies.is_empty(),"low variant still loads original large textures")
		for i in range(catalog.size()-1,-1,-1):
			if catalog[i].source==source:catalog.remove_at(i)
		catalog.append({"source":source,"source_sha256":FileAccess.get_sha256(source),"target":target,"textures_resized":resized.size(),"before_max_texture":before.max_texture,"after_max_texture":final.max_texture,"mesh_bone_animation_signature_identical":true,"dependencies":dependencies,"bytes":FileAccess.get_file_as_bytes(target).size()})
		var file:=FileAccess.open(CATALOG,FileAccess.WRITE);file.store_string(JSON.stringify(catalog,"  "));file.close()
		print("RECENT_LOW_OK ",source," before=",before.max_texture," after=",final.max_texture," textures=",resized.size())
		check.free();inst.free();await get_tree().process_frame
	print("RECENT_LOW_DONE");get_tree().quit()
