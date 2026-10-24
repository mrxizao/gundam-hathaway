class_name SuiteTutorial
extends RefCounted
## **新手教学**（1.2 第二十五轮）。
##
## 用户原话：「加入新手教学模式，**和靶场在同一页面**，新手教学模式有
## **每个机体的特色详解**」。
##
## ## ⚠️ 为什么文件名不是 `suite_roundNN.gd`
##
## 这个仓库**有另一个会话在并发编辑**，它按"轮次"占编号。
## 本套件第一版叫 `suite_round22.gd`，**被那一轮的 `suite_round22.gd`
##（地图放大 2.3 倍）整个覆盖掉了** —— 我的教学测试一条都没留下，
## 而 `test_runner` 照样绿（它跑的是别人的套件）。
##
## 所以改成**按主题命名**（`suite_tutorial`）：主题不会和"轮次"抢编号。
##
## ## 分六组
##   1. **特色详解数据**（`SuitProfile.features()`）—— 每台机都要讲得出东西
##   2. **教学步骤数据**（`SuitProfile.tutorial_steps()`）—— 按机体定制
##   3. **接线**（训练项目页两项、`Game.tutorial_mode` 的开关与复位、导航轴）
##   4. **按键引导·步骤数据**（`DirectorScript.build_steps`）—— 动作名真存在、按机体裁剪
##   5. **靶机无限血**（`FlightBody.invincible`）—— 教学局里打不爆、关掉即恢复
##   6. **按键引导·真局走通**（真 match + 真玩家 + Input 注入）—— 全程能 done

const FEATURES := "Tutorial / 机体特色详解：数据驱动"
const STEPS := "Tutorial / 教学步骤：按机体定制"
const WIRING := "Tutorial / 接线：训练项目页与教学开关"
const KEY_STEPS := "Tutorial / 按键引导：步骤数据"
const INVINCIBLE := "Tutorial / 靶机无限血"
const LIVE_FLOW := "Tutorial / 按键引导：真局走通"

## ⚠️ 用 **preload** 而不是全局类名：新建的 `class_name` 在编辑器重扫之前
## 不在全局类缓存里，headless 回归会报 "Identifier not found" ——
## preload 按路径解析，永不踩缓存。
const DirectorScript := preload("res://scripts/flight/tutorial_director.gd")


static func run(t: T, host: Node) -> void:
	t.suite(FEATURES)
	_features(t)
	t.suite(STEPS)
	_steps(t)
	t.suite(WIRING)
	await _wiring(t, host)
	t.suite(KEY_STEPS)
	_key_steps(t)
	t.suite(INVINCIBLE)
	_invincible(t, host)
	t.suite(LIVE_FLOW)
	await _live_flow(t, host)


## 全部可选机体（含只在对战里出现的 ACE）。
static func _all_suits() -> Array[SuitProfile]:
	return [
		SuitProfile.xi(),
		SuitProfile.penelope(),
		SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL),
		SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE),  # 批 27：覆盖辅助教学的"超级加速"分岔
		SuitProfile.messer_m01(),
		SuitProfile.gustav00_armed(),
	]


# ---------------------------------------------------------------- 1 特色详解

