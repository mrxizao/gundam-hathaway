extends SceneTree
func _init() -> void:
	var fv := FogVolume.new()
	print("=== shape 属性 ===")
	for p in fv.get_property_list():
		if String(p["name"]) == "shape":
			print("  type=%d hint=%d hint_string=%s" % [p["type"], p["hint"], p["hint_string"]])
	print("  default shape = %d" % fv.shape)
	print("=== ClassDB 常量 ===")
	print("  ", ClassDB.class_get_integer_constant_list("FogVolume", true))
	print("=== RenderingServer 里有 FogVolumeShape 吗 ===")
	var rs := ClassDB.class_get_integer_constant_list("RenderingServer", true)
	var hit := []
	for c in rs:
		if String(c).contains("FOG_VOLUME"):
			hit.append(c)
	print("  ", hit)
	print("=== FogMaterial 属性 ===")
	for p in FogMaterial.new().get_property_list():
		print("  %s (%d) = %s" % [p["name"], p["type"], str(p.get("hint_string", ""))])
	quit()
