class_name SuiteHudInstruments
extends RefCounted
## 批 2 的验收：**姿态仪 / 高度带 / 告警状态机 / 语音通道**（设计文档 §4.2 / §4.3）。
##
## ## 为什么这一批也全是纯函数断言
## 姿态仪和高度带本体都是 `_draw_*`，而 `_draw()` 在无头环境里**画不出东西**
## （没有帧缓冲、`can_draw()` 还可能为假）。所以"画得对不对"被切成两半：
##   - **几何与判据** —— 地平线偏移多少度、盘心落在哪、哪一刻该报警、
##     这一帧该播哪句语音、刻度之间隔多少像素 —— 全部抽成纯函数，这里逐条断言；
##   - **剩下那部分** —— 线的颜色、字号、衬底 —— 人眼试玩时看，测试不管（也管不了）。
## 这不是"覆盖不全"，而是**把能测的部分从不能测的部分里切干净**：
## 一段"大概对着截图看着像"的几何，改错方向是没人能发现的。
##
## ## 这一套里最要紧的三条
##   1. `attitude_local_to_screen` 的**旋转方向**（写反了盘会朝反方向歪）；
##   2. `tape_y` 的**上下方向**（写反了整个高度带上下颠倒）；
##   3. `pick_voice` 的**边沿触发 vs 节流**（写错会变成"结巴"或"永远哑了"）。
## 前两条都是"截图上看不出问题"的那一类，第三条是玩家两分钟就会骂的那一类。

const VIEWS := [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080), Vector2(1600, 1000)]
## 设计文档的基准分辨率（版式常量是在它上面调的）。
const BASE := Vector2(1600, 900)


static func run(t: T, _host: Node) -> void:
	t.suite("HudInstruments / 人工地平仪 · 纯函数")
	_attitude_readout(t)
	t.suite("HudInstruments / 人工地平仪 · 版式不压别人")
	_attitude_layout(t)
	t.suite("HudInstruments / 高度带 · 几何")
	_tape_layout(t)
	t.suite("HudInstruments / 高度带 · 刻度换算与色阶阈值")
	_tape_scale(t)
	t.suite("HudInstruments / 告警状态机")
	_warn_state(t)
	t.suite("HudInstruments / 语音仲裁")
	_voice(t)
	t.suite("HudInstruments / 语音通道 · 素材缺失降级")
	_voice_channel(t)
	t.suite("HudInstruments / 拦截框 · 菱形（四边相等）")
	_threat_shape(t)


# ============================================================ ① 姿态仪 · 纯函数

