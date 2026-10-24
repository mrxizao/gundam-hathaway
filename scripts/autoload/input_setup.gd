extends Node
## 运行时保证输入映射存在。
##
## 为什么不只依赖 project.godot 的 [input] 段：那个段是序列化出来的
## Object(InputEventKey, ...) 字面量，任何一个属性名写错都会静默失效。
## 这里做一层幂等兜底 —— 已存在的 action 不会被动过，缺的才补。
##
## 键位表按需求重新排过：
##   - 加速（Shift）/ 悬停（Ctrl）/ 丢枪（R）/ 举盾（Z）都是新增模式键，
##     所以油门从 Shift·Ctrl 挪到了 `[` `]` 与鼠标滚轮。
##   - 开火改为鼠标左键（光束步枪）、右键（光束军刀劈砍）。
##   - 火神炮保留空格，浮游导弹保留 F。

## 键盘 / 鼠标按键类动作。俯仰按**操纵杆方向**命名，避免歧义：
##   pitch_nose_up   = 拉杆（S / ↓）→ 机头抬起
##   pitch_nose_down = 推杆（W / ↑）→ 机头下沉   ← 真实飞机操纵杆约定，Ace Combat 同款
##
## 关于 Q / F / R 三个键的改动（第三轮需求）：
##   Q = 发射浮游导弹（原 F），F = 举盾（原 Z），R = 光束步枪换弹（原 R=丢枪）。
##   被挤掉的两个功能各让了一步：
##     - 偏航从 Q/E 挪到 **Z/X**（Q 让给飞弹，E 空出来）
##     - 柯西的"丢枪脱锁"从 R 挪到 **G**（R 让给换弹）
const BINDINGS := {
	"pitch_nose_up": [KEY_S, KEY_DOWN],
	"pitch_nose_down": [KEY_W, KEY_UP],
	"roll_left": [KEY_A, KEY_LEFT],
	"roll_right": [KEY_D, KEY_RIGHT],
	"yaw_left": [KEY_Q],
	"yaw_right": [KEY_E],
	"throttle_up": [KEY_BRACKETRIGHT],
	"throttle_down": [KEY_BRACKETLEFT],
	"boost": [KEY_SHIFT],
	"hover": [KEY_CTRL],
	"fire_gun": [KEY_SPACE],
	"fire_missile": [KEY_F],
	"shield": [KEY_T],
	"reload": [KEY_R],
	# ⚠️ 1.2：**G 让给辅助飞行**（用户指定），所以丢枪不再有"直达键"——
	# 只剩 **R 长按 0.6 s**（键盘）与 **长按 Y**（手柄 = `reload`）。这是刻意的：
	# ⚠️ ★63-9 B6：手柄那一路原来是“长按 B”（= `shield`），已按用户要求删掉 ——
	# 举盾要一直按住，挂在它上面等于每次举盾都走一遍丢枪判定。
	# 丢枪不可逆，本来就该多花一点力气；而辅助飞行是随时会开关的东西，
	# 放在手指自然覆盖的 G 上更合理。
	# T 让给"举盾"之后，切换目标挪到 Tab。
	# 1v1 只有一个目标，这个功能本来就近乎无用（保留着，将来做多敌机时还要用）。
	"switch_target": [KEY_TAB],
	# 1.2 第十六轮：**数字键 1 – 9 = 直选右上角敌机列表里的第 n 架**（用户指定）。
	# 这一条在 §20.8 的"仍然欠着的"里挂了好几轮 —— 六轮以来基本是 1v1，
	# "选谁"无所谓；训练（四架靶机）与挑战（一波三架）一多起来，
	# `Tab` 只能一圈一圈转、鼠标要点中，**"我就想打第 3 架"没有直达入口**。
	#
	# ⚠️ **不是"只做 1/2/3"**：用户第二轮明确"不止 123，按数字键可以切换扫描到的敌机"。
	# 所以 1–9 全给上（小键盘一并绑，理由和 `confirm` 同时认 Enter 与小键盘 Enter 一样）。
	# 列表里**每一架都带号**，第 10 架起才退回 `Tab` 循环 —— 这一版场上一共也就几架，
	# 9 个槽位实际上永远不会用完，但"够不够用"不该由玩家去猜。
	# 0 键**故意不绑**：它没有对应的序号（第 10 架），绑上去只会变成"按了没反应"。
	#
	# ⚠️ 手柄没有数字键，所以这一列在手柄上留空：手柄的等价入口是
	# `switch_target`（十字键 ↑）循环 —— 帮助面板里那一行写的就是它，
	# 不会出现"说明书印着一个按不出来的键"（第十五轮 §2.4 那类事故）。
	"select_contact_1": [KEY_1, KEY_KP_1],
	"select_contact_2": [KEY_2, KEY_KP_2],
	"select_contact_3": [KEY_3, KEY_KP_3],
	"select_contact_4": [KEY_4, KEY_KP_4],
	"select_contact_5": [KEY_5, KEY_KP_5],
	"select_contact_6": [KEY_6, KEY_KP_6],
	"select_contact_7": [KEY_7, KEY_KP_7],
	"select_contact_8": [KEY_8, KEY_KP_8],
	"select_contact_9": [KEY_9, KEY_KP_9],
	"flares": [KEY_C],
	"look_back": [KEY_V],
	"toggle_invert": [KEY_I],
	#   Z   = **变形**（阿利宙斯巡航 ↔ 常态）。Q/E 给了偏航、X/Shift/Ctrl 各有归属，
	#         Z 是左手小指自然覆盖、且不与任何动作冲突的位置。
	#
	# ⚠️ **第十八轮：`lock_camera`（Alt）改名成 `missile_mode`**（用户指定）——
	#   原来的"锁定镜头开关"**并进了辅助飞行**：辅助开启且已锁定时，镜头自动跟住目标
	#   （见 `PlayerController._tick_assist`）。Alt 因此空出来，改成
	#   **导弹系统模式切换**：拦截 ⇄ 全弹发射（模式决定鼠标右键 / L1 干什么）。
	"missile_mode": [KEY_ALT],
	"transform": [KEY_Z],
	# 1.2 新增：**B = 选来袭威胁**（拦截目标）。
	# ⚠️ ★63-9 B6：这里原来还写着“B 长按仍然是丢枪”，那条已删
	#（丢枪只剩键盘 R / 手柄 Y 的长按）⇒ B 在键盘侧只属于 `select_threat` 一个动作。
	"select_threat": [KEY_B],
	# 1.2：**X** = 切换武器（光束步枪 ↔ 光束军刀）。X 之前没有任何归属。
	"switch_weapon": [KEY_X],
	# 1.2：**U** = 开始修复（用掉一个修复包）。U 之前没有归属。
	"repair": [KEY_U],
	# 辅助飞行（1.2）：**H**（键盘）+ **手柄 A**。A 在菜单里是'确认'，
	# 两者阶段互斥（菜单 vs 飞行），所以登记进 SHARED_KEYS_OK。
	"flight_assist": [KEY_G],
	# ---- 飞行踏板：载具系统（1.2）----
	#
	# 用户指定："踏板要有搭乘键和脱离键，类似载具系统。按键还能呼叫飞行踏板到自己的位置来。"
	#
	# ⚠️ **只有两个键，不是三个**：搭乘与呼叫是**同一个动作**（"C"= Call）——
	# 没板就呼叫到身边、板在附近就搭上去。拆成两个键会让玩家先想"我该按哪个"，
	# 而这两件事在体感上是同一件事："我要上板"。
	# 脱离是**共用 T（举盾）**：骑板时举盾本来就不可用（踏板形态禁用），
	# 所以同一个键在骑乘状态下改读成"脱离"—— 和"空格在骑板时改成踏板火神炮"
	# 是同一套做法（一钮两义、靠骑乘状态分）。
	#
	# ⚠️ **手柄上没有这两个键**：手柄 17 个键已经全满（见 `HANDOFF.md` §5.2），
	# 而"呼叫踏板"不像"使用武器"那样每局都用，所以按第十五轮"回头看"的先例
	# **退回键盘** —— `HELP_SECTIONS` 里手把那一列留空，HUD 会自动只印键盘文案。
	"ride_pedal": [KEY_N],
	"open_settings": [KEY_P],
	# 轮 25：**F1 = 第一人称 / 第三人称，随时切换**（用户指定）。
	#
	# 需求原文（用户，轮 25）：「把第一人称和第三人称切换按钮从设置菜单里面调到 F1 键，
	# 然后把眩晕警告先保留，但是隐藏着，以后我们可以把它放到别的地方去，
	# 现在先隐藏，做第一人称第三人称随意切换的形式。」
	# 手柄那一路是"长按 Back"，见 `PAD_HOLD["look_back"]`。
	#
	# ⚠️ 这条路**刻意不过眩晕门** —— 但门的部件一个都没删（`Stage.FPV_CONFIRM` /
	# `_open_fpv_confirm` / `FPV_CONFIRM_ROWS` / `Settings.FPV_WARNING`），
	# 只是设置页那一行已撤掉 ⇒ 弹窗从"唯一的入口"变成"暂时没有入口"。
	# 详见 `main_menu.gd` 里 `SETTING_ROWS` 的旁注。
	"toggle_fpv": [KEY_F1],
	# 轮 31：**M = 中央屏切换**（雷达 / 机体剪影 / 等高线地形图，用户指定）。
	# 与 `toggle_fpv` 同一套：只注册一个键，真正的状态机在 `Settings` 里。
	"cycle_dash_screen": [KEY_M],
	"confirm": [KEY_ENTER, KEY_KP_ENTER],
	"menu_back": [KEY_ESCAPE],
	"pause": [KEY_ESCAPE],
}

