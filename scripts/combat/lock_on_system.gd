class_name LockOnSystem
extends Node
## 目标选择与锁定。挂在玩家机（或 AI 机）身上。
##
## # 1.2 起：锁定从「开关」改成「质量条 + 三层」（方案 A）
##
## 1.1 那版是"锁定之后一直保持"（角度完全不参与），那是用户当时的要求；
## 但它把锁定变成了**一次性的入场券**：锁上之后就再也不用管机头，
## 强锁定不"要维持"，机动也就没有防守价值。
## 1.2 改成**质量条**（`quality` 0..1），由五项相乘得到目标质量 `target_quality()`：
##   1. **角度**（机头，不是鼠标准星）：内锥满质量，外锥 0.30，锥外 0
##   2. **距离**：射程内 1.0 → 0.55，出射程往下掉，到脱锁距离归零
##   3. **视野角速率**（C-1「机动即防御」）：目标横着跑得越快，我越锁不住
##   4. **后半球**（C-2）：咬尾 ×1.15，对头 ×0.90
##   5. **干扰弹**（C-3）：×0.25
##
## 质量往上走时按 `lock_time` 推进（歪着也能锁，只是慢），往下走时按 `decay_rate` 衰减，
## 衰减速度还乘一个 `max(1 - q, 0.35)` —— 质量低的时候掉得更快（"快掉没了"有加速度）。
##
## ## 三层与迟滞
##
## | 层 | 条件 | 解锁什么 |
## |---|---|---|
## | `NONE` | 质量 < 0.15 | 只有目标框；打不了导弹 |
## | `TRACK` | 质量 ≥ 0.30 | 光束步枪、火神炮（**没有**精确提前量圈） |
## | `LOCK` | 质量 ≥ 1.0 | 浮游导弹、军刀吸附突进、精确提前量圈 |
##
## 回落带迟滞：`LOCK → TRACK` 在 0.70 以下、`TRACK → NONE` 在 0.15 以下 ——
## 不然质量卡在阈值上会来回抖，HUD 和警报都会跟着抽。
## 掉到 `NONE` 时质量清零并进入 `relock_lockout` 秒不能重新起锁
## （玩家 0.5 s；敌机按难度 3.0 / 1.8 / 0.9 s）。
##
## ## 批 1（R11）：**锁定组 —— 最多同时锁定 3 个目标**
##
## 一句话：锁定组最多 3 个槽位，每次扳机的导弹按「已稳定锁定」的成员数**平分**，
## 于是锁定多个目标 = **压制面更广、单点杀伤更薄**（`salvo_split()`）。
##
## 三个「为什么这么设计」，都写在代码里的对应位置：
##   - `target` / `quality` / `locked` **改成派生量**（取值来自 `lock_group` / `_members`）——
##     子步骤：**成员状态从"一份"变成"一目标一份"**。这是本节唯一的真结构变化。
##   - `add_lock()` 要求对方**已经建立航迹**（`Tier.TRACK`）—— 锁定是"挣来的"，
##     不是盯着它按一下键就白送（`ADD_LOCK_COOLDOWN` 是防"一口气填满 3 个名额"）。
##   - **不做自动补位**：加人必须靠玩家显式动作，否则"锁 3 个"变成被动收益，
##     玩家为覆盖面付的价（火力分散）就不再是他自己选的了。
##
## ⚠️ **最重要的一条不变量：K = 1 时行为与改动之前逐位相同。**
## 证明方式不是"我觉得"，而是把这几个写点全部收进 `_set_main()`：
## 旧代码里"换主目标"的三个入口（自动接战 / `select_target` / `cycle_target`）
## 当年都是「赋 `target` + `quality = 0` + 层级回 `NONE`」，`_set_main()` 做的就是同一件事。
## 组内只有一人时，凡读 `target` / `quality` / `locked` 的地方拿到的值与旧版一致。
##
## ## 批 2（轮 36）：**锁定对象不再自动切换**
##
## 用户原话：「锁定系统重修，**除非玩家手动切换锁定，不然不会自动切换锁定对象**」。
##
## 旧版把主目标做成 `lock_group[0]` 的**派生量** —— 于是「组的 0 号换人」与
## 「锁定对象换人」被绑死：主目标被击坠时，组里顺位的那个人**自动**成了新锁定对象，
## 玩家一根手指都没动，火控自己换了目标。派生量表达不了
## 「组还在、但当前**没有**锁定对象」这个状态。
##
## 现在两者**分开**：
##
## | 字段 | 是什么 | 能不能为空 |
## |---|---|---|
## | `lock_group` | **玩家纳入火控的目标集合**（≤ `MAX_LOCKS`，成员进度各自独立） | 空组 = 什么都没锁 |
## | `_main`（`target`） | **当前锁定对象** | **可以**为 `null` |
##
## 三条自动行为各自被处理：
##
##   1. **自动接战**（组空时自动咬候选表头名）：加了次数上限 `auto_engage_limit`。
##      AI 火控 `-1`（不限次，**与改动前逐位相同**）；玩家火控 `1`（进场保底锁一次）。
##   2. **顺位补位**（主目标没了就由组里下一位顶上）：**取消**。
##      主目标一出组，`_main` 就变 `null`，组内其余成员**原地保留**（连同进度），
##      等玩家自己按 Tab 切（`cycle_target()` 会把队首顶上来，是**瞬间**的）。
##   3. **鼠标罩住即锁**：**取消**（`PlayerController._read_lock_input()` 已删）。
##      鼠标只负责准星与弹道，锁定只由 Tab / 数字键发起。
##
## ### 两条不变量（缺一条都会让 HUD 或火力分配读错）
##
##   ① `_main == null` **或** `lock_group.has(_main)` —— 锁定对象必须在组里。
##   ② `_main == null` **或** `lock_group[0] == _main` —— 锁定对象尽量排在组首，
##      因为 `salvo_split()` 把余数补给"靠前的"，而它是玩家眼下最可能在打的那个。
##      ⚠️ 两者分开的唯一时刻是**锁定对象刚被移出组**：那时 `_main == null`，
##      组首已经是"下一个顺位"，但它**不是**锁定对象（这正是本次需求）。
##
## ### `null` 的语义要一致地读
##
## `target == null` ⇒ `tier()` 回 `NONE` ⇒ `locked` 为假 ⇒ **导弹 / 军刀 / 精确提前量
## 全部关闭**，HUD 也不画主目标框。这是**故意的**：没有锁定对象就是没有锁定对象，
## 「组里还有别人」并不等于「你可以开火」—— 那种半吊子状态会让"打谁"变得不可预期。

