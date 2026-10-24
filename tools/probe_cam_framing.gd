extends Node
## 无头判据台：锁定视角下「**自机还在不在画面里**」（轮 63-5 · 批 3 §四）。
##
## ## 为什么要无头
## 相机是**全工程唯一一台**，回归风险最高（发射段 / FPV / 震动池 / FOV / 六节套件）。
## 但"自机在不在画面里"**本质是一个几何量**，不依赖渲染
##（量的是"相机 → 自机"与"相机 → 视线点"两条射线的夹角），
## 所以它**必须**能在 `--headless` 下跑 —— 否则不敢动相机。
##
## ## 量的是什么
##   ① `_baseline`：对 (目标方位 θ × 距离 D) 网格，用**真实** `_desired_position()` /
##      `_desired_basis()` 算出视轴，再量
##        · 自机相对视轴夹角  `player_off`
##        · 敌机相对视轴夹角  `target_off`
##      与半水平视场比 ⇒ 谁出画。
##   ② `_collapse`：**证明"辅助驾驶的同框层"是死代码**。
##      做法：同一几何下跑三次 —— 只开锁定 / 只开同框 / 两个都开
##      （`_frame_blend` 与 `_lock_blend` 直接写 1.0，不靠计时器逐步逼近）。
##      若"两个都开"的结果与"只开锁定"**逐位相同**，就说明同框层被后写的锁定层吃掉了。
##   ③ `_jerk`：目标横移 2000 m/s 时，视线点的**瞬时**转向量（度）。
##      除以 `rotate_lag` 的时间常数（1/5 s = 12 帧）⇒ 峰值 ≈ 度/帧，用来量"瞬拉"。
##
## ## 模拟 vs 产品（**这条要看清**）
## 表里带 `[模拟]` 的行是**把设计文档 §4.4 的公式在探针里重写一遍**算出来的，
## **不是产品读数** —— 它的用途只有一个：让你在拍板**系数**之前看见量级。
## 产品落地之后必须**再跑一次**，以 `_baseline` 口径的读数为准。
##
## ## 跑法
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       res://tools/probe_cam_framing.tscn

const ALT := 3000.0
## 目标方位角（水平，度）。55 = 锁定锥边缘（`lock_on_system.gd` 的 `LOCK_CONE_DEG`）。
const BEARINGS := [0.0, 10.0, 20.0, 30.0, 40.0, 45.0, 50.0, 55.0]
const DISTS := [300.0, 1000.0, 3000.0]
## 目标横移速度（m/s）—— 用来量"瞬拉"。
const SIDE_VEL := 2000.0
## 半视场（垂直 fov 68° 换算；Godot 的 `fov` 是**垂直**角）。
const ASPECT_169 := 16.0 / 9.0
const ASPECT_1610 := 1600.0 / 1000.0
## 设计文档 §4.4 提的安全角系数与 `lk` 上限（**待用户拍板**，这里只用来算模拟量级）。
const SIM_SAFE_COEF := 0.62
const SIM_LK_MAX := 0.45


## 一台只带 `fm` 的哑机体：`ChaseCamera` 只用鸭子类型读 `target.get("fm")`，
## 所以不需要 `FlightBody`（也就不需要加载任何 glb ⇒ 无头下又快又干净）。
class DummyBody extends Node3D:
	var fm := FlightModel.new()


var _made: Array[Node] = []
var _cam: ChaseCamera
var _player: DummyBody
var _foe: DummyBody


func _ready() -> void:
	_build()
	_report()
	_cleanup()
	get_tree().quit(0)


func _build() -> void:
	_player = DummyBody.new()
	_player.name = "Player"
	add_child(_player)
	_player.global_position = Vector3(0.0, ALT, 0.0)
	_foe = DummyBody.new()
	_foe.name = "Foe"
	add_child(_foe)
	_cam = ChaseCamera.new()
	add_child(_cam)
	_cam.set_physics_process(false)   # 帧数完全由本探针决定
	_cam.current = false
	_cam.set_target(_player)
	_cam.aim_target = _foe
	_made = [_player, _foe, _cam]


func _cleanup() -> void:
	for n: Node in _made:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			n.queue_free()
	_made = []


