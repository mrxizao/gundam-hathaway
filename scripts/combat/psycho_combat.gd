extends RefCounted
## Combat state shared by local units and remote snapshots; no profile mutation.
const RESONANCE_SECONDS := 30.0
const RESONANCE_PROTECTION := 7.0
const PASSIVE_GAIN := 0.8
const DEALT_GAIN_PER_HIT := 5.0
const TAKEN_GAIN_PER_HIT := 7.0
const RELOAD_RATE := 1.5
const FIN_RATE := 1.5
const RANGED_DAMAGE := 1.25
const MELEE_DAMAGE := 1.5
const KICK_SECONDS := 20.0
const KICK_COOLDOWN := 10.0
const EXECUTE_RATIO := 0.15
var gauge := 0.0
var resonance_left := 0.0
var protection_left := 0.0
var kick_left := 0.0
var kick_cd := 0.0
var kick_source: WeakRef
var active_victim: WeakRef
var melee_marks: Dictionary = {}
var motion_scale := 1.0
var waves: Array[MeshInstance3D] = []
var age := 0.0

func is_remote(body) -> bool:
	return body.has_method("apply_state") or (body.has_method("receive_snapshot") and Net.role == Net.Role.CLIENT)
func active() -> bool:
	return resonance_left > 0.0
func immune() -> bool:
	return protection_left > 0.0
func reload_rate() -> float:
	return RELOAD_RATE if active() else 1.0
func damage_rate(kind: int) -> float:
	if not active(): return 1.0
	return MELEE_DAMAGE if kind == Damage.Type.SABER else RANGED_DAMAGE
func movement_rate(body) -> float:
	var slow:float=body.thunder_slow_rate if body.thunder_slow_left>0 else 1.0
	if kick_left <= 0.0: return slow
	return minf(slow,0.3 if body.profile.id == SuitProfile.Id.ZORIN_SOUL else 0.6)
func gain(body, amount: float) -> void:
	if not body.alive or body.profile.id != SuitProfile.Id.NU_GUNDAM or is_remote(body) or active() or amount <= 0.0: return
	gauge = minf(100.0, gauge + amount)
	if gauge >= 100.0: activate(body)
func activate(body) -> void:
	gauge = 0.0
	resonance_left = RESONANCE_SECONDS
	protection_left = RESONANCE_PROTECTION
	body.ifield_hp = minf(body.ifield_max, body.ifield_hp + body.ifield_max * 0.07)
	if body.is_player:
		body.notice.emit("精神感应框架共鸣 · 30秒 / 无敌屏障7秒", 3.0)
		Audio.play_resonance_bgm()
	intercept(body)
func tick(body, delta: float) -> void:
	if not body.alive or Game.phase != Game.Phase.FIGHT: return
	age += delta
	kick_cd = maxf(0.0, kick_cd - delta)
	kick_left = maxf(0.0, kick_left - delta)
	if body.in_transform(): kick_left = 0.0
	var was_active := active()
	resonance_left = maxf(0.0, resonance_left - delta)
	protection_left = maxf(0.0, protection_left - delta)
	if not was_active and not is_remote(body): gain(body, PASSIVE_GAIN * delta)
	if immune(): intercept(body)
	update_waves(body)
func intercept(body) -> void:
	for missile in body.get_tree().get_nodes_in_group("missiles"):
		if missile is Missile and not missile.is_queued_for_deletion() and is_instance_valid(missile.shooter) and body.is_hostile_to(missile.shooter):
			missile._detonate(true, null, false)
func melee_hit(source, victim) -> void:
	if source.profile.id != SuitProfile.Id.SAZABI or not victim.alive or victim.in_transform() or victim.combat_buffs.kick_left > 0.0: return
	var id: int = victim.get_instance_id()
	if not melee_marks.has(id) or melee_marks[id].get_ref() != victim:
		melee_marks[id] = weakref(victim)
		return
	var previous = active_victim.get_ref() if active_victim != null else null
	if kick_cd > 0.0 or (is_instance_valid(previous) and previous.alive and previous.combat_buffs.kick_left > 0.0): return
	victim.combat_buffs.kick_left = KICK_SECONDS
	victim.combat_buffs.kick_source = weakref(source)
	active_victim = weakref(victim)
	kick_cd = KICK_COOLDOWN
	if source.has_method("apply_state"): Net.send_kick_confirmation()
	if victim.is_player: victim.notice.emit("夏亚飞踢 · I力场穿透 / 减速 / 15%斩杀", 2.5)
	if source.is_player: source.notice.emit("夏亚飞踢生效 · 20秒", 2.0)
func execute_if_needed(body, source) -> void:
	if kick_left <= 0.0 or not body.alive or body.invincible or body.in_transform() or body.hp_ratio() > EXECUTE_RATIO: return
	kick_left = 0.0
	body.hp = 0.0
	if not body._transformed and body.profile.transform_to_form >= 0:
		body._begin_transform()
	else:
		body.destroy(source, "夏亚飞踢 · 15%斩杀")
func record_damage(victim, source, hull: float, shield: float) -> void:
	var effective := maxf(hull, 0.0) + maxf(shield, 0.0)
	if effective <= 0.0 or not is_instance_valid(source) or not source is FlightBody or not source.is_hostile_to(victim): return
	gain(victim, TAKEN_GAIN_PER_HIT)
	var credit: float = DEALT_GAIN_PER_HIT
	if source.profile.id == SuitProfile.Id.NU_GUNDAM:
		if source.has_method("apply_state"): Net.send_resonance_credit(credit)
		else: source.combat_buffs.gain(source, credit)
func restore_motion(body) -> void:
	# Undo only our preceding frame's scale before the original flight solver.
	if motion_scale < 1.0:
		body.fm.velocity /= motion_scale
		body.fm.speed /= motion_scale
		body.velocity /= motion_scale
		motion_scale = 1.0
func scale_motion(body) -> void:
	motion_scale = movement_rate(body)
	body.fm.velocity *= motion_scale
	body.fm.speed *= motion_scale
	body.velocity *= motion_scale
func snapshot() -> Dictionary:
	return {"gauge":gauge, "resonance":resonance_left, "protection":protection_left, "kick":kick_left}
func apply_snapshot(data: Dictionary) -> void:
	gauge = clampf(float(data.get("gauge",0)),0,100)
	resonance_left = clampf(float(data.get("resonance",0)),0,RESONANCE_SECONDS)
	protection_left = clampf(float(data.get("protection",0)),0,RESONANCE_PROTECTION)
	kick_left = clampf(float(data.get("kick",0)),0,KICK_SECONDS)
func update_waves(body) -> void:
	if immune() and waves.is_empty():
		for i in 3:
			var wave := MeshInstance3D.new()
			var ring := TorusMesh.new()
			ring.inner_radius = 0.994; ring.outer_radius = 1.0; ring.rings = 48; ring.ring_segments = 6
			wave.mesh = ring
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.45,0.9,1,0.22)
			wave.material_override = mat
			body.add_child(wave); waves.append(wave)
	for i in waves.size():
		var wave := waves[i]
		wave.visible = immune() and body.alive
		if not wave.visible: continue
		var t := fposmod(age + i * 0.33, 1.0)
		wave.scale = Vector3.ONE * (body.profile.target_height * (0.7 + t * 3.0))
		wave.rotation = Vector3(i * 0.7, age * 0.2, i * 0.5)
		wave.material_override.albedo_color.a = (1.0-t)*0.22
