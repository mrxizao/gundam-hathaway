extends Node3D
## 2026-09-25 交付用：三台机体**真尾焰**的落点与颜色取证。
##
## ## 要回答的三件事
##   ① 尾焰**从哪出来** —— 是不是落在 `engine_plumes` 那张表上的喷口？
##   ② 三台机的颜色**真的不一样**吗（黄 / 紫 / 蓝）？
##   ③ 游戏里（后上方视角）看起来对不对？
##
## ## 为什么要有"关掉尾焰"的那一张
## 位置判据不能用"看图觉得挺像" —— 必须有一个**同一瞬间的对照**：
## 同一个机体、同一机位，只把尾焰节点关掉再抓一张，两张**逐像素相减**，
## 得到的差值图就是"尾焰到底占了屏幕哪一块"。于是
## 「尾焰质心 ↔ 喷口标记」的距离是可以**量出来**的（`_r16_plume.py`）。
##
## ⚠️ 这一条是本轮之前踩过的坑的延续（`tools/plume_speed.gd` 文件头）：
## **切换显隐之后要静置几个渲染帧再抓**，抓图有 1~2 帧滞后；
## 而且 `GPUParticles3D` 是按渲染帧推进的，两张图之间**粒子相位本来就不同** ——
## 所以判据只用**形状/质心**这类稳的量，不用绝对像素数。
##
## ## ⚠️ 第二版修掉的坑：机体不能摆在 y=0
## 第一版把机体放在原点，结果 `FlightBody.CRASH_ALTITUDE`（24 m）在
## **第一个物理帧**就判"撞海"并 `destroy()`：模型被拆走、原地炸开一团爆炸特效，
## 抓到的三张图全是**满屏黄花瓣**，而且"关尾焰"那张一模一样 ⇒ 差分为零。
## 日志里的现场是 `[destroy] xi: 撞海`（见 `_shoot()` 里那段长注释）。
## 现在机体 `set_physics_process(false)`：位置冻住、不做撞击判定，
## 渲染帧照常推进，`_tick_effects()` 由 `_settle()` 手工调。
##
## ## ⚠️ 第三版修掉的坑：两套"像素坐标"
## 工程设了拉伸 ⇒ `get_viewport().get_visible_rect()` 是 **1600×1600**（内容坐标），
## 而落盘的 PNG 是 **720×720**（窗口尺寸）。`unproject_position()` 走的是前者，
## 直接拿来标后者，喷口标记会整体缩放错位 2.222 倍 —— 而且**看起来仍像"标记在机身上"**，
## 因为它还是等比落在画面中间那一带。`screen_*.txt` 里的坐标已按
## `落盘宽 / 内容宽` 换算，并把比例写进文件头供回验。
##
## ## 跑法（**不能加 --headless**，dummy 渲染器抓出来是空的）
##   godot --path <工程> res://tools/plume_nozzle_shot.tscn -- <输出目录>

## 想要的窗口尺寸。⚠️ **它只是"请求"** —— 这个工程的 `project.godot` 自带
## 拉伸设定，`window_set_size()` 会被接管，真实视口是 1600×1600（`shot_w/shot_h` 里记的是真值）。
## 留着这两个常量是因为分辨率够大是好事：喷口标记只有几个像素宽。
const SHOT_W := 720
const SHOT_H := 720
## 静置帧数：抓图滞后 + 让粒子把喷口周围铺满一个寿命周期（0.30 s ≈ 18 帧）。
const SETTLE := 26

var out_dir := "user://plume_nozzle"
var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else out_dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	_build_env()

	var suits := [
		["xi", SuitProfile.xi()],
		["penelope", SuitProfile.penelope()],
		["arizeus_cruise", SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)],
		# N63（2026-10-09）：常态 10 口（用户后视图圈点指定）的真机取证。
		["arizeus_normal", SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)],
	]
	for item: Array in suits:
		await _shoot(str(item[0]), item[1] as SuitProfile)
	print("### PLUME_NOZZLE_DONE -> %s" % out_dir)
	get_tree().quit(0)


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.065, 0.085)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.76, 0.88)
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 150, 0)
	key.light_energy = 1.7
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, -50, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.72, 0.82, 1.0)
	add_child(fill)


