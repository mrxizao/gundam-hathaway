extends SceneTree
func _init() -> void:
	print("=== FogVolume 的常量 / 枚举 ===")
	for c in ClassDB.class_get_integer_constant_list("FogVolume", true):
		print("  %s = %d" % [c, ClassDB.class_get_integer_constant("FogVolume", c)])
	print("=== 枚举表 ===")
	for e in ClassDB.class_get_enum_list("FogVolume", true):
		print("  enum %s" % e)
	print("=== shape 属性的 hint_string ===")
	for p in FogVolume.new().get_property_list():
		if String(p["name"]) == "shape":
			print("  hint_string = %s" % String(p["hint_string"]))
	quit()
