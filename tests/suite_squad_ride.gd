class_name SuiteSquadRide
extends RefCounted
## **编队战的搭乘**（1.2 第二十六轮）。
##
## 用户原话：「开局的时候六台量产机，**只有三台是在踏板上的**。
## 我需要**六台量产机分为 2/2/2 三组都在飞行踏板上**，
## **接近敌人被锁定之后再从飞行踏板上下来**」。
##
## ## 两个真问题
##
## **① 僚机根本没上板**：`main._spawn_side()` 只给领机配了板，
## 后座走的是 `set_formation(lead, 1)` —— 那只是"靠转向跟着飞"，
## `has_pedal()` 为假、板上也只登记着领机一台。
## 于是"一个编队 = 一块板 + 两台"从来没真正成立过，
## 分状态模型也只会显示"只有一号机"。
##
## **② 该下板的时候不下板**：骑板有硬代价（转向钝 ×0.8、不能悬停、不能拔刀），
## 所以"一路骑着板冲进缠斗"是打不赢的。用户要的是
## **赶路靠板、开打靠腿**。
##
## ## ⚠️ 文件名为什么不带轮次
## 这个仓库有另一个会话在并发编辑、按"轮次"占编号。
## 本仓库已经发生过一次"我的 `suite_round22.gd` 被别人的同名文件整个覆盖、
## 而 runner 照样绿"。所以按**主题**命名。

const RIDERS := "SquadRide / 六个量产机都在板上（3 板 × 2 台）"
const CARRIED := "SquadRide / 后座真的被载（位置由踏板驱动）"
const DISMOUNT := "SquadRide / 接近敌人之后下板"


static func run(t: T, host: Node) -> void:
	t.suite(RIDERS)
	await _riders(t, host)
	t.suite(CARRIED)
	await _carried(t, host)
	t.suite(DISMOUNT)
	await _dismount(t, host)


static func _spawn_squad(host: Node) -> Node:
	Game.reset()
	Game.active_suit = SuitProfile.Id.MESSER_M01
	Game.active_side = BattleFormation.Side.MAFTY
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main_scene)
	return main_scene


# ---------------------------------------------------------------- 1 都在板上

static func _riders(t: T, host: Node) -> void:
	var m := _spawn_squad(host)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 16:
		await host.get_tree().physics_frame

	var player = m.get("player")
	t.ok(player != null, "编队战局建起来了")
	# 场上 14 台（两边各 7），其中**量产机 6 台/边**。
	var mp_total := 0
	var on_pedal := 0
	var carried_n := 0
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if not u.has_method("is_alive") or not u.is_alive():
			continue
		# ⚠️ 必须写显式类型：`u.get("profile")` 是 Variant，
		# 不写的话 GDScript 会把 `is_ace()` 解析到**接收者 `u`**（BanditAI）上，
		# 报 "Nonexistent function 'is_ace' in base BanditAI" —— 很难看出是类型问题。
		var p: SuitProfile = u.get("profile")
		if p == null or p.is_ace():
			continue
		mp_total += 1
		if u.has_method("has_pedal") and u.has_pedal():
			on_pedal += 1
		if u.has_method("is_carried") and u.is_carried():
			carried_n += 1
	# 量产机 = 两边各 6 = 12 台
	t.eq(mp_total, 12, "两边合计 **12 台量产机**（每边 6）")
	# ⚠️ **这是用户报的那条**：原来只有 6 台在板上（每边 3 个领机），
	# 现在是 12 台 —— 每台量产机都在某块板上。
	t.eq(on_pedal, 12,
		"**12 台量产机全部在踏板上**（原来只有 6 台 —— 用户实测报的那个 bug）")
	# 后座（被载的）= 每边 3 台 = 6 台
	t.eq(carried_n, 6, "**6 台是被载的后座**（每边 3）")

	m.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 2 真被载

