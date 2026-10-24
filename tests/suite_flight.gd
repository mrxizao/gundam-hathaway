class_name SuiteFlight
extends RefCounted
## 飞行模型单元测试。
##
## 这一套是整个项目最该被测试的东西：手感调参一旦改坏，
## 表现是"玩起来怪怪的"而不是崩，没有断言就发现不了。
## 尤其是三个轴向的正负号 —— 写反了游戏照样跑，但操作会完全错乱。

const DT := 1.0 / 60.0
## 让速度恰好维持在当前值的油门（target = lerp(min, max, throttle)）。
## 从模板实例读参数而不是写死数字 —— 调参时测试不会跟着失效。
static func _hold_throttle(speed: float) -> float:
	var f := FlightModel.new()
	return clampf((speed - f.min_speed) / (f.max_speed - f.min_speed), 0.0, 1.0)


static func run(t: T) -> void:
	t.suite("FlightModel / 轴向符号")
	_axes(t)
	t.suite("FlightModel / 油门与速度")
	_throttle(t)
	t.suite("FlightModel / 加速模式与悬停")
	_boost_and_hover(t)
	t.suite("FlightModel / 能量")
	_energy(t)
	t.suite("FlightModel / 升力与失速")
	_lift_and_stall(t)
	t.suite("FlightModel / 速度矢量滞后")
	_velocity_lag(t)
	t.suite("FlightModel / 确定性")
	_determinism(t)
	t.suite("FlightModel / 手感基线（probe_handling 的三个测点）")
	_handling_baseline(t)
	t.suite("FlightModel / 出生初速与失速线")
	_spawn_speed(t)


static func _sim(fm: FlightModel, basis: Basis, input: Vector3, seconds: float) -> Basis:
	var steps := int(round(seconds / DT))
	for i in steps:
		basis = fm.advance(DT, basis, input)
	return basis


static func _axes(t: T) -> void:
	# --- 正 pitch = 抬头 ---
	var fm := FlightModel.new()
	fm.speed = 220.0
	fm.throttle = _hold_throttle(220.0)
	var b := _sim(fm, Basis.IDENTITY, Vector3(1, 0, 0), 0.25)
	t.gt((-b.z).y, 0.10, "正 pitch 使机头上仰（forward.y>0）")
	t.gt(b.y.y, 0.9, "抬头时机体上轴仍大致朝上")

	# --- 正 roll = 左滚（右翼抬起）---
	fm = FlightModel.new()
	fm.speed = 220.0
	fm.throttle = _hold_throttle(220.0)
	b = _sim(fm, Basis.IDENTITY, Vector3(0, 0, 1), 0.25)
	t.gt(b.x.y, 0.30, "正 roll 使右翼抬起（basis.x.y>0）→ 左滚")

	# --- 正 yaw = 机头向左 ---
	fm = FlightModel.new()
	fm.speed = 220.0
	fm.throttle = _hold_throttle(220.0)
	b = _sim(fm, Basis.IDENTITY, Vector3(0, 1, 0), 0.25)
	t.lt((-b.z).x, -0.05, "正 yaw 使机头偏左（forward.x<0）")

	# --- 三轴旋转后 basis 保持正交归一 ---
	fm = FlightModel.new()
	fm.speed = 240.0
	fm.throttle = _hold_throttle(240.0)
	b = _sim(fm, Basis.IDENTITY, Vector3(0.9, 0.4, -0.8), 4.0)
	var dot_xy := b.x.dot(b.y)
	t.near(dot_xy, 0.0, 0.001, "长时间乱杆后 basis 仍正交（x·y≈0）")
	t.near(b.x.length(), 1.0, 0.001, "basis.x 仍为单位长度")


