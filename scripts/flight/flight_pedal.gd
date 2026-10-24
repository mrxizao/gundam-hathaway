class_name FlightPedal
extends Node3D
const SUIT_MATERIALS = preload("res://scripts/flight/suit_materials.gd")
var _material_cel_mode := false
## **飞行踏板**（1.2）—— 机体的骑乘推进平台，能**载两台**。
##
## ## 它是什么
## 脚下的独立平台：机体踩在上面赶路，**油门响应更快**，但**转向变钝、不能用光束军刀、
## 不能悬停**；平台自己有耐久，**被打爆之后骑手会被抛出去并短暂失能**。
## 于是它给玩家的不是"多一个按钮"，而是**一个新的射击目标**：
## 把敌机从踏板上打下来，再打它本人。
##
## ## 一块板 = 一对（1.2 用户指定）
## 「马夫蒂的飞行踏板是**前后两台梅萨**，喀耳刻部队的飞行踏板是**前后两台古斯塔夫**」
## —— 所以踏板**不是单人坐骑，是"一队的载具"**：一台领机（`riders[0]`，板挂在他身上、
## 他正常飞）+ 一台被载机（`riders[1]`，**运动学贴**在挂位上，自己不做气动）。
##
## ⚠️ **为什么被载的那台不做气动**：两台机各自做气动的话，两套独立的
## `velocity/速度` 状态永远在互相追——推进/减速/AI 决策各偏一点，
## 几十秒后就是"一台在前面飞、一台在后面追"，看起来完全不像"站在同一块板上"。
## 所以被载机用**运动学**方式贴合（`FlightBody.set_carried_by()` 每帧读领机的位姿），
## 和联机里的 `NetProxyBody` 是同一个思路。
##
## ## 挂位（前后纵列）
## `slot_offset()` 给的是**骑手局部坐标**（X 左右 / Y 上下 / Z 前后，
## 正面朝 −Z），所以换模型缩放不用改这里。
##
## ⚠️ 前后间距是按"**两块板的 Z 跨度**"分别给的，不是拍脑袋：
##   马夫蒂板 Z 跨度 0.7632 → 7.0 m 高时全长约 17.5 m，两块 22 m 的机体**放不下**，
##     所以只能取小间距（对叠一点，视觉上可接受）；
##   喀耳刻板 Z 跨度 0.9390 → 全长约 20.8 m，明显更长。
## 这是**已知的将就**：真正的"前后两台不重叠"需要把踏板缩放调大，
## 而那会连带影响挂高与观感，留给"阵营小队"那一轮连同编队一起定。
##
## ## 模型
## - 马夫蒂：`mafty_base_jabber.glb`（实测 0.9995 × **0.3062** × 0.7632 · **180** 网格）
## - 喀耳刻：`kilce_base_jabber.glb`（实测 0.9712 × **0.3159** × 0.9390 · **233** 网格）
##
## 两块都出过四方位图：不散架、带材质、正面朝 −Z。
## 喀耳刻板逐层扫描显示**最低 6 层是窄件**（约 0.095 的起落架/鳍），
## 所以它的包围盒底比真正的地面线低一点 —— 挂位是按包围盒算的，偏差落在空隙里。
##
## ## 谁骑哪块（按阵营）
## 马夫蒂方的机体（柯西 / 阿利宙斯 / 梅萨M01）→ 马夫蒂踏板；
## 其余（佩涅罗佩 / 古斯塔夫00）→ 喀耳刻部队踏板。

## 骑乘期间的伤害分配：**进踏板的份额**。
##
## ⚠️ 这个数是"打踏板值不值"的旋钮，不是手感数：
##   - 太大（1.0）⇒ 踏板变成一层额外血条，玩家必须先打掉它才能伤到人，变成解谜；
##   - 太小（0.2）⇒ 没人会去瞄它，"打踏板"这个动作不存在。
## 0.7 的意图是：**专心打踏板能在 3~5 秒内打掉，但不管它的话机体照样在掉血** ——
## 于是"打不打踏板"是一个真选择，而不是唯一解。
const PEDAL_SHARE := 0.7

## ---- 两种板 ----
#
# ⚠️ **两块板各配一套"出击"模型**（2026-09-20 用户提供）：
#   马夫蒂踏板 → `梅萨出击！.glb`   = 踏板 + **两台梅萨并排**
#   喀耳刻踏板 → `古斯塔夫出击！.glb` = 踏板 + **两台古斯塔夫并排**
#
# 也就是说**成套模型里已经排好了两台机体的位置**，不需要我们在代码里摆。
# 所以本类的做法是：**整套挂上去当一只"载具"用**（`USE_DEPLOYED_MODEL`），
# 而**两台机体的战斗逻辑仍然是两台独立的 `FlightBody`** ——
# 图形交给用户的模型，判定/伤害/失能仍走各自的机体。
#
# 实测（`tools/probe_model.tscn`，见 §10 落地记录）：
#   梅萨出击     2.9292 × **1.6445** × 2.2366 · **494** 网格
#   古斯塔夫出击 1.8422 × **1.0957** × 1.7811 · **666** 网格
# 注意那两个 Y 是**整套**（踏板+两台机）的高度，不是单台机体的高度。
## ## ⚠️ `MESSER_CMD` **必须加在末尾**（2026-09-30 · N62）
##
## 中间插值会改掉 `KILCE` 的数值。源码里没有硬编码数字，但没有理由动它。
##
## ## 为什么梅萨指挥官型要单独一块板
##
## 踏板的分状态模型（`pedal_states/*.glb`）是**按阵营把手/机体烤死**的：
## `mafty_*` 里烤的是**量产型 M01**。指挥官型在 2026-09-29（N58）才挂进工程，
## 沿用了马夫蒂板 ⇒ **指挥官型骑板时画出来的是量产型**（机型与涂装都不对），
## F01 型同理（但用户裁决只给指挥官型开新板，F01 仍用马夫蒂板）。
##
## 用户为此专门做了一份「指挥官型乘坐踏板」的模型；本类据此开第三种板。
## **板本体与马夫蒂是同一块**（`messer_cmd_*` 里的踏板逐件等价于 `mafty_empty`），
## 差别只在烤进去的机体 —— 所以 `EMPTY_NATIVE` / `LOADED_NATIVE` /
## `STATE_RIDER_POS` / `MODEL_YAW_DEG` 四项与 MAFTY **同值**。
enum Kind { MAFTY, KILCE, MESSER_CMD, ODYSSEUS, GUSTAV_SINGLE }

const MODEL_MAFTY := "res://assets/models/pedal/mafty_base_jabber.glb"
const MODEL_KILCE := "res://assets/models/pedal/kilce_base_jabber.glb"
## 成套"出击"模型（踏板 + 两台机体）。
const MODEL_DEPLOYED_MAFTY := "res://assets/models/deployed/messer_m01_deployed.glb"
const MODEL_DEPLOYED_KILCE := "res://assets/models/deployed/gustav_deployed.glb"
## 模型自身高度（`tools/probe_model.tscn` 实测值）。
## 与 `target_height_of()` 的返回值**成对**：改模型必须重跑探针。
const NATIVE_HEIGHT_MAFTY := 0.3062
const NATIVE_HEIGHT_KILCE := 0.3159
## 指挥官型与马夫蒂**同一块板** ⇒ 三项原生尺寸与 MAFTY 逐位相同（实测复核）。
const NATIVE_HEIGHT_MESSER_CMD := 0.3062
const NATIVE_HEIGHT_DEPLOYED_MAFTY := 1.6445
const NATIVE_HEIGHT_DEPLOYED_KILCE := 1.0957
## 模型自身**长轴**（X）的原生尺寸（实测）。
##
## ⚠️ 踏板是一条**长平台**，它的 X 才是"多大"的尺度 —— 最短轴 Y 只是厚度。
const NATIVE_LENGTH_MAFTY := 0.9995
const NATIVE_LENGTH_KILCE := 0.9712
const NATIVE_LENGTH_MESSER_CMD := 0.9995

## **踏板长度 ÷ 骑手全高**。这是"踏板该多大"的唯一定义式，实测自用户给的两组
## "出击"合集（那两份模型就是官方给出的搭载方式）：
##
## | 合集 | 踏板长（X） | 机身高（Y） | 比值 |
## |---|---|---|---|
## | 马夫蒂 | 2.9292 | 1.2384 | **2.365** |
## | 联邦 | 1.8422 | 0.7388 | **2.494** |
##
## 取两者平均 **2.43**。两侧踏板的缩放是**等比**的（套装 ÷ 单体 = 2.930 / 1.897，
## 三轴一致），所以拿比值反推是安全的。
##
## ## ⚠️ 这一条推翻了我原来那个推导（用户实测报"飞行踏板太小"）
##
## 原来我写的是「套装 1.6445 高，其中踏板 0.3062 高 ⇒ 踏板只占 18.6%，
## 翻到游戏里 ≈ 7.0 m」。**那个前提是错的**：0.3062 是**单体踏板**的厚度，
## 而套装里的踏板是缩放 2.93× 之后的 **0.8972**。
## 于是我把"单体踏板"和"套装里的踏板"当成了同一个东西，
## 算出 7.0 m（板长 22.9 m ≈ 机体全高）—— 而正确值是它的 **2.4 倍**。
const PEDAL_LENGTH_RATIO := 2.43

## 同一编队两位骑手沿踏板**长轴**的间距 ÷ 踏板长度。
##
## 实测自同一个合集：马夫蒂 0.8108/2.9292 = 0.2768，联邦 0.5305/1.8422 = 0.2880
## ⇒ 取 **0.28**。两位骑手是**并排**（用户明确纠正过："并排"不是前后）。
const SLOT_SPREAD_RATIO := 0.28

