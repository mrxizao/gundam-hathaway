class_name EndlessScript
extends RefCounted

const MODE_TITLE := "无限激化模拟"
## ═══════════════════════════════════════════════════════════════════════════
## ★63-24「无限强化演习」—— 波次编排 + 品质抽取 + 奖励轮判定
##
## 设计真源：`DESIGN-2026-10-08-无限强化演习.md` §6 / §7 / §8 / §12
##
## ## 为什么整份都是 `static` 纯函数
##
## 本工程的无头判据靠"**纯函数 + 可注入 roll / rng**"做到**可复现**
## （先例：`intro_playlist.gd` 的 `pick_index(roll)`、`audio_director.gd` 的 `shuffle_with`）。
## 抽取逻辑**必须**照这个形状写，否则判据只能靠"多跑几次看看"——
## 那是本工程反复吃亏的那种"记录的条件 ≠ 实际发生的条件"。
##
## ## 三个"轮"（§2.2，一个字都不能混）
##   波次轮（Wave）        战斗段，清空才进下一段
##   间歇轮（Intermission） 战斗段之间的三选一窗口，基础 10 s
##   奖励轮（Bonus）        间歇轮的**特殊形态**：品质强制完美、可选张数 > 1
##
## ## 难度的唯一来源是"两个无界相乘"（§16）
##   波次无界（每 5 min 每波还要 +1 架）× 卡可**无限叠加**（R15）
##   ⇒ 所以平衡全部**外置成常量**（本节），编排做成纯函数（可直测），
##     副作用限制在"玩家那一份 profile 实例"里（可回滚）。

## 局内阶段（§4.1）。`CLEARING` 不是装饰态：它承担"最后一架刚炸、
## 但掉落/特效还没收尾"的那段时间 —— 没有它，间歇轮 UI 会在爆炸特效里弹出来。
enum Phase { IDLE, WAVE, CLEARING, INTERMISSION, BONUS, OVER }

# ───────────────────────── 波次（§6.1 / §8） ─────────────────────────

## 小波台数基数。
const WAVE_MINOR_BASE := 2
## 小波台数**软上限**（Q11：0 = 永不封顶）。超过后不再加数量。
const WAVE_MINOR_MAX := 16
## 每 N 波一个强敌波（S1 拍板：5）。
const WAVE_ACE_EVERY := 5
## 本波清空后的收尾过渡（秒）。
const CLEARING_SECS := 1.2

# ─────────────── ★ 敌人强度爬升（**单轴：局内时间**，2026-10-08 拍板） ───────────────

## 每 5 分钟一档。
const ENEMY_STEP_SECS := 300.0
## 每档、每波多刷 1 个。
const ENEMY_ADD_PER_STEP := 1
## 每档伤害 +10%。
const ENEMY_DMG_PER_STEP := 0.10
## Q9 拍板：**乘算** `1.1^n`（加算配玩家的线性血量 ⇒ 永远不崩 ⇒ 无限模式没有终局）。
const ENEMY_DMG_COMPOUND := true
## Q10 拍板：**只涨伤害，耐久不动**。一起涨的话 20 min 后敌人耐久 ×1.46
## ⇒ 终局变成"打不动"而不是"被打死"。
const ENEMY_HULL_ALSO := false

# ───────────────────────── 间歇轮 / 奖励轮（§7 / §6.2） ─────────────────────────

## 间歇轮基础时长（用户逐字：基础为 10 s）。
const INTERMISSION_BASE := 10.0
## 奖励轮可选 2 张的局内时间门槛（15 min）。
const BONUS_PICKS_2_AT := 900.0
## 奖励轮可选 3 张的局内时间门槛（20 min）。
const BONUS_PICKS_3_AT := 1200.0

# ═══════════════════════════ 波次阵容 §6.1 ═══════════════════════════

## 小波次的敌机池（**只出量产机**，R3）。
static func minor_pool() -> Array[int]:
	return [SuitProfile.Id.GUSTAV00, SuitProfile.Id.MESSER_M01,
		SuitProfile.Id.MESSER_CMD, SuitProfile.Id.MESSER_F01]


## 强敌波的敌机池（**只出 ACE**，R4）。两个池**交集为空**是判据。
static func ace_pool() -> Array[int]:
	return [SuitProfile.Id.XI, SuitProfile.Id.XI_FINAL, SuitProfile.Id.REGZ_CUSTOM, SuitProfile.Id.PENELOPE, SuitProfile.Id.ARIZEUS]


