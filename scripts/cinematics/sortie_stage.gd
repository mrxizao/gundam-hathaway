extends Node3D
## Hardware and illumination are shared by every shot in each day/night version.
const Ship:=preload("res://scripts/world/sortie_ship.gd")
var world_only:=false
var adelaide_launch:=false
var night:=false
var runway:=true
var door:Node3D
var tractor:Node3D
var cradle:Node3D
var transport_support:Node3D
var wheels:Array[MeshInstance3D]=[]
var practical_lights:Array[Light3D]=[]
var edge_lights:Array[MeshInstance3D]=[]
var launch_point:=Vector3(0,6,0)
var ship:Node3D
func material(color:Color,emission:=0.0)->StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=.8
	if emission>0:m.emission_enabled=true;m.emission=color;m.emission_energy_multiplier=emission
	return m
func box(parent:Node3D,title:String,at:Vector3,size:Vector3,color:Color,emission:=0.0)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=title;var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh;node.material_override=material(color,emission);parent.add_child(node);node.position=at;return node
func _ready()->void:
	if not world_only:_build_environment()
	_build_hardware()
func _build_environment()->void:
	var env:=Environment.new();env.background_mode=Environment.BG_SKY
	var sky:=Sky.new();var sky_mat:=ProceduralSkyMaterial.new()
	sky_mat.sky_top_color=Color(.008,.015,.05) if night else Color(.13,.35,.68)
	sky_mat.sky_horizon_color=Color(.06,.09,.15) if night else Color(.65,.78,.85)
	sky_mat.ground_bottom_color=Color(.01,.025,.04);sky_mat.ground_horizon_color=sky_mat.sky_horizon_color;sky.sky_material=sky_mat;env.sky=sky
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.38,.5,.75) if night else Color(.7,.8,.9);env.ambient_light_energy=.5 if night else .85
	if adelaide_launch:
		env.ambient_light_color=Color(.52,.58,.64);env.ambient_light_energy=.14 if night else .22
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env.glow_enabled=true;env.glow_intensity=.5
	var world:=WorldEnvironment.new();world.environment=env;add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-32,-35,0);sun.light_energy=.45 if night else 1.6;sun.light_color=Color(.5,.65,1) if night else Color(1,.94,.82);sun.shadow_enabled=true;add_child(sun)
	if adelaide_launch:sun.directional_shadow_max_distance=1800.0
	if not adelaide_launch: box(self,"Ocean",Vector3(0,-3,0),Vector3(18000,2,18000),Color(.015,.045,.075) if night else Color(.08,.26,.36))
