extends Node3D
const Spec:=preload("res://scripts/data/zorin_spec.gd")
const Fin:=preload("res://scripts/combat/zorin_fin.gd")
enum State { DOCKED, DEPLOYING, ACTIVE, WAITING, RETURNING, COOLDOWN_DOCKED }
enum Mode { SEQUENCE, VOLLEY, DEFENSE }
var body
var fins:Array[Node3D]=[]
var state:=State.DOCKED
var mode:=Mode.SEQUENCE
var energy:=Spec.ENERGY_MAX
var cooldown_left:=0.0
var cooldown_total:=Spec.COOLDOWN
var age:=0.0
var state_age:=0.0
var shot_left:=0.0
var next_fin:=0
var destroyed_count:=0
var target:Node3D
var barrier:MeshInstance3D
var barrier_edges:MeshInstance3D
var shot_log:Array[Dictionary]=[]
var visual_only:=false
var remote_swing:=false
var pilot_intent:=Vector3.ZERO
var pilot_intent_valid:=false
var bazooka_mag:=Spec.BAZOOKA_MAG
var bazooka_reload_left:=0.0
var bazooka_cd:=0.0
var bazooka_pose_left:=0.0
var last_model_id:=0
var remote_slot:="rifle"
var remote_scope:=false
var equipment_cd:=0.0
func _ready()->void:
	process_mode=Node.PROCESS_MODE_PAUSABLE;name="ZorinSystems"
	visual_only=body.has_method("apply_state") or (Net.role==Net.Role.CLIENT and body.get("net_unit_id")!=null)
	for i in Spec.FIN_COUNT:
		var fin:=Fin.new();fin.controller=self;fin.index=i;body.projectile_container.add_child(fin);fins.append(fin)
	_build_barrier();_sync_docks()
func deployed()->bool:return state in [State.DEPLOYING,State.ACTIVE,State.WAITING,State.RETURNING]
func mode_name()->String:return Spec.MODE_NAMES[mode]
func status_text()->String:
	return "CD %.1fs"%cooldown_left if cooldown_left>0 else "%03d / 200"%roundi(energy)
func bazooka_status()->String:
	if equipment_cd>0:return "CD %.1fs"%equipment_cd
	return "装填 %.1fs"%bazooka_reload_left if bazooka_reload_left>0 else "%02d / 4"%bazooka_mag
func discard_equipment()->bool:
	if equipment_cd>0:
		if body.is_player:body.notice.emit("盾牌 / 火箭筒冷却中 · %.1fs"%equipment_cd,1.5)
		return false
	if not body.alive or body.in_transform():return false
	preload("res://scripts/combat/nu_jettison.gd").spawn(body,"NuBazooka",1)
	preload("res://scripts/combat/nu_jettison.gd").spawn(body,"NuShield",-1)
	equipment_cd=15.0;bazooka_reload_left=0.0;bazooka_pose_left=0.0
	body.shield_up=false;body.shield_timer=0;body.shield_cooldown=maxf(body.shield_cooldown,15)
	body.unlockable_until=maxf(body.unlockable_until,Game.clock+SuitProfile.xi().discard_unlockable_seconds)
	var opposing_lock=Game.lock_of_opponent_of(body)
	if opposing_lock!=null:opposing_lock.force_drop_if_target(body)
	Audio.play_3d("ui_item",body.global_position,-4,1.25)
	_sync_equipment()
	if body.is_player:body.notice.emit("盾牌 / 火箭筒已丢出 · 骗锁 · 冷却15s",2)
	if not visual_only:body._net_report_fire("nu_jettison",body.global_position,body.forward())
	return true
func _sync_equipment()->void:
	if not is_instance_valid(body.model_root):return
	for prefix in ["NuBazooka_*","NuShield_*"]:
		for mesh in body.model_root.find_children(prefix,"MeshInstance3D",true,false):mesh.visible=equipment_cd<=0
