class_name SuiteModelFsm
extends RefCounted
## 动作切换状态机的**门**（棒 12 测试官 · 2026-09-26）。
##
## ## 为什么要有这一套
##
## `suite_model_anim` 钉的是"**动作能播**"（名字对不对、锚点跟不跟）。
## 但"播完之后去哪、发射途中形态变了怎么办、冷却结束再打一轮会不会重播"
## 这些**切换语义**在那之前**没有任何自动判据** —— 而它们错起来是这样：
##
##   * 发射动画**一帧都没播**就弹回待机（`play()` 与 `finished()` 同帧）；
##   * 每帧重启 ⇒ 进度永远按在第 0 帧（"动作播了但看不出在动"）；
##   * 发射途中按变形键 ⇒ 动作被换成另一形态的版本，**闪一下错的姿势**；
##   * 巡航形态却播了常态版的发射动作 ⇒ 发射前跳变。
##
## 四种都**不报错、不复现、只能靠人眼在某局里撞见**。这一套把它们变成断言。
##
## ## 五段
##
##   ① **哑机**：没动画的模型拿到的是哑机 —— 一切方法安全、安静（老资产零影响）；
##   ② **状态转移**：IDLE ⇄ BURST 的进入 / 退出 / 回待机，以及形态选版本；
##   ③ **锁定与事件驱动**：发射途中挂起形态；连点不重播、冷却后必须重播；
##   ④ **冲刺八向**（N46）：进 / 出 / 中途改向 / 拿不到方向的退化 / 优先级；
##   ⑤ **与 FlightBody 的集成**：宿主接口、真在推进、旁路播放被记账。

const XI_DIR := "res://assets/models/xi/"
const FLY := "res://assets/models/xi_movie/xi_movie_rigged.scn"
const BURST := XI_DIR + "xi_burst.glb"
const BURST_CRUISE := XI_DIR + "xi_burst_cruise.glb"
## 冲刺八向只取四向做断言（前 / 右 / 左 / 后）。八向的**全体**逐个验是探针的活
##（`tools/_n45_dash8.tscn` + `_n45_dash_why.tscn`），这里钉的是**状态机语义**。
const DASH_F := XI_DIR + "anim/xi_dash_f.glb"
const DASH_R := XI_DIR + "anim/xi_dash_r.glb"
const DASH_L := XI_DIR + "anim/xi_dash_l.glb"
const DASH_B := XI_DIR + "anim/xi_dash_b.glb"
## ★ N56 收枪：要倒放的那一段（`shoot`）＋ 巡航归位段的两个**源**。
const SHOOT := XI_DIR + "anim/xi_shoot.glb"
const CRUISE_IDLE := XI_DIR + "anim/xi_cruise_idle.glb"
const FORM_ON := XI_DIR + "anim/xi_form_on.glb"

## `burst` / `burst_cruise` 都在 1.34 s 以内，2.5 s 足够跑完一整轮。
const SETTLE_TIMEOUT := 2.5


static func run(t: T, host: Node) -> void:
	t.suite("ModelFSM / 哑机（老资产零影响）")
	await _mute(t, host)
	t.suite("ModelFSM / 状态转移")
	await _transitions(t, host)
	t.suite("ModelFSM / 锁定与事件驱动")
	await _locking(t, host)
	t.suite("ModelFSM / 冲刺八向")
	await _dash(t, host)
	t.suite("ModelFSM / 收枪（N56）")
	await _unaction(t, host)
	t.suite("ModelFSM / 与 FlightBody 的集成")
	await _integration(t, host)


# ============================================================ ① 哑机

