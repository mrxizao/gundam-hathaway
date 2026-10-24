class_name ModelAnimFSM
extends RefCounted
## 柯西交付动作（`fly` / `burst` / `burst_cruise`）的**切换状态机**（棒 12 · 2026-09-26）。
##
## ## 为什么已有的 `ModelAnimator` 还不够
##
## `ModelAnimator` 只回答"**怎么播一个动作**"，它**没有状态**。
## 于是"播完 `burst` 该回哪里 / 巡航形态该选哪一版发射动作 / 发射途中形态变了要不要打断"
## 这三件事原先散在 `FlightBody` 的三个函数里：
##
##   * `_tick_model_anim()` 判"播完了吗"、并决定回 `idle_action`；
##   * `full_burst_action()` 判形态（`cruise_morph >= 0.5`）并选版本；
##   * `play_model_action()` / `play_full_burst()` 负责真的喊下去。
##
## **没有单一真相源**：想实现"发射途中不许被形态切换打断"，得同时改这三处，
## 而且改漏了不会报错，只会在某次玩法里闪一下错误形态 —— 属于最难查的那类问题。
##
## 这个类把那三处收成一张显式状态图：
##
##     NONE ──(模型无 AnimationPlayer：18 个老资产全是这条)──► 死路，一切方法是空操作
##
##     IDLE ──request_burst()──► BURST ──(动作播完)──► IDLE
##       ▲                                              │
##       └────── 形态切换在 IDLE 立刻生效；在 BURST 挂起，等发射结束再生效 ──────┘
##
##     IDLE ──set_dash("r")──► DASH ──set_dash("")──► IDLE        （N46 八向冲刺）
##
## ## 分支顺序即优先级（`tick()` 里从上到下）
##
##     BURST ／ FORM  ＞  DASH  ＞  形态切换  ＞  待机
##
## 冲刺**不能**打断发射与形态过渡（那两条必须播完整），但可以抢在形态切换之前。
##
## ## 四条硬约束（都是实测换来的，不是设计洁癖）
##
## **① 老资产必须逐位不变。** 18 个老 glb 全部 `skins: 0 / animations: 0`
## （`glb_morph_probe.py` 实测）⇒ `ModelAnimator.ready == false` ⇒
## 这里 `state == NONE`。`request_burst()` 返回 `false`、`tick()` 直接 return，
## **且不 `push_warning`**（每个老机体都会走到，吼一声会把日志淹掉）。
## 所以 `create()` **永不返回 `null`** —— 宿主不必到处判空，这本身就是个防错设计。
##
## **② 事件驱动 ≠ 帧驱动。** `request_burst()` 是"**发射那一帧喊一次**"，
## 所以重复喊**必须重播**（20 s 冷却结束后再打一轮，动画得从头放）；
## 而 `tick()` 是**每帧**喊，**绝不能重播** —— 否则进度永远被按在第 0 帧，
## 表现是"动作播了但看不出在动"（`ModelAnimator.play_once()` 里也踩过这个坑）。
## 两条路径靠 `restart` 参数显式分开，**不靠"猜调用频次"**。
##
## **③ `burst` 与 `burst_cruise` 的形态基准不同**（前者起于常态待机、
## 后者起于巡航待机）。选错会在发射前看到一次形态跳变 ⇒
## 形态只影响"选哪一版"，且**发射途中不许换**：`set_form()` 在 BURST 期间
## 只写 `_want_form`，等发射结束才落到 `form`。
##
## **④ 状态推进只有一个入口。** `set_form()` 从不直接切动作，它只改目标形态；
## 真正的切换全部发生在 `tick()` 里。测试因此可以**只驱动 `tick()`** 就复现全部行为，
## 不需要去戳私有字段。

# ============================================================ 状态与形态

## 状态。`NONE` = 这个模型没有动画能力（老资产），不是错误态。
##
## `FORM` = 正在播**形态过渡动作**（`form_on` / `form_off`，一次性），播完自动落到目标形态的待机。
## 只有配了过渡动作的机体（柯西）才会进入这个态；其余机体在第一道判据就返回
## ⇒ 状态图与改动前逐位一致。
##
## `DASH` = 正在播**方向动作族**里的一段（循环），由 `set_dash()` / `set_fly_dir()` 进、
## 两个方向名都为空则出（N46 起；N49 起覆盖两族）。
##
## ★ **一族动作、一个态**（N49）：
##   · `dash_<dir>` —— 冲刺激活时（宿主给 `_dash_anim_dir`）；
##   · `fly_<dir>`  —— 常态平飞时（宿主给 `translate_dir`）。
##   两者**共用同一张八向表**（`FlightBody.DASH_DIR_NAMES`）、同一套进入/退出/改向逻辑，
##   差别只在**选哪个前缀**。分开写两个态会得到两份会各自漂移的改向代码。
##
## `TURN` = 正在播**姿态微调**里的一段（`turn_<轴>`，循环，N49）。由 `set_turn()` 进、
## 轴名清空则出。它是与 DASH **并列的第二套方向语义**：DASH 收的是**平移方向**
##（`translate_dir` / 冲刺方向），TURN 收的是**三轴姿态**（`control_input`）。
## 两者刻意分开 —— N32 原文："`translate_dir`→八向；`control_input`→三轴混合，⛔ 不混进同一个"。
##
## ★ 优先级：`BURST/FORM > DASH > TURN > 形态切换 > 待机`。
##   DASH 在 TURN 之前 = **有平移输入时以平移为准**（边按 W 边打舵，播的是 `fly_f`）。
##
## `ACTION` = 正在播**战斗一次性动作**（`shoot` / `slash` / `shield` / `trans_*`，N49）。
## 与 BURST **同构**：`request_action(name)` 进、`finished()` 出、播完回待机。
##
## ★ 优先级**并列最高**（与 BURST / FORM 一起排在 DASH / TURN 之前）。
##   依据与 DASH 那次同源 —— **被打断的代价不对称**：
##   战斗动作是"玩家刚按了键"的即时反馈，被持续动作盖掉就**看不见反馈**（像是没响应）；
##   反过来，方向/姿态动作被战斗动作盖掉只损失零点几秒。
##
## `UNACTION` = **收枪**（N56，用户方案：「射击完，短时间内没有下一发射击 ⇒ 倒放收枪」）。
##
##      ACTION ──(播完 且 这段被声明为"可收枪")──► UNACTION ──(宿主报"窗口到了")──► 倒放
##                                                     │                              │
##                                                     │                              ▼
##                                                     └────────(倒放播完)──────► IDLE（播巡航归位段）
##
## 两个阶段：**滞留**（还举着枪、等窗口）→ **倒放**（枪口按原轨迹回摆 0.40 s）→ 回待机。
##
## ★ 优先级**最低的一档**（`tick()` 里排在 `ACTION` 之后）。理由同 N46「被打断的代价不对称」：
##   收枪被新射击盖掉只损失一段**可以重播**的收尾动画；
##   反过来 = 玩家按了键却看不到反馈 —— 那正是 N56 §1.5 实测的**既有缺陷**
##（`request_action()` 的"同段在播不重播"把**倒放**也认成"正在播"⇒ 倒放途中开火，
##  `speed` 恒 **−1.00**、"按了没反应"）。独立成态后这条自动修好：新射击直接接管。
##
## ★ **末尾追加**：`NONE/IDLE/BURST/FORM/DASH/TURN/ACTION` 的值一个都没动。
enum State { NONE, IDLE, BURST, FORM, DASH, TURN, ACTION, UNACTION }