static func _attitude_readout(t: T) -> void:
	var ppd := FlightHUD.PITCH_PX_PER_DEG

	# ---- 平飞 ----
	var flat := FlightHUD.attitude_readout(Basis.IDENTITY)
	t.near(float(flat["horizon_offset_px"]), 0.0, 0.001, "平飞：地平线过盘心")
	t.near(float(flat["horizon_roll_deg"]), 0.0, 0.001, "平飞：不歪")

	# ---- 抬机头：地平线**往下走**（+y），量 = 俯仰 × PITCH_PX_PER_DEG ----
	var up := FlightHUD.attitude_readout(Basis(Vector3.RIGHT, deg_to_rad(30.0)))
	t.near(float(up["horizon_offset_px"]), 30.0 * ppd, 0.01,
		"抬机头 30°：地平线下移 30 × %.1f px" % ppd)
	t.gt(float(up["horizon_offset_px"]), 0.0,
		"抬机头 ⇒ 偏移为**正**（屏幕 y 向下 = 地平线往下走，这就是真实姿态仪的方向）")
	t.near(float(up["horizon_roll_deg"]), 0.0, 0.001, "纯抬机头不带滚转")

	# ---- 压机头：反过来 ----
	var down := FlightHUD.attitude_readout(Basis(Vector3.RIGHT, deg_to_rad(-45.0)))
	t.near(float(down["horizon_offset_px"]), -45.0 * ppd, 0.01,
		"压机头 45°：地平线上移（负偏移）")

	# ---- 滚转 ----
	# 绕 +Z 转 ⇒ 右翼下沉。`right()` 的 y 分量为正。
	var bank := FlightHUD.attitude_readout(Basis(Vector3.BACK, deg_to_rad(45.0)))
	t.near(float(bank["horizon_roll_deg"]), 45.0, 0.01, "右滚 45°：roll = +45")
	t.near(float(bank["horizon_offset_px"]), 0.0, 0.001, "纯滚转不动地平线的竖直位置")

	var bank_l := FlightHUD.attitude_readout(Basis(Vector3.BACK, deg_to_rad(-30.0)))
	t.near(float(bank_l["horizon_roll_deg"]), -30.0, 0.01, "左滚 30°：roll = −30")

	# ---- 局部坐标 → 屏幕坐标：**旋转方向**（这一条错了整块盘会歪向反侧）----
	#
	# ⚠️ 方向千万别说反。物理事实是：
	#   **飞机向右滚 ⇒ 机头视野里地平线的「右端」抬高。**
	#   推导：右滚 φ 等价于世界系里的 `R_z(−φ)`；世界东方向在机体系里是
	#   `(cos φ, sin φ, 0)`，它有一个沿「机体上方」的**正**分量 ——
	#   所以右滚时东侧那段地平线朝机体上方跑。
	#   （直觉上容易反着记成"右滚时右端往下"，那条是"机翼"的方向，不是"地平线"的方向。）
	var c := Vector2(100.0, 100.0)
	var same := FlightHUD.attitude_local_to_screen(c, 0.0, Vector2(7.0, -3.0)) - c
	t.near(same.x, 7.0, 0.001, "不滚转时局部→屏幕是恒等（x）")
	t.near(same.y, -3.0, 0.001, "不滚转时局部→屏幕是恒等（y）")

	var tip := FlightHUD.attitude_local_to_screen(c, 90.0, Vector2(10.0, 0.0))
	t.lt(tip.y, c.y, "右滚 90°：地平线右端转到**上方**（屏幕 y 向下 ⇒ y 更小）")
	t.near(tip.x, c.x, 0.01, "右滚 90°：右端正好转到正上方")
	var tip_l := FlightHUD.attitude_local_to_screen(c, -90.0, Vector2(10.0, 0.0))
	t.gt(tip_l.y, c.y, "左滚 90°：右端转到下方（与右滚镜像）")
	# 45° 也要同向 —— 只在 90° 那个特例上对是不够的（符号写反时 90° 恰好能蒙对）
	var half := FlightHUD.attitude_local_to_screen(c, 45.0, Vector2(10.0, 0.0)) - c
	t.lt(half.y, 0.0, "右滚 45°：右端同样抬高")
	t.gt(half.x, 0.0, "右滚 45°：右端仍然在右侧（没有转过半圈）")

	# ---- 已知近似：带俯仰时 asin(right.y) 偏小 ----
	# 把它**写下来**，免得以后有人当成 bug"修"成欧拉角分解 ——
	# 那条路会在 ±90° 处跳变，盘会"啪"地翻一下，比偏小难看得多。
	var mixed := Basis(Vector3.RIGHT, deg_to_rad(60.0)) * Basis(Vector3.BACK, deg_to_rad(90.0))
	var mr := absf(float(FlightHUD.attitude_readout(mixed)["horizon_roll_deg"]))
	t.lt(mr, 90.0, "已知近似：带 60° 俯仰时读到的滚转 < 真实 90°（读到 %.1f°）" % mr)
	t.gt(mr, 5.0, "已知近似：但仍然明确地在滚（%.1f°），不是 0" % mr)


# ============================================================ ② 姿态仪 · 版式

