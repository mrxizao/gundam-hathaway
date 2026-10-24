class_name SuiteMissionAces
extends RefCounted
## 剧情关**敌方编制**的硬约束：「M03 / M06 的敌人里不出现王牌机」（轮 51 · 2026-09-30）。
##
## ⚠️ 轮 55（2026-09-30）口径更新：M03「接货」**整个删掉了敌方编制**（老板：「接货这一关不要设置敌人」）
## ⇒ 它现在**一台敌机都没有**，那条硬约束对它**空成立**（没有敌人 ⇒ 自然没有王牌机）。
## 判据因此分两半：
##   · **M03**：`has_enemies() == false`（零敌机是这条约束的「最强形式」）；
##   · **其余关**：仍按白名单查（`_whitelist()` 那条循环一个字没动）。
##
## ## 老板原话
##
## 「M06 和 M07 的敌人配置里不要有王牌机（佩涅罗佩和阿利宙斯）」
## 口述两条补充：「M03 和 M07 一起清，M05 不清」「M07 并成一波 3 台古斯塔夫00」。
## ★ 上面这三句是**老板原话**，按**他当时口述的编号**抄的；他口述的关号与代码 `id`
##   一向对不上（见 `notes/14`）⇒ 顺位后**故意不动它们**，免得把"原话"记成别的话。
##   （按**现在的 id** 写的口径见本文件第 3 行：「M03 / M06 的敌人里不出现王牌机」。）
##
## ## 这一套在钉什么
##
## 改动本身只是几个字段，但「哪几关的敌人可以是王牌机」在改之前是一句**口头约定** ——
## 而口头约定在这张表里对应一整类**不会报错的失败**：
##
## | 症状 | 为什么会静默 | 本套哪一条 |
## |---|---|---|
## | 简报写「敌方：佩涅罗佩」，场上却全是量产机 | `enemy_suit` 与 `waves` 是**两个字段**，没人对账 | ② 简报不许撒谎 |
## | 王牌机撤了，电台还在念「佩涅罗佩，下降」 | 台词正文是自由文本，**没有任何消费者校验它** | ④ 电台不撒谎 |
## | 并波之后留着「清场」拍子 —— 它**一次都不会触发** | `win_on_clear` 的关在末机销毁那一帧就判胜 ⇒ `_tick_mission_triggers()` 整帧被跳过 | ⑦ 死拍子 |
## | 将来顺手给 M05 加一波王牌 | 没有「敌方不许是 ACE」这条不变量 | ① 白名单 |
## | 判据自己写错了（永远返回空） | 一条**只会通过**的断言与一条**真的在盯**的断言长得一样 | ⑥ 反向对照 |
##
## ## 本轮顺带发现的一条：并波会制造**死拍子**
##
## 老板口径「M06 并成一波 3 台古斯塔夫00」把原来挂在第 1 波上的 `wave_cleared:0`
## 从「中途拍子」变成了「结束拍子」：本关的 `win_on_clear` 是**默认的 true**，
## `Game._evaluate_end()` 里那道「还有没刷出来的波次时不许判胜」的守卫
##（`challenge_wave + 1 < wave_count`）在**单波**时恒假 ⇒ 末机销毁那一帧就判胜；
## 而 `main._tick_mission_triggers()` 第一行是 `phase != Phase.FIGHT ⇒ return`
## ⇒ 那条触发器**一次都不会被求值**。不是「被结算页盖住」，是**结构性不可达**。
## ⇒ 本轮把 M06 的那条触发器及其 `ira_05` 台词整条撤掉；判据见 ⑦。
## ⚠️ M07 的 `wave_cleared:0` **不受影响**（`xi_vs_arizeus()` 有 2 波 ⇒ 守卫放行，它是真拍子）。
## 判据写成**带前提**的，正是为了不拦着这种复用。
##
## ## 为什么是白名单，而不是"谁都不许"
##
## M04（重力）与 M07（艾尔斯岩）的王牌戏是**有意的**：前者逐字搬
## `xi_vs_penelope()`、后者逐字搬 `xi_vs_arizeus()`（DESIGN §4.3「原样」）。
## ⇒ 判据写成「除 `ACE_ENEMY_OK` 之外，任何一关的敌方都不许是 ACE」。
##
## ⚠️ **ACE 的判定一律走 `SuitProfile.is_ace()`**（唯一真源）—— 本套**不自带**一份机号名单，
##    否则将来加第四台 ACE 时两份名单当场分家。
## ⚠️ 跨文件引用走 `preload`（同 `suite_campaign` 头注那条：新 `class_name` 不在无头跑的类缓存里）。

