extends Node
## 主菜单**鼠标操控**真机判据图探针（★63-19）。
##
## ## 为什么必须有它
##
## 无头回归里 `_draw()` 不产生像素（RenderingServer 是 dummy），
## 所以 `suite_menu_mouse` 证明的是**接线与算术**；而
## 「改了之后画面**一模一样**」与「鼠标真的把光标挪过去了」只有真渲染能看出来。
##
## ## 跑法（**不能加 `--headless`**，加了拿不到图）
##   Godot_v4.7.1-stable_win64_console.exe --path <工程目录> res://tests/menuprobe.tscn \
##       -- --tag=post [--out=res://]
##
## ## 它产什么
##   ① 逐页截图 `<out>/_mp_<tag>_<页>.png` —— 用来做**改造前/后 A/B**（视觉零位移的判据）；
##   ② 鼠标三步截图（悬停 / 左键 / 右键）—— 用来证明鼠标真的接通了；
##   ③ stdout 上每一步的**状态量**（`stage` / `mode_index`），人眼与脚本都能核。
##
## ⚠️ 条件固定：分辨率钉 1600×900、每帧抓图前等 `frame_post_draw`、
## 页面顺序固定 —— 两次跑的差异只该来自工程代码本身。

const PAGES := [MainMenu.Stage.MODE, MainMenu.Stage.DIFFICULTY, MainMenu.Stage.SUIT,
	MainMenu.Stage.MAP, MainMenu.Stage.FPV_CONFIRM]

var _tag := "run"
var _out := "res://"
## `pages` = 只拍逐页截图（**这一档能在改造前的代码上跑** —— 视觉零位移 A/B 用它）；
## `mouse` = 再加鼠标三步（要改造后的代码：`_list_geometry` / `row_rect`）。
var _mode := "mouse"
var _menu: MainMenu = null
var _bad := 0


func _ready() -> void:
	_parse_args()
	if DisplayServer.get_name() == "headless":
		push_error("menuprobe 必须真渲染运行 —— 去掉 --headless 再来。")
		get_tree().quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	await _run()
	print("[menuprobe] 完：tag=%s mode=%s  截图前缀=%s_mp_%s_  异常=%d" % [
		_tag, _mode, _out, _tag, _bad])
	get_tree().quit(1 if _bad > 0 else 0)


func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"--tag": _tag = kv[1]
			"--out": _out = kv[1]
			"--mode": _mode = kv[1]