## ## 兼容
##
## `locked` 这个布尔被 5 处读（玩家侧导弹/军刀门禁、AI 的三种武器与 `_is_locked_by_player()`、
## HUD、main），`target` 被 5 处读、且被测试**直写**（`suite_abilities` 的丢枪用例）。
## 所以**两个字段名全部保留**：`locked` 是纯派生（`tier() == Tier.LOCK`），
## `target` 保留了一个**可写的**属性（赋值 = 强制换锁定对象，见 `_set_main`）。

signal target_changed(new_target: Node3D)
signal lock_acquired(target: Node3D)
signal lock_lost
## 层级变化（1.2）：警报与 HUD 用它，不必自己去比质量条。
signal tier_changed(new_tier: int)

enum Tier { NONE, TRACK, LOCK }

# ---------------------------------------------------------------- 可调参数

## 基准锁定耗时（秒）。敌机的实际耗时 = 它 × 难度表的 `lock_time_mult`
## （简单 1.80 → 1.53 s / 中等 1.25 → 1.06 s / 困难 0.70 → 0.60 s）。
const BASE_LOCK_TIME := 0.85
## 基准衰减速率（1/s）。敌机再乘难度表的 `lock_decay_mult`。
const BASE_DECAY := 0.9

## 同时锁定的目标上限（用户指定 3）。
const MAX_LOCKS := 3
## ★63-24：`MAX_LOCKS` 的**实例字段**版（默认 = 常量）—— 上面那个是给测试与静态读的，
## 实例字段才是"能被演习模式 R-M1「独锁」压到 1"的那一个（每台机各一份）。
var max_locks := MAX_LOCKS
## 往组里加人之后的这段时间内不能再加（秒）。
## 防的是"按住 Tab 一口气把 3 个名额全填满" —— 那会让"为覆盖面付代价"这件事
## 变成一次性的无脑操作。0.35 s 与 `PAD_HOLD` 的长按阈值（0.4 s）同量级。
const ADD_LOCK_COOLDOWN := 0.35
## 锁定组在 HUD 上的圈号。**只此一份**：HUD 与测试都读它，
## 免得"①②③"的字形在 HUD 里改了一次、而测试还在找旧的。
const GROUP_MARKS := ["①", "②", "③"]

## 锁定范围（米）。
##
## ⚠️ **跟着 `WorldBuilder.MAP_SCALE` 放大**（2026-09-21 拍板）。
##
## 它曾是"玩法常数、明确不随地图缩放"的 9000 —— 那条决定在地图放大 2.3 倍之后
## 造成了两个不变量互相打架：训练靶场为了保住"比例一致"必须放到 11960，
## 但 11960 > 9000 就又弄坏了"出生点锁得上靶机"。取 (b) 之后两端一起放大，
## 两条同时成立，而**相对手感不变**（靶机距离/锁定距离 仍是 0.578，见衔接文档 §2.4）。
##
## ⚠️ 它现在与 `WorldBuilder.TRAINING_PATROL_RADIUS` 是**同一条不变量的两端**
## （`巡逻半径 < 锁定范围`，断言在 `suite_round19`）—— 改一个必须看另一个。
##
## ⚠️⚠️ **它是 `@export` 字面量，不派生自 `MAP_SCALE`** ⇒ 地图放大时**必须手改**。
## 2026-09-27（达沃重制，对局尺度 ×2.25）：20 700 → **46 575**，
## 与 `WorldBuilder.SPAWN_RADIUS` 同值（两者本来就都是"旧值 × 2.25"）。
## 判据：46 575 > `TRAINING_PATROL_RADIUS` 26 910 ✓，比例 26 910/46 575 = 0.578
## 与旧值 11 960/20 700 = 0.578 一字不差（相对手感不变）。
@export var seeker_range := 46575.0
## 选目标宽锥（度）：超出它不再进候选列表；也是质量里"角度"一项的外锥。
## 1.2 实测从 45° 放宽到 **55°**：玩家的准星本来就有偏移（当时走 `MOUSE_GAIN`
## 那套增益，见 `player_controller.gd` 轮 41 的注释）、而"大致朝着它"应该算数 ——
## 45° 时侧前方的敌人会出现"看得见却锁不上"。
##
## ⚠️ **轮 41 之后这个 55° 没有重新标定过**：弹道真源改成"准星像素的
## 相机射线"之后，准星能偏得**更远**（屏幕角落约 50°，旧公式上限只有 28.81°）。
## 若出现"准星明明压在敌机上却锁不上"，先看这个宽锥，别去动 `aim_forward()`。
@export var seeker_half_angle := 55.0
## 质量里"角度满质量"的内锥（度）。外锥之内都能锁，只是慢。
## 18° 是**实测调过**的数：12° 要求玩家把机头压得很准，配合上面那五项相乘
## 直接变成"锁半天都锁不到敌人"（用户反馈）。18° 在 1600×900 下大约是屏幕中心
## 半径 200 px 的范围，属于"瞄着它飞"就能维持的精度。
@export var inner_deg := 18.0
## 锁定耗时（秒）。玩家 = `BASE_LOCK_TIME`；敌机由 `BanditAI` 按难度改写。
@export var lock_time := BASE_LOCK_TIME
## 质量衰减速率。敌机由 `BanditAI` 按难度改写。
@export var decay_rate := BASE_DECAY
## 掉到 NONE 之后多久不能再起锁（秒）。玩家 0.5，敌机按难度。
@export var relock_lockout := 0.5

## 组**空**时「自动接战」的次数上限（自动咬住候选表头名）。轮 36 新增。
##
##   · `-1`（默认）= **不限次** —— AI 火控的现状行为，**与改动前逐位相同**：
##     AI 从不调 `add_lock()` ⇒ 组里永远只有一个人 ⇒ 组空必然等于"目标没了"，
##     自动接战就是它选目标的唯一方式。
##   · `1` = **本局只自动一次**（玩家火控，见 `main.gd` 的 `player_lock`）：
##     进场保底自动锁住正前方最近的敌机，之后**完全交给玩家** ——
##     打掉目标 / 目标飞出脱锁距离 / 对方丢枪脱锁之后，火控**不再自己咬下一个**。
##   · `0` = 从不自动（留给"一律手动"的将来）。
##
## ⚠️ 计的是**次数**不是布尔：`1` 与 `-1` 是两种真实存在的玩法，用 bool 表达不了
##（"只自动一次"与"从不自动"会挤成同一个值）。
@export var auto_engage_limit := -1

