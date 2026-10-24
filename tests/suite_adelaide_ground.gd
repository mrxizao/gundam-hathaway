extends RefCounted
const Ground:=preload("res://scripts/world/adelaide_ground_material.gd")
const Builder:=preload("res://scripts/world/adelaide_builder.gd")
static func digest(value:Variant)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(value));return h.finish().hex_encode()
static func run(t:T,host:Node)->void:
	t.suite("AdelaideGround / geometry-derived boundaries and compressed PBR")
	var old_quality:int=Settings.effects_quality
	var city:=Builder.new();host.add_child(city);await city.build_staged()
	var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/materials/adelaide_pbr/ground_mask_metadata.json"))
	var layout:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/materials/adelaide_pbr/ground_layout.json"))
	t.eq(digest(city.roads),metadata.roads_hash,"mask matches actual road layout")
	t.eq(digest(city.buildings),metadata.buildings_hash,"mask matches actual parcel layout")
	t.eq(digest(city.parcel_records),metadata.parcels_hash,"surface integration preserves all parcel seeds")
	var collision:ConcavePolygonShape3D=city.get_node("AdelaideCollision").get_child(0).shape
	t.eq(digest(collision.get_faces()),metadata.collision_hash,"surface integration preserves collision")
	t.eq(metadata.hardscape_count,layout.hardscape.size(),"mask includes the current ground-level hardscape")
	t.eq(metadata.parcel_count,1699,"all building parcels feed the mask")
	var mask_texture:Texture2D=load("res://assets/materials/adelaide_pbr/adelaide_ground_mask.png")
	var image:Image=mask_texture.get_image()
	if image.is_compressed():image.decompress()
	t.eq(image.get_size(),Vector2i(4096,4096),"whole-city linear layout mask has the planned density")
	var road_max:=0.0;var parcel_max:=0.0
	for road:Array in layout.hardscape:
		var point:=Vector2(road[0]+road[2]*0.5,road[1]+road[3]*0.5)
		road_max=maxf(road_max,Ground.sample_mask(image,point).r*Ground.MASK_DISTANCE_M)
	for parcel:Dictionary in city.parcel_records:
		parcel_max=maxf(parcel_max,Ground.sample_mask(image,parcel.bounds.get_center()).g*Ground.MASK_DISTANCE_M)
	t.lt(road_max,20.0,"all hardscape centres are identified within half a mask texel")
	t.near(parcel_max,0.0,0.001,"parcel centres contain no vegetation eligibility gap")
	t.eq(Ground.sample_mask(image,Vector2(100000,100000)),Color(1,1,0,0),"outside city has no clamped edge stripe")
	var airport:=Ground.sample_mask(image,Vector2(-14540,6800))
	t.gt(airport.a,0.99,"airport turf uses the actual reservation")
	var river_x:=5400.0
	var river_z:float=Builder.river_z(river_x/Builder.CITY_SCALE)*Builder.CITY_SCALE
	t.gt(Ground.sample_mask(image,Vector2(river_x,river_z-1800)).b,0.85,"near bank is damp")
	t.lt(Ground.sample_mask(image,Vector2(river_x,river_z-5000)).b,0.01,"river moisture does not cover the whole city")
	t.lt(Ground.sample_mask(image,Vector2(-14540,6800)).b,0.01,"river mask does not leak onto airport")
	var loaded:=0;var legacy_sand:=0;var mask_id:=0
	for child in city.get_children():
		if not child is MeshInstance3D or child.get_meta("surface_family",0)!=1:continue
		var material:ShaderMaterial=child.material_override
		var color:Color=material.get_shader_parameter("base_color")
		if color.r>0.6:
			legacy_sand+=1
			t.ok(material.shader.resource_path.ends_with("adelaide_surface_trial.gdshader"),"coastal sand retains its existing material")
			continue
		loaded+=1
		t.ok(material.shader.resource_path.ends_with("adelaide_ground.gdshader"),"all inland grass batches use citywide material")
		for name in ["surface_albedo","surface_normal","surface_orm","dry_albedo","dry_normal","dry_orm","soil_albedo","soil_normal","soil_orm"]:
			var map:Texture2D=material.get_shader_parameter(name)
			t.ok(map is CompressedTexture2D,"PBR map is a compressed imported resource")
			t.eq(map.get_size(),Vector2(2048,2048),"all nine source maps are aligned 2K")
		var mask:Texture2D=material.get_shader_parameter("ground_mask")
		if mask_id==0:mask_id=mask.get_instance_id()
		t.eq(mask.get_instance_id(),mask_id,"all terrain batches share one mask resource")
		t.near(float(material.get_shader_parameter("tile_m")),2.0,.0001,"surface density follows source metres")
	t.eq(loaded,2,"base terrain and airport turf share full coverage")
	t.eq(legacy_sand,1,"coastline is classified separately")
	t.suite("AdelaideGround / live quality changes and protected map")
	for quality in [2,1,0,2]:
		Settings.effects_quality=quality;Settings.changed.emit()
		for material:ShaderMaterial in city._surface_materials:
			if not material.shader.resource_path.ends_with("adelaide_ground.gdshader"):continue
			t.eq(int(material.get_shader_parameter("ground_quality")),quality,"quality changes without rebuilding the world")
			t.eq(int(material.get_shader_parameter("surface_detail")),0 if quality==0 else 1,"low quality disables material response maps")
	city.set_surface_trials_enabled(false)
	for material:ShaderMaterial in city._surface_materials:t.not_ok(material.get_shader_parameter("trial_enabled"),"material rollback stays functional")
	city.set_surface_trials_enabled(true)
	for material:ShaderMaterial in city._surface_materials:t.ok(material.get_shader_parameter("trial_enabled"),"citywide material restores")
	t.eq(city.get_node("AdelaideAirport/MSSortiePath").curve.point_count,5,"hangar sortie route remains intact")
	city.free();await host.get_tree().process_frame
	Settings.effects_quality=old_quality;Settings.changed.emit()
