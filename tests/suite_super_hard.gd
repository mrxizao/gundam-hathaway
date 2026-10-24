extends RefCounted
const CS=preload("res://scripts/data/campaign.gd")
const MS=preload("res://scripts/data/mission_script.gd")
const MapUI=preload("res://scripts/ui/campaign_map.gd")
static func unit(host:Node,level:int,profile:SuitProfile,team:=1)->BanditAI:
	var ai:=BanditAI.new();ai.profile=profile;ai.team=team;ai.difficulty=Difficulty.make(level)
	host.add_child(ai);ai.position=Vector3(0,5000,0);ai.set_process(false);ai.set_physics_process(false)
	return ai
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset()
	var old_unlock:bool=Game.super_hard_unlocked
	t.suite("SuperHard / unlock, difficulty and independent campaign files")
	var ordinary:=CS.new_progress()
	t.not_ok(CS.super_hard_unlocked(ordinary),"new story does not unlock super hard")
	ordinary.cleared_mask=127
	t.not_ok(CS.super_hard_unlocked(ordinary),"old seven-mission save must finish chapter three")
	ordinary.cleared_mask=(1<<CS.MASK_ORDER.size())-1
	t.ok(CS.super_hard_unlocked(ordinary),"entire story completion unlocks")
	var normal_path:="user://test_super_hard_normal.cfg"
	var super_path:String=CS.path_for_difficulty(normal_path,Difficulty.Level.SUPER_HARD)
	CS.erase(super_path)
	CS.save_progress(ordinary,normal_path)
	t.not_ok(normal_path==super_path,"ordinary and super-hard files are distinct")
	t.eq(CS.path_for_difficulty(normal_path,Difficulty.Level.HARD),normal_path,"original difficulties share old file")
	t.eq(Difficulty.all_levels().size(),3,"locked menu has three difficulties")
	t.eq(Difficulty.all_levels(true).size(),4,"unlocked menu has four difficulties")
	t.eq(MapUI.cycle_difficulty(Difficulty.Level.HARD,1),Difficulty.Level.EASY,"locked campaign cannot choose super hard")
	t.eq(MapUI.cycle_difficulty(Difficulty.Level.HARD,1,true),Difficulty.Level.SUPER_HARD,"unlocked campaign exposes super hard")
	var d:=Difficulty.make(Difficulty.Level.SUPER_HARD)
	t.near(d.salvo_chance,.40,.0001,"super hard salvo probability is 40 percent")
	t.near(Difficulty.make(Difficulty.Level.HARD).salvo_chance,.08,.0001,"hard salvo probability stays 8 percent")
	t.near(d.rifle_accuracy,.70,.0001,"rifle accuracy policy 70 percent")
	var main:=preload("res://scripts/main.gd").new();main.campaign_save_path=normal_path;host.add_child(main)
	main._refresh_super_hard_unlock(true)
	t.ok(main.menu._super_notice.visible,"unlock notice shown on main menu")
	t.eq(main.menu._super_notice.get_child(0).text,"超级困难模式已开放","exact requested notice")
	t.ok(CS.load_progress(normal_path).super_hard_notice_seen,"shown notice survives reload")
	main.menu._super_notice.hide();main._refresh_super_hard_unlock(true)
	t.not_ok(main.menu._super_notice.visible,"unlock is announced once")
	main._open_campaign(Difficulty.Level.SUPER_HARD)
	t.eq(Game.campaign_progress.cleared_mask,0,"super-hard story starts fresh")
	t.eq(main.campaign_map.cursor,0,"super-hard page opens at first mission")
	t.eq(main.campaign_map.level,Difficulty.Level.SUPER_HARD,"page keeps super-hard difficulty")
	Game.active_mission=MS.by_id("M01");main._settle_campaign(true)
	t.ok(CS.is_cleared(CS.load_progress(super_path),"M01"),"super-hard completion saves to its file")
	t.eq(CS.load_progress(normal_path).cleared_mask,ordinary.cleared_mask,"original clears remain intact")
	main.campaign_map._cycle_diff(1)
	t.eq(main.campaign_map.level,Difficulty.Level.EASY,"real page input switches to original difficulty")
	t.eq(Game.campaign_progress.cleared_mask,ordinary.cleared_mask,"switching back restores original page")
	main.campaign_map.cursor=4;main.campaign_map._cycle_diff(1)
	t.eq(main.campaign_map.cursor,4,"switching among original difficulties preserves selected mission")
	main.campaign_map._cycle_diff(-1);main.campaign_map._cycle_diff(-1)
	t.eq(main.campaign_map.level,Difficulty.Level.SUPER_HARD,"real page input switches back to super hard")
	t.eq(Game.campaign_progress.cleared_mask,1,"switching again restores super-hard page")
	t.eq(main.campaign_map.cursor,1,"super-hard page resumes its own next mission")
	main.free();CS.erase(normal_path);CS.erase(super_path);Game.reset()
	t.suite("SuperHard / ace scaling, dash energy, pursuit and rifle solutions")
	var stage:=Node3D.new();host.add_child(stage)
	for profile in [SuitProfile.xi(),SuitProfile.penelope(),SuitProfile.arizeus(),SuitProfile.regz_custom(),SuitProfile.messer_m01()]:
		var ai:=unit(stage,Difficulty.Level.SUPER_HARD,profile)
		var ace:bool=profile.is_ace() or profile.id==SuitProfile.Id.REGZ_CUSTOM
		t.near(ai.max_hp,profile.hull_hp*(1.35 if ace else 1.0),.001,"ace-only hull scaling "+profile.display_name)
		t.near(ai.damage_mult,1.3*(1.3 if ace else 1.0),.001,"ace-only extra damage "+profile.display_name)
		ai.hp=ai.max_hp*.6;ai.ifield_hp=ai.ifield_max*.4
		ai._apply_difficulty()
		t.near(ai.hp_ratio(),.6,.001,"difficulty refresh does not heal")
		t.near(ai.ifield_ratio(),.4,.001,"difficulty refresh does not refill I-field")
		ai.free()
	for profile in [SuitProfile.arizeus(),SuitProfile.penelope(),SuitProfile.regz_custom()]:
		var changing:=unit(stage,Difficulty.Level.SUPER_HARD,profile)
		changing.hp=changing.max_hp*.6
		t.ok(changing.switch_form(0 if changing.form_index==1 else 1,true),"actual form change is available: "+profile.display_name)
		t.near(changing.max_hp,changing.profile.hull_hp*1.35,.001,"new form keeps ace hull boost")
		t.near(changing.hp_ratio(),.6,.001,"actual form change preserves hull ratio")
		t.near(changing.damage_mult,1.69,.001,"new form keeps ace damage boost")
		changing.free()
	var ai:=unit(stage,Difficulty.Level.SUPER_HARD,SuitProfile.xi())
	ai.dash_charge=.19
	t.not_ok(ai._start_hard_dash(Vector3.RIGHT),"below 20 percent waits")
	ai.dash_charge=.39
	t.not_ok(ai._start_hard_dash(Vector3.RIGHT),"latched wait continues above 20 but below 40")
	ai.dash_charge=.4
	t.ok(ai._start_hard_dash(Vector3.RIGHT),"at 40 percent dash is allowed")
	t.near(ai.dash_charge,.25,.001,"AI dash consumes actual gauge")
	ai._hard_dash_left=0;ai._hard_dash_cd=0;ai.dash_charge=.19
	ai._tick_super_resources(.5)
	t.not_ok(ai._super_dash_ready(),"recharge below 40 keeps wait latch")
	ai._tick_super_resources(.5)
	t.ok(ai._super_dash_ready(),"recharge to 40 releases wait latch")
	var player:=unit(stage,Difficulty.Level.NORMAL,SuitProfile.xi(),0);Game.player=player
	player.position=Vector3(0,5000,-20000);ai._target=player
	ai._hard_dash_cd=0;ai._hard_dash_left=0;ai._target_scan_left=0
	ai._think(.05)
	t.ok(ai.fm.boosting and ai.fm.super_boost,"distant player triggers super acceleration")
	t.gt(ai._hard_dash_left,0.0,"distant player triggers pursuit dash")
	t.gt(ai._hard_dash_dir.dot(ai.global_position.direction_to(player.global_position)),.999,"pursuit dash closes distance")
	ai._super_rifle_credit=0
	var accurate:=0
	for i in 100:
		var origin:=ai.global_position
		var ideal:Vector3=ai._lead_point(origin,player.global_position,player.fm.velocity,0,true)
		var point:Vector3=ai.rifle_aim_point(origin,player,true)
		if point.distance_to(ideal)<.01:accurate+=1
	t.eq(accurate,70,"70 of 100 emitted beam solutions aim precisely")
	t.suite("SuperHard / real beam collisions and defensive missile launch")
	ai._hard_dash_left=0;ai._hard_dash_cd=100;ai._super_rifle_credit=0
	ai.projectile_container=stage;ai.position=Vector3(0,5000,0);ai.global_basis=Basis.IDENTITY
	player.position=Vector3(0,5000,-1000);player.fm.velocity=Vector3.ZERO
	player.ifield_hp=0;player.max_hp=1000000;player.hp=player.max_hp
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var shots:Array[Projectile]=[]
	for i in 100:
		ai.rifle_cooldown=0;ai.rifle_reloading=false;ai.rifle_mag=1000
		var before:=stage.get_child_count()
		t.ok(ai.fire_beam(true,player,true),"super hard rifle emits through real weapon path")
		for index in range(before,stage.get_child_count()):
			var shot=stage.get_child(index)
			if shot is Projectile:shot.set_physics_process(false);shots.append(shot)
	var hits:=0
	for shot in shots:
		for step in 2:
			if not shot.is_queued_for_deletion():shot._physics_process(.10)
		if shot.is_queued_for_deletion():hits+=1
	t.eq(shots.size(),100,"one hundred real rifle projectiles emitted")
	t.eq(hits,70,"seventy percent real hits in an unobstructed stationary fixture")
	for shot in shots:if is_instance_valid(shot):shot.queue_free()
	var hostile:=Missile.funnel(stage,ai.position+Vector3(0,0,-500),Vector3.BACK,ai,player,10,Missile.Trail.LOW)
	hostile.set_physics_process(false)
	ai.funnel_cooldown=0;ai.funnel_reload_left=0;ai.funnel_count=100
	await host.get_tree().physics_frame
	var ammo:=ai.funnel_count
	ai._drive_super_intercept()
	var defenses:=0
	for child in stage.get_children():
		if child is Missile and child.shooter==ai and child.intercept_target==hostile:defenses+=1
	t.gt(defenses,0,"AI launches a real interceptor locked to the incoming missile")
	t.eq(ammo-ai.funnel_count,defenses,"interception consumes actual missile inventory")
	ai._hard_salvo_cd=0;ai._hard_salvo_left=0;ai.hp=ai.max_hp*.49;ai.funnel_count=150
	t.ok(ai._start_hard_salvo(player),"super hard can start the real full salvo")
	t.eq(ai._hard_salvo_left,PlayerController.FULL_SALVO_COUNT,"full salvo owns the real pending burst")
	# Exercise the real probability gate, including lock, HP, ammo and cooldown conditions.
	ai.lock=LockOnSystem.new();ai.add_child(ai.lock);ai.lock.setup(ai);ai.lock.set_physics_process(false)
	ai.lock.target=player;ai.lock.force_lock();ai._hard_rng.seed=4721
	ai._hard_cannon_cd=200;ai._hard_dash_cd=200
	var salvos:=0
	for trial in 1000:
		ai._hard_salvo_cd=0;ai._hard_salvo_left=0;ai._hard_salvo_roll=0
		ai.funnel_count=150;ai.funnel_reload_left=0;ai.funnel_cooldown=0
		ai._drive_hard_skills(1000,0)
		if ai._hard_salvo_left>0:salvos+=1
	t.ok(salvos>340 and salvos<460,"40 percent salvo gate across seeded eligible trials: %d/1000" % salvos)
	ai._hard_salvo_left=0
	for dir in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK,Vector3.UP,Vector3.DOWN]:
		ai.dash_charge=.7;ai._hard_dash_cd=0;ai._hard_dash_left=0;ai._super_dash_recovering=false
		t.ok(ai._start_hard_dash(dir),"all six safe dash directions are usable")
		t.ok(ai._before_flight_move(.01),"dash uses real flight integration")
		t.gt(ai.fm.velocity.normalized().dot(dir),.99,"dash velocity follows chosen direction")
	ai._hard_dash_left=0;ai._hard_dash_cd=100;ai.fm.speed=ai.fm.ab_speed
	ai.fm.super_boost=true;ai.fm.boosting=true;ai.fm._step_speed(.1,Vector3.FORWARD)
	t.gt(ai.fm.speed,ai.fm.ab_speed,"super acceleration exceeds normal boost speed through real physics")
	ai.free();player.free();stage.free();Game.reset()
	Game.super_hard_unlocked=old_unlock;Settings.end_isolated()
