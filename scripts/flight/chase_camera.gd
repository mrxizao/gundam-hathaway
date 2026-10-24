class_name ChaseCamera
extends Camera3D
## Ace Combat 式追尾镜头。
##
## 三个关键处理：
##   1. **位置滞后**（指数平滑）—— 转弯时机体先动、镜头后跟，速度感来自这个差值。
##   2. 第三人称保持世界地平线水平；第一人称与演出保留原有滚转混合。
##   3. **FOV 随速度张开** —— 加速时视野扩张，是最便宜的"速度感"来源。

@export var follow_lag := 6.5          ## 位置跟随速率（1/s）
@export var rotate_lag := 5.0          ## 姿态跟随速率（1/s）
@export var roll_blend := 0.62         ## 第一人称 / 演出：0=水平，1=跟随机体滚转
@export var base_fov := 68.0
@export var fov_per_speed := 22.0
## 加速模式（Shift）额外拉高的视野角度。0..1 的 boost_amount 由外部写入。
@export var fov_boost_bonus := 16.0
## **超级加速的追加 FOV 档**（批 11 手感，批 12 按用户要求大幅上调）。
## 阿利宙斯巡航形态按住 Shift 时目标速度已经冲到 1.35×加力上限，
## 但速度项的 FOV 是渐变的 —— "超级"得有一个**档位感**：进入这一档，
## 视野在普通加力之上再拉开一截。
##
## ⚠️ 批 11 定的 7° 实测"有但不够"：普通加力已经拉开 16°（fov_boost_bonus），
## 超级档只多 7° 在画面上读不出"又上了一级"。18° 让三档形成
## **68 → 84 → 100+** 的清晰台阶（满速时 68+22+16+18 = 124°），
## 配合下方的持续微晃（SUPER_WOBBLE_*），"超级加速"在画面上不可能认错。
## 走 motion_scale（"降低动态"时一起安静）。
const FOV_SUPER_BONUS := 18.0
## ---- 超级加速的**持续**微晃通道（批 12，用户要求"来点镜头小晃动"）----
##
## ⚠️ 为什么不用现成的 `_shake` 池：`_shake` 是**按事件充值、线性衰减**的
## 一次性通道（每秒 -2.4，见 `_apply_shake`）—— 持续输入会被衰减整根吃掉
##（`LAUNCH_KICK_SALVO` 的注释里有同款教训），而且随机抖读出来是"噪声"，
## 不是"引擎在震"。所以另开一条**相位正弦**通道：三个轴不同频率的平滑摆动，
## 读成"推进器在震"，而不是"镜头在抽筋"。
##
## 幅度锚点：肉眼阈值约 0.20°（`VISIBLE_DEG` 的实测口径）。
## 持续摆动要"一直在但压得住"，取 0.16°——比阈值略低是为了它**永不抢戏**：
## 受击（最高 2.17°）、相杀、齐射闷震都盖得过它。
## 走 shake_scale（设置里关"镜头抖动"时一起安静）—— 它本质是抖动。
const SUPER_WOBBLE_DEG := 0.16
## 滚转轴的倍率（与主通道 `SHAKE_ROLL_MUL` 0.7 同一思路：横滚最容易晕）。
const SUPER_WOBBLE_ROLL_MUL := 0.6
## 渐入/渐出速率（1/s）。约 0.4 s 走完 —— 瞬间全幅会读成"挨了一记"。
const SUPER_WOBBLE_RAMP := 2.5
## 微晃的渐入量（0..1，向目标机 super 状态渐近）与相位钟。
var _wob_amount := 0.0
var _wob_phase := 0.0
## 当前加速程度 0..1，由 main.gd 从玩家的 boost_intensity 写入。
var boost_amount := 0.0

# Third-person propulsion envelopes. First-person and launch paths stay separate.
const THRUST_MAX_FOV := 104.0
var _thrust_boost := 0.0
var _thrust_super := 0.0
var _thrust_dash := 0.0
var _thrust_accel := 0.0
var _thrust_speed := -1.0
var _thrust_step := 0.0
var _dash_direction := Vector3.ZERO

func _thrust_enabled() -> bool:
	return not first_person and _fpv_blend < 0.001 and not _launch_view

func _reset_thrust_motion() -> void:
	_thrust_boost = 0.0
	_thrust_super = 0.0
	_thrust_dash = 0.0
	_thrust_accel = 0.0
	_thrust_speed = -1.0
	_thrust_step = 0.0
	_dash_direction = Vector3.ZERO

static func propulsion_envelope(value: float, goal: float, dt: float, attack: float, release: float) -> float:
	return lerpf(value, goal, 1.0 - exp(-(attack if goal > value else release) * maxf(dt, 0.0)))

func _step_thrust_motion(delta: float) -> void:
	if not _thrust_enabled():
		_reset_thrust_motion()
		return
	_thrust_step = clampf(delta, 0.0, 0.1)
	var velocity := _target_velocity()
	var speed := velocity.length()
	var acceleration := 0.0
	if _thrust_speed >= 0.0 and delta > 0.00001:
		acceleration = clampf((speed - _thrust_speed) / delta / 600.0, -1.0, 1.0)
	_thrust_speed = speed
	_thrust_accel = propulsion_envelope(_thrust_accel, acceleration, delta, 8.0, 5.0)
	var boost := clampf(boost_amount, 0.0, 1.0)
	var dashing := false
	if target is FlightBody:
		dashing = target.translate_dash
		if target.fm != null and target.fm.boosting: boost = 1.0
	if dashing:
		_dash_direction = target.global_basis.inverse() * velocity.normalized()
	_thrust_boost = propulsion_envelope(_thrust_boost, boost, delta, 8.0, 4.0)
	_thrust_super = propulsion_envelope(_thrust_super, _super_amount(), delta, 4.5, 3.0)
	_thrust_dash = propulsion_envelope(_thrust_dash, 1.0 if dashing else 0.0, delta, 16.0, 7.0)


var target: Node3D = null
## 锁定目标时镜头会向它偏一点，让目标更容易被看到。
var aim_target: Node3D = null
var aim_bias := 0.0

## ---- 锁定镜头（1.1 新增，Alt 切换）----
##
## 用户要求："按 Alt 键可以切换到锁定镜头（并非一直跟随在锁定视角）"。两句话各管一件事：
##   - "切换到" = **开关式**：按一下进去、再按一下回来，不是"按住才看"；
##   - "并非一直跟随" = 锁定镜头**不是默认视角**，锁定生效时也不会自动接管 ——
##     默认永远是追尾镜头，只有玩家主动按 Alt 才切过去。
## 锁定丢失（目标没了 / 不可锁）时自动退回追尾镜头，
## 否则玩家会盯着一个已经不存在的目标发呆，还以为是镜头卡住了。
var lock_view := false
## 0..1 的混合量。切换时平滑过渡，不然机位会瞬移（一瞬移就分不清自己在往哪飞）。
var _lock_blend := 0.0

# ---- 辅助驾驶的"两者都在画面里"构图（1.2 用户要求）----
#
# 与"锁定镜头"的区别很重要：锁定镜头是**盯住敌机**（自机可能被甩到画面外），
# 而用户要的是「机体可以转向，但镜头必须同时框住机体与被锁定的敌机」。
# 所以这一套不做"视线贴到目标身上"，而是：
#   ① 视线看向**两者的中点**；② 距离按**间距**撑开，够装下两点。
# 用 `_frame_blend` 渐进过渡，和 `_lock_blend` 一样连续，不会突然跳。
var frame_both := false
var _frame_blend := 0.0
# Shoulder composition is driven by the existing assist switch, independent of lock.
var _assist_side_blend := 0.0
var _precision_blend := 0.0
var _precision_anchor_id := 0
var _precision_anchor_position := Vector3.ZERO

var _precision_orbit_valid := false
var _precision_orbit_frame := Basis.IDENTITY
var _precision_orbit_offset := Vector3.ZERO
var _precision_orbit_depth := 4000.0
var _precision_orbit_model := ""

func _precision_center() -> Vector3:
	var bounds = target.get("model_bounds")
	return target.global_transform*bounds.get_center() if bounds is AABB else target.global_position

func _step_precision_orbit(delta: float) -> void:
	if _precision_blend < 0.001 or first_person or _launch_view:
		_precision_orbit_valid = false
		return
	if not _precision_active(): return
	var focus := _precision_focus()
	var direction := _precision_free_direction()
	var depth := 4000.0
	if focus != null:
		direction = _precision_center().direction_to(focus.global_position)
		depth = maxf(_precision_center().distance_to(focus.global_position),200.0)
	if direction.length_squared() < 0.5: direction = -target.global_basis.z
	var goal_up := Vector3.RIGHT if absf(direction.normalized().y)>0.999 else Vector3.UP
	var goal := _horizon_basis(Basis.looking_at(direction,goal_up))
	var profile = target.get("profile")
	var model: String = str(profile.id)+":"+str(profile.form)+":"+profile.model_path if profile != null else ""
	if _precision_orbit_valid and model != _precision_orbit_model:
		# A newly installed model needs its own hull clearance; this is not a lock change.
		_precision_orbit_offset = _precision_shoulder_offset(_precision_orbit_frame,assist_side_offset(offset*0.70,1.0))
	_precision_orbit_model = model
	if not _precision_orbit_valid:
		_precision_orbit_frame = _horizon_basis(global_basis)
		_precision_orbit_offset = _precision_shoulder_offset(_precision_orbit_frame,assist_side_offset(offset*0.70,1.0))
		_precision_orbit_depth = depth
		_precision_orbit_valid = true
	var angle := _precision_orbit_frame.get_rotation_quaternion().angle_to(goal.get_rotation_quaternion())
	var turn := minf(1.0-exp(-8.0*delta),deg_to_rad(240.0)*delta/maxf(angle,0.00001))
	var previous := _precision_orbit_frame
	var base := assist_side_offset(offset*0.70,1.0)
	# Prepare enough shoulder room before orbiting a wide cruise hull sideways.
	# Both the distance and lateral movement remain speed-limited.
	var prepared := _precision_shoulder_offset(previous,base)
	for sample_index in range(1,13):
		var sample := float(sample_index)/12.0
		var frame := _horizon_basis(previous.slerp(goal,sample).orthonormalized())
		var needed := _precision_shoulder_offset(frame,base)
		prepared.x = maxf(prepared.x,needed.x)
		prepared.z = maxf(prepared.z,needed.z)
	# Buffer the sampled sweep so a support-point peak cannot stall the orbit.
	prepared.x += 0.5
	prepared.z += 1.2
	_precision_orbit_offset = _precision_orbit_offset.move_toward(prepared,24.0*delta)
	var lower := 0.0
	var upper := turn
	for iteration in 10:
		var amount := (lower+upper)*0.5
		var frame := _horizon_basis(previous.slerp(goal,amount).orthonormalized())
		var needed := _precision_shoulder_offset(frame,base)
		if needed.x <= _precision_orbit_offset.x+0.001 and needed.z <= _precision_orbit_offset.z+0.001:
			lower = amount
		else: upper = amount
	_precision_orbit_frame = _horizon_basis(previous.slerp(goal,lower).orthonormalized())
	_precision_orbit_depth = lerpf(_precision_orbit_depth,depth,1.0-exp(-6.0*delta))

func _advance_precision_anchor() -> void:
	var identity := target.get_instance_id()
	if identity != _precision_anchor_id:
		_precision_anchor_id = identity
		_precision_anchor_position = target.global_position
		return
	var displacement := target.global_position-_precision_anchor_position
	_precision_anchor_position = target.global_position
	if _precision_blend > 0.001 and not first_person and _fpv_blend < 0.001 and not _launch_view:
		# Smooth the shoulder orbit in the moving hull frame, not across its flight path.
		global_position += displacement

func _precision_active() -> bool:
	return is_instance_valid(target) and target.has_method("precision_view_active") and target.call("precision_view_active") and not _launch_view

func _precision_focus() -> Node3D:
	if not _precision_active() or first_person or not target.has_method("precision_focus_target"): return null
	var focus = target.call("precision_focus_target")
	return focus if is_instance_valid(focus) else null


func _precision_free_direction() -> Vector3:
	if not _precision_active() or first_person or not target.has_method("precision_free_direction"): return Vector3.ZERO
	return target.call("precision_free_direction")



func _assist_side_active() -> bool:
	return is_instance_valid(target) and target.get("assist_on") == true and not first_person and not _launch_view

static func assist_side_offset(base: Vector3, amount: float) -> Vector3:
	# Positive camera X places the suit left of the forward sight line.
	return base.lerp(Vector3(base.z * 0.31, base.y * 0.72, base.z * 0.76), clampf(amount,0.0,1.0))

const FRAME_RATE := 3.0
## 撑开时的余量（免得刚好擦边）。
const FRAME_MARGIN := 1.45
## 估算"要装下 S 米需要退多远"用的视场角（取保守值：比实际 FOV 小一点 → 退得更远一点）。
const FRAME_FOV_DEG := 62.0
## ⚠️ **后退上限**（1.2 用户实测反馈："为什么要拉那么远，能不能和正常巡航的时候距离保持差不多"）。
##
## 一开始我按"装下两点"的几何去撑距离，结果是敌机一远、镜头就退到很远，
## 自机在画面里变得很小 —— 而用户要的构图是"**自机还是巡航时那么大**，
## 只是别把敌机甩出画面"。所以：
##   ① 视线看中点（这才是"两边都在画面里"的主要手段）；
##   ② 距离**最多只比常规后退 18%**，超出的部分不再后退。
## 代价是"敌机极远时它会靠近画面边缘" —— 那是可以接受的，通过拉远换来的
## "自机变小"反而更难受。
const FRAME_MAX_MULT := 1.18

# ---- ★ 轮 63-5：辅助驾驶构图修正（批 3 §四）----
#
# ## 症状（用户报）
#   ① 正常飞行时自机容易跑到画面外；
#   ② 辅助驾驶下锁定目标大幅机动时，视角被一瞬间拉过去、自机突然消失。
#
# ## 根因（`tools/probe_cam_framing.gd` **无头**实测）
#   ② 的一半 = **同框层是死代码**：本文件里锁定层**后写**、把同框层整段覆盖
#      （把机位钉住后，"两个都开"与"只开锁定"的视线方向**逐位相同 / 差 0.000000°**）。
#   ①② 的共同根因 = **没有"自机必须留在画面里"这道约束**：锁定锥角
#      `LOCK_CONE_DEG` 55° **大于**半水平视场（16:9 50.17° / 16:10 47.18°）
#      ⇒ 敌机转到锥边缘时自机必然出画（实测自机偏角峰值 **54.96°**）。
#
# ⚠️ 实测**推翻**了一个想当然（原设计文档 §4.4 的乐观估计）：中点与敌机**同方位**
# ⇒ "看中点"只把自机偏角改 **0.33°**、把 `lk` 钳到 0.45 只改 **0.52°**。
# **真正把自机拉回画面的是安全角**（54.96° → 29.25° @16:10）。前两条仍然要做
#（它们治的是"哪一层说了算"和提前量抖动），但不能指望它们治出画。
#
# ⚠️ 安全角**刻意不约束手动锁定视角**（Alt）—— 理由见 `_desired_basis()` 里的 `guard`。

## 自机留框的安全角 = 半水平视场 × 本系数（用户拍板 0.62）。
## 不取 1.0 的理由：贴着画面边缘读不出"我还在里面"，留出边缘余量后缠斗中的
## 自机始终有"看得见自己在哪"的裕度。
const SAFE_FRAC := 0.62
## 辅助驾驶时**锁定层的权重上限**（用户拍板：钳住 `lk ≤ 0.45`）。
const ASSIST_LOCK_CAP := 0.45
## 提前量的**距离封顶**系数（用户拍板：`lead` 长度 ≤ 0.25 × 目标距离）。
const LEAD_DIST_FRAC := 0.25
## 锁定视线的**时间**提前量（秒）。`lead = 敌机速度 × 本值`，再按距离封顶。
const LOCK_LEAD_TIME := 0.25


## 两个点（自机与敌机）的间距；没有锁定目标时返回 0。
func _separation() -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	var other := _frame_partner()
	if other == null:
		return 0.0
	return target.global_position.distance_to(other.global_position)


func _frame_partner() -> Node3D:
	if aim_target != null and is_instance_valid(aim_target):
		return aim_target
	return null


## **纯函数**：要同时装下间距为 `sep` 的两个点，相机最少要退到多远。
## 抽出来是为了能单测 —— 画面构图这种事，靠肉眼盯截图很容易漏。
static func framing_distance(sep: float, base_back: float) -> float:
	if sep <= 0.0:
		return base_back
	var need := sep * FRAME_MARGIN / (2.0 * tan(deg_to_rad(FRAME_FOV_DEG) * 0.5))
	return maxf(base_back, need)
