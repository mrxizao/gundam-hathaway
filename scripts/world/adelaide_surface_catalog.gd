extends RefCounted
## Semantic terrain and road library, in final world metres. Never consumes city RNG.
const Ground := preload("res://scripts/world/adelaide_ground_material.gd")
const Road := preload("res://scripts/world/road_surface.gd")
const CONCRETE := 3
const PATCH := 4
const PAINT := 5
const DRAIN := 6
const GRASS := 1
const ASPHALT := 2
const SITES := [
	{"id":"airport","label":"机场草坪与跑道","bounds":Rect2(-15600,5200,3400,3200)},
	{"id":"street","label":"市区街口","bounds":Rect2(-6500,-500,3300,3600)},
	{"id":"festival","label":"节庆中心与林荫道","bounds":Rect2(3000,-36000,5200,6500)}]
const GRASS_TILE_M := 2.51
const ASPHALT_TILE_M := 2.35
static func batch_key(color:Color,kind:int,region:String,family:int)->String:
	return color.to_html()+"|"+str(kind)+"|"+region+"|"+str(family)
static func parcel_record(ix:int,iz:int,rect:Rect2,height:float,color:Color)->Dictionary:
	return {"id":"parcel_%02d_%02d"%[ix,iz],"seed":(ix*73856093)^(iz*19349663),"bounds":Rect2(rect.position*18.0,rect.size*18.0),"height":height,"color":color,"damaged":false}
static func sample_weight(point:Vector2)->float:
	var weight:=0.0
	for site:Dictionary in SITES:
		var box:Rect2=site.bounds
		var d:Vector2=(point-box.get_center()).abs()-box.size*.5
		weight=maxf(weight,1.0-smoothstep(-80.0,0.0,maxf(d.x,d.y)))
	return weight
static func material(family:int,color:Color,kind:int)->ShaderMaterial:
	if family==GRASS and color.r<0.6:return Ground.material(color,kind)
	if family>=ASPHALT:
		var road:=Road.material(family-2,color,true)
		road.set_shader_parameter("surface_family",family)
		road.set_shader_parameter("material_kind",kind)
		return road
	var result:=ShaderMaterial.new()
	result.shader=load("res://shaders/adelaide_surface_trial.gdshader")
	result.set_shader_parameter("base_color",color)
	result.set_shader_parameter("material_kind",kind)
	result.set_shader_parameter("surface_family",family)
	result.set_shader_parameter("tile_m",GRASS_TILE_M if family==GRASS else ASPHALT_TILE_M)
	var asset:="grass_ground" if family==GRASS else "asphalt_floor"
	for pair in [["surface_albedo","diff"],["surface_normal","nor_gl"],["surface_orm","arm"]]:
		result.set_shader_parameter(pair[0],load("res://assets/materials/adelaide_pbr/"+asset+"_"+pair[1]+"_2k.png"))
	var bounds:=PackedVector4Array()
	for site:Dictionary in SITES:
		var box:Rect2=site.bounds
		bounds.append(Vector4(box.get_center().x,box.get_center().y,box.size.x*.5,box.size.y*.5))
	result.set_shader_parameter("trial_bounds",bounds)
	return result
