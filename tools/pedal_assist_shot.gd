extends Node
## 轮 37：**骑飞行踏板时，辅助驾驶走哪条路** —— 真机判据图（2 行 × 3 列 = 6 格），
## 外加读条提示语单独一张（**轮 38 起这一张改为"证明那条提示被删干净了"**，
## 见 `_shot_tip()`）。
##
## ## 需求原话（2026-09-28）
## > "飞行踏板在辅助驾驶模式下操控方式和阿利宙斯巡航态一样"
##
## ## 出图布局（`pedal_assist_grid.png`）
##   行 1 = **按住 Shift**
##   行 2 = **点按 Shift**
##   列 1 = **骑在飞行踏板上**（量产机 · 编队战领机，开局就带板）   ← 本轮改的就是它
##   列 2 = **阿利宙斯 · 巡航形态**（需求里的参照物）
##   列 3 = **同一台量产机脱板后**（平移模式 = 旧默认），用来对照"分界真的换了支路"
##
## ⚠️ 列 3 和列 1 用的是**同一台机体、同一条命**，只改了"在不在板上"这一个变量
##    （`release_pedal()`）。机型、玩家控制器、镜头、地图全都一样 ⇒ 差异可归因。
##
## ## 判据（一句话）
##   辅助驾驶里"冲刺"有两个入口（`FlightBody` 的两个方法，别处不许重写）：
##     `assist_dashing()` = 平移模式 + 闪避冲刺窗口（**点按** Shift，0.45 s）
##     `super_dashing()`  = 超级加速（**按住** Shift，持续态）
##   本图要证的：**列 1 与列 2 同档（super）、列 3 是另一档（assist）**。
##
## ⚠️ 两行**必须分开拍**：两种冲刺的触发方式不同（按住 vs 点按），
##    混在一格里就分不清"没亮"是因为状态不对、还是因为没按对。
##
## ⚠️ 列 3 行 1（平移 + 按住）**故意截在冲刺窗口之后**（按下后 1.5 s）：
##    按住 Shift 在平移模式里只会触发**一次**闪避（判据是 `just_pressed`），
##    窗口 0.45 s 早过 ⇒ 那一格展示的是"平移模式的稳定态：没有超级加速"。
##    窗口内的样子在列 3 行 2（点按那一格）。
##
## ⚠️ 列 1（骑板）与列 3（平移）都**不额外按方向键**：闪避的方向会退化成机头方向，
##    于是"转身 360°"那条门限（`DASH_SPIN_MIN_LAT`）不触发 —— 本图要量的不是转身
##    （那是轮 33 的题），而是"哪一档冲刺被点着了"。少一个变量。
##
## ## ⚠️ 探针自己的两条护栏（真机取证踩出来的）
##   1. **多建的 main 用完必须立刻释放**（`_shot_tip()` 之后那句 `queue_free()`）。
##      不释放：它的主菜单一直画在最上面，而你后面取的是新那份 main 的
##      `menu.visible`（false）⇒ **读数全绿、六格图全废**。
##   2. **每一格都要钉住"读的是本局那位玩家"**（`_read` 里的 `is_mine` / `in_tree` /
##      `phys` 三个字段 + 一条前置判据）。实测踩过：某一跑里骑板列读到
##      `fm.super_boost=false`，而同一工程另起进程做逐帧诊断时它 160 帧恒 true
##      ⇒ 判据红了、产品是好的。只要对象被换掉 / 掉了树 / 停了处理，读数就会
##      **定格**在最后一次被驱动时的值，而且看上去完全合法（辅助=true、增压=true、
##      平移=false……每一条"都像对的"）。所以"逐帧变化点"＋"身份三问"要一起留。
##
## ## 跑法（**不能加 --headless**：dummy 渲染器抓出来是全黑）
##   godot --path <工程> res://tools/pedal_assist_shot.tscn -- <输出目录>

