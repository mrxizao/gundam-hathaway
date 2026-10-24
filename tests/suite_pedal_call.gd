class_name SuitePedalCall
extends RefCounted
## **重新呼叫飞行踏板**（1.2.1 · DESIGN §3.4）。
##
## 用户实测（截图 3）：「重新呼叫飞行踏板的时候……就是会看到底部是吧 /
## 不知道 但是肯定是不对的」。
##
## ## 读码查出的真因 —— 它是**逻辑必然**，不是观感问题
##
## ```gdscript
## # 入场点在骑手**正上方**
## global_position = for_rider.global_position + Vector3(0.0, CALL_HEIGHT, 0.0)
## # 而朝向修正被一条退化守卫挡着：
## if d > 1.0 and absf(to.normalized().dot(Vector3.UP)) < 0.999:
##     look_at(r.global_position, Vector3.UP)     # ← dot = −1，absf = 1.0，**永不成立**
## ```
## 入场矢量**恰好与 UP 平行** ⇒ 守卫**恒为假** ⇒ 那块板：
##   ① **全程不转**，保持 `FlightPedal.new()` 的默认朝向（板面朝上、机头朝世界 −Z）；
##   ② 从骑手**正上方**直落 ⇒ 玩家仰视看到的是**板底**（用户报的就是这条）；
##   ③ 顺带也没有"在飞"的姿态感，只有平移。
##
## 修法：入场点改**前上方斜向**（`CALL_APPROACH_DIST`）+ 显式入场姿态 +
## `_tick_inbound()` 的 `look_at` 换成 **slerp 限速转向**。
##
## ## 这个套件的重点
##
## **把"看到板底"这件事变成一条可断言的几何不变量**（入场矢量不得接近垂直），
## 而不是靠人眼看截图 —— 那正是它藏了这么久没被发现的原因。
## 同时锁住"修朝向时别碰坏挂载与飞行加成"（`_pedal_turn_applied` 那个坑）。

const APPROACH := "PedalCall / 入场点在前上方（不是正上方）"
const ATTITUDE := "PedalCall / 入场姿态与限速转向"
const MOUNT := "PedalCall / 到位后挂载 + 加成不叠加"
const RIDER_VIS := "PedalCall / 骑手模型不叠影（B1）"
const BODY_SRC := "res://scripts/flight/flight_body.gd"
const PEDAL_SRC := "res://scripts/flight/flight_pedal.gd"


static func run(t: T, host: Node) -> void:
	t.suite(APPROACH)
	await _approach(t, host)
	t.suite(ATTITUDE)
	await _attitude(t, host)
	t.suite(MOUNT)
	await _mount(t, host)
	t.suite(RIDER_VIS)
	await _rider_vis(t, host)


# ---------------------------------------------------------------- 工具

## 建一局 1v1 并**卸掉玩家身上的板** —— 这个套件要测的是"呼叫"那条路。
static func _rider_without_pedal(host: Node) -> Dictionary:
	Game.reset()
	Game.active_suit = SuitProfile.Id.MESSER_M01
	Game.active_side = BattleFormation.Side.MAFTY
	var m := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(m)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, -1)
	for i in 16:
		await host.get_tree().physics_frame
	var player: FlightBody = m.get("player")
	if player == null:
		return {"m": m, "player": null, "pedal": null}
	if player.has_pedal():
		player.release_pedal()
		for i in 3:
			await host.get_tree().physics_frame
	# 起手：呼叫一块板（走的是生产路径 `mount_pedal()`）
	player.mount_pedal()
	await host.get_tree().process_frame
	var pedal := _find_pedal(m, FlightPedal.Mode.INBOUND)
	return {"m": m, "player": player, "pedal": pedal}


static func _find_pedal(root: Node, mode: int) -> FlightPedal:
	for c: Node in root.get_children():
		var p := c as FlightPedal
		if p != null and p.mode == mode:
			return p
		var deeper := _find_pedal(c, mode)
		if deeper != null:
			return deeper
	return null


# ---------------------------------------------------------------- 1 入场点

