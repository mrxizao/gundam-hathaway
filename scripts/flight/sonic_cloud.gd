extends Node3D
## Visual condensation attached to the moving suit. Uses the exact HUD readout.
const CLOUD_SHADER := preload("res://shaders/sonic_cloud.gdshader")
const THRESHOLD_KMH := 2000
const PULSE_DURATION := 0.65
var body: Node3D
var intensity := 0.0
var burst_age := PULSE_DURATION
var bursts := 0
var was_fast := false
var clock := 0.0
var mesh: MeshInstance3D
static var _shell: ArrayMesh

static func displayed_kmh(airspeed_kmh: float) -> int:
	return int(airspeed_kmh * FlightHUD.SPEED_DISPLAY_SCALE)

static func speed_strength(readout: int) -> float:
	if readout <= THRESHOLD_KMH: return 0.0
	return 0.55 + 0.45 * smoothstep(float(THRESHOLD_KMH),3200.0,float(readout))

static func atmosphere(map: MapDef, altitude: float) -> float:
	if map != null and not map.has_ground: return 0.0
	return 1.0 - smoothstep(15000.0,45000.0,altitude)

func _ready() -> void:
	name = "SonicCloud"
	top_level = true

static func shell() -> ArrayMesh:
	if _shell != null: return _shell
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in 3:
		for a in 64:
			for z in 12:
				for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
					var u := float(z+corner.x)/12.0
					var v := float(a+corner.y)/64.0
					st.set_uv(Vector2(u,v))
					st.set_uv2(Vector2(float(layer)/2.0,0.0))
					st.set_normal(Vector3(cos(v*TAU),sin(v*TAU),-0.5).normalized())
					st.add_vertex(Vector3(cos(v*TAU)*(0.12+0.88*u),sin(v*TAU)*(0.12+0.88*u)*0.74,u-0.50))
	_shell = st.commit()
	return _shell

func _build() -> void:
	mesh = MeshInstance3D.new()
	mesh.name = "CondensationShell"
	mesh.mesh = shell()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	mesh.material_override = material
	add_child(mesh)

func _process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	if not is_instance_valid(body) or body.profile == null: return
	clock += delta
	burst_age = minf(burst_age+delta,PULSE_DURATION)
	var readout := displayed_kmh(body.airspeed_kmh())
	var air := atmosphere(Game.active_map,body.global_position.y)
	var fast: bool = readout>THRESHOLD_KMH and body.alive and not body.placeholder_only and air>0.0
	if fast and not was_fast and burst_age >= PULSE_DURATION:
		burst_age = 0.0
		bursts += 1
	was_fast = fast
	var turn: float = clampf(body.control_input.length(),0.0,1.0)
	var target: float = speed_strength(readout)*air*(1.0+turn*0.15) if fast else 0.0
	intensity = lerpf(intensity,minf(target,1.0),1.0-exp(-delta*(10.0 if fast else 14.0)))
	# Vacuum and death have no condensation; no frozen remnant on a wreck.
	if air<=0.0 or not body.alive or body.placeholder_only:
		intensity = 0.0
	var camera := get_viewport().get_camera_3d()
	var nearby: bool = camera == null or camera.global_position.distance_squared_to(body.global_position)<3600.0*3600.0
	if intensity<0.008 or not nearby:
		if mesh != null: mesh.visible = false
		return
	if mesh == null: _build()
	mesh.visible = true
	var velocity: Vector3 = body.fm.velocity
	var forward: Vector3 = velocity.normalized() if velocity.length_squared()>1.0 else -body.global_basis.z
	var up: Vector3 = body.global_basis.y
	if absf(forward.dot(up))>0.98: up = body.global_basis.x
	global_transform = Transform3D(Basis.looking_at(forward,up),body.global_position)
	var height: float = body.profile.target_height
	var span: float = maxf(height*0.48,minf(body.model_bounds.size.x*0.55,height*1.25))
	var length_scale := height*0.55
	mesh.custom_aabb = AABB(Vector3(-span*2,-span*2,-length_scale),Vector3(span*4,span*4,length_scale*3))
	var material := mesh.material_override as ShaderMaterial
	material.set_shader_parameter("clock",clock)
	material.set_shader_parameter("strength",intensity)
	material.set_shader_parameter("span",span)
	material.set_shader_parameter("length_scale",length_scale)
	material.set_shader_parameter("pulse",(1.0-burst_age/PULSE_DURATION)*intensity if fast else 0.0)
