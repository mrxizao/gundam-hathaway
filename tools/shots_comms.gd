extends Control
## **通讯（电台 / 字幕 / 人物对话 / 播报）** 的真机截图台 · 2026-09-30。
##
## ⚠️ **根节点必须是 `Control`**（本文件第一行），不能是 `Node`。
## 2026-09-30 实测：写成 `extends Node` 时，加进去的子 Control **一个像素都不画** ——
## 不报错、不警告，`save_png` 照样 err=0，出来的是纯黑图。
## `shots_producer.gd` / `shots_sally.gd` 一个 extends Control、一个 extends Node，
## 但后者是**靠 `main.tscn` 整棵树**在画，自己不加 CanvasItem 子节点。
## 判据：黑图 + 零报错 ⇒ 先怀疑"根节点不是 CanvasItem"。
##
## 老板原话：「这两份是闪哈一闪哈2的台词剧本，你导入进去，根据这个去做电台和字幕和人物对话。」
## 这一台就是把那句话的四样东西**拍出来** —— 数据层绿了不等于画面对。
##
## ## 为什么走 `main.tscn`（与 `shots_producer.gd` 相反）
## 制作人模式那七张只发生在两个纯 `_draw()` 面板上，所以那台**刻意不碰** `main.tscn`。
## 这一台不行：本轮有一条**跨对象**的版式判据 ——
## 「电台框必须让开姿态仪整盘」。姿态仪画在 `if player != null` 那个分支里，
## 没有真玩家（= 没有 `main.tscn` 起的那一局）就根本不出现在画面上，
## 这一条就变成了"自己跟自己比"。所以要真起一局。
##
## ## 九张图
## | 图 | 钉住的那句话 |
## |---|---|
## | `00_radio_lane` | 战斗中三条电台同时在场；**最新一条在最下面**；左缘让开姿态仪整盘 |
## | `01_radio_typing` | 打字机：字没打完时**末尾有光标**（否则"没打完"与"就这么短"看不出区别） |
## | `02_subtitle` | 字幕：马夫蒂宣言的**真实原句**（下中、无名字牌） |
## | `03_dialogue` | 人物对话：序章豪恩泽号的**真实原句** + 名字牌（比字幕大一号） |
## | `04_alert` | 播报（SPTV）：上方一条，**底边停在告警区上面** |
## | `05_all_lanes` | 四条兰**同时**在场（跨样式不排队）—— 找它们有没有互相压 |
## | `06_radio_720p` | 720p 下电台条数**自动收紧**（不是硬画三条去压速度块） |
## | `07_live_mission` | ★ **由真实驱动产生**（不摆台）：真起一局 M01，等 `elapsed>=4` 的触发器**自己到点**，并把六条触发器的 `fired` 逐条念出来 |
## | `08_m04_gawman` | M04「重力」那条电台的呼号：`duel_lane_01`「拿出你的本事 马夫蒂」⇒ 呼号应为**加乌曼**（轮 62 订正的数据）。**摆台** —— 真起 M04 会让本台进程提前退出，原因见 `_m04_duel_shot()` 的注释 |
##
## ⚠️ **前七张能证"画得对"，证不了"游戏里会出现"** —— 它们全是 `_stage()` 人工塞队列。
## 只有第 8 张不摆台（真起一局、等触发器自己到点）：`CommsDirector` 一次都没被
## tick 过的那个真 bug，就是第 8 张抓出来的。每个"显示层"的出图台都该有这样一张。
##
## ⚠️ **不能加 `--headless`** —— 无头用 dummy 渲染器，一个像素都不产生。
## 这个脚本的全部意义就是**能真的看到**。
##
## ⚠️ **不出 `04` 与 `03` 就不会知道它们打架**：字幕与人物对话都落在"下中"、
## 都用 `_band_bottom_y()` 当底边。单拍一张永远看不出来，只有把四条一起摆上才看得见。
##
## ⚠️ **绝不碰玩家存档**：`campaign_save_path` 注入临时文件（本台会走 `_launch_match()`，
## 那条路会读进度）。跑完删掉。
##
## 跑法：
##   godot --path <工程> res://tools/shots_comms.tscn -- <输出目录>
##
## 脚本里所有等待都走**物理帧**（物理固定 60 Hz；等渲染帧在 300+ fps 的窗口里
## 只有几分之一秒，会出现"页面还没重画就截图了"）。

const DIR := preload("res://scripts/flight/comms_director.gd")
const COMMS := preload("res://scripts/data/comms.gd")
const BANK := preload("res://scripts/data/comms_bank.gd")
## 第 ⓪′ 张要读本关的**触发器表**（把"哪几条到点了"当读数念出来）。
const MS := preload("res://scripts/data/mission_script.gd")

const SHOT_W := 1600
const SHOT_H := 900
const SMALL_W := 1280
const SMALL_H := 720

## 本台的临时存档（**绝不碰** `user://campaign.cfg`）。
const TMP := "user://comms_shots_tmp.cfg"

