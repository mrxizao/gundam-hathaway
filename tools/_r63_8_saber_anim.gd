extends Node
## 轮 63-8 判据探针（★63-7 探针的**加宽机位版**）：**光束军刀挥砍动作到底有没有进游戏**，以及「幅度到底差多少」。
##
## ## 为什么另开一份、而不是改 ★63-7 那份
## ★63-7 的 `tools/_r63_7_saber_anim.gd` 是**上一轮的可复现证据**（连拍 10 张 + 负对照图），
## 改它就等于改历史读数。而 ★63-7 的机位（`CAM_SEQ_SIDE 34`）是按**旧动作**（`hand_L` 走 4.4 m）
## 定的；★63-8 把动作幅度放大到 13.5 m 之后，刀**扫出了画框**（帧 5 包围盒左边界 = 0）
## ⇒ 同机位量到的行程只是**下界**。所以本轮：
##   · 保留 ★63-7 那份不动；
##   · 另起这一份，机位拉远（`CAM_SEQ_SIDE 34 → 50`、`CAM_SEQ_UP 6 → 10`），
##     并新增**画框余量自检**（逐帧把刀根/前刃尖/后刃尖投影到屏幕，报离边框的最小余量），
##     让「有没有切出画」变成一个**可读的数**，而不是靠眼睛看图猜。
##   · 改前 / 改后各跑一遍（同一机位）⇒ 屏幕行程才可比。
##
## 背景：用户报「刀身不显示 + 动作得重新做」，★63-4 修掉了刀身（挂点长在被隐藏的占位骨架上），
## 但**动作本身**只剩 5 根骨在动（`UpperArm.L` 64°、`Chest`/`Hips`/`UpperArm.R` 全 0°）。
## 本轮要回答三个问题，全部用读数、不靠读码推断：
##
##   ① 调用链通不通：`try_saber()` → `play_model_action("slash")` → `ModelAnimFSM.request_action()`
##      → `ModelAnimator.play_once()`。**决定性一问 = `anim.has("slash")` 与 `action_names()`**
##      —— 若运行期剪辑名不是 `slash`，动作永远播不出来而**不报任何错**。
##   ② 动作真的在跑：逐帧 `model_fsm.state` / `current_action()` / `anim.current` /
##      `player.current_animation_position` / `desyncs`。播放头**在推进**才算在跑。
##   ③ 幅度用「米」说话（设计 §5.5 判据 6）：真骨架 `hand_L` 的**世界位移峰值 ≥ 3 m**。
##      ⚠️ glb 里骨架是 ~1 m 单位空间（`model_native_height`），真机尺度由
##      `inst.scale = target_height / model_native_height` 给 ⇒ **只有引擎里量的才是米**。
##      同时量 `Chest`/`Hips`/`Shoulder.L`/`UpperArm.R` 的世界旋转跨度（判据 5 的引擎侧复核）。
##
## 另外两个出图任务（同一次运行内完成）：
##   · 柯西双头剑侧视：前刃 15 m / 后刃 9 m 应看成**一长一短两根**（判据 7）；
##   · 下刃长度三档对照（7.5 / 9.0 / 11.0）交给用户在 §九-5 上拍板。
##
## ## ⚠️ 三个已踩过的坑（沿用 ★63-4 的结论，别重犯）
##   1. **别把靶机判死**：`_step_saber()` 的有效性检查含 `tgt.is_alive()` ⇒ 靶机一死，
##      过 `SABER_MISS_GRACE`（0.5 s）就空挥回收。正解 = 靶机**保持活着**、沿机头挪走 30 km。
##   2. **抓图本身推进物理帧**：所以抓图前 `get_tree().paused = true`。
##   3. **镜头对准判据物**（刀身/手），不是场景中心，否则长刀被画框切掉。
##
## ## 跑法（⚠️ 不能加 `--headless`：无头下 RenderingServer 是 dummy，图全黑）
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       res://tools/_r63_8_saber_anim.tscn -- <输出目录>

const ALT := 3000.0
const SHOT_W := 1600
const SHOT_H := 900
const RENDER_WAIT := 3
## ② 连拍节奏：每 10 物理帧一张 × 10 张 = 100 帧 ≈ 1.67 s
##（`slash` 段长 1.50 s ⇒ **整段挥砍都在里面**）。
const STEP_PHYS := 10
const N_SHOT := 10
const MIN_VALID := 8

