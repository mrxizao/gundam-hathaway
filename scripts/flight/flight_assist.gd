class_name FlightAssist
extends RefCounted
## 2026-10-14: ground is rescued immediately before movement/death by PlayerController.
## Historical pure helpers below remain for compatibility; live pitch warnings are disabled.
## 辅助飞行系统（1.2）：帮玩家**调朝向 / 保持索敌距离 / 规避障碍物**。
##
## # 最重要的一条设计约束（用户原话）
##
## > "玩家可以在辅助飞行系统的过程中也能操控机体的上下左右"
##
## 所以辅助**只做一件事：把修正量加到玩家的操纵量上**，绝不接管、绝不覆盖。
## `_read_flight_input()` 先读玩家的输入，辅助再叠一层，最后一起 clamp 到 ±1。
## 后果是玩家随时能把机头掰回去 —— 辅助只是"托一把"，
## 而不是"你按不动了"。这也让它天然不会和"鼠标只做准星"那条冲突。
##
## 三件事各自的机制：
##   1. **朝向**：把"目标相对机头的方向"分解到本机的 (上, 右) 两个轴上，
##      得到俯仰/滚转误差，按增益给一个**受限**的修正（`CAP`）——
##      受限是为了"玩家一推杆就能盖过它"。
##   2. **索敌距离**：以 `preferred` 为中心的**容差带**，太近减油门、太远加油门。
##      只动 `throttle` 的偏置，不动速度矢量（那是机动，不该自动化）。
##   3. **规避障碍**：机头前向 + 下方各一条射线，算"还有多久撞上"，
##      低于 `AVOID_TIME` 就追加抬头 —— 同样是**追加**，玩家的俯冲仍然有效。
##
## 纯函数核心（`correction_for`）与射线是分开的：前者可以脱离场景单测，
## 后者只是"把世界问一遍再喂给它"。

## 修正量上限（输入量单位）。0.55 的意思是：辅助最多出到"半杆多一点"，
## 玩家满杆（±1.0）永远盖得过它。
const CAP := 0.55
## 朝向修正增益（误差 → 输入量）。
const AIM_GAIN := 1.35
## 索敌距离的容差带（比例）。太近 = 低于 `preferred * NEAR`，太远 = 高于 `preferred * FAR`。
const NEAR := 0.75
const FAR := 1.30
## 距离修正的油门偏置上限。
const THROTTLE_CAP := 0.45
## 多久之内会撞上就抬杆（秒）。
const AVOID_TIME := 1.8
## **地面**探头的视界（秒）——刻意比"前方障碍"更长。
## 撞山还有机会拉起来，撞地没有；而俯冲时的高度损失是指数级的，
## 1.8 s 的视界在 800 m/s 下只提前 1.4 km，来不及改出。
const GROUND_TIME := 2.8
## 规避时最多追加的抬杆量。
const AVOID_PITCH := 0.85
## ---- 松手改出（第十四轮追加，老板两次澄清后的最终口径）----
##
## 老板原话：
##   ① "如果玩家手动撞地是可以的，但是辅助模式就是要有防撞地。"
##   ② "玩家在辅助模式下主动冲向地面哪怕离地面只有 10 m，**只要玩家松手就要立刻抬升海拔**。"
##
## 所以触发条件是**输入**，不是高度 —— 这一点是关键，第一版做错过：
##
## | 时机 | 正确行为 |
## |---|---|
## | 玩家**还在压杆**俯冲 | **一点都不干预**，允许他一路冲到贴地（这是他的自由） |
## | 玩家**一松手**（且探头看到地面、且当前不是在爬升） | **立刻**满抬头，不看高度、不等倒计时 |
## | 已经接管 | 一直拉到"在爬升 **且** 飞出探头视界"才交还（否则会在贴地高度反复拉/松） |
##
## ⚠️ 因此旧的 `HARD_AVOID_TIME`（"进入危险高度就夺杆"）是**错的**：它会在玩家
## 主动俯冲时把杆抢走。已删除，换成下面这条。
##
## ⚠️ 物理边界（必须说清楚，不能假装是保证）：松手后"立刻抬头"是保证的，
## 但"一定拉得出来"不是 —— 600 m/s 垂直下坠时满杆拉升的转弯半径就有几百米。
## 而且本作 `FlightBody.CRASH_ALTITUDE` = 24 m 就直接判坠毁，所以老板说的
## "10 m" 在代码里其实已经低于死亡线了：能救的最矮高度就是 24 m 上下。
##
## ---- ⚠️ 2026-09-21 收紧了触发（老板："辅助飞行很容易抢控制权。飞到一半就是自动改出"）----
##
## 上面那条口径有两个洞，合起来就是"**飞到一半也夺杆**"：
##   ① `vertical_speed < CLIMB_EPS` 这个条件太松 —— **平飞**（下坠 ≈ 0）也满足；
##   ② 地面探头的视界是 `speed * GROUND_TIME`（800 m/s → **2.24 km**），
##      于是"中低空 + 松手"几乎必然看到地面。
## 两条一凑：**在中低空平飞时松开俯仰，系统立刻夺杆**。那不是防撞地，那是抢杆。
##
## 现在的口径（三句话）：
##   1. **必须真的在下坠**（`vertical_speed < -DIVE_SINK`）—— 平飞、微降、爬升一律不碰；
##   2. **松手要维持 `RELEASE_GRACE`** 才算"松手"—— 点一下杆、抖一下手不算；
##   3. 仍然**压着杆一点不干预**（主动撞地是玩家的自由），接管后仍然拉到"在爬升且飞出探头"。
const RELEASE_PULL_TIME := 2.8
## 认作"松手"的俯仰输入阈值。
const RELEASE_INPUT_EPS := 0.05
## 已经在以这个速率爬升就不用拉（m/s）。
const CLIMB_EPS := 1.0
## **算"俯冲"的下坠率**（m/s，正数写、按下降量比较）。
##
## 40 m/s 在 800 m/s 的巡航速度下约等于 2.9° 的下滑角 —— 再小的下坠在画面里看不出姿态变化，
## 那是"平飞时高度慢慢掉"，不是俯冲。**这一条就是"飞到一半不再夺杆"的开关**：
## 调大 = 更少干预（更靠近"只有真俯冲才救"），调到 0 = 退回旧行为（平飞也夺）。
const DIVE_SINK := 40.0
## **松手的宽限期**（秒）：俯仰必须持续松开这么久才认。
## 没有它的话"推一下杆再松手"的那一帧就会触发接管 —— 玩家会觉得是按键/系统在抢他。
const RELEASE_GRACE := 0.25