const MS := preload("res://scripts/data/mission_script.gd")
const COMMS := preload("res://scripts/data/comms.gd")

## 敌方**允许**出现王牌机的关（有意的宿敌戏）。
const ACE_ENEMY_OK := ["M04", "M07", "M09", "M11", "M12"]

## 被老板点名的那两台。**只用于断言的文案** —— 判定一律走 `is_ace()`。
const NAMED_ACES := ["佩涅罗佩", "阿利宙斯"]


static func run(t: T) -> void:
	t.suite("剧情模式 / 敌方编制（M03 零敌机 · M06 不出现王牌机）")
	_whitelist(t)
	_briefing(t)
	_literals(t)
	_radio(t)
	_landed(t)
	_selfcheck(t)
	_beats(t)


# ============================================================ ① 白名单
## 除 `ACE_ENEMY_OK` 外，任何一关的**敌方字段**与**波次**里都不许有 ACE。
static func _whitelist(t: T) -> void:
	var bad: Array = []
	for m: MS.Mission in MS.all():
		if ACE_ENEMY_OK.has(m.id):
			continue
		var mark := _ace_in_enemy(m)
		if mark != "":
			bad.append("%s（%s）" % [m.id, mark])
	t.eq(bad.size(), 0,
		"除白名单（%s）外没有一关的敌人是王牌机。越界的：%s" % [",".join(ACE_ENEMY_OK), str(bad)])

	# 白名单本身要**真的用得到** —— 否则它只是一句"以后也许"的空话。
	# 只有把集合列出来，「多了 = 漏清」与「少了 = 白名单虚挂」这两头才都看得见。
	var hits: Array = []
	for m2: MS.Mission in MS.all():
		if _ace_in_enemy(m2) != "":
			hits.append(m2.id)
	t.eq(",".join(hits), ",".join(ACE_ENEMY_OK),
		"有王牌敌机的关恰好是各章配置的白名单（少了 = 白名单虚挂）")


## 这一关的**敌方**里有没有王牌机。
##
## 返回 `""` = 没有；否则返回一句人话（哪个字段、哪台机）—— 出红时一眼看出越界点。
##
## ⚠️ `enemy_suit` 与 `waves` **必须各查一次**：它们是两个字段，只改一个的表现是
##    「简报写着佩涅罗佩、场上全是古斯塔夫」，而这一处**一处都不报错**。
static func _ace_in_enemy(m: MS.Mission) -> String:
	if m == null:
		return ""
	var p: SuitProfile = SuitProfile.by_id(m.enemy_suit)
	if p != null and p.is_ace():
		return "enemy_suit=%s" % p.display_name
	var names: Array = []
	for w: ChallengeScript.Wave in m.waves:
		var wp: SuitProfile = SuitProfile.by_id(w.suit)
		if wp != null and wp.is_ace():
			names.append(wp.display_name)
	if not names.is_empty():
		return "waves=%s" % ",".join(names)
	return ""


