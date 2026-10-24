class_name UpgradeCard
extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ★63-24「无限强化演习」—— **改装芯片**（内部叙述语汇叫"卡"，游戏内字样一律"芯片"）
##
## 设计真源：`DESIGN-2026-10-08-无限强化演习.md`
##   §5.1 四字段 · §5.2 类型 · §5.3 品质 · §5.4/§5.9/§5.10 卡表 · §13 判据
##
## ## 三条不能破的规矩（都是设计文档用血换来的）
##
## 1. **卡只作用于"玩家那一份 `by_id()` 实例"**（§5.5 地基）。
##    `SuitProfile.by_id()` 每次 `new` ⇒ 在玩家实例上覆写字段 = 零侵入。
##    ⚠️ 绝不改静态表、绝不改 `xi()` 等工厂、绝不改敌方实例（§13 `NO_LEAK`）。
##
## 2. **`hull_hp` / `ifield_hp` 有 setter，会自动 ×`DURABILITY_MULT`(1.60)**
##    ⇒ 本文件的装甲卡一律写在**裸字段** `_hull_hp` / `_ifield_hp` 上，
##      走 `set()` 会二次相乘且**不报错**（§5.5 坑 1 / §13 `DURABILITY`）。
##
## 3. **卡面文案不许出现"补弹 / 省弹 / 加弹药 / 回 N 发 / 弹药 +N"**
##    —— 本作弹药全部无限，那是卖一个**不存在的成本**（§5.4.4 红线 5 / §13 `AMMO`）。
##
## ## 本表覆盖范围（★ 诚实交代）
##
## 本轮只收 **🟢 级**（落点是"已被真实消费的字段"）的卡。
## 下面这些 🟡 级条目**故意不在表里**，等下一轮（每条都要么缺落点、要么要补最小框架）：
##   · 火力：F5 撬棍 · F6 弹幕追加 · F7 击杀爆破 · F8 巨兽弹头 · F9 回响齐射 ·
##           F10 连锁冲击 · **F11 连锁闪电**（要补最小链式溅射）· **F12 燃烧弹**（要补最小 DOT）
##   · 装甲：A3 减伤镀层 · A4 概率格挡 · A5 闪避超频 · **A6 立场再生**（唯一允许新造的口子）·
##           A10 抗打断修复 · A11 超凡化（已移入激进档）· A12 最后的朋友 · A13 濒死悟道 · A14 泰坦之躯
##   · 机制：M5 浮游自主索敌 · M10 命中减速 · M11 眩晕弹 · M12 击杀刷新 · M13 狂暴 ·
##           M14 随武器转速 · M15 重掷 · M16 自动炮台 · M17 精英猎手
##   · 白刃：S7 后刃加长（准入 `saber_double`，只给柯西）· S8 断刃追击（要新状态）
##   · 重炮：C5 双管齐射 · C6 余热压制 · C7 贯穿残响
##   · 以及 §5.7.6 那批"拿到名字没拿到效果文本"的（**不猜**）
##
## ## 拍板记录（本轮采用文档推荐值，用户可随时否决）
##   Q13 = **D1** 保留原生名、删外来源重复项（F1/F2/A1/A2/M1/M2/M3/M4/M5/M6/M8 共 11 张重复已删）
##   Q14 = **A** 类型 3 → **5**（火力/装甲/机制/白刃/重炮），R5 改"5 类里取 3 个不同类型"
##   Q16 = ① 激进那 10% **从 ADVANCED 扣**（60→50）② 奖励轮**仍是 PERFECT**、激进不给保底
##          ③ 激进档**跟随 Q14 铺满 5 类**
##   Q17 = **A** 拿到激进后那 10% **原路还给 ADVANCED**（见 `endless_script.pick_tier`）

enum Type { FIRE, ARMOR, MECH, SABER, CANNON }
enum Tier { BASIC, ADVANCED, PERFECT, RADICAL }

const TYPE_NAMES := ["火力", "装甲", "机制", "白刃", "重炮"]
const TIER_NAMES := ["基础", "进阶", "完美", "激进"]
const TYPE_COUNT := 5
const TIER_COUNT := 4

