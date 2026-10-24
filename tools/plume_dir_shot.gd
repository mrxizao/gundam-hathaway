extends Node3D
## 2026-09-25 轮 18 交付用：佩涅罗佩两个喷口的**开口朝向**「改前 / 改后」真渲染对照。
##
## ## 为什么不能用轮 16 那个后视机位
##
## `tools/plume_nozzle_shot.tscn` 的判据机位是**正交后视**（相机在 +Z 正对机背）。
## 而这一轮改的恰好是"喷射方向从 +Z 变成朝下外方" —— 后视看过去，
## **两个候选朝向的位移都躺在视轴方向上**，投影到屏幕上长度恒为 0。
## 也就是说：那个机位**在原理上量不出这一轮改了什么**（两张图当然不同 ——
## 锥被转了个角度 —— 但"焰从口里往哪去"这一条读不出来）。
##
## ⇒ 判据机位必须是**与两个候选朝向都近乎垂直**的那个方向。
## 两个候选是 `+Z`（旧）与 `(±0.354, −0.866, +0.354)`（新），叉积 ≈ `(0.866, −0.354, 0)`
## ⇒ **正交侧视（相机在 −X）** 观测到的夹角最大。所以本探针两个机位都拍：
##   · `side`（−X 侧视）= **判据机位**：位移完全落在屏幕上；
##   · `back`（+Z 后视）= 轮 16 那个机位，留作**"为什么必须换机位"的对照**
##     （同一次改动、同一台机，在它上面量不到东西）。
##
## ## 「改前」怎么造（**不许改生产代码**）
##
## `SuitProfile.plume_dir()` 的边界是：`engine_plume_dirs` 与 `engine_plumes`
## **长度不一致 ⇒ 回零向量** ⇒ `_rebuild_plumes()` 兜到 `PLUME_AXIS`（+Z）。
## 所以把 `prof.engine_plume_dirs` 整个换成空表、再 `_rebuild_plumes()`，
## 得到的就是**轮 16 的行为**（两个口都朝 +Z），一行生产代码都不用动。
##
## ⚠️ 是**整个换一个数组**给这一台实例的字段，不是原地 `append` / `clear`：
## `PENELOPE_PLUME_DIRS` 是 const，被 `p.engine_plume_dirs = PENELOPE_PLUME_DIRS`
## **按引用**共享，原地改会污染常量表（第 ⑬ 节有一条断言专门盯着这件事）。
##
## ## 每张「开」都配一张「关」
##
## 判据是**同一机位、同一姿态**的逐像素差分：`_off`（尾焰节点 `visible=false`）
## 与 `_on` 相减，模型自身像素恒为 0，非零处只可能来自尾焰。
## 于是"焰到底往哪偏、偏了多少像素"是**量出来的**，不是看出来的。
##
## ## ⚠️ 三个已知坑（都沿用 `plume_nozzle_shot.gd` 的现场记录）
##   1. 机体**不能**摆在 y=0 又开着物理：第一个物理帧就被 `CRASH_ALTITUDE`（24 m）
##      判"撞海"、模型被拆走并原地炸开 —— 抓到的全是满屏花瓣，差分恒为 0。
##      这里 `set_physics_process(false)` 把位置冻住，并关掉撞击判定。
##   2. 只关 `emitting` 不够：已出生的粒子要活完一个寿命（0.30 s ≈ 18 帧）。
##      `visible = false` 才是同一瞬间的干净基线。
##   3. `unproject_position()` 给的是**内容坐标**（1600×1600），落盘的 PNG 是
##      **窗口尺寸**（720×720）—— 工程设了拉伸。`dir_marks.txt` 里的屏幕坐标
##      已按 `落盘宽 / 内容宽` 换算，比例也一并落盘供回验。
##
## ## 跑法（**不能加 `--headless`**，dummy 渲染器抓出来是空的）
##   godot --path <工程> res://tools/plume_dir_shot.tscn -- <输出目录>

const SHOT_W := 720
const SHOT_H := 720
## 静置帧数：抓图有 1~2 帧滞后，且要让粒子把喷口周围铺满一个寿命周期。
const SETTLE := 26

var out_dir := "user://plume_dir"
var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else out_dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	_build_env()
	await _shoot()
	print("### PLUME_DIR_DONE -> %s" % out_dir)
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