## 第 n 波是不是强敌波。`n` 从 1 开始计。
static func is_ace_wave(n: int) -> bool:
	return n > 0 and n % WAVE_ACE_EVERY == 0


## 小波台数：基数 + 波次项 + **时间档项**（§6.4.2）。
static func minor_count(n: int, t: float) -> int:
	var c := WAVE_MINOR_BASE + int(n / 3) + enemy_step(t) * ENEMY_ADD_PER_STEP
	if WAVE_MINOR_MAX > 0:
		c = mini(c, WAVE_MINOR_MAX)
	return maxi(c, 1)


## 强敌波台数：ACE 的基数远低于小波，但同样吃时间档（每两档才 +1）。
static func ace_count(n: int, t: float) -> int:
	var c := 1 + int(n / 10) + int(enemy_step(t) / 2)
	if WAVE_MINOR_MAX > 0:
		c = mini(c, WAVE_MINOR_MAX)
	return maxi(c, 1)


## 第 n 波、局内时间 t 时应该刷几架（波型分派）。
static func wave_count_of(n: int, t: float) -> int:
	return ace_count(n, t) if is_ace_wave(n) else minor_count(n, t)


## 第 n 波该刷哪些机体（`count` 架，逐架从对应池里随机取）。
## ⚠️ **古斯塔夫必须走 `by_id()` 的武装版**（`suit_profile.gd:2781`）——
##    选错会退化成靶机版（`rifle_count = 0`）：敌人**一枪不放**且**不报错**，
##    HUD 还会显示"（靶机）"。这是静默失败，§13 有 `WAVE_GUSTAV` 盯着。
static func wave_suits(n: int, t: float, rng: RandomNumberGenerator) -> Array[int]:
	var pool := ace_pool() if is_ace_wave(n) else minor_pool()
	var count := wave_count_of(n, t)
	var out: Array[int] = []
	for i in count:
		out.append(pool[rng.randi_range(0, pool.size() - 1)])
	return out


# ═══════════════════════════ 敌人强度 §6.4 ═══════════════════════════

## 时间档号：`t < 300 ⇒ 0`（无加成）。**t 必须是"演习总时长"（含间歇轮）**，
## 不是 `Game.elapsed` —— 后者只在 `Phase.FIGHT` 累加，用它算档位会让
## "在间歇轮里慢慢看卡"变成对自己有利（拖延 ⇒ 档位涨得慢 ⇒ 敌人更弱）。
static func enemy_step(t: float) -> int:
	return int(floor(maxf(t, 0.0) / ENEMY_STEP_SECS))


## 敌人伤害倍率。
static func enemy_damage_mult(t: float) -> float:
	var n := enemy_step(t)
	if ENEMY_DMG_COMPOUND:
		return pow(1.0 + ENEMY_DMG_PER_STEP, float(n))
	return 1.0 + ENEMY_DMG_PER_STEP * float(n)


## 敌人耐久倍率。Q10 = 只涨伤害 ⇒ 恒 1.0。
static func enemy_hull_mult(t: float) -> float:
	return enemy_damage_mult(t) if ENEMY_HULL_ALSO else 1.0


## 本模式乘进 `BanditAI.reinforce` 的那一个系数（**唯一新增**，见 §6.4.3）。
## ⚠️ 非演习模式恒为 `1.0` ⇒ 所有既有难度套件的读数**逐位不变**（§13 `NO_TOUCH_OTHERS`）。
static func enemy_reinforce(t: float) -> float:
	return enemy_damage_mult(t)


# ═══════════════════════════ 间歇轮 / 奖励轮 §6.2 §7 ═══════════════════════════

## 奖励轮可选张数（按**局内总时长**分档，R10）。
static func bonus_picks(elapsed: float) -> int:
	if elapsed >= BONUS_PICKS_3_AT:
		return 3
	if elapsed >= BONUS_PICKS_2_AT:
		return 2
	return 1


## 第 n 波清空后是不是奖励轮（**挂在强敌波之后**，S2 拍板）。
## ⇒ 与 `is_ace_wave` 同周期（每 5 波），玩家能**预测**下一次奖励轮。
static func is_bonus_wave(n: int) -> bool:
	return is_ace_wave(n)