func snapshot()->Dictionary:
	var actors:Array=[]
	for fin in fins:
		actors.append({"p":fin.global_position,"r":fin.global_rotation,"hp":fin.hp,"alive":fin.alive,"out":fin.deployed})
	return {"state":state,"mode":mode,"energy":energy,"cd":cooldown_left,"total":cooldown_total,"lost":destroyed_count,"fins":actors,"slot":body.current_slot() if body.has_method("current_slot") else "rifle","scope":body.precision_view_active() if body.has_method("precision_view_active") else false,"shield":body.shield_up,"equipment_cd":equipment_cd,"unlock":body.unlockable_seconds_left(),"minovsky":barrier_left,"barrier_cd":barrier_cd,"charges":charge_left,"motion":{"pilot":pilot_intent,"pilot_valid":pilot_intent_valid,"input":body.control_input,"translate":body.translate_dir,"assisted":body.translate_mode,"dash":body._qb_timer,"dash_dir":body._qb_dir,"boost":body.fm.boosting,"melee":body._saber_visual_clock,"swing":body.saber_active() or body._saber_visual_tail>0}}
func apply_snapshot(data:Dictionary)->void:
	if data.is_empty():return
	if visual_only:
		var motion:Dictionary=data.get("motion",{})
		pilot_intent=motion.get("pilot",Vector3.ZERO);pilot_intent_valid=bool(motion.get("pilot_valid",false))
		body.control_input=motion.get("input",Vector3.ZERO);body.translate_dir=motion.get("translate",Vector3.ZERO);body.translate_mode=motion.get("assisted",false)
		body._qb_timer=float(motion.get("dash",0));body._qb_dir=motion.get("dash_dir",Vector3.ZERO);body.fm.boosting=motion.get("boost",false)
		body._saber_visual_clock=float(motion.get("melee",0));remote_swing=bool(motion.get("swing",false))
	barrier_left=float(data.get("minovsky",0));barrier_cd=float(data.get("barrier_cd",0));charge_left=Array(data.get("charges",[0.0,0.0,0.0]))
	_sync_minovsky()
	state=int(data.state);mode=int(data.mode);energy=float(data.energy);cooldown_left=float(data.cd);cooldown_total=float(data.total);destroyed_count=int(data.lost)
	remote_slot=str(data.slot);remote_scope=bool(data.scope);body.shield_up=bool(data.shield)
	equipment_cd=float(data.get("equipment_cd",0));body.unlockable_until=Game.clock+float(data.get("unlock",0))
	for i in mini(fins.size(),data.fins.size()):
		var entry:Dictionary=data.fins[i];var fin=fins[i]
		fin.global_position=entry.p;fin.global_rotation=entry.r;fin.hp=float(entry.hp);fin.alive=bool(entry.alive);fin.deployed=bool(entry.out)
		fin.visible=fin.alive and fin.deployed;fin.collision_layer=Spec.FIN_HIT_LAYER if fin.visible else 0
	_sync_docks();_sync_equipment();_update_barrier()
func find_target()->Node3D:
	var lock=body.get("lock")
	if lock!=null and is_instance_valid(lock.target) and lock.target.alive:return lock.target
	if is_instance_valid(target) and target.alive and body.is_hostile_to(target):return target
	if body.is_player:return null
	var best:Node3D;var distance:=16000.0
	for foe in Game.live_hostiles_of(body):
		var d:float=body.global_position.distance_to(foe.global_position)
		if d<distance:best=foe;distance=d
	return best
func deploy(mark:Node3D=null)->bool:
	if deployed():
		return recall()
	if cooldown_left>0:
		if body.is_player:body.notice.emit("浮游炮冷却中 · %.1fs"%cooldown_left,1.3)
		return false
	if not body.alive or body.in_transform() or body.weapons_locked():return false
	target=mark;state=State.DEPLOYING;state_age=0;next_fin=0;shot_left=0
	for i in fins.size():fins[i].reset(true);fins[i].launch_from=_dock(i)
	Audio.play_3d("funnel_fire",body.global_position,-4)
	_sync_docks();return true
func cycle_mode()->void:
	mode=(mode+1)%2;shot_left=Spec.VOLLEY_INTERVAL if mode==Mode.VOLLEY else 0
	for fin in fins:fin.cancel_shot()
	_update_barrier()
func _dock(index:int)->Vector3:
	var marker:Node3D=body.model_root.find_child("Mount_nu_dock"+str(index),true,false) if is_instance_valid(body.model_root) else null
	return marker.global_position if marker!=null else body.global_position+body.global_basis*Vector3(-4,8+index,4)
func _center()->Vector3:return body.global_transform*body.rig_anchor("chest")
func barrier_active()->bool:
	return false
