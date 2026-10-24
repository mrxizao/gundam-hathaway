extends RefCounted
## Additive visual flinch; never writes physics, velocity, damage or weapon state.
const DURATION := 0.82
var elapsed := DURATION
var peak := Vector3.ZERO
var angles := Vector3.ZERO
static func supports(profile: SuitProfile) -> bool:
	return profile != null and profile.id not in [SuitProfile.Id.GP03D,SuitProfile.Id.GP03S,SuitProfile.Id.NEUE_ZIEL]
func trigger(body,source: Node3D) -> void:
	if not supports(body.profile): return
	var direction: Vector3 = body.global_basis*Vector3.BACK
	if is_instance_valid(source) and source != body and body.global_position.distance_squared_to(source.global_position)>0.0001:
		direction=body.global_position-source.global_position
	trigger_direction(body,direction)

func trigger_direction(body,direction: Vector3) -> void:
	if not supports(body.profile): return
	var local: Vector3 = body.global_basis.orthonormalized().inverse()*direction.normalized() if direction.length_squared()>0.0001 else Vector3.BACK
	var heavy: bool = body.profile.id in [SuitProfile.Id.PENELOPE,SuitProfile.Id.ARIZEUS]
	var gain := 0.68 if heavy else 1.0
	if body.profile.form>0: gain*=0.8
	# Backward flinch from frontal cuts, side twist/roll from lateral strikes.
	peak=Vector3(-local.z*18.0-local.y*6.0,local.x*11.0,local.x*15.0)*gain
	if peak.length()<3.0: peak=Vector3(-14,4,3)*gain
	elapsed=0.0
func step(delta: float) -> Vector3:
	elapsed=minf(elapsed+maxf(delta,0.0),DURATION)
	var weight := 0.0
	if elapsed<0.09: weight=smoothstep(0.0,0.09,elapsed)
	elif elapsed<0.24: weight=lerpf(1.0,0.8,smoothstep(0.09,0.24,elapsed))
	elif elapsed<0.53: weight=lerpf(0.8,-0.16,smoothstep(0.24,0.53,elapsed))
	else: weight=lerpf(-0.16,0.0,smoothstep(0.53,DURATION,elapsed))
	angles=peak*weight
	return angles