var main: Node
## ⚠️ 必须写**具体类**而不是 `Node`：本台要读 `FlightHUD` 的一串常量
## （`ATTITUDE_RADIUS` / `HEALTH_BLOCK_TOP_FROM_BOTTOM` / `SPEED_BLOCK_BOTTOM_PAD`
## / `COM_ALERT_TOP`…）。`Node` 上这些名字编译期根本不存在，只有标了类才解析得到。
var hud: FlightHUD
var comms: RefCounted
## 降级底板（只有独立 HUD 模式才建），720p 那一张要跟着改尺寸。
var bg: ColorRect
## `true` = **没走 `main.tscn`**（降级模式）。见 `_boot_main()` 的注释。
var standalone := false
var out_dir := "user://shots_comms"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ★★ 注意：这里**不能**只写 `DisplayServer.window_set_size()`。见 `_apply_design_size()`。
	_apply_design_size(SHOT_W, SHOT_H)

	if await _boot_main():
		if not await _launch("M01"):
			CS_erase()
			get_tree().quit(1)
			return
		hud = main.get("hud")
	else:
		await _boot_standalone()

	if hud == null:
		push_error("SHOTS_FAILED(没有 hud)")
		CS_erase()
		get_tree().quit(1)
		return
	comms = hud.comms
	if comms == null:
		push_error("SHOTS_FAILED(hud.comms 是空的 —— 轮 E 的接线断了)")
		CS_erase()
		get_tree().quit(1)
		return

	# ★★ ⓪′ **先拍真机那一张** —— 它必须排在 `set_process(false)` **之前**。
	# 那一步冻住的正是驱动 `comms.tick()` 与触发器求值的那个每帧入口，
	# 冻住之后再怎么等也等不到电台自己响（会变成"我摆的"而不是"它来的"）。
	await _live_mission_shot()

	# ★ **冻住时钟**再拍。
	# `hud._process()` 每帧替 `comms.tick(delta)` 推一格、并在末尾 `queue_redraw()`。
	# 不冻的话：① 打字机每张图多冒一两个字符（读数与画面就不是同一帧的）；
	# ② 三条电台会在我摆好之后各走各的、淡出程度不一样。
	# 冻住之后**重绘要自己推**（`_shot()` 里那句 `queue_redraw()`）——
	# 这正是 `shots_producer.gd` 踩过的那个坑：症状是"多张图字节完全相同"。
	hud.set_process(false)

	_report_wiring()
	await _radio_shots()
	await _typing_shot()
	await _subtitle_shot()
	await _dialogue_shot()
	await _alert_shot()
	await _all_lanes_shot()
	await _m04_duel_shot()
	await _small_view()

	CS_erase()
	print("SHOTS done -> %s" % out_dir)
	get_tree().quit(0)


## 起主场景（拿一个**真玩家** ⇒ 姿态仪会出场）。
##
## ## 失败**不是**错误
## 本仓库有并行会话，`main.gd` 经常处在"改到一半"的状态。实测 2026-09-30：
## `cutscene_script.gd` 里一个尚未写出的成员（`rig_cockpit`）就让 `main.gd`
## **整个解析不过**，于是**所有走 `main.tscn` 的出图台一张图都拍不出来**。
## 那时本台**降级**成"只建 HUD"：四条兰的版式照样能核，
## 只有「电台让开姿态仪」那一条失去意义（姿态仪自己不出场，见 `_report_wiring()` 的告警）。
func _boot_main() -> bool:
	var ps := load("res://scenes/main.tscn") as PackedScene
	if ps == null:
		push_warning("SHOTS_WARN(main.tscn 装不起来 ⇒ 降级为独立 HUD 模式)")
		return false
	var n := ps.instantiate()
	if n == null:
		push_warning("SHOTS_WARN(main.tscn 实例化失败 ⇒ 降级为独立 HUD 模式)")
		return false
	# ⚠️ `load()` 成功**不代表 `main.gd` 装上了**：`.tscn` 自己读得出来，
	# 只是根节点的脚本在 `GDScript::reload` 那里解析不过 ⇒ 节点照建、没有脚本。
	# 所以判据是**探节点上有没有那个方法**（以及 `get_script()` 是不是空），
	# 不能只看 `ps == null`。实测 2026-09-30：只看 `ps` 时会一路跑下去，
	# 然后在 `_resolve_campaign_match` 上炸 "Nonexistent function in base 'Node3D'"。
	if n.get_script() == null or not n.has_method("_resolve_campaign_match"):
		n.free()
		push_warning("SHOTS_WARN(main.gd 没装上 —— 解析不过 ⇒ 降级为独立 HUD 模式)")
		return false
	main = n
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)
	main.set("campaign_save_path", TMP)
	return true