static func _attitude_layout(t: T) -> void:
	for view: Vector2 in VIEWS:
		var c := FlightHUD.attitude_center(view)
		var r := FlightHUD.ATTITUDE_RADIUS
		var health_top := view.y - FlightHUD.HEALTH_BLOCK_TOP_FROM_BOTTOM
		var speed_bottom := view.y * 0.5 + FlightHUD.SPEED_BLOCK_BOTTOM_PAD
		var radar := FlightHUD.radar_center(view)

		# 1) 整个盘在内容列右侧
		t.near(c.x - r, UILayout.content_left(view), 0.001,
			"%s：盘左缘 = content_left" % view)
		# 2) 盘顶在速度块最低一行之下（矮窗口下这一条靠"往下压"换来的）
		t.ok(c.y - r >= speed_bottom - 0.001,
			"%s：盘顶（%.0f）不压速度块最低一行（%.0f）" % [view, c.y - r, speed_bottom])
		# 3) 盘不压血条块
		t.ok(c.y + r <= health_top - 4.0 + 0.001,
			"%s：盘底（%.0f）留在血条块顶边（%.0f）之上" % [view, c.y + r, health_top])
		# 4) 盘右缘在雷达左缘之左
		t.lt(c.x + r, radar.x - FlightHUD.RADAR_RADIUS,
			"%s：盘右缘在雷达左缘之左" % view)
		# 5) 盘留在屏幕内
		t.gt(c.y - r, 0.0, "%s：盘顶不越出屏幕上缘" % view)
		t.lt(c.y + r, view.y, "%s：盘底不越出屏幕下缘" % view)
		# 6) 空间够的时候必须落在**首选位**（血条之上 46 px）——
		#    这条数字是"姿态仪和血条挨多近"的唯一真源，所以要用等号钉住。
		if view.y >= 900.0:
			t.near(c.y + r, health_top - 46.0, 0.001,
				"%s：空间够 ⇒ 盘底 = 血条顶边 − 46 px（首选位）" % view)

	# 基准分辨率下的具体数值（版式常量就是在这上面调的）
	var cb := FlightHUD.attitude_center(BASE)
	t.near(cb.x, 110.0, 0.001, "1600×900：盘心 x = 54 + 56")
	t.near(cb.y, 690.0, 0.001, "1600×900：盘心 y = 900 − 108 − 46 − 56")


# ============================================================ ③ 高度带 · 几何

static func _tape_layout(t: T) -> void:
	for view: Vector2 in VIEWS:
		var box := UILayout.alt_tape_rect(view)
		t.near(box.position.x + box.size.x, view.x - UILayout.MARGIN, 0.001,
			"%s：高度带紧贴屏幕右缘（落在**外框线**上）" % view)
		t.near(box.size.x, UILayout.ALT_TAPE_W, 0.001, "%s：带宽 = ALT_TAPE_W" % view)
		# 竖直方向：带必须落在 `[MARGIN, 弹药栏首行 − MARGIN]` 里，并在**能居中的时候**居中。
		# ⚠️ 1280×720 下这两件事**冲突**：可用区间 [24, 488] 的中心是 256，
		# 而屏幕中心是 360 —— 于是带被上移 62 px。这是**正确行为**（宁可贴住敌机列表，
		# 也不让刻度横穿弹药栏），所以这里是"区间内尽量居中"，不是写死的数。
		var cy_lo := UILayout.MARGIN + box.size.y * 0.5
		var cy_hi := view.y - UILayout.AMMO_TOP_FROM_BOTTOM - UILayout.MARGIN - box.size.y * 0.5
		t.between(box.position.y + box.size.y * 0.5, cy_lo - 0.001, cy_hi + 0.001,
			"%s：高度带落在允许的竖直区间内" % view)
		if view.y * 0.5 >= cy_lo and view.y * 0.5 <= cy_hi:
			t.near(box.position.y + box.size.y * 0.5, view.y * 0.5, 0.001,
				"%s：区间够 ⇒ 竖直居中" % view)
		t.ok(box.position.y >= UILayout.MARGIN - 0.001,
			"%s：高度带顶不越出上缘留白" % view)
		t.ok(box.position.y + box.size.y <= view.y - UILayout.AMMO_TOP_FROM_BOTTOM + 0.001,
			"%s：高度带底让开右下角弹药栏首行" % view)
		t.near(box.size.y, UILayout.ALT_TAPE_H, 0.001, "%s：带长 = ALT_TAPE_H" % view)

		# 高度块的数值列必须**整个**让开带宽 —— 这就是加高度带的代价
		var av := UILayout.alt_value_right(view)
		t.lt(av, box.position.x, "%s：高度块数值列在高度带左侧（让开带宽）" % view)
		t.gt(av, box.position.x - 40.0, "%s：让位 ≤ 40 px（不让出一条空沟）" % view)
		t.lt(av, UILayout.content_right(view), "%s：高度块数值列在 content_right 左侧" % view)

		# 弹药栏**不受影响**：它还在 content_right 上，与结算菜单共用一条线
		t.near(float(UILayout.ammo_columns(view)["value"]), UILayout.content_right(view), 0.001,
			"%s：弹药栏数值列仍在 content_right（高度带没动它）" % view)
		# 高度带不许压到弹药栏（右下角那三列，它们的数值列与带的 x 区间真的重叠）
		t.ok(box.position.y + box.size.y <= view.y - UILayout.AMMO_TOP_FROM_BOTTOM + 0.001,
			"%s：高度带底在弹药栏首行之上" % view)
		# 带贴的是**外框线**，所以它的左缘一定落在 `content_right` 左边 ——
		# 这正是"高度块的数值列必须让位"的原因（`alt_value_right()`）。
		t.lt(box.position.x, UILayout.content_right(view),
			"%s：带左缘在 content_right 左侧（数值列非让位不可）" % view)


	# 1280×720 的具体数钉住 —— 免得以后有人"顺手"把它改回竖直居中，
	# 而那个改动会让刻度横穿右下角弹药栏的数值列（一个只在矮窗口才出现的问题）。
	var box720 := UILayout.alt_tape_rect(Vector2(1280, 720))
	t.near(box720.position.y + box720.size.y * 0.5, 298.0, 0.001,
		"1280×720：带心在 298（不是屏幕中心 360）")
	t.near(box720.position.y + box720.size.y,
		720.0 - UILayout.AMMO_TOP_FROM_BOTTOM - UILayout.MARGIN, 0.001,
		"1280×720：带底正好落在允许区间的下界（贴住弹药栏留白）")