## 没动画的模型 ⇒ 哑机。**每一个老机体都会走这条路**，所以判据是
## "安全 + 安静 + 形态仍然正确"，而不是"报个错"。
static func _mute(t: T, host: Node) -> void:
	var mute := ModelAnimFSM.create(null)
	t.ok(mute != null, "create(null) 不返回 null —— 宿主不必到处判空（防错设计）")
	t.eq(mute.state, ModelAnimFSM.State.NONE, "state == NONE（是降级，不是错误态）")
	t.not_ok(mute.is_enabled(), "is_enabled() == false")
	t.not_ok(mute.is_locked(), "哑机 is_locked() == false")
	t.not_ok(mute.request_burst(), "哑机 request_burst() 返回 false")
	t.eq(mute.current_action(), "", "哑机没有当前动作")
	t.eq(mute.progress(), 0.0, "哑机 progress() 恒 0")
	t.eq(mute.burst_action_for_form(ModelAnimFSM.Form.CRUISE), "",
		"哑机查不到发射动作（纯查询，安全）")
	mute.tick(0.016)
	t.eq(mute.state, ModelAnimFSM.State.NONE, "哑机 tick() 后仍在 NONE（不崩、不乱转）")
	mute.stop()
	t.eq(mute.state, ModelAnimFSM.State.NONE, "哑机 stop() 后仍在 NONE")
	# 形态仍要跟上 —— HUD / 变形动画都在读它，读到过期值会显示错形态。
	mute.set_form(true)
	t.eq(mute.form_name(), "cruise", "哑机也跟随形态（HUD 读到的不是过期值）")
	t.eq(mute.want_form_name(), "cruise", "哑机目标形态同步")

	# ---- 老机体走完整链路：真的套一个 Body 上去 ----
	# ★ 2026-09-28（N49）：样本从「古斯塔夫」换成「**阿利宙斯 · 巡航形态**」。
	#   古斯塔夫**已接线（27 段）**、主模型也换成了带骨架的 `gustav_fly.glb`
	#   ⇒ 拿它当"老机体"会**测错对象**（§8 R5 那条"加动作资产要同步测试"防的就是这个）。
	#   ★ **五台机体现已全部接线**，全工程唯一仍走老路径的是**阿利宙斯巡航形态**：
	#     交付侧没有巡航形态的绑定件 ⇒ `model_path` 仍是无骨架旧件、动作表为空。
	#   判据**逐字未变**，只换样本 ＋ 下面那道「样本确实是老资产」的前置。
	var oldp := SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
	t.eq(oldp.model_anim_files.size(), 0,
		"样本确实是老资产（前置：⛔ 它哪天接线了，就得换样本）")
	var body := FlightBody.new()
	body.profile = oldp
	body.use_placeholder = false
	host.add_child(body)
	await host.get_tree().physics_frame
	t.ok(body.model_fsm != null, "老机体身上 model_fsm 也不是 null（契约成立）")
	t.eq(body.model_fsm.state, ModelAnimFSM.State.NONE, "老机体的状态机是哑机")
	t.not_ok(body.play_full_burst(), "老机体 play_full_burst() 返回 false（静默降级）")
	t.eq(body.full_burst_action(), "", "老机体 full_burst_action() 为空串")
	body.free()


# ============================================================ ② 状态转移

static func _transitions(t: T, host: Node) -> void:
	var m: Dictionary = await _mount(host)
	var inst := m["inst"] as Node3D
	var anim := m["anim"] as ModelAnimator
	if not anim.ready:
		t.ok(false, "模型实例上应当有 AnimationPlayer（前置条件）")
		_teardown(inst)
		return

	# ---- 三个动作确实合到了同一个播放器上 ----
	var got: Array = anim.action_names()
	var want: Array = ["burst", "burst_cruise", "fly"]
	got.sort()
	want.sort()
	t.ok(want.all(func(action): return got.has(action)), "基础三个动作与新模型形态动作共用同一个 AnimationPlayer")

	# ---- 常态入场 ----
	var fsm := ModelAnimFSM.create(anim, false)
	t.eq(fsm.state, ModelAnimFSM.State.IDLE, "create 后进 IDLE")
	t.eq(fsm.form_name(), "normal", "常态形态")
	t.eq(fsm.current_action(), "fly", "IDLE 起播 fly")
	t.eq(fsm.fallbacks, 0, "常态待机不需要回退")
	t.not_ok(fsm.is_locked(), "IDLE 未锁定")

	# ---- 形态切换：set_form 只写目标，tick 才生效（单一推进入口）----
	fsm.set_form(true)
	t.eq(fsm.form_name(), "normal", "set_form 不立刻改 form（只写目标形态）")
	t.eq(fsm.want_form_name(), "cruise", "目标形态已记下")
	fsm.tick(0.016)
	t.eq(fsm.form_name(), "cruise", "tick 后形态才生效")
	t.eq(fsm.fallbacks, 1,
		"★ 巡航形态没有专用待机 ⇒ 记一次回退（已知缺口，但是可观测的）")

	# ---- 巡航形态发射：必须选 burst_cruise ----
	t.ok(fsm.request_burst(), "巡航形态下 request_burst() 成功")
	t.eq(fsm.state, ModelAnimFSM.State.BURST, "进 BURST")
	t.eq(fsm.current_action(), "burst_cruise", "★ 选的是巡航版 burst_cruise")
	t.eq(fsm.fallbacks, 1, "巡航版拿得到，没有再记回退")
	t.ok(fsm.is_locked(), "BURST 期间 is_locked() == true")

	await _settle(fsm, host)
	t.eq(fsm.state, ModelAnimFSM.State.IDLE, "播完自动回 IDLE")
	t.eq(fsm.current_action(), "fly", "回到待机动作")
	t.not_ok(fsm.is_locked(), "回 IDLE 后解锁")

	# ---- 常态形态发射：必须选 burst ----
	var f2 := ModelAnimFSM.create(anim, false)
	t.ok(f2.request_burst(), "常态形态下 request_burst() 成功")
	t.eq(f2.current_action(), "burst", "★ 选的是常态版 burst")
	t.eq(f2.fallbacks, 0, "常态版没有回退")

	# ---- 记谱 ----
	var h := f2.history()
	t.ok(h.size() >= 2, "历史至少有 init + burst 两条（实测 %d）" % h.size())
	t.ok(str(h[0]).begins_with("init:"), "历史首条是初始化（%s）" % h[0])
	t.ok(str(h[h.size() - 1]).begins_with("burst:"), "历史末条是发射（%s）" % h[h.size() - 1])
	t.gt(f2.transitions, 1, "迁移计数在涨（%d 次）" % f2.transitions)

	_teardown(inst)


