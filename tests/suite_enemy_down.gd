class_name SuiteEnemyDown
extends RefCounted
## ★63-9 · D4「敌方机体坠毁提醒」。
##
## 判据分三段：
##   (a) 源码接线 —— 提醒只有一个真源、两条击毁回调都接、三个接线点都绑上机体自己、
##       门用 `Game.phase`（不是 `main.phase`）；
##   (b) 小队战（`_on_enemy_destroyed` 那条路，对战 / 编队 / 联机共用）：
##       非终结性击毁弹一条**带机名**的 toast；终结那一台**不再**加一条；
##   (c) 挑战（`_on_challenge_enemy_destroyed` 那条路，剧情 / 挑战共用）：
##       同一套结论都成立（含"清空一波去刷下一波"的中间态），顺带钉住 toast 的 5 条上限。
##
## ⚠️ 每条运行时断言之前都**先清空** `hud._notices`。
## 那个数组有 **5 条上限**（`push_notice()` 里 `pop_front`）—— 不清空的话，
## 「终结那一台没加新条」会被上限**吃掉**（加第 6 条时第 1 条被挤掉、长度照旧是 5），
## 于是变成一条**永远绿**的假断言。这是本套件最容易写错的一处。
##
## ⚠️ 文案断言一律**整串相等**，不用 `contains`：
## `"敌机坠毁 —— 古斯塔夫00"` 与 `"敌机坠毁 —— 古斯塔夫000"` 互为前缀，
## 本工程已经栽过一次同款（`"长按 Back"` 命中 `"长按 B"`）。

const MAIN_PATH := "res://scripts/main.gd"
const BODY_PATH := "res://scripts/flight/flight_body.gd"
const SEC_A := "EnemyDown / 源码接线（D4）"
const SEC_B := "EnemyDown / 小队战：坠毁提醒（D4）"
const SEC_C := "EnemyDown / 挑战：坠毁提醒 + toast 上限（D4）"
const PREFIX := "敌机坠毁"


static func run(t: T, host: Node) -> void:
	t.suite(SEC_A)
	_scan_source(t)
	t.suite(SEC_B)
	await _squad(t, host)
	t.suite(SEC_C)
	await _challenge(t, host)


# ================================================================ (a) 源码接线
static func _scan_source(t: T) -> void:
	var msrc := SuiteUiStyle._code(MAIN_PATH)
	var bsrc := SuiteUiStyle._code(BODY_PATH)

	t.eq(msrc.count("func _notify_enemy_down(unit: Node3D) -> void:"), 1,
		"提醒只有一个真源")
	t.eq(msrc.count("\t_notify_enemy_down(unit)"), 3,
		"三条击毁回调都调它（对战/编队 + 挑战/剧情 + ★63-24 无限强化演习）")
	t.eq(msrc.count(".destroyed.connect(_on_enemy_destroyed.bind("), 2,
		"对战与编队那两个 `destroyed` 接线点都把机体自己绑进回调")
	t.eq(msrc.count(".destroyed.connect(_on_challenge_enemy_destroyed.bind("), 1,
		"挑战那个接线点同样绑了机体")
	# ★63-24：演习那条是**第四个**接线点（每波现撒 ⇒ 每架各连一次）。
	# 同一个坑：`destroyed(killer)` 收不到自己 ⇒ 不 `bind(ai)` 就永远不知道掉的是哪台。
	t.eq(msrc.count(".destroyed.connect(_on_endless_enemy_destroyed.bind("), 1,
		"★63-24 演习那个接线点同样绑了机体")
	# 信号签名是 `destroyed(killer)` —— **收不到自己**。
	# ⇒ 不 `bind()` 就永远拿不到"掉的是哪台"，只能弹一句没有名字的提示。
	t.ok(msrc.contains("enemy.destroyed.connect(_on_enemy_destroyed.bind(enemy))"),
		"1v1 的对手：绑的是 enemy")
	t.ok(msrc.contains("ai.destroyed.connect(_on_enemy_destroyed.bind(ai))"),
		"编队 / 联机：绑的是当场撒出来的那台 ai")
	t.ok(msrc.contains("ai.destroyed.connect(_on_challenge_enemy_destroyed.bind(ai))"),
		"挑战 / 剧情：同上")

	var body := _body(msrc, "func _notify_enemy_down(")
	t.ok(body.contains("if Game.phase != Game.Phase.FIGHT:"),
		"门就是这一行：不是 FIGHT 就什么都不弹")
	t.ok(body.contains("player.notice.emit("),
		"提醒走玩家的 notice 通道（中央那摞 toast）")
	t.not_ok(body.contains("Phase.RESULT"),
		"门不许改成 main 的 RESULT —— 小队战实测：击坠 1 架时 main.phase 已经是 RESULT，"
		+ "而 `Game.phase` 仍是 FIGHT、屏幕上根本没有结算页")
	t.ok(bsrc.contains("Game.log_event(\"敌机坠毁 —— %s\" % display_name)"),
		"结算页左栏那一行带上了机名（P12：终结性击毁的提示落在结算页）")
	t.eq(msrc.count("敌机被击坠") + bsrc.count("敌机被击坠"), 0,
		"旧文案「敌机被击坠」一处不剩")