## 一个机体在游戏里的标准全高（米）。用户给的参考值。
##
## ⚠️ 它是**踏板的缩放锚点**：`loaded_scale_of()` 让载人模型里的骑手正好这么高，
## 于是"踏板多大"是从**机体的绝对尺寸**推出来的结论，而不是反过来。
##
## ⚠️⚠️ **它与机体表的 `target_height = 22.0` 差 1.0 m（4.55%）—— 已知、刻意保留，不是笔误。**
## 两个数**量的不是同一件事**：
##   · 这里是**用户给的名义全高 23 m**，作用是"踏板这个资产的缩放锚"。动它会
##     把踏板连同**嵌在模型里的那位骑手**整体缩放 4.35%（`LOADED_NATIVE` /
##     `STATE_RIDER_POS` 都是原生量，按比例跟着走）—— 那是玩家**看得见的板子大小**变化，
##     不在任何一轮的需求里，所以不许顺手对齐；
##   · `SuitProfile.target_height = 22.0`（古斯塔夫 00 / 梅萨 M01 / 阿利宙斯某形态）是
##     **按各自模型包围盒反推**的缩放值，被 `suite_round` 的"包围盒 ≈ target_height"钉着，
##     那头也不能改。
##
## ⇒ 现状的**代价**（已知、可接受）：脱板那一刻，嵌在板模型里的骑手比真机体高 4.55%，
##    会看到一点点尺寸跳变。
## ⇒ **收口方案（未采纳，留给后续轮拍板）**：把这里改成 22.0 ⇒ 板与嵌入骑手整体缩 4.35%。
##    判据在 `tests/suite_pedal_call.gd` 的「尺寸口径」那三条：两个数都钉着，
##    谁动了其中一个，回归就会点名。
const SUIT_GAME_HEIGHT := 23.0

## 这块板当前的**可视状态**（1.2 第二十四轮：用户给了整套分状态模型）。
##
## ## 为什么用"分状态模型"而不是"一块板 + 各自画骑手"
##
## 用户的方案是：「正常双击搭乘状态就**直接用** `梅萨出击！` / `古斯塔夫出击！`
## 的模型」，并且按"脱落的是几号机"切换成对应模型：
##   两台都在 → 出击合集（两台）；
##   只剩一号机 → 「只有前面/左边」那个；
##   只剩二号机 → 「只有后面/右边」那个；
##   都脱落   → 空板模型。
##
## 这正好解开了我当初**否决套装模型**的三条理由：
##   ① 叠影 —— 现在**按需隐藏骑手自己的模型**；
##   ② 打不掉的"影子" —— 现在分状态模型会**跟着脱落切换**；
##   ③ 不能独立开火/脱板 —— 判定仍然是两台独立 `FlightBody`，模型只是外观。
##
## ⚠️ **模型的"座次"与阵营有关**（用户指定）：
##   马夫蒂：一号机 = **前**、二号机 = **后**；
##   喀耳刻：一号机 = **左**、二号机 = **右**。
## 实测两族的座位**都沿模型局部 X 分开**，靠各自不同的朝向修正
##（`MODEL_YAW_DEG`）变成"前后"与"左右"。
enum Vis { EMPTY, SLOT0_ONLY, SLOT1_ONLY, BOTH }

## 各状态的模型路径。
const STATE_MODEL := {
	Kind.GUSTAV_SINGLE: {
		Vis.EMPTY: "res://assets/models/pedal_states/kilce_empty.glb",
		Vis.SLOT0_ONLY: "res://assets/models/gustav_single/mounted.scn",
		Vis.SLOT1_ONLY: "res://assets/models/gustav_single/mounted.scn",
		Vis.BOTH: "res://assets/models/gustav_single/mounted.scn",
	},
	Kind.ODYSSEUS: {
		Vis.EMPTY: "res://assets/models/odysseus_pedal/empty.scn",
		Vis.SLOT0_ONLY: "res://assets/models/odysseus_pedal/mounted.scn",
		Vis.SLOT1_ONLY: "res://assets/models/odysseus_pedal/mounted.scn",
		Vis.BOTH: "res://assets/models/odysseus_pedal/mounted.scn",
	},
	Kind.MAFTY: {
		Vis.EMPTY: "res://assets/models/pedal_states/mafty_empty.glb",
		Vis.SLOT0_ONLY: "res://assets/models/pedal_states/mafty_front.glb",
		Vis.SLOT1_ONLY: "res://assets/models/pedal_states/mafty_back.glb",
		Vis.BOTH: "res://assets/models/pedal_states/mafty_both.glb",
	},
	Kind.KILCE: {
		Vis.EMPTY: "res://assets/models/pedal_states/kilce_empty.glb",
		Vis.SLOT0_ONLY: "res://assets/models/pedal_states/kilce_left.glb",
		Vis.SLOT1_ONLY: "res://assets/models/pedal_states/kilce_right.glb",
		Vis.BOTH: "res://assets/models/pedal_states/kilce_both.glb",
	},
	Kind.MESSER_CMD: {
		# ⚠️ 空板**复用马夫蒂那份** —— 板本体本来就同一块，
		# 复制一份只是多 4 MB 重复资产（`mafty_empty` 与 `mafty_base_jabber` 逐字节相同）。
		Vis.EMPTY: "res://assets/models/pedal_states/mafty_empty.glb",
		Vis.SLOT0_ONLY: "res://assets/models/pedal_states/messer_cmd_front.glb",
		Vis.SLOT1_ONLY: "res://assets/models/pedal_states/messer_cmd_back.glb",
		Vis.BOTH: "res://assets/models/pedal_states/messer_cmd_both.glb",
	},
}

## **空板**模型里踏板本体的原生尺寸（实测）。
const EMPTY_NATIVE := {
	Kind.GUSTAV_SINGLE: Vector3(0.9712,0.3159,0.9390),
	Kind.ODYSSEUS: Vector3(1.84220113,0.72855864,1.78108599),
	Kind.MAFTY: Vector3(0.9995, 0.3062, 0.7632),
	Kind.KILCE: Vector3(0.9712, 0.3159, 0.9390),
	Kind.MESSER_CMD: Vector3(0.9995, 0.3062, 0.7632),
}
## **载人**模型里"踏板那一段"的原生尺寸（实测）。长轴就是第一项。
const LOADED_NATIVE := {
	Kind.GUSTAV_SINGLE: Vector3(1.842201,0.599257,1.781086),
	Kind.ODYSSEUS: Vector3(1.84220113,0.72855864,1.78108599),
	Kind.MAFTY: Vector3(2.9292, 0.8972, 2.2366),
	Kind.KILCE: Vector3(1.8422, 0.5993, 1.7811),
	Kind.MESSER_CMD: Vector3(2.9292, 0.8972, 2.2366),
}
## **载人**模型里"骑手那一台"的原生全高（实测）。
##
## ⚠️ 指挥官型在 `messer_cmd_*` 里是**按这个值反推缩放生成的**
##（`1.3032 / 0.9756 = 1.33579`，0.9756 = `messer_cmd.glb` 的世界 AABB 高）。
## 两条路都通向 1.3032 ⇒ 与 M01 在板上**等高**（都归一到 `SUIT_GAME_HEIGHT`）。
const RIDER_NATIVE_H := {
	Kind.GUSTAV_SINGLE: 0.738764,
	Kind.ODYSSEUS: 0.88181063,
	Kind.MAFTY: 1.3032,
	Kind.KILCE: 0.7388,
	Kind.MESSER_CMD: 1.3032,
}
## 两位骑手在**载人模型**里的原生**中心点**（实测）。
## 索引 0 = 一号机（−X 侧）、索引 1 = 二号机（+X 侧）。
const STATE_RIDER_POS := {
	Kind.GUSTAV_SINGLE: [Vector3(-0.01334074,0.3812905,0.22178435)],
	Kind.ODYSSEUS: [Vector3(0.00856403,0.46848234,0.29439365)],
	Kind.MAFTY: [Vector3(-0.3085, 0.5188, 0.0082), Vector3(0.5023, 0.5443, -0.0372)],
	Kind.KILCE: [Vector3(-0.3182, 0.3813, 0.2264), Vector3(0.2123, 0.3738, 0.2078)],
	Kind.MESSER_CMD: [Vector3(-0.3085, 0.5188, 0.0082), Vector3(0.5023, 0.5443, -0.0372)],
}


## 载人状态的缩放：**让模型里的骑手正好 `SUIT_GAME_HEIGHT` 高**。
##
## ⚠️ 锚点选"骑手全高"而不是"踏板长度"：骑手是玩家操作的那台机，
## 它的尺寸必须是一个**已知的绝对值**；踏板多大是**跟着模型走的结论**，
## 不该反过来把踏板当成锚（那样"骑手多大"就变成了模型比例的副产品）。
static func loaded_scale_of(k: int) -> float:
	return (26.0 if k == Kind.ODYSSEUS else SUIT_GAME_HEIGHT) / float(RIDER_NATIVE_H.get(k, 1.0))


## 空板状态的缩放：**让空板与载人板的世界尺寸一致**。
##
## ⚠️ 必须单独算：空板与载人板的原生尺度**差一倍多**
##（马夫蒂 0.9995 vs 2.9292、喀耳刻 0.9712 vs 1.8422）。
## 不分别缩放的话"人一下板，板会突然缩小"。
static func empty_scale_of(k: int) -> float:
	var e: Vector3 = EMPTY_NATIVE.get(k, Vector3.ONE)
	var l: Vector3 = LOADED_NATIVE.get(k, Vector3.ONE)
	if e.x <= 0.0:
		return loaded_scale_of(k)
	return loaded_scale_of(k) * (l.x / e.x)


## 某个可视状态下这块板该缩放到多少倍。
static func state_scale_of(k: int, vis: int) -> float:
	return empty_scale_of(k) if vis == Vis.EMPTY else loaded_scale_of(k)


