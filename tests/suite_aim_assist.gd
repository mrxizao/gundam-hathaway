class_name SuiteAimAssist
extends RefCounted
## ★63-9 · D3a「光束步枪辅助瞄准（辅助驾驶模式下自动开启）+ 提示圈提醒」。
##
## ## 用户原话
## 「给光束步枪加入辅助瞄准模式，辅助驾驶模式下自动开启，在屏幕的空白处有放大镜效果
##  （在对方机体 0.4 km 处设置相机，来显示对方）增加射击预测提示圈和射击时候的准星吸附，
##   准星靠近提示圈会有吸附和射击提醒。」
##
## ✂︎ 本轮只做 **D3a**（接线级）：修单位 + 武器/模式两处门 + 提示圈提醒。
## 放大镜（D3b）**单独立轮**并带性能预算（拍板 P9）—— 它要给全场景再加一次
## `SubViewport` 渲染，属于本工程风险最高的那一类改动，不该塞进接线轮。
##
## ## 两处死代码，本轮一起接上
## ① **单位错**：`Ballistics.angle_off_boresight()` 返**度**，而 `aim_assist_weight()`
##    内部按**弧度**比（`deg_to_rad(2.5)` / `deg_to_rad(7.0)`）⇒ 传进来的"度"永远
##    大于锥角 0.1222 rad ⇒ `w` 恒 0.0 ⇒ **整段辅助瞄准一次都没生效过**；
## ② **提示**：提前量圈早就画着（`hud.gd` 的 6 px 机炮圈 / 10 px 光束圈），
##    缺的是"准星进锥了就告诉你 + 吸附中"这一条。
##
## ## 四段判据
##   ① 单位与锥形（纯函数；含解析出来的**最大偏转 2.7222°**）；
##   ② 接线（武器门在光束调用点、模式门覆写在控制器、火神炮零改动）；
##   ③ 真机对象（偏 3° 拉、偏 20°/辅助关/火神炮口径 一律逐位不动）；
##   ④ 提示圈与吸附**同源**（阈值只有一处真源）。
##
## ## 关于 README §16.1 需求 4（"弹道跟随准星"）的冲突量化
## `w` 随偏角线性下降、而偏转量是 `偏角 × w` ⇒ 最大值**不在** 2.5°（吸附边界）上，
## 而在 `(2.5 + 7) / 2 = 3.5°` 处取得：`3.5 × (1 − 1/4.5) = 2.7222°`。
## 也就是说"只做 ≤ 2.5°"这句话**实际是 ≤ 2.7223°** —— ① 段把这两个数都钉住，
## 免得以后有人按 2.5 去论证"和 README 没冲突"（那差 9 个百分点）。
##
## ## 负对照（五个，实测红的条数与归因见括号；每次回滚都与金标逐位一致）
##   `nc_deg_inside`     `aim_assist_weight()` 内部把度当弧度用 ⇒ 红 ① 12 + ③ 3
##   `nc_no_rad`         调用点去掉 `deg_to_rad()`（= 修之前那段死代码的写法）
##                       ⇒ 红 ② 2 + ③ 4
##   `nc_no_gate`        去掉模式门、只留武器门 ⇒ 红 ② 3 + ③ 1
##   `nc_vulcan_assist`  火神炮那一处也多传两位 `false, true` ⇒ 红 ② 1
##                       ⚠️ 第一版的牙是"源码里不出现 `aim_assist` 字样"，**抓不住**这种情况
##                       ⇒ 改成 `_argc()` **数顶层实参个数**（这是本轮学到的第二条）
##   `nc_hud_literal`    HUD 把常量换成字面量 `2.5` ⇒ 红 ④ 2
##                       ⚠️ 锚点必须带 `if snap_ang` 前缀：裸的 `FlightBody.AIM_ASSIST_SNAP_DEG`
##                       在文件里出现 2 次（代码 1 + 注释 1），`assert count == 1` 会失败
##                       而让这个负对照**根本没被应用**（第一版就跑出"0 红"）

