class_name SuiteInput
extends RefCounted
## 输入映射测试。
##
## 这一套防的是"最容易静默坏掉"的东西：键位没绑上、绑反了、或者 action 名改了
## 但调用处没跟着改。这类问题不会报错 —— 只是玩的时候发现"按左键不开枪"。

## action -> 应当能点亮它的键
const KEY_PROBES := {
	"pitch_nose_up": KEY_S,
	"pitch_nose_down": KEY_W,
	"roll_left": KEY_A,
	"roll_right": KEY_D,
	"yaw_left": KEY_Q,
	"yaw_right": KEY_E,
	"throttle_up": KEY_BRACKETRIGHT,
	"throttle_down": KEY_BRACKETLEFT,
	"boost": KEY_SHIFT,
	"hover": KEY_CTRL,
	"fire_gun": KEY_SPACE,
	"fire_missile": KEY_F,
	"shield": KEY_T,
	"reload": KEY_R,
		# 1.2：G 从"丢弃步枪"改成**辅助飞行**（用户指定）；丢枪不再是一个 InputMap 动作
	# （它由"长按 R / 长按 B"的代码路径直接调函数），所以它已进 RETIRED_ACTIONS。
	"flight_assist": KEY_G,
	"switch_target": KEY_TAB,
	# 第十六轮：数字键 1 – 9 直选右上角敌机列表里的第 n 架（用户指定，第二轮明确"不止 123"）
	"select_contact_1": KEY_1,
	"select_contact_2": KEY_2,
	"select_contact_3": KEY_3,
	"select_contact_4": KEY_4,
	"select_contact_5": KEY_5,
	"select_contact_6": KEY_6,
	"select_contact_7": KEY_7,
	"select_contact_8": KEY_8,
	"select_contact_9": KEY_9,
	"flares": KEY_C,
	"look_back": KEY_V,
	"toggle_invert": KEY_I,
	# 1.1 新增：锁定镜头（Alt，用户点名）与变形（Z）
	"missile_mode": KEY_ALT,
	"transform": KEY_Z,
	"open_settings": KEY_P,
	"confirm": KEY_ENTER,
	"menu_back": KEY_ESCAPE,
}

## action -> 应当能点亮它的鼠标键
const MOUSE_PROBES := {
	"fire_primary": MOUSE_BUTTON_LEFT,
	"fire_secondary": MOUSE_BUTTON_RIGHT,
	"throttle_up": MOUSE_BUTTON_WHEEL_UP,
	"throttle_down": MOUSE_BUTTON_WHEEL_DOWN,
}


