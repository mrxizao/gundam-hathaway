extends RefCounted
const Meshes:=preload("res://scripts/world/adelaide_building_mesh.gd")
const Details:=preload("res://scripts/world/adelaide_detail_modules.gd")
const Library:=preload("res://scripts/world/adelaide_building_library.gd")
const Materials:=preload("res://scripts/world/adelaide_building_material.gd")
static func run(t:T,host:Node)->void:
	t.suite("AdelaideRoofDetail / twelve reusable modules and deterministic placement")
	t.eq(Details.NAMES.size(),12,"twelve distinct detail module entries")
	for kind in 12:
		var writer:=Meshes.new();Details.emit(writer,kind,Vector3.ZERO)
		var mesh:ArrayMesh=writer.finish_mesh();var valid:=true
		for surface in mesh.get_surface_count():
			var a:=mesh.surface_get_arrays(surface);var points:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
			valid=valid and a[Mesh.ARRAY_TEX_UV].size()==points.size() and a[Mesh.ARRAY_TANGENT].size()==points.size()*4
			for i in range(0,points.size(),3):
				var cross:Vector3=(points[i+1]-points[i]).cross(points[i+2]-points[i]);var n:Vector3=a[Mesh.ARRAY_NORMAL][i]
				if cross.length()<.0001 or cross.normalized().dot(n)>-.999:valid=false
		t.ok(valid,"module has nondegenerate clockwise geometry, physical UV and tangents")
		t.ok(int(mesh.get_meta("triangles"))<=160,"module has a bounded geometry cost")
	var parcel:={"id":"test_parcel","bounds":Rect2(-130,-110,260,220),"height":320.0,"style":4,"seed":1247}
	var first:=Details.placements(parcel);t.eq(first,Details.placements(parcel),"same stable seed reproduces equipment layout")
	var other:=parcel.duplicate();other.seed=387;t.not_ok(first==Details.placements(other),"different stable seeds vary equipment layouts")
	var in_bounds:=true
	for placement:Dictionary in first:
		var writer:=Meshes.new();Details.emit(writer,placement.kind,placement.position);var mesh:ArrayMesh=writer.finish_mesh()
		for surface in mesh.get_surface_count():
			for point:Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if absf(point.x)>130.01 or absf(point.z)>110.01 or point.y<-.01 or point.y>334:in_bounds=false
	t.ok(in_bounds,"equipment stays in the original parcel and within 14m of the roof")
	for role in [5,6]:
		var material:=Materials.material(role,0)
		for key in ["surface_albedo","surface_normal","surface_orm"]:t.eq(material.get_shader_parameter(key).get_width(),2048,"roof PBR channels are aligned 2K textures")
	t.suite("AdelaideRoofDetail / citywide shared materials and regional batches")
	var city=load("res://scripts/world/adelaide_builder.gd").new();host.add_child(city);await city.build_staged()
	var lib:Node3D=city.building_library;var intact:=0;var districts:=[0,0,0]
	for record:Dictionary in city.parcel_records:
		if not record.damaged:intact+=1
	var total:=0
	for count:int in city.building_style_counts:total+=count;t.ok(count>0,"each shared facade style appears in the city")
	t.eq(total,intact,"all intact city buildings receive a stable shared material style")
	for entry:Dictionary in lib.entries:districts[Library.district_for(entry.record.bounds.get_center())]+=1
	t.eq(districts,[16,16,16],"three route districts each receive 16 detailed buildings")
	t.ok(lib.detail_instances>=48*9 and lib.detail_instances<=48*11,"detail instance counts stay inside layout bounds")
	t.ok(lib.detail_mesh_triangles<80000,"region-batched detail geometry stays below 80K triangles")
	t.ok(lib.detail_regions.size()<24,"equipment is batched by spatial regions")
	t.eq(lib.detail_writers.size(),0,"temporary mesh writers are released after committing batches")
	for region:Node3D in lib.detail_regions:
		t.eq(region.get_child_count(),2,"each region has one visible mesh and one shadow proxy")
		t.eq(region.get_child(1).mesh.get_surface_count(),1,"one depth surface casts all regional equipment shadows")
	for quality in [0,1,2]:
		Settings.effects_quality=quality;Settings.changed.emit();lib.refresh_quality()
		for material:ShaderMaterial in city._city_shared_materials:t.eq(material.get_shader_parameter("city_quality"),quality,"existing shared city materials react to quality changes")
		for region:Node3D in lib.detail_regions:
			t.eq(region.visible,quality>0,"low quality omits only optional detail modules")
			t.eq(region.get_child(0).visibility_range_end,4500.0 if quality==2 else 1800.0,"detail culling distances match quality budgets")
	var legacy:PackedScene=load("res://assets/models/adelaide_modules/legacy/brick_streetfront.tscn")
	t.ok(legacy!=null,"preserved original building remains a separately usable scene")
	city.free();await host.get_tree().process_frame