# ============================================================ ④ 高度带 · 刻度与色阶

static func _tape_scale(t: T) -> void:
	var lay := FlightHUD.altitude_tape_layout(BASE)
	var span := float(lay["bottom"]) - float(lay["top"])
	var ppm := float(lay["px_per_m"])

	t.near(ppm * UILayout.ALT_TAPE_SPAN_M, span, 0.001, "px_per_m × 跨度 = 带长")
	t.near(span, UILayout.ALT_TAPE_H, 0.001, "1600×900 下带长 = ALT_TAPE_H")

	# 指针恒在带心
	t.near(FlightHUD.tape_y(lay, 3000.0, 3000.0), float(lay["center"]), 0.001,
		"当前高度画在带心（指针不动，带滚动）")
	# 方向：越高越靠上
	t.lt(FlightHUD.tape_y(lay, 3500.0, 3000.0), FlightHUD.tape_y(lay, 3000.0, 3000.0),
		"高 500 m 的刻度在**上方**（y 更小）")
	t.gt(FlightHUD.tape_y(lay, 2500.0, 3000.0), float(lay["center"]),
		"低 500 m 的刻度在下方")
	# 500 m 一格 = 500 × px_per_m ≈ 38 px
	t.near(FlightHUD.tape_y(lay, 3000.0, 3000.0) - FlightHUD.tape_y(lay, 3500.0, 3000.0),
		500.0 * ppm, 0.001, "500 m 一格 = 500 × px_per_m")
	t.near(500.0 * ppm, 38.0, 0.6, "500 m 一格 ≈ 38 px（46 px 的带宽装得下）")

	# 地面线在量程外 —— 这决定了"贴边报数"是必须的、不是可选的美化
	t.gt(FlightHUD.tape_y(lay, 0.0, 3000.0), float(lay["bottom"]),
		"在 3000 m 飞时地面落在量程之外 ⇒ 必须贴边并把距离写出来")
	# 反过来：贴地飞时地面线在带内（那条实线才有意义）
	t.gt(FlightHUD.tape_y(lay, 0.0, 100.0), float(lay["bottom"]) - span * 0.5,
		"在 100 m 飞时地面在带的下半部分（线画得出来）")

	# 色阶阈值与 PULL_UP_ALTITUDE **同源**
	t.near(FlightHUD.ALT_DANGER_M, FlightHUD.PULL_UP_ALTITUDE, 0.001,
		"危险色阶 = PULL_UP_ALTITUDE（数字变红的高度就是告警线）")
	t.near(FlightHUD.ALT_WARN_M, FlightHUD.PULL_UP_ALTITUDE * 2.0, 0.001,
		"警告色阶 = 2 × PULL_UP_ALTITUDE")
	t.gt(FlightHUD.ALT_WARN_M, FlightHUD.ALT_DANGER_M, "警告阈值高于危险阈值")


