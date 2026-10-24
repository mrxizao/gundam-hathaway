extends Node3D
const MODEL_SCALE := 8.0
const CENTER := Vector3(0,12000,0)
const GEOMETRY := preload("res://scripts/world/colony_geometry.gd")
const LIGHTNING := preload("res://scripts/world/colony_lightning.gd")
var model: Node3D
var lightning: Node3D

func build() -> void:
	name = "ColonyRuins"
	model = load("res://assets/maps/colony_ruins/colony_ruined.scn").instantiate()
	model.name = "ImportedColony"
	add_child(model)
	model.position = CENTER
	model.scale *= MODEL_SCALE
	GEOMETRY.prepare(model)
	lightning = LIGHTNING.new()
	lightning.spatial_scale = MODEL_SCALE
	add_child(lightning)

static func spawn_position(angle_degrees: float) -> Vector3:
	# Both pilots start in the clear central channel, facing across the interior.
	var angle := deg_to_rad(angle_degrees)
	return CENTER+Vector3(cos(angle)*160,sin(angle)*35-220,sin(angle)*2100)
