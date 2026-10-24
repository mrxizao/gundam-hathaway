extends SceneTree
func _initialize() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var error := doc.append_from_file("res://assets/models/xi_final_rebuilt/authoring_hidden/xi_final_fresh_rig.glb",state)
	assert(error == OK)
	var model := doc.generate_scene(state)
	assert(model != null)
	# GLTF drops channels equal to rest. Restore them so a form transition also
	# lowers an already-raised rifle instead of inheriting the previous action.
	var skeleton: Skeleton3D = model.find_children("*","Skeleton3D",true,false)[0]
	var player: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
	var base_path := str(player.get_node(player.root_node).get_path_to(skeleton))
	for name in player.get_animation_list():
		var animation := player.get_animation(name)
		var present: Dictionary = {}
		for track in animation.get_track_count(): present[str(animation.track_get_path(track))+":"+str(animation.track_get_type(track))] = true
		for bone in skeleton.get_bone_count():
			var path := NodePath(base_path+":"+str(skeleton.get_bone_name(bone)))
			var rest := skeleton.get_bone_rest(bone)
			for kind in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
				if present.has(str(path)+":"+str(kind)): continue
				var value: Variant = rest.origin
				if kind == Animation.TYPE_ROTATION_3D: value = rest.basis.orthonormalized().get_rotation_quaternion()
				elif kind == Animation.TYPE_SCALE_3D: value = rest.basis.get_scale()
				var track := animation.add_track(kind)
				animation.track_set_path(track,path)
				animation.track_insert_key(track,0.0,value)
				animation.track_insert_key(track,animation.length,value)
	var scene := PackedScene.new()
	assert(scene.pack(model) == OK)
	assert(ResourceSaver.save(scene,"res://assets/models/xi_final_rebuilt/xi_final_fresh_rig.scn",ResourceSaver.FLAG_COMPRESS) == OK)
	print("IMPORTED ",model.name)
	for node in model.find_children("*","Skeleton3D",true,false):print("SKELETON ",model.get_path_to(node)," / ",node.get_bone_count())
	for node in model.find_children("*","AnimationPlayer",true,false):print("PLAYER ",node.root_node," / ",node.get_animation_list()," firsttrack ",node.get_animation("fly").track_get_path(0))
	model.free()
	quit()

