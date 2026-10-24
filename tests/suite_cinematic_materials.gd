extends RefCounted
const MATERIALS = preload("res://scripts/flight/suit_materials.gd")

static func run(t: T, host: Node) -> void:
	t.suite("CinematicMaterials / actual model surfaces, switching and immutable geometry")
	var old_placeholder := FlightBody.use_placeholder
	var old_cel := Settings.cel_shading
	FlightBody.use_placeholder = false
	Settings.cel_shading = false
	var stage := Node3D.new()
	host.add_child(stage)
	for profile in [SuitProfile.xi_final(), SuitProfile.gustav00_armed(), SuitProfile.xi()]:
		var body := FlightBody.new()
		body.profile = profile
		body.is_player = true
		body.projectile_container = stage
		stage.add_child(body)
		body.position = Vector3(0,3000,0)
		body.set_physics_process(false)
		var pbr: bool = profile.id != SuitProfile.Id.XI
		var lit_count := 0
		var normal_count := 0
		var roles: Dictionary = {}
		var checked_textures: Dictionary = {}
		var snapshots: Array = []
		for node in body.model_root.find_children("*","MeshInstance3D",true,false):
			var mi := node as MeshInstance3D
			if mi.mesh == null: continue
			snapshots.append([mi,mi.mesh,mi.skin,mi.transform,mi.visibility_range_end])
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
				var mat := mi.get_active_material(i) as StandardMaterial3D
				if src == null or mat == null or src.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: continue
				lit_count += 1
				t.eq(mat.albedo_texture,src.albedo_texture,"original base-color texture retained")
				t.eq(mat.normal_texture,src.normal_texture,"original normal texture retained")
				t.eq(mat.transparency,src.transparency,"authored transparency retained")
				t.near(mat.albedo_color.a,src.albedo_color.a,.0001,"opacity is not multiplied with color")
				if pbr:
					t.eq(mat.diffuse_mode,BaseMaterial3D.DIFFUSE_BURLEY,"continuous physical diffuse")
					t.eq(mat.specular_mode,BaseMaterial3D.SPECULAR_SCHLICK_GGX,"physical specular")
					t.not_ok(mat.rim_enabled,"no artificial toon rim")
					var role: String = mat.get_meta("cinematic_surface_role","")
					roles[role]=true
					var rough := mat.roughness_texture
					if rough != null and not checked_textures.has(rough.get_instance_id()):
						checked_textures[rough.get_instance_id()]=true
						t.ok(rough.get_image().has_mipmaps(),"material data textures have mipmaps for distant stability")
					if src.normal_enabled and src.normal_texture != null: normal_count += 1
				else:
					t.eq(mat.diffuse_mode,BaseMaterial3D.DIFFUSE_TOON,"unselected suit keeps legacy rendering")
		if pbr:
			t.gt(lit_count,200,"actual imported model was tested")
			t.ok(roles.has("frame") and roles.has("paint"),"armor and frame are separate materials")
			if profile.id == SuitProfile.Id.XI_FINAL: t.gt(normal_count,200,"Xi authored normal maps remain active")
		var model := body.model_root
		var skeleton := body._model_skel
		var muzzle := body._rifle_muzzle_local(0)
		var hp := body.hp
		body.set_cloud_shade(.55)
		for enabled in [true,false,true,false]:
			Settings.cel_shading = enabled
			Settings.changed.emit()
			t.eq(body.model_root,model,"style switch does not rebuild model")
			t.eq(body._model_skel,skeleton,"style switch retains animated skeleton")
			t.near(body.hp,hp,.0001,"style switch does not change combat state")
			t.lt(body._rifle_muzzle_local(0).distance_to(muzzle),.0001,"weapon muzzle stays aligned")
			t.near(body.cloud_shade(),.55,.0001,"cloud shade survives style switch")
			for snap in snapshots:
				var mi: MeshInstance3D = snap[0]
				t.eq(mi.mesh,snap[1],"original mesh resource retained")
				t.eq(mi.skin,snap[2],"skin binding retained")
				t.eq(mi.transform,snap[3],"part transform retained")
				t.eq(mi.visibility_range_end,snap[4],"LOD ranges retained")
			if pbr:
				for mat in body._shade_mats:
					if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: continue
					t.eq(mat.diffuse_mode,BaseMaterial3D.DIFFUSE_TOON if enabled else BaseMaterial3D.DIFFUSE_BURLEY,"existing setting switches actual surface shading")
		if profile.id == SuitProfile.Id.GUSTAV00:
			for kind in [FlightPedal.Kind.KILCE,FlightPedal.Kind.GUSTAV_SINGLE]:
				var board := FlightPedal.new()
				stage.add_child(board)
				board.setup(body,kind)
				var board_model := board._model
				for enabled in [true,false]:
					Settings.cel_shading=enabled
					Settings.changed.emit()
					t.eq(board._model,board_model,"mounted rider style switch retains platform geometry")
					var count := 0
					for node in board._model.find_children("*","MeshInstance3D",true,false):
						var mi := node as MeshInstance3D
						if mi.mesh == null: continue
						for i in mi.mesh.get_surface_count():
							var mat := mi.get_active_material(i) as StandardMaterial3D
							if mat == null or mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: continue
							count+=1
							t.eq(mat.diffuse_mode,BaseMaterial3D.DIFFUSE_TOON if enabled else BaseMaterial3D.DIFFUSE_BURLEY,"embedded Gustav follows material style")
					t.gt(count,0,"actual mounted model tested")
				board.free()
		body.free()
	var unlit := StandardMaterial3D.new()
	unlit.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	unlit.emission_enabled=true
	unlit.emission_energy_multiplier=2.7
	MATERIALS.apply(unlit,SuitProfile.Id.XI_FINAL)
	t.near(unlit.emission_energy_multiplier,2.7,.0001,"emissive FX retain brightness")
	t.not_ok(unlit.clearcoat_enabled,"unlit FX do not gain a paint layer")
	Settings.cel_shading=old_cel
	FlightBody.use_placeholder=old_placeholder
	stage.free()
	await host.get_tree().process_frame