## 某个状态模型的原生尺寸（厚度的两倍关系都在这上面）。
static func state_native_of(k: int, vis: int) -> Vector3:
	return EMPTY_NATIVE.get(k, Vector3.ONE) if vis == Vis.EMPTY \
		else LOADED_NATIVE.get(k, Vector3.ONE)


## 是否使用成套"出击"模型（**已关闭** —— 见下面那段教训）。
##
## ## ⚠️ 为什么最终**不用**这两份套装模型（2026-09-20 实测结论）
##
## 用户给的 `梅萨出击！.glb` / `古斯塔夫出击！.glb` 是**踏板与两台机体烤在一起的
## 单一网格**（494 / 666 个 MeshInstance3D）。一开始我把它整份挂上去当"载具"，
## 并把两位骑手自己的模型藏掉 —— 结果有三个致命问题：
##
##   ① **歪**：整套挂在**领机**身上，领机的姿态变化会带着整套一起转，
##      而套装模型自身的轴心在踏板中心，所以编队看起来是斜的；
##   ② **打不掉的影子**：打完一台之后，另一台还"藏"在套装模型里 ——
##      玩家看到两台，但只有一台能被击中；
##   ③ **不能混编**：用户要的是"两台机体各自操控自己的武装"，
##      而烤死的网格无法让两台独立开火/独立脱落。
##
## 用户后来也明确了：「我给梅萨出击和古斯塔夫出击的模型**只是让你参考
## 每个踏板该缩放多大**，古斯塔夫高 23 米梅萨也高 23 米，二者一样大的情况下
## 你自己调整游戏内踏板缩放和在踏板上的排列方式」。
##
## **所以最终做法**：踏板用**单独的踏板模型**（`mafty_base_jabber` /
## `kilce_base_jabber`），两台骑手**各带自己的模型**并排站在上面。
## 套装模型只用来**反推踏板该多大**（见 `PEDAL_GAME_HEIGHT`）。
const USE_DEPLOYED_MODEL := false

## 一台机体在挂位上的横向间距（**米**，正负各一个）。
##
## ⚠️ **用户给的是"并排"不是"前后"** —— 四方位渲染确认：
## `梅萨出击！` 里两台梅萨是**左右并立**站在踏板上的（前视能看到两台胸部并排）。
## 所以挂位沿 **X** 分开，不是沿 Z。
##
## ## ⚠️ 这一条被推翻过一次（1.2 第二十二轮：踏板尺寸修正）
##
## 原来这里写的是**绝对米数 9.0**，理由"间距由机体宽度决定、与踏板多宽无关"。
## 那个理由本身站得住，但当时**踏板本身算错了（只有 22.9 m 长）**，
## 于是 9.0 m 的间距在视觉上是对的、而板太小。
## 板按官方合集修正到 ~56 m 之后，**间距必须跟着板走**，
## 否则两台会挤在板中央、两侧空出一大片（实测截图确认）。
##
## 现在改用 `SLOT_SPREAD_RATIO`（实测 0.28）× 板长 —— 见 `slot_spread_m()`。
## 保留这个名字只为了让"旧调用点/测试"还能读到间距的**当值**。
const SLOT_SPREAD_X_M := 9.0
## 被载机该贴在挂位上的**哪个高度**（占整套高度的比例，从模型底往上）。
##
## 两台机是**站在甲板上**的，所以贴合点在踏板顶面之上一点。
## 46% 是从 `梅萨出击！` 的逐层扫描估的：宽件（= 两台机体的腿脚）从
## 约 −0.12 开始一直往上，而踏板那一段在最低的 0.449 里。
const SLOT_LIFT_RATIO := 0.46
## 成套"出击"模型里**机体脚的高度**（原生 y，实测值）。
##
## 怎么来的：`tools/probe_model.tscn` 的逐层扫描里，`梅萨出击！` 的宽件
## （= 两台机体的腿与脚）从第 4 层 y ≈ **−0.12** 开始连续到第 10 层；
## 下面那 4 层（−0.449 ~ −0.12）是踏板本体。所以 −0.12 就是"脚踩在甲板上"那条线。
const DEPLOYED_FOOT_Y := -0.12
## 骑手脚下留的空隙（米）——只在**单踏板模型**模式（`USE_DEPLOYED_MODEL = false`）下用。
const FOOT_GAP := 0.8

## 踏板耐久基数。实际值 = `max_hp`（由 `FlightBody.configure_pedal()` 按骑手耐久给）。
##
## ⚠️ 一块板载两台、两台的伤害都打进**同一份耐久**（见 `FlightBody.pedal_hp_pool()`），
## 所以这个系数是"一对的总耐受"：0.62 意味着打掉它大约等于打掉领机六成耐久。
const HP_RATIO := 0.62
## 骑乘期间的**油门响应**倍率（加速 / 加力加速 / 减速三项一起乘）。
##
## ## ⚠️ 这里为什么不给"最高速加成"（这是本轮最要紧的一个设计决定）
##
## 第一版给的是 `RIDE_SPEED_MUL = 1.25`（最高速 ×1.25），结果**当场顶穿了
## 第十四轮那条回归门**：`suite_round` 与 `suite_round14` 都断言
## "敌机上限 ≤ 玩家加力上限 ×0.92"，而 1.25 倍的骑板敌机必然越线
## （实测 724.5 > 580.1，两条断言同时红）。
##
## 那条天花板不是随手写的数，它是**玩家实测"怎么追都追不上"的修复**：
## 中等难度佩涅罗佩 737 m/s vs 玩家柯西加力 630 m/s。给敌机一个能顶穿它的
## 加成，等于把那次修复撤掉。**所以不能靠"把断言放宽"来解决，那是撤护栏。**
##
## 改法：踏板的收益从"飞得更快"换成"**回速更快**" ——
## 巡航 / 极速 / 过载上限**一个不动**（天花板不变量原样成立），
## 而加速、加力加速、减速三项 ×1.45 ⇒ **缠斗中掉下去的速度能更快拉回来**，
## 实际平均速度明显更高。这在体感上就是"踏板让机体更跟手"，
## 而且它和"转向变钝 ×0.8"（`RIDE_TURN_MUL`）正好是一对**取舍**：
## 直线回速好、转弯差 ⇒ 逼出"它转弯吃亏的那几秒"这个可打的窗口。
const RIDE_THROTTLE_RESPONSE := 1.45
## 骑乘期间的转向折扣。
##
## 这是踏板的**代价**，也是"贴上去逼它脱板"能成立的原因：
## 骑板敌机转不动，玩家切军刀贴到内圈就能逼它。
## 0.8 是"明显但还能打"的档位（对比阿利宙斯巡航形态的 0.62 是"完全转不动"）。
##
## ⚠️ **骑板时"辅助驾驶"也不再走平移模式、而是保持飞行操纵**（2026-09-28 用户要求：
## 「飞行踏板在辅助驾驶模式下操控方式和阿利宙斯巡航态一样」）—— 正因如此，
## 上面这两个乘在气动上的系数才**真的会被玩家用到**；判据在
## `PlayerController.assist_uses_translation(p, has_pedal())`。
const RIDE_TURN_MUL := 0.8

## 踏板被打爆后，骑手的**失能时长**（秒）。这段时间里骑手的速度被夺走、不能开火。
## 给的是"玩家可以抓住的窗口"：太短等于没发生，太长等于直接赢。
const STAGGER_TIME := 0.8
## 爆掉时骑手吃的那一轮伤害（绝对值，再乘难度出伤倍率）。
const BREAK_DAMAGE := 55.0
## 爆掉时把骑手**向上向后**抛出去的速度（m/s）。
const THROW_SPEED := 240.0

# ---- 踏板自己的武器：**火神机枪**（1.2 用户指定）----
#
# 用户原话：「飞行踏板上必须有一个领队机（在踏板上的时候可以操控踏板），
# 另外一台机体负责踏板的武器操控（**飞行踏板的火神机枪**），
# 两台机体的机体武装的操控各自负责」。
#
# 所以踏板是**有武装的**，而且是**第二位骑手**在打它 —— 不是领机。
# 但玩家操控的那台**总是领机**（`main` 把玩家摆在 0 号位），
# 所以为了"玩家也能打踏板火神炮"，规则落成：
#   **骑板时空格 = 踏板的火神炮**（自己那门暂时让给领机/僚机去管）。
# 这既是用户指定的键位（"空格在骑板时改成踏板火神炮"），
# 也让"踏板有武器"这件事在单机上真的能被玩家用上。
## 踏板火神炮的单发伤害。比机体的 0.65 高一档（它是**载具**的固定武器，位置也稳）。
const GUN_DAMAGE := 1.15
## 射击间隔（秒）。比机体的 0.055 慢一档：耐久打光前它是持续压制，不是融化。
const GUN_INTERVAL := 0.085
## 弹速（m/s）。
##
## ⚠️ 写成"从 `SuitProfile` 推出来的表达式"而不是字面量：机体实际速度 ×1.5 之后，
## 踏板机炮的弹速必须跟着走，否则它比领机慢一档。
## ⚠️ 目前这个常量**没有读取点**（真正决定速度的是 `Projectile.vulcan()`），
## 保留它只是为了让"这个数是共享的"这件事有一处可查。
const GUN_SPEED := SuitProfile.VULCAN_BASE_SPEED * SuitProfile.SPEED_REAL_MULT
## 炮口相对踏板原点的偏移（占**踏板全长**的比例，正面朝 −Z）。
## 0.9 = 放在甲板最前缘，和机体的炮口不会挤在一起。
const GUN_MUZZLE_Z := -0.42
const GUN_MUZZLE_Y := 0.35

signal gun_fired

