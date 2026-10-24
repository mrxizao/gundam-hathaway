extends RefCounted
## Runtime clips use each model's own bind lengths and axes. No imported asset
## is modified, and the melee movement/damage rules remain in FlightBody.

static var _clips: Dictionary = {}

static func style(p: SuitProfile) -> Dictionary:
	var duration := 1.08
	var windup := 0.20
	var amplitude := 1.0
	var torso := 1.0
	match p.id:
		SuitProfile.Id.XI, SuitProfile.Id.XI_FINAL:
			duration = 1.14
			windup = 0.22
			amplitude = 1.08
			torso = 1.20
		SuitProfile.Id.PENELOPE:
			duration = 1.32
			windup = 0.26
			amplitude = 0.82
			torso = 1.12
			if p.form == 1: # Odysseus sheds the heavy flight armor.
				duration = 1.08
				windup = 0.20
				amplitude = 1.0
		SuitProfile.Id.ARIZEUS:
			if p.form == SuitProfile.ArizeusForm.NORMAL:
				duration = 1.25
				windup = 0.25
				amplitude = 0.72
			else:
				duration = 1.05
				windup = 0.18
		SuitProfile.Id.GUSTAV00:
			duration = 1.14
			windup = 0.22
			amplitude = 0.82
		SuitProfile.Id.MESSER_M01, SuitProfile.Id.MESSER_CMD, SuitProfile.Id.MESSER_F01:
			duration = 1.04
			windup = 0.18
			torso = 1.15
			if p.id == SuitProfile.Id.MESSER_CMD:
				amplitude = 0.94
			elif p.id == SuitProfile.Id.MESSER_F01:
				amplitude = 1.06
		SuitProfile.Id.NEUE_ZIEL:
			duration = 1.32
			windup = 0.26
		SuitProfile.Id.GP03D:
			torso = 0.0
	return {"duration":duration,"windup":windup,"impact":windup + 0.18,"follow":windup + 0.34,"amplitude":amplitude,"variant":int(p.id),"torso":torso}

static func install(anim: ModelAnimator, body) -> bool:
	var sk: Skeleton3D = body._model_skel
	if anim == null or not anim.ready or sk == null or not body.profile.has_saber:
		return false
	for name in ["UpperArm.L","LowerArm.L","Hand.L","hand_L"]:
		if sk.find_bone(name) < 0: return false
	var base := anim._track_base()
	if base.is_empty(): return false
	var p: SuitProfile = body.profile
	var key := "%s:%s:%.4f:%.4f" % [p.model_path,base,p.target_height,p.model_yaw_deg]
	if not _clips.has(key):
		var neutral := anim.rotations_at(anim.idle_action,0.0) if not anim.idle_action.is_empty() else {}
		if anim.pose_overrides.has(anim.idle_action):
			var source := anim.player.get_animation(anim.playback_name(anim.idle_action))
			for track in source.get_track_count():
				var path := source.track_get_path(track)
				if source.track_get_type(track) == Animation.TYPE_ROTATION_3D and path.get_subname_count() == 1:
					neutral[str(path.get_subname(0))] = source.rotation_track_interpolate(track,0.0)
		var root: Transform3D = body.global_transform.affine_inverse() * sk.global_transform
		_clips[key] = build(sk,root,p,base,neutral)
	var library := anim.player.get_animation_library(ModelAnimator.DEFAULT_LIBRARY)
	if library.has_animation("slash"): library.remove_animation("slash")
	library.add_animation("slash",_clips[key])
	anim.actions["slash"] = true
	return true

static func _smooth(t: float) -> float:
	t = clampf(t,0,1)
	return t * t * t * (t * (t * 6 - 15) + 10)

static func _phase(time: float, s: Dictionary) -> Dictionary:
	var knots: Array[float] = [0.0,s["windup"],s["impact"],s["follow"],s["follow"] + 0.07,s["duration"]]
	var i := 0
	while i < knots.size() - 2 and time > knots[i + 1]: i += 1
	return {"a":i,"b":i + 1,"blend":_smooth((time - knots[i]) / maxf(knots[i + 1] - knots[i],0.001))}

