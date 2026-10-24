extends RefCounted
const Timeline:=preload("res://scripts/data/sortie_script.gd")
const Director:=preload("res://scripts/cinematics/sortie_director.gd")
class Owner:
	extends Node3D
	var player:PlayerController
	var world:LaunchWorld
	var units_root:Node3D
	var projectiles:Node3D
	var chase:Camera3D
	var hud:Control
class LaunchWorld:
	extends Node3D
	var time_of_day:TimeOfDay
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset();Game.set_phase(Game.Phase.INTRO)
	t.suite("Sortie / timelines and launch routing")
	t.not_ok(Timeline.supported(SuitProfile.xi_final()),"final battle Xi excluded")
	for p in [SuitProfile.xi(),SuitProfile.penelope(),SuitProfile.arizeus(1),SuitProfile.gustav00_armed(),SuitProfile.messer_m01(),SuitProfile.messer_cmd(),SuitProfile.messer_f01(),SuitProfile.regz_custom()]:
		for night in [false,true]:
			t.eq(Timeline.version(p,night).size(),7 if p.id==SuitProfile.Id.XI else 6,"six authored segments in each lighting version")
			var prev:=Vector3.ZERO
			for step in 109:
				var sample:Dictionary=Timeline.sample(p,step*.1)
				t.ok(sample.position.is_finite(),"finite launch path")
				t.ok(sample.position.y>=prev.y-.01,"no sinking during launch")
				t.ok(sample.position.z<=prev.z+.01,"launch moves forward")
				prev=sample.position
	t.suite("Sortie / real models, freeze and handoff")
	var previous_placeholder:=FlightBody.use_placeholder
	FlightBody.use_placeholder=false
	for p in [SuitProfile.xi(),SuitProfile.penelope(),SuitProfile.arizeus(1),SuitProfile.gustav00_armed(),SuitProfile.messer_m01(),SuitProfile.messer_cmd(),SuitProfile.messer_f01(),SuitProfile.regz_custom()]:
		for night in [false,true]:
			var owner:=Owner.new();host.add_child(owner)
			owner.world=LaunchWorld.new();owner.world.time_of_day=TimeOfDay.night() if night else TimeOfDay.day();owner.add_child(owner.world)
			owner.units_root=Node3D.new();owner.add_child(owner.units_root);owner.projectiles=Node3D.new();owner.add_child(owner.projectiles)
			owner.chase=Camera3D.new();owner.add_child(owner.chase);owner.hud=Control.new();owner.add_child(owner.hud)
			owner.player=PlayerController.new();owner.player.profile=p;owner.player.is_player=true;owner.player.position=Vector3(0,3000,0);owner.units_root.add_child(owner.player);owner.player.set_physics_process(false)
			var count:=Game.units.size();var original:Node3D=Game.player;var position:=owner.player.position
			var director:=Director.new();director.setup(owner);owner.add_child(director)
			print("SORTIE ",p.display_name," night=",night," profile=",director.actor.profile.form," origin=",director.origin)
			t.eq(Game.units.size(),count,"cinematic actor never registers in combat")
			t.eq(Game.player,original,"cinematic actor never replaces real player")
			t.eq(owner.units_root.process_mode,Node.PROCESS_MODE_DISABLED,"all combat units frozen")
			t.not_ok(owner.hud.visible,"game HUD hidden during every segment")
			if Timeline.cruise(p):
				if p.id==SuitProfile.Id.PENELOPE:t.near(director.actor.cruise_morph,1,.001,"Penelope uses cruise geometry")
				else:t.eq(director.actor.profile.form,0 if p.id==SuitProfile.Id.ARIZEUS else 1,"cruise model used from hangar onward")
			if Timeline.pedal(p):t.ok(director.actor.has_pedal(),"mass-production suit launches on platform")
			for time in ([.6,2.0,2.6,4.0,6.0,7.5] if Timeline.deck(p) else [.6,2.5,4.3,6.4,8.2,10.0]):
				director.time=time;director.pose(0.0)
				t.ok(director.camera.position.distance_to(director.actor.position)>p.target_height,"camera stays outside suit")
			if p.id==SuitProfile.Id.XI:
				for form_time in [4.0,5.3,5.9,6.5,6.6]:
					director.time=form_time;director.pose(.016)
					var expected:float=Timeline.sample(p,form_time).cruise_morph
					t.near(director.actor.cruise_morph,expected,.0001,"Xi form follows departure timeline in both lighting variants")
					if form_time<=6.5:t.near(director.actor.position.z,director.origin.z,.001,"no forward launch before cruise unfolds")
					if form_time>=5.3:t.gt(director.actor.position.y-director.origin.y,64.9,"transformation occurs airborne")
			if not Timeline.deck(p):
				for tow_time in [2.5,4.3,6.4,7.9]:
					director.time=tow_time;director.pose(0.0)
					var cargo:Vector3=director.actor.position-director.origin
					t.near(director.stage.cradle.position.x,cargo.x,.001,"trailer follows cargo all the way to runway X")
					t.near(director.stage.cradle.position.z,cargo.z,.001,"trailer follows cargo all the way to runway Z")
					t.near(director.stage.tractor.position.x,cargo.x,.001,"tractor stays attached during tow")
					t.near(director.stage.cradle.rotation.y,director.actor.rotation.y,.001,"cargo and trailer turn together")
					t.near(director.stage.cradle.position.y,0,.001,"transport wheels remain on pavement")
				director.time=8.95;director.pose(0.0)
				t.gt(director.stage.cradle.position.x-director.actor.position.x,100,"trailer clears sideways before acceleration")
				t.gt(director.stage.tractor.position.x-director.actor.position.x,140,"tractor clears runway before acceleration")
				t.near(director.stage.cradle.position.y,0,.001,"trailer never sinks through ground")
			director.finish()
			if p.id==SuitProfile.Id.XI:t.near(owner.player.cruise_morph,1.0,.0001,"Xi hands over with cruise geometry")
			t.eq(owner.units_root.process_mode,Node.PROCESS_MODE_INHERIT,"unit process restored")
			t.ok(owner.hud.visible,"HUD restored")
			t.eq(owner.player.position,position,"intro never teleports active mission player")
			if p.id==SuitProfile.Id.REGZ_CUSTOM:t.eq(owner.player.profile.form,1,"Re-GZ takes over in cruise")
			if p.id==SuitProfile.Id.ARIZEUS:t.eq(owner.player.profile.form,0,"Arizeus takes over in cruise")
			director.cleanup(false);owner.free();await host.get_tree().process_frame
	t.suite("Sortie / persistent southeast ships")
	var fleet:=preload("res://scripts/world/pacific_fleet.gd").new();host.add_child(fleet)
	for ship in fleet.ships:
		var bounds:AABB=ship.model.get_meta("source_bounds")
		t.near(bounds.size.z*ship.model.scale.z,200,.001,"each ship exactly 200 metres long")
		t.near(ship.model.scale.x,ship.model.scale.y,.00001,"width and height uniform scale")
		t.near(ship.model.scale.y,ship.model.scale.z,.00001,"length shares same scale")
		t.ok(ship.position.x>0 and ship.position.z>0,"ship placed southeast")
	fleet.apply_time(TimeOfDay.night());t.gt(fleet.ships[0].flood.light_energy,0,"night deck lighting active")
	for lamp in fleet.airbase.edge_lights:t.near(lamp.material_override.emission_energy_multiplier,4.0,.001,"every runway edge lamp switches to night")
	fleet.apply_time(TimeOfDay.day());t.near(fleet.ships[0].flood.light_energy,0,.001,"day floodlights off")
	fleet.free();FlightBody.use_placeholder=previous_placeholder;Settings.end_isolated()
