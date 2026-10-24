class_name BanditAI
extends FlightBody
const BossTactics:=preload("res://scripts/ai/super_boss_tactics.gd")
var _boss:=BossTactics.new()
## 敌机 AI：SEEK / ATTACK / EVADE / EXTEND 四态机 + 纯追踪转向控制器。
##
## 转向控制器的核心在 `_steer()`：把"想去哪个方向"翻译成 (pitch, roll)。
## 关键是用**机体坐标系下的 atan2(y, −z) 与 atan2(x, −z)**，而不是世界角度——
## 这样"目标在正后方"会自然得出"滚转到最大 + 拉满杆"，不需要给每种情况写特例，
## 而且滚转与俯仰天然协调（压坡度转弯），看起来像在开飞机。
##
## 难度（Difficulty）同时决定四件事：
##   1. 速度上限（柯西基准 × 1.0 / 1.3 / 1.5）
##   2. 出伤倍率（× 1.0 / 1.1 / 1.3）
##   3. 反应速度与射击精度（skill）
##   4. **丢枪时机**（柯西专属，见 _check_discard）

enum State { SEEK, ATTACK, EVADE, EXTEND }

const PITCH_REF := 0.55          ## 俯仰满杆对应的角度误差（rad）
const ROLL_REF := 0.62           ## 滚转满杆对应的横向误差（rad）

# ---- 避地 ----
#
# 之前 AI 会一头扎进海里自爆，三个原因叠在一起（用户实测报的）：
#   1. `SAFE_ALTITUDE` 只有 520 m。困难难度敌机 630 m/s，俯仰转弯半径就有 **360 m**，
#      520 m 的余量根本不够把机头从俯冲里拉回来；
#   2. 避地只看**当前高度**，不看"按现在这个下沉率再过两秒会在哪"。
#      等高度真的低于安全线时，动量已经把它压进海里了；
#   3. EVADE 状态**主动俯冲**（`down` 的 y 分量是 −0.55）去换速度，而且是加力状态，
#      于是"规避"这个动作本身就在把它往海里按。
#
# 现在改成：预判 + 软硬两级 + 低空禁止俯冲。
## 按当前速度矢量外推出的高度低于它，就开始持续上仰。
const SAFE_ALTITUDE := 1600.0
## 低于它（或预判会低于它）进入**紧急拉升**，压过状态机、停火、收油门。
const CRITICAL_ALTITUDE := 700.0
## 外推多少秒。2.6 s 覆盖了"机头已抬起但速度矢量还在往下冲"的那段滞后。
const PULL_UP_LOOKAHEAD := 2.6

# ---- 避地 · 地形探头（批 16）----
#
# 上面那套 SAFE/CRITICAL 只看**海平面**（y=0）外推 —— 而地图是真实起伏地形
#（沙丘 / 峡谷 / 城区），山脊上的机 y 很高、离地可能只有几十米，海平面外推
# 根本看不见山。玩家侧的防撞地（FlightAssist）从来都是**射线探头**；
# 这一批把同一套思路搬进 AI：机头前向 + 前下两条射线（只打 WORLD 层），
# 把"照这样飞多久撞上地形"折算成秒，喂给三处：
#   ① < TERRAIN_PULL_TIME  → 紧急拉升（与 `_needs_pull_up()` 同级，压过状态机）；
#   ② < TERRAIN_AVOID_TIME → 软性上仰（揉进期望方向，见 `_blend_safety`）；
#   ③ 军刀突进中 < SABER_ABORT_TERRAIN_TIME → 直接掐断（突进里转向无效，
#      唯一的活路就是 abort，见 `_think` 顶部那条注释）。
## 前向探头多少秒之内会撞上地形就紧急拉升。
const TERRAIN_PULL_TIME := 2.0
## 多少秒之内会撞上就开始软性上仰（不夺杆，只揉方向）。
const TERRAIN_AVOID_TIME := 3.0
## 前下探头的俯角（与 FlightAssist.PROBE_DOWN 同一个量：探的是前方地面）。
const TERRAIN_PROBE_DOWN := 0.55
## 军刀突进中前向探头多少秒之内看到地形就掐断突进。
const SABER_ABORT_TERRAIN_TIME := 1.2
## 军刀突进的门禁高度：自己低于它不冲、目标低于它不冲。
## 1150 m/s 冲 1.5 s 是 1.7 km 的直线，没有任何避地余地。
const SABER_MIN_OWN_ALTITUDE := 900.0
const SABER_MIN_TARGET_ALTITUDE := 1100.0
## 突进途中掉到这个高度就直接掐断突进。
const SABER_ABORT_ALTITUDE := 650.0
## 竞技场半径直接引用 WorldBuilder 的常量 —— 两边各写一个数迟早会对不上，
## 表现是 AI 把玩家往场地外推、或者 AI 自己贴着看不见的墙来回蹭。
const ARENA_RADIUS := WorldBuilder.ARENA_RADIUS

@export var skill := 0.72
@export var engage_range := 2800.0
@export var gun_range := 950.0
@export var gun_cone_deg := 5.5
@export var beam_range := 2400.0
@export var beam_cone_deg := 9.0
@export var missile_range := 4200.0
@export var break_range := 240.0
@export var saber_range := 520.0

## 进攻欲望（用户要求："让敌方 AI 进攻欲望再强 30%"）。
##
## ## 为什么是一个常量而不是一个"欲望变量"
## 这台 AI **没有**"进攻欲望"这个量 —— 它就是"一场战斗里处于 `ATTACK` 的时间占比"。
## 所以先把这个占比做成**可测量**的（`tools/probe_aggression.tscn`），再调参去够它。
##
## ## ⚠️ 为什么是 1.14 而不是 1.30
## 第一版按字面把下面这一组阀值**全乘了 1.30**，实测严重过头：
##
## | 旋钮 | ATTACK 占比（AI 对 AI，3 态势 × 60 s × 3 难度，64800 帧） |
## |---|---|
## | ×1.00（原值） | 26.4% |
## | ×1.30（"字面乘 1.3"） | **46.3%（+75%）** ← 过头 |
## | ×1.12 | 33.1%（+25%） |
## | **×1.14（现在的值）** | **34.4%（+30.3%）** ✅ |
##
## 原因是状态机**非线性**：×1.30 涨出来的份额几乎全部来自 SEEK（37.0% → 19.5%），
## 因为接战距离一放大，SEEK 那一段直接变成了 ATTACK。
## 于是"旋钮拧 30%"和"欲望强 30%"根本不是一回事 —— 用户要的是后者。
##
## 分难度落地（×1.14）：简单 30.6% → **39.1%**、中等 24.8% → **32.7%**、
## 困难 23.7% → **31.4%**；平均交战距离 2142/2543/2606 m → 1966/2267/2335 m。
##
## ## 这张表是**旋钮**的落点（数值按 skill = 0.72 的中等档算）
##
## | 项 | 落在哪 | 原始行为 | ×1.14 之后 |
## |---|---|---|---|
## | 接战距离 | `engage_dist()` | 2.8 km 内压上去 | 3.19 km 就压上去 |
## | 脱离距离 | `break_dist()` | 贴到 240 m 算冲过头 | 贴到 211 m 才算 |
## | 被威胁后的耐性 | `AGGRESSION / skill` | 被锁定/有导弹 1.39 s 就转防御 | 1.58 s 才转 |
## | 规避时长 | `evade_seconds()` | 躲一次 2.90 s | 2.55 s |
## | 脱离时长 | `extend_seconds()` | 拉开一次 3.13 s | 2.75 s |
##
## ## ⚠️ 刻意**不动**这几项（拧了就不是"欲望"，是别的东西）
## - **射击锥角**（`beam_cone_deg + 4·skill`）、点射节奏、导弹发射概率：
##   那是**准头与射速**。调高它们等于偷偷加强命中率，而不是"更想打"。
## - **`difficulty.lock_*`**：上一轮刚给 AI 加上的"锁定要付钱"（方案 B）。
##   拧松它会把那一轮的平衡整个改掉 —— 那是另一件事，不能夹带。
## - **避地安全线**（`SAFE_ALTITUDE` 等）：与进攻无关；压低它 AI 会扎海。
##
## ## 怎么复测
## `tools/probe_aggression.tscn`（两个真 AI 对打，量 ATTACK 时间占比）。
## 改这个常量之后必须重跑它 —— 旋钮与欲望的换算关系**会随状态机改动而变**。
const AGGRESSION := 1.14

var lock: LockOnSystem
var difficulty: Difficulty = null
var state := State.SEEK

## ★ 轮 57：**演出接管**开关。`true` ⇒ `_think()` 首行直接让路
##（不选目标、不推状态机、不开火），位置与朝向由演出方每帧直接写。
##
## ## 用的地方只有一处
## M04「重力」的开场演出（老板 2026-09-30：「先做佩涅罗佩使用光束大炮攻击柯西运输仓，
## 然后再是玩家操控柯西和佩涅罗佩对决」）。演出期间佩涅罗佩既不该自己决策、
## 也不该顺手把玩家打下来。
##
## ## ⚠️ 为什么是一个布尔，而不是加一个 `State.FROZEN`
## 状态机管的是**怎么打**（`SEEK / ATTACK / EVADE / EXTEND`），而"由谁开车"
## 是更上一层的事：加一个状态就得在四条转移里各判一次"要不要出发"，
## 而那正是漏判的温床。布尔在入口一次性让路 ⇒ **默认 false 时行为逐位不变**。
var scripted := false


## 演出接管开关。**`main` 侧的唯一入口** —— 不直接写字段，理由同
## `ChaseCamera.set_launch_view()`：谁来开、谁来关，要能一眼搜出来。
func set_scripted(on: bool) -> void:
	scripted = on
	if on:
		# 接管那一刻把王牌机的"强制进攻节拍"清零：状态机是停下来了，
		# 但那个节拍是**累计量**，不清的话演出结束一放开 AI 就立刻强冲一次。
		_ace_pressure = 0.0
		_ace_commit = 0.0