func _run() -> void:
	# ★63-19d：先把两条**环境量**钉住，否则偶发红会被误读成"功能坏了"。
	await _await_window_stable()
	await _await_focus()
	_menu = MainMenu.new()
	add_child(_menu)
	await _settle()
	# ⚠️ `_ready()` 里 `set_process(false)`（进游戏前菜单不跑逻辑）——
	# 探针要它跑 `_process`（`_read_input()` 在里面），所以这里显式打开。
	_menu.set_process(true)
	_menu.open_menu(0.0)
	await _settle()
	_menu.set("active", true)
	await _settle()
	print("[menuprobe] 开菜单：visible=%s active=%s size=%s stage=%d lockout=%.2f" % [
		str(_menu.visible), str(_menu.get("active")), str(_menu.size),
		int(_menu.get("stage")), float(_menu.get("input_lockout"))])
	# 坐标诊断（★必须打出来）：窗口逻辑尺寸与帧缓冲尺寸**不是一回事**（本机 160% 缩放），
	# 一旦 `warp_mouse` 的单位与 `Control` 的坐标系不一致，悬停就会**静默失效**
	#（点得到、划不过去），而日志上看不出任何异常。
	var w := get_window()
	print("[menuprobe] 坐标：window=%s  framebuffer=%s  content_scale=%.2f  screen_scale=%.2f  os_mouse=%s" % [
		str(w.size), str(w.get_visible_rect().size), w.content_scale_factor,
		DisplayServer.screen_get_scale(), str(DisplayServer.mouse_get_position())])

	# ---- 诊断档：只发一发滚轮，然后**逐帧**看意图活了几帧、哪一帧闸门关着 ----
	# 用来定位"滚轮时红时绿"（★63-19 实测确有过 4 异常）。
	if _mode == "wheel":
		await _wheel_diag()
		return

	# ---- A/B 拍摄模式：把**除被测变量之外的一切**钉死 ----
	#
	# ⚠️⚠️ 这两行是实测撞出来的，缺一条 A/B 就会给出**看似有说服力的错结论**：
	#   ① 关逻辑（`_time` 不再累加）—— `_draw()` 里的星空与机体卡的脉冲高亮
	#      都读 `_time`。不钉死，两次跑的相位不同 ⇒ MODE/难度/地图各差 ~700 个像素
	#      （最大通道差 6~9）。那是**动画相位**，不是版式。
	#   ② 关输入 —— 改造后悬停是**真生效**的，而 OS 光标恰好停在卡片区上
	#      ⇒ `suit_index` 被挪走 ⇒ SUIT 页差了 **106 万**像素（最大通道差 191）。
	#      看起来像"版式被改坏了"，真相是"新功能按设计工作了"。
	if _mode == "pages":
		_menu.set_process(false)
		_menu.set_process_input(false)
		print("[menuprobe] --mode=pages ⇒ 钉死 `_time` + `_choice_age` / `_text_tilt` / 输入"
			+ "（只关 `_process` 不够：那两个量会冻在「光标当时在哪儿」的值上）")
		_pin_visuals()

	# ---- ① 逐页截图（**这一组是视觉零位移 A/B 的判据**）----
	for st: int in PAGES:
		_menu.set("stage", st)
		# `pages` 模式关了 `_process`，所以要自己把重绘排上
		#（正常路径是 `_process()` 末尾的 `queue_redraw()`）。
		_menu.set("_time", 0.0)
		_pin_visuals()
		_menu.queue_redraw()
		await _settle()
		await _shot("_mp_%s_page%d.png" % [_tag, st])
		# 几何量只在改造后打印（改造前没有 `_list_geometry()`）—— 走 `call()` 动态派发，
		# 这样**同一份探针**能在两个版本上跑（否则改前的脚本编译不过，也就拿不到 A/B 图）。
		if _menu.has_method("_list_geometry"):
			var g: Dictionary = _menu.call("_list_geometry")
			print("[menuprobe] 页 %2d：stage=%d  focus=%d  count=%d  first=%d  shown=%d" % [
				st, int(_menu.get("stage")), int(_menu.call("_focus_index")),
				int(g["count"]), int(g["first"]), int(g["shown"])])
		else:
			print("[menuprobe] 页 %2d：stage=%d（改造前：无 `_list_geometry()`）" % [
				st, int(_menu.get("stage"))])

	# ---- ② 鼠标三步 ----
	if _mode == "pages":
		print("[menuprobe] --mode=pages ⇒ 跳过鼠标三步（改造前的代码没有这套接口）")
		return
	await _mouse_steps()