const FB_SRC := "res://scripts/flight/flight_body.gd"
const PC_SRC := "res://scripts/flight/player_controller.gd"
const HUD_SRC := "res://scripts/ui/hud.gd"
const AI_SRC := "res://scripts/ai/bandit_ai.gd"

## 靶机距离（m）与探针机位置。3 km 是"提前量几乎归零"的光束典型交战距离。
const LIVE_D := 3000.0
const LIVE_POS := Vector3(0, 900, 0)


static func run(t: T, host: Node) -> void:
	t.suite("AimAssist / ① 单位与锥形：度当弧度=归零、最大偏转 2.7222°（D3a）")
	_unit(t)
	t.suite("AimAssist / ② 接线：武器门在光束、模式门在控制器、火神炮零改动（D3a）")
	_wiring(t)
	t.suite("AimAssist / ③ 真机对象：偏 3° 拉 / 偏 20°·辅助关·火神炮 不动（D3a）")
	await _live(t, host)
	t.suite("AimAssist / ④ 提示圈与吸附同源：阈值只有一处真源（D3a）")
	_hud(t)


# ================================================================ 工具

## 取某个函数的**函数体**（从标题之后到下一个顶层定义之前）。
##
## ⚠️ 终止符必须**一起**找 `func` / `static func` / `const` / `var` / `class`：
## `suite_reverse_fly` 那版只找 `"\nfunc "`，于是 `_fire_vulcan_round()` 的函数体
## 会一路吞到 `aim_point()` 的头上去（中间那些 `static func` / `const` 都不匹配）
## —— 「火神炮里不许出现 aim_assist」这条断言当场会因为吞进了 `aim_assist_weight`
## 而变红，而那是**夹具**的错、不是产品的错。
static func _body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var rest := src.substr(i + header.length())
	var cut := rest.length()
	for pat: String in ["\nfunc ", "\nstatic func ", "\nconst ", "\nvar ", "\nclass "]:
		var j := rest.find(pat)
		if j >= 0 and j < cut:
			cut = j
	return rest.substr(0, cut)


## 这一行里有没有数字（用来钉"HUD 那行阈值不许写死成数"）。
static func _has_digit(s: String) -> bool:
	for i in s.length():
		var c := s[i]
		if c >= "0" and c <= "9":
			return true
	return false


## 数一次调用的**顶层实参个数**（嵌套括号里的逗号不算）。
##
## 为什么要数：本轮"火神炮一个字没动"这条判据，光断言"不出现 `aim_assist` 字样"
## **抓不住**"多补了两个 `false, true`"—— 负对照 `nc_vulcan_assist` 第一版
## 就是这么漏过去的（改了源码、套件照样全绿 = 没牙齿）。
static func _argc(body: String, call: String) -> int:
	var i := body.find(call)
	if i < 0:
		return -1
	var j := i + call.length()
	var depth := 1
	var commas := 0
	while j < body.length():
		var c := body[j]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth == 0:
				return commas + 1
		elif c == "," and depth == 1:
			commas += 1
		j += 1
	return -1


## 把靶机摆到"相对准星偏 deg 度、距离 d"处，并返回**产品口径的** boresight 点。
##
## ⚠️ 返回值的表达式必须与 `aim_point()` 里那句逐字同源
##（`global_position + aim_forward() * global_position.distance_to(tp)`），
## 否则"锥外逐位不动"那条 `t.eq` 会因为浮点尾数不同而假红。
static func _place(pc: PlayerController, foe: Node3D, deg: float, d: float) -> Vector3:
	var th := deg_to_rad(deg)
	foe.global_position = pc.global_position + Vector3(sin(th), 0.0, -cos(th)) * d
	return pc.global_position + pc.aim_forward() * pc.global_position.distance_to(foe.global_position)


# ================================================================ ① 单位与锥形