## 形态。只影响"选哪一版待机 / 哪一版发射动作"。
enum Form { NORMAL, CRUISE }


# ============================================================ 常量

## 进入 BURST 后的**最短保护时间**（秒）：这段时间内不判"播完"。
##
## 防的是 `play()` 与 `finished()` 落在**同一帧**时，`is_playing()` 尚未翻真
## 就被判成"已结束"，于是发射动画**一帧都没播**就弹回待机 ——
## 现象是"全弹发射没有动作"，且完全不报错。
const MIN_BURST_HOLD := 0.05

## 混合时间：进发射要"咬"得干脆，回待机要软。
const BLEND_BURST_IN := 0.12
const BLEND_BURST_OUT := 0.18

## 形态切换时换待机动作的混合时间。
const BLEND_FORM := 0.18

## 进冲刺要"咬"得干脆（与 `BLEND_BURST_IN` 同档）：闪避是一下 commit，
## 动作若是软软地淡进来，冲刺的"弹开感"就没了。
## 出冲刺回待机复用 `BLEND_BURST_OUT`（软回），两个常数够用，不另开。
const BLEND_DASH_IN := 0.12

## 收枪倒放的**起手**混合时间（N56）。与 `BLEND_DASH_IN` 同档 ——
## 倒放是"枪口按原轨迹回摆"，起手要跟得上"停火"这个事件；
## 而**归位那一段**（倒放播完回待机）复用 `BLEND_BURST_OUT`（软回）。
const BLEND_STOW := 0.12

## `_history` 的条数上限（只留最近若干条，免得长局跑下来无限涨）。
const HISTORY_LIMIT := 16


# ============================================================ 状态

## 底层播放器。`state == NONE` 时可能为 `null`。
var anim: ModelAnimator

## 当前状态。
var state: State = State.NONE

## **当前生效**的形态（BURST 期间冻结，见约束③）。
var form: Form = Form.NORMAL

## **目标**形态。`set_form()` 只写这里，实际切换一律在 `tick()` 里做（约束④）。
var _want_form: Form = Form.NORMAL

## 状态机认定的当前动作名。与 `anim.current` 互为校验（见 `_check_desync()`）。
var _action := ""

## 待机期**状态机要求底层播放器在跑的那一段**（N56）。
##
## ## 为什么非有不可（这是 N56 顺手补掉的一个旧洞）
##
## `_action == ""` 有两种情况，两种都不是"没期望值"：
##   ① 「空待机 ⇒ 播**恒定静置段** `__rest__`」（N50，五台机体 / 老资产）；
##   ② 「巡航待机 ⇒ 播**巡航归位段** `__cruise_hold__`」（N56，柯西）。
## 这两种情况下状态机手里的动作名是空串（它们**不是动作**、不进 `actions`），
## 而 `_check_desync()` 原本在 `_action == ""` 时**直接早退**
## ⇒ **这两条路上的旁路播放完全不可观测**。
##
## ⚠️ 实测症状（N56 · S4）：`suite_model_fsm / 与 FlightBody 的集成` 里那条
## 「绕过状态机播别的动作 ⇒ desyncs 涨到 N（旁路可观测）」**变红** ——
## 因为那一刻机体已在巡航形态、走的是 ②，`_action == ""` ⇒ 早退 ⇒ `desyncs` 恒 0。
## 也就是说：**"换一段待机载体"这件事同时把一条观测通路关掉了**。
##
## ⇒ 把"要求底层在跑什么" 记下来，`_check_desync()` 拿它当期望值。
## 非待机态（BURST / FORM / DASH / TURN / ACTION / UNACTION）恒为空串，行为逐位不变。
var _idle_clip := ""

## 进入 BURST 后已经过的时间，用于 `MIN_BURST_HOLD`。
var _burst_hold := 0.0

## 进入 FORM（形态过渡动作）后已经过的时间。理由同 `MIN_BURST_HOLD`：
## 防 `play_once()` 与 `finished()` 落在同一帧，过渡动作**一帧都没播**就被判结束。
var _form_hold := 0.0

## **目标**冲刺方向名（`""` = 不在冲刺）。与 `_want_form` 逐字同构：
## `set_dash()` 只写这里，真正的切换一律在 `tick()` 里做（约束④）。
##
## 取值 = 八向之一：`f` / `fr` / `r` / `br` / `b` / `bl` / `l` / `fl`。
var _want_dash := ""

## 进入 DASH 后已经过的时间。理由同 `MIN_BURST_HOLD`：
## 防"`play()` 与冲刺窗口结束落在同一帧"⇒ 冲刺动作**一帧都没播**就弹回待机。
var _dash_hold := 0.0

## **目标**常态平飞方向名（`""` = 没有平移输入）。与 `_want_dash` 逐字同构（N49）。
##
## ## 为什么两者分开存、而不是合并成一个"当前方向"
##
## 它们是**两个独立的输入事实**，同一帧可以同时成立：玩家按着 W 冲刺时，
## `_want_dash` 有值（冲刺方向）而 `_want_fly` 也有值（平飞方向），
## 而**该播哪一族是优先级问题**（冲刺优先），不是"谁覆盖谁"的问题。
## 合并存会丢掉低优先那个 —— 冲刺窗口一结束，`translate_dir` 还在，
## 却因为已被覆盖而读不回来，表现是"冲刺完那一下动画没了"。
var _want_fly := ""

## **目标**姿态微调轴名（`""` = 三轴都在死区里）。取值：`pitch_up` / `pitch_down` /
## `yaw_L` / `yaw_R` / `roll_L` / `roll_R`（N49）。与 `_want_fly` 同构、同一套理由。
##
## ⚠️ 它与 `_want_fly` **不是互斥的两选一**，而是两个独立事实：
##   玩家可以一边按 W 一边打舵。`tick()` 里 DASH 分支在前 ⇒ 有平移时用它。
var _want_turn := ""

