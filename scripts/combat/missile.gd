class_name Missile
extends Node3D
## 导弹（本项目里的"ファンネル・ミサイル"）。
##
## 制导：限速率纯追踪 + 命中点提前量。刻意不做完全的比例导引——
## 限速率才能让玩家靠"急转 + 甩尾"把导弹甩掉，这是缠斗的乐趣来源。
##
## 三种终止方式：近炸引信 / 撞地 / 燃料耗尽自毁。

const WORLD_LAYER := 1 << 0
const UNIT_LAYER := 1 << 1

var speed := 130.0
## 最大速度。**真源是 `SuitProfile.missile_speed()`**（"导弹比佩涅罗佩的巡航上限
## 快 2.6 倍"，见那里的注释）—— 别在这里写死：弹速要和机体速度一起调，
## 两处各写一份迟早对不上。
var max_speed := SuitProfile.missile_speed()
## 从发射初速爬到最大速度用多久（秒）。
## **加速度由它反推**（见 `_ready()`）：速度上限抬高时加速度必须跟着抬，
## 否则"弹速调快了"只体现在后半段，前半段还是慢慢悠悠 —— 手感上根本不像变快了。
var accel_time := 2.4
## 加速度 m/s²。由 `accel_time` 算出来；保留这个字段是为了让探针/测试能直接读。
var accel := 260.0
var turn_rate := 2.1          # rad/s，随飞行时间衰减
var turn_decay := 0.055

## ---- 浮游导弹的「跟踪能力」（轮 15：−25%）----
##
## 用户原话：「浮游导弹的跟踪能力减弱 25%」。
##
## ## 「跟踪能力」的口径 = 整条**转向角速度曲线**（rad/s）
## 每帧真正用的角速度是 `maxf(turn_rate − turn_decay · age, TURN_FLOOR)`（见 `_physics_process`）。
## 「减弱 25%」的可验证含义就是**这条曲线整体乘 0.75** ⇒ 上限与衰减**一起**乘 0.75：
##
##     rate_new(a) = 0.75 · (3.4 − 0.04·a) = 2.55 − 0.03·a = 0.75 · rate_old(a)     ← 精确
##
## ## 为什么**必须**连衰减一起缩（第一版只缩了上限，被自己的测试抓出来）
## 只缩上限、留着 `turn_decay = 0.04`，得到的是 `2.55 − 0.04a` —— 那是把曲线**平移** −0.85，
## 不是**缩放**。于是实际减弱幅度随弹龄漂移：
##
##     age  0.0 s → 2.55 / 3.40 = **0.750**（−25.0%）
##     age  0.6 s → 2.53 / 3.38 = 0.748
##     age 14.0 s → 1.99 / 2.84 = **0.701**（−30.0%）
##
## 那既不是「减弱 25%」也不是别的什么整数 —— 弹越老钝得**更多**，
## 而这层"额外惩罚"是本轮**没人要求**的。乘同一条曲线则让 −25% 在**整个寿命内精确成立**：
##
##   下限 `TURN_FLOOR = 0.55` 咬住曲线的时刻 ——
##     旧：age = (3.4 − 0.55) / 0.04 = 71.25 s
##     新：age = (2.55 − 0.55) / 0.03 = 66.67 s
##   而 `Missile.lifetime = 14 s` ⇒ **两条曲线在寿命内都够不到下限**
##（够得到的话，尾部比值会被下限截断抬高，"全程 −25%"就不成立了）。
##
## ## 有意**不动**的东西
## · `SuitProfile.missile_speed()`（弹速上限）—— 那是**速度**不是**转向**。
## · `deploy_time` / `accel_time` / `fuse_radius` —— 展开段 / 加速 / 引信，都在别的轴上。
## · 导引头视场 / `decoy_chance` —— 那是「跟谁」不是「跟得多快」。
## · 普通导弹的 `turn_rate = 2.1` —— 本轮的改动**不能漏过去**（测试②在核这条）。
const FUNNEL_TURN_RATE := 2.55
const FUNNEL_TURN_DECAY := 0.03
## 改前的两个基线值。**只给测试与文档用**：判据是「新 / 旧 == 0.75」，
## 有它们才能把 −25% 写成可回归的**比值**，而不是把两个魔法数字抄进测试。
const FUNNEL_TURN_RATE_WAS := 3.4
const FUNNEL_TURN_DECAY_WAS := 0.04

## 转向角速度的**下限**（rad/s）：`rate = maxf(turn_rate − turn_decay·age, TURN_FLOOR)`。
## 抽成常量只为了让测试能算「下限什么时候咬住」（见上面那段：两条都要到 66 s 以后，
## 而 `lifetime = 14 s`）—— 散在函数体里的字面量算不了这个账。
const TURN_FLOOR := 0.55

var damage := 45.0
var damage_type := Damage.Type.FUNNEL
var fuse_radius := 26.0
var lifetime := 14.0
var lead_factor := 0.7
## 每秒被干扰弹骗走的概率（目标在导引头锥内放了干扰弹时）。
var decoy_chance := 1.1
## 展开时间：这段时间内不制导，先沿初速飞出去 —— 浮游导弹"从挂架弹出去再转向"的观感。
var deploy_time := 0.0

