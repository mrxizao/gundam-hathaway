extends RefCounted
## Shared third-person rifle geometry. No camera, flight, or lock writes.
const VERSION := "rifle-aim-v2-65-target"
## A firing solution, not a random hit chance: retain intent and world occlusion.
const HIT_RATE_TARGET := 0.65
const SNAP_DEG := 2.4
const CONE_DEG := 4.0
static func intent_weight(angle_deg: float) -> float:
	return clampf((CONE_DEG-angle_deg)/(CONE_DEG-SNAP_DEG),0.0,1.0)


static func solve(origin: Vector3, ray_origin: Vector3, ray_direction: Vector3,
		target, steady_speed: float, assistance: bool) -> Dictionary:
	var direction := ray_direction.normalized()
	var valid: bool = is_instance_valid(target) and target is FlightBody and target.alive
	var prediction := Vector3.ZERO
	var depth := 4000.0
	if valid:
		prediction = Ballistics.beam_lead_point(origin, target.global_position,
			target.fm.velocity, steady_speed)
		depth = maxf((prediction - ray_origin).dot(direction), 1.0)
	var raw := ray_origin + direction * depth
	var aim := raw
	var weight := 0.0
	var error := 0.0
	if valid and (prediction - origin).length_squared() > 1.0:
		error = Ballistics.angle_off_boresight(raw - origin, prediction - origin)
		if assistance:
			weight = intent_weight(Ballistics.angle_off_boresight(direction,target.global_position-ray_origin))
		if weight > 0.0:
			aim = origin + (raw - origin).slerp(prediction - origin, weight)
	var span := origin.distance_to(aim)
	return {"valid": valid, "prediction": prediction, "raw_point": raw, "aim_point": aim,
		"origin": origin, "ray_origin": ray_origin, "ray_direction": direction,
		"target_id": target.get_instance_id() if valid else 0,
		"weight": weight, "error_deg": error,
		"correction_deg": Ballistics.angle_off_boresight(raw - origin, aim - origin),
		"flight_time": SuitProfile.rifle_flight_time(span, steady_speed),
		"steady_speed": steady_speed, "blocked": false,
		"physics_frame": Engine.get_physics_frames(), "version": VERSION}

static func clear_path(unit: FlightBody, origin: Vector3, destination: Vector3, target) -> bool:
	if not unit.is_inside_tree() or origin.distance_squared_to(destination) < 1.0:
		return true
	var query := PhysicsRayQueryParameters3D.create(origin, destination,
		FlightBody.WORLD_LAYER | FlightBody.UNIT_LAYER, [unit.get_rid()])
	var hit := unit.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target