## 本轮该抽的品质：奖励轮**强制完美**，跳过抽取（§2.2「先判奖励轮，再抽品质」）。
static func tier_for(n: int, roll: float, has_radical: bool) -> int:
	if is_bonus_wave(n):
		return UpgradeCard.Tier.PERFECT
	return pick_tier(roll, has_radical)


# ═══════════════════════ 间歇轮的推进（§7 · 读法 A「耗时回补」）═══════════════════════
#
# 这一节全是**纯函数**，理由只有一个：`Main._tick_endless()` 的间歇分支就是它们
# （**不是它们的副本**）—— 于是"倒计时到底怎么走"能在无头里逐条喂边界值钉死，
# 不必起真场景。判据在 `suite_endless` 的 `INTERMISSION` 分节。

## 清空第 `cleared_wave` 波之后进哪一轮（§4.1 / §6.2）。
##
## 奖励轮**挂在强敌波之后**（S2 拍板）⇒ 与 `is_ace_wave()` 同周期、玩家**能预测**。
static func round_phase(cleared_wave: int) -> int:
	return Phase.BONUS if is_bonus_wave(cleared_wave) else Phase.INTERMISSION


## 这一轮要塞进几张（R10）：普通轮恒 1；奖励轮按**局内总时长**分档（1 / 2 / 3）。
##
## ⚠️ `elapsed` 必须是 `Game.endless_elapsed`（含间歇轮连续走），
## 不是 `Game.elapsed` —— 后者只在 `Phase.FIGHT` 累加（见 §6.2 的警告）。
static func round_picks(cleared_wave: int, elapsed: float) -> int:
	return bonus_picks(elapsed) if is_bonus_wave(cleared_wave) else 1


## 操作宽限（秒）：**松手之后倒计时再等这么久**才恢复递减（§7.2 的边界表需要它）。
##
## ⚠️⚠️ 为什么必须有它，而不是"动过就永久暂停"：
## 那样一来，玩家按一次 Tab 之后走开 ⇒ 倒计时永远不走 ⇒ **超时自动选也永不触发**
## ⇒ **这一局直接卡死在间歇轮里**（而 §7.2 那两条边界 ——"一直不动 ⇒ 超时自动选"
## 与"一直动手不选 ⇒ 不设上限"—— 会退化成同一句话，等于其中一条从没被实现）。
##
## ⚠️ 为什么不是 0：按键是**离散事件**，两帧之间必然"没按"。
## 取 0 就等于倒计时永远在走，"操作时暂停"这条规则等于没写。
const OPERATE_GRACE := 0.6


## 倒计时**一步**（`tick_remaining` 是这一行的"纯减法"版，单独留着好喂边界值）。
##
## `operating = true` ⇒ **暂停**，`remaining` **原样**返回。
## ⇒ 绝不出现"我正在看卡，时间到了被强制关掉"。
##
## ⚠️ **不设操作时长上限**（§7.2 的边界表第 2 行）：拖时间只延长"这一轮"，
## 而奖励轮的门槛（`bonus_picks`）用的是**连续走的总时长**
##（`Game.endless_elapsed` 在间歇轮里照走）⇒ 拖延**不会**让玩家更容易拿 2/3 张。
## 这条是"把捷径堵死在机制层"，而不是"给倒计时加个上限"那种能被钻的做法。
static func tick_remaining(remaining: float, delta: float, operating: bool) -> float:
	if operating:
		return remaining
	return maxf(remaining - delta, 0.0)


## 选定一张之后，把"这一段操作**暂停掉**的秒数"**加回**剩余时间（§7.2）。
##
## 奖励轮要选 2/3 张 ⇒ **每选一张单独回补一次**（调用方每选一张就把 `secs` 清零重记）。
static func refund_time(remaining: float, operated_secs: float) -> float:
	return remaining + maxf(operated_secs, 0.0)


