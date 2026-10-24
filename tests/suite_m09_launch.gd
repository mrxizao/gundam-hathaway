extends RefCounted
const S:=preload("res://scripts/data/m09_launch_script.gd")
static func run(t:T)->void:
	t.suite("M09Launch / ordered shots, replay, total blackout and 700m handoff")
	var home:=Vector3(0,26,0)
	t.ok(S.cockpit(2),"starts inside cockpit")
	t.not_ok(S.cockpit(5),"hangar third-person shot precedes explosion")
	t.ok(S.cockpit(S.REPLAY+.1),"same attack replays in cockpit")
	for age in [0.0,.1,.4,.8,1.3]:
		var first:Dictionary=S.sample(S.IMPACT+age,home)
		var replay:Dictionary=S.sample(S.REPLAY_IMPACT+age,home)
		t.eq(first.position,replay.position,"replay has identical impact displacement")
		t.near(first.roll,replay.roll,.000001,"replay has identical impact roll")
	t.near(S.blackout(S.BLACK+.2),1,.00001,"all-screen blackout holds before restart")
	t.near(S.blackout(S.IGNITION),0,.00001,"ignition hard cuts to exterior")
	t.not_ok(S.cockpit(S.IGNITION),"base exterior replaces cockpit at ignition")
	t.near(S.TOTAL-S.ORBIT_END,3,.00001,"rear view holds three full seconds")
	var previous:float=home.y
	for frame in 481:
		var time:float=lerpf(S.IGNITION,S.ASCENT_END,float(frame)/480)
		var sample:Dictionary=S.sample(time,home)
		t.ok(sample.position.is_finite(),"finite ascent path")
		t.ok(sample.position.y>=previous-.00001,"ascent never dips")
		previous=sample.position.y
	var end:Dictionary=S.sample(S.TOTAL,home)
	t.near((end.position.y+S.BASE_WORLD.y)*FlightHUD.ALT_DISPLAY_SCALE,700,.0001,"handoff altitude matches HUD 700m")
	t.eq(end.position,S.sample(S.ORBIT_END,home).position,"rear hold does not move the ship")
	t.near(end.pitch,0,.00001,"hull levels before control returns")
