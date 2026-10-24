class_name SuiteEndlessLive
extends RefCounted
## ★63-24 无限强化演习 · **端到端**（真起一局 · 真清波 · 真选卡）。
##
## ## 为什么要有它（R3 交付时留下的那个洞）
##
## R3 的两个新分节把状态机钉得很死，但它们是**两种"没真跑"的判据**：
##   · `INTERMISSION`       —— 喂的是 `EndlessScript` 的**纯函数**（不碰 main）；
##   · `INTERMISSION_WIRING` —— 扫的是 `main.gd` 的**源码字符串**（不执行它）。
##
## ⇒ 从"清完一波"到"面板弹出来"再到"下一波刷出来"这条**真链路**，
##    在 R3 收工那一刻**一次都没有被真正执行过**。它能坏成什么样：
##    · 清空之后 `_begin_endless_round()` 根本没被调 ⇒ **卡在 CLEARING**，游戏不动了；
##    · 面板开了但 `_take_endless_card()` 收不掉轮 ⇒ **永远停在选卡屏**；
##    · 收轮了但没放开 `controls_enabled` ⇒ 玩家能看不能开。
##
## 这三种在真机上都是"**这一局打不下去了**"，而源码扫描一条都抓不到
##（字符串都在，只是没人按那个顺序调）。所以本套件的职责只有一个：
## **把 R3 那条链路在真节点上跑一遍，证明它不会卡死。**
##
## ⚠️ 它**不能**替代真机试玩 —— `--headless` 下 `_draw_*` **根本不执行**，
##    所以"面板画出来什么样"这里一格都测不到（那是 `INTERMISSION_UI` 的几何
##    + 判据图 + 用户真机试玩的活）。这里测的是**状态机**那一条线。
##
## ⚠️ 跑法：`--only=suite_endless_live`
##    （**别用 `--only=suite_endless`** —— 那是子串匹配，会把纯逻辑那套一起拉进来。）

const ENDLESS := preload("res://scripts/data/endless_script.gd")

## 开局自选的 3 张。选它们只因为**对柯西全部可用**（过了准入谓词）：
## 火力（有步枪）/ 装甲（人人可装）/ 机制（多重锁定）。
const PICKS := ["rifle_dmg", "hull", "multi_lock"]


static func run(t: T, host: Node) -> void:
	# ⚠️ 分节条数的基线**不能写 0** —— 全量回归跑到这里时前面已经累计了上万条，
	#    `now - 0` 会把"这一节"的量成一个巨大的数，下限闸门在那儿**恒真**。
	#    先取当前全局计数当基线，闸门才真的在量"这一节"。
	var c := t.passed + t.failed

	t.suite("EndlessLive / 起局：演习真的能开起来（自选 3 张已落地）")
	var main := await _boot(t, host)
	if main == null:
		return
	c = _count(t, "§1 起局", c, 12)
	t.suite("EndlessLive / intensity tiers update surviving enemies without healing")
	_intensity_live(t,main)
	c = _count(t,"time tiers",c,10)

	t.suite("EndlessLive / 清波 → CLEARING → 间歇轮（R3 那条链路的入口）")
	await _clear_to_intermission(t, main, host.get_tree())
	c = _count(t, "§2 清波 → 间歇轮", c, 10)

	t.suite("EndlessLive / 选卡 → 收轮 → 下一波（链路出口）")
	_take(t, main, host.get_tree())
	c = _count(t, "§3 选卡 → 下一波", c, 9)

	t.suite("EndlessLive / 连打 6 波：奖励轮 / 超时自动选 / 不卡死")
	await _march(t, main, host.get_tree())
	c = _count(t, "§4 连打 6 波", c, 10)

	t.suite("EndlessLive / 静默失效门：拿卡之后 FlightBody 的读数真的跟着走")
	_stats(t, main)
	c = _count(t, "§5 读数同步", c, 4)

	main.queue_free()
	await host.get_tree().process_frame