## 判据 5 的引擎侧复核：整段里这几根骨的世界旋转跨度。
const SPAN_BONES := ["UpperArm.L", "LowerArm.L", "Shoulder.L", "UpperArm.R", "Chest", "Spine", "Hips"]
## 判据 6 的门槛（米）。
const HAND_MIN := 3.0
## 下刃三档对照的长度（米）。
const REAR_CHOICES := [7.5, 9.0, 11.0]
## 双头剑出图机位（⚠️ 首版 105 m 太远：机体在画幅里只占 ~140 px，长短读不出来）。
const CAM_NEAR_SIDE := 42.0
const CAM_NEAR_UP := 5.0
## 挥砍连拍机位：**钉机体**（`look_at_blade = false`），近一点才看得出手的行程。
## ★63-8：34/6 是按旧动作定的 ⇒ 动作放大后刀扫出画。拉远到 50/10，并加画框余量自检。
const CAM_SEQ_SIDE := 50.0
const CAM_SEQ_UP := 10.0

var _out := "user://r63_8_saber"
var _host: Node3D
var _pc: PlayerController
var _foe: FlightBody
var _cam: Camera3D
var _bone_idx := {}
var _valid := 0

func _ready() -> void:
	_run()

func _say(s: String) -> void:
	print("[r63_8] ", s)

