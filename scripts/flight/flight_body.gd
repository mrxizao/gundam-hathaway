class_name FlightBody
extends CharacterBody3D
const SUIT_MATERIALS = preload("res://scripts/flight/suit_materials.gd")
var _material_cel_mode := false
## 一架可飞行的机体：飞行模型 + 视觉 + 护盾/损伤 + 全部武器。
## 子类只负责"产生控制输入"（玩家 = 键鼠，AI = 状态机），飞行/开火/死亡全在这里。
##
## 场景结构（全部代码生成）：
##   FlightBody (CharacterBody3D)      碰撞体在这里，原点 = 机体中心（约全高 55% 处）
##   ├─ ModelPivot (Node3D)            飞行前倾角
##   │  └─ ModelRoot (Node3D)          把模型重心平移到原点
##   │     ├─ SuitRig (Node3D)         槽位锚点（真模型到位后隐藏，只留锚点）
##   │     └─ <真模型实例>              按 profile.target_height 缩放
##   ├─ Afterburner / DamageSmoke
##
## ## 两层减伤（需求原文）
## 1. **I 立场护盾**：独立血条 `ifield_hp`，消耗完**不恢复**，之后才开始掉机体血。
##    对光束步枪 100% 减伤、对火神炮 / 浮游导弹 70% 减伤（见 Damage.IFIELD_REDUCTION）。
## 2. **主动举盾**（按住 Z）：在 I 立场之后再打一个固定比例折扣，
##    柯西 0.55 > 佩涅罗佩 0.35。
## 光束军刀与撞击不在 I 立场减伤表里 → 直接打机体，再被主动举盾削一次。
## 这就是"盾厚的时候近战才是解法"的设计来源。

const WORLD_LAYER := 1 << 0
const UNIT_LAYER := 1 << 1

## 出生高度以下即判定撞海/撞地。
##
## ⚠️ **只对有地面的图成立**（2026-09-29 起）：轨道图上越过下边界**不判死**，
## 而是被推回战斗高度带 —— 见 `_check_ceiling()` 与 `orbit_floor_alt()`。
const CRASH_ALTITUDE := 24.0

## 本局被"**推回轨道**"的次数（轨道图专用，见 `_enforce_orbit_floor()`）。
##
## ## 为什么需要它
## 轨道图上越过再入线**不判死**（老板：「近地轨道没有撞地这种情况」）——
## 于是"那条路到底有没有走过"这件事**在结算界面上完全看不见**：
## 不扣血、不弹提示、机体还活着，与"什么都没发生"长得一模一样。
## ⇒ 判据只能靠计数：断言它 `>= 1` 才是"真的被推回来了"，
##    而不是"机体恰好没越过线"（后者是个**假绿**：把功能整个删掉也能过）。
var orbit_returns := 0

## 撞击伤害的冷却。没有它的话，两机贴在一起的那几帧会**每帧**结算一次撞击，
## 一次接触就能瞬间扣掉好几倍的血（实测两帧重叠＝双倍伤害，直接把一架打掉）。
const RAM_COOLDOWN := 1.0
const RAM_DAMAGE := 45.0

## ★63-25 军刀撞击豁免：军刀**收招之后**，撞击伤害再免多久。
##
## ## 为什么需要它
## 军刀命中判定在 `saber_hit_range`（78 m）就触发，而 `_slash()` 命中那一刻就
## `_end_saber()` **收招了、速度却没归零** ⇒ 两机继续贴近到碰撞胶囊（半径约 5~7 m）
## ⇒ 「砍中对方」几乎必然伴随一次**撞机结算**（双方各 45）。
## 算过：还要走 66 m ÷ 1150 m/s ≈ **3.4 帧**（0.057 s）⇒ 0.7 s 是**很宽松的余量**
##（用户指定的数；调到 0.5~1.0 手感几乎无差）。
const RAM_GUARD_AFTER_SABER := 0.7

## 占位体块模式。真模型找不到时的兜底，正常运行走 profile.model_path。
static var use_placeholder := false
## Per-instance placeholder for invisible cinematic proxies; never changes the shared test flag.
var placeholder_only := false

## 军刀状态。**没有 `CLASH` 这一档**：相杀是**瞬时**事件 ——
## `_begin_clash()` 里双方立刻 `_end_saber()` 回到 IDLE，随后的"弹开"由速度体现。
## 所以相杀之后要问的是"**在不在相杀冷却里**"（`in_clash_cooldown()`），
## 而不是"是不是停在相杀状态"（那样永远为假，早先真这么写过一版）。
enum SaberState { IDLE, CHARGE }
const PlumeMotion := preload("res://scripts/flight/plume_motion.gd")
const XiPlume := preload("res://scripts/flight/xi_plume.gd")
const PenelopePlume := preload("res://scripts/flight/penelope_plume.gd")
const PenelopeMovieMotion := preload("res://scripts/flight/penelope_movie_motion.gd")
const XiMovieMotion := preload("res://scripts/flight/xi_movie_motion.gd")
const FlightFrame := preload("res://scripts/flight/flight_frame.gd")
const InputPose := preload("res://scripts/flight/input_pose.gd")
var _input_pose := InputPose.new()
const AceMotion := preload("res://scripts/flight/ace_motion.gd")
const SONIC_CLOUD := preload("res://scripts/flight/sonic_cloud.gd")
const FlyMotion := preload("res://scripts/flight/fly_motion.gd")
const GunMotion := preload("res://scripts/flight/gun_motion.gd")
const SaberMotion := preload("res://scripts/flight/saber_motion.gd")

signal damaged(amount: float, source: Node3D, damage_type: int)
signal destroyed(killer: Node3D)
signal gun_fired
signal beam_fired
signal funnel_fired
signal saber_hit(target: Node3D)
## 军刀相杀（1.2）。双方都在 0.2 s 窗口内进入军刀突进且贴到 100 m 内时触发。
signal saber_clashed(opponent: Node3D)
## 对外通知"呼叫的踏板到位了"。玩家控制器用它弹提示。
signal pedal_arrived(board: FlightPedal)
signal ifield_broken
## I 立场吸收了一次命中（**机体一滴血都没掉**）—— §4.9.2⑤。
##
## ⚠️ 它**不是** `damaged`：`damaged` 的语义是"血量变了"，这条的语义是
## "护盾被消耗"。分开的理由：护盾挨打不该触发"受损"级的震动与告警语音，
## 但**必须有个反馈** —— 否则护盾期被持续打是**完全无感**的，
## 而护盾是这台机最重要的资源（掉了不恢复）。
##
## `absorbed` 报的是**护盾值的消耗量**，不是伤害量：同一发 10 点伤害，
## 破盾效率低的武器（军刀 0.45）会报出更大的数 —— 这正是玩家该读到的信息。
signal ifield_hit(absorbed: float, source: Node3D, damage_type: int)
signal rifle_discarded(remaining: int)
signal shield_raised
signal shield_lowered
## 形态切换完成（1.1：阿利宙斯）。HUD 与测试都靠它知道"换完了"。
signal form_changed(new_form: int, form_name: String)
## 残血爆壳变身开始（爆炸那一下）。HUD 用它弹提示，测试用它计数。
signal transform_started(to_form: int)

# ------------------------------------------------------------ 身份

## 0 = 玩家方，1 = 敌方。不同 team 互为敌机。
@export var team := 1
@export var display_name := "MESSER"
@export var is_player := false

## 机体数据表（柯西 / 佩涅罗佩 / 阿利宙斯）。子类/生成器负责注入。
## 多形态机体（阿利宙斯）：`profile` 永远是**当前形态那一份**，
## 别的系统只读它；要换形态走 `switch_form()`。
var profile: SuitProfile = null
## 出伤倍率。难度给敌机乘上 1.0 / 1.1 / 1.3。
var damage_mult := 1.0

# ------------------------------------------------------------ 多形态（1.1）

## 当前形态下标。单形态机体恒为 0。
var form_index := 0
## 手动变形冷却剩余秒数（见 `SuitProfile.FORM_COOLDOWN`）。
var form_cooldown := 0.0
## 变身掩护计时（>0 = 正在"爆炸→烟雾→换壳"的过程中）。
var _form_swap_timer := 0.0
var _form_swap_pending := -1
## 已经爆过壳了（一次性）。
var _transformed := false
## 无敌到期时刻（Game.clock 基准）。变身掩护期间用它挡伤害。
var invuln_until := 0.0
## 脱出飞升突进：时长与初速。
## **命中停顿**（1.2，方案里的"打击感"三件之一）。
##
## 砍中的那一刻，双方速度被按住 0.10 s —— 不是"动全局 time_scale"（那会把整个
## 世界一起顿住，包括镜头与 UI），而是**只压这两台机的速度**。
## 放在 `_apply_flight()` 的**开头**（飞行模型步进之前），并且用 `minf` 做成"地板"：
## 这一步之后模型即使给推力，速度也不会超过停顿时的值，于是观感是"顿住了"。
const HITSTOP_TIME := 0.10
## **分级顿帧**（批 10 打击感）：不同武器/事件的停顿不该一样长 ——
## 一记军刀（近战重击）比一发步枪重，相杀（双方对拼）比单方命中更重。
## 之前全部 0.10 s："擦弹"和"拼刀"读起来一个分量，打击感没有梯度。
const HITSTOP_TIME_SABER := 0.16
const HITSTOP_TIME_CLASH := 0.24
const HITSTOP_SPEED := 0.15
const ESCAPE_DASH_TIME := 1.25
const ESCAPE_DASH_SPEED_UP := 260.0
const ESCAPE_DASH_SPEED_FWD := 320.0
var _escape_timer := 0.0
## 命中停顿剩余时间与"停顿时被按到的速度"（见 HITSTOP_* 的注释）。
var _hitstop := 0.0
var _hitstop_hold := 0.0

## 变形白闪的剩余时间与受影响的网格（见 `_flash_model`）。
## 时长略长于光球的 0.42 s：白闪全程被光球盖住，等光球淡完再一次性摘 override，
## 于是玩家看到的是"亮起来 → 里面走出新形态"，而不是"白一下之后机体突然跳变"。
const MODEL_FLASH_TIME := 0.48
var _model_flash := 0.0
var _flash_nodes: Array[MeshInstance3D] = []

# ------------------------------------------------------------ 飞行

var fm := FlightModel.new()
## 子类每物理帧写入：Vector3(pitch, yaw, roll)，各 −1..1
var control_input := Vector3.ZERO

# ---- 辅助驾驶 · 平移模式（2026-09-22，用户要求）----
#
# 辅助驾驶开启后（**阿利宙斯巡航形态除外**，它保持原辅助）：
#   WASD = 前后左右 · QE = 上升下降 · Shift = 朝输入方向冲刺
#   （手柄：左摇杆 = 前后左右 · 右摇杆前推/后拉 = 升/降 · X = 冲刺）
#
# ## 为什么是"绕过气动"而不是"把 WASD 翻译成俯仰偏航"
# 平移模式的语义是**位置直控**（像开车），而气动模型是"机头姿态决定速度矢量"。
# 硬翻译的话 W 还是会先抬头再加速，"左右"也分不清是滚转还是平移 —— 手感必然糊。
# 所以平移模式在 `_apply_flight()` 里走独立分支：直接对 `fm.velocity` 做
# 朝目标速度的插值（不经过 `FlightModel.advance` 的姿态步进），
# 机头由"水平航向跟随速度"接管。冲刺/悬停/军刀/脱出突进的既有接管逻辑不受影响
#（它们排在分支之前/之后，见 `_apply_flight` 的顺序注释）。
#
# ⚠️ 只有玩家的辅助驾驶会置 `translate_mode`；AI 恒为 false，照走气动。
## true 时 `_apply_flight` 走"直接位移"分支（由 PlayerController 按辅助状态每帧维护）。
var translate_mode := false
## 本帧想去的平移修正（世界系，**长度 ≤ 1 保留摇杆模拟量**；ZERO = 纯自动飞行）。
var translate_dir := Vector3.ZERO
## `translate_dir` 里属于**向前推杆（W）**的那一份（世界系；与 `translate_dir` 同一帧、
## 同一个归一化系数）。ZERO = 本帧没有向前分量（按 S / 只横移 / 只升降都算没有）。
##
## 存在的理由只有一个：**W 的提速幅度要单独降档**（2026-09-29 用户：「辅助驾驶模式下
## 按 w 的加速速率下调到 15% 左右」；口径确认 = 只降 W、降的是幅度不是追随速率）。
## `translate_dir` 自己**语义不变** —— 闪避方向、八向动画、左右冲刺转身判据全读它，
## 拆分只发生在**速度层**（见 `translate_offset_vec()`）。
##
## ⚠️ 必须与 `translate_dir` **同帧同系数**：两者都只由
##    `PlayerController._read_translate_input()` 写。不同帧 / 不同系数的话，
##    `translate_dir − translate_fwd` 会把横向分量当成前向残差，横移也跟着降档。
var translate_fwd := Vector3.ZERO
## 派生状态：闪避冲刺窗口是否活跃（拖尾光条 / FX 读它）。
var translate_dash := false
## 倒着飞（★63-9 · D2）：true 时平移模式的**底速方向取反**（沿机尾方向飞）。
##
## 由 `PlayerController._tick_reverse_toggle()` 写入（**唯一写入点**，且只在
## `translate_mode` 为真时可能为真 —— 巡航形态 / 骑板那两支根本没有底速可取反）。
##
## ## ⚠️ 只翻速度、**不翻机头**
## `global_transform` 一个字节不改 ⇒ 锁定 / 弹道 / 军刀吸附 / 炮口与喷口锚点
## 全部逐位不变（设计文档 §3.2 的 ①(b)：只翻速度方向）。
##
## ## ⚠️ 无锁定目标时，「机头追速度矢量」会与底速**互相咬**
## 底速一反过来，（真实）速度矢量也反过来 ⇒「机头追速度」每帧都在追一个
## 与自己差 180° 的方向 ⇒ **连续自旋**（不是抖动，是转个不停）。
## 所以倒飞时水平朝向改追**等效正向速度**（把反向那一份底速换回正向、
## 平移修正原样保留）：无输入时它是机头自己的方向 = **不动点**；
## 有输入时转向增益与正向完全一致（不会出现"按左反而右转"的反向操舵）。
## 见 `_apply_translate()` 里 `vref` 那一段。
var translate_reverse := false
## ---- 闪避冲刺（二调 2026-09-22：装甲核心式 QB，**点按**触发）----
## 点按请求入口：`request_quick_boost()` 置位，`_apply_translate` 消费。
## 输入层用 just_pressed 触发 —— 按住不叠加、不重复触发。
var penelope_cruise_enabled := false
var _penelope_backflip := false
var _qb_pending := false
var _qb_timer := 0.0
var _qb_dir := Vector3.ZERO

## 本次冲刺的**动画方向名**（`DASH_DIR_NAMES` 之一 / `""` = 不在冲刺）—— N46。
##
## 与 `_dash_spin_dir` 同构：**起手那一帧定死、窗口结束清空**（闪避是一次 commit，
## 中途改向不该让动作在八向之间乱跳）。`_tick_model_anim()` 每帧把它交给状态机。
##
## ⚠️ 退出平移模式时必须一并清（见 `_physics_process` 的残留清理段）：
##    留着旧方向的话，下次进平移模式会**凭空播回一段冲刺**。
var _dash_anim_dir := ""
## 平移模式的**机头朝向目标**（锁定敌机）。由 PlayerController 每帧维护；
## null = 机头跟速度矢量（旧行为）。二调 2026-09-22：用户要求"不断使玩家机体
## 朝向被锁定的敌方机体"（装甲核心标准模式的手感）。
var face_target: Node3D = null
## 朝向目标的**测试 / 调试通道**：非 null 时优先于 `face_target`
##（输入层每帧按 lock 重写 face_target，测试没法直接塞 —— 走这条）。
var face_target_override: Node3D = null


## 机头朝向目标的统一读取点（override 优先）。
func _face() -> Node3D:
	return face_target_override if face_target_override != null else face_target


## 窗口时长：点一下冲这么久，然后自然回落自动飞行底速。
const QB_TIME := 0.45
## 窗口内的速度目标 = 加力极速 × 这个倍数（闪避要明显快过底速才有"弹开"感）。
const QB_SPEED_MULT := 1.45
## 窗口内的速度追随速率 —— 闪避的"爽"一半来自这个响应差。
const QB_RESPONSE := 8.0
## **QB 爆冲段**（批 11 手感）：窗口**开头**的这一小段时间里用远高于
## QB_RESPONSE 的追随速率 —— 装甲核心 QB 的"突进感"一半来自**起跑那一瞬**：
## 速度不是"很快到位"而是"当场砸到位"，之后保持巡航即可。
const QB_BURST_TIME := 0.12
## 爆冲段的追随速率（对 1−exp(−r·t)：0.1 s 内到位 89%，旧值 8 只有 55%）。
const QB_BURST_RESPONSE := 22.0
## 一次闪避额外烧掉的燃料槽（秒）。量产机闪避是稀缺资源；ACE 机无槽不受影响。
const QB_JET_COST := 0.6
## 平移修正的追随速率。越大越"指哪去哪"，越小越漂。
const TRANSLATE_RESPONSE := 3.2
## ---- 左右冲刺的机身转身（轮 33，用户要求）----
##
## 用户原话：「左右冲刺的时候朝冲刺方向机体水平旋转 360°（前后冲刺的时候不用）」
## 「第一人称的视角不受影响」；随后修正口径：「**不是机体翻跟头，而是转身**」
## ⇒ 绕**竖直轴**在水平面里转一圈（机头扫过一圈回到原方向），而不是绕自身长轴的桶滚。
##
## ## 三条不许动的口径
##
##   ① **只转视觉**：转身角只写在 `spin_pivot` 上，`global_transform` 一个字节不改
##      ⇒ 锁定判定、速度矢量、机头朝向、追尾镜头、座舱镜头全部照旧。
##      "第一人称视角不受影响"是这条的直接结果 —— 座舱相机读的是 `global_transform`，
##      而且它压根看不见自己的模型（`set_model_visible(false)`）。
##   ② **锚点不吃转身**：`rig_anchor()` 与 `_muzzle_local` 一律给出**不含转身**的位置
##      ⇒ 转身期间枪口不会绕着机体中轴画圈、子弹不会从"没有枪的位置"冒出来。
##      尾焰 / 夜航灯同理（代价见交付说明"已知边界"：那 0.45 s 里挂件与模型的水平
##      偏移不再同步，偏移量 = 喷口到机体中轴的距离，肉眼读成一点摆动）。
##   ③ **只认左右**：纯前后 / 纯升降的冲刺不转 —— 判定与方向见 `_start_dash_spin()`。
##
## ## 为什么偏要单开一层 `spin_pivot`，而且挂在 `model_pivot` **之上**
##
##   · **轴**：挂在上层 ⇒ 旋转轴 = 机体的上轴（**不含** `model_pivot` 那 18° 前倾）
##     ⇒ 前倾方向跟着转身一起扫，读成"转身"；挂在下面则是绕一根斜轴进动，会歪。
##   · **锚点**：`rig_anchor()` 的合成式从 `model_pivot` 起步，`spin_pivot` 在它外面
##     ⇒ 天然不进锚点（真骨那条①路径要显式剔一次，见 `rig_anchor()` 的注释）。
##   · **轴心**：`model_root` 的原点被 `_center_and_measure()` 挪到了**脚底下方 0.55H**
##     （`model_root.position = -offset`），把角度写在 `model_root` 上等于绕着脚画大圈；
##     `spin_pivot` 与 `model_pivot` 共用原点 = 机体 55% 高度处 = 想要的转身轴。
##
## ## 角度曲线
##
## 窗口内走 smoothstep（两端缓入缓出），与 `_qb_timer` 同起同落 ⇒ 收尾**恰好** 360°(≡0°)。
const DASH_SPIN_MIN_LAT := 0.25
## 左右转身期间「形态收起」（飞行翼 / 肩甲）的时长（秒）。见 `_tick_cruise_morph()`。
##
## ★ 比 `cruise_morph_seconds`（0.45）**短得多**，这是有意的：
##   收起与转身**同时起步**，若沿用 0.45 就等于"整个转身都在收"，
##   玩家读到的是"边转边收"而不是"先收好再转"。0.15 s 让它在转身的前 1/3 收完，
##   剩下的 0.45−0.15 里机体是**完全收起**的姿态在转（这才是"恢复成飞行态"）。
##   展开仍走默认的 `cruise_morph_seconds` —— 用户要的是"转身完之后**再**展开"，
##   那一下该是完整、看得清的变形，不该被赶时间。
const DASH_SPIN_STOW_SECONDS := 0.15

## 冲刺八向的**方向名表**（N46）：索引序 = 从"正前"起、顺时针。
##
##   0=`f` 1=`fr` 2=`r` 3=`br` 4=`b` 5=`bl` 6=`l` 7=`fl`
##
## 与交付的 `dash_<名>.glb` 逐名对应；`_dash_dir8()` 把世界方向离散到这张表。
## ⚠️ 表序**不能**按"从正后起"或逆时针写 —— 索引是靠 `atan2` 的符号直接算出来的，
##    改了顺序不会有任何报错，只会让八向**整体镜像/旋转 45°**（八段都还在播，
##    只是播错方向）。改表必须同时改 `_dash_dir8()` 的注释与验收探针。
const DASH_DIR_NAMES := ["f", "fr", "r", "br", "b", "bl", "l", "fl"]

## ---- 多喷口特效的粒子**预算**（见 `_rebuild_plumes`）----
##
## 抽成常量只为一件事：让"贴着翻车线抬"这条**可以被断言**。
## 16 喷口时每个喷口拿到的量 = `BUDGET / 16`，必须**小于 34** ——
## 那是历史翻车线（`16 × 34 = 544` 时实测"整块后机身糊成一团白"，见 `FX.afterburner` 函数头）。
## 预算写在 `_rebuild_plumes` 里的话，"320 / 16 = 20 < 34"这笔账就只能靠人肉核。
const PLUME_BOOST_BUDGET := 320
const PLUME_SMOKE_BUDGET := 160
## 翻车线：单喷口超过这个数就要重新看那张照片。
const PLUME_PER_NOZZLE_MAX := 34
## **"形状层"（形态 A / B + 马赫环）按喷口逐个铺开的上限喷口数**（2026-09-25）。
##
## 尾焰有两层，分开决定"挂在哪"：
##   · **形状层** —— `Afterburner`（形态 A）/ `AfterburnerDash` + `DashRings`（形态 B）。
##     它表达的是"这一记是普通加力还是冲刺"，所以**每个喷口都要有一套**，
##     否则"两形区分"在多喷口机体上就没了。
##   · **密度层** —— `exhaust_smoke` 尾气 + `nozzle_glow` 常亮光晕，**永远逐喷口**建。
##
## 为什么不设成"所有喷口一视同仁"：阿利宙斯巡航有 **16 个**口，
## 16 × 2 形 = **32 个发射器**，而每个口直径才 1 m 上下 ——
## 那个尺度上"细束"和"粗锥"**根本分不出来**，白花 16 份开销。
## ⇒ 超过这个数就退回"每喷口一条加力焰"（旧行为，见 `_rebuild_plumes`）。
##
## 取 4 而不是 2：三台机里柯西 / 佩涅罗佩各 2 个口，**留一倍余量**给以后加口。
const PLUME_SHAPE_MAX_NOZZLES := 4
## 喷口**轴**（机体本地坐标）—— 尾焰粒子沿它射出，横风形变也按它分解。
##
## ⚠️ 它必须与 `FX.afterburner*()` 里写死的 `direction`（本地 +Z）**同源**，
## 而不是与"模型里喷口的真实朝向"同源：形变是相对**发射器自己的喷射方向**算的，
## 两者不一致，顺飞那一刻本该为 0 的横分量会凭空多出一截（焰自己歪掉）。
##
## ⚠️ **两个已知近似，都不是本轮引入的**，都写在这里免得下次再找：
##   ① 喷射方向一直是写死的本地 +Z。模型经 `flight_pitch_deg`（前倾 18°）之后
##      喷口真实朝向略偏下 —— 但 `direction` 一直是 +Z，所以这里跟它对齐。
##   ② 佩涅罗佩 FF 单元两侧那两个口实际朝**下偏外**（2026-09-25 的几何扫描：
##      后视是 55×30 的横条，换 −20°/±35° 看才变圆）。做成**逐口**的表时，
##      这里从常量变成 `item` 上的一个键就够 —— 本轮的形变本来就是按"轴"算的。
const PLUME_AXIS := Vector3(0, 0, 1)
## 横风形变的**满偏加速度**（m/s²）：当"相对气流的横分量"达到
## `profile.player_boost_speed()`（= 冲刺量级）时，焰拿到的横向加速度。
##
## ⚠️ 这个数是**照着俯视取证图定的**，不是拍的。两个口径都记在这，别只信一个：
##
##   估算（最老那一粒的偏出）：位移 = ½·a·t²，t = 束的寿命 0.26 s
##     ⇒ ½ × 1150 × 0.26² ≈ **38.9 m**，而束的射程（v₀ × 寿命）= 67.6 m
##     ⇒ 焰梢偏出约**射程的 0.58**。
##   实测（俯视图逐像素差分，柯西形态 B）：满横风时**整条焰的横向质心**被吹偏
##     **11.2 m**，而"同一档抓两次"的噪声地板是 2.13 m ⇒ **5.2 倍**；
##     同一批图里"固定站位 35 m 处"的弯曲角从 −0.5° 变成 **+17.9°**。
##   质心比"焰梢"小是应该的：位移 ∝ t²（越老越弯），而质心是整条焰的加权平均。
##
## 取证图与两张对照图见 `_r17_report.md`。**要改这个数，先重跑
## `tools/plume_bend_shot.tscn` + `_r17_bend.py`** —— 只改常量不回看，改完
## "弯多少"就没人知道了。
const PLUME_BEND_ACCEL := 1150.0
## 横风形变的一阶跟随速率（1/s）。
##
## ⚠️ **必须平滑，不能把 `fm.velocity` 直连到 `gravity`**：速度本身带噪声
##（气动积分 / 碰撞回弹 / 帧率抖动），直连会让焰抖成一条毛毛虫；
## 而且 QB 起跑那一帧速度是**跳变**的（`QB_BURST_RESPONSE = 22` 的追随率）。
## 12/s ≈ 0.083 s 时间常数 —— 比 QB 窗口（0.45 s）短得多，跟得上，
## 又足够滤掉抖动。
const PLUME_BEND_RESPONSE := 12.0
## 平滑后的横风加速度（**机体本地**坐标）。`_tick_plume_bend()` 是唯一的写入点。
var _plume_bend := Vector3.ZERO
## 本帧的相对风速（**机体本地**坐标，未投影、未平滑）。`_tick_plume_bend()` 唯一写入。
##
## 单独存一份，是为了让"逐喷口按各自轴线投影"复用**同一个** `fm.velocity` 读数 ——
## 每个口各读一次的话，只要有一个口读到别的帧，两条焰的弯就会差一帧（而看不出来）。
var _plume_wind := Vector3.ZERO
## 平移修正的速度权重（× 巡航极速）：WASD/QE 是在自动飞行底速上**叠加的修正**，
## 不是另一种极速 —— 修正永远盖不过底速的量级，自动飞行的主轴不动摇。
const TRANSLATE_OFFSET := 0.65
## **W（向前）那一份的提速幅度倍率** —— 2026-09-29 用户要求：
## 「辅助驾驶模式下按 w 的加速速率下调到 15% 左右」。
##
## 只乘 `translate_dir` 里"镜头水平前的**正向**分量"；后退（S）· 横移（A D）· 升降（Q E）
## 仍按 `TRANSLATE_OFFSET` 满权重。`= 1.0` 即逐位回到旧行为。
##
## 柯西实算：巡航极速 1512 × 0.65 = 982.8（满权重）→ × 0.15 = **147.4**；
## 于是"按 W 的目标速度"从 2268 + 982.8 = 3250.8（比底速 +43%）降到 2268 + 147.4
## = 2415.4（比底速 +6.5%）。
##
## ⚠️ 判据在 `suite_assist_drive._fwd_offset()`，目标值**硬编码** ——
##    别改成从本常量取，那会让"改回 1.0"时判据跟着变绿（自证假绿）。
const TRANSLATE_FWD_SCALE := 0.15
## ---- 平移模式的**转弯侧倾**（批 11 手感：王牌空战式压坡转弯）----
##
## 没有侧倾的平移模式开起来像气垫船：机头转向了、机身却纹丝不滚，
## "在开飞机"的感觉全靠脑补。这里按**机头偏航角速率**给一个平滑的压坡角，
## 横移修正（A/D）再叠一点"朝移动方向压"的分量 —— 转弯与横移都看得见。
## 只动**模型姿态**（want 基准绕自身后轴滚转，机头方向不变），不影响速度合成。
## 王牌空战的标准转弯就是 20~40° 压坡，上限 0.5 rad ≈ 28.6° 取中。
## 每秒偏航 1 rad 对应的压坡角。
const ASSIST_BANK_GAIN := 0.42
## 压坡角上限（rad）。≈ 28.6°。
const ASSIST_BANK_MAX := 0.50
## 横移修正的附加压坡（满杆 A/D 朝移动方向压的这一部分）。
const ASSIST_BANK_STRAFE := 0.30
## 侧倾角的平滑值（rad，正 = 左压坡）。只在 `_apply_translate` 里读写。
var _bank_sm := 0.0
## 上一帧的**水平机头朝向**（算偏航角速率用；零向量 = 尚无基准，本帧不给侧倾）。
var _prev_flat_fwd := Vector3.ZERO
## 拖尾光条（闪避冲刺 / 超级加速时亮，见 `BoostTrail`）。
var _boost_trail: BoostTrail


## 请求一次闪避冲刺（玩家 Shift/X 点按、或测试直呼）。见 `_apply_translate`。
func request_quick_boost() -> void:
	_qb_pending = true


## **QB 真正起跑**的信号（手感批 2026-09-22）：请求被消费、窗口真的开起来时发。
## 玩家侧接它做"爆冲"反馈（镜头脉冲 + 喷口爆闪）；请求被拒（条空/CD/窗口中）
## 不发 —— 没跑起来就没有起跑感，误发反而假。
signal quick_boost_started(dir: Vector3)


## ---- 冲刺限制条（批 10，用户要求）----
## 只对 `profile.has_dash_limit()` 的机生效（**全部 ACE 机**：柯西 / 佩涅罗佩 /
## 阿利宙斯常态 / 阿利宙斯核心；**仅阿利宙斯巡航形态豁免** —— 它 Shift 走超级
## 加速、没有这条；量产机走燃料槽。见 `SuitProfile.has_dash_limit` 的解析）。
##
## 规则（用户原话："不消耗完可以每秒中等速度恢复，消耗完需要等待更长的 cd，
## 满冲刺条可以冲刺 6-7 次这样"）：
##   - 满条 1.0，每次闪避扣 `QB_CHARGE_COST` = 0.15 → **满条 6 次整**；
##     第 7 次点按会把剩下的零头**一口气烧干**（消耗量 = 剩余值）—— 正好"6-7 次"；
##   - 条没空时每秒回充 `QB_CHARGE_REGEN`（约 4.5 秒回满）；
##   - **条被烧干 → 进 CD**（`QB_CHARGE_CD` 秒）：期间不能闪、也不回充，
##     CD 结束后从 0 重新回充。量产机的"槽空了"是同一种体感，ACE 机补的就是它。
const QB_CHARGE_COST := 0.15
const QB_CHARGE_REGEN := 0.22
const QB_CHARGE_CD := 5.0
## 当前冲刺能量（0..1）。只对带限制的机有意义；其它机恒为 1.0。
## 当前转身角（弧度，0..±TAU）。左右冲刺时 0.45 s 扫满一圈，其余时刻恒 0。
var dash_spin := 0.0
## +1 = 向左转身（机头朝左扫），−1 = 向右，0 = 这一记不转。起手时定一次，窗口内不再重判。
var _dash_spin_dir := 0.0
## 转身窗口剩余时间。与 `_qb_timer` 同起同落 —— 这是"收尾恰好 360°"的保证。
var _dash_spin_t := 0.0

var dash_charge := 1.0
## 耗尽后的冷却剩余秒数。> 0 期间既不能闪、也不回充。
var dash_cd := 0.0


## 这台机要不要吃冲刺限制条（转发 `SuitProfile.has_dash_limit`，profile 判空兜底）。
func has_dash_limit() -> bool:
	return profile != null and profile.has_dash_limit()


## 此刻能不能闪避（限制机：CD 中 / 条空了都不行；不限机恒真）。
func can_quick_boost() -> bool:
	if not has_dash_limit():
		return true
	return dash_cd <= 0.0 and dash_charge > 0.0


## 限制条的**显示比例**（HUD 画条用）：CD 中显示 0（空条 + 冷却提示）。
func dash_ratio() -> float:
	return 0.0 if dash_cd > 0.0 else dash_charge


## 机身转身层（轮 33，用户要求）：挂在 `model_pivot` **之上**。
##
## 它是**唯一**承载 `dash_spin` 的节点 —— 为什么不写进 `model_pivot`：
## `rig_anchor()` 的合成式里有 `model_pivot.transform`，并进去等于把转身算进锚点，
## 枪口就跟着画圈了（见 `dash_spin` 的说明）。
var spin_pivot: Node3D
var model_pivot: Node3D
var model_root: Node3D
## 外部的愿望（“第一人称吗 / 还活着吗”）—— `set_model_visible()` 的**唯一写入点**。
var _model_wish := true
## 板上有人吗（有人时踏板模型**自带**机体几何）⇒ 骑手自己的模型必须藏。
##
## ⚠️ 唯一写入点 = `set_rider_hidden()`（只有 `FlightPedal` 调）。
## ⚠️ 这就是 B1 的正解：把“该不该显示”升格成**判据**，
## 而不是“谁最后写谁赢” —— 后者在这里必然输：
## `main._apply_camera_settings()` 是**每帧**跑的外部写入者。
var rider_hidden := false
var rig: SuitRig
var model_bounds := AABB(Vector3.ZERO, Vector3(20, 30, 20))

# ------------------------------------------------------------ 模型自带骨架 / 动画（棒 12 · 2026-09-26）
#
# ## 为什么要有这一节
#
# 老资产（`rx105_xi_gundam.glb` 等 18 个）**全是单网格、无骨架、无动画**（实测
# `skins: 0 / animations: 0`），所以这条链路从没被用过：模型只是"可见件"，
# 炮口/喷口锚点全靠程序化的 `SuitRig` 提供。
#
# 新的 Blender 管线（`gundam-anim`）交付的是**带 50 根骨的 glb**，而且
# ① 动作就在模型里（`fly` / `burst` / `burst_cruise`），② 锚点骨
# （`muzzle_L/R` / `thruster_L/R` / `hand_L/R` …）**也在那副骨架上**。
#
# 所以这两件事必须接上，否则：
#   - 动作是**孤儿**（全仓 0 个 `AnimationPlayer.play()`，实测 N28）；
#   - 锚点取的是 `SuitRig` 的**硬编码佩涅罗佩槽位表**，与真模型解剖对不上
#     （见 `_collect_muzzles()` 里那段说明）—— 表现是"子弹从肚子里出来"。
#
# ## 对老资产零影响（这是本节的安全边界）
#
# 两者都是**按名字命中、命中不到就退回原路径**：
#   - `_model_skel == null`（无骨架）⇒ `rig_anchor()` 走老路；
#   - `model_anim.ready == false`（无 AnimationPlayer）⇒ 播放全部是空操作。
# 实测 18 个老 glb 全部两条都不满足 ⇒ **行为逐位不变**。
var model_anim: ModelAnimator
## 动作切换状态机（`fly` / `burst` / `burst_cruise` 的切换与回待机）。
## **永不 null**：没动画的模型拿到的是 `state == NONE` 的哑机，一切方法是空操作。
##
## ⚠️ 它是**唯一**该被外部驱动动画的入口 —— 想切动作请走 `play_full_burst()`，
## 不要直接调 `model_anim.play_*()`（那会让状态机记一次 `desyncs`，见那里的说明）。
##
## ⚠️ 这里给一个**默认哑机**而不是留 `null`：`_release_model_anim()` 会把它清掉，
## 而 `_setup_model_anim()` 有一条 `inst == null` 的早退分支 —— 两处之间
## 只要有别的代码读一次 `model_fsm`，就会撞上 null。默认值把这条缝焊死。
var model_fsm: ModelAnimFSM = ModelAnimFSM.create(null)
## 巡航形态层（`cruise_on` 的**骨骼版**）。挂在模型骨架的求值链上，
## 按 `cruise_morph` 把 8 根形态骨从 `fly` 的姿态 slerp 到巡航姿态。
##
## **可为 null**，null = 该模型没有形态层（老资产 / 只有常态动作的模型），
## 此时一切是空操作。与 `model_fsm` 的"永不 null"契约**不同**：
## 形态层是可选增强，多用一层哑机只会让 `_tick_cruise_morph()` 白白多判一次。
var _cruise_form: CruiseFormModifier
## 巡航形态**曲线层**（`_cruise_form` 的升级版 · N42·十三）。与它**互斥**：
## 曲线层可用时走曲线层，否则回退 `_cruise_form`。
##
## 区别：`_cruise_form` 是「常态 → 巡航」**两点匀速 slerp**（纯线性）；曲线层沿一条
## **逐帧的变形曲线**走（`xi_cruise_on.glb`），于是 6 根形态骨**同步**展开、
## 且两端慢中间快（**缓动**，不是匀速）—— 见 `FormCurveModifier`。
##
## ⚠️ 两者**绝不并存**：两个 `SkeletonModifier3D` 争写同一批形态骨，
## 执行顺序按子节点序 ⇒ 后者从前者的结果再插值，行为不可预测。
var _form_curve: FormCurveModifier
## 形态骨**帧末焊**载体（轮 42）。⚠️ 它与上面两档**不是同一档东西**：
##
## * `_cruise_form` / `_form_curve` 是 `SkeletonModifier3D`（插在骨架求值链上）——
##   实测**压不过 `AnimationPlayer`**，连把那些轨道 `track_set_enabled(false)`
##   关掉都一样 ⇒ 对「有动画在播」的机体**结构性地无效**；
## * `_form_weld` **不是** `SkeletonModifier3D`：它挂 **`AnimationMixer.mixer_applied`**
##   信号、在「动画求值刚写完」那一刻**直接写骨** —— 实测这是唯一留得住的时机。
##   ⚠️ 别退回 `SceneTree.process_frame`：出图实测那条路**只骗得过局部 pose 读数、
##   骗不过渲染**（看板读 0.00°，真机投影面积却与「焊关」逐位相同 ⇒ 假绿）。
##
## 柯西（形态由动作表达）走 `_form_weld`；其余机体照旧走上面两档，行为逐位不变。
var _form_weld: FormWeld
## 模型自带的骨架（老资产为 null）。
var _model_skel: Skeleton3D
## 骨名 → bone index 的缓存。`rig_anchor()` 每帧被喷口/炮口/夜航灯调很多次，
## 不能每次都线性扫 50 根骨。
var _bone_idx := {}
## 飞行姿态前倾角（度）。0 = 直立悬停，90 = 像战斗机一样平飞。
var flight_pitch_deg := 18.0

# ------------------------------------------------------------ 状态

var max_hp := 120.0
var hp := 120.0
var ifield_max := 0.0
var ifield_hp := 0.0
var alive := true
## 举盾状态。现在是**按一次举 5 秒**（用户要求），不再是按住。
## 它由 `shield_timer` 驱动，外部不该直接写 —— 用 `raise_shield()`。
var shield_up := false
## 剩余举盾时间。
var shield_timer := 0.0
## 举盾结束后的冷却，冷却期间按了也没用。
var shield_cooldown := 0.0
const SHIELD_DURATION := 5.0
const SHIELD_COOLDOWN := 1.0

# ------------------------------------------------------------ 武器

## 火神炮左右炮口轮流的计数器。
##
## ⚠️ 原来是拿 `gun_ammo`（剩余弹数）取模来做轮流的，但 1.2 起火神炮改成**无限弹**，
## 弹数不再递减 —— 继续用它取模就会**永远打在同一个炮口**上。
## 所以轮流必须有自己的计数器，与弹药彻底解耦。
var _gun_cycle := 0
var gun_cooldown := 0.0
var rifle_count := 0
var rifle_cooldown := 0.0

## 收枪窗口（N56）：步枪冷却**归零之后**再等这么久、期间没有射击 ⇒ 收枪。
##
## ## 为什么读冷却、不自己拍一个"停火 X 秒"
##
## `rifle_cooldown` 是"能不能再开一枪"的**唯一真源**（`fire_beam()` 写
## `profile.rifle_interval`、`_tick_weapons()` 每帧递减）：
##   · 冷却中（> 0）⇒ 玩家**开不了枪**，此刻收枪必被下一发打断 ⇒ 不收枪；
##   · 归零后再等 `STOW_DELAY` ⇒ 这一段才是"枪已经能打了、玩家却没打"的信号。
##
## ⚠️ 各机 `rifle_interval` 不同（柯西 0.78 / 佩涅罗佩 0.82）⇒ 自拍一个固定秒数会与
## **射速脱钩**（改射速后收枪时机就不对了，而且不报错）。
## 柯西的窗口总长 ≈ 0.78 + 0.25 = **1.03 s**（而 `shoot` 本身只有 0.40 s）。
const STOW_DELAY := 0.25

## `rifle_cooldown` 归零之后已经过了多久（秒）。冷却期恒 0。= 收枪窗口的计时器。
var stow_idle := 0.0
## 当前弹匣里还剩几发。总弹药无限，但打空要按 R 换弹。
var rifle_mag := 0
var rifle_reloading := false
var reload_timer := 0.0
var funnel_count := 0
var funnel_cooldown := 0.0
## 弹夹容量（发，来自 `profile.funnel_count`）。批 14：浮游导弹**总量无限**，
## 只受弹夹限制 —— 打空自动换弹（`funnel_reload_left`），换完重新满上。
var funnel_mag_size := 0
## 换弹剩余秒数（> 0 = 换弹中，不能发射）。
var funnel_reload_left := 0.0
## ---- 火神炮过热（批 14）：无限弹的代价必须存在 ----
## 热量 0..1。每发 +VULCAN_HEAT_PER_SHOT，停火后按 VULCAN_COOL_RATE 冷却。
var vulcan_heat := 0.0
## 过热卡住标记。⚠️ 过热后必须冷却到 VULCAN_RESUME 以下才能再开火 ——
## 只判"热量 >= 1 不许开火"的话，冷却几帧后第一发就把热量顶回 1.0，
## 陷入"每打一发就过热"的死循环。
var vulcan_overheated := false
## 过热瞬间起算的**最短**卡住秒数 —— 用户要的"过热条和cd"里的那个 cd。
var vulcan_jam_left := 0.0

# ---- 蓄力激光炮（阿利宙斯常态 / 巡航；2026-09-28 用户指定）----
#
# 参数全部来自 `SuitProfile.cannon_*`（见那里的长注释）。
# 这里的两个变量都是**运行时状态**，与蓄力进度无关 ——
# "按住多久"是输入层的事（`PlayerController`），机体只回答"能不能放 / 冷却还有多久"。
##
## 大炮的剩余冷却（秒）。0 = 可以发射。从 `fire_cannon()` **发射那一刻**起算
## （用户没说从哪算；取发射时刻，因为"松手到柱消失"那 4 秒里玩家已经在等下一发了）。
var cannon_cd_left := 0.0
## 当前正在照射的那条激光柱（可为 null）。**只用于存活判断**：
## 柱自己每帧跟着炮口走，这里不查它的位置。
var active_cannon: Node3D = null

var combat_buffs = preload("res://scripts/combat/psycho_combat.gd").new()
var saber_cooldown := 0.0
var saber_state := SaberState.IDLE
var saber_target: Node3D = null
var saber_timer := 0.0
## 突进期间挂在手部锚点上的**光束刀刃**（批 10 打击感，见 `FX.beam_blade`）。
## 之前挥刀全程模型上没有刀 —— "谁在劈砍"只有音效在说，画面上读不出。
## 突进开始显示、`_end_saber` 摘除；变形/阵亡路径由 `_end_saber` 统一收口。
var _blade: Node3D = null
## 光刃的**锚点**（`_blade` 的父节点）。它挂在 **FlightBody 自己**下面、**不在 `model_root` 里**。
##
## ⚠️ 为什么不直接把刀挂进 `_model_skel` / `model_root`（那样写起来更省事）：
## `_rebuild_visual()` 里的 `_apply_owner_materials()` 会
## `model_root.find_children("*", "MeshInstance3D", true, false)` 给**每一个**
## MeshInstance3D 盖上 `visibility_range_end`（逐件细节剔除，轮 41 性能）。
## 刀身一旦被盖上就是"**远距离静默消失**"（不报错、回归全绿）—— 见 `DESIGN` §5.4 那条 ⚠️。
## 挂在 FlightBody 自己下面既不会被那次遍历扫到，又能随本体一起显隐。
##
## 真模型路径跟随 `hand_L`，动画求值后同帧更新位置与朝向；
## 无骨架形态也使用独立可见锚点，避免刀刃被隐藏的占位骨架一并藏掉。
var _blade_anchor: Node3D = null
var _blade_bind_basis := Basis()
# Gustav's shoulder shield is exported under LowerArm.L. Keep both the mesh
# bone and gameplay shield anchor on the shoulder, retaining their bind offsets.
var _shoulder_armor_bind: Dictionary = {}
var _gun_grip_bind: Dictionary = {}
var _gun_barrel_in_hand := Vector3.FORWARD
var _regz_motion
var thunderbolt_systems
var thunder_slow_left:=0.0
var thunder_slow_rate:=1.0
var thunder_lock_left:=0.0
var flash_blind_left:=0.0
var _flashbang_overlay: CanvasLayer
var sazabi_systems
var _gun_pose_ready := false
var _gun_recoil_clock := 1.0
var _saber_visual_tail := 0.0
var _saber_visual_clock := 0.0
var _saber_swing_released := false
var _saber_anim_style: Dictionary = {}
const FLARE_MAG_SIZE := 30
const FLARE_AUTO_RELOAD_TIME := 20.0
var flare_reload_left := 0.0
var flare_count := FLARE_MAG_SIZE
var flare_cooldown := 0.0
var flare_interval := 0.6
## 干扰弹的"有效期"（1.2，方案 C-3）：撒出去之后这么长时间内算"被干扰"，
## 对**锁定质量**有惩罚（见 `LockOnSystem.target_quality()` 的第 5 项）。
## ⚠️ 用计时器而不是"还剩几颗"：干扰弹是"一次撒一把、烧几秒"的东西，
## 用数量表达会让"刚撒完"和"撒完很久"完全没区别。
var flare_active := 0.0

# ---- 修复包（1.2 用户要求）----
#
# "每次战斗都有三个修复包，每个修复包能恢复 40% 的血量"。
# 做成**持续 2.5 秒的修复通道**而不是瞬回：瞬回在狗斗里等于"按一下满血"，
# 没有任何风险；通道则要求玩家抓住喘息窗口，而且**受损即中断**（见 take_damage）——
# 否则"边挨打边回血"会让修复包变成无敌药。
var repair_packs := 3
const REPAIR_TIME := 2.5
const REPAIR_FRACTION := 0.40
var _repair_left := 0.0
var _repair_total := 0.0
## 撞击伤害冷却，见 RAM_COOLDOWN。
var ram_cooldown := 0.0

## ★63-25 军刀撞击豁免**余量**（秒）。> 0 时本机不结算撞击伤害。
##
## ⚠️ 用「余量」而不是「绝对时刻」，是为了与同类的 `ram_cooldown` / `saber_cooldown`
##    同形状 —— 也就能和它们**一起在 `_tick_weapons()` 里递减**（少一个真源）。
## ⚠️ **不要**再加一个布尔开关：见 `in_ram_guard()` 的说明。
var ram_guard_left := 0.0

## "不可被锁定"到期时刻（用 Game.clock 作时间基准，便于测试推进）。
var unlockable_until := 0.0
var discard_cooldown := 0.0

# ---- 飞行踏板（1.2）----
#
# 只有 AI 敌机会骑（`configure_pedal()` 由 `main._attach_ai()` 调）。
## 骑乘中的踏板节点；null = 没骑。**别直接判它**，用 `has_pedal()`。
##
## ⚠️ **被载机不用这个字段** —— 他的踏板挂在领机身上，见 `carried_by` 与
## `pedal_owner()`。一块板载两台时，板只有一份、挂在领机上。
var pedal: FlightPedal = null
## 正在飞向我的踏板（**呼叫到一半**；到了才变成 `pedal`）。
##
## 见 `mount_pedal()`：呼叫不是瞬移，板会从天上飞过来。
var _inbound_pedal: FlightPedal = null
## **被载**：由领机的踏板驮着走。
##
## ⚠️ **当前路线（每台机体各带一块板）下它恒为 null**，保留字段是为了
## 早先那条"一板载两台"的路还能被人认出来 —— 那条路的问题是
## "两台画成一个烤死的样子、各自不能独立开火/脱落"，已被否决（见
## `FlightPedal.USE_DEPLOYED_MODEL` 与 `main.attach_pedal_pair` 的注释）。
## **不要再往它上面接新逻辑**：`_apply_carried()` 已经删了，
## 现在写上它不会有任何效果，只会让人以为"运动学贴合"还在。
var carried_by: FlightBody = null
## 我是这条搭载链的领机时，自己占第几个挂位（0 = 前）。被载机不读它。
var pedal_slot := 0
## 脱板之后的失能剩余时间（秒）。>0 时不能开火、速度被夺走。
var _stagger_timer := 0.0
## 第一次触碰相杀时用的标记（测试与 HUD 都不用读它）。
## ⚠️ **必须留下一个可断言的痕迹**：相杀是瞬时的，跑完之后从状态上看不出发生过。
## 早先只靠 `saber_cooldown` 反推（>1.2 s 就说明刚相杀过），
## 但正常挥刀的冷却也是 3.2 s —— 两者分不开，测试会假绿。
var clash_count := 0
## 踏板的**转向折扣**贴过没有。见 `apply_pedal_flight_bonus()`：
## 它是一个"乘在基值上"的一次性操作，而 `_apply_top_speed()` 会被调多次
## （挂载时 / 变形时），没有这个标记就会重复相乘。
var _pedal_turn_applied := false

# ---- 燃料槽（1.2 第十九轮：量产机专用）----
#
# ## 为什么用"意愿 + 单一裁决"而不是在各处加门禁
# `fm.boosting` 在工程里有 **10 个写入点**（玩家手动 / 辅助驾驶 / 核心脱出 /
# AI 的巡航决策 / 低空逃逸……）。如果让"用 Shift"这件事各自去查槽，
# 必然漏掉一两处 —— 而漏掉的表现是"槽空了还能加速"，属于最难查的那类静默失效。
# 所以：**各处照旧表达意愿**（`fm.boosting`），由机体在这一处统一裁决 ——
# 槽不够就把意愿否掉。既有代码一行都不用改。
## 满槽能连续加速的秒数流水账（秒）。0 = 空了。
var jet_left := 0.0
## 本帧**实际**在用燃料（裁决之后的真实状态）。HUD 与特效读它。
var jet_active := false


## 辅助驾驶模式下：槽烧空后要**涨回满槽的这个比例**才重新放行加力。
##
## ⚠️ 取 0.5 而不是 0，是为了**防抖** —— 不加这道滞回门，槽刚涨过 0 的下一帧就会被
## 重新放行加力、当场烧光，加力退化成每 0.1 s 一次的脉冲（引擎音与尾焰跟着闪）。
## 门限的取值**不改变**加力占比（回充与消耗都是线性的），只决定一来一回的周期多长。
const JET_ASSIST_REARM := 0.5
## 辅助驾驶模式下「槽已烧空、正在等回充」的闩。true 期间**不给加力**，
## 直到槽涨回 `JET_ASSIST_REARM` 比例。手动模式每帧清掉它。见 `resolve_jet_gauge()`。
var _jet_assist_recover := false


## 这台机有没有燃料槽（只有量产机有，见 `SuitProfile.has_jet_gauge`）。
func has_jet_gauge() -> bool:
	return profile != null and profile.has_jet_gauge


## 槽的比例（1 = 满）。ACE 机没有槽 ⇒ 恒 1.0（HUD 因此可以画"满"或干脆不画）。
func jet_ratio() -> float:
	if not has_jet_gauge():
		return 1.0
	if profile.jet_seconds <= 0.0:
		return 1.0
	return clampf(jet_left / profile.jet_seconds, 0.0, 1.0)


## 槽见底了（HUD 用来闪红 / 提示"没槽了，得靠巡航"）。
func jet_empty() -> bool:
	return has_jet_gauge() and jet_left <= 0.0


## 本帧的回充速率（燃料秒 / 秒）。**单一真源** —— 骑板 / 辅助 / 手动三条路都读它。
##
## ⚠️ 抽出来不只是去重：它决定「槽多久回满」，而这个数现在有一条**外部口径**
##（`SuitProfile.jet_recharge` = 柯西冲刺条速率的 80%，推导写在 `SuitProfile` 那边）。
## 三条路各写一遍的话，将来调平衡必然漏掉一两处 —— 而漏掉的表现是
##「辅助模式和手动模式回充不一样快」，不报错、也几乎看不出来。
func _jet_recharge_rate() -> float:
	if profile == null:
		return 0.0
	return profile.jet_seconds / maxf(profile.jet_recharge, 0.001)


## 按想不想加速、以及槽够不够，裁决本帧**实际**的加力状态。返回裁决结果。
##
## ⚠️ **这是 `fm.boosting` 的唯一收口**：所有表达意愿的地方（玩家、AI、辅助驾驶）
## 都照旧写 `fm.boosting`，跑完 `_think()` 之后由这里统一改写成「真的能不能加」。
func resolve_jet_gauge(delta: float) -> bool:
	if not has_jet_gauge():
		# ACE 机：没有槽这回事，加速想按多久按多久。
		jet_active = fm.boosting
		return jet_active
	# ---- 骑在踏板上 ⇒ **机体不烧自己的槽**（1.2 第二十四轮，用户指定）----
	#
	# 用户原话：「一号机能操控踏板的飞行，**踏板飞行的时候机体是不消耗燃料的**，
	# **踏板本身也不需要消耗燃料**」。
	# 踏板的推进是它自己的（`apply_pedal_flight_bonus()` 给的是油门响应），
	# 所以骑乘期间机体那本账不动 —— 于是「靠踏板赶路」对量产机的意义
	# 从「省一点」变成「完全不花」，那才是它值得等板的原因。
	#
	# ⚠️ 只**不掉**、照旧**回充**：不这样的话「骑一段板 = 免费把槽充满」，
	# 板就成了移动加油站（比设计意图多给了一份好处）。
	if has_pedal() and not pedal_staggered():
		jet_active = fm.boosting
		jet_left = minf(jet_left + delta * _jet_recharge_rate(), profile.jet_seconds)
		return jet_active
	# ---- 辅助驾驶（平移模式）：常驻加力 ⇒ 槽空之后必须能自己涨回来 ----
	#
	# 用户原话（2026-09-30 · 轮 44）：「修改梅萨系列和古斯塔夫的燃料槽：
	# **在辅助驾驶模式下也能恢复**，恢复速度提升至柯西的 80%」。
	#
	# 为什么必须单独一条路：辅助驾驶期间 `PlayerController._tick_assist()` **每帧**把
	# `fm.boosting` 压成 true（那段注释写着「替你按住 Shift」）⇒ 槽一旦烧空，旧代码永远
	# 落在「想加速但没槽」那一支里、**再也不回充**。手动模式还能松手攒回来，
	# 辅助模式连那个机会都没有 —— 量产机在辅助模式下等于**永久失去加速**。
	#
	# ⚠️ 这条路必须有**滞回门**（`JET_ASSIST_REARM`）：不加的话，槽刚涨过 0 的下一帧
	# 就会被重新放行加力、当场烧光 —— 加力退化成每 0.1 s 一次的脉冲，
	# 引擎音、尾焰、以及一切读 `jet_active` 的特效全跟着闪。
	# ⚠️ 门限只决定「一来一回的周期有多长」，**不影响加力占比**：回充与消耗都是线性的，
	# 占比恒为 `jet_seconds / (jet_seconds + jet_recharge)` ≈ 58%，与门限设在哪儿无关。
	if translate_mode:
		if _jet_assist_recover:
			# 等回充：加力先撤下来，涨到门限才解锁。
			jet_active = false
			fm.boosting = false
			jet_left = minf(jet_left + delta * _jet_recharge_rate(), profile.jet_seconds)
			if jet_left >= profile.jet_seconds * JET_ASSIST_REARM:
				_jet_assist_recover = false
			return jet_active
		var want_a := fm.boosting
		if want_a and jet_left > 0.0:
			jet_active = true
			jet_left = maxf(jet_left - delta, 0.0)
			return jet_active
		jet_active = false
		fm.boosting = false
		if want_a:
			# 想加速但槽空 ⇒ 进「等回充」闩（HUD 的闪红照旧来自 `jet_empty()`）
			_jet_assist_recover = true
		else:
			# 辅助开着但这一帧没在加力（例：防撞地接管时 `_tick_assist()` 提前 return）
			jet_left = minf(jet_left + delta * _jet_recharge_rate(), profile.jet_seconds)
		return jet_active
	# ---- 手动模式：**保持原样**（只把回充速率换成单一真源）----
	#
	# 手动模式下「槽空就真的没加力、要松手才回充」是**有意的**：它是这一族机体的核心代价，
	# 也是「必须靠踏板」成立的原因。辅助模式那条路是**补回它本来不可能有**的松手机会，
	# 不是把这条代价抹掉。
	_jet_assist_recover = false
	var want := fm.boosting
	if want and jet_left > 0.0:
		jet_active = true
		jet_left = maxf(jet_left - delta, 0.0)
	elif want:
		# 想加速但槽空了 ⇒ **否掉意愿**。这就是「时间限制」的字面实现。
		jet_active = false
	else:
		jet_active = false
		# 只在**不加速**时回充（加速期间不回 —— 否则续航会被拉长，等于槽更大）。
		jet_left = minf(jet_left + delta * _jet_recharge_rate(), profile.jet_seconds)
	# 把裁决结果写回去：下游（气动、特效、音频）读的都是它。
	fm.boosting = jet_active
	return jet_active

## 上一次搭乘/脱离失败的原因（空串 = 没失败过）。见 `mount_pedal()`。
var _fail_reason := ""

## 弹道/导弹/干扰弹的宿主容器（由 main 注入）。
var projectile_container: Node = null

var _afterburner_fx: GPUParticles3D
## 冲刺焰（**形态 B**，2026-09-25）：辅助驾驶的闪避冲刺 / 超级加速时亮，
## 与 `_afterburner_fx`（形态 A，普通加力）**永不同时 emitting**。
## 两者的形态差异见 `FX.afterburner_dash()` 的对照表。
var _dash_fx: GPUParticles3D
## 冲刺焰的马赫环（激波串）。与 `_dash_fx` 同点同向、同开同关 ——
## 单独亮环会像"机尾掉了几个呼啦圈"。
var _dash_rings: GPUParticles3D
## 多喷口特效（`profile.engine_plumes` 非空时才建）：每个喷口一个尾焰 + 一个常亮光晕。
## 每项 = `{ "fx": GPUParticles3D, "glow": MeshInstance3D }`。
var _plume_fx: Array[Dictionary] = []
## 浮游导弹左右挂架的交替计数器（见 `fire_funnel`：一次三发，不能拿剩余弹数取模）。
var _funnel_slot := 0
## 所有喷口光晕**共用**的材质：亮度整体调（随油门/加速），也省 draw call。
var _plume_mat: StandardMaterial3D
var _smoke_fx: GPUParticles3D
var _nav_strobe: MeshInstance3D
## 夜航灯节点 + 它挂在哪个槽位上（形态切换后要按新骨架重新对位）。
var _nav_lights: Array[Dictionary] = []
var _strobe_phase := 0.0
## 引擎循环音。
var _engine: AudioStreamPlayer3D
## 柯西座舱的巡航检测音（1.5 秒一次）。
var _detect_player: AudioStreamPlayer
var _detect_timer: Timer
var _hit_flash := 0.0
var _muzzle_local: Array[Vector3] = []
var _weapon_emitters
var _model_mounts: Dictionary = {}
var wire_cd_left := 0.0
var _neue_motion := Vector3.ZERO
const GP03_BAZOOKA_MAG := 16
const GP03_BAZOOKA_RELOAD := 12.0
const GP03_BAZOOKA_INTERVAL := 0.35
var bazooka_mag := GP03_BAZOOKA_MAG
var bazooka_reload_left := 0.0
var bazooka_cd := 0.0
var grapple_cd := 0.0
var gp03_grab_owner: Node3D
var active_grapple: Node3D
var active_wire_arms: Node3D

var _wreck_timer := -1.0
var _ifield_broken_emitted := false
var _hover_pose := 0.0


# ============================================================ 生命周期

func flare_mag_size() -> int:
	if profile!=null and SuitProfile.is_thunderbolt(profile.id):return 90
	if profile != null and profile.id == SuitProfile.Id.REGZ_CUSTOM: return 120
	if profile != null and profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL]:
		return 120
	return FLARE_MAG_SIZE

var nu_systems: Node3D
var nu_motion: SkeletonModifier3D

func _ready() -> void:
	if profile == null:
		profile = SuitProfile.penelope() if team != 0 else SuitProfile.xi()
	if profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL,SuitProfile.Id.SAZABI]:
		flight_pitch_deg = 0.0
	flare_count = flare_mag_size()
	form_index = maxi(profile.form, 0)
	# 燃料槽开局是**满的**（1.2）。ACE 机没有槽，这个字段对它无意义（恒 0）。
	jet_left = profile.jet_seconds if profile.has_jet_gauge else 0.0
	add_to_group("units")
	if is_player:
		add_to_group("player")
	else:
		add_to_group("hostiles")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	slide_on_ceiling = false
	floor_stop_on_slope = false
	collision_layer = UNIT_LAYER
	collision_mask = WORLD_LAYER | UNIT_LAYER

	_apply_profile_to_flight()
	max_hp = profile.hull_hp
	hp = max_hp
	ifield_max = profile.ifield_hp
	ifield_hp = ifield_max
	# 武器基数也来自机体表
	rifle_count = profile.rifle_count
	rifle_mag = profile.rifle_magazine
	funnel_count = profile.funnel_count
	funnel_mag_size = profile.funnel_count
	# ★63-24：修复包个数也从机体表取（默认 3）—— A7「修复包增备」改的就是它。
	repair_packs = profile.repair_packs

	_build_visual()
	Settings.changed.connect(_on_material_style_changed)
	_build_collision()
	_build_attachments()
	var sonic_cloud := SONIC_CLOUD.new()
	sonic_cloud.body = self
	add_child(sonic_cloud)
	_collect_morph_nodes()
	if projectile_container == null:
		projectile_container = get_parent()
	if profile.id in [SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.ZORIN_SOUL]:
		nu_systems = preload("res://scripts/combat/zorin_systems.gd").new() if profile.id==SuitProfile.Id.ZORIN_SOUL else preload("res://scripts/combat/nu_systems.gd").new()
		nu_systems.body = self
		add_child(nu_systems)
	if SuitProfile.is_thunderbolt(profile.id):
		thunderbolt_systems=preload("res://scripts/combat/thunderbolt_systems.gd").new()
		thunderbolt_systems.install(self)
	Game.register(self)
	if is_player:
		Game.mark_player(self)


# ============================================================ 多形态 / 变身
#
# 用户需求（1.1）："阿利宙斯分为三个模式…在血量减低之后进行一次爆炸，
# 然后在烟雾中切换为量产型ν高达模式。"
#
# 实现上把形态做成**一份 SuitProfile 换另一份**：模型、全高、耐久上限、
# 速度上限、转向系数、武器门禁全部来自 profile，所以换形态只需要
# （a）换 profile（b）重建可见模型（c）重设耐久（按比例带过去）。
# 别的系统（AI 提前量、HUD、锁定）一行都不用改 —— 它们读的都是 unit.profile。

## 取第 i 个形态的 profile。
func form_profile(i: int) -> SuitProfile:
	if profile == null:
		return null
	return SuitProfile.by_id_form(profile.id, i)


func form_count() -> int:
	return profile.form_count if profile != null else 1


func form_name() -> String:
	return profile.form_name() if profile != null else ""


## 玩家能手动切的形态：**最后一个形态除外**（那是"爆壳变身"的产物，
## 只能由战损触发，手动切等于白送一次免死）。单形态机体返回空。
func switchable_forms() -> Array[int]:
	if profile != null and profile.id == SuitProfile.Id.REGZ_CUSTOM: return [0,1]
	var out: Array[int] = []
	var n := form_count()
	for i in n - 1:
		out.append(i)
	return out


## 切换"可手动切换的形态"之间的循环（玩家按 Z 走这里）。返回是否真的换了。
##
## 冷却 4 秒（用户指定）。冷却期间调用会返回 false，调用方负责给一句提示 ——
## 玩家按了没反应会被当成按键失灵。
func toggle_form() -> bool:
	var list := switchable_forms()
	if list.size() < 2 or form_cooldown > 0.0:
		return false
	var idx := list.find(form_index)
	var next := list[(idx + 1) % list.size()] if idx >= 0 else list[0]
	if not switch_form(next):
		return false
	form_cooldown = SuitProfile.FORM_COOLDOWN
	return true


## ★63-24 无限强化演习：**局内拿到卡之后，把"抄来的"那批读数重新对齐 `profile`**。
##
## ## 为什么必须有它（否则是**静默半失效**）
##
## `_ready()`（本文件 `:904` 一带）把 `profile.hull_hp` / `ifield_hp` /
## `rifle_count` / `rifle_magazine` / `funnel_count` / `repair_packs` **抄进自己的字段**，
## 之后**再也不看 profile**。
## ⇒ 局内拿卡若不调本函数：库存（`Game.endless_owned`）涨了、卡也"装上"了，
##    **而机体一点没变** —— 玩家拿到《装甲增厚》连装三张，血条一格不涨，
##    并且**一处都不报错**（设计 §5.5 坑 1 的同族，只是发生在"第二张之后"）。
##
## ## 取舍：**按增量补**，不是"按比例保留"
##
## `switch_form()` 用的是比例（形态换了，满值不同 ⇒ 比例才有意义）。
## 这里**刻意反过来**：本模式是"越打越强"的正反馈，拿卡那一刻必须**立刻**看得见收益
## ⇒ `hp += (新上限 − 旧上限)`。比例保留会让"残血拿到装甲卡"几乎无感，
## 而那正是最需要它的时候。
##
## ⚠️ **幂等**：`max_hp` / `ifield_max` 每次都**从 profile 重算**（不是累乘），
## 而 `hp` 加的是"这一次 max 涨了多少" ⇒ 连着调 1 次与 3 次结果一致。
## 判据在 `suite_endless` 的 `INTERMISSION` 分节。
##
## ⚠️ 只在**演习局**由 `main._take_endless_card()` 调。别的模式**没有**这条路径
## ⇒ 既有对局的读数逐位不变。
func refresh_profile_stats() -> void:
	if profile == null:
		return
	var prev_max := max_hp
	var prev_ifield_max := ifield_max
	# 飞行性能（顶速 / 加速 / 转向）走 `switch_form()` 用的同一条路 ——
	# 那条路在"变形"时已经被证明可以中途跑（不会把飞行状态打飞）。
	_apply_profile_to_flight()
	max_hp = profile.hull_hp
	ifield_max = profile.ifield_hp
	hp = clampf(hp + (max_hp - prev_max), 1.0, max_hp)
	# ⚠️ 下限 0（立场可以被打空），上限 ifield_max；别用 `maxf(..., 1.0)`：
	# 立场打空之后本来就该是 0（`rad_a1`「弃盾」把它钉在 0 是**有意的代价**）。
	ifield_hp = clampf(ifield_hp + (ifield_max - prev_ifield_max), 0.0, ifield_max)
	# 武器 / 挂架 / 修复包：只许**变多**，绝不在半途把玩家的东西收走。
	# （`repair_packs` 用 `maxi` 而不是覆盖：卡是"绝对置值"，而局内可能已经用掉几个
	#   —— 取大值等于"增备"，取覆盖会让"已经用掉的包"凭空回来，那是另一回事。）
	rifle_count = maxi(rifle_count, profile.rifle_count)
	funnel_count = maxi(funnel_count, profile.funnel_count)
	repair_packs = maxi(repair_packs, profile.repair_packs)


## 切形态。
##
## `keep_ratio=true`（默认）：把当前的血/盾**按比例**带到新形态上。
## 手动在巡航/常态之间变形时两边满值相同，比例带过去就等于没变；
## 爆壳变身时两边满值不同，比例带过去才有意义 —— "外壳还剩四成血"就该变出
## "核心还剩四成血"，而不是要么满血复活、要么直接暴毙。
## `refill=true`：弹匣填满（变身那一刻核心是"刚露出来"的，枪是满的）。
func switch_form(i: int, keep_ratio := true, refill := false) -> bool:
	if profile == null or i == form_index:
		return false
	var forms := SuitProfile.forms_of(profile.id)
	if i < 0 or i >= forms.size():
		return false
	var newp := SuitProfile.by_id_form(profile.id, forms[i])
	if newp == null:
		return false

	var hp_ratio_before := hp_ratio()
	var ifield_ratio_before := ifield_ratio()
	# 形态切换期间正在突进的军刀要掐断：模型都换了，旧突进的目标姿态没有意义
	_end_saber()

	if profile.id == SuitProfile.Id.GP03D and newp.id == SuitProfile.Id.GP03S:
		if is_instance_valid(active_grapple): active_grapple.free()
		if is_instance_valid(active_cannon): active_cannon.queue_free()
		active_grapple = null
		active_cannon = null
		gp03s_weapon = "rifle"
		bazooka_mag = GP03_BAZOOKA_MAG
		bazooka_reload_left = 0.0
		bazooka_cd = 0.0
		flight_pitch_deg = 18.0
	profile = newp
	if profile.id == SuitProfile.Id.PENELOPE and profile.form == 1:
		penelope_cruise_enabled = false
		cruise_morph = 0.0
		_penelope_backflip = false
		_dash_spin_t = 0.0
		dash_spin = 0.0
		fm.super_boost = false
	if profile.id == SuitProfile.Id.GP03S and has_method("_on_gp03s_escape"): call("_on_gp03s_escape")
	form_index = forms[i]
	_apply_profile_to_flight()
	max_hp = profile.hull_hp
	ifield_max = profile.ifield_hp
	if keep_ratio:
		hp = maxf(max_hp * hp_ratio_before, 1.0)
		ifield_hp = maxf(ifield_max * ifield_ratio_before, 0.0)
	else:
		hp = max_hp
		ifield_hp = ifield_max
	rifle_count = maxi(rifle_count, profile.rifle_count)
	# 燃料槽：形态换了之后"有没有槽"也可能变（阿利宙斯三形态都是 ACE 机、
	# 都没有槽，所以当前是空操作 —— 但把这条写在这里，将来给某个形态加槽时
	# 不会出现"换了形态槽还是旧形态的量"）。**保留余量、不补满**：
	# 补满的话"变形"就成了免费的续航补给。
	if profile.has_jet_gauge:
		jet_left = minf(jet_left, profile.jet_seconds)
	else:
		jet_left = 0.0
	if refill:
		rifle_reloading = false
		reload_timer = 0.0
		rifle_mag = profile.rifle_magazine
	else:
		rifle_mag = mini(rifle_mag, profile.rifle_magazine)
	# 没有导弹的形态：把弹仓清掉（HUD 上那一条会显示 0 并且不可用）
	if not profile.has_missiles:
		funnel_count = 0
		# ⚠️ 弹夹容量也要一起清（批 14）：留着的话自动换弹会把弹夹重新满上，
		# "本形态无导弹"的形态 HUD 上反而显示满弹夹。
		funnel_mag_size = 0
		funnel_reload_left = 0.0
	if not profile.has_saber:
		_end_saber()

	display_name = profile.display_name
	# 变形特效的**顺序**有讲究：
	#   1. 先把光球挂到自己身上（`parent = self`）—— 它跟着机体平飞，
	#      换模型的那两帧正好被它罩住（用户要求："特效跟着机体走"）；
	#   2. 再换模型；
	#   3. 最后把**新模型自己**刷白（那层遮罩只存在于机体的像素上）。
	var ball_r := model_flash_radius(newp)
	FX.form_flash(self, Vector3.ZERO, ball_r, profile.accent.lerp(Color(1, 1, 1), 0.35))
	# 变形音效（用户提供的素材）。玩家自己听非定位版，别人变形听 3D 定位版 ——
	# 和枪声/爆炸一样的分工：座舱里不该有距离衰减。
	if is_player:
		Audio.play_self("arizeus_transform", -3.0)
	else:
		Audio.play_3d("arizeus_transform", global_position, -2.0)
	_rebuild_visual()
	_rebuild_collision()
	_flash_model()
	form_changed.emit(form_index, profile.form_name())
	return true


## 变形闪光球该多大：按机体可见包围盒给，还要把**目标形态**考虑进来
## （巡航形态比常态长一倍多：39 m vs 33 m 全高，只按当前模型给的话，
## 常态 → 巡航那一次球会短一截、换模型时露出机头）。
##
## 1.1 用户看过第一版之后要求"半径再大一点"：系数 0.70 → **0.95**。
## 大一点是安全的，因为"遮住模型"这件事主要由 `_flash_model()` 那层
## （把模型自己刷白）负责，光球只负责"闪一下"的观感。
func model_flash_radius(target: SuitProfile = null) -> float:
	var b := model_bounds.size
	var r := maxf(maxf(b.x, b.y), b.z)
	if target != null:
		r = maxf(r, target.target_height)
	return clampf(r * 0.95, 6.0, 90.0)


## 机体自身的白闪：把模型的材质临时换成"不受光、纯白"，再把透明度推到 1。
##
## 这是"遮挡模型但不遮挡屏幕"的真正实现 —— 闪光只出现在**机体自己的像素**上，
## 所以相机贴多近都不会糊住屏幕（只靠光球做不到：相机一近，球就占满画面）。
## 材质是一份共享的 `StandardMaterial3D`，逐个 `MeshInstance3D` 走
## `transparency`（几何体级的不透明度），结束时把 override 摘掉、透明度清零。
func _flash_model() -> void:
	_flash_nodes.clear()
	_model_flash = 0.0
	if model_root == null or not is_instance_valid(model_root):
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_receive_shadows = true
	for c: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		mi.material_override = mat
		_flash_nodes.append(mi)
	if not _flash_nodes.is_empty():
		_model_flash = MODEL_FLASH_TIME


func _tick_model_flash(delta: float) -> void:
	if _model_flash <= 0.0:
		return
	_model_flash = maxf(_model_flash - delta, 0.0)
	var t := 1.0 - _model_flash / MODEL_FLASH_TIME
	# ⚠️ 这里要的是"**变成纯白**并保持"，不是"渐隐"。
	# `GeometryInstance3D.transparency` 是**透明度**（0 = 不透明、1 = 完全看不见），
	# 第一版按 `t` 直接写进去，结果是"机体越闪越透明、最后整台机消失，
	# 0.55 秒后再啪地出现"—— 截图里直接拍到了"巡航形态看不见机体"。
	# 正确做法：用 `1 - t*5` 在头 0.2 秒里从"原样"过渡到"纯白"，之后一直保持白，
	# 最后由 `_end_model_flash()` 一次性摘掉 override（那一瞬被光球盖住）。
	var a := clampf(1.0 - t * 5.0, 0.0, 1.0)
	for mi: MeshInstance3D in _flash_nodes:
		if is_instance_valid(mi):
			mi.transparency = a
	if _model_flash <= 0.0:
		_end_model_flash()


## 收尾：把材质 override 与透明度都还原。**必须还原** ——
## 忘了摘 override 的话，模型会永久停在"纯白不受光"的状态，
## 表现是"按一次 Z 之后机体就变成一坨白影子再也好不了"。
func _end_model_flash() -> void:
	for mi: MeshInstance3D in _flash_nodes:
		if is_instance_valid(mi):
			mi.transparency = 0.0
			mi.material_override = null
	_flash_nodes.clear()
	_model_flash = 0.0


## 血量降到 `profile.transform_hull_ratio` 时爆壳变身（一次性）。
func _begin_transform() -> void:
	if _transformed or profile == null or profile.transform_to_form < 0:
		return
	combat_buffs.kick_left = 0.0
	_transformed = true
	_form_swap_pending = profile.transform_to_form
	_form_swap_timer = SuitProfile.TRANSFORM_COVER
	invuln_until = Game.clock + SuitProfile.TRANSFORM_COVER + 0.2
	var parent := get_parent()
	if parent != null:
		# 1.2：脱出要**更大**的爆炸与烟（用户要求"脱出的时候要有更大的爆炸和烟雾"）。
		# 之前的 1.9/2.2 看着像"又一次命中"；现在是整台外壳炸开，所以再加一档，
		# 并且分两次（先炸开、烟再追上来）—— 单次爆炸在这个尺度下显得很轻。
		FX.explosion(parent, global_position, 3.4, Color(1.0, 0.76, 0.34))
		FX.explosion(parent, global_position + Vector3(0, 6.0, 0), 2.4, Color(1.0, 0.55, 0.22))
		FX.smoke_burst(parent, global_position, 4.6)
		FX.smoke_burst(parent, global_position + Vector3(0, 10.0, 0), 3.2)
	Audio.play_3d("boom_l", global_position, 2.0, 0.96, 26000.0)
	if is_player:
		Game.log_event("外壳剥离 —— 核心形态启动")
	else:
		Game.log_event("敌机外壳剥离")
	transform_started.emit(_form_swap_pending)


func _tick_transform(delta: float) -> void:
	if _form_swap_timer <= 0.0:
		return
	_form_swap_timer -= delta
	if _form_swap_timer > 0.0:
		return
	var to := _form_swap_pending
	_form_swap_pending = -1
	_form_swap_timer = 0.0
	# 换壳发生在烟雾里：先补一团烟再换，玩家看到的是"烟里走出来一台新机"
	var parent := get_parent()
	if parent != null:
		FX.smoke_burst(parent, global_position, 3.0)
	# **核心是新的一条满血**（`keep_ratio = false`），且没有 I 立场 ——
	# 用户要求："血条是在扣完之后才变成量产型ν高达的血条"。
	switch_form(to, false, true)
	# 换完之后有一段**自动的上拉升突进**，玩家要等它走完才拿回操作权。
	# 用户要求："量产型ν高达有一段向上的飞升突进，才给玩家自由操作。"
	_begin_escape_dash()
	Audio.play_3d("boom_m", global_position, 0.0)


## 脱出后的向上飞升突进（1.2，用户要求）。
##
## 它是**强制**的：这段时间里 `control_input` / 油门 / 加速全部由机体接管
## （在 `_apply_flight()` 里覆盖，所以玩家这一帧按什么都没用），
## 表现是"核心刚从壳里出来、喷射器全力把我顶上去"，
## 等计时走完再把操作权还给玩家 —— 否则玩家会在一团烟雾里、零速度、被压着打。
func _begin_escape_dash() -> void:
	_escape_timer = ESCAPE_DASH_TIME
	invuln_until = maxf(invuln_until, Game.clock + ESCAPE_DASH_TIME)
	# 初速直接给一个向上的冲量：光靠推力"慢慢加速"看不出"突进"
	var up := Vector3.UP
	fm.velocity = (up * ESCAPE_DASH_SPEED_UP + forward() * ESCAPE_DASH_SPEED_FWD)
	fm.speed = maxf(fm.speed, ESCAPE_DASH_SPEED_FWD)
	fm.sink_speed = 0.0


func escape_dash_active() -> bool:
	return _escape_timer > 0.0


## 变身掩护中：不开火、不吃伤害。
func in_transform() -> bool:
	return _form_swap_timer > 0.0


func is_invulnerable() -> bool:
	if combat_buffs.immune(): return true
	return Game.clock < invuln_until


## ★63-25 军刀撞击豁免：本机现在是否**不结算撞击伤害**。
##
## 窗口 = 「军刀突进中」∪「收招后 `RAM_GUARD_AFTER_SABER` 秒」：
##   - 前半段读 `saber_state == SaberState.CHARGE` —— 这就是需求说的
##     「**从按下鼠标开始**」。⚠️ **必须带这一段**：`_step_saber()` 期间每帧都跑
##     `_check_collisions()`，**突进路上**先撞上也会扣 45，只护「命中之后」是不够的。
##   - 后半段读 `ram_guard_left`（由 `_end_saber()` 置位）。
##
## ⚠️ **不另开一个布尔开关**：`saber_state` 已经是「突进中」的唯一真源
##    （`try_saber()` 设 CHARGE / `_end_saber()` 设 IDLE），再开一个就是第二个写者。
## ⚠️ **只免撞击，不免别的** —— 与 `is_invulnerable()`（变身掩护 / 脱出冲刺，免**一切**）
##    是**两根独立的轴**，不许混用：复用会把那两个已验收的演出改成「挨枪重新掉血」。
func in_ram_guard() -> bool:
	return saber_state == SaberState.CHARGE or ram_guard_left > 0.0


## 只重建"会跟着形态变"的那一层：model_pivot 连同 rig 与模型实例。
## 挂在锚点上的附件（尾焰/夜航灯）不重建，只重新对位 —— 重建就会多出一份。
func _rebuild_visual() -> void:
	# 旧模型连同它身上的白闪一起要被换掉：先把闪光的账结清（否则
	# `_flash_nodes` 里会留着已释放的网格，帧循环里一碰就是报错）。
	_end_model_flash()
	# ⚠️ 骨架/播放器的引用**必须在这里清**：`model_pivot.free()` 之后
	# `_model_skel` 与 `model_anim.player` 都是**已释放节点**，
	# 而 `rig_anchor()` 每帧都在调 —— 留着就是 "Attempt to call function
	# on a null instance"。清了之后由 `_build_visual()` 重新建立。
	_release_model_anim()
	# ⚠️ 要 free 的是 `spin_pivot`（`model_pivot` 现在是它的子节点）——
	# free `model_pivot` 只会摘掉视觉层的一半，`spin_pivot` 连着旧模型留在树上。
	if spin_pivot != null and is_instance_valid(spin_pivot):
		spin_pivot.free()
	spin_pivot = null
	model_pivot = null
	_muzzle_local.clear()
	_build_visual()
	_collect_morph_nodes()
	_reposition_attachments()


func _rebuild_collision() -> void:
	for key in ["Hull", "CannonHull"]:
		var old := get_node_or_null(key)
		if old != null:
			old.free()
	_build_collision()


func _apply_profile_to_flight() -> void:
	fm.configure(profile.player_top_speed(), profile.player_boost_speed())
	fm.thrust_accel_limit = profile.propulsion_g * 9.81
	if profile.propulsion_g > 0.0:
		fm.accel = fm.thrust_accel_limit * 0.65
		fm.ab_accel = fm.thrust_accel_limit
		fm.gravity_energy = 1.0
	else:
		fm.gravity_energy = 5.5
	# 机体自身的转向系数。全局的 170% 增益由 FlightModel.turn_gain 负责，不在这里重复。
	#
	# ⚠️⚠️ **必须是"基值 × 系数"的赋值，不能写成 `fm.pitch_rate *= turn_scale`。**
	# 本函数会被反复调用（出生 / 变形 / 踏板脱落 / ★63-24 局内每拿一张卡），
	# 而 `fm` **从不重建** ⇒ 累乘的话每走一次这条路就多乘一档 `turn_scale`，
	# 演习局拿二十来张卡之后机体直接变陀螺，且**不报任何错**。
	# 基值真源是 `FlightModel.PITCH_RATE_BASE` 那三个常量（见那里的头注）。
	fm.pitch_rate = FlightModel.PITCH_RATE_BASE * profile.turn_scale
	fm.roll_rate = FlightModel.ROLL_RATE_BASE * profile.turn_scale
	fm.yaw_rate = FlightModel.YAW_RATE_BASE * profile.turn_scale
	# 骑踏板中：把踏板的油门响应加成重新贴回去。
	# ⚠️ **必须在这里调**，而不是只在 `configure_pedal()` 里调一次 ——
	# 上面的 `configure()` 会把 accel / ab_accel / brake 按 top_speed 重算，
	# 而阿利宙斯（AI 也会开）**变形时会再走一次这条路**，
	# 只在挂载时加一次的话，它一变形踏板加成就静默消失了。
	# 同时把"转向折扣已贴"的标记清掉：基值刚被重置，折扣要跟着重新贴。
	_pedal_turn_applied = false
	apply_pedal_flight_bonus()


func _build_visual() -> void:
	# ⚠️ `spin_pivot`（轮 33）挂在 `model_pivot` **之上**：转身只写在这一层，
	# 且它的轴是机体的上轴（不含模型前倾）。三条理由见 `dash_spin` 的说明。
	spin_pivot = Node3D.new()
	spin_pivot.name = "SpinPivot"
	add_child(spin_pivot)

	model_pivot = Node3D.new()
	model_pivot.name = "ModelPivot"
	spin_pivot.add_child(model_pivot)

	model_root = Node3D.new()
	model_root.name = "ModelRoot"
	model_pivot.add_child(model_root)

	# 槽位骨架永远存在：真模型只是把可见件换掉，炮口/喷口/手部锚点继续由它提供。
	rig = SuitRig.new()
	rig.name = "SuitRig"
	model_root.add_child(rig)
	rig.build()

	var inst := _instantiate_model()
	if inst != null:
		rig.set_placeholder_visible(false)
		# 模型 native 高约 1 m → 按官方全高缩放。脚底已在 y=0。
		var s := profile.target_height / maxf(profile.model_native_height, 0.001)
		inst.scale = Vector3.ONE * s
		# ---- 朝向修正（`SuitProfile.model_yaw_deg`）----
		#
		# 工程的约定是模型正面朝 −Z，但**导出管线不保证**：
		# 梅萨M01 的模型实际朝 +X（用户实测"左边朝前面了"），
		# 不修的话它整台机侧着飞 —— 而代码不会报任何错。
		#
		# ⚠️ 修正必须加在 **`inst` 的父节点**上，不能直接给 `inst`：
		# `inst.scale` 已经设好了，而 Godot 的 `Node3D.rotation` 与 `scale`
		# 是同一个 `transform` 的两个分量 —— 直接转 `inst` 会与缩放互相干扰
		# （非等比缩放 + 旋转的组合是"看起来转对了、其实被拉斜了"）。
		# 用一个独立的枢轴承载旋转，缩放留给 `inst`，两者互不影响。
		if not is_zero_approx(profile.model_yaw_deg):
			var yaw := Node3D.new()
			yaw.name = "ModelYaw"
			yaw.rotation_degrees = Vector3(0.0, profile.model_yaw_deg, 0.0)
			yaw.add_child(inst)
			model_root.add_child(yaw)
		else:
			model_root.add_child(inst)
		# 骨架缩放到同一全高，槽位锚点才落在真模型对应的位置上
		var rig_h := rig.local_bounds().size.y
		if rig_h > 0.001:
			rig.scale = Vector3.ONE * (profile.target_height / rig_h)
	else:
		push_warning("[FlightBody] 未找到模型 %s，回退占位骨架" % profile.model_path)
		var rig_h := rig.local_bounds().size.y
		if rig_h > 0.001:
			rig.scale = Vector3.ONE * (profile.target_height / rig_h)

	# 注意：量包围盒必须在**施加飞行前倾角之前**做。
	# 前倾 18° 之后，一个 28 m 高、20 m 厚的机体的 Y 向包围盒会变成
	# 28·cos18° + 20·sin18° ≈ 32.8 m —— 看起来像"机体变高了"，
	# 于是碰撞体、炮口位置、全高断言全都跟着错。
	_model_mounts.clear()
	for mount: Node in model_root.find_children("Mount_*", "Marker3D", true, false):
		_model_mounts[str(mount.name).trim_prefix("Mount_")] = mount
	_center_and_measure()
	model_pivot.rotation_degrees = Vector3(flight_pitch_deg, 0.0, 0.0)
	_apply_owner_materials()
	# ⚠️ **必须在 `_collect_muzzles()` 之前** —— 那一步要读 `rig_anchor()`，
	# 而锚点是不是从模型骨架取，由这里的 `_model_skel` 决定。顺序反了就会
	# 用"上一台机体"（或占位骨架）的锚点定炮口，且不报任何错。
	_setup_model_anim(inst)
	if profile.id == SuitProfile.Id.REGZ_CUSTOM:
		_regz_motion = preload("res://scripts/flight/regz_motion.gd").new()
		_regz_motion.install(self)
	if profile.id==SuitProfile.Id.SAZABI:
		if sazabi_systems==null:sazabi_systems=preload("res://scripts/combat/sazabi_systems.gd").new()
		sazabi_systems.install(self)
	if profile.id == SuitProfile.Id.NU_GUNDAM:
		nu_motion=preload("res://scripts/flight/nu_motion.gd").new()
		nu_motion.install(self)
	_collect_muzzles()
	_weapon_emitters=preload("res://scripts/flight/weapon_emitters.gd").new()
	_weapon_emitters.bind(self)
	# ⚠️ ★63-9 B1：**建完必须算一次实际可见性**。
	# `model_root` 是上面 `Node3D.new()` 造的，`visible` 默认 true，
	# 而它是两条判据（`_model_wish` ∧ 非 `rider_hidden`）合成的量。
	# 骑在板上换形态（`set_form()` → `_rebuild_visual()` → 这里）时
	# 不重算，自己那台机体就重新出现在板上、与踏板自带几何叠影。
	# 写在这里（而不是 `_rebuild_visual()`）是因为本函数有**两个**调用点。
	_apply_model_visibility()
	if inst != null:
		var distant_lod := preload("res://scripts/flight/distant_model_lod.gd").new()
		model_root.add_child(distant_lod)
		distant_lod.setup(self)


## 挂在**机体身上**（而不是 ModelPivot 里）的那些附件：加力尾焰、受损黑烟、
## 夜航灯、引擎循环音。它们只在 _ready 里建一次 —— 形态切换时只重新对位，
## 不重建：多建一份引擎循环音就是两个引擎在轰鸣，而且旧的永远停不下来。
func _build_attachments() -> void:
	# ⚠️ 这三处的方向走 `PLUME_AXIS` 而不是字面量 `Vector3(0,0,1)`：机尾那一套本来就是
	# "本地 +Z"，写常量是为了**和逐喷口那条路共用一个真源**（轮 18 加了逐喷口朝向之后，
	# 字面量会变成"第二份 +Z"，改默认轴时容易只改一处）。
	_afterburner_fx = FX.afterburner(self, Vector3.ZERO, PLUME_AXIS, 2.4)
	# ---- 冲刺焰（形态 B）+ 马赫环（2026-09-25，用户要求两种形态做区分）----
	#
	# 与 `_afterburner_fx` 建在同一处、同一个喷口位置，由 `_tick_effects` 二选一。
	# 一次性建好的理由和 `_boost_trail` 一样：形态切换时只重新对位，
	# 不给每个形态各建一套（那会在切换的瞬间留下一串没熄的旧粒子）。
	_dash_fx = FX.afterburner_dash(self, Vector3.ZERO, PLUME_AXIS, 2.4)
	_dash_rings = FX.dash_rings(self, Vector3.ZERO, PLUME_AXIS, 2.4)
	_smoke_fx = FX.damage_smoke(self, Vector3(0, 0, 0), 1.4)
	_build_nav_lights()
	_build_engine_audio()
	# ---- 拖尾光条（批 8）：冲刺 / 超级加速时的连贯光带 ----
	# 一次性建好（top_level 在类里已设，光带跟的是世界坐标不是机尾局部）；
	# 颜色随形态走，在 _reposition_attachments 里刷。
	_boost_trail = BoostTrail.new()
	add_child(_boost_trail)
	_reposition_attachments()


## 把挂在槽位锚点上的附件重新对位（形态换了 → 骨架缩放变了 → 锚点位置也变了）。
func _reposition_attachments() -> void:
	if _afterburner_fx != null and is_instance_valid(_afterburner_fx):
		_afterburner_fx.position = rig_anchor("thruster_L") + Vector3(0, 0, 3.0)
	# 冲刺焰与马赫环**必须与形态 A 完全同点**：它们指的是同一个喷口，
	# 差一点点（比如忘了对位）就会变成"两簇火从不同地方喷出来"。
	if _dash_fx != null and is_instance_valid(_dash_fx):
		_dash_fx.position = rig_anchor("thruster_L") + Vector3(0, 0, 3.0)
	if _dash_rings != null and is_instance_valid(_dash_rings):
		_dash_rings.position = rig_anchor("thruster_L") + Vector3(0, 0, 3.0)
	for item: Dictionary in _nav_lights:
		var mi := item["node"] as MeshInstance3D
		if mi != null and is_instance_valid(mi):
			mi.position = rig_anchor(str(item["slot"]))
	# 拖尾光条颜色跟形态走（巡航/常态/核心的 accent 不同）
	if _boost_trail != null and is_instance_valid(_boost_trail) and profile != null:
		_boost_trail.set_base_color(profile.accent)
	_rebuild_plumes()


## 多喷口特效：`profile.engine_plumes` 里的**每一个喷口**各建一组
##（阿利宙斯巡航 16 个；2026-09-25 起柯西 / 佩涅罗佩各 2 个）。
##
## ## 为什么是"重建"而不是像夜航灯那样只对位
## 夜航灯只对位是因为**引擎循环音**多建一份就是两个引擎在轰鸣、旧的还停不下来
## （见 `_build_attachments` 的说明）。粒子和自发光圆盘没有这个问题：
## 而且各形态的**喷口数量不同**（巡航 16 个、常态 0 个、柯西/佩涅罗佩 2 个），位置又是相对
## `model_bounds` 的百分比 —— 换了形态连包围盒都变了，只能重建。
##
## ## 位置怎么算
## `profile.engine_plumes` 存的是**包围盒归一化分数**，所以直接
## `model_bounds.position + u * model_bounds.size`。和双联炮口同一套口径 ——
## 换模型缩放不会偏，但**换模型形状要重扫喷口**（`tools/nozzle_scan.tscn`）。
func _rebuild_plumes() -> void:
	for item: Dictionary in _plume_fx:
		# ⚠️ **这里必须把 `ab` / `dash` 也列上**：漏掉一个键 = 形态切换时留下
		# 一串没熄的旧粒子（queue_free 没执行到，节点还挂在树上继续喷）。
		# 加键的时候要连着这一行一起加 —— 本函数是唯一的销毁点。
		for k: String in ["fx", "glow", "boost", "ab", "dash"]:
			var n := item.get(k) as Node
			if n != null and is_instance_valid(n):
				# Retire the old form immediately, including the frame before
				# queue_free runs. Otherwise two forms can show jets together.
				if n is Node3D: n.visible = false
				if n is GPUParticles3D: n.emitting = false
				n.queue_free()
	_plume_fx.clear()
	_plume_mat = null
	if profile == null or profile.engine_plumes.is_empty() or model_bounds.size.length() < 0.01:
		return
	_plume_mat = FX.plume_material(profile.engine_plume_color)
	# ⚠️ 每个喷口的粒子数**按喷口数反比给**：`FX.afterburner` 的默认量是给
	# "整机一个尾焰"调的，16 个喷口照搬会把后机身糊成一团白。
	# 尾气用**暗色透明烟雾**（`exhaust_smoke`），不是发光的尾焰 ——
	# 颜色只给喷口的**光晕**与**尾焰**。两者是两种东西，见 `FX.exhaust_smoke()` 的说明。
	# 预算 96 → 160（轮 15「粒子特效数量太少了」，见 `FX` 顶部那段密度表）。
	var per := clampi(int(float(PLUME_SMOKE_BUDGET) / float(profile.engine_plumes.size())), 4, 24)
	# 加力焰同样按喷口数反比给量（用户 2026-09-22 指定：喷气口的"光源"
	# 不再聚在机尾一个点上，分散到各喷口 —— 标注图上红点的位置）。
	# 单点那版的总量是 80（2026-09-25 两轮：24 → 40 → 80，见 `FX.afterburner` 的说明）。
	#
	# ⚠️ **预算 192 → 320 是贴着天花板抬的，不是随手 ×2**：
	# 阿利宙斯巡航态有 **16 个喷口**，历史上量给到 **16 × 34 = 544** 时实测
	# "整块后机身糊成一团白"（见 `FX.afterburner` 函数头那段）。320/16 = 20 每个，
	# 仍然**低于那条翻车线**；而且每个喷口的半径只有 ~1 m
	#（原来是整机一簇 2.4 m），加色叠完远不如原来那一团白。
	var per_boost := clampi(int(float(PLUME_BOOST_BUDGET) / float(profile.engine_plumes.size())), 6, 24)
	# 焰色跟光晕走，但 **alpha 拉满** —— afterburner 的色带用 tint.a 缩放
	# 不透明度，光晕那份 0.42/0.70 的 alpha 会把焰叠得几乎看不见。
	var btint := profile.engine_plume_color
	btint.a = 1.0
	# ---- 形状层这次归谁（见 `PLUME_SHAPE_MAX_NOZZLES` 的说明）----
	#   true  = 喷口数超上限（阿利宙斯巡航 16 个）⇒ 每个口只建一条加力焰，不做 A/B；
	#   false = 1~4 个口（柯西 / 佩涅罗佩）⇒ 每个口建 `ab` + `dash` **两形都齐**。
	var shape_per_nozzle := profile.engine_plumes.size() <= PLUME_SHAPE_MAX_NOZZLES
	var base_radius := profile.engine_plume_radius
	for idx in profile.engine_plumes.size():
		var r := base_radius
		if SuitProfile.is_thunderbolt(profile.id) and _model_mounts.has("plume"+str(idx)):
			r *= float(_model_mounts["plume"+str(idx)].get_meta("plume_radius",1.0))
		var u: Vector3 = profile.engine_plumes[idx]
		var at: Vector3 = rig_anchor("plume"+str(idx)) if (profile.id in [SuitProfile.Id.GP03S,SuitProfile.Id.NU_GUNDAM] or SuitProfile.is_thunderbolt(profile.id)) and anchor_from_model("plume"+str(idx)) else model_bounds.position + u * model_bounds.size
		# ---- 这个口**朝哪边喷**（轮 18）----
		#
		# `profile.plume_dir()` 返回 `Vector3.ZERO` = **这个口没量过朝向**
		#（或 `engine_plume_dirs` 与 `engine_plumes` 长度对不上）⇒ 退回 `PLUME_AXIS`。
		# ⚠️ **默认轴只在这一处定**：数据层不抄一份，否则两个真源迟早分叉 ——
		# 而分叉之后屏幕上只是"某个口喷歪了"，没有任何东西会报错。
		#
		# ⚠️ 长度门槛 `0.25`（= 长度 0.5）是防"退化的方向数据"（全零向量 / 手滑写了 0.01）。
		# 单位向量恒为 1.0，所以 0.5 这个门槛既不会误杀正常值，也拦得住垃圾。
		var dir := profile.plume_dir(idx)
		if dir.length_squared() < 0.25:
			dir = PLUME_AXIS
		else:
			dir = dir.normalized()
		var item := {
			"fx": FX.exhaust_smoke(self, at, dir, r, per),
			"glow": FX.nozzle_glow(self, at, _plume_mat, r * 0.75),
			"boost": null,
			"ab": null,
			"dash": null,
			# 这个口的轴线。**横风形变要按它自己投影**，见 `_tick_plume_bend()`。
			"axis": dir,
			"local_at": at,
		}
		if shape_per_nozzle:
			# 形状层逐喷口：形态 A（普通加力的短粗锥）与形态 B（冲刺的拉丝束）。
			# 两者**永不同时 emitting**，由 `_tick_effects` 二选一。
			# ⚠️ 马赫环**只给单喷口机体建**（`_dash_rings`，挂在机尾那一路）：
			# 环是"束的分段标记"，两个口各来一串就是四串环叠在屏幕上，读不出节拍。
			var ab := FX.afterburner(self, at, dir, r, btint, per_boost)
			var dash := FX.afterburner_dash(self, at, dir, r, btint, per_boost)
			ab.emitting = false
			dash.emitting = false
			item["ab"] = ab
			item["dash"] = dash
		else:
			# 喷口太多：形状层退场，每个口一条加力焰顶替（旧行为）。
			var boost := FX.afterburner(self, at, dir, r * 0.9, btint, per_boost)
			boost.emitting = false
			item["boost"] = boost
		if profile.id == SuitProfile.Id.GP03D:
			# Large MA engines: enlarge the local flame without moving its nozzle anchor.
			for key in ["boost", "ab", "dash"]:
				var jet := item.get(key) as GPUParticles3D
				if jet != null:
					jet.scale = Vector3.ONE * 1.7
					var envelope := jet.get_node_or_null("JetEnvelope") as MeshInstance3D
					if envelope != null: envelope.set_instance_shader_parameter("brightness", 1.8)
		XiPlume.install(self,item,idx)
		PlumeMotion.install(self,item)
		if PenelopePlume.supports(profile): PenelopePlume.configure(item)
		_plume_fx.append(item)
	if model_anim != null and model_anim.player != null:
		if not model_anim.player.mixer_applied.is_connected(_sync_xi_plumes):
			model_anim.player.mixer_applied.connect(_sync_xi_plumes)

func _sync_xi_plumes() -> void:
	for item: Dictionary in _plume_fx:
		XiPlume.sync(self,item)
		PlumeMotion.sync(self,item)


func _instantiate_model() -> Node3D:
	if use_placeholder or placeholder_only or profile == null or profile.model_path == "":
		return null
	if not ResourceLoader.exists(profile.model_path):
		return null
	var res := load(preload("res://scripts/flight/low_texture_models.gd").resolve_model(profile.model_path))
	if res is PackedScene:
		return (res as PackedScene).instantiate() as Node3D
	return null


# ============================================================ 模型骨骼动画的绑定（棒 12 · 2026-09-26）

## 建立"模型自带骨架 + 自带动作"这条链路。由 `_build_visual()` 在**测完包围盒之后**调。
##
## 三件事：
##   ① 找到模型里的 `Skeleton3D` ⇒ `rig_anchor()` 从此可以从**真骨的位姿**取锚点；
##   ② 找到 `AnimationPlayer` 并把 `profile.model_anim_files` 里的动作摘过来；
##   ③ 播待机循环。
##
## 老资产（无骨架、无动画）三件事全部落空 ⇒ 什么都不变。**这不是容错，是设计边界**。
func _setup_model_anim(inst: Node3D) -> void:
	_release_model_anim()
	if inst == null:
		# 没有模型实例（走占位骨架的那条路）⇒ 仍然装一台**哑机**，
		# 让 `model_fsm` 在任何路径下都不为 null（字段说明里的契约）。
		model_anim = null
		model_fsm = ModelAnimFSM.create(null, in_cruise_form())
		return
	for c in inst.find_children("*", "Skeleton3D", true, false):
		_model_skel = c as Skeleton3D
		break
	var extras: Array = profile.model_anim_files if profile != null else []
	model_anim = ModelAnimator.setup(inst, extras)
	if profile != null:
		model_anim.idle_action = profile.model_anim_idle
		model_anim.burst_action = profile.model_anim_burst
		model_anim.burst_cruise_action = profile.model_anim_burst_cruise
		# ★ 巡航形态的三个动作名（N42·二十一 方案 B + N42·二十二 回程过渡）。
		#   空串 = 其余机体/老资产，`ModelAnimFSM` 那边会逐位退回旧行为。
		model_anim.idle_cruise_action = profile.model_anim_idle_cruise
		model_anim.form_on_action = profile.model_anim_form_on
		model_anim.form_off_action = profile.model_anim_form_off
		# ⚠️ **必须重跑**：`_prepare_loops()` 在上一行的 `ModelAnimator.setup()` 里
		#    已经跑过一次，那时这两个名字还是空串 ⇒ `cruise_idle` 拿不到
		#    `LOOP_LINEAR`，症状是巡航待机**播完停在末帧**（不循环、不报错、回归全绿）。
		model_anim.prepare_loops()
		# ★ N56：同样**必须**在这之后 —— 「巡航归位段」要把 `cruise_idle` 的轨
		#   抄进来、再用 `form_on` 的末帧补臂 / 腿 / 躯干，两者都得先有名字。
		#   建不出来的机体（没有巡航待机）这里静默空跑，状态机逐位走旧路径。
		model_anim.prepare_clips()
	AceMotion.install(model_anim, self)
	FlyMotion.install(model_anim, self)
	SaberMotion.install(model_anim, self)
	_gun_pose_ready = GunMotion.install(model_anim, self) if profile.id != SuitProfile.Id.NU_GUNDAM else false
	AceMotion.finish(model_anim, self)
	AceMotion.install_cruise(model_anim, self)
	if not _gun_grip_bind.is_empty():
		model_anim.player.mixer_applied.connect(_sync_gun_grip)
		_sync_gun_grip()
	# 状态机的初始形态取**当下**的变形进度：机体是带着巡航形态入场的，
	# 第一帧就该是巡航该有的样子，不该先闪一下常态再切过去。
	model_fsm = ModelAnimFSM.create(model_anim, in_cruise_form())
	# 巡航形态层：上游 §9.2 说 `burst_cruise` 尾帧 = 「巡航形态的待机」，
	# 巡航姿态就从它的末帧读。老资产（无骨架）在这里自然落空。
	_setup_cruise_form()
	_setup_shoulder_armor()
	if not model_anim.ready:
		# 没有 AnimationPlayer = 这个模型没有自带动作。**不告警** ——
		# 18 个老资产每一个都走这里，吼一声会把日志淹掉。
		return
	# ⚠️ 待机循环由 `ModelAnimFSM.create()` 负责起播（上面那一行），
	# 这里不再重复调 `play_loop` —— 两个地方各播一次会让状态机记 `desyncs`。
	# 顺带量一次锚点跟随的基准，供 HUD/测试读（见 `anchor_follow_error()`）。
	_anchor_probe_cache.clear()


func _sync_gun_grip() -> void:
	if _model_skel == null or _gun_grip_bind.is_empty(): return
	var hand := _model_skel.get_bone_global_pose(_bone_index("Hand.R"))
	for bone: int in _gun_grip_bind:
		var wanted: Transform3D = hand * _gun_grip_bind[bone]
		var parent := _model_skel.get_bone_parent(bone)
		var local := _model_skel.get_bone_global_pose(parent).affine_inverse() * wanted
		_model_skel.set_bone_pose_position(bone,local.origin)
		_model_skel.set_bone_pose_rotation(bone,local.basis.orthonormalized().get_rotation_quaternion())
		_model_skel.set_bone_pose_scale(bone,local.basis.get_scale())


func _setup_shoulder_armor() -> void:
	if profile == null or profile.id != SuitProfile.Id.GUSTAV00 or _model_skel == null:
		return
	var shoulder := _model_skel.find_bone("Shoulder.L")
	if shoulder < 0: return
	var shoulder_rest := _model_skel.get_bone_global_rest(shoulder)
	for name in ["Shield.L", "shield_L"]:
		var bone := _model_skel.find_bone(name)
		if bone >= 0:
			_shoulder_armor_bind[bone] = shoulder_rest.affine_inverse() * _model_skel.get_bone_global_rest(bone)
	if model_anim != null and model_anim.player != null and not _shoulder_armor_bind.is_empty():
		model_anim.player.mixer_applied.connect(_sync_shoulder_armor)
	_sync_shoulder_armor()


func _sync_shoulder_armor() -> void:
	if _model_skel == null or _shoulder_armor_bind.is_empty(): return
	var shoulder := _model_skel.find_bone("Shoulder.L")
	var shoulder_pose := _model_skel.get_bone_global_pose(shoulder)
	for bone: int in _shoulder_armor_bind:
		var wanted: Transform3D = shoulder_pose * _shoulder_armor_bind[bone]
		var parent := _model_skel.get_bone_parent(bone)
		var local := _model_skel.get_bone_global_pose(parent).affine_inverse() * wanted
		_model_skel.set_bone_pose_position(bone,local.origin)
		_model_skel.set_bone_pose_rotation(bone,local.basis.orthonormalized().get_rotation_quaternion())
		_model_skel.set_bone_pose_scale(bone,local.basis.get_scale())


## 清掉引用。**必须在 `model_pivot.free()` 之前调** —— 否则 `_model_skel`
## 与 `model_anim.player` 会指向已释放的节点，而 `rig_anchor()` 每帧都在调。
##
## ⚠️ 这里装的是**哑机**而不是留 `null`：`model_fsm` 的契约是"永不为 null"
##（见字段说明）。留 null 的话，任何在 `_build_visual()` 早退路径上读它的代码都会崩。
func _release_model_anim() -> void:
	_weapon_emitters=null
	_regz_motion = null
	if model_anim != null and model_anim.player != null \
			and model_anim.player.mixer_applied.is_connected(_sync_gun_grip):
		model_anim.player.mixer_applied.disconnect(_sync_gun_grip)
	_gun_grip_bind.clear()
	_gun_pose_ready = false
	_gun_recoil_clock = 1.0
	if model_anim != null and model_anim.player != null \
			and model_anim.player.mixer_applied.is_connected(_sync_shoulder_armor):
		model_anim.player.mixer_applied.disconnect(_sync_shoulder_armor)
	_shoulder_armor_bind.clear()
	if model_anim != null and model_anim.player != null \
			and model_anim.player.mixer_applied.is_connected(_sync_blade_anchor):
		model_anim.player.mixer_applied.disconnect(_sync_blade_anchor)
	# ⚠️ 摘信号必须在 `model_anim = null` **之前** —— 之后就拿不到 `player` 了，
	# 那个回调会永远挂在已销毁机体的播放器上。
	if model_anim != null and model_anim.player != null \
			and model_anim.player.mixer_applied.is_connected(_weld_form_bones):
		model_anim.player.mixer_applied.disconnect(_weld_form_bones)
	model_anim = null
	model_fsm = ModelAnimFSM.create(null)
	# ⚠️ 形态层是挂在骨架**下面**的节点，随 `model_pivot.free()` 一起走。
	# 这里只清引用 —— 别 `free()` 它，那会在 free 父节点的途中触发
	# "Parent node is busy setting up children" 一类的报错。
	_cruise_form = null
	_form_curve = null
	# ⚠️ 帧末焊的载体只是 `RefCounted`，它**裸持骨架引用** —— 必须显式解绑，
	# 否则 `model_pivot.free()` 之后那个引用就是野引用。
	#（信号已在函数开头摘掉 —— 那必须在 `model_anim = null` 之前做。）
	if _form_weld != null:
		_form_weld.detach()
		_form_weld = null
	_model_skel = null
	_bone_idx.clear()
	_anchor_probe_cache.clear()
	# 重建视觉会换掉 `model_root` ⇒ 形态网格要重扫（`_collect_morph_nodes()` 的理由）。
	_morph_nodes.clear()
	_morph_collected = false


## 建「巡航形态层」并挂到骨架的求值链上（`cruise_on` 的骨骼版）。
##
## ★ **N42·二十一 起对柯西不再生效**：形态改由动作（`cruise_idle` / `form_on`）表达，
## 本函数在第 4 道判据上早退。保留整条实现是为了其余机体与**回滚**
##（清空 `SuitProfile.model_anim_idle_cruise` 即自动回到这条路）。
##
## 三条前置缺一不可，所以老资产与"只有常态动作"的模型都自然落空 ⇒ 空操作：
##   ① 模型自带骨架（`_model_skel`）—— 形态层的载体；
##   ② 有待机动作（常态基准）；
##   ③ 有**巡航版**发射动作（巡航姿态基准，即上游说的"巡航待机"）。
func _setup_cruise_form() -> void:
	_cruise_form = null
	_form_curve = null
	if _model_skel == null or model_anim == null or not model_anim.ready:
		return
	# ★★ N42·二十一 方案 B（2026-09-27）：形态改由**动作**表达 ⇒ 形态层让位。
	#
	# 两套载体（`SkeletonModifier3D` 与 `AnimationPlayer`）作用于**同一批骨**，
	# 而实机判决证明后者每帧覆盖前者（回调每帧在跑、角度算对、屏幕纹丝不动）
	# ⇒ 同时开着只会让形态层白跑一层求值。
	#
	# 只要 `cruise_idle` 真的挂上了就早退；挂不上（文件缺失 / 名字写错）⇒ 自然落到
	# 下面的形态层 —— **退化成改动前的行为**，这是个安全的回退，不是错误。
	#
	# ⚠️ 早退后 `_form_curve` / `_cruise_form` 保持 `null`：`_tick_cruise_morph()`
	# 对这两个字段本来就有判空（"曲线层 / 两点层"二选一的写法），无需改动。
	#
	# ★★★ 轮 42（2026-09-28）：**光让位给动作是不够的**，实测把那个洞找出来了。
	#
	# ① `tools/probe_wing_tracks.gd`：`dash_*` / `fly_*` / `turn_*` 这 10 段方向动作
	#    **每一段都带 8 根形态骨的轨道**、姿态 = 常态（命中的骨-动作对 **80 / 80**）。
	#    于是**一按方向键就离开 `cruise_idle`**，背后的翼立刻被写回「关」
	#    —— 用户报的「辅助飞行模式下按哪个键都会关上飞行翼」正是这个。
	# ② `tools/probe_form_layer_vs_anim.gd`：把形态层加回来**也没用** ——
	#    `morph = 1` 时帧末读到的仍是常态（141.30°）；**把那 8 条轨道
	#    `track_set_enabled(false)` 关掉，读数一模一样** ⇒ 动画求值链在形态层之后
	#    **无条件重写**这批骨。形态层这条路是死的，不是参数没调对。
	# ③ `tools/probe_form_weld_timing.gd`：`_process()` 里写 ✗ ／ `call_deferred()` ✗；
	#    但探针那条「`process_frame` 之后 ✓」是**假绿**（它只读局部 pose）。
	#    真机出图 `tools/form_weld_shot.gd` 把真相量出来了：「焊接开」与「焊接关」
	#    两格的投影面积**逐位相同（10.66%）** ⇒ 屏幕上根本没展开过。
	#    ⇒ 唯一可靠的落点是 **`AnimationMixer.mixer_applied`**（动画求值刚写完那一刻）。
	#
	# ⇒ 这一档的形态载体换成 `FormWeld`（见 `_setup_form_weld()`）：
	#   动作照播（姿势该动还动），但形态骨每帧被焊在 `cruise_morph` 指定的姿态上。
	if model_anim.idle_cruise_action != "" and model_anim.has(model_anim.idle_cruise_action):
		_setup_form_weld()
		return
	var idle := model_anim.idle_action
	var cruise_clip := model_anim.burst_cruise_action
	if idle == "" or cruise_clip == "":
		return
	if not model_anim.has(idle) or not model_anim.has(cruise_clip):
		return
	# 常态基准取待机**首帧**：实测 `fly` 首帧与 `burst_cruise` 首帧同姿态
	#（差 0.0000 m），所以这个基准是干净的 —— 用它算出来的角度差**纯粹**是形态差。
	var normal := model_anim.rotations_at(idle, 0.0)
	var cruise := model_anim.rotations_at(cruise_clip)
	if normal.is_empty() or cruise.is_empty():
		return
	# ---- 通路①（优先）：形态**曲线层**（N42·十三）----
	#
	# `profile.model_form_curve` 是**可选**字段；老资产是空串 ⇒ 直接跳过。
	# 曲线层自己做**端点自检**（曲线首/末帧必须落在本机的常态/巡航基准上）
	# 与形态骨筛选；任一条不过就返回 null ⇒ 自然落到下面的两点层。
	if profile != null and profile.model_form_curve != "":
		var curve := model_anim.load_curve_from(preload("res://scripts/flight/low_texture_models.gd").resolve_model(profile.model_form_curve),
				_form_bone_candidates(cruise))
		_form_curve = FormCurveModifier.setup(_model_skel, normal, cruise, curve)
		if _form_curve != null:
			_model_skel.add_child(_form_curve)
			# 机体可能带着形态入场（例如生成在巡航中），第一帧就该是对的样子。
			_form_curve.morph = cruise_morph
			return
	# ---- 通路②（回退）：两点线性 slerp ----
	_cruise_form = CruiseFormModifier.setup(_model_skel, normal, cruise)
	if _cruise_form == null:
		# 挑不出形态骨 ⇒ 这个模型的巡航形态不靠骨骼差表达（或根本没有）。
		# **不告警**：18 个老资产 + 任何单形态模型都会走这里。
		return
	_model_skel.add_child(_cruise_form)
	# 机体可能带着形态入场（例如生成在巡航中），第一帧就该是对的样子。
	_cruise_form.morph = cruise_morph


## 建「帧末焊」形态载体（轮 42）。**只对形态由动作表达的机体**（柯西）调用。
##
## 基准取法：常态 = `idle_action` 的**首帧**、巡航 = `idle_cruise_action` 的**末帧**。
## 为什么巡航取末帧：它是循环待机，`cruise_morph >= 0.5` 时 FSM 播的就是它，
## 末帧才是稳定的巡航姿态（首帧还在从常态过渡）。
##
## ⚠️ 这里**只借** `CruiseFormModifier.setup()` 的形态骨筛选（`min_deg` 判据只此一处，
## 两处判据迟早打架），**不** `add_child` —— 它作为 `SkeletonModifier3D` 的那条路
## 已被实测证否（见 `_setup_cruise_form()` 早退处那段）。
func _setup_form_weld() -> void:
	if PenelopeMovieMotion.supports(self):
		_form_weld = PenelopeMovieMotion.bind(self)
		if not model_anim.player.mixer_applied.is_connected(_weld_form_bones):
			model_anim.player.mixer_applied.connect(_weld_form_bones)
		_weld_form_bones()
		return
	if XiMovieMotion.supports(self):
		_form_weld = XiMovieMotion.bind(self)
		if not model_anim.player.mixer_applied.is_connected(_weld_form_bones):
			model_anim.player.mixer_applied.connect(_weld_form_bones)
		_weld_form_bones()
		return
	if _model_skel == null or model_anim == null:
		return
	var idle := model_anim.idle_action
	var idle_cruise := model_anim.idle_cruise_action
	if idle == "" or idle_cruise == "":
		return
	var n0 := model_anim.rotations_at(idle, 0.0)
	var c1 := model_anim.rotations_at(idle_cruise)
	if n0.is_empty() or c1.is_empty():
		return
	# ★★ N52：**位置基准与旋转基准同一次取、同一来源** —— 形态表达的另一半。
	#
	# 为什么不能只取旋转：这 8 根骨展平时**主要靠平移**（`RearHang.R` 常态→巡航
	# 两端位置差 **1.1607**（模型本地）≈ 118% 身高，世界里 33.1 单位）。
	# 只焊旋转 ⇒ 世界变换 = **旋转取焊缝 ＋ 位移取动画** ⇒ 一按方向键，位置被
	# `dash_*` / `fly_*`（它们的 translation 轨**恒定写在常态位置**）写回常态，
	# 翼板「以展开的角度贴回机体」= 用户报的「按哪个键都会关上飞行翼」。
	#
	# ⚠️ 两侧取样的**时点必须与上面两行逐字对应**（常态取 `idle` 首帧 `0.0`、
	# 巡航取 `idle_cruise` 末帧）—— 旋转与位置用不同时点，就是
	#「两处判据打架」（N42·十二）。这条由 `ModelAnimator._keys_at()` 统一口径保证。
	var n0p := model_anim.locations_at(idle, 0.0)
	var c1p := model_anim.locations_at(idle_cruise)
	# ---- ★ 常态位置基准：主模型自带的 `fly` **不带**那 8 根骨的位置轨 ----
	#
	# 实测（`tools/_n52_diag.gd`）：`fly` 的轨道类型分布 = **POS 1 / ROT 26**，
	# 唯一那条 POS 轨还不在形态骨上 ⇒ `locations_at(idle)` 对 8 根形态骨**全缺**。
	# 而 `cruise_idle` 是 POS 14 / ROT 19、8 根齐全。
	#
	# ★ 但"动画不写位置轨"这件事**本身就是语义**：那些骨的位置停在 **rest**。
	#   逐位旁证：`fly` 在播时 `RearHang.R` 的局部位置读
	#   `(-0.1414, -0.2820, -0.0594)`，与 `assets/models/xi/anim/xi_form_on.glb`
	#   首帧（= 作者定义的"常态"）**完全相同**。
	#
	# ⚠️ 为什么不去别的"常态动作"（`dash_*` / `fly_*`）取位置：那会让**旋转基准与
	#   位置基准来自不同动作** —— 正是「两处判据」（N42·十二）。用 rest 则是同一个
	#   语义来源（`fly` 里没写 ⇒ 就是 rest）。
	#
	# ⚠️ 补全的**执行点在 `CruiseFormModifier.setup()` 里**（两张位置表都补，缺键 →
	#   `get_bone_rest().origin`）—— 本函数**只负责取原始两表**，不在两处各写一份
	#   兜底逻辑（两处兜底迟早漂移，同「两处判据」）。`Shoulder.L` 正是靠那条兜底
	#   才没把整张位置表顶掉（见 `CruiseFormModifier.setup()` 循环里的注释）。
	#
	# ★ 这条兜底还顺手修掉一个既有毛病：`cruise_idle` 写位置、`fly` 不写
	#   ⇒ 退出巡航时位置**没人写回**（轮 42 文件头记的"morph 回 0 时没有任何东西
	#   能把它拉回常态"）。位置通路一旦启用，焊缝每帧把两端都钉住，这个洞同时补上。
	var pick := CruiseFormModifier.setup(_model_skel, n0, c1, 0.5, n0p, c1p)
	# ---- ★★ N55：**祖先闭包**的两套基准 ----
	#
	# 闭包本身（哪几根祖先要纳入）由 `FormWeld.setup()` 从**骨架父链**算出来 ——
	# 本函数只负责**给基准**。
	#
	# ## 为什么巡航侧的祖先基准**不能**取 `idle_cruise_action`（本轮实测的转折点）
	#
	# 离线读 `.glb` 时 `cruise_idle` 带全部 51 根骨的轨道，于是「巡航父链姿态 =
	# `cruise_idle` 末帧」。**但引擎里 `cruise_idle` 只剩 19 条旋转轨**
	#（Godot 的 glTF 导入会删掉常量轨）⇒ `Chest` / `Spine` / `Hips` / `Shoulder.R`
	# 在那里**根本没有轨道** ⇒ `rotations_at(idle_cruise)` 里没有它们，读到的值是
	# **上一段动作留下的残留**（实测：紧跟 `fly` 之后读，读到的是**常态**值 6.07/5.73/18.09）。
	# 后果很隐蔽：拿它当基准会**把症状读没**（探针第一版因此把「26% 上抬」读成 2.5%）。
	#
	# ⇒ 巡航侧改取 **`form_on` 末帧**：它在引擎里 36 条旋转轨、5 根祖先全在，
	#   且实测与 `cruise_idle` 末帧、`form_off` 首帧**两两相差 ≤ 0.04°** ⇒ **同一个姿态**,
	#   只是走了**一条引擎里还留着轨道的路**。而且这正是**游戏里**建立巡航父链姿态的那条路
	#（按住 Shift ⇒ `form_on` 播完 ⇒ 父链留在巡航位 ⇒ `cruise_idle` 循环时不再动它）。
	#
	# ⚠️ 下面那段「两处一致性」自检是「两处判据打架」（N42·十二）的守卫：
	#   能在两处都读到的骨，两处必须一致；不一致就**告警**，不静默选一边。
	var fa := model_anim.form_on_action
	var anc_c := model_anim.rotations_at(fa) if fa != "" else {}
	var anc_cp := model_anim.locations_at(fa) if fa != "" else {}
	if anc_c.is_empty():
		# 没有形态过渡动作 ⇒ 拿不到可靠的巡航父链基准 ⇒ **不建祖先闭包**（退回改动前行为），
		# 并如实告警（否则就是"看着修了、其实没修"）。
		push_warning("FormWeld: 没有 `form_on`（= `profile.model_anim_form_on`）⇒ 祖先闭包基准缺失，"
			+ "退回只焊形态骨 ⇒ 巡航态下父链漂移仍在")
	if not anc_c.is_empty() and not c1.is_empty():
		var mx_cross := 0.0
		var who := ""
		for b: String in anc_c.keys():
			if not c1.has(b):
				continue
			var dq := rad_to_deg((anc_c[b] as Quaternion).angle_to(c1[b] as Quaternion))
			if dq > mx_cross:
				mx_cross = dq
				who = b
		if mx_cross > 0.5:
			push_warning("FormWeld: 巡航基准两处不一致（`%s` 末帧 vs `%s` 末帧：`%s` 差 %.2f°）"
				% [fa, idle_cruise, who, mx_cross])
	_form_weld = FormWeld.setup(_model_skel, pick, FormWeld.WELD_MIN_DEG,
		n0, anc_c, n0p, anc_cp)
	if _form_weld != null and _form_weld.has_ancestors():
		print("[N55] 祖先闭包 %d 根：%s（形态骨 %d 根）"
			% [_form_weld.ancestor_count(), str(_form_weld.ancestor_bones()),
				_form_weld.form_bone_count()])
	if _form_weld != null and not _form_weld.has_positions():
		# 位置通路没建起来 ⇒ 形态仍是「只焊一半」，**如实告警**别静默。
		push_warning("FormWeld: 位置基准不可用（n0p=%d c1p=%d）⇒ 只焊旋转，翼板位置不受管"
			% [n0p.size(), c1p.size()])
	if _form_weld == null:
		# 挑不出形态骨 ⇒ 这台机的形态不靠骨骼差表达。**不告警**。
		return
	# ★ 挂在 **`AnimationMixer.mixer_applied` 信号**上 —— 那是引擎在「动画求值刚写完」
	# 那一刻发的信号，写得进去、且一定在渲染之前生效。用 `AnimationPlayer` 自己的
	# 钩子而不是任何「帧阶段」，与帧率、树顺序、物理/空闲阶段全都无关。
	#
	# ⚠️ 别改成 `SceneTree.process_frame`：那条路**只让「局部 pose 读数」变好，
	# 渲染用的仍是动画的姿态** —— 真机出图实测「按前进 + 焊接开」与
	# 「按前进 + 焊接关」的投影面积**逐位相同（都是 10.66%）**，屏幕上翼根本没展开。
	# 而探针只读局部 pose，会给出**假绿**。详见 `FormWeld` 文件头「踩过的坑」。
	var pl := model_anim.player if model_anim != null else null
	if pl != null and not pl.mixer_applied.is_connected(_weld_form_bones):
		pl.mixer_applied.connect(_weld_form_bones)
	# 机体可能带着形态入场（例如生成在巡航中），第一帧就该是对的样子。
	_weld_form_bones()


## **帧末**把形态骨焊到 `cruise_morph` 指定的姿态。
##
## ⚠️ 由 `AnimationMixer.mixer_applied` 信号驱动（见 `_setup_form_weld()`），
## **不是**本类的 `_process()`，也不是 `SceneTree.process_frame`：
##   · 前者太早 —— 父节点的 `_process` 早于子节点的 `AnimationPlayer`（实测）；
##   · 后者有个更隐蔽的陷阱 —— 它能让**局部 pose 的读数**变好，
##     但**渲染**用的仍是动画的姿态 ⇒ 探针只读局部 pose 时会给出**假绿**
##     （轮 42 真机出图实测，见 `FormWeld` 文件头「踩过的坑」）。
##
## ⚠️ `cruise_morph == 0` 时**也写**（写常态）：本载体是这几根骨的**唯一**写入者，
## "不写"等于把它们丢给上一个动作 ⇒ 退出巡航时翼收不回去。
## ★ N55：**祖先骨不适用上一条** —— 它们有主人（在播的动作），只在**接管窗**里写。
## 见 `FormWeld.weld()` 的 `ancestors_ok` 与「门控①/②/②b」。
func _weld_form_bones() -> void:
	if _form_weld != null:
		_form_weld.weld(cruise_morph, not _in_form_window() and _ancestors_armed() and not AceMotion.cruise_owns_ancestors(self))


## ★ N55 门控②：现在是不是「形态过渡动作」（`form_on` / `form_off`）在播的窗口。
##
## 该窗口内祖先骨**退位**给作者动画 —— 那两段本来就是「常态 ↔ 巡航」的完整过渡
##（51 轨全骨），焊缝再去覆盖它就是「两条时间轴不同步」（N52·R2）搬到躯干上。
##
## ⚠️ 只读 `model_fsm.state`（`State.FORM`），**不读 `model_anim.current`**：
## 状态机才是"这段动作有没有播完"的真源（N46 约束④：状态推进只有一个入口）。
func _in_form_window() -> bool:
	return model_fsm != null and model_fsm.state == ModelAnimFSM.State.FORM


## ★★ N55 门控②b：祖先骨的**接管窗** = 「形态真的停在巡航稳态」那一档（`morph ≥ 0.999`）。
##
## ## 为什么只有「不在 `State.FORM` 窗口内」这条**不够**（本轮实测的第二个转折点）
##
## 焊缝会在 `morph` 刚离开 0 的**第一帧**就开始写祖先（那时 FSM 还是 `IDLE`、播的是 `fly`），
## 而 FSM 要等 `morph ≥ 0.5` 才进 `State.FORM` 播 `form_on`，且 `form_on` 是
## **从自己的第 0 帧（= 常态）起手** —— 于是焊缝刚把躯干推到 **52% 巡航**，
## 交接那一帧就被作者动画**弹回常态**。
##
## **实测（`tools/probe_xi_wing_world.gd --form-trace`，`_relay/n55_s3_trace.log`）**：
##
## | 边界 | 相邻帧形态骨位移 | 祖先位移 | 稳态对照 |
## |---|---|---|---|
## | `on` 第 13 帧（**进** FORM，morph 0.5185） | **0.08925** | 0.04692 | 0.0407 / 0.0036 |
## | `off` 第 14 帧（**进** FORM，morph 0.4444） | **0.08640** | 0.04706 | 0.0410 / 0.0036 |
##
## ⇒ 一跳 ≈ 2.2 倍稳态位移、祖先位移 13 倍（那正是"上抬"的方向）。
##
## ## 修法 = 接管窗收紧，而不是把门槛搬来搬去
##
## 展开 / 收起**全过程**交给作者动画（它本来就是为那段设计的），
## 只有「**展开后停住**」才由焊缝把躯干锁死 —— 那正是用户要的那一档
##（"展开之后…不要有飞翼位置的改变"）。于是：
##
## | 场合 | `morph` | FSM | 祖先归谁 |
## |---|---|---|---|
## | 展开中 / 收起中 | 0 < m < 1 | `IDLE` / `FORM` | **作者动画**（无跳变） |
## | **巡航稳态** | = 1 | `IDLE` / `DASH` / `TURN` / `ACTION` | **焊缝锁死** ← 用户要的 |
## | 左右转身收翼 | → 0 | 任意 | 作者动画（用户允许改变） |
##
## ⚠️ 门槛必须留**容差**（`0.999` 而不是 `1.0`）：`move_toward()` 结束时理论上恰好 1.0，
## 但若哪天它停在 0.9999996，`>= 1.0` 会让焊缝**永远不接管** ⇒ 整个修复**静默失效**
##（形态看着正常、只是会飘 —— 最坏的那种）。这条由 §2 主判据守着：
## 它把 `cruise_morph` 直接设成 `1.0`，若接管窗判定写错，§2 立刻从 0.0000 变回 0.2547。
func _ancestors_armed() -> bool:
	return cruise_morph >= 0.999


## 交给 `ModelAnimator.load_curve_from()` 的**候选骨名** = 巡航基准里的全部骨。
##
## ★ 为什么**先给全部、不在这里筛**：筛形态骨的判据只应存在于**一处**
##（`FormCurveModifier.setup()`，与 `CruiseFormModifier` 逐字同判据）。
## 在这里再筛一遍就有了两处判据 —— 迟早会不一致，而"两处判据打架"
## 正是 N42·十二「半升级」静默故障的成因。
##
## 代价可忽略：`load_curve_from()` 是按骨名查轨道，50 根骨的线性扫描在
## 建体时**只跑一次**。
func _form_bone_candidates(cruise: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for b: String in cruise.keys():
		out.append(b)
	return out


## 每帧推一下状态机：宣告形态、再让它推进。
##
## **这是动作切换的唯一驱动点**。两件事的顺序有意义：
##   ① `set_form()` 先宣告"现在该是什么形态"（它只记目标，不切动作）；
##   ② `tick()` 才真的推进 —— 发射途中挂起的形态切换也在这一步落地。
##
## ⚠️ `model_fsm` 不会为 null（`create()` 契约），但仍判一下：
## `_build_visual()` 与 `_tick_effects()` 之间的时序不保证。
func _tick_model_anim(delta: float) -> void:
	if model_fsm == null:
		return
	var in_cruise := in_cruise_form()
	if PenelopePlume.supports(profile) and is_player:
		in_cruise = penelope_cruise_enabled and _dash_spin_t <= 0.0
	model_fsm.set_form(in_cruise)
	# 冲刺八向（N46）：宿主只**报当前事实**（`""` = 不在冲刺），切不切由状态机按
	# 自己的优先级定（见 `ModelAnimFSM.tick()` 的分支顺序）。空串恒安全。
	#
	# Xi has cruise-based clips: preserve its dash input and let the FSM select
	# the matching family. Suits without those clips retain the original gate.
	model_fsm.set_dash(_dash_anim_dir if not in_cruise or AceMotion.cruise_ready(self) else "")
	# 常态平飞八向（N49 · 2026-09-28）：同一套"只报事实"。两族的优先级由状态机定
	#（冲刺族在前、平飞族在后，见 `ModelAnimFSM.State.DASH`）—— 这里不必也不该替它判。
	#
	# ★★ N56：**巡航形态下抑制这一族**。它们与常态共用同一张八向表（N49「一族动作、
	# 一个态」），而 `fly_*` 是**常态基准**的姿态 ⇒ 巡航时按 WASD 会把整条手臂从巡航位
	# 带到常态持枪位（`UpperArm.R` +89.53°、枪口离胸口 +0.2295 m）= 用户报的"举枪"，
	# 双腿一并被带走 25.92 ~ 32.77%。
	#   ⛔ 不是"某个机体的特例"：抑制只发生在**巡航形态**，而巡航形态本身只有配了
	#      `cruise_morph` + 巡航待机的机体才有 ⇒ 其余机体此处 `in_cruise` 恒 `false`，
	#      送进去的还是原来那个值，逐位不变。
	model_fsm.set_fly_dir("" if in_cruise else _fly_dir8())
	# 姿态微调（N49）：同样是"只报事实"。宿主的死区/主轴筛选在 `_turn_dir()` 里，
	# 状态机只负责"这一轴有没有对应动作、优先级排第几"。
	# ★ N56：巡航形态下**一起抑制**（用户裁决）。`turn_*` 与 `fly_*` 是同一个病灶 ——
	# 它们同样是常态基准的姿态，实测会把腿带跑 25.92%。
	model_fsm.set_turn("" if in_cruise else _turn_dir())
	# ★ N56 收枪窗口："现在允许收枪了吗"—— 宿主只报事实，判定在 `stow_idle` 里。
	model_fsm.set_can_stow(in_cruise and stow_idle >= STOW_DELAY)
	model_fsm.tick(delta)


## 现在算不算"巡航形态"（`cruise_morph` 过了阈值）。
##
## ⚠️ **阈值只有这一个真源。** 改之前 `cruise_morph >= 0.5` 这个字面量在**四处**
## 各写了一遍（建状态机 ×2 / 每帧宣告形态 / 选全弹发射版本），它们必须永远同值 ——
## 一旦谁为了调手感只改其中一处，就会出现"状态机认为是巡航、全弹发射却选常态动作"
## 这种**两块各自都对、合起来不对**的半升级故障，而且两边都不报错。
## 同 N42·十二「两处判据打架」的教训。
func in_cruise_form() -> bool:
	return cruise_morph >= CRUISE_FORM_THRESHOLD


## 让模型播一个**战斗一次性动作**（`shoot` / `slash` / `shield` / `trans_*`）。
## 返回 false = 这个模型没有动作 / 没有这个名字。（N49 起改走状态机）
##
## ## 为什么从"旁路"改成"走状态机"
##
## 原来它直调底层播放器 ⇒ 状态机在下一 `tick()` 发现"实际在播的和它以为的不是同一个"，
## 记一次 `desyncs` 并把 `_action` 同步过去 —— **能用，但状态机对这段动作完全不知情**：
## 它会继续按待机 / 冲刺的逻辑往同一批骨上写，**两套写入打架**（谁最后写谁赢，
## 而"最后写"的次序取决于添加顺序，属于最难查的那类）。
## 现在交给 `ModelAnimFSM.request_action()`（新增的 `ACTION` 态）：独占、播完自动回待机、
## 且与 BURST 同级优先。
##
## ⚠️ 空名 / 不存在的名字都安全返回 `false`（哑机与老资产一律 `false`）。
##
## ## `can_stow`（N56）
##
## 这一段播完后**允不允许收枪**（倒放 ＋ 归位）。默认 `false` ⇒ 既有调用点逐位不变
##（军刀 / 举盾 / 变形动作都不会被收枪流程接管）。
##
## ★ "这一下是不是火器"是**玩法层**的事实（`player_controller` 的
## `_shoot_rifle_now()` 知道），所以由**调用方**声明，不在这里按动作名猜 ——
## 状态机里写死 `"shoot"` 就等于把玩法判断埋进表现层。
func play_model_action(action_name: String, can_stow := false) -> bool:
	if model_fsm == null:
		return false
	return model_fsm.request_action(action_name, can_stow)


## 全弹发射该播哪一版：巡航形态（`cruise_morph >= 0.5`）播巡航版，否则播常态版。
## 没有动作（老资产）就返回 ""。
##
## ⚠️ 这两段动作的**形态基准不同**（`burst` 起于常态待机、`burst_cruise` 起于
## 巡航待机），选错会在发射前看到一次形态跳变。取舍依据是 `cruise_morph`。
##
## 从棒 12 起，真正的选择逻辑在 `ModelAnimFSM.burst_action_for_form()`（单一真相源），
## 这里只是**转发**，保留旧签名给探针与既有调用点用。
func full_burst_action() -> String:
	if model_fsm == null:
		return ""
	var f: ModelAnimFSM.Form = ModelAnimFSM.Form.NORMAL
	if in_cruise_form():
		f = ModelAnimFSM.Form.CRUISE
	return model_fsm.burst_action_for_form(f)


## 全弹发射时调。由 `PlayerController.fire_full_salvo()` 调用。
##
## 从棒 12 起交给状态机：它负责"按形态选版本 / 锁住不被形态切换打断 / 播完回待机"。
## 发射途中再喊一次会**重播**（冷却 20 s 打一轮的真实语义），
## 但同一瞬间连点会被忽略，免得动作被反复怼回第 0 帧。
func play_full_burst() -> bool:
	if model_fsm == null:
		return false
	return model_fsm.request_burst()


## 锚点跟随的实测误差（米）：`rig_anchor(slot)` 反算成世界坐标后，
## 与"模型骨架里同名骨的**可见世界位置**"比。两者现在走的是同一条路，
## 所以这个数应当 ≈ 0；它存在的意义是**在换模型/换绑定之后还能被量到**。
##
## 只给探针与测试用 —— `_anchor_probe_cache` 是个 1 项缓存，不会每帧算。
var _anchor_probe_cache := {}

func anchor_follow_error(slot_name: String) -> float:
	if _anchor_probe_cache.has(slot_name):
		return _anchor_probe_cache[slot_name]
	# ⚠️ 转身期间这个数是**故意不为 0** 的（`rig_anchor()` 剔掉了转身，而骨位姿含转身）
	# ⇒ 直接报 −1。否则探针 / 测试会把"设计如此"读成"锚点漂了"。
	if dash_spin != 0.0:
		return -1.0
	var err := -1.0
	var b := _bone_index(slot_name)
	if _model_skel != null and b >= 0:
		var bone_world: Vector3 = (_model_skel.global_transform
			* _model_skel.get_bone_global_pose(b)).origin
		err = (global_transform * rig_anchor(slot_name)).distance_to(bone_world)
	_anchor_probe_cache[slot_name] = err
	return err


## 量出可见网格（真模型；占位骨架已隐藏）在 FlightBody 空间的包围盒，
## 把"从底往上 55% 处"移到原点，并记下包围盒。
func _center_and_measure() -> void:
	var box := _measure_visible_meshes()
	if box.size.length_squared() <= 0.0001:
		box = AABB(Vector3(-12, 0, -10), Vector3(24, 32, 20))
	var offset := box.get_center()
	offset.y = box.position.y + box.size.y * 0.55
	model_root.position = -offset
	model_bounds = AABB(box.position - offset, box.size)


func _measure_visible_meshes() -> AABB:
	var out := AABB()
	var first := true
	var inv := global_transform.affine_inverse()
	for c: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if profile.id == SuitProfile.Id.GP03S and mi.get_meta("gp03s_weapon",false): continue
		var xf: Transform3D = inv * mi.global_transform
		var a: AABB = xf * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


## 自机反照率压暗系数（第十四轮，老板追加的光照要求："玩家主体比环境更黑"）。
##
## ⚠️ 这是**保守的一档**：只压反照率，**不动环境光**。
## `time_of_day.gd` 的夜晚预设里写着为什么当年否掉了"把机体压黑"那一版：
## "完全按真实月夜来，自家机体就是一个纯黑剪影，玩家连自己的姿态都看不出来"。
## 老板这次要的正是那个观感，所以压回来 —— 但保留天空环境光对机体的塑形，
## 姿态可读性交给月光、夜航灯、加速尾焰，以及第十四轮抬亮后的海面与云背光。
const PLAYER_ALBEDO_SCALE := 0.6
## 云影对机体的最大压暗量。与地表的 `WorldBuilder.CLOUD_SHADE_STRENGTH`（0.45）同量级，
## 但机体不用压那么狠 —— 它本身就比环境暗了（见 `PLAYER_ALBEDO_SCALE`）。
const CLOUD_SHADE_DEPTH := 0.35
## 云影系数变化小于这个值就不重写材质：一台机十几个 surface，
## 每帧无脑赋值会白白触发一堆材质更新。
const CLOUD_SHADE_EPSILON := 0.01


## 敌机改色 / 自机压暗所改的那批材质，以及它们的**原始** albedo。
##
## 存原值是为了云影：云影不能让颜色一路乘下去
## （0.6 × 0.65 × 0.65 … 几秒就全黑了），必须每次都从原值算。
var _shade_mats: Array[StandardMaterial3D] = []
var _shade_base: Array[Color] = []
## 当前云影系数（−1 = 还没写过，保证第一次一定生效）。
var _cloud_shade := -1.0


## 当前云影系数（0..1）。
func cloud_shade() -> float:
	return maxf(_cloud_shade, 0.0)


## 云影（第十四轮 A5）。`v` = 0..1，1 = 完全在云下。
##
## 由 `main` 每帧从 `WorldBuilder.cloud_shade_at()` 写入。关键点是它与
## 地表 / 海面 shader 那条路径**采样的是同一张覆盖图**，
## 所以"机体上的云影"和"它脚下的云影"一定重合 —— 两套独立算法做不到这一点。
func set_cloud_shade(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if absf(v - _cloud_shade) < CLOUD_SHADE_EPSILON:
		return
	_cloud_shade = v
	var k := 1.0 - v * CLOUD_SHADE_DEPTH
	for i in _shade_mats.size():
		var mat := _shade_mats[i]
		if mat == null:
			continue
		var base: Color = _shade_base[i]
		mat.albedo_color = Color(base.r * k, base.g * k, base.b * k, base.a)


## 显示 / 隐藏**自机的视觉模型**（第一人称座舱视角用，见 `ChaseCamera.first_person`）。
##
## ## 为什么第一人称要把自己的模型藏起来
##
## 座舱眼位落在**头部壳的内部**。本工程的机体是 AI 扫描出来的**单层壳** ——
## 没有座舱内构、没有内壁材质、没有"从里往外看"的那一层。
## 相机待在壳里只会看到两样东西：背面剔除之后的穿透碎片（有的面读成"看得穿"、
## 有的面被 `cull_back` 剔掉），以及近平面（1.2 m）在头部切出一圈剖面。
## 要做"看得见自己肩膀"的座舱视角，得给每台机补一层内壳 —— 那是美术资产的事。
##
## ## 三个必须守住的细节
##
## ⚠️ **只动 `model_root` 的可见性，绝不碰 `rig`**：炮口 / 喷口 / 夜航灯 / 手部锚点
## 全靠 `SuitRig` 提供，FPV 下必须照常工作 —— 枪要从对的位置打出去。
## 有真模型时 `rig` 本来就是隐藏的（`set_placeholder_visible(false)`），
## 而它是 `model_root` 的子节点 ⇒ 一起被藏掉，没有副作用。
##
## ⚠️ **幂等**：`main._apply_camera_settings()` 每帧调一次，这里只在真的变了才写 ——
## 每帧写一次 `Node3D.visible` 会白白发出可见性通知。
##
## ⚠️ **不许把"阵亡后藏起来"这件事覆盖掉**：`die()` 里也写这个字段
##（机体没了就不该还有模型）。调用方（`main`）负责把 `alive` 一起算进条件里，
## 这个函数只做"照着给的布尔值写"这一件事。
func set_model_visible(v: bool) -> void:
	# A newly mounted/rebuilt board may contain the rider mesh even when the wish is unchanged.
	if is_instance_valid(pedal_owner()):
		pedal_owner().sync_cockpit_visibility(not v)
	# ⚠️ 早退看的是**愿望**（而不是原来那个“可见性没变就返回”）：
	# 踏板把 `rider_hidden` 一改，实际可见性就得重算，而愿望本身没变。
	if _model_wish == v:
		return
	_model_wish = v
	_apply_model_visibility()
	_sync_cockpit_propulsion_visibility()


## 板上有人 / 没人 ⇒ 骑手自己的模型该藏吗（**唯一写入点**，只有 `FlightPedal` 调）。
##
## ⚠️ **不做“标志没变就早退”**：`model_root` 会在 `_rebuild_visual()` 里被
## **重建**（新节点的 `visible` 默认 true）⇒ 早退会漏掉“换了模型但判据没变”这一类。
## 重算本身是幂等且仅在上下板 / 重建时跑，不是每帧。
func set_rider_hidden(v: bool) -> void:
	rider_hidden = v
	_apply_model_visibility()


## 两条判据合成**实际可见性** —— 全工程唯一写 `model_root.visible` 的地方
##（另一处在 `die()`，它同时把愿望也置假；见那里的注释）。
func _apply_model_visibility() -> void:
	if model_root == null or not is_instance_valid(model_root):
		return
	var want := _model_wish and not rider_hidden
	# 幂等：每帧写一次 `Node3D.visible` 会白白发可见性通知
	if model_root.visible == want:
		return
	model_root.visible = want


## 自机模型现在可不可见（测试用）。
func model_visible() -> bool:
	return model_root != null and is_instance_valid(model_root) and model_root.visible


## 自机压暗 + 敌机改色。**两者共用同一趟材质覆写**：都是"逐 surface 复制一份
## StandardMaterial3D 再改 albedo"，合并之后只遍历一次、也只留一份原值数组。
##
## 敌机那一半的理由没变：两台机本来就是不同模型（剪影可分），
## 所以只做一个很轻的暖色偏移，外加 HUD 的目标框来区分敌我 ——
## 上重涂装会把图集里辛苦烘的配色毁掉。
# ============================================================ 逐件细节距离剔除（轮 41 · 性能）
#
# 需求原文（轮 41）：「导弹多发 + 多台机子的时候会特别卡」+「在不改烟带的同时还能做优化」。
#
# ## 实测（编队战 14 台 · 交错 3 轮 · 同轮配对取中位，`tools/probe_perf.tscn --decompose`）
#   基准 23.8 ms ｜ 隐藏 13 台 AI 的模型 **省 10.9 ms**（绘制 3761 → 1017）
#   逐件按尺寸做距离剔除 **省 5.5 ms** —— 即这一项能吃掉 AI 模型开销的一半。
#
# ## 为什么"件数"才是瓶颈
#   机体的模型是**几百个独立件**拼的（实测 `--decompose` 打印的组成：**每台 493 件 /
#   166 份材质** —— 材质各不相同 ⇒ 合批不了 ⇒ 一件一次绘制调用）。而其中绝大多数是
#   **几厘米的小件**（单台件半径分布实测 `<0.1 m: 1 · <0.3 m: 14 · <1 m: 49 · <3 m: 116
#   · >=3 m: 44`）：它们在几百米外连**一个像素**都不到，却照样各占一次绘制调用。
#
# ## 做法：用引擎自带的按距离剔除，不新增任何每帧代码
#   `GeometryInstance3D.visibility_range_end` 是引擎的 per-instance 距离剔除：
#   **建模型时一次性设好，之后每帧零成本**，不参与任何脚本热路径。
#
# ## K 是**算出来的**，不是调的
#   件半径 r 的件在距离 d 处的屏幕尺寸约 `px ≈ r·H / (d·tan(fov/2))`。
#   本工程 60° FOV、视口高 1000 px ⇒ `tan30° ≈ 0.5774` ⇒ `px ≈ r · 1733 / d`。
#   取"**不到 1 像素就剔**"⇒ `d = 1733·r`。`DETAIL_LOD_K := 2000` 略严于 1 像素
#   （≈0.87 px），留一点余量防止边缘闪烁。
const DETAIL_LOD_K := 2000.0
# 下限（m）：再小的件也留到这么远 —— 否则机体贴脸时就开始掉件。
const DETAIL_LOD_MIN_M := 250.0
# 上限（m）：**必须留得足够大**，否则整台机体在远距会一起消失。
#   实测最大的件半径 10~15 m（躯干/腿），×K 就是 20~30 km ⇒ 地图内永不剔除
#   ⇒ 「12 km 交战看得见对面」这条玩法口径不受影响。**别再往小里调。**
const DETAIL_LOD_MAX_M := 30000.0


## 件半径 `radius_m` 的件，超过这个距离（m）就整件不画。
##
## 纯函数（静态、无副作用）⇒ 测试可以直接断言边界，不用起场景。
static func detail_range_end(radius_m: float, crowded: bool = false) -> float:
	# In squad battles, discard only small remote details around the two-pixel scale.
	# Large silhouette parts retain the original range, including long-range targets.
	var factor := 900.0 if crowded and radius_m < 3.0 else DETAIL_LOD_K
	return clampf(radius_m * factor, DETAIL_LOD_MIN_M, DETAIL_LOD_MAX_M)


## Hysteresis stops subpixel details toggling when the camera hovers at the cutoff.
## It preserves the existing threshold and never enables transparent fading.
static func detail_range_margin(range_end: float) -> float:
	return minf(120.0,maxf(0.0,range_end)*0.06)


## 单件的"半径"（米）：网格局部 AABB 的**半对角线长** × 全局平均缩放。
##
## ⚠️ 用 `get_aabb()`（网格自带、随资源走）而**不是** `bound_box` 那类缓存 ——
## 本工程有"包围盒缓存陈旧、差值到 0.13 单位"的记录；这里只需要量级，够用。
## ⚠️ 蒙皮件的 AABB 是**绑定姿势**下的包围盒。动画里件会摆大摆小，但这只是给
## 距离阈值定量级 —— 摆大 20% 不会让阈值从"1 像素"变成"可见"。
static func part_radius_m(mi: MeshInstance3D) -> float:
	if mi == null or mi.mesh == null:
		return 0.0
	var box := mi.get_aabb()
	var sc := mi.global_transform.basis.get_scale()
	return box.size.length() * 0.5 * ((sc.x + sc.y + sc.z) / 3.0)


func _on_material_style_changed() -> void:
	if profile == null or not SUIT_MATERIALS.supports(profile.id):
		return
	if _material_cel_mode == Settings.cel_shading:
		return
	var shade := cloud_shade()
	_apply_owner_materials(false)
	set_cloud_shade(shade)


func _apply_owner_materials(update_ranges := true) -> void:
	_material_cel_mode = Settings.cel_shading
	_shade_mats.clear()
	_shade_base.clear()
	_cloud_shade = -1.0
	if model_root == null or not is_instance_valid(model_root):
		return
	var tint := Color(0.42, 0.16, 0.14)
	for c: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# ---- 逐件细节距离剔除（轮 41 性能）----
		# 就设这一行：建模型时一次性写死，之后每帧零成本（见上面 `DETAIL_LOD_K` 的推导）。
		# ⚠️ 放在**这个循环里**而不是另起一次遍历：这里本来就要把 493 个件走一遍，
		#    再走一遍只是白花一次 493 节点的树遍历（14 台就是 6900 次）。
		if update_ranges:
			mi.visibility_range_end = detail_range_end(part_radius_m(mi), Game.match_mode == Game.MatchMode.SQUAD and not is_player)
			if mi.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
				mi.visibility_range_end_margin = detail_range_margin(mi.visibility_range_end)
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			# Custom authored shaders are not replaced by the new PBR path.
			if SUIT_MATERIALS.supports(profile.id) and src != null and not src is StandardMaterial3D:
				mi.set_surface_override_material(i, src)
				continue
			var mat: StandardMaterial3D
			if src is StandardMaterial3D:
				mat = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
			# Calibrated PBR for Xi Final / Gustav when cartoon rendering is off;
			# other suits and unlit effects retain their existing path.
			if SUIT_MATERIALS.supports(profile.id):
				SUIT_MATERIALS.apply(mat, profile.id)
			else:
				FX.toonify(mat)
			var realistic := SUIT_MATERIALS.realistic(profile.id)
			var lit := mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED
			if is_player and (not realistic or lit):
				# ⚠️ 不能写 `mat.albedo_color * PLAYER_ALBEDO_SCALE`：
				# Godot 的 `Color * float` 会**连 alpha 一起乘**，
				# 遇到用了透明通道的材质就会把机体变得半透明。逐通道显式写。
				var c0 := mat.albedo_color
				var albedo_scale := 0.88 if realistic else PLAYER_ALBEDO_SCALE
				mat.albedo_color = Color(c0.r * albedo_scale, c0.g * albedo_scale, c0.b * albedo_scale, c0.a)
			elif not realistic:
				mat.albedo_color = mat.albedo_color.lerp(tint, 0.22)
			mi.set_surface_override_material(i, mat)
			if not realistic or lit:
				_shade_mats.append(mat)
				_shade_base.append(mat.albedo_color)


## 槽位锚点 → FlightBody 局部坐标。rig 带缩放，必须走 rig.transform 而不能直接取 position。
##
## ## 两条来源，按名字命中（2026-09-26 · 棒 12）
##
##   ① **模型自带骨架**（新管线交付的 glb 有 50 根骨，锚点骨就在里面）——
##      取骨的**世界位姿**再折回机体局部空间。动作一播，锚点跟着动。
##   ② **占位骨架 `SuitRig`**（老路径，18 个老资产全是这条）——
##      一张硬编码的佩涅罗佩槽位表，与模型解剖无关，但**它是老机的唯一来源**。
##
## ⚠️ ① 优先而不是 ② 优先，是因为 ② 的表**恒命中**（见 `SuitRig.slot()`：
## 先查硬编码 `_slots`，`find_child` 回退永远走不到）⇒ 不优先①的话，
## 真模型的 `muzzle_L/R` 骨**永远不会被读到**，第 4 轮为枪口做的验收也就白做。
##
## ⚠️ 名字命中不到就退回②：模型骨架里没有 `shield_L` 这类槽位是正常的，
## 不能因此返回 `Vector3.ZERO`（那会让夜航灯/尾焰全部跑到原点）。
func rig_anchor(slot_name: String) -> Vector3:
	if profile != null and profile.id == SuitProfile.Id.XI_FINAL and slot_name in ["funnel_L", "funnel_R"] and _form_weld != null and _form_weld.get("_tail_motion") != null:
		return _form_weld.tail_anchor(slot_name)
	if _model_mounts.has(slot_name) and is_instance_valid(_model_mounts[slot_name]):
		var mount: Node3D = _model_mounts[slot_name]
		var local: Vector3 = global_transform.affine_inverse() * mount.global_position
		if (dash_spin != 0.0 or melee_hit_reaction.angles.length_squared()>0.000001) and is_instance_valid(spin_pivot):
			local = spin_pivot.transform.basis.transposed() * local
		return local
	# ---- ① 模型自带骨架 ----
	if _model_skel != null:
		var b := _bone_index(slot_name)
		if b >= 0:
			var bone_world: Transform3D = _model_skel.global_transform * _model_skel.get_bone_global_pose(b)
			# ⚠️ 转身期间要把它**剔掉**（轮 33）：`bone_world` 是**世界**位姿、含
			# `spin_pivot` 那一层；而锚点的契约是"模型没转身时骨该在的地方"
			#（见 `dash_spin` 的说明）—— 不剔的话枪口跟着模型绕机体中轴画圈，
			# 子弹从"看起来没有枪的位置"射出来。
			#
			# 做法：先折回机体局部（**这时还是含转身的**），再乘一次
			# `spin_pivot` 旋转的**转置**（纯旋转的逆就是转置）剔掉它。
			# 用转置而不是 `affine_inverse()`：转置是精确的 —— `affine_inverse()`
			# 版实测在 y≈900 的坐标量级上会留下 2.5 mm 的漂移（同一条断言量到过）。
			var local := global_transform.affine_inverse() * bone_world.origin
			if (dash_spin != 0.0 or melee_hit_reaction.angles.length_squared()>0.000001) and spin_pivot != null and is_instance_valid(spin_pivot):
				local = spin_pivot.transform.basis.transposed() * local
			return local
	# ---- ② 占位骨架 ----
	if rig == null:
		return Vector3.ZERO
	var s := rig.slot(slot_name)
	if s == null:
		return Vector3.ZERO
	return model_pivot.transform * (model_root.position + rig.transform * s.position)


## 这个槽位的锚点是不是**从模型骨架取的**。`_collect_muzzles()` 靠它决定
## 要不要乘收拢系数 `MUZZLE_INWARD`（见那里的说明）。
func anchor_from_model(slot_name: String) -> bool:
	return _model_mounts.has(slot_name) or (_model_skel != null and _bone_index(slot_name) >= 0)


## 骨名 → bone index（带缓存）。`rig_anchor()` 每帧被喷口/炮口/夜航灯调多次，
## 线性扫 50 根骨是白费的。
func _bone_index(bone_name: String) -> int:
	if _bone_idx.has(bone_name):
		return _bone_idx[bone_name]
	var idx := -1
	if _model_skel != null:
		idx = _model_skel.find_bone(bone_name)
	_bone_idx[bone_name] = idx
	return idx


## 炮口位置相对槽位锚点的收拢系数（1.1，用户要求"射击位置往模型中心一点"）。
##
## 槽位骨架是从佩涅罗佩的线稿定的，`muzzle_L/R` 落在**前臂盾的外缘**
## （局部坐标 ±10.6 / −6.6 / −4.6，按骨架缩放后两门炮相距二十多米）。
## 弹道从炮口起算（见 `aim_point`），炮口离中心越远，
## 两侧弹道在准星处交汇的夹角就越大 —— 近战距离下会出现"两发子弹夹着目标跑"。
## 把偏移整体乘 0.45 收拢到机体中心附近：交汇点更靠内、观感更像"从机体正面打出去"，
## 同时保留了左右两侧的交替感（HUD/音频还是能听出两边在轮流开火）。
const MUZZLE_INWARD := 0.45


## 双联背部炮口的定位 —— **用 `model_bounds`（真实模型的包围盒）**，不用骨架锚点。
##
## ⚠️ **为什么不能用 `rig_anchor("backpack")`**（第一版就是这么写的，炮口跑到小腹上）：
## 那副骨架是按**佩涅罗佩线稿**定的，阿利宙斯的模型只是被"按包围盒居中"塞进同一副骨架，
## 两者的解剖结构**对不上**。实测（`tools/probe_twin`）：
##   模型包围盒 y ∈ [−18.16, +14.85]（总高 33.0 m）、z ∈ [−15.30, +15.30]
##   而 `rig_anchor("backpack")` = (0, **−14.77**, 2.76) —— 那是**腰以下**，不是背包；
##   照它放炮口得到 (±2.91, −8.62, +0.81)：模型 26% 高度、离中心 2.9 m。
## 于是光束从小腹里射出来、前半段整段埋在机体内部，追尾镜头里根本看不见。
##
## 包围盒是**量出来的真实几何**，按比例取"上后方"就不会错，而且自动随形态缩放
## （巡航形态是另一个模型、另一套尺寸）。
##
## ⚠️ **两道光束的间距由这条规则给定**（用户指定："半间距是光束半径的 3 倍"）：
##
##     半间距 = 光束**可视**半径 × 3，其中 可视半径 = `Projectile.BEAM_VIS_RADIUS × rifle_scale`
##
## 所以间距**不是**一个独立的米数，而是**跟着光束尺寸走**的 —— 光束一大，炮口自动往外挪。
## 这正是要的：间距如果写死，"把光束调大"这一步就会让两道光糊成一道粗的。
##
## 口径说明（重要）：这里用**可视半径**（`BEAM_VIS_RADIUS`，圆柱的半径），
## 不是 `Projectile.hit_radius()`。后者是**判定**半径（`BEAM_HIT_RADIUS`，刻意更大，
## 工程规矩：让"擦着机翼过去"的弹也算命中），拿它去乘 3 会得到远超整台机宽度的轴距，
## 炮口会飘在机体外面的空气里。
##
## （2026-10-03 轮 63：两个半径已拆成独立常量。炮口跟着**可视**那个走，
##   所以"把子弹调粗"仍然会自动把炮口推开，而"把判定放宽"不会动炮口几何。）
const BACK_MUZZLE_GAP_MUL := 3.0

## 从模型底部往上多少比例处开炮（`model_bounds` 是**量出来的真实几何**）。
##
## ⚠️ **这个比例是相对"包围盒"的，而包围盒会被凸出物撑长/撑短** —— 换模型或加减部件之后
## 必须用 `tools/probe_twin.tscn` 重新核对，别默认它还有效。实测沿革：
##
##   - `0.84`：**尾翼被误删**那版的值。那版包围盒里最高的部件就是肩背，0.84 正好在肩上方。
##   - 尾翼恢复后包围盒向下长了 0.196（= 游戏里 7.05 m）。沿用 0.84 会把炮口顶高
##     约 6 m；我一度按"离包围盒底部不变"反算成 0.69，**那是错的** ——
##     包围盒底部已经从脚底变成了**尾翼尖**，所以 0.69 把炮口压到了胸口
##     （实测离脚底 20.6 m，原本是 27.7 m）。
##   - 现在 `0.868` = 按"**离脚底的绝对高度不变（27.7 m）**"反算：
##       脚底在包围盒底部之上 7.05 m ⇒ 27.7 + 7.05 = 34.75 m ⇒ 34.75 ÷ 40.05 ≈ 0.868
const BACK_MUZZLE_HEIGHT := 0.868
## 从模型最前到最后的多少比例处（0.66 ≈ 背侧）。
## 同样注意它是相对包围盒的；尾翼往后伸也把包围盒往后带了，实测炮口后移 0.9 m（可接受）。
const BACK_MUZZLE_DEPTH := 0.66


func _collect_muzzles() -> void:
	_muzzle_local.clear()
	if profile.id == SuitProfile.Id.NEUE_ZIEL:
		var battery = preload("res://scripts/combat/neue_battery.gd")
		var axis := Basis(Vector3.UP,PI*0.5)
		for i in 4:
			_muzzle_local.append(axis * (battery.PORTS[i]*battery.SOURCE_SCALE))
		return
	if profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.GP03S]:
		_muzzle_local.append(rig_anchor("muzzle_L"))
		return
	# ---- 双联背部炮（阿利宙斯常态 / 巡航）----
	if profile != null and profile.rifle_back_mount and model_bounds.size.length() > 0.01:
		var b := model_bounds
		var y := b.position.y + b.size.y * BACK_MUZZLE_HEIGHT
		var z := b.position.z + b.size.z * BACK_MUZZLE_DEPTH
		# 半间距 = 光束可视半径 × 3（见 BACK_MUZZLE_GAP_MUL）
		var half := Projectile.BEAM_VIS_RADIUS * profile.rifle_scale * BACK_MUZZLE_GAP_MUL
		_muzzle_local.append(Vector3(half, y, z))
		_muzzle_local.append(Vector3(-half, y, z))
		return
	# ---- 老行为：前臂盾外缘的两门（见 MUZZLE_INWARD）----
	for n: String in ["muzzle_L", "muzzle_R"]:
		if anchor_from_model(n):
			# 模型自带的锚点骨 = **真实几何位置**，不要再乘收拢系数。
			# `MUZZLE_INWARD` 存在的唯一理由是"占位骨架的 muzzle 落在佩涅罗佩
			# 前臂盾外缘、两门炮相距二十多米"；而真模型的 `muzzle_L/R` 是两个
			# **重合**的枪口点（柯西单手持枪，实测两点距离 0.000000000），
			# 乘 0.45 只会把枪口拉向机身中心 —— 又一次"子弹不从枪管出"。
			_muzzle_local.append(rig_anchor(n))
		elif rig != null and rig.has_slot(n):
			_muzzle_local.append(rig_anchor(n) * MUZZLE_INWARD)
	if _muzzle_local.is_empty():
		var h := model_bounds.size
		_muzzle_local = [
			Vector3(h.x * 0.30, h.y * 0.08, -h.z * 0.34) * MUZZLE_INWARD,
			Vector3(-h.x * 0.30, h.y * 0.08, -h.z * 0.34) * MUZZLE_INWARD,
		]


## 引擎循环音的兜底（档案没写、或写了个非循环的）。
## 与 `SuitProfile.engine_sound` 的默认值保持一致 —— 两处不一致的话，
## "哪个是默认"就得靠猜。
##（2026-09-30 轮 49 两处**一起**从 `cruise_penelope` 改成 `cruise_xi`：
##   默认值现在的语义是"**除佩涅罗佩外**的所有机体"。）
const ENGINE_SOUND_DEFAULT := "cruise_xi"

## 引擎音**起播淡入**时长（秒）。
##
## ⚠️ 为什么要它（2026-10-09 用户实测：「进入战斗会有引擎的突然爆音」）：
## `Audio.make_loop_3d()` 把播放器造出来时写 **`volume_db = -60`**（静音），
## 而 `_update_engine_audio()` 在**下一物理帧**就把它改写成速度映射值 ——
## 出生时 `fm.speed = SuitProfile.spawn_speed()` 已经是巡航档
## ⇒ `engine_gain` ≈ 0.31 ⇒ **约 -10 dB**（实测 -10.14）。
## ⇒ **一帧之内 -60 → -10 dB（实测 49.9 dB 台阶）**：起播那一帧就是一次满幅冲击。
## 而且出生是**整队同时**的，`Audio._stream()` 又按名字缓存（同一份 `AudioStream`）
## ⇒ N 台机体的引擎在**同一帧、同一相位**起播，相干相加；
## 而工程没有任何总线限幅器 ⇒ 叠起来就是用户听到的那声"爆音"。
##
## 淡入之后：1.2 s 内平稳升到目标值，单帧跳变约 0.8 dB（实测 0.69）。
## ⚠️ **稳态逐位不变** —— 淡入只改"开头那一段"，`engine_gain()` 那条曲线一个字没动
##（它另有判据钉着，见 `suite_audio._engine_gain`）。
const ENGINE_FADE_IN := 1.2

## 引擎音的"起播静音"值。
##
## ⚠️ **必须与 `Audio.make_loop_3d()` 的初值一致**（那边写的是 `-60.0`）。
## 不一致的症状：淡入的起点与播放器实际的起点对不上 —— 差几 dB 就是一个**新的台阶**，
## 也就是"修完还在爆音"，而且**不报任何错**。
const ENGINE_SILENT_DB := -60.0

## 本机引擎音已经播了多久（秒）。`_build_engine_audio()` 里归零。
##
## 用它而不是 `Engine.get_physics_frames()`：这里要的是"这台机的引擎存在了多久"，
## 与全局帧号无关（出生时刻各不相同，而且出生那一帧不一定是第 0 帧）。
var _engine_age := 0.0


## 引擎循环音 + 柯西座舱检测音。
##
## **玩家自己的引擎是非定位的**（在座舱里，不该有距离衰减），
## **敌机的引擎是 3D 定位的** —— 需求里"如果玩家开的是佩涅罗佩，
## 柯西的巡航声要靠近了才听得到"就是靠这个衰减自然实现的，不需要手写距离判断。
##
## 音量随速度：静止时 5%、满速 100%（需求原文）。
##
## ⚠️⚠️ 2026-09-25：音源**读 `profile.engine_sound`**，不要再按 `profile.id` 现判。
##
## 原来那一行是 `"cruise_xi" if profile.id == SuitProfile.Id.XI else "cruise_penelope"`。
## 于是"阿利宙斯的引擎音沿用柯西那一条"这个决定**写在档案里、却从来没被读过** ——
## `engine_sound` 这个字段全场只有 **5 处赋值、0 处读取**（死字段）。
## 阿利宙斯 id 不是 XI ⇒ 它一直发的是佩涅罗佩那条循环音。
## 用户 2026-09-25 报的就是这个：「把阿利宙斯巡航模式的音效换成和柯西一样的」。
##
## 改完之后音源只有**一个真源**（档案字段）：要改哪台机的引擎音，改那台机的档案，
## 不用回来动这里。也正因为只有一个真源，"档案里写了什么"与"屏幕上放了什么"
## 才不可能再分叉 —— 分叉的那段时间里，两边看着都是对的。
func _build_engine_audio() -> void:
	var sound := ENGINE_SOUND_DEFAULT
	if profile != null and profile.engine_sound != "":
		sound = profile.engine_sound
	# 防"档案上填了个不循环的音效"：引擎音必须循环，否则播一遍之后**永久静音**，
	# 而这件事不会报任何错（`make_loop_3d` 照建、`stream` 也非空、`playing` 还是 true）。
	# 静音是最难查的一类故障，所以这里降级 + 吼一声，不让它悄悄发生。
	if not SoundBank.is_looping(sound):
		push_warning("[FlightBody] engine_sound = %s 不在 SoundBank.LOOPING 里，退回 %s"
			% [sound, ENGINE_SOUND_DEFAULT])
		sound = ENGINE_SOUND_DEFAULT
	_engine = Audio.make_loop_3d(sound, 3200.0, not is_player)
	add_child(_engine)
	# ⚠️ 归零必须在 `play()` **之前**：起播与"计时起点"要是同一个时刻，
	# 否则第一次调 `_update_engine_audio()` 时 `_engine_age` 已经不为 0 ⇒
	# 淡入从中间开始 = 起播仍然是台阶（只是小了一点，最难查的那种）。
	_engine_age = 0.0
	_engine.play()

	# 巡航检测音只有开柯西才听得到（佩涅罗佩的座舱里没有这套提示）。
	# 用 Timer 每 1.5 秒重放一次，而不是靠音频文件自身长度去凑 ——
	# 素材多长都不影响节拍。
	if is_player and profile.id in [SuitProfile.Id.XI, SuitProfile.Id.XI_FINAL, SuitProfile.Id.GP03D]:
		_detect_player = AudioStreamPlayer.new()
		_detect_player.name = "DetectBeep"
		_detect_player.bus = Settings.BUS_SFX
		add_child(_detect_player)
		var s := Audio.get_stream_for("xi_detect")
		if s != null:
			_detect_player.stream = s
			_detect_timer = Timer.new()
			_detect_timer.name = "DetectTimer"
			_detect_timer.wait_time = 1.5
			_detect_timer.autostart = true
			_detect_timer.timeout.connect(_on_detect_beep)
			add_child(_detect_timer)


func _on_detect_beep() -> void:
	if _detect_player != null and alive:
		_detect_player.play()


## 引擎音量映射：**静止 5% → 满速 100%**（需求原文）。
## 抽成静态纯函数是为了能单测 —— 这条映射是需求里唯一给了具体数字的音频规则。
static func engine_gain(speed: float, top_speed: float) -> float:
	if top_speed <= 0.0:
		return 0.05
	return lerpf(0.05, 1.0, clampf(speed / top_speed, 0.0, 1.0))


## 引擎音量：静止 5% → 满速 100%。
##
## ⚠️ `delta` 是**新增的**（2026-10-09 起播淡入）—— 它只喂淡入计时，
## 稳态那一段与加它之前**逐位相同**（见 `ENGINE_FADE_IN` 的头注）。
## 默认 0.0 是留给"只想读一遍稳态"的调用方（探针 / 别的套件）；
## 产品路径**必须**传真实 delta，否则淡入永远停在起点（引擎一直静音，不报错）。
func _update_engine_audio(delta := 0.0) -> void:
	if _engine == null:
		return
	_engine_age += delta
	var top := maxf(fm.max_reachable_speed(), 1.0)
	var gain := engine_gain(fm.speed, top)
	var want_db := linear_to_db(maxf(gain, 0.001))
	# 敌机的引擎再按难度调低一点底噪，免得远距离糊住整个声场
	if not is_player:
		want_db -= 4.0
	# ★ 起播淡入：从静音值升到 `want_db`，1.2 s 内走完。
	#
	# ⚠️ 在 **dB 空间**里插值（不是"把线性音量乘 ramp"）：
	#   linear 乘 ramp 的前几帧 dB 涨得极快（对数量），台阶只是被挪进前 0.1 s，
	#   听感上仍是"啪一下起来"。
	# ⚠️ `ramp >= 1.0` 时**直接写 `want_db`**，不走 `lerpf`：
	#   `lerpf(a, b, 1.0)` 算的是 `a + (b - a) * 1.0`，浮点上**不保证**逐位等于 `b`。
	#   稳态要是差了 1e-6 dB，全量回归里"稳态与旧公式逐位相同"那条判据就成了假绿。
	var ramp := 1.0 if ENGINE_FADE_IN <= 0.0 else clampf(_engine_age / ENGINE_FADE_IN, 0.0, 1.0)
	_engine.volume_db = want_db if ramp >= 1.0 else lerpf(ENGINE_SILENT_DB, want_db, ramp)


func _build_collision() -> void:
	if profile.id == SuitProfile.Id.NEUE_ZIEL:
		var hull := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = model_bounds.size * Vector3(0.90,0.92,0.90)
		hull.shape = box
		hull.position = model_bounds.get_center()
		add_child(hull)
		return
	if profile.id == SuitProfile.Id.GP03D:
		# Broad Orchis hull, plus the separate narrow cannon; do not use an MS capsule.
		for spec in [{"name":"Hull","size":Vector3(58,34,73),"at":Vector3(0,-2,31.5)},
				{"name":"CannonHull","size":Vector3(5,5,67),"at":Vector3(14,3,-36.5)}]:
			var part := CollisionShape3D.new()
			part.name = spec["name"]
			var box := BoxShape3D.new()
			box.size = spec["size"]
			part.shape = box
			part.position = spec["at"]
			add_child(part)
		return
	var shape := CollisionShape3D.new()
	shape.name = "Hull"
	var cap := CapsuleShape3D.new()
	cap.radius = clampf(maxf(model_bounds.size.x, model_bounds.size.z) * 0.26, 3.0, 11.0)
	cap.height = maxf(model_bounds.size.y * 0.72, cap.radius * 2.2)
	shape.shape = cap
	add_child(shape)


## 夜航灯：左红 / 右绿 / 尾部白色频闪。
## 夜战里机体本体几乎全黑，没有这几点光是完全看不出对方姿态的，
## 所以它们是玩法的一部分，不只是装饰。
## 用自发光小球而不是 OmniLight —— 两机六个光源在 Forward+ 里不划算，
## 而屏幕空间辉光（glow）已经能把小球拉出光晕。
func _build_nav_lights() -> void:
	# wing_L 在 +X（建模里 +X 是右），所以绿；wing_R 在 −X（左），红。
	var specs := [
		{"slot": "wing_L", "color": Color(0.25, 1.0, 0.40), "size": 0.70},
		{"slot": "wing_R", "color": Color(1.0, 0.20, 0.16), "size": 0.70},
		{"slot": "backpack", "color": Color(1.0, 1.0, 0.95), "size": 0.55},
	]
	_nav_lights.clear()
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var mi := MeshInstance3D.new()
		mi.name = "NavLight%d" % i
		var sphere := SphereMesh.new()
		sphere.radius = spec["size"]
		sphere.height = float(spec["size"]) * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = spec["color"]
		mat.emission_enabled = true
		mat.emission = spec["color"]
		mat.emission_energy_multiplier = 6.0
		mat.disable_receive_shadows = true
		sphere.material = mat
		mi.mesh = sphere
		mi.position = rig_anchor(spec["slot"])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_nav_lights.append({"node": mi, "slot": spec["slot"]})
		if i == 2:
			_nav_strobe = mi


# ============================================================ 每帧

func _physics_process(delta: float) -> void:
	if not alive:
		_wreck_timer -= delta
		if _wreck_timer <= 0.0 and _wreck_timer > -900.0:
			queue_free()
		return
	combat_buffs.tick(self,delta)
	melee_guard.tick(self,delta)
	_tick_transform(delta)
	_think(delta)
	# ---- 燃料槽裁决（1.2 第十九轮）----
	#
	# ⚠️ **位置很关键：必须在 `_think()` 之后、`_apply_flight()` 之前**。
	#   之前 ⇒ 各子类（玩家 / AI / 辅助驾驶）已经表达了"我想加速"的意愿；
	#   之后 ⇒ 气动读到的 `fm.boosting` 已经是**裁决过**的真相。
	# 放在这两者之中，10 个写入点一个都不用动。
	resolve_jet_gauge(delta)
	# ---- 被载机（一块板上两台，1.2 第二十六轮）----
	#
	# ⚠️ **位置由领机的踏板驱动，不做气动**（`_apply_carried()`）。
	# 两套独立气动会让两台互相追 —— 表现是"一台在前、一台在后"，
	# 而分状态模型里那两台机体是**固定座次**的，必须严丝合缝地站在挂位上。
	#
	# 用户实测报的就是这个：「开局六台量产机，**只有三台是在踏板上的**」——
	# 编队战只给领机配了板，僚机只是靠转向跟着飞，根本没上板。
	if is_carried():
		_apply_carried(delta)
		_tick_weapons(delta)
		_tick_effects(delta)
		return
	if not is_instance_valid(gp03_grab_owner):
		_apply_flight(delta)
	_tick_weapons(delta)
	_tick_effects(delta)


## 子类覆盖：写入 control_input / fm.throttle / fm.boosting / fm.hovering / shield_up，
## 并调用武器接口。
func _think(_delta: float) -> void:
	pass


## Player-only predictive guard hook. AI and manual flight keep the exact path.
## Returns true when the subclass adjusted the flight vector before movement.
func _before_flight_move(_delta: float) -> bool:
	return false


## 进入命中停顿（`_slash()` 会同时对双方调用）。
##
## `duration < 0`（默认）= 用 `HITSTOP_TIME`；军刀命中传 `HITSTOP_TIME_SABER`、
## 相杀传 `HITSTOP_TIME_CLASH` —— 分级顿帧（批 10 打击感），见那两个常量的注释。
func begin_hitstop(duration := -1.0) -> void:
	_hitstop = duration if duration >= 0.0 else HITSTOP_TIME
	_hitstop_hold = maxf(fm.speed * HITSTOP_SPEED, 0.0)


func _apply_flight(delta: float) -> void:
	combat_buffs.restore_motion(self)
	# ---- 骑踏板时**不能悬停**（1.2 第十九轮：这成了踏板剩下的唯一硬代价）----
	#
	# ⚠️ 放在 `_apply_flight()` 的**最前面**，理由与下面"脱出突进"那段一样：
	#    子类在 `_think()` 里写 `fm.hovering`，而这里是紧接着的下一站 ——
	#    在这里覆盖，玩家 / AI / 辅助驾驶三条路一次性都盖到，不用各加开关。
	#
	# ⚠️ 上一轮起"骑板禁军刀"被去掉了（量产机要骑板赶路，禁刀 = 那六台整场近战残废，
	# 而且让**相杀对骑板者永远不可达** —— 见 `try_saber()`）。
	# 于是踏板现在的取舍只剩：**转向钝（×0.8）+ 不能悬停**。
	# 这条门禁必须留着，否则踏板会变成"只赚不赔"。
	if has_pedal():
		fm.hovering = false

	# 命中停顿：把速度按在"砍中那一刻的 15%"。用 minf 而不是直接赋值 ——
	# 于是模型给推力也超不过这个地板，观感是"顿住了"而不是"被清零又立刻加速"。
	# ⚠️ 放在**最前面**（飞行模型步进之前），且与辅助驾驶的"压加速"互不干扰：
	# 那一句在 `PlayerController._apply_flight()` 里、走的是 `super.` 之前的路径。
	if _hitstop > 0.0:
		_hitstop = maxf(_hitstop - delta, 0.0)
		fm.speed = minf(fm.speed, _hitstop_hold)
		if fm.velocity.length() > 1.0:
			fm.velocity = fm.velocity.normalized() * fm.speed
	# ---- 脱出飞升突进（1.2）：这一段时间里机体自己接管操纵 ----
	#
	# 覆盖点刻意选在 `_apply_flight()` 而不是 `_think()`：
	# 子类（玩家/ AI）在 `_think()` 里写 control_input，而 `_apply_flight()`
	# 是紧接着调用的 —— 在这里覆盖等于"谁的输入都没用"，
	# 不需要给 PlayerController / BanditAI 各加一个"我正在突进"的开关。
	if _escape_timer > 0.0:
		_escape_timer = maxf(_escape_timer - delta, 0.0)
		control_input = Vector3(1.0, 0.0, 0.0)   # 满杆抬头
		fm.boosting = true
		fm.hovering = false
		fm.throttle = 1.0
		if fm.speed < ESCAPE_DASH_SPEED_FWD:
			fm.speed = minf(fm.speed + 900.0 * delta, ESCAPE_DASH_SPEED_FWD)
	if _step_saber(delta):
		# 军刀突进期间姿态与速度由状态机接管，不走常规气动
		_before_flight_move(delta)
		velocity = fm.velocity
		combat_buffs.scale_motion(self)
		melee_guard.limit(self)
		move_and_slide()
		_check_collisions()
		_check_ceiling()
		return
	# ---- 辅助驾驶 · 平移模式（2026-09-22）----
	#
	# ⚠️ 排在**军刀与脱出突进之后**：那两个接管期间平移让位
	#（脱出突进是强制演出，玩家这 1.25 s 按什么都没用 —— 平移分支若在它前面，
	# 会把"飞升突进"的初速当场抹掉，演出直接消失）。
	# 命中停顿不排它：0.1 s 的停顿里速度被 lerp 拉走一点，观感无损。
	if (translate_mode or (profile.id == SuitProfile.Id.PENELOPE and (_qb_pending or _qb_timer > 0.0))) and _escape_timer <= 0.0:
		_apply_translate(delta)
		return
	# ---- 退出平移模式的闪避残留清理（批 10 bug 排查补）----
	# `_qb_timer` 只在 `_apply_translate` 里衰减：闪避窗口（0.45 s）中途关辅助
	# （G）的话，残留的窗口状态会一直挂着 —— 下次再进平移模式时，把没走完的
	# 窗口"补放"出来：凭空朝旧方向冲一段、拖尾亮、限制条还不回充。
	# 非平移路径每帧清一次（禁控分支在 PlayerController 侧另有同款清理）。
	if translate_dash or _qb_pending or _qb_timer > 0.0:
		translate_dash = false
		_qb_pending = false
		_qb_timer = 0.0
	# 侧倾状态一并清（批 11）：残留的压坡角/朝向基准会让下次进平移模式时
	# 机头"莫名歪一下"。非平移路径每帧清，代价是两次赋值。
	_bank_sm = 0.0
	_prev_flat_fwd = Vector3.ZERO
	# 转身状态一并清（轮 33）：闪避窗口中途关辅助 / 被禁控时，残留的角度会让机体
	# "歪着转一半"停在下次进平移模式的那一刻。
	_dash_spin_dir = 0.0
	_dash_spin_t = 0.0
	dash_spin = 0.0
	# 冲刺动画方向一并清（N46）：理由同上 —— 残留会让下次进平移模式凭空播一段冲刺。
	_dash_anim_dir = ""
	var nb := fm.advance(delta, global_transform.basis, control_input)
	global_transform = Transform3D(nb, global_transform.origin)
	_before_flight_move(delta)
	velocity = fm.velocity
	combat_buffs.scale_motion(self)
	melee_guard.limit(self)
	move_and_slide()
	_check_collisions()
	_check_ceiling()


func _check_ceiling() -> void:
	# ---- 有地面：照旧（贴海面 / 贴地飞撞上去就判死）----
	if map_has_ground():
		if not map_ground_damaging(): return
		if global_position.y < CRASH_ALTITUDE:
			if _prevent_ground_crash(): return
			destroy(null, "撞海")
		return
	# ---- ★ 轨道图：**没有"撞地"这回事**（老板：「近地轨道没有撞地这种情况」）----
	#
	# 越过下边界（再入线）不判死，而是**强制推回战斗高度带**。
	# ⚠️ 这两条路**互斥**：轨道图上 `destroy()` 一次都不该被调用 ——
	# `suite_space_map` 的越界判据直接断言"机体还活着"（那是行为判据，不是读字段）。
	if global_position.y < orbit_floor_alt():
		_enforce_orbit_floor()


## 轨道图的**下边界**（米）= 再入线。有地面图返回 `CRASH_ALTITUDE`（照旧）。
##
## ⚠️ 读数**不认地图 id**，认的是 `has_ground` 那一位 —— 与 `map_has_ground()` 同一条规矩
##（加第二张无地面图时不必回来改这里）。
static func orbit_floor_alt() -> float:
	var m := Game.active_map
	if m == null or m.has_ground:
		return CRASH_ALTITUDE
	return m.reentry_alt


## 越过下边界时把机体**推回战斗高度带**（老板从三个选项里挑的那一档）。
##
## ## 三条它**不做**的事（每一条都是刻意的）
##   · **不判死**。近地轨道上没有"撞地"，`destroy()` 在这条路上一次都不调；
##   · **不扣血、不打断**。探到边界只该"被顶回来"，不该挨一发惩罚；
##   · ★ **不改水平速度**。被顶回来的是**垂直**那一维 —— 水平照飞。
##     否则"贴再入线飞"（本图那条低空语义）会在碰到线的瞬间变成急刹车。
##
## ## ⚠️ 垂直速度为什么必须清零
## 不清的话：位置被抬回 550 km，而 `fm.velocity.y` 还是负的（俯冲中）
## ⇒ **下一帧立刻又掉到线下** ⇒ 每帧触发一次回轨 ⇒ 机体在边界上高频抖动，
## 而且 `orbit_returns` 疯涨（判据读到几千而不是 1，"被推回来过"这件事就失去了读数）。
func _enforce_orbit_floor() -> void:
	var m := Game.active_map
	var back := m.orbit_alt if (m != null and m.orbit_alt > 0.0) else WorldBuilder.SPACE_ORBIT_ALT
	global_position.y = back
	fm.velocity.y = 0.0
	velocity.y = 0.0
	orbit_returns += 1


## 本局所在地图**底下有没有东西**。`Game.active_map` 为空（单测 / 还没开局）时
## 按**有地面**算 —— 那是五张地表图的行为，也是 `MapDef.has_ground` 的默认值。
##
## ## 它现在决定两条**互斥**的路（2026-09-29 起）
##   · 有地面图：`_check_ceiling()` 判 `y < CRASH_ALTITUDE` ⇒ `destroy("撞海")`；
##   · 轨道图：**不判死**，改走 `_enforce_orbit_floor()` 把机体推回战斗高度带
##     （老板：「近地轨道没有撞地这种情况」）。下边界的高度取 `m.reentry_alt`（卡门线 100 km）。
##
## ⚠️ **改前那一版不是这样的**：轨道图把 `y = 0` 当再入线、与五张图的 `y = 0`（海平面）
## "数值同构"，于是越过那条线是 `destroy("再入烧毁")` —— 一样是死，只是换了句文案。
## 2026-09-29 老板把整套坐标换成**真实高度**（地球球顶 = `y = 0`、再入线 = 100 km、
## 轨道 = 550 km），"撞地"这件事在轨道上就彻底不存在了，这里跟着分成两条路。
static func map_ground_damaging() -> bool:
	return Game.active_map == null or Game.active_map.ground_collision_damage

static func map_has_ground() -> bool:
	var m := Game.active_map
	return m == null or m.has_ground


## 冲刺起手时判一次"这一记是不是左右冲刺"，是就开转身窗口（轮 33）。
##
## ## 判据
##
## `translate_dir` 是"镜头水平前 / 镜头水平右 / 世界上"三轴的合成
##（见 `PlayerController._read_translate_input`），把它投影到**机体自身的水平轴**上，
## 横向分量占优就是玩家读到的那一下左右横移。
##
## ⚠️ **门限 `DASH_SPIN_MIN_LAT` 不能省**：纯前后冲刺的 `_qb_dir` 与机头几乎共线，
## 横向分量只剩浮点噪声（1e-7 量级）。没有门限的话每一次前冲刺都会"闪一下"。
##
## ⚠️ 判据用"相对机体"而不是"相对屏幕"：锁定目标时镜头 ≈ 镜头前，而机头被拽向敌机，
## 两者可能差几十度 —— 按相对屏幕判的话，按 A/D 会在某些角位上被判成"前后冲刺"。
##
## ## 方向（向左冲就往左转身）
##
## 绕机体上轴（+Y）转正角度时，机头 −Z 被送到 (−sinθ, 0, −cosθ) ⇒ **机头朝左扫**。
## 冲刺向左时 `lat`（`_qb_dir` 在机体右轴上的投影）为负，取反得正角度 ⇒ 左转 ✓。
func _penelope_dash_direction(dir: Vector3) -> Vector3:
	_penelope_backflip = profile.id == SuitProfile.Id.PENELOPE and profile.form == 0 and penelope_cruise_enabled and _dash_dir8(dir) == "b"
	return Vector3.UP if _penelope_backflip else dir

func _start_dash_spin(dir: Vector3) -> void:
	_dash_spin_dir = 0.0
	_dash_spin_t = 0.0
	if SuitProfile.is_thunderbolt(profile.id):return
	# ★ 按机体关（2026-09-28 · N45；2026-09-29 起**默认就是关**）：
	#   转身会把左右两向的**动作本身**盖住（验收时看不出 `dash_l` / `dash_r` 播的是什么），
	#   所以 2026-09-29 用户要求「除了柯西以外的其他机体都不做翻滚转身」⇒
	#   `SuitProfile.dash_spin_visual` 默认 `false`，显式打开的只有
	#   **`SuitProfile.xi()`** 与 **`SuitProfile.arizeus()`** 两处（一次 grep 可查全）。
	#   —— 同日稍后用户追加「阿利宙斯可以做左右冲刺转身」，所以现在是**两台机体**。
	#   ⚠️ 连带："转身期间形态收起"也一并关掉 —— 两者共用 `_dash_spin_t`（有意）。
	#   注意这里仍把两个量**先归零**再早退：调用点可能在中途（例如上次窗口未完），
	#   不归零会留下半个角度。
	if _penelope_backflip and profile.id == SuitProfile.Id.PENELOPE:
		_dash_spin_dir = 1.0
		_dash_spin_t = QB_TIME
		return
	if profile.id == SuitProfile.Id.XI_FINAL and not in_cruise_form():
		return
	if not profile.dash_spin_visual:
		return
	if not model_visible():
		# 座舱视角：模型本来就不画，转身只剩"锚点口径要不要跟着变"这个纯负担。
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.000001:
		return
	var b := global_transform.basis
	var right := Vector3(b.x.x, 0.0, b.x.z)
	var fore := Vector3(-b.z.x, 0.0, -b.z.z)
	if right.length_squared() < 0.000001 or fore.length_squared() < 0.000001:
		return
	var d := flat.normalized()
	var lat := d.dot(right.normalized())
	var lon := d.dot(fore.normalized())
	if absf(lat) < DASH_SPIN_MIN_LAT or absf(lat) <= absf(lon):
		return
	_dash_spin_dir = -signf(lat)
	_dash_spin_t = QB_TIME


## 冲刺**动画**起手：把冲刺方向离散成八向名，之后由 `_tick_model_anim()` 每帧转发给状态机。
##
## 与 `_start_dash_spin()` 在**同一处、同一帧**调 —— 两者都是"闪避这一次 commit"的产物。
## 分开调的话，迟早有一天只调了其中一个（本工程最擅长的那种静默半升级）。
func _start_dash_anim(dir: Vector3) -> void:
	if profile != null and absf(dir.y) > Vector2(dir.x,dir.z).length() * 1.2:
		_dash_anim_dir = "u" if dir.y > 0.0 else "d"
	else:
		_dash_anim_dir = _dash_dir8(dir)


## 把世界方向离散成**相对机体**的八向名。返回 `""` = 方向退化（纯垂直 / 零向量），不播。
##
## ## 为什么判据是"相对机体"而不是"相对屏幕"
##
## 动画表达的是**机体在做哪种机动**，与镜头当时朝哪无关。这条依据与
## `_start_dash_spin()` **必须同源** —— 否则会出现"转身判定说是横移、
## 动画播的是前冲"的错配（两块各自都对，合起来不对）。
##
## ⚠️ 锁定目标时镜头 ≈ 镜头前、而机头被拽向敌机，两者可能差几十度：
##    按屏幕判的话，按 W 会被算成左右冲刺。
##
## ⚠️ 向前用 `-basis.z`（机体前），与 `_start_dash_spin()` 同式；⛔ 别用 `+basis.z`。
func _dash_dir8(dir: Vector3) -> String:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.000001:
		return ""
	var b := global_transform.basis
	var right := Vector3(b.x.x, 0.0, b.x.z)
	var fore := Vector3(-b.z.x, 0.0, -b.z.z)
	if right.length_squared() < 0.000001 or fore.length_squared() < 0.000001:
		return ""
	var d := flat.normalized()
	# `atan2(lat, lon)`：0 = 正前、+90° = 正右。除以 45° 取整 ⇒ 落到 `DASH_DIR_NAMES` 的索引。
	var lat := d.dot(right.normalized())
	var lon := d.dot(fore.normalized())
	var i := int(round(atan2(lat, lon) / (TAU / 8.0)))
	i = ((i % 8) + 8) % 8
	return DASH_DIR_NAMES[i]


## 常态平飞方向（`fly_<dir>` 的八向名）。没有平移输入 ⇒ `""`（不播方向动作）（N49）。
##
## ## 为什么要和 `_dash_dir8()` 共用一个函数
##
## 两族动作（`dash_*` / `fly_*`）用的是**同一张八向表**（`DASH_DIR_NAMES`）、
## 同一个"相对机体"离散化。各写一份的话，迟早出现"冲刺判定说横移、平飞播的是前冲"
## —— 那种错配两块各自都对、合起来不对，最难查。
##
## ## ⚠️ 判据是 `translate_dir`（**输入意图**），不是 `linear_velocity`（实际速度）
##
## 速度里有惯性和"自动飞行"底速（辅助驾驶模式下**无输入也永远在飞**）⇒
## 按速度判会让机体在零输入时一直播方向动作，等于把刚撤掉的"飞行待机"
## 从另一条路放回来。要的是"手上有输入才有动作"，所以读意图方向。
func _fly_dir8() -> String:
	if translate_dir.length_squared() <= 0.000001:
		return ""
	return _dash_dir8(translate_dir)


## 姿态微调的六向轴名（N49）。`""` = 三轴都在死区里（不播姿态动作）。
##
## ## 为什么取「绝对值最大」的那一轴
##
## `control_input` 是三根模拟量，同一帧通常三根都有值（摇杆残余、键盘斜按）。
## 而 `turn_*` 是**六选一**的单段动作 ⇒ 必须收敛成一根主轴。
## 取最大轴 = "玩家这会儿主要在打哪个舵"，与"只播一个"这个物理限制一致。
##
## ## ⚠️ 死区不是可选项
##
## 摇杆/按键回中后有残余 ⇒ 死区太小会让 `turn_*` **常态挂播**，
## 等于把刚撤掉的"飞行待机"从第三条路放回来（`fly_*` 那条路已经用
## `translate_dir` 的顺序行判过了，这里同理）。0.35 与 `flight_assist` 的杆量死区同量级。
##
## ## 符号（照 `player_controller` 的实源码，不是猜的）
##
## | 分量 | 正方向含义 | 正 / 负 → 动作 |
## |---|---|---|
## | `.x` pitch | 抬头（源码 `Vector3(1.0, 0.0, 0.0)` 注释："满杆抬头"） | `pitch_up` / `pitch_down` |
## | `.y` yaw   | 左偏航（`get_axis("yaw_right","yaw_left")` ⇒ 左 = +1） | `yaw_L` / `yaw_R` |
## | `.z` roll  | 左滚（源码注释："正 = 左滚（右翼抬起）"） | `roll_L` / `roll_R` |
const TURN_DEADZONE := 0.35

func _turn_dir() -> String:
	var ap := absf(control_input.x)
	var ay := absf(control_input.y)
	var ar := absf(control_input.z)
	var m := maxf(ap, maxf(ay, ar))
	if m < TURN_DEADZONE:
		return ""
	if m == ap:
		return "pitch_up" if control_input.x > 0.0 else "pitch_down"
	if m == ay:
		return "yaw_L" if control_input.y > 0.0 else "yaw_R"
	return "roll_L" if control_input.z > 0.0 else "roll_R"


## 辅助驾驶 · 平移模式的每帧位移（2026-09-22 二调：自动飞行 + 闪避冲刺）。
##
## 手感契约（用户反馈驱动）：
##   "辅助驾驶模式下依然保持加速飞行啊，自动飞行" → 底速 = 机头水平朝向 ×
##   加力极速，**无输入也永远在飞**；WASD/QE 只叠加修正（TRANSLATE_OFFSET 权重），
##   机头跟随速度矢量 → 按 A/D 自然压坡转弯。
##   "shift 键就变成类似装甲核心闪避/冲刺一样的功能" → 点按触发
##   （request_quick_boost），窗口内朝闪避方向直冲（加力极速 × QB_SPEED_MULT、
##   高响应），窗口结束自然回落底速；额外烧一段燃料槽（QB_JET_COST）。
##
## 三件事：
##   1. **速度**：向目标速度矢量插值（底速 + 修正，或闪避档）。
##   2. **机头**：水平航向跟随速度矢量，垂直速度带一点俯仰 ——
##      追尾镜头永远看着要去的方向。不经过 `FlightModel._step_attitude`。
##   3. **碰撞/坠海**：与常规路径同一套检查，一行都不省。
##
## ⚠️ `fm.speed` / `fm.velocity` 必须同步写：HUD 速度表、引擎音量、锁定距离、
## 军刀吸附……全都从它们读。写 `velocity`（CharacterBody3D 的）供 `move_and_slide` 用。
## ⚠️ `fm.boosting` 进来时已被 `resolve_jet_gauge()` 裁决：量产机槽空 → false，
## 底速自动退巡航极速、闪避也触发不了 —— 平移模式不豁免燃料槽。
## 平移修正在**速度层**的那一份（世界系，已按方向分档）。
##
## 抽成静态纯函数是为了**能钉数字**：`_apply_translate()` 要跑物理帧、要读 `profile` /
## 机头 / 锁定目标，测里没法直接问"按 W 到底叠加了多少速度"。有了它，
## `suite_assist_drive` 就能一次钉住四档（W 降 / S·D·Q 不降）且逐条可证伪。
##
## `fwd_part` = `dir` 里属于向前推杆的那一份（即 `translate_fwd`，由 PlayerController
## 同帧写下来）。`translate_dir` 是"镜头水平前 × mv + 镜头水平右 × strafe + 世界上 × lift"
## 的合成，三个轴**两两正交** ⇒ `dir − fwd_part` 恰好是"除 W 正向外的全部"
##（后退 / 横移 / 升降一个不少）—— 这就是"只降 W"能一行写完的原因。
static func translate_offset_vec(dir: Vector3, fwd_part: Vector3, off: float) -> Vector3:
	return ((dir - fwd_part) + fwd_part * TRANSLATE_FWD_SCALE) * off


## 平移模式的**底速方向**：正向 = 沿机头；倒飞 = 沿机尾（★63-9 · D2）。
##
## 抽成静态纯函数只为**能钉住"关着时必须逐位等于今天"**：
## `reverse == false` 时原样返回 `fwd`（含每一个分量的符号与精度），
## `true` 才取反。判据 1 与它的负对照都压在这一个函数上。
static func translate_base_dir(fwd: Vector3, reverse: bool) -> Vector3:
	return -fwd if reverse else fwd


func _apply_translate(delta: float) -> void:
	fm.hovering = false
	if profile.id != SuitProfile.Id.PENELOPE: fm.super_boost = false
	var face0 := _face()
	var fwd := -global_transform.basis.z
	if face0 != null and is_instance_valid(face0):
		# 朝向目标：底速跟**全 3D 机头**（敌机在高处就斜着爬过去，不减速）
		fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3.FORWARD
	else:
		# 无目标：投影到水平面 —— 防止"Q 上升 → 机头抬 → 底速更朝上"的正反馈
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3.FORWARD
	# ★63-9 · D2：底速方向 = `fwd`（正向）或 `-fwd`（倒飞）。
	# ⚠️ 只动**速度**层 —— 机头姿态写在下面那一段（`global_transform`），这里不碰。
	var base_dir := translate_base_dir(fwd, translate_reverse)
	var auto_speed := profile.player_boost_speed() if fm.boosting \
		else profile.player_top_speed()
	if fm.super_boost: auto_speed *= FlightModel.SUPER_BOOST_MULT
	# ---- 闪避冲刺：消费点按请求（槽里有气、不在窗口中、限制条够才给）----
	if _qb_pending:
		_qb_pending = false
		if fm.boosting and _qb_timer <= 0.0 and can_quick_boost():
			_qb_timer = QB_TIME
			# 无输入 ⇒ 闪避朝**当前位移方向**（倒飞时就是机尾方向 = `base_dir`）。
			_qb_dir = translate_dir.normalized() \
				if translate_dir.length_squared() > 0.0001 else base_dir
			# 起跑信号（批 11）：只在这一处、只在真的跑起来时发 ——
			# 玩家侧接它做镜头脉冲 + 喷口爆闪（AI / 测试不接，天然无副作用）。
			_qb_dir = _penelope_dash_direction(_qb_dir)
			quick_boost_started.emit(_qb_dir)
			# 左右冲刺 → 机身转身一圈（轮 33）。方向在起手这一帧定死，
			# 之后由 `_dash_spin_t` 自己走完窗口 —— 中途不再重判（闪避是一次 commit）。
			_start_dash_spin(_qb_dir)
			_start_dash_anim(_qb_dir)
			if has_jet_gauge():
				jet_left = maxf(jet_left - QB_JET_COST, 0.0)
			# 冲刺限制条扣费（全部 ACE 机，仅阿利宙斯巡航豁免）：扣到见底 = 烧干 → 进 CD。
			# ⚠️ 扣费取 min(cost, 剩余)：最后一次"零头冲刺"把条正好烧到 0，
			# 这就是"满条 6 次整 + 第 7 次点按烧干"那个 6-7 次的手感来源。
			if has_dash_limit():
				dash_charge = maxf(dash_charge - QB_CHARGE_COST / (3.0 if profile.id==SuitProfile.Id.ZORIN_SOUL else 1.0), 0.0)
				if dash_charge <= 0.0001:
					dash_charge = 0.0
					dash_cd = QB_CHARGE_CD
	_qb_timer = maxf(_qb_timer - delta, 0.0)
	translate_dash = _qb_timer > 0.0
	if not translate_dash:
		# 窗口结束 ⇒ 交出动画方向，状态机随即回待机（没有待机动作的机体归位到 rest）。
		_dash_anim_dir = ""
	# ---- 转身角推进（轮 33）----
	# 与 `_qb_timer` 同起同落 ⇒ 窗口结束**恰好**是 360°（≡ 0°），不会残留半个角度。
	# 走 smoothstep 而不是线性：线性的话起手那一帧角速度就从 0 跳到 800°/s、
	# 收尾又是硬刹，转身会读成"卡了一下"。两端缓入缓出最顺。
	_dash_spin_t = maxf(_dash_spin_t - delta, 0.0)
	if _dash_spin_t <= 0.0 or not model_visible():
		# 窗口结束 / 模型不可见（座舱视角 / 阵亡）→ 归零。
		if _dash_spin_t <= 0.0:
			_dash_spin_dir = 0.0
		dash_spin = 0.0
	else:
		var spin_p := 1.0 - _dash_spin_t / QB_TIME
		dash_spin = TAU * _dash_spin_dir * (spin_p * spin_p * (3.0 - 2.0 * spin_p))
	# ---- 冲刺限制条回充 ----
	# CD 优先：烧干后的长冷却既不能闪也不回充；CD 结束从 0 慢慢回。
	# 闪避窗口内不回充（那一秒你在冲刺，不是在喘气）。
	if has_dash_limit():
		if dash_cd > 0.0:
			dash_cd = maxf(dash_cd - delta, 0.0)
		elif not translate_dash and dash_charge < 1.0:
			dash_charge = minf(dash_charge + QB_CHARGE_REGEN * delta, 1.0)
	var target: Vector3
	var corr := Vector3.ZERO
	var resp := TRANSLATE_RESPONSE
	if translate_dash:
		# 窗口内：全力朝闪避方向直冲，不吃平移修正（闪避是 commit 的一下）。
		# 起跑 0.12 s 是**爆冲段**（QB_BURST_RESPONSE）—— 突进感来自"当场砸到位"；
		# 之后回落 QB_RESPONSE 稳住冲刺速度，窗口结束再回落底速。
		target = _qb_dir * (profile.player_boost_speed() * QB_SPEED_MULT)
		resp = QB_BURST_RESPONSE \
			if _qb_timer > QB_TIME - QB_BURST_TIME else QB_RESPONSE
	else:
		# 自动飞行底速 + 平移修正
		target = base_dir * auto_speed
		if translate_dir != Vector3.ZERO:
			# W（向前）那一份单独降档（见 `TRANSLATE_FWD_SCALE`）—— 后退 / 横移 / 升降
			# 仍按满权重。`translate_fwd == ZERO`（按 S / 只横移 / 只升降）时这一行
			# 逐位等于旧的 `translate_dir * off`。
			corr = translate_offset_vec(translate_dir, translate_fwd,
				profile.player_top_speed() * TRANSLATE_OFFSET)
			target += corr
	# ---- 机头朝向用的**速度参考**（★63-9 · D2）----
	#
	# 无目标时机头追"速度矢量"（见下面那一段）。倒飞时真实速度是反的：
	# 直接追它 ⇒「机头追速度」与「底速沿机头」互相咬成**每帧 180° 的自旋**。
	# 改用**等效正向速度** = 把底速那一份换回正向、平移修正原样保留 ⇒
	#   ① 无输入时方向不变 ⇒ 机头是**不动点**（不会自己转）；
	#   ② 按 A/D 时转向增益与正向一致（修正/底速 的比值没变）。
	# ⚠️ 正向（`translate_reverse == false`）时 `vref` 就是 `fm.velocity`
	#    本身 ⇒ 下面那一段逐位等于改动前。
	var vref := fm.velocity
	if translate_reverse:
		vref = target if translate_dash else (fwd * auto_speed + corr)
	fm.velocity = fm.velocity.lerp(target, 1.0 - exp(-resp * delta))
	fm.speed = fm.velocity.length()
	if _before_flight_move(delta):
		vref = -fm.velocity if translate_reverse else fm.velocity
	# ---- 机头朝向（二调 2026-09-22）----
	# **有锁定目标 → 机头持续转向目标**（用户："不断使玩家机体朝向被锁定的
	# 敌方机体"）。底速沿机头 → 自动朝敌机飞；WASD 横移变绕圈缠斗。
	# **无目标 → 机头跟速度矢量**（旧行为，追尾镜头看着要去的方向）。
	var want: Basis
	var face := _face()
	if face != null and is_instance_valid(face):
		var to_t := face.global_position - global_position
		if to_t.length() > 1.0:
			want = FlightFrame.facing(to_t,global_basis.rotated(global_basis.z,-_bank_sm),Vector3.UP,delta)
		else:
			want = global_basis
	else:
		var flat := Vector3(vref.x, 0.0, vref.z)
		if flat.length() > 8.0:
			want = Basis.looking_at(flat.normalized(), Vector3.UP)
			# 垂直速度 → 机头俯仰：+0.8 的系数是"看得见在爬/在扎"又不至于倒扣的最小值
			var pitch := clampf(fm.velocity.y / maxf(fm.speed, 1.0) * 0.8, -0.45, 0.45)
			want = want.rotated(want.x, pitch)
		else:
			want = global_transform.basis
	# ---- 转弯侧倾（批 11：王牌空战式压坡转弯）----
	# ① 按机头**偏航角速率**压坡：左转左压、右转右压（cross.y 的符号在
	#    "水平朝向"那一节验证过：左转 > 0，而绕**后轴**正角度 = 左压坡，正好同号）。
	# ② 横移修正（A/D）朝移动方向再压一点 —— 原地平飞横移也看得见"机身在响应"。
	# 只改 want 的滚转分量（绕 want.z 旋转不动机头方向），速度合成与锁定判定全不受影响。
	var cur_flat := Vector3(
		-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
	var bank_target := 0.0
	if _prev_flat_fwd.length_squared() > 0.0001 and cur_flat.length_squared() > 0.0001:
		var denom := _prev_flat_fwd.length() * cur_flat.length()
		var s := clampf(_prev_flat_fwd.cross(cur_flat).y / denom, -1.0, 1.0)
		var yaw_rate := asin(s) / maxf(delta, 0.0001)
		bank_target = clampf(yaw_rate * ASSIST_BANK_GAIN, -ASSIST_BANK_MAX, ASSIST_BANK_MAX)
	_prev_flat_fwd = cur_flat
	if translate_dir.length_squared() > 0.0001:
		var lat := global_transform.basis.x.normalized().dot(translate_dir)
		bank_target = clampf(bank_target - lat * ASSIST_BANK_STRAFE,
			-ASSIST_BANK_MAX, ASSIST_BANK_MAX)
	_bank_sm = lerpf(_bank_sm, bank_target, 1.0 - exp(-6.0 * delta))
	if absf(_bank_sm) > 0.001:
		want = want.rotated(want.z, _bank_sm*smoothstep(0.05,0.4,cur_flat.length()))
	global_transform = Transform3D(
		global_transform.basis.slerp(want.orthonormalized(),
			1.0 - exp(-6.0 * delta)).orthonormalized(),
		global_position)
	velocity = fm.velocity
	combat_buffs.scale_motion(self)
	melee_guard.limit(self)
	move_and_slide()
	_check_collisions()
	_check_ceiling()


func _check_collisions() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i).get_collider()
		if col == self:
			continue
		if col is FlightBody:
			var other := col as FlightBody
			if not other.alive:
				continue
			if ram_cooldown > 0.0 or other.ram_cooldown > 0.0:
				continue
			# ★63-25：任一方在军刀窗口内 ⇒ **整条接触跳过**（不结算，**也不写冷却**）。
			#
			# ⚠️⚠️ **位置是这一条的全部要点**：必须在**写 `ram_cooldown` 之前**拦。
			#    若改成在下游 `take_damage()` 里 return，冷却**已经写上了** ⇒ 症状是
			#    「出了军刀窗口之后贴脸撞上去，1 秒内也不掉血」—— 用户要的「其他时候正常」
			#    就不成立，而且**不报错、日志里什么都看不到**。
			#
			# ⚠️ 判据含 `other`（不是「只免在窗口内那一方」）：两机贴在一起本来就不该
			#    单方面吃亏；相杀场面下两人**都在**窗口内，只免一方会退化成不对称。
			if in_ram_guard() or other.in_ram_guard():
				continue
			ram_cooldown = RAM_COOLDOWN
			other.ram_cooldown = RAM_COOLDOWN
			other.take_damage(RAM_DAMAGE, self, Damage.Type.RAM)
			take_damage(RAM_DAMAGE, other, Damage.Type.RAM)
		else:
			if col is Node and col.is_in_group("avoidance_ground") and not map_ground_damaging():
				continue # Solid contact slides normally; no damage or destruction on Axis.
			if col is Node and col.is_in_group("avoidance_ground") and _prevent_ground_crash():
				continue
			# WORLD 层的实体：地表 / 楼体 / 残骸 / 轨道图上的人造物。
			# 文案随地图走（`map_has_ground()`）—— 轨道图上撞到的一定是**人造物**
			#（那里没有地表几何），写"撞地"会让人以为是地图坏了。
			destroy(null, "撞地" if map_has_ground() else "撞毁")
			return


func _tick_weapons(delta: float) -> void:
	flash_blind_left=maxf(0.0,flash_blind_left-delta)
	thunder_slow_left=maxf(0,thunder_slow_left-delta);thunder_lock_left=maxf(0,thunder_lock_left-delta)
	if thunderbolt_systems!=null:thunderbolt_systems.step(delta)
	if sazabi_systems!=null:sazabi_systems.step(delta)
	_auto_reload_empty_weapons()
	if flare_reload_left > 0.0:
		flare_reload_left = maxf(0.0,flare_reload_left-delta)
		if flare_reload_left <= 0.0: flare_count = flare_mag_size()
	bazooka_cd = maxf(0.0, bazooka_cd - delta)
	grapple_cd = maxf(0.0, grapple_cd - delta)
	if bazooka_reload_left > 0.0:
		bazooka_reload_left = maxf(0.0, bazooka_reload_left - delta)
		if bazooka_reload_left <= 0.0:
			bazooka_mag = GP03_BAZOOKA_MAG
	wire_cd_left = maxf(0.0,wire_cd_left-delta)
	gun_cooldown = maxf(gun_cooldown - delta, 0.0)
	rifle_cooldown = maxf(rifle_cooldown - delta, 0.0)
	# ★ N56 收枪窗口计时：冷却**归零之后**才累计（见 `STOW_DELAY`）。
	#   开火那一帧 `rifle_cooldown` 被写成 `profile.rifle_interval` ⇒ 下一帧这里自动归零，
	#   所以不需要在开火处另写一行"重置窗口"（少一个真源）。
	stow_idle = stow_idle + delta if rifle_cooldown <= 0.0 else 0.0
	# 大炮冷却与其它冷却**同一处**递减：它是"这个动作还要等多久"这一类里的一个，
	# 散到别处去就会出现"按了没反应、HUD 却在倒数"（或者反过来）。
	cannon_cd_left = maxf(cannon_cd_left - delta, 0.0)
	funnel_cooldown = maxf(funnel_cooldown - delta, 0.0)
	saber_cooldown = maxf(saber_cooldown - delta, 0.0)
	flare_cooldown = maxf(flare_cooldown - delta, 0.0)
	discard_cooldown = maxf(discard_cooldown - delta, 0.0)
	form_cooldown = maxf(form_cooldown - delta, 0.0)
	flare_active = maxf(flare_active - delta, 0.0)
	_tick_shield(delta)
	ram_cooldown = maxf(ram_cooldown - delta, 0.0)
	# ★63-25：军刀撞击豁免余量。与 `ram_cooldown` **同一处**递减 —— 它们是一类东西
	#（「这个状态还要持续多久」），散到别处就会出现「余量走完了却还在免」或反过来。
	ram_guard_left = maxf(ram_guard_left - delta, 0.0)
	# 脱板失能倒计时（1.2 飞行踏板）：归零之前不能开火，见 `is_staggered()`。
	# 放在这里是因为它和冷却是一类东西 —— "这个动作还要等多久"。
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)
	if rifle_reloading:
		reload_timer -= delta * combat_buffs.reload_rate()
		if reload_timer <= 0.0:
			rifle_reloading = false
			reload_timer = 0.0
			rifle_mag = profile.rifle_magazine
	# ---- 浮游导弹换弹（批 14）：打空自动换，换完满夹 ----
	if profile != null and profile.id == SuitProfile.Id.GP03D and funnel_reload_left > 0.0:
		funnel_reload_left -= delta
		while funnel_reload_left <= 0.0 and funnel_count < funnel_mag_size:
			funnel_count = mini(funnel_count + 108, funnel_mag_size)
			funnel_reload_left += 10.0
		if funnel_count >= funnel_mag_size:
			funnel_reload_left = 0.0
	elif funnel_reload_left > 0.0:
		funnel_reload_left = maxf(funnel_reload_left - delta, 0.0)
		if funnel_reload_left <= 0.0 and funnel_mag_size > 0:
			funnel_count = funnel_mag_size
	# ---- 火神炮过热（批 14）：卡住计时与冷却 ----
	# 卡住期间（vulcan_jam_left > 0）热量**不冷却**——"红着一条顶满"是过热的视觉本体；
	# 卡住时间走完才开始降温，降到 VULCAN_RESUME 以下解除过热。
	vulcan_jam_left = maxf(vulcan_jam_left - delta, 0.0)
	if not vulcan_overheated or vulcan_jam_left <= 0.0:
		vulcan_heat = maxf(vulcan_heat - VULCAN_COOL_RATE * delta, 0.0)
	if vulcan_overheated and vulcan_jam_left <= 0.0 \
			and vulcan_heat <= VULCAN_RESUME:
		vulcan_overheated = false


## 脱板失能中（1.2 飞行踏板）。**唯一的开火门禁读点**：
## 步枪 / 火神炮 / 导弹 / 军刀全部读它，别在各自的分支里各判一次。
func is_staggered() -> bool:
	return _stagger_timer > 0.0


## 失能剩余秒数（HUD 用）。
func stagger_left() -> float:
	return _stagger_timer


## 判定"现在算巡航形态"的 morph 门槛。**唯一真源**，见 `in_cruise_form()`。
##
## 取 0.5 是既有行为（N42 起）：`cruise_morph` 是 0→1 的插值，过一半就算进了巡航形态，
## 于是形态过渡动作播到一半时状态机就开始按巡航选待机 —— 那是**故意的**
##（过渡动作的末帧 = 巡航待机首帧，提前换没有跳变，但能让 0.43 s 的过渡不被白等）。
const CRUISE_FORM_THRESHOLD := 0.5


## 巡航变形的 morph 值（0 = 正常形态，1 = 巡航形态）。HUD 与测试读它。
##
## ⚠️ 它的语义是**形态进度**，不是"morph 已写到几个网格"。修 `_tick_cruise_morph()`
## 之后，没有 blend shape 的模型（新资产）也照常推进这个值 —— 因为
## `ModelAnimFSM.set_form()` 与 `full_burst_action()` 都靠它判形态。
var cruise_morph := 0.0
var _morph_nodes: Array[MeshInstance3D] = []
## 是否**扫完过**一次的形态网格。
##
## 存在的理由：新资产 `blend shape = 0`，`_morph_nodes` 永远是空 —— 没有这个标记，
## `_tick_cruise_morph()` 就得**每帧**遍历 203 个 `MeshInstance3D` 去确认"还是没有"。
## 一场战斗 60 fps × 几分钟，这是白烧的。
var _morph_collected := false


## 收集带 blend shape 的网格（柯西那块模型只有一个，但写成循环更耐改）。
##
## ⚠️ 只扫**一次**（成功后置 `_morph_collected`）。`model_root` 还没就绪时会
## **保留未扫状态**，下次 tick 再试 —— 这是唯一需要重扫的情形。
func _collect_morph_nodes() -> void:
	_morph_nodes.clear()
	_morph_collected = false
	if profile == null or not profile.cruise_morph or model_root == null \
			or not is_instance_valid(model_root):
		return
	for c: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		# ⚠️ `get_blend_shape_count()` 只存在于 **ArrayMesh**；BoxMesh / CylinderMesh
		# 这些自带图元没有这个方法（调用会直接报 "Nonexistent function"）。
		# 占位骨架里全是图元，所以必须先判类型。
		var am := (mi.mesh as ArrayMesh) if mi != null else null
		if am != null and am.get_blend_shape_count() > 0:
			_morph_nodes.append(mi)
	_morph_collected = true


## 巡航变形动画：**按住 Shift 正向播放，松开倒放**（用户要求）。
##
## 这里刻意不做"播放中锁状态"：插值值随时跟着按键走，
## 于是"动画没播完就松开"自然是"从当前进度倒放回去"，
## 中途反复按放也不会跳帧 —— 这比写一个"动画状态机 + 反向播放"简单得多，也更符合手感。
## 悬停（Ctrl）与 Shift 互斥（和飞行模型里的优先级一致），所以悬停时也往回收。
##
## ★ 2026-09-26 修一条**静默失效**：插值进度与"输出目标"必须解耦。
##
## 老写法把 `cruise_morph = move_toward(...)` 放在
## `if _morph_nodes.is_empty(): return` **之后**，于是新资产（blend shape = 0）
## 的 `cruise_morph` **永远停在 0.0**。后果不止"形态不显示"：
## `_tick_model_anim()` 里 `model_fsm.set_form(cruise_morph >= 0.5)` 也恒收到 false
## ⇒ 连**巡航版全弹发射（`burst_cruise`）都不会被选中**，一路播常态版。
## 全程不报任何错 —— 玩家的感受是"按了 Shift 什么都没变"。
##
## 现在两条输出并列，谁在场谁生效：
##   ① blend shape —— 老资产的通路（`cruise_on` morph，来自参考模型形态）；
##   ② 骨骼形态层 —— 新资产的通路。**这一层自身还有两档**（在
##      `_setup_cruise_form()` 里二选一）：**曲线层**（`FormCurveModifier`，
##      N42·十三，沿 `xi_cruise_on.glb` 的变形曲线走 ⇒ 6 根同步展开）优先；
##      曲线层建不起来（没有曲线源 / 端点对不上 / 挑不出形态骨）就**回退**
##      到**两点层**（`CruiseFormModifier`，常态→巡航匀速 slerp）。
func _tick_cruise_morph(delta: float) -> void:
	if profile == null or not profile.cruise_morph:
		return
	if model_root == null or not is_instance_valid(model_root):
		return
	# ---- 进度：**先算**，与有没有输出无关 ----
	var want := 1.0 if (fm.boosting and not fm.hovering) else 0.0
	if profile.id == SuitProfile.Id.PENELOPE and is_player:
		want = 1.0 if penelope_cruise_enabled else 0.0
	var secs := profile.cruise_morph_seconds
	# ---- 轮 34：**左右转身期间把形态压回常态**（飞行翼 / 肩甲收起）----
	#
	# 与转身**共用同一个窗口** `_dash_spin_t`（在 `_apply_translate` 里递减，
	# 本函数在 `_tick_effects` 里读 —— 顺序保证读到的是本帧已推进过的值）。
	# 用它当判据有两个好处：
	#   ① 前后 / 升降冲刺**天然不含**（`_start_dash_spin()` 那两路早退 ⇒ 它是 0）；
	#   ② 不用再抄一遍"左右还是前后"的判定 —— 抄一遍就是两处判据，迟早打架。
	#
	# 窗口走完 `want` 自动回到上面那行算出的常态逻辑 ⇒ 在巡航态里**立刻再展开**
	#（柯西走 `form_on` 0.4333 s，其余机体走 0.18 s 交叉淡入）——"先收后放"的"放"在这里，
	# 不需要任何收尾代码："在窗口内压制"本身就是全部实现。
	#
	# ⚠️ 收起必须**比默认快**（`DASH_SPIN_STOW_SECONDS`）：理由见那个常量的注释。
	if _dash_spin_t > 0.0:
		want = 0.0
		secs = minf(secs, DASH_SPIN_STOW_SECONDS)
	if not is_equal_approx(cruise_morph, want):
		var rate := 1.0 / maxf(secs, 0.05)
		cruise_morph = move_toward(cruise_morph, want, rate * delta)
	# ---- 输出①：blend shape（老资产）----
	if not _morph_collected:
		_collect_morph_nodes()
	for mi: MeshInstance3D in _morph_nodes:
		if not is_instance_valid(mi):
			continue
		var am := mi.mesh as ArrayMesh
		if am == null:
			continue
		for s in am.get_blend_shape_count():
			mi.set_blend_shape_value(s, cruise_morph)
	# ---- 输出②：骨骼形态层（新资产）----
	#
	# 曲线层与两点层**互斥**（`_setup_cruise_form()` 里二选一）⇒ 两个都推一遍，
	# 另一个必是 null。两者的 `morph` 语义**逐字相同**
	#（0 = 常态 = 完全空操作，1 = 巡航形态）。
	if _form_curve != null:
		_form_curve.morph = cruise_morph
	elif _cruise_form != null:
		_cruise_form.morph = cruise_morph
	# ---- 输出③：形态骨**帧末焊**（轮 42）----
	#
	# 这里**刻意不调** `_form_weld.weld()`：本函数跑在 `_tick_effects`（`_process` 链）里，
	# 而实测写明那个时机写进去的骨会被动画覆盖（见 `FormWeld` 文件头）。
	# 焊缝挂在 **`AnimationMixer.mixer_applied`** 信号上（动画求值刚写完那一刻），
	# 由 `_weld_form_bones()` 读**同一个** `cruise_morph`。所以这里只需把进度算对。


## ---- 冲刺判据（2026-09-25 · 尾焰形态区分）----
##
## "冲刺"在玩家侧有两个入口，就是下面两个方法：
##   ① 辅助驾驶的**闪避冲刺**（QB）：平移模式下点按 Shift，`translate_dash` 在窗口内为真；
##   ② **超级加速**：阿利宙斯巡航形态 + 辅助 + 按住 Shift（`fm.super_boost`）。
## 两者互斥（平移路径会把 `super_boost` 压回 false），所以 `or` 就够。
##
## ⚠️ **别在调用方重写这两个条件。** 它现在有三个读者：
## `_tick_effects`（尾焰形态二选一 / 拖尾光条 / 起跑包络）与
## `main._update_camera_assist`（屏幕速度线的形态）。三处各写一遍就是
## "改一处漏两处"的经典来源。
func assist_dashing() -> bool:
	return translate_mode and translate_dash


func super_dashing() -> bool:
	return fm.super_boost and fm.boosting


## 本帧是否在冲刺（两者之一）。
func is_dashing() -> bool:
	return assist_dashing() or super_dashing()


## 本帧的尾焰**横风形变**（机体本地坐标）。用户原话：
##
## > "在向着不同方向冲刺的时候尾焰能不能别那么直，来点物理形变"
##
## 一条链讲完：
##   `fm.velocity`（世界）→ 转到机体本地 → 取**相对气流** `−v_local`
##   → 投影成**垂直于喷口轴**的横分量（`FX.plume_bend_vector`）
##   → 按"横分量 ÷ `player_boost_speed()`"定量 → 一阶平滑。
##
## ⚠️ **归一化用 `profile.player_boost_speed()`，不是写死的数**：那个值已经含
## `SPEED_REAL_MULT` 与机体速度系数 ⇒ 以后整体提速时，"满弯对应的横风"自动跟着走。
## 写死一个 m/s 就是又造了一个"改速度时不会跟着动"的真源
##（`suit_profile.gd` 顶部那条"整件事只有一个旋钮"的规矩）。
##
## ⚠️ `profile == null` 必须守：测试与工具里都有"没有档案"的机（走占位模型那条），
## `null.player_boost_speed()` 会直接抛。
##
## ⚠️ 速度读 `fm.velocity` 而**不是** `velocity`：前者是气动每帧写的那份权威值，
## 后者是 `move_and_slide()` 之后由引擎填的东西（见 `_apply_translate` 末尾的
## "`fm.speed` / `fm.velocity` 必须同步写"那条注释）。这条函数在
## `_apply_flight()` **之后**跑（`_physics_process` 的顺序），所以读到的就是本帧的。
func _tick_plume_bend(delta: float) -> void:
	for item: Dictionary in _plume_fx:
		XiPlume.sync(self,item)
		PlumeMotion.sync(self,item)
	# ---- 本帧的机体本地风速（唯一读取 `fm.velocity` 的地方）----
	_plume_wind = Vector3.ZERO
	if profile != null:
		# 相对气流的**方向**：空气相对机体在动 ⇒ 方向是 −v。
		# ⚠️ 负号要写进括号里：`-Basis * v` 在 GDScript 里是"对 Basis 取负"，
		# 直接 `Parse Error: Invalid operand of type "Basis" for unary operator`。
		# 而且变量要显式标 `Vector3` —— `Basis * Vector3` 的结果类型推不出来
		#（不标就是 `Cannot infer the type of "wind"`，同样是编译期红）。
		_plume_wind = global_transform.basis.inverse() * (-fm.velocity)
	var k := 1.0 - exp(-PLUME_BEND_RESPONSE * delta)
	# ---- ① 机尾那一路（以及所有"没量过朝向"的口）：轴线 = `PLUME_AXIS` ----
	# ⚠️ 这一段与轮 17 **逐位等价**（同一个 `want`、同一个 lerp 系数）—— 别顺手改，
	# 第 ⑫ 节那一整组断言就是照它写的。
	_plume_bend = _plume_bend.lerp(_plume_bend_want(PLUME_AXIS), k)
	# 收敛到零就别留残渣：否则"停下之后"那条指数尾巴会永远挂着一个极小的弯，
	# 既让"静止 ⇒ 不弯"这条断言变成"近似成立"，也白刷 30 多个材质的 uniform。
	if _plume_bend.length_squared() < 0.01:
		_plume_bend = Vector3.ZERO
	# ---- ② 逐喷口：**按各口自己的轴线**投影（轮 18）----
	#
	# 为什么不能直接复用上面那一条：横风形变的头一步是"把沿轴分量丢掉"
	#（`FX.plume_bend_vector`）。佩涅罗佩那两个口的轴线离 +Z 差 **69°** ——
	# 拿 +Z 去投影，剩下的所谓"横分量"里会混进一大截沿该口轴线的东西，
	# 于是弯的方向不是"被风吹"的方向，而是"被风按错轴线吹"的方向。
	#
	# 状态挂在 `item["bend"]` 上（**逐口一份**），只给"轴线 ≠ +Z"的口留 ——
	# 轴线就是 +Z 的口走 `item.get("bend", _plume_bend)` 的默认值，
	# 复用机尾那一条 ⇒ 柯西 / 阿利宙斯那两支与轮 17 **逐位相同**。
	for item: Dictionary in _plume_fx:
		var axis: Vector3 = item.get("axis", PLUME_AXIS)
		if axis.is_equal_approx(PLUME_AXIS):
			item["bend"] = _plume_bend
			continue
		var b: Vector3 = item.get("bend", Vector3.ZERO)
		var wanted := _plume_bend_want(axis)
		var response := k
		if PenelopePlume.supports(profile):
			wanted = wanted.limit_length(PenelopePlume.MAX_BEND)
			response = 1.0-exp(-6.0*delta)
		if PlumeMotion.maneuver_trim(profile) and wanted.is_zero_approx():
			response = 1.0-exp(-18.0*delta)
		b = b.lerp(wanted, response)
		if b.length_squared() < 0.01:
			b = Vector3.ZERO
		item["bend"] = b


## "按 `axis` 这条轴线算出来的横风加速度"（未平滑；无副作用）。
##
## 轮 17 的推导整段搬进来、一个字没改，只是把轴线从写死的 `PLUME_AXIS` 变成参数 ——
## 好让逐喷口那条路能按**自己的**轴线算（见 `_tick_plume_bend()` 的第 ② 段）。
func _plume_bend_want(axis: Vector3) -> Vector3:
	if profile == null:
		return Vector3.ZERO
	if PlumeMotion.maneuver_trim(profile):
		return PlumeMotion.maneuver_bend(_plume_wind,axis,profile.player_boost_speed(),PLUME_BEND_ACCEL)
	var cross: Vector3 = FX.plume_bend_vector(_plume_wind, axis)
	var speed := cross.length()
	if speed <= 0.01:
		return Vector3.ZERO
	var ref := maxf(profile.player_boost_speed(), 1.0)
	var amount := clampf(speed / ref, 0.0, 1.0)
	# ⚠️ 符号：加速度**沿气流下游**（粒子是被风吹着走的），所以是 `+cross`。
	# 写反了屏幕上就是"焰迎着风翘起来"—— 看着也有形变，只是方向是错的，
	# 所以第 ⑫ 节专门钉了"横移向右 ⇒ 焰往左偏"这一条。
	return cross * (PLUME_BEND_ACCEL * amount / speed)


func own_propulsion_enabled() -> bool:
	var board := pedal_owner()
	return board == null


## Torque of each measured nozzle chooses which RCS jets respond to the controls.
func neue_nozzle_drive(at: Vector3, exhaust: Vector3) -> float:
	var torque := (at-model_bounds.get_center()).cross(-exhaust).normalized()
	var steering := maxf(0.0,torque.dot(control_input))
	var cruise := maxf(0.0,exhaust.dot(Vector3.BACK)) * fm.throttle
	return clampf(maxf(steering,cruise),0.0,1.0)


func _sync_thunderbolt_plumes() -> void:
	if profile == null or not SuitProfile.is_thunderbolt(profile.id):return
	for index in _plume_fx.size():
		var slot := "plume"+str(index)
		if not _model_mounts.has(slot):continue
		var mount:Node3D=_model_mounts[slot]
		if not is_instance_valid(mount):continue
		var position := to_local(mount.global_position)
		var live_axis := (global_basis.inverse()*mount.global_basis.z).normalized()
		var original := profile.plume_dir(index)
		if original.length_squared()<.25:original=PLUME_AXIS
		var rotation := Basis(Quaternion(original.normalized(),live_axis))
		var item:Dictionary=_plume_fx[index]
		item["local_at"]=position;item["axis"]=live_axis;item["plume_basis"]=rotation
		for key in ["fx","glow","boost","ab","dash"]:
			var effect:Node3D=item.get(key) as Node3D
			if is_instance_valid(effect):effect.position=position;effect.basis=rotation

func _tick_effects(delta: float) -> void:
	_tick_model_flash(delta)
	_tick_cruise_morph(delta)
	_tick_saber_visual(delta)
	_tick_model_anim(delta)
	_tick_repair(delta)
	# ---- 拖尾光条（2026-09-21，用户要求）----
	#
	# 只在两处点亮：**闪避冲刺**（辅助驾驶 + Shift 点按，窗口内）与**超级加速**
	# （阿利宙斯巡航形态辅助 + Shift）。普通加力（不辅助时按 Shift）维持
	# 原有的加力尾焰粒子，不叠光条 —— "闪避/超级"必须和"普通加速"看得出来不一样。
	# ---- 冲刺状态（本帧到底"在不在冲刺"）----
	#
	# 后面三处读的都是同一份判断：拖尾光条 / 尾焰形态二选一 / 冲刺的起跑包络。
	# 判据本身收在 `assist_dashing()` / `super_dashing()` 里，屏幕速度线
	#（`main._update_camera_assist`）读的是同一对 —— **一处改，两处对**。
	var assist_dash := assist_dashing()
	var super_dash := super_dashing()
	var dashing := assist_dash or super_dash
	if _boost_trail != null and profile != null:
		var tip := global_position - forward() * (model_bounds.size.z * 0.42)
		var trail_on := false
		if translate_mode:
			trail_on = assist_dash and fm.speed > profile.player_top_speed() * 0.35
		elif super_dash:
			trail_on = true
		_boost_trail.push(tip, trail_on and own_propulsion_enabled(), delta)
	# ---- 尾焰**形态二选一**（2026-09-25，用户要求"两种形态要做区分"）----
	#
	# | 什么时候 | 走哪一形 |
	# |---|---|
	# | 普通加力（不辅助时按住 Shift） | **形态 A** `Afterburner`：短、粗、散开的蓝锥 |
	# | 辅助驾驶的冲刺 | **形态 B** `AfterburnerDash` + `DashRings`：长、细、拉丝的白束 |
	#
	# "辅助驾驶的冲刺"有两个入口，都算：
	#   ① **闪避冲刺 QB**：平移模式下点按 Shift，`translate_dash` 置位的 0.45 s 窗口；
	#   ② **超级加速**：阿利宙斯巡航形态 + 辅助 + 按住 Shift（`fm.super_boost`）。
	# 两者由 `PlayerController` 互斥地维护（平移路径会把 `super_boost` 压回 false），
	# 所以这里一个 `or` 就够。
	#
	# ⚠️ 两形**永不同时 emitting**：同时亮 = 屏幕上同时有"一团散火"和"一条白束"，
	# 那是穿帮不是丰富。
	# ⚠️ `profile.engine_plumes` 非空时**机尾那一套退场** —— 尾焰已按喷口铺开
	#（见下面 `_plume_fx` 那一段），机尾再留一团就是"两处同时喷"。
	#   喷口数 ≤ `PLUME_SHAPE_MAX_NOZZLES`（柯西 / 佩涅罗佩）：**两形照样区分**，
	#   只是每形各有 N 套（逐喷口），由下面 `_plume_fx` 那一段逐口开关；
	#   喷口数更多（阿利宙斯巡航 16 个）：两形都退场，每口只留一条加力焰 ——
	#   每个口直径才 1 m 上下，细束和粗锥在那个尺度上根本分不出来。
	var own_propulsion := own_propulsion_enabled()
	var single_plume := _plume_fx.is_empty() and own_propulsion
	if _afterburner_fx != null:
		# 多喷口形态（阿利宙斯巡航）下单点尾焰退场：加力焰分散在每个喷口
		#（用户 2026-09-22 指定，见 `_rebuild_plumes` 里的说明）。
		_afterburner_fx.emitting = fm.boosting and not dashing and single_plume
	if _dash_fx != null:
		_dash_fx.emitting = dashing and single_plume
	if _dash_rings != null:
		_dash_rings.emitting = dashing and single_plume
	# ---- 冲刺的**起跑包络**（细节层）----
	#
	# QB 窗口的头 `QB_BURST_TIME`（0.12 s）是**爆冲段**（速度追随率也是另一档，
	# 见 `_apply_translate`）—— 焰量与粒子速度都在这一段拉满，之后回落到 0.6 档。
	# 观感上就是"顶出去的那一记最狠"。超级加速没有窗口计时，恒 1.0。
	#
	# ⚠️ **这一份包络要在两个消费者之间共享**：机尾那一路（`_dash_fx` / `_dash_rings`）
	# 与**逐喷口**那一路（下面 `item["dash"]`）。所以在最前面算**一次** ——
	# 分两处各算一遍就是"改一处漏一处"（其中一处会一直用旧档位，而断言只盯了另一处）。
	var env := 1.0
	if assist_dash:
		env = 1.0 if _qb_timer > QB_TIME - QB_BURST_TIME else 0.6
	if _dash_fx != null and is_instance_valid(_dash_fx):
		_dash_fx.amount_ratio = env
		# 爆冲段的粒子也飞得更快 —— 与速度包络同向，读数才对得上。
		_dash_fx.speed_scale = 1.25 if env >= 1.0 else 1.0
	if _dash_rings != null and is_instance_valid(_dash_rings):
		_dash_rings.amount_ratio = 1.0 if env >= 1.0 else 0.55
	if _afterburner_fx != null:
		# 形态 A 恒满量（它是"一直在烧"的常态）。
		_afterburner_fx.amount_ratio = 1.0
	# ---- 尾焰的**横风形变**（轮 17）----
	#
	# 用户原话：「在向着不同方向冲刺的时候尾焰能不能别那么直，来点物理形变」。
	# 一份 `_plume_bend` 分给**所有**尾焰发射器 —— 与包络 `env` 同一个道理：
	# 分处各算一遍就是"改一处漏一处"（其中一处会一直用旧值，而断言只盯了另一处）。
	# 逐步推导见 `_tick_plume_bend()`，几何见 `FX.plume_bend_vector()`。
	_tick_plume_bend(delta)
	# 机尾那一路（`engine_plumes` 为空：阿利宙斯常态、占位机、其它机体）。
	var single_bend := _plume_bend
	if _plume_fx.is_empty() and model_pivot != null:
		single_bend = model_pivot.basis.inverse()*single_bend
	FX.set_plume_bend(_afterburner_fx, single_bend)
	FX.set_plume_bend(_dash_fx, single_bend)
	# ⚠️ 环**不能**跟束拿同一个数：环的轴向速度只有束的 0.46 倍，
	# 同一个加速度下会被吹歪 4.7 倍 ⇒ 飞出束外。系数推导见 `FX.PLUME_RING_BEND_RATIO`。
	FX.set_plume_bend(_dash_rings, single_bend * FX.PLUME_RING_BEND_RATIO)
	# ---- 多喷口（阿利宙斯巡航态 16 个；柯西 / 佩涅罗佩各 2 个）----
	#
	# 尾焰：**只要在推进就喷**（不是只在加速时）。用户要的是"喷射轨迹"，
	# 而这些喷口本来就一直在工作 —— 只在加速时才亮会显得引擎是坏的。
	# 光晕：平时也亮（"这个喷口是活的"），加速时更亮。
	# 形状层：喷口数 ≤ `PLUME_SHAPE_MAX_NOZZLES` 时**逐喷口**有 `ab`/`dash` 两形
	#（与机尾那一路**同一套二选一、同一份包络**）；超过上限时只有一条 `boost` 加力焰。
	if not _plume_fx.is_empty():
		var jetting := own_propulsion and fm.throttle > 0.05 and not fm.hovering
		for item: Dictionary in _plume_fx:
			var drive := 1.0
			if profile.id == SuitProfile.Id.NEUE_ZIEL:
				drive = neue_nozzle_drive(item["local_at"],item["axis"])
			if profile.id == SuitProfile.Id.GP03S:
				var nozzle := _plume_fx.find(item)
				var pos := rig_anchor("plume"+str(nozzle))
				item["local_at"] = pos
				for key in ["fx","glow","boost","ab","dash"]:
					var effect: Node3D = item.get(key) as Node3D
					if is_instance_valid(effect):
						effect.position = pos
			var glow := item.get("glow") as MeshInstance3D
			if is_instance_valid(glow):
				glow.visible = own_propulsion and drive > 0.05
			var fx := item.get("fx") as GPUParticles3D
			if fx != null and is_instance_valid(fx):
				fx.emitting = jetting and drive > 0.05
				fx.amount_ratio = drive
			var pa := item.get("ab") as GPUParticles3D
			if pa != null and is_instance_valid(pa):
				pa.emitting = own_propulsion and drive > 0.05 and fm.boosting and not dashing
				pa.amount_ratio = drive
			var pd := item.get("dash") as GPUParticles3D
			if pd != null and is_instance_valid(pd):
				pd.emitting = own_propulsion and drive > 0.05 and dashing
				pd.amount_ratio = env * drive
				pd.speed_scale = 1.25 if env >= 1.0 else 1.0
			var bf := item.get("boost") as GPUParticles3D
			if bf != null and is_instance_valid(bf):
				bf.emitting = own_propulsion and drive > 0.05 and (fm.boosting or control_input.length_squared() > 0.01)
				bf.amount_ratio = drive
				# 超级加速时每个喷口的焰也**飞得更快**：形态不换（见上面的说明），
				# 靠速度差把"这一记是冲刺"说出来。
				bf.speed_scale = 1.7 if super_dash else 1.0
			# ---- 形状层的三个逐个吃横风形变 ----
			# `fx`（尾气）**不吃**：它是世界空间的烟，给它喂机体本地的 `gravity`
			# 是坐标系错误。三条理由写在 `FX.set_plume_bend()` 后面那段。
			#
			# ⚠️ 取**本口那一份**（`_tick_plume_bend()` 第 ② 段按该口轴线算的），
			# 不是机尾那一条。轴线就是 +Z 的口没有 `"bend"` 键 ⇒ 默认值兜到
			# `_plume_bend`，于是它们与轮 17 **逐位相同**。
			var bend: Vector3 = item.get("bend", _plume_bend)
			if item.has("xi_basis"): bend = item["xi_basis"].inverse()*bend
			elif item.has("plume_basis"): bend = item["plume_basis"].inverse()*bend
			FX.set_plume_bend(pa, bend)
			FX.set_plume_bend(pd, bend)
			FX.set_plume_bend(bf, bend)
			if PenelopePlume.supports(profile):
				PenelopePlume.update(item,jetting,fm.boosting,dashing,delta)
		if _plume_mat != null:
			# 平时很暗（只是"这个喷口是活的"），加速时亮一档，超级加速再亮一档。
			# 绝对值都不高：16 个加色叠加，单个给亮就会糊成一片。
			if super_dash:
				_plume_mat.emission_energy_multiplier = 1.95
			elif fm.boosting:
				_plume_mat.emission_energy_multiplier = 1.25
			else:
				_plume_mat.emission_energy_multiplier = 0.55
			if profile.id == SuitProfile.Id.GP03D:
				_plume_mat.emission_energy_multiplier *= 2.0
	_sync_cockpit_propulsion_visibility()
	if _smoke_fx != null:
		_smoke_fx.emitting = hp / maxf(max_hp, 1.0) < 0.45
	if _hit_flash > 0.0:
		_hit_flash = maxf(_hit_flash - delta * 4.0, 0.0)
		if model_root != null:
			model_root.scale = Vector3.ONE * (1.0 + _hit_flash * 0.03)
	# 悬停时把机体立起来（米诺夫斯基飞行器的悬停姿态），飞行时前倾
	var want_pitch := 0.0 if fm.hovering else flight_pitch_deg
	_hover_pose = move_toward(_hover_pose, want_pitch, delta * 90.0)
	if model_pivot != null:
		_gun_recoil_clock += delta
		var cannon_kick := 0.0
		if profile.rifle_back_mount and _model_skel == null:
			cannon_kick = -2.0 * GunMotion.recoil_at(_gun_recoil_clock,0.46)
		model_pivot.rotation_degrees = Vector3(_hover_pose + cannon_kick, 0.0, 0.0)
		if _form_weld != null and _form_weld.has_method("step_vertical_pose"):
			model_pivot.rotation_degrees.x += _form_weld.step_vertical_pose(delta)
		# Large mobile armors and rigid cruise meshes use hull trim, not humanoid knees.
		if _model_skel == null and profile.id != SuitProfile.Id.GP03S and not SuitProfile.is_thunderbolt(profile.id) and _qb_timer > 0.0:
			var dash_time := QB_TIME-_qb_timer
			var dash_local := global_basis.inverse()*_qb_dir
			var dash_weight := smoothstep(0.0,0.10,dash_time)*(1.0-smoothstep(QB_TIME-0.14,QB_TIME,dash_time))
			var hull_gain := 0.65 if profile.id == SuitProfile.Id.GP03D else 1.0
			model_pivot.rotation_degrees += Vector3(dash_local.z*7.0-dash_local.y*4.0,-dash_local.x*2.5,-dash_local.x*9.0)*dash_weight*hull_gain
		# Unskeletoned flight forms still commit the hull to the cut; GP03D alone stays level.
		if profile.id != SuitProfile.Id.GP03D and _model_skel == null and profile.id != SuitProfile.Id.GP03S and (saber_active() or _saber_visual_tail > 0.0):
			var cut_style := SaberMotion.style(profile)
			var cut_phase := SaberMotion._phase(_saber_visual_clock,cut_style)
			var lean_keys := [Vector3.ZERO,Vector3(-3,7,-4),Vector3(3,-3,2),Vector3(5,-8,5),Vector3(4,-6,4),Vector3.ZERO]
			model_pivot.rotation_degrees += lean_keys[cut_phase.a].lerp(lean_keys[cut_phase.b],cut_phase.blend)
		if profile.id == SuitProfile.Id.NEUE_ZIEL:
			# Slow inertial visual response; physical turning and aiming stay unchanged.
			var motion_target := Vector3(-control_input.x * 3.5 - (2.5 if fm.boosting else 0.0), -control_input.y * 2.0, control_input.y * 5.0 - control_input.z * 3.0)
			_neue_motion = _neue_motion.lerp(motion_target, 1.0 - exp(-2.4 * delta))
			model_pivot.rotation_degrees += _neue_motion

	# 转身（轮 33）：写在自己的层上，**不并进 `model_pivot`** —— 并进去的话
	# `rig_anchor()` 的合成式会把它算进锚点，枪口就跟着画圈了。
	# ⚠️ 绕 **Y**（机体上轴）而不是绕 Z：用户要的是"转身"（机头在水平面里扫一圈），
	# 不是绕自身长轴的桶滚 —— 这个轴选错，出图会是一台在原地翻跟头的机体。
	if spin_pivot != null and is_instance_valid(spin_pivot):
		spin_pivot.rotation_degrees = Vector3(rad_to_deg(dash_spin),0.0,0.0) if _penelope_backflip else Vector3(0.0, rad_to_deg(dash_spin), 0.0)
	var hit_angles: Vector3 = melee_hit_reaction.step(delta)
	if is_instance_valid(spin_pivot): spin_pivot.rotation_degrees += hit_angles
	# 尾部频闪：两短闪一长歇，和真飞机的防撞灯一个节奏
	if _nav_strobe != null:
		_strobe_phase = fmod(_strobe_phase + delta, 1.6)
		_nav_strobe.visible = _strobe_phase < 0.09 or (_strobe_phase > 0.20 and _strobe_phase < 0.29)
	if model_pivot != null and InputPose.supports(profile):
		model_pivot.rotation_degrees += _input_pose.step(self, delta)
	if sazabi_systems!=null:sazabi_systems.motion.step(delta)
	if _regz_motion != null: _regz_motion.step(delta)
	if _form_weld != null and _form_weld.has_method("step_motion"):
		_form_weld.step_motion(delta)
	_sync_xi_plumes()
	_sync_thunderbolt_plumes()
	PlumeMotion.sync_single(self)
	_update_engine_audio(delta)


# ============================================================ 火焰神炮（火神炮）

## ---- 火神炮过热参数（批 14，用户要求"加入过热条和cd"）----
## 每发热量。约 56 发 ≈ 3.1 s 连发（18 发/s）顶满 —— 够打完一次像样的点射。
const VULCAN_HEAT_PER_SHOT := 0.018
## 冷却速率（热量/秒）。从顶满降到可再开火（VULCAN_RESUME）约 1.3 s。
const VULCAN_COOL_RATE := 0.5
## 过热后必须降到这个热量以下才解除卡住（防"第一发就重新顶满"的循环）。
const VULCAN_RESUME := 0.35
## 过热瞬间起算的**最短**卡住秒数。加上降温段，一次过热的总代价约 2.8 s。
const VULCAN_JAM_MIN := 1.5

## 火神炮。**1.2 起是无限弹，批 14 加过热**（用户指定："火神炮也改为无限子弹，
## 但是加入过热条和cd"）—— 无限连发的代价就是热量：顶满卡住，降到阈值以下才能再打。
##
## ⚠️ 门槛读 `profile.has_vulcan()`（装没装），**不是"剩多少弹"**：
## 靶机版的古斯塔夫用 `vulcan_ammo = 0` 表示"不装武器"，把 0 当"打空了"
## 会让靶机开始还击（训练模式就变味了）。
##
## ⚠️ 玩家与 AI 共用这一条路径 —— 所以"敌方机体也改"（批 14）是自动成立的：
## AI 的点射打久了同样会过热卡住，逼它停火散热。
func fire_gun(trigger: bool, target: Node3D = null) -> bool:
	if profile != null and profile.id == SuitProfile.Id.FULL_ARMOR_TB: return false
	if weapons_locked(): return false
	if profile != null and profile.id == SuitProfile.Id.GP03S:
		return false
	if profile != null and profile.id == SuitProfile.Id.NEUE_ZIEL:
		return fire_beam(true, target) if trigger else false
	if profile != null and profile.id == SuitProfile.Id.GP03D:
		return fire_bazooka(target) if trigger else false
	if not trigger or gun_cooldown > 0.0 or projectile_container == null:
		return false
	if profile == null or not profile.has_vulcan():
		return false
	if vulcan_overheated:
		return false
	if in_transform() or is_staggered():
		return false
	gun_cooldown = profile.vulcan_interval
	_fire_vulcan_round(target)
	vulcan_heat = minf(vulcan_heat + VULCAN_HEAT_PER_SHOT, 1.0)
	if vulcan_heat >= 1.0 and not vulcan_overheated:
		vulcan_overheated = true
		vulcan_jam_left = VULCAN_JAM_MIN
	return true


## 骑板时的那门炮：**踏板的火神机枪**（1.2 用户指定："踏板要有……飞行踏板的火神机枪"）。
##
## ## 为什么在 `FlightBody` 上而不是在踏板里读输入
## 踏板只有几何与耐久，**输入全在机体侧**（玩家的在 `PlayerController`、
## AI 的在 `BanditAI`）。把"空格按住"翻译成"打踏板那门炮"放在这里，
## 两个操作者就共用同一条路径，不会各写一份。
##
## 返回是否真的打出去了。
func fire_pedal_gun(trigger: bool, target: Node3D = null) -> bool:
	if weapons_locked(): return false
	if not trigger or is_staggered():
		return false
	if not has_pedal() or projectile_container == null:
		return false
	var board := pedal_owner()
	if board == null:
		return false
	var fired := board.fire_gun(projectile_container, target)
	if fired:
		# 音效走和机体火神炮同一条资源，但**压低一点 + 更闷**（它挂在载具上）。
		Audio.play_3d("vulcan", board.global_position, -13.0, randf_range(0.78, 0.9))
		if is_player:
			Game.shots_fired += 1
			Game.gun_shots += 1
	return fired


## 打一发**机体的**火神炮（不含门禁与冷却 —— 那些在 `fire_gun()` 里判完）。
##
## 抽出来是为了让 `fire_gun()` 只负责门禁，而出膛/音效/统计这一段保持一处 ——
## 早先 `fire_pedal_gun()` 加进来时我把这段留在了 `fire_gun()` 里，
## 结果多出一个永远走不到的 `return true` 之后的死代码块。
func _fire_vulcan_round(target: Node3D = null) -> void:
	# 炮口轮流：用**自己的**计数器（弹药不再递减，见 `_gun_cycle` 的说明）
	_gun_cycle += 1
	var idx := _gun_cycle % 2
	var origin := global_transform * _vulcan_muzzle_local(idx)
	var dir := (aim_point(origin, target, false, SuitProfile.vulcan_speed()) - origin).normalized()
	dir = (dir + _spread(0.006)).normalized()
	_net_report_fire("gun", origin, dir)
	Projectile.vulcan(projectile_container, origin, dir, self,
		profile.vulcan_damage * damage_mult, Color(1.0, 0.62, 0.62, 0.95))
	# 火神炮 18 发/秒，靠 Audio 的节流表压到 ~13 发/秒并加随机音高，
	# 否则每发都放一遍会变成一堵噪音墙
	if is_player:
		Audio.play_self("vulcan", -10.0, randf_range(0.94, 1.08))
	else:
		Audio.play_3d("vulcan", global_position, -10.0, randf_range(0.94, 1.08))
	if is_player:
		Game.shots_fired += 1
		Game.gun_shots += 1
	gun_fired.emit()


## 辅助瞄准的锥角（度）。**只对玩家生效。**
##
## 需求："不希望玩家太难上手"。3D 空战里手动解提前量门槛很高 ——
## 目标每秒横移几百米，不辅助的话绝大多数玩家会一直打空，一场仗不是打 5 分钟
## 而是"打不中 5 分钟"。AI 本来就用解析法解提前量，不需要这个。
const AIM_ASSIST_SNAP_DEG := 2.5
const AIM_ASSIST_CONE_DEG := 7.0
## Global rifle balance is applied after suit, mission and upgrade damage values.
const RIFLE_DAMAGE_MULT := 0.75


## 辅助瞄准的权重：0 = 完全按机头，1 = 完全指向提前量点。
##
## 刻意做成**渐变而不是硬吸附**：越接近瞄准线拉得越多，锥角边缘归零。
## 硬吸附（进了锥就 100% 代瞄）会让玩家觉得"这不是我打的"；
## 渐变的手感是"我瞄得准，所以打得中"。
static func aim_assist_weight(angle_rad: float) -> float:
	var snap := deg_to_rad(AIM_ASSIST_SNAP_DEG)
	var cone := deg_to_rad(AIM_ASSIST_CONE_DEG)
	if angle_rad <= snap:
		return 1.0
	if angle_rad >= cone:
		return 0.0
	return 1.0 - (angle_rad - snap) / (cone - snap)


## 「辅助瞄准」的**门**：玩家是否处于「辅助驾驶」模式。
##
## 用户原话（轮 63-9 · D3）：「给光束步枪加入辅助瞄准模式，
## 辅助驾驶模式下自动开启」。
## 于是这里**不新增开关** —— 门就是辅助驾驶本身，由 `PlayerController`
## 覆写本函数返回它的 `assist_on`。新增一个独立开关会造出
## 「辅助开着、代瞄却没开」这种玩家既无法理解、
## 也无法从 HUD 上看出来的状态。
##
## ⚠️ 为什么是**覆写**而不是在这里直接读 `assist_on`：
## `assist_on` 声明在 `PlayerController` 上，`FlightBody` 里引用它是
## **解析期**错误 —— 那会让整套件编译不过、末尾的节被静默吃掉
##（本工程反复踩过的假绿）。与 `_think()` 用虚函数是同一套路。
##
## ⚠️ 这里**只判模式、不判武器**：武器门留在调用点上（`fire_beam()`
## 传 `true`、`_fire_vulcan_round()` 不传）—— 用户要的是「光束步枪」的
## 辅助瞄准，火神炮的弹道一个字节都不许动（18 发/秒的泼水武器，
## 代瞄没有意义，而改它就是「顺手动了另一个武器」，
## 属于本工程最忌讳的连带改动）。
func aim_assist_enabled() -> bool:
	return false


## 求"从某个炮口出发应该打向哪一点"。
##
## 这里解决的是一个真实存在的瞄准 bug：**方向必须从炮口算，不能从机体中心算**。
## 佩涅罗佩的炮口在机体侧前方约 10 m 处，若按中心→目标的方向发射，
## 弹道会整条平移 10 m，1000 m 外就稳定偏出命中圈 —— 玩家怎么瞄都打不中。
##
## 所以：
##   - `lead=false`（玩家）：取"机头指向 × 目标距离"上的一点，
##     两侧炮口的弹道会在准星处交汇（也就是航炮交汇/gun convergence），
##     再叠加**辅助瞄准**（见 aim_assist_weight）。
##   - `lead=true`（AI）：直接解提前量，同样从炮口起算。
## 交汇点。`beam_model` = true 走**光束**那套解算（弹道两段式，没有"一个弹速"，
## 见 `Ballistics.beam_lead_point`）；false 走经典等速拦截（机炮 / 踏板机炮）。
##
## ⚠️ `projectile_speed` 在 `beam_model = true` 时**被忽略** —— 留这个参数是为了
## 不影响既有的调用点，别为了让签名好看去改一圈调用。光束那一路改读
## **本机的 `profile.rifle_steady_speed`**（阿利宙斯的匀速弹道覆盖值，
## 见 `SuitProfile.ARIZEUS_RIFLE_STEADY_SPEED`）：提前量必须跟实际弹道同一个数，
## 否则屏幕上是匀速光柱、准星却按两段制算。
func aim_point(origin: Vector3, target: Node3D, lead: bool, projectile_speed: float,
		beam_model := false, assist := false) -> Vector3:
	if target != null and is_instance_valid(target):
		var tp := target.global_position
		var tv := _velocity_of(target)
		if lead:
			return _lead_point(origin, tp, tv, projectile_speed, beam_model)
		var dist := global_position.distance_to(tp)
		var boresight := global_position + aim_forward() * dist
		if not is_player:
			return boresight
		var lead_pt := _lead_point(origin, tp, tv, projectile_speed, beam_model)
		var to_bore := boresight - origin
		var to_lead := lead_pt - origin
		if to_bore.length_squared() < 1.0 or to_lead.length_squared() < 1.0:
			return boresight
		# ⚠️ **两处门，缺一不可**（轮 63-9 · D3a）：
		#   ① `assist` = **武器门**，由调用点给 —— 只有 `fire_beam()` 传 true；
		#   ② `aim_assist_enabled()` = **模式门**，玩家侧 = 辅助驾驶开关（AI 侧恒 false）。
		#
		# ⚠️ `deg_to_rad(...)` 这一层**不能省**：`Ballistics.angle_off_boresight()`
		# 结尾是 `return rad_to_deg(...)`（**度**），而 `aim_assist_weight()` 内部
		# 拿 `deg_to_rad(AIM_ASSIST_SNAP_DEG)` / `deg_to_rad(AIM_ASSIST_CONE_DEG)` 去比
		# （**弧度**）。少这一层包装的后果不是「拉得少一点」，
		# 而是**恒不拉**：传进来的度（哪怕 2.0）永远大于锥角
		# 0.1222 rad ⇒ `w` 恒 0.0。轮 63-9 之前这就是真实状态
		#（读数见 `tools/probe_aim_follow.gd` 第 7 节）。
		if not assist or not aim_assist_enabled():
			return boresight
		var w := aim_assist_weight(deg_to_rad(Ballistics.angle_off_boresight(to_bore, to_lead)))
		# ⚠️ 锥外（`w == 0`）时**原样返回** `boresight`，不走 `slerp`：
		# 要的是「辅助关 / 锥外 ⇒ 弹道**逐位**回到今天」，不是「差一点点」。
		if w <= 0.0:
			return boresight
		return origin + to_bore.slerp(to_lead, w)
	# 没有目标：沿**准星**平行发射。
	#
	# ⚠️ 0.6 版这里读的是 `forward()`（机头）—— 那是「鼠标还操纵机头」年代的口径：
	# 当时机头由鼠标决定，所以「弹道读机头」等价于「弹道跟鼠标」。
	# 轮 36 把鼠标改成「只管准星」之后，机头不再由鼠标决定，而这条兜底没跟着改，
	# 于是**没锁定时弹道完全不听准星**。实测（`tools/probe_aim_follow.gd`）：
	# 准星自身摆动 49.594°，而光束弹道只摆 0.000°、火神炮 0.430°；
	# 与准星夹角 24.818°、与机头夹角 0.000° ⇒ 弹道钉死在机头上。
	#
	# `aim_forward()` 在没有鼠标事件时**恒等于** `forward()`（见它自己的兜底），
	# 所以 AI / 手柄那一侧一个数都没变。
	#
	# （这里只换真源、不动几何：仍是「从炮口沿该方向平行发射」。
	#   若哪天要两管在准星上收拢，应改成 `global_position + aim_forward() * 4000.0`，
	#   与上面 `boresight` 的构造同源 —— 那是另一件事，别顺手做。）
	return origin + aim_forward() * 4000.0


## 提前量解算的分派（两种弹种的前提不同，不能混）。
func _lead_point(origin: Vector3, target_pos: Vector3, target_vel: Vector3,
		projectile_speed: float, beam_model: bool) -> Vector3:
	if beam_model:
		return Ballistics.beam_lead_point(origin, target_pos, target_vel,
			profile.rifle_steady_speed if profile != null else 0.0)
	return Ballistics.intercept_point(origin, target_pos, target_vel,
		maxf(projectile_speed, 1.0))


func _spread(amount: float) -> Vector3:
	if amount <= 0.0:
		return Vector3.ZERO
	return Vector3(randf_range(-amount, amount), randf_range(-amount, amount), randf_range(-amount, amount))


# ============================================================ 光束步枪

## Read animated hand/forearm emitters at emission time. Back cannons keep
## their dedicated hardpoints; vulcan and cannon logic retain their own sources.
func _live_weapon_anchor(slot: String) -> Vector3:
	if _model_mounts.has(slot) and is_instance_valid(_model_mounts[slot]):
		return to_local(_model_mounts[slot].global_position)
	var bone:=_bone_index(slot)
	if bone>=0:
		return global_transform.affine_inverse()*_model_skel.global_transform*_model_skel.get_bone_global_pose(bone).origin
	var point:=rig_anchor(slot)
	return spin_pivot.transform.basis*point if is_instance_valid(spin_pivot) else point

func _vulcan_muzzle_local(index: int) -> Vector3:
	if _weapon_emitters!=null:return _weapon_emitters.head_local(index)
	return _live_weapon_anchor("head")

func _rifle_muzzle_local(index: int) -> Vector3:
	if SuitProfile.is_thunderbolt(profile.id):return _live_weapon_anchor("muzzle_R")
	if profile.id==SuitProfile.Id.ZORIN_SOUL:return global_transform.affine_inverse()*_zorin_mount_world("muzzle_L").origin
	if profile.id==SuitProfile.Id.NU_GUNDAM:return _live_weapon_anchor("muzzle_R")
	if _weapon_emitters!=null:
		var calibrated = _weapon_emitters.rifle_local()
		if calibrated!=null:return calibrated
	if _regz_motion != null and _regz_motion.ready: return _regz_motion.muzzle_local()
	if profile.id in [SuitProfile.Id.GP03S,SuitProfile.Id.ZORIN_SOUL]: return _live_weapon_anchor("muzzle_L")
	if _gun_pose_ready and not profile.rifle_back_mount:
		var name := "muzzle_L" if index % 2 == 0 else "muzzle_R"
		if _bone_index(name) >= 0:
			return _live_weapon_anchor(name)
	var point:=_muzzle_local[index % _muzzle_local.size()]
	return spin_pivot.transform.basis*point if is_instance_valid(spin_pivot) else point


## 光束步枪。总弹药无限，打空自动换弹，R 可提前更换未满弹匣；
## 另外还需要 `rifle_count > 0`（柯西可以把枪丢掉换脱锁）。
## `lead` = true 时朝提前量打（AI 用），false 时机头指哪儿打哪儿（玩家用，靠 HUD 提前量自己瞄）。
func fire_beam(trigger: bool, target: Node3D = null, lead := false) -> bool:
	if thunderbolt_systems!=null:return thunderbolt_systems.primary() if trigger else false
	if profile.id==SuitProfile.Id.ZORIN_SOUL and is_instance_valid(nu_systems):return nu_systems.fire_primary() if trigger else false
	if sazabi_systems!=null:return sazabi_systems.fire_primary() if trigger else false
	if weapons_locked(): return false
	if profile != null and profile.id == SuitProfile.Id.GP03S and has_method("current_slot") and gp03s_equipped() != "rifle":
		return false
	if profile != null and profile.cannon_only:
		return fire_cannon(target) if trigger else false
	if not trigger or rifle_reloading or rifle_cooldown > 0.0:
		return false
	# 脱板失能期间打不出光束（1.2 飞行踏板）——与火神炮/导弹/军刀同一道门禁。
	if is_staggered():
		return false
	if rifle_count <= 0 or projectile_container == null or in_transform():
		return false
	# 弹匣门槛：**无限弹**的机体（梅萨M01）不看 `rifle_mag` —— 它没有换弹这回事。
	if not has_infinite_rifle_ammo() and rifle_mag <= 0:
		return false
	rifle_cooldown = profile.rifle_interval
	if not has_infinite_rifle_ammo():
		rifle_mag -= 1
	# 一次扳机打出 `rifle_pellets` 道（1 = 老的单管；阿利宙斯常态/巡航 = 2）。
	#
	# ⚠️ **每道各自解交汇点**（`aim_point` 按各自 origin 算）：两道弹道因此会在
	# 准星处收拢，而不是两条平行光柱 —— 和两门航炮的交汇是同一个机制。
	# 弹药统计按**弹体**记（`shots_fired`/`beam_shots` 各 +1），
	# 因为 `Game.hits` 也是按弹体记的，这样命中率才不会被双联腰斩。
	var pellets := maxi(profile.rifle_pellets, 1)
	if _muzzle_local.is_empty():
		# `_collect_muzzles()` 保证至少有 2 个（有兜底），这里只是别让"哪天兜底失效"
		# 变成一次越界崩溃 —— 静默打不出来，比崩掉整局好排查。
		return false
	# Successful player and AI shots share the same animation entry. Repeated
	# player-side requests are idempotent in the action state machine.
	play_model_action("shoot", true)
	_gun_recoil_clock = 0.0
	if profile.id == SuitProfile.Id.GP03S: _gp03s_pose("rifle")
	var rifle_trigger := Game.rifle_stats.begin_trigger() if is_player else 0
	for i in pellets:
		var origin := global_transform * _rifle_muzzle_local(i)
		# ⚠️ `beam_model = true`：光束的弹道是两段式，提前量走
		# `Ballistics.beam_lead_point()`（第 4 个参数 `projectile_speed` 在这条路上不用）。
		# ★63-9 · D3a：第 6 个实参 `assist = true` = **武器门** —— 只有光束步枪走
		# 辅助瞄准（`_fire_vulcan_round()` 不传，保持默认 false）。
		# 本轮之前这一位不存在，而 `aim_assist_weight()` 又因为单位错恒 0，
		# 所以整段辅助瞄准是**死代码**；现在两处一起接上。
		var aim := rifle_aim_point(origin, target, lead)
		var dir := (aim - origin).normalized()
		# 弹道总长 = 炮口 → 瞄准点。弹丸靠它算"出膛慢速段"有多长。
		var span := origin.distance_to(aim)
		# 弹速的真源：`profile.rifle_steady_speed`（阿利宙斯 > 0 ⇒ 整条弹道匀速）。
		# ⚠️ 与 `_lead_point()` 的提前量读的是**同一个字段** —— 改一个不改另一个
		# 就是本文件反复点名的"准星与实际弹道对不上"。
		var pellet := Projectile.beam(projectile_container, origin, dir, self,
			profile.rifle_damage * damage_mult * RIFLE_DAMAGE_MULT, profile.beam_color(), span,
			profile.rifle_scale, profile.rifle_steady_speed)
		if is_player:
			Game.shots_fired += 1
			Game.beam_shots += 1
			pellet.rifle_recorder = Game.rifle_stats
			var metadata: Dictionary = call("rifle_shot_metadata") if has_method("rifle_shot_metadata") else {"input": "script"}
			metadata["distance"] = span
			metadata["muzzle"] = [origin.x, origin.y, origin.z]
			metadata["direction"] = [dir.x, dir.y, dir.z]
			metadata["steady_speed"] = profile.rifle_steady_speed
			pellet.rifle_record_id = Game.rifle_stats.emitted(rifle_trigger, metadata)
		_net_report_fire("beam", origin, dir)
	# 音频**一次扳机只响一次**：双联齐射是"一发"，响两遍会听成两次开火
	if is_player:
		Audio.play_self("beam_rifle", -4.0)
	else:
		Audio.play_3d("beam_rifle", global_position, -2.0)
	beam_fired.emit()
	_auto_reload_empty_weapons()
	return true


## 联机里把"我开了一枪"告诉对面：对面在**我这台代理机体**的位置生成同样的弹丸，
## 于是双方都看得到对方的弹道（命中判定仍在开枪方，见 NetSession 的文件头）。
## 单机模式下 `Net.is_online()` 恒为 false，这里等于空操作。
func _net_report_fire(kind: String, origin: Vector3, dir: Vector3) -> void:
	if Net.is_online() and (is_player or (Net.role == Net.Role.HOST and get("net_unit_id") != null)):
		Net.send_fire("ai|" + str(get("net_unit_id")) + "|" + kind if not is_player else kind, origin, dir)


## 激光柱实体（见 `beam_cannon.gd`）。
##
## ⚠️ **走 `preload` 而不是依赖全局 `class_name`**：本工程有并行会话，
## 全局类名缓存（`.godot/global_script_class_cache.cfg`）只在编辑器 / `--import` 时刷新，
## 无头回归里新加的 `class_name` 可能解析不到（本工程栽过一次"整类静默失效"）。
const BeamCannonScript := preload("res://scripts/combat/beam_cannon.gd")


# ============================================================ 蓄力激光炮
#
# 需求（2026-09-28 用户原话）见 `SuitProfile.cannon_enabled` 那一段。
# 这里只做三件事：**答"能不能放" / 放 / 记冷却与过热**。
# "按住 1.7 s 进蓄力、松手放"是输入层（`PlayerController`）的事。

## 本形态有没有这门炮。**唯一判据读 `profile.cannon_enabled`**。
func cannon_available() -> bool:
	return profile != null and profile.cannon_enabled


## 此刻能不能**发射**。玩家侧（进蓄力）与真正的发射都读这一个函数 ——
## 分成两份就会漂移成"蓄力进去了、松手却打不出来"。
func cannon_ready() -> bool:
	if not cannon_available() or cannon_cd_left > 0.0:
		return false
	if in_transform() or is_staggered() or projectile_container == null:
		return false
	if profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL,SuitProfile.Id.REGZ_CUSTOM,SuitProfile.Id.SAZABI]:
		return true
	if rifle_reloading:
		return false
	if rifle_count <= 0 or projectile_container == null:
		return false
	# 用户点名的硬门槛：「光束大炮**只能在弹夹全满的时候**使用」。
	# ⚠️ 写成 `>=` 而不是 `==`：这一条挡的是"打剩一发也能放大炮"，
	# 不是"多出来的子弹不许有"（`rifle_mag` 理论上不会超过容量，但用 `==`
	# 会让将来任何一次容量调整变成一个静默的"大炮永远放不出来"）。
	return rifle_mag >= profile.rifle_magazine


## 这门炮从哪几个口出去。阿利宙斯是**双联背部炮** ⇒ 两个口。
func cannon_muzzles() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if sazabi_systems!=null:
		out.append(sazabi_systems.motion.belly_muzzle_local())
		return out
	if profile.id == SuitProfile.Id.NEUE_ZIEL:
		out.append(rig_anchor("muzzle_L"))
		return out
	for m: Vector3 in _muzzle_local:
		out.append(m)
	if out.is_empty():
		# 与 `_collect_muzzles()` 的兜底同向（那里也保证至少两个口）。
		var b := model_bounds
		out.append(Vector3(b.size.x * 0.16, b.position.y + b.size.y * 0.62,
			b.position.z + b.size.z * 0.30))
	return out


## 发射蓄力激光炮。返回 true = 真的放出去了。
##
## 副作用有三条，都是用户点名的：
##   1. **大炮冷却 20 s**（`cannon_cd_left`）；
##   2. **光束步枪过热 → 15 s 换弹**（借既有的 `rifle_reloading` 通道）；
##   3. 生成一条持续 4 s、每秒 35 伤害的光束柱（`BeamCannon`）。
##
## ⚠️ **不消耗弹匣**：用户只说"用过之后步枪过热换弹"，没说"吃掉子弹"。
## 而 15 s 换弹结束时弹匣自然满上 —— 加一条"扣 1 发"只会让 HUD 上那条
## 已经打满的弹匣条在最后关头闪一下，语义上也没有对应。
func fire_cannon(target: Node3D = null) -> bool:
	if weapons_locked(): return false
	if not cannon_ready():
		return false
	if profile.id == SuitProfile.Id.REGZ_CUSTOM:
		load("res://scripts/combat/regz_weapons.gd").new().fire_battery(self)
		return true
	var c: Node3D = BeamCannonScript.launch(projectile_container, self, cannon_muzzles(),
		target, profile.cannon_dps, profile.cannon_duration, profile.cannon_color(),
		profile.beam_cannon_radius,1.0,0.0,false,sazabi_systems!=null)
	_net_report_fire("sazabi_belly" if sazabi_systems!=null else "cannon", global_position, forward())
	active_cannon = c
	play_model_action("shoot", true)
	_gun_recoil_clock = 0.0
	cannon_cd_left = profile.cannon_cooldown
	# ---- 过热：借既有的换弹通道 ----
	# 于是 HUD 那条滚动读条、`fire_beam()` 的弹匣门槛、换完自动满弹匣
	# **三件事一行都不用改**就全都对上了。
	if not profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL,SuitProfile.Id.SAZABI]:
		rifle_reloading = true
		reload_timer = profile.cannon_overheat_reload
	if is_player:
		Audio.play_self("beam_rifle", 0.0)
	else:
		Audio.play_3d("beam_rifle", global_position, 2.0)
	# ⚠️ 镜头抖动**不在这里** —— `camera` 是 `PlayerController` 的东西，
	# `FlightBody` 上没有这个标识符（写上去是整个类编译不过，不是运行时报错）。
	# 走 `_on_funnel_launch()` 那一套钩子（`PlayerController` 覆写、AI 不覆写 ⇒ 天然不抖）。
	if profile.id == SuitProfile.Id.NEUE_ZIEL and is_instance_valid(target):
		var battery = preload("res://scripts/combat/neue_battery.gd").new()
		battery.shooter = self
		battery.target = target
		battery.include_shoulders = false
		projectile_container.add_child(battery)
	_on_cannon_fired()
	return true


## 大炮冷却进度 0（刚打完）→ 1（可以放）。HUD 用它画倒数。
## **未就绪时也返回 1**（"没有冷却这回事"与"冷却走完了"在显示上是同一件事）。
func cannon_cd_ratio() -> float:
	if profile == null or profile.cannon_cooldown <= 0.0:
		return 1.0
	if cannon_cd_left <= 0.0:
		return 1.0
	return clampf(1.0 - cannon_cd_left / profile.cannon_cooldown, 0.0, 1.0)

## 这台机是不是"光束步枪打不光"（梅萨M01）。**单一判定点**：
## `fire_beam()` 的弹匣门槛、`reload_rifle()` 的拒绝、`mag_ratio()` 的显示
## 三处都读它，不要在别处另写 `profile.rifle_ammo_infinite`。
func has_infinite_rifle_ammo() -> bool:
	return profile != null and profile.rifle_ammo_infinite


## 换弹。总弹药无限，所以只要有枪且弹匣不满就能换。
##
## ⚠️ 无限弹的机体**不能换弹**：它弹匣恒满，`reload_rifle()` 返回 false 是对的，
## 这样"按 R 没反应"就是正确行为，而不是 bug（HUD 那边也不会画换弹提示）。
func _auto_reload_empty_weapons() -> void:
	if not alive or profile == null: return
	if rifle_mag <= 0 and profile.rifle_magazine > 0 and not profile.cannon_only:
		reload_rifle()
	if profile.has_missiles: _funnel_check_reload()
	if (profile.id == SuitProfile.Id.GP03D and bazooka_mag <= 0) or (profile.id == SuitProfile.Id.GP03S and bazooka_mag < 2):
		reload_bazooka()
	if flare_count <= 0 and flare_reload_left <= 0.0:
		flare_reload_left = FLARE_AUTO_RELOAD_TIME

func reload_rifle() -> bool:
	if rifle_reloading or rifle_count <= 0 or has_infinite_rifle_ammo():
		return false
	if rifle_mag >= profile.rifle_magazine:
		return false
	rifle_reloading = true
	reload_timer = profile.rifle_reload_time
	return true


func reload_progress() -> float:
	if not rifle_reloading or profile.rifle_reload_time <= 0.0:
		return 0.0
	return clampf(1.0 - reload_timer / profile.rifle_reload_time, 0.0, 1.0)


## 浮游导弹装填进度（0 → 1）。**与 `reload_progress()` 同形**：未装填恒为 0，
## 所以调用方统一用"进度 > 0"就能表达"要不要画读条"。
##
## 批 28（用户指定做滚动读条）新加。换算必须放在**这里**而不是 HUD：
## 装填的加减只在 `_funnel_check_reload()` 与 `_tick_weapons()`，
## 进度反推也只有这一处 —— HUD 里再除一遍 `profile.funnel_reload_time`
## 就是第三份拷贝，改一个数就会"条走完了弹夹还没满"。
func funnel_reload_progress() -> float:
	if profile == null or funnel_reload_left <= 0.0 or profile.funnel_reload_time <= 0.0:
		return 0.0
	return clampf(1.0 - funnel_reload_left / profile.funnel_reload_time, 0.0, 1.0)


func mag_ratio() -> float:
	if profile == null or profile.rifle_magazine <= 0:
		return 0.0
	# 无限弹：条恒满（HUD 另画一个 ∞），于是"打空闪按 R"那套提示永远不会亮。
	if has_infinite_rifle_ammo():
		return 1.0
	return clampf(float(rifle_mag) / float(profile.rifle_magazine), 0.0, 1.0)


static func _velocity_of(n: Node3D) -> Vector3:
	if n == null or not is_instance_valid(n):
		return Vector3.ZERO
	var v = n.get("fm")
	if v is FlightModel:
		return (v as FlightModel).velocity
	return Vector3.ZERO


# ============================================================ 浮游导弹

## 浮游导弹：从左右挂架交替弹出，先向外散开再咬住目标（见 Missile.funnel）。
##
## 1.1：**核心 · 量产型ν高达形态没有导弹**（用户要求"只能用光束步枪和火神炮"），
## 门禁读的是 `profile.has_missiles` —— 于是玩家与 AI 走同一套规则，
## 不需要在输入层各写一次"这台机能不能打导弹"。
##
## `salvo_cooldown`（第十五轮追加；批 21 起语义改为**按次直定**）：本次扳机之后压多长的发射器冷却。
## **≥ 0 一律按传入值算（0 = 零冷却）**；**< 0（默认）才走通用值** `profile.funnel_interval`。
## 批 26（2026-09-22 用户指定）「拦截飞弹开枪间隔和浮游飞弹一样」：
## 键鼠 F / 右键路径**不传**（走通用 0.42 s，与浮游飞弹同闸 —— 批 21 的 CD=0 因
## "长按一秒泼一堆"被撤回）；手柄**自动拦截**传 0，节奏由状态机 `SHOT_INTERVAL`
## （0.42 s，与通用冷却对齐）等价表达 —— 不走通用冷却是防扳机/冷却归零的浮点赛跑。
## **AI 不受影响** —— 它仍传自己的 `ai_cd`（0.31~0.36，按难度）。
func fire_funnel(target: Node3D, salvo_cooldown := -1.0) -> bool:
	if thunderbolt_systems!=null:return thunderbolt_systems.secondary()
	if weapons_locked(): return false
	if not profile.has_missiles:
		return false
	if target == null or not is_instance_valid(target):
		return false
	# 批 14：换弹中（弹夹打空自动换）也不能发射 —— "按了没反应"必须可解释，
	# HUD 浮游导弹一行会读 `funnel_reload_left` 显示进度。
	if funnel_cooldown > 0.0 or (funnel_reload_left > 0.0 and profile.id != SuitProfile.Id.GP03D) or funnel_count <= 0 \
			or projectile_container == null or in_transform():
		return false
	if is_staggered():
		return false
	if profile.id == SuitProfile.Id.NEUE_ZIEL:
		return _fire_neue_missiles(target)
	if profile.id == SuitProfile.Id.GP03D:
		return _fire_gp03d_pods(target)
	funnel_cooldown = salvo_cooldown if salvo_cooldown >= 0.0 else profile.funnel_interval
	# 库存按**发**计，所以一次扳机要扣 `MISSILE_PER_SHOT` 发。
	# 分给谁由 `_funnel_plan()` 决定（多目标锁定 ⇒ 火力分散，见它自己的注释）。
	var plan := _funnel_plan(target)
	for entry: Dictionary in plan:
		var tgt: Node3D = entry["unit"]
		var n: int = int(entry["shots"])
		for j in n:
			funnel_count -= 1
			# 左右挂架交替：**必须用自己的计数器** —— `funnel_count` 在循环里一直在变，
			# 拿它取模会让三发全从同一侧出去（单发时代那样写是对的，多发就不成立了）。
			var side := 1.0 if _funnel_slot % 2 == 0 else -1.0
			_funnel_slot += 1
			var slot := "funnel_L" if side > 0.0 else "funnel_R"
			# ⚠️ **必须走 `global_transform *`，不能写 `global_position +`**（轮 13 修正）。
			#
			# `rig_anchor()` 返回的是**机体局部空间**里的向量（它内部由
			# `model_pivot.transform` + `model_root.position` + `rig.transform` 合成，
			# 见那里的说明）。直接加到 `global_position` 上，等于假设"机体永远不旋转" ——
			# 机体一滚转（转弯侧倾是批 11 的常态），挂架弹射点就飘到机体外的空气里。
			#
			# ⚠️ 火神炮与光束用的是 `global_transform * _muzzle_local[i]`（**正确口径**），
			# 唯有导弹这一条此前漏了 —— 同一个工程里两种口径并存，属于"改了一处忘了另一处"
			# 那类静默不一致。现在三条发射路径统一到 `global_transform *`。
			var origin := global_transform * rig_anchor(slot)
			# 同一个目标的那几发要扇成"一蓬"而不是叠在一条线上：上下各偏一点
			var fan := (float(j) - 0.5 * float(n - 1)) * 0.30
			var outward := (right() * side + up() * (0.45 + fan) - forward() * 0.15).normalized()
			_net_report_fire("funnel", origin, outward)
			Missile.funnel(projectile_container, origin, outward, tgt, self,
				profile.funnel_damage * damage_mult)
			# **挂架弹射**的那一小团烟（DESIGN §4.4「另加两处小东西」①）。
			# 位置用 `origin`（挂架）而不是导弹的位置：弹一离架就带着初速走了，
			# 烟要留在**挂架那儿**才读得出"是从这里弹出去的"。
			# ⚠️ 粒子数由 `FX.MISSILE_LAUNCH_PUFF` 压到 18 —— 一次扳机 3 发，
			# 用 `smoke_burst` 的默认值 150 会变成 450 粒子只为"一小团烟"。
			FX.smoke_burst(projectile_container, origin, 0.35, 1.2, FX.MISSILE_LAUNCH_PUFF)
			# 每一发离架都给一次反馈（基类是空实现，见 `_on_funnel_launch()`）。
			# ⚠️ **必须逐发调**，不能在循环外面调一次：三发是**每隔 `funnel_interval`
			# 一次扳机**打出去的，而一次扳机里这三发是同一帧出去的 ——
			# 只抖一次会让"扳机感"和实际发射的数量脱节（DESIGN §4.10.1 缺口 1）。
			_on_funnel_launch()
			if is_player:
				Game.missiles_fired += 1
	# 音效**一次扳机只响一次**：三发连着放三遍会变成一堵噪音墙
	if is_player:
		Audio.play_self("funnel_fire", -3.0)
		Game.funnels_fired += 1
	else:
		Audio.play_3d("funnel_fire", global_position, -2.0)
	funnel_fired.emit()
	# 批 14：弹夹可能刚好打空（总量无限的世界里，"打空"只意味着"该换弹了"）
	_funnel_check_reload()
	return true


## 弹夹打空 → 自动换弹（批 14）。玩家（`fire_funnel` / 全弹发射）与 AI 共用 ——
## 发射路径里**只在这里触发**，换弹的推进在 `_tick_weapons()`。
func fire_wire_arms(target: Node3D) -> bool:
	if weapons_locked(): return false
	if profile.id != SuitProfile.Id.NEUE_ZIEL or projectile_container == null \
			or wire_cd_left > 0.0 or is_instance_valid(active_wire_arms) or is_staggered() or in_transform():
		return false
	if not is_instance_valid(target) or target == self or target.get("team") == team:
		return false
	if global_position.distance_to(target.global_position) > preload("res://scripts/combat/neue_wire_arms.gd").MAX_CABLE:
		return false
	var volley = preload("res://scripts/combat/neue_wire_arms.gd").new()
	if not volley.configure(self,target):
		volley.free()
		return false
	projectile_container.add_child(volley)
	active_wire_arms = volley
	wire_cd_left = 12.0
	# ★ 联机（2026-10-11 用户实测「看不到线控炮」）：远端在**代理机体**上挂一副纯视觉的
	# （见 `main._on_net_fire()` 的 `"wire"` 分支，那边把 `visual_only` 打开）。
	_net_report_fire("wire", global_position,
		global_position.direction_to(target.global_position))
	return true


func _fire_neue_missiles(target: Node3D) -> bool:
	var count := mini(profile.funnel_per_shot,funnel_count)
	for i in count:
		var side := "funnel_L" if i % 2 == 0 else "funnel_R"
		var origin := global_transform * rig_anchor(side)
		var outward := (forward()+right()*(float(i)-1.5)*0.1).normalized()
		Missile.spawn(projectile_container,origin,outward,target,self,profile.funnel_damage*damage_mult,Missile.Trail.HIGH)
		if is_player:
			Game.missiles_fired += 1
		# ★ 联机（2026-10-11 用户实测「看不到导弹」）：**露维杰露的浮游导弹也要上报**。
		# 柯西/佩涅罗佩那条 `fire_funnel()` 早就报了，这两台 MA 的专属武器当时漏了 ——
		# 症状是"对面什么都看不到"，而单机下一切正常（`_net_report_fire` 在离线时是空操作）。
		_net_report_fire("missile", origin, outward)
	funnel_count -= count
	funnel_cooldown = profile.funnel_interval
	_funnel_check_reload()
	funnel_fired.emit()
	Audio.play_3d("funnel_fire",global_position,-3.0)
	return count > 0


func _fire_gp03d_pods(target: Node3D) -> bool:
	var wave = preload("res://scripts/combat/gp03d_pod_salvo.gd").new()
	wave.configure(self, target, _funnel_plan(target))
	projectile_container.add_child(wave)
	# ★ 联机（2026-10-11）：集束弹仓也要上报 —— 远端放一份**纯视觉**的
	# （`main._on_net_fire()` 的 `"pod"` 分支，那边把 `damage` 归零）。
	# ⚠️ 一趟 108 发，**绝不能按发上报**（108 个可靠包 = 卡顿 + 丢包）；
	# 报文只带 "这一仓打出来了"，远端自己重建同一套弹幕。
	_net_report_fire("pod", global_position, forward())
	funnel_count -= 108
	_funnel_slot += 1
	funnel_cooldown = profile.funnel_interval
	_funnel_check_reload()
	_on_funnel_launch()
	if is_player:
		Audio.play_self("funnel_fire", -3.0)
		Game.funnels_fired += 1
	else:
		Audio.play_3d("funnel_fire", global_position, -2.0)
	funnel_fired.emit()
	return true


func _funnel_check_reload() -> void:
	if profile != null and profile.id == SuitProfile.Id.GP03D:
		if funnel_count < funnel_mag_size and funnel_reload_left <= 0.0:
			funnel_reload_left = 10.0
		return
	if funnel_count <= 0 and funnel_mag_size > 0 and funnel_reload_left <= 0.0:
		funnel_reload_left = profile.funnel_reload_time


## 本次扳机的**分配表**：`[{"unit": Node3D, "shots": int}, ...]`。
##
## 这是需求里「锁定多个目标 → 自己的导弹发射火力分散」的落点：
## **总弹量不变**，按「已经稳定锁定」的成员数平分（`LockOnSystem.salvo_split`），
## 于是多锁一个目标 = 压制面更广、单点杀伤更薄。
##
## 三条边界，缺一条都会出事：
##
## ① **没有锁定组**（AI 侧、拦截弹、测试里没 `Game.register_lock` 的机体）
##    ⇒ 全部给 `primary`，与改动前**逐位相同**。这是零回归的证明点。
## ② **组里一个都还没锁上**（刚 `add_lock`、层级还停在 TRACK）⇒ 同样全给 `primary`。
##    ⚠️ K 必须取 `locked_in_group()` 的长度，**不能取 `lock_group.size()`** ——
##    否则"长按 Tab 把 3 个名额填满"就成了一次白送的齐射，而
##    "火力分散"这个代价本来是要求玩家先付出锁定时间的。
## ③ **余额不足**（`funnel_count < MISSILE_PER_SHOT`）⇒ 照样平分，
##    分到 0 发的成员直接跳过 —— 沿用旧版"把剩下的打完，不制造死角"。
##
## ⚠️ 放置位置的理由：这段必须**在玩家与 AI 共用的函数里**，
## 而不是在 `PlayerController` 里另写一遍 —— 两份发射逻辑迟早会不一致，
## 而不一致的表现是"AI 的导弹分配方式和玩家不一样"，极难发现。
## AI 之所以天然是单目标，是因为**它从不调 `add_lock()`**（DESIGN §4.1.7）。
func _funnel_plan(primary: Node3D) -> Array:
	var total := mini(funnel_per_shot(), funnel_count)
	# ⚠️ `Game.lock_of()` 返回 Variant（它不认识 `LockOnSystem`），
	# 所以这里不能用 `:=` 推断类型 —— 那会直接编译不过（同 `_clash_lock_out`）。
	var lk = Game.lock_of(self)
	var group: Array[FlightBody] = []
	if lk != null and lk.unit == self:
		group = lk.locked_in_group()
	if group.is_empty():
		return [{"unit": primary, "shots": total}]
	var parts := LockOnSystem.salvo_split(total, group.size())
	var out: Array = []
	for i in group.size():
		if parts[i] <= 0:
			continue
		out.append({"unit": group[i], "shots": parts[i]})
	return out


## 每一发浮游导弹离架后的**反馈钩子**。基类是**空实现**。
##
## ⚠️ 判定**不能**写在 `fire_funnel()` 的循环里（比如 `if is_player: 抖镜头`）：
## 那个函数是**玩家与 AI 共用**的（`BanditAI` 也走它），把"谁发的"判断散在循环里，
## 迟早会有人漏掉一处 —— 而症状是**玩家被敌机的导弹震镜头**，
## 属于"玩两分钟就会骂"的那类 bug。
##
## 覆写点只有一个：`PlayerController`（它同时持有 `camera`）。
## AI 不覆写 ⇒ 天然不抖。这条结构比一个 `is_player` 判断更耐改。
func _on_funnel_launch() -> void:
	pass


## 蓄力激光炮发射时的钩子（2026-09-28）。**与 `_on_funnel_launch()` 同一个理由**：
## `camera` 只有 `PlayerController` 持有，`FlightBody` 里写 `camera.add_shake()`
## 会**整个类编译失败**（实测：`Parse Error: Identifier "camera" not declared`，
## 连锁让 `Game` / `AudioDirector` / 所有依赖它的套件全红）。
## 所以让玩家侧覆写这个空函数去抖，AI 不覆写就什么都不发生。
func _on_cannon_fired() -> void:
	pass


func deploy_flares() -> bool:
	if flare_cooldown > 0.0 or flare_count <= 0 or projectile_container == null:
		return false
	flare_cooldown = flare_interval
	flare_count = maxi(flare_count - 6, 0)
	_auto_reload_empty_weapons()
	# 1.2（方案 C-3）：干扰弹不再只是"骗导弹"——它同时**压对方的锁定质量**。
	# 3.0 秒的有效期是按"撒出去、烧完"给的，正好覆盖一次急转脱离的时间尺度。
	flare_active = FLARE_ACTIVE_TIME
	Flare.deploy_burst(projectile_container, global_position - up() * 6.0, fm.velocity, 6)
	if is_player:
		Game.flares_used += 1
	return true


## 干扰弹是否正在生效（`LockOnSystem.target_quality()` 会读它）。
func flares_active() -> bool:
	return flare_active > 0.0


const FLARE_ACTIVE_TIME := 3.0


# ============================================================ 光束军刀

## 劈砍。若 target 被锁定且距离在 saber_magnet_range 内 → **吸附**：
## 机头锁死目标、速度拉到 saber_dash_speed 高速突进，贴到 saber_hit_range 即判定命中。
## 超出范围则只是一次普通的向前突刺（没有吸附）。
func try_saber(target: Node3D) -> bool:
	if weapons_locked():return false
	if thunderbolt_systems!=null:thunderbolt_systems.ram_attack=profile.id==SuitProfile.Id.FULL_ARMOR_TB and shield_up
	if saber_locked(): return false
	if not alive or not profile.has_saber or in_transform() or is_staggered(): return false
	if not saber_locked() and melee_guard.elapsed < melee_guard.BAR_TIME and is_instance_valid(melee_guard.incoming()) and melee_guard.incoming().saber_active():
		return melee_guard.press(self)
	if profile.id == SuitProfile.Id.GP03S and has_method("current_slot") and gp03s_equipped() != "saber":
		return false
	if is_instance_valid(gp03_grab_owner):
		return false
	if not profile.has_saber or in_transform():
		return false
	# ⚠️ **骑踏板不再禁止挥军刀**（1.2 第十九轮改了这条）。
	#
	# 原先这条规则（`pedal_restricts_melee()`）的用意是"骑板时手没空"，
	# 但它引出两个**不可接受**的后果：
	#   ① 骑板的人整场**近战残废** —— 而第十九轮起量产机要骑板赶路，
	#      等于让那六台机体永久失去军刀；
	#   ② **相杀对骑板者永远不可达** —— 相杀要求双方都在军刀突进态，
	#      骑板者根本进不去（第十八轮实测确认过）。
	#
	# 现在的代价仍然成立（转向钝 0.8 + 不能悬停），够不够就看手感了 ——
	# 这是**用户拍板前的临时决定**，已登记在方案 §11.2 待复核。
	# 踏板那点"手上没空"的设定改成：**可以拔刀，但骑板时转向吃亏**。
	if is_staggered():
		return false
	if saber_state != SaberState.IDLE or saber_cooldown > 0.0:
		return false
	if profile.id == SuitProfile.Id.GP03S: _gp03s_pose("saber")
	saber_cooldown = profile.saber_interval
	_melee_attack_serial += 1
	saber_state = SaberState.CHARGE
	saber_timer = saber_dash_seconds()
	_saber_visual_clock = 0.0
	_saber_swing_released = false
	_saber_anim_style = SaberMotion.style(profile)
	# N49：挥刀动作（`slash`）。**放在三条早退之后、状态真的进 CHARGE 这一刻** ——
	# 冷却中 / 硬直中 / 没军刀的机体按键不该有动作（同 `raise_shield()` 的口径）。
	play_model_action("slash")
	saber_target = null
	if target != null and is_instance_valid(target):
		var d := global_position.distance_to(target.global_position)
		if d <= saber_magnet_range():
			saber_target = target
	if saber_target != null:
		# 吸附：把速度矢量整根甩向目标，随后由 _step_saber 锁死机头
		var dir := (saber_target.global_position - global_position).normalized()
		fm.speed = profile.saber_dash_speed
		fm.velocity = dir * fm.speed
	if saber_target is FlightBody:
		saber_target.melee_guard.warn(saber_target,self)
	if is_player:
		Audio.play_self("beam_saber", -3.0, 1.0)
	else:
		Audio.play_3d("beam_saber", global_position, -2.0)
	_net_report_fire("saber_rush",global_position,fm.velocity.normalized() if fm.velocity.length_squared()>1.0 else forward())
	_show_blade()
	return true


## 瞄准方向（单位向量）。ZERO = 用机头指向。
##
## 用户要求"鼠标控制导弹锁定准星、机枪射击准星、光束步枪发射准星"。
## 做法不是在三套武器里各判断一次"是不是鼠标模式"，而是**让它们都读同一个方向**：
## 玩家用鼠标瞄准时 PlayerController 把这里设成鼠标指的方向，
## 于是锁定、机枪、光束步枪一起跟着走，改一处三处一致。
var aim_dir := Vector3.ZERO


## 当前的瞄准前向：鼠标瞄准时是准星方向，否则就是机头方向。
func aim_forward() -> Vector3:
	if aim_dir.length_squared() > 0.25:
		return aim_dir.normalized()
	return forward()


func set_aim_direction(d: Vector3) -> void:
	aim_dir = d if d.length_squared() > 0.25 else Vector3.ZERO


## 蓄力激光炮的**发射方向**（世界系，单位向量）。`BeamCannon` **每帧**取用它 ——
## 所以"柱子跟着准星扫"这件事只有这一个真源。
##
## 需求（2026-09-28 用户原话）：
## > 发射方向和火神炮差不多，都是**跟随着鼠标方向走的**。
##
## 于是它返回的就是 `aim_forward()` —— 玩家用鼠标瞄准时，`PlayerController._read_aim_input()`
## 每物理帧把准星方向写进 `aim_dir`，火神炮（`_fire_vulcan_round` → `aim_point`）、
## 光束步枪、HUD 准星读的也是它。**不要再让大炮去看 `lock.target`**：
## 那样柱子的朝向由"锁到谁"决定，玩家甩不动它 —— 就是用户说的"锁定有点太死了"。
func cannon_aim_dir() -> Vector3:
	return aim_forward()


## 玩家侧的军刀参数（1.2 用户反馈"远处砍不到"）：
## 吸附距离 620 → **1400 m**、突进 1.5 → **2.4 s**。
##
## ⚠️ **AI 必须保持 profile 里的 620 / 1.5**。理由不是"公平"，而是安全：
## AI 突进期间 `_step_saber` 完全接管速度矢量、不接受任何转向输入，
## 于是"避地"这类基于转向的保护在这段时间里是失效的 —— 放宽它就会重现
## README §14 第 10 条那场"AI 一头扎进海里"。所以这两个数按 `is_player` 分开取。
const PLAYER_SABER_MAGNET := 1400.0
const PLAYER_SABER_DASH_TIME := 2.4
## 命中要求的**相对接近速度**（m/s）：让"擦过去"和"正面砍中"区分开。
const SABER_MIN_CLOSING := 60.0
## 线段扫掠的判定半径（米）。机体碰撞胶囊只有 5 m 左右，而模型 28 m 高带翼展 ——
## 军刀是"挥过去"，判定要给到"刀刃扫过的体积"，不能只算中轴。
const SABER_SWEEP_RADIUS := 26.0
## 空挥回收 / 未命中可中断（第十四轮 B6）。
##
## 来自玩家实测与老板自己的定位：
##   「光束军刀砍人是不是有僵直，手感怪怪的」
##   「逻辑是向前方冲刺一段然后砍人……**但是如果空挥的话就会很生硬的冲刺**」
##
## 突进期间 `_step_saber` 完全接管速度矢量、不接受任何转向输入。**有吸附目标时这是对的**
## （"朝对方脸上冲过去"就是军刀的意义），但**没有吸附目标**时就变成了把玩家
## 摁在一条直线上飞满 2.4 秒 —— 挥空了却收不回来，这就是"生硬"。
##
## 于是：突进开始 `SABER_MISS_GRACE` 秒后仍然没有吸附目标，就直接结束突进，
## 把速度矢量还给玩家。冷却不退回（`try_saber` 那一刻已经扣过了），
## 所以"空挥不要钱"并不成立 —— 只是不再额外罚两秒钟的直线飞行。
##
## ⚠️ **只对玩家生效**：AI 的突进由 `_saber_is_viable` 门禁保证"这一刀有得打"，
## 中途放开转向会让它一头扎进海里（见 `PLAYER_SABER_MAGNET` 与 `abort_saber` 的注释）。
const SABER_MISS_GRACE := 0.5

# ---- 军刀相杀（1.2 用户指定）----
#
# 需求原话：「近战系统要加入相杀（**在同一段时间判定窗口内都使用了光束军刀攻击，
# 则触发相杀**，相杀之后会**暂时失去双方的锁定**，并且**强制弹开一段距离**）」。
#
# ⚠️ **判定距离必须比命中距离（`saber_hit_range` = 78 m）大一点** ——
# 取 **100 m**。理由：如果相杀窗口比命中窗口小，那么"两边对砍"永远是先判命中、
# 根本轮不到相杀，这个机制等于不存在。所以 `_step_saber()` 里**先查相杀、再查命中**。
const CLASH_RANGE := 100.0
## 相杀后的**弹开速度**（m/s）。背向 + 一点竖直分量。
const CLASH_PUSH_SPEED := 600.0
## 相杀后**互相不可锁定**的时长（秒）。
##
## 需求："暂时失去双方的锁定"。做法复用现成的 `unlockable_until`（丢枪脱锁在用同一条）。
const CLASH_UNLOCKABLE := 1.2
## 相杀**冷却**（秒）。
##
## ⚠️ **必须比 `CLASH_UNLOCKABLE` 长**：否则双方刚能重新锁定就又对撞，
## 贴脸缠斗会变成"相杀 → 相杀 → 相杀"的死循环（谁也没法真正进入伤害交换）。
## 2.5 s 给了彼此足够时间拉开或改打别的。
const CLASH_COOLDOWN := 2.5
## 相杀是否额外要求"**机头互指**"（默认**关**）。
##
## ⚠️ 默认 false 是刻意的：开启后 `forward().dot(fb.forward()) > -0.2` 会把
## **侧向擦过的相杀**一起干掉 —— 手感上"拼刀"会明显变难触发。
## 留一个常量开关，等老板试玩现版本之后再定（见 DESIGN §10 第 4 条）。
const CLASH_REQUIRE_FACING := false


## ★63-24：玩家那一支改读 `profile`（默认 = 原常量）⇒ 演习模式的卡才改得动它。
## ⚠️ 玩家侧**吸附距离**有**两处口径**：这里（真判定）＋ `player_controller.gd:1170`
##    （只管"要不要播吸附提示 + 震屏"）。两处必须同时落到 `profile.player_saber_magnet`，
##    否则会出「吸附了却没提示」／「提示了却没吸附」——同样不报错。
func saber_magnet_range() -> float:
	if is_player:
		return profile.player_saber_magnet if profile != null else PLAYER_SABER_MAGNET
	return profile.saber_magnet_range


func saber_dash_seconds() -> float:
	if is_player:
		return profile.player_saber_dash_time if profile != null else PLAYER_SABER_DASH_TIME
	return profile.saber_dash_time


## ★63-24：以下三个 + 相杀冷却原为 `const`，现读 profile（默认 = 原常量）。
## 全部带 `profile == null` 兜底 —— 有些测试会 `new()` 一个没设 profile 的 FlightBody。
func saber_sweep_radius() -> float:
	return profile.saber_sweep_radius if profile != null else SABER_SWEEP_RADIUS


func saber_min_closing() -> float:
	return profile.saber_min_closing if profile != null else SABER_MIN_CLOSING


func saber_miss_grace() -> float:
	return profile.saber_miss_grace if profile != null else SABER_MISS_GRACE


func clash_cooldown_secs() -> float:
	return profile.clash_cooldown if profile != null else CLASH_COOLDOWN


## ★63-24：一次扳机出几发（原 `SuitProfile.MISSILE_PER_SHOT` 常量）。
func funnel_per_shot() -> int:
	return profile.funnel_per_shot if profile != null else SuitProfile.MISSILE_PER_SHOT


func saber_active() -> bool:
	return saber_state == SaberState.CHARGE


## 从外部中断军刀突进。
##
## 突进期间 `_step_saber` 完全接管速度矢量、不接受任何转向输入，
## 所以"避地"这类基于转向输入的保护在这段时间里是失效的 ——
## AI 需要一个能直接掐断的入口（见 BanditAI._think 的兜底）。
func abort_saber() -> void:
	if saber_state != SaberState.IDLE:
		_end_saber()


## 返回 true 表示本帧飞行由军刀状态机接管。
func _step_saber(delta: float) -> bool:
	if saber_state != SaberState.CHARGE:
		return false
	# 刀身每帧跟着手骨走。⚠️ 放在**最前面**：后面 `_try_clash()` / 命中那两条
	# 早退路径都会 `return true`，放中间就会漏帧（刀会在拼刀那一帧开始滞后）。
	# 占位骨架路径下 `_blade_anchor == null` ⇒ 本函数空转。
	_sync_blade_anchor()
	saber_timer -= delta

	# A short telegraph makes the 0.2 s defensive window usable at close range.
	if is_instance_valid(saber_target) and saber_dash_seconds()-saber_timer < 0.20:
		fm.velocity = Vector3.ZERO
		velocity = Vector3.ZERO
		return true

	# ---- **相杀**（1.2 用户指定）**必须排在命中判定之前** ----
	#
	# ⚠️ 顺序是这一条的全部要点：相杀窗口（100 m）比命中距离（78 m）大，
	# 若先判命中，那么"双方同时冲进来"永远会在 78 m 处先判命中，
	# 相杀只在"偏偏没砍中"时才出现 —— 那不是需求要的东西，等于没做。
	# 所以先问"对面是不是也在冲"，是就相杀、不是才继续走命中判定。
	if _try_clash(delta):
		return true

	# ---- **线段扫掠判定**（1.2 用户反馈"近处反应不过来"）----
	#
	# 旧实现只对**锁定目标**判距离（`saber_target`），所以"没锁定 + 3 m 掠过"
	# 这样的命中根本不掉血 —— 一半的"反应不过来"其实是"判定压根没在看"。
	# 现在每一帧把"这一帧扫过的那一段"（p0 → p1）对所有敌对单位做扫掠：
	#   ① 判定对象是**所有敌对单位**（不只锁定目标）；
	#   ② 要求**相对接近速度 ≥ 60 m/s**（贴着一起飞不算砍中，否则缠斗会乱触发）；
	#   ③ 半径按"刀刃扫过的体积"给（26 m），不是机体那根 5 m 的中轴胶囊。
	# 整个突进期间每帧都在扫 → 这本身就是方案要的"起手窗口"，
	# 而不是"按下那一帧定生死"。
	var p0 := global_position
	var p1 := p0 + velocity * delta
	for h: Node3D in Game.live_hostiles_of(self):
		var fb := h as FlightBody
		if fb == null or fb == self or not fb.alive:
			continue
		if fb.is_unlockable():
			continue
		var to_fb := fb.global_position - p0
		var d := to_fb.length()
		if d > saber_magnet_range() + saber_sweep_radius():
			continue
		var closing := (velocity - fb.fm.velocity).normalized().dot(to_fb.normalized()) \
			* maxf((velocity - fb.fm.velocity).length(), 0.0)
		if closing < saber_min_closing():
			continue
		var closest := Geometry3D.get_closest_point_to_segment(fb.global_position, p0, p1)
		if closest.distance_to(fb.global_position) <= saber_sweep_radius():
			_slash(fb)
			return true

	# ---- 空挥回收 / 未命中可中断（第十四轮 B6）----
	#
	# 走到这里说明**这一帧没有扫到人**。分两种情况：
	#   - 有吸附目标 → 继续朝它突进（下面那段，行为一行没改）；
	#   - 没有吸附目标 → 这一刀本来就没冲着任何东西去，玩家不该被按在直线上飞满 2.4 秒。
	#
	# ⚠️ 宽限期内的那段"直线冲刺"**必须保留**，而且是玩家与 AI 共用的：
	#   ① 它给的是"起手那几帧"的机会 —— 吸附目标可能比挥刀晚一点点才成立；
	#   ② 更要紧的是它**给 `velocity` 赋值**。扫掠判定读的是节点属性 `velocity`，
	#      而 `try_saber()` 只写 `fm.velocity`；删掉这一行，起手那一帧 `velocity`
	#      还是 0，扫掠就永远打不到"贴脸掠过"的敌机 ——
	#      `suite_abilities` 的"没锁定 + 3 m 掠过 → 命中"正是钉这一条的。
	var tgt := saber_target
	if tgt == null or not is_instance_valid(tgt) or (tgt.has_method("is_alive") and not tgt.is_alive()):
		if is_player and saber_dash_seconds() - saber_timer >= saber_miss_grace():
			# 过了宽限期还没有吸附目标 → 交还控制权。
			# 冷却不退回（`try_saber` 那一刻已经扣过），所以"空挥不要钱"并不成立，
			# 只是不再额外罚两秒钟的直线飞行。
			_end_saber()
			return false
		# 直着冲出去（宽限期内；AI 则是整个突进期）
		global_transform = Transform3D(
			global_transform.basis.rotated(global_transform.basis.x, 0.0),
			global_transform.origin)
		velocity = forward() * fm.speed
		if saber_timer <= 0.0:
			_end_saber()
		return true

	var to := tgt.global_position - global_position
	var dist := to.length()
	if dist <= profile.saber_hit_range:
		_slash(tgt)
		return true
	if saber_timer <= 0.0:
		_end_saber()
		return false

	var direction := to / dist
	# The sweep above gets the first chance to hit. After a missed pass,
	# release homing instead of making a U-turn around the opponent.
	if fm.velocity.length_squared() > 1.0 and direction.dot(fm.velocity.normalized()) < -0.05:
		_end_saber()
		return false
	# Keep the current up axis near vertical targets; a fixed world-up
	# becomes singular at the poles and can flip the entire model.
	var up := global_basis.y.normalized()
	if absf(direction.dot(up)) > 0.98:
		up = global_basis.x.normalized()
	var want := Basis.looking_at(direction, up)
	var current_q := global_basis.orthonormalized().get_rotation_quaternion()
	var wanted_q := want.get_rotation_quaternion()
	var angle := current_q.angle_to(wanted_q)
	var weight := minf(1.0 - exp(-16.0 * delta), deg_to_rad(360.0)*delta/maxf(angle,0.0001))
	global_transform = Transform3D(Basis(current_q.slerp(wanted_q,weight)),global_position)
	fm.speed = profile.saber_dash_speed
	# Travel along the homing vector, not the still-turning model nose.
	fm.velocity = direction * fm.speed
	return true


func _slash(tgt: Node3D) -> void:
	if weapons_locked():return
	var facing := forward()
	if tgt is Node3D:
		facing = (tgt.global_position - global_position).normalized()
	if projectile_container != null:
		# 军刀刃色跟着机体走（`alpha = 0` = 没指定 ⇒ `FX` 用老粉白）。
		FX.saber_slash(projectile_container, tgt.global_position, facing, Vector3.UP,
			profile.saber_beam_color)
	# 1.2：命中用**独立音效**（用户素材）—— 之前是压低音量的挥刀声，
	# 于是"挥空"和"砍中"听不出区别（打击感的一半是听觉）。
	# **特效分级**（1.2 方案）：打在 I 立场上是"蓝白力场波纹"，破盾砍到机体上是"橙红火花"。
	# 之前两者共用同一套，于是"砍在盾上"和"砍在肉上"在画面上没有区别。
	var shield_up := false
	if tgt is FlightBody:
		shield_up = (tgt as FlightBody).ifield_hp > 0.0
	if projectile_container != null:
		if shield_up:
			FX.beam_impact(projectile_container, tgt.global_position)
		else:
			# 白热闪光 + 火花：火花是"碎屑"，闪光是"接触面被烧亮"的那一瞬 ——
			# 之前缺这一层，"砍中"的画面分量全靠弧光撑（批 10 打击感）。
			FX.impact_flash(projectile_container, tgt.global_position,
				Color(1.0, 0.92, 1.0))
			FX.hit_spark(projectile_container, tgt.global_position, 1.6)
	Audio.play_3d("saber_impact", tgt.global_position, 0.0)
	var axe_hit:bool=sazabi_systems!=null and sazabi_systems.axe_swing
	var axe_stun:bool=axe_hit and tgt is FlightBody and not tgt.shield_up and not tgt.is_invulnerable()
	tgt.take_damage(profile.saber_damage * damage_mult * melee_guard.DAMAGE_MULT * (3.0 if axe_hit else (1.5 if thunderbolt_systems!=null and thunderbolt_systems.ram_attack else 1.0)), self, Damage.Type.SABER)
	if axe_stun:sazabi_systems.stun(tgt)
	if thunderbolt_systems!=null and thunderbolt_systems.ram_attack and tgt is FlightBody:tgt.apply_thunder_status("ram",facing)
	# **命中停顿（分级）**：军刀是近战重击，比默认档（步枪路径等）长一截；
	# 双方一起顿 —— 只顿砍的人、不顿被砍的人，看起来像"穿模滑过去"。
	begin_hitstop(HITSTOP_TIME_SABER)
	if tgt is FlightBody:
		(tgt as FlightBody).begin_hitstop(HITSTOP_TIME_SABER)
	if is_player:
		Game.saber_hits += 1
		Game.log_event("光束军刀命中敌机")
	saber_hit.emit(tgt)
	_end_saber(true)


## Compatibility hook: timed defensive input now owns clash activation.
## See melee_guard.gd for the 2 s bar and the single 0.2 s success window.
func _try_clash(_delta: float) -> bool:
	# Defensive clashes are committed by a fresh melee press in the green window.
	# Merely holding two old attack states must never bypass the 0.2 s timing.
	return false


## 进入相杀。**双方各自调用一次**（谁先查到对方谁先触发，
## 触发时把对方的军刀态也掐掉，所以第二个人查的时候已经不成立了 —— 天然只触发一次）。
func _begin_clash(other: FlightBody) -> void:
	# ① 双方军刀态结束（**冷却不退回**：起手那一刻已经扣过了，见 `try_saber`）。
	_end_saber()
	other._end_saber()

	# ② **不掉血**：这里不发 `_slash()`、不碰 `take_damage()`。
	#    相杀的本体就是"两边都砍到了对方、但谁也没占到便宜"。

	# ③ 弹开：**各自**背向（沿双方连线）+ 一点竖直分量。
	#    直接写 `fm.velocity`，随后由常规气动把它拉回正常（所以不需要额外衰减逻辑）。
	#
	# ⚠️⚠️ **两行缺一不可**（2026-09-21 修的真 bug）：
	# 原来这里只写了 `_push_back_from(other)`，而注释写的是"**各自**背向" ——
	# `other` 从头到尾没被弹开。加上去重是靠"掐掉对方的 CHARGE"实现的，
	# 所以 `_begin_clash` **只会被调用一次** ⇒ 表现是
	# **谁先扫到对方，谁被弹开；另一个人的速度一点没变**。
	# 相杀于是从"谁也没占便宜"变成了"先检测到的一方吃亏"，与需求原文
	#（"强制弹开一段距离"）直接矛盾。
	_push_back_from(other)
	other._push_back_from(self)

	# ④ 失锁：清掉指向对方的锁定 + 互相不可锁定一段时间。
	#    ⚠️ **只有这一处写入** `unlockable_until`（铁律 6：两个写者 = bug）。
	_clash_lock_out(other)
	other._clash_lock_out(self)

	# ⑤ 顿帧（和军刀命中共用同一套打击感，但用**相杀档**——最重的一档）。
	#
	# ⚠️ **双方都要顿**（2026-09-22 批 10 排查修的真 bug）：原来只 `begin_hitstop()`
	# 了 self —— 而本函数只会被**先检测到的一方**调用一次（触发时把对方的
	# CHARGE 也掐掉了），于是"谁先扫到谁顿、另一个人照飞"，又是那个
	# 相杀经典对称性破裂（和当年"只弹开一方"同款）。现在双方都进相杀档顿帧。
	begin_hitstop(HITSTOP_TIME_CLASH)
	other.begin_hitstop(HITSTOP_TIME_CLASH)
	# 冲击波：拼刀点一圈扩散白环 + 白闪 —— 相杀是整局最重的碰撞，
	# 之前只有 hit_spark，读不出"拼开了"的分量（批 10 打击感）。
	if projectile_container != null:
		FX.clash_shockwave(projectile_container,
			(global_position + other.global_position) * 0.5)
	# 记录痕迹（见 `clash_count` 的说明）：两边各记一次。
	clash_count += 1
	other.clash_count += 1

	# ⑥ 被相杀 **强制脱板**（不吃伤害）。踏板那一轮预留的接口，正好接在这里。
	#
	# ⚠️ **双方都要卸**：只卸发起方的话，"谁先查到对方"就成了决定性的不公平 ——
	# 两边同时撞上去，一个人被掀下板、另一个人还骑着，而相杀的定义就是"谁也没占便宜"。
	# 本轮测试抓到了这一条（只卸了 A、没卸 B）。
	if has_pedal():
		release_pedal()
	if other.has_pedal():
		other.release_pedal()

	if is_player or other.is_player:
		# ⚠️ 判"**玩家是否参与**"而不是"调用方是不是玩家"：谁先扫到对方是调度运气，
		# 记账不能跟着运气走。门禁保证相杀必有一方是玩家（`_try_clash` 限定 ⑥），
		# 旧版 else 分支的"敌机之间军刀相杀"在门禁之后**结构性不可达** —— 已删。
		# （`notice` 信号只存在于 `PlayerController`，中央提示由它接
		# `saber_clashed` 去弹；这里只走**日志**——结算页的战斗经过。）
		Game.log_event("军刀相杀 —— 双方脱锁弹开")
		Game.saber_clashes += 1
	saber_clashed.emit(other)
	# ⚠️ 音效与特效由**两边各放一次**（各自视角都要有），
	# 所以不放在 `is_player` 分支里 —— AI 对撞时玩家在远处也该听见。
	if projectile_container != null:
		var mid := (global_position + other.global_position) * 0.5
		FX.hit_spark(projectile_container, mid, 2.6)
		Audio.play_3d("saber_impact", mid, 1.5, randf_range(0.62, 0.72), 12000.0)


## 弹开：沿"远离对方"的方向给速度。
##
## 用**双方连线**而不是各自的 -forward：两边对冲时机头是相对的，
## 沿连线分开才是"弹开一段距离"；用 -forward 在侧向相杀时会把两边推向同一侧。
func _push_back_from(other: FlightBody) -> void:
	var away := global_position - other.global_position
	if away.length_squared() < 1.0:
		away = -forward()
	away = away.normalized()
	var dir := (away + Vector3.UP * 0.28).normalized()
	fm.velocity = dir * CLASH_PUSH_SPEED
	fm.speed = CLASH_PUSH_SPEED
	fm.boosting = false
	fm.hovering = false


## 相杀之后的失锁：清掉指向对方的目标，并在一段时间内互相锁不上。
func _clash_lock_out(other: FlightBody) -> void:
	unlockable_until = maxf(unlockable_until, Game.clock + CLASH_UNLOCKABLE)
	# 立刻清掉"我正在锁他"这条（`force_drop_if_target` 是现成的入口）。
	# ⚠️ `Game.lock_of()` 返回 Variant（它不认识 `LockOnSystem`），
	# 所以这里不能用 `:=` 推断类型 —— 那会直接编译不过。
	var lk = Game.lock_of(self)
	if lk != null:
		lk.force_drop_if_target(other)
	# 冷却压到相杀冷却：这一条同时保证"刚能重新锁定就再相杀"不会发生
	# （相杀冷却 2.5 s > 失锁 1.2 s，所以重新锁上的时候冷却还在）。
	saber_cooldown = maxf(saber_cooldown, clash_cooldown_secs())


## 相杀**冷却**中（刚相杀完、这段时间里再冲也不会触发第二次）。
##
## ⚠️ 这里查的是**冷却**而不是 `saber_state`：相杀是**瞬时**的 ——
## 触发时双方立刻 `_end_saber()`，所以状态不会停在 `CLASH` 上。
## 早先写过一个 `saber_clashing()`（判 `state == CLASH`），它**永远为假**，
## 是一条看起来能用、实际没人能读到的 API —— 已经换成这一条。
func in_clash_cooldown() -> bool:
	return saber_cooldown > 0.0


## 相杀冷却**还剩多少秒**。
##
## ⚠️ 补这个访问器是因为 `suite_round18` 一直在调它，而它**根本不存在** ——
## 那次调用抛异常、**把它后面的断言全部跳过**（套件照样报数，只是少测了几条）。
## 这类"静默少测"比红更难发现：`N PASS / M FAIL` 里 N 只是变小了。
## 教训：跑完除了看 FAIL，还要看**有没有 SCRIPT ERROR**、以及 N 有没有掉。
func clash_cooldown_left() -> float:
	return maxf(saber_cooldown, 0.0)


func _end_saber(preserve_visual := false) -> void:
	if saber_active() and not has_method("apply_state"):
		_net_report_fire("saber_stop",global_position,forward())
	if clash_debug:
		# ⚠️ **不要用 `get_stack_trace()`**：它在这个工程里会拖垮整套测试
		# （实测 1935 PASS → 1318 PASS / 35 FAIL）。只记一条轻量的来源标记。
		print("    [clash] %s._end_saber (state=%d)" % [name, saber_state])
	saber_state = SaberState.IDLE
	saber_target = null
	saber_timer = 0.0
	# ★63-25：收招之后，撞击豁免再延续 `RAM_GUARD_AFTER_SABER`。
	# ⚠️ 放在**这里（唯一收口）**而不是 `_slash()` 里：命中的那一下固然要免，
	#    但**相杀**（两人贴得更近）与**空挥收招**同样要免 —— 放 `_slash()` 会漏掉相杀。
	# ⚠️ 也覆盖 `preserve_visual = true` 那条路径（收招只保视觉、状态照样回 IDLE）。
	ram_guard_left = RAM_GUARD_AFTER_SABER
	if model_anim != null:
		model_anim.release_saber()
	if preserve_visual and _blade != null and is_instance_valid(_blade):
		var s := SaberMotion.style(profile)
		var time := _saber_visual_clock
		if model_anim != null and model_anim.current == "slash":
			time = model_anim.player.current_animation_position
		_saber_visual_tail = clampf(s["follow"] + 0.10 - time, 0.15, 0.65)
	else:
		_hide_blade()

func _tick_saber_visual(delta: float) -> void:
	if _blade == null or not is_instance_valid(_blade):
		return
	_saber_visual_clock += delta
	var s := _saber_anim_style
	if s.is_empty(): s = SaberMotion.style(profile)
	if saber_active() and not _saber_swing_released:
		var arrival := 0.0
		if is_instance_valid(saber_target) and saber_target is FlightBody:
			var relative := saber_target.global_position - global_position
			var closing := (fm.velocity - (saber_target as FlightBody).fm.velocity).dot(relative.normalized())
			arrival = maxf(relative.length() - profile.saber_hit_range, 0.0) / maxf(closing, 1.0)
		var time := _saber_visual_clock
		if model_anim != null and model_anim.current == "slash":
			time = model_anim.player.current_animation_position
		if time >= float(s["windup"]):
			if arrival > float(s["impact"]) - float(s["windup"]) and saber_timer > 0.2:
				_saber_visual_clock = s["windup"]
				if model_anim != null: model_anim.hold_saber_at(s["windup"])
			else:
				_saber_swing_released = true
				if model_anim != null: model_anim.release_saber()
	if not saber_active():
		_saber_visual_tail = maxf(_saber_visual_tail - delta, 0.0)
		var interrupted := model_anim != null and model_anim.ready and model_anim.current != "slash"
		if _saber_visual_tail <= 0 or interrupted:
			_hide_blade()
			return
	_sync_blade_anchor()


## 亮刀：在**真模型 `hand_L` 骨**上挂一道光束刃（批 10 打击感，见 `_blade` 的注释）。
## 所有出口都收口在 `_end_saber`，所以这里只需在突进开始时调一次。
##
## ⚠️ 2026-10-03（轮 63-4）修「光束军刀刀身在游戏内不显示」：
## 旧实现把刀挂在 `rig.slot("hand_L")` 上，而 `rig` 是**占位骨架** ——
## 只要有真模型（= **所有机体的常态**，见 `:1231` 的 `set_placeholder_visible(false)`），
## 整棵占位子树就被隐藏了 ⇒ 刀**永不显示**（节点在树里、判定照算、只是不可见）。
## 症状之所以长期没被发现：`tests/suite_abilities.gd` 那两条只断言
## "节点存在 / 在树里"⇒ 一直绿（**断言测的是仪器，不是产品**，与 `notes/09` 同源）。
func _show_blade() -> void:
	if profile.id==SuitProfile.Id.PSYCHO_ZAKU_TB or (thunderbolt_systems!=null and thunderbolt_systems.ram_attack):return
	if sazabi_systems != null: return # Its articulated right hand carries the actual blade.
	if profile != null and profile.id == SuitProfile.Id.NEUE_ZIEL:
		_hide_blade()
		_blade_anchor = preload("res://scripts/combat/neue_aux_sabers.gd").new()
		add_child(_blade_anchor)
		return
	_hide_blade()   # 防御：异常路径重复起手时不叠两把
	if rig == null or not is_instance_valid(rig):
		return
	if profile == null:
		return
	# 同上：柯西的主色是绿，其余机体的 `saber_beam_color` 是 alpha=0 ⇒ 老粉白。
	# 长度不再写死 —— 双头剑（柯西：前 15 / 后 9）由 `SuitProfile` 给。
	var rear: float = profile.saber_blade_rear if profile.saber_double else 0.0
	_blade = FX.beam_blade_pair(profile.saber_blade_front, rear, profile.saber_beam_color)
	# Keep every variant's blade outside the hidden placeholder subtree, including
	# Arizeus' unskinned flight form. Skeletal models follow their real hand.
	_blade_anchor = Node3D.new()
	_blade_anchor.name = "SaberAnchor"
	add_child(_blade_anchor)
	_blade_anchor.add_child(_blade)
	if profile.id == SuitProfile.Id.GP03D:
		# GP03D uses one claw saber; increase diameter by 400%, preserving length.
		_blade.scale = Vector3(5.0,5.0,1.0)
	# ---- ① 首选：真模型骨架的手骨 ----
	if _model_skel != null and _bone_index("hand_L") >= 0:
		var bind := _model_skel.get_bone_global_rest(_bone_index("hand_L"))
		var hand_in_body := global_transform.basis.inverse() * _model_skel.global_transform.basis * bind.basis
		_blade_bind_basis = hand_in_body.orthonormalized().inverse()
		var pl := model_anim.player if model_anim != null else null
		if pl != null and not pl.mixer_applied.is_connected(_sync_blade_anchor):
			pl.mixer_applied.connect(_sync_blade_anchor)
		_sync_blade_anchor()
		return
	# 无骨架的巡航形态/占位模型：仍走独立锚点与完整挥刀方向曲线。
	_sync_blade_anchor()


## 同帧跟随真手挂点的位置和旋转。绑定姿态的逆基抵消各导出器的骨轴差异，
## 让刀随手腕挥砍，不再始终沿机头；无骨架形态使用独立挂点及同一方向曲线。
func _sync_blade_anchor() -> void:
	if profile != null and profile.id == SuitProfile.Id.NEUE_ZIEL:
		return
	if _blade_anchor == null or not is_instance_valid(_blade_anchor):
		return
	if (profile.id in [SuitProfile.Id.GP03S,SuitProfile.Id.ZORIN_SOUL] or SuitProfile.is_thunderbolt(profile.id)) and _model_mounts.has("saber_R"):
		var mount: Node3D = _model_mounts["saber_R"]
		_blade_anchor.global_transform = _zorin_mount_world("saber_R") if profile.id==SuitProfile.Id.ZORIN_SOUL else Transform3D(mount.global_basis.orthonormalized(),mount.global_position)
		return
	var idx := _bone_index("hand_L")
	if _model_skel == null or idx < 0:
		var local := rig_anchor("hand_L")
		if not use_placeholder and not _model_mounts.has("hand_L") and not model_bounds.size.is_zero_approx():
			local = Vector3(-model_bounds.size.x * 0.18,model_bounds.position.y + model_bounds.size.y * 0.42,-model_bounds.size.z * 0.16)
		var s := SaberMotion.style(profile)
		var direction := SaberMotion.blade_direction(_saber_visual_clock,s)
		_blade_anchor.global_transform = global_transform * Transform3D(Basis.looking_at(direction,Vector3.UP),local)
		return
	var hand_world := _model_skel.global_transform * _model_skel.get_bone_global_pose(idx)
	_blade_anchor.global_transform = Transform3D(hand_world.basis.orthonormalized() * _blade_bind_basis,hand_world.origin)


func _hide_blade() -> void:
	_saber_visual_tail = 0.0
	if _blade_anchor != null:
		# 锚点是刀身的父节点：收掉锚点，刀随之销毁（`_blade` 一并置空）。
		if is_instance_valid(_blade_anchor):
			_blade_anchor.queue_free()
		_blade_anchor = null
		_blade = null
		return
	if _blade != null:
		if is_instance_valid(_blade):
			_blade.queue_free()
		_blade = null


# ============================================================ 丢弃光束步枪（柯西专属）

## 丢一把枪：强制解除对手对我的锁定，并让自己在 unlock_seconds 内不可被锁定。
## unlock_seconds < 0 时用 profile 的默认值（玩家 15 s；敌机由难度规则传入 0 / 7）。
## ---------------------------------------------------------------- 举盾
##
## 用户要求改成**按一次举 5 秒、冷却 1 秒**（原来是按住）。
##
## 实现上把"举盾中"变成由计时器驱动的状态，而不是"键还按着"：
## 好处是 AI 和玩家走同一套规则，而且 HUD 能画出剩余时间。
## 冷却从**放下盾**开始算，不是从按下开始 —— 否则 5 秒举盾里冷却早就偷偷走完了，
## 变成可以无缝续盾。

## 举盾。返回 false 表示现在举不了（冷却中或已经在举）。
func raise_shield() -> bool:
	if profile.id==SuitProfile.Id.PSYCHO_ZAKU_TB or weapons_locked():return false
	if is_instance_valid(nu_systems) and nu_systems.equipment_cd>0:return false
	if profile.id == SuitProfile.Id.GP03S and gp03s_equipped() == "bazooka":
		return false
	if not alive or shield_cooldown > 0.0 or shield_up:
		return false
	shield_up = true
	shield_timer = 6.0 if profile.id==SuitProfile.Id.FULL_ARMOR_TB else SHIELD_DURATION
	shield_raised.emit()
	# N49：举盾动作（`shield`）。**放在"真的举起来了"之后**，与上面那三条早退同一个口径 ——
	# 冷却中 / 已经举着 / 已阵亡时按键**不该有动作**（那是"没响应"，不是"响应了"）。
	play_model_action("shield")
	melee_guard.shield_press(self)
	return true


## 当前能不能举盾（HUD 用它决定画不画可用状态）。
func can_raise_shield() -> bool:
	if profile.id==SuitProfile.Id.PSYCHO_ZAKU_TB or weapons_locked():return false
	return alive and (not is_instance_valid(nu_systems) or nu_systems.equipment_cd<=0) and shield_cooldown <= 0.0 and not shield_up and not (profile.id == SuitProfile.Id.GP03S and gp03s_equipped() == "bazooka")


func _tick_shield(delta: float) -> void:
	if shield_up:
		shield_timer -= delta
		if shield_timer <= 0.0:
			shield_timer = 0.0
			shield_up = false
			# 冷却从放下盾开始算
			shield_cooldown = 10.0 if profile.id==SuitProfile.Id.FULL_ARMOR_TB else SHIELD_COOLDOWN
			shield_lowered.emit()
	elif shield_cooldown > 0.0:
		shield_cooldown = maxf(shield_cooldown - delta, 0.0)


## 举盾剩余比例（HUD 用）。
func shield_ratio() -> float:
	if SHIELD_DURATION <= 0.0:
		return 0.0
	return clampf(shield_timer / (6.0 if profile.id==SuitProfile.Id.FULL_ARMOR_TB else SHIELD_DURATION), 0.0, 1.0)


func discard_rifle(unlock_seconds := -1.0) -> bool:
	if profile == null or not profile.can_discard_rifle:
		return false
	if rifle_count <= 0 or discard_cooldown > 0.0:
		return false
	discard_cooldown = profile.discard_cooldown
	rifle_count -= 1
	# 丢枪会打断换弹
	rifle_reloading = false
	reload_timer = 0.0

	var secs := unlock_seconds if unlock_seconds >= 0.0 else profile.discard_unlockable_seconds
	if secs > 0.0:
		unlockable_until = Game.clock + secs

	# 强制解除"正在锁定我"的那一方的锁定
	# （Game.lock_of_opponent_of 返回 Variant，所以这里不能用 := 推断）
	var foe_lock = Game.lock_of_opponent_of(self)
	if foe_lock != null:
		foe_lock.force_drop_if_target(self)

	if projectile_container != null:
		FX.jettisoned_rifle(projectile_container,
			global_position + right() * (model_bounds.size.x * 0.5),
			right() * 26.0 + Vector3.DOWN * 12.0)
	if saber_state == SaberState.CHARGE:
		_end_saber()
	Audio.play_3d("ui_item", global_position, -4.0, 1.25)
	if is_player:
		Game.rifles_discarded += 1
		Game.log_event("丢弃光束步枪（剩 %d 把），%.0f 秒内无法被锁定" % [rifle_count, secs])
	rifle_discarded.emit(rifle_count)
	return true


func is_unlockable() -> bool:
	return Game.clock < unlockable_until


func unlockable_seconds_left() -> float:
	return maxf(unlockable_until - Game.clock, 0.0)


# ============================================================ 损伤

func is_alive() -> bool:
	return alive


func is_hostile_to(other: Node) -> bool:
	var fb := other as FlightBody
	if fb == null:
		return true
	return fb.team != team


## 这一发是不是**友军打的**（友军伤害闸门）。
##
## ⚠️ **白名单式，不是黑名单式** —— 只有"来源确实是一台机体、且不是自己"时才判阵营。
## 下面三种**一律放行**，否则会顺手把正常伤害一起挡掉：
##   - `source == null`：撞地 / 撞海 / 世界几何（`Damage.Type.RAM` 的常见来源）；
##   - `source == self`：变形自伤、踏板爆裂把骑手抛出去；
##   - 来源不是 `FlightBody`（`FlightPedal` 也有 `take_damage`，但它不是机体）。
##
## ⚠️ **跨类共用的单一真源**：本函数是 `take_damage()` 与 `Projectile` 命中判定
## **共同**的判据（见 `projectile.gd` 的调用点）。拆成两处各写一遍 `team != team`，
## 迟早有一处分叉 —— 而分叉的症状是"机炮不伤了、光束还在伤"这种极难归因的半失效。
##
## 起因（2026-09-21 实测："而且为啥有自相残杀的"）：整个工程的阵营判定只有
## `is_hostile_to()` 一个真源，但它**只被用在"选目标"这条链上**
##（`live_hostiles_of` → 锁定 / AI / 军刀扫掠）；
## **"伤害落地"这条链上一次都没用过它** —— 于是玩家的机炮扫过僚机，僚机真的掉血。
func is_friendly_fire(source: Node3D) -> bool:
	if source == null or not is_instance_valid(source) or source == self:
		return false
	var fb := source as FlightBody
	if fb == null:
		return false
	return not fb.is_hostile_to(self)


## **无限血开关**（1.2 第二十六轮）：true 时任何伤害都**不掉血**。
##
## 统计照记（`Game.damage_dealt` / `ifield_dealt` 照常入账 —— 教学"命中一次"
## 的判定读的就是它们）、受击闪白照给，但 hp 与 I 立场分毫不动，
## 也永远不会走到 destroy()。教学局用它把靶机变成"打不爆的沙袋"
##（`main.spawn_training` 按 `Game.tutorial_mode` 打开；自由打靶不开）。
var invincible := false


## 两层减伤结算。规则见 Damage 的文件头：
## **I 立场没扣完之前，机体一滴血都不掉**；护盾碎了之后才轮到机体血，
## 这时候主动举盾（F）仍然打一个固定比例折扣。
func take_damage(amount: float, source: Node3D, damage_type := Damage.Type.RAM) -> void:
	if not alive or amount <= 0.0:
		return
	if is_instance_valid(nu_systems) and nu_systems.barrier_active(): return
	# Full Armor: deployed four-shield guard blocks all damage before I-field or hit reactions.
	if profile.id == SuitProfile.Id.FULL_ARMOR_TB and shield_up: return
	# ---- 友军伤害闸门（2026-09-21）----
	#
	# ⚠️ **放在最前面**（在"修复被打断"之前）是有意的：友军的流弹打过来时
	# **连"修复被打断"都不该触发**，否则僚机扫一梭就把你的修复包白吃了。
	# 这一条同时也顺手修好了友军的撞击伤害、踏板火神炮误伤僚机、AI 僚机误伤玩家。
	if is_friendly_fire(source):
		# 拦截不是无声的（2026-09-22 阵营系统完善）：每拦一次记一笔，
		# 结算页"友军拦截"读的就是它 —— 让玩家看见自己的火力线有多密。
		# 弹丸路径不经过这里（命中友军只出 FX，见 `projectile.gd`），
		# 所以计数口径 = "直调 take_damage 被拦下的次数"（军刀 / 撞击 / 溅射等）。
		Game.friendly_fire_blocked += 1
		return
	# Ignore a late network hit from an attack already parried on this client.
	if damage_type == Damage.Type.SABER and is_instance_valid(source) and source.has_method("apply_state") and melee_guard.incoming()==source and melee_guard.result=="格挡成功" and melee_guard.elapsed-melee_guard.center<0.45:
		return
	amount *= Damage.funnel_target_multiplier(profile.id, damage_type)
	# 修复被打断（1.2）：受损即中断 —— 否则"边挨打边回血"等于无敌药。
	# 注意**修复包不退还**：这是刻意的，让"什么时候按 U"成为一个真决策。
	if _repair_left > 0.0:
		_repair_left = 0.0
	# 变身掩护（外壳剥离那 1 秒多）里不吃伤害：否则玩家会在爆炸的同一帧被补死，
	# 那就不是"第二条命"，而是"死两次"。
	if is_invulnerable():
		return

	if damage_type == Damage.Type.SABER:
		if melee_guard.consume_shield(self,source): return
		melee_guard.hit(self)
		if model_fsm != null: model_fsm.interrupt_melee()
		melee_hit_reaction.trigger(self,source)
		if not has_method("apply_state"):
			var hit_direction := Vector3.BACK
			if is_instance_valid(source) and global_position.distance_squared_to(source.global_position)>0.0001:
				hit_direction=(global_position-source.global_position).normalized()
			_net_report_fire("melee_hit",global_position,hit_direction)

	# ---- 飞行踏板这一层（1.2，**只有装了的机体才有**）----
	#
	# ⚠️ **这里是唯一的注入点**。踏板不是独立碰撞体（不给它加碰撞形状），
	# 所以命中链路（`Projectile` 撞到谁就调谁的 `take_damage`）**一行都不用改**：
	# 打到骑手身上的伤害在这里被分流，一部分由踏板吃掉。
	# "不再加一套碰撞层"是这一项最省的地方 —— 判定半径、命中归属都不用碰。
	if is_instance_valid(source) and source.has_method("confirm_zorin_weapon_hit"):
		source.confirm_zorin_weapon_hit(self,damage_type)

	if damage_type == Damage.Type.SABER and source is FlightBody:
		source.combat_buffs.melee_hit(source,self)
	if has_pedal() and combat_buffs.kick_left <= 0.0:
		_route_damage_through_pedal(amount, source, damage_type)
		return

	_apply_damage(amount, source, damage_type)


## ---- 飞行踏板 ----
## 相杀诊断开关（**默认关**，只在排查"相杀为什么不触发"时打开）。
## 排查完就该关掉 —— 它每帧会 `print`，留着会污染测试输出。
var melee_guard = preload("res://scripts/combat/melee_guard.gd").new()
var melee_hit_reaction = preload("res://scripts/flight/melee_hit_reaction.gd").new()
var _melee_attack_serial := 0
var clash_debug := false
## 这台机是不是骑着踏板。**单一判定点**：HUD、AI、伤害分流都读它，
## 不要在别处写 `pedal != null`。
##
## ⚠️ **被载机也算"骑着"**：他站在同一块板上，所以一样受"不能挥军刀、不能悬停"约束，
## 一样按骑乘规则分流伤害。区别只在他不做气动（`_apply_carried`）。
func has_pedal() -> bool:
	return pedal_owner() != null


## 我在**哪块板**上：自己挂着的（领机），否则是被载那条链上领机的板。
##
## 这是"一板载两台"的关键 —— 板上只有**一份耐久**，两台机被打都从它扣，
## 打爆了**两台一起被放下来**（`FlightPedal.break_off()` 会遍历所有 riders）。
func pedal_owner() -> FlightPedal:
	if pedal != null and is_instance_valid(pedal) and pedal.is_alive():
		return pedal
	var l := carried_by
	if l != null and is_instance_valid(l):
		var p := l.pedal_owner()
		if p != null:
			return p
	return null


## 伤害要打进**哪份**踏板耐久。两块板各一位骑手时就是自己的；
## 被载机打进领机那份（同一块板）。
func pedal_hp_pool() -> FlightPedal:
	return pedal_owner()


## 把"被这台机载着"接上。`slot` 0 = 前、1 = 后（见 `FlightPedal.slot_offset`）。
##
## 被载机**不做气动**：`_physics_process` 会走 `_apply_carried()` 把自己贴到挂位上。
## 这样两台永远在同一块板上，而不是"两套独立气动互相追"。
func set_carried_by(leader: FlightBody, slot: int) -> void:
	carried_by = leader
	pedal_slot = slot
	# 被载机不自己拿板；板的挂位由领机的 `pedal` 提供。
	pedal = null


## 我是**被载**的那一台（站在别人的板上，自己不飞）。
func is_carried() -> bool:
	return carried_by != null and is_instance_valid(carried_by)


## 每帧把自己贴到领机的挂位上。
##
## ⚠️ 三件事一起做才算"站在板上"：
##   ① 位置 = 领机踏板的挂位（世界坐标）；
##   ② 姿态 = 领机的姿态（连倾斜都跟着，否则转弯时它像悬在空中）；
##   ③ `fm.velocity` 同步领机的速度 —— **不是气动需要，是武器与瞄准需要**：
##      提前量解算读 `fm.velocity`，不同步的话被载机会朝一个错的方向开火。
func _apply_carried(_delta: float) -> void:
	var l := carried_by
	if l == null or not is_instance_valid(l):
		return
	var p := l.pedal_owner()
	if p == null:
		# 板已经爆了：`FlightPedal.break_off()` 会把我们摘下来并开始失能，
		# 这一帧什么都不做，下一帧 `carried_by` 已经是 null。
		return
	var slot := pedal_slot
	global_transform = Transform3D(l.global_transform.basis, p.slot_world_position(slot))
	fm.velocity = l.fm.velocity
	fm.speed = l.fm.speed


## 给这台机配一块踏板（**只有 AI 敌机会调**，见 `FlightPedal` 的文件头）。
## 必须在机体 `_ready()` 之后调 —— 踏板要读 `model_bounds` 才能对到脚下。
func configure_pedal(kind := -1, force := true) -> FlightPedal:
	if profile != null and profile.id == SuitProfile.Id.REGZ_CUSTOM: return null
	if kind == FlightPedal.Kind.ODYSSEUS and not FlightPedal.is_odysseus(profile):
		return null
	if has_pedal():
		return pedal_owner()
	if rig == null and model_root == null:
		return null
	# 资格门禁：ACE 机（柯西/佩涅罗佩/阿利宙斯）骑不了（用户指定）。
	# ⚠️ 出生配板走 `force = true`（那时**还没人操作**，资格只对"主动搭乘"有意义）；
	# 玩家的搭乘/呼叫必须传 `false`，否则规则形同虚设。
	if not force and profile != null and not profile.can_ride_pedal():
		return null
	var p := FlightPedal.new()
	add_child(p)
	p.setup(self, kind)
	pedal = p
	# ⚠️ **不接 `broken` 信号**：脱板的善后走 `on_pedal_broken()`，
	# 由 `FlightPedal.break_off()` 对板上**每一位**骑手直接调用
	# （一板载两台时两台都要被放下来，信号只带一个 rider 参数表达不了这件事）。
	apply_pedal_flight_bonus()
	return p


# ---- 载具系统：搭乘 / 脱离 / 呼叫（1.2 用户指定）----
#
# 用户原话：「踏板要有**搭乘键和脱离键**，类似载具系统。
# 按键还能**呼叫飞行踏板到自己的位置来**」。
#
# 三条规则：
#   - **资格**：只有量产机骑得了（`SuitProfile.can_ride_pedal()`）。
#     用户原话："AI 僚机能用，然后玩家在操控古斯塔夫和梅萨的时候也能用，
#     但是操控 ACE 机（柯西佩涅罗佩阿利宙斯）不能用"。
#   - **搭乘与呼叫是同一个键**（"我要上板"）：没板就地建一块（= 呼叫到身边），
#     已经有板就直接骑上 —— 拆成两个键会让玩家先想"我该按哪个"。
#   - **脱离**是独立动作，且**不吃伤害**（主动下板不是被打下来）。


## 出生时给自己配一块踏板（**不看"主动搭乘"的资格**，只看"这台机装不装得下板"）。
##
## ## 为什么与 `mount_pedal()` 分开
## `mount_pedal()` 是**玩家/僚机主动上板**那条路，它有资格门禁（ACE 机不可骑）。
## 而出装配板是**开局配置**：那时还没人操作，门禁没有意义 ——
## 而且"这台机该不该有板"已经由编制（`BattleFormation.Unit.is_ace`）决定了。
##
## ⚠️ 仍然必须判"这台机骑不骑得了"：ACE 机（柯西/佩涅罗佩/阿利宙斯）
## 在编制里本来就不会被配板，这里是**第二道闸**，防止将来谁把某个 ACE
## 塞进量产编队时静默给错。
## `kind` 留 −1 表示按机体自动挑板；显式传值时**强制**用那种板
##（测试要钉死板型、模拟"开古斯塔夫却骑马夫蒂板"这种错误配置时用得到）。
func spawn_with_pedal(kind := -1) -> FlightPedal:
	if profile == null or not profile.can_ride_pedal():
		return null
	return configure_pedal(kind, true)


## 这台机**现在**能不能搭乘踏板（资格 + 状态）。
func can_mount_pedal() -> bool:
	if not alive or is_staggered() or in_transform():
		return false
	if has_pedal():
		return false
	if profile == null or not profile.can_ride_pedal():
		return false
	return true


## 搭乘 / 呼叫踏板（同一个键）。
##
## 返回 true 表示**这次调用之后他在板上**。
## 失败原因写进 `pedal_fail_reason()`，HUD 用它给一句话提示 ——
## "ACE 机不可骑"和"已经骑着了"是两件不同的事，玩家要能分辨。
func mount_pedal() -> bool:
	if has_pedal():
		_fail_reason = "已经在踏板上了"
		return true
	if not alive or is_staggered():
		_fail_reason = "失能中 · 无法搭乘"
		return false
	if in_transform():
		_fail_reason = "变形中 · 无法搭乘"
		return false
	if profile == null or not profile.can_ride_pedal():
		_fail_reason = "灵格斯特装型不可搭乘飞行踏板" if profile != null and profile.id == SuitProfile.Id.REGZ_CUSTOM else "ACE 机不可搭乘飞行踏板（只有量产机可以）"
		return false
	# ---- 呼叫中：已经在路上了就别再叫一块 ----
	if pedal_inbound():
		_fail_reason = "踏板已在途中"
		return true
	# ---- **呼叫**：从天而降，不瞬移（1.2 第二十三轮，用户指定）----
	#
	# 用户原话："呼叫踏板也是**先在天上出现才飞到玩家身边**"。
	# 所以这里**不能**走 `configure_pedal()`（那是当场贴在脚下），
	# 而是造一块**挂在世界层**的板、让它自己飞过来；到位之后
	# `FlightPedal._arrive()` 会回调 `_complete_pedal_mount()` 收尾。
	var p := FlightPedal.new()
	var host := get_parent()
	if host == null:
		host = self
	host.add_child(p)
	p.begin_inbound(self, -1)
	_inbound_pedal = p
	_fail_reason = ""
	return true


## 这块板**正在飞过来**（还没骑上）。HUD 用它提示"踏板在途中"。
func pedal_inbound() -> bool:
	return _inbound_pedal != null and is_instance_valid(_inbound_pedal)


## 呼叫的板**到位了** —— 由 `FlightPedal._arrive()` 回调。
##
## ⚠️ 这是"呼叫路径"完成挂载的**唯一入口**，它必须把 `configure_pedal()` 里
## 该做而这里也没做的事补齐（登记骑手、贴飞行加成），否则会出现
## "板看着贴在脚下、但玩家一点加成都没有"这种半生效状态。
func _complete_pedal_mount(p: FlightPedal) -> void:
	if p == null or not is_instance_valid(p):
		return
	_inbound_pedal = null
	p.add_rider(self)
	pedal = p
	apply_pedal_flight_bonus()
	pedal_arrived.emit(p)


## 主动脱离踏板（`release_pedal()` 已经在了：被相杀/撞地也走它）。
func dismount_pedal() -> bool:
	if not has_pedal():
		_fail_reason = "不在踏板上"
		return false
	release_pedal()
	_fail_reason = ""
	return true


## 上一次搭乘/脱离失败的原因（空串 = 没失败过）。HUD 读它弹一句话。
func pedal_fail_reason() -> String:
	return _fail_reason


func clear_pedal_fail_reason() -> void:
	_fail_reason = ""


## 骑乘期间的伤害分流：一部分进踏板，一部分照常进机体。
##
## ⚠️ 耐久池取 `pedal_hp_pool()` 而不是 `pedal`：**一板载两台时两台共用一份耐久**，
## 被载机（`pedal` 为 null）打进去的伤害也必须从同一块板上扣。
func _route_damage_through_pedal(amount: float, source: Node3D, damage_type: int) -> void:
	var board := pedal_hp_pool()
	if board == null:
		_apply_damage(amount, source, damage_type)
		return
	var split := FlightPedal.damage_split(amount, board.hp, true)
	var to_pedal: float = split["to_pedal"]
	var to_hull: float = split["to_hull"]
	if to_pedal > 0.0 and board.take_damage(to_pedal):
		# 这一发把板打爆了：**脱板的那一刻就发生**，而不是等计分结算。
		# `break_off()` 会**同步**遍历板上所有骑手回调 `on_pedal_broken(self, true)`，
		# 并**返回它处理过的那份名单**。
		# ⚠️ 必须用返回值判断"我有没有被处理过"：`break_off()` 已经把 `riders`
		# 清空了，事后查它永远查不到（早先那个判断因此恒为真、
		# 于是每个骑手被善后两次）。而被载机（板挂在领机身上）确实可能不在名单里。
		var processed := board.break_off()
		if not processed.has(self):
			on_pedal_broken(board, true)
		Game.log_event("踏板被击毁")
		if source == Game.player:
			Game.pedals_destroyed += 1
	if to_hull > 0.0:
		_apply_damage(to_hull, source, damage_type)


## 踏板爆掉：把骑手抛出去 + 短暂失能 + 吃一轮伤害。
##
## ⚠️ **这是"骑手被脱板"的唯一写入点**。`abort_pedal()` 也走它，
## 于是"被打爆"与"主动脱板"共用同一套善后（区别只在要不要吃伤害）。
## 骑手被放下（**板爆了**，或者主动脱板）。
##
## ## 失能时长由**谁放下他**决定（`by_break`）
##
## 这是本轮定下的规则，两条路必须分开：
##   - `by_break = true`（板**被打爆**）⇒ **进失能**（`STAGGER_TIME`）。
##     这是玩家"把敌人从板上打下来"那一刻的回报 —— 他要有一个可抓的窗口。
##   - `by_break = false`（**主动脱板**：按 T 下去 / 被相杀强制 / 切换战斗方式）
##     ⇒ **不进失能**。自己下板不是被打下来，罚他就是在罚一个主动决策。
##
## ⚠️ 早先的实现是"先把 `_stagger_timer` 清零，再由这里统一设成 0.8" ——
## 于是主动脱板也会被罚 0.8 s（`release_pedal()` 那行清零**完全无效**）。
## 本轮被测试抓到（`got 0.7833 want 0.0000`）。**改动前想清楚哪条路该罚。**
##
## ⚠️ 另一个前提：**骑板时挥不了军刀**（`try_saber` 的 `pedal_restricts_melee`），
## 而相杀要求双方都在军刀突进态 —— 所以"被相杀强制脱板"这条路
## **目前在骑乘状态下不可达**。接口按正确方式接好了，等那条限制松动才会真走到。
func on_pedal_broken(board: FlightPedal, by_break := true) -> void:
	if board != null and is_instance_valid(board):
		board.remove_rider(self)
	pedal = null
	carried_by = null
	_stagger_timer = FlightPedal.STAGGER_TIME if by_break else 0.0
	# 把踏板的飞行加成**摘掉**：`_apply_profile_to_flight()` 会按 profile 重设
	# 转向基值并重算 speed/accel，而此刻 `has_pedal()` 已经是 false，
	# 所以油门响应与转向折扣一起回到正常值。
	_apply_profile_to_flight()
	# 抛出：**向上 + 向后**（沿着机头反方向）。把速度矢量整根换掉，
	# 让它立刻失去踏板的巡航优势 —— 这是"打掉踏板"在体感上最直接的一下。
	var back := -forward()
	fm.velocity = (back * 0.75 + Vector3.UP * 0.55).normalized() * FlightPedal.THROW_SPEED
	fm.speed = FlightPedal.THROW_SPEED
	if projectile_container != null:
		FX.explosion(projectile_container, global_position, 0.7)
	Audio.play_3d("boom_s", global_position, 0.0)


## 主动脱板（掉头缠斗、撞地、被相杀时调）。**不吃伤害**。
## 主动脱离踏板（**不吃伤害、也不进失能**）。
##
## 使用者：`dismount_pedal()`（按 T / 按 N 下板）、相杀时强制脱板。
## 与"板被打爆"那一路的区别见 `on_pedal_broken()` 的 `by_break`。
##
## ⚠️ 实现上 **不能只把 `_stagger_timer` 清零**：`break_off()` 会同步回调
## `on_pedal_broken()`，而那个函数才是失能的唯一写入点 ——
## 所以这里必须**把"这是主动脱板"这件事传下去**（`by_break = false`）。
## 早先那版只清了零，结果主动下板照样被罚 0.8 s（测试 `got 0.7833 want 0.0000`）。
func release_pedal() -> void:
	var board := pedal_owner()
	if board == null:
		return
	# ⚠️ `by_break = false` 必须**从这一层传进去**，不能在 `release_pedal()` 里
	# 事后补救（比如"先清零再让回调覆盖"）—— 失能的唯一写入点是
	# `on_pedal_broken()`，所以在它被调用时就得分清是哪条路。
	#
	# `break_off(false)` 会把板上**每一位**骑手都按"主动脱板"处理（含领机），
	# 所以返回之后不需要再补任何善后 —— 补了就是第二次调用。
	board.break_off(false)


## 骑乘中：不能挥军刀、不能悬停。
##
## ⚠️ **1.2 第十九轮起它不再拦军刀**（见 `try_saber()` 里那段说明）：
## 量产机骑板赶路之后，"骑板禁军刀"会让那六台整场近战残废，
## 而且让**相杀对骑板者永远不可达**。这个函数保留是为了：
##   - 悬停那条限制仍然生效（由 `_apply_flight` 读 `has_pedal()` 处理）；
##   - 将来若要恢复"骑板禁刀"，改 `try_saber()` 一处即可。
## **不要再拿它当军刀门禁** —— 那正是被本轮推翻的那条规则。
func pedal_restricts_melee() -> bool:
	return false


func pedal_staggered() -> bool:
	return _stagger_timer > 0.0


## 把踏板的飞行加成贴到飞行模型上（**幂等地"设"值，不是乘上去**）。
##
## ⚠️ 必须是**赋值**而不是 `*= `：`configure()` 每次都会按 top_speed 重算
## accel / ab_accel / brake，所以这里只要按"当前基值 × 倍率"设一遍就对了；
## 写成累乘的话，变形一次就乘一次，两次之后敌机会变成火箭。
##
## 只改**响应**（加速 / 加力加速 / 减速）+ **转向折扣**，
## **不碰 max_speed / ab_speed**：
##   - 最高速不动 ⇒ 第十四轮"敌机 ≤ 玩家加力 ×0.92"那条不变量原样成立；
##   - 转向折扣是踏板**唯一的代价**，见 `FlightPedal.RIDE_TURN_MUL`。
##
## ⚠️ 转向折扣用 `_pedal_turn_applied` 做**一次性的幂等标记**：
## 它乘在 `_apply_profile_to_flight()` 刚设好的基值上，而那之后
## `_apply_top_speed()` 还会被调（挂载踏板时、变形时）——
## 没有这个标记的话每调一次就多乘一次 0.8，两次之后敌机就转不动了。
func apply_pedal_flight_bonus() -> void:
	if fm == null:
		return
	if not has_pedal():
		return
	# 基值 = `FlightModel.configure()` 里那三条按 top_speed 的比例式，在 configure 之后重算：
	# 这里没有保存"基值"，所以从 max_speed 反推（与 configure 用的是同一个 top_speed）。
	if profile.pedal_speed_cap > 0.0:
		fm.max_speed = profile.pedal_speed_cap
		fm.ab_speed = profile.pedal_speed_cap
	var base_accel := fm.max_speed * 0.17
	var base_ab := fm.max_speed * 0.36
	var base_brake := fm.max_speed * 0.27
	var m := FlightPedal.RIDE_THROTTLE_RESPONSE
	fm.accel = base_accel * m
	fm.ab_accel = base_ab * m
	fm.brake = base_brake * m
	if not _pedal_turn_applied:
		_pedal_turn_applied = true
		var t := FlightPedal.RIDE_TURN_MUL
		fm.pitch_rate *= t
		fm.roll_rate *= t
		fm.yaw_rate *= t


## 两层减伤结算。规则见 `Damage` 的文件头：
## **I 立场没扣完之前，机体一滴血都不掉**；护盾碎了之后才轮到机体血，
## 这时候主动举盾（T）仍然打一个固定比例折扣。
##
## ⚠️ 这是**伤害真正落地的地方**，而它只从 `take_damage()` 进来 ——
## 也就是说"经不经过飞行踏板"的分流在上一层就做完了，这里对踏板一无所知。
## 这样分层的好处是：加踏板**没有改动这一层的任何一条规则**。
func _apply_damage(amount: float, source: Node3D, damage_type: int) -> void:
	if combat_buffs.immune(): return
	if source is FlightBody and not source.has_method("apply_state"):
		amount *= source.combat_buffs.damage_rate(damage_type)
	if is_instance_valid(nu_systems) and nu_systems.barrier_active(): return
	# A raised physical shield completely blocks rifle beams before the I-field.
	if shield_up and profile.shield_reduction>0.0 and damage_type==Damage.Type.BEAM:
		return
	var to_hull := amount
	var ifield_before := ifield_hp

	# ---- 第 1 层：I 立场。护盾没碎之前机体一滴血不掉 ----
	if ifield_hp > 0.0 and combat_buffs.kick_left <= 0.0:
		var eff := Damage.ifield_efficiency(damage_type)
		var need := amount / eff              # 吸收这一发要花多少护盾值
		if need <= ifield_hp:
			ifield_hp -= need
			to_hull = 0.0
		else:
			# 这一发把护盾打爆：护盾吃下它能吃的，剩下的溢出到机体
			var absorbed := ifield_hp * eff
			to_hull = amount - absorbed
			ifield_hp = 0.0
		if ifield_hp <= 0.0 and not _ifield_broken_emitted:
			_ifield_broken_emitted = true
			ifield_broken.emit()
			if is_player:
				Game.ifield_broken_self = true
				Game.log_event("I 立场被击穿")
			else:
				Game.ifield_broken_foe = true
				Game.log_event("敌机 I 立场被击穿")

	# ---- 统计：谁打谁、打在护盾上还是打在机体上 ----
	var shield_used := ifield_before - ifield_hp
	var from_player := source != null and is_instance_valid(source) and source == Game.player
	if is_player:
		Game.damage_taken += to_hull if to_hull > 0.0 else 0.0
		Game.ifield_taken += shield_used
	if from_player:
		Game.damage_dealt += to_hull if to_hull > 0.0 else 0.0
		Game.ifield_dealt += shield_used

	# ---- 第 2 层：主动举盾（护盾已碎也照样生效）----
	if shield_up and to_hull > 0.0:
		to_hull *= (1.0 - profile.shield_reduction)

	combat_buffs.record_damage(self,source,minf(maxf(to_hull,0.0),maxf(hp,0.0)),shield_used * Damage.ifield_efficiency(damage_type))
	if to_hull <= 0.0:
		# 全被 I 立场吃下：不掉血。命中的视觉反馈由弹丸侧的命中特效负责，
		# 这里不发 damaged 信号（否则镜头会因为"零伤害"抖一下，很怪）。
		#
		# 但**不能什么都不发**（§4.9.2⑤）：护盾期可以长达几十秒，全程零反馈
		# ⇒ 玩家读不出"我正在被打"。所以走一条**语义分开**的 `ifield_hit`：
		# 它不叫"受损"，叫"护盾被消耗"，幅度由接收方按护盾池自己折算。
		#
		# ⚠️ 只在**真的消耗了护盾**时发：`shield_used == 0`（零伤害命中）时
		# 发一条 0 吸收量的信号没有意义，而且会让任何"命中计数"凭空多一份。
		if shield_used > 0.0:
			ifield_hit.emit(shield_used, source, damage_type)
		return

	# ---- 无限血（1.2 第二十六轮）----
	# 放在统计之后：上面 damage_dealt / ifield_dealt 已照常入账（教学"命中
	# 一步"的判定读它们）；受击反馈照给（damaged 信号、闪白）。
	# 但**血量一滴不掉** —— 教学局里靶机永远打不爆，也就永远不会
	# 走到下面的扣血 / 变身 / destroy 分支。
	if invincible and to_hull > 0.0:
		_hit_flash = 1.0
		damaged.emit(to_hull, source, damage_type)
		return

	hp -= to_hull
	combat_buffs.execute_if_needed(self,source)
	if not alive or in_transform(): return
	_hit_flash = 1.0
	damaged.emit(to_hull, source, damage_type)
	if hp <= 0.0:
		# 1.2 用户要求：**外壳的血条扣完之后不是"死"，而是"脱出"** ——
		# 血量归零 → 爆壳 → 换成核心形态**自己的一条满血**（核心没有 I 立场）。
		# 这就是"第二条命"的字面实现：外壳打光只是把第一条命用完。
		if profile != null and not _transformed and profile.transform_to_form >= 0:
			hp = 0.0
			_begin_transform()
			return
		hp = 0.0
		destroy(source)
		return
	# 战损爆壳：血量第一次降到线以下就开始变身（一次性）。
	# 放在扣血之后、最终判定之后 —— 于是"这一发正好把血打光"仍然是直接击坠，
	# 不会出现"明明该炸了却先变身"的怪事（那等于白送一条命）。
	if profile != null and not _transformed and profile.transform_hull_ratio > 0.0 \
			and hp_ratio() <= profile.transform_hull_ratio:
		_begin_transform()


## killer 用于结算；reason 仅用于调试日志。
func destroy(killer: Node3D, reason := "") -> void:
	# **同步**清掉所有指向自己的锁定目标（见 `Game.forget_locks_of` 的注释）：
	# 等到锁定系统在下一个物理帧自己发现，中间那一帧里"带类型读取已释放目标"
	# 就会抛 `previously freed` —— 屏幕上的表现是随机报错。
	Game.forget_locks_of(self)

	if not alive:
		return
	alive = false
	_wreck_timer = 2.2
	_end_saber()
	var parent := get_parent()
	if parent != null:
		FX.explosion(parent, global_position, 1.0)
	# boom_l = 机体爆炸。max_distance 放得很大：十几公里外有人被打爆时，
	# 夜战里应该还能听到一点动静，而不是死寂。
	Audio.play_3d("boom_l", global_position, 2.0, randf_range(0.94, 1.04), 26000.0)
	# 引擎循环要显式停掉：单位还有 2.2 秒才 queue_free，这段时间不该继续轰鸣
	if _engine != null:
		_engine.stop()
	if _detect_timer != null:
		_detect_timer.stop()
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	# ⚠️ ★63-9 B1：**愿望也要一起置假** —— 实际可见性 = 愿望 ∧ 非骑手隐藏，
	# 只裸写 `model_root.visible` 的话，踏板那边下一次同步（`set_rider_hidden(false)`）
	# 会把残骸重新显回来（它只重算那一次，不知道机体已经没了）。
	_model_wish = false
	if model_root != null:
		model_root.visible = false
	if _afterburner_fx != null:
		_afterburner_fx.emitting = false
	# 冲刺焰与马赫环一起灭（机体已经藏起来了，还在喷就是"隐形的引擎"）。
	if _dash_fx != null:
		_dash_fx.emitting = false
	if _dash_rings != null:
		_dash_rings.emitting = false
	# 多喷口也要一起灭 —— 机体已经藏起来了，喷口还在喷就是"隐形的引擎"
	for item: Dictionary in _plume_fx:
		var jet := item.get("fx") as GPUParticles3D
		if jet != null and is_instance_valid(jet):
			jet.emitting = false
		var bf2 := item.get("boost") as GPUParticles3D
		if bf2 != null and is_instance_valid(bf2):
			bf2.emitting = false
		var glow := item.get("glow") as MeshInstance3D
		if glow != null and is_instance_valid(glow):
			glow.visible = false
	Game.notify_destroyed(self, killer)
	destroyed.emit(killer)
	if is_player:
		Game.log_event("自机被击坠" if reason == "" else "自机坠毁（%s）" % reason)
	elif killer != null and is_instance_valid(killer) and killer == Game.player:
		Game.log_event("敌机坠毁 —— %s" % display_name)
	if reason != "":
		print("[destroy] %s: %s" % [display_name, reason])


# ============================================================ 只读

func forward() -> Vector3:
	return -global_transform.basis.z


func up() -> Vector3:
	return global_transform.basis.y


func right() -> Vector3:
	return global_transform.basis.x


func airspeed_kmh() -> float:
	return fm.airspeed_kmh()


func hp_ratio() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


func ifield_ratio() -> float:
	if ifield_max <= 0.0:
		return 0.0
	return clampf(ifield_hp / ifield_max, 0.0, 1.0)


func has_ifield() -> bool:
	return ifield_hp > 0.0


func distance_to_unit(other: Node3D) -> float:
	if other == null or not is_instance_valid(other):
		return INF
	return global_position.distance_to(other.global_position)


## 是否有导弹正在追我（AI 规避与 HUD 告警都用它）。
func incoming_missiles() -> Array[Node]:
	var out: Array[Node] = []
	# 组快照走 Game 的每物理帧缓存（批 10 性能二轮）：每台 AI 每帧不再各自分配
	for m: Node in Game.group_snapshot(get_tree(), "missiles"):
		var ms := m as Missile
		if ms == null or not is_instance_valid(ms):
			continue
		if ms.target == self:
			out.append(ms)
	return out
# ============================================================ 修复包（1.2）

func repair_active() -> bool:
	return _repair_left > 0.0


## ★63-24：修复通道时长 / 单包回复比例改读 profile（默认 = 原常量）。
func repair_time_secs() -> float:
	return profile.repair_time if profile != null else REPAIR_TIME


func repair_frac() -> float:
	return profile.repair_fraction if profile != null else REPAIR_FRACTION


## 现在能不能修：有包、活着、没满血、也没在修。
func can_repair() -> bool:
	return repair_packs > 0 and alive and hp < max_hp and _repair_left <= 0.0


## 用一个修复包开始修复。返回是否真的开始了。
func start_repair() -> bool:
	if not can_repair():
		return false
	repair_packs -= 1
	_repair_left = repair_time_secs()
	_repair_total = max_hp * repair_frac()
	return true


## 修复进度（0..1），HUD 用。
func repair_ratio() -> float:
	if _repair_left <= 0.0:
		return 0.0
	return clampf(1.0 - _repair_left / repair_time_secs(), 0.0, 1.0)


func _tick_repair(delta: float) -> void:
	if _repair_left <= 0.0:
		return
	var step_dt := minf(delta, _repair_left)
	_repair_left = maxf(_repair_left - delta, 0.0)
	hp = minf(hp + _repair_total * (step_dt / repair_time_secs()), max_hp)


var gp03s_weapon := "rifle"

func gp03s_equipped() -> String:
	return str(call("current_slot")) if has_method("current_slot") else gp03s_weapon

func gp03s_equip(slot: String) -> void:
	if profile == null or profile.id != SuitProfile.Id.GP03S or slot not in ["rifle","bazooka","saber"]: return
	var changed := gp03s_weapon != slot
	gp03s_weapon = slot
	if slot == "bazooka" and shield_up:
		shield_up = false
		shield_timer = 0.0
		shield_cooldown = SHIELD_COOLDOWN
	if is_instance_valid(model_root):
		var rigged := model_root.find_child("GP03S",true,false)
		if rigged != null: rigged.animate(0.0)
	if changed: _net_report_fire("gp03s_equip_"+slot,global_position,forward())

func _gp03s_pose(action: String) -> void:
	gp03s_equip(action)
	if not is_instance_valid(model_root): return
	var rigged := model_root.find_child("GP03S",true,false)
	if rigged != null: rigged.animate(0.0)

func fire_gp03s_bazookas(target: Node3D = null) -> bool:
	if weapons_locked(): return false
	if has_method("current_slot") and gp03s_equipped() != "bazooka": return false
	if profile.id != SuitProfile.Id.GP03S or not alive or projectile_container == null or in_transform() or is_staggered() or bazooka_cd > 0.0 or bazooka_reload_left > 0.0 or bazooka_mag < 2:
		return false
	bazooka_cd = 1.1
	_gp03s_pose("bazooka")
	for key in ["bazooka_L","bazooka_R"]:
		var from := global_transform * rig_anchor(key)
		Missile.spawn(projectile_container,from,forward(),target,self,35.0,Missile.Trail.LOW)
	bazooka_mag -= 2
	if bazooka_mag <= 0: reload_bazooka()
	if is_player: Audio.play_self("funnel_fire",-3.0)
	else: Audio.play_3d("funnel_fire",global_position,-3.0)
	_net_report_fire("gp03s_bazookas",global_position,forward())
	gun_fired.emit()
	return true

func reload_bazooka() -> bool:
	if bazooka_mag >= GP03_BAZOOKA_MAG or bazooka_reload_left > 0.0:
		return false
	bazooka_reload_left = GP03_BAZOOKA_RELOAD
	return true

func fire_bazooka(target: Node3D = null) -> bool:
	if weapons_locked(): return false
	if not alive or projectile_container == null or in_transform() or is_staggered() or bazooka_cd > 0.0 or bazooka_reload_left > 0.0 or bazooka_mag <= 0:
		return false
	var from := global_transform * rig_anchor("muzzle_L")
	Missile.spawn(projectile_container, from, forward(), target, self, 45.0, Missile.Trail.LOW)
	bazooka_mag -= 1
	bazooka_cd = GP03_BAZOOKA_INTERVAL
	if bazooka_mag == 0:
		reload_bazooka()
	Audio.play_3d("funnel_fire", from, -6.0)
	_net_report_fire("bazooka", from, forward())
	gun_fired.emit()
	return true

func try_gp03_grapple(target: Node3D) -> bool:
	if weapons_locked(): return false
	if not saber_locked() and melee_guard.elapsed < melee_guard.BAR_TIME and is_instance_valid(melee_guard.incoming()) and melee_guard.incoming().saber_active():
		return melee_guard.press(self)
	if profile.id != SuitProfile.Id.GP03D or not alive or projectile_container == null or is_staggered() or in_transform() or grapple_cd > 0.0 or is_instance_valid(active_grapple) or is_instance_valid(gp03_grab_owner):
		return false
	if not is_instance_valid(target) or not target is FlightBody or not target.alive or target.team == team or is_instance_valid(target.gp03_grab_owner) or global_position.distance_to(target.global_position) > 1300.0:
		return false
	var grapple = preload("res://scripts/combat/gp03_grapple.gd").new()
	grapple.shooter = self
	grapple.victim = target
	active_grapple = grapple
	grapple_cd = 8.0
	projectile_container.add_child(grapple)
	return true

func weapons_locked() -> bool:
	return thunder_lock_left>0 or flash_blind_left>0

func apply_thunder_status(kind:String,direction:=Vector3.ZERO)->void:
	if not alive or is_invulnerable() or in_transform():return
	if has_method("apply_state"):
		Net.send_thunder_status(kind,direction);return
	if kind=="sting":
		thunder_lock_left=maxf(thunder_lock_left,7.0)
		thunder_slow_rate=minf(thunder_slow_rate,.1) if thunder_slow_left>0 else .1
	elif kind=="ram":
		thunder_slow_rate=.05
		var travel:=direction.normalized()*3000.0
		var query:=PhysicsRayQueryParameters3D.create(global_position,global_position+travel,1)
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		global_position=hit.position-direction.normalized()*20 if not hit.is_empty() else global_position+travel
	else:return
	thunder_slow_left=7.0
	if is_instance_valid(active_cannon):active_cannon.queue_free();active_cannon=null
	if is_player:emit_signal("notice","刺雷命中 · 武器封锁7秒" if kind=="sting" else "盾牌冲撞 · 减速7秒",2)


func saber_locked() -> bool:
	return melee_guard.impact_left > 0.0



## Subclasses may rescue an assisted player immediately before ground destruction.
func _prevent_ground_crash() -> bool:
	return false

## External thrust stays simulated but cannot render inside the cockpit, including live particles.
func _sync_cockpit_propulsion_visibility() -> void:
	for effect: Node3D in [_afterburner_fx,_dash_fx,_dash_rings,_boost_trail]:
		if is_instance_valid(effect): effect.visible = _model_wish
	for item: Dictionary in _plume_fx:
		for key in ["fx","boost","ab","dash"]:
			var effect := item.get(key) as Node3D
			if is_instance_valid(effect): effect.visible = _model_wish
		var glow := item.get("glow") as Node3D
		if is_instance_valid(glow) and not _model_wish: glow.visible = false


func rifle_aim_point(origin:Vector3,target:Node3D,lead:bool)->Vector3:
	return aim_point(origin,target,lead,0.0,true,true)


## Called only by an accepted, positive enemy weapon hit. The firing peer owns its gauge.
func confirm_zorin_weapon_hit(victim: Node3D, kind: int) -> void:
	if profile==null or profile.id!=SuitProfile.Id.ZORIN_SOUL or not alive or has_method("apply_state"):return
	if kind not in [Damage.Type.BEAM,Damage.Type.VULCAN,Damage.Type.SABER,Damage.Type.BEAM_CANNON]:return
	if not is_instance_valid(victim) or not is_hostile_to(victim):return
	jet_left=profile.jet_seconds
	dash_charge=1.0;dash_cd=0.0
	_jet_assist_recover=false


## Read the evaluated wrist pose directly; BoneAttachment nodes update later in the frame.
func _zorin_mount_world(slot:String)->Transform3D:
	var marker:Node3D=_model_mounts.get(slot)
	if not is_instance_valid(marker):return global_transform
	var attach:=marker.get_parent() as BoneAttachment3D
	if attach!=null:
		var skeleton:=attach.get_parent() as Skeleton3D
		if skeleton!=null:
			var bone:=skeleton.find_bone(attach.bone_name)
			if bone>=0:
				var world:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(bone)*marker.transform
				return Transform3D(world.basis.orthonormalized(),world.origin)
	return marker.global_transform


func apply_flashbang(origin: Vector3) -> bool:
	if not alive or has_method("apply_state") or not origin.is_finite() or global_position.distance_squared_to(origin)>4000.0*4000.0:return false
	flash_blind_left=3.0
	if is_player:
		if not is_instance_valid(_flashbang_overlay):
			_flashbang_overlay=preload("res://scripts/ui/flashbang_whiteout.gd").new()
			_flashbang_overlay.unit=self
			add_child(_flashbang_overlay)
		_flashbang_overlay.refresh()
	return true