# 困难敌机独立技能节拍；不改变玩家武器与普通难度。
const HARD_DASH_CD := 5.0
const HARD_CANNON_CD := 40.0
const HARD_SALVO_CD := 190.0
const HARD_SALVO_CHANCE := 0.08
const HARD_SALVO_ROLL_INTERVAL := 5.0
var _hard_dash_cd := 0.0
var _hard_cannon_cd := 0.0
var _hard_salvo_cd := 0.0
var _hard_salvo_roll := HARD_SALVO_ROLL_INTERVAL
var _hard_dash_left := 0.0
var _hard_dash_dir := Vector3.ZERO
var _hard_salvo_left := 0
var _hard_salvo_gap := 0.0
var _hard_salvo_target: FlightBody
var _hard_rng := RandomNumberGenerator.new()

var _state_time := 0.0
var _target: FlightBody
var _burst_timer := 0.0
var _burst_hold := false
var _flare_timer := 0.0
## profile 的**原始**耐久（`_apply_difficulty()` 的困难强化是乘在它上面的）。
##
## ⚠️ 存这一份是为了**幂等**：`_apply_difficulty()` 会被调多次（难度变化），
## 直接在 `max_hp` 上连乘会让"切一次难度血翻一倍"。
var _base_hull := 0.0
var _base_ifield := 0.0
var _discard_rule_used: Array[bool] = []
## 形态切换冷却（阿利宙斯）。见 `_drive_form()`。
var _form_timer := 0.0

# ---- 1.2（方案 B）：AI 也要为锁定付钱 ----
#
# 计划书里那句话说得很准："现在的不对称在**操纵精度**" —— AI 的机头太准、
# 锁定又不要钱，于是玩家被咬住就等死。所以这一组改动是往 AI 身上加误差，
# 而不是继续削弱玩家（玩家侧的质量条见 `LockOnSystem`）。
#
# 三件事：
#   1. **反应延迟**（一阶滞后）：AI 瞄的是"多久之前的目标位置"。它同时作用于转向、
#      开火判定与提前量解算 —— 只滞后转向的话会出现"杆是旧的、扳机是新的"，
#      子弹照样弹无虚发，只有航迹看着像人。
#   2. **机头抖动**（慢速正弦）：困难 ±0.5° 几乎不抖，简单 ±3° 足够让它的锁定质量
#      在 0.7~1.0 之间横跳 ——「咬住了也咬不稳」。
#   3. **猎杀规则**（阿利宙斯对残血柯西）：见 `hunt_lock_mult()`。
## AI 瞄准用的"旧位置"（一阶滞后）。
var _lag_pos := Vector3.ZERO
## 机头抖动的相位。
var _noise_phase := 0.0
## 猎杀锁定是否已经播报过（只在**进入**猎杀时报一次）。
var _hunt_announced := false
## 地形探头的最近结果（"照这样飞多久撞上地形"，秒）；INF = 视界内没有地形。
## 每个物理帧在 `_think` 顶部刷新，见 `_probe_terrain()`。
var terrain_time := INF


func _ready() -> void:
	super._ready()
	_hard_rng.randomize()
	if difficulty == null:
		difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	_apply_difficulty()


## 把难度表落到这台机的速度上限、出伤倍率与技能水平上。
##
## 速度只改上限（configure），机体自身的转向系数在 FlightBody._ready 已经乘过，不受影响。
##
## ⚠️ 第十四轮起**不再直接用 `enemy_top_speed()`**：难度倍率只乘在敌机上，
## 会造出"中等难度的佩涅罗佩 737 m/s vs 玩家柯西加力 630 m/s"这种追不上的对手
## （玩家实测"很难追上敌机"）。实战一律走 `enemy_top_speed_capped()`，
## 见 `SuitProfile.ENEMY_SPEED_CEILING_RATIO`。
func _apply_difficulty() -> void:
	# ---- 困难模式的**按玩家机体**补偿（1.2 第二十八轮）----
	#
	# 用户实测：「**困难柯西很难**，难度可以只稍微上调 20%。
	# 剩余的**困难佩涅罗佩和困难阿利宙斯就太简单了**，失去了困难模式的意义」。
	#
	# 所以"困难"对三台机于是**三件不同的事**，统一倍率必然"一台刚好、两台白给"。
	# 系数挂在**玩家选的机体**上（`SuitProfile.hard_enemy_reinforce`），
	# 这里只负责把它乘进去。
	#
	# ⚠️ 拿不到玩家时（`_apply_difficulty()` 早于玩家出生、或测试里 AI 对 AI）
	# **退回 1.0**（不强化）—— 这个方向是安全的：宁可不加难度，
	# 也不要凭空造出一个"玩家还没选机体就已经被加强"的对手。
	#（和 `_player_boost_reference()` 退回柯西是同一个取舍逻辑。）
	var reinforce := 1.0
	if difficulty.level in [Difficulty.Level.HARD,Difficulty.Level.SUPER_HARD]:
		var p := Game.live_player() as FlightBody
		if p != null and p.profile != null:
			reinforce = p.profile.hard_enemy_reinforce
	# ★63-24 无限强化演习的**时间爬升**（设计 §6.4.3）：每 5 分钟这一档的敌人伤害 +10%
	#（乘算 `1.1^n`）。非演习局它**恒为 1.0** ⇒ 所有既有难度套件的读数逐位不变
	#（判据 `NO_TOUCH_OTHERS`）。
	#
	# ⚠️⚠️ 刻意**只乘进 `damage_mult`**，**不并进上面那个 `reinforce`**：
	# 那个变量下面还会拿去算 `max_hp` / `ifield_max`（见本函数后半
	# `max_hp = _base_hull * reinforce * ...`）—— 并进去就变成"演习里敌人的血也一起涨"，
	# 而 Q10 拍的是**只涨伤害**（`EndlessScript.ENEMY_HULL_ALSO = false`）。
	var endless_mult := Game.endless_enemy_reinforce
	var super_ace:=_super_hard() and _is_ace()
	damage_mult = difficulty.damage_mult * reinforce * endless_mult * (difficulty.ace_damage_mult if super_ace else 1.0)
	skill = difficulty.ai_skill
	# 耐久也一起强化。
	#
	# ## ⚠️⚠️ 绝对**不能**在这里把血补满（这是我犯过的严重 bug）
	#
	# 第一版写的是 `hp = max_hp` / `ifield_hp = ifield_max`。
	# 而 `_apply_difficulty()` **不是只在出生时调一次** ——
	# `_drive_form()` 里**每次形态切换成功**都会调它（`bandit_ai.gd` 的
	# "必须重算难度速度"那一段）。于是：
	#
	#   **阿利宙斯每变一次形态 ⇒ 血量与 I 立场全部回满。**
	#
	# 用户的实测报告就是这句话：「**敌方机体的 I 立场护盾和血量都会自动回复，
	# 完全打不掉**」。它表现得像"敌机自带回血"，真因却是**重算难度时顺手把血补满了**。
	#
	# 正确做法：**保留当前的比例**（和 `FlightBody.switch_form(keep_ratio)` 同一个口径）。
	# 出生时 `hp == max_hp` ⇒ 比例 1.0 ⇒ 仍然是满的；中途重算 ⇒ 按比例换算，不白送。
	#
	# ⚠️ 同时 `max_hp` 必须**幂等**：先记一次 profile 原始耐久，之后每次从它算，
	# 否则 `max_hp *= reinforce` 会连乘。
	if _base_hull <= 0.0:
		_base_hull = max_hp
		_base_ifield = ifield_max
	var hull_ratio := hp_ratio()
	var ifield_ratio := ifield_ratio()
	max_hp = _base_hull * reinforce * (difficulty.ace_hull_mult if super_ace else 1.0)
	ifield_max = _base_ifield * reinforce
	hp = clampf(max_hp * hull_ratio, 1.0, max_hp)
	ifield_hp = clampf(ifield_max * ifield_ratio, 0.0, ifield_max)
	_apply_top_speed()
	_discard_rule_used.resize(difficulty.discard_rules.size())
	for i in _discard_rule_used.size():
		_discard_rule_used[i] = false


## ★ 本关专属的敌机速度乘子（轮 63-9 · D1）。**默认 1.0 ⇒ 乘了也等于没乘。**
##
## 存在的理由：敌机极速有一条跨轮次的回归门「≤ 玩家加力 × 0.92」
##（`ENEMY_SPEED_CEILING_RATIO`）。m02 的玩家机是古斯塔夫 00 **武装版**
##（`by_id(GUSTAV00)` ⇒ `gustav00_armed()`，`speed_scale 0.85`），巡航 856.8，
## 而敌机被那条门钉在 1182.384（中等 / 困难）⇒ 不按加力**永远**追不上。
## 削 `messer_m01().speed_scale` 是**全局**的（会撞 27 组合不变量表）⇒ 只能按关削。
##
## ⚠️ **唯一写入点是 `set_enemy_speed_mult()`**：直接改这个字段**不会**重算速度
##（`_apply_top_speed()` 只在难度变化 / 挂板时跑），表现是「本关速度没变」且**不报错**。
var enemy_speed_mult := 1.0


## 设本关速度乘子并**立刻重算**速度上限（`enemy_speed_mult` 的唯一写入点）。
##
## ⚠️ 钳到 ≥ 0.01：0 或负数会让 `fm.configure(0, 0)` 把 accel / brake 全算成 0，
## 敌机会**停在空中**（比「慢」更糟，而且看起来像「AI 坏了」）；负数还会翻向。
func set_enemy_speed_mult(v: float) -> void:
	enemy_speed_mult = maxf(v, 0.01)
	_apply_top_speed()


## 只重算速度上限（不动出伤倍率 / 技能 / 丢枪规则）。
##
## ⚠️ 单独抽出来的原因：**上/下踏板要在不重置"丢枪规则已用"的前提下改速度**。
## 直接再调一次 `_apply_difficulty()` 会把 `_discard_rule_used` 清空 ——
## 那等于让敌机的"血量 ≤50% 丢一次枪"复活一次，是静默的行为改变。
## 分工：**难度变化走 `_apply_difficulty()`，踏板开关走这个**。
func _apply_top_speed() -> void:
	var top := profile.enemy_top_speed_capped(difficulty.speed_mult, _player_boost_reference())
	# ★ 轮 63-9 · D1：本关专属乘子。`1.0` 时是 `x * 1.0` ⇒ **逐位不变**
	#（IEEE754 里 x*1.0 == x，所以那条 27 组合的不变量表一格都不动）。
	top *= enemy_speed_mult
	fm.configure(top, top)
	# ⚠️ **踏板不给最高速加成**（踩过：1.25 倍的最高速当场顶穿
	# "敌机 ≤ 玩家加力 ×0.92"那条第十四轮的回归门）。
	# 它的收益是**油门响应**，见 `FlightPedal.RIDE_THROTTLE_RESPONSE`。
	# `configure()` 会把 accel / ab_accel / brake 按新的 top_speed 重算一遍，
	# 所以这一行**必须在它之后**。
	apply_pedal_flight_bonus()