## 逐帧诊断：一发滚轮之后，意图在**第几帧**被设、第几帧被消费、第几帧被"过期清掉"。
##
## ⚠️ 为什么需要它：`_process()` 末尾有一行**无条件**的 `_mouse_wheel = 0`
##（"一帧租约"）。鼠标事件若在 `_process()` **之后**到达，意图要活到下一帧才被消费 ——
## 而中间只要有**一帧闸门不开**（`active` 掉 / `input_lockout` 没走完 / `_await_release` 为真），
## 那一行就会把滚轮**静默吞掉**（日志上只看得到"事件收到了、索引没动"）。
## 这条路径不看逐帧帧号是查不出来的。
func _wheel_diag() -> void:
	_menu.set("stage", MainMenu.Stage.MODE)
	_menu.set("mode_index", 1)
	await _settle()
	var c := _row_center(MainMenu.Stage.MODE, 1)
	print("[wheel] nav_axis(MODE)=%d  MODE 页项数=%d  row中心=%s" % [
		int(_menu.call("nav_axis", MainMenu.Stage.MODE)),
		int((_menu.call("_list_geometry") as Dictionary)["count"]), str(c)])
	print("[wheel] 前置：stage=%d mi=%d wheel=%d intent=%d iframe=%d active=%s lockout=%.3f release=%s" % [
		int(_menu.get("stage")), int(_menu.get("mode_index")), int(_menu.get("_mouse_wheel")),
		int(_menu.get("_mouse_intent")), int(_menu.get("_mouse_intent_frame")),
		str(_menu.get("active")), float(_menu.get("input_lockout")),
		str(_menu.get("_await_release"))])
	await _send_button(c, MOUSE_BUTTON_WHEEL_DOWN)
	for i in 12:
		print("[wheel] f%02d F=%d stage=%d mi=%d wheel=%d mi_d=%d intent=%d active=%s lock=%.3f rel=%s" % [
			i, Engine.get_process_frames(), int(_menu.get("stage")),
			int(_menu.get("mode_index")), int(_menu.get("_mouse_wheel")),
			int(_menu.get("_mi_d")), int(_menu.get("_mouse_intent")),
			str(_menu.get("active")), float(_menu.get("input_lockout")),
			str(_menu.get("_await_release"))])
		await get_tree().process_frame
	print("[wheel] 完：stage=%d mi=%d（期望 0 / 2）" % [
		int(_menu.get("stage")), int(_menu.get("mode_index"))])


