extends Node
## 2026-09-26（棒 12）：**真实生产路径**下的机体朝向取证。
##
## ## 为什么再写一个（已有的不够用）
##   · `tools/yaw_choices.gd` —— 只出**俯视**四格。而工程自己的技能文档里写着
##     「分辨正反必须靠正/背视，别只看顶视下结论」（机甲肩板/背包会盖住头部，
##     头尾轮廓几乎一样）；我本轮实测也**确实没能从顶视图上判出机头**。
##   · `tools/model_shots.gd` —— 只渲染**原始 glb**，**不经过 `model_yaw_deg`**。
##     它回答的是"这份文件本身朝哪边"，回答不了"改完 yaw 之后玩家看到的是哪一面"。
##   · `tools/plume_nozzle_shot.gd` —— 走真 FlightBody，但只有**后视**一个机位。
##
## 本工具补的正是这一段：**实例化真的 `FlightBody`（带 profile、带 `ModelYaw` 枢轴）**，
## 再从**眼睛高度、正对**的四个机位拍。一眼能判：是哪一格出现了"脸"。
##
## ## 出图布局（4 格一排）
##   1 = yaw **0**   · 正面相机（−Z 侧）
##   2 = yaw **180** · 正面相机（−Z 侧）
##   3 = yaw **0**   · 背面相机（+Z 侧）
##   4 = yaw **180** · 背面相机（+Z 侧）
##
## 读法（**自洽判据，不用我解释**）：
##   **恰好有一格"正面相机"拍到脸**（= 朝向对的那个 yaw），
##   **且恰好有一格"背面相机"拍到脸**（= 朝向反的那个 yaw）。
##   两者必须是**同一个 yaw** 的两个不同机位 —— 对不上就说明相机标定错了，
##   此时整张图作废（不要"挑一个看起来对的"）。
##
## ## 相机命名（⚠️ 踩过的坑，写在 `model_shots.gd` 里）
## 视角是拿**相机位置**命名的，不是"绕模型转的角度"：
## 机体正面朝 −Z ⇒ "正面视图"的相机站在 **−Z 侧**。
## 第一版把 0° 标成 front，四台机全被看成了背面。
##
## ## 跑法（**不能加 --headless**，dummy 渲染器抓出来是空的）
##   godot --path <工程> res://tools/suit_orient_shot.tscn -- <输出目录> [<机体id>]
##
## 机体 id 见 `SuitProfile.Id`（柯西 = 0）。

const W := 460
const H := 620
## 俯角：**略高于水平**。纯水平会看不出机体厚度，俯角太大又会让"脸"变形。
const ELEV_DEG := 15.0
## 待选 yaw（本工具只比 0 与 180 —— 要四选一请用 `yaw_choices`）。
const YAWS := [0.0, 180.0]

var out_dir := "user://suit_orient"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var suit_id := SuitProfile.Id.XI
	if args.size() > 1:
		suit_id = int(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	_build_env()
	await get_tree().physics_frame

	var prof := SuitProfile.by_id(suit_id)
	# 四格：**按"机位"分组**（先两张正面、再两张背面），这样读图时是先横着比
	# "哪个 yaw 的正面相机拍到了脸"。
	#
	# ⚠️ 一格一格填、**不要同时摆两台机**：本工具只摆一台在 (0,3000,0)，
	# 同时摆两台会互相入镜（两台的机位完全一样）。
	var cells: Array = [null, null, null, null]
	for yi in YAWS.size():
		var ang: float = YAWS[yi]
		# ⚠️ `by_id()` 每次新建一份 profile，改它不会写回代码 —— 只用来出对照图。
		var p := SuitProfile.by_id(suit_id)
		p.model_yaw_deg = ang
		var fb := await _mount(p)
		cells[0 * YAWS.size() + yi] = await _shoot(fb, "front")
		cells[1 * YAWS.size() + yi] = await _shoot(fb, "back")
		fb.get_parent().queue_free()
		await get_tree().physics_frame

	var got := 0
	for c in cells:
		if c != null:
			got += 1
	if got == 0:
		push_error("一张都没拍到")
		get_tree().quit(1)
		return

	var sheet := Image.create(W * cells.size(), H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.07, 0.08, 0.10))
	for i in cells.size():
		var ci := cells[i] as Image
		if ci == null:
			continue
		sheet.blit_rect(ci, Rect2i(Vector2i.ZERO, Vector2i(W, H)), Vector2i(W * i, 0))
		# 只画序号（点阵字体只有数字，省得为了几个字母把字库摊大）。
		_draw_label(sheet, W * i + 12, 24, "%d" % (i + 1))

	var out := out_dir.path_join("%s_orient_cmp.png" % prof.model_name.get_slice(" ", 0))
	print("SHOT %s err=%d" % [out, sheet.save_png(out)])
	print("  格 1 = yaw 0   · 正面相机（−Z 侧）")
	print("  格 2 = yaw 180 · 正面相机（−Z 侧）")
	print("  格 3 = yaw 0   · 背面相机（+Z 侧）")
	print("  格 4 = yaw 180 · 背面相机（+Z 侧）")
	print("  读法：正面相机拍到脸的那个 yaw = 朝向对的那个；")
	print("        它必须与「背面相机拍到脸的那个 yaw」**互补**，否则相机标定错了。")
	print("  代码里现在填的是：%.1f°" % prof.model_yaw_deg)
	print("ORIENT_SHOT_DONE -> ", out_dir)
	get_tree().quit(0)


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.63, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.84, 0.87, 0.94)
	env.ambient_light_energy = 1.20
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# 主光从**斜前方上方**打：脸（−Z 侧）受光，判读更容易。
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 200.0, 0.0)
	key.light_energy = 1.8
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, 20.0, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.74, 0.84, 1.0)
	add_child(fill)


