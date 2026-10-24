extends RefCounted
## Ground-only assist policy. Buildings (including roofs) remain obstacles.
const TRIGGER_HEIGHT := 30.0

## All player suits/forms share the last-moment boundary above the 24m death plane.
static func trigger_height(_player: Node3D) -> float:
	return TRIGGER_HEIGHT

static func excluded_ground(player: Node3D) -> Array[RID]:
	var result: Array[RID] = []
	for body in player.get_tree().get_nodes_in_group("avoidance_ground"):
		if body is CollisionObject3D:
			result.append(body.get_rid())
	return result

static func height(player: Node3D) -> float:
	return height_at(player, player.global_position)

static func height_at(player: Node3D, point: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(point, point + Vector3.DOWN * 100000.0, 1)
	if player is CollisionObject3D:
		q.exclude = [player.get_rid()]
	for i in 32:
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			break
		var body = hit.get("collider")
		if body is Node and body.is_in_group("avoidance_ground"):
			return snappedf(maxf(0.0, point.y - (hit["position"] as Vector3).y), 0.001)
		var excluded := q.exclude
		excluded.append(hit["rid"])
		q.exclude = excluded
	# Water may have no physics body. Orbit callers disable ground separately.
	return maxf(0.0, point.y)
