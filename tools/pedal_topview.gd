extends Node
## **临时**俯视对比：两块飞行踏板的"甲板承载面"到底能站几台、怎么站。
##
## 为什么要它：老板说"马夫蒂踏板前后两台梅萨 / 喀耳刻踏板前后两台古斯塔夫"，
## 而**前后纵列**要求踏板明显**长**于宽。实测两块的 X/Z 尺寸是：
##   马夫蒂 0.9995 × 0.7632（宽 > 长）、喀耳刻 0.9712 × 0.9390（接近正方）
## 都不是"细长"的形状 —— 所以得看**俯视图**才能判断甲板朝哪边、能不能并排。
##
## 跑法（不能加 --headless）：
##   godot --path <工程> res://tools/pedal_topview.tscn -- <输出目录>

const W := 760
const H := 620
var out_dir := "user://pedal_topview"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))
	await get_tree().physics_frame

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.57, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.87, 0.92)
	env.ambient_light_energy = 1.2
	add_child(_wrap_env(env))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 140, 0)
	sun.light_energy = 1.8
	add_child(sun)

	await _sheet("res://assets/models/pedal/mafty_base_jabber.glb", "mafty")
	await _sheet("res://assets/models/pedal/kilce_base_jabber.glb", "kilce")
	# ⚠️ 2026-09-30（N62）：**必须拿搭载态一起拍** ——
	# 上面两块是**空板**，看不出"机体朝哪"。指挥官型板是后加的，
	# 它在模型空间里的朝向（用户手工摆的 −150°）只有跟马夫蒂那套并排看才能判对不对。
	await _sheet("res://assets/models/pedal_states/mafty_both.glb", "mafty_both")
	await _sheet("res://assets/models/pedal_states/messer_cmd_both.glb", "cmd_both")
	print("PEDAL_TOPVIEW_DONE -> ", out_dir)
	get_tree().quit(0)


func _wrap_env(e: Environment) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.environment = e
	return we


func _sheet(path: String, label: String) -> void:
	var ps := load(path)
	if ps == null:
		print("加载失败 ", path)
		return
	var inst := (ps as PackedScene).instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = "Holder_" + label
	add_child(holder)
	holder.add_child(inst)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var box := _measure(inst)
	print("\n[%s] size=(%.3f, %.3f, %.3f)  min=(%.3f, %.3f, %.3f)  max=(%.3f, %.3f, %.3f)" % [
		label, box.size.x, box.size.y, box.size.z,
		box.position.x, box.position.y, box.position.z,
		box.position.x + box.size.x, box.position.y + box.size.y, box.position.z + box.size.z])

	var sheet := Image.create(W * 2, H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.09, 0.11))
	var focus := box.get_center()
	var r := maxf(box.size.length() * 1.15, 0.05)

	# 视图 1：**正上方俯视**（看甲板能站几排）
	var cam1 := Camera3D.new()
	cam1.fov = 34.0
	cam1.near = 0.02
	cam1.far = 4000.0
	add_child(cam1)
	cam1.global_position = focus + Vector3(0.0, r * 1.8, 0.001)
	cam1.look_at(focus, Vector3.UP)
	cam1.current = true
	for i in 4:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img1 := get_viewport().get_texture().get_image()
	img1.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(img1, Rect2i(Vector2i.ZERO, Vector2i(W, H)), Vector2i(0, 0))

	# 视图 2：**正侧视**（看甲板高度剖面与承载面平不平）
	cam1.global_position = focus + Vector3(r * 1.8, r * 0.18, 0.0)
	cam1.look_at(focus, Vector3.UP)
	for i in 4:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img2 := get_viewport().get_texture().get_image()
	img2.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(img2, Rect2i(Vector2i.ZERO, Vector2i(W, H)), Vector2i(W, 0))

	var out := out_dir.path_join("%s_top_side.png" % label)
	print("  SHOT %s err=%d" % [out, sheet.save_png(out)])
	cam1.queue_free()
	holder.queue_free()
	await get_tree().physics_frame


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