static func run(t: T, host: Node) -> void:
	t.suite("Input / 键盘动作")
	for action: String in KEY_PROBES:
		t.ok(InputMap.has_action(action), "存在输入动作 %s" % action)
	for action: String in KEY_PROBES:
		var key: int = KEY_PROBES[action]
		await _key(host, key, true)
		t.ok(Input.is_action_pressed(action), "按下 %s 点亮 %s" % [OS.get_keycode_string(key), action])
		await _key(host, key, false)
		t.ok(not Input.is_action_pressed(action), "松开 %s 熄灭 %s" % [OS.get_keycode_string(key), action])

	t.suite("Input / 鼠标动作")
	for action: String in MOUSE_PROBES:
		var btn: int = MOUSE_PROBES[action]
		await _button(host, btn, true)
		t.ok(Input.is_action_pressed(action), "按下鼠标键 %d 点亮 %s" % [btn, action])
		await _button(host, btn, false)
		t.ok(not Input.is_action_pressed(action), "松开鼠标键 %d 熄灭 %s" % [btn, action])

	t.suite("Input / 键位方向")
	# 俯仰必须符合"推杆低头 / 拉杆抬头"的真实操纵杆约定，写反了操作全乱
	t.ok(InputSetup.BINDINGS["pitch_nose_up"].has(KEY_S), "拉杆(S) 绑定为机头抬起")
	t.ok(InputSetup.BINDINGS["pitch_nose_down"].has(KEY_W), "推杆(W) 绑定为机头下沉")
	# 加速与悬停必须分属两个键，否则"加速 + 悬停"无法同时表达
	t.ok(InputSetup.BINDINGS["boost"].has(KEY_SHIFT), "Shift = 加速")
	t.ok(InputSetup.BINDINGS["hover"].has(KEY_CTRL), "Ctrl = 悬停")
	# 第六轮指定的键位
	t.ok(InputSetup.BINDINGS["yaw_left"].has(KEY_Q), "Q = 左偏航")
	t.ok(InputSetup.BINDINGS["yaw_right"].has(KEY_E), "E = 右偏航")
	t.ok(InputSetup.BINDINGS["fire_missile"].has(KEY_F), "F = 发射浮游导弹")
	t.ok(InputSetup.BINDINGS["shield"].has(KEY_T), "T = 举盾")
	t.ok(InputSetup.BINDINGS["reload"].has(KEY_R), "R = 光束步枪换弹")
	t.ok(InputSetup.BINDINGS["fire_gun"].has(KEY_SPACE), "空格 = 火神炮")
	# T 让给举盾之后切换目标挪到了 Tab；不能没有归属，也不能和别的键撞
	t.ok(InputSetup.BINDINGS["switch_target"].has(KEY_TAB), "Tab = 切换目标")
	# 第十六轮（用户指定）：**数字键 1 – 9 = 直选右上角列表的第 n 架敌机**。
	# 这一组还顺带钉住"列表行数与键位数是同一份数据"——
	# `CONTACT_KEYS` 是唯一的真源，HUD 画几行带号也读它。
	t.suite("Input / 敌机列表数字键 = 列表槽位")
	var digits := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
	t.eq(PlayerController.CONTACT_KEYS.size(), 9,
		"敌机列表有 9 个编号槽位（用户明确「不止 123」；第 10 架起才走十字键 ↑ 循环）")
	t.eq(PlayerController.CONTACT_KEYS.size(), digits.size(),
		"槽位数与数字键个数一致（两边都得改才不会错位）")
	for i in PlayerController.CONTACT_KEYS.size():
		var act: String = PlayerController.CONTACT_KEYS[i]
		t.ok(InputSetup.BINDINGS.has(act), "第 %d 行（%s）有键位" % [i + 1, act])
		t.ok((InputSetup.BINDINGS.get(act, []) as Array).has(digits[i]),
			"%s 绑在数字键 %d 上（列表第 %d 行）" % [act, i + 1, i + 1])
		t.ok(InputMap.has_action(act), "%s 真的进了 InputMap" % act)
	# 0 键**故意不绑**：它没有对应的序号（第 10 架），绑上去只会变成"按了没反应"。
	t.not_ok(InputSetup.BINDINGS.has("select_contact_0"), "不绑 0 键（没有第 0 架）")
	# 手柄那一列留空是**故意的**：手柄没有数字键，等价入口是十字键 ↑ 循环。
	# 这一条防的是"随手把数字键也塞给手柄"，那会挤掉手柄上本来就满的功能键。
	for act: String in PlayerController.CONTACT_KEYS:
		t.eq((InputSetup.PAD_BINDINGS.get(act, []) as Array).size(), 0,
			"%s 不占手柄键位（手柄用十字键 ↑ 循环同一份名单）" % act)
	# 1.1：鼠标从"操纵机头"缩到"只负责锁定"，所以没有任何鼠标轴类动作挂到飞行上；
	# 新增的两个键也必须落在用户点名/约定的位置。
	t.ok(InputSetup.BINDINGS["missile_mode"].has(KEY_ALT), "Alt = 导弹系统模式切换（第十八轮；锁定镜头并进辅助飞行）")
	t.ok(InputSetup.BINDINGS["transform"].has(KEY_Z), "Z = 变形（阿利宙斯 巡航 ↔ 常态）")
	# 普通鼠标不控制机头；新增中键只用于有意按住的驾驶舱环视。
	for action: String in InputSetup.MOUSE_BINDINGS:
		t.ok(action in ["fire_primary", "fire_secondary", "throttle_up", "throttle_down", "cockpit_freelook"],
			"鼠标只有武器/油门/独立头部环视（%s），不操纵机头" % action)
	t.eq(InputSetup.MOUSE_BINDINGS["cockpit_freelook"], [MOUSE_BUTTON_MIDDLE], "中键按住环视；普通鼠标不转动视角")
	# 键位表必须覆盖到帮助面板里列出的每一个动作，否则说明会印出一个按不出来的键
	t.suite("Input / 帮助面板与键位一致")
	for sec: Dictionary in InputSetup.HELP_SECTIONS:
		for it: Array in sec["items"]:
			t.ok(InputSetup.help_text(it) != "" and str(it[1]) != "",
				"帮助条目完整：%s → %s" % [InputSetup.help_text(it), it[1]])
	var help_actions := 0
	for sec: Dictionary in InputSetup.HELP_SECTIONS:
		help_actions += (sec["items"] as Array).size()
	t.gt(help_actions, 15, "帮助面板列出的操作足够完整（%d 条）" % help_actions)

	# ---- 旧绑定残留检查 ----
	# 这一组是踩坑之后加的：project.godot 的 [input] 段是固化副本，
	# 改键位表时它不会自动更新。只"补缺"不"剪旧"的话，
	# 第三轮把飞弹从 F 挪到 Q 之后，F 会同时属于 fire_missile 和 shield ——
	# 玩家按 F 举盾，结果同时打出浮游导弹并弹"未锁定目标"。
	# 光靠人眼看键位表是抓不到这种问题的，必须让测试直接对着运行时 map 查。
	t.suite("Input / 不得有旧绑定残留")
	for action: String in InputSetup.all_actions():
		# 批 4（§4.8.10）：残留检查改查**权威表** bound_*() ——
		# 否则用户的自定义绑定会被当成"多余事件"误报。
		var allowed_keys: Array = InputSetup.bound_keys(action)
		var allowed_buttons: Array = InputSetup.bound_buttons(action)
		var allowed_pads: Array = InputSetup.PAD_BINDINGS.get(action, [])
		var allowed_axes: Array = InputSetup.PAD_AXIS_BINDINGS.get(action, [])
		for ev: InputEvent in InputMap.action_get_events(action):
			var k := ev as InputEventKey
			if k != null:
				t.ok(allowed_keys.has(k.physical_keycode),
					"%s 上没有多余键 %s" % [action, OS.get_keycode_string(k.physical_keycode)])
				continue
			var b := ev as InputEventMouseButton
			if b != null:
				t.ok(allowed_buttons.has(b.button_index),
					"%s 上没有多余鼠标键 %d" % [action, b.button_index])
				continue
			var jb := ev as InputEventJoypadButton
			if jb != null:
				t.ok(allowed_pads.has(jb.button_index),
					"%s 上没有多余手柄键 %d" % [action, jb.button_index])
				continue
			var jm := ev as InputEventJoypadMotion
			if jm != null:
				var ok := false
				for pair: Array in allowed_axes:
					if int(pair[0]) == jm.axis and absf(float(pair[1]) - jm.axis_value) < 0.01:
						ok = true
				t.ok(ok, "%s 上没有多余手柄轴 %d" % [action, jm.axis])

	for a: String in InputSetup.RETIRED_ACTIONS:
		t.not_ok(InputMap.has_action(a), "废弃动作 %s 已从 map 中移除" % a)

	# 一个键不能同时属于两个动作（ESC 那种刻意共用的除外）
	var seen := {}
	var dup_found := false
	for action: String in InputSetup.all_actions():
		for ev: InputEvent in InputMap.action_get_events(action):
			var k := ev as InputEventKey
			if k == null:
				continue
			var key: int = k.physical_keycode
			if seen.has(key) and seen[key] != action:
				if not _shared_ok(seen[key], action):
					dup_found = true
					t.ok(false, "键 %s 同时属于 %s 与 %s"
						% [OS.get_keycode_string(key), seen[key], action])
			seen[key] = action
	t.not_ok(dup_found, "没有任何按键被重复绑定到两个动作")

	# 手柄按键同理。手柄只有十几个键，"一键两用"比键盘更常见，
	# 所以刻意共用的那几对同样登记在 `SHARED_KEYS_OK` 里（阶段互斥，不会同时生效）；
	# 没登记却撞在一起的，就是真的绑错了。
	var pad_seen := {}
	var pad_dup := false
	for action: String in InputSetup.all_actions():
		for ev: InputEvent in InputMap.action_get_events(action):
			var jb := ev as InputEventJoypadButton
			if jb == null:
				continue
			var btn: int = jb.button_index
			if pad_seen.has(btn) and pad_seen[btn] != action:
				if not _shared_ok(str(pad_seen[btn]), action):
					pad_dup = true
					t.ok(false, "手柄键 %d 同时属于 %s 与 %s" % [btn, pad_seen[btn], action])
			pad_seen[btn] = action
	t.not_ok(pad_dup, "没有任何手柄按键被重复绑定到两个动作")

	t.suite("Input / 鼠标准星只管弹道，不影响视角")
	await _mouse_reticle(t, host)

	# ---- 轮 40 · **准星必须真的到武器** ----
	#
	# 上面那一节只验了 `aim_forward()` 这个纯函数，**从不经过武器真正用的
	# `FlightBody.aim_point()`** —— 而后者按「有没有目标」分两条路，其中
	# 「没有目标」那条读的是**机头** `forward()`。于是「没锁定时光束步枪 /
	# 火神炮完全不听准星」这个缺陷，可以在上面那一节全绿的情况下一直存在。
	# 详见 `_aim_reaches_weapon()` 的文件头注释。
	t.suite("Input / 准星必须真的到武器（没锁定也要跟）")
	await _aim_reaches_weapon(t, host)

	# ---- 轮 41 · **准星像素 ⇄ 弹道方向 同源** ----
	#
	# 轮 40 那一节钉的是**方向**（准星偏右 ⇒ 弹道偏右），它管不到**量**：
	# 偏 3° 和偏 25° 在它那里都是绿的。而用户报的恰恰是量 ——
	# 「向上发射光束步枪，为什么光束步枪的子弹还是会朝前？」。
	# 详见 `_cursor_ray_matches_aim()` 的文件头注释。
	t.suite("Input / 准星像素 ⇄ 弹道方向 同源（轮 41）")
	await _cursor_ray_matches_aim(t, host)