## 间歇轮**每帧推进** —— `Main._tick_endless_round()` 调的就是它（**不是它的副本**）。
##
## 入参：
##   `left`   剩余秒数 ｜ `delta` 帧长 ｜ `pressed` 这一帧有没有按键
##   `secs`   这一段已经**暂停掉**的累计秒数（选定后回补的量）
##   `idle`   距**上一次按键**过了多久 ｜ `focus` 焦点 ｜ `hand_size` 手牌张数
##
## 返回 `{left, expired, auto, secs, idle, operating}`：
##   `auto` 到点该自动选的下标（−1 = 不自动选），取**当前焦点**那一张
##   （§7.2 边界表第 1 行：**不惩罚、不阻塞** —— 玩家一直不动也保证流程一定前进）。
##
## ⚠️ `operating` 的判据是 `idle < OPERATE_GRACE`（**不是**"这一帧按了没"）：
## 按键是离散的，两帧之间必然"没按"。理由见 `OPERATE_GRACE` 的头注。
static func intermission_step(left: float, delta: float, pressed: bool,
		secs: float, idle: float, focus: int, hand_size: int) -> Dictionary:
	var new_idle := 0.0 if pressed else maxf(idle, 0.0) + delta
	var operating := new_idle < OPERATE_GRACE
	var new_secs := maxf(secs, 0.0) + (delta if operating else 0.0)
	var new_left := tick_remaining(left, delta, operating)
	var expired := new_left <= 0.0
	return {
		"left": new_left,
		"expired": expired,
		"auto": clampi(focus, 0, maxi(hand_size - 1, 0)) if expired else -1,
		"secs": new_secs,
		"idle": new_idle,
		"operating": operating,
	}


## 焦点在 `hand_size` 张里循环（`step` 取 ±1；越界回绕）。
##
## ⚠️ 用 `posmod` 而不是 `clampi`：这一排只有 3 张，"到头停住"在 3 张上
## 等于"按两下就没反应了"，玩家会以为按键坏了。
## 而 `hand_size <= 0`（不应该发生）⇒ 返回 0，不返回 −1（避免调用方拿到负下标）。
static func cycle_focus(focus: int, hand_size: int, step: int) -> int:
	if hand_size <= 0:
		return 0
	return posmod(focus + step, hand_size)


## 这一轮**是不是该收了**（选满了要的张数，或手牌空了）。
##
## 手牌空这一条是兜底：`draw_hand()` 的 Q15 降级链保证"绝不发空卡"，
## 但真出现"不足 `want` 张"时也必须能收轮 —— 卡在间歇轮里 = 这一局再也走不动。
static func round_done(got: int, want: int, hand_left: int) -> bool:
	return got >= want or hand_left <= 0


# ═══════════════════════════ 品质抽取 §6.3 ═══════════════════════════

## **纯函数、可注入 roll**：把 `[0,1)` 映射到品质。
##
## 权重（普通间歇轮）`30 / 50 / 10 / 10`，区间：
##   `[0,.30) BASIC` · `[.30,.80) ADVANCED` · `[.80,.90) PERFECT` · `[.90,1) RADICAL`
##
## ★ `has_radical = true`（玩家**已持有**一张激进）⇒ 权重回退成 `30 / 60 / 10`（**Q17**）：
## 那 10% **原路还给 ADVANCED**，**不污染"完美恒 10%"这个用户点位**。
## ⇒ 判据好写：`pick_tier(0.85, false)` → PERFECT，`pick_tier(0.85, true)` → ADVANCED ——
##    **同一个 roll、只翻一个入参，结果必须不同**。
##
## ⚠️ 用**整数权重累加**而不是浮点累加：`0.3 + 0.5 = 0.7999999...` 这类浮点误差
## 会让 `0.799 / 0.80` 这一对边界不稳定。乘 100 取整后逐档比较，边界是确定的。
static func pick_tier(roll: float, has_radical: bool) -> int:
	var w: Dictionary = UpgradeCard.TIER_WEIGHTS_NO_RADICAL if has_radical \
		else UpgradeCard.TIER_WEIGHTS
	var r := int(floor(clampf(roll, 0.0, 0.999999) * 100.0))
	var acc := 0
	for tier in [UpgradeCard.Tier.BASIC, UpgradeCard.Tier.ADVANCED,
			UpgradeCard.Tier.PERFECT, UpgradeCard.Tier.RADICAL]:
		if not w.has(tier):
			continue
		acc += int(w[tier])
		if r < acc:
			return tier
	return UpgradeCard.Tier.PERFECT


## 权重表之和必须是 100（§13 `品质抽取`）。
static func weights_sum(has_radical: bool) -> int:
	var w: Dictionary = UpgradeCard.TIER_WEIGHTS_NO_RADICAL if has_radical \
		else UpgradeCard.TIER_WEIGHTS
	var s := 0
	for k in w:
		s += int(w[k])
	return s


