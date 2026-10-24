extends RefCounted
## N57：**老路（按住连发）开火必须播 `shoot` 战斗动作** —— 只走**输入层**验证。
##
## ## 为什么这个套件必须存在（它的存在本身就是一条判据）
##
## 用户 2026-09-29 真机反馈：「**开枪还是没有抬手动作啊**」。
## 而上一轮（N56）我的探针**读数是绿的** —— 因为那个自称"真机条件"的探针
## 直接调 `fb.play_model_action("shoot", true)`：它补上了 T65 的**条件差**
##（不关 tick、不手推帧、等稳态），却漏掉了**入口差** ——
## **直接调 API ≠ 玩家按键**。
##
## 真根因：`player_controller._read_weapon_input()` 里，全工程**只有**
## `profile.rifle_fire_on_release == true` 那条路（`_read_release_rifle()` →
## `_shoot_rifle_now()`）会调 `play_model_action()`；**老路**（按住连发，
## 该字段**默认 false**，**柯西走的就是它**）一个动作调用都没有
## ⇒ 打得出光束、HUD 弹匣在减，**手臂一动不动**。
##
## ⇒ 本套件**只走输入层**（`Input.action_press("fire_primary")`），
##   ⛔ **不许直接调 `play_model_action()`** —— 那样就又回到"测了个假的"。
##
## ## 证伪条（A/B 实测过，不是声称）
##
## 把 `player_controller.gd` 老路里 `play_model_action("shoot", true)` 那一行
## 注释掉 ⇒ 本套件 `常态开火` 与 `巡航开火 + 收枪` 两节**必须变红**
##（前者的"进了 ACTION / 接管 shoot"，后者的"臂峰值 / stows"）。
##
## `Input.action_press` 的可用性：本工程 `suite_assist_drive.gd` 早有先例；
## ⚠️ 而 `tutorial_director.gd:47` 记的"无头下 `just_pressed` 帧戳不可靠"那条坑
## **不影响本套件** —— 老路读的是 `is_action_pressed`（持续态），不是 just_pressed。

const ARM_BONES := ["UpperArm.R", "LowerArm.R", "Hand.R"]
## ★ 起始高度：**必须远高于海面**。巡航那一节要按住形态飞 ~8 秒，
## 机体不悬停时会掉高度 —— `y = 900` 实测自由落体到撞海（`[destroy] 撞海`），
## 机体被 `queue_free()` 之后读任何字段都变成 `previously freed` 脚本错误，
## 把"机体没活下来"伪装成"读属性失败"（T31 的变体：静默失败换了个面孔）。
## 3000 与已跑通的 `probe_n56_fire_trace.gd` 同一口径。
const START_Y := 3000.0
const MODEL_WAIT_SEC := 20.0
const CRUISE_WAIT_SEC := 14.0
const STOW_WAIT_FRAMES := 240


static func run(t: T, host: Node) -> void:
	# 清场：上一个套件 / 上一轮若残留按键，"按住"这一路会假真。
	Input.action_release("fire_primary")
	_premise(t)
	await _normal_form(t, host)
	await _cruise_form(t, host)
	await _cruise_dash(t, host)
	_wiring(t)


## 前提守卫。**不是**为了证明"柯西该在老路"，而是**保护本套件判据的有效性**：
## 哪天有人把柯西改成松手发射，本套件的两节就都测不到老路了 —— 那时**必须变红**提醒，
## 否则它会安静地继续绿、而老路已经没人测。
static func _premise(t: T) -> void:
	t.suite("FireAction / 前提（柯西确实走老路）")
	t.ok(InputMap.has_action("fire_primary"),
		"`fire_primary` 是真键位（不然 `Input.action_press` 注入的是个空气动作）")
	var p := SuitProfile.xi()
	t.not_ok(p.rifle_fire_on_release,
		"柯西 `rifle_fire_on_release == false` ⇒ 走**老路**（按住连发）")
	t.gt(p.rifle_interval, 0.0, "柯西有步枪冷却 %.2f s" % p.rifle_interval)