## 只建 HUD（没有战场、没有玩家）。
##
## 深色底板是必要的：正常游戏里 HUD 背后是 3D 战场，本台没有 —— 不铺一块的话
## 半透明的框会压在最底下的默认清屏色上，"框"就读不出来了。
func _boot_standalone() -> void:
	standalone = true
	# ⚠️ 窗口模式与尺寸**这里也要设一遍**：上面那一遍写在 `_boot_main()` 里，
	# 降级路根本不走那段 ⇒ 窗口保持默认（实测抓出来是 2560×1600），
	# 而 HUD 被我按 1600×900 摆 ⇒ 图里只有左上角一块有东西。
	# 不设 `WINDOW_MODE_WINDOWED` 的话，玩家设置是全屏时窗口尺寸也改不动。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)
	# 尺寸**从视口读回来**，不按常量硬摆 —— 窗口管理器可能给了别的值。
	var v := get_viewport().get_visible_rect().size
	bg = ColorRect.new()
	bg.color = Color(0.015, 0.03, 0.055, 1.0)
	bg.position = Vector2.ZERO
	bg.size = v
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	hud = FlightHUD.new()
	add_child(hud)
	hud.position = Vector2.ZERO
	hud.size = v
	# ★★ **必须给 HUD 一台相机**，否则它一个像素都不画（不报错、err=0、纯黑）。
	#
	# 根因：`FlightHUD.can_draw()` 是**这个类自己重写的**（`hud.gd:1039`），
	# 内容是 `camera != null and is_instance_valid(camera)` —— **只看相机、不看玩家**
	# （那条注释解释了为什么：玩家阵亡后残骸会被释放，绘制入口不能跟着关掉）。
	# 于是"没有主场景 ⇒ 没有相机 ⇒ `_draw()` 第一行就 return"。
	#
	# ⚠️ 排查这个坑时我绕了三圈，记住这条：**卡在 `can_draw()` 上先去看它是不是被重写过** ——
	# 引擎那个 `CanvasItem.can_draw()` 判的是"在树里 + 可见 + 有视口"，
	# 三者实测**全为真**（`visible=true`、`is_visible_in_tree()=true`、视口 = root Window），
	# 而读数依然是 `false`。`grep -n "func can_draw" scripts/` 一眼就能看见重写。
	#
	# 这台相机只为过守卫而存在：`first_person` 关着 ⇒ `_draw_cockpit_rails()` 自己
	# 又会早退，其余用相机的分支全在 `if player != null` 里（本模式没有玩家）。
	var cam := ChaseCamera.new()
	add_child(cam)
	hud.camera = cam
	await _frames(6)



# ============================================================ ⓪ 接线读数
## 拍之前先把"四个样式真的都接上了"念一遍 —— 只拍不念的话，
## "某一兰没画"分不清是"没接到"还是"那一刻没台词"。
func _report_wiring() -> void:
	print("--- ⓪ 接线")
	if standalone:
		print("    ⚠️ **降级模式**（没起 main.tscn）⇒ 没有玩家 ⇒ 姿态仪不出场。")
		print("       下面那条「空档」读数**只是算术**（两个纯函数相减），")
		print("       它不是「画面上真的没压到」的证据 —— 要那一条请等 main.tscn 能起再跑。")
	print("    hud.comms = %s（%s）· live 总数 = %d · clock = %.2f"
		% [str(comms), comms.get_class(), comms.live().size(), comms.clock()])
	for st: String in COMMS.STYLES:
		print("    样式 %-9s live=%d" % [st, comms.live_of(st).size()])
	print("    电台表 %d 条 · 场景 %d 段 · 剧本库 %d 条 · 存疑 %d 条"
		% [COMMS.radio_ids().size(), COMMS.scene_ids().size(), BANK.count(),
			BANK.doubtful().size()])
	var v := hud.size
	print("    HUD 尺寸 = %s" % str(v))
	_report_lane_geometry(v)


## 四条兰各自的几何 + ★ 电台与姿态仪的空档。
##
## ⚠️ 这里的数字**全部从纯函数读**（`radio_rect()` / `centered_rect()` / `alert_rect()`
## / `FlightHUD.attitude_center()`），不抄任何常量 —— 抄一份的话这条读数就会与画面分家。
func _report_lane_geometry(v: Vector2) -> void:
	var blood := v.y - FlightHUD.HEALTH_BLOCK_TOP_FROM_BOTTOM - DIR.RADIO_BOTTOM_PAD
	var ceil_y := hud._radio_ceil_y()
	var floor_y := v.y * 0.5 + FlightHUD.SPEED_BLOCK_BOTTOM_PAD + 8.0
	var cols := DIR.radio_columns(v, floor_y, ceil_y)
	print("    电台兰：上界(速度块下) %.0f · 下界 %.0f（血条口径 %.0f%s）· 排得下 %d 条"
		% [floor_y, ceil_y, blood,
			"，已被下中条压下去 %.0f" % (blood - ceil_y) if ceil_y < blood - 0.01 else "",
			cols])
	var r0 := DIR.radio_rect(v, 0, maxi(cols, 1), ceil_y)
	print("    电台框左缘 x = %.1f（= content_left + RADIO_LEFT_INSET %.0f）"
		% [r0.position.x, DIR.RADIO_LEFT_INSET])
	var ac := FlightHUD.attitude_center(v)
	var att_r := FlightHUD.ATTITUDE_RADIUS
	print("    姿态仪：圆心 %s · 半径 %.0f ⇒ 右缘 x = %.1f"
		% [str(ac), att_r, ac.x + att_r])
	print("    ★ 空档 = 电台左缘 − 姿态仪右缘 = **%.1f px**（>= 0 才算让开）%s"
		% [r0.position.x - (ac.x + att_r),
			"  ⚠️ 降级模式：姿态仪没出场，这只是算术" if standalone else ""])
	print("    字幕条底边 y = %.1f（_band_bottom_y，first_person=%s）"
		% [hud._band_bottom_y(), str(Settings.first_person)])
	_report_band_vs_radio(v, floor_y, ceil_y, cols)
	var alert := DIR.alert_rect(v, 2, FlightHUD.COM_ALERT_TOP)
	print("    播报条（2 行）: %s ⇒ 底边 %.1f（告警区从 y=130 起）"
		% [str(alert), alert.end.y])