## 1.1 的核心约定：**鼠标决定打哪儿，但绝不决定往哪飞**。
##
## 用户先后给过两句话（"把鼠标调整视角删掉"+"射击方向跟随鼠标操控的准星"），
## 这一条把两句话的**交集**钉住：调 `_read_aim_input()` 之后
##   - `aim_forward()`（弹道方向）必须变；
##   - `control_input`（操纵量）必须**一个数都没动**。
## 只要这一条成立，"鼠标不影响视角"就不会在某次重构里被悄悄破坏。
static func _mouse_reticle(t: T, host: Node) -> void:
	var cam := Camera3D.new()
	cam.current = true
	host.add_child(cam)
	cam.global_position = Vector3(0, 0, 120)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	var pc := PlayerController.new()
	pc.team = 0
	pc.is_player = true
	pc.profile = SuitProfile.xi()
	host.add_child(pc)
	await host.get_tree().process_frame
	pc.controls_enabled = true
	pc.debug_input_enabled = true     # 不让键盘/摇杆掺进来
	pc.debug_input = Vector3.ZERO
	pc.debug_throttle = 0.8

	# 没有鼠标事件：弹道 = 机头
	t.ok(pc.aim_forward().is_equal_approx(pc.forward()),
		"没有鼠标事件时弹道就是机头方向（键鼠/手柄玩家不会突然打偏）")

	# 准星甩到屏幕右侧：弹道应偏向机体右侧，而操纵量必须纹丝不动
	var vs := host.get_viewport().get_visible_rect().size
	pc.cursor_seen = true
	pc.aim_cursor = Vector2(vs.x * 0.92, vs.y * 0.5)
	pc.call("_read_aim_input")
	t.gt(pc.aim_forward().dot(pc.right()), 0.1, "准星偏右 → 弹道也偏右（射击跟随准星）")
	t.ok(pc.control_input.is_equal_approx(Vector3.ZERO),
		"鼠标不产生任何操纵量（这就是「鼠标不影响视角」）")

	# 准星往左：弹道跟着往左
	pc.aim_cursor = Vector2(vs.x * 0.08, vs.y * 0.5)
	pc.call("_read_aim_input")
	t.lt(pc.aim_forward().dot(pc.right()), -0.1, "准星偏左 → 弹道偏左")
	t.ok(pc.control_input.is_equal_approx(Vector3.ZERO), "换到左边也一样不动操纵量")
	# 炮口收拢：两门炮的弹道交汇点更靠近机体中心（用户要求"往模型中心一点"）。
	#
	# ⚠️ 基准**不能**是"模型的半宽"：骨架（SuitRig）是从佩涅罗佩线稿定的，
	# 它的炮口间距和**具体模型**的宽度无关 —— 柯西换过朝向之后模型 X 向变窄，
	# 按半宽写的那条断言就无端红了（而炮口一点没动）。
	# 要表达的是"收向中心"，基准就用骨架自己的锚点长度：收拢系数必须真的 < 1。
	var muzzles: Array = pc.get("_muzzle_local")
	t.gt(muzzles.size(), 0, "机体有炮口锚点")
	var max_off := 0.0
	for v: Vector3 in muzzles:
		max_off = maxf(max_off, v.length())
	var rig_len := 0.0
	if pc.rig != null:
		rig_len = pc.rig_anchor("muzzle_L").length()
	t.gt(rig_len, 1.0, "骨架上有炮口锚点（%.1f m）" % rig_len)
	t.lt(max_off, rig_len * 0.75,
		"炮口被收向机体中心（最远 %.1f m < 骨架 %.1f m 的 75%%）" % [max_off, rig_len])

	pc.free()
	cam.free()
	await host.get_tree().process_frame
	Game.reset()


