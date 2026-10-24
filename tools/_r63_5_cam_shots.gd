extends Node
## 轮 63-5 · 批 3 §四 的**真机判据图**：辅助驾驶"两者都在画面里"到底成不成立。
##
## ## 为什么无头判据之外还要出图
## 无头那边量的是**角度**（自机偏角 ≤ 安全角）——它证明的是"几何上在框内"。
## 但"在框内"与"看得见"是两件事：这一台把**真机像素**摆出来，直接回答
## "自机还在不在画面里"。A/B 两份图由**改后**与**改前**的 `chase_camera.gd`
## 渲染 —— **同一台子、同一摆位**，唯一变量是被测源码。
##
## ## 抓两拍（同一 build 内）
##   · `A_frame_both`：辅助驾驶（`frame_both` + 锁定**同时开**）← 用户症状②的现场
##   · `B_lock_only` ：只有锁定层（= `Alt` 手动锁定视角，按设计**不受安全角约束**）
## 4 张图并排看：改前的 A 与 B 应该**几乎一样**（同框层是死代码 ⇒ 后写的锁定层通吃）；
## 改后的 A 里自机回来了、B 仍然把自机甩出去（设计如此）。
##
## ## 跑法
##   godot --path <工程> --resolution 1600x1000 res://tools/_r63_5_cam_shots.tscn \
##       -- <输出目录> <标签>
## ⚠️ **必须真机**：`--headless` 的 dummy 渲染器一个像素都不产生。
##
## ## 摆位（与 `tools/probe_cam_framing.gd` 的 (55°, 1000 m) 同源）
## 自机在 3000 m 高、机头朝 −Z；敌机放在"机头偏 **55°**（= 锁定锥边缘）、**1000 m**"。
## 55° 是关键：半水平视场 16:10 只有 **47.18°**、安全角 29.25°
## ⇒ **改前自机必然出画**（实测 48.46°），改后应落在 29.25°。
##
## ## ⚠️ 两个已踩的坑（都写在这里免得下次再踩）
##   ① **本节点是场景根**，`main` 是它的**子节点** ⇒ Godot 按树序先父后子，
##      于是 `_physics_process` 里**先跑的是本台、后跑的是 `main`** ——
##      摆位会被 `main` 的相机跟随当场覆盖（实测读数 `lock_blend=0.00`、
##      自机偏角与"不摆位"完全一样）。修法 = `process_priority = 1000`
##      + 在 `_process`（渲染帧）里再钉一次。
##   ② 辅助驾驶是**长按 0.45 s** 的开关（`flight_assist`，`HoldAction`）
##      ⇒ 要真按 0.6 s 才会"开启"（HUD 那一行会跟着变）。

const MScript := preload("res://scripts/main.gd")
const W := 1600
const H := 1000
## 敌机方位 / 距离（与无头探针同源）。
const BEARING := 55.0
const DIST := 1000.0
## 摆位之后先空转几帧让混合量爬到 1（`LOCK_VIEW_RATE` 4.5 ⇒ 约 14 帧）。
const SETTLE := 90

var out_dir := "user://_r63_5_cam_shots"
var tag := "run"
var main: Node
var player: Node3D
var chase: ChaseCamera
var foe: Node3D
var _done := false
## 本拍要的**同框层**状态（自己说了算，不读 `chase.frame_both` ——
## 那个字段被 `main._tick_assist()` 每帧改写，读它等于让被测对象决定判据摆位）。
var _pose_fb := true


func _ready() -> void:
	# ① 见文件头：本节点是根，不抬高优先级就会被 `main` 覆盖。
	process_priority = 1000
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		tag = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(W, H))
	await _frames(10)
	print("[shot] display=%s viewport=%s"
		% [DisplayServer.get_name(), str(get_viewport().get_visible_rect().size)])

	Game.active_suit = SuitProfile.Id.XI
	Game.active_side = BattleFormation.Side.MAFTY
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, -1)
	await _frames(40)

	player = main.get("player")
	chase = main.get("chase")
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u == player:
			continue
		if u.has_method("is_alive") and u.is_alive() and u.team != player.team:
			foe = u
			break
	if player == null or chase == null or foe == null:
		push_error("[shot] 建局失败：player=%s chase=%s foe=%s"
			% [str(player), str(chase), str(foe)])
		get_tree().quit(1)
		return
	chase.aim_target = foe

	# ---- 真开辅助驾驶（长按 0.6 s）----
	Input.action_press("flight_assist")
	await _frames(36)
	Input.action_release("flight_assist")
	await _frames(6)
	print("[shot] 辅助驾驶 assist_on=%s（HUD 那一行应显示「开启」）"
		% str(player.get("assist_on")))

	# ---- 拍 A：辅助驾驶（两层都开）----
	_pose_fb = true
	chase.set_lock_view(true)
	await _frames(SETTLE)
	await _shot("A_frame_both")

	# ---- 拍 B：只有锁定层（= 辅助驾驶平移模式 / Alt 手动锁定，症状②的主现场）----
	_pose_fb = false
	chase.set_lock_view(true)
	await _frames(SETTLE)
	await _shot("B_lock_only")

	_done = true
	print("[shot] done -> %s  tag=%s" % [out_dir, tag])
	get_tree().quit(0)


## 把整局的最后状态**钉死**到判据摆位上。
##
## ⚠️ 必须在 `main` **之后**跑（`process_priority` + 渲染帧各钉一次）：
## AI / 物理 / 相机跟随全都在跑，本台只保证"这一帧画出去的"就是判据摆位。
func _pin() -> void:
	if _done or player == null or not is_instance_valid(player) or \
			foe == null or not is_instance_valid(foe) or chase == null:
		return
	var p0 := Vector3(0.0, 3000.0, 0.0)
	player.global_transform = Transform3D(Basis(), p0)
	var yaw := deg_to_rad(BEARING)
	foe.global_position = p0 + Vector3(sin(yaw), 0.0, -cos(yaw)) * DIST
	foe.look_at(p0, Vector3.UP)
	var pf = player.get("fm")
	if pf is FlightModel:
		(pf as FlightModel).velocity = Vector3.ZERO
	var ff = foe.get("fm")
	if ff is FlightModel:
		(ff as FlightModel).velocity = Vector3.ZERO
	# 相机：混合量钉到该拍的目标态，再按**产品自己的公式**落位 / 定姿。
	chase.aim_target = foe
	chase.frame_both = _pose_fb
	chase._fpv_blend = 0.0
	chase._lock_blend = 1.0
	chase._frame_blend = 1.0 if _pose_fb else 0.0
	chase.global_position = chase._desired_position()
	chase.global_transform = Transform3D(chase._desired_basis(), chase.global_position)


func _physics_process(_delta: float) -> void:
	_pin()


func _process(_delta: float) -> void:
	# 渲染帧再钉一次：`main` 的 `_process` 里 `_tick_assist()` 会把 `set_lock_view(false)`
	# 顺带把 `_lock_blend` 清零，必须在它之后重新写回。
	_pin()


func _shot(pose: String) -> void:
	var off := rad_to_deg((-chase.global_transform.basis.z).angle_to(
		chase.global_position.direction_to(player.global_position)))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [out_dir, tag, pose]
	var err := img.save_png(path)
	print("[shot] %s  %dx%d err=%d  自机偏角=%.2f°  frame_both=%s  assist_on=%s"
		% [path, img.get_width(), img.get_height(), err, off,
		   str(chase.frame_both), str(player.get("assist_on"))])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
