extends Node
## 轮 14 交付用：**机体真的在飞**时的尾焰 A/B —— 回答"尾焰跟不跟得上机体速度"。
##
## ## 为什么不能用现成的 `plume_shot.gd`
##
## 它每帧把机体位置**回钉**在同一个点上（那是为了三张图背景逐像素一致）。
## 而回钉之后，"世界坐标"与"局部坐标"的粒子读数**逐像素相同** ——
## 也就是说那个机位在原理上**看不见"机体在动"这一维**，而本缺陷正是被它藏住的
## （轮 11 验收过的那一版参数、那一版 read，都是在这个机位下看的）。
##
## ⇒ **取证条件把被测现象抹掉了**。要验"跟不跟得上"，取证条件里必须**真的有速度**。
##
## ## 本探针怎么做
##
##   · 机体**真的飞**：走 debug 输入通道（`debug_boost` / `debug_input`），
##     并在每帧把**燃料槽回满**（`jet_left`）—— 否则槽烧空之后 `resolve_jet_gauge`
##     会否掉加力、速度掉下来，三个 pass 就不是同一个速度了（这是本探针最容易踩的坑）；
##   · 相机是机体的**子节点**（局部坐标 ⇒ 严丝合缝地跟着）；
##     每帧在脚本里按"机体当前位置"摆相机是不行的：一个物理帧机体就走 38 m，
##     相机滞后一帧就是 38 m 的相对偏移（在 118 m 机位上 ≈ 300 px 的抖动）；
##   · 每个 pass 都**回到同一个锚点**、再跑**同样多的物理帧** ⇒
##     位置 / 姿态一致；
##   · 两个 pass 只差一件事：
##       `NEW` 现在的代码（机体局部空间，`local_coords = true`）；
##       `OLD` 运行期把 `local_coords` 置回 `false` ⇒ **复刻改前**（世界空间）。
##   · 每个 pass 抓 **6 张**：`{close,wide} × {on,off,on2}` ——
##     **先冻住整棵树**（`paused = true`：粒子定格、背景定格），再在**同一个瞬间**
##     依次：显示 → 隐藏 → 再显示。`on − off` = **纯粹的尾焰屏幕足迹**；
##     `on2 − on` = **"暂停确实冻住了粒子"的对照**（必须逐像素为零）。
##
##     ⚠️ 这一步是本探针最重要的方法学修正。原版是"拿 OFF pass 当基线做跨 pass 差分"，
##     但**跨 pass 的机体位置根本对不齐**（实测差一个物理帧 = 38 m = 特写机位 ~300 px），
##     于是差分里混进了"整片星空错位"（亮像素数从 3026 里 90% 是星点），
##     结论也就没法用。**同一瞬间的显/隐 A/B 把"背景一致"这个假设整个删掉了** ——
##     不需要假设，因为两张图的背景本来就是同一帧渲染的。
##
## ## 跑法（**不能加 --headless**，dummy 渲染器抓出来是空的）
##
##   godot --path <工程> res://tools/plume_speed.tscn -- <输出目录> <tag>

const SHOT_W := 1600
const SHOT_H := 900
## 起跑时长（秒）：只是让 `velocity` 的 lerp 收敛 + 尾焰填满一个寿命周期，
## **不是**在等速度饱和（速度已由 `_refill()` 钉在 `ab_speed` 上）。
const SPOOL := 1.5
## 每个 pass 从锚点起飞到抓图的**物理帧数**。
##
## ⚠️ 用**物理帧数**而不是墙钟秒数：Godot 的物理步是固定步长 ⇒ 帧数直接等于
## "飞了多远"。**三个 pass 必须飞同样多的帧数**，否则末端位置不同、背景不同。
## 60 帧 = 1.0 s @ 60 Hz：> 尾焰寿命 0.30 s 的三倍（世界空间那一版要整代换掉才不留残影）。
const PASS_FRAMES := 60

var main: Node
var out_dir := "user://captures"
var tag := "plume_speed"

