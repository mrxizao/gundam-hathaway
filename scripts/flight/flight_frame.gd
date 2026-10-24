extends RefCounted
## Transport the previous frame through vertical flight without a world-up pole flip.
static func facing(direction: Vector3, previous: Basis, preferred_up := Vector3.UP, delta := 1.0/60.0) -> Basis:
	var current := previous.orthonormalized()
	if direction.length_squared() < 0.000001: return current
	var forward := direction.normalized()
	var old_forward := -current.z
	var turn: Quaternion
	if old_forward.dot(forward) < -0.99999:
		turn = Quaternion(current.y, PI)
	else:
		turn = Quaternion(old_forward, forward)
	var transported := (Basis(turn)*current).orthonormalized()
	var up := preferred_up-forward*preferred_up.dot(forward)
	var strength := up.length()
	if strength < 0.000001: return transported
	up /= strength
	var angle := atan2(forward.dot(transported.y.cross(up)), transported.y.dot(up))
	# Roll correction fades continuously near the pole, rather than switching axes.
	var correction := angle*smoothstep(0.02,0.25,strength)
	if strength < 0.4 or absf(angle)>0.1:
		correction = clampf(correction,-deg_to_rad(120.0)*delta,deg_to_rad(120.0)*delta)
	return transported.rotated(forward, correction).orthonormalized()