# ============================================================ ③ 锁定与事件驱动

## 这一段的四条是**互相独立**的坑，任何一条破了都会在生产里表现为"偶尔怪一下"。
static func _locking(t: T, host: Node) -> void:
	var m: Dictionary = await _mount(host)
	var inst := m["inst"] as Node3D
	var anim := m["anim"] as ModelAnimator
	if not anim.ready:
		t.ok(false, "模型实例上应当有 AnimationPlayer（前置条件）")
		_teardown(inst)
		return

	# ---- ① 同一瞬间连点：不重播 ----
	var fsm := ModelAnimFSM.create(anim, false)
	t.ok(fsm.request_burst(), "第一次发射")
	var after_first := fsm.transitions
	t.ok(fsm.request_burst(), "紧接着第二次也返回 true（幂等，不是失败）")
	t.eq(fsm.transitions, after_first,
		"★ 同一瞬间连点没产生新迁移（transitions 仍 = %d）" % after_first)

	# ---- ② 冷却结束后重播：必须从头播 ----
	await _settle(fsm, host)
	t.eq(fsm.state, ModelAnimFSM.State.IDLE, "第一轮播完回 IDLE")
	t.eq(fsm.current_action(), "fly", "第一轮回待机")
	t.ok(fsm.request_burst(), "冷却结束后再打一轮")
	t.eq(fsm.state, ModelAnimFSM.State.BURST, "重新进 BURST")
	t.lt(fsm.progress(), 0.35,
		"★ 第二轮是从头播的（progress %.3f 还很小，不是接着上一轮）" % fsm.progress())
	t.gt(fsm.transitions, after_first, "迁移计数继续增长（%d）" % fsm.transitions)

	# ---- ③ 帧驱动绝不重播 ----
	await _settle(fsm, host)
	var before_idle := fsm.transitions
	var act_before := fsm.current_action()
	for _i in 60:
		await host.get_tree().process_frame
		fsm.tick(0.016)
	t.eq(fsm.transitions, before_idle,
		"★ IDLE 里连推 60 帧 tick()：零迁移（没有每帧重启动作）")
	t.eq(fsm.current_action(), act_before, "动作名没有抖动（%s）" % act_before)
	t.gt(fsm.progress(), 0.0, "且待机动作确实在推进（progress %.4f）" % fsm.progress())

	# ---- ④ 发射途中形态切换：挂起，不打断 ----
	var f2 := ModelAnimFSM.create(anim, false)
	t.ok(f2.request_burst(), "常态形态发射")
	t.eq(f2.current_action(), "burst", "播的是常态版")
	f2.set_form(true)
	t.eq(f2.form_name(), "normal", "★ 发射途中 form 不变（挂起，不是不响应）")
	t.eq(f2.want_form_name(), "cruise", "目标形态已经记下")
	t.eq(f2.current_action(), "burst", "★ 动作也没被换掉（发射没被打断）")
	await _settle(f2, host)
	t.eq(f2.form_name(), "cruise", "★ 发射结束后，挂起的形态才生效")
	t.eq(f2.state, ModelAnimFSM.State.IDLE, "并回到 IDLE")

	_teardown(inst)


# ============================================================ ④ 冲刺八向（N46）

