extends Node3D
const Ship:=preload("res://scripts/world/sortie_ship.gd")
const VALIANT_POSITION:=Vector3(34000,0,34000)
const SEAWEED_POSITION:=Vector3(34800,0,34400)
const BASE_POSITION:=Vector3(32200,0,35500)
var ships:Array[Node3D]=[]
var airbase:Node3D
func _ready()->void:
	name="PacificFleet"
	for key in ["valiant","seaweed"]:
		var ship:=Ship.new();ship.kind=key;add_child(ship)
		ship.position=VALIANT_POSITION if key=="valiant" else SEAWEED_POSITION
		ship.rotation.y=PI*.25;ships.append(ship)
	airbase=load("res://scripts/cinematics/sortie_stage.gd").new();airbase.world_only=true;airbase.name="SoutheastAirbase";add_child(airbase);airbase.position=BASE_POSITION;airbase.rotation.y=PI*.25
	var ground:=StaticBody3D.new();ground.collision_layer=1;airbase.add_child(ground)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(500,22,2250);shape.shape=box;shape.position=Vector3(0,-7,-620);ground.add_child(shape)
func apply_time(tod:TimeOfDay)->void:
	var night:=tod!=null and tod.preset==TimeOfDay.Preset.NIGHT
	for ship in ships:ship.apply_night(night)
	if is_instance_valid(airbase):airbase.apply_night(night)