## (a) 常态开火：按住左键 ⇒ 状态机进 `ACTION`，且当前动作是 `shoot`。
##
## ★ 本节的**证伪条**就在生产那一行上：删掉 ⇒ 永远进不了 ACTION。
static func _normal_form(t: T, host: Node) -> void:
	t.suite("FireAction / 常态开火（走输入层）")
	var pc := _make_player(host, SuitProfile.xi())
	var ok_model := await _wait_model(pc, host)
	t.ok(ok_model, "模型装载完成（`model_anim.ready` —— 没装载则 `model_fsm` 是哑机，动作一律拒收）")
	if not ok_model:
		_drop(pc)
		return
	t.ok(pc.alive, "玩家机体活着（`_physics_process` 不会在开头早退）")
	t.gt(pc.rifle_count, 0, "带着步枪（%d 把）" % pc.rifle_count)
	t.gt(pc.rifle_mag, 0, "弹匣里有弹（%d 发）" % pc.rifle_mag)
	t.eq(pc.current_slot(), "rifle", "当前槽位是步枪 —— 左键才会走 `_read_weapon_input` 的步枪分支")
	t.ok(pc.projectile_container != null,
		"`projectile_container` 非空（为空时 `fire_beam()` 会**静默** return false）")

	Input.action_press("fire_primary")
	var entered := false
	var got := ""
	for i in 40:
		await host.get_tree().physics_frame
		if pc.model_fsm.state == ModelAnimFSM.State.ACTION:
			entered = true
			got = pc.model_fsm.current_action()
			break
	Input.action_release("fire_primary")

	t.ok(entered, "按住左键后状态机进了 `ACTION`（这条路只能由 `_read_weapon_input()` 走通）")
	t.eq(got, "shoot", "接管的动作是 `shoot`（不是别的战斗动作）")
	t.ok(_history_has(pc, "action:shoot"),
		"状态机的事件流水里出现过 `action:shoot`（`_note()` 记的，绕不过去）")
	_drop(pc)
	await host.get_tree().physics_frame


