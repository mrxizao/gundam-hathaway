extends RefCounted
## Instance-private weapon poses. Imported meshes, skins and animations stay intact.
const Math := preload("res://scripts/flight/saber_motion.gd")
static var _cache: Dictionary = {}
static var _weapons: Dictionary = {}
static var _shot_templates: Dictionary = {}

static func weapon_geometry(body) -> Dictionary:
	# The delivered muzzle helpers are not consistently at the barrel tip.
	# Read the actual rigid rifle mesh at bind pose; exclude fingers and armor.
	var points: Array[Vector3] = []
	for mi: MeshInstance3D in body.model_root.find_children("*","MeshInstance3D",true,false):
		if mi.mesh == null or mi.skin == null: continue
		var extent := mi.mesh.get_aabb().size
		var long_mesh: bool = maxf(extent.x,maxf(extent.y,extent.z)) > body.profile.model_native_height * 0.18
		var xf: Transform3D = body.global_transform.affine_inverse() * mi.global_transform
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty(): continue
			var stride: int = bones.size() / vertices.size()
			if body.profile.id == SuitProfile.Id.XI_FINAL:
				for vertex_index in vertices.size():
					var best := vertex_index*stride
					for k in range(best,best+stride):
						if weights[k] > weights[best]: best=k
					var bind_index := bones[best]
					var name := str(mi.skin.get_bind_name(bind_index))
					if name.is_empty(): name=str(body._model_skel.get_bone_name(mi.skin.get_bind_bone(bind_index)))
					if name == "Weapon.R": points.append(xf*vertices[vertex_index])
				continue
			var slot := 0
			for k in stride:
				if weights[k] > weights[slot]: slot = k
			var bind := bones[slot]
			var bone_name := str(mi.skin.get_bind_name(bind))
			if bone_name.is_empty(): bone_name = str(body._model_skel.get_bone_name(mi.skin.get_bind_bone(bind)))
			if bone_name != "Weapon.R" and not (bone_name == "Hand.R" and long_mesh): continue
			for vertex in vertices: points.append(xf * vertex)
	if points.size() < 20: return {}
	var center := Vector3.ZERO
	for point in points: center += point
	center /= points.size()
	var xx := 0.0
	var xy := 0.0
	var xz := 0.0
	var yy := 0.0
	var yz := 0.0
	var zz := 0.0
	for point in points:
		var v := point - center
		xx += v.x*v.x
		xy += v.x*v.y
		xz += v.x*v.z
		yy += v.y*v.y
		yz += v.y*v.z
		zz += v.z*v.z
	var axis := Vector3.FORWARD
	for k in 32:
		axis = Vector3(xx*axis.x + xy*axis.y + xz*axis.z,xy*axis.x + yy*axis.y + yz*axis.z,xz*axis.x + yz*axis.y + zz*axis.z).normalized()
	if axis.dot(Vector3.FORWARD) < 0: axis = -axis
	var projections: Array[float] = []
	for point in points: projections.append((point - center).dot(axis))
	projections.sort()
	var cutoff := projections[int(projections.size() * 0.98)]
	var tip := Vector3.ZERO
	var count := 0
	for point in points:
		if (point - center).dot(axis) >= cutoff:
			tip += point
			count += 1
	return {"axis":axis,"tip":tip / maxi(count,1)}

static func style(p: SuitProfile) -> Dictionary:
	var duration := 0.42
	var recoil := 0.065
	var reach := 0.82
	var lateral := 0.18
	match p.id:
		SuitProfile.Id.XI, SuitProfile.Id.XI_FINAL:
			duration = 0.48
			recoil = 0.075
			reach = 0.88
			lateral = 0.16
		SuitProfile.Id.PENELOPE:
			duration = 0.56
			recoil = 0.060
		SuitProfile.Id.ARIZEUS:
			duration = 0.46 if p.rifle_back_mount else 0.36
			recoil = 0.035 if p.rifle_back_mount else 0.055
		SuitProfile.Id.GUSTAV00:
			duration = 0.49
			recoil = 0.045
			reach = 0.77
			lateral = 0.24
		SuitProfile.Id.MESSER_M01, SuitProfile.Id.MESSER_CMD, SuitProfile.Id.MESSER_F01:
			duration = 0.46
			reach = 0.76
			lateral = 0.27
	return {"duration":duration,"recoil":recoil,"reach":reach,"lateral":lateral}