## 鼠标键类动作。
const MOUSE_BINDINGS := {
	"cockpit_freelook": [MOUSE_BUTTON_MIDDLE],
	"fire_primary": [MOUSE_BUTTON_LEFT],
	"fire_secondary": [MOUSE_BUTTON_RIGHT],
	"throttle_up": [MOUSE_BUTTON_WHEEL_UP],
	"throttle_down": [MOUSE_BUTTON_WHEEL_DOWN],
}
## ============================================================ 批 4 · 按键自定义（§4.8）
##
## 范围：**只做键鼠**（§4.8.5）—— 手柄 17 个入口已满、轴绑定是 `[轴, 方向]` 二元组，
## `PAD_BINDINGS` / `PAD_AXIS_BINDINGS` / `PAD_HOLD` 这一轮一个字都不动。
##
## 三层防自锁（§4.8.4，缺一不可）：
##   ① API 层   `try_rebind()` 对 `LOCKED_ACTIONS` 直接返回 RESERVED；
##   ② 加载层   `load_overrides()` 读到锁死动作的覆盖值就丢弃并 push_warning；
##   ③ 输入层   主菜单 `_input()` 第一行写死 Esc 的保险丝（**不经过 InputMap**）。

## 不允许重绑的动作。**这是防自锁的代码级防线**，不是"UI 里把那行画灰"——
## 灰的按钮挡不住一个被手改坏的配置文件。
const LOCKED_ACTIONS := ["menu_back", "pause", "confirm"]

## 重绑失败的原因。**返回码而不是 bool**——失败原因要能原样显示给玩家
##（"Tab 已被「切换目标」占用"才是可操作的；"重绑失败"不可操作）。
enum Bind { OK, CONFLICT, RESERVED, BAD_EVENT }

## 用户覆盖（可写，唯一新增的状态）。**空字典 = 完全等价现状**（零回归的证明方式）。
## ⚠️ 用 static var：`ensure_all()` / `_prune_action()` / 测试都在静态上下文里调它们，
## 改成实例字段会把这三个函数连带改成非静态。
## 结构：{ "action": [码, ...] }，键盘存 physical_keycode、鼠标存 button_index。
static var key_overrides := {}
static var mouse_overrides := {}
## 手柄按键覆盖（批 10："按键自定义系统还是再优化一下" —— 补上手柄重绑）。
## 结构同上：{ "action": [JoyButton 码, ...] }。**只覆盖按键不覆盖轴**
## （摇杆/扳机进 InputMap 要带正负号的 JoypadMotion，语义完全不同，
## 见 `PAD_AXIS_BINDINGS` 的注释 —— 那部分保持出厂固定）。
static var pad_overrides := {}

## 键位存档（§4.8.8）。**不塞进 settings.cfg**：那个文件归 Settings 管，
## 而 InputSetup 是第一个 autoload、先于它 ready —— 塞进去会引入反向依赖。
const KEYBINDS_PATH := "user://keybinds.cfg"


## 某个 action 的**当前权威**键位 = 出厂值 ∪ 用户覆盖。
## ⚠️⚠️ 所有"允许哪些事件"的判断**必须**走这里（§4.8.2）。
## 任何一处直接读 `BINDINGS.get(action, [])`，那一处的用户绑定就会被剪掉——
## 而症状是"改了没保存"，不是报错。这一条是本项最容易犯、也最难查的错。
static func bound_keys(action: String) -> Array:
	return key_overrides.get(action, BINDINGS.get(action, []))


static func bound_buttons(action: String) -> Array:
	return mouse_overrides.get(action, MOUSE_BINDINGS.get(action, []))


## 手柄按键的当前权威绑定 = 出厂值 ∪ 用户覆盖（批 10，与上两个同一套规矩）。
static func bound_pads(action: String) -> Array:
	return pad_overrides.get(action, PAD_BINDINGS.get(action, []))


## ---- 键名显示（KEY_LABELS 是批 4 新建的；此前第一列是手写死的）----
const KEY_LABELS := {
	KEY_ESCAPE: "Esc", KEY_ENTER: "Enter", KEY_KP_ENTER: "小键盘 Enter",
	KEY_TAB: "Tab", KEY_SPACE: "空格", KEY_SHIFT: "Shift", KEY_CTRL: "Ctrl", KEY_ALT: "Alt",
	KEY_W: "W", KEY_A: "A", KEY_S: "S", KEY_D: "D", KEY_Q: "Q", KEY_E: "E",
	KEY_R: "R", KEY_F: "F", KEY_T: "T", KEY_Z: "Z", KEY_X: "X", KEY_C: "C",
	KEY_V: "V", KEY_B: "B", KEY_N: "N", KEY_U: "U", KEY_I: "I", KEY_G: "G", KEY_P: "P",
	KEY_F1: "F1",
	KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→",
	KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
	KEY_1: "1", KEY_2: "2", KEY_3: "3", KEY_4: "4", KEY_5: "5",
	KEY_6: "6", KEY_7: "7", KEY_8: "8", KEY_9: "9",
	KEY_KP_1: "小1", KEY_KP_2: "小2", KEY_KP_3: "小3", KEY_KP_4: "小4", KEY_KP_5: "小5",
	KEY_KP_6: "小6", KEY_KP_7: "小7", KEY_KP_8: "小8", KEY_KP_9: "小9",
}

const MOUSE_LABELS := {
	MOUSE_BUTTON_LEFT: "鼠标左键", MOUSE_BUTTON_RIGHT: "鼠标右键",
	MOUSE_BUTTON_MIDDLE: "鼠标中键", MOUSE_BUTTON_WHEEL_UP: "滚轮上",
	MOUSE_BUTTON_WHEEL_DOWN: "滚轮下",
}


## 键码 → 显示名。表里没有的键码用 OS 兜底，**不许渲染成空白**——
## 空白在 UI 上读成"这个动作没绑键"。
static func key_label(key: int) -> String:
	return str(KEY_LABELS.get(key, OS.get_keycode_string(key)))


static func mouse_label(btn: int) -> String:
	return str(MOUSE_LABELS.get(btn, "鼠标 %d" % btn))


## 手柄按键码 → 显示名（批 10）。与 KEY_LABELS 同一套规矩：表外用编号兜底。
## ⚠️ 刻意写"键帽"而不是"手柄第 X 键"：玩家看的是自己手柄上的字母。
const PAD_LABELS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_DPAD_UP: "十字键↑", JOY_BUTTON_DPAD_DOWN: "十字键↓",
	JOY_BUTTON_DPAD_LEFT: "十字键←", JOY_BUTTON_DPAD_RIGHT: "十字键→",
}