## 质量里"角度"一项的外锥（度）。敌机按难度给 32 / 40 / 46。
## 默认与选目标宽锥一致 —— 于是玩家的行为是"宽锥之内都能锁，只是偏得多就慢"。
var outer_deg := 45.0

## 外部（`BanditAI`）每帧写入的**绝对覆盖倍率**：1.0 = 不覆盖。
## 猎杀规则（阿利宙斯对残血柯西）用它把 `lock_time` 压到 0.30 × 0.85 = **0.255 s**，
## 而且**不乘难度** —— 这是用户点名的例外。
var quality_override := 1.0

## 脱锁距离 = 射程 × 这个倍数（1.1 起：锁定靠"保持"，只有超距才掉）。
const LOCK_BREAK_MULT := 1.6

## 层级阈值（进入 / 迟滞回落）
const Q_LOCK := 1.0
const Q_TRACK := 0.30
const HYST_LOCK := 0.70
const HYST_TRACK := 0.15

# 5 项质量因子的调参区
#
# ⚠️ 这一组数**用户实测过一轮**：第一版按计划书原值落地（内锥 12°、角度底 0.30、
# 角速率底 0.15、对头 0.90、射程外 0.55），结果"锁半天都锁不到敌人" ——
# 原因是五项**相乘**：正面接近时 qa×qj×qb ≈ 0.75×0.5×0.9 = 0.34，
# 而累积速率原样乘 q，于是 0.85 秒的锁定被拖到 2.5 秒开外。
# 现在的原则是：**每一项都还能表达它的意思，但没任何一项能把速率打到 50% 以下**。
const RATE_FLOOR := 0.50     ## 累积速率的**下限**（q 再差也有它兜底）
const JINK_FREE := 0.45      ## 视野角速率低于它不惩罚（rad/s）
const JINK_KILL := 3.00      ## 到它就压到最低（rad/s）
const Q_JINK_MIN := 0.45
const Q_BEHIND := 1.15       ## 我在他六点
const Q_HEAD_ON := 0.95      ## 对头
const Q_FLARE := 0.35        ## 对方撒干扰弹
const Q_RANGE_FAR := 0.70    ## 出射程之后的质量上限

# ---------------------------------------------------------------- 状态

var unit: FlightBody = null

## 当前候选表：宽锥（`seeker_half_angle`）之内、射程之内、且可被锁定的敌机，
## 按"离机头瞄准线多近"排序。自动接战取它的头名，长按加锁也在这张表里挑。
var candidates: Array[FlightBody] = []

## 锁定组：**玩家纳入火控的目标集合**。长度 ≤ `MAX_LOCKS`，元素 0 是锁定对象。
##
## ⚠️ 轮 36 起它**不再**等于"锁定对象" —— 组里可以有人而**没有**锁定对象
##（`_main == null`，即锁定对象刚被击坠 / 脱锁）。见 `_main` 的注释。
##
## 想让谁当锁定对象：
##   · 组**外**的人 ⇒ `_set_main()`（清组、只留它 —— "重新选一个"）
##   · 组**内**的人 ⇒ `_set_main_in_group()`（不动组、进度照旧 —— "在已锁的目标间切换"）
## **不要**在这里直接插入/交换顺序。
var lock_group: Array[FlightBody] = []

## 每个接触的**独立**状态。`{FlightBody: {"q": float, "tier": int, "relock": float}}`
##
## ⚠️ 为什么每个成员各自一条质量条：锁定是"挣来的"，
## 不允许因为"别人锁上了"就白送一个 —— 否则锁 3 个变成被动收益。
##
## 表里**同时装组内成员与组外候选**：组外那些的质量条不是白算的，
## 它是 `add_lock()` 的门槛（"先让它成为航迹，再把它加进组"）。
var _members: Dictionary = {}

## `add_lock` 的冷却（见 `ADD_LOCK_COOLDOWN`）。
var _add_cd := 0.0

## 最近一次脱锁的原因（HUD / 提示行读它来说清"为什么掉了"）。
var last_lost_reason := ""

## 主目标上一次处于 LOCK 与否。`lock_acquired` / `lock_lost` 由它驱动。
var _was_locked := false

## 本局**已经自动接战过几次**（上限见 `auto_engage_limit`）。
var _auto_engages := 0

## **当前锁定对象**的真源。`null` = 火控此刻没有锁定对象。
##
## ⚠️ 轮 36 起 `target` **不再是** `lock_group[0]` 的别名 —— 完整理由见文件头
## 「批 2」。一句话：**组还在，但当前没有锁定对象**是一个必须能表达的状态。
##
## `null` 会一路传导下去（这是设计）：`tier()` 回 `NONE` → `locked` 为假 →
## 导弹 / 军刀 / 精确提前量全部关闭、HUD 不画主目标框。
var _main: FlightBody = null

## 当前**锁定对象**。HUD 的主目标框、导弹与军刀的门禁、AI 的 `is_locked_by_player()` 都读它。
##
## **保留字段名**（5 处调用点 + 测试直写都不用改），但真源换成了 `_main`。
##
## 赋值语义 = "强制换锁定对象"（旧版单目标的年代就是"赋值给 target"）：
## 清空锁定组、只留这一个，且它的质量条从 0 起。
## ⚠️ 类内部请走 `_set_main()`（组外）/ `_set_main_in_group()`（组内），
## 不要用属性赋值 —— 赋值会连带清组，写在 `_physics_process` 里会变成"每帧清一次组"。
var target: FlightBody:
	get:
		return _main
	set(v):
		_set_main(v)


## 主目标的质量条（0..1）。派生量：真源在 `_members[target]["q"]`。
var quality: float:
	get:
		return _q_of(target)


## 派生量：`tier() == Tier.LOCK`。保留字段名是为了让 5 处调用点一行都不用改。
var locked: bool:
	get:
		return tier() == Tier.LOCK


func setup(owner_unit: FlightBody) -> void:
	unit = owner_unit


## 脱锁距离（米）。
func lock_break_range() -> float:
	return seeker_range * LOCK_BREAK_MULT


func tier() -> int:
	return _tier_of(target)