## 进入 TURN 后已经过的时间。理由同 `MIN_BURST_HOLD`。
var _turn_hold := 0.0

## 进入 ACTION（战斗一次性动作）后已经过的时间。理由同 `MIN_BURST_HOLD`：
## 防"`play_once()` 与 `finished()` 落在同一帧"⇒ 动作**一帧都没播**就弹回待机。
var _act_hold := 0.0

# ---- N56 收枪（UNACTION）----

## 收枪要倒放的那段动作名（`""` = 这段动作**不收枪**）。
##
## ★ 由**调用方**在 `request_action()` 时声明，不在这里按名字猜 ——
## "这一下是不是火器"是**玩法层**的事实（宿主/武器代码知道），
## 状态机里写死 `"shoot"` 就等于把玩法判断埋进表现层，将来加一把步枪要改三个文件。
var _stow_action := ""

## 收枪阶段：`0` = **滞留**（还举着枪、等窗口）；`1` = **倒放中**。
var _stow_stage := 0

## 进入 UNACTION 后已经过的时间（用法同 `MIN_BURST_HOLD`；换阶段时归零）。
var _stow_hold := 0.0

## 宿主**每帧**报的事实：现在**允许**收枪了吗。
##
## = 「步枪冷却已归零 且 又等了 `FlightBody.STOW_DELAY`」—— 判据全在宿主侧
##（同 `set_form()` / `set_dash()` / `set_fly_dir()` 的"只报事实"契约，约束④）。
## 状态机只消费它，不自己拍秒数："能不能再开一枪"这个真实约束只有一个真源。
var _can_stow := false

## 真的开始倒放的次数（观测计数器，只读）。滞留期被打断不计。
var stows := 0

# ---- 观测计数器：只读、不影响行为。给测试与 HUD 用。----

## 状态迁移次数（含初始化那一次）。
var transitions := 0
## "想要的动作拿不到、退而求其次"的次数。**巡航形态进待机时必然 +1**，见下方说明。
var fallbacks := 0
## 状态机认定的动作与底层播放器实际动作**对不上**的次数。
## 非零 ⇒ 有人绕过状态机直接调了 `ModelAnimator`（旁路播放）。
var desyncs := 0

var _history: Array[String] = []


# ============================================================ 构造

## 唯一的构造入口。**永不返回 `null`** —— 没动画的模型拿到的是一个 `state == NONE` 的哑机。
##
## `a` = 已经 `setup()` 过的 `ModelAnimator`（可为 `null`）；
## `cruise` = 初始形态。
static func create(a: ModelAnimator, cruise: bool = false) -> ModelAnimFSM:
	var fsm := ModelAnimFSM.new()
	fsm.anim = a
	if cruise:
		fsm.form = Form.CRUISE
	fsm._want_form = fsm.form
	if a == null or not a.ready:
		# 老资产：没有 AnimationPlayer。**不是错误**，静默降级。
		fsm.state = State.NONE
		return fsm
	fsm.state = State.IDLE
	fsm._action = fsm.idle_action_for_form(fsm.form)
	if fsm._action != "":
		a.play_loop(fsm._action, 0.0, true)
		fsm._note("init:" + fsm._action)
	else:
		# ★★ N50：这个模型**没有待机动作**（五台机体按用户要求不播飞行待机）。
		#
		# 旧行为是"静静停着"（`init:none`）—— 姿态上没错，但**播放器停着**
		# ⇒ 之后每一次 `play(动作, blend)` 都没有"前一段"可混 ⇒ 全是零混合硬切。
		# 改成先起播"恒定静置段"：姿态同样是 rest，但播放器一直在跑。
		fsm._begin_rest(0.0)
		fsm._note("init:rest")
	return fsm


# ============================================================ 查询

## 这个模型有没有动画能力。
func is_enabled() -> bool:
	return state != State.NONE


## 当前是否锁在发射动作里（此期间形态切换被挂起）。
func is_locked() -> bool:
	return state == State.BURST


func state_name() -> String:
	match state:
		State.NONE:
			return "none"
		State.IDLE:
			return "idle"
		State.BURST:
			return "burst"
		State.FORM:
			return "form"
		State.DASH:
			return "dash"
		State.TURN:
			return "turn"
		State.ACTION:
			return "action"
		State.UNACTION:
			return "unaction"
	return "?"


func form_name() -> String:
	return "cruise" if form == Form.CRUISE else "normal"


## 目标形态名（发射途中可能与 `form_name()` 不同 —— 那正是"挂起中"）。 
func want_form_name() -> String:
	return "cruise" if _want_form == Form.CRUISE else "normal"


func current_action() -> String:
	return _action


## 当前动作的播放进度 0..1。**这是"动作真的在动"的可断言证据**（N28 的核心）。
func progress() -> float:
	if anim == null or not anim.ready:
		return 0.0
	return anim.progress()


## 最近的状态迁移标签（按时间升序）。返回副本，外部改不到内部。
func history() -> Array[String]:
	return _history.duplicate()


## 归零三个观测计数器（`tick()` 前的取基线用）。
func reset_stats() -> void:
	transitions = 0
	fallbacks = 0
	desyncs = 0
	_history.clear()


# ============================================================ 动作选择（纯查询，无副作用）

## 某个形态下该播哪一版全弹发射。返回 `""` = 这个模型没有发射动作。
##
## ⚠️ 本函数**纯查询、无副作用** —— 探针/测试可以随便调，不会污染 `fallbacks`。
## 计数发生在 `request_burst()` 里（那里才知道"这是真的在发射"）。
func burst_action_for_form(f: Form) -> String:
	if anim == null or not anim.ready:
		return ""
	if f == Form.CRUISE and anim.has(anim.burst_cruise_action):
		return anim.burst_cruise_action
	if anim.has(anim.burst_action):
		return anim.burst_action
	return ""


## 某个形态下该播哪个待机循环。
##
## ## N42·二十一 方案 B（2026-09-27）：巡航形态不再共用 `fly`
##
## 此前两形态共用同一个 `idle_action`（源码原话「本次交付里只有这一个循环动作」），
## 而 `fly` 的姿态是**飞行姿势** —— 与用户给的参照 `柯西巡航2.0`
##（rest 身体 + 翼展）**差 0.7193 m**（202/203 件超差）。本轮补上了巡航专用待机
## `cruise_idle`，这里真的分形态。
##
## 拿不到 `idle_cruise_action`（其余五台机体 / 18 个老资产）⇒ **逐位退回旧行为**。
func idle_action_for_form(f: Form) -> String:
	if anim == null or not anim.ready:
		return ""
	if f == Form.CRUISE and anim.has(anim.idle_cruise_action):
		return anim.idle_cruise_action
	if anim.has(anim.idle_action):
		return anim.idle_action
	return ""


