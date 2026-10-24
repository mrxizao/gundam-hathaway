extends BeamCannon
## Short sustained funnel beam: instantaneous column, integrated damage over 0.3 s.
const PULSE_DURATION := 0.3
const PULSE_RANGE := 1500.0
const WIDTH_FACTOR := 0.30
var direction := Vector3.FORWARD
var origin := Vector3.ZERO
var anchor: WeakRef
var anchor_offset := Vector3.ZERO
var visual_only := false
var core_radius := 3.68

static func pulse(container: Node, owner_body: FlightBody, from: Vector3, aim: Vector3,
		shot_damage: float, tint: Color, size_factor: float, emitter: Node3D = null, remote := false) -> BeamCannon:
	var beam = load("res://scripts/combat/funnel_beam.gd").new()
	beam.shooter=owner_body;beam.origin=from;beam.direction=aim.normalized()
	beam.duration=PULSE_DURATION;beam.dps=shot_damage/PULSE_DURATION;beam.color=tint
	beam.radius=Projectile.BEAM_HIT_RADIUS*size_factor
	beam.core_radius=Projectile.BEAM_VIS_RADIUS*size_factor*Projectile.FIN_VISUAL_WIDTH*WIDTH_FACTOR
	beam.visual_only=remote
	if is_instance_valid(emitter):
		beam.anchor=weakref(emitter);beam.anchor_offset=emitter.to_local(from)
	container.add_child(beam)
	beam.global_position=from
	return beam

static func remote_emitter(body: FlightBody, from: Vector3) -> Node3D:
	var candidates: Array = []
	if body.sazabi_systems != null: candidates=body.sazabi_systems.drones
	elif is_instance_valid(body.nu_systems): candidates.assign(body.nu_systems.fins)
	var nearest: Node3D
	var distance := 400.0
	for fin in candidates:
		if not is_instance_valid(fin) or fin.is_queued_for_deletion():continue
		var d:float=fin.global_position.distance_squared_to(from)
		if d<distance:distance=d;nearest=fin
	return nearest

func _ready() -> void:
	_core=_make_cylinder(core_radius,1.0,color,1.0)
	_glow=_make_cylinder(core_radius*1.6,1.0,Color(color,.12),.4)
	# A compact glow keeps six simultaneous shots inexpensive.
	_flare=FX.nozzle_glow(self,Vector3.ZERO,_additive_mat(color,1.2),core_radius*2.0)
	_core.visible=false;_glow.visible=false

func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter) or not shooter.alive:
		queue_free();return
	if anchor != null:
		var fin=anchor.get_ref()
		if not is_instance_valid(fin) or fin.is_queued_for_deletion():queue_free();return
		if (fin.get("alive") != null and not fin.alive) or (fin.get("destroyed") != null and fin.destroyed):queue_free();return
		origin=fin.to_global(anchor_offset)
	var dt:=minf(maxf(delta,0.0),maxf(duration-_life,0.0))
	var length:=PULSE_RANGE
	if _pq==null:_pq=PhysicsRayQueryParameters3D.new()
	_pq.from=origin;_pq.to=origin+direction*PULSE_RANGE;_pq.collision_mask=WORLD_LAYER
	_pq.exclude=[shooter.get_rid()]
	var hit:=get_world_3d().direct_space_state.intersect_ray(_pq)
	if hit.has("position"):length=origin.distance_to(hit.position)
	global_position=origin
	var glow:=.85+.15*sin(_life*40.0)
	_place(_core,origin,direction,length,glow);_place(_glow,origin,direction,length,glow*.6)
	_core.visible=length>.001;_glow.visible=length>.001
	if not visual_only:_apply_damage(origin,origin+direction*length,dt)
	_life+=dt
	if _life>=duration-.000001:queue_free()

func _apply_damage(from: Vector3, to: Vector3, delta: float) -> void:
	var amount:=dps*delta
	if amount<=0:return
	for unit in Game.live_hostiles_of(shooter):
		if is_instance_valid(unit) and Ballistics.segment_distance(from,to,unit.global_position,unit.global_position)<=radius+UNIT_RADIUS:
			unit.take_damage(amount,shooter,Damage.Type.BEAM)
	var fins:Array=Game.group_snapshot(get_tree(),"sazabi_funnels").duplicate()
	for unit in Game.live_hostiles_of(shooter):
		if is_instance_valid(unit.nu_systems):
			for fin in unit.nu_systems.fins:
				if is_instance_valid(fin) and fin.alive and fin.deployed:fins.append(fin)
	for fin in fins:
		if is_instance_valid(fin) and not fin.is_queued_for_deletion() and Ballistics.segment_distance(from,to,fin.global_position,fin.global_position)<=radius+3:
			fin.take_damage(amount,shooter,Damage.Type.BEAM)