## 冲刺八向的**状态机语义**。
##
## ## 为什么非有这一套
##
## 八向动作从 N26 就在交付批次里，但工程侧**一直没有消费方** ——
## 用户实机反馈「八向冲刺动作没有反应」。排查（`REPORT-N45b`）证明：
## 8/8 段都能播，而全工程 `play_*("dash_*")` 调用点 = 0，`tick(delta)` 的签名里
## **根本没有可以传进 `translate_dir` 的位置**。⇒ 不是"幅度小"，是**没有线**。
##
## 于是接线方式设计成 `set_form()` 的同构体：**宿主写目标、`tick()` 兑现**。
## 这一套把它钉住，重点是三件静默失败：
##
##   * 宿主不报方向时**必须**留在 IDLE（老路径零影响，柯西以外五台都不报）；
##   * DASH 里**连推帧不许重播**（否则进度按在第 0 帧 = "动作播了看不出在动"）；
##   * 拿不到的方向名（名字写错 / 该机没有这一段）要**静默退化**，不崩不刷日志。
##
## 外加一条**优先级**：DASH 期间请求全弹发射 ⇒ BURST 必须抢走
##（`burst` 靠 `finished()` 收尾，被盖住会**永远收不了尾**）。
##
## 以及 ★★ **N46 用户回归**（「柯西转身结束之后背后飞翼会反复抽搐一下」）：
## 冲刺期间 `form` 必须**静默跟上** `_want_form`（⛔ 不许播过渡动作）。
## 修前它被"冲刺优先于形态切换"压着不办 ⇒ 窗口一结束立刻播 `form_off`，
## 而"放翼"此时已重新越过 0.5 阈值 ⇒ 紧接着又要 `form_on`
## ⇒ **一对方向相反的过渡动作首尾相接** = 屏幕上飞翼来回抽一下。
##
## ⚠️ 这条判据钉在**状态机内部状态**上（`form` vs `_want_form` / 迁移数 / 历史里
## 有没有 `form_off`）—— "屏幕抖不抖"不可复现，不能当判据。
static func _dash(t: T, host: Node) -> void:
	var m: Dictionary = await _mount_dash(host)
	var inst := m["inst"] as Node3D
	var anim := m["anim"] as ModelAnimator
	if not anim.ready:
		t.ok(false, "模型实例上应当有 AnimationPlayer（前置条件）")
		_teardown(inst)
		return
	# 前置：这一份样本确实带 dash（否则下面全是在测空气）
	t.ok(anim.has("dash_r") and anim.has("dash_f"),
		"样本确实带冲刺八向（前置：dash_r / dash_f 在可播表里）")

	# ---- ① 老路径：宿主不报方向 ⇒ 永远进不了 DASH ----
	var fsm := ModelAnimFSM.create(anim, false)
	t.eq(fsm.dash_dir(), "", "初始 dash_dir() 为空")
	t.eq(fsm.state, ModelAnimFSM.State.IDLE, "不报冲刺时是 IDLE")
	for _i in 30:
		await host.get_tree().process_frame
		fsm.tick(0.016)
	t.eq(fsm.state, ModelAnimFSM.State.IDLE,
		"★ 连推 30 帧也不进 DASH（宿主没报方向 ⇒ 行为与改动前逐位一致）")

	# ---- ② 报右向 ⇒ 进 DASH 且播 dash_r ----
	fsm.set_dash("r")
	t.eq(fsm.state, ModelAnimFSM.State.IDLE,
		"set_dash() 不立刻切动作（只写目标，与 set_form 同构）")
	await host.get_tree().process_frame
	fsm.tick(0.016)
	t.eq(fsm.state, ModelAnimFSM.State.DASH, "tick 后进 DASH")
	t.eq(fsm.current_action(), "dash_r", "★ 播的是 dash_r")
	t.eq(fsm.dash_dir(), "r", "dash_dir() 报出生效方向")
	t.eq(fsm.state_name(), "dash", "state_name() = dash")
	t.not_ok(fsm.is_locked(), "DASH 不是锁定态（形态切换仍可请求）")
	t.ok(fsm.is_enabled(), "DASH 算 enabled（不是哑机）")

	# ---- ③ ★ 帧驱动绝不重播 ----
	var before := fsm.transitions
	for _i in 30:
		await host.get_tree().process_frame
		fsm.tick(0.016)
	t.eq(fsm.transitions, before,
		"★ DASH 里连推 30 帧 tick()：零迁移（没有每帧重启动作）")
	t.eq(fsm.current_action(), "dash_r", "动作名没有抖动")
	t.gt(fsm.progress(), 0.0, "且冲刺动作确实在推进（progress %.4f）" % fsm.progress())

	# ---- ④ 中途改向 ⇒ 换到新的那一段 ----
	fsm.set_dash("f")
	await host.get_tree().process_frame
	fsm.tick(0.016)
	t.eq(fsm.current_action(), "dash_f", "★ 中途改向换到 dash_f")
	t.gt(fsm.transitions, before, "换段记了一次迁移（%d）" % fsm.transitions)

	# ---- ⑤ 清方向 ⇒ 回待机（柯西有待机，回 fly）----
	fsm.set_dash("")
	await host.get_tree().process_frame
	fsm.tick(0.016)
	t.eq(fsm.state, ModelAnimFSM.State.IDLE, "清空方向 ⇒ 回 IDLE")
	t.eq(fsm.current_action(), "fly", "回到常态待机 fly")
	t.eq(fsm.dash_dir(), "", "dash_dir() 随之为空")

	# ---- ⑥ 拿不到的方向名：静默退化，不崩不刷日志 ----
	var f2 := ModelAnimFSM.create(anim, false)
	t.eq(f2.dash_action_for("zz"), "", "dash_action_for(未知) 返回空串（纯查询）")
	t.eq(f2.dash_action_for(""), "", "dash_action_for(空串) 返回空串")
	f2.set_dash("zz")
	await host.get_tree().process_frame
	f2.tick(0.016)
	t.eq(f2.state, ModelAnimFSM.State.IDLE,
		"★ 方向名拿不到 ⇒ 留在 IDLE（静默退化，不崩）")
	t.eq(f2.current_action(), "fly", "且动作没被换掉")

	# ---- ⑦ 优先级：DASH 中请求发射 ⇒ BURST 抢走 ----
	var f3 := ModelAnimFSM.create(anim, false)
	f3.set_dash("l")
	await host.get_tree().process_frame
	f3.tick(0.016)
	t.eq(f3.state, ModelAnimFSM.State.DASH, "先进入 DASH（dash_l）")
	t.eq(f3.current_action(), "dash_l", "播的是 dash_l")
	t.ok(f3.request_burst(), "DASH 中请求全弹发射：拿到动作（返回 true）")
	f3.tick(0.016)
	t.eq(f3.state, ModelAnimFSM.State.BURST,
		"★ BURST 优先于 DASH（发射靠 finished() 收尾，不能被盖住）")
	t.eq(f3.current_action(), "burst", "播的是 burst")
	await _settle(f3, host)
	t.eq(f3.state, ModelAnimFSM.State.IDLE, "发射播完仍能正常回 IDLE（收尾没坏）")

	# ---- ⑧ 优先级反向：发射途中报冲刺 ⇒ 不打断发射 ----
	var f4 := ModelAnimFSM.create(anim, false)
	t.ok(f4.request_burst(), "先进 BURST")
	f4.set_dash("b")
	f4.tick(0.016)
	t.eq(f4.state, ModelAnimFSM.State.BURST,
		"★ 发射途中报冲刺不打断发射（同「发射途中形态切换挂起」的规矩）")
	t.eq(f4.current_action(), "burst", "动作仍是 burst")
	await _settle(f4, host)

	# ---- ⑨ ★★ N46：冲刺期间 `form` 静默跟上 `_want_form`（⛔ 不许有形态过渡）----
	#   症状 = 用户实测「柯西转身结束之后背后飞翼会反复抽搐一下」。
	#   根因 = 冲刺把形态切换压到窗口之后 ⇒ 撞上"放翼"重新越过 0.5 ⇒
	#          `form_off` 与 `form_on` 首尾相接。
	var f5 := ModelAnimFSM.create(anim, false)
	f5.set_form(false)
	await host.get_tree().process_frame
	f5.tick(0.016)
	t.eq(f5.form_name(), "normal", "N46 前置：常态形态")
	f5.set_dash("r")
	await host.get_tree().process_frame
	f5.tick(0.016)
	t.eq(f5.state, ModelAnimFSM.State.DASH, "N46 前置：已进 DASH")
	t.eq(f5.current_action(), "dash_r", "N46 前置：动作 = dash_r")
	var tr5 := f5.transitions
	# ★ 冲刺中请求切巡航（复刻 game 里 `_tick_cruise_morph()` 的每帧喂值）
	f5.set_form(true)
	await host.get_tree().process_frame
	f5.tick(0.016)
	t.eq(f5.want_form_name(), "cruise", "N46：待办形态已指向 cruise")
	t.eq(f5.form_name(), "cruise",
		"★★ N46：DASH 里 form 静默跟上 _want_form（修前这里仍是 normal ⇒ 抽搐）")
	t.eq(f5.transitions, tr5, "★ 静默同步不记迁移（没播过渡动作）")
	t.eq(f5.current_action(), "dash_r", "★ 冲刺动作没被过渡顶掉")
	t.eq(f5.state, ModelAnimFSM.State.DASH, "仍在 DASH")
	# 反向：改回常态，同样静默（修前正是这一来一回组成了"反复"抽搐）
	f5.set_form(false)
	await host.get_tree().process_frame
	f5.tick(0.016)
	t.eq(f5.form_name(), "normal", "★★ N46：反向同样静默跟上（不会来回抽）")
	t.eq(f5.transitions, tr5, "★ 反向同样零迁移")
	# 窗口结束 ⇒ 直接回待机。⚠️ 要多推几帧：`MIN_BURST_HOLD` 会把窗口内的
	# 「清方向」先挡一下（`_dash_hold` 还没攒够 0.05 s）。
	f5.set_dash("")
	for _i in 4:
		await host.get_tree().process_frame
		f5.tick(0.016)
	t.eq(f5.state, ModelAnimFSM.State.IDLE, "N46：清方向 ⇒ 回 IDLE")
	t.eq(f5.current_action(), "fly", "N46：落到常态待机 fly")
	var h5: Array[String] = f5.history()
	t.not_ok(h5.has("form_off"), "★★ N46 症状级：全程没有 form_off")
	t.not_ok(h5.has("form_on"), "★★ N46 症状级：全程没有 form_on")
	t.eq(f5.transitions, tr5 + 1,
		"★★ N46：整个冲刺 episode 只多出回待机这 1 次迁移")

	_teardown(inst)