func orbit_point(index:int)->Vector3:
	if mode==Mode.DEFENSE:
		var directions:=[Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
		return _center()+body.global_basis*directions[index]*body.profile.target_height*1.8
	var center:Vector3=target.global_position if is_instance_valid(target) else _center()
	var angle:float=age*TAU/Spec.VOLLEY_INTERVAL+index*TAU/6
	if mode==Mode.VOLLEY:return center+Vector3(cos(angle)*500,250,sin(angle)*500)
	var radius:float=480+120*sin(age*.37+index*2.31)
	var height:float=sin(age*.73+index*1.71)*250
	return center+Vector3(cos(angle*.55+index)*radius,height,sin(angle*.55+index)*radius)
func tick(delta:float)->void:
	if delta<=0:return
	_tick_minovsky(delta)
	if state==State.DOCKED and cooldown_left<=0:energy=minf(energy+8.0*delta,Spec.ENERGY_MAX)
	if equipment_cd>0:
		equipment_cd=maxf(equipment_cd-delta,0)
		if equipment_cd<=0:
			bazooka_mag=Spec.BAZOOKA_MAG;bazooka_reload_left=0;_sync_equipment()
			if body.is_player:body.notice.emit("盾牌 / 火箭筒已恢复",1.3)
	age+=delta;state_age+=delta;bazooka_cd=maxf(bazooka_cd-delta,0);bazooka_pose_left=maxf(bazooka_pose_left-delta,0)
	if bazooka_reload_left>0:
		bazooka_reload_left=maxf(bazooka_reload_left-delta,0)
		if bazooka_reload_left<=0:bazooka_mag=Spec.BAZOOKA_MAG
	if is_instance_valid(body.model_root) and body.model_root.get_instance_id()!=last_model_id:_sync_docks()
	target=find_target()
	if not body.is_player and not visual_only and is_instance_valid(target):
		if state==State.DOCKED and cooldown_left<=0:deploy(target)
		if _hostile_missiles_present():use_minovsky()
	if state==State.RETURNING:
		for i in fins.size():
			if fins[i].alive:fins[i].global_position=fins[i].return_from.lerp(_dock(i),smoothstep(0,Spec.RETURN_TIME,state_age))
		if state_age>=Spec.RETURN_TIME:
			state=State.COOLDOWN_DOCKED if cooldown_left>0 else State.DOCKED
			for fin in fins:fin.hide();fin.deployed=false;fin.collision_layer=0
			_sync_docks()
	if cooldown_left>0:
		cooldown_left=maxf(cooldown_left-delta,0)
		if cooldown_left<=0:
			energy=Spec.ENERGY_MAX;destroyed_count=0;state_age=0
			var in_air:bool=state==State.WAITING
			state=State.ACTIVE if in_air else State.DOCKED
			for fin in fins:fin.reset(not in_air)
			shot_left=Spec.VOLLEY_INTERVAL if mode==Mode.VOLLEY else 0;_sync_docks()
		_update_barrier();return
	if state not in [State.DEPLOYING,State.ACTIVE]:_update_barrier();return
	energy=maxf(energy-Spec.DRAIN[mode]*delta,0)
	if energy<=0:
		_begin_cooldown(Spec.DEFENSE_COOLDOWN if mode==Mode.DEFENSE else Spec.COOLDOWN,false)
		return
	for i in fins.size():
		var fin=fins[i]
		if not fin.alive:continue
		var launch_age:float=state_age-i*Spec.LAUNCH_STAGGER
		if state==State.DEPLOYING and launch_age<0:continue
		if not fin.deployed:fin.activate(_dock(i));_sync_docks()
		fin.tick_shot(delta)
		if fin.frozen():continue
		var goal:=orbit_point(i)
		if state==State.DEPLOYING and launch_age<.8:
			var escape:Vector3=fin.launch_from+body.global_basis*Vector3(0,70 if i%2==0 else -70,45)
			var u:float=clampf(launch_age/.8,0,1)
			goal=fin.launch_from.lerp(escape,u).lerp(goal,u*u)
		fin.global_position=fin.global_position.move_toward(goal,maxf(10000.0*delta,fin.global_position.distance_to(goal)*minf(delta*8,1)))
		if launch_age>.5:fin.collision_layer=Spec.FIN_HIT_LAYER
		if is_instance_valid(target):
			var direction:Vector3=fin.global_position.direction_to(target.global_position)
			if absf(direction.dot(Vector3.UP))>.99:direction=(direction+Vector3.RIGHT*.03).normalized()
			fin.global_basis=Basis.looking_at(direction,Vector3.UP)
	if state==State.DEPLOYING and state_age>(Spec.FIN_COUNT-1)*Spec.LAUNCH_STAGGER+.8:
		state=State.ACTIVE;state_age=0;shot_left=Spec.VOLLEY_INTERVAL if mode==Mode.VOLLEY else 0
	if state==State.ACTIVE and mode!=Mode.DEFENSE and is_instance_valid(target) and not body.weapons_locked():
		shot_left-=delta
		if shot_left<=0:
			if mode==Mode.VOLLEY:
				for fin in fins:
					if fin.alive:fin.prepare(target)
				shot_left+=Spec.VOLLEY_INTERVAL
			else:
				for attempt in fins.size():
					var chosen:int=next_fin;next_fin=(next_fin+1)%fins.size()
					if fins[chosen].alive:fins[chosen].prepare(target);break
				shot_left+=Spec.SEQUENCE_INTERVAL
	_update_barrier()
func _begin_cooldown(seconds:float,recall:bool)->void:
	energy=0;cooldown_left=maxf(cooldown_left,seconds);cooldown_total=maxf(seconds,cooldown_left);state_age=0
	state=State.RETURNING if recall else State.WAITING
	for fin in fins:fin.cancel_shot();fin.return_from=fin.global_position
	_update_barrier()
func fin_destroyed(_index:int)->void:
	destroyed_count+=1
	if destroyed_count>=2 and state not in [State.RETURNING,State.COOLDOWN_DOCKED]:_begin_cooldown(Spec.COOLDOWN,true)
func record_shot(index:int,from:Vector3,direction:Vector3)->void:
	shot_log.append({"index":index,"time":age,"mode":mode})
	if shot_log.size()>64:shot_log.pop_front()
	if not visual_only:body._net_report_fire("zorin_fin",from,direction)
func _sync_docks()->void:
	if not is_instance_valid(body.model_root):return
	last_model_id=body.model_root.get_instance_id()
	for i in Spec.FIN_COUNT:
		var show_dock:bool=not fins[i].deployed and fins[i].alive
		for mesh in body.model_root.find_children("ZorinDock"+str(i)+"_*","MeshInstance3D",true,false):mesh.visible=show_dock
func reload_bazooka()->bool:
	if bazooka_reload_left>0 or bazooka_mag>=Spec.BAZOOKA_MAG:return false
	bazooka_reload_left=Spec.BAZOOKA_RELOAD;return true
func fire_bazooka(mark:Node3D=null)->bool:
	if not body.alive or body.weapons_locked() or equipment_cd>0 or bazooka_reload_left>0 or bazooka_cd>0 or bazooka_mag<=0:return false
	var marker:Node3D=body.model_root.find_child("Mount_nu_bazooka",true,false) if is_instance_valid(body.model_root) else null
	var from:Vector3=marker.global_position if marker!=null else body.global_position+body.forward()*10
	var direction:Vector3=body.aim_dir if body.aim_dir.length_squared()>.1 else body.forward()
	if is_instance_valid(mark):
		var velocity:Vector3=mark.fm.velocity if mark is FlightBody else Vector3.ZERO
		direction=from.direction_to(mark.global_position+velocity*minf(from.distance_to(mark.global_position)/Spec.BAZOOKA_SPEED,1.5))
	var rocket:=Missile.spawn(body.projectile_container,from,direction,null,body,0.0 if visual_only else Spec.BAZOOKA_DAMAGE*body.damage_mult,Missile.Trail.LOW)
	rocket.speed=Spec.BAZOOKA_SPEED;rocket.max_speed=Spec.BAZOOKA_SPEED;rocket.launch_vel=Vector3.ZERO
	bazooka_mag-=1;bazooka_cd=Spec.BAZOOKA_INTERVAL;bazooka_pose_left=.5
	if bazooka_mag<=0:bazooka_reload_left=Spec.BAZOOKA_RELOAD
	body.play_model_action("shoot",true);Audio.play_3d("funnel_fire",from,-3)
	if not visual_only:body._net_report_fire("nu_bazooka",from,direction)
	return true
func _build_barrier()->void:
	barrier=MeshInstance3D.new();barrier.name="NuFinBarrier";add_child(barrier)
	barrier_edges=MeshInstance3D.new();barrier_edges.name="NuFinBarrierEdges";add_child(barrier_edges)
	var mesh:=ImmediateMesh.new();var lines:=ImmediateMesh.new()
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.cull_mode=BaseMaterial3D.CULL_DISABLED;mat.albedo_color=Color(1,.25,.66,.025)
	var edge:=mat.duplicate();edge.albedo_color=Color(1,.4,.77,.5)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,mat);lines.surface_begin(Mesh.PRIMITIVE_LINES,edge)
	for x in [-1,1]:
		for y in [-1,1]:
			for z in [-1,1]:
				var points:=[Vector3(x,0,0),Vector3(0,y,0),Vector3(0,0,z)]
				for point in points:mesh.surface_add_vertex(point)
				for i in 3:lines.surface_add_vertex(points[i]);lines.surface_add_vertex(points[(i+1)%3])
	mesh.surface_end();lines.surface_end();barrier.mesh=mesh;barrier_edges.mesh=lines;_update_barrier()
