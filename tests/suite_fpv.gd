class_name SuiteFPV
extends RefCounted
## 第一人称（座舱视角）· 轮 20。
##
## 用户原话：「做一个第一人称模式，然后把第一人称模式的开关放到设置里面，
## 再加一个开关提醒：开启本模式会导致强烈的 3d 眩晕，是否还要开启？」
##
## 拆成七组断言：
##   1. **设置项**（`Settings.first_person`）：默认关、存档往返、标签；
##   2. **眩晕警告门**（`MainMenu.Stage.FPV_CONFIRM`）：默认停在「否」、
##      写入被下标守卫包着、Esc 退出一条路完全不碰设置、已开启时不再问；
##   3. **镜头本体**（`ChaseCamera` 的 FPV 通道）：眼位落到头部锚点、
##      视线贴机头、进出**渐变不瞬移**、换机时直接落位；
##   4. **抖动补偿**（`_fx_gain` / `_fx_pos_gain`）：只在 FPV 里生效、
##      旋转与位置**各用自己那套跟随速率**、且**不许绕过** `shake_scale`；
##   5. **自机模型可见性**（`FlightBody.set_model_visible`）：只藏自己、不复活残骸；
##   6. **全周天刻度导轨**（`FlightHUD.rail_dirs`，轮 21）：横轨 + 竖轨、
##      地平线圈躺在水平面上、整颗球上最坏的空隙 < 12°（"无死角"的量化证明）；
##   7. **座舱仪表台**（`FlightHUD.dash_layout`，轮 21）：屏幕最下方一整块台，
##      雷达居中嵌在中央格里；窄窗口下**自己收窄**，绝不压左下血条 / 右下弹药。
##
## ## 两条测试装置的规矩（都是踩过坑换来的）
##   - **相机必须进树**：不进树时 `global_transform` 恒为单位阵，
##     存取两端一起错、正好抵消（`_apply_kick` 的注释点名过这个坑）。
##   - **`set_physics_process(false)`，帧由测试自己喂**：`delta` 才是已知量，
##     断言才能写成等式而不是"大概是这个量级"。
##
## ## 为什么警告门那几条**不靠注入按键**
## `suite_tutorial` 实测过：无头环境里 `Input.action_press` 的 `just_pressed`
## 帧戳不可靠（40 次注入漏一次）。所以这里把安全性钉在**确定性的事实**上：
## 下标顺序（`FPV_CONFIRM_ROWS[0]` = 否）、每次进门的重置、以及
## **源码结构**（写入唯一且被 `if fpv_confirm_row == FPV_CONFIRM_YES:` 包着、
## 返回分支在写入之前）—— 这三条合起来就是那句安全性的完整证明，
## 而且不会因为引擎的输入帧戳抽风而假红。

const SETTINGS_SRC := "res://scripts/autoload/settings.gd"
const MENU_SRC := "res://scripts/ui/main_menu.gd"
const CAMERA_SRC := "res://scripts/flight/chase_camera.gd"
const BODY_SRC := "res://scripts/flight/flight_body.gd"
const MAIN_SRC := "res://scripts/main.gd"
const PLAYER_SRC := "res://scripts/flight/player_controller.gd"
const HUD_SRC := "res://scripts/ui/hud.gd"


static func run(t: T, host: Node) -> void:
	var backup: bool = Settings.first_person
	_settings(t)
	await _gate(t, host)
	await _lens(t, host)
	await _fx(t, host)
	await _model(t, host)
	_rails(t)
	_dash(t)
	_wiring(t)
	_hotkey25(t)

	# ⚠️ 必须还原：这个开关是**玩家的**，测完留在"开"上等于替玩家打开了最晕的模式。
	Settings.first_person = backup
	Settings.save_config()
	t.eq(Settings.first_person, backup, "套件跑完后第一人称开关已还原（不替玩家做决定）")
	await host.get_tree().process_frame

	# ⚠️ 中央屏那一节**必须排在最后**：`t.suite()` 会把它**之前**累积的断言结算给上一个节 ——
	# 插在前面的节会把上面那条「收尾还原」断言**收进自己名下**，于是逐套件对账里会出现
	# 「自由切换节 −1、新节 +1」这种要解释半天的账（本轮第一次跑就是这个数）。
	_screen31(t)


# ============================================================ 工具

## 取某个函数的**函数体**（从标题之后到下一个 `func ` 之前）。
##
## ⚠️ 存在的理由：「写入有没有被守卫包着」这种断言不能靠"整篇里有没有这两个字符串"——
## 那样写的话，把守卫删掉、把写入挪到函数开头，测试照样绿。
## 必须能在**函数内部**比先后、数次数。
static func _func_body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var rest := src.substr(i + header.length())
	var j := rest.find("\nfunc ")
	return rest if j < 0 else rest.substr(0, j)


## 工程实际的物理步长（1/s）。**不写死 1/60** —— 这个工程曾经有人按 20 Hz
## 推过一整段注释（见 `chase_camera.gd` 里那条 ⚠️），写死的数会跟着一起错。
static func _dt() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


# ============================================================ ① 设置项

static func _settings(t: T) -> void:
	t.suite("FPV / 设置：默认关 / 标签 / 存档往返")
	var src := SuiteUiStyle._code(SETTINGS_SRC)

	# ---- 默认关：查**声明**，不查运行时的值 ----
	# 运行时的值可能被上一轮测试或玩家自己存成 true —— 那不代表出厂默认。
	t.ok(src.contains("var first_person := false"),
		"出厂默认 = 关（危险选项不默认开）")
	t.ok(src.contains("cfg.set_value(\"camera\", \"first_person\", first_person)"),
		"开关会写进存档")
	t.ok(src.contains("cfg.get_value(\"camera\", \"first_person\", first_person)"),
		"存档缺这一项时退回当前值 ⇒ 全新安装一定是关")

	# ---- 标签 ----
	Settings.set_first_person(true)
	t.ok(Settings.first_person, "set_first_person(true) 真的写进了状态")
	t.ok(Settings.first_person_label().contains("座舱"),
		"开着时标签写明是「座舱视角」而不是一个光秃秃的「开」：%s"
			% Settings.first_person_label())
	t.eq(Settings.first_person_label() == "", false, "标签不为空（设置页不会画出一行空值）")
	Settings.set_first_person(false)
	t.not_ok(Settings.first_person, "set_first_person(false) 也生效（关掉不需要任何确认）")
	t.eq(Settings.first_person_label(), "关", "关着时标签是「关」")

	# ---- 存档往返 ----
	Settings.set_first_person(true)
	Settings.first_person = false          # 先把内存搅乱，再从文件读回来
	Settings.load_config()
	t.ok(Settings.first_person, "第一人称开关能存下来也能读回来")

	# ---- 警示语唯一真源（文案本身属于设置项，不归 UI 管）----
	var warn: String = Settings.FPV_WARNING
	t.ok(warn.contains("眩晕"), "警示语点名了风险是「眩晕」：%s" % warn)
	t.ok(warn.contains("3D") or warn.contains("3d"),
		"警示语写明了是 3D 眩晕（不是笼统的「不适」）")
	t.ok(warn.contains("是否还要开启") or warn.ends_with("？"),
		"警示语是个**问句** —— 要玩家回答，不是一条通知")
	t.ok(warn.length() >= 16, "警示语不是糊弄话（%d 字）" % warn.length())


# ============================================================ ② 眩晕警告门

static func _gate(t: T, host: Node) -> void:
	t.suite("FPV / 眩晕警告门：默认停在「否」")
	# **下标 0 必须是「否」**，而且每次进门都重置回 0。
	# 这道门全部的价值就在"它默认不让你过"：默认停在「是」的话，
	# 玩家一路连按确认就会顺手把最晕的模式打开，那还不如不做这道门。
	t.eq(MainMenu.FPV_CONFIRM_ROWS.size(), 2, "警告框正好两个选项")
	t.ok(str(MainMenu.FPV_CONFIRM_ROWS[0]).contains("否"), "下标 0 是「否」（顺序就是安全性）")
	t.ok(str(MainMenu.FPV_CONFIRM_ROWS[1]).contains("是"), "下标 1 是「是」")
	t.eq(MainMenu.FPV_CONFIRM_YES, 1, "「是」的下标抽成了常量（输入与绘制读同一个数）")
	t.not_ok(MainMenu.FPV_CONFIRM_YES == 0, "「是」**不在**下标 0 —— 任何重排都必须把这条搞红")
	t.eq(MainMenu.nav_axis(MainMenu.Stage.FPV_CONFIRM), MainMenu.Nav.Y,
		"警告框用竖轴（上/下选）")

	var menu := MainMenu.new()
	host.add_child(menu)
	# 关掉引擎驱动：`_process` 一旦跑起来，`stage == SETTINGS` 时它会去调
	# `_setting_step()`，把测试摆好的状态搅乱。
	menu.set_process(false)
	menu.set_physics_process(false)

	# ---- 未开启 ⇒ 拨右 / Enter 都进门，而且**每次都回到「否」** ----
	Settings.first_person = false
	menu.set("stage", MainMenu.Stage.SETTINGS)
	menu.set("fpv_confirm_row", MainMenu.FPV_CONFIRM_YES)   # 假装上次停在了「是」
	menu.call("_open_fpv_confirm")
	t.eq(int(menu.get("stage")), MainMenu.Stage.FPV_CONFIRM,
		"没开着的时候拨右 / 按 Enter ⇒ 进警告框（不是直接开）")
	t.eq(int(menu.get("fpv_confirm_row")), 0,
		"进门的瞬间重置回「否」—— 上次停在「是」也不例外")

	# ---- 已经开启 ⇒ 不再问（这道门守的是"别不小心打开"，不是"不许改主意"）----
	Settings.first_person = true
	menu.set("stage", MainMenu.Stage.SETTINGS)
	menu.set("fpv_confirm_row", MainMenu.FPV_CONFIRM_YES)
	menu.call("_open_fpv_confirm")
	t.eq(int(menu.get("stage")), MainMenu.Stage.SETTINGS, "已经开着的时候再拨 ⇒ 不弹门")
	t.eq(int(menu.get("fpv_confirm_row")), MainMenu.FPV_CONFIRM_YES,
		"……而且不碰光标位置（只出音效，什么都不改）")

	# ---- Esc 保险丝：警告框卡住时永远有一条**不生效**的出口 ----
	var fuse := SuiteUiStyle._code(MENU_SRC)
	t.ok(fuse.contains("or stage == Stage.FPV_CONFIRM"),
		"Esc 保险丝（§4.8.4 第③层，不走 InputMap）覆盖了警告框")

	menu.free()
	Settings.first_person = false
	await host.get_tree().process_frame


# ============================================================ ③ 镜头本体

static func _lens(t: T, host: Node) -> void:
	t.suite("FPV / 镜头：眼位落到头部锚点 · 视线贴机头")
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "FpvBody"
	pc.profile = SuitProfile.xi()
	pc.team = 0
	c.add_child(pc)
	pc.set_physics_process(false)          # 冻结机体：位姿完全由测试摆
	pc.global_position = Vector3(0, 900, 0)
	var cam := ChaseCamera.new()
	host.add_child(cam)
	cam.set_physics_process(false)
	cam.current = false
	cam.set_target(pc)
	cam.boost_amount = 0.0
	cam.shake_scale = 1.0

	# ---- 眼位的真源是**头部锚点**（鸭子类型 `rig_anchor`，不依赖 FlightBody 类型）----
	var head: Vector3 = pc.rig_anchor("head")
	t.gt(head.length(), 0.001, "机体能给出头部锚点（眼位的真源）: %v" % head)
	var eye: Vector3 = cam._fpv_eye_local()
	t.near(eye.y, head.y + ChaseCamera.FPV_EYE_UP, 0.001, "眼位 = 锚点抬高 FPV_EYE_UP")
	t.near(eye.z, head.z - ChaseCamera.FPV_EYE_FWD, 0.001,
		"眼位 = 锚点前移 FPV_EYE_FWD（−Z 是机头方向）")
	t.near(eye.x, head.x, 0.001, "眼位不偏离机体中线")

	# ---- 兜底：目标不是机体（或干脆没有目标）也不能炸 ----
	var plain := Node3D.new()
	host.add_child(plain)
	cam.target = plain
	t.eq(cam._fpv_eye_local(), ChaseCamera.FPV_FALLBACK_EYE,
		"目标没有 rig_anchor ⇒ 退回兜底眼位")
	cam.target = null
	t.eq(cam._fpv_eye_local(), ChaseCamera.FPV_FALLBACK_EYE, "没有目标 ⇒ 同样退兜底，不炸")
	cam.target = pc

	# ---- 机位：座舱 vs 五十米外的追尾 ----
	cam.first_person = false
	cam._fpv_blend = 0.0
	var chase_pos: Vector3 = cam._desired_position()
	var chase_dist: float = chase_pos.distance_to(pc.global_position)
	cam.first_person = true
	cam._fpv_blend = 1.0
	var fpv_pos: Vector3 = cam._desired_position()
	var fpv_dist: float = fpv_pos.distance_to(pc.global_position)
	var want_eye: Vector3 = pc.global_transform * cam._fpv_eye_local()
	t.gt(chase_dist, 40.0,
		"对照：追尾机位离机体原点 %.1f m（offset.z = 53）" % chase_dist)
	t.lt(fpv_pos.distance_to(want_eye), 0.25,
		"FPV 眼位 = 机体局部眼位变换到世界（速度 0 ⇒ 前馈项为 0）")
	t.lt(fpv_dist * 3.0, chase_dist,
		"FPV 眼位（%.1f m）比追尾机位（%.1f m）近 3 倍以上 —— 座舱不是「往前挪一点的追尾」"
			% [fpv_dist, chase_dist])

	# ---- 视线：FPV 下直接给机头方向 ----
	var nose: Vector3 = -pc.global_transform.basis.z
	var fwd_fpv: Vector3 = -cam._desired_basis().z
	t.gt(fwd_fpv.dot(nose), 0.9999,
		"FPV 视线与机头方向重合（地平线跟着机体滚转；准星不会和机头分家）")
	cam.first_person = false
	cam._fpv_blend = 0.0
	var fwd_chase: Vector3 = -cam._desired_basis().z
	# ⚠️ 余量取 0.001 而不是"看着差不多"的 0.005：实测追尾镜头的 dot 是 **0.9974**
	#（它看向机头前方 36 m 再抬高 2.6 m 的人造点 ⇒ 本来就带一点俯角），
	# 留太大余量这条断言就永远真、等于没测。
	t.lt(fwd_chase.dot(nose), 0.999,
		"对照：追尾镜头是俯视机背（dot %.4f < 0.999）" % fwd_chase.dot(nose))
	t.gt(fwd_fpv.dot(nose), fwd_chase.dot(nose) + 0.001,
		"……而 FPV 直接给机头方向（%.4f > %.4f）—— 准星不会和机头分家"
			% [fwd_fpv.dot(nose), fwd_chase.dot(nose)])

	# ---- 跟随速率：中途按混合量线性过渡 ----
	cam._fpv_blend = 0.0
	t.near(cam._pos_lag(), cam.follow_lag, 0.0001, "追尾档位置速率 = follow_lag")
	t.near(cam._rot_lag(), cam.rotate_lag, 0.0001, "追尾档姿态速率 = rotate_lag")
	cam._fpv_blend = 1.0
	t.near(cam._pos_lag(), ChaseCamera.FPV_LAG, 0.0001, "FPV 档位置速率压到 FPV_LAG")
	t.near(cam._rot_lag(), ChaseCamera.FPV_LAG, 0.0001, "FPV 档姿态速率压到 FPV_LAG")
	cam._fpv_blend = 0.5
	t.between(cam._pos_lag(), cam.follow_lag, ChaseCamera.FPV_LAG,
		"中间档在两者之间过渡（不是硬跳档）")

	# ---- 进 / 出都走渐变，**不许瞬移** ----
	t.suite("FPV / 进出渐变（座舱与追尾差五十米，硬切会甩玩家一下）")
	var dt := _dt()
	# 换机（= 每局开始）时**直接落位**：无 target 时 `_physics_process` 早退，
	# 混着来的话第一帧会从上一局的混合量渐变过去。
	cam.first_person = true
	cam._fpv_blend = 0.0
	cam.set_target(pc)
	t.near(cam.fpv_blend(), 1.0, 0.0001, "开着 FPV 时换机 ⇒ 混合量直接落位 1.0")
	cam.first_person = false
	cam.set_target(pc)
	t.near(cam.fpv_blend(), 0.0, 0.0001, "关着 FPV 时换机 ⇒ 混合量直接落位 0.0")

	cam.first_person = true
	cam.global_position = Vector3(0, 900, 0)
	cam.global_transform = Transform3D(Basis.IDENTITY, cam.global_position)
	cam._physics_process(dt)
	t.near(cam.fpv_blend(), ChaseCamera.FPV_RATE * dt, 0.0002,
		"第一步只走 FPV_RATE×dt = %.4f（不跳变；跳变本身就是晕动症的引信）"
			% (ChaseCamera.FPV_RATE * dt))
	var prev := cam.fpv_blend()
	var mono := true
	for i in 40:
		cam._physics_process(dt)
		if cam.fpv_blend() < prev:
			mono = false
		prev = cam.fpv_blend()
	t.ok(mono, "混合量单调不减（不来回抖）")
	t.near(cam.fpv_blend(), 1.0, 0.0001,
		"约 %.2f s 内走完（1 / FPV_RATE）" % (1.0 / ChaseCamera.FPV_RATE))
	cam.first_person = false
	for i in 40:
		cam._physics_process(dt)
	t.near(cam.fpv_blend(), 0.0, 0.0001, "关掉也走同一条渐变（不瞬间弹回五十米外）")

	cam.queue_free()
	pc.free()
	plain.free()
	c.free()
	await host.get_tree().process_frame


# ============================================================ ④ 抖动补偿