static func pad_label(btn: int) -> String:
	return str(PAD_LABELS.get(btn, "手柄 %d" % btn))


## 动作 → 中文显示名（重绑页 / 冲突提示用）。**唯一来源**，调用方不许自己拼。
const ACTION_NAMES := {
	"cockpit_freelook": "驾驶舱环视",
	"pitch_nose_up": "拉杆抬头", "pitch_nose_down": "推杆低头",
	"roll_left": "左滚转", "roll_right": "右滚转",
	"yaw_left": "左偏航", "yaw_right": "右偏航",
	"throttle_up": "加油门", "throttle_down": "收油门",
	"boost": "加速模式", "hover": "悬停",
	"transform": "变形", "look_back": "回头看", "toggle_invert": "俯仰反转",
	"fire_primary": "使用当前武器", "fire_secondary": "拦截来袭飞弹",
	"switch_weapon": "切换武器", "reload": "换弹",
	"fire_gun": "火神炮", "fire_missile": "浮游导弹",
	"repair": "修复", "shield": "举盾", "ride_pedal": "呼叫 / 搭乘踏板",
	"flares": "干扰弹", "select_threat": "选来袭威胁",
	"flight_assist": "辅助飞行", "missile_mode": "导弹系统模式",
	"switch_target": "切换目标", "open_settings": "打开设置",
	"select_contact_1": "直选目标 1", "select_contact_2": "直选目标 2",
	"select_contact_3": "直选目标 3", "select_contact_4": "直选目标 4",
	"select_contact_5": "直选目标 5", "select_contact_6": "直选目标 6",
	"select_contact_7": "直选目标 7", "select_contact_8": "直选目标 8",
	"select_contact_9": "直选目标 9",
	# 轮 25：视角切换进了重绑页（`KEY_GROUPS`），所以必须有可读名 ——
	# 漏了这一行，重绑页那一格会**回退成原始键名 `toggle_fpv`**
	# （`action_name()` 的兜底是 `ACTION_NAMES.get(action, action)`）。
	"toggle_fpv": "第一人称 / 第三人称",
	# 轮 31：同样进了重绑页（`KEY_GROUPS`），所以同样必须有可读名 ——
	# 漏了它那一格会显示成原始键名 `cycle_dash_screen`（`action_name()` 的兜底）。
	"cycle_dash_screen": "中央屏切换",
}


static func action_name(action: String) -> String:
	return str(ACTION_NAMES.get(action, action))


## 动作 → 当前**全部**键位（键盘 + 鼠标），" / " 连接。重绑页与 HUD 键位列的唯一来源。
static func bind_label(action: String) -> String:
	var parts: Array[String] = []
	for k: int in bound_keys(action):
		parts.append(key_label(k))
	for b: int in bound_buttons(action):
		parts.append(mouse_label(b))
	return "未绑定" if parts.is_empty() else " / ".join(parts)


## 动作 → 「给玩家看的一个键」：取首个键盘键；纯鼠标动作退回鼠标键。
## （第二绑定如方向键/小键盘不占版面 —— 与旧说明书的紧凑写法一致。）
static func _kb_primary(action: String) -> String:
	var keys: Array = bound_keys(action)
	if not keys.is_empty():
		return key_label(int(keys[0]))
	var btns: Array = bound_buttons(action)
	if not btns.is_empty():
		return mouse_label(int(btns[0]))
	return "未绑定"


## 把 HELP_SECTIONS 条目的第一列（**spec**）算成给玩家看的文本。
## 重绑之后这一列必须跟着变，否则说明书立刻撒谎（§4.8.6）。
## spec 两种形态：
##   String → 字面文本（手柄专属行 / 没有对应动作的行，如「鼠标移动」）
##   Array  → 顺序拼接的**部件**，每个部件：
##     String                 → 字面文本（如 " 长按"）
##     ["act", a]             → 动作当前全部键位（bind_label）
##     ["kb", a]              → 动作的首个键盘键
##     ["kb2", a1, a2]        → 两个动作的首键，用 " / " 连（「W / S」）
##     ["n9", a1..a9]         → 九个直选动作：全是数字时紧凑成「1 – 9」
##     ["wheel2", up, down]   → 两个鼠标动作：恰为滚轮上下时紧凑成「滚轮」
## ⚠️ **三处同源**（§4.8.6）：HELP_SECTIONS 第一列 · 设置页按键行 · 重绑页行，
## 全部走这里 / bind_label()。任何一处自己拼字符串，自定义之后就会不一致。
static func help_text(item: Array) -> String:
	var first: Variant = item[0]
	if first is String:
		return str(first)
	var out := ""
	for part: Variant in first:
		if part is String:
			out += str(part)
			continue
		var p: Array = part
		match str(p[0]):
			"act":
				out += bind_label(str(p[1]))
			"kb":
				out += _kb_primary(str(p[1]))
			"kb2":
				var sep := " / " if p.size() < 4 else str(p[3])
				out += _kb_primary(str(p[1])) + sep + _kb_primary(str(p[2]))
			"n9":
				var digs := ""
				for i in range(1, p.size()):
					var keys: Array = bound_keys(str(p[i]))
					if keys.size() >= 1 and int(keys[0]) >= KEY_1 and int(keys[0]) <= KEY_9:
						digs += str(int(keys[0]) - KEY_1 + 1)
					elif keys.size() >= 1 and int(keys[0]) >= KEY_KP_1 and int(keys[0]) <= KEY_KP_9:
						digs += str(int(keys[0]) - KEY_KP_1 + 1)
					else:
						digs += _kb_primary(str(p[i]))
				out += "1 – 9" if digs == "123456789" else digs
			"wheel2":
				var up: Array = bound_buttons(str(p[1]))
				var down: Array = bound_buttons(str(p[2]))
				if up == [MOUSE_BUTTON_WHEEL_UP] and down == [MOUSE_BUTTON_WHEEL_DOWN]:
					out += "滚轮"
				else:
					var labels: Array[String] = []
					for b: int in up:
						labels.append(mouse_label(b))
					for b: int in down:
						labels.append(mouse_label(b))
					out += " / ".join(labels)
	return out


## ---- 重绑 API（§4.8.3）----

## 把 action 的第 slot 个绑定换成 ev。返回 {"code": Bind, "conflict": String}。
## ⚠️ **必须原子**：先在副本上推演（冲突扫描），成功才动内存；
## 写盘失败则整体回滚 —— 绝不留下"内存一套、存档一套"。
static func try_rebind(action: String, slot: int, ev: InputEvent) -> Dictionary:
	# 防自锁第①层：API 直接拒绝
	if LOCKED_ACTIONS.has(action):
		return {"code": Bind.RESERVED, "conflict": ""}
	var k := ev as InputEventKey
	var mb := ev as InputEventMouseButton
	# 手柄按键（批 10）：与键鼠同一套原子推演，只是换一张表。
	# ⚠️ 只收 JoypadButton 不收 JoypadMotion —— 轴是"摇杆/扳机"，
	# 不在本系统的重绑范围（见 pad_overrides 与 PAD_AXIS_BINDINGS 的注释）。
	var jb := ev as InputEventJoypadButton
	if k == null and mb == null and jb == null:
		return {"code": Bind.BAD_EVENT, "conflict": ""}
	if k != null and _is_modifier_key(k.physical_keycode):
		return {"code": Bind.BAD_EVENT, "conflict": ""}
	var is_key := k != null
	var is_pad := jb != null
	var code := int(k.physical_keycode) if is_key \
		else (int(jb.button_index) if is_pad else int(mb.button_index))
	var table: Dictionary = key_overrides if is_key \
		else (pad_overrides if is_pad else mouse_overrides)
	var defaults: Dictionary = BINDINGS if is_key \
		else (PAD_BINDINGS if is_pad else MOUSE_BINDINGS)
	if not defaults.has(action):
		return {"code": Bind.BAD_EVENT, "conflict": ""}
	# 原子性：先在副本上推演
	var cand := {}
	for a: String in table:
		cand[a] = (table[a] as Array).duplicate()
	var cur: Array = (cand.get(action, defaults[action]) as Array).duplicate()
	if slot < 0 or slot >= cur.size():
		return {"code": Bind.BAD_EVENT, "conflict": ""}
	if int(cur[slot]) == code:
		return {"code": Bind.OK, "conflict": ""}  # 换成同一个键 = 无事发生
	cand[action] = cur
	cur[slot] = code
	var other := _find_conflict(cand, defaults, action)
	if other != "":
		return {"code": Bind.CONFLICT, "conflict": other}
	# 推演全部通过：落地 → 让运行时 map 跟上 → 存档
	table[action] = cur
	ensure_all()
	if not save_config():
		table.erase(action)
		ensure_all()
		push_warning("keybinds.cfg 写盘失败，本次重绑已回滚（内存与存档保持一致）")
		return {"code": Bind.BAD_EVENT, "conflict": ""}
	return {"code": Bind.OK, "conflict": ""}


