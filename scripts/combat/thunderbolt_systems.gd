extends RefCounted
## Independent launch intervals; Full Armor launchers share one refillable missile magazine.
const STING_SECONDS:=7.0
const BEAM_SECONDS:=2.5
const FLASHBANG := preload("res://scripts/combat/full_armor_flashbang.gd")
var flash_cd:=0.0
var flash_projectile: Node3D
var body
var secondary_missiles:=false
var primary_cd:=0.0
var primary_reload:=0.0
var primary_ammo:=18
var secondary_cd:=0.0
var bazooka_cd:=0.0
var bazooka_reload:=0.0
var bazooka_ammo:=60
var support_cd:=0.0
var shoulder_interval:=0.0
var hand_interval:=0.0
var held:=0.0
var hold_fired:=false
var visual_only:=false
var ram_attack:=false
var shot_pose:=0.0
var ai_timer:=0.0
var remote_motion:=Vector3.ZERO
var remote_dash:=0.0
var remote_dash_direction:=Vector3.ZERO
func install(unit)->void:
	body=unit;visual_only=body.has_method("apply_state")
	primary_ammo=3 if psycho() else 18
func psycho()->bool:return body.profile.id==SuitProfile.Id.PSYCHO_ZAKU_TB
func slot()->String:return body.current_slot() if body.has_method("current_slot") else "rifle"
func ready()->bool:return body.alive and not body.weapons_locked() and not body.in_transform() and not body.is_staggered() and not visual_only
func target()->Node3D:
	if not body.is_player and body.flash_blind_left>0:return null
	var lock=body.get("lock")
	return lock.target if lock!=null and is_instance_valid(lock.target) else null
func muzzle(key:String,fallback:Vector3)->Vector3:
	var marker=body.model_root.find_child("Mount_"+key,true,false) if is_instance_valid(body.model_root) else null
	return marker.global_position if marker!=null else body.global_transform*fallback
func direction(origin:Vector3)->Vector3:return origin.direction_to(body.rifle_aim_point(origin,target(),true))
func report(kind:String,origin:Vector3,ray:Vector3)->void:body._net_report_fire("tb_"+kind,origin,ray)
func reload()->void:
	if primary_ammo<(3 if psycho() else 18) and primary_reload<=0:primary_reload=9.0 if psycho() else 3.0
	if psycho() and secondary_missiles and bazooka_ammo<60 and bazooka_reload<=0:bazooka_reload=5.0
func primary()->bool:
	if not ready():return false
	if slot()=="saber":
		ram_attack=not psycho() and body.shield_up
		return body.try_saber(target())
	if primary_cd>0 or primary_reload>0:return false
	if primary_ammo<=0:reload();return false
	var origin=muzzle("muzzle_R",Vector3(3,2,-7));var ray=direction(origin)
	if psycho():
		beam(origin,120.0*body.damage_mult);report("beam",origin,ray);primary_cd=BEAM_SECONDS
	else:
		for side in [-1,1]:
			var from:Vector3=origin+body.right()*side*.4
			Projectile.beam(body.projectile_container,from,ray,body,body.profile.rifle_damage*body.damage_mult,Color(1,.35,.65),10000,1.0,14000)
			report("rifle",from,ray)
		primary_cd=.45
	primary_ammo-=1;shot_pose=BEAM_SECONDS if psycho() else .4;body.play_model_action("shoot",true)
	if primary_ammo==0:primary_reload=9.0 if psycho() else 3.0
	Audio.play_3d("beam_rifle",origin,-3);return true
func beam(origin:Vector3,damage:float)->void:
	var cannon=preload("res://scripts/combat/thunderbolt_beam.gd").new()
	cannon.shooter=body;cannon.offsets.append(body.to_local(origin));cannon.local_offset=body.to_local(origin)
	cannon.target=target();cannon.dps=damage;cannon.duration=BEAM_SECONDS;cannon.color=Color(1,.35,.65);cannon.radius=8;cannon.visual_scale=.6
	cannon.emitter=body.model_root.find_child("Mount_muzzle_R" if psycho() else "Mount_cannon",true,false)
	body.projectile_container.add_child(cannon);body.active_cannon=cannon
func secondary()->bool:
	if not ready():return false
	if psycho() and secondary_missiles:
		if bazooka_cd>0 or bazooka_reload>0:return false
		if bazooka_ammo<2:bazooka_reload=5.0;return false
		rockets(2,35.0,"bazooka",false);bazooka_ammo-=2;bazooka_cd=1.1
		if bazooka_ammo==0:bazooka_reload=5.0
		return true
	if secondary_cd>0 and (psycho() or not secondary_missiles):return false
	if psycho():rockets(2,35.0,"sting",true);secondary_cd=11.5
	elif secondary_missiles:
		if shoulder_interval>0:return false
		if not full_armor_missiles(6,"shoulder"):return false
		shoulder_interval=body.GP03_BAZOOKA_INTERVAL
	else:
		var origin=muzzle("cannon",Vector3(3,7,-3));beam(origin,120.0*body.damage_mult)
		report("beam",origin,direction(origin));secondary_cd=6.0
	shot_pose=.4;return true
