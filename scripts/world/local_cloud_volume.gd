extends Node3D
## Four static-position cloud volumes selected around the active camera.
## Selection is throttled; opacity eases to zero before a slot is reassigned.
const FOG_SHADER := preload("res://shaders/cloud_volume.gdshader")
const SLOT_COUNT := 4
const DENSITY_BUDGET := 0.00014
var samples: Array[Transform3D] = []
var buckets: Dictionary = {}
var query_cells := 1
const CELL_SIZE := 4096.0
var fogs: Array[FogVolume] = []
var selected: Array[int] = [-1, -1, -1, -1]
var weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
var desired: Array[int] = []
var tint := Color(0.2, 0.24, 0.32)
var elapsed := 1.0

func configure(bands: Array) -> void:
	samples.clear()
	buckets.clear()
	selected.fill(-1)
	weights.fill(0.0)
	desired.clear()
	elapsed=1.0
	for fog in fogs:
		fog.visible=false
		(fog.material as ShaderMaterial).set_shader_parameter("density_scale",0.0)
	var max_radius := 1.0
	# Low and main cumulus only. High cirrus stays thin.
	for b in mini(2, bands.size()):
		for xf: Transform3D in bands[b]:
			samples.append(xf)
			max_radius = maxf(max_radius, maxf(xf.basis.x.length(), xf.basis.y.length()) * 0.5)
			var key := Vector3i((xf.origin / CELL_SIZE).floor())
			if not buckets.has(key): buckets[key] = []
			buckets[key].append(samples.size() - 1)
	query_cells = maxi(1, int(ceil(max_radius * 1.35 / CELL_SIZE)))

func _ready() -> void:
	for i in SLOT_COUNT:
		var fog := FogVolume.new()
		fog.name = "LocalCloud%d" % i
		fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		var mat := ShaderMaterial.new()
		mat.shader = FOG_SHADER
		fog.material = mat
		fog.visible = false
		add_child(fog)
		fogs.append(fog)

var quality_active := true
func _process(delta: float) -> void:
	var enabled:=Settings.effects_quality==2
	if not enabled:
		if quality_active:
			for fog in fogs:fog.visible=false
			weights.fill(0.0)
			selected.fill(-1)
			desired.clear()
		quality_active=false
		return
	if not quality_active:elapsed=1.0
	quality_active=true
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	step_near_camera(camera.global_position,delta)

func step_near_camera(point: Vector3,delta: float) -> void:
	elapsed += delta
	if elapsed >= 0.25:
		elapsed = 0.0
		desired = nearest(point)
	for i in SLOT_COUNT:
		var idx := selected[i]
		var target := 0.0
		if idx >= 0 and desired.has(idx):
			target = 1.0 - smoothstep(0.65, 1.35, normalized_distance(point, samples[idx]))
		weights[i] = move_toward(weights[i], target, delta * 2.5)
		if weights[i] <= 0.001 and (idx < 0 or not desired.has(idx)):
			selected[i] = -1
			for candidate in desired:
				if not selected.has(candidate):
					selected[i] = candidate
					var xf := samples[candidate]
					fogs[i].position = xf.origin
					fogs[i].size = Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.x.length())
					break
	var total_weight:=0.0
	for weight in weights: total_weight+=weight
	for i in SLOT_COUNT:
		fogs[i].visible = selected[i] >= 0 and weights[i] > 0.001
		var mat := fogs[i].material as ShaderMaterial
		mat.set_shader_parameter("density_scale", weights[i]*DENSITY_BUDGET/maxf(total_weight,1.0))
		mat.set_shader_parameter("cloud_tint", Vector3(tint.r, tint.g, tint.b))

static func normalized_distance(point: Vector3, xf: Transform3D) -> float:
	var radius := Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.x.length()) * 0.5
	radius = radius.max(Vector3.ONE)
	return ((point - xf.origin) / radius).length()

func nearest(point: Vector3) -> Array[int]:
	var ids: Array[int] = []
	var distances: Array[float] = []
	var key := Vector3i((point / CELL_SIZE).floor())
	var candidates: Array = []
	for occupied: Vector3i in buckets:
		var offset := (occupied - key).abs()
		if maxi(offset.x, maxi(offset.y, offset.z)) <= query_cells:
			candidates.append_array(buckets[occupied])
	for value in candidates:
		var i := int(value)
		var d := normalized_distance(point, samples[i])
		if d >= 1.35:
			continue
		var at := 0
		while at < distances.size() and distances[at] < d:
			at += 1
		ids.insert(at, i)
		distances.insert(at, d)
		if ids.size() > SLOT_COUNT:
			ids.resize(SLOT_COUNT)
			distances.resize(SLOT_COUNT)
	return ids