## 普通间歇轮的品质权重（和 == 100）。区间：`[0,.30) / [.30,.80) / [.80,.90) / [.90,1)`。
const TIER_WEIGHTS := {Tier.BASIC: 30, Tier.ADVANCED: 50, Tier.PERFECT: 10, Tier.RADICAL: 10}
## ★ Q17：**已持有激进**时的权重 —— 那 10% **原路还给 ADVANCED**（60），
## **不动 BASIC 与 PERFECT**（用户点名"和完美一样都是 10%"⇒ 完美不能动）。
const TIER_WEIGHTS_NO_RADICAL := {Tier.BASIC: 30, Tier.ADVANCED: 60, Tier.PERFECT: 10}
## 全局唯一：一整局最多持有 1 张激进；达到上限 ⇒ **整档停止刷新**（§5.10.2 第 1+4 条）。
const RADICAL_CAP := 1
## 同一数值词条至多叠 2 份（沿用 `campaign.gd:62`，R15 保留的唯一软约束）。
const SAME_ENTRY_CAP := 2

# ───────────────────────────── 实例字段（§5.1） ─────────────────────────────

var type: int = Type.FIRE
var tier: int = Tier.BASIC
var id := ""
var name := ""
var line := ""
## 落点符号（判据用：**同一类型内不许出现两行同落点**，§5.4.5.5 / §13 `POOL`）。
var land := ""
## 激进档的"代价"列（判据：激进卡这一列**必须非空**，§13 `RADICAL` ③）。
var cost := ""
## 施加函数：`apply(profile) -> void`，只写"玩家那一份实例"。
var apply: Callable = Callable()


func type_name() -> String:
	return TYPE_NAMES[type] if type >= 0 and type < TYPE_NAMES.size() else "?"


func tier_name() -> String:
	return TIER_NAMES[tier] if tier >= 0 and tier < TIER_NAMES.size() else "?"


func describe() -> String:
	return "[%s·%s] %s —— %s" % [type_name(), tier_name(), name, line]


# ═══════════════════════════ apply 函数工厂 ═══════════════════════════
#
# 用"工厂返回 Callable"而不是给每张卡手写一个 lambda：**加一条词条 = 表里加一行**，
# 且能保证同一类运算（乘/加/置）在所有卡上写法一致 —— 这是 §5.3 那条
# 「倒数型字段必须是 ÷ 而不是 ×」最容易写错的地方。
#
# ⚠️ 装甲卡一律走 `_mulf(&"_hull_hp")` 的**裸字段**，见文件头规矩 2。

## float 字段 ×(1 + v/100)（v 是百分数）
static func _mulf(prop: StringName) -> Callable:
	return func(p: SuitProfile, v: float) -> void:
		p.set(prop, float(p.get(prop)) * (1.0 + v / 100.0))


## float 字段 ×(1 - v/100)（v 是百分数）—— 用于"时间/间隔"这类倒数型字段
static func _subf(prop: StringName) -> Callable:
	return func(p: SuitProfile, v: float) -> void:
		p.set(prop, float(p.get(prop)) * (1.0 - v / 100.0))


## float 字段 = v（绝对值）
static func _setf(prop: StringName) -> Callable:
	return func(p: SuitProfile, v: float) -> void:
		p.set(prop, float(v))


## float 字段 += v/100（**百分点**，用于减伤率这类"绝对率"）
static func _addpp(prop: StringName) -> Callable:
	return func(p: SuitProfile, v: float) -> void:
		p.set(prop, clampf(float(p.get(prop)) + v / 100.0, 0.0, 1.0))


## int 字段 += int(v)
static func _addi(prop: StringName) -> Callable:
	return func(p: SuitProfile, v: float) -> void:
		p.set(prop, int(p.get(prop)) + int(v))


## int 字段 = int(v)
static func _seti(prop: StringName) -> Callable:
	return func(p: SuitProfile, v: float) -> void:
		p.set(prop, int(v))


# ═══════════════════════════ 词条表 ═══════════════════════════
#
# 一条词条 = 一条 `Dictionary`：三档共用同一批词条，只是数值不同（§5.3）。
#   id / name / land / fmt / vals / extra / fn
#   `fmt % vals[tier]` 就是卡面一行说明；`extra` 只挂在**完美**档（§5.3 附带）。

static func _e(id: String, name: String, land: String, fmt: String, vals: Array,
		extra: String, fn: Callable) -> Dictionary:
	return {"id": id, "name": name, "land": land, "fmt": fmt, "vals": vals,
		"extra": extra, "fn": fn}