# ============================================================ ② 简报不许撒谎
## 有敌人的关，简报那一行「敌方：X」必须**就是**真的会出场的机型之一。
##
## 理由：`enemy_suit` 是给简报用的**独立字段**，而真正撒出来的是 `waves[].suit`。
## 两者可以只改一个 —— 表现是备战页在玩家出发前就撒一个谎，且没有任何代码会报错。
static func _briefing(t: T) -> void:
	var bad: Array = []
	for m: MS.Mission in MS.all():
		if not m.has_enemies():
			continue
		var suits: Array = []
		for w: ChallengeScript.Wave in m.waves:
			if not suits.has(w.suit):
				suits.append(w.suit)
		if not suits.has(m.enemy_suit):
			bad.append("%s：写的 %s，实际出 %s" % [m.id, m.enemy_suit_name(), str(suits)])
	t.eq(bad.size(), 0, "简报上那一行「敌方：」= 真的会出场的机型（撒谎的：%s）" % str(bad))
	# 这条是**可证伪**的：M06 被改过，两个字段都动过 —— 若只改了其中一个，上面那条就会点名它。
	t.eq(MS.by_id("M06").enemy_suit, SuitProfile.Id.MESSER_M01, "M06 的敌方字段 = 梅萨M01")
	# ★ 轮 55：M03 现在**没有敌人**，所以「简报不许撒谎」这条对它**自动成立**：
	# `has_enemies()` 一为假，上面那条循环就跳过它。
	# ⚠️ 但跳过就是盲区 —— 将来有人给它惄惄加回一波、而 `enemy_suit` 又没同步，
	# 就会**一处都不报错**。⇒ 把「零敌机」本身写成一条可断言的事实。
	# ⚠️ `enemy_suit` 字段**按 M01 的惯例留着**（元数据，不是「会出场」的承诺）。
	var m03b: MS.Mission = MS.by_id("M03")
	t.not_ok(m03b.has_enemies(), "★ M03 零敌机（`has_enemies()` == false ⇒ 简报不写「敌方：」那一行）")
	t.eq(m03b.enemy_suit, SuitProfile.Id.GUSTAV00,
		"M03 的 `enemy_suit` 仍是古斯塔夫00（元数据，与 M01 同惯例；不进简报）")


# ============================================================ ③ 玩家可见文案
## M03 / M06 的简报、任务背景、目标名里不许再出现那两台王牌的名字。
static func _literals(t: T) -> void:
	for mid: String in ["M03", "M06"]:
		var m: MS.Mission = MS.by_id(mid)
		t.ok(m != null, "取到 %s" % mid)
		if m == null:
			continue
		var pool: Array = [m.enemy_suit_name(), m.brief, m.story]
		for o: MS.Objective in m.objectives:
			pool.append(o.label)
		var hit: Array = []
		for s: String in pool:
			for nm: String in NAMED_ACES:
				if s.contains(nm):
					hit.append(s)
		t.eq(hit.size(), 0,
			"%s 的简报/背景/目标文案里不出现王牌机名（命中：%s）" % [mid, str(hit)])


## 这一关有没有**结构性不可达**的「清场」拍子。
##
## 单波 + `win_on_clear` ⇒ `Game._evaluate_end()` 在末机销毁那一帧就 `set_phase(WIN)`，
## 而 `main._tick_mission_triggers()` 第一行 `phase != FIGHT ⇒ return`
## ⇒ 挂在 `wave_cleared:*` 上的动作永远等不到求值。
##
## ⚠️ 前提写进判据里（**不**写成「谁都别用这个键」）：将来给某关补上第 2 波时，
## 这条不该拦着它复用同一个键。
static func _dead_clear_beats(m: MS.Mission) -> Array:
	var out: Array = []
	if m == null or not bool(m.win_on_clear) or m.wave_count() > 1:
		return out
	for trg: MS.Trigger in m.triggers:
		var w := str(trg.when)
		if w.begins_with("wave_cleared"):
			out.append(w)
	return out