## 纯修饰键不能当绑定（只按下 Shift 不应该被当成一次绑定）。
static func _is_modifier_key(key: int) -> bool:
	return [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK,
		KEY_NUMLOCK, KEY_SCROLLLOCK].has(key)


## 候选状态下，action 的键位有没有撞上别的动作（SHARED_KEYS_OK 的刻意共用除外）。
## ⚠️ 查的是**权威表**（覆盖 ∪ 出厂）的候选拷贝，不是 const ——
## 否则自定义就成了"一键一动作"铁律的绕过口（§4.8.10；F 键事故的教训）。
static func _find_conflict(cand: Dictionary, defaults: Dictionary, action: String) -> String:
	var mine: Array = cand.get(action, defaults.get(action, []))
	for code: int in mine:
		for a: String in defaults:
			if a == action:
				continue
			var theirs: Array = cand.get(a, defaults.get(a, []))
			if theirs.has(code) and not _pair_shared_ok(action, a):
				return a
	return ""


static func _pair_shared_ok(a: String, b: String) -> bool:
	for pair: Array in SHARED_KEYS_OK:
		if (str(pair[0]) == a and str(pair[1]) == b) \
				or (str(pair[0]) == b and str(pair[1]) == a):
			return true
	return false


## 本行恢复默认。
static func reset_action(action: String) -> void:
	key_overrides.erase(action)
	mouse_overrides.erase(action)
	pad_overrides.erase(action)
	ensure_all()
	save_config()


## 全部恢复默认。出厂 const 表是唯一来源（§4.8.2 的三条理由之一）。
static func reset_all() -> void:
	key_overrides = {}
	mouse_overrides = {}
	pad_overrides = {}
	ensure_all()
	save_config()


## 测试 / 模拟重启用：只清**内存**覆盖，不动存档（配合 load_overrides() 读回）。
static func clear_overrides_memory() -> void:
	key_overrides = {}
	mouse_overrides = {}
	pad_overrides = {}


## 覆盖表的只读快照（测试断言用；外部不许直接摸 static var）。
static func overrides_snapshot() -> Dictionary:
	return {"keys": key_overrides.duplicate(), "mouse": mouse_overrides.duplicate(),
		"pad": pad_overrides.duplicate()}


## 存当前覆盖。空覆盖也写（显式"这是出厂状态"，跟"没有存档"区分开）。
static func save_config() -> bool:
	var cf := ConfigFile.new()
	for a: String in key_overrides:
		cf.set_value("keys", a, key_overrides[a])
	for a: String in mouse_overrides:
		cf.set_value("mouse", a, mouse_overrides[a])
	for a: String in pad_overrides:
		cf.set_value("pad", a, pad_overrides[a])
	return cf.save(KEYBINDS_PATH) == OK


## 启动时读覆盖（`_ready()` 里在 `ensure_all()` **之前**调）。
## 坏数据一律**丢弃 + push_warning**（自愈，和 Settings 夹取索引同套路）：
##   - 锁死动作的覆盖值（防自锁第②层：配置文件被手改坏也能自愈）
##   - 退役动作（不许复活 —— 否则被清掉的旧动作又回来吃键，F 键事故的同类）
##   - 不在出厂表里的动作 / 类型不对的值 / 槽位数对不上的
##   - 加载完再跑一次冲突扫描，撞车的覆盖值整条丢弃
static func load_overrides() -> void:
	key_overrides = {}
	mouse_overrides = {}
	pad_overrides = {}
	var cf := ConfigFile.new()
	if cf.load(KEYBINDS_PATH) != OK:
		return  # 没有存档 = 出厂键位（最常见的路径）
	var tables := [
		["keys", key_overrides, BINDINGS],
		["mouse", mouse_overrides, MOUSE_BINDINGS],
		["pad", pad_overrides, PAD_BINDINGS],
	]
	for row: Array in tables:
		var section: String = row[0]
		var table: Dictionary = row[1]
		var defaults: Dictionary = row[2]
		if not cf.has_section(section):
			continue
		for a: String in cf.get_section_keys(section):
			if LOCKED_ACTIONS.has(a):
				push_warning("keybinds.cfg：%s 不允许重绑，覆盖值已丢弃" % a)
				continue
			if RETIRED_ACTIONS.has(a):
				push_warning("keybinds.cfg：%s 已退役，覆盖值已丢弃" % a)
				continue
			if not defaults.has(a):
				continue
			var raw: Array = cf.get_value(section, a, [])
			var clean: Array = []
			var ok := true
			for v: Variant in raw:
				var code := int(v)
				if code <= 0:
					ok = false
					break
				clean.append(code)
			if not ok or clean.is_empty() \
					or clean.size() != (defaults[a] as Array).size():
				push_warning("keybinds.cfg：%s 的覆盖值格式不对，已丢弃" % a)
				continue
			table[a] = clean
	for a: String in key_overrides.duplicate():
		if _find_conflict(key_overrides, BINDINGS, a) != "":
			push_warning("keybinds.cfg：%s 的覆盖值与其它动作撞键，已丢弃" % a)
			key_overrides.erase(a)
	for a: String in mouse_overrides.duplicate():
		if _find_conflict(mouse_overrides, MOUSE_BINDINGS, a) != "":
			push_warning("keybinds.cfg：%s 的覆盖值与其它动作撞键，已丢弃" % a)
			mouse_overrides.erase(a)
	for a: String in pad_overrides.duplicate():
		if _find_conflict(pad_overrides, PAD_BINDINGS, a) != "":
			push_warning("keybinds.cfg：%s 的手柄覆盖与其它动作撞键，已丢弃" % a)
			pad_overrides.erase(a)

