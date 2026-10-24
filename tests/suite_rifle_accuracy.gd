extends RefCounted
const Solver = preload("res://scripts/combat/rifle_aim_solution.gd")
const Recorder = preload("res://scripts/combat/rifle_accuracy.gd")

static func run(t: T, host: Node) -> void:
	t.suite("RifleAccuracy / independent projectile accounting")
	_statistics(t)
	t.suite("RifleAccuracy / camera ray and profile solution")
	await _geometry(t, host)
	t.suite("RifleAccuracy / intent, pad, visibility and missile lock")
	await _candidates(t, host)
	t.suite("RifleAccuracy / actual muzzle projectiles and damage")
	await _shots(t, host)
	t.suite("RifleAccuracy / moving targets, input and physics rates")
	await _moving(t, host)
	t.suite("RifleAccuracy / two-stage integration timing")
	await _timing(t, host)

class MovingTarget extends Node:
	var unit: FlightBody
	func _physics_process(delta: float) -> void:
		if is_instance_valid(unit):
			unit.global_position += unit.fm.velocity * delta

static func _moving(t: T, host: Node) -> void:
	Settings.begin_isolated()
	Settings.first_person = false
	var saved_pad := InputSetup.using_gamepad
	var saved_hz := Engine.physics_ticks_per_second
	for hz in [30, 60, 120]:
		Engine.physics_ticks_per_second = hz
		for steady in [false, true]:
			for pad in [false, true]:
				InputSetup.using_gamepad = pad
				var stage := _stage(host)
				var p := _player(stage, steady)
				# Using a real camera tests screen-edge rays and camera/muzzle parallax.
				var cam := Camera3D.new()
				stage.add_child(cam)
				cam.global_position = p.global_position + Vector3(25, 15, 70)
				cam.make_current()
				var foe := _foe(stage, p.global_position + Vector3(0, 0, -2000))
				await host.get_tree().physics_frame
				if not pad:
					p.cursor_seen = true
					p.aim_cursor = cam.unproject_position(foe.global_position)
				foe.fm.velocity = Vector3(300, 0, 0)
				p._tick_rifle_aim(0.2)
				var mover := MovingTarget.new()
				mover.unit = foe
				mover.process_physics_priority = -10
				stage.add_child(mover)
				var before := foe.hp
				t.ok(p.fire_beam(true), "moving target shot fires")
				var recorder = Game.rifle_stats
				for frame in int(hz * 0.6):
					await host.get_tree().physics_frame
					if recorder.pending.is_empty(): break
				print("[RIFLE_MOVING] hz=", hz, " steady=", steady, " pad=", pad,
					" hits=", recorder.effective_hits, "/", recorder.shots)
				t.lt(foe.hp, before, "real 300m/s transverse target: %.0fHz steady=%s pad=%s" % [hz, steady, pad])
				t.eq(recorder.effective_hits, recorder.shots, "moving twin/single projectiles independently hit")
				stage.free()
				await host.get_tree().physics_frame
	Engine.physics_ticks_per_second = saved_hz
	InputSetup.using_gamepad = saved_pad
	Settings.end_isolated()

static func _statistics(t: T) -> void:
	var r = Recorder.new()
	var trigger: int = r.begin_trigger()
	var a: int = r.emitted(trigger, {"input": "keyboard_mouse"})
	var b: int = r.emitted(trigger, {"input": "keyboard_mouse"})
	r.settle(a, "effective_hit", 0.0, 10.0, true, true)
	r.settle(a, "effective_hit", 99.0, 0.0, true, true)
	t.eq(r.effective_hits, 1, "duplicate settlement contributes once")
	t.eq(r.pending.size(), 1, "unresolved twin remains in denominator")
	t.near(r.accuracy(), 0.5, 0.00001, "one twin hit counts 1/2")
	r.settle(b, "effective_hit", 5.0, 0.0, true, true)
	t.eq(r.trigger_hits, 1, "two pellets, one successful trigger")
	for outcome in ["expired", "terrain", "friendly", "missile_intercept", "zero_effect", "scene_exit"]:
		var id: int = r.emitted(r.begin_trigger(), {"input": "gamepad"})
		r.settle(id, outcome, 0.0, 0.0, outcome == "zero_effect", true)
	t.eq(r.shots, 8, "all emitted misses kept")
	t.near(r.accuracy("keyboard_mouse"), 1.0, 0.00001, "separate mouse result")
	t.near(r.accuracy("gamepad"), 0.0, 0.00001, "pad cannot borrow mouse hits")
	t.eq(r.contacts, 3, "zero-effect contact is separate")
	t.eq(r.groups.size(), 0, "settled trigger state is released")
	var cohort: Dictionary = r.cohorts["keyboard_mouse|first_person|assist_off|unknown"]
	t.eq(cohort["shots"], 2, "view and assist groups keep their own denominator")
	t.eq(cohort["effective_hits"], 2, "cohort hits match actual settlement")
	t.eq(cohort["pending"], 0, "cohort pending settles too")
	var next = Recorder.new()
	var old_id: int = r.emitted(r.begin_trigger(), {"input": "script"})
	r.settle(old_id, "scene_exit")
	t.eq(next.shots, 0, "old round cannot change fresh recorder")
	t.ok(r.report()["pending_projectiles"].is_empty(), "report exposes pending records")