func _half_h_fov(aspect: float) -> float:
	return rad_to_deg(atan(tan(deg_to_rad(_cam.base_fov * 0.5)) * aspect))


## 把敌机摆到"自机机头方向偏 `bearing` 度、距离 `dist`"处；`side_vel` 非 0 时给它一个
## **水平横向**速度（沿"绕机体上轴把机头转 90°"的方向）。
func _place(bearing: float, dist: float, side_vel: float) -> void:
	var yaw := deg_to_rad(bearing)
	var fwd := Vector3(sin(yaw), 0.0, -cos(yaw))       # 机体机头 -Z 绕 Y 转 bearing
	var side := Vector3(cos(yaw), 0.0, sin(yaw))       # 与 fwd 正交的水平方向
	_foe.global_position = _player.global_position + fwd * dist
	_foe.fm.velocity = side * side_vel
	_player.fm.velocity = Vector3.ZERO


## 按给定混合量算一次视轴，返回量到的角（度）。
## `pinned_pos` 非零时用**钉住的相机位置**（用来把"同框层改了后退距离"这一项剔除，
## 单独看视线点本身变没变）。
func _measure(lk: float, fr: float, pinned_pos := Vector3.ZERO) -> Dictionary:
	_cam._lock_blend = lk
	_cam._frame_blend = fr
	_cam._fpv_blend = 0.0
	# 相机位置先落到稳态（`_desired_position()` 是纯几何，不依赖历史）
	var pos := _cam._desired_position()
	if pinned_pos != Vector3.ZERO:
		pos = pinned_pos
	_cam.global_position = pos
	var b := _cam._desired_basis()
	_cam.global_transform = Transform3D(b, _cam.global_position)
	var dir := -b.z
	var to_player := _cam.global_position.direction_to(_player.global_position)
	var to_foe := _cam.global_position.direction_to(_foe.global_position)
	return {
		"player_off": rad_to_deg(dir.angle_to(to_player)),
		"target_off": rad_to_deg(dir.angle_to(to_foe)),
		"dir": dir,
		"cam_pos": _cam.global_position,
	}


## 真实步进：把 `step_now(dt)` 一帧一帧喂进去，量**切进锁定视角**那一下的摆动。
## 返回 `{max_frame, total, settle_frames, final_player_off, ok}`。
##
## ⚠️ 这是判据 4 的正口径 —— "瞬拉"是**混合量从 0 爬到 1 的过程**，
## 不是"两个静态姿态之间的差"（后者只是它的上界来源之一）。
func _engage(bearing: float, dist: float, frame_on: bool,
		frames := 120, dt := 1.0 / 60.0) -> Dictionary:
	_place(bearing, dist, 0.0)
	_cam.set_physics_process(false)
	_cam._fpv_blend = 0.0
	_cam._lock_blend = 0.0
	_cam.frame_both = frame_on
	# ⚠️ 必须走 `set_lock_view(true)` —— 它才是"_lock_blend 该往哪走"的开关。
	#    第一版只写了 `_lock_blend = 0.0` 却漏了这个开关 ⇒ `step_now()` 里
	#    `want_blend` 恒为 0 ⇒ 整段一动不动，单帧峰值读到 **0.000** 还以为是"绿了"。
	#    这正是 notes/09 那条："读数会在最后一次被驱动的值上定格，且看上去完全合法"。
	if not _cam.set_lock_view(true):
		return {"max_frame": -1.0, "total": -1.0, "settle_frames": -1,
			"final_player_off": -1.0, "ok": false}
	_cam._frame_blend = 1.0 if frame_on else 0.0
	_cam.global_position = _cam._desired_position()
	_cam.global_transform = Transform3D(_cam._desired_basis(), _cam.global_position)
	var first := -_cam.global_transform.basis.z
	var prev := first
	var mx := 0.0
	var settle := -1
	for i in frames:
		_cam.step_now(dt)
		var cur := -_cam.global_transform.basis.z
		mx = maxf(mx, rad_to_deg(prev.angle_to(cur)))
		if settle < 0 and _cam._lock_blend >= 0.999:
			settle = i + 1
		prev = cur
	return {
		"max_frame": mx,
		"total": rad_to_deg(first.angle_to(prev)),
		"settle_frames": settle,
		"final_player_off": _off_now(),
		"ok": true,
	}