## ★★ 电台兰 × 下中那条带：**逐条框**比一遍，不是只拿最上面那一格比。
##
## ⚠️ 首版这里只拿 `radio_rect(v, 0, ...)`（最上面那条）去比 —— 它当然不撞，
## 因为它位置最高。而**真正会撞的是最下面那条**（底边 = 下界，
## 正好落进带子的 y 区间）。于是这条读数报"否"、画面里两只框压在一起。
## 教训：判"两族框不相交"必须**遍历**，拿一个代表样本比是假判据。
func _report_band_vs_radio(v: Vector2, floor_y: float, ceil_y: float, cols: int) -> void:
	var stack := DIR.band_stack(v, hud._band_bottom_y(), 1, 1)
	var bands: Array = [stack["subtitle"], stack["dialogue"]]
	var names: Array = ["字幕", "对白"]
	for k in bands.size():
		var b: Rect2 = bands[k]
		if b.size.y <= 0.0:
			continue
		var hit := 0
		for i in cols:
			if DIR.radio_rect(v, i, cols, ceil_y).intersects(b):
				hit += 1
		print("    ★ 【没有夹上界时的反事实】电台 %d 条 × %s %s ⇒ 会撞 %d 条 —— "
			% [cols, str(names[k]), str(b), hit]
			+ "这就是 `radio_ceil_y()` 存在的理由（当前帧不带子 ⇒ 上界还是血条口径 %.0f）"
				% ceil_y)


# ============================================================ ⓪′ ★ 真机那一张

## ★★ 这一张是老板那句「**没看到电台啊**」的直接回答。
##
## 本台此前七张全是**人工摆台**（`_stage()` 把条目直接塞进播放器）——
## 它们能证明"**画得对**"，但**证明不了"游戏里会出现"**。
## 而 2026-09-30 之前 `CommsDirector` **一次都没被 tick 过**
##（`scripts/main.gd` 里一处 `comms` 都没有）⇒ 真机上一条电台都不会出现，
## 而七张摆台图**全都正常**。这正是"摆台图给了虚假的安全感"的标本。
##
## ⇒ 这一张**不摆台**：真起一局，让 `main._process()` 自己把
## `Game.trigger_state()` 喂给 `hud.comms.tick_mission()`，**等触发器自己到点**
##（M01：`elapsed>=4` → `radio:davao_sibet_01`）。
## 这里报出来的每一条都是**它自己涌出来的**，我只负责按快门。
##
## ⚠️ 必须排在 `hud.set_process(false)` 之前（见 `_ready()` 里那句注释）。
## ⚠️ 降级模式（没有 `main.tscn`）**直接跳过并说出来**，绝不假造一张。
func _live_mission_shot() -> void:
	print("--- ⓪′ 真机（不由本台摆台）")
	if standalone:
		print("    ⚠️ **降级模式**（没起 main.tscn）⇒ 没有 `_process` 驱动触发器 ⇒")
		print("       这一张**跳过**。要在真机上看到电台，必须走 main.tscn 全路径。")
		return
	var m: MS.Mission = Game.active_mission
	if m == null or comms == null:
		print("    ⚠️ 没有 active_mission / comms ⇒ 跳过（不假造）。")
		return
	var trs: Array = m.triggers
	print("    mission=%s · 触发器共 %d 条 ⇒ 其中电台 %d 条"
		% [m.id, trs.size(), _radio_count(trs)])
	print("    本局第一条电台的条件 = `%s` ⇒ 目标就等它"
		% _first_radio_when(trs))
	# M01 的第一条在 `elapsed>=4`；多等 0.4 s 让它进场（首帧寿命为 0 ⇒ 透明度也是 0）。
	var reached := await _wait_elapsed(4.4, 14.0)
	# ⚠️ `comms` 声明成 `RefCounted`（不引 FlightHUD 的依赖）⇒ `live_of()` 的返回
	# 在编译期是 Variant，**不能** `:=` 推类型（实测报
	# `Cannot infer the type of "live_radio"`）。显式标 `Array`。
	var live_radio: Array = comms.live_of(COMMS.STYLE_RADIO)
	print("    等到 elapsed=%.2f（到位=%s）· fired=%d / %d 条 · live=%d 条（电台 %d 条）"
		% [Game.elapsed, str(reached), comms.fired_count(m.id), trs.size(),
			comms.live().size(), live_radio.size()])
	# ★ 把**每一条**触发器的到点情况念出来 —— 只说"响了"是断言，
	#   逐条列出"哪条到点、哪条还没"才是可核对的过程。
	for i in trs.size():
		var t0: MS.Trigger = trs[i]
		print("      [%2d] %-26s → %-26s fired=%s"
			% [i, t0.when, t0.do_what, str(comms.is_fired(m.id, i))])
	if live_radio.is_empty():
		push_error("SHOTS_FAILED(真机上没有电台 —— 触发器那一半的接线断了)")
	await _shot("07_live_mission")
	_report_live("07 **真机**开局：台词由 main._process → tick_mission 自己涌出")


