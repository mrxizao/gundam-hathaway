extends Node3D
var count := 0
var failures := 0
var retained: Array[Resource] = []
func check(ok: bool,label: String) -> void:
	if ok:count += 1
	else:
		failures += 1
		push_error("FLASH_TEST_FAIL "+label)

func unit(suit: int,team_id: int,player := false) -> FlightBody:
	var body := PlayerController.new() if player else FlightBody.new()
	body.profile = SuitProfile.by_id(suit)
	body.team = team_id
	body.is_player = player
	body.projectile_container = self
	add_child(body)
	body.set_physics_process(false)
	body.set_process(false)
	body.invuln_until = -1
	return body

func _ready() -> void:
	Settings.begin_isolated()
	for file in DirAccess.get_files_at("res://shaders"):
		if file.ends_with(".gdshader"):retained.append(load("res://shaders/"+file))
	Game.reset()
	Game.phase = Game.Phase.FIGHT
	Game.active_map = MapDef.colony_ruins()
	check(not Game.active_map.ground_collision_damage,"Colony uses safe surface contact")
	var source := unit(SuitProfile.Id.FULL_ARMOR_TB,0,true)
	var victim := unit(SuitProfile.Id.PSYCHO_ZAKU_TB,1,true)
	var far := unit(SuitProfile.Id.PSYCHO_ZAKU_TB,1)
	var ally := unit(SuitProfile.Id.PSYCHO_ZAKU_TB,0)
	Game.player = source
	source.position = Vector3(-60,5000,0)
	victim.position = Vector3(0,5000,-4000)
	far.position = Vector3(0,5000,-4001)
	ally.position = Vector3(0,5000,200)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.add_to_group("avoidance_ground")
	wall.position = Vector3(0,5000,0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10,200,200)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	var hp := source.hp
	source.velocity = Vector3(6000,0,0)
	source.move_and_slide()
	check(source.get_slide_collision_count()>0,"Surface really collides")
	source._check_collisions()
	check(source.alive and source.hp == hp,"Actual structure collision causes no damage or explosion")
	check(source.position.x < 0,"Solid wall still stops movement")
	wall.queue_free()
	await get_tree().process_frame
	source.position = Vector3(0,5000,100)
	check(not source.profile.has_vulcan() and not source.fire_gun(true),"Full Armor no longer has a vulcan")
	check(victim.profile.has_vulcan(),"Psycho Zaku machinegun is retained")
	var systems = source.thunderbolt_systems
	Input.action_press("fire_gun")
	systems.input(1.0/60)
	check(systems.flash_armed() and systems.flash_cd==30,"First Space press launches one round and starts 30s CD")
	check(victim.flash_blind_left == 0,"Launching does not blind")
	var grenade: Node3D = systems.flash_projectile
	grenade.set_physics_process(false)
	for frame in 3:
		await get_tree().process_frame
		systems.input(1.0/60)
	check(systems.flash_projectile == grenade and victim.flash_blind_left==0,"Holding Space cannot trigger detonation")
	Input.action_release("fire_gun")
	await get_tree().process_frame
	grenade.position = Vector3(0,5000,0)
	var victim_hp := victim.hp
	var victim_shield := victim.ifield_hp
	Input.action_press("fire_gun")
	systems.input(1.0/60)
	Input.action_release("fire_gun")
	check(not systems.flash_armed(),"Second Space press detonates during cooldown")
	check(victim.flash_blind_left==3,"Enemy exactly 4km away is blind for 3s")
	check(far.flash_blind_left==0,"Enemy beyond 4km is unaffected")
	check(ally.flash_blind_left==0 and source.flash_blind_left==0,"Allies and shooter are not blinded")
	check(victim.hp==victim_hp and victim.ifield_hp==victim_shield,"Flash causes no hull or I-field damage")
	check(victim._flashbang_overlay.visible,"Victim's actual screen overlay is shown")
	check(victim._flashbang_overlay.white.color==Color.WHITE,"Overlay is solid white")
	check(not victim.weapons_locked(),"Blind player retains weapon and flight controls")
	victim._tick_weapons(2.99)
	victim._flashbang_overlay.refresh()
	check(victim.flash_blind_left>0 and victim._flashbang_overlay.visible,"Whiteout persists until 3 seconds")
	victim._tick_weapons(0.02)
	victim._flashbang_overlay.refresh()
	check(victim.flash_blind_left==0 and not victim._flashbang_overlay.visible,"Whiteout ends after 3 seconds")
	check(not systems.flash_press(),"Cooldown blocks a second grenade")
	systems.step(30)
	check(systems.flash_press(),"A new grenade becomes available after 30s")
	check(systems.flash_status().contains("待引爆"),"HUD reports armed state")
	systems.flash_projectile._physics_process(31.0)
	check(systems.flash_armed(),"Pending round persists until manual detonation after cooldown")
	check(systems.flash_press(),"Later second press still detonates the original round")
	var rows: Array = systems.hud_rows()
	check(str(rows).contains("闪光弹"),"Cockpit readout includes flashbang")
	victim.apply_flashbang(victim.position)
	Game.phase = Game.Phase.WIN
	victim._flashbang_overlay.refresh()
	check(not victim._flashbang_overlay.visible,"Whiteout cannot cover results")
	Game.phase = Game.Phase.FIGHT
	get_tree().paused = true
	victim._flashbang_overlay.refresh()
	check(not victim._flashbang_overlay.visible,"Whiteout cannot cover pause/settings")
	get_tree().paused = false
	var ai := BanditAI.new()
	ai.profile = SuitProfile.thunderbolt(true)
	ai.projectile_container = self
	ai.team = 1
	add_child(ai)
	ai.set_physics_process(false)
	ai.position = source.position+Vector3(0,0,-1000)
	ai.target_override = source
	ai.apply_flashbang(ai.position)
	ai._think(0.1)
	check(ai._target==null and ai.thunderbolt_systems.target()==null,"Blinded AI cannot retain perfect targeting")
	print("FLASHBANG PASS ",count," FAIL ",failures)
	for audio in get_tree().root.find_children("*","AudioStreamPlayer3D",true,false):audio.stop();audio.stream=null
	for audio in get_tree().root.find_children("*","AudioStreamPlayer",true,false):audio.stop();audio.stream=null
	for child in get_children():child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.12).timeout
	Settings.end_isolated()
	get_tree().quit(failures)
