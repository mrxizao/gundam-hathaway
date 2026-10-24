extends RefCounted
const ThirdPerson := preload("res://scripts/ui/third_person_hud.gd")

static func run(t: T, host: Node) -> void:
	t.suite("ThirdPersonHUD / view routing protects cockpit and launch")
	var hud := FlightHUD.new()
	var saved: bool = Settings.first_person
	Settings.first_person = false
	t.ok(hud.uses_third_person_hud(), "third-person uses the new HUD")
	Settings.first_person = true
	t.ok(not hud.uses_third_person_hud(), "first-person uses the existing cockpit")
	Settings.first_person = false
	hud.cockpit_only = true
	t.ok(not hud.uses_third_person_hud(), "rocket launch keeps its existing cockpit")
	Settings.first_person = saved
	hud.free()
	t.suite("ThirdPersonHUD / instruments fit varied aspect ratios")
	for view: Vector2 in [Vector2(1600, 900), Vector2(2560, 1600), Vector2(1280, 720), Vector2(1280, 960), Vector2(3440, 1440)]:
		var g := ThirdPerson.layout(view)
		var bounds := Rect2(Vector2.ZERO, g["view"])
		for key in ["ap", "energy", "weapons", "speed", "alt", "radar"]:
			var rect: Rect2 = g[key]
			t.ok(bounds.encloses(rect), "%s fits %s" % [key, view])
		t.ok(not (g["ap"] as Rect2).intersects(g["energy"]), "AP and energy do not overlap")
		t.ok(not (g["energy"] as Rect2).intersects(g["weapons"]), "energy and weapons do not overlap")
		var radar: Rect2 = g["radar"]
		var ap: Rect2 = g["ap"]
		t.ok(radar.end.y + 12 <= ap.position.y, "radar sits above AP with a gap")
		t.ok(radar.get_center().x >= ap.position.x and radar.get_center().x <= ap.end.x, "radar aligns over the AP area")
		for key in ["ap", "energy", "weapons", "speed", "alt"]:
			t.ok(not (g["radar"] as Rect2).intersects(g[key]), "radar does not cover %s at %s" % [key, view])
	t.suite("ThirdPersonHUD / limited contacts retain target and stable keys")
	t.eq(ThirdPerson.contact_indices([], null).size(), 0, "empty roster")
	t.eq(ThirdPerson.contact_indices([1, 2], 2), [0, 1], "short roster retains numbering")
	t.eq(ThirdPerson.contact_indices([1, 2, 3, 4, 5, 6], 6), [0, 1, 5], "selected target outside first three stays visible with original key")
	t.eq(ThirdPerson.contact_indices([1, 2, 3, 4], null), [0, 1, 2], "roster remains bounded without a target")

	t.suite("ThirdPersonHUD / radar bearing, range and vertical fallback")
	var samples := [
		[Vector3(0, 0, -2500), Vector3.FORWARD, Vector2(0, -25)],
		[Vector3(2500, 0, 0), Vector3.FORWARD, Vector2(25, 0)],
		[Vector3(0, 0, 2500), Vector3.FORWARD, Vector2(0, 25)],
		[Vector3(-2500, 0, 0), Vector3.FORWARD, Vector2(-25, 0)],
		[Vector3(2500, 9000, 0), Vector3.RIGHT, Vector2(0, -25)],
		[Vector3(0, 0, -2500), Vector3.UP, Vector2(0, -25)],
		[Vector3(0, 9000, 0), Vector3.FORWARD, Vector2.ZERO]]
	for sample: Array in samples:
		var contact := ThirdPerson.radar_contact(sample[0], sample[1], 50, 5000)
		var offset: Vector2 = contact["offset"]
		var expected: Vector2 = sample[2]
		t.near(offset.x, expected.x, 0.001, "radar horizontal bearing %s" % sample[0])
		t.near(offset.y, expected.y, 0.001, "radar forward bearing %s" % sample[0])
		t.ok(not contact["outside"], "inside contacts stay inside")
	var edge := ThirdPerson.radar_contact(Vector3(5000, 0, 0), Vector3.FORWARD, 50, 5000)
	t.near((edge["offset"] as Vector2).x, 50, 0.001, "range boundary maps to rim")
	t.ok(not edge["outside"], "exact range is still inside")
	var far := ThirdPerson.radar_contact(Vector3(10000, 10000, -10000), Vector3.FORWARD, 50, 5000)
	var far_offset: Vector2 = far["offset"]
	t.ok(far["outside"], "distant contacts marked out of range")
	t.near(far_offset.length(), 50, 0.001, "distant contacts clamp to rim")
	t.near(far_offset.x, -far_offset.y, 0.001, "rim clamping preserves bearing")
	_motion(t, host)

static func _graduation(ticks: Array[Dictionary], value: float) -> float:
	for tick: Dictionary in ticks:
		if is_equal_approx(tick["value"], value):
			return tick["offset"]
	return INF

