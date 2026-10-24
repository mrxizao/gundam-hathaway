class_name SuiteCameraFeedback
extends RefCounted
## **镜头反馈：受击与发射**（1.2.1 · DESIGN §4.9 / §4.10）。
##
## ## 两项各自缺什么（都不是"通道不存在"，而是"没有反馈设计"）
##
## **受击**：原来只有 `main._on_player_damaged()` 里一行 `chase.add_shake(0.5)`——
## 三个已经递到手上的参数（`amount` / `source` / `type`）**全被丢掉**
##（形参前的下划线就是"我故意没读它"）。后果：
##   ① 机炮蹭一下和相杀级重击**体感一样重**（幅度是常数）；
##   ② 玩家分不出被打的是哪一侧（只有随机抖，没有方向）；
##   ③ 近炸和光束用同一种抖（`Damage.Type` 已经传进来了）；
##   ④ **I 立场吃掉的命中完全不抖**（`_apply_damage` 在 `to_hull <= 0` 时提前 return，不发 `damaged`）。
##
## **发射**：原来只有 `camera.add_shake(0.18)` 一行、每次扳机一次，而
##   ① 三发是同一帧出去的，抖一次与"打了几发"无关；
##   ② **全弹发射那条路一处 `add_shake` 都没有**（100 发是场上最大的动作，镜头却不动）。
##
## ## 这个套件把"手感"翻译成可断言的东西
##
## 力度 / 方向 / 节流 / 设置兼容全部用**状态量**断言（`_kick` / `_kick_dir` / `_shake`），
## 不靠看截图、也不靠位置（`_physics_process` 每帧都在把相机拉向目标机位，
## 位置里混着跟随运动，拿它做断言等于测了个噪声）。
##
## ⚠️ 最要紧的一条是"**AI 发弹不抖玩家**"：`fire_funnel()` 是玩家与 AI **共用**的，
## 写错的话玩家会被敌机的导弹震镜头 —— 那是"玩两分钟就会骂"的那种 bug。

const HIT := "CameraFeedback / 受击：幅度 / 方向 / 类型 / 节流"
const SETTINGS := "CameraFeedback / 受击不与「降低动态 / 关闭抖动」打架"
const LAUNCH := "CameraFeedback / 发射：按发数累加 + 节流"
const AI := "CameraFeedback / AI 发弹不抖玩家（最关键的一条）"
const VISIBLE := "CameraFeedback / 肉眼可见性（画面到底动没动）"
const SHIELD := "CameraFeedback / I 立场挨打不是零反馈（§4.9.2⑤）"
const FRAMING := "CameraFeedback / 构图：自机留框 + 加权合成 + 提前量封顶（§四）"


static func run(t: T, host: Node) -> void:
	# 相机要**进树**（见 `_fresh()`），所以先把挂载点记下来。
	_host = host
	_spawned = []
	t.suite("CameraFeedback / propulsion transitions and high-speed framing")
	_propulsion(t, host)
	t.suite(HIT)
	_hit(t)
	t.suite(SETTINGS)
	_settings(t)
	t.suite(LAUNCH)
	_launch(t)
	t.suite(AI)
	await _ai(t, host)
	t.suite(VISIBLE)
	_visible(t)
	t.suite(SHIELD)
	await _shield(t, host)
	t.suite(FRAMING)
	_framing(t, host)
	# 回收：留着的话下一轮 `Game.reset()` 之后还会挂着一堆没主人的相机与哑目标。
	for n: Node in _spawned:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			n.queue_free()
	_spawned = []
	_host = null


# ---------------------------------------------------------------- 工具

## 场景树（`run()` 注入）。相机**必须进树**才对。
static var _host: Node = null
## 本套件造出来的临时节点，`run()` 末尾统一回收。
static var _spawned: Array[Node] = []


## 一台**受控**的相机 + 一个哑目标。
##
## 两个约束缺一不可（第一版只做对了一半）：
##   ① **必须进树**：不进树时 Godot 每次读 `global_transform` 都报
##      `Condition "!is_inside_tree()" is true. Returning: Transform3D()`，
##      而且拿到的是单位阵 —— 方向断言会变成在测"恒等变换"。实测一轮刷了 2358 条 ERROR。
##   ② **必须手动关掉引擎驱动的 `_physics_process`**：进树之后引擎会自己按物理帧调它，
##      测试就再也控制不了"跑了几帧"，节流与衰减全都不可复现。
##      （断言里显式调 `cam._physics_process(dt)`，帧数完全由测试决定。）
## `basis` 摆正（单位阵）也是刻意的：方向断言只有在这个基准下才有确定含义。
static func _fresh() -> Dictionary:
	var tgt := Node3D.new()
	var cam := ChaseCamera.new()
	_host.add_child(tgt)
	_host.add_child(cam)
	cam.set_physics_process(false)   # ① 见上
	cam.current = false              # 别跟真镜头抢"当前相机"（`_ready()` 会把它设成 true）
	cam.set_target(tgt)
	cam.global_transform = Transform3D(Basis(), Vector3.ZERO)
	_spawned.append(tgt)
	_spawned.append(cam)
	return {"cam": cam, "tgt": tgt}


# ---------------------------------------------------------------- 1 受击