## 锁定镜头下机位后拉 / 抬高的量：目标在自己侧后方时，追尾机位会把目标压在屏幕边角上，
## 得把镜头往外挪一点才看得清。
##
## ⚠️ 0.62 → 0.30 / 7.0 → 5.0（2026-09-22 晚，用户："辅助模式镜头锁定之后
## 镜头太远了，拉近一点"）。原来的后拉量在辅助驾驶（常驻锁定跟随）下
## 全程生效，机位远了 62% —— 减半到 0.30：保住"目标不压屏幕边角"的初衷，
## 玩家机体重新成为画面的主角。
const LOCK_VIEW_PULLBACK := 0.30
const LOCK_VIEW_RISE := 5.0
## 切换速率（1/s）。约 0.22 秒走完，够快也不至于"啪"地跳过去。
const LOCK_VIEW_RATE := 4.5

var _shake := 0.0
var _look_back := false

## ---- 设置项（第十四轮 A4，由 `Settings` 每帧写入）----
##
## 玩家实测："画面一直在晃""我不是特别晕 3d，但玩这个还是有点难受吧"。
## 抖动与 FOV 动态都是"感觉"，不是物理 —— 所以它们必须**能被关掉**，
## 而不是当成一个内嵌在 `add_shake()` 里的常数。
## 0 = 关。滚转跟随（`roll_blend`）也走同一条路，见 `Settings.CAM_ROLL_STEPS`。
var shake_scale := 1.0
var motion_scale := 1.0

# ============================================================ 第一人称（座舱视角，轮 20）
#
# 需求原文：「做一个第一人称模式，然后把第一人称模式的开关放到设置里面，
# 再加一个开关提醒：开启本模式会导致强烈的 3d 眩晕，是否还要开启？」
#
# 实现上只有三件事，但每一件都得做对：
#
#   ① **眼位贴到机体头部** —— 锚点走 `rig_anchor("head")`（鸭子类型读，
#      理由见 `_fpv_eye_local()`：不许写死 `FlightBody`，那会绕成循环依赖）。
#   ② **刚性贴合** —— 追尾镜头的 `follow_lag` 在 200 m/s 下稳态差出 30 米
#      （`v / follow_lag`，靠速度前馈才在巡航时补掉）。不压死滞后的话，
#      所谓"第一人称"其实是"没有模型的追尾镜头"，玩家会觉得自己挂在机体后面飘。
#   ③ **锁定镜头 / 双机同框在 FPV 里退场** —— 那两个都是"把视线拉到别人身上"的构图，
#      眼睛长在自己头上时它们没有意义，硬留着会让准星和机头分家。
#
# ⚠️ 一个必须交代的取舍：**FPV 下自机模型由 `main` 整个隐藏**。
# 眼位落在头部**壳内**，而本工程的机体是 AI 扫描出来的**单层壳**（没有座舱内构、
# 也没有内壁材质），留在壳里只会看到背面剔除后的穿透碎片 + 近平面（1.2 m）剖切。
# 要做"看得见自己肩膀"的座舱视角，得给每台机补一层内壳 —— 那是美术资产的事，
# 不是这个开关的事。
var first_person := false
# Deliberate head look is separate from flight input and ordinary mouse aiming.
var head_look := Vector2.ZERO
var head_look_active := false
var _head_mouse_mode := -1
var _head_cursor_position := Vector2.ZERO
const HEAD_LOOK_SENSITIVITY := 0.003
const HEAD_LOOK_RETURN := 10.0

func set_head_look_active(active: bool) -> void:
	if active == head_look_active: return
	head_look_active = active
	if active:
		_head_mouse_mode = Input.mouse_mode
		_head_cursor_position = get_viewport().get_mouse_position()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif _head_mouse_mode >= 0:
		Input.mouse_mode = _head_mouse_mode
		if _head_mouse_mode == Input.MOUSE_MODE_VISIBLE: Input.warp_mouse(_head_cursor_position)
		_head_mouse_mode = -1

func add_head_look(relative: Vector2) -> void:
	head_look.x = wrapf(head_look.x+relative.x*HEAD_LOOK_SENSITIVITY,-PI,PI)
	head_look.y = clampf(head_look.y+relative.y*HEAD_LOOK_SENSITIVITY,deg_to_rad(-89.5),deg_to_rad(89.5))

func _input(event: InputEvent) -> void:
	if event.is_action("cockpit_freelook"):
		set_head_look_active(event.is_pressed() and first_person and not _launch_view and is_instance_valid(target))
	elif event is InputEventMouseMotion and head_look_active:
		add_head_look(event.relative)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_EXIT_TREE]:
		set_head_look_active(false)

func _step_head_look(delta: float) -> void:
	if not first_person or _launch_view or not is_instance_valid(target):
		set_head_look_active(false)
		head_look = Vector2.ZERO
	elif not head_look_active:
		head_look = head_look.lerp(Vector2.ZERO,1.0-exp(-HEAD_LOOK_RETURN*delta))
		if head_look.length_squared()<0.000001: head_look=Vector2.ZERO

func is_head_looking() -> bool:
	return head_look_active or head_look.length_squared()>0.000001 or (first_person and _look_back)

func head_look_basis(body: Basis) -> Basis:
	var yaw := -head_look.x+(PI if _look_back else 0.0)
	return (body*Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,-head_look.y)).orthonormalized()

## 0..1 的混合量。进/出各走 `FPV_RATE`，**不许瞬移**：
## 座舱与追尾两个机位差了五十米，硬切会把玩家甩一下，而"被甩一下"正是晕动症的引信。
var _fpv_blend := 0.0
## 进/出第一人称的混合速率（1/s）。约 0.2 秒走完。
const FPV_RATE := 5.0
## 眼位相对头部锚点的补正（机体局部坐标，−Z 是机头方向）：往机头前一点、略抬一点。
const FPV_EYE_FWD := 0.45
const FPV_EYE_UP := 0.12
## 找不到头部锚点时的兜底眼位（机体局部坐标）。
## 12 m ÷ 28 m 全高 ≈ 机体的 43% 高度处 —— 与占位骨架的 `head` 槽位同高度。
const FPV_FALLBACK_EYE := Vector3(0.0, 12.0, 0.3)
## FPV 下的跟随速率（位置与姿态共用）。
##
## ⚠️ **不是无限大**，而且这个数不是随手挑的 —— 它被抖动补偿的一致性锁死。
##
## 追尾镜头的稳态幅度 = `名义值 ÷ 每帧回收比例`（`_apply_shake()` 每帧先被
## `want_basis` 回收一次、再叠一个随机转角，稳态解 `x·f = a` ⇒ `x = a/f`）。
## 把滞后压到 0（每帧硬写 basis）会把这份累加**整个抹掉** ⇒
## 受击 / 发射 / 超级加速微晃在 FPV 下静默变弱好几倍，而"挨打要看得见"
## 是本作打击感的地基之一。所以这里留一个**有限**的滞后，再用 `_fx_gain` 补差额。
##
## ⚠️ **物理步是 60 Hz**（`project.godot` 里没有改 `physics_ticks_per_second`，
## 2026-09-26 用 `Engine.physics_ticks_per_second` 实测 = 60），
## 所以 `dt = 1/60`：`f_chase = 1 − e^(−5/60) = 8.00%`、`f_fpv = 1 − e^(−30/60) = 39.35%`，
## 纯回收比 `f_fpv / f_chase` = **4.92**（位置通道同理是 3.83，见 `_fx_pos_gain`）。
##
## ## ⚠️ 这份补偿是**标定过的近似，不是精确匹配** —— 把账摊开在这里
##
## 各通道"要让 FPV 的峰值幅度等于追尾镜头"所需倍数。按**有限脉冲的峰值**算：
## `x = Σ push_n · (1−f)^(剩余帧数)`，峰值取在脉冲最后一帧之后。
##
## | 通道 | 脉冲长度 | 需要（旋转 / 位置） | 实际用 |
## |---|---|---|---|
## | 超级加速微晃（**永不结束**） | ∞ | **4.92 / 3.83** | 4.92 / 3.83 ✓ 精确 |
## | 发射抖动（`_shake₀ = LAUNCH_SHAKE_CEIL = 0.30`） | 0.12 s | 4.60 / 4.11 | 4.92 / 3.83 ✓ |
## | 受击随机抖（`_shake₀` = 0.30 / 0.55 / 1.20） | 0.12–0.50 s | 4.6–17.5 / 4.1–12.4 | 弱 0–3.6× |
## | 定向推拒的**旋转**（`k₀` 跑 0.05→3.5） | 0.03–2.19 s | 1.20–4.92 | 短脉冲强 ≤2.7× |
## | 定向推拒的**位置**（同上） | 0.03–2.19 s | 1.27–14.1 | 长脉冲弱 ≤3.7× |
##
## 为什么一个数盖不住：**只有"永不结束"的那一条真有稳态**。
## 其余全是**有限脉冲**，需要的倍数从 1.2 到 17.5 跨了一个数量级 ——
## 位置通道更极端（形状是线性斜坡，累加 ∝ `1/f²` ⇒ 比值是回收比的**平方**）。
##
## 取"纯回收比"（旋转 4.92 / 位置 3.83）的后果，逐条讲清（这是本轮的取舍）：
##   - **持续通道精确对齐** —— 微晃是唯一常驻的，它对了，日常手感就对了；
##   - **发射抖动（最频繁的那条，0.12 s）几乎精确**：需要 4.60、给了 4.92，差 7%；
##   - **短促推拒的旋转偏热 ≤2.7×** —— 这反而是好事：追尾镜头把 `LAUNCH_KICK_SALVO`
##     压到峰值只有 0.36°（本来就看不见），补完是 0.98°，座舱里开火终于看得见；
##   - **受击随机抖偏冷 0–3.6×**（大挨打时最明显）—— 但"挨打"的读法主要由**旋转**承担，
##     而推拒旋转在典型受击（`k₀ ≈ 0.5–1.2`）上是精确的，所以不会读不出来；
##   - **位置通道一律偏冷**（推拒位置最多弱 3.7×）—— 这个方向**刻意留着**：
##     座舱里相机平移 = 整个世界横移，是这个模式最晕的一种位移；
##     旋转通道已经保证了打击感，位置不必再对齐。位置另走 `_fx_pos_gain`
##     （它按 `_pos_lag()` 回收，理由见那个变量的注释）。
##
## 要真精确，得给每条通道按它自己的衰减速率与脉冲长度各算一个倍数（4 处），
## 而"多一个会静默失准的地方"本身就是代价 —— 本轮的取舍是**一个数 + 把偏差写清**。
##
## 刚性的代价：姿态上给最大滚转速率留约 2.6° 的**恒定**相位差（滚转**速率**是对的，
## 只是角度差一格，在动态里看不出来）；位置上靠速度前馈把稳态误差消到 0，
## 只剩加速度量级的残差（6 g 机动 ≈ 0.1 m，近平面 1.2 m）。
##
## 另外记一笔**没做**的事：这个滞后本来还可以给"座舱视角的呼吸感"用，
## 但那需要把抖动与跟随解耦成两个基底，改动面远大于本轮的收益 —— 不做。
const FPV_LAG := 30.0
## FPV 下"视线沿机头方向"的取点距离（米）。只用来定方向，距离本身无意义。
const FPV_LOOK_AHEAD := 120.0
## FPV 下**随速度张开的动态 FOV** 的保留比例。
##
## 视野随速度扩张是速度感最便宜的来源，也是晕动症最直接的引信 ——
## 而 FPV 把这份动态**直接糊在眼睛上**。压到一半：留住速度感，不至于难受。
## ⚠️ 只压这一项，**不压 `_fov_kick`**（那是"我打中了"的正反馈，压它等于压打击感）。
## "降低动态"（`motion_scale = 0`）优先级更高，照样能把它们整个关掉。
const FPV_FOV_DYN := 0.5
## **旋转**（抖动 / 推拒主通道）的幅度补偿系数。1.0 = 追尾镜头（不动）。
##
## 存在的理由与四条通道的账见 `FPV_LAG` 的注释。要点：
## 稳态累加 `x = 名义值 ÷ 每帧回收比例 f`，而 FPV 的 `f` 大得多 ⇒ 同一个名义幅度
## 在座舱里看起来弱好几倍。所以倍数 = **两个回收比例之比**，
## 在 `_update_fx_gain()` 里按真实 `delta` 现算 ——
## 写死 4.92 的话，哪天有人调 `rotate_lag` 或物理步长，这里就会静默失准。
var _fx_gain := 1.0
## **位置**（`SHAKE_M_PER_DEG` 那点"配重"）的幅度补偿系数。
##
## ⚠️ 单列一个、不复用 `_fx_gain`：位置走 `_pos_lag()`、旋转走 `_rot_lag()`，
## 而这两个速率在追尾镜头下**本来就不相等**（`follow_lag = 6.5` vs `rotate_lag = 5`）
## ⇒ 两条通道的回收比例不同、需要的倍数也不同（60 Hz 下 3.83 vs 4.92）。
## 复用旋转那个等于把位置多推 28%，而位置抖动在座舱里就是"整个世界横移"，
## 是这个模式里最晕的一种位移 —— 没有理由让它偏热。
var _fx_pos_gain := 1.0

# ============================================================ 反馈抖动（2026-09-21）
#
# 抖动**通道**早就存在（`_shake` → `_apply_shake()`），缺的是"反馈设计"：
#
#   `_shake`  = **无方向**的随机抖（发射、相杀、击坠都用它）；
#   `_kick`   = **有方向**的一次性推拒（**只有受击用**）。
#
# 两条通道独立叠加、互不覆盖 —— 真实的体感也是"被推了一下 + 震了一下"。
#
# ⚠️ 为什么发射抖动**不带 `_kick`**（DESIGN §4.10.2④）：
# 导弹是从自己身上出去的，"被推的方向"没有物理意义；硬给一个方向会让
# **"我刚开火"和"我刚挨打"变得分不清** —— 这两种反馈必须能一眼分辨。

## ⚠️ **2026-09-21 第二次返工：单位错了，功能等于没做。**
##
## 第一版把"伤害占比"**直接**当幅度用（`占比 × KICK_PER_RATIO` 米）。
## 而真实占比小得离谱：光束步枪 7 / 217 ≈ **0.032**，军刀 22 / 217 ≈ 0.10。
## 一发光束步枪因此只得到 0.10 米位移 —— 相机在 54 米外、
## 68° 视场下半屏对应 36 米，0.10 / 36 ≈ **0.3%，1080p 上不到 0.5 像素**。
## 军刀也只有约 7 像素。**玩家说"抖了但看不出来"，就是这里。**
##
## 所以引入**严重度归一化**：占比先按 `HIT_RATIO_REF` 折成"挨了几下"，
## 1.0 = 一次正常挨打。这样"一发步枪"和"一记军刀"才落在有梯度的区间里。