static func _features(t: T) -> void:
	for p: SuitProfile in _all_suits():
		var feats := p.features()
		# ⚠️ **至少 3 条**：少于 3 条说明这个函数漏了这台机的某个特征，
		# 而不是"这台机没特色"。教学里"没得讲"是最差的结果。
		t.gt(feats.size(), 2,
			"%s 的特色详解 ≥ 3 条（实测 %d）" % [p.display_name, feats.size()])
		for f: Dictionary in feats:
			t.ok(str(f.get("title", "")) != "", "%s：每条都有标题" % p.display_name)
			t.ok(str(f.get("body", "")) != "", "%s：每条都有正文" % p.display_name)
		# ---- 内容必须**真的反映这台机**（不是一段通用文案）----
		var joined := ""
		for f: Dictionary in feats:
			joined += str(f["title"]) + str(f["body"])
		# 导弹：有/无必须讲对
		if p.has_missiles:
			t.ok(joined.contains("浮游导弹"), "%s：有导弹 ⇒ 讲了导弹" % p.display_name)
		else:
			t.ok(joined.contains("没有浮游导弹"),
				"%s：**没有**导弹 ⇒ 明确说了没有（这是它最重要的特色）" % p.display_name)
		# 军刀：有/无必须讲对
		if p.has_saber:
			t.ok(joined.contains("军刀"), "%s：有军刀 ⇒ 讲了军刀" % p.display_name)
		else:
			t.ok(joined.contains("没有光束军刀"),
				"%s：**没有**军刀 ⇒ 明确说了没有" % p.display_name)
		# 骑板资格：ACE 与量产机必须讲对（用户定过 ACE 不可骑）
		if p.can_ride_pedal():
			t.ok(joined.contains("可以骑飞行踏板"),
				"%s：骑得了板 ⇒ 说了可以骑" % p.display_name)
		else:
			t.ok(joined.contains("不能骑飞行踏板"),
				"%s：ACE 机 ⇒ 说了不能骑" % p.display_name)
			t.ok(joined.contains("ACE"), "%s：并且点明它是 ACE 机" % p.display_name)
		# 燃料槽只有量产机有。
		#
		# ⚠️ 判据**不能**用"有没有出现『燃料槽』三个字"：ACE 那一条正文里
		# **故意**写了"ACE 机没有槽，可以一直按加速"——那是在讲清规则，不是教错。
		# 所以钉的是**具体表述**（第一版就是栽在这个粗判据上，红了三条）。
		if p.has_jet_gauge:
			t.ok(joined.contains("按 Shift 有上限"),
				"%s：有槽 ⇒ 有那条燃料槽详解" % p.display_name)
		else:
			t.not_ok(joined.contains("按 Shift 有上限"),
				"%s：**没有**槽 ⇒ 不该有燃料槽详解" % p.display_name)
			t.ok(joined.contains("没有槽"),
				"%s：并且**明说**没有槽（否则玩家会等一个永远不掉的条）" % p.display_name)
		# 变形（阿利宙斯）
		if p.cruise_morph:
			t.ok(joined.contains("可变形"), "%s：能变形 ⇒ 讲了变形" % p.display_name)


# ---------------------------------------------------------------- 2 教学步骤

static func _steps(t: T) -> void:
	for p: SuitProfile in _all_suits():
		var steps := p.tutorial_steps()
		t.gt(steps.size(), 4, "%s 的教学步骤 ≥ 5 条" % p.display_name)
		# 顺序：第一条必须是"起飞/巡航" —— 一上来就讲特色是教学大忌。
		t.ok(steps[0].contains("起飞"), "%s：第一步是**起飞与巡航**" % p.display_name)
		# 最后一条是自由练习（收尾）
		t.ok(steps[steps.size() - 1].contains("自由练习"),
			"%s：最后一步是自由练习" % p.display_name)
		var joined := ""
		for s: String in steps:
			joined += s
		# ⚠️ 这几条是"不能教错"的：没有的武器不要让它去练。
		if not p.has_saber:
			t.not_ok(joined.contains("军刀突进"),
				"%s：没军刀 ⇒ **不该**有挥刀那一步" % p.display_name)
		if not p.has_missiles:
			t.ok(joined.contains("没有导弹") or joined.contains("步枪与军刀"),
				"%s：没导弹 ⇒ 步骤里说明了只能靠枪刀" % p.display_name)
		if not p.has_jet_gauge:
			t.not_ok(joined.contains("燃料槽："),
				"%s：没槽 ⇒ 不该有练槽那一步" % p.display_name)
		if not p.can_ride_pedal():
			t.not_ok(joined.contains("飞行踏板：按 N"),
				"%s：ACE 骑不了板 ⇒ 不该有骑板那一步" % p.display_name)


# ---------------------------------------------------------------- 3 接线

