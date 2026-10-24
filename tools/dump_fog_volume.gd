extends SceneTree
## 一次性工具：dump `FogVolume` / `FogMaterial` 的**真实**属性名与取值范围。
##
## 与 `dump_env_props.gd` 同一个理由：这批工程的规矩是"**属性名不猜**"。
## 典型的坑：`StandardMaterial3D` 上没有 `specular`（是 `metallic_specular`）、
## `ArrayMesh` 没有 `material`（要 `material_override`）—— 两次都只在真渲染时报错，
## `--check-only` 语法闸**查不出**。
##
## 用法：
##   ... --script res://tools/dump_fog_volume.gd [名字过滤]
func _init() -> void:
	var filter := ""
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		filter = argv[0].to_lower()

	print("=== FogVolume 属性 ===")
	var fv := FogVolume.new()
	for p in fv.get_property_list():
		if p["type"] == TYPE_NIL:
			continue
		if not (p["usage"] & PROPERTY_USAGE_EDITOR):
			continue
		var nm := String(p["name"])
		if filter != "" and not nm.to_lower().contains(filter):
			continue
		print("  %-40s type=%-3d  value=%s" % [nm, p["type"], str(fv.get(nm))])

	print()
	print("=== FogMaterial 属性（含 hint 范围）===")
	var fm := FogMaterial.new()
	for p in fm.get_property_list():
		if p["type"] == TYPE_NIL:
			continue
		if not (p["usage"] & PROPERTY_USAGE_EDITOR):
			continue
		var nm := String(p["name"])
		if filter != "" and not nm.to_lower().contains(filter):
			continue
		var hint := ""
		if p.has("hint_string") and String(p["hint_string"]) != "":
			hint = "  hint=%s" % String(p["hint_string"])
		print("  %-40s type=%-3d  value=%s%s" % [nm, p["type"], str(fm.get(nm)), hint])

	print()
	print("=== FogVolume 的 shape 是节点属性（MeshInstance3D 那样） ===")
	print("  shape            -> %s" % str(fv.get("shape")))
	print("  mesh             -> %s" % str(fv.get("mesh")))
	print()
	print("=== 相关 Environment 开关（复核高度雾没有 volumetric 版本）===")
	var env := Environment.new()
	for nm in ["fog_enabled", "fog_mode", "fog_density", "fog_height",
			"fog_height_density", "fog_aerial_perspective", "fog_sky_affect",
			"volumetric_fog_enabled", "volumetric_fog_density",
			"volumetric_fog_length", "volumetric_fog_anisotropy",
			"volumetric_fog_sky_affect", "volumetric_fog_emission_energy"]:
		print("  %-36s = %s" % [nm, str(env.get(nm))])
	quit()
