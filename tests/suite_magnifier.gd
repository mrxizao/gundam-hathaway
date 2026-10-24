class_name SuiteMagnifier
extends RefCounted
## ★63-10 · D3b「放大镜」：在屏幕空白处显示对方机体的近景。
##
## ## 用户原话
## 「……在屏幕的空白处有放大镜效果（在对方机体 0.4 km 处设置相机，来显示对方）……」
##
## ✂︎ D3a（辅助瞄准 + 提示圈 + 吸附提醒）在轮 63-9 已落地；本套件管的是 **D3b**：
## 它要给全场景**再加一次渲染**，是本工程风险最高的那一类改动，所以单独一轮、单独一套判据。
##
## ## 四段判据
##   ① 「屏幕的空白处」是**算出来的**：矩形与「附近敌机列表」「高度带」都不相交，
##      且换分辨率仍然成立（写死坐标的话，换分辨率 / 名单多一行就过期）；
##   ② **底座**：全工程唯一一个 `SubViewport`，且它的 `world_3d` **就是主视口那一份**；
##      默认 `UPDATE_DISABLED`（不显示时零渲染）；
##   ③ **机位**：相机与目标机距离 ∈ [0.39, 0.41] km、朝向夹角 ≤ 5°；
##   ④ **开关**：四条门逐条 + 不显示时把更新档写回 `UPDATE_DISABLED` + 推帧节流。
##
## ## 负对照（三条，括号里是**实测**红条数；一字不差地落在下面这几条上）
##   `nc_no_world3d`   删掉 `_mag_vp.world_3d = ...` 那一句 ⇒ 红 ② **3 条**
##                     （`world_3d` 非空 / 就是主视口那一份 / 源码里恰好 1 处）
##                     ⚠️ 它钉的是「**产品不再显式接主世界**」这件事本身，**不是**「镜里会黑」：
##                     真机实测（`nc_noworld`）摘掉它之后镜面结构照旧（标准差 31.86 对 31.61）
##                     ⇒ 引擎默认就继承父视口世界 ⇒ 这一句是显式化、防回退。
##   `nc_always`       不显示时不写回 `UPDATE_DISABLED`（改成 `UPDATE_ALWAYS`）
##                     ⇒ 红 ④ **1 条**（实测 `got=4` = `UPDATE_WHEN_VISIBLE` ⇒ 每帧白渲染）
##   `nc_every_frame`  把 `MAG_PUSH_EVERY` 改成 1 ⇒ 红 ① 1 条 + ④ **2 条**
##                     （间隔越界 / 3 次 tick 推了 3 次 / 末拍不在 `DISABLED`）
##   ⚠️ 三次回滚后 `hud.gd` 与金标 `16d6304d82cc91abbc736a225a1d9a9f` **逐位一致**。
##
## ⚠️ 本套件**不画像素**（`_draw()` 要真实渲染、`--headless` 截不出像素）：
## `world_3d` 那一条直接用**运行时对象**断言，而不是去数源码里的字符串 ——
## 后者对「把代码注释掉但字还留着」这种假修免疫不了。

const HUD_SRC := "res://scripts/ui/hud.gd"

## 两种真实尺寸：逻辑画布（Control 的坐标就是它）与真机。
const VIEW_CANVAS := Vector2(1600, 1000)
const VIEW_MACHINE := Vector2(2560, 1600)

## 目标机放在自机正前方 4 km。
const FOE_DIST := 4000.0


static func run(t: T, host: Node) -> void:
	t.suite("Magnifier / ① 空白处是算出来的：与敌机列表、高度带都不相交（D3b）")
	_rect(t)
	t.suite("Magnifier / ② 底座：唯一的 SubViewport 接的是主世界那一份 World3D（D3b）")
	await _build(t, host)
	t.suite("Magnifier / ③ 机位：相机在目标机前方 0.4 km、朝向夹角 ≤ 5°（D3b）")
	await _live(t, host)
	t.suite("Magnifier / ④ 开关：四条门 + 不显示时零渲染 + 推帧节流（D3b）")
	await _gate(t, host)
	t.suite("Magnifier / overlap fade timing, screen geometry and reset")
	await _fade(t, host)


