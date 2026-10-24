extends RefCounted
const Drone=preload("res://scripts/combat/sazabi_funnel.gd")
const Axe=preload("res://scripts/combat/sazabi_axe.gd")
const Motion=preload("res://scripts/flight/sazabi_motion.gd")
enum State { DOCKED, ACTIVE, RETURNING }
enum Mode { SEQUENCE, VOLLEY }
const RETURN_SECONDS:=3.0
const REPAIR_SECONDS:=20.0
const AXE_HOLD_SECONDS:=.45
var body
var motion
var state:=State.DOCKED
var mode:=Mode.SEQUENCE
var energy:=1.0
var repair_left:=0.0
var lost:Array[int]=[]
var drones:Array[Node3D]=[]
var target:Node3D
var return_age:=0.0
var volley_phase:=0
var volley_age:=0.0
var visual_only:=false
var scoped:=false
var selected:Node3D
var ammo:Array[int]=[18,8]
var fire_cd:=0.0
var reload_left:=0.0
var reload_slot:=0
var axe_cd:=0.0
var axe_held:=0.0
var axe_swing:=false
var _secondary_last:=false
var _axe_thrown:=false
var _ai_mode_clock:=0.0
var ai_slot:="rifle"

func install(owner_body)->void:
	body=owner_body;motion=Motion.new();motion.install(body)
	visual_only=body.has_method("apply_state")
	for i in 6:dock_visible(i,state==State.DOCKED and not lost.has(i))
func report(kind:String,origin:=Vector3.ZERO,direction:=Vector3.FORWARD)->void:
	if not visual_only:body._net_report_fire("sazabi_"+kind,origin,direction)
func slot()->String:
	return body.current_slot() if body.has_method("current_slot") else ai_slot
func mode_name()->String:
	return "依次射击" if mode==Mode.SEQUENCE else "齐射"
func cannon_status()->String:
	if body.cannon_cd_left>0:return "CD %.1fs" % body.cannon_cd_left
	if body.has_method("cannon_charging") and body.cannon_charging():return "松手发射"
	if body.has_method("cannon_hold_ratio") and body.cannon_hold_ratio()>0:return "蓄力 %d%%" % int(body.cannon_hold_ratio()*100)
	return "READY"
func scope_active()->bool:
	return scoped and slot() in ["rifle","sniper"]
func valid_target()->bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.get("alive")==true and body.is_hostile_to(target)
func update_target()->void:
	var system=body.get("lock")
	if system is LockOnSystem and is_instance_valid(system.target) and system.target.alive:target=system.target
	elif not valid_target():target=null
func home(index:int)->Vector3:
	if motion!=null and index<motion.docks.size() and is_instance_valid(motion.docks[index]):return motion.docks[index].global_position
	return body.global_position+body.up()*7.0-body.forward()*5.0+body.right()*(float(index)-2.5)*1.8
func dock_visible(index:int,value:bool)->void:
	if motion!=null and index<motion.docks.size():motion.docks[index].visible=value
func launch()->bool:
	if state!=State.DOCKED or repair_left>0 or energy<=.001 or lost.size()>=2 or not body.alive:return false
	update_target()
	if not valid_target():return false
	state=State.ACTIVE;volley_phase=0;volley_age=0
	for i in 6:
		if lost.has(i):continue
		var drone:=Drone.new();drone.controller=self;drone.slot=i
		if motion!=null and i<motion.docks.size():
			drone.visual=motion.docks[i].duplicate() as Node3D
			drone.visual.transform=Transform3D.IDENTITY
			drone.visual.scale=Vector3.ONE*(body.profile.target_height/body.profile.model_native_height)
			drone.visual.show()
		body.projectile_container.add_child(drone);drone.global_position=home(i);drones.append(drone);dock_visible(i,false)
	Audio.play_3d("funnel_fire",body.global_position,-2)
	report("launch")
	return true
func recall()->bool:
	if state!=State.ACTIVE:return false
	state=State.RETURNING;return_age=0
	report("recall")
	for drone in drones:
		if is_instance_valid(drone) and not drone.is_queued_for_deletion():drone.begin_return()
	return true
func toggle()->bool:
	return recall() if state==State.ACTIVE else launch()
func toggle_mode()->void:
	mode=Mode.VOLLEY if mode==Mode.SEQUENCE else Mode.SEQUENCE
	report("mode_"+str(mode))
	volley_phase=0;volley_age=0
	for drone in drones:
		if is_instance_valid(drone):drone.phase=0;drone.phase_age=0;drone.next_shot=drone.age+1.0+drone.slot*.5
