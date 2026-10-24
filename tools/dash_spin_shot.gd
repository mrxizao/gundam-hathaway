extends Node
## 轮 33：**左右冲刺的机身转身** —— 真机判据图（3 排 × 4 格）。
##
## ## 出图布局
##   排 1：**追尾机位**（玩家看到的那一面）· 向左转身 —— 0° / +90° / +180° / +270°
##   排 2：**俯视机位**（判机头朝向）      · 向左转身 —— 同上四个角
##   排 3：**追尾机位**                    · 向右转身 —— 0° / −90° / −180° / −270°
##
## ## 读法（自洽判据，不用我解释）
##   · **排 2 是"绕没绕竖直轴"的判决图**：四个格里机头应依次指向
##     **上 → 左 → 下 → 右**（水平面内扫一圈）。若机体在"翻跟头"（绕横轴）或
##     "桶滚"（绕自身长轴），俯视图里机头会原地不动、只有机身侧面在翻 —— 一眼可辨。
##   · 排 1 的第 1 格应是**背面**（追尾视角看到背包），第 3 格应是**正面**（看到脸）。
##   · 排 1 与排 3 的第 1 / 3 格必须**完全相同**（0° 与 180° 不分左右）；
##     第 2 / 4 格必须**互为镜像**（+90° 与 −90° 相反的转向）。
##
## ## 为什么摆角度而不是真跑一次冲刺
## 真跑冲刺同时发生两件事：机体以 ~3500 m/s 位移、机头被速度矢量拽着转（0.45 s
## 能转几十度）⇒ 各格的**机头朝向互不相同**，图会读成"每格在往不同方向飞"，
## 姿态根本没法逐格比对。
##
## 转身是**纯视觉姿态**，静止摆到同一个逻辑角与冲刺中那一瞬是同一个姿态 ——
## 走的是同一条链路（`dash_spin` → `_tick_effects()` → `spin_pivot.rotation.y`），
## 所以这样出图既真实又可比。
##
## ## 跑法（**不能加 --headless**：dummy 渲染器抓出来是空的）
##   godot --path <工程> res://tools/dash_spin_shot.tscn -- <输出目录>

const W := 380
const H := 480
## 追尾机位的仰角：略高于水平，能看出机体厚度又不至于把姿态压扁。
const TAIL_ELEV_DEG := 12.0
## 一圈的四个 90° 分位。
const ANGLES := [0.0, 90.0, 180.0, 270.0]
## 三排：[机位名, 转向符号]
##   "tail" = 追尾（+Z 侧）· "top" = 俯视（正上方，屏幕上方 = 世界前）
const ROWS := [["tail", 1.0], ["top", 1.0], ["tail", -1.0]]

var out_dir := "user://dash_spin"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	_build_env()
	await get_tree().physics_frame

	var prof := SuitProfile.xi()
	var fb := await _mount(prof)

	var cols := ANGLES.size()
	var rows := ROWS.size()
	var sheet := Image.create(W * cols, H * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.07, 0.08, 0.10))
	var got := 0
	for row in rows:
		var view: String = ROWS[row][0]
		var sign_v: float = ROWS[row][1]
		for ai in cols:
			var deg: float = ANGLES[ai] * sign_v
			# 逻辑角 → 视觉层：与冲刺窗口里那条链路**同一个入口**（同一个变量、同一个函数）。
			fb.dash_spin = deg_to_rad(deg)
			fb._tick_effects(0.0)
			var img := await _shoot(fb, view)
			var x := W * ai
			var y := H * row
			if img == null:
				continue
			got += 1
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(W, H)), Vector2i(x, y))
			_draw_text(sheet, x + 14, y + 14,
				("－" if deg < 0.0 else "") + str(int(absf(deg))))
	# 格线：逐格比姿态，有线才读得出"这一列是不是镜像"。
	for ai in range(1, cols):
		sheet.fill_rect(Rect2i(W * ai, 0, 2, H * rows), Color(0.42, 0.48, 0.58))
	for ri in range(1, rows):
		sheet.fill_rect(Rect2i(0, H * ri, W * cols, 2), Color(0.42, 0.48, 0.58))

	var out := out_dir.path_join("dash_spin_cmp.png")
	print("SHOT %s err=%d  拍到 %d 格" % [out, sheet.save_png(out), got])
	print("  排 1 = 追尾机位 · 向左转身   排 2 = 俯视机位 · 向左转身   排 3 = 追尾 · 向右转身")
	print("  读法：排 2 四格机头应依次指 上→左→下→右（在水平面里扫一圈）；")
	print("        排 1 与排 3 的第 1 / 3 格相同，第 2 / 4 格互为镜像。")
	print("DASH_SPIN_SHOT_DONE -> ", out_dir)
	get_tree().quit(0 if got > 0 else 1)


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
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 20.0, 0.0)
	key.light_energy = 1.8
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, 200.0, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.74, 0.84, 1.0)
	add_child(fill)


