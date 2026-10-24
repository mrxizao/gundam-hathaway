extends RefCounted
## Shared, world-metre terrain material. Layout masks are baked from actual Adelaide geometry.
const MASK_BOUNDS:=Rect2(-65000,-65000,145000,130000)
const MASK_DISTANCE_M:=512.0
const TILE_M:=2.0
const ASSETS:=["leafy_grass","withered_grass","dirt"]
const MEANS:=[Vector3(0.12,0.145,0.065),Vector3(0.19,0.165,0.095),Vector3(0.105,0.078,0.052)]
## Generated from ground_calibration.json; runtime/export needs no loose JSON file.
const GAINS:=[
	Vector3(0.3681883682505692,0.6064056884211139,0.6005375086761126),
	Vector3(0.4411516200192752,0.5334917288757938,0.4631406791084899),
	Vector3(0.8332036113785168,0.9108491158992214,1.0643875042827273)]
static func material(color:Color,kind:int)->ShaderMaterial:
	var result:=ShaderMaterial.new()
	result.shader=load("res://shaders/adelaide_ground.gdshader")
	result.set_shader_parameter("base_color",color)
	result.set_shader_parameter("material_kind",kind)
	result.set_shader_parameter("surface_family",1)
	result.set_shader_parameter("tile_m",TILE_M)
	for layer in 3:
		var asset:String=ASSETS[layer]
		var names:Array=[["surface_albedo","surface_normal","surface_orm"],["dry_albedo","dry_normal","dry_orm"],["soil_albedo","soil_normal","soil_orm"]][layer]
		for channel in 3:
			var suffix:String=["diff","nor_gl","arm"][channel]
			result.set_shader_parameter(names[channel],load("res://assets/materials/adelaide_pbr/"+asset+"_"+suffix+"_2k.png"))
		result.set_shader_parameter(["green_gain","dry_gain","soil_gain"][layer],GAINS[layer])
		result.set_shader_parameter(["green_mean","dry_mean","soil_mean"][layer],MEANS[layer])
	result.set_shader_parameter("ground_mask",load("res://assets/materials/adelaide_pbr/adelaide_ground_mask.png"))
	result.set_shader_parameter("mask_bounds",Vector4(MASK_BOUNDS.position.x,MASK_BOUNDS.position.y,MASK_BOUNDS.size.x,MASK_BOUNDS.size.y))
	return result
static func sample_mask(image:Image,point:Vector2)->Color:
	if not MASK_BOUNDS.has_point(point):return Color(1,1,0,0)
	var uv:Vector2=(point-MASK_BOUNDS.position)/MASK_BOUNDS.size
	return image.get_pixel(clampi(int(uv.x*image.get_width()),0,image.get_width()-1),clampi(int(uv.y*image.get_height()),0,image.get_height()-1))