signal broken(pedal: FlightPedal, rider: Node3D)
signal damaged(amount: float)

## 这块板挂在哪台机身上（领机）。**板上所有骑手的伤害都打进他的这份耐久。**
var owner_rider: FlightBody = null
## 当前骑手（`[0]` 是领机，后面是被载机）。长度 ≤ 2。
var riders: Array[FlightBody] = []
var max_hp := 100.0
var hp := 100.0
var alive := true
var kind: int = Kind.MAFTY

var _model: Node3D = null
var _visual_ready := false
## 踏板火神炮的冷却（秒）。
var gun_cooldown := 0.0
var _gun_cycle := 0


## ---- 骑乘资格 / 载具系统（1.2 用户指定）----
##
## 用户：「AI 僚机能用，然后玩家在操控**古斯塔夫和梅萨**的时候也能用，
## 但是操控 **ACE 机（柯西 / 佩涅罗佩 / 阿利宙斯）不能用**」。
##
## ⚠️ 判定放在**机体**身上（`SuitProfile.can_ride_pedal()`），踏板这边只转发 ——
## "谁能骑"是一个机体属性，不该散在载具里各写一份。
static func can_suit_ride(suit_id: int) -> bool:
	return SuitProfile.by_id(suit_id).can_ride_pedal()


func can_rider_ride(r: FlightBody) -> bool:
	if r == null or not is_instance_valid(r) or r.profile == null:
		return false
	return r.profile.can_ride_pedal() and (kind != Kind.ODYSSEUS or is_odysseus(r.profile))


## 按机体所属阵营挑一块板 —— **"谁骑哪块"的唯一真源**。
##
## ⚠️ 用户："一台踏板上必须是**统一阵营**各自操控的机体" ——
## 所以踏板型号必须和机体阵营**成对**出现（马夫蒂板只载马夫蒂机，
## 喀耳刻板只载联邦/喀耳刻机）。这条由 `kind_for_suit()` 保证：
## 每台机体只对应一种板，不存在"选错板"的可能。
##
## ⚠️ **阿利宙斯在 2026-09-20 从马夫蒂侧改到喀耳刻侧**（见 `BattleFormation.mafty()`
## 的注释：它本来就是喀耳刻部队的机体）—— 所以它现在骑**喀耳刻板**，
## 必须从这个马夫蒂列表里去掉。三个列表（阵营池 / 踏板归属 / 这里的注释）要一起改，
## 否则会出现"喀耳刻的机骑着马夫蒂的板"这种自相矛盾的组合。
## ⚠️ 这条 match 的兜底是 `Kind.KILCE`（联邦的板）—— 所以**新加一台马夫蒂机
## 而忘了改这里，表现是"这台机静默骑上联邦的板"**，不报任何错。
## 2026-09-29 加梅萨指挥官型 / F01型时就是照这条走过来的
##（`suite_messer_roster` 现在把两台都钉在 `Kind.MAFTY` 上，前后各钉一次）。
##
## ⚠️ **2026-09-30（N62）指挥官型改钉 `Kind.MESSER_CMD`** ——
## 它不是"换了一个阵营"，而是**换了一块板**：`mafty_*` 那套搭乘态里
## 烤死的机体是量产型 M01，指挥官型骑上去会**画成量产型**。
## ⇒ 这个方法判的**不是阵营，而是"这块板烤的是不是它自己"**。
## 以后再加机体要同时问两件事：① 它在哪一边；② 板上有没有它的搭乘态模型。
static func is_odysseus(p: SuitProfile) -> bool:
	return p != null and p.id == SuitProfile.Id.PENELOPE and p.form == 1

static func kind_for_profile(p: SuitProfile) -> int:
	return Kind.ODYSSEUS if is_odysseus(p) else kind_for_suit(p.id if p != null else -1)

static func kind_for_rider(rider: FlightBody) -> int:
	if rider.is_player and rider.profile != null and rider.profile.id == SuitProfile.Id.GUSTAV00 \
			and Game.match_mode == Game.MatchMode.CHALLENGE and Game.active_mission != null \
			and Game.active_mission.centered_player_pedal:
		return Kind.GUSTAV_SINGLE
	return kind_for_profile(rider.profile)

static func kind_for_suit(suit_id: int) -> int:
	match suit_id:
		SuitProfile.Id.REGZ_CUSTOM:
			return Kind.KILCE
		SuitProfile.Id.MESSER_CMD:
			return Kind.MESSER_CMD
		SuitProfile.Id.XI, SuitProfile.Id.XI_FINAL, SuitProfile.Id.MESSER_M01, SuitProfile.Id.MESSER_F01:
			return Kind.MAFTY
	return Kind.KILCE


## 某个**可视状态**下该用哪个模型。
static func model_path_of(k: int, vis := Vis.BOTH) -> String:
	var table: Dictionary = STATE_MODEL.get(k, {})
	return str(table.get(vis, table.get(Vis.BOTH, "")))


## 这个状态模型的原生尺寸（三轴）。
static func state_native_size(k: int, vis := Vis.BOTH) -> Vector3:
	var n: Vector3 = EMPTY_NATIVE.get(k, Vector3.ONE) if vis == Vis.EMPTY \
		else LOADED_NATIVE.get(k, Vector3.ONE)
	return n


## 这个状态模型的原生**厚度**（Y）。`_build_visual()` 用它算缩放。
static func native_height_of(k: int, vis := Vis.BOTH) -> float:
	return state_native_size(k, vis).y


## **单踏板模型**的原生长轴尺寸（X）。见 `PEDAL_LENGTH_RATIO`。
static func native_length_of(k: int) -> float:
	return 1.84220113 if k == Kind.ODYSSEUS else (NATIVE_LENGTH_KILCE if k in [Kind.KILCE,Kind.GUSTAV_SINGLE] else NATIVE_LENGTH_MAFTY)


## 这块踏板在游戏里该**缩放到多少倍**（载人状态；空板见 `empty_scale_of`）。
static func game_scale_of(k: int) -> float:
	return loaded_scale_of(k)


## 这块踏板在游戏里的**长度**（米）。HUD / 挂位 / 测试都读它。
##
## 它**不是一个独立的自由参数**：由"模型里骑手 23 m 高"推出来，
## 于是比值自动等于用户给的那两份出击合集（马夫蒂 ≈2.25、喀耳刻 ≈2.49）。
static func game_length_of(k: int) -> float:
	return float(LOADED_NATIVE.get(k, Vector3.ONE).x) * loaded_scale_of(k)


## 这块踏板在游戏里该**缩到多厚**（米）。
##
## ⚠️ 这个返回值是"模型 Y 轴的长度"，**不是"踏板有多高"这个观感概念** ——
## 踏板是一条长平台，Y 是它的厚度。
static func target_height_of(k: int, vis := Vis.BOTH) -> float:
	return native_height_of(k, vis) * state_scale_of(k, vis)


static func kind_name(k: int) -> String:
	match k:
		Kind.ODYSSEUS:
			return "奥德修斯专用"
		Kind.GUSTAV_SINGLE:
			return "古斯塔夫单座"
		Kind.KILCE:
			return "喀耳刻部队"
		Kind.MESSER_CMD:
			return "梅萨指挥官型"
	return "马夫蒂"


## 这台机骑的是不是**马夫蒂那块板**（按板型，不是按阵营）。
##
## ⚠️ N62 之后 `MESSER_CMD` 也返回 **false** —— 因为它骑的是自己那块板。
## 想判"阵营"请用 `SuitProfile.by_id(id).faction` 之类，别拿这个当阵营判据。
static func is_mafty_kind(k: int) -> bool:
	return k == Kind.MAFTY


## 第 `slot` 个骑手相对**踏板原点**的挂位偏移（米）。
##
## ## 现在它是**从载人模型里直接量出来的**（1.2 第二十四轮）
##
## 用户要求「踏板占位参考出击合集」，并且给了明确的座次语义：
##   马夫蒂：一号机 = **前**、二号机 = **后**；
##   喀耳刻：一号机 = **左**、二号机 = **右**。
## 实测两族的座位都沿模型局部 X 分开（−X 侧 = 一号机、+X 侧 = 二号机），
## 配上各自的朝向修正（`MODEL_YAW_DEG`）就分别读成"前后"与"左右"。
##
## ⚠️ 所以**不要再手调间距**了 —— 座次是模型的属性，量出来就是对的。
## 以前那个 `SLOT_SPREAD_RATIO`（0.28 × 板长）是我在"自己摆两台"时的近似，
## 现在模型自带座次，近似反而会和模型打架（骑手对不上模型里的那台）。
func slot_offset(slot: int) -> Vector3:
	var s := state_scale_of(kind, vis_state())
	var pos: Vector3 = _native_rider_pos(slot) * s
	# ⚠️ 座位的原生坐标是**模型空间**的，而模型挂在朝向枢轴下面 ——
	# 所以要先过一遍枢轴的旋转，才是"踏板局部空间"里的偏移。
	return _yaw_basis() * pos


## 两位骑手在**载人模型**里的原生中心点。`slot` 越界时退回 0 号位。
func _native_rider_pos(slot: int) -> Vector3:
	var arr: Array = STATE_RIDER_POS.get(kind, [])
	if arr.is_empty():
		return Vector3.ZERO
	return arr[clampi(slot, 0, arr.size() - 1)]


## 朝向修正的旋转基（绕 Y）。
func _yaw_basis() -> Basis:
	var yaw := float(model_yaw_override) if model_yaw_override != null else model_yaw_of(kind)
	return Basis(Vector3.UP, deg_to_rad(yaw))


## 两位骑手在模型里差多远（米）。HUD / 测试读它。
static func slot_separation_m(k: int) -> float:
	var arr: Array = STATE_RIDER_POS.get(k, [])
	if arr.size() < 2:
		return 0.0
	return (Vector3(arr[1]) - Vector3(arr[0])).length() * loaded_scale_of(k)