static func _throttle(t: T) -> void:
	var fm := FlightModel.new()
	fm.speed = 200.0
	fm.throttle = 1.0
	fm.boosting = false
	_sim(fm, Basis.IDENTITY, Vector3.ZERO, 4.0)
	t.gt(fm.speed, 300.0, "满油门 4 秒后加速到 300 m/s 以上")
	t.lt(fm.speed, 341.0, "不按加速时不会超过 max_speed")

	fm = FlightModel.new()
	fm.speed = 300.0
	fm.throttle = 0.0
	_sim(fm, Basis.IDENTITY, Vector3.ZERO, 4.0)
	t.lt(fm.speed, 130.0, "收光油门 4 秒后减速到 130 m/s 以下")
	t.gt(fm.speed, 90.0, "减速但不会低于 min_speed 太多")

	fm = FlightModel.new()
	fm.speed = 300.0
	fm.throttle = 1.0
	fm.boosting = true
	_sim(fm, Basis.IDENTITY, Vector3.ZERO, 4.0)
	t.gt(fm.speed, 480.0, "加速模式 4 秒后突破 480 m/s")

	# 加速是**独立开关**（Shift），不再靠"油门顶满"自动触发
	fm = FlightModel.new()
	fm.throttle = 0.5
	for i in 240:
		fm.set_throttle_axis(true, false, DT)
	t.near(fm.throttle, 1.0, 0.0001, "持续加油门会封顶在 100%")
	t.not_ok(fm.boosting, "油门顶到底也不会自动进入加速（加速只由 Shift 控制）")


static func _boost_and_hover(t: T) -> void:
	# --- 加速模式：**不再**削弱转弯能力（用户要求撤掉 −30%）---
	var normal := FlightModel.new()
	normal.speed = 200.0
	var nb := _sim(normal, Basis.IDENTITY, Vector3(1, 0, 0), 0.5)
	var normal_pitch: float = (-nb.z).y

	var boosted := FlightModel.new()
	boosted.speed = 200.0
	boosted.boosting = true
	var bb := _sim(boosted, Basis.IDENTITY, Vector3(1, 0, 0), 0.5)
	var boost_pitch: float = (-bb.z).y

	t.gt(boost_pitch, 0.05, "加速模式下仍能抬头")
	t.near(boost_pitch / maxf(normal_pitch, 0.0001), 1.0, 0.05,
		"加速模式的转弯能力和普通飞行一样（惩罚已撤掉）")
	t.near(boosted.boost_turn_penalty, 1.0, 0.001, "boost_turn_penalty 已停用（= 1.0）")

	# --- 全局转向增益 170%（用户要求）---
	var base := FlightModel.new()
	base.speed = 200.0
	base.turn_gain = 1.0
	var b1 := _sim(base, Basis.IDENTITY, Vector3(1, 0, 0), 0.2)

	var gained := FlightModel.new()
	gained.speed = 200.0     # turn_gain 默认就是 1.7
	var b2 := _sim(gained, Basis.IDENTITY, Vector3(1, 0, 0), 0.2)

	t.near(gained.turn_gain, 1.7, 0.001, "默认转向增益是 170%")
	var a1 := Vector3.FORWARD.angle_to(-b1.z)
	var a2 := Vector3.FORWARD.angle_to(-b2.z)
	t.gt(a1, 0.05, "基准转角是个有意义的量")
	t.near(a2 / maxf(a1, 0.0001), 1.7, 0.06, "实际转角是基准的 170%")

	# --- 悬停：速度被压到 0 且不下沉 ---
	var hover := FlightModel.new()
	hover.speed = 420.0
	hover.hovering = true
	hover.sink_speed = 6.0
	_sim(hover, Basis.IDENTITY, Vector3.ZERO, 2.0)
	t.lt(hover.speed, 1.0, "按住悬停 2 秒后速度归零")
	t.lt(hover.sink_speed, 0.5, "悬停时不再下沉")

	# 悬停时依然能原地转向（速度 0 时普通舵效会掉到下限，所以有专门的 hover_authority）
	t.gt(hover.control_authority(), 0.5, "悬停时保留可用的舵效")
	var hb := hover.advance(DT, Basis.IDENTITY, Vector3(1, 0, 0))
	t.gt((-hb.z).y, 0.0, "悬停时拉杆仍能抬头")

	# 松开悬停后速度要能重新爬起来
	hover.hovering = false
	hover.throttle = 1.0
	_sim(hover, Basis.IDENTITY, Vector3.ZERO, 3.0)
	t.gt(hover.speed, 100.0, "退出悬停后速度重新爬升")

	# --- configure()：换机/换难度时整套速度参数一起缩放 ---
	var fast := FlightModel.new()
	fast.configure(630.0, 630.0)
	t.near(fast.max_speed, 630.0, 0.001, "configure 设置速度上限")
	t.gt(fast.stall_speed, 75.0, "失速线随速度上限一起抬高（不会一加速就失速）")
	t.gt(fast.accel, 70.0, "加速度随尺度放大")