static func _carried(t: T, host: Node) -> void:
	var m := _spawn_squad(host)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 16:
		await host.get_tree().physics_frame

	# 找一对"领机 + 被载"
	var lead: FlightBody = null
	var wing: FlightBody = null
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or not u.has_method("is_carried"):
			continue
		if u.is_carried():
			wing = u
			lead = u.carried_by
			break
	t.ok(wing != null, "找到一台被载的后座")
	if wing == null or lead == null:
		m.queue_free()
		return
	t.ok(lead.has_pedal(), "领机有一块板")
	t.ok(wing.has_pedal(), "**后座也算骑着**（`pedal_owner()` 沿 carried_by 找上去）")
	t.eq(wing.pedal_owner(), lead.pedal_owner(), "两台骑的是**同一块板**")
	# ⚠️ `is_ace()` 在 **`SuitProfile`** 上，不在机体上 —— 写 `wing.is_ace()`
	# 会抛 `Nonexistent function`，而**异常会中断这个测试函数**、
	# 把它后面的断言全部跳过（套件照样报数，只是少测）。
	# 这一类"静默少测"本仓库已经抓到三次，写断言时一律先把类型写清楚。
	t.ok(not wing.profile.is_ace(), "被载的是量产机")
	# 板上**登记了两位**
	var board := lead.pedal_owner()
	t.eq(board.riders.size(), 2, "板上登记了 **2 位骑手**（原来只有 1 位）")
	t.eq(board.vis_state(), FlightPedal.Vis.BOTH,
		"可视状态是 **BOTH** ⇒ 会显示「两台都在」那个模型")
	# 后座的位置 = 踏板挂位（由 `_apply_carried()` 驱动，不是自己飞）
	var want: Vector3 = board.slot_world_position(wing.pedal_slot)
	t.near(wing.global_position.distance_to(want), 0.0, 2.5,
		"后座贴在**挂位**上（实测偏差 %.2f m）" % wing.global_position.distance_to(want))
	# 后座与领机不同座
	t.ok(wing.pedal_slot != lead.pedal_slot, "两台的座号不同")

	m.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 3 接近就下板

static func _dismount(t: T, host: Node) -> void:
	# 用两台 AI 直接测（不起整局，快且确定）。
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var lead := BanditAI.new()
	lead.team = 1
	lead.profile = SuitProfile.messer_m01()
	lead.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	lead.projectile_container = c
	c.add_child(lead)
	lead.global_position = Vector3(0.0, 3200.0, 0.0)
	await host.get_tree().physics_frame
	var board := lead.spawn_with_pedal()
	await host.get_tree().physics_frame
	t.ok(board != null and lead.has_pedal(), "前置：领机骑着板")

	var foe := BanditAI.new()
	foe.team = 0
	foe.profile = SuitProfile.messer_m01()
	foe.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	# ⚠️ **敌机必须在"让 AI 思考"之前就摆远**。
	#
	# 第一版先建在原点（和领机同一位置）再 `await` 一帧 ——
	# 那一帧里 `_maybe_dismount_for_combat()` 就跑了，距离 0 ≤ 阈值 ⇒
	# **当场下板**，于是"还太远时不该下板"那条断言从一开始就注定红。
	# 这和 `suite_round21` 里"先摆位、再让 AI 思考"是同一个坑。
	foe.projectile_container = c
	c.add_child(foe)
	foe.global_position = Vector3(0.0, 3200.0, -(BanditAI.SQUAD_DISMOUNT_DIST + 1200.0))
	await host.get_tree().physics_frame

	# ---- ① 还太远：不该下板 ----
	Game.match_mode = Game.MatchMode.SQUAD
	foe.global_position = Vector3(0.0, 3200.0, -(BanditAI.SQUAD_DISMOUNT_DIST + 1200.0))
	lead._think(1.0 / 60.0)
	t.ok(lead.has_pedal(), "距离还超过阈值 ⇒ **骑着板继续赶路**")

	# ---- ② 进入阈值：主动脱离 ----
	foe.global_position = Vector3(0.0, 3200.0, -(BanditAI.SQUAD_DISMOUNT_DIST - 500.0))
	lead._think(1.0 / 60.0)
	await host.get_tree().physics_frame
	t.not_ok(lead.has_pedal(), "**接近敌人 ⇒ 从踏板上下来**（这就是用户要的那一步）")
	# 主动脱离**不吃伤害、不进失能**（和"被打爆"区分开）
	t.near(lead.stagger_left(), 0.0, 0.001, "主动下板**不进失能**")

	# ---- ③ 非编队战不下板（1v1/训练表现不变）----
	Game.match_mode = Game.MatchMode.VERSUS
	var b2 := lead.spawn_with_pedal()
	await host.get_tree().physics_frame
	t.ok(lead.has_pedal(), "重新上板")
	foe.global_position = Vector3(0.0, 3200.0, -200.0)
	lead._think(1.0 / 60.0)
	t.ok(lead.has_pedal(), "**非编队战**里贴脸也不下板（不改动 1v1 / 训练的行为）")

	c.queue_free()
	await host.get_tree().physics_frame