## 敌机速度天花板的基准：**玩家这台机的加力上限**。
##
## 拿不到玩家时（`_apply_difficulty()` 早于玩家出生、或测试里只有 AI 对 AI）
## 退回**柯西的加力上限** —— 它是三台可选机里最低的那一档，
## 所以"退回"只会让敌机更慢一点，**绝不会造出一个追不上的对手**：
## 这个方向是安全的，反过来（退回佩涅罗佩）就会。
func _player_boost_reference() -> float:
	var p := Game.live_player() as FlightBody
	if p != null and p.profile != null:
		return p.profile.player_boost_speed()
	return SuitProfile.xi().player_boost_speed()


## 强制目标。平时是 null，走 `Game.live_player()`。
##
## 存在的意义有两个：
##   1. 实测战斗时长的探针要"两个 AI 对打"，而 `Game.live_player()` 只有一个玩家位；
##   2. 将来做 2v2 时，僚机需要一个"打谁"的显式入口。
var target_override: FlightBody = null

# ---- 编队跟随（1.2 第二十轮）----
#
# 用户要的编制是"**三个量产机编队（三台飞行踏板 + 六台量产机）+ 一台 ACE**"，
# 而"一个编队 = 一块板上两台"。
#
# ⚠️ **为什么必须有跟随**：两台各自做气动的话，出生时并排、
# 十几秒后就是"一台在前面飞、一台在后面追"，看起来完全不像"站在同一块板上"
# （第十七轮实测登记过这条欠账）。所以被载的那台要**把领机的挂位当目标点**。
#
# ## 怎么跟：在转向层面加权，不是硬写坐标
# 一开始想直接写 `global_position = 领机挂位`（运动学贴合），那会绕过气动 ——
# 表现是它**不吃重力、不受失速影响**，转弯时像贴纸一样滑，而且撞上别人也不会被弹开。
# 所以改成**加权**：离挂位越远，"往挂位飞"的权重越高；
# 在挂位附近权重归零、完全按打斗来（该开火开火、该咬人咬人）。
## 跟随的领机（null = 不是僚机）。
##
## ⚠️ 类型是 **`FlightBody`** 而不是 `BanditAI`：领机**可能是玩家**
## （玩家开量产机时他就占在第一个编队的 0 号位上，见 `BattleFormation.lineup()`）。
## 写成 `BanditAI` 的话"玩家的后座"永远找不到领机 —— 而它**不会报错**，
## 只是那台僚机安静地不跟队，表现是"编队散了一个人"。
var formation_leader: FlightBody = null
## 我在领机的第几个挂位上（0 = 领机自己，1 = 后座）。
var formation_slot := 0
## 超过这个距离就**只管归队**（不再参与打斗），免得一路被拖散。
const FORMATION_BREAK_DIST := 220.0
## 进入这个距离之后跟随权重开始下降（= 到家了，专心打）。
const FORMATION_HOLD_DIST := 55.0


## 把我设成 `leader` 的僚机。
func set_formation(leader: FlightBody, slot: int) -> void:
	formation_leader = leader
	formation_slot = slot


## 我该待在哪儿（世界坐标）。没领机时返回当前位置。
func formation_anchor() -> Vector3:
	var l := formation_leader
	if l == null or not is_instance_valid(l):
		return global_position
	var board := l.pedal_owner()
	if board == null:
		# 领机的板已经爆了 —— 退化成"跟在领机侧后方"，
		# 总比原地不动强（板没了不代表编队立刻解散）。
		return l.global_position + l.global_transform.basis.x * FlightPedal.SLOT_SPREAD_X_M
	return board.slot_world_position(formation_slot)


## 把"归队"揉进想去的方向。
##
## 权重形状：`距离 → 0~1`，在 `FORMATION_HOLD_DIST` 内是 0（专心打），
## 到 `FORMATION_BREAK_DIST` 涨到 1（只管归队），中间线性过渡。
## 这样"打得正欢"和"被甩掉了"两种情况自然分开，不需要再加一个状态机。
func _blend_formation(desired: Vector3) -> Vector3:
	var l := formation_leader
	if l == null or not is_instance_valid(l):
		return desired
	var to_anchor := formation_anchor() - global_position
	var d := to_anchor.length()
	if d < FORMATION_HOLD_DIST or to_anchor.length_squared() < 1.0:
		return desired
	var w := clampf(
		(d - FORMATION_HOLD_DIST) / maxf(FORMATION_BREAK_DIST - FORMATION_HOLD_DIST, 1.0),
		0.0, 1.0)
	# 混合之后**重新归一化**：`_steer()` 期待的是一根方向向量。
	return desired.normalized().lerp(to_anchor.normalized(), w).normalized()


## 挑这一帧要打谁。
##
## ## ⚠️ 这一条修的是一个**严重的阵营 bug**（1.2 第二十三轮）
##
## 原来这里写的是 `_target = Game.live_player()` —— **无条件把玩家当目标**。
## 1v1 时代这没问题（场上就一个敌对目标），但编队战里
## **玩家的 6 台僚机也走这段代码** ⇒ **僚机会掉头打玩家**。
## 用户实测报障：「我测试古斯塔夫的时候会被其他古斯塔夫攻击」——
## 那正是这个：他的僚机是古斯塔夫，而它们把他当成了靶子。
##
## 现在改成"从**敌对阵营**里挑最近的"。
##
## ## 两条设计约束
##
## **① 用 `Game.live_hostiles_of(self)` 而不是自己遍历 `Game.units`** ——
## 阵营判定只有 `is_hostile_to()` 一处真源（它判的是 `team` 不等），
## 重写一遍迟早会和它不一致。
##
## **② 带滞回：当前目标还活着、还是敌人，就继续打它。**
## 每帧无条件重选"最近的"会让 AI 在两个距离相近的目标之间**反复横跳**
##（航迹会抖，而且锁定系统每帧被切来切去）。
## 只有当前目标死了/变成友军/消失时才重新挑。
func _pick_target() -> FlightBody:
	if is_instance_valid(target_override) and not target_override.is_queued_for_deletion():
		return target_override
	if _super_hard():
		var player:=Game.live_player() as FlightBody
		if player!=null and is_hostile_to(player) and global_position.distance_to(player.global_position)>15000.0:return player
	# ---- ① 先算"谁还能打"：**优先挑没人咬的**（1.2 第二十六轮：降低集火强度）----
	#
	# 老板："降低集火强度：在有其他无主目标可以选的情况下，就别选已经有人选过的敌人目标；
	# 如果没有其他敌人目标可以选择了，那么才可以一起集火最近的敌方。"
	#
	# 判据读**队友此刻的 `_target`**（`_claimed_targets()`），不另立登记表：
	# 登记表要维护生命周期（谁死了、谁退场），而 `_target` 本来就每帧重算。
	var foes: Array = []
	for h: Node3D in Game.live_hostiles_of(self):
		var fb := h as FlightBody
		if fb != null and fb != self:
			foes.append(fb)
	if foes.is_empty():
		return null
	var claimed := _claimed_targets()
	var free: Array = []
	for f in foes:
		if not claimed.has(f):
			free.append(f)
	# **全都有人咬了**才允许一起集火（这时才回到"最近的"）
	var pool: Array = free if not free.is_empty() else foes

	# ---- ② ACE 优先咬对面的 ACE（只在**允许的池子里**挑）----
	#
	# 判据读 `SuitProfile.is_ace()`（机体自带属性），不新增"我是 ACE"的状态位 ——
	# 于是"谁在开"完全不影响：玩家自己开 ACE 时，对面的 ACE 也会优先来咬玩家。
	# ⚠️ 顺序是"**先无主、再 ACE 优先**"。反过来的话，ACE 会把队友已经咬住的敌方 ACE
	# 再抢一遍 —— 那恰好就是老板要削的那种集火。
	if _is_ace():
		var ace := _nearest_in(pool, true)
		if ace != null:
			return ace

	# ---- ③ 滞回：当前目标**还在池子里**就不换 ----
	#
	# ⚠️ 滞回**优先于"谁也不许重复"**，这是刻意的：写成"发现别人也在咬就立刻让开"的话，
	# 两台僚机会同时让开、又同时选中下一个、再同时让开 —— 航迹要抖、锁定每帧被切。
	# 现在这套是稳定的：**先到的那台留住目标，后到的那台（本来还没目标）直接挑无主的**。
	var cur := _target
	if cur != null and is_instance_valid(cur) and not cur.is_queued_for_deletion() \
			and cur.is_alive() and cur.is_hostile_to(self) and pool.has(cur):
		return cur
	# ---- ④ 池子里最近的 ----
	return _nearest_in(pool, false)


## 队友**此刻**已经咬住的目标（不含自己）。
##
## ⚠️ 只算"还活着"的：一台僚机刚被打死、`_target` 还指着谁，不该继续占着那个目标。
## ⚠️ 玩家的 `PlayerController` 不是 `BanditAI`（没有 `_target`），`as` 之后是 null，
## 自然被跳过 —— 不需要为它写特例。
func _claimed_targets() -> Array:
	var out: Array = []
	for a: Node3D in Game.live_allies_of(self):
		var mate := a as BanditAI
		if mate == null or mate == self:
			continue
		var t = mate._target
		if t != null and is_instance_valid(t) and not t.is_queued_for_deletion() and t.is_alive():
			out.append(t)
	return out


## 在给定池子里挑最近的（`ace_only` = 只挑 ACE 机）。
func _nearest_in(pool: Array, ace_only: bool) -> FlightBody:
	var best: FlightBody = null
	var best_d := INF
	for x in pool:
		var fb := x as FlightBody
		if fb == null or not is_instance_valid(fb) or not fb.is_alive():
			continue
		if ace_only and (fb.profile == null or not fb.profile.is_ace()):
			continue
		var d := global_position.distance_squared_to(fb.global_position)
		if d < best_d:
			best_d = d
			best = fb
	return best


## 自己是不是 ACE 机（`profile` 还没配好时按"不是"处理）。
func _is_ace() -> bool:
	return profile != null and (profile.is_ace() or (_super_hard() and profile.id==SuitProfile.Id.REGZ_CUSTOM))


