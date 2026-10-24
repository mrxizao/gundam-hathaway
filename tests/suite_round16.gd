class_name SuiteRound16
extends RefCounted
## 第十六轮（用户指定的两块 UI）：
##   「左上角显示辅助驾驶系统有没有开启，右上角显示周围的敌机列表（按 123 能切换已扫描的敌机）」
##   —— 第二轮补充「**不止 123**，按数字键可以切换扫描到的敌机」，所以槽位是 1 – 9。
##
## 分成两半测，因为这两半会坏的方式完全不同：
##
##   1. **版式**（纯函数 `FlightHUD.corner_layout`）—— 右端必须落在 `content_right` 上、
##      列表底部不能压到右中的高度块。差几像素这件事**在截图上只是"有点怪"**，
##      只有算得出来。
##   2. **数据**（真的起一局训练）—— 列表里是哪几架、编号会不会偷偷换人、
##      数字键选中的是不是列表第 n 行那一架。**"按 3 选了别的"是没人能一眼看出来的**
##      那类 bug（玩家按下去也有反应、也有提示，只是选错了），所以必须钉住。
##
## ⚠️ 为什么单独一个文件而不是塞进 `suite_round.gd`：第十六轮与第十四轮的落地
## 是**并行的两个会话**，共用一个 suite 文件会互相覆盖。round 号一个文件
## （`suite_round14.gd` 也是这么来的），落地时少一半冲突面。


static func run(t: T, host: Node) -> void:
	t.suite("Round16 / 两块角标的版式")
	_layout(t)
	t.suite("Round16 / 左上角的按键提示")
	_assist_hint(t)
	t.suite("Round16 / 系统状态块：中央那五行搬到了辅助驾驶下面")
	_system_block(t)
	t.suite("Round16 / 敌机列表与数字键 1 / 2 / 3")
	await _contacts(t, host)


## **1.2 第二十五轮**：屏幕**中央**那五行常驻文字搬到了左上角（辅助驾驶 / 踏板下面）。
##
## 用户原话：「战斗时候的 ui 需要优化，**屏幕中心太多字了**，你看看能不能放到其他地方去，
## 比如**辅助驾驶系统的下面**之类的」。
##
## 为什么这一段测的是**内容与上界**而不是"截图里中央有没有字"：
## 中央空了这件事没法在无头测试里断言（像素要截图），但搬过去之后最容易犯的两个错
## **可以**钉住 ——
##   ① **搬丢了一行**（信息没了，而玩家只会觉得"怎么不告诉我了"）；
##   ② **搬过去之后没有上界**（左上角一路长下去，变成第二个中央）。
static func _system_block(t: T) -> void:
	# ---- ① 导弹系统模式**永远在** ----
	# 它决定"右键 / L1 干什么"（拦截 ⇄ 全弹发射），藏起来玩家会以为按键坏了。
	var base := {"mode": "拦截", "hint": "L1 切换", "full": false, "cd": 0.0, "ready": true,
		"count": 100, "auto": false, "hold": 0.0, "sel": false, "tti": 0.0,
		"how": "右键直接拦", "threats": 0, "cycle": "B 换目标"}
	var rows := FlightHUD.system_block_rows(base)
	t.eq(rows.size(), 1, "没有别的状态时就只有模式那一行")
	t.ok(str(rows[0]["text"]).contains("导弹系统"), "第 1 行 = 导弹系统模式（%s）" % str(rows[0]["text"]))
	t.ok(str(rows[0]["text"]).contains("拦截"), "模式名来自状态")

	# ---- ② 全弹发射：冷却 / 就绪 / 弹药不足 三态 ----
	var full := base.duplicate()
	full["full"] = true
	full["cd"] = 12.4
	t.ok(_has_row(FlightHUD.system_block_rows(full), "冷却"), "冷却中 → 有冷却行")
	full["cd"] = 0.0
	full["ready"] = true
	t.ok(_has_row(FlightHUD.system_block_rows(full), "就绪"), "冷却走完 → 有就绪行")
	full["ready"] = false
	t.ok(_has_row(FlightHUD.system_block_rows(full), "弹药不足"), "弹不够 → 有弹药不足行")
	t.not_ok(_has_row(FlightHUD.system_block_rows(base), "全弹发射"),
		"**拦截模式下不画全弹发射那一行**（否则就是新的常驻噪音）")

	# ---- ③ 自动拦截：开着一行；按住时是"带进度条那一行" ----
	var auto := base.duplicate()
	auto["auto"] = true
	t.ok(_has_row(FlightHUD.system_block_rows(auto), "自动拦截 ON"), "自动拦截开着 → 有 ON 行")
	auto["auto"] = false
	auto["hold"] = 0.5
	rows = FlightHUD.system_block_rows(auto)
	t.ok(_has_row(rows, "自动拦截"), "按住期间 → 有提示行")
	t.near(_bar_of(rows), 0.5, 0.001, "那一行带 0.5 的进度（画条用）")

	# ---- ④ 当前选中 + TTI + 怎么拦（它改变 F / 右键的语义，必须常驻可见）----
	var sel := base.duplicate()
	sel["sel"] = true
	sel["tti"] = 2.5
	rows = FlightHUD.system_block_rows(sel)
	t.ok(_has_row(rows, "当前选中"), "有选中 → 有「当前选中」行")
	t.ok(_has_row(rows, "TTI 2.5"), "TTI 写进那一行")
	t.ok(_has_row(rows, "右键直接拦"), "「怎么拦」跟着一起搬（文案仍按设备换）")

	# ---- ⑤ 威胁总数 ----
	var many := base.duplicate()
	many["threats"] = 3
	t.ok(_has_row(FlightHUD.system_block_rows(many), "×3"), "威胁计数写进那一行")

	# ---- ⑥ 上界：所有开关全开也只有 6 行 ----
	var all_on := {"mode": "全弹发射", "hint": "L1 切换", "full": true, "cd": 0.0, "ready": true,
		"count": 100, "auto": true, "hold": 1.0, "sel": true, "tti": 1.0,
		"how": "右键直接拦", "threats": 9, "cycle": "B 换目标"}
	rows = FlightHUD.system_block_rows(all_on)
	t.gt(rows.size(), 1, "全开时确实不止一行（说明条件行真的会出现）")
	t.ok(rows.size() <= 6, "全开也只有 %d 行（≤6）—— 这块接在踏板下面，必须**有上界**" % rows.size())

	# ---- ⑦ 每行字段齐全（少一个键 = 运行时崩在 `_draw()` 里）----
	for row: Dictionary in rows:
		t.ok(row.has("text") and row.has("size") and row.has("col") and row.has("bar"),
			"行结构完整：%s" % str(row.get("text", "?")))