# ============================================================ ⑤ 与 FlightBody 的集成

static func _integration(t: T, host: Node) -> void:
	var p := SuitProfile.xi()
	p.model_path = FLY
	var body := FlightBody.new()
	body.profile = p
	body.is_player = true
	body.use_placeholder = false
	body.flight_pitch_deg = 0.0
	host.add_child(body)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame

	t.ok(body.model_fsm != null, "柯西身上有状态机")
	t.ok(body.model_fsm.is_enabled(), "柯西的状态机已就绪（不是哑机）")
	t.eq(body.model_fsm.state, ModelAnimFSM.State.IDLE, "入场即 IDLE")
	t.eq(body.model_fsm.current_action(), "fly", "入场起播 fly")

	# 关掉物理推进，改成手动推 —— 时序才可复现。
	body.set_physics_process(false)

	# ---- 宿主接口 ----
	t.ok(body.play_full_burst(), "FlightBody.play_full_burst() 成功")
	t.eq(body.model_fsm.state, ModelAnimFSM.State.BURST, "宿主接口切进了 BURST")
	t.eq(body.full_burst_action(), "burst", "full_burst_action() 转发正确（常态形态）")

	# ---- ★ 动作真的在动（N28 的核心：不是孤儿）----
	var p0 := body.model_fsm.progress()
	for _i in 20:
		await host.get_tree().process_frame
		body._tick_model_anim(0.016)
	var p1 := body.model_fsm.progress()
	t.gt(p1, p0, "★ 发射动画进度在推进：%.4f → %.4f（动作不是孤儿）" % [p0, p1])

	# ---- 形态由宿主喂进去 ----
	body.cruise_morph = 1.0
	body._tick_model_anim(0.016)
	t.eq(body.model_fsm.want_form_name(), "cruise",
		"宿主把 cruise_morph 喂给了状态机（目标形态 = cruise）")
	t.eq(body.model_fsm.form_name(), "normal",
		"★ 但发射途中形态仍挂起（form 还是 normal）")

	# ---- ★ 旁路播放会被记账 ----
	await _settle(body.model_fsm, host)
	t.eq(body.model_fsm.state, ModelAnimFSM.State.IDLE, "发射结束回 IDLE")
	t.eq(body.model_fsm.form_name(), "cruise", "挂起的巡航形态在这一刻生效")
	var d0 := body.model_fsm.desyncs
	# ⚠️ 这里必须旁路播一个**与状态机认知不同**的动作。
	# 此时机体已在巡航形态、状态机手里没有动作名（`_action == ""`）——
	# 它要求底层跑的是**巡航归位段 `__cruise_hold__`**（N56）。
	#
	# ★★ N56：这条断言**在加收枪那一轮真的变红过**（got=0/want>0），
	#   根因不是"旁路没被记账"，而是 `_check_desync()` 原本在 `_action == ""` 时
	#   **直接早退** ⇒ 换掉待机载体（`cruise_idle` → `__cruise_hold__`）顺手关掉了
	#   一条观测通路。修法是让状态机记下"要求底层跑什么"（`ModelAnimFSM._idle_clip`）
	#   ⇒ **这条断言就是那次修复的证伪条**，删掉它那个洞会再次静默张开。
	#
	# ⚠️ 若旁路也播同一段，`play_once()` 对同名动作不重启动（防"每帧重启"）⇒
	#   底层 `current` 压根没变，那就**没有失同步可言**，断言会误红。
	#
	# ★ N49：触发方式从 `body.play_model_action("burst")` 改成**直调底层播放器** ——
	#   `play_model_action()` 现在**不再是一条旁路**（它转发给
	#   `ModelAnimFSM.request_action()`、走 `ACTION` 态），拿它测"旁路可观测"会恒为 0。
	#   **要测的语义一个字没变**（"有人绕过状态机直接写播放器"必须被记账），
	#   变的只是"用哪只手去绕"：状态机之外的那只手现在只剩 `ModelAnimator` 自己。
	body.model_anim.play_once("burst")
	body._tick_model_anim(0.016)
	t.gt(body.model_fsm.desyncs, d0,
		"★ 绕过状态机播别的动作 ⇒ desyncs 涨到 %d（旁路可观测）" % body.model_fsm.desyncs)

	body.set_physics_process(true)
	body.free()