## 编队战里"该从踏板上下来了"的距离（米）。
##
## 用户原话：「六台量产机分为 2/2/2 三组**都在飞行踏板上**，
## **接近敌人被锁定之后再从飞行踏板上下来**」。
##
## ## 为什么要有这一步
##
## 骑板有硬代价：**转向变钝 ×0.8、不能悬停、不能拔刀**
##（见 `FlightBody.pedal_restricts_melee()` 那一段）。
## 所以"一路骑着板冲进缠斗"是**打不赢**的 —— 赶路靠板、开打靠腿，
## 这个切换点就是这条设计的落点。
##
## 4500 m 的取法：这是"已经进入视距、开始互相锁定"的量级
##（锁定距离按 6 km 计），而再近一点（2 km 内）才开始下板就来不及了 ——
## 板上的转向钝感会直接吃掉第一轮交火的角度。
const SQUAD_DISMOUNT_DIST := 4500.0


## 编队战：带着队伍接近敌人之后**主动脱离踏板**。
##
## ⚠️ 只有**领机**做这件事（板挂在他身上）。他 `release_pedal()` 一次，
## `break_off()` 会把板上每一位都放下来 —— 所以后座不用自己判断。
##
## ⚠️ **只在编队战里做**：1v1 与训练里也去下板的话，
## "敌机一路骑着板"这个既有表现会被改掉，而那些模式的测试是按旧行为写的。
func _maybe_dismount_for_combat() -> void:
	if Game.match_mode != Game.MatchMode.SQUAD:
		return
	# 被载机不判断（放板是领机的事）；没板也不用判断。
	if is_carried() or not has_pedal():
		return
	var tgt := _target
	if tgt == null or not is_instance_valid(tgt):
		return
	if global_position.distance_to(tgt.global_position) <= SQUAD_DISMOUNT_DIST:
		# `release_pedal()` = **主动脱离**：不吃伤害、不进失能，
		# 板会自己飞走 5 s 后消失（不是自爆）—— 见 `FlightPedal.begin_cast_off()`。
		release_pedal()


## 对面**最近的一台活着的 ACE** —— 没有就返回 null。
##
## 只在 ACE 机的 `_pick_target()` 里调用。`Game.live_hostiles_of()` 的条目
## 可能不是 `FlightBody`（网络代理 / 正在删的），所以逐个 `as` 判空。
func _nearest_hostile_ace() -> FlightBody:
	var best: FlightBody = null
	var best_d := INF
	for h: Node3D in Game.live_hostiles_of(self):
		var fb := h as FlightBody
		if fb == null or fb == self or fb.profile == null or not fb.profile.is_ace():
			continue
		if not fb.is_alive() or fb.is_queued_for_deletion():
			continue
		var d := global_position.distance_squared_to(fb.global_position)
		if d < best_d:
			best_d = d
			best = fb
	return best


const TARGET_SCAN_INTERVAL := 0.2
var _target_scan_left := 0.0
var _target_scan_had_target := false
var _target_unit_count := 0

# Roster changes and explicit target resets bypass the periodic scan.
func _refresh_target(delta: float) -> void:
	_target_scan_left -= delta
	var lost := _target != null and (not is_instance_valid(_target) or _target.is_queued_for_deletion() or not _target.is_alive() or not _target.is_hostile_to(self))
	if _target_scan_left <= 0.0 or Game.units.size() != _target_unit_count or lost or (_target == null and _target_scan_had_target) or (is_instance_valid(target_override) and not target_override.is_queued_for_deletion() and _target != target_override):
		_target = _pick_target()
		_target_scan_had_target = _target != null
		_target_unit_count = Game.units.size()
		# Stagger later scans, without delaying the first decision or target loss.
		_target_scan_left = TARGET_SCAN_INTERVAL+float(get_instance_id()%7)*0.004

func _think(delta: float) -> void:
	if flash_blind_left>0:
		_target=null
		_target_scan_left=0.0
		terrain_time=_probe_terrain()
		_steer(_blend_safety(forward()),delta)
		fm.throttle=0.6
		fm.boosting=false
		return
	# ★ 轮 57：**演出接管**（M04 的开场演出把佩涅罗佩借走几秒）。
	# ⚠️ 让路点选在 `_think()` 而不是 `_physics_process()`：`BanditAI` 没有覆写
	# `_physics_process`（飞行积分在 `FlightBody` 那边），所以"让路"的粒度正好是
	# "AI 不产生控制输入"这一层 —— 物理照跑，位置由演出方每帧覆盖。
	_tick_hard_skills(delta)
	if scripted:
		return
	_refresh_target(delta)
	_boss.tick(self,delta)
	# 编队战：接近敌人之后**从踏板上下来**（赶路靠板、开打靠腿）。
	# 放在选目标之后：判断要用到 `_target`。
	_maybe_dismount_for_combat()
	_burst_timer = maxf(_burst_timer - delta, 0.0)
	_flare_timer = maxf(_flare_timer - delta, 0.0)
	_form_timer = maxf(_form_timer - delta, 0.0)
	_state_time += delta
	_drive_form()
	_tick_aim_error(delta)
	# 王牌机的强制进攻节拍（每 `ACE_ATTACK_PERIOD` 秒必冲一次）—— 放在状态判断之前。
	_tick_ace_pressure(delta)
	_sync_lock_params()

	# 兜底：军刀突进期间速度矢量被 `_step_saber` 完全接管，转向输入一律无效，
	# 所以避地逻辑在这段时间里是**失效**的。高度一旦进入危险区就只能直接掐断，
	# 让正常飞行模型接管。门禁（_saber_is_viable）挡的是"别冲出去"，
	# 这一条挡的是"冲出去之后情况变了"（目标机动、自己角度不对）。
	if saber_active() and global_position.y < SABER_ABORT_ALTITUDE:
		abort_saber()

	# ---- 地形探头（批 16 防撞地）----
	# 海平面外推（SAFE/CRITICAL）看不见山：沙丘/峡谷图里"y 很高、离地几十米"
	# 照样撞。探头看的是**真实几何**，结果喂给三处：军刀掐断（下面）、
	# 紧急拉升（`_needs_pull_up` 旁边）、软性上仰（`_blend_safety`）。
	terrain_time = _probe_terrain()
	if saber_active() and terrain_time < SABER_ABORT_TERRAIN_TIME:
		abort_saber()

	if _target == null:
		# 没有目标就平飞巡航 —— 但**僚机要归队**（否则"没目标"就等于编队散了）。
		# ⚠️ 巡航也要过避地（批 16）：无目标漫飞正是撞山的重灾区 ——
		# 这条线在批 16 之前连海平面那一套都不走。
		_steer(_blend_safety(_blend_formation(forward())), delta)
		fm.throttle = 0.6
		fm.boosting = false
		fm.hovering = false
		# 不再直接关盾：举盾现在是"按一次 5 秒"，已经举起来的就让它自然走完。
		# 不调 raise_shield() 就等于不再续盾。
		return

	var desired := _decide_desired_direction()
	# ---- 编队跟随（1.2 第二十轮）----
	#
	# ⚠️ 放在 `_decide_desired_direction()` **之后**、避地与转向之前：
	#   - 之后 ⇒ 它揉的是"打斗想去的方向"，而不是覆盖它；
	#   - 之前 ⇒ 后面还有紧急拉升（那个优先于一切，不该被归队带偏）。
	# 于是"离队太远"会自动压过"想咬人"，而被甩回队形之后又自然放开手。
	desired = _blend_formation(desired)
	# 紧急拉升优先于一切：状态机想俯冲也好、想咬人也罢，先活下来再说。
	# （批 16：海平面预判 `_needs_pull_up()` 之外，地形探头的"秒数到点"
	# 也进这一档 —— 山不会等海平面那一套反应过来。）
	if _needs_pull_up() or terrain_time < TERRAIN_PULL_TIME:
		_steer(_pull_up_direction(), delta)
		_drive_escape_throttle()
		_check_discard()
		return
	desired = _blend_safety(desired)
	_steer(desired, delta)
	_apply_point_noise()
	_check_discard()
	_drive_weapons(delta)


# ------------------------------------------------------------ 1.2：瞄准误差与锁定代价

## AI 瞄准用的目标位置（**滞后**版）。所有"往哪转、往哪打"都要读它，
## 这样"反应慢"才会同时体现在航迹和命中率上。
func _aim_pos() -> Vector3:
	if _target == null or not is_instance_valid(_target):
		return global_position
	if _lag_pos == Vector3.ZERO:
		_lag_pos = _target.global_position
	return _lag_pos