# ================================================================ ① 位置

## 「屏幕的空白处」= 右侧那两块（敌机列表、高度带）之外，且含屏幕中心的那一块不算数。
##
## ⚠️ 这一段的判据**一个写死的坐标都没有**：全部与 `corner_layout()` / `alt_tape_rect()`
## 这两处真源相减。写死坐标的版本换分辨率必过期，而那属于"改了没人发现"的一类。
static func _rect(t: T) -> void:
	t.eq(FlightHUD.MAG_CAM_DIST, 400.0, "相机距离 0.4 km 是常量（用户原话的 0.4 km）")
	t.ok(FlightHUD.MAG_PUSH_EVERY == 2,
		"推帧间隔 %d 对应60 Hz下30 Hz刷新" % FlightHUD.MAG_PUSH_EVERY)
	t.near(FlightHUD.MAG_CAM_FOV, 6.0, 0.001, "放大镜相机 fov = 6.0（长焦，不是主相机那个 68）")
	t.gt(FlightHUD.MAG_CAM_FOV * 2.0, 0.0, "前置：fov 为正")
	var half_h: float = FlightHUD.MAG_CAM_DIST * tan(deg_to_rad(FlightHUD.MAG_CAM_FOV * 0.5))
	t.near(half_h * 2.0, 41.9, 0.5,
		"★ 0.4 km 处的画面高 = 2·400·tan(3°) = %.1f m ⇒ 一台 20 m 机体约占一半（这就是「放大」）"
			% (half_h * 2.0))

	for view: Vector2 in [VIEW_CANVAS, VIEW_MACHINE]:
		var r := FlightHUD.magnifier_rect(view)
		t.eq(r.size, Vector2(FlightHUD.MAG_SIZE),
			"%.0fx%.0f：矩形尺寸 = MAG_SIZE（%s）" % [view.x, view.y, str(r.size)])
		t.gt(r.position.x, 0.0, "%.0fx%.0f：左边界在屏幕内" % [view.x, view.y])
		t.gt(r.position.y, 0.0, "%.0fx%.0f：上边界在屏幕内" % [view.x, view.y])
		t.lt(r.end.x, view.x, "%.0fx%.0f：右边界在屏幕内" % [view.x, view.y])
		t.lt(r.end.y, view.y, "%.0fx%.0f：下边界在屏幕内" % [view.x, view.y])

		# ---- 让开「附近敌机列表」（右上角）----
		var g := FlightHUD.corner_layout(view)
		var rows := 1 + PlayerController.CONTACT_KEYS.size() + 1
		var list_bottom: float = float(g["top"]) + rows * FlightHUD.CONTACT_ROW_STEP
		t.gt(r.position.y, list_bottom,
			"★ %.0fx%.0f：矩形在敌机列表**下方**（%.1f > %.1f）" % [view.x, view.y, r.position.y, list_bottom])

		# ---- 让开「高度带」（紧贴右缘）----
		var tape := UILayout.alt_tape_rect(view)
		t.lt(r.end.x, tape.position.x,
			"★ %.0fx%.0f：矩形右端在高度带**左侧**（%.1f < %.1f）" % [view.x, view.y, r.end.x, tape.position.x])

		# ---- 不含屏幕中心：准星与锁定环都在那儿 ----
		t.ok(not r.has_point(view * 0.5),
			"★ %.0fx%.0f：矩形不含屏幕中心（准星 / 锁定环在主现场）" % [view.x, view.y])



# ================================================================ ② 底座