static func _shared_ok(a: String, b: String) -> bool:
	for pair: Array in InputSetup.SHARED_KEYS_OK:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


static func _key(host: Node, key: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await host.get_tree().process_frame
	await host.get_tree().process_frame


static func _button(host: Node, button: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await host.get_tree().process_frame
	await host.get_tree().process_frame

## 轮 40 回归守卫：**鼠标准星必须真的决定弹道**，而且不许只在一个分支上成立。
##
## ## 为什么既有那一节抓不到这个缺陷
##
## `_mouse_reticle()` 的做法是「直接赋 `aim_cursor` → 直接 `pc.call("_read_aim_input")`
## → 断言 `pc.aim_forward()`」。它证明的只是**那个纯函数算得对**；而武器开火时真正走的
## 解算是 `FlightBody.aim_point()`，它按「有没有目标」分成两条路：
##
##   - 有目标 ⇒ `boresight = global_position + aim_forward() * dist` ← 读**准星**
##   - 无目标 ⇒ `return origin + forward() * 4000.0`                 ← 读**机头**（缺陷）
##
## 玩家开火时传的 `target` 是**锁定目标**（`player_controller.gd`：
## `var target: Node3D = lock.target if lock != null else null`），所以
## **没锁定时 `target == null`** ⇒ 走第二条 ⇒ 光束步枪与火神炮都朝机头打、完全不听准星。
## 而 `LockOnSystem` 会自动选目标，实战里多数时候 `target` 非空、看起来「跟准星」；
## 这个缺陷只在**刚重生 / 目标出锥 / 被干扰**时才暴露 —— 于是能长期不被发现。
##
## ## 这一节的判据
##
##   - **不手工调 `_read_aim_input()` / 不手工赋 `aim_cursor` 了事**：注入真鼠标事件，
##     让 `_think()` 自己走完链路（`_input()` → `aim_cursor` → `_read_aim_input()` → `aim_dir`）；
##   - **真开火**（`fire_beam(true, null)` / `fire_gun(true, null)`），读**弹丸自己的
##     `direction`** —— 不是我们算出来的那条方向（那样只是自己证明自己）；
##   - `target = null` 是**故意**的：它就是出缺陷的那条分支。
##
## 判据：准星甩右 ⇒ 弹道必须有**正的侧向分量**。把 `aim_point()` 那条兜底改回
## `forward()`，本节立刻变红。
##
## ⚠️ **两个会让测试假绿的坑**（都做成了前置自检）：
##   ① 机体不能放在 y=0：`CRASH_ALTITUDE = 24`，第一个物理帧就自毁 ⇒ `alive = false`
##      ⇒ `_physics_process` 直接 return ⇒ `_think()` 永不跑 ⇒ `aim_dir` 恒 ZERO
##      ⇒ **「跟准星 0°」与「跟机头 0°」同时成立**，整节读数是废的。
##   ② 注入的鼠标坐标要过 `get_viewport().get_final_transform()`（headless 实测缩放 25 倍）。
##      注入后**回读 `aim_cursor`** 自检；补偿不成立就明说并退回直接赋值，**不静默给假读数**。
static func _aim_reaches_weapon(t: T, host: Node) -> void:
	const ALT := 3000.0
	Game.reset()

	var cam := Camera3D.new()
	host.add_child(cam)
	cam.current = true
	var shots := Node3D.new()
	shots.name = "AimShots"
	host.add_child(shots)

	var pc := PlayerController.new()
	pc.team = 0
	pc.is_player = true
	pc.profile = SuitProfile.xi()
	pc.projectile_container = shots
	host.add_child(pc)
	pc.global_position = Vector3(0.0, ALT, 0.0)
	pc.max_hp = 600.0
	pc.hp = 600.0
	pc.ifield_max = 0.0
	pc.ifield_hp = 0.0
	pc.fm.speed = 260.0
	pc.fm.throttle = 0.78
	pc.fm.align_velocity(pc.forward())
	await host.get_tree().process_frame
	pc.controls_enabled = true
	pc.debug_input_enabled = true
	pc.debug_input = Vector3.ZERO
	pc.debug_throttle = 0.8
	pc.mouse_lock_enabled = true
	pc.cursor_seen = false
	pc.set_aim_direction(Vector3.ZERO)
	cam.global_position = pc.global_position + Vector3(0.0, 0.0, 120.0)
	cam.look_at(pc.global_position, Vector3.UP)
	await _aim_phys(host, 4)

	# ---- 自检：先证明这一节自己没坏（不然后面每一条都是假绿）----
	var think_ran := absf(pc.fm.throttle - 0.8) < 0.001
	t.ok(pc.alive, "机体没自毁（在 CRASH_ALTITUDE 之上）—— 否则 _think() 不跑，本节全是假绿")
	t.ok(think_ran, "_think() 在跑（判据 fm.throttle = 0.800，实读 %.3f）" % pc.fm.throttle)
	t.ok(host.get_viewport().get_camera_3d() != null,
		"视口里有当前相机（没有的话 _read_aim_input() 直接 return，读数会假红）")
	if not pc.alive or not think_ran or host.get_viewport().get_camera_3d() == null:
		t.ok(false, "前置自检没过 —— 下面所有读数无效，先修测试")
		pc.free()
		cam.free()
		shots.free()
		await host.get_tree().process_frame
		Game.reset()
		return
	t.ok((pc.get("_muzzle_local") as Array).size() > 0, "机体有炮口锚点（瞄准点要从炮口起算）")

	# ---- 没有鼠标事件：弹道必须还是机头（键鼠 / 手柄 / AI 侧一个数都不能变）----
	pc.cursor_seen = false
	pc.set_aim_direction(Vector3.ZERO)
	await _aim_phys(host, 3)
	var b_none := _fire_dir(shots, pc, "beam")
	t.lt(_angle_deg(b_none, pc.forward()), 2.0,
		"没有鼠标事件时弹道就是机头（实读 %.3f°），键鼠 / 手柄玩家不会突然打偏"
		% _angle_deg(b_none, pc.forward()))

	# ---- 准星甩到屏幕右侧 ----
	var vs := host.get_viewport().get_visible_rect().size
	var px_r := Vector2(vs.x * 0.92, vs.y * 0.5)
	var got_event := await _aim_inject(host, pc, px_r)
	t.ok(got_event, "真鼠标事件落到了 _input()（不通时本节退回直接赋值，行为断言仍然有效）")
	t.ok(pc.aim_cursor.distance_to(px_r) <= 1.0,
		"准星摆到位：(%.0f, %.0f)" % [pc.aim_cursor.x, pc.aim_cursor.y])
	var aim_r := pc.aim_forward()
	t.gt(aim_r.dot(pc.right()), 0.1, "准星偏右 → 准星方向也偏右（链路前半段通）")
	t.ok(pc.control_input.is_equal_approx(Vector3.ZERO), "鼠标不产生任何操纵量")

	var b_r := _fire_dir(shots, pc, "beam")
	var v_r := _fire_dir(shots, pc, "vulcan")
	t.gt(b_r.dot(pc.right()), 0.1,
		"**没锁定**时光束步枪弹道跟着准星偏右（实读 %+.4f）" % b_r.dot(pc.right()))
	t.gt(v_r.dot(pc.right()), 0.1,
		"**没锁定**时火神炮弹道跟着准星偏右（实读 %+.4f）" % v_r.dot(pc.right()))
	t.lt(_angle_deg(b_r, aim_r), 2.0,
		"光束弹道与准星夹角 < 2°（实读 %.3f°）" % _angle_deg(b_r, aim_r))
	t.lt(_angle_deg(v_r, aim_r), 3.0,
		"火神炮弹道与准星夹角 < 3°（含散布；实读 %.3f°）" % _angle_deg(v_r, aim_r))
	var off_head := _angle_deg(b_r, pc.forward())
	t.gt(off_head, 5.0,
		"光束弹道与**机头**明显不同（实读 %.3f°）—— 缺陷版本这里正是 0.000°" % off_head)

	# ---- 准星甩到屏幕左侧：同一条判据的另一半 ----
	await _aim_inject(host, pc, Vector2(vs.x * 0.08, vs.y * 0.5))
	var aim_l := pc.aim_forward()
	var b_l := _fire_dir(shots, pc, "beam")
	var v_l := _fire_dir(shots, pc, "vulcan")
	t.lt(b_l.dot(pc.right()), -0.1,
		"准星偏左 → 光束弹道也偏左（实读 %+.4f）" % b_l.dot(pc.right()))
	t.lt(v_l.dot(pc.right()), -0.1,
		"准星偏左 → 火神炮弹道也偏左（实读 %+.4f）" % v_l.dot(pc.right()))
	t.gt(_angle_deg(aim_r, aim_l), 10.0,
		"两次准星确实摆在不同方向上（夹角 %.3f°）" % _angle_deg(aim_r, aim_l))
	t.gt(_angle_deg(b_r, b_l), 10.0,
		"两条光束弹道之间也拉开了同样大的角（弹道真的在动）%.3f°" % _angle_deg(b_r, b_l))
	t.gt(_angle_deg(v_r, v_l), 10.0,
		"两条火神炮弹道同理 %.3f°" % _angle_deg(v_r, v_l))

	pc.free()
	cam.free()
	shots.free()
	await host.get_tree().process_frame
	Game.reset()


## 轮 41：**准星像素 ⇄ 弹道方向 必须同源**。
##
## ## 为什么轮 40 那一节盖不住它
##
## `_aim_reaches_weapon()` 钉的是**方向**（准星偏右 ⇒ 弹道偏右），它管不到**量**：
## 偏 3° 和偏 25° 在它那里都是绿的。而用户报的恰恰是量 ——
## 「向上发射光束步枪，为什么光束步枪的子弹还是会朝前？」。
##
## 真因：弹道偏角旧公式恒等于 `atan(MOUSE_GAIN*|m|)`（单轴上限 **28.81°**），
## 而准星是 HUD 按**原始鼠标像素**画的（`hud.gd::_draw_aim_cursor()`）。
## 两者只在屏幕中心相等，越往外差得越多 —— 实测（`tools/probe_aim_cursor_offset.gd`，
## 真 ChaseCamera）：屏幕正上方 **9.52°**、屏幕正左 **23.75°**、左上角 **21.07°**、
## 用户截图那帧 **16.44°**。
##
## ## 判据（以**准星像素那一条相机射线**为基准）
##
##   · `aim_forward()` 与它夹角 **< 2°** —— 旧公式在屏幕边缘是 9~24°，会**红**；
##   · 再真发一发光束，`Projectile.direction` 与它夹角 **< 2°** —— 端到端，
##     不是只测 `aim_forward()` 这个纯函数（轮 40 的教训：纯函数绿、武器那条路红）。
##
## ⚠️ 准星位置特意**不取屏幕中心**：旧公式在中心误差只有 0.13°，
##    测中心等于测了个"两种实现都绿"的格子，区分不出来。
static func _cursor_ray_matches_aim(t: T, host: Node) -> void:
	const ALT := 3000.0
	Game.reset()

	var cam := Camera3D.new()
	host.add_child(cam)
	cam.current = true
	var shots := Node3D.new()
	shots.name = "RayShots"
	host.add_child(shots)

	var pc := PlayerController.new()
	pc.team = 0
	pc.is_player = true
	pc.profile = SuitProfile.xi()
	pc.projectile_container = shots
	host.add_child(pc)
	pc.global_position = Vector3(0.0, ALT, 0.0)
	pc.max_hp = 600.0
	pc.hp = 600.0
	pc.ifield_max = 0.0
	pc.ifield_hp = 0.0
	pc.fm.speed = 260.0
	pc.fm.throttle = 0.78
	pc.fm.align_velocity(pc.forward())
	await host.get_tree().process_frame
	pc.controls_enabled = true
	pc.debug_input_enabled = true
	pc.debug_input = Vector3.ZERO
	pc.debug_throttle = 0.8
	pc.mouse_lock_enabled = true
	pc.cursor_seen = true
	pc.set_aim_direction(Vector3.ZERO)
	cam.global_position = pc.global_position + Vector3(0.0, 0.0, 120.0)
	cam.look_at(pc.global_position, Vector3.UP)
	await _aim_phys(host, 4)

	var vs := host.get_viewport().get_visible_rect().size
	var cam_ok := host.get_viewport().get_camera_3d() != null
	var ready := pc.alive and cam_ok
	t.ok(ready, "（前提）机体活着、视口里有当前相机 —— 否则 `_read_aim_input()` 直接 return")
	if not ready:
		pc.free()
		cam.free()
		shots.free()
		await host.get_tree().process_frame
		Game.reset()
		return

	# 三个位置全是**旧公式误差最大**的那几处
	var spots := [
		["屏幕正上方", Vector2(0.5, 0.02)],
		["屏幕正左", Vector2(0.02, 0.5)],
		["左上角", Vector2(0.02, 0.02)],
	]
	for sp: Array in spots:
		var frac: Vector2 = sp[1]
		var px := Vector2(vs.x * frac.x, vs.y * frac.y)
		await _aim_inject(host, pc, px)
		var got: Vector2 = pc.aim_cursor
		# 注入会不会被"窗口里那只真鼠标"覆盖是环境问题；先证明注入落到点上了，
		# 否则下面两条会变成"量了一把空气"（实测跑到屏幕左缘时确实被覆盖过一次）。
		t.lt(got.distance_to(px), 2.0,
			"%s：准星确实被摆到了 (%.0f, %.0f)（实读 (%.0f, %.0f)）"
			% [sp[0], px.x, px.y, got.x, got.y])
		var ray := cam.project_ray_normal(got)
		var aim: Vector3 = pc.aim_forward()
		var e_aim := _angle_deg(ray, aim)
		t.lt(e_aim, 2.0,
			"%s：弹道方向 = 准星像素的相机射线（实读 %.2f°；旧 MOUSE_GAIN 公式这里是 9~24°）"
			% [sp[0], e_aim])
		var d := _fire_dir(shots, pc, "beam")
		var e_shot := _angle_deg(d, ray)
		t.lt(e_shot, 2.0,
			"%s：**真弹丸**的飞行方向也等于那条射线（实读 %.2f°）" % [sp[0], e_shot])

	pc.free()
	cam.free()
	shots.free()
	await host.get_tree().process_frame
	Game.reset()


## 打一发**真弹**，返回**弹丸自己**的 `direction`（不是我们算的那条方向）。
##
## `target` 传 `null` 是**故意**的 —— 那就是「没锁定」这条出缺陷的分支。
static func _fire_dir(shots: Node3D, pc: PlayerController, kind: String) -> Vector3:
	var before := shots.get_child_count()
	if kind == "beam":
		pc.rifle_cooldown = 0.0
		pc.rifle_reloading = false
		pc.rifle_count = maxi(pc.rifle_count, 3)
		pc.rifle_mag = maxi(pc.rifle_mag, 20)
		pc.fire_beam(true, null)
	else:
		pc.gun_cooldown = 0.0
		pc.vulcan_overheated = false
		pc.fire_gun(true, null)
	var after := shots.get_child_count()
	if after <= before:
		# 一发都没打出去 —— 返回零向量，调用方的夹角判据会得到 180° 并**变红**，
		# 而不是安静地「测了个空」。
		return Vector3.ZERO
	var d: Variant = shots.get_child(after - 1).get("direction")
	return d if d is Vector3 else Vector3.ZERO


## 两个方向之间的夹角（度）。任一为零向量时返回 **180°**（＝读数无效），
## 这样调用方的 `lt(角度, 2)` 会**红**，不会把「没读到」混成「读到了 0°」。
static func _angle_deg(a: Vector3, b: Vector3) -> float:
	if a.length_squared() < 1e-9 or b.length_squared() < 1e-9:
		return 180.0
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


## 注入一个**真**鼠标移动事件，让 `_think()` 自己把它读成 `aim_dir`。
##
## 返回 `true` = 走的是真事件通道；`false` = 坐标补偿失效、退回直接赋值。
##
## ⚠️ 坐标必须过 `get_viewport().get_final_transform()`：`_input()` 收到的
## `mm.position` 已经是视口变换之后的坐标（headless 实测缩放 **25 倍**）。
## ⚠️ 同一帧内对**同一位置**重复注入会被 Godot **去重**，所以每次注入后都等物理帧。
static func _aim_inject(host: Node, pc: PlayerController, px: Vector2) -> bool:
	var f := host.get_viewport().get_final_transform()
	var ev := InputEventMouseMotion.new()
	ev.position = f * px
	ev.global_position = ev.position
	ev.relative = Vector2.ZERO
	Input.parse_input_event(ev)
	await _aim_phys(host, 2)
	if pc.aim_cursor.distance_to(px) <= 1.0:
		return true
	# 补偿失效：退回直接赋值。仍然**不手工调 `_read_aim_input()`** ——
	# 照旧等 `_think()` 自己读，只是「事件」这一环由我们代填。
	pc.cursor_seen = true
	pc.aim_cursor = px
	await _aim_phys(host, 2)
	return false


static func _aim_phys(host: Node, n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