## (b) 巡航开火 + 收枪：形态进巡航后按左键 ⇒ 同样 ACTION/shoot，
##     手臂从**巡航基准**抬起 ≥ 20°，且停火后自动收枪（`stows` ≥ 1）并归位。
##
## ★ 这里同时验 N56 的收枪：`can_stow = true` 只在柯西这条路上真的生效。
static func _cruise_form(t: T, host: Node) -> void:
	t.suite("FireAction / 巡航开火 + 收枪（走输入层）")
	var pc := _make_player(host, SuitProfile.xi())
	var ok_model := await _wait_model(pc, host)
	if not ok_model:
		t.ok(false, "★ 模型装载完成 —— 没完成则本节全无意义")
		_drop(pc)
		return
	if pc.model_anim == null or not pc.model_anim.has_cruise_hold():
		# ⛔ 不给"跳过"的出口：柯西必须建得出巡航归位段，建不出说明资产 / 装机坏了。
		t.ok(false, "★ 柯西必须建得出巡航归位段（`has_cruise_hold()`）")
		_drop(pc)
		return
	var skel: Skeleton3D = pc._model_skel
	if skel == null:
		t.ok(false, "★ 拿不到骨架（`use_placeholder` 必须为 false 才有真模型）")
		_drop(pc)
		return

	# ★★ 进巡航形态**必须走状态层**，⛔ 不能手写 `fm.boosting` / `fm.hovering`：
	#   `PlayerController._think()` 每帧都会按当前模式**重写**这两个字段
	#   （`_read_translate_input()` 结尾就是 `hovering = false` ＋ `boosting = true`），
	#   手写的值**下一帧就被盖掉** —— 这一版我实测踩过：`--only` 跑出
	#   "巡航稳态没达成" 而机体还活着（存活那条 PASS）。
	#   ⚠️ 探针 `probe_n56_fire_trace.gd` 用 `FlightBody` 能过、本测试用
	#   `PlayerController` 过不了，差的就是这层 `_think()` 覆写 ——
	#   **这也是"入口差"的又一例：状态字段不是输入，写它 ≠ 让机体真的那么飞。**
	#   辅助驾驶开 ⇒ 平移模式（`boosting` 恒真 ＋ 不悬停）＝ 巡航条件。
	#   用户报的「巡航模式下按 WASD 举枪」本来就发生在辅助驾驶下 ⇒ 条件与真机一致。
	pc.assist_on = true
	var steady := await _wait_cruise(pc, host)
	t.ok(steady, "巡航稳态达成（`cruise_morph` ≥ 0.999 ＋ 状态机 IDLE ＋ 播 `__cruise_hold__`）")
	if not steady:
		# ★ 区分"没到稳态"与"机体没了" —— 后者必须说清楚，否则会被读成形态逻辑坏。
		t.ok(is_instance_valid(pc) and pc.alive,
			"（失败原因排查）机体仍活着 —— 没活着就是撞海了，不是形态逻辑的问题")
		_drop(pc)
		return

	var ref := _arm_ref(skel)
	var drift := _arm_gap(skel, ref)
	t.lt(drift, 0.01, "取基准那一刻臂的漂移 %.4f°（应 ≈ 0）" % drift)

	# ---- 开火：只按输入层 ----
	Input.action_press("fire_primary")
	var entered := false
	for i in 40:
		await host.get_tree().physics_frame
		if pc.model_fsm.state == ModelAnimFSM.State.ACTION:
			entered = true
			break
	t.ok(entered, "巡航下按住左键同样进了 `ACTION`（动作没被 DASH / TURN 抢走）")
	t.eq(pc.model_fsm.current_action(), "shoot", "接管的是 `shoot`")

	# ---- 峰值 ＋「按住就不该收枪」----
	#
	# ★ 峰值必须在**按住**期间取：抬枪发生在动作的头 0.4 s 里。
	# ★ 同时守一条用户需求原话：「短时间内**没有**进行下一发射击，就倒放进行收枪」
	#   ⇒ 反向也成立：**一直按着就绝不该收枪**。按住期间每次开火都把 `stow_idle`
	#     归零，所以收枪窗永远走不完 —— 这一条把"窗口太短、边打边收"钉死。
	var peak := 0.0
	var peak_at := -1
	for i in 120:
		await host.get_tree().physics_frame
		var g := _arm_gap(skel, ref)
		if g > peak:
			peak = g
			peak_at = i
	t.gt(peak, 20.0, "开火窗内手臂离巡航基准峰值 %.2f°（第 %d 帧）⇒ 真的抬起来了" % [peak, peak_at])
	var held_stows := pc.model_fsm.stows
	Input.action_release("fire_primary")
	t.eq(held_stows, 0, "全程按住左键期间**一次都没收枪**（`stows` 仍为 0）——「停手才收」")

	# ---- 收枪：松手后自己放下（倒放 ＋ 归位），状态回到 IDLE ----
	var stowed := false
	for i in STOW_WAIT_FRAMES:
		await host.get_tree().physics_frame
		if pc.model_fsm.stows >= 1 and pc.model_fsm.state == ModelAnimFSM.State.IDLE:
			stowed = true
			break
	t.ok(stowed, "松手后自动收枪（`stows` ≥ 1 且回到 IDLE）")
	if stowed:
		# ★★ 归位是**混合**（0.18 s），不是瞬变：`stows` 在倒放**结束**时就 +1、
		#   状态随即回 IDLE，而**归位混合才刚开始** ⇒ 那一刻立刻读臂还在高位。
		#   实测踩到：立刻读得 **85.20°**，看着像"没收枪"，其实只是"还在混合中"。
		#   ⚠️ 与 T65 的「基线必须先等稳态」是同一族的坑：**读数必须等稳态**。
		var settled := await _wait_arm_back(pc, host, skel, ref, 1.0, 2.5)
		t.ok(settled, "收枪后手臂回到巡航基准 %.4f°（应 < 1° ＝ 真归位）" % _arm_gap(skel, ref))
	# ★ 最后兜一条"实验条件本身成立"：机体没在过程中撞海。没有它，
	#   一旦高度不够，上面所有读数都是在**已被销毁的机体**上取的（而脚本错误会掩盖这点）。
	t.ok(_alive(pc), "开火 → 收枪全程机体没坠毁（读数取在真活机体上）")
	_drop(pc)
	await host.get_tree().physics_frame