static func blade_direction(time: float, s: Dictionary) -> Vector3:
	var keys := [Vector3.FORWARD,Vector3(-0.75,0.55,0.35).normalized(),Vector3(0.18,-0.12,-1).normalized(),Vector3(0.8,-0.48,-0.18).normalized(),Vector3(0.8,-0.48,-0.18).normalized(),Vector3.FORWARD]
	if s.get("variant",-1) in [int(SuitProfile.Id.XI),int(SuitProfile.Id.XI_FINAL)]:
		keys = [Vector3.FORWARD,Vector3(-0.88,0.48,0.22).normalized(),Vector3(0.12,-0.10,-1).normalized(),Vector3(0.84,-0.50,-0.25).normalized(),Vector3(0.84,-0.50,-0.25).normalized(),Vector3.FORWARD]
	elif s.get("variant",-1) == int(SuitProfile.Id.PENELOPE):
		keys = [Vector3.FORWARD,Vector3(-0.85,0.40,0.18).normalized(),Vector3(-0.25,-0.12,-1).normalized(),Vector3(0.55,-0.55,-0.55).normalized(),Vector3(0.55,-0.55,-0.55).normalized(),Vector3.FORWARD]
	elif s.get("variant",-1) == int(SuitProfile.Id.GP03D):
		keys = [Vector3.FORWARD,Vector3(-0.72,0.22,0.30).normalized(),Vector3(0.12,-0.08,-1).normalized(),Vector3(0.72,-0.32,-0.35).normalized(),Vector3(0.66,-0.28,-0.42).normalized(),Vector3.FORWARD]
	var phase := _phase(time,s)
	return (keys[phase["a"]] as Vector3).slerp(keys[phase["b"]],phase["blend"]).normalized()

static func _global_pose(sk: Skeleton3D, i: int, rotations: Array[Quaternion], positions: Array[Vector3], scales: Array[Vector3], root: Transform3D, cache: Dictionary) -> Transform3D:
	if cache.has(i): return cache[i]
	var parent := sk.get_bone_parent(i)
	var parent_pose := root if parent < 0 else _global_pose(sk,parent,rotations,positions,scales,root,cache)
	var result := parent_pose * Transform3D(Basis(rotations[i]).scaled(scales[i]),positions[i])
	cache[i] = result
	return result