static func _energy(t: T) -> void:
	# 同样油门、同样速度，爬升的必定掉速、平飞的不掉
	var level := FlightModel.new()
	level.speed = 300.0
	level.throttle = _hold_throttle(300.0)
	_sim(level, Basis.IDENTITY, Vector3.ZERO, 2.0)

	var climbing := FlightModel.new()
	climbing.speed = 300.0
	climbing.throttle = _hold_throttle(300.0)
	var up_basis := Basis(Vector3.RIGHT, deg_to_rad(40.0))
	_sim(climbing, up_basis, Vector3.ZERO, 2.0)

	t.gt(level.speed - climbing.speed, 20.0, "爬升 2 秒比平飞少 20 m/s 以上（重力沿航迹做功）")

	# 俯冲应当加速
	var diving := FlightModel.new()
	diving.speed = 300.0
	diving.throttle = _hold_throttle(300.0)
	var down_basis := Basis(Vector3.RIGHT, deg_to_rad(-40.0))
	_sim(diving, down_basis, Vector3.ZERO, 2.0)
	t.gt(diving.speed - level.speed, 20.0, "俯冲 2 秒比平飞多 20 m/s 以上")


static func _lift_and_stall(t: T) -> void:
	# 高速：升力足够，不下沉
	var fast := FlightModel.new()
	fast.speed = 260.0
	fast.throttle = _hold_throttle(260.0)
	_sim(fast, Basis.IDENTITY, Vector3.ZERO, 1.5)
	t.lt(fast.sink_speed, 0.6, "巡航速度下几乎不下沉")
	t.not_ok(fast.stalled, "巡航速度不失速")

	# 低速：升力不足，开始下沉
	var slow := FlightModel.new()
	slow.speed = 110.0
	slow.throttle = _hold_throttle(110.0)
	_sim(slow, Basis.IDENTITY, Vector3.ZERO, 1.5)
	t.gt(slow.sink_speed, 4.0, "低速时明显下沉")

	# 失速线以下：stalled 置位、舵效骤降、机头自动下坠
	var stall := FlightModel.new()
	stall.speed = 60.0
	stall.throttle = 0.0
	stall.advance(DT, Basis.IDENTITY, Vector3.ZERO)
	t.ok(stall.stalled, "速度低于 stall_speed 即失速")
	t.lt(stall.control_authority(), 0.16, "失速时舵效降到 0.16 以下")

	var normal := FlightModel.new()
	normal.speed = 220.0
	normal.stalled = false
	t.near(normal.control_authority(), 1.0, 0.01, "巡航速度舵效为满")

	# 失速且不给输入时机头会自己往下掉
	var drop := FlightModel.new()
	drop.speed = 55.0
	drop.throttle = 0.0
	var b := _sim(drop, Basis.IDENTITY, Vector3.ZERO, 1.0)
	t.lt((-b.z).y, -0.02, "失速不收杆时机头自动下坠")


