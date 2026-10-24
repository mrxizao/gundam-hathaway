extends Node3D
var passed:=0
var failed:=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS ",label)
	else:failed+=1;push_error("FAIL "+label)
func unit(profile:SuitProfile,team:int=1)->FlightBody:
	var b:=FlightBody.new();b.profile=profile;b.team=team;add_child(b)
	b.set_physics_process(false);b.invuln_until=-1;b.invincible=false
	if is_instance_valid(b.nu_systems):b.nu_systems.set_physics_process(false)
	return b
func _ready()->void:
	await get_tree().process_frame
	Settings.begin_isolated();Game.reset();Game.phase=Game.Phase.FIGHT;FlightBody.use_placeholder=true
	var saz:=unit(SuitProfile.sazabi(),0)
	var victim:=unit(SuitProfile.xi(),1)
	var initial:float=victim.hp
	victim.take_damage(1,saz,Damage.Type.SABER)
	check(victim.combat_buffs.kick_left==0 and victim.hp==initial,"First melee marks without hull bypass")
	var shield:float=victim.ifield_hp
	victim.take_damage(1,saz,Damage.Type.SABER)
	check(victim.combat_buffs.kick_left==20 and is_equal_approx(victim.hp,initial-1),"Second melee triggers status with no bonus damage")
	check(victim.ifield_hp==shield,"Triggering hit bypasses I-field")
	victim.combat_buffs.kick_left=15
	victim.take_damage(2,saz,Damage.Type.BEAM)
	check(is_equal_approx(victim.hp,initial-3) and victim.ifield_hp==shield,"Subsequent ranged damage goes directly to hull")
	victim.take_damage(1,saz,Damage.Type.SABER)
	check(victim.combat_buffs.kick_left==15,"Repeated melee does not stack or refresh status")
	check(saz.combat_buffs.kick_cd==10,"Kick trigger starts ten-second cooldown")
	var second:=unit(SuitProfile.xi(),1)
	second.take_damage(1,saz,Damage.Type.SABER);second.take_damage(1,saz,Damage.Type.SABER)
	check(second.combat_buffs.kick_left==0,"One active victim per Sazabi")
	var zorin:=unit(SuitProfile.zorin_soul(),1);zorin.combat_buffs.kick_left=20
	check(is_equal_approx(victim.combat_buffs.movement_rate(victim),.6) and is_equal_approx(zorin.combat_buffs.movement_rate(zorin),.3),"Slow is forty percent, seventy for Zorin")
	victim.fm.velocity=Vector3(100,0,0);victim.velocity=victim.fm.velocity;victim.fm.speed=100
	victim.combat_buffs.scale_motion(victim)
	check(is_equal_approx(victim.fm.speed,60),"Movement is slowed")
	victim.combat_buffs.restore_motion(victim);victim.combat_buffs.scale_motion(victim)
	check(is_equal_approx(victim.fm.speed,60),"Slow does not compound each frame")
	victim.combat_buffs.tick(victim,16);victim.combat_buffs.restore_motion(victim)
	check(victim.combat_buffs.kick_left==0 and is_equal_approx(victim.fm.speed,100),"Expiration restores original movement")
	victim.combat_buffs.kick_left=20;victim.hp=victim.max_hp*.15+.5
	victim.take_damage(1,saz,Damage.Type.BEAM)
	check(not victim.alive,"Fifteen percent hull executes despite intact I-field")
	var gp:=unit(SuitProfile.gp03d(),1);gp.combat_buffs.kick_left=20;gp.hp=gp.max_hp*.15+.5
	gp.take_damage(1,saz,Damage.Type.BEAM)
	check(gp.alive and gp._transformed and gp.combat_buffs.kick_left==0,"Execution starts GP03D escape and clears debuff")
	var ar:=unit(SuitProfile.arizeus(),1);ar.combat_buffs.kick_left=20;ar.hp=ar.max_hp*.15+.5
	ar.take_damage(1,saz,Damage.Type.BEAM)
	check(ar.alive and ar._transformed,"Execution respects Arizeus escape")
	check(is_equal_approx(saz.profile.saber_interval,1.7) and saz.saber_magnet_range()==4500,"Sazabi saber cooldown and 4.5km magnet")
	saz.is_player=true;check(saz.saber_magnet_range()==4500,"Player Sazabi magnet is 4.5km")
	Game.phase=Game.Phase.FIGHT # Prior execution fixture may finish the match.
	var nu:=unit(SuitProfile.nu_gundam(),0);nu.is_player=false
	nu.combat_buffs.tick(nu,10)
	check(is_equal_approx(nu.combat_buffs.gauge,8),"Passive resonance is 0.8 percent per second")
	var foe:=unit(SuitProfile.xi(),1);foe.ifield_hp=0;foe.hp=foe.max_hp
	foe.take_damage(10,nu,Damage.Type.BEAM)
	check(is_equal_approx(nu.combat_buffs.gauge,13),"Each accepted outgoing hit adds five percent")
	var outgoing:float=nu.combat_buffs.gauge
	foe.take_damage(.1,nu,Damage.Type.BEAM);foe.take_damage(30,nu,Damage.Type.BEAM)
	check(is_equal_approx(nu.combat_buffs.gauge-outgoing,10),"Small and large outgoing hits each add five percent")
	outgoing=nu.combat_buffs.gauge;foe.ifield_hp=.1
	foe.take_damage(3,nu,Damage.Type.BEAM)
	check(is_equal_approx(nu.combat_buffs.gauge-outgoing,5),"One hit crossing shield and hull grants outgoing credit once")
	var meter:float=nu.combat_buffs.gauge
	nu.take_damage(10,foe,Damage.Type.BEAM)
	check(is_equal_approx(nu.combat_buffs.gauge-meter,7),"Each accepted incoming I-field hit adds seven percent")
	meter=nu.combat_buffs.gauge
	nu.take_damage(.1,foe,Damage.Type.BEAM);nu.take_damage(30,foe,Damage.Type.BEAM)
	check(is_equal_approx(nu.combat_buffs.gauge-meter,14),"Small and large incoming hits each add seven percent")
	meter=nu.combat_buffs.gauge;nu.ifield_hp=.1
	nu.take_damage(3,foe,Damage.Type.BEAM)
	check(is_equal_approx(nu.combat_buffs.gauge-meter,7),"One hit crossing shield and hull grants incoming credit once")
	meter=nu.combat_buffs.gauge
	foe.invuln_until=Game.clock+10;foe.take_damage(10,nu,Damage.Type.BEAM)
	check(nu.combat_buffs.gauge==meter,"Invulnerable target grants no resonance")
	foe.invuln_until=-1
	nu.combat_buffs.gain(nu,100)
	check(nu.combat_buffs.resonance_left==30 and nu.combat_buffs.protection_left==7,"Full gauge activates thirty-second mode and seven-second protection")
	var nhp:float=nu.hp;var nif:float=nu.ifield_hp
	nu.take_damage(10000,foe,Damage.Type.SABER)
	check(nu.hp==nhp and nu.ifield_hp==nif,"Seven-second protection rejects all damage")
	nu.combat_buffs.gain(nu,100);check(nu.combat_buffs.gauge==0,"No retrigger or stored meter during resonance")
	foe.hp=foe.max_hp;foe.take_damage(10,nu,Damage.Type.BEAM)
	check(is_equal_approx(foe.max_hp-foe.hp,12.5),"Ranged damage multiplier is 1.25")
	foe.hp=foe.max_hp;foe.take_damage(10,nu,Damage.Type.SABER)
	check(is_equal_approx(foe.max_hp-foe.hp,15),"Melee damage multiplier is 1.5")
	nu.rifle_reloading=true;nu.reload_timer=3;nu._tick_weapons(1)
	check(is_equal_approx(nu.reload_timer,1.5),"Reload progresses at 1.5 speed")
	var sys=nu.nu_systems
	sys.state=sys.State.ACTIVE;sys.target=foe;sys.energy=50;sys.shot_left=10;sys.mode=sys.Mode.SEQUENCE
	sys.tick(1)
	check(sys.energy==50 and is_equal_approx(sys.shot_left,8.5),"Resonance fin fire rate 1.5 and no energy drain")
	nu.combat_buffs.tick(nu,7.1)
	check(not nu.is_invulnerable() and nu.combat_buffs.active(),"Invulnerability ends after seven seconds")
	nu.combat_buffs.tick(nu,23)
	check(not nu.combat_buffs.active() and nu.combat_buffs.reload_rate()==1,"Thirty-second expiry restores multipliers")
	sys.energy=50;sys.tick(.1);check(sys.energy<50,"Fin energy drain resumes")
	var remote:=NetProxyBody.new();remote.profile=SuitProfile.nu_gundam();remote.team=1;add_child(remote);remote.set_physics_process(false);remote.nu_systems.set_physics_process(false)
	nu.combat_buffs.gain(nu,100);nu.combat_buffs.kick_left=12
	remote.apply_state(Net.unpack_state(Net.state_dict(nu)))
	check(remote.combat_buffs.active() and remote.combat_buffs.immune() and remote.combat_buffs.kick_left==12,"Network snapshot retains combat states")
	var before:float=remote.combat_buffs.gauge;remote.combat_buffs.tick(remote,1)
	check(remote.combat_buffs.gauge==before,"Remote visual proxy never accumulates passive meter")
	# Remote hits are already multiplied on the firing peer.
	foe.hp=foe.max_hp;foe.ifield_hp=0;remote.invuln_until=-1;remote.team=0
	foe.take_damage(12.5,remote,Damage.Type.BEAM)
	check(is_equal_approx(foe.max_hp-foe.hp,12.5),"Remote resonance damage is not multiplied twice")
	var hostile:=Missile.new();hostile.shooter=foe;add_child(hostile);hostile.set_physics_process(false)
	var friendly:=Missile.new();friendly.shooter=nu;add_child(friendly);friendly.set_physics_process(false)
	nu.combat_buffs.intercept(nu)
	check(hostile.is_queued_for_deletion() and not friendly.is_queued_for_deletion(),"Protection detonates hostile missiles but preserves friendly missiles")
	nu.combat_buffs.resonance_left=0;nu.combat_buffs.protection_left=0;nu.combat_buffs.gauge=0
	var friend_unit:=unit(SuitProfile.xi(),0)
	friend_unit.take_damage(10,nu,Damage.Type.BEAM)
	foe.take_damage(0,nu,Damage.Type.BEAM)
	check(nu.combat_buffs.gauge==0,"Friendly and zero damage grant no meter")
	Audio.play_resonance_bgm()
	check(Audio.current_bgm_track()=="beyond_the_time","Resonance selects BEYOND THE TIME")
	check(absf(Audio._bgm_players[Audio._bgm_active].get_playback_position()-88)<1,"Resonance music starts at 1 minute 28 seconds")
	Audio.stop_bgm(0)
	Settings.end_isolated()
	print("PSYCHO_DONE ",passed," PASS / ",failed," FAIL")
	get_tree().quit(1 if failed else 0)

