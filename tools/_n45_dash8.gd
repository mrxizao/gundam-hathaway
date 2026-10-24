extends Node3D
## N45：**八向冲刺（`dash_*`）验收** —— 8 段各出一帧 + 两两差异矩阵。
##
## ## 为什么用户看不到八向
##
## 工程里左右冲刺会叠一层「机身水平转一圈」的视觉转身（`spin_pivot` · 轮 33）。
## 它把 `dash_l` / `dash_r` 的**动作本身**盖住了 ⇒ 验收时分不清八向到底做没做。
## 用户 2026-09-28 要求取消（`SuitProfile.dash_spin_visual = false`）。
## 本探针是**独立**于那个开关的第二条证据：直接读**动作数据**，与转身无关。
##
## ## 两个判据
##
##   ① 量化：8 段 × 8 段 的「最大单骨夹角」矩阵 —— 任意两段必须**可分辨**；
##   ② 出图：3×3 拼图（八向绕一圈，中心放 `fly` 基准）+ 8 张单图。
##
## 跑法（不能加 `--headless`）：
##   godot --path <工程> res://tools/_n45_dash8.tscn -- <输出目录>

const BG := Color(0.10, 0.12, 0.15)
const FOCUS := Vector3(0.0, 0.5, 0.0)
const RADIUS := 0.75
const CELL_W := 640
const CELL_H := 360

## 3×3 布局里的八向（中心那格放基准 `fly`）
const GRID := [
	["bl", "b", "br"],
	["l", "", "r"],
	["fl", "f", "fr"],
]
const REF := "fly"