## 「一次正常挨打」的伤害占比（光束步枪 ≈ 0.032，军刀 ≈ 0.10）。
const HIT_RATIO_REF := 0.05
## 严重度上限：一次挨打最多按几倍算（撞机量级 ≈ 3）。
## 没有它的话，一发 10.0 的测试伤害会算出 200 倍，把上限断言变成在测 `clampf`。
const HIT_SEV_MAX := 3.0
## 定向推拒：**每单位严重度**多少米。
##
## ⚠️ 这个数是**记账值**，不是画面位移 —— 中间隔着跟随滞后：`_physics_process` 每帧把相机
## 往目标机位 lerp 过去（`follow_lag = 6.5` ⇒ 60 Hz 下每帧只回收 **10.27%**、残留 **89.73%**），
## 于是"每帧都加一点"会被残留**累加**起来。
##
## ⚠️⚠️ **但"累加倍数"不是常数，别写成"记账值 × N 倍"**：
## `_kick` 是**线性衰减**的（`_kick = maxf(_kick - delta * KICK_DECAY, 0)`），
## **脉冲长度 ∝ 幅度** ⇒ 峰值位移对幅度是**超线性**的。
## 实测：单位幅度（k = 1.0）在 1/20 下倍数 2.2872，而实际步枪那档（k = 0.542）只有 1.889。
## ⇒ 只许**按实际幅度各测一次**，不许拿单位幅度的倍数去乘。
##
## 下表是 `tools/probe_cam_accum.tscn` 的 `SHIFT` 表原文（隔离法：`_shake` 清零、
## 只剩推拒这一条通道；半屏 = 54 m 距离 / 68° FOV ≈ 36 m）：
##   类型                     记账_kick   1/20 峰值   1/60 峰值  20Hz倍  60Hz倍  60Hz半屏
##   光束步枪 7/217 BEAM      0.542 m     1.023 m     2.580 m   1.889   4.760     7.2%
##   光束军刀 22/217 SABER    1.947 m     5.208 m    13.828 m   2.676   7.104    38.4%
##   撞机    0.15 RAM         3.500 m    10.331 m    27.643 m   2.952   7.898    76.8%
##（撞机那格的 3.5 是 `KICK_MAX` 截断后的值：sev 3.00 × 权重 1.0 本应给 3.60。
##  旧注释那个 5.96 倍是**单位幅度**的倍数，乘到 0.542 上会把 2.58 m 说成 3.23 m。）
## 梯度正常；最重一档 **76.8% 半屏**，仍在画面内，但已经相当"飞"了 —— 见本节末。
##
## ⚠️ **@60 Hz 是这一轮才第一次按实测步长算的**（`project.godot` 没改
## `physics_ticks_per_second`；2026-09-25 / 09-27 两次读到
## `Engine.physics_ticks_per_second == 60`）。旧注释按 20 Hz 推 ⇒ 这些峰值**一直被低估**
## （撞机 20 Hz 口径 10.3 m，60 Hz 实为 27.6 m）。放大倍数 2.5 ~ 2.7 倍，**随幅度略变**。
##
## ⚠️ **常量一个字没动**：它是按**实机手感**逐档调出来的，不是从这些倍率算出来的。
## 哪天觉得受击位移太"飞"，该动的是手感（`HIT_KICK_M` / `KICK_MAX`），不是这段注释。
const HIT_KICK_M := 1.2
## 受击随机抖：**每单位严重度**多少「抖动池」单位。
## 与 `HIT_KICK_M` 分开是因为两条通道的换算率不同（见 `SHAKE_DEG_PER_UNIT`）。
const HIT_JITTER_UNITS := 0.55
## 全向冲击（近炸）没有方向通道，把那份能量折进随机抖时的**放大系数**。
## 不放大等于"爆炸比同伤害的定向命中更轻"，那是反直觉的。
const HIT_FUNNEL_FOLD := 1.4
## 单次推拒的幅度上限（米，记账值）。被一发放倒也不该把镜头甩飞。
##
## 3.5 是**让它真的绑得住**的数：撞机（sev 上限 3 × 权重 1.0）算出 3.6 ⇒ 被截。
## 第一道防线仍是 `HIT_SEV_MAX`，这一档管的是"撞机也别把自机甩出画面"。
const KICK_MAX := 3.5
## 推拒的衰减速率（1/s）。**比 `_shake` 的 2.4 慢**，是为了让"被推"读得出来
##（抖一下就没了的话，方向信息根本来不及被感知）。
const KICK_DECAY := 1.6
## 两次**新推拒**之间的最短间隔（秒）。
## 节流的是**事件的边沿**，不是总量：窗口内后续命中照样把幅度叠进 `_kick`，
## 于是"被连续打"的量感保留，而镜头不会变成震动棒。
const HIT_SHAKE_MIN_INTERVAL := 0.12
## 机炮专用的更长间隔：连发武器让它读成"持续被打"的闷震，而不是每发推一下。
const HIT_SHAKE_MIN_INTERVAL_VULCAN := 0.22
## 单次随机抖的幅度上限（抖动池单位）。`_shake` 池子的上限是 1.4（击坠级），受击不该到那。
const HIT_SHAKE_MAX := 1.2
## §4.9.2⑤：护盾期挨打的抖动倍率。
##
## ⚠️ 0.45 是**实测扫出来的**，不是照着严重度线性外推的（那样会取到 1.0，
## 结果和掉血期一样重，等于没压低）。扫的是**画面峰值转角**，
## 那张表在 `shield_hit_ratio()` 的注释里。
const HIT_SHIELD_MUL := 0.45
## 同一次连续发射的最短落账间隔（秒）。
## ⚠️ 20 发/秒 × 100 发的齐射如果每发都推一次镜头，那不是"后坐感"，
## 那是**镜头在抽筋**（DESIGN §4.10.2③）。
const LAUNCH_SHAKE_MIN_INTERVAL := 0.05
## 浮游导弹**每一发离架**的后坐量。
##
## ⚠️ 0.05 是"三分之二发"那一档的一半，**故意压低**：
## 3 发合计 0.15 —— 必须**明显轻于**全弹发射的`LAUNCH_SHAKE_CEIL`（0.30），
## 否则"打 3 发"和"打 100 发"在镜头上一模一样，玩家读不出自己按的是哪个键。
## 实测 3 发峰值约 0.5°，仍在肉眼阈值以上（`VISIBLE_DEG` 0.20）。
const LAUNCH_KICK_FUNNEL := 0.05
## 全弹发射**每一发**的后坐量。
##
## ⚠️ 这个数**不是随手定的**，它被 `_apply_shake()` 的衰减方式锁死：
## 衰减是**线性**的（`_shake -= delta * 2.4`）⇒ **每秒不到 2.4 的输入会被整根吃掉**，
## `_shake` 永远停在 0。而全弹发射恰好是 20 发/秒 ⇒
## **每发必须 > 2.4 / 20 = 0.12**，否则"场上最大的一次动作"在镜头上一点都读不出来。
##
## 第一版按 3 发那档的 1/4 给了 0.02（设计稿里也是这个数），实测**峰值恒为 0.000**
## —— 功能等于没做。0.14 是"刚好压过阈值"的值，配合 `LAUNCH_SHAKE_CEIL` 得到
## 持续的闷震（实测齐射期间稳定在 0.38~0.5）。
const LAUNCH_KICK_SALVO := 0.14
## 发射通道能顶到多高。**只给发射用**（受击有自己的 `HIT_SHAKE_MAX` 1.2）。
##
## 存在的理由：发射是**按发累加**的，而线性衰减又要求"每发压过阈值"，
## 两者相乘会让齐射无限往上爬 —— 封一个天花板，读成"闷震"而不是"抽筋"。
##
## ⚠️ **2026-09-21 第二次返工：0.5 → 0.30。**
## 0.5 那一版实测齐射峰值 **1.69°**，而撞机是 **2.17°** —— 两者几乎一样重。
## 全弹发射是"我一直按着开火键"，撞机是"我被撞飞了"，**这两种必须先分得开**；
## 而且齐射是**持续**的，1.69° 顶住五秒会晕。0.30 实测峰值约 1.0°，
## 既在阈值以上、又稳稳低于任何一档受击。
const LAUNCH_SHAKE_CEIL := 0.30

# ---- 抖动 → 画面位移：为什么必须是**旋转**（2026-09-21 第二次返工的核心）----
#
# 第一版把抖动**只**施加在 `global_position` 上（平移）。这个通道在追尾镜头里
# 弱得几乎没有，原因是个纯几何问题：
#
#   机体在 54 m 外，68° 视场 ⇒ 半屏对应 `54 × tan(34°) ≈ 36 m`。
#   ⇒ 平移 `d` 米造成的画面位移 = `d / 36`。
#   ⇒ 想看出 1% 的画面位移，得平移 **0.36 米**；一发光束步枪当时只给了 0.10 米。
#
# 而**转角**没有这个问题：相机转 θ 度，画面就转 θ 度，**与距离无关**。
# 人眼对"画面整体在转"的敏感度也远高于"画面整体平移"——
# 这也是所有商业引擎的镜头抖动（cinemachine impulse、UE camera shake）
# 都做成**旋转/角速度** импульс 的原因。
#
# 所以现在：**主通道是旋转，平移只留一点点当"配重"**。
# 单位换算率就下面这三个数，全部可反推。

## `_shake`（抖动池，无量纲，上限 1.4）→ **峰值转角**（度）。
##
## 取值对照：
##   `add_shake(0.5)`（相杀级）→ 0.63°    —— 明显但不晕
##   `add_shake(1.2)`（击坠）  → 1.50°    —— 一局里最重的一次
##   发射齐射稳定在 0.5       → 0.63°    —— 持续的闷震
##   `add_shake(0.07)`（轻微）→ 0.09°    —— 刚好在阈下，只当底噪
## ⚠️ 别往上调太多：受击抖动是晕动症最敏感的来源，1.4 的池上限本来就对应"击坠级"。
##
## ⚠️ **一个必须交代的连带影响**：抖动现在会真的转动镜头基向量，而
## `HUD` 与 `PlayerController` 的选目标都用 `camera.unproject_position()`
##（`player_controller.gd:387 / :397 / :1234`，按"离准星最近"挑目标）。
## 转角越大，`unproject_position` 的结果偏得越多（3.4° ≈ 屏幕横向 10% 半屏），
## 也就是说**挨重击时准星附近的目标有可能换人**。
## 这一条**评估过、可以接受**，理由两条：
##   ① 那把筛选里本来就有 `MOUSE_SWITCH_HYSTERESIS`（"光标还罩着现在这个就不跳走"），
##      它当初就是为了抗这种微小扰动加的；
##   ② 受击抖动是**短促**的（`KICK_DECAY = 1.6`，约 0.6 s 走完），
##      唯一持续的那档是全弹发射的 0.95°，也还在迟滞带的量级内。
## 但如果哪天把 `SHAKE_DEG_PER_UNIT` 往上调一大截，这条就必须重新评估 ——
## 届时正确做法是给这些取值处提供一个"**未抖动**的基向量"，而不是继续靠迟滞兜。
const SHAKE_DEG_PER_UNIT := 1.25
## 抖动同时带一点平移（**米 / 度**）。
##
## 纯旋转读起来像"镜头在云台上转"，加一点平移才有"机身在震"的分量。
## 0.30 是让 `_shake = 0.5` 得到 **0.188 米**（**记账值**：名义上"这一帧推多少"）
## —— 与第一版那个 0.275 米同量级，也就是说**平移没有被削弱**，只是不再是主角。
##
## ⚠️ 但**画面上的峰值位移不等于这个记账值**：平移通道同样被跟随滞后的残留累加
##（与 `HIT_KICK_M` 那一格是同一笔账）。`tools/probe_cam_accum.tscn` 实测
## `_shake` 恒定在 0.5 时的峰值位移：1/20 步长 **0.53 m**、60 Hz **0.85 m**。
## 工程实测步长是 60 Hz ⇒ 量级按 **0.85 m** 读，别按名义的 0.188。
##（0.53 / 0.85 是 `_shake` **恒定充值**时的上限；真实受击里 `_shake` 是衰减的，
##  峰值介于「0.188 记账值」与这两个数之间，实际值取决于受击类型。）
const SHAKE_M_PER_DEG := 0.30
## `_kick`（米，记账值）→ **整段推拒的总转角**（度）。
##
## ⚠️ 这里说的是"**整段**总转角"，不是"每帧转角" —— 施加端按**本帧消耗掉的推拒量**
## 记账（见 `_apply_kick()` 的注释）：每帧都按当前值转一个角会被 basis 的 slerp 残留
## 累加成 `1/(1−0.92) = **12.5 倍**`的稳态偏角
##（60 Hz：`rotate_lag = 5` ⇒ 每帧只回收 **8.00%**、残留 **92.00%**。
##  旧注释写的"1/(1−0.78) ≈ 4.5 倍"是 20 Hz 口径，轮 29 按实测步长重推），
## 实测一次撞机能滚出近 20°（那是**修复前**的版本，现版本已按消耗量记账），镜头像被拧住了。
## 按消耗量记账 ⇒ 总转角 = 记账值 × 本常量，有界、可预测、**且与步长无关**。
##
## 取 3.2 的反推：步枪记账 0.542 m ⇒ **1.73°**；军刀 1.947 m ⇒ 6.23°；撞机 3.50 m ⇒ 11.2°。
##（记账值读的是真机状态量 `_kick`，见 `tools/probe_cam_accum.tscn` 的 `CASE` 表 ——
##  旧注释里的 0.38 / 1.37 / 2.55 与上面 `HIT_KICK_M` 那一格自相矛盾，轮 29 一并改齐。）
##
## ⚠️ 这三个是"**注入量**"（施加端一共转出去多少度），**不是画面上的峰值残留角** ——
## 每帧转出去的角度都会被下一次 slerp 拉回去一截。隔离掉位置通道后实测
##（探针 `kick_rot_total_iso`，k0 = 2.55 m 档 ⇒ 注入 8.16°）：峰值残留角
## 1/20 步长 **1.157°**、60 Hz **1.067°** —— 只有注入量的 **13%**，两个步长只差 8%。
## 换算到撞机的 3.50 m 档（注入 11.2°）就是 **9.5%**。
## 这就是"与步长无关"的实测证据，也正是"按消耗量记账"相对
## "每帧按当前值转"（12.5 倍、且随步长放大）的价值所在。
##（⚠️ 位置通道**不满足**"与步长无关" —— 见 `HIT_KICK_M` 那张 SHIFT 表：
##  同一条推拒在 1/20 与 1/60 下的位移差 2.5~2.7 倍。两条通道的记账方式本来就不同。）
const KICK_DEG_PER_M := 3.2
## 滚转抖动相对俯仰/偏航的比例。
## 滚转给满会读成"翻跟头"（追尾镜头里天地线本来就在动），压一档更稳。
const SHAKE_ROLL_MUL := 0.7

## 伤害类型 → **方向权重**（0 = 不给方向）。见 `add_hit_shake()`。
##
## ⚠️ `FUNNEL`（近炸 / 浮游导弹命中）**故意是 0**：
## 爆炸是**全向**的，爆点可能在机体任意一侧。按"爆点方向"推镜头会让玩家读成
## "从那个方向被打了"，而他看到的是四面开花 —— **全向冲击就该是全向抖**。
## 这一格是**有意留空**的，别"顺手补上"。
const HIT_DIR_WEIGHT := {
	Damage.Type.RAM: 1.0,      # 撞机：整台机被撞飞，来向最明确
	Damage.Type.SABER: 0.8,    # 军刀：有来向
	Damage.Type.BEAM: 0.7,
	Damage.Type.BEAM_CANNON: 0.7,     # 光束：有来向，但命中瞬间是"烧穿"
	Damage.Type.VULCAN: 0.3,   # 机炮：连发，方向感弱
	Damage.Type.FUNNEL: 0.0,   # 近炸：**全向**
}
## 伤害类型 → **随机抖权重**。
const HIT_JITTER_WEIGHT := {
	Damage.Type.RAM: 1.0,
	Damage.Type.FUNNEL: 1.0,   # 全向冲击 → 全向抖，所以随机幅度给满
	Damage.Type.SABER: 0.7,
	Damage.Type.BEAM: 0.6,
	Damage.Type.BEAM_CANNON: 0.6,
	Damage.Type.VULCAN: 0.35,
}

var _kick := 0.0
## 推拒方向，**相机局部坐标系**。
##
## ⚠️ 必须转成局部：相机自己也在滚转，用世界方向的话"从左边来"会在几帧内
## 变成"从上边来"（相机转过去了），玩家读到的方向就飘了。
var _kick_dir := Vector3.ZERO
var _hit_cd := 0.0
var _launch_cd := 0.0
## 本帧待落账的发射后坐（**累加**，见 `add_launch_shake()`）。
var _launch_pending := 0.0

## 机位（机体局部坐标系，−Z 为机头方向）。
## 第四轮按需求把镜头拉近了 35%：83 m → 54 m。
## 更近的机位让机体占屏高从约 30% 提到约 45% —— 夜景里动作更容易看清，
## 代价是前半球视野变小，所以 keep_look_ahead 也跟着缩了一档。
var offset := Vector3(0, 9.0, 53.0)
var look_ahead := 36.0
var look_up := 2.6


## 远裁面（米）。**地表图**是 90 km —— 从 52 km 提到这里是因为竞技场半径扩到 26 km 之后，
## 原来的远平面会在视野边缘切掉远处海面与岛屿。
const GROUND_FAR := 90000.0
## 远裁面（米）。**轨道图** 7 000 km —— 见 `_sync_depth_range()` 里那笔几何账。
##
## ⚠️⚠️ 2026-09-30 从 `1.0e7` **降到 `7.0e6`**。这不是"顺手调小"：
## `far = 1e7` 配 `near ≤ 0.5` 会让 `rendering_light_culler.cpp::create_frustum_points`
## 直接失败（`ERROR: Condition "!res" is true. Returning: false`），
## 后果是**整个 3D 场景不被点亮**：所有 `StandardMaterial3D` 都不画，
## 画面上只剩天空盒的星星（而日志里除了上面那行 ERROR 什么都没有）。
##
## 定点扫描（`tools/_nearfar_probe.gd`，14 张图，同一夜图 / 同一机位；
## ⚠️ 该探针跑完就归档了 —— 在 `WorkBuddy/2026-09-27-13-34-43/_archive_rocket_cockpit_20260930/`，
## 原始读数在同一个工作区的 `_nearfar.log`）：
##
## | `near` | `far` | 亮像素占比 | 均值 | |
## |---|---|---|---|---|
## | 0.35 | 90 k / 500 k / 1 M / 2 M / 3.5 M / 5 M / **7 M** | 0.8351 | 150 | ✅ |
## | 0.35 | **10 M** | **0.0957** | **38** | ❌ 整场不点亮 |
## | 0.20 / 0.50 | 10 M | 0.0956 | 38 | ❌ |
## | **0.70 / 1.00** | 10 M | 0.8351 | 150 | ✅ |
##
## ⇒ 坏的是**这一组合**，不是几何（同一跑里舱位 / 眼位 / 法线全对）。
##
## ## 为什么 7 000 km 在几何上**足够**
## 相机在轨高 550 km，地球是一个半径 `R = 6 371 km` 的球、球心在相机下方 `R + h`。
## 可见轮廓就是**切线圆**，它离相机 `√((R+h)² − R²) = √(6921² − 6371²) ≈ 2 703 km`。
## 远半面**被近半面自己挡着** ⇒ 2 703 km 之外一个可见像素都没有。
## 10 000 km 里那多出来的 3 000 km 是**纯浪费**，换来的就是上面那行渲染管线崩溃。
const ORBIT_FAR := 7.0e6