static func _hit(t: T) -> void:
	# ---- 幅度有梯度（不再是一个常数 0.5）----
	var a: ChaseCamera = _fresh()["cam"]
	a.add_hit_shake(0.05, Vector3.RIGHT, Damage.Type.BEAM)
	var small := a._kick
	var b: ChaseCamera = _fresh()["cam"]
	b.add_hit_shake(0.30, Vector3.RIGHT, Damage.Type.BEAM)
	var big := b._kick
	t.gt(small, 0.0, "小伤害也产生推拒（不是被四舍五入掉）")
	t.gt(big, small, "伤害占比大 ⇒ 推拒更重（%.3f → %.3f，原来恒为同一个数）" % [small, big])

	# ---- 上限 ----
	var c: ChaseCamera = _fresh()["cam"]
	c.add_hit_shake(10.0, Vector3.RIGHT, Damage.Type.RAM)
	t.ok(c._kick <= ChaseCamera.KICK_MAX + 0.0001,
		"单次推拒受 `KICK_MAX` 限制（一发放倒也不会把镜头甩飞）")

	# ---- 方向：相机被推向**背离来源**＝冲击传播方向 ----
	#
	# 从正上方打来 ⇒ 冲击方向朝下 ⇒ 相机被向下推。
	# （我第一次把方向写反了：朝来源推会变成"挨打时往对手怀里飞"，这里钉死。）
	var d: ChaseCamera = _fresh()["cam"]
	d.add_hit_shake(0.4, Vector3.DOWN, Damage.Type.BEAM)
	t.lt(d._kick_dir.y, -0.5, "从**正上方**打来 ⇒ 推拒方向朝**下**（背离来源）")
	t.near(d._kick_dir.length(), 1.0, 0.01, "推拒方向是单位向量")

	var e: ChaseCamera = _fresh()["cam"]
	e.add_hit_shake(0.4, Vector3.RIGHT, Damage.Type.RAM)
	t.gt(e._kick_dir.x, 0.5, "从**左方**打来（冲击朝右）⇒ 推拒方向朝右")

	# ---- 局部坐标：相机自己滚转时，方向不能跟着飘 ----
	#
	# ⚠️ 存的是**局部**方向，要还原成世界方向就得乘回 basis。
	# 第一版写的是 `_kick_dir.dot(basis.x)` —— 拿局部向量的分量去点乘一个**世界**向量，
	# 两个坐标系混着用；它当时"通过"只是因为相机没进场景树、`global_transform` 读出来
	# 恒为单位阵，**两端一起错正好抵消**。相机一进树就露馅了（实测 -1.0000 而不是 1.0）。
	var f: ChaseCamera = _fresh()["cam"]
	f.global_transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90.0)), Vector3.ZERO)
	f.add_hit_shake(0.4, Vector3.RIGHT, Damage.Type.RAM)
	t.near((f.global_transform.basis * f._kick_dir).dot(Vector3.RIGHT), 1.0, 0.05,
		"推拒方向按**相机局部坐标**存（相机已滚 90°，还原回世界仍指原来那一侧）")

	# 施加端也必须走同一个坐标系：存局部、却按世界去加，位移会落在一个错的侧面上。
	# 这里直接调 `_apply_kick()`（不走 `_physics_process`，免得混进跟随运动）。
	var kick_before := f.global_position
	f._apply_kick(0.0001)
	var kick_move := f.global_position - kick_before
	t.gt(kick_move.dot(Vector3.RIGHT), 0.0,
		"`_apply_kick()` 的位移落在**还原后的世界方向**上")

	# ---- 类型：近炸不给方向，把幅度并进随机抖 ----
	var g: ChaseCamera = _fresh()["cam"]
	g.add_hit_shake(0.4, Vector3.DOWN, Damage.Type.FUNNEL)
	t.eq(g._kick_dir, Vector3.ZERO, "近炸（FUNNEL）**不给方向** —— 爆炸是全向的，给方向等于撒谎")
	t.near(g._kick, 0.0, 0.0001, "近炸不产生定向推拒")
	t.gt(g._shake, 0.0, "近炸把幅度并进**随机抖**（没有白算掉这块量）")

	# 机炮的随机幅度要比撞机小（连发武器抖大了会晕）
	var h: ChaseCamera = _fresh()["cam"]
	h.add_hit_shake(0.4, Vector3.RIGHT, Damage.Type.VULCAN)
	var i2: ChaseCamera = _fresh()["cam"]
	i2.add_hit_shake(0.4, Vector3.RIGHT, Damage.Type.RAM)
	t.lt(h._shake, i2._shake, "机炮的随机抖**小于**撞机（连发武器要收敛）")

	# ---- 节流：机炮连发不能每发都推一次 ----
	var j: ChaseCamera = _fresh()["cam"]
	var impulses := 0
	for k in 25:                      # 0.5 s，每 0.02 s 一次命中
		j._physics_process(0.02)
		if j._hit_cd <= 0.0:
			impulses += 1
		j.add_hit_shake(0.05, Vector3.RIGHT, Damage.Type.VULCAN)
	t.lt(float(impulses), 5.0, "0.5 s 内 25 次机炮命中 ⇒ **新冲量 ≤ 4**（节流生效）")
	t.ok(j._kick <= ChaseCamera.KICK_MAX + 0.0001, "...而且总幅度始终受限")

	# 反证：节流不是"永久哑掉" —— 间隔够长时每次都算新冲量
	var m2: ChaseCamera = _fresh()["cam"]
	var impulses2 := 0
	for k in 5:
		m2._physics_process(0.5)      # 0.5 s ≫ HIT_SHAKE_MIN_INTERVAL
		if m2._hit_cd <= 0.0:
			impulses2 += 1
		m2.add_hit_shake(0.05, Vector3.RIGHT, Damage.Type.BEAM)
	t.eq(impulses2, 5, "间隔够长时每次命中都是新冲量（不是冷却没到就永远哑了）")


# ---------------------------------------------------------------- 2 设置兼容

static func _settings(t: T) -> void:
	# "镜头抖动=关" / "降低动态" 都通过 `shake_scale = 0` 表达。
	#
	# ⚠️ 关键不是"位移为 0"（那本来就是 0），而是**衰减照走**：
	# 只把位移乘 0 而让 `_kick` 停在满值，玩家把抖动从关调成标准的那一瞬间
	# 会立刻吃到一次满幅推拒 —— `_apply_shake()` 的注释点名过同一个坑。
	var cam: ChaseCamera = _fresh()["cam"]
	cam.shake_scale = 0.0
	cam.add_hit_shake(0.6, Vector3.DOWN, Damage.Type.RAM)
	t.gt(cam._kick, 0.0, "倍率 0 时推拒仍被记录（不是直接丢掉）")
	# ⚠️ 帧数**不能写死**：`add_hit_shake(0.6, RAM)` 现在会顶到 `KICK_MAX`（3.5），
	# 而衰减是 1.6/s。原来写死 40 帧（= 3.2 的衰减量）在 `KICK_MAX` 是 2.55 时刚好够、
	# 涨到 3.5 之后就不够了（实测残留 0.30 ⇒ 这条假红）。按常量算帧数。
	var frames := int(ceil(ChaseCamera.KICK_MAX / (ChaseCamera.KICK_DECAY * 0.05))) + 5
	for i in frames:
		cam._physics_process(0.05)
	t.near(cam._kick, 0.0, 0.0001, "倍率 0 时推拒**照常衰减到 0**（%d 帧）" % frames)
	t.near(cam._shake, 0.0, 0.0001, "随机抖同样衰减到 0")

	cam.shake_scale = 1.0
	t.near(cam._kick, 0.0, 0.0001,
		"把倍率调回标准：`_kick` 仍是 0 —— **不会突然吃到一次满幅推拒**")

	# 发射通道同样遵守（它是同一个 `_shake`）
	var c2: ChaseCamera = _fresh()["cam"]
	c2.shake_scale = 0.0
	c2.add_launch_shake(ChaseCamera.LAUNCH_KICK_FUNNEL)
	c2._physics_process(0.05)
	c2._physics_process(0.5)
	t.near(c2._shake, 0.0, 0.0001, "倍率 0 时发射抖动也衰减到 0")


# ---------------------------------------------------------------- 3 发射

