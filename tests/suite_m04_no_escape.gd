extends RefCounted
const MS:=preload("res://scripts/data/mission_script.gd")
class Runtime:
	extends "res://scripts/main.gd"
	func _ready()->void:
		set_process(false);set_physics_process(false)
	func _settle_campaign(_win:bool)->void:pass # Never touch the player's campaign save.
class EmptyWorld extends WorldBuilder:
	func _ready()->void:pass
	func match_spawn_radius()->float:return 12000.0
class Pilot extends PlayerController:
	func _ready()->void:
		set_process(false);set_physics_process(false)
static func run(t:T,host:Node)->void:
	t.suite("M04NoEscape / real wave spawn, hull destruction and victory")
	var previous:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	for mode in [Game.MatchMode.CHALLENGE,Game.MatchMode.VERSUS]:
		for mission_id in ["M04","M09"]:
			# M09 is a negative control for the wave policy, not its chapter controller.
			Settings.begin_isolated();Game.reset();Game.match_mode=mode
			Game.active_mission=MS.by_id(mission_id) if mode==Game.MatchMode.CHALLENGE else null
			Game.active_challenge=ChallengeScript.xi_vs_penelope();Game.challenge_total=1
			Game.active_difficulty=Difficulty.make(Difficulty.Level.NORMAL)
			var main:=Runtime.new();host.add_child(main)
			main.world=EmptyWorld.new();main.add_child(main.world)
			main.units_root=Node3D.new();main.projectiles=Node3D.new();main.add_child(main.units_root);main.add_child(main.projectiles)
			main.player=Pilot.new();main.player.profile=SuitProfile.xi();main.player.is_player=true
			main.player.hp=100;main.player.max_hp=100;main.units_root.add_child(main.player);Game.player=main.player
			main.hud=FlightHUD.new();main.hud.player=main.player;main.add_child(main.hud)
			main.chase=ChaseCamera.new();main.add_child(main.chase);main.chase.set_physics_process(false)
			main.phase=main.Phase.FIGHT;Game.set_phase(Game.Phase.FIGHT)
			main._spawn_wave(0)
			var boss:BanditAI=main.wave_units[0];boss.set_physics_process(false);boss.set_process(false);boss.ifield_hp=0
			var blocked:bool=mission_id=="M04" and mode==Game.MatchMode.CHALLENGE
			if blocked:
				t.eq(boss.profile.transform_to_form,-1,"M04 spawn disables the fatal-hit escape")
				t.eq(boss.profile.transform_hull_ratio,0.0,"M04 spawn disables early 1-percent escape")
				boss._apply_damage(boss.max_hp*.995,main.player,Damage.Type.BEAM)
				t.ok(boss.alive and not boss.in_transform(),"below one percent remains the original Penelope")
				t.eq(main.phase,main.Phase.FIGHT,"low hull alone cannot finish the mission")
				var events:Dictionary={"destroyed":0,"transform":0}
				boss.destroyed.connect(func(_killer):events.destroyed+=1)
				boss.transform_started.connect(func(_form):events.transform+=1)
				boss._apply_damage(boss.max_hp,main.player,Damage.Type.BEAM)
				t.not_ok(boss.alive,"empty main hull destroys Penelope immediately")
				t.eq(boss.hp,0.0,"main hull ends at zero")
				t.eq(boss.profile.form,0,"no Odysseus form appears")
				t.eq(events.transform,0,"escape sequence never starts")
				t.eq(events.destroyed,1,"actual explosion destruction emits one kill")
				t.gt(main.units_root.find_children("Explosion*","Node3D",true,false).size(),0,"normal destruction creates explosion effect")
				t.eq(Game.challenge_killed,1,"kill credited to the mission")
				t.eq(Game.phase,Game.Phase.WIN,"existing mission rules mark victory")
				t.eq(main.phase,main.Phase.RESULT,"actual victory handler opens the result")
				# A single overkill hit must take the same ending, with no core cover timer.
				Game.challenge_killed=0;Game.set_phase(Game.Phase.FIGHT);main.phase=main.Phase.FIGHT
				main._spawn_wave(0)
				var fresh:BanditAI=main.wave_units[0];fresh.set_physics_process(false);fresh.ifield_hp=0
				fresh._apply_damage(fresh.max_hp*2,main.player,Damage.Type.BEAM)
				t.ok(not fresh.alive and not fresh.in_transform(),"one-hit overkill destroys M04 Penelope without escape")
				t.eq(fresh.profile.form,0,"one-hit overkill never creates Odysseus")
				t.eq(Game.phase,Game.Phase.WIN,"one-hit overkill also completes the mission")
			else:
				t.eq(boss.profile.transform_to_form,1,"other missions and ordinary battles retain Odysseus escape")
				boss._apply_damage(boss.max_hp*2,main.player,Damage.Type.BEAM)
				t.ok(boss.alive and boss.in_transform(),"overkill outside M04 still begins protected core escape")
				t.eq(main.phase,main.Phase.FIGHT,"escape alone does not finish an ordinary battle")
			main.free();Game.reset();Settings.end_isolated()
			await host.get_tree().process_frame
	FlightBody.use_placeholder=previous
	t.eq(SuitProfile.penelope().transform_to_form,1,"fresh Penelope profiles remain unchanged globally")
