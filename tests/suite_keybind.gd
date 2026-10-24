class_name SuiteKeybind
extends RefCounted
## 批 4（§4.8 按键自定义）的验收套件。按主题命名，不按轮次。
##
## ⚠️ **这一套必须在 SUITES 表里排最后**：它会真的改 InputMap 与
## `user://keybinds.cfg`（结束后 reset_all 回出厂），排前面会把其它套件的
## "InputMap == 出厂表"断言搞红。
##
## 十条断言（§4.8.9）：默认零回归 / 重绑生效 / **重启后仍在（核心）** /
## 原子性 / 防自锁 / 坏配置自愈 / 退役动作不复活 / 无重复绑定 /
## 说明书不撒谎 / headless。
##
## §4.8.10 的铁律也在这里被反向钉住："一键一动作"查的是 **bound_*()**
##（覆盖 ∪ 出厂），不是 const 表 —— 否则自定义就成了那条铁律的绕过口。

static func run(t: T, _host: Node) -> void:
	t.suite("Keybind / 默认零回归")
	InputSetup.reset_all()
	t.eq(InputSetup.LOCKED_ACTIONS, ["menu_back", "pause", "confirm"],
		"锁死动作 = 防自锁三件套（menu_back / pause / confirm）")
	for a: String in InputSetup.BINDINGS:
		t.eq(InputSetup.bound_keys(a), InputSetup.BINDINGS[a],
			"reset_all 后 %s 的键盘绑定逐条 = 出厂" % a)
	for a: String in InputSetup.MOUSE_BINDINGS:
		t.eq(InputSetup.bound_buttons(a), InputSetup.MOUSE_BINDINGS[a],
			"reset_all 后 %s 的鼠标绑定逐条 = 出厂" % a)
	for a: String in InputSetup.PAD_BINDINGS:
		t.eq(InputSetup.bound_pads(a), InputSetup.PAD_BINDINGS[a],
			"reset_all 后 %s 的手柄绑定逐条 = 出厂" % a)
	t.ok(InputMap.has_action("confirm") and InputMap.has_action("menu_back"),
		"headless 下 _ready() 正常：核心动作都在 map 里")

	t.suite("Keybind / 重绑生效（浮游导弹 F → H）")
	var ev_h := InputEventKey.new()
	ev_h.physical_keycode = KEY_H
	var res: Dictionary = InputSetup.try_rebind("fire_missile", 0, ev_h)
	t.eq(int(res["code"]), InputSetup.Bind.OK, "重绑返回 OK")
	InputSetup.ensure_all()
	t.eq(_map_physical("fire_missile"), [KEY_H],
		"运行时 InputMap 里 fire_missile 只有 H")
	var f_stolen := false
	for a: String in InputSetup.all_actions():
		if _map_physical(a).has(KEY_F):
			f_stolen = true
	t.not_ok(f_stolen, "F 不再属于任何动作（旧键被剪干净，不是'补缺不剪旧'）")

	t.suite("Keybind / 重绑在「重启」后还在（§4.8.2 核心断言）")
	InputSetup.clear_overrides_memory()
	InputSetup.ensure_all()
	t.eq(InputSetup.bound_keys("fire_missile"), [KEY_F],
		"模拟重启第一步：内存清零 + ensure_all → 回到出厂 F")
	InputSetup.load_overrides()
	InputSetup.ensure_all()
	t.eq(InputSetup.bound_keys("fire_missile"), [KEY_H],
		"读回 keybinds.cfg 后仍是 H（「改了不保存」的静默失败被钉死）")
	t.eq(_map_physical("fire_missile"), [KEY_H], "运行时 InputMap 也不是 F")

	t.suite("Keybind / 原子性：撞键整条拒绝，两边都不动")
	var ev_h2 := InputEventKey.new()
	ev_h2.physical_keycode = KEY_H   # H 此刻被 fire_missile 占用
	var res2: Dictionary = InputSetup.try_rebind("shield", 0, ev_h2)
	t.eq(int(res2["code"]), InputSetup.Bind.CONFLICT, "把举盾改到 H 返回 CONFLICT")
	t.eq(str(res2["conflict"]), "fire_missile", "报出占用者（可操作的失败原因）")
	t.eq(InputSetup.bound_keys("shield"), [KEY_T], "举盾的绑定一个字都没变")
	t.eq(InputSetup.bound_keys("fire_missile"), [KEY_H], "飞弹的绑定也没被顶掉")

	t.suite("Keybind / 防自锁：menu_back / pause / confirm 改不动")
	var ev_q := InputEventKey.new()
	ev_q.physical_keycode = KEY_Q
	for locked: String in ["menu_back", "pause", "confirm"]:
		var r: Dictionary = InputSetup.try_rebind(locked, 0, ev_q)
		t.eq(int(r["code"]), InputSetup.Bind.RESERVED, "%s 返回 RESERVED" % locked)
	t.eq(InputSetup.bound_keys("menu_back"), [KEY_ESCAPE], "Esc 仍然是返回键")

	t.suite("Keybind / 说明书不撒谎（派生第一列 = 旧手写文本，逐字）")
	InputSetup.reset_all()   # 说明书断言要**出厂态**
	var checks := [
		["推杆低头", "W / S"], ["左 / 右滚转", "A / D"], ["左 / 右偏航", "Q / E"],
		["收 / 加油门", "[ ] / 滚轮"], ["加速模式", "Shift"], ["悬停（空中定住）", "Ctrl"],
		["变形", "Z"], ["按住回头看", "V"], ["俯仰反转开关", "I"],
		["使用当前武器", "鼠标左键"], ["切换武器", "X"], ["光束步枪换弹", "R"],
		["火神炮", "空格"], ["浮游导弹", "F"], ["拦截来袭飞弹", "鼠标右键"],
		["修复机体", "U"], ["举盾（按一次", "T"],
		["呼叫 / 搭乘飞行踏板", "N"], ["脱离飞行踏板", "N 骑板时"],
		["干扰弹", "C"], ["丢弃步枪", "R 长按"],
		["选来袭飞弹作拦截目标", "B"], ["辅助驾驶 · 镜头跟住锁定目标", "G 长按"],
		["导弹系统：拦截 ⇄ 全弹发射", "Alt"], ["切换目标", "Tab"],
		["加入锁定组", "Tab 长按"], ["选中右上角敌机列表", "1 – 9"],
		["设置：画面尺寸", "P"], ["确认 · 出击", "Enter"],
		["暂停（战斗中）", "Esc"], ["主菜单里退出游戏", "Esc"],
	]
	var hit := {}
	var blank := 0
	for sec: Dictionary in InputSetup.HELP_SECTIONS:
		for it: Array in sec["items"]:
			var txt := InputSetup.help_text(it)
			if txt == "":
				blank += 1
			for c: Array in checks:
				if str(it[1]).begins_with(str(c[0])):
					hit[str(c[0])] = true
					t.eq(txt, str(c[1]),
						"说明书「%s…」列首 = %s" % [str(c[0]), str(c[1])])
	t.eq(blank, 0, "没有任何一行的派生文本是空白（空白会读成'没绑键'）")
	t.eq(hit.size(), checks.size(), "黄金对照表里的每一行都被真实命中（防对照表自己过期）")

	t.suite("Keybind / 坏配置自愈 + 退役动作不复活")
	var cf := ConfigFile.new()
	cf.set_value("keys", "menu_back", [KEY_Q])            # 锁死动作 → 丢弃
	cf.set_value("keys", "fire_gun", [KEY_J])             # 合法 → 保留（中键现已用于驾驶舱环视，改用空闲侧键）
	cf.set_value("keys", "yaw_left", [KEY_J])             # 与 fire_gun 撞键 → 至少丢一个
	cf.set_value("keys", "not_an_action", [KEY_K])        # 不存在的动作 → 丢弃
	cf.set_value("keys", "lock_camera", [KEY_K])          # 退役动作 → 丢弃
	cf.set_value("keys", "boost", [KEY_J, KEY_K])         # 槽位数对不上 → 丢弃
	cf.set_value("mouse", "fire_primary", [MOUSE_BUTTON_XBUTTON1])  # 合法 → 保留
	cf.save(InputSetup.KEYBINDS_PATH)
	InputSetup.clear_overrides_memory()
	InputSetup.load_overrides()
	var snap: Dictionary = InputSetup.overrides_snapshot()
	t.not_ok(snap["keys"].has("menu_back"), "锁死动作的覆盖值被丢弃（不崩，push_warning）")
	t.not_ok(snap["keys"].has("lock_camera"), "退役动作的覆盖值被丢弃")
	t.not_ok(snap["keys"].has("not_an_action"), "不存在的动作被丢弃")
	t.not_ok(snap["keys"].has("boost"), "槽位数对不上的覆盖值被丢弃")
	t.eq(int(snap["keys"].has("fire_gun")) + int(snap["keys"].has("yaw_left")), 1,
		"合法的键盘覆盖值保留：撞键的两条恰好幸存一条（另一条整条丢弃）")
	var surv: Array = snap["keys"].get("fire_gun", snap["keys"].get("yaw_left", []))
	t.eq(surv, [KEY_J], "幸存那条的覆盖值内容不变")
	t.eq(snap["mouse"].get("fire_primary", []), [MOUSE_BUTTON_XBUTTON1], "合法的鼠标覆盖值保留")
	t.not_ok(snap["keys"].has("fire_gun") and snap["keys"].has("yaw_left"),
		"撞键的两条覆盖值至少丢弃一条（加载期也跑冲突扫描）")
	InputSetup.ensure_all()
	t.not_ok(InputMap.has_action("lock_camera"), "退役动作没有被复活（§4.8.8）")
	t.eq(InputSetup.bound_keys("menu_back"), [KEY_ESCAPE], "menu_back 仍是出厂值")

	t.suite("Keybind / 一键一动作对 bound_*() 成立（§4.8.10）")
	var seen := {}
	var dup := false
	for a: String in InputSetup.all_actions():
		for code in InputSetup.bound_keys(a):
			var key: int = int(code)
			if seen.has(key) and str(seen[key]) != a \
					and not _shared(str(seen[key]), a):
				dup = true
				t.ok(false, "键 %d 同时属于 %s 与 %s" % [key, seen[key], a])
			seen[key] = a
	t.not_ok(dup, "键盘：一个键只属于一个动作（重绑之后仍然成立）")
	var mseen := {}
	var mdup := false
	for a: String in InputSetup.all_actions():
		for code in InputSetup.bound_buttons(a):
			var btn: int = int(code)
			if mseen.has(btn) and str(mseen[btn]) != a:
				mdup = true
				t.ok(false, "鼠标键 %d 同时属于 %s 与 %s" % [btn, mseen[btn], a])
			mseen[btn] = a
	t.not_ok(mdup, "鼠标：一键一动作仍然成立")
	# 手柄（批 10）：同一铁律也必须对 pad 表成立。
	var pseen := {}
	var pdup := false
	for a: String in InputSetup.PAD_BINDINGS:
		for code in InputSetup.bound_pads(a):
			var pbtn: int = int(code)
			if pseen.has(pbtn) and str(pseen[pbtn]) != a \
					and not _shared(str(pseen[pbtn]), a):
				pdup = true
				t.ok(false, "手柄键 %d 同时属于 %s 与 %s" % [pbtn, pseen[pbtn], a])
			pseen[pbtn] = a
	t.not_ok(pdup, "手柄：一键一动作仍然成立（刻意共用对除外）")

	t.suite("Keybind / 重绑页的行表与键位表同源")
	var flat: Array[String] = MainMenu.keys_flat()
	t.gt(flat.size(), 30, "重绑页列出全部可重绑动作（%d 行）" % flat.size())
	for locked: String in InputSetup.LOCKED_ACTIONS:
		t.not_ok(flat.has(locked), "锁死动作 %s 不出现在重绑页" % locked)
	var missing: Array[String] = []
	for a: String in InputSetup.BINDINGS:
		if not InputSetup.LOCKED_ACTIONS.has(a) and not flat.has(a):
			missing.append(a)
	for a: String in InputSetup.MOUSE_BINDINGS:
		if not flat.has(a):
			missing.append(a)
	t.eq(missing, [], "键位表里每个可重绑动作在重绑页都有一行（三处同源）")

	# ---- 批 10：手柄重绑各节（必须在收尾之前 —— 收尾要断言覆盖全空）----
	run_pad_sections(t)

	t.suite("Keybind / 收尾：回到出厂（后面没有别的套件了）")
	InputSetup.reset_all()
	t.eq(InputSetup.bound_keys("fire_missile"), [KEY_F], "收尾：飞弹回到 F")
	t.eq(InputSetup.bound_keys("fire_gun"), [KEY_SPACE], "收尾：火神炮回到空格")
	var fin: Dictionary = InputSetup.overrides_snapshot()
	t.eq(fin["keys"], {}, "存档覆盖已清空（空字典 = 完全等价现状）")
	t.eq(fin["mouse"], {}, "鼠标覆盖同样为空")
	t.eq(fin["pad"], {}, "手柄覆盖同样为空")


