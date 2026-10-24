extends Node
## **踏板朝向四选一**（1.2 第二十三轮）。
##
## 用户报「梅萨的踏板还是**左边朝前**」—— 和机体那边同一个病：
## 模型导出的朝向和工程约定（正面朝 −Z）不一致。
##
## ⚠️ 我在这台机上已经因为"看图判断朝向"错过三次（见
## `SuitProfile.model_yaw_deg` 的长注释），所以这里**不推断、只出图给用户点**。
##
## 一格一个候选角（0 / 90 / 180 / 270），机位在**踏板后方偏上** ——
## 和游戏里的追尾镜头同一个视角，所以"哪一格看着对"就是答案。
##
## 跑法（不能加 --headless）：
##   godot --path <工程> res://tools/pedal_yaw_choices.tscn -- <输出目录> [kind]
##   kind 省略 = 两种板各出一张。

const YAWS := [0.0, 90.0, 180.0, 270.0]
const W := 460
const H := 620
const SUIT := 4  # 每个候选格渲几个角度？这里不做多角度，固定一个机位

var out_dir := "user://pedal_yaw_choices"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var kinds := [FlightPedal.Kind.MAFTY, FlightPedal.Kind.KILCE]
	if args.size() > 1:
		kinds = [int(args[1])]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_energy = 1.5
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.66)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.near = 1.0
	cam.far = 40000.0
	add_child(cam)
	cam.current = true

	for k: int in kinds:
		await _sheet(cam, k)
	print("PEDAL_YAW_CHOICES_DONE -> ", out_dir)
	get_tree().quit(0)


func _sheet(cam: Camera3D, kind: int) -> void:
	var sheet := Image.create(W * YAWS.size(), H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.10, 0.11, 0.14))
	for i in YAWS.size():
		var holder := Node3D.new()
		add_child(holder)
		var prof := SuitProfile.messer_m01() if kind == FlightPedal.Kind.MAFTY \
			else SuitProfile.gustav00_armed()
		var rider := BanditAI.new()
		rider.team = 0
		rider.profile = prof
		rider.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
		holder.add_child(rider)
		rider.global_position = Vector3(0.0, 3000.0, 0.0)
		rider.set_physics_process(false)
		await get_tree().physics_frame
		# 直接给一块板、并**临时把候选角写进去**
		var board := FlightPedal.new()
		holder.add_child(board)
		board.setup(rider, kind)
		board.model_yaw_override = YAWS[i]
		board.rebuild_visual_for_test()
		await get_tree().physics_frame

		var focus := board.global_position
		var L := FlightPedal.game_length_of(kind)
		# **踏板后方偏上** —— 和游戏追尾镜头同一个方向。
		# 谁的"前"朝得对，一眼就能看出来（和梅萨那次同一个题）。
		cam.global_position = focus + Vector3(0.0, L * 0.55, L * 1.35)
		cam.look_at(focus, Vector3.UP)
		for f in 4:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.convert(Image.FORMAT_RGBA8)
			img.resize(W, H, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(W, H)), Vector2i(W * i, 0))
		holder.queue_free()
		await get_tree().physics_frame
	var out := out_dir.path_join("PEDAL_yaw_choices_%s.png" % FlightPedal.kind_name(kind))
	print("SHOT %s err=%d" % [out, sheet.save_png(out)])
	print("  四格从左到右：yaw = 0 / 90 / 180 / 270。")
	print("  机位在**踏板后方偏上** —— **机头（或板的前端）朝画面外侧的那一格是对的**。")