func _shoot() -> void:
	var holder := Node3D.new()
	holder.name = "Holder_penelope"
	add_child(holder)

	var prof := SuitProfile.penelope()
	var u := FlightBody.new()
	u.name = "Suit_penelope"
	u.team = 0
	u.is_player = true
	u.profile = prof
	u.display_name = "penelope"
	u.use_placeholder = false
	# 机头朝 −Z、不俯冲：与 `nozzle_scan` 那套投影同一个模型空间口径。
	u.set("flight_pitch_deg", 0.0)
	holder.add_child(u)
	u.global_position = Vector3.ZERO
	u.max_hp = 1000.0
	u.hp = 1000.0
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	# 推加力：形状层看 `fm.boosting`，尾气看 `fm.throttle`（见 `_tick_effects`）。
	u.fm.boosting = true
	u.fm.throttle = 1.0
	u.set("translate_mode", false)
	u.set("translate_dash", false)
	u.fm.super_boost = false

	# 关物理解算：位置冻在原点 ⇒ 不撞海、不飞走（正交机位才站得住）；
	# 渲染帧照常推进（粒子由引擎按渲染帧走），`_tick_effects()` 由 `_settle()` 手工调。
	u.set_physics_process(false)
	u.set_process(false)
	await _settle(u, 6)
	if u.model_pivot != null:
		u.model_pivot.rotation_degrees = Vector3.ZERO
	# ⚠️ 夜航灯（`_build_nav_lights()` 建的 `NavLight0..2`）是**频闪**的：
	# `_tick_effects()` 按相位开关 `_nav_strobe.visible`。它会在 `_off` / `_on`
	# 两张之间随机明灭 ⇒ 逐像素差分里多出几个与尾焰无关的亮斑，
	# 还会被"取最大簇"当成尾焰团。这里一次性关掉，**在源头上**去掉这个混淆项，
	# 而不是在分析脚本里靠阈值把它筛掉（那种筛法迟早会连真信号一起筛掉）。
	for ch: Node in u.get_children():
		if String(ch.name).begins_with("NavLight"):
			(ch as Node3D).visible = false
			print("    （关掉夜航灯 %s）" % ch.name)

	var b := u.model_bounds
	var center := b.get_center()
	var org := u.global_position
	var diag := b.size.length()
	# 表里的分数 → 机体局部世界点
	var nz: Array[Vector3] = []
	for p: Vector3 in prof.engine_plumes:
		nz.append(b.position + p * b.size)
	var noz_mid := Vector3.ZERO
	for at: Vector3 in nz:
		noz_mid += at
	noz_mid /= float(maxi(nz.size(), 1))

	# 视口要同时装得下两个喷口（它们沿 X 分开）与 ~5 m 的焰。
	var hs := maxf(maxf(b.size.x, b.size.z), b.size.y * 0.8) * 1.15

	var views := [
		{
			"tag": "side",
			"from": Vector3(-1, 0, 0),
			"aim": noz_mid,
			"note": "正交侧视(−X)：与两个候选朝向都近乎垂直 ⇒ 判据机位",
		},
		{
			"tag": "back",
			"from": Vector3(0, 0, 1),
			"aim": center,
			"note": "正交后视(+Z)：轮 16 用的机位，位移沿视轴 ⇒ 屏幕上为零",
		},
	]
	# ⚠️ 「改前」= 空朝向表 ⇒ `plume_dir()` 回零向量 ⇒ 兜到 `PLUME_AXIS`（+Z）。
	var none: Array[Vector3] = []
	var states := [
		{"tag": "old", "dirs": null, "note": "engine_plume_dirs 空表 ⇒ 两个口都朝 +Z（轮 16 行为）"},
		{"tag": "new", "dirs": SuitProfile.PENELOPE_PLUME_DIRS, "note": "engine_plume_dirs = 表值 ⇒ 朝下外方"},
	]

	var marks := FileAccess.open(out_dir.path_join("dir_marks.txt"), FileAccess.WRITE)
	marks.store_line("# 轮 18：喷口朝向改前/改后 —— 真渲染对照的机位与喷口标记")
	for v: Dictionary in views:
		var from: Vector3 = v["from"]
		if _cam != null and is_instance_valid(_cam):
			_cam.queue_free()
		_cam = _make_cam()
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = hs
		_cam.keep_aspect = Camera3D.KEEP_HEIGHT
		_cam.global_position = org + (v["aim"] as Vector3) + from.normalized() * (diag * 2.2)
		_cam.look_at(org + (v["aim"] as Vector3), Vector3.UP)
		await get_tree().process_frame
		var basis := _cam.global_transform.basis
		for st: Dictionary in states:
			if st["dirs"] == null:
				prof.engine_plume_dirs = none
			else:
				prof.engine_plume_dirs = st["dirs"]
			u.call("_rebuild_plumes")
			await _settle(u, 4)
			var pair := "%s_%s" % [v["tag"], st["tag"]]
			_set_plumes(u, false)
			await _settle(u, SETTLE)
			var sz: Vector2i = await _snap(out_dir.path_join("d_%s_off.png" % pair))
			_set_plumes(u, true)
			await _settle(u, SETTLE)
			await _snap(out_dir.path_join("d_%s_on.png" % pair))

			var vp := get_viewport().get_visible_rect().size
			var kp := float(sz.x) / maxf(vp.x, 1.0)
			marks.store_line("view %s state %s" % [v["tag"], st["tag"]])
			marks.store_line("  note_v %s" % v["note"])
			marks.store_line("  note_s %s" % st["note"])
			marks.store_line("  cam_pos %.5f %.5f %.5f ortho_size %.5f" % [
				_cam.global_position.x, _cam.global_position.y, _cam.global_position.z,
				_cam.size])
			marks.store_line("  cam_x_axis %.6f %.6f %.6f" % [basis.x.x, basis.x.y, basis.x.z])
			marks.store_line("  cam_y_axis %.6f %.6f %.6f" % [basis.y.x, basis.y.y, basis.y.z])
			marks.store_line("  cam_z_axis %.6f %.6f %.6f" % [basis.z.x, basis.z.y, basis.z.z])
			marks.store_line("  view_content %.1f %.1f  img %d %d  scale %.6f" % [
				vp.x, vp.y, sz.x, sz.y, kp])
			marks.store_line("  bounds_pos %.5f %.5f %.5f" % [
				b.position.x, b.position.y, b.position.z])
			marks.store_line("  bounds_size %.5f %.5f %.5f" % [b.size.x, b.size.y, b.size.z])
			var i := 0
			for at: Vector3 in nz:
				var px := _cam.unproject_position(at) * kp
				var d := Vector3(0, 0, 1)
				if st["dirs"] != null:
					d = SuitProfile.PENELOPE_PLUME_DIRS[i]
				marks.store_line("  nozzle %d world %.4f %.4f %.4f axis %.4f %.4f %.4f screen %.3f %.3f" % [
					i, at.x, at.y, at.z, d.x, d.y, d.z, px.x, px.y])
				i += 1
			print("### PAIR %-12s 机位=%s(%s) 喷口=%d ortho=%.1f" % [
				pair, v["tag"], from, nz.size(), hs])
	marks.close()
	holder.queue_free()
	await get_tree().process_frame