## ★ 轮 62：M04「重力」开场 20 秒那条电台的**呼号**。
##
## 由来：老板「M04 电台的那句『拿出你的本事 马夫蒂』说话人应该是加乌曼」——
## 剧本真源 `h1_dialogue.csv` 第 1208 行那一格的说话人**本来就是推断出来的**
##（表头写的就是 `说话人(推断)`），本轮订正为加乌曼并重建 `comms_bank.gd`。
## 改的是**数据**，所以这张图要看的就是**画面上那个呼号**。
##
## ⚠️ **这一张是摆台（`_stage()`），不是「真起 M04 等它自己到点」。**
## 本轮实测：本台起过 M01（`_launch("M01")`）之后**再** `_launch("M04")`，
## `LAUNCH M04 · suit=XI map=太平洋群岛` 打出来之后**进程立刻自己退出**
##（exit=0；日志停在那一行；`08` 与后面 00~06 一张都没拍）。
## `scripts/main.gd` 里**没有任何** `quit()` / `change_scene()` ⇒
## 嫌疑是「一局没清就再起一局」。那是**独立的一件事**，本轮不修（见交付说明的提示项）。
##
## ⇒ 所以这一张退回摆台：它证的是「**画出来的呼号是加乌曼**」；
##   「触发器真会到点」由 `suite_mission_aces` 的正面断言 + 第 8 张（M01 真机）覆盖。
func _m04_duel_shot() -> void:
	print("--- ⓪″ M04「重力」那条电台的呼号（摆台；真起 M04 见本函数注释）")
	var id := "duel_lane_01"
	_stage([{"id": id, "t": _t_full(id)}])
	await _shot("08_m04_gawman")
	var line := _line_for(id)
	print("    呼号=%s · 正文=%s · src=%s"
		% [str(line.get("speaker", "")), str(line.get("text", "")), str(line.get("src", ""))])


## 本关触发器里 `radio:` 动作的条数。
func _radio_count(trs: Array) -> int:
	var n := 0
	for t0: MS.Trigger in trs:
		if str(t0.do_what).begins_with("radio:"):
			n += 1
	return n


## 本关**第一条**电台触发器的条件（念出来用；没有就返回空串）。
func _first_radio_when(trs: Array) -> String:
	for t0: MS.Trigger in trs:
		if str(t0.do_what).begins_with("radio:"):
			return t0.when
	return ""


## 等 `Game.elapsed` 走到 `target`（最多等 `limit_secs` 秒）。
##
## ⚠️ 等的是**游戏时钟**不是墙钟：本函数按**物理帧**计数只是给个上限，
## 真正的判据是 `Game.elapsed`。它由 `game.gd._process()` 在 `phase == FIGHT` 时推进 ——
## 所以"等不到"本身就说明**那一半接线断了**，是个有信息量的失败。
func _wait_elapsed(target: float, limit_secs: float) -> bool:
	var budget := int(limit_secs * 60.0)
	var i := 0
	while i < budget and Game.elapsed < target:
		await get_tree().physics_frame
		i += 1
	return Game.elapsed >= target


# ============================================================ ①② 电台

func _radio_shots() -> void:
	# ---- 三条同时在场：最新一条在**最下面** ----
	_stage([
		{"id": "davao_ken_01", "t": _t_full("davao_ken_01")},
		{"id": "davao_gawman_03", "t": _t_full("davao_gawman_03")},
		{"id": "oenbelli_ira_01", "t": _t_full("oenbelli_ira_01")},
	])
	await _shot("00_radio_lane")
	_report_live("00 三条电台（第三条是最新上场的）")


func _typing_shot() -> void:
	# ---- 打字机进行中：末尾必须有光标 ----
	# ★ 轮 56：原来用的是 `sea_ira_01`（M04 打捞那关的电台）—— 那一关连同它的两条电台
	# 一起下架了 ⇒ 摆台引用到不存在的 id。换成 `leo_ira_01`（19 字，本台别处没用过，
	# 长度够演示"打字到一半 + 末尾光标"）。
	var id := "leo_ira_01"
	_stage([{"id": id, "t": _t_typing(id)}])
	await _shot("01_radio_typing")
	var line := _line_for(id)
	print("--- 01 打字机中途：正文 %d 字，已揭示 %d 字 ⇒ 画的文本=「%s」"
		% [str(line.get("text", "")).length(),
			DIR.reveal_of(float(_live0(COMMS.STYLE_RADIO)["t"]), line),
			DIR.shown_text(float(_live0(COMMS.STYLE_RADIO)["t"]), line)])
	print("    仍有未揭示部分 = %s（True 才会画那个光标）"
		% str(str(line.get("text", "")).length() > DIR.reveal_of(
			float(_live0(COMMS.STYLE_RADIO)["t"]), line)))


# ============================================================ ③④ 字幕 / 对话