static func _fx(t: T, host: Node) -> void:
	t.suite("FPV / 抖动补偿：只在 FPV 里生效，且不绕过 shake_scale")
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "FpvFxBody"
	pc.profile = SuitProfile.xi()
	pc.team = 0
	c.add_child(pc)
	pc.set_physics_process(false)
	pc.global_position = Vector3(0, 900, 0)
	var cam := ChaseCamera.new()
	host.add_child(cam)
	cam.set_physics_process(false)
	cam.current = false
	cam.set_target(pc)
	cam.shake_scale = 1.0
	var dt := _dt()

	# ---- 追尾档：一个字节都不改 ----
	cam._fpv_blend = 0.0
	cam._update_fx_gain(dt)
	t.near(cam.fx_gain(), 1.0, 0.0001, "追尾镜头下旋转补偿 = 1.0（不动）")
	t.near(cam.fx_pos_gain(), 1.0, 0.0001, "追尾镜头下位置补偿 = 1.0（不动）")

	# ---- FPV 档：各用**自己的**跟随速率算 ----
	cam._fpv_blend = 1.0
	cam._update_fx_gain(dt)
	var want_rot: float = (1.0 - exp(-cam._rot_lag() * dt)) / (1.0 - exp(-cam.rotate_lag * dt))
	var want_pos: float = (1.0 - exp(-cam._pos_lag() * dt)) / (1.0 - exp(-cam.follow_lag * dt))
	t.near(cam.fx_gain(), want_rot, 0.001,
		"旋转补偿 = 两个回收比例之比（实得 %.3f）" % cam.fx_gain())
	t.near(cam.fx_pos_gain(), want_pos, 0.001,
		"位置补偿 = **位置通道自己**的回收比例之比（实得 %.3f）" % cam.fx_pos_gain())
	t.gt(cam.fx_gain(), 3.0,
		"FPV 下旋转抖动被补回 %.1f 倍 —— 不补的话座舱里挨打几乎看不见" % cam.fx_gain())
	t.lt(cam.fx_pos_gain(), cam.fx_gain(),
		"位置补偿 < 旋转补偿（位置走 follow_lag = 6.5，追尾下回收本来就更快）")

	# ---- 补的是**幅度**，不是闸门：`shake_scale = 0` 仍然一滴都不抖 ----
	cam.shake_scale = 0.0
	cam._shake = 1.0
	cam.global_transform = Transform3D(cam._desired_basis(), cam.global_position)
	var q_before := cam.global_transform.basis.get_rotation_quaternion()
	cam._apply_shake(dt)
	var moved := rad_to_deg(q_before.angle_to(
		cam.global_transform.basis.get_rotation_quaternion()))
	t.lt(moved, 0.0001,
		"补偿**不许绕过**「关镜头抖动」：shake_scale = 0 时转角 %.5f°" % moved)
	t.lt(cam._shake, 1.0, "……但衰减照走（无障碍铁律：关着的时候池子要放空）")
	cam.shake_scale = 1.0

	# ---- 实测：每帧转角确实是 fx_gain 倍（不是只把系数写在那儿好看）----
	var sum_chase := 0.0
	cam._fpv_blend = 0.0
	cam._update_fx_gain(dt)
	for i in 40:
		cam._shake = 1.0
		cam.global_transform = Transform3D(cam._desired_basis(), cam.global_position)
		var q0 := cam.global_transform.basis.get_rotation_quaternion()
		cam._apply_shake(dt)
		sum_chase += rad_to_deg(q0.angle_to(
			cam.global_transform.basis.get_rotation_quaternion()))
	var sum_fpv := 0.0
	cam._fpv_blend = 1.0
	cam._update_fx_gain(dt)
	for i in 40:
		cam._shake = 1.0
		cam.global_transform = Transform3D(cam._desired_basis(), cam.global_position)
		var q0 := cam.global_transform.basis.get_rotation_quaternion()
		cam._apply_shake(dt)
		sum_fpv += rad_to_deg(q0.angle_to(
			cam.global_transform.basis.get_rotation_quaternion()))
	var ratio := sum_fpv / maxf(sum_chase, 0.0001)
	t.between(ratio, cam.fx_gain() * 0.7, cam.fx_gain() * 1.3,
		"实测每帧转角是追尾的 %.2f 倍（系数 %.2f）—— 补偿真的落在幅度上"
			% [ratio, cam.fx_gain()])

	# ---- 视野：随速度张开的那三项压一半，命中脉冲（打击感正反馈）不压 ----
	var src := SuiteUiStyle._code(CAMERA_SRC)
	t.ok(src.contains("FPV_FOV_DYN"),
		"FPV 把「随速度张开的动态 FOV」压了一档（视野扩张是晕动症最直接的引信）")
	t.ok(src.contains("_fov_kick * motion_scale")
			and not src.contains("_fov_kick * dyn"),
		"但**没压** `_fov_kick` —— 那是「我打中了」的正反馈，压它等于压打击感")

	cam.queue_free()
	pc.free()
	c.free()
	await host.get_tree().process_frame


# ============================================================ ⑤ 自机模型可见性

static func _model(t: T, host: Node) -> void:
	t.suite("FPV / 自机模型：只藏自己、不复活残骸")
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "FpvVisBody"
	pc.profile = SuitProfile.xi()
	pc.team = 0
	c.add_child(pc)
	pc.set_physics_process(false)
	await host.get_tree().process_frame

	t.ok(pc.model_root != null and is_instance_valid(pc.model_root),
		"机体建出了视觉层根节点 model_root")
	t.ok(pc.rig != null and is_instance_valid(pc.rig),
		"占位骨架 rig 也在（锚点/炮口/喷口挂在它上面）")

	var rig_was := true
	if pc.rig != null and is_instance_valid(pc.rig):
		rig_was = pc.rig.visible
	pc.set_model_visible(false)
	t.not_ok(pc.model_visible(), "set_model_visible(false) 真的把自机模型藏了")
	if pc.rig != null and is_instance_valid(pc.rig):
		t.eq(pc.rig.visible, rig_was,
			"只动 model_root —— 骨架层（锚点/炮口）的可见性不受影响")
	else:
		t.eq(0, 0, "（本机体没有占位骨架 rig，跳过骨架层可见性检查）")
	pc.set_model_visible(true)
	t.ok(pc.model_visible(), "set_model_visible(true) 能收回来")
	pc.set_model_visible(true)
	t.ok(pc.model_visible(), "幂等：重复置同一个值不出错")
	pc.set_model_visible(false)
	pc.set_model_visible(false)
	t.not_ok(pc.model_visible(), "幂等：重复置 false 也不出错")

	# ---- 接线：main 每帧驱动，且**必须**带 player.alive ----
	var main_src := SuiteUiStyle._code(MAIN_SRC)
	t.ok(main_src.contains("player.set_model_visible((not Settings.first_person) and player.alive)"),
		"main 每帧驱动可见性，且带 `and player.alive` —— 不覆盖 die() 里的隐藏残骸")
	t.eq(main_src.count("set_model_visible("), 1,
		"只对 player 调一次 —— **只藏自己**，敌机/僚机一行都不碰")
	var body_src := SuiteUiStyle._code(BODY_SRC)
	t.ok(body_src.contains("model_root.visible = false"),
		"die() 里隐藏残骸那一句还在（不能被 FPV 的驱动顶掉）")
	t.ok(body_src.contains("func set_model_visible"),
		"FlightBody 提供可见性开关（带幂等短路）")

	pc.free()
	c.free()
	await host.get_tree().process_frame


# ============================================================ ⑥ 全周天刻度导轨（轮 21）

## 需求原文：「记得做全周天 720° 无死角的刻度线导轨，横轨和竖轨，
## 不然机体转体一下导轨贴图就消失了。」
##
## 这一节**全部打在纯函数 `FlightHUD.rail_dirs()` 上** —— 它只吐方向，
## 不吐屏幕坐标、不碰相机，所以「覆盖全周天、一个洞都没有」是**可断言的**。
## 靠人对着截图找哪里缺一块是找不到的：屏幕每帧都在动，缺一处根本看不出来。
##
## ⚠️ 参考系（世界 / 地平线对齐，不是钉在机身上）在 `hud.gd` 那段分节注释里
## 写了两条理由。这里只钉**后果**：地平线圈必须真的躺在水平面上、
## 滚转时整层刻度会跟着转 —— 那才是「能读出我歪没歪」的前提。
static func _rails(t: T) -> void:
	t.suite("FPV / 全周天刻度导轨：横轨 + 竖轨 · 覆盖无死角")
	var list: Array = FlightHUD.rail_dirs()
	t.gt(list.size(), 0, "刻度表非空（%d 条）" % list.size())

	var mer := 0
	var par := 0
	var hor := 0
	var majors := 0
	var centers: Array = []
	for d in list:
		if bool(d["meridian"]):
			mer += 1
		else:
			par += 1
		if bool(d["horizon"]):
			hor += 1
		if bool(d["major"]):
			majors += 1
		centers.append(((d["a"] as Vector3) + (d["b"] as Vector3)).normalized())

	# ---- 横轨与竖轨**两样都得在**（用户点名的就是这两样）----
	var n_mer := int(round(360.0 / FlightHUD.RAIL_MERIDIAN_DEG))
	var n_par := int(round(180.0 / FlightHUD.RAIL_PARALLEL_DEG)) - 1
	var n_pt := int(round(90.0 / FlightHUD.RAIL_TICK_DEG)) * 2 + 1
	var n_az := int(round(360.0 / FlightHUD.RAIL_TICK_DEG))
	t.eq(mer, n_mer * n_pt,
		"竖轨 = %d 条经线 × %d 点（每条从 −90° 竖到 +90°，含天顶与天底）" % [n_mer, n_pt])
	t.eq(par, n_par * n_az,
		"横轨 = %d 圈纬线 × %d 点（每圈绕满 360°，不是半圈）" % [n_par, n_az])
	t.eq(mer + par, 1236, "出厂配置合计 %d 条刻度" % (mer + par))
	t.lt(mer + par, 3000,
		"总量有上限（%d 条）—— 谁把 RAIL_TICK_DEG 调细一档，这条先炸，\n\t\t别等真机上掉帧才发现" % (mer + par))

	# ---- 地平线圈 ----
	# 它是这一层里唯一"亮一档"的东西，因为它直接回答"地平线在哪"。
	var n_horizon := int(round(360.0 / FlightHUD.RAIL_TICK_DEG))
	t.eq(hor, n_horizon, "地平线圈正好一整圈（%d 个刻度）" % n_horizon)
	var off_plane := 0
	for d in list:
		if bool(d["horizon"]):
			var hc: Vector3 = ((d["a"] as Vector3) + (d["b"] as Vector3)).normalized()
			if absf(hc.y) > 0.002:
				off_plane += 1
	t.eq(off_plane, 0,
		"……而且每一条都落在**水平面**上（y 分量 = 0）—— 参考系钉在世界，不是机体")

	# ---- 天顶 / 天底也得有刻度 ----
	# 纬线圈在 ±90° 退化成**一个点**、画不出东西；那两处只能靠经线的端点来盖。
	# 这就是"横轨和竖轨都要"最硬的一条实证：只有横轨的话，攒到天顶就是一块空白。
	var top := 0
	var bottom := 0
	for c: Vector3 in centers:
		if c.y > 0.999:
			top += 1
		if c.y < -0.999:
			bottom += 1
	t.gt(top, 0, "天顶有刻度（%d 条经线的端点）" % top)
	t.gt(bottom, 0, "天底也有（%d 条）—— 翻过来朝天飞时不会是一块空白" % bottom)

	# ---- 「无死角」的**量化证明** ----
	# 在整颗球上均匀撒点（斐波那契球），量"每个点到最近刻度的角距"，取最坏值。
	# 口径：最坏的空隙出现在两条经线正中叠上两条纬线正中，解析值约 7.9°，实测 7.7°。
	# 阈值 12° 是"看上去仍是连续刻度"的上限，也给改常量留了余量。
	var worst := _worst_gap_deg(centers, 600)
	t.lt(worst, 12.0,
		"全周天无死角：整颗球上最坏的空隙只有 %.2f°（阈值 12°）" % worst)

	# ---- 用户那句话的**直接反证**：任何朝向都不许是空的 ----
	# 「不然机体转体一下导轨贴图就消失了」—— 那就把朝向铺开扫一遍：
	# 滚转 4 档 × 俯仰 5 档 × 偏航 8 档 = 160 个机头指向，
	# 每一个都得看得见刻度，否则就是用户担心的那种"转过去就没了"。
	#
	# ⚠️ 走的是**绘制时用的那个函数**（`rail_visible_indices()`），
	# 不是在这里另写一份采样数学 —— 否则测的是测试自己，跟真机没关系。
	var empty_dirs := 0
	var tightest := 999999
	var probes := 0
	for ri in range(4):
		for pi in range(5):
			for yi in range(8):
				var eul := Vector3(
					deg_to_rad(-80.0 + float(pi) * 40.0),
					deg_to_rad(float(yi) * 45.0),
					deg_to_rad(float(ri) * 90.0))
				var fwd := -Basis.from_euler(eul).z
				var n := FlightHUD.rail_visible_indices(fwd, 68.0, 16.0 / 9.0).size()
				probes += 1
				if n == 0:
					empty_dirs += 1
				tightest = mini(tightest, n)
	t.eq(probes, 160, "扫了 %d 个朝向（滚转 4 × 俯仰 5 × 偏航 8）" % probes)
	t.eq(empty_dirs, 0,
		"**没有一个**朝向是空的 —— 这就是「机体转体一下导轨就消失」的反证")
	t.gt(tightest, 4,
		"最空的朝向也还剩 %d 条刻度（视野锥剔除是保守的：宁多画、不漏画）" % tightest)

	# ---- 剔除真的在起作用 ----
	# 不做这一层的话，每帧要把 1236 条全部送去 `unproject_position`，纯浪费。
	var vis0 := FlightHUD.rail_visible_indices(Vector3(0.0, 0.0, -1.0), 68.0, 16.0 / 9.0).size()
	t.lt(vis0, list.size() / 2,
		"正前方只留 %d / %d 条 —— 砍掉大半，不是把整颗球都送去投影" % [vis0, list.size()])
	t.gt(vis0, 20, "……但留下的量足够铺出刻度（%d 条）" % vis0)
	t.lt(FlightHUD.rail_cos_limit(68.0, 16.0 / 9.0), 1.0,
		"视野锥阈值 < 1（等于 1 就只剩正前方那一条，退化成平面导轨了）")

	# ---- 两档刻度 ----
	t.gt(FlightHUD.RAIL_TICK_MAJOR_DEG, FlightHUD.RAIL_TICK_MINOR_DEG,
		"主刻度比次刻度长（%.1f° > %.1f°）"
			% [FlightHUD.RAIL_TICK_MAJOR_DEG, FlightHUD.RAIL_TICK_MINOR_DEG])
	t.gt(majors, 0, "有主刻度（%d 条）" % majors)
	t.lt(majors, list.size(),
		"也有次刻度（%d 条）—— 只有一种长度就没有节奏、读不出方位了" % (list.size() - majors))
	# ⚠️ 轮 22 第一版这里断言的是自造的 `RAIL` / `RAIL_W_*` / `RAIL_OUTLINE`
	# —— 那 4 个颜色常量被 `suite_ui_style` 判 FAIL（UI 脚本的颜色常量只许那 9 个），
	# 线宽也超出了「只有两档」的铁律。现在改成断言**取色通道**与**分层不变式**。
	var w_white := FlightHUD.deco_white(1.0)
	t.near(w_white.r, FlightHUD.NEUTRAL.r, 0.001, "装饰层的白取自工程的白 NEUTRAL")
	t.near(w_white.g, FlightHUD.NEUTRAL.g, 0.001, "……G 分量同源")
	t.near(w_white.b, FlightHUD.NEUTRAL.b, 0.001, "……B 分量同源")
	t.gt(w_white.r, 0.9,
		"而且它确实是白的（R 分量 %.2f）—— 轮 22 用户实测：原来那套青绿「有点看不到」"
			% w_white.r)
	t.near(FlightHUD.deco_white(0.25).a, 0.25, 0.001,
		"`deco_white(a)` 只改 alpha、不碰色相（四档分层不会变成四种白）")
	t.near(FlightHUD.deco_white(0.25).r, w_white.r, 0.001, "……降透明度那档与本体同色")
	t.gt(FlightHUD.RAIL_A_HORIZON, 0.7,
		"地平线圈 alpha %.2f —— 够亮（原来 0.34，座舱里几乎看不见）"
			% FlightHUD.RAIL_A_HORIZON)
	t.gt(FlightHUD.RAIL_A_HORIZON, FlightHUD.RAIL_A_MAJOR, "地平线圈比主刻度亮")
	t.gt(FlightHUD.RAIL_A_MAJOR, FlightHUD.RAIL_A_MINOR, "主刻度比次刻度亮")
	t.gt(FlightHUD.RAIL_A_MINOR, FlightHUD.RAIL_A_ARC,
		"次刻度比背景轨线亮（轨线是网格、刻度是节拍 —— 反过来就成了噪声）")
	# ⚠️ 线宽**只有两档可用**（工程铁律），所以分层只能靠 alpha 拉开：
	t.gt(FlightHUD.RAIL_A_HORIZON - FlightHUD.RAIL_A_MINOR, 0.3,
		"最亮档与最暗档的 alpha 拉开 %.2f（%.2f − %.2f）—— 线宽只剩两档，\n\t\t分层全压在 alpha 上，挤在一起就读不出层级了"
			% [FlightHUD.RAIL_A_HORIZON - FlightHUD.RAIL_A_MINOR,
				FlightHUD.RAIL_A_HORIZON, FlightHUD.RAIL_A_MINOR])
	t.gt(FlightHUD.RAIL_A_BACKDROP, 0.2,
		"刻度 / 轨线都垫了一道暗边（alpha %.2f）—— 白线压在亮天空、亮沙漠上才不会糊掉"
			% FlightHUD.RAIL_A_BACKDROP)

	# ---- 轨线（轮 22）：**刻度与轨线是两样东西，缺一不可** ----
	# 第一版只画了刻度，真机截图里整片天球就是"散落的小短杠"，读不出网格。
	var arcs := FlightHUD.rail_arcs()
	var n_mer_arc := 0
	var n_par_arc := 0
	var arc_horizon := 0
	var arc_worst := 0.0
	for d in arcs:
		var dd: Dictionary = d
		if bool(dd["meridian"]):
			n_mer_arc += 1
		else:
			n_par_arc += 1
			if bool(dd["horizon"]):
				arc_horizon += 1
		arc_worst = maxf(arc_worst, rad_to_deg((dd["a"] as Vector3).angle_to(dd["b"] as Vector3)))
	t.eq(n_mer_arc, 12 * 36, "经线轨线 %d 段（12 条 × 36 段）" % n_mer_arc)
	t.eq(n_par_arc, 11 * 72, "纬线轨线 %d 段（11 圈 × 72 段）" % n_par_arc)
	t.eq(arcs.size(), 1224, "轨线合计 %d 段" % arcs.size())
	t.near(arc_worst, FlightHUD.RAIL_ARC_DEG, 0.001,
		"每段正好 %.1f°（切段大小 = RAIL_ARC_DEG，逐段剔除才成立）"
			% FlightHUD.RAIL_ARC_DEG)
	t.eq(arc_horizon, 72,
		"地平线圈也在轨线表里（%d 段）—— 它是唯一单独提亮的一整圈" % arc_horizon)
	t.ok(is_same(FlightHUD.rail_arcs(), FlightHUD.rail_arcs()),
		"`rail_arcs()` 也走缓存（1224 段不该每帧重算）")

	# 轨线与刻度共用同一套剔除：**任何朝向都不许空**
	var empty_arc := 0
	var arc_min := 999999
	for az_i in range(8):
		for el_i in range(-2, 3):
			var fwd_arc := FlightHUD.rail_dir(float(az_i) * 45.0, float(el_i) * 30.0)
			var n_arc := FlightHUD.rail_visible_of(arcs, fwd_arc, 68.0, 16.0 / 9.0).size()
			arc_min = mini(arc_min, n_arc)
			if n_arc == 0:
				empty_arc += 1
	t.eq(empty_arc, 0,
		"轨线也是「任何朝向都不空」× 40 个朝向 —— 这是用户那句「转体一下就消失」的正解")
	t.gt(arc_min, 8, "最空的朝向也还有 %d 段轨线" % arc_min)

	# ---- 刻度线的**朝向**：垂直于它所在的那条轨 ----
	# 经线上的刻度横着长（沿方位方向）、纬线上的竖着长（沿仰角方向）；
	# 两个切向必须互相垂直，横竖轨的交叉处才是"小十字"而不是"两条斜线"。
	var t_az := FlightHUD.rail_tick_tangent(37.0, 23.0, true)
	var t_el := FlightHUD.rail_tick_tangent(37.0, 23.0, false)
	t.near(t_az.dot(t_el), 0.0, 0.0001, "方位切向 ⊥ 仰角切向（两级刻度交叉成直角）")
	t.near(t_az.length(), 1.0, 0.0001, "方位切向是单位向量")
	t.near(t_el.length(), 1.0, 0.0001, "仰角切向是单位向量")
	t.near(t_az.y, 0.0, 0.0001,
		"经线上的刻度是**横**的（落在水平面内）—— 用户说的「横轨的刻度线」")
	t.near(t_el.y, cos(deg_to_rad(23.0)), 0.0001,
		"纬线上的刻度是**竖**的（沿仰角方向）—— 用户说的「竖轨的刻度线」")

	# ---- 刻度的**几何**：两个端点真的差了一个"刻度长度" ----
	var one: Dictionary = list[0]
	var one_ang := rad_to_deg((one["a"] as Vector3).angle_to(one["b"] as Vector3))
	var want_len: float = FlightHUD.RAIL_TICK_MAJOR_DEG
	if not bool(one["major"]):
		want_len = FlightHUD.RAIL_TICK_MINOR_DEG
	t.near(one_ang, want_len, 0.05,
		"一条刻度的两端夹角 = 它该有的长度（%.2f°，期望 %.2f°）" % [one_ang, want_len])
	t.near((one["a"] as Vector3).length(), 1.0, 0.0001,
		"端点是**单位方向**而不是位置 —— 球半径归 RAIL_R 管，两者彻底解耦")

	# ---- 缓存：刻度表是常量，不该每帧重算 ----
	t.ok(is_same(FlightHUD.rail_dirs(), FlightHUD.rail_dirs()),
		"`rail_dirs()` 走缓存（第二次数到的是同一份，不重算 1236 条）")