var _p: FlightBody = null
var _cam: Camera3D = null
## 第三个参数给 `static` ⇒ **速度钉 0**（隔离实验：区分"坐标系"与"真的在动"）。
var _stationary := false
## 每个 pass 的起跑点（世界坐标）。三个 pass 都回到这里。
var _anchor := Vector3.ZERO
## 每个 pass 抓图时的速度与位置（打印出来自证"三个 pass 同速"）。
var _speed_at_shot := 0.0
var _frames_flown := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		tag = args[1]
	if args.size() > 2:
		_stationary = str(args[2]) == "static"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	var menu = main.get("menu")
	if menu != null:
		menu.call("close_menu")
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS)
	await _frames(30)
	main.call("_start_fight")
	await _frames(20)

	_p = main.get("player") as FlightBody
	if _p == null or not is_instance_valid(_p):
		print("PLUME_SPEED_FAILED(no player)")
		get_tree().quit(1)
		return
	_p.max_hp = 99999.0
	_p.hp = 99999.0
	_p.ifield_max = 9999.0
	_p.ifield_hp = 9999.0
	# ⚠️ **必须走 debug 输入通道**，不能直接写 `fm.boosting`：`_read_flight_input()`
	# 每帧拿真实按键重写 `fm.boosting`，探针里没人按 Shift ⇒ 手写的 true 下一帧被抹掉。
	_p.set("debug_input_enabled", true)
	_p.set("debug_input", Vector3.ZERO)
	_p.set("debug_throttle", 1.0)
	_p.set("debug_boost", true)
	_p.set("debug_hover", false)

	# 敌机挪到远处并冻住：它在画面里只会干扰对尾焰的读数。
	var e = main.get("enemy")
	if e != null and is_instance_valid(e):
		e.set_physics_process(false)
		e.set_process(false)
		if e.get("fm") != null:
			e.fm.velocity = Vector3.ZERO
			e.fm.speed = 0.0
		e.global_position = _p.global_position + Vector3(0, 0, -9000)

	# ⚠️ **必须停掉 `Main` 的每帧逻辑**（与 `plume_shot.gd` 同一条规矩），否则
	# `_update_cloud_shade()` 一类的每帧改写会让尾焰**整个不可见**（实测：
	# 不停 Main 时三张图里一发尾焰都没有，而接线 print 显示 emitting=true / amount=40 /
	# visible=true；停掉之后火焰立刻出现）。机体自己的 `_physics_process` 照跑
	#（它是子节点），所以"真的在飞"这件事不受影响。
	main.set_physics_process(false)
	main.set_process(false)

	_hide_ui()
	_setup_cam()

	# ---- 起跑：让速度向量与粒子进入稳态（速度已由 `_refill()` 钉住）----
	await _spool(SPOOL)
	_anchor = _p.global_position
	print("[plume_speed] 起跑完成：speed=%.1f m/s  anchor=(%.0f, %.0f, %.0f)"
		% [_p.fm.speed, _anchor.x, _anchor.y, _anchor.z])

	# ---- 暖机 pass（**抓图但丢弃**）----
	#
	# ⚠️ 实测无论把哪个 pass 排在第一个，它的落点都比后面几个**少走一个物理帧**
	#（37.8 m = 2268 m/s ÷ 60 Hz，在所有 pass 上都是同一个数）。
	# 改用"同一瞬间显/隐 A/B"之后背景已经不需要跨 pass 对齐了，但这个暖机 pass
	# 仍然保留：它保证后面两个 pass 的**粒子场**也处在同一种相位上（同一个寿命相位）。
	await _pass("WARM", true, false)
	# ---- pass NEW：现在的代码（机体局部空间）----
	_show_plumes(true)
	await _pass("NEW", true)
	# ---- pass OLD：复刻改前（世界空间）----
	await _pass("OLD", false)

	print("PLUME_SPEED_DONE -> ", out_dir)
	get_tree().quit(0)


## 一个 pass：回到锚点 → 摆好坐标系 → 飞 PASS_FRAMES 个物理帧 → 特写 + 全景两张图。
##
## `space`：`true`/`false` = 把三个发射器的 `local_coords` 设成它（`null` = 不动）。
##
## ⚠️ 三件事的顺序不能变：**先摆坐标系、再飞满帧数**。
## 第一版把"摆坐标系"放在飞完之后（想让它整代换掉），于是 OFF 只飞 42 帧、
## NEW/OLD 飞 66 帧 ⇒ 末端位置差 1.6 km ⇒ 三张图的背景根本对不上，
## 差分法直接失效（只有打印出来的 speed/pos 能看出这件事）。
func _pass(name: String, space, shoot := true) -> void:
	_p.global_position = _anchor
	_refill()
	if space != null:
		_apply_space(space)
	# 回锚点时，上一个 pass 留下的世界空间粒子在 1.6 km 之外（画面里看不到），
	# 所以不需要额外的"排空"时间 —— 飞满 PASS_FRAMES 本身就够整代换掉。
	await _fly(PASS_FRAMES)
	_speed_at_shot = _p.fm.speed
	print("[plume_speed] %-4s 抓图时 speed=%.1f m/s  pos=(%.0f, %.0f, %.0f)  local_coords=%s"
		% [name, _speed_at_shot, _p.global_position.x, _p.global_position.y,
			_p.global_position.z, _space_label()])
	print("[plume_speed]      %s" % _plume_state())
	if not shoot:
		return
	# 冻住整棵树再抓图：粒子与背景都定格 ⇒ 下面这一对图的**背景是同一帧渲染出来的**。
	get_tree().paused = true
	await _shot_pair(name, false)
	await _shot_pair(name, true)
	get_tree().paused = false


