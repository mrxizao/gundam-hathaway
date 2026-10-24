extends SceneTree
func _initialize() -> void:
	call_deferred("build")
func build() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert(doc.append_from_file("res://assets/models/odysseus_pedal/authoring_hidden/odysseus_pedal.glb",state)==OK)
	var model := doc.generate_scene(state)
	root.add_child(model)
	for empty in [false,true]:
		var target := Node3D.new()
		target.name="OdysseusPedalEmpty" if empty else "OdysseusPedalMounted"
		var count := 0
		for source: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			var parent_name := str(source.get_parent().name).replace(".","").replace("_","")
			var rider := parent_name == "ParentNode005" or str(source.name)=="Penelope_Rifle"
			if empty and rider: continue
			var mesh := MeshInstance3D.new()
			mesh.name=source.name
			mesh.mesh=source.mesh
			mesh.transform=source.global_transform
			mesh.set_meta("odysseus_rider",rider)
			target.add_child(mesh)
			mesh.owner=target
			count+=1
		var packed := PackedScene.new()
		assert(packed.pack(target)==OK)
		var path := "res://assets/models/odysseus_pedal/empty.scn" if empty else "res://assets/models/odysseus_pedal/mounted.scn"
		assert(ResourceSaver.save(packed,path,ResourceSaver.FLAG_COMPRESS)==OK)
		print("IMPORTED ",path," mesh_count=",count)
		target.free()
	model.free()
	quit()
