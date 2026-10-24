extends RefCounted
## Camera-centred exponential grid. Wave phase stays in world coordinates.
## A single connected mesh avoids ring cracks. UV2.x carries local cell size.
const SEGMENTS := 384
const CORE := 256.0
const SNAP := 4.0
static var cached_mesh: ArrayMesh
static var cached_half_size := -1.0

static func coordinate(u: float, half_size: float) -> float:
	return signf(u) * CORE * (exp(absf(u) * log(1.0 + half_size / CORE)) - 1.0)

static func wave_weight(wavelength: float, cell_size: float) -> float:
	return smoothstep(4.0, 8.0, wavelength / maxf(cell_size, 0.001))

static func build(half_size: float) -> ArrayMesh:
	if cached_mesh != null and is_equal_approx(cached_half_size, half_size):
		return cached_mesh
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	var axis := PackedFloat32Array()
	var cells := PackedFloat32Array()
	for i in range(SEGMENTS + 1):
		axis.append(coordinate(float(i) * 2.0 / SEGMENTS - 1.0, half_size))
	for i in range(SEGMENTS + 1):
		var left := axis[i] - axis[maxi(0, i - 1)]
		var right := axis[mini(SEGMENTS, i + 1)] - axis[i]
		cells.append(maxf(left, right))
	for z in range(SEGMENTS + 1):
		for x in range(SEGMENTS + 1):
			verts.append(Vector3(axis[x], 0.0, axis[z]))
			normals.append(Vector3.UP)
			uv.append(Vector2(float(x), float(z)) / float(SEGMENTS))
			uv2.append(Vector2(maxf(cells[x], cells[z]), 0.0))
	for z in range(SEGMENTS):
		for x in range(SEGMENTS):
			var a := z * (SEGMENTS + 1) + x
			var b := a + 1
			var c := a + SEGMENTS + 1
			indices.append_array(PackedInt32Array([a, b, c, b, c + 1, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	cached_mesh = mesh
	cached_half_size = half_size
	return mesh
