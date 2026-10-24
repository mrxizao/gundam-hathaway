extends Node3D
## One wave owns one physical pod and 108 independently simulated missiles.
## MultiMesh shares geometry and Xi-style trail history; no per-missile effect nodes.
const PODS := 1
const FACES := 3
const PER_FACE := 36
const TOTAL := PODS * FACES * PER_FACE
const STEP := 1.0 / 30.0
const TURN_RATE := 0.85
const LEAD := 0.30
const LIFE := 14.0
var shooter: Node3D
var targets: Array[Node3D] = []
var origin := Transform3D.IDENTITY
var inherited := Vector3.ZERO
var damage := 1.0
var max_speed := 0.0
var ray_query: PhysicsRayQueryParameters3D
var clock := 0.0
var accumulated := 0.0
var emitted := 0
var launch_slot := 0
var pods: Array[Node3D] = []
var positions := PackedVector3Array()
var directions := PackedVector3Array()
var ages := PackedFloat32Array()
var bodies: MultiMesh
var ribbons: MultiMeshInstance3D
var trails: MultiMesh
var smoke: MultiMesh
var smoke_image: Image
var smoke_texture: ImageTexture
var smoke_material: ShaderMaterial

static func smoke_amount() -> int:
	return 12 if Settings.effects_quality==0 else FX.TRAIL_HIGH_AMOUNT

var exclusions: Array[RID] = []
var _fx_budget := 0

func configure(source: Node3D, target: Node3D, plan: Array) -> void:
	shooter = source
	max_speed = SuitProfile.missile_speed()
	launch_slot = source._funnel_slot
	origin = source.global_transform
	inherited = Missile.carrier_velocity(source)
	damage = source.profile.funnel_damage * source.damage_mult
	if source is CollisionObject3D:
		exclusions.append(source.get_rid())
	# Each trigger assigns a whole pod; successive launches rotate stable locks.
	var assigned := target
	if not plan.is_empty():
		assigned = plan[launch_slot % plan.size()].unit
	for i in PODS:
		targets.append(assigned)

