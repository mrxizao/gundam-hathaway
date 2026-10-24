extends RefCounted
const Road:=preload("res://scripts/world/road_surface.gd")
static func run(t:T,host:Node)->void:
	t.suite("RoadSurface / three cities, PBR sharing and geometry invariants")
	var old:=Settings.effects_quality
	var materials:Array=[]
	for role in 5:
		var m:=Road.material(role,Color(0.2,0.21,0.2))
		materials.append(m)
		t.eq(m.get_shader_parameter("road_role"),role,"explicit road semantics")
		if role<3:
			for channel in ["surface_albedo","surface_normal","surface_orm"]:
				var tex:Texture2D=m.get_shader_parameter(channel)
				t.eq(tex.get_width(),2048,"2K aligned PBR source")
				t.eq(tex.get_height(),2048,"2K aligned PBR source")
	var shared:=Road.material(0,Color(0.12,0.14,0.15))
	t.eq(materials[0].get_shader_parameter("surface_albedo"),shared.get_shader_parameter("surface_albedo"),"maps share texture resource, not per-instance copies")
	for mp:MapDef in [MapDef.oenbelli(),MapDef.davao()]:
		# Production tests never depend on the external audit fixture.
		var world:=WorldBuilder.new();world.defer_initial_map=true;host.add_child(world);await world.apply_map_staged(mp)
		var counts:={};var transform_digest:={}
		for name:String in Road.ROAD_NAMES:
			var node:=world.find_child(name,true,false)
			if node==null:continue
			t.ok(node is MultiMeshInstance3D,mp.name_cn+" retains instanced "+name)
			t.ok(node.material_override is ShaderMaterial,"real builder binds shared road shader")
			t.eq(node.material_override.get_shader_parameter("road_role"),Road.ROAD_NAMES[name],"surface role follows node purpose")
			counts[name]=node.multimesh.instance_count
			t.gt(counts[name],0,"road batch has geometry")
			if name=="CityRoadMarks":
				var original:StandardMaterial3D=node.get_meta("road_baseline")
				t.eq(node.material_override.get_shader_parameter("emission_energy")>0.0,original.emission_enabled,"night paint keeps original emission policy")
		for quality in [0,1,2]:
			Settings.effects_quality=quality;await host.get_tree().process_frame
			for material:ShaderMaterial in world._road_materials:t.eq(material.get_shader_parameter("road_quality"),quality,"quality changes on existing road, bridge and ring materials")
		world.apply_map(MapDef.pacific())
		t.eq(world._road_materials.size(),0,"map switch releases owned materials")
		world.free();await host.get_tree().process_frame
	Settings.effects_quality=old;Settings.changed.emit()