func _update_barrier()->void:
	if barrier==null:return
	var active:=barrier_active();barrier.visible=active;barrier_edges.visible=active
	var xf:=Transform3D(body.global_basis*body.profile.target_height*1.8,_center())
	barrier.global_transform=xf;barrier_edges.global_transform=xf
func _physics_process(delta:float)->void:
	if not is_instance_valid(body) or not body.alive:
		for fin in fins:
			if is_instance_valid(fin):fin.queue_free()
		barrier.hide();barrier_edges.hide();set_physics_process(false);return
	if visual_only:_tick_minovsky(delta);_update_barrier();return
	if Game.phase==Game.Phase.FIGHT:tick(delta)
func _exit_tree()->void:
	for fin in fins:
		if is_instance_valid(fin):fin.queue_free()

var charge_left: Array=[0.0,0.0,0.0]
const BARRIER_COOLDOWN:=5.0
const BARRIER_RECHARGE:=10.0
var barrier_cd:=0.0
var barrier_left:=0.0
var waves: Array[MeshInstance3D]=[]
const PAK_SPEED:=14000.0
func recall()->bool:
	if state==State.RETURNING:return false
	state=State.RETURNING;state_age=0
	for fin in fins:fin.cancel_shot();fin.return_from=fin.global_position
	return true
