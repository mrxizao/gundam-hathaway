class_name SuiteMissionPedal
extends RefCounted
## 关卡里的飞行踏板配板 —— **双方量产机都踩板出击**（轮 54）。
##
## 老板原话：「古斯塔夫出击的时候应该要踩着飞行踏板的」，
## 追问后口径定为「剧情关**双方**量产机都配板」。
##
## ## 三侧的板来源互不相干，坏起来的样子也完全不同
##
## | 侧 | 板是哪来的 | 坏掉的样子 |
## |---|---|---|
## | **玩家** | `main.spawn_challenge()` 里那一行 `player.spawn_with_pedal()` | **静默**：他照样出生、照样能打，只是少块板 —— 正是这次要修的那件事 |
## | **敌机** | `_spawn_wave()` → `_attach_ai()`（`with_pedal` **默认为 true**） | 整队空手登场 |
## | **友军** | `_spawn_mission_allies()` → `_spawn_side()`（编队领机） | 僚机飘着飞、`pedal_owner()` 找不到板 |
##
## ## ★ 判据为什么不写成"哪一关该有板"的表
##
## 期望值一律**从 `SuitProfile.can_ride_pedal()` 推**：
## `body.has_pedal() == body.profile.can_ride_pedal()`。
## 这样"以后新加一关 / 换机体"时判据自动跟着走，不会变成一张过期名单。
##
## ⚠️ 但**必须同时钉住 `can_ride_pedal()` 本身**（§1）—— 否则整组断言会随着它
## 一起烂掉：「该有板」与「实际有板」两边同时变 false 仍然恒等，
## 那是一条**派生量自比**的假判据。
##
## ## ★ 轮 54b：连"哪几关存在"也不写死
##
## §1 原来有一张写了八行的 `want` 表（哪一关该有板），结果两个方向都翻过车：
##   · **漏**：只写了七关 ⇒ M04 整整一关不被检查（静默通过、汇总照样全绿）；
##   · **旧**：并行会话重构战役表（删一关、关号前移）之后 `M08` 从 `MS.all()`
##     里消失 ⇒ 表里那一行只剩"不存在"。
## ⇒ 现在一律**遍历 `MS.all()`**（任务表的唯一真源），任务表增删关卡时自动跟着走。
## 剩下**人写的事实**只有三条，全部可证伪：
##   ① §1 顶上那 7 条 `can_ride_pedal()`（整节的**锚**）；
##   ② 老板点名的 **M02 / M03** 的玩家机必须可骑；
##   ③ **"至少 3 关玩家开可骑机体"**这个数（掉了 ⇒ 需求的前提没了，不是 bug）。
## 外加一条**覆盖闸门**：玩家开可骑机体的关，一关都不能漏进 `LIVE_IDS`。
##
## ⚠️⚠️ `SuitProfile.by_id()` 的兜底是 `return xi()` —— **它从不返回 null**。
## 所以 `by_id(x) != null` 形状的判据**恒真**（假绿）；唯一可靠的形状是
## **回环比对** `by_id(x).id == x`。（轮 54b 实测：这条抓的就是"某关指向了
## 一个不存在的机体 id ⇒ 静默变成柯西"。）
##
## ⚠️ 本套件**不引用任何别的套件的 `class_name` / 工具函数**（轮 49 的教训：
## `SuiteUiStyle` 被十个套件引用，那个文件一解析失败，引用它的套件就
## "判据消失"而不是"变红"）。要用的东西全写在本文件里。

const MS := preload("res://scripts/data/mission_script.gd")

## 真机要进哪几关。**不是全部** —— 每关都要重建一整张地图：
##   · M01 是唯一撒友军编队的关（板要与僚机共用，且玩家会被配两次板 ⇒ 幂等）；
##   · M02 是老板点名的那一关（玩家开古斯塔夫00）；
##   · M03 是另一台量产机（梅萨指挥官型）—— 证明"不是只给古斯塔夫特判"；
##   · M05 是 ACE 机的反面对照（玩家开柯西，不该有板）。
## 其余关的玩家同样是柯西（自 M04《重力》起）⇒ 与 M05 同一条代码路径，不重复建图。
##
## ⚠️ 这份名单**必须覆盖所有"玩家开可骑机体"的关** —— 但**别靠这份注释自律**：
##    §1 末尾有一条按 `MS.all()` 逐关查的**覆盖闸门**，漏一关就红
##    （轮 54 首版就是漏了 M04，而当时 M04 的玩家正是梅萨M01）。
const LIVE_IDS := ["M01", "M02", "M03", "M05"]


