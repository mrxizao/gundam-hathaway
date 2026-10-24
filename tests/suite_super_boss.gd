extends RefCounted
static func unit(host:Node,profile:SuitProfile,level:=Difficulty.Level.SUPER_HARD,team:=1)->BanditAI:
	var ai:=BanditAI.new();ai.profile=profile;ai.difficulty=Difficulty.make(level);ai.team=team
	host.add_child(ai);ai.set_process(false);ai.set_physics_process(false)
	ai.position=Vector3(0,5000,0);return ai
static func bind(ai:BanditAI,foe:FlightBody)->void:
	ai._target=foe;ai.target_override=foe;ai._lag_pos=foe.global_position
	if ai.lock==null:
		ai.lock=LockOnSystem.new();ai.add_child(ai.lock);ai.lock.setup(ai);ai.lock.set_physics_process(false)
	ai.lock.target=foe;ai.lock.force_lock();ai._boss.tick(ai,.01)
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset()
	var old_placeholder:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	var stage:=Node3D.new();host.add_child(stage)
	t.suite("SuperBoss / scope, phases and native resource limits")
	for profile in [SuitProfile.xi(),SuitProfile.xi_final(),SuitProfile.penelope(),SuitProfile.arizeus(),SuitProfile.regz_custom(),SuitProfile.gp03d(),SuitProfile.gp03s(),SuitProfile.neue_ziel()]:
		var ai:=unit(stage,profile)
		t.ok(ai._boss.enabled(ai),"every ace receives tactics: "+profile.display_name)
		for level in [Difficulty.Level.EASY,Difficulty.Level.NORMAL,Difficulty.Level.HARD]:
			ai.difficulty=Difficulty.make(level);t.not_ok(ai._boss.enabled(ai),"original difficulty is unchanged")
		ai.difficulty=Difficulty.make(Difficulty.Level.SUPER_HARD);ai.team=0
		t.not_ok(ai._boss.enabled(ai),"friendly aces excluded")
		ai.team=1;ai.scripted=true;t.not_ok(ai._boss.enabled(ai),"scripted cutscenes excluded")
		ai.free()
	var xi:=unit(stage,SuitProfile.xi());var penelope:=unit(stage,SuitProfile.penelope())
	for phase in [0,1,2]:
		xi._boss.phase=phase;penelope._boss.phase=phase
		t.near(penelope._boss.preferred_range(penelope),xi._boss.preferred_range(xi),.001,"Penelope uses the same close-assault range as Xi")
		t.lt(penelope._boss.missile_interval(penelope),xi._boss.missile_interval(xi),"Penelope assault carries denser missile pressure")
	xi.free();penelope.free()
	var grunt:=unit(stage,SuitProfile.messer_m01());t.not_ok(grunt._boss.enabled(grunt),"mass production AI remains previous super-hard behavior");grunt.free()
	var ai:=unit(stage,SuitProfile.xi());var foe:=unit(stage,SuitProfile.xi(),Difficulty.Level.NORMAL,0)
	foe.position=Vector3(0,5000,-1500);foe.global_basis=Basis(Vector3.UP,PI);bind(ai,foe)
	t.eq(ai._boss.phase,0,"full HP starts opening phase")
	var phase0_range:float=ai._boss.preferred_range(ai)
	ai.hp=ai.max_hp*.60;ai._boss.tick(ai,.01)
	t.eq(ai._boss.phase,1,"60 percent escalates pressure")
	t.lt(ai._boss.preferred_range(ai),phase0_range,"second phase closes combat distance")
	ai.hp=ai.max_hp*.30;ai._boss.tick(ai,.01)
	t.eq(ai._boss.phase,2,"30 percent enters final pressure phase")
	ai.hp=ai.max_hp;ai._boss.tick(ai,.01)
	t.eq(ai._boss.phase,2,"escape/refill cannot downgrade battle phase")
	t.gt(ai._boss.salvo_cooldown(),0,"full salvo remains rate limited")
	t.gt(ai._boss.cannon_cooldown(ai),ai.profile.cannon_cooldown-.001,"native cannon cooldown remains the floor")
	ai.dash_charge=.19;ai._hard_dash_cd=0
	t.not_ok(ai._start_hard_dash(Vector3.RIGHT),"final phase obeys 20 percent lockout")
	ai.dash_charge=.39;t.not_ok(ai._start_hard_dash(Vector3.RIGHT),"final phase still waits until 40 percent")
	ai.dash_charge=.4;t.ok(ai._start_hard_dash(Vector3.RIGHT),"40 percent releases dash")
	t.near(ai.dash_charge,.25,.001,"final phase still spends real dash charge")
	ai._hard_dash_left=0;ai._hard_dash_cd=100
	t.suite("SuperBoss / observed beam, reaction delay and counter window")
	ai._boss.phase=0;ai.profile.cannon_enabled=false
	t.ok(foe.fire_beam(true,ai,false),"target emits a real beam through weapon path")
	t.not_ok(ai._boss.evading(ai),"no zero-latency beam dodge")
	ai._boss.tick(ai,.17);t.not_ok(ai._boss.evading(ai),"reaction delay has not elapsed")
	ai._boss.tick(ai,.02);t.ok(ai._boss.evading(ai),"visible beam triggers defensive response after delay")
	ai._drive_shield(1500);t.ok(ai.shield_up,"reaction raises real timed shield")
	t.near(ai.shield_timer,FlightBody.SHIELD_DURATION,.001,"shield uses native duration")
	ai._hard_dash_cd=0;ai.dash_charge=1;ai._drive_hard_skills(1500,0)
	t.gt(ai._hard_dash_left,0,"threat response executes a real dash")
	t.gt(absf(ai._hard_dash_dir.dot(ai.right())),.7,"beam dodge crosses line of fire")
	ai._before_flight_move(.01);t.gt(absf(ai.fm.velocity.x),500,"dodge moves the actual flight body laterally")
	ai._boss._shot_left=0;foe.quick_boost_started.emit(Vector3.RIGHT)
	t.not_ok(ai._boss.opening(ai),"opponent dash has not finished yet")
	ai._boss.tick(ai,FlightBody.QB_TIME+.01)
	t.ok(ai._boss.opening(ai),"opponent dash recovery opens counter window")
	ai._boss.tick(ai,1.2);t.not_ok(ai._boss.opening(ai),"counter window expires")
	foe.rifle_reloading=true;t.ok(ai._boss.opening(ai),"observed reload is an attack opening");foe.rifle_reloading=false
	foe.fm.velocity=Vector3(800,0,0);foe.position=Vector3(0,5000,-9000)
	t.gt(ai._boss.pursuit(ai).x,.05,"far pursuit cuts toward observed target velocity")
	foe.fm.velocity=Vector3.ZERO;foe.position=Vector3(0,5000,-200);ai.saber_cooldown=10
	ai._boss._target_dash_left=0;ai._boss._counter_left=0;ai.active_cannon=null
	var away:Vector3=ai._boss.dash_direction(ai,200)
	t.gt(away.dot(Vector3.BACK),.8,"close pass uses backward spacing instead of random dash")
	foe.position=Vector3(0,5000,-1500);ai._boss.detach()
	t.not_ok(foe.beam_fired.is_connected(ai._boss._on_beam),"detach disconnects old target fire signal")
	bind(ai,foe)
	t.suite("SuperBoss / real missiles, shield response and full salvo reserve")
	await host.get_tree().physics_frame;await host.get_tree().physics_frame
	var incoming:=Missile.spawn(stage,ai.global_position+Vector3.FORWARD*600,Vector3.BACK,ai,foe,0)
	incoming.set_physics_process(false);incoming.speed=1200
	await host.get_tree().physics_frame
	ai._boss._sensor_left=0;ai._boss.tick(ai,.01)
	t.ok(ai._boss.evading(ai),"actual nearby incoming missile triggers evasion")
	incoming.position=ai.position+Vector3.FORWARD*9000
	t.not_ok(ai._boss.evading(ai),"far missile does not cause premature evasive dancing")
	foe.saber_state=FlightBody.SaberState.CHARGE
	t.ok(ai._boss.evading(ai),"far missile cannot mask an immediate enemy saber threat")
	foe._end_saber();incoming.free();ai._boss._threat=null
	foe.shield_up=true;ai._hard_dash_left=0;ai._hard_dash_cd=100
	ai.hp=ai.max_hp;ai.funnel_count=150;ai.funnel_reload_left=0;ai.funnel_cooldown=0
	ai._boss._missile_cd=0;ai.rifle_cooldown=0;ai.rifle_reloading=false;ai.rifle_mag=ai.profile.rifle_magazine
	foe.profile.shield_reduction=0;t.not_ok(ai._boss.hold_rifle(ai),"cosmetic shield flag on a shieldless target does not suppress rifle")
	foe.profile.shield_reduction=SuitProfile.SHIELD_REDUCTION
	var before_mag:=ai.rifle_mag;var ammo:=ai.funnel_count
	ai._drive_weapons(.01)
	t.eq(ai.rifle_mag,before_mag,"does not waste rifle on a fully blocking shield")
	t.lt(ai.funnel_count,ammo,"shield counterattack consumes real missiles")
	var launched:=0
	for child in stage.get_children():
		if child is Missile and child.shooter==ai:launched+=1;child.set_physics_process(false)
	t.gt(launched,0,"shield counterattack has real projectile nodes")
	ai.hp=ai.max_hp*.4;ai._hard_salvo_cd=0;ai.funnel_count=102;ai.funnel_cooldown=0;ai._boss._missile_cd=0
	ai._boss.fire_missiles(ai,1500)
	t.eq(ai.funnel_count,102,"holds full-salvo inventory while roll is eligible")
	ai._hard_salvo_cd=10;ai._boss.fire_missiles(ai,1500)
	t.lt(ai.funnel_count,102,"ordinary missile pressure resumes during salvo cooldown")
	ai.profile.cannon_enabled=true;foe.shield_up=false;ai._boss._cannon_reserved=false
	ai.rifle_mag=ai.profile.rifle_magazine;ai.rifle_reloading=false;ai.cannon_cd_left=0;ai._hard_cannon_cd=0
	ai.global_basis=Basis(Vector3.UP,deg_to_rad(10));ai._boss.tick(ai,.01)
	t.ok(ai._boss.hold_rifle(ai),"fresh magazine gets a short cannon alignment opportunity")
	ai._boss.tick(ai,.8);t.not_ok(ai._boss.hold_rifle(ai),"failed cannon alignment cannot starve rifle indefinitely")
	var wall:=StaticBody3D.new();wall.collision_layer=FlightBody.WORLD_LAYER
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1000,1000,60);collision.shape=box
	wall.add_child(collision);stage.add_child(wall);wall.position=Vector3(0,5000,-600)
	await host.get_tree().physics_frame;await host.get_tree().physics_frame
	t.not_ok(ai._boss.line_clear(ai),"real world geometry blocks the shot line")
	ai.global_basis=Basis.IDENTITY;ai._drive_hard_skills(1500,0)
	t.not_ok(is_instance_valid(ai.active_cannon),"boss does not spend cannon into a wall")
	wall.free();ai.profile.cannon_enabled=false;ai._hard_dash_left=0;ai._hard_dash_cd=0
	foe.shield_up=true;foe.position=Vector3(0,5000,-400);ai._lag_pos=foe.global_position;ai.saber_cooldown=0
	t.lt(ai._boss.preferred_range(ai),ai.saber_range,"shielded target changes approach into melee range")
	ai._drive_weapons(.01)
	t.ok(ai.saber_active(),"shield counterattack executes the real beam saber instead of retreating first")
	ai._end_saber();ai.saber_cooldown=10;ai._hard_dash_cd=0
	foe.position=Vector3(0,5000,-1000)
	t.ok(ai._start_hard_dash(Vector3.FORWARD),"approach dash starts")
	t.lt(ai._hard_dash_left,FlightBody.QB_TIME,"approach dash duration stops short of the opponent")
	ai.free();foe.free()
	t.suite("SuperBoss / tactical form choice and persistent ace reinforcement")
	for profile in [SuitProfile.arizeus(),SuitProfile.regz_custom()]:
		var changing:=unit(stage,profile);var target:=unit(stage,SuitProfile.xi(),Difficulty.Level.NORMAL,0)
		target.position=Vector3(0,5000,-9000);bind(changing,target);changing.hp=changing.max_hp*.29
		changing._boss.tick(changing,.01);changing._drive_form()
		t.eq(changing.profile.form,0 if profile.id==SuitProfile.Id.ARIZEUS else 1,"long approach selects actual cruise form")
		t.near(changing.hp_ratio(),.29,.001,"tactical transform does not heal")
		t.near(changing.max_hp,changing.profile.hull_hp*1.35,.001,"actual transformed ace retains hull enhancement")
		target.position=Vector3(0,5000,-800);changing._form_timer=0;changing._drive_form()
		t.eq(changing.profile.form,1 if profile.id==SuitProfile.Id.ARIZEUS else 0,"close combat returns to actual normal form")
		t.near(changing.damage_mult,1.69,.001,"form choice does not stack damage")
		t.eq(changing._boss.phase,2,"enraged phase persists across forms")
		changing.free();target.free()
	stage.free();FlightBody.use_placeholder=old_placeholder;Game.reset();Settings.end_isolated()