static func _build(t: T, host: Node) -> void:
	var stage := _make_stage(host, "MagBuild")
	var hud := stage["hud"] as FlightHUD
	hud._build_magnifier()

	var sv: SubViewport = null
	var cams := 0
	for ch in hud.get_children():
		if ch is SubViewport:
			sv = ch
			for g in ch.get_children():
				if g is Camera3D:
					cams += 1
	t.ok(sv != null, "★ HUD 底下有一个 SubViewport")
	t.eq(cams, 1, "★ 它底下**恰好**一台 Camera3D（多一台 = 多一份渲染）")
	if sv == null:
		stage["stage"].free()
		await host.get_tree().process_frame
		return

	# ---- 幂等：重复调用不会再建一个 ----
	var before := hud.get_child_count()
	hud._build_magnifier()
	t.eq(hud.get_child_count(), before, "★ `_build_magnifier()` 幂等（重复调用不新增节点）")

	# ---- ⚠️ 这一条是整套件最贵的一条 ----
	t.ok(sv.world_3d != null,
		"★ 镜里的 world_3d **非空**（显式接主世界 —— 不写其实也能看见东西，引擎会继承）")
	t.ok(sv.world_3d == hud.get_viewport().world_3d,
		"★ 而且**就是主视口那一份**（同一个 World3D 对象 —— 这里钉的是显式同源）")

	t.eq(sv.size, FlightHUD.MAG_SIZE, "SubViewport 尺寸 = MAG_SIZE")
	t.eq(sv.render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"★ 默认**关着**：不显示时一次都不渲染（`UPDATE_WHEN_VISIBLE` 会让它每帧都渲染）")
	var cam: Camera3D = null
	for g in sv.get_children():
		if g is Camera3D:
			cam = g
	t.ok(cam != null, "拿到了放大镜相机")
	if cam != null:
		t.near(cam.fov, FlightHUD.MAG_CAM_FOV, 0.001, "相机 fov = MAG_CAM_FOV")
		t.gt(cam.far, 10000.0, "相机 far = %.0f（目标可能远在几十 km 外，不能用主相机那个值）" % cam.far)

	# ---- 源码级：那一句真源只写了一次（写在注释里不算修）----
	var src := SuiteUiStyle._code(HUD_SRC)
	t.eq(src.count("_mag_vp.world_3d = get_viewport().world_3d"), 1,
		"★ `world_3d` 的赋值在 hud.gd 恰好 1 处（有且只有一处真源）")

	stage["stage"].free()
	await host.get_tree().process_frame
	Game.reset()


# ================================================================ ③ 机位

static func _live(t: T, host: Node) -> void:
	var stage := _make_stage(host, "MagLive")
	var hud := stage["hud"] as FlightHUD
	var pc: PlayerController = stage["pc"]
	var foe: FlightBody = stage["foe"]

	hud._build_magnifier()
	hud._aim_magnifier_at(foe)

	var cam: Camera3D = hud._mag_cam
	var d := cam.global_position.distance_to(foe.global_position)
	t.near(d, 400.0, 10.0,
		"★ 相机与目标机距离 = %.3f m（判据 ∈ [390, 410] m ⇒ 0.39~0.41 km）" % d)
	t.near(d, FlightHUD.MAG_CAM_DIST, 0.001, "★ 而且等于常量 `MAG_CAM_DIST` 本身（不是另一个 400）")

	# 朝向：相机的前向（-Z）与「相机 → 目标」的夹角
	var look := cam.global_position.direction_to(foe.global_position)
	var fwd := -cam.global_transform.basis.z
	var ang := rad_to_deg(look.angle_to(fwd))
	t.lt(ang, 5.0, "★ 相机朝向与「相机→目标」夹角 = %.4f°（判据 ≤ 5°）" % ang)

	# 相机必须落在**朝自机那一侧**（不然是从目标背后拍）
	var to_eye := foe.global_position.direction_to(pc.global_position)
	var to_cam := foe.global_position.direction_to(cam.global_position)
	t.gt(to_eye.dot(to_cam), 0.999,
		"★ 相机在目标机**朝自机那一侧**（dot = %.6f；从背后拍的话是 −1）" % to_eye.dot(to_cam))
	print("        [真机读数] 相机距目标 %.3f m｜朝向夹角 %.4f°｜轴向 dot %.6f" % [d, ang, to_eye.dot(to_cam)])

	# ---- 目标在头顶正上方：`look_at` 的 up 退化分支必须接住（否则报错并保持原朝向）----
	foe.global_position = pc.global_position + Vector3.UP * FOE_DIST
	hud._aim_magnifier_at(foe)
	var d2 := cam.global_position.distance_to(foe.global_position)
	t.near(d2, FlightHUD.MAG_CAM_DIST, 0.5,
		"★ 目标在正上方时仍摆到 0.4 km（`look_at` 的 up 退化被兜底接住，距离 %.3f）" % d2)
	var look2 := cam.global_position.direction_to(foe.global_position)
	var ang2 := rad_to_deg(look2.angle_to(-cam.global_transform.basis.z))
	t.lt(ang2, 5.0, "★ 且朝向仍然对准（夹角 %.4f°）" % ang2)

	stage["stage"].free()
	await host.get_tree().process_frame
	Game.reset()