static func run(t: T, host: Node) -> void:
	# ⚠️ 运行器**只在失败时打标签** ⇒ "每节跑了几条"必须显式打出来，
	# 否则"判据消失"（套件解析失败 / 某节被跳过 / 提前 return）在汇总里
	# 照样读成 `0 FAIL`（轮 49 的坑：某套件从 25 条静默掉到 12 条而汇总全绿）。
	#
	# ★★ `prev` 的**初值不能写 0**（轮 54 全量回归抓出来的自己一个 bug）：
	#    单跑 `--only=suite_mission_pedal` 时全局计数确实从 0 起，看着一切正常；
	#    但**全量回归**跑到这里时前面套件已经累计了 1 万多条 ⇒ `now - 0` 打印出
	#    `§1 …：11910 条`，而 `gt(n, lo-0.5)` 因为 n 巨大而**恒真** ——
	#    §1 的「条数下限闸门」在唯一真正需要它的场合里**形同虚设**。
	#    ⇒ 先把当前全局计数当基线，闸门才真的量的是"这一节"。
	var c := t.passed + t.failed
	t.suite("MissionPedal / 资格与板型（纯函数 · 下面所有判据的基准）")
	_eligibility(t)
	c = _count(t, "§1 资格与板型", c, 23)
	t.suite("MissionPedal / 真机逐关：玩家 / 敌机 / 友军的板")
	await _live(t, host)
	c = _count(t, "§2 真机逐关（M01/M02/M03/M05）", c, 51)
	t.suite("MissionPedal / 装备板是幂等的（同一块板、骑手不重复登记）")
	await _idempotent(t, host)
	c = _count(t, "§3 幂等", c, 6)
	t.suite("MissionPedal / 反面对照：非关卡模式不受影响")
	await _outside(t, host)
	c = _count(t, "§4 反面对照（1v1）", c, 3)


## 记"这一节跑了几条"并显式打出来，同时给它一个**条数下限**。
##
## ⚠️ 条数下限不是凑数：某节整节消失时（解析失败 / 中途 `return`），
## 汇总仍然是 `0 FAIL` —— 只有这条闸门会红。
static func _count(t: T, tag: String, prev: int, lo: int) -> int:
	var now := t.passed + t.failed
	var n := now - prev
	print("[r54] %s：%d 条" % [tag, n])
	t.gt(float(n), float(lo) - 0.5, "%s 至少 %d 条（整节消失会在这里红）" % [tag, lo])
	return now


