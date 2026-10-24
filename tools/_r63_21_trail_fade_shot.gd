extends Node3D
## ★63-21 真机出图：**导弹尾迹的近距离淡出**，用**真实产品对象**取证。
##
## ## 需求原话（两段）
##   「离镜头越近，透明度就越高，离镜头只有 3 m 的时候透明度彻底 100%」
##   「是镜头内的**部分**透明哦，不是整条透明」
##
## ## 为什么必须真机
## 距离淡出是**渲染管线**行为：`--headless` 的 dummy 渲染器一个像素都不产生。
## 引擎语义（公式与"逐片元"）已由 `tools/_r63_21_fade_probe.tscn` 十距离序列坐实；
## **本探针证的是产品**：真 `MissileRibbon`（真材质、真 `rebuild()`）与真
## `FX._trail_smoke_mat()`，在真机的像素上确实按那条斜坡淡。
##
## ## A/B 不改源码
## `fade=off` 在**运行时**把材质的 `distance_fade_mode` 打回 `DISABLED`
## ⇒ 两趟跑的是同一份源码、同一个几何，**唯一的变量就是那一行开关**。
## （烟带材质是 static 缓存，进程内改一次即可；探针跑完就退出，不留痕。）
##
## ## 几何
## 一条 3 点真烟带：`(0,0,-2) → (0,0,-155) → (0,0,-308)`（间距 ≈ `SPACING`）。
## 相机在近端后方 `dist` 米、并**偏一点横向/竖向**（正对会把 `side` 逼进退化分支、
## 让带子躺平看不见）。于是：近端在画面里是一大片、远端收成一条细带。
##
##   · `dist ≤ 3`  ⇒ 近端整片应当**消失**，画面只剩远处那条细带 ⇒ 「部分透明」
##   · `dist ≥ 60` ⇒ 与 `fade=off` **逐位接近**（斜坡乘子恒为 1）
##
## 跑法：godot --path <工程> res://tools/_r63_21_trail_fade_shot.tscn -- <输出目录> <kind> <fade> <dist>
##   kind ∈ ribbon / sphere / trailsphere    fade ∈ on / off

var out := "user://r63_21_trail_fade"
var kind := "ribbon"
var fade := "on"
var dist := 3.0
## ⚠️ 粒子层那份材质是 **HDR 受光**的（`albedo_color (2.20,2.12,1.92)`）。
## 光一强，`fade=off` 那趟直接**打到 1.0 削顶** ⇒ 量出来的比值就被压缩了
## （实测：d=20 时比值 0.927，而那条斜坡的理论值只有 ~0.21）。
## 把光压低，让两趟都落在**未削顶**的线性区，比值才正比于 alpha。
var light_e := 1.0

const LAT := 1.2
const UP := 0.8
const NEAR_Z := -2.0
## 真烟带的三个采样点（z 依次向后 153 m ≈ `MissileRibbon.SPACING`）。
const PTS: Array[float] = [-2.0, -155.0, -308.0]
## 球体替身的半径要**小**：淡出斜坡是按**片元到相机的距离**算的，
## 半径一大，同一个球上就有两极相反的读数（近极淡、远极浓）⇒ 量不出"那一个距离"。
## 1.5 m ⇒ 最近几档相机不会钻进球里，且整球跨度 ≤ 3 m。
const SPHERE_R := 1.5