## ---- 载机速度继承（轮 13）----
##
## ## 需求
## 用户原话：「导弹和光束都得是从机体身上发射出去的，**现在完全看不到导弹的发射了**」。
##
## ## 根因：导弹**不带载机速度**，一离架就被甩掉
## 出膛初速 `speed = 90 m/s`（浮游导弹）是**相对地面**给的，而机体在 `×2.4` 之后
## 加力极速已达 **2268 – 2414 m/s**（柯西 / 佩涅罗佩 → 阿利宙斯巡航，后者最快）。
## 于是离架那一瞬间，导弹相对机体以 **≈2.4 km/s 向后**跑（下表取最快的 2414 算）：
##
##   | 时刻 | 机体已飞 | 导弹已飞 | 导弹落在相机后面 |
##   |---|---|---|---|
##   | 0.15 s | 362 m | 13 m | −349 m（还在视野边缘） |
##   | 0.55 s（deploy 段结束，刚开始制导） | 1328 m | 49 m | **−1278 m（早已出画）** |
##
## （⚠️ 上面两行是**不含继承项**的老行为。加上继承 + 1.6 s 线性衰减之后，弹体在 0.55 s
## 内沿机头方向已经跟出 **1061 m**（载机 2344 m/s 的实测；老行为在同一条轴上位移 **0 m**，
## 因为它的初速是相对地面的）。距机体的三维距离：**331 m**（老行为 **1619 m**）。
## 详见 `tests/funnelprobe.gd` 与 `suite_missile_smoke` 的「载机速度继承」节。）
##
## 相机是跟随机体的，所以玩家从头到尾**看不到那一发弹**。
## 备机加速到 4062 m/s 是 1.7 s 之后的事 —— 那时它早就不在画面里了。
##
## ## 修法：离架瞬间**继承载机速度**，再按时间衰减掉
##
## 真实的空射导弹就是这么走的（载机 2 km/s 打出去的弹，初速天然带 2 km/s）。
## 继承之后在**相机参考系**里，导弹以 `90 m/s` 沿自己的弹射方向离开挂架 ——
## 正是"看得见的发射"该有的样子。而绝对弹道仍然由 `max_speed` 主导：
## 衰减时间一到，行为与改动前**逐位相同**。
##
## ⚠️ 衰减写成 `launch_vel × k`（`k` 由 `_age` 直接算），不是逐帧累乘 ——
## 逐帧累乘会让"衰减到 0"永远不到（指数尾巴），且结果依赖帧率。
const INHERIT_MUL := 1.0
## 继承到的速度用几秒**线性**衰减到 0。
##
## 1.6 s 的取值理由：要覆盖 `deploy_time`（0.55 s，弹射段）**外加**导引头接管后的
## 头一段 —— 否则导弹在"开始咬目标"那一刻突然丢掉载机速度，会看到一次**速度台阶**。
## 又不能太长：那是"导弹能挂在机体旁边蹭半天"，会让咬尾变得没有代价。
const INHERIT_DECAY_TIME := 1.6

## 离架瞬间继承到的载机速度（世界向量）。0 = 老行为（原地起步）。
##
## ⚠️ 必须在**进场景树之前**由 `_configure()` 定好（同 `max_speed` 的规矩）：
## 进树会触发 `_ready()`，而 `_ready()` 会读 `max_speed` 反算 `accel`。
var launch_vel := Vector3.ZERO

## 继承量的衰减系数：离架 `age` 秒后还剩几成（1 → 0，**线性**）。
##
## 抽成静态纯函数是为了**可测** —— `_physics_process()` 里的局部量没法在无头测试里
## 直接读，而"到点归零"这件事必须能被断言钉住（它是"弹道最终回到改动前"的保证）。
static func inherit_factor(age: float) -> float:
	if INHERIT_DECAY_TIME <= 0.0:
		return 0.0
	return maxf(1.0 - age / INHERIT_DECAY_TIME, 0.0)


## 尾迹档位（DESIGN §4.4「性能」）。**只影响观感的粒子数**，不碰任何弹道参数。
##
## 为什么要分档：尾迹是**每发一份**的粒子发射器。正常扳机 3 发没问题，
## 但全弹发射是 100 发 —— 老版一律 90 粒子 ⇒ **9000 粒子/秒**，
## 叠上爆炸 / 尾焰 / 受损黑烟会直接把帧率打下去。
## 而弹幕的观感本来就是"一整片烟"，单发看得清与看不清并不影响它。
enum Trail { LOW, HIGH }

## 本发的尾迹档位。
##
## ⚠️ **必须在进场景树之前定好** —— 理由是 `_ready()` 里要按它建尾迹，
## 而 `add_child()` 会**同步**触发 `_ready()`；先 add_child 再赋值就晚了
## （与 `max_speed` / `accel_time` 同一条规矩，见 `_configure()` 的注释）。
##
## 默认 `HIGH`（正常扳机，与改动前一致）；全弹发射那 100 发由
## `PlayerController._emit_full_salvo_shot()` 显式传 `LOW`。
var trail_level: int = Trail.HIGH

## 本发的**连续烟带**（轮 40，见 `MissileRibbon`）。
##
## ⚠️ 它挂在 **`get_parent()`（弹丸容器）** 上，**不是**弹的子节点 ——
## 理由是需求本身：用户看不到"弹飞过的那条轨迹"，而弹一命中就 `queue_free()`，
## 挂在弹身上的东西会跟着**一起消失**，那条已经铺了十几公里的烟就白铺了。
## 所以烟带活得比弹长：弹没了它自己淡出（`release()` → `_process`）。
##
## 全弹发射（`Trail.LOW`）**是 `null`** —— 一次 100 条带上百点的带子顶点会到六位数。
var _ribbon: MissileRibbon = null