## 源码守卫：老路的 `elif` 分支体里必须**同时**有 `fire_beam(true, target)` 与
## `play_model_action("shoot"`，且后者在分支内（位置在前者之后）。
##
## ★ 为什么源码守卫不能省：行为测试依赖"搭得起真玩家控制器"这一整串环境；
##   哪天环境坏了（模型装不上 / autoload 缺失），行为测试会**红成一片而看不出是环境问题**，
##   而这条静态断言能独立指出"接线本身还在不在"。⛔ 但它**代替不了**行为测试。

## (c) 巡航形态下**冲刺**同样不该举枪（用户原话：「按前后**冲刺**的时候枪会举起来」）。
##
## ★ 这是 N57 的第二处修复。N56 只抑制了两族 —— `fly_*`（`set_fly_dir`）与
##   `turn_*`（`set_turn`），**漏了冲刺族**（`set_dash(_dash_anim_dir)`，
##   `flight_body.gd:1767`）。而冲刺族优先级**更高**（`ModelAnimFSM.tick()` 里
##   冲刺族在前、平飞族在后）⇒ 巡航下按 Shift 冲刺照样播 `dash_*`，
##   它们同样是"常态基准姿态" ⇒ 把手臂从巡航位带走。
##
## ★ 触发手段：直接调 `request_quick_boost()` —— 与 `suite_assist_drive._auto_flight()`
##   完全同一手段（本工程既有先例）。它是**被检对象的入口**（等价于"玩家点按了
##   Shift"），之后的一切（`_read_translate_input` → `_apply_translate` →
##   `_start_dash_anim` → `_dash_anim_dir` → `set_dash` → 状态机）**全是生产代码在跑**。
##   ⛔ 不用 `Input.action_press("boost")`：那条读的是 `is_action_just_pressed`，
##      无头下**帧戳不可靠**（`tutorial_director.gd:47` 有实测记录：连续注入 40 次一次不触发）。
static func _cruise_dash(t: T, host: Node) -> void:
	t.suite("FireAction / 巡航冲刺不举枪（走冲刺入口）")
	var pc := _make_player(host, SuitProfile.xi())
	var ok_model := await _wait_model(pc, host)
	if not ok_model:
		t.ok(false, "★ 模型装载完成")
		_drop(pc)
		return
	var skel: Skeleton3D = pc._model_skel
	if skel == null:
		t.ok(false, "★ 拿不到骨架")
		_drop(pc)
		return
	pc.assist_on = true
	var steady := await _wait_cruise(pc, host)
	t.ok(steady, "巡航稳态达成")
	if not steady:
		_drop(pc)
		return
	var ref := _arm_ref(skel)
	t.lt(_arm_gap(skel, ref), 0.01, "基准漂移 ≈ 0（%.4f°）" % _arm_gap(skel, ref))

	pc.request_quick_boost()
	await host.get_tree().physics_frame
	# ★★ 这条是**防假绿**的：冲刺窗口没开的话，"臂峰值 < 1°"是**恒真**的
	#   （什么都不播自然不动）—— 那会把"没测到"读成"抑制生效"。
	t.ok(pc.translate_dash, "冲刺窗口真的开了（否则下面那条是恒真的假绿）")
	var peak := 0.0
	var peak_at := -1
	for i in 96:
		await host.get_tree().physics_frame
		var g := _arm_gap(skel, ref)
		if g > peak:
			peak = g
			peak_at = i
	t.lt(peak, 1.0,
		"冲刺期间手臂离巡航基准峰值 %.4f°（第 %d 帧，应 < 1° ＝ 冲刺也不举枪）" % [peak, peak_at])
	t.ok(_alive(pc), "全程机体没坠毁")
	_drop(pc)
	await host.get_tree().physics_frame