# ============================================================ ★ 发射段机位
#
# ## 为什么必须单独一套
#
# 火箭是**直立**的（`RocketBody.upright_basis()` ⇒ 机体 −Z = 世界 +Y = 机头朝上），
# 于是默认机位（`offset = (0, 9, 53)`，局部 +Z = 世界 −Y）把相机放在
# **火箭下方 53 m**。平台还在的时候这勉强能用（箭底在 +50 m ⇒ 相机在 −3 m）。
#
# ⚠️ 2026-09-30 老板砍掉平台、要求「直接从海里面出来」之后，箭底到了 **−34 m**
#（`LaunchScript.PAD_DRAFT` 吃水）⇒ 默认机位把相机放到 **海面下 87 m**：
# 水面之上的一切都看不见，而**日志里一切正常**。这不是审美问题，是"这段演出没了"。
#
# ## 这套数是怎么定的
# 目标：相机在**海面之上**、在火箭的侧后方、且**控制符号不变**。
#
#   · 局部 +Y = 世界 +Z、局部 −Z = 世界 +Y（箭体直立时）
#   ⇒ `offset = (x, D, −H)` 给世界偏移 `(x, +H, +D)`：
#     `D` 是世界 +Z（水平、在火箭侧面）、`H` 是"比箭底高多少"。
#   · `H = 52`，箭底 −34 ⇒ 相机在 **+18 m**，稳稳在水面之上。
#   · `D = 62` ⇒ 相机离**箭底** `√(62² + 52²) = ` **80.9 m**，58 m 高的箭占屏高
#     **约 53%**（`base_fov` 68°，实测见 `tools/_rocket_shots.gd` ④ 那张）。
#     ⚠️ 那条 53% 是**离架那一刻**的读数（箭底 180 m，速度还近 0）。
#     2026-09-30 晚补上「FOV 速度项」之后（见 `RocketBody.speed_fov_mix()`），
#     FOV 会在整段上升里从 68° 连续张到 ~80°，同一档机位的占屏高
#     从 53% 收到 **约 43%**（`_rocket_shots.gd` ⑫ 出云之后那张量得到）。
#     两条并不矛盾：**离箭距离始终是 80.92 m**，「全程跟随」说的是距离，
#     占屏高只随 FOV 走。
#     ⚠️ 上一版这里写的是「66 m / 76%」—— 那是更早一版 `D 62 / H 78` 的数，
#     改 `H` 时没跟着改。**镜头口径的每个数都必须能被探针复算**，否则
#     "离得太远 / 太近"这类问题只能在图上靠感觉吵。
#   · `x = 0` 是**刻意的**：世界 X 是**偏航**让机头去的那个方向。
#     相机若摆在世界 X 上（= 正对着机头的偏转方向），偏航在画面上就**没有横向位移**,
#     只剩"箭在原地拧"。摆在世界的 Z 上才读得出来 —— 这也是默认那套
#     （局部 +Z ⇒ 世界 −Y，与偏航轴正交）能成立的原因。
#
# ## ★★ 2026-09-30 老板第二次改：从 `D 175 / H 78` 拉近到 `D 62 / H 52`
# > 「**发射过程中镜头离火箭太远了，我希望做全程跟随的**」
#
# 旧那套（192 m）是**照"能看见整枚箭 + 一圈出水特效"定的**，
# 站在观众席上合适，但玩家是**在操控这枚箭**：只有 30% 屏高的箭看不出
# 姿态变化、也读不出"我在加速"。这一版按"跟随"重新定：
#   · 占屏约 53% ⇒ 箭体从箭底到箭顶超过半个屏，姿态（偏航/俯仰）一眼可读；
#   · 相机与箭体**刚性同移** —— 但这件事**不是 `_desired_position()` 一个函数就够的**：
#     它算出来的那个点本来就与箭体刚性同移（`target.global_transform * LAUNCH_OFFSET`），
#     可**位置跟随那一步是一阶滞后**（`global_position.lerp(want, 1-exp(-lag·dt))`），
#     稳态误差 = `v / lag` ⇒ 速度一高镜头就被甩在后面。
#     ⚠️ 上一版这条注释写的是「所以"全程跟随"是结构保证的」——**那句话是假的**，
#     老板第三次改「相机要一直和火箭保持一个距离」正是在说这件事。
#     真正的保证是 `_rigid_chase()`（逐帧硬落位），见那一段。
#   · ⚠️ 别为了"更近"把 `H` 压到 48 以下：箭底 −34 + `H` 就是相机海拔，
#     `H ≤ 48` ⇒ 相机掉到 `LAUNCH_MIN_ALT`(14) 那道保险上，会被**抬回去**
#     ⇒ 于是机位不再是刚性的（保险是每帧钳，不是落位）。
#     52 给的是 +18 m，留 4 m 余量。
#   · ⚠️ 也别把 `D` 压到 40 以下：箭体外径 22.2 m（实测包围盒 X），
#     `D = 40` 时相机离箭侧只有 18 m ⇒ 近裁面 `near = 1.2` 之下箭体糊满屏。
#
# ## ⚠️ `roll_blend = 0` 是这套机位的一半
# `_desired_basis()` 的 `want_up = UP.lerp(t_up, roll_mix)`，而箭体直立时
# `t_up` = 世界 **+Z** —— `roll_blend` 保持默认的 0.62，地平线会歪 **~58°**。
# 战斗里"歪地平线"是缠斗感（那是刻意的旋钮）；但发射段玩家在看的是一枚
# **竖直上升的箭**，歪地平线只会让人分不清"是箭在歪还是我在歪"。
# ⇒ 发射段压到 0。控制符号**不受它影响**（滚转不改变"右"）。
## ## ★★ 2026-09-30 晚第四次改：**水平转到对侧**（`y` 从 `+62` 变 `−62`）
## 老板原话：
## > 「**镜头转过去拍火箭的另外一面**」
##
## ⇒ 机位绕箭体轴线（= 直立时的世界竖直轴）转 180°：
## 水平分量取反、`z`（高度分量）**不动**。于是
## 「相机在箭底上方 52 m、离箭心 80.92 m、箭体占屏 53%」这三件事**逐位不变**，
## 变的只有**水平方位**（受光面与背景）。
##
## ⚠️⚠️ **这个改动会镜像屏幕左右**，`main._launch_axis()` 的两个通道**必须同步取反**。
## 相机投哪边是由相机自己的 `right` 轴决定的（`Basis.looking_at()`），
## 相机绕到箭体对侧，`right` 就换向 —— 于是"按左键机头往屏幕左"会静默变成反的。
## 实测（`tools/_launch_ctrl_probe.gd`，机头方向变化点乘相机两轴、**减掉零输入基线**）：
## ```
##                     offset.y = +62      offset.y = −62
##   pitch_in = +1     sy = +0.0063（上）   sy = −0.0069（下）
##   yaw_in   = +1     sx = −0.0171（左）   sx = +0.0171（右）
## ```
## ⇒ **两个通道在屏幕上都会翻**。`main._launch_axis()` 里两个符号因此一起反了写。
##
## ⚠️ 这个数**不能只改一半**：改机位不改符号 = 玩家的左键往右转，而它不报任何错；
## 改符号不改机位 = 同样反。`suite_rocket_launch` 里有一条断言把"机位在哪一侧"
## 与"两个通道的符号"钉在一起（见 `_launch_axis_signs`）。
##
## ⚠️ 也别顺手把 `z` 一起取反：`−52` 是**高度分量**（箭底之上 52 m），
## 取反会让相机掉到箭底**下方** 52 m —— 那是另一个机位（`_launch_view_probe` 的 `E_below`），
## 不是老板要的这个。
const LAUNCH_OFFSET := Vector3(0.0, -62.0, -52.0)
## 发射段"看向机头前方多少米"。火箭 58 m 高 ⇒ 看箭体中段（不是看无穷远）。
##
## ⚠️ 它同时是**俯角的来源**：视线点 = 箭底 + `look_ahead` + `look_up`，
## 而相机在箭底 + 52 m ⇒ 24 给出"从上往下看箭体中段"，构图正。
## 拉近机位时**必须一起收**：还留 26 的话视线点在相机下方 22 m，
## 箭体被推到画面下缘（画面里一半是海）。
const LAUNCH_LOOK_AHEAD := 24.0
## 发射段"看向机头前方再抬多少米"（世界向上）。0 = 不看抬，平视箭体。
const LAUNCH_LOOK_UP := 2.0
## 发射段相机离海面的**最低高度**（米）。见 `_desired_position()` 里那道保险。
const LAUNCH_MIN_ALT := 14.0

# ============================================================ ★ 座舱眼位档（2026-09-30，改写 2026-09-30 晚）
#
# 老板原话（第一版）：
# > 「**在火箭最上端加一个驾驶舱第一人称（不是全周天！）需要建模驾驶舱视角的
# >  ui 和控制台仪表盘**」
#
# 老板原话（第二版，推翻第一版）：
# > 「**你驾驶舱做的好丑，直接用全周天驾驶舱的代码吧**」
#
# ## 这一档现在是**纯眼位**，舱体不再是一份 3D 几何
# 第一版建了一个 3D 舱（`RocketCockpit`：顶棚 / A 柱 / 控制台 / 三块 shader 圆表，
# 刚性挂在箭体上）。那一版被老板否掉，**整套 3D 舱已删除**；
# 现在的舱内表现 = `hud.gd` 里那层**全周天座舱**（刻度导轨 + 仪表台 + 取景框），
# 与机体第一人称走**同一份代码**（`cockpit_only` / `cockpit_eye` 那两个开关，见 `hud.gd`）。
#
# ⚠️ 于是这一档少了**两样曾经必须存在的东西**，别照着旧注释把它们加回来：
#   · ~~`COCKPIT_NEAR = 0.35`~~ —— 那是为了不把 1.1~2.0 m 外的控制台切掉。
#     现在舱是 2D 叠层，**没有几何可切**，近裁面回到 `LAUNCH_NEAR`（1.2）.
#     （顺带解掉一个真 bug：`near 0.35 × far 1e7` 会让整场景不被点亮，见 `ORBIT_FAR`。）
#   · ~~舱体显隐~~ —— `main._sync_cockpit()` 原来每帧切 `RocketCockpit.visible`。
#
# ## 它复用工程里既有的 FPV 通道（不另造一套）
# `_fpv_blend` 那条路已经做了三件正需要的事（见"第一人称（座舱视角，轮 20）"那段）：
#   ① 眼位取 target 的局部锚点（`_fpv_eye_local()` ⇒ `RocketBody.rig_anchor("head")`）；
#   ② 视线吸附到 target 的 **−Z**（`dir.slerp(-basis.z, blend)`）；
#   ③ 滞后压到 `FPV_LAG`。
# ⇒ `set_launch_eye(COCKPIT)` 只需要把 `first_person` 打开、把机位 / 视线 / 滚转换掉。
enum LaunchEye { CHASE, COCKPIT }

## 座舱档的**位置跟随滞后**（1/s）—— 见 `_rigid_eye()`：这一档根本不走弹簧，
## 所以它只用于"进出舱那 0.2 s 的混合"里 `_pos_lag()` 的取值。
## ⚠️ 为什么不干脆沿用 `FPV_LAG = 30`：混合期间位置是**硬落位**的（同 `_rigid_eye()`），
## 滞后值在这一档**一次都没被用到**，写 30 只是让"万一将来谁改成弹簧"时不至于 667 m。
## 666.7 = `FPV_LAG` 的 30 × 22.2 … 不是，是刻意取的"比 FPV_LAG 大一个量级"，
## 让任何残留的弹簧项在 0.015 s 内收敛（`1 - exp(-667 × 1/60) = 0.9999`）。
const COCKPIT_LAG := 667.0
## 座舱档的**滚转跟随**：`1.0` = 完全跟机体滚。
##
## ★★ 这一条**不是审美选择，是必须**：全周天那层刻度导轨钉在**世界**上
##（`RAIL_R` 那套，见 `hud.gd`），而"地平线在画面里歪多少"正是它要报的那个数。
## 相机上向量若还是世界 UP，机体滚 90° 时机头轴会与世界 UP **共线** ⇒
## `Basis.looking_at` 退化（Denormal / 随手滚，见"正俯视必须显式给 Basis"那条踩坑）。
## 取 `t_up` 之后两者恒垂直（机体的上 ⊥ 机头），退化不可能发生。
const COCKPIT_ROLL := 1.0
## 发射段的近裁面（米）—— 就是 `_ready()` 里那个值，两个眼位档**共用**。
## ⚠️ 2026-09-30 之前座舱档用的是 0.35，那时舱是 3D 几何。舱改成 2D 叠层之后
## 0.35 没有任何用处，却正好踩进"`near ≤ 0.5` × `far = 1e7` ⇒ 整场景不点亮"
## 那个渲染管线坑（见 `ORBIT_FAR` 的表）⇒ 取消，两档统一 1.2。
const LAUNCH_NEAR := 1.2
## 座舱档"看向机头前方多少米"。**取大值** ⇒ 视线 = 机头轴线本身。
## ⚠️ 别减小：24（追尾档那个数）会让视线从"箭底 + 24 m"指向"箭底 + 2 m"，
## 也就是**朝下看** —— 座舱里往机尾看，画面里全是箭体。
const COCKPIT_LOOK_AHEAD := 800.0


## 是否处于发射段机位（`set_launch_view()` 切）。
var _launch_view := false
## 发射段的**眼位档**（`LaunchEye`）。只有 `_launch_view` 为真时有意义。
var _launch_eye: int = LaunchEye.CHASE
## 切进发射段机位之前的四个值，`set_launch_view(false)` 时原样放回去。
var _saved := {}

## 上一次同步远裁面时用的地图（`null` = 还没同步过）。只在**换图**时才真的写 `far`。
var _depth_map: MapDef = null


## ★★ **谁在驱动这一台相机**（2026-09-30 加）。
##
## `false`（出厂）= 相机自己走 `_physics_process`（**固定 60 Hz**）——
## 战斗、菜单、探针都走这一条，一个字没变。
##
## `true` = **由外部在渲染帧里调用 `step_now(delta)`**。发射段用这一档，
## 理由见 `step_now()` 的头注：那一段是一整条 `main._process` 里的显式调用链
##（`rocket.step()` → 火焰 → 出水 → 相机），**火箭与相机必须同一个钟**。
var externally_stepped := false


func _ready() -> void:
	near = 1.2
	far = GROUND_FAR
	_sync_depth_range()
	fov = base_fov
	current = true
	# 相机在物理帧跟随，避免和机体位置不同步导致的抖动
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## 切进 / 切出**发射段机位**（马夫蒂火箭）。见上面那组 `LAUNCH_*` 常量的推导。
##
## ⚠️ 进来时把原来那四个值**存住**、出去时原样放回 ——
## 直接写回"默认值"是错的：玩家可以在设置里改 `roll_blend`
##（`main.gd` 每帧从 `Settings.cam_roll_blend()` 落值），
## 写死一个数会把玩家的设置**悄悄覆盖掉**，而它只在"打过一局发射段之后"才发生。
func set_launch_view(on: bool) -> void:
	if on == _launch_view:
		return
	_launch_view = on
	if on:
		_saved = {"offset": offset, "look_ahead": look_ahead,
			"look_up": look_up, "roll_blend": roll_blend, "near": near}
		# ★ 基础档 = **贴近追尾**（老板原话：「镜头离火箭太远了，我希望做全程跟随的」）。
		# 驾驶舱由 `main.gd` 的 F1 切（它每帧调 `set_launch_eye()`，从
		# `Settings.first_person` 读 —— 所以"上一局开着第一人称"进这一段会直接进舱）。
		#
		# ⚠️ 这里**不读 `Settings`**：本类不认识那个 autoload（它与 `Settings` 的
		# 全部耦合就一处 `main.gd._apply_camera_settings()`）。两条来源写在一起
		# 会让"默认是哪一档"变成一个要跨文件才能回答的问题。
		_apply_launch_eye(LaunchEye.CHASE)
	else:
		if _saved.has("offset"):
			offset = _saved["offset"]
			look_ahead = _saved["look_ahead"]
			look_up = _saved["look_up"]
			roll_blend = _saved["roll_blend"]
			near = _saved["near"]
		_launch_eye = LaunchEye.CHASE
		# ⚠️ 出舱**必须**把 FPV 关掉：不然切回战斗时玩家会以"座舱视角"开机体，
		# 而那是另一个舱（走 `Settings.first_person`，见 `_apply_camera_settings`）。
		first_person = false
		_saved = {}
		# ★ 顺手把"外部驱动"也放掉：本段结束之后相机该回到物理钟。
		#（`main._finish_launch()` 也会放一次 —— 两处都放，是为了
		#  "先走到哪一条路径都不至于被永久锁在渲染帧驱动"上。）
		externally_stepped = false
	# 立刻落位：不落的话会从上一套机位**渐变**过去，而那 0.3 秒正好是
	# 倒计时第一帧 —— 玩家看到的是镜头从海底往上飘。
	if target != null and is_instance_valid(target):
		global_position = _desired_position()
		global_transform = Transform3D(_desired_basis(), global_position)