const CELL_W := 800
const CELL_H := 450
const SHOT_W := 1600
const SHOT_H := 900
## 按住档按下后等多少物理帧（2.5 s）—— 让速度爬到档位附近再读。
##
## ⚠️ 这只是让**观测量**（`fm.velocity`）走近稳态；**判据用的是 `max_reachable_speed()`**
##    （档位值，瞬时可得、与等待时长无关），所以调这个数不会影响结论。
const HOLD_FRAMES := 150
## 按住档按下后的头 30 帧（0.5 s）用来统计"有几次闪避窗口"。
const PRESS_POLL := 30
## 点按档：按下 2 帧再松；松开后轮询多少帧（0.7 s > 窗口 0.45 s）。
const TAP_POLL := 42
## 点按档在松开后第几帧截图（0.2 s ≈ 窗口 45% 处，速度已开始冲）。
const TAP_SHOT_AT := 12

var out_dir := "user://r37_pedal_assist"
var _main: Node
## 当前这一局的 main（诊断用：要读它的 menu / hud / chase）。
var _cur_main: Node
## 当前这一局的玩家（诊断用）。
var _rider_now: PlayerController
var _grid := {}
var _tips := []
## 局内每次 `_diag()`（贴着截图那一刻）数到的 MainMenu [实例峰值, 可见峰值]。
## ⚠️ 判据必须用这个，不能用收尾时的即时值 —— 收尾时两局的 main 都已 free，
## 数出来必然是 0，那不是"干净"，那是"没东西可数"（首版就写成了假红）。
var _menus_seen := [0, 0]
var _ok_all := true


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	await _shot_tip()
	# ⚠️⚠️ **拍完必须释放这个 main。**
	#    它是为一个"顺手拍一张别的界面"的额外需求实例化的（读条提示语），
	#    而后面 `_run_all()` 会**另建**一个 main 去开打仗。
	#    不释放的后果：`_main` 的主菜单一直画在最上面，
	#    你后面每一张战斗截图都盖着一张菜单；
	#    而断言读的是**新那份 main** 的 `menu.visible`（false）⇒ **读数全绿、图全废**。
	#    （本轮实测踩过：六格图全被主菜单糊住，而 21 条判据一条没红。）
	_main.queue_free()
	_main = null
	await _frames(10)
	await _run_all()
	_write_sheet()

	print("\n--- 自动判据 ---")
	for rec: Array in _tips:
		_judge(str(rec[0]), bool(rec[1]))
	print("\nALL_OK=%s" % str(_ok_all))
	print("PEDAL_ASSIST_SHOT_DONE -> ", out_dir)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().quit(0 if _ok_all else 1)


# ============================================================ 第 0 部分：读条提示语

## 读条提示语：**轮 38 把"长按 G 切换辅助驾驶"那一整条删掉了**
##（轮 37 一度把它扩写成"巡航形态 / 骑板改成飞行操纵 + 超级加速"，用户要求整条去掉）。
##
## 所以这里问两件事：
##   ① **真的删干净了**：整张 `TIPS` 的每一条里都不许再出现「骑板 / 巡航」。
##      这是**唯一**的证据 —— 只盯第 0 条不够：删掉一条、别处又冒一句出来，
##      光看第 0 条完全看不见（`TIPS` 是轮播的，谁先出场还是随机的）。
##   ② 剩下的提示仍然**放得下**：`_draw_center()` 是"按算出的宽度居中、
##      **不折行、不裁剪**"—— 不会切字，但**长过头会左右同时出屏**。
##      判据是「文本宽度 < 视口宽 × 0.90」，不是"看起来有没有被切"。
func _shot_tip() -> void:
	var ls := _main.get("loading") as LoadingScreen
	if ls == null:
		print("SHOTS_FAILED(no loading screen)")
		return
	# ---- ① 全表扫描：那句、以及它的关键词，一条都不许留 ----
	var n := LoadingScreen.TIPS.size()
	var joined := ""
	for i in n:
		joined += str(LoadingScreen.TIPS[i]) + "\n"
	_tips.append(["读条提示里再也找不到「骑板 / 巡航」（%d 条全扫过）" % n,
		not joined.contains("骑板") and not joined.contains("巡航")])
	var tip: String = LoadingScreen.TIPS[0]
	ls.open("太平洋群岛 · 夜")
	ls.advance(0.42, "重塑地表……")
	var font := ls.get("_font") as Font
	var tw := -1.0
	if font != null:
		tw = font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	# 轮播每 4 s 换一条（`_tip_base` 是随机的）⇒ 每帧钉回第 0 条再拍。
	for i in 8:
		ls.set("_tip_base", 0)
		ls.set("_visible_t", 0.0)
		await _frames(1)
	var img := await _shoot_view()
	_tips.append(["提示语宽度 %.1f px < 视口 %.1f px × 0.90（放得下，不会左右出屏）"
		% [tw, SHOT_W], tw > 0.0 and tw < float(SHOT_W) * 0.90])
	var out := out_dir.path_join("r38_tip.png")
	var err := -1
	if img != null:
		err = img.save_png(out)
	print("\nSHOT %s err=%d  视口宽=%d  提示语宽=%.1f px（占 %.1f%%）" % [
		out, err, SHOT_W, tw, tw / float(SHOT_W) * 100.0])
	print("  现在第 0 条：%s" % tip)
	print("  全表 %d 条：" % n)
	for i in n:
		print("    [%d] %s" % [i, str(LoadingScreen.TIPS[i])])
	# 拍完立刻藏掉：它铺满全屏（`mouse_filter = STOP`），留着会盖住后面 6 格。
	ls.visible = false


