extends RefCounted
const GRID := preload("res://scripts/world/ocean_detail_mesh.gd")
const FFT := preload("res://scripts/world/fft_ocean_detail.gd")
const CLOUD := preload("res://scripts/world/local_cloud_volume.gd")

static func run(t, host: Node) -> void:
	t.suite("EnvironmentDetail / adaptive ocean topology and bandwidth")
	var mesh := GRID.build(WorldBuilder.OCEAN_SIZE * 0.5)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	t.eq(vertices.size(), (GRID.SEGMENTS + 1) * (GRID.SEGMENTS + 1), "complete connected lattice")
	t.eq(indices.size(), GRID.SEGMENTS * GRID.SEGMENTS * 6, "two triangles per cell")
	t.near(vertices[0].x, -WorldBuilder.OCEAN_SIZE * 0.5, 0.1, "full sea extent retained")
	t.near(vertices[-1].z, WorldBuilder.OCEAN_SIZE * 0.5, 0.1, "opposite sea edge retained")
	var center := (GRID.SEGMENTS / 2) * (GRID.SEGMENTS + 1) + GRID.SEGMENTS / 2
	t.near(vertices[center].length(), 0.0, 0.001, "camera anchor at grid centre")
	t.ok(uv2[center].x < 10.0, "near-camera cells resolve waves, below 10 m")
	t.gt(uv2[0].x, uv2[center].x * 100.0, "far cells progressively coarsen")
	var monotonic := true
	var symmetric := true
	for i in range(GRID.SEGMENTS):
		monotonic = monotonic and vertices[i + 1].x > vertices[i].x
		symmetric = symmetric and absf(vertices[i].x + vertices[GRID.SEGMENTS - i].x) < 0.1
	t.ok(monotonic, "no inverted/overlapping strips")
	t.ok(symmetric, "grid balanced around camera")
	var valid := true
	var clockwise := true
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		valid = valid and a.is_finite() and b.is_finite() and c.is_finite()
		clockwise = clockwise and (b - a).cross(c - a).y < 0.0
	t.ok(valid, "all generated vertices finite")
	t.ok(clockwise, "all triangles consistently wound")
	t.near(GRID.wave_weight(72.0, 30.0), 0.0, 0.001, "unresolved waves removed")
	t.near(GRID.wave_weight(72.0, 8.0), 1.0, 0.001, "near waves fully resolved")
	t.ok(GRID.wave_weight(72.0, 12.0) > 0.0 and GRID.wave_weight(72.0, 12.0) < 1.0, "continuous transition, no binary LOD switch")
	t.ok(indices.size() / 3 < WorldBuilder.OCEAN_SEG * WorldBuilder.OCEAN_SEG * 2, "adaptive grid has fewer triangles than legacy")

	t.suite("EnvironmentDetail / FFT frame-pair interpolation")
	t.near(FFT.b_weight(10.0, 10.0, 11.0, 1), 0.0, 0.001, "new B starts from previous A")
	t.near(FFT.b_weight(11.0, 10.0, 11.0, 1), 1.0, 0.001, "new B ends on current B")
	t.near(FFT.b_weight(10.0, 10.0, 11.0, 0), 1.0, 0.001, "new A starts from previous B")
	t.near(FFT.b_weight(10.25, 10.0, 11.0, 0), 0.75, 0.001, "A/B reversal preserves interpolation time")
	t.near(FFT.b_weight(12.0, 10.0, 11.0, 0), 0.0, 0.001, "late frame never extrapolates texture pair")

	t.suite("EnvironmentDetail / local clouds bounded and deterministic")
	var clouds := CLOUD.new()
	var transforms: Array[Transform3D] = []
	for i in 12:
		transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1000, 600, 1000)), Vector3(i * 80, 4000, 0)))
	clouds.configure([transforms, [], []])
	var point := Vector3(200, 4000, 0)
	var near_ids := clouds.nearest(point)
	t.eq(near_ids.size(), 4, "maximum four fog volumes")
	t.eq(near_ids, clouds.nearest(point), "stable selection without RNG")
	t.eq(clouds.nearest(Vector3(100000, 0, 0)).size(), 0, "no local fog outside cloud field")
	t.near(CLOUD.normalized_distance(transforms[0].origin, transforms[0]), 0.0, 0.001, "density centre follows source puff")
	t.near(CLOUD.normalized_distance(Vector3(500,4000,0), transforms[0]), 1.0, 0.001, "extent matches cloud radius")
	clouds.configure([])
	t.eq(clouds.samples.size(), 0, "reconfiguration drops previous map samples")
	clouds.free()

	t.suite("EnvironmentDetail / world lifecycle and material gates")
	var w := WorldBuilder.new()
	w.initial_map = MapDef.Id.PACIFIC
	host.add_child(w)
	t.ok(w.ocean.mesh is ArrayMesh, "default ocean uses connected adaptive mesh")
	t.eq(w.ocean.has_node("FFTSea"), FFT.supported(), "FFT resources require an actual rendering device")
	t.eq(w._ocean_mat.get_shader_parameter("adaptive_mesh"), true, "vertex transform gate enabled")
	t.near(float(w._ocean_mat.get_shader_parameter("wave_amp")), 4.0, 0.001, "collision-safe displacement envelope unchanged")
	var enabled_mat := w._terrain_material(Color.WHITE, 0.9, true, 0.5, 0.4) as ShaderMaterial
	t.near(float(enabled_mat.get_shader_parameter("surface_detail")), 1.0, 0.001, "terrain detail wired")
	t.suite("EnvironmentDetail / thicker cloud banks and atmospheric sky")
	var largest_width := 0.0
	var smallest_width := INF
	var tallest := 0.0
	var floor_valid := true
	for xf: Transform3D in w.cloud_bands[1]:
		largest_width = maxf(largest_width, xf.basis.x.length())
		smallest_width = minf(smallest_width, xf.basis.x.length())
		tallest = maxf(tallest, xf.basis.y.length())
		floor_valid = floor_valid and xf.origin.y - xf.basis.y.length() * 0.5 >= WorldBuilder.CLOUD_FLOOR - 0.01
	t.near(largest_width, 2100.0 * 5.0, 0.01, "large cloud width equals five former largest puffs")
	t.ok(smallest_width >= 2100.0, "small cumulus at least former largest puff size")
	t.gt(tallest, 2100.0 * 1.7, "cumulus has substantially greater vertical thickness")
	t.ok(floor_valid, "thicker clouds retain minimum cloud floor")
	t.near(float(w._sky_mat.get_shader_parameter("star_coverage")), 0.14, 0.001, "Pacific retains fourteen percent of old star candidates")
	t.near(float(w._sky_mat.get_shader_parameter("atmosphere")), 1.0, 0.001, "ground atmosphere enabled")
	t.near(MapDef.pacific().cloud_altitude_offset, 0.0, 0.01, "Pacific cloud altitude retained")
	t.near(MapDef.uluru().cloud_altitude_offset, 4000.0, 0.01, "desert clouds raised 4 km")
	t.near(MapDef.training_range().cloud_altitude_offset, 4000.0, 0.01, "range clouds raised 4 km")
	t.near(MapDef.oenbelli().cloud_altitude_offset, 6000.0, 0.01, "Oenbelli clouds clear skyline by higher band")
	t.near(MapDef.davao().cloud_altitude_offset, 6000.0, 0.01, "Davao clouds raised 6 km")
	var near_cloud := CLOUD.new()
	near_cloud.configure(w.cloud_bands)
	var largest: Transform3D = w.cloud_bands[1][0]
	t.ok(not near_cloud.nearest(largest.origin + Vector3(4000, 0, 0)).is_empty(), "large-bank fog discoverable away from its centre bucket")
	near_cloud.free()
	w.environment_detail_enabled = false
	w.apply_map(MapDef.pacific())
	t.ok(w.ocean.mesh is PlaneMesh, "A/B restores original plane")
	t.eq(w._ocean_mat.get_shader_parameter("adaptive_mesh"), false, "legacy geometry sampling restored")
	for m: ShaderMaterial in w._cloud_mats:
		t.near(float(m.get_shader_parameter("surface_detail")), 0.0, 0.001, "cloud A/B gate restored")
	# Inspect actual geometry, not just the per-map offset data.
	for definition: MapDef in [MapDef.uluru(), MapDef.training_range(), MapDef.oenbelli(), MapDef.davao()]:
		w.map = definition
		w._rebuild_clouds(definition.cloud_density)
		var lowest := INF
		for band: Array in w.cloud_bands:
			for xf: Transform3D in band:
				lowest = minf(lowest, xf.origin.y - xf.basis.y.length() * 0.5)
		t.ok(lowest >= WorldBuilder.CLOUD_FLOOR + definition.cloud_altitude_offset - 0.1, definition.code + " actual cloud geometry respects raised floor")
		var first: Transform3D = w.cloud_bands[1][0]
		t.near(first.basis.z.length(), first.basis.x.length(), 0.01, definition.code + " cloud depth is a full 3D volume")
	w.environment_detail_enabled = true
	w.apply_map(MapDef.leo())
	t.ok(w.ocean == null, "space never receives ocean")
	t.near(float(w._sky_mat.get_shader_parameter("atmosphere")), 0.0, 0.001, "space preserves original sky shader branch")
	t.near(float(w._sky_mat.get_shader_parameter("star_brightness")), 2.9, 0.001, "orbital star brightness unchanged")
	t.eq(w.cloud_bands.size(), 0, "orbit clears old atmospheric cloud data")
	t.near(w.cloud_shade_at(Vector3.ZERO), 0.0, 0.001, "orbit clears ground cloud shadows")
	t.ok(not is_instance_valid(w._local_cloud_volume), "space never receives local atmosphere")
	w.free()
	await host.get_tree().process_frame