static func _unit(t: T) -> void:
	# 硬编码口径（⛔ 不从 `FlightBody` 取常量 —— 本工程踩过"目标值跟着被验常量
	# 一起变"的自证假绿）：SNAP 2.5°、CONE 7.0°；中点 = (2.5 + 7) / 2 = 4.75°。
	const SNAP := 2.5
	const CONE := 7.0
	const MID := 4.75
	const PEAK_ANG := 3.5
	const PEAK := 2.7222222

	# ---- 弧度口径（正路）----
	t.near(FlightBody.aim_assist_weight(0.0), 1.0, 0.0001,
		"正对（0 rad）⇒ 权重 1.0（吸附内完全代瞄）")
	t.near(FlightBody.aim_assist_weight(deg_to_rad(SNAP)), 1.0, 0.0001,
		"偏 2.5°（= 0.0436 rad）⇒ 仍 1.0")
	t.near(FlightBody.aim_assist_weight(deg_to_rad(MID)), 0.5, 0.0005,
		"偏 4.75° ⇒ 权重 0.5（**中点不是 3.5°**：2.5 与 7 的中点是 4.75）")
	t.near(FlightBody.aim_assist_weight(deg_to_rad(CONE)), 0.0, 0.0001,
		"偏 7.0° ⇒ 权重 0.0（锥边归零）")
	t.near(FlightBody.aim_assist_weight(deg_to_rad(40.0)), 0.0, 0.0001,
		"偏 40° ⇒ 仍是 0.0（不出现负数回勾）")
	t.gt(FlightBody.aim_assist_weight(deg_to_rad(3.0)), FlightBody.aim_assist_weight(deg_to_rad(6.0)),
		"斜坡段单调递减")

	# ---- **负对照写进判据**：把"度"当"弧度"传 ⇒ 必须归零 ----
	# 这一条就是"单位不许再错"的牙齿：轮 63-9 之前产品里就是这么传的。
	t.near(FlightBody.aim_assist_weight(SNAP), 0.0, 0.0001,
		"把 2.5 当**弧度**传 ⇒ 0.0（= 修之前产品里那个恒 0 的死代码）")
	t.near(FlightBody.aim_assist_weight(3.5), 0.0, 0.0001, "把 3.5 当**弧度**传 ⇒ 0.0")
	t.gt(FlightBody.aim_assist_weight(deg_to_rad(3.5)) - FlightBody.aim_assist_weight(3.5), 0.7,
		"同一个数字 3.5：按弧度读 0.7778、按度读 0.0000 —— 差 0.7778 就是单位口径的指纹")

	# ---- 最大偏转：本轮关于"和 README 需求 4 冲突多大"的核心量化 ----
	var peak := 0.0
	var peak_at := 0.0
	var a := SNAP
	while a <= CONE + 0.000001:
		var defl := a * FlightBody.aim_assist_weight(deg_to_rad(a))
		if defl > peak:
			peak = defl
			peak_at = a
		a += 0.001
	t.near(peak, PEAK, 0.003, "★ 全锥最大偏转 %.4f°（解析值 %.4f°）" % [peak, PEAK])
	t.near(peak_at, PEAK_ANG, 0.01, "★ 最大偏转出现在 %.2f° 处（解析值 3.50°）" % peak_at)
	t.lt(peak, 2.75,
		"★ 最大偏转 < 2.75° ⇒ 弹道仍基本跟随准星（README §16.1 需求 4 的冲突压到 3° 以内）")
	t.lt(peak - SNAP, 0.23,
		"★ 但它**比吸附半径多 %.4f°** ⇒ 「只做 2.5°」这句口径差着 9 个百分点，别拿 2.5 去论证"
			% (peak - SNAP))

	# 端点 + 粗抽样：锥内任意偏角都不许超过这个上界
	var worst := 0.0
	var n := 4000
	for i in n + 1:
		var ang := SNAP + (CONE - SNAP) * float(i) / float(n)
		worst = maxf(worst, ang * FlightBody.aim_assist_weight(deg_to_rad(ang)))
	t.lt(worst, PEAK + 0.0005,
		"锥内 %d 点抽样全部 ≤ %.4f（实测上确界 %.4f）" % [n + 1, PEAK, worst])
	t.near(worst, peak, 0.0005, "抽样上确界与逐点扫描的最大值一致（同一件事的两种量法）")


# ================================================================ ② 接线