## 在整颗球上均匀撒 `n` 个点（斐波那契球），返回"离最近刻度最远的那个点"的角距（度）。
##
## ⚠️ 采样而不是解析：解析要预设"最坏点一定落在网格正中间"，而那正是本函数想验证的东西。
static func _worst_gap_deg(centers: Array, n: int) -> float:
	var worst := 0.0
	var ga := PI * (1.0 + sqrt(5.0))
	for i in range(n):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / float(n)
		var rr := sqrt(maxf(1.0 - y * y, 0.0))
		var th := ga * float(i)
		var dir := Vector3(cos(th) * rr, y, sin(th) * rr)
		var best := -2.0
		for c: Vector3 in centers:
			var dp := dir.dot(c)
			if dp > best:
				best = dp
		worst = maxf(worst, rad_to_deg(acos(clampf(best, -1.0, 1.0))))
	return worst


# ============================================================ ⑦ 座舱仪表台（轮 21）

## 需求原文：「第一人称模式最下方屏幕仪表盘素材」（附一张机战座舱参考图）
## + 追问里的两点：显示内容 **「123」**（推力条 / 姿态条 / 纯饰条三样都要）、
## 铺法 **「雷达补充到这里面」**（雷达是这块仪表台的中央主屏）。
##
## 这一节钉的是**版式**（纯函数 `FlightHUD.dash_layout()`）—— 屏幕底部左右两角
## 已经被血条与弹药栏占死，"台子会不会压到它们"必须是一条算式，
## 不能靠"在某个窗口下跑一眼看着没压"。
static func _dash(t: T) -> void:
	t.suite("FPV / 座舱仪表台：三块独立模块 / 圆表 / 不压血条 / 雷达居中")
	var v := Vector2(1600, 900)
	var lay := FlightHUD.dash_layout(v)
	var rect: Rect2 = lay["rect"]
	var center: Rect2 = lay["center"]
	var left: Rect2 = lay["left"]
	var right: Rect2 = lay["right"]

	# ---- 台底贴屏底、不越界 ----
	t.near(rect.end.y, v.y - FlightHUD.DASH_BOTTOM_PAD, 0.01,
		"台**底边**落在距屏底 %.0f px 处" % FlightHUD.DASH_BOTTOM_PAD)
	t.near(rect.size.y, FlightHUD.DASH_H, 0.01, "中央格高 = DASH_H")
	t.gt(rect.position.y, 0.0, "台顶没有跑出屏幕上沿")

	# ---- 版式（格子）仍然严丝合缝：留缝是**模块**的事，版式一个字不动 ----
	t.near(left.end.x, center.position.x, 0.01, "版式上左格右端 = 中央格左端")
	t.near(center.end.x, right.position.x, 0.01, "版式上中央格右端 = 右格左端")
	t.near(left.position.y, rect.position.y, 0.01, "三格同一条顶边")
	t.near(left.position.x, rect.position.x, 0.01, "左格贴着台左缘")
	t.near(right.end.x, rect.end.x, 0.01, "右格贴着台右缘")

	# ---- 轮 22：三块**独立模块**（参考图的头号特征）----
	var mods := FlightHUD.dash_modules(lay)
	var mc: Rect2 = mods["center"]
	var ml: Rect2 = mods["left"]
	var mr: Rect2 = mods["right"]
	t.gt(mc.position.x, center.position.x,
		"中央模块左端 %.0f 比中央格 %.0f 靠里 —— 这就是模块之间那条缝"
			% [mc.position.x, center.position.x])
	t.near(mc.end.y, rect.end.y, 0.01, "中央模块的底边仍然贴着台底")
	t.near(ml.end.y, mc.end.y, 0.01, "左模块与中央模块**底边齐**（参考图三块底边对齐）")
	t.near(mr.end.y, mc.end.y, 0.01, "右模块同理")
	t.near(ml.size.y, FlightHUD.DASH_SIDE_H, 0.01, "侧模块高 = DASH_SIDE_H")
	t.gt(mc.size.y, ml.size.y,
		"中央模块 %.0f 比侧模块 %.0f 高 —— 参考图里中央那块明显更高"
			% [mc.size.y, ml.size.y])
	t.lt(ml.size.y, ml.size.x,
		"侧模块是**横长**的（%.0f 宽 × %.0f 高）—— 参考图侧屏是横置的框，不是方块"
			% [ml.size.x, ml.size.y])
	t.lt(ml.end.x, mc.position.x + 0.01, "左模块与中央模块**不重叠**（缝是真的留出来了）")
	t.gt(mr.position.x, mc.end.x - 0.01, "右模块同理")

	# ---- 雷达居中：这是「雷达补充到这里面」的字面兑现 ----
	var cy: float = FlightHUD.radar_center(v).y
	t.gt(cy - mc.position.y, FlightHUD.RADAR_RADIUS,
		"雷达圆上沿在**中央模块**内（上方留 %.0f px > 半径 %.0f）"
			% [cy - mc.position.y, FlightHUD.RADAR_RADIUS])
	t.gt(mc.end.y - cy, FlightHUD.RADAR_RADIUS,
		"雷达圆下沿也在模块内（下方留 %.0f px）" % (mc.end.y - cy))

	# ---- 中央模块的内壁 ----
	var cl := FlightHUD.dash_center_layout(mc)
	var c_inner: Rect2 = cl["inner"]
	t.gt(c_inner.size.x, FlightHUD.RADAR_RADIUS * 2.0,
		"内容区宽 %.0f 装得下雷达直径 %.0f"
			% [c_inner.size.x, FlightHUD.RADAR_RADIUS * 2.0])
	var side_room := (c_inner.size.x - FlightHUD.RADAR_RADIUS * 2.0) * 0.5
	t.gt(side_room, 22.0,
		"雷达两侧各留 %.0f px —— 参考图里雷达两侧是有装饰位置的（盾形的肩、竖排六边形）；\n		上一版这里只剩 9 px，什么都放不下" % side_room)
	t.lt(side_room, FlightHUD.RADAR_RADIUS * 0.4,
		"……但两侧余量加起来（%.0f px）还不如一个半径 —— 雷达仍是这块屏的主体"
			% (side_room * 2.0))
	t.near(c_inner.position.x + c_inner.size.x * 0.5, v.x * 0.5, 0.01,
		"内容区水平居中于屏幕中心（雷达才可能居中）")
	# 机体名（轮 22 搬到雷达圆**上方**）：基线与字形都要落在内容区里
	var name_base := cy - FlightHUD.RADAR_RADIUS - 8.0
	t.gt(name_base - 9.0, c_inner.position.y,
		"机体名字形上沿（基线 − 9）在内容区内，距内沿上 %.0f px"
			% (name_base - 9.0 - c_inner.position.y))
	t.lt(name_base, cy - FlightHUD.RADAR_RADIUS,
		"……且与雷达圆留了 %.0f px，没压到圆上"
			% (cy - FlightHUD.RADAR_RADIUS - name_base))
	t.gt(mc.end.y - c_inner.end.y, FlightHUD.DASH_BEZEL - 0.01,
		"内容区底边之下有 %.0f px 的框带（刻度饰条画在这里，不是画在内容区里）"
			% (mc.end.y - c_inner.end.y))
	t.near(mc.end.y - FlightHUD.DASH_BEZEL + 1.0 + FlightHUD.DASH_TICK_LONG, mc.end.y, 0.01,
		"刻度饰条最长的那一条刚好收到模块底边（不会画到屏幕外）")

	# ---- 形状（轮 24）：圆角 / 盾形 / 三角卡箍 / 四角角标 ----
	# 参考图那块放大 2× 看得很清楚：四个角是**圆**的，不是切角。
	var rrp := FlightHUD.round_rect_pts(Rect2(0, 0, 200, 120), FlightHUD.DASH_CORNER_R)
	t.eq(rrp.size(), 4 * (FlightHUD.DASH_CORNER_SEG + 1),
		"圆角矩形 %d 个点（4 个角 × 每个 %d 段）"
			% [rrp.size(), FlightHUD.DASH_CORNER_SEG])
	var rrp_bad := 0
	var rrp_min_x := 9999.0
	var rrp_max_x := -9999.0
	for p in rrp:
		var q: Vector2 = p
		if q.x < -0.01 or q.x > 200.01 or q.y < -0.01 or q.y > 120.01:
			rrp_bad += 1
		rrp_min_x = minf(rrp_min_x, q.x)
		rrp_max_x = maxf(rrp_max_x, q.x)
	t.eq(rrp_bad, 0,
		"……每一个点都落在矩形里（圆角写歪会画出自交的「蝴蝶结」，而那种错肉眼看不出来）")
	t.near(rrp_min_x, 0.0, 0.01, "最左的点仍在外沿上（圆角是往里收，不是把矩形整体缩小）")
	t.near(rrp_max_x, 200.0, 0.01, "最右的点也仍在外沿上")
	var rrp_clamp_x := 0.0
	for p in FlightHUD.round_rect_pts(Rect2(0, 0, 10, 10), 50.0):
		rrp_clamp_x = maxf(rrp_clamp_x, (p as Vector2).x)
	t.lt(rrp_clamp_x, 10.01, "半径超过半边长时被夹住（不会跑到矩形外面去）")

	var st := FlightHUD.round_rect_step_pts(Rect2(0, 0, 200, 120),
		FlightHUD.DASH_CORNER_R, FlightHUD.DASH_STEP, FlightHUD.DASH_STEP_FRAC)
	t.eq(st.size(), 4 * (FlightHUD.DASH_CORNER_SEG + 1) + 4,
		"带台阶的圆角矩形 %d 个点（四个圆角 + 顶边那四个折点）" % st.size())
	var st_top := 9999.0
	for p in st:
		st_top = minf(st_top, (p as Vector2).y)
	t.near(st_top, -FlightHUD.DASH_STEP, 0.01,
		"台阶把顶边中段抬高 DASH_STEP（往 *上* 凸 ⇒ 不会顶出屏幕：台底距屏底只有 12 px）")

	# ---- 罩框（∩ 形）：**每一段都必须落在雷达圆外面** ----
	# ⚠️ 这里原本是「盾形」。真机截图直接否掉：盾的斜边从肩收到窄底，
	# 而雷达圆盘就在中间 —— 斜边穿进圆里只被那层半透明底色压暗一点，
	# 看起来是**两道划过雷达的划痕**，不是轮廓。改判据：罩框的每一段都在圆外。
	var cp := FlightHUD.canopy_pts(Rect2(0, 0, 200, 160),
		FlightHUD.DASH_CANOPY_TOP_W, FlightHUD.DASH_CANOPY_CHAM)
	t.eq(cp.size(), 6, "罩框是 6 个点（左下端 / 左上斜角 / 顶边两点 / 右上斜角 / 右下端）")
	var cp_ok := true
	for p in cp:
		var q: Vector2 = p
		if q.x < -0.01 or q.x > 200.01 or q.y < -0.01 or q.y > 160.01:
			cp_ok = false
	t.ok(cp_ok, "……六个点全在给定矩形里")
	var cp_sym := true
	for p in cp:
		var q: Vector2 = p
		var hit := false
		for p2 in cp:
			var q2: Vector2 = p2
			if absf((100.0 - q.x) - (q2.x - 100.0)) < 0.01 and absf(q.y - q2.y) < 0.01:
				hit = true
				break
		if not hit:
			cp_sym = false
	t.ok(cp_sym, "……左右镜像对称（参考图那块罩框是左右对称的）")
	var cp_top_w := (cp[3] as Vector2).x - (cp[2] as Vector2).x
	t.lt(cp_top_w, 200.0, "顶边 %.0f 比全宽 200 窄 —— 上方两个斜角才存在" % cp_top_w)
	t.gt(cp_top_w, 0.0, "……而且是正宽度（不是收成一条线）")
	t.near((cp[2] as Vector2).y, 0.0, 0.01, "顶边在矩形最上沿")
	t.near((cp[0] as Vector2).y, 160.0, 0.01, "两条侧边一直落到矩形最下沿（罩框**不封底**）")
	t.near((cp[1] as Vector2).y, FlightHUD.DASH_CANOPY_CHAM, 0.01,
		"左上斜角在 y 上占 DASH_CANOPY_CHAM")
	t.near((cp[0] as Vector2).x, 0.0, 0.01, "侧边贴着矩形左右沿")

	# ---- 这条是本轮最要紧的一条：罩框与雷达圆的关系 ----
	var c_art: Rect2 = cl["art"]
	var c_radar := FlightHUD.radar_center(v)
	var c_pts := FlightHUD.canopy_pts(c_art, FlightHUD.DASH_CANOPY_TOP_W,
		FlightHUD.DASH_CANOPY_CHAM)
	var c_min := 99999.0
	for i in range(c_pts.size() - 1):
		var aa: Vector2 = c_pts[i]
		var ab2 := (c_pts[i + 1] as Vector2) - aa
		var tt2 := clampf((c_radar - aa).dot(ab2)
			/ maxf(ab2.length_squared(), 0.0001), 0.0, 1.0)
		c_min = minf(c_min, (aa + ab2 * tt2).distance_to(c_radar))
	t.gt(c_min, FlightHUD.RADAR_RADIUS,
		"罩框的每一段都在雷达圆**外**（最近 %.1f px > 半径 %.0f）——\n"
			% [c_min, FlightHUD.RADAR_RADIUS]
		+ "上一版盾形就是死在这一条上：斜边穿进圆里，看起来是两道划痕")

	# ---- 三角卡箍 / 四角角标 ----
	var tri3 := FlightHUD.tri_pts(Vector2.ZERO, 10.0, 0.0)
	t.eq(tri3.size(), 3, "卡箍是三角形（3 个点）")
	var tri_r := 0.0
	for p in tri3:
		tri_r = maxf(tri_r, (p as Vector2).length())
	t.near(tri_r, 10.0, 0.01, "……三个顶点都在外接圆上（实测 %.2f）" % tri_r)
	t.near((tri3[0] as Vector2).y, -10.0, 0.01,
		"0° 的顶点朝正上方（与 dash_dial_tip 同一套角度语义）")

	var br := FlightHUD.bracket_pts(Rect2(0, 0, 200, 120), 0, 12.0, 2.0)
	t.eq(br.size(), 3, "角标是 3 个点（一条边上的端点 → 角点 → 另一条边上的端点）")
	t.near((br[1] as Vector2).x, 2.0, 0.01, "corner 0 的角点落在**左上**（离外沿 2 px）")
	t.near((br[1] as Vector2).y, 2.0, 0.01, "……x 与 y 都是内缩后的值")
	t.near((br[2] as Vector2).x, 14.0, 0.01, "……第三点沿顶边往里 12 px（臂长）")
	t.near((br[0] as Vector2).y, 14.0, 0.01, "……第一点沿左边往下 12 px")
	var br3 := FlightHUD.bracket_pts(Rect2(0, 0, 200, 120), 3, 12.0, 2.0)
	t.near((br3[1] as Vector2).x, 2.0, 0.01, "corner 3 的角点落在**左下**")
	t.near((br3[1] as Vector2).y, 118.0, 0.01, "……y = 高 − 2")
	var br_clamp_max := 0.0
	for p in FlightHUD.bracket_pts(Rect2(0, 0, 20, 20), 0, 500.0, 1.0):
		br_clamp_max = maxf(br_clamp_max, maxf((p as Vector2).x, (p as Vector2).y))
	t.lt(br_clamp_max, 20.01, "臂长超过矩形时被夹住（不会画到矩形外面）")

	var hex6 := FlightHUD.hex_pts(Vector2.ZERO, 5.0)
	t.eq(hex6.size(), 6, "铆钉是正**六**边形")
	var hex_r := 0.0
	for p in hex6:
		hex_r = maxf(hex_r, (p as Vector2).length())
	t.near(hex_r, 5.0, 0.01, "六个顶点都在外接圆上（实测半径 %.2f）" % hex_r)

	# ---- 圆表：半径不越格 / 指针几何 / 量程 ----
	var sl := FlightHUD.dash_side_layout(ml)
	var dr: float = sl["dial_radius"]
	var dc: Vector2 = sl["dial_center"]
	var s_inner: Rect2 = sl["inner"]
	t.gt(dr, 20.0, "侧格圆表半径 %.1f px —— 够大才看得出是一块指针表" % dr)
	t.gt(dc.x - dr, s_inner.position.x - 0.01, "圆表左边不越出内容区")
	t.lt(dc.x + dr, s_inner.end.x + 0.01, "圆表右边不越出内容区")
	t.gt(dc.y - dr, s_inner.position.y - 0.01, "圆表上边不越出内容区")
	t.lt(dc.y + dr, s_inner.end.y + 0.01, "圆表下边不越出内容区")
	var bar: Rect2 = sl["bar"]
	t.lt(bar.end.y, mc.end.y + 0.01, "侧格底部那条点阵也在模块内")
	t.gt(float(sl["mode_y"]), dc.y + dr - 0.01, "档位文字的基线在圆表下方（不会压在圆上）")

	t.near(FlightHUD.dash_dial_angle(0.0), -FlightHUD.DASH_DIAL_SWEEP, 0.01,
		"读数 0 ⇒ 指针指到 −SWEEP")
	t.near(FlightHUD.dash_dial_angle(1.0), FlightHUD.DASH_DIAL_SWEEP, 0.01,
		"读数满 ⇒ +SWEEP")
	t.near(FlightHUD.dash_dial_angle(0.5), 0.0, 0.01, "读数一半 ⇒ 正上方")
	t.near(FlightHUD.dash_dial_angle(2.0), FlightHUD.DASH_DIAL_SWEEP, 0.01,
		"读数越界被夹住（不会绕过一圈）")
	var tip_up := FlightHUD.dash_dial_tip(Vector2.ZERO, 10.0, 0.0)
	t.near(tip_up.y, -10.0, 0.01, "0° 的针尖在正上方（屏幕 y 向下 ⇒ 负）")
	t.near(tip_up.x, 0.0, 0.01, "……x 不动")
	var tip_r := FlightHUD.dash_dial_tip(Vector2.ZERO, 10.0, 90.0)
	t.near(tip_r.x, 10.0, 0.01, "90° 的针尖在正右（顺时针为正）")
	t.eq(FlightHUD.dash_thrust_ticks().size(), 19, "推力表 ±135° 每 15° 一条 ⇒ 19 条")
	t.eq(FlightHUD.dash_roll_ticks().size(), 9, "滚转表 ±60° 每 15° 一条 ⇒ 9 条")

	# ---- 窄窗口：台自己收窄，绝不去压左下血条 / 右下弹药 ----
	var v1280 := Vector2(1280, 720)
	var r1280: Rect2 = FlightHUD.dash_layout(v1280)["rect"]
	t.gt(r1280.position.x, v1280.x * 0.5 - FlightHUD.DASH_EDGE_CLEAR - 0.01,
		"1280 宽下台左端 %.0f 仍落在空档里（中心往左 %.0f 是血条的地盘）"
			% [r1280.position.x, FlightHUD.DASH_EDGE_CLEAR])
	t.lt(r1280.size.x, FlightHUD.DASH_HALF_W * 2.0,
		"……代价是台自动收窄到 %.0f px（窗口够宽时是 %.0f）"
			% [r1280.size.x, FlightHUD.DASH_HALF_W * 2.0])
	var m1280 := FlightHUD.dash_modules(FlightHUD.dash_layout(v1280))
	var ml1280: Rect2 = m1280["left"]
	var mc1280: Rect2 = m1280["center"]
	t.gt(ml1280.size.x, 0.0, "……左模块仍有正宽度（%.0f px），没有变成负数" % ml1280.size.x)
	t.near(ml1280.end.y, mc1280.end.y, 0.01, "……窄窗口下三块仍然底边齐")
	t.lt(ml1280.end.x, mc1280.position.x + 0.01, "……缝也还在")

	# ---- 极窄窗口：侧格可以被压没，中央格（雷达）必须保得住 ----
	var tiny := FlightHUD.dash_modules(FlightHUD.dash_layout(Vector2(1024, 600)))
	var t_l: Rect2 = tiny["left"]
	var t_c: Rect2 = tiny["center"]
	t.ok(t_l.size.x >= 0.0, "极窄窗口下侧模块宽度不为负（%.0f px）" % t_l.size.x)
	t.lt(t_l.size.x, 40.0,
		"……窄到 %.0f px 时绘制会跳过侧格（`_draw_dash_*` 开头的守卫）" % t_l.size.x)
	t.gt(t_c.size.x, 0.0, "中央格（雷达那一格）在任何窗口下都保得住（%.0f px）" % t_c.size.x)
	t.eq(FlightHUD.dash_side_layout(t_l)["dial_radius"], 0.0,
		"……连圆表半径都被算成 0（半径是**由格子算出来**的，不是写死的）")

	# ---- 台永远比屏幕窄（否则就是"横贯整条"，会盖住两角）----
	for w: float in [1024.0, 1280.0, 1600.0, 1920.0, 2560.0]:
		var rr: Rect2 = FlightHUD.dash_layout(Vector2(w, 900.0))["rect"]
		t.lt(rr.size.x, w, "窗口宽 %.0f 时台宽 %.0f —— 始终窄于屏幕" % [w, rr.size.x])

	# ---- 接线（源码扫描）----
	var hud_src := SuiteUiStyle._code(HUD_SRC)
	for fn: String in ["func _draw_cockpit_dash", "func dash_layout", "func dash_modules",
			"func round_rect_pts", "func round_rect_step_pts", "func canopy_pts",
			"func hex_pts", "func tri_pts", "func bracket_pts",
			"func dash_center_layout", "func dash_side_layout", "func dash_dial_tip",
			"func dash_dial_angle", "func dash_thrust_ticks", "func dash_roll_ticks",
			"func _draw_dash_module", "func _draw_dash_center_art", "func _draw_dash_hexes",
			"func _draw_dash_ticks", "func _draw_dash_gauge", "func _draw_dash_pips",
			"func _draw_dash_side_deco", "func _draw_dash_thrust", "func _draw_dash_attitude"]:
		t.ok(hud_src.contains(fn), "hud.gd 里有 `%s`" % fn)

	var body := _func_body(hud_src, "func _draw_cockpit_dash")
	t.ok(body.contains("not Settings.first_person"),
		"仪表台第一件事也是查设置（默认关 ⇒ 既有截图与像素测试逐位不变）")
	t.ok(body.find("not Settings.first_person") < body.find("_draw_dash_module"),
		"……查在画之前（提前 return，不是画完再判）")
	t.ok(body.contains("_draw_dash_module(mc, true)"),
		"中央那块走**带台阶**的模块（参考图中央屏顶边那一级）")
	t.ok(body.contains("_draw_dash_module(ml, false)")
			and body.contains("_draw_dash_module(mr, false)"),
		"左右两块走普通倒角模块")
	t.ok(body.contains("_draw_dash_thrust") and body.contains("_draw_dash_attitude"),
		"推力表 + 姿态表都接了线（用户答「123」里的 1 与 2）")
	t.ok(body.contains("_draw_dash_ticks") and body.contains("_draw_dash_center_art"),
		"刻度饰条 + 中央内壁装饰也接了线（用户答「123」里的 3 —— 纯座舱饰条）")

	var mod := _func_body(hud_src, "func _draw_dash_module")
	t.ok(mod.contains("DASH_BEZEL") and mod.contains("round_rect_pts")
			and mod.contains("round_rect_step_pts"),
		"模块是「先铺满框色、再挖内容区」画出来的 —— 框是**有厚度的一圈**，不是 1 px 的线")
	t.ok(not mod.contains("chamfer_pts"),
		"……四角走的是**圆角**（`round_rect_pts`），不是上一版那种切角")
	t.ok((mod.split("draw_colored_polygon") as Array).size() >= 3,
		"……铺完框色还要再挖一次内容区（两笔 fill，中间剩的那圈才是框）")

	var draw_body := _func_body(hud_src, "func _draw()")
	var i_dash := draw_body.find("_draw_cockpit_dash()")
	var i_radar := draw_body.find("_draw_radar()")
	var i_tag := draw_body.find("_draw_model_tag()")
	t.ok(i_dash >= 0, "`_draw()` 里真的调用了它（只定义不接线 = 画不出来）")
	t.ok(i_radar > i_dash,
		"台面画在雷达**之前** —— 雷达压在台面上，这才叫「雷达补充到这里面」")
	t.ok(i_tag > i_dash, "机体名也排在台面之后（否则会被台面盖住）")

	var thr := _func_body(hud_src, "func _draw_dash_thrust")
	t.ok(thr.contains("fm.super_boost") and thr.contains("fm.boosting"),
		"档位判据与 `_draw_speed_block()` 同源（不会一处写 BOOST、另一处还写 CRUISE）")
	t.ok(thr.contains("dash_thrust_ticks") and thr.contains("dash_dial_angle"),
		"推力表走纯函数的刻度表与指针角度（几何不在绘制里现算）")
	var att := _func_body(hud_src, "func _draw_dash_attitude")
	t.ok(att.contains("dash_roll_ticks") and att.contains("attitude_readout"),
		"滚转表走纯函数刻度表；滚转角取 `attitude_readout()`，**不另算一份**"
			+ "（asin / 欧拉角那条取舍只该有一个真源）")

	# ---- 轮 24：新装饰件真的接了线（对着参考图逐件抄的那几样）----
	var cart := _func_body(hud_src, "func _draw_dash_center_art")
	t.ok(cart.contains("canopy_pts"),
		"中央屏主轮廓走 `canopy_pts()` —— ∩ 形罩框，每一段都在雷达圆外")
	t.ok(cart.contains("DASH_CANOPY_LINE"),
		"……而且画了内外**两条**（参考图那条主轮廓是双线）")
	t.ok(cart.contains("DASH_FOOT_DX"),
		"圆盘下方还有两个小卡角（参考图中央屏底部那两颗）")
	t.ok(cart.contains("DASH_SPINE_HALF"), "中央屏有一根中轴**竖脊**")
	t.ok(cart.contains("DASH_HEX_BAND_N"), "底边那条链式六边形带也在里面")
	t.ok(cart.contains("tri_pts"), "顶上那个倒三角徽标走 `tri_pts()`")

	var chex := _func_body(hud_src, "func _draw_dash_hexes")
	t.ok(chex.contains("DASH_HEX_COL_N") and chex.contains("DASH_HEX_COL_DX"),
		"左右两条**竖排六边形**（参考图中央屏左右沿那一列）")

	var dside := _func_body(hud_src, "func _draw_dash_side_deco")
	t.ok(dside.contains("bracket_pts"), "侧屏四角有小 L 角标")
	t.ok(dside.contains("tri_pts") and dside.contains("DASH_CLAMP_DEG"),
		"……环上还压着三颗卡箍三角（参考图那三颗骑在环上的圆角三角）")
	t.ok(dside.contains("mirror"), "`mirror` 形参在 —— 参考图左右两块侧屏是**镜像件**")

	var gau := _func_body(hud_src, "func _draw_dash_gauge")
	t.eq(gau.count("draw_arc"), 5,
		"圆表是**五层同心弧**（轮 24 四层 + 轮 30 的第二道外弧）")
	t.ok(gau.contains("DASH_BAND_SEG"),
		"外沿那一圈是**填实的环带**（36 条径向短线）—— 参考图那块圆盘的边框"
			+ "是有厚度的金属环，不是一根细线")

	var dashb2 := _func_body(hud_src, "func _draw_cockpit_dash")
	t.ok(dashb2.contains("_draw_dash_side_deco(ml, false)")
			and dashb2.contains("_draw_dash_side_deco(mr, true)"),
		"左右两块各调一次侧屏装饰，**右边那个 mirror=true**（镜像件）")
	t.ok(not dashb2.contains("_draw_dash_hexes"),
		"竖排六边形不是从总入口调的 —— 它挂在 `_draw_dash_center_art` 里")

	# ---- 轮 30：结构件层（"想更粗"只能翻译成 alpha + 双线，不能翻译成线宽）----
	# 需求原文（轮 30）：「再对着原剧图片进行下一步优化」+ 同一张 `09_原剧座舱参考.png`。
	# 本轮补的是**厚度**：原剧的件有外线 + 内衬 + 端头切角，我们原来只有单根细线，
	# 于是两块侧屏在放大对照图里读作「一个细圆表浮在空框里」。
	var bp := FlightHUD.block_pts(Rect2(0, 0, 40, 20), 4.0)
	t.eq(bp.size(), 8, "带切角的矩形是 8 个点")
	var bp_corner := false
	for p in bp:
		var q: Vector2 = p
		if absf(q.x) < 0.01 and absf(q.y) < 0.01:
			bp_corner = true
	t.ok(not bp_corner,
		"……四个直角**一个都没留**（全是切角）—— 这正是「机加工件」与「贴纸」的区别")
	var bp_bad := 0
	for p in bp:
		var q2: Vector2 = p
		if q2.x < -0.01 or q2.x > 40.01 or q2.y < -0.01 or q2.y > 20.01:
			bp_bad += 1
	t.eq(bp_bad, 0, "……8 个点全在矩形里")
	t.near((bp[0] as Vector2).x, 4.0, 0.01, "……切角宽度就是 cut")
	var bp_clamp := 0.0
	for p in FlightHUD.block_pts(Rect2(0, 0, 10, 20), 50.0):
		bp_clamp = maxf(bp_clamp, maxf((p as Vector2).x, (p as Vector2).y))
	t.lt(bp_clamp, 20.01,
		"cut 超过半边长时被夹住 —— 不夹的话四个切角会交叉成一个菱形（肉眼看不出来的那种错）")

	var tp := FlightHUD.trap_pts(Rect2(0, 0, 40, 20), 6.0)
	t.eq(tp.size(), 4, "梯形是 4 个点")
	t.near((tp[1] as Vector2).x - (tp[0] as Vector2).x, 28.0, 0.01,
		"……上边比下边每侧窄 cut（40 − 2×6 = 28）—— 原剧那两块舱盖是上窄下宽的")
	t.near((tp[3] as Vector2).x - (tp[2] as Vector2).x, -40.0, 0.01, "……下边仍是全宽")
	t.lt((FlightHUD.trap_pts(Rect2(0, 0, 40, 20), 500.0)[0] as Vector2).x, 20.01,
		"cut 被夹在半个宽度以内（上边不会被收成负宽度 ⇒ 画出来不会自交）")

	# ---- 阶梯竖轨：每一级都必须落在**雷达圆外面**那条窄带里 ----
	var sp := FlightHUD.stair_pts(0.0, 0.0, FlightHUD.DASH_STAIR_N,
		FlightHUD.DASH_STAIR_W, FlightHUD.DASH_STAIR_H, FlightHUD.DASH_STAIR_STEP,
		FlightHUD.DASH_STAIR_GAP)
	t.eq(sp.size(), FlightHUD.DASH_STAIR_N,
		"一条阶梯竖轨有 %d 级（每级一条独立折线 —— 连成一条就退化成\"一根竖条\"）"
			% FlightHUD.DASH_STAIR_N)
	t.eq((sp[0] as PackedVector2Array).size(), 8, "……每级是一个带切角的短块（8 点）")
	# ⚠️ 错开是**双向**的：第 0 级中心在基准轴 +step/2、第 1 级在 −step/2。
	# 第一版这条断言写成了「第二级更靠外」，把交替读成了单向平移 —— 直接 FAIL。
	var sp_c0 := 0.0
	var sp_c1 := 0.0
	var sp_lo := 9999.0
	var sp_hi := -9999.0
	for p in sp[0]:
		sp_c0 += (p as Vector2).x
		sp_lo = minf(sp_lo, (p as Vector2).x)
		sp_hi = maxf(sp_hi, (p as Vector2).x)
	sp_c0 /= float((sp[0] as PackedVector2Array).size())
	for p in sp[1]:
		sp_c1 += (p as Vector2).x
		sp_lo = minf(sp_lo, (p as Vector2).x)
		sp_hi = maxf(sp_hi, (p as Vector2).x)
	sp_c1 /= float((sp[1] as PackedVector2Array).size())
	t.near(absf(sp_c1 - sp_c0), FlightHUD.DASH_STAIR_STEP, 0.01,
		"……相邻两级**交替错开** DASH_STAIR_STEP（两级中心相差 %.1f px）"
			% absf(sp_c1 - sp_c0)
		+ "\n\t\t—— 连成一条直边就退化成\"一根竖条\"，交替错开才是原剧那条齿条")
	t.near(sp_hi - sp_lo, FlightHUD.DASH_STAIR_W + FlightHUD.DASH_STAIR_STEP, 0.01,
		"……整条轨的横向总跨度 = 块宽 + 错位（%.1f px）" % (sp_hi - sp_lo))

	# ⚠️ 轮 30 第二版：级高 = 缝距时 4 级首尾相接，整条轨是一根 80 px 高的连续竖条 ——
	# 1× 下与一根直线无异。真机逐位 diff（轮 24 截图 vs 轮 30 截图）里，侧屏红得很实、
	# 中央屏只剩这几个**孤立红点**。所以「有缝」和「够宽」都要写成断言。
	var sp_b0 := -99999.0
	for p in sp[0]:
		sp_b0 = maxf(sp_b0, (p as Vector2).y)
	var sp_t1 := 99999.0
	for p in sp[1]:
		sp_t1 = minf(sp_t1, (p as Vector2).y)
	t.near(sp_t1 - sp_b0, FlightHUD.DASH_STAIR_GAP, 0.01,
		"……相邻两级之间留 DASH_STAIR_GAP 的缝（%.1f px）——"
			% (sp_t1 - sp_b0)
		+ "\n\t\t首尾相接时 4 级连成一根竖条，1× 下与一条直线无异")
	var sp_top := 99999.0
	var sp_bot := -99999.0
	for seg in sp:
		for p in seg:
			sp_top = minf(sp_top, (p as Vector2).y)
			sp_bot = maxf(sp_bot, (p as Vector2).y)
	t.near(sp_bot - sp_top, FlightHUD.DASH_STAIR_H * float(FlightHUD.DASH_STAIR_N)
		+ FlightHUD.DASH_STAIR_GAP * float(FlightHUD.DASH_STAIR_N - 1), 0.01,
		"……整条轨总高 = 级数×级高 + (级数−1)×缝（%.1f px）" % (sp_bot - sp_top))
	t.gt(FlightHUD.DASH_STAIR_W, 10.0,
		"……块宽 > 10 px（现在是 %.0f）—— 8 px 配最暗那档 alpha，1× 下只剩几个孤点"
			% FlightHUD.DASH_STAIR_W)
	var cbody := _func_body(hud_src, "func _draw_dash_center_art")
	t.ok(cbody.contains("stair_pts") and cbody.contains("DASH_STAIR_GAP")
			and cbody.contains("DASH_A_LINE_MID"),
		"……接线：中央屏用 DASH_STAIR_GAP 分节，并且用 DASH_A_LINE_MID（中灰）"
		+ "\n\t\t而不是最暗的 DASH_A_LINE_DIM —— 轨是结构件、不是底纹")

	var stair_y0 := c_art.end.y - FlightHUD.DASH_STAIR_DY \
		- (FlightHUD.DASH_STAIR_H * float(FlightHUD.DASH_STAIR_N) \
			+ FlightHUD.DASH_STAIR_GAP * float(FlightHUD.DASH_STAIR_N - 1))
	var stair_min := 99999.0
	var stair_out := 0
	for sg: float in [-1.0, 1.0]:
		for seg in FlightHUD.stair_pts(c_art.position.x + c_art.size.x * 0.5
				+ sg * FlightHUD.DASH_STAIR_DX, stair_y0, FlightHUD.DASH_STAIR_N,
				FlightHUD.DASH_STAIR_W, FlightHUD.DASH_STAIR_H,
				FlightHUD.DASH_STAIR_STEP, FlightHUD.DASH_STAIR_GAP):
			var pts2: PackedVector2Array = seg
			for i in range(pts2.size()):
				var aa: Vector2 = pts2[i]
				var bb: Vector2 = pts2[(i + 1) % pts2.size()]
				var ab2 := bb - aa
				var tt2 := clampf((c_radar - aa).dot(ab2)
					/ maxf(ab2.length_squared(), 0.0001), 0.0, 1.0)
				stair_min = minf(stair_min, (aa + ab2 * tt2).distance_to(c_radar))
				if aa.x < c_art.position.x - 0.01 or aa.x > c_art.end.x + 0.01 \
						or aa.y < c_art.position.y - 0.01 or aa.y > c_art.end.y + 0.01:
					stair_out += 1
	t.gt(stair_min, FlightHUD.RADAR_RADIUS,
		"阶梯竖轨的每一段都在雷达圆**外**（最近 %.1f px > 半径 %.0f）——"
			% [stair_min, FlightHUD.RADAR_RADIUS]
		+ "\n\t\t与罩框那条判据同源：压进圆里就只是一堆划过盘面的划痕，不是结构")
	t.eq(stair_out, 0, "……而且没有一根跑出中央屏的内容区")

	# ---- 结构柱：上下端必须**接住**两个角标，且不压到圆盘 ----
	var col_x := s_inner.end.x - FlightHUD.DASH_SIDE_COL_PAD - FlightHUD.DASH_SIDE_COL_W
	t.near(col_x + FlightHUD.DASH_SIDE_COL_W,
		s_inner.end.x - FlightHUD.DASH_SIDE_COL_PAD, 0.01,
		"结构柱贴着内容区右沿（只留 DASH_SIDE_COL_PAD）")
	t.gt(col_x - (dc.x + dr), 2.0,
		"……柱的左沿 %.1f 在圆盘右沿 %.1f **之外**（实测间距 %.1f px）——"
			% [col_x, dc.x + dr, col_x - (dc.x + dr)]
		+ "\n\t\t半径原来是 67，柱根本放不下；轮 30 把 dtop/dbot 各让 7 px 才腾出这条柱")
	var col_y0 := s_inner.position.y + FlightHUD.DASH_BRACKET_PAD + FlightHUD.DASH_BRACKET_ARM
	var col_y1 := s_inner.end.y - FlightHUD.DASH_BRACKET_PAD - FlightHUD.DASH_BRACKET_ARM
	t.near(col_y0, s_inner.position.y + FlightHUD.DASH_BRACKET_PAD
		+ FlightHUD.DASH_BRACKET_ARM, 0.01,
		"柱顶 = 右上角标的**下端**（角标 / 柱 / 舱盖读起来是一件事，不是三件各摆各的）")
	var trap_h := ((col_y1 - col_y0)
		- FlightHUD.DASH_SIDE_TRAP_GAP * float(FlightHUD.DASH_SIDE_TRAP_N - 1)) \
		/ float(FlightHUD.DASH_SIDE_TRAP_N)
	t.gt(trap_h, FlightHUD.DASH_SIDE_TRAP_H - 0.01,
		"……柱高够放 %d 块舱盖（单块 %.1f px ≥ %.0f）—— 两块时分到 44 高 × 30 宽，"
			% [FlightHUD.DASH_SIDE_TRAP_N, trap_h, FlightHUD.DASH_SIDE_TRAP_H]
		+ "\n\t\t4× 放大图里读成\"两根竖槽\"；三块得到 %.1f 高，长宽才接近"
			% trap_h)
	t.lt(trap_h, FlightHUD.DASH_SIDE_COL_W - 4.0 + 8.0,
		"……而且单块不是**细高条**（%.1f 高 vs %d 宽）"
			% [trap_h, int(FlightHUD.DASH_SIDE_COL_W) - 4])
	t.lt(col_y1, float(sl["mode_y"]) - 0.01,
		"……柱底也在档位文字上方（不会压住 CRUISE / R）")

	# ---- 底边那排人字纹：位置**从圆盘底沿算**，不是写死 y ----
	# ⚠️ 这里第一版是「排在圆盘下方」（hy = 底沿 + 2）—— 4× 放大图上它压到了
	# 左下角标的横臂（角标臂长 34 ⇒ 横臂在内容区底 −34）。现在改成"贴底沿、
	# 并横向让出游标刻度圈"，两条约束都写成断言。
	var hy := dc.y + dr - 3.0
	var hy_stop := s_inner.end.y - FlightHUD.DASH_BRACKET_PAD - FlightHUD.DASH_BRACKET_ARM
	t.lt(hy + FlightHUD.DASH_SIDE_HATCH_H, hy_stop,
		"人字纹整排停在**左下角标的横臂之上**（%.0f + %.0f < %.0f）"
			% [hy, FlightHUD.DASH_SIDE_HATCH_H, hy_stop])
	t.lt(hy + FlightHUD.DASH_SIDE_HATCH_H, float(sl["mode_y"]),
		"……也在档位文字的基线上方（%.0f + %.0f < %.0f）"
			% [hy, FlightHUD.DASH_SIDE_HATCH_H, float(sl["mode_y"])])
	var hx0 := s_inner.position.x + 2.0
	var hx1 := hx0 + FlightHUD.DASH_SIDE_HATCH_STEP * float(FlightHUD.DASH_SIDE_HATCH_N - 1) \
		+ FlightHUD.DASH_SIDE_HATCH_W
	var dy_h := hy + FlightHUD.DASH_SIDE_HATCH_H * 0.5 - dc.y
	var v_r := dr + FlightHUD.DASH_GAUGE_OUT
	var ring_dx := sqrt(maxf(v_r * v_r - dy_h * dy_h, 0.0))
	t.lt(hx1, dc.x - ring_dx + 0.01,
		"……整排横向落在**游标刻度圈之外**（右端 %.1f < 圈左端 %.1f）——"
			% [hx1, dc.x - ring_dx]
		+ "\n\t\t五条人字纹横向铺 50 px，铺到圈里就会与那圈齿叠成一团")

	# ---- 圆表盘面细刻度 ----
	var gau2 := _func_body(hud_src, "func _draw_dash_gauge")
	t.eq(gau2.count("draw_arc"), 5,
		"圆表是**五层**同心弧（外沿 / 第二外弧 / 环带内沿 / 中间环 / 轮毂环）——"
		+ "\n\t\t第二道外弧是轮 30 加的：盘的边圈要读成\"双线\"，与罩框 / 角标同一套语言")
	t.ok(gau2.contains("DASH_GAUGE_FINE") and gau2.contains("DASH_GAUGE_FINE_LEN"),
		"盘面环带内侧有一圈**密刻度** —— 只有 36 条填充线时放大图里读作\"一个环\"，"
		+ "读不出\"一块表盘\";\n\t\t原剧那块圆盘的表盘是密刻度的")
	t.ok(gau2.contains("DASH_GAUGE_OUT") and not gau2.contains("DASH_GAUGE_VERN"),
		"环外是**第二道弧**，不是一圈游标齿 —— 第一版那 60 根 5 px 短线在 4× 放大图里"
		+ "\n\t\t是一圈**毛刺**（像静电噪点），只有双线才读得出\"金属边圈\"")
	t.lt(FlightHUD.DASH_GAUGE_OUT, FlightHUD.DASH_BAND_W,
		"……第二道弧的间距（%.0f）比环带厚度（%.0f）小，两圈才读成一层边圈"
			% [FlightHUD.DASH_GAUGE_OUT, FlightHUD.DASH_BAND_W])
	t.gt(FlightHUD.DASH_BAND_W, 6.0,
		"环带本身是有厚度的（%.0f px）—— 5 px 在 1600×900 下只是一根细圈，"
			% FlightHUD.DASH_BAND_W
		+ "整块屏会读成\"圆规画的圆\"，而不是\"一圈金属环\"")
	t.gt(float(FlightHUD.DASH_GAUGE_FINE), float(FlightHUD.dash_roll_ticks().size()),
		"……细刻度比环上的主刻度密得多（%d 条 vs %d 条）"
			% [FlightHUD.DASH_GAUGE_FINE, FlightHUD.dash_roll_ticks().size()])

	# ---- 接线（这三个件的几何都不许在绘制里现算）----
	var cart2 := _func_body(hud_src, "func _draw_dash_center_art")
	t.ok(cart2.contains("stair_pts"),
		"中央屏左右沿走 `stair_pts()`（阶梯竖轨）")
	t.ok(not cart2.contains("art.end.y - 16.0"),
		"……轮 24 那两列横短划线**已经撤掉**，不是两份并存（放大图里那 8 道线读不出形状）")
	t.ok(thr.contains("DASH_SIDE_LABEL_INSET") and att.contains("DASH_SIDE_LABEL_INSET"),
		"两个读数标签都按 `DASH_SIDE_LABEL_INSET` 从内容区边沿内缩 ——"
		+ "\n\t\t角标臂长抬到 34 之后，左上角标的**竖臂**正好从「THRUST」的字母里穿过去"
		+ "（4× 放大图里一眼看到，纯逻辑断言抓不到这种\"线压字\"）")
	t.gt(float(sl["label_y"]) - 9.0, s_inner.position.y + FlightHUD.DASH_BRACKET_PAD,
		"……标签行的字形顶（基线 − 9）也在角标**横臂**（内容区 + %.0f）之下"
			% FlightHUD.DASH_BRACKET_PAD)

	# ⚠️ 层序：卡箍是"骑在环上"的紧固件，装饰必须在圆表**之后**画。
	# 第一版写反了，4× 放大图里卡箍被 60 条密齿埋掉，而断言全绿 ——
	# 因为当时**没有任何一条断言管层序**。
	t.ok(body.find("_draw_dash_thrust") < body.find("_draw_dash_side_deco")
			and body.find("_draw_dash_attitude") < body.find("_draw_dash_side_deco"),
		"侧屏装饰（含三颗卡箍）画在圆表**之后** —— 卡箍压在刻度之上才叫\"骑在环上\"")
	var dside2 := _func_body(hud_src, "func _draw_dash_side_deco")
	t.ok(dside2.contains("_draw_dash_side_column"), "侧屏接了那根结构柱")
	t.ok(dside2.contains("UILayout.LINE_STRUCT"),
		"……四角结构块的**外线**走 LINE_STRUCT —— 两档线宽之下，\"厚\"只能靠线宽档"
		+ " + 两层之间的间距给")
	t.ok(dside2.contains("DASH_SIDE_HATCH_N"), "……底边那排人字纹也接了线")
	t.ok(dside2.contains("DASH_SIDE_DECO_MIN_W")
			and _func_body(hud_src, "func _draw_dash_side_column").contains("DASH_SIDE_DECO_MIN_W"),
		"……**两端都**有窄窗口守卫 —— 1280×720 下侧格只剩 69 px 宽、圆表半径 14.5 px；"
		+ "\n\t\t一根 34 px 宽的结构柱会横跨圆表 —— 宁可整件不画，也不要画成一团")
	t.ok(hud_src.contains("func _draw_dash_side_column"),
		"hud.gd 里有 `_draw_dash_side_column`（只定义不接线 = 画不出来）")
	t.ok(hud_src.contains("func block_pts") and hud_src.contains("func trap_pts")
			and hud_src.contains("func stair_pts"),
		"三个新形状纯函数都在（几何不在绘制里现算 —— 可逐条断言）")

	var tag := _func_body(hud_src, "func _draw_model_tag")
	t.ok(tag.contains("Settings.first_person"),
		"机体名在第一人称下走另一套：搬到雷达圆**上方**（台底那条边让给饰条了）")
	t.ok(tag.contains("deco_white(DASH_A_TXT)"),
		"……而且换成台面白（原来那点淡绿在座舱里看不清）")


