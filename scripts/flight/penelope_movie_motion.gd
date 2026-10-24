extends FormWeld
## Authored rigid-panel curves share the frame-end form-weld interface.
var _owner: WeakRef
var _tail := -1
var _tail_rest := Quaternion.IDENTITY
var _previous_basis := Basis.IDENTITY
var _previous_velocity := Vector3.ZERO
var _sampled := false
var _previous_hull_pitch := 0.0
var tail_angles := Vector3.ZERO
var _tail_speed := Vector3.ZERO
var _tail_target := Vector3.ZERO
var _morph := 0.0
var _vertical_pitch := 0.0
var _vertical_pitch_speed := 0.0
var _clip: Animation
var _channels: Array[Dictionary] = []
static func supports(body) -> bool:
	return body.profile != null and body.profile.model_path == "res://assets/models/penelope_movie/penelope_movie_rigged.scn"
static func bind(body) -> FormWeld:
	var result = load("res://scripts/flight/penelope_movie_motion.gd").new()
	result._skel = body._model_skel
	result._owner = weakref(body)
	result._tail = result._skel.find_bone("TailStab")
	if result._tail >= 0:
		result._tail_rest = result._skel.get_bone_rest(result._tail).basis.orthonormalized().get_rotation_quaternion()
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
			result._normal[index] = result._clip.rotation_track_interpolate(channel["track"],0.0).normalized()
			result._cruise[index] = result._clip.rotation_track_interpolate(channel["track"],result._clip.length).normalized()
		elif channel["type"] == Animation.TYPE_POSITION_3D:
			result._normal_pos[index] = result._clip.position_track_interpolate(channel["track"],0.0)
			result._cruise_pos[index] = result._clip.position_track_interpolate(channel["track"],result._clip.length)
	return result
func weld(morph: float, _ancestors_ok := true) -> void:
	if not _skel_alive(): return
	_morph = clampf(morph,0.0,1.0)
	var time := _morph*_clip.length
	for channel: Dictionary in _channels:
		match channel["type"]:
			Animation.TYPE_ROTATION_3D: _skel.set_bone_pose_rotation(channel["bone"],_clip.rotation_track_interpolate(channel["track"],time).normalized())
			Animation.TYPE_POSITION_3D: _skel.set_bone_pose_position(channel["bone"],_clip.position_track_interpolate(channel["track"],time))
			Animation.TYPE_SCALE_3D: _skel.set_bone_pose_scale(channel["bone"],_clip.scale_track_interpolate(channel["track"],time))

	_apply_tail()

## Sample actual movement, rather than input: works for players, AI and cruise.
func step_motion(delta: float) -> void:
	var body = _owner.get_ref() if _owner != null else null
	if body == null or not _skel_alive() or _tail < 0: return
	var dt := clampf(delta, 0.0001, 0.05)
	var basis: Basis = body.global_basis.orthonormalized()
	var velocity: Vector3 = body.velocity
	var angular := Vector3.ZERO
	var acceleration := Vector3.ZERO
	var hull_pitch: float = body.model_pivot.rotation.x if body.model_pivot != null else 0.0
	var hull_rate := 0.0
	if _sampled:
		var change := (_previous_basis.inverse()*basis).get_rotation_quaternion()
		angular = change.get_axis()*change.get_angle()/dt
		acceleration = basis.inverse()*(velocity-_previous_velocity)/dt
		hull_rate = wrapf(hull_pitch-_previous_hull_pitch,-PI,PI)/dt
	_previous_hull_pitch = hull_pitch
	_previous_basis = basis
	_previous_velocity = velocity
	_sampled = true
	_tail_target = motion_target(body, angular, acceleration, basis.inverse()*velocity, hull_rate, _morph)
	if not body.alive: _tail_target = Vector3.ZERO
	var remaining := dt
	while remaining > 0.0:
		var h := minf(remaining, 1.0/120.0)
		_tail_speed += ((_tail_target-tail_angles)*90.0-_tail_speed*15.0)*h
		tail_angles += _tail_speed*h
		remaining -= h
	# Write after the mechanical form curves; repeated welds cannot accumulate.
	_apply_tail()