## 档位 → 每发粒子数。**唯一的映射点**。
## 数字真源在 `FX`（特效层），弹丸层只做"档位 → 那个数"的翻译 ——
## 反过来（让 `FX` 认识 `Trail`）会把特效层绑死在弹丸上。
static func trail_amount(level: int) -> int:
	return FX.TRAIL_LOW_AMOUNT if level == Trail.LOW else FX.TRAIL_HIGH_AMOUNT


## 每物理帧给烟带推一个采样点。全弹发射（没有烟带）时是空操作。
func _tick_ribbon(delta: float) -> void:
	if _ribbon != null and is_instance_valid(_ribbon):
		_ribbon.push(global_position, delta)

var shooter: Node3D = null
var target: Node3D = null
var decoy: Node3D = null
## **可以拦截**（1.2 用户澄清）：辅助驾驶下打出的导弹是"能对撞"的。
## 判定放在导弹自己的 `_physics_process` 里：可拦截的导弹只要在飞行途中
## 与**迎面而来的导弹**擦到 `INTERCEPT_RADIUS` 之内，两发一起炸（对撞），
## 而不是"飞过去把它点掉"—— 用户原话："用发射的导弹和对面的导弹对撞"。
var intercept_capable := false

## **拦截目标**（1.2 方案 A）：这一发要在半路撞掉的那枚**来袭飞弹**。
##
## ⚠️ 与 `target` 的分工必须分清：
##   - `target` = "我这发弹最终要去打谁"（对拦截弹来说仍是**敌机**）；
##   - `intercept_target` = "我要撞掉哪一枚弹"。
##
## 加这个字段之前**只有 `target`**，于是玩家在 HUD 上"选中的拦截目标"
## 对弹道**毫无影响** —— 拦截弹照样朝敌机飞，能不能撞上来袭弹全看两条弹道会不会
## 自然相交。用户实测"拦截成功率还是有点低了"，根因就是这里：不是数值不够，
## 是**根本没在瞄**。
var intercept_target: Node3D = null

## 上一物理帧的位置。**扫掠判定要用**（见 `_check_intercept`）：
## 只有"当前点"的话，两发高速对头的弹会在线性帧之间互相穿过去。
var _prev_pos := Vector3.ZERO

## 拦截弹的速度倍率（1.2 用户要求："如果导弹目标是拦截导弹，速度会更快到现在的 1.8 倍"）。
##
## ⚠️ 它加的是**拦截弹自己**的速度，来袭弹一点没动 —— 这正是"不改变来袭弹的数量与弹速
## 也能提高拦截能力"的那一类杠杆。
##
## ---- 2026-09-21 从 **1.8 下调到 1.1** ----
##
## 老板原话：「拦截系统现在拦截的有点过快了，**没有展示出弹幕的华丽度**了，
## 让拦截的导弹速度从 1.5 改为 1.1 吧。」（他记的 1.5 是上一版讲解里的
## "拦截弹 1500 m/s" —— 那句话出自当时 `Interceptor` 里一个**从来没被实例化的
## 节点类**的同名常量。那个类连同它的常量**已经在 2026-09-21 删掉**
##（见 `interceptor.gd` 的文件头）：改它从来没有任何效果。
## 真正在跑的是下面这个常数，当时是 1.8。）
##
## 来袭弹 1134 m/s，原来拦截弹 **2041 m/s（快八成）**：对着头飞几乎是瞬间贴上，
## 弹幕还没铺开就被点掉了 —— 这就是"看不到华丽度"。
## 1.1 之后拦截弹 = **1247 m/s**：
##   - 仍然**比来袭弹快**（+10%），"追得上"这条物理前提没破
##     （它是拦截成立的条件，`suite_combat` 有断言盯着）；
##   - **侧面 / 追尾**的拦截要飞一段才咬上 —— 那一段就是玩家看见的弹幕，
##     也正是老板要的观赏性；
##   - **对头**拦截仍然几乎瞬间（两边接近率相加 2381 m/s），这是几何决定的，
##     改不了也不该改。
##
## ⚠️ 同一个常数**也管全弹发射的那 100 发**（`_emit_full_salvo_shot()` 里每发都
## `arm_intercept(null)`）—— 所以那一波也一起从 2041 降到 1247。
## 如果老板只想慢"点对点拦截"、而让 100 发继续快，就得把这个常数**拆成两个**
##（一个给目标拦截、一个给全弹发射的墙）。**这次没拆**：先按他说的数走，
## 拆不拆等他的手感反馈。
##
## ⚠️ 顺带修好的一件事：转向率按 rad/s 给，所以速度倍率降下来**转弯半径也跟着降** ——
## 1.8 那版"斜向拦截明显变钝"的代价（见旧注释）现在自然变轻了。
const INTERCEPT_SPEED_MULT := 1.1

var _age := 0.0
var _last_target_pos := Vector3.ZERO
var _last_target_vel := Vector3.ZERO