## 在**同一个瞬间**抓一对：① 发射器隐藏（基线）② 发射器显示（信号）。
##
## 两张之差 = **纯粹的尾焰屏幕足迹**：背景是同一帧，粒子位置也定格（树已 paused），
## 所以这个掩膜**不含任何假设** —— 既不需要"跨 pass 背景一致"，也不需要"背景与喷口无关"
##（后者被星点证伪过：OFF 图自身就有 685 个过阈值的星点像素）。
##
## 结束时把发射器恢复成**显示**，好让下一个 pass 的 `_fly()` 能正常累积粒子
##（世界空间那版尤其需要：藏起来的发射器不发射，尾迹就建不起来）。
##
## ⚠️ 抓**三**张：`on → off → on2`，而且每次切换显隐之后**先静置 4 个渲染帧**再抓。
##
## 两件事都必须做，缺一个就会拿到假图：
##
##   ① **静置**：实测"切完显隐立刻抓"拿到的还是**上一状态的画面**
##      （第一版 `off → on` 的顺序里，`off` 那图 = 纯基线、`on` 那图才有火；
##       改成 `on → off → on2` 之后，前两张**都是纯基线**，只有第三张才有火）。
##      ⇒ 切换与渲染之间有 1~2 帧滞后，不静置就是"拿错帧当证据"。
##
##   ② **`speed_scale = 0`**：实测 `paused = true` **并没有冻住 GPU 粒子**
##      （否则 `on` 与 `on2` 必须逐像素相同，实际上差了一整团火）。
##      粒子在三次抓图之间还在推进 ⇒ 只靠 `paused`，"显 − 隐"里会混进"粒子自己走了几帧"。
##      把 `speed_scale` 钉 0 才是真正的定格；抓完恢复原值。
##
## 抓完把发射器恢复成**显示**，好让下一个 pass 的 `_fly()` 能正常累积粒子
##（世界空间那版尤其需要：藏起来的发射器不发射，尾迹就建不起来）。
func _shot_pair(name: String, wide: bool) -> void:
	var view := "wide" if wide else "close"
	var keep := _set_speed_scale(0.0)          # 真正定格
	_show_plumes(true)
	await _idle(4)
	await _shot("%s_%s_%s_on" % [tag, name, view], wide)
	_show_plumes(false)
	await _idle(4)
	await _shot("%s_%s_%s_off" % [tag, name, view], wide)
	_show_plumes(true)
	await _idle(4)
	await _shot("%s_%s_%s_on2" % [tag, name, view], wide)
	_restore_speed_scale(keep)


## 把三个发射器的 `speed_scale` 设成 `v`，返回**原值**（抓完要还回去）。
func _set_speed_scale(v: float) -> Array:
	var keep := []
	for key in ["_afterburner_fx", "_dash_fx", "_dash_rings"]:
		var n := _p.get(key) as GPUParticles3D
		if n != null and is_instance_valid(n):
			keep.append([n, n.speed_scale])
			n.speed_scale = v
	return keep


func _restore_speed_scale(keep: Array) -> void:
	for pair in keep:
		var n = pair[0]
		if n != null and is_instance_valid(n):
			n.speed_scale = pair[1]