static func recoil_at(time: float, duration: float) -> float:
	var t := clampf(time / maxf(duration,0.01),0,1)
	if t < 0.16: return Math._smooth(t / 0.16)
	return 1.0 - Math._smooth((t - 0.16) / 0.84)

static func install(anim: ModelAnimator, body) -> bool:
	var sk: Skeleton3D = body._model_skel
	if anim == null or not anim.ready or sk == null or body.profile.rifle_count <= 0:
		return false
	for name in ["UpperArm.R","LowerArm.R","Hand.R"]:
		if sk.find_bone(name) < 0: return false
	var base := anim._track_base()
	if base.is_empty(): return false
	var p: SuitProfile = body.profile
	var key := "%s:%s:%.4f:%.4f" % [p.model_path,base,p.target_height,p.model_yaw_deg]
	if not _weapons.has(key):
		_weapons[key] = weapon_geometry(body) if not p.rifle_back_mount and not (p.id == SuitProfile.Id.PENELOPE and p.form == 0) else {}
	var weapon: Dictionary = _weapons[key]
	if not weapon.is_empty():
		var root: Transform3D = body.global_transform.affine_inverse() * sk.global_transform
		var hand := root * sk.get_bone_global_rest(sk.find_bone("Hand.R"))
		body._gun_barrel_in_hand = hand.basis.orthonormalized().inverse() * (weapon["axis"] as Vector3)
		for name in ["Weapon.R","hand_R","muzzle_L","muzzle_R"]:
			var bone := sk.find_bone(name)
			if bone < 0: continue
			var target := root * sk.get_bone_global_rest(bone)
			if name.begins_with("muzzle"): target.origin = weapon["tip"]
			body._gun_grip_bind[bone] = hand.affine_inverse() * target
	if not _cache.has(key):
		var clips := {}
		var root: Transform3D = body.global_transform.affine_inverse() * sk.global_transform
		var neutral := anim.player.get_animation(ModelAnimator.REST_CLIP)
		clips["shoot"] = build(sk,root,p,base,neutral,true,weapon)
		if not p.rifle_back_mount:
			for name in anim.player.get_animation_list():
				var n := str(name)
				if n == str(ModelAnimator.REST_CLIP) or n == anim.idle_action or n.begins_with("fly_") or n.begins_with("dash_") or n.begins_with("turn_"):
					clips[n] = build(sk,root,p,base,anim.player.get_animation(anim.playback_name(name)),false,weapon)
		_cache[key] = clips
	var library := anim.player.get_animation_library(ModelAnimator.DEFAULT_LIBRARY)
	for name in _cache[key]:
		var playback := str(name) if name == "shoot" else "__gun_ready_" + str(name)
		if name != "shoot": anim.pose_overrides[str(name)] = playback
		if library.has_animation(playback): library.remove_animation(playback)
		library.add_animation(playback,_cache[key][name])
	anim.actions["shoot"] = true
	if p.id in [SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL,SuitProfile.Id.PENELOPE]:
		_shot_template(body,anim.player.get_animation("shoot"))
		anim.shot_rebase = func(source: Animation) -> Animation: return context_shot(body,source)
	return true

static func _sample(sk: Skeleton3D, source: Animation, time: float) -> Dictionary:
	var rotations: Array[Quaternion] = []
	var positions: Array[Vector3] = []
	var scales: Array[Vector3] = []
	for i in sk.get_bone_count():
		var rest := sk.get_bone_rest(i)
		rotations.append(rest.basis.orthonormalized().get_rotation_quaternion())
		positions.append(rest.origin)
		scales.append(rest.basis.get_scale())
	if source != null:
		for tr in source.get_track_count():
			var path := source.track_get_path(tr)
			if path.get_subname_count() != 1 or source.track_get_key_count(tr) == 0: continue
			var bone := sk.find_bone(path.get_subname(0))
			if bone < 0: continue
			match source.track_get_type(tr):
				Animation.TYPE_ROTATION_3D: rotations[bone] = source.rotation_track_interpolate(tr,time)
				Animation.TYPE_POSITION_3D: positions[bone] = source.position_track_interpolate(tr,time)
				Animation.TYPE_SCALE_3D: scales[bone] = source.scale_track_interpolate(tr,time)
	return {"r":rotations,"p":positions,"s":scales}