static func _launch(t: T) -> void:
	# ---- 按"每一发离架"累加，而不是"每次扳机一次" ----
	var a: ChaseCamera = _fresh()["cam"]
	for i in 3:
		a.add_launch_shake(ChaseCamera.LAUNCH_KICK_FUNNEL)
	t.near(a._launch_pending, 3.0 * ChaseCamera.LAUNCH_KICK_FUNNEL, 0.0001,
		"3 发同帧 ⇒ 后坐量**按发数累加**（不能被节流折成一次）")
	a._physics_process(0.02)
	t.near(a._launch_pending, 0.0, 0.0001, "下一帧落账（pending 清零）")
	# ⚠️ 阈值**不写死**，跟着常量走：3 发 = `LAUNCH_KICK_FUNNEL × 3`，
	# 而本帧还会扣掉 `2.4 × delta` 的衰减（0.02 s ⇒ 0.048）。
	# 这个常量在 2026-09-21 第二次返工里从 0.08 降到 0.05（为了让"打 3 发"
	# 明显轻于"打 100 发"），写死的阈值会跟着常量一起悄悄失真。
	var want_landed := 3.0 * ChaseCamera.LAUNCH_KICK_FUNNEL - 2.4 * 0.02
	t.gt(a._shake, want_landed - 0.01,
		"落进 `_shake`（3 发 = %.3f，扣掉本帧衰减后应约 %.3f；实测 %.3f）"
			% [3.0 * ChaseCamera.LAUNCH_KICK_FUNNEL, want_landed, a._shake])

	# ---- 节流：成批发射要把爆发摊平 ----
	var b: ChaseCamera = _fresh()["cam"]
	var flushes := 0
	var frames := 30
	for i in frames:
		for j in 5:                   # 每帧 5 发（模拟 FULL_SALVO_PER_TICK 的爆发）
			b.add_launch_shake(ChaseCamera.LAUNCH_KICK_SALVO)
		if b._launch_pending > 0.0 and b._launch_cd <= 0.0:
			flushes += 1
		b._physics_process(1.0 / 60.0)
	t.lt(float(flushes), float(frames),
		"成批发射（每帧 5 发）⇒ 落账次数 %d < %d 帧（节流把爆发摊平了）" % [flushes, frames])
	t.lt(float(flushes), 100.0, "...而且远小于「每发都推一次」的次数")

	# ---- 100 发齐射：要有后坐，但**不许**饱和 ----
	#
	# ⚠️ 这一节的判据原本是错的（`t.gt(peak, 1.0)` 写在"不该到 1.0"的标题下面），
	# 但更根本的问题是**当时的实现压根抖不起来**：`LAUNCH_KICK_SALVO` 曾经是 0.02，
	# 而 `_apply_shake()` 的衰减是**线性**的 2.4/s ⇒ 20 发/秒 的输入（0.4/s）
	# 被整根吃掉，实测峰值**恒为 0.000** —— 功能等于没做（设计稿里那个数没算过账）。
	# 常量已经按这个算术改成 0.14，并另加 `LAUNCH_SHAKE_CEIL` 封顶（见两处注释）。
	var c: ChaseCamera = _fresh()["cam"]
	var peak := 0.0
	for i in 100:
		c.add_launch_shake(ChaseCamera.LAUNCH_KICK_SALVO)
		c._physics_process(0.05)      # 20 发/秒，与真实全弹发射同频
		peak = maxf(peak, c._shake)
	# ⚠️ 这个阈值量的是**帧末值**（`_apply_shake()` 已经把本帧的衰减扣掉了），
	# 所以它比 `LAUNCH_SHAKE_CEIL` 低一档：稳态时"顶到上限 0.30 → 扣 0.12 → 0.18"。
	# 写死 0.2 就会假红（0.18 ⇒ 差一点点）。判据的本意只是"**不是 0**"（对照 0.02 那版恒为 0.000），
	# 所以给到 0.1 就够，且不会随上限微调而反复失效。
	t.gt(peak, 0.1, "...确实在抖（帧末峰值 %.3f）—— 0.02 那一版这里恒为 0.000" % peak)
	t.lt(peak, ChaseCamera.LAUNCH_SHAKE_CEIL + 0.0001,
		"...但被 `LAUNCH_SHAKE_CEIL` 封住（峰值 %.3f ≤ %.2f）"
			% [peak, ChaseCamera.LAUNCH_SHAKE_CEIL])
	t.lt(peak, 1.0, "...远低于击坠级饱和 —— 1.0 以上读成「镜头在抽筋」")

	# ---- 两种抖动的可分辨性：发射**不带方向** ----
	var d: ChaseCamera = _fresh()["cam"]
	d.add_hit_shake(0.3, Vector3.DOWN, Damage.Type.RAM)   # 先来一次受击（有方向）
	var dk := d._kick_dir
	d.add_launch_shake(ChaseCamera.LAUNCH_KICK_FUNNEL * 10.0)
	d._physics_process(0.05)
	t.eq(d._kick_dir, dk, "发射**不会改动**推拒方向 —— 「刚开火」和「刚挨打」必须能一眼分辨")


# ---------------------------------------------------------------- 3.5 肉眼可见性

## **这一节是 1.2.1 返工的直接产物，存在的理由比前面四节加起来还硬。**
##
## 第一版的四个套件**全绿**，但玩家实测反馈是"抖了，但感受不出来"。
## 原因：那些断言问的都是**状态量**（`_shake > 0` / `_kick_dir.x > 0.5`），
## 而当时的实现把幅度算成了
##
##     一发步枪 7 / 217 ≈ 0.032 占比 × 3.2 米 = 0.10 米平移，
##     相机在 54 米外、68° 视场 ⇒ 半屏 36 米 ⇒ **0.3% 画面位移，1080p 上不到 0.5 像素**。
##
## 状态量全都"大于 0"，画面却一点没动 —— **断言选错了对象**。
## 所以这里改成直接量"**画面真的转了多少度**"：把相机摆在它自己的稳态机位上
## （`_desired_position()` / `_desired_basis()`，这样跟随运动恒为 0，混不进来），
## 然后跑真物理帧，量镜头前向相对稳态的**最大偏离角**。
##
## 角度是唯一和距离无关的量：相机转 θ 度，画面就转 θ 度，
## 不管自机在画面里占多大。这也是为什么施加端必须走旋转（见 `SHAKE_DEG_PER_UNIT`）。

## 肉眼能读出"挨了一下"的转角下限（度）。
##
## 这不是人眼分辨率的极限（那要低两个量级），而是"能不能被读成一次反馈"的门槛：
## 0.20° 在 1080p 上约是画面中心 4 像素的位移，低于这个量级只会被当成噪声。
const VISIBLE_DEG := 0.20
## 单次受击的转角上限（度）。超过就要怀疑又踩了"每帧按当前值累加"那个坑
##（见 `_apply_kick()` 的注释：那样会滚出近 20°，镜头像被拧住）。
const SANE_DEG := 12.0


## 把相机**摆到它自己的稳态机位**。
##
## 为什么必须这么做：直接 `_fresh()` 出来的相机 pose 与 `_desired_*()` 不一致，
## 于是每一帧都有跟随运动，量出来的转角里混着"相机在往稳态赶路"那一大坨，
## 抖动那点量会被彻底淹没。对齐之后跟随项恒为 0，残余转角**只可能**来自抖动通道。
static func _aligned() -> Dictionary:
	var h := _fresh()
	var cam: ChaseCamera = h["cam"]
	cam.global_position = cam._desired_position()
	cam.global_transform = Transform3D(cam._desired_basis(), cam.global_position)
	return h


## 跑 `frames` 个物理帧，返回镜头前向相对稳态基准的最大 / 平均偏离角（度）。
##
## 量的是**偏离角**而不是"每帧增量"：抖动是每帧重新随机的，逐帧增量会被
## "上一帧还没被 slerp 拉回去"这件事搅乱（第一版在踏板套件上就栽过一次），
## 而偏离角是单调可比的量。
static func _excursion(cam: ChaseCamera, frames: int, dt: float) -> Dictionary:
	# ⚠️ 括号不能省：`-a.b.c.angle_to(ref)` 会被解析成 `-(a.b.c.angle_to(ref))`
	#（成员访问与方法调用比一元负号结合得紧），那样算出来是个负的**标量**，
	# 下面 `angle_to` 就接不上了。
	var ref := -cam.global_transform.basis.z
	var mx := 0.0
	var sum := 0.0
	for i in frames:
		cam._physics_process(dt)
		var ang := rad_to_deg((-cam.global_transform.basis.z).angle_to(ref))
		mx = maxf(mx, ang)
		sum += ang
	return {"max": mx, "mean": sum / float(frames)}


