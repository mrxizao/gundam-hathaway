extends RefCounted
## Visual thrust trim, independent of authored normal/cruise mechanical curves.
var angles := Vector3.ZERO
var speed := Vector3.ZERO
var intent := Vector2.ZERO

static func supports(profile: SuitProfile) -> bool:
	return profile.id in [SuitProfile.Id.XI, SuitProfile.Id.PENELOPE, SuitProfile.Id.REGZ_CUSTOM] and not (profile.id == SuitProfile.Id.PENELOPE and profile.form == 1)

static func read_intent(body) -> Vector2:
	if not body.is_player or not body.alive or body.get("controls_enabled") != true:
		return Vector2.ZERO
	if body.translate_mode:
		var local: Vector3 = body.global_basis.orthonormalized().inverse()*body.translate_dir
		return Vector2(local.x, -local.z).limit_length(1.0)
	return Vector2(Input.get_axis("roll_left", "roll_right"), Input.get_axis("pitch_nose_up", "pitch_nose_down")).limit_length(1.0)

func step(body, delta: float) -> Vector3:
	intent = read_intent(body)
	var cruise: bool = body.in_cruise_form() or (body.profile.id == SuitProfile.Id.REGZ_CUSTOM and body.profile.form == 1)
	var heavy: bool = body.profile.id == SuitProfile.Id.PENELOPE
	var gain := 0.75 if heavy else 1.0
	var pitch := -intent.y*(5.0 if cruise else 7.0)
	# Reverse thrust is a visible upright braking stance, not an inverted forward lean.
	if intent.y < 0.0: pitch = -intent.y*(7.0 if cruise else 10.0)
	var target := Vector3(pitch, -intent.x*(2.0 if cruise else 3.0), -intent.x*(12.0 if cruise else 10.0))*gain
	# Strong authored gestures own their silhouette; input trim recedes smoothly.
	if body.melee_hit_reaction.elapsed<body.melee_hit_reaction.DURATION or body._qb_timer > 0.0 or body.saber_active() or body._saber_visual_tail > 0.0:
		target = Vector3.ZERO
	elif body._gun_recoil_clock < 0.24:
		target *= 0.35
	if body.model_fsm != null and body.model_fsm.state in [ModelAnimFSM.State.FORM, ModelAnimFSM.State.BURST]:
		target = Vector3.ZERO
	var omega := 10.0 if heavy else 14.0
	var remaining := clampf(delta, 0.0, 0.1)
	while remaining > 0.0:
		var h := minf(remaining, 1.0/120.0)
		speed += ((target-angles)*omega*omega-speed*2.0*omega)*h
		angles += speed*h
		remaining -= h
	return angles