# ============================================================ 第 1 部分：六格

func _run_all() -> void:
	# ---- 局 A：马夫蒂侧量产机（编队战领机 ⇒ `main._spawn_side` 给他挂板）----
	var ma := await _start_match(SuitProfile.Id.MESSER_M01, BattleFormation.Side.MAFTY)
	var ra := ma.get("player") as PlayerController
	if ra == null:
		print("SHOTS_FAILED(no player A)")
		return
	print("\n=== 局 A：%s · 马夫蒂 · 编队战（玩家 = 领机）===" % ra.profile.display_name)
	print("  开局就骑板？%s   辅助？%s   可动？%s" % [
		str(ra.has_pedal()), str(ra.assist_on), str(ra.controls_enabled)])
	ra.assist_on = true
	await _frames(8)
	print("  辅助开、骑板：translate_mode=%s" % str(ra.translate_mode))

	# 列 0 = 骑板
	_grid["0_0"] = await _cell(ra, true)
	_grid["1_0"] = await _cell(ra, false)

	# 列 2 = 脱板（同一条命的同一台机）
	ra.release_pedal()
	await _frames(14)
	print("  脱板后：骑板？%s   translate_mode=%s（应为 true = 回到平移）" % [
		str(ra.has_pedal()), str(ra.translate_mode)])
	_grid["0_2"] = await _cell(ra, true)
	_grid["1_2"] = await _cell(ra, false)

	ma.queue_free()
	await _frames(6)
	Game.reset()

	# ---- 局 B：联邦侧阿利宙斯 → 变形到巡航形态（需求里的参照物）----
	var mb := await _start_match(SuitProfile.Id.ARIZEUS, BattleFormation.Side.FEDERATION)
	var rb := mb.get("player") as PlayerController
	if rb == null:
		print("SHOTS_FAILED(no player B)")
		return
	print("\n=== 局 B：%s · 联邦军 · 编队战（玩家 = ACE ⇒ 没有板）===" % rb.profile.display_name)
	print("  开局就骑板？%s（ACE 机骑不了板）" % str(rb.has_pedal()))
	for i in 8:
		if rb.profile.form == SuitProfile.ArizeusForm.CRUISE:
			break
		rb.form_cooldown = 0.0
		rb.toggle_form()
		await _frames(4)
	print("  变形后形态：%s  form_index=%d" % [rb.profile.form_name(), rb.form_index])
	rb.assist_on = true
	await _frames(8)
	print("  辅助开、巡航形态：translate_mode=%s（应为 false）" % str(rb.translate_mode))

	# 列 1 = 巡航形态
	_grid["0_1"] = await _cell(rb, true)
	_grid["1_1"] = await _cell(rb, false)

	mb.queue_free()
	await _frames(6)
	Game.reset()
	_print_table()
	_build_judges()


