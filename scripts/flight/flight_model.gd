class_name FlightModel
extends RefCounted
## 街机化飞行模型（Ace Combat 手感）—— 整个游戏手感的地基。
##
## 决定手感的四件事：
##   1. **机头姿态与速度矢量分离**：速度矢量以 velocity_follow 的速率滞后追随机头，
##      急转时会有"甩尾"。这是玩家能"感觉到能量"的前提。
##   2. **升力随速度衰减**：速度低于 lift_ref_speed 开始下沉，低速时必须靠俯冲补速度。
##   3. **重力沿航迹做功**：爬升掉速、俯冲加速，由 gravity_energy 放大成街机手感。
##   4. **舵效随速度变化**：速度越低舵越软；失速时舵效骤降且机头自动下坠。
##
## 坐标与符号约定（Godot：+X 右，+Y 上，−Z 前）：
##   input = Vector3(pitch, yaw, roll)，三者均在 −1..1
##     pitch 正 = 抬头
##     yaw   正 = 机头向左
##     roll  正 = 左滚（右翼抬起）
##
## 两种特殊飞行模式（来自需求）：
##   - **加速模式**（`boosting`，Shift）：目标速度换成 boost 上限，
##     加速模式现在**不再**削弱转弯能力（用户要求）。
##   - **悬停模式**（`hovering`，Ctrl）：极猛刹车把速度压到 0 并顶住重力，
##     可以原地转向。米诺夫斯基飞行器，不遵守空气动力学。
##
## 本类**不接触场景树、不使用随机数**，只吃 Basis + 输入，方便无头单元测试。

# ---------------------------------------------------------------- 调参区

## 失速速度：低于此值舵效骤降、机头自动下坠。
var stall_speed := 75.0
## 收光油门能达到的最低速度。
var min_speed := 95.0
## 巡航速度：舵效的基准速度。
var cruise_speed := 200.0
## 满油门（不加速）最高速度。
var max_speed := 340.0
## 加速模式最高速度。
var ab_speed := 560.0

var thrust_accel_limit := 0.0
var accel := 70.0
var ab_accel := 150.0
var brake := 110.0
## 比例式推力增益：加速度 = (目标速度 − 当前速度) × speed_gain，再按 brake/accel 封顶。
var speed_gain := 1.0

var gravity := 9.81
## 重力沿航迹做功的放大系数（1.0 = 真实，越大越"街机"）。
## 它直接决定"爬升有多掉速、俯冲有多涨速"，也就是能量空战有没有意义。
var gravity_energy := 5.5

## 升力基准速度：低于它开始掉高度。
var lift_ref_speed := 170.0
## 下沉速度收敛到目标值的速率（m/s²）。
var sink_response := 14.0
## 下沉速度上限系数。
var sink_gain := 2.2

## 三轴舵效的**基值**（rad/s @ 巡航速度）。
##
## ⚠️⚠️ 为什么要有常量名，而不是直接写在这三个 `var` 的初值里：
## `FlightBody._apply_profile_to_flight()` 要做的是「**基值 × 机体 `turn_scale`**」——
## 也就是**赋值**。它拿不到"基值"的话只能写成 `fm.pitch_rate *= turn_scale`，
## 而那是**累乘**：`fm` 从不重建，于是同一个 `FlightBody` 每走一次那条路就多乘一档
## `turn_scale`。那条路会被调用在：
##   · `_ready()`（出生，第一次）
##   · `switch_form()`（变形，每切一档一次）
##   · `on_pedal_broken()`（踏板被打掉）
##   · ★63-24 `main._take_endless_card()`（局内每拿一张卡一次）
## ⇒ 演习局拿到「姿态喷口」(+38%) 之后每拿一张卡舵效就 ×1.38：
##   二十来张卡之后机体变成陀螺（而**不报任何错**）。
## 下面 `apply_pedal_flight_bonus()` 的头注其实早就把契约写明了
##（「必须是赋值而不是 `*=`」+「`_apply_profile_to_flight()` 会按 profile 重设转向基值」）
## —— 那里面的 `_pedal_turn_applied` 一次性标记正是**假定**基值会被重设。
## 所以这三个常量不是新设计，是把那句注释落成代码。
const PITCH_RATE_BASE := 0.95
const ROLL_RATE_BASE := 2.40
const YAW_RATE_BASE := 0.94