## 切**发射段的眼位档**（驾驶舱 / 贴近追尾）。只在 `_launch_view` 为真时有意义。
##
## 两档的全部差别就是 `_apply_launch_eye()` 里那四行（机位 / 视线 / 滚转 / 近裁面）
## 外加 `first_person`（它驱动 `_fpv_blend`，而后者决定眼位与视线的混合）。
##
## ⚠️ **它会被 `_apply_camera_settings()` 每帧复核**（`main.gd`）——
## 这一档是"本段自己的状态"，与玩家的全局 `Settings.first_person` **不是一回事**：
## 玩家在设置里开着机体第一人称，不该让发射段一进来就进舱；
## 反过来也一样。两件事在 2026-09-30 之前是同一根线，那是错的。
func set_launch_eye(eye: int) -> void:
	if not _launch_view:
		return
	if eye == _launch_eye:
		return
	_apply_launch_eye(eye)


func _apply_launch_eye(eye: int) -> void:
	_launch_eye = eye
	if eye == LaunchEye.COCKPIT:
		offset = Vector3.ZERO        # 真正的眼位由 `_fpv_eye_local()` 给（锚点在箭体上）
		look_ahead = COCKPIT_LOOK_AHEAD
		look_up = 0.0
		roll_blend = COCKPIT_ROLL
		near = LAUNCH_NEAR           # ★ 两档共用（舱改成 2D 叠层之后没有几何可切，见节头）
		first_person = true
		# ⚠️ 进舱瞬间把混合量**直接落位**：从 80.9 m 外的追尾机位"飞进舱"要 0.2 s，
		# 而那是**倒计时期间**（火箭还静着）—— 玩家会先看见镜头穿过箭体。
		_fpv_blend = 1.0
	else:
		offset = LAUNCH_OFFSET
		look_ahead = LAUNCH_LOOK_AHEAD
		look_up = LAUNCH_LOOK_UP
		roll_blend = 0.0
		near = LAUNCH_NEAR
		first_person = false
		_fpv_blend = 0.0
	if target != null and is_instance_valid(target):
		global_position = _desired_position()
		global_transform = Transform3D(_desired_basis(), global_position)


## 当前发射段眼位档（测试与探针读）。
func launch_eye() -> int:
	return _launch_eye


## ★ 是不是**刚性眼位**（驾驶舱档）。
##
## ## 为什么必须"刚性"（不走弹簧、不吃抖动、不吃前馈）
## 相机的位置/姿态本来走一阶滞后（`global_position.lerp(want, 1 - exp(-lag·dt))`），
## 巡航时靠**速度前馈**（`want += v / _pos_lag()`）把稳态误差补掉。
## 而前馈读的是 `target.get("fm")` —— **火箭没有 `fm`**（它不是 `FlightBody`），
## 于是前馈恒为 0，稳态滞后 = `v / lag`：
##   · 走 `FPV_LAG = 30` ⇒ 末段 35 km/s 时相机落后 **1 167 m**。
##
## ⚠️ 2026-09-30 第一版这里写的是"舱框会飘出画面"（那版舱是 3D 几何）。
## 舱改成 **2D 全周天叠层**之后，那条具体后果没了 —— 但**刚性本身仍然必须**：
## 全周天那层刻度导轨是**画在相机上的**（`unproject_position`），它的意义是
## "机头指向 + 地平线在哪"；相机若落后箭体 1 167 m，玩家看到的方向就**不是当时的机头**，
## 仪表报的就是一个过期的姿态。抖动同理：`_apply_shake` 平移相机 ⇒
## 刻度与地平线跟着抖，而"座舱抖"该由仪表表现，不该是整个世界在动。
##
## ⇒ 这一档**逐帧硬落位**（`global_transform = Transform3D(want_basis, want_pos)`），
##   并且跳过整段抖动。代价是"没有手感的抖动"，但那本来就是错的。
func _rigid_eye() -> bool:
	return _launch_view and _launch_eye == LaunchEye.COCKPIT


## ★ 是不是**刚性追尾**（发射段的舱外档）。
##
## ## 为什么舱外档也必须刚性（老板第三次改）
## > 「**相机要一直和火箭保持一个距离**」
##
## `_desired_position()` 给的机位**本来就是刚性的**（`target.global_transform * LAUNCH_OFFSET`
## ⇒ 离箭底恒 `√(62²+52²) = ` 80.92 m），所以"距离会变"这件事**只能**来自跟随那一步：
##
##     `global_position = global_position.lerp(want_pos, 1 - exp(-_pos_lag() * delta))`
##
## 一阶滞后对匀速目标的稳态误差 = `v / lag`。`follow_lag` 默认 6.5：
## | 箭速 | 稳态落后 | 实际距离 | 箭体占屏高 |
## |---|---|---|---|
## | 180 m/s | 27.7 m | 108.6 m | 53% → **38%** |
## | 1 000 m/s | 154 m | 235 m | 53% → **18%** |
## | 8 000 m/s（末段） | 1 231 m | 1 312 m | 53% → **3%** |
##
## ⇒ 它**不是手感**，是"这枚箭在往上冲，镜头被甩掉"——老板看到的正是这个。
## ⚠️ 而且它**长得像功能**：镜头确实在动、也确实"跟着"，只是越飞越远。
##
## 前馈（`want += v / _pos_lag()`）在这里**救不了**：火箭不是 `FlightBody`、没有 `fm`，
## `_target_velocity()` 恒回 `Vector3.ZERO`（同一件事在 `_rigid_eye()` 那段写过）。
##
## ## 与驾驶舱档的差别只有两条
##   · **姿态仍走 slerp**（保留一点点转向滞后 —— 拉近之后唯一的"手感"来源）。
##     重力转弯是 60 s 的平滑过程，稳态落后 `ω / rotate_lag` ≈ 0.6°，画面上读不出来。
##   · **抖动照旧施加**：发射段的 `LAUNCH_SHAKE_*` 是设计要求，而抖动的平移量
##     （`_shake * SHAKE_DEG_PER_UNIT * SHAKE_M_PER_DEG` ≤ 0.3 度 × 0.30 m）只有
##     零点几米 —— 对"距离恒定"是噪声级别，不是漂移。
func _rigid_chase() -> bool:
	return _launch_view and _launch_eye == LaunchEye.CHASE


## 当前是不是发射段机位（测试与探针读）。
func launch_view() -> bool:
	return _launch_view


func set_target(t: Node3D) -> void:
	set_head_look_active(false)
	head_look = Vector2.ZERO
	target = t
	_precision_blend = 0.0
	_precision_orbit_valid = false
	_precision_orbit_model = ""
	_precision_anchor_id = t.get_instance_id() if is_instance_valid(t) else 0
	_precision_anchor_position = t.global_position if is_instance_valid(t) else Vector3.ZERO
	_reset_thrust_motion()
	# ⚠️ 换机（= 每局开始）时把 FPV 混合量**直接落位**，不要从上一局的值渐变过去。
	# 设置页只在主菜单里开着，所以"上一局是座舱视角、这一局改了"是常态；
	# 而 `_physics_process` 在没有 target 时是**早退**的（混合量根本不更新），
	# 靠它自己收敛的话，新一局开局会先白送 0.2 秒的"从机体后面飘进座舱"。
	_fpv_blend = 1.0 if first_person else 0.0
	if t != null:
		global_position = _desired_position()
		if _thrust_enabled():
			global_position -= _target_velocity() / maxf(_pos_lag(), 0.001)
		global_transform = Transform3D(_desired_basis(), global_position)


# ---------------------------------------------------------------- 第一人称的几何

## 当前生效的位置跟随速率（FPV 下压到 `FPV_LAG`）。
func _pos_lag() -> float:
	return lerpf(lerpf(follow_lag,20.0,_precision_blend), FPV_LAG, _fpv_blend)


## 当前生效的姿态跟随速率。
func _rot_lag() -> float:
	return lerpf(lerpf(rotate_lag,26.0,_precision_blend), FPV_LAG, _fpv_blend)


## 座舱眼位（**机体局部坐标**）。
##
## ⚠️ **不许写成 `target as FlightBody`**：`FlightBody` 的子类 `PlayerController`
## 依赖 `ChaseCamera`，写死了就是循环依赖 —— 表现是
## `Could not parse global class ChaseCamera`，然后整个工程连锁编译失败
##（`_desired_basis()` 里那段注释记着同一个坑）。这里只用鸭子类型读一个方法名。
##
## 读不到就退回 `FPV_FALLBACK_EYE`：占位骨架模式下 `rig_anchor()` 一样可用，
## 所以"读不到"只可能发生在 target 是个裸 Node3D（测试里的哑目标）的时候。
func _fpv_eye_local() -> Vector3:
	var t := target
	if t == null or not is_instance_valid(t):
		return FPV_FALLBACK_EYE
	if t.has_method("rig_anchor"):
		var head: Vector3 = t.rig_anchor("head")
		if head.length_squared() > 0.0001:
			return head + Vector3(0.0, FPV_EYE_UP, -FPV_EYE_FWD)
	return FPV_FALLBACK_EYE


## 抖动补偿系数（见 `_fx_gain` / `_fx_pos_gain` 两个变量的注释）。
##
## `delta` 现取（`_physics_process` 每帧调它一次）：物理步长是可配的
##（本工程是默认的 60 Hz，但别把它写进代码），写死一个数值的话哪天步长一改，
## 这份补偿就静默偏掉。
##
## ⚠️ 旋转与位置**各算一遍**，因为两者回收速率不同（`_rot_lag()` vs `_pos_lag()`）。
func _update_fx_gain(delta: float) -> void:
	# FPV 每帧回收比例比追尾镜头大得多 ⇒ 同一个名义幅度在座舱里弱好几倍，
	# 倍数 = 两个回收比例之比。**幅度恒定**的通道（超级加速微晃、发射抖动）
	# 靠它精确对齐；**有限脉冲**的通道会各有偏差（方向不一、最多弱 3.6×）——
	# 逐条写清在 `FPV_LAG` 的表里，那是本轮明确接受的取舍。
	if _fpv_blend <= 0.0 or delta <= 0.0:
		_fx_gain = 1.0
		_fx_pos_gain = 1.0
		return
	var ratio_rot := (1.0 - exp(-_rot_lag() * delta)) / maxf(1.0 - exp(-rotate_lag * delta), 0.0001)
	var ratio_pos := (1.0 - exp(-_pos_lag() * delta)) / maxf(1.0 - exp(-follow_lag * delta), 0.0001)
	# 上限只是防呆（倍率异常时别把镜头抖飞）；60 Hz + 出厂参数下是 4.92 / 3.83。
	_fx_gain = lerpf(1.0, clampf(ratio_rot, 1.0, 12.0), _fpv_blend)
	_fx_pos_gain = lerpf(1.0, clampf(ratio_pos, 1.0, 12.0), _fpv_blend)


## 补偿是否真的在起作用（测试用；也是"补偿只该在 FPV 里生效"的读出口）。
func fx_gain() -> float:
	return _fx_gain


## 位置通道的补偿系数（测试用）。
func fx_pos_gain() -> float:
	return _fx_pos_gain


## 当前 FPV 混合量（测试用）。
func fpv_blend() -> float:
	return _fpv_blend


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.4)


## 命中正反馈（批 10 打击感）：玩家**打中**敌人时的一记短促镜头脉冲 ——
## FOV 快速扩张随即回落 + 一点轻抖。
##
## 之前镜头只回答"我挨了多少"（`add_hit_shake`），不回答"我打中了"：
## 军刀命中时玩家自己也在顿帧里，没有镜头反馈的话，"砍到了"只靠火花和音效说。
## 幅度刻意远小于受击（约 1/3 量级）—— 正反馈要"脆"，不能盖过受击的"痛"。
##
## ⚠️ `_fov_kick` 只存**未缩放**的量，倍率在 `_update_fov` 里乘 `motion_scale`
##（和 `_shake` 存未缩放量同一条规矩）：设置里"降低动态"或关抖动时这条也安静。
var _fov_kick := 0.0

func add_impact_pulse(strength := 1.0) -> void:
	if strength <= 0.0:
		return
	_fov_kick = minf(_fov_kick + 6.0 * strength, 10.0)
	add_shake(0.22 * strength)


## 受击反馈：按伤害占比给一次**定向推拒** + 一点随机抖。
##
## `amount_ratio` = 本次伤害 / 最大血量（0..1，由调用方算好 —— 相机不认识 max_hp）。
## `impact_dir_world` = **冲击传播方向** = "从伤害来源指向自机"，也就是弹丸飞行的方向。
##
## ⚠️ 方向约定一定要说清楚（我第一次就写反了）：
## 相机被推的方向 = `impact_dir_world` **本身**，即**背离来源**。
## 从正上方打来 ⇒ 冲击方向朝下 ⇒ 相机被**向下**推 —— 那才读得出"我从上方挨了一下"。
## 反过来（朝来源推）会变成"被打的时候往对手怀里飞"，方向信息是反的。
##
## `type` = `Damage.Type`，只用来查上面那两张权重表。
##
## ⚠️ **受击抖动不存在"绕过设置"的版本**：两条通道的幅度都在 `_apply_*` 里乘
## `shake_scale`（"镜头抖动=关" 与 "降低动态" 都让它为 0）。
## 这是无障碍要求，不是可选项 —— 受击抖动恰恰是晕动症最敏感的来源。
## 所以这里**存的是未缩放的量**，倍率只在施加时用（和 `_shake` 同一条规矩）。
## 护盾期挨打该怎么折成 `add_hit_shake()` 的占比（§4.9.2⑤）。
##
## ⚠️ **分母必须是护盾池**（`ifield_max`），不是机体血：这条通道量的是
## "这一发吃掉了护盾的百分之几"。拿机体血当分母，护盾厚的机（柯西 467）
## 与护盾薄的机（梅萨 120）会抖出**毫不相干**的幅度 —— 同一个数在两台机上
## 一个是"蹭了一下"、一个是"盾快没了"。
##
## ⚠️ 0.45 是**扫出来的**，不是推出来的。第一次我按"严重度线性映射到转角"
## 外推，取了 1.0，实测护盾期 0.602° 对掉血期 0.648° —— **几乎一样重**，
## 而设计要的是"护盾期挨打节奏长，所以要压低"。于是按
## `suite_camera_feedback._excursion()` 那套量法扫了一遍**画面峰值转角**
##（种子固定；柯西 467 的护盾池；一发 7 点光束）：
##
##     倍率 1.00 → 0.602°   倍率 0.80 → 0.484°   倍率 0.60 → 0.449°
##     倍率 0.45 → 0.322°  ← 掉血期 0.648° 的一半，且在阈值之上 ✅
##     倍率 0.30 → 0.266°   倍率 0.20 → 0.177°（掉到阈值 0.20 以下）
##
## 取 0.45：既踩着设计稿那个数，也实测落在"看得见、但明显轻于掉血期"的区间。
## ⚠️ 下界由测试钉住（护盾期 ≥ 掉血期的 35%），别再往小调 —— 那就是
## §4.9.4 那个"参数在动、画面不动"的坑。
##
## 换成护盾分母之后还多一个好处：**对不同机体自适应**。同样一发，
## 盾薄的机（梅萨 120）比盾厚的机（柯西 467）抖得更重 —— 这才是对的。
static func shield_hit_ratio(absorbed: float, ifield_max: float) -> float:
	# ⚠️ 没有护盾的机（训练靶 / 核心形态，`ifield_max == 0`）**根本走不到这里**
	#（`ifield_hit` 只在 `shield_used > 0` 时发，那要求护盾本来有值）。
	# 但这里不能退化成 `maxf(ifield_max, 1.0)` —— 那会把 10 点吸收量放大成
	# "吃掉 1000% 护盾"，一个永远不可能发生的输入却给到满幅抖动。
	if ifield_max <= 0.0:
		return 0.0
	return absorbed / ifield_max * HIT_SHIELD_MUL


