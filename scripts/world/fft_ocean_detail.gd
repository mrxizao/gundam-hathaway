extends Node
const GENERATOR := preload("res://addons/environment_fft/wave_generator.gd")
const CASCADE := preload("res://addons/environment_fft/wave_cascade_parameters.gd")
## FFT subset from the MIT demo; rendering uses WorldBuilder's frozen/pauseable clock.
## 30 Hz future frames blend on GPU; all three cascades share the same time pair.
const MAP_SIZE := 256
const CASCADE_COUNT := 3
const STEP := 1.0 / 30.0
const WARM_STEPS := 16
var material: ShaderMaterial
var generator: GENERATOR
var cascades: Array[CASCADE] = []
var displacements: Array[Texture2DArrayRD] = []
var normals: Array[Texture2DArrayRD] = []
var previous_time := 0.0
var next_time := 0.0
var last_clock := -1.0
var dispatch_count := 0

static func supported() -> bool:
	return RenderingServer.get_rendering_device() != null

static func b_weight(clock: float, previous: float, future: float, newest: int) -> float:
	var f := clampf((clock - previous) / maxf(future - previous, 0.00001), 0.0, 1.0)
	return f if newest == 1 else 1.0 - f

func _clock() -> float:
	var value = material.get_shader_parameter("wave_time")
	return 0.0 if value == null else float(value)

func _ready() -> void:
	process_priority = 100
	if not supported():
		set_process(false)
		return
	_render_call(_initialize_gpu)

# The main RenderingDevice belongs to the render thread. In particular, freeing
# its buffers on the scene thread while a map is rendering can race GPU work.
# Wait for completion so map teardown cannot outlive its owner.
func _render_call(action: Callable) -> void:
	var done := Semaphore.new()
	RenderingServer.call_on_render_thread(func():
		action.call()
		done.post())
	done.wait()

func _initialize_gpu() -> void:
	for i in CASCADE_COUNT:
		var c := CASCADE.new()
		var length_m: float = [4096.0, 973.0, 233.0][i]
		c.tile_length = Vector2.ONE * length_m
		c.wind_speed = [18.0, 14.0, 10.0][i]
		c.wind_direction = 35.0 + i * 13.0
		c.fetch_length = 120.0
		c.water_depth_meters = 500.0
		c.displacement_scale = 0.55
		c.normal_scale = 0.90
		c.whitecap = 0.72
		c.initialize_runtime_state(Vector2i(7107 + i * 131, 9137 + i * 47), 0.0)
		cascades.append(c)
	generator = GENERATOR.new()
	generator.map_size = MAP_SIZE
	generator.init_gpu(CASCADE_COUNT)
	for suffix in ["a", "b"]:
		var d := Texture2DArrayRD.new()
		d.texture_rd_rid = generator.descriptors[StringName("displacement_map_" + suffix)].rid
		displacements.append(d)
		var n := Texture2DArrayRD.new()
		n.texture_rd_rid = generator.descriptors[StringName("normal_map_" + suffix)].rid
		normals.append(n)
	material.set_shader_parameter("fft_displacements_a", displacements[0])
	material.set_shader_parameter("fft_displacements_b", displacements[1])
	material.set_shader_parameter("fft_normals_a", normals[0])
	material.set_shader_parameter("fft_normals_b", normals[1])
	_restart_at(_clock())
	material.set_shader_parameter("fft_enabled", true)

func _compute_at(time: float) -> void:
	for i in CASCADE_COUNT:
		cascades[i].advance(time - cascades[i].time, 0.0, 0.0, false)
		generator.update_cascade(i, cascades[i])
	dispatch_count += 1

func _restart_at(clock: float) -> void:
	# Frozen captures get identical foam history, independent of scene startup time.
	for maps in generator.output_descriptors:
		for key in [&"displacement_map", &"normal_map"]:
			generator.context.device.texture_clear(maps[key].rid, Color(0,0,0,0), 0, generator.mip_count, 0, CASCADE_COUNT * 2)
	for c in cascades:
		c.time = clock - WARM_STEPS * STEP
		c.request_spectrum_reset()
	for i in WARM_STEPS + 1:
		_compute_at(clock - (WARM_STEPS - 1 - i) * STEP)
	previous_time = clock
	next_time = clock + STEP
	last_clock = clock
	_update_blend(clock)

func _update_blend(clock: float) -> void:
	material.set_shader_parameter("fft_b_weight", b_weight(clock, previous_time, next_time, generator.cascade_newest_output[0]))

func _process(_delta: float) -> void:
	if generator == null: return
	var clock := _clock()
	_render_call(_tick_gpu.bind(clock))

func _tick_gpu(clock: float) -> void:
	if clock < last_clock or clock - last_clock > 1.0:
		_restart_at(clock)
	elif clock >= next_time:
		previous_time = next_time
		next_time = maxf(next_time + STEP, clock + STEP)
		_compute_at(next_time)
	_update_blend(clock)
	last_clock = clock

func _exit_tree() -> void:
	set_process(false)
	if generator == null: return
	_render_call(_release_gpu)

func _release_gpu() -> void:
	material.set_shader_parameter("fft_enabled", false)
	for key in ["fft_displacements_a", "fft_displacements_b", "fft_normals_a", "fft_normals_b"]:
		material.set_shader_parameter(key, null)
	for texture in displacements: texture.texture_rd_rid = RID()
	for texture in normals: texture.texture_rd_rid = RID()
	generator.free()
	generator = null