## 每帧推进滞后位置 + 机头抖动相位。
func _tick_aim_error(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_lag_pos = Vector3.ZERO
		return
	if _lag_pos == Vector3.ZERO:
		_lag_pos = _target.global_position
	var tau := maxf(difficulty.ai_reaction_lag, 0.02)
	_lag_pos = _lag_pos.lerp(_target.global_position, 1.0 - exp(-delta / tau))
	_noise_phase += delta * (0.8 + 0.5 * skill)


## 机头抖动：把慢速正弦加进操纵量。**在 `_steer()` 之后调用**（否则会被覆盖）。
func _apply_point_noise() -> void:
	var amp := deg_to_rad(difficulty.ai_point_noise_deg)
	if amp <= 0.0:
		return
	control_input.x += sin(_noise_phase * 1.7) * amp / PITCH_REF
	control_input.z += sin(_noise_phase * 1.1 + 1.3) * amp / ROLL_REF
	control_input.x = clampf(control_input.x, -1.0, 1.0)
	control_input.z = clampf(control_input.z, -1.0, 1.0)


## 每帧把难度表的锁定参数写进自己的 `LockOnSystem`（方案 B 的接线）。
##
## ⚠️ **为什么是每帧而不是在 `_ready()` 里落一次**：`enemy.lock` 是在
## `main._attach_ai()` 里"机体建好之后"才赋值的，而 `BanditAI._ready()` 跑得更早 ——
## 那一刻 `lock` 还是 null，只在 `_ready()` 落参数等于**一个都没落上**。
## （`_drive_form()` 里有一条同样性质的注释：换形态之后也必须重算难度参数。）
func _sync_lock_params() -> void:
	if lock == null:
		return
	var hunt := hunt_lock_mult()
	var mult := difficulty.lock_time_mult if hunt >= 1.0 else hunt
	lock.lock_time = lock.BASE_LOCK_TIME * mult
	lock.outer_deg = difficulty.lock_outer_deg
	lock.decay_rate = lock.BASE_DECAY * difficulty.lock_decay_mult
	lock.relock_lockout = difficulty.relock_lockout
	# 猎杀规则是"绝对覆盖"（不乘难度），所以把它作为质量倍率交给锁定系统：
	# `target_quality()` 会乘上它 —— 1.0 之上没有意义，所以只在 < 1 时生效。
	lock.quality_override = hunt
	if hunt < 1.0 and not _hunt_announced:
		_hunt_announced = true
		# 必须给玩家一个说法：没有反馈的话，体验是"突然就躲不掉了"。
		# 那是设计事故，不是难度。
		Game.log_event("阿利宙斯 · 猎杀锁定")
		Audio.play_self("alarm_lock", -2.0)
	elif hunt >= 1.0:
		_hunt_announced = false


## 猎杀锁定：阿利宙斯对残血柯西（用户指定）。
##
## 原文：「阿利宙斯遭遇柯西，柯西 40% 血量之后锁定倍率为 0.3」。
##   - **只给 AI**：这条写在 `BanditAI` 里，而它是敌机类 —— 天然只给 AI，
##     玩家侧永远不检查（这样"只给 AI"最省事也最不容易写错）；
##   - **绝对覆盖，不乘难度**：0.85 × 0.30 = **0.255 s**，三个难度一样凶；
##   - **与丢枪的因果**：柯西 ≤50% 血丢枪换来 7 秒不可被锁定，而 40% 恰好落在那 7 秒里 ——
##     于是"丢枪换来的 7 秒"就是玩家唯一的喘气窗口，窗口一过就是 0.255 s。
## 返回 1.0 = 不覆盖，0.30 = 绝对覆盖。
func hunt_lock_mult() -> float:
	if profile == null or profile.id != SuitProfile.Id.ARIZEUS:
		return 1.0
	if _target == null or not is_instance_valid(_target) or _target.profile == null:
		return 1.0
	if _target.profile.id not in [SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL]:
		return 1.0
	return 0.30 if _target.hp_ratio() < 0.40 else 1.0



#
# 用户要求"阿利宙斯分三个模式"。玩家侧用 Z 手动切巡航/常态、按血线自动爆壳变核心；
# **AI 侧没有手，所以这里给一条"什么状态用哪个形态"的规则**：
#   赶路 / 脱离（SEEK·EXTEND·EVADE）→ 巡航形态（直线最快，转不动也无所谓）；
#   缠斗（ATTACK）→ 常态（转得动才咬得住）。
# 核心形态只能由爆壳产生，AI 不手动切（`switchable_forms()` 也不给它切）。

func _drive_form() -> void:
	if _boss.enabled(self):
		_boss.drive_form(self)
		return
	if profile == null or profile.id != SuitProfile.Id.ARIZEUS:
		return
	if _form_timer > 0.0 or profile.form == SuitProfile.ArizeusForm.CORE_NU:
		return
	var want := SuitProfile.ArizeusForm.NORMAL
	if state == State.SEEK or state == State.EXTEND or state == State.EVADE:
		want = SuitProfile.ArizeusForm.CRUISE
	if want == profile.form:
		return
	if switch_form(want, true):
		_form_timer = 3.0
		# ⚠️ 必须重算难度速度：`switch_form` 走的是 `_apply_profile_to_flight()`
		# （玩家侧的速度上限），而敌机的上限是"基准 × 难度倍率 × 机体系数"。
		# 漏掉这一句，敌机换形态后速度会突然掉回玩家档 —— 表现就是"变了个形态就变笨了"。
		_apply_difficulty()


# ------------------------------------------------------------ 状态机

func set_state(s: State) -> void:
	if state == s:
		return
	state = s
	_state_time = 0.0


# ---- 进攻欲望的落点（见 AGGRESSION）----
#
# 下面这几个读写点就是状态机的**全部**阀值。`AGGRESSION` 只在这里出现，
# 状态机本体读的是"已含欲望"的值 —— 这样整体拧一个常量时，不会出现
# "改了接战距离却漏了脱离距离"那种只拧一半的状态。

## 多远就压上去（`SEEK → ATTACK`）。越大越主动。
func engage_dist() -> float:
	return engage_range * AGGRESSION * (1.5 if _super_hard() else 1.0)


## 贴到多近算"冲过头"、要脱离（`ATTACK → EXTEND`）。越小越敢贴脸。
func break_dist() -> float:
	return break_range / AGGRESSION / (1.4 if _super_hard() else 1.0)


## 躲一次要驻留多久（`EVADE`）。越短越凶。
func evade_seconds() -> float:
	return lerpf(4.2, 2.4, skill) / AGGRESSION * (.45 if _super_hard() else 1.0)


## 拉开一次要驻留多久（`EXTEND`）。越短越凶。
func extend_seconds() -> float:
	return lerpf(4.5, 2.6, skill) / AGGRESSION * (.40 if _super_hard() else 1.0)


# ---- 王牌机的**强制进攻周期**（1.2 第二十九轮，用户指定）----
#
# 用户原话：「**增加对方王牌机的进攻欲望，每 12 秒强制进攻一次**」。
#
# ## 为什么需要"强制"，而不是再调一个概率
#
# 现在的状态机是"条件满足才打"：`SEEK → ATTACK` 要求**距离够近且机头角度够正**
#（`dist < engage_dist() and ang < 75`）。于是会出现这种局面 ——
# 双方在互相绕圈、谁都咬不到，ACE 就一直卡在 `SEEK`/`EXTEND` 里**什么都不做**。
# 对玩家来说那是"敌机在发呆"，而它其实是"条件没满足"。
#
# 所以这条不是"更凶一点"，而是**保证一个下限**：不管角度、不管距离，
# 每 `ACE_ATTACK_PERIOD` 秒它至少会**冲上去一次**。这让对局有节奏 ——
# 玩家知道"最多等这么久它一定会来"，而不是"运气不好它就一直飘着"。
#
# ## ★ 轮 63-9 · B5 修订：**12.0 → 9.0**（用户 2026-10-04 改口）
#
# 用户原话：「阿利宙斯偶尔会一直跑路，需要让他进攻欲望增强。」
# 12 秒是上面那位用户自己定的，但它定的是**下限节拍**；这次的抱怨
# 「偶尔一直跑路」说明**下限太松**。`tools/probe_aggression.tscn` 的基线读数
#（3 态势 × 60 s，全部难度平均 ATTACK 占比 **55.9%**）：
# 简单 **72.6%** / 中等 **65.6%** / **困难 29.4%** ——
# 困难档 29.4% 正是"互相绕圈时它大半时间在 EXTEND"的样子。
#
# 占空比 `ACE_COMMIT_WINDOW / ACE_ATTACK_PERIOD`：**4/12 = 33.3% → 5/9 = 55.6%**。
#
# ⚠️ 只动这两个常量、**不动 `AGGRESSION`**：它已标定到 +30%，且
# `README.md` 里那张历史标定表在案；重标一次要连带
# `engage_dist` / `break_dist` / `evade_seconds` / `extend_seconds` 四处 ——
# 那是另一件事（设计文档 §2.5「方案 A」）。
const ACE_ATTACK_PERIOD := 9.0
## 强制进攻之后的**不许脱战窗口**（秒）。
##
## ⚠️ 没有这个窗口的话，"强制进 ATTACK"会被下一帧的状态机立刻推翻
##（比如恰好被威胁 ⇒ 当场切 `EVADE`），等于什么都没做。
## 4 秒 ≈ 一次正面交火的时间：够它把这一轮攻势打出去，又不至于一直挨打不躲。
#
# ★ 轮 63-9 · B5：**4.0 → 5.0**（与 `ACE_ATTACK_PERIOD` 一起动，理由见上面那一段）。
# ⚠️ 必须**仍小于** `ACE_ATTACK_PERIOD`（`suite_hardmode` 有守卫）——
# 否则它一直在进攻、从不脱离，变成无脑冲。`5.0 < 9.0` 成立。
const ACE_COMMIT_WINDOW := 5.0


## 距离上一次强制进攻过了多久（秒）。
var _ace_pressure := 0.0
## 强制进攻的"不许脱战"窗口剩余（秒）。>0 时不许切 EVADE/EXTEND。
var _ace_commit := 0.0


## 王牌机的强制进攻节拍。**每帧调一次**（在 `_think` 里）。
##
## 只对 ACE 生效（用户说的是"**对方王牌机**"）——
## 量产机保持原来的行为，否则六台杂兵一起按这个节拍强冲，场面会失控。
func _tick_ace_pressure(delta: float) -> void:
	if not _is_ace():
		return
	_ace_commit = maxf(_ace_commit - delta, 0.0)
	_ace_pressure += delta
	if _ace_pressure < (4.0 if _super_hard() else ACE_ATTACK_PERIOD):
		return
	_ace_pressure = 0.0
	# 没有目标就没有"进攻"可言（这时它该做的是巡航/归队）。
	if _target == null or not is_instance_valid(_target):
		return
	_ace_commit = 3.6 if _super_hard() else ACE_COMMIT_WINDOW
	set_state(State.ATTACK)


func _decide_desired_direction() -> Vector3:
	var dist := global_position.distance_to(_aim_pos())
	var ang := Ballistics.angle_off_boresight(forward(), _aim_pos() - global_position)
	var threatened := _is_threatened()
	if _super_hard() and dist>15000.0:
		set_state(State.ATTACK)
		return global_position.direction_to(_target.global_position)

	if _boss.enabled(self) and is_instance_valid(_target):
		set_state(State.EVADE if _boss.evading(self) else (State.SEEK if dist>engage_dist()*1.35 else State.ATTACK))
		return _boss.direction(self)

	match state:
		State.SEEK:
			if dist < engage_dist() and ang < 75.0:
				set_state(State.ATTACK)
			elif threatened:
				set_state(State.EVADE)
		State.ATTACK:
			# ⚠️ **强制进攻窗口内不许脱战**（见 `_tick_ace_pressure()`）。
			# 不挡的话下面那两条会当场把"强制进攻"推翻 ——
			# 表现是"每过一个周期它确实切了一下 ATTACK，但你看不出来"。
			if _ace_commit <= 0.0 and dist < break_dist():
				set_state(State.EXTEND)
			# 「被威胁了还咬多久」= 进攻欲望最直接的落点：×1.3 之后它更不躲。
			elif _ace_commit <= 0.0 and threatened \
					and _state_time > AGGRESSION / maxf(skill, 0.2):
				set_state(State.EVADE)
			# ⚠️ **这一条有意不挂 `_ace_commit` 守门**（轮 63-9 实测后的决定）：
			# 远距时 `ATTACK` 与 `SEEK` 的方向**完全一致** —— `dist >= gun_range`
			# ⇒ 两边都返回 `_intercept_dir_beam()`，差别只在油门：
			# `SEEK` 是 `0.92 + boosting`、`ATTACK` 是 `1.0 + 不 boost` ⇒
			# 让位给 `SEEK` **更快**；硬把 ATTACK 钉在远距上反而**拖慢**它压上去。
			# 于是"每过一个周期强行切一次 ATTACK"在远距是**无声的**：
			# `_ace_pressure` 归零、`_ace_commit` 被武装，但状态当帧就回 SEEK。
			# 判据见 `tests/suite_ace_pressure.gd` §④-b（钉的就是这条行为）。
			elif dist > engage_dist() * 1.35:
				set_state(State.SEEK)
		State.EVADE:
			# 在窗口里就**立刻转回进攻**（它是被强制进攻之前就已经在躲的那种情况）。
			if _ace_commit > 0.0:
				set_state(State.ATTACK)
			elif _state_time > evade_seconds() and not threatened:
				set_state(State.SEEK if dist > break_dist() * 2.0 else State.EXTEND)
		State.EXTEND:
			# 同理：窗口里不许继续脱离，转回进攻。
			if _ace_commit > 0.0:
				set_state(State.ATTACK)
			elif _state_time > extend_seconds():
				set_state(State.SEEK)

	return _direction_for_state(dist)


func _direction_for_state(dist: float) -> Vector3:
	match state:
		State.SEEK:
			return _intercept_dir_beam()
		State.ATTACK:
			if dist < gun_range:
				return _intercept_dir(SuitProfile.vulcan_speed())
			return _intercept_dir_beam()
		State.EVADE:
			# 破 S：垂直于来袭方向横滚脱离。**低空时不再往下切** ——
			# 原来固定带一个 −0.55 的俯冲分量去换速度，在低空等于主动扎海。
			var away := (_aim_pos() - global_position).normalized()
			var side := away.cross(Vector3.UP)
			if side.length_squared() < 0.01:
				side = Vector3.RIGHT
			side = side.normalized() * (1.0 if (Time.get_ticks_msec() / 900) % 2 == 0 else -1.0)
			# 高度越低，俯冲分量越小；低于安全线时直接去掉
			var dive := -0.55 * clampf(
				(global_position.y - CRITICAL_ALTITUDE) / SAFE_ALTITUDE, 0.0, 1.0)
			var down := Vector3(maxf(-away.x, 0.0), dive, maxf(-away.z, 0.0))
			if down.length_squared() < 0.001:
				down = Vector3.UP
			return (side * 0.85 + down.normalized() * 0.35).normalized()
		State.EXTEND:
			var away2 := (global_position - _aim_pos()).normalized()
			return (away2 + Vector3(0, 0.12, 0)).normalized()
		_:
			return forward()


## 朝目标提前量点的方向。
func _intercept_dir(projectile_speed: float) -> Vector3:
	var aim := Ballistics.intercept_point(
		global_position, _aim_pos(), _target.fm.velocity, maxf(projectile_speed, 1.0))
	var d := aim - global_position
	if d.length_squared() < 0.001:
		return forward()
	return d.normalized()


## 光束步枪的瞄准方向。⚠️ 光束的弹道是**两段式**（出膛慢 → 接近光速），
## 工程里没有"光束弹速"这个数，所以不能走 `_intercept_dir()` 的等速方程
##（代 900 会把提前量算到天上，代 9×10⁴ 等于完全不提前量）。
## 这条与 `FlightBody.aim_point(..., beam_model = true)`、HUD 的提前量圈**同源**。
func _intercept_dir_beam() -> Vector3:
	var aim := Ballistics.beam_lead_point(global_position, _aim_pos(), _target.fm.velocity)
	var d := aim - global_position
	if d.length_squared() < 0.001:
		return forward()
	return d.normalized()


## 按当前速度矢量外推，判断"照这样飞下去会不会撞海"。
##
## 关键在外推而不是看当前高度：630 m/s 下一秒钟就下沉几百米，
## 等到高度真的低于安全线时，动量已经把人压进海里了。
func _needs_pull_up() -> bool:
	var y := global_position.y
	if y < CRITICAL_ALTITUDE:
		return true
	return _predicted_altitude() < CRITICAL_ALTITUDE


func _predicted_altitude() -> float:
	return global_position.y + fm.velocity.y * PULL_UP_LOOKAHEAD


## 拉升方向：以约 55° 爬升，同时保留一部分水平机动 —— 纯垂直爬升会把速度全部吃光，
## 而且万一正好在玩家前方，纯垂直等于把自己挂在天上当靶子。
func _pull_up_direction() -> Vector3:
	var v := fm.velocity
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length_squared() < 1.0:
		flat = forward()
	flat = flat.normalized()
	return (flat + Vector3.UP * 1.4).normalized()


## 紧急拉升时收油门：转弯半径 r = v/ω，速度降下来半径才收得紧。
## 继续加力只会让它以更大的半径平缓地扎进海里。
func _drive_escape_throttle() -> void:
	fm.hovering = false
	fm.boosting = false
	fm.throttle = 0.35
	# 同样不直接关盾，理由见上


## 低空强制拉起 + 出界回中。现在都改成**预判式**的。
func _blend_safety(desired: Vector3) -> Vector3:
	var predicted := _predicted_altitude()
	if predicted < SAFE_ALTITUDE:
		var urgency := clampf((SAFE_ALTITUDE - predicted) / SAFE_ALTITUDE, 0.0, 1.0)
		desired = desired.lerp(Vector3.UP, urgency * 0.95)
	# ---- 地形探头（批 16）----
	# 与海平面那一档同向（都朝 UP），谁急听谁的 —— 两个 lerp 叠加自然取重者。
	if terrain_time < TERRAIN_AVOID_TIME:
		var kt := clampf(1.0 - terrain_time / TERRAIN_AVOID_TIME, 0.0, 1.0)
		desired = desired.lerp(Vector3.UP, kt * 0.9)
	var dist_origin := Vector2(global_position.x, global_position.z).length()
	if dist_origin > ARENA_RADIUS:
		var inward := Vector3(-global_position.x, 0, -global_position.z).normalized()
		var urgency2 := clampf((dist_origin - ARENA_RADIUS) / 4000.0, 0.0, 1.0)
		desired = desired.lerp(inward, urgency2 * 0.8)
	return desired.normalized()


## 地形探头：机头前向 + 前下两条射线，取"最近撞击"折算成秒。
##
## 与 FlightAssist 的探头同一条规矩：
##   - **只打 WORLD 层**（collision_mask = 1）—— 机体之间的碰撞不触发避让，
##     否则两机对冲会互相抬杆；
##   - "下"用**世界 DOWN**，不用机体自己的 up —— 压坡度/倒飞时 basis.y
##     接近水平，用它会朝侧面探；
##   - 视界长度 = 速度 × TERRAIN_AVOID_TIME × 1.2 —— 高速机看得远才拉得回来。
##
## ⚠️ 海平面外推的盲区就是它存在的理由：探头看的是**真实几何**，
## 山脊上 y 再高、离地只剩几十米它也看得见。
func _probe_terrain() -> float:
	if not is_inside_tree() or not alive or is_carried():
		return INF
	var space := get_world_3d().direct_space_state
	var spd := maxf(fm.speed, 60.0)
	var fwd := forward()
	var best := INF
	for dir: Vector3 in [fwd, (fwd + Vector3.DOWN * TERRAIN_PROBE_DOWN).normalized()]:
		var q := PhysicsRayQueryParameters3D.create(
			global_position, global_position + dir * (spd * TERRAIN_AVOID_TIME * 1.2))
		q.collision_mask = 1          # WORLD_LAYER
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var at: Vector3 = hit.get("position", global_position)
		best = minf(best, global_position.distance_to(at) / spd)
	return best


# ------------------------------------------------------------ 转向控制器

## 把"世界方向"翻译成 (pitch, roll)。
func _steer(desired_dir: Vector3, _delta: float) -> void:
	var local := global_transform.basis.inverse() * desired_dir.normalized()
	var fwd_comp := -local.z
	var pitch_ang := atan2(local.y, fwd_comp)
	var roll_ang := atan2(local.x, fwd_comp)
	control_input = Vector3(
		clampf(pitch_ang / PITCH_REF, -1.0, 1.0),
		0.0,
		clampf(-roll_ang / ROLL_REF, -1.0, 1.0))


# ------------------------------------------------------------ 丢枪（柯西专属）

## 按难度表检查丢枪时机。规则是"一次性的"，触发过就不再触发。
func _check_discard() -> void:
	if profile == null or not profile.can_discard_rifle:
		return
	if rifle_count <= 0 or discard_cooldown > 0.0:
		return
	if difficulty == null:
		return
	for i in difficulty.discard_rules.size():
		if i < _discard_rule_used.size() and _discard_rule_used[i]:
			continue
		var rule: Dictionary = difficulty.discard_rules[i]
		var fire := false
		match rule.get("trigger", ""):
			Difficulty.TRIGGER_HP_BELOW:
				fire = hp_ratio() <= float(rule.get("threshold", 0.0))
			Difficulty.TRIGGER_FIRST_LOCKED:
				fire = _is_locked_by_player()
		if fire:
			if i < _discard_rule_used.size():
				_discard_rule_used[i] = true
			discard_rifle(float(rule.get("unlock", 0.0)))
			return


# ------------------------------------------------------------ 武器

## 现在劈出去安不安全。
##
## 判据是**目标的高度**而不是自己的：突进是朝目标冲的，终点就在目标附近，
## 所以决定"会不会扎海"的是目标在什么高度。
## 顺带要求自己也不能太低 —— 从贴海位置起冲，冲完也拉不起来。
func _saber_is_viable() -> bool:
	if global_position.y < SABER_MIN_OWN_ALTITUDE:
		return false
	# `_target` 是在 `_think` 开头赋值的，理论上 `_drive_weapons` 被调用时它一定有值。
	# 但这里还是兜一层从 Game 取目标：不然"目标是谁"会依赖调用时机，
	# 一旦哪天有人从别处调这个方法，门禁就会静默失效（返回 true = 允许冲锋）。
	var tgt := _target
	if tgt == null:
		tgt = Game.live_player() as FlightBody
	if tgt != null and tgt.global_position.y < SABER_MIN_TARGET_ALTITUDE:
		return false
	return true


func _drive_weapons(delta: float) -> void:
	var dist := global_position.distance_to(_aim_pos())
	var ang := Ballistics.angle_off_boresight(forward(), _aim_pos() - global_position)
	_drive_throttle(dist)
	_drive_shield(dist)
	_drive_flares(delta)

	_drive_super_intercept()
	_drive_hard_skills(dist, ang)

	# --- 光束军刀：贴脸且有锁定就劈（吸附突进）---
	# ⚠️ 这里必须加高度门禁。军刀突进是"朝目标 1150 m/s 直线冲 1.5 秒"（约 1.7 km），
	# **期间完全不走避地逻辑**（`_step_saber` 直接接管了速度矢量）。
	# 目标贴着海面时这一冲就是死亡冲锋 —— 实测玩家在 60 m 高度时，
	# 敌机会一路冲到 27 m 然后撞海自爆（撞海线是 24 m）。
	# 低空目标不劈，改用机炮/光束咬。
	if dist < saber_range and saber_cooldown <= 0.0 and lock != null and lock.locked \
			and profile.has_saber and _saber_is_viable() and _hard_dash_left <= 0.0:
		try_saber(_target)
		return

	# GP03S equips one weapon at a time; reload windows favor the bazookas.
	if profile.id == SuitProfile.Id.GP03S:
		if saber_active() or _saber_visual_tail > 0.0 or bazooka_cd > 0.0: return
		if rifle_reloading and dist < beam_range and ang < beam_cone_deg:
			fire_gp03s_bazookas(_target)
			return

	# --- 光束步枪：主武器，进锥就打（弹匣空了就先换弹）---
	if rifle_mag <= 0 and not rifle_reloading and rifle_count > 0:
		reload_rifle()
	elif dist < beam_range and ang < beam_cone_deg + 4.0 * skill and not (_boss.enabled(self) and _boss.hold_rifle(self)):
		fire_wire_arms(_target)
		fire_beam(true, _target, true)

	# --- 火神炮：近距点射 ---
	if _burst_hold:
		if _burst_timer <= 0.0:
			_burst_hold = false
			_burst_timer = lerpf(1.1, 0.35, skill)
		else:
			# ⚠️ 骑板时这一发走**踏板的火神机枪**（1.2）：用户的分工是
			# "领队机操控踏板、另一台负责踏板的武器"。判据用
			# `FlightPedal.gun_operator()`（板上第二位骑手）——
			# 于是"一台机体"永远只有一个火神炮操作者，不会两门炮一起响。
			var board := pedal_owner()
			if board != null and board.gun_operator() == self:
				fire_pedal_gun(true, _target)
			elif board == null:
				fire_gun(true, _target)
	elif dist < gun_range and ang < gun_cone_deg + 3.0 * skill and _burst_timer <= 0.0:
		_burst_hold = true
		_burst_timer = lerpf(0.55, 0.95, skill)

	# --- 浮游导弹：锁定且距离合适就放（核心形态没有导弹）---
	# 第十八轮：**AI 的弹幕加密**（用户要求"提升导弹的密度和华丽度"）。
	# 开关就是 `fire_funnel()` 的 `salvo_cooldown` 参数 —— 它天生是"这次扳机压多长冷却"，
	# 于是**只改 AI**：玩家仍是 0.42 s、手柄自动拦截仍是 0.16 s（不跨设备漂移）。
	# ⚠️ 难度越高越密（0.36 → 0.26 s）：压力交给难度表说话，而不是所有难度一起拉满。
	if _boss.enabled(self):
		_boss.fire_missiles(self,dist)
		return
	if _hard_salvo_left <= 0 and profile.has_missiles and lock != null and lock.locked \
			and dist < missile_range and dist > 320.0:
		var ai_cd := 0.36 - 0.05 * skill
		if randf() < (0.28 + 0.5 * skill) * delta * 6.0:
			fire_funnel(lock.target, ai_cd)


func _drive_throttle(dist: float) -> void:
	fm.hovering = false
	match state:
		State.EXTEND, State.EVADE:
			fm.throttle = 1.0
			fm.boosting = true
		State.SEEK:
			fm.throttle = 0.92
			fm.boosting = dist > engage_dist() * 1.2
		State.ATTACK:
			# 追得太近就收油避免冲过头
			var t := clampf((dist - break_dist()) / 600.0, 0.0, 1.0)
			fm.throttle = lerpf(0.45, 1.0, t)
			fm.boosting = false
		_:
			fm.throttle = 0.8
			fm.boosting = false
	if _super_hard():
		fm.throttle=maxf(fm.throttle,.95)
		fm.boosting=dist>break_dist()*2 or _super_boost_left>0 or dist>15000
		fm.super_boost=fm.boosting and (_super_boost_left>0 or dist>15000)
	if _boss.enabled(self):_boss.throttle(self,dist)



## 被咬住或残血时举盾。柯西的举盾减伤率更高，所以 AI 开柯西时收益也更大。
##
## 举盾改成"按一次举 5 秒 + 冷却 1 秒"之后，这里改成**表达意愿**：
## 想要盾就一直调 `raise_shield()`，它自己会在冷却/已举时拒绝。
## 不要直接写 `shield_up` —— 那样会绕过计时器，盾永远不落。
func _drive_shield(dist: float) -> void:
	var want := (dist < 1600.0 and _is_locked_by_player()) or hp_ratio() < 0.25
	if _boss.enabled(self) and profile.shield_reduction>0:want=want or _boss.evading(self)
	if want:
		raise_shield()


func _drive_flares(delta: float) -> void:
	if _flare_timer > 0.0:
		return
	var incoming := incoming_missiles().size()
	var locked := _is_locked_by_player()
	if incoming <= 0 and not locked:
		return
	var md := 0.45
	if difficulty != null:
		md = difficulty.missile_defense
	# ---- ① 困难模式：**对大规模来袭立即反应**（1.2 第二十七轮）----
	#
	# 用户报「有了全弹发射之后，佩涅罗佩和阿利宙斯的困难模式特别容易通关」。
	# 根因是下面那条**概率**触发：全弹发射一次 100 发，AI 平均要等几帧才掷中，
	# 而导弹到得很快 —— 掷不中就整梭吃满。
	#
	# 所以困难档（`missile_defense >= 1.0`）走这条**确定性**的路。
	# 这是把"难度"落在**行为**上，而不是提 `speed_mult` ——
	# 那条有"敌机极速 ≤ 玩家加力 × 0.92"的回归门，
	# 是"追不上的对手"的防线，动不得（见 `_apply_top_speed()`）。
	const SALVO_THRESHOLD := 4
	if md >= 1.0 and incoming >= SALVO_THRESHOLD:
		deploy_flares()
		# 反应越快冷却越短 —— 这是"高手"与"新手"最直观的差别。
		_flare_timer = 0.45
		return
	# ---- ② 其余档：概率触发（`missile_defense` 越高越勤）----
	#
	# ⚠️ 原来写死 `(0.5 + 0.5 * skill)`，难度**对这一条完全没影响** ——
	# 于是"简单"和"困难"在"会不会放干扰弹"这件事上是同一个 AI。
	# 现在按难度分档（简单 0.15 / 中等 0.45 / 困难走上面那条确定性的路）。
	var chance := (0.5 + 0.5 * skill) * (0.35 + 0.65 * md)
	if randf() < chance * delta * 3.0:
		deploy_flares()
		_flare_timer = lerpf(1.6, 0.7, skill)


# ------------------------------------------------------------ 态势感知

func _is_threatened() -> bool:
	return not incoming_missiles().is_empty() or _is_locked_by_player()


func _is_locked_by_player() -> bool:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return false
	var l = p.get("lock")
	if l is LockOnSystem:
		return (l as LockOnSystem).target == self and (l as LockOnSystem).locked
	return false


func state_name() -> String:
	match state:
		State.SEEK: return "SEEK"
		State.ATTACK: return "ATTACK"
		State.EVADE: return "EVADE"
		State.EXTEND: return "EXTEND"
	return "?"


# ------------------------------------------------------------ 困难敌机技能
func _hard_skills_enabled() -> bool:
	return alive and not scripted and team != 0 and difficulty != null \
		and difficulty.level in [Difficulty.Level.HARD,Difficulty.Level.SUPER_HARD]


func _tick_hard_skills(delta: float) -> void:
	_tick_super_resources(delta)
	if _super_hard() and not scripted:fm.super_boost=false
	_hard_dash_cd = maxf(0.0, _hard_dash_cd - delta)
	_hard_cannon_cd = maxf(0.0, _hard_cannon_cd - delta)
	_hard_salvo_cd = maxf(0.0, _hard_salvo_cd - delta)
	_hard_dash_left = maxf(0.0, _hard_dash_left - delta)
	if not _hard_skills_enabled():
		_hard_dash_left = 0.0
		_hard_salvo_left = 0
		_hard_salvo_roll = HARD_SALVO_ROLL_INTERVAL
		return
	# 判定时钟独立于帧率，也不在不满足半血/冷却时预存一次抽签。
	if hp_ratio() < 0.5 and _hard_salvo_cd <= 0.0:
		_hard_salvo_roll = maxf(0.0, _hard_salvo_roll - delta)
	else:
		_hard_salvo_roll = HARD_SALVO_ROLL_INTERVAL
	if _hard_salvo_left <= 0:
		return
	if not is_instance_valid(_hard_salvo_target) or not _hard_salvo_target.alive \
		or not is_hostile_to(_hard_salvo_target) or projectile_container == null:
		_hard_salvo_left = 0
		return
	if in_transform() or is_staggered():
		return
	_hard_salvo_gap -= delta
	while _hard_salvo_gap <= 0.0 and _hard_salvo_left > 0:
		_hard_salvo_gap += PlayerController.FULL_SALVO_TICK_GAP
		for i in mini(PlayerController.FULL_SALVO_PER_TICK, _hard_salvo_left):
			var n := PlayerController.FULL_SALVO_COUNT - _hard_salvo_left
			var side := 1.0 if n % 2 == 0 else -1.0
			var slot := "funnel_L" if side > 0.0 else "funnel_R"
			var a := float(n) * 2.399963
			var outward := (right() * cos(a) * side + up() * (0.30 + 0.80 * absf(sin(a)))
				+ forward() * (0.15 - 0.35 * cos(a))).normalized()
			var m := Missile.funnel(projectile_container, global_transform * rig_anchor(slot),
				outward, _hard_salvo_target, self, profile.funnel_damage * damage_mult, Missile.Trail.LOW)
			m.arm_intercept(null)
			_hard_salvo_left -= 1


func _drive_hard_skills(dist: float, ang: float) -> void:
	if not _hard_skills_enabled() or not is_instance_valid(_target) or not _target.alive \
		or in_transform() or is_staggered() or saber_active() or is_carried():
		return
	# 先判断大炮再走普通步枪，满弹匣门槛不会被同帧步枪消耗掉。
	if _hard_cannon_cd <= 0.0 and dist < beam_range and ang < beam_cone_deg \
		and lock != null and lock.locked and lock.target == _target \
		and (not _boss.enabled(self) or _boss.line_clear(self)):
		if fire_cannon(_target):
			_hard_cannon_cd = _boss.cannon_cooldown(self) if _boss.enabled(self) else HARD_CANNON_CD
	if _hard_dash_cd <= 0.0 and (state == State.EVADE or _is_threatened() \
		or (state == State.SEEK and dist > engage_dist()) or _super_hard()):
		var dir := (forward() + right() * (1.0 if _hard_rng.randf() < 0.5 else -1.0)).normalized() \
			if state == State.EVADE or _is_threatened() else forward()
		if _boss.enabled(self) and is_instance_valid(_boss.target()):
			dir=_boss.dash_direction(self,dist)
		elif _super_hard():
			if dist>15000.0:dir=global_position.direction_to(_target.global_position)
			else:
				var choices: Array[Vector3]=[right(),-right(),forward(),-forward(),up(),-up(),(forward()+right()).normalized(),(forward()-right()).normalized()]
				var begin:=_hard_rng.randi_range(0,choices.size()-1)
				for index in choices.size():
					var option:Vector3=choices[(begin+index)%choices.size()]
					if _hard_dash_clear(option):dir=option;break
		_start_hard_dash(dir)
	if hp_ratio() < 0.5 and _hard_salvo_cd <= 0.0 and _hard_salvo_roll <= 0.0:
		_hard_salvo_roll = HARD_SALVO_ROLL_INTERVAL
		if _hard_rng.randf() < (difficulty.salvo_chance if _super_hard() else HARD_SALVO_CHANCE) and dist > 320.0 and dist < missile_range \
			and lock != null and lock.locked and lock.target == _target:
			_start_hard_salvo(_target)


func _start_hard_salvo(target_unit: FlightBody) -> bool:
	if not _hard_skills_enabled() or hp_ratio() >= 0.5 or _hard_salvo_cd > 0.0 \
		or _hard_salvo_left > 0 or not is_instance_valid(target_unit) or not target_unit.alive \
		or not is_hostile_to(target_unit) or not profile.has_missiles \
		or (funnel_reload_left > 0.0 and profile.id != SuitProfile.Id.GP03D) or funnel_count < PlayerController.FULL_SALVO_COUNT \
		or projectile_container == null or in_transform() or is_staggered():
		return false
	if profile.id == SuitProfile.Id.GP03D:
		var fired := fire_funnel(target_unit)
		if fired: _hard_salvo_cd = _boss.salvo_cooldown() if _boss.enabled(self) else HARD_SALVO_CD
		return fired
	funnel_count -= PlayerController.FULL_SALVO_COUNT
	_funnel_check_reload()
	_hard_salvo_cd = _boss.salvo_cooldown() if _boss.enabled(self) else HARD_SALVO_CD
	_hard_salvo_left = PlayerController.FULL_SALVO_COUNT
	_hard_salvo_gap = 0.0
	_hard_salvo_target = target_unit
	play_full_burst()
	Audio.play_3d("funnel_fire", global_position, -1.0)
	funnel_fired.emit()
	return true


func _start_hard_dash(dir: Vector3) -> bool:
	if not _hard_skills_enabled() or _hard_dash_cd > 0.0 or saber_active() \
		or in_transform() or is_staggered() or is_carried() or _escape_timer > 0.0:
		return false
	if _super_hard() and not _super_dash_ready():return false
	dir = dir.normalized()
	if dir.is_zero_approx() or not _hard_dash_clear(dir):
		return false
	_hard_dash_dir = dir
	_hard_dash_left = _boss.dash_duration(self,dir) if _boss.enabled(self) else QB_TIME
	_hard_dash_cd = _boss.dash_cooldown() if _boss.enabled(self) else (.85 if _super_hard() else HARD_DASH_CD)
	if _super_hard():
		dash_charge=maxf(0,dash_charge-QB_CHARGE_COST)
		if dash_charge<.20:_super_dash_recovering=true
	quick_boost_started.emit(dir)
	return true


func _hard_dash_clear(dir: Vector3) -> bool:
	var travel := profile.player_boost_speed() * QB_SPEED_MULT * (_hard_dash_left if _hard_dash_left > 0.0 else QB_TIME)
	if map_has_ground() and global_position.y + dir.y * travel < CRITICAL_ALTITUDE:
		return false
	var shape := SphereShape3D.new()
	shape.radius = 32.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, global_position)
	q.motion = dir * (travel + 60.0)
	q.collision_mask = WORLD_LAYER
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.cast_motion(q)[0] >= 1.0