# ---------------------------------------------------------------- §1 基准
## **谁可骑** + **谁骑哪块**。
##
## ⚠️ 这一节的存在理由不是"再抄一遍 `can_ride_pedal()`" —— 它是后面所有
## 「该有板 == 实际有板」判据的**锚**。锚没了，那些判据会在两边同时变假时静默变绿。
static func _eligibility(t: T) -> void:
	t.ok(SuitProfile.gustav00().can_ride_pedal(), "古斯塔夫00 可骑（它不是 ACE 机）")
	t.ok(SuitProfile.messer_m01().can_ride_pedal(), "梅萨M01 可骑")
	t.ok(SuitProfile.messer_cmd().can_ride_pedal(), "梅萨指挥官型 可骑")
	t.ok(SuitProfile.messer_f01().can_ride_pedal(), "梅萨F01 可骑")
	t.not_ok(SuitProfile.xi().can_ride_pedal(), "柯西**不可骑**（ACE 机）")
	t.not_ok(SuitProfile.penelope().can_ride_pedal(), "佩涅罗佩**不可骑**（ACE 机）")
	t.not_ok(SuitProfile.arizeus().can_ride_pedal(), "阿利宙斯**不可骑**（ACE 机）")

	# 板型：**不是按阵营判，而是按"这块板烤的是不是它自己"**（N62 修正）。
	# ⚠️ 这条原来写的是"指挥官型 → 马夫蒂板" —— 那是把阵营当成了板型。
	# `mafty_*` 那套搭乘态里烤死的是**量产型 M01**，指挥官型骑上去会被画成量产型。
	t.eq(FlightPedal.kind_for_suit(SuitProfile.Id.GUSTAV00), FlightPedal.Kind.KILCE,
		"古斯塔夫（联邦 / 喀耳刻部队）→ 喀耳刻板")
	t.eq(FlightPedal.kind_for_suit(SuitProfile.Id.MESSER_CMD), FlightPedal.Kind.MESSER_CMD,
		"★ 梅萨指挥官型 → **指挥官型板**（板上烤的是它自己，不是量产型）")
	t.eq(FlightPedal.kind_for_suit(SuitProfile.Id.MESSER_M01), FlightPedal.Kind.MAFTY,
		"梅萨M01（马夫蒂）→ 马夫蒂板")

	# ---- 逐关：**玩家机 ⇒ 该不该有板** ----
	#
	# ⚠️ 这里**不维护"哪一关该有板"的名单**。轮 54 首版写了一张开八行的表，
	#    结果两个方向都翻车：
	#      · **漏**：只写了七关 ⇒ M04 整整一关不被检查（静默通过，汇总照样全绿）；
	#      · **旧**：并行会话重构战役表（删一关、关号前移）之后 `M08` 从
	#        `MS.all()` 里消失 ⇒ 表里那一行只剩"不存在"三个字。
	#    ⇒ 改成**遍历 `MS.all()`**（任务表的唯一真源），逐关把玩家机查出来并打印。
	#      可骑与否不在这里重新锚定 —— 锚在 §1 开头那 7 条 `can_ride_pedal()` 上。
	#
	# ⚠️⚠️ 判断"这个玩家机 id 是不是一个真机体"**不能**写成 `by_id(x) != null`：
	#      `SuitProfile.by_id()` 的兜底是 `return xi()` —— 它**从不返回 null**，
	#      那种形状的判据**恒真**（一条假绿）。唯一可靠的形状是**回环比对**
	#      `by_id(x).id == x`：兜底成柯西时 `id` 对不上，当场红。
	for m: MS.Mission in MS.all():
		var p := SuitProfile.by_id(m.player_suit)
		t.eq(p.id, m.player_suit,
			"%s（%s）：玩家机 id=%d 是**真机体**（没被兜底成柯西）" % [m.id, m.title, m.player_suit])
		print("[r54]   %s《%s》 玩家 = %-12s 可骑 = %s"
			% [m.id, m.title, p.display_name, str(p.can_ride_pedal())])

	# ★ 老板**点名**的两关（原话：「M02 和 M03 都应该有板」）。
	#   钉的是"这两关的玩家是谁"这个**人写的事实**（不是把 `can_ride_pedal()` 抄一遍）：
	#   哪天有人把 M02 / M03 的玩家机换成 ACE 机，这里当场红。
	for boss_id: String in ["M02", "M03"]:
		var bm: MS.Mission = MS.by_id(boss_id)
		t.ok(bm != null, "老板点名的 %s 还在任务表里" % boss_id)
		if bm == null:
			continue
		var bp := SuitProfile.by_id(bm.player_suit)
		var bp_name: String = bp.display_name if bp != null else "查不到"
		t.ok(bp != null and bp.can_ride_pedal(),
			"老板点名：%s 的玩家机（%s）必须**可骑**" % [boss_id, bp_name])

	# ★ 数量闸门：**"剧情关双方量产机都配板"这件事的前提** —— 玩家得有量产机开。
	#   现在是 3 关（M01 梅萨M01 / M02 古斯塔夫00 / M03 梅萨指挥官型）。
	#   这个数掉下去**不等于 bug**，而是"老板那条需求的前提没了"（玩家机全成了 ACE）
	#   —— 两种情况的处置完全不同，所以要能分开。
	var n_ride := 0
	for m2: MS.Mission in MS.all():
		var p2 := SuitProfile.by_id(m2.player_suit)
		if p2 != null and p2.can_ride_pedal():
			n_ride += 1
	t.gt(float(n_ride), 2.5, "★ 至少 3 关的玩家开**可骑的量产机**（本任务表里是 %d 关）" % n_ride)

	# ★★ 覆盖闸门：**玩家开可骑机体的关，必须每一关都进 `LIVE_IDS` 真跑一遍**。
	#   轮 54 首版没有它 —— `LIVE_IDS` 漏了当时开着梅萨M01 的 M04，
	#   而"少跑一关"的症状是**什么都没发生**（不多红、也不少绿）。
	#   派生侧的锚 = §1 开头那 7 条 `can_ride_pedal()` 断言（它们红 ⇒ 这一条不作数）。
	#   ⚠️ 这一条**可以变红**（负对照：把 "M01" 从 `LIVE_IDS` 里删掉）。
	for m3: MS.Mission in MS.all():
		var p3 := SuitProfile.by_id(m3.player_suit)
		if p3 != null and p3.can_ride_pedal():
			t.ok(LIVE_IDS.has(m3.id),
				"覆盖：%s（%s）的玩家开 %s（可骑）⇒ 必须在 `LIVE_IDS` 里"
				% [m3.id, m3.title, p3.display_name])