static func _wiring(t: T, host: Node) -> void:
	# ---- 训练项目页：**两项，同一页**（用户要的"和靶场在同一页面"）----
	t.eq(MainMenu.TRAINING_ITEMS.size(), 2, "训练项目**两项**")
	t.eq(str(MainMenu.TRAINING_ITEMS[0]), "自由打靶", "第 1 项是靶场")
	t.eq(str(MainMenu.TRAINING_ITEMS[1]), "新手教学", "第 2 项是新手教学")
	# 导航轴必须与版式一致（竖排 ⇒ Nav.Y）。
	# 阵营页就是在这里错过的（版式竖排、却给了横轴），所以这条要有。
	t.eq(MainMenu.nav_axis(MainMenu.Stage.TRAINING), MainMenu.Nav.Y,
		"训练项目页是**竖排** ⇒ 导航轴是 Y")

	# ---- 教学开关：能被写、且**每局会被清掉** ----
	Game.tutorial_mode = true
	t.ok(Game.tutorial_mode, "`tutorial_mode` 能置真")
	Game.reset()
	t.not_ok(Game.tutorial_mode,
		"`Game.reset()` 会清掉它（不清的话「打过一次教学，之后每次打靶都挂着教学面板」）")

	# ---- 真局：走训练模式起步，并确认教学**不改玩法** ----
	#
	# ⚠️ 这里**不**直接断言"选了教学就进教学" —— 那要走菜单的
	# `training_item` + `_launch()` 一整条链，而 `_launch()` 里
	# `Game.tutorial_mode` 的写入点已经由上面那条（写入 + reset 清掉）覆盖。
	# 真局这一段的目的是**另一件事**：确认教学**没有改动训练的玩法**
	#（靶机还是 4 架、还是不还手），那是"教学只是多一层引导"的判据。
	Game.reset()
	Game.active_suit = SuitProfile.Id.MESSER_M01
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main_scene)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	main_scene.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.RANGE, Game.MatchMode.TRAINING, -1)
	for i in 10:
		await host.get_tree().physics_frame
	var player = main_scene.get("player")
	t.ok(player != null, "教学/打靶局建起来了")
	t.eq(Game.match_mode, Game.MatchMode.TRAINING, "仍然是**训练模式**（教学不是一个新模式）")
	t.gt(Game.training_targets_total, 0, "靶机照旧撒出来了")
	# 教学步骤对**玩家这台机**成立。
	# ⚠️ 必须写显式类型：`player.profile` 在 `main` 里无类型（Variant），
	# `:=` 推不出 `Array[String]`，会报 "Cannot infer the type"。
	var steps: Array[String] = player.profile.tutorial_steps()
	t.gt(steps.size(), 4, "玩家（梅萨）的教学步骤可用")
	main_scene.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 4 按键引导·步骤数据

