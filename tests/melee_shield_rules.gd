extends Node
class Body extends FlightBody:
	var damage_calls := 0
	var gun_calls := 0
	func _ready() -> void: pass
	func _apply_damage(_amount: float,_source: Node3D,_type: int) -> void: damage_calls+=1
	func _fire_vulcan_round(_target: Node3D = null) -> void: gun_calls+=1
func unit(team_id: int) -> Body:
	var b := Body.new()
	b.profile=SuitProfile.xi()
	b.team=team_id
	add_child(b)
	b.set_physics_process(false)
	b.projectile_container=self
	return b
func warning(defender: Body,attacker: Body) -> void:
	attacker.saber_state=FlightBody.SaberState.CHARGE
	attacker.saber_timer=1.0
	attacker._melee_attack_serial+=1
	defender.melee_guard.warn(defender,attacker)
	defender.melee_guard.elapsed=0.25
	defender.melee_guard.center=1.0
func _ready() -> void:
	var a := unit(1)
	var b := unit(0)
	a.position=Vector3(0,0,-100)
	warning(b,a)
	assert(not b.melee_guard.can_guard(b))
	assert(b.raise_shield())
	assert(b.melee_guard.shield_armed)
	b.take_damage(10,a,Damage.Type.SABER)
	assert(b.damage_calls==0)
	assert(b.melee_guard.result=="举盾防御成功")
	assert(b.melee_guard.impact_left==0 and b.melee_guard.slow_left==0)
	assert(not b.melee_guard.shield_armed)
	# One guard cannot cancel a second damage packet.
	b.take_damage(10,a,Damage.Type.SABER)
	assert(b.damage_calls==1)
	assert(b.saber_locked() and not b.weapons_locked())
	assert(not b.try_saber(a))
	assert(b.fire_gun(true,a) and b.gun_calls==1)
	# Speed penalty remains 90%, without cancelling active ranged weapons.
	var c := unit(0)
	c.fm.speed=1000
	c.fm.velocity=Vector3(0,0,-1000)
	c.velocity=c.fm.velocity
	c.active_cannon=Node3D.new()
	c.add_child(c.active_cannon)
	c.take_damage(10,a,Damage.Type.SABER)
	assert(is_equal_approx(c.fm.speed,100))
	assert(is_equal_approx(c.velocity.length(),100))
	assert(not c.active_cannon.is_queued_for_deletion())
	c.velocity=Vector3(900,0,0)
	c.melee_guard.limit(c)
	assert(c.velocity.length()<=100.001)
	# Riding/carried units cannot select the new shield defense.
	var mounted := unit(0)
	var board := FlightPedal.new()
	add_child(board)
	board.alive=true
	mounted.pedal=board
	warning(mounted,a)
	assert(not mounted.melee_guard.shield_available(mounted))
	mounted.raise_shield()
	assert(not mounted.melee_guard.shield_armed)
	print("MELEE SHIELD RULES: 18 PASS")
	get_tree().quit()
