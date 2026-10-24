extends RefCounted
const SHADER:=preload("res://shaders/adelaide_building.gdshader")
const ASSETS:=["concrete_wall_003","brick_wall_001","painted_metal_shutter","adelaide_trim_atlas"]
const MEANS:=[Vector3(0.6337117744840988,0.4980982054422816,0.3571855773318887),Vector3(0.1383853894659484,0.07570965731577467,0.05009284725358353),Vector3(0.2161504076708708,0.2296589616706754,0.2392422687343208)]
const TRIM_MEANS:=[Vector3(0.3143655030333637,0.3378859337635307,0.32600198741407177),Vector3(0.09345843203216513,0.12438169566996804,0.138212706696439),Vector3(0.008462516410710117,0.010712364712359174,0.012386561126625052),Vector3(0.1529032767752027,0.17657728894201372,0.17657728894201372),Vector3(0.24965843576818433,0.2299997600058913,0.18491018821823832),Vector3(0.03922287966530701,0.05854321877536083,0.06755596362581576),Vector3(0.13118679405171596,0.15289681786589823,0.160567308587801),Vector3(0.026909552212477768,0.03272874484981849,0.03589004653316607)]
const TILES:=[3.0,3.0,2.0,8.0]
const ROOF_ASSETS:=["bitumen","corrugated_iron"]
const ROOF_MEANS:=[Vector3(0.043259400656614065,0.03732853622457168,0.035376766389790204),Vector3(0.405413934403388,0.4516692708180802,0.42818535947701314)]
static func material(role:int,style:int)->ShaderMaterial:
	var result:=ShaderMaterial.new();result.shader=SHADER
	var color:=Color(0.52,0.55,0.55)
	match role:
		0:color=Color(0.57,0.59,0.58) if style==5 else Color(0.52,0.55,0.55)
		1:color=Color(0.48,0.34,0.26)
		2:color=Color(0.34,0.39,0.41)
		3:color=Color(0.92,0.95,0.96)
		4:color=Color(0.18,0.28,0.33)
		5:color=Color(0.22,0.24,0.25)
		6:color=Color(0.32,0.37,0.39)
	result.set_shader_parameter("base_color",color)
	result.set_shader_parameter("surface_role",role)
	result.set_shader_parameter("floor_m",6.4)
	result.set_shader_parameter("bay_m",10.0 if style==2 else 14.0 if style==3 else 12.0)
	result.set_shader_parameter("building_quality",clampi(Settings.effects_quality,0,2))
	if role<4:
		result.set_shader_parameter("tile_m",TILES[role])
		result.set_shader_parameter("color_gain",Vector3.ONE/MEANS[role] if role<3 else Vector3.ONE)
		for pair in [["surface_albedo","diff"],["surface_normal","nor_gl"],["surface_orm","arm"]]:result.set_shader_parameter(pair[0],load("res://assets/materials/adelaide_pbr/"+ASSETS[role]+"_"+pair[1]+"_2k.png"))
	if role>=5:
		result.set_shader_parameter("tile_m",4.0 if role==5 else 2.0)
		result.set_shader_parameter("color_gain",Vector3.ONE/ROOF_MEANS[role-5])
		for pair in [["surface_albedo","diff"],["surface_normal","nor_gl"],["surface_orm","arm"]]:result.set_shader_parameter(pair[0],load("res://assets/materials/adelaide_pbr/"+ROOF_ASSETS[role-5]+"_"+pair[1]+"_2k.png"))
	result.set_shader_parameter("trim_means",PackedVector3Array(TRIM_MEANS))
	return result

static func merged_material(style:int)->ShaderMaterial:
	var result:=ShaderMaterial.new();result.shader=load("res://shaders/adelaide_building_merged.gdshader")
	result.set_shader_parameter("building_quality",clampi(Settings.effects_quality,0,2));result.set_shader_parameter("bay_m",10.0 if style==2 else 14.0 if style==3 else 12.0)
	for role in [0,1,2,5,6]:
		var source:=material(role,style)
		for pair in [["albedo","surface_albedo"],["normal","surface_normal"],["orm","surface_orm"]]:result.set_shader_parameter("role_"+str(role)+"_"+pair[0],source.get_shader_parameter(pair[1]))
		result.set_shader_parameter("gain_"+str(role),source.get_shader_parameter("color_gain"))
	return result