# ============================================================ ⑤ 告警状态机

static func _warn_state(t: T) -> void:
	# ---- 平安 ----
	var clean := FlightHUD.warn_state(3000.0, 0.0, false, false, 3.0, true)
	for k: String in FlightHUD.WARN_PRIORITY:
		t.not_ok(bool(clean[k]), "平安：%s 不成立" % k)
	t.eq(FlightHUD.highest_warning(clean), "", "平安：没有最高告警")

	# ---- 拉起：按**预测高度**判，不是当前高度 ----
	var pull := FlightHUD.warn_state(300.0, -200.0, false, false, 3.0, true)
	t.ok(bool(pull["pull_up"]), "300 m 且以 −200 m/s 下坠 ⇒ 拉起告警")
	t.not_ok(bool(FlightHUD.warn_state(3000.0, 0.0, false, false, 3.0, true)["pull_up"]),
		"3000 m 平飞 ⇒ 不报")
	t.not_ok(bool(FlightHUD.warn_state(300.0, 200.0, false, false, 3.0, true)["pull_up"]),
		"300 m 但在爬升 ⇒ 不报（预测高度被抬上去，不用额外判机头朝向）")
	t.eq(FlightHUD.highest_warning(pull), "pull_up", "最高告警 = 拉起")

	# 边界：判据是**严格小于**
	t.not_ok(bool(FlightHUD.warn_state(FlightHUD.PULL_UP_ALTITUDE, 0.0,
		false, false, 3.0, true)["pull_up"]), "预测高度恰好 = 阈值 ⇒ 不报")
	t.ok(bool(FlightHUD.warn_state(FlightHUD.PULL_UP_ALTITUDE - 1.0, 0.0,
		false, false, 3.0, true)["pull_up"]), "预测高度低 1 m ⇒ 报")

	# ---- 过载：阈值同源，判据是严格大于 ----
	t.not_ok(bool(FlightHUD.warn_state(3000.0, 0.0, false, false,
		FlightHUD.OVER_G_THRESHOLD, true)["over_g"]), "G 恰好 = 阈值 ⇒ 不报")
	t.ok(bool(FlightHUD.warn_state(3000.0, 0.0, false, false,
		FlightHUD.OVER_G_THRESHOLD + 0.1, true)["over_g"]), "G 超过阈值 ⇒ 报")

	# ---- 导弹 / 失速 / 护盾：直接透传 ----
	t.ok(bool(FlightHUD.warn_state(3000.0, 0.0, true, false, 3.0, true)["missile"]),
		"有弹追 ⇒ 报")
	t.ok(bool(FlightHUD.warn_state(3000.0, 0.0, false, true, 3.0, true)["stall"]),
		"失速 ⇒ 报")
	t.ok(bool(FlightHUD.warn_state(3000.0, 0.0, false, false, 3.0, false)["ifield_down"]),
		"没有 I 立场 ⇒ 报")

	# ---- 优先级 ----
	var many := FlightHUD.warn_state(300.0, -200.0, true, true, 20.0, false)
	t.eq(FlightHUD.highest_warning(many), "pull_up", "五条同时成立 ⇒ 取最高的拉起")
	t.eq(str(FlightHUD.WARN_PRIORITY[FlightHUD.WARN_PRIORITY.size() - 1]), "ifield_down",
		"ifield_down 排在最后（它长时间成立，排前面会把别的告警全挡掉）")

	# ---- `no_warn_state()` 的键必须与优先级表**完全**一致 ----
	# 少一个键 = 一条永远不报的告警（`get(k, false)` 会把缺失读成"平安"）。
	var empty := FlightHUD.no_warn_state()
	t.eq(empty.size(), FlightHUD.WARN_PRIORITY.size(), "no_warn_state 的键数 = 优先级表长度")
	for k: String in FlightHUD.WARN_PRIORITY:
		t.ok(empty.has(k), "no_warn_state 含 %s" % k)
		t.not_ok(bool(empty[k]), "no_warn_state 的 %s 是 false" % k)