# ================================================================ ④ 开关

static func _gate(t: T, host: Node) -> void:
	var stage := _make_stage(host, "MagGate")
	var hud := stage["hud"] as FlightHUD
	var pc: PlayerController = stage["pc"]
	var foe: FlightBody = stage["foe"]

	t.ok(hud.magnifier_active(), "★ 全条件满足 ⇒ 开")

	pc.rifle_count = 0
	t.not_ok(hud.magnifier_active(), "★ 没有光束步枪 ⇒ 关")
	pc.rifle_count = SuitProfile.xi().rifle_count

	pc.assist_on = false
	t.not_ok(hud.magnifier_active(), "★ 辅助驾驶关 ⇒ 关（与 D3a **同一个** `aim_assist_enabled()`）")
	pc.assist_on = true
	t.ok(hud.magnifier_active(), "★ 辅助驾驶开 ⇒ 开（用户原话「辅助驾驶模式下自动开启」）")

	pc.lock.target = null
	t.not_ok(hud.magnifier_active(), "★ 没有锁定对象 ⇒ 关（「对方机体」）")
	pc.lock.target = foe
	t.ok(hud.magnifier_active(), "★ 锁上 ⇒ 开")

	hud.cockpit_only = true
	t.not_ok(hud.magnifier_active(), "★ 发射段（`cockpit_only`）⇒ 关（那时 `player` 是 null）")
	hud.cockpit_only = false

	hud.visible = false
	t.not_ok(hud.magnifier_active(), "★ HUD 本身不可见 ⇒ 关")
	hud.visible = true

	# ---- 不该显示时：更新档必须写回 DISABLED ----
	pc.assist_on = false
	hud._mag_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	hud._tick_magnifier()
	t.eq(hud._mag_vp.render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"★ 不该显示时 `_tick_magnifier()` 把更新档写回 `UPDATE_DISABLED`"
			+ "（否则它一直「可见」，默认档会每帧渲染一次全场景 = 性能判据当场红）")

	# ---- 推帧节流：每 MAG_PUSH_EVERY 帧才推一次 ----
	pc.assist_on = true
	hud._mag_frame = 0
	var pushed := 0
	# ⚠️ `+ 1` 是**必须**的：取整数倍的话，最后一拍恰好落在推帧上，
	# 于是下面那条「不推时留在 DISABLED」永远看不到 DISABLED（第一版就是这么红的）。
	var ticks: int = FlightHUD.MAG_PUSH_EVERY * 2 + 1
	for i in ticks:
		hud._mag_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		hud._tick_magnifier()
		if hud._mag_vp.render_target_update_mode == SubViewport.UPDATE_ONCE:
			pushed += 1
	t.eq(pushed, 2,
		"★ %d 次 tick 只推 2 次（`MAG_PUSH_EVERY` = %d ⇒ 多推 = 白付一次全场景渲染）"
			% [ticks, FlightHUD.MAG_PUSH_EVERY])
	t.eq(hud._mag_vp.render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"★ 而第 %d 次不是推帧那一拍 ⇒ tick 完留在 DISABLED（不多渲染一帧）" % ticks)

	# ---- 重新开启后计数复位 ----
	pc.assist_on = false
	hud._mag_frame = 7
	hud._tick_magnifier()
	t.eq(hud._mag_frame, 0, "★ 关掉时推帧计数复位（再开时不会「接着上次的相位」）")

	pc.assist_on = true
	pc.lock.target = null
	hud._mag_frame = 7
	hud._tick_magnifier()
	t.eq(hud._mag_frame, 0, "★ 丢锁也一样复位")

	stage["stage"].free()
	await host.get_tree().process_frame
	Game.reset()


