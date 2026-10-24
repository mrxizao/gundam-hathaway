extends Node
## 「变形过程」**真机活体**体检（2026-09-27 · 棒 0 `spec`）。
##
## ## 它补的是哪一道缺口
##
## 1. `xi_anim_probe.gd` 为了出图稳定，把 `FlightBody` 的每帧逻辑**停掉**了
##    （`set_physics_process(false)`），形态层全靠它手动 `set("morph", …)` 推 ——
##    而且它**还把 `AnimationPlayer` 冻住了**（`speed_scale = 0`）。
## 2. 单测 `suite_cruise_form` 验的是"形态层自己算得对"。
##
## 两头都绿，中间这条**唯一决定"玩家能不能在游戏里看见变形"**的通路是空的：
##
##     `_tick_effects()`（生产每帧函数）→ `_tick_cruise_morph()`
##       → 形态层 `.morph = cruise_morph` → `_process_modification()`
##         → 骨架姿态 → 蒙皮 → 屏幕
##
## ## 本探针的做法
##
##   * 驱动走**生产函数** `_tick_effects(dt)`（就是 `_physics_process()` 里那一步），
##     不写任何形态层内部字段；
##   * 机体**钉住位置与姿态**（空世界没海面，掉下去会 `destroy("撞海")` ⇒
##     `model_root.visible=false` ⇒ 读数/出图静默失效）；
##   * **两组对照**：`AnimationPlayer` 照播 vs 冻结 —— 这是分辨
##     "形态层没写进模型" 与 "写了但被动画每帧覆盖" 的唯一办法。
##
## 跑法：
##   ...console.exe --headless --path <工程> res://tools/xi_morph_live.tscn
##   ...console.exe --path <工程> res://tools/xi_morph_live.tscn -- --shots <目录>
##   （出图**必须带窗**，headless 是 dummy 渲染器）

## 主模型（自带 `fly`）。生产侧 `SuitProfile.xi().model_path` 就是它。
const PRIMARY := "res://assets/models/xi_movie/xi_movie_rigged.scn"

## ★ 2026-09-27（N42·十五）加了 `RearHang.L/R` —— 它们就是用户说的
## 「后翼下方**大片**翼」。此前它们不在形态表里（N36 清零遗留）⇒ 巡航时
## 一动不动，症状正是「大片翼没跟着上方的小翼一起展开」。
## 补回后形态骨 6 → 8 根，**本表针必须覆盖到**，否则这条回归没有读数能抓住。
const PROBE_BONES := ["BinderBack.L", "BinderFront.R", "Wing.L", "Wing.R",
	"RearHang.L", "RearHang.R"]
## 每档推多少个 dt（60 Hz）—— 0.45 s 的变形 = 27 帧走完。
const STEP_DT := 1.0 / 60.0
const STEPS := 36
## 出图时刻（帧序号）。
const SHOT_AT := [0, 6, 12, 18, 24, 30, 36]

## 出生高度：必须高于 `FlightBody.CRASH_ALTITUDE = 24 m`。
const SPAWN_Y := 400.0


## 姿态**快照器**：挂在同一骨架上、**排在形态层之后**的第二个 `SkeletonModifier3D`。
##
## ## 为什么需要它（2026-09-27 实测踩到）
##
## 本探针原本在 `await get_tree().process_frame` 之后读 `Skeleton3D` 的骨姿态，
## 想把「屏幕上是什么」读出来。**读不到**：
##
##   * `get_bone_global_pose()` ⇒ 覆盖不到（global 缓存的刷新在骨架自己的更新通道里）；
##   * `get_bone_pose_rotation()` ⇒ **也是 0.00**。实测 2026-09-27 之前的所有
##     `log_morph_live*.log` 六列**全 0**，与形态层是否生效无关。
##
## 根因是**帧序**：`AnimationPlayer` 每帧先把 `fly` 的姿态写进骨架，
## 形态层在骨架的更新通道里再改一次；而我们在 idle 帧的 `process_frame` 处恢复执行，
## 那一刻动画已经写过、修饰器**还没轮到**（或已在本帧之后）⇒ 读到的是动画原值。
##   `_process_modification()` 的 `calls` 与 `last_applied_deg` 是**层内部**读数，
##   它们一直是对的 —— 所以「层在写」与「我们读到 0」同时成立。**这就是静默故障的样子。**
##
## ⇒ 正解：不跟引擎抢帧序，而是**排进修饰器队列**。引擎按子节点序执行修饰器，
##   所以本节点（`add_child` 在形态层之后）读到的就是形态层**写完之后**的最终值。
class SnapshotMod extends SkeletonModifier3D:
	var bones: PackedInt32Array = PackedInt32Array()
	var names: PackedStringArray = PackedStringArray()
	## 骨名 → 本帧最终的**局部**姿态。
	var snap: Dictionary = {}
	var runs := 0

	func _process_modification() -> void:
		var skel := get_skeleton()
		if skel == null:
			return
		runs += 1
		for i in bones.size():
			snap[names[i]] = skel.get_bone_pose_rotation(bones[i])

