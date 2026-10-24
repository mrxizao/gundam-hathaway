extends RefCounted
static func run(t: T,host: Node) -> void:
	t.suite("AdelaideCinematicDetail / additive modules and geometry budget")
	var city=load("res://scripts/world/adelaide_builder.gd").new()
	host.add_child(city)
	await city.build_staged()
	t.eq(city.airport_detail_bays,6,"all six hangars receive service structure")
	t.gt(city.detailed_roofs,10,"flight corridor has rooftop detail")
	t.ok(city.detailed_roofs<=72,"rooftop budget is bounded")
	t.gt(city.roadside_modules,0,"flight corridor has roadside modules")
	t.ok(city.roadside_modules<=48,"roadside budget is bounded")
	var meshes:=0
	var vertices:=0
	for child in city.get_children():
		if child is MeshInstance3D and child.has_meta("cinematic_detail"):
			meshes+=1
			t.ok(child.visibility_range_end<=14000.0,"detail has finite culling distance")
			t.ok(child.get_aabb().size.length()<20000.0,"detail is batched locally, not across the city")
			for surface in child.mesh.get_surface_count(): vertices+=child.mesh.surface_get_array_len(surface)
	t.gt(meshes,0,"detail geometry was built")
	t.ok(meshes<=256,"local detail draw batch budget")
	t.ok(vertices/3<=60000,"added geometry stays within 60000 triangles")
	t.suite("AdelaideCinematicDetail / protected airport and river clearance")
	var base: Node3D=city.get_node("AdelaideAirport")
	for n in 6:
		var z: float=1500.0+n*540
		t.eq(base.get_node("MSStand%02d" % (n+1)).position,Vector3(-9480,27,(z-30)*3),"stand marker unchanged")
		t.eq(base.get_node("HangarExit%02d" % (n+1)).position,Vector3(-9480,27,(z-360)*3),"exit marker unchanged")
	var expected: Array[Vector3]=[Vector3(-12600,28,12900),Vector3(-14010,28,12900),Vector3(-14970,28,12900),Vector3(-14970,220,5400),Vector3(-14970,900,-1200)]
	var path: Path3D=base.get_node("MSSortiePath")
	t.eq(path.curve.point_count,expected.size(),"sortie waypoint count unchanged")
	for i in expected.size(): t.eq(path.curve.get_point_position(i),expected[i],"sortie waypoint unchanged")
	await host.get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D=city.get_world_3d().direct_space_state
	for n in 6:
		var z: float=(1500+n*540)*3
		for offset: float in [-55,0,55]:
			for height: float in [55,110,145]:
				var query:=PhysicsRayQueryParameters3D.create(Vector3(-9480+offset,height,z),Vector3(-9480+offset,height,z-1080),1)
				t.ok(space.intersect_ray(query).is_empty(),"MS body and shoulder departure lane remains clear")
	for i in expected.size()-1:
		var query:=PhysicsRayQueryParameters3D.create(expected[i]+Vector3.UP*40,expected[i+1]+Vector3.UP*40,1)
		t.ok(space.intersect_ray(query).is_empty(),"sortie path remains clear")
	var rx:=300.0
	var rz: float=city.river_z(rx)
	var query:=PhysicsRayQueryParameters3D.create(Vector3(rx*18,100,rz*18),Vector3(rx*18,-50,rz*18),1)
	var hit: Dictionary=space.intersect_ray(query)
	t.ok(not hit.is_empty(),"riverbed collision retained")
	if not hit.is_empty(): t.lt(hit.position.y,1.0,"riverbed remains below water surface")
	city.free()
	await host.get_tree().process_frame