static func _approach(t: T, host: Node) -> void:
	var s := await _rider_without_pedal(host)
	var m: Node = s["m"]
	var player: FlightBody = s["player"]
	var pedal: FlightPedal = s["pedal"]
	if player == null or pedal == null:
		t.ok(false, "**呼叫做不出来（没拿到 INBOUND 的板）** —— 本套件前提不成立")
		if m != null:
			m.queue_free()
		await host.get_tree().physics_frame
		return

	t.ok(player.profile.can_ride_pedal(), "梅萨是量产机（可骑板）")
	t.not_ok(player.has_pedal(), "起手没板 —— 下面测的才是「呼叫」这条路径")
	t.eq(pedal.mode, FlightPedal.Mode.INBOUND, "板处于 INBOUND（在飞过来）")
	t.ok(pedal.is_alive(), "板活着")

	# ---- 核心不变量：入场矢量**不得接近垂直** ----
	#
	# ⚠️ 这一条就是"看到板底"那个 bug 的**判据**。阈值 0.95（≈18°）远严于
	# 原来的 0.999：0.999 正是让守卫失效的那条线。
	var to_rider := player.global_position - pedal.global_position
	var dir := to_rider.normalized()
	t.gt(to_rider.length(), 100.0, "入场时离骑手有足够距离（板在天上）")
	t.lt(absf(dir.dot(Vector3.UP)), 0.95,
		"**入场矢量不接近垂直**（|dot(UP)| = %.3f）—— 否则 look_at 的退化守卫会恒为假、"
		% absf(dir.dot(Vector3.UP)) + "板全程不转、玩家只看到板底")
	t.gt(float(FlightPedal.CALL_APPROACH_DIST), 0.0,
		"`CALL_APPROACH_DIST` > 0（入场点有前向分量）")

	# 高度仍然保留"看得见它下来"
	t.gt(pedal.global_position.y - player.global_position.y, 100.0,
		"入场点仍在**骑手上方**（用户要的「先在天上出现」没被改掉）")

	m.queue_free()
	await host.get_tree().physics_frame


## 板的机头方向与"指向骑手"之间的夹角（度）。
##
## ⚠️ 用"**还差多少度**"而不是"这一帧转了多少度"：
## 前者是单调函数，对帧对齐免疫；后者取决于 `await process_frame` 的恢复点落在
## `_process` 之前还是之后，实测会给出反直觉的数（3.7° 与 34.3°）。
static func _off_angle_deg(pedal: FlightPedal, rider: FlightBody) -> float:
	var toward := (rider.global_position - pedal.global_position).normalized()
	var facing := -pedal.global_transform.basis.z
	return rad_to_deg(facing.angle_to(toward))


# ---------------------------------------------------------------- 2 姿态

