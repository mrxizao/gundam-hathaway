extends Node3D
## Source length is Z; all axes receive one and the same scale.
const LENGTH:=200.0
var kind:="valiant"
var model:Node3D
var lamps:Array[MeshInstance3D]=[]
var flood:OmniLight3D
var deck_height:=21.8
var launch_z:=-68.0
func _ready()->void:
	name="Valiant" if kind=="valiant" else "Seaweed"
	var packed:=load("res://assets/models/sortie_ships/"+kind+".scn") as PackedScene
	if packed==null:return
	model=packed.instantiate();add_child(model)
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		mesh.visibility_range_end=12000.0
		mesh.visibility_range_end_margin=1000.0
	var bounds:AABB=model.get_meta("source_bounds")
	var factor:=LENGTH/bounds.size.z
	model.scale=Vector3.ONE*factor
	model.position=Vector3(-bounds.get_center().x*factor,.08*factor,-bounds.get_center().z*factor)
	deck_height=(-.016 if kind=="valiant" else .004)*factor+model.position.y+.5
	launch_z=-68.0 if kind=="valiant" else -40.0
	var pad:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(28,.25,35);pad.mesh=box
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.19,.22,.23);material.roughness=.9;pad.material_override=material
	pad.position=Vector3(0,deck_height-.125,launch_z);add_child(pad)
	var body:=StaticBody3D.new();body.collision_layer=1;add_child(body)
	if kind=="valiant":
		body.add_to_group("valiant_hull")
		var target:=Marker3D.new();target.name="ValiantTarget";target.position=Vector3(0,deck_height-8,0);target.add_to_group("valiant_target");add_child(target)
	var hull:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(bounds.size.x*factor*.82,24,190);hull.shape=shape;hull.position=Vector3(0,deck_height-14,0);body.add_child(hull)
	var top:=CollisionShape3D.new();var plate:=BoxShape3D.new();plate.size=box.size;top.shape=plate;top.position=pad.position;body.add_child(top)
	for side in [-1,1]:
		for z in [launch_z-15,launch_z+15]:
			var lamp:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.5;sphere.height=1;lamp.mesh=sphere
			var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.3,1,.6) if side<0 else Color(1,.4,.2);mat.emission_enabled=true;mat.emission=mat.albedo_color;lamp.material_override=mat
			lamp.position=Vector3(side*13,deck_height+.35,z);add_child(lamp);lamps.append(lamp)
	flood=OmniLight3D.new();flood.position=Vector3(0,deck_height+18,launch_z+6);flood.omni_range=75;flood.light_color=Color(1,.82,.58);add_child(flood)
	apply_night(false)
func launch_point()->Vector3:return to_global(Vector3(0,deck_height+.08,launch_z))
func apply_night(night:bool)->void:
	for lamp in lamps:
		(lamp.material_override as StandardMaterial3D).emission_energy_multiplier=3.0 if night else .3
	if is_instance_valid(flood):flood.light_energy=3.0 if night else 0.0
