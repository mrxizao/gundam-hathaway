extends Node3D
## Visual-only sea interaction. Stamps stay in world space after a suit leaves.
const WAVE_SHADER := preload("res://shaders/sea_flight_wake.gdshader")
const TRAIL_SHADER := preload("res://shaders/sea_flight_trail.gdshader")
const TRAIL_LIFETIME := 3.6
const SAMPLE_STEP := 1.0 / 60.0
const TRIGGER_HEIGHT := 150.0
const LIFETIME := 2.8
const CAMERA_RANGE := 3600.0
var world: Node3D
var packets: Array[Dictionary] = []
var emitters: Dictionary = {}
var accumulator := 0.0
var emitted_packets := 0
var surface_id := 0
var _ring: ArrayMesh
var _spray_mesh: QuadMesh
var _cursor := 0
var _clock := 0.0

func _new_trail() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "SeaFoamTrail"
	node.top_level = true
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = TRAIL_SHADER
	material.set_shader_parameter("lifetime",TRAIL_LIFETIME)
	node.material_override = material
	add_child(node)
	node.global_transform = Transform3D.IDENTITY
	return node

func _trail_point(entry: Dictionary, point: Vector3, flow: Vector3, power: float, continuous: bool) -> void:
	var points: Array = entry["points"]
	if points.size() > 0 and point.distance_to(points[-1]["point"]) < 4.0: return
	var side := Vector3(flow.z,0,-flow.x).normalized()
	var broken: bool = not continuous or bool(entry.get("trail_broken",false)) or (points.size() > 0 and _clock - float(points[-1]["time"]) > 0.3)
	points.append({"point":point,"time":_clock,"angle":atan2(side.z,side.x),"power":power,"broken":broken})
	entry["trail_broken"] = false
	while points.size() > 40 or (points.size() > 0 and _clock - float(points[0]["time"]) > TRAIL_LIFETIME): points.pop_front()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertex_count := 0
	for i in range(1,points.size()):
		if points[i]["broken"]: continue
		for flank in [0.0,1.0]:
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var p: Dictionary = points[i-1+corner.y]
				st.set_uv(Vector2(corner.x,corner.y))
				st.set_uv2(Vector2(p["time"],p["angle"]))
				st.set_color(Color(flank,p["power"],1,1))
				st.set_normal(Vector3.UP)
				st.add_vertex(p["point"])
				vertex_count += 1
	var trail: MeshInstance3D = entry["trail"]
	trail.mesh = st.commit() if vertex_count > 0 else null
	if points.size() > 0:
		var bounds := AABB(points[0]["point"],Vector3.ONE)
		for p in points: bounds = bounds.expand(p["point"])
		trail.custom_aabb = bounds.grow(240.0)

func _trail_head(entry: Dictionary, point: Vector3, flow: Vector3, power: float, continuous: bool) -> void:
	var head: MeshInstance3D = entry["head"]
	var points: Array = entry["points"]
	head.visible = continuous and not bool(entry.get("trail_broken",false)) and flow.length()>80.0 and points.size()>0
	if not head.visible: return
	var old: Dictionary = points[-1]
	if point.distance_to(old["point"]) < 1.0:
		head.mesh = null
		return
	var side := Vector3(flow.z,0,-flow.x).normalized()
	var ends := [old,{"point":point,"time":_clock,"angle":atan2(side.z,side.x),"power":power}]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for flank in [0.0,1.0]:
		for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
			var p: Dictionary = ends[corner.y]
			st.set_uv(Vector2(corner.x,corner.y))
			st.set_uv2(Vector2(p["time"],p["angle"]))
			st.set_color(Color(flank,p["power"],1,1))
			st.set_normal(Vector3.UP)
			st.add_vertex(p["point"])
	head.mesh = st.commit()
	head.custom_aabb = AABB(old["point"],Vector3.ONE).expand(point).grow(240.0)