func support()->bool:
	if not ready() or (psycho() and support_cd>0) or (not psycho() and hand_interval>0):return false
	if psycho():rockets(2,120.0,"heavy",false)
	elif not full_armor_missiles(5,"hand"):return false
	support_cd=12.0 if psycho() else 0.0
	if not psycho():hand_interval=body.GP03_BAZOOKA_INTERVAL
	return true
func full_armor_missiles(count:int,key:String)->bool:
	if body.funnel_reload_left>0 or body.funnel_count<=0:return false
	var shots:int=mini(count,body.funnel_count)
	rockets(shots,SuitProfile.xi().funnel_damage*2.0,key,false)
	body.funnel_count-=shots
	body._funnel_check_reload()
	return true
func missile_status()->String:
	return "装填 %.1fs"%body.funnel_reload_left if body.funnel_reload_left>0 else "%d / %d"%[body.funnel_count,body.funnel_mag_size]
func missile_ratio()->float:
	return body.funnel_reload_progress() if body.funnel_reload_left>0 else float(body.funnel_count)/maxi(body.funnel_mag_size,1)
func rockets(count:int,damage:float,key:String,sting:bool)->void:
	for i in count:
		var origin=muzzle(key+str(i%2),Vector3((-3 if key=="hand" else 3)*(1 if i%2==0 else -1),5 if key in ["shoulder","heavy","bazooka"] else 1,-4))
		origin+=body.up()*float(i/2)*.35
		var ray=direction(origin)
		var missile=Missile.spawn(body.projectile_container,origin,ray,target(),body,damage*body.damage_mult,Missile.Trail.HIGH)
		missile.thunder_sting=sting
		report("sting" if sting else "rocket",origin,ray)
	Audio.play_3d("funnel_fire",body.global_position,-3);shot_pose=.45
func input(delta:float)->void:
	if Input.is_action_just_pressed("switch_weapon"):body.switch_weapon()
	if Input.is_action_just_pressed("missile_mode"):
		secondary_missiles=not secondary_missiles
		body.notice.emit("右键："+secondary_name(),1.5)
	if Input.is_action_just_pressed("reload"):reload()
	if not ready():held=0;return
	if Input.is_action_just_pressed("flares"):body.deploy_flares()
	if Input.is_action_just_pressed("shield") and not psycho():body.raise_shield()
	if Input.is_action_pressed("fire_primary"):primary()
	if Input.is_action_pressed("fire_secondary"):secondary()
	if psycho():
		if Input.is_action_pressed("fire_gun"):body.fire_gun(true,target())
	elif Input.is_action_just_pressed("fire_gun"):flash_press()
	if psycho():
		if Input.is_action_pressed("fire_missile"):
			held+=delta
			if held>=.45 and not hold_fired:hold_fired=support()
		else:held=0;hold_fired=false
	elif Input.is_action_pressed("fire_missile"):support()
func step(delta:float)->void:
	flash_cd=maxf(0.0,flash_cd-delta)
	shoulder_interval=maxf(0.0,shoulder_interval-delta);hand_interval=maxf(0.0,hand_interval-delta)
	primary_cd=maxf(0,primary_cd-delta);secondary_cd=maxf(0,secondary_cd-delta);support_cd=maxf(0,support_cd-delta);bazooka_cd=maxf(0,bazooka_cd-delta);shot_pose=maxf(0,shot_pose-delta)
	if primary_reload>0:
		primary_reload=maxf(0,primary_reload-delta)
		if primary_reload==0:primary_ammo=3 if psycho() else 18
	if bazooka_reload>0:
		bazooka_reload=maxf(0,bazooka_reload-delta)
		if bazooka_reload==0:bazooka_ammo=60
	if not body.saber_active():ram_attack=false
	if not body.is_player and not visual_only and ready():
		ai_timer-=delta
		if ai_timer<=0:
			ai_timer=.4
			if is_instance_valid(target()):
				primary();secondary();support()
				if not psycho():
					if not flash_armed() and flash_cd<=0:flash_press()
				if not psycho() and body.global_position.distance_to(target().global_position)<1600:body.raise_shield()
func secondary_name()->String:
	return ("双持火箭筒" if secondary_missiles else "刺雷") if psycho() else ("肩部六连导弹" if secondary_missiles else "米加粒子炮")