var shots_dir := ""
var body: FlightBody
var _skel: Skeleton3D
var _idx: Dictionary = {}
var _mod: Object = null          # 当前生效的形态层（曲线层或两点层）
var _snap: SnapshotMod = null    # 排在形态层之后的姿态快照器（见类头）
var _gbase: Dictionary = {}      # 骨名 → morph=0 时的**局部**姿态（`get_bone_pose_rotation`）


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--shots" and i + 1 < args.size():
			shots_dir = str(args[i + 1])

	print("")
	print("########## 柯西「变形过程」真机活体体检 ##########")
	print("（驱动走生产函数 `_tick_effects()`；不写形态层任何内部字段）")
	_build_env()
	_build_body()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if body == null:
		print("!! 机体没建起来")
		print("VERDICT: XI-MORPH-LIVE-ABORTED")
		get_tree().quit(2)
		return

	# 每帧逻辑交给我们自己按 dt 推 —— 但推的是**生产函数**，不是平行实现。
	body.set_physics_process(false)
	await _check_form_layer()
	await _ramp("A) 照播 · morph 锁 0（对照）", false, 0.0)
	await _ramp("B) 照播 · morph 锁 1（对照）", false, 1.0)
	await _ramp("C) 冻结动画 · morph 0→1 走一遍", true, -1.0)

	Input.action_release("boost")
	if body != null and is_instance_valid(body):
		body.free()
	body = null
	_skel = null
	await get_tree().process_frame
	print("")
	print("VERDICT: XI-MORPH-LIVE-DONE")
	get_tree().quit(0)


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.63, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.85)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 132, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -60, 0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)


func _build_body() -> void:
	var p := SuitProfile.xi()
	p.model_path = PRIMARY
	var holder := Node3D.new()
	holder.name = "Holder"
	add_child(holder)
	body = FlightBody.new()
	body.name = "XiBody"
	body.profile = p
	body.is_player = true
	body.use_placeholder = false
	# 前倾角归零：18° 的飞行姿态会让"形态差分"混在整机姿态里读不出来。
	body.flight_pitch_deg = 0.0
	holder.add_child(body)
	body.display_name = p.display_name
	body.global_transform = Transform3D(Basis(), Vector3(0.0, SPAWN_Y, 0.0))
	print("[装配] %s ｜ model=%s" % [p.display_name, p.model_path])
	print("        cruise_morph=%s  cruise_morph_seconds=%.2f" % [str(p.cruise_morph),
		p.cruise_morph_seconds])
	print("        model_form_curve=%s" % p.model_form_curve)


