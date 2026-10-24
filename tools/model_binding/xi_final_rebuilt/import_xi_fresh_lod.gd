extends SceneTree
func _initialize() -> void:
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://tools/xi_fresh_lod.json"))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in source:
		tool.set_color(Color(row[9],row[10],row[11]))
		for vertex in 3: tool.add_vertex(Vector3(row[vertex*3],row[vertex*3+1],row[vertex*3+2]))
	tool.generate_normals()
	var mesh := tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0,material)
	assert(ResourceSaver.save(mesh,"res://assets/models/distant_lod/6bf965705994fd2b68a279499136d2e5.res",ResourceSaver.FLAG_COMPRESS)==OK)
	print("XI FINAL LOD ",mesh.get_surface_count()," surface / ",source.size()," triangles")
	quit()