# ============================================================ ⑧ 接线（源码扫描）

## 注释里写了名字不算数 —— 一律扫**剥掉注释**之后的源码（`SuiteUiStyle._code`）。
static func _wiring(t: T) -> void:
	t.suite("FPV / 接线（源码扫描）")
	var menu_src := SuiteUiStyle._code(MENU_SRC)

	# ---- 设置页那一行 ----
	# ⚠️ 轮 25：这一行**已撤掉**（视角切换挪到 F1 / 长按手柄 Back）⇒ 断言反向。
	# 但门的部件一个都没删，所以紧跟着的 `_setting_step` 那一段**仍然**必须成立。
	# 撤掉的是**入口**（这也是门唯一的入口）⇒ 弹窗暂时不可达，不是被删。
	t.not_ok(menu_src.contains("{\"key\": \"first_person\""),
		"设置页行表里**没有**「第一人称视角」了（它的唯一入口没了）")
	var step := _func_body(menu_src, "func _setting_step")
	t.ok(step.contains("\"first_person\":"), "调值分支里有 first_person（左右拨真的接上了）")
	t.ok(step.contains("if not fresh:"),
		"……且只认 `fresh`：长按不该反复弹警告框（否则「关了又被弹出来」会变成循环）")
	t.ok(step.contains("_open_fpv_confirm()"), "往右 ⇒ 过警告门")
	t.ok(step.contains("Settings.set_first_person(false)"),
		"往左 ⇒ 直接关，不弹任何东西（关掉一个让你难受的选项不该有摩擦）")
	t.ok(step.contains("return"), "……分支自带 return（不吃函数末尾那一下统一的音效，免得双响）")

	# ---- 警告门本体 ----
	t.ok(menu_src.contains("func _open_fpv_confirm"),
		"两个入口（Enter 与拨右）共用一个 `_open_fpv_confirm()`")
	t.ok(menu_src.contains("func _read_fpv_confirm_input"), "警告框有自己的输入处理")
	t.ok(menu_src.contains("func _draw_fpv_confirm_stage"), "警告框有自己的绘制")
	t.ok(menu_src.contains("stage = Stage.FPV_CONFIRM"), "……真的会切到那一页")
	t.ok(menu_src.contains("Stage.FPV_CONFIRM:"),
		"`_read_input` / `_draw` / `nav_axis` / Esc 保险丝都认这一页（四张 match 表都加了）")

	# ---- 写入唯一、且被下标守卫包着（这是那句安全性的**结构证明**）----
	var read := _func_body(menu_src, "func _read_fpv_confirm_input")
	var i_guard := read.find("if fpv_confirm_row == FPV_CONFIRM_YES:")
	var i_write := read.find("Settings.set_first_person(true)")
	t.ok(i_guard >= 0, "警告框里：写入被 `fpv_confirm_row == FPV_CONFIRM_YES` 守着")
	t.ok(i_write >= 0, "……守卫里面真的调了 `Settings.set_first_person(true)`")
	t.gt(float(i_write), float(i_guard), "写入在守卫**之后**（不是先写后判）")
	t.eq(read.count("Settings.set_first_person"), 1,
		"警告框里只有**一处**写入 —— 没有第二条绕过守卫的路")
	var i_back := read.find("menu_back")
	t.ok(i_back >= 0 and i_back < i_write,
		"返回分支在写入之前（先判后 return）⇒ Esc 退出去一个字都不改设置")

	# ---- 文案同源：正文直接画 Settings.FPV_WARNING，UI 里不另写一份 ----
	t.ok(menu_src.contains("Settings.FPV_WARNING"),
		"警告框正文直接取 `Settings.FPV_WARNING`（唯一真源）")
	t.ok(not menu_src.contains("\"开启本模式"),
		"警示语**不在 UI 里另写一份**（「弹窗说的」和「测试断言的」必须是同一句）")

	# ---- HUD 取景框：默认关 ⇒ 对既有截图逐位无影响 ----
	var hud_src := SuiteUiStyle._code(HUD_SRC)
	var frame := _func_body(hud_src, "func _draw_cockpit_frame")
	t.ok(frame.contains("not Settings.first_person"),
		"HUD 取景框第一件事就是查设置（关着时一滴都不画 ⇒ 既有像素/截图测试逐位不变）")
	t.ok(frame.find("not Settings.first_person") < frame.find("draw_rect"),
		"……查在画之前（提前 return）")
	t.ok(frame.contains("draw_rect") and frame.contains("座舱视角"),
		"开着时才画框 + 角标")
	t.ok(hud_src.count("_draw_cockpit_frame()") >= 2,
		"……且在 `_draw()` 里被调用（只定义不接线 = 画不出来）")

	# ---- 全周天刻度导轨（轮 21）----
	var rails := _func_body(hud_src, "func _draw_cockpit_rails")
	t.ok(rails.contains("not Settings.first_person"),
		"刻度导轨第一件事也是查设置（默认关 ⇒ 既有截图逐位不变）")
	t.ok(rails.find("not Settings.first_person") < rails.find("draw_line"),
		"……查在画之前（提前 return，不是画完再判）")
	t.ok(rails.contains("_visible("),
		"投影前先判相机前后 —— `unproject_position` 对身后的点照样给坐标，\n\t\t不判的话背后那半层刻度会**镜像**着画到屏幕上")
	t.ok(rails.contains("rail_arcs()") and rails.contains("rail_visible_of("),
		"轨线也画了 —— 只画刻度就是「散落的小短杠」，真机截图里读不出网格（轮 22 的根因）")
	t.ok(rails.contains("_visible(wa)") and rails.contains("_visible(wa2)"),
		"刻度与轨线都逐段判相机前后（`unproject_position` 对身后的点照样给坐标）")
	# ⚠️ 轮 22 第一版这条断言写反了：当时要求**不许**出现 `UILayout.LINE_HAIR`
	# （理由写的是"0.5 px 的刻度就是看不到的成因"）。真因是**颜色**（青绿 + alpha 0.09），
	# 不是线宽；而绕开 `UILayout` 那两档直接违反工程的线宽铁律（`suite_ui_style` 判 FAIL）。
	# ⇒ 现在反过来钉：导轨线宽**必须**来自 `UILayout`，可见性由颜色承担。
	t.ok(rails.contains("UILayout.LINE_STRUCT") and rails.contains("UILayout.LINE_HAIR"),
		"导轨线宽走 `UILayout` 那两档（地平线 / 主刻度 = LINE_STRUCT，次刻度 / 轨线 = LINE_HAIR）")
	t.ok(not rails.contains("RAIL_W_") and not rails.contains("RAIL_OUTLINE"),
		"……不再自造 `RAIL_W_*` / `RAIL_OUTLINE` 那套线宽（工程只有两档，闸门会炸）")
	t.ok(rails.contains("deco_white("),
		"颜色走 `deco_white()`（工程的白 NEUTRAL）—— 不再自造颜色常量")
	t.ok(rails.contains("rail_dirs()"),
		"画的是那张缓存过的方向表（不是在这里内联一份自己的刻度）")
	t.ok(not rails.contains("player"),
		"导轨**不依赖 player** —— 纯相机 + 设置（阵亡那一刻层级不跳变）")

	var draw_body := _func_body(hud_src, "func _draw()")
	var i_rails := draw_body.find("_draw_cockpit_rails()")
	var i_frame := draw_body.find("_draw_cockpit_frame()")
	t.ok(i_rails >= 0, "`_draw()` 里真的调用了 `_draw_cockpit_rails()`")
	t.ok(i_rails > draw_body.find("can_draw()"),
		"调用点在 `can_draw()` 之后（没有相机时算投影会炸）")
	t.ok(i_frame > i_rails,
		"刻度导轨画在座舱框**之前** —— 层级是「座舱内壁 → 窗框」")