## 一个格子：先去上一次的 Shift，再按 `hold` 走"按住"或"点按"那一档。
func _cell(rider: PlayerController, hold: bool) -> Dictionary:
	_rider_now = rider
	Input.action_release("boost")
	await _frames(12)
	var rec := {}
	if hold:
		Input.action_press("boost")
		var press_hits := 0
		var trace: Array = []
		for i in HOLD_FRAMES:
			if i < PRESS_POLL and rider.translate_dash:
				press_hits += 1
			await _frames(1)
			_trace_step(trace, rider, i)
		rec = _read(rider, "按住Shift")
		rec["press_hits"] = press_hits
		rec["trace"] = trace
		_diag("按住·截图前")
		rec["img"] = await _shoot_view()
		Input.action_release("boost")
		await _frames(10)
	else:
		Input.action_press("boost")
		await _frames(2)
		Input.action_release("boost")
		var hits := 0
		for i in (TAP_POLL + TAP_SHOT_AT):
			if rider.translate_dash:
				hits += 1
			if i == TAP_SHOT_AT:
				rec = _read(rider, "点按Shift")
				_diag("点按·截图前")
				rec["img"] = await _shoot_view()
			await _frames(1)
		if rec.is_empty():
			rec = _read(rider, "点按Shift")
			_diag("点按·兜底截图前")
			rec["img"] = await _shoot_view()
		rec["hits"] = hits
		rec["press_hits"] = -1
		await _frames(10)
	return rec


## 逐帧记「状态变化点」。
##
## ⚠️ 为什么需要它：骑板那一列曾读数 `fm.super_boost=false`，而事后单独跑
##    「同一条支路」的逐帧诊断，160 帧里它一直是 true ⇒ 说明**产品是对的、
##    是探针那个读数点不对**。只记"读到的值"分不清这两种情况，
##    记下"每帧的真值序列"就能一眼看出是"从没真过"还是"读的那一刻恰好假"。
func _trace_step(trace: Array, rider: PlayerController, i: int) -> void:
	var now := "辅助=" + str(rider.assist_on) + " 平移=" + str(rider.translate_mode) \
		+ " 增压=" + str(rider.fm.boosting) + " 超冲=" + str(rider.fm.super_boost) \
		+ " 按键=" + str(Input.is_action_pressed("boost")) \
		+ " 窗口=" + str(rider.translate_dash) \
		+ " 同人=" + str(rider == _cur_main.get("player")) \
		+ " 树=" + str(rider.is_inside_tree()) \
		+ " 处理=" + str(rider.is_physics_processing())
	if trace.is_empty() or str(trace[-1][1]) != now:
		trace.append([i, now])


## 截图**那一刻**的场景事实：确认没有别的界面盖在战斗画面上。
##
## ⚠️ 这个打印必须贴着 `_shoot_view()` 放。第一版放在格子开头
##（离截图还有 150 帧），它报"menu 已隐藏"，而拍出来的图里
## **主菜单还盖在上面** —— 打印位置不对，等于没打印。
func _diag(tag: String) -> void:
	var mn = _cur_main.get("menu")
	var hd = _cur_main.get("hud")
	var ch = _cur_main.get("chase")
	var cnt := _count_menus()
	_menus_seen[0] = maxi(int(_menus_seen[0]), int(cnt[0]))
	_menus_seen[1] = maxi(int(_menus_seen[1]), int(cnt[1]))
	var on := _rider_now != null
	print("  [DIAG %s] MainMenu 实例=%d(可见 %d) | 本局 menu.visible=%s | hud.visible=%s | phase=%s | chase.target=%s | 玩家血=%.0f" % [
		tag, int(cnt[0]), int(cnt[1]),
		str(mn.get("visible")), str(hd.get("visible")), str(_cur_main.get("phase")),
		str(ch.get("target")),
		(_rider_now.hp if on else -1.0)])
	var tpc := 0
	if on:
		var tl = _rider_now.get("_boost_trail")
		if tl != null and is_instance_valid(tl):
			tpc = int(tl.point_count())
	print("          辅助=%s 平移=%s 增压=%s 超冲=%s 按键=%s 拖尾=%d" % [
		str(_rider_now.assist_on) if on else "?",
		str(_rider_now.translate_mode) if on else "?",
		str(_rider_now.fm.boosting) if on else "?",
		str(_rider_now.fm.super_boost) if on else "?",
		str(Input.is_action_pressed("boost")), tpc])