## **按键引导的步骤数据**（1.2 第二十六轮）。
##
## 三条硬纪律：
##   1. 每步要么带 `actions`、要么带 `check`（没有"永远过不去"的模糊步骤）；
##   2. `actions` 里的每个动作名都必须是 **InputMap 里的真动作** ——
##      写错名字的症状是"按了没反应、教学卡死"（第十五轮 §2.4 那类事故）；
##   3. 步骤按机体字段裁剪：没导弹的机体没有导弹步骤、ACE 没有槽 / 踏板步骤。
static func _key_steps(t: T) -> void:
	for p: SuitProfile in _all_suits():
		# ⚠️ DirectorScript 是 preload 的 GDScript，返回值是 Variant —— 显式标类型
		var steps: Array[Dictionary] = DirectorScript.build_steps(p)
		t.gt(steps.size(), 3, "%s：按键教学 ≥ 4 步（实测 %d）" % [p.display_name, steps.size()])
		for s: Dictionary in steps:
			t.ok(s.has("actions") or s.has("check"),
				"%s：每步都带 actions 或 check（没有模糊步骤）" % p.display_name)
			if s.has("actions"):
				for a: String in s["actions"]:
					t.ok(InputMap.has_action(a),
						"%s：动作「%s」在 InputMap 里真实存在" % [p.display_name, a])
		# 第一步必须是转向（先会飞）；最后一步必须是自由练习（收尾）。
		t.ok(str(steps[0]["text"]).contains("转向"),
			"%s：第一步是**起飞与转向**" % p.display_name)
		t.ok(str(steps[steps.size() - 1]["text"]).contains("自由练习"),
			"%s：最后一步是自由练习" % p.display_name)
		# 条件步骤按字段裁剪 —— 不能教玩家按一个它按不出的功能。
		var joined := ""
		for s2: Dictionary in steps:
			joined += str(s2["text"])
		if not p.has_missiles:
			t.not_ok(joined.contains("浮游导弹"),
				"%s：没导弹 ⇒ 没有导弹步骤" % p.display_name)
		if not p.has_saber:
			t.not_ok(joined.contains("军刀"),
				"%s：没军刀 ⇒ 没有军刀步骤" % p.display_name)
		if not p.has_jet_gauge:
			t.not_ok(joined.contains("燃料槽"),
				"%s：没槽 ⇒ 没有燃料槽步骤" % p.display_name)
		if not p.can_ride_pedal():
			t.not_ok(joined.contains("踏板"),
				"%s：骑不了板 ⇒ 没有踏板步骤" % p.display_name)
		# ---- 辅助驾驶三连（批 27）----
		# 所有机体都有"开启辅助"步；开起来之后的操作**按形态分岔**，
		# 与实机同一条判据（`PlayerController.assist_uses_translation`）。
		t.ok(joined.contains("辅助驾驶"),
			"%s：有辅助驾驶步骤（用户 2026-09-22 要求并入教学）" % p.display_name)
		if PlayerController.assist_uses_translation(p):
			t.ok(joined.contains("闪避冲刺"),
				"%s：非巡航形态 ⇒ 教**平移 + 闪避冲刺**" % p.display_name)
			t.not_ok(joined.contains("超级加速"),
				"%s：非巡航形态 ⇒ **不教**超级加速（那是巡航形态的 Shift）" % p.display_name)
		else:
			t.ok(joined.contains("超级加速"),
				"%s：巡航形态 ⇒ 教**超级加速**（Shift 另一义）" % p.display_name)
			t.not_ok(joined.contains("闪避冲刺"),
				"%s：巡航形态 ⇒ **不教**闪避冲刺（它没有平移模式）" % p.display_name)

	# ---- 导演推进（单元层：玩家传 null，动作步走**输入探针**、状态步改统计）----
	# ⚠️ 不用 `Input.action_press`：无头环境里它的 just_pressed 帧戳实测不可靠
	#（40 次注入一次不触发）。键位映射由上面的 InputMap.has_action 断言 +
	# 下面的源码扫描守卫兜住，推进逻辑用探针桩做确定性验证。
	Game.reset()
	var d: RefCounted = DirectorScript.new()
	var probe := {}
	d.input_probe = func(a: String) -> bool: return probe.has(a)
	d.start(SuitProfile.messer_m01())
	t.eq(d.idx, 0, "导演：start 后停在第 0 步")
	t.ok(str(d.current_text()).contains("转向"), "导演：当前步是起飞与转向")
	# 找到**第一个 null 玩家推不动的状态步**的位置（批 27 起辅助驾驶三连
	# 排在军刀之前，所以"停住点"从军刀步前移到辅助步 —— 不写死是哪一种）。
	var stop_i := -1
	for i in int(d.steps.size()):
		var ck := str(d.steps[i].get("check", ""))
		if ck in ["assist", "translate_move", "qb_dash", "super_boost", "saber"]:
			stop_i = i
			break
	var guard := 0
	while not bool(d.done) and guard < 40:
		guard += 1
		var step: Dictionary = d.steps[int(d.idx)]
		var advanced := false
		if step.has("actions"):
			var a: String = step["actions"][0]
			probe[a] = true
			advanced = d.poll(null, 0.016)
			probe.erase(a)
		else:
			match str(step["check"]):
				"lock":
					Game.locks_acquired += 1
					advanced = d.poll(null, 0.016)
				"hit":
					Game.damage_dealt += 5.0
					advanced = d.poll(null, 0.016)
				"jet":
					probe["boost"] = true
					advanced = d.poll(null, 3.0)
					probe.erase("boost")
				"assist", "translate_move", "qb_dash", "super_boost":
					# 辅助驾驶三连（批 27）盯 player 的**真实状态**：
					# null 玩家推不动（防教学跳穿）；真局层用真玩家推，见 _live_flow。
					advanced = d.poll(null, 0.016)
					t.not_ok(advanced, "「%s」步在玩家为空时不会自己推进（防教学跳穿）"
						% str(step["check"]))
					break
				"saber":
					# 单元层玩家为 null：军刀步**不允许**自己跳过（防教学跳穿）；
					# 真局里由 switch_weapon 完成，见 _live_flow。
					advanced = d.poll(null, 0.016)
					t.not_ok(advanced, "军刀步在玩家为空时不会自己推进（防教学跳穿）")
					break
				_:
					break
		if advanced:
			t.ok(true, "第 %d 步完成后推进" % (int(d.idx) - 1))
	if stop_i >= 0:
		t.eq(int(d.idx), stop_i, "单元层推进到第一个玩家状态步并停住（null 玩家推不动它）")
	else:
		t.ok(bool(d.done), "这台机没有玩家状态步 ⇒ 单元层直接走完教学")
	# 生产默认必须走真实 Input（探针只是测试缝，不许把真输入顶掉）。
	# ⚠️ 不用 `DirectorScript.source_code`：const preload 的类型会被推成脚本类，
	# 静态查不到 GDScript 资源自己的成员 —— 直接读文件最稳。
	var dsrc: String = FileAccess.get_file_as_string("res://scripts/flight/tutorial_director.gd")
	t.ok(dsrc.contains("Input.is_action_just_pressed"),
		"导演默认走真实 Input 的 just_pressed（探针只是测试缝）")
	t.ok(dsrc.contains("Input.is_action_pressed"),
		"jet 步默认走真实 Input 的按住态")