# ---------------------------------------------------------------- §2 真机
## 起局，把这一关**三侧**的板都量一遍。
static func _live(t: T, host: Node) -> void:
	var tree := host.get_tree()
	for id: String in LIVE_IDS:
		var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
		host.add_child(main)
		await tree.process_frame
		# ⚠️ `--only=` 过滤的是**路径**不是显示名 —— 这一套件的路径是
		# `res://tests/suite_mission_pedal.gd`（跑法见文件头）。
		if not bool(main.call("_resolve_campaign_match", id)):
			t.ok(false, "%s 能解析（`_resolve_campaign_match` 返回了 false）" % id)
			main.queue_free()
			await tree.process_frame
			continue
		main.call("_launch_match")
		for i in 6:
			await tree.physics_frame
		var pl: FlightBody = main.get("player")
		if pl == null or not is_instance_valid(pl):
			t.ok(false, "%s 里玩家起来了" % id)
			main.queue_free()
			await tree.process_frame
			continue
		t.ok(pl.alive, "%s：玩家是活的（下面几条读的是真机体）" % id)

		# ---- ① 玩家 ----
		var can: bool = pl.profile.can_ride_pedal()
		t.eq(pl.has_pedal(), can, "%s：%s 的踩板状态 == 可骑资格（%s）"
			% [id, pl.profile.display_name, str(can)])
		if can:
			var b := pl.pedal_owner()
			t.ok(b != null and is_instance_valid(b), "%s：有板 ⇒ `pedal_owner()` 不为空" % id)
			if b != null and is_instance_valid(b):
				t.eq(b.kind, FlightPedal.Kind.GUSTAV_SINGLE if id == "M02" else FlightPedal.kind_for_suit(pl.profile.id),
					"%s：板型按阵营 = %s" % [id, FlightPedal.kind_name(b.kind)])
				t.ok(b.riders.find(pl) >= 0, "%s：玩家本人登记在 `riders` 里" % id)
				t.ok(b.alive, "%s：板是活的" % id)
			t.eq(_count_pedals(pl), 1, "%s：玩家身上只有**一块**板" % id)
		else:
			# ★ 真机版的 ACE 门禁：硬叫一块板也拿不到（不是"恰好没人给他配"）。
			var got = pl.spawn_with_pedal()
			t.ok(got == null and not pl.has_pedal(),
				"%s：★ `spawn_with_pedal()` 对 ACE 机返回 null、板也没挂上" % id)

		# ---- ② 敌机（`_attach_ai()` 给的）----
		#
		# ⚠️ 期望值要**按这一关的设定**，不是"一律 > 0"：
		# M01「夜袭达沃」在轮 50 被老板改成**零敌机**（纯突袭 —— 目标是对酒店开光束枪）。
		# 第一版这里写死 `t.gt(foes.size(), 0)` 当"尺子非空守卫"，在 M01 上直接**假红**
		# （读数 `0.0000 > 0.0000`）—— 守卫本身必须从数据推，不能写死。
		var m: MS.Mission = Game.active_mission
		t.ok(m != null, "%s：`Game.active_mission` 就位" % id)
		var foes := Game.live_hostiles_of(pl)
		if m != null and m.has_enemies():
			t.gt(foes.size(), 0, "%s：这一关设了敌机 ⇒ 场上真有敌对单位" % id)
		else:
			t.eq(foes.size(), 0, "%s：这一关**设定就是零敌机** ⇒ 场上确实一台都没有" % id)
		for f in foes:
			if f == null or not is_instance_valid(f) or f.profile == null:
				continue
			var fcan: bool = f.profile.can_ride_pedal()
			t.eq(f.has_pedal(), fcan, "%s：敌机 %s 的板 == 可骑资格（%s）"
				% [id, f.profile.display_name, str(fcan)])
			if fcan and f.has_pedal():
				t.eq(f.pedal_owner().kind, FlightPedal.kind_for_suit(f.profile.id),
					"%s：敌机 %s 的板型按阵营" % [id, f.profile.display_name])

		# ---- ③ 友军（`_spawn_side()` 给的；只有 M01 有）----
		var n_ally := 0
		for u in _units(main):
			if u == pl or not (u is FlightBody) or u.profile == null or u.team != 0:
				continue
			n_ally += 1
			t.eq(u.has_pedal(), u.profile.can_ride_pedal(),
				"%s：友军 %s 的板 == 可骑资格" % [id, u.profile.display_name])
		if id == "M01":
			t.eq(n_ally, 5, "M01 的僚机是 5 台（3 板 × 2 台，另半格是玩家自己）")
			# ★ M01 是**唯一**同时走两条配板路的关：`spawn_challenge()` 那一行
			# 先给玩家配一块，随后 `_spawn_mission_allies()` → `_spawn_side()`
			# 又给编队领机配一次 ⇒ 幂等必须成立，僚机也得挂到**同一块**板上。
			var b1 := pl.pedal_owner()
			t.eq(b1.riders.size() if b1 != null else -1, 2,
				"M01：玩家与僚机**共用同一块板**（`riders` 应为 2）")
		else:
			t.eq(n_ally, 0, "%s 没有友军编队（这是这一关的既有设定）" % id)

		main.queue_free()
		await tree.process_frame
		Game.reset()


