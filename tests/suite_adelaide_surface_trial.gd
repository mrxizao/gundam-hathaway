extends RefCounted
const Catalog:=preload("res://scripts/world/adelaide_surface_catalog.gd")
static func digest(value:Variant)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(value));return h.finish().hex_encode()
static func replace_one(city:Node3D,parcel:Dictionary,wanted:String)->bool:
	if parcel.id!=wanted:return false
	var mesh:=MeshInstance3D.new();mesh.name="ReplacementFixture"
	var box:=BoxMesh.new();var bounds:Rect2=parcel.bounds
	box.size=Vector3(bounds.size.x,parcel.height,bounds.size.y);mesh.mesh=box
	mesh.position=Vector3(bounds.get_center().x,25+parcel.height*.5,bounds.get_center().y)
	city.add_child(mesh);return true
static func run(t:T,host:Node)->void:
	t.suite("AdelaideSurfaceTrial / metre scale, protected map and future model replacement")
	var old_quality:int=Settings.effects_quality
	var city=load("res://scripts/world/adelaide_builder.gd").new();host.add_child(city);await city.build_staged()
	t.eq(city.parcel_records.size(),1699,"all current parcels expose a stable visual record")
	var ids:={};var damaged:=0
	for record:Dictionary in city.parcel_records:
		t.not_ok(ids.has(record.id),"parcel identifiers are unique")
		ids[record.id]=true
		if record.damaged:damaged+=1
	t.eq(damaged,61,"visual records retain existing damaged parcels")
	var collision:ConcavePolygonShape3D=city.get_node("AdelaideCollision").get_child(0).shape
	var original_faces:=collision.get_faces()
	t.eq(digest(original_faces),"7c68ed731e57f1f796091dca32990d706f3765c6b4c260789d4c905e54768dd0","surface classification keeps every collision vertex")
	var ground:=0;var asphalt:=0;var unchanged:=0;var other_surfaces:=0
	for child in city.get_children():
		if not child is MeshInstance3D or not child.has_meta("surface_family"):continue
		var family:int=child.get_meta("surface_family")
		var material:ShaderMaterial=child.material_override
		if family==0:
			unchanged+=1
			t.not_ok(material.shader.resource_path.ends_with("surface_trial.gdshader"),"non-ground material remains on original shader")
			continue
		if family>Catalog.ASPHALT:other_surfaces+=1;continue
		if family==Catalog.GRASS:ground+=1
		if family==Catalog.ASPHALT:asphalt+=1
		t.ok(not child.has_meta("cinematic_detail"),"surface family does not become a short-range detail batch")
		t.near(child.visibility_range_end,0.0,.00001,"ground is not culled at roof-detail distance")
		t.eq(int(material.get_shader_parameter("surface_family")),family,"semantic material follows explicit batch class")
		for map in ["surface_albedo","surface_normal","surface_orm"]:
			var texture:Texture2D=material.get_shader_parameter(map)
			t.eq(texture.get_width(),2048,"real source map loads at planned 2K resolution")
			t.eq(texture.get_height(),2048,"source channels remain aligned")
		t.near(float(material.get_shader_parameter("tile_m")),(2.0 if material.shader.resource_path.ends_with("adelaide_ground.gdshader") else 2.51) if family==Catalog.GRASS else 2.35,.0001,"source material uses measured world metres")
	t.gt(ground,0,"terrain and airport grass have semantic material batches")
	t.gt(asphalt,0,"city and runway asphalt have semantic material batches")
	t.eq(unchanged+ground+asphalt+other_surfaces,city.serial,"all root batches retain explicit surface classification after material sharing")
	t.ok(city.serial<=195,"road semantics stay within 21 additional city batches")
	for site:Dictionary in Catalog.SITES:
		var bounds:Rect2=site.bounds
		t.near(Catalog.sample_weight(bounds.get_center()),1.0,.00001,"sample area contains its centre")
		t.near(Catalog.sample_weight(bounds.position-Vector2.ONE*100),0.0,.00001,"sample shader excludes surrounding world")
	t.near(Catalog.sample_weight(Vector2(60000,60000)),0.0,.00001,"remote scenery stays unchanged")
	for quality in [0,2,0]:
		Settings.effects_quality=quality;Settings.changed.emit()
		for material:ShaderMaterial in city._surface_materials:
			t.eq(int(material.get_shader_parameter("surface_detail")),0 if quality==0 else 1,"quality changes propagate without a city rebuild")
	city.set_surface_trials_enabled(false)
	for material:ShaderMaterial in city._surface_materials:
		t.not_ok(material.get_shader_parameter("trial_enabled"),"baseline material remains available through rollback switch")
	city.set_surface_trials_enabled(true)
	for material:ShaderMaterial in city._surface_materials:
		t.ok(material.get_shader_parameter("trial_enabled"),"samples can be enabled again")
	var replacement=load("res://scripts/world/adelaide_builder.gd").new()
	replacement.parcel_visual_factory=replace_one.bind(city.parcel_records[0].id)
	host.add_child(replacement);await replacement.build_staged()
	t.ok(replacement.has_node("ReplacementFixture"),"future building factory can install a replacement model")
	t.eq(replacement.parcel_records,city.parcel_records,"replacement does not perturb city RNG or later parcels")
	var replaced_collision:ConcavePolygonShape3D=replacement.get_node("AdelaideCollision").get_child(0).shape
	t.eq(digest(replaced_collision.get_faces()),digest(original_faces),"visual replacement retains original collision")
	t.ok(replacement.emit_visual_geometry,"visual gate restores after replacement")
	t.eq(replacement.buildings,city.buildings,"replacement retains parcel placement")
	t.eq(replacement.roads,city.roads,"replacement retains road placement")
	replacement.free();city.free();await host.get_tree().process_frame
	Settings.effects_quality=old_quality;Settings.changed.emit()