static func influence(height: float, size: float, speed: float, powered: bool, boost: bool) -> float:
	if height < -5.0 or height > TRIGGER_HEIGHT: return 0.0
	# At 150 m the effect is already visible, rather than fading to zero there.
	var proximity := 0.25 + 0.75 * (1.0 - smoothstep(minf(size * 0.45,60.0),TRIGGER_HEIGHT,maxf(height,0.0)))
	var drive := maxf(clampf(speed / 700.0,0.0,1.0),0.45 if powered else 0.0)
	return clampf(proximity * drive * (1.25 if boost else 1.0),0.0,1.0)

func _ready() -> void:
	name = "SeaFlightWake"
	_ring = _build_ring()
	_spray_mesh = QuadMesh.new()
	_spray_mesh.size = Vector2(1.2,2.2)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.68,0.84,0.90,0.70)
	material.emission_enabled = true
	material.emission = Color(0.025,0.045,0.055)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.9
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE,Color(1,1,1,0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5,0.5)
	texture.fill_to = Vector2(0.5,1.0)
	material.albedo_texture = texture
	_spray_mesh.material = material

func _build_ring() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in 96:
		for band in 8:
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var u := float(band + corner.x) / 8.0
				var v := float(segment + corner.y) / 96.0
				st.set_uv(Vector2(u,v))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(cos(v * TAU),0,sin(v * TAU)) * lerpf(0.72,1.16,u))
	return st.commit()

func _new_emitter() -> GPUParticles3D:
	var spray := GPUParticles3D.new()
	spray.name = "SeaSpray"
	spray.amount = [128,256,512][clampi(Settings.effects_quality,0,2)]
	spray.lifetime = 1.5
	spray.preprocess = 0.0
	spray.fixed_fps = 30
	spray.local_coords = false
	spray.emitting = false
	spray.draw_pass_1 = _spray_mesh
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spray.visibility_aabb = AABB(Vector3(-220,-30,-220),Vector3(440,180,440))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 12.0
	process.emission_ring_inner_radius = 4.0
	process.emission_ring_height = 1.0
	process.direction = Vector3.UP
	process.spread = 65.0
	process.gravity = Vector3(0,-35,0)
	process.initial_velocity_min = 18.0
	process.initial_velocity_max = 42.0
	process.scale_min = 0.45
	process.scale_max = 1.6
	process.angle_min = -25.0
	process.angle_max = 25.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0,0.12,0.65,1.0])
	ramp.colors = PackedColorArray([Color(1,1,1,0),Color.WHITE,Color(0.8,0.9,1,0.5),Color(0.8,0.9,1,0)])
	var colors := GradientTexture1D.new()
	colors.gradient = ramp
	process.color_ramp = colors
	spray.process_material = process
	add_child(spray)
	return spray

func _wave_packet() -> Dictionary:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _ring
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.custom_aabb = AABB(Vector3(-1000,-12,-1000),Vector3(2000,120,2000))
	var material := ShaderMaterial.new()
	material.shader = WAVE_SHADER
	mesh.material_override = material
	add_child(mesh)
	return {"mesh":mesh,"material":material,"age":0.0}

func stamp(point: Vector3, flow: Vector3, size: float, power: float, spacing := 0.0) -> void:
	var limit: int = [24,36,48][clampi(Settings.effects_quality,0,2)]
	var entry: Dictionary
	if packets.size() < limit:
		entry = _wave_packet()
		packets.append(entry)
	else:
		entry = packets[_cursor % limit]
		_cursor += 1
	var node: MeshInstance3D = entry["mesh"]
	node.global_position = point
	node.rotation.y = atan2(flow.x,flow.z)
	node.visible = true
	entry["age"] = 0.0
	var material: ShaderMaterial = entry["material"]
	material.set_shader_parameter("age",0.0)
	material.set_shader_parameter("lifetime",LIFETIME)
	material.set_shader_parameter("strength",power)
	material.set_shader_parameter("initial_radius",maxf(maxf(size * 0.45,12.0),spacing * 0.55))
	material.set_shader_parameter("expansion",45.0 + power * 45.0 + clampf(flow.length() * 0.01,0.0,45.0))
	material.set_shader_parameter("stretch",1.0 + clampf(flow.length() / 1600.0,0.0,0.5))
	material.set_shader_parameter("phase",float(emitted_packets) * 2.39996)
	material.set_shader_parameter("directional",clampf(flow.length() / 350.0,0.0,1.0))
	emitted_packets += 1

