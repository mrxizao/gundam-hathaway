extends Node
class Rider extends FlightBody:
	func _ready() -> void: pass
class Board extends FlightPedal:
	func _ready() -> void: pass
func _ready() -> void:
	var rider := Rider.new()
	add_child(rider)
	rider.set_process(false)
	rider.set_physics_process(false)
	rider.model_root = Node3D.new()
	rider.add_child(rider.model_root)
	rider._afterburner_fx = GPUParticles3D.new()
	rider.add_child(rider._afterburner_fx)
	var plume := GPUParticles3D.new()
	var glow := MeshInstance3D.new()
	rider.add_child(plume)
	rider.add_child(glow)
	rider._plume_fx.append({"fx":plume,"glow":glow})
	var board := Board.new()
	add_child(board)
	board.set_process(false)
	board.kind = FlightPedal.Kind.GUSTAV_SINGLE
	board.mode = FlightPedal.Mode.RIDDEN
	board.alive = true
	board.owner_rider = rider
	board.riders.append(rider)
	rider.pedal = board
	var path := FlightPedal.model_path_of(board.kind,FlightPedal.Vis.SLOT0_ONLY)
	board._model = load(path).instantiate()
	board.add_child(board._model)
	var thrust := Node3D.new()
	thrust.name = "PedalPropulsion"
	board.add_child(thrust)
	rider.set_model_visible(false)
	assert(not rider.model_root.visible)
	assert(not board._model.visible)
	assert(not thrust.visible)
	assert(not rider._afterburner_fx.visible and not plume.visible and not glow.visible)
	board._process(0.016)
	assert(not board._model.visible)
	# Engine tick may turn glow on, but the cockpit visibility pass must still suppress it.
	glow.visible = true
	rider._sync_cockpit_propulsion_visibility()
	assert(not glow.visible)
	# Rebuild/mount while FPV is already selected (unchanged wish) cannot leak geometry.
	board._model.visible = true
	rider.set_model_visible(false)
	assert(not board._model.visible)
	rider.set_model_visible(true)
	assert(board._model.visible and thrust.visible)
	assert(rider._afterburner_fx.visible and plume.visible)
	rider.set_model_visible(false)
	board.mode = FlightPedal.Mode.CAST_OFF
	board._cast_timer = 5.0
	board._process(0.016)
	assert(board._model.visible)
	assert(thrust.visible)
	# A separate AI board remains visible; no global Settings-based hiding.
	var ai_board := Board.new()
	add_child(ai_board)
	ai_board._model = Node3D.new()
	ai_board.add_child(ai_board._model)
	ai_board._process(0.016)
	assert(ai_board._model.visible)
	print("FPV VISIBILITY: 12 PASS; imported Gustav single mounted scene tested")
	get_tree().quit()
