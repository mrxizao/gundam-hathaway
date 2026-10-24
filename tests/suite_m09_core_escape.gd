extends RefCounted
const MS:=preload("res://scripts/data/mission_script.gd")
class Runtime:
	extends "res://scripts/main.gd"
	func _ready()->void:
		set_process(false);set_physics_process(false)
	func _settle_campaign(_win:bool)->void:pass
static func run(t:T,host:Node)->void:
	t.suite("M09CoreEscape / shell loss, mission triggers and final core death")
	var previous:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	for fatal in [false,true]:
		Game.reset();Game.match_mode=Game.MatchMode.CHALLENGE;Game.active_mission=MS.m09()
		var main:=Runtime.new();host.add_child(main)
		main.units_root=Node3D.new();main.add_child(main.units_root)
		main.player=PlayerController.new();main.player.profile=Game.active_mission.make_player_profile();main.player.is_player=true
		main.units_root.add_child(main.player);main.player.set_physics_process(false);main.player.set_process(false)
		main.player.position=Vector3(0,4000,0);main.player.ifield_hp=0;main.player.controls_enabled=true;Game.player=main.player
		main.chase=ChaseCamera.new();main.add_child(main.chase);main.chase.set_physics_process(false);main.chase.set_target(main.player)
		main.hud=FlightHUD.new();main.hud.player=main.player;main.hud.camera=main.chase;main.add_child(main.hud)
		main.player.destroyed.connect(main._on_player_destroyed)
		main.phase=main.Phase.FIGHT;Game.set_phase(Game.Phase.FIGHT)
		main.player.take_damage(main.player.max_hp*(2.0 if fatal else .995),null,Damage.Type.BEAM)
		t.ok(main.player.alive and main.player.in_transform(),"shell defeat starts protected escape")
		main._tick_mission_triggers()
		t.eq(Game.phase,Game.Phase.FIGHT,"M09 does not fail during shell escape")
		t.eq(main.phase,main.Phase.FIGHT,"result screen cannot interrupt shell escape")
		t.ok(main.player.controls_enabled,"mission failure does not disable the recovering pilot")
		main.player._tick_transform(SuitProfile.TRANSFORM_COVER+.01)
		main.player.set_physics_process(false);main.player.set_process(false)
		t.eq(main.player.profile.form,1,"actual form swap creates Odysseus")
		t.eq(main.player.hp,main.player.max_hp,"Odysseus gets its own full hull bar")
		t.eq(main.player.ifield_max,0.0,"escaped core has no I-field")
		t.eq(main.player.funnel_count,0,"escaped core cannot retain shell missiles")
		t.ok(main.player.escape_dash_active(),"core receives its normal escape climb")
		main._tick_mission_triggers()
		t.eq(Game.phase,Game.Phase.FIGHT,"core can continue the same mission")
		# A badly damaged core is still alive until its own hull reaches zero.
		main.player.hp=main.player.max_hp*.005;main._tick_mission_triggers()
		t.eq(Game.phase,Game.Phase.FIGHT,"live core below one percent does not fail prematurely")
		Game.clock=main.player.invuln_until+.1
		main.player.take_damage(main.player.max_hp*2,null,Damage.Type.BEAM)
		t.not_ok(main.player.alive,"destroying core is the actual player defeat")
		t.eq(Game.phase,Game.Phase.LOSE,"core death still loses M09")
		t.eq(main.phase,main.Phase.RESULT,"core death opens the real defeat result")
		main.free();Game.reset();await host.get_tree().process_frame
	FlightBody.use_placeholder=previous
