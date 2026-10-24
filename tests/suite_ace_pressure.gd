class_name SuiteAcePressure
extends RefCounted
## **王牌机的强制进攻节拍**（轮 63-9 · B5）。
##
## 用户原话（2026-10-04）：「阿利宙斯偶尔会一直跑路，需要让他进攻欲望增强。」
##
## ## 这一轮动的是什么
## 只动**两个 ACE 专属常量**（`bandit_ai.gd`）：
## `ACE_ATTACK_PERIOD 12.0 → 9.0` · `ACE_COMMIT_WINDOW 4.0 → 5.0`
##（占空比 33.3% → 55.6%）。**不动 `AGGRESSION`** —— 它已标定到 +30%，
## `README.md` 里有那张历史标定表；重标一次要连带 `engage_dist` /
## `break_dist` / `evade_seconds` / `extend_seconds` 四处，那是另一件事。
##
## ## ★★ 施工期发现（这条比两个常量值钱）
## 强制脉冲在**远距是"无声的"**：`_ace_commit` 只挡住了 ATTACK 分支的
## 前两条出口（贴太近要脱战 / 被威胁要转防御），**没有挡第三条**
##（`dist > engage_dist() * 1.35 ⇒ 回 SEEK`）。
## 于是远距触发脉冲之后，同一帧就被送回 SEEK ——
## 实测（§④-b，120 km）：脉冲**确实按时触发**（`_ace_pressure` 归零、
## `_ace_commit` 被武装），但 `state` 全程 `SEEK`。
##
## **这不是 bug，是有利的让位**，理由是量出来的而不是猜的：
## 远距时 `ATTACK` 与 `SEEK` 走**同一个方向**（`dist >= gun_range` ⇒ 两个分支
## 都返回 `_intercept_dir_beam()`），差别只在油门 ——
## `SEEK` 是 `0.92 + boosting`、`ATTACK` 是 `1.0 + 不 boost`）。
## ⇒ 让位给 SEEK **更快**。硬把 ATTACK 钉住反而会**拖慢**它压上去。
## 所以本轮**不改**那一条，只在源码里加一句说明 + 在 §④-b 把它钉住
##（免得下一个人把它当 bug"修"掉）。
##
## ⚠️ 也就是说：脉冲真正起作用的地方是
## `break_dist() < dist < engage_dist() * 1.35` —— 也就是"该冲却没冲"的那段。
## 判据必须站在那一段上，站在 120 km 上量到的只是"让位"。
##
## ## ⚠️ 本套件**钉不住**什么（如实说明）
## 「手感是不是变好了」钉不住 —— 那要人玩。这里钉的是四件**可证伪**的事：
##   ① 占空比与周期值（常量级）
##   ② 五个「不许连带」的旋钮逐位没动（源码级）
##   ③ SEEK 的巡速**有意**不与 `AGGRESSION` 耦合（源码级，见③的说明）
##   ④ 真机：中距（脉冲的作用区间）里一个周期内被强制切入 ATTACK 且窗口内不被推翻；
##      远距只触发不换态；两种距离下量产机都不吃这个节拍
##
## ## 真机读数（不在本套件里，避免绝对值随态势漂）
## `tools/probe_aggression.tscn`（3 态势 × 60 s，AI 对 AI）——
## 改动前后各一组，见轮 63-9 交付件。

const DUTY := "AcePressure / ① 占空比与周期：把「想让它多凶」变成可算的数"
const NO_SIDE := "AcePressure / ② 不许连带：准头 / 射速 / 锁定 / 安全线逐位没动"
const SEEK_AGGR := "AcePressure / ③ SEEK 的巡速不与 AGGRESSION 耦合 + 让位的根据"
const LIVE_MID := "AcePressure / ④-a 真机：中距一个周期内强制切入 ATTACK 并守住窗口"
const LIVE_FAR := "AcePressure / ④-b 真机：远距按时触发但**不换态**（让位给更快的 SEEK）"

const AI := "res://scripts/ai/bandit_ai.gd"
const DIFF := "res://scripts/data/difficulty.gd"


static func run(t: T, host: Node) -> void:
	t.suite(DUTY)
	_duty(t)
	t.suite(NO_SIDE)
	_no_side(t)
	t.suite(SEEK_AGGR)
	_seek_aggr(t)
	t.suite(LIVE_MID)
	await _live_mid(t, host)
	t.suite(LIVE_FAR)
	await _live_far(t, host)


# ------------------------------------------------------------ ① 常量级