# ============================================================ ⑤b 收枪（N56）

## ## 为什么非有这一套
##
## 用户报：「柯西在巡航模式下按 WASD 就会举枪 ⇒ 不要举枪，**只有光束步枪射击时才举枪**」，
## 并追加：「射击完，如果**短时间内没有下一发**，就**倒放**收枪」。
##
## ## 这一段钉的三个静默失败
##
##   * **收枪有没有发生**：`can_stow = false`（默认）时**必须一次都不收** ——
##     否则军刀 / 举盾 / 变身那几条会连带被倒放，而它们**不报错**，只是动作怪一下；
##   * **倒放 ≠ 归位**：`shoot` 的**首帧 ≡ 末帧 ≡ 常态待机 `fly` 首帧**（N56·T60 实测
##     两两逐位 `0.000000`）⇒ 只倒放到底**仍在举枪位** ⇒ 必须紧跟一次归位混合；
##   * **倒放期间开火被吞**：`ModelAnimator.play_once()` 的「同段在播不重播」会把
##     **倒放也认成在播** ⇒ 按了没反应（N56 §1.5 实测 `speed` 恒 `−1.00`）
##     ⇒ 收枪必须是**独立态且优先级低于 `ACTION`**，让新射击天然抢断。
##
## ## 判据（★ 正判 + 证伪条）
##
##   ① ★ **证伪条**：`can_stow = false` ⇒ 播完**直接回 IDLE**，`stows == 0`；
##   ② 正判：`can_stow = true` ⇒ 播完进 `UNACTION`、`stow_stage() == 0`（滞留），
##      且**播放器停着**（T30：停播不还原姿态 ⇒ 就是「枪还举着」）；
##   ③ 正判：宿主报窗口到 ⇒ 进阶段 1、`stows == 1`、**播放速度为负**；
##   ④ ★ **抢断**：倒放途中 `request_action("shoot", true)` ⇒ 回 `ACTION`、速度**翻正**
##      （没有 ④ 的话，"倒放中按了没反应"这个 bug 会再次静默复发）；
##   ⑤ 正判：倒放播完 ⇒ 回 `IDLE`，且播的是**巡航归位段**（不是 `cruise_idle`）；
##   ⑥ ★ **证伪条**：没有归位段的模型（其余五台机体走的路）⇒ 声明了 `can_stow` 也**不收**。
static func _unaction(t: T, host: Node) -> void:
	var m: Dictionary = await _mount_stow(host)
	var inst := m["inst"] as Node3D
	var anim := m["anim"] as ModelAnimator
	if not anim.ready:
		t.ok(false, "模型实例上应当有 AnimationPlayer（前置条件）")
		_teardown(inst)
		return
	t.ok(anim.has("shoot"), "（前置）样本带 shoot")
	t.ok(anim.has_cruise_hold(), "（前置）巡航归位段建出来了 —— 没有它就不该收枪")

	# ---- ① ★ 证伪条：不声明 can_stow ⇒ 一次都不收 ----
	var f0 := ModelAnimFSM.create(anim, true)
	t.ok(f0.request_action("shoot"), "① 起播 shoot（**不**声明可收枪）")
	t.eq(f0.state, ModelAnimFSM.State.ACTION, "① 进的是 ACTION")
	t.eq(f0.stow_stage(), -1, "① 不在收枪（stow_stage() == -1）")
	await _settle_from(f0, host, ModelAnimFSM.State.ACTION)
	t.eq(f0.state, ModelAnimFSM.State.IDLE,
		"★ ① 证伪条：can_stow = false ⇒ 播完**直接回 IDLE**（不进收枪）")
	t.eq(f0.stows, 0, "★ ① 收枪计数 == 0（军刀/举盾/变身那几条走的就是这条路）")

	# ---- ② 声明 can_stow ⇒ 播完进 UNACTION 滞留（枪还举着）----
	var f := ModelAnimFSM.create(anim, true)
	t.ok(f.request_action("shoot", true), "② 起播 shoot（声明可收枪）")
	await _settle_from(f, host, ModelAnimFSM.State.ACTION)
	t.eq(f.state, ModelAnimFSM.State.UNACTION, "★ ② 播完进 UNACTION（不是直接回 IDLE）")
	t.eq(f.state_name(), "unaction", "② state_name() = unaction")
	t.eq(f.stow_stage(), 0, "★ ② 阶段 0 = 滞留（还举着枪，等窗口）")
	t.not_ok(anim.player.is_playing(),
		"★★ ② 滞留期**什么都不播** ⇒ 停播不还原姿态（T30）⇒ 就是「枪还举着」")
	t.eq(f.stows, 0, "② 还没开始倒放")
	t.not_ok(f.is_locked(), "② 收枪不是锁定态（优先级最低，靠抢断而非锁）")

	# ---- ③ 窗口到了 ⇒ 起倒放 ----
	f.set_can_stow(true)
	await host.get_tree().process_frame
	f.tick(0.016)
	t.eq(f.stow_stage(), 1, "★ ③ 进阶段 1 = 倒放中")
	t.eq(f.stows, 1, "★ ③ 收枪计数 +1")
	t.eq(f.current_action(), "shoot", "③ 倒的是 shoot 这一段")
	t.lt(anim.player.get_playing_speed(), 0.0,
		"★★ ③ 播放速度为**负**（实测 %.2f）—— 这才叫「倒放」，⛔ 不是「再播一遍」"
		% anim.player.get_playing_speed())

	# ---- ④ ★ 抢断：倒放途中开火 ⇒ 立刻回 ACTION、速度翻正 ----
	t.ok(f.request_action("shoot", true), "④ 倒放途中开火（返回 true）")
	t.eq(f.state, ModelAnimFSM.State.ACTION,
		"★★ ④ 抢断回 ACTION（收枪优先级最低 ⇒ 不需要任何特例分支）")
	t.eq(f.stow_stage(), -1, "④ 已离开收枪态")
	t.gt(anim.player.get_playing_speed(), 0.0,
		"★★ ④ 速度**翻正**（实测 %.2f）—— 修前是恒 −1.00（按了没反应）"
		% anim.player.get_playing_speed())

	# ---- ⑤ 走完一整轮：滞留 → 倒放 → 回 IDLE 且播**巡航归位段** ----
	await _settle_from(f, host, ModelAnimFSM.State.ACTION)
	t.eq(f.state, ModelAnimFSM.State.UNACTION, "⑤ ①~④ 之后又回到滞留（can_stow 仍为真）")
	f.set_can_stow(true)
	await host.get_tree().process_frame
	f.tick(0.016)
	t.eq(f.stow_stage(), 1, "⑤ 再次进入倒放")
	t.eq(f.stows, 2, "⑤ 收枪计数 == 2")
	await _settle_from(f, host, ModelAnimFSM.State.UNACTION)
	t.eq(f.state, ModelAnimFSM.State.IDLE, "★ ⑤ 倒放播完回 IDLE（T61②：倒放到 0 自然停）")
	t.eq(f.current_action(), "", "★ ⑤ 回 IDLE 后动作名为空串（收枪不登记成动作）")
	t.eq(anim.current, str(ModelAnimator.CRUISE_HOLD_CLIP),
		"★★ ⑤ 收枪后播的是**巡航归位段**（⛔ 不是 cruise_idle —— 它不带臂/腿）")
	t.ok(anim.player.is_playing(),
		"★ ⑤ 归位段在跑（下一次 play(blend) 才有前一段可混）")

	# ---- ⑥ ★ 证伪条：没有归位段的模型 ⇒ 声明了 can_stow 也不收 ----
	var m2: Dictionary = await _mount_stow(host, false)
	var inst2 := m2["inst"] as Node3D
	var anim2 := m2["anim"] as ModelAnimator
	t.not_ok(anim2.has_cruise_hold(), "（前置）这一份确实没有归位段")
	var f2 := ModelAnimFSM.create(anim2, true)
	t.ok(f2.request_action("shoot", true), "⑥ 声明 can_stow = true")
	await _settle_from(f2, host, ModelAnimFSM.State.ACTION)
	t.eq(f2.state, ModelAnimFSM.State.IDLE,
		"★ ⑥ 证伪条：没有归位段 ⇒ 不收枪（② 不是恒真断言）")
	t.eq(f2.stows, 0, "★ ⑥ 收枪计数 == 0")

	_teardown(inst2)
	_teardown(inst)