## 记"这一节跑了几条"并显式打出来，同时给它一个**条数下限**。
##
## ⚠️ 下限闸门不是凑数：某一节整节消失时（套件解析失败 / 中途 `return`），
## 汇总仍然是 `0 FAIL` —— 只有这条闸门会红。（轮 49 的坑：某套件从 25 条
## 静默掉到 12 条而汇总全绿。）
static func _count(t: T, tag: String, prev: int, lo: int) -> int:
	var now := t.passed + t.failed
	var n := now - prev
	print("[r63-24] %s：%d 条" % [tag, n])
	t.gt(float(n), float(lo) - 0.5, "%s 至少 %d 条（整节消失会在这里红）" % [tag, lo])
	return now


# ─────────────────────────────────────────────── §1 起局

## 真起一局演习。成功返回 `main`，失败返回 `null`（并已经记了红）。
##
## ⚠️ 走 `_on_start_match()` —— main 里写明它是"**测试与探针的正式入口**"，
## 同步语义（返回时玩家 / 敌机 / 世界全部就位、阶段已到 FIGHT）。
## 菜单那条路是 `_begin_match_loading()`（带读条协程），测试不用它。
static func _boot(t: T, host: Node) -> Node:
	var tree := host.get_tree()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await tree.process_frame

	# ⚠️ 自选卡必须在**起局之前**放进请求通道 —— `spawn_round()` 会把它读走、
	#    施加到 profile 上，然后**清空通道**（那是它的唯一消费点）。
	#
	# ⚠️ 用 `assign()` 而不是 `=`：`Game.endless_pick_request` 是 `Array[String]`，
	#    而 `PICKS` 是无类型字面量数组 —— 直接赋会报
	#    "Invalid assignment ... with value of type 'Array'"（实测踩过）。
	Game.endless_pick_request.assign(PICKS)
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL, -1,
		Game.MatchMode.ENDLESS)
	for i in 6:
		await tree.physics_frame

	var pl: FlightBody = main.get("player")
	if pl == null or not is_instance_valid(pl):
		t.ok(false, "演习起局之后 player 存在（下面所有断言都读它）")
		main.queue_free()
		return null
	t.ok(pl.alive, "起局后玩家是活的")

	# ---- 模式口径 ----
	t.eq(Game.match_mode, Game.MatchMode.ENDLESS, "模式 = ENDLESS")
	t.eq(Game.phase, Game.Phase.FIGHT, "阶段已到 FIGHT（不用等按键）")
	t.eq(Game.active_map.id, MapDef.Id.PACIFIC, "★ 演习**强制**太平洋群岛（§11.3 第 25 条）")
	t.ok(Game.active_challenge == null,
		"★ `active_challenge` 恒为 null（演习没有 Encounter ⇒ 判胜守卫在它身上形同虚设）")

	# ---- 第 1 波 ----
	t.eq(Game.endless_wave, 1, "开局就在第 1 波")
	t.eq(Game.endless_phase, ENDLESS.Phase.WAVE, "第 1 波的状态是 WAVE")
	t.gt(float(Game.endless_wave_total), 0.0, "第 1 波至少撒了 1 架")
	t.eq(Game.endless_wave_remaining, Game.endless_wave_total,
		"剩余数 == 本波总数（开局没打掉任何一架）")

	# ---- 开局那 3 张卡 ----
	t.eq(Game.endless_owned.size(), PICKS.size(), "开局自选 3 张已落地")
	t.eq(Game.endless_owned_tier.size(), Game.endless_owned.size(),
		"★ 品质数组**同长**（成对写的；短了会让 `_owned_cards()` 静默退回 BASIC）")
	for i in PICKS.size():
		t.eq(Game.endless_owned[i], PICKS[i], "第 %d 张就是菜单里自选的那张" % (i + 1))
	t.eq(Game.endless_pick_request.size(), 0, "请求通道已被消费（`spawn_round()` 清空）")

	# 第 0 档 ⇒ 强化 ×1.00
	t.eq(Game.endless_enemy_reinforce, 1.0, "开局在第 0 档 ⇒ 敌机强化 ×1.00")
	return main


