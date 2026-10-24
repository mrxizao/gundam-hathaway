extends RefCounted
static func state(world: WorldBuilder) -> Dictionary:
	var result: Dictionary={"sun_color":world.sun.light_color,"sun_energy":world.sun.light_energy,"sun_rotation":world.sun.rotation_degrees}
	for property in ["ambient_light_sky_contribution","ambient_light_color","ambient_light_energy","tonemap_exposure","glow_intensity","glow_bloom","glow_hdr_threshold","adjustment_contrast","adjustment_saturation","fog_light_color","fog_density","fog_sky_affect","fog_sun_scatter","fog_aerial_perspective","volumetric_fog_anisotropy"]:
		result[property]=world._env.get(property)
	for uniform in ["zenith","horizon","disc_dir","star_amount","scatter_strength","scatter_power","scatter_color"]:
		result[uniform]=world._sky_mat.get_shader_parameter(uniform)
	return result
static func run(t: T,host: Node) -> void:
	t.suite("CinematicLighting / map identities and legacy preset contracts")
	t.eq(MapDef.adelaide().time_of_day.preset,TimeOfDay.Preset.DAY,"Adelaide remains daytime")
	t.eq(MapDef.oenbelli().time_of_day.preset,TimeOfDay.Preset.DUSK,"Oenbelli remains overcast dusk")
	t.eq(MapDef.oenbelli().city_lights,MapDef.CityLights.POSTS_ONLY,"dead-city lights remain off")
	t.eq(MapDef.davao().time_of_day.preset,TimeOfDay.Preset.NIGHT,"Davao remains night")
	t.eq(MapDef.pacific().time_of_day.preset,TimeOfDay.Preset.NIGHT,"Pacific remains night")
	t.eq(TimeOfDay.night().sun_energy,0.44,"shared moon preset retained")
	t.eq(TimeOfDay.night().ambient_sky_contribution,1.0,"shared night fill contract retained")
	t.eq(TimeOfDay.space().fog_density,0.0,"space retains no atmospheric distance fog")
	t.eq(TimeOfDay.space().sky_scatter_strength,0.0,"no atmospheric solar scattering in space")
	t.eq(TimeOfDay.dusk_overcast().disc_amount,0.0,"shared overcast has no sun disc")
	var ad:=MapDef.adelaide().time_of_day
	t.gt(ad.sun_color.r,ad.sun_color.b,"warm key light")
	t.gt(ad.ambient_color.b,ad.ambient_color.r,"cool shadow fill")
	t.lt(ad.glow_bloom,0.06,"highlight bloom is restrained")
	t.gt(ad.glow_hdr_threshold,1.1,"ordinary bright armor does not trigger broad bloom")
	t.suite("CinematicLighting / runtime environment, map order and quality gates")
	var world:=WorldBuilder.new()
	world.defer_initial_map=true
	host.add_child(world)
	world.set_process(false)
	var fresh: Dictionary={}
	for map_id in MapDef.Id.values():
		world.apply_time_of_day(MapDef.by_id(map_id).time_of_day)
		fresh[map_id]=state(world)
	for map_id in [MapDef.Id.ADELAIDE,MapDef.Id.DAVAO,MapDef.Id.PACIFIC,MapDef.Id.OENBELLI,MapDef.Id.LEO,MapDef.Id.ADELAIDE,MapDef.Id.RANGE,MapDef.Id.ULURU]:
		world.apply_time_of_day(MapDef.by_id(map_id).time_of_day)
		t.eq(state(world),fresh[map_id],"map grade is independent of previous map: "+str(map_id))
		var desired:=MapDef.by_id(map_id).time_of_day
		t.near(world._env.tonemap_exposure,desired.exposure,.0001,"manual exposure follows active map")
		t.lt(world.sun.global_basis.z.normalized().distance_to(world._sky_mat.get_shader_parameter("disc_dir")),.0001,"visible sun and actual lighting direction agree")
	# Applying a grade must not force expensive effects back on.
	world._env.glow_enabled=false
	world._env.volumetric_fog_enabled=false
	world.apply_time_of_day(ad)
	t.not_ok(world._env.glow_enabled,"quality-disabled glow remains disabled")
	t.not_ok(world._env.volumetric_fog_enabled,"quality-disabled volume fog remains disabled")
	world.apply_time_of_day(TimeOfDay.night())
	t.near(world._env.adjustment_saturation,1.05,.0001,"manual preset change clears map saturation")
	t.eq(world._sky_mat.get_shader_parameter("scatter_strength"),0.0,"manual preset change clears map scattering")
	world.free()
	await host.get_tree().process_frame