static func _wiring(t: T) -> void:
	var fb := SuiteUiStyle._code(FB_SRC)
	var pc := SuiteUiStyle._code(PC_SRC)
	var ai := SuiteUiStyle._code(AI_SRC)

	var ap := _body(fb, "func aim_point")
	var beam := _body(fb, "func fire_beam")
	var vulcan := _body(fb, "func _fire_vulcan_round")

	# ---- 前置：函数体真的取到了（取不到时下面全是"空串里没有 X"的恒真）----
	t.gt(ap.length(), 500, "取到了 `aim_point()` 的函数体（%d 字符）" % ap.length())
	t.gt(beam.length(), 500, "取到了 `fire_beam()` 的函数体（%d 字符）" % beam.length())
	t.gt(vulcan.length(), 300, "取到了 `_fire_vulcan_round()` 的函数体（%d 字符）" % vulcan.length())

	# ---- 武器门：签名默认 false + 两处调用点各自表态 ----
	t.ok(fb.contains("beam_model := false, assist := false) -> Vector3:"),
		"`aim_point()` 新增第 6 个形参 `assist`，且**默认 false**（不表态就不代瞄）")
	t.eq(ap.count("aim_assist_enabled()"), 1, "`aim_point()` 里恰好查一次模式门")
	t.ok(ap.contains("if not assist or not aim_assist_enabled():"),
		"★ 两处门是 `and` 关系（`not (assist and enabled)` ⇒ 任一不满足就早退）")
	t.eq(fb.count("aim_point("), 3,
		"全文件 3 处 `aim_point(`：1 处定义 + 2 处调用（火神炮 / 光束）")
	t.ok(beam.contains("aim_point(origin, target, lead, 0.0, true, true)"),
		"★ 光束步枪那一处传 `assist = true`（**武器门**只在这里开）")
	t.not_ok(vulcan.contains("aim_assist"),
		"★ 火神炮那一处**一个 `aim_assist` 都不提** ⇒ 它的弹道逐位等于今天")
	t.eq(_argc(vulcan, "aim_point("), 4,
		"★ 火神炮那一处**只传 4 个实参**（`beam_model` / `assist` 两位都不表态 ⇒ 走默认 false）")
	t.eq(vulcan.count("aim_point("), 1, "火神炮仍然只调一次 `aim_point()`，参数表没动")
	t.eq(_argc(beam, "aim_point("), 6,
		"★ 光束那一处传满 6 个实参（最后一位 `assist = true` 就是武器门）")

	# ---- 修单位：那一层 `deg_to_rad()` 必须还在 ----
	t.ok(ap.contains("deg_to_rad(Ballistics.angle_off_boresight(to_bore, to_lead))"),
		"★ 单位包装还在：`deg_to_rad(Ballistics.angle_off_boresight(...))`")
	t.not_ok(ap.contains("aim_assist_weight(Ballistics.angle_off_boresight"),
		"★ 那一行**没有**退回「把度直接喂进按弧度比的函数」（= 死代码的写法）")
	t.ok(ap.contains("if w <= 0.0:") and ap.contains("return boresight"),
		"锥外（`w == 0`）也原样返回 `boresight`，不走 `slerp` ⇒ 锥外逐位不动")
	t.ok(ap.contains("if not is_player:"),
		"AI 那一道早退仍在（辅助瞄准只对玩家）")
	t.lt(ap.find("if lead:"), ap.find("aim_assist_enabled()"),
		"★ `lead` 的早退排在辅助瞄准**之前** ⇒ AI 口径（解析提前量）一个字节没变")

	# ---- 模式门：覆写在控制器上，且只有两处定义 ----
	t.eq(fb.count("func aim_assist_enabled("), 1,
		"`FlightBody` 上 1 处定义（虚函数，恒 false）")
	t.eq(pc.count("func aim_assist_enabled("), 1, "`PlayerController` 上 1 处覆写")
	t.ok(_body(pc, "func aim_assist_enabled").contains("return assist_on"),
		"★ 覆写体就是 `return assist_on`（门 = 辅助驾驶开关，**没有第二个开关**）")
	t.not_ok(fb.contains("assist_on"),
		"★ `FlightBody` 里**不出现** `assist_on` —— 在基类引用它是解析期错误（整套件会编译不过）")
	t.not_ok(ai.contains("aim_assist_enabled"),
		"★ `BanditAI` 不覆写模式门 ⇒ AI 永远拿不到辅助瞄准（倍率机器本来就解提前量）")

	# ---- 门跟着唯一那个开关走 ----
	t.eq(pc.count("assist_on := "), 1, "`assist_on` 只有 1 处声明（初值 false）")
	t.eq(pc.count("assist_on = not assist_on"), 1,
		"取反只有 1 处（`_tick_assist_toggle()` 里那一次点按）—— 门不再有别的开关")