static func _visible(t: T) -> void:
	# ⚠️ **必须先固定随机源**。抖动是每帧 `randf_range` 出来的，于是
	# "军刀比步枪重"这类断言其实是在比较**两个随机变量** ——
	# 不定种子的话它会随机翻绿翻红（实测同一份代码连跑两次：
	# saber 0.886° 与 1.222°，一次挂一次过）。定种子之后每次同值，调参才有意义。
	seed(20260921)

	# ---- 一发光束步枪（用**真实**比值 7 / 217，不是随手编的数）----
	var rifle: ChaseCamera = _aligned()["cam"]
	rifle.add_hit_shake(7.0 / 217.0, Vector3.RIGHT, Damage.Type.BEAM)
	var mr := _excursion(rifle, 30, 1.0 / 20.0)
	t.gt(mr["max"], VISIBLE_DEG,
		"一发光束步枪（7/217）⇒ 画面峰值转角 %.3f° > %.2f°（**肉眼阈值**）"
			% [mr["max"], VISIBLE_DEG])
	t.gt(mr["mean"], VISIBLE_DEG * 0.35,
		"...而且不是一帧的偶然尖峰（平均 %.3f°）" % mr["mean"])

	# ---- 护盾期挨打：必须"看得见"但"明显轻于掉血期"（§4.9.2⑤）----
	#
	# ⚠️ 两条边都要钉：只钉上界的话，把倍率调小到看不见照样绿 ——
	# 那就是 §4.9.4 那个"参数在动、画面不动"的坑。倍率 0.45 实测 0.322°，
	# 倍率 0.20 实测 0.177°（已在阈值之下），所以下界用掉血期的 35% 卡住。
	var sh: ChaseCamera = _aligned()["cam"]
	sh.add_hit_shake(ChaseCamera.shield_hit_ratio(7.0, 467.0), Vector3.RIGHT,
		Damage.Type.BEAM)
	var msh := _excursion(sh, 30, 1.0 / 20.0)
	t.gt(msh["max"], VISIBLE_DEG,
		"护盾期挨一发光束（柯西 467 池）⇒ 峰值 %.3f° > %.2f°（**肉眼阈值**）"
			% [msh["max"], VISIBLE_DEG])
	t.lt(msh["max"], mr["max"],
		"...但明显轻于掉血期的同一发（%.3f° < %.3f°）—— 护盾期挨打的节奏长得多"
			% [msh["max"], mr["max"]])
	t.gt(msh["max"], mr["max"] * 0.35,
		"...也没轻到看不见（%.3f° > 掉血期的 35%% = %.3f°）—— 倍率别再往下调"
			% [msh["max"], mr["max"] * 0.35])

	# ---- 军刀必须明显重于步枪（梯度是"反馈"的全部意义）----
	var saber: ChaseCamera = _aligned()["cam"]
	saber.add_hit_shake(22.0 / 217.0, Vector3.RIGHT, Damage.Type.SABER)
	var ms := _excursion(saber, 30, 1.0 / 20.0)
	t.gt(ms["max"], mr["max"] * 1.4,
		"军刀（22/217）比步枪重得多：%.3f° vs %.3f°" % [ms["max"], mr["max"]])

	# ---- 撞机：最重，但**不许**失控 ----
	var ram: ChaseCamera = _aligned()["cam"]
	ram.add_hit_shake(0.15, Vector3.RIGHT, Damage.Type.RAM)
	var mram := _excursion(ram, 30, 1.0 / 20.0)
	t.gt(mram["max"], ms["max"], "撞机又重于军刀：%.3f°" % mram["max"])
	t.lt(mram["max"], SANE_DEG,
		"...但最重的一档也远低于失控线 %.0f°（撞机 %.3f°）" % [SANE_DEG, mram["max"]])

	# ---- 反证：倍数必须真的起作用（否则上面三条只是在测"有抖动"）----
	var off: ChaseCamera = _aligned()["cam"]
	off.shake_scale = 0.0
	off.add_hit_shake(0.15, Vector3.RIGHT, Damage.Type.RAM)
	var moff := _excursion(off, 30, 1.0 / 20.0)
	t.near(moff["max"], 0.0, 0.0001, "倍率 0 ⇒ 画面**一点都不动**（%.4f°）" % moff["max"])

	# ---- 平移通道单独也要在"看得见"的量级（不能只靠旋转撑场面）----
	#
	# 第一版就是只有平移、且只有 0.10 米 —— 峰值位移 0.36 米 ≈ 3 像素。
	# 现在一发步枪的记账值是 **0.542 米**（`HIT_KICK_M` 1.2 × sev 0.645 × 权重 0.7）。
	# ⚠️ **峰值位移 ≠ 记账值 × 某个常数**：`_kick` 线性衰减 ⇒ 脉冲长度 ∝ 幅度 ⇒
	# 倍数随幅度变（单位幅度 1/20 是 2.29，这一发只有 1.89）——
	# 见 `chase_camera.gd` 的 `HIT_KICK_M` 注释里那张实测表。
	# 本套件（1/20、含随机抖）实测峰值 **1.02 米**（下面那条断言会打出来）；
	# 探针隔离法（`_shake` 清零）跑同一发是 1.023 米；含随机抖时 5 个种子落在
	# 1.012 ~ 1.046 米 —— 抖动在这一发里的净分量很小（方向逐帧随机，会互相抵消）。
	# ⚠️ 真机是 **60 Hz**：同一记账值实为 **2.58 米**，比这里的 1/20 口径大 2.5 倍。
	var shift: ChaseCamera = _aligned()["cam"]
	var p0 := shift.global_position
	shift.add_hit_shake(7.0 / 217.0, Vector3.RIGHT, Damage.Type.BEAM)
	var peak_shift := 0.0
	for i in 30:
		shift._physics_process(1.0 / 20.0)
		peak_shift = maxf(peak_shift, (shift.global_position - p0).length())
	t.gt(peak_shift, 0.4,
		"平移通道的峰值位移 %.2f m 也在可见量级（不是第一版那种 0.10 m ≈ 0.5 像素）"
			% peak_shift)
	# ---- 发射齐射：**持续**的闷震也必须在阈值以上 ----
	#
	# 第一版 `LAUNCH_KICK_SALVO = 0.02` 时这里恒为 0.000°（见 `_launch()` 的注释）。
	var salvo: ChaseCamera = _aligned()["cam"]
	var sref := -salvo.global_transform.basis.z
	var peak_launch := 0.0
	for i in 100:
		salvo.add_launch_shake(ChaseCamera.LAUNCH_KICK_SALVO)
		salvo._physics_process(0.05)   # 20 发/秒，与真实全弹发射同频
		peak_launch = maxf(peak_launch,
			rad_to_deg((-salvo.global_transform.basis.z).angle_to(sref)))
	t.gt(peak_launch, VISIBLE_DEG,
		"全弹发射的持续闷震峰值 %.3f° > %.2f°（100 发是场上最大的动作）"
			% [peak_launch, VISIBLE_DEG])
	t.lt(peak_launch, mram["max"],
		"...但仍轻于一次撞机（%.3f° < %.3f°）—— 开火和挨打要能分辨"
			% [peak_launch, mram["max"]])
	print("[vis] 受击/发射的**画面转角**（度）：步枪 %.2f / 军刀 %.2f / 撞机 %.2f"
		% [mr["max"], ms["max"], mram["max"]])
	print("[vis] 全弹齐射 %.2f / 护盾期挨打 %.2f（阈值 %.2f）"
		% [peak_launch, msh["max"], VISIBLE_DEG])
	print("[vis] 一次步枪命中的平移峰值 %.2f m（阈值 %.2f）" % [peak_shift, VISIBLE_DEG])


# ---------------------------------------------------------------- 5 I 立场挨打