## 手柄按键。
##
## **只用按键**：摇杆与扳机是"轴"，进 InputMap 要写成 InputEventJoypadMotion 还得区分正负，
## 可读性很差。轴直接在 PlayerController 里读（见 `_pad_axis` / `_pad_throttle`），
## 只有离散动作才走这里 —— 这样也和键盘/鼠标共用同一套 InputMap 与同一条测试。
##
## 布局（**1.2 第十五轮改过** —— 老板指定"右手武器 · 左手导弹"）：
##   左摇杆 = 俯仰 + 滚转、右摇杆 X = 偏航、右摇杆 Y = 油门
##   **R2 使用当前武器 / R1 火神炮（按住） · L2 浮游导弹 / L1 拦截来袭飞弹**
##   A 确认(出击) / B 举盾(B 同时也是返回) / X 加速 / Y 换弹
##
## ⚠️ 第十五轮为什么这么换（三处改动首尾相接，**没有新增键、没有动作失去入口**）：
##   1. **拦截从 R2 轴挪到 L1** —— 原来它和"开火"挤在同一只手上（R1/R2），
##      而拦截恰恰经常要和开火同时发生；挪到左手之后**双手分家**：右手武器、左手导弹。
##   2. **"使用当前武器"从 R1 挪到 R2 轴** —— 主武器放扳机上有行程感（步枪点射 / 军刀劈砍）。
##   3. **火神炮从 L1 挪到 R1** —— 唯一空出来的位置（它是"按住连发"，肩键更省力）。
##   ⚠️ R2 从"拦截"改成"当前武器"之后，`fire_primary` **必须从这张表搬进轴表**
##     （扳机是轴，见下方 `PAD_AXIS_BINDINGS`），否则 R2 会同时属于两个动作。
const PAD_BINDINGS := {
	"fire_gun": [JOY_BUTTON_RIGHT_SHOULDER],       # R1 火神炮（按住连发）
	# 拦截来袭飞弹：**L1**（第十五轮从 R2 轴挪过来）。
	# 点按 = 拦一发；按住 = 自动拦最危险的 2 枚（`InterceptAuto`）。
	# ⚠️ 它与**鼠标右键**共用 `fire_secondary` 这一个动作，
	#    读取点靠 `PlayerController._intercept_pad_mode()` 按设备分叉。
	"fire_secondary": [JOY_BUTTON_LEFT_SHOULDER],  # L1 拦截来袭飞弹
	"shield": [JOY_BUTTON_B],                      # B 举盾（菜单里同时是返回）
	"reload": [JOY_BUTTON_Y],                      # Y 换弹
	# 干扰弹：1.2 从 **Back 挪到十字键 ↓**（用户要求"每个方向拿来做功能性按键"）。
	# 1.1 之前它在 L3（按下左摇杆）→ 1.1 退到 Back → 1.2 退到十字键 ↓。
	# `discard_rifle`（丢枪脱锁，仅柯西）**不在这张表里，但手柄上有入口**：
	# **长按 Y 0.6 s** —— 由 `PlayerController._tick_holds()` 读 `reload` 的长按，
	# 和键盘的“R 长按”是同一个机制。所以它**不是**“手柄做不了的动作”。
	# ⚠️ ★63-9 B6：原来写的是“长按 B（= `shield`）”，已按用户要求删掉。
	# `look_back`（按住回头看）1.2 起在 **Back** 上 —— 用户点名"这个键还没用上"。
	# 加速曾经绑在 **L3（按下左摇杆）** 上 —— 用户实测"太反人类了"：
	# 加速是要长时间按住的动作，而按下摇杆会同时把杆推歪，边加速边精确压杆根本做不到。
	# 现在挪到 **X 键**（拇指自然停在的地方，和 A 确认互不干扰）。
	"boost": [JOY_BUTTON_X],                       # X 加速（按住）
	"hover": [JOY_BUTTON_RIGHT_STICK],             # R3 悬停（按一次切换性质的动作，可以留在摇杆上）
	# 变形：L3。和干扰弹原来占的是同一个键 —— 1.1 把 L3 给了变形（见上）。
	"transform": [JOY_BUTTON_LEFT_STICK],          # L3 变形（点按）
	# `missile_mode`（导弹系统模式切换，Alt）**手柄上是十字键 ←** —— 键位**没变**
	# （它原来绑的就是 `lock_camera`），所以菜单那条"横向导航读十字键"的路不用改键位，
	# 只要把菜单读的动作名一起换掉（见 `MainMenu._nav_x`）。
	# ---- 十字键：**1.2 起全部改成功能键**（用户要求）----
	#
	# 原来它复用的是四个"操纵"动作（俯仰/滚转），好处是主菜单不用另写一套导航。
	# 用户明确要求"别拿来控制镜头和机体方向了，每个方向拿来做功能性按键" ——
	# 于是四个方向各自接管一个**战斗功能**：
	#   ↑ 切换目标（原来只有键盘 Tab）  ↓ 干扰弹（原来在 Back）
	#   ← 导弹系统模式（原来只有键盘 Alt）  → 军刀/武器（1.2 下一轮接武器选择）
	#
	# ⚠️ **主菜单导航必须另找方向源**：菜单是靠 `roll_left/right` 与
	# `pitch_nose_up/down` 这几个动作选项目的，十字键摘掉之后手柄就只剩左摇杆 ——
	# `_nav_x()` / `_nav_y()` 本来就读摇杆轴（见 main_menu），所以导航不受影响，
	# 但**飞行时的手柄配平（trim）从此没有了**：那是刻意的取舍，
	# 用户要的是功能键而不是"又一个操纵入口"。
	"switch_target": [JOY_BUTTON_DPAD_UP],
	"flares": [JOY_BUTTON_DPAD_DOWN],
	"missile_mode": [JOY_BUTTON_DPAD_LEFT],   # 十字键 ← 导弹系统模式（拦截 ⇄ 全弹发射）
	"switch_weapon": [JOY_BUTTON_DPAD_RIGHT],   # 十字键 →（四个方向里最后空着的那一个）
	# 回头看：**Back**（"返回键"用来"回头看"是最自然的映射），
	# 它到 1.2 之前一直是键盘独占（V）—— 用户点名"这个键还没用上"。
	"look_back": [JOY_BUTTON_BACK],
	"confirm": [JOY_BUTTON_A],                     # A 确认 / 出击
	# 辅助飞行同样是 A —— 点按确认、**长按 0.45 s** 开关辅助（HoldAction 区分）。
	"flight_assist": [JOY_BUTTON_A],
	"menu_back": [JOY_BUTTON_B],
	# 暂停：手柄上对应的就是 Esc。**Start 在菜单里是"设置"、在战斗里是"暂停"** ——
	# 两者分处不同阶段（主菜单 stage ≠ INTRO/FIGHT），永远不会同时生效。
	"pause": [JOY_BUTTON_START],
	"open_settings": [JOY_BUTTON_START],
	# 十字键复用四个"操纵"动作。
	# ⚠️ **1.2 已废弃**：用户要求"别拿来控制镜头和机体方向了，每个方向拿来做功能性按键"，
	# 四个方向现在在下面各自绑了功能动作（切换目标 / 干扰弹 / 导弹模式 / 切换武器）。
	# 这一行留在注释里是为了记住"为什么主菜单曾经不用另写导航"。
	# "roll_left": [JOY_BUTTON_DPAD_LEFT],
	# "roll_right": [JOY_BUTTON_DPAD_RIGHT],
	# "pitch_nose_up": [JOY_BUTTON_DPAD_UP],
	# "pitch_nose_down": [JOY_BUTTON_DPAD_DOWN],
}

## 扳机在 Godot 里是**轴**不是按键（L2 = TRIGGER_LEFT、R2 = TRIGGER_RIGHT），
## 所以单独一张表。每条是 `[轴, 方向]`，方向 +1 表示"按到底"。
##
## ⚠️ 第十五轮：`fire_secondary` 从这张表**搬回了按键表**（拦截挪到 L1），
##    而 `fire_primary` 从按键表**搬进**这里（"使用当前武器"挪到 R2）。
##    两张表是互补的：**同一个动作只能出现在一张表里**
##    （否则 `_prune_action()` 会把另一张表加的事件当成"多余绑定"剪掉）。
const PAD_AXIS_BINDINGS := {
	"fire_primary": [[JOY_AXIS_TRIGGER_RIGHT, 1]],     # R2 使用当前武器（光束步枪 / 光束军刀）
	"fire_missile": [[JOY_AXIS_TRIGGER_LEFT, 1]],      # L2 浮游导弹（一次扳机 3 发）
}

## 「加入锁定组」（批 1 · 多目标锁定）的长按时长（秒）。**键鼠与手柄共用这一个数**。
##
## ⚠️ 为什么必须同源：键鼠是"长按 Tab"、手柄是"长按十字键 ↑"，两边若各写一个数，
## 迟早会变成一种**隐藏的难度差**（"手柄要按住更久才加得上"），而且没人会注意到。
##
## ⚠️ 为什么是 0.45 而不是设计文档里写的 0.4：`suite_gamepad` 有一条硬断言
## 「长按时长 > 0.4（防误触）」，而 0.4 **正好不满足**它。宁可把这个数抬一档，
## 也不要把那条防误触的闸放松 —— 那条闸保护的是"点按切目标"这个高频动作。
const ADD_LOCK_HOLD_SECS := 0.45