func hud_rows()->Array:
	return [
		{"name":"光束火箭筒" if psycho() else "二连装步枪","value":"装填 %.1fs"%primary_reload if primary_reload>0 else str(primary_ammo)},
		{"name":secondary_name(),"value":("装填 %.1fs"%bazooka_reload if bazooka_reload>0 else str(bazooka_ammo)) if psycho() and secondary_missiles else (missile_status() if not psycho() and secondary_missiles else ("CD %.1fs"%secondary_cd if secondary_cd>0 else "READY"))},
		{"name":"长按F 双重火箭" if psycho() else "F 五连导弹","value":("CD %.1fs"%support_cd if support_cd>0 else "READY") if psycho() else missile_status()},
		{"name":"机关枪" if psycho() else "空格 闪光弹（自动索敌引爆）","value":("过热" if body.vulcan_overheated else "∞") if psycho() else flash_status()},
		{"name":"干扰弹","value":str(body.flare_count)},
		{"name":"热能斧" if psycho() else "撑盾 / 冲撞","value":"X切换" if psycho() else ("展开 %.1fs"%body.shield_timer if body.shield_up else "CD %.1fs"%body.shield_cooldown)}]
func snapshot()->Dictionary:
	var movement:Vector3=body.global_basis.orthonormalized().inverse()*body.translate_dir if body.translate_mode else Vector3(-body.control_input.z,body.control_input.y,body.control_input.x)
	return {"mode":secondary_missiles,"shield":body.shield_up,"shield_left":body.shield_timer,"shot":shot_pose,"ram":ram_attack,"movement":movement,"dash":body._qb_timer,"dash_dir":body.global_basis.orthonormalized().inverse()*body._qb_dir}
func apply_snapshot(data:Dictionary)->void:
	secondary_missiles=bool(data.get("mode",false));body.shield_up=bool(data.get("shield",false));body.shield_timer=float(data.get("shield_left",0));shot_pose=float(data.get("shot",0));ram_attack=bool(data.get("ram",false))
	remote_motion=data.get("movement",Vector3.ZERO);remote_dash=float(data.get("dash",0));remote_dash_direction=data.get("dash_dir",Vector3.ZERO)
func remote_fire(kind:String,origin:Vector3,ray:Vector3)->void:
	if kind=="tb_flash_launch":
		if flash_armed():flash_projectile.queue_free()
		flash_projectile=FLASHBANG.spawn(body.projectile_container,origin,ray,body,true)
		Audio.play_3d("funnel_fire",origin,-6)
		return
	if kind=="tb_flash_burst":
		if flash_armed():flash_projectile.queue_free()
		flash_projectile=null
		FLASHBANG.burst(body.projectile_container,origin)
		return
	shot_pose=.45
	match kind:
		"tb_beam":beam(origin,0.0)
		"tb_rifle":
			var shot=Projectile.beam(body.projectile_container,origin,ray,body,0,Color(1,.35,.65),10000,1.0,14000);shot.visual_only=true
		"tb_sting","tb_rocket":Missile.spawn(body.projectile_container,origin,ray,Game.player,body,0.0,Missile.Trail.HIGH)
	Audio.play_3d("funnel_fire" if kind in ["tb_sting","tb_rocket"] else "beam_rifle",origin,-4)


func flash_armed()->bool:
	return is_instance_valid(flash_projectile) and not flash_projectile.is_queued_for_deletion()

func flash_status()->String:
	if flash_armed():return "追踪中 · %.0fs"%flash_cd if flash_cd>0 else "追踪中"
	return "CD %.1fs"%flash_cd if flash_cd>0 else "READY"

func flash_detonate()->bool:
	if visual_only or not flash_armed():return false
	var at:Vector3=flash_projectile.global_position
	flash_projectile.queue_free();flash_projectile=null
	FLASHBANG.burst(body.projectile_container,at)
	for unit in Game.live_hostiles_of(body):
		if unit is FlightBody and not unit.has_method("apply_state"):unit.apply_flashbang(at)
	Net.send_flashbang_event("burst",at,Vector3.ZERO)
	return true

func flash_press()->bool:
	if psycho() or not ready():return false
	if flash_armed():return flash_detonate()
	if flash_cd>0 or body.projectile_container==null:return false
	var origin:Vector3=body.global_position+body.forward()*(body.model_bounds.size.z*.6+10)+body.up()*2
	var ray:Vector3=direction(origin)
	flash_projectile=FLASHBANG.spawn(body.projectile_container,origin,ray,body)
	flash_cd=30.0
	Net.send_flashbang_event("launch",origin,ray)
	Audio.play_3d("funnel_fire",origin,-6)
	if body.is_player:body.notice.emit("闪光弹已发射 · 自动索敌引爆",1.5)
	return true