## 树里 MainMenu 的 [实例数, 可见数]。
##
## ⚠️ **只读"本局那个 menu 的 visible"是不够的**：探针多建过一份 main 的话，
##    被画在屏上的是那份的 menu，而你手里这局的 menu 老老实实报 false。
##    要判断"屏幕上有没有菜单"，得数**整棵树**。
func _count_menus() -> Array:
	var n := 0
	var vis := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is MainMenu:
			n += 1
			if nd.is_visible_in_tree():
				vis += 1
		for c in nd.get_children():
			stack.append(c)
	return [n, vis]


## 一格的读数。**全部读现成的量，不在探针里重算判据**（重算就等于自己证明自己）。
func _read(rider: PlayerController, tag: String) -> Dictionary:
	var trail = rider.get("_boost_trail")
	var pc := 0
	if trail != null and is_instance_valid(trail):
		pc = int(trail.point_count())
	var f: FlightModel = rider.fm
	return {
		"tag": tag,
		"machine": rider.profile.display_name,
		"pedal": rider.has_pedal(),
		"form": rider.profile.form_name(),
		"tm": rider.translate_mode,
		"assist": rider.assist_on,
		# ---- 读数身份护栏（见文件头「为什么要有这三条」）----
		# 只要有一条为假，整格读数就**不可信**（对象可能已经不在被驱动的树上）。
		"is_mine": rider == _cur_main.get("player"),
		"in_tree": rider.is_inside_tree(),
		"phys": rider.is_physics_processing(),
		"boosting": f.boosting,
		"sb": f.super_boost,
		"assist_dash": rider.assist_dashing(),
		"super_dash": rider.super_dashing(),
		"tdash": rider.translate_dash,
		"trail": pc,
		"spd": f.velocity.length(),
		"max": f.max_reachable_speed(),
		"ab": f.ab_speed,
	}