# ============================================================ (b) 小队战那条路
static func _squad(t: T, host: Node) -> void:
	var tree := host.get_tree()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await tree.process_frame
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	await tree.process_frame
	await tree.physics_frame
	main.call("_start_fight")
	await tree.physics_frame

	var p = main.get("player")
	var hud = main.get("hud")
	var foes: Array = Game.live_hostiles_of(p).duplicate()
	t.gt(foes.size(), 1, "小队战场上多于一台敌机（否则谈不上「非终结性击毁」）")

	# ---- ① 非终结性：场上还剩好几台 ----
	_clear(hud)
	var victim = foes[0]
	var vn: String = victim.display_name
	victim.destroy(p)
	t.eq(Game.phase, Game.Phase.FIGHT, "击坠 1 台之后仍是 FIGHT（这一下不是终结）")
	t.eq(_text(hud), PREFIX + " —— " + vn,
		"中央提示正好一条，且报的是被击落那台的名字")

	# ---- ② 终结性：清到只剩一台，再打掉它 ----
	# ⚠️ `duplicate()` 不可省：`Game.live_hostiles_of()` 返回的是 `Game` 内部那个
	# **每物理帧重建的缓存数组本身**（Array 是按引用传的）。直接拿它当循环上界，
	# 每 `destroy()` 一台数组就**原地缩短**一格 ⇒ 循环越界、协程当场断掉。
	var rest: Array = Game.live_hostiles_of(p).duplicate()
	for i in rest.size() - 1:
		rest[i].destroy(p)
		await tree.physics_frame
	t.eq(Game.live_hostiles_of(p).size(), 1, "场上只剩最后一台")
	_clear(hud)
	t.eq(Game.phase, Game.Phase.FIGHT, "还剩一台 ⇒ 仍是 FIGHT")
	rest[rest.size() - 1].destroy(p)
	t.eq(Game.phase, Game.Phase.WIN,
		"打掉最后一台 ⇒ `Game.phase` 当场翻 WIN（结算页就在那一帧上来）")
	t.eq(_text(hud), "",
		"终结那一台不再往中央提示里加一条（用户要的「不要和游戏结算冲突」）")

	main.free()
	await tree.process_frame
	Game.reset()
	await tree.process_frame


# ======================================================== (c) 挑战 / 剧情那条路
static func _challenge(t: T, host: Node) -> void:
	var tree := host.get_tree()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await tree.process_frame
	Game.active_challenge_id = ChallengeScript.xi_vs_arizeus().id
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		-1, Game.MatchMode.CHALLENGE)
	await tree.process_frame
	await tree.physics_frame
	main.call("_start_fight")
	await tree.physics_frame

	var p = main.get("player")
	var hud = main.get("hud")
	# ⚠️ 同样必须 `duplicate()`：清空第 1 波最后一台的同一帧里，
	# `_on_challenge_enemy_destroyed()` 会调 `_spawn_wave(1)`，而它第一件事就是
	# `wave_units.clear()` —— 直接拿这个数组当循环源，会在迭代中途被**掏空换人**。
	var wave: Array = (main.get("wave_units") as Array).duplicate()
	t.eq(wave.size(), 3, "第 1 波三台（本场的真源，不是硬写的数）")

	# ---- ① 非终结性（同一波里还有两台）----
	_clear(hud)
	var vn: String = wave[0].display_name
	wave[0].destroy(p)
	t.eq(Game.phase, Game.Phase.FIGHT, "第 1 波掉 1 台仍是 FIGHT")
	t.eq(_text(hud), PREFIX + " —— " + vn, "提示报的是被击落那台的名字")

	# ---- ② 清空整波：下面还有一波 ⇒ 仍是非终结性，且刷波提醒不能被挤掉 ----
	_clear(hud)
	for u in wave:
		if is_instance_valid(u) and u.is_alive():
			u.destroy(p)
			await tree.physics_frame
	t.eq(Game.phase, Game.Phase.FIGHT, "清空第 1 波之后仍是 FIGHT（下面还有一波）")
	t.eq(Game.challenge_wave, 1, "自动进入第 2 波")
	t.ok(_text(hud).contains("下一波"), "刷波提醒照旧（D4 的改动没把它挤掉）")
	t.eq(_count(hud), 2, "清空那一波的两台各留下一条坠毁提醒")

	# ---- ③ 终结性：最后一波的最后一台 ----
	var second: Array = (main.get("wave_units") as Array).duplicate()
	t.eq(second.size(), 1, "第 2 波一台")
	_clear(hud)
	second[0].destroy(p)
	t.eq(Game.phase, Game.Phase.WIN, "打掉最后一台 ⇒ WIN")
	t.eq(_text(hud), "", "终结性击毁不弹 toast（这一条与小队战那一半是同一个门）")

	# ---- ④ toast 上限：既有行为，钉住别被这次改动带坏 ----
	_clear(hud)
	for i in 7:
		hud.push_notice("上限 %d" % i, 30.0)
	t.eq((hud.get("_notices") as Array).size(), 5, "toast 上限仍是 5 条")

	main.free()
	await tree.process_frame
	Game.reset()
	await tree.process_frame


# ==================================================================== 小工具
## 从源码里摘一个函数体（到下一条 `func` 为止）。
static func _body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var lines := src.substr(i).split("\n")
	var out: Array = [str(lines[0])]
	for k in range(1, lines.size()):
		var s := str(lines[k])
		if s.begins_with("func ") or s.begins_with("static func "):
			break
		out.append(s)
	return "\n".join(out)


static func _clear(hud) -> void:
	hud.set("_notices", [])


## 把当前那摞 toast 的**文本**按顺序拼成一个串 —— 整串比对，杜绝前缀命中。
static func _text(hud) -> String:
	var out: Array = []
	for n in hud.get("_notices"):
		out.append(str(n.get("text", "")))
	return "|".join(out)


## 其中"坠毁提醒"有几条。
static func _count(hud) -> int:
	var k := 0
	for n in hud.get("_notices"):
		if str(n.get("text", "")).begins_with(PREFIX):
			k += 1
	return k