# ---------------------------------------------------------------- §3 幂等
## `spawn_with_pedal()` 是"出装配板"的公共入口，`spawn_challenge()` 与
## `_spawn_side()` **都会调它**（M01 的玩家两处都走到）。
##
## 它必须幂等：否则会建出**第二块板** —— 而 `pedal` 只有一个槽，
## 第二块就成了孤儿节点（还挂在机体下），`has_pedal()` 仍为真 ⇒ 静默。
static func _idempotent(t: T, host: Node) -> void:
	var tree := host.get_tree()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await tree.process_frame
	if not bool(main.call("_resolve_campaign_match", "M02")):
		t.ok(false, "M02 能解析")
		main.queue_free()
		await tree.process_frame
		return
	main.call("_launch_match")
	for i in 6:
		await tree.physics_frame
	var pl: FlightBody = main.get("player")
	t.ok(pl != null and is_instance_valid(pl), "M02 局起来了")
	if pl == null or not is_instance_valid(pl):
		main.queue_free()
		await tree.process_frame
		return

	var b1 := pl.pedal_owner()
	t.ok(b1 != null and is_instance_valid(b1), "前提：M02 玩家出征时就踩着板")
	if b1 == null or not is_instance_valid(b1):
		main.queue_free()
		await tree.process_frame
		return
	var n1 := b1.riders.size()
	var again = pl.spawn_with_pedal()
	t.eq(again, b1, "再调一次 ⇒ 拿到的是**同一块板**")
	t.eq(pl.pedal_owner(), b1, "`pedal_owner()` 也没换人")
	t.eq(b1.riders.size(), n1, "`riders` 没被重复登记（%d → %d）" % [n1, b1.riders.size()])
	t.eq(_count_pedals(pl), 1, "玩家身上仍然只有一块板（没建出孤儿板）")

	main.queue_free()
	await tree.process_frame
	Game.reset()


# ---------------------------------------------------------------- §4 反面对照
## 这一改动只落在 `spawn_challenge()` 上 ⇒ 别的模式不受影响。
##
## 为什么必须单独测：`spawn_challenge()` 与 `spawn_versus()` / `spawn_squad()` /
## `spawn_training()` 是**四个并列的入口**，把它们搞混（比如把那行写到
## `spawn_round()` 里）不会有任何报错 —— 只会让 1v1 / 编队战 / 训练的玩家
## 凭空多一块板，而那几种模式的玩家手册、HUD 与"骑板时不能悬停"的手感全跟着变。
static func _outside(t: T, host: Node) -> void:
	var tree := host.get_tree()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await tree.process_frame
	main.call("_on_start_match", SuitProfile.Id.GUSTAV00, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, SuitProfile.Id.MESSER_M01)
	for i in 6:
		await tree.physics_frame
	var pl: FlightBody = main.get("player")
	t.ok(pl != null and is_instance_valid(pl), "1v1 局起来了")
	if pl != null and is_instance_valid(pl):
		# ⚠️ 前提断言：这一局的机**是可骑的** —— 否则"没有板"可能只是因为它骑不了，
		# 这条对照就什么都没证明（一条假绿）。
		t.ok(pl.profile.can_ride_pedal(), "前提：这一局玩家开的古斯塔夫**是可骑的**机")
		t.not_ok(pl.has_pedal(),
			"★ 1v1 里玩家开量产机**不配板** ⇒ `spawn_challenge()` 那一行没有外溢到别的模式")
	main.queue_free()
	await tree.process_frame
	Game.reset()


# ---------------------------------------------------------------- 小工具
## `units_root` 的子节点（玩家 / 僚机 / 敌机都在这里）。
static func _units(main: Node) -> Array:
	var root: Node = main.get("units_root")
	if root == null or not is_instance_valid(root):
		return []
	return root.get_children()


## 这台机体身上挂了几块板（板是 `add_child` 到骑手自己的，见 `configure_pedal()`）。
static func _count_pedals(body: Node) -> int:
	var n := 0
	for c in body.get_children():
		if c is FlightPedal:
			n += 1
	return n