## ---- 地形告警（★ 63-15 · **只提醒，不改出**）----
##
## 它与上面「松手改出」的分工，一句话：
##   · `needs_release_pull_up()` = **硬夺杆**，门是 `GROUND_GUARD_ALT = 50 m`，老板点名的绝对门；
##   · 本段 = **只报警**，在 50 m **之上**、按当前垂速已经快撑不住时，提前给一条提示。
##
## ⚠️ **它不碰任何操纵**（`translate_dir` / `control_input` / `fm`）—— 这是刻意的，
##   不是没写完："高于 50 m 就别改出"这条口径因此**一字未破**。
##
## ⚠️ 门是"**还能撑几秒**"（`ground_dist / |垂速|`），**不是高度** —— 与 50 m 那条完全不同：
##   平飞时 `|垂速| → 0` ⇒ 门 → 0 ⇒ **一次都不报**。
##   否则平飞时告警一直响，玩家很快就会把它当背景音忽略掉。
##
## 2.5 s 的依据：满杆拉平要转过 33°，而平移模式重定速度矢量的时间常数
## `1 / TRANSLATE_RESPONSE 3.2` ≈ 0.31 s ⇒ 收敛约 3τ ≈ 0.94 s。留 2.5 s 是给**人**
## 而不是给伺服：从听到到手动拉杆大概要 1 s 上下。
const TERRAIN_WARN_TIME := 2.5
## **改出的高度门槛**（米，对地高度）：**只有低于这个值才允许接管**。
##
## 老板 2026-09-21：「防撞地的阈值改到 **50 m**。**高于这个值就别改出了**。」
##
## 它盖过前面所有条件：50 m 以上，松手再久、下坠再快、探头看得见地面，都不接管 ——
## 那些情况现在归**玩家自己**（他松手了，但还没到要命的高度）。
## 50 m 以下才轮到系统。
##
## ⚠️ 必须说清的物理边界（不是推脱，是免得被当成 bug）：`FlightBody.CRASH_ALTITUDE = 24 m`
## 直接判坠毁，而满杆拉升的转弯半径按**几百米**算 —— 所以 50 m 才开始拉，
## **救不救得回来取决于当时的速度与下坠率**。这条门要的是"只在真贴地时才动手"，
## 不承诺"一定拉得出来"。要"更早救"就得把 50 调大（老板的原话就是"高于这个值就别改出"，
## 所以这个数是他给的，不是我们猜的）。