static func _globals(sk: Skeleton3D, rotations: Array[Quaternion], positions: Array[Vector3], scales: Array[Vector3], root: Transform3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	var cache := {}
	for i in sk.get_bone_count(): poses.append(_global_pose(sk,i,rotations,positions,scales,root,cache))
	return poses

static func _rotate_body_axis(sk: Skeleton3D, name: String, axis: Vector3, angle: float, rotations: Array[Quaternion], positions: Array[Vector3], scales: Array[Vector3], root: Transform3D) -> void:
	var i := sk.find_bone(name)
	if i < 0: return
	var parent := sk.get_bone_parent(i)
	var cache := {}
	var parent_basis := (root if parent < 0 else _global_pose(sk,parent,rotations,positions,scales,root,cache)).basis.orthonormalized()
	var local_axis := parent_basis.inverse() * axis
	rotations[i] = (Quaternion(local_axis.normalized(),angle) * rotations[i]).normalized()

static func _set_world_rotation(sk: Skeleton3D, i: int, wanted: Quaternion, rotations: Array[Quaternion], poses: Array[Transform3D], root: Transform3D) -> void:
	var parent := sk.get_bone_parent(i)
	var parent_basis := (root if parent < 0 else poses[parent]).basis.orthonormalized()
	rotations[i] = (parent_basis.get_rotation_quaternion().inverse() * wanted).normalized()

static func build(sk: Skeleton3D, root: Transform3D, p: SuitProfile, base: String, neutral: Dictionary) -> Animation:
	var s := style(p)
	var a := Animation.new()
	a.resource_name = "slash"
	a.length = s["duration"]
	a.loop_mode = Animation.LOOP_NONE
	var rest: Array[Quaternion] = []
	var positions: Array[Vector3] = []
	var scales: Array[Vector3] = []
	var tracks: Array[int] = []
	var position_tracks: Array[int] = []
	for i in sk.get_bone_count():
		var bind := sk.get_bone_rest(i)
		var q: Quaternion = neutral.get(str(sk.get_bone_name(i)),bind.basis.orthonormalized().get_rotation_quaternion())
		rest.append(q.normalized())
		positions.append(bind.origin)
		scales.append(bind.basis.get_scale())
		var path := NodePath(base + ":" + str(sk.get_bone_name(i)))
		var rotation := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(rotation,path)
		tracks.append(rotation)
		for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_SCALE_3D]:
			var tr := a.add_track(type)
			a.track_set_path(tr,path)
			if type == Animation.TYPE_POSITION_3D: position_tracks.append(tr)
			var value: Vector3 = bind.origin if type == Animation.TYPE_POSITION_3D else bind.basis.get_scale()
			a.track_insert_key(tr,0.0,value)
			a.track_insert_key(tr,a.length,value)
	var neutral_poses := _globals(sk,rest,positions,scales,root)
	var upper := sk.find_bone("UpperArm.L")
	var lower := sk.find_bone("LowerArm.L")
	var wrist := sk.find_bone("Hand.L")
	var grip := sk.find_bone("hand_L")
	var grip_bind := neutral_poses[wrist].affine_inverse() * neutral_poses[grip]
	var length_1 := neutral_poses[upper].origin.distance_to(neutral_poses[lower].origin)
	var length_2 := neutral_poses[lower].origin.distance_to(neutral_poses[wrist].origin)
	var total := length_1 + length_2
	var neutral_reach := neutral_poses[wrist].origin - neutral_poses[upper].origin
	var wrist_keys := [neutral_reach,Vector3(-0.65,0.35,0.25).normalized() * total * 0.87,Vector3(-0.23,-0.12,-0.94).normalized() * total * 0.94,Vector3(0.40,-0.55,-0.55).normalized() * total * 0.86,Vector3(0.40,-0.55,-0.55).normalized() * total * 0.86,neutral_reach]
	if p.id in [SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL]:
		wrist_keys = [neutral_reach,Vector3(-0.78,0.44,0.18).normalized()*total*0.86,Vector3(-0.18,-0.08,-0.97).normalized()*total*0.94,Vector3(0.43,-0.48,-0.59).normalized()*total*0.88,Vector3(0.43,-0.48,-0.59).normalized()*total*0.88,neutral_reach]
	elif p.id == SuitProfile.Id.PENELOPE:
		wrist_keys = [neutral_reach,Vector3(-0.82,0.32,0.18).normalized()*total*0.84,Vector3(-0.40,-0.05,-0.91).normalized()*total*0.90,Vector3(0.14,-0.40,-0.78).normalized()*total*0.84,Vector3(0.14,-0.40,-0.78).normalized()*total*0.84,neutral_reach]
	var twist_keys := [0.0,-1.12,0.48,1.18,1.04,0.0]
	var guard_keys := [0.0,1.0,0.88,0.62,0.48,0.0]
	var ik_keys := [0.0,1.0,1.0,1.0,1.0,0.0]
	var steps := ceili(a.length * 60)
	for frame in range(steps + 1):
		var time := minf(frame / 60.0,a.length)
		var rotations: Array[Quaternion] = rest.duplicate()
		var phase := _phase(time,s)
		var blend: float = phase["blend"]
		var twist: float = lerpf(twist_keys[phase["a"]],twist_keys[phase["b"]],blend) * s["amplitude"]
		var guard: float = lerpf(guard_keys[phase["a"]],guard_keys[phase["b"]],blend) * s["amplitude"]
		var ik: float = lerpf(ik_keys[phase["a"]],ik_keys[phase["b"]],blend)
		# Torso arrives slightly after the hand; knees absorb the follow-through.
		var body_phase := _phase(maxf(0.0,time - 0.025 * sin(PI * time / a.length)),s)
		var body_twist: float = lerpf(twist_keys[body_phase["a"]],twist_keys[body_phase["b"]],body_phase["blend"]) * s["amplitude"] * s["torso"]
		_rotate_body_axis(sk,"Head",Vector3.UP,deg_to_rad(5.0 * body_twist),rotations,positions,scales,root)
		_rotate_body_axis(sk,"Chest",Vector3.BACK,deg_to_rad(3.5 * body_twist),rotations,positions,scales,root)
		_rotate_body_axis(sk,"Hips",Vector3.UP,deg_to_rad(-9 * body_twist),rotations,positions,scales,root)
		_rotate_body_axis(sk,"Chest",Vector3.UP,deg_to_rad(-14 * body_twist),rotations,positions,scales,root)
		_rotate_body_axis(sk,"Spine",Vector3.RIGHT,deg_to_rad(-6 * guard),rotations,positions,scales,root)
		_rotate_body_axis(sk,"UpperArm.R",Vector3.BACK,deg_to_rad(14 * guard),rotations,positions,scales,root)
		_rotate_body_axis(sk,"LowerArm.R",Vector3.RIGHT,deg_to_rad(-12 * guard),rotations,positions,scales,root)
		_rotate_body_axis(sk,"Thigh.L",Vector3.RIGHT,deg_to_rad(-12 * guard),rotations,positions,scales,root)
		_rotate_body_axis(sk,"Thigh.R",Vector3.RIGHT,deg_to_rad(13 * guard),rotations,positions,scales,root)
		_rotate_body_axis(sk,"Shin.L",Vector3.RIGHT,deg_to_rad(13 * guard),rotations,positions,scales,root)
		if p.id in [SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL,SuitProfile.Id.PENELOPE]:
			_rotate_body_axis(sk,"Hips",Vector3.RIGHT,deg_to_rad(-4.0*guard),rotations,positions,scales,root)
			_rotate_body_axis(sk,"Thigh.R",Vector3.RIGHT,deg_to_rad(-7.0*twist),rotations,positions,scales,root)
			_rotate_body_axis(sk,"Shin.R",Vector3.RIGHT,deg_to_rad(-10.0*guard),rotations,positions,scales,root)
		var poses := _globals(sk,rotations,positions,scales,root)
		if frame > 0 and frame < steps:
			var reach: Vector3 = (wrist_keys[phase["a"]] as Vector3).lerp(wrist_keys[phase["b"]],blend)
			var shoulder := poses[upper].origin
			var distance := clampf(reach.length(),absf(length_1 - length_2) + 0.01,total * 0.985)
			var axis := reach.normalized()
			# Keep the elbow plane behind the arm. An outward pole can align with
			# the wide windup reach and flip the elbow around the shoulder.
			var pole := Vector3(-0.3,-0.2,1)
			pole = (pole - axis * pole.dot(axis)).normalized()
			if pole.length_squared() < 0.001: pole = axis.cross(Vector3.UP).normalized()
			var along := (length_1 * length_1 + distance * distance - length_2 * length_2) / (2 * distance)
			var elbow := shoulder + axis * along + pole * sqrt(maxf(0,length_1 * length_1 - along * along))
			var goal := shoulder + axis * distance
			var upper_delta := Quaternion((poses[lower].origin - shoulder).normalized(),(elbow - shoulder).normalized())
			_set_world_rotation(sk,upper,upper_delta * poses[upper].basis.orthonormalized().get_rotation_quaternion(),rotations,poses,root)
			rotations[upper] = rest[upper].slerp(rotations[upper],ik)
			poses = _globals(sk,rotations,positions,scales,root)
			var lower_delta := Quaternion((poses[wrist].origin - poses[lower].origin).normalized(),(goal - poses[lower].origin).normalized())
			_set_world_rotation(sk,lower,lower_delta * poses[lower].basis.orthonormalized().get_rotation_quaternion(),rotations,poses,root)
			rotations[lower] = rest[lower].slerp(rotations[lower],ik)
			poses = _globals(sk,rotations,positions,scales,root)
			var desired := Basis.looking_at(blade_direction(time,s),Vector3.UP).get_rotation_quaternion() * neutral_poses[wrist].basis.orthonormalized().get_rotation_quaternion()
			_set_world_rotation(sk,wrist,desired,rotations,poses,root)
			rotations[wrist] = rest[wrist].slerp(rotations[wrist],ik)
			# hand_L is a sibling of Hand.L on several delivered rigs. Rebuild its
			# local pose from the real palm, retaining the original grip offset.
			poses = _globals(sk,rotations,positions,scales,root)
			var grip_world := poses[wrist] * grip_bind
			var parent := sk.get_bone_parent(grip)
			var grip_local := (root if parent < 0 else poses[parent]).affine_inverse() * grip_world
			rotations[grip] = grip_local.basis.orthonormalized().get_rotation_quaternion()
			a.track_insert_key(position_tracks[grip],time,grip_local.origin)
		for i in sk.get_bone_count(): a.track_insert_key(tracks[i],time,rotations[i])
	return a
