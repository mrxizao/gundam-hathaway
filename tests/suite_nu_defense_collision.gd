extends RefCounted

class Pilot extends Node:
	var body:FlightBody
	var command:=Vector3.RIGHT*600
	var follow_fins:=false
	var turn:=false
	var age:=0.0
	var contacts:=0
	func _physics_process(delta:float)->void:
		if not body.alive:return
		age+=delta
		if turn:
			body.rotation=Vector3(sin(age*2)*.6,age*1.2,sin(age)*.3)
			command=body.forward()*1800+Vector3.UP*sin(age*3)*500
		body.velocity=command;body.fm.velocity=command
		body.move_and_slide()
		contacts+=body.get_slide_collision_count()
		body._check_collisions()
		if follow_fins and body.alive:body.nu_systems.tick(delta)

static func fixture(host:Node)->Dictionary:
	Game.reset()
	var stage:=Node3D.new();host.add_child(stage)
	var unit:=PlayerController.new();unit.profile=SuitProfile.nu_gundam();unit.is_player=true;unit.team=0;stage.add_child(unit)
	unit.set_physics_process(false);unit.set_process(false);unit.nu_systems.set_physics_process(false)
	unit.global_position=Vector3(0,5000,0)
	var pilot:=Pilot.new();pilot.body=unit;stage.add_child(pilot);pilot.set_physics_process(false)
	return {"stage":stage,"unit":unit,"pilot":pilot,"sys":unit.nu_systems}

static func simulate(host:Node,pilot:Pilot,seconds:float)->void:
	await host.get_tree().physics_frame
	pilot.set_physics_process(true)
	for i in ceili(seconds*Engine.physics_ticks_per_second):await host.get_tree().physics_frame
	pilot.set_physics_process(false)

static func finish(host:Node,stage:Node)->void:
	stage.free()
	preload("res://tests/suite_nu_gundam.gd").clean_audio(host)
	await host.get_tree().physics_frame

static func run(t:T,host:Node)->void:
	Settings.begin_isolated()
	var saved_hz:=Engine.physics_ticks_per_second
	var placeholder:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	t.suite("NuDefenseCollision / physical funnel contact cannot crash the hull")
	for state_name in ["defense","waiting","restored","remote"]:
		var st:=fixture(host);var unit:PlayerController=st.unit;var sys=st.sys
		sys.state=sys.State.ACTIVE;sys.mode=sys.Mode.DEFENSE
		for i in 6:
			sys.fins[i].reset(false);sys.fins[i].global_position=sys.orbit_point(i)
		# Put one live damageable fin directly in the flight path, as can happen
		# during deployment, turning, offense->defense and cooldown recovery.
		sys.fins[0].global_position=unit.global_position+Vector3.RIGHT*30
		if state_name=="waiting":sys._begin_cooldown(33,false)
		if state_name=="restored":sys.fins[0].reset(false)
		if state_name=="remote":
			var packet:Dictionary=sys.snapshot();sys.apply_snapshot(packet)
		var hp:=unit.hp
		if state_name=="defense":t.ok(sys.barrier_active(),"barrier is active before direct crossing")
		await simulate(host,st.pilot,.4)
		t.ok(unit.alive,state_name+": own funnel does not cause instant crash")
		t.eq(unit.hp,hp,state_name+": no self collision damage")
		t.eq(st.pilot.contacts,0,state_name+": fins do not physically block the hull")
		t.gt(unit.global_position.x,200,state_name+": movement crosses the fin instead of stopping")
		await finish(host,st.stage)
	t.suite("NuDefenseCollision / fast deployment, pitch and turning")
	for hz in [30,60,120]:
		Engine.physics_ticks_per_second=hz
		var st:=fixture(host);var unit:PlayerController=st.unit;var sys=st.sys
		sys.mode=sys.Mode.DEFENSE;sys.deploy()
		st.pilot.follow_fins=true;st.pilot.turn=true
		var hp:=unit.hp
		await simulate(host,st.pilot,3.5)
		t.ok(unit.alive,"moving defense deployment survives at %d Hz"%hz)
		t.eq(unit.hp,hp,"moving defense has no hull damage at %d Hz"%hz)
		t.eq(st.pilot.contacts,0,"moving fins never enter hull contact at %d Hz"%hz)
		t.ok(sys.barrier_active(),"defense finishes enclosing moving hull at %d Hz"%hz)
		sys.mode=sys.Mode.SEQUENCE
		await simulate(host,st.pilot,.7)
		sys.mode=sys.Mode.DEFENSE
		await simulate(host,st.pilot,.8)
		t.ok(unit.alive,"switching back to defense while turning survives at %d Hz"%hz)
		t.ok(sys.barrier_active(),"barrier resumes after mode switch at %d Hz"%hz)
		await finish(host,st.stage)
	Engine.physics_ticks_per_second=60
	t.suite("NuDefenseCollision / other hulls and genuine terrain")
	var st:=fixture(host);var sys=st.sys;var unit:PlayerController=st.unit
	sys.fins[0].reset(false);sys.fins[0].global_position=Vector3(30,5000,-1000)
	var other:=FlightBody.new();other.profile=SuitProfile.gustav00();other.team=1;st.stage.add_child(other)
	other.set_physics_process(false);other.set_process(false);other.global_position=Vector3(0,5000,-1000)
	var pilot:=Pilot.new();pilot.body=other;st.stage.add_child(pilot);pilot.set_physics_process(false)
	await simulate(host,pilot,.4)
	t.ok(other.alive,"enemy hull does not treat a funnel as terrain")
	t.eq(pilot.contacts,0,"enemy hull is not blocked by the damage hitbox")
	var wall:=StaticBody3D.new();wall.collision_layer=FlightBody.WORLD_LAYER;wall.collision_mask=0
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(10,100,100);shape.shape=box;wall.add_child(shape)
	wall.position=unit.global_position+Vector3.RIGHT*30;st.stage.add_child(wall)
	await simulate(host,st.pilot,.4)
	t.not_ok(unit.alive,"genuine world collision still destroys the hull")
	t.gt(st.pilot.contacts,0,"terrain remains physically solid")
	await finish(host,st.stage)
	Engine.physics_ticks_per_second=saved_hz;FlightBody.use_placeholder=placeholder
	Settings.end_isolated();Game.reset()
