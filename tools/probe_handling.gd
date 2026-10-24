extends Node
## 驾驶手感**测点**（出数，不出图）。设计文档 §4.5。
##
## 跑法：`godot --headless --path <工程> res://tools/probe_handling.tscn`
##
## ## 它解决什么问题
##
## 交接文档 §7.2 记着一条判断层的教训：**靠感觉描述调参会让改动来回摆** ——
## "生硬 / 迟钝 / 飘"这类词没法比较、没法回退，换个会话还可能是另一个意思。
## 所以 §4.5 的核心建议是「**先把测点建起来，再调数**」：把三组动作换成 11 个数。
##
## | 测点 | 输入 | 输出 |
## |---|---|---|
## | 滚转响应 | 满舵滚转到 180° | t90 · t180 · 超调 · 稳速时间 · 稳态角速率 |
## | 转向（半筋斗） | 巡航油门 + 满舵拉杆 | 起始角速率 · 转 180° 用时 · 转弯半径 · 掉多少速度 |
## | 加减速 | 油门 0 → 满 → 0 | 到 90% 巡航 · 到 90% 上限 · 刹到最低 |
##
## ## 边界（很重要，否则会对着错的数调参）
##
## - 测的是**气动核心**（`FlightModel`）本身：**不经过** `flight_assist`、`player_controller`
##   的鼠标增益、也不经过 `SuitProfile.turn_scale`。所以"推杆觉得钝"要先看是不是辅助在抢杆。
## - 测的是**模板机体**（不 `configure()`），但滚转那一格与机体尺度**无关**（见下面那条注）。
## - 纯仿真、无随机 ⇒ **同一个工程每次跑出来的数逐位相同**，可以直接当基线。
##
## 数一旦落盘就是基线，断言在 `tests/suite_flight.gd` 的「手感基线」一节
## （**同一份测量代码**，不各算一份）。改 `flight_model` 的响应项时会红 —— 那是故意的：
## 那一刻必须想清楚"我要把手感改成什么样"，并把基线一起更新。

## 一个数的打印格式。宽度对齐，方便和上一次的输出直接 diff。
const LINE := "  %-26s %8.3f  %s"

func _ready() -> void:
	await get_tree().process_frame
	var m := SuiteFlight.measure_handling()
	var base := FlightModel.new()

	print("")
	print("=============== 驾驶手感测点（DESIGN §4.5）===============")
	print("气动核心：FlightModel 模板（未 configure）· 60 fps 纯仿真 · 无随机")
	print("巡航速 %.0f m/s · 油门 %.3f（稳速在巡航）· turn_gain %.2f"
		% [base.cruise_speed, SuiteFlight.cruise_throttle(base), base.turn_gain])
	print("")
	print("① 滚转响应（满舵滚转到 180°）")
	print(LINE % ["滚转 90° 用时 (s)", m["t90"], ""])
	print(LINE % ["滚转 180° 用时 (s)", m["t180"], ""])
	print(LINE % ["超调 (deg)", m["overshoot_deg"], "≤ 一帧步长 ⇒ 无转动惯量"])
	print(LINE % ["稳速时间 (s)", m["settle_s"], "≈ 一帧 ⇒ 满舵即满速率"])
	print(LINE % ["稳态角速率 (deg/s)", m["steady_deg_s"],
		"roll_rate × turn_gain = %.1f" % rad_to_deg(base.roll_rate * base.turn_gain)])
	print("")
	print("② 转向（巡航油门 + 满舵拉杆 = 半筋斗）")
	print(LINE % ["起始角速率 (deg/s)", m["rate0_deg_s"], "取前 0.5 s 平均"])
	print(LINE % ["转过 180° 用时 (s)", m["t180_s"], ""])
	print(LINE % ["转弯半径 (m)", m["radius_m"], "r = v / ω"])
	print(LINE % ["掉速度 (m/s)", m["speed_loss_180"],
		"最低到 %.0f m/s ⇒ 能量空战有没有意义看这一格" % m["speed_min"]])
	print("")
	print("③ 加减速（油门 0 → 满 → 0）")
	print(LINE % ["→ 90% 巡航 (s)", m["accel_to_90cruise_s"], "从 min_speed 起、油门顶满"])
	print(LINE % ["→ 90% 上限 (s)", m["accel_to_90max_s"], ""])
	print(LINE % ["→ 刹到最低 (s)", m["brake_to_min_s"],
		"判据 min_speed × 1.05（油门收光只渐近到 min_speed）"])
	print("")
	print("④ 不变量：滚转手感与机体尺度无关（巡航点上 control_authority 恒为 1）")
	var heavy := FlightModel.new()
	heavy.configure(630.0, 900.0)
	heavy.speed = heavy.cruise_speed
	heavy.throttle = SuiteFlight.cruise_throttle(heavy)
	print(LINE % ["重机体巡航舵效", heavy.control_authority(), "应为 1.000"])
	print("")
	print("========================================================")
	get_tree().quit(0)
