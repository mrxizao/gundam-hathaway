extends RefCounted
static func pad(pressed:bool)->void:
	var event:=InputEventJoypadButton.new()
	event.device=0;event.button_index=JOY_BUTTON_DPAD_UP;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
static func key(code:Key,pressed:bool)->void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset()
	var old_placeholder:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	var old_device:=InputSetup.using_gamepad
	var stage:=Node3D.new();host.add_child(stage)
	var player:=PlayerController.new();player.profile=SuitProfile.xi();player.team=0;player.is_player=true
	stage.add_child(player);player.set_physics_process(false);player.position=Vector3(0,5000,0)
	var lock:=LockOnSystem.new();stage.add_child(lock);lock.setup(player);lock.set_physics_process(false)
	lock.auto_engage_limit=0;player.lock=lock
	var enemies:Array[FlightBody]=[]
	for offset in [Vector3(0,0,-1000),Vector3(1400,0,0),Vector3(0,0,1800)]:
		var foe:=FlightBody.new();foe.profile=SuitProfile.xi();foe.team=1
		stage.add_child(foe);foe.set_physics_process(false);foe.position=player.position+offset;enemies.append(foe)
	player._refresh_contacts()
	t.suite("PadTarget / real D-pad and keypad input use the same contact selection")
	t.eq(player.contacts(),enemies,"test contacts have a stable list order, including side/rear targets")
	lock.select_target(enemies[0]);lock.force_lock()
	lock._set_main_in_group(enemies[0]);lock.lock_group.append(enemies[2])
	# Neither the candidate list nor the old two-member group includes list #2.
	lock.candidates.assign([enemies[0],enemies[2]])
	pad(true)
	t.ok(Input.is_action_just_pressed("switch_target"),"physical D-pad Up reaches its mapped action")
	t.ok(InputSetup.using_gamepad,"actual pad event selects the gamepad input route")
	player._tick_contacts();player._read_weapon_input(1.0/60.0)
	t.eq(lock.target,enemies[1],"Up chooses next list contact even outside the front cone and old group")
	t.eq(lock.lock_group.size(),1,"group-external selection resets the group exactly like the keypad")
	t.near(lock.quality,0,.0001,"new target starts native lock acquisition")
	pad(false);await host.get_tree().process_frame
	lock.select_target(enemies[0]);lock.force_lock();lock.lock_group.append(enemies[2])
	key(KEY_KP_2,true);player._tick_contacts()
	t.eq(lock.target,enemies[1],"physical keypad 2 chooses exactly the same enemy as D-pad Up")
	t.eq(lock.lock_group.size(),1,"keypad and pad have the same group behavior")
	key(KEY_KP_2,false);await host.get_tree().process_frame
	pad(true);player._tick_contacts();player._read_weapon_input(1.0/60.0)
	t.eq(lock.target,enemies[2],"second Up press advances to a rear target")
	pad(false);await host.get_tree().process_frame
	pad(true);player._tick_contacts();player._read_weapon_input(1.0/60.0)
	t.eq(lock.target,enemies[0],"Up wraps from last contact back to first")
	pad(false);await host.get_tree().process_frame
	player.melee_guard.impact_left=1.0
	pad(true);player._tick_contacts();player._read_weapon_input(1.0/60.0)
	t.eq(lock.target,enemies[1],"Up still selects contacts during weapon stun, exactly like numeric keys")
	await host.get_tree().process_frame
	player._tick_contacts()
	t.eq(lock.target,enemies[1],"holding Up does not repeatedly cycle every frame")
	pad(false);player.melee_guard.impact_left=0;await host.get_tree().process_frame
	lock.select_target(enemies[0])
	enemies[1].position=player.position+Vector3.RIGHT*(lock.seeker_range+1000)
	pad(true);player._tick_contacts();player._read_weapon_input(1.0/60.0)
	t.eq(lock.target,enemies[2],"Up skips a visible but unscanned contact")
	pad(false);await host.get_tree().process_frame
	enemies[0].alive=false
	pad(true);player._tick_contacts();player._read_weapon_input(1.0/60.0)
	t.eq(lock.target,enemies[2],"destroyed and out-of-range contacts cannot displace the sole valid target")
	pad(false);await host.get_tree().process_frame
	lock.force_lock();var progress:=lock.quality
	t.ok(player.cycle_contact(),"single selectable contact remains selected")
	t.near(lock.quality,progress,.0001,"cycling a sole target preserves lock progress")
	enemies[2].position=player.position+Vector3.BACK*(lock.seeker_range+1000)
	t.not_ok(player.cycle_contact(),"no scanned contacts reports failure")
	t.eq(lock.target,enemies[2],"no scanned contacts does not clear the current target")
	for foe in enemies:foe.alive=true
	enemies[0].position=player.position+Vector3.FORWARD*1000
	enemies[1].position=player.position+Vector3.RIGHT*1400
	enemies[2].position=player.position+Vector3.BACK*1800
	lock.select_target(enemies[0]);lock.candidates.assign([enemies[0],enemies[2]])
	key(KEY_TAB,true);player._read_weapon_input(1.0/60.0)
	t.eq(lock.target,enemies[2],"keyboard Tab retains its existing candidate-cycle behavior")
	key(KEY_TAB,false);await host.get_tree().process_frame
	for foe in enemies:foe.alive=false
	t.not_ok(player.cycle_contact(),"empty contact list is handled without modulo-by-zero")
	t.eq(InputSetup.PAD_BINDINGS.switch_target,[JOY_BUTTON_DPAD_UP],"D-pad binding remains unique")
	stage.free();Game.reset();FlightBody.use_placeholder=old_placeholder
	InputSetup.using_gamepad=old_device;Settings.end_isolated()
