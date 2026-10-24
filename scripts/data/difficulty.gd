class_name Difficulty
extends RefCounted
## AI 难度表。
##
## ## 速度与伤害（需求原文 → 数值）
## | 难度 | 敌机速度 | 敌机伤害 |
## |---|---|---|
## | 简单 | 柯西基准 × 1.0（= 和柯西一样快） | × 1.0 |
## | 中等 | 柯西基准 × 1.3 | × 1.1 |
## | 困难（最高） | 柯西基准 × 1.5 | × 1.3 |
##
## ## 敌机柯西"丢枪"时机（需求原文 → discard_rules）
## - 简单：血量 ≤ 50% 丢一次，效果 **仅解除锁定**（不给无敌期）
## - 中等：血量 ≤ 50% 丢一次、< 10% 再丢一次，效果为解除锁定 + **7 秒不可被锁定**
## - 困难：**开局第一次被玩家锁定**就丢、≤ 50% 丢、< 10% 再丢，同样 7 秒
##
## 注意丢枪只对**柯西**有意义（`SuitProfile.can_discard_rifle`）——
## 敌机是佩涅罗佩时这几条规则会被跳过。

enum Level { EASY, NORMAL, HARD, SUPER_HARD }

## 丢枪触发条件
const TRIGGER_HP_BELOW := "hp_below"
const TRIGGER_FIRST_LOCKED := "first_locked"

var level: int = Level.NORMAL
var name_cn := "中等"
var speed_mult := 1.3
var damage_mult := 1.1
var ai_skill := 0.72

# ---- 锁定效率（1.2 第十轮：方案 B）----
#
# 这一组是"AI 的机头太准"的解药：**敌方 AI 也要为锁定付钱**。
# 没有它，方案 A（玩家侧改成质量条）只会让 AI 更难被玩家锁上、玩家却被 AI 一锁一个准。
#
# | 字段 | 简单 | 中等 | 困难 | 含义 |
# |---|---|---|---|---|
# | `ai_reaction_lag` | 0.50 s | 0.30 s | 0.12 s | AI 瞄准用的是"多久之前的目标位置" |
# | `ai_point_noise_deg` | 3.0° | 1.6° | 0.5° | AI 机头抖动量（慢速正弦） |
# | `lock_time_mult` | 1.80 | 1.25 | 0.70 | 锁定耗时倍率 → **1.53 / 1.06 / 0.60 s** |
# | `lock_outer_deg` | 32° | 40° | 46° | 敌机的锁定锥 |
# | `lock_decay_mult` | 0.55 | 0.80 | 1.00 | 已获质量的衰减倍率 |
# | `relock_lockout` | 3.0 s | 1.8 s | 0.9 s | 掉锁后多久才能重新起锁 |
#
# ⚠️ **它和柯西的丢枪规则正好咬成一段节奏**，看平衡时不能分开看：
# 柯西在 ≤50% 血按本表丢枪、换来 **7 秒不可被锁定**；
# 而阿利宙斯的"猎杀锁定"（见 `BanditAI.hunt_lock_mult()`）在柯西 **<40%** 触发，
# 40% 恰好落在那 7 秒窗口里 —— 于是"丢枪换来的 7 秒"就是玩家唯一的喘气窗口，
# 窗口一过，阿利宙斯进入 **0.255 s** 的绝对猎杀锁定（不乘难度）。
## AI 瞄准的滞后时长（秒）。一阶滞后，同时作用于转向、开火判定与提前量解算 ——
## 只滞后转向的话会出现"杆是旧的、扳机是新的"，子弹照样弹无虚发、只有航迹像人。
var ai_reaction_lag := 0.30
## AI 机头抖动幅度（度）。慢速正弦，让它的锁定质量在 0.7~1.0 之间横跳 ——「咬住了也咬不稳」。
var ai_point_noise_deg := 1.6
## 敌机锁定耗时倍率（乘在 `LockOnSystem.BASE_LOCK_TIME` = 0.85 s 上）。
var lock_time_mult := 1.25
## 敌机锁定锥（度）。
var lock_outer_deg := 40.0
## 敌机已获质量的衰减倍率。
var lock_decay_mult := 0.80
## 掉锁后多久不能重新起锁（秒）。
var relock_lockout := 1.8
## 每条：{ "trigger": 触发条件, "threshold": 血量阈值(0..1), "unlock": 自身不可被锁定秒数 }
var discard_rules: Array = []
var blurb := ""
var salvo_chance := 0.08
var rifle_accuracy := 0.0
var ace_hull_mult := 1.0
var ace_damage_mult := 1.0