## 把这一发**武装成拦截弹**：标记可对撞 + 咬住要撞的那一枚 + 给速度加成。
##
## 为什么三件事必须在**同一个方法**里做：它们是"拦截弹"这一个概念的三个面。
## 拆到三个调用点各写一遍，迟早有人只写两件 —— 比如忘了重算 `accel`，
## 表现是"加速时间莫名变成 1.8 倍"，而代码不报任何错。
##
## ⚠️ **幂等**：`max_speed` 是乘上去的，重复调用会变成 1.8²、1.8³ …
func arm_intercept(who: Node3D) -> void:
	if intercept_capable:
		return
	intercept_capable = true
	intercept_target = who
	max_speed *= INTERCEPT_SPEED_MULT
	# ⚠️ `accel` 必须在改完 `max_speed` 之后**重算**：它在 `_ready()` 里是按
	# `(max_speed - speed) / accel_time` 反推出来的。只改上限不改加速度的话，
	# 加速时间会变成原来的 1.8 倍 —— 而拦截是"越早到越好"，那等于把加成吃回去一半。
	accel = maxf(max_speed - speed, 1.0) / maxf(accel_time, 0.1)


## 通用导弹。参数必须在**进场景树之前**配好，因为 `_ready()` 要按最终的
## `max_speed` / `accel_time` 反算加速度（见 `_configure` / `_attach` 的说明）。
static func spawn(container: Node, from: Vector3, dir: Vector3, target_unit: Node3D,
		shooter_unit: Node3D, damage_amount := 45.0, trail := Trail.HIGH) -> Missile:
	var m := _configure(from, dir, target_unit, shooter_unit, damage_amount)
	m.trail_level = trail
	_attach(container, m, from)
	return m


## 浮游导弹：先朝 outward 方向弹出去一小段（deploy_time 内不制导），再咬住目标。
## 这个"先散开再收拢"的观感是浮游导弹区别于普通导弹的地方。
##
## 速度上限与普通导弹**相同**（都取 `SuitProfile.missile_speed()`）——
## 区别在**敏捷**：转向更快、出仓后加速更猛。这样"弹速比机体快"这条对两种弹都成立。
##
## ⚠️ **`speed = 90` 的语义在轮 13 变了**：它现在是"**相对载机的弹射初速**"，
## 不是"相对地面的初速" —— 载机那 2 km/s 由 `launch_vel` 继承过来
##（见 `INHERIT_MUL`）。所以 `deploy_time` 这 0.55 s 里，相机里看到的位移是
## 0.55 × 90 ≈ **50 m 的挂架弹射**，而不是改动前那 0.55 × 2270 ≈ **1250 m 的向后掉队**。
## 这正是"看得见的发射"与"完全看不见"的分界。
##
## `trail`：尾迹档位（见 `Trail` 的注释）。默认 `HIGH`；
## **全弹发射的 100 发必须传 `LOW`**，否则 9000 粒子/秒会把帧率打下去。
static func funnel(container: Node, from: Vector3, outward: Vector3, target_unit: Node3D,
		shooter_unit: Node3D, damage_amount := 26.0, trail := Trail.HIGH) -> Missile:
	var m := _configure(from, outward, target_unit, shooter_unit, damage_amount)
	m.trail_level = trail
	m.damage_type = Damage.Type.FUNNEL
	m.deploy_time = 0.55
	m.speed = 90.0
	m.accel_time = 1.7
	m.turn_rate = FUNNEL_TURN_RATE
	m.turn_decay = FUNNEL_TURN_DECAY
	m.fuse_radius = 24.0
	_attach(container, m, from)
	return m


## 配好参数、**还没进场景树**。进树会触发 `_ready()`，而 `_ready()` 要按最终的
## `max_speed` / `accel_time` 反算 `accel` —— 先 add_child 再改参数的写法
## 会让刚算好的加速度被覆盖（这一类"顺序错了但看不出错"的问题只能靠结构避免）。
static func _configure(from: Vector3, dir: Vector3, target_unit: Node3D,
		shooter_unit: Node3D, damage_amount: float) -> Missile:
	var m := Missile.new()
	m.shooter = shooter_unit
	m.target = target_unit
	m.damage = damage_amount
	m.direction_seed = dir.normalized()
	# ---- 载机速度继承（轮 13，见 INHERIT_MUL 的说明）----
	# 在**这里**赋值（= 进场景树之前），和 max_speed / accel_time 同一条规矩。
	m.launch_vel = carrier_velocity(shooter_unit) * INHERIT_MUL
	if target_unit != null and is_instance_valid(target_unit):
		m._last_target_pos = target_unit.global_position
	return m


## 载机（`FlightBody`）当前的速度向量。取不到就返回 0 ⇒ 该发弹退回老行为。
##
## ⚠️ **不能复用 `_velocity_of()`**：那个是实例方法，而且它的后备分支是
## "读 `speed` 当飞行方向"（给**导弹**用的）。用在这里会出大错 ——
## 发射瞬间载机不是弹体，`get("speed")` 在 `FlightBody` 上是 `null`，
## 但若以后有人给机体加了同名字段，导弹就会把"机体的某个速度标量"
## 当成弹体速度继承进来。两件事必须由两个函数表达。
static func carrier_velocity(n: Node3D) -> Vector3:
	if n == null or not is_instance_valid(n):
		return Vector3.ZERO
	var v = n.get("fm")
	if v is FlightModel:
		return (v as FlightModel).velocity
	return Vector3.ZERO