# ═══════════════════════════ 抽一手（§12 draw_hand） ═══════════════════════════

## 玩家是否**已持有**激进（**不是"曾出现"** —— §5.10.2 第 4 条 / R22）。
static func player_has_radical(owned: Array) -> bool:
	for c in owned:
		if c is UpgradeCard and (c as UpgradeCard).tier == UpgradeCard.Tier.RADICAL:
			return true
	return false


## 抽 `count` 张卡（默认三选一）。
##
## 规则（R5）：**同一品质 · 不同类型**。★ **过滤发生在"抽"之前**，不是"抽到了再换"——
## 否则会出现"三张卡里有一张是空的"（§5.9.5 坑 1）。
##
## 准入两层：
##   ① **能力谓词**（§5.9.5）：白刃卡要 `has_saber`、重炮卡要 `cannon_enabled`；
##   ② **同一数值词条至多 `SAME_ENTRY_CAP` 份**（R15 保留的唯一软约束）。
##
## Q15 降级顺序（**绝不发空卡**）：① 正路（5 类取 3，类型互异）
##   → ② 允许同类型重复 → ③ 允许复用一张已持有的卡。
static func draw_hand(tier: int, rng: RandomNumberGenerator, profile: SuitProfile,
		owned: Array = [], count: int = 3) -> Array[UpgradeCard]:
	var out: Array[UpgradeCard] = []
	if rng == null:
		rng = RandomNumberGenerator.new()
	# 已持有份数（按词条 id 计数）
	var have := {}
	for c in owned:
		if c is UpgradeCard:
			var cid := (c as UpgradeCard).id
			have[cid] = int(have.get(cid, 0)) + 1
	# 类型顺序随机 ⇒ 每次"哪三类入选"不同
	var types: Array[int] = []
	for t in UpgradeCard.TYPE_COUNT:
		types.append(t)
	_shuffle_i(types, rng)
	var used := {}
	# ① 正路
	for t in types:
		if out.size() >= count:
			break
		var c := _pick_one(t, tier, rng, profile, have, used)
		if c != null:
			out.append(c)
			used[c.id] = true
	# ② Q15 降级一：允许同类型重复
	if out.size() < count:
		var rest: Array[UpgradeCard] = []
		for t in UpgradeCard.TYPE_COUNT:
			for c in UpgradeCard.pool_of(t, tier):
				if UpgradeCard.viable_for(c, profile) and not used.has(c.id) \
						and int(have.get(c.id, 0)) < UpgradeCard.SAME_ENTRY_CAP:
					rest.append(c)
		_shuffle_c(rest, rng)
		for c in rest:
			if out.size() >= count:
				break
			out.append(c)
			used[c.id] = true
	# ③ Q15 降级二：放宽"至多 2 份"，允许复用已持有
	if out.size() < count:
		for t in UpgradeCard.TYPE_COUNT:
			for c in UpgradeCard.pool_of(t, tier):
				if out.size() >= count:
					break
				if UpgradeCard.viable_for(c, profile) and not used.has(c.id):
					out.append(c)
					used[c.id] = true
	return out


## 抽一手的 **id**。
##
## `Game.endless_hand` 与 `Game.endless_owned` 是**同一口径（id）**，
## 而不是一手 `UpgradeCard` 对象：卡是可变的真源之外的东西，
## 存 id 才不会有"两份对象、改了一份"的问题（菜单那一侧同理）。
## 渲染时用 `UpgradeCard.by_id(id, Game.endless_hand_tier)` 取回 —— `draw_hand()`
## 只从**同一档**的池里取（① 正路 ② 同类型重复 ③ 复用已持有，都不跨档）
## ⇒ 按那一档一定找得回来。
static func draw_hand_ids(tier: int, rng: RandomNumberGenerator, profile: SuitProfile,
		owned: Array = [], count: int = 3) -> Array[String]:
	var out: Array[String] = []
	for c in draw_hand(tier, rng, profile, owned, count):
		out.append(c.id)
	return out


