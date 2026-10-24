class_name SuiteGamepad
extends RefCounted
## 手柄适配的测试。
##
## 手柄最容易"看起来接了其实没接"：按键绑了但只在运行时补、轴写错了正负、
## 或者菜单能确认却不能选项。所以这里断言的是 **InputMap 里真的有那些事件**，
## 以及纯函数（边沿判定、符号换算）的行为。
##
## ★★ 2026-09-30（轮 57）：补上「**真页面的真事件**」那一层 ——
## 起因是用户实测「任务菜单选择的时候手柄按下没有反应」：
## `campaign_map` / `mission_brief` 两页**只认 `InputEventKey`**，手柄一个键都进不来，
## 而它们的页脚（`_draw_hint()`）从落地那天就印着「十字键选择 · A 出击 · B 返回」。
## ⇒ 本文件新增 `_campaign_pages()`，用**事件注入**直接喂
## `InputEventJoypadButton` / `InputEventKey` 给 `_input()`，看光标与信号动不动。
## ⚠️ 不走 `Input.action_press()` —— 那个的 `just_pressed` 帧戳在无头下不可靠
##（`suite_tutorial` 实测漏一次、`suite_fpv` 因此改过写法）；
## 事件注入是确定性的：`is_action_pressed()` 走 InputMap 的静态匹配，与帧无关。

const CMAP := preload("res://scripts/ui/campaign_map.gd")
const CBRIEF := preload("res://scripts/ui/mission_brief.gd")
const MS := preload("res://scripts/data/mission_script.gd")
const CS := preload("res://scripts/data/campaign.gd")


static func run(t: T, host: Node) -> void:
	t.suite("Gamepad / InputMap 里的手柄事件")
	_bindings(t)
	t.suite("Gamepad / 菜单导航用十字键")
	_nav_keys(t)
	t.suite("Gamepad / 剧情流程的页面必须真的吃手柄")
	_campaign_pages(t, host)
	t.suite("Gamepad / 无手柄时不产生输入")
	_no_pad(t)
	t.suite("Gamepad / 摇杆边沿判定")
	_edges(t)
	t.suite("Gamepad / 检测到手柄就切换提示")
	_hint_switch(t)


## 提示文案随设备切换。这是用户明确要求的那一条。
static func _hint_switch(t: T) -> void:
	var old := InputSetup.using_gamepad
	InputSetup.using_gamepad = false
	t.eq(InputSetup.hint("W / S", "左摇杆"), "W / S", "键鼠模式下给键盘文案")
	t.eq(str(InputSetup.hint("R", "Y")), "R", "键鼠模式下换弹提示是 R")
	InputSetup.using_gamepad = true
	t.eq(InputSetup.hint("W / S", "左摇杆"), "左摇杆", "手柄模式下给手柄文案")
	t.eq(str(InputSetup.hint("R", "Y")), "Y", "手柄模式下换弹提示变成 Y")
	t.eq(str(InputSetup.hint("I", "")), "I",
		"手柄做不了的动作（俯仰反转）退回键盘文案，不会显示空白")
	InputSetup.using_gamepad = old

	# 帮助表每一项都必须有第三项，否则手柄模式下那一行会没提示
	var missing := 0
	for sec: Dictionary in InputSetup.HELP_SECTIONS:
		for it: Array in sec["items"]:
			if it.size() < 3:
				missing += 1
	t.eq(missing, 0, "帮助表每一项都带手柄键位（可留空表示手柄做不了）")

	# HUD 右下角那几件装备都得有手柄写法，否则手柄模式下会显示鼠标键
	for act: String in ["fire_primary", "fire_secondary", "fire_gun", "reload",
			"fire_missile", "flares", "shield"]:
		t.ok(FlightHUD.PAD_GLYPH.has(act), "HUD 装备行 %s 有手柄写法" % act)