## 这块板当前处于哪个**可视状态**（由"哪几位骑手还在"决定）。
func vis_state() -> int:
	var has0 := false
	var has1 := false
	# ⚠️ **座次是"粘"在骑手身上的**（`FlightBody.pedal_slot`），不是按数组下标 ——
	# 一号机脱离之后，留在板上的那台**仍然是二号机**（显示在二号位）。
	# 按下标算的话，剩下的那台会被当成一号机，模型就会切错
	#（空板/只剩一台/两台之间切错是**看得见的**）。
	for r: FlightBody in riders:
		if r == null or not is_instance_valid(r):
			continue
		if r.pedal_slot <= 0:
			has0 = true
		else:
			has1 = true
	return Vis.BOTH if (has0 and has1) else (Vis.SLOT0_ONLY if has0
		else (Vis.SLOT1_ONLY if has1 else Vis.EMPTY))


## 找一个空座位（先 0 后 1）。满了返回 −1。
func _free_slot() -> int:
	var used := {}
	for r: FlightBody in riders:
		if r != null and is_instance_valid(r):
			used[r.pedal_slot] = true
	if not used.has(0):
		return 0
	if slot_count() > 1 and not used.has(1):
		return 1
	return -1


func slot_count() -> int:
	return 1 if kind in [Kind.ODYSSEUS,Kind.GUSTAV_SINGLE] else 2


## 把某位骑手**自己的模型**藏起来。
##
## ⚠️ **注释修正（2026-09-21，设计文档 §3.5 第 2 条）**：这里原来写着
## 「只在 `USE_DEPLOYED_MODEL = true`（套装模型路线）下用……**当前路线是单踏板模式，
## 永远用不到它**」—— **这两句现在都是错的**：`USE_DEPLOYED_MODEL` 这个开关早就不在了，
## 而这个函数有**三个**调用点，全是无条件调的：
##   - `add_rider()`（有人上板）
##   - `_build_visual()`（按新状态重建外观）
##   - `_sync_rider_model_visibility()`（按 `vis_state()` 统一同步）
##
## 真正的约束是：**载人状态的踏板模型里自带机体几何**（1.2 第二十四轮的成分状态方案），
## 所以只要板上有人就必须藏骑手自己的模型，否则两台叠影；
## 空板（`Vis.EMPTY`）反过来要**显**回来 —— 见 `show_rider_model()`。
##
## 这正是交接文档 §7.2 第 1 条点名的坑：**注释说"用不到 / 已删"，去代码里确认一遍再动手。**
func hide_rider_model(r: FlightBody) -> void:
	# ⚠️ ★63-9 B1：改成走 `FlightBody` 的**唯一写入点**，不再裸写 `model_root.visible`。
	#
	# 原写法只在状态变化时写一次，而 `main._apply_camera_settings()` **每帧**
	# 会把骑手自己的模型显回来（它读 `(not first_person) and alive`，
	# 不知道板上已经有他那一份几何）⇒ 两台机体叠影。
	#
	# 也不再需要 `r.model_root == null` 那道守门：判据先置上，
	# 模型迟一点建出来（或重建）时 `_apply_model_visibility()` 会自己算对。
	if r == null or not is_instance_valid(r):
		return
	r.set_rider_hidden(true)


## 还原所有骑手自己的模型（脱板时调，否则两台会一起隐形）。
func show_riders() -> void:
	for r: FlightBody in riders:
		if r != null and is_instance_valid(r):
			r.set_rider_hidden(false)


## 挂上一位骑手。`rider.team` 用来决定它在 HUD 上是敌是友。
func add_rider(r: FlightBody) -> void:
	if r == null or not is_instance_valid(r) or riders.has(r) or (r.profile != null and r.profile.id == SuitProfile.Id.REGZ_CUSTOM) or (kind == Kind.ODYSSEUS and not can_rider_ride(r)):
		return
	if riders.size() >= slot_count():
		return
	# **座位号粘在骑手身上**：先 0 后 1 取第一个空位。
	var slot := _free_slot()
	if slot < 0:
		return
	r.pedal_slot = slot
	# ⚠️ **不要**在这里写 `r.pedal = self`（我加过一次，被 round17 的回归门抓住）。
	#
	# `riders` 是"**这块板登记的骑手**"，而 `FlightBody.pedal` 是"**骑手自己骑的那块板**"
	# —— 两回事。把领机临时挂到别人的板上测炮手判定（测试真这么干）时，
	# 那行会**把领机从他的板上偷走**，随后那块板爆掉就把领机也一起放了下来。
	#
	# 骑手自己的板只在两处设置：`configure_pedal()`（自己造一块）与
	# `_complete_pedal_mount()`（呼叫的板到位）。
	riders.append(r)
	if owner_rider == null:
		owner_rider = r
	# ⚠️ 现在**一律藏**骑手自己的模型：载人状态模型里**自带机体几何**
	#（1.2 第二十四轮改的成分状态方案）。不藏就是两台叠影。
	# 板上只剩一位时也藏 —— 那个状态的模型里也带着那一台。
	hide_rider_model(r)
	# 人变了 ⇒ 按新状态换模型（只有前机/只有后机/两台/空板）。
	refresh_state_visual()


## 只把某一位骑手的模型恢复可见（脱板时逐位调）。
func show_rider_model(r: FlightBody) -> void:
	if r == null or not is_instance_valid(r):
		return
	r.set_rider_hidden(false)


func remove_rider(r: FlightBody) -> void:
	riders.erase(r)
	# 人少了 ⇒ 换模型（可能从"两台"变成"只剩一台"）。
	refresh_state_visual()


func has_rider(r: FlightBody) -> bool:
	return riders.has(r)


## 挂到骑手身上。**必须在 rider 进入场景树之后调用**（模型缩放要读它的 `model_bounds`）。
## `k` 留 −1 表示按骑手的机体自动挑板。
func setup(for_rider: FlightBody, k := -1) -> void:
	owner_rider = for_rider
	kind = k if k >= 0 else kind_for_rider(for_rider)
	# ⚠️ **领机也必须登记进 `riders`**：`break_off()` 是靠遍历这个数组
	# 把板上的每一位放下来的。第一版只在 `add_rider()` 里登记，
	# 于是领机的失能/抛出全都没发生（表现是"板爆了但他还在正常飞"）——
	# 这一条是测试抓出来的，别删。
	add_rider(for_rider)
	max_hp = maxf(for_rider.max_hp * HP_RATIO, 1.0)
	hp = max_hp
	alive = true
	name = "Pedal"
	_build_visual()
	_align_to_rider(for_rider)


## 板上的人变了 ⇒ **按新状态换模型**（用户指定的分状态方案）。
##
## 三种情况各对应一个模型：只剩一号机 / 只剩二号机 / 两台都在 / 空板。
## 所以每张骑手变动（上板、脱板、被打爆）都要过一遍这里。
##
## ⚠️ 只在**状态真的变了**时重建：`reparent`/`instantiate` 一整套模型不便宜，
## 而 `_build_visual()` 被多处调用（`setup` / 呼叫到位 / 换状态），
## 不判就会反复重建、白吃帧。
func refresh_state_visual() -> void:
	var vis := vis_state()
	if _visual_ready and vis == _built_vis and _model != null and is_instance_valid(_model):
		# 状态没变，但**骑手模型该藏/该显**可能变了（比如回板）。
		_sync_rider_model_visibility()
		return
	_teardown_model()
	_built_vis = vis
	_build_visual()
	var lead := owner_rider if owner_rider != null and is_instance_valid(owner_rider) \
		else (riders[0] if not riders.is_empty() else null)
	if lead != null:
		_align_to_rider(lead)


## 拆掉当前模型（换状态前调用）。
func _teardown_model() -> void:
	if _model != null and is_instance_valid(_model):
		var p := _model.get_parent()
		if p != null:
			p.remove_child(_model)
		_model.queue_free()
	_model = null
	for ch in get_children():
		if ch is Node3D and (str(ch.name).begins_with("YawPivot") or str(ch.name).begins_with("MeleeImpactPivot")):
			remove_child(ch)
			ch.queue_free()
	_visual_ready = false


## 载人模型自带机体几何 ⇒ 骑手自己的模型要藏；空板状态没有 ⇒ 要显。
func _sync_rider_model_visibility() -> void:
	var hide_them := vis_state() != Vis.EMPTY
	for r: FlightBody in riders:
		if r == null or not is_instance_valid(r):
			continue
		if hide_them:
			hide_rider_model(r)
		else:
			show_rider_model(r)