## 一台机体：建 → 推加力 → 三张图（关尾焰的后视 / 开尾焰的后视 / 开尾焰的透视）。
func _shoot(tag: String, prof: SuitProfile) -> void:
	var holder := Node3D.new()
	holder.name = "Holder_" + tag
	add_child(holder)

	var u := FlightBody.new()
	u.name = "Suit_" + tag
	u.team = 0
	u.is_player = true
	u.profile = prof
	u.display_name = tag
	u.use_placeholder = false
	# 让机头朝 −Z、**不俯冲**：正交后视才和 `nozzle_scan` 那套投影严格对应
	#（`nozzle_scan` 是在"未施加飞行前倾角"的模型空间里扫的）。
	u.set("flight_pitch_deg", 0.0)
	holder.add_child(u)
	u.global_position = Vector3.ZERO
	u.max_hp = 1000.0
	u.hp = 1000.0
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	# 推加力：`_tick_effects` 里 `fm.boosting` 管形状层、
	# `throttle` 管尾气（见 `flight_body.gd` 那一段）。
	u.fm.boosting = true
	u.fm.throttle = 1.0
	u.set("translate_mode", false)
	u.set("translate_dash", false)
	u.fm.super_boost = false

	# ⚠️⚠️ 这一段是本探针**第一版的唯一事故点**，注释必须留着。
	#
	# 第一版把机体摆在 y=0（"原点最省事"），而 `FlightBody.CRASH_ALTITUDE := 24.0`：
	# 第一个物理帧 `_check_ceiling()` 就 `destroy(null, "撞海")` ——
	# 模型被拆走、原地炸开一团爆炸特效。抓到的三张图**全是满屏黄花瓣**，
	# 而且**"关尾焰"那张一模一样** ⇒ 差分恒等于零，"位置判据"根本无从谈起。
	# 日志里那行 `[destroy] xi: 撞海` 就是现场。
	#
	# 这与 `main.gd` 里"玩家停在原点 → 一开局就死"是**同一个坑**，
	# 只是这次它发生在探针里 —— 所以两处都写了注释。
	#
	# 解法：关掉物理解算。位置冻在原点 ⇒ 不会撞海、也不会飞走（正交机位才站得住）；
	# 渲染帧照常推进（粒子是引擎自己按渲染帧走的）；
	# 而 `_tick_effects()` 由 `_settle()` 手工按 60 Hz 调 —— 尾焰该开的照开。
	u.set_physics_process(false)
	u.set_process(false)
	await _settle(u, 6)
	if u.model_pivot != null:
		u.model_pivot.rotation_degrees = Vector3.ZERO

	var b := u.model_bounds
	var center := b.get_center()
	var diag := b.size.length()
	var hs := maxf(b.size.x, b.size.y) * 0.62
	# 相机挂在根节点上，而 `center` 是**机体局部**坐标 ⇒ 必须叠加机体的世界位置。
	# 现在它是原点，但写成 `org + ...` 是为了"以后把机体抬高"时不会静默错位。
	var org := u.global_position
	# ⚠️ 这个数**不是**落盘图像的尺寸。工程设了拉伸 ⇒ 它恒为 1600×1600（内容坐标），
	# 而 PNG 是 720×720（窗口尺寸）。两套坐标都要，别混用（见下面 `kp`）。
	var vp := get_viewport().get_visible_rect().size

	# ---- 喷口清单（表里的分数 → 世界点），落盘给 Python 画标记 ----
	var world_pts: Array[Vector3] = []
	for p: Vector3 in prof.engine_plumes:
		world_pts.append(b.position + p * b.size)
	var f := FileAccess.open(out_dir.path_join("nozzles_%s.txt" % tag), FileAccess.WRITE)
	f.store_line("tag %s" % tag)
	f.store_line("origin %.6f %.6f %.6f" % [org.x, org.y, org.z])
	f.store_line("bounds_pos %.6f %.6f %.6f" % [b.position.x, b.position.y, b.position.z])
	f.store_line("bounds_size %.6f %.6f %.6f" % [b.size.x, b.size.y, b.size.z])
	f.store_line("center %.6f %.6f %.6f" % [center.x, center.y, center.z])
	f.store_line("hs %.6f" % hs)
	# 这两行记的是**内容坐标**，只作诊断用（`screen_*.txt` 里另记了落盘尺寸与比例）。
	f.store_line("view_content %d %d" % [int(vp.x), int(vp.y)])
	f.store_line("plume_color %.6f %.6f %.6f %.6f" % [
		prof.engine_plume_color.r, prof.engine_plume_color.g,
		prof.engine_plume_color.b, prof.engine_plume_color.a])
	f.store_line("plume_count %d" % prof.engine_plumes.size())
	var pi := 0
	for at: Vector3 in world_pts:
		var p := prof.engine_plumes[pi]
		f.store_line("nozzle %.6f %.6f %.6f -> world %.4f %.4f %.4f" % [
			p.x, p.y, p.z, at.x, at.y, at.z])
		pi += 1
	f.close()

	# ---- 正交后视（相机在 +Z，正对 −Z 的机背）----
	_cam = _make_cam()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = hs * 2.0
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.global_position = org + center + Vector3(0, 0, diag * 2.0)
	_cam.look_at(org + center, Vector3.UP)
	await get_tree().process_frame

	# (a) 关掉尾焰：对照基线
	_set_plumes(u, false)
	await _settle(u, SETTLE)
	var img_size: Vector2i = await _snap(out_dir.path_join("%s_a_off.png" % tag))

	# ---- 屏幕像素位置，**换算到落盘图像的那套坐标** ----
	#
	# `unproject_position()` 给的是**内容坐标**（1600×1600），而落盘的 PNG 是
	# **窗口尺寸**（720×720）—— 工程设了拉伸，两者差 2.222 倍。
	# 直接用前者去标后者，标记会整体跑到画外（这是本轮第二个"看着像回事、
	# 一量全错"的口径坑；第一个是 `view_*.txt` 排序）。
	# 所以这里按 `落盘宽 / 内容宽` 缩放，并把这个比例一并落盘，Python 侧可回验。
	var kp := float(img_size.x) / maxf(vp.x, 1.0)
	var s := FileAccess.open(out_dir.path_join("screen_%s.txt" % tag), FileAccess.WRITE)
	s.store_line("tag %s" % tag)
	s.store_line("view_content %.1f %.1f  img %d %d  scale %.6f" % [
		vp.x, vp.y, img_size.x, img_size.y, kp])
	s.store_line("cam_pos %.4f %.4f %.4f  ortho_size %.4f" % [
		_cam.global_position.x, _cam.global_position.y, _cam.global_position.z,
		_cam.size])
	for at: Vector3 in world_pts:
		var px := _cam.unproject_position(at) * kp
		s.store_line("screen %.3f %.3f" % [px.x, px.y])
	s.close()

	# (b) 开尾焰：同一机位
	_set_plumes(u, true)
	await _settle(u, SETTLE)
	await _snap(out_dir.path_join("%s_b_on.png" % tag))

	# ---- (c) 后上方透视（"游戏里大概长这样"）----
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 34.0
	var k := Vector3(0.0, 0.42, 1.0).normalized()
	_cam.global_position = org + center + k * (diag * 1.85)
	_cam.look_at(org + center, Vector3.UP)
	await _settle(u, 10)
	await _snap(out_dir.path_join("%s_c_persp.png" % tag))

	print("### SHOT %-16s 喷口 %2d 个  色=(%.2f, %.2f, %.2f) alpha=%.2f" % [
		tag, prof.engine_plumes.size(), prof.engine_plume_color.r,
		prof.engine_plume_color.g, prof.engine_plume_color.b, prof.engine_plume_color.a])
	_cam.queue_free()
	holder.queue_free()
	await get_tree().process_frame