## 鼠标：悬停移焦点 → 左键推进 → 右键返回 → 滚轮移焦点。
##
## 每一步都把**状态量**打出来（不是"看起来动了"）：脚本核 stdout、人眼看图。
##
## ⚠️⚠️ **坐标单位这件事必须讲清**（本机实测踩到）：`Input.warp_mouse()` 收的是
## **物理像素**，而 `Control.get_local_mouse_position()` 返回的是**逻辑像素**
##（本机窗口 2560×1600、逻辑视口 1600×1000，比值 1.6）。不换算就会落到别处 ——
## 而且**不报错**：实测送 (800,615) 落到逻辑 (500,384)，正好在第 0 行上，
## 于是"悬停没反应"看起来像功能坏了。所以统一走 `_warp()`。
func _mouse_steps() -> void:
	# 模式页：把光标放到第 2 行的中心
	_menu.set("stage", MainMenu.Stage.MODE)
	_menu.set("mode_index", 0)
	await _settle()
	var c := _row_center(MainMenu.Stage.MODE, 2)
	print("[menuprobe] 目标逻辑像素 = %s（模式页第 2 行中心）" % str(c))

	var hovered := await _pin(c, "mode_index", 2, "悬停把 mode_index 挪到 2")
	_state("悬停后")
	print("[menuprobe] 悬停后 mode_index=%d（期望 2）" % int(_menu.get("mode_index")))
	_expect(hovered, "悬停把焦点挪到第 2 行")
	await _shot("_mp_%s_hover.png" % _tag)

	# 左键 = 推进。⚠️ 点**第 0 行**（对战模式）：它是唯一有子页的分组 ⇒ 进 BATTLE。
	# （点第 2 行「训练模式」也推进，但它是单项分组 ⇒ 直接进机体页 —— 第一版我把
	#   期望写成 BATTLE 而报了假红，正是"期望必须从数据推、不能拍"的例子。）
	await _send_motion(_row_center(MainMenu.Stage.MODE, 0))
	await _send_button(_row_center(MainMenu.Stage.MODE, 0), MOUSE_BUTTON_LEFT)
	var to_battle := await _until(
		func() -> bool: return int(_menu.get("stage")) == MainMenu.Stage.BATTLE,
		"左键把 stage 推到 BATTLE")
	_state("左键后")
	print("[menuprobe] 左键后 stage=%d（期望 %d=BATTLE）" % [
		int(_menu.get("stage")), MainMenu.Stage.BATTLE])
	_expect(to_battle, "左键 = 推进到对战模式子页")
	await _shot("_mp_%s_click.png" % _tag)

	# 右键 = 返回上一层
	await _send_motion(_row_center(MainMenu.Stage.BATTLE, 0))
	await _send_button(_row_center(MainMenu.Stage.BATTLE, 0), MOUSE_BUTTON_RIGHT)
	var to_mode := await _until(
		func() -> bool: return int(_menu.get("stage")) == MainMenu.Stage.MODE,
		"右键把 stage 退回 MODE")
	_state("右键后")
	print("[menuprobe] 右键后 stage=%d（期望 %d=MODE）" % [
		int(_menu.get("stage")), MainMenu.Stage.MODE])
	_expect(to_mode, "右键 = 返回上一层")
	await _shot("_mp_%s_back.png" % _tag)

	# 滚轮 = 移动焦点（不动页面）
	_menu.set("stage", MainMenu.Stage.MODE)
	_menu.set("mode_index", 1)
	await _settle()
	var cw := _row_center(MainMenu.Stage.MODE, 1)
	# ⚠️ 滚轮是**相对量**：起点不钉死，外来 motion 先挪一格、滚轮再挪一格 ⇒ 读数变 +2。
	await _pin(cw, "mode_index", 1, "滚轮前把焦点钉在第 1 行")
	await _send_button(cw, MOUSE_BUTTON_WHEEL_DOWN)
	var down_ok := await _until(func() -> bool: return int(_menu.get("mode_index")) == 2,
		"滚轮下一格 ⇒ mode_index 2")
	_state("滚轮下后")
	print("[menuprobe] 滚轮下一格：mode_index=%d（期望 2）" % int(_menu.get("mode_index")))
	_expect(down_ok, "滚轮 = 移动焦点")
	await _send_button(cw, MOUSE_BUTTON_WHEEL_UP)
	var up_ok := await _until(func() -> bool: return int(_menu.get("mode_index")) == 1,
		"滚轮上一格 ⇒ mode_index 1")
	_state("滚轮上后")
	print("[menuprobe] 滚轮上一格：mode_index=%d（期望 1）" % int(_menu.get("mode_index")))
	_expect(up_ok, "……上下都认")

	# 机体页：点第 2 张卡 —— 验"槽位 → 名单下标"那一次换算
	_menu.set("stage", MainMenu.Stage.SUIT)
	_menu.set("suit_index", 0)
	await _settle()
	var cc := _row_center(MainMenu.Stage.SUIT, 1)
	var card_ok := await _pin(cc, "suit_index", 1, "机体页悬停第 1 张卡 ⇒ suit_index 1")
	_state("卡片悬停后")
	print("[menuprobe] 机体页悬停第 1 张卡：suit_index=%d（期望 1）" % int(_menu.get("suit_index")))
	_expect(card_ok, "机体页点第 1 张卡 ⇒ 选中第 1 台")
	await _shot("_mp_%s_card.png" % _tag)


# ---------------------------------------------------------------- 工具

## 等某个**结果**出现（最多 `max_frames` 帧）。
##
## ⚠️⚠️ **不能用"固定等 N 帧"**（本机实测：滚轮那条时红时绿）：
## `Input.parse_input_event()` 会把事件丢进缓冲，投递的帧数不定 —— 等 3 帧有时够、
## 有时不够。判据必须盯**结果**，不是盯时间。
func _until(pred: Callable, what: String, max_frames := 30) -> bool:
	for i in max_frames:
		await get_tree().process_frame
		if bool(pred.call()):
			return true
	push_error("[menuprobe] %d 帧内等不到：%s" % [max_frames, what])
	_bad += 1
	return false

## 等窗口尺寸**稳定**（连续 3 帧不变）。
##
## ⚠️ `DisplayServer.window_set_size()` 要**几帧**才真正生效。没稳定时
## `_mouse_scale()` 算出的比例是错的 ⇒ 发出去的事件坐标整体偏移 ⇒ 悬停算错行。
func _await_window_stable() -> void:
	var prev := Vector2i(-1, -1)
	var same := 0
	while same < 3:
		await get_tree().process_frame
		same = (same + 1) if get_window().size == prev else 0
		prev = get_window().size
	print("[menuprobe] 窗口稳定：%s  换算比例=%s" % [str(prev), str(_mouse_scale())])