static func _shield(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := FlightBody.new()
	u.team = 1
	u.profile = SuitProfile.penelope()   # I 立场 240
	u.projectile_container = c
	c.add_child(u)
	u.global_position = Vector3(0, 3000, 0)
	u.fm.speed = 260.0
	u.fm.throttle = 0.78
	u.fm.align_velocity(u.forward())

	var shield_hits: Array = []
	var hull_hits: Array = []
	u.ifield_hit.connect(func(a: float, _s: Node3D, _d: int) -> void: shield_hits.append(a))
	u.damaged.connect(func(a: float, _s: Node3D, _d: int) -> void: hull_hits.append(a))

	# ---- 核心：护盾吃下的一发，不掉血但**必须有反馈** ----
	u.ifield_hp = u.ifield_max
	u.take_damage(10.0, null, Damage.Type.BEAM)
	t.eq(hull_hits.size(), 0, "护盾吃下的一发**不发** `damaged`（血没变，发了就是撒谎）")
	t.eq(shield_hits.size(), 1, "...但**发了** `ifield_hit`（改之前这里是一条都没有）")
	if shield_hits.size() > 0:
		t.near(float(shield_hits[0]), 10.0 / Damage.ifield_efficiency(Damage.Type.BEAM),
			0.001, "`absorbed` 报的是**护盾值的消耗量**（光束效率 1.00 ⇒ 10.0）")

	# ---- 破盾效率低的武器报出更大的数（这是"读得出被打的是什么"的全部意义）----
	u.ifield_hp = u.ifield_max
	shield_hits.clear()
	u.take_damage(10.0, null, Damage.Type.SABER)
	t.eq(shield_hits.size(), 1, "军刀那一发也发 `ifield_hit`")
	if shield_hits.size() > 0:
		t.gt(float(shield_hits[0]), 10.0,
			"同一发 10 点伤害，**军刀**报出的护盾消耗更大（%.1f > 10.0，破盾效率 0.45）"
				% float(shield_hits[0]))

	# ---- 零伤害不发（否则任何"命中计数"都会凭空多一份）----
	u.ifield_hp = u.ifield_max
	shield_hits.clear()
	u.take_damage(0.0, null, Damage.Type.BEAM)
	t.eq(shield_hits.size(), 0, "零伤害命中**不**发 `ifield_hit`")

	# ---- 语义边界：打穿护盾、伤害溢出到机体时走 `damaged`，不是这条 ----
	u.ifield_hp = 5.0
	shield_hits.clear()
	hull_hits.clear()
	u.take_damage(40.0, null, Damage.Type.BEAM)
	t.eq(shield_hits.size(), 0,
		"打穿护盾并溢出到机体的那一发**不发** `ifield_hit`（它掉血了，有 `damaged`）")
	t.eq(hull_hits.size(), 1, "...那一发发的是 `damaged`（语义正确）")

	# ---- 换算：分母是护盾池，不是机体血 ----
	t.near(ChaseCamera.shield_hit_ratio(10.0, 200.0),
		ChaseCamera.shield_hit_ratio(20.0, 400.0), 0.000001,
		"同样吃掉 5% 护盾 ⇒ 同样的幅度（**护盾池**作分母，与池子多大无关）")
	t.gt(ChaseCamera.shield_hit_ratio(10.0, 120.0),
		ChaseCamera.shield_hit_ratio(10.0, 467.0),
		"盾薄的机（120）挨同一发**比盾厚的机（467）抖得更重** —— 这才是对的")
	t.near(ChaseCamera.shield_hit_ratio(10.0, 0.0), 0.0, 0.000001,
		"`ifield_max == 0`（没有护盾的机）⇒ 幅度 0，不会除零")

	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ---------------------------------------------------------------- 4 AI 不抖玩家

static func _ai(t: T, host: Node) -> void:
	Game.reset()
	# ⚠️ 玩家这台机**必须带浮游导弹**：这条测的是"玩家自己发弹 ⇒ 自己的镜头抖"，
	# 而量产机（梅萨）根本没有浮游导弹 ⇒ `fire_funnel()` 直接返回 false，
	# 第一版就是这么写的，于是反证那条永远测不到东西（假绿）。
	# 柯西是玩家侧唯一带浮游导弹的机（梅萨/古斯塔夫没有），配对自动落到佩涅罗佩。
	Game.active_suit = SuitProfile.Id.XI
	Game.active_side = BattleFormation.Side.MAFTY
	var m := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(m)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, -1)
	for i in 16:
		await host.get_tree().physics_frame

	var player: FlightBody = m.get("player")
	var chase: ChaseCamera = m.get("chase")
	var foe: FlightBody = null
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u == player:
			continue
		if not u.has_method("is_alive") or not u.is_alive():
			continue
		if u.team != player.team:
			foe = u
			break
	if player == null or chase == null or foe == null:
		t.ok(false, "**1v1 局没建起来** —— AI 发弹那条测不了")
		m.queue_free()
		await host.get_tree().physics_frame
		return

	# 让敌机打一梭（把可能挡路的闸手动放开，保证**真的打出来了**）
	foe.set("funnel_cooldown", 0.0)
	var foe_ammo_before := float(foe.get("funnel_count"))
	var before := chase._shake
	var before_pending := chase._launch_pending
	var launched: bool = foe.fire_funnel(player, 0.0)
	t.ok(launched, "敌机**确实**打出了一梭（否则下面那条是空测）")
	t.lt(float(foe.get("funnel_count")), foe_ammo_before, "...而且弹药确实消耗了")

	t.near(chase._shake, before, 0.0001,
		"**AI 发弹一点都没抖玩家的镜头**（`fire_funnel()` 是玩家与 AI 共用的）")
	t.near(chase._launch_pending, before_pending, 0.0001, "...连待落账的后坐量都没动")

	# 反证：玩家自己打一梭，**玩家**的镜头就得动 —— 证明上面那条不是"通道整个坏了"
	#
	# ⚠️ 判据用 `_launch_pending`（**同步**累加）而不是 `_shake`。两个原因：
	#   ① `_shake` 要等 `_physics_process → _flush_launch_shake()` 才落账，
	#      而第一版这里 `await` 的是 **`process_frame`** —— 落账根本不会发生，
	#      于是"玩家发弹"实测 0.0000，看着像通道是坏的。
	#      (`add_launch_shake()` 是 `fire_funnel()` 里**同步**调的，所以这样读既确定又不用等帧。)
	#   ② 等两帧的话，敌机刚才那几发导弹可能正好打中玩家，`_shake` 会因为**受击**而升高
	#      —— 那条断言就变成在测别的东西了。
	t.gt(float(player.get("funnel_count")), 0.0, "（前提）玩家这台机带浮游导弹")
	player.set("funnel_cooldown", 0.0)
	var p_pending := chase._launch_pending
	var p_ok: bool = player.fire_funnel(_any_target(player), 0.0)
	t.ok(p_ok, "玩家自己打得出这一梭（前提成立）")
	t.gt(chase._launch_pending, p_pending + 0.01,
		"玩家自己发弹 ⇒ 后坐量**确实**进了玩家镜头（上面那条不是空测）")

	m.queue_free()
	await host.get_tree().physics_frame


static func _any_target(player: FlightBody) -> Node3D:
	for u: Node3D in Game.units:
		if is_instance_valid(u) and u != player and u.has_method("is_alive") and u.is_alive():
			return u
	return null


# ------------------------------------------------ 7 构图（批 3 §四 · 轮 63-5）
#
# 用户报的两个症状：
#   ① 正常飞行时自机容易跑到画面外；
#   ② 辅助驾驶下锁定目标大幅机动时，视角被一瞬间拉过去、自机突然消失。
#
# 根因（`tools/probe_cam_framing.gd` 无头实测，改前读数）：
#   · ② 的一半 = **同框层是死代码** —— `_desired_basis()` 里锁定层**后写**、
#     把同框层整段覆盖（钉住机位后"两个都开"与"只开锁定"的视线方向**逐位相同**）。
#   · ①② 的共同根因 = **没有"自机必须留在画面里"这道约束**：锁定锥角 55°
#     大于半水平视场（16:10 47.18°）⇒ 敌机到锥边缘时自机必然出画（峰值 54.96°）。
#
# ⚠️ 本节的判据**全是几何量**，不依赖渲染 ⇒ `--headless` 下可跑（§4.5 的硬要求）。
# ⚠️ 本节刻意**不动手动锁定视角**（Alt）：`notes/04` 明写那套是"盯住敌机、
# 自机可被甩出"，是设计不是 bug ⇒ 有一节专门把这个"让开"钉住。

## 构图判据用的哑机体。
##
## `ChaseCamera` 只**鸭子类型**读 `target.get("fm")`（见 `_target_velocity()`），
## 所以判据不需要 `FlightBody`，也就不加载任何 glb（无头下又快又干净）。
class DummyFmBody extends Node3D:
	var fm := FlightModel.new()


## 目标方位（水平，度）。55 = 锁定锥边缘（`lock_on_system.gd` 的 `LOCK_CONE_DEG`）。
const FRAME_BEARINGS := [0.0, 20.0, 30.0, 40.0, 50.0, 55.0]
const FRAME_DISTS := [300.0, 1000.0, 3000.0]
## 目标横移速度（m/s）—— 用来把提前量逼到封顶之外。
const FRAME_SIDE_VEL := 2000.0


