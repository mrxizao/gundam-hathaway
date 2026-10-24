extends Node
## N61 兵器挂载出图探针：M01 / cmd / F01 / 古斯塔夫，各拍 front / back / side / q34。
##   Godot_v4.7.1-stable_win64_console.exe --path <proj> res://tools/_n61_weapon_shots.tscn -- <out_dir>
## ⛔ 不能加 --headless（dummy 渲染器抓出来是空的）。
## 机头朝 +X（N60 已定）⇒ 相机放 +X 侧即"正视"。

const W := 620
const H := 780
var out_dir := "user://n61_weapon"
var holder: Node3D
var cam: Camera3D

const MODELS := [
	["m01", "res://assets/models/messer/messer_fly.glb"],
	["cmd", "res://assets/models/messer_cmd/messer_cmd_fly.glb"],
	["f01", "res://assets/models/messer_f01/messer_f01_fly.glb"],
	["gustav", "res://assets/models/gustav/gustav_fly.glb"],
]
const VIEWS := [
	["front", Vector3(1.0, 0.0, 0.0)],
	["back", Vector3(-1.0, 0.0, 0.0)],
	["side", Vector3(0.0, 0.0, 1.0)],
	["q34", Vector3(0.85, 0.30, 0.65)],
]


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))
	_build_env()
	await _run()
	print("N61_WEAPON_DONE -> ", out_dir)
	get_tree().quit(0)


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.80, 0.86)
	env.ambient_light_energy = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	sun.light_energy = 1.6
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -55.0, 0.0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)

	holder = Node3D.new()
	add_child(holder)

	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.world_3d = get_viewport().world_3d
	add_child(vp)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)


func _aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var b := mi.get_aabb()
		var g := mi.global_transform
		for i in 8:
			var p := g * b.get_endpoint(i)
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box


func _run() -> void:
	for entry: Array in MODELS:
		var tag: String = entry[0]
		var ps: PackedScene = load(entry[1])
		if ps == null:
			print("[skip] ", tag, "  (", entry[1], ")")
			continue
		for c: Node in holder.get_children():
			c.queue_free()
		await get_tree().process_frame
		var root := ps.instantiate() as Node3D
		holder.add_child(root)
		await get_tree().process_frame
		var box := _aabb(root)
		var ctr := box.get_center()
		var span: float = maxf(box.size.y, maxf(box.size.x, box.size.z))
		cam.size = span * 1.18
		cam.near = 0.01
		cam.far = span * 40.0
		for v: Array in VIEWS:
			var dir: Vector3 = (v[1] as Vector3).normalized()
			cam.global_position = ctr + dir * (span * 6.0)
			cam.look_at(ctr, Vector3.UP)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			# ⚠️ `cam.get_parent()` 的静态类型是 `Node`（没有 get_texture）⇒ 必须显式转型，
			#    否则 `:=` 推断失败 → **Parse Error** → 整个脚本加载不了、进程挂住不退出。
			var vp := cam.get_parent() as SubViewport
			var img: Image = vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.save_png("%s/%s_%s.png" % [out_dir, tag, v[0]])
		print("shot %-8s span %.3f" % [tag, span])