# ================================================================ 工具

## 搭一套真机对象：自机（`PlayerController`）+ 目标（`FlightBody`）+ HUD，全都进树。
##
## ⚠️ 三个都必须 `add_child` 进树：`FlightBody` 在树外构造不会拿到 `fm`，
## 而 `_aim_magnifier_at()` 要读 `player.global_position`、`magnifier_active()` 要读
## `is_inside_tree()`。
static func _make_stage(host: Node, tag: String) -> Dictionary:
	Game.reset()
	var stage := Node3D.new()
	stage.name = "%sStage" % tag
	host.add_child(stage)

	var pc := PlayerController.new()
	pc.name = "%sProbe" % tag
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.projectile_container = stage
	stage.add_child(pc)
	pc.global_position = Vector3(0, 900, 0)
	pc.controls_enabled = false
	pc.assist_on = true
	# ⚠️ `pc.lock` 平时由 `main` 注入（`main.gd` 里 `player_lock = LockOnSystem.new()`），
	# **测试这条路上没有人给** —— 少了它，`pc.lock.target = foe` 会打在 `Nil` 上：
	# 报一条 SCRIPT ERROR，而套件照样显示「0 FAIL」（断言全被异常跳过）⇒ 假绿。
	# 写成「只在 null 时建」而不是无条件覆盖：将来真机路径上它已经有一个了。
	if pc.lock == null:
		var lk := LockOnSystem.new()
		lk.name = "%sLockOn" % tag
		stage.add_child(lk)
		lk.setup(pc)
		pc.lock = lk

	var foe := FlightBody.new()
	foe.name = "%sFoe" % tag
	foe.team = 1
	foe.profile = SuitProfile.xi()
	foe.projectile_container = stage
	stage.add_child(foe)
	foe.global_position = pc.global_position + Vector3.FORWARD * FOE_DIST

	var hud := FlightHUD.new()
	hud.name = "%sHUD" % tag
	stage.add_child(hud)
	hud.player = pc
	hud.lock = pc.lock

	# 目标挂上锁定（走属性赋值 = 「强制换锁定对象」，正是这里要的语义）。
	pc.lock.target = foe

	return {"stage": stage, "pc": pc, "foe": foe, "hud": hud}