static func _stage(host: Node) -> Node3D:
	Game.reset()
	var stage := Node3D.new()
	host.add_child(stage)
	return stage

static func _player(stage: Node3D, steady := false) -> PlayerController:
	var p := PlayerController.new()
	p.profile = SuitProfile.arizeus() if steady else SuitProfile.xi()
	p.is_player = true
	p.team = 0
	p.controls_enabled = false
	p.projectile_container = stage
	stage.add_child(p)
	p.global_position = Vector3(0, 3000, 0)
	p.set_physics_process(false)
	p.assist_on = true
	return p

static func _foe(stage: Node3D, pos: Vector3) -> FlightBody:
	var f := FlightBody.new()
	f.profile = SuitProfile.xi()
	f.team = 1
	stage.add_child(f)
	f.global_position = pos
	f.set_physics_process(false)
	f.hp = 10000.0
	f.ifield_hp = 0.0
	return f

static func _geometry(t: T, host: Node) -> void:
	var stage := _stage(host)
	var p := _player(stage)
	var f := _foe(stage, Vector3(0, 3000, -2000))
	f.fm.velocity = Vector3(300, 0, 0)
	var origin := p._rifle_origin()
	var ray_origin := p.global_position + Vector3(35, 30, 100)
	for steady in [0.0, 10900.0]:
		var s: Dictionary = Solver.solve(origin, ray_origin, Vector3.FORWARD, f, steady, true)
		var expected := Ballistics.beam_lead_point(origin, f.global_position, f.fm.velocity, steady)
		t.near(s["prediction"].distance_to(expected), 0.0, 0.001, "same real muzzle and speed model")
		t.near(s["flight_time"], SuitProfile.rifle_flight_time(origin.distance_to(s["aim_point"]), steady), 0.00001, "display uses projectile duration")
		var raw: Vector3 = s["raw_point"]
		t.near(raw.x, ray_origin.x, 0.001, "camera ray origin preserved horizontally")
		t.near(raw.y, ray_origin.y, 0.001, "camera ray origin preserved vertically")
	var no_target: Dictionary = Solver.solve(origin, ray_origin, Vector3.FORWARD, null, 0, true)
	t.not_ok(no_target["valid"], "no target is explicit, no origin prediction")
	t.near(no_target["weight"], 0.0, 0.00001, "no target gives no assistance")
	var off: Dictionary = Solver.solve(origin, ray_origin, Vector3.FORWARD, f, 0, false)
	t.eq(off["aim_point"], off["raw_point"], "assistance off preserves raw ray convergence")
	stage.free()
	await host.get_tree().physics_frame

static func _candidates(t: T, host: Node) -> void:
	Settings.begin_isolated()
	Settings.first_person = false
	var saved_pad := InputSetup.using_gamepad
	var stage := _stage(host)
	var p := _player(stage)
	p.controls_enabled = true
	p._rifle_input_active = false
	t.eq(p.rifle_shot_metadata()["input"], "script", "direct API firing is not a human sample")
	p._rifle_input_active = true
	Game.rifle_metrics_test_mode = false
	InputSetup.using_gamepad = false
	t.eq(p.rifle_shot_metadata()["input"], "keyboard_mouse", "real mouse input context is labeled")
	InputSetup.using_gamepad = true
	t.eq(p.rifle_shot_metadata()["input"], "gamepad", "real pad input context is labeled")
	Game.rifle_metrics_test_mode = true
	t.eq(p.rifle_shot_metadata()["input"], "script", "test injected input also excluded from human samples")
	p._rifle_input_active = false
	p.controls_enabled = false
	var a := _foe(stage, p.global_position + Vector3(500, 0, -1000))
	var b := _foe(stage, p.global_position + Vector3(10, 0, -1000))
	var lock := LockOnSystem.new()
	lock.unit = p
	stage.add_child(lock)
	lock.set_process(false)
	lock.set_physics_process(false)
	p.lock = lock
	lock.target = a
	await host.get_tree().physics_frame
	for pad in [false, true]:
		InputSetup.using_gamepad = pad
		p._rifle_candidate = null
		p._rifle_pending = null
		for i in 8:
			p._tick_rifle_aim(1.0 / 60.0)
		t.eq(p._rifle_candidate, b, "nearby intended target selected for both devices")
		t.eq(lock.target, a, "rifle candidate never replaces missile target")
		t.gt(p.rifle_hud_solution().get("weight", 0), 0.9, "same preview available even without cursor")
	p._rifle_candidate = null
	p._rifle_pending = null
	b.global_position = p.global_position + Vector3(20, 0, -1000)
	p._tick_rifle_aim(0.01)
	t.eq(p._rifle_candidate, null, "noncentral contact waits for stability")
	var wall := StaticBody3D.new()
	wall.collision_layer = FlightBody.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 200, 10)
	shape.shape = box
	wall.add_child(shape)
	stage.add_child(wall)
	wall.global_position = p.global_position + Vector3(0, 0, -500)
	await host.get_tree().physics_frame
	for i in 12:
		p._tick_rifle_aim(1.0 / 60.0)
	t.eq(p._rifle_candidate, null, "wall releases candidate immediately")
	wall.free()
	await host.get_tree().physics_frame
	lock.target = b
	p._tick_rifle_aim(0.016)
	t.eq(p._rifle_candidate, b, "explicit nearby selection available immediately")
	b.alive = false
	p._tick_rifle_aim(0.016)
	t.eq(p._rifle_candidate, null, "dead target released")
	Settings.first_person = true
	t.ok(p.rifle_hud_solution().is_empty(), "new UI disabled in first person")
	stage.free()
	InputSetup.using_gamepad = saved_pad
	Settings.end_isolated()
	await host.get_tree().physics_frame