# ============================================================ ⑥ 语音仲裁

static func _only(k: String) -> Dictionary:
	var d := FlightHUD.no_warn_state()
	d[k] = true
	return d


static func _voice(t: T) -> void:
	# ---- ① 优先级仲裁：同时成立只播一条 ----
	var both := FlightHUD.no_warn_state()
	both["pull_up"] = true
	both["missile"] = true
	t.eq(FlightHUD.pick_voice(both, "", "", 99.0), "pull_up",
		"同时「拉起 + 导弹」⇒ 只点播拉起那一条（不叠加）")
	t.eq(FlightHUD.pick_voice(both, "pull_up", "pull_up", 0.05), "",
		"拉起已经在播 ⇒ 本帧不重复点播")

	# ---- ② 边沿触发：持续成立**不重复**（这就是设计文档说的"3 秒只播一次"）----
	var st := _only("stall")
	t.eq(FlightHUD.pick_voice(st, "", "", 99.0), "stall", "失速刚成立 ⇒ 播")
	t.eq(FlightHUD.pick_voice(st, "stall", "stall", 0.02), "", "第 2 帧 ⇒ 不播")
	t.eq(FlightHUD.pick_voice(st, "stall", "stall", 1.0), "", "持续 1.0 s ⇒ 不播")
	t.eq(FlightHUD.pick_voice(st, "stall", "stall", 3.0), "", "持续 3.0 s ⇒ 仍然只有开头那一次")
	t.eq(FlightHUD.pick_voice(st, "stall", "stall", 30.0), "", "持续 30 s ⇒ 依然不播（不是结巴）")
	# ⚠️ 这一条是**有意的机制偏差**：设计文档把"3 秒只播一次"记在 VOICE_THROTTLE 账上，
	# 而按纯节流实现 3 秒里会播两次（t=0 与 t=2.5）。这里改成边沿触发实现那一条，
	# VOICE_THROTTLE 专职挡下面的抖动。见 `pick_voice()` 的注释。

	# ---- ③ 消失再出现：held 被清空 ⇒ 立刻能播（不是"冷却没到就永远哑了"）----
	t.eq(FlightHUD.pick_voice(st, "", "stall", 3.0), "stall",
		"失速消失 3 s 后重现 ⇒ 立刻能播")
	# ---- ④ 抖动：边沿每次放行，靠 VOICE_THROTTLE 挡住 ----
	t.eq(FlightHUD.pick_voice(st, "", "stall", 0.2), "",
		"消失 0.2 s 就重现 ⇒ 被节流挡住（预言高度在阈值上抖时靠它）")
	t.eq(FlightHUD.pick_voice(st, "", "stall", FlightHUD.VOICE_THROTTLE), "stall",
		"节流窗口刚过 ⇒ 又能播")

	# ---- ⑤ 无告警 ⇒ 不播 ----
	t.eq(FlightHUD.pick_voice(FlightHUD.no_warn_state(), "stall", "stall", 9.0), "",
		"没有告警 ⇒ 不播")

	# ---- ⑥ 表本身 ----
	for k: String in ["pull_up", "missile", "stall", "over_g"]:
		t.ok(FlightHUD.VOICE_FOR.has(k), "告警 %s 有语音" % k)
	t.not_ok(FlightHUD.VOICE_FOR.has("ifield_down"),
		"ifield_down **故意**没有语音（长时间成立会挡掉别的告警）")
	t.ok(FlightHUD.VOICE_THROTTLE >= 1.0 and FlightHUD.VOICE_THROTTLE <= 5.0,
		"节流窗口在一个合理的区间（%.1f s）" % FlightHUD.VOICE_THROTTLE)


