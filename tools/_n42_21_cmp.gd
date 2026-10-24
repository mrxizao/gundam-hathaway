extends Node3D
## N42·二十一 实机判决：**方案 B（`form_on` → `cruise_idle`）到底在屏幕上生效了没有**。
##
## ## 与 `_n42_20_cmp.gd` 的关系（为什么不能复用）
##
## N42·二十那版把形态**直接手推到 `cruise_morph = 1`**，测的是**形态层**
## （`SkeletonModifier3D`）那条通路 —— 判决结果是"写不进渲染"。
##
## 本轮改成走**动作**：`ModelAnimFSM` 在 `cruise_morph ≥ 0.5` 时进 `FORM` 态、
## 播一次 `form_on`（0.4333 s），播完落 `cruise_idle` 循环。
## ⇒ 探针必须**照游戏的驱动方式驱动状态机**（`_tick_cruise_morph` + `_tick_model_anim`），
## 自己手推 `cruise_morph` 会**绕过 `FORM` 态**，等于没测。
##
## ## 判据（本轮新增/沿用）
##
##   **P2（屏幕）** 巡航/常态的**非背景轮廓包围盒** 宽×? 高×? —— 必须显著 ≠ 1.000 ± 0.02
##                （N42·二十的失败态：宽 ×1.000 / 高 ×0.975；参照 `柯西巡航2.0` 是 ×1.083 / ×1.863）
##   **P3（通路）** 骨架上的**实际 pose** vs `cruise_idle` 资产里的关键帧值 —— 必须一致
##                （⊂「骨变 ⇒ 屏幕必变」；`get_bone_pose_rotation()` 是动画真写进 Skeleton 的读数）
##   **P5（时序）** 三档状态名/动作名/进度：`idle/fly` → `form/form_on` → `idle/cruise_idle`
##                ⇒ 证明过渡动作真的被播了，而不是被 `BLEND_FORM` 交叉淡入糊过去
##
## ## 跑法（**必须带窗**；headless 是 dummy 渲染器，出不来图）
##
##   godot --path <工程> res://tools/_n42_21_cmp.tscn -- --out <目录>
##
## ## 三个静默失败陷阱（都踩过，注释在对应位置）
##
##   ① 出生点必须是 `Vector3(0, SPAWN_Y, 0)` —— 写成 `(0,0,SPAWN_Y)` 会让 y=0
##      ⇒ 撞海 ⇒ `model_root.visible=false` ⇒ **出图全空且不报错**。
##   ② 轮廓判据不能用 `model_bounds`（那是 rest 包围盒，形态变它**不变**）
##      ⇒ 只能量**屏幕像素**。
##   ③ `AnimationPlayer` 停住时不求值 ⇒ 探针必须让它**真的在播**，
##      否则测的不是游戏行为。

## 参照在工程之外 ⇒ 用 GLTFDocument 读绝对路径。
const REF_DIR := "C:/Users/MSIPC/Desktop/游戏/闪哈游戏/柯西与佩涅罗佩/柯西模型/"
const REF_CRUISE := REF_DIR + "柯西巡航2.0.glb"
const REF_NORMAL := REF_DIR + "柯西常态2.0.glb"
## 参照相对主模型的朝向修正（N42·十四 实测 −90°）。
const REF_YAW_DEG := -90.0
const MAIN_PATH := "res://assets/models/xi_movie/xi_movie_rigged.scn"

## 出生高度：必须高于 `FlightBody.CRASH_ALTITUDE`（24 m）。
const SPAWN_Y := 400.0

## 量「骨到底转没转」用这几根（与 `xi_morph_live.gd` / `_n42_20_cmp.gd` 同批 ⇒ 可跨轮比对）。
const PROBE_BONES := ["BinderBack.L", "BinderFront.R", "Wing.L", "Wing.R",
	"RearHang.L", "RearHang.R"]

## ★★ 本轮的**头号嫌疑**：身体骨。
##
## `xi_cruise_idle.glb` 在 Godot 里只有 **19 条旋转轨道**（导入器把「整段恒定 = rest」的
## 32 条丢了；源 glb 有 51 条 —— `_relay/probe_glb_channels.py` 实测）。
## 而 `AnimationPlayer` 换动作时，**新动作没有轨道的属性保持上一动作的值**。
##
## ⇒ 若 `form_on` 也没能把这 18 根身体骨落到 rest，它们就会**停在 `fly` 的飞行姿势**上
##   ⇒ 屏幕上「翼展开了、机体还是趴着飞」= 用户报的「你还是没改」。
const BODY_BONES := ["Hips", "Spine", "Chest", "Neck", "Head",
	"Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R",
	"LowerArm.L", "LowerArm.R", "Hand.L", "Hand.R",
	"Thigh.L", "Thigh.R", "Shin.L", "Shin.R", "Foot.L", "Foot.R"]