func charge_remaining()->float:
	var remaining:=BARRIER_RECHARGE
	var pending:=false
	for value in charge_left:
		if float(value)>0:
			pending=true;remaining=minf(remaining,float(value))
	return remaining if pending else 0.0
func charge_progress()->float:
	return 1.0-charge_remaining()/BARRIER_RECHARGE
func cooldown_progress()->float:
	return 1.0-barrier_cd/BARRIER_COOLDOWN
func charges()->int:
	var count:=0
	for value in charge_left:
		if value<=0:count+=1
	return count
func _hostile_missiles_present()->bool:
	for missile in get_tree().get_nodes_in_group("missiles"):
		if missile is Missile and is_instance_valid(missile.shooter) and body.is_hostile_to(missile.shooter):return true
	return false
func use_minovsky()->bool:
	if not body.alive or body.weapons_locked() or barrier_cd>0 or charges()==0:return false
	for i in charge_left.size():
		if charge_left[i]<=0:charge_left[i]=BARRIER_RECHARGE;break
	barrier_cd=BARRIER_COOLDOWN;barrier_left=4.0
	body.ifield_hp=minf(body.ifield_max,body.ifield_hp+body.ifield_max*.07)
	_sync_minovsky();_intercept_minovsky()
	if not visual_only:body._net_report_fire("zorin_barrier",body.global_position,body.forward())
	Audio.play_3d("ui_item",body.global_position,-4)
	return true
func remote_minovsky()->void:
	barrier_left=4.0;_sync_minovsky();_intercept_minovsky()
func _intercept_minovsky()->void:
	if barrier_left<=0 or not body.alive:return
	for missile in get_tree().get_nodes_in_group("missiles"):
		if missile is Missile and not missile.is_queued_for_deletion() and is_instance_valid(missile.shooter) and body.is_hostile_to(missile.shooter):
			missile._detonate(true,null,false) # Explode in place, never retarget or damage the victim.
func _tick_minovsky(delta:float)->void:
	# Only the portion of this frame after the shared cooldown advances charges.
	var recharge_delta:=maxf(0.0,delta-barrier_cd)
	barrier_cd=maxf(0,barrier_cd-delta)
	for i in charge_left.size():charge_left[i]=maxf(0,float(charge_left[i])-recharge_delta)
	barrier_left=maxf(0,barrier_left-delta);_sync_minovsky();_intercept_minovsky()