## 某个方向名该播哪一段冲刺动作。返回 `""` = 这个模型没有这一段。
##
## ⚠️ **纯查询、无副作用** —— 探针/测试可以随便调（同 `burst_action_for_form()`）。
func dash_action_for(dir_name: String) -> String:
	if anim == null or not anim.ready or dir_name == "":
		return ""
	var cruise_name := "dash_cruise_" + dir_name
	if _want_form == Form.CRUISE and anim.has(cruise_name): return cruise_name
	var nm := "dash_" + dir_name
	return nm if anim.has(nm) else ""


## 某个方向名该播哪一段**常态平飞**动作（`fly_<dir>`，N49）。返回 `""` = 没有这一段。
##
## 与 `dash_action_for()` 是**同一个函数的两个前缀** —— 共用八向表、共用改向逻辑，
## 只有前缀不同（见 `State.DASH` 的说明）。⚠️ 纯查询、无副作用。
func fly_action_for(dir_name: String) -> String:
	if anim == null or not anim.ready or dir_name == "":
		return ""
	var nm := "fly_" + dir_name
	return nm if anim.has(nm) else ""


## 某个姿态轴名该播哪一段微调动作（`turn_<轴>`，N49）。返回 `""` = 没有这一段。
##
## 轴名取值：`pitch_up` / `pitch_down` / `yaw_L` / `yaw_R` / `roll_L` / `roll_R`。
## 与 `dash_action_for()` / `fly_action_for()` 同构，第三张前缀。⚠️ 纯查询、无副作用。
func turn_action_for(axis_name: String) -> String:
	if anim == null or not anim.ready or axis_name == "":
		return ""
	var nm := "turn_" + axis_name
	return nm if anim.has(nm) else ""


## 冲刺方向请求（`""` = 结束冲刺）。由宿主**每帧**写目标值。
##
## ## 为什么是"写目标 + `tick()` 兑现"，而不是直接播
##
## 与 `set_form()` 逐字同构（约束④：状态推进只有一个入口）。三个好处：
##   ① 测试**只驱动 `tick()`** 就能复现全部行为，不必去戳播放器；
##   ② 优先级天然由 `tick()` 的**分支顺序**决定（BURST / FORM 都排在 DASH 之前）；
##   ③ 宿主不必知道"此刻能不能切" —— 它只负责报当前事实。
##
## ⚠️ 判据用 `_want_dash` 而不是直接比 `_action`：这样"中途改向"（`want != _action`）
## 与"窗口结束"（`want == ""`）是两条不同的路，各自有各自的收尾。
func set_dash(dir_name: String) -> void:
	_want_dash = dir_name


## 常态平飞方向请求（`""` = 没有平移输入）。由宿主**每帧**写目标值（N49）。
##
## 与 `set_dash()` 逐字同构：只写目标、切不切由 `tick()` 定。
## 优先级低于 `set_dash()` —— 冲刺窗口里即使有平移输入也播 `dash_*`。
func set_fly_dir(dir_name: String) -> void:
	_want_fly = dir_name


## 姿态微调请求（`""` = 三轴都在死区）。由宿主**每帧**写目标值（N49）。
##
## 与 `set_dash()` / `set_fly_dir()` 逐字同构：只写目标、切不切由 `tick()` 定。
## 优先级低于 `set_dash()`（有平移输入时以平移为准，见 `State.TURN`）。
func set_turn(axis_name: String) -> void:
	_want_turn = axis_name


## 当前**生效**的冲刺方向名（`""` = 不在冲刺）。给 HUD / 测试读。
##
## ⚠️ 与 `_want_dash` 的区别正是"挂起中"：窗口已结束但状态机还没 `tick()` 到那一步时，
## 这里已经是 `""`、而目标值可能还在。读**生效值**才是对的。
func dash_dir() -> String:
	return _want_dash if state == State.DASH else ""


# ============================================================ 驱动

## 形态切换请求。**不立刻切动作**，只改目标形态（约束④）。
## BURST 期间调用 = 挂起，等发射结束生效（约束③）。
func set_form(cruise: bool) -> void:
	var f: Form = Form.NORMAL
	if cruise:
		f = Form.CRUISE
	if f == _want_form:
		return
	_want_form = f
	if state == State.NONE:
		# 哑机也要跟上形态，免得 HUD 读到过期形态。
		form = f


## 请求播一次全弹发射（由 `PlayerController.fire_full_salvo()` 那一帧喊）。
## 返回 `true` = 真的切进 BURST 了。
##
## **可重入**：冷却结束后再打一轮，动画从头放（`restart = true`，见约束②）；
## 但**同一瞬间被连点**会忽略第二次 —— 否则动作被反复怼回第 0 帧。
func request_burst() -> bool:
	if state == State.NONE:
		return false

	var want := anim.burst_action
	if _want_form == Form.CRUISE:
		want = anim.burst_cruise_action
	var got := burst_action_for_form(_want_form)
	if got == "":
		# 有播放器但一个发射动作都没有。静静不播，不刷日志。
		return false
	if got != want:
		# 巡航形态没有巡航版发射动作，退回常态版 —— 会闪一次形态跳变，记一笔。
		fallbacks += 1
	if state == State.BURST and got == _action and _burst_hold < MIN_BURST_HOLD:
		# 同一瞬间被重复触发（连点 / 左右键同按）。不重播。
		return true

	_action = got
	state = State.BURST
	_burst_hold = 0.0
	anim.play_once(got, BLEND_BURST_IN, true)
	_note("burst:" + got)
	return true