static func _bindings(t: T) -> void:
	var missing: Array[String] = []
	for action: String in InputSetup.PAD_BINDINGS:
		if not InputMap.has_action(action):
			missing.append(action + "(动作不存在)")
			continue
		for btn: int in InputSetup.PAD_BINDINGS[action]:
			var found := false
			for ev: InputEvent in InputMap.action_get_events(action):
				var jb := ev as InputEventJoypadButton
				if jb != null and jb.button_index == btn:
					found = true
			if not found:
				missing.append("%s→按键%d" % [action, btn])
	t.eq(missing.size(), 0, "所有手柄按键都进了 InputMap（缺：%s）" % str(missing))

	var axis_missing: Array[String] = []
	for action: String in InputSetup.PAD_AXIS_BINDINGS:
		for pair: Array in InputSetup.PAD_AXIS_BINDINGS[action]:
			var axis := int(pair[0])
			var found := false
			for ev: InputEvent in InputMap.action_get_events(action):
				var jm := ev as InputEventJoypadMotion
				if jm != null and jm.axis == axis:
					found = true
			if not found:
				axis_missing.append("%s→轴%d" % [action, axis])
	t.eq(axis_missing.size(), 0, "所有手柄轴都进了 InputMap（缺：%s）" % str(axis_missing))

	# 飞行/战斗的关键动作必须都能用手柄做到，否则"适配"是残的
	for action: String in ["fire_primary", "fire_secondary", "fire_gun", "fire_missile",
			"shield", "reload", "boost", "hover", "confirm", "menu_back", "pause"]:
		t.ok(InputSetup.PAD_BINDINGS.has(action) or InputSetup.PAD_AXIS_BINDINGS.has(action),
			"战斗关键动作 %s 有手柄绑定" % action)

	# 用户实测的两条：
	#   （a）"按住左摇杆才是加速太反人类" → 加速必须挪到 X，且**不能**再留在 L3 上；
	#   （b）"手柄的 Esc 适配也没做" → 暂停必须有手柄入口（Start）。
	t.ok(InputSetup.PAD_BINDINGS.get("boost", []).has(JOY_BUTTON_X),
		"加速绑在 X 键上（用户要求：按住 X 加速）")
	t.not_ok(InputSetup.PAD_BINDINGS.get("boost", []).has(JOY_BUTTON_LEFT_STICK),
		"加速**不再**绑在按下左摇杆（L3）上 —— 那样没法边加速边精确压杆")
	t.ok(InputSetup.PAD_BINDINGS.get("pause", []).has(JOY_BUTTON_START),
		"暂停绑在 Start 上（就是手柄上的 Esc）")
	# 剩下的按键归属（这些是"手柄适配"里最容易漏掉的小动作）
	# 1.1：手柄 16 个键早就满了，这一轮又加进"变形"（阿利宙斯的核心动作），
	# 于是重新分了家：**变形 ← L3**（点一下的动作，原来在 L3 的干扰弹退到 Back），
	# **干扰弹 ← Back**，而"只有柯西才有"的丢枪脱锁与"只是换个观察角度"的锁定镜头
	# 退回键盘（G / Alt）。取舍理由见 InputSetup.PAD_BINDINGS 的注释。
	for pair: Array in [["transform", JOY_BUTTON_LEFT_STICK], ["flares", JOY_BUTTON_DPAD_DOWN],
			["reload", JOY_BUTTON_Y], ["hover", JOY_BUTTON_RIGHT_STICK]]:
		t.ok(InputSetup.PAD_BINDINGS.get(str(pair[0]), []).has(int(pair[1])),
			"%s 有手柄键位" % pair[0])
	t.not_ok(InputSetup.PAD_BINDINGS.has("discard_rifle"),
		"丢枪脱锁**不占独立手柄键位**：它走「长按 Y 0.6 s」（= `reload` 的长按，见 PlayerController._tick_holds）")
	# ---- 1.2：十字键改成功能键（用户要求）----
	#
	# 旧设计是"十字键复用 roll_*/pitch_*，于是主菜单不用另写导航"。
	# 用户明确要求"别拿来控制镜头和机体方向了，每个方向拿来做功能性按键"，
	# 于是四个方向各自接管一个战斗功能，**导航改由 `_nav_x/_nav_y` 读左摇杆轴**。
	t.ok(InputSetup.PAD_BINDINGS.has("missile_mode"),
		"导弹系统模式 第十八轮占用手柄按键（十字键 ←；锁定镜头并进了辅助飞行）")
	t.ok(InputSetup.PAD_BINDINGS.has("look_back"),
		"回头看 1.2 起占用手柄按键（**Back** —— 用户点名这个键没用上）")
	for pair: Array in [["switch_target", JOY_BUTTON_DPAD_UP], ["flares", JOY_BUTTON_DPAD_DOWN],
			["missile_mode", JOY_BUTTON_DPAD_LEFT]]:
		t.ok(InputSetup.PAD_BINDINGS.get(str(pair[0]), []).has(int(pair[1])),
			"%s 绑在十字键上（功能键，不再是操纵）" % pair[0])
	# ⚠️ 反向约束：十字键**不得**再出现在任何操纵动作上
	for a: String in ["roll_left", "roll_right", "pitch_nose_up", "pitch_nose_down"]:
		for b: int in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
				JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
			t.not_ok(InputSetup.PAD_BINDINGS.get(a, []).has(b),
				"%s 不再占用十字键（用户要求：十字键只做功能键）" % a)
	t.ok(InputSetup.PAD_BINDINGS.get("flares", []).has(JOY_BUTTON_DPAD_DOWN),
		"干扰弹从 Back 挪到十字键 ↓")
	t.not_ok(InputSetup.PAD_BINDINGS.get("flares", []).has(JOY_BUTTON_BACK),
		"干扰弹不再占用 Back（Back 让给回头看）")

	# ---- 2026-09-21：手柄的「长按二义」（老板："把古斯塔夫和梅萨都做手柄适配"）----
	#
	# 手柄 17 键全满，所以"修复"与"呼叫 / 搭乘飞行踏板"只能靠长按补 ——
	# 而这两个恰好是两台量产机的招牌（能骑板 + 每场 3 个修复包），原来都是**键盘独占**。
	# 批 1（多目标锁定）又加了第三条：**长按十字键 ↑ = 加入锁定组**。
	t.eq(InputSetup.PAD_HOLD.size(), 4,
		"长按二义表有四条（修复 / 呼叫踏板 / 加入锁定组 / 视角切换）")
	var hold_targets: Array[String] = []
	var help_pads := ""
	for sec: Dictionary in InputSetup.HELP_SECTIONS:
		for it: Array in sec["items"]:
			help_pads += str(it[2]) + "|"
	for trigger: String in InputSetup.PAD_HOLD:
		var spec: Dictionary = InputSetup.PAD_HOLD[trigger]
		hold_targets.append(str(spec.get("hold_action", "")))
		t.ok(InputSetup.PAD_BINDINGS.has(trigger),
			"长按的**触发键** %s 本身是手柄键（不然长按无从谈起）" % trigger)
		t.gt(float(spec.get("secs", 0.0)), 0.4,
			"%s 的长按时长 %.2f s 够长（防误触）" % [trigger, float(spec.get("secs", 0.0))])
		t.ok(str(spec.get("glyph", "")).contains("长按"), "%s 的写法带「长按」" % trigger)
		# ⚠️ **三处同源的反向门**：表里写了长按，帮助面板就必须真有一行印着它。
		# 少这一处就是本工程反复栽的"说明书印着一个按不出来的键"。
		t.ok(help_pads.contains(str(spec["glyph"])),
			"帮助面板里有「%s」这一行" % str(spec["glyph"]))
	t.ok(hold_targets.has("repair"), "手柄上有**修复**（回血）的入口")
	t.ok(hold_targets.has("ride_pedal"), "手柄上有**呼叫 / 搭乘飞行踏板**的入口")
	t.ok(hold_targets.has("add_lock"), "手柄上有**加入锁定组**的入口（批 1 多目标锁定）")
	# 轮 25：手柄上视角切换的入口（"长按回头键"，用户指定）——
	# 与 F1 同款：都调 `Settings.toggle_first_person()`。
	t.ok(hold_targets.has("toggle_fpv"), "手柄上有**第一人称 / 第三人称切换**的入口（轮 25）")
	t.eq(str(InputSetup.PAD_HOLD["look_back"]["hold_action"]), "toggle_fpv",
		"视角切换挂在**长按 Back**上（点按 Back 仍是按住回头看）")
	t.gt(float(InputSetup.PAD_HOLD["look_back"]["secs"]), 0.9,
		"长按 Back 的阈值明显长于别处（回头是按住型动作，短阈值会误切视角）")
	# ⚠️ 表里写了还不够：**控制器必须真的把它建出来**（"配好了却没接线"是本工程的老坑）。
	# `_init()` 只配置 HoldAction，不需要进树，所以这里可以裸建一个。
	var pc := PlayerController.new()
	t.eq((pc.get("_pad_holds") as Dictionary).size(), InputSetup.PAD_HOLD.size(),
		"PlayerController 按表建了同样多条长按实例（表 / 代码同源）")
	for trigger: String in InputSetup.PAD_HOLD:
		t.ok((pc.get("_pad_holds") as Dictionary).has(trigger),
			"%s 的长按实例存在" % trigger)
	pc.free()