func add_hit_shake(amount_ratio: float, impact_dir_world: Vector3, type: int) -> void:
	if amount_ratio <= 0.0:
		return
	var dir_w: float = HIT_DIR_WEIGHT.get(type, 0.6)
	var jit_w: float = HIT_JITTER_WEIGHT.get(type, 0.6)
	# ⚠️ `amount_ratio` 是**占比**（0.03 量级），不能直接当幅度用 ——
	# 先折成"挨了几下"的**严重度**（1.0 = 一次正常挨打）。见 `HIT_RATIO_REF` 的长注释：
	# 第一版就是漏了这一步，一发光束步枪实测不到 0.5 像素。
	var sev := clampf(amount_ratio / HIT_RATIO_REF, 0.0, HIT_SEV_MAX)
	var amp := sev * HIT_KICK_M          # 定向推拒，米
	var jitter := sev * HIT_JITTER_UNITS * jit_w   # 随机抖，抖动池单位

	# 到了节流窗口内：**只叠量、不触发新推拒**。
	if _hit_cd > 0.0:
		_kick = minf(_kick + amp * 0.35, KICK_MAX)
		_shake = minf(_shake + jitter * 0.35, HIT_SHAKE_MAX)
		return
	_hit_cd = HIT_SHAKE_MIN_INTERVAL_VULCAN if type == Damage.Type.VULCAN else HIT_SHAKE_MIN_INTERVAL
	_shake = minf(_shake + jitter, HIT_SHAKE_MAX)

	if dir_w <= 0.0 or impact_dir_world.length_squared() <= 0.0001:
		# 全向冲击（近炸）：**不给方向**，把幅度并进随机抖 ——
		# 否则这部分量会"落在一条没有方向的分量上"，等于白算。
		# ⚠️ 折进来的是**抖动池单位**（不是 `amp` 那些米）：两条通道换算率不同，
		# 拿米去加抖动池会把 `HIT_SHAKE_MAX` 一次性顶爆。
		_shake = minf(_shake + sev * HIT_JITTER_UNITS * jit_w * HIT_FUNNEL_FOLD,
			HIT_SHAKE_MAX)
		return
	_kick = minf(_kick + amp * dir_w, KICK_MAX)
	_kick_dir = (global_transform.basis.inverse() * impact_dir_world.normalized()).normalized()


## 发射后坐（**无方向**）。**按每一发离架调用**，不是每次扳机。
##
## ⚠️ 只**累加**、不直接改 `_shake`：三发浮游导弹是**同一帧**出去的
##（`fire_funnel()` 的循环），若在这里按调用次数节流，三次会被折成一次 ——
## 于是"打 3 发"和"打 100 发"读起来一样轻。真正落账在 `_flush_launch_shake()`。
func add_launch_shake(amount: float) -> void:
	if amount > 0.0:
		_launch_pending += amount


## 把累计的发射后坐按节流落进 `_shake`。
##
## 正常扳机（3 发同帧，间隔 0.42 s）⇒ 节流不生效，**每一发都能感觉到**；
## 全弹发射（20 发/秒）⇒ 恰好压着 `LAUNCH_SHAKE_MIN_INTERVAL` 走，
## 读成"持续的闷震"而不是抽筋。
func _flush_launch_shake(delta: float) -> void:
	_launch_cd = maxf(_launch_cd - delta, 0.0)
	if _launch_pending <= 0.0 or _launch_cd > 0.0:
		return
	_launch_cd = LAUNCH_SHAKE_MIN_INTERVAL
	# ⚠️ 封顶用 `LAUNCH_SHAKE_CEIL`（0.30），**不是** `_shake` 的击坠级上限 1.4 ——
	# 见那个常量的注释：发射是按发累加的，不另设一档就会一路爬到 1.4（抽筋）。
	_shake = minf(_shake + _launch_pending, LAUNCH_SHAKE_CEIL)
	_launch_pending = 0.0


## 切换锁定镜头。返回切换后的状态。
## 没有可锁的目标时**不允许进入**（否则会切进一个"盯着虚空"的镜头），
## 但允许随时退出 —— 退出永远是无条件可用的。
func set_lock_view(v: bool) -> bool:
	lock_view = v and has_lock_target()
	if not lock_view:
		_lock_blend = 0.0
	return lock_view


func toggle_lock_view() -> bool:
	return set_lock_view(not lock_view)


func has_lock_target() -> bool:
	return aim_target != null and is_instance_valid(aim_target)


## 当前**实际**处于锁定镜头（混合已经走起来）。
func lock_view_active() -> bool:
	return _lock_blend > 0.15


## Third-person camera uses world up even when the hull banks or rolls upside down.
## Clamp only the exact vertical singularity; retain the last heading at the poles.
func _horizon_basis(attitude: Basis) -> Basis:
	var forward := -attitude.z.normalized()
	var heading := Vector3(forward.x, 0.0, forward.z)
	if heading.length_squared() < 0.000001:
		heading = Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	if heading.length_squared() < 0.000001: heading = Vector3.FORWARD
	heading = heading.normalized()
	var pitch := clampf(asin(clampf(forward.y,-1.0,1.0)),deg_to_rad(-89.5),deg_to_rad(89.5))
	forward = heading*cos(pitch)+Vector3.UP*sin(pitch)
	return Basis.looking_at(forward, Vector3.UP)

func _follow_frame() -> Basis:
	var body := target.global_basis.orthonormalized()
	if _launch_view: return body
	return _horizon_basis(body).slerp(body,_fpv_blend).orthonormalized()

## A closer scope uses the actual hull extents, with space beside the sight line.
func _precision_shoulder_offset(frame: Basis, off: Vector3) -> Vector3:
	var bounds = target.get("model_bounds")
	if not bounds is AABB: return Vector3(off.x*1.2,off.y,off.z)
	var points: Array[Vector3] = []
	var lateral := off.x*1.2
	for corner in 8:
		var point: Vector3 = bounds.position+bounds.size*Vector3(float(corner&1),float((corner>>1)&1),float((corner>>2)&1))
		point = frame.inverse()*target.global_basis*(point-bounds.get_center())
		points.append(point)
		lateral = maxf(lateral,point.x+1.6)
	var tangent := tan(deg_to_rad(base_fov*0.65*0.5))
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x/maxf(size.y,1.0)
	var distance := off.z*0.80
	for point in points:
		distance = maxf(distance,point.z+absf(point.x-lateral)/(tangent*aspect*0.93))
		distance = maxf(distance,point.z+absf(point.y-off.y)/(tangent*0.93))
	return Vector3(lateral,off.y,maxf(off.z*0.80,distance))

func _precision_framed_direction(direction: Vector3) -> Vector3:
	var bounds = target.get("model_bounds")
	if not bounds is AABB: return direction
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x/maxf(size.y,1.0)
	var vertical := deg_to_rad(fov*0.5)*0.97
	var horizontal := atan(tan(deg_to_rad(fov*0.5))*aspect)*0.97
	var view := Basis.looking_at(direction,Vector3.UP)
	# Correct only the rectangular frustum overflow. A bounding-sphere fallback
	# changed modes at the wing edge and repeatedly snapped the view inward.
	for iteration in 2:
		for axis in 2:
			var center: Vector3 = view.inverse()*(target.global_transform*bounds.get_center()-global_position)
			var center_angle := atan2(center.x if axis == 0 else center.y,-center.z)
			var smallest := INF
			var largest := -INF
			for corner in 8:
				var point: Vector3 = bounds.position+bounds.size*Vector3(float(corner&1),float((corner>>1)&1),float((corner>>2)&1))
				point = view.inverse()*(target.global_transform*point-global_position)
				var angle := atan2(point.x if axis == 0 else point.y,-point.z)
				angle = center_angle+wrapf(angle-center_angle,-PI,PI)
				smallest = minf(smallest,angle)
				largest = maxf(largest,angle)
			var limit := horizontal if axis == 0 else vertical
			var lower := largest-limit
			var upper := smallest+limit
			var correction := clampf(0.0,lower,upper) if lower <= upper else (lower+upper)*0.5
			view = view.rotated(view.y if axis == 0 else view.x,-correction if axis == 0 else correction).orthonormalized()
	# Keep the sight line beside the rightmost hull edge throughout an orbit.
	var rightmost := -INF
	for corner in 8:
		var point: Vector3 = bounds.position+bounds.size*Vector3(float(corner&1),float((corner>>1)&1),float((corner>>2)&1))
		point = view.inverse()*(target.global_transform*point-global_position)
		rightmost = maxf(rightmost,atan2(point.x,-point.z))
	var gap := deg_to_rad(0.85)
	if rightmost > -gap:
		view = view.rotated(view.y,-(rightmost+gap)).orthonormalized()
	return -view.z

func _stabilize_third_person() -> void:
	if not first_person and _fpv_blend < 0.001 and not _launch_view:
		global_basis = _horizon_basis(global_basis)
		if _precision_active() and _precision_blend > 0.001:
			# Recheck after smoothing and shake, using this frame's actual eye position.
			global_basis = Basis.looking_at(_precision_framed_direction(-global_basis.z),Vector3.UP)


func _desired_position() -> Vector3:
	if target == null or not is_instance_valid(target):
		return global_position
	var lk := lerpf(_lock_blend, 0.0, _fpv_blend)
	var fr := lerpf(_frame_blend, 0.0, _fpv_blend)
	var off := offset
	if target is FlightBody and target.profile != null and target.profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL]:
		off = Vector3(0,36,135) if target.profile.id == SuitProfile.Id.NEUE_ZIEL else Vector3(0,30,120)
	# Bring the third-person camera 30% closer before blending to the cockpit eye.
	if not _launch_view:
		off *= 0.70
	if not _launch_view and not first_person:
		off = assist_side_offset(off, maxf(_assist_side_blend,_precision_blend) * (1.0-_fpv_blend))
	if _fpv_blend > 0.0:
		off = off.lerp(_fpv_eye_local(), _fpv_blend)
	var gunit := (1.0 if not _look_back else -1.6) if _fpv_blend <= 0.0 else 1.0
	var back := off.z * (1.0 + LOCK_VIEW_PULLBACK * lk)
	if _frame_blend > 0.0:
		var want_back := minf(framing_distance(_separation(), off.z), off.z * FRAME_MAX_MULT)
		back = lerpf(back, want_back, fr)
	if _thrust_enabled():
		var dynamics := clampf(motion_scale, 0.0, 1.0)
		back *= 1.0 + (0.04 * _thrust_boost + 0.07 * _thrust_super + 0.08 * _thrust_dash + 0.035 * _thrust_accel) * dynamics
		off.x -= _dash_direction.x * _thrust_dash * off.z * 0.035 * dynamics
		off.y -= _dash_direction.y * _thrust_dash * off.z * 0.020 * dynamics
	var want := target.global_position + _follow_frame() * Vector3(
		off.x, off.y + LOCK_VIEW_RISE * lk, back * gunit)
	# 速度前馈：没有它的话，一阶滞后会留下 v/follow_lag 的稳态距离，
	# 于是"飞得越快镜头掉得越远"，低速和高速的构图完全不同（实测 280 m/s 时差 43 m）。
	# 加上这一项，稳态零误差，但转弯时的滞后感全部保留。
	# ⚠️ 前馈的分母**必须跟着 `_pos_lag()` 走**。FPV 下沿用 `follow_lag` 会白送
	# 一个 `v / 6.5 ≈ 30 m` 的前置偏移，而那正好把眼位推回"没有模型的追尾机位" ——
	# 症状是"开了第一人称却感觉自己挂在机体后面"，且不报任何错。
	var feedforward := 1.0 / maxf(_pos_lag(), 0.001)
	if _thrust_enabled() and _thrust_step > 0.00001:
		# Exact discrete compensation avoids velocity-dependent forward drift.
		feedforward = _thrust_step / maxf(exp(_pos_lag() * _thrust_step) - 1.0, 0.00001)
	# Precision carries the previous eye by actual hull displacement before orbiting.
	# Velocity feedforward would place the orbit goal ahead of a fast cruise hull.
	if _precision_blend > 0.001 and not first_person and _fpv_blend < 0.001 and not _launch_view:
		feedforward = 0.0
	want += _target_velocity() * feedforward
	if _precision_orbit_valid and not first_person and not _launch_view:
		var framed := _precision_center()+_precision_orbit_frame*_precision_orbit_offset
		var center := _precision_center()
		var from := want-center
		var to := framed-center
		var blend := _precision_blend*(1.0-_fpv_blend)
		if from.length_squared() > 0.001 and to.length_squared() > 0.001:
			want = center+from.normalized().slerp(to.normalized(),blend)*lerpf(from.length(),to.length(),blend)
		else: want = want.lerp(framed,blend)

	# ---- ★ 发射段：机位**永不在海面之下** ----
	#
	# 上面那组 `LAUNCH_*` 数已经把相机放在 +44 m（箭底 −34 + 78）。这一道是**保险**，
	# 不是主要手段：它只在"箭比设计的还低"时才起作用（调吃水、改曲线起点、
	# 或者将来谁把 `rest_alt()` 往下挪）。
	#
	# ⚠️ 它为什么必须存在：**相机沉到水面之下不会报任何错**，而画面上
	# "什么都没有"与"这段演出没做出来"长得一模一样（`_rocket_shots` 那次
	# 全屏只有天空盒，就是同一类）。所以宁可在几何上把它挡死。
	# ⚠️ 判据读 `LaunchScript.BREACH_ALT`（= 海面），**不在这里另写一个 0**。
	if _launch_view:
		want.y = maxf(want.y, LaunchScript.BREACH_ALT + LAUNCH_MIN_ALT)
	return want


func set_look_back(v: bool) -> void:
	_look_back = v


func _target_velocity() -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	var v = target.get("fm")
	if v is FlightModel:
		return (v as FlightModel).velocity
	return Vector3.ZERO


# ---- ★ 轮 63-5：构图三件套的纯函数（批 3 §四）----
#
# 抽成 `static` / 小实例方法，为的是**能单测**：画面构图靠肉眼盯截图很容易漏，
# 而这几个都是"给定输入应当返回什么"的确定性问题（`suite_camera_feedback` 已钉死）。
# ⚠️ 判据必须能**无头**跑（§4.5：「本项必须能无头跑，否则不敢动相机」）——
# 下面没有任何 GPU / 视口**投影**调用，`_half_h_fov()` 只读视口**尺寸**，headless 可用。

## 半水平视场的一半（**弧度**）。⚠️ Godot 的 `fov` 是**垂直**角，水平方向要乘宽高比：
##     `h = atan(tan(fov/2) × aspect)`
## 宽高比从**运行时视口**读，不写死 16:9：写死的话在 16:10 的窗口上会把安全角
## 算成 50.17°（比真实的 47.18° 宽 3°）—— 自机于是**又出画了**，而且不报任何错。
## 读的是**当前** `fov`（会随速度张开）⇒ 超级加速时安全锥自然变宽。
func _half_h_fov() -> float:
	var aspect := 1.7777778
	var vp := get_viewport()
	if vp != null:
		var sz := vp.get_visible_rect().size
		if sz.y > 0.0001:
			aspect = sz.x / sz.y
	return atan(tan(deg_to_rad(fov * 0.5)) * aspect)


## 自机留框的安全角（弧度）= 半水平视场 × `SAFE_FRAC`。
func _safe_angle() -> float:
	return _half_h_fov() * SAFE_FRAC


## **纯函数**：把提前量向量 `lead` 的长度封顶到 `frac × distance`。
## 方向不变、长度只减不增 ⇒ 距离近时提前量按比例缩小，不会把视线甩出去。
static func lead_with_cap(lead: Vector3, distance: float, frac: float) -> Vector3:
	if frac <= 0.0 or distance <= 0.0:
		return Vector3.ZERO
	var l := lead.length()
	if l <= 0.000001:
		return Vector3.ZERO
	var cap := distance * frac
	if l <= cap:
		return lead
	return lead * (cap / l)


## **纯函数**：把基准视线点与两个"卫星点"（同框 / 锁定）按权重合成。
##
## 规则：卫星点取两者的**加权平均**、混入量取 `min(1, 权重和)`。
## ⚠️ 这条规则的可断言价值在于它**逐位保留单层情形**：
##     `compose(base, fp, w, _, 0) ≡ base.lerp(fp, min(1, w))`
## ⇒ 旧代码里"只有同框"与"只有锁定"两条路一个 bit 都没动（回归面最小），
## 而**两层同时在场**时不再互相覆盖。
## ⚠️ 旧写法是**顺序 lerp**（先同框、再锁定）：后写的锁定层把同框层整段覆盖 ——
## 实测（`tools/probe_cam_framing.gd`，把机位钉住后）"两个都开"与"只开锁定"的
## 视线方向**逐位相同 / 差 0.000000°** ⇒ 同框层等于死代码。
static func compose_look_point(base_pt: Vector3, frame_pt: Vector3, frame_w: float,
		lock_pt: Vector3, lock_w: float) -> Vector3:
	var sat_sum := 0.0
	var sat_pt := Vector3.ZERO
	if frame_w > 0.0:
		sat_sum += frame_w
		sat_pt += frame_pt * frame_w
	if lock_w > 0.0:
		sat_sum += lock_w
		sat_pt += lock_pt * lock_w
	if sat_sum <= 0.0:
		return base_pt
	return base_pt.lerp(sat_pt / sat_sum, minf(1.0, sat_sum))


