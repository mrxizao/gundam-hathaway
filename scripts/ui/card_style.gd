class_name CardStyle
extends RefCounted
## ★63-24「无限强化演习」· **改装芯片的配色真源**。
##
## ## 为什么单开一个文件
##
## 这套颜色原本只写在 `MainMenu.card_color()` 里（配置页那一排勾选行要用）。
## 局内三选一面板（`FlightHUD._draw_endless_intermission()`）要画**同一批芯片**
## ⇒ 颜色就有了第二个消费方。于是只有两条路：
##   ① 在 HUD 里再抄一份 `match` ⇒ **两份真源**：改一处另一处不动，而**不报错**；
##   ② 提到一个两边都读的地方 ⇒ 就是本文件。
##
## 走 ② 而不是把颜色塞进 `UpgradeCard`（数据层）：配色是**界面**的事，
## 数据层不该为了画图依赖 `Color`。工程里已经有同形状的先例 ——
## `UILayout` 就是"菜单与 HUD 都要用的那份界面真源"。
##
## ⚠️ `MainMenu.card_color()` **保留原签名**（判据 `suite_endless` 的 5 色那一条
## 直接查它），但函数体改成转调这里 —— 于是"菜单那一侧没变"，而真源只有一份。

## 芯片五类型各有各的颜色。
##
## 抽成静态函数（而不是在绘制里内联一个 `match`）只有一个理由：**可测** ——
## 判据能直接查"5 类各有各的颜色"，而不是去截图里找色块。
static func type_color(ty: int) -> Color:
	match ty:
		UpgradeCard.Type.FIRE:
			return Color(1.00, 0.58, 0.40)
		UpgradeCard.Type.ARMOR:
			return Color(0.54, 0.82, 1.00)
		UpgradeCard.Type.MECH:
			return Color(0.70, 0.95, 0.60)
		UpgradeCard.Type.SABER:
			return Color(1.00, 0.86, 0.42)
		UpgradeCard.Type.CANNON:
			return Color(0.82, 0.68, 1.00)
	return Color(0.72, 0.82, 0.94)


## 芯片四品质的配色（奖励轮**恒** `PERFECT`，所以这一列在局内会亮得很显眼）。
##
## ⚠️ 与 `type_color()` **必须是两套**：类型在**卡名左边**、品质在**卡名右边**，
## 两个维度同时出现在一行里。用同一套色的话，"这张是什么类型"与"这张多好"
## 会长得一模一样 —— 而三选一里玩家最先要判断的恰恰是**后者**。
##
## `BASIC` 刻意用**低饱和灰**：它是"没有额外加成"的那一档，
## 和 `ADVANCED` 放在一起时必须一眼看出"这张是垫底的"。
static func tier_color(tier: int) -> Color:
	match tier:
		UpgradeCard.Tier.BASIC:
			return Color(0.62, 0.70, 0.78)
		UpgradeCard.Tier.ADVANCED:
			return Color(0.52, 0.92, 0.70)
		UpgradeCard.Tier.PERFECT:
			return Color(1.00, 0.84, 0.38)
		UpgradeCard.Tier.RADICAL:
			return Color(1.00, 0.42, 0.62)
	return Color(0.72, 0.82, 0.94)


## 品质的**底纹**（画在徽标方块上，字压在它上面）。
##
## 与 `tier_color()` 分开：徽标是"色块 + 深色字"，直接用 `tier_color()` 当底、
## 再用 `HUD` 绿写字会糊成一片；这里给的是同色系压暗过的那一版。
static func tier_bg(tier: int) -> Color:
	return Color(tier_color(tier), 0.22)