# ============================================================ 工具

## 挂一个"已进树、动画就绪"的柯西模型实例。
##
## ⚠️ 直接造 `ModelAnimator` 而不套 `FlightBody`：状态机的单元行为不该
## 依赖飞行体的物理/形态那一整套东西，否则测试会因为无关的物理扰动而红。
static func _mount(host: Node) -> Dictionary:
	var ps := load(FLY) as PackedScene
	var inst := ps.instantiate() as Node3D
	host.add_child(inst)
	await host.get_tree().process_frame
	var anim := ModelAnimator.setup(inst, [BURST, BURST_CRUISE])
	return {"inst": inst, "anim": anim}


## 挂一个**带冲刺八向**的柯西实例。
##
## ⚠️ 为什么另开一个、不给 `_mount()` 加参数：`_transitions()` 里有一条
## 「动作表恰好 = `[burst, burst_cruise, fly]`」的断言 —— 给 `_mount()` 加件会把它顶红。
## 那条断言本身是对的（钉的是"跨 glb 摘取**只摘该摘的**"），不该为了测试方便放宽。
##
## `burst` / `burst_cruise` 仍然带上：第 ⑦⑧ 条要验 DASH 与 BURST 的优先级。
static func _mount_dash(host: Node) -> Dictionary:
	var ps := load(FLY) as PackedScene
	var inst := ps.instantiate() as Node3D
	host.add_child(inst)
	await host.get_tree().process_frame
	var anim := ModelAnimator.setup(inst,
			[BURST, BURST_CRUISE, DASH_F, DASH_R, DASH_L, DASH_B])
	return {"inst": inst, "anim": anim}


