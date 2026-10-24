extends Node3D
## N47b：找**正确的归位方式** ＋ 净效应隔离「三个 setter 里哪一个在毁模型」。
##
## ## 背景
##
## N47 实测：`reset_to_rest()`（把 pose 设成 `Quaternion()`/`ZERO`/`ONE`）
## 之后与「出厂 rest」相差**最大 171.5°、37/39 骨 > 5°、骨原点位移 1.05 m**
## ⇒ 模型被压成一个尖刺团。出图 `n47_pose/after_dash_idle.png` 可见。
##
## ⇒ 该实现把 Godot 的 `Skeleton3D` pose 当成了「相对 rest 的偏移」，
##   而它其实是**骨骼在父空间里的绝对局部变换** —— 本工程 T6 早已记下这条，
##   但 `reset_to_rest()` 的实现违背了它。
##
## ## 本探针要回答的三个问题
##
##   1. `set_bone_pose(i, get_bone_rest(i))` 能不能**逐位**回到出厂 rest？
##   2. 有没有官方 API（`reset_bone_poses` 之类）能一步做到？
##   3. 三个 setter（rotation / position / scale）里，**哪一个**才是主凶？
##
## 跑法（**不能加 `--headless`**）：
##   godot --path <工程> res://tools/_n47b_rest_fix.tscn -- <输出目录>

const BG := Color(0.10, 0.12, 0.15)
const FOCUS := Vector3(0.0, 0.5, 0.0)
const RADIUS := 0.75
const CELL_W := 640
const CELL_H := 360

var _cam: Camera3D
var out_dir := "user://n47b_rest_fix"
var _ma: ModelAnimator
var _ap: AnimationPlayer
var _skel: Skeleton3D
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
	var ps := load(prof.model_path) as PackedScene
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	await get_tree().process_frame
	_ma = ModelAnimator.setup(inst, prof.model_anim_files)
	_ap = _ma.player
	for c in inst.find_children("*", "Skeleton3D", true, false):
		_skel = c as Skeleton3D
		break

	print("=== N47b 归位方式候选（佩涅罗佩）===")
	print("  骨架 = %d 骨 ｜ AnimationPlayer = %s" % [_skel.get_bone_count(), str(_ap != null)])
	print("  Skeleton3D 的可用复位 API：")
	for m in ["reset_bone_poses", "clear_bones_global_pose_override", "set_bone_pose",
			"get_bone_rest", "get_bone_pose", "reset_bone_pose"]:
		print("    %-32s %s" % [m, str(_skel.has_method(m))])

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.near = 0.02
	_cam.far = 200.0
	_cam.current = true
	add_child(_cam)
	_place()

	# ---- 出厂 rest = 参照 ----
	var fresh := _snapshot()
	await _shot("00_fresh")

	# ---- 候选 A：set_bone_pose(i, get_bone_rest(i)) ----
	print("")
	print("=== 候选 A：set_bone_pose(i, get_bone_rest(i)) ===")
	_rest_by_rest()
	await _frames(3)
	var cand_a := _snapshot()
	_cmp("A vs 出厂 rest", fresh[0], cand_a[0])
	print("    骨原点最大位移 : %.6f m" % _max_origin_delta(fresh[1], cand_a[1]))
	await _shot("10_candA_rest_by_rest")

	# ---- 候选 B：官方 reset_bone_poses()（存在才试） ----
	if _skel.has_method("reset_bone_poses"):
		print("")
		print("=== 候选 B：reset_bone_poses() ===")
		_rest_by_rest()          # 先回到已知态
		await _frames(2)
		_skel.call("reset_bone_poses")
		await _frames(3)
		var cand_b := _snapshot()
		_cmp("B vs 出厂 rest", fresh[0], cand_b[0])
		print("    骨原点最大位移 : %.6f m" % _max_origin_delta(fresh[1], cand_b[1]))
		await _shot("11_candB_reset_bone_poses")
	else:
		print("")
		print("=== 候选 B：reset_bone_poses() —— **不存在**，跳过 ===")

	# ---- 净效应隔离：三个 setter 各自单独来一遍 ----
	print("")
	print("=== 净效应隔离：三个 setter 各自单独来一遍（每次都先从候选 A 复位）===")
	await _iso("20_rot_identity", "rot", fresh)
	await _iso("21_pos_zero", "pos", fresh)
	await _iso("22_scale_one", "scale", fresh)

	# ---- 现状实现（三个一起）= 用户看到的那个 ----
	print("")
	print("=== 现状实现：三个 setter 一起（= `reset_to_rest()` 今天的样子）===")
	_rest_by_rest()
	await _frames(2)
	_ma.reset_to_rest()
	await _frames(3)
	var after := _snapshot()
	_cmp("现状 vs 出厂 rest", fresh[0], after[0])
	print("    骨原点最大位移 : %.6f m" % _max_origin_delta(fresh[1], after[1]))
	await _shot("30_current_reset_to_rest")

	# ---- 拼图 ----
	var cells := ["00_fresh", "10_candA_rest_by_rest", "11_candB_reset_bone_poses",
			"20_rot_identity", "21_pos_zero", "30_current_reset_to_rest"]
	var big := Image.create(CELL_W * 3, CELL_H * 2, false, Image.FORMAT_RGBA8)
	big.fill(BG)
	for i in cells.size():
		var nm: String = str(cells[i])
		if not _shots.has(nm):
			continue
		var im: Image = (_shots[nm] as Image).duplicate()
		im.resize(CELL_W, CELL_H, Image.INTERPOLATE_LANCZOS)
		big.blit_rect(im, Rect2i(0, 0, CELL_W, CELL_H),
				Vector2i((i % 3) * CELL_W, (i / 3) * CELL_H))
	big.save_png(out_dir.path_join("n47b_grid.png"))
	print("")
	print("  拼图 3x2 已存 n47b_grid.png")
	print("    上排：出厂 rest | 候选A set_bone_pose(rest) | 候选B reset_bone_poses()")
	print("    下排：只归零 rotation | 只归零 position | 现状三个一起(= 游戏里的乱)")

	print("")
	print("VERDICT: N47B-REST-FIX-DONE  -> %s" % out_dir)
	get_tree().quit(0)


# ============================================================ 工具

## 候选 A：把每根骨的 pose 设成它自己的 rest。
func _rest_by_rest() -> void:
	for i in _skel.get_bone_count():
		_skel.set_bone_pose(i, _skel.get_bone_rest(i))


func _iso(shot_name: String, which: String, fresh: Array) -> void:
	_rest_by_rest()
	await _frames(2)
	var n := _skel.get_bone_count()
	match which:
		"rot":
			for i in n:
				_skel.set_bone_pose_rotation(i, Quaternion())
		"pos":
			for i in n:
				_skel.set_bone_pose_position(i, Vector3.ZERO)
		"scale":
			for i in n:
				_skel.set_bone_pose_scale(i, Vector3.ONE)
	await _frames(3)
	var s := _snapshot()
	_cmp("只改 %-5s vs 出厂 rest" % which, fresh[0], s[0])
	print("        骨原点最大位移 %.6f m" % _max_origin_delta(fresh[1], s[1]))
	await _shot(shot_name)


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
		return
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(out_dir.path_join("%s.png" % name))
	_shots[name] = img


func _snapshot() -> Array:
	var q := {}
	var p := {}
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
	print("  %-26s 最大 %8.4f°  (%s)   >1° %d 个  >5° %d 个"
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