## 静置 n 个**渲染帧**（`process_frame` 在 `paused` 下照常发信号；`physics_frame` 也是，
## 但这里要的是渲染侧追上来，所以用渲染帧）。
func _idle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 每帧的把柄：**速度钉在推进上限** + 回满燃料槽 + 保住生命值。
##
## ## 为什么速度要钉
## `FlightModel._step_speed()` 是**比例式**（`a = clampf((target − speed) · speed_gain, …)`），
## `_step_velocity()` 又是 `velocity.lerp(desired, 1 − exp(−k·dt))` ——
## **两条都是渐近的、永远到不了目标**。实测三个 pass 的末端位置差 **25 m**
##（≈ 特写机位上的 200 px），而"与 OFF 图相减"的差分法要求背景**逐像素一致**。
## 钉住之后，pass 之间**只差 `local_coords` 一件事** —— 这才是受控对照。
## 这是**受控条件**（与 `plume_shot._repin()` 的逐帧回钉同一性质），不是在被测对象上做手脚：
## 被测对象是粒子的坐标系，而速度是**取证条件**。
##
## ## 为什么燃料槽要回满
## 槽空之后 `resolve_jet_gauge()` 会否掉加力（`jet_active = false`）⇒ 速度掉下来 ⇒
## 三个 pass 又不是同一个速度了。
func _refill() -> void:
	if _p == null or not is_instance_valid(_p):
		return
	if _p.profile != null and _p.profile.has_jet_gauge:
		_p.set("jet_left", _p.profile.jet_seconds)
	_p.hp = _p.max_hp
	if _p.fm != null:
		if _stationary:
			_p.fm.speed = 0.0
			_p.fm.velocity = Vector3.ZERO
		else:
			_p.fm.speed = _p.fm.ab_speed
			_p.fm.velocity = -_p.global_transform.basis.z * _p.fm.speed