func _make_cam() -> Camera3D:
	var c := Camera3D.new()
	c.near = 0.05
	c.far = 6000.0
	c.current = true
	add_child(c)
	return c


## 把机体身上所有尾焰相关的粒子系统**开/关**（形状层 + 密度层一起）。
##
## ⚠️ 只关 `emitting` 不够：`GPUParticles3D` 停止发射之后**已经在场的粒子还会活完剩下的寿命**
##（0.30 s ≈ 18 帧），于是"关掉"的那一张里仍然有火。`visible = false` 才是同一瞬间的干净基线。
func _set_plumes(u: FlightBody, on: bool) -> void:
	var n := 0
	var keys := ["_afterburner_fx", "_dash_fx", "_dash_rings", "_smoke_fx"]
	for k: String in keys:
		var node := u.get(k) as GPUParticles3D
		if node != null and is_instance_valid(node):
			node.visible = on
			if not on:
				node.emitting = false
			n += 1
	for item: Dictionary in (u.get("_plume_fx") as Array):
		for k2: String in ["fx", "glow", "boost", "ab", "dash"]:
			var node2 := item.get(k2) as Node3D
			if node2 != null and is_instance_valid(node2):
				node2.visible = on
				if not on and node2 is GPUParticles3D:
					(node2 as GPUParticles3D).emitting = false
				n += 1
	print("    （%s 尾焰节点 %d 个）" % ["开" if on else "关", n])


## 推进 `frames` 个**渲染帧**，同时按 60 Hz 手工调 `_tick_effects()`。
##
## ⚠️ 为什么要手工调：机体已经被 `set_physics_process(false)`，引擎不会再碰它，
## 而尾焰的 `emitting` / `amount_ratio` / `speed_scale` **全部**由 `_tick_effects()`
## 逐帧写入。不调它，粒子节点永远停在"建出来时那个默认态"（全在发射），
## 于是 `a_off` / `b_on` 两张会一样 —— 和"被爆炸盖住"是同一个症状。
func _settle(u: FlightBody, frames: int) -> void:
	for _i in frames:
		u.call("_tick_effects", 1.0 / 60.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## 抓图。返回**落盘图像**的像素尺寸 —— 它和 `get_viewport().get_visible_rect()`
## **不是一回事**：工程设了拉伸，内容坐标 1600×1600，而窗口 / 渲染目标是 720×720。
## 所有"世界 → 像素"的换算都必须用**落盘尺寸**，否则整体缩放错位 2.222 倍。
func _snap(path: String) -> Vector2i:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("抓图失败：%s" % path)
		return Vector2i.ZERO
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(path)
	return img.get_size()