## 踏板模型的**朝向修正**（度，绕 Y）。
##
## ## 为什么需要它（和机体那边同一个坑）
##
## 工程的约定是**模型正面朝 −Z**。梅萨M01 的模型实际朝 +X，于是整台侧着飞
## ——用户实测报过「梅萨的模型方向不对，现在是左边朝前面了」，
## 修法是 `SuitProfile.model_yaw_deg = 90`。踏板是**另一份模型**，要各自量。
##
## ## 这次的值怎么定的（**两条独立证据互相印证**，不再只靠"看图"这一条腿）
##
## **证据一（用户给的座次语义）**：用户说「喀耳刻的踏板一号机就是**左边**的、
## 二号机就是**右边**的；马夫蒂的踏板一号机就是**前面**的、二号机就是**后面**的」。
## 而实测两族的两个座位**都沿模型局部 X 分开**（见 `STATE_RIDER_POS`）：
## 马夫蒂 −0.3085 / +0.5023、喀耳刻 −0.3182 / +0.2123。
## 同一个"局部 X"要分别读成"前后"和"左右" ⇒ **两个模型相对飞行方向差 90°**。
##
## **证据二（四选一出图）**：`tools/pedal_yaw_choices.tscn` 的四格图里，
## 马夫蒂的**第 2 格（90°）**、喀耳刻的**第 1 格（0°）**是"前端朝画面外侧"的那一格。
##
## 两条指向一致 ⇒ 先采用 90°，**但那是错的**（见下）。
##
## ## ⚠️ **正确值是马夫蒂 270° / 喀耳刻 0°** —— 由**测试**抓出来，不是看出来的
##
## 90° 会让一号机落到 **+Z（机尾方向）**，而用户要的是"一号机在**前**"（前 = −Z）。
## `t.lt(m0.z, m1.z)` 那条断言第一次跑就是红的：
## 实测 m0.z = +15.96、m1.z = −25.98 —— **正好反了 180°**。
##
## 四选一图只能分出"轴对不对"，**分不出"朝前还是朝后"**，所以那个坑必须靠
## **可执行的判据**兜住。这条断言就是为它写的，别删。
##
## ## ✅ 用户已试玩确认（2026-09-20："踏板的方向对了"）
##
## 所以这两个数**不要再动**。这里特意写死结论，是因为我在这台机上已经
## 因为"看图判断朝向"错过三次，而后人看到"四选一图 + 一个可疑的角度"
## 很容易想再"修"一次 —— 那会把一个已经正确的值改坏。
##
## 真要复核就改**判据**（`suite_round17` 里那两条 `一号机在前/在左`），
## 别去改这两个数。
##
## 喀耳刻是 0°：0° 下 slot 0 落在 −X（左），与"一号机在**左**"一致。
const YAW_CHOICES := [0.0, 90.0, 180.0, 270.0]

const MODEL_YAW_DEG := {
	Kind.ODYSSEUS: 0.0, # Supplied rider and rear engine outlets already face native flight axes.
	Kind.MAFTY: 270.0,
	Kind.KILCE: 0.0,
	## 指挥官型的板与马夫蒂**是同一块** ⇒ 同一个朝向修正。
	##（区别只在于 `messer_cmd_*` 里烤的机体，那是**模型空间内部的朝向**，
	##  由生成脚本 `n62_make_states.py` 的 `CMD_YAW_DEG` 控制，与这里无关。）
	Kind.MESSER_CMD: 270.0,
}


static func model_yaw_of(k: int) -> float:
	return float(MODEL_YAW_DEG.get(k, 0.0))


## **工具专用的朝向覆盖**（null = 用 `MODEL_YAW_DEG` 表里的值）。
##
## ⚠️ 只给 `tools/pedal_yaw_choices.tscn` 那种"四选一"出图用：
## 它要在一张图里把四个候选角**同时**渲出来，所以必须能临时改朝向。
## **生产代码不要设它** —— 正式值只走 `MODEL_YAW_DEG`。
var model_yaw_override: Variant = null


## 拆掉重建可视件 —— 给"改了朝向之后重新出图"用。
##
## 单独一个函数而不是让工具去摸 `_model`：那些都是私有字段，
## 工具直接改会和内部状态（`_visual_ready` / 枢轴层级）脱节。
func rebuild_visual_for_test() -> void:
	if _model != null and is_instance_valid(_model):
		var p := _model.get_parent()
		if p != null:
			p.remove_child(_model)
		_model.queue_free()
	_model = null
	# ⚠️ 枢轴也是上一次建的，一起清掉 —— 留着会叠加两次旋转。
	for ch in get_children():
		if ch is Node3D and (str(ch.name).begins_with("YawPivot") or str(ch.name).begins_with("MeleeImpactPivot")):
			remove_child(ch)
			ch.queue_free()
	_visual_ready = false
	_build_visual()
	if owner_rider != null and is_instance_valid(owner_rider):
		_align_to_rider(owner_rider)


func _on_material_style_changed() -> void:
	if kind in [Kind.KILCE, Kind.GUSTAV_SINGLE] and _material_cel_mode != Settings.cel_shading and is_instance_valid(_model):
		_apply_model_materials()


func _apply_model_materials() -> void:
	_material_cel_mode = Settings.cel_shading
	for c: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src is StandardMaterial3D:
				var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				mi.set_surface_override_material(i, mat)
				if kind in [Kind.KILCE, Kind.GUSTAV_SINGLE]:
					SUIT_MATERIALS.apply(mat, SuitProfile.Id.GUSTAV00, true)
				else:
					FX.toonify(mat)


func _build_visual() -> void:
	if _visual_ready:
		return
	var vis := vis_state()
	var ps := load(model_path_of(kind, vis))
	if ps is PackedScene:
		_model = (ps as PackedScene).instantiate() as Node3D
	if _model == null:
		# 模型缺失时**不能静默**：踏板会在玩法上照常工作（耐久/脱板都在代码里），
		# 但玩家看不到它 —— 那是最难查的一类问题。所以这里明确记一条日志。
		push_warning("FlightPedal: 踏板模型加载失败 %s —— 踏板逻辑仍在运行，但不可见"
			% model_path_of(kind, vis))
		_visual_ready = true
		return
	_model.scale = Vector3.ONE * state_scale_of(kind, vis)
	_model.position = Vector3.ZERO
	_apply_model_materials()
	if not Settings.changed.is_connected(_on_material_style_changed):
		Settings.changed.connect(_on_material_style_changed)
	# ---- 朝向修正：走**独立枢轴**，不要直接转 `_model` ----
	#
	# ⚠️ `scale` 与 `rotation` 是同一个 `Transform3D` 的两个分量。
	# 在**非等比缩放**（踏板模型三轴比例差得远：0.9995 / 0.3062 / 0.7632）
	# 的节点上叠一个旋转，会得到"看着转对了、其实被拉斜了"的结果 ——
	# 这是梅萨那边踩过的同一个坑，那里也是用枢轴解的。
	var yaw := float(model_yaw_override) if model_yaw_override != null else model_yaw_of(kind)
	if not is_zero_approx(yaw):
		var pivot := Node3D.new()
		pivot.name = "YawPivot"
		pivot.rotation_degrees = Vector3(0.0, yaw, 0.0)
		add_child(pivot)
		pivot.add_child(_model)
	else:
		add_child(_model)
	_visual_ready = true
	# A separate additive layer keeps imported/yaw transforms intact during platform impacts.
	var impact := Node3D.new()
	impact.name = "MeleeImpactPivot"
	_model.get_parent().add_child(impact)
	_model.reparent(impact,false)
	# Platform models have hundreds of parts too; use the existing body detail policy.
	for part: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := part as MeshInstance3D
		if mesh.mesh != null:
			mesh.visibility_range_end = FlightBody.detail_range_end(FlightBody.part_radius_m(mesh), Game.match_mode == Game.MatchMode.SQUAD and not (is_instance_valid(owner_rider) and owner_rider.is_player))
	if _model != null:
		var propulsion := get_node_or_null("PedalPropulsion")
		if propulsion == null:
			propulsion = Node3D.new()
			propulsion.set_script(preload("res://scripts/flight/pedal_propulsion.gd"))
			propulsion.name = "PedalPropulsion"
			add_child(propulsion)
		propulsion.bind(self, _model)
		sync_cockpit_visibility(_cockpit_hidden)
	# ---- 载人模型自带机体几何 ⇒ 把骑手**自己的模型藏掉**（否则叠影）----
	#
	# ⚠️ 脱板时**必须还原**（`on_pedal_broken()` 那边会调 `show_riders()`），
	# 否则板爆了之后两台会同时变成隐形 —— 那就从"漂亮的编队"变成"莫名其妙打不中"。
	#
	# ⚠️ 空板状态**没有**机体几何，那时两位骑手本来就不在板上，不会走到这里。
	if vis != Vis.EMPTY:
		for r: FlightBody in riders:
			hide_rider_model(r)


## 踏板模型在**自身**坐标系下的包围盒（未缩放）。
##
## ⚠️ 要的是**整个 AABB**而不只是尺寸：对位要同时用到"底在哪"（`position`）
## 和"多高"（`size`）。成套模型的底在 `−size.y/2`（居中导出），
## 单踏板模型也是居中——两套一致，所以这里不做特殊处理。
func _local_aabb() -> AABB:
	var fallback := AABB(Vector3(-0.5, -NATIVE_HEIGHT_MAFTY * 0.5, -0.38),
		Vector3(1.0, NATIVE_HEIGHT_MAFTY, 0.76))
	if _model == null or not is_instance_valid(_model):
		# 模型缺失时的兜底：给一个"像块板"的盒子，挂位还能量出来。
		return fallback
	var out := AABB()
	var first := true
	for c: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a: AABB = mi.transform * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return fallback if first else out


## 把这块板摆到"领机的座位正好落在领机原点"的位置。
##
## ## 口径变了（1.2 第二十四轮：改用分状态模型）
##
## 以前是"单踏板模型 + 自己摆两台骑手"：板贴到骑手脚底、两台骑手按比例摆在板上。
## 现在是**载人模型自带座次**，所以要**反过来**：
##   模型里那个座位在哪，板就反向平移多少 —— 这样模型里那台机体正好套住领机。
##
## 于是"骑手站在踏板上"不再需要我算甲板高度/半身高/脚缝那一串近似
## （第二十三轮那套 `slot_height_m()` 已经删掉）—— 座次是**量出来的**，
## 模型自己是准的。
##
## ⚠️ 板挂了朝向枢轴，模型的原生坐标要先过枢轴的旋转。
func _align_to_rider(for_rider: FlightBody) -> void:
	if for_rider == null or not is_instance_valid(for_rider):
		return
	var slot := _slot_index_of(for_rider)
	var s := state_scale_of(kind, vis_state())
	# 反向平移：让"模型空间里那个座位"落到踏板原点（= 领机原点）上。
	position = -(_yaw_basis() * (_native_rider_pos(slot) * s))