## 起跑：让速度向量与粒子都进入稳态。
##
## ⚠️ 这里**不需要**"等速度饱和"—— 速度已经被 `_refill()` 钉在上限上了。
## 这 1.5 s 只是为了：① `velocity` 的 lerp 收敛；② 尾焰填满一个寿命周期（0.30 s）。
func _spool(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().physics_frame
		_refill()


func _fly(n: int) -> void:
	_frames_flown = 0
	for i in n:
		await get_tree().physics_frame
		_refill()
		_frames_flown += 1


## 三个尾焰发射器：显隐（OFF 基线用）。
## ⚠️ `visible` 是**没有别的地方会写**的字段（`_tick_effects` 只写 `emitting` /
## `amount_ratio` / `speed_scale`）⇒ 探针可以安全地用它当开关。
func _show_plumes(on: bool) -> void:
	for key in ["_afterburner_fx", "_dash_fx", "_dash_rings"]:
		var n := _p.get(key) as Node3D
		if n != null and is_instance_valid(n):
			n.visible = on


## 把三个发射器的坐标系设成 `local`（`local_coords = local`）。
func _apply_space(local: bool) -> void:
	for key in ["_afterburner_fx", "_dash_fx", "_dash_rings"]:
		var n := _p.get(key) as GPUParticles3D
		if n != null and is_instance_valid(n):
			n.local_coords = local


func _space_label() -> String:
	var n := _p.get("_afterburner_fx") as GPUParticles3D
	if n == null:
		return "?"
	return "true" if n.local_coords else "false"


## 把"尾焰到底有没有在喷"的接线级信息印出来。
##
## ⚠️ 第一版漏了这一步，结果三张图里**一发尾焰都没有**，而图看上去"只是暗"。
## 根因是 `_think()` 的第一行：`if not controls_enabled: fm.boosting = false` ——
## 探针逐帧钉了 `fm.speed`/`fm.velocity`，机体照样按 2268 m/s 飞（位置、方差、
## 差分全都正常），但 `fm.boosting` 被否掉 ⇒ 尾焰根本不喷。
## **"机体在飞"完全不能证明"加力状态是开的"** —— 因为速度是探针钉的。
func _plume_state() -> String:
	var ab := _p.get("_afterburner_fx") as GPUParticles3D
	var dsh := _p.get("_dash_fx") as GPUParticles3D
	var any_dash := false
	if _p.has_method("is_dashing"):
		any_dash = bool(_p.call("is_dashing"))
	return "接线：controls_enabled=%s fm.boosting=%s dashing=%s plumes=%d | A: emitting=%s ratio=%.2f visible=%s amount=%d local=%s" % [
		_p.get("controls_enabled"), _p.fm.boosting, any_dash, (_p.get("_plume_fx") as Array).size(),
		ab.emitting if ab != null else false,
		ab.amount_ratio if ab != null else -1.0,
		ab.visible if ab != null else false,
		ab.amount if ab != null else -1,
		ab.local_coords if ab != null else false]


# ============================================================ 相机

## 相机挂成机体的**子节点**：局部坐标 ⇒ 与机体严丝合缝（不会有"滞后一帧 = 38 m"的抖动）。
##
## ⚠️ 必须先关掉 `ChaseCamera` 的 process —— 它每帧按 FOV 档与目标位置重算机位，
## 不关的话这里设的下一帧就被它覆盖。
func _setup_cam() -> void:
	# ⚠️ `var chase := ...` 会踩 "inferred from a Variant value"（本项目把该警告
	# 当错误处理）—— `Node.get()` 的返回是 Variant，所以这里**不能**用 `:=`。
	var chase = main.get("chase")
	if chase is Node:
		(chase as Node).set_process(false)
		(chase as Node).set_physics_process(false)
		if chase is Camera3D:
			(chase as Camera3D).current = false
	_cam = Camera3D.new()
	_cam.name = "PlumeSpeedCam"
	_cam.fov = 48.0
	_cam.near = 0.6
	_cam.far = 60000.0
	_p.add_child(_cam)
	_cam.current = true


## 摆相机（**局部坐标**：`+Z` = 机尾方向，`+X` = 机体右侧）。
##
## ⚠️ 必须是**正侧方**、不能是轴向后方：尾焰沿机尾轴向喷出，从轴向看过去
##    "长度"全被透视压掉（轮 11 踩过）。正侧方看的是侧剖面。
func _place_cam(wide: bool) -> void:
	if _cam == null or _p == null:
		return
	if wide:
		# 全景：把镜头拉远到 330 m，取景中心放到机尾后方 300 m ⇒ 画面横向覆盖 ~800 m，
		# 足够看清"世界空间那一版被抹成了多长一条"。
		_cam.position = Vector3(330.0, 90.0, 300.0)
		_cam.fov = 70.0
		_look_at_local(Vector3(0.0, 0.0, 300.0))
	else:
		# 特写：侧后方 118 m、高 12 m，取景中心在机尾往后 20 m —— 尾焰主体就在这一带。
		_cam.position = Vector3(118.0, 12.0, 28.0)
		_cam.fov = 48.0
		_look_at_local(Vector3(0.0, 0.0, 48.0))


func _look_at_local(local_target: Vector3) -> void:
	var up := _p.global_transform.basis.y.normalized()
	var from := _cam.global_position
	var target := _p.to_global(local_target)
	if from.distance_to(target) < 0.5:
		return
	if absf((target - from).normalized().dot(up)) > 0.999:
		up = _p.global_transform.basis.z.normalized()
	_cam.look_at(target, up)


# ============================================================ 抓图

func _hide_ui() -> void:
	for key in ["hud", "speed_lines"]:
		var n: Node = main.get(key)
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	var menu = main.get("menu")
	if menu is CanvasItem:
		(menu as CanvasItem).visible = false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String, wide: bool) -> void:
	_place_cam(wide)
	# 摆完相机要**等一帧**让它生效（`look_at` 改的是下一帧才参与渲染的变换）。
	await get_tree().process_frame
	# 印出**喷口的屏幕坐标**：判据是"亮像素离喷口多远"，那个参考点必须由探针自己算。
	# 事后拿相机参数手算是不行的 —— 机体一有滚转/俯仰就偏，而且 `unproject_position()`
	# 对落在相机背后的点会返回一个"看似合理"的居中坐标（齐次除法把负 w 翻正），
	# 所以这里**必须**配 `is_position_in_frustum()` 一起判。
	var ab := _p.get("_afterburner_fx") as Node3D
	var ns := Vector2(-1.0, -1.0)
	var ok := false
	if ab != null and _cam != null:
		ok = _cam.is_position_in_frustum(ab.global_position)
		if ok:
			ns = _cam.unproject_position(ab.global_position)
	print("PLUMEPOS %s wide=%s nozzle_screen=(%.1f, %.1f) in_frustum=%s nozzle_local=(%.1f, %.1f, %.1f)"
		% [name, "T" if wide else "F", ns.x, ns.y, "T" if ok else "F",
			ab.position.x if ab != null else 0.0,
			ab.position.y if ab != null else 0.0,
			ab.position.z if ab != null else 0.0])
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport) ", name)
		return
	var tex := vp.get_texture()
	if tex == null:
		print("SHOT_FAILED(no texture) ", name)
		return
	var img := tex.get_image()
	if img == null:
		print("SHOT_FAILED(no image) ", name)
		return
	var path := out_dir.path_join("%s.png" % name)
	var err := img.save_png(path)
	print("SHOT %s  err=%d  %dx%d" % [path, err, img.get_width(), img.get_height()])
