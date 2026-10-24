extends Node3D
func digest(value:Variant)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(value));return h.finish().hex_encode()
func _ready()->void:
	Settings.begin_isolated()
	var output_path:="res://assets/materials/adelaide_pbr/ground_layout.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output_path=argument.trim_prefix("--output=")
	var city=load("res://scripts/world/adelaide_builder.gd").new();add_child(city);await city.build_staged()
	var hard:Array=[];var parcels:Array=[]
	for mesh in city.get_children():
		if not mesh is MeshInstance3D or not mesh.has_meta("surface_family"):continue
		var family:int=mesh.get_meta("surface_family")
		var material:ShaderMaterial=mesh.material_override
		var kind_value=material.get_shader_parameter("material_kind")
		var kind:int=0 if kind_value==null else int(kind_value)
		if family!=2 and kind!=10:continue
		var arrays:Array=mesh.mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		# Adelaide box() emits 36 consecutive vertices; sample only ground-level hardscape.
		for start in range(0,vertices.size(),36):
			if start+36>vertices.size():continue
			var lo:=Vector3(INF,INF,INF);var hi:=Vector3(-INF,-INF,-INF)
			for index in range(start,start+36):lo=lo.min(vertices[index]);hi=hi.max(vertices[index])
			if hi.y>28.0 or hi.y<25.0 or hi.x-lo.x<20.0 or hi.z-lo.z<20.0:continue
			hard.append([lo.x,lo.z,hi.x-lo.x,hi.z-lo.z])
	for record:Dictionary in city.parcel_records:
		var rect:Rect2=record.bounds
		parcels.append([rect.position.x,rect.position.y,rect.size.x,rect.size.y])
	var faces:PackedVector3Array=city.get_node("AdelaideCollision").get_child(0).shape.get_faces()
	var out:={"hardscape":hard,"parcels":parcels,"roads_hash":digest(city.roads),"buildings_hash":digest(city.buildings),"collision_hash":digest(faces),"parcels_hash":digest(city.parcel_records),"river":{"x_min":-60750.0,"x_max":74250.0,"scale":18.0,"water_half_width":1242.0},"airport":[-16500.0,600.0,9300.0,17400.0]}
	var file:=FileAccess.open(output_path,FileAccess.WRITE);assert(file!=null,"Cannot write layout: "+output_path);file.store_string(JSON.stringify(out,"  "));file.close()
	print("DAY2_LAYOUT_READY hardscape=",hard.size()," parcels=",parcels.size())
	city.free();await get_tree().process_frame;get_tree().quit()
