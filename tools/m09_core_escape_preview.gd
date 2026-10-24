extends Node
const Fixture:=preload("res://tests/suite_m09_core_escape.gd")
const MS:=preload("res://scripts/data/mission_script.gd")
var output:="C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/m09_core_escape"
func shot(name:String)->void:
	for i in 12:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name+".png"))
func _ready()->void:
	Settings.begin_isolated();Game.reset();Game.match_mode=Game.MatchMode.CHALLENGE;Game.active_mission=MS.m09()
	AudioServer.set_bus_mute(0,true);DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1200,720))
	var main:=Fixture.Runtime.new();add_child(main)
	main.units_root=Node3D.new();main.add_child(main.units_root)
	main.player=PlayerController.new();main.player.profile=Game.active_mission.make_player_profile();main.player.is_player=true
	main.units_root.add_child(main.player);main.player.set_process(false);main.player.set_physics_process(false)
	main.player.position=Vector3(0,100,0);main.player.ifield_hp=0;main.player.controls_enabled=true;Game.player=main.player
	main.chase=ChaseCamera.new();main.add_child(main.chase);main.chase.set_physics_process(false);main.chase.make_current();main.chase.set_target(main.player)
	main.chase.position=Vector3(55,122,-90);main.chase.look_at(main.player.position+Vector3.UP*12);main.chase.fov=50
	main.hud=FlightHUD.new();main.hud.player=main.player;main.hud.camera=main.chase;main.add_child(main.hud)
	main.player.destroyed.connect(main._on_player_destroyed)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.025,.045,.075)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color(.65,.75,.95);environment.environment.ambient_light_energy=.7;main.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=2;main.add_child(light)
	main.phase=main.Phase.FIGHT;Game.set_phase(Game.Phase.FIGHT)
	await shot("01_m09_penelope")
	main.player.take_damage(main.player.max_hp*2,null,Damage.Type.BEAM);main._tick_mission_triggers()
	var success:bool=main.phase==main.Phase.FIGHT and Game.phase==Game.Phase.FIGHT and main.player.in_transform()
	await shot("02_shell_empty_escaping")
	main.player._tick_transform(SuitProfile.TRANSFORM_COVER+.01);main.player.set_physics_process(false);main.player.set_process(false)
	main.player._tick_model_flash(FlightBody.MODEL_FLASH_TIME+.1);main._tick_mission_triggers()
	await get_tree().create_timer(.9).timeout
	await shot("03_m09_odysseus_continue")
	success=success and main.player.profile.form==1 and main.player.alive and main.phase==main.Phase.FIGHT and main.player.hp==main.player.max_hp
	Game.clock=main.player.invuln_until+.1;main.player.take_damage(main.player.max_hp*2,null,Damage.Type.BEAM)
	await shot("04_core_destroyed_defeat")
	success=success and not main.player.alive and Game.phase==Game.Phase.LOSE and main.phase==main.Phase.RESULT
	print("M09_CORE_ESCAPE_GPU ","PASS" if success else "FAIL"," core_form=",main.player.profile.form," defeat_after_core=",Game.phase==Game.Phase.LOSE)
	main.free();Game.reset();Settings.end_isolated();await get_tree().process_frame
	get_tree().quit(0 if success else 1)
