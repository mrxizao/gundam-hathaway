extends RefCounted
## A tap commits on release; crossing the hold threshold can never spend a dash.
const HOLD_SECONDS := 0.25
var elapsed := 0.0
var down := false
var super_active := false
func tick(delta: float, pressed: bool) -> bool:
	var tap := false
	if pressed:
		elapsed = elapsed + delta if down else delta
		down = true
		super_active = elapsed >= HOLD_SECONDS
	else:
		tap = down and not super_active
		reset()
	return tap
func reset() -> void:
	elapsed = 0.0
	down = false
	super_active = false
