extends BanditAI
## Only the host simulates squad AI. Guests render host snapshots and report hits.
var net_unit_id := ""
var net_state: Dictionary = {}
func _physics_process(delta: float) -> void:
	if Net.role != Net.Role.CLIENT:
		super._physics_process(delta)
		return
	if not alive:
		super._physics_process(delta)
		return
	if not net_state.is_empty():
		var k := 1.0 - exp(-12.0 * delta)
		global_position = global_position.lerp(net_state["position"], k)
		global_basis = global_basis.slerp(net_state["basis"], k).orthonormalized()
		fm.velocity = net_state["velocity"]
		fm.speed = fm.velocity.length()
	combat_buffs.tick(self, delta)
	_tick_effects(delta)

func receive_snapshot(pkt: Dictionary) -> void:
	net_state = Net.unpack_state(pkt)
	combat_buffs.apply_snapshot(net_state.get("combat", {}))
	if is_instance_valid(nu_systems): nu_systems.apply_snapshot(net_state.get("nu",{}))
	hp = net_state["hp"]
	ifield_hp = net_state["ifield"]
	if not net_state["alive"] and alive:
		destroy(null, "联机击坠")

func take_damage(amount: float, source: Node3D, damage_type := Damage.Type.RAM) -> void:
	if Net.role == Net.Role.CLIENT:
		# Visual-only remote projectiles deal zero damage; only local hits report.
		if amount > 0.0 and source == Game.player:
			Net.send_ai_damage(net_unit_id, amount * source.combat_buffs.damage_rate(damage_type), damage_type)
		return
	super.take_damage(amount, source, damage_type)
