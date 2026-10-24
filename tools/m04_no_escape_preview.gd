extends Node
const Fixture:=preload("res://tests/suite_m04_no_escape.gd")
const MS:=preload("res://scripts/data/mission_script.gd")
var output:="C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/m04_no_escape"
func shot(name:String)->void:
	for i in 12:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name+".png"))
func _ready()->void:
	Settings.begin_isolated();Game.reset();Game.match_mode=Game.MatchMode.CHALLENGE
	Game.active_mission=MS.m04();Game.active_challenge=ChallengeScript.xi_vs_penelope();Game.challenge_total=1
	Game.active_difficulty=Difficulty.make(Difficulty.Level.NORMAL);AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1200,720))
	var main:=Fixture.Runtime.new();add_child(main)
	main.world=Fixture.EmptyWorld.new();main.add_child(main.world)
	main.units_root=Node3D.new();main.projectiles=Node3D.new();main.add_child(main.units_root);main.add_child(main.projectiles)
	main.player=Fixture.Pilot.new();main.player.profile=SuitProfile.xi();main.player.is_player=true
	main.player.hp=main.player.profile.hull_hp;main.player.max_hp=main.player.hp;main.units_root.add_child(main.player);Game.player=main.player
	main.hud=FlightHUD.new();main.hud.player=main.player;main.add_child(main.hud)
	main.chase=ChaseCamera.new();main.add_child(main.chase);main.chase.set_physics_process(false);main.chase.make_current();main.hud.camera=main.chase
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.025,.045,.075)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color(.65,.75,.95);environment.environment.ambient_light_energy=.7
	main.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=2;main.add_child(light)
	main.phase=main.Phase.FIGHT;Game.set_phase(Game.Phase.FIGHT);main._spawn_wave(0)
	var boss:BanditAI=main.wave_units[0];boss.set_process(false);boss.set_physics_process(false);boss.position=Vector3(0,100,0);boss.ifield_hp=0
	main.chase.position=Vector3(-55,120,-85);main.chase.look_at(boss.position+Vector3.UP*12);main.chase.fov=50
	await shot("01_m04_penelope")
	boss._apply_damage(boss.max_hp*.995,main.player,Damage.Type.BEAM)
	await shot("02_low_hull_no_escape")
	var low_ok:bool=boss.alive and not boss.in_transform() and boss.profile.form==0
	boss._apply_damage(boss.max_hp*2,main.player,Damage.Type.BEAM)
	await shot("03_m04_explosion_win")
	var success:bool=low_ok and not boss.alive and boss.profile.form==0 and not boss.in_transform() and Game.phase==Game.Phase.WIN and main.phase==main.Phase.RESULT
	print("M04_NO_ESCAPE_GPU ","PASS" if success else "FAIL"," form=",boss.profile.form," hull=",boss.hp," alive=",boss.alive," result=",main.phase==main.Phase.RESULT)
	main.free();Game.reset();Settings.end_isolated()
	await get_tree().process_frame
	get_tree().quit(0 if success else 1)
