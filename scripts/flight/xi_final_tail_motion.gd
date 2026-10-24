extends "res://scripts/flight/penelope_movie_motion.gd"
## Reuse Penelope's bounded inertial tail without its armour or hull-pitch curves.
static func attach(body) -> FormWeld:
	var result = load("res://scripts/flight/xi_final_tail_motion.gd").new()
	result._skel = body._model_skel
	result._owner = weakref(body)
	result._tail = result._skel.find_bone("Tail")
	result._tail_rest = result._skel.get_bone_rest(result._tail).basis.orthonormalized().get_rotation_quaternion()
	return result

func weld(morph: float, _ancestors_ok := true) -> void:
	_morph = clampf(morph, 0.0, 1.0)
	_apply_tail()

## Native tail-space side outlets, above the three rear engine mouths.
func missile_anchor(slot: String) -> Vector3:
	var body = _owner.get_ref() if _owner != null else null
	if body == null or not _skel_alive(): return Vector3.ZERO
	var side := 1.0 if slot == "funnel_L" else -1.0
	var point := Vector3(side*0.105, -0.12, -0.14)
	var local: Vector3 = body.global_transform.affine_inverse()*_skel.global_transform*_skel.get_bone_global_pose(_tail)*point
	if (body.dash_spin != 0.0 or body.melee_hit_reaction.angles.length_squared()>0.000001) and is_instance_valid(body.spin_pivot):
		local = body.spin_pivot.transform.basis.transposed()*local
	return local