static func _rigid_grip(sk: Skeleton3D, wrist: int, name: String, neutral: Array[Transform3D], rotations: Array[Quaternion], positions: Array[Vector3], scales: Array[Vector3], root: Transform3D) -> void:
	var bone := sk.find_bone(name)
	if bone < 0 or bone == wrist: return
	var poses := Math._globals(sk,rotations,positions,scales,root)
	var wanted := poses[wrist] * neutral[wrist].affine_inverse() * neutral[bone]
	var parent := sk.get_bone_parent(bone)
	var local := (root if parent < 0 else poses[parent]).affine_inverse() * wanted
	rotations[bone] = local.basis.orthonormalized().get_rotation_quaternion()
	positions[bone] = local.origin

static func _arm(sk: Skeleton3D, side: String, p: SuitProfile, firing: bool, recoil: float, neutral: Array[Transform3D], rotations: Array[Quaternion], positions: Array[Vector3], scales: Array[Vector3], root: Transform3D, weapon: Dictionary) -> void:
	var upper := sk.find_bone("UpperArm." + side)
	var lower := sk.find_bone("LowerArm." + side)
	var wrist := sk.find_bone("Hand." + side)
	if upper < 0 or lower < 0 or wrist < 0: return
	var poses := Math._globals(sk,rotations,positions,scales,root)
	var s := style(p)
	var sign_x := 1.0 if side == "R" else -1.0
	var l1 := neutral[upper].origin.distance_to(neutral[lower].origin)
	var l2 := neutral[lower].origin.distance_to(neutral[wrist].origin)
	var total := l1 + l2
	var direction := Vector3(0,0.07 * recoil,-1).normalized() if firing else Vector3(0,-0.27,-1).normalized()
	var muzzle := sk.find_bone("muzzle_R" if side == "R" else "muzzle_L")
	if p.id == SuitProfile.Id.PENELOPE and p.form == 0:
		# Forearm-mounted emitters: aim the forearm itself, retaining the hand
		# and shield offsets. A wrist-only correction cannot aim these weapons.
		var elbow_dir := Vector3(sign_x * (0.12 + 0.025 * recoil),-0.90,-0.32 - (0.12 if firing else 0.0) + 0.12 * recoil).normalized()
		var delta := Quaternion((poses[lower].origin - poses[upper].origin).normalized(),elbow_dir)
		Math._set_world_rotation(sk,upper,delta * poses[upper].basis.orthonormalized().get_rotation_quaternion(),rotations,poses,root)
		poses = Math._globals(sk,rotations,positions,scales,root)
		var gun_axis := (neutral[muzzle].origin - neutral[lower].origin).normalized()
		var wanted := Quaternion(gun_axis,direction) * neutral[lower].basis.orthonormalized().get_rotation_quaternion()
		Math._set_world_rotation(sk,lower,wanted,rotations,poses,root)
		return
	var goal_dir := Vector3(sign_x * float(s["lateral"]),-0.25,-0.92) if firing else Vector3(sign_x * float(s["lateral"]),-0.62,-0.62)
	var reach := goal_dir.normalized() * total * float(s["reach"])
	if firing: reach += Vector3(0,0,total * float(s["recoil"]) * recoil)
	var distance := clampf(reach.length(),absf(l1 - l2) + 0.001,total * 0.97)
	var axis := reach.normalized()
	var pole := Vector3(sign_x, -0.2,0.7)
	pole = (pole - axis * pole.dot(axis)).normalized()
	var along := (l1*l1 + distance*distance - l2*l2) / (2*distance)
	var shoulder := poses[upper].origin
	var elbow := shoulder + axis * along + pole * sqrt(maxf(0,l1*l1 - along*along))
	var goal := shoulder + axis * distance
	var upper_delta := Quaternion((poses[lower].origin - shoulder).normalized(),(elbow - shoulder).normalized())
	Math._set_world_rotation(sk,upper,upper_delta * poses[upper].basis.orthonormalized().get_rotation_quaternion(),rotations,poses,root)
	poses = Math._globals(sk,rotations,positions,scales,root)
	var lower_delta := Quaternion((poses[wrist].origin - poses[lower].origin).normalized(),(goal - poses[lower].origin).normalized())
	Math._set_world_rotation(sk,lower,lower_delta * poses[lower].basis.orthonormalized().get_rotation_quaternion(),rotations,poses,root)
	poses = Math._globals(sk,rotations,positions,scales,root)
	var grip := sk.find_bone("hand_R")
	var reference := neutral[grip].origin if grip >= 0 else neutral[wrist].origin
	var gun_axis := (neutral[muzzle].origin - reference).normalized() if muzzle >= 0 else Vector3.FORWARD
	if not weapon.is_empty(): gun_axis = weapon["axis"]
	var wanted := Quaternion(gun_axis,direction) * neutral[wrist].basis.orthonormalized().get_rotation_quaternion()
	Math._set_world_rotation(sk,wrist,wanted,rotations,poses,root)
	for name in ["hand_R","Weapon.R","muzzle_L","muzzle_R"]:
		_rigid_grip(sk,wrist,name,neutral,rotations,positions,scales,root)