static func _shots(t: T, host: Node) -> void:
	Settings.begin_isolated()
	Settings.first_person = false
	var saved_pad := InputSetup.using_gamepad
	InputSetup.using_gamepad = true
	for steady in [false, true]:
		for distance in [600.0, 1200.0, 2000.0, 3000.0]:
			var stage := _stage(host)
			var p := _player(stage, steady)
			var foe := _foe(stage, p.global_position + Vector3(0, 0, -distance))
			await host.get_tree().physics_frame
			p._tick_rifle_aim(0.2)
			var before := foe.hp
			t.ok(p.fire_beam(true), "real normal rifle emits")
			var count := 0
			for child in stage.get_children():
				if child is Projectile:
					count += 1
					var expected: Dictionary = p.rifle_solution(child.global_position)
					t.near(child.direction.angle_to((expected["aim_point"] - child.global_position).normalized()), 0.0, 0.001, "muzzle direction equals common solution")
			t.eq(Game.rifle_stats.shots, count, "actual pellets equal statistical denominator")
			for i in 55:
				await host.get_tree().physics_frame
				if Game.rifle_stats.pending.is_empty():
					break
			t.lt(foe.hp, before, "actual swept projectile damages stationary foe at %.0fm" % distance)
			t.eq(Game.rifle_stats.effective_hits, count, "all real pellets independently settle")
			stage.free()
			await host.get_tree().physics_frame
	# Actual friendly / invincible / I-FIELD outcomes use the collision path.
	for mode in ["friendly", "invincible", "ifield", "scene_exit"]:
		var stage := _stage(host)
		var p := _player(stage)
		p.assist_on = false
		var foe := _foe(stage, p.global_position + Vector3(0, 0, -600))
		if mode == "friendly": foe.team = 0
		if mode == "invincible": foe.invincible = true
		if mode == "ifield": foe.ifield_hp = 1000
		await host.get_tree().physics_frame
		p.fire_beam(true, foe)
		var recorder = Game.rifle_stats
		if mode != "scene_exit":
			for i in 40:
				await host.get_tree().physics_frame
				if recorder.pending.is_empty(): break
		stage.free()
		await host.get_tree().physics_frame
		t.eq(recorder.effective_hits, 1 if mode == "ifield" else 0, "actual %s classification" % mode)
		t.eq(recorder.pending.size(), 0, "cleanup settles %s" % mode)
	InputSetup.using_gamepad = saved_pad
	Settings.end_isolated()

static func _timing(t: T, host: Node) -> void:
	var stage := _stage(host)
	for hz in [30.0, 60.0, 120.0]:
		var bolt := Projectile.beam(stage, Vector3(0, 5000, 0), Vector3.FORWARD, null, 1, Color.WHITE, 2000)
		bolt.set_physics_process(false)
		var elapsed := 0.0
		var dt: float = 1.0 / hz
		# Stop just before the analytic intercept, then advance the fractional step.
		var intercept_time := SuitProfile.rifle_flight_time(2000)
		while elapsed + dt < intercept_time:
			bolt._physics_process(dt)
			elapsed += dt
		bolt._physics_process(intercept_time - elapsed)
		print("[RIFLE_TIMING] hz=", hz, " analytic_distance=2000 actual=", bolt.travelled)
		t.near(bolt.travelled, 2000, 0.1, "two-stage travel matches prediction at %.0fHz" % hz)
		bolt.free()
	stage.free()
	await host.get_tree().physics_frame