static func _has_row(rows: Array, needle: String) -> bool:
	for row: Dictionary in rows:
		if str(row.get("text", "")).contains(needle):
			return true
	return false


## 取出"带进度条那一行"的比值（没有就返回 −1）。
static func _bar_of(rows: Array) -> float:
	for row: Dictionary in rows:
		if float(row.get("bar", 0.0)) > 0.0:
			return float(row["bar"])
	return -1.0


## 左上角那一块必须带**按哪个键**（用户第二轮要求："左上角辅助驾驶要有按键提示"）。
##
## 两条硬要求：
##   ① **手柄模式下不能印一个按不出来的键** —— 第十五轮 §2.4 那次事故
##      （说明书印着按不出来的键）就是这么来的；
##   ② 文案必须带**「长按」** —— 辅助驾驶是长按 0.45 s 开关的（`HoldAction`），
##      只印一个光秃秃的 `G`，玩家点一下没反应就会以为按键坏了。
static func _assist_hint(t: T) -> void:
	t.eq(FlightHUD.assist_hint(false), "长按 G", "键鼠模式：左上角印「长按 G」")
	t.eq(FlightHUD.assist_hint(true), "长按 A",
		"手柄模式：左上角印「长按 A」（不是印着 G 让手柄玩家去按）")
	t.ok(FlightHUD.assist_hint(false).contains("长按"),
		"提示里带「长按」：写成光秃秃的 G 会让玩家点一下以为按键坏了")
	# HUD 这一行与帮助面板必须**同源同说法**：改一处忘一处就是"说明书说谎"。
	var help_row: Array = []
	for sec: Dictionary in InputSetup.HELP_SECTIONS:
		for it: Array in sec["items"]:
			if InputSetup.help_text(it).begins_with("G"):
				help_row = it
	t.eq(help_row.size(), 3, "帮助面板里有「G 长按 → 辅助飞行」那一行")
	if help_row.size() == 3:
		t.ok(str(help_row[0]).contains("长按"), "帮助面板同样写明「长按」（%s）" % str(help_row[0]))
		t.eq(str(help_row[2]), "长按 A", "帮助面板的手柄列就是「长按 A」，和 HUD 上那一行对得上")