## 火力（FIRE）—— §5.4.1 原生 7 条。
static func _cat_fire() -> Array:
	return [
		_e("rifle_dmg", "枪管增压", "rifle_damage",
			"步枪伤害 +%d%%", [8, 18, 30], "穿透一层", _mulf(&"rifle_damage")),
		_e("rifle_rate", "供弹加速", "rifle_interval",
			"射击间隔 -%d%%", [8, 16, 25], "弹匣 +1", _subf(&"rifle_interval")),
		_e("rifle_mag", "弹仓扩容", "rifle_magazine",
			"弹匣 +%d 发", [1, 2, 4], "底火弹：弹匣最后一发伤害 +60%", _addi(&"rifle_magazine")),
		_e("funnel_load", "挂架增联", "funnel_per_shot",
			"一次扳机 %d 发", [4, 5, 6], "发射器冷却 -25%", _seti(&"funnel_per_shot")),
		_e("funnel_dmg", "聚能装药", "funnel_damage",
			"浮游伤害 +%d%%", [10, 22, 40], "过载装填：打空弹夹叠加伤害", _mulf(&"funnel_damage")),
		_e("vulcan_rate", "转膛提速", "vulcan_interval",
			"火神射速间隔 -%d%%", [10, 22, 35], "弹链不断：连续开火 2 秒后散布归零",
			_subf(&"vulcan_interval")),
		_e("grenade_dmg", "高爆装药", "grenade_damage",
			"榴弹伤害 +%d%%", [12, 25, 45], "爆炸范围 +20%", _mulf(&"grenade_damage")),
	]


## 装甲（ARMOR）—— §5.4.2 原生 6 条 + A7/A8/A9 修复包体系扩展（§5.7.5 P2）。
## ⚠️ 头 6 条的 `_hull_hp` / `_ifield_hp` 是**裸字段**（规矩 2）。
static func _cat_armor() -> Array:
	return [
		_e("hull", "装甲增厚", "_hull_hp",
			"机体耐久 +%d%%", [10, 22, 38], "受击后 2 秒减伤 15%", _mulf(&"_hull_hp")),
		_e("ifield", "立场扩容", "_ifield_hp",
			"I 立场 +%d%%", [12, 28, 50], "破盾时爆炸反击", _mulf(&"_ifield_hp")),
		_e("shield_cut", "举盾强化", "shield_reduction",
			"举盾减伤 +%d 个百分点", [3, 6, 10], "举盾冷却 -1.0 秒", _addpp(&"shield_reduction")),
		_e("reload", "快速换弹", "rifle_reload_time",
			"换弹时间 -%d%%", [10, 20, 35], "换弹时减伤", _subf(&"rifle_reload_time")),
		_e("turn", "姿态喷口", "turn_scale",
			"转向速率 +%d%%", [10, 22, 38], "转向不掉速", _mulf(&"turn_scale")),
		_e("jet_time", "燃料槽扩容", "jet_seconds",
			"能量槽时长 +%d%%", [15, 35, 60], "能量回复 +30%", _mulf(&"jet_seconds")),
		# ---- A7 / A8 / A9：**只扩展既有的修复包体系**，不新造任何东西（§5.7.5 P2）----
		_e("rep_packs", "修复包增备", "repair_packs",
			"每局修复包 %d 个", [4, 5, 6], "开局自带一个半血修复", _seti(&"repair_packs")),
		_e("rep_frac", "修复效率", "repair_fraction",
			"单个修复包回复 %d%%", [52, 64, 80], "修复期间减伤", _setf(&"repair_fraction")),
		_e("rep_time", "快修通道", "repair_time",
			"修复通道 %.1f 秒", [2.0, 1.5, 1.0], "修复不消耗修复包", _setf(&"repair_time")),
	]


## 机制（MECH）—— §5.4.3 去掉 `iff`（本模式是单人，那匹马没用）后剩 6 条，
## 其中 2 条的落点**已被真实消费**（`max_locks` / `clash_cooldown`），本轮只收这 2 条。
## ⚠️ 其余 4 条（锁定加速 / 拦截提前量 / 辅助预判 / 浮游自主索敌）要新建"倍率字段 + 接线"，
##    属 🟡 ⇒ 见文件头"本轮覆盖范围"。
static func _cat_mech() -> Array:
	return [
		_e("multi_lock", "多重锁定", "max_locks",
			"同时锁定 +%d", [1, 2, 3], "锁定组满员时首发伤害 +20%", _addi(&"max_locks")),
		_e("clash_win", "相杀窗口", "clash_cooldown",
			"相杀冷却 -%d%%", [20, 45, 80], "相杀后 1 秒内锁定加速 100%",
			_subf(&"clash_cooldown")),
	]


