extends SceneTree
## 临时：查 SkeletonModifier3D 的默认状态（用完即删）。

func _init() -> void:
	var m := SkeletonModifier3D.new()
	print("默认 active   = ", m.active)
	print("默认 influence= ", m.influence)
	print("继承链: ", ClassDB.get_parent_class("SkeletonModifier3D"))
	print("set_influence 存在 = ", ClassDB.class_has_method("SkeletonModifier3D", "set_influence"))
	print("")
	print("Skeleton3D 是否自己驱动 modifier（有无骨架求值通知相关方法）:")
	for mm in ["get_modifier_count", "get_modifier", "add_child"]:
		print("  Skeleton3D.%-20s %s" % [mm, str(ClassDB.class_has_method("Skeleton3D", mm))])
	print("")
	print("Node3D 父类上有没有 skeleton 求值钩子:")
	for mm in ["set_bone_pose_rotation", "get_bone_pose_rotation"]:
		print("  SkeletonModifier3D.%-24s %s" % [mm, str(ClassDB.class_has_method("SkeletonModifier3D", mm))])
	quit()