static func _attach(container: Node, m: Missile, from: Vector3) -> void:
	container.add_child(m)
	# ⚠️ 用 `look_at_from_position` 而不是 `look_at`：这一行在 `container.add_child()`
	# **之前**执行，节点还没进树，`look_at()` 会直接报 "Node not inside tree"
	# —— 每次开火刷一条错，控制台全是噪声（真实缺陷，不只是测试噪声）。
	m.global_position = from
	m.look_at_from_position(from, from + m.direction_seed, Vector3.UP)


static var _body_mesh: CapsuleMesh

var thunder_sting:=false
var direction_seed := Vector3.FORWARD


func _ready() -> void:
	# 加速度由"爬升时间"反推：速度上限改了，加速度自动跟上
	accel = maxf(max_speed - speed, 1.0) / maxf(accel_time, 0.1)
	add_to_group("missiles")
	var body := MeshInstance3D.new()
	if _body_mesh == null:
		_body_mesh = CapsuleMesh.new()
		_body_mesh.radius = 0.7; _body_mesh.height = 7.0
		_body_mesh.radial_segments = 8; _body_mesh.rings = 2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.86, 0.86, 0.9)
		mat.metallic = 0.75; mat.roughness = 0.35
		_body_mesh.material = mat
	body.mesh = _body_mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.rotation_degrees = Vector3(90, 0, 0)
	add_child(body)
	# 2026-09-22 增厚：scale 参数 0.55 → 0.65（与 fx.gd 的尺寸上调叠加，柱径约 +85%）。
	# Budget only visual smoke; every missile retains full guidance and damage.
	var smoke_allowed := Settings.effects_quality>0 or get_tree().get_node_count_in_group("budget_missile_smoke") < 64
	if smoke_allowed:
		var smoke := FX.missile_trail(self, 0.65, mini(trail_amount(trail_level),12) if Settings.effects_quality==0 else trail_amount(trail_level))
		smoke.add_to_group("budget_missile_smoke")
	# ---- 连续烟带（轮 40）：**长度**由它负责，上面那串粒子球负责近端的**体积感** ----
	#
	# 分工是用户 2026-09-28 定的（「烟带 + 烟团都做」）。两边各管一头：
	#   · 粒子球：近端一柱「厚」的（`lifetime 0.16 s` ⇒ 柱长 650 m，近端的体积感靠它）；
	#   · 烟带：  从弹一直连到**发射点**（实测 12 km 交战时弹道 16.7 km、实铺 100%），
	#             它没有"间距"这个量，所以多长都不稀疏。
	#
	# ⚠️ 挂 `get_parent()` 而不是 `self`（理由见 `_ribbon` 成员那段）。
	# ⚠️ **全弹发射不开**：100 条 × 上百采样点会把顶点数推到六位数，
	#    而弹幕的观感本来就是"一整片烟"、"单发看不清并不影响它"（与 LOW 档同一条理由）。
	if trail_level != Trail.LOW and (Settings.effects_quality>0 or get_tree().get_node_count_in_group("budget_missile_ribbons") < 24):
		var holder := get_parent()
		if holder != null:
			_ribbon = MissileRibbon.new()
			holder.add_child(_ribbon)
			_ribbon.add_to_group("budget_missile_ribbons")
			_ribbon.global_position = global_position


