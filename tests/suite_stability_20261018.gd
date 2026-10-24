extends RefCounted
const Samples:=preload("res://scripts/flight/mesh_sample_cache.gd")
const Warm:=preload("res://scripts/flight/loadout_warmup.gd")
static func uncached(mesh:Mesh)->PackedVector3Array:
	var points:=PackedVector3Array()
	for surface in mesh.get_surface_count():
		var vertices:PackedVector3Array=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for index in range(0,vertices.size(),maxi(1,vertices.size()/1600)):points.append(vertices[index])
	return points
static func old_world_points(body:Node3D,mesh:MeshInstance3D)->Array[Vector3]:
	var points:Array[Vector3]=[];var xf:Transform3D=body.global_transform.affine_inverse()*mesh.global_transform
	for surface in mesh.mesh.get_surface_count():
		var vertices:PackedVector3Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for index in range(0,vertices.size(),maxi(1,vertices.size()/1600)):points.append(xf*vertices[index])
	return points
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();var previous:=FlightBody.use_placeholder
	t.suite("Stability / compact mesh samples, invalidation and bounded retention")
	Samples.clear()
	var mesh:=ArrayMesh.new();var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();vertices.resize(120000)
	for i in vertices.size():vertices[i]=Vector3(i%317,(i/317)%131,i%7)
	arrays[Mesh.ARRAY_VERTEX]=vertices;mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var expected:=uncached(mesh);var actual:=Samples.sample(mesh)
	t.eq(actual,expected,"native points exactly preserve old sampling")
	for i in 50:Samples.sample(mesh)
	t.eq(Samples.reads,1,"same mesh is read once across repeated bindings")
	var stage:=Node3D.new();host.add_child(stage);var node:=MeshInstance3D.new();node.mesh=mesh;stage.add_child(node);node.position=Vector3(7,-3,11)
	var translated:=preload("res://scripts/flight/weapon_emitters.gd").mesh_points(stage,node)
	t.lt(translated[0].distance_to(expected[0]+node.position),.0001,"different instances retain their own transform")
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);Samples.sample(mesh)
	t.eq(Samples.reads,3,"changing a mesh invalidates sampled geometry")
	var models:Array[Mesh]=[]
	for i in 110:
		var model:=BoxMesh.new();models.append(model);Samples.sample(model)
	t.ok(Samples.entries.size()<=Samples.MAX_ENTRIES,"mesh cache has a hard entry cap")
	t.ok(Samples.point_count<=Samples.MAX_POINTS,"mesh sample memory has a hard point cap")
	Samples.clear();var start:=Time.get_ticks_usec()
	for i in 80:uncached(mesh)
	var raw_ms:=float(Time.get_ticks_usec()-start)/1000.0
	Samples.sample(mesh);start=Time.get_ticks_usec()
	for i in 80:Samples.sample(mesh)
	var cached_ms:=float(Time.get_ticks_usec()-start)/1000.0
	print("PERF_SAMPLE baseline_ms=",raw_ms," cached_ms=",cached_ms," reads=",Samples.reads," retained_points=",Samples.point_count)
	start=Time.get_ticks_usec()
	for i in 80:old_world_points(stage,node)
	var old_world_ms:=float(Time.get_ticks_usec()-start)/1000.0
	start=Time.get_ticks_usec()
	for i in 80:preload("res://scripts/flight/weapon_emitters.gd").mesh_points(stage,node)
	print("PERF_WORLD_POINTS baseline_ms=",old_world_ms," optimized_ms=",float(Time.get_ticks_usec()-start)/1000.0)
	stage.free();models.clear();Samples.clear()
	t.suite("Stability / transient visual budget and invisible-particle cleanup")
	Settings.effects_quality=0;stage=Node3D.new();host.add_child(stage)
	var budget_root:=host.get_tree().root.get_node_or_null("TransientFXBudget")
	if budget_root!=null:budget_root.prune()
	var fx_start:=Time.get_ticks_usec()
	for i in 140:FX.hit_spark(stage,Vector3(i,0,0))
	print("PERF_FX burst=140 creation_ms=",float(Time.get_ticks_usec()-fx_start)/1000.0," gpu_emitters=",stage.find_children("*","GPUParticles3D",true,false).size())
	var budget=host.get_tree().root.get_node("TransientFXBudget")
	t.ok(budget.entries.size()<=48,"hit effects cannot accumulate without bound")
	t.ok(budget.rejected>=116,"excess same-frame hits skip GPU/material allocation")
	t.ok(stage.find_children("*","GPUParticles3D",true,false).size()<=24,"same-frame emission count is bounded before GPU construction")
	var untouched:=Node3D.new();stage.add_child(untouched)
	await host.get_tree().process_frame
	t.ok(stage.get_child_count()<=49,"retired visuals are actually released")
	budget._process(2.1);await host.get_tree().process_frame
	t.eq(budget.entries.size(),0,"watchdog expires effects even when GPU finished never arrives")
	t.ok(is_instance_valid(untouched),"budget cannot destroy an unregistered combat object")
	var curve1:=FX._curve([Vector2(0,1),Vector2(1,.4)])
	var curve2:=FX._curve([Vector2(0,1),Vector2(1,.4)])
	t.eq(curve1,curve2,"constant particle curves reuse their GPU resource")
	for i in 90:FX._curve([Vector2(0,1),Vector2(1,float(i)/100)])
	t.ok(FX._curve_cache.size()<=64,"particle curve cache is bounded")
	stage.free();await host.get_tree().process_frame
	t.suite("Stability / responsive and scoped threaded loadout reads")
	FlightBody.use_placeholder=false
	var loadout:=Warm.paths([SuitProfile.Id.SAZABI,SuitProfile.Id.SAZABI,-1])
	t.eq(loadout.size(),5,"selected Sazabi loadout deduplicates body and four weapons")
	t.eq(Warm.MAX_JOBS,2,"loading never creates an unbounded IO worker batch")
	FlightBody.use_placeholder=true;t.eq(Warm.paths([SuitProfile.Id.SAZABI]).size(),0,"placeholder tooling does not load heavyweight real assets")
	var paths:Array[String]=[]
	for i in 2:
		var root:=Node3D.new();root.name="WarmProbe%d"%i
		var packed:=PackedScene.new();packed.pack(root);root.free()
		var path:="user://stability_warm_probe_%d.tscn"%i
		t.eq(ResourceSaver.save(packed,path),OK,"small asynchronous load fixture saved")
		paths.append(path)
	var progress:Array=[]
	var held:=await Warm.warm(host,paths,func(done:int,total:int):progress.append(Vector2i(done,total)))
	t.eq(held.size(),2,"both requested scenes finish reading")
	t.ok(held[0] is PackedScene and held[1] is PackedScene,"warmup returns instantiable resources")
	t.eq(progress.back(),Vector2i(2,2),"loading progress reaches completion")
	for path in paths:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	held.clear();FlightBody.use_placeholder=previous;Settings.end_isolated()
