class_name Damage
extends RefCounted
## 伤害类型与 I 立场的**吸收效率**表。
##
## 单独放一个文件而不是塞进 FlightBody，是为了避免
## Projectile / Missile / FlightBody 之间出现循环 class_name 引用
## （GDScript 的全局类解析遇到环会直接报 "could not resolve class"）。
##
## ## 规则（第四轮确认版）
## **I 立场没扣完之前，机体一滴血都不能掉。** 所有伤害都先打进护盾。
##
## 那么这张表代表什么？——**吸收效率**，也就是"1 点护盾值能吃掉多少点伤害"：
##   - 1.00（光束步枪）：1 点护盾值吃 1 点伤害，最省
##   - 0.70（火神炮 / 浮游导弹）：1 点护盾值只吃 0.7 点，
##     也就是护盾消耗快 1/0.7 ≈ 1.43 倍
##   - 0.45（光束军刀）：消耗快 2.2 倍 —— 军刀是**破盾最快**的手段，
##     但它同样不穿盾（早期版本里军刀直接穿盾，与"护盾没扣完不掉血"冲突，已改）
##   - 0.50（撞击）
##
## 需求原文写的是"对光束步枪 100% 减伤、对火神炮和浮游导弹 70% 减伤"。
## 在"护盾未破不掉血"的前提下，那个百分比唯一还能表达的含义就是**护盾的消耗速度**，
## 所以这里把它实现成效率而不是减伤率 —— 否则 70% 减伤会让 30% 漏到机体，
## 与"护盾没扣完不掉血"直接矛盾。

enum Type { BEAM, VULCAN, FUNNEL, SABER, RAM, BEAM_CANNON }

const IFIELD_EFFICIENCY := {
	Type.BEAM: 1.00,
	Type.BEAM_CANNON: 1.00,
	Type.VULCAN: 0.70,
	Type.FUNNEL: 0.70,
	Type.SABER: 0.45,
	Type.RAM: 0.50,
}

const LABEL := {
	Type.BEAM: "光束步枪",
	Type.BEAM_CANNON: "光束大炮",
	Type.VULCAN: "火神炮",
	Type.FUNNEL: "浮游导弹",
	Type.SABER: "光束军刀",
	Type.RAM: "撞击",
}


## 吸收效率。永远 > 0，所以 take_damage 里不需要防除零。
static func ifield_efficiency(type: int) -> float:
	return maxf(IFIELD_EFFICIENCY.get(type, 0.5), 0.05)


static func label(type: int) -> String:
	return LABEL.get(type, "?")


## 吸收一发需要消耗多少护盾值（HUD 与测试都用得到）。
static func ifield_cost(amount: float, type: int) -> float:
	return amount / ifield_efficiency(type)


## Every attacker uses the same matchup bonus, before shield/pedal routing.
static func funnel_target_multiplier(suit_id: int, type: int) -> float:
	if type == Type.FUNNEL and suit_id in [SuitProfile.Id.MESSER_M01, SuitProfile.Id.MESSER_CMD, SuitProfile.Id.MESSER_F01, SuitProfile.Id.GUSTAV00]:
		return 3.0
	return 1.0