## 视角：[名, 方位角°, 仰角°, 距离系数]（与 `_ref_shots.gd` / `_n42_20_cmp.gd` 同表）。
const VIEWS := [
	["top", 0.0, 89.0, 0.95],
	["side", 200.0, 6.0, 1.05],
]

## 驱动步长。**固定值**（不取真实帧间隔）⇒ 三档时刻可复现。
const DT := 1.0 / 60.0

## 逐帧轨迹（`--trace`）。用来判**两个方向**的过程感，以及「无轨道的骨什么时候被写」。
var _trace := false

## 轨迹里跟踪的骨（一根身体骨 + 一根翼骨 ⇒ 能同时看身体与形态）。
const TRACE_BONES := ["Hips", "Spine", "UpperArm.R", "Shin.L", "Wing.L", "RearHang.L"]

## 降采样宽度（轮廓扫描用；2560×1600 逐像素在 GDScript 里太慢）。
const DW := 640

var out_dir := ""
var body: FlightBody = null
var _cam: Camera3D = null
var _focus := Vector3.ZERO
var _radius := 1.0
## 各档的轮廓包围盒：tag → Vector2i(w, h)
var _sil := {}


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = a[i + 1]
		if a[i] == "--trace":
			_trace = true
	if out_dir == "":
		print("!! 需要 --out <目录>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir.replace("\\", "/"))
	var win := get_window()
	if win != null:
		win.size = Vector2i(1600, 1000)

	print("")
	print("########## N42·二十一 实机判决：form_on → cruise_idle（方案 B）##########")
	_build_env()

	# ---- ① 相机由**参照件**包围盒一次定死，所有图共用 ----
	var ref := _load_glb(REF_CRUISE)
	if ref == null:
		print("!! 参照加载失败 ⇒ 停手（相机定不下来）")
		print("VERDICT: N42-21-ABORTED")
		get_tree().quit(2)
		return
	ref.rotation.y = deg_to_rad(REF_YAW_DEG)
	add_child(ref)
	await get_tree().process_frame
	await get_tree().process_frame
	var b := _bbox(ref)
	_focus = b.get_center()
	_radius = maxf(b.size.length() * 0.5, 0.5)
	print("  [相机基准] 参照 bounds center=%s size=%s radius=%.3f"
		% [str(_focus), str(b.size), _radius])
	await _shoot("ref_cruise", ref)
	remove_child(ref)
	ref.queue_free()

	var rn := _load_glb(REF_NORMAL)
	if rn != null:
		rn.rotation.y = deg_to_rad(REF_YAW_DEG)
		add_child(rn)
		await get_tree().process_frame
		await get_tree().process_frame
		await _shoot("ref_normal", rn)
		remove_child(rn)
		rn.queue_free()

	# ---- ② 游戏内（生产侧 `SuitProfile.xi()`）----
	await _build_body()
	if body == null:
		print("!! 机体没建起来")
		print("VERDICT: N42-21-ABORTED")
		get_tree().quit(3)
		return

	# ---- ③ 六档:常态 / 过渡中段 / 巡航 / 巡航 + 1 s（循环）/ 回程中段 / 回到常态 ----
	await _shoot_game("game_normal")
	await _drive(12)                       # 0.20 s：`cruise_morph` 已到 ~0.44，尚未过 0.5
	await _shoot_game("game_before_form")
	await _drive(6)                        # 再 0.10 s：`cruise_morph` 过 0.5 ⇒ 进 FORM 态
	await _shoot_game("game_form_mid")
	await _drive_until_action("cruise_idle", 600)   # 等 `form_on` 播完、落 `cruise_idle`
	await _shoot_game("game_cruise")
	await _drive(60)                       # 再 1.0 s：证 `cruise_idle` 真在循环（进度回绕）
	await _shoot_game("game_cruise_loop")
	# ★★ 回程：松开 Shift。**用户 2026-09-27 反馈「切回正常飞行时动画生硬」** ——
	#    这一档把回程的过程逐帧录下来，作为「生硬」的定性与定量证据；
	#    N42·二十二 补了 `form_off` 之后重跑，这里应当变成**逐帧平滑**。
	print("")
	print("  ---- 回程（松开 Shift：巡航 → 常态）----")
	await _drive(20, false)                # 0.33 s：应正处在 `form_off` 中段
	await _shoot_game("game_back_mid")
	await _drive_until_action("fly", 600, false)
	await _shoot_game("game_back_normal")

	# ---- ④ 判据汇总 ----
	_report()

	if body != null and is_instance_valid(body):
		body.free()
	body = null
	await get_tree().process_frame
	print("")
	print("VERDICT: N42-21-DONE")
	get_tree().quit(0)


## ------------------------------ 环境 / 装配 ------------------------------

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
	p.model_path = MAIN_PATH
	var holder := Node3D.new()
	holder.name = "Holder"
	add_child(holder)
	body = FlightBody.new()
	body.name = "XiBody"
	body.profile = p
	body.is_player = true
	body.use_placeholder = false
	body.flight_pitch_deg = 0.0
	holder.add_child(body)
	body.display_name = p.display_name
	# ★ 陷阱①：出生点必须**高于** `CRASH_ALTITUDE`。
	body.global_transform = Transform3D(Basis(), Vector3(0.0, SPAWN_Y, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	body.set_physics_process(false)
	print("  [装配] %s ｜ model=%s" % [p.display_name, p.model_path])
	print("         profile: idle=%s burst=%s burst_cruise=%s idle_cruise=%s form_on=%s form_off=%s"
		% [p.model_anim_idle, p.model_anim_burst, p.model_anim_burst_cruise,
		   p.model_anim_idle_cruise, p.model_anim_form_on, p.model_anim_form_off])
	var ma: Object = body.get("model_anim")
	var fsm: Object = body.get("model_fsm")
	if ma != null:
		var lst: Array = ma.call("action_names")
		print("         动作表(%d)：%s" % [lst.size(), str(lst)])
		print("         ★ 挂上了吗：cruise_idle=%s  form_on=%s  form_off=%s  fly=%s"
			% [str(ma.call("has", "cruise_idle")), str(ma.call("has", "form_on")),
			   str(ma.call("has", "form_off")), str(ma.call("has", "fly"))])
		var a_c: Animation = ma.get("player").call("get_animation", "cruise_idle")
		var a_f: Animation = ma.get("player").call("get_animation", "form_on")
		# ⚠️ Godot 的 `Animation.LoopMode`：**0=NONE / 1=LINEAR / 2=PINGPONG**。
		#    上一版注释把 2 写成 LINEAR（错），看日志会误判成"没设上"。
		print("         ★ loop_mode：cruise_idle=%d（要 1=LINEAR）  form_on=%d（0=NONE）"
			% [a_c.loop_mode if a_c != null else -1, a_f.loop_mode if a_f != null else -1])
		print("         ★ 时长：cruise_idle=%.4f s  form_on=%.4f s  form_off=%.4f s  fly=%.4f s"
			% [a_c.length if a_c != null else -1.0, a_f.length if a_f != null else -1.0,
			   _anim_len(ma, "form_off"), _anim_len(ma, "fly")])
	if fsm != null:
		print("         状态机：state=%s form=%s action=%s"
			% [fsm.call("state_name"), fsm.call("form_name"), fsm.call("current_action")])
	# ★ 形态层应当**早退**（`_setup_cruise_form()` 第 4 道判据）⇒ 两个字段都该是 null。
	print("         ★ 形态层让位：`_form_curve`=%s  `_cruise_form`=%s（都该是「无」）"
		% ["有" if body.get("_form_curve") != null else "无",
		   "有" if body.get("_cruise_form") != null else "无"])


## ------------------------------ 驱动 ------------------------------

## 照游戏的驱动方式推 `n` 步：先算形态进度，再推状态机。
##
## `boost` = 是否按住 Shift（`fm.boosting`）。**去程与回程靠它区分**。
func _drive(n: int, boost := true) -> void:
	if body == null or not is_instance_valid(body):
		return
	var fm: Object = body.get("fm")
	if fm != null:
		fm.set("boosting", boost)
		fm.set("hovering", false)
	for i in n:
		body.call("_tick_cruise_morph", DT)
		body.call("_tick_model_anim", DT)
		await get_tree().process_frame
		_trace_line("drive%d" % n, i + 1, boost)


## 一直推到状态机回到 IDLE 且拿到目标动作（或到 `limit` 步）。
##
## ⚠️ 本函数传的 `DT` 只喂给 `MIN_BURST_HOLD`；**`AnimationPlayer` 走的是真实帧间隔**。
## 所以这里同时记**墙钟时间** —— 若它明显大于动作时长而步数却很少，
## 说明探针每步比 1/60 s 慢（渲染卡），别误读成"过渡动作被跳过了"。
func _drive_until_action(want: String, limit: int, boost := true) -> void:
	if body == null or not is_instance_valid(body):
		return
	var fm: Object = body.get("fm")
	if fm != null:
		fm.set("boosting", boost)
		fm.set("hovering", false)
	var t0 := Time.get_ticks_msec()
	for i in limit:
		body.call("_tick_cruise_morph", DT)
		body.call("_tick_model_anim", DT)
		await get_tree().process_frame
		_trace_line("wait:" + want, i + 1, boost)
		var fsm: Object = body.get("model_fsm")
		if fsm == null:
			return
		if str(fsm.call("state_name")) == "idle" \
				and str(fsm.call("current_action")) == want:
			var ms := Time.get_ticks_msec() - t0
			print("      [等到了] %s：第 %d 步 ｜ 模拟时间 %.3f s ｜ **墙钟 %.3f s**"
				% [want, i + 1, float(i + 1) * DT, float(ms) / 1000.0])
			return
	print("      !! %d 步内没落到 `%s`" % [limit, want])


## 逐帧轨迹：状态 / 动作 / 动作进度 / 几根骨的局部旋转角（度，双覆盖已归一）。
func _trace_line(phase: String, step: int, boost: bool) -> void:
	if not _trace or body == null or not is_instance_valid(body):
		return
	var fsm: Object = body.get("model_fsm")
	var ma: Object = body.get("model_anim")
	var sk: Skeleton3D = body.get("_model_skel")
	if fsm == null or ma == null or sk == null:
		return
	var s := "    [trace %-12s %3d] boost=%d morph=%.3f state=%-4s act=%-10s prog=%.3f ｜" % [
		phase, step, 1 if boost else 0, float(body.get("cruise_morph")),
		str(fsm.call("state_name")), str(fsm.call("current_action")),
		float(ma.call("progress"))]
	for bn in TRACE_BONES:
		var bi := sk.find_bone(bn)
		if bi < 0:
			continue
		var q: Quaternion = sk.get_bone_pose_rotation(bi)
		var deg := rad_to_deg(2.0 * acos(clampf(absf(q.w), 0.0, 1.0)))
		s += " %s=%.1f" % [bn, deg]
	print(s)


## ------------------------------ 出图 + 读数 ------------------------------

func _shoot_game(tag: String) -> void:
	if body == null or not is_instance_valid(body):
		return
	body.global_transform = Transform3D(Basis(), Vector3(0.0, SPAWN_Y, 0.0))
	await get_tree().process_frame
	await get_tree().process_frame
	var fsm: Object = body.get("model_fsm")
	var ma: Object = body.get("model_anim")
	print("")
	print("  [%s] cruise_morph=%.3f ｜ 状态机 state=%s action=%s progress=%.3f"
		% [tag, float(body.get("cruise_morph")),
		   str(fsm.call("state_name")) if fsm != null else "-",
		   str(fsm.call("current_action")) if fsm != null else "-",
		   float(ma.call("progress")) if ma != null else -1.0])
	if fsm != null:
		print("      history(last 6)=%s" % str(fsm.call("history").slice(-6)))
	# ★ P3：骨上**实际生效**的 pose vs 资产里的关键帧值（含"没轨道的骨该不该是 rest"）。
	_pose_check_full(tag)
	var sk: Skeleton3D = body.get("_model_skel")
	if sk != null:
		var line := "      全局basis.y（朝向）："
		for nm in PROBE_BONES:
			var bi := sk.find_bone(nm)
			if bi < 0:
				continue
			var tf: Transform3D = sk.get_bone_global_pose(bi)
			line += " %s=(%.3f,%.3f,%.3f)" % [nm, tf.basis.y.x, tf.basis.y.y, tf.basis.y.z]
		print(line)
	await _shoot(tag, body)


## P3：把骨上实际 pose 与「该动作在 t=0 的关键帧值」逐骨比，报最大夹角（度）。
##
## ## 为什么这是**通路**判据而不是几何判据
##
## `SkeletonModifier3D` 那条路的失败特征就是「局部角算对了、屏幕不动」——
## 所以「算对」不构成证据。而 `get_bone_pose_rotation()` 是**动画真的写进
## `Skeleton3D` 的 pose**（`AnimationPlayer` 每帧求值的落点）。
## 它若与资产关键帧值一致 ⇒ 值确实到了骨上 ⇒ 屏幕再不动就只能是更下游的问题。
##
## ## ★★ 本轮新增：**没有轨道的骨**也要判
##
## `cruise_idle` 在 Godot 里只有 19 条旋转轨道（源 glb 有 51 条，导入器丢了 32 条
## 「整段恒定 = rest」的）。这些骨**不在动作里**，所以它们要么被正确归位（rest）、
## 要么**停在上一段动作的姿势上**（`AnimationPlayer` 的经典行为）。
##
## 判据：
##   * **有轨道**的骨 → 与资产值比，差应为 0（通路有效）；
##   * **无轨道**的骨 → 实际 pose 应 ≈ rest；不 ≈ rest 的列出来，并给出
##     「与 `fly` 差多少度」——若差值 ≈ 0 ⇒ **它卡在 `fly` 上**（这就是缺陷）。
func _pose_check_full(tag: String) -> void:
	var ma: Object = body.get("model_anim")
	var sk: Skeleton3D = body.get("_model_skel")
	if ma == null or sk == null:
		return
	var nm := str(ma.get("current"))
	if nm == "":
		print("      [pose/P3] %s：没在播动作 ⇒ 跳过" % tag)
		return
	var want: Dictionary = ma.call("rotations_at", nm, 0.0)
	var flyw: Dictionary = ma.call("rotations_at", "fly", 0.0)
	var max_track := 0.0
	var worst_track := ""
	var n_track := 0
	var stuck: Array = []
	var body_stuck: Array = []
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		var q: Quaternion = sk.get_bone_pose_rotation(i)
		# 四元数**双覆盖**：`q` 与 `−q` 是同一个旋转 ⇒ 用 `|w|` 算角（区间 0..180°）。
		# ⚠️ 直接 `q.get_angle()` 在 `w < 0` 时会给 360−θ，看起来像"转了 236°"。
		var deg := rad_to_deg(2.0 * acos(clampf(absf(q.w), 0.0, 1.0)))
		if want.has(bn):
			n_track += 1
			var wq: Quaternion = want[bn]
			var d := rad_to_deg(2.0 * acos(clampf(absf(q.dot(wq)), 0.0, 1.0)))
			if d > max_track:
				max_track = d
				worst_track = bn
			continue
		if deg > 0.01:
			var ex := ""
			if flyw.has(bn):
				var fq: Quaternion = flyw[bn]
				var fd := rad_to_deg(2.0 * acos(clampf(absf(q.dot(fq)), 0.0, 1.0)))
				ex = "（与 fly 差 %.2f°%s）" % [fd, " ← 卡在 fly" if fd < 1.0 else ""]
			stuck.append("%s=%.2f°%s" % [bn, deg, ex])
			if BODY_BONES.has(bn):
				body_stuck.append(bn)
	print("      [pose/P3] 动作=%s ｜ 有轨道 %d 骨，与资产最大夹角 %.4f° (%s)"
		% [nm, n_track, max_track, worst_track])
	if stuck.is_empty():
		print("                无轨道的骨 **全部在 rest** ✓（共 %d 根）"
			% (sk.get_bone_count() - n_track))
	else:
		print("                ★★ 无轨道却非 rest 的骨 %d 根：%s"
			% [stuck.size(), ", ".join(PackedStringArray(stuck))])
		print("                  其中**身体骨** %d 根：%s"
			% [body_stuck.size(), ", ".join(PackedStringArray(body_stuck))])


func _anim_len(ma: Object, nm: String) -> float:
	if ma == null:
		return -1.0
	var a: Animation = ma.get("player").call("get_animation", nm)
	return a.length if a != null else -1.0


func _load_glb(path: String) -> Node3D:
	if path.begins_with("res://"):
		var ps := load(path) as PackedScene
		if ps == null:
			return null
		return ps.instantiate() as Node3D
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		print("!! GLTFDocument 读失败 err=%d %s" % [err, path])
		return null
	return doc.generate_scene(st) as Node3D


func _bbox(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var bb := Transform3D(mi.global_transform.basis, mi.global_transform.origin) * mi.get_aabb()
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	return out


## 出图 + **当场**量轮廓（不落盘再读，省一轮往返）。
func _shoot(tag: String, root: Node3D) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 34.0
		_cam.near = 0.05
		_cam.far = 5000.0
		add_child(_cam)
	# ★ 取景各按自身包围盒归一（参照与机体各自归一）——不作"同世界坐标"假设。
	#   ⚠️ 但**同一 tag 系列内**（`game_*`）用的是同一个 `model_bounds`
	#   = **rest 包围盒**（形态变化它不变）⇒ 相机逐位相同 ⇒ 轮廓比可比。
	var c := _focus
	var r := _radius
	if root is FlightBody:
		var mb: AABB = (root as FlightBody).model_bounds
		c = root.global_transform * mb.get_center()
		r = maxf(mb.size.length() * 0.5, 0.5)
	for v in VIEWS:
		var name := str(v[0])
		var az := deg_to_rad(float(v[1]))
		var el := deg_to_rad(float(v[2]))
		var k := float(v[3])
		var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
		_cam.global_position = c + dir * r * 2.6 * k
		_cam.look_at(c, Vector3.UP)
		_cam.current = true
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			print("    !! %s_%s 取不到图" % [tag, name])
			continue
		var p: String = out_dir.path_join("%s_%s.png" % [tag, name])
		img.save_png(p)
		var box := _silhouette(img)
		_sil["%s_%s" % [tag, name]] = box
		print("    saved %-30s ｜ 轮廓 w=%4d h=%4d ｜ 宽/高 %.4f"
			% [p.get_file(), box.x, box.y, float(box.x) / float(maxi(box.y, 1))])


## 非背景轮廓包围盒。背景色取 (2,2) 处像素（环境是纯色 `BG_COLOR`）。
func _silhouette(img: Image) -> Vector2i:
	var h := int(round(float(img.get_height()) * DW / float(img.get_width())))
	img.resize(DW, h, Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var bg := img.get_pixel(2, 2)
	var x0 := DW
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in DW:
			var c := img.get_pixel(x, y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.06:
				if x < x0: x0 = x
				if y < y0: y0 = y
				if x > x1: x1 = x
				if y > y1: y1 = y
	if x1 < 0:
		return Vector2i(0, 0)
	return Vector2i(x1 - x0 + 1, y1 - y0 + 1)


## ------------------------------ 判据汇总 ------------------------------

func _report() -> void:
	print("")
	print("################ 判据汇总 ################")
	print("  P2 屏幕轮廓（同相机一对一比）")
	var pairs := [
		["game_normal", "game_cruise"],
		["game_normal", "game_cruise_loop"],
		["game_before_form", "game_cruise"],
		["game_cruise", "game_back_normal"],
		["ref_normal", "ref_cruise"],
	]
	var p2_ok := false
	for pr in pairs:
		var a1: String = str(pr[0]) + "_top"
		var b1: String = str(pr[1]) + "_top"
		if not (_sil.has(a1) and _sil.has(b1)):
			continue
		var va: Vector2i = _sil[a1]
		var vb: Vector2i = _sil[b1]
		var rw := float(vb.x) / float(maxi(va.x, 1))
		var rh := float(vb.y) / float(maxi(va.y, 1))
		var tag := ""
		if str(pr[0]) == "game_normal" and str(pr[1]) == "game_cruise":
			tag = "  ← ★ P2 主判据"
			if maxf(absf(rw - 1.0), absf(rh - 1.0)) > 0.02:
				p2_ok = true
		print("    %-22s→%-22s 宽 ×%.3f  高 ×%.3f%s"
			% [str(pr[0]), str(pr[1]), rw, rh, tag])
	print("")
	print("  P2 VERDICT：%s" % ("PASS（轮廓显著变化）" if p2_ok
		else "FAIL（轮廓仍 ≈ 1.000 ⇒ 屏幕没变）"))
	print("  （N42·二十 失败态 = 宽 ×1.000 / 高 ×0.975；参照 = 宽 ×1.083 / 高 ×1.863）")
	print("################ 判据汇总结束 ################")