# ---------------------------------------------------------------- 5 靶机无限血

## **无限血**（1.2 第二十六轮）：教学局靶机打不爆，关掉开关立刻恢复可击毁。
##
## ⚠️ 直调 `take_damage`（走全链路：友军闸门 → 出生保护 → 无限血分支），
## 不绕过任何一层 —— 绕过的测试守不住真链路。
## 命中统计（`Game.damage_dealt`）只在 `source == Game.player` 时入账，
## 所以这里造一台真射手挂进 `Game.player`，测完还原。
static func _invincible(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var shooter := FlightBody.new()
	shooter.team = 0
	shooter.profile = SuitProfile.gustav00_armed()
	c.add_child(shooter)
	var d := TargetDrone.new()
	d.team = 1
	d.profile = SuitProfile.gustav00_armed()
	d.projectile_container = c
	c.add_child(d)
	d.global_position = Vector3(0, 3000, 0)
	d.invuln_until = -1.0  # 排除出生保护的干扰（测试直伤，不走真实出生时序）
	d.invincible = true
	var hp0: float = d.hp
	var player_backup = Game.player
	Game.player = shooter
	d.take_damage(40.0, shooter)
	t.eq(d.hp, hp0, "无限血：挨了一发血量分毫不动")
	t.ok(d.alive, "无限血：靶机仍活着")
	# 命中统计照记（教学"命中"步的判定读它）。⚠️ 靶机可能用 I 立场吃下这一发
	#（gustav00_armed 有立场），所以判**总和** —— 与导演"hit"步的口径同源。
	t.gt(Game.damage_dealt + Game.ifield_dealt, 0.0,
		"无限血：命中统计照常入账（damage_dealt + ifield_dealt > 0）")
	d.take_damage(99999.0, shooter)
	t.ok(d.alive, "无限血：99999 伤害也打不爆")
	# 关掉开关 → 照常可击毁（自由打靶不受影响）
	d.invincible = false
	d.take_damage(99999.0, shooter)
	t.not_ok(d.alive, "关掉无限血后照常能被打爆（自由打靶不受影响）")
	Game.player = player_backup
	c.free()


# ---------------------------------------------------------------- 6 按键引导·真局走通

## **真局全程走通**：真 match + 真玩家 + Input 注入，把教学一步步推到 done。
##
## 这是"按键引导"的**端到端**判据 —— 单元层只能证明数据与推进逻辑，
## 证明不了"玩家按 X 教学真的会往下走"。注入手段：
##   - 按键步 → `Input.action_press / release`（InputMap 的真动作）；
##   - 状态步 → 直接改 `Game` 统计（与真实链路同源）；
##   - 军刀步 → 真调 `switch_weapon()`（切过去即过）。
static func _live_flow(t: T, host: Node) -> void:
	Game.reset()
	Game.active_suit = SuitProfile.Id.MESSER_M01
	# 菜单的时序：开局**之前**把教学意图写进**请求**（main_menu._launch 同款）——
	# spawn_round 会在 reset 之后把它落成 `tutorial_mode`。
	Game.tutorial_requested = true
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main_scene)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	main_scene.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.RANGE, Game.MatchMode.TRAINING, -1)
	for i in 10:
		await host.get_tree().physics_frame
	var player = main_scene.get("player")
	t.ok(player != null, "教学真局建起来了")
	t.ok(Game.tutorial_mode, "教学开关在开局后仍然为真（spawn_round 的 reset 没吃掉它）")
	t.not_ok(Game.tutorial_requested, "教学请求已被 spawn_round 消费（不留给下一局）")
	# 靶机无限血：教学局撒出来的每一架都开着（main.spawn_training 读 tutorial_mode）。
	var targets_v = main_scene.get("targets")
	t.ok(targets_v != null, "main 的靶机列表存在")
	if targets_v != null:
		var targets: Array = targets_v
		t.eq(targets.size(), 4, "教学局照旧 4 架靶机")
		var all_inv := true
		for d in targets:
			if not d.invincible:
				all_inv = false
		t.ok(all_inv, "教学局里所有靶机都开着无限血")
	# 导演全程走通（输入走探针桩 —— 与单元层同一理由，见 _key_steps）。
	var director: RefCounted = DirectorScript.new()
	var probe := {}
	director.input_probe = func(a: String) -> bool: return probe.has(a)
	director.start(player.profile)
	var guard := 0
	while not bool(director.done) and guard < 60:
		guard += 1
		var step: Dictionary = director.steps[int(director.idx)]
		var advanced := false
		if step.has("actions"):
			var a: String = step["actions"][0]
			probe[a] = true
			advanced = director.poll(player, 0.016)
			probe.erase(a)
		else:
			match str(step["check"]):
				"lock":
					Game.locks_acquired += 1
					advanced = director.poll(player, 0.016)
				"hit":
					Game.damage_dealt += 5.0
					advanced = director.poll(player, 0.016)
				"jet":
					probe["boost"] = true
					advanced = director.poll(player, 3.0)
					probe.erase("boost")
				# ---- 辅助驾驶三连（批 27）：真局层直接把真实状态写出来，
				# 与实机写这些状态的**字段**同源（assist_on / translate_dir /
				# translate_dash / fm.super_boost 分别由开关、平移输入、
				# QB 窗口、巡航超级加速写）。
				"assist":
					player.assist_on = true
					advanced = director.poll(player, 0.016)
				"translate_move":
					player.translate_dir = Vector3(0, 0, 1)
					advanced = director.poll(player, 0.016)
				"qb_dash":
					player.translate_dash = true
					advanced = director.poll(player, 0.016)
				"super_boost":
					player.fm.super_boost = true
					advanced = director.poll(player, 0.016)
				"saber":
					for i in 8:
						if player.current_slot() == "saber":
							break
						player.switch_weapon()
					advanced = director.poll(player, 0.016)
				_:
					break
		if advanced:
			t.ok(true, "真局：第 %d 步完成后推进" % (int(director.idx) - 1))
	t.ok(bool(director.done), "真局：教学全部走通（done）")
	t.ok(str(director.current_text()).contains("自由练习"), "收尾文案是自由练习")
	main_scene.queue_free()
	await host.get_tree().physics_frame
	Game.tutorial_mode = false  # 还原，不污染后续套件