## 摆一台**真的** FlightBody（走 `_build_visual()` ⇒ `spin_pivot` 真的在链上）。
##
## ⚠️ 三个必踩的坑（前两个抄自 `suit_orient_shot.gd` 的现场记录）：
##   · 机体不能摆 y=0 —— `CRASH_ALTITUDE` 会在第一个物理帧判"撞海"并 `destroy()`；
##   · `set_physics_process(false)` 要在 `add_child` **之后**立刻设；
##   · `_hover_pose` 初值是 0，而 `_tick_effects(0.0)` 的 `move_toward(…, 0)` 不推进它
##     ⇒ 不显式补这一下，拍到的是"竖直站立"，与冲刺中真实看到的**前倾飞行姿态**不符。
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
	for i in 3:
		await get_tree().physics_frame
	fb._hover_pose = fb.flight_pitch_deg
	return fb


## 拍一张。`view` = "tail"（追尾，+Z 侧）或 "top"（正上方俯视）。
##
## ⚠️ 俯视机位的 up 必须换成 **−Z（世界前）**：用默认的 `Vector3.UP` 会与视线
## （朝正下方）**共线**，`looking_at()` 会当场拒绝，相机停在原点。换成 −Z 之后
## 屏幕上方 = 世界前 ⇒ 俯视图里"机头朝上"就是 0°，读图最省事。
func _shoot(fb: FlightBody, view: String) -> Image:
	var bounds: AABB = fb.model_bounds
	# 焦点 = 机体中心。`model_bounds` 的 y 原点在**全高 55%** 处
	#（`_center_and_measure()` 的规则），所以中心比节点原点低 0.05×全高。
	var focus: Vector3 = fb.global_position \
		+ Vector3(0.0, bounds.position.y + bounds.size.y * 0.5, 0.0)
	var r := maxf(bounds.size.y, 1.0)
	var d := r * 2.0
	var off: Vector3
	var cam_up := Vector3.UP
	if view == "top":
		off = Vector3(0.0, d, 0.0)
		cam_up = Vector3(0.0, 0.0, -1.0)
	else:
		var el := deg_to_rad(TAIL_ELEV_DEG)
		off = Vector3(0.0, sin(el), cos(el)) * d

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# ⚠️ 取景尺寸**各格共用**（按静止全高 ×1.20 定死）：若按每格自己的包围盒取景，
	# 缩放会跟着变 —— "看起来在转"与"看起来被放大了"就分不出来。
	cam.size = r * 1.20
	cam.near = 0.05
	cam.far = 6000.0
	add_child(cam)
	# ⚠️ `global_position` 必须在 `add_child` 之后设（先设位置再挂树，相机会停在原点）。
	cam.global_position = focus + off
	cam.transform = cam.transform.looking_at(focus, cam_up)
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
	# ⚠️ 必须缩放再贴：`window_set_size()` 在 Windows 上会被系统 DPI 顶掉。
	img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	return img


## 极简 5×7 点阵（数字 + 负号，工具自包含、不引字体资源）。
func _draw_text(img: Image, x: int, y: int, text: String) -> void:
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
		"－": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	}
	var cx := x
	for ch in text:
		var rows: Array = glyphs.get(ch, glyphs["0"])
		for ry in rows.size():
			var row: String = rows[ry]
			for rx in row.length():
				if row[rx] == "1":
					img.set_pixel(cx + rx, y + ry, Color(1.0, 0.85, 0.35))
		cx += 7