## 请求播一次**战斗动作**（`shoot` / `slash` / `shield` / `trans_*`）。返回 `true` = 接管了（N49）。
##
## 由 `FlightBody.play_model_action()` 转发 —— 那条路此前是**旁路**（直调播放器、绕过状态机、
## 于是每帧被 `_check_desync()` 记一笔 `desyncs`）。现在收到状态机里统一管。
##
## ## ⚠️ 与 `request_burst()` 有一处**故意不同**：同一段正在播时**不重播**
##
## 全弹发射有 20 s 冷却，重播是对的（冷却结束后再打一轮，动画当然从头放）。
## 而步枪 / 军刀 / 举盾是**高频输入** —— 每次输入都重播的话，播放头会被反复按回第 0 帧，
## 屏幕上"手一直在抖"，而且完全不像在射击。
##
## ★★ N57 实测**更正**：本条注释原先写"柯西的 `rifle_interval` 是 0.78 s，
##   **比动作本身还短**" —— **方向写反了**。实测（`_relay/n56_fire_trace.log`）：
##   柯西 `rifle_interval` = **0.78 s**，而 `shoot` 段长 = **0.400 s**
##   ⇒ **动作比冷却短**（短的是动作，长的是冷却）。
##   ⚠️ 这正是"注释里的前提数字必须当断言核验"的原因：结论（不重播）是对的，
##     但支撑它的理由**假** —— 谁若照这条注释去"优化"（把不重播改成重播）就会撞上抖动。
##   两种时序下"不重播"都成立，这才是它真正的理由：
##     · 冷却 **<** 动作长（输入比动作密）：播完之前来的请求被忽略 ⇒ 动作完整播一遍，防抖 ✓
##     · 冷却 **>** 动作长（柯西实况 0.78 > 0.40）：动作早已播完、状态回 IDLE ⇒ 下一发**自然重播** ✓
##
## 所以：同一段正在播就忽略这次请求、让它播完（`finished()` 会把状态收回 IDLE，
## 下次输入自然重播）。
##
## ## `can_stow`（N56）
##
## 这一段播完后**允不允许收枪**（倒放 ＋ 归位）。默认 `false` ⇒ 只有**显式声明**的
## 调用点（步枪的 `_shoot_rifle_now()`）会进收枪流程，其余战斗动作行为逐位不变。
##
## ⚠️ 倒放途中（`state == UNACTION`）再调本函数**会直接接管**（走下面这条正常路径）——
## 这正是修掉 N56 §1.5 那个"倒放期间开火按了没反应"的地方：因为收枪是独立态、
## 优先级低于 `ACTION`，所以新射击天然抢断，不需要任何特例分支。
func request_action(name: String, can_stow := false) -> bool:
	if state == State.NONE:
		return false
	if name == "" or anim == null or not anim.has(name):
		return false
	if state == State.ACTION and _action == name:
		return true
	_action = name
	_stow_action = name if can_stow else ""
	state = State.ACTION
	_act_hold = 0.0
	anim.play_once(name, BLEND_BURST_IN, true)
	_note("action:" + name)
	return true


## 宿主**每帧**报事实：现在允许收枪了吗（N56）。见 `_can_stow` 的说明。
##
## 与 `set_form()` / `set_dash()` 逐字同构 —— 只写目标，真正的推进在 `tick()` 里。
func set_can_stow(ok: bool) -> void:
	_can_stow = ok


## 收枪阶段：`-1` = 不在收枪；`0` = 滞留（还举着枪）；`1` = 倒放中。给探针 / 测试读。
func stow_stage() -> int:
	return _stow_stage if state == State.UNACTION else -1