## 自机机头方向在水平面内偏 `th` 弧度（度制外面转）的单位向量。
static func _dir_at(th: float) -> Vector3:
	return Vector3(sin(th), 0.0, -cos(th))


## 造一台"受控相机 + 哑自机 + 哑敌机"。
##
## 相机的 `_physics_process` 必须关掉（同 `_fresh()`：不关就没法控制"跑了几帧"）。
static func _framing_rig(host: Node) -> Dictionary:
	var p := DummyFmBody.new()
	var f := DummyFmBody.new()
	var cam := ChaseCamera.new()
	host.add_child(p)
	host.add_child(f)
	host.add_child(cam)
	cam.set_physics_process(false)
	cam.current = false
	cam.set_target(p)
	cam.aim_target = f
	p.global_position = Vector3(0.0, 3000.0, 0.0)
	_spawned.append(p)
	_spawned.append(f)
	_spawned.append(cam)
	return {"cam": cam, "player": p, "foe": f}


## 把敌机摆到"自机机头偏 `bearing` 度、距离 `dist`"，并给它一个水平横移速度。
static func _place_foe(player: Node3D, foe: DummyFmBody, bearing: float, dist: float,
		side_vel: float) -> void:
	var yaw := deg_to_rad(bearing)
	foe.global_position = player.global_position + _dir_at(yaw) * dist
	foe.fm.velocity = Vector3(cos(yaw), 0.0, sin(yaw)) * side_vel


## 相机**钉在** `pin` 处、按给定混合量算一次视轴方向。
##
## ⚠️ 必须钉住位置：`_frame_blend` 同时改**后退距离**，不钉的话量到的是
## "机位变没变"而不是"视线点变没变"（第一次就栽在这上面：读数 0.77° 而不是 0）。
static func _view_dir(cam: ChaseCamera, lk: float, fr: float, pin: Vector3) -> Vector3:
	cam._lock_blend = lk
	cam._frame_blend = fr
	cam._fpv_blend = 0.0
	cam.global_position = pin
	var b := cam._desired_basis()
	cam.global_transform = Transform3D(b, cam.global_position)
	return -b.z


## **硬截断**版安全角 —— **只用来自证判据抓得住这种写法**（产品不许这么写）。
static func _hard_clamp(cam_pos: Vector3, player_pos: Vector3, look_point: Vector3,
		safe_rad: float) -> Vector3:
	var to_lp := look_point - cam_pos
	var to_p := player_pos - cam_pos
	if to_lp.length_squared() < 0.0000001 or to_p.length_squared() < 0.0000001:
		return look_point
	if to_lp.angle_to(to_p) <= safe_rad:
		return look_point
	return cam_pos + to_p.normalized() * to_lp.length()


## 单层合成必须与旧公式 `base.lerp(点, w)` **逐位相同**。
static func _one_layer_ok(base: Vector3, pt: Vector3, w: float) -> bool:
	return ChaseCamera.compose_look_point(base, Vector3.ZERO, 0.0, pt, w) == base.lerp(pt, w)