func _check_form_layer() -> void:
	print("")
	print("========== ① 形态层档位（真机建体产物） ==========")
	var fc: Object = body.get("_form_curve")
	var cf: Object = body.get("_cruise_form")
	print("  `_form_curve`（曲线层） = %s" % ("有" if fc != null else "**无**"))
	print("  `_cruise_form`（两点层）= %s" % ("有" if cf != null else "无"))
	_mod = fc if fc != null else cf
	_skel = body.get("_model_skel") as Skeleton3D
	if _skel == null:
		print("  !! 没有骨架")
		return
	var ma: Object = body.get("model_anim")
	print("  动作表 `fly`=%s `burst_cruise`=%s" % [str(ma.call("has", "fly")),
		str(ma.call("has", "burst_cruise"))])
	var normal: Dictionary = ma.call("rotations_at", str(ma.get("idle_action")), 0.0)
	var cruise: Dictionary = ma.call("rotations_at", str(ma.get("burst_cruise_action")))
	for nm: String in PROBE_BONES:
		var bi := _skel.find_bone(nm)
		_idx[nm] = bi
		print("     表针骨 %-14s idx=%d ｜ 常态↔巡航 %6.2f°" % [nm, bi,
			rad_to_deg((normal.get(nm, Quaternion.IDENTITY) as Quaternion)
				.angle_to(cruise.get(nm, Quaternion.IDENTITY)))])
	# 快照器**最后**加 ⇒ 引擎按子节点序执行修饰器 ⇒ 它读到形态层写完之后的值。
	_snap = SnapshotMod.new()
	_snap.name = "SnapshotMod"
	for nm2: String in PROBE_BONES:
		_snap.names.append(nm2)
		_snap.bones.append(_idx[nm2])
	_skel.add_child(_snap)
	print("     姿态快照器已挂在形态层之后（reads = 形态层的**最终**写入值）")


## 一档：把 `fm.boosting` 按"玩家按住 Shift"设为 true，按 dt 推生产函数。
##
## ⚠️ 用 `fm.boosting = true` 而不是按输入键：`PlayerController` 在**平移模式**
## （辅助开）下把加力意愿恒置 true，在手动模式下才读 Shift —— 这里要验的是
## 形态层这条链，不是输入路由（那条由既有测试覆盖）。两种模式都会把
## `fm.boosting` 置 true，所以这是**生产会出现的取值**。
func _ramp(title: String, freeze_anim: bool, lock_morph: float) -> void:
	print("")
	print("========== %s ==========" % title)
	var ap: Object = body.get("model_anim").get("player")
	if ap != null:
		if freeze_anim:
			# 冻之前先**归位到 `fly` 首帧**：否则冻的是"上一组跑到哪就停在哪"，
			# 后面的 morph=0 基准就不是常态（探针当年也这么干）。
			ap.call("play", "fly")
			ap.call("seek", 0.0, true)
			ap.set("speed_scale", 0.0)
		else:
			ap.call("play", "fly")
			ap.call("seek", 0.0, true)
			ap.set("speed_scale", 1.0)
		print("  `AnimationPlayer.speed_scale = %.1f` ｜ morph 锁 = %s"
			% [float(ap.get("speed_scale")),
			   "不锁（走生产推进）" if lock_morph < 0.0 else "%.2f" % lock_morph])
	var fm: Object = body.get("fm")
	fm.set("boosting", true)
	body.set("cruise_morph", 0.0)
	_mod.set("morph", 0.0)
	body.global_transform = Transform3D(Basis(), Vector3(0.0, SPAWN_Y, 0.0))
	await get_tree().process_frame
	_capture_gbase()

	var cam: Camera3D = null
	var tail: Camera3D = null
	if shots_dir != "":
		if cam == null:
			cam = _build_camera()
		if tail == null:
			tail = _build_tail_camera()

	print("  帧    t(s)  cruise_morph  层morph  层读回°  层写入°  层调用  %s" % _hdr())
	var tag := ("frozen" if freeze_anim else "live") \
		+ ("" if lock_morph < 0.0 else "_lock%.0f" % lock_morph)
	for i in STEPS + 1:
		if i % 6 == 0 or i == STEPS:
			_report(i)
		if shots_dir != "" and i in SHOT_AT:
			await _shot(cam, tail, tag, i)
		body._tick_effects(STEP_DT)
		if lock_morph >= 0.0:
			# **只在调用之后**改写：`_tick_effects()` 是生产函数、照常跑完，
			# 我们只把它推出来的 morph 换成定值 ⇒ 两组除了 morph 完全同条件。
			body.set("cruise_morph", lock_morph)
			_mod.set("morph", lock_morph)
		body.global_transform = Transform3D(Basis(), Vector3(0.0, SPAWN_Y, 0.0))
		await get_tree().process_frame
	ap.set("speed_scale", 1.0)