func _print_table() -> void:
	print("\n=== 六格读数（列 = 骑板 / 巡航 / 平移；行 = 按住 / 点按）===")
	print("%-6s %-4s %-18s %-14s %-4s %-4s %-4s %-4s %-4s %-4s %-6s %-9s %-9s %-8s" % [
		"列", "行", "机体", "形态", "骑板", "平移", "增压", "超冲", "闪冲", "窗口",
		"拖尾点", "档位上限", "实测速度", "闪避次"])
	for c in 3:
		for r in 2:
			var rec: Dictionary = _grid.get("%d_%d" % [r, c], {})
			if rec.is_empty():
				print("  （缺格 %d_%d）" % [r, c])
				continue
			var hits := int(rec.get("hits", -1))
			var ph := int(rec.get("press_hits", -1))
			var htxt := str(hits) if hits >= 0 else ("按 %d" % ph)
			var cname: String = ["骑板", "巡航", "平移"][c]
			var rname: String = ["按住", "点按"][r]
			print("%-6s %-4s %-18s %-14s %-4s %-4s %-4s %-4s %-4s %-4s %-6d %-9.1f %-9.1f %-8s" % [
				cname, rname, str(rec["machine"]), str(rec["form"]),
				"是" if bool(rec["pedal"]) else "否",
				"平" if bool(rec["tm"]) else "飞",
				"是" if bool(rec["boosting"]) else "否",
				"是" if bool(rec["sb"]) else "否",
				"是" if bool(rec["assist_dash"]) else "否",
				"是" if bool(rec["tdash"]) else "否",
				int(rec["trail"]), float(rec["max"]), float(rec["spd"]), htxt])
	print("")
	print("  列含义：增压 = `fm.boosting`（辅助替你按住加力）· 超冲 = `fm.super_boost`（超级加速档）")
	print("        闪冲 = `assist_dashing()`（平移模式的闪避冲刺）· 窗口 = `translate_dash`")
	print("        档位上限 = `FlightModel.max_reachable_speed()`（**判据用这个**：纯档位值）")
	print("        实测速度 = `fm.velocity.length()`（**仅供参考**，理由见下）")
	print("")
	print("  ⚠️ 为什么「实测速度」不能当判据（两台各有一条**既有**机制）：")
	print("     ① 骑板时踏板把加速响应乘 `RIDE_THROTTLE_RESPONSE` = 1.45，")
	print("        只改 `fm.accel / ab_accel / brake`、**一个字都不改档位上限**，")
	print("        但冲得上目标之上 —— 所以骑板的实测速度会高于同机的档位上限；")
	print("     ② `FlightModel` 的软天花板是 `ab×1.25`（超级档抬到 `ab×1.35×1.15`），")
	print("        这条是给俯冲涨速留的余量，与本次改动无关。")
	print("     两条都是**改动前就有**的，本图不拿实测速度判任何一条。")
	print("")
	print("  ---- 按住档逐帧变化点（只在状态变化时记一条；f0 = 按下后第 1 个物理帧）----")
	for c in 3:
		var trec: Dictionary = _grid.get("0_" + str(c), {})
		var tr: Array = trec.get("trace", [])
		print("    列" + str(c + 1) + "(" + ["骑板", "巡航", "平移"][c] + ") 共 "
			+ str(tr.size()) + " 条变化点：")
		for e in tr:
			print("      f" + str(int(e[0])) + "  " + str(e[1]))


