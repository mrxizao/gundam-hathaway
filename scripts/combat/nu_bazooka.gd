extends RefCounted
## Shared guidance and Xi-style smoke for local and replicated Nu bazooka rounds.
const Spec := preload("res://scripts/data/nu_spec.gd")

static func valid_target(shooter: Node3D, candidate: Node3D) -> bool:
	return is_instance_valid(candidate) and candidate is FlightBody and candidate.alive and shooter.is_hostile_to(candidate)

static func acquire(shooter: Node3D, origin: Vector3, forward: Vector3, preferred: Node3D = null) -> Node3D:
	if valid_target(shooter, preferred):return preferred
	var best: Node3D
	var best_score := INF
	for candidate in Game.live_hostiles_of(shooter):
		if not valid_target(shooter, candidate):continue
		var offset: Vector3 = candidate.global_position-origin
		var distance := offset.length()
		if distance <= .01 or distance > Spec.BAZOOKA_SEEK_RANGE:continue
		var alignment := forward.dot(offset/distance)
		if alignment < Spec.BAZOOKA_SEEK_DOT:continue
		var score := distance/(.5+alignment)
		if score < best_score:
			best_score=score;best=candidate
	return best

static func spawn(container: Node, origin: Vector3, direction: Vector3, shooter: Node3D, damage: float, preferred: Node3D = null) -> Missile:
	var ray: Vector3 = direction.normalized() if direction.length_squared()>.001 else shooter.forward()
	var target := acquire(shooter, origin, ray, preferred)
	if target != null:
		var aim := Ballistics.intercept_point(origin,target.global_position,Missile.carrier_velocity(target),Spec.BAZOOKA_SPEED)
		ray=origin.direction_to(aim)
	var rocket := Missile._configure(origin,ray,target,shooter,damage)
	rocket.trail_level=Missile.Trail.HIGH
	rocket.speed=Spec.BAZOOKA_SPEED;rocket.max_speed=Spec.BAZOOKA_SPEED
	rocket.launch_vel=Vector3.ZERO
	rocket.turn_rate=Spec.BAZOOKA_TURN_RATE;rocket.turn_decay=Spec.BAZOOKA_TURN_DECAY
	rocket.lead_factor=1.0
	Missile._attach(container,rocket,origin)
	return rocket
