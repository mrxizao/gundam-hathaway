extends Node3D
func _ready() -> void:
	var shots := Node3D.new()
	add_child(shots)
	var defender := FlightBody.new()
	defender.profile=SuitProfile.xi()
	defender.team=0
	defender.projectile_container=shots
	defender.position=Vector3(0,300,0)
	add_child(defender)
	defender.set_physics_process(false)
	var attacker := FlightBody.new()
	attacker.profile=SuitProfile.xi()
	attacker.team=1
	attacker.projectile_container=shots
	attacker.position=Vector3(0,300,-120)
	add_child(attacker)
	attacker.set_physics_process(false)
	assert(defender.model_anim!=null and defender.model_anim.ready)
	assert(defender.play_model_action("slash"))
	defender.saber_state=FlightBody.SaberState.CHARGE
	defender.fm.speed=1000
	defender.fm.velocity=Vector3(0,0,-1000)
	defender.velocity=defender.fm.velocity
	attacker._slash(defender)
	assert(defender.melee_hit_reaction.elapsed==0)
	assert(not defender.saber_active())
	assert(defender.model_fsm.state!=ModelAnimFSM.State.ACTION or defender.model_fsm._action!="slash")
	assert(defender.fire_gun(true,attacker))
	assert(defender.fire_beam(true,attacker))
	assert(defender.model_fsm._action=="shoot")
	for n in 6:
		defender._tick_effects(1.0/60.0)
		await get_tree().process_frame
	assert(defender.spin_pivot.rotation_degrees.length()>3)
	assert(is_equal_approx(defender.velocity.length(),100))
	if "--visual" in OS.get_cmdline_user_args():
		var env := WorldEnvironment.new()
		env.environment=Environment.new()
		env.environment.background_mode=Environment.BG_COLOR
		env.environment.background_color=Color(0.07,0.09,0.13)
		env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_energy=0.8
		add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees=Vector3(-40,-30,0)
		add_child(sun)
		var camera := Camera3D.new()
		attacker.set_model_visible(false)
		camera.position=Vector3(35,325,-40)
		add_child(camera)
		camera.look_at(defender.position+Vector3.UP*15)
		camera.current=true
		await get_tree().create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/melee_hit_combat.png")
	for n in 65:
		defender._tick_effects(1.0/60.0)
		await get_tree().process_frame
	assert(defender.melee_hit_reaction.angles.length()<0.001)
	assert(defender.spin_pivot.rotation_degrees.length()<0.001)
	# Actual shield action must replace the old pose and block the following real slash.
	defender.melee_guard.tick(defender,4.1)
	defender.shield_up=false
	defender.shield_cooldown=0
	attacker.saber_state=FlightBody.SaberState.CHARGE
	attacker.saber_timer=1.0
	attacker._melee_attack_serial+=1
	defender.melee_guard.warn(defender,attacker)
	defender.melee_guard.elapsed=0.25
	assert(defender.raise_shield())
	assert(defender.model_fsm._action=="shield")
	var before_hp := defender.hp
	var before_field := defender.ifield_hp
	attacker._slash(defender)
	assert(defender.hp==before_hp and defender.ifield_hp==before_field)
	assert(defender.melee_guard.result=="举盾防御成功")
	assert(defender.melee_guard.impact_left==0)
	print("MELEE COMBAT BLEND PASS actual Xi rig: slash interruption, gun/rifle, flinch, recovery")
	get_tree().quit()