func _before_flight_move(_delta: float) -> bool:
	if _hard_dash_left <= 0.0:
		return false
	if not _hard_skills_enabled() or saber_active() or in_transform() or is_staggered() \
		or _needs_pull_up() or terrain_time < TERRAIN_PULL_TIME or not _hard_dash_clear(_hard_dash_dir):
		_hard_dash_left = 0.0
		return false
	fm.velocity = _hard_dash_dir * profile.player_boost_speed() * QB_SPEED_MULT
	fm.speed = fm.velocity.length()
	_start_dash_anim(_hard_dash_dir)
	return true


func assist_dashing() -> bool:
	return _hard_dash_left > 0.0 and _hard_skills_enabled()


var _super_dash_recovering:=false
var _super_boost_left:=0.0
var _super_boost_cd:=0.0
var _super_intercept_cd:=0.0
var _super_rifle_credit:=0
func _super_hard()->bool:
	return difficulty!=null and difficulty.level==Difficulty.Level.SUPER_HARD and team!=0
# Form swaps rebuild unscaled hull/field values. Reapply the enemy modifiers once
# using the new form's base values, retaining the ratio chosen by switch_form.
func switch_form(i:int,keep_ratio:=true,refill:=false)->bool:
	var changed:=super.switch_form(i,keep_ratio,refill)
	if changed and _super_hard():
		_base_hull=profile.hull_hp;_base_ifield=profile.ifield_hp
		_apply_difficulty()
	return changed