## 白刃（SABER）—— §5.9.3 S1~S6 + 既有 `saber_dmg` / `saber_reach` / M9 冲刺强化。
## ⚠️ 准入谓词是 `profile.has_saber`（§5.9.5）：古斯塔夫没有军刀 ⇒ 这张格对它关门。
static func _cat_saber() -> Array:
	return [
		_e("saber_dmg", "刀锋研磨", "saber_damage",
			"军刀伤害 +%d%%", [12, 25, 45], "命中回冲刺", _mulf(&"saber_damage")),
		_e("saber_reach", "延长刃", "saber_hit_range",
			"军刀命中长度 +%d%%", [10, 25, 45], "冲刺时间 +0.3 秒", _mulf(&"saber_hit_range")),
		_e("saber_cd", "连斩", "saber_interval",
			"军刀冷却 -%d%%", [19, 34, 50], "连斩：命中后 1.5 秒内再快 50%",
			_subf(&"saber_interval")),
		_e("saber_magnet", "磁吸锁定", "player_saber_magnet",
			"吸附距离 %.0f 米", [1800.0, 2400.0, 3200.0], "吸附瞬间减伤 20%",
			_setf(&"player_saber_magnet")),
		_e("saber_dash", "突进延长", "player_saber_dash_time",
			"突进时长 %.1f 秒", [2.9, 3.4, 4.0], "突进期间转向不减",
			_setf(&"player_saber_dash_time")),
		_e("saber_sweep", "判宽", "saber_sweep_radius",
			"扫掠判定半径 %.0f 米", [32.0, 39.0, 48.0], "扫掠命中判定半径 +20%",
			_setf(&"saber_sweep_radius")),
		_e("saber_close", "擦过即斩", "saber_min_closing",
			"命中所需接近速度 %.0f 米/秒", [40.0, 20.0, 0.0], "扫到即中",
			_setf(&"saber_min_closing")),
		_e("saber_grace", "空挥不空", "saber_miss_grace",
			"空挥宽限 %.1f 秒", [0.8, 1.2, 1.8], "空挥不进入冷却",
			_setf(&"saber_miss_grace")),
		_e("saber_dashspd", "冲刺强化", "saber_dash_speed",
			"冲刺速度 +%d%%", [25, 25, 25], "突进时长 +10%", _mulf(&"saber_dash_speed")),
	]


## 重炮（CANNON）—— §5.9.4 C1~C4 + `cannon_charge`（蓄能压缩）+ M7 装备减冷。
## ⚠️ 准入谓词是 `profile.cannon_enabled`（§5.9.5）：**柯西没有大炮** ⇒ 这格对它关门。
## ⚠️ `cannon_charge` 的落点**已按 §5.9.2 改正**：原表写 `cannon_duration`（光柱时长），
##    那等于"装了一张让大炮变弱的卡"；正确的语义是缩短**蓄力** ⇒ `cannon_charge_time`。
static func _cat_cannon() -> Array:
	return [
		_e("cannon_charge", "蓄能压缩", "cannon_charge_time",
			"蓄力时间 -%d%%", [15, 30, 45], "蓄力期间减伤 30%", _subf(&"cannon_charge_time")),
		_e("cannon_dps", "增幅装药", "cannon_dps",
			"光柱每秒伤害 +%d%%", [20, 45, 80], "光柱命中附带击退",
			_mulf(&"cannon_dps")),
		_e("cannon_dur", "持续照射", "cannon_duration",
			"光柱时长 +%d%%", [25, 55, 100], "光柱期间移动加速", _mulf(&"cannon_duration")),
		_e("cannon_cool", "装备减冷", "cannon_cooldown",
			"大炮冷却 -%d%%", [15, 30, 50], "冷却期间步枪射速 +25%",
			_subf(&"cannon_cooldown")),
		_e("cannon_oheat", "过热抑制", "cannon_overheat_reload",
			"用完后过热 -%d%%", [30, 55, 80], "过热期间仍可举盾",
			_subf(&"cannon_overheat_reload")),
		_e("cannon_rad", "加粗光柱", "beam_cannon_radius",
			"光柱判定半径 %.0f 米", [15.0, 18.0, 23.0], "光柱边缘仍按 80% 结算",
			_setf(&"beam_cannon_radius")),
	]


# ═══════════════════════ 激进档（RADICAL）：独立词条池 ═══════════════════════
#
# §5.10.3：激进档**不是**"同一批词条的第四级"，它是**另一批形状不同的词条** ——
# 每一条都长成「**失去某些能力 ⇒ 从而强化其他能力**」（用户点名的"亮出你的剑"形状）。
# ⇒ id 形如 `rad_*`，与上面九格（现在是十五格）**零重叠**；且**必须填 `cost` 列**。