## 这位骑手是几号机（0 / 1）。**读它自己身上粘的座位号**（见 `vis_state()`）。
func _slot_index_of(r: FlightBody) -> int:
	if r == null or not is_instance_valid(r):
		return 0
	return clampi(r.pedal_slot, 0, slot_count() - 1)


## 某位骑手在**世界**里的挂位（领机用不到，被载机读它）。
func slot_world_position(slot: int) -> Vector3:
	return global_transform * slot_offset(slot)


## 把一份伤害分给踏板与机体。
##
## ⚠️ **纯函数**（不碰场景树、不读全局）：它是"骑乘伤害分配"的**唯一真源**，
## 回归测试直接喂数值就行，不需要起一局。
##
## 返回 `{"to_pedal": float, "to_hull": float}`。
##   - 踏板还活着：按 `PEDAL_SHARE` 切分，并把"进踏板的份额"**钳到剩余耐久**
##     —— 最后一发打爆它时不会把多出来的伤害吞掉（那等于让玩家白打一发）。
##   - 踏板已爆：全部进机体。
static func damage_split(amount: float, pedal_hp: float, has_pedal: bool) -> Dictionary:
	if not has_pedal or pedal_hp <= 0.0:
		return {"to_pedal": 0.0, "to_hull": amount}
	var want := amount * PEDAL_SHARE
	var to_pedal := minf(want, pedal_hp)
	return {"to_pedal": to_pedal, "to_hull": amount - to_pedal}


## 踏板吃伤害。返回 true 表示**这一发把它打爆了**。
func take_damage(amount: float) -> bool:
	if not alive or amount <= 0.0:
		return false
	hp -= amount
	damaged.emit(amount)
	if hp <= 0.0:
		hp = 0.0
		return true
	return false


func ratio() -> float:
	return 0.0 if max_hp <= 0.0 else clampf(hp / max_hp, 0.0, 1.0)


func is_alive() -> bool:
	return alive


# ============================================================ 踏板自己的武器

## 炮口在**世界**里的位置。
##
## 与 `FlightBody._collect_muzzles()` 同一套口径：位置从**模型包围盒**反推
## （而不是写死坐标），所以换模型/改缩放都不会偏。
func muzzle_world_position() -> Vector3:
	var box := _local_aabb()
	var scale := target_height_of(kind) / native_height_of(kind)
	var local := Vector3(0.0, box.position.y + box.size.y * GUN_MUZZLE_Y,
		box.position.z + box.size.z * GUN_MUZZLE_Z)
	return global_transform * (local * scale)


## 分给踏板火神炮的**下一位骑手**（用户："另外一台机体负责踏板的武器操控"）。
##
## `riders[0]` 是领机（他操控踏板本身），所以武器的负责人是 `riders[1]`；
## 板只有一台骑手时（单机骑乘）就退回他本人 —— 否则单机骑板会变成
## "有炮却没人能开"，那是个不能交付的状态。
##
## ⚠️ 玩家操控的**总是领机**（`main` 把他摆在 0 号位），所以为了让玩家
## 也能打这门炮，`FlightBody` 那边把"骑板时的空格"直接接到踏板的 `fire_gun()`
## 上（见 `SuitProfile`/`input_setup` 里那两条键位说明）。这里返回的是
## **AI 侧**的分工判据。
func gun_operator() -> FlightBody:
	if riders.size() >= 2:
		return riders[1]
	return riders[0] if not riders.is_empty() else null


## 这门炮现在能不能开（冷却好、板活着、有人在管它）。
func can_fire_gun() -> bool:
	return alive and gun_cooldown <= 0.0 and gun_operator() != null


## 打一发踏板火神炮。`container` 是弹丸的挂载节点（由骑手传进来）。
##
## 返回是否真的打出去了 —— 调用方（`FlightBody`）靠它决定要不要播报/记统计。
func fire_gun(container: Node, aim_target: Node3D = null) -> bool:
	if not can_fire_gun() or container == null:
		return false
	gun_cooldown = GUN_INTERVAL
	_gun_cycle += 1
	var origin := muzzle_world_position()
	# 炮口轮流：这门炮是**两管**（模型甲板前端左右各一），交替出膛看起来不呆板。
	var side := 0.12 if _gun_cycle % 2 == 0 else -0.12
	origin += global_transform.basis.x * side * (target_height_of(kind) / native_height_of(kind))
	var dir := forward_dir()
	if aim_target != null and is_instance_valid(aim_target):
		var aim := aim_target.global_position
		var d := aim - origin
		if d.length_squared() > 1.0:
			dir = d.normalized()
	Projectile.vulcan(container, origin, dir, owner_rider, GUN_DAMAGE,
		Color(1.0, 0.72, 0.55, 0.95))
	gun_fired.emit()
	return true


## 踏板朝向（= 领机朝向；没有领机时用自己的）。
func forward_dir() -> Vector3:
	var r := owner_rider
	if r != null and is_instance_valid(r):
		return r.forward()
	return -global_transform.basis.z


func _process(delta: float) -> void:
	# Embedded rider geometry is part of the platform model, not FlightBody.model_root.
	var cockpit := false
	if is_ridden():
		for rider: FlightBody in riders:
			if is_instance_valid(rider) and rider.alive and not rider._model_wish:
				cockpit = true
	sync_cockpit_visibility(cockpit)
	if is_instance_valid(_model):
		var impact := _model.get_parent()
		if impact.name == "MeleeImpactPivot":
			var lean := Vector3.ZERO
			for rider: FlightBody in riders:
				if is_instance_valid(rider) and rider.alive: lean += rider.melee_hit_reaction.angles
			impact.rotation_degrees = lean*0.28
	gun_cooldown = maxf(gun_cooldown - delta, 0.0)
	# ---- 两个新状态的自走（1.2 第二十三轮）----
	#
	# ⚠️ 它们必须在 `_process` 里走，**不能**指望骑手的 `_physics_process` ——
	# 呼叫中的板**还不是骑手的子节点**（挂在世界层），骑手那边根本遍历不到它。
	match mode:
		Mode.INBOUND:
			_tick_inbound(delta)
		Mode.CAST_OFF:
			_tick_cast_off(delta)


## 呼叫中：朝骑手飞过去，到了就 `_arrive()`。
func _tick_inbound(delta: float) -> void:
	var r := owner_rider
	if r == null or not is_instance_valid(r) or r.is_queued_for_deletion():
		queue_free()
		return
	var to := r.global_position - global_position
	var d := to.length()
	var remaining := maxf(CALL_MAX_SECONDS - _call_elapsed, 0.0)
	_call_elapsed += maxf(delta, 0.0)
	if d <= CALL_ARRIVE_DIST or remaining <= delta:
		global_position = r.global_position
		_arrive()
		return
	# ⚠️ `minf(..., d)` 夹一下：不夹的话最后一帧会**冲过头**，
	# 然后下一帧又反向冲回来 —— 表现是板在骑手身边来回抽搐。
	var speed := maxf(CALL_SPEED, d / maxf(remaining, 0.001) + r.velocity.length())
	global_position += to.normalized() * minf(speed * maxf(delta,0.0), d)
	if global_position.distance_to(r.global_position) <= CALL_ARRIVE_DIST:
		_arrive()
		return
	# 让板"朝着骑手"转过去，看起来是在飞而不是平移。
	#
	# ⚠️ 原来是 `look_at()`（**瞬时**朝向）。换成 **slerp 限速**有两个理由：
	#   ① `look_at` 是瞬时的，接近时最后几帧方向变化很剧烈（`d → CALL_ARRIVE_DIST`），
	#      板会"啪"地抽一下；
	#   ② 顺带不再需要"方向与 UP 平行就跳过"那个退化守卫 —— 那条守卫本身是对的，
	#      错的是入场点选得让它永远生效（见 `CALL_APPROACH_DIST`）。现在入场矢量
	#      斜向、且 `d > CALL_ARRIVE_DIST`（45 m）保证 `to` 非零，`looking_at` 安全。
	#
	# 限速 6.0 /s：约 0.17 s 走完大半，够稳也不至于"跟不上"。
	if d > 1.0:
		var direction := to.normalized()
		var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
		var want := Basis.looking_at(direction, up)
		global_transform = Transform3D(
			global_transform.basis.slerp(want, 1.0 - exp(-6.0 * delta)).orthonormalized(),
			global_position)


## 脱离后：自由滑飞，时间到就消失。
func _tick_cast_off(delta: float) -> void:
	_cast_timer -= delta
	_cast_vel.y -= CAST_OFF_GRAVITY * delta
	global_position += _cast_vel * delta
	if _cast_timer <= 0.0:
		queue_free()


## 这块板当前处于哪种状态。
##
## ## 为什么需要它（1.2 第二十三轮，用户提的两条行为）
##
## 用户原话：
##   「脱离踏板踏板并不是直接自爆，而是**自由飞走 5s 后消失**，
##     呼叫踏板也是**先在天上出现才飞到玩家身边**」。
##
## 原来两条都是"瞬时"的：脱板时 `break_off()` 直接 `queue_free()`（= 自爆），
## 呼叫时 `configure_pedal()` 当场贴在脚下。所以要引入一个状态机。
enum Mode {
	## 已被骑乘（常规状态）。
	RIDDEN,
	## 呼叫中：挂在世界里、从骑手上方飞过来。**还没骑上**。
	INBOUND,
	## 已脱离：自由滑飞一段时间后自行消失。
	CAST_OFF,
}

var mode: Mode = Mode.RIDDEN

## 上一次建模型时用的是哪个可视状态（`Vis`）。`refresh_state_visual()` 用它判"要不要重建"。
var _built_vis := -1