## 手柄上的**长按二义**：点按 = 那个动作，长按 = `hold_action`。
##
## 为什么需要这张表：**手柄 17 个入口在 1.2 就已经全满**（见 `PAD_BINDINGS`），
## 想再给一个动作加入口，只能"点按 / 长按分家" —— 这条路工程里早就走通了
##（长按 L3 = 修复、长按十字键 → = 踏板、长按十字键 ↑ = 加锁、长按 Back = 第一人称）。
## ⚠️ 丢枪**不在这张表里**：它是 `PlayerController._tick_holds()` 直接读 `reload` 的长按
##（键盘 R / 手柄 Y），与 `shield` 已经分家（★63-9 B6）。
##
## ⚠️ 写成**数据**是为了三处同源：`PlayerController._tick_holds()` 迭代它、
## `HELP_SECTIONS` 的手柄列照它写、`suite_gamepad` 直接断言它。
## 以前这三处各写各的，正是"说明书印着一个按不出来的键"那类事故的温床。
##
## 2026-09-21 加前两条的直接原因：老板要「**把古斯塔夫和梅萨都做手柄适配**」。
## 这两台量产机与 ACE 机的差别只有两处，而**两处在手柄上原来都是空的**：
##   ① **能骑飞行踏板**（ACE 机不可骑）—— 手柄原来没有"呼叫踏板"的路；
##   ② **修复**（每场 3 个修复包）—— 手柄原来也没有。
## 第三条（加入锁定组）是批 1 多目标锁定的输入，理由见 `ADD_LOCK_HOLD_SECS`。
const PAD_HOLD := {
	# 点按 L3 = 变形，长按 = **修复**。
	# ⚠️ 敢把 L3 的长按给修复，是因为**古斯塔夫 / 梅萨 / 柯西 / 佩涅罗佩 都没有变形**
	#（只有阿利宙斯有），点按在那四台上本来就是无效的 —— 长按正好补上量产机最缺的一个。
	"transform": {
		"hold_action": "repair", "secs": 0.6, "glyph": "长按 L3",
	},
	# 点按十字键 → = 切换武器，长按 = **呼叫 / 搭乘飞行踏板**。
	# ⚠️ 选十字键而不是摇杆按下（L3/R3）：十字键是**离散**的，
	# 长按它不会像"按住摇杆"那样同时把机体推歪（加速从 L3 挪走的教训）。
	"switch_weapon": {
		"hold_action": "ride_pedal", "secs": 0.6, "glyph": "长按十字键 →",
	},
	# 点按十字键 ↑ = 切换主目标（**不变**），长按 = **加入锁定组**（批 1）。
	# ⚠️ 触发键选十字键 ↑ 而不是新键：手柄 17 个入口早就满了（见上面的表头注释），
	# 而 ↑ 的"点按语义"（切主目标）与"长按语义"（把它也纳入火控）是同一族的动作，
	# 玩家容易建立直觉 —— 这比塞给一个完全无关的键好。
	"switch_target": {
		"hold_action": "add_lock", "secs": ADD_LOCK_HOLD_SECS, "glyph": "长按十字键 ↑",
	},
	# 轮 25：**点按 Back = 按住回头看（不变），长按 Back = 第一人称 / 第三人称切换**。
	#
	# ⚠️ 这一条**和上面三条不一样**，值得单独交代：
	#   `look_back` 本身就是**按住型**动作（按住不放才回头看），所以长按阈值
	#   **必须明显长于一次正常的回头**，否则"瞟一眼背后"就会顺手把视角切了。
	#   因此这里用 **1.2 s**，而不是别处的 0.6 s —— 0.6 s 只是"看了一眼"，
	#   1.2 s 才是"有意按住"。（`HoldAction` 只在**按住期间**越过阈值时触发一次，
	#   松手不会补一次点按，所以不会连带触发回头看。）
	#
	# 手柄 17 个入口早就满了，没有空键可给，所以只能复用 —— 这一条是用户指定的
	#（"长按回头键，那个手柄按钮 4"）。
	"look_back": {
		"hold_action": "toggle_fpv", "secs": 1.2, "glyph": "长按 Back",
	},
}

const DEADZONE := 0.2

## 已废弃、需要从运行时 map 与 project.godot 里彻底清掉的旧动作。
## 光"不再使用"是不够的：只要它还留在 InputMap 里，绑过的键就会被它吃掉一半。
##   - controls_help：游戏内说明面板已撤掉，改成把键位印在右下角装备旁边
##   - restart：第二轮把"再战一局"绑到 R，后来改用 confirm；现在 R 归"换弹"，
##     留着它会让 R 同时属于两个动作（正是 F 那个 bug 的同类）
const RETIRED_ACTIONS := ["controls_help", "restart",
	# 第十八轮：`lock_camera` 退役 —— 它的功能**并进了辅助飞行**（辅助开启且已锁定时，
	# 镜头自动跟住目标），键位 Alt / 十字键 ← 转给 `missile_mode`。
	# ⚠️ 必须写进这张表：光改 `BINDINGS` 不够，`project.godot` 里固化过的那条还在，
	# Alt 会继续被它吃掉 —— "一个键属于两个动作"是本工程反复栽过的坑。
	"lock_camera",
	# 1.2：`discard_rifle` 不再是一个 InputMap 动作 —— 丢枪只由"长按 R / 长按 B"
	# 的代码路径直接调函数（`PlayerController._tick_holds`），所以它必须从这里清掉。
	# ⚠️ 光从 BINDINGS 里删是不够的：project.godot 里固化过的那条**还在**，
	# G 键会继续被它吃掉（用户实测："G 键为什么还有丢枪，g 键和丢枪无关"）。
	"discard_rifle"]

## 故意共用同一个物理件的动作对。ESC 既是暂停也是返回，两者分处不同阶段、不会同时生效，
## 所以显式登记在这里 —— 有了它，"一个键不得同时属于两个动作"这条检查才敢开成硬规则，
## 真正的手滑重复绑定（例如 F 同时是举盾和飞弹）就会被立刻抓出来。
##
## 手柄同理，而且手柄上"一键两用"比键盘更常见（按键本来就少）：
##   - `pause` / `open_settings` 都在 **Start** 上：菜单里是设置、战斗里是暂停；
##   - `menu_back` / `shield` 都在 **B** 上：菜单里是返回、战斗里是举盾。
## 两条都是**阶段互斥**的，不会在同一帧被两个动作同时读到。
const SHARED_KEYS_OK := [["pause", "menu_back"], ["pause", "open_settings"], ["menu_back", "shield"],
	# 手柄 A：菜单里是"确认"，飞行里是"长按开辅助飞行" —— 阶段互斥
	["confirm", "flight_assist"]]

