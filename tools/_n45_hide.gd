extends Node3D
## N45：按**件名**隐藏网格后重渲 —— 定位「双脚中间那个方块」到底是哪一件。
##
## ## 为什么要这件工具
##
## 用户截图圈出「双脚中间一个无贴图灰方块」，要求删掉。候选来自
## `parts_table.csv` 里 `bone == Root` 的 **7 件 2~3 三角形碎片**，但
## ⚠️ **不能按坐标列序反推屏幕位置**（该表列序与 `verify.txt` 的「X 左右 / Y 前后」
## 不一致 —— 上轮已因此翻过一次车）⇒ 唯一可靠判据是**净效应隔离**：
## 隐藏某件 → 重渲同一机位 → 那个方块消失 ⇒ 归因成立。
##
## 相机：`front`（az 180°）= 机体**正面**（与用户截图同向）；再加一个**脚部特写**。
##
## 跑法（不能加 `--headless`）：
##   godot --path <工程> res://tools/_n45_hide.tscn -- <输出目录>

const MAIN := "res://assets/models/penelope_movie/penelope_movie_rigged.scn"
const BG := Color(0.12, 0.14, 0.18)

## 候选分组：名字 → 要隐藏的件名列表
const GROUPS := [
	["base", []],
	["hide_p258", ["PEN_z0C_p258"]],
	["hide_p068p181", ["PEN_z0C_p068", "PEN_z0C_p181"]],
	["hide_root7", ["PEN_z0C_p068", "PEN_z0C_p181", "PEN_z0C_p258",
			"PEN_z1C_p139", "PEN_z1C_p140", "PEN_z1C_p184", "PEN_z1C_p257"]],
]

## 机位：tag / focus / 半径 / 方位角 / 仰角
const SHOTS := [
	["full_front", Vector3(0.0, 0.5, 0.0), 0.75, 180.0, 6.0],
	["foot_front", Vector3(0.0, 0.08, 0.0), 0.13, 180.0, 6.0],
]

var _cam: Camera3D
var out_dir := "user://n45_hide"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = str(args[0])
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.86, 0.88, 0.93)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var prof := SuitProfile.penelope()
	var ps := load(prof.model_path) as PackedScene
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	var ma := ModelAnimator.setup(inst, prof.model_anim_files)
	ma.idle_action = prof.model_anim_idle
	ma.prepare_loops()

	var meshes: Array = []
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		meshes.append(c)

	print("=== 网格件总数 %d ===" % meshes.size())
	print("=== 名字含候选号的件 ===")
	for mi: MeshInstance3D in meshes:
		var n := str(mi.name)
		if n.contains("p258") or n.contains("p068") or n.contains("p181") \
				or n.contains("p139") or n.contains("p140") or n.contains("p184") or n.contains("p257"):
			var aabb := mi.mesh.get_aabb()
			print("  %-20s aabb.size=%s pos=%s" % [n, str(aabb.size), str(aabb.position)])

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.near = 0.01
	_cam.far = 200.0
	_cam.current = true
	add_child(_cam)

	if ma.has("fly"):
		ma.play_loop("fly", 0.0, true)
	await _frames(40)

	for g in GROUPS:
		var gname: String = str(g[0])
		var hide_list: Array = g[1]
		var hid := 0
		for mi: MeshInstance3D in meshes:
			var want: bool = not hide_list.has(str(mi.name))
			if mi.visible != want:
				mi.visible = want
			if not want:
				hid += 1
		await _frames(3)	# 让渲染同步
		print("---- 组 %s：隐藏 %d 件 ----" % [gname, hid])
		for s in SHOTS:
			await _place(s[1], float(s[2]), float(s[3]), float(s[4]))
			await _save("%s_%s" % [gname, str(s[0])])

	print("")
	print("VERDICT: N45-HIDE-PART-DONE  → %s" % out_dir)
	get_tree().quit(0)


func _place(focus: Vector3, radius: float, az_deg: float, el_deg: float) -> void:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	_cam.global_position = focus + dir * radius * 2.8
	_cam.look_at(focus, Vector3.UP)
	await _frames(3)


func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("    !! %s 取不到图" % tag)
		return
	var p: String = out_dir.path_join(tag + ".png")
	img.save_png(p)
	print("    saved %s" % p.get_file())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
