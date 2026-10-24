extends RefCounted
## Super-hard aces only. Observe actual weapon/boost signals; all actions still
## use FlightBody's ammunition, cooldown, shield and collision gates.
var phase:=0
var _owner:WeakRef
var _target:WeakRef
var _shot_left:=0.0
var _reaction_left:=0.0
var _target_dash_left:=0.0
var _counter_left:=0.0
var _sensor_left:=0.0
var _threat:WeakRef
var _side:=1.0
var _side_left:=0.0
var _missile_cd:=0.0
var _combo_cd:=0.0
var _cannon_setup_left:=0.0
var _cannon_reserved:=false

func enabled(ai)->bool:
	return ai._super_hard() and ai._is_ace() and ai.alive and not ai.scripted \
		and not ai.is_carried() and ai._escape_timer<=0

func target()->FlightBody:
	return _target.get_ref() as FlightBody if _target!=null else null

func detach()->void:
	var old:=target()
	if is_instance_valid(old):
		if old.beam_fired.is_connected(_on_beam):old.beam_fired.disconnect(_on_beam)
		if old.quick_boost_started.is_connected(_on_dash):old.quick_boost_started.disconnect(_on_dash)
	_target=null;_owner=null;_threat=null
	_shot_left=0;_reaction_left=0;_target_dash_left=0;_counter_left=0

func tick(ai,delta:float)->void:
	if not enabled(ai):detach();return
	var next:FlightBody=ai._target
	if next!=target():
		detach()
		if is_instance_valid(next):
			_owner=weakref(ai);_target=weakref(next)
			_side=1.0 if ai._hard_rng.randf()>.5 else -1.0;_side_left=3.2-.4*phase
			next.beam_fired.connect(_on_beam);next.quick_boost_started.connect(_on_dash)
	phase=maxi(phase,2 if ai.hp_ratio()<=.30 else (1 if ai.hp_ratio()<=.60 else 0))
	_shot_left=maxf(0,_shot_left-delta);_reaction_left=maxf(0,_reaction_left-delta)
	_counter_left=maxf(0,_counter_left-delta)
	var was_dashing:bool=_target_dash_left>0
	_target_dash_left=maxf(0,_target_dash_left-delta)
	if was_dashing and _target_dash_left<=0:_counter_left=1.15
	_missile_cd=maxf(0,_missile_cd-delta);_combo_cd=maxf(0,_combo_cd-delta)
	_cannon_setup_left=maxf(0,_cannon_setup_left-delta)
	_side_left-=delta
	if _side_left<=0:
		_side=-_side;_side_left=3.2-.4*phase
	_sensor_left-=delta
	if _sensor_left<=0:
		_sensor_left=.12 if phase<2 else .08
		_threat=null
		var nearest:=INF
		for missile in ai.incoming_missiles():
			if not is_instance_valid(missile) or missile.is_queued_for_deletion():continue
			var gap:float=ai.global_position.distance_to(missile.global_position)
			if gap<nearest:nearest=gap;_threat=weakref(missile)
	if is_instance_valid(next) and ai.cannon_ready() and ai._hard_cannon_cd<=0 \
		and ai.lock!=null and ai.lock.locked and ai.lock.target==next:
		if not _cannon_reserved and ai.global_position.distance_to(next.global_position)<ai.beam_range \
			and Ballistics.angle_off_boresight(ai.forward(),next.global_position-ai.global_position)<30 and line_clear(ai):
			_cannon_setup_left=.75;_cannon_reserved=true
	else:
		_cannon_reserved=false;_cannon_setup_left=0

func _on_beam()->void:
	var ai:FlightBody=_owner.get_ref() as FlightBody if _owner!=null else null
	var foe:=target()
	if not is_instance_valid(ai) or not is_instance_valid(foe):return
	var to_ai:Vector3=foe.global_position.direction_to(ai.global_position)
	var locked:bool=false
	var lock=foe.get("lock")
	if lock is LockOnSystem:locked=lock.target==ai and lock.locked
	if foe.global_position.distance_to(ai.global_position)>6000 or (foe.forward().dot(to_ai)<.94 and not locked) or not line_clear(ai):return
	if _shot_left<=0:_reaction_left=[.18,.13,.09][phase]
	_shot_left=.55