var _cam: Camera3D
var out_dir := "user://n45_dash8"


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
	# ★ 这条判据必须与「转身开关」无关 ⇒ 顺带把当下取值打出来存档。
	print("★ dash_spin_visual = %s（佩涅罗佩应为 false）" % str(prof.dash_spin_visual))

	var ps := load(prof.model_path) as PackedScene
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	var ma := ModelAnimator.setup(inst, prof.model_anim_files)
	ma.idle_action = prof.model_anim_idle
	ma.prepare_loops()

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.near = 0.02
	_cam.far = 200.0
	_cam.current = true
	add_child(_cam)
	_place()

	var ap: AnimationPlayer = ma.player
	print("=== 动作表 %d 个 ===" % ma.action_names().size())

	# ---- ① 量化：末帧与中帧的骨骼旋转，与基准比 ----
	var names := ["b", "bl", "br", "f", "fl", "fr", "l", "r"]
	var mid := {}
	var end := {}
	var refl := {}
	for n in names:
		var an := "dash_" + str(n)
		if not ma.has(an):
			print("  !! 缺动作 %s" % an)
			continue
		var a := ap.get_animation(an)
		var dur := a.length
		mid[an] = _pose_at(ma, an, dur * 0.5)
		end[an] = _pose_at(ma, an, -1.0)
		print("  %-12s length=%.3f s  轨道=%d  关键帧=%d" % [
				an, dur, a.get_track_count(), _key_count(a)])
	if ma.has(REF):
		refl = _pose_at(ma, REF, -1.0)

	print("")
	print("=== 判据① 两两最大单骨夹角（度）· 中帧（进度 0.5）===")
	print("   ⚠️ 不能看末帧：`dash_*` 都是「从 fly 出发再回到 fly」的循环动作 ⇒ 末帧全部 = 基准。")
	var keys := []
	for n in names:
		if mid.has("dash_" + str(n)):
			keys.append("dash_" + str(n))
	_print_matrix(keys, mid)

	print("")
	print("=== 判据①b 与基准 %s 的最大夹角（度）===" % REF)
	for k in keys:
		print("  %-12s vs %s : 中帧 %.3f°   末帧 %.3f°" % [
				k, REF, _max_diff(mid[k], refl), _max_diff(end[k], refl)])

	# ---- ② 出图：逐段截图 + 3×3 拼图 ----
	var shots := {}
	var big := Image.create(CELL_W * 3, CELL_H * 3, false, Image.FORMAT_RGBA8)
	big.fill(BG)
	for row in 3:
		for col in 3:
			var nm: String = str(GRID[row][col])
			var an := REF if nm == "" else "dash_" + nm
			if not ma.has(an):
				continue
			ap.play(an)
			ap.seek(ap.get_animation(an).length * 0.5, true)
			await _frames(3)
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if img == null:
				continue
			# ★ 坑：viewport 出来的 Image 格式不一定是 RGBA8 ⇒ 直接 blit_rect 会报
			#   `Condition "format != p_src->format" is true.`（图还是出得来，但拼图缺格）。
			img.convert(Image.FORMAT_RGBA8)
			img.save_png(out_dir.path_join("%s.png" % an))
			shots[an] = img.duplicate()
			img.resize(CELL_W, CELL_H, Image.INTERPOLATE_LANCZOS)
			big.blit_rect(img, Rect2i(0, 0, CELL_W, CELL_H),
					Vector2i(col * CELL_W, row * CELL_H))
	big.save_png(out_dir.path_join("dash8_grid.png"))
	print("")
	print("    saved dash8_grid.png + 8 张单图")

	# ---- ③ ★ 屏幕像素差：用户的原话是「完全看不出」⇒ 这是最贴近那句话的判据 ----
	#
	# 同机位、同光照、同背景 ⇒ 两帧之间**所有**像素变化都只能来自姿态。
	# 角度差（10°）是人看不懂的抽象量；"屏幕上 3% 的像素变了"才是用户能对照的读数。
	#
	# ⚠️ 用 `get_data()` 逐字节比，**不用 `get_pixel()`** —— 92 万像素 × 8 段 ×
	#   逐点函数调用在 GDScript 里要几分钟（实测 `get_pixel` 版跑不完）。
	print("")
	print("=== 判据② 屏幕像素差（vs 基准 %s，同机位同光照）===" % REF)
	if not shots.has(REF):
		print("  !! 基准图 `%s` 没截到" % REF)
	else:
		var refimg: Image = shots[REF]
		var w := refimg.get_width()
		var h := refimg.get_height()
		var total := w * h
		var rd: PackedByteArray = refimg.get_data()
		print("  基准图 %d×%d = %d 像素 ｜ 阈值：任一 RGB 通道差 > 8/255 记为该像素「变了」"
			% [w, h, total])
		print("  %-12s %10s %9s   %s" % ["动作", "变化像素", "占比", "变化区域 (x0..x1, y0..y1)"])
		for n in names:
			var an := "dash_" + str(n)
			if not shots.has(an):
				continue
			var d: PackedByteArray = (shots[an] as Image).get_data()
			var changed := 0
			var minx := 1 << 30
			var miny := 1 << 30
			var maxx := -1
			var maxy := -1
			for i in range(0, d.size(), 4):
				if absi(d[i] - rd[i]) > 8 or absi(d[i + 1] - rd[i + 1]) > 8 \
					or absi(d[i + 2] - rd[i + 2]) > 8:
					changed += 1
					var p := i / 4
					var px := p % w
					var py := p / w
					minx = mini(minx, px)
					maxx = maxi(maxx, px)
					miny = mini(miny, py)
					maxy = maxi(maxy, py)
			print("  %-12s %10d %8.3f%%   x[%d..%d] y[%d..%d]"
				% [an, changed, 100.0 * float(changed) / float(total),
				   minx, maxx, miny, maxy])
		print("  ⚠️ 判读：占比 < 1% ⇒ 一屏 100 个像素里看不到 1 个在动，**肉眼不可辨**；")
		print("     1%~5% ⇒ 盯得住才看得出；> 5% ⇒ 一眼可见。")

		# ---- ③ 差异热力图：把「变了」的像素涂红、其余压暗 ----
		#
		# 百分比回答了"动没动"，热力图回答"**哪里**在动" —— 后者才是人眼判"看不看得出"的依据：
		# 差异若全落在翼尖/脚尖几个孤立区域，百分比再高也读不成"一个动作"。
		print("")
		print("=== 判据③ 差异热力图（红 = 姿态变化处，同机位同光照）===")
		var NW := 640
		var NH := int(float(h) * float(NW) / float(w))
		var heat := Image.create(NW * 4, NH * 2, false, Image.FORMAT_RGBA8)
		heat.fill(Color(0.04, 0.04, 0.05))
		var idx := 0
		for n in names:
			var an2 := "dash_" + str(n)
			if not shots.has(an2):
				continue
			var d2: PackedByteArray = (shots[an2] as Image).get_data()
			var out := PackedByteArray()
			out.resize(d2.size())
			for i in range(0, d2.size(), 4):
				if absi(d2[i] - rd[i]) > 8 or absi(d2[i + 1] - rd[i + 1]) > 8 \
					or absi(d2[i + 2] - rd[i + 2]) > 8:
					out[i] = 255
					out[i + 1] = 45
					out[i + 2] = 45
					out[i + 3] = 255
				else:
					out[i] = rd[i] / 4
					out[i + 1] = rd[i + 1] / 4
					out[i + 2] = rd[i + 2] / 4
					out[i + 3] = 255
			var himg := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)
			himg.resize(NW, NH, Image.INTERPOLATE_LANCZOS)
			heat.blit_rect(himg, Rect2i(0, 0, NW, NH),
					Vector2i((idx % 4) * NW, (idx / 4) * NH))
			idx += 1
		heat.save_png(out_dir.path_join("dash8_heat.png"))
		print("    saved dash8_heat.png  （2×4，按 `names` 序：")
		print("      上排 b / bl / br / f      下排 fl / fr / l / r）")

	print("VERDICT: N45-DASH8-DONE  → %s" % out_dir)
	get_tree().quit(0)


func _pose_at(ma: ModelAnimator, action: String, t: float) -> Dictionary:
	return ma.rotations_at(action, t)


## 两个姿态字典里同名骨的最大四元数夹角（度）。★ 取角必须**双覆盖归一** `2·acos(|w|)`。
func _max_diff(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for k in a:
		if not b.has(k):
			continue
		var q1: Quaternion = a[k]
		var q2: Quaternion = b[k]
		var d: float = absf(q1.dot(q2))
		d = clampf(d, 0.0, 1.0)
		var ang := rad_to_deg(2.0 * acos(d))
		if ang > worst:
			worst = ang
	return worst


func _print_matrix(keys: Array, poses: Dictionary) -> void:
	var hdr := "             "
	for b in keys:
		hdr += "%11s" % str(b).replace("dash_", "")
	print(hdr)
	for a in keys:
		var row := "%11s" % str(a).replace("dash_", "")
		for b in keys:
			row += "%11.2f" % _max_diff(poses[a], poses[b])
		print(row)


func _key_count(a: Animation) -> int:
	var n := 0
	for tr in a.get_track_count():
		n = maxi(n, a.track_get_key_count(tr))
	return n


func _place() -> void:
	# 正面偏侧一点，能同时看清前后左右的姿态差
	var az := deg_to_rad(200.0)
	var el := deg_to_rad(10.0)
	var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	_cam.global_position = FOCUS + dir * RADIUS * 2.8
	_cam.look_at(FOCUS, Vector3.UP)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