func funnel_destroyed(index:int)->void:
	if lost.has(index):return
	lost.append(index);dock_visible(index,false)
	report("lost_"+str(index))
	if lost.size()>=2:
		repair_left=REPAIR_SECONDS
		recall()
func _dock()->void:
	for drone in drones:
		if is_instance_valid(drone):drone.queue_free()
	drones.clear();state=State.DOCKED
	for i in 6:dock_visible(i,not lost.has(i))
func step(delta:float)->void:
	fire_cd=maxf(0,fire_cd-delta);axe_cd=maxf(0,axe_cd-delta)
	if not body.saber_active():axe_swing=false
	if reload_left>0:
		reload_left=maxf(0,reload_left-delta)
		if reload_left<=0:ammo[reload_slot]=18 if reload_slot==0 else 8
	if repair_left>0:
		repair_left=maxf(0,repair_left-delta)
		if repair_left<=0:
			lost.clear()
			if state==State.DOCKED:
				for i in 6:dock_visible(i,true)
	if state==State.DOCKED:energy=minf(1,energy+.05*delta)
	elif state==State.RETURNING:
		return_age=minf(RETURN_SECONDS,return_age+delta)
		if return_age>=RETURN_SECONDS:_dock()
	elif state==State.ACTIVE:
		update_target()
		energy=maxf(0,energy-(.06 if mode==Mode.SEQUENCE else .10)*delta)
		if energy<=0 or not valid_target():recall()
		elif mode==Mode.VOLLEY:
			volley_age+=delta
			if volley_phase==0 and volley_age>=3.7:
				volley_phase=1;volley_age=0
				for drone in drones:
					if is_instance_valid(drone):drone.freeze()
			elif volley_phase==1 and volley_age>=Drone.BEFORE_SHOT:
				for drone in drones:
					if is_instance_valid(drone) and not drone.is_queued_for_deletion():drone.fire()
				volley_phase=2;volley_age=0
			elif volley_phase==2 and volley_age>=Drone.AFTER_SHOT:volley_phase=0;volley_age=0
	if not body.is_player and not visual_only and body.has_method("_is_ace"):drive_ai(delta)
func drive_ai(delta:float)->void:
	update_target()
	if not valid_target():return
	var distance:float=body.global_position.distance_to(target.global_position)
	ai_slot="sniper" if distance>2400 else "rifle"
	if state==State.DOCKED and energy>.35 and distance<12000:launch()
	_ai_mode_clock-=delta
	if _ai_mode_clock<=0:
		_ai_mode_clock=7;toggle_mode()
func reload()->bool:
	var index:=1 if slot()=="sniper" else 0
	if slot() not in ["rifle","sniper"] or reload_left>0 or ammo[index]>=(8 if index==1 else 18):return false
	reload_slot=index;reload_left=6.0 if index==1 else 4.0
	return true
func beam_direction(origin:Vector3)->Vector3:
	if visual_only:return body.forward()
	var system=body.get("lock")
	var mark=selected if scoped and is_instance_valid(selected) else (system.target if system is LockOnSystem else null)
	return origin.direction_to(body.rifle_aim_point(origin,mark,true))
func fire_primary()->bool:
	if slot()=="cannon":return false # Dedicated press/hold/release input owns charging.
	if slot()=="saber":
		axe_swing=false
		return body.try_saber(body.lock.target if body.lock!=null else null)
	if fire_cd>0 or reload_left>0 or body.weapons_locked() or body.is_staggered() or not body.alive:return false
	var index:=1 if slot()=="sniper" else 0
	if ammo[index]<=0:reload();return false
	var origin:Vector3=body.global_transform*motion.muzzle_local()
	var system=body.get("lock")
	var mark=selected if scoped and is_instance_valid(selected) else (system.target if system is LockOnSystem else null)
	var aim:Vector3=body.rifle_aim_point(origin,mark,true)
	var direction:Vector3=origin.direction_to(aim)
	if index==1:
		var offsets:Array[Vector3]=[motion.muzzle_local()]
		body.active_cannon=BeamCannon.launch(body.projectile_container,body,offsets,mark,70.0*body.damage_mult,1.5,Color(.55,1,.4),5,.40)
		fire_cd=3.0
		report("sniper",origin,direction)
	else:
		var rng:=RandomNumberGenerator.new();rng.randomize()
		var spread:float=deg_to_rad(3.0 if scoped else 9.0)
		var basis:=Basis.looking_at(direction,Vector3.UP if absf(direction.y)<.98 else Vector3.RIGHT)
		for i in 12:
			var angle:=TAU*float(i)/12+rng.randf_range(-.10,.10)
			var radius:=sqrt((float(i)+.5)/12)*tan(spread)
			var ray:Vector3=(direction+basis.x*cos(angle)*radius+basis.y*sin(angle)*radius).normalized()
			var shot:=Projectile.beam(body.projectile_container,origin,ray,body,9.0*body.damage_mult,Color(.55,1,.4),origin.distance_to(aim),.65,14000)
			shot.set_beam_visual_width(Projectile.SAZABI_PELLET_VISUAL_WIDTH)
			body._net_report_fire("sazabi_pellet",origin,ray)
			if body.is_player:Game.shots_fired+=1;Game.beam_shots+=1
		fire_cd=1.1
	ammo[index]-=1;body.play_model_action("shoot",true);body._gun_recoil_clock=0
	body.beam_fired.emit();Audio.play_3d("beam_rifle",origin,0)
	return true