func _on_dash(_dir:Vector3)->void:
	_target_dash_left=FlightBody.QB_TIME

func heavy(ai)->bool:
	return ai.profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL]

func preferred_range(ai)->float:
	var foe:=target()
	if is_instance_valid(foe) and foe.shield_up and foe.profile.shield_reduction>0 and ai.profile.has_saber and not heavy(ai) and ai._saber_is_viable():
		return ai.saber_range*.85
	var range_m:=1300.0
	match ai.profile.id:
		SuitProfile.Id.PENELOPE:range_m=1300.0 if ai.profile.form==0 else 1000.0
		SuitProfile.Id.ARIZEUS:range_m=1400.0 if ai.profile.form!=SuitProfile.ArizeusForm.CORE_NU else 950.0
		SuitProfile.Id.REGZ_CUSTOM:range_m=1850.0
		SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL:range_m=2800.0
		SuitProfile.Id.GP03S:range_m=950.0
	return minf(range_m,ai.beam_range*.85)*([1.0,.95,.90][phase] if heavy(ai) else [1.0,.88,.72][phase])

func opening(ai)->bool:
	var foe:=target()
	return is_instance_valid(foe) and (_counter_left>0 or foe.rifle_reloading or foe.is_staggered())

func evading(ai)->bool:
	if _shot_left>0 and _reaction_left<=0:return true
	var missile:Node3D=_threat.get_ref() as Node3D if _threat!=null else null
	if is_instance_valid(missile):
		var speed:float=missile.get("speed")
		if ai.global_position.distance_to(missile.global_position)<clampf(speed*.7,450,2600):return true
	var foe:=target()
	return is_instance_valid(foe) and foe.saber_active() and ai.global_position.distance_to(foe.global_position)<1800

func _side_dir(radial:Vector3)->Vector3:
	var side:=radial.cross(Vector3.UP).normalized()
	return (side if not side.is_zero_approx() else Vector3.RIGHT)*_side

func pursuit(ai)->Vector3:
	var foe:=target()
	if not is_instance_valid(foe):return ai.forward()
	var gap:float=ai.global_position.distance_to(foe.global_position)
	var aim:Vector3=Ballistics.beam_lead_point(ai.global_position,foe.global_position,foe.fm.velocity)
	if gap>ai.beam_range:
		var time:float=clampf(gap/maxf(ai.fm.ab_speed,1),.15,1.4)
		aim=foe.global_position+foe.fm.velocity*time*.75
	return ai.global_position.direction_to(aim)

func direction(ai)->Vector3:
	var radial:=pursuit(ai)
	return (radial+_side_dir(radial)*(.45 if evading(ai) else .065+.015*phase)).normalized()

func dash_direction(ai,dist:float)->Vector3:
	if is_instance_valid(ai.active_cannon) or ai._hard_salvo_left>0:return Vector3.ZERO
	if not evading(ai) and dist<ai.saber_range and ai.profile.has_saber and ai.saber_cooldown<=0 \
		and ai.lock!=null and ai.lock.locked and ai.lock.target==target() and ai._saber_is_viable():return Vector3.ZERO
	var radial:=pursuit(ai)
	var side:=_side_dir(radial)
	var preferred:=preferred_range(ai)
	var want:=side
	if dist>15000:want=ai.global_position.direction_to(ai._target.global_position)
	elif evading(ai):
		want=(side+Vector3.UP*.30*_side).normalized()
		var foe:=target()
		if is_instance_valid(foe) and foe.saber_active():want=(-radial+side*.4).normalized()
	elif dist<preferred*.55:want=(-radial+side*.25).normalized()
	elif dist>preferred*1.3 or (opening(ai) and not heavy(ai) and dist>preferred*.8):want=(radial+side*.15).normalized()
	var choices:Array[Vector3]=[want,side,-side,(side+Vector3.UP*.4).normalized(),Vector3.UP,radial,-radial]
	for option in choices:
		if ai._hard_dash_clear(option):return option
	return Vector3.ZERO