# ============================================================ ⑨ 自由切换（轮 25）

## 需求原文（用户，轮 25）：
##   「把第一人称和第三人称切换按钮从设置菜单里面调到 F1 键，然后把眩晕警告先保留，
##    但是隐藏着，以后我们可以把它放到别的地方去，现在先隐藏，
##    做第一人称第三人称随意切换的形式。」
##   「手柄就是长按回头键吧，那个手柄按钮 4，长按就会变成第三人称。」
##
## 这一节钉三件事：
##   ① **切换本体是个纯函数**（`Settings.toggle_first_person()`）——
##      无头里注入按键不可靠（见套件开头那两条装置规矩），所以「视角到底切没切」
##      必须能在不按任何键的情况下问出来；
##   ② **两条路都汇到它** —— 键盘 F1（`main.gd`）与手柄长按 Back（`player_controller.gd`），
##      两条路**只有一个状态机**，不存在「键盘切了、手柄没切」这种分叉；
##   ③ **撤的是入口，不是门** —— 设置页那一行没了 ⇒ 眩晕弹窗不可达；但门的每个部件
##      （`Stage.FPV_CONFIRM` / `_open_fpv_confirm` / `FPV_CONFIRM_ROWS` / `Settings.FPV_WARNING`
##      / `fpv_confirm_row` / Esc 保险丝）都还在，把那一行加回来就原样复活。
##
## ⚠️ 与前面 `_gate` 那一节的分工：那边测「门本身对不对」（下标顺序、写入被守卫包着），
## 这边测「轮 25 把入口挪走了、但没顺手把门拆了」。
static func _hotkey25(t: T) -> void:
	t.suite("FPV / 自由切换：F1 键 + 长按 Back（轮 25）")

	# ---- ① 切换本体：纯函数、双向 ----
	var before: bool = Settings.first_person
	Settings.set_first_person(true)
	t.eq(Settings.toggle_first_person(), false, "toggle_first_person() 从「开」翻到「关」")
	t.not_ok(Settings.first_person, "……状态真的落到了关（不是只返回个数）")
	t.eq(Settings.toggle_first_person(), true, "再翻一次回到「开」（是翻转，不是单向开关）")
	t.ok(Settings.first_person, "……状态跟着回来")
	Settings.set_first_person(before)

	# ---- ② 键盘那一路 ----
	var kb: Array = InputSetup.BINDINGS.get("toggle_fpv", [])
	t.eq(kb.size(), 1, "出厂表里 toggle_fpv 只有一个键（不占第二个入口去挤别的动作）")
	t.eq(kb[0] if kb.size() > 0 else -1, KEY_F1, "……那个键就是 F1（唯一真源在 BINDINGS）")
	t.ok(InputSetup.bound_keys("toggle_fpv").has(KEY_F1),
		"……而且真的进了 InputMap（读运行时表，不是那份字面量）")
	t.eq(InputSetup.key_label(KEY_F1), "F1", "F1 有可读键名（帮助面板不会印出空白）")
	t.not_ok(InputSetup.LOCKED_ACTIONS.has("toggle_fpv"),
		"……没有锁死 —— 玩家可以按自己习惯把它挪走（锁死的只有 menu_back / pause / confirm）")

	var main_src := SuiteUiStyle._code(MAIN_SRC)
	var g := _func_body(main_src, "func _handle_global_input")
	var i_phase := g.find("if phase != Phase.FIGHT:")
	var i_paused := g.find("if _paused:")
	t.ok(i_phase >= 0 and i_paused >= 0, "……那两道 early-return 也都在")
	# ★★ 2026-09-30：F1 现在有**两个**入口。
	# 老板：「**另外可以随便按F1切换火箭时候仓内的第一人称视角**」⇒ 发射段那一个
	# 必须摆在下面那道 `phase != Phase.FIGHT` 早退**之前**（发射段的 phase 是
	# `Phase.LAUNCH`，早退之后按 F1 一个字都不会发生），而战斗段那一个仍在闸之后。
	# ⇒ "F1 在闸之后"这条要**从闸之后开始找**，不能再用"第一处 toggle_fpv"。
	var i_launch := g.find("Phase.LAUNCH")
	var i_f1 := g.find('"toggle_fpv"', i_paused)
	t.ok(i_f1 >= 0, "`_handle_global_input()` 里接了 toggle_fpv（F1 真的会走到设置里）")
	t.gt(float(i_f1), float(i_phase), "战斗段那一个 F1 在「非战斗」闸**之后**（菜单里按 F1 什么也不做）")
	t.gt(float(i_f1), float(i_paused), "……也在「暂停」闸之后（暂停期间输入整个交给暂停菜单）")
	t.ok(g.contains("Settings.toggle_first_person()"),
		"……走的是那个唯一实现（回写状态，不在这里再写第二份翻转）")
	t.ok(i_launch >= 0 and i_launch < i_phase,
		"★★ 发射段那一个 F1 在两道闸**之前**（早退会让它整段静默失效）")
	var launch_branch := g.substr(i_launch, i_phase - i_launch)
	t.ok(launch_branch.contains("_launch_eye_cockpit"),
		"★★ ……翻的是**发射段自己那一位**")
	t.not_ok(launch_branch.contains("Settings.toggle_first_person"),
		"★★ ……而且**不许**写 `Settings.first_person`：在箭顶按一下 F1 不该把机体也改成第一人称")

	# ---- ③ 手柄那一路：长按 Back ----
	var lback: Dictionary = InputSetup.PAD_HOLD.get("look_back", {})
	t.eq(str(lback.get("hold_action", "")), "toggle_fpv",
		"手柄上视角切换挂在 look_back 上（点按 Back 仍是按住回头看）")
	t.gt(float(lback.get("secs", 0.0)), 1.0,
		"长按阈值 1.2 s，明显长于别处的 0.6 s —— 回头本身就是按住型动作，短阈值会误切")
	t.eq(str(lback.get("glyph", "")), "长按 Back",
		"写法是「长按 Back」（`suite_gamepad` 拿它做反向门，改这里会连带红）")
	t.ok(InputSetup.PAD_BINDINGS.get("look_back", []).has(JOY_BUTTON_BACK),
		"触发键还是那个 Back 键（手柄 17 键全满，只能复用，用户指定）")

	var pc_src := SuiteUiStyle._code(PLAYER_SRC)
	var rh := _func_body(pc_src, "func _run_pad_hold")
	t.ok(rh.contains('"toggle_fpv":'), "手柄长按分派表（`match`）里有 toggle_fpv")
	t.ok(rh.contains("Settings.toggle_first_person()"),
		"……调的是与 F1 **同一个**函数（两条路只有一个状态机）")

	# ---- ④ 撤的是入口，不是门 ----
	var menu_src := SuiteUiStyle._code(MENU_SRC)
	t.not_ok(menu_src.contains('{"key": "first_person"'),
		"设置页行表里已经没有 first_person ⇒ 眩晕弹窗暂时**没有入口**")
	t.ok(menu_src.contains("func _open_fpv_confirm"), "但门的入口函数还在（`_open_fpv_confirm`）")
	t.ok(menu_src.contains("func _read_fpv_confirm_input"), "门的输入处理还在")
	t.ok(menu_src.contains("func _draw_fpv_confirm_stage"), "门的绘制还在")
	t.ok(menu_src.contains("Settings.FPV_WARNING"), "门的正文还在（唯一真源）")
	t.ok(menu_src.contains("Stage.FPV_CONFIRM:"), "四张 match 表仍然认这一页（Esc 保险丝也在）")
	t.eq(MainMenu.FPV_CONFIRM_ROWS.size(), 2, "门的两个选项还在（下标顺序由前面那节管）")
	t.ok(SuiteUiStyle._code(SETTINGS_SRC).contains("func toggle_first_person"),
		"而切换本体在 Settings 里 —— 与界面无关，门拆不拆都不影响它")
	# ⚠️ 反过来也要钉：`_setting_step` / `_read_settings_input` 里那两个 first_person 分支
	# **刻意保留**（用户："相关代码不用删"）。删掉它们不算 bug，但会让"把行加回来"变麻烦——
	# 这一条把"留着"这件事也钉住，免得以后有人顺手清理掉。
	var step := _func_body(menu_src, "func _setting_step")
	t.ok(step.contains('"first_person":'),
		"`_setting_step` 里那个分支**仍然保留**（当前不可达，但把行加回来就复活）")
	var readin := _func_body(menu_src, "func _read_settings_input")
	t.ok(readin.contains('"first_person"'),
		"`_read_settings_input` 里那一段也保留（Enter / 拨右两个手势的入口函数都还在）")

	# ---- ⑤ 两处"说明书与现实一致"（都是**真机截图**才暴露出来的）----
	#
	# ⚠️ 这两条为什么非要有：撤一行、加一个动作，纯逻辑测试全绿，
	# 但界面会**撒谎**——截图一跑就露馅。踩过的两个具体形态：
	#   ① 重绑页那一格显示成原始键名 `toggle_fpv`（别的行都是「切换目标」这种可读名）——
	#      根因是 `ACTION_NAMES` 漏了它，而 `action_name()` 的兜底正是"返回原名"，
	#      **不报错、测试也不红**；
	#   ② 设置页底部提示仍旧写着「Enter 选曲 / 开启第一人称」——而那一行已经撤了，
	#      提示在教玩家按一个**页面上不存在**的入口。
	# ⇒ 两条都钉死：动作名表要盖住重绑页**每一行**（不只是 toggle_fpv），
	#   提示里不许再出现那句假话。
	var missing: Array = []
	for a in MainMenu.keys_flat():
		if not InputSetup.ACTION_NAMES.has(str(a)):
			missing.append(str(a))
	t.eq(missing.size(), 0,
		"重绑页每一行都有可读动作名（缺了就会回退成原始键名；缺的是 %s）" % str(missing))
	t.eq(InputSetup.action_name("toggle_fpv"), "第一人称 / 第三人称",
		"……其中这一行显示的就是它的可读名")
	# ⚠️ 断言要**收窄到设置页那一页**："开启第一人称"这六个字还合法地活在
	# `FPV_CONFIRM_ROWS`（警告框的「是」选项）里 —— 那是**刻意保留**的门。
	# 一开始写成扫整篇 ⇒ 假红（门还在，所以它当然还在）。
	var sbody := _func_body(menu_src, "func _draw_settings_stage")
	t.not_ok(sbody.contains("开启第一人称"),
		"设置页底部提示里不再出现「开启第一人称」（那一行撤了 ⇒ 那句话是假的）")
	t.ok(sbody.contains("F1"),
		"……而是换成了指向新入口的提示（玩家来设置页找它，能看到它搬去 F1 了）")