## 等窗口**拿回焦点**。
##
## ⚠️ 窗口失焦时鼠标事件会被丢弃 ⇒ "必须收到事件"的判据（悬停/点击）偶发红。
## 本工程**常有并行会话**（另一个 AI 会话可能弹窗口抢焦点）⇒ 必须显式等。
func _await_focus() -> void:
	for i in 180:
		if DisplayServer.window_is_focused():
			return
		await get_tree().process_frame
	# ⚠️ 这是**环境**问题（并行会话 / 别的窗口在抢），**不是判据失败** ⇒
	# 只警告、**不计入 `_bad`**。窗口若一直失焦，鼠标判据自己会被 `_until` 抓到，
	# 不会漏检 —— 所以这里不需要用"计异常"的方式兜底。
	print("[menuprobe] 环境警告：180 帧内窗口仍未获得焦点（有别的窗口在抢？）")


## 物理像素 / 逻辑像素 的比值（本机 = 1.6）。**每次都现算** —— 换台机器就变了。
func _mouse_scale() -> Vector2:
	var w := get_window()
	var vis := w.get_visible_rect().size
	if vis.x <= 0.0 or vis.y <= 0.0:
		return Vector2.ONE
	return Vector2(w.size) / vis


## 这个节点上有没有叫 `name` 的属性。
##
## ⚠️ 不能直接 `_menu.get(name)`：属性不存在时 Godot 会**报错**。
## 也不能写 `if name in _menu` —— GDScript 没有这种写法。只能翻属性表。
func _has_prop(name: String) -> bool:
	for p in _menu.get_property_list():
		if str(p["name"]) == name:
			return true
	return false


## 把**随"帧数 / 真实指针位置"漂移的渲染量**钉死（A/B 模式专用）。
##
## ⚠️⚠️ 只钉 `_time` **不够** —— 实测同一份 `main_menu.gd` 连跑三次，每页差 2.4k~22k 像素。
## 漂的是这两个（都在 `_process()` 里更新）：
##   · `_choice_age` —— 选中行文字按它做最多 **1.08×** 缩放（`MENU_VISUALS.focus_scale`）；
##   · `_text_tilt`  —— 指针倾斜：`tilt_target(get_local_mouse_position(), …)`
##                     **读的是真实光标位置** ⇒ **用户在动鼠标**、或光标恰好停在某行的
##                     三角区内，渲染结果就会不一样。
## 关掉 `_process` 只是把它们**冻结**，冻结在哪个值取决于「前面跑过几帧 + 光标在哪儿」
## ⇒ 必须显式归零。归零后连跑三次逐字节相同（实测）。
func _pin_visuals() -> void:
	if _has_prop("_choice_age"):
		_menu.set("_choice_age", 0.0)
	if _has_prop("_pointer_tilt_active"):
		_menu.set("_pointer_tilt_active", false)
	if _has_prop("_text_tilt"):
		_menu.set("_text_tilt", Vector2.ZERO)
	# ⚠️⚠️ 提示文案（`⚙ 设置（Start）` vs `⚙ 设置（P）`、底部手柄字形 vs 键盘字形）
	# 由 `InputSetup.using_gamepad` 决定，而它**被真实键鼠事件翻来翻去**
	#（`input_setup.gd` 的 `_input()`：键鼠一动就 `_use_gamepad(false)`）
	# ⇒ **用户在动鼠标，同一页渲染出来的字形就不一样**（实测差 ~15k 像素，且只差
	#   最顶/最底两条提示带 —— 中间菜单区一个像素都不差）。
	# 两道：① 关掉 `InputSetup` 的输入，不再被真实事件翻；② 把值钉成一位。
	var setup := get_node_or_null("/root/InputSetup")
	if setup != null:
		setup.set_process_input(false)
		setup.set_process_unhandled_input(false)
		setup.set("using_gamepad", false)