## 十字键在菜单里**四个方向一个都不能是死的**。
##
## ⚠️ 原来这里只有一句 `t.ok(true, "主菜单类可用…")` —— 那是**恒真的装饰**：
## 它长得像"测过菜单导航了"，实际上一个字节都没测（`t.ok(true,…)` 永远绿）。
## 改成三条真判据：
##   ① 四个方向在 InputMap 里各自有动作接住（`_map_pad`）；
##   ② 纵向那两个动作**真的被菜单的导航表**算成"上 / 下"，且**上下两张表不相交**
##      （相交正是 2026-09 那次"按一下不知道跳到哪"的成因）；
##   ③ 摇杆边沿兜底的那条路还在（十字键被征用给飞行之后，菜单全靠它）。
static func _nav_keys(t: T) -> void:
	# ① 四个方向各有动作接住 —— 少一个的症状就是"按那个方向没反应"
	for pair: Array in [["switch_target", JOY_BUTTON_DPAD_UP],
			["flares", JOY_BUTTON_DPAD_DOWN],
			["missile_mode", JOY_BUTTON_DPAD_LEFT],
			["switch_weapon", JOY_BUTTON_DPAD_RIGHT]]:
		t.ok(_map_pad(str(pair[0]), int(pair[1])),
			"十字键方向 %d 有动作 %s 接住" % [int(pair[1]), str(pair[0])])

	# ② 纵向：读的就是 `NAV_*_ACTIONS`（不是另抄一份），且符号正确
	t.eq(MainMenu.nav_delta_y(["switch_target"]), -1, "十字键 ↑ 在菜单里算「上」")
	t.eq(MainMenu.nav_delta_y(["flares"]), 1, "十字键 ↓ 算「下」")
	t.eq(MainMenu.nav_delta_y(MainMenu.NAV_UP_ACTIONS), -1, "整张上表一起算「上」")
	t.eq(MainMenu.nav_delta_y(MainMenu.NAV_DOWN_ACTIONS), 1, "整张下表一起算「下」")
	for a: String in MainMenu.NAV_UP_ACTIONS:
		t.not_ok(MainMenu.NAV_DOWN_ACTIONS.has(a),
			"★ %s **不能同时**在上下两张表里（同时认 ⇒ 「按一下不知道跳到哪」）" % a)

	# ③ 摇杆兜底那条路（`_process` → `_update_pad_edges()` → `_pad_dx/_pad_dy`）。
	# ⚠️ 只钉"这条路存在"：它读的是 `Input.get_joy_axis`，无头下没法注入。
	# 纯函数那一半（`_edge()` 的死区与边沿）由 `_edges()` 逐条验，两半合起来才闭环。
	var menu := MainMenu.new()
	t.ok(menu.has_method("_update_pad_edges"),
		"主菜单有摇杆边沿兜底（十字键被征用给飞行后，菜单导航靠它）")
	menu.free()