# ============================================================ ⑨ 中央屏三模式（轮 31）

## 用户原话：「按 m 键可以切换中间屏幕显示的是雷达还是机体剪影还是小地图（等高线地形图）」；
## 紧接着追加：「机体剪影按照血量来划分颜色（I 立场还在的时候就是蓝色，血量大于 80%
## 是绿色，高于 50% 是黄色，高于 30% 是橙色，高于 0% 是红色）」。
##
## 拆成五组：
##   ① **模式状态**（`Settings.dash_screen_mode`）：出厂默认档、可逆循环、下标夹取、名字表；
##   ② **M 键**（`InputSetup.BINDINGS`）：注册了 / 可读名有 / 重绑页有一行 / 操作说明有一行；
##   ③ **接线**（`main.gd`）：`_handle_global_input()` 里接了它，位置在两道 early-return 之后，
##      且**没有**把 F1 的调用体挤到自己体内（本轮踩过）；
##   ④ **分派**（`hud.gd`）：`_draw_radar()` 里三种模式各有去处、底盘在分派之前、
##      雷达那一路的量程标签与敌我光点都还在；
##   ⑤ **几何与分色**（纯函数）：剪影「机体→表」映射 / 在圆内 / 总高对 /
##      脚不压血条 / 四台互不相同；等高线闭合 / 逐点不相交 /
##      相位真的起作用又逐位可复现；五档颜色的分界点与"橙是插值出来的第三档"。
## 一组多边形点的**并集**包围盒（用来验"贴图矩形 == 外轮廓点表的 bbox"）。
static func _bbox_of(parts: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for part in parts:
		var pp: PackedVector2Array = part
		for pt in pp:
			var pv: Vector2 = pt
			if first:
				r = Rect2(pv, Vector2.ZERO)
				first = false
			else:
				r = r.expand(pv)
	return r


static func _screen31(t: T) -> void:
	t.suite("FPV / 中央屏三模式：M 键切换（轮 31）")

	# ---- ① 模式状态 ----
	var mode_was: int = Settings.dash_screen_mode
	t.eq(Settings.DASH_SCREEN_RADAR, 0, "雷达是 0 档（= 不按 M 时看到的那一档）")
	t.eq(Settings.DASH_SCREEN_SILHOUETTE, 1, "机体剪影是 1 档")
	t.eq(Settings.DASH_SCREEN_CONTOUR, 2, "等高线地形图是 2 档")
	t.eq(Settings.DASH_SCREEN_COUNT, 3, "一共三种模式（循环的分母就是它）")
	t.eq(Settings.DASH_SCREEN_NAMES.size(), Settings.DASH_SCREEN_COUNT,
		"名字表的长度与档数一致（少一个就是 `label()` 越界）")
	var uniq := {}
	for nm in Settings.DASH_SCREEN_NAMES:
		uniq[str(nm)] = true
	t.eq(uniq.size(), Settings.DASH_SCREEN_COUNT, "三个名字互不相同（提示里不会出现两个一样的）")

	var ssrc := SuiteUiStyle._code(SETTINGS_SRC)
	t.ok(ssrc.contains("var dash_screen_mode := DASH_SCREEN_RADAR"),
		"**出厂**默认档就是雷达（读源码而不是读运行时 —— 玩家存档可能已经切过）")
	t.ok(ssrc.contains('cfg.set_value("ui", "dash_screen", dash_screen_mode)'),
		"`save_config()` 里写了这一项（不写的话切了不记住）")
	var load_body := _func_body(ssrc, "func load_config")
	t.ok(load_body.contains('get_value("ui", "dash_screen"'), "`load_config()` 里读回它")
	t.ok(load_body.contains("dash_screen_mode = clampi("),
		"……而且**夹取**（老存档没这项、或以后档数变了都不会越界 —— 与镜头那几个索引同一条理由）")

	# 循环：三次回到原值，中途每次都真的换了档
	var a: int = Settings.cycle_dash_screen()
	t.eq(a, posmod(mode_was + 1, Settings.DASH_SCREEN_COUNT),
		"`cycle_dash_screen()` 返回切**之后**的档（调用方印提示直接用）")
	t.eq(Settings.dash_screen_mode, a, "……返回值与落在状态里的档一致（不是只返回个数）")
	var b: int = Settings.cycle_dash_screen()
	t.not_ok(a == b, "连按两次落在不同档（不是原地不动）")
	t.eq(Settings.cycle_dash_screen(), mode_was, "按三次回到起点（三档循环，不会漏档）")

	Settings.set_dash_screen_mode(99)
	t.eq(Settings.dash_screen_mode, Settings.DASH_SCREEN_COUNT - 1,
		"`set_dash_screen_mode(99)` 夹取到最后一档（越界不崩）")
	Settings.set_dash_screen_mode(-5)
	t.eq(Settings.dash_screen_mode, Settings.DASH_SCREEN_RADAR, "负数夹到第一档")
	Settings.set_dash_screen_mode(Settings.DASH_SCREEN_CONTOUR)
	t.eq(Settings.dash_screen_label(),
		str(Settings.DASH_SCREEN_NAMES[Settings.DASH_SCREEN_CONTOUR]),
		"`dash_screen_label()` 与名字表逐字一致")
	Settings.set_dash_screen_mode(mode_was)

	# ---- ② M 键 ----
	var kb: Array = InputSetup.BINDINGS.get("cycle_dash_screen", [])
	t.eq(kb.size(), 1, "出厂表里 `cycle_dash_screen` 只有一个键")
	t.eq(kb[0] if kb.size() > 0 else -1, KEY_M, "……那个键就是 M（用户指定）")
	t.ok(InputSetup.bound_keys("cycle_dash_screen").has(KEY_M),
		"……而且真的进了 InputMap（读运行时表，不是那份字面量）")
	t.eq(InputSetup.key_label(KEY_M), "M", "M 有可读键名（帮助面板不会印出空白）")
	t.eq(InputSetup.action_name("cycle_dash_screen"), "中央屏切换",
		"有可读动作名（漏了它重绑页那一格会印成原始键名 `cycle_dash_screen`）")
	t.not_ok(InputSetup.LOCKED_ACTIONS.has("cycle_dash_screen"),
		"……没有锁死（玩家可以按自己习惯把它挪走）")
	t.ok(MainMenu.keys_flat().has("cycle_dash_screen"),
		"重绑页（`MainMenu.KEY_GROUPS`）里有这一行 —— `suite_keybind` 会反向查这张表")
	var help_hit := 0
	for sec: Dictionary in InputSetup.HELP_SECTIONS:
		if str(sec["items"]).contains("cycle_dash_screen"):
			help_hit += 1
	t.eq(help_hit, 1,
		"操作说明（`HELP_SECTIONS`）里**恰好一行**印了它 —— 不然玩家不知道有 M 这个键")

	# ---- ③ 接线 ----
	var main_src := SuiteUiStyle._code(MAIN_SRC)
	var g := _func_body(main_src, "func _handle_global_input")
	var i_phase := g.find("if phase != Phase.FIGHT:")
	var i_paused := g.find("if _paused:")
	var i_m := g.find('"cycle_dash_screen"')
	t.ok(i_m >= 0, "`_handle_global_input()` 里接了 `cycle_dash_screen`（M 真的会走到设置里）")
	t.gt(float(i_m), float(i_phase), "M 在「非战斗」闸**之后**（菜单里按 M 什么也不做）")
	t.gt(float(i_m), float(i_paused), "M 在「暂停」闸之后（暂停期间输入整个交给暂停菜单）")
	t.ok(g.contains("Settings.cycle_dash_screen()"),
		"……走的是那个唯一实现（不在这里再写一份 posmod）")

	# ⚠️ 下面两条是**从本轮的一次翻车**里来的。
	# 往这个函数里插新分支时，第一版把 `Settings.toggle_first_person()` 插到了
	# 新 `if` 的**体内** —— 于是"按 M 也会切第一人称"，而当时**所有纯逻辑断言全绿**
	#（没有任何一条查过那个 if 体里装的是什么）。
	# 断言不能只查"两个字符串都在"：必须查**它们在什么位置**。
	var f1 := g.find('if Input.is_action_just_pressed("toggle_fpv"):')
	t.ok(f1 >= 0, "F1 那条分支还在（没被新分支顶掉）")
	# ⚠️ 窗口 200 而**不是** 160：轮 35 给 M 那条 `if` 加了 `Settings.first_person and `
	# 门（+29 字符），原本 160 的窗口会把 M 那行**截在中间** —— `find` 落空 ⇒ `-1`，
	# 而 `0 < -1` 是假 ⇒ 这条断言会以「顺序错了」的名义红，与真实原因毫无关系。
	# 量过：F1 的 if → M 的 if 现在是 118 字符（剥注释后）。
	var near_f1 := g.substr(f1, 200)
	t.ok(near_f1.contains("Settings.toggle_first_person()"),
		"……而且它的调用体就紧跟在自己的 if 下面（插新分支时最容易被挤走的地方）")
	t.ok(near_f1.find("Settings.toggle_first_person()")
			< near_f1.find('is_action_just_pressed("cycle_dash_screen")'),
		"……顺序是「F1 的 if → F1 的体 → M 的 if」⇒ 两条路各管各的（本轮踩过一次）")

	# ---- ④ 分派 ----
	var hud_src := SuiteUiStyle._code(HUD_SRC)
	var rbody := _func_body(hud_src, "func _draw_radar")
	var i_circle := rbody.find("draw_circle(center, radius")
	var i_silh := rbody.find("Settings.DASH_SCREEN_SILHOUETTE")
	var i_cont := rbody.find("Settings.DASH_SCREEN_CONTOUR")
	t.ok(i_circle >= 0 and i_silh > 0 and i_cont > 0,
		"`_draw_radar()` 里：圆底 + 两种非雷达档各有去处")
	t.gt(float(i_silh), float(i_circle),
		"分派在圆底**之后** ⇒ 三种模式共用同一个底盘（换模式只换内容，屏幕不变形）")
	t.gt(float(i_cont), float(i_silh), "剪影档排在等高线档之前（顺序 = 常量顺序，好读）")
	t.ok(rbody.contains("_draw_screen_silhouette(center, radius)"),
		"剪影档调的就是那个函数（参数是共用的圆心与半径）")
	t.ok(rbody.contains("_draw_screen_contour(center, radius)"), "等高线档同理")
	# 雷达那一路的**功能**一件都不能少（默认档必须还是原来那块屏）
	var tail := rbody.substr(i_cont)
	t.ok(tail.contains("RADAR %.1fkm"), "雷达的量程标签仍在（默认档逐位不变）")
	t.ok(tail.contains("live_allies_of") and tail.contains("live_hostiles_of"),
		"……敌我光点也仍在（切模式不会把雷达功能弄丢）")
	t.ok(tail.contains("draw_colored_polygon(self_pts, HUD)"), "……自机三角也在")

	var silh_body := _func_body(hud_src, "func _draw_screen_silhouette")
	t.ok(silh_body.contains("silhouette_color("),
		"剪影颜色走那个纯函数（唯一真源）")
	t.not_ok(silh_body.contains("ifield_hp >"),
		"……绘制里**没有**第二份 I 立场判断（有两份就会出现「剪影绿、下面血条黄」）")
	t.ok(silh_body.contains("if radius <= 8.0:"), "剪影绘制有窄窗口守卫")
	t.ok(silh_body.contains("UILayout.LINE_STRUCT"),
		"剪影描边用 LINE_STRUCT —— 0.5 px 的直边在深色底上会整段消失（轮 30 的教训）")
	t.ok(silh_body.contains("silhouette_key(player.profile.id, player.profile.form)"),
		"轮 32：形状按**当前机体**选表 —— 写死一台就会「开佩涅罗佩却显示柯西的剪影」")
	t.ok(silh_body.contains("silhouette_parts(center, radius, key)"),
		"……而且把**圆心与半径**传下去（四台机共用一个圆盘，只有表不同）")
	t.not_ok(hud_src.contains("const SILH_LIFT"),
		"轮 32 起没有 SILH_LIFT 了 —— 改成「锚底边」（四台机总高不同，锚中心会让脚上下乱跑）")
	t.not_ok(hud_src.contains("const SILH_H :="),
		"……也没有单个 SILH_H 了 —— 换成按机体查的 SILH_H_BY_KEY")
	var cont_body := _func_body(hud_src, "func _draw_screen_contour")
	t.ok(cont_body.contains("contour_rings("), "等高线走那个纯函数（几何才可断言）")
	t.ok(cont_body.contains("player.global_position"),
		"……相位来自玩家位置 ⇒ 飞起来地形会走（这才是小地图）")
	t.ok(cont_body.contains("if radius <= 8.0:"), "等高线绘制也有窄窗口守卫")
	t.not_ok(cont_body.contains("UILayout.LINE_HAIR"),
		"……而且整段没有 LINE_HAIR：等高线与十字在 0.5 px 下都会读成虚线（第一版翻过车）")

	# ---- ⑤ 几何：剪影（轮 32 换成**真实线稿描出来的轮廓**）----
	var center := Vector2(800.0, 782.0)
	var bar_top := center.y + FlightHUD.RADAR_RADIUS * 0.60

	# —— 映射：机体 → 剪影表下标（纯函数 ⇒ 映射本身也能被钉住）——
	t.eq(FlightHUD.SILH_H_BY_KEY.size(), 6,
		"高度表 6 项：5 台有线稿的机体（轮 35 加了阿利宙斯巡航态）+ 1 件兜底")
	t.eq(FlightHUD.SILH_KEY_FALLBACK, 4, "兜底件的下标 = 4（**不是**末位 —— 新增机体往后追加）")
	t.eq(FlightHUD.silhouette_key(SuitProfile.Id.XI, SuitProfile.ArizeusForm.NORMAL), 0,
		"柯西 ⇒ 0 号（用户给的「柯西.png」）")
	t.eq(FlightHUD.silhouette_key(SuitProfile.Id.PENELOPE, SuitProfile.ArizeusForm.NORMAL), 1,
		"佩涅罗佩 ⇒ 1 号（「佩涅罗佩.jpg」）")
	t.eq(FlightHUD.silhouette_key(SuitProfile.Id.ARIZEUS, SuitProfile.ArizeusForm.CRUISE), 5,
		"阿利宙斯·巡航 ⇒ 5 号（「阿利宙斯巡航态.png」，轮 35 单列）—— 翼展平铺是**另一个形状**，"
			+ "与常态化共用 2 号时屏上画的是常态的外壳")
	t.eq(FlightHUD.silhouette_key(SuitProfile.Id.ARIZEUS, SuitProfile.ArizeusForm.NORMAL), 2,
		"阿利宙斯·常态 ⇒ 2 号（「阿利宙斯.png」，本轮唯一走「结构线」配方的）")
	t.eq(FlightHUD.silhouette_key(SuitProfile.Id.ARIZEUS, SuitProfile.ArizeusForm.CORE_NU), 3,
		"核心形态 ⇒ 3 号（「量产型牛高达.png」）—— 设定上是另一台机，只看 id 会画成阿利宙斯的壳")
	t.eq(FlightHUD.silhouette_key(SuitProfile.Id.GUSTAV00, SuitProfile.ArizeusForm.NORMAL), 4,
		"古斯塔夫没有线稿 ⇒ 兜底 4 号（宁可显示通用机体，也不能让那块屏空着）")
	t.eq(FlightHUD.silhouette_key(SuitProfile.Id.MESSER_M01, SuitProfile.ArizeusForm.CORE_NU), 4,
		"梅萨没有线稿 ⇒ 兜底 4 号（形态参数不该影响结果）")

	# —— 逐台查几何：同一套判据过 5 个下标 ——
	var sigs: Array = []
	for key in FlightHUD.SILH_H_BY_KEY.size():
		var parts := FlightHUD.silhouette_parts(center, FlightHUD.RADAR_RADIUS, key)
		t.gt(float(parts.size()), 0.0, "第 %d 号剪影非空（%d 块）" % [key, parts.size()])
		if key != FlightHUD.SILH_KEY_FALLBACK:
			t.eq(parts.size(), 1,
				"第 %d 号是**一条闭合轮廓**（真实线稿：腿间那道缝在外轮廓上是个凹口，不是孔）" % key)
		var h := FlightHUD.RADAR_RADIUS * float(FlightHUD.SILH_H_BY_KEY[key])
		var pts: Array = []
		var min_x := INF
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		var area2 := 0.0
		var min_seg := INF
		for part in parts:
			var pp: PackedVector2Array = part
			t.gt(float(pp.size()), 2.0, "第 %d 号每块至少是个三角形（%d 点）" % [key, pp.size()])
			var n := pp.size()
			for k in n:
				# ⚠️ 名字不能叫 a / b：本函数第 1562/1566 行已经声明过 `var a` / `var b`，
				# GDScript 不允许嵌套作用域遮蔽同名变量（会直接 Parse Error，整套件一条都跑不了）。
				var pa := pp[k]
				var pb := pp[(k + 1) % n]
				area2 += pa.cross(pb)               # 鞋带公式（闭合环自带回边）
				min_seg = minf(min_seg, pa.distance_to(pb))
				pts.append(pa)
				min_x = minf(min_x, pa.x)
				max_x = maxf(max_x, pa.x)
				min_y = minf(min_y, pa.y)
				max_y = maxf(max_y, pa.y)
		t.near(max_y - min_y, h, 0.5,
			"第 %d 号总高恰为 %.2f r = %.1f px（v 归一化到 0..100 的直接结果）"
				% [key, FlightHUD.SILH_H_BY_KEY[key], h])
		if key != 5:
			t.lt(max_x - min_x, h, "第 %d 号总宽窄于总高（机形是竖的）" % key)
		else:
			t.gt(max_x - min_x, h,
				"第 5 号（阿利宙斯巡航态）**反过来**：总宽 %.0f > 总高 %.0f —— 翼展平铺的横形"
					% [max_x - min_x, h])
		# 底边锚点 = 「脚不许压血条」的另一面
		var want_bottom := center.y + FlightHUD.RADAR_RADIUS * FlightHUD.SILH_BOTTOM_K
		t.near(max_y, want_bottom, 0.5,
			"第 %d 号**底边**锚在圆心 + %.2f r（锚底边而不是锚中心 —— 五台机总高不同，锚中心会让脚上下乱跑）"
				% [key, FlightHUD.SILH_BOTTOM_K])
		t.lt(max_y, bar_top,
			"第 %d 号脚底（%.1f）在血条顶（%.1f）**之上**，留了 %.1f px（第一版 1.58 r 时两者重叠 7.8 px，4× 图里那条红血条横穿双脚）"
				% [key, max_y, bar_top, bar_top - max_y])
		var worst := 0.0
		for v in pts:
			worst = maxf(worst, v.distance_to(center))
		t.lt(worst, FlightHUD.RADAR_RADIUS * 0.93,
			"第 %d 号每个顶点都在圆盘里且留了余量（最远 %.1f px / 半径 %.0f）—— 顶出去就是画到屏幕别处了"
				% [key, worst, FlightHUD.RADAR_RADIUS])
		t.gt(absf(area2) * 0.5, 1.0,
			"第 %d 号是**非退化**多边形（鞋带面积 %.0f px²）—— 退化成一条线的话三角化会静默出垃圾"
				% [key, absf(area2) * 0.5])
		t.gt(min_seg, 0.05,
			"第 %d 号没有重合的相邻点（最近一段 %.3f px）—— 重合点会让三角化退化" % [key, min_seg])
		sigs.append([key, pts.size(), snappedf(max_x - min_x, 0.5)])

	# —— 五台真机必须**互不相同** ——
	# 抄表 / 贴错图是最容易发生、又最不容易看出来的错（五张图画面对比才看得出来）。
	# ⚠️ 跳过兜底件（4 号）与「新增就别重排」之外还要注意：`sigs` 是**按下标顺序**攒的，
	# 所以这里按**键号表**取，而不是按下标 0,1,2,3（轮 35 的下标 5 就落在这条路上）。
	var sig_keys: Array = [0, 1, 2, 3, 5]
	for a_i in sig_keys.size():
		for b_i in range(a_i + 1, sig_keys.size()):
			var ka: int = sig_keys[a_i]
			var kb2: int = sig_keys[b_i]
			t.not_ok(sigs[ka] == sigs[kb2],
				"第 %d 号与第 %d 号不是同一个形状（%d 点 / 宽 %.1f  vs  %d 点 / 宽 %.1f）"
					% [ka, kb2, sigs[ka][1], sigs[ka][2], sigs[kb2][1], sigs[kb2][2]])

	# ---- ⑤ 几何：等高线 ----
	var rings := FlightHUD.contour_rings(center, FlightHUD.RADAR_RADIUS * 0.94,
		FlightHUD.CONTOUR_N, FlightHUD.CONTOUR_SEG)
	t.eq(rings.size(), FlightHUD.CONTOUR_N, "等高线正好 %d 圈" % FlightHUD.CONTOUR_N)
	var prev := PackedFloat32Array()
	for ri in rings.size():
		var rr: PackedVector2Array = rings[ri]
		t.eq(rr.size(), FlightHUD.CONTOUR_SEG + 1,
			"第 %d 圈有 %d 个点（末点回到首点 ⇒ 闭合）" % [ri, FlightHUD.CONTOUR_SEG])
		t.lt(float(rr[0].distance_to(rr[rr.size() - 1])), 1e-4,
			"……第 %d 圈首尾确实是同一个点" % ri)
		var radii := PackedFloat32Array()
		var far := 0.0
		for v in rr:
			var d: float = v.distance_to(center)
			radii.append(d)
			far = maxf(far, d)
		t.lt(far, FlightHUD.RADAR_RADIUS,
			"第 %d 圈全部点在圆内（最远 %.1f px < 半径 %.0f）" % [ri, far, FlightHUD.RADAR_RADIUS])
		if prev.size() > 0:
			var cross := 0
			var gap := INF
			for k in radii.size():
				if radii[k] <= prev[k]:
					cross += 1
				gap = minf(gap, radii[k] - prev[k])
			t.eq(cross, 0,
				"第 %d ↔ %d 圈**逐点都不相交**（%d 处交叉）—— 相交就读成「两座山连成一片」"
					% [ri - 1, ri, cross])
			t.gt(gap, 0.0, "……最近处还差 %.2f px（正数 = 真的分得开）" % gap)
		prev = radii
	# 相位：真的起作用（飞起来地形会走），但同一相位逐位可复现（截图可重拍）
	var rings2 := FlightHUD.contour_rings(center, FlightHUD.RADAR_RADIUS * 0.94,
		FlightHUD.CONTOUR_N, FlightHUD.CONTOUR_SEG, Vector2(2.0, 0.0))
	var moved := 0
	var same := true
	for ri in rings.size():
		if (rings[ri] as PackedVector2Array)[0].distance_to(
				(rings2[ri] as PackedVector2Array)[0]) > 0.01:
			moved += 1
		if (rings[ri] as PackedVector2Array) != (rings2[ri] as PackedVector2Array):
			same = false
	t.eq(moved, rings.size(), "相位真的起作用（%d / %d 圈的形状变了）⇒ 飞起来地形会走"
			% [moved, rings.size()])
	var rings3 := FlightHUD.contour_rings(center, FlightHUD.RADAR_RADIUS * 0.94,
		FlightHUD.CONTOUR_N, FlightHUD.CONTOUR_SEG, Vector2(2.0, 0.0))
	var same2 := true
	for ri in rings.size():
		if (rings2[ri] as PackedVector2Array) != (rings3[ri] as PackedVector2Array):
			same2 = false
	t.ok(same2, "同一个相位逐位一致（不掺随机数 ⇒ 判据图可原样重拍）")
	t.ok(not same, "……而不同相位确实不同（否则「滚动」是假的）")

	# ---- ⑤ 分色：用户指定的五档 ----
	t.eq(FlightHUD.silhouette_color(1.0, true), FlightHUD.IFIELD,
		"I 立场还在 ⇒ 蓝（盾在，机体本身挨不挨打都还是「有壳」状态）")
	t.eq(FlightHUD.silhouette_color(0.05, true), FlightHUD.IFIELD,
		"……哪怕血只剩 5% 也是蓝：I 立场的优先级**高于**血量")
	t.eq(FlightHUD.silhouette_color(1.0, false), FlightHUD.HUD, "满血 ⇒ 绿")
	t.eq(FlightHUD.silhouette_color(0.81, false), FlightHUD.HUD, "……81% 仍是绿")
	t.eq(FlightHUD.silhouette_color(0.8, false), FlightHUD.WARN,
		"80% 本身落到黄（判据是**严格大于**，边界值归下一档）")
	t.eq(FlightHUD.silhouette_color(0.6, false), FlightHUD.WARN, "60% ⇒ 黄")
	var orange: Color = FlightHUD.WARN.lerp(FlightHUD.DANGER, FlightHUD.SILH_ORANGE_MIX)
	t.eq(FlightHUD.silhouette_color(0.5, false), orange, "50% 本身落到橙")
	t.eq(FlightHUD.silhouette_color(0.4, false), orange, "40% ⇒ 橙")
	t.eq(FlightHUD.silhouette_color(0.3, false), FlightHUD.DANGER, "30% 本身落到红")
	t.eq(FlightHUD.silhouette_color(0.1, false), FlightHUD.DANGER, "10% ⇒ 红")
	t.eq(FlightHUD.silhouette_color(0.0, false), FlightHUD.DANGER, "0% ⇒ 红（最低档，不是透明）")
	# 橙必须**真的是黄与红之间**那一档，不是第二个黄、也不是第二个红
	t.gt(orange.h, FlightHUD.DANGER.h,
		"橙的色相（%.1f°）在红的**右边**（红 %.1f° → 橙 → 黄 %.1f°）"
			% [orange.h, FlightHUD.DANGER.h, FlightHUD.WARN.h])
	t.lt(orange.h, FlightHUD.WARN.h, "……也在黄的左边 ⇒ 它是插值出来的第三档")
	t.not_ok(orange == FlightHUD.WARN, "橙 ≠ 黄（否则「>50% 黄 / >30% 橙」两档看不出区别）")
	t.not_ok(orange == FlightHUD.DANGER, "橙 ≠ 红")
	t.ok(hud_src.contains("const SILH_ORANGE_MIX := 0.55"),
		"橙是**派生**的（WARN→DANGER 插值）而不是第 10 个颜色常量 —— 调色板契约钉着恰好 9 个")

	# ---- ⑥ 机型标签那一行：中央屏罩框里**只放得下一行**（轮 32 修叠字）----
	# 单独一个新节：上面那一节是轮 31 的三模式，这一条是轮 32 修的另一件事。
	t.suite("FPV / 中央屏机型标签：罩框里只放得下一行（轮 32）")
	var v16 := Vector2(1600.0, 900.0)
	var rc16 := FlightHUD.radar_center(v16)
	var row0 := FlightHUD.fp_tag_row_y(v16)
	var dmod: Rect2 = FlightHUD.dash_modules(FlightHUD.dash_layout(v16))["center"]
	var art: Rect2 = FlightHUD.dash_center_layout(dmod)["art"]

	# ① 状态行整条搬到台面**之上**，不再压在罩框/圆盘上
	t.lt(row0, art.position.y,
		"状态行首条基线（%.1f）在罩框顶边（%.1f）之上" % [row0, art.position.y])
	t.lt(row0, rc16.y - FlightHUD.RADAR_RADIUS,
		"……也在雷达圆顶（%.1f）之上" % (rc16.y - FlightHUD.RADAR_RADIUS))

	# ② 与机体编号那一行**不相交** —— 这才是本轮修的那件事
	var name_y := rc16.y - FlightHUD.RADAR_RADIUS - 8.0
	t.gt(name_y - row0, 24.0,
		("编号行（%.1f）与状态行首条（%.1f）相距 %.1f px —— 13 / 14 pt 的字形盒"
			+ "（各约 17 px）不可能相交") % [name_y, row0, name_y - row0])

	# ③ 多条状态行**往上堆**，不会往下压进台面
	t.gt(FlightHUD.FP_TAG_PITCH, 0.0, "行距为正")
	t.lt(row0 - FlightHUD.FP_TAG_PITCH, row0, "第 2 行在第 1 行之上")
	t.lt(row0 - FlightHUD.FP_TAG_PITCH * 3.0, row0,
		"……第 4 行也更上面（同时出现时是往上排队，不是往回叠）")

	# ④ 跟着台面走，不是写死的 1600×900 坐标
	var small := Vector2(1280.0, 720.0)
	var row_s := FlightHUD.fp_tag_row_y(small)
	var rc_s := FlightHUD.radar_center(small)
	t.lt(row_s, row0, "1280×720 下首条也跟着台面上移（%.1f < %.1f）" % [row_s, row0])
	t.lt(row_s, rc_s.y - FlightHUD.RADAR_RADIUS,
		"……而且仍然在雷达圆顶之上（小窗口下同样不许压回圆里）")

	# ⑤ 「并排挤一行」为什么走不通 —— 用工程真字体量，不靠嘴说
	var fam := ThemeDB.fallback_font
	var core: SuitProfile = SuitProfile.by_id_form(
		SuitProfile.Id.ARIZEUS, SuitProfile.ArizeusForm.CORE_NU)
	var long_name: String = core.model_name
	var long_tag := "形态 " + core.form_name()
	var wn := fam.get_string_size(long_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var wt := fam.get_string_size(long_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	t.gt(wt, 0.0, "形态行有宽度（空串会让下面那条判据变成假的）")
	t.gt(wn, art.size.x * 0.9,
		"「%s」13 pt 下宽 %.0f px，几乎占满罩框内容区（%.0f px）"
			% [long_name, wn, art.size.x])
	t.gt(wn + wt, art.size.x * 1.3,
		"……再并上「%s」（%.0f px）合计 %.0f px ⇒ 并排一行绝无可能，只能各占一行"
			% [long_tag, wt, wn + wt])

	# ⑥ 接线：第一人称下状态行的 y 真的换源了
	var tag_body := _func_body(hud_src, "func _draw_model_tag")
	t.ok(tag_body.contains("fp_tag_row_y(size)"),
		"`_draw_model_tag()` 第一人称分支改用 `fp_tag_row_y(size)`")
	t.ok(tag_body.contains("if Settings.first_person:"),
		"……而且是**分支**：第三人称那条老路一行都没改")
	t.ok(tag_body.contains("var row_y: float = center.y - RADAR_RADIUS - 10.0"),
		"……保留老那条作为默认值（第三人称逐位不变）")
	t.ok(hud_src.contains("func fp_tag_row_y(view: Vector2) -> float"),
		"纯函数在场（几何不在绘制里现算 ⇒ 位置能被逐条断言）")
	t.ok(tag_body.contains("center - Vector2(0, RADAR_RADIUS + 8.0)"),
		"编号那一行**还是老位置**（轮 22 那次搬家不许被这轮改动碰掉）")



	# ============================================================ ⑨ 中央屏内部线稿贴图
	#
	# ⚠️ 本节挂在**最末**：`t.suite()` 结算的是它之前累积的断言。
	#
	# 需求链条：机主先说「不要那么剪影，还是要有点线稿在里面的」（⇒ 加了 `SILH_FILL_A`
	# 那道淡底 + 内部线稿），看完成品又说「还是没有很线稿啊」—— 查出来是**贴图根本没画
	# 上去**：`SilhLines.WH` 多套了一层方括号 ⇒ `WH[key]` 拿到的是 `[86, 120]` 整体，
	# `int(wh[0])` 报错、`texture()` 回落 `null`、`draw_texture_rect` 被 `if tex != null`
	# 跳过，屏上只剩淡底 + 外轮廓（运行期错误还被窗口日志冲掉了）。
	# 更深一层，那张贴图**即使画上去**也不对：源图是排线半调，直接降采样 ⇒ 噪点，
	# 所以又补了「源尺寸去排线 + 面积精确降采样」。下面把这两件事都钉成判据。
	#
	# ⚠️ 轮 35 改的是**配方**：机主说「除了阿利宙斯常态以外，都使用我原来的素材」
	# ⇒ 柯西 / 佩涅罗佩 / 量产型牛 / **阿利宙斯巡航态**改走「原图原样」（源画按显示
	# 尺寸的正确降采样），只有阿利宙斯常态留「结构线」。两档的差别见 `silh_lines.gd`
	# 文件头。判据也跟着拆：保真度靠**离线**的独立参考通道算 MAE（源图不在 `res://`
	# 内），工程侧钉的是**密度契约**（下面那张表）。
	t.suite("FPV / 中央屏内部线稿贴图：两档配方 · 4 bit alpha（轮 32·35）")

	var ln_src := SuiteUiStyle._code("res://scripts/ui/silh_lines.gd")
	t.gt(ln_src.length(), 0, "读得到 `scripts/ui/silh_lines.gd`（走 `SuiteUiStyle._code`）")
	var ln_sl: GDScript = load("res://scripts/ui/silh_lines.gd")
	t.ok(ln_sl != null, "`silh_lines.gd` 能当场 load（无头下也解得出贴图，见下面几条）")
	var ln_map: Dictionary = ln_sl.get_script_constant_map()
	var ln_kfb: int = FlightHUD.SILH_KEY_FALLBACK
	var ln_wh: Array = ln_map["WH"]
	var ln_b64: Array = ln_map["B64"]
	## 有线稿的键（4 号是兜底件 —— 两张表在那里都是空，不走下面这些条目）。
	var ln_keys: Array = [0, 1, 2, 3, 5]
	## 密度契约：每台 alpha 的**平均不透明度**，是离线管线烘图时报出来的原值（±0.02）。
	##
	## ⚠️ 这条取代了轮 32 那条「平均不透明度 < 0.28」。撤它的理由不是"不好"，是
	## **它题不对**了：原图原样四台的均值是 0.287 / 0.247 / 0.169 / 0.278，两台在
	## 0.28 之上、两台之下 ⇒ 同一条门对四台有**两种**判定，红绿都读不出信息。
	## 而它想表达的「不要那么剪影」已经由下面的覆盖率与「不是实心块」两条表达完了；
	## 「跟原画一致」这件事**在工程侧根本判不了**（源图不在 `res://` 内），只能靠
	## 离线管的独立参考通道（MAE：原图原样 0.018~0.026 / 结构线 0.191，见交付说明）。
	## 工程侧改成钉**密度**：谁重烘一次把配方或阈值改了，这里立刻红。
	var ln_density := {0: 0.287, 1: 0.247, 2: 0.209, 3: 0.169, 5: 0.278}

	# ---- ① 两张表的结构：一一对应、兜底件在 4 号 ----
	t.eq(ln_wh.size(), 6, "`WH` 有 6 项（5 台有线稿的 + 1 个兜底件）")
	t.eq(ln_b64.size(), 6, "`B64` 也是 6 项（少一项就是下标错位）")
	t.eq(ln_wh.size(), FlightHUD.SILH_H_BY_KEY.size(),
		"`WH` 与 `SILH_H_BY_KEY` 项数一致（两张表按同一个下标取值，长度必须同源）")
	t.eq(ln_wh[ln_kfb], [0, 0], "兜底件那项的尺寸写成 `[0, 0]`（= 「这台没有线稿」的标志）")
	t.eq(ln_b64[ln_kfb].size(), 0, "……数据也是空表")
	t.eq(ln_wh[0][0], 86, "柯西那张宽 86 —— 与 `RADAR_RADIUS` 同一套显示像素（1:1，不缩放）")
	var ln_pos := 0
	for ln_i: int in ln_keys:
		if int(ln_wh[ln_i][0]) > 0 and int(ln_wh[ln_i][1]) > 0 and ln_b64[ln_i].size() > 0:
			ln_pos += 1
	t.eq(ln_pos, 5, "五台有线稿的**每台**都是正尺寸 + 非空数据（少一台就是表错位）")
	var ln_wset := {}
	for ln_i: int in ln_keys:
		ln_wset[int(ln_wh[ln_i][0])] = true
	t.eq(ln_wset.size(), 5, "五台的贴图宽度互不相同（宽度就是那台机的实际比例，不是同一个框）")
	# 轮 35 新增的巡航态：**横形**，且排在兜底件**之后**（下标是落盘契约，不许重排）
	t.eq(ln_keys.size(), 5, "有线稿的键恰好 5 个")
	t.gt(int(ln_wh[5][0]), int(ln_wh[5][1]),
		"下标 5（巡航态）的贴图是**横形** %s —— 翼展平铺，与另外四台（竖形）方向相反"
			% [str(ln_wh[5])])
	t.eq(ln_sl.texture(4) == null, ln_b64[4].size() == 0,
		"下标 4 仍是**兜底件**（空表 + `texture` 返回 `null`）—— 新增机体必须往后追加")

	# ---- ② 访问器的边界（`null` 是**正常路径**，不是错误）----
	t.ok(ln_sl.texture(ln_kfb) == null, "`texture(兜底件)` 返回 `null`（没有线稿照样有外轮廓可描）")
	t.ok(ln_sl.texture(-1) == null, "`texture(-1)` 返回 `null`（不越界）")
	t.ok(ln_sl.texture(99) == null, "`texture(99)` 返回 `null`（以后加机体也不会崩）")
	for ln_i: int in ln_keys:
		var ln_tex: Texture2D = ln_sl.texture(ln_i)
		# 这一条就是"贴图没画上去"那次事故的闸门：`WH` 写错时它回落 `null`。
		t.ok(ln_tex != null, "`texture(%d)` 解出来了（屏上真的有这张线稿）" % ln_i)
		if ln_tex == null:
			continue
		t.eq(ln_tex.get_width(), int(ln_wh[ln_i][0]), "……第 %d 台宽 = `WH[%d][0]`" % [ln_i, ln_i])
		t.eq(ln_tex.get_height(), int(ln_wh[ln_i][1]), "……第 %d 台高 = `WH[%d][1]`" % [ln_i, ln_i])
		var ln_img: Image = ln_tex.get_image()
		t.eq(ln_img.get_format(), Image.FORMAT_RGBA8, "……第 %d 台是 RGBA8（线量在 A 通道）" % ln_i)

		# ---- ③ 4 bit 解包不变量 + 密度契约（两档配方各自的门）----
		#
		# ⚠️ 轮 32 那条「平均不透明度 < 0.28」**已撤**，见上面 `ln_density` 的注释：
		#   原图原样四台的均值 0.287 / 0.247 / 0.169 / 0.278 正好骑在 0.28 两侧
		#   ⇒ 它对四台有两种判定，红绿都读不出信息（而且 0.287 那台会**假红**）。
		#   换成的两条各自说得清：**密度契约**（跟烘图时报的数一致）+ **不是实心块**
		#   （整机铺一层底会顶到 0.35~0.47，轮 32 之前阿利宙斯常态就是 0.468）。
		var ln_n := ln_img.get_width() * ln_img.get_height()
		var ln_bad := 0
		var ln_nz := 0
		var ln_sum := 0.0
		for ln_y in ln_img.get_height():
			for ln_x in ln_img.get_width():
				var ln_a := int(round(ln_img.get_pixel(ln_x, ln_y).a * 255.0))
				if ln_a % 17 != 0:
					ln_bad += 1
				if ln_a > 0:
					ln_nz += 1
				ln_sum += float(ln_a)
		t.eq(ln_bad, 0,
			"第 %d 台 alpha 全是 17 的倍数（4 bit 量化的不变量；混进 8 bit 值就是解包写错了）"
				% ln_i)
		var ln_cov := float(ln_nz) / float(ln_n)
		t.between(ln_cov, 0.20, 0.70,
			"第 %d 台非零像素占 %.1f%% —— 两头顶住都不是线稿（全 0 = 空图，全 1 = 实心块）"
				% [ln_i, ln_cov * 100.0])
		var ln_amean := ln_sum / (255.0 * float(ln_n))
		var ln_want: float = float(ln_density[ln_i])
		t.near(ln_amean, ln_want, 0.02,
			("第 %d 台平均不透明度 %.3f ≈ 烘图时的 %.3f（±0.02）—— **密度契约**："
				+ "配方 / 阈值改了却没重报数，这里立刻红") % [ln_i, ln_amean, ln_want])
		t.lt(ln_amean, 0.40,
			("第 %d 台 %.3f < 0.40 —— 「不要那么剪影」的另一半：整机铺一层底会把它"
				+ "顶到 0.35~0.47（轮 32 之前阿利宙斯常态就是 0.468）") % [ln_i, ln_amean])

	# ---- ④ 贴图矩形 == 外轮廓点表的 bbox（差 ≤ 1 px）----
	#
	# 这是"线稿整体偏出壳体"的唯一判据：两张表来自同一个裁剪框，
	# 差一点就会看到线稿浮在轮廓外面。
	var ln_view := Vector2(1600.0, 900.0)
	var ln_rc := FlightHUD.radar_center(ln_view)
	var ln_rad: float = FlightHUD.RADAR_RADIUS
	for ln_i: int in ln_keys:
		var ln_bb := _bbox_of(FlightHUD.silhouette_parts(ln_rc, ln_rad, ln_i))
		var ln_lr := FlightHUD.silhouette_line_rect(ln_rc, ln_rad, ln_i)
		t.gt(ln_bb.size.x, 1.0,
			"第 %d 台外轮廓 bbox 非退化（空 bbox 会让下面四条全变成假绿）" % ln_i)
		t.near(ln_lr.position.x, ln_bb.position.x, 1.0,
			"第 %d 台左边对齐（贴图 %.2f vs 轮廓 %.2f）" % [ln_i, ln_lr.position.x, ln_bb.position.x])
		t.near(ln_lr.position.y, ln_bb.position.y, 1.0,
			"第 %d 台上边对齐（贴图 %.2f vs 轮廓 %.2f）" % [ln_i, ln_lr.position.y, ln_bb.position.y])
		t.near(ln_lr.end.x, ln_bb.end.x, 1.0,
			"第 %d 台右边对齐（贴图 %.2f vs 轮廓 %.2f）" % [ln_i, ln_lr.end.x, ln_bb.end.x])
		t.near(ln_lr.end.y, ln_bb.end.y, 1.0,
			"第 %d 台下边对齐（贴图 %.2f vs 轮廓 %.2f）" % [ln_i, ln_lr.end.y, ln_bb.end.y])
	t.eq(FlightHUD.silhouette_line_rect(ln_rc, ln_rad, ln_kfb), Rect2(),
		"兜底件返回**零矩形**（调用方不必再判一次）")

	# ---- ⑤ 三道绘制齐全，而且顺序是「淡底 → 线稿 → 外轮廓」----
	var ln_sil := _func_body(hud_src, "func _draw_screen_silhouette")
	t.gt(ln_sil.length(), 0, "读到 `_draw_screen_silhouette()` 本体")
	var ln_if := ln_sil.find("draw_colored_polygon")
	var ln_it := ln_sil.find("draw_texture_rect(tex, silhouette_line_rect")
	var ln_io := ln_sil.find("draw_polyline(_closed(p)")
	t.gt(ln_if, -1, "① 淡底那道在（`draw_colored_polygon`）")
	t.gt(ln_it, -1, "② 内部线稿那道在（`draw_texture_rect` + `silhouette_line_rect`）")
	t.gt(ln_io, -1, "③ 外轮廓那道在（`draw_polyline`）")
	t.lt(ln_if, ln_it, "顺序：淡底在线稿之下")
	t.lt(ln_it, ln_io, "顺序：线稿在外轮廓之下（最锐的那道留给描边，不被贴图糊掉）")
	t.ok(ln_sil.contains("if tex != null:"), "贴图调用有 `null` 守卫（兜底件不走这条路）")
	t.ok(ln_sil.contains("SilhLines.texture(key)"), "……取的是**当前机体**那一张，不是固定下标")
	t.ok(hud_src.contains("const SILH_FILL_A := 0.06"),
		"淡底 = 0.06（贴图自带明暗，全局那层只留一点点：亮背景上仍看得出机体在哪）")
	t.lt(0.06, 0.30, "……而且远小于轮 32 之前那个 0.30 的实心块")

	# ---- ⑥ 两个坑的回归闸门 ----
	#
	# ⚠️ 坑 A：`class_name` 的全局类名要等编辑器 import 才进
	#   `.godot/global_script_class_cache.cfg`，而写/跑这套流水线全程**不开编辑器**
	#   ⇒ 无头跑直接 `Parse Error: Identifier "SilhLines" not declared in the current scope`。
	# ⚠️ 坑 B：`WH` 多套一层方括号 —— 脚本照样加载，只是每次取贴图都报
	#   `Nonexistent 'int' constructor` + index 越界，屏上"什么都没有"。
	t.ok(ln_src.find("\nclass_name") < 0 and not ln_src.begins_with("class_name"),
		"`silh_lines.gd` **不许**出现 `class_name` 声明（无头下拿不到全局类名）")
	t.ok(ln_src.begins_with("extends RefCounted"), "……文件第一行就是 `extends RefCounted`")
	t.ok(hud_src.contains('const SilhLines := preload("res://scripts/ui/silh_lines.gd")'),
		"`hud.gd` 走 `preload`（与 `TutorialDirectorScript` 同一条路）")
	t.ok(ln_src.contains("const WH: Array = [["), "`WH` 字面量恰好一层方括号")
	t.ok(ln_src.find("const WH: Array = [[[") < 0, "……没有多套一层（那次事故的形状）")
	t.eq(ln_src.count("const B64: Array = ["), 1,
		"`B64` 的声明在场且只有一处（曾被一次改注释顺手删掉，症状是取贴图时 index 越界）")


	# ============================================================ ⑩ 第三人称锁中央屏（轮 35）
	#
	# ⚠️ 本节**必须挂在最末**：`t.suite()` 结算的是它之前累积的断言（同 ⑨ 的理由）。
	#
	# 需求原文：「第三人称模式下按 m 不能切换除了雷达以外的」。
	# 拆成**两件各自可断言的事**，因为它们失败的方式完全不同：
	#   ① **按键无效** —— `main.gd` 的入口加 `Settings.first_person` 门；
	#   ② **屏上恒为雷达** —— HUD 画的是 `Settings.effective_dash_screen()`，
	#      而不是玩家在座舱里选的那一档。
	# 只做 ① 会剩下"第三人称下档位还是剪影"（换个入口/重进战斗就会露出来）；
	# 只做 ② 会剩下"按 M 还在偷偷改偏好"（回座舱时档位已经不是玩家选的那个了）。
	t.suite("FPV / 第三人称锁中央屏：M 失效 + 屏恒雷达（轮 35）")

	# ---- ① 显示档 vs 偏好档：函数在场、只读不写 ----
	var tp_set := _func_body(ssrc, "func effective_dash_screen() -> int:")
	t.gt(tp_set.length(), 0, "`settings.gd` 有 `effective_dash_screen()`（显示档的**唯一**来源）")
	t.ok(tp_set.contains("first_person"), "……判据就是 `first_person`")
	t.ok(tp_set.contains("DASH_SCREEN_RADAR"),
		"……第三人称落回 `DASH_SCREEN_RADAR`（常量，不是字面量 0 —— 下标只有一份真源）")
	t.ok(tp_set.contains("dash_screen_mode"),
		"……座舱里读的是玩家的偏好档")
	t.not_ok(tp_set.contains("dash_screen_mode ="),
		"……而且**只读不写**：它不是「偷偷把玩家的档改掉」，回座舱要原样回来")

	# ---- ② 行为：三档 × 两种视角 ----
	# ⚠️ 这两件事**必须分开存**：合成一个变量的话，"第三人称被强制雷达"就会把偏好也抹掉，
	# 回座舱就回不来了 —— 而机主要的正是"回到第一人称时恢复上次切到的档位"。
	var tp_mode_was: int = Settings.dash_screen_mode
	var tp_fpv_was: bool = Settings.first_person
	var tp_seen := 0
	var tp_total := Settings.DASH_SCREEN_COUNT * 2
	for tp_m in Settings.DASH_SCREEN_COUNT:
		Settings.set_dash_screen_mode(tp_m)
		Settings.set_first_person(true)
		if Settings.effective_dash_screen() == tp_m:
			tp_seen += 1
		Settings.set_first_person(false)
		if Settings.effective_dash_screen() == Settings.DASH_SCREEN_RADAR:
			tp_seen += 1
	t.eq(tp_seen, tp_total,
		"座舱里 %d 档都原样透出；第三人称下**每一档**都落回雷达（%d/%d）"
			% [Settings.DASH_SCREEN_COUNT, tp_seen, tp_total])
	t.eq(Settings.dash_screen_mode, Settings.DASH_SCREEN_COUNT - 1,
		"上面那一圈跑完，**偏好档**停在最后一档（说明显示没有反过来改状态）")

	# 最小往返：第三人称 → 回座舱，档位必须自己回来
	Settings.set_first_person(false)
	Settings.set_dash_screen_mode(Settings.DASH_SCREEN_SILHOUETTE)
	t.eq(Settings.dash_screen_mode, Settings.DASH_SCREEN_SILHOUETTE,
		"第三人称下**档位字段**仍是玩家选的那一档（显示被覆盖 ≠ 状态被改）")
	t.eq(Settings.effective_dash_screen(), Settings.DASH_SCREEN_RADAR,
		"……而这块屏这时画的是**雷达**")
	Settings.set_first_person(true)
	t.eq(Settings.effective_dash_screen(), Settings.DASH_SCREEN_SILHOUETTE,
		"回座舱 ⇒ 剪影**原样回来**（不许把偏好改掉，意义就在这一条）")

	# 默认值也要对：出厂 `first_person = false` ⇒ 屏上本来就该是雷达
	t.ok(ssrc.contains("var first_person := false"),
		"出厂 `first_person = false`（与 `dash_screen_mode` 的默认雷达同向，不打架）")

	# ---- ③ 按键那条路：门开在**入口** ----
	var tp_g := _func_body(main_src, "func _handle_global_input")
	t.ok(tp_g.contains(
			'if Settings.first_person and Input.is_action_just_pressed("cycle_dash_screen"):'),
		"M 键那条 `if` 上带 `Settings.first_person` 门（第三人称按 M 毫无反应）")
	t.not_ok(tp_g.contains('\n\tif Input.is_action_just_pressed("cycle_dash_screen"):'),
		"……而且没有第二条**没带门**的同款 `if`（两条并存 = 第三人称照样能切）")
	t.eq(tp_g.count("cycle_dash_screen"), 2,
		"`_handle_global_input()` 里 `cycle_dash_screen` 恰好 2 次（一次判键、一次调实现）")
	var tp_f1 := tp_g.find('if Input.is_action_just_pressed("toggle_fpv"):')
	var tp_mi := tp_g.find('"cycle_dash_screen"')
	t.gt(float(tp_mi), float(tp_f1),
		"M 仍在 F1 那条分支**之后**（两条路各管各的，没被新门挤进对方体内）")
	t.ok(tp_g.contains("Settings.cycle_dash_screen()"),
		"……而且仍然只调那个唯一实现")

	# ---- ④ 绘制那条路：HUD 读的是显示档 ----
	var tp_rbody := _func_body(hud_src, "func _draw_radar")
	t.ok(tp_rbody.contains("var mode: int = Settings.effective_dash_screen()"),
		"`_draw_radar()` 取的是 `effective_dash_screen()`（显示档）")
	t.not_ok(tp_rbody.contains("Settings.dash_screen_mode"),
		"……而且**不再**直接读 `dash_screen_mode`：读它第三人称下就会切成剪影 / 等高线")
	t.ok(tp_rbody.contains("draw_circle(center, radius"),
		"……三种模式共用的底盘仍在（换的是内容，不是屏幕本身）")
	# 分派用的是**常量**，所以「切到哪一档」这件事仍然只有一份真源
	t.ok(tp_rbody.contains("Settings.DASH_SCREEN_SILHOUETTE")
			and tp_rbody.contains("Settings.DASH_SCREEN_CONTOUR"),
		"……分派仍按 `DASH_SCREEN_*` 常量（不是字面量 1 / 2）")

	Settings.set_first_person(tp_fpv_was)
	Settings.set_dash_screen_mode(tp_mode_was)
	t.eq(Settings.first_person, tp_fpv_was,
		"本节跑完把 `first_person` 还原（不替玩家打开最晕的模式）")
	t.eq(Settings.dash_screen_mode, tp_mode_was, "……中央屏档位也还原")