## 把焦点**钉**到某个值上：反复重发**同一条** motion，读到 `want` 即停。
##
## ⚠️⚠️ 为什么要重发：探针**不真挪 OS 光标**（见 `_send_motion()`），于是真实光标停在窗口里，
## 系统/用户任何一次真实移动都会送一发**外来** `InputEventMouseMotion`；产品侧只认事件自带的
## `position` ⇒ 外来事件会按**它自己的坐标**改 `mode_index`/`suit_index`。
## 实测读数：`悬停后 mode_index=0（期望 2）`、`滚轮下一格=3（期望 2）` —— 都是外来事件干的。
##
## 重发是**幂等**的（焦点只能被设成同一个值）⇒ 收敛即停，**不削弱判据**：
## 真缺陷下重发 12 次也到不了 `want`，`_expect()` 照样红。
func _pin(pos: Vector2, key: String, want: int, what: String) -> bool:
	var tries := 0
	for i in 12:
		tries += 1
		await _send_motion(pos)
		if int(_menu.get(key)) == want:
			# ⚠️ 重发过不止一次 ⇒ 说明有**外来** motion 在抢（真实光标在动）。
			# 打印出来，读日志的人才知道这一轮的环境不干净。
			if tries > 1:
				print("[menuprobe] 环境提示：%s 重发 %d 次才钉住（真实光标在动？）" % [what, tries])
			return true
	push_error("[menuprobe] 12 次重发后仍到不了 %s=%d：%s" % [key, want, what])
	return false


## 把 OS 光标挪到**逻辑**坐标 `pos` 上。
func _warp(pos: Vector2) -> void:
	Input.warp_mouse(pos * _mouse_scale())


## warp + **等 OS 光标真的到位**。
##
## ⚠️⚠️ `Input.warp_mouse()` 只是"发个请求"：Windows 的光标移动是**异步消息**，
## 命令发出后要**好几帧**光标才真挪过去。不等它就发事件 ⇒ 菜单那侧
## `Control.get_local_mouse_position()` 读到的还是**旧位置** ⇒
## 悬停算错行 ⇒ 间歇性"悬停没反应 / 点错行"。
##
## ★63-19 实测三次修正才落到这条：先是误判成"`parse_input_event` 投递帧数不定"，
## 再是误判成"滚轮被 `_process()` 的无条件清零吞掉"（那条**确实**存在，是第二个 bug），
## 最后逐帧诊断才看清 —— **两个 bug 叠在一起，各自都只造成偶发**。
func _warp_wait(pos: Vector2) -> void:
	_warp(pos)
	for i in 30:
		if _menu.get_local_mouse_position().distance_to(pos) < 2.0:
			return
		await get_tree().process_frame
	push_error("[menuprobe] warp 30 帧后光标仍未到 %s（现在 %s）" % [
		str(pos), str(_menu.get_local_mouse_position())])
	_bad += 1


## 某一页第 `i` 行（**绘制/逻辑坐标系**）的中心像素。
##
## ⚠️ 用 `Object.call()` **动态派发**而不是 `MainMenu.row_rect(...)`：后者的方法名在
## **编译期**就要存在，而改造前的 `main_menu.gd` 根本没有它 ⇒ 同一份探针编译不过，
## A/B 的两张图也就没法用同一套条件拍出来。动态派发把"有没有这个方法"推到运行期。
func _row_center(st: int, i: int) -> Vector2:
	_menu.set("stage", st)
	var mm: Object = _menu
	var g: Dictionary = mm.call("_list_geometry")
	var r: Rect2 = mm.call("row_rect", _menu.size, g, i)
	return r.get_center()