# ============================================================ ⑦ 语音通道 · 降级

static func _voice_channel(t: T) -> void:
	# ⚠️ 四条录音**现在不在工程里**（要由用户提供，§4.3.3）。
	# 所以这里断言的是**降级路径**：`voice_or_fallback()` 永远返回一个
	# **已登记的音效名**，于是"语音没录"不会变成"告警没了"。
	# 素材到货那天 `has_voice()` 自己会翻成 true，这几条断言随之变成"走录音" ——
	# 刻意写成这样，就是为了不用改测试。
	t.ok(SoundBank.SFX.has("alarm_critical"), "降级目标 alarm_critical 已登记")
	t.ok(SoundBank.SFX.has("alarm_missile"), "降级目标 alarm_missile 已登记")

	for k: String in FlightHUD.VOICE_FOR:
		var vn := str(FlightHUD.VOICE_FOR[k])
		t.ok(SoundBank.VOICE_FALLBACK.has(vn), "%s 有降级兜底" % vn)
		var got := SoundBank.voice_or_fallback(vn)
		t.ok(got != "", "%s：voice_or_fallback 不返回空（当前得到 %s）" % [vn, got])
		t.ok(SoundBank.SFX.has(got),
			"%s：拿到的是一个**已登记的**音效名（%s）" % [vn, got])
		# 有录音时必须原样返回自己（不然素材到货了也听不到）
		if SoundBank.has_voice(vn):
			t.eq(got, vn, "%s：素材在 ⇒ 用录音自己" % vn)

	t.eq(SoundBank.voice_or_fallback("voice_根本不存在"), "", "完全未知的名字 ⇒ 返回空（静默）")

	# ---- 通道本体 ----
	t.ok(Audio.has_method("play_voice"), "AudioDirector 有 play_voice()")
	t.ok(Audio.has_method("stop_voice"), "AudioDirector 有 stop_voice()")
	t.ok(Audio.has_method("is_voice_playing"), "AudioDirector 有 is_voice_playing()")

	Audio.stop_voice()
	t.not_ok(Audio.is_voice_playing(), "stop_voice() 之后通道是干净的")
	# 无头模式下调它**不许报错** —— 音频设备在 headless 下是 Dummy 驱动，
	# 而这一条直接对着 `SCRIPT ERROR = 0` 那条基线。
	Audio.play_voice("voice_pull_up")
	Audio.play_voice("voice_missile")
	Audio.play_voice("voice_根本不存在")
	t.ok(true, "三条语音连播（含一条不存在的）在无头下不报错")
	Audio.stop_voice()
	t.not_ok(Audio.is_voice_playing(), "掐掉之后仍然只有一条通道、且是空的")


# ============================================================ ⑧ 拦截框 · 菱形

