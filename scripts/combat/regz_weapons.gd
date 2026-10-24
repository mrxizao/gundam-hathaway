extends RefCounted
## Right-button weapon routing shared by keyboard and pad fire actions.
const Cannon := preload("res://scripts/combat/beam_cannon.gd")
const CHARGE_SECONDS := 2.5
var irradiation := false
var held := false
var charge := 0.0
var fired := false
var selected: Node3D
var speed_hold := -1.0

func cancel() -> void:
 held = false
 charge = 0.0
 fired = false
 selected = null
 speed_hold = -1.0

func toggle() -> void:
 irradiation = not irradiation
 cancel()

func scope_active() -> bool:
 return held and not irradiation

func charging() -> bool:
 return held and irradiation

func mode_name() -> String:
 return "MEGA光束加农炮" if irradiation else "精准射击"

func tick(unit, delta: float, secondary: bool, primary: bool, primary_pressed: bool) -> void:
 if not unit.alive or not unit.controls_enabled or unit.in_transform() or unit.is_staggered() or (unit.current_slot() != "rifle" and not (unit.is_nu() and unit.current_slot()=="bazooka")):
  cancel()
  return
 held = secondary
 if not held:
  charge = 0.0
  fired = false
  selected = null
  speed_hold = -1.0
  if primary and _primary(unit,unit.lock.target if unit.lock != null else null):
   unit.play_model_action("shoot",true)
  return
 if irradiation:
  if unit.profile.form != 1:
   cancel()
   return
  selected = null
  if unit.cannon_ready() and not fired:
   charge = minf(charge+delta,CHARGE_SECONDS)
  else:
   charge = 0.0
  if primary_pressed and charge >= CHARGE_SECONDS and unit.cannon_ready() and not fired:
   fire_battery(unit)
   fired = true
   charge = 0.0
 else:
  charge = 0.0
  if primary_pressed or (primary and not eligible(unit,selected)):
   selected = acquire(unit)
   if is_instance_valid(selected) and unit.lock != null:
    unit.lock.select_target(selected)
  if not eligible(unit,selected): selected = null
  if primary and _primary(unit,selected if is_instance_valid(selected) else null):
   unit.play_model_action("shoot",true)

func _primary(unit,mark) -> bool:
 if unit.is_nu() and unit.current_slot()=="bazooka": return unit.nu_systems.fire_bazooka(mark)
 return unit.fire_beam(true,mark)

func acquire(unit) -> Node3D:
 var best: Node3D
 var score := 9.0
 var ray: Dictionary = unit.rifle_raw_ray()
 for foe in Game.live_hostiles_of(unit):
  if not eligible(unit,foe): continue
  var angle := Ballistics.angle_off_boresight(ray["direction"],foe.global_position-ray["origin"])
  if angle < score:
   score = angle
   best = foe
 return best

func eligible(unit,foe) -> bool:
 if not is_instance_valid(foe) or not foe.alive or not unit.is_hostile_to(foe): return false
 if unit.global_position.distance_to(foe.global_position)>6000.0: return false
 var ray: Dictionary = unit.rifle_raw_ray()
 if Ballistics.angle_off_boresight(ray["direction"],foe.global_position-ray["origin"])>12.0: return false
 return preload("res://scripts/combat/rifle_aim_solution.gd").clear_path(unit,unit._rifle_origin(),foe.global_position,foe)

func muzzle_offsets(unit) -> Array[Vector3]:
 if unit._regz_motion != null and unit._regz_motion.ready:
  var ports: Array[Vector3] = []
  for index in 5: ports.append(unit._regz_motion.port_local(index))
  return ports
 var h: float = 20.0
 if unit.profile.form == 1:
  return [Vector3(0,0,-h*0.50),Vector3(-h*0.17,0,-h*0.30),Vector3(h*0.17,0,-h*0.30),Vector3(-h*0.28,h*0.10,-h*0.15),Vector3(h*0.28,h*0.10,-h*0.15)]
 # Canonical centered model frame; central emitter is ahead of the torso.
 return [Vector3(0,h*0.08,-h*0.24),Vector3(-h*0.17,-h*0.06,-h*0.10),Vector3(h*0.17,-h*0.06,-h*0.10),Vector3(-h*0.28,h*0.27,-h*0.06),Vector3(h*0.28,h*0.27,-h*0.06)]

func fire_battery(unit, visual_only := false) -> void:
 if unit.profile == null or unit.profile.id != SuitProfile.Id.REGZ_CUSTOM or unit.profile.form != 1 or unit.in_transform(): return
 var origins := muzzle_offsets(unit)
 for i in origins.size():
  var points: Array[Vector3] = [origins[i]]
  var beam := Cannon.launch(unit.projectile_container,unit,points,null,
   (unit.profile.cannon_dps if i==0 else unit.profile.cannon_dps*0.35) if not visual_only else 0.0,
   unit.profile.cannon_duration,unit.profile.cannon_color(),5.0 if i==0 else 2.5,0.40 if i==0 else 0.16)
  if unit._regz_motion != null and unit._regz_motion.ready: beam.emitter_index = i
  if i==0: unit.active_cannon = beam
 unit._gun_recoil_clock = 0.0
 unit.cannon_cd_left = unit.profile.cannon_cooldown
 unit.play_model_action("shoot",true)
 unit._on_cannon_fired()
 if not visual_only: unit._net_report_fire("regz_battery",unit.global_position,unit.forward())
 if unit.is_player: Audio.play_self("beam_rifle",0.0)
 else: Audio.play_3d("beam_rifle",unit.global_position,0.0)

func slow_flight(unit,delta: float) -> void:
 if not charging() or not unit.alive or not unit.controls_enabled or unit.profile.form != 1:
  speed_hold = -1.0
  return
 unit.fm.boosting = false
 unit.fm.super_boost = false
 var limit: float = unit.profile.player_top_speed()*0.25
 if speed_hold<0.0: speed_hold = unit.fm.speed
 speed_hold = move_toward(speed_hold,limit,unit.profile.player_top_speed()*delta*1.5)
 if unit.fm.velocity.length()>speed_hold:
  unit.fm.velocity = unit.fm.velocity.normalized()*speed_hold
  unit.fm.speed = speed_hold