static func build(sk: Skeleton3D, root: Transform3D, p: SuitProfile, base: String, source: Animation, firing: bool, weapon: Dictionary = {}, saber_guard := false) -> Animation:
	var s := style(p)
	var a := Animation.new() if firing else source.duplicate() as Animation
	a.length = float(s["duration"]) if firing else source.length
	a.loop_mode = Animation.LOOP_NONE if firing else source.loop_mode
	var bind := _sample(sk,null,0)
	var neutral := Math._globals(sk,bind["r"],bind["p"],bind["s"],root)
	if not weapon.is_empty():
		for name in ["muzzle_L","muzzle_R"]:
			var bone := sk.find_bone(name)
			if bone >= 0: neutral[bone].origin = weapon["tip"]
	var names: Array[String] = []
	if firing:
		for i in sk.get_bone_count(): names.append(str(sk.get_bone_name(i)))
	else:
		names = ["UpperArm.R","LowerArm.R","Hand.R","hand_R","Weapon.R","muzzle_L","muzzle_R"]
		if p.id == SuitProfile.Id.PENELOPE and p.form == 0 and not saber_guard:
			names.append_array(["UpperArm.L","LowerArm.L","Hand.L"])
	# Replace only the owned channels, leaving locomotion, wing and other
	# animation tracks on the private copy exactly as authored.
	for tr in range(a.get_track_count() - 1,-1,-1):
		var path := a.track_get_path(tr)
		if path.get_subname_count() == 1 and str(path.get_subname(0)) in names and a.track_get_type(tr) in [Animation.TYPE_ROTATION_3D,Animation.TYPE_POSITION_3D,Animation.TYPE_SCALE_3D]:
			a.remove_track(tr)
	var tracks := {}
	for name in names:
		var i := sk.find_bone(name)
		if i < 0: continue
		var channels := []
		for type in [Animation.TYPE_ROTATION_3D,Animation.TYPE_POSITION_3D,Animation.TYPE_SCALE_3D]:
			var tr := a.add_track(type)
			a.track_set_path(tr,NodePath(base + ":" + name))
			channels.append(tr)
		tracks[i] = channels
	var fps := 60.0 if firing else 20.0
	var steps := ceili(a.length * fps)
	for frame in range(steps + 1):
		var time := minf(frame / fps,a.length)
		var values := _sample(sk,null if firing else source,time)
		var rotations: Array[Quaternion] = values["r"]
		var positions: Array[Vector3] = values["p"]
		var scales: Array[Vector3] = values["s"]
		var recoil := recoil_at(time,a.length) if firing else 0.0
		if firing:
			Math._rotate_body_axis(sk,"Spine",Vector3.RIGHT,deg_to_rad(-2.5 * recoil),rotations,positions,scales,root)
			Math._rotate_body_axis(sk,"Chest",Vector3.UP,deg_to_rad((-1.5 if p.rifle_back_mount else -3.0) * recoil),rotations,positions,scales,root)
		if not p.rifle_back_mount:
			_arm(sk,"R",p,firing,recoil,neutral,rotations,positions,scales,root,weapon)
			if p.id == SuitProfile.Id.PENELOPE and p.form == 0 and not saber_guard:
				_arm(sk,"L",p,firing,recoil,neutral,rotations,positions,scales,root,weapon)
			elif firing:
				Math._rotate_body_axis(sk,"UpperArm.L",Vector3.BACK,deg_to_rad(-6),rotations,positions,scales,root)
		for i: int in tracks:
			a.track_insert_key(tracks[i][0],time,rotations[i])
			a.track_insert_key(tracks[i][1],time,positions[i])
			a.track_insert_key(tracks[i][2],time,scales[i])
	return a