var cam: Camera3D
var rb: MissileRibbon
var mat: BaseMaterial3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = str(args[0])
	if args.size() > 1:
		kind = str(args[1])
	if args.size() > 2:
		fade = str(args[2])
	if args.size() > 3:
		dist = float(args[3])
	if args.size() > 4:
		light_e = float(args[4])
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	# ---- 环境：近黑 + 一点环境光 + 一盏平行光 ----
	# ⚠️ 尾迹粒子那份材质是**受光**的（`SHADING_MODE_PER_PIXEL`），纯黑环境会把它渲染成黑，
	# 亮度就不再正比于 alpha、量不出斜坡。所以必须给光。
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.10, 0.11, 1.0)
	env.ambient_light_energy = 1.0
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = light_e
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	add_child(sun)

	cam = Camera3D.new()
	cam.name = "Cam"
	cam.fov = 60.0
	# ⚠️ 相机必须**抬离带子所在的平面**：`rebuild()` 用
	# `side = dir.cross(to_cam)` 算带宽方向，在"相机落在带子轴线上"时会退化
	# ⇒ 退回 `dir.cross(UP)` ⇒ 带子躺平、被看成刀刃。
	# 第一版（横向 1.2 m / 抬高 0.8 m，d=90）实测只剩 **16/64000** 个亮点，就是撞在这上面。
	# 现在按距离抬 `0.40×dist`（仰角恒定 ≈ 24°），远近都能看到带子的"面"。
	cam.position = Vector3(0.3, dist * 0.40, NEAR_Z + dist * 0.90)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.0, -200.0))
	cam.make_current()

	if kind == "sphere" or kind == "trailsphere":
		# ⚠️ 球体是**确定性**替身（朝向无关、无随机场）：把**真材质**挂上去量那条斜坡。
		#    · `kind=sphere`      ⇒ `MissileRibbon._shared_mat()`（烟带层那份，unshaded）
		#    · `kind=trailsphere` ⇒ `FX._trail_smoke_mat()`（粒子层那份，**受光** ⇒ 需要光）
		# 真烟带的"部分透明"另由 kind=ribbon 在 d=3 直接拍（那里几何不退化）。
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = SPHERE_R
		sm.height = SPHERE_R * 2.0
		sm.radial_segments = 24
		sm.rings = 12
		mat = FX._trail_smoke_mat() if kind == "trailsphere" else MissileRibbon._shared_mat()
		sm.material = mat
		s.mesh = sm
		add_child(s)
		s.global_position = Vector3(0.0, 0.0, NEAR_Z)
	else:
		rb = MissileRibbon.new()
		add_child(rb)
		for z in PTS:
			rb.push(Vector3(0.0, 0.0, z), 1.0 / 60.0)
		rb.rebuild()
		mat = MissileRibbon._shared_mat()

	# ---- A/B：运行时把那一行开关打回 DISABLED（不改源码）----
	if fade == "off" and mat != null:
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
		print("[fade] A/B=BACK 已把 distance_fade_mode 打回 DISABLED")

	await _frames(30)
	var d_near := cam.global_position.distance_to(Vector3(0.0, 0.0, NEAR_Z))
	print("[fade] kind=%s fade=%s dist=%.2f  相机到近端=%.2f m  fov=%.0f  光=%.3f"
		% [kind, fade, dist, d_near, cam.fov, light_e])
	if rb != null:
		print("[fade] 烟带 pts=%d segs=%d covered=%.1f m  锚点 %.1f→%.1f"
			% [rb.point_count(), rb.drawn_segments(), rb.covered_m(),
				MissileRibbon.FADE_NEAR_M, MissileRibbon.FADE_FULL_M])
	if mat != null:
		print("[fade] 材质回读 mode=%d min=%.1f max=%.1f"
			% [mat.distance_fade_mode, mat.distance_fade_min_distance,
				mat.distance_fade_max_distance])
	var lsuf := "" if is_equal_approx(light_e, 1.0) else "_L%03d" % int(round(light_e * 1000.0))
	await _snap("%s_%s_d%03d%s" % [kind, fade, int(round(dist)), lsuf])
	print("R63_21_FADE_SHOT_DONE -> %s" % out)
	get_tree().quit(0)


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport) ", name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(no image) ", name)
		return
	# 探针**自己**先算一遍（每 8 px 抽一格）—— 与 Python 侧独立复算互为对照。
	var w := img.get_width()
	var h := img.get_height()
	var mx := 0.0
	var sum := 0.0
	var n := 0
	var lit := 0
	for y in range(0, h, 8):
		for x in range(0, w, 8):
			var v := img.get_pixel(x, y).r
			if v > mx:
				mx = v
			sum += v
			n += 1
			if v > 0.02:
				lit += 1
	print("STAT %s  %dx%d  mean=%.5f max=%.5f lit=%d/%d"
		% [name, w, h, sum / maxf(float(n), 1.0), mx, lit, n])
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  err=%d" % [path, img.save_png(path)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