func _build_judges() -> void:
	var a_hold: Dictionary = _grid.get("0_0", {})
	var c_hold: Dictionary = _grid.get("0_1", {})
	var b_hold: Dictionary = _grid.get("0_2", {})
	var a_tap: Dictionary = _grid.get("1_0", {})
	var c_tap: Dictionary = _grid.get("1_1", {})
	var b_tap: Dictionary = _grid.get("1_2", {})
	if a_hold.is_empty() or c_hold.is_empty() or b_hold.is_empty() \
			or a_tap.is_empty() or c_tap.is_empty() or b_tap.is_empty():
		_tips.append(["六格都拍到了", false])
		return

	# ---- 前置：屏幕上没有别的界面 ----
	# ⚠️ 取样点必须落在**局内**（`_diag()` 贴着每次截图记峰值）；收尾再数一次
	#    必然是 0（两局的 main 都已 queue_free）—— 那不是干净，是没东西可数。
	_tips.append(["前置·局内每次截图前只有本局这一个 MainMenu 且它不可见（实例峰值 %d / 可见峰值 %d）"
		% [int(_menus_seen[0]), int(_menus_seen[1])],
		int(_menus_seen[0]) == 1 and int(_menus_seen[1]) == 0])
	# ---- 前置：三列确实是三个不同状态 ----
	_tips.append(["前置·列1 真的骑在板上", bool(a_hold["pedal"])])
	_tips.append(["前置·列2 是阿利宙斯且**没有**板", str(c_hold["machine"]).begins_with("阿利宙斯")
		and not bool(c_hold["pedal"])])
	_tips.append(["前置·列3 与列1 同一台机体、已脱板", str(b_hold["machine"]) == str(a_hold["machine"])
		and not bool(b_hold["pedal"])])
	# ---- 前置：六格的读数都真的来自本局那位玩家 ----
	# ⚠️ 这条是**给探针自己**的护栏，不是给产品的。实测踩过：某一跑里骑板列读到
	#    `fm.super_boost=false`，而同一工程另起进程做逐帧诊断时它 160 帧恒 true
	#    ⇒ 判据"红"了，产品是好的。三种探针侧故障（对象被换 / 掉了树 / 停了处理）
	#    都会让读数定格在"最后一次被驱动时的值"，而**看上去完全合法**。
	var id_ok := true
	var id_bad := ""
	for cc in 3:
		for rr in 2:
			var r2: Dictionary = _grid.get(str(rr) + "_" + str(cc), {})
			if r2.is_empty():
				continue
			if not (bool(r2.get("is_mine", false)) and bool(r2.get("in_tree", false))
					and bool(r2.get("phys", false))):
				id_ok = false
				id_bad += " " + ["骑板", "巡航", "平移"][cc] + ["·按住", "·点按"][rr]
	_tips.append(["前置·六格读数都来自本局那位玩家（在树上 + 在物理处理）" + id_bad, id_ok])
	# ---- 分界：谁走平移 ----
	_tips.append(["★ 骑板 → **不走平移**（translate_mode=false）", not bool(a_hold["tm"])])
	_tips.append(["★ 巡航形态 → 不走平移（与骑板同档）", not bool(c_hold["tm"])])
	_tips.append(["★ 脱板 → 回到平移（translate_mode=true）", bool(b_hold["tm"])])
	# ---- 按住 Shift：超级加速 ----
	_tips.append(["★ 按住 Shift：骑板 = **超级加速**（fm.super_boost=true）", bool(a_hold["sb"])])
	_tips.append(["★ 按住 Shift：巡航 = 超级加速（同档）", bool(c_hold["sb"])])
	_tips.append(["★ 按住 Shift：平移 ≠ 超级加速（fm.super_boost=false）", not bool(b_hold["sb"])])
	_tips.append(["★ `super_dashing()` 骑板 = 真（与巡航一致）",
		bool(a_hold["super_dash"]) and bool(c_hold["super_dash"])])
	_tips.append(["★ `super_dashing()` 平移 = 假", not bool(b_hold["super_dash"])])
	# ⚠️ **判据必须落在比值上，绝不能比绝对极速。**
	#    `ab_speed` 是**每台机各自的**（实测：梅萨M01 1391.0 / 阿利宙斯 2413.9），
	#    两台机的绝对极速本来就不该相等。首版就写了"骑板与巡航极速完全同值"，
	#    等于拿一个**必然失败**的判据去测一个本来就对的行为 —— 假红。
	#    要证的是"同档"，那就比 `max / ab`（这也是 `max_reachable_speed()` 的构造）。
	var mult := FlightModel.SUPER_BOOST_MULT
	var r_ped := float(a_hold["max"]) / maxf(float(a_hold["ab"]), 1.0)
	var r_cru := float(c_hold["max"]) / maxf(float(c_hold["ab"]), 1.0)
	var r_tra := float(b_hold["max"]) / maxf(float(b_hold["ab"]), 1.0)
	_tips.append(["★ 骑板档位 = ab × %.4f（ab=%.1f）—— 就是 SUPER_BOOST_MULT %.2f"
		% [r_ped, float(a_hold["ab"]), mult], absf(r_ped - mult) < 0.001])
	_tips.append(["★ 巡航档位 = ab × %.4f（ab=%.1f）—— 同一个倍率"
		% [r_cru, float(c_hold["ab"])], absf(r_cru - mult) < 0.001])
	_tips.append(["★ 骑板与巡航**同档**（%.4f vs %.4f；绝对极速 %.1f vs %.1f 本来就不同——两台 ab 不同）"
		% [r_ped, r_cru, float(a_hold["max"]), float(c_hold["max"])],
		absf(r_ped - r_cru) < 0.001])
	_tips.append(["★ 平移档位 = ab × %.4f（没有被超级加速抬上去）" % r_tra,
		absf(r_tra - 1.0) < 0.001])
	# ---- 拖尾：超级加速会亮 ----
	_tips.append(["★ 拖尾光条：骑板/巡航 亮（%d / %d 点）、平移 不亮（%d 点）"
		% [int(a_hold["trail"]), int(c_hold["trail"]), int(b_hold["trail"])],
		int(a_hold["trail"]) > 0 and int(c_hold["trail"]) > 0
			and int(b_hold["trail"]) == 0])
	# ---- 按住 Shift 在平移模式里只触发一次闪避 ----
	_tips.append(["★ 按住 Shift：平移触发过闪避窗口（%d 帧）、骑板/巡航 一次都没有（%d / %d）"
		% [int(b_hold["press_hits"]), int(a_hold["press_hits"]), int(c_hold["press_hits"])],
		int(b_hold["press_hits"]) > 0 and int(a_hold["press_hits"]) == 0
			and int(c_hold["press_hits"]) == 0])
	# ---- 点按 Shift：平移才有闪避冲刺 ----
	_tips.append(["★ 点按 Shift：平移出现闪避冲刺窗口（%d 帧）" % int(b_tap["hits"]),
		int(b_tap["hits"]) > 0])
	_tips.append(["★ 点按 Shift：骑板 %d 帧 / 巡航 %d 帧 —— 都没有闪避冲刺"
		% [int(a_tap["hits"]), int(c_tap["hits"])],
		int(a_tap["hits"]) == 0 and int(c_tap["hits"]) == 0])
	_tips.append(["★ 点按 Shift：骑板仍不走平移、巡航仍不走平移",
		not bool(a_tap["tm"]) and not bool(c_tap["tm"])])


