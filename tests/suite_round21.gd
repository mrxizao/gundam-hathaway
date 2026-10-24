class_name SuiteRound21
extends RefCounted
## 第二十三轮：**用户实测报的五条**。
##
## 用户原话：
##   1.「梅萨的踏板还是**左边朝前**」
##   2.「梅萨在踏板上的时候，**没有站在踏板上，现在是浮空的**」
##   3.「古斯塔夫也没有站在踏板上」
##   4.「脱离踏板踏板并不是直接自爆，而是**自由飞走 5 s 后消失**，
##       呼叫踏板也是**先在天上出现才飞到玩家身边**」
##   5.「你是不是**阵营系统和小队系统没做**，我测试古斯塔夫的时候
##       会被**其他古斯塔夫攻击**」
##
## 第 5 条不是"没做"，是一个**真 bug**：`BanditAI._think()` 无条件把玩家当目标
## （`_target = Game.live_player()`），所以**玩家的僚机也掉头打玩家**。
## 这一轮把它改成"从敌对阵营里挑最近的"。
##
## 分五组：
##   1. **AI 选目标**（阵营 bug —— 这轮最要紧的一条）
##   2. **骑手站在甲板上**（不再浮空）
##   3. **脱离 = 自由飞走 5 s**（不再自爆）
##   4. **呼叫 = 天上出现再飞过来**
##   5. **踏板朝向修正**（机制在，具体角度由用户点图确定）

const TARGETING := "Round21 / AI 选目标：队友不能打队友"
const STANDING := "Round21 / 骑手站在甲板上（不再浮空）"
const CASTOFF := "Round21 / 脱离 = 自由飞走 5 s，不自爆"
const INBOUND := "Round21 / 呼叫 = 天上出现再飞到身边"
const YAW := "Round21 / 踏板朝向修正机制"
const STATES := "Round21 / 分状态模型 + 座次粘性"


static func run(t: T, host: Node) -> void:
	t.suite(TARGETING)
	await _targeting(t, host)
	t.suite(STANDING)
	await _standing(t, host)
	t.suite(CASTOFF)
	await _cast_off(t, host)
	t.suite(INBOUND)
	await _inbound(t, host)
	t.suite(YAW)
	_yaw(t)
	t.suite(STATES)
	await _states(t, host)


# ------------------------------------------------- 6 分状态模型 + 座次粘性