## ---- 批 10：手柄按键重绑 ----
##
## 用户要求"按键自定义系统还是再优化一下"。批 4 的 §4.8.5 刻意把"手柄不进自定义"
## 定成当时的设计（"手柄玩家在等待态按不出新键"）—— 本批把它反过来：
## **手柄按键（JoypadButton）与键鼠同一套 try_rebind / 冲突扫描 / 持久化**；
## 轴（摇杆/扳机）仍不开放（语义不同，见 `PAD_AXIS_BINDINGS`）。
static func run_pad_sections(t: T) -> void:
	t.suite("Keybind / 手柄重绑：真改生效（换弹 Y → GUIDE）")
	InputSetup.reset_all()
	# 换一个**出厂没人用**的键：GUIDE（手柄徽标键）。这同时覆盖了 PAD_LABELS
	# 表外兜底（"手柄 %d"）的路径。
	var ev_g := InputEventJoypadButton.new()
	ev_g.button_index = JOY_BUTTON_GUIDE
	var res: Dictionary = InputSetup.try_rebind("reload", 0, ev_g)
	t.eq(int(res["code"]), InputSetup.Bind.OK, "换弹 Y → GUIDE 返回 OK")
	t.eq(InputSetup.bound_pads("reload"), [JOY_BUTTON_GUIDE],
		"权威表里 reload 的手柄绑定已换成 GUIDE")
	t.eq(InputSetup.bound_pads("transform"), [JOY_BUTTON_LEFT_STICK],
		"别的动作一个字没动（原子性对手柄同样成立）")
	InputSetup.ensure_all()
	t.eq(_map_pad_buttons("reload"), [JOY_BUTTON_GUIDE],
		"运行时 InputMap 里 reload 的手柄键是 GUIDE")
	var y_free := true
	for a: String in InputSetup.PAD_BINDINGS:
		if a != "reload" and InputSetup.bound_pads(a).has(JOY_BUTTON_Y):
			y_free = false
	t.ok(y_free, "Y 不再属于 reload 以外的任何动作（旧键被剪干净）")

	t.suite("Keybind / 手柄重绑：撞键整条拒绝")
	# Y 此刻已经空了，但 X 被 boost 占用 —— 把 reload 改到 X 必须撞车。
	var ev_x := InputEventJoypadButton.new()
	ev_x.button_index = JOY_BUTTON_X
	var res2: Dictionary = InputSetup.try_rebind("reload", 0, ev_x)
	t.eq(int(res2["code"]), InputSetup.Bind.CONFLICT, "换弹改到 X 返回 CONFLICT")
	t.eq(str(res2["conflict"]), "boost", "报出占用者（boost）")
	t.eq(InputSetup.bound_pads("reload"), [JOY_BUTTON_GUIDE], "reload 保持 GUIDE 不变")

	t.suite("Keybind / 手柄重绑：锁定动作改不动 + 同键无事")
	var ev_b := InputEventJoypadButton.new()
	ev_b.button_index = JOY_BUTTON_GUIDE
	var r_locked: Dictionary = InputSetup.try_rebind("menu_back", 0, ev_b)
	t.eq(int(r_locked["code"]), InputSetup.Bind.RESERVED,
		"menu_back（防自锁）在 pad 表上同样 RESERVED")
	var ev_same := InputEventJoypadButton.new()
	ev_same.button_index = JOY_BUTTON_GUIDE
	t.eq(int(InputSetup.try_rebind("reload", 0, ev_same)["code"]), InputSetup.Bind.OK,
		"换成同一个键 = 无事发生（OK）")
	var ev_axis := InputEventJoypadMotion.new()
	ev_axis.axis = JOY_AXIS_TRIGGER_RIGHT
	ev_axis.axis_value = 1.0
	t.eq(int(InputSetup.try_rebind("reload", 0, ev_axis)["code"]), InputSetup.Bind.BAD_EVENT,
		"轴事件（JoypadMotion）不进重绑（摇杆/扳机保持出厂）")

	t.suite("Keybind / 手柄重绑：重启后还在（持久化）")
	InputSetup.clear_overrides_memory()
	InputSetup.ensure_all()
	t.eq(InputSetup.bound_pads("reload"), [JOY_BUTTON_Y],
		"内存清零 → 回出厂 Y")
	InputSetup.load_overrides()
	InputSetup.ensure_all()
	t.eq(InputSetup.bound_pads("reload"), [JOY_BUTTON_GUIDE],
		"读回 keybinds.cfg 后仍是 GUIDE")
	t.eq(_map_pad_buttons("reload"), [JOY_BUTTON_GUIDE], "运行时 InputMap 同步")
	InputSetup.reset_all()
	t.eq(InputSetup.bound_pads("reload"), [JOY_BUTTON_Y], "收尾：换弹回到出厂 Y")


## 运行时 map 里某动作的**键盘**绑定（physical_keycode 列表）。
static func _map_physical(action: String) -> Array:
	var out: Array = []
	for ev: InputEvent in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k != null:
			out.append(int(k.physical_keycode))
	return out


## 运行时 map 里某动作的**手柄按键**绑定（button_index 列表；轴不算）。
static func _map_pad_buttons(action: String) -> Array:
	var out: Array = []
	for ev: InputEvent in InputMap.action_get_events(action):
		var jb := ev as InputEventJoypadButton
		if jb != null:
			out.append(int(jb.button_index))
	return out


static func _shared(a: String, b: String) -> bool:
	for pair: Array in InputSetup.SHARED_KEYS_OK:
		if (str(pair[0]) == a and str(pair[1]) == b) \
				or (str(pair[0]) == b and str(pair[1]) == a):
			return true
	return false
