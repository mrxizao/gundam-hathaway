extends Node
## 判据探针：**辅助驾驶模式下，前后冲刺会不会把柯西背后的飞行翼收起来。**
##
## ## 用户原话（轮 42）
##
##   「现在柯西在辅助驾驶模式下向前冲刺和向后冲刺的时候背后的飞行翼都会关上，
##     向前和向后辅助飞行翼就别关了，向左向右才关。」
##
## ## 收翼只有**一个**杠杆（先把归因范围收死）
##
## 形态的单一进度量是 `FlightBody.cruise_morph`（1 = 巡航态 / 翼展开，0 = 收起）。
## 它由 `_tick_cruise_morph()` 推：
##
##     want = 1.0 if (fm.boosting and not fm.hovering) else 0.0
##     if _dash_spin_t > 0.0:            # ← 轮 34 加的：左右转身窗口里压低
##         want = 0.0
##
## 而平移模式里 `PlayerController._read_translate_input()` **末尾把 `fm.boosting`
## 写死 true**、`fm.hovering` 写死 false ⇒ `want` 恒为 1。
## ⇒ **唯一能让形态收起来的路径就是 `_dash_spin_t > 0`。**（这条是本次归因的地基，
##   所以第 0 节先把它实测出来，不靠读代码自证。）
##
## ## `_dash_spin_t` 什么时候开
##
## `_start_dash_spin(dir)` 把冲刺方向投影到**机体自身**的水平轴：
##
##     lat = d · right_body        lon = d · fore_body
##     if |lat| < 0.25 or |lat| <= |lon|: return   # 判成立才开窗口
##
## 而 `d` 来自 `_qb_dir` ← `translate_dir.normalized()`，`translate_dir` 的"前 / 右"
## 取自**镜头**的水平轴（`_read_translate_input` 里 `cf` / `cr` 来自 `camera`）。
##
## ⇒ **镜头与机体不同向时，"按 W" 投影到机体上就带横向分量。**
##   锁定镜头（`ChaseCamera.lock_view`）恰恰把视线从"机头前方"拉到"敌机身上"
##   ⇒ 两者分家。这是本探针要量的东西。
##
## ⚠️ 现有测试 `tests/suite_assist_drive.gd::_dash_stow()` 的 ④ 节已经断言
##   「向前冲刺全程**不收**」且**它是绿的** —— 那套件**没有相机**，
##   于是 `_read_translate_input` 退回**机体**基准，与 `_start_dash_spin` 同基准，
##   永远判不出横移。本探针**装真 `ChaseCamera`**，就是为了补上这个缺口。
##
## ## 量什么（每个方向一行）
##
##   ① 冲刺起手那一帧的**镜头 vs 机体**水平夹角 `θ`
##      （θ = 0 ⇒ 两套基准同向；θ 越大 ⇒ "前"越容易被判成横移）
##   ② `_start_dash_spin` 真正算的 `lat` / `lon`（同一式子重算一遍，便于对账）
##   ③ 窗口内 `_dash_spin_t` 开了几帧（0 = 没开窗口 = 不会收翼）
##   ④ 窗口内 `cruise_morph` 的**谷值**（< 0.5 就是"翼关上了"）
##   ⑤ `fm.boosting` 是否全程 true（证明兜底假设）
##
## 用法（无头即可，本探针量的全是**角度**不是像素）：
##   "C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" \
##     --headless --path . res://tools/probe_wing_fold_dash.tscn

const ALT := 3000.0
## 锁定目标距离（复刻用户截图里的 6.5 km）。
const TARGET_RANGE := 6500.0
## 冲刺窗口 `QB_TIME` 之后再多跑几帧，看清"窗口走完之后有没有回展开"。
const MEASURE_FRAMES := 60

const ChaseCameraScript := preload("res://scripts/flight/chase_camera.gd")

## 八个方向：[键名, 说明, 是不是玩家眼里的"左右"]。
## 键名与 `_read_translate_input` 里 `Input.get_axis()` 用的是同一批 action。
const DIRS := [
	["pitch_nose_down", "W  向前", false],
	["pitch_nose_up", "S  向后", false],
	["roll_left", "A  向左", true],
	["roll_right", "D  向右", true],
	["yaw_left", "Q  上升", false],
	["yaw_right", "E  下降", false],
]