func clear_effects() -> void:
	for entry in packets: (entry["mesh"] as Node).queue_free()
	packets.clear()
	for entry in emitters.values():
		(entry["spray"] as Node).queue_free()
		(entry["wash"]["mesh"] as Node).queue_free()
		(entry["trail"] as Node).queue_free()
		(entry["head"] as Node).queue_free()
	emitters.clear()
	accumulator = 0.0
	_clock = 0.0

func water_at(point: Vector3) -> bool:
	if world == null or not is_instance_valid(world.get("ocean")): return false
	var map: MapDef = world.get("map")
	if map == null: return false
	if map.terrain == MapDef.Terrain.CITY:
		if not WorldBuilder.is_water_at(point.x,point.z,map.city_layout) or WorldBuilder.city_is_dry(point.x,point.z,map.city_layout): return false
	elif map.terrain != MapDef.Terrain.ISLANDS: return false
	# Islands, buildings and bridges block the downwash before it reaches water.
	var sea: MeshInstance3D = world.get("ocean")
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x,maxf(point.y,sea.global_position.y + 2.0),point.z),Vector3(point.x,sea.global_position.y + 0.5,point.z),1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _water_height(point: Vector3) -> float:
	var sea: MeshInstance3D = world.get("ocean")
	var material: ShaderMaterial = world.get("_ocean_mat")
	if material == null: return sea.global_position.y + 0.8
	var amp: float = material.get_shader_parameter("wave_amp")
	var clock: float = world.get("_anim_time")
	var a := sin(Vector2(point.x,point.z).dot(Vector2(0.82,0.57)) * TAU / 3600.0 + clock * 0.42)
	var b := sin(Vector2(point.x,point.z).dot(Vector2(-0.35,0.94)) * TAU / 1900.0 - clock * 0.63)
	return sea.global_position.y + (a * 0.68 + b * 0.32) * amp * 0.7 + 0.8

