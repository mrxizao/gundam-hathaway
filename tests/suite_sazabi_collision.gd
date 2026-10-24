extends RefCounted
class Pilot extends Node:
	var body:FlightBody
	var contacts:=0
	func _physics_process(delta:float)->void:
		if not body.alive:return
		body.velocity=Vector3.RIGHT*600;body.fm.velocity=body.velocity
		body.move_and_slide();contacts+=body.get_slide_collision_count();body._check_collisions()
static func simulate(host:Node,seconds:float)->void:
	for i in ceili(seconds*Engine.physics_ticks_per_second):await host.get_tree().physics_frame
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset()
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	var hz_before:=Engine.physics_ticks_per_second
	t.suite("Sazabi collision / own deployed weapon is not terrain")
	for hz in [30,60,120]:
		Engine.physics_ticks_per_second=hz
		var stage:=Node3D.new();host.add_child(stage)
		var ai:=BanditAI.new();ai.profile=SuitProfile.sazabi();ai.team=1;ai.position=Vector3(0,5000,0);stage.add_child(ai);ai.set_physics_process(false)
		var p:=FlightBody.new();p.profile=SuitProfile.nu_gundam();p.team=0;p.is_player=true;p.position=Vector3(0,5000,-3000);stage.add_child(p);p.set_physics_process(false)
		p.nu_systems.set_physics_process(false)
		var lock:=LockOnSystem.new();stage.add_child(lock);lock.setup(ai);lock.select_target(p);lock.force_lock();lock.set_physics_process(false);ai.lock=lock
		var sys=ai.sazabi_systems;sys.step(.016)
		t.eq(sys.drones.size(),6,"locked AI automatically launches six funnels")
		for drone in sys.drones:
			drone.set_physics_process(false);drone.global_position=Vector3(500,5000,100+drone.slot*10)
		var fin=sys.drones[0];fin.global_position=Vector3(40,5000,0)
		var pilot:=Pilot.new();pilot.body=ai;stage.add_child(pilot)
		var hp:=ai.hp
		await simulate(host,.4);pilot.set_physics_process(false)
		print("SAZABI_COLLISION_PROBE ",hz," alive=",ai.alive," altitude=",ai.position.y," contacts=",pilot.contacts," funnel_layer=",fin.collision_layer)
		t.ok(ai.alive,"own funnel crossing survives at %dHz"%hz)
		t.eq(ai.hp,hp,"no self-collision hull damage")
		t.eq(pilot.contacts,0,"weapon hitbox never physically blocks aircraft")
		t.gt(ai.position.x,150,"aircraft crosses deployed weapon")
		if ai.alive:
			# A real beam sweep must still hit this shootable remote weapon.
			var shot:=Projectile.beam(stage,fin.global_position+Vector3(0,0,80),Vector3.FORWARD,p,20,Color.GREEN,0,1,5000)
			await simulate(host,.4)
			t.ok(not is_instance_valid(fin) or fin.destroyed,"real enemy beam can still destroy the funnel")
			# Keeping normal WORLD contacts is essential: do not solve this by invulnerability.
			var wall:=StaticBody3D.new();wall.collision_layer=FlightBody.WORLD_LAYER;wall.collision_mask=0
			var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4,50,50);shape.shape=box;wall.add_child(shape);stage.add_child(wall);wall.position=ai.position+Vector3.RIGHT*40
			await host.get_tree().physics_frame;pilot.set_physics_process(true);await simulate(host,.3);pilot.set_physics_process(false)
			t.not_ok(ai.alive,"real world obstacle still causes a crash")
		stage.free();preload("res://tests/suite_nu_gundam.gd").clean_audio(host)
		await host.get_tree().physics_frame;await host.get_tree().process_frame
	Engine.physics_ticks_per_second=hz_before;FlightBody.use_placeholder=old;Game.reset();Settings.end_isolated()