## 每帧推一次。**状态推进的唯一入口**。
##
## `delta` 只喂给 `MIN_BURST_HOLD`，不参与别的判断 —— 完成与否一律以
## `anim.finished()`（即"播放头真的到了末尾"）为判据，**不自己计时**，
## 免得"动作长度改了、状态机还在按老时长算"。
func tick(delta: float) -> void:
	if state == State.NONE:
		return

	# 观测优先：先看底层播放器是不是被人插了一手（旁路播放）。
	# ⚠️ 放在分支**之前**，这样 IDLE 与 BURST 两条路都会被检到 ——
	# 放在 IDLE 末尾的话，"发射途中被旁路换掉动作"就永远测不出来。
	_check_desync()

	if state == State.BURST:
		_burst_hold += delta
		if _burst_hold < MIN_BURST_HOLD:
			return
		if anim == null or not anim.finished():
			return
		# 发射结束。发射途中挂起的形态切换**现在**生效（约束③）。
		form = _want_form
		_enter_idle(BLEND_BURST_OUT)
		return

	# ---- ACTION（战斗一次性动作，N49）----
	# ★ 与 BURST 并列最高：排在 DASH / TURN 之前。理由见 `State.ACTION` 的说明
	#  （战斗动作被持续动作盖掉 = 玩家按了键却看不到反馈）。
	if state == State.ACTION:
		_act_hold += delta
		if _act_hold < MIN_BURST_HOLD:
			return
		if anim == null or not anim.finished():
			return
		# 播完 ⇒ 回待机（发射途中挂起的形态切换同样在这一刻落地，与 BURST 一致）。
		form = _want_form
		# ★ N56：这一段被声明为"可收枪"（步枪）、且这个模型/形态收得了 ⇒ 先进 UNACTION。
		#
		# ⚠️ 此刻**什么都不播**是**故意的**：`AnimationPlayer` 停播不还原骨姿态（T30）
		#   ⇒ "什么都不做"恰好就是"停在射击末帧 = 枪还举着"，正是玩家说的
		#   「射击完，短时间内没有下一发射击」的那个中间状态。
		if _stow_eligible():
			# The last frame may still report playing until the next mixer tick.
			# Pause explicitly to hold the evaluated shot pose without resetting it.
			anim.player.pause()
			_stow_stage = 0
			_stow_hold = 0.0
			state = State.UNACTION
			_note("stow:hold")
			return
		_enter_idle(BLEND_BURST_OUT)
		return

	# ---- UNACTION（收枪，N56）----
	#
	# ★ 排在 `ACTION` **之后** = 全文件优先级最低：新射击天然抢断（上面的 ACTION 分支
	#   先判、先 `return`）。理由见 `State.UNACTION` 的说明。
	#   ⚠️ 形态切换在这一态**不播过渡动作**（`form = _want_form` 静默同步，同 DASH 分支）：
	#     形状在这段时间里是被收枪逻辑主动改变的，插一条 `form_on/off` 只会两条都播不完。
	if state == State.UNACTION:
		form = _want_form
		_stow_hold += delta
		if _stow_stage == 0:
			# ---- 滞留：还举着枪，等宿主报"窗口到了" ----
			if _want_form != Form.CRUISE:
				# 玩家把巡航关了（或本来就不是巡航）⇒ 走旧路径收尾
				#（播目标形态的待机，`fly` 有自己的臂 / 腿轨 ⇒ 手会被拉回常态位）。
				_enter_idle(BLEND_BURST_OUT)
				return
			if not _can_stow:
				return
			# ★ 开始倒放：枪口按原轨迹回摆 0.40 s。
			#   拿不到（这个模型没这段 / 没播放器）⇒ 直接回待机 = **今天的行为**，
			#   "退化了但不会出错"（同 `_begin_rest()` 的兜底哲学）。
			if anim == null or not anim.play_backwards_once(_stow_action, BLEND_STOW):
				_enter_idle(BLEND_BURST_OUT)
				return
			_stow_stage = 1
			_stow_hold = 0.0
			stows += 1
			_note("stow:back")
			return
		# ---- 倒放中：等它自然到 0 ----
		if _stow_hold < MIN_BURST_HOLD:
			return
		if anim == null or not anim.finished():
			return
		# 倒放到底 ⇒ 回**巡航归位段**（臂 / 腿 / 躯干在这一刻才真的放下）。
		# ⚠️ 倒放**本身不构成归位** —— `shoot` 首帧 ≡ 末帧（N56 §1.5 实测逐位 0.000000），
		#   倒放到底仍停在举枪位；归位是紧接着这一步做的。
		_enter_idle(BLEND_BURST_OUT)
		return

	# ---- FORM（形态过渡动作播放中）----
	if state == State.FORM:
		_form_hold += delta
		if _form_hold < MIN_BURST_HOLD:
			return
		if anim == null or not anim.finished():
			return
		# 过渡动作播完 ⇒ 落到目标形态的待机。
		# 两条过渡动作的末帧都 = 目标待机的**首帧**（逐位相同）⇒ 这一步是**无缝**的，不是跳变。
		form = _want_form
		_enter_idle(BLEND_BURST_OUT)
		return

	# ---- DASH（冲刺八向，N46）----
	#
	# ★ 优先级：**低于 BURST / FORM**（上面两个分支先判、先 `return`）。
	#   理由是"被打断的代价不对称"：
	#     全弹发射与形态过渡是**短而必须完整**的段落 —— 发射还被 `finished()` 收尾，
	#     中途被盖住就**永远收不了尾**（`_burst_hold` 会一直涨）；形态过渡被盖住会闪。
	#     反过来，冲刺被它们盖掉只是少播零点几秒的机动姿势，窗口一到自然回来。
	#   ⇒ 冲刺可以中途起、中途停、也可以被发射抢走，**不需要额外的锁**。
	if state == State.DASH:
		# ★★ N46 修复（用户实测：「柯西转身结束之后背后飞翼会反复抽搐一下」）——
		#   冲刺期间让 `form` **静默跟上** `_want_form`，**不播**过渡动作。
		#
		# ## 抽搐是怎么来的（A/B 净效应隔离实测，`tools/_n46_xi_twitch.tscn`）
		#
		# 冲刺窗口里，`_tick_cruise_morph()` 会把形态**压回收起**（0.15 s 快收）
		# ⇒ 宿主每帧喂进来的 `set_form(cruise_morph >= 0.5)` 翻成 `false`。
		# 而本状态机把这次翻转**压着不办**（DASH 优先于形态切换，那是为了让 0.45 s 的
		# 冲刺不被 0.43 s 的过渡拦腰截断）—— 到这里都对。
		#
		# 错在**窗口结束那一帧**：`want` 已经回到常态，于是它会去播 `form_off`
		#（巡航→常态，0.4333 s）。可**同一时刻**"放翼"已经在爬升了
		#（`_dash_spin_t` 归零 ⇒ morph 从 0 涨向 1）⇒ 爬到一半越过 0.5，
		# `_want_form` 又翻回 `cruise` ⇒ `form_off` 一播完，下一帧立刻又要 `form_on`。
		#
		# 屏幕上就是**一对方向相反的过渡动作首尾相接** = 飞翼来回抽一下。
		# 实测迁移数：接线关（N46 之前）3 次，接线开 5 次 —— 多出的正是这一对。
		#
		# ## 为什么"静默同步"是对的，而不是"把过渡也压着"
		#
		# 形态在这 0.45 s 里**真的**被压回了常态（那是 `DASH_SPIN_STOW_SECONDS` 0.15 s
		# 的快速收翼，本来就不是走过渡动作表达的）⇒ `form` 跟着走才是**如实**的。
		# 压着不办，就等于让状态机记着一个它自己都知道已经过期的形态。
		#
		# ⚠️ 代价（已知、可接受）：冲刺这 0.45 s 里玩家若真的按变形键，过渡动作会被吞掉
		#   （静默切换形态）。比"飞翼抽搐"轻得多，且窗口只有 0.45 s。
		form = _want_form
		_dash_hold += delta
		if _dash_hold < MIN_BURST_HOLD:
			return
		# ★ N49：**两族一个态**。先冲刺族、再常态平飞族 —— 顺序即优先级
		#   （冲刺是"这一次 commit"，平飞是持续状态），与 IDLE 入口那两段判据同一顺序。
		var want := dash_action_for(_want_dash)
		var tag := "dash:"
		if want == "":
			want = fly_action_for(_want_fly)
			tag = "fly:"
		if want == "":
			# 两族都没得播（冲刺窗口结束**且**当前没有平移输入，或这个模型没有这一段）⇒ 回待机。
			_enter_idle(BLEND_BURST_OUT)
			return
		if want != _action:
			# 中途改向（含"冲刺 → 平飞"的跨界）⇒ 叠到新的那一段上。
			# ⚠️ `restart = true`：换段必须真的从头播，否则会接在上一段的残留进度上。
			_action = want
			anim.play_loop(want, BLEND_DASH_IN, true)
			_note(tag + want)
		return

	# ---- TURN（姿态微调，N49）----
	#
	# ★ 排在 DASH **之后** = 有平移输入时以平移为准：
	#   平飞八向（`fly_*`）是"往哪飞"的整机姿态，姿态微调是"手上在微调哪根舵"，
	#   两者同时成立时**只播一个**，取平移那条（它更明确、且不会因摇杆残余一直被抢占）。
	#   ⛔ 别把两边"混"进一个动作 —— N32 明文规定这两套载体不许混。
	if state == State.TURN:
		form = _want_form
		_turn_hold += delta
		if _turn_hold < MIN_BURST_HOLD:
			return
		var want := turn_action_for(_want_turn)
		if want == "":
			# 打舵回中（宿主清空轴名），或这个模型没有这一段 ⇒ 回待机。
			_enter_idle(BLEND_BURST_OUT)
			return
		if want != _action:
			_action = want
			anim.play_loop(want, BLEND_DASH_IN, true)
			_note("turn:" + want)
		return

	# ---- IDLE ----
	# 冲刺**优先于开始形态切换**：`form_on` / `form_off` 是 0.43 s 的一次性动作、
	# 冲刺窗口 0.45 s，让形态过渡插在冲刺中间会两条都播不完。
	# 形态请求留在 `_want_form` 里不丢 —— 冲刺结束回 `_enter_idle()` 后，
	# 下一个 `tick()` 立刻由下面的分支兑现。
	if _want_dash != "":
		var da := dash_action_for(_want_dash)
		if da != "":
			_action = da
			state = State.DASH
			_dash_hold = 0.0
			anim.play_loop(da, BLEND_DASH_IN, true)
			_note("dash:" + da)
			return
	# ★ N49：常态平飞八向（`fly_<dir>`）。排在冲刺之后 = **冲刺优先**；
	#   排在形态切换之前 = 与冲刺同级（理由同上面那段注释：0.43 s 的过渡
	#   插在持续的方向动作里会两条都播不完整）。冲刺时这条**走不到**，
	#   因为上面的分支已经 `return` 了。
	if _want_fly != "":
		var fa := fly_action_for(_want_fly)
		if fa != "":
			_action = fa
			state = State.DASH
			_dash_hold = 0.0
			anim.play_loop(fa, BLEND_DASH_IN, true)
			_note("fly:" + fa)
			return
	# ★ N49：姿态微调（`turn_<轴>`）。排在平飞**之后** —— 顺序即优先级（见 `State.TURN`）。
	if _want_turn != "":
		var ta := turn_action_for(_want_turn)
		if ta != "":
			_action = ta
			state = State.TURN
			_turn_hold = 0.0
			anim.play_loop(ta, BLEND_DASH_IN, true)
			_note("turn:" + ta)
			return
	if form != _want_form:
		if _begin_form_change():
			return
		form = _want_form
		_enter_idle(BLEND_FORM)