## Preserve the evaluated flight stance while the upper body delivers the shot.
## Upper-arm world axes are compensated, so a banking torso cannot turn the gun.
static func _shot_template(body,source: Animation) -> Dictionary:
	var key := source.get_instance_id()
	if _shot_templates.has(key): return _shot_templates[key]
	var sk: Skeleton3D=body._model_skel
	var root: Transform3D=body.global_transform.affine_inverse()*sk.global_transform
	var owned := ["UpperArm.","LowerArm.","Hand.","hand_","Weapon.","muzzle_","shield_"]
	var retained: Array[int]=[]
	for bone in sk.get_bone_count():
		var arm:=false
		for prefix in owned:
			if str(sk.get_bone_name(bone)).begins_with(prefix): arm=true;break
		if not arm: retained.append(bone)
	var tracks: Dictionary={}
	for tr in source.get_track_count():
		var path:=source.track_get_path(tr)
		if path.get_subname_count()!=1: continue
		var bone:=sk.find_bone(path.get_subname(0))
		if bone>=0:
			if not tracks.has(bone): tracks[bone]={}
			tracks[bone][source.track_get_type(tr)]=tr
	var uppers: Array[int]=[sk.find_bone("UpperArm.R")]
	if body.profile.id==SuitProfile.Id.PENELOPE: uppers.append(sk.find_bone("UpperArm.L"))
	var frames: Array[Dictionary]=[]
	for frame in range(ceili(source.length*60)+1):
		var values:=_sample(sk,source,minf(frame/60.0,source.length))
		var poses:=Math._globals(sk,values["r"],values["p"],values["s"],root)
		var world: Dictionary={}
		for upper in uppers: world[upper]=poses[upper].basis.orthonormalized().get_rotation_quaternion()
		values["world"]=world;frames.append(values)
	var template: Dictionary={"base":_sample(sk,null,0),"retained":retained,"tracks":tracks,"frames":frames}
	_shot_templates[key]=template
	return template

static func context_shot(body, source: Animation) -> Animation:
	var sk: Skeleton3D=body._model_skel
	var root: Transform3D=body.global_transform.affine_inverse()*sk.global_transform
	var clip: Animation=source.duplicate()
	var template:=_shot_template(body,source)
	var capture: Array[Quaternion]=[]
	var capture_pos: Array[Vector3]=[]
	for bone in sk.get_bone_count():
		capture.append(sk.get_bone_pose_rotation(bone));capture_pos.append(sk.get_bone_pose_position(bone))
	var base: Dictionary=template["base"]
	var frames: Array[Dictionary]=template["frames"]
	# Capture-to-rest deltas are constant throughout this shot. Evaluate them
	# once instead of repeating inverse/multiply work for every baked keyframe.
	var rotation_offsets: Dictionary={}
	var position_offsets: Dictionary={}
	for bone: int in template["retained"]:
		rotation_offsets[bone]=capture[bone]*(base["r"][bone] as Quaternion).inverse()
		position_offsets[bone]=capture_pos[bone]-base["p"][bone]
	for frame in frames.size():
		var values: Dictionary=frames[frame]
		var rotations: Array[Quaternion]=values["r"].duplicate()
		var positions: Array[Vector3]=values["p"].duplicate()
		var scales: Array[Vector3]=values["s"]
		for bone: int in template["retained"]:
			rotations[bone]=((rotation_offsets[bone] as Quaternion)*rotations[bone]).normalized()
			positions[bone]=(position_offsets[bone] as Vector3)+positions[bone]
		var cache: Dictionary={}
		for upper: int in values["world"]:
			var parent:=sk.get_bone_parent(upper)
			var parent_pose: Transform3D=root if parent<0 else Math._global_pose(sk,parent,rotations,positions,scales,root,cache)
			rotations[upper]=(parent_pose.basis.orthonormalized().get_rotation_quaternion().inverse()*(values["world"][upper] as Quaternion)).normalized()
		# The duplicate already owns the authored keys. Only body compensation
		# and upper-arm world aiming changed; scale and the other arm channels
		# must remain untouched. Avoid thousands of redundant resource writes.
		for bone: int in template["tracks"]:
			var channels: Dictionary=template["tracks"][bone]
			if (rotation_offsets.has(bone) or values["world"].has(bone)) and channels.has(Animation.TYPE_ROTATION_3D):
				clip.track_set_key_value(channels[Animation.TYPE_ROTATION_3D],frame,rotations[bone])
			if position_offsets.has(bone) and channels.has(Animation.TYPE_POSITION_3D):
				clip.track_set_key_value(channels[Animation.TYPE_POSITION_3D],frame,positions[bone])
	return clip