# ─────────────────────────────────────────────── §2 清波 → 间歇轮

static func _clear_to_intermission(t: T, main: Node, tree: SceneTree) -> void:
	await _wipe(t, main, tree)
	t.eq(Game.endless_phase, ENDLESS.Phase.CLEARING,
		"★ 本波清空 ⇒ 进 CLEARING（**不再直接刷下一波** —— 这正是 R3 改的那一行）")
	t.gt(float(Game.endless_wave_total), 0.0, "（前置）确实清掉了一波有敌机的")

	# 边界：1.2 s **差一点点**的时候还不能开轮
	_tick(main, ENDLESS.CLEARING_SECS - 0.05)
	t.eq(Game.endless_phase, ENDLESS.Phase.CLEARING,
		"CLEARING 没走完时**不许**开下一轮（这一条钉的是 `>=` 那个边界）")
	# ⚠️ 接下来**只推 `_tick_endless`**（不推 `_tick_endless_round`）——
	#    为的是在"刚开轮、还没走钟"那一瞬做检查。
	#    `_process()` 里两个钟是紧挨着调的，但那样一推完 `left` 就已经少了一格 delta，
	#    「倒计时从满值起」这条断言就永远量不到（它会以一个极小的差恒定变红）。
	main.call("_tick_endless", 0.10)
	t.ok(Game.endless_phase != ENDLESS.Phase.CLEARING, "走完 CLEARING ⇒ 离开 CLEARING（开了一轮）")

	# 第 1 波不是 5 的倍数 ⇒ 普通间歇轮
	t.eq(Game.endless_phase, ENDLESS.Phase.INTERMISSION,
		"第 1 波之后是**普通**间歇轮（奖励轮挂在强敌波之后）")
	t.ok(not ENDLESS.is_ace_wave(1), "（前置）第 1 波确实不是强敌波")

	# 面板的局面
	t.eq(Game.endless_hand.size(), 3, "★ 抽了 3 张手牌")
	# ⚠️ 品质是**随机掷**的（`tier_for(1, rng.randf(), ...)`，权重 30/50/10/10）
	#    ⇒ 判据只能钉"落在四档之内"，**不能**钉某一个具体档 ——
	#    钉具体档的话这套件会**偶发红**（而偶发红比不红更坏：它会让人开始忽略红）。
	t.ok(Game.endless_hand_tier >= UpgradeCard.Tier.BASIC
		and Game.endless_hand_tier <= UpgradeCard.Tier.RADICAL,
		"普通轮的品质落在四档之内（按权重掷，不预设是哪一档）")
	t.eq(Game.endless_hand_want, 1, "普通轮只要选 **1** 张")
	t.eq(Game.endless_hand_got, 0, "还没选，所以 got = 0")
	t.eq(Game.endless_focus, 0, "焦点归零（面板打开时不是上次那个位置）")
	t.eq(Game.endless_intermission_left, ENDLESS.INTERMISSION_BASE,
		"倒计时从满值起（没被开局的假账吃掉）")
	t.eq(Game.endless_operate_idle, ENDLESS.OPERATE_GRACE,
		"★ 开局 `idle` 钉在**宽限值本身**（写 0 会让开局 0.6 s 被判成「正在操作」）")
	t.not_ok(main.get("player").controls_enabled,
		"选卡期间**禁控**（结算/暂停/锁内那条既有约定，不是新开关）")


# ─────────────────────────────────────────────── §3 选卡 → 下一波