# ============================================================ 出图

func _write_sheet() -> void:
	var w := CELL_W * 3 + 4
	var h := CELL_H * 2 + 2
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.07, 0.08, 0.10))
	var got := 0
	for c in 3:
		for r in 2:
			var rec: Dictionary = _grid.get("%d_%d" % [r, c], {})
			var img = rec.get("img", null)
			if img == null:
				continue
			got += 1
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(CELL_W, CELL_H)),
				Vector2i(CELL_W * c + c * 2, CELL_H * r + r * 2))
	for c in range(1, 3):
		sheet.fill_rect(Rect2i(CELL_W * c + (c - 1) * 2, 0, 2, h), Color(0.45, 0.52, 0.62))
	sheet.fill_rect(Rect2i(0, CELL_H, w, 2), Color(0.45, 0.52, 0.62))
	var out := out_dir.path_join("pedal_assist_grid.png")
	print("\nSHOT %s err=%d  拍到 %d 格" % [out, sheet.save_png(out), got])
	print("  列 = ① 骑板 ② 阿利宙斯巡航 ③ 脱板(平移) ；行 = 上 按住 Shift / 下 点按 Shift")


func _judge(label: String, cond: bool) -> void:
	if not cond:
		_ok_all = false
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])


# ============================================================ 工具

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 开一局真比赛，等玩家可控后返回 `main` 节点。
##
## ⚠️ `_on_start_match()` 是**同步**入口，不走读条（`main.gd` 的注释里写着
##    "测试不走这条路"）⇒ 读条层不会盖在我们头上，可以干净地截 HUD。
func _start_match(suit_id: int, side: int) -> Node:
	Game.active_suit = suit_id
	Game.active_side = side
	var m := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(m)
	_cur_main = m
	# 多等几帧再开局：`_ready()` 里菜单还在做开场轨道动画，
	# 立刻开局会让主菜单那一帧的残影混进来（取帧是"当前帧"没错，但世界还没稳）。
	await _frames(20)
	m.call("_on_start_match", suit_id, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	var rider: PlayerController = null
	for i in 300:
		await _frames(1)
		rider = m.get("player") as PlayerController
		if rider != null and rider.controls_enabled:
			break
	if rider == null or not rider.controls_enabled:
		print("  ⚠️ 玩家一直没能动（controls_enabled 恒 false）")
	await _frames(10)
	return m


## 抓全屏，缩成 CELL_W × CELL_H。
##
## ⚠️ 必须等 `frame_post_draw`：不等的话拿到的是**上一帧**的画面。
## ⚠️ `window_set_size()` 在 Windows 上会被系统 DPI 顶掉 ⇒ 统一 resize，
##    免得同一张图里混进两种尺寸。
func _shoot_view() -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.resize(CELL_W, CELL_H, Image.INTERPOLATE_LANCZOS)
	return img
