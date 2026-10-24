extends FormWeld
## Authored rigid-panel curves share the frame-end form-weld interface.
var _clip: Animation
var _channels: Array[Dictionary] = []
var _tail_motion: FormWeld
static func supports(body) -> bool:
	return body.profile != null and body.profile.model_path in ["res://assets/models/xi_movie/xi_movie_rigged.scn","res://assets/models/xi_final/xi_final_rigged.scn","res://assets/models/xi_final_rebuilt/xi_final_fresh_rig.scn"]
static func bind(body) -> FormWeld:
	var result = load("res://scripts/flight/xi_movie_motion.gd").new()
	result._skel = body._model_skel
	if body.profile.id == SuitProfile.Id.XI_FINAL and result._skel.find_bone("Tail") >= 0:
		result._tail_motion = load("res://scripts/flight/xi_final_tail_motion.gd").attach(body)
	result._clip = body.model_anim.player.get_animation("form_on")
	var bones: Dictionary = {}
	for track in result._clip.get_track_count():
		var path: NodePath = result._clip.track_get_path(track)
		if path.get_subname_count() != 1: continue
		var name := str(path.get_subname(0))
		if not name.begins_with("Movie_"): continue
		var bone: int = result._skel.find_bone(name)
		if bone >= 0:
			result._channels.append({"track":track,"bone":bone,"type":result._clip.track_get_type(track)})
			bones[bone] = true
	for bone: int in bones:
		result._idx.append(bone)
		result._normal.append(result._skel.get_bone_rest(bone).basis.orthonormalized().get_rotation_quaternion())
		result._cruise.append(result._normal[-1])
		result._normal_pos.append(result._skel.get_bone_rest(bone).origin)
		result._cruise_pos.append(result._normal_pos[-1])
	for channel: Dictionary in result._channels:
		var index: int = result._idx.find(channel["bone"])
		if channel["type"] == Animation.TYPE_ROTATION_3D:
			result._normal[index] = result._clip.rotation_track_interpolate(channel["track"],0.0)
			result._cruise[index] = result._clip.rotation_track_interpolate(channel["track"],result._clip.length)
		elif channel["type"] == Animation.TYPE_POSITION_3D:
			result._normal_pos[index] = result._clip.position_track_interpolate(channel["track"],0.0)
			result._cruise_pos[index] = result._clip.position_track_interpolate(channel["track"],result._clip.length)
	return result
func weld(morph: float, _ancestors_ok := true) -> void:
	if not _skel_alive(): return
	var time := clampf(morph,0.0,1.0)*_clip.length
	for channel: Dictionary in _channels:
		match channel["type"]:
			Animation.TYPE_ROTATION_3D: _skel.set_bone_pose_rotation(channel["bone"],_clip.rotation_track_interpolate(channel["track"],time))
			Animation.TYPE_POSITION_3D: _skel.set_bone_pose_position(channel["bone"],_clip.position_track_interpolate(channel["track"],time))
			Animation.TYPE_SCALE_3D: _skel.set_bone_pose_scale(channel["bone"],_clip.scale_track_interpolate(channel["track"],time))

	if _tail_motion != null: _tail_motion.weld(morph)

func step_motion(delta: float) -> void:
	if _tail_motion != null: _tail_motion.step_motion(delta)

func tail_anchor(slot: String) -> Vector3:
	return _tail_motion.missile_anchor(slot)

func detach() -> void:
	if _tail_motion != null:
		_tail_motion.detach()
		_tail_motion = null
	super.detach()