static func _attitude(t: T, host: Node) -> void:
	var s := await _rider_without_pedal(host)
	var m: Node = s["m"]
	var player: FlightBody = s["player"]
	var pedal: FlightPedal = s["pedal"]
	if player == null or pedal == null:
		t.ok(false, "**呼叫做不出来** —— 姿态那几条测不了")
		if m != null:
			m.queue_free()
		await host.get_tree().physics_frame
		return

	# ---- 入场第 1 帧的朝向：机头已经指着骑手 ----
	#
	# ⚠️ 断言的是**第 1 帧**（刚 `begin_inbound()` 完、还没等到任何 `_process`）。
	# 靠 `_tick_inbound()` 去补是不行的 —— 它要等下一帧，
	# 而"入场那一帧的朝向"既会被截图抓到、也会被玩家看到。
	var toward := (player.global_position - pedal.global_position).normalized()
	# Godot 的 −Z 是前方，所以 `basis.z` 指向骑手的**反方向**
	var facing := -pedal.global_transform.basis.z
	var deg := rad_to_deg(facing.angle_to(toward))
	t.lt(deg, 30.0, "入场第 1 帧机头指向骑手（偏差 %.1f° < 30°）" % deg)
	# 板面朝上：up 分量要为正（没有翻过来）
	t.gt(pedal.global_transform.basis.y.dot(Vector3.UP), 0.4, "入场姿态板面朝上（没翻）")

	# ---- 限速转向：不该"啪"地跳过去，但要确实收敛 ----
	#
	# 做法是把板挪到**侧上方**、对准骑手之后再**人为拧 90°**，
	# 于是它必须转约 90° 才能重新对上。
	#
	# ⚠️ 判据用**偏角（还差多少度）**，不用"每帧转了多少度"。
	# 第一版按"第 1 帧转的度数 > 第 2 帧"写，实测拿到 3.7° 与 34.3°（正好反了）——
	# 那是**帧对齐**问题：`await process_frame` 的恢复点在 `_process` 之前还是之后
	# 决定了这一帧算不算数，逐帧差值对时序太敏感。
	# 而"偏角单调下降 + 一次没转完"对时序免疫，且正是"指数收敛"的定义本身。
	#
	# 骑手也钉住：他要是自己飞（500 m/s ≈ 8 m/帧），"指向骑手"这个方向
	# 会在 1 秒里漂出几百米，收敛判据里就混进了别的东西。
	player.set_physics_process(false)
	var anchor := player.global_position + Vector3(0.0, 2000.0, 2000.0)
	pedal.global_position = anchor
	pedal.look_at(player.global_position, Vector3.UP)   # 先对准
	pedal.rotate_y(deg_to_rad(90.0))                    # 再拧开 90°
	var off0 := _off_angle_deg(pedal, player)
	t.gt(off0, 45.0, "起手确实拧开了约 90°（偏角 %.1f°）" % off0)

	await host.get_tree().process_frame
	var off1 := _off_angle_deg(pedal, player)
	t.gt(off1, 10.0,
		"**第 1 帧没有一步转到位**（偏角仍 %.1f°）—— 瞬时 `look_at` 会直接变 0" % off1)
	t.lt(off1, off0, "第 1 帧朝骑手转了一点（slerp 限速生效）")

	var off_last := off1
	var monotonic := true
	for i in 59:
		# 每帧钉回锚点：真让它飞的话会转成 RIDDEN（`d <= CALL_ARRIVE_DIST`），
		# `_tick_inbound` 随即停掉，收敛就再也测不出来了。
		pedal.global_position = anchor
		await host.get_tree().process_frame
		var now := _off_angle_deg(pedal, player)
		if now > off_last + 0.001:
			monotonic = false
		off_last = now
	t.ok(monotonic, "偏角**单调下降**（指数收敛，不会来回过冲）")
	t.lt(off_last, 10.0, "60 帧内收敛到骑手（偏角 %.2f°）" % off_last)

	m.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 3 挂载与加成