# ============================================================ ④ 电台不撒谎
## 撤了王牌机却留着「佩涅罗佩，下降」是最容易漏的一处 —— 台词正文没有任何消费者校验。
static func _radio(t: T) -> void:
	for mid: String in ["M03", "M06"]:
		var m: MS.Mission = MS.by_id(mid)
		if m == null:
			continue
		var ids: Array = []
		for trg: MS.Trigger in m.triggers:
			var act := trg.do_what
			if act.begins_with("radio:"):
				ids.append(act)
		t.gt(float(ids.size()), 0.0, "%s 至少有 1 条电台（否则下面那条是空转）" % mid)
		var hit: Array = []
		for rid: String in ids:
			var txt := str(COMMS.radio(rid).get("text", ""))
			for nm: String in NAMED_ACES:
				if txt.contains(nm):
					hit.append("%s → %s" % [rid, txt])
		t.eq(hit.size(), 0, "%s 的电台台词里不出现王牌机名（命中：%s）" % [mid, str(hit)])
	# 两条被撤掉的旧台词必须**真的没了**：留着会变成孤儿条目，
	# 把 `suite_comms` 那条「没有孤儿台词」的双向扫描顶红。
	t.not_ok(COMMS.has_radio("lane_02"), "`lane_02`（「佩涅罗佩，下降」）已整条撤出通讯表")
	# ⚠️ 轮 55（2026-09-30）M03 那一拍**又换了一次**：从上一版**自己编的**
	# 「联邦巡逻机：运输仓外侧有热源……」换成哈萨维的原句（`h1:1117`「雷蒙德 敌人将至」）
	# —— 剧本 07-17 那一场压根没有联邦侧的台词。
	# ★ **这条断言的用意一个字没变**：那一拍不许是王牌机在说话。
	t.eq(str(COMMS.radio("radio:leo_hathaway_01").get("speaker", "")), "哈萨维",
		"M03 的 60 秒拍子是哈萨维的原话（不再是自己编的联邦巡逻机）")
	t.not_ok(COMMS.has_radio("ira_05"),
		"`ira_05` 没有落地（它要挂的那条触发器不成立 ⇒ 落地就是孤儿条目）")
	# M04 的重力仍然要有通讯 —— id 从 `lane_01` 换成 `duel_lane_01`（原来那条的
	# `src` 指着 `h1:1205`，正文却是自己写的"进入交战距离"）。
	t.ok(COMMS.has_radio("duel_lane_01"), "M04 的重力仍要有人说话（`duel_lane_01`）")
	# ★ 2026-10-01 老板：`h1:1208`「拿出你的本事 马夫蒂」是**加乌曼**说的
	#   （原句库那一列本来就是「推断」，已改真源 CSV 并重建）。
	# ⚠️ `suite_comms` 那条「说话人逐字等于原句库」只能证明**两边同步**，
	#   证明不了「是谁说的」⇒ 说话人本身必须在这里正面钉死，否则回退没人拦。
	t.eq(str(COMMS.radio("duel_lane_01")["speaker"]), "加乌曼",
		"★ M04 开场 20 秒那一拍是加乌曼说的（不再是推断出来的雷恩）")


