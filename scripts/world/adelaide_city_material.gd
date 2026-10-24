extends RefCounted
const Materials:=preload("res://scripts/world/adelaide_building_material.gd")
const PALETTE:=[Color(.52,.55,.55),Color(.56,.56,.53),Color(.48,.34,.26),Color(.24,.33,.38),Color(.34,.39,.41),Color(.57,.59,.58)]
static func bind(material:ShaderMaterial,kind:int)->void:
	var role:=-1
	if kind>=12 and kind<=17:role=1 if kind==14 else 2 if kind in [15,16] else 0
	elif kind==19:role=5
	elif kind in [3,20]:role=6
	if role<0:return
	var source:=Materials.material(role,0)
	material.set_shader_parameter("city_pbr",true);material.set_shader_parameter("city_role",role)
	material.set_shader_parameter("city_quality",clampi(Settings.effects_quality,0,2))
	for key in ["tile_m","color_gain","surface_albedo","surface_normal","surface_orm"]:material.set_shader_parameter("city_"+key,source.get_shader_parameter(key))
