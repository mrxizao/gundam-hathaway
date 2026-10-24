extends Node3D
## Cosmetic electrical discharges. All visuals, lights and audio are bounded pools.
signal strike_generated(interior: bool, start: Vector3, end: Vector3)
const POOL_SIZE := 4
const CENTER := Vector3(0,12000,0)
var space_mode := false
var spatial_scale := 1.0
var rng := RandomNumberGenerator.new()
var slots: Array[Dictionary] = []
var sounds: Array[AudioStreamWAV] = []
var interval := 1.8
var preview_active := false
var strikes_inside := 0
var strikes_outside := 0

func _ready() -> void:
	name = "ColonyElectricalStorm"
	rng.randomize()
	for index in 3:
		# Native audio resources are included directly in exported games.
		sounds.append(load("res://assets/maps/colony_ruins/colony_thunder_%d.res" % (index+1)) as AudioStreamWAV)
	for index in POOL_SIZE:
		var mesh := MeshInstance3D.new()
		mesh.name = "PooledArc%d" % index
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		var light := OmniLight3D.new()
		light.light_color = Color(0.38,0.62,1.0)
		light.omni_range = 1000
		light.shadow_enabled = false
		add_child(light)
		var audio := AudioStreamPlayer3D.new()
		audio.bus = Settings.BUS_SFX
		audio.max_distance = 14000
		audio.unit_size = 2400
		audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(audio)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.emission_enabled = true
		material.emission = Color(0.60,0.76,1.0)
		material.emission_energy_multiplier = 3.5
		mesh.material_override = material
		mesh.visible = false
		light.visible = false
		slots.append({"mesh":mesh,"light":light,"audio":audio,"material":material,"age":10.0,"life":0.65,"sound_at":-1.0})

func _process(delta: float) -> void:
	var active := preview_active or Game.phase == Game.Phase.FIGHT
	if not active:
		for slot in slots:
			slot.mesh.visible = false
			slot.light.visible = false
			slot.sound_at = -1.0
			if slot.audio.playing: slot.audio.stop()
		return
	interval -= delta
	if interval <= 0:
		spawn_strike(rng.randf() < 0.6)
		interval = rng.randf_range(2.8,7.5)
	for slot in slots:
		slot.age += delta
		if slot.sound_at >= 0 and slot.age >= slot.sound_at:
			slot.audio.play()
			slot.sound_at = -1.0
		if slot.age >= slot.life:
			slot.mesh.visible = false
			slot.light.visible = false
			continue
		# Two quick return strokes, then a soft decay; never a full-screen white flash.
		var t: float = slot.age
		var pulse := maxf(exp(-t*18.0),exp(-absf(t-0.13)*48.0)*0.85)
		pulse = maxf(pulse,exp(-absf(t-0.29)*42.0)*0.45)
		slot.material.albedo_color = Color(1,1,1,pulse)
		slot.light.light_energy = pulse*9.0
		slot.light.visible = Settings.effects_quality > 0 and pulse > 0.025
		slot.mesh.visible = pulse > 0.015

func spawn_strike(interior: bool) -> bool:
	var slot: Dictionary = {}
	for candidate in slots:
		if candidate.age >= candidate.life and candidate.sound_at < 0 and not candidate.audio.playing:
			slot = candidate
			break
	if slot.is_empty(): return false
	var a: Vector3
	var b: Vector3
	if interior:
		# The open cylinder axis is Z. Arcs cross the surviving lower wall and ribs.
		var theta := rng.randf_range(PI*1.02,TAU*0.96)
		var theta_end := theta+rng.randf_range(0.24,0.65)
		var axial := rng.randf_range(-2400,2500)
		a = CENTER+Vector3(cos(theta)*rng.randf_range(600,940),sin(theta)*rng.randf_range(600,930),axial)
		b = CENTER+Vector3(cos(theta_end)*rng.randf_range(570,940),sin(theta_end)*rng.randf_range(570,930),axial+rng.randf_range(160,650))
		strikes_inside += 1
	else:
		var theta := rng.randf_range(0,TAU)
		var radius := rng.randf_range(1300,3400)
		a = CENTER+Vector3(cos(theta)*radius,sin(theta)*radius,rng.randf_range(-3800,3400))
		b = a+Vector3(rng.randf_range(-800,800),rng.randf_range(-600,600),rng.randf_range(450,1250))
		strikes_outside += 1
	a = CENTER+(a-CENTER)*spatial_scale
	b = CENTER+(b-CENTER)*spatial_scale
	if space_mode:
		var view := get_viewport().get_camera_3d()
		var center := view.global_position if view != null else CENTER
		var radial := Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
		a = center+radial*rng.randf_range(2000,7000)
		b = a+Vector3(rng.randf_range(-1800,1800),rng.randf_range(-1800,1800),rng.randf_range(-1800,1800))
	var paths: Array[PackedVector3Array] = []
	var trunk := _path(a,b,24)
	paths.append(trunk)
	for branch in 3:
		var start := trunk[rng.randi_range(5,17)]
		paths.append(_path(start,start+(b-a)*0.22+Vector3(rng.randf_range(-170,170),rng.randf_range(-150,150),rng.randf_range(-150,150)),9))
	slot.mesh.mesh = _arc_mesh(paths)
	slot.mesh.visible = true
	slot.light.global_position = (a+b)*0.5
	slot.audio.global_position = (a+b)*0.5
	slot.audio.stream = sounds[rng.randi_range(0,sounds.size()-1)]
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to((a+b)*0.5) if camera != null else 0.0
	slot.audio.volume_db = -6.0 if distance < 1800 else -10.0
	slot.audio.pitch_scale = rng.randf_range(0.88,1.12)
	slot.age = 0.0
	slot.life = 0.65
	slot.sound_at = clampf(distance/8500.0,0.025,1.5)
	strike_generated.emit(interior,a,b)
	return true

func _path(a: Vector3,b: Vector3,steps: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	for index in steps+1:
		var t := float(index)/steps
		var jitter := Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))*sin(t*PI)*a.distance_to(b)*0.065
		result.append(a.lerp(b,t)+jitter)
	return result

func _arc_mesh(paths: Array[PackedVector3Array]) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for path in paths:
		for index in path.size()-1:
			var a := path[index]
			var b := path[index+1]
			var direction := a.direction_to(b)
			var right := direction.cross(Vector3.UP).normalized()
			if right.length_squared() < 0.01: right = Vector3.RIGHT
			var up := direction.cross(right).normalized()
			for layer in 2:
				var width := 8.0 if layer == 0 else 1.8
				var color := Color(0.20,0.42,1.0,0.18) if layer == 0 else Color(0.82,0.94,1.0,1)
				tool.set_color(color)
				for side in 5:
					var angle0 := TAU*side/5.0
					var angle1 := TAU*(side+1)/5.0
					var p := (right*cos(angle0)+up*sin(angle0))*width
					var q := (right*cos(angle1)+up*sin(angle1))*width
					for point in [a+p,b+p,b+q,a+p,b+q,a+q]:tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()