## 挂一个**带收枪全套**（`shoot` ＋ 巡航待机 ＋ `form_on`）的柯西实例。
##
## `with_hold = false` 时**故意不**调 `prepare_clips()`：这一份就等价于
## 「**其余五台机体**」——它们没有巡航待机 ⇒ 建不出归位段 ⇒ `_stow_eligible()` 为假。
## 用它当第 ⑥ 条的正经证伪条。
static func _mount_stow(host: Node, with_hold := true) -> Dictionary:
	var ps := load(FLY) as PackedScene
	var inst := ps.instantiate() as Node3D
	host.add_child(inst)
	await host.get_tree().process_frame
	var anim := ModelAnimator.setup(inst, [SHOOT, CRUISE_IDLE, FORM_ON])
	if with_hold:
		# ★ 复刻生产路径的赋值顺序（`FlightBody._setup_model_anim()`）：
		#   `setup()` → 赋名字 → `prepare_loops()` → `prepare_clips()`。
		var p := SuitProfile.xi()
		anim.idle_cruise_action = p.model_anim_idle_cruise
		anim.form_on_action = p.model_anim_form_on
		anim.prepare_loops()
		anim.prepare_clips()
	return {"inst": inst, "anim": anim}


## 一直 tick 到这个状态机离开 BURST（或超时）。
static func _settle(fsm: ModelAnimFSM, host: Node) -> void:
	await _settle_from(fsm, host, ModelAnimFSM.State.BURST)


## 一直 tick 到这个状态机**离开 `from`**（或超时）。
##
## ⚠️ 必须真的 `await process_frame`：`AnimationPlayer` 是按真实 delta 推进的，
## 靠"连续调 tick()"只会空转 —— 播放头不动，`finished()` 永远不真，
## 循环会一直跑到超时，然后红一条**看着像状态机坏了**的断言。
static func _settle_from(fsm: ModelAnimFSM, host: Node, from: int) -> void:
	var t0 := Time.get_ticks_msec()
	var deadline := int(SETTLE_TIMEOUT * 1000.0)
	while fsm.state == from and Time.get_ticks_msec() - t0 < deadline:
		await host.get_tree().process_frame
		fsm.tick(0.016)


static func _teardown(inst: Node) -> void:
	if inst != null and is_instance_valid(inst):
		inst.free()