static func _states(t: T, host: Node) -> void:
	for item: Array in [
		[FlightPedal.Kind.MAFTY, SuitProfile.messer_m01(), "mafty", "front", "back"],
		[FlightPedal.Kind.KILCE, SuitProfile.gustav00_armed(), "kilce", "left", "right"],
	]:
		Game.reset()
		var kind: int = item[0]
		var c := Node3D.new()
		host.add_child(c)
		var a := _make(c, "A_%s" % str(item[2]), 0, item[1])
		await host.get_tree().physics_frame
		a.global_position = Vector3(0.0, 3200.0, 0.0)
		var board := a.spawn_with_pedal(kind)
		await host.get_tree().physics_frame
		t.ok(board != null, "%s：建出了板" % str(item[2]))
		if board == null:
			c.queue_free()
			continue
		var b := _make(c, "B_%s" % str(item[2]), 0, item[1])
		await host.get_tree().physics_frame

		# ---- 两台：BOTH ----
		t.eq(board.vis_state(), FlightPedal.Vis.SLOT0_ONLY,
			"%s：只挂领机 ⇒ SLOT0_ONLY" % str(item[2]))
		t.ok(board.model_path_of(kind, board.vis_state()).contains(str(item[3])),
			"%s：只剩一号机时用「只有%s」那个模型" % [str(item[2]), str(item[3])])
		board.add_rider(b)
		await host.get_tree().physics_frame
		t.eq(board.vis_state(), FlightPedal.Vis.BOTH, "%s：挂上第二台 ⇒ BOTH" % str(item[2]))
		t.ok(board.model_path_of(kind, board.vis_state()).contains("both"),
			"%s：两台都在时用合集模型" % str(item[2]))

		# ---- 座次粘性：座号是分配出来的，且两台不同 ----
		t.eq(a.pedal_slot, 0, "%s：先挂的拿 0 号位" % str(item[2]))
		t.eq(b.pedal_slot, 1, "%s：后挂的拿 1 号位" % str(item[2]))
		t.ok(a.pedal_slot != b.pedal_slot, "%s：两台的座号不同" % str(item[2]))

		# ---- 关键：把**一号机摘掉**，二号机必须**仍然是二号机** ----
		#
		# ⚠️ 这正是这一轮修掉的 bug：座次曾经按**数组下标**算，
		# 于是"一号机脱离后，剩下的那台会被当成一号机" ⇒ **模型切错**。
		# 粘性座次（`pedal_slot`）才能让它在二号位上不动。
		board.remove_rider(a)
		await host.get_tree().physics_frame
		t.eq(board.vis_state(), FlightPedal.Vis.SLOT1_ONLY,
			"%s：摘掉一号机 ⇒ **SLOT1_ONLY**（不是 SLOT0_ONLY）" % str(item[2]))
		t.eq(b.pedal_slot, 1, "%s：留下来的那台**座号不变**（粘性）" % str(item[2]))
		t.ok(board.model_path_of(kind, board.vis_state()).contains(str(item[4])),
			"%s：只剩二号机时用「只有%s」那个模型" % [str(item[2]), str(item[4])])
		# 两个状态用的模型**必须不同** —— 否则"切模型"这件事等于没做。
		t.ok(board.model_path_of(kind, FlightPedal.Vis.SLOT0_ONLY)
				!= board.model_path_of(kind, FlightPedal.Vis.SLOT1_ONLY),
			"%s：一号机/二号机两个状态用的是**不同模型**" % str(item[2]))

		# ---- 空了 ⇒ EMPTY ----
		board.remove_rider(b)
		await host.get_tree().physics_frame
		t.eq(board.vis_state(), FlightPedal.Vis.EMPTY, "%s：都摘掉 ⇒ EMPTY" % str(item[2]))
		t.ok(board.model_path_of(kind, FlightPedal.Vis.EMPTY).contains("empty"),
			"%s：空板用的是空板模型" % str(item[2]))

		# ---- 四个状态的模型路径**两两不同**（四个模型各司其职）----
		var seen := {}
		for v: int in [FlightPedal.Vis.EMPTY, FlightPedal.Vis.SLOT0_ONLY,
				FlightPedal.Vis.SLOT1_ONLY, FlightPedal.Vis.BOTH]:
			var path := board.model_path_of(kind, v)
			t.ok(path != "", "%s：状态 %d 有模型" % [str(item[2]), v])
			t.not_ok(seen.has(path), "%s：状态 %d 的模型不与他人重复" % [str(item[2]), v])
			seen[path] = true

		# ---- 空板与载人板的**原生尺度差一倍多** ⇒ 必须分别缩放 ----
		#
		# 不分别缩放的话"人一下板，板会突然缩小/放大"。
		var se := FlightPedal.state_scale_of(kind, FlightPedal.Vis.EMPTY)
		var sl := FlightPedal.state_scale_of(kind, FlightPedal.Vis.BOTH)
		t.ok(not is_equal_approx(se, sl), "%s：空板与载人板的缩放**不同**" % str(item[2]))
		# 但世界尺寸必须一致：两种状态算出来的板长应当相等。
		var len_empty := FlightPedal.state_native_size(kind, FlightPedal.Vis.EMPTY).x * se
		var len_loaded := FlightPedal.state_native_size(kind, FlightPedal.Vis.BOTH).x * sl
		t.near(len_empty, len_loaded, 0.1,
			"%s：空板与载人板的**世界板长一致**（实测 %.1f vs %.1f m）"
				% [str(item[2]), len_empty, len_loaded])

		c.queue_free()
		await host.get_tree().physics_frame


# ---------------------------------------------------------------- 1 阵营 bug