static func _pick_one(t: int, tier: int, rng: RandomNumberGenerator, profile: SuitProfile,
		have: Dictionary, used: Dictionary) -> UpgradeCard:
	var cand: Array[UpgradeCard] = []
	for c in UpgradeCard.pool_of(t, tier):
		if not UpgradeCard.viable_for(c, profile):
			continue
		if used.has(c.id):
			continue
		if int(have.get(c.id, 0)) >= UpgradeCard.SAME_ENTRY_CAP:
			continue
		cand.append(c)
	if cand.is_empty():
		return null
	return cand[rng.randi_range(0, cand.size() - 1)]


static func _shuffle_i(a: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp


static func _shuffle_c(a: Array[UpgradeCard], rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp


# ═══════════════════════════ 施加（§5.5 幂等） ═══════════════════════════

## 把 `cards` 逐张施加到 `profile`。
##
## ⚠️ **幂等的前提是"从出厂值重算"，不是"增量施加"**：调用方必须先拿一份**出厂快照**、
## 还原 profile，再调本函数。若把"拿卡"实现成"当场把当前字段乘一遍"，
## 同一张卡拿到两次会乘两次、且**无法回滚**（一局可能几十张卡）。
## 判据：**同一张卡施加 1 次与 3 次，字段必须一致**（§13 `IDEMPOTENT`）。
static func apply_cards(profile: SuitProfile, cards: Array) -> void:
	if profile == null:
		return
	for c in cards:
		if c is UpgradeCard:
			var cb: Callable = (c as UpgradeCard).apply
			if cb.is_valid():
				cb.call(profile)


## ⚠️ **卡的落点全集** —— 「还原出厂值」时逐字段回写用的名单。
##
## 为什么必须显式枚举（而不是 `get_property_list()` 全遍历）：本工程有一批字段
## **不进卡池但也不该被重置**（型号 / 模型路径 / 形态表 …），全遍历会把它们一起搅了。
## 每加一条新落点的卡，**必须**在这里补一个字段名 —— 漏了的表现是
## 「幂等判据绿着、但那张卡在重算路径里被漏掉了一半」，属于静默失败。
const MUTABLE_FIELDS: Array[StringName] = [
	# 火力
	&"rifle_damage", &"rifle_interval", &"rifle_magazine", &"rifle_reload_time",
	&"rifle_count", &"funnel_damage", &"funnel_interval", &"funnel_count",
	&"funnel_per_shot", &"vulcan_interval", &"grenade_damage",
	# 装甲（⚠️ 裸字段，见 `upgrade_card.gd` 文件头规矩 2）
	&"_hull_hp", &"_ifield_hp", &"shield_reduction", &"turn_scale",
	&"jet_seconds", &"jet_recharge",
	&"repair_packs", &"repair_fraction", &"repair_time",
	# 机制
	&"max_locks", &"has_missiles", &"has_saber",
	# 白刃
	&"saber_damage", &"saber_interval", &"saber_hit_range", &"saber_dash_speed",
	&"player_saber_magnet", &"player_saber_dash_time",
	&"saber_sweep_radius", &"saber_min_closing", &"saber_miss_grace", &"clash_cooldown",
	# 重炮
	&"cannon_charge_time", &"cannon_dps", &"cannon_duration", &"cannon_cooldown",
	&"cannon_overheat_reload", &"beam_cannon_radius",
]


## **幂等的施加入口**：先把 `profile` 还原成出厂值，再逐张施加 `cards`。
##
## `factory` 必须是**同一机体**的出厂实例（`SuitProfile.by_id(id)` 每次 `new` 一份，
## 所以随手再取一份就是干净的出厂值）。
##
## ⇒ 于是"拿一张新卡" = "把本局卡列表加一项，然后**整批重算**"，
##    而不是"当场把当前字段再乘一遍"。后者同一张卡拿两次会乘两次、**且无法回滚**
##    （本模式一局可能几十张卡）。
## ⇒ 判据：**同一批卡连续施加 1 次与 3 次，字段必须逐位一致**（§13 `IDEMPOTENT`）。
static func apply_run(profile: SuitProfile, factory: SuitProfile, cards: Array) -> void:
	if profile == null or factory == null:
		return
	for f in MUTABLE_FIELDS:
		profile.set(f, factory.get(f))
	apply_cards(profile, cards)


## 字段快照（判据用）。只取 `MUTABLE_FIELDS` 这一批。
static func snapshot(p: SuitProfile) -> Dictionary:
	var d := {}
	if p == null:
		return d
	for f in MUTABLE_FIELDS:
		d[str(f)] = p.get(f)
	return d