func _sync_minovsky()->void:
	if waves.is_empty() and barrier_left>0:
		for i in 3:
			var wave:=MeshInstance3D.new();wave.name="MinovskyWave"+str(i)
			var mesh:=TorusMesh.new();mesh.inner_radius=.985;mesh.outer_radius=1.0;mesh.rings=64;mesh.ring_segments=6
			wave.mesh=mesh;wave.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;mat.emission_enabled=true;mat.emission=Color(.3,.7,1);mat.emission_energy_multiplier=1.2
			wave.material_override=mat;add_child(wave);waves.append(wave)
	for i in waves.size():
		var wave:=waves[i];wave.visible=barrier_left>0 and body.alive
		if not wave.visible:continue
		var t:=fposmod(4.0-barrier_left+float(i)*.28,1.0)
		wave.scale=Vector3.ONE*(body.profile.target_height*(.9+t*9.0))
		wave.rotation=Vector3(PI*.5 if i!=1 else 0,0,float(i)*PI/3)
		wave.material_override.albedo_color=Color(.35,.75,1,(1-t)*minf(barrier_left,1.0)*.42)
func fire_primary()->bool:
	if not body.alive or body.in_transform() or body.weapons_locked() or body.rifle_reloading or body.rifle_cooldown>0 or body.rifle_mag<=0:return false
	var from:Vector3=body.global_transform*body._rifle_muzzle_local(0)
	var direction:Vector3=from.direction_to(body.rifle_aim_point(from,find_target(),not body.is_player))
	if not body.is_player:
		var mark:=find_target()
		if is_instance_valid(mark):direction=from.direction_to(mark.global_position+mark.velocity*minf(from.distance_to(mark.global_position)/PAK_SPEED,1.0))
	Projectile.spawn(body.projectile_container,from,direction,body,body.profile.rifle_damage*body.damage_mult*FlightBody.RIFLE_DAMAGE_MULT,Color(1,.82,.42),Damage.Type.VULCAN,PAK_SPEED,1.5,1.5)
	body.rifle_mag-=1;body.rifle_cooldown=body.profile.rifle_interval
	if body.rifle_mag<=0:body.reload_rifle()
	body.gun_fired.emit();body.play_model_action("shoot",true)
	Audio.play_3d("vulcan",from,-2)
	if body.is_player:Game.shots_fired+=1;Game.gun_shots+=1
	if not visual_only:body._net_report_fire("zorin_pak",from,direction)
	return true
func input(_delta:float)->void:
	if body.weapons_locked():return
	var mark:Node3D=body.lock.target if body.lock!=null else null
	if Input.is_action_just_pressed("switch_weapon"):body.switch_weapon()
	if Input.is_action_pressed("fire_primary"):
		if body.current_slot()=="saber":body.try_saber(mark)
		else:fire_primary()
	if Input.is_action_pressed("fire_gun"):body.fire_gun(true,mark)
	if Input.is_action_just_pressed("reload"):body.reload_rifle()
	if Input.is_action_just_pressed("shield"):body.raise_shield()
	if Input.is_action_pressed("fire_secondary"):body.fire_funnel(mark)
	if Input.is_action_just_pressed("fire_missile"):deploy(mark)
	if Input.is_action_just_pressed("flares"):use_minovsky()


## Capture the pilot's axes before assistance, collision avoidance or steering trim changes them.
func capture_pilot_input()->void:
	pilot_intent=Vector3.ZERO;pilot_intent_valid=true
	if not body.alive or not body.controls_enabled:return
	var forward:=Input.get_axis("pitch_nose_up","pitch_nose_down")
	var right:=Input.get_axis("roll_left","roll_right")
	var up:=Input.get_axis("yaw_right","yaw_left")
	var device:int=body.active_joypad()
	if device>=0:
		forward-=body._dead(Input.get_joy_axis(device,JOY_AXIS_LEFT_Y))
		right+=body._dead(Input.get_joy_axis(device,JOY_AXIS_LEFT_X))
		up-=body._dead(Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y))
	pilot_intent=Vector3(clampf(right,-1,1),clampf(up,-1,1),-clampf(forward,-1,1)).limit_length(1.0)