func _adv(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _capture(name: String) -> void:
	for _i in RENDER_WAIT:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	_say("    出图 %s.png  %dx%d" % [name, img.get_width(), img.get_height()])

func _bone_world(nm: String) -> Vector3:
	var idx: int = _bone_idx.get(nm, -1)
	if idx < 0:
		return Vector3.ZERO
	return (_pc._model_skel.global_transform * _pc._model_skel.get_bone_global_pose(idx)).origin

func _bone_quat(nm: String) -> Quaternion:
	var idx: int = _bone_idx.get(nm, -1)
	if idx < 0:
		return Quaternion.IDENTITY
	var b: Basis = (_pc._model_skel.get_bone_global_pose(idx)).basis
	return b.get_rotation_quaternion()

## **局部**姿态（相对父骨）。这一条才与资产侧 `_r63_7_ruler.py` 的 glb 跨度同口径 ——
## 上面那个 `_bone_quat()` 是**世界**姿态，会把父骨的旋转累加进来（读数会明显偏大）。
func _bone_local_quat(nm: String) -> Quaternion:
	var idx: int = _bone_idx.get(nm, -1)
	if idx < 0:
		return Quaternion.IDENTITY
	var b: Basis = (_pc._model_skel.get_bone_pose(idx)).basis
	return b.get_rotation_quaternion()

## 一组四元数的**两两最大夹角**（度）—— 与资产侧 `_r63_dbg2.py` / `_r63_7_ruler.py` 同口径。
func _pairwise_span(qs: Array) -> float:
	var mx := 0.0
	for a in range(qs.size()):
		for b in range(a + 1, qs.size()):
			mx = maxf(mx, rad_to_deg(absf((qs[a] as Quaternion).angle_to(qs[b] as Quaternion))))
	return mx

func _place_cam(side: float, up: float, look_at_blade := true) -> void:
	var focus: Vector3 = _pc.global_position
	if look_at_blade and _pc._blade != null and is_instance_valid(_pc._blade):
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
	_foe.global_position = Vector3(0.0, ALT, -400.0)
	_foe.fm.speed = 0.0
	_foe.fm.throttle = 0.0

	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.far = 90000.0
	_host.add_child(_cam)
	_cam.current = true

	await get_tree().process_frame
	await _adv(6)

	# ================= ⓪ 前置自检 =================
	if _pc._model_skel == null:
		_say("❌ 柯西没加载真模型（`_model_skel == null`）—— 本轮所有图与读数无效")
		get_tree().quit(3)
		return
	_say("前置 OK：真模型已加载")
	var p := _pc.profile
	_say("尺度：target_height = %.2f m   model_native_height = %.3f m  ⇒  inst.scale = %.3f"
		% [p.target_height, p.model_native_height,
			p.target_height / maxf(p.model_native_height, 0.001)])
	_say("军刀数据：front = %.1f m   rear = %.1f m   double = %s   has_saber = %s"
		% [p.saber_blade_front, p.saber_blade_rear, str(p.saber_double), str(p.has_saber)])
	for nm in SPAN_BONES + ["hand_L", "LowerArm.R"]:
		var idx: int = _pc._bone_index(nm)
		_bone_idx[nm] = idx
	_say("骨索引：%s" % str(_bone_idx))
	if _bone_idx.get("hand_L", -1) < 0:
		_say("❌ 真骨架里没有 `hand_L` 骨 —— 读数无效")
		get_tree().quit(3)
		return

	# ================= ① 调用链：动作名到底在不在 =================
	var ma: ModelAnimator = _pc.model_anim
	if ma == null:
		_say("❌ `model_anim == null` —— 这个模型没有动作播放器")
		get_tree().quit(4)
		return
	var names: Array = ma.action_names()
	_say("① 运行期动作名共 %d 个：%s" % [names.size(), str(names)])
	_say("① `anim.has(\"slash\")` = %s   `idle_action` = %s"
		% [str(ma.has("slash")), ma.idle_action])
	if not ma.has("slash"):
		_say("❌❌ 运行期**没有** `slash` 这个动作名 ⇒ `request_action(\"slash\")` 会静默 `return false`，"
			+ "动作在游戏里根本播不出来。这才是「动作没进游戏」的真根因。")
	else:
		_say("✅ `slash` 在运行期动作表里 ⇒ 调用链的名字这一环是通的")

	# ================= ② 起手 + 逐帧读数（判据 6 + 判据 5 引擎复核）=================
	_pc.saber_cooldown = 0.0
	if not _pc.try_saber(_foe):
		_say("❌ try_saber() 失败 —— 读数无效")
		get_tree().quit(5)
		return
	_say("② 起手成功：saber_state = %d（1 = CHARGE）  吸附目标 = %s  突进时长 = %.2f s"
		% [_pc.saber_state, str(_pc.saber_target != null), _pc.saber_dash_seconds()])
	_foe.global_position += _pc.forward() * 30000.0   # 挪远但不判死（坑 1）

	var fsm: ModelAnimFSM = _pc.model_fsm
	_say("② 起手当帧：fsm.state = %d   current_action() = %s   anim.current = %s   刀可见 = %s"
		% [fsm.state, fsm.current_action(), ma.current,
			str(_pc._blade != null and _pc._blade.is_visible_in_tree())])

	# ⚠️ **必须换算到机体坐标系**：突进本身以 ~1150 m/s 在飞，直接把世界坐标相减
	# 量到的是"机体飞了多远"（首版实测 4600 m），跟挥刀毫无关系。
	# 判据要的是"手相对机体扫过多少米" ⇒ 用 `to_local()`。
	#
	# ⚠️ 统计口径统一为**两两取最大**（与资产侧 `_r63_7_ruler.py` / `_r63_dbg2.py` 一致）：
	#    "与首帧比"会低估（姿态非单调时读不到真正的极值）。
	var hpts: Array = []
	var wq := {}
	var lq := {}
	for nm in SPAN_BONES:
		wq[nm] = []
		lq[nm] = []
	var h0: Vector3 = _pc.to_local(_bone_world("hand_L"))
	hpts.append(h0)
	for nm in SPAN_BONES:
		(wq[nm] as Array).append(_bone_quat(nm))
		(lq[nm] as Array).append(_bone_local_quat(nm))
	var path := 0.0
	var prev := h0
	var saw_action := false
	var action_frames := 0
	var pos_lo := 999.0
	var pos_hi := -1.0
	var desync0: int = fsm.desyncs
	# 采样 100 帧（≈1.67 s，覆盖 1.50 s 的 slash 段）
	for i in 100:
		await get_tree().physics_frame
		var h: Vector3 = _pc.to_local(_bone_world("hand_L"))
		path += prev.distance_to(h)
		prev = h
		hpts.append(h)
		for nm in SPAN_BONES:
			(wq[nm] as Array).append(_bone_quat(nm))
			(lq[nm] as Array).append(_bone_local_quat(nm))
		if fsm.state == ModelAnimFSM.State.ACTION:
			action_frames += 1
			if fsm.current_action() == "slash":
				saw_action = true
			pos_lo = minf(pos_lo, ma.player.current_animation_position)
			pos_hi = maxf(pos_hi, ma.player.current_animation_position)
		if i % 10 == 0 or i < 5:
			_say("   帧%3d  fsm.state=%d  action=%s  anim.current=%s  播放头=%.3f  在播=%s  手机体坐标=%s  saber_state=%d"
				% [i, fsm.state, fsm.current_action(), ma.current,
					ma.player.current_animation_position, str(ma.player.is_playing()),
					str(h.round()), _pc.saber_state])

	# ---- 统计（两两取最大）----
	var peak := 0.0
	for a in range(hpts.size()):
		for b in range(a + 1, hpts.size()):
			peak = maxf(peak, (hpts[a] as Vector3).distance_to(hpts[b] as Vector3))
	var span_max := {}
	var lspan_max := {}
	for nm in SPAN_BONES:
		span_max[nm] = _pairwise_span(wq[nm])
		lspan_max[nm] = _pairwise_span(lq[nm])

	_say("")
	_say("② 汇总：走过 ACTION 态且动作名 = `slash` ？ **%s**（ACTION 帧数 = %d）"
		% ["是" if saw_action else "否", action_frames])
	_say("② 播放头区间 = [%.3f, %.3f] s（推进 = %s）；desyncs 增量 = %d"
		% [pos_lo, pos_hi, str(pos_hi > pos_lo), fsm.desyncs - desync0])
	_say("③ 判据 6：`hand_L` 世界位移峰值 = **%.3f m**（累计路程 %.3f m）门槛 ≥ %.1f m ⇒ **%s**"
		% [peak, path, HAND_MIN, "PASS" if peak >= HAND_MIN else "FAIL"])
	_say("③ 判据 5 引擎侧复核（度）：  「局部跨度」= 相对父骨（**与 glb 口径一致**）；"
		+ "「世界跨度」= 累加了父骨旋转）
")
	_say("     %-12s %10s %10s" % ["骨", "局部跨度", "世界跨度"])
	for nm in SPAN_BONES:
		_say("     %-12s %10.2f %10.2f" % [nm, lspan_max[nm], span_max[nm]])

	# ================= ③ 连拍（判据 7）=================
	_pc.abort_saber()
	await _adv(4)
	# ⚠️ **必须先把靶机放回吸附范围内**再起手：`saber_target` 只在 `try_saber()` 里写一次，
	# 而玩家路径有 `SABER_MISS_GRACE`（0.5 s）—— **没有吸附目标**就 0.5 s 后直接收刀。
	# 首版把靶机留在 30 km 外 ⇒ 第二次起手没设上 `saber_target` ⇒ 突进只走了 ~30 帧，
	# 10 张连拍里只有 3 张在突进态（3/10）。
	_foe.global_position = _pc.global_position + _pc.forward() * 400.0
	await _adv(1)
	_pc.saber_cooldown = 0.0
	if not _pc.try_saber(_foe):
		_say("❌ 第二次起手失败，连拍作废")
		get_tree().quit(6)
		return
	_say("④ 第二次起手：吸附目标 = %s（必须在突进期内保持非空）" % str(_pc.saber_target != null))
	# 吸附目标已设上 ⇒ 现在把它挪远（保活、维持突进，见坑 1）
	_foe.global_position = _pc.global_position + _pc.forward() * 30000.0
	_say("")
	_say("④ 连拍：每 %d 物理帧一张 × %d 张" % [STEP_PHYS, N_SHOT])
	# ★63-8 机位自检：`unproject_position` 用的是视口坐标，而存盘图就是视口纹理
	# ⇒ 两者同尺寸（1600×900）。⚠️ **必须先 `_place_cam()` 再看读数** —— 否则相机还停在
	# 出生位（identity），读到的是"机体在世界里离相机多远"，与画幅无关（首版读到 (800, 5)）。
	# `look_at()` 把焦点摆到画幅正中 ⇒ 正常应读到 ≈ (800, 450)。
	_place_cam(CAM_SEQ_SIDE, CAM_SEQ_UP, false)
	_say("   机位自检：机体投影 = %s（画幅 %dx%d 中心 = %s）"
		% [str(_cam.unproject_position(_pc.global_position).round()),
			SHOT_W, SHOT_H, str(Vector2(SHOT_W * 0.5, SHOT_H * 0.5))])
	var margin_min := 99999.0
	for i in N_SHOT:
		await _adv(STEP_PHYS)
		get_tree().paused = true
		var vis := false
		var off := -1.0
		if _pc._blade != null and is_instance_valid(_pc._blade):
			vis = _pc._blade.is_visible_in_tree()
			off = _pc._blade.global_position.distance_to(_bone_world("hand_L"))
		var in_dash: bool = _pc.saber_state == 1
		if in_dash:
			_valid += 1
		# ⚠️ **镜头钉在机体上、不钉在刀上**：首版用 `_place_cam(105,16)`（默认 look_at_blade=true）
		# ⇒ 相机跟着刀根走，而刀身朝向 = 机体 basis（`_sync_blade_anchor()` 的既定做法）
		# ⇒ **屏幕上刀身纹丝不动**，10 帧的绿像素包围盒逐帧完全相同（684,448,874,452）
		# —— 仪器把要判的事抵消掉了。机体锚定后，挥刀才表现为刀在画幅里扫过。
		_place_cam(CAM_SEQ_SIDE, CAM_SEQ_UP, false)
		# ★63-8 画框余量：刀根 + 前刃尖 + 后刃尖三点投影，取到四边的最小距离。
		# ≤ 0 = 这一帧的刀被画框切了 ⇒ 该帧的屏幕行程只能当**下界**。
		var margin := 99999.0
		if _pc._blade != null and is_instance_valid(_pc._blade):
			var bt: Transform3D = _pc._blade.global_transform
			var tips: Array[Vector3] = [Vector3.ZERO,
				Vector3(0.0, 0.0, -(_pc.profile.saber_blade_front + 1.5)),
				Vector3(0.0, 0.0, (_pc.profile.saber_blade_rear + 1.5))]
			for lp: Vector3 in tips:
				var sp: Vector2 = _cam.unproject_position(bt * lp)
				margin = minf(margin, minf(minf(sp.x, float(SHOT_W) - sp.x),
					minf(sp.y, float(SHOT_H) - sp.y)))
		margin_min = minf(margin_min, margin)
		_say("   帧%2d  突进态=%-5s  刀在树里可见=%-5s  距真骨 %6.3f m  fsm.action=%s  播放头=%.3f  画框余量 %7.1f px"
			% [i, str(in_dash), str(vis), off, fsm.current_action(),
				ma.player.current_animation_position, margin])
		await _capture("slash_%02d" % i)
		get_tree().paused = false
	_say("④ 画框余量最小值 = %.1f px ⇒ %s"
		% [margin_min, "全部在画内（读数可信）" if margin_min > 0.0 else "⚠️ 有帧被切 ⇒ 行程只是下界"])
	_pc.abort_saber()
	get_tree().paused = false
	await _adv(3)
	_say("④ 有效（在突进态里的）帧 = %d / %d（下限 %d）⇒ %s"
		% [_valid, N_SHOT, MIN_VALID, "OK" if _valid >= MIN_VALID else "❌ 判据图不完整"])
	if _valid < MIN_VALID:
		get_tree().quit(7)
		return

	# ================= ④ 双头剑侧视 + 下刃三档对照（§九-5）=================
	get_tree().paused = true
	var f0: float = _pc.profile.saber_blade_front
	for rear in REAR_CHOICES:
		_pc.profile.saber_blade_rear = float(rear)
		_pc._show_blade()
		_place_cam(CAM_NEAR_SIDE, CAM_NEAR_UP)
		await _capture("twin_side_%04d" % int(round(float(rear) * 10.0)))
		_place_cam(CAM_NEAR_SIDE, CAM_NEAR_UP * 4.0)
		await _capture("twin_high_%04d" % int(round(float(rear) * 10.0)))
		# 屏幕投影：前刃 / 后刃各自像素长度（"图上能不能看出上长下短"就是这个量）
		var f_px := -1.0
		var r_px := -1.0
		if _pc._blade != null and is_instance_valid(_pc._blade):
			_place_cam(CAM_NEAR_SIDE, CAM_NEAR_UP)
			var bt: Transform3D = _pc._blade.global_transform
			var o_px := _cam.unproject_position(bt.origin)
			var f_tip: Vector3 = bt * Vector3(0.0, 0.0, -(f0 + 1.5))
			var r_tip: Vector3 = bt * Vector3(0.0, 0.0, (float(rear) + 1.5))
			f_px = o_px.distance_to(_cam.unproject_position(f_tip))
			r_px = o_px.distance_to(_cam.unproject_position(r_tip))
		_say("   下刃 %5.1f m ⇒ 屏幕投影：前刃 %6.1f px / 后刃 %6.1f px  (比 %.2f)"
			% [float(rear), f_px, r_px, f_px / maxf(r_px, 0.001)])
	# 还原示意值（判据探针不许改产品的持久状态）
	_pc.profile.saber_blade_rear = 9.0
	_pc._show_blade()
	get_tree().paused = false

	_say("done.")
	get_tree().quit(0)