# ============================================================ ⑤ 落成数
## 改完之后的编成。改玩法要看得见数 —— 只写"改了"等于没改。
static func _landed(t: T) -> void:
	# ★ 轮 55：M03 的**整个敌方编制**随老板口径下架（`waves = []`）—— 不是「换机型」，是**没有敌人**。
	# 原来那四条波次断言（1 波 / 1 台 / 古斯塔夫00 / 高度 `ORBIT_ALT + 8000`）
	# 描述的是一支**已经不存在的部队** ⇒ 换成「零敌机是本关的一个可断言事实」。
	var m03: MS.Mission = MS.by_id("M03")
	t.eq(m03.wave_count(), 0, "★ M03 零波（老板：「接货这一关不要设置敌人」）")
	t.eq(m03.total_enemies(), 0, "★ M03 全场 0 台敌机")
	t.not_ok(m03.has_enemies(), "★ `has_enemies()` == false（`to_encounter()` 拿到的 `waves` 也是空的）")
	# ⚠️ 与 `_dead_clear_beats()` 的联动：零敌机的关**必须** `win_on_clear = false`，
	# 否则「场上无敌对单位」开局即成立 ⇒ 任何一台单位被销毁都会把它当成打赢（判据在 `suite_campaign`）。
	t.not_ok(m03.win_on_clear, "★ M03 的胜负改由目标门给（零敌机的关不许走清场判胜）")

	var m06: MS.Mission = MS.by_id("M06")
	t.eq(m06.wave_count(), 1, "★ M06 并成了 1 波（原来 2 波）")
	t.eq(m06.total_enemies(), 2, "M06 两台梅萨护卫英勇号")
	var w07: ChallengeScript.Wave = m06.waves[0]
	t.eq(w07.suit, SuitProfile.Id.MESSER_M01, "M06 那一波是梅萨M01")
	t.ok(m06.waves_auto, "M06 的 `waves_auto` 仍是默认的 true（它本来就是自动推波）")

	# ---- 反向：M04 一个字没动（这是"只清了 M03 / M06"的证据）
	var m04: MS.Mission = MS.by_id("M04")
	t.eq(m04.enemy_suit, SuitProfile.Id.PENELOPE, "★ M04 的佩涅罗佩**保留**（老板：M04 不清）")
	t.eq(m04.wave_count(), 1, "M04 仍是一波")
	var w05: ChallengeScript.Wave = m04.waves[0]
	t.eq(w05.suit, SuitProfile.Id.PENELOPE, "M04 那一波仍是佩涅罗佩")

	# ---- M05：老板点名了它，如实核一遍（它本来就只出古斯塔夫）
	var m05: MS.Mission = MS.by_id("M05")
	t.eq(_ace_in_enemy(m05), "", "★ M05 的敌人里没有王牌机（本来就没有 —— 这是**核对**，不是改动）")
	t.eq(m05.total_enemies(), 4, "M05 仍是 3 + 1（两波古斯塔夫）")
	t.not_ok(m05.waves_auto, "M05 的事件驱动增援没动")