func _apply_tail() -> void:
	if _tail < 0 or not _skel_alive(): return
	var parent := _skel.get_bone_parent(_tail)
	var parent_q := Quaternion.IDENTITY
	if parent >= 0:
		parent_q = _skel.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
	var deflection := Quaternion.from_euler(tail_angles)
	_skel.set_bone_pose_rotation(_tail, (parent_q.inverse()*deflection*parent_q*_tail_rest).normalized())

## Critically damped hull pitch keeps angular velocity continuous at boost end.
func step_vertical_pose(delta: float) -> float:
	var body = _owner.get_ref() if _owner != null else null
	if body == null: return 0.0
	var target := 0.0
	if body.alive and body._qb_timer > 0.0:
		var cruise := smoothstep(0.55,0.95,body.cruise_morph)
		var vertical: float = (body.global_basis.inverse()*body._qb_dir.normalized()).y
		if absf(vertical) >= 0.5:
			var elapsed: float = body.QB_TIME-body._qb_timer
			target = vertical*55.0*smoothstep(0.0,0.16,elapsed)*cruise
	var remaining := clampf(delta,0.0,0.05)
	while remaining > 0.0:
		var h := minf(remaining,1.0/120.0)
		_vertical_pitch_speed += ((target-_vertical_pitch)*100.0-_vertical_pitch_speed*20.0)*h
		_vertical_pitch_speed = clampf(_vertical_pitch_speed,-220.0,220.0)
		_vertical_pitch += _vertical_pitch_speed*h
		remaining -= h
	if absf(_vertical_pitch)<0.01 and absf(_vertical_pitch_speed)<0.05 and is_zero_approx(target):
		_vertical_pitch=0.0
		_vertical_pitch_speed=0.0
	return _vertical_pitch

## Distinct motion envelopes share one bounded mechanical tail joint.
static func motion_target(body, angular: Vector3, acceleration: Vector3, local_velocity: Vector3, hull_rate: float, morph: float) -> Vector3:
	var gain := lerpf(1.0, 0.86, morph)
	var side := clampf(local_velocity.x/maxf(local_velocity.length(),200.0),-1.0,1.0)
	var target := Vector3(
		clampf(-angular.x*0.17+acceleration.z*0.000065,-0.28,0.28)*gain,
		clampf(-angular.y*0.22-acceleration.x*0.000065,-0.34,0.34)*gain-side*0.08,
		clampf(-angular.z*0.12,-0.12,0.12)*gain-side*0.04)
	target.x -= clampf(acceleration.y*0.00010,-0.32,0.32)*lerpf(1.0,0.90,morph)
	# Follow the visible nose-up/dive gesture as well as physical turning.
	target.x -= clampf(hull_rate*0.025,-0.16,0.16)
	if body._qb_timer > 0.0:
		var local_dash: Vector3 = body.global_basis.inverse()*body._qb_dir.normalized()
		var elapsed: float = body.QB_TIME-body._qb_timer
		var vertical_weight := absf(local_dash.y)
		var rise := lerpf(0.06,0.14,vertical_weight)
		var fall := lerpf(0.10,0.18,vertical_weight)
		var envelope := smoothstep(0.0,rise,elapsed)*smoothstep(0.0,fall,body._qb_timer)
		target += Vector3(local_dash.z*0.14*gain-local_dash.y*0.48*lerpf(1.0,0.90,morph),-local_dash.x*0.35*gain,-local_dash.x*0.10*gain)*envelope
	# Small gun response; a heavy cut gets its own windup / slash / follow-through.
	target.x -= 0.045*clampf(1.0-body._gun_recoil_clock/0.18,0.0,1.0)
	if is_instance_valid(body.active_cannon): target.x -= 0.07
	if body.saber_active() or body._saber_visual_tail > 0.0:
		var style: Dictionary = body.SaberMotion.style(body.profile)
		var phase: Dictionary = body.SaberMotion._phase(body._saber_visual_clock,style)
		var keys := [Vector3.ZERO,Vector3(-0.07,0.16,-0.04),Vector3(0.11,-0.24,0.07),Vector3(0.04,-0.10,0.025),Vector3(0.02,-0.04,0.01),Vector3.ZERO]
		target += keys[phase.a].lerp(keys[phase.b],phase.blend)*gain
	# A shared elliptical limit stops diagonal motions from stacking excessively.
	var usage := Vector3(target.x/0.56,target.y/0.42,target.z/0.16).length()
	if usage > 1.0: target /= usage
	return target