func tier_name() -> String:
	match tier():
		Tier.TRACK:
			return "追踪"
		Tier.LOCK:
			return "锁定"
	return "搜索"


## HUD 画质量环用（1.1 的 `lock_ratio()` 就是它）。
func track_ratio() -> float:
	return quality


func lock_ratio() -> float:
	return quality


## 导弹 / 军刀 / 精确提前量的门禁（= 稳定锁定）。
func is_locked() -> bool:
	return tier() == Tier.LOCK


## 光束步枪 / 火神炮的门禁（追踪及以上）。
func can_track() -> bool:
	return tier() != Tier.NONE


# ============================================================ 批 1：锁定组

## 组内**已经稳定锁定**的成员（按组内顺序）。火力按它们的数量平分。
##
## ⚠️ 这是 `fire_funnel()` 唯一该读的东西 —— 不要用 `lock_group.size()`：
## 刚加入组的成员还没锁上（层级是 NONE），它**不该**分到弹
## （否则"长按 Tab 白嫖一次齐射"就成了最优解）。
func locked_in_group() -> Array[FlightBody]:
	var out: Array[FlightBody] = []
	for fb: FlightBody in lock_group:
		if _tier_of(fb) == Tier.LOCK:
			out.append(fb)
	return out


## 某个接触在组里的槽位（0 = 主目标）；不在组里返回 -1。
func group_index(fb: FlightBody) -> int:
	return lock_group.find(fb)


## 某个接触是不是**当前锁定对象**。
##
## ⚠️ 轮 36 起它与「`group_index() == 0`」**不是一回事**：锁定对象被击坠后
## `_main` 为 `null`，而 `lock_group[0]` 已经是"下一个顺位"了。
func is_main(fb: FlightBody) -> bool:
	return fb != null and fb == _main


## 某个接触的质量条 / 层级。HUD 画组内每个成员的圈用的是这两个。
func quality_of(fb: FlightBody) -> float:
	return _q_of(fb)


func tier_of(fb: FlightBody) -> int:
	return _tier_of(fb)


## 把某个接触**加入锁定组**。返回是否真的加进去了。
##
## 门槛有六道，每一道都是"这是不是一次合法的加人"：
##   ① 冷却已过（`ADD_LOCK_COOLDOWN`）；② 组没满；③ 不在组里；
##   ④ 活着且没被强制脱锁；⑤ 敌对；⑥ 在射程内；
##   ⑦ **已经建立航迹**（`Tier.TRACK`）—— 见下。
##
## ⑦ 是这一版里最"讲究"的一条：它让"锁 3 个"变成一个**要花时间挣**的状态 ——
## 你得先把机头扫过第二、第三个敌人各零点几秒，它们才会进组。
## 没有它，玩家可以在一开始就把 3 个名额填满，而"火力分散"这个代价
## 就变成"开局按一下"就付完了，不构成任何取舍。
func add_lock(fb: FlightBody) -> bool:
	if unit == null or fb == null or not is_instance_valid(fb):
		return false
	if _add_cd > 0.0 or lock_group.size() >= max_locks:
		return false
	if lock_group.has(fb) or not fb.alive or fb.is_unlockable():
		return false
	if not fb.is_hostile_to(unit):
		return false
	if unit.global_position.distance_to(fb.global_position) > seeker_range:
		return false
	if _tier_of(fb) == Tier.NONE:
		return false
	lock_group.append(fb)
	_member(fb)
	_add_cd = ADD_LOCK_COOLDOWN
	return true


## 把**当前候选表里质量最高、还没进组**的那个敌人加进组。
##
## 玩家侧的输入（长按 Tab / 长按十字键 ↑）走这条：玩家没法用光标点一个
## "除了主目标之外的敌人"，能用的只有"机头大致朝谁"。
## 用质量最高而不是距离最近，是为了跟"机头指向"一致 ——
## 玩家扫过谁，加进去的就是谁。
func add_lock_nearest() -> bool:
	var best: FlightBody = null
	var best_q := -1.0
	for fb: FlightBody in candidates:
		if lock_group.has(fb) or _tier_of(fb) == Tier.NONE:
			continue
		var qv := _q_of(fb)
		if qv > best_q:
			best_q = qv
			best = fb
	return add_lock(best) if best != null else false


## 火力分配表：`total` 发弹按 `k` 个已锁定目标平分，**余数补给靠前的**。
##
## K = 1 → 3 发全给主目标（**现状，零回归**）
## K = 2 → 2 / 1
## K = 3 → 1 / 1 / 1
##
## **为什么余数给靠前的而不是随机**：随机分配会让同一套输入产出不同手感，
## 玩家没法建立"按一次扳机 = 会发生什么"的预期。靠前的顺序是"离机头最近"，
## 也就是玩家最可能在瞄的那个 —— 余数给它是符合直觉的。
##
## **代价的数学**（写给后人，免得有人"顺手把 K=3 加强"）：
##   3 发打一个目标 ⇒ 近炸引信有 3 次命中机会、覆盖一片；
##   1 发打一个目标 ⇒ 只有 1 次机会。
##   ⇒ 目标数变多、**总弹量不变** ⇒ 单位目标的期望伤害降为 1/K 量级。
##   这就是需求里「火力分散」的精确含义，**不需要再额外加惩罚**
##   （再加一层，K=3 就永远不划算 = 机制白做）。
static func salvo_split(total: int, k: int) -> Array[int]:
	var out: Array[int] = []
	if k <= 0:
		return out
	var base := int(total / k)
	var rest := total % k
	for i in k:
		out.append(base + (1 if i < rest else 0))
	return out


# ============================================================ 每帧

func _physics_process(delta: float) -> void:
	if unit == null or not is_instance_valid(unit) or not unit.alive:
		return
	_add_cd = maxf(_add_cd - delta, 0.0)
	_refresh_candidates()
	_validate_group()
	# 自动接战：**组空**时才发生，且受 `auto_engage_limit` 约束（轮 36）。
	# `_set_main` 会把接战到的那个人的质量条清零，于是"接战到锁定"仍是完整的一轮 `lock_time`。
	#
	# ⚠️ 判据必须是「**组**空」而不是「锁定对象为空」：
	# 轮 36 之后这两个不再等价 —— 锁定对象被击坠而组里还有别人时，
	# `_main` 为 `null` 但组非空。那种情况**绝不能**自动接战，
	# 那正是用户点名要禁掉的"自动切换锁定对象"。
	if lock_group.is_empty() and _can_auto_engage() and not candidates.is_empty():
		_auto_engages += 1
		_set_main(candidates[0])
	_update_group(delta)