static func _take(t: T, main: Node, tree: SceneTree) -> void:
	var pl: FlightBody = main.get("player")
	var owned := Game.endless_owned.size()
	var hp_before := pl.hp
	var max_before := pl.max_hp
	var wave := Game.endless_wave

	main.call("_take_endless_card", 0)

	t.eq(Game.endless_owned.size(), owned + 1, "★ 选中的卡真的进了 `endless_owned`")
	t.eq(Game.endless_owned_tier.size(), Game.endless_owned.size(),
		"★ 品质数组**同步**长（`_take_endless_card()` 里成对 append）")
	# ⚠️ 普通轮只要 1 张 ⇒ **这一张选完就当场收轮**：手牌被 `_finish_endless_round()`
	#    清空、`hand_got` 归零。所以这里**不是**"3 → 2" ——
	#    首版就是照直觉写成 2（那条红是判据写错了，不是代码坏了）。
	t.eq(Game.endless_hand.size(), 0, "手牌清空（选满 `want` ⇒ 当场收轮）")
	t.eq(Game.endless_hand_got, 0, "`hand_got` 随收轮归零（下一轮从 0 起）")

	# ---- 收轮的出口 ----
	t.eq(Game.endless_phase, ENDLESS.Phase.WAVE, "★ 选满 1 张 ⇒ 立刻收轮、回到 WAVE")
	t.eq(Game.endless_wave, wave + 1, "★ 收轮之后刷的是**下一波**（wave + 1）")
	t.ok(pl.controls_enabled, "★ 收轮之后**放开操作**（不放的话玩家能看不能开）")
	t.eq(Game.endless_operate_idle, ENDLESS.OPERATE_GRACE, "宽限值复位")

	# 每拿一张卡都会整批重算 ⇒ `max_hp` 必须跟着 profile 走
	t.eq(pl.max_hp, pl.profile.hull_hp,
		"★ 拿卡后 `max_hp` 与 `profile` 同步（`refresh_profile_stats()` 真的被调了）")
	t.gt(pl.hp, 0.0, "拿卡之后血还是正的（增量补血没把血算成负的）")
	if pl.max_hp > max_before:
		t.gt(pl.hp, hp_before, "上限涨了 ⇒ 当前血也往上补（不是比例保留）")
	else:
		t.eq(pl.max_hp, max_before, "这一张不加耐久 ⇒ 上限不动（对照：不是无脑变大）")
	await tree.process_frame


# ─────────────────────────────────────────────── §4 连打 6 波

## 从当前波一路打到第 7 波（覆盖两次"清波 → 选卡"、一次**强敌波奖励轮**、
## 一次**超时自动选**）。
##
## ⚠️ 用 `while` + `guard` 而不是 `for`：波号由 `_finish_endless_round()` 改，
## 我要的是"一直打到第 7 波"，而不是"循环 6 次"。guard 防的是**卡死** ——
## 万一状态机不往前走，这里会以一条红收场，而不是把测试挂死。
static func _march(t: T, main: Node, tree: SceneTree) -> void:
	var guard := 0
	var saw_bonus := false
	var saw_auto := false
	while Game.endless_wave < 7 and guard < 20:
		guard += 1
		var w := Game.endless_wave
		await _wipe(t, main, tree)
		_tick(main, ENDLESS.CLEARING_SECS + 0.05)
		if Game.endless_phase == ENDLESS.Phase.CLEARING:
			t.ok(false, "第 %d 波清空后卡在 CLEARING（`_begin_endless_round()` 没被调）" % w)
			return
		if not _in_round():
			t.ok(false, "第 %d 波清空后没进间歇轮（phase = %d）" % [w, Game.endless_phase])
			return

		# ---- 强敌波（每 5 波）之后是奖励轮 ----
		if ENDLESS.is_ace_wave(w):
			saw_bonus = true
			t.eq(Game.endless_phase, ENDLESS.Phase.BONUS,
				"★ 第 %d 波（强敌波）之后进的是**奖励轮**" % w)
			t.eq(Game.endless_hand_tier, UpgradeCard.Tier.PERFECT,
				"★ 奖励轮的品质**强制「完美」**（不掷权重）")
			t.ok(Game.endless_hand_want >= 1, "奖励轮至少选 1 张（拿到 %d）" % Game.endless_hand_want)
		else:
			t.eq(Game.endless_phase, ENDLESS.Phase.INTERMISSION,
				"第 %d 波（小波）之后是普通轮" % w)

		# ---- 第 3 波那一轮**不动手**，走超时自动选 ----
		if w == 3:
			saw_auto = true
			_tick(main, ENDLESS.INTERMISSION_BASE + 0.5)
			t.eq(Game.endless_phase, ENDLESS.Phase.WAVE,
				"★ 全程不动 ⇒ 超时**自动选掉焦点那张**、流程照常往前走（不惩罚不阻塞）")
			t.eq(Game.endless_wave, w + 1, "自动选之后也刷了下一波")
			continue

		# ---- 其余轮：把该选的张数选满 ----
		var want := Game.endless_hand_want
		for i in want:
			if _in_round():
				main.call("_take_endless_card", 0)
		t.eq(Game.endless_phase, ENDLESS.Phase.WAVE,
			"第 %d 波那一轮选满 %d 张 ⇒ 收轮" % [w, want])
		t.eq(Game.endless_wave, w + 1, "收轮之后波号 +1")

	t.ok(saw_bonus, "★ 这段连打里**确实经过了一次奖励轮**（不然上面那几条判据没被执行）")
	t.ok(saw_auto, "★ 这段连打里**确实走了一次超时自动选**")
	t.gt(float(Game.endless_owned.size()), float(PICKS.size()),
		"连打 6 波之后手里的卡比开局多（成长那一半真的在走）")
	t.eq(Game.endless_owned_tier.size(), Game.endless_owned.size(),
		"★ 连打之后两个数组**仍然同长**（每张卡都成对写的）")


