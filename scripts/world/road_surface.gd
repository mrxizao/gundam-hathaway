extends RefCounted
## Shared road library. ResourceLoader shares texture resources across all three maps.
const SHADER := preload("res://shaders/road_surface.gdshader")
const ASSETS := ["asphalt_floor","concrete_floor_01","clean_asphalt"]
const TILES := [2.35,2.0,2.1]
const MEANS := [Vector3(0.2877383743965947,0.2129450401366565,0.15807253336055777),Vector3(0.18929238475562793,0.15363754305812594,0.10420840532532123),Vector3(0.05862702775132978,0.06029674073067146,0.06093565805465355)]
const ROAD_NAMES := {"CityRoads":0,"CityLocalStreets":0,"CityCanalBridges":0,"CityViaductDeck":0,"BridgeRamp":0,"CityRoadKerbs":1,"CityLocalKerbs":1,"CityRoadMarks":3}
static func material(role:int,color:Color,explicit:bool=false,emission:Color=Color(0,0,0,0),energy:float=0.0)->ShaderMaterial:
	var m:=ShaderMaterial.new();m.shader=SHADER
	m.set_shader_parameter("road_role",role)
	m.set_meta("road_source_color",color)
	var target:=color.srgb_to_linear()
	if role in [0,2]:
		# Neutral graphite; quantized legacy RGB must not turn a runway cyan/black.
		var value:=clampf(target.r*0.2126+target.g*0.7152+target.b*0.0722,0.042,0.085)
		if role==2:value*=0.78
		target=Color(value,value*1.015,value*1.025,1.0)
	m.set_shader_parameter("base_color",target)
	m.set_shader_parameter("explicit_frame",explicit)
	m.set_shader_parameter("road_quality",clampi(Settings.effects_quality,0,2))
	m.set_shader_parameter("emission_color",emission.srgb_to_linear())
	m.set_shader_parameter("emission_energy",energy if emission.a>0.0 else 0.0)
	var index:=clampi(role,0,2)
	var mean:Vector3=MEANS[index];var linear:=target
	m.set_shader_parameter("color_gain",Vector3(linear.r,linear.g,linear.b)/mean)
	m.set_shader_parameter("tile_m",TILES[index])
	if role<3:
		for pair in [["surface_albedo","diff"],["surface_normal","nor_gl"],["surface_orm","arm"]]:
			m.set_shader_parameter(pair[0],load("res://assets/materials/adelaide_pbr/"+ASSETS[index]+"_"+pair[1]+"_2k.png"))
	if explicit:
		m.set_shader_parameter("adelaide_mask",true)
		m.set_shader_parameter("junction_mask",load("res://assets/materials/adelaide_pbr/road_junction_mask.png"))
	return m
static func from_city(role:int,source:StandardMaterial3D)->ShaderMaterial:
	var m:=material(role,source.albedo_color,false,source.emission if source.emission_enabled else Color(0,0,0,0),source.emission_energy_multiplier)
	m.set_shader_parameter("local_z_frame",true)
	return m