func _subtitle_shot() -> void:
	# 马夫蒂宣言 —— 字幕没有名字牌，是一条**单向**压在画面上的话。
	_stage([{"id": "h1:0890", "t": _t_full("h1:0890")}])
	await _shot("02_subtitle")
	_report_live("02 字幕（马夫蒂宣言）")


func _dialogue_shot() -> void:
	# 序章豪恩泽号 —— 琪琪点破"此行目的"的那一句（老板纠正过的归属）。
	_stage([{"id": "h1:0010", "t": _t_full("h1:0010")}])
	await _shot("03_dialogue")
	_report_live("03 人物对话（名字牌 + 更大字号）")


# ============================================================ ⑤ 播报

func _alert_shot() -> void:
	_stage([{"id": "oenbelli_broadcast_01", "t": _t_full("oenbelli_broadcast_01")}])
	await _shot("04_alert")
	_report_live("04 播报（上方一条，无呼号）")


# ============================================================ ⑥ 四条兰一起

## ⚠️ 这一张是**唯一**能看出"字幕与人物对话打架"的图。
##
## 两者都落在"下中"、都拿 `_band_bottom_y()` 当底边、都用 `centered_rect()` ——
## 各自单拍一张都完美，摆在一起才可能重叠。手机位那一栏骗不了人。
func _all_lanes_shot() -> void:
	_stage([
		{"id": "davao_ken_01", "t": _t_full("davao_ken_01")},
		{"id": "davao_gawman_03", "t": _t_full("davao_gawman_03")},
		{"id": "h1:0889", "t": _t_full("h1:0889")},
		{"id": "h1:0010", "t": _t_full("h1:0010")},
		{"id": "oenbelli_broadcast_01", "t": _t_full("oenbelli_broadcast_01")},
	])
	await _shot("05_all_lanes")
	_report_live("05 四条兰同时在场")
	# ★ 把"有没有重叠"变成读数（画面上"看起来挨着"和"真的压上了"不是一回事）。
	# 走**绘制用的同一个** `band_stack()` / `_radio_ceil_y()`，不自己摆一遍坐标。
	var v := hud.size
	var st := DIR.band_stack(v, hud._band_bottom_y(),
		_rows("h1:0889", FlightHUD.COM_SUB_FS), _rows("h1:0010", FlightHUD.COM_DLG_FS))
	var sub: Rect2 = st["subtitle"]
	var dlg: Rect2 = st["dialogue"]
	var ceil_y := hud._radio_ceil_y()
	var floor_y := v.y * 0.5 + FlightHUD.SPEED_BLOCK_BOTTOM_PAD + 8.0
	var cols := DIR.radio_columns(v, floor_y, ceil_y)
	print("    ★ 下中两条的框：字幕 %s / 对话 %s" % [str(sub), str(dlg)])
	print("    ★ 字幕 × 对白：重叠 = %s · 缝 = %.1f px（BAND_STACK_GAP %.0f）"
		% ["是" if sub.intersects(dlg) else "否",
			dlg.position.y - sub.end.y, DIR.BAND_STACK_GAP])
	print("    ★ 这一帧电台排得下 %d 条（上界被带子压到 %.0f，血条口径 %.0f）"
		% [cols, ceil_y,
			v.y - FlightHUD.HEALTH_BLOCK_TOP_FROM_BOTTOM - DIR.RADIO_BOTTOM_PAD])
	var hits := 0
	for i in cols:
		var rr := DIR.radio_rect(v, i, cols, ceil_y)
		for b: Rect2 in [sub, dlg]:
			if b.size.y > 0.0 and rr.intersects(b):
				hits += 1
	print("    ★ 电台框 × 下中条：相交 %d 条（遍历每一格；只拿最上面那格比是假判据）"
		% hits)


# ============================================================ ⑦ 720p

## ★★ 改「设计尺寸」，不是改窗口尺寸 —— 只改窗口是**没用**的。
##
## 本工程 `project.godot` 是 `stretch/mode="canvas_items"` + `aspect="expand"`、
## 基准 **1600×900**。这种组合下 `get_viewport().get_visible_rect().size` 返回的是
## **设计尺寸（1600×900）而不是窗口尺寸**：窗口缩到 1280×720 时，Godot 把整张
## 1600×900 的画布**整体缩 0.8 倍**铺进窗口，`hud.size` 从头到尾还是 1600×900。
##
## ⇒ 只调窗口的结果（实测，第一版就是这么错的）：
## `06_radio_720p.png` 里电台框高 **49** px、节距 **54**，而 `00_radio_lane.png`
## 是 **62 / 68**；`x` 从 190 变 152。三个比值**全是 0.8** —— 那张图只是 900p 版面的
## 缩图，`radio_columns()` 照样返回 **3**，"720p 自动收紧到 1 条"这句话**根本没被证明**。
## 更坏的是它长得完全正常：尺寸对了、有图、`ink` 也正常，只有量像素才看得出来。
## ⇒ 要真改版面，必须同时改 `Window.content_scale_size`。
func _apply_design_size(w: int, h: int) -> void:
	var win := get_window()
	win.content_scale_size = Vector2i(w, h)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(w, h))