func _hdr() -> String:
	var s := ""
	for nm: String in PROBE_BONES:
		s += "%-20s" % (nm + "(离基准°)")
	return s


func _report(i: int) -> void:
	if body == null or not is_instance_valid(body):
		print("  %3d  （机体已不在了）" % i)
		return
	var line := "  %3d  %6.3f  %10.4f  %7.4f  %8.4f  %8.4f  %6s  " % [
		i, i * STEP_DT, float(body.get("cruise_morph")),
		float(_mod.get("morph")),
		float(_mod.get("read_residual_deg")),
		float(_mod.get("last_applied_deg")),
		str(_mod.get("calls"))]
	for nm: String in PROBE_BONES:
		line += "%-20s" % _live_global_deg(nm)
	print(line)


func _capture_gbase() -> void:
	_gbase.clear()
	if _snap == null or _snap.snap.is_empty():
		# ★ 不许静默：读数来源没起来就必须喊出来（这列以前正是"恒 0 却不报错"的坑）。
		print("  !! 姿态快照器没有产出（runs=%d）⇒ 基准抓不到，「离基准°」会全为 '-'"
			% (0 if _snap == null else _snap.runs))
		return
	for nm: String in PROBE_BONES:
		if _snap.snap.has(nm):
			_gbase[nm] = _snap.snap[nm]


## 该骨离基准多少度。
##
## 取值口径 = **快照器在本帧修饰器队列末尾读到的局部姿态**（见 `SnapshotMod` 类头）——
## 也就是形态层写完之后、蒙皮真正会用的那一份局部姿态，与 `_capture_gbase()` 同源同口径。
##
## ⚠️ 2026-09-27 修正一处**恒零判据**：原先在 `process_frame` 之后直接读骨架，
## 读到的是 `AnimationPlayer` 的原值（形态层的写入还没轮到），
## 于是六列**永远 0.00**、与形态层是否生效无关 —— 而"全 0"和"一切正常"长得一模一样。
func _live_global_deg(nm: String) -> String:
	if _snap == null or not _gbase.has(nm):
		return "-"
	if not _snap.snap.has(nm):
		return "-"
	var cur: Quaternion = _snap.snap[nm]
	return "%.2f" % rad_to_deg(cur.angle_to(_gbase[nm]))


# ------------------------------------------------------------ 出图

func _shot(cam: Camera3D, tail: Camera3D, tag: String, i: int) -> void:
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var morph := float(body.get("cruise_morph"))
	for pr in [[cam, "full"], [tail, "tail"]]:
		var c: Camera3D = pr[0]
		if c == null:
			continue
		c.current = true
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			continue
		var out := "%s/%s_%s_f%02d_m%.2f.png" % [shots_dir, tag, str(pr[1]), i, morph]
		img.save_png(out)
		print("    saved %s" % out.get_file())


func _build_camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)
	var b: AABB = body.model_bounds
	var focus: Vector3 = body.global_transform * b.get_center()
	var radius := maxf(b.size.length() * 1.05, 1.0)
	var a := deg_to_rad(200.0)
	cam.global_position = focus + Vector3(sin(a) * radius, b.size.y * 0.30, cos(a) * radius)
	cam.look_at(focus, Vector3.UP)
	cam.current = true
	print("  [取景] size=%s center=%s radius=%.3f" % [str(b.size), str(b.get_center()), radius])
	return cam


func _build_tail_camera() -> Camera3D:
	var c := Camera3D.new()
	c.fov = 34.0
	c.near = 0.05
	c.far = 4000.0
	add_child(c)
	var b: AABB = body.model_bounds
	var focus: Vector3 = body.global_transform * (b.get_center() + Vector3(0.0, b.size.y * 0.20, 0.0))
	var radius := maxf(b.size.length() * 0.50, 1.0)
	c.global_position = focus + Vector3(0.0, b.size.y * 0.08, radius)
	c.look_at(focus, Vector3.UP)
	return c