## 给主菜单与游戏内帮助面板共用的**操作说明展示表**。
## 放在这里而不是各写一份：键位改一次就该两处同时变，否则迟早对不上。
##
## 结构：{ "title": 分组名, "items": [[键位spec, 作用, 手柄键位], ...] }
## ⚠️ 批 4 起**第一列是 spec 不是文本**：String = 字面文本，Array = 由
## `help_text()` 按 `bound_*()` 现算（§4.8.6 —— 重绑之后说明书不许撒谎）。
## 第三项留空 = 手柄做不了这个动作，提示会退回键盘文案（见 `hint()`）。
## 这份表就是"检测到手柄就切换提示"的数据来源。
##
## ⚠️ 手柄那一列必须**和 `PAD_BINDINGS` / `PAD_AXIS_BINDINGS` 对得上**。
## 之前这里写着"十字键 ↑↓ 收/加油门"、"V 十字键 ← 回头看"，
## 而十字键其实绑在俯仰/滚转上、油门在手柄上根本没有入口 ——
## 说明书印着一个按不出来的键，比不写还糟。现在油门给了右摇杆 Y。
## ⚠️ **这张表是要给玩家看的，必须和 `BINDINGS` 逐条对得上。**
## 它曾经很过时（右键还写着"光束军刀"，而 1.2 早把右键改成了拦截飞弹；
## 军刀搬到了"X 切换武器后的左键"），本表已按 1.2 的**实际读取点**重写：
## 判据不是"绑了什么键"，而是 `PlayerController._read_weapon_input()` 里真的读了什么。
const HELP_SECTIONS := [
	{
		"title": "飞行",
		"items": [
			[[["kb2", "pitch_nose_down", "pitch_nose_up"]], "推杆低头 / 拉杆抬头", "左摇杆 ↑↓"],
			[[["kb2", "roll_left", "roll_right"]], "左 / 右滚转", "左摇杆 ←→"],
			[[["kb2", "yaw_left", "yaw_right"]], "左 / 右偏航", "右摇杆 ←→"],
			[[["kb2", "throttle_down", "throttle_up", " "], " / ", ["wheel2", "throttle_up", "throttle_down"]], "收 / 加油门", "右摇杆 ↑↓"],
			[[["kb", "boost"]], "加速模式（速度上限 ×1.5）", "X"],
			[[["kb", "hover"]], "悬停（空中定住）", "R3"],
			[[["kb", "transform"]], "变形（阿利宙斯 巡航 ↔ 常态 · 冷却 4 秒）", "L3"],
			[[["kb", "look_back"]], "按住回头看", "Back"],
			[[["act", "cockpit_freelook"]], "按住环视驾驶舱，松开回正", ""],
			[[["kb", "toggle_invert"]], "俯仰反转开关", ""],
		],
	},
	{
		"title": "武器",
		"items": [
			# 1.2 第二十六轮：**古斯塔夫00 多了第三件武器（腕部榴弹炮）**，
			# 所以这两行的文案跟着从"步枪 / 军刀"改成"当前机体能切到的那几件"。
			# ⚠️ 描述列**不许再长**：它不折行，超过面板宽度会被右边缘切掉（实测过）。
			[[["act", "fire_primary"]], "使用当前武器（步枪 / 腕部榴弹炮 / 军刀）", "R2"],
			[[["kb", "switch_weapon"]], "切换武器（步枪 ⇄ 榴弹 ⇄ 军刀 · 榴弹 5 发 / 70 伤害）", "十字键 →"],
			[[["kb", "reload"]], "光束步枪换弹", "Y"],
			[[["kb", "fire_gun"]], "火神炮（无限弹 · 按住连发）", "R1"],
			[[["kb", "fire_missile"]], "浮游导弹（需锁定 · 一次三发 · 弹夹 150 自动换弹）", "L2"],
			# ⚠️ 第十五轮：拦截从 R2 挪到 **L1**，键位列因此从"R2"改成"L1"。
			# ⚠️ **这一列只能放短标签**：面板第一列宽 112 px，描述从 x+112 起画且**不折行**
			#    （见 `MainMenu._draw_help_panel`），"L1（点按拦一发·按住自动）"这种写法
			#    会和后面的描述**直接叠字**。所以"按住 = 自动拦截"单独起一行。
			[[["act", "fire_secondary"]], "拦截来袭飞弹（拦截模式下点中即发射）", "L1"],
			["L1 按住", "自动拦截：每秒拦最危险的 2 枚", ""],
			[[["kb", "repair"]], "修复机体（每场 3 个修复包）", "长按 L3"],
			[[["kb", "shield"]], "举盾（按一次持续 5 秒 · 冷却 1 秒）", "B（点按）"],
			# ⚠️ 1.2 飞行踏板：**这两行只在骑乘状态下生效**（一钮两义）。
			# 2026-09-21：手柄那一列**不再是空的**了 —— 老板要"把古斯塔夫和梅萨都做手柄适配"，
			# 而这两台量产机的招牌就是"能骑踏板"（ACE 机不可骑），手柄却原来没有入口。
			# 现在走 `InputSetup.PAD_HOLD`：**长按十字键 →**（点按仍是切武器）。
			[[["kb", "ride_pedal"]], "呼叫 / 搭乘飞行踏板（量产机专用 · ACE 机不可骑）", "长按十字键 →"],
			[[["kb", "ride_pedal"], " 骑板时"], "脱离飞行踏板（举盾键 T 也脱离）", "长按十字键 →（骑板时）／ B"],
			[[["kb", "fire_gun"], " 骑板时"], "改成**踏板的火神炮**（机体自己的火神炮暂不可用）", "R1（骑板时）"],
			[[["kb", "flares"]], "干扰弹", "十字键 ↓"],
			[[["kb", "reload"], " 长按"], "丢弃步枪 · 仅柯西（长按 0.6 s，HUD 有进度提示）", "长按 Y"],
		],
	},
	{
		"title": "锁定 / 系统",
		"items": [
			["鼠标移动", "准星（决定光束/火神炮方向）· 罩住敌机即锁定", ""],
			[[["kb", "select_threat"]], "选来袭飞弹作拦截目标（选中后 HUD 常驻显示 TTI）", ""],
			# ⚠️ 这一行的长度就是面板能容下的上限：加一句"开着时打出的导弹可对撞拦截"
			# 就会被右边缘切掉（实测）。拦截的说法已经在"鼠标右键"那一行里了。
			[[["kb", "flight_assist"], " 长按"], "辅助驾驶 · 镜头跟住锁定目标（长按再关）", "长按 A"],
			# ---- 辅助驾驶 · 平移模式（2026-09-22）----
			# 辅助开启后的操控换挡：WASD/QE/Shift 的语义整体切到"位移"。
			# ⚠️ 两种情形**保持飞行操纵、Shift = 超级加速**：阿利宙斯巡航形态，
			# 以及**骑飞行踏板**（2026-09-28 用户要求）—— 第三行写明。
			# ⚠️ 描述列**尽量不要超过约 24 个全角字符** —— 这条口径来自
			# **已删除**的主菜单底部说明面板（批 24：面板不折行，超了会被右边缘切掉，实测）。
			# 删面板之后本表**没有绘制消费者**（`controls_help` 已进 `RETIRED_ACTIONS`，
			# 剩下的只有测试在数条数）⇒ 它不是硬法律；但说明面板若复活，
			# 它就是唯一的口径来源，所以不要删。
			["辅助驾驶中", "WASD / 左摇杆 = 前后左右", "左摇杆"],
			["辅助驾驶中", "QE / 右摇杆 = 上升与下降", "右摇杆"],
			["辅助驾驶中", "Shift / X = 闪避冲刺（点按）· 巡航/骑板 = 超级加速", "X"],
			# 倒飞（★63-9 · D2）：平移模式下 **CTRL / R3** 从"悬停"改读成"倒着飞"开关
			#（那一支本来就不读 `hover`，见 `_read_translate_input`）。底速反向之后
			# W/S 的语义自然互换：W 的修正是沿屏幕前的加法 ⇒ 变成减速；S 变成加速。
			["辅助驾驶中", "Ctrl / R3 = 反向巡航（再按恢复）· W 减速 / S 加速", "R3"],
			[[["kb", "missile_mode"]], "导弹系统：拦截 ⇄ 全弹发射", "十字键 ←"],
			["全弹发射模式", "L1 / 右键 = 100 发 · 60 s 冷却", ""],
			[[["kb", "switch_target"]], "切换目标", "十字键 ↑"],
			# 批 1（多目标锁定）：长按把候选敌机加入锁定组。
			# ⚠️ 手柄那一列**必须**逐字等于 `PAD_HOLD["switch_target"]["glyph"]` ——
			# `suite_gamepad` 会拿它做反向检查（"表里写了长按，面板就必须真有一行"）。
			[[["kb", "switch_target"], " 长按"], "加入锁定组（最多 3 个 · 火力按人数分散）", "长按十字键 ↑"],
			# 第十六轮：右上角敌机列表 + 数字键直选（用户指定）。
			# ⚠️ 手柄那一列**不是空的**：手柄没有数字键，但十字键 ↑ 循环的是同一份名单，
			# 所以手柄模式下这一行会显示成"十字键 ↑ 循环" —— 真话，不是空白。
			[[["n9", "select_contact_1", "select_contact_2", "select_contact_3", "select_contact_4", "select_contact_5", "select_contact_6", "select_contact_7", "select_contact_8", "select_contact_9"]], "选中右上角敌机列表里的第 n 架（列表每一架都带号）", "十字键 ↑ 循环"],
			[[["kb", "open_settings"]], "设置：画面尺寸 / 音量（主菜单）", "Start"],
			# 轮 25：F1 = 第一人称 / 第三人称**随时切换**（用户指定）。
			# ⚠️ 手柄那一列**不是空的**：手柄上挂在"长按 Back"（`PAD_HOLD["look_back"]`），
			# 与 `switch_target` 那一行同一套写法 —— `suite_gamepad` 会拿
			# `PAD_HOLD[...]["glyph"]` 做**反向检查**（表里写了，面板就必须真印着它）。
			# 描述列**不必**提眩晕：这条路根本不走门。
			[[["kb", "toggle_fpv"]], "第一人称 / 第三人称 随时切换", "长按 Back"],
			# ⚠️ 描述列**不许再长**：它不折行，超过面板宽度会被右边缘切掉（这条踩过）。
			# 所以三模式只写三个短名，不写"（雷达 / 机体剪影 / 等高线地形图）"全称。
			[[["kb", "cycle_dash_screen"]], "中央屏切换（雷达 / 剪影 / 等高线）", ""],
			[[["kb", "confirm"]], "确认 · 出击 · 结算后回主菜单", "A"],
			[[["kb", "pause"]], "暂停（战斗中）· 菜单里可返回主菜单", "Start"],
			[[["kb", "menu_back"]], "主菜单里退出游戏", "B（主菜单）"],
		],
	},
]