static func _velocity_lag(t: T) -> void:
	# 用偏航（而非俯仰）来测滞后：偏航不改变高度，速度不会因为爬升掉下来污染结果
	var fm := FlightModel.new()
	fm.speed = 240.0
	fm.throttle = _hold_throttle(240.0)
	fm.align_velocity(Vector3.FORWARD)
	var b := Basis.IDENTITY
	for i in 180:
		b = fm.advance(DT, b, Vector3(0, 1, 0))
	var angle := rad_to_deg(fm.velocity.normalized().angle_to(-b.z))
	t.gt(angle, 1.0, "持续偏航时速度矢量落后于机头（有甩尾感）")
	t.lt(angle, 25.0, "滞后角不会大到失去操控感")

	# 松杆后速度矢量应重新贴回机头
	var fm2 := FlightModel.new()
	fm2.speed = 240.0
	fm2.throttle = _hold_throttle(240.0)
	fm2.align_velocity(Vector3.FORWARD)
	var b2 := Basis.IDENTITY
	for i in 60:
		b2 = fm2.advance(DT, b2, Vector3(0, 1, 0))
	for i in 240:
		b2 = fm2.advance(DT, b2, Vector3.ZERO)
	var angle2 := rad_to_deg(fm2.velocity.normalized().angle_to(-b2.z))
	t.lt(angle2, 2.0, "松杆后速度矢量重新与机头对齐")


static func _determinism(t: T) -> void:
	var a := FlightModel.new()
	var b := FlightModel.new()
	var ba := Basis.IDENTITY
	var bb := Basis.IDENTITY
	for i in 400:
		var inp := Vector3(sin(i * 0.05), cos(i * 0.037), sin(i * 0.081))
		ba = a.advance(DT, ba, inp)
		bb = b.advance(DT, bb, inp)
	t.near(a.speed, b.speed, 0.0000001, "同输入同初值 → 速度完全一致")
	t.near((ba.z - bb.z).length(), 0.0, 0.0000001, "姿态完全一致（无隐藏随机）")


# ============================================================ 手感基线（DESIGN §4.5）

## 手工飞行的**测点**。DESIGN §4.5 的核心建议是「先把测点建起来，再调数」。
##
## 为什么必须这么做（交接文档 §7.2 的教训，原文）：靠感觉描述调参（"生硬 / 迟钝 / 飘"）
## 会来回摆 —— 改动没法比较、没法回退，两个人对同一个词的理解还不一样。
## 把它换成「滚转 180° 用 x 秒、超调 y 度、刹到最低 z 秒」之后，改动就变成了可比较的数。
##
## ⚠️ 这里是**纯 `FlightModel` 仿真**：不碰场景树、不用随机数、不经过
## `flight_assist` / `player_controller`。所以
##   - 它只测「气动核心」，改辅助飞行与鼠标增益**不会**让它动；
##   - 同输入永远同输出（见 `_determinism`），所以基线断言可以卡得很紧。
##
## 测点是**模板机体**（`FlightModel.new()`，不调 `configure()`）。
##
## 供两个地方用：`tools/probe_handling.gd`（出数给人看）与下面的 `_handling_baseline()`（拦无意改动）。
const HANDLE_DT := 1.0 / 60.0


## 让速度恰好稳在 `cruise_speed` 的油门。从模板读参数而不是写死数字 —— 调参后测点自动跟着走。
static func cruise_throttle(fm: FlightModel) -> float:
	return clampf((fm.cruise_speed - fm.min_speed) / maxf(fm.max_speed - fm.min_speed, 0.001),
		0.0, 1.0)


## 一台"平飞巡航"的基准模型。
static func cruise_model() -> FlightModel:
	var fm := FlightModel.new()
	fm.speed = fm.cruise_speed
	fm.throttle = cruise_throttle(fm)
	fm.align_velocity(Vector3.FORWARD)
	return fm


