extends RefCounted

static func run(t: T, host: Node) -> void:
	t.suite("HardAISkills / gates, actual dash, cannon and salvo")
	var stage := Node3D.new()
	host.add_child(stage)
	var ai := BanditAI.new()
	ai.profile = SuitProfile.penelope()
	ai.difficulty = Difficulty.make(Difficulty.Level.HARD)
	ai.projectile_container = stage
	ai.position = Vector3(0, 4000, 0)
	stage.add_child(ai)
	ai.set_physics_process(false)
	var target := FlightBody.new()
	target.profile = SuitProfile.xi()
	target.team = 0
	target.position = Vector3(0, 4000, -1600)
	target.projectile_container = stage
	stage.add_child(target)
	target.set_physics_process(false)
	ai._target = target
	ai._lag_pos = target.global_position
	ai.lock = LockOnSystem.new()
	ai.add_child(ai.lock)
	ai.lock.setup(ai)
	ai.lock.set_physics_process(false)
	ai.lock.target = target
	ai.lock.force_lock()
	await host.get_tree().physics_frame
	t.ok(ai._hard_skills_enabled(), "hard enemy skill gate")
	for level in [Difficulty.Level.EASY, Difficulty.Level.NORMAL]:
		ai.difficulty = Difficulty.make(level)
		t.ok(not ai._start_hard_dash(Vector3.FORWARD), "ordinary difficulty cannot dash")
		ai.hp = ai.max_hp * 0.49
		t.ok(not ai._start_hard_salvo(target), "ordinary difficulty cannot salvo")
	ai.difficulty = Difficulty.make(Difficulty.Level.HARD)
	ai.team = 0
	t.ok(not ai._start_hard_dash(Vector3.FORWARD), "friendly hard AI unchanged")
	t.ok(not ai._start_hard_salvo(target), "friendly hard AI cannot salvo")
	ai.team = 1
	ai.scripted = true
	t.ok(not ai._start_hard_dash(Vector3.FORWARD), "cutscene gate")
	ai.scripted = false
	t.ok(ai._start_hard_dash(Vector3.FORWARD), "actual dash begins")
	t.ok(ai.assist_dashing(), "dash effects gate")
	t.ok(ai._before_flight_move(1.0 / 60.0), "normal aerodynamic movement consumes dash")
	t.near(ai.fm.velocity.length(), ai.profile.player_boost_speed() * ai.QB_SPEED_MULT, 0.01, "dash really changes speed")
	t.ok(ai._dash_anim_dir != "", "dash animation connected")
	var initial_position := ai.global_position
	ai._apply_flight(1.0 / 60.0)
	t.ok(ai.global_position.distance_to(initial_position) > 10.0, "dash actually moves the body through physics")
	t.ok(not ai._start_hard_dash(Vector3.RIGHT), "dash cooldown cannot retrigger")
	ai._tick_hard_skills(0.45)
	t.ok(not ai.assist_dashing(), "dash window ends")
	ai._tick_hard_skills(4.54)
	t.ok(not ai._start_hard_dash(Vector3.FORWARD), "5 sec cooldown not early")
	ai._tick_hard_skills(0.02)
	t.ok(ai._start_hard_dash(Vector3.RIGHT), "5 sec cooldown permits next dash")
	ai._hard_dash_left = 0.0
	ai.hp = ai.max_hp
	ai.state = BanditAI.State.ATTACK
	var before := stage.get_child_count()
	ai._drive_hard_skills(1600, 0)
	t.near(ai._hard_cannon_cd, 40.0, 0.001, "cannon 40 sec cooldown starts on success")
	t.ok(is_instance_valid(ai.active_cannon), "real beam cannon spawned")
	t.ok(stage.get_child_count() > before, "cannon exists in projectile world")
	ai.cannon_cd_left = 0.0
	ai.rifle_reloading = false
	ai.rifle_mag = ai.profile.rifle_magazine
	before = stage.get_child_count()
	ai._tick_hard_skills(39.99)
	ai._drive_hard_skills(1600, 0)
	t.eq(stage.get_child_count(), before, "native cooldown reset cannot bypass AI 40 sec")
	ai._tick_hard_skills(0.02)
	ai._drive_hard_skills(1600, 0)
	t.ok(stage.get_child_count() > before, "cannon available after 40 sec")
	ai._hard_cannon_cd = 0.0
	ai.cannon_cd_left = 0.0
	ai.rifle_reloading = false
	ai.profile.cannon_enabled = false
	before = stage.get_child_count()
	ai._drive_hard_skills(1600, 0)
	t.eq(stage.get_child_count(), before, "unsupported cannon not granted to a suit")
	t.near(ai._hard_cannon_cd, 0.0, 0.001, "unavailable cannon consumes no AI cooldown")
	ai.profile.cannon_enabled = true
	ai.hp = ai.max_hp * 0.5
	var ammo := ai.funnel_count
	t.ok(not ai._start_hard_salvo(target), "exact half HP does not qualify")
	t.eq(ai.funnel_count, ammo, "failed salvo costs no ammo")
	ai.hp = ai.max_hp * 0.49
	ai.funnel_count = 99
	t.ok(not ai._start_hard_salvo(target), "100 missiles required")
	t.near(ai._hard_salvo_cd, 0.0, 0.001, "failed salvo consumes no cooldown")
	ai.funnel_count = 150
	ai.profile.has_missiles = false
	t.ok(not ai._start_hard_salvo(target), "missileless form cannot salvo")
	ai.profile.has_missiles = true
	t.ok(ai._start_hard_salvo(target), "below half starts full salvo")
	t.eq(ai.funnel_count, 50, "salvo consumes exactly 100 rounds")
	t.near(ai._hard_salvo_cd, 190.0, 0.001, "salvo 190 sec cooldown")
	before = stage.get_child_count()
	for i in 120:
		ai._tick_hard_skills(1.0 / 120.0)
	t.eq(stage.get_child_count() - before, 100, "full salvo emits 100 real missiles")
	t.eq(ai._hard_salvo_left, 0, "salvo sequence completes")
	ai.funnel_count = 150
	t.ok(not ai._start_hard_salvo(target), "salvo cannot repeat during cooldown")
	ai._tick_hard_skills(188.99)
	t.ok(not ai._start_hard_salvo(target), "190 sec cooldown not early")
	ai._tick_hard_skills(0.02)
	t.ok(ai._start_hard_salvo(target), "salvo eligible after 190 sec")
	ai.set_scripted(true)
	ai._tick_hard_skills(0.1)
	t.eq(ai._hard_salvo_left, 0, "cutscene cancels pending missiles")
	ai.set_scripted(false)
	ai._hard_salvo_cd = 0.0
	for hz in [30, 60, 120]:
		ai._hard_salvo_roll = 5.0
		for i in hz * 4:
			ai._tick_hard_skills(1.0 / float(hz))
		t.near(ai._hard_salvo_roll, 1.0, 0.001, "roll timing independent of FPS")
		for i in hz + 1:
			ai._tick_hard_skills(1.0 / float(hz))
		t.near(ai._hard_salvo_roll, 0.0, 0.001, "one roll becomes due at 5 sec")
	# Seeded trials: meaningful negative check that low HP does not guarantee a salvo.
	ai._hard_rng.seed = 4721
	var triggers := 0
	for i in 1000:
		ai._hard_salvo_cd = 0.0
		ai._hard_salvo_left = 0
		ai._hard_salvo_roll = 0.0
		ai.funnel_count = 150
		ai.funnel_reload_left = 0.0
		ai._drive_hard_skills(1600, 0)
		if ai._hard_salvo_left > 0:
			triggers += 1
	t.ok(triggers > 45 and triggers < 115, "low probability observed across seeded trials: %d/1000" % triggers)
	ai._hard_salvo_left = 0
	ai._hard_dash_cd = 0.0
	ai.position.y = 600
	t.ok(not ai._start_hard_dash(Vector3.DOWN), "unsafe ground dash rejected")
	t.near(ai._hard_dash_cd, 0.0, 0.001, "unsafe dash consumes no cooldown")
	ai.position = Vector3(0,4000,0)
	var wall := StaticBody3D.new()
	wall.collision_layer = FlightBody.WORLD_LAYER
	wall.position = Vector3(0,4000,-100)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000,1000,40)
	cs.shape = box
	wall.add_child(cs)
	stage.add_child(wall)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	print("[HARD_DASH_WALL] ai=",ai.global_position," wall=",wall.global_position," clear=",ai._hard_dash_clear(Vector3.FORWARD))
	t.ok(not ai._start_hard_dash(Vector3.FORWARD), "building sweep blocks unsafe dash")
	stage.queue_free()
	await host.get_tree().process_frame