## ★★ 剧情流程里的页面必须真的吃手柄（轮 57 修的那条 bug）。
##
## 事故形状：`campaign_map` / `mission_brief` 的 `_input()` 第一行写着
## `if not (event is InputEventKey): return` ⇒ **手柄事件在门口就被丢掉**。
## 而两页的页脚早就承诺了手柄键位（`_draw_hint()` 的 `InputSetup.hint()` 第二参数）。
## ⇒ 玩家看到「A 出击」按下去毫无反应。**提示与实现分家**，且没有任何断言会红。
##
## ⚠️ 这里的判据必须**同时**钉住"该动的动了"与"不该动的不动"：
## 只测前者的话，"任何事件都会推进光标"这种 bug 也能全绿。
static func _campaign_pages(t: T, host: Node) -> void:
	# ---- ① 页脚承诺的动作名，必须真的绑在十字键上 ----
	#
	# 页脚印的是「十字键选择 · 左右调难度」，那行字里**没有按钮号** ——
	# 它与代码之间的唯一契约就是"`PAD_*` 那几个动作名真的绑在十字键上"。
	for pair: Array in [[CMAP.PAD_UP, JOY_BUTTON_DPAD_UP],
			[CMAP.PAD_DOWN, JOY_BUTTON_DPAD_DOWN],
			[CMAP.PAD_LEFT, JOY_BUTTON_DPAD_LEFT],
			[CMAP.PAD_RIGHT, JOY_BUTTON_DPAD_RIGHT],
			[CBRIEF.PAD_LEFT, JOY_BUTTON_DPAD_LEFT],
			[CBRIEF.PAD_RIGHT, JOY_BUTTON_DPAD_RIGHT]]:
		var act := str(pair[0])
		var btn := int(pair[1])
		t.ok(InputMap.has_action(act), "页脚承诺的动作 %s 在 InputMap 里存在" % act)
		t.ok(_map_pad(act, btn), "★ %s 真的绑在十字键 %d 上（页脚印的就是它）" % [act, btn])

	# ---- ② 战役图（"任务菜单"）：注入真事件 ----
	var cm := CMAP.new()
	host.add_child(cm)
	# 全解锁 ⇒ "按 A 出击"走的是真信号，而不是被 `can_enter()` 明确拒绝挡掉
	#（那样的话下面那条会假绿：看起来"有反应"其实是"拒绝"）。
	cm.set("producer", true)
	t.ok(bool(cm.call("open", CS.new_progress())),
		"战役图打开了（前置 —— 不开的话下面全是空转）")
	# ⚠️ 只关 `_process`（摇杆那一路），`_input` 留着 —— 保证读数不受
	# "这台机器上真插着手柄、摇杆恰好被推过阈值"影响。
	cm.set_process(false)

	var chosen: Array = []
	var backs: Array = [0]
	cm.mission_chosen.connect(func(id: String) -> void: chosen.append(id))
	cm.cancelled.connect(func() -> void: backs[0] += 1)

	var c0 := int(cm.get("cursor"))
	var lv0 := int(cm.get("level"))

	cm.call("_input", _pad(JOY_BUTTON_DPAD_DOWN))
	t.eq(int(cm.get("cursor")), c0 + 1, "★ 十字键 ↓ 把光标往下挪一格（施工前：一个键都进不来）")
	# ⚠️ 期望值取「按下 ↓ **之后**的读数」而不是 c0。
	# 写死 c0 的话，输入整条失效时"↑ 挪回来"会**假绿** —— 光标压根没动过，
	# `== c0` 成立，而它证明的其实是"没去过"，不是"回来了"。
	var c_down := int(cm.get("cursor"))
	cm.call("_input", _pad(JOY_BUTTON_DPAD_UP))
	t.eq(int(cm.get("cursor")), c_down - 1, "★ 十字键 ↑ 挪回来（相对按下后的读数）")

	cm.call("_input", _pad(JOY_BUTTON_DPAD_RIGHT))
	var lv1 := int(cm.get("level"))
	t.ok(lv1 != lv0, "★ 十字键 → 真的切了难度（%d → %d）" % [lv0, lv1])
	cm.call("_input", _pad(JOY_BUTTON_DPAD_LEFT))
	var lv_back := int(cm.get("level"))
	# 期望值用**独立的 lv0**（不引 `cycle_difficulty()` 自证），
	# 再配一条"来回之间真的变过"破假绿：全失效时 lv1 == lv_back。
	t.eq(lv_back, lv0, "★ 十字键 ← 切回原来的难度")
	t.not_ok(lv1 == lv_back,
		"★ 左右两个方向都真的通（不是一个通一个死；全失效时这条会红）")

	# （对照）无关按键在这页上什么都不该做
	var c_before := int(cm.get("cursor"))
	var lv_before := int(cm.get("level"))
	cm.call("_input", _pad(JOY_BUTTON_X))
	cm.call("_input", _pad(JOY_BUTTON_Y))
	t.eq(int(cm.get("cursor")), c_before, "（对照）X / Y 不动光标")
	t.eq(int(cm.get("level")), lv_before, "（对照）X / Y 不动难度")
	t.eq(chosen.size() + backs[0], 0, "（对照）X / Y 不发任何信号")

	cm.call("_input", _pad(JOY_BUTTON_A))
	t.eq(chosen.size(), 1, "★ A = 出击（发 `mission_chosen`）")
	t.eq(str(chosen[0]) if chosen.size() > 0 else "", str(cm.call("selected_id")),
		"选中的就是光标上那一关")
	# （对照）"抬起"不是"按下"：菜单是"按一下走一步"，松手再响应会像延迟一拍
	cm.call("_input", _pad(JOY_BUTTON_A, false))
	t.eq(chosen.size(), 1, "（对照）抬起 A 不该再触发一次")

	cm.call("_input", _pad(JOY_BUTTON_B))
	t.eq(backs[0], 1, "★ B = 返回（发 `cancelled`）")

	# ---- ③ 键盘那一路不能被我改坏（加一条路 ≠ 换一条路）----
	var kd := InputEventKey.new()
	kd.keycode = KEY_DOWN
	kd.pressed = true
	var c_kb := int(cm.get("cursor"))
	cm.call("_input", kd)
	t.eq(int(cm.get("cursor")), c_kb + 1, "★ 键盘 ↓ 照旧管用（手柄是**加**的一条路）")
	var kes := InputEventKey.new()
	kes.keycode = KEY_ESCAPE
	kes.pressed = true
	cm.call("_input", kes)
	t.eq(backs[0], 2, "键盘 Esc 照旧返回")
	cm.queue_free()

	# ---- ④ 简报页（选完关卡的下一页，同一个流程）----
	var m: MS.Mission = MS.by_id(str(CS.mission_ids()[0]))
	t.ok(m != null, "拿到一个真任务（前置）")
	var br := CBRIEF.new()
	host.add_child(br)
	t.ok(bool(br.call("open", m)), "简报页打开了（前置）")
	br.set_process(false)

	var conf: Array = [0]
	var canc: Array = [0]
	br.confirmed.connect(func() -> void: conf[0] += 1)
	br.cancelled.connect(func() -> void: canc[0] += 1)

	br.call("_input", _pad(JOY_BUTTON_DPAD_LEFT))
	t.eq(int(br.get("cursor")), 1, "★ 十字键 ← 把选项翻到「返回」")
	t.eq(conf[0] + canc[0], 0, "（对照）只翻选项**不发信号**")
	# 同 ②：相对"← 之后的读数"而不是写死 0，避开"没去过也算回来了"的假绿。
	var br_left := int(br.get("cursor"))
	br.call("_input", _pad(JOY_BUTTON_DPAD_RIGHT))
	t.eq(int(br.get("cursor")), 1 - br_left, "★ 十字键 → 翻回「出击」（相对 ← 之后的读数）")
	br.call("_input", _pad(JOY_BUTTON_X))
	t.eq(int(br.get("cursor")), 0, "（对照）无关按键不动选项")

	br.call("_input", _pad(JOY_BUTTON_B))
	t.eq(canc[0], 1, "★ B = 返回")
	br.call("_input", _pad(JOY_BUTTON_A))
	t.eq(conf[0], 1, "★ A = 出击（光标停在「出击」上时）")

	var kd2 := InputEventKey.new()
	kd2.keycode = KEY_D
	kd2.pressed = true
	br.call("_input", kd2)
	t.eq(int(br.get("cursor")), 1, "★ 键盘 D 照旧翻选项（手柄是**加**的一条路）")
	br.queue_free()