static func _framing(t: T, host: Node) -> void:
	seed(20261003)
	var rig := _framing_rig(host)
	var cam: ChaseCamera = rig["cam"]
	var player: DummyFmBody = rig["player"]
	var foe: DummyFmBody = rig["foe"]

	# ---- 1 半水平视场从**运行时视口**取宽高比（不许写死 16:9）----
	#
	# ⚠️ Godot 的 `fov` 是**垂直**角。写死 16:9 的实现会在无头（方形视口）下
	# 把安全角算宽 3°，于是自机又出画，而且**不报任何错**。
	var vp := cam.get_viewport()
	var aspect := 1.7777778
	if vp != null:
		var sz := vp.get_visible_rect().size
		if sz.y > 0.0001:
			aspect = sz.x / sz.y
	var want_h := atan(tan(deg_to_rad(cam.fov * 0.5)) * aspect)
	var safe := cam._safe_angle()
	t.near(cam._half_h_fov(), want_h, 0.000001,
		"`_half_h_fov()` = atan(tan(fov/2) × aspect)，宽高比取**运行时视口**")
	t.near(safe, want_h * ChaseCamera.SAFE_FRAC, 0.000001, "安全角 = 半水平视场 × SAFE_FRAC")
	t.near(ChaseCamera.SAFE_FRAC, 0.62, 0.000001, "安全角系数 = 0.62（用户拍板）")
	t.near(ChaseCamera.ASSIST_LOCK_CAP, 0.45, 0.000001, "辅助驾驶 `lk` 上限 = 0.45（用户拍板）")
	t.near(ChaseCamera.LEAD_DIST_FRAC, 0.25, 0.000001, "提前量距离封顶 = 0.25（用户拍板）")
	t.near(ChaseCamera.LOCK_LEAD_TIME, 0.25, 0.000001, "锁定时间提前量仍是 0.25 s")
	t.lt(safe, cam._half_h_fov(), "安全角严格小于半水平视场（贴边不算在里面，要留余量）")
	print("[frame] 无头视口 aspect=%.4f ⇒ 半水平视场 %.2f° / 安全角 %.2f°"
		% [aspect, rad_to_deg(cam._half_h_fov()), rad_to_deg(safe)])

	# ---- 2 `force_in_frame()`：锥内逐位不动 / 锥外落回锥面 / 连续 ----
	var cpos := Vector3.ZERO
	var ppos := Vector3(0.0, 0.0, -1000.0)
	t.ok(ChaseCamera.force_in_frame(cpos, ppos, ppos, safe) == ppos,
		"锥内的视线点**逐位原样返回**（`==`）—— 这是不改既有构图的保证")
	var out_pt := cpos + _dir_at(deg_to_rad(48.0)) * 1000.0
	var fixed := ChaseCamera.force_in_frame(cpos, ppos, out_pt, safe)
	t.near((fixed - cpos).angle_to(ppos - cpos), safe, 0.0001,
		"锥外 48° 的视线点被拉到**恰好**安全角（%.4f°）" % rad_to_deg(safe))
	t.near((fixed - cpos).length(), 1000.0, 0.01, "而且长度不变（只转向、不缩水）")
	# 连续：扫过阈值那一段的**单步位移**
	var n_steps := 120
	var span := 0.12
	var half := span * 0.5
	var prev_s := ChaseCamera.force_in_frame(cpos, ppos, cpos + _dir_at(safe - half) * 1000.0, safe)
	var prev_h := _hard_clamp(cpos, ppos, cpos + _dir_at(safe - half) * 1000.0, safe)
	var step_soft := 0.0
	var step_hard := 0.0
	for i in range(1, n_steps + 1):
		var th := safe - half + span * float(i) / float(n_steps)
		var pt := cpos + _dir_at(th) * 1000.0
		var s := ChaseCamera.force_in_frame(cpos, ppos, pt, safe)
		var h := _hard_clamp(cpos, ppos, pt, safe)
		step_soft = maxf(step_soft, (s - prev_s).length())
		step_hard = maxf(step_hard, (h - prev_h).length())
		prev_s = s
		prev_h = h
	t.gt(step_hard, 100.0,
		"（仪器自证）换成**硬截断**写法，同一扫描下最大单步位移 %.1f m ⇒ 本判据抓得住它" % step_hard)
	t.lt(step_soft, 2.0,
		"产品是**软钳**：最大单步位移 %.5f m（= 1000 m × 扫描步长 %.5f rad 的量级）"
			% [step_soft, span / float(n_steps)])

	# ---- 3 `lead_with_cap()` ----
	var lv := Vector3(FRAME_SIDE_VEL * ChaseCamera.LOCK_LEAD_TIME, 0.0, 0.0)
	t.ok(ChaseCamera.lead_with_cap(lv, 3000.0, ChaseCamera.LEAD_DIST_FRAC) == lv,
		"未超封顶时**逐位原样返回**（3000 m 处封顶 750 m > 500 m）")
	var capped := ChaseCamera.lead_with_cap(lv, 1000.0, ChaseCamera.LEAD_DIST_FRAC)
	t.near(capped.length(), 250.0, 0.001, "1000 m 处封顶到 0.25 × 1000 = 250 m（未封顶是 500 m）")
	t.near(capped.normalized().dot(lv.normalized()), 1.0, 0.000001, "方向不变（封顶只砍长度）")
	t.eq(ChaseCamera.lead_with_cap(lv, 0.0, ChaseCamera.LEAD_DIST_FRAC), Vector3.ZERO,
		"距离 0 ⇒ 提前量 0（不会除零）")

	# ---- 4 `compose_look_point()`：单层逐位退化 + 两层不再互相覆盖 ----
	var base := Vector3(0.0, 0.0, -100.0)
	var fp := Vector3(10.0, 0.0, -50.0)
	var lp := Vector3(30.0, 0.0, -20.0)
	t.ok(_one_layer_ok(base, fp, 1.0), "只有同框层（w=1）⇒ 与旧公式逐位相同")
	t.ok(_one_layer_ok(base, lp, 0.15) and _one_layer_ok(base, lp, 0.5) and _one_layer_ok(base, lp, 1.0),
		"只有锁定层（w=0.15 / 0.5 / 1）⇒ 与旧公式**逐位相同**（回归面最小）")
	t.ok(ChaseCamera.compose_look_point(base, fp, 0.0, lp, 0.0) == base,
		"两层权重都是 0 ⇒ 基准点逐位不动")
	var both := ChaseCamera.compose_look_point(base, fp, 1.0, lp, 1.0)
	t.gt(both.distance_to(base.lerp(lp, 1.0)), 1.0,
		"两层都开时结果**不等于**只有锁定（相距 %.3f m）—— 旧代码这里恒为 0.000000，正是死代码指纹"
			% both.distance_to(base.lerp(lp, 1.0)))

	# ---- 5 真实宿主：辅助驾驶（`frame_both` + 锁定同时开）⇒ 自机留在画面里 ----
	#
	# ⚠️ 这两层**同时为真**不是巧合：`player_controller._tick_assist()` 在
	# "保持飞行操纵"（巡航 / 骑板）下就是 `frame_both = true` + `set_lock_view(true)`。
	var worst_assist := 0.0
	var worst_manual := 0.0
	var worst_raw_manual := 0.0
	for bearing: float in FRAME_BEARINGS:
		for dist: float in FRAME_DISTS:
			player.global_position = Vector3(0.0, 3000.0, 0.0)
			player.fm.velocity = Vector3.ZERO
			_place_foe(player, foe, bearing, dist, 0.0)
			cam.aim_target = foe
			# 机位**钉死**成同一处（辅助驾驶那一档的后退距离）⇒ 只比视线方向，
			# 不比"机位变没变"。
			cam._lock_blend = 1.0
			cam._frame_blend = 1.0
			cam._fpv_blend = 0.0
			var pin := cam._desired_position()
			var d_assist := _view_dir(cam, 1.0, 1.0, pin)
			worst_assist = maxf(worst_assist, rad_to_deg(
				d_assist.angle_to(cam.global_position.direction_to(player.global_position))))
			var d_manual := _view_dir(cam, 1.0, 0.0, pin)
			worst_manual = maxf(worst_manual, rad_to_deg(
				d_manual.angle_to(cam.global_position.direction_to(player.global_position))))
			# 不施加安全角时长什么样：只有锁定层 ⇒ 视线点 = 敌机本身（`side_vel` 传 0，
			# 提前量为 0）⇒ 直接量"相机 → 敌机"与"相机 → 自机"的夹角
			worst_raw_manual = maxf(worst_raw_manual, rad_to_deg(
				cam.global_position.direction_to(foe.global_position).angle_to(
					cam.global_position.direction_to(player.global_position))))
	t.lt(worst_assist, rad_to_deg(safe) + 0.05,
		"辅助驾驶（两层都开）⇒ 自机偏角最大 %.2f° ≤ 安全角 %.2f°（改前是 54.96°）"
			% [worst_assist, rad_to_deg(safe)])
	t.lt(worst_manual, rad_to_deg(safe) + 0.05,
		"只有锁定层（= 辅助驾驶**平移模式** / Alt 手动锁定，同一条路）⇒ 自机偏角最大 %.2f° ≤ 安全角 %.2f°"
			% [worst_manual, rad_to_deg(safe)])
	t.gt(worst_raw_manual, rad_to_deg(safe) * 1.5,
		"（负对照）同一摆位**不施加**安全角时自机偏角达 %.2f°（> 1.5 × 安全角 %.2f°）"
			% [worst_raw_manual, rad_to_deg(safe)])
	t.gt(worst_assist, 0.0, "（前提）确实量到了东西（不是全 0 的空测）")

	# ---- 6 真实宿主：**正常飞行**（无锁定）相机被甩到侧方 ⇒ 自机仍在画面里 ----
	#
	# 症状①的正口径：不是"稳态构图"（那本来就在正中），而是**相机因滞后落到自机侧方**时。
	cam.aim_target = null
	cam.frame_both = false
	cam._lock_blend = 0.0
	cam._frame_blend = 0.0
	cam._fpv_blend = 0.0
	player.global_position = Vector3(0.0, 3000.0, 0.0)
	player.global_transform = Transform3D(Basis(), player.global_position)
	player.fm.velocity = Vector3.ZERO
	var worst_norm := 0.0
	var worst_raw := 0.0
	for r: float in [20.0, 40.0, 60.0, 80.0, 120.0, 300.0]:
		cam.global_position = player.global_position + Vector3(r, 0.0, 0.0)
		var to_p := cam.global_position.direction_to(player.global_position)
		var b := cam._desired_basis()
		cam.global_transform = Transform3D(b, cam.global_position)
		worst_norm = maxf(worst_norm, rad_to_deg((-b.z).angle_to(to_p)))
		# 未加安全角时的视线点（只在判据里算，不动产品）
		var raw := player.global_position + (-player.global_transform.basis.z) * cam.look_ahead \
				+ Vector3.UP * cam.look_up
		worst_raw = maxf(worst_raw, rad_to_deg(
			cam.global_position.direction_to(raw).angle_to(to_p)))
	t.gt(worst_raw, rad_to_deg(safe) * 2.0,
		"（负对照）不加安全角时同样的机位会把自机偏到 %.2f°（> 2 × 安全角 %.2f°）"
			% [worst_raw, rad_to_deg(safe)])
	t.lt(worst_norm, rad_to_deg(safe) + 0.05,
		"加上安全角后偏角最大 %.2f° ≤ 安全角 %.2f° —— 症状①的正解"
			% [worst_norm, rad_to_deg(safe)])

	# ---- 7 产品口径：`_lead_vector()` 真的被距离封住 ----
	cam.aim_target = foe
	player.global_position = Vector3(0.0, 3000.0, 0.0)
	cam.global_position = player.global_position      # 机位摆在自机上 ⇒ 相机距离 = 目标距离
	_place_foe(player, foe, 30.0, 1000.0, FRAME_SIDE_VEL)
	t.near(cam._lead_vector().length(), 250.0, 0.01,
		"1000 m 处、敌机横移 2000 m/s ⇒ 提前量被压到 250 m（未封顶是 500 m）")
	_place_foe(player, foe, 30.0, 3000.0, FRAME_SIDE_VEL)
	t.near(cam._lead_vector().length(), 500.0, 0.01,
		"3000 m 处封顶 750 m > 500 m ⇒ 提前量**原样放行**（不误伤远距离）")

	# ---- 8 真实步进：`step_now()` 把混合量喂到 1，自机仍留框、且无单帧跳变 ----
	player.global_position = Vector3(0.0, 3000.0, 0.0)
	player.global_transform = Transform3D(Basis(), player.global_position)
	player.fm.velocity = Vector3.ZERO
	_place_foe(player, foe, 55.0, 1000.0, 0.0)
	cam.aim_target = foe
	cam.frame_both = true
	cam._lock_blend = 0.0
	cam._frame_blend = 0.0
	cam._fpv_blend = 0.0
	# 先摆到"未锁定"的稳态：`_aligned()` 同款理由（不摆的话第一帧的 slerp 里
	# 混着"相机在赶路"那一大坨，单帧峰值会被它污染）。
	cam.global_position = cam._desired_position()
	cam.global_transform = Transform3D(cam._desired_basis(), cam.global_position)
	t.ok(cam.set_lock_view(true), "锁定目标在场 ⇒ 可以切进锁定视角")
	var settle := 0
	var worst_step := 0.0
	var prev_dir := -cam.global_transform.basis.z
	for i in 180:
		cam.step_now(1.0 / 60.0)
		var dir := -cam.global_transform.basis.z
		worst_step = maxf(worst_step, rad_to_deg(dir.angle_to(prev_dir)))
		prev_dir = dir
		if settle == 0 and cam._lock_blend >= 0.9999 and cam._frame_blend >= 0.9999:
			settle = i + 1
	t.near(cam._lock_blend, 1.0, 0.0001, "步进 180 帧后 `_lock_blend` 到达 1")
	t.near(cam._frame_blend, 1.0, 0.0001, "`_frame_blend` 也到达 1（辅助驾驶两层都在场）")
	t.gt(float(settle), 0.0, "两层在 180 帧内就都稳定（第 %d 帧）" % settle)
	var safe2 := cam._safe_angle()
	var off_final := rad_to_deg((-cam.global_transform.basis.z).angle_to(
		cam.global_position.direction_to(player.global_position)))
	t.lt(off_final, rad_to_deg(safe2) + 0.5,
		"稳定后自机偏角 %.2f° ≤ 安全角 %.2f°（切进辅助驾驶的全过程都留在画面里）"
			% [off_final, rad_to_deg(safe2)])
	t.lt(worst_step, 3.0, "全程**单帧最大转角** %.3f°/帧 < 3.0 ⇒ 没有一瞬间拉过去" % worst_step)
	t.gt(worst_step, 0.0, "（前提）确实转了（否则上面那条是空测）")
	print("[frame] 辅助驾驶步进：稳定帧 %d｜自机终值 %.2f°｜单帧峰值 %.3f°/帧"
		% [settle, off_final, worst_step])

	# ---- 9 常规第三人称（**发射段刚性追尾同款**）构图一字未动 ----
	#
	# `_rigid_chase()` 走的就是本函数（`_desired_basis()`）⇒ 只要常规机位下自机偏角
	# **远小于**安全角，安全角那道就完全不介入（`force_in_frame()` 原样返回）。
	# 这条是"改动没有溅到发射段 / 常规飞行"的判据 —— 比出图便宜而且更硬。
	player.global_position = Vector3(0.0, 3000.0, 0.0)
	player.global_transform = Transform3D(Basis(), player.global_position)
	player.fm.velocity = Vector3.ZERO
	cam.aim_target = null
	cam.frame_both = false
	cam._lock_blend = 0.0
	cam._frame_blend = 0.0
	cam._fpv_blend = 0.0
	cam.global_position = cam._desired_position()
	var b0 := cam._desired_basis()
	var off0 := rad_to_deg((-b0.z).angle_to(
		cam.global_position.direction_to(player.global_position)))
	t.lt(off0, rad_to_deg(safe) * 0.5,
		"常规追尾机位（发射段同款）自机偏角 %.2f° 远小于安全角 %.2f°"
			% [off0, rad_to_deg(safe)])
	var lp0 := player.global_position + Vector3.UP * cam.look_up \
			+ Vector3(0.0, 0.0, -cam.look_ahead)
	t.ok(ChaseCamera.force_in_frame(cam.global_position, player.global_position, lp0, safe) == lp0,
		"该几何下 `force_in_frame()` **逐位原样返回** ⇒ 发射段 / 常规飞行构图一字未动")
	print("[frame] 常规追尾机位自机偏角 %.2f°（安全角 %.2f°）⇒ 安全角不介入"
		% [off0, rad_to_deg(safe)])