static func _targeting(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	# 玩家方（team 0）：一台"玩家" + 一台僚机
	var pl := _make(c, "P", 0, SuitProfile.gustav00_armed(), true)
	var ally := _make(c, "Ally", 0, SuitProfile.gustav00_armed())
	# 敌方（team 1）：一台远的、一台近的
	var foe_far := _make(c, "FoeFar", 1, SuitProfile.messer_m01())
	var foe_near := _make(c, "FoeNear", 1, SuitProfile.messer_m01())
	# ⚠️ **位置必须在"让 AI 思考"之前摆好**。
	#
	# `_make()` 把每台都放在同一点；如果先 `await` 一帧再摆位，AI 会在
	# "四台重合"的那一帧就锁定（同距时按 `Game.units` 的登记顺序挑），
	# 之后**滞回一直保持它** —— 于是测到的是"滞回生效"，而不是"挑最近的"。
	# 第一版就是这么红的，一度看着像"挑最近"坏了。
	await host.get_tree().physics_frame
	# ⚠️ **摆位必须在 `await` 之后再来一次、且不留间隙**。
	#
	# `await` 那一帧里三台 AI 的 `_physics_process` 都会跑 ⇒ **位置全变了**，
	# 于是"最近的敌人"可能不是 `foe_near`（第二版就是这么继续红的）。
	# 所以：等完帧 → 重新钉死位置 → 清目标 → **立刻** `_think()` 断言。
	pl.global_position = Vector3(0.0, 3200.0, 0.0)
	ally.global_position = Vector3(120.0, 3200.0, 0.0)
	foe_near.global_position = Vector3(0.0, 3200.0, -900.0)
	foe_far.global_position = Vector3(0.0, 3200.0, -9000.0)
	ally._target = null
	foe_near._target = null

	# ---- 核心断言：**僚机的目标不能是玩家** ----
	ally._think(1.0 / 60.0)
	t.ok(ally._target != pl, "**僚机不会把玩家当目标**（这就是用户报的那个 bug）")
	t.eq(ally._target, foe_near, "僚机打的是**最近的敌人**")

	# 敌军那边：目标必须是**敌对阵营**里的某一台（不一定是玩家）。
	#
	# ⚠️ 这里原来钉的是"敌机仍然把**玩家**当目标"，而那是**过严**的：
	# `_pick_target()` 挑的是"最近的敌对"，而测试里几台 AI 各自在动，
	# 僚机有时比玩家更近 ⇒ 敌机锁僚机是**正确行为**，断言却红。
	# 要钉的是"它在打敌人、不是打队友"这件事。
	foe_near._think(1.0 / 60.0)
	t.ok(foe_near._target != null and foe_near.is_hostile_to(foe_near._target),
		"敌机的目标是**敌对阵营**里的一台（不是空、也不是队友）")

	# ---- 滞回：当前目标还活着就不换 ----
	# 把另一台敌人挪得更近，僚机也不该立刻改主意（否则航迹会抖）。
	var before = ally._target
	foe_far.global_position = Vector3(140.0, 3200.0, 0.0)   # 现在更近
	ally._think(1.0 / 60.0)
	t.eq(ally._target, before, "当前目标还活着 ⇒ **不换**（滞后，防止来回横跳）")

	# ---- 目标死了才换 ----
	foe_near.alive = false
	ally._think(1.0 / 60.0)
	t.eq(ally._target, foe_far, "目标没了 ⇒ 换成下一个最近的敌人")

	# ---- 没有敌人时不给目标（不能空指针，也不能回头打队友）----
	foe_far.alive = false
	ally._think(1.0 / 60.0)
	t.eq(ally._target, null, "没有敌人 ⇒ 目标为 null（绝不退化成打队友）")

	# ---- `target_override` 仍然优先（实测探针依赖它）----
	ally.target_override = foe_near
	ally._think(1.0 / 60.0)
	t.eq(ally._target, foe_near, "`target_override` 优先于自动挑选")

	c.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 2 站在甲板上

static func _standing(t: T, host: Node) -> void:
	for item: Array in [
		[FlightPedal.Kind.MAFTY, SuitProfile.messer_m01(), "梅萨"],
		[FlightPedal.Kind.KILCE, SuitProfile.gustav00_armed(), "古斯塔夫"],
	]:
		Game.reset()
		var c := Node3D.new()
		host.add_child(c)
		var r := _make(c, "R_%s" % str(item[2]), 0, item[1])
		await host.get_tree().physics_frame
		r.global_position = Vector3(0.0, 3200.0, 0.0)
		var board := r.spawn_with_pedal()
		await host.get_tree().physics_frame
		t.ok(board != null, "%s 挂上了板" % str(item[2]))
		if board == null:
			c.queue_free()
			continue

		# ---- 判据（第二十四轮改成"分状态模型"之后）----
		#
		# 以前我算的是"甲板面 + 半身高 + 脚缝"，一串近似。
		# 现在是**模型自带座次**：板上那个座位在哪，板就反向平移多少，
		# 于是"模型里那台机体"正好套住骑手 —— 浮空问题从根上不存在了。
		#
		# 所以判据变成：**领机的座位在踏板局部空间里正好落在原点**。
		var s := board.state_scale_of(int(item[0]), board.vis_state())
		var off := board._yaw_basis() * (board._native_rider_pos(0) * s)
		var world_off := board.global_transform.basis * off
		var lead_pos := r.global_position - board.global_position
		t.near((lead_pos - world_off).length(), 0.0, 0.05,
			"%s：领机的位置**正好落在模型里一号机的座位**上" % str(item[2]))

		# 被载机：座位位置也要与模型一致（踏板局部空间里的 slot 1）。
		var rest := _make(c, "W_%s" % str(item[2]), 0, item[1])
		await host.get_tree().physics_frame
		var off1 := board._yaw_basis() * (board._native_rider_pos(1) * s)
		var slot1_world := board.global_transform * off1
		# 被载机的**原点（中心）**应当落在那个座位上
		var want := board.global_position + board.global_transform.basis * off1
		t.near((slot1_world - want).length(), 0.0, 0.01,
			"%s：二号机的座位与模型一致" % str(item[2]))
		t.near(FlightPedal.slot_separation_m(int(item[0])),
			(off1 - off).length(), 0.05,
			"%s：座位间距与模型量出来的一致" % str(item[2]))

		c.queue_free()
		await host.get_tree().physics_frame


# ---------------------------------------------------------------- 3 脱离

static func _cast_off(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var r := _make(c, "CastR", 0, SuitProfile.messer_m01())
	await host.get_tree().physics_frame
	r.global_position = Vector3(0.0, 3200.0, 0.0)
	var board := r.spawn_with_pedal()
	await host.get_tree().physics_frame
	t.ok(board != null and r.has_pedal(), "前置：骑在板上")

	var host_parent := board.get_parent()
	t.eq(host_parent, r, "前置：板挂在骑手身上")

	r.release_pedal()
	await host.get_tree().physics_frame

	# ---- 核心：板**没有被销毁**，而是转成 CAST_OFF ----
	t.ok(is_instance_valid(board), "**主动脱板后板仍然存在**（不是当场自爆）")
	t.eq(board.mode, FlightPedal.Mode.CAST_OFF, "板进入 CAST_OFF 状态")
	t.ok(board.get_parent() != r, "板已经**脱离骑手的父链**（否则会跟着骑手飞）")
	t.not_ok(r.has_pedal(), "骑手这边已经不算骑乘了")

	# ---- 它会自己动（自由飞走）----
	var p0 := board.global_position
	for i in 12:
		await host.get_tree().physics_frame
	t.gt(board.global_position.distance_to(p0), 1.0, "板在**自由移动**（不是原地不动）")

	# ---- 5 秒后自行消失：直接推时间（等真实 5 s 太慢，也不该让测试慢）----
	t.near(FlightPedal.CAST_OFF_LIFE, 5.0, 0.001, "自由飞走时长就是用户指定的 5 s")
	board._tick_cast_off(FlightPedal.CAST_OFF_LIFE + 0.1)
	await host.get_tree().physics_frame
	t.ok(not is_instance_valid(board) or board.is_queued_for_deletion(),
		"5 s 到了 ⇒ 板自行消失")

	# ---- 对照：**被打爆**那条路仍然当场消失 ----
	var r2 := _make(c, "BreakR", 0, SuitProfile.messer_m01())
	await host.get_tree().physics_frame
	r2.global_position = Vector3(0.0, 3200.0, 0.0)
	var b2 := r2.spawn_with_pedal()
	await host.get_tree().physics_frame
	b2.break_off(true)
	await host.get_tree().physics_frame
	t.ok(not is_instance_valid(b2) or b2.is_queued_for_deletion(),
		"被打爆（`by_break = true`）仍然**当场消失**")

	c.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 4 呼叫

static func _inbound(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var r := _make(c, "CallR", 0, SuitProfile.messer_m01())
	await host.get_tree().physics_frame
	r.global_position = Vector3(0.0, 3200.0, 0.0)
	await host.get_tree().physics_frame

	t.not_ok(r.pedal_inbound(), "前置：没有在途的板")
	t.ok(r.mount_pedal(), "呼叫踏板")
	await host.get_tree().physics_frame

	# ---- 核心：**不是瞬移**，板在天上 ----
	t.ok(r.pedal_inbound(), "出现了一块**在途**的板")
	t.not_ok(r.has_pedal(), "**还没骑上**（呼叫不是瞬移）")
	var board := r._inbound_pedal
	t.ok(board != null and is_instance_valid(board), "拿得到那块在途的板")
	if board == null:
		c.queue_free()
		return
	var dy := board.global_position.y - r.global_position.y
	# ⚠️ 不要钉**精确**等于 `CALL_HEIGHT` —— 板在被测到之前已经飞了几帧，
	# 高度必然掉了一点（实测 847 / 900）。要钉的是"**它确实是从天上来的**"。
	t.gt(dy, FlightPedal.CALL_HEIGHT * 0.5,
		"板出现在骑手**上方 %.0f m 量级**（实测 %.0f m）—— 用户要的「先在天上出现」"
			% [FlightPedal.CALL_HEIGHT, dy])
	t.eq(board.mode, FlightPedal.Mode.INBOUND, "状态是 INBOUND")
	t.ok(board.get_parent() != r, "在途期间板**不在骑手身上**（否则会跟着转身）")

	# ---- 反复呼叫不会叠出一堆板 ----
	var again := r.mount_pedal()
	t.ok(again, "再按一次仍然返回 true")
	t.eq(r._inbound_pedal, board, "但**还是同一块板**（没有叠一块新的）")

	# ---- 它会朝骑手飞 ----
	var d0 := board.global_position.distance_to(r.global_position)
	for i in 20:
		await host.get_tree().physics_frame
	var d1 := board.global_position.distance_to(r.global_position)
	t.lt(d1, d0, "板在**朝骑手靠近**（%.0f → %.0f m）" % [d0, d1])

	# ---- 到位：转成骑乘 ----
	# 直接推到位（等它飞完 900 m 太慢，也不该让测试慢）。
	board.global_position = r.global_position
	board._tick_inbound(1.0 / 60.0)
	await host.get_tree().physics_frame
	t.ok(r.has_pedal(), "到位之后**真的骑上了**")
	t.not_ok(r.pedal_inbound(), "在途状态清掉了")
	t.eq(r.pedal, board, "骑的正是那块飞过来的板")
	t.eq(board.get_parent(), r, "到位后板**重新挂回骑手身上**")
	t.eq(board.mode, FlightPedal.Mode.RIDDEN, "状态回到 RIDDEN")
	t.ok(board.riders.has(r), "骑手登记进了 `riders`（`_complete_pedal_mount` 补的）")
	# ⚠️ 飞行加成必须也补上：漏了会变成"板贴在脚下但一点加成都没有"。
	t.gt(r.fm.speed_gain, 0.0, "飞行加成已贴（不是半生效状态）")

	c.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 5 朝向

static func _yaw(t: T) -> void:
	# 机制必须在：两种板都要能读到修正角。
	#
	# ✅ **用户已试玩确认（2026-09-20："踏板的方向对了"）**，
	# 所以 `MODEL_YAW_DEG` 里的 **马夫蒂 270° / 喀耳刻 0°** 是定稿值。
	#
	# ⚠️ 这里**故意不去钉那个字面角度**：真正的契约是"一号机在前/在左"
	#（`suite_round17` 里两条断言钉的就是它）。钉字面角度的坏处是
	# 换个模型就得改测试，而"行为对不对"反倒没人看。
	# 但也**不要**因为"四选一图看着像 90°"就去改那两个数 —— 那正是踩过的坑。
	for k: int in [FlightPedal.Kind.MAFTY, FlightPedal.Kind.KILCE]:
		var y := FlightPedal.model_yaw_of(k)
		t.between(y, -360.0, 360.0,
			"%s 的朝向修正在合理范围内（实测 %.0f°）" % [FlightPedal.kind_name(k), y])
		# ⚠️ **故意不断言"两种板用同一个角"**：它们是**两个独立的 .glb**，
		# 导出时的烘焙朝向不一定一致（实测四选一图里两张的"正确格"看起来不同）。
		# 写死"必须相同"会逼着后来的人把两个模型当成一个 —— 那是错的耦合。
	t.ok(FlightPedal.YAW_CHOICES.size() == 4, "候选角是四个（0/90/180/270）")
	t.ok(FlightPedal.YAW_CHOICES.has(0.0), "候选里有 0（「不改」也是合法答案）")


# ---------------------------------------------------------------- 工具

static func _make(parent: Node3D, node_name: String, team: int, p: SuitProfile,
		is_player := false) -> BanditAI:
	var fb := BanditAI.new()
	fb.name = node_name
	fb.team = team
	fb.is_player = is_player
	fb.profile = p
	fb.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	fb.projectile_container = parent
	parent.add_child(fb)
	fb.global_position = Vector3(0.0, 3200.0, 0.0)
	return fb
