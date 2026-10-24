extends Node
var count:=0
var failed:=0
func check(ok:bool,label:String)->void:
	if ok:count+=1;print("PASS ",label)
	else:failed+=1;push_error("FAIL "+label)
func body(profile:SuitProfile,team:int=1)->FlightBody:
	var b:=FlightBody.new();b.profile=profile;b.team=team;add_child(b);b.set_physics_process(false);b.invuln_until=-1
	if is_instance_valid(b.nu_systems):b.nu_systems.set_physics_process(false)
	return b
func empty(b)->void:b.jet_left=0;b.dash_charge=0;b.dash_cd=9;b._jet_assist_recover=true
func full(b)->bool:return b.jet_left==b.profile.jet_seconds and b.dash_charge==1 and b.dash_cd==0 and not b._jet_assist_recover
func _ready()->void:
	await get_tree().process_frame
	Settings.begin_isolated();Game.phase=Game.Phase.FIGHT;FlightBody.use_placeholder=true
	var profile:=SuitProfile.zorin_soul()
	check(profile.rifle_magazine==15 and is_equal_approx(profile.rifle_damage,SuitProfile.nu_gundam().rifle_damage*6.5),"Pak43A magazine and damage")
	check(is_equal_approx(profile.player_top_speed()*3.6*(.6/2.4),3880),"3880 km/h cruise")
	check(profile.jet_seconds==SuitProfile.xi().jet_seconds*3 and profile.funnel_count==30,"Triple fuel and thirty missiles")
	var b:=body(profile,0);b.is_player=true
	var enemy:=body(SuitProfile.xi(),1);enemy.position=Vector3(1000,1000,0)
	var ally:=body(SuitProfile.xi(),0);ally.position=Vector3(-1000,1000,0)
	for kind in [Damage.Type.BEAM,Damage.Type.VULCAN,Damage.Type.SABER,Damage.Type.BEAM_CANNON]:
		empty(b);enemy.take_damage(1,b,kind);check(full(b),"Enemy weapon hit refill kind "+str(kind))
	empty(b);enemy.take_damage(1,b,Damage.Type.FUNNEL);check(b.dash_charge==0,"Floating missile does not refill")
	enemy.take_damage(1,b,Damage.Type.RAM);check(b.dash_charge==0,"Ram does not refill")
	ally.take_damage(1,b,Damage.Type.BEAM);check(b.dash_charge==0,"Friendly fire does not refill")
	enemy.take_damage(0,b,Damage.Type.BEAM);check(b.dash_charge==0,"Zero damage does not refill")
	enemy.invuln_until=Game.clock+20;enemy.take_damage(1,b,Damage.Type.BEAM);check(b.dash_charge==0,"Invulnerability does not refill");enemy.invuln_until=-1
	var proxy:=NetProxyBody.new();proxy.profile=SuitProfile.xi();proxy.team=1;add_child(proxy);proxy.set_physics_process(false)
	empty(b);proxy.take_damage(1,b,Damage.Type.VULCAN);check(full(b),"Network proxy hit refills firing player")
	empty(b);proxy.take_damage(1,b,Damage.Type.FUNNEL);check(b.dash_charge==0,"Network floating missile excluded")
	var sys=b.nu_systems
	check(sys.fins.size()==6 and sys.energy==200,"Six fins and double energy")
	for i in 8:sys.cycle_mode();check(sys.mode in [0,1],"Only sequence and volley modes")
	check(sys.deploy(enemy),"Deploy actual system")
	sys.tick(2.1);check(sys.state==sys.State.ACTIVE,"Deployment completes")
	var fin=sys.fins[0];fin.cancel_shot();check(fin.prepare(enemy),"Fin can prepare")
	check(is_equal_approx(fin.pre_left,.05),"Pre shot freeze .05s")
	fin.tick_shot(.05);check(is_equal_approx(fin.post_left,.1),"Post shot freeze .1s")
	check(sys.deploy(enemy) and sys.state==sys.State.RETURNING,"F recalls deployed fins")
	sys.tick(1.1);var energy:float=sys.energy;sys.tick(1);check(sys.energy>energy,"Docked fins recharge")
	b.ifield_hp=b.ifield_max*.5
	check(sys.use_minovsky(),"Barrier activation")
	check(is_equal_approx(b.ifield_hp,b.ifield_max*.57),"Barrier heals seven percent")
	check(sys.charges()==2 and is_equal_approx(sys.barrier_cd,5.0) and is_equal_approx(sys.barrier_left,4),"Independent charges and activation times")
	check(not sys.use_minovsky(),"Shared cooldown blocks immediate reuse")
	sys._tick_minovsky(2.5);check(sys.charges()==2 and is_equal_approx(sys.barrier_cd,2.5) and is_equal_approx(sys.charge_remaining(),10),"Recharge paused during cooldown")
	var hostile:=Missile.funnel(self,Vector3(100,100,0),Vector3.FORWARD,b,enemy,10)
	var friendly:=Missile.funnel(self,Vector3(-100,100,0),Vector3.FORWARD,enemy,ally,10)
	sys._intercept_minovsky();check(hostile.is_queued_for_deletion() and not friendly.is_queued_for_deletion(),"Barrier induces enemy missiles only")
	sys._tick_minovsky(3.0)
	check(is_equal_approx(sys.barrier_cd,0) and is_equal_approx(sys.charge_remaining(),9.5),"Only time beyond cooldown advances charge")
	check(sys.use_minovsky() and sys.charges()==1,"Second independent charge usable")
	sys._tick_minovsky(5)
	check(is_equal_approx(sys.charge_remaining(),9.5),"New cooldown pauses all pending charges")
	sys._tick_minovsky(9.5)
	check(sys.charges()==2 and is_equal_approx(sys.charge_remaining(),.5),"Independent recharge completion")
	sys._tick_minovsky(.5)
	check(sys.charges()==3 and is_equal_approx(sys.charge_progress(),1),"Charges full after ten charging seconds")
	check(is_equal_approx(preload("res://scripts/data/zorin_spec.gd").DAMAGE,27*1.8),"Fin damage is Nu times 1.8")
	b.rifle_mag=1;b.rifle_reloading=false;b.rifle_cooldown=0
	check(sys.fire_primary() and b.rifle_reloading,"Last chemical round starts automatic reload")
	var pak:Projectile
	for child in get_children():
		if child is Projectile and child.damage_type==Damage.Type.VULCAN:pak=child
	check(pak!=null and pak.damage_type==Damage.Type.VULCAN and is_equal_approx(pak.damage,profile.rifle_damage*FlightBody.RIFLE_DAMAGE_MULT),"Chemical round actual damage and physical type")
	check(load("res://scripts/ui/zorin_hud.gd").rows(b).size()==6 if b.has_method("weapon_name") else true,"HUD helper parses")
	for path in ["res://scripts/flight/player_controller.gd","res://scripts/ui/cockpit_3d.gd","res://scripts/ui/third_person_hud.gd","res://scripts/ui/cockpit_readouts.gd","res://scripts/ui/zorin_cockpit_surface.gd","res://scripts/ui/main_menu.gd","res://scripts/main.gd","res://scripts/flight/zorin_rig.gd"]:
		check(load(path)!=null,"Load "+path)
	check(Net.valid_room_choice(SuitProfile.Id.ZORIN_SOUL,-1,LanPlan.Form.ACE_DUEL),"LAN ace accepts Zorin")
	check(not Net.valid_room_choice(SuitProfile.Id.ZORIN_SOUL,0,LanPlan.Form.SQUAD),"LAN squad excludes Zorin")
	check(load("res://scripts/ui/main_menu.gd").SUITS.has(SuitProfile.Id.ZORIN_SOUL),"Menu includes Zorin")
	var main=load("res://scripts/main.gd").new()
	main.projectiles=Node3D.new();add_child(main.projectiles)
	var remote:=NetProxyBody.new();remote.profile=SuitProfile.zorin_soul();remote.team=1;add_child(remote);remote.set_physics_process(false);remote.nu_systems.set_physics_process(false)
	main.remote_proxy=remote
	for kind in ["zorin_pak","zorin_fin"]:
		var before:int=main.projectiles.get_child_count()
		main._on_net_fire(kind,Vector3(0,500,0),Vector3.FORWARD)
		var shot:Node=main.projectiles.get_child(before)
		check(shot!=null and shot.visual_only and ((shot is Projectile and shot.damage==0) or (shot is BeamCannon and shot.dps==0)),"Remote effect visible without duplicate damage "+kind)
	main._on_net_fire("zorin_barrier",Vector3.ZERO,Vector3.FORWARD)
	check(remote.nu_systems.barrier_left==4 and remote.nu_systems.waves.size()==3,"Remote expanding barrier reconstructed")
	remote.nu_systems.apply_snapshot(sys.snapshot())
	check(remote.nu_systems.energy==sys.energy and remote.nu_systems.charge_left==sys.charge_left,"Network snapshot retains energy and independent charges")
	main.free()
	print("ZORIN_DONE ",count," PASS / ",failed," FAIL")
	for n in get_children():n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Settings.end_isolated();get_tree().quit(1 if failed else 0)

