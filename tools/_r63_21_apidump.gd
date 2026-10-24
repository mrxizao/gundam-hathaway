extends Node
## ★63-18 步骤 0a：**直接问引擎**「距离淡出」这套属性/枚举的真名。
## 上一版探针凭记忆写了 `GeometryInstance3D.DISTANCE_FADE_PIXEL_ALPHA` ⇒ 当场 Parse Error。
## 这个脚本只查 ClassDB、不渲染 ⇒ **可以 `--headless` 跑**，几秒出结果。

func _ready() -> void:
	for cls: String in ["GeometryInstance3D", "BaseMaterial3D", "GPUParticles3D", "MeshInstance3D"]:
		print("================ %s ================" % cls)
		var props := PackedStringArray()
		for p in ClassDB.class_get_property_list(cls, false):
			var n := str(p.get("name", ""))
			var low := n.to_lower()
			if low.contains("fade") or low.contains("visibility") or low.contains("transparency"):
				props.append("%s(%s)" % [n, str(p.get("type", -1))])
		print("  [props] %s" % str(props))
		var consts := PackedStringArray()
		for c: String in ClassDB.class_get_integer_constant_list(cls, false):
			if c.to_upper().contains("FADE") or c.to_upper().contains("TRANSPARENCY") \
					or c.to_upper().contains("VISIBILITY"):
				consts.append("%s=%d" % [c, ClassDB.class_get_integer_constant(cls, c)])
		print("  [consts] %s" % str(consts))
		for e: String in ClassDB.class_get_enum_list(cls, false):
			if e.to_lower().contains("fade") or e.to_lower().contains("visibility"):
				var vals := PackedStringArray()
				for k: String in ClassDB.class_get_enum_constants(cls, e, false):
					vals.append("%s=%d" % [k, ClassDB.class_get_integer_constant(cls, k)])
				print("  [enum %s] %s" % [e, str(vals)])
	print("R63_18_APIDUMP_DONE")
	get_tree().quit(0)
