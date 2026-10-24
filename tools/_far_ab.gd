extends Node
## **A/B 对照**：探针图"整个场景全黑、只有天空盒的星星"到底是哪个旋钮造成的。
##
## ## 症状（`_rocket_shots` 第一版）
## 九张图全部只有 `Environment` 的天空盒：太平洋那几张是"星空 + 下半纯黑"，
## 连 132 m 外的 58 m 火箭都看不见；⑥"云幕全遮"那张**整屏云幕也没有**。
## 天空盒能画 ⇒ 相机与 Environment 是好的；**几何一件都不画** ⇒ 没有光照。
## 同一份日志里刷着 `create_frustum_points (rendering_light_culler.cpp:682)`。
##
## ## 两个嫌疑（都要**真机读数**判，不许推理）
## | # | 变量 | 依据 |
## |---|---|---|
## | A | `Camera3D.far` = **4.0e7** | 工程自己的相机用地表图 `GROUND_FAR = 90 000`、轨道图 `ORBIT_FAR = 1.0e7`；探针写了 444 倍 |
## | B | `DirectionalLight3D.shadow_enabled` | `_build_sun()` 里是 `true` + `SHADOW_PARALLEL_4_SPLITS`；`create_frustum_points` 正是阴影锥 |
##
## ## 判据
## 每档都拍一张**发射点（火箭 + 海面 + 头顶云垛）**的图，
## 然后**读像素**：均值亮度 / 亮像素占比。
## 「全黑」= 均值 ~0、最亮也只有星点 ⇒ 与 ① 那张同病。
## ⚠️ 一律**关掉四个天气层**，否则雾会把海面糊成一片、读数没有分辨力。
##
## ⚠️ 2026-09-30：判据对象从"海上平台"换成"火箭 + 云垛"（平台被老板砍掉了）。
## 这个工具本身**留着** —— 它钉的是"`far` 过大会让整个场景几何全黑且不报错"
## 这条引擎行为，与判据对象是什么无关；将来换了相机的 `far` 还要靠它复验。
##
## 跑法（**不能 `--headless`**）：
##   godot --path <工程> res://tools/_far_ab.tscn -- <输出目录>

var out_dir := "user://far_ab"
var world: WorldBuilder
var cam: Camera3D
var rocket: RocketBody
var _idx := 0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	world = WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	world.apply_map(MapDef.pacific())
	await _frames(20)

	cam = Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.current = true
	add_child(cam)

	rocket = RocketBody.new()
	add_child(rocket)
	rocket.place_at_launch(LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))
	var ps := load("res://assets/models/mafty_rocket/mafty_rocket.glb") as PackedScene
	if ps == null:
		push_error("火箭资产载不到")
	else:
		rocket.set_model(ps.instantiate())
	await _frames(4)

	var base := LaunchScript.launch_pos()
	# 机位：从海面斜上方 1.2 km 外看发射点，**略微抬头** —— 一帧里要同时有
	# 海面、火箭（水下 34 m + 水上 24 m）、以及头顶那垛云（1500~5000 m）。
	# 平台砍掉之前这里用的是 420 m 正俯视；现在没有甲板可读了，抬头才读得出云。
	cam.global_position = base + Vector3(0.0, 300.0, 1200.0)
	cam.look_at(base + Vector3(0.0, 480.0, 0.0), Vector3.UP)

	print("== sun.shadow_enabled = %s / directional_shadow_mode = %d"
		% [str(world.sun.shadow_enabled), world.sun.directional_shadow_mode])

	# ---- A/B/C 三档 ----
	await _trial("A_far4e7_shadowON", 4.0e7, true)
	await _trial("B_far9e4_shadowON", ChaseCamera.GROUND_FAR, true)
	await _trial("C_far4e7_shadowOFF", 4.0e7, false)

	print("== 对照完成：%d 张 ⇒ %s" % [_idx, out_dir])
	get_tree().quit(0)


func _trial(tag: String, far: float, shadow: bool) -> void:
	cam.far = far
	world.sun.shadow_enabled = shadow
	await _frames(10)
	var img := await _shot(tag)
	if img == null:
		return
	var stats := _stats(img)
	print("== [%s] far = %.0f km / shadow = %s ⇒ 均值 %.1f / 亮像素 >40 占比 %.4f / 最亮 %d"
		% [tag, far / 1000.0, str(shadow), stats.mean, stats.lit, stats.maxv])


## 均值 / 亮像素占比 / 最亮值。**判"有没有几何"看 `lit`** ——
## 星点是自发光的峰值，但它们只覆盖极少数像素；平台+海面若被照亮，
## `lit`（>40 的像素占比）会从"万分之几"跳到"一大片"。
##
## ⚠️ 用 `get_data()` 逐字节扫，**不用 `get_pixel()`** ——
## GDScript 里 `get_pixel()` 是逐次跨引擎边界的调用，1600×900 要跑几十秒。
func _stats(img: Image) -> Dictionary:
	var im := img.duplicate() as Image
	im.convert(Image.FORMAT_RGB8)
	var d := im.get_data()
	var total := d.size() / 3
	var n := 0
	var sum := 0.0
	var lit := 0
	var maxv := 0
	var i := 0
	while i + 2 < d.size():
		var v := maxi(d[i], maxi(d[i + 1], d[i + 2]))
		n += 1
		sum += float(v)
		maxv = maxi(maxv, v)
		if v > 40:
			lit += 1
		i += 3
	return {"mean": sum / maxf(float(n), 1.0), "lit": float(lit) / maxf(float(total), 1.0), "maxv": maxv}


func _shot(tag: String) -> Image:
	_idx += 1
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	var p := out_dir.path_join("%s.png" % tag)
	img.save_png(p)
	print("SHOT %s" % p)
	return img


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _on_watchdog() -> void:
	print("WATCHDOG_TIMEOUT")
	get_tree().quit(3)