func _small_view() -> void:
	# ★ 这一行是**这一张图唯一的难点**：换了窗口尺寸而不换设计尺寸，等于没换。
	_apply_design_size(SMALL_W, SMALL_H)
	# 降级模式的底板与 HUD 都是**显式尺寸**，窗口变小它们不会自己跟 ——
	# 不跟的话矮一档那一张里画面右下角会露出一块没铺底的空处。
	# ⚠️ 只在降级模式里手动改：走 main.tscn 时 HUD 挂在 CanvasLayer 上、由布局撑满，
	# 手写 size 会与它抢（而且下一帧就被覆盖，写了等于没写，还看不出问题）。
	if standalone:
		var v2 := get_viewport().get_visible_rect().size
		bg.size = v2
		hud.size = v2
	await _frames(16)
	_stage([
		{"id": "davao_ken_01", "t": _t_full("davao_ken_01")},
		{"id": "davao_gawman_03", "t": _t_full("davao_gawman_03")},
		{"id": "oenbelli_ira_01", "t": _t_full("oenbelli_ira_01")},
	])
	await _shot("06_radio_720p")
	_report_live("06 720p（矮一档 ⇒ 电台条数自动收紧，不是硬画三条）")


# ============================================================ 摆台

## 把场上清空，再按 `specs`（`[{"id": ..., "t": ...}]`）摆好并**把 t 钉死**。
##
## 为什么不用 `push()` 然后等几帧：那样子**每条走的秒数不一样**，打字机进度、
## 淡入完成度都不可复现。这里 `tick(0.0)` 只做"从队列补位"这一件事（delta = 0 ⇒
## 谁都不推进），随后逐条写入指定寿命 —— 于是同一张图每次跑出来逐字节一样。
func _stage(specs: Array) -> void:
	comms.clear()
	for s in specs:
		var line := _line_for(str(s["id"]))
		if line.is_empty():
			push_error("SHOTS_FAILED(查不到的 id: %s)" % str(s["id"]))
			continue
		comms.enqueue_line(line)
	comms.tick(0.0)
	# 逐样式按**上场顺序**钉 t（live_of 返回的就是上场顺序）
	var want: Dictionary = {}
	for s in specs:
		var st := str(_line_for(str(s["id"])).get("style", ""))
		if not want.has(st):
			want[st] = []
		(want[st] as Array).append(float(s.get("t", 1.0)))
	for st: String in want:
		var live: Array = comms.live_of(st)
		var ws: Array = want[st]
		for i in mini(live.size(), ws.size()):
			(live[i] as Dictionary)["t"] = ws[i]


## 这一条**完全打完**且**还没开始淡出**的寿命值。
##
## 三个约束一起夹：① 打完要 `长度 / CPS` 秒；② 淡入要 `FADE_IN`；
## ③ 不能进到淡出段（`FADE_IN + hold`）。取中段偏上。
func _t_full(id: String) -> float:
	var line := _line_for(id)
	if line.is_empty():
		return 1.0
	var n := float(str(line.get("text", "")).length())
	var typed := n / COMMS.CPS
	var hold := float(line.get("secs", 2.0))
	# 打完之后留 0.4 秒的"完整停留"，再往上夹住淡出起点
	return clampf(maxf(typed, DIR.FADE_IN) + 0.4, DIR.FADE_IN + 0.05,
		DIR.FADE_IN + hold - 0.35)


## 打到 **四成** 时的寿命值（用来拍字号/光标，不是拍完整句子）。
func _t_typing(id: String) -> float:
	var line := _line_for(id)
	if line.is_empty():
		return 0.3
	var n := float(str(line.get("text", "")).length())
	return maxf(n * 0.4 / COMMS.CPS, 0.25)


## 任意 id → 台词字典（电台优先，其次在**场景**里找）。
##
## `COMMS.line()` 只认"电台 + 场景"两条路，拿不到任意一条剧本库行 ——
## 所以场景要展开成 `lines` 再逐个 id 比。找不到返回空字典（**不兜底**）。
func _line_for(id: String) -> Dictionary:
	var r := COMMS.radio(id)
	if not r.is_empty():
		return r
	for sid: String in COMMS.scene_ids():
		for l: Dictionary in (COMMS.scene(sid)["lines"] as Array):
			if str(l["id"]) == id:
				return l
	return {}


func _live0(style: String) -> Dictionary:
	var items: Array = comms.live_of(style)
	return {} if items.is_empty() else (items[0] as Dictionary)


## 某一条按某个字号折行占几行 —— 走的是**绘制用的同一个** `UILayout.wrap()`，
## 所以这个读数与画面上框的高度必然一致（自己写一份估算就是两个真源）。
func _rows(id: String, fs: int) -> int:
	var line := _line_for(id)
	if line.is_empty():
		return 1
	var f: Font = hud.get("_font")
	if f == null:
		return 1
	var w := minf(DIR.SUBTITLE_MAX_W, hud.size.x - 80.0) - FlightHUD.COM_BAND_PAD_X * 2.0
	return maxi(UILayout.wrap(f, str(line.get("text", "")), w, fs,
		FlightHUD.COM_BAND_MAX_LINES).size(), 1)


# ============================================================ 读数 / 工具

