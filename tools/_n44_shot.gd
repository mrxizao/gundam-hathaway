extends Node3D
## N44 佩涅罗佩「已经装进工程」的**视觉证据**。
##
## ## 跑法（**不能加 `--headless`**）
##
##   godot --path <工程> res://tools/_n44_shot.tscn -- <输出目录>
##
## headless 用的是 dummy 渲染器，`get_viewport().get_texture()` 拿不到画面
## （本工程 `capture.gd` / `_n42_21_cmp.gd` 的头注都写着这条）。
##
## ## 它证什么（数值判据之外的另一条腿）
##
## 本工程的铁律是「**数值不能自证**」——`_n44_pen.tscn` 已经量出
## 「28 段动作 / 39 骨 / 328 网格 / ready=true」，但那都是**元数据**。
## 真正会静默出错的是这两件事，只有出图才看得见：
##
##   ① **模型到底可不可见**：`_instantiate_model()` 失败时 `model_root.visible = false`
##      ⇒ 探针照样报"动作表 28 个"，而屏幕上是空的。
##   ② **朝向**：工程约定「模型正面朝 −Z」。本机 `model_yaw_deg = 0`
##      （因为 `penelope_rig_v3` 已把「绕世界 Z +90°」烘进骨架 rest 与顶点）。
##      烘过之后再给 yaw 就是**转双份**；漏给就是**整台侧着飞** —— 两种都不报错。
##      ⇒ `front` 那张（相机在 **−Z** 侧）必须看到**机体的正面**；
##        若拍到的是背包/那两片夹克翼的背面，说明朝向错了。

const MAIN_PATH := "res://assets/models/penelope_movie/penelope_movie_rigged.scn"
const BG := Color(0.12, 0.14, 0.18)
const SHOT_W := 1280
const SHOT_H := 720

## 取景中心与半径（模型原生高 ≈ 0.999 m，脚底 y≈0 ⇒ 中心在 y=0.5）。
const FOCUS := Vector3(0.0, 0.5, 0.0)
const RADIUS := 0.75

## `[tag, 方位角(度), 仰角(度), 距离系数]`
##
## 相机方向 `dir = (sin az·cos el, sin el, cos az·cos el)`，相机坐在 `焦点 + dir·距离`：
##   `az=0`   ⇒ 相机在 **+Z**（机体**背后**）；
##   `az=180` ⇒ 相机在 **−Z**（机体**正前方**）。
const VIEWS := [
	["front", 180.0, 6.0, 1.0],
	["back", 0.0, 6.0, 1.0],
	["left", 270.0, 8.0, 1.0],
	["top", 180.0, 74.0, 1.0],
]

var _cam: Camera3D
var out_dir := "user://n44_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	# 纯色背景：轮廓/可见性肉眼可判，也不会被环境光晕糊掉边界。
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
	if ps == null:
		print("!! 主模型载入失败 %s" % prof.model_path)
		get_tree().quit(1)
		return
	var inst := ps.instantiate() as Node3D
	add_child(inst)

	# ---- 生产接线（与 `FlightBody._setup_model_anim()` 同一组赋值）----
	var ma := ModelAnimator.setup(inst, prof.model_anim_files)
	ma.idle_action = prof.model_anim_idle
	ma.burst_action = prof.model_anim_burst
	ma.burst_cruise_action = prof.model_anim_burst_cruise
	ma.idle_cruise_action = prof.model_anim_idle_cruise
	ma.form_on_action = prof.model_anim_form_on
	ma.form_off_action = prof.model_anim_form_off
	ma.prepare_loops()
	var meshes := inst.find_children("*", "MeshInstance3D", true, false).size()
	print("  ModelAnimator ready=%s ｜ 动作表 %d 个 ｜ 可见网格 %d 件"
		% [str(ma.ready), ma.action_names().size(), meshes])

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.near = 0.02
	_cam.far = 200.0
	_cam.current = true
	add_child(_cam)

	# ---- ① `fly` 待机，四个机位 ----
	if ma.has("fly"):
		ma.play_loop("fly", 0.0, true)
	await _frames(40)          # 让待机姿势真的落地（≈0.67 s @60 Hz）
	for v in VIEWS:
		await _place(str(v[0]), float(v[1]), float(v[2]), float(v[3]))
		await _save("pen_" + str(v[0]))

	# ---- ② 对照：同一机位换播 `slash`，证明**动作真的改变姿势** ----
	#   （数值侧已由 `_n44_pen.tscn` 给出 27/27 有差异；这里是肉眼那一半。）
	if ma.has("slash"):
		ma.stop()
		var a: Animation = ma.player.get_animation("slash")
		ma.player.play("slash", 0.0, 0.0, false)     # speed=0：把播放头钉死
		ma.player.seek(a.length * 0.5, true)
		await _frames(3)
		await _place("front", 180.0, 6.0, 1.0)
		await _save("pen_slash_front")

	print("")
	print("VERDICT: N44-SHOT-DONE  → %s" % out_dir)
	get_tree().quit(0)


func _place(tag: String, az_deg: float, el_deg: float, k: float) -> void:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	_cam.global_position = FOCUS + dir * RADIUS * 2.8 * k
	_cam.look_at(FOCUS, Vector3.UP)
	await _frames(3)


func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("    !! %s 取不到图" % tag)
		return
	var p: String = out_dir.path_join(tag + ".png")
	img.save_png(p)
	print("    saved %-28s (%dx%d)" % [p.get_file(), img.get_width(), img.get_height()])


## 等物理帧（固定 60 Hz）。等渲染帧在几百 fps 的窗口里只有几分之一秒，
## 会出现"动画还没走到那一帧就截图了"（`capture.gd` 头注里的老坑）。
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