# ─────────────────────────────────────────────── §5 读数同步

## ★ 静默失效门：`FlightBody._ready()` 把 `profile` 的耐久/武装读数**抄进自己的字段**，
## 之后**再也不看 profile** ⇒ 拿卡时必须有一条"重抄"的路，否则
## **装甲卡加血一个点都不生效**（而伤害 / 间隔那类每次现读 profile 的卡全正常）。
##
## 这里手工把上限抬一档、调一次 `refresh_profile_stats()`，直接验"重抄 + 增量补血"。
## ⚠️ 放在**最后**：它故意改了 profile，会污染后面所有读数。
static func _intensity_live(t: T, main: Node) -> void:
	var clock_before := Game.endless_elapsed
	var reinforce_before := Game.endless_enemy_reinforce
	var members: Array = main.get("wave_units")
	var snapshot: Array = []
	for ai in members:
		snapshot.append([ai,ai.damage_mult,ai.hp,ai.ifield_hp,ai.max_hp,ai.ifield_max])
	Game.endless_elapsed = 299.9
	main.call("_tick_endless",0.2)
	t.eq(FlightHUD.EndlessIntensityHUD.readout(Game.endless_elapsed)["level"],2,"real run clock advances table to LV.02")
	for saved: Array in snapshot:
		var ai = saved[0]
		t.near(ai.damage_mult,saved[1]*1.1,0.00001,"survivor receives first tier immediately")
		t.eq([ai.hp,ai.ifield_hp,ai.max_hp,ai.ifield_max],[saved[2],saved[3],saved[4],saved[5]],"time tier does not heal or increase durability")
	main.call("_tick_endless",1.0)
	for saved: Array in snapshot:
		t.near(saved[0].damage_mult,saved[1]*1.1,0.00001,"same tier does not compound every frame")
	Game.endless_elapsed = 599.9
	main.call("_tick_endless",0.2)
	for saved: Array in snapshot:
		t.near(saved[0].damage_mult,saved[1]*1.21,0.00001,"second time tier compounds to 1.21")
	var newcomer := BanditAI.new()
	newcomer.profile = SuitProfile.xi()
	newcomer.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	main.add_child(newcomer)
	newcomer.set_physics_process(false)
	t.near(newcomer.damage_mult,newcomer.difficulty.damage_mult*1.21,0.00001,"new enemy spawns at current time tier")
	newcomer.free()
	var hud: FlightHUD = main.get("hud")
	var fp_saved := Settings.first_person
	for fp in [false,true]:
		Settings.first_person = fp
		t.ok(FlightHUD.EndlessIntensityHUD.active(hud),"table is available in either combat view")
	Settings.first_person = fp_saved
	Game.match_mode = Game.MatchMode.VERSUS
	var retained: float = members[0].damage_mult
	var retained_clock := Game.endless_elapsed
	main.call("_tick_endless",300)
	t.eq(Game.endless_elapsed,retained_clock,"other modes do not advance intensity clock")
	t.eq(members[0].damage_mult,retained,"other modes do not apply time scaling")
	t.ok(not FlightHUD.EndlessIntensityHUD.active(hud),"table is hidden outside this mode")
	Game.match_mode = Game.MatchMode.ENDLESS
	Game.endless_elapsed = clock_before
	Game.endless_enemy_reinforce = reinforce_before
	for saved: Array in snapshot: saved[0].damage_mult = saved[1]

