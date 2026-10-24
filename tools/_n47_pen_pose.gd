extends Node3D
## N47 根因探针：佩涅罗佩「一按八向冲刺，模型就整个乱七八糟」。
##
## ## 待证假设
##
## N46 给佩涅罗佩配了 `model_anim_idle = ""`（用户裁决：飞行待机违和），
## 并在 `ModelAnimFSM._enter_idle()` 里补了 `anim.reset_to_rest()`。
## 于是**冲刺窗口一结束**（约 0.45 s）就会走：
##
##     _enter_idle() → a == "" → reset_to_rest() → 全部骨 pose 归零
##
## **如果佩涅罗佩的 rest 姿态 ≠ `fly` 首帧姿态**，那归零 = 归到一个散架姿态，
## 而且**之后不会再被任何动作救回来**（没有待机动作可播）⇒ 永久乱。
##
## ⚠️ 本轮之前**从未**验证过「佩涅罗佩的 rest 长什么样」——
##   N46 的验收只钉在「状态机内部状态」（动作名 / 播放头），没出过图。
##
## ## 判据（一条量化 ＋ 一条目视）
##
##   ① 量化：`rest` vs `fly 首帧` 的最大单骨夹角 / 骨原点位移 / 网格包围盒；
##   ② 出图：2×3 拼图 —— 右下列那格就是「游戏里冲刺之后你看到的东西」。
##
## 跑法（**不能加 `--headless`**）：
##   godot --path <工程> res://tools/_n47_pen_pose.tscn -- <输出目录>

const BG := Color(0.10, 0.12, 0.15)
const FOCUS := Vector3(0.0, 0.5, 0.0)
const RADIUS := 0.75
const CELL_W := 640
const CELL_H := 360

## 2 行 × 3 列，上排 = 「该有的样子」，下排 = 「冲刺相关」
const GRID := [
	["rest_fresh", "fly_f0", "fly_mid"],
	["dash_r_mid", "dash_r_end", "after_dash_idle"],
]

var _cam: Camera3D
var out_dir := "user://n47_pen_pose"
var _ma: ModelAnimator
var _ap: AnimationPlayer
var _skel: Skeleton3D
var _inst: Node3D
var _shots := {}


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
	print("=== 佩涅罗佩姿态探针（N47）===")
	print("  model_path       = %s" % prof.model_path)
	print("  model_anim_idle  = 「%s」  <- N46 起为空（用户裁决：飞行待机违和）" % prof.model_anim_idle)
	print("  dash_spin_visual = %s" % str(prof.dash_spin_visual))
	print("  extra files      = %d 个" % prof.model_anim_files.size())

	var ps := load(prof.model_path) as PackedScene
	if ps == null:
		print("  !! 主模型载入失败")
		get_tree().quit(1)
		return
	_inst = ps.instantiate() as Node3D
	add_child(_inst)
	await get_tree().process_frame

	_ma = ModelAnimator.setup(_inst, prof.model_anim_files)
	_ma.idle_action = prof.model_anim_idle
	_ma.prepare_loops()
	_ap = _ma.player
	if _ap == null:
		print("  !! 主模型没有 AnimationPlayer ⇒ 下游读数无意义")
		get_tree().quit(1)
		return
	_skel = _find_skel(_inst)
	print("  ready            = %s ｜ 动作表 %d 个 ｜ 骨架 = %s"
		% [str(_ma.ready), _ma.action_names().size(),
		   "找不到" if _skel == null else "%d 骨" % _skel.get_bone_count()])
	if _skel == null:
		print("  !! 没有骨架 ⇒ reset_to_rest() 是**空操作**，本探针无法复现")
	print("  fly 在表里？ %s ｜ dash_r 在表里？ %s"
		% [str(_ma.has("fly")), str(_ma.has("dash_r"))])

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.near = 0.02
	_cam.far = 200.0
	_cam.current = true
	add_child(_cam)
	_place()

	# ---------------- (1) 出厂 rest（什么都不播） ----------------
	var fresh := _snapshot()
	await _shot("rest_fresh")
	var bb_rest := _bbox(_inst)

	# ---------------- (2) fly 首帧 / 中帧 ----------------
	var dur := 0.0
	if _ma.has("fly"):
		dur = _ap.get_animation("fly").length
	_ap.play("fly")
	_ap.seek(0.0, true)
	await _frames(3)
	var fly0 := _snapshot()
	await _shot("fly_f0")
	var bb_fly := _bbox(_inst)

	_ap.seek(dur * 0.5, true)
	await _frames(3)
	await _shot("fly_mid")

	# ---------------- (3) dash_r 中帧 / 末帧 ----------------
	var dart := 0.0
	if _ma.has("dash_r"):
		dart = _ap.get_animation("dash_r").length
	_ap.play("dash_r")
	_ap.seek(dart * 0.5, true)
	await _frames(3)
	await _shot("dash_r_mid")
	_ap.seek(maxf(dart - 0.001, 0.0), true)
	await _frames(3)
	await _shot("dash_r_end")

	# ---------------- (4) ★ 生产路径：冲刺结束 → _enter_idle() → reset_to_rest() ----------------
	_ma.reset_to_rest()
	await _frames(3)
	var after := _snapshot()
	await _shot("after_dash_idle")
	var bb_after := _bbox(_inst)

	# ---------------- 判据一：量化 ----------------
	print("")
	print("=== 判据一 姿态量化（骨局部旋转，双覆盖归一 2*acos(|w|)）===")
	_cmp("rest vs fly 首帧", fresh[0], fly0[0])
	_cmp("rest vs 冲刺后归位", fresh[0], after[0])
	_cmp("fly首帧 vs 冲刺后归位", fly0[0], after[0])
	print("")
	print("  骨原点最大位移（骨架空间，米）：")
	print("    rest -> fly 首帧     : %.4f m" % _max_origin_delta(fresh[1], fly0[1]))
	print("    fly 首帧 -> 冲刺后归位: %.4f m" % _max_origin_delta(fly0[1], after[1]))

	print("")
	print("=== 判据一b 整个模型的网格包围盒（散架 = 包围盒暴涨）===")
	var b0: float = bb_rest.size.length()
	_bb_line("出厂 rest", bb_rest, b0)
	_bb_line("fly 首帧", bb_fly, b0)
	_bb_line("冲刺后归位", bb_after, b0)

	# ---------------- 出图：2×3 拼图 ----------------
	var big := Image.create(CELL_W * 3, CELL_H * 2, false, Image.FORMAT_RGBA8)
	big.fill(BG)
	for row in 2:
		for col in 3:
			var nm: String = str(GRID[row][col])
			if not _shots.has(nm):
				continue
			var im: Image = (_shots[nm] as Image).duplicate()
			im.resize(CELL_W, CELL_H, Image.INTERPOLATE_LANCZOS)
			big.blit_rect(im, Rect2i(0, 0, CELL_W, CELL_H), Vector2i(col * CELL_W, row * CELL_H))
	big.save_png(out_dir.path_join("n47_grid.png"))
	print("")
	print("  拼图 2x3 已存 n47_grid.png")
	print("    上排：rest(出厂) | fly 首帧 | fly 中帧")
	print("    下排：dash_r 中帧 | dash_r 末帧 | ★冲刺结束回待机（= 游戏里你看到的那一格）")

	print("")
	print("VERDICT: N47-PEN-POSE-DONE  -> %s" % out_dir)
	get_tree().quit(0)


