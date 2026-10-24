extends SceneTree
const DEST := "res://assets/models/gp03d_v2/gp03d_v2.scn"
func _initialize() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert(doc.append_from_file("D:/gp03D/GP03d 2.0.glb",state)==OK)
	var original := doc.generate_scene(state)
	# Keep the original close-up geometry, with screen-space LODs for distant views.
	var lod_meshes := 0
	for mi: MeshInstance3D in original.find_children("*","MeshInstance3D",true,false):
		var source := mi.mesh
		var importer := ImporterMesh.new()
		for surface in source.get_surface_count():
			importer.add_surface(source.surface_get_primitive_type(surface), source.surface_get_arrays(surface), [], {}, source.surface_get_material(surface), source.surface_get_name(surface))
		importer.generate_lods(60.0,25.0,[])
		mi.mesh = importer.get_mesh()
		lod_meshes += 1
	print("LOD GENERATED ",lod_meshes," meshes")
	var root_model := Node3D.new()
	root_model.name = "GP03D_V2"
	root_model.set_meta("source_asset", "GP03d 2.0.glb")
	root_model.set_meta("model_revision", "2.0")
	var axis := Node3D.new()
	axis.name = "Dimensions"
	axis.rotation_degrees.y = 90.0
	# Source axes: +X forward, Y up, Z starboard. Calibrate to user dimensions.
	axis.scale = Vector3(140.0/0.9839835465,38.5/0.3382256627,62.0/0.4781177044)
	root_model.add_child(axis)
	axis.add_child(original)
	own(root_model,root_model)
	# Source-space mounts, measured on the static mesh. Converted with geometry.
	var mounts := {
		"muzzle_L":Vector3(0.492,0.094,0.110),"muzzle_R":Vector3(0.492,0.094,0.110),
		"hand_L":Vector3(-0.10,-0.040,-0.060),"hand_R":Vector3(-0.10,-0.040,0.060),
		"head":Vector3(-0.035,0.122,0.0),"chest":Vector3(-0.050,0.075,0.0),
		"funnel_L":Vector3(0.052,0.170,0.180),"funnel_R":Vector3(0.052,0.170,-0.180),
		"wing_L":Vector3(-0.030,0.190,0.235),"wing_R":Vector3(-0.030,0.190,-0.235),
		"backpack":Vector3(-0.320,0.060,0.0),
		"thruster_L":Vector3(-0.336,0.022,0.025),"thruster_R":Vector3(-0.336,0.022,-0.025)
	}
	for key in mounts:
		var marker := Marker3D.new()
		marker.name = "Mount_"+key
		marker.position = axis.transform * mounts[key]
		root_model.add_child(marker)
		marker.owner = root_model
	var scene := PackedScene.new()
	assert(scene.pack(root_model)==OK)
	DirAccess.make_dir_recursive_absolute(DEST.get_base_dir())

	assert(ResourceSaver.save(scene,DEST,ResourceSaver.FLAG_COMPRESS)==OK)
	root_model.free()
	print("SAVED ",DEST)
	quit()
func own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		own(child,owner_node)
