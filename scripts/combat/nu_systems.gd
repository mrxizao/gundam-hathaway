extends Node3D
const Spec:=preload("res://scripts/data/nu_spec.gd")
const Fin:=preload("res://scripts/combat/nu_fin.gd")
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
var bazooka_mag:=Spec.BAZOOKA_MAG
var bazooka_reload_left:=0.0
var bazooka_cd:=0.0
var bazooka_pose_left:=0.0
var last_model_id:=0
var remote_slot:="rifle"
var remote_scope:=false
var equipment_cd:=0.0
func _ready()->void:
	process_mode=Node.PROCESS_MODE_PAUSABLE;name="NuSystems"
	visual_only=body.has_method("apply_state") or (Net.role==Net.Role.CLIENT and body.get("net_unit_id")!=null)
	for i in Spec.FIN_COUNT:
		var fin:=Fin.new();fin.controller=self;fin.index=i;body.projectile_container.add_child(fin);fins.append(fin)
	_build_barrier();_sync_docks()
func deployed()->bool:return state in [State.DEPLOYING,State.ACTIVE,State.WAITING,State.RETURNING]
func mode_name()->String:return Spec.MODE_NAMES[mode]
func status_text()->String:
	return "CD %.1fs"%cooldown_left if cooldown_left>0 else "%03d%%"%roundi(energy)
func bazooka_status()->String:
	if equipment_cd>0:return "CD %.1fs"%equipment_cd
	return "装填 %.1fs"%bazooka_reload_left if bazooka_reload_left>0 else "%02d / %d"%[bazooka_mag,Spec.BAZOOKA_MAG]
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
	return {"state":state,"mode":mode,"energy":energy,"cd":cooldown_left,"total":cooldown_total,"lost":destroyed_count,"fins":actors,"slot":body.current_slot() if body.has_method("current_slot") else "rifle","scope":body.precision_view_active() if body.has_method("precision_view_active") else false,"shield":body.shield_up,"equipment_cd":equipment_cd,"unlock":body.unlockable_seconds_left()}
func apply_snapshot(data:Dictionary)->void:
	if data.is_empty():return
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
		if body.is_player:body.notice.emit("浮游炮已经发射",1.5)
		return false
	if cooldown_left>0:
		if body.is_player:body.notice.emit("浮游炮冷却中 · %.1fs"%cooldown_left,1.3)
		return false
	if not body.alive or body.in_transform() or body.weapons_locked():return false
	target=mark;state=State.DEPLOYING;state_age=0;next_fin=0;shot_left=0
	for i in fins.size():fins[i].reset(true);fins[i].launch_from=_dock(i)
	Audio.play_3d("funnel_fire",body.global_position,-4)
	_sync_docks();return true
func cycle_mode()->void:
	mode=(mode+1)%3;shot_left=Spec.VOLLEY_INTERVAL if mode==Mode.VOLLEY else 0
	for fin in fins:fin.cancel_shot()
	_update_barrier()
func _dock(index:int)->Vector3:
	var marker:Node3D=body.model_root.find_child("Mount_nu_dock"+str(index),true,false) if is_instance_valid(body.model_root) else null
	return marker.global_position if marker!=null else body.global_position+body.global_basis*Vector3(-4,8+index,4)
func _center()->Vector3:return body.global_transform*body.rig_anchor("chest")
func barrier_active()->bool:
	if mode!=Mode.DEFENSE or state!=State.ACTIVE or energy<=0 or cooldown_left>0 or not body.alive:return false
	var center:=_center();var radius:float=body.profile.target_height*1.8
	for fin in fins:
		if fin.alive and fin.global_position.distance_to(center)>radius*1.7:return false
	return destroyed_count<2
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
	if equipment_cd>0:
		equipment_cd=maxf(equipment_cd-delta,0)
		if equipment_cd<=0:
			bazooka_mag=Spec.BAZOOKA_MAG;bazooka_reload_left=0;_sync_equipment()
			if body.is_player:body.notice.emit("盾牌 / 火箭筒已恢复",1.3)
	age+=delta;state_age+=delta;bazooka_cd=maxf(bazooka_cd-delta,0);bazooka_pose_left=maxf(bazooka_pose_left-delta,0)
	if bazooka_reload_left>0:
		bazooka_reload_left=maxf(bazooka_reload_left-delta*body.combat_buffs.reload_rate(),0)
		if bazooka_reload_left<=0:bazooka_mag=Spec.BAZOOKA_MAG
	if is_instance_valid(body.model_root) and body.model_root.get_instance_id()!=last_model_id:_sync_docks()
	target=find_target()
	if not body.is_player and not visual_only and is_instance_valid(target):
		if state==State.DOCKED and cooldown_left<=0:deploy(target)
		if target.global_position.distance_to(body.global_position)<4500 and bazooka_cd<=0 and bazooka_reload_left<=0:fire_bazooka(target)
	if state==State.RETURNING:
		for i in fins.size():
			if fins[i].alive:fins[i].global_position=fins[i].return_from.lerp(_dock(i),smoothstep(0,Spec.RETURN_TIME,state_age))
		if state_age>=Spec.RETURN_TIME:
			state=State.COOLDOWN_DOCKED
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
	if not body.combat_buffs.active(): energy=maxf(energy-Spec.DRAIN[mode]*delta,0)
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
		shot_left-=delta*(body.combat_buffs.FIN_RATE if body.combat_buffs.active() else 1.0)
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
	if not visual_only:body._net_report_fire("nu_fin",from,direction)
func _sync_docks()->void:
	if not is_instance_valid(body.model_root):return
	last_model_id=body.model_root.get_instance_id()
	for i in Spec.FIN_COUNT:
		var show_dock:bool=not fins[i].deployed and fins[i].alive
		for mesh in body.model_root.find_children("NuDock"+str(i)+"_*","MeshInstance3D",true,false):mesh.visible=show_dock
func reload_bazooka()->bool:
	if bazooka_reload_left>0 or bazooka_mag>=Spec.BAZOOKA_MAG:return false
	bazooka_reload_left=Spec.BAZOOKA_RELOAD;return true
func fire_bazooka(mark:Node3D=null)->bool:
	if not body.alive or body.weapons_locked() or equipment_cd>0 or bazooka_reload_left>0 or bazooka_cd>0 or bazooka_mag<=0:return false
	var marker:Node3D=body.model_root.find_child("Mount_nu_bazooka",true,false) if is_instance_valid(body.model_root) else null
	var from:Vector3=marker.global_position if marker!=null else body.global_position+body.forward()*10
	var direction:Vector3=body.aim_dir if body.aim_dir.length_squared()>.1 else body.forward()
	var rocket:=preload("res://scripts/combat/nu_bazooka.gd").spawn(body.projectile_container,from,direction,body,0.0 if visual_only else Spec.BAZOOKA_DAMAGE*body.damage_mult,mark)
	direction=-rocket.global_basis.z
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
	if visual_only:_update_barrier();return
	if Game.phase==Game.Phase.FIGHT:tick(delta)
func _exit_tree()->void:
	for fin in fins:
		if is_instance_valid(fin):fin.queue_free()