func _ready() -> void:
	# ⚠️ 顺序不能换（§4.8.8）：先读覆盖，权威表才是"出厂 ∪ 用户覆盖"；
	# 反过来的话 ensure_all() 会把用户绑定当"多余事件"剪掉（改了没保存的根因）。
	load_overrides()
	ensure_all()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	pad_connected = not Input.get_connected_joypads().is_empty()


## ---------------------------------------------------------------- 输入设备
##
## 用户要求"检测到手柄就切换成手柄的提示"。做法是**追踪当前在用哪种设备**：
## 收到手柄事件就切到手柄提示，收到键鼠事件就切回键鼠提示。
## 不是"插了手柄就永远显示手柄" —— 那样插着手柄用键盘玩的人会被误导。
signal input_device_changed(using_gamepad: bool)
signal gamepad_connected(connected: bool)

var pad_connected := false
var using_gamepad := false


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	pad_connected = not Input.get_connected_joypads().is_empty()
	gamepad_connected.emit(pad_connected)
	if pad_connected:
		_use_gamepad(true)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_use_gamepad(true)
	elif event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventMouseMotion:
		_use_gamepad(false)


func _use_gamepad(on: bool) -> void:
	if using_gamepad == on:
		return
	using_gamepad = on
	input_device_changed.emit(on)


## 按当前设备挑一条提示文案。
## `pad` 留空表示"这个动作手柄做不了"，那就退回键盘文案。
##
## 注意**不是 static**：它要读实例上的 `using_gamepad`。
## 调用方写 `InputSetup.hint(...)` —— InputSetup 是 autoload 实例，静态上下文里也拿得到。
func hint(keyboard: String, pad := "") -> String:
	if using_gamepad and pad != "":
		return pad
	return keyboard


## 幂等地让运行时 InputMap 与下面的键位表**完全一致**：缺的补上、多的剪掉。
## 返回本次新增的 action 名列表（测试用）。
##
## ⚠️ 为什么必须"剪掉"而不能只"补齐"（踩过的坑）：
## project.godot 的 [input] 段是固化副本，改键位表时它不会自动更新。
## 只做补齐的话，旧绑定会一直留在 map 里。第三轮把飞弹从 F 挪到 Q 之后，
## `fire_missile` 就同时拥有 F 和 Q 两个键 —— 玩家按 F 举盾，结果**同时打出了浮游导弹**
## 并弹出"未锁定目标"。所以这里以代码里的 BINDINGS 为唯一权威，多余事件一律剪掉。
static func ensure_all() -> Array[String]:
	var added: Array[String] = []
	for action: String in all_actions():
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
			added.append(action)
		_prune_action(action)
	for a: String in RETIRED_ACTIONS:
		if InputMap.has_action(a):
			InputMap.erase_action(a)
	for action: String in BINDINGS:
		for key: int in bound_keys(action):
			if not _has_physical_key(action, key):
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)
	for action: String in MOUSE_BINDINGS:
		for btn: int in bound_buttons(action):
			if not _has_button(action, btn):
				var ev := InputEventMouseButton.new()
				ev.button_index = btn
				InputMap.action_add_event(action, ev)
	for action: String in PAD_BINDINGS:
		for btn: int in bound_pads(action):
			if not _has_pad_button(action, btn):
				var ev := InputEventJoypadButton.new()
				ev.button_index = btn
				InputMap.action_add_event(action, ev)
	for action: String in PAD_AXIS_BINDINGS:
		for pair: Array in PAD_AXIS_BINDINGS[action]:
			var axis := int(pair[0])
			var sign := float(pair[1])
			if not _has_pad_axis(action, axis, sign):
				var ev := InputEventJoypadMotion.new()
				ev.axis = axis
				ev.axis_value = sign
				InputMap.action_add_event(action, ev)
	return added


static func _has_pad_button(action: String, btn: int) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		var jb := ev as InputEventJoypadButton
		if jb != null and jb.button_index == btn:
			return true
	return false


static func _has_pad_axis(action: String, axis: int, sign: float) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		var jm := ev as InputEventJoypadMotion
		if jm != null and jm.axis == axis and absf(jm.axis_value - sign) < 0.01:
			return true
	return false


## 删掉某个 action 上不属于当前键位表的事件。
static func _prune_action(action: String) -> void:
	var allowed_keys: Array = bound_keys(action)
	var allowed_buttons: Array = bound_buttons(action)
	# ⚠️ 手柄也要走权威表（批 10）：原来这里直接读 PAD_BINDINGS const，
	# 等于"手柄重绑永远被剪掉" —— 与 bound_keys 注释里那个"改了没保存"同款错。
	var allowed_pads: Array = bound_pads(action)
	var allowed_axes: Array = PAD_AXIS_BINDINGS.get(action, [])
	# 必须 duplicate：erase_event 会改到正在遍历的那个数组
	for ev: InputEvent in InputMap.action_get_events(action).duplicate():
		var k := ev as InputEventKey
		if k != null:
			if not (allowed_keys.has(k.physical_keycode) or allowed_keys.has(k.keycode)):
				InputMap.action_erase_event(action, ev)
			continue
		var b := ev as InputEventMouseButton
		if b != null:
			if not allowed_buttons.has(b.button_index):
				InputMap.action_erase_event(action, ev)
			continue
		var jb := ev as InputEventJoypadButton
		if jb != null:
			if not allowed_pads.has(jb.button_index):
				InputMap.action_erase_event(action, ev)
			continue
		var jm := ev as InputEventJoypadMotion
		if jm != null:
			var ok := false
			for pair: Array in allowed_axes:
				if int(pair[0]) == jm.axis and absf(float(pair[1]) - jm.axis_value) < 0.01:
					ok = true
			if not ok:
				InputMap.action_erase_event(action, ev)


static func all_actions() -> Array[String]:
	var out: Array[String] = []
	for a: String in BINDINGS:
		if not out.has(a):
			out.append(a)
	for a: String in MOUSE_BINDINGS:
		if not out.has(a):
			out.append(a)
	return out


static func _has_physical_key(action: String, key: int) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k != null and (k.physical_keycode == key or k.keycode == key):
			return true
	return false


static func _has_button(action: String, button: int) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		var b := ev as InputEventMouseButton
		if b != null and b.button_index == button:
			return true
	return false