##
## ---- ★ 63-15（2026-10-07）：这条边界**已拍板、不再追求拉起来** ----
##
## 上面只是"不承诺"；现在它有了**实测数字**，而且老板已拍板不动这个阈值：
##
##   · 50 m → 判死线 `CRASH_ALTITUDE = 24 m` 只剩 **26 m**；
##   · 平移模式**恒加力**（`_read_translate_input()` 里 `fm.boosting = true`），
##     而 E 键俯冲的实测角 = `atan(TRANSLATE_OFFSET 0.65)` = **33°**
##     ⇒ 垂速 ≈ 2268 × sin33° = **1235 m/s**；
##   · ⇒ 拉起窗 = 26 / 1235 = **0.021 s**（1.3 个物理帧）。
##
## **实测**（`tests/suite_ground_guard.gd` ⑥：加力极速、33° 俯冲、离地 4000 m 出发）：
##   `frames=194  min_y=28.6 m  vy=-1010.8 m/s  grounded=true`
##   —— 防撞地**确实接管了**（`_auto_pull_up = true`），但 194 帧后照样撞海。
##
## ⇒ **这不是 bug，是拍板后的工程边界。** 想拉起来只有一条路：
##   让"满抬头"发生在 50 m **之上** —— 而那恰恰就是"高于这个值别改出"。
##   两者只能选一个，老板选了**守阈值**；代价就是极速俯冲救不回来。
##   于是 50 m 之上只补一层**只报警、不改出**的地形告警（见 `terrain_warning()`）。
const GroundPolicy = preload("res://scripts/flight/ground_avoidance.gd")
const GROUND_GUARD_ALT := GroundPolicy.TRIGGER_HEIGHT
## 探地的射线方向（机头下方，稍微往前）。
const PROBE_DOWN := 0.55

## 俯仰已经连续松开了多久（秒，见 `RELEASE_GRACE`）。`update()` 维护。
var _released := 0.0


## 松手改出的**触发判定**。纯函数：不依赖场景，可以直接单测。
##
## 六个条件**全部**成立才拉：
##   1. 玩家没有在压杆（`abs(pitch_input) <= RELEASE_INPUT_EPS`）——
##      他还在压就说明这是他主动要下去的，**不干预**；
##   2. **松手已经维持了 `RELEASE_GRACE`**（`released_for`）—— 防"推一下杆再松"被当成松手；
##   3. **真的在下坠**（`vertical_speed < -DIVE_SINK`）—— 平飞/微降/爬升一律不碰
##      （2026-09-21 补的，"飞到一半被夺杆"就是漏了这一条）；
##   4. **对地高度低于 `GROUND_GUARD_ALT`（50 m）** —— 老板 2026-09-21 点名：
##      「防撞地的阈值改到 50 m。**高于这个值就别改出了**」；
##   5. 地面探头看得到地面（`ground_time < RELEASE_PULL_TIME`）；
##   6. 当前不是在爬升（`vertical_speed < CLIMB_EPS`）。
##
## ⚠️ 参数默认值都是"**最松的那一端**"（`released_for` = 很久、`altitude` = 贴地）：
## 老调用点（只传前三个参数）等价于"松手很久了、而且已经贴地"，
## 于是它们测的仍然是**几何与俯仰**那几条，而不管后加的两条门。
## 要测新门就显式传进来 —— `suite_round14` 里两组都各有一份。
static func needs_release_pull_up(pitch_input: float, ground_time: float,
		vertical_speed: float, released_for := 999.0, altitude := 0.0, guard_alt := GROUND_GUARD_ALT) -> bool:
	if absf(pitch_input) > RELEASE_INPUT_EPS:
		return false
	if released_for < RELEASE_GRACE:
		return false
	# ⚠️ 高度门放在**最前面**（在"有没有下坠"之前）：老板的口径是**绝对**的 ——
	# 高于 50 m 什么都不做，不管下坠多快。写成"先看下坠再看高度"会让人误以为
	# 高度只是若干条件之一，改起来也就更容易被顺手挪走。
	if altitude >= guard_alt:
		return false
	# 先判"有没有在下坠"，再判地面：反过来的话平飞时 `ground_time` 也小于窗口，
	# 于是又回到"平飞夺杆"那个坑。
	if vertical_speed > -DIVE_SINK:
		return false
	if ground_time >= RELEASE_PULL_TIME:
		return false
	return vertical_speed < CLIMB_EPS


