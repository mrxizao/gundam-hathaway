extends RefCounted
## Native rig coordinates measured on the new movie mesh's aft nozzle surfaces.
const POINTS := [Vector3(-0.024529,0.821280,-0.063970),Vector3(-0.022006,0.762614,-0.066960),Vector3(0.10517,0.26027,-0.05893),Vector3(-0.19375,0.26981,-0.04491)]
const BONES := ["Thruster.R","Thruster.R","Shin.L","Shin.R"]
static func install(body, item: Dictionary, index: int) -> void:
	if body.profile.model_path != "res://assets/models/xi_movie/xi_movie_rigged.scn" or body._model_skel == null or index >= POINTS.size(): return
	var sk: Skeleton3D = body._model_skel
	var bone := sk.find_bone(BONES[index])
	if bone < 0: return
	var native_to_model: Transform3D = body.model_pivot.global_transform.affine_inverse()*sk.global_transform
	var rest: Transform3D = native_to_model*sk.get_bone_global_rest(bone)
	var at: Vector3 = native_to_model*POINTS[index]
	item["xi_bone"] = bone
	item["xi_offset"] = rest.affine_inverse()*Transform3D(Basis.IDENTITY,at)
	sync(body,item)
static func sync(body, item: Dictionary) -> void:
	if not item.has("xi_bone") or not is_instance_valid(body._model_skel): return
	var xf: Transform3D = body.global_transform.affine_inverse()*body._model_skel.global_transform*body._model_skel.get_bone_global_pose(item["xi_bone"])*item["xi_offset"]
	item["local_at"] = xf.origin
	item["axis"] = (xf.basis*Vector3.BACK).normalized()
	item["xi_basis"] = xf.basis.orthonormalized()
	for key in ["fx","glow","boost","ab","dash"]:
		var effect: Node3D = item.get(key) as Node3D
		if is_instance_valid(effect): effect.transform = xf