var _host: Node3D = null
var _pc: PlayerController = null
var _cam = null
var _lock: LockOnSystem = null
var _foe: FlightBody = null
## 机体钉住的原点（不让它 4 秒飞出几个 km，破坏几何）。
var _origin := Vector3.ZERO


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("\n=== 探针结束 ===")
	get_tree().quit()


func _say(s: String) -> void:
	print(s)


## 建一局：真 ChaseCamera + 真 LockOnSystem + 真 PlayerController（辅助驾驶）。
##
## `bear_deg`：**敌机**相对世界 −Z 的方位角（度）。
## `nose_deg`：**机头**被强制指向的方位角（度）。`NAN` = 不强制，
##             让 `face_target`（= 锁定目标）自己把机头拽过去 —— 真机就是这个样子。
##
## ⚠️ `controls_enabled` **必须 true**：`PlayerController._think()` 第一件事就是
##    `if not controls_enabled:` 早退，并且**顺手把 `translate_mode` 清成 false**
##    （那一支的注释写着"禁控期间不能按最后一份 translate_dir 继续滑行"）。
##    第一次跑探针就踩了这个 —— 整篇读数全是 0，还差点被读成"不支持平移"。
func _setup(bear_deg: float, nose_deg: float) -> void:
	Game.reset()
	FlightBody.use_placeholder = false
	_host = Node3D.new()
	_host.name = "ProbeHost"
	add_child(_host)

	_cam = ChaseCameraScript.new()
	_cam.name = "ProbeCam"
	_host.add_child(_cam)

	_lock = LockOnSystem.new()
	_host.add_child(_lock)

	_pc = PlayerController.new()
	_pc.name = "ProbePC"
	_pc.profile = SuitProfile.xi()
	_pc.is_player = true
	_pc.team = 0
	_pc.controls_enabled = true
	_host.add_child(_pc)
	_origin = Vector3(0.0, ALT, 0.0)
	_pc.global_position = _origin

	_lock.setup(_pc)
	Game.register_lock(_pc, _lock)
	_cam.set_target(_pc)
	_cam.current = true
	_pc.setup_refs(_lock, _cam)
	_pc.assist_on = true

	_foe = PlayerController.new()
	_foe.name = "ProbeFoe"
	_foe.profile = SuitProfile.penelope()
	_foe.is_player = false
	_foe.team = 1
	_foe.controls_enabled = false
	_host.add_child(_foe)
	_foe.global_position = _origin + _bearing(bear_deg) * TARGET_RANGE
	# 敌机原地不动：本探针量的是**自机**的判定，敌机一动几何就漂。
	_foe.set_physics_process(false)
	# **显式**指定锁定对象。不显式指定的话，只有落在自动搜索锥（`outer_deg` 45°）
	# 里的敌机才会被自动选上 —— 第一次跑探针时"敌机方位 90°"那一格就因此没有目标，
	# 镜头根本没进锁定镜头，那一格的 θ 是假的。
	_lock.target = _foe

	# 机头强制指向（可选）：一个空 marker，`face_target_override` 的优先级高于
	# `face_target`（见 `FlightBody._face()`）⇒ 能把"镜头看敌机、机头看别处"造出来。
	if not is_nan(nose_deg):
		var marker := Node3D.new()
		marker.name = "NoseMarker"
		_host.add_child(marker)
		marker.global_position = _origin + _bearing(nose_deg) * TARGET_RANGE
		_pc.face_target_override = marker


## 方位角（度）→ 单位方向。0° = 世界 −Z。
func _bearing(deg: float) -> Vector3:
	var r := deg_to_rad(deg)
	return Vector3(-sin(r), 0.0, -cos(r))


## 推进 n 帧；每帧把自机**钉回原点**，免得它在 4 秒里飞出十几公里把几何跑掉。
func _pump(n: int) -> void:
	for i in n:
		_pc.global_position = _origin
		await get_tree().physics_frame


