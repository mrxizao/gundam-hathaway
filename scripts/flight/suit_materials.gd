extends RefCounted
## Runtime overrides only: imported geometry, UVs, normal maps and animations stay intact.
## Other suits keep their existing material path until they receive individual calibration.
const PRESETS = preload("res://assets/materials/cinematic_suits/presets.gd")
const GRAIN_PATH := "res://assets/materials/cinematic_suits/matte_grain.png"
static var _grain: Texture2D
static var _textures: Dictionary = {}

static func supports(suit_id: int) -> bool:
	return suit_id in [SuitProfile.Id.XI_FINAL, SuitProfile.Id.GUSTAV00]

static func realistic(suit_id: int) -> bool:
	return supports(suit_id) and not Settings.cel_shading

static func apply(mat: StandardMaterial3D, suit_id: int, embedded := false) -> void:
	if mat == null or mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return
	if not realistic(suit_id):
		FX.toonify(mat)
		return
	var key := "xi_final" if suit_id == SuitProfile.Id.XI_FINAL else "gustav"
	var table: Dictionary = PRESETS.DATA.get(key, {})
	# Embedded platform exports have different part numbering; never apply a rider's part table.
	var preset: Dictionary = {} if embedded else table.get(mat.resource_name, {})
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mat.rim_enabled = false
	mat.metallic_specular = 0.45
	mat.roughness = float(preset.get("roughness", 0.64))
	mat.metallic = float(preset.get("metallic", 0.06))
	if preset.has("orm"):
		var path: String = preset.orm
		if not _textures.has(path):
			_textures[path] = load(path)
		mat.roughness_texture = _textures[path]
		mat.metallic_texture = _textures[path]
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	elif mat.roughness_texture == null:
		if _grain == null:
			_grain = load(GRAIN_PATH)
		mat.roughness_texture = _grain
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	# Keep authored normal maps; reduce the oversharp grain on Xi's existing scanned surface.
	if mat.normal_enabled and mat.normal_texture != null:
		mat.normal_scale *= 0.6
	mat.clearcoat = float(preset.get("clearcoat", 0.05))
	mat.clearcoat_enabled = mat.clearcoat > 0.0 and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.clearcoat_roughness = 0.55
	mat.set_meta("cinematic_suit_material", key)
	mat.set_meta("cinematic_surface_role", preset.get("role", "paint"))