static func _duty(t: T) -> void:
	t.near(BanditAI.ACE_ATTACK_PERIOD, 9.0, 0.001,
		"强制进攻周期 = **9 秒**（63-9 用户改口；原稿的 12 秒也是用户自己定的）")
	t.near(BanditAI.ACE_COMMIT_WINDOW, 5.0, 0.001, "不许脱战窗口 = **5 秒**（原 4 秒）")
	t.ok(BanditAI.ACE_COMMIT_WINDOW > 4.0, "窗口比原稿**更大**（进攻之后更能赖着不走）")
	t.ok(BanditAI.ACE_ATTACK_PERIOD < 12.0, "周期比原稿**更短**（来得更勤）")

	var duty: float = BanditAI.ACE_COMMIT_WINDOW / BanditAI.ACE_ATTACK_PERIOD
	t.ok(duty >= 0.5, "占空比不低于 0.5，实测 " + str(snappedf(duty, 0.001)))
	t.ok(duty < 1.0, "占空比仍小于 1（还留得出脱离的时间，不是无脑冲）")

	# 周期与窗口的**唯一真源**：源码里各只有一个 `:=` 赋值，不许在别处补一个乘子。
	var ai := _code(AI)
	t.eq(ai.count("ACE_ATTACK_PERIOD := "), 1, "周期常量只有一处赋值")
	t.eq(ai.count("ACE_COMMIT_WINDOW := "), 1, "窗口常量只有一处赋值")
	t.eq(ai.count("_tick_ace_pressure("), 2, "节拍函数 = 一处定义 + 一处调用（不许在别处再补一次）")
	t.ok(ai.contains("func _tick_ace_pressure(delta: float) -> void:")
		and ai.contains("if not _is_ace():\n\t\treturn"),
		"节拍**只对 ACE 生效**（量产机不吃这个旋钮）")


# ------------------------------------------------------------ ② 不许连带

## ⚠️ 这一段的形态是**源码字面量扫描**，不是行为断言。
##
## 理由：这几项在本工程里**没有可读的运行时真源**（`@export var` / 局部 `lerpf`
## 参数 / 难度表里的赋值），量行为要起一整局加时间推进，成本与收益不成比例；
## 而"本轮不许夹带它们"这条纪律本身是**文本级**的 —— 改了就红，正是我们要的。
##
## 代价：今后**真的**要合法调这几项时，这段会先红。那时把它当成
## 「提醒你把 63-9 的纪律条款一并改掉」，而不是当成误报。
static func _no_side(t: T) -> void:
	var ai := _code(AI)
	var df := _code(DIFF)

	t.ok(ai.contains("gun_cone_deg := 5.5"), "机炮锥角仍是 5.5 度")
	t.ok(ai.contains("beam_cone_deg := 9.0"), "光束锥角仍是 9.0 度")
	t.ok(ai.contains("ang < beam_cone_deg + 4.0 * skill"), "光束开火判据仍是 + 4.0 乘 skill")
	t.ok(ai.contains("ang < gun_cone_deg + 3.0 * skill"), "机炮开火判据仍是 + 3.0 乘 skill")
	t.ok(ai.contains("_burst_timer = lerpf(1.1, 0.35, skill)"), "点射间隔仍是 1.1 到 0.35")
	t.ok(ai.contains("_burst_timer = lerpf(0.55, 0.95, skill)"), "点射持续仍是 0.55 到 0.95")
	t.ok(ai.contains("dist < missile_range and dist > 320.0"),
		"浮游导弹的发射距离窗口仍是 4200 / 320")
	t.ok(ai.contains("var ai_cd := 0.36 - 0.05 * skill"), "AI 齐射冷却仍是 0.36 到 0.31")

	t.ok(ai.contains("SAFE_ALTITUDE := 1600.0"), "AI 安全高度仍是 1600 m")
	t.ok(ai.contains("CRITICAL_ALTITUDE := 700.0"), "AI 危险高度仍是 700 m")

	t.ok(ai.contains("AGGRESSION := 1.14"), "AGGRESSION 仍是 1.14（本轮**不动**它）")
	t.ok(df.contains("lock_time_mult := 1.25"), "锁定耗时默认仍是 1.25")
	t.ok(df.contains("lock_outer_deg := 40.0"), "锁定锥默认仍是 40 度")
	t.ok(df.contains("lock_decay_mult := 0.80"), "质量衰减默认仍是 0.80")
	t.ok(df.contains("relock_lockout := 1.8"), "掉锁冷却默认仍是 1.8 秒")
	t.ok(df.contains("d.lock_time_mult = 1.80") and df.contains("d.lock_outer_deg = 32.0"),
		"困难档的锁定量仍是 1.80 / 32 度")
	t.ok(df.contains("d.lock_time_mult = 0.70") and df.contains("d.lock_outer_deg = 46.0"),
		"简单档的锁定量仍是 0.70 / 46 度")