## 复位到状态、回静置。
##
## ⚠️ N50 起**不再** `anim.stop()`：停播会让播放器**没有"前一段"**，
## 下一次 `play(动作, blend)` 又变回零混合硬切。改成回静置段 ——
## 姿态同样是 rest，但播放器一直在跑（建不出静置段时才真停播，见 `_begin_rest()`）。
func stop() -> void:
	if anim != null and anim.ready:
		_begin_rest(0.0)
	_action = ""
	_burst_hold = 0.0
	_form_hold = 0.0
	# 冲刺也一并清：宿主的"每帧报方向"在重建视觉/释放模型那条路上会断供，
	# 留着旧方向的话，下次 `tick()` 会凭空播回一段冲刺。
	_want_dash = ""
	_dash_hold = 0.0
	# 平飞方向同理（N49）：宿主的"每帧报方向"在重建视觉那条路上会断供。
	_want_fly = ""
	_want_turn = ""
	_turn_hold = 0.0
	_act_hold = 0.0
	# 收枪状态一并清（N56）：留着 `_stow_stage == 1` 的话，下一次进 UNACTION
	# 会跳过滞留直接判"倒放播完"，表现是"收枪一闪而过"且不报错。
	_stow_action = ""
	_stow_stage = 0
	_stow_hold = 0.0
	if state != State.NONE:
		state = State.IDLE


# ============================================================ 内部

## 形态切换时若有**专用过渡动作**就先播它，播完由 `tick()` 收尾。
## 返回 `true` = 过渡已接管（调用方**不要**再自己切待机）。
##
## ## 两个方向各有一条动作（N42·二十二 补齐反方向）
##
## | 方向 | 动作 | 首帧 | 末帧 |
## |---|---|---|---|
## | 常态 → 巡航 | `form_on`  | 常态（= `fly` 首帧） | 巡航待机首帧 |
## | 巡航 → 常态 | `form_off` | 巡航待机首帧 | `fly` 首帧 |
##
## 两条都是"首帧 = 上一段的姿态、末帧 = 下一段的姿态" ⇒ **两端零接缝**。
##
## ## 为什么反方向非有不可
##
## 用户实测：「**巡航模式切换回正常飞行状态的动画有点生硬了**」。
## 逐帧轨迹（`_relay/log_n42_21_trace.txt`）显示旧行为的回程 =
## **先干等 0.23 s 画面完全不动** ＋ **0.18 s 交叉淡入硬切**，而去程有 0.4333 s 的曲线。
##
## ## 为什么只认这两个方向、不认"BURST 途中"
##
## `tick()` 只在 `IDLE` 态调本函数（`BURST` 有自己的分支）⇒ 发射途中形态切换天然被挂起
##（约束③），这里不必再判一次。
##
## 拿不到对应动作的机体（其余五台 / 18 个老资产）在第一道判据就返回 `false`
## ⇒ 走老路径，行为逐位不变。空串也天然安全（`has("")` 恒 `false`）。
func _begin_form_change() -> bool:
	if anim == null or not anim.ready:
		return false
	# ⚠️ 判"现在从哪来"必须用**当前生效**的 `form`（不是 `_want_form`）：
	#    `_want_form` 已经指向目标了，用它选动作会两个方向都选成 `form_on`。
	var a := ""
	if _want_form == Form.CRUISE:
		a = anim.form_on_action
	elif form == Form.CRUISE:
		a = anim.form_off_action
	if a == "" or not anim.has(a):
		return false
	_action = a
	state = State.FORM
	_form_hold = 0.0
	anim.play_once(a, BLEND_FORM, true)
	_note(a)
	return true


## 回"静置"：**优先**播恒定静置段（于是收尾真的会混合），兜底才硬切。
##
## ## 为什么要有兜底那条路
##
## 静置段是**程序生成**的，需要两个条件同时成立：
##   ① 模型有 `Skeleton3D`；② 能从既有动画里抄到一条轨道的路径前缀。
## 任一不满足就建不出来。那时**不能硬播一个空动作** —— 必须退回
## `reset_to_rest()`：它至少保证**姿态是对的**（只是没有混合）。
##
## ⇒ 这是一个"退化了但不会出错"的设计：**建不出来 = 回到 N49 的行为**，
##   而不是"什么都不做、骨停在末帧"。
func _begin_rest(blend: float) -> void:
	if anim == null:
		return
	if anim.ready and anim.has_rest_clip():
		anim.hold_rest(blend)
		# ★ N56：记下"要求底层在跑什么"，好让 `_check_desync()` 在 `_action == ""`
		#   的待机期仍能发现旁路播放（见 `_idle_clip` 的长说明）。
		_idle_clip = str(ModelAnimator.REST_CLIP)
	else:
		anim.reset_to_rest()
		# 建不出静置段 ⇒ 播放器是**停着的**，没有"要求的动作"可言。
		_idle_clip = ""


## 回"巡航位"：播**巡航归位段**（N56）。见 `ModelAnimator.CRUISE_HOLD_CLIP`。
##
## 兜底与 `_begin_rest()` 同哲学：建不出来就退回静置段 ——
## 姿态至少是对的（柯西的 rest 今天恰好等于巡航姿态），只是丢掉 `cruise_idle` 的观感。
func _begin_cruise_hold(blend: float) -> void:
	if anim != null and anim.ready and anim.has_cruise_hold():
		anim.hold_cruise(blend)
		_idle_clip = str(ModelAnimator.CRUISE_HOLD_CLIP)
	else:
		_begin_rest(blend)


