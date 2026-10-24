extends Node
## N62：俯视 + 前视对比「马夫蒂搭乘态」与「指挥官型搭乘态」的**机体朝向**。
##
## 为什么要专门拍这个：`messer_cmd_*` 里机体在模型空间的朝向是**用户手工摆的
## −150°**，而 `mafty_both` 里那台是 **−163.72°**。两者差 13.72° ——
## 斜上四分之三机位看不出来，**俯视图**才能一眼判"有没有歪"。
##
## 跑法（不能加 --headless）：
##   godot --path <工程> res://tools/_n62_pedal_top.tscn -- <输出目录>

var out_dir := "user://n62_top"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1100, 820))
	await get_tree().physics_frame

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 34.0, 0.0)
	sun.light_energy = 1.5
	add_child(sun)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_energy = 1.15
	we.environment = e
	add_child(we)

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.02
	cam.far = 4000.0
	add_child(cam)
	cam.current = true

	for it: Array in [
		["res://assets/models/pedal_states/mafty_both.glb", "A_mafty_both"],
		["res://assets/models/pedal_states/messer_cmd_both.glb", "B_cmd_both"],
	]:
		await _shoot(cam, str(it[0]), str(it[1]))

	print("N62_PEDAL_TOP_DONE -> ", out_dir)
	get_tree().quit(0)


func _shoot(cam: Camera3D, path: String, label: String) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		print("加载失败 ", path)
		return
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	for i in 4:
		await get_tree().physics_frame
	var box := _measure(inst)
	var c := box.get_center()
	var r := maxf(box.size.length(), 1.0)
	print("[%s] box size=(%.3f %.3f %.3f) center=(%.3f %.3f %.3f)"
		% [label, box.size.x, box.size.y, box.size.z, c.x, c.y, c.z])

	# ---- 图 1：正上方俯视（屏幕上方 = 世界 −Z = 机首方向）----
	#
	# ⚠️ 俯视时 `look_at` 的 up **不能**用 `Vector3.UP`（与视线平行 ⇒ 姿态退化），
	# 用 `Vector3.BACK`(= +Z 的反向，即屏幕上方向指向 −Z)。
	cam.global_position = c + Vector3(0.0, r * 1.45, 0.0)
	cam.look_at(c, Vector3(0.0, 0.0, -1.0))
	await _snap(cam, "%s_top.png" % label)

	# ---- 图 2：正前方（从 −Z 平视，能看到"正脸"就是朝向对）----
	cam.global_position = c + Vector3(0.0, box.size.y * 0.35, -r * 1.25)
	cam.look_at(c, Vector3.UP)
	await _snap(cam, "%s_front.png" % label)

	inst.queue_free()
	await get_tree().physics_frame


func _snap(cam: Camera3D, name: String) -> void:
	for i in 4:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		print("SHOT_FAILED ", name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(img) ", name)
		return
	var p := out_dir.path_join(name)
	print("SHOT %s err=%d" % [p, img.save_png(p)])


func _measure(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out
