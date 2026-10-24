extends RefCounted
## Dedicated magnifier layer; original main-view layers remain intact.
const LAYER := 1 << 19
var roots: Array[Node3D] = []
var saved: Array[Dictionary] = []

func clear() -> void:
	for item in saved:
		if is_instance_valid(item.node): item.node.layers = item.layers
	saved.clear()
	roots.clear()

func sync(target: FlightBody) -> void:
	var wanted: Array[Node3D] = []
	if is_instance_valid(target.model_root): wanted.append(target.model_root)
	var board := target.pedal_owner()
	if is_instance_valid(board) and is_instance_valid(board._model): wanted.append(board._model)
	if wanted == roots: return
	clear()
	roots.assign(wanted)
	for root in roots:
		for node: Node in root.find_children("*","GeometryInstance3D",true,false):
			var geometry := node as GeometryInstance3D
			saved.append({"node":geometry,"layers":geometry.layers})
			geometry.layers |= LAYER