static func _motion(t: T, host: Node) -> void:
	t.suite("ThirdPersonHUD / continuous instruments and wraparound")
	# Test the same absolute mark before/after motion, including a cell boundary.
	for sample: Array in [[19.0, 21.0, 20.0], [599.0, 601.0, 600.0], [-1.0, 1.0, 0.0]]:
		var before := _graduation(ThirdPerson.ruler_ticks(sample[0], 20, 21, 147), sample[2])
		var after := _graduation(ThirdPerson.ruler_ticks(sample[1], 20, 21, 147), sample[2])
		t.near(after - before, -2.1, 0.0001, "speed/altitude mark crosses index continuously")
	var north_before := _graduation(ThirdPerson.ruler_ticks(359, 2.5, 9, 324), 360)
	var north_after := _graduation(ThirdPerson.ruler_ticks(1, 2.5, 9, 324), 0)
	t.near(north_after - north_before, -7.2, 0.001, "north mark scrolls through 359 to 001 without a jump")
	for value in [0.0, 0.5, 59.99, 60.01, 700.0, -130.0]:
		var ticks := ThirdPerson.ruler_ticks(value, 20, 21, 147)
		t.ok(ticks.size() >= 13 and ticks.size() <= 15, "graduation density stays bounded")
		for tick: Dictionary in ticks:
			t.ok(absf(tick["offset"]) <= 147.0, "rolling ticks stay in their instrument")
	t.suite("ThirdPersonHUD / attitude, turn inertia and frame rate")
	var reference = null
	for hz in [30, 60, 144]:
		var motion := ThirdPerson.new()
		motion.tick_motion(Basis(), 1.0 / hz)
		for frame in hz:
			var b := Basis(Vector3.UP, deg_to_rad(30.0 * (frame + 1.0) / hz))
			b = b * Basis(Vector3.RIGHT, deg_to_rad(20)) * Basis(Vector3.BACK, deg_to_rad(25))
			motion.tick_motion(b, 1.0 / hz)
		t.ok(motion.pitch_offset > 30, "raising nose moves horizon wings down")
		t.ok(motion.bank > 0.15, "bank rotates reference with the world horizon in canvas coordinates")
		t.ok(motion.turn_offset > 6, "left turn adds bounded rightward inertia")
		if reference != null:
			t.near(motion.pitch_offset, reference.x, 0.001, "pitch response matches across frame rates")
			t.near(motion.turn_offset, reference.y, 0.01, "turn response matches across frame rates")
		reference = Vector2(motion.pitch_offset, motion.turn_offset)
		var unchanged := motion.frame_point(Vector2(800,450), Vector2(342,270))
		motion.tick_motion(Basis(), 0)
		t.eq(motion.frame_point(Vector2(800,450),Vector2(342,270)), unchanged, "zero delta does not corrupt state")
		for frame in hz:
			motion.tick_motion(Basis(), 1.0 / hz)
		t.ok(absf(motion.pitch_offset) < 0.01 and absf(motion.turn_offset) < 0.01, "motion settles after leveling off")
	var wrap := ThirdPerson.new()
	wrap.tick_motion(Basis(Vector3.UP, deg_to_rad(359)), 0.1)
	wrap.tick_motion(Basis(Vector3.UP, deg_to_rad(1)), 0.1)
	t.ok(wrap.turn_offset > 0 and wrap.turn_offset < 5, "heading wrap retains small correct turn direction")
	wrap.tick_motion(Basis(Vector3.RIGHT, PI / 2), 0.1)
	t.ok(absf(wrap.turn_offset) < 5, "vertical flight does not invent a turn")
	wrap.tick_motion(Basis(Vector3.UP,1),0.1,0)
	t.near(wrap.turn_offset,0,0.0001,"reduced motion disables decorative turn inertia")
	for frame in 60:
		wrap.tick_motion(Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.BACK, PI / 2), 1.0 / 60)
	t.ok(absf(wrap.pitch_offset) <= 52 and absf(wrap.bank) <= deg_to_rad(12), "extreme attitude respects visibility limits")
	for view: Vector2 in [Vector2(1280,960),Vector2(3440,1440),Vector2(1600,900)]:
		var g := ThirdPerson.layout(view)
		for x in [-388.0,388.0]:
			for y in [-270.0,270.0]:
				t.ok(Rect2(Vector2.ZERO,g["view"]).has_point(wrap.frame_point(g["center"],Vector2(x,y))), "moving rails remain inside viewport")
		for direction in [-1.0,1.0]:
			wrap.bank = deg_to_rad(12) * direction
			wrap.turn_offset = 18 * direction
			wrap.pitch_offset = 52 * direction
			for side in [-1.0,1.0]:
				var rail := wrap.corner_rail(g["center"],side,1,g["radar"],g["weapons"])
				var bounds := Rect2(rail[0],Vector2.ZERO).expand(rail[1]).grow(12)
				t.ok(not bounds.intersects(g["radar"]),"banked lower rails clear radar, including end caps")
				t.ok(not bounds.intersects(g["weapons"]),"banked lower rails clear weapon text")
	t.suite("ThirdPersonHUD / real HUD process and cockpit isolation")
	var saved := Settings.first_person
	Settings.first_person = false
	var stage := Node3D.new()
	host.add_child(stage)
	var p := PlayerController.new()
	p.profile = SuitProfile.xi()
	p.controls_enabled = false
	stage.add_child(p)
	p.set_physics_process(false)
	var hud := FlightHUD.new()
	stage.add_child(hud)
	hud.player = p
	hud.set_process(false)
	hud._process(0.1)
	var initial := hud._third_person_motion.frame_point(Vector2.ZERO,Vector2(184,0))
	p.basis = Basis(Vector3.RIGHT,deg_to_rad(20))
	hud._process(0.1)
	t.ok(hud._third_person_motion.frame_point(Vector2.ZERO,Vector2(184,0)).y > initial.y + 10, "real process moves geometry when attitude changes, even at same speed and altitude")
	Settings.first_person = true
	hud._process(0.1)
	t.near(hud._third_person_motion.pitch_offset,0,0.0001,"first-person resets third-person motion")
	t.ok(not hud.uses_third_person_hud(),"cockpit renderer still selected")
	Settings.first_person = false
	hud._process(0.1)
	t.ok(hud._third_person_motion.pitch_offset > 30,"returning to third-person initializes current attitude immediately")
	hud.player = null
	hud._process(0.1)
	t.near(hud._third_person_motion.pitch_offset,0,0.0001,"missing player clears stale motion")
	Settings.first_person = saved
	stage.free()