## 这一刻还允许自动接战吗（见 `auto_engage_limit`）。
func _can_auto_engage() -> bool:
	if auto_engage_limit < 0:
		return true
	return _auto_engages < auto_engage_limit


func _refresh_candidates() -> void:
	candidates.clear()
	if unit == null:
		return
	# 自动选目标用的是**机头方向**，不是鼠标准星方向（`aim_forward()`）。
	# 1.1 起鼠标可以打着侧后方的敌人（准星只管弹道），如果这里跟着准星走，
	# 玩家把准星甩到一边就会顺手换掉锁定目标 —— 那不是玩家想要的。
	# 显式选目标请用鼠标（`select_target`）或 Tab（`cycle_target`）。
	var fwd := unit.forward()
	var scored: Array = []
	for h: Node3D in Game.live_hostiles_of(unit):
		var fb := h as FlightBody
		if fb == null:
			continue
		# 柯西丢枪后的"不可被锁定"窗口：直接不进候选列表
		if fb.is_unlockable():
			continue
		var to := fb.global_position - unit.global_position
		var dist := to.length()
		if dist > seeker_range:
			continue
		var ang := Ballistics.angle_off_boresight(fwd, to)
		if ang > seeker_half_angle:
			continue
		scored.append({"unit": fb, "ang": ang, "dist": dist})
	# 主排序键是"离机头瞄准线多近"，距离只作为次要权重 —— 这样玩家用机头选目标
	scored.sort_custom(func(a, b):
		var sa: float = a["ang"] + a["dist"] / seeker_range * 12.0
		var sb: float = b["ang"] + b["dist"] / seeker_range * 12.0
		return sa < sb)
	for s: Dictionary in scored:
		candidates.append(s["unit"])
	# 鼠标选中的目标可能在宽锥之外（鼠标可以选侧后方的敌人），
	# 但用它做 `cycle_target()` 的起点时**必须**在候选表里，否则 Tab 会从别人身上重新开始。
	#
	# ⚠️ `target.alive` 这一条**必须有**，它是「组内全存活」这条不变量的根：
	# 候选表同时是**自动接战的取人头**（`_physics_process` 里 `_set_main(candidates[0])`），
	# 而主目标在**被 `_validate_group()` 移出组的那一帧**仍然是 `target`
	#（`_refresh_candidates()` 排在 `_validate_group()` 之前）。
	# 少了这一条，那具已经爆掉的残骸会被重新塞回候选表 ⇒
	# 下一个物理帧又「接战」到它、又被移出、再被塞回 —— **锁定框永远停在一具残骸上**。
	#
	# 实测：`suite_multi_lock / 锁定组的不变量` 里「全部成员失效 ⇒ 组空」那两条就是被它挂掉的
	#（该套件造的是**没向 Game 注册**的 `LockOnSystem`，和 `suite_combat` 同一种构造）。
	# 生产路径上 `FlightBody.destroy()` 会先同步调 `Game.forget_locks_of(self)` 把尸体清掉，
	# 所以这一条平时不显形 —— 但**不变量不该依赖「外面有没有人帮你清」**。
	if target != null and is_instance_valid(target) and target.alive \
			and not candidates.has(target) \
			and not target.is_unlockable() \
			and unit.global_position.distance_to(target.global_position) <= seeker_range:
		candidates.append(target)


## 把组里"已经不该留"的成员移出去。**逐条对应旧 `_validate_target()` 的三个丢目标路径。**
##
## ⚠️ 与旧版的区别：旧版"丢目标"= 整个锁定作废；现在只移出**那一个**，
## 组里其余成员照常留在组内。
##
## ⚠️ 轮 36 再改一条：主目标被移出时**不再顺位补位**（旧版"顺位补上主目标"）。
## 组里剩谁就剩谁，但**锁定对象变成 `null`** —— 玩家不按 Tab 就不会换。
func _validate_group() -> void:
	if lock_group.is_empty():
		_gc_members()
		return
	for i in range(lock_group.size() - 1, -1, -1):
		var fb := lock_group[i]
		var why := _invalid_reason(fb)
		if why == "":
			continue
		# 只有主目标的离开才写 `last_lost_reason`（HUD 那一行说的是"为什么丢了锁定"，
		# 2 号/3 号掉出去不该改它）。
		_remove_group_member(fb, why if i == 0 else "")
	_gc_members()


## 它"不该留在组里"的原因；空串 = 没问题。
func _invalid_reason(fb: FlightBody) -> String:
	if not is_instance_valid(fb) or fb.is_queued_for_deletion() or not fb.alive:
		return "目标被击坠"
	# 对方进入"不可被锁定"状态（丢枪）→ 立刻移出，且在此期间选不回来
	if fb.is_unlockable():
		return "对方强行脱锁"
	# 只有"超出脱锁距离"会直接移出；角度/机动/干扰弹都只让**质量**往下走
	# （迟滞之后才掉层，掉到 NONE 也只是进入重新起锁的冷却，成员仍然留着）。
	if unit != null and unit.global_position.distance_to(fb.global_position) > lock_break_range():
		return "超出锁定距离 %.0f km" % (lock_break_range() / 1000.0)
	return ""


## 移出组外 + 丢掉它的成员状态。
##
## ⚠️ 若它是**锁定对象** ⇒ `_main` 变 `null`，**不做顺位补位**（轮 36 的核心落点）。
##
## 组内其余成员**留在组里**，各自的质量条 / 层级 / 锁定进度**一个都不动** ——
## 玩家按一下 Tab 就能把队首那个切上来（`cycle_target()`），**不按就不会换**。
## 这正是需求「除非玩家手动切换锁定，不然不会自动切换锁定对象」的落点。
func _remove_group_member(fb: FlightBody, reason := "") -> void:
	var idx := lock_group.find(fb)
	if idx < 0:
		return
	var was_main := fb == _main
	lock_group.remove_at(idx)
	_members.erase(fb)
	if was_main:
		_main = null
		if reason != "":
			last_lost_reason = reason
		target_changed.emit(null)
	_sync_lock_signal()


