extends Node
## 判据出图探针：柯西的**光束军刀刀身**到底在不在画面上（轮 63-4）。
##
## ## 为什么必须有这一版
## 用户原话：「光束军刀刀身在游戏内不显示（柯西是双头剑，上长下短）」
##
## 旧代码把刀挂在 `rig`（**占位骨架**）的 `hand_L` 槽位上，而只要有真模型
##（= **所有机体的常态**），`FlightBody` 就会 `set_placeholder_visible(false)`
## 把整棵占位子树隐藏 ⇒ 刀**永不显示**。而旧断言只问"节点存在吗 / 在树里吗"
## ⇒ 一直绿。**这条故障不看图是查不出来的**：数值全对、画面上没有刀。
##
## ## 判据（可证伪）
##   ① 每帧打印 `_blade.is_visible_in_tree()` 与"刀根到真骨 `hand_L` 的距离（m）"；
##   ② 每帧打印**屏幕投影**：前刃 / 后刃各自的像素长度（应 ≈ 15 : 9）；
##   ③ 抓 `N_SHOT` 帧覆盖整段突进（玩家 `saber_dash_seconds()` = 2.4 s），图落盘；
##   ④ 像素级统计（"画面上到底有多少绿色刀身"）交给 Python 侧的 `_saberpx.py`
##      —— 不让阈值藏在 GDScript 里，也不让探针自己给自己打分。
##
## ## 负对照（必须做，否则判据可能是永真）
##   把 `_show_blade()` 的首选分支拆掉（强制走占位骨架）再跑一遍
##   ⇒ ① 变 false、② 距离跳到 27 m 量级、③ 图上是**没有刀的机体**。
##
## ## ⚠️ 两个已踩过的坑（v1 就是栽在这上面）
##   **坑 1 · 别把靶机判死。** v1 为了"不让突进提前结束"写了 `_foe.alive = false`
##   —— 结果适得其反：`_step_saber()` 的吸附目标有效性检查里含 `tgt.is_alive()`，
##   靶机一死 ⇒ `saber_target` 当帧失效 ⇒ 过 `SABER_MISS_GRACE`（**0.5 s**）
##   就 `_end_saber()` 走"空挥回收"。实测只抓到了 **4** 张有刀帧。
##   正确做法：靶机**保持活着**，只把它沿机头挪走 30 km
##   （`saber_target` 只在 `try_saber` 写一次、只在 `_end_saber` 清，
##    中途不会被重新求值 ⇒ 挪远了也照样维持突进）。
##   **坑 2 · 抓图本身会推进物理帧。** `await RenderingServer.frame_post_draw`
##   等的是渲染帧，而物理跟着走（`Engine.max_physics_steps_per_frame` 默认 8，
##   渲染一慢就成倍放大）⇒ 每抓一张图实际吃掉 6~27 个物理步，
##   "抓 10 张"根本盖不满 1.5~2.4 s 的突进。
##   正确做法：**抓图前 `get_tree().paused = true` 冻结世界**
##   （`PlayerController`/`FlightBody` 都是默认 PAUSABLE ⇒ 暂停后
##    `_physics_process` 不跑、突进计时器停住），抓完再解冻。
##   这样"抓多少张"与"突进剩多少"彻底解耦。
##
## ## 跑法（⚠️ **不能加 `--headless`**：无头下 RenderingServer 是 dummy，图全黑）
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       res://tools/probe_saber_blade_shots.tscn -- <输出目录>