func _build_hardware()->void:
	if adelaide_launch:
		var city := preload("res://scripts/world/adelaide_builder.gd").new()
		add_child(city); city.build(); city.position=Vector3(9480,-21,-4410)
		launch_point=Vector3(0,6,0)
		_build_launch_hardware()
		return
	if not runway:
		ship=Ship.new();ship.kind="valiant" if get_meta("xi",false) else "seaweed";add_child(ship);ship.apply_night(night);launch_point=ship.launch_point();return
	box(self,"IslandFoundation",Vector3(0,-7,-620),Vector3(500,22,2250),Color(.23,.25,.2))
	box(self,"Runway",Vector3(0,3.5,-680),Vector3(105,5,1900),Color(.085,.095,.105))
	for z in range(100,-1600,-45):
		box(self,"CenterMark",Vector3(0,6.02,z),Vector3(1.3,.04,18),Color(.8,.82,.75))
		for side in [-1,1]:edge_lights.append(box(self,"RunwayEdgeLight",Vector3(side*48,6.3,z),Vector3(.7,.35,1.8),Color(.55,.8,1),4.0 if night else .35))
	for side in [-1,1]:
		box(self,"HangarWall",Vector3(side*65,48,45),Vector3(5,84,205),Color(.25,.29,.3))
	box(self,"HangarRoof",Vector3(0,91,45),Vector3(135,5,205),Color(.22,.26,.27))
	box(self,"HangarBack",Vector3(0,48,145),Vector3(135,84,5),Color(.22,.26,.27))
	door=Node3D.new();add_child(door)
	for side in [-1,1]:box(door,"HangarDoor",Vector3(side*32.5,47,-57),Vector3(64,82,3),Color(.3,.34,.32))
	for z in [-35,35,105]:
		box(self,"CeilingStrip",Vector3(0,87,z),Vector3(95,.5,2),Color(1,.82,.55),3.5)
		var light:=OmniLight3D.new();light.position=Vector3(0,65,z);light.omni_range=115;light.light_energy=2.0 if night else 1.2;light.light_color=Color(1,.82,.6);add_child(light);practical_lights.append(light)
	for z in [-230,-650,-1100]:
		for side in [-1,1]:
			box(self,"FloodPole",Vector3(side*75,28,z),Vector3(1,44,1),Color(.22,.25,.27))
			var light:=OmniLight3D.new();light.position=Vector3(side*75,50,z);light.omni_range=140;light.light_energy=3.0 if night else 0.0;light.light_color=Color(.75,.85,1);add_child(light);practical_lights.append(light)
	tractor=Node3D.new();add_child(tractor)
	box(tractor,"TowMotor",Vector3(0,9,-43),Vector3(12,6,16),Color(.44,.43,.23))
	box(tractor,"TowCab",Vector3(0,14,-47),Vector3(9,5,7),Color(.18,.24,.25))
	box(tractor,"TowBar",Vector3(0,8,-25),Vector3(1.3,1.3,20),Color(.48,.46,.35))
	cradle=Node3D.new();add_child(cradle)
	box(cradle,"TransportCradle",Vector3(0,7.5,0),Vector3(45,3,55),Color(.28,.3,.27))
	for parent in [tractor,cradle]:
		for side in [-1,1]:
			for z in ([-48,-38] if parent==tractor else [-18,18]):
				var wheel:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=2;mesh.bottom_radius=2;mesh.height=2.2;wheel.mesh=mesh;wheel.material_override=material(Color(.055,.065,.07));wheel.rotation.z=PI*.5;parent.add_child(wheel);wheel.position=Vector3(side*(7 if parent==tractor else 22),7.8,z);wheels.append(wheel)
func sample(time:float)->void:
	if adelaide_launch:
		_sample_adelaide(time)
		return
	if not runway:return
	var opening:=smoothstep(0,1.4,time)
	for panel:MeshInstance3D in door.get_children():
		panel.scale.y=maxf(.005,1.0-opening);panel.position.y=88-41*(1.0-opening)
	var tow:float=-250*smoothstep(1.4,3.8,time)
	tractor.position.z=tow;cradle.position.z=tow
	var retract:float=smoothstep(3.8,4.8,time)
	tractor.position.x=95*retract;cradle.position.y=-14*retract
	for wheel in wheels:wheel.rotation.x=tow*.5

func apply_night(value:bool)->void:
	night=value
	for lamp in practical_lights:
		lamp.light_energy=(2.0 if night else 1.2) if lamp.position.z>=-35 else (3.0 if night else 0.0)
	for lamp:MeshInstance3D in edge_lights:
		(lamp.material_override as StandardMaterial3D).emission_energy_multiplier=4.0 if night else .35