func _report_live(tag: String) -> void:
	# ★ "live 几条"与"画出来几条"**不是一回事**：电台兰按窗口高度自动收紧
	# （`radio_columns`），live=3 而这一屏只画 1 条是正常行为。只报 live 的话，
	# 720p 那张图的读数就证明不了"收紧了"这件事。
	var v := hud.size
	var ceil_y := hud._radio_ceil_y()
	var floor_y := v.y * 0.5 + FlightHUD.SPEED_BLOCK_BOTTOM_PAD + 8.0
	var cols := DIR.radio_columns(v, floor_y, ceil_y)
	print("--- %s" % tag)
	print("    窗口 %s ⇒ 电台一屏排得下 %d 条（下界 %.0f / 上界 %.0f）"
		% [str(v), cols, floor_y, ceil_y])
	for st: String in COMMS.STYLES:
		var items: Array = comms.live_of(st)
		if items.is_empty():
			continue
		var drawn := items.size()
		if st == COMMS.STYLE_RADIO:
			drawn = mini(items.size(), cols)
		print("    [%s] live=%d 画出=%d %s" % [st, items.size(), drawn,
			"（最新的排在下面，只画最近这 %d 条）" % drawn if drawn < items.size() else ""])
		for e in items:
			var line: Dictionary = e["line"]
			var t := float(e["t"])
			print("       t=%.2f a=%.2f 说话人='%s' 正文(%d字)「%s」档=%s"
				% [t, DIR.alpha_of(t, line), str(line.get("speaker", "")),
					str(line.get("text", "")).length(), DIR.shown_text(t, line),
					str(line.get("src", ""))])


func _launch(id: String) -> bool:
	if not bool(main.call("_resolve_campaign_match", id)):
		push_error("SHOTS_FAILED(_resolve_campaign_match %s)" % id)
		return false
	main.call("_launch_match")
	await _frames(30)
	var pl = main.get("player")
	if pl == null or not is_instance_valid(pl):
		push_error("SHOTS_FAILED(player 没起来：%s)" % id)
		return false
	print("LAUNCH %s · suit=%s map=%s"
		% [id, str(SuitProfile.by_id(Game.active_suit).id_name()),
			str(Game.active_map.name_cn)])
	return true


func CS_erase() -> void:
	# 本台注入的临时档；删掉不留痕（`CS.erase()` 是本工程既有的写法）
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	# ⚠️ **必须自己推重绘**：上面把 `hud.set_process(false)` 冻住了，而那正是
	# 平常替 HUD 调 `queue_redraw()` 的地方。不推的话画面停在冻住前那一帧，
	# 症状是**多张图字节完全相同**（不是报错、不是黑屏）。
	hud.queue_redraw()
	await _frames(2)
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport) ", name)
		return
	var tex := vp.get_texture()
	if tex == null:
		print("SHOT_FAILED(no texture) ", name)
		return
	var img := tex.get_image()
	if img == null:
		print("SHOT_FAILED(no image) ", name)
		return
	var path := out_dir.path_join("%s.png" % name)
	# ★ 空图判定**写成读数**，别靠人眼看：降级路第一次跑出来的就是"不报错、
	# err=0、纯黑"（见本文件头部那条）。每隔 4 个像素采一格，1.44M 像素不至于卡。
	#
	# ⚠️ 判据是"**与底板色不同**的采样点数"，不是"非黑" —— 底板本身就是暗蓝
	# （0.015/0.03/0.055），按"非黑"数的话整屏都算有东西（实测 90000/90000），
	# 空图反而判不出来。
	var ink := _ink(img)
	print("SHOT %s  %dx%d  ink=%d  err=%d"
		% [path, img.get_width(), img.get_height(), ink, img.save_png(path)])
	# ★★ **被缩放的图**必须报出来（见 `_apply_design_size()` 的注释）。
	# 判据：设计尺寸（= `hud.size`，版式算式的输入）必须**逐像素等于**图尺寸。
	# 不等 ⇒ 这张图是别的分辨率缩过来的，图上量出来的任何尺寸都不是版式的真值。
	var design := Vector2i(hud.size)
	if design != Vector2i(img.get_width(), img.get_height()):
		print("SHOT_SCALED %s —— 设计尺寸 %s ≠ 图 %dx%d：版面被缩放，这张图的读数不作数！"
			% [name, str(design), img.get_width(), img.get_height()])
	if ink < 20:
		# 空图时把参考像素打出来：纯黑 ⇒ 连底板都没画（根节点不是 CanvasItem 那一类）；
		# 暗蓝 ⇒ 底板画了、只有 HUD 没画（⇒ 先去看 `FlightHUD.can_draw()` 那个重写）。
		print("SHOT_BLANK %s —— 几乎没画东西（ink=%d）· 参考像素(2,2)=%s"
			% [name, ink, str(img.get_pixel(2, 2))])


## 与**左上角那一格**（底板）颜色不同的采样点数。
##
## 采样步长 4 ⇒ 1600×900 上 90000 个样本；阈值 < 20 就当空图
## （正常一张图上万，差一个数量级，不会被噪声误判）。
func _ink(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var ref := img.get_pixel(2, 2)
	var n := 0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			if absf(c.r - ref.r) + absf(c.g - ref.g) + absf(c.b - ref.b) > 0.10:
				n += 1
			x += 4
		y += 4
	return n