## 摆一台**真的** FlightBody（走 `_build_visual()`，因此 `ModelYaw` 枢轴真的生效）。
##
## ⚠️ 两个必踩的坑：
##   · 机体不能摆在 y=0 —— `CRASH_ALTITUDE` 会在第一个物理帧判"撞海"并 `destroy()`，
##     拍到的是爆炸花瓣（`plume_nozzle_shot.gd` 有完整现场）。
##   · `set_physics_process(false)` 要在 `add_child` **之后**立刻设，
##     否则第一个物理帧已经跑过了。
func _mount(p: SuitProfile) -> FlightBody:
	var holder := Node3D.new()
	add_child(holder)
	var fb := FlightBody.new()
	fb.team = 0
	fb.profile = p
	holder.add_child(fb)
	fb.global_position = Vector3(0.0, 3000.0, 0.0)
	fb.global_transform = Transform3D(Basis(), Vector3(0.0, 3000.0, 0.0))
	fb.set_physics_process(false)
	# 让 `_build_visual()` / `_center_and_measure()` 都跑完。
	for i in 3:
		await get_tree().physics_frame
	return fb


## 从 `dir_name` 那一侧拍一张。
func _shoot(fb: FlightBody, dir_name: String) -> Image:
	# ⚠️ 取景有两个坑（第一版都踩了，机体在画面上只占一小块、几乎判不出来）：
	#   ① **不能用包围盒对角线当取景尺寸** —— `size.length()` 是三维对角线，
	#      用它做正交高度会把机体缩到 1/2 以下。正交 `Camera3D.size` 在
	#      `keep_aspect = KEEP_HEIGHT`（默认）下就是**画面高度**，应该拿全高去算。
	#   ② **不能拿 `fb.global_position` 当焦点** —— `model_bounds` 的 y 原点在
	#      全高的 **55%** 处（`_center_and_measure()` 的规则），所以机体中心比
	#      节点原点**低** `0.05 × 全高`。焦点偏了会上下都留白。
	var bounds: AABB = fb.model_bounds
	var focus: Vector3 = fb.global_position + Vector3(0.0, bounds.position.y + bounds.size.y * 0.5, 0.0)
	var r := maxf(bounds.size.y, 1.0)
	# 机位方向（**世界系**，机体此时是单位朝向）：正面 = −Z，背面 = +Z。
	var az := 0.0
	if dir_name == "front":
		az = 180.0
	elif dir_name == "back":
		az = 0.0
	elif dir_name == "right":
		az = 90.0
	else:
		az = 270.0
	var el := deg_to_rad(ELEV_DEG)
	var d := r * 2.0
	var off := Vector3(sin(deg_to_rad(az)) * cos(el), sin(el), cos(deg_to_rad(az)) * cos(el)) * d

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = r * 1.06
	cam.near = 0.05
	cam.far = 6000.0
	add_child(cam)
	# ⚠️ `global_position` 必须在 `add_child` **之后**设（`yaw_choices.gd` 踩过：
	# 先设位置再挂树，相机停在原点，拍到的位置全错）。
	cam.global_position = focus + off
	cam.transform = cam.transform.looking_at(focus, Vector3.UP)
	cam.current = true
	for f in 4:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	cam.queue_free()
	await get_tree().physics_frame
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	# ⚠️ **必须缩放再贴**：`window_set_size()` 在 Windows 上会被系统 DPI 顶掉，
	# 直接 `blit_rect` 贴的是"视口图左上角"，而模型在画面中心 ⇒ 四格全空
	#（`yaw_choices.gd` 的注释里有完整现场）。
	img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	return img


## 极简 5x7 点阵（只做数字，保持工具自包含、不引字体资源）。
func _draw_label(img: Image, x: int, y: int, text: String) -> void:
	var glyphs := {
		"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
		"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
		"3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
		"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	}
	var cx := x
	for ch in text:
		var rows: Array = glyphs.get(ch, glyphs["1"])
		for ry in rows.size():
			var row: String = rows[ry]
			for rx in row.length():
				if row[rx] == "1":
					img.set_pixel(cx + rx, y + ry, Color(1.0, 0.85, 0.35))
		cx += 6