static func _mount(t: T, host: Node) -> void:
	var s := await _rider_without_pedal(host)
	var m: Node = s["m"]
	var player: FlightBody = s["player"]
	var pedal: FlightPedal = s["pedal"]
	if player == null or pedal == null:
		t.ok(false, "**呼叫做不出来** —— 挂载那几条测不了")
		if m != null:
			m.queue_free()
		await host.get_tree().physics_frame
		return

	var accel_off := player.fm.accel
	var pitch_off := player.fm.pitch_rate

	# 缩短距离把"到位"那一段跑快（`_tick_inbound` 在 `_process` 里跑，所以 await 它）
	var dir := (pedal.global_position - player.global_position).normalized()
	pedal.global_position = player.global_position + dir * (FlightPedal.CALL_ARRIVE_DIST + 40.0)
	var arrived := false
	for i in 90:
		await host.get_tree().process_frame
		if player.has_pedal():
			arrived = true
			break
	t.ok(arrived, "板飞到位 → `has_pedal()` 为真（自动转成 RIDDEN）")
	t.eq(pedal.mode, FlightPedal.Mode.RIDDEN, "板切到 RIDDEN")
	t.ok(pedal.riders.has(player), "骑手登记在板上")

	# ---- 加成与代价 ----
	#
	# ⚠️ 第一版把方向写反了（断言 accel **降低**），实测是**升高**的：
	# `apply_pedal_flight_bonus()` 用的是 `RIDE_THROTTLE_RESPONSE`，而它是个 **>1** 的倍率
	#（实测 65.7 → 95.2）。骑板换到的是"**油门响应更快**"，代价在**转向**
	#（`RIDE_TURN_MUL` < 1，同一函数里乘 pitch/roll/yaw）。
	# 断言要照着代码写，不能照着"骑板应该更笨重"的直觉写。
	var accel_on := player.fm.accel
	t.gt(accel_on, accel_off,
		"骑乘**加成**：油门响应更快（accel %.1f → %.1f）" % [accel_off, accel_on])
	t.lt(player.fm.pitch_rate, pitch_off,
		"骑乘**代价**：转向更钝（pitch_rate %.3f → %.3f）" % [pitch_off, player.fm.pitch_rate])

	# ⚠️ 转向折扣是**一次性乘法**，靠 `_pedal_turn_applied` 幂等 —— 这就是那段
	# "它是一个乘在基值上的一次性操作，而 `_apply_top_speed()` 会被调多次（挂载时 / 变形时）"
	# 的注释在防的事。多调一次不能再跌 0.8。
	var pitch_after := player.fm.pitch_rate
	player.apply_pedal_flight_bonus()
	t.near(player.fm.pitch_rate, pitch_after, 0.0001,
		"重复调用**不再扣一次**转向折扣（`_pedal_turn_applied` 幂等）")

	# ---- 回归门：重新呼叫一次，加成**不得叠加两次** ----
	#
	# `apply_pedal_flight_bonus()` 把折扣乘在基值上，而 `_apply_top_speed()` 之后还会被调 ——
	# 没有 `_pedal_turn_applied` 那个一次性标记的话，每调一次就多乘一次。
	player.release_pedal()
	for i in 3:
		await host.get_tree().physics_frame
	player.mount_pedal()
	await host.get_tree().process_frame
	var p2 := _find_pedal(m, FlightPedal.Mode.INBOUND)
	if p2 == null:
		t.ok(false, "**第二次呼叫没造出板**（重新呼叫那条路断了）")
	else:
		var dir2 := (p2.global_position - player.global_position).normalized()
		p2.global_position = player.global_position \
			+ dir2 * (FlightPedal.CALL_ARRIVE_DIST + 40.0)
		var arrived2 := false
		for i in 90:
			await host.get_tree().process_frame
			if player.has_pedal():
				arrived2 = true
				break
		t.ok(arrived2, "**重新呼叫**也能到位（脱离之后再来一次）")
		t.near(player.fm.accel, accel_on, 0.01,
			"重新呼叫后 `fm.accel` 与第一次**完全一致**（加成没有被叠加两次）")

	m.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 4 不叠影（B1）