## 清理"已经没了"的成员状态（击坠 / 出表 / 出了候选表）。
##
## 出了候选表就把进度丢掉，是**故意的**：候选表本来就是"机头朝向之内"的定义，
## 一架敌机从你的视野里飞出去再回来，那中间的时间不该被算成"你一直在跟它"。
func _gc_members() -> void:
	for k in _members.keys():
		var fb := k as FlightBody
		if fb == null or not is_instance_valid(fb) or not fb.alive \
				or (not lock_group.has(fb) and not candidates.has(fb)):
			_members.erase(k)


## 旧版的 `_drop_target()`：**丢掉整个锁定组**。
##
## ⚠️ 现在它只剩一个调用点（`cycle_target()` 在候选表为空时用它），
## 因为"逐个成员失效"的路径已经归 `_validate_group()` + `_remove_group_member()`。
## 保留它是因为那条路径的语义确实就是"这次锁定整个作废"：
## 候选表空了 ⇒ 没有任何可以锁的东西 ⇒ 组自然该清空。
func _drop_target(reason := "") -> void:
	if reason != "":
		last_lost_reason = reason
	lock_group.clear()
	_main = null
	target_changed.emit(null)
	_sync_lock_signal()


## 由被锁定方调用（丢枪技能）：若它正在我的锁定组里，强制移出。
func force_drop_if_target(who: Node3D) -> bool:
	var fb := who as FlightBody
	if fb == null or not lock_group.has(fb):
		return false
	_remove_group_member(fb, "对方强行脱锁")
	return true


## 主目标的 LOCK 状态翻转 → 发 `lock_acquired` / `lock_lost`。
##
## ⚠️ **只由这里发这两个信号**（旧版散在 `_set_tier()` 里）：
## 主目标是"组的 0 号"，而 0 号会因为组成员进出而换人 ——
## 把发信号集中在一处，换人时就不会漏发或多发。
func _sync_lock_signal() -> void:
	var now := locked
	if now and not _was_locked:
		_was_locked = true
		lock_acquired.emit(target)
	elif not now and _was_locked:
		_was_locked = false
		lock_lost.emit()


# ============================================================ 选目标

## 换锁定对象 = **重新选**：清空组、只留它，且它的质量条从 0 起。
##
## ⚠️ 这是"K=1 逐位相同"的**唯一**关口。旧代码里三处换主目标的写法都是
## 「赋 `target` + `quality = 0` + 层级回 NONE」，这里一次做全。
##
## ⚠️ **它会清组** —— 只适用于"玩家重新选了一个组**外**的目标"。
## 组**内**轮转（`cycle_target()` / `select_target()` 命中已在组里的目标）
## **不能**走它：那会把玩家辛苦锁的其余成员连进度一起清掉，
## 要走 `_set_main_in_group()`。
func _set_main(fb: FlightBody) -> void:
	lock_group.clear()
	_main = fb
	if fb != null:
		lock_group.append(fb)
		_set_q_of(fb, 0.0)
		_member(fb)["relock"] = 0.0
		_member(fb)["tier"] = Tier.NONE
	last_lost_reason = ""
	target_changed.emit(_main)
	_sync_lock_signal()


## 把**组内**某个成员提为锁定对象。**不动组、不清质量条**（那是它自己挣来的）。
##
## 与 `_set_main()` 的分工：
##   · 这一条 = "玩家在**已经锁定**的几个目标之间切换"（Tab 轮转 / 数字键点到组内成员）
##   · 那一条 = "玩家重新选了一个目标"（清组重来）
##
## 维持不变量②：锁定对象排在组首（`salvo_split()` 的余数补给靠前的）。
func _set_main_in_group(fb: FlightBody) -> void:
	if fb == null or not lock_group.has(fb):
		return
	_main = fb
	lock_group.erase(fb)
	lock_group.push_front(fb)
	last_lost_reason = ""
	target_changed.emit(_main)
	_sync_lock_signal()


## 鼠标光标选目标。返回是否真的换了目标。
##
## 只有"在射程内、活着、可被锁定"的敌机才接受 —— 光标扫过一片空地不该把锁定清掉，
## 所以非法/空目标一律**返回 false 且不动当前目标**。
##
## 若它**已经在组里**，那只是"把它提成锁定对象"（组不变，它的质量条也不动 ——
## 那是它自己挣来的）；否则按"重新选一个目标"处理（组重置成它一个）。
##
## ⚠️ 轮 36 起**只有一个调用点**：数字键直选（`PlayerController.select_contact`）。
## 鼠标那条已经删了 —— 用户要求"鼠标只管准星"，锁定对象绝不会因为光标飘过去而变。
func select_target(fb: FlightBody) -> bool:
	if unit == null or fb == null or not is_instance_valid(fb):
		return false
	if not fb.alive or fb.is_unlockable() or fb == target:
		return false
	if not fb.is_hostile_to(unit):
		return false
	if unit.global_position.distance_to(fb.global_position) > seeker_range:
		return false
	if lock_group.has(fb):
		_set_main_in_group(fb)
		return true
	_set_main(fb)
	return true


## 手动切换锁定对象（Tab 点按 / 手柄十字键 ↑）。
##
## 轮 36 起分三段，顺序不能换：
##
##   1. **没有锁定对象、但组里还有人**（= 刚被击坠 / 脱锁之后）⇒
##      把队首那个**顶上来**。这是需求里「按一下 Tab 就能切过去」的落点：
##      组内成员的锁定进度一个都没丢，所以切过去是**瞬间**的，不必重锁一遍。
##   2. **组内 > 1 人** ⇒ 在组内轮转（旋转组，让锁定对象回到队首）。
##      这正是"锁定组"的意义：已经把这几架纳入火控，切换就该在这几架里切。
##   3. **组内 ≤ 1 人**（含空组）⇒ 保持旧行为，在**候选表**里循环。
##      ⚠️ 这一支**会清组**（走 `_set_main`）—— 但此时组里最多只有锁定对象自己，
##      清掉等于没清，所以 K=1 的体验一字未变。
##
## ⚠️ 第 3 支的条件必须是「组内 ≤ 1」而不是「组内 < 2」的字面等价写法：
## 若把"组内只有 1 人"也并进第 2 支，那个 1 人旋转完还是自己 ⇒ **Tab 切不动了**
##（玩家锁着 A 想按 Tab 换 B，会发现按键失灵）。
func cycle_target() -> void:
	if _main == null and not lock_group.is_empty():
		_set_main_in_group(lock_group[0])
		return
	if lock_group.size() > 1:
		# ⚠️ 显式标类型：`Array.pop_front()` 返回 Variant，
		# 而本工程开了"推断自 Variant 即报错"的警告（当错误处理）。
		var first: FlightBody = lock_group.pop_front()
		lock_group.append(first)
		_set_main_in_group(lock_group[0])
		return
	if candidates.is_empty():
		_drop_target()
		return
	if target == null:
		_set_main(candidates[0])
	else:
		var idx := candidates.find(target)
		_set_main(candidates[(idx + 1) % candidates.size()])