## 测点 ① **滚转响应**：满舵滚转到 180°（倒飞）。返回
## `{t90, t180, overshoot_deg, settle_s, steady_deg_s}`。
##
## 各数的含义与用途：
##   - `t90` / `t180`：滚到 90° / 180° 用时（秒）—— **主指标**，"跟不跟杆"就是它；
##   - `overshoot_deg`：越过 180° 那一刻**多转**了多少。本模型没有转动惯量，
##     所以超调只可能来自**整帧步长**（恒 ≤ 一帧转角）。这个数一变大，就说明
##     有人给滚转加了惯量/阻尼 —— 那是"手感变重"的信号，必须是有意为之；
##   - `settle_s`：滚转角速率进入稳态（每帧变动 < 2%）用时。
##     它 ≈ 一帧 ⇒ 本模型的滚转**没有爬升段**（满舵即满速率）；
##   - `steady_deg_s`：稳态角速率（度/秒）。它应当 = `roll_rate × turn_gain`（弧度制）× 57.3，
##     也就是"真源参数做了什么，测点就量到什么"。
static func measure_roll() -> Dictionary:
	var fm := cruise_model()
	var b := Basis.IDENTITY
	var bank := 0.0
	var t := 0.0
	var t90 := -1.0
	var t180 := -1.0
	var overshoot := 0.0
	var settle := -1.0
	var prev_step := -1.0
	var steady_step := 0.0
	for i in 900:                      # 15 s 足够滚好几圈
		var nb := fm.advance(HANDLE_DT, b, Vector3(0, 0, 1))
		# 本帧绕机头轴转过的角。累加就是"已经从水平滚过多少度"——
		# 不用去解欧拉角：滚转是绕机体 Z 轴的纯旋转，逐帧带符号角直接可加。
		# ⚠️ 轴取 `nb.z`（机体后方）而不是 `-nb.z`：`signed_angle_to` 的符号是
		# 「从轴的方向看逆时针为正」，取反会让正舵量出一个负数。
		var step := rad_to_deg(b.x.signed_angle_to(nb.x, nb.z))
		bank += step
		b = nb
		t += HANDLE_DT
		if prev_step >= 0.0 and settle < 0.0 and absf(step - prev_step) <= 0.02 * absf(prev_step):
			settle = t
		if i > 6:
			steady_step = step
		prev_step = step
		if t90 < 0.0 and bank >= 90.0:
			t90 = t
		if t180 < 0.0 and bank >= 180.0:
			t180 = t
			overshoot = bank - 180.0
			break
	return {
		"t90": t90, "t180": t180, "overshoot_deg": overshoot,
		"settle_s": settle, "steady_deg_s": steady_step / HANDLE_DT,
	}


## 测点 ② **转向（半筋斗）**：保持巡航油门、满舵拉杆。返回
## `{rate0_deg_s, t180_s, radius_m, speed_loss_180, speed_min}`。
##
## 各数的含义：
##   - `rate0_deg_s`：起始 0.5 s 的平均角速率 —— "跟杆响应"；
##   - `t180_s`：转过 180°（半个筋斗）用时；
##   - `radius_m`：**瞬时转弯半径** = 速度 ÷ 角速率。这就是"转 180° 的水平半径"那个量
##     （水平转弯的半径公式是 `r = v / ω`；这里拉杆是垂直面的筋斗，
##     **同一个公式**给出的仍是机体的转弯半径，只是圆的朝向不同）
##   - `speed_loss_180` / `speed_min`：转 180° 期间掉了多少速度、最低掉到多少。
##     ⚠️ 这两个数是"能量空战有没有意义"的量化 —— 掉得太多就是"拉一圈就没速度了"。
static func measure_turn() -> Dictionary:
	var fm := cruise_model()
	var b := Basis.IDENTITY
	var turned := 0.0
	var t := 0.0
	var t180 := -1.0
	var speed0 := fm.speed
	var speed_min := fm.speed
	var sum := 0.0
	var n := 0
	for i in 1800:                     # 30 s
		var nb := fm.advance(HANDLE_DT, b, Vector3(1, 0, 0))
		var step := rad_to_deg(b.z.signed_angle_to(nb.z, nb.x))
		turned += step
		b = nb
		t += HANDLE_DT
		speed_min = minf(speed_min, fm.speed)
		if t <= 0.5:
			sum += step / HANDLE_DT
			n += 1
		if t180 < 0.0 and turned >= 180.0:
			t180 = t
			break
	var rate0 := (sum / maxf(float(n), 1.0)) if n > 0 else 0.0
	var radius := speed0 / maxf(deg_to_rad(rate0), 0.0001) if rate0 > 0.0 else -1.0
	return {
		"rate0_deg_s": rate0, "t180_s": t180, "radius_m": radius,
		"speed_loss_180": speed0 - fm.speed, "speed_min": speed_min,
	}