var pitch_rate := PITCH_RATE_BASE   # rad/s @ 巡航速度
var roll_rate := ROLL_RATE_BASE
## **偏航角速率**（rad/s @ 巡航速度）。
##
## 2026-09-26 用户裁决：`0.45 → 0.94`。原值下按方向键偏航转 180° 要
## `π / (0.45 × turn_gain 1.7) ≈ 4.1 s` —— 四秒才调得过头，而**这件事动画补不了**
##（转向归物理，`player_controller.gd` 的六个姿态轴只写输入），只能改这里。
## 改后 `π / (0.94 × 1.7) ≈ 1.97 s`。
##
## ⚠️ 特意取了与 `pitch_rate`（0.95）**同档**：俯仰与偏航等舵效 = 协调转弯，
## 按方向键画出来的弧线才不会"一边快一边慢"。
##
## 连带效应（**只动观感，不动能量**，改前请连同下面三条一起读）：
##   · `_step_attitude()` 三轴同乘本值 ⇒ 辅助驾驶的压坡角目标
##     `角速率 × ASSIST_BANK_GAIN 0.42` 从 18.4° 顶到上限
##     `ASSIST_BANK_MAX`（0.50 rad ≈ 28.6°），**转弯侧倾明显更大**；
##     想保住原来的 18° 观感，同步把 `ASSIST_BANK_GAIN` 降到 ≈0.30。
##   · `_update_g_load()` 的过载读数随角速率线性涨 ⇒ HUD 过载告警更容易亮。
##   · **诱导阻力不看本值**（`turn_drag` 只吃 `input` 杆量）⇒ 满杆掉速度不变。
## ⚠️ 初值取常量 `YAW_RATE_BASE`：`FlightBody._apply_profile_to_flight()` 要靠它
## 做**赋值**（幂等），理由见 `PITCH_RATE_BASE` 的头注。
var yaw_rate := YAW_RATE_BASE

## 速度矢量追赶机头的速率（1/s）。越大越"贴杆"，越小越飘。
var velocity_follow := 5.5
## 失速时舵效保留比例。
var stall_authority := 0.30
## 失速时机头自动下坠速率（rad/s）。
var stall_nose_drop := 0.55

## **大过载诱导阻力**（批 11 手感：王牌空战的能量空战根基）。
##
## 拉杆转向时按 `stick² × turn_drag × speed` 掉速度 —— 物理上这就是
## 诱导阻力 ∝ 升力系数²（大过载 = 大迎角 = 大诱导阻力）。手感上是三件事：
##   1. **急转是有代价的**：满杆筋斗掉速度，转完变"低速机"，追咬要算能量；
##   2. **能量管理成立**：俯冲攒的速度在急转里花掉，Bz 战术（能量互换）有意义；
##   3. **松杆回血**：阻力只在拉杆时存在，松杆后比例推力把速度补回来。
##
## ⚠️ 只挂**俯仰/偏航**（真正在转向速度矢量的舵），**不挂滚转** ——
## 滚转不改航向，物理上没有诱导阻力；而且 `suite_flight` 的滚转稳态角速率
## 断言（±2%）靠"巡航点舵效恒为 1"，滚转掉速会直接把它带红。
## 数值：0.045 × 满杆 × 200 m/s ≈ 9 m/s² 的额外减速 —— 一个筋斗多掉
## 十几二十 m/s，"能感觉到"但不至于"拉一圈就失速"。
var turn_drag := 0.045

# ---------------------------------------------------------------- 模式

