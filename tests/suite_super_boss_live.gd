extends RefCounted
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset()
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=false
	for profile in [SuitProfile.xi(),SuitProfile.penelope(),SuitProfile.arizeus(),SuitProfile.regz_custom()]:
		t.suite("SuperBossLive / actual moving fight: "+profile.display_name)
		var stage:=Node3D.new();host.add_child(stage)
		var foe:=FlightBody.new();foe.profile=SuitProfile.xi();foe.team=0;stage.add_child(foe)
		foe.set_process(false);foe.set_physics_process(false);foe.position=Vector3(0,5000,-1400)
		foe.max_hp=1000000;foe.hp=foe.max_hp;foe.ifield_hp=0
		var ai:=BanditAI.new();ai.profile=profile;ai.difficulty=Difficulty.make(Difficulty.Level.SUPER_HARD)
		ai.position=Vector3(0,5000,0);ai.projectile_container=stage;stage.add_child(ai)
		ai.target_override=foe;ai._hard_rng.seed=7301
		ai.hp=ai.max_hp*.28;ai.invuln_until=Game.clock+60
		ai._hard_cannon_cd=0 if profile.id==SuitProfile.Id.REGZ_CUSTOM else 8
		ai.fm.speed=profile.player_top_speed()*.6;ai.fm.velocity=Vector3.FORWARD*ai.fm.speed
		ai.lock=LockOnSystem.new();ai.add_child(ai.lock);ai.lock.setup(ai);ai.lock.target=foe;ai.lock.force_lock()
		var counts:={"beams":0,"dash":0,"missiles":0,"saber":0}
		ai.beam_fired.connect(func():counts.beams+=1)
		ai.quick_boost_started.connect(func(_dir):counts.dash+=1)
		ai.funnel_fired.connect(func():counts.missiles+=1)
		ai.saber_hit.connect(func(_target):counts.saber+=1)
		var start:=ai.position;var nearest:=INF;var furthest:=0.0;var lowest_charge:=1.0
		var max_real_missiles:=0;var max_real_cannons:=0;var target_shots:=0
		for frame in 360:
			var seconds:=frame/60.0
			foe.position=Vector3(sin(seconds*.8)*1000,5000+sin(seconds*.6)*180,-1400+cos(seconds*.8)*400)
			foe.fm.velocity=Vector3(cos(seconds*.8)*800,cos(seconds*.6)*108,-sin(seconds*.8)*320)
			var toward:Vector3=foe.global_position.direction_to(ai.global_position)
			foe.global_basis=Basis.looking_at(toward,Vector3.UP)
			foe.shield_up=frame>=90 and frame<150
			foe.rifle_reloading=frame>=210 and frame<260
			if frame%45==0:
				foe.rifle_cooldown=0;foe.rifle_mag=foe.profile.rifle_magazine
				if foe.fire_beam(true,ai,true):target_shots+=1
			foe._tick_weapons(1.0/60.0)
			# The fixture controls target motion, so it must also advance native
			# melee recovery normally advanced by FlightBody's physics loop.
			foe.melee_guard.tick(foe,1.0/60.0)
			await host.get_tree().physics_frame
			var distance:float=ai.global_position.distance_to(foe.global_position)
			nearest=minf(nearest,distance);furthest=maxf(furthest,distance)
			lowest_charge=minf(lowest_charge,ai.dash_charge)
			max_real_missiles=maxi(max_real_missiles,stage.get_children().filter(func(node):return node is Missile and node.shooter==ai).size())
			max_real_cannons=maxi(max_real_cannons,stage.get_children().filter(func(node):return node.get_script()==preload("res://scripts/combat/beam_cannon.gd") and node.shooter==ai).size())
			t.ok(ai.global_position.is_finite() and ai.fm.velocity.is_finite(),"live motion remains finite")
			t.ok(ai.dash_charge>=0 and ai.dash_charge<=1,"real energy gauge remains bounded")
		t.ok(ai.alive,"boss survives its own movement")
		t.eq(ai._boss.phase,2,"live low-HP fight uses final phase")
		t.gt(ai.position.distance_to(start),100,"boss actually moves in the running physics loop")
		t.gt(counts.dash,0,"live fight executes context-dependent dashes")
		t.gt(counts.beams,0,"live fight actually fires beam rifle")
		if profile.has_missiles:
			t.gt(counts.missiles,0,"live fight executes missile attacks")
			t.gt(max_real_missiles,0,"missile attacks create active real missiles")
		else:
			t.eq(counts.missiles,0,"Re-GZ retains its native absence of missiles")
			t.eq(max_real_missiles,0,"no missile weapon is invented for Re-GZ")
			t.eq(max_real_cannons,5,"Re-GZ actually transforms and fires its five-beam MEGA battery")
		t.lt(lowest_charge,.99,"live dashes spend energy")
		t.gt(target_shots,2,"opponent really fires to exercise observed reactions")
		print("SUPER_BOSS_LIVE ",profile.display_name," actions=",counts," gap=",nearest,"..",furthest," gauge_min=",lowest_charge," missiles=",max_real_missiles," cannons=",max_real_cannons," opponent_shots=",target_shots)
		stage.queue_free();await host.get_tree().process_frame;Game.reset()
	FlightBody.use_placeholder=old;Settings.end_isolated()