# ============================================================ 工具

func _find_skel(root: Node) -> Skeleton3D:
	for c in root.find_children("*", "Skeleton3D", true, false):
		return c as Skeleton3D
	return null


func _place() -> void:
	var az := deg_to_rad(200.0)
	var el := deg_to_rad(10.0)
	var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	_cam.global_position = FOCUS + dir * RADIUS * 2.8
	_cam.look_at(FOCUS, Vector3.UP)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("  !! %s 截图失败" % name)
		return
	# ★ viewport 出来的 Image 不保证 RGBA8 ⇒ 不转的话 blit_rect 会报格式不匹配。
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(out_dir.path_join("%s.png" % name))
	_shots[name] = img


## 读一遍全骨局部旋转 + 骨原点（骨架空间）。返回 [旋转字典, 原点字典]。
func _snapshot() -> Array:
	var q := {}
	var p := {}
	if _skel == null:
		return [q, p]
	for i in _skel.get_bone_count():
		var bn := _skel.get_bone_name(i)
		q[bn] = _skel.get_bone_pose_rotation(i)
		p[bn] = _skel.get_bone_global_pose(i).origin
	return [q, p]


func _cmp(label: String, a: Dictionary, b: Dictionary) -> void:
	var worst := 0.0
	var over1 := 0
	var over5 := 0
	var worst_bone := ""
	for k in a:
		if not b.has(k):
			continue
		var q1: Quaternion = a[k]
		var q2: Quaternion = b[k]
		var d: float = clampf(absf(q1.dot(q2)), 0.0, 1.0)
		var ang: float = rad_to_deg(2.0 * acos(d))
		if ang > 1.0:
			over1 += 1
		if ang > 5.0:
			over5 += 1
		if ang > worst:
			worst = ang
			worst_bone = str(k)
	print("  %-22s 最大 %7.3f°  (%s)   >1° 的骨 %d 个  >5° 的骨 %d 个"
		% [label, worst, worst_bone, over1, over5])


func _max_origin_delta(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for k in a:
		if not b.has(k):
			continue
		var d: float = (a[k] as Vector3).distance_to(b[k] as Vector3)
		if d > worst:
			worst = d
	return worst


func _bb_line(label: String, bb: AABB, base: float) -> void:
	var diag: float = bb.size.length()
	var ratio: float = 1.0
	if base > 0.0:
		ratio = diag / base
	var c := bb.position + bb.size * 0.5
	print("  %-12s size=(%.3f, %.3f, %.3f)  对角线 %.3f m  (相对 rest x%.2f)  center=(%.2f, %.2f, %.2f)"
		% [label, bb.size.x, bb.size.y, bb.size.z, diag, ratio, c.x, c.y, c.z])


## 全部可见网格的合并世界包围盒。
func _bbox(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var wb: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = wb
			first = false
		else:
			out = out.merge(wb)
	return out