## 两块角标共用 `content_left` / `content_right` 这两根线 —— 和主菜单、结算菜单、
## 右下角装备栏是同一套网格（`UILayout`），不允许自己另起一格。
static func _layout(t: T) -> void:
	for view: Vector2 in [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080)]:
		var g := FlightHUD.corner_layout(view)
		t.near(float(g["right"]), UILayout.content_right(view), 0.001,
			"%s：列表右端 = content_right（和右下角装备栏同一条竖线）" % view)
		t.near(float(g["assist_x"]), UILayout.content_left(view), 0.001,
			"%s：辅助驾驶块左端 = content_left（就在左上角）" % view)
		t.near(float(g["assist_top"]), float(g["top"]), 0.001,
			"%s：两块角标的上边在同一条线上（各写一份迟早对不上）" % view)
		t.gt(float(g["tag_x"]), view.x * 0.5, "%s：号牌列在屏幕右半边" % view)
		t.gt(float(g["name_x"]), float(g["tag_x"]) + 20.0, "%s：机名列在号牌列右侧" % view)
		# 距离列最长的形态是「15.0 km 未扫描」（fs 13 下约 97 px），
		# 机名最长的形态是「古斯塔夫00（靶机）」（fs 14 下约 130 px）。
		# 两列都得装得下 —— 装不下就是"名字被距离盖住"，那种重叠在截图上一眼看不出来。
		var name_room := float(g["right"]) - float(g["name_x"]) - 97.0
		t.gt(name_room, 130.0,
			"%s：距离列（含「未扫描」）之外还装得下最长的机体名" % view)
		# 行首那个"屏幕外方向"小箭头在 tag_x − 18 处，也不能掉进屏幕中间
		t.gt(float(g["tag_x"]) - 18.0, view.x * 0.5, "%s：行首箭头也在右半边" % view)
		# 标题 + **满号**（`CONTACT_KEYS` 有 9 个槽位）+ 一行"其余 N 架"整体
		# 都要留在右中高度块（它在 view.y * 0.5）之上 —— 按最坏情况算，不按当前敌机数
		var rows := float(PlayerController.CONTACT_KEYS.size())
		var bottom: float = float(g["top"]) + 22.0 + float(g["row_step"]) * rows + 22.0
		t.lt(bottom, view.y * 0.5 - 40.0,
			"%s：列表满号（%d 行）+ 汇总行也不压到右中高度块" % [view, int(rows)])