func _physics_process(delta: float) -> void:
	# ⚠️ 必须在**最前面**：这个函数有四处早退出口（燃料耗尽、已销毁……），
	# 挂在半途漏一处就是"某几种死法没有烟"，而且不报错。
	_tick_ribbon(delta)
	_age += delta
	lifetime -= delta
	if lifetime <= 0.0:
		_detonate(false)
		return

	_prev_pos = global_position

	# ---- 展开段：不制导，**也先不加速**（轮 13）----
	#
	# ⚠️ 加速被移进了"出仓之后"，理由是**实测**（`tests/funnelprobe` 的相机投影表）：
	# 原来 `speed` 从 `_age = 0` 就一路 `move_toward` 上去，于是弹射段里它自己也飙 ——
	# 0.2 s 后自航速度已经 557 m/s，相对机体沿弹射方向的位移 65 m，
	# **0.10 s 之后三发全部飞出视锥**（相机的横向半宽在这个距离上只有十几米）。
	# 而"浮游导弹从挂架上弹出去"这个动作，语义上就该是**弹出去**、
	# 不是"弹出去的同时已经在飙"。
	#
	# 移进来之后：弹射段内相对机体的位移 = 90 m/s × 0.55 s ≈ **50 m**（看得见的一段），
	# 出仓那一刻再按 `accel_time` 猛加速去咬目标（"先散开再收拢"还是那个观感，只是真的看得见了）。
	#
	# ⚠️ **零回归**：普通导弹 `deploy_time = 0.0` ⇒ `_age >= 0.0` 恒成立
	# （`_age` 在函数开头已经加过本帧 delta）⇒ `speed` 照旧每帧更新，与改动前逐位相同。
	if _age >= deploy_time:
		speed = move_toward(speed, max_speed, accel * delta)
		var aim := _aim_point()
		var fwd := -global_transform.basis.z
		var to_aim := aim - global_position
		if to_aim.length_squared() > 0.0001:
			var desired := to_aim.normalized()
			var axis := fwd.cross(desired)
			var angle := fwd.angle_to(desired)
			var rate := maxf(turn_rate - turn_decay * _age, TURN_FLOOR)
			if axis.length_squared() > 1e-8:
				var step: float = minf(rate * delta, angle)
				basis = basis.rotated(axis.normalized(), step).orthonormalized()

	# ---- 载机速度继承的衰减因子（轮 13，见 INHERIT_MUL）----
	# ⚠️ `k` 走 `inherit_factor()` 这个**静态纯函数**，不是在这里现算：
	#   ① 逐帧累乘一个 <1 的系数只有指数尾巴，"到点归零"永远不成立；
	#   ② 累乘的结果依赖帧率 —— 30 fps 与 144 fps 下同一条弹道会不一样，
	#      而这种偏差在无头回归里根本看不见（帧率固定）。
	# 线性衰减写成"初始向量 × k"，两点都免疫；抽成函数则让"到点归零"可被测。
	var inherit_k := inherit_factor(_age)
	var step_vec := (-global_transform.basis.z) * speed * delta + launch_vel * inherit_k * delta

	# --- 撞地 ---
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step_vec)
	q.collision_mask = WORLD_LAYER
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.get("position", global_position + step_vec)
		preload("res://scripts/combat/missile_spatial_index.gd").moved(self)
		_detonate(true)
		return

	global_position += step_vec
	preload("res://scripts/combat/missile_spatial_index.gd").moved(self)

	# --- 冲进烟雾 → 在烟雾里自爆（第十八轮）---
	# 用户原话："被热诱弹骗到的导弹都会冲向大量烟雾中然后在烟雾中爆炸"。
	# 这是"干扰弹 = 确定性清屏"的**兑现点**：诱骗只负责把弹引过来，让它消失的是这一句。
	# `hurt = false`：它已经在烟里了，**不该再结算对玩家的伤害**。
	if decoy != null and is_instance_valid(decoy) \
			and global_position.distance_to(decoy.global_position) <= SMOKE_KILL_RADIUS:
		_detonate(true, null, false)
		return

	# --- 对撞判定（方案 C：放在**移动之后**）---
	# 位置先更新，才有"这一帧从哪走到哪"的线段；判定因此是**扫掠**而不是点采样。
	# 放在移动前的话，两发高速对头的弹会在两次采样之间互相穿过去。
	if intercept_capable:
		_check_intercept()
		if is_queued_for_deletion():
			return

	# --- 近炸引信 ---
	var victim := _nearest_victim()
	if victim != null and global_position.distance_to(victim.global_position) <= fuse_radius:
		_detonate(true, victim)


## 追踪目标（或已被骗去的干扰弹）。目标丢失超过 4 秒就直飞。
##
## **拦截弹优先咬住 `intercept_target`**（方案 A）：那才是"要撞掉的那一枚"。
## 没有它时才是老行为（追敌机 / 被干扰弹骗走）。
func _aim_point() -> Vector3:
	# ---- 方案 A：拦截弹**真的瞄着来袭弹**飞 ----
	if intercept_target != null:
		if not is_instance_valid(intercept_target) or intercept_target.is_queued_for_deletion():
			# 目标没了（被别人打掉 / 自己炸了）→ 退回追敌机，别一头扎空
			intercept_target = null
		else:
			var ip: Vector3 = intercept_target.global_position
			var iv := _velocity_of(intercept_target)
			_last_target_pos = ip
			_last_target_vel = iv
			# ⚠️ **必须解二次方程，而且要用"巡航速度"估飞行时间**。
			#
			# 两个坑叠在一起：
			#   1. 导弹是**加速**的（出膛 130 → 巡航 1134，`accel_time` 2.4 s）。
			#      拿**当前速度**算 tof，刚发射那几帧会高估近十倍，提前量直接飞到
			#      目标后面 —— 表现是"拦截弹朝反方向瞄"（测试实测到的就是这个：
			#      瞄点落回自己身后）。所以用 `maxf(speed, max_speed*0.75)`。
			#   2. `位置 + 速度×时间` 是个近似；`intercept_point()` 解的是
			#      `|D + V·t|² = s²·t²`（弹丸与目标**同时**到达），这才是对撞要的。
			# 提前量也**不乘 `lead_factor`**：那是给"打飞机"调的 0.7，
			# 而这里要撞的是一枚同样在高速接近的弹体 —— 欠提前量就是永远差半步。
			var est := maxf(speed, max_speed * 0.75)
			return Ballistics.intercept_point(global_position, ip, iv, est)

	if decoy == null and target != null and is_instance_valid(target) and target.has_method("is_alive") and target.is_alive():
		_maybe_break_lock()
	if decoy != null and (not is_instance_valid(decoy) or decoy.is_queued_for_deletion()):
		decoy = null
		return _last_target_pos + _last_target_vel * 2.0

	var track: Node3D = decoy if decoy != null else target
	if track == null or not is_instance_valid(track):
		return global_position + (-global_transform.basis.z) * 500.0

	var pos := track.global_position
	var vel := _velocity_of(track)
	_last_target_pos = pos
	_last_target_vel = vel
	var dist := global_position.distance_to(pos)
	var tof: float = dist / maxf(speed, 1.0)
	return pos + vel * tof * lead_factor