## **地形告警的判定**（★ 63-15 · 纯函数）。
##
## 返回 true = 按现在这个垂速下去，`TERRAIN_WARN_TIME` 秒内会到地。
##
## ⚠️ 与 `needs_release_pull_up()` 的关键区别：**它不看高度、不看松手、也不会夺杆**。
##   它只回答一个问题："该提醒玩家了吗？"
static func terrain_warning(ground_dist: float, vertical_speed: float) -> bool:
	# 不在下坠（平飞 / 爬升 / 微降）⇒ 不报。这一条就是"别让告警变成背景音"的全部。
	if vertical_speed > -DIVE_SINK:
		return false
	# 探头打空（INF）或数据没到 ⇒ 不报。
	if not is_finite(ground_dist) or ground_dist <= 0.0:
		return false
	return ground_dist < TERRAIN_WARN_TIME * -vertical_speed

## 本帧算出来的修正（玩家输入叠加上去之前）。
var input := Vector3.ZERO          ## (pitch, yaw, roll)，与 `control_input` 同构
var throttle_bias := 0.0
## 最近一次的探头结果（HUD/调试可读）。
var obstacle_time := INF
## 距离地面还有多久（秒）；INF = 高得没事。地面是**否决式**兜底，见 correction_for。
var ground_time := INF
## **正下方到地面的距离**（米，AGL）；INF = 探头没打到地。
##
## 它和 `ground_time` 是**同一次射线**的两个说法（时间 = 距离 ÷ 速度），
## 所以这里不另打一条射线 —— "两条射线各自算"迟早会给出互相矛盾的两个高度。
##
## ⚠️ 改出用的高度门槛读**它**，不读 `player.global_position.y`：
## 峡谷 / 夜城那种地形里 y 会骗人（山脊上的机 y 很高、其实离地只有几十米），
## 而"防撞地"要的是**离地**多少。
var ground_dist := INF
## 是否已进入"松手改出"状态（第十四轮）。由 `PlayerController` 读取并执行 ——
## 这里只负责**判断**，"夺杆"这种会影响玩家体验的动作放在控制器里、和提示一起做。
var release_pull := false
## 地形告警（★ 63-15）：**只提醒、不改出** —— 上一帧 `update()` 算出来的。
## 接线在 `PlayerController._tick_terrain_warn()`（带边沿去重）。
var terrain_warn := false


## **纯函数核心**：给定几何关系算修正量。不碰场景、不读输入，可以直接单测。
##
## `dir_to_target` / `fwd` / `right` / `up` 都是单位向量；`dist` = 当前距离；
## `preferred` = 想保持的距离；`obstacle_time` = 障碍还有多久（INF = 没有障碍）。
static func correction_for(dir_to_target: Vector3, fwd: Vector3, right: Vector3, up: Vector3,
		dist: float, preferred: float, obstacle_time: float, ground_time := INF,
		player_pitching_down := false) -> Dictionary:
	var pitch := 0.0
	var roll := 0.0
	if dir_to_target.length_squared() > 0.0001:
		var d := dir_to_target.normalized()
		# 目标在我的上方 → 抬杆（正）；在右侧 → 向右滚转（正）去"压坡度"转弯
		pitch = clampf(d.dot(up) * AIM_GAIN, -CAP, CAP)
		roll = clampf(d.dot(right) * AIM_GAIN, -CAP, CAP)
	# 距离带：进带内不干预（留出让玩家自己飞的死区）
	var thr := 0.0
	if preferred > 1.0 and dist > 0.0:
		if dist < preferred * NEAR:
			thr = -THROTTLE_CAP
		elif dist > preferred * FAR:
			thr = THROTTLE_CAP
	# 规避：越近抬得越狠
	if obstacle_time < AVOID_TIME:
		var k := clampf(1.0 - obstacle_time / AVOID_TIME, 0.0, 1.0)
		pitch = clampf(pitch + AVOID_PITCH * k, -1.0, 1.0)
	# **地面硬兜底**（1.2 用户实测："偶尔会自己往地上撞"）。
	#
	# 根因：朝向修正会把机头指向目标 —— 目标在下方时那就是一条**俯冲指令**，
	# 而"规避"只是**加**一点抬杆，加不过俯冲的量。所以近地时必须改成**否决**：
	# 抬杆修正不允许为负（`maxf`），"帮忙"绝不能变成"往地里按"。
	#
	# ⚠️ 第十四轮补了一个前提 `not player_pitching_down`：这一条管的是
	# **辅助自己别把机头往地里按**，不是"阻止玩家俯冲"。玩家自己在压杆时
	# （老板口径："主动冲向地面是可以的"），辅助不该跟他抢 —— 否则玩家压杆
	# 得到的是一个被削掉的俯冲，而不是他要的俯冲。
	if ground_time < AVOID_TIME and not player_pitching_down:
		var kg := clampf(1.0 - ground_time / AVOID_TIME, 0.0, 1.0)
		pitch = maxf(pitch, AVOID_PITCH * kg)
	return {"pitch": pitch, "roll": roll, "throttle": thr}