## 这一段战斗动作播完后，**该不该**进收枪流程（N56）。
##
## 三个条件缺一不可：
##   ① 调用方声明过"这段可收枪"（`request_action(..., can_stow = true)`，只有步枪那条路）；
##   ② 目标形态是**巡航**（常态没有"举枪"这个问题，收了反而多余）；
##   ③ 这个模型**建得出巡航归位段** —— 否则倒放到底仍举着枪（N56 §1.5 实测
##      48.46% / 95.28% / 25.92%），白播一段 0.40 s 的动画，还不如直接走旧路径。
func _stow_eligible() -> bool:
	if anim == null or not anim.ready:
		return false
	if _want_form != Form.CRUISE:
		return false
	if _stow_action == "" or not anim.has(_stow_action):
		return false
	return anim.has_cruise_hold()


## 回待机。**同一个待机动作就不重播**（否则每帧进度归零，等于不动）。
func _enter_idle(blend: float) -> void:
	var a := idle_action_for_form(form)
	var prev := _action
	state = State.IDLE
	# ★ N56：离开"待机载体"这条路之前先清掉旧值 —— 下面每个出口都会按自己播的东西
	#   重新写它（真切动作的出口保持空串 ⇒ `_check_desync()` 走 `_action`）。
	_idle_clip = ""
	# ★★ N56：巡航形态 + 这个模型有「巡航归位段」⇒ 用它收尾，**不播** `cruise_idle`。
	#
	# ## 为什么不能继续播 `cruise_idle`
	#
	# `cruise_idle` 在引擎里只剩 **19 条旋转轨** —— 臂 / 腿 / 躯干（`UpperArm.*` /
	# `LowerArm.*` / `Hand.*` / `Thigh.*` / `Shin.*` / `Foot.*` / `Chest` / `Spine` /
	# `Hips`）**一根都没有**，而 `AnimationPlayer` 的规则是"**没有轨道的属性保持当前值**"
	# ⇒ 播它**不承担归位**：按 W 时被带跑的臂 / 腿**永远放不回来**。
	# 实测（N56 §1.3）：松手 90 帧后 臂 48.46% / 枪 95.28% / 腿 25.92%，
	# 与"按住 W 期间"**一模一样** —— 这就是玩家说的「按 WASD 就会举枪」。
	#
	# 归位段 = `cruise_idle` 自己的轨（保住巡航待机的观感：翼 / 装甲）
	# ＋ `form_on` 末帧补上的臂 / 腿 / 躯干（与 `FormWeld` 的祖先基准**同源**）
	# ⇒ 实测把三项**全部拉到 0.00%**。详见 `ModelAnimator.CRUISE_HOLD_CLIP`。
	#
	# ⚠️ 触发条件是"**这个模型真的建得出归位段**"（`has_cruise_hold()`），
	#   ⛔ 不是"所有机体"：其余五台机体 / 18 个老资产 `idle_cruise_action == ""`
	#   ⇒ 建不出来 ⇒ 逐位走下面的旧路径（N49 的老资产约束）。
	if form == Form.CRUISE and a != "" and anim != null and anim.has_cruise_hold():
		_action = ""
		_begin_cruise_hold(blend)
		return
	if a == "":
		# 这个模型**没有待机动作**（五台机体按用户要求不播飞行待机 ——
		# `model_anim_idle == ""`）。
		#
		# ⚠️ 必须显式归位：`AnimationPlayer` 停播**不会**还原骨姿态
		#   （规则是"没有轨道的属性保持当前值"）⇒ 少了这一步，动作播完
		#   模型会**僵在末帧姿势**上，而且**不报任何错**。
		#
		# ★★ N50：归位改走 `_begin_rest()`（= 从当前姿态**混合**回 rest），
		#   不再直调 `reset_to_rest()`（= 瞬间硬切回 rest）。
		#
		#   实测（`tools/_n50_smoothness.gd`，逐帧全骨姿态活动量 A、J = A[i]-A[i-1]）：
		#   硬切那一帧全身要在一帧里转 **134° ~ 159°**，而柯西（有待机动作、
		#   播放器一直在跑）同类收尾只有 **≈ 0 ~ 5°** ⇒ 8.5 倍差距，
		#   正是用户说的"**每个动作过渡都有点生硬**"。
		_action = ""
		_begin_rest(blend)
		return
	if form == Form.CRUISE and a == anim.idle_action:
		# 巡航形态拿不到专用待机 ⇒ 退回常态待机（`fly`），模型会回到常态姿态。
		# **柯西自 N42·二十一 起不再走这里**（已有 `cruise_idle`）；
		# 其余机体/老资产仍会命中 —— 那是"本来就没有巡航待机"的如实反映。
		fallbacks += 1
	_action = a
	if a == prev:
		anim.play_loop(a, blend)
	else:
		anim.play_loop(a, blend, true)
		_note("idle:" + a)


## 状态机认定的动作 vs 底层播放器实际动作。对不上 ⇒ 有人绕过状态机播了东西。
##
## ⚠️ `_action == ""` **不再等于"没有期望值"**（N56 修正）：待机期底层跑的是恒定段
## （`__rest__` / `__cruise_hold__`），要求是什么记在 `_idle_clip` 里
## ⇒ 这两条路上的旁路播放现在**可观测**（修前完全不可观测，见 `_idle_clip` 的长说明）。
##
## 两者都为空才是真的"没配到任何动作名"（动作名写错）—— 那时底层 `anim.current`
## 留着上一次的残留值，**不该算失同步**。
func _check_desync() -> void:
	if anim == null or not anim.ready:
		return
	var expected := _action if _action != "" else _idle_clip
	if expected == "":
		return
	var live := anim.current
	if live != "" and live != expected:
		desyncs += 1
		_action = live
		# 已经"改认"成旁路播的那一段了 ⇒ 待机载体的期望值作废，免得下一帧再记一次。
		_idle_clip = ""


func _note(tag: String) -> void:
	transitions += 1
	_history.append(tag)
	if _history.size() > HISTORY_LIMIT:
		_history.remove_at(0)

## A confirmed hit cancels only the old melee gesture; new firearm/shield actions remain free.
func interrupt_melee() -> void:
	if state==State.ACTION and (_action=="slash" or _action.begins_with("slash_")):
		_stow_action=""
		_act_hold=0.0
		if anim!=null: anim.release_saber()
		_enter_idle(0.12)