func axe_attack(thrown:bool)->bool:
	if not body.alive or axe_cd>0 or body.weapons_locked() or body.is_staggered() or body.saber_active():return false
	if not thrown:
		axe_swing=true
		if body.try_saber(body.lock.target if body.lock!=null else null):
			axe_cd=3.5;report("axe_swing");return true
		axe_swing=false;return false
	motion.throw_age=0.0
	var projectile:=Axe.new();projectile.shooter=body
	projectile.direction=body.rifle_raw_ray().direction
	projectile.model=Motion.make_blade(true);projectile.model.scale=Vector3.ONE*body.profile.target_height/body.profile.model_native_height
	body.projectile_container.add_child(projectile)
	projectile.global_position=motion.joints.Hand_R.global_position if motion.joints.has("Hand_R") else body.global_transform*motion.muzzle_local();axe_cd=4.5
	report("throw",projectile.global_position,projectile.direction)
	body.play_model_action("slash",true);Audio.play_3d("beam_saber",body.global_position,0)
	return true
func stun(foe)->void:
	if not foe.alive or body.is_friendly_fire(foe) or foe.in_transform():return
	if is_instance_valid(foe.nu_systems) and foe.nu_systems.barrier_active():return
	if foe.has_method("apply_state"):report("stun:player",foe.global_position)
	foe.melee_guard.impact_left=maxf(foe.melee_guard.impact_left,6.5)
	foe.melee_guard.slow_left=maxf(foe.melee_guard.slow_left,6.5)
	foe._stagger_timer=maxf(foe._stagger_timer,6.5)
func input(delta:float)->void:
	var secondary:=Input.is_action_pressed("fire_secondary")
	scoped=secondary and slot() in ["rifle","sniper"]
	if scoped:
		selected=body.lock.target if body.lock!=null and is_instance_valid(body.lock.target) else body.regz_weapons.acquire(body)
	else:selected=null
	if Input.is_action_just_pressed("switch_weapon"):
		body._cancel_cannon_charge()
		body.switch_weapon();scoped=false;axe_held=0;_secondary_last=false
		if is_instance_valid(body.active_cannon):body.active_cannon.queue_free();body.active_cannon=null
		report("slot_"+slot())
	if Input.is_action_just_pressed("reload"):reload()
	if Input.is_action_pressed("shield"):body.raise_shield()
	if Input.is_action_just_pressed("flares"):body.deploy_flares()
	if Input.is_action_just_pressed("fire_missile"):toggle()
	if Input.is_action_just_pressed("missile_mode"):toggle_mode()
	if slot()=="cannon":
		if body.weapons_locked() or body.is_staggered() or not body.alive:body._cancel_cannon_charge()
		else:body._read_release_rifle(delta,body.lock.target if body.lock!=null else null)
	elif Input.is_action_pressed("fire_primary"):fire_primary()
	if slot()=="saber":
		if secondary:
			if not _secondary_last:_axe_thrown=false;axe_held=0
			axe_held+=delta
			if axe_held>=AXE_HOLD_SECONDS and not _axe_thrown:_axe_thrown=axe_attack(true)
		elif _secondary_last:
			if not _axe_thrown and axe_held<AXE_HOLD_SECONDS:axe_attack(false)
			axe_held=0
	else:axe_held=0
	_secondary_last=secondary