static func _stats(t: T, main: Node) -> void:
	var pl: FlightBody = main.get("player")
	var max_before := pl.max_hp
	var hp_before := pl.hp
	var ifield_max_before := pl.ifield_max
	var ifield_before := pl.ifield_hp

	# 手动把两个上限抬起来（模拟"拿了一张装甲卡 + 一张立场卡"）
	var p := pl.profile
	p.set(&"_hull_hp", float(p.get(&"_hull_hp")) * 1.38)
	p.set(&"_ifield_hp", float(p.get(&"_ifield_hp")) * 1.28)
	pl.refresh_profile_stats()

	t.gt(pl.max_hp, max_before, "★ `refresh_profile_stats()` 把新耐久上限**抄了进来**")
	t.gt(pl.hp, hp_before,
		"★ 当前血**按增量往上补**（`hp += 新上限 − 旧上限`；比例保留的话这里不涨）")
	t.eq(pl.max_hp, pl.profile.hull_hp, "抄完之后 `max_hp` == `profile.hull_hp`（逐位）")
	if ifield_max_before > 0.0:
		t.gt(pl.ifield_max, ifield_max_before, "I 立场上限同样被抄进来")
		t.gt(pl.ifield_hp, ifield_before, "I 立场当前值也按增量补")
	t.gt(pl.hp, 0.0, "补血之后血是正的（没有把血算成负数或 0）")


# ─────────────────────────────────────────────── 工具

static func _in_round() -> bool:
	return Game.endless_phase == ENDLESS.Phase.INTERMISSION \
		or Game.endless_phase == ENDLESS.Phase.BONUS


## 推一帧钟 —— **两个钟都要推**（`_process()` 里它们就是这样紧挨着调的）。
##
## ⚠️ 不 `await tree.process_frame` 去等真实帧时间：无头下的帧间隔不确定，
## 要凑够 10 s 得等上千帧。这里直接把 delta 喂进去，时间完全可控。
static func _tick(main: Node, dt: float) -> void:
	main.call("_tick_endless", dt)
	main.call("_tick_endless_round", dt)


## 把**当前这一波**的敌机全清掉。
##
## ⚠️ 走真回调 `_on_endless_enemy_destroyed()`，**不是**直接
## `Game.endless_wave_remaining = 0` —— 后者只改结果、绕过 main 里那段
## "清空 ⇒ 进 CLEARING"的逻辑，而**那一段正是 R3 改动的入口**
##（原来它直接刷下一波）。绕过它就等于什么都没测。
static func _wipe(t: T, main: Node, tree: SceneTree) -> void:
	var units: Array = main.get("wave_units")
	var n := Game.endless_wave_total
	if n <= 0 or units.is_empty():
		t.ok(false, "本波没有敌机可清（`wave_units` 空 / `wave_total` = %d）" % n)
		return
	for i in n:
		var u: Node3D = units[i % units.size()] as Node3D
		main.call("_on_endless_enemy_destroyed", null, u)
	t.eq(Game.endless_wave_remaining, 0, "清完之后本波剩余数归零")
	# 真把节点也清掉：不然场上越积越多，下一波刷出来会和旧的混在一起
	for u in units:
		if u != null and is_instance_valid(u):
			(u as Node).queue_free()
	await tree.process_frame
