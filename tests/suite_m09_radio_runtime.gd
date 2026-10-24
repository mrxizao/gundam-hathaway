extends RefCounted
const Controller:=preload("res://scripts/flight/chapter_three_controller.gd")
const Radio:=preload("res://scripts/flight/m09_radio.gd")
const MS:=preload("res://scripts/data/mission_script.gd")
const Comms:=preload("res://scripts/flight/comms_director.gd")
class Dummy extends PlayerController:
	func _ready()->void:set_process(false);set_physics_process(false)
	func set_scripted(_on:bool)->void:pass
class Owner extends Node3D:
	enum Phase { FIGHT, RESULT }
	var phase:=Phase.FIGHT
	var player:PlayerController
	var hud:FlightHUD
	var projectiles:Node3D
	func _notify_enemy_down(_unit):pass
	func _finish_round():phase=Phase.RESULT;player.controls_enabled=false
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset();Game.match_mode=Game.MatchMode.CHALLENGE;Game.active_mission=MS.m09();Game.set_phase(Game.Phase.FIGHT)
	t.suite("M09Radio / real damage, kill, retreat and result callbacks")
	var owner:=Owner.new();host.add_child(owner)
	owner.player=Dummy.new();owner.player.profile=SuitProfile.penelope();owner.player.max_hp=100;owner.player.hp=100;owner.player.is_player=true;owner.add_child(owner.player)
	Game.player=owner.player
	owner.hud=FlightHUD.new();owner.hud.player=owner.player;owner.add_child(owner.hud);owner.hud.set_process(false);owner.hud.hide();owner.hud.comms=Comms.new()
	owner.projectiles=Node3D.new();owner.add_child(owner.projectiles)
	var controller:=Controller.new();controller.setup(owner,MS.m09());owner.add_child(controller)
	var radio:=Radio.new();radio.setup(controller);controller.add_child(radio);controller.precision_radio=radio;radio.set_process(false)
	var xi:=Dummy.new();xi.profile=SuitProfile.xi();xi.max_hp=100;xi.hp=100;owner.add_child(xi);controller.foes.append(xi);controller.target=xi
	var messers:Array[FlightBody]=[]
	for i in 3:
		var foe:=Dummy.new();foe.profile=SuitProfile.messer_m01();foe.max_hp=100;foe.hp=100;owner.add_child(foe);controller.foes.append(foe);messers.append(foe)
	radio.observe({"elapsed":25,"messer_distance":2000,"messer_alive":3,"messer_down":0,"city_distance":12000})
	messers[0].position=Vector3(15,-3,0)
	owner.player.damaged.emit(8.0,messers[0],Damage.Type.SABER)
	t.ok(radio.fired.has("hit") and radio.fired.has("right_hit"),"actual right-side saber hit selects damage dialogue")
	owner.player.beam_fired.emit()
	t.ok(radio.fired.has("exchange"),"actual rifle signal selects crossfire dialogue")
	xi.hp=20;controller._target_damaged(1,null,Damage.Type.BEAM)
	t.ok(radio.fired.has("xi_retreat"),"actual Xi hull threshold selects supplied withdrawal lines")
	t.ok(bool(Game.mission_events.get("xi_repelled",false)),"dialogue hook preserves gameplay objective")
	t.eq(Game.phase,Game.Phase.FIGHT,"repelling Xi alone does not end battle")
	for foe in messers:
		foe.alive=false;controller._unit_destroyed(foe,owner.player)
	t.ok(radio.fired.has("first_down"),"actual Messer destruction selects supplied kill lines")
	t.eq(controller.messer_down,3,"kill bookkeeping unchanged")
	t.eq(Game.phase,Game.Phase.WIN,"existing objectives still finish the mission")
	radio._process(0);owner.hud.comms.tick(.2);radio._process(0)
	t.ok(radio.won and radio.result_panel.visible,"victory radio remains visible while combat HUD is hidden")
	var heard:Dictionary={}
	for i in 10:
		for entry in owner.hud.comms.live():heard[entry.line.id]=true
		owner.hud.comms.tick(30);radio._process(.1);owner.hud.comms.tick(.1)
	t.eq(heard.size(),8,"all withdrawal and conclusion lines reach the live radio")
	t.eq(radio.pending.size(),0,"result radio drains fully")
	controller.cleanup();owner.free();Game.reset();Settings.end_isolated()
	await host.get_tree().process_frame