func _material(color: Color, glow := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.emission_enabled = glow
	mat.emission = color
	mat.roughness = 0.65
	return mat

func _instances(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return mm

func _ready() -> void:
	ray_query = PhysicsRayQueryParameters3D.new()
	ray_query.collision_mask = 3
	ray_query.exclude = exclusions
	# All state coordinates are world coordinates, independent of container transform.
	top_level = true
	global_transform = Transform3D.IDENTITY
	positions.resize(TOTAL)
	directions.resize(TOTAL)
	ages.resize(TOTAL)
	ages.fill(-1.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.45, 0.45, 3.0)
	mesh.material = _material(Color(0.82, 0.85, 0.91))
	bodies = _instances(mesh, TOTAL)
	var plume := BoxMesh.new()
	plume.size = Vector3(0.3, 0.3, 1.2)
	plume.material = _material(Color(.80,.80,.84))
	trails = _instances(plume, TOTAL)
	_build_smoke()
	ribbons=preload("res://scripts/world/gp03d_xi_ribbon.gd").new()
	ribbons.configure(TOTAL,max_speed*(LIFE+3.0)+inherited.length()*2.0,origin.origin)
	add_child(ribbons)
	# Closed three-sided prism, long axis Z. Each side has its own 6x6 ports.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in FACES:
		var a := Vector2.from_angle(TAU * face / 3.0) * 3.0
		var b := Vector2.from_angle(TAU * (face + 1) / 3.0) * 3.0
		for v: Vector3 in [Vector3(b.x,b.y,7),Vector3(b.x,b.y,-7),Vector3(a.x,a.y,-7),Vector3(a.x,a.y,7),Vector3(b.x,b.y,7),Vector3(a.x,a.y,-7)]:
			surface.add_vertex(v)
	for end in [-1.0,1.0]:
		for j in [2,1,0] if end>0 else [0,1,2]:
			var v := Vector2.from_angle(TAU*j/3.0)*3.0
			surface.add_vertex(Vector3(v.x,v.y,end*7))
	surface.generate_normals()
	var pod_mesh := surface.commit()
	pod_mesh.surface_set_material(0,_material(Color(0.19,0.21,0.29)))
	var port_mesh := SphereMesh.new()
	port_mesh.radius = 0.23
	port_mesh.height = 0.46
	port_mesh.radial_segments = 6
	port_mesh.rings = 3
	port_mesh.material = _material(Color(0.82,0.69,0.23))
	for i in PODS:
		var pod := MeshInstance3D.new()
		pod.mesh = pod_mesh
		pod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pod)
		pod.visible = false
		pods.append(pod)
		var ports := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = port_mesh
		mm.instance_count = FACES*PER_FACE
		for j in FACES*PER_FACE:
			mm.set_instance_transform(j,Transform3D(Basis.IDENTITY,_port(j/36,j%36)))
		ports.multimesh = mm
		ports.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pod.add_child(ports)

func _build_smoke() -> void:
	smoke_image = Image.create(TOTAL,2,false,Image.FORMAT_RGBAF)
	for i in TOTAL:
		smoke_image.set_pixel(i,0,Color(0,0,0,-100))
	smoke_texture = ImageTexture.create_from_image(smoke_image)
	smoke_material = ShaderMaterial.new()
	smoke_material.shader = preload("res://shaders/gp03d_missile_smoke.gdshader")
	smoke_material.set_shader_parameter("missile_state",smoke_texture)
	smoke_material.set_shader_parameter("smoke_grain",FX._smoke_grain_tex())
	smoke_material.set_shader_parameter("particles_per_missile",smoke_amount())
	var quad := QuadMesh.new()
	quad.material = smoke_material
	smoke = _instances(quad,TOTAL*smoke_amount())
	for i in smoke.instance_count:
		smoke.set_instance_transform(i,Transform3D.IDENTITY)
	var reach := max_speed*(LIFE+3.0)+inherited.length()*2.0
	smoke.custom_aabb = AABB(origin.origin-Vector3.ONE*reach,Vector3.ONE*reach*2.0)


func _port(face: int, index: int) -> Vector3:
	var a := Vector2.from_angle(TAU*face/3.0)*3.0
	var b := Vector2.from_angle(TAU*(face+1)/3.0)*3.0
	var xy := a.lerp(b,(float(index%6)+0.5)/6.0)
	return Vector3(xy.x,xy.y,(float(index/6)-2.5)*2.0)

func _physics_process(delta: float) -> void:
	accumulated += delta
	while accumulated >= STEP:
		accumulated -= STEP
		_step(STEP)

func _step(dt: float) -> void:
	clock += dt
	_fx_budget = 3
	ribbons.clock=clock
	# Keep only the visual container alive until the last 1.5s hold + fade finishes.
	if clock > LIFE + 5.0:
		queue_free()
		return
	for pod_index in PODS:
		var elapsed := clock - pod_index*0.045
		if elapsed >= 2.0:
			pods[pod_index].visible = false
			continue
		if elapsed < 0.0:
			continue
		var side := 1.0 if launch_slot%2==0 else -1.0
		var row := (launch_slot%16)/2
		var local := Vector3(side*(24.0+elapsed*70.0),17.0+row*1.1+elapsed*28.0,-12.0-elapsed*85.0)
		var pod := pods[pod_index]
		pod.global_transform = Transform3D(origin.basis,origin*local+inherited*minf(elapsed,1.4))
		pod.visible = elapsed < 2.0
		for face in FACES:
			for j in PER_FACE:
				var index := pod_index*108+face*36+j
				# Visible delay before deployment, then rows launch from each face.
				if ages[index] != -1.0 or elapsed < 0.65+face*0.18+(j/6)*0.025:
					continue
				positions[index] = pod.global_transform*_port(face,j)
				var angle := TAU*(face+0.5)/3.0
				directions[index] = origin.basis*Vector3(cos(angle),sin(angle),-0.35).normalized()
				ages[index] = 0.0
				ribbons.push_point(index,positions[index],clock)
				emitted += 1
				if is_instance_valid(shooter) and shooter.is_player:
					Game.missiles_fired += 1
	var space := get_world_3d().direct_space_state
	for i in TOTAL:
		if ages[i] < 0.0:
			continue
		ages[i] += dt
		if ages[i] > LIFE:
			_retire(i)
			continue
		var target := targets[i/108]
		var tracking: bool = is_instance_valid(target) and target.has_method("is_alive") and target.is_alive()
		var old := positions[i]
		var dir := directions[i]
		# Heat decoys reliably break these ordinary missiles' lock.
		if tracking and target.has_method("flares_active") and target.flares_active():
			targets[i/108] = null
			tracking = false
		var speed := minf(130.0+maxf(ages[i]-0.15,0.0)*(max_speed-130.0)/2.4,max_speed)
		if tracking and ages[i]>0.15:
			var aim := target.global_position + Missile.carrier_velocity(target)*minf(old.distance_to(target.global_position)/maxf(speed,1.0),2.0)*LEAD
			var desired := old.direction_to(aim)
			var axis := dir.cross(desired)
			if axis.length_squared()>0.000001:
				dir = dir.rotated(axis.normalized(),minf(dir.angle_to(desired),TURN_RATE*dt)).normalized()
		var next := old + (dir*speed+inherited*Missile.inherit_factor(ages[i]+0.65))*dt
		ray_query.from = old
		ray_query.to = next
		var hit := space.intersect_ray(ray_query)
		var victim: Node3D = null
		if not hit.is_empty():
			next = hit.position
			var collider = hit.collider
			if collider is Node3D and collider.has_method("take_damage"):
				victim = collider
		elif tracking and Geometry3D.get_closest_point_to_segment(target.global_position,old,next).distance_to(target.global_position)<12.0:
			victim = target
		if victim != null or not hit.is_empty():
			ribbons.push_point(i,next,clock)
			if is_instance_valid(victim) and (not is_instance_valid(shooter) or victim.get("team") != shooter.get("team")):
				var src: Node3D = shooter if is_instance_valid(shooter) else null
				victim.take_damage(damage,src,Damage.Type.FUNNEL)
				if src != null and src == Game.player:
					Game.missiles_hit += 1
			if _fx_budget>0:
				_fx_budget -= 1
				FX.explosion(get_parent(),next,0.18)
				Audio.play_explosion(next)
			_retire(i)
			continue
		ribbons.push_point(i,next,clock)
		positions[i] = next
		directions[i] = dir
		var orient := Basis.looking_at(dir,Vector3.RIGHT if absf(dir.y)>0.98 else Vector3.UP)
		bodies.set_instance_transform(i,Transform3D(orient,next))
		trails.set_instance_transform(i,Transform3D(orient,next-dir*7.5))
		smoke_image.set_pixel(i,0,Color(next.x,next.y,next.z,clock))
		var velocity := (next-old)/dt
		smoke_image.set_pixel(i,1,Color(velocity.x,velocity.y,velocity.z,1.0))
	smoke_texture.update(smoke_image)
	smoke_material.set_shader_parameter("simulation_time",clock)

func _retire(i: int) -> void:
	ages[i] = -2.0
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO)
	bodies.set_instance_transform(i,hidden)
	trails.set_instance_transform(i,hidden)