class MotionTarget extends FlightBody:
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass

static func _propulsion(t: T, host: Node) -> void:
	for fps in [30, 60, 120]:
		var value := 0.0
		for i in fps:
			value = ChaseCamera.propulsion_envelope(value, 1.0, 1.0 / fps, 8.0, 4.0)
		t.near(value, 1.0 - exp(-8.0), 0.00001, "propulsion envelope independent of FPS %d" % fps)
	var body := MotionTarget.new()
	body.profile = SuitProfile.by_id(SuitProfile.Id.XI)
	body.fm = FlightModel.new()
	host.add_child(body)
	var cam := ChaseCamera.new()
	host.add_child(cam)
	cam.set_physics_process(false)
	cam.set_target(body)
	cam.shake_scale = 0.0
	cam.boost_amount = 1.0
	body.fm.boosting = true
	body.fm.super_boost = true
	body.fm.velocity = Vector3(0, 0, -1800)
	body.fm.speed = 1800.0
	for i in 180:
		cam._step_thrust_motion(1.0 / 60.0)
		cam._update_fov(1.0 / 60.0)
	t.ok(cam.fov <= 104.001 and cam.fov > 100.0, "super FOV distinct and bounded instead of 124 degrees")
	var super_fov := cam.fov
	body.fm.super_boost = false
	for i in 180:
		cam._step_thrust_motion(1.0 / 60.0)
		cam._update_fov(1.0 / 60.0)
	t.ok(cam.fov < super_fov - 8.0, "ordinary boost has a separate FOV tier")
	body.translate_dash = true
	body.fm.velocity = Vector3(1800, 0, 0)
	cam._step_thrust_motion(1.0 / 60.0)
	t.ok(cam._thrust_dash > 0.0 and cam._thrust_dash < 0.5, "dash attack starts smoothly")
	t.gt(cam._dash_direction.x, 0.9, "lateral dash feedback follows actual velocity")
	body.translate_dash = false
	for i in 120: cam._step_thrust_motion(1.0 / 60.0)
	t.lt(cam._thrust_dash, 0.001, "dash offset returns after release")
	cam.motion_scale = 0.0
	for i in 180: cam._update_fov(1.0 / 60.0)
	t.near(cam.fov, cam.base_fov, 0.001, "reduce motion disables propulsion FOV")
	cam.first_person = true
	cam._step_thrust_motion(1.0 / 60.0)
	t.near(cam._thrust_super + cam._thrust_boost + cam._thrust_dash, 0.0, 0.001, "cockpit bypasses new motion envelopes")
	cam.first_person = false
	cam.motion_scale = 0.0
	cam.boost_amount = 0.0
	body.fm.boosting = false
	for fps in [30, 60, 120]:
		body.position = Vector3.ZERO
		body.fm.velocity = Vector3(0, 0, -1800)
		cam.set_target(body)
		t.near(cam.position.distance_to(body.position), cam.offset.length(), 0.01, "spawn camera starts at physical follow distance")
		for i in fps * 4:
			body.position += body.fm.velocity / fps
			cam.step_now(1.0 / fps)
		t.near(cam.position.distance_to(body.position), cam.offset.length(), 0.1, "high-speed steady framing has no velocity-dependent drift %d FPS" % fps)
	cam.set_target(null)
	t.near(cam._thrust_dash + cam._thrust_boost + cam._thrust_super, 0.0, 0.001, "target switch clears motion state")
	cam.free()
	body.free()