func throttle(ai,dist:float)->void:
	var preferred:=preferred_range(ai)
	if dist<preferred*1.2 and (not opening(ai) or heavy(ai)):
		ai.fm.throttle=clampf(dist/preferred-.20,.30,.95)
		ai.fm.boosting=false;ai.fm.super_boost=false
	elif opening(ai) and not heavy(ai):
		ai.fm.boosting=true;ai.fm.super_boost=true
	if is_instance_valid(ai.active_cannon):
		ai.fm.throttle=.35;ai.fm.boosting=false;ai.fm.super_boost=false

func drive_form(ai)->void:
	var foe:=target()
	if not is_instance_valid(foe) or ai._form_timer>0 or ai.in_transform() or ai.saber_active() or is_instance_valid(ai.active_cannon):return
	var dist:float=ai.global_position.distance_to(foe.global_position)
	var want:int=ai.profile.form
	if ai.profile.id==SuitProfile.Id.ARIZEUS and ai.profile.form!=SuitProfile.ArizeusForm.CORE_NU:
		if dist>3500:want=SuitProfile.ArizeusForm.CRUISE
		elif dist<2200:want=SuitProfile.ArizeusForm.NORMAL
	elif ai.profile.id==SuitProfile.Id.REGZ_CUSTOM:
		if dist>3500 or (dist>1300 and ai.cannon_cd_left<=0):want=1
		elif dist<1100 or ai.cannon_cd_left>0:want=0
	if want!=ai.profile.form and ai.switch_form(want,true):ai._form_timer=2.5

func line_clear(ai)->bool:
	var foe:=target()
	if not is_instance_valid(foe) or not ai.is_inside_tree():return false
	var query:=PhysicsRayQueryParameters3D.create(ai.global_position,foe.global_position,FlightBody.WORLD_LAYER)
	query.exclude=[ai.get_rid()]
	return ai.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func hold_rifle(ai)->bool:
	var foe:=target()
	return is_instance_valid(foe) and ((foe.shield_up and foe.profile.shield_reduction>0) or not line_clear(ai) or (_cannon_setup_left>0 and ai.cannon_ready()))

func fire_missiles(ai,dist:float)->void:
	if _missile_cd>0 or ai._hard_salvo_left>0 or not ai.profile.has_missiles or ai.lock==null \
		or not ai.lock.locked or ai.lock.target!=target() or dist<=320 or dist>=ai.missile_range or not line_clear(ai):return
	# Keep one full salvo in reserve while its 40% roll is eligible. Interception
	# may still spend these rounds when survival takes priority.
	if ai.hp_ratio()<.5 and ai._hard_salvo_cd<=0 and ai.funnel_count>=PlayerController.FULL_SALVO_COUNT \
		and ai.funnel_count<PlayerController.FULL_SALVO_COUNT+6:return
	var interval:float=missile_interval(ai)
	if ai.fire_funnel(target(),interval):
		_missile_cd=interval
		if _combo_cd<=0:_counter_left=.9;_combo_cd=4.0-.8*phase

func cannon_cooldown(ai)->float:
	return maxf(ai.profile.cannon_cooldown,[32.0,26.0,22.0][phase])
func salvo_cooldown()->float:
	return [150.0,120.0,95.0][phase]
func dash_cooldown()->float:
	return [.85,.75,.65][phase]

func dash_duration(ai,dir:Vector3)->float:
	var foe:=target()
	if not is_instance_valid(foe):return FlightBody.QB_TIME
	var radial:Vector3=ai.global_position.direction_to(foe.global_position)
	if dir.dot(radial)<.6:return FlightBody.QB_TIME
	var gap:float=maxf(0,ai.global_position.distance_to(foe.global_position)-preferred_range(ai)*.65)
	return clampf(gap/maxf(ai.profile.player_boost_speed()*FlightBody.QB_SPEED_MULT,1),.12,FlightBody.QB_TIME)

func missile_interval(ai)->float:
	if ai.profile.id==SuitProfile.Id.PENELOPE and ai.profile.form==0:
		return [.24,.19,.14][phase]
	return [.30,.24,.18][phase]