const ALT := 3000.0
const SHOT_W := 1600
const SHOT_H := 900
## 抓帧节奏：每 `STEP_PHYS` **物理帧**一张、抓 `N_SHOT` 张。
## 玩家突进 `PLAYER_SABER_DASH_TIME` = 2.4 s = 144 物理帧
## ⇒ 12 帧/张 × 10 张 = 120 帧 ≈ 2.0 s，**整段都在突进里**。
## ⚠️ 这个"12"之所以准，是因为抓图期间世界被暂停了（见坑 2）：
##    不暂停的话每张要多走 6~27 帧，120 帧会变成 300+ 帧、后半全是空刀。
const STEP_PHYS := 12
const N_SHOT := 10
## 出图前等几个渲染帧（≥2：隐藏翻一帧会留下渲染历史，第一帧往往还是旧画面）。
const RENDER_WAIT := 3
## 判据下限：至少要抓到这么多张"刀在突进态里"的图，否则探针自己判失败。
const MIN_VALID := 8
## 机位：从**左侧**看 —— 刀轴沿机体 ±Z（前 / 后），左视（沿体轴 ±X 看）能把
## 前 15 m / 后 9 m 看成**横着的两根**。
##
## ⚠️ **镜头要对准刀身、不是机体中心**：手在左臂 ⇒ 刀根偏离机体中心一截，
##    对准机体中心时那 16.5 m 的前刃会被画框切掉（v2 就是这个问题：
##    图上只剩一根，判据 §5.5 #7「能看出上长下短两根」读不出来）。
##    刀全长 16.5 + 10.5 = 27 m ⇒ 距离 ≥ 27/(2·tan(fov/2)) ≈ 23 m 才装得下，
##    再留点余量。`FOLLOW_BLADE = false` 时退回"看机体中心"（负对照/无刀时用）。
const CAM_SIDE := 105.0
const CAM_UP := 16.0
## 特写机位（第 `CLOSEUP_AT` 帧额外拍一张）。
const CAM_SIDE_CLOSE := 45.0
const CAM_UP_CLOSE := 6.0
const CLOSEUP_AT := 2

var _out := "user://saber_shots"
var _host: Node3D
var _pc: PlayerController
var _foe: FlightBody
var _cam: Camera3D
var _valid := 0
var _blank := 0

func _ready() -> void:
	_run()

func _say(s: String) -> void:
	print("[saber] ", s)

