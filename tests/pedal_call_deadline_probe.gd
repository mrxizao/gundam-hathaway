extends Node
class Rider extends FlightBody:
	func _ready() -> void: pass
class Pedal extends FlightPedal:
	var arrived := false
	func _arrive() -> void:
		arrived = true
		mode = Mode.RIDDEN
func _ready() -> void:
	for scenario in 4:
		var rider := Rider.new()
		add_child(rider)
		rider.set_process(false)
		rider.set_physics_process(false)
		var board := Pedal.new()
		add_child(board)
		board.set_process(false)
		board.owner_rider = rider
		board.mode = FlightPedal.Mode.INBOUND
		board.global_position = Vector3(900,900,0) if scenario == 0 else Vector3(100000,900,0)
		var elapsed := 0.0
		var dt := 0.1 if scenario == 3 else 1.0/60.0
		while not board.arrived and elapsed < 5.01:
			rider.velocity = Vector3(0,0,3000) if scenario > 0 else Vector3.ZERO
			rider.global_position += rider.velocity*dt
			if scenario == 2 and elapsed > 4.8: rider.global_position += Vector3(50000,10000,0)
			board._tick_inbound(dt)
			elapsed += dt
		assert(board.arrived)
		assert(elapsed <= 5.0+dt)
		assert(board.global_position.distance_to(rider.global_position) <= FlightPedal.CALL_ARRIVE_DIST)
		board.free()
		rider.free()
	print("PEDAL CALL: 12 PASS (stationary, fast rider, late teleport, low FPS)")
	get_tree().quit()