func _velocity_of(n: Node3D) -> Vector3:
	var fm = n.get("fm")
	if fm != null and fm is FlightModel:
		return (fm as FlightModel).velocity
	# ⚠️ **飞弹没有 `fm`**（它不是 FlightBody），但它当然有速度：沿自身 −Z 以 `speed` 前进。
	# 这里返回 0 的话，打拦截弹就**完全没有提前量** —— 而目标是同样高速的弹体，
	# 差半步就永远撞不上。方案 A 能不能成立，这一行是前提。
	var sp = n.get("speed")
	if sp != null:
		return (-n.global_transform.basis.z) * float(sp)
	return Vector3.ZERO


## 干扰弹诱骗判定。
##
## ## 第十八轮：目标撒干扰弹期间 —— **无条件**诱骗
##
## 老版本是"**机头 ±36.9° 锥角**（`fwd.dot(dir) < 0.80`）+ **260 m** + 每帧掷骰子"的三重门。
## 后果很具体：**从侧后方来的导弹根本骗不掉**（而弹幕是全向的），救命要靠运气 ——
## 这正是"被弹幕糊脸时没有任何可靠出路"的那一半原因。
##
## 现在加一条**无条件分支**：只要目标还在干扰弹有效期内（`flares_active()`），
## 所有"冲它来的"弹一律改咬**最近的干扰源**，不看锥角、不看距离、不看概率。
## 下面的概率分支只留给"烟雾烧完之后还想再骗一下"的补刀。
func _maybe_break_lock() -> void:
	var tv = target
	if tv != null and is_instance_valid(tv) \
			and tv.has_method("flares_active") and tv.flares_active():
		var near := _nearest_flare()
		if near != null:
			decoy = near
			return
	if decoy_chance <= 0.0:
		return
	var fwd := -global_transform.basis.z
	# 组快照走 Game 的每物理帧缓存（批 10 性能二轮）
	for f: Node in Game.group_snapshot(get_tree(), "flares"):
		var fn := f as Node3D
		if fn == null or not is_instance_valid(fn):
			continue
		var d := global_position.distance_to(fn.global_position)
		if d > 260.0:
			continue
		var dir := (fn.global_position - global_position).normalized()
		if fwd.dot(dir) < 0.80:
			continue
		if randf() < decoy_chance * get_physics_process_delta_time():
			decoy = fn
			return


## 场上**最近的**干扰源。故意不筛锥角、不筛距离、不看概率 —— 见 `_maybe_break_lock()`。
## 找不到就返回 null（那说明场上没有干扰弹，调用方保持原行为）。
func _nearest_flare() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for f: Node in Game.group_snapshot(get_tree(), "flares"):
		var fn := f as Node3D
		if fn == null or not is_instance_valid(fn):
			continue
		var d := global_position.distance_to(fn.global_position)
		if d < best_d:
			best_d = d
			best = fn
	return best


## 弹轴方向。导引头是否"咬住"目标就靠它和视线方向的夹角判断。
func forward_dir() -> Vector3:
	return -global_transform.basis.z


func _nearest_victim() -> Node3D:
	if target != null and is_instance_valid(target) and target.has_method("is_alive") and target.is_alive():
		return target
	return null


## 被拦截（1.2）：在半空中被打爆 —— 不伤人、不留弹。
##
## 干扰弹骗掉飞弹走的也是这条出口（`_detonate(false)`），
## 所以"骗掉"与"打掉"的表现和后果完全一致，区别只是"概率"与"确定"。
func intercept() -> void:
	_detonate(false)


## **被机炮 / 光束打掉**（第十八轮）。与 `intercept()` 的区别只有一条：**要有爆炸的动静**。
##
## `hurt = false`：弹已经没了，不该再结算对谁的伤害。
## 之所以不让调用方直接写 `_detonate(true, null, false)`：那个参数组合的意图
## （"打爆了、但别扣血"）值得有一个名字 —— 否则下一个人很容易顺手写成
## `_detonate(true)`，那时 `victim` 会退回"锁定的敌机"，于是**打掉一颗飞来的弹
## 反而扣了敌机/自己的血**。
func shot_down() -> void:
	_detonate(true, null, false)


## 对撞判定（1.2）：只对**可拦截**的导弹生效。
##
## 判据刻意收得很紧，避免误伤自己的僚机导弹：
##   ① 自己必须是"可拦截"的（辅助驾驶下打出来的）；
##   ② 对面必须是**向我方来的**（它的 `target` 是我的 `shooter`，
##      或者干脆就是我所在这方 —— 用 `target` 与 `shooter` 的关系近似）；
##   ③ **两条线段之间的最短距离** ≤ `INTERCEPT_RADIUS`（不是两点的距离，
##      见方案 C 的说明）。
##
## ## 方案 B：半径 48 → **80 m**
## 捕获截面积 ∝ 半径²，48 → 80 就是 **×2.8** 的命中面积 ——
## 这是"不动来袭弹的数量与弹速"前提下最直接的"成功率乘数"。
## 判定只在 `intercept_capable` 的弹上跑（玩家打出的拦截弹），
## 所以放大它对普通对射**毫无影响**。
##
## ## 方案 C：点采样 → **扫掠**
## 判定必须放在**移动之后**（见 `_physics_process`），这样每发弹都有
## "这一帧从哪走到哪"的线段。原来只比两个点：1134 m/s 对头接近最快 37.8 m/帧，
## 最近距离落在 44~48 m 的擦过会在两帧之间**互相穿过去**。
const INTERCEPT_RADIUS := 80.0