## 等逻辑帧 + 一次真渲染，让 `_draw()` 与 `_process()` 都跑过。
func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## 抓当前画面存 PNG。
func _shot(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		push_error("取画面失败：get_viewport().get_texture() 为空")
		_bad += 1
		return
	var img := tex.get_image()
	if img == null:
		push_error("取画面失败：get_image() 为空")
		_bad += 1
		return
	var path := _out + suffix
	var err := img.save_png(path)
	if err != OK:
		push_error("存图失败 err=%d → %s" % [err, path])
		_bad += 1
		return
	print("[menuprobe] 图 → %s (%d×%d)" % [path, img.get_width(), img.get_height()])


## 闸门四件套 + 意图状态 —— 鼠标"收得到但没反应"时，先看这四个量。
##
## `_read_input()` 只在 `active and input_lockout <= 0 and not _await_release`（且 visible）
## 时才跑 ⇒ 任何一个false，意图就会被"一帧租约"作废，表现是**完全没反应**。
func _state(tag: String) -> void:
	print("[menuprobe]   状态[%s] stage=%d visible=%s active=%s lockout=%.2f release=%s wheel=%d intent=%d" % [
		tag, int(_menu.get("stage")), str(_menu.visible), str(_menu.get("active")),
		float(_menu.get("input_lockout")), str(_menu.get("_await_release")),
		int(_menu.get("_mouse_wheel")), int(_menu.get("_mouse_intent"))])


func _send_motion(pos: Vector2) -> void:
	# ★63-19c：**不再真挪 OS 光标**（`Input.warp_mouse`）——
	# 产品侧已改成读 `event.position`，光标在哪**不影响判定**；
	# 而真挪光标反而会**额外**产生一发 OS 自己的 motion（异步、时机不定），
	# 那一发带着**旧**坐标进来 —— 正是"悬停偶发算错行"的根源。
	# 现在这条路径是**纯确定性**的：探针说什么位置，菜单就按什么位置算。
	var ev := InputEventMouseMotion.new()
	# ⚠️⚠️ **必须乘 `_mouse_scale()`**：`Viewport` 会把输入事件的 `position`
	# 从 **OS 物理像素**换算成 **视口逻辑像素**（本机 2560×1600 → 1600×1000，比值 1.6）。
	# 直接用逻辑坐标发 ⇒ 菜单读到的是 `pos / 1.6` ⇒ 悬停落到**别的行**，且**不报错**。
	# ★63-19 实测：发 (800,505)，菜单收到 (500,315.6)。
	var upos := pos * _mouse_scale()
	ev.position = upos
	ev.global_position = upos
	ev.relative = Vector2.ZERO
	Input.parse_input_event(ev)
	await get_tree().process_frame
	_state("motion后")


## 发一个鼠标按键（左/右键自动补一发 release）。
##
## ⚠️⚠️ **`warp := false` 是给滚轮用的**：滚轮分支根本不读光标位置
##（`_handle_mouse()` 只看 `button_index`），但 `_warp()` 会让系统产生
## **真实的 WM_MOUSEMOVE** ⇒ 菜单收到 motion ⇒ `_hover_focus()` 把焦点
## **点回光标所在行** —— 正好把刚滚出来的那一格**拽回去**。
##
## ★63-19 实测：这就是"滚轮时红时绿"的**真凶**。此前我把它归因成
## "`parse_input_event` 投递帧数不定" —— **归因错了**：逐帧诊断显示
## `nav_d` 补位**确实生效**（`nav_d=1`），是**随后**的悬停把 `mode_index` 拽回原值。
func _send_button(pos: Vector2, btn: int) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = btn
	down.pressed = true
	var bpos := pos * _mouse_scale()
	down.position = bpos
	down.global_position = bpos
	Input.parse_input_event(down)
	if btn == MOUSE_BUTTON_LEFT or btn == MOUSE_BUTTON_RIGHT:
		var up := InputEventMouseButton.new()
		up.button_index = btn
		up.pressed = false
		up.position = bpos
		up.global_position = bpos
		Input.parse_input_event(up)
	await get_tree().process_frame
	_state("btn%d后" % btn)


func _expect(cond: bool, what: String) -> void:
	if cond:
		print("[menuprobe] OK    %s" % what)
	else:
		print("[menuprobe] !!    %s" % what)
		_bad += 1