## 自机相对**当前**（步进后的）视轴的偏角。
func _off_now() -> float:
	var dir := -_cam.global_transform.basis.z
	return rad_to_deg(dir.angle_to(
		_cam.global_position.direction_to(_player.global_position)))


## **[模拟]** 合成后的视线点（不含安全角）。`cap_lk` 为真时把 `lk` 封顶到 `SIM_LK_MAX`。
func _sim_lp(lk: float, fr: float, normalize: bool, cap_lk: bool) -> Vector3:
	var lk_eff: float = minf(lk, SIM_LK_MAX) if cap_lk else lk
	var mid := (_player.global_position + _foe.global_position) * 0.5
	var tgt := _foe.global_position + _foe.fm.velocity * 0.25
	if normalize and fr + lk_eff > 0.0:
		return (mid * fr + tgt * lk_eff) / (fr + lk_eff)
	return tgt


## **[模拟]** 三个杠杆**分开**量化（只为估算量级，不是产品读数）：
##   `normalize` = 把两层按权重归一（修 B）
##   `cap_lk`    = 辅助态下把 `lk` 封顶到 `SIM_LK_MAX`（修 B 的"更稳做法"）
##   `safety`    = 把视线点沿 (自机 → 视线点) 拉回，直到自机偏角 ≤ `safe_deg`（修 A）
## 返回自机相对视轴的偏角（度）。
##
## ⚠️ **必须分开量**：三个杠杆都"看起来像"能治自机出画，但它们的**作用机理完全不同** ——
## 不分开量就会得出"随便改哪个都行"的错误结论。实测（见日志）：
## 归一几乎不动自机偏角（中点与目标在同一方位射线上），真正把它压下去的是 `safety`。
func _sim(lk: float, fr: float, normalize: bool, cap_lk: bool,
		safety: bool, safe_deg: float) -> float:
	var look_point := _sim_lp(lk, fr, normalize, cap_lk)
	_cam._lock_blend = lk
	_cam._frame_blend = fr
	_cam._fpv_blend = 0.0
	var cam_pos := _cam._desired_position()
	var to_player := cam_pos.direction_to(_player.global_position)
	if not safety:
		return rad_to_deg(cam_pos.direction_to(look_point).angle_to(to_player))
	# 二分找"拉到多近"刚好落到安全角（软钳的等价实现）
	var lo := 0.0
	var hi := 1.0
	for _i in 40:
		var mid_t := (lo + hi) * 0.5
		var p: Vector3 = _player.global_position.lerp(look_point, mid_t)
		if rad_to_deg(cam_pos.direction_to(p).angle_to(to_player)) > safe_deg:
			hi = mid_t
		else:
			lo = mid_t
	return rad_to_deg(cam_pos.direction_to(
		_player.global_position.lerp(look_point, lo)).angle_to(to_player))