# ============================================================ 方案 A：质量条

## **纯函数**：某个接触这一刻的"目标质量"（0..1）。不写状态、不随机，可直接单测。
##
## 五项相乘（缺一项都会让某类机动失去意义）：
##   角度 × 距离 × 视野角速率 × 后半球 × 干扰弹
func target_quality_of(fb: FlightBody) -> float:
	if fb == null or not is_instance_valid(fb) or unit == null:
		return 0.0
	var to := fb.global_position - unit.global_position
	var dist := to.length()
	var los := to / maxf(dist, 0.001)

	# ⚠️ **§11 回退（1.2 第十一轮，用户拍板）：三项与角度有关的因子钉成 1.0。**
	#
	# 质量条跑了三轮，结论是它对玩家不公平：AI 的机头天生比人稳，
	# 而玩家在"准星瞄准、键盘飞"的操作下要么被角度卡住、要么靠放宽参数绕过去
	# （前两轮我都在放宽参数，越放越像"没有质量条"，说明方向不对）。
	# 现在把 角度 / 视野角速率 / 后半球 三项**钉成常量**，语义立刻回到**计时锁定**，
	# 但**结构一行不删** —— 将来想再开（或者换成"地形/云层遮挡断锁"）就是改这三行。
	#
	# 保留的东西：距离项（超距脱锁的过渡）、干扰弹（撒了就不推进）、
	# `quality_override`（猎杀规则，本来就是"耗时倍率"语义）、三层显示、难度锁定倍率。
	var qa := 1.0        # 原：角度（准星内外锥）—— 回退
	var qj := 1.0        # 原：视野角速率（机动即防御）—— 回退
	var qb := 1.0        # 原：后半球（咬尾吃香 / 对头吃亏）—— 回退
	if false:            # 下面这段保留为参考实现（回退时用不到，但不删）
		var ang := Ballistics.angle_off_boresight(unit.aim_forward(), to)
		qa = 1.0
		if ang > outer_deg:
			qa = 0.0
		elif ang > inner_deg:
			qa = lerpf(1.0, Q_TRACK, (ang - inner_deg) / maxf(outer_deg - inner_deg, 0.001))
		var rel_v0 := fb.fm.velocity - unit.fm.velocity
		var omega0 := (rel_v0 - los * rel_v0.dot(los)).length() / maxf(dist, 1.0)
		qj = 1.0
		if omega0 > JINK_FREE:
			qj = lerpf(1.0, Q_JINK_MIN,
				clampf((omega0 - JINK_FREE) / maxf(JINK_KILL - JINK_FREE, 0.001), 0.0, 1.0))
		var nose0 := fb.forward()
		qb = 1.0
		if nose0.dot(los) > 0.62:
			qb = Q_BEHIND
		elif nose0.dot(-los) > 0.87:
			qb = Q_HEAD_ON

	# 2) 距离：射程内 1.0 → 0.55；出射程往下掉，到脱锁距离归零
	var qd := 1.0
	if dist > seeker_range:
		qd = Q_RANGE_FAR * clampf(
			1.0 - (dist - seeker_range) / maxf(lock_break_range() - seeker_range, 1.0), 0.0, 1.0)
	elif dist > seeker_range * 0.35:
		qd = lerpf(1.0, Q_RANGE_FAR, (dist - seeker_range * 0.35) / (seeker_range * 0.65))

	# 3) 视野角速率 / 4) 后半球：**已按 §11 回退**（上面钉成常量 1.0，
	#    参考实现的代码在回退块里，这里不再重复计算）。

	# 5) 干扰弹（C-3）
	var qf := Q_FLARE if fb.flares_active() else 1.0

	return clampf(qa * qd * qj * qb * qf * quality_override, 0.0, 1.0)


## 主目标的"目标质量"。保留旧签名（HUD / 测试在读它）。
func target_quality() -> float:
	return target_quality_of(target)


## 每帧推进**组内成员与候选表**里每一个接触的质量条。
##
## 组外候选也要推进：它们的质量条是 `add_lock()` 的门槛（"先建立航迹"）。
## 而 K=1 时这些组外进度**没有任何读取点** —— 于是"K=1 逐位相同"成立。
func _update_group(delta: float) -> void:
	for fb: FlightBody in lock_group:
		_update_member(fb, delta)
	for fb: FlightBody in candidates:
		if not lock_group.has(fb):
			_update_member(fb, delta)
	_sync_lock_signal()


func _update_member(fb: FlightBody, delta: float) -> void:
	if fb == null or not is_instance_valid(fb) or not fb.alive:
		return
	var m := _member(fb)
	if m["relock"] > 0.0:
		# 掉层之后的"重新起锁冷却"：这段时间质量起不来（玩家 0.5 s，敌机按难度更久）
		m["relock"] = maxf(float(m["relock"]) - delta, 0.0)
		_set_q_of(fb, _q_of(fb) - delta * decay_rate)
	elif fb.flares_active():
		# 干扰弹：**不推进**（方案原话），也不掉 —— 就是冻住。
		# 这让"撒干扰弹"成为一个确定的事件式反制，而不是概率。
		pass
	else:
		var q := target_quality_of(fb)
		if q > 0.05:
			# ⚠️ **只要 q 不为零就朝 1.0 推进**，速率由 q 决定（歪着也能锁，只是慢）。
			#
			# 这是我在 1.2 里犯过的最贵的一个错：原来的写法是
			#     `if q > quality: 涨  else: 掉`
			# 那等于让质量**收敛到 q 而不是 1.0**，而 LOCK 阈值恰恰是 1.0 ——
			# 于是只要 q < 1（4 km 处 0.90、对头 0.95、目标一机动、对方撒干扰弹），
			# 质量就永远差一点点，稳定锁定永远拿不到 → 导弹与军刀形同虚设。
			# 用户三次反馈"锁半天锁不上""锁不上敌人"，根因都在这一行。
			# 现在只有"推进（目标恒为 1.0）"与"衰减"两种状态。
			var t := maxf(lock_time * quality_override, 0.05)
			_set_q_of(fb, _q_of(fb) + delta / t * maxf(q, RATE_FLOOR))
		else:
			# q ≈ 0：目标飘到脱锁距离之外或彻底看不见 → 衰减（质量越低掉得越快）
			_set_q_of(fb, _q_of(fb) - delta * decay_rate * maxf(1.0 - q, 0.35))
	_refresh_tier_of(fb)