func _physics_process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	var sea = world.get("ocean") if is_instance_valid(world) else null
	var id: int = sea.get_instance_id() if is_instance_valid(sea) else 0
	if id != surface_id:
		clear_effects()
		surface_id = id
	if id == 0: return
	_clock += delta
	for entry in emitters.values():
		var trail: MeshInstance3D = entry["trail"]
		(trail.material_override as ShaderMaterial).set_shader_parameter("clock",_clock)
	for entry in packets:
		entry["age"] += delta
		(entry["mesh"] as MeshInstance3D).visible = entry["age"] < LIFETIME
		(entry["material"] as ShaderMaterial).set_shader_parameter("age",entry["age"])
	accumulator += delta
	if accumulator < SAMPLE_STEP: return
	var sample_delta := accumulator
	accumulator = 0.0
	var camera := get_viewport().get_camera_3d()
	var candidates: Array[FlightBody] = []
	for node in get_tree().get_nodes_in_group("units"):
		if not node is FlightBody or not node.alive or node.placeholder_only: continue
		if camera != null and camera.global_position.distance_squared_to(node.global_position) > CAMERA_RANGE * CAMERA_RANGE: continue
		var height: float = node.global_position.y - sea.global_position.y
		if influence(height,node.profile.target_height,node.fm.velocity.length(),node.own_propulsion_enabled(),node.fm.boosting) > 0.025:
			candidates.append(node)
	candidates.sort_custom(func(a: FlightBody,b: FlightBody) -> bool:
		if a.is_player != b.is_player: return a.is_player
		return a.global_position.distance_squared_to(camera.global_position if camera != null else Vector3.ZERO) < b.global_position.distance_squared_to(camera.global_position if camera != null else Vector3.ZERO))
	var active := {}
	var limit: int = [2,3,4][clampi(Settings.effects_quality,0,2)]
	for unit in candidates:
		if active.size() >= limit: break
		var point := unit.global_position
		if not water_at(point): continue
		var uid := unit.get_instance_id()
		if not emitters.has(uid):
			var trail := _new_trail()
			var head := _new_trail()
			head.material_override = trail.material_override
			emitters[uid] = {"spray":_new_emitter(),"wash":_wave_packet(),"trail":trail,"head":head,"points":[],"last":point}
		var entry: Dictionary = emitters[uid]
		active[uid] = true
		point.y = _water_height(point)
		var size := unit.profile.target_height
		var flow := unit.fm.velocity
		var power := influence(unit.global_position.y - sea.global_position.y,size,flow.length(),unit.own_propulsion_enabled(),unit.fm.boosting)
		var last: Vector3 = entry["last"]
		# A persistent footprint follows the suit every physics sample. Only the
		# detached history is throttled, so high-speed suits cannot outrun onset.
		var wash: Dictionary = entry["wash"]
		var wash_node: MeshInstance3D = wash["mesh"]
		wash_node.global_position = point
		wash_node.rotation.y = atan2(flow.x,flow.z)
		wash_node.visible = true
		var wash_material: ShaderMaterial = wash["material"]
		wash_material.set_shader_parameter("age",0.045)
		wash_material.set_shader_parameter("strength",power)
		wash_material.set_shader_parameter("initial_radius",maxf(size * 0.55,14.0))
		wash_material.set_shader_parameter("expansion",80.0)
		wash_material.set_shader_parameter("stretch",1.0 + clampf(flow.length() / 5000.0,0.0,0.6))
		wash_material.set_shader_parameter("directional",clampf(flow.length()/350.0,0.0,1.0))
		var distance := Vector2(point.x-last.x,point.z-last.z).length()
		var count := mini(8,maxi(1,ceili(distance / 45.0)))
		var continuous := true
		if distance > maxf(1200.0,flow.length() * 0.5):
			continuous = false
			count = 1
			last = point
			distance = 0.0
		entry["wave_elapsed"] = float(entry.get("wave_elapsed",0.35)) + sample_delta
		if entry["wave_elapsed"] >= (0.10 if flow.length() > 80.0 else 0.35):
			for i in count:
				var origin := last.lerp(point,float(i+1)/count) if count > 1 else point
				if water_at(Vector3(origin.x,unit.global_position.y,origin.z)):
					origin.y = _water_height(origin)
					stamp(origin,flow,size,power,distance / count)
				else: continuous = false
			if flow.length() > 80.0: _trail_point(entry,point,flow,power,continuous)
			entry["wave_elapsed"] = 0.0
			entry["last"] = point
		_trail_head(entry,point,flow,power,continuous)
		var spray: GPUParticles3D = entry["spray"]
		spray.global_position = point
		spray.amount_ratio = clampf(power,0.05,1.0)
		var process := spray.process_material as ParticleProcessMaterial
		process.initial_velocity_min = 22.0 + power * 26.0
		process.initial_velocity_max = 40.0 + power * 48.0
		process.emission_ring_radius = maxf(8.0,size * 0.45)
		spray.emitting = true
	for uid in emitters.keys():
		if not active.has(uid):
			emitters[uid]["trail_broken"] = true
			var spray: GPUParticles3D = emitters[uid]["spray"]
			spray.emitting = false
			(emitters[uid]["wash"]["mesh"] as MeshInstance3D).visible = false
			(emitters[uid]["head"] as MeshInstance3D).visible = false
			emitters[uid]["idle"] = float(emitters[uid].get("idle",0.0)) + sample_delta
			if emitters[uid]["idle"] > TRAIL_LIFETIME:
				spray.queue_free()
				(emitters[uid]["wash"]["mesh"] as Node).queue_free()
				(emitters[uid]["trail"] as Node).queue_free()
				(emitters[uid]["head"] as Node).queue_free()
				emitters.erase(uid)
		else: emitters[uid]["idle"] = 0.0
