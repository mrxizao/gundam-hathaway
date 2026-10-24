extends RefCounted
const DAMAGE_MULT := 2.405
const IMPACT_TIME := 3.0
const SLOW_TIME := 4.0
const BAR_TIME := 2.0
const WINDOW := 0.2
var impact_left := 0.0
var slow_left := 0.0
var speed_cap := 0.0
var attacker: WeakRef
var attack_serial := -1
var elapsed := BAR_TIME
var center := 1.0
var attempted := false
var window_started := false
var result := ""
var shield_armed := false
func incoming():
	return attacker.get_ref() if attacker != null else null
func warn(body, foe) -> void:
	if not is_instance_valid(foe) or not foe.is_hostile_to(body): return
	if incoming()==foe and attack_serial==foe._melee_attack_serial: return
	if elapsed < BAR_TIME and is_instance_valid(incoming()) and incoming().saber_active(): return
	attacker=weakref(foe)
	attack_serial=foe._melee_attack_serial
	elapsed=0.0
	attempted=false
	window_started=false
	result=""
	shield_armed=false
	center=clampf(arrival(body,foe)-WINDOW*0.5,0.10,1.90)
func arrival(body, foe) -> float:
	var to:Vector3=body.global_position-foe.global_position
	var closing:float=maxf((foe.fm.velocity-body.fm.velocity).dot(to.normalized()),foe.profile.saber_dash_speed)
	var windup:float=maxf(0.20-(foe.saber_dash_seconds()-foe.saber_timer),0.0)
	return windup+maxf(to.length()-body.CLASH_RANGE,0.0)/maxf(closing,1.0)
func can_guard(body) -> bool:
	var foe=incoming()
	return impact_left<=0 and elapsed<BAR_TIME and not attempted and is_instance_valid(foe) and foe.alive and foe.saber_active() and foe.is_hostile_to(body) and absf(elapsed-center)<=WINDOW*0.5+0.000001
func press(body) -> bool:
	var success:=can_guard(body)
	attempted=true
	result="格挡成功" if success else "时机未中"
	if success:
		var foe=incoming()
		body._net_report_fire("saber_parry",body.global_position,(foe.global_position-body.global_position).normalized())
		body._begin_clash(foe)
	return success
func tick(body, delta:float) -> void:
	impact_left=maxf(impact_left-delta,0.0)
	slow_left=maxf(slow_left-delta,0.0)
	if slow_left<0.000001:slow_left=0.0
	if impact_left<0.000001:impact_left=0.0
	if shield_armed and (not body.shield_up or not is_instance_valid(incoming()) or not incoming().saber_active()): shield_armed=false
	elapsed=minf(elapsed+delta,BAR_TIME)
	var foe=incoming()
	if is_instance_valid(foe) and foe.alive and foe.saber_active() and elapsed<BAR_TIME and not attempted:
		# Track actual approach so the green region remains fair if either unit moves.
		if not window_started:
			center=clampf(elapsed+arrival(body,foe)-WINDOW*0.5,0.10,1.90)
			if elapsed>=center-WINDOW*0.5:window_started=true
	if elapsed>=BAR_TIME:
		for other in Game.live_hostiles_of(body):
			if not other.has_method("saber_active") or not other.saber_active():continue
			var to:Vector3=body.global_position-other.global_position
			var closing:float=(other.fm.velocity-body.fm.velocity).dot(to.normalized())
			if closing>200 and to.length()<closing*BAR_TIME+body.CLASH_RANGE and other.forward().dot(to.normalized())>0.5:
				warn(body,other)
				break
func slow(body) -> void:
	var fresh := slow_left<=0.0
	slow_left=SLOW_TIME
	if fresh:
		speed_cap=maxf(maxf(body.fm.speed,body.velocity.length()),body.fm.velocity.length())*0.10
		body.velocity*=0.10
		body.fm.velocity*=0.10
		body.fm.speed=minf(body.fm.speed,speed_cap)
func hit(body) -> void:
	impact_left=IMPACT_TIME
	slow(body)
	# A carried rider moves with the shared platform; slow its pilot as well,
	# while only the struck rider loses weapon access.
	if body.is_carried() and is_instance_valid(body.carried_by):
		body.carried_by.melee_guard.slow(body.carried_by)
	if elapsed<BAR_TIME:
		result="被近战命中"
		attempted=true

	body.abort_saber()
	body._qb_timer=0.0
	body.translate_dash=false
	body.fm.super_boost=false
	# Ranged weapon charging/firing continues during saber-only recovery.
func limit(body) -> void:
	if slow_left<=0:return
	body.velocity=body.velocity.limit_length(speed_cap)
	body.fm.velocity=body.fm.velocity.limit_length(speed_cap)
	body.fm.speed=minf(body.fm.speed,speed_cap)

static func remote_attack(body, target, direction:Vector3) -> void:
	body._melee_attack_serial+=1
	body.saber_state=body.SaberState.CHARGE
	body.saber_timer=body.saber_dash_seconds()
	body._saber_visual_clock=0.0
	body.saber_target=target
	body.fm.velocity=direction.normalized()*body.profile.saber_dash_speed
	body.play_model_action("slash")
	body._show_blade()
	if is_instance_valid(target):target.melee_guard.warn(target,body)
static func remote_parry(defender) -> void:
	for body in Game.units:
		if not is_instance_valid(body) or body.has_method("apply_state") or not body.saber_active():continue
		if body.saber_target==defender:
			body._begin_clash(defender)
			return

func defense_prompt_active(body) -> bool:
	var foe=incoming()
	return body.alive and elapsed<BAR_TIME and is_instance_valid(foe) and foe.alive and foe.saber_active() and foe.is_hostile_to(body)

func shield_available(body) -> bool:
	return impact_left<=0.0 and not attempted and not body.has_pedal() and not body.is_carried() and defense_prompt_active(body)

func shield_press(body) -> bool:
	if not body.shield_up or not shield_available(body): return false
	if body.saber_active(): body.abort_saber()
	shield_armed=true
	attempted=true
	result="举盾防御"
	body._net_report_fire("saber_shield",body.global_position,body.forward())
	return true

func consume_shield(body,source: Node3D) -> bool:
	if not shield_armed or not body.shield_up or not is_instance_valid(source) or source!=incoming(): return false
	if source._melee_attack_serial!=attack_serial: return false
	shield_armed=false
	result="举盾防御成功"
	if source.has_method("abort_saber"): source.abort_saber()
	if source.model_fsm!=null: source.model_fsm.interrupt_melee()
	body.play_model_action("shield")
	body._net_report_fire("saber_shield_block",body.global_position,body.forward())
	if is_instance_valid(body.projectile_container): FX.hit_spark(body.projectile_container,body.global_position,1.0)
	return true

static func remote_shield(body,blocked: bool) -> void:
	body.shield_up=true
	body.shield_timer=body.SHIELD_DURATION
	body.play_model_action("shield")
	if blocked:
		for unit in Game.units:
			if is_instance_valid(unit) and unit.saber_target==body and unit.saber_active():
				unit.abort_saber()
				if unit.model_fsm!=null: unit.model_fsm.interrupt_melee()