# ------------------------------------------------------------ ③ SEEK 的巡速 + 让位的根据

## 这一条是设计文档 §2.5 判据 3 的**结论**，但结论与原文相反，所以要把理由写死。
##
## 判据 3 原话：「`aggression = 1.14` 与 `2.0` 两种取值下，`SEEK` 的 `fm.throttle`
## 必须**不同**；今天两者相同 ⇒ 红。要么接上，要么把『AGGRESSION 不影响巡速』
## 写进注释并加一条断言钉住。」
##
## 取**后者**（不接上）。理由：`SEEK` 的 `0.92` 是**巡速**，而 `AGGRESSION`
## 管的是**接战距离 / 脱离距离 / 两种时长** —— 都是"想不想打"，不是"飞多快"。
## 把它接到巡速上，等于让"更凶"顺便变成"更快"，那正好与 D1
##（m02 的梅萨追不上）那条需求**反着走**：追不上的对手会更快地跑掉。
##
## ⚠️ 也就是说：这里钉的是一条**经过取舍的决定**，不是一条"本来就该绿"的断言。
## 谁要改这个决定，必须同时改掉这条断言与它上面这段话。
static func _seek_aggr(t: T) -> void:
	var ai := _code(AI)
	var i := ai.find("func _drive_throttle(dist: float) -> void:")
	t.gt(float(i), 0.0, "找到 `_drive_throttle` 的真源")
	var j := ai.find("\nfunc ", i + 1)
	t.gt(float(j), float(i), "找到它的结尾（下一个顶层 func）")
	var body := ai.substr(i, j - i)

	var k := body.find("State.SEEK:")
	t.gt(float(k), 0.0, "找到 SEEK 那一支")
	var nxt := body.find("State.ATTACK:", k)
	t.gt(float(nxt), float(k), "找到 ATTACK 那一支（用它切出 SEEK 的范围）")
	var seek := body.substr(k, nxt - k)

	t.ok(seek.contains("fm.throttle = 0.92"), "SEEK 的巡速仍是 0.92")
	t.ok(not seek.contains("AGGRESSION"),
		"SEEK 的巡速**不接** AGGRESSION（有意：那是速度，不是欲望 —— 见本段说明）")
	t.ok(seek.contains("fm.boosting = dist > engage_dist() * 1.2"),
		"SEEK 在远距保持 boost（这是它比 ATTACK 更快的原因）")
	t.ok(body.contains("fm.throttle = 1.0") and body.contains("fm.boosting = true"),
		"EXTEND / EVADE 仍是唯一加油门的那一支（这解释了「调高 AGGRESSION 反而显得慢」）")
	t.ok(body.contains("lerpf(0.45, 1.0, t)"), "ATTACK 的油门曲线仍是 0.45 到 1.0")


# ------------------------------------------------------------ ④-a 真机 · 中距