## 测点 ③ **加减速**：油门 0 → 满 → 0。返回
## `{accel_to_90cruise_s, accel_to_90max_s, brake_to_min_s}`。
##
## ⚠️ 目标速度是 `lerp(min_speed, max_speed, throttle)`，所以：
##   - 油门顶满只收敛到 `max_speed`（**不是** `ab_speed` —— 那是加速模式的事）；
##   - 油门收光只收敛到 `min_speed`，是**渐近**的，永远不会正好等于它。
##     所以刹车那条的判据取 `min_speed × 1.05`（"基本停住"），不是 `== min_speed`
##     —— 否则这个测点会永远测不完。
static func measure_throttle() -> Dictionary:
	var reach := 20.0
	var accel_to_90cruise := -1.0
	var accel_to_90max := -1.0
	var fm := cruise_model()
	fm.speed = fm.min_speed
	fm.throttle = 1.0
	var t := 0.0
	for i in int(reach / HANDLE_DT):
		fm.advance(HANDLE_DT, Basis.IDENTITY, Vector3.ZERO)
		t += HANDLE_DT
		if accel_to_90cruise < 0.0 and fm.speed >= fm.cruise_speed * 0.9:
			accel_to_90cruise = t
		if accel_to_90max < 0.0 and fm.speed >= fm.max_speed * 0.9:
			accel_to_90max = t

	var brake_to_min := -1.0
	var fm2 := cruise_model()
	fm2.throttle = 0.0
	var target := fm2.min_speed * 1.05
	var t2 := 0.0
	for i in int(reach / HANDLE_DT):
		fm2.advance(HANDLE_DT, Basis.IDENTITY, Vector3.ZERO)
		t2 += HANDLE_DT
		if fm2.speed <= target:
			brake_to_min = t2
			break
	return {
		"accel_to_90cruise_s": accel_to_90cruise,
		"accel_to_90max_s": accel_to_90max,
		"brake_to_min_s": brake_to_min,
	}


## 三个测点一起算。`tools/probe_handling.gd` 与下面的断言都走它（**不许各算一份**）。
static func measure_handling() -> Dictionary:
	var out := {}
	out.merge(measure_roll())
	out.merge(measure_turn())
	out.merge(measure_throttle())
	return out