static func _wiring(t: T) -> void:
	t.suite("FireAction / 接线（源码守卫）")
	const PATH := "res://scripts/flight/player_controller.gd"
	var src := _code(PATH)
	t.ok(src != "", "读到了 player_controller.gd 且剥掉了注释行")

	var i_old := src.find('elif Input.is_action_pressed("fire_primary")')
	t.gt(i_old, 0, "老路（按住连发）的 `elif` 还在")
	var i_fire := src.find("fire_beam(true, target)", i_old)
	t.gt(i_fire, i_old, "老路分支体里有 `fire_beam(true, target)`")
	var i_act := src.find('play_model_action("shoot"', i_fire)
	t.gt(i_act, i_fire, "★ 老路分支体里**紧跟其后**有 `play_model_action(\"shoot\"`（N57 修的就是这一条）")
	# ★ 必须与 `camera` 判空拆开：原写法 `fire_beam(...) and camera != null` 会在
	#   `camera == null` 时把动作一起短路掉（静默不播）。
	# Check only the beam-to-animation path. A later camera-only flash branch
	# must not be mistaken for a guard around the animation call.
	var probe := src.substr(i_fire,maxi(0,i_act-i_fire))
	t.not_ok(probe.contains("and camera != null"),
		"动作不在 `and camera != null` 的短路表达式里（否则无镜头时静默不播）")

	var i_want := src.find('play_model_action("shoot", true)')
	t.gt(i_want, 0, "`can_stow` 显式传 `true`（收枪只由火器声明，军刀 / 举盾不声明）")


# ---------------------------------------------------------------- 工具

