extends RefCounted
## Five conventional mobile suits: steady jet flight, never a walking cycle.
## Only the instance-private directional clips change; weapons and form clips
## retain their own animation ownership. GunMotion is installed afterwards.
const Math := preload("res://scripts/flight/saber_motion.gd")
const Sample := preload("res://scripts/flight/gun_motion.gd")
static var _cache: Dictionary = {}

static func supports(p: SuitProfile) -> bool:
	return p.id in [SuitProfile.Id.GUSTAV00,SuitProfile.Id.MESSER_M01,SuitProfile.Id.MESSER_CMD,SuitProfile.Id.MESSER_F01] or (p.id == SuitProfile.Id.ARIZEUS and p.model_path.contains("nu_mp/"))

static func style(p: SuitProfile) -> Dictionary:
	if p.id == SuitProfile.Id.GUSTAV00:
		return {"lean":5.5,"bank":5.0,"knee":20.0,"spread":4.0,"arm":8.0,"cycle":2.8}
	if p.id == SuitProfile.Id.ARIZEUS:
		return {"lean":7.0,"bank":7.0,"knee":25.0,"spread":3.0,"arm":10.0,"cycle":2.4}
	return {"lean":9.0,"bank":10.0,"knee":30.0,"spread":6.0,"arm":15.0,"cycle":2.2}

static func install(anim: ModelAnimator, body) -> bool:
	if anim == null or not anim.ready or body._model_skel == null or not supports(body.profile): return false
	var sk: Skeleton3D = body._model_skel
	var base := anim._track_base()
	if base.is_empty(): return false
	var p: SuitProfile = body.profile
	var key := "%s:%s:%.4f:%.4f" % [p.model_path,base,p.target_height,p.model_yaw_deg]
	if not _cache.has(key):
		var clips := {}
		var root: Transform3D = body.global_transform.affine_inverse() * sk.global_transform
		for action in anim.actions:
			var name := str(action)
			if name.begins_with("fly_") or name.begins_with("dash_") or name.begins_with("turn_"):
				clips[name] = build(sk,root,p,base,name)
		_cache[key] = clips
	var library := anim.player.get_animation_library(ModelAnimator.DEFAULT_LIBRARY)
	for action in _cache[key]:
		library.remove_animation(action)
		library.add_animation(action,_cache[key][action])
	return true

static func direction(name: String) -> Vector2:
	var suffix := name.trim_prefix("dash_").trim_prefix("fly_")
	var v := Vector2.ZERO
	if suffix.contains("l"): v.x = -1
	if suffix.contains("r"): v.x = 1
	if suffix.contains("f"): v.y = 1
	if suffix.contains("b"): v.y = -1
	return v.normalized()

