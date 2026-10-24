extends RefCounted
static func digest(value:Variant)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(var_to_bytes(value));return context.finish().hex_encode()
static func run(t:T,host:Node)->void:
	t.suite("AdelaideLandmarkDetail / protected layout and noncolliding finish")
	var city=load("res://scripts/world/adelaide_builder.gd").new();host.add_child(city);await city.build_staged()
	var layer:Node3D=city.landmark_detail
	t.eq(city.parcel_records.size(),1699,"parcel layout preserved")
	t.eq(city.damaged_buildings,61,"existing damage distribution preserved")
	t.eq(digest(city.get_node("AdelaideCollision").get_child(0).shape.get_faces()),"7c68ed731e57f1f796091dca32990d706f3765c6b4c260789d4c905e54768dd0","all old collision triangles preserved byte for byte")
	t.eq(layer.practical_lights.size(),12,"two registered work lights per hangar")
	t.eq(layer.hangar_count,6,"six open-front hangars refined")
	t.eq(layer.festival_count,5,"five original Festival masses refined")
	t.eq(layer.ruin_records.size(),61,"only existing damaged buildings get fracture edges")
	t.eq(layer.WEAR_NAMES.size(),12,"twelve authored wear masks")
	t.ok(layer.triangles<50000,"landmark and fracture additions remain below 50K triangles")
	t.ok(layer.optional_meshes.size()<32,"ruins use spatial batches")
	t.eq(layer.region_writers.size(),0,"temporary geometry writers released")
	var shader_bytes:=FileAccess.get_file_as_string("res://shaders/adelaide_landmark.gdshader")
	t.ok(shader_bytes.contains("cull_back") and not shader_bytes.contains("ALPHA="),"opaque material avoids transparency ordering")
	var encoded_patterns:Dictionary={}
	for mesh:MeshInstance3D in layer.landmark_meshes+layer.optional_meshes:
		t.eq(mesh.get_child_count(),0,"no collision or decal receiver added")
		t.eq(mesh.mesh.get_surface_count(),1,"one visible draw surface per regional mesh")
		t.eq(mesh.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"original buildings supply shadows without duplicate passes")
		for value:Color in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:encoded_patterns[int(round(value.g*12.0))]=true
		var data:=mesh.mesh.surface_get_arrays(0);var points:PackedVector3Array=data[Mesh.ARRAY_VERTEX];var valid:=true
		t.eq(data[Mesh.ARRAY_TEX_UV].size(),points.size(),"physical UV supplied")
		t.eq(data[Mesh.ARRAY_TANGENT].size(),points.size()*4,"PBR tangents supplied")
		for i in range(0,points.size(),3):
			var normal:Vector3=data[Mesh.ARRAY_NORMAL][i];var cross:Vector3=(points[i+1]-points[i]).cross(points[i+2]-points[i])
			if cross.length()<.00001 or cross.normalized().dot(normal)>-.995:valid=false
		t.ok(valid,"outward normals and clockwise nondegenerate triangles")
		if str(mesh.name).begins_with("Festival"):
			var bounds:=mesh.mesh.get_aabb()
			t.ok(bounds.size.x<1712 and bounds.size.z<2612 and bounds.end.y<=76.01,"landmark roof confined to each existing body; deleted giant canopy stays absent")
		if str(mesh.name).begins_with("Hangar"):
			var clear:=true
			for point:Vector3 in points:
				if absf(point.x)<85 and point.y>10 and point.y<145 and point.z<0:clear=false
			t.ok(clear,"no visible new equipment crosses central open hangar portal")
	t.eq(encoded_patterns.size(),12,"all twelve masks survive vertex storage and are actually assigned")
	var camera:=Camera3D.new();city.add_child(camera);camera.position=Vector3(-9480,70,4450);camera.make_current()
	for quality in [0,1,2]:
		Settings.effects_quality=quality;Settings.changed.emit();layer.refresh_quality()
		var active_lights:=0
		for light:SpotLight3D in layer.practical_lights:
			if light.visible:active_lights+=1
			t.not_ok(light.shadow_enabled,"local work lights do not multiply shadow draws")
		t.eq(active_lights,quality,"low/mid/high use zero/one/two nearest-bay lights")
		for material:ShaderMaterial in layer.materials.values():t.eq(material.get_shader_parameter("detail_quality"),quality,"material quality follows settings")
		for mesh:MeshInstance3D in layer.landmark_meshes:t.ok(mesh.visible,"base landmark finish remains on every quality")
		for mesh:MeshInstance3D in layer.optional_meshes:
			t.eq(mesh.visible,quality>0,"low quality retains original ruin silhouette and omits optional fractures")
			t.eq(mesh.visibility_range_end,6500.0 if quality==2 else 3500.0,"local fracture culling follows quality")
	Settings.effects_quality=2;Settings.changed.emit()
	city.free();await host.get_tree().process_frame
