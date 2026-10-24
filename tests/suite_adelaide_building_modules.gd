extends RefCounted
const Library:=preload("res://scripts/world/adelaide_building_library.gd")
const Meshes:=preload("res://scripts/world/adelaide_building_mesh.gd")
const Materials:=preload("res://scripts/world/adelaide_building_material.gd")
static func digest(v:Variant)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(v));return h.finish().hex_encode()
static func run(t:T,host:Node)->void:
	t.suite("AdelaideBuildingModules / six metre-scale prototypes and three LODs")
	for style in 6:
		var counts:Array[int]=[]
		for lod in 3:
			var mesh:ArrayMesh=Meshes.new().build(Vector3(260,640,220),style,lod)
			counts.append(Meshes.triangle_count(mesh))
			var normal_ok:=true;var tangent_ok:=true;var winding_ok:=true;var bounds_ok:=true
			for surface in mesh.get_surface_count():
				var a:=mesh.surface_get_arrays(surface);var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=a[Mesh.ARRAY_NORMAL];var tangents:PackedFloat32Array=a[Mesh.ARRAY_TANGENT]
				if tangents.size()!=vertices.size()*4:tangent_ok=false
				for p:Vector3 in vertices:
					if not p.is_finite() or absf(p.x)>130.01 or absf(p.z)>110.01 or p.y<-.01 or p.y>653.0:bounds_ok=false
				for n:Vector3 in normals:
					if not n.is_finite() or absf(n.length()-1.0)>.001:normal_ok=false
				for i in range(0,vertices.size(),3):
					var cross:Vector3=(vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i])
					if cross.length()<.0001 or cross.normalized().dot(normals[i])>-.999:winding_ok=false
				t.eq(a[Mesh.ARRAY_TEX_UV].size(),vertices.size(),"all surfaces have physical UVs")
			t.ok(normal_ok,"unit outward normals")
			t.ok(tangent_ok,"real tangent frame for OpenGL normals")
			t.ok(winding_ok,"clockwise front faces agree with outward normals")
			t.ok(bounds_ok,"all modules remain in the original footprint")
			t.eq(mesh.get_meta("floor_m"),6.4,"floor scale remains fixed at every LOD")
			t.ok(counts[-1]<=12000,"per-building mesh budget")
		t.gt(counts[0],counts[1],"middle LOD actually simplifies geometry")
		t.gt(counts[1],counts[2],"far LOD actually simplifies geometry")
	for role in 4:
		var m:=Materials.material(role,0)
		for key in ["surface_albedo","surface_normal","surface_orm"]:t.eq(m.get_shader_parameter(key).get_width(),2048,"all PBR and atlas channels aligned at 2K")
	var shared_a:=Materials.material(0,0);var shared_b:=Materials.material(0,1)
	t.eq(shared_a.get_shader_parameter("surface_albedo"),shared_b.get_shader_parameter("surface_albedo"),"six styles share underlying textures")
	t.suite("AdelaideBuildingModules / actual replacements, protected map and LOD lifecycle")
	var before:Node3D=load("res://scripts/world/adelaide_builder.gd").new();before.building_modules_enabled=false;host.add_child(before);await before.build_staged()
	var after:Node3D=load("res://scripts/world/adelaide_builder.gd").new();host.add_child(after);await after.build_staged()
	var lib:Node3D=after.building_library
	t.eq(lib.entries.size(),48,"exactly 48 intended display replacements")
	t.eq(after.parcel_records,before.parcel_records,"all parcel IDs, damage flags, heights and colours retained")
	t.eq(after.roads,before.roads,"road plan retained")
	t.eq(after.bridge_sites,before.bridge_sites,"bridges retained")
	t.eq(after.rng.state,before.rng.state,"all city and forest random draws retained")
	var collision:PackedVector3Array=after.get_node("AdelaideCollision").get_child(0).shape.get_faces()
	t.eq(digest(collision),"7c68ed731e57f1f796091dca32990d706f3765c6b4c260789d4c905e54768dd0","all original collision vertices retained byte-for-byte")
	t.eq(digest(collision),digest(before.get_node("AdelaideCollision").get_child(0).shape.get_faces()),"model changes add no collision triangles")
	var style_counts:={};var selected:={};var buckets:={}
	for entry:Dictionary in lib.entries:
		var shadow:MeshInstance3D=entry.root.get_node("ShadowCaster")
		t.eq(shadow.mesh.get_surface_count(),1,"shadow materials fuse into one depth surface")
		t.eq(shadow.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"shadow geometry never doubles visible facades")
		t.eq(shadow.mesh.get_meta("triangles"),entry.levels[0].mesh.get_meta("triangles"),"full-detail shadow silhouette is retained")
		for level in entry.levels:t.eq(level.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"LOD surfaces do not duplicate shadow passes")
		for lod in [1,2]:
			var merged:ArrayMesh=entry.levels[lod].mesh
			var rect_for_merge:Rect2=entry.record.bounds
			var source:ArrayMesh=Meshes.new().build(Vector3(rect_for_merge.size.x,entry.record.height,rect_for_merge.size.y),entry.style,lod)
			t.eq(merged.get_surface_count(),1,"middle and far buildings submit only one material surface")
			t.eq(merged.get_aabb(),source.get_aabb(),"draw merging preserves the exact building envelope")
			t.eq(merged.get_meta("triangles"),source.get_meta("triangles"),"draw merging does not drop silhouette geometry")
		t.not_ok(entry.record.damaged,"ruined buildings stay on the existing ruin model")
		t.ok(Library.route_distance(entry.record.bounds.get_center())<=5000.01,"every replacement is near the actual low flight route")
		style_counts[entry.style]=int(style_counts.get(entry.style,0))+1;selected[entry.id]=entry.style
		var rect:Rect2=entry.record.bounds.grow(.2)
		for ix in range(floori(rect.position.x/2000),floori(rect.end.x/2000)+1):
			for iz in range(floori(rect.position.y/2000),floori(rect.end.y/2000)+1):
				var key:=Vector2i(ix,iz)
				if not buckets.has(key):buckets[key]=[]
				buckets[key].append(entry.record)
	for style in 6:t.eq(style_counts.get(style,0),8,"each style has eight route examples")
	t.eq(selected,Library.TARGETS,"baked route selection matches production targets")
	var chosen:=Library.choose(after.parcel_records);var chosen_ids:={}
	for record:Dictionary in chosen:chosen_ids[record.id]=record.style
	t.eq(chosen_ids,Library.TARGETS,"selection is reproducible from actual current parcels")
	var duplicates:=0
	for child in after.get_children():
		if not child is MeshInstance3D or child.get_meta("surface_family",0)!=0:continue
		for surface in child.mesh.get_surface_count():
			var a:PackedVector3Array=child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for i in range(0,a.size(),3):
				var p:Vector3=(a[i]+a[i+1]+a[i+2])/3.0
				for record:Dictionary in buckets.get(Vector2i(floori(p.x/2000),floori(p.z/2000)),[]):
					if p.y>25.5 and p.y<25.0+record.height-.01 and record.bounds.grow(.2).has_point(Vector2(p.x,p.z)):duplicates+=1
	t.eq(duplicates,0,"old facade triangles are removed, not hidden behind the replacement")
	var old_quality:int=Settings.effects_quality
	var cam:=Camera3D.new();host.add_child(cam);cam.current=true
	var e:Dictionary=lib.entries[0];var rect:Rect2=e.record.bounds
	cam.position=e.root.global_position+Vector3(0,e.record.height*.5,rect.size.y*.5+120);cam.look_at(e.root.global_position+Vector3.UP*e.record.height*.5)
	for quality in [0,1,2]:
		Settings.effects_quality=quality;lib.refresh_quality();lib.update_lods(cam)
		for material:ShaderMaterial in lib.materials.values():t.eq(material.get_shader_parameter("building_quality"),quality,"quality applies to existing materials")
		var near_count:=0
		for entry:Dictionary in lib.entries:
			if entry.level==0:near_count+=1
			t.ok(entry.level>=2-quality,"quality caps geometric detail")
		t.ok(near_count<=6,"near detail has an explicit visible budget")
	lib.force_lod=2;lib.update_lods(cam)
	t.eq(e.old,-1,"forced LOD cancels transitions")
	lib.set_lod(e,0,true);t.eq(e.old,2,"transition keeps old geometry temporarily")
	t.ok(e.levels[0].visible and e.levels[2].visible,"complementary masks cover the handover")
	lib.set_lod(e,1,false)
	t.ok(e.levels[1].visible and not e.levels[0].visible and not e.levels[2].visible,"hard quality switch cannot leave stale LODs")
	lib.force_lod=-1;Settings.effects_quality=2;lib.refresh_quality()
	var tall:Dictionary=lib.entries[0]
	for entry:Dictionary in lib.entries:
		if entry.record.height>tall.record.height:tall=entry
	var tb:Rect2=tall.record.bounds
	cam.position=tall.root.global_position+Vector3(0,30,-tb.size.y*.5-120)
	cam.look_at(tall.root.global_position+Vector3(0,30,-tb.size.y*.5))
	t.not_ok(cam.is_position_in_frustum(tall.root.global_position+Vector3.UP*tall.record.height*.5),"test views the tower base while its centre is off-screen")
	lib.update_lods(cam)
	t.eq(tall.level,0,"very close tower facades retain detail when the centre leaves the frustum")
	cam.free();Settings.effects_quality=old_quality;Settings.changed.emit()
	# Retained roof collision must have a visible representation while the main old box is suppressed.
	var roof:Node3D=load("res://scripts/world/adelaide_builder.gd").new();roof.emit_visual_geometry=false;roof._preserve_roof_y=100
	roof.box(Vector3(0,50,0),Vector3(20,100,20),Color(.5,.5,.5),true)
	t.eq(roof.batches.size(),0,"old full-height body is suppressed")
	roof.box(Vector3(0,110,0),Vector3(10,20,10),Color(.5,.5,.5),true)
	t.gt(roof.batches.size(),0,"existing colliding roof core remains visible")
	t.eq(roof.solid.size(),72,"suppression never removes collision faces")
	t.not_ok(roof.emit_visual_geometry,"roof preservation restores the facade gate")
	roof.free();before.free();after.free();await host.get_tree().process_frame