## 每帧：问一遍世界（射线），再交给纯函数。
##
## `player_pitch` = 玩家本帧的俯仰输入（辅助叠加**之前**的值）。它只用来判断
## "玩家是不是正在主动压杆" —— 见 `correction_for` 的 `player_pitching_down`。
func update(player: Node3D, target: Node3D, preferred: float, _delta := 0.0,
		player_pitch := 0.0) -> void:
	if player == null or not is_instance_valid(player):
		input = Vector3.ZERO
		throttle_bias = 0.0
		release_pull = false
		_released = 0.0
		return
	var fwd := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	var up := player.global_transform.basis.y
	var dir := Vector3.ZERO
	var dist := 0.0
	if target != null and is_instance_valid(target):
		var to := target.global_position - player.global_position
		dist = to.length()
		dir = to / maxf(dist, 0.001)
	ground_dist = GroundPolicy.height(player)
	obstacle_time = _probe(player, fwd)
	ground_time = INF # Ground rescue is applied immediately before movement, not as a pitch warning.
	var vertical := 0.0
	var fm_ref = player.get("fm")
	if fm_ref is FlightModel:
		vertical = (fm_ref as FlightModel).velocity.y
	# 松手计时：压着杆就归零，否则累加 —— `_delta` 这个形参存在的唯一理由就是它。
	# （`RELEASE_GRACE` 那 0.25 s 宽限期靠这个累加器，见 `needs_release_pull_up`。）
	if absf(player_pitch) > RELEASE_INPUT_EPS:
		_released = 0.0
	else:
		_released += _delta
	# ⚠️ 传 `ground_dist`（**对地**高度，米）而不是 `player.global_position.y`：
	# 峡谷/夜城图里 y 会骗人，而 50 m 这条门槛说的是"离地 50 m"。见 `ground_dist`。
	release_pull = false
	terrain_warn = false
	var c := correction_for(dir, fwd, right, up, dist, preferred, obstacle_time, ground_time,
		player_pitch < -RELEASE_INPUT_EPS)
	input = Vector3(float(c["pitch"]), 0.0, float(c["roll"]))
	throttle_bias = float(c["throttle"])


## 前向 + 下方两条射线，取"最近的那次撞击"折算成时间。
## 层只打 WORLD：机体之间的碰撞不该触发规避（否则两机对冲会互相抬杆）。
func _probe(player: Node3D, fwd: Vector3) -> float:
	var space := player.get_world_3d().direct_space_state
	var speed := 220.0
	var fm_ref = player.get("fm")
	if fm_ref != null:
		speed = maxf(float(fm_ref.speed), 60.0)
	var best := INF
	# ⚠️ 这里的"下"必须用**世界** DOWN，不能用机体自己的 `up`：
	# 一压坡度/倒飞，`basis.y` 就接近水平，射线会朝侧面飞出去 ——
	# 平飞时看着有效、**侧倾时等于没有防触地**（用户实测"偶尔会自己往地上撞"）。
	for dir: Vector3 in [fwd, (fwd + Vector3.DOWN * PROBE_DOWN).normalized()]:
		var q := PhysicsRayQueryParameters3D.create(
			player.global_position, player.global_position + dir * (speed * AVOID_TIME * 1.2))
		q.collision_mask = 1          # WORLD_LAYER
		q.exclude = GroundPolicy.excluded_ground(player)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var at: Vector3 = hit.get("position", player.global_position)
		best = minf(best, player.global_position.distance_to(at) / speed)
	return best
## 只探**正下方**的那条射线（视界比前向探头短：它管的是"别撞地"，不是"别撞山"）。
func _probe_down(player: Node3D, up: Vector3) -> float:
	var space := player.get_world_3d().direct_space_state
	var speed := 220.0
	var fm_ref = player.get("fm")
	if fm_ref != null:
		speed = maxf(float(fm_ref.speed), 60.0)
	var q := PhysicsRayQueryParameters3D.create(
		player.global_position, player.global_position + Vector3.DOWN * (speed * GROUND_TIME))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		ground_dist = INF
		return INF
	var at: Vector3 = hit.get("position", player.global_position)
	ground_dist = player.global_position.distance_to(at)
	return ground_dist / speed