## 被干扰弹骗走的导弹，进入离干扰源这么近就**在烟雾里自爆**（第十八轮）。
##
## 用户原话："热诱弹会放出大量烟雾，被热诱弹骗到的导弹都会冲向大量烟雾中然后在烟雾中爆炸"。
## 这一条把"干扰弹 = 确定性清屏"从**设计**变成一个**兑现点**：
## `_maybe_break_lock()` 的无条件分支只负责把弹引过来，真正让它消失的是这里。
##
## ⚠️ 取值要**大于** `fuse_radius × 1.6`（24 × 1.6 = 38.4 m）：否则自爆那一刻
## 会走进 `_detonate()` 的伤害分支、对**干扰源**调 `take_damage()` —— 而干扰源是
## 个粒子节点，没有这个方法（会直接崩）。55 m 留了余量。
const SMOKE_KILL_RADIUS := 55.0


func _check_intercept() -> void:
	if not intercept_capable or shooter == null or not is_instance_valid(shooter):
		return
	var tree := get_tree()
	if tree == null:
		return
	# 本帧自己的线段。`_prev_pos` 还没被写过（刚生成的那一帧）时退化成一点。
	var my_a := _prev_pos
	var my_b := global_position
	if my_a == Vector3.ZERO:
		my_a = my_b
	# 组快照走 Game 的每物理帧缓存（批 10 性能二轮）
	for other: Node in preload("res://scripts/combat/missile_spatial_index.gd").query(tree,my_a,my_b,INTERCEPT_RADIUS):
		if other == self or not is_instance_valid(other) or not (other is Missile):
			continue
		var o := other as Missile
		if o.shooter == null or o.shooter == shooter:
			continue                      # 自己人的弹不打
		# 只打"冲着我来"的那一发：对方的目标就是我（或我这一方）
		if o.target != shooter and o.target != self:
			continue
		# 对方本帧的线段。它可能还没轮到本帧的 `_physics_process`，
		# 那时线段退化成一点（用上一帧的位置）—— 照样比点距更准，不会更差。
		var o_a := o._prev_pos
		var o_b := o.global_position
		if o_a == Vector3.ZERO:
			o_a = o_b
		if not Ballistics.swept_bounds_overlap(my_a,my_b,o_a,o_b,INTERCEPT_RADIUS):continue
		if Ballistics.segment_distance(my_a, my_b, o_a, o_b) <= INTERCEPT_RADIUS:
			# 对撞：两发一起炸，弹体不留
			o.intercept()
			intercept()
			return


## `hurt = false`：**只炸、不掉血**（第十八轮加）。
## 用在两处：① 被干扰弹骗走的弹在烟雾里自爆（见 `SMOKE_KILL_RADIUS` 那段）；
## ② 被机炮 / 光束打掉的弹（见 `Projectile._physics_process`）。
## ⚠️ 没有这个开关的话，这两处只有两条坏路可走：传一个"假 victim"（干扰源是个粒子节点、
## 没有 `take_damage` → 崩），或者绕过 `_detonate`（于是"打爆了却一点动静都没有"）。
func _detonate(explosive: bool, victim: Node3D = null, hurt := true) -> void:
	# 弹没了 —— 烟带**留下来自己淡出**（`MissileRibbon.release()`）。
	# ⚠️ 放在**所有出口之前**：本函数有三条 return（`not hurt` / 末尾），漏一条就是
	#    "被拦截打掉的那些弹不留烟"，而这正是玩家最常看到的那一种死法。
	if _ribbon != null and is_instance_valid(_ribbon):
		_ribbon.release()
	var parent := get_parent()
	if explosive and parent != null:
		FX.explosion(parent, global_position, 0.55)
		# 「冲进烟里炸掉」这件事本身应该把烟**搅大一圈**（DESIGN §4.4「另加两处小东西」②）。
		# 判据刻意用 `decoy`：它正好是"被干扰弹骗走的弹"这个语义的唯一标志。
		# ⚠️ 不要改成"所有爆炸都叠烟" —— 那会让正常近炸也冒一团烟，
		# 与"干扰弹 = 确定性清屏"的视觉承诺撞在一起，玩家分不清自己骗掉了几发。
		if decoy != null and is_instance_valid(decoy):
			FX.smoke_burst(parent, global_position, 1.8, 1.4, FX.MISSILE_SMOKE_KILL_PUFF)
		# 近处用 boom_s、远处用 boom_m —— 两版是不同的录音，按距离选，不是调音量
		Audio.play_explosion(global_position)
	if not hurt:
		queue_free()
		return
	if victim == null:
		victim = _nearest_victim()
	if victim != null and global_position.distance_to(victim.global_position) <= fuse_radius * 1.6:
		# shooter 可能已经被销毁（发射者在导弹落地前先坠机了）。
		# 已释放的引用传进类型化参数会让 Godot 在进入函数之前就报错，
		# 所以必须在调用点判有效性，不能指望被调方处理。
		var src: Node3D = shooter if (shooter != null and is_instance_valid(shooter)) else null
		victim.take_damage(damage, src, damage_type)
		if thunder_sting and damage>0 and victim is FlightBody:victim.apply_thunder_status("sting")
		if src != null and src == Game.player:
			Game.missiles_hit += 1
	queue_free()


func _exit_tree() -> void:
	preload("res://scripts/combat/missile_spatial_index.gd").forget(self)