## 造一个手柄按键事件。`pressed = false` 用来做"抬起不该算"的反面。
static func _pad(btn: int, pressed := true) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	return ev


## 某个动作在 InputMap 里**真的**绑着这个手柄键吗。
##
## ⚠️ 不查 `InputSetup.PAD_BINDINGS` 那张表 —— 表是"出厂意图"，
## 而 `is_action_pressed()` 读的是 **InputMap**（`ensure_all()` 之后的结果）。
## 这两者分家正是本仓库反复吃亏的地方（"配好了却没接线"）。
static func _map_pad(action: String, btn: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev: InputEvent in InputMap.action_get_events(action):
		var jb := ev as InputEventJoypadButton
		if jb != null and jb.button_index == btn:
			return true
	return false


## 没插手柄时，手柄那条路必须完全静默，不能凭空给操纵量。
static func _no_pad(t: T) -> void:
	if PlayerController.active_joypad() >= 0:
		t.ok(true, "当前接了手柄，跳过「无手柄」检查")
		return
	t.eq(PlayerController.active_joypad(), -1, "没插手柄时 active_joypad() 返回 −1")
	var pc := PlayerController.new()
	t.eq(pc._pad_axis(), Vector3.ZERO, "没插手柄时不产生任何操纵量")
	t.eq(pc._pad_throttle(), 0.0, "没插手柄时不产生任何油门量")
	pc.free()


static func _edges(t: T) -> void:
	# 边沿判定：只有"刚推过去"的那一下算一次，一直推着不再重复触发
	t.eq(MainMenu._edge(0.0, 0.0), 0, "摇杆回中不触发")
	t.eq(MainMenu._edge(0.9, 0.0), 1, "刚推到右边触发一次")
	t.eq(MainMenu._edge(0.9, 0.9), 0, "一直推着不重复触发")
	t.eq(MainMenu._edge(0.0, 0.9), 0, "松手回中不触发")
	t.eq(MainMenu._edge(-0.9, 0.0), -1, "刚推到左边触发一次")
	t.eq(MainMenu._edge(-0.9, -0.9), 0, "一直推着左边也不重复")
	t.eq(MainMenu._edge(0.3, 0.0), 0, "没过阈值不触发（死区）")