## **导弹防御积极度**（0~1）。
##
## ## 为什么加这一条（1.2 第二十七轮，用户实测）
##
## 用户原话：「增加困难模式的难度，现在**有了全弹发射之后**，
## 佩涅罗佩和阿利宙斯的困难模式变得**特别容易通关**了」。
##
## 全弹发射是**一次 100 发**、AI 挨上基本必死。所以"困难模式太难/太易"
## 的真正杠杆不是敌机血多血少，而是**它会不会对大规模来袭做出反应**。
##
## ⚠️ 不能靠提 `speed_mult` 来解决：`suite_round`/`suite_round14` 有一条回归门
## "敌机极速 ≤ 玩家加力 × 0.92"，那是"追不上的对手"的防线，动不得。
## 所以难度要落在**行为**上，而不是数值膨胀上。
##
## 取值：
##   0.15 / 0.45 —— 仍走概率触发（保留"偶尔会漏"的手感）；
##   **1.0 困难** —— 来袭数量到阈值就**立即**放干扰弹，不吃概率
##   （`BanditAI._drive_flares()` 会据此走"确定性反应"那条路）。
var missile_defense := 0.45


static func make(level: int) -> Difficulty:
	if level == Level.SUPER_HARD:
		var super_hard := make(Level.HARD)
		super_hard.level = Level.SUPER_HARD
		super_hard.name_cn = "超级困难"
		super_hard.ai_skill = 1.0
		super_hard.ai_reaction_lag = 0.04
		super_hard.ai_point_noise_deg = 0.15
		super_hard.salvo_chance = 0.40
		super_hard.rifle_accuracy = 0.70
		super_hard.ace_hull_mult = 1.35
		super_hard.ace_damage_mult = 1.30
		super_hard.blurb = "高频超级加速与各向冲刺 · 主动追击与导弹拦截"
		return super_hard
	var d := Difficulty.new()
	d.level = level
	match level:
		Level.EASY:
			d.name_cn = "简单"
			d.missile_defense = 0.15
			d.speed_mult = 1.0
			d.damage_mult = 1.0
			d.ai_skill = 0.50
			d.ai_reaction_lag = 0.50
			d.ai_point_noise_deg = 3.0
			d.lock_time_mult = 1.80
			d.lock_outer_deg = 32.0
			d.lock_decay_mult = 0.55
			d.relock_lockout = 3.0
			d.discard_rules = [
				{"trigger": TRIGGER_HP_BELOW, "threshold": 0.50, "unlock": 0.0},
			]
			d.blurb = "半血丢枪一次 · 仅解除锁定\n不给自己无敌期"
		Level.HARD:
			d.name_cn = "困难"
			# **对大规模来袭立即反应** —— 这一条是"困难模式在全弹发射之后
			# 变得太容易"的直接对策（见 `missile_defense` 的注释）。
			d.missile_defense = 1.0
			d.speed_mult = 1.5
			d.damage_mult = 1.3
			d.ai_skill = 0.92
			d.ai_reaction_lag = 0.12
			d.ai_point_noise_deg = 0.5
			d.lock_time_mult = 0.70
			d.lock_outer_deg = 46.0
			d.lock_decay_mult = 1.00
			d.relock_lockout = 0.9
			d.discard_rules = [
				{"trigger": TRIGGER_FIRST_LOCKED, "threshold": 0.0, "unlock": 7.0},
				{"trigger": TRIGGER_HP_BELOW, "threshold": 0.50, "unlock": 7.0},
				{"trigger": TRIGGER_HP_BELOW, "threshold": 0.10, "unlock": 7.0},
			]
			d.blurb = "首次被锁定 / 半血 / 残血 各丢一次枪\n丢枪后 7 秒不可被锁定\n对大规模来袭**立即**放干扰弹"
		_:
			d.level = Level.NORMAL
			d.name_cn = "中等"
			d.speed_mult = 1.3
			d.damage_mult = 1.1
			d.ai_skill = 0.72
			d.ai_reaction_lag = 0.30
			d.ai_point_noise_deg = 1.6
			d.lock_time_mult = 1.25
			d.lock_outer_deg = 40.0
			d.lock_decay_mult = 0.80
			d.relock_lockout = 1.8
			d.discard_rules = [
				{"trigger": TRIGGER_HP_BELOW, "threshold": 0.50, "unlock": 7.0},
				{"trigger": TRIGGER_HP_BELOW, "threshold": 0.10, "unlock": 7.0},
			]
			d.blurb = "半血与残血各丢一次枪\n丢枪后 7 秒不可被锁定"
	return d


static func all_levels(super_hard_unlocked := false) -> Array[int]:
	var levels:Array[int]=[Level.EASY, Level.NORMAL, Level.HARD]
	if super_hard_unlocked: levels.append(Level.SUPER_HARD)
	return levels


## 速度 / 伤害这两个数**只由主菜单右侧的数值列显示**（直接读 `speed_mult` / `damage_mult`）。
##
## ⚠️ **不要在 `blurb` 里重复这两个数。** 早先同一组数字在三处出现：
## 左边的摘要素、右边新加的数值列、以及 `blurb` 的第一行 ——
## 三行"×1.5"排在一起，看起来像排版出错（用户报的"重新优化布局"里就有这一条）。
## 现在的分工是：`blurb` 只写**丢枪规则**，速度/伤害留给数值列。