## 只在**未暂停**状态下推进物理：`await physics_frame` 每来一次 = 恰好 1 个物理步。
func _adv(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

## 抓一张图。**前置条件：世界已暂停**（否则抓图本身会吃掉突进时长，见坑 2）。
func _capture(name: String) -> void:
	for _i in RENDER_WAIT:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	_say("    出图 %s  %dx%d" % [path, img.get_width(), img.get_height()])

func _place_cam(side: float, up: float) -> void:
	# 对焦点 = 刀根（有刀时）；没刀时退回机体中心。
	var focus: Vector3 = _pc.global_position
	if _pc._blade != null and is_instance_valid(_pc._blade):
		focus = _pc._blade.global_position
	_cam.global_position = focus - _pc.right() * side + _pc.up() * up
	_cam.look_at(focus, _pc.up())

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_say("输出目录 = %s" % _out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await get_tree().process_frame
	await get_tree().process_frame

	# ⚠️ `use_placeholder` 是 **static**：显式写死，免得被别的会话留下的脏值影响
	#（本轮要的就是"真模型"这条路）。
	FlightBody.use_placeholder = false

	_host = Node3D.new()
	_host.name = "Host"
	add_child(_host)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.05, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.88)
	env.ambient_light_energy = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	_host.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-34.0, -128.0, 0.0)
	_host.add_child(sun)

	var cont := Node3D.new()
	cont.name = "Projectiles"
	_host.add_child(cont)

	_pc = PlayerController.new()
	_pc.name = "PC"
	_pc.team = 0
	_pc.is_player = true
	_pc.profile = SuitProfile.xi()
	_pc.display_name = "PC"
	_pc.projectile_container = cont
	cont.add_child(_pc)
	_pc.global_position = Vector3(0.0, ALT, 0.0)
	_pc.max_hp = 600.0
	_pc.hp = 600.0
	_pc.ifield_max = 0.0
	_pc.ifield_hp = 0.0
	_pc.fm.speed = 260.0
	_pc.fm.throttle = 0.78
	_pc.fm.align_velocity(_pc.forward())

	_foe = FlightBody.new()
	_foe.name = "Foe"
	_foe.team = 1
	_foe.profile = SuitProfile.penelope()
	_foe.projectile_container = cont
	cont.add_child(_foe)
	_foe.global_position = Vector3(0.0, ALT, -400.0)   # 吸附距离（玩家 1400 m）内
	_foe.fm.speed = 0.0
	_foe.fm.throttle = 0.0

	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.far = 90000.0
	_host.add_child(_cam)
	_cam.current = true

	await get_tree().process_frame
	await _adv(4)

	# ---- 前置自检（不成立就直接退出，免得后面全是"在仪器上绿"的假读数）----
	if _pc._model_skel == null:
		_say("❌ 柯西没加载真模型（`_model_skel == null`）—— 本节所有图与读数无效")
		get_tree().quit(3)
		return
	var idx: int = _pc._bone_index("hand_L")
	if idx < 0:
		_say("❌ 真骨架里没有 `hand_L` 骨 —— 读数无效")
		get_tree().quit(3)
		return
	_say("前置 OK：柯西有真骨架、有 `hand_L`（bone_idx = %d）" % idx)
	_say("柯西军刀数据：front=%.1f m  rear=%.1f m  double=%s"
		% [_pc.profile.saber_blade_front, _pc.profile.saber_blade_rear,
			str(_pc.profile.saber_double)])
	_say("突进时长 saber_dash_seconds() = %.2f s（= %.0f 物理帧）"
		% [_pc.saber_dash_seconds(), _pc.saber_dash_seconds() * 60.0])

	# ---- 起手 ----
	if not _pc.try_saber(_foe):
		_say("❌ try_saber() 失败 —— 读数无效")
		get_tree().quit(4)
		return
	_say("起手成功：saber_state=%d  吸附目标=%s"
		% [_pc.saber_state, str(_pc.saber_target != null)])
	# ⚠️ 让突进跑满全程，但**不能让靶机死**（见坑 1）：
	#    把它沿机头挪走 30 km —— 扫掠/命中都够不着，而 `saber_target` 依然有效
	#    ⇒ 不走 `SABER_MISS_GRACE` 的空挥回收。挪动方向取**当前机头方向**
	#    ⇒ 机头朝向不变、机位不用跟着改。
	_foe.global_position += _pc.forward() * 30000.0

	# ---- 逐帧抓（抓图期间暂停世界，突进计时不流逝）----
	var f0: float = _pc.profile.saber_blade_front
	var r0: float = _pc.profile.saber_blade_rear
	for i in N_SHOT:
		await _adv(STEP_PHYS)
		get_tree().paused = true      # ← 冻结：下面所有 await 都不推进物理
		var vis := false
		var off := -1.0
		var f_px := -1.0
		var r_px := -1.0
		if _pc._blade != null and is_instance_valid(_pc._blade):
			vis = _pc._blade.is_visible_in_tree()
			var bw: Vector3 = (_pc._model_skel.global_transform
				* _pc._model_skel.get_bone_global_pose(idx)).origin
			off = _pc._blade.global_position.distance_to(bw)
			# 屏幕投影：前刃 / 后刃各自的像素长度（"图上能不能看出上长下短"就是这个量）
			_place_cam(CAM_SIDE, CAM_UP)
			var bt := _pc._blade.global_transform
			var o_px := _cam.unproject_position(bt.origin)
			var f_tip := bt * Vector3(0.0, 0.0, -(f0 + 1.5))
			var r_tip := bt * Vector3(0.0, 0.0, (r0 + 1.5))
			f_px = o_px.distance_to(_cam.unproject_position(f_tip))
			r_px = o_px.distance_to(_cam.unproject_position(r_tip))
		var in_dash: bool = _pc.saber_state == 1
		if in_dash:
			_valid += 1
		else:
			_blank += 1
		_say("帧 %2d  saber_state=%d  在树里可见=%-5s  距真骨 %7.3f m  投影：前刃 %6.1f px / 后刃 %6.1f px（比 %.2f，应 ≈ %.2f）"
			% [i, _pc.saber_state, str(vis), off, f_px, r_px,
				f_px / maxf(r_px, 0.001), (f0 + 1.5) / maxf(r0 + 1.5, 0.001)])
		await _capture("saber_%02d" % i)
		if in_dash and i == CLOSEUP_AT:
			_place_cam(CAM_SIDE_CLOSE, CAM_UP_CLOSE)
			await _capture("saber_%02d_closeup" % i)
		get_tree().paused = false     # ← 解冻，继续推进物理

	_pc.abort_saber()
	get_tree().paused = false
	await _adv(3)
	_say("有效帧=%d / 空刀帧=%d（判据下限 %d）" % [_valid, _blank, MIN_VALID])
	if _valid < MIN_VALID:
		_say("❌ 有刀帧不足 —— 判据图不完整，别拿它下结论")
		get_tree().quit(5)
		return
	_say("done.")
	get_tree().quit(0)
