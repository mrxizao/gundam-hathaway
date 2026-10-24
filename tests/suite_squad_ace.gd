class_name SuiteSquadAce
extends RefCounted
## ★63-9 · B4「小队战选敌方是阿利宙斯，实际来的是佩涅罗佩」。
##
## 五段判据（对着设计文档 §2.4 的第 1~5 条）：
##   ① 纯函数 —— `lineup()` 第三参能点名敌方 ACE；**不传时旧行为逐位不变**；
##   ② 同阵营守卫 —— 跨阵营的点名必须被接住（退到本阵营的量产机），绝不跨阵营；
##   ③ 接线（菜单）—— 编队战下把 `enemy_index` 拨到阿利宙斯，`start_match` 第 5 个参数 == ARIZEUS；
##   ④ 菜单池 —— 编队战下候选池 = **敌方阵营的 ACE 池**（不含跨阵营的机）；
##   ⑤ 端到端 —— `spawn_squad()` 之后，敌方那边真的出现玩家点的那台。
##
## ⚠️ 判据①②是**纯函数**（不建场景，秒级）；③④只用 `MainMenu.new()`（不建主场景）；
## 只有⑤要起一局编队战。分三段挂是为了让红灯一眼看出是哪一层坏的。

const SUIT_XI := SuitProfile.Id.XI
const SUIT_PENELOPE := SuitProfile.Id.PENELOPE
const SUIT_ARIZEUS := SuitProfile.Id.ARIZEUS
const SUIT_GUSTAV := SuitProfile.Id.GUSTAV00
const SUIT_MESSER := SuitProfile.Id.MESSER_M01


static func run(t: T, host: Node) -> void:
	t.suite("SquadAce / 编制可以为敌方 ACE 点名（B4）")
	_pure(t)
	t.suite("SquadAce / 菜单：敌机池与出击参数（B4）")
	_menu(t)
	t.suite("SquadAce / 端到端：敌方 ACE 真的是那台（B4）")
	await _spawn(t, host)


# ================================================================ ① ② 纯函数
static func _pure(t: T) -> void:
	var fed := BattleFormation.Side.FEDERATION
	var maf := BattleFormation.Side.MAFTY

	# ---- 「对面是谁」的唯一真源 ----
	t.eq(BattleFormation.opposing(maf), fed, "马夫蒂的对面是联邦")
	t.eq(BattleFormation.opposing(fed), maf, "联邦的对面是马夫蒂")
	t.eq(BattleFormation.opposing(BattleFormation.opposing(fed)), fed, "对面取两次回来（幂等）")

	# ---- ① 点名生效 ----
	t.eq(_ace_of(BattleFormation.lineup(fed, -1, SUIT_ARIZEUS)), SUIT_ARIZEUS,
		"联邦那边可以被点名成阿利宙斯（用户要的就是这条）")
	t.eq(_ace_of(BattleFormation.lineup(maf, -1, SUIT_XI)), SUIT_XI,
		"马夫蒂那边点名柯西（它本来就是 `aces[0]`，照样成立）")
	t.eq(BattleFormation.lineup(fed, -1, SUIT_ARIZEUS).size(),
		BattleFormation.unit_count_per_side(),
		"点名**只换 ACE 那一个槽**，台数不变")

	# ---- ①的负对照（同一条断言里钉住旧行为）----
	t.eq(_ace_of(BattleFormation.lineup(fed, -1)), SUIT_PENELOPE,
		"不传第三参 ⇒ 仍然给出 `aces[0]`（佩涅罗佩）—— 旧行为逐位不变")

	# ---- ② 同阵营守卫：跨阵营的点名必须被接住 ----
	var cross := _ace_of(BattleFormation.lineup(fed, -1, SUIT_MESSER))
	t.ok(BattleFormation.belongs_to(fed, cross),
		"跨阵营点名（梅萨M01 点给联邦）被接住：退回来的那台仍属联邦（%s）"
			% SuitProfile.by_id(cross).display_name)
	t.eq(cross, SUIT_GUSTAV, "退到的就是联邦自己的量产机")
	t.eq(_foreign_count(BattleFormation.lineup(fed, -1, SUIT_MESSER), fed), 0,
		"整份名单里一台跨阵营的机都没有")
	t.eq(_foreign_count(BattleFormation.lineup(fed, -1, SUIT_ARIZEUS), fed), 0,
		"点名成阿利宙斯之后同样一台跨阵营的机都没有")
	# 反向也来一次：给马夫蒂点名联邦的佩涅罗佩
	t.eq(_ace_of(BattleFormation.lineup(maf, -1, SUIT_PENELOPE)), SUIT_MESSER,
		"给马夫蒂点名联邦的佩涅罗佩 ⇒ 退到马夫蒂自己的量产机")