## 水平前向（去掉 Y 分量后归一）。
func _h(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length_squared() > 1e-8 else Vector3.ZERO


## 水平夹角（度）。任一为零向量 ⇒ 返 −1（"量不出来"，不伪装成 0）。
func _hdeg(a: Vector3, b: Vector3) -> float:
	var x := _h(a)
	var y := _h(b)
	if x == Vector3.ZERO or y == Vector3.ZERO:
		return -1.0
	return rad_to_deg(x.angle_to(y))


func _run() -> void:
	_say("################################################################")
	_say("#  探针：辅助驾驶模式下，冲刺方向 → `_dash_spin_t` → 飞行翼收不收")
	_say("################################################################")
	_say("")
	_say("--- 0 归因地基：平移模式里 `want` 真的恒为 1 吗 ---")
	_say("  若此项不成立，下面所有「收翼 = `_dash_spin_t` 的锅」的推理都作废。")
	await _setup(0.0, NAN)
	await _pump(300)
	_say("  前置 pc.translate_mode  = %s   （false 则本探针整篇无效）" % _pc.translate_mode)
	_say("  前置 pc.assist_on       = %s" % _pc.assist_on)
	_say("  跑 300 帧后：")
	_say("    fm.boosting          = %s   ← `_read_translate_input` 末尾写死 true" % _pc.fm.boosting)
	_say("    fm.hovering          = %s" % _pc.fm.hovering)
	_say("    cruise_morph         = %.4f  （应 ≈ 1：巡航态常驻）" % _pc.cruise_morph)
	_say("    _dash_spin_t         = %.4f  （应 0）" % _pc._dash_spin_t)
	var src := FileAccess.get_file_as_string("res://scripts/flight/player_controller.gd")
	_say("  源码自证 `_read_translate_input` 里那句写死：%s"
		% ("找到 `fm.boosting = true`" if src.contains("fm.boosting = true") else "**没找到**"))
	_teardown()

	# ---- 主表：四种几何 × 六个方向 ----
	#
	# 四种几何是**故意的梯度**，用来把"θ 多大才会误判"钉成一条可读的线：
	#   ① 无锁定                  —— 镜头顺着机头（θ ≈ 0，等同现有测试的环境）
	#   ② 锁定 + 机头自动对准敌机  —— 真机稳态（`face_target` 会转，θ 应该很小）
	#   ③ 锁定 + 机头被按在侧面 90° —— θ ≈ 90°（把镜头/机头分家放大到极限）
	#   ④ 锁定 + 机头被按在侧面 50° —— θ ≈ 50°，刚好压在 45° 门限上方
	_say("")
	_say("--- 1 主表：镜头(锁定)与机头不同向时，各方向冲刺判成什么 ---")
	_say("")
	for geom in [
		[0.0, NAN, "① 无锁定（镜头顺机头）"],
		[0.0, NAN, "② 锁定 + 机头自动对准敌机（真机稳态）"],
		[90.0, 0.0, "③ 锁定+机头被按在正侧方（θ≈90°）"],
		[50.0, 0.0, "④ 锁定+机头被按在斜侧方（θ≈50°）"],
		[30.0, 0.0, "⑤ 锁定+机头被按在斜前方（θ≈30°）"],
	]:
		await _geometry(geom[0], geom[1], geom[2])

	_say("")
	_say("--- 2 源码事实（行号，别信记忆）---")
	_fact("scripts/flight/flight_body.gd", "const DASH_SPIN_MIN_LAT")
	_fact("scripts/flight/flight_body.gd", "absf(lat) <= absf(lon)")
	_fact("scripts/flight/flight_body.gd", "if _dash_spin_t > 0.0:")
	_fact("scripts/flight/flight_body.gd", "want = 0.0")
	_fact("scripts/flight/player_controller.gd", "if camera != null and camera.is_inside_tree():")
	_fact("scripts/flight/player_controller.gd", "translate_dir = want if want.length() <= 1.0")


func _geometry(bear: float, nose_deg: float, label: String) -> void:
	await _setup(bear, nose_deg)
	await _pump(300)
	var theta := _hdeg(-(_cam.global_transform.basis.z), -_pc.global_transform.basis.z)
	_say("── %s" % label)
	var foe_bear := _hdeg(_foe.global_position - _pc.global_position, -_pc.global_transform.basis.z)
	_say("   敌机方位 %.0f° ｜ 锁定目标 = %s ｜ 锁定层级 = %s ｜ 敌机离机头 %.1f° ｜ 镜头锁定混合 = %.2f"
		% [bear, ("有" if _pc.lock.target != null else "**无**"), _pc.lock.tier_name(),
			foe_bear, _cam._lock_blend])
	_say("   θ（镜头水平前 ↔ 机体水平前）= %.2f°" % theta)
	_say("   cruise_morph（起手前）= %.4f    _dash_spin_t = %.4f" % [_pc.cruise_morph, _pc._dash_spin_t])
	_say("   %-10s %8s %8s %8s %9s %9s %7s"
		% ["方向", "lat", "lon", "窗口帧", "morph谷值", "θ@起手", "收翼?"])
	for d in DIRS:
		await _one_dir(d[0], d[1])

	_teardown()


func _one_dir(action: String, label: String) -> void:
	# 回到干净的巡航态再量下一个方向
	await _pump(60)
	var morph0 := _pc.cruise_morph
	Input.action_press(action)
	await _pump(8)   # 让 translate_dir 稳定到该方向（模拟量输入本身就是即时读的）

	# ---- 起手前先算一遍 `_start_dash_spin` 的那两个投影（同一式子重算） ----
	var td: Vector3 = _pc.translate_dir
	var d := _h(td)
	var b := _pc.global_transform.basis
	var right := _h(Vector3(b.x.x, 0.0, b.x.z))
	var fore := _h(Vector3(-b.z.x, 0.0, -b.z.z))
	var lat := d.dot(right) if d != Vector3.ZERO and right != Vector3.ZERO else 0.0
	var lon := d.dot(fore) if d != Vector3.ZERO and fore != Vector3.ZERO else 0.0
	var theta := _hdeg(-(_cam.global_transform.basis.z), -_pc.global_transform.basis.z)

	_pc.request_quick_boost()
	var win := 0
	var min_morph := 1.0
	var boost_all_true := true
	for i in MEASURE_FRAMES:
		_pc.global_position = _origin
		await get_tree().physics_frame
		if _pc._dash_spin_t > 0.0:
			win += 1
			min_morph = minf(min_morph, _pc.cruise_morph)
		if not _pc.fm.boosting:
			boost_all_true = false
	Input.action_release(action)
	var folded := "**关**" if min_morph < 0.5 else "没关"
	_say("   %-10s %8.3f %8.3f %8d %9.4f %8.2f° %7s"
		% [label, lat, lon, win, min_morph, theta, folded])
	if win == 0:
		_say("              └ 窗口没开（`_dash_spin_t` 恒 0）⇒ 形态**没有被压低**，morph 停在 %.4f（起手前 %.4f）"
			% [min_morph, morph0])
	else:
		_say("              └ 窗口开了 %d 帧 ⇒ `want` 被压成 0 ⇒ morph 掉到 %.4f（起手前 %.4f）%s"
			% [win, min_morph, morph0, ("" if boost_all_true else "  ⚠️ 期间 fm.boosting 曾为 false")])


func _teardown() -> void:
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	_host = null
	_pc = null
	_cam = null
	_lock = null
	_foe = null
	await get_tree().process_frame


func _fact(path: String, needle: String) -> void:
	var src := FileAccess.get_file_as_string("res://" + path)
	if src == "":
		_say("  %s  「%s」  行号 = **文件读不到**" % [path.get_file(), needle])
		return
	var lines := src.split("\n")
	for i in lines.size():
		if lines[i].contains(needle):
			_say("  %-28s %-46s 行号 = %d" % [path.get_file(), needle, i + 1])
			return
	_say("  %-28s %-46s 行号 = **找不到**" % [path.get_file(), needle])