## **纯函数**：若视线方向与"自机方向"的夹角 θ 超过安全角，把视线**连续地**
## 旋转回安全锥面上（保持长度）。θ ≤ 安全角时**逐位原样返回**。
##
## ⚠️ 必须**连续**：位移 = θ − 安全角 ⇒ θ→安全角 时位移→0。
## 硬截断（`if θ > safe: dir = 自机方向`）会在越过阈值的那一帧"啪"地跳一下 ——
## 那正是用户症状②投诉的"视角被一瞬间拉过去"。
static func force_in_frame(cam_pos: Vector3, player_pos: Vector3,
		look_point: Vector3, safe_rad: float) -> Vector3:
	var to_lp := look_point - cam_pos
	var to_p := player_pos - cam_pos
	if to_lp.length_squared() < 0.0000001 or to_p.length_squared() < 0.0000001:
		return look_point
	var ang := to_lp.angle_to(to_p)
	if ang <= safe_rad:
		return look_point
	var axis := to_lp.cross(to_p)
	if axis.length_squared() < 0.0000001:
		# 视线与自机方向共线（同向或反向）—— 绕任一垂直轴结果等价
		axis = to_lp.cross(Vector3.UP)
		if axis.length_squared() < 0.0000001:
			axis = to_lp.cross(Vector3.RIGHT)
	axis = axis.normalized()
	# 绕 (to_lp × to_p) **正向**转 (θ − 安全角)：右手定则下这样转是把 `to_lp`
	# 朝 `to_p` 靠。⚠️ 方向写反的话自机会**更**出画，而且断言很可能照绿 ——
	# 所以这里钉的是几何（θ 旋转后必须**等于**安全角），不是"看着像"。
	return cam_pos + (Basis(axis, ang - safe_rad) * to_lp)


## 锁定视线的提前量（世界向量）：`敌机速度 × LOCK_LEAD_TIME`，再按距离封顶。
## ⚠️ 提前量是个**绝对长度**：2000 m/s 的横移就是 500 m，在 1 km 处相当于
## 25.6° 的视线甩动 ⇒ 敌机一改向，视线被拽着走（症状②的"一瞬间拉过去"）。
## 封顶到 `LEAD_DIST_FRAC × 距离` 后，同样的速度在 1 km 处最多甩 atan(0.25) = 14.0°。
func _lead_vector() -> Vector3:
	if aim_target == null or not is_instance_valid(aim_target):
		return Vector3.ZERO
	var fmv = aim_target.get("fm")
	if not (fmv is FlightModel):
		return Vector3.ZERO
	var d := global_position.distance_to(aim_target.global_position)
	return lead_with_cap((fmv as FlightModel).velocity * LOCK_LEAD_TIME, d, LEAD_DIST_FRAC)


func _desired_basis() -> Basis:
	var t := target
	if t == null or not is_instance_valid(t):
		return global_transform.basis
	var t_up: Vector3 = t.global_transform.basis.y
	# FPV：锁定镜头 / 双机同框**一起退场**（同 `_desired_position()`）。
	# ⚠️ 注意这里**不动 `roll_mix`** —— 眼位长在机体头上，"地平线跟着机体滚"是
	# 物理事实，而 `roll_blend` 是玩家明确设过的无障碍旋钮。进 FPV 就把它无视掉
	# 是越权：想更稳的玩家本来就该把设置里的「镜头滚转」调到"保持水平"，
	# 而那一个旋钮同时管住两种视角 —— 比"FPV 里再压一档"更好解释。
	var lk := lerpf(_lock_blend, 0.0, _fpv_blend)
	var fr := lerpf(_frame_blend, 0.0, _fpv_blend)
	var roll_mix := roll_blend
	# 锁定镜头里把"跟机体滚"压下去：盯着目标转的时候天地还在转，两秒就晕了。
	# 混合量走多少，滚转就跟世界走多少 —— 于是进出锁定镜头的过渡是连续的。
	roll_mix = lerpf(roll_blend, 0.16, lk)
	var want_up := Vector3.UP.lerp(t_up, roll_mix if (_fpv_blend > 0.0 or _launch_view) else 0.0)
	if want_up.length_squared() < 0.001:
		want_up = Vector3.UP
	want_up = want_up.normalized()

	var look_point: Vector3 = t.global_position + (-t.global_transform.basis.z) * look_ahead \
			+ Vector3.UP * look_up
	if not first_person and not _launch_view:
		look_point += _follow_frame().x * offset.z * 0.70 * 0.24 * maxf(_assist_side_blend,_precision_blend) * (1.0-_fpv_blend)
	if aim_target != null and is_instance_valid(aim_target) and aim_bias > 0.0:
		look_point = look_point.lerp(aim_target.global_position, aim_bias)
	# 锁定镜头：把视线从"机头前方"拉到"锁定目标身上"（带一点提前量，不然高机动目标
	# 会一直贴在屏幕边缘）。这一层是在 aim_bias 之后叠加的，所以两套偏移不会互相打架。
	#
	# ⚠️ 这里**不能写 `aim_target as FlightBody`**：那会让镜头依赖 FlightBody，
	# 而 FlightBody 的子类 PlayerController 又依赖 ChaseCamera —— 一个循环依赖，
	# 表现是"Could not parse global class ChaseCamera"，然后整个工程连锁编译失败。
	# 只用鸭子类型读 `fm`（和 `_target_velocity()` 同一套写法），依赖就断开了。
	#
	# ---- ★ 轮 63-5：两个"卫星点"**加权合成**，不再"后写覆盖" ----
	#
	#   · 同框点 = 自机与敌机的**中点**（辅助驾驶"两者都在画面里"）；
	#   · 锁定点 = 敌机位置 + **距离封顶**的提前量（盯住敌机）。
	# 合成规则与"单层逐位退化"的保证都在 `compose_look_point()` 里。
	var part: Node3D = _frame_partner()
	var frame_w := fr if part != null else 0.0
	var lock_w := lk if has_lock_target() else 0.0
	# 辅助驾驶下 `frame_both` 与 `set_lock_view` **同时为真**，不钳的话锁定层
	# 权重 1.0 会把视线整个拽到敌机身上、同框层一点份额都留不下（见 ASSIST_LOCK_CAP）。
	if frame_w > 0.0:
		lock_w = minf(lock_w, ASSIST_LOCK_CAP)
	var frame_pt := Vector3.ZERO
	if part != null:
		frame_pt = (t.global_position + part.global_position) * 0.5
	var lock_pt := Vector3.ZERO
	if lock_w > 0.0:
		lock_pt = aim_target.global_position + _lead_vector()
	look_point = compose_look_point(look_point, frame_pt, frame_w, lock_pt, lock_w)
	var precision_focus := _precision_focus()
	if precision_focus != null:
		look_point=look_point.lerp(precision_focus.global_position,_precision_blend*(1.0-_fpv_blend))


	# ---- ★ 安全角：自机必须留在画面里（轮 63-5 新增）----
	#
	# 根因与实测量见 `SAFE_FRAC` 那段注释：锁定锥角 55° > 半水平视场，
	# 没有这道约束时自机偏角峰值 54.96°（出画判定线 47.18° @16:10）⇒ 必然出画。
	# ⚠️ `force_in_frame()` 是**连续**的软钳（θ→安全角 时位移→0），不是硬截断。
	#
	# ⚠️⚠️ **这道约束对所有第三人称路径统一生效**，**包括"只有锁定层"那一路** ——
	# `player_controller._tick_assist()` 在**平移模式**下正是
	# `frame_both = false` + `set_lock_view(true)`，那恰恰就是用户症状②
	#（"辅助驾驶下锁定目标大幅机动时自机突然消失"）的现场；手动 Alt 锁定走同一条。
	#
	# ⚠️ 曾经写过一个给"手动锁定"开豁免的版本
	#（`guard = 1 − _lock_blend × (1 − _frame_blend)`，理由是 `notes/04` 把
	#  "盯住敌机、自机可被甩出"写成过设计），后来**删掉**了，两个原因：
	#   ① 用户把这件事当 **bug** 报了上来，而"辅助驾驶"与"手动 Alt 锁定"
	#      在相机这一层是**同一条路**，豁免等于漏掉症状②的主现场；
	#   ② 那个 `guard` 会在"辅助驾驶关闭"的那一帧从 1 直接掉到 0 ⇒ 视线
	#      **瞬间**从锥面弹回锁定点（最多 26°），正是本项要治的那种跳。
	# 统一生效反而一路连续：进锁定视角时 `_lock_blend` 自己往上爬，
	# 安全角跟着**渐进**接管。
	#
	# FPV 仍然让开：座舱里"自机在不在画面里"没有意义，而且 `dir` 随后会被整段
	# 换成机头方向。
	var guard := 1.0 - _fpv_blend
	if guard > 0.0:
		look_point = look_point.lerp(
			force_in_frame(global_position, t.global_position, look_point, _safe_angle()),
			guard)

	var dir := global_position.direction_to(look_point)
	if dir.length_squared() < 0.0001:
		dir = -t.global_transform.basis.z
	if _precision_orbit_valid and not first_person and not _launch_view:
		var point := _precision_center()-_precision_orbit_frame.z*_precision_orbit_depth
		dir = dir.slerp(global_position.direction_to(point),_precision_blend).normalized()
		dir = _precision_framed_direction(dir)
	else:
		var free_scope := _precision_free_direction()
		if free_scope.length_squared() > 0.5:
			dir = dir.slerp(free_scope,_precision_blend).normalized()
			dir = _precision_framed_direction(dir)

	# FPV：视线**沿机头方向**。
	# 座舱里"往哪看"就是机头往哪 —— 追尾镜头那个"看向机头前方 36 m、再抬高 2.6 m"
	# 的人造点，在 FPV 下会变成一个固定的俯仰偏角（眼位比机体中心低，偏角约 9°），
	# 表现是准星和机头分家、抬头/低头都差着一格。直接给机头方向。
	if _fpv_blend > 0.0:
		var head_basis := head_look_basis(t.global_transform.basis)
		dir = dir.slerp((-head_basis.z).normalized(), _fpv_blend)
		var head_up := Vector3.UP.lerp(head_basis.y,roll_mix).normalized()
		if head_up.length_squared()<0.000001: head_up = head_basis.y
		want_up = want_up.lerp(head_up,_fpv_blend).normalized()
	var facing := preload("res://scripts/flight/flight_frame.gd").facing(dir,global_basis,want_up)
	return _horizon_basis(facing) if (not _launch_view and _fpv_blend < 0.001 and not first_person) else facing


## 按**当前地图**切换远裁面（轨道图要容得下地球的剪影，90 km 远远不够）。
##
## ## 这笔几何账（不是我拍脑袋给的 1e7）
## 玩家在 550 km 高、地球半径 6 371 km ⇒ 几何地平线距离
## `sqrt(2Rh + h²) = sqrt(2×6371×550 + 550²) ≈ 2 647 km`。
## **90 km 的远平面会在 29 倍处把地球整个切掉** —— 表现是"向下看什么都没有"，
## 与改前那块纯色**看起来一模一样**；而探针那边只会告诉你"地球节点存在"
##（它确实存在，只是没被画出来）—— 一条**沉默的**失败。
##
## ⚠️ `far = 1e7` 之下深度精度**够用**：Godot 用反向 Z + 浮点深度缓冲，精度集中在近处；
## 46 km 外的碎片带在 `near = 1.2` 下仍留得住（实机出图逐像素可辨）。
## ⚠️ **只在无地面图上放开** —— 五张地表图的 90 km 一个字不动（它们的雾与远裁面是配好的）。
func _sync_depth_range() -> void:
	var m: MapDef = Game.active_map
	if m == _depth_map:
		return
	_depth_map = m
	far = ORBIT_FAR if (m != null and not m.has_ground) else GROUND_FAR


## 相机往前走**一步**。**唯一实现** —— `_physics_process()` 只是它的一条调用路径。
##
## ## ★ 为什么把它挖出来（老板：「**现在的镜头还是很抽搐**」）
## 相机的位置与姿态是**每一帧按目标机的 `global_transform` 算出来的**：
##     `want_pos = target.global_transform * offset`
## ⇒ "相机没抖"这件事**完全依赖"算 want 用的那个 target 变换"和"这一帧画出去的
##   target 变换"是同一个**。而本工程里这两个曾经常在不同帧：
##
## | 谁 | 在哪个回调里 | 时钟 |
## |---|---|---|
## | 火箭 `rocket.step()` | `main._process()` ⇒ `_tick_launch()` | **渲染帧**（可变 dt） |
## | 相机落位 | `ChaseCamera._physics_process()` | **固定 60 Hz** |
##
## 一帧里 Godot 的次序是「先物理、后 `_process`、再画」。于是画出去的那一帧里：
##   相机 = 火箭(**上一帧 `_process` 结束时的**)位置 + offset
##   火箭 = 火箭(**这一帧 `_process` 结束时的**)位置
## 两者的差 = `v · Δt_相位`。60 Hz 显示器上两钟同拍（Δ 恒定）⇒ 看不出来；
## 但渲染帧率一旦不是 60 的整数倍（120 / 144 / 165 Hz，本工程 vsync 默认开），
## 每帧的 Δt_相位**在 0 与一个物理步之间来回跳** ⇒ 那个差逐帧突变。
##
## 量级：末段 `v ≈ 33 km/s`，物理步 16.7 ms ⇒ **一跳 550 m**，
## 而机体长 58 m、镜头离它 80.9 m ⇒ 机体在画面里一帧内甩出视轴几十度。
## 那正是"抽搐"，而且**箭越快越抽**、帧率越高越抽。
##
## ## 修法：发射段整段用**一个钟**
## `main._begin_launch()` 把 `externally_stepped` 置真 ⇒ `_physics_process` 让路，
## 由 `_tick_launch()` 在**渲染帧**里、紧跟 `rocket.step()` 之后显式调用本函数。
## 于是同一帧内"算 want 的 target"与"画出去的 target"逐位相同 ⇒ 相对位移恒为 0。
##
## ⚠️ 别改成"把火箭搬去 `_physics_process`"那条路：那要把
## `physics/common/physics_interpolation` 打开才能不顿，而那是一个**全工程**的
## 渲染开关，会顺手改掉整个战斗段的观感 —— 为一个 60 s 的演出不值。
func step_now(delta: float) -> void:
	# ⚠️ **必须摆在早退之前**：没有 target 时（主菜单 / 换图那一帧）远平面照样要跟上，
	# 否则"相机已经建好、target 还没设"的那几帧会把地球裁掉。
	_sync_depth_range()
	_step_head_look(delta)
	if target == null or not is_instance_valid(target):
		return

	_precision_blend = move_toward(_precision_blend, 1.0 if _precision_active() else 0.0, delta/0.30)
	_assist_side_blend = move_toward(_assist_side_blend, 1.0 if _assist_side_active() else 0.0, delta / 0.65)
	_step_thrust_motion(delta)

	# 第一人称的进 / 出。**摆在跟随之前**：同一帧里混合量先到位，
	# 下面算 `want_pos` / `want_basis` 用的才是这一帧的档位。
	_fpv_blend = move_toward(_fpv_blend, 1.0 if first_person else 0.0, FPV_RATE * delta)
	_advance_precision_anchor()

	# 锁定丢失 → 自动退出锁定镜头（见 lock_view 的注释）
	if lock_view and not has_lock_target():
		lock_view = false
	var want_blend := 1.0 if (lock_view and has_lock_target()) else 0.0
	_lock_blend = move_toward(_lock_blend, want_blend, LOCK_VIEW_RATE * delta)
	# 辅助驾驶的构图：没有可框的敌机就自动退回追尾视角（和锁定镜头同一条规矩）
	var want_frame := 1.0 if (frame_both and has_lock_target() and _frame_partner() != null) else 0.0
	_frame_blend = move_toward(_frame_blend, want_frame, FRAME_RATE * delta)
	_step_precision_orbit(delta)

	# ⚠️ 跟随速率走 `_pos_lag()` / `_rot_lag()`（FPV 下压到 `FPV_LAG`）。
	# 写死 `follow_lag` 的话，座舱视角会带着 200 m/s ÷ 6.5 ≈ 30 m 的稳态滞后，
	# 玩家看到的是"一台隐形的机体的追尾机位"。
	var want_pos := _desired_position()
	var want_basis := _desired_basis()

	# ---- ★★ 刚性眼位（驾驶舱）：硬落位 + 跳过全部抖动 ----
	#
	# 理由全在 `_rigid_eye()` 那段（火箭没有 `fm` ⇒ 前馈恒 0 ⇒ 弹簧会落后 1 167 m）。
	# ⚠️ 抖动池**照旧排空**（不在下面那三行 `_apply_*` 里做，要在这里显式做）：
	# 不排的话，出舱那一刻会把舱里攒下的抖动分一次性放出来 ——
	# 与 `_apply_shake` 里"倍率是 0 时衰减照走"那条规矩是同一条。
	if _rigid_eye():
		global_transform = Transform3D(want_basis, want_pos)
		_hit_cd = maxf(_hit_cd - delta, 0.0)
		_flush_launch_shake(delta)
		_shake = maxf(_shake - delta * 2.4, 0.0)
		_wob_amount = 0.0
		_update_fov(delta)
		_update_fx_gain(delta)
		return

	# ---- ★ 刚性追尾（发射段舱外档）：位置硬落位，姿态仍走 slerp ----
	#
	# 理由全在 `_rigid_chase()` 那段（老板：「相机要一直和火箭保持一个距离」）。
	# ⚠️ 位置**必须在最前面硬写**，不能"先 lerp 再补"：`_apply_shake` / `_apply_kick`
	# 都会往 `global_position` 上加量，那样一帧就会把上一帧的抖动累进位置里。
	# 先落位、再叠这一帧的抖动 ⇒ 抖动是零均值的噪声，不产生漂移。
	if _rigid_chase():
		global_position = want_pos
		# ★★ 眼位**先落位、再算视线**：`_desired_basis()` 读的就是 `global_position`。
		#
		# ⚠️ 反过来写（用上面那个在 `want_pos` 之前就算好的 `want_basis`）在**战斗速度**
		# 下看不出来 —— 那里 `global_position` 与 `want_pos` 只差几米。
		# 但发射末段会烂掉：那一对 `want_*` 是在 `global_position` **还是上一帧的眼位**
		# 时算的，而 `target` 是**这一帧**的 ⇒ 视线瞄的是"上一帧眼位 → 这一帧箭心"，
		# 而相机站的是这一帧的位置。14 km/s 下每帧差 **217 m**，
		# 于是视线被抬到一枚**根本不在那儿**的火箭方向上。
		#
		# 实测（`tools/_launch_cam_probe.gd` 的 `B60`）：
		# **偏离视轴 115°**（箭早就飞出画面了），而 `dist` 仍是精确的 **80.92 m**。
		# ⇒ 这是一条"**位置对、视线错**"的失败：任何只看距离的判据一个字都抓不到它。
		var chase_basis := _desired_basis()
		global_transform = Transform3D(
			global_transform.basis.slerp(chase_basis,
				1.0 - exp(-_rot_lag() * delta)).orthonormalized(),
			global_position)
		_update_fov(delta)
		_update_fx_gain(delta)
		_hit_cd = maxf(_hit_cd - delta, 0.0)
		_flush_launch_shake(delta)
		_apply_shake(delta)
		_apply_kick(delta)
		_apply_super_wobble(delta)
		return

	var follow := 1.0-exp(-_pos_lag()*delta)
	if _precision_orbit_valid and not first_person and not _launch_view:
		# The rig already smooths its orbit and distance; avoid a second, lagging orbit.
		global_position = global_position.lerp(want_pos,lerpf(follow,1.0,_precision_blend))
	else:
		global_position = global_position.lerp(want_pos,follow)

	if _thrust_enabled():
		# Aim from the actual new eye position, not last frame's camera position.
		want_basis = _desired_basis()

	global_transform = Transform3D(
		global_transform.basis.slerp(want_basis, lerpf(1.0-exp(-_rot_lag()*delta),1.0,_precision_blend) if _precision_orbit_valid else 1.0-exp(-_rot_lag()*delta)).orthonormalized(),
		global_position)

	_update_fov(delta)
	_update_fx_gain(delta)
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	_flush_launch_shake(delta)
	_apply_shake(delta)
	_apply_kick(delta)
	_apply_super_wobble(delta)
	_stabilize_third_person()