static func _fade(t: T, host: Node) -> void:
	for hz in [30, 60, 144]:
		var opacity := 1.0
		for frame in hz / 2:
			opacity = FlightHUD.magnifier_opacity_step(opacity, true, 1.0 / hz)
		t.near(opacity, 0.05, 0.0001, "%d Hz reaches 5 percent in 0.5 seconds" % hz)
		opacity = FlightHUD.magnifier_opacity_step(opacity, true, 10.0)
		t.near(opacity, 0.05, 0.0001, "persistent overlap holds minimum")
		for frame in hz / 2:
			opacity = FlightHUD.magnifier_opacity_step(opacity, false, 1.0 / hz)
		t.near(opacity, 0.525, 0.0001, "halfway through recovery at 0.5 seconds")
		for frame in hz / 2:
			opacity = FlightHUD.magnifier_opacity_step(opacity, false, 1.0 / hz)
		t.near(opacity, 1.0, 0.0001, "fully recovered at 1 second")
	var halfway := FlightHUD.magnifier_opacity_step(1.0, true, 0.25)
	t.near(halfway, 0.525, 0.0001, "fade reaches halfway after 0.25 seconds")
	t.near(FlightHUD.magnifier_opacity_step(halfway, false, 0), halfway, 0.0001, "reversal is continuous")
	t.near(FlightHUD.magnifier_opacity_step(halfway, false, 0.1), 0.62, 0.0001, "early exit recovers from current opacity")
	t.near(FlightHUD.magnifier_opacity_step(0.62, true, 0.1), 0.43, 0.0001, "re-entry fades from current opacity")
	for view: Vector2 in [Vector2(1600,900), Vector2(2560,1600), Vector2(1280,720), Vector2(1280,960), Vector2(3440,1440)]:
		var g := FlightHUD.ThirdPersonHUD.layout(view)
		var scale_factor: float = g["scale"]
		var rect := FlightHUD.ThirdPersonHUD.magnifier_rect(view)
		t.near(rect.size.x / scale_factor, 204.0, 0.001, "panel width reduced by 15 percent")
		t.near(rect.size.y / scale_factor, 114.75, 0.001, "panel height reduced by 15 percent")
		t.ok(Rect2(Vector2.ZERO,view).encloses(rect), "panel fits viewport")
		var alt: Rect2 = g["alt"]
		t.ok(not rect.intersects(Rect2(alt.position * scale_factor, alt.size * scale_factor)), "panel avoids altitude instrument")
		t.near(rect.position.x / scale_factor, 72.0, 0.001, "panel aligns with assist text")
		t.ok(rect.position.y / scale_factor >= 106.0, "panel title clears assist and event lines")
		var speed: Rect2 = g["speed"]
		t.ok(not rect.intersects(Rect2(speed.position * scale_factor, speed.size * scale_factor)), "panel avoids speed instrument")
	var stage := _make_stage(host, "MagFade")
	var hud: FlightHUD = stage["hud"]
	var pc: PlayerController = stage["pc"]
	var foe: FlightBody = stage["foe"]
	hud.set_process(false)
	pc.set_physics_process(false)
	foe.set_physics_process(false)
	var cam := ChaseCamera.new()
	stage["stage"].add_child(cam)
	cam.set_process(false)
	cam.set_physics_process(false)
	cam.global_position = pc.global_position + Vector3(0,0,200)
	hud.camera = cam
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1600,900)
	var saved: bool = Settings.first_person
	Settings.first_person = false
	hud._begin_magnifier_ui()
	var panel := FlightHUD.ThirdPersonHUD.magnifier_rect(hud.size)
	var away := Vector2(-100,-100)
	t.ok(hud.magnifier_blocked(panel.get_center()), "mouse inside panel triggers fade")
	t.not_ok(hud.magnifier_blocked(away), "clear panel remains opaque")
	# Partially intersecting UI counts even with its center outside the panel.
	hud._magnifier_ui_rect(Rect2(panel.position - Vector2(25,0),Vector2(30,15)))
	t.ok(hud.magnifier_blocked(away), "partial UI overlap triggers fade")
	hud._begin_magnifier_ui()
	hud._magnifier_ui_rect(Rect2(Vector2(20,20),Vector2(20,20)))
	t.not_ok(hud.magnifier_blocked(away), "unrelated UI stays clear")
	hud._mag_collecting = false
	hud._magnifier_ui_rect(panel)
	t.not_ok(hud.magnifier_blocked(away), "magnifier drawing cannot trigger itself")
	foe.global_position = cam.project_position(panel.get_center(),2000)
	t.ok(hud._magnifier_enemy_rect(foe).intersects(panel), "enemy model projects into panel")
	t.ok(hud.magnifier_blocked(away), "enemy alone triggers overlap without mouse or UI")
	foe.global_position = cam.project_position(Vector2(panel.position.x - 1,panel.get_center().y),2000)
	t.not_ok(panel.has_point(hud._project(foe.global_position)), "enemy center is outside panel")
	t.ok(hud.magnifier_blocked(away), "part of enemy model entering panel is enough")
	foe.global_position = cam.global_position + Vector3(0,0,2000)
	t.not_ok(hud.magnifier_blocked(away), "enemy behind camera does not trigger fade")
	hud._mag_opacity = 0.05
	pc.assist_on = false
	hud._tick_magnifier_fade(0.1)
	t.near(hud._mag_opacity,1.0,0.0001,"inactive panel clears stale transparency")
	pc.assist_on = true
	Settings.first_person = true
	hud._mag_opacity = 0.05
	hud._tick_magnifier_fade(0.1)
	t.near(hud._mag_opacity,1.0,0.0001,"first-person opacity remains unchanged")
	Settings.first_person = saved
	stage["stage"].free()
	await host.get_tree().process_frame
	Game.reset()