## 骑手模型**不叠影**（★７63-9 B1）。
##
## ## 现场（用户报的）
##
## 「古斯塔夫、梅萨在踏板上的时候会穿模看到梅萨和古斯塔夫的胸部模型」。
##
## ## 根因 —— 是**一类**漏洞，不是一处笔误
##
## 「骑手自己的模型该不该显示」这件事原来有**两个写入者**：
##   ① `FlightPedal.hide_rider_model()` —— 上板时藏一次（**只写一遍**）；
##   ② `main._apply_camera_settings()` —— **每帧**写 `(not first_person) and alive`。
## 后者的条件里**不含「板上已经有人」** ⇒ 下一帧就把藏好的模型顶回来，
## 于是「踏板自带的那份几何」+「骑手自己那份」⇒ **叠影**，且不报任何错。
##
## ## 正解
##
## 把「该不该显示」**升格成两条判据的与**：
##   `_model_wish`（第一人称吗 / 还活着吗） **且** 非 `rider_hidden`（板上有人吗）
## 合成点唯一 = `FlightBody._apply_model_visibility()`（另有 `die()` 直写，它同时把愿望置假）。
## 两家都只**置自己的判据**、谁也不写最终值 ⇒ 没有「谁最后写谁赢」。
##
## ## 四条断言各咬什么
##
##   (a) 源码级 —— `model_root.visible` 的**写入点**在全工程只剩 2 处；
##   (b) 运行时段 —— 上板走**生产路径** ⇒ 判据置真 + 模型在树里真的不可见；
##   (c) 「被别的写入者裸写回来」的那一帧，会被下一次同步纠正
##       （`set_rider_hidden()` **刻意不做**「标志没变就早退」）；
##   (d) 重建视觉层（换形态那条路）之后仍然不可见 —— **第二类**静默漏洞：
##       `Node3D.new()` 的 `visible` 默认 true，而两条判据都可能是否。
static func _rider_vis(t: T, host: Node) -> void:
	# ---- (a) 源码级：唯一写入点 ----
	var body := SuiteUiStyle._code(BODY_SRC)
	var pedal := SuiteUiStyle._code(PEDAL_SRC)
	t.eq(body.count("model_root.visible = "), 2,
		"`flight_body.gd` 里写 `model_root.visible` 的真代码只剩 2 行"
		+ "（`_apply_model_visibility()` 与 `die()`）—— 其余都是读")
	t.eq(pedal.count("model_root.visible"), 0,
		"`flight_pedal.gd` **一行都不裸写** `model_root.visible`（B1 的根因就在这里）")
	t.ok(body.contains("_model_wish and not rider_hidden"),
		"合成式是「愿望 且 非骑手隐藏」—— 两条判据都得满足才显示")
	t.eq(body.count("func set_rider_hidden"), 1,
		"`set_rider_hidden()` 是本字段的唯一写入点")
	t.eq(body.count("_model_wish = false"), 1,
		"`die()` 把**愿望**也置假 —— 只裸写 `model_root.visible` 的话，"
		+ "踏板下一次同步会把残骸显回来")
	t.gt(pedal.count("set_rider_hidden(true)"), 0, "藏这条路走判据")
	t.gt(pedal.count("set_rider_hidden(false)"), 0, "显这条路也走判据")

	# ---- (b) 运行时段：走生产路径上板 ----
	var s := await _rider_without_pedal(host)
	var m: Node = s["m"]
	var player: FlightBody = s["player"]
	var board: FlightPedal = s["pedal"]
	if player == null or board == null:
		t.ok(false, "**呼叫做不出来** —— 不叠影那几条测不了")
		if m != null:
			m.queue_free()
		await host.get_tree().physics_frame
		return

	# 缩短距离让它到位：`_tick_inbound()` → `_complete_pedal_mount()` → `add_rider()` → 藏
	var dir := (board.global_position - player.global_position).normalized()
	board.global_position = player.global_position + dir * (FlightPedal.CALL_ARRIVE_DIST + 40.0)
	var arrived := false
	for i in 90:
		await host.get_tree().process_frame
		if player.has_pedal():
			arrived = true
			break
	t.ok(arrived, "板到位（下面几条的前提）")
	t.ok(player.rider_hidden, "上板把判据置真（`add_rider()` → `hide_rider_model()`）")
	t.not_ok(player.model_visible(),
		"**骑板上自己的模型不可见** —— 这条就是「叠影」的判据")
	t.ok(player.model_root != null and not player.model_root.is_visible_in_tree(),
		"`model_root` 在**整棵树里**也不可见"
		+ "（只断节点存在会被「存在但被藏」骗过去）")
	t.ok(player.visible, "藏的是**模型**：机体节点自己还活着（锚点/炮口/判定都还要用它）")
	t.ok(board.vis_state() != FlightPedal.Vis.EMPTY,
		"板处于载人状态 ⇒ 踏板模型里**自带**机体几何（所以必须藏骑手那一份）")

	# ---- (c) 被别的写入者裸写回来的那一帧，会被下一次同步纠正 ----
	#
	# `main` 原来正是「别的写入者」：它把**最终值**写进 `model_root.visible`。
	# 现在它只能改愿望（`set_model_visible()`），而愿望为真时会被 `rider_hidden` 挡掉。
	player.model_root.visible = true      # 模拟「直接写了最终值」的那一帧
	player.set_rider_hidden(true)         # 踏板的下一次同步（判据**没变**）
	t.not_ok(player.model_visible(),
		"判据没变时也重算一次 ⇒ 被裸写回来的那帧当场纠正"
		+ "（给 `set_rider_hidden()` 加「标志没变就早退」会让这条红）")

	# ---- (d) 重建视觉层之后仍然不可见（第二类静默漏洞）----
	#
	# `_build_visual()` 里 `model_root = Node3D.new()`，`visible` 默认 **true** ——
	# 而「愿望 且 非隐藏」两条判据当时都还可能是否。换形态（`set_form()`）正走这条路：
	# 骑着板换形态 ⇒ 自己那台机体重新出现在板上。
	player.call("_rebuild_visual")        # 走生产路径（直接调 `_build_visual()` 会漏拆旧节点）
	t.not_ok(player.model_visible(),
		"换形态重建视觉层之后**仍然不可见**（新 `model_root` 的默认 true 不许漏出去）")

	# ---- (e) 脱板：恢复的是**判据**，不是「无条件显示」----
	player.release_pedal()
	for i in 3:
		await host.get_tree().physics_frame
	t.not_ok(player.rider_hidden, "脱板把判据置回假（`break_off()` → `set_rider_hidden(false)`）")
	t.ok(player.model_visible(), "第三方视角 + 活着 ⇒ 脱板后自己的模型显回来")

	# ⚠️ 独立判据：愿望是假的时候（第一人称 / 已阵亡），脱板**不许**把它显出来。
	#
	# 这里必须走踏板的**生产函数**（`add_rider()` / `show_rider_model()`），
	# 不能直接调 `set_rider_hidden()` —— 实测（NC-E）直接调 setter 时，
	# 把 `show_rider_model()` 改回裸写 `model_root.visible = true` 只有**源码那条**会红，
	# 运行时这条抓不到。判据要咬在**产品那条路径**上。
	player.set_model_visible(false)       # 第一人称（愿望 = 假）
	board.add_rider(player)               # 上板 → `hide_rider_model()` → 判据置真
	board.show_rider_model(player)        # 「显」这条路的唯一入口
	t.not_ok(player.model_visible(),
		"**脱板不是「无条件显示」**：愿望为假（第一人称/已阵亡）时必须仍不可见")
	player.set_model_visible(true)
	t.ok(player.model_visible(), "愿望收回真 ⇒ 立刻显回来（两条判据各自独立生效）")

	# ---- (f) 尺寸口径：两个「全高」不是同一个量（只钉住，不要求相等）----
	#
	# `SUIT_GAME_HEIGHT`（踏板模型的缩放锚 = 用户给的名义全高）与机体表的
	# `target_height`（按模型包围盒反推）实测差 1.0 m。理由见 `SUIT_GAME_HEIGHT` 那段长注释。
	# ⚠️ 这三条**不是**"要求它们相等"，而是把两个数钉住：
	# 谁将来动了其中一个，都必须来这里说明 —— 动 `SUIT_GAME_HEIGHT` 的代价是
	# **踏板连同嵌在模型里的骑手整体缩放 4.35%**（玩家看得见的板子大小变化）。
	var gustav := SuitProfile.gustav00()
	var messer := SuitProfile.messer_m01()
	t.near(gustav.target_height, 22.0, 0.001,
		"古斯塔夫 00 的 `target_height` = 22.0（模型包围盒反推）")
	t.near(messer.target_height, 22.0, 0.001,
		"梅萨 M01 的 `target_height` = 22.0（同上）")
	t.near(FlightPedal.SUIT_GAME_HEIGHT, 23.0, 0.001,
		"踏板的缩放锚 `SUIT_GAME_HEIGHT` = 23.0（用户给的名义全高）")
	t.near(FlightPedal.SUIT_GAME_HEIGHT - gustav.target_height, 1.0, 0.001,
		"口径差 = 1.0 m（%.2f%%）—— **已知且刻意保留**；要收口就改 `SUIT_GAME_HEIGHT`，"
		% (100.0 * (FlightPedal.SUIT_GAME_HEIGHT - gustav.target_height) / gustav.target_height)
		+ "代价是踏板整体缩小 4.35%（见那里的注释）")

	m.queue_free()
	await host.get_tree().physics_frame