## 物理帧那条路。`externally_stepped` 为真时**整段让路**（发射段自己在渲染帧里调
## `step_now()`）。见那里的头注 —— 让路不是优化，是"一帧只落一次位"的保证：
## 两边都跑的话，同一帧里相机先被物理帧按**旧**的 target 落一次、
## 再被 `_tick_launch()` 按**新**的落一次，抖动只是换了个相位，一点没少。
func _physics_process(delta: float) -> void:
	if externally_stepped:
		return
	step_now(delta)


## 目标机是否处于超级加速（0/1）。鸭子类型读 fm —— `_update_fov` 与
## `_apply_super_wobble` 共用这一份判据，不会出现"FOV 开了晃没开"的分裂。
func _super_amount() -> float:
	var t := target
	if t == null or not is_instance_valid(t):
		return 0.0
	var fmv = t.get("fm")
	if fmv is FlightModel:
		var fm := fmv as FlightModel
		if fm.boosting and fm.super_boost:
			return 1.0
	return 0.0


## 超级加速的**持续**微晃（批 12，用户要求"来点镜头小晃动"）。
##
## 三个轴各走一条不同频率的正弦 —— 平滑、循环、永不相消，
## 读成"推进器在持续震"，与 `_apply_shake` 的随机抖（"挨了一下"）质感分开。
## `_wob_amount` 渐入渐出（SUPER_WOBBLE_RAMP），进/出都不跳变。
##
## ⚠️ 无障碍与 `_apply_shake` 同一条规矩：`shake_scale = 0`（关镜头抖动）时
## **位移照乘 0、渐出照走** —— 玩家把抖动从关调回标准的那一瞬间，
## 不能凭空吃出一记满幅晃动。
func _apply_super_wobble(delta: float) -> void:
	var want := _super_amount()
	_wob_amount = move_toward(_wob_amount, want, SUPER_WOBBLE_RAMP * delta)
	if _wob_amount <= 0.0:
		return
	_wob_phase += delta
	var a := _wob_amount * SUPER_WOBBLE_DEG * _fx_gain
	var t := _wob_phase
	var rot := Basis()
	rot = rot.rotated(Vector3.RIGHT, deg_to_rad(sin(t * 9.0) * a))
	rot = rot.rotated(Vector3.UP, deg_to_rad(sin(t * 7.3 + 1.7) * a))
	rot = rot.rotated(Vector3.BACK,
		deg_to_rad(sin(t * 11.7 + 3.9) * a * SUPER_WOBBLE_ROLL_MUL))
	if shake_scale > 0.0:
		global_transform.basis = (global_transform.basis * rot).orthonormalized()
		# 副通道：极小的平移配重（与主抖通道 SHAKE_M_PER_DEG 的思路一致）。
		# ⚠️ 位置用**自己的**倍率 `_fx_pos_gain`（它按 `_pos_lag()` 回收，
		# 与旋转的 `_rot_lag()` 不是同一个速率），所以这里从名义量重新乘一遍，
		# 不能在 `a` 上再叠 —— `a` 已经含了旋转倍率。
		var amp := _wob_amount * SUPER_WOBBLE_DEG * _fx_pos_gain * SHAKE_M_PER_DEG
		global_position += Vector3(
			sin(t * 8.1 + 0.9) * amp, sin(t * 6.7 + 2.3) * amp, 0.0)


func _update_fov(delta: float) -> void:
	var t := target
	var sp := 0.0
	if t != null and is_instance_valid(t):
		if t.has_method("speed_fov_mix"):
			# ★ 目标**自报**速度项（0…1）。给"速度跨数量级"的目标用：
			#   发射段 0 → 126 000 km/h，而下面那条通用窗口只有 300…1900 km/h
			#   ⇒ 会在第 8 s 顶死、之后 44 s 一动不动。实现与实测见
			#   `RocketBody.speed_fov_mix()` / `tools/_launch_fov_probe.gd`。
			#   只有 `RocketBody` 定义了这个方法 ⇒ 机体那一路逐字节不变。
			sp = clampf(t.speed_fov_mix(), 0.0, 1.0)
		elif t.has_method("airspeed_kmh"):
			sp = clampf((t.airspeed_kmh() - 300.0) / 1600.0, 0.0, 1.0)
	# 超级加速档（批 11）：鸭子类型读 fm（与 `_target_velocity()` 同一条规矩，
	# 不让相机依赖 FlightBody 类型 —— 循环依赖的坑见 `_desired_basis`）。
	var super_amt := _super_amount()
	# 加速模式除了速度本身，再额外拉一档视野 —— 这是"变广角"最直接的表达。
	# 超级加速在它之上再叠一档（FOV_SUPER_BONUS）。
	# `motion_scale = 0`（设置里的"降低动态"）时三项动态一起关掉：FOV 恒定。
	# `_fov_kick`（命中脉冲）同样乘 `motion_scale` —— 无障碍同一条铁律。
	#
	# ⚠️ FPV 再压一道（`FPV_FOV_DYN`），但**只压"随速度张开"的那三项**。
	# `_fov_kick` 不压：那是"我打中了"的正反馈，压它等于把打击感一起压掉
	#（和 `_apply_shake` 里"受击反馈不许绕过设置、但也不许被顺手削弱"是同一条规矩）。
	var dyn := motion_scale * lerpf(1.0, FPV_FOV_DYN, _fpv_blend)
	var want := base_fov + (fov_per_speed * sp + fov_boost_bonus * boost_amount
		+ FOV_SUPER_BONUS * super_amt) * dyn \
		+ _fov_kick * motion_scale
	var fov_rate := 3.5
	if _thrust_enabled():
		want = base_fov + (14.0 * sp + 10.0 * _thrust_boost + 12.0 * _thrust_super + 4.0 * _thrust_dash) * dyn
		want = minf(want, maxf(base_fov, THRUST_MAX_FOV)) + _fov_kick * motion_scale
		fov_rate = 6.0 if want > fov else 3.5
	want = lerpf(want,base_fov*0.65,_precision_blend)
	fov = lerpf(fov, want, 1.0 - exp(-fov_rate * delta))
	# 命中脉冲的衰减：指数快收（~0.3 s 回落），读成"一记短促的扩张"。
	_fov_kick *= exp(-9.0 * delta)
	if _fov_kick < 0.01:
		_fov_kick = 0.0


func _apply_shake(delta: float) -> void:
	if _shake <= 0.0:
		return
	# ⚠️ 抖动的**衰减照走**，即使倍率是 0：只把位移乘 0 而让 `_shake` 停在满值，
	# 玩家把"镜头抖动"从关调成标准的那一瞬间会立刻吃到一次满幅抖动。
	if shake_scale <= 0.0:
		_shake = maxf(_shake - delta * 2.4, 0.0)
		return
	# ---- 主通道：**旋转**（与距离无关，见 `SHAKE_DEG_PER_UNIT` 的长注释）----
	#
	# 三个轴各自独立随机。用局部坐标（`rotated()` 右乘 = 后乘 = 在自身坐标系里转），
	# 所以"抖的方向"跟着镜头走，不会在相机滚转时变成绕世界轴乱翻。
	#
	# `_fx_gain`：FPV 下补回"刚性贴合丢掉的残留累加"（见 `FPV_LAG` 的注释）。
	# 它是**幅度**倍率，与 `shake_scale` 并列；无障碍的闸门仍然是 `shake_scale`。
	var deg: float = _shake * SHAKE_DEG_PER_UNIT * shake_scale * _fx_gain
	var rot := Basis()
	rot = rot.rotated(Vector3.RIGHT, deg_to_rad(randf_range(-deg, deg)))   # 俯仰
	rot = rot.rotated(Vector3.UP, deg_to_rad(randf_range(-deg, deg)))      # 偏航
	rot = rot.rotated(Vector3.BACK, deg_to_rad(randf_range(-deg * SHAKE_ROLL_MUL,
		deg * SHAKE_ROLL_MUL)))                                            # 滚转
	global_transform.basis = (global_transform.basis * rot).orthonormalized()

	# ---- 副通道：留一点平移当"配重"（免得读成"镜头在云台上转"）----
	# ⚠️ 位置用**自己的**倍率 `_fx_pos_gain`（按 `_pos_lag()` 回收），理由见那个变量；
	# 所以这一行从名义量重新乘，不能直接拿 `deg`（它已含旋转倍率 `_fx_gain`）。
	var amp: float = _shake * SHAKE_DEG_PER_UNIT * shake_scale * _fx_pos_gain * SHAKE_M_PER_DEG
	global_position += Vector3(
		randf_range(-amp, amp), randf_range(-amp, amp), randf_range(-amp, amp))
	_shake = maxf(_shake - delta * 2.4, 0.0)


## 定向推拒的施加（受击专用，见 `add_hit_shake()`）。
##
## ⚠️ 与 `_apply_shake()` **同一条规矩**：倍率为 0 时**衰减照走**。
## 只把位移乘 0 而让 `_kick` 停在满值，玩家把"镜头抖动"从关调成标准的那一瞬间
## 会立刻吃到一次满幅推拒 —— 和 `_apply_shake()` 里注释点名的那个坑一模一样。
func _apply_kick(delta: float) -> void:
	if _kick <= 0.0:
		return
	if shake_scale > 0.0 and _kick_dir.length_squared() > 0.0001:
		# ⚠️ `_kick_dir` 存的是**相机局部坐标**（见 `add_hit_shake()`），
		# 所以施加前**必须**用当前 basis 转回世界。
		# 第一版直接把局部向量加到 `global_position` 上 —— 那个方向只在"相机恰好轴对齐"
		# 时才是对的，而追尾镜头的 basis 几乎从来不是单位阵。
		# 这个错**在把相机放进场景树之前一直看不出来**：不进树时 `global_transform`
		# 读出来恒为单位阵，存取两端一起错、正好抵消（实测滚 90° 后还原出 (0,1,0) 而非 (1,0,0)）。
		#
		# ⚠️ **先平移、后旋转**，顺序不能换：平移量要落在"当初记账时可用的那个 basis"上。
		# 先转再平移的话，推拒方向会被自己刚转出来的那个角带偏，而且
		# `suite_camera_feedback` 里"位移落在还原后的世界方向上"那条会跟着漂。
		var world_push := (global_transform.basis * _kick_dir)
		# 位置用 `_fx_pos_gain`（按 `_pos_lag()` 回收），旋转用 `_fx_gain`（`_rot_lag()`）。
		global_position += world_push * _kick * shake_scale * _fx_pos_gain

		# ---- 主通道：**绕推拒方向的垂轴旋转**（受击的方向感就来自这个转角）----
		#
		# 轴 = 推拒方向 × 镜头前向。推拒朝局部 +X（被打者的右边）时，轴落在 ±Y 上
		# ⇒ 镜头**偏航**：视角被推离来弹，画面里被打的那一侧向后掠过去。
		#
		# ⚠️ **本帧转角必须由"本帧消耗掉的推拒量"算，不能由 `_kick` 的当前值算。**
		# `_physics_process` 每帧都会把 basis 往 `want_basis` slerp 回去
		# （`rotate_lag = 5`、60 Hz ⇒ 每帧只回收 8.00%，残留 92.00%），所以"每帧都按当前值转一个角"
		# 会被这个残留**累加**成 `1/(1-0.92) = 12.5 倍`的稳态偏角 ——
		# 一次撞机实测会滚出近 20° 的持续偏航，镜头看起来是"被拧住了"，不是"被撞了一下"。
		# 改成按"消耗量"记账 ⇒ 整段推拒的总转角 = `初始推拒量 × KICK_DEG_PER_M`，
		# 有界、可预测、和 `_kick` 的衰减速率无关。
		var spent := _kick - maxf(_kick - delta * KICK_DECAY, 0.0)
		var axis := _kick_dir.cross(Vector3.BACK)
		if axis.length_squared() < 0.0001:
			# 推拒方向与镜头前向重合（正后方/正前方打来）⇒ 叉积退化。
			# 这时改用"绕右轴俯仰"，读成被顶了一下，而不是干脆不转。
			axis = Vector3.RIGHT
		var deg: float = spent * KICK_DEG_PER_M * shake_scale * _fx_gain
		if deg > 0.0:
			global_transform.basis = (global_transform.basis
				* Basis(axis.normalized(), deg_to_rad(deg))).orthonormalized()
	_kick = maxf(_kick - delta * KICK_DECAY, 0.0)


## HUD 用来判断某个世界坐标是否在视野里。
func is_in_front(world_pos: Vector3) -> bool:
	return global_transform.basis.z.dot(global_position.direction_to(world_pos)) < 0.0
