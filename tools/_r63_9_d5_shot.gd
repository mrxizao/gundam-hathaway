extends Node3D
## ★63-9 · D5 真机出图：**烟带那一层的透明度 A/B**（判据 6）。
##
## ## 为什么出图
## 「白烟太挡视野了」是一个**观感**主张。参数断言（`suite_smoke_density`）能断
## `ALPHA == 0.44`，但"屏幕上那层白烟真的淡了"只有像素说了算。
##
## ## 为什么只拍**烟带**、不拍粒子层（这一点必须写明，不许含糊）
## 粒子层是**随机场**（`GPUParticles3D` 没有可钉的 seed）：同一份代码两次跑，
## 逐像素结果都不一样 ⇒ **做不出可复现的 A/B**。
## 烟带是**确定性几何**（同一批点 ⇒ 同一个 mesh），只差顶点色里的 alpha ⇒
## 两次跑的像素差**只可能来自 alpha**，这正是我们要证的那一件事。
## 粒子层的「密度 −20%」由**参数**证（`amount` 80→64 且 `lifetime` 同比例降，
## 见 `suite_smoke_density` 与 `nc_amount_only` 那颗牙齿），不假装有像素证据。
##
## ## 怎么跑（两遍，只差被改回旧值的源码）
##   ① 现值（ALPHA 0.44）  ⇒ 出 `d5_ribbon_alpha_0.44.png`
##   ② 拿 r63_9_d5 备份把 `missile_ribbon.gd`/`fx.gd` 还原成旧值（0.55）跑一遍
##                          ⇒ 出 `d5_ribbon_alpha_0.55.png`
##   ③ 还原成现值，用 Pillow 比两张图在同一窗口里的亮度
##
## ⚠️ 不要加 `--headless`：dummy 渲染器一个像素都不产生，抓出来全黑。
##
## 跑法：godot --path <工程> res://tools/_r63_9_d5_shot.tscn -- <输出目录>

var out := "user://r63_9_d5_shot"
var cam: Camera3D
var rb: MissileRibbon

## 采样点：14 个 × 120 m = 1560 m 长的一条直带（`SPACING` 就是 120）。
const N_PTS := 14
const STEP := 120.0
const X0 := -780.0
## 相机正对原点。⚠️ 「带子在画面上有多高」= `12 × 视口高 / (2·d·tan(fov/2))`，
## 与视口是 1600×900 还是真机 2560×1600 **无关的只有比例**：
##   fov 60 / d 170 ⇒ 约 98 px，但 d 比带子半长（780 m）小得多 ⇒ **斜视把远端压扁**，
##   画面上会出现「一条亮线 + 一片虚带」两截（第一版实测），不干净。
##   fov **15** / d **800** ⇒ 可见窗口 x ∈ ±168 m（斜视只有 12°），带子高约 91 px
##   ⇒ 一截干净的水平软带（顶点色沿长度 0.15→1.0，窗口落在中段 f≈0.61）。
## ⚠️ 真机窗口实际是 2560×1600（scale 1.6×），`window_set_size` 不生效 ⇒
## 不要按 1600×900 反算；两遍跑同尺寸即可（A/B 只需可比，不需绝对值）。
const CAM_Z := 800.0
const CAM_FOV := 15.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	# ---- 纯黑背景、无环境光：画面里除了这条烟带什么都没有（统计才有意义）----
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.0, 0.0, 0.0, 1.0)
	we.environment = env
	add_child(we)

	cam = Camera3D.new()
	cam.name = "Cam"
	cam.fov = CAM_FOV
	cam.position = Vector3(0.0, 0.0, CAM_Z)
	add_child(cam)
	cam.look_at(Vector3.ZERO)
	cam.make_current()

	rb = MissileRibbon.new()
	add_child(rb)
	for i in N_PTS:
		rb.push(Vector3(X0 + STEP * float(i), 0.0, 0.0), 1.0 / 60.0)
	rb.rebuild()

	# 诊断开关（第二参传 `noribbon`）：不放烟带 ⇒ 用来判定"画面里那条细亮线
	# 到底是不是烟带自己画的"。不是烟带画的就必须在交付里说明来源。
	if args.size() > 1 and str(args[1]) == "noribbon":
		rb.visible = false
		rb.set_process(false)
		print("[d5] DIAG noribbon：烟带已隐藏")

	await _frames(20)
	print("[d5] ALPHA=%.4f  segs=%d  pts=%d  covered=%.1f m  node=%s"
		% [MissileRibbon.ALPHA, rb.drawn_segments(), rb.point_count(),
			rb.covered_m(), rb.name])
	await _shot("d5_ribbon_alpha_%.2f" % MissileRibbon.ALPHA)
	print("R63_9_D5_SHOT_DONE -> %s" % out)
	get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport) ", name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(no image) ", name)
		return
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  %dx%d  err=%d"
		% [path, img.get_width(), img.get_height(), img.save_png(path)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