# ================================================================ ③ 真机对象

static func _live(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	c.name = "AimAssistStage"
	host.add_child(c)

	var pc := PlayerController.new()
	pc.name = "AimAssistProbe"
	pc.rifle_assist_v1 = false # This fixture verifies the preserved baseline / first-person path.
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.projectile_container = c
	c.add_child(pc)
	pc.global_position = LIVE_POS
	# ⚠️ 关掉控制：`_think()` 哨兵段直接 return（**不会**碰 `assist_on`），
	# 而开着控制时 `_read_aim_input()` 每帧会把 `aim_dir` 按鼠标重写。
	pc.controls_enabled = false
	pc.set_aim_direction(Vector3.FORWARD)

	var foe := Node3D.new()
	foe.name = "AimAssistFoe"
	c.add_child(foe)

	t.ok(pc.aim_forward().is_equal_approx(Vector3.FORWARD),
		"前置：准星方向钉在 +FORWARD（%s）" % str(pc.aim_forward()))
	t.not_ok(pc.aim_assist_enabled(), "前置：默认辅助驾驶关 ⇒ 模式门关")

	var origin := pc.global_position
	var speed := SuitProfile.vulcan_speed()

	# ---- 3°：辅助开 ⇒ 必须拉 ----
	pc.assist_on = true
	t.ok(pc.aim_assist_enabled(), "★ 辅助开 ⇒ `aim_assist_enabled()` 为真（**真覆写**，不是测试里的假实现）")

	var bore := _place(pc, foe, 3.0, LIVE_D)
	var lead_pt: Vector3 = pc._lead_point(origin, foe.global_position, Vector3.ZERO, speed, false)
	t.ok(lead_pt.is_equal_approx(foe.global_position),
		"前置：靶机静止 ⇒ 提前量点 = 靶机位置（差 %.6f m）"
			% (lead_pt - foe.global_position).length())
	var ang := Ballistics.angle_off_boresight(bore - origin, lead_pt - origin)
	t.near(ang, 3.0, 0.05, "前置：这一摆法的偏角实测 %.3f°（目标 3.000°）" % ang)

	var w_expect := 1.0 - (3.0 - 2.5) / (7.0 - 2.5)
	var off := pc.aim_point(origin, foe, false, speed, false, true)
	var defl := Ballistics.angle_off_boresight(bore - origin, off - origin)
	t.gt(defl, 2.0, "★ 偏 3° + 辅助开 ⇒ 弹道被拉走 %.4f°（**不是** boresight 了）" % defl)
	t.near(defl, 3.0 * w_expect, 0.05,
		"★ 拉走量 = 偏角 × 权重 = 3.0° × 0.7778 = %.4f°" % (3.0 * w_expect))
	t.lt(defl, 2.75, "★ 而且**没有**超过 2.7223° 这个解析上界（与 ① 段同一条牙）")
	t.gt((off - origin).normalized().dot((lead_pt - origin).normalized()), 0.9995,
		"拉的方向朝**提前量点**（dot = %.7f；不拉时只有 cos3° = 0.99863）"
			% (off - origin).normalized().dot((lead_pt - origin).normalized()))
	print("        [真机读数] 偏 3°：boresight→瞄准点 %.4f°（权重 %.4f）｜拉到离准星 %.4f°"
		% [ang, w_expect, defl])

	# ---- 20°：锥外 ⇒ 逐位不动 ----
	bore = _place(pc, foe, 20.0, LIVE_D)
	var off20 := pc.aim_point(origin, foe, false, speed, false, true)
	t.eq(off20, bore, "★ 偏 20°（锥外）⇒ 返回点**逐位**等于 boresight")

	# ---- 辅助关 ⇒ 模式门关 ⇒ 逐位不动 ----
	bore = _place(pc, foe, 3.0, LIVE_D)
	pc.assist_on = false
	t.not_ok(pc.aim_assist_enabled(), "关辅助 ⇒ 门关")
	var off_off := pc.aim_point(origin, foe, false, speed, false, true)
	t.eq(off_off, bore, "★ 辅助关 ⇒ 逐位等于 boresight（弹道回到今天，一个字都没动）")

	# ---- 火神炮口径（不传第 6 个实参）⇒ 即使辅助开也不动 ----
	pc.assist_on = true
	var off_vu := pc.aim_point(origin, foe, false, speed)
	t.eq(off_vu, bore, "★ 火神炮口径（不传 `assist`）⇒ 逐位等于 boresight")
	t.not_ok(off_vu.is_equal_approx(off),
		"★ 同一个 3° 摆法：光束被拉走（%s）、火神炮没动（%s）—— 两者必须不同"
			% [str(off), str(off_vu)])

	pc.controls_enabled = true
	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ================================================================ ④ 提示圈同源

static func _hud(t: T) -> void:
	var hud := SuiteUiStyle._code(HUD_SRC)
	var fb := SuiteUiStyle._code(FB_SRC)
	var dt := _body(hud, "func _draw_target")

	t.gt(dt.length(), 1500, "取到了 `_draw_target()` 的函数体（%d 字符）" % dt.length())

	# ---- 同源：吸附用的阈值只有一处真源 ----
	t.eq(fb.count("AIM_ASSIST_SNAP_DEG :="), 1,
		"★ 常量在 `flight_body.gd` 恰好声明 1 次（弹道那一侧）")
	t.eq(hud.count("AIM_ASSIST_SNAP_DEG :="), 0,
		"★ HUD **不许**自己再声明一个 —— 两处各写一个数就是「口径不一致」的温床")
	t.eq(dt.count("FlightBody.AIM_ASSIST_SNAP_DEG"), 1,
		"★ HUD 恰好读它 1 次（是引用，不是写死的数）")
	t.eq(dt.count("player.aim_assist_enabled()"), 1,
		"提醒挂在**模式门**上：辅助关时不提醒（否则会对着关掉的系统喊吸附）")

	var hit := ""
	for line: String in dt.split("\n"):
		if line.contains("FlightBody.AIM_ASSIST_SNAP_DEG"):
			hit = line
	t.ok(hit != "", "取到了读那一行：`%s`" % hit.strip_edges())
	t.not_ok(_has_digit(hit),
		"★ 那一行**一个数字都没有**（有人把它换成字面量 2.5 就会被这条当场抓到）")

	# ---- 提醒是"看得见"的 ----
	t.ok(dt.contains("吸附"), "★ 提示文字上屏（含「吸附」二字）")
	t.ok(dt.contains("UILayout.LINE_STRUCT"),
		"画环走结构线宽档（`suite_ui_style` 的线宽闸门要求实参里字面出现它）")
	t.ok(dt.contains("DANGER"), "吸附环用 DANGER 色（与常亮的 IFIELD 提前量圈区分开）")
	t.ok(dt.contains("_text_center("), "用 `_text_center()` 上字")
	t.not_ok(dt.contains("**"), "上屏文字里**没有** markdown 的 `**`（会原样打出来）")

	# ---- 用户要的"预测提示圈"是既有件，别在加提醒时把它删了 ----
	t.ok(dt.contains("lock.gun_lead_point(SuitProfile.vulcan_speed())"),
		"机炮提前量圈的真源仍在")
	t.ok(dt.contains("lock.gun_lead_point_beam()"), "光束提前圈的真源仍在")
	t.gt(float(dt.count("draw_arc(")), 4.0,
		"`_draw_target()` 里仍然画着 5 处以上的环（%d 处）" % dt.count("draw_arc("))