## 呼叫时在骑手**上方**多高处出现（米）。
##
## 用户要"先在天上出现" —— 900 m 而不是几十米，是为了让"它从上面下来"这件事
## **看得见**（30 m 会像凭空贴上来）。这个高度也是"呼叫不是瞬间生效"的代价。
const CALL_HEIGHT := 900.0
## 呼叫时在骑手**前方**多远处出现（米）。**高度与它合起来才是入场点。**
##
## ⚠️⚠️ 2026-09-21 补。原来入场点是骑手**正上方** `(0, CALL_HEIGHT, 0)`，
## 于是入场矢量**恰好与 UP 平行**，`_tick_inbound()` 里 `look_at` 的退化守卫
## `absf(to.normalized().dot(Vector3.UP)) < 0.999` **恒为假** ⇒ 那条 `look_at`
## **全程不生效**。后果有两条，玩家报的是第一条：
##   ① 板保持 `FlightPedal.new()` 的默认朝向从正上直落 ⇒ 玩家仰视只看到**板底**；
##   ② 顺带"在飞"的姿态感也没有，只有平移。
## 改成前上方斜向之后，入场矢量 ≈ `(0.707, -0.707, ·)`，`absf(dot) ≈ 0.707 < 0.999`
## ⇒ `look_at`（现在换成了 slerp 限速转向）开始工作，板会**机头朝骑手俯冲**。
##
## 高度仍保留 900 m：斜向之后总距离 ≈ 1272 m（`sqrt(900² + 900²)`），
## 基础速度 650 m/s，并按剩余的 5 s 时限动态加速，"从上面下来"这件事照样看得见。
const CALL_APPROACH_DIST := 900.0
## 呼叫基础速度（米/秒）；移动目标和远距离按剩余时限继续提速。
const CALL_SPEED := 650.0
## Deadline follows the current rider position, including boosts and teleports.
const CALL_MAX_SECONDS := 5.0
var _call_elapsed := 0.0
## 离骑手多近算"到了"（米）。到了就贴上去、转成 `RIDDEN`。
const CALL_ARRIVE_DIST := 45.0

## 脱离之后自由飞多久（秒）——用户指定 **5 s**。
const CAST_OFF_LIFE := 5.0
## 脱离瞬间的分离速度（米/秒）。沿骑手速度方向甩出去、再带一点下坠。
const CAST_OFF_SPEED := 70.0
## 脱离后的下坠加速度（米/秒²）。给一点点重力感，让它"掉下去消失"而不是平飞。
const CAST_OFF_GRAVITY := 6.0

var _cast_timer := 0.0
var _cast_vel := Vector3.ZERO


## 从天上把这块板投送过来（**呼叫**键走这条）。
##
## ⚠️ 这个阶段它**挂在骑手的父节点**（世界）上，还**不是**骑手的子节点 ——
## 所以骑手转身不会带着它转（一块从天上掉下来的板不该跟着机体横滚）。
## 到位之后 `_arrive()` 再把它重新挂到骑手身上。
func begin_inbound(for_rider: FlightBody, k := -1) -> void:
	owner_rider = for_rider
	kind = k if k >= 0 else kind_for_rider(for_rider)
	max_hp = maxf(for_rider.max_hp * HP_RATIO, 1.0)
	hp = max_hp
	alive = true
	name = "PedalInbound"
	_build_visual()
	mode = Mode.INBOUND
	_call_elapsed = 0.0
	# ⚠️ **前上方斜向**，不是正上方 —— 见 `CALL_APPROACH_DIST` 那段注释：
	# 正上入场会让 `_tick_inbound()` 的转向守卫恒为假，板全程不转、玩家只看到板底。
	global_position = for_rider.global_position \
		+ for_rider.forward() * CALL_APPROACH_DIST + Vector3.UP * CALL_HEIGHT
	# 入场姿态：板面朝上、机头指向骑手。**写死一次**，别指望第一帧的转向逻辑 ——
	# 它要等 `_process` 才跑，中间那一帧的默认朝向会被截图和测试抓到
	#（"入场第 1 帧机头应该指着骑手"是一条断言）。
	var to_rider := for_rider.global_position - global_position
	if to_rider.length_squared() > 0.0001:
		basis = Basis.looking_at(to_rider.normalized(), Vector3.UP)


## 到位：贴到骑手身上并**转交给骑手**（由 `FlightBody._complete_pedal_mount()` 收尾）。
func _arrive() -> void:
	var r := owner_rider
	if r == null or not is_instance_valid(r) or r.is_queued_for_deletion():
		# 呼叫途中目标没了（被打爆/已退出）⇒ 直接消失，别留一块孤儿板在天上。
		queue_free()
		return
	if not can_rider_ride(r):
		if r._inbound_pedal == self: r._inbound_pedal = null
		queue_free()
		return
	mode = Mode.RIDDEN
	reparent(r)
	# Inbound flight aims at the rider; it is not the mounted flight heading.
	if kind == Kind.ODYSSEUS:
		basis = Basis.IDENTITY
	r._complete_pedal_mount(self)


## **脱离**：不消失，而是自由滑飞 `CAST_OFF_LIFE` 秒之后自行了断。
##
## ⚠️ 关键是**必须脱离骑手的父链**：踏板本来是骑手的子节点，
## 不 `reparent` 出去的话它会**跟着骑手飞**（看起来像"板还粘在脚上"），
## 而不是"自己飞走"。
func begin_cast_off(from_rider: FlightBody) -> void:
	mode = Mode.CAST_OFF
	_cast_timer = CAST_OFF_LIFE
	# 沿骑手当前的前进方向甩出去 + 一点侧偏，免得"板直直地往后飞"像没动。
	var fwd := from_rider.forward() if from_rider != null else Vector3.FORWARD
	_cast_vel = fwd * CAST_OFF_SPEED + Vector3(0.0, 14.0, 0.0)
	var host := get_parent()
	if host != null and host.get_parent() != null:
		# 挂到"骑手的父节点"那一层（世界层），保持世界变换不变。
		reparent(host.get_parent(), true)
	alive = false
	if _model != null and is_instance_valid(_model):
		_model.visible = true


func is_ridden() -> bool:
	return mode == Mode.RIDDEN


## 爆掉：把**板上所有骑手**放下来。返回**被处理过的骑手列表**。
##
## ⚠️ 返回这个列表是必须的：被载机（板挂在领机身上）不一定在 `riders` 里，
## 而 `break_off()` 会**先把 `riders` 清空** —— 调用方事后查 `riders` 永远查不到
## （早先就是这么写的，于是"我有没有被处理过"的判断恒为真，
## 每个骑手都被善后了两次）。所以由**这个函数的返回值**回答那个问题。
##
## 这里**只负责"脱板"这件事本身** —— 失能与抛出交给骑手那边的
## `FlightBody.on_pedal_broken()`（它是骑手状态的唯一写入点，见铁律 6）。
## `by_break = true`：这条路上的骑手是**被打下来**的，要进失能。
##
## ⚠️ `by_break` 必须由**调用方**指定，不能在里面对每个骑手瞎猜：
## 领机**永远**在 `riders` 里，所以"我只处理了别人、没处理领机"这种判断
## 会让他绕过主动脱板那一路（本轮为此红了同一条断言两次）。
##
## ## 两条路的**去向不同**（1.2 第二十三轮，用户指定）
##
## - `by_break = true`（**被打爆**）：板就此消失（`queue_free`），骑手进失能。
##   这条不变 —— 被打爆就该当场没。
## - `by_break = false`（**主动脱离**）：板**不消失**，而是自由滑飞 5 s 后消失
##   （`begin_cast_off()`）。用户原话："脱离踏板踏板并不是直接自爆，
##   而是自由飞走 5s 后消失"。
##
## 所以"善后骑手"与"处理板自己"在这一轮里**分开**了：
## 骑手那边两条路一样（`on_pedal_broken(by_break)` 自己分辨失能与否），
## 板这边按 `by_break` 分岔。
func break_off(by_break := true) -> Array:
	var processed: Array = []
	if not alive:
		return processed
	alive = false
	var who := riders.duplicate()
	riders.clear()
	# 板空了 ⇒ 按用户的分状态方案换成**空板模型**（载人状态模型会跟着消失）。
	# ⚠️ 放在这里而不是 `begin_cast_off()` 里：**被打爆**那条路也要变空板
	#（板会当场隐藏，但状态要一致，免得同一块板两次使用之间留下错误的模型）。
	refresh_state_visual()
	broken.emit(self, owner_rider)
	for r: FlightBody in who:
		if r == null or not is_instance_valid(r):
			continue
		# ⚠️ **先把每位骑手的模型恢复可见再回调**：套装模型模式下他们的模型被藏了，
		# 不还原的话板一爆两台就一起隐形。`riders` 已经清空，
		# 所以这里不能走 `show_riders()`（那会遍历一个空数组）。
		# ★63-9 B1：走判据（`rider_hidden = false`）而不裸写 `model_root.visible`。
		r.set_rider_hidden(false)
		processed.append(r)
		r.on_pedal_broken(self, by_break)
	# ---- 板自己的去向：被打爆就消失，主动脱离就滑飞 5 s ----
	if by_break:
		if _model != null and is_instance_valid(_model):
			_model.visible = false
		queue_free()
	else:
		begin_cast_off(processed[0] if not processed.is_empty() else owner_rider)
	return processed

var _cockpit_hidden := false

## Keep the world/physics platform active; only its imported exterior and thrust are hidden.
func sync_cockpit_visibility(hidden: bool) -> void:
	_cockpit_hidden = hidden and is_ridden()
	if is_instance_valid(_model): _model.visible = not _cockpit_hidden
	var thrust := get_node_or_null("PedalPropulsion") as Node3D
	if is_instance_valid(thrust): thrust.visible = not _cockpit_hidden