## 剥掉整行注释后的源码。**必须剥** —— 本文件的说明文字里到处写着
## `play_model_action("shoot", true)` 这些片段，不剥的话"名字出现过"与
## "代码真的调用它"分不开（假绿）。与 `suite_arizeus_cannon._code()` 同一口径。
static func _code(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	var out := ""
	for line in txt.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out += line + "\n"
	return out


static func _history_has(pc: PlayerController, needle: String) -> bool:
	if pc.model_fsm == null:
		return false
	for s in pc.model_fsm._history:
		if str(s) == needle:
			return true
	return false


## 搭一台**真**玩家控制器：`PlayerController` ＋ 真模型 ＋ 抬离海面。
static func _make_player(host: Node, p: SuitProfile) -> PlayerController:
	var holder := Node3D.new()
	host.add_child(holder)
	var pc := PlayerController.new()
	pc.name = "FireActionProbe"
	pc.profile = p
	pc.is_player = true
	pc.team = 0
	pc.controls_enabled = true
	holder.add_child(pc)
	# ★ 抬离海面（见 `START_Y` 的说明）：碰海 `die()` ⇒ 模型隐藏 ⇒ 动作链**永不触发且不报错**。
	pc.global_transform = Transform3D(Basis(), Vector3(0.0, START_Y, 0.0))
	return pc


## 拆掉这一节搭出来的整棵子树（holder 是 `_make_player` 加的）。
static func _drop(pc: PlayerController) -> void:
	if not is_instance_valid(pc):
		return
	var holder := pc.get_parent()
	if holder != null and is_instance_valid(holder):
		holder.queue_free()


## 等模型装载完成。`ready` 是 `ModelAnimator` 自己写的"轨道 / 段都挂好了"
## （`model_anim.gd:44`）—— ⛔ 不能用"等 N 帧"代替：glb 大小不同，帧数不是判据。
static func _wait_model(pc: PlayerController, host: Node) -> bool:
	var budget := int(MODEL_WAIT_SEC * 60.0)
	for i in budget:
		if not _alive(pc):
			return false
		if pc.model_anim != null and pc.model_anim.ready:
			return true
		await host.get_tree().physics_frame
	return false


## 等巡航稳态。★ 只 `await`，**不手推** —— 态必须是宿主自己走到的（T65）。
static func _wait_cruise(pc: PlayerController, host: Node) -> bool:
	var budget := int(CRUISE_WAIT_SEC * 60.0)
	for i in budget:
		# ★ 守卫：撞海会被 `queue_free()`，此后每次读字段都是一条 `previously freed`
		#   脚本错误 —— 那会把"机体没活下来"读成"形态逻辑坏"，是本轮真踩到的坑。
		if not _alive(pc):
			return false
		if pc.cruise_morph >= 0.999 and pc.model_fsm != null \
				and pc.model_fsm.state == ModelAnimFSM.State.IDLE \
				and pc.model_anim != null \
				and pc.model_anim.current == str(ModelAnimator.CRUISE_HOLD_CLIP):
			return true
		await host.get_tree().physics_frame
	return false


## 实例仍然有效且机体活着（`alive == false` = 已被摧毁 / 正在自毁流程）。
static func _alive(pc: PlayerController) -> bool:
	return is_instance_valid(pc) and pc.alive


## 等手臂**回落到基准**（`tol` 度以内），最多 `max_sec` 秒。
##
## ★ 收枪的最后一段是**混合**（0.18 s）——`stows` 一到 1 就立刻读，读到的是
##   "还在混合中"的高位（实测 85.20°），会误判成"没收枪"。所以判据必须是
##   **最终**回到基准，而不是"收枪事件发生时"的姿态。
## ⛔ 也不能只"等固定 30 帧"：混合时长是配置项（`BLEND_*`），写死帧数就是第二个真源。
static func _wait_arm_back(pc: PlayerController, host: Node, skel: Skeleton3D,
		ref: Dictionary, tol: float, max_sec: float) -> bool:
	var budget := int(max_sec * 60.0)
	for i in budget:
		if not _alive(pc):
			return false
		if _arm_gap(skel, ref) < tol:
			return true
		await host.get_tree().physics_frame
	return false


static func _arm_ref(skel: Skeleton3D) -> Dictionary:
	var out := {}
	for b in ARM_BONES:
		var bi := skel.find_bone(b)
		if bi >= 0:
			out[b] = skel.get_bone_pose_rotation(bi)
	return out


static func _arm_gap(skel: Skeleton3D, ref: Dictionary) -> float:
	var mx := 0.0
	for b: String in ref:
		var bi := skel.find_bone(b)
		if bi < 0:
			continue
		mx = maxf(mx, _q_angle_deg(skel.get_bone_pose_rotation(bi), ref[b] as Quaternion))
	return mx


## ★★ 夹角量具 = `4·asin(‖a−b‖/2)`（N56 三量具对拍定版）。
## ⛔ 不用 `Quaternion.angle_to()`（= `2·acos(|dot|)`）：它在近单位元处把误差**开平方**
##   ⇒ 会把"逐分量只差 1e-8"的两个姿态印成 0.0396°，本套件 `drift < 0.01` 那条会**假红**。
## ⛔ 也不用 `2·asin(max|Δc|)`：只在起止同轴时精确，最坏低估到 θ/√2。
static func _q_angle_deg(a: Quaternion, b: Quaternion) -> float:
	var q := b
	if a.dot(b) < 0.0:
		q = -b
	return rad_to_deg(4.0 * asin(clampf((a - q).length() * 0.5, 0.0, 1.0)))