## 加速模式：目标速度 = ab_speed。
var boosting := false
## **超级加速**（2026-09-22）：目标速度 = ab_speed × `SUPER_BOOST_MULT`。
##
## 只有一个写入点：阿利宙斯巡航形态在辅助驾驶下按 Shift（用户指定
## "阿利宙斯变形之后的辅助模式依然保持现状，不过他的 shift 就变成超级加速"）。
## 普通机体与其它形态永远 false —— `resolve_jet_gauge()` 之后气动读到的
## 是裁决过的值，这里只是"上限换挡"，不改变加力的开/关语义。
var super_boost := false
## 超级加速的速度倍数（乘在加力上限上）。1.35：巡航形态本来就是三形态最快，
## 再叠一档后极速 ≈ 1358 m/s（≈4890 km/h），一秒一公里多的观感才配得上"超级"。
const SUPER_BOOST_MULT := 1.35
## 悬停模式：速度强制归零、不下沉，可原地转向。
var hovering := false
## **全局转向增益**。用户要求"任何时候的转向操控都改成 170%"，所以基准角速率
## 在这里统一乘 1.7。
## 实际角速率 = pitch_rate × 机体 turn_scale × turn_gain × control_authority
var turn_gain := 1.7
## 加速模式的转弯能力折扣。**按用户要求已停用（= 1.0，不再打折）**；
## 想恢复"加速时转弯变钝"就把它改回 0.7。
var boost_turn_penalty := 1.0
## 悬停时的舵效。速度归零后 control_authority 会掉到下限，悬停必须单独给一个值。
var hover_authority := 0.85
## 悬停刹车加速度（m/s²），由 configure() 按尺度给出。
var hover_brake := 520.0

# ---------------------------------------------------------------- 状态

## 空速（m/s），沿机头方向的标量。
var speed := 200.0
## 油门 0..1。
var throttle := 0.65
## 是否失速。
var stalled := false
## 当前过载（仅用于 HUD 显示与告警）。
var g_load := 1.0
## 实际位移速度（m/s），由 move_and_slide 使用。
var velocity := Vector3.ZERO
## 因升力不足产生的下沉速度（m/s，正数表示向下）。
var sink_speed := 0.0


## 按机体/难度的速度上限整体重算全部速度相关参数。
##
## 只改 max_speed 是不够的：加速度、失速线、升力基准、悬停刹车如果还停在旧尺度，
## 换一台快 1.5 倍的机就会出现"油门到底也爬不起来"或者"一碰就失速"这种怪现象。
func configure(top_speed: float, boost_speed: float) -> void:
	max_speed = top_speed
	ab_speed = boost_speed
	cruise_speed = top_speed * 0.55
	min_speed = top_speed * 0.22
	stall_speed = top_speed * 0.18
	lift_ref_speed = top_speed * 0.52
	accel = top_speed * 0.17
	ab_accel = top_speed * 0.36
	brake = top_speed * 0.27
	hover_brake = top_speed * 1.25
	throttle = clampf(throttle, 0.0, 1.0)


## 出生/重置时把速度矢量对齐到机头方向，避免第一帧"横着飞"。
func align_velocity(fwd: Vector3) -> void:
	velocity = fwd.normalized() * speed
	sink_speed = 0.0
	g_load = 1.0


## 舵效系数。悬停时用固定的 hover_authority；否则随速度变化，加速模式再打折。
func control_authority() -> float:
	if hovering:
		return hover_authority
	var a := clampf(speed / cruise_speed, 0.35, 1.0)
	if stalled:
		a *= stall_authority
	if boosting:
		a *= boost_turn_penalty
	return a


## 推进一帧。delta 秒，basis 当前姿态，input = (pitch, yaw, roll)。
## 返回新的姿态 Basis；内部同步更新 speed / velocity / sink_speed / stalled / g_load。
func advance(delta: float, basis: Basis, input: Vector3) -> Basis:
	# 诱导阻力只看俯仰/偏航杆量（真正的"转向"舵）；滚转不算（见 turn_drag 注释）。
	var stick := clampf(sqrt(input.x * input.x + input.y * input.y), 0.0, 1.0)
	_step_speed(delta, -basis.z, stick)
	_step_lift(delta)
	var nb := _step_attitude(delta, basis, input)
	_step_velocity(delta, -nb.z)
	return nb