static func pose(sk: Skeleton3D, root: Transform3D, p: SuitProfile, name: String, time: float) -> Dictionary:
	var values := Sample._sample(sk,null,0)
	var rotations: Array[Quaternion] = values["r"]
	var positions: Array[Vector3] = values["p"]
	var scales: Array[Vector3] = values["s"]
	var s := style(p)
	var dash := name.begins_with("dash_")
	var turning := name.begins_with("turn_")
	var dir := Vector2.ZERO if turning else direction(name)
	# First and last pose are identical. Tiny symmetric trim avoids the old
	# repeated rest -> thrust -> rest pumping while input is continuously held.
	var trim := sin(TAU * time / float(s["cycle"]))
	var pitch: float = -dir.y * float(s["lean"]) * (1.6 if dash else 1.0)
	var bank: float = -dir.x * float(s["bank"]) * (1.5 if dash else 1.0)
	var yaw := -dir.x * 3.0
	if turning:
		if name.ends_with("pitch_up"): pitch = 8.0
		elif name.ends_with("pitch_down"): pitch = -8.0
		elif name.ends_with("yaw_L"):
			yaw = 7.0
			bank = 4.0
		elif name.ends_with("yaw_R"):
			yaw = -7.0
			bank = -4.0
		elif name.ends_with("roll_L"): bank = 10.0
		elif name.ends_with("roll_R"): bank = -10.0
		if p.id == SuitProfile.Id.GUSTAV00:
			pitch *= 0.7
			bank *= 0.7
			yaw *= 0.7
	for part in [["Hips",0.65],["Spine",0.20],["Chest",0.15]]:
		var weight: float = part[1]
		Math._rotate_body_axis(sk,part[0],Vector3.RIGHT,deg_to_rad((pitch + 0.3 * trim) * weight),rotations,positions,scales,root)
		Math._rotate_body_axis(sk,part[0],Vector3.UP,deg_to_rad(yaw * weight),rotations,positions,scales,root)
		Math._rotate_body_axis(sk,part[0],Vector3.BACK,deg_to_rad(bank * weight),rotations,positions,scales,root)
	Math._rotate_body_axis(sk,"Head",Vector3.RIGHT,deg_to_rad(-pitch * 0.35),rotations,positions,scales,root)
	Math._rotate_body_axis(sk,"Head",Vector3.BACK,deg_to_rad(-bank * 0.45),rotations,positions,scales,root)
	for side in ["L","R"]:
		var sign_x := 1.0 if side == "R" else -1.0
		var trail: float = 2.0 - (8.0 if dash else 0.0) - dir.y * 8.0
		var knee: float = float(s["knee"]) + (10.0 if dash else 0.0)
		# The leg on the thrust side tucks slightly; the other leg steadies it.
		trail += dir.x * sign_x * 4.0
		knee += dir.x * sign_x * 3.0
		Math._rotate_body_axis(sk,"Thigh." + side,Vector3.RIGHT,deg_to_rad(trail + 0.35 * trim),rotations,positions,scales,root)
		Math._rotate_body_axis(sk,"Thigh." + side,Vector3.BACK,deg_to_rad(sign_x * float(s["spread"]) - dir.x * 2.0),rotations,positions,scales,root)
		Math._rotate_body_axis(sk,"Shin." + side,Vector3.RIGHT,deg_to_rad(-knee - 0.35 * trim),rotations,positions,scales,root)
		Math._rotate_body_axis(sk,"Foot." + side,Vector3.RIGHT,deg_to_rad(knee * 0.35),rotations,positions,scales,root)
	Math._rotate_body_axis(sk,"UpperArm.L",Vector3.BACK,deg_to_rad(-float(s["arm"]) - (4.0 if dash else 0.0)),rotations,positions,scales,root)
	Math._rotate_body_axis(sk,"LowerArm.L",Vector3.RIGHT,deg_to_rad(12.0 + (4.0 if dash else 0.0)),rotations,positions,scales,root)
	return values

static func build(sk: Skeleton3D, root: Transform3D, p: SuitProfile, base: String, name: String) -> Animation:
	var clip := Animation.new()
	clip.resource_name = name
	clip.length = float(style(p)["cycle"])
	clip.loop_mode = Animation.LOOP_LINEAR
	var tracks := {}
	for bone in sk.get_bone_count():
		var path := NodePath(base + ":" + str(sk.get_bone_name(bone)))
		var rotation := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(rotation,path)
		tracks[bone] = rotation
		var rest := sk.get_bone_rest(bone)
		for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_SCALE_3D]:
			var tr := clip.add_track(type)
			clip.track_set_path(tr,path)
			var value: Vector3 = rest.origin if type == Animation.TYPE_POSITION_3D else rest.basis.get_scale()
			clip.track_insert_key(tr,0,value)
			clip.track_insert_key(tr,clip.length,value)
	var frames := ceili(clip.length * 30)
	for frame in range(frames + 1):
		var time := minf(frame / 30.0,clip.length)
		var values := pose(sk,root,p,name,time)
		for bone: int in tracks: clip.track_insert_key(tracks[bone],time,values["r"][bone])
	return clip