static func _rad(id: String, name: String, cost: String, line: String, fn: Callable) -> Dictionary:
	return {"id": id, "name": name, "land": "radical:" + id, "cost": cost, "line": line, "fn": fn}


static func _cat_radical(t: int) -> Array:
	match t:
		Type.FIRE:
			return [
				_rad("rad_f1", "弃枪从刃", "失去光束步枪",
					"军刀伤害 +80%", func(p: SuitProfile) -> void:
						p.saber_damage *= 1.80
						p.rifle_count = 0),
				_rad("rad_f2", "裸装炮管", "弹匣 6 → 2",
					"步枪伤害 +70%", func(p: SuitProfile) -> void:
						p.rifle_damage *= 1.70
						p.rifle_magazine = 2),
				_rad("rad_f3", "一次全弹", "弹夹 150 → 45",
					"浮游一次扣板 9 发", func(p: SuitProfile) -> void:
						p.funnel_per_shot = 9
						p.funnel_count = 45),
			]
		Type.ARMOR:
			return [
				_rad("rad_a1", "弃盾", "失去 I 立场",
					"机体耐久 +60%", func(p: SuitProfile) -> void:
						p.set(&"_hull_hp", float(p.get(&"_hull_hp")) * 1.60)
						p.set(&"_ifield_hp", 0.0)),
				_rad("rad_a2", "裸机", "机体耐久 -40%",
					"I 立场 +120%", func(p: SuitProfile) -> void:
						p.set(&"_ifield_hp", float(p.get(&"_ifield_hp")) * 2.20)
						p.set(&"_hull_hp", float(p.get(&"_hull_hp")) * 0.60)),
				_rad("rad_a3", "无修复", "失去全部修复包",
					"举盾减伤 +45 个百分点", func(p: SuitProfile) -> void:
						p.repair_packs = 0
						p.shield_reduction = clampf(p.shield_reduction + 0.45, 0.0, 1.0)),
			]
		Type.MECH:
			return [
				_rad("rad_m1", "独锁", "同时锁定 3 → 1",
					"步枪伤害 +45%", func(p: SuitProfile) -> void:
						p.max_locks = 1
						p.rifle_damage *= 1.45),
				_rad("rad_m2", "短槽", "能量槽 8 → 4 秒",
					"能量槽回复速度 +120%", func(p: SuitProfile) -> void:
						p.jet_seconds = 4.0
						p.jet_recharge = p.jet_recharge * 2.2),
				_rad("rad_m3", "弃浮游", "失去浮游飞弹",
					"军刀与步枪伤害各 +45%", func(p: SuitProfile) -> void:
						p.has_missiles = false
						p.saber_damage *= 1.45
						p.rifle_damage *= 1.45),
			]
		Type.SABER:
			return [
				_rad("rad_s1", "断枪执刃", "失去光束步枪",
					"军刀伤害 +85% 且冷却 -30%", func(p: SuitProfile) -> void:
						p.rifle_count = 0
						p.saber_damage *= 1.85
						p.saber_interval *= 0.70),
				_rad("rad_s2", "轻装突进", "机体耐久 -35%",
					"突进时长 +80%，吸附距离 ×2", func(p: SuitProfile) -> void:
						p.set(&"_hull_hp", float(p.get(&"_hull_hp")) * 0.65)
						p.player_saber_dash_time *= 1.80
						p.player_saber_magnet *= 2.0),
			]
		Type.CANNON:
			return [
				_rad("rad_c1", "弃刃重炮", "失去光束军刀",
					"光柱每秒伤害 +90%", func(p: SuitProfile) -> void:
						p.has_saber = false
						p.cannon_dps *= 1.90),
				_rad("rad_c2", "超载炮管", "弹匣 6 → 2，I 立场 -50%",
					"大炮冷却与过热各 -60%", func(p: SuitProfile) -> void:
						p.rifle_magazine = 2
						p.set(&"_ifield_hp", float(p.get(&"_ifield_hp")) * 0.50)
						p.cannon_cooldown *= 0.40
						p.cannon_overheat_reload *= 0.40),
			]
		_:
			return []


# ═══════════════════════════ 对外接口 ═══════════════════════════