func _report() -> void:
	var h169 := _half_h_fov(ASPECT_169)
	var h1610 := _half_h_fov(ASPECT_1610)
	print("[cam] 垂直 fov = %.1f°  ⇒  半水平视场：16:9(1.778) = %.2f°   16:10(1.600) = %.2f°"
		% [_cam.base_fov, h169, h1610])
	print("[cam] offset=%s  look_ahead=%.1f  look_up=%.1f  LOCK_VIEW_PULLBACK=%.2f  LOCK_VIEW_RISE=%.1f  rotate_lag=%.1f"
		% [str(_cam.offset), _cam.look_ahead, _cam.look_up,
			ChaseCamera.LOCK_VIEW_PULLBACK, ChaseCamera.LOCK_VIEW_RISE, _cam.rotate_lag])
	print("[cam] 判定线：自机偏角 > %.2f° ⇒ 16:10 出画； > %.2f° ⇒ 16:9 出画" % [h1610, h169])

	# ---- ① 基线 + ② 同框层是否被吃掉 ----
	print("")
	print("=== ① 基线 + 三个杠杆分开量化（自机 / 敌机 相对视轴的偏角，度） ===")
	print("%5s %6s | %-15s | %-15s | %-33s"
		% ["方位", "距离", "只开锁定 lk=1 fr=0", "两个都开 lk=1 fr=1",
			"[模拟] 归一 / 归一+lk≤0.45 / 再加安全角"])
	print("%5s %6s | %7s %7s | %7s %7s | %8s %9s %10s"
		% ["(°)", "(m)", "自机", "敌机", "自机", "敌机", "只归一", "+lk上限", "+安全角"])
	print("-".repeat(104))
	var worst_both := 0.0
	var worst_lock := 0.0
	var worst_frame_only := 0.0
	var worst_sim_norm := 0.0
	var worst_sim_cap := 0.0
	var worst_sim_safe := 0.0
	var collapse_max := 0.0
	for d in DISTS:
		for b in BEARINGS:
			_place(b, d, 0.0)
			var lock_only := _measure(1.0, 0.0)
			var frame_only := _measure(0.0, 1.0)
			var both := _measure(1.0, 1.0)
			var safe_deg := h1610 * SIM_SAFE_COEF
			var s_norm := _sim(1.0, 1.0, true, false, false, safe_deg)
			var s_cap := _sim(1.0, 1.0, true, true, false, safe_deg)
			var s_safe := _sim(1.0, 1.0, true, true, true, safe_deg)
			# ⚠️ 证明"同框层被吃掉"必须**把相机位置钉住**：同框层还会把镜头后退 18%，
			#    不钉住的话量到的是"后退带来的角差"，而不是"视线点本身变没变"。
			var pinned: Vector3 = both["cam_pos"]
			var lock_pinned := _measure(1.0, 0.0, pinned)
			var coll := rad_to_deg(
				(both["dir"] as Vector3).angle_to(lock_pinned["dir"] as Vector3))
			collapse_max = maxf(collapse_max, coll)
			worst_both = maxf(worst_both, both["player_off"])
			worst_lock = maxf(worst_lock, lock_only["player_off"])
			worst_frame_only = maxf(worst_frame_only, frame_only["player_off"])
			worst_sim_norm = maxf(worst_sim_norm, s_norm)
			worst_sim_cap = maxf(worst_sim_cap, s_cap)
			worst_sim_safe = maxf(worst_sim_safe, s_safe)
			print("%5.0f %6.0f | %7.2f %7.2f | %7.2f %7.2f | %8.2f %9.2f %10.2f"
				% [b, d, lock_only["player_off"], lock_only["target_off"],
					both["player_off"], both["target_off"],
					s_norm, s_cap, s_safe])
	print("-".repeat(104))
	print("[cam] 【同框层是不是死代码】把相机位置钉住后，「两个都开」与「只开锁定」的"
		+ "视线方向最大差 = **%.6f°**" % collapse_max)
	if collapse_max < 1e-6:
		print("[cam] ⇒ **逐位相同 ⇒ 同框层是死代码**：后写的锁定层把 `look_point` 整段覆盖"
			+ "（设计文档 §4.3 证实）")
	print("[cam] 自机偏角**峰值**（判定线 %.2f°，超过即出画）：" % h1610)
	print("        只开锁定 %.2f° ｜ 只开同框 %.2f° ｜ 两个都开 %.2f°"
		% [worst_lock, worst_frame_only, worst_both])
	print("        [模拟] 只归一 %.2f° ｜ 归一+lk≤0.45 %.2f° ｜ 再加安全角 %.2f°"
		% [worst_sim_norm, worst_sim_cap, worst_sim_safe])

	# ---- ② 目标横移引起的视线跳变 ----
	print("")
	print("=== ② 瞬拉来源之一：目标横移 %.0f m/s 时视线点的**瞬时**转向 ===" % SIDE_VEL)
	print("%5s %6s | %8s %8s %8s | %10s %10s %10s"
		% ["方位", "距离", "现状", "只归一", "归一+上限", "现状Δ/帧", "归一Δ/帧", "上限Δ/帧"])
	print("-".repeat(84))
	var jerk_max := 0.0
	var jn_max := 0.0
	var jc_max := 0.0
	var legacy_only_max := 0.0
	for d in [1000.0, 3000.0]:
		for b in [30.0, 45.0, 55.0]:
			var frames := 60.0 / _cam.rotate_lag
			# 现状（= 两个都开的实际行为：锁定层把同框层覆盖掉）
			_place(b, d, 0.0)
			var a0 := _measure(1.0, 0.0)
			_place(b, d, SIDE_VEL)
			var a1 := _measure(1.0, 0.0)
			var dj := rad_to_deg((a0["dir"] as Vector3).angle_to(a1["dir"] as Vector3))
			# [模拟] 归一 / 归一+lk 上限
			_place(b, d, 0.0)
			var c0 := _cam._desired_position()
			var n0 := c0.direction_to(_sim_lp(1.0, 1.0, true, false))
			var k0 := c0.direction_to(_sim_lp(1.0, 1.0, true, true))
			_place(b, d, SIDE_VEL)
			var c1 := _cam._desired_position()
			var n1 := c1.direction_to(_sim_lp(1.0, 1.0, true, false))
			var k1 := c1.direction_to(_sim_lp(1.0, 1.0, true, true))
			var dn := rad_to_deg(n0.angle_to(n1))
			var dk := rad_to_deg(k0.angle_to(k1))
			legacy_only_max = maxf(legacy_only_max, a0["player_off"])
			jerk_max = maxf(jerk_max, dj)
			jn_max = maxf(jn_max, dn)
			jc_max = maxf(jc_max, dk)
			print("%5.0f %6.0f | %8.2f %8.2f %8.2f | %10.3f %10.3f %10.3f"
				% [b, d, dj, dn, dk, dj / frames, dn / frames, dk / frames])
	print("-".repeat(84))
	print("[cam] 瞬拉 Δ 峰值：现状 %.2f°（%.3f°/帧）｜ [模拟] 只归一 %.2f°（%.3f°/帧）"
		% [jerk_max, jerk_max / (60.0 / _cam.rotate_lag),
			jn_max, jn_max / (60.0 / _cam.rotate_lag)])
	print("        ｜ [模拟] 归一 + lk≤0.45 %.2f°（%.3f°/帧）"
		% [jc_max, jc_max / (60.0 / _cam.rotate_lag)])
	print("[cam] 判定线：单帧 ≤ 3.0° ⇒ 现状 **%s**"
		% ("红" if jerk_max / (60.0 / _cam.rotate_lag) > 3.0 else "绿"))

	# ---- ③ 进 / 出锁定视角那一瞬间的逐帧摆动（判据 4 的正口径）----
	print("")
	print("=== ③ 「瞬拉」正口径：真实步进 `step_now()`，量切进锁定视角的逐帧摆动 ===")
	print("%6s %7s %8s | %12s %12s %12s %10s" %
		["方位", "距离", "同框层", "单帧峰值(°)", "整段摆幅(°)", "自机终值(°)", "稳定帧"])
	print("-".repeat(76))
	var per_frame_worst := 0.0
	var per_frame_worst_lock := 0.0
	for d in [1000.0, 3000.0]:
		for b in [30.0, 45.0, 55.0]:
			for fo: bool in [false, true]:
				var r := _engage(b, d, fo)
				if not r["ok"]:
					print("  ❌ 无法进入锁定视角（%s）—— 读数无效" % r)
					continue
				per_frame_worst = maxf(per_frame_worst, r["max_frame"])
				if not fo:
					per_frame_worst_lock = maxf(per_frame_worst_lock, r["max_frame"])
				print("%6.0f %7.0f %8s | %12.3f %12.2f %12.2f %10d"
					% [b, d, ("开" if fo else "关"),
						r["max_frame"], r["total"], r["final_player_off"],
						r["settle_frames"]])
	print("-".repeat(76))
	print("[cam] 单帧峰值（只开锁定）= **%.3f°/帧**   （全部口径峰值 %.3f°/帧）"
		% [per_frame_worst_lock, per_frame_worst])
	print("[cam] 判定线：单帧 ≤ 3.0° ⇒ 当前 **%s**"
		% ("红" if per_frame_worst_lock > 3.0 else "绿"))
	print("[cam] done.")