# ================================================================= ③ ④ 菜单
static func _menu(t: T) -> void:
	var m := MainMenu.new()
	t.ok(m.select_mode(Game.MatchMode.SQUAD), "菜单能摆到小队战")

	# ---- ④ 池子 = 敌方阵营的 ACE 池 ----
	m.set("side_index", 0)          # 玩家选马夫蒂
	t.eq(m.enemy_pool(), [SUIT_PENELOPE, SUIT_ARIZEUS],
		"玩家选马夫蒂 ⇒ 敌方是联邦 ⇒ 候选 {佩涅罗佩, 阿利宙斯}")
	for id: int in m.enemy_pool():
		t.ok(BattleFormation.belongs_to(BattleFormation.Side.FEDERATION, id),
			"候选里的每一台都必须属于敌方阵营（%s）" % SuitProfile.by_id(id).display_name)

	m.set("side_index", 1)          # 玩家选联邦
	t.eq(m.enemy_pool(), [SUIT_XI],
		"玩家选联邦 ⇒ 敌方是马夫蒂 ⇒ 候选只有柯西")
	for id: int in m.enemy_pool():
		t.ok(BattleFormation.belongs_to(BattleFormation.Side.MAFTY, id),
			"同上：%s 属于马夫蒂" % SuitProfile.by_id(id).display_name)

	# 池子换了长度，下标必须被夹住（跨模式留下来的 `enemy_index` 可能是旧的）
	m.set("enemy_index", 2)
	t.eq(m.enemy_index_now(), 0, "池子只剩 1 台时，旧下标 2 被夹回 0（越界会当场抛错）")
	t.eq(m.selected_enemy(), SUIT_XI, "夹过之后选中的就是池子里唯一那台")

	# ---- 对战那一路不许被改：还是原来三台 ----
	t.ok(m.select_mode(Game.MatchMode.VERSUS), "菜单能摆到对战")
	t.eq(m.enemy_pool(), MainMenu.ENEMY_SUITS,
		"对战模式的敌机池仍是写死那三台（含跨阵营的柯西 —— 镜像战靠它）")

	# ---- ③ 接线：编队战下出击参数里的第 5 项 ----
	t.ok(m.select_mode(Game.MatchMode.SQUAD), "再摆回小队战")
	m.set("side_index", 0)          # 马夫蒂 ⇒ 敌方联邦
	m.set("suit_index", 0)
	m.set("enemy_index", 1)         # 联邦池里第 2 台 = 阿利宙斯
	if m.enemy_pool().size() > 1:
		t.eq(m.selected_enemy(), SUIT_ARIZEUS, "先确认选中的确实是阿利宙斯")
	# ⚠️ lambda 对局部变量是**值捕获**（GDScript 的规矩）：里面写 `got = [...]`
	# 改的是**副本**，外面看还是空的（实测就是这一条把断言打红的）。
	# 值的捕获里那个 Array 仍是同一个引用 ⇒ 必须**原地改**（`append`）才有用。
	var got: Array = []
	m.start_match.connect(func(suit: int, level: int, map_id: int, mode: int, enemy: int) -> void:
		got.append([suit, level, map_id, mode, enemy]))
	m.set("stage", MainMenu.Stage.MAP)
	m.call("_launch")
	t.eq(got.size(), 1, "出击信号带着参数发出了")
	if not got.is_empty():
		var args: Array = got[0]
		t.eq(args.size(), 5, "五个参数一个不少")
		if args.size() == 5:
			t.eq(args[3], Game.MatchMode.SQUAD, "模式是编队战")
			t.eq(args[4], SUIT_ARIZEUS,
				"编队战下第 5 个参数 == 菜单选的那台敌方 ACE（这一条以前恒为 −1）")
	t.eq(Game.active_side, BattleFormation.Side.MAFTY,
		"顺带：玩家阵营照旧落进 `Game.active_side`（这一条原本就有，别被改动带坏）")


# =============================================================== ⑤ 端到端
static func _spawn(t: T, host: Node) -> void:
	var tree := host.get_tree()
	Game.reset()
	Game.active_side = BattleFormation.Side.MAFTY
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await tree.process_frame
	main.call("_on_start_match", SUIT_XI, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, SUIT_ARIZEUS)
	await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame

	var foes: Array = []
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if not u.has_method("is_alive") or not u.is_alive():
			continue
		if int(u.get("team")) == 1:
			foes.append(u)
	# ⚠️ `lineup()` 里「哪个槽是 ACE」没有对外暴露 ⇒ 这里按**机体型号数**判，
	# 不靠「找 is_ace 那个槽」—— 型号数本身就是玩家看得见的那件事。
	t.eq(foes.size(), BattleFormation.unit_count_per_side(),
		"敌方 7 台（点名不改变编制规模）")
	t.eq(_n_suit(foes, SUIT_ARIZEUS), 1, "敌方那台 ACE 就是玩家点的阿利宙斯")
	t.eq(_n_suit(foes, SUIT_PENELOPE), 0, "佩涅罗佩一台都没来（旧行为才会有一台）")
	t.eq(_n_suit(foes, SUIT_GUSTAV), 6, "六台量产机照旧是古斯塔夫00（编制没被动）")

	main.free()
	await tree.process_frame
	Game.reset()
	await tree.process_frame


# ==================================================================== 小工具
## 名单里那台 ACE 的机体 id（`is_ace` 那个槽；每边恒一台）。
static func _ace_of(units: Array) -> int:
	for u in units:
		if u.is_ace:
			return u.suit
	return -1


## 名单里有几台的机体**不属于**这个阵营（0 = 干净）。
static func _foreign_count(units: Array, side: int) -> int:
	var k := 0
	for u in units:
		if not BattleFormation.belongs_to(side, u.suit):
			k += 1
	return k


static func _n_suit(units: Array, suit: int) -> int:
	var k := 0
	for u in units:
		if u.profile.id == suit:
			k += 1
	return k