## 某个类型的全部词条（三档共用）。**每次调用都新建** ⇒ 卡对象不复用、可安全改写。
static func entries_of(t: int) -> Array:
	match t:
		Type.FIRE: return _cat_fire()
		Type.ARMOR: return _cat_armor()
		Type.MECH: return _cat_mech()
		Type.SABER: return _cat_saber()
		Type.CANNON: return _cat_cannon()
	return []


static func _card_from(e: Dictionary, t: int, tier: int) -> UpgradeCard:
	var c := UpgradeCard.new()
	c.type = t
	c.tier = tier
	c.id = str(e["id"])
	c.name = str(e["name"])
	c.land = str(e["land"])
	var v := float(e["vals"][tier])
	c.line = str(e["fmt"]) % v
	var ex := str(e.get("extra", ""))
	if tier == Tier.PERFECT and ex != "":
		c.line += "（附带：" + ex + "）"
	var fn: Callable = e["fn"]
	c.apply = func(p: SuitProfile) -> void:
		fn.call(p, v)
	return c


static func _radical_card(e: Dictionary, t: int) -> UpgradeCard:
	var c := UpgradeCard.new()
	c.type = t
	c.tier = Tier.RADICAL
	c.id = str(e["id"])
	c.name = str(e["name"])
	c.land = str(e["land"])
	c.cost = str(e["cost"])
	c.line = str(e["line"])
	c.apply = e["fn"]
	return c


## **唯一芯片库真源**：取一个格子 `(type, tier)` 的全部卡。
## ⇒ 5 类型 × 4 品质 = **20 格**，每格非空（§13 `POOL`）。
static func pool_of(t: int, tier: int) -> Array[UpgradeCard]:
	var out: Array[UpgradeCard] = []
	if tier == Tier.RADICAL:
		for e in _cat_radical(t):
			out.append(_radical_card(e, t))
		return out
	for e in entries_of(t):
		out.append(_card_from(e, t, tier))
	return out


## 全库（判据遍历用）。
static func all_cards() -> Array[UpgradeCard]:
	var out: Array[UpgradeCard] = []
	for t in TYPE_COUNT:
		for tier in TIER_COUNT:
			out.append_array(pool_of(t, tier))
	return out


## **能力谓词准入**（§5.9.5）：卡要对"没有这件装备的机体"关门。
## 用谓词（`has_saber` / `cannon_enabled`）而**不是机体名单** ——
## 写死名字的话，将来加机体必忘改，而漏改的后果是"发了空卡还不报错"。
static func viable_for(card: UpgradeCard, p: SuitProfile) -> bool:
	if p == null:
		return false
	match card.type:
		Type.SABER:
			return p.has_saber
		Type.CANNON:
			return p.cannon_enabled
	return true


# ───────────────────────── ★63-24：给"开局自选"用的两个入口 ─────────────────────────
#
# 主菜单的开局配置页（`MainMenu._draw_endless_stage()`）与 `main._apply_endless_cards()`
# 都要问同一件事："这一台机的**基础档**卡池里有哪些卡"。抽到这里来只有一个理由：
# **别在菜单里再抄一份卡名单**。抄一份就会有两份真源 —— 加了新词条、菜单里看不到，
# 而"看不到"不报错（设计 §11.1 第 8 条原本写的是 `const ENDLESS_CARDS` 池，
# 那是数据层落地（★63-24）之前的写法，现在这个函数取代它）。

## **基础档卡池**（设计 §5.6）：5 类型 × `BASIC` 档，按能力谓词过滤。
##
## ⚠️ 过滤用的是"**这一台机的** profile"，所以同一个玩家的机体换了，池子也跟着换 ——
## 柯西的池里没有重炮卡、佩涅罗佩的池里有（`cannon_enabled`）。这正是 §5.9.5 要的。
static func basic_pool(p: SuitProfile) -> Array[UpgradeCard]:
	var out: Array[UpgradeCard] = []
	for t in TYPE_COUNT:
		for c in pool_of(t, Tier.BASIC):
			if viable_for(c, p):
				out.append(c)
	return out


## 按 `id` 在**某个档**的全库里反查一张卡。找不到返回 `null`。
##
## ⚠️ 为什么要带 `tier` 参数：`id` 是**词条**的名字（`"rifle_dmg"`），
## 而同一词条在三个档各有一张卡（数值不同）⇒ 只按 id 查会拿到**第一档**那张，
## 于是"玩家自选的完美卡"会在施加时**静默退化成基础卡**。
static func by_id(cid: String, tier: int = Tier.BASIC) -> UpgradeCard:
	for t in TYPE_COUNT:
		for c in pool_of(t, tier):
			if c.id == cid:
				return c
	return null
