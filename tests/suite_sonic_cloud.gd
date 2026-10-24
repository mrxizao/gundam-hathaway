extends RefCounted
const Cloud := preload("res://scripts/flight/sonic_cloud.gd")
static func run(t: T, host: Node) -> void:
	t.suite("SonicCloud / exact HUD threshold and attached condensation")
	t.eq(Cloud.displayed_kmh(8000),int(8000*FlightHUD.SPEED_DISPLAY_SCALE),"uses the HUD display conversion")
	t.eq(Cloud.speed_strength(2000),0.0,"no cloud at a displayed 2000 km/h")
	t.gt(Cloud.speed_strength(2001),0.5,"cloud triggers strictly above displayed 2000 km/h")
	t.eq(Cloud.speed_strength(1999),0.0,"subthreshold speed does not trigger")
	t.eq(Cloud.atmosphere(MapDef.leo(),5000),0.0,"no clouds in vacuum")
	t.eq(Cloud.atmosphere(MapDef.pacific(),50000),0.0,"no clouds above the atmospheric visual envelope")
	var old_map := Game.active_map
	Game.active_map = MapDef.pacific()
	var old_placeholder := FlightBody.use_placeholder
	FlightBody.use_placeholder = true
	var unit := FlightBody.new()
	unit.profile = SuitProfile.messer_m01()
	host.add_child(unit)
	unit.set_physics_process(false)
	unit.global_position = Vector3(0,3000,0)
	var cloud := unit.get_node("SonicCloud")
	cloud.set_process(false)
	unit.fm.speed = 2000.9/FlightHUD.SPEED_DISPLAY_SCALE/3.6
	cloud.step(0.1)
	t.eq(cloud.bursts,0,"fractional raw speed still displaying 2000 cannot trigger")
	t.ok(cloud.mesh == null,"subthreshold units allocate no cloud geometry")
	unit.fm.speed = 2002.0/FlightHUD.SPEED_DISPLAY_SCALE/3.6
	unit.fm.velocity = Vector3(0,0,-unit.fm.speed)
	cloud.step(0.1)
	t.eq(cloud.bursts,1,"crossing threshold triggers one shock cloud")
	t.ok(cloud.mesh != null and cloud.mesh.visible,"condensation becomes visible")
	unit.fm.speed = 1999.0/FlightHUD.SPEED_DISPLAY_SCALE/3.6
	cloud.step(0.01)
	unit.fm.speed = 2002.0/FlightHUD.SPEED_DISPLAY_SCALE/3.6
	cloud.step(0.01)
	t.eq(cloud.bursts,1,"threshold jitter cannot spam overlapping shock flashes")
	for i in 10: cloud.step(0.1)
	t.eq(cloud.bursts,1,"sustained speed cannot retrigger a pulse every frame")
	unit.global_position += Vector3(10,50,-500)
	cloud.step(1.0/60)
	t.near(cloud.global_position.distance_to(unit.global_position),0,0.001,"cloud remains on the suit at speed")
	t.gt((-cloud.global_basis.z).dot(unit.fm.velocity.normalized()),0.99,"cloud axis follows actual airflow")
	unit.fm.speed = 1999.0/FlightHUD.SPEED_DISPLAY_SCALE/3.6
	for i in 30: cloud.step(1.0/60)
	t.ok(not cloud.mesh.visible,"cloud fades after speed drops below the threshold")
	unit.fm.speed = 2400.0/FlightHUD.SPEED_DISPLAY_SCALE/3.6
	cloud.step(0.1)
	t.eq(cloud.bursts,2,"reacceleration can trigger a new sonic cloud")
	Game.active_map = MapDef.leo()
	cloud.step(0.1)
	t.ok(not cloud.mesh.visible,"switching to space immediately clears condensation")
	Game.active_map = MapDef.pacific()
	unit.alive = false
	cloud.step(0.1)
	t.ok(not cloud.mesh.visible,"destroyed suits have no frozen clouds")
	unit.free()
	FlightBody.use_placeholder = old_placeholder
	Game.active_map = old_map
	await host.get_tree().process_frame