# ============================================================ ⑥ 判据自检
## 判据本身必须**会红**：一条"永远返回空"的检查与一条真的在盯的检查长得一模一样。
static func _selfcheck(t: T) -> void:
	# ---- 反向对照（人造样本）：两个字段各来一次
	var fake: MS.Mission = MS.Mission.new("X99", "人造样本")
	fake.enemy_suit = SuitProfile.Id.ARIZEUS
	t.ok(_ace_in_enemy(fake).contains("阿利宙斯"),
		"★ 反向对照：`enemy_suit` 是阿利宙斯 ⇒ 判据点名它（不是「永远返回空」）")
	fake.enemy_suit = SuitProfile.Id.GUSTAV00
	fake.waves = [ChallengeScript.Wave.new(1, SuitProfile.Id.PENELOPE, 3200.0)]
	t.ok(_ace_in_enemy(fake).contains("佩涅罗佩"),
		"★ 反向对照：只把**波次**换成佩涅罗佩 ⇒ 也点名（两个字段各查一次）")
	fake.waves = [ChallengeScript.Wave.new(2, SuitProfile.Id.GUSTAV00, 3200.0)]
	t.eq(_ace_in_enemy(fake), "", "正对照：全是量产机 ⇒ 返回空串")

	# ---- ★ 真关数据的反向对照：把 M06（**不在白名单里**）就地改回佩涅罗佩。
	# 上面那两条只证明"判据函数认得出 ACE"；这一条补上另一半 ——
	# "白名单那段循环真的会在一个非白名单的关上报出来"。
	# ⚠️ `MS.by_id()` 每次调用都**重新派生**（`all()` 里现造），所以这份实例改坏不会漏给别人。
	var live: MS.Mission = MS.by_id("M06")
	var keep_suit: int = live.enemy_suit
	var keep_waves: Array = live.waves
	live.enemy_suit = SuitProfile.Id.PENELOPE
	live.waves = [ChallengeScript.Wave.new(1, SuitProfile.Id.PENELOPE, 3200.0)]
	t.ok(_ace_in_enemy(live) != "", "★ 反向对照（真关数据）：M06 改回佩涅罗佩 ⇒ 判据认得出")
	t.not_ok(ACE_ENEMY_OK.has(live.id), "★ 而 M06 **不在**白名单里 ⇒ 上一条会升级成 FAIL（才是真判据）")
	live.enemy_suit = keep_suit
	live.waves = keep_waves
	t.eq(_ace_in_enemy(live), "", "还原之后 M06 又干净了（本条的副作用为零）")

	# ---- 真源对账：`is_ace()` 现在到底认哪几台（整套判据都建在它上面）
	t.not_ok(SuitProfile.by_id(SuitProfile.Id.GUSTAV00).is_ace(), "古斯塔夫00 不是 ACE")
	t.not_ok(SuitProfile.by_id(SuitProfile.Id.MESSER_M01).is_ace(), "梅萨M01 不是 ACE")
	t.ok(SuitProfile.by_id(SuitProfile.Id.PENELOPE).is_ace(), "佩涅罗佩是 ACE")
	t.ok(SuitProfile.by_id(SuitProfile.Id.ARIZEUS).is_ace(), "阿利宙斯是 ACE")
	t.ok(SuitProfile.by_id(SuitProfile.Id.XI).is_ace(), "柯西是 ACE")

	# ---- ⑦ 死拍子那条判据的反向对照（三个人造态）
	var db: MS.Mission = MS.Mission.new("X98", "人造样本")
	db.win_on_clear = true
	db.waves = [ChallengeScript.Wave.new(1, SuitProfile.Id.GUSTAV00, 3200.0)]
	db.triggers = [MS.Trigger.new("wave_cleared:0", "radio:zz", true, "zz_clear")]
	t.eq(_dead_clear_beats(db).size(), 1,
		"★ 反向对照：单波 + `win_on_clear` + `wave_cleared:0` ⇒ 点名它（不是「永远返回空」）")
	db.waves = [ChallengeScript.Wave.new(1, SuitProfile.Id.GUSTAV00, 3200.0),
		ChallengeScript.Wave.new(1, SuitProfile.Id.GUSTAV00, 4200.0)]
	t.eq(_dead_clear_beats(db).size(), 0,
		"前提①：补上第 2 波 ⇒ 同一个键**合法**（判据不拦复用）")
	db.waves = [ChallengeScript.Wave.new(1, SuitProfile.Id.GUSTAV00, 3200.0)]
	db.win_on_clear = false
	t.eq(_dead_clear_beats(db).size(), 0,
		"前提②：`win_on_clear = false`（目标门）的关不受这条约束")


# ============================================================ ⑦ 死拍子
## 单波 + `win_on_clear` 的关**不许**挂 `wave_cleared:*` —— 那条拍子结构性不可达。
##
## 这一条不是「顺手加的洁癖」：老板口径「M06 并成一波」正是**制造**这类死拍子的动作
##（原来清第 1 波是本局中途，并波之后清唯一一波 = 本局结束）。
## ⇒ 写成不变量，下一次并波 / 减波时会当场看到红。
##
## ⚠️ 判据**带前提**（单波 **且** `win_on_clear`）—— 见 `_dead_clear_beats()` 的注释。
static func _beats(t: T) -> void:
	var dead: Array = []
	for m: MS.Mission in MS.all():
		for w: String in _dead_clear_beats(m):
			dead.append("%s[%s]" % [m.id, w])
	t.eq(dead.size(), 0,
		"没有一关把「清场」拍子挂在结构性不可达的位置（死拍子：%s）" % str(dead))
	var m06b: MS.Mission = MS.by_id("M06")
	t.eq(_dead_clear_beats(m06b).size(), 0,
		"★ M06（本轮并波的那一关）里没有 `wave_cleared:*`")
	# 另一头也钉住：M07 有 2 波 ⇒ 它的同款拍子**是**真拍子（免得被下一个人一起删掉）
	var m07b: MS.Mission = MS.by_id("M07")
	t.gt(float(m07b.wave_count()), 1.0,
		"M07 有 2 波 ⇒ 它的 `wave_cleared:0`（哈拉那句）是真拍子")