func _make_cam() -> Camera3D:
	var c := Camera3D.new()
	c.near = 0.05
	c.far = 6000.0
	c.current = true
	add_child(c)
	return c


## 把机体身上所有尾焰相关的粒子系统开/关（形状层 + 密度层 + 尾气一起）。
##
## ⚠️ 只关 `emitting` 不够：`GPUParticles3D` 停发之后**已经在场的粒子还会活完剩下的寿命**
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
	print("      （%s 尾焰节点 %d 个）" % ["开" if on else "关", n])


## 推进 `frames` 个**渲染帧**，同时按 60 Hz 手工调 `_tick_effects()`。
##
## ⚠️ 为什么手工调：机体已 `set_physics_process(false)`，引擎不会再碰它，而尾焰的
## `emitting` / `amount_ratio` / `speed_scale` **全部**由 `_tick_effects()` 逐帧写入。
## 不调它，粒子节点永远停在"建出来时那个默认态"，`_off` / `_on` 两张会一样。
func _settle(u: FlightBody, frames: int) -> void:
	for _i in frames:
		u.call("_tick_effects", 1.0 / 60.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## 抓图。返回**落盘图像**的像素尺寸 —— 它和 `get_viewport().get_visible_rect()`
## **不是一回事**：工程设了拉伸，内容坐标 1600×1600，窗口 / 渲染目标 720×720。
func _snap(path: String) -> Vector2i:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("抓图失败：%s" % path)
		return Vector2i.ZERO
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(path)
	return img.get_size()