func _super_dash_ready()->bool:
	if dash_charge<.20:_super_dash_recovering=true
	if _super_dash_recovering and dash_charge>=.40 and dash_cd<=0:_super_dash_recovering=false
	return not _super_dash_recovering and dash_cd<=0 and dash_charge>=.20
func _tick_super_resources(delta:float)->void:
	if not _super_hard() or scripted:return
	if dash_charge<.20:_super_dash_recovering=true
	dash_cd=maxf(0,dash_cd-delta)
	if dash_cd<=0 and _hard_dash_left<=0:dash_charge=minf(1,dash_charge+QB_CHARGE_REGEN*delta)
	_super_dash_ready()
	_super_intercept_cd=maxf(0,_super_intercept_cd-delta)
	_super_boost_left=maxf(0,_super_boost_left-delta)
	_super_boost_cd=maxf(0,_super_boost_cd-delta)
	if _super_boost_cd<=0 and is_instance_valid(_target) and not in_transform() and not is_staggered():
		_super_boost_left=2.8;_super_boost_cd=5.0

func rifle_aim_point(origin:Vector3,target:Node3D,lead:bool)->Vector3:
	if not _super_hard() or not lead or not is_instance_valid(target):return super.rifle_aim_point(origin,target,lead)
	var aim:=_lead_point(origin,target.global_position,_velocity_of(target),0.0,true)
	# Each ten emitted beams get seven precise solutions and three intentional misses.
	# Geometry, cover, flight time and target dodges still determine actual hits.
	_super_rifle_credit+=roundi(difficulty.rifle_accuracy*100)
	if _super_rifle_credit>=100:
		_super_rifle_credit-=100
		return aim
	var side:Vector3=(aim-origin).normalized().cross(Vector3.UP).normalized()
	if side.is_zero_approx():side=Vector3.RIGHT
	var radius:=40.0
	if target is FlightBody:radius=maxf(radius,target.model_bounds.size.length()*.7+16.0)
	return aim+side*radius*(1.0 if _hard_rng.randf()>.5 else -1.0)

func _drive_super_intercept()->void:
	if not _super_hard() or _super_intercept_cd>0 or not profile.has_missiles or projectile_container==null:return
	if funnel_count<=0 or funnel_cooldown>0 or funnel_reload_left>0 or in_transform() or is_staggered():return
	var incoming:=incoming_missiles()
	if incoming.is_empty():return
	var fired:=0
	for threat:Node3D in incoming:
		if not is_instance_valid(threat) or threat.is_queued_for_deletion():continue
		if threat.global_position.distance_to(global_position)>12000:continue
		var slot:="funnel_L" if fired%2==0 else "funnel_R"
		var origin:Vector3=global_transform*rig_anchor(slot)
		var missile:=Missile.funnel(projectile_container,origin,origin.direction_to(threat.global_position),threat,self,profile.funnel_damage*damage_mult,Missile.Trail.LOW)
		missile.arm_intercept(threat)
		funnel_count-=1;fired+=1
		if fired>=3 or funnel_count<=0:break
	if fired>0:
		_super_intercept_cd=.75;funnel_cooldown=maxf(funnel_cooldown,.75)
		_funnel_check_reload();Audio.play_3d("funnel_fire",global_position,-3.0);funnel_fired.emit()


func _exit_tree()->void:
	_boss.detach()