## 来袭飞弹的「拦截显示框」是**菱形**（四边相等），机体锁定框仍是**正方形** —— 用户指定。
##
## ## 为什么断言的是顶点、不是像素
## `_draw()` 在无头环境里**画不出东西**（没有帧缓冲、`can_draw()` 还可能为假），
## 所以"形状对不对"只能落在**几何**上 —— 这与本套件开头那段的切法一致。
##
## 而"四边相等的菱形"这句话本身就是几何：四个顶点到框心等距 ⇒ 两条对角线
## 都是 `2h` 且互相垂直平分 ⇒ 四条边恒等于 `h·√2`。逐条断言它，
## 比对着截图说"看着像菱形"结实得多 —— 后者正是误判过的那种判据。
static func _threat_shape(t: T) -> void:
	var c := Vector2(712.0, 431.0)
	var h := FlightHUD.THREAT_BOX_H

	# ---- ① 菱形：四个顶点等距 ⇒ 对角线等长 ⇒ **四边相等** ----
	var v := FlightHUD.threat_box_vertices(c, h)
	t.eq(v.size(), 4, "菱形框恰好 4 个顶点")
	for i in v.size():
		t.near(c.distance_to(v[i]), h, 0.001,
			"顶点 %d 到框心 = h（四个都一样 ⇒ 两条对角线等长）" % i)
	var side := h * sqrt(2.0)
	for i in v.size():
		t.near(v[i].distance_to(v[(i + 1) % v.size()]), side, 0.001,
			"第 %d 条边长 = h·√2（四条必须一样长 —— 这就是「四边相等」）" % (i + 1))

	# ---- ② 顶点在正上 / 正下 / 正左 / 正右 ----
	# ⚠️ 这一条才是「菱形」与「正方形」的**全部差别**：不在 ±45° 上，就不是方的。
	for i in v.size():
		var off := v[i] - c
		t.ok(is_zero_approx(off.x) or is_zero_approx(off.y),
			"菱形顶点 %d 落在正上/正下/正左/正右（不在 ±45° 上 —— 那是正方形）" % i)

	# ---- ③ 锁定框（正方形）必须仍是**另一套**顶点方位 ----
	var sq := FlightHUD.bracket_vertices(c, h)
	t.eq(sq.size(), 4, "正方形框也是 4 个顶点")
	for i in sq.size():
		var off := sq[i] - c
		t.ok(not is_zero_approx(off.x) and not is_zero_approx(off.y),
			"正方形框顶点 %d 在**对角**方向（x、y 分量都不为零）" % i)
		t.near(absf(off.x), h, 0.001, "正方形框顶点 %d 的 |x| = h" % i)
		t.near(absf(off.y), h, 0.001, "正方形框顶点 %d 的 |y| = h" % i)
	# 两种记号**不许共点**：共点 = 有个方位上两种框重合，形状编码当场失效。
	for i in v.size():
		for j in sq.size():
			t.gt(v[i].distance_to(sq[j]), 0.001,
				"菱形顶点 %d 与正方形顶点 %d 不重合" % [i, j])

	# ---- ④ 臂：数量 / 长度 / 朝向 ----
	# 与正方形框**同一套记号**，只有顶点方位不同 —— 所以臂长必须逐位相同。
	var ar := FlightHUD.threat_box_arms(c, h)
	t.eq(ar.size(), 8, "菱形框 8 条臂（4 个顶点 × 2）")
	var want_seg := h * FlightHUD.BRACKET_ARM_RATIO
	for e in ar:
		var seg: PackedVector2Array = e
		t.eq(seg.size(), 2, "每条臂两个端点")
		t.near(seg[0].distance_to(seg[1]), want_seg, 0.001,
			"臂长 = h × BRACKET_ARM_RATIO（与正方形框同长，不是各写一份）")
		var d := seg[1] - seg[0]
		# 臂必须走 45° 斜线：正 / 水平的臂画出来是正方形，菱形就没了。
		t.near(absf(d.x), absf(d.y), 0.001, "臂是 45° 斜线（|dx| = |dy|）")
		t.near(absf(d.x), want_seg * sqrt(0.5), 0.001, "45° 臂的分量 = 臂长 / √2")
		# ⚠️ 方向：从顶点朝**框内**收。写到 `n.rotated(±45°)` 会朝外，
		# 画出来是"四角星"而不是菱形 —— 而那在截图上一眼分不出来。
		t.gt((seg[0] - c).length(), (seg[1] - c).length(),
			"臂从顶点朝框心收（终点离框心更近）")

	# ---- ⑤ 框外文字必须让开上下顶点（换成菱形带出来的**新约束**）----
	# 正方形的角在 `(±h, ±h)`，`x = 框心` 那一列是空的，居中文字压在下缘上无所谓；
	# 菱形的上下顶点**正好落在 `x = 框心`** 上。`_text_center()` 按**基线**居中、
	# 字形向上长 ⇒「文字上升沿落在顶点之外」等价于 `偏移 ≥ 字号`。
	const TTI_FONT := 13
	t.gt(FlightHUD.THREAT_LABEL_PAD, 0.0, "标签偏移为正（文字在框外）")
	t.ok(FlightHUD.THREAT_LABEL_PAD >= float(TTI_FONT),
		"标签偏移 ≥ 字号 %d px ⇒ TTI 文字的上升沿落在框下顶点之外" % TTI_FONT)