func _step_speed(delta: float, fwd: Vector3, stick := 0.0) -> void:
	if hovering:
		# 悬停：米诺夫斯基飞行器顶住重力，速度强行压到 0 且不下沉
		speed = move_toward(speed, 0.0, hover_brake * delta)
		stalled = false
		return

	var target := ab_speed if boosting else lerpf(min_speed, max_speed, clampf(throttle, 0.0, 1.0))
	var max_accel := ab_accel if boosting else accel
	if boosting and super_boost:
		# 超级加速：目标与加速度一起上探超级档（否则天花板抬了也爬不上去）
		target = ab_speed * SUPER_BOOST_MULT
		max_accel = ab_accel * 1.6
	if thrust_accel_limit > 0.0:
		max_accel = minf(max_accel,thrust_accel_limit)
	var a := clampf((target - speed) * speed_gain, -brake, max_accel)
	# 重力沿航迹做功：爬升掉速、俯冲加速。
	# 这里必须算成**加速度**再积分，不能直接改 speed ——
	# 直接改速度的话，下一帧的比例推力立刻就把损失补回来了，爬升完全不掉速，
	# "能量"这个概念在游戏里就彻底消失了（这个坑踩过一次）。
	a -= gravity * gravity_energy * fwd.y
	# 大过载诱导阻力：拉杆越狠、速度越高，掉得越多（见 turn_drag 的说明）。
	# 平方项是刻意的 —— 半杆巡航几乎无感，满杆机动才有"在花能量"的感觉。
	if stick > 0.0:
		a -= stick * stick * turn_drag * speed
	# 速度天花板：普通态 = 加力上限 ×1.25（留给俯冲涨速的余量）；
	# 超级加速时天花板跟着抬到超级目标 ×1.15 —— 否则下面的 clamp 会把
	# 超级档静默截在 1.25 倍处（1.35 的档位等于没做）。
	var ceiling := ab_speed * 1.25
	if boosting and super_boost:
		ceiling = ab_speed * SUPER_BOOST_MULT * 1.15
	speed = clampf(speed + a * delta, 0.0, ceiling)
	stalled = speed < stall_speed


func _step_lift(delta: float) -> void:
	if hovering:
		sink_speed = move_toward(sink_speed, 0.0, sink_response * 3.0 * delta)
		return
	var lift := clampf(speed / lift_ref_speed, 0.0, 1.0)
	var target_sink := gravity * (1.0 - lift) * sink_gain
	if stalled:
		target_sink *= 2.0
	sink_speed = move_toward(sink_speed, target_sink, sink_response * delta)


func _step_attitude(delta: float, basis: Basis, input: Vector3) -> Basis:
	var auth := control_authority() * turn_gain
	var pitch := input.x * pitch_rate * auth * delta
	var roll := input.z * roll_rate * auth * delta
	var yaw := input.y * yaw_rate * auth * delta
	if stalled:
		# 失速时机头自己往下掉，玩家压杆只能延缓、不能阻止
		pitch -= stall_nose_drop * delta
	# 依次绕机体三轴旋转（rotated 的轴取当前 basis 的机体轴）
	basis = basis.rotated(basis.x, pitch)
	basis = basis.rotated(basis.z, roll)
	basis = basis.rotated(basis.y, yaw)
	basis = basis.orthonormalized()
	_update_g_load(delta, pitch, yaw)
	return basis


## 过载 = 1 + 向心加速度/g。仅供 HUD 显示与告警，不影响操控。
func _update_g_load(delta: float, pitch: float, yaw: float) -> void:
	if delta <= 0.0:
		g_load = 1.0
		return
	var turn_rate := sqrt(pitch * pitch + yaw * yaw) / delta
	g_load = 1.0 + turn_rate * speed / gravity


func _step_velocity(delta: float, fwd: Vector3) -> void:
	var desired := fwd * speed + Vector3.DOWN * sink_speed
	velocity = velocity.lerp(desired, 1.0 - exp(-velocity_follow * delta))


# ---------------------------------------------------------------- 只读便捷方法

func airspeed_kmh() -> float:
	return speed * 3.6


func max_reachable_speed() -> float:
	if boosting and super_boost:
		return ab_speed * SUPER_BOOST_MULT
	return ab_speed if boosting else max_speed


## 油门把手。加速/悬停改成独立开关（Shift / Ctrl），不再靠"顶满油门"触发。
func set_throttle_axis(up: bool, down: bool, delta: float) -> void:
	var step := 0.85 * delta
	if up and not down:
		throttle = clampf(throttle + step, 0.0, 1.0)
	elif down and not up:
		throttle = clampf(throttle - step, 0.0, 1.0)