## 手感基线断言。
##
## ## 两层判据，各自管一件事
##
## ① **自洽性**（跟着真源走）：测点量出来的角速率必须等于 `roll_rate × turn_gain`。
##    这一层不需要维护任何魔数 —— 调了 `roll_rate`，它照样成立；但如果有人
##    把参数改成了"没生效"的写法（比如乘错了地方），它会立刻红。
##
## ② **手感数字本身**（钉住）：t90 / t180 / 刹车时间这些数用 ±12% 的带子钉住。
##    ⚠️ 这一层的用意**不是**"这些数最好"，而是"改动必须是自觉的"：
##    谁要调 `roll_rate` / `turn_gain` / `gravity_energy`，就得**同时**把这里改一遍
##    —— 那一刻他必须想清楚"我要把手感改成什么样"。这正是 §4.5 要的效果。
##
## 另外补一条**不变量**：滚转响应与机体尺度**无关**。
## 理由是硬的：巡航点上 `control_authority() = clamp(speed/cruise_speed) = 1.0`，
## 而 `cruise_speed` 随 `configure()` 一起缩放 ⇒ 分子分母同缩放 ⇒ 舵效恒为 1。
## 所以重机体与轻机体的滚转手感**应当完全一致**（速度快慢是另一回事）。
static func _handling_baseline(t: T) -> void:
	var m := measure_handling()
	var base := FlightModel.new()

	# ---- ① 自洽性：测点 ↔ 真源参数 ----
	var want_rate := rad_to_deg(base.roll_rate * base.turn_gain)
	t.near(m["steady_deg_s"], want_rate, want_rate * 0.02,
		"滚转稳态角速率 = roll_rate × turn_gain（测得 %.1f，参数算出 %.1f）"
			% [m["steady_deg_s"], want_rate])
	t.ok(measure_roll()["steady_deg_s"] == m["steady_deg_s"],
		"测点是**确定性**的（连算两次逐位相同 —— 否则基线断言会随机翻红）")
	var r_turn := measure_turn()
	t.gt(r_turn["rate0_deg_s"], 0.0, "拉杆起始角速率是个正数")
	t.near(r_turn["radius_m"] * deg_to_rad(r_turn["rate0_deg_s"]), base.cruise_speed,
		base.cruise_speed * 0.02, "转弯半径满足 r = v / ω（自洽）")

	# ---- ② 手感数字（±12% 的带子；基线来自 tools/probe_handling.gd 的实测）----
	_near_rel(t, m["t90"], 0.400, "滚转 90° 用时 (s)")
	_near_rel(t, m["t180"], 0.783, "滚转 180° 用时 (s)")
	t.lt(m["t90"], m["t180"], "滚到 90° 当然早于滚到 180°")
	# 超调**不需要魔数**：它最多就是一帧的转角，而"≤ 一帧"正是"没有转动惯量"的定义。
	t.lt(m["overshoot_deg"], m["steady_deg_s"] * HANDLE_DT + 0.01,
		"滚转超调 ≤ 一帧步长（%.2f° ≤ %.2f° ⇒ **没有转动惯量**，超调只来自离散化）"
			% [m["overshoot_deg"], m["steady_deg_s"] * HANDLE_DT])
	t.lt(m["settle_s"], 0.10,
		"满舵即满速率（稳速用时 %.3f s ≈ 两帧，没有爬升段）" % m["settle_s"])
	t.near(m["t180"] / maxf(m["t90"], 0.0001), 2.0, 0.15,
		"t180 / t90 ≈ 2（滚转是**匀速积分**，不是指数逼近）")
	_near_rel(t, m["t180_s"], 2.200, "半筋斗转过 180° 用时 (s)")
	_near_rel(t, m["rate0_deg_s"], 91.091, "拉杆起始角速率 (deg/s)")
	_near_rel(t, m["radius_m"], 125.800, "转弯半径 (m)  r = v / ω")
	t.gt(m["speed_loss_180"], 15.0,
		"拉半筋斗会掉速度（能量有意义：掉 %.1f m/s）" % m["speed_loss_180"])
	t.lt(m["speed_min"], base.cruise_speed, "拉半筋斗过程中速度确实低过巡航")
	_near_rel(t, m["accel_to_90cruise_s"], 1.217, "油门顶满 → 90% 巡航 (s)")
	_near_rel(t, m["accel_to_90max_s"], 3.217, "油门顶满 → 90% 上限 (s)")
	_near_rel(t, m["brake_to_min_s"], 3.083, "收光油门 → 刹到最低 (s)")
	t.lt(m["accel_to_90cruise_s"], m["accel_to_90max_s"], "到 90% 巡航比到 90% 上限早")

	# ---- ③ 不变量：滚转手感与机体尺度无关 ----
	var heavy := FlightModel.new()
	heavy.configure(630.0, 900.0)
	heavy.speed = heavy.cruise_speed
	heavy.throttle = cruise_throttle(heavy)
	heavy.align_velocity(Vector3.FORWARD)
	t.near(heavy.control_authority(), 1.0, 0.001,
		"巡航点上舵效恒为 1（与速度上限无关）—— 下面那条不变量的依据")
	t.near(heavy.cruise_speed, 630.0 * 0.55, 0.01,
		"`configure()` 确实按尺度重算了巡航速（%.1f = 630 × 0.55；模板是 %d）"
			% [heavy.cruise_speed, int(base.cruise_speed)])
	t.near(rad_to_deg(heavy.roll_rate * heavy.turn_gain), want_rate, 0.01,
		"滚转角速率**不随机体尺度变**（roll_rate / turn_gain 都不是按尺度给的）")


