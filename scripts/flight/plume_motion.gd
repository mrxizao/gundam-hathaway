extends RefCounted
## Effect transforms stay in metres; the bind frame supplies only model motion.
const REAR_NOZZLES := preload("res://scripts/flight/rear_nozzle_plume.gd")
const CANDIDATES := ["Thruster.L","Thruster.R","Backpack","Shin.L","Shin.R","Foot.L","Foot.R","SideArmor.L","SideArmor.R"]
static func install(body, item: Dictionary) -> void:
	if REAR_NOZZLES.install(body,item,body._plume_fx.size()): return
	if item.has("xi_bone") or body.model_pivot == null: return
	var at: Vector3 = item["local_at"]
	if body.profile.id == SuitProfile.Id.GP03S:
		item["motion_bone"] = -2
		item["motion_axis"] = item["axis"]
		item["motion_slot"] = body._plume_fx.size()
		item["motion_offset"] = Transform3D(Basis.IDENTITY,at)
		sync(body,item)
		return
	var bone := -1
	var sk: Skeleton3D = body._model_skel
	if sk != null:
		var native_to_model: Transform3D = body.model_pivot.global_transform.affine_inverse()*sk.global_transform
		var nearest := INF
		for name in CANDIDATES:
			var index := sk.find_bone(name)
			if index < 0: continue
			var rest: Transform3D = native_to_model*sk.get_bone_global_rest(index)
			var distance := rest.origin.distance_squared_to(at)
			if distance < nearest:
				nearest = distance
				bone = index
		if bone >= 0:
			var rest: Transform3D = native_to_model*sk.get_bone_global_rest(bone)
			item["motion_offset"] = rest.affine_inverse()*Transform3D(Basis.IDENTITY,at)
	if bone < 0: item["motion_offset"] = Transform3D(Basis.IDENTITY,at)
	item["motion_bone"] = bone
	item["motion_axis"] = item["axis"]
	sync(body,item)
static func sync(body, item: Dictionary) -> void:
	if item.has("nozzle_node"):
		REAR_NOZZLES.sync(body,item)
		return
	if not item.has("motion_bone"): return
	var frame: Transform3D = body.global_transform.affine_inverse()*body.model_pivot.global_transform
	if item["motion_bone"] >= 0 and is_instance_valid(body._model_skel):
		frame = body.global_transform.affine_inverse()*body._model_skel.global_transform*body._model_skel.get_bone_global_pose(item["motion_bone"])
	var xf: Transform3D = frame*item["motion_offset"]
	if item["motion_bone"] == -2:
		xf = Transform3D(frame.basis.orthonormalized(),body.rig_anchor("plume"+str(item["motion_slot"])))
	item["local_at"] = xf.origin
	item["plume_basis"] = xf.basis.orthonormalized()
	item["axis"] = (xf.basis*item["motion_axis"]).normalized()
	for key in ["fx","glow","boost","ab","dash"]:
		var effect: Node3D = item.get(key) as Node3D
		if not is_instance_valid(effect): continue
		var size := 1.7 if body.profile.id == SuitProfile.Id.GP03D and key in ["boost","ab","dash"] else 1.0
		effect.transform = Transform3D(xf.basis*size,xf.origin)
static func sync_single(body) -> void:
	if not body._plume_fx.is_empty() or body.model_pivot == null: return
	var frame: Transform3D = body.global_transform.affine_inverse()*body.model_pivot.global_transform
	var at: Vector3 = body.rig_anchor("thruster_L") + frame.basis*Vector3(0,0,3.0)
	for effect in [body._afterburner_fx,body._dash_fx,body._dash_rings]:
		if is_instance_valid(effect): effect.transform = Transform3D(frame.basis.orthonormalized(),at)


static func maneuver_trim(profile:SuitProfile)->bool:
	return profile.id in [SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL,SuitProfile.Id.PENELOPE,SuitProfile.Id.ARIZEUS,SuitProfile.Id.REGZ_CUSTOM]

## Forward flow is not crosswind merely because an articulated nozzle is tilted.
static func maneuver_bend(wind:Vector3,axis:Vector3,reference:float,accel:float)->Vector3:
	var lateral:=Vector3(wind.x,wind.y,0)
	if lateral.length()<=maxf(1.0,absf(wind.z)*.025):return Vector3.ZERO
	var cross:=FX.plume_bend_vector(lateral,axis)
	var speed:=cross.length()
	if speed<=.01:return Vector3.ZERO
	return (cross*accel/maxf(reference,1.0)).limit_length(120.0)
