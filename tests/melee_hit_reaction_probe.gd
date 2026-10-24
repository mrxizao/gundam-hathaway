extends Node
class Body extends FlightBody:
	var applied := 0
	func _ready() -> void: pass
	func _apply_damage(_amount: float,_source: Node3D,_kind: int) -> void: applied+=1
func _ready() -> void:
	var source := Body.new()
	source.team = 1
	source.profile = SuitProfile.xi()
	add_child(source)
	source.set_physics_process(false)
	source.set_process(false)
	source.position = Vector3(0,0,-100)
	var count := 0
	for id in SuitProfile.Id.values():
		var body := Body.new()
		body.team = 0
		body.profile = SuitProfile.by_id(id)
		add_child(body)
		body.set_physics_process(false)
		body.set_process(false)
		body.take_damage(10,source,Damage.Type.SABER)
		var reaction = body.melee_hit_reaction
		var expected: bool = id not in [SuitProfile.Id.GP03D,SuitProfile.Id.GP03S,SuitProfile.Id.NEUE_ZIEL]
		assert((reaction.elapsed == 0.0) == expected)
		assert(body.applied == 1)
		if expected:
			assert(reaction.step(0.09).length()>3.0)
			assert(reaction.step(1.0).length()<0.0001)
			body.take_damage(10,source,Damage.Type.RAM)
			assert(reaction.elapsed == reaction.DURATION)
			# Friendly saber contact must not trigger the visual or damage.
			source.team=0
			body.take_damage(10,source,Damage.Type.SABER)
			assert(reaction.elapsed == reaction.DURATION)
			source.team=1
			# Consecutive cuts restart cleanly; side cuts produce roll/yaw.
			source.position=Vector3(-100,0,0)
			body.take_damage(10,source,Damage.Type.SABER)
			assert(absf(reaction.step(0.09).z)>1)
			source.position=Vector3(0,0,-100)
		count+=1
		body.free()
	var rider := Body.new()
	rider.profile = SuitProfile.by_id(SuitProfile.Id.GUSTAV00)
	add_child(rider)
	rider.set_physics_process(false)
	var board := FlightPedal.new()
	add_child(board)
	board.set_process(false)
	board.mode=FlightPedal.Mode.RIDDEN
	board.riders.append(rider)
	var pivot := Node3D.new()
	pivot.name="MeleeImpactPivot"
	board.add_child(pivot)
	board._model=Node3D.new()
	pivot.add_child(board._model)
	rider.melee_hit_reaction.trigger(rider,source)
	rider.melee_hit_reaction.step(0.09)
	board._process(0.016)
	assert(pivot.rotation_degrees.length()>1)
	rider.melee_hit_reaction.step(1.0)
	board._process(0.016)
	assert(pivot.rotation_degrees.length()<0.0001)
	board.free()
	rider.free()
	print("MELEE HIT REACTION PASS profiles=",count," GP03D/GP03S/Neue excluded")
	get_tree().quit()