## 出生初速必须**高于失速线** —— 而这件事要求出生初速**跟着 `SPEED_REAL_MULT` 走**。
##
## ## 这条是 2026-09-25 第二次提速（×1.5 → ×2.4）时才补上的
## `main.gd` 原来把出生初速写成字面量 `260.0`。它在 ×1.5 的世界里没问题
##（柯西失速线 = 945 × 0.18 = 170.1），但失速线是 `top_speed × 0.18`、**会跟着倍率涨**：
##
##     ×2.4 下柯西失速线 = 1512 × 0.18 = **272.2 > 260**
##
## ⇒ 出生的**第一帧** `stalled = speed < stall_speed` 就是 true（`FlightModel` 第 206 行），
## 于是开局头几帧舵效只有 30%、机头还在自己往下掉。佩涅罗佩（281.2）与
## 阿利宙斯巡航态（289.7）比柯西更早越线。
##
## 几帧而已、肉眼看不出来 —— 但它是一条**真的断掉的不变量**，
## 而且坏法是"以后速度再涨就越来越明显"。所以现在出生初速走
## `SuitProfile.spawn_speed()`（= 巡航 × 0.275），按比例给。
##
## ⚠️ 判据读的是 `configure()` **算完之后**的 `stall_speed`，不是自己再乘一遍 0.18 ——
## 这样以后谁在 `configure()` 里改了失速线的算法，这条会跟着走，而不是脱钩。
static func _spawn_speed(t: T) -> void:
	var spawn := SuitProfile.spawn_speed()
	t.gt(spawn, 0.0, "出生初速为正（%.1f m/s）" % spawn)
	var ids: Array[int] = [SuitProfile.Id.XI, SuitProfile.Id.PENELOPE,
		SuitProfile.Id.ARIZEUS, SuitProfile.Id.GUSTAV00, SuitProfile.Id.MESSER_M01]
	var checked := 0
	var worst := ""
	var worst_margin := INF
	for id: int in ids:
		for form: int in SuitProfile.forms_of(id):
			var p := SuitProfile.by_id_form(id, form)
			var fm := FlightModel.new()
			fm.configure(p.player_top_speed(), p.player_boost_speed())
			var margin := spawn - fm.stall_speed
			if margin < worst_margin:
				worst_margin = margin
				worst = p.display_name
			t.gt(spawn, fm.stall_speed,
				"%s：出生初速 %.1f > 失速线 %.1f（否则一出生就是失速状态）"
					% [p.display_name, spawn, fm.stall_speed])
			checked += 1
	t.gt(checked, 0, "至少检查了一台机体（%d 份 profile）" % checked)
	# 余量最小的那台也留了一截（不是"刚好压线"）—— 免得下次微调就又越过去。
	t.gt(worst_margin, 40.0,
		"余量最小的 %s 也留了 %.1f m/s 的裕度（> 40）" % [worst, worst_margin])


## 「相对 ±12%」断言。第 2 个参数是**基线值**，不是上界 —— 名字写成 `_near_rel`
## 是为了让人一眼看出它是"钉住基线"，而不是"不得超过"。
static func _near_rel(t: T, got: float, want: float, what: String) -> void:
	t.near(got, want, absf(want) * 0.12,
		"%s：%.3f（基线 %.3f，±12%%）" % [what, got, want])