## 真起一局训练，并把几何**摆成确定的**：
##   玩家挪到跑道圆心（靶机绕 5.2 km 的圈飞），再把 4 号靶机扔到 15 km 外。
## 于是"列表里有几架、哪几架超距"都不依赖出生点的随机角度 —— 断言不会时红时绿。
static func _contacts(t: T, host: Node) -> void:
	var tree := host.get_tree()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await tree.process_frame
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.RANGE, Game.MatchMode.TRAINING)
	await tree.process_frame
	for i in 3:
		await tree.physics_frame

	var player := main.get("player") as PlayerController
	var lk := main.get("player_lock") as LockOnSystem
	var targets: Array = []
	targets = main.get("targets")
	if player == null or lk == null or targets.size() < 4:
		t.ok(false, "训练局没起来（玩家 / 玩家锁定系统 / 靶机缺项）")
		return

	# ---- 摆成确定几何：玩家在圆心，4 号靶机扔到 30 km 外（超距）----
	# 这一下同时把**保号**测掉了：若编号是"每帧按距离重排"，把一架甩到 30 km 外
	# 必然打乱顺序；保号的话顺序一动不动。
	#
	# ⚠️ **这个数从 `seeker_range` 反推，不能写死 15 km**：
	# 2026-09-21 把 `seeker_range` 从 9000 抬到 20700 之后，15 km 就**落进射程了**，
	# 于是下面那条 `scanned_n == 3` 会变成 4 —— 而那**不是**"保号"坏了，
	# 是这条几何摆错了。写死米数就会在下一次调整射程时重演一次。
	var order_before: Array = []
	order_before = player.contacts()
	t.eq(order_before.size(), 4, "开局四架靶机都进了列表（实际 %d）" % order_before.size())

	player.global_position = Vector3(0.0, 2600.0, 0.0)
	var far = targets[3]
	far.global_position = player.global_position + Vector3(0.0, 0.0, -(lk.seeker_range + 9000.0))
	for i in 2:
		await tree.physics_frame

	var list: Array = []
	list = player.contacts()
	t.eq(list.size(), targets.size(), "列表 = 场上还活着的敌机，一架都不少")
	var same_order := list.size() == order_before.size()
	if same_order:
		for i in list.size():
			if list[i] != order_before[i]:
				same_order = false
	t.ok(same_order, "把一架甩到 %.1f km 外之后序号一动不动（编号只发一次，不按距离重排）"
		% ((lk.seeker_range + 9000.0) / 1000.0))
	var far_i := list.find(far)
	t.gt(far_i, -1, "超距的那架仍然在列表里（看得见，才谈得上「周围有几架」）")
	var scanned_n := 0
	for c in list:
		if player.global_position.distance_to((c as Node3D).global_position) <= lk.seeker_range:
			scanned_n += 1
	t.eq(scanned_n, 3, "三架在射程内（已扫描）、一架超距（未扫描）")

	# ---- 数字键直选：按 n，锁定的必须是列表第 n 行那一架 ----
	# 挑一个**在射程内**的行来按（超距那架按了会被正确地拒绝，那是下一条测的）
	var pick_i := -1
	for i in mini(list.size(), PlayerController.CONTACT_KEYS.size()):
		if player.global_position.distance_to((list[i] as Node3D).global_position) <= lk.seeker_range:
			pick_i = i
			break
	if pick_i >= 0:
		var want = list[pick_i]
		# 数字键与槽位一一对应（`CONTACT_KEYS` 是唯一真源，键位 1 – 9）
		var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
		await _key(host, keys[pick_i], true)
		for i in 10:
			await tree.physics_frame
			if lk.target == want:
				break
		t.ok(lk.target == want, "按 %d → 锁定的就是列表第 %d 行那一架" % [pick_i + 1, pick_i + 1])
		await _key(host, keys[pick_i], false)
		for i in 2:
			await tree.physics_frame
	else:
		t.ok(false, "列表前三行里没有已扫描的敌机，数字键那一条没法测")

	# ---- 编号只发一次：飞一段之后 1 号还是同一架 ----
	# 按距离每帧重排的话，两架敌机交叉而过时 1 号会换人，
	# 而玩家是"先读到列表、再按键"，中间换人等于选错。
	var first = list[0]
	for i in 45:
		await tree.physics_frame
	var after: Array = []
	after = player.contacts()
	t.gt(after.size(), 0, "飞 45 个物理帧之后列表里还有敌机")
	if after.size() > 0:
		t.ok(after[0] == first, "1 号还是原来那一架（编号不换人）")

	# ---- 超距那一架：看得见、选不上，而且会说明原因 ----
	var before_target = lk.target
	var picked_far: bool = player.call("select_contact", far_i + 1)
	t.not_ok(picked_far, "超距的那一架（第 %d 行）按数字键选不上" % (far_i + 1))
	t.ok(lk.target == before_target, "选不上时不会顺手把当前目标换掉")
	var picked_oob: bool = player.call("select_contact", 9)
	t.not_ok(picked_oob, "按 9（列表里没有第 9 架）返回 false，不会崩")

	# ---- 辅助驾驶状态：HUD 左上角那一块读的就是它 ----
	var st: Dictionary = {}
	st = player.call("assist_state")
	t.eq(bool(st.get("on", true)), false, "默认是关的（辅助是「帮忙」系统，不该默认替玩家做决定）")
	for k: String in ["aim", "range", "avoid"]:
		t.ok(st.has(k), "状态里带 %s（左上角才画得出「是谁在出力」）" % k)
	# 第十四轮的地面硬兜底：那时俯仰被系统写死、推杆没反应，
	# 左上角必须能把"接管拉升"画出来（不然玩家只会以为按键坏了）。
	t.ok(st.has("auto_pull"), "状态里带 auto_pull（硬兜底接管时左上角改印「接管拉升」）")
	player.assist_on = true
	st = player.call("assist_state")
	t.eq(bool(st.get("on", false)), true, "打开之后 assist_state 报 on —— 左上角那块读的就是它")
	player.assist_on = false

	main.free()
	await tree.process_frame
	Game.reset()


static func _key(host: Node, key: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
