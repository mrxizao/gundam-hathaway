extends Node
## 机体模型体检工具：把工程里的 GLB 逐个摆到干净背景里，从四个方位渲染成一张对比图。
##
## 跑法（**不能加 --headless**，headless 是 dummy 渲染器，抓出来是空的）：
##   godot --path <工程> res://tools/model_shots.tscn -- <输出目录> <res://模型路径> [...]
##
## 用途：新模型接进游戏之前先确认三件事 —— **朝向对不对（−Z 是不是正面）、
## 比例对不对（全高）、有没有一堆散落的碎片**。这三件事光看 GLB 的包围盒是看不出来的：
## 包围盒只能告诉你"有多大"，不能告诉你"是不是散架的"（阿利宙斯常态就是这么发现的）。

const SHOT_W := 480
const SHOT_H := 600
## ⚠️ 视角是拿**相机位置**命名的，不是"绕着模型转的角度"：
## 机体的正面朝 −Z（glTF/Godot 惯例），所以"正面视图"的相机必须站在 **−Z 一侧**，
## 也就是 `sin/cos` 参数取 180°，不是 0°。第一版把 0° 标成 front，
## 于是四台机全被看成了背面（阿利宙斯的巡航形态差点被误判成朝向反了）。
const VIEWS := [180, 90, 0, 270]
const VIEW_NAMES := ["front", "right(+X)", "back", "left(−X)"]

var out_dir := "user://model_shots"


## 用法：-- <输出目录> <res://模型路径> [...]
## 额外可选：末尾加 `--morph 0.5` 可以把所有 blend shape 推到指定值 ——
## 柯西的巡航形态是 morph target，靠它才能拍到"变形到一半"那一帧。
var morph_value := -1.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 0:
		push_error("用法：-- <输出目录> <res://模型路径> [...] [--morph 0..1]")
		get_tree().quit(2)
		return
	out_dir = args[0]
	var models: Array[String] = []
	var i := 1
	while i < args.size():
		if args[i] == "--morph" and i + 1 < args.size():
			morph_value = float(args[i + 1])
			i += 2
			continue
		models.append(args[i])
		i += 1
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	var env_root := _build_rig()
	var index := 0
	for path: String in models:
		index += 1
		await _shoot_model(path, env_root, index)
	print("MODEL_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0)


## 干净背景 + 一盏灯。
## 背景刻意用**中亮灰**（0.62）而不是深色：体检要能同时看清
## "亮色的机体"和"嵌在旁边的黑色废料"。第一版用深色背景，
## 结果黑色废料和背景糊在一起，阿利宙斯两侧的黑色碎片完全没被发现。
func _build_rig() -> Node3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.63, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.85)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 132, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -60, 0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)

	var root := Node3D.new()
	root.name = "Holder"
	add_child(root)
	return root


## 单个模型：算包围盒 → 摆相机 → 四个方位各抓一张 → 拼成一张对比图。
func _shoot_model(path: String, holder: Node3D, index: int) -> void:
	for c in holder.get_children():
		c.free()
	var label := path.get_file().get_basename()
	# 主场景是唯一的相机来源：这里临时把 Game 的相机停掉，避免两个 current 打架
	if not ResourceLoader.exists(path):
		push_error("模型不存在：%s" % path)
		return
	var res := load(path)
	var inst: Node3D = null
	if res is PackedScene:
		inst = (res as PackedScene).instantiate() as Node3D
	if inst == null:
		push_error("不是 PackedScene：%s" % path)
		return
	holder.add_child(inst)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# morph target：把每个网格的每个 blend shape 都推到同一个值（0 = 正常形态，1 = 巡航形态）
	if morph_value >= 0.0:
		var n := 0
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			for s in mi.mesh.get_blend_shape_count():
				mi.set_blend_shape_value(s, morph_value)
				n += 1
		print("  morph=%.2f 应用到 %d 个 blend shape" % [morph_value, n])

	var box := _measure(inst)
	print("[%02d] %s  size=(%.3f, %.3f, %.3f)  center=(%.3f, %.3f, %.3f)  min_y=%.3f" % [
		index, label, box.size.x, box.size.y, box.size.z,
		box.get_center().x, box.get_center().y, box.get_center().z, box.position.y])

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.02
	cam.far = 4000.0
	cam.current = true
	add_child(cam)

	var sheet := Image.create(SHOT_W * VIEWS.size(), SHOT_H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.10, 0.11, 0.13))
	var radius := maxf(box.size.length() * 0.95, 0.05)
	var focus := box.get_center()
	for v in VIEWS.size():
		var a := deg_to_rad(float(VIEWS[v]))
		cam.global_position = focus + Vector3(sin(a) * radius, radius * 0.28, cos(a) * radius)
		cam.look_at(focus, Vector3.UP)
		for _i in 3:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			push_error("抓图失败：%s" % label)
			continue
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i(SHOT_W * v, 0))
	var out := out_dir.path_join("%02d_%s_sheet.png" % [index, label])
	print("  -> %s   (视图顺序 %s)" % [out, ", ".join(VIEW_NAMES)])
	sheet.save_png(out)
	cam.queue_free()
	inst.queue_free()


## 合并可见网格的世界包围盒，再折算回 holder 局部空间。
func _measure(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var owner_node := node.get_parent() as Node3D
	var inv := owner_node.global_transform.affine_inverse() if owner_node != null \
		else Transform3D.IDENTITY
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	if first:
		out = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return out