## 迟滞分层（见文件头的阈值表）。**逐成员**跑 —— 这是"每个成员各自一条质量条"的落点。
func _refresh_tier_of(fb: FlightBody) -> void:
	var cur := _tier_of(fb)
	var qv := _q_of(fb)
	var want := cur
	match cur:
		Tier.LOCK:
			want = Tier.LOCK if qv >= HYST_LOCK else (Tier.TRACK if qv >= HYST_TRACK else Tier.NONE)
		Tier.TRACK:
			want = Tier.LOCK if qv >= Q_LOCK else (Tier.TRACK if qv >= HYST_TRACK else Tier.NONE)
		_:
			# 从 NONE 起锁要跨过"进入阈值"（比回落阈值高），否则会在 0.15 上抖
			want = Tier.LOCK if qv >= Q_LOCK else (Tier.TRACK if qv >= Q_TRACK else Tier.NONE)
	if want != cur:
		_set_tier_of(fb, want)


func _set_tier_of(fb: FlightBody, t: int) -> void:
	var m := _member(fb)
	var was := int(m["tier"])
	if t == was:
		return
	m["tier"] = t
	if t == Tier.NONE and was != Tier.NONE:
		m["q"] = 0.0
		m["relock"] = relock_lockout
	# `tier_changed` 是**主目标**的层变化（HUD 与警报只关心主目标）。
	# 组内 2 号 / 3 号的层变化有它们自己的读取点（`tier_of()`）。
	if fb == target:
		tier_changed.emit(t)


## 强制进入稳定锁定（质量拉满 + 层推到 LOCK）。
##
## 用途是"跳过 0.85 秒的累积过程"：调试、剧本演出，以及测试里
## "我只想验证导弹能不能打出去"这类**与质量无关**的断言。
## ⚠️ 正常战斗流程里**不要**调它 —— 那等于把方案 A 的质量条整个绕过去。
func force_lock() -> void:
	if target == null or not is_instance_valid(target):
		return
	_set_q_of(target, 1.0)
	_member(target)["relock"] = 0.0
	_set_tier_of(target, Tier.LOCK)
	_sync_lock_signal()


## "为什么现在锁不上" —— 给 HUD 用的一句话。
##
## 起因是用户两次反馈"锁不上"：质量条本身没问题，但**玩家看不到自己差在哪一项**，
## 于是只能反复试。这一句把当前最拖后腿的那一项说出来（角度 / 射程 / 目标机动 / 干扰弹）。
func block_reason() -> String:
	if target == null or not is_instance_valid(target) or unit == null:
		return "无目标"
	var to := target.global_position - unit.global_position
	var dist := to.length()
	if dist > lock_break_range():
		return "超出锁定距离"
	var ang := Ballistics.angle_off_boresight(unit.aim_forward(), to)
	if ang > outer_deg:
		return "准星偏出锁定锥（%.0f° > %.0f°）" % [ang, outer_deg]
	if dist > seeker_range:
		return "超出射程 %.1f km" % (dist / 1000.0)
	if target.flares_active():
		return "对方干扰弹生效中"
	var rel_v := target.fm.velocity - unit.fm.velocity
	var los := to / maxf(dist, 0.001)
	var omega := (rel_v - los * rel_v.dot(los)).length() / maxf(dist, 1.0)
	if omega > JINK_FREE:
		return "目标高速机动（%.2f rad/s）" % omega
	if float(_member(target)["relock"]) > 0.0:
		return "重新起锁冷却 %.1f s" % float(_member(target)["relock"])
	return "" if locked else "质量 %.0f%%" % (quality * 100.0)


## 机炮提前量落点（HUD 的 lead indicator）。**只有稳定锁定才给**（见文件头的三层表）。
func gun_lead_point(projectile_speed: float) -> Vector3:
	if target == null or not is_instance_valid(target) or tier() != Tier.LOCK:
		return Vector3.ZERO
	return Ballistics.intercept_point(
		unit.global_position, target.global_position, target.fm.velocity, projectile_speed)


## 光束步枪提前量落点（HUD 的另一个圈）。
##
## ⚠️ 与 `gun_lead_point()` 的差别**不在半径也不在判定**，在**解算模型**：
## 光束的弹道是两段式（出膛慢 → 接近光速），工程里**不存在"光束弹速"这个数**了，
## 所以走 `Ballistics.beam_lead_point()`。混用会让 HUD 画的点和实际弹道对不上
##（本文件与 `SuitProfile` 都点名过这一类偏差）。
func gun_lead_point_beam() -> Vector3:
	if target == null or not is_instance_valid(target) or tier() != Tier.LOCK:
		return Vector3.ZERO
	return Ballistics.beam_lead_point(
		unit.global_position, target.global_position, target.fm.velocity,
		unit.profile.rifle_steady_speed if unit.profile != null else 0.0)


func angle_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	return Ballistics.angle_off_boresight(
		unit.forward(), target.global_position - unit.global_position)


func range_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	return unit.global_position.distance_to(target.global_position)


# ============================================================ 成员状态存取
#
# 内层一律走这几个函数。它们存在的理由就一条：**质量条从"一份"变成"一目标一份"**
# 之后，`quality` / `_tier` 那种单变量写法就再也表达不了状态了 ——
# 与其留着一堆"其实是主目标的"别名，不如把读写口收在一处。

func _member(fb: FlightBody) -> Dictionary:
	var m: Dictionary = _members.get(fb, {})
	if m.is_empty():
		m = {"q": 0.0, "tier": Tier.NONE, "relock": 0.0}
		_members[fb] = m
	return m


func _q_of(fb: FlightBody) -> float:
	if fb == null:
		return 0.0
	return float(_members.get(fb, {}).get("q", 0.0))


func _tier_of(fb: FlightBody) -> int:
	if fb == null:
		return Tier.NONE
	return int(_members.get(fb, {}).get("tier", Tier.NONE))


func _set_q_of(fb: FlightBody, v: float) -> void:
	if fb == null:
		return
	_member(fb)["q"] = clampf(v, 0.0, 1.0)
