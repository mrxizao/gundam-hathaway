extends RefCounted
## Predictive WORLD obstacle avoidance; ground uses the separate last-frame rescue.
## Called immediately before movement,
## so reverse cruise, lateral quick boosts and target-facing flight use one guard.
const GroundPolicy = preload("res://scripts/flight/ground_avoidance.gd")
const LOOKAHEAD := 2.6
const RESPONSE := 6.0
const PLAN_INTERVAL := 0.12
const CLEAR_HOLD := 0.65
var active := false
var kind := ""
var time_to_impact := INF
var escape := Vector3.ZERO
var radius := 24.0
var _sphere := SphereShape3D.new()
var _space: PhysicsDirectSpaceState3D
var _exclude: Array[RID] = []
var _ground := false
var _floor := 0.0
var _clear_for := 0.0
var _plan_in := 0.0
var _entry_speed := 0.0
var _path_room := 1.0

func reset() -> void:
	active = false
	kind = ""
	time_to_impact = INF
	escape = Vector3.ZERO
	_clear_for = 0.0
	_plan_in = 0.0
	_entry_speed = 0.0

func solve(player: CharacterBody3D, proposed: Vector3, delta: float, _has_ground: bool, crash_altitude: float) -> Vector3:
	if delta <= 0.0:
		return proposed
	_space = player.get_world_3d().direct_space_state
	_exclude = [player.get_rid()]
	_ground = false # Ground is rescued at the movement/death boundary, never by long-range planning.
	if not _ground:
		_exclude.append_array(GroundPolicy.excluded_ground(player))
		if kind == "ground":
			reset()
	var hull := player.get_node_or_null("Hull") as CollisionShape3D
	if hull != null and hull.shape is CapsuleShape3D:
		var capsule := hull.shape as CapsuleShape3D
		radius = maxf(24.0, capsule.height * 0.5 + 10.0)
	_sphere.radius = radius
	_floor = crash_altitude + radius + 8.0
	var origin := player.global_position
	var risk := _sweep(origin, proposed * LOOKAHEAD)
	time_to_impact = float(risk["fraction"]) * LOOKAHEAD if risk["hit"] else INF
	_plan_in = maxf(0.0, _plan_in - delta)
	if risk["hit"]:
		if not active:
			_entry_speed = maxf(proposed.length(), 1.0)
			_plan_in = 0.0
		active = true
		_clear_for = 0.0
		kind = risk.get("kind", "building")
	elif active:
		_clear_for += delta
		if _clear_for >= CLEAR_HOLD:
			reset()
	if not active:
		return proposed
	var safe_speed := minf(maxf(proposed.length(), _entry_speed * 0.35), _entry_speed * 0.82)
	if _plan_in <= 0.0 or escape == Vector3.ZERO:
		_plan(origin, proposed, safe_speed, risk)
		_plan_in = PLAN_INTERVAL
	var target := escape * safe_speed
	if _path_room < 0.18:
		# Boxed in: brake instead of forcing an ascent into a roof or overhang.
		target = Vector3.ZERO
	var next := proposed.lerp(target, 1.0 - exp(-RESPONSE * delta))
	# Last-moment distance limit keeps the integrated step inside available space.
	# This changes velocity only; collision damage and the death plane stay intact.
	var step := _sweep(origin, next * delta)
	if step["hit"]:
		next *= maxf(0.0, float(step["fraction"]) - 0.02)
	return next

func _query(origin: Vector3, motion: Vector3) -> PhysicsShapeQueryParameters3D:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis(), origin)
	q.motion = motion
	q.collision_mask = 1 # FlightBody.WORLD_LAYER; units and projectiles are ignored.
	q.exclude = _exclude
	q.margin = 0.02
	return q

func _sweep(origin: Vector3, motion: Vector3) -> Dictionary:
	var fraction := 1.0
	var normal := Vector3.ZERO
	var hit_kind := "building"
	var q := _query(origin, motion)
	# cast_motion ignores initial overlaps. Honor the contact only when moving
	# farther into it; a retreat out of the safety margin must remain possible.
	var overlap := _space.get_rest_info(_query(origin, Vector3.ZERO))
	if not overlap.is_empty():
		var n: Vector3 = overlap["normal"]
		if motion.dot(n) < -0.0001:
			fraction = 0.0
			normal = n
			var body = instance_from_id(overlap.get("collider_id", 0))
			if body is Node and body.is_in_group("avoidance_ground"):
				hit_kind = "ground"
	if motion.length_squared() > 0.0001:
		var cast := _space.cast_motion(q)
		if cast.size() >= 2 and cast[0] < fraction:
			fraction = cast[0]
			var contact := _space.get_rest_info(_query(origin + motion * minf(1.0, cast[1] + 0.0001), Vector3.ZERO))
			normal = contact.get("normal", -motion.normalized())
			var body = instance_from_id(contact.get("collider_id", 0))
			hit_kind = "ground" if body is Node and body.is_in_group("avoidance_ground") else "building"
	# Ocean maps may have a rendered water surface without a physics collider.
	# Orbit maps explicitly opt out: y=0 is not ground there.
	if _ground and motion.y < -0.0001 and origin.y + motion.y < _floor:
		var sea_fraction := clampf((origin.y - _floor) / -motion.y, 0.0, 1.0)
		if sea_fraction <= fraction:
			fraction = sea_fraction
			normal = Vector3.UP
			hit_kind = "ground"
	return {"hit": fraction < 1.0, "fraction": fraction, "normal": normal, "kind": hit_kind}

func _path_clearance(origin: Vector3, velocity: Vector3, target: Vector3) -> float:
	var elapsed := 0.0
	var pos := origin
	var current := velocity
	# Sample the curved transition, not just an instantly rotated escape ray.
	for duration: float in [0.2, 0.2, 0.2, 0.2, LOOKAHEAD - 0.8]:
		var next := current.lerp(target, 1.0 - exp(-RESPONSE * duration))
		var motion := (current + next) * 0.5 * duration
		var hit := _sweep(pos, motion)
		if hit["hit"]:
			return (elapsed + duration * float(hit["fraction"])) / LOOKAHEAD
		pos += motion
		current = next
		elapsed += duration
	return 1.0

func _plan(origin: Vector3, velocity: Vector3, speed: float, risk: Dictionary) -> void:
	var forward := velocity.normalized() if velocity.length_squared() > 1.0 else Vector3.FORWARD
	var side := forward.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.1:
		side = Vector3.RIGHT
	var normal: Vector3 = risk["normal"]
	var options: Array[Vector3] = [
		(forward + Vector3.UP * 1.15).normalized(),
		(forward + side * 1.25).normalized(),
		(forward - side * 1.25).normalized(),
		(forward + Vector3.UP + side).normalized(),
		(forward + Vector3.UP - side).normalized(),
		Vector3.UP,
		(forward + normal * 1.8).normalized()]
	if escape != Vector3.ZERO:
		options.push_front(escape)
	var best := -INF
	for direction: Vector3 in options:
		if direction.length_squared() < 0.1:
			continue
		var room := _path_clearance(origin, velocity, direction * speed)
		var score := room * 12.0 + direction.dot(forward) * 0.7
		if kind == "ground":
			score += direction.y * 0.9
		else:
			score -= absf(direction.y) * 0.2 # Prefer a clear side route to a tall climb.
		if escape != Vector3.ZERO:
			score += direction.dot(escape) * 0.6 # Stay on the chosen side of a building.
		if score > best:
			best = score
			escape = direction
			_path_room = room
