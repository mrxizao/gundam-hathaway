extends RefCounted

class Pilot extends Node:
	var player: PlayerController
	var translating := true
	var command := Vector3.ZERO
	var lift := 0.0
	var activated := false
	var first_height := INF
	var min_height := INF
	var climbed := false
	var events := 0
	var last_active := false
	func _physics_process(delta: float) -> void:
		if not player.alive: return
		player.translate_mode = translating
		player.translate_dir = Vector3.UP * lift
		player.translate_fwd = Vector3.ZERO
		player.control_input = command
		player.fm.boosting = true
		player._tick_assist(delta)
		player._apply_flight(delta)
		if not player.alive:
			for i in player.get_slide_collision_count():
				var collision := player.get_slide_collision(i)
				var collider = collision.get_collider()
				print("[GUARD_CONTACT] at=",player.global_position," collider=",collider," path=",collider.get_path() if collider is Node else "", " normal=",collision.get_normal())
		var active: bool = player.assist_state()["collision_guard"]
		if active and not activated: first_height = player.global_position.y
		activated = activated or active
		climbed = climbed or (active and player.fm.velocity.y > 10)
		min_height = minf(min_height,player.global_position.y)
		if active != last_active: events += 1
		last_active = active

static func _box(stage: Node3D, pos: Vector3, extent: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = FlightBody.WORLD_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extent
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	stage.add_child(body)
	return body

static func _stage(host: Node, pos: Vector3, profile: SuitProfile = null) -> Dictionary:
	Game.reset()
	var stage := Node3D.new()
	host.add_child(stage)
	var p := PlayerController.new()
	p.profile = profile if profile != null else SuitProfile.xi()
	p.is_player = true
	p.projectile_container = stage
	p.controls_enabled = true
	p.assist_on = true
	stage.add_child(p)
	p.set_physics_process(false)
	p.global_position = pos
	p.fm.speed = 900
	p.fm.align_velocity(p.forward())
	var pilot := Pilot.new()
	pilot.player = p
	pilot.set_physics_process(false)
	stage.add_child(pilot)
	return {"stage":stage,"p":p,"pilot":pilot}

static func _simulate(host: Node, pilot: Pilot, seconds: float) -> void:
	pilot.set_physics_process(true)
	for i in int(Engine.physics_ticks_per_second * seconds):
		await host.get_tree().physics_frame
	pilot.set_physics_process(false)

static func run(t: T, host: Node) -> void:
	Settings.begin_isolated()
	var saved_hz := Engine.physics_ticks_per_second
	var saved_pad := InputSetup.using_gamepad
	t.suite("CollisionGuard / real dives, buildings, reverse and side boosts")
	for hz in [30,60,120]:
		Engine.physics_ticks_per_second = hz
		for pad in [false,true]:
			InputSetup.using_gamepad = pad
			var st := _stage(host,Vector3(0,3500,0))
			var p: PlayerController = st["p"]
			var pilot: Pilot = st["pilot"]
			_box(st["stage"],Vector3(0,-20,0),Vector3(60000,40,60000))
			var aim := Node3D.new()
			(st["stage"] as Node).add_child(aim)
			aim.global_position = p.global_position + Vector3(0,-26000,-40000)
			p.face_target_override = aim
			p.look_at(aim.global_position)
			p.fm.speed = p.profile.player_boost_speed()
			p.fm.align_velocity(p.forward())
			pilot.lift = -1 # Held descent must not defeat the new collision guard.
			await host.get_tree().physics_frame
			await _simulate(host,pilot,3.0)
			print("[GUARD_DIVE] hz=",hz," pad=",pad," min_y=",pilot.min_height," first_y=",pilot.first_height," alive=",p.alive)
			t.ok(p.alive,"high-speed held dive survives at %dHz pad=%s" % [hz,pad])
			t.ok(pilot.activated and pilot.climbed,"predictive guard activates and actually climbs")
			t.ok(pilot.first_height > 50,"intervention is predictive, above the old 50m last-second gate")
			t.ok(pilot.min_height > FlightBody.CRASH_ALTITUDE + 20,"keeps physical clearance from the death plane")
			t.eq(p.face_target_override,aim,"flight override does not erase selected target")
			(st["stage"] as Node).free()
			await host.get_tree().physics_frame
	Engine.physics_ticks_per_second = 60
	for scenario in ["tower","roof","reverse","side_boost","flight","boxed"]:
		var profile := SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE) if scenario == "flight" else SuitProfile.xi()
		var st := _stage(host,Vector3(0,400,0),profile)
		var p: PlayerController = st["p"]
		var pilot: Pilot = st["pilot"]
		_box(st["stage"],Vector3(0,-20,0),Vector3(60000,40,60000))
		var obstacle := Vector3(0,1000,-1000)
		if scenario == "reverse":
			p.translate_reverse = true
			p.fm.velocity = Vector3.BACK * 900
			obstacle.z = 1000
		if scenario == "side_boost":
			p.translate_dir = Vector3.RIGHT
			p.request_quick_boost()
			p._qb_timer = 0.4
			p._qb_dir = Vector3.RIGHT
			p.fm.velocity = Vector3.RIGHT * 2000
			obstacle = Vector3(1000,1000,0)
		pilot.translating = scenario != "flight"
		if scenario == "roof" or scenario == "boxed":
			_box(st["stage"],Vector3(0,550,0),Vector3(10000,40,10000))
		if scenario == "boxed":
			_box(st["stage"],Vector3(-65,500,0),Vector3(40,1000,10000))
			_box(st["stage"],Vector3(65,500,0),Vector3(40,1000,10000))
			obstacle.z = -350
		_box(st["stage"],obstacle,Vector3(600,2000,100) if scenario != "side_boost" else Vector3(100,2000,600))
		var before_hp := p.hp
		await host.get_tree().physics_frame
		await _simulate(host,pilot,4.0)
		print("[GUARD_OBSTACLE] ",scenario," pos=",p.global_position," alive=",p.alive," events=",pilot.events," hp=",p.hp)
		t.ok(pilot.activated,"actual velocity detects obstacle: "+scenario)
		t.ok(p.alive,"auto avoidance survives: "+scenario)
		t.near(p.hp,before_hp,0.001,"avoidance prevents physical collision damage: "+scenario)
		t.ok(pilot.events <= 8,"entry/exit hysteresis avoids per-frame flicker: "+scenario)
		if scenario == "roof": t.ok(absf(p.global_position.x) > 320,"blocked ascent chooses a side route")
		if scenario == "boxed":
			t.ok(p.global_position.z + 300 > p._collision_guard.radius - 0.1,"boxed-in flight retains swept-hull clearance before front wall")
			t.ok(p.fm.speed < 5,"boxed-in flight comes to a controlled stop")
		if scenario == "side_boost": t.ok(not p.translate_dash,"danger cancels quick boost into wall")
		(st["stage"] as Node).free()
		await host.get_tree().physics_frame
	t.suite("CollisionGuard / manual, disabled controls, clear flight and release")
	var st := _stage(host,Vector3(0,2000,0))
	var p: PlayerController = st["p"]
	await host.get_tree().physics_frame
	var original := Vector3(20,-300,-900)
	p.fm.velocity = original
	p.assist_on = false
	p._before_flight_move(0.1)
	t.eq(p.fm.velocity,original,"manual flight vector stays exactly unchanged")
	p.assist_on = true
	p.controls_enabled = false
	p._before_flight_move(0.1)
	t.eq(p.fm.velocity,original,"launch/disabled controls do not get guarded")
	p.controls_enabled = true
	p.fm.velocity = Vector3.FORWARD * 900
	p._before_flight_move(0.1)
	t.eq(p.fm.velocity,Vector3.FORWARD * 900,"clear high flight has no correction")
	t.ok(not p.assist_state()["collision_guard"],"clear flight keeps normal control")
	# Ocean without collider still has a death plane; orbit explicitly does not.
	p.global_position.y = 100
	var guard = p._collision_guard
	guard.solve(p,Vector3.DOWN*500,0.1,false,FlightBody.CRASH_ALTITUDE)
	t.ok(not guard.active,"orbit has no invented y=0 ground")
	guard.solve(p,Vector3.DOWN*500,0.1,true,FlightBody.CRASH_ALTITUDE)
	t.ok(guard.active and guard.kind == "ground","ocean death plane is guarded without a collider")
	for i in 8: guard.solve(p,Vector3.UP*500,0.1,true,FlightBody.CRASH_ALTITUDE)
	t.ok(not guard.active,"clear climb returns control after stable safe interval")
	var other := FlightBody.new()
	other.profile = SuitProfile.messer_m01()
	(st["stage"] as Node).add_child(other)
	other.set_physics_process(false)
	other.global_position = p.global_position + Vector3(0,0,-100)
	await host.get_tree().physics_frame
	guard.solve(p,Vector3.FORWARD*900,0.1,false,FlightBody.CRASH_ALTITUDE)
	t.ok(not guard.active,"unit layer does not trigger building avoidance")
	var ai_velocity := Vector3(10,-100,-500)
	other.fm.velocity = ai_velocity
	other._before_flight_move(0.1)
	t.eq(other.fm.velocity,ai_velocity,"AI default movement hook stays unchanged")
	_box(st["stage"],Vector3.ZERO,Vector3(2000,40,2000))
	await host.get_tree().physics_frame
	guard.solve(p,Vector3.DOWN*500,0.1,false,FlightBody.CRASH_ALTITUDE)
	t.ok(guard.active and guard.kind == "building","real orbital platforms trigger obstacle avoidance, not invented ground")
	(st["stage"] as Node).free()
	await host.get_tree().physics_frame
	t.suite("CollisionGuard / manual collision remains physical")
	st = _stage(host,Vector3(0,400,0),SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE))
	p = st["p"]
	p.assist_on = false
	var pilot: Pilot = st["pilot"]
	pilot.translating = false
	_box(st["stage"],Vector3(0,1000,-700),Vector3(600,2000,100))
	await host.get_tree().physics_frame
	await _simulate(host,pilot,2)
	t.ok(not p.alive,"same physical wall still destroys manual flight with assist off")
	t.ok(not pilot.activated,"manual flight never silently activates guard")
	(st["stage"] as Node).free()
	await host.get_tree().physics_frame
	InputSetup.using_gamepad = saved_pad
	Engine.physics_ticks_per_second = saved_hz
	Settings.end_isolated()
	Game.reset()