## 把两台机钉在 `break_dist() < dist < engage_dist() * 1.35` 那一带 ——
## **脉冲唯一真正起作用的地方**（见文件头「施工期发现」）。
##
## 为什么每帧把 `b` 挪回去：如果不钉，双方对头飞 4 km/s ⇒ 一秒就贴上了，
## 那时 SEEK 会**自然**转 ATTACK，"强制"与"自然"就分不开。
## 钉住之后 `dist` 恒大于 `engage_dist()` ⇒ 自然转移**在几何上不可能**。
## ⚠️ 间距的取法（第一版就栽在这里）：状态机量的是 `_aim_pos()`，那是**滞后**的
## 瞄准点（AI 的反应延迟），实测比真实间距**近约 500 m**。
## 第一版按 `engage_dist() * 1.15` 钉，有效距离掉到 3163 m < 3192 m ⇒
## 第 262 帧就**自然**转进了 ATTACK，看着像"提前乱冲"。
## ⇒ 取 `* 1.30`，并且**把"有效距离始终在接战距离之外"做成实测断言**
##   （不是假设）—— 前提一旦不成立，它会自己红出来，而不是把结论悄悄带歪。
static func _live_mid(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	var a := _mk(c, SuitProfile.xi(), 0, Vector3(0.0, 3200.0, 0.0))
	var b := _mk(c, SuitProfile.xi(), 1, Vector3(0.0, 3200.0, -4150.0))
	a.target_override = b
	b.target_override = a
	# 量产机**自己一套**（ACE / 量产机各配一个靶机）。
	#
	# ⚠️ 别让两台共用同一个靶机：那样 m 与靶机的几何关系与 a 不同，**滞后方向**
	# 也不同，实测 m 的有效距离变成 4788 m —— 掉到让位线（4309 m）**之外**，
	# 于是"去掉 ACE 闸门"这条负对照根本咬不到（m 当帧就被赶回 SEEK，
	# 看着像闸门有效，其实是距离条款在替它挡）。各配一套之后两者几何一致。
	var m := _mk(c, SuitProfile.messer_m01(), 0, Vector3(20000.0, 3200.0, 0.0))
	var b2 := _mk(c, SuitProfile.xi(), 1, Vector3(20000.0, 3200.0, -4150.0))
	m.target_override = b2
	b2.target_override = m
	await host.get_tree().physics_frame

	var hold: float = a.engage_dist() * 1.30
	t.gt(hold, a.engage_dist(), "钉住的间距在接战距离**之外**（自然转移走不通）")
	t.lt(hold, a.engage_dist() * 1.35, "但又在让位线**之内**（脉冲换出来的 ATTACK 不会被赶回 SEEK）")

	a.set_state(BanditAI.State.SEEK)
	a._ace_pressure = 0.0
	m.set_state(BanditAI.State.SEEK)
	m._ace_pressure = 0.0

	var frames := int((BanditAI.ACE_ATTACK_PERIOD + BanditAI.ACE_COMMIT_WINDOW + 1.0) * 60.0)
	var first := -1
	var run := 0
	var best := 0
	var min_aim := INF
	var min_aim_m := INF
	var m_attack := 0
	for i in frames:
		await host.get_tree().physics_frame
		# 钉住间距（见上面那段为什么）
		b.global_position = a.global_position + Vector3(0.0, 0.0, -hold)
		b2.global_position = m.global_position + Vector3(0.0, 0.0, -hold)
		min_aim = minf(min_aim, a.global_position.distance_to(a._aim_pos()))
		min_aim_m = minf(min_aim_m, m.global_position.distance_to(m._aim_pos()))
		if a.state == BanditAI.State.ATTACK:
			if first < 0:
				first = i
			run += 1
			best = maxi(best, run)
		else:
			run = 0
		if m.state == BanditAI.State.ATTACK:
			m_attack += 1

	t.gt(min_aim, a.engage_dist(),
		"整整 %d 帧里 ACE 的**有效距离**（到滞后瞄准点）最近 %.0f m 都在接战距离 %.0f m 之外"
		% [frames, min_aim, a.engage_dist()])
	t.gt(min_aim_m, m.engage_dist(),
		"量产机那一套的**有效距离**也一直在接战距离之外（最近 %.0f m）" % min_aim_m
		+ " —— 否则它会被自然转进 ATTACK，下面那条就不成立")
	t.gt(float(first), 0.0,
		"中距的纯 SEEK 里被强制切进了 ATTACK（第 %d 帧）" % first)
	t.ok(first >= int((BanditAI.ACE_ATTACK_PERIOD - 0.4) * 60.0),
		"不是提前乱冲：第 %d 帧不早于周期起点" % first)
	t.ok(first <= int((BanditAI.ACE_ATTACK_PERIOD + 1.0) * 60.0),
		"也没有拖过周期太久：第 %d 帧" % first)
	t.ok(float(best) >= (BanditAI.ACE_COMMIT_WINDOW - 0.5) * 60.0,
		"窗口内**没有被推翻**：连续 ATTACK 最长 %d 帧（窗口 = %d 帧）"
		% [best, int(BanditAI.ACE_COMMIT_WINDOW * 60.0)])
	t.eq(m_attack, 0, "同距离的量产机**一帧都没有**被强制（节拍只对 ACE 生效）")

	c.queue_free()
	await host.get_tree().physics_frame


# ------------------------------------------------------------ ④-b 真机 · 远距（让位）

## 远距（120 km）时脉冲**照样按时触发**，但**不换态** —— 状态留在 SEEK。
##
## 怎么在不看 `state` 的前提下判断"脉冲触发了"：`_tick_ace_pressure()` 触发时会把
## `_ace_pressure` **归零重新计数**（`_ace_pressure = 0.0` 那一行）。
## 于是"压力计时出现一次下跌"就是脉冲的指纹 —— 比读状态更靠近机制本身。
##
## ⚠️ 这条断的是**当前行为**，而当前行为是**被论证过、有意保留的**（见文件头）。
## 谁要改掉那条让位，必须同时改这里与文件头，并说明为什么"更慢的 ATTACK"更好。
static func _live_far(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	var a := _mk(c, SuitProfile.xi(), 0, Vector3(0.0, 3200.0, 0.0))
	var b := _mk(c, SuitProfile.xi(), 1, Vector3(0.0, 3200.0, -120000.0))
	a.target_override = b
	b.target_override = a
	# 量产机放 233 km 外（x 200 km，而目标在 −120 km）：10 秒里靠不到接战距离。
	# ⚠️ 不要把它钉在目标和 ACE 中间 —— 第一版把 m 与 b 钉到同一个点上，
	# 间距变 0，m 当场进了 ATTACK（"量产机也被强制了"的假红）。
	var m := _mk(c, SuitProfile.messer_m01(), 0, Vector3(200000.0, 3200.0, 0.0))
	m.target_override = b
	await host.get_tree().physics_frame

	# 纯函数级：远距时两个状态取的是**同一个方向** —— 这才是"让位不吃亏"的根据。
	a.set_state(BanditAI.State.SEEK)
	var d_seek := a._direction_for_state(100000.0)
	a.set_state(BanditAI.State.ATTACK)
	var d_attack := a._direction_for_state(100000.0)
	t.near(d_seek.dot(d_attack), 1.0, 0.0001,
		"远距时 SEEK 与 ATTACK 的方向**完全一致**（都走光束提前量点）")

	a.set_state(BanditAI.State.SEEK)
	a._ace_pressure = 0.0
	var prev: float = 0.0
	var resets := 0
	var reset_frame := -1
	var commit_at_reset := 0.0
	var states: Array[int] = []
	var m_attack := false
	var frames := int((BanditAI.ACE_ATTACK_PERIOD + 1.0) * 60.0)
	for i in frames:
		await host.get_tree().physics_frame
		var now: float = a._ace_pressure
		if now < prev - 0.001:
			resets += 1
			if reset_frame < 0:
				reset_frame = i
				commit_at_reset = a._ace_commit
		prev = now
		if not states.has(a.state):
			states.append(a.state)
		if m.state == BanditAI.State.ATTACK:
			m_attack = true

	t.eq(resets, 1, "一个周期里强制脉冲**恰好触发一次**（第 %d 帧）" % reset_frame)
	t.gt(commit_at_reset, 0.0,
		"触发那一刻**武装了窗口**（`_ace_commit` = " + str(snappedf(commit_at_reset, 0.01)) + "）")
	t.eq(states.size(), 1, "整个观察窗里状态**一个都没变过**（远距只触发、不换态）")
	t.eq(a.state, BanditAI.State.SEEK, "留在 SEEK —— 让位给更快的那一支（有意，见文件头）")
	t.ok(not m_attack, "同一时间窗内量产机**一次都没**被强制（节拍只对 ACE 生效）")

	c.queue_free()
	await host.get_tree().physics_frame


# ------------------------------------------------------------ 夹具

static func _mk(parent: Node3D, p: SuitProfile, team: int, pos: Vector3) -> BanditAI:
	var fb := BanditAI.new()
	fb.team = team
	fb.profile = p
	fb.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	fb.projectile_container = parent
	parent.add_child(fb)
	fb.global_position = pos
	fb.fm.speed = 400.0
	return fb


static func _code(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var out: Array[String] = []
	for line in f.get_as_text().split("\n"):
		var s := str(line)
		if s.strip_edges().begins_with("#"):
			continue
		out.append(_strip_inline_comment(s))
	return "\n".join(out)


## 去掉行尾注释（`#` 落在字符串里的时候不算注释）—— 内外靠**引号计数**判断。
## 与 `suite_ui_style` 里同名函数同一套做法（那边是 UI 风格闸门用的）。
static func _strip_inline_comment(line: String) -> String:
	var quotes := 0
	for i in line.length():
		var ch := line[i]
		if ch == "\"" or ch == "'":
			quotes += 1
		elif ch == "#" and quotes % 2 == 0:
			return line.substr(0, i)
	return line
