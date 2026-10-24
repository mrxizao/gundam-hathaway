extends Node3D
var shooter
var direction:=Vector3.FORWARD
var age:=0.0
var previous:=Vector3.ZERO
var model:Node3D
var hit:=false
var visual_only:=false
func _ready()->void:
	previous=global_position
	if direction.length_squared()>.01:global_basis=Basis.looking_at(direction.normalized(),Vector3.UP if absf(direction.normalized().y)<.98 else Vector3.RIGHT)
	if model!=null:add_child(model)
func _physics_process(delta:float)->void:
	if not is_instance_valid(shooter) or not shooter.alive or age>2.0:queue_free();return
	age+=delta
	var next:=global_position+direction*6000.0*delta
	var query:=PhysicsRayQueryParameters3D.create(global_position,next,FlightBody.WORLD_LAYER|FlightBody.UNIT_LAYER)
	query.exclude=[shooter.get_rid()]
	var result:=get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var foe=result.get("collider")
		if not visual_only and foe is Node3D and foe.has_method("take_damage"):
			var friendly:bool=foe is FlightBody and foe.is_friendly_fire(shooter)
			var accepted:bool=not friendly and (not foe is FlightBody or (foe.alive and not foe.is_invulnerable() and not foe.shield_up))
			foe.take_damage(shooter.profile.saber_damage*3.0*shooter.damage_mult*shooter.melee_guard.DAMAGE_MULT,shooter,Damage.Type.SABER)
			if accepted and foe is FlightBody:shooter.sazabi_systems.stun(foe)
			hit=accepted
		FX.saber_slash(get_parent(),result.position,direction,Vector3.UP,Color(.65,1,.38))
		queue_free();return
	global_position=next
	if model!=null:model.rotate_x(delta*22.0)