func _build_launch_hardware()->void:


	for z in range(-990,-9000,-150):
		box(self,"CenterMark",Vector3(-5490,6.02,z),Vector3(1.3,.04,18),Color(.8,.82,.75))
		for side in [-1,1]:edge_lights.append(box(self,"RunwayEdgeLight",Vector3(-5490+side*175,6.3,z),Vector3(.7,.35,1.8),Color(.55,.8,1),4.0 if night else .35))

	door=Node3D.new();add_child(door)
	for side in [-1,1]:box(door,"HangarDoor",Vector3(side*250,80,-441),Vector3(500,148,3),Color(.3,.34,.32))
	# Shared Adelaide roof fixtures and nearest-bay work lights replace the floating legacy strips.
	for z in [-230,-650,-1100]:
		for side in [-1,1]:
			box(self,"FloodPole",Vector3(side*75,28,z),Vector3(1,44,1),Color(.22,.25,.27))
			var light:=OmniLight3D.new();light.position=Vector3(side*75,50,z);light.omni_range=140;light.light_energy=3.0 if night else 0.0;light.light_color=Color(.75,.85,1);add_child(light);practical_lights.append(light)
	tractor=Node3D.new();tractor.name="RunwayTowTractor";add_child(tractor)
	box(tractor,"TowMotor",Vector3(0,9,-68),Vector3(15,6,20),Color(.44,.43,.23))
	box(tractor,"TowCab",Vector3(0,14,-72),Vector3(11,5,8),Color(.18,.24,.25))
	box(tractor,"CabGlass",Vector3(0,15,-76.1),Vector3(8,2.4,.15),Color(.1,.22,.28))
	box(tractor,"TowBar",Vector3(0,8,-42),Vector3(1.6,1.6,36),Color(.48,.46,.35))
	box(tractor,"Beacon",Vector3(0,17,-72),Vector3(2,.8,1),Color(1,.54,.08),2.0)
	cradle=Node3D.new();cradle.name="RunwayTransportTrailer";add_child(cradle)
	box(cradle,"TransportCradle",Vector3(0,7.5,0),Vector3(75,3,85),Color(.28,.3,.27))
	for side in [-1,1]:
		box(cradle,"DeckStripe",Vector3(side*35,9.05,0),Vector3(1,.08,78),Color(.85,.65,.18))
	for parent in [tractor,cradle]:
		for side in [-1,1]:
			for z in ([-73,-63] if parent==tractor else [-28,28]):
				var wheel:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=2;mesh.bottom_radius=2;mesh.height=2.2;wheel.mesh=mesh;wheel.material_override=material(Color(.055,.065,.07));wheel.rotation.z=PI*.5;parent.add_child(wheel);wheel.position=Vector3(side*(8 if parent==tractor else 37),7.8,z);wheels.append(wheel)
func _sample_adelaide(time:float)->void:
	if not runway:return
	var opening:=smoothstep(0,1.4,time)
	for panel:MeshInstance3D in door.get_children():
		panel.scale.y=maxf(.005,1.0-opening);panel.position.y=154-74*(1.0-opening)
	var convoy:Dictionary=preload("res://scripts/data/sortie_script.gd").tow_pose(time)
	var release:=smoothstep(8.0,8.85,time)
	tractor.position=convoy.position+Vector3(150*release,0,-25*release)
	cradle.position=convoy.position+Vector3(110*release,0,0)
	tractor.rotation.y=convoy.yaw-PI*.2*sin(PI*release)
	cradle.rotation.y=convoy.yaw
	if transport_support!=null:transport_support.scale.y=maxf(.05,1.0-release)
	var distance:float=-convoy.position.z-convoy.position.x
	for wheel in wheels:wheel.rotation.x=distance*.5


func fit_transport_support(bounds:AABB)->void:
	if not adelaide_launch or cradle==null:return
	transport_support=Node3D.new();transport_support.name="RetractingCargoSaddles";cradle.add_child(transport_support);transport_support.position.y=9
	var height:=clampf(bounds.size.y*.32,4.0,14.0)
	for side in [-1,1]:
		for z in [-6,6]:
			box(transport_support,"HydraulicJack",Vector3(side*7,height*.5,z),Vector3(2.5,height,2.5),Color(.19,.23,.24))
			box(transport_support,"SupportSaddle",Vector3(side*7,height,z),Vector3(8,1.2,9),Color(.47,.44,.27))
