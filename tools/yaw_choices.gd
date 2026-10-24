extends Node
## **临时**诊断（第十九轮前置）：**俯视**盯着机头看 —— 梅萨M01 到底该转多少度。
##
## ## 为什么有这个工具
## 用户在游戏里反馈"梅萨的模型方向不对，现在是左边朝前面了"。
## 我先试了"看 yaw_check 的正面/背面图"，**误判两次**（把背面看成脸、又把侧面看成脸）；
## 再试"量头部前额冠偏向哪一轴"，结果**方法不自洽**：
## 它把**已经确认正确**的佩涅罗佩与古斯塔夫都判成"需要转 180°"，
## 而这两台机在游戏里一直是对的。所以那个启发式在这批模型上不可信，废弃。
##
## **最终做法：不推断，直接出四选一。** 俯视图最不容易看错 ——
## 机头（尖的那头）与机尾（有喷口/背包的那头）在俯视下方向感最强。
##
## 跑法（不能加 --headless）：
##   godot --path <工程> res://tools/yaw_choices.tscn -- <输出目录> <机体id> <俯仰角>
##
## ⚠️ 用法提醒：这个脚本会**临时改 `prof.model_yaw_deg`** 来出四格对照图。
## `SuitProfile.by_id()` 每次都新建一份 profile，所以改它**不会**写回代码 ——
## 但如果你正在同一个进程里拿它当"确认最终值"用，记得以磁盘上的代码为准。

const W := 460
const H := 620
var out_dir := "user://yaw_choices"
## 四个待选角度。0 = 不改（工程默认约定）。
const YAWS := [0.0, 90.0, 180.0, 270.0]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var suit_id := SuitProfile.Id.MESSER_M01
	if args.size() > 1:
		suit_id = int(args[1])
	# `--live`：**不改角度**，直接按代码里 `SuitProfile.model_yaw_deg` 的当前值出图。
	#
	# ⚠️ 这个模式是必要的：默认模式会**临时改** `model_yaw_deg` 去出四格对照，
	# 所以它**永远显示四个候选**、看不出"代码里现在填的是哪个"。
	# 改完代码要复核就必须用 `--live`（本轮真踩过：拿默认模式去"复核"，
	# 看到第二格对就以为改对了 —— 而那个模式本来就会把第二格画成 90°）。
	var live := false
	for a in args:
		if a == "--live":
			live = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))
	await get_tree().physics_frame

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.64, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.85, 0.92)
	env.ambient_light_energy = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 128, 0)
	sun.light_energy = 1.8
	add_child(sun)

	var prof := SuitProfile.by_id(suit_id)
	# `--live`：只出一格，用**代码里的当前值**
	var angles: Array = [prof.model_yaw_deg] if live else YAWS
	var sheet := Image.create(W * angles.size(), H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.07, 0.08, 0.10))

	for i in angles.size():
		var ang: float = angles[i]
		if not live:
			prof.model_yaw_deg = ang
		var holder := Node3D.new()
		add_child(holder)
		var fb := FlightBody.new()
		fb.name = "Yaw%d" % int(ang)
		fb.team = 1
		fb.profile = prof
		holder.add_child(fb)
		fb.global_position = Vector3(0.0, 3000.0, 0.0)
		fb.set_physics_process(false)
		fb.global_transform = Transform3D(Basis(), Vector3(0.0, 3000.0, 0.0))
		await get_tree().physics_frame

		var cam := Camera3D.new()
		cam.fov = 34.0
		cam.near = 0.05
		cam.far = 6000.0
		add_child(cam)
		cam.current = true
		var focus: Vector3 = fb.global_position
		var r := maxf(fb.model_bounds.size.length() * 1.1, 1.0)
		# **俯视 + 一点点前倾**：正上方拍不到机体厚度，稍微偏一点能看出机头指向
		cam.global_position = focus + Vector3(0.0, r * 1.55, r * 0.55)
		cam.look_at(focus, Vector3.UP)
		for f in 4:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.convert(Image.FORMAT_RGBA8)
			# ⚠️ **必须缩放到格子大小再贴**：`DisplayServer.window_set_size()`
			# 在 Windows 上会被系统 DPI 缩放顶掉（实测设 460×620 实际拿到 2560×1600）。
			# 直接 `blit_rect` 贴的是"视口图的左上角"，而模型在画面**中心** ——
			# 于是四格全空、只有自定义标签画上去了（本轮真踩过）。
			img.resize(W, H, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(W, H)),
				Vector2i(W * i, 0))
			# 在每格左上角写角度
			_draw_label(sheet, W * i + 12, 26, "yaw = %d" % int(ang))
		cam.queue_free()
		holder.queue_free()
		await get_tree().physics_frame

	var out := out_dir.path_join("%s_yaw_choices.png" % prof.model_name.get_slice(" ", 0))
	print("SHOT %s err=%d" % [out, sheet.save_png(out)])
	print("  （四格从左到右：yaw = 0 / 90 / 180 / 270。**机头朝上那格是对的** ——")
	print("    本工具相机在机体后方偏上，所以「机头朝画面外侧 = 背离镜头 = 正确朝向」。）")
	print("YAW_CHOICES_DONE -> ", out_dir)
	get_tree().quit(0)


## 用一个极简的 5x7 点阵写字（不引字体资源，保持工具自包含）。
func _draw_label(img: Image, x: int, y: int, text: String) -> void:
	var glyphs := {
		"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
		"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
		"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
		"3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
		"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
		"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
		"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
		"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
		"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
		"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
		"=": ["00000", "00000", "11111", "00000", "11111", "00000", "00000"],
		"y": ["10001", "10001", "10001", "01111", "00001", "00010", "01100"],
		"a": ["00000", "00000", "01110", "00001", "01111", "10001", "01111"],
		"w": ["00000", "00000", "10001", "10001", "10101", "10101", "01010"],
		" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	}
	var cx := x
	for ch in text:
		var rows: Array = glyphs.get(ch, glyphs[" "])
		for ry in rows.size():
			var row: String = rows[ry]
			for rx in row.length():
				if row[rx] == "1":
					img.set_pixel(cx + rx, y + ry, Color(1.0, 0.85, 0.35))
		cx += 6
