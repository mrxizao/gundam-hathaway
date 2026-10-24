extends Node
## 佩涅罗佩「蓄力激光炮 + **保住连发**」真机取证（2026-09-29）。
##
## ⚠️ **不能加 `--headless`** —— 无头用的是 dummy 渲染器，一个像素都不产生，
## 抓出来是全黑。这个脚本的全部意义就是"能真的看到"。
##
## 跑法：
##   godot --path <工程> res://tools/penelope_cannon_shot.tscn -- <输出目录>
##
## ## 为什么必须有它（套件里测不到的那一段）
## 套件能测**纯函数**（`rifle_press_route()`）与**锁存语义**，但它**不敢**读
## `Input.is_action_just_pressed` / `just_released` —— 无头下这两个的帧戳实测不可靠
## （`tutorial_director.gd:47`）。而"按下 → 蓄力 → 松手 → 柱体出现"这条链
## **恰好全靠那两个边沿**，所以只能在这里、在**真渲染 + 真输入**下跑。
##
## ## 三段，各要"数字 + 画面"两条证据
##   P1 **真输入端到端（就绪）**：满弹匣按住 1.9 s ⇒ `cannon_charging()` 为真 ⇒
##      松手 ⇒ 柱体出现 + 冷却 20 s + 过热换弹 15 s。**这是唯一能证明"输入真的接线了"
##      的证据** —— 套件里扫的是源码结构与纯函数。
##   P2 **保住连发（弹匣不满）**：同一套按键、同一时长 ⇒ **一次都不进蓄力**，
##      而且弹匣真的在掉（多发普通光束打出去了）。这是用户拍板那条口径的**反面**。
##   P3 HUD 那一行两态（就绪 / 弹夹不满）。
##
## ## 三个坑写在出事的那一行旁边
##   1. 机体不能摆在 y=0（`FlightBody.CRASH_ALTITUDE` 判撞海 → 抓到满屏爆炸花瓣）；
##   2. 真实输入那一段必须关 `debug_input_enabled`（开着时 `_physics_process()`
##      读完瞄准就 return，`_read_weapon_input()` **整个不执行**）；
##   3. `_shot()` 很慢（存一次 PNG ≈ 100 ms），别插进"量每帧位移"那种循环里。

const SHOT_W := 1600
const SHOT_H := 900
## 连拍时把时间放慢到这个倍率：两段制弹道的后半段是 90000 m/s，
## 正常速度下"屏幕上有几道光束"这件事根本读不出来（打出去就到了）。
const SLOW_MO := 0.15

var main: Node
var out_dir := "user://captures_pen_cannon"
var _idx := 0
## 命令行给了 `diag` 时多跑一段「注入 → 玩家看见边沿」的逐帧诊断（见 `_phase_input_diag`）。
var _diag := false

## 待注入的按键：[物理帧号, 动作名, 是否按下]
var _pending: Array = []
## 本节点自己数的物理帧（与 `Engine.get_physics_frames()` 同步递增，只是读起来近）。
var _pf := 0
## 注入器一共在几帧里看到过 `fire_primary` 的按下边沿（诊断用）。
var _edge_frames := 0


## ★★ **按键注入必须走 `Input.parse_input_event(InputEventAction)`，不能用
## `Input.action_press()`。**
##
## 为什么（轮 47 用 `tools/_probe_input_edge.gd` 实测定死，三种方式各跑一遍）：
##
##   注入方式                              `pressed` 起始帧   `just_pressed` 帧   与真人一致？
##   `Input.action_press()`                     pf=5             **pf=6**          ✗ 早一帧
##   `InputEventAction` + parse                 pf=9             **pf=9**          ✓ 同帧
##   `InputEventMouseButton` + parse            pf=9             **pf=9**          ✓ 同帧
##
## `action_press()` 是"立刻置为按下、但把边沿记给下一帧"⇒ **`pressed` 比边沿早一帧**。
## 真人按鼠标不是这样：`pressed` 与 `just_pressed` **同帧**成立。
##
## 这一帧之差会**静默判死**任何"边沿 + 门禁"耦合的路由 —— 佩涅罗佩的蓄力炮正好是：
##   · 注入帧：玩家读到 `pressed=true`、`just=false` ⇒ 走老路 ⇒ **先打掉一发**
##     （弹匣 6→5）；
##   · 下一帧：边沿才到，`latch_rifle_route(true)` 去问 `cannon_ready()` ——
##     而它要求"弹夹全满" ⇒ **false** ⇒ 锁存成"不是炮" ⇒ 之后整段按住都在连发。
## 症状（本轮实测）：`按下生效=true` 但 `rifle_press_is_cannon()` 恒 false、
## 弹匣照旧掉 3 发 —— 看着像"路由写错了"，其实是**注入方式**不忠实。
##
## 事件注入是**延迟**的（实测约 4 个物理帧才生效），所以本探针一律
## **轮询状态变化**（`_wait_held`）而不是"注入后等固定帧数"。
##
## ⚠️ 顺带记一条：`InputEventMouseButton` 也"同帧"，但**不用它** ——
## 它带 `position`，会一并喂给 `_input()` 里的准星记录与 UI；`InputEventAction`
## 没有位置、只动那一个动作名，最小侵入。
func _physics_process(_delta: float) -> void:
	_pf += 1
	if Input.is_action_just_pressed("fire_primary"):
		_edge_frames += 1
	for i in range(_pending.size() - 1, -1, -1):
		var e: Array = _pending[i]
		if int(e[0]) <= _pf:
			var down := bool(e[2])
			var ev := InputEventAction.new()
			ev.action = str(e[1])
			ev.pressed = down
			ev.strength = 1.0 if down else 0.0
			Input.parse_input_event(ev)
			_pending.remove_at(i)


## 排一个按键事件：`delay` 个物理帧之后按下 / 松开。
func _inject(act: String, down: bool, delay := 2) -> void:
	_pending.append([_pf + delay, act, down])


## 保证按键处在"未按下"的干净状态。
##
## ⚠️ 只在**确实按下**时才 release：无条件 `Input.action_release()` 会凭空造出
## 一个 `just_released` 边沿 —— 在老路上那就是"白打一发"，把弹匣读数搅浑。
## ⚠️ 松开也是**事件**，要等它真的生效（轮询），别写"等固定帧数"。
func _zero_key(act: String) -> void:
	if not Input.is_action_pressed(act):
		await _frames(2)
		return
	var ev := InputEventAction.new()
	ev.action = act
	ev.pressed = false
	ev.strength = 0.0
	Input.parse_input_event(ev)
	var ok := await _wait_held(act, false)
	print("ZERO %s 已松开=%s" % [act, str(ok)])


## 等按键的**持续态**真的变过去（按下 / 松开生效），不是"等固定帧数"。
##
## ⚠️ **第一件事就是 `await`**（不是先判一次）：先判的话，如果按键在调用时
## **已经**是想要的状态，本函数会在**零帧**内返回 —— 于是调用方紧接着打的那一行
## 读数全是"注入还没被执行"的旧值（实测：`注入器看见边沿 0 帧` 就是这么来的，
## 它看着像"边沿丢了"，其实只是**读得太早**）。
## `from_frame` 用来排除调用之前的脏状态：注入派在某帧，就从那一帧起算。
func _wait_held(act: String, want: bool, from_frame := 0, budget := 60) -> bool:
	for i in budget:
		await get_tree().physics_frame
		if _pf >= from_frame and Input.is_action_pressed(act) == want:
			return true
	return false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	for a: String in args:
		if a == "diag":
			_diag = true
		else:
			out_dir = a
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	var menu = main.get("menu")
	if menu != null and is_instance_valid(menu):
		menu.close_menu()
	await _frames(10)
	main.call("_on_start_match", SuitProfile.Id.PENELOPE, Difficulty.Level.NORMAL,
		MapDef.Id.ULURU, Game.MatchMode.VERSUS)
	await _frames(30)
	main.call("_start_fight")
	await _frames(20)

	var p := _p()
	if p == null:
		push_error("PEN_CANNON_FAILED(no player)")
		get_tree().quit(1)
		return
	_setup_match(p)
	await _settle_camera()

	await _phase_hud_ready(p)
	if _diag:
		await _phase_input_diag(p)
	await _phase_real_input(p)
	await _phase_spray(p)
	await _phase_spray_visual(p)

	Engine.time_scale = 1.0
	print("PEN_CANNON_DONE idx=%d out=%s" % [_idx, out_dir])
	get_tree().quit(0)


## 玩家与敌机的初始状态。
func _setup_match(p: Node) -> void:
	p.max_hp = 99999.0
	p.hp = 99999.0
	p.ifield_max = 9999.0
	p.ifield_hp = 9999.0
	p.rifle_mag = p.profile.rifle_magazine
	p.cannon_cd_left = 0.0
	p.rifle_reloading = false
	p.reload_timer = 0.0

	# ⚠️ 机体不能摆在 y=0：`FlightBody.CRASH_ALTITUDE := 24.0` 会在第一个物理帧
	# 就判"撞海"并 `destroy()` —— 模型被拆走、原地炸开一团爆炸特效，抓到满屏花瓣。
	p.global_position = Vector3(3000.0, 900.0, 1500.0)
	p.fm.velocity = Vector3.ZERO
	p.fm.align_velocity(p.forward())

	p.debug_input_enabled = true
	p.debug_input = Vector3.ZERO
	p.debug_throttle = 0.0
	p.debug_boost = false
	p.debug_hover = false
	# ⚠️ 两个都要 true 才会走"用 aim_cursor 算方向"那条路
	p.mouse_lock_enabled = true
	p.cursor_seen = true

	var e := _e()
	if e != null:
		e.max_hp = 99999.0
		e.hp = 99999.0
		e.ifield_max = 0.0
		e.ifield_hp = 0.0
		e.flare_count = 0
		e.set_physics_process(false)
		e.fm.velocity = Vector3.ZERO
	print("PEN_CANNON profile=%s mag=%d magazine=%d cannon_ready=%s 敌机=%s"
		% [p.profile.display_name, p.rifle_mag, p.profile.rifle_magazine,
			str(p.cannon_ready()), str(e != null)])


# ============================================================ P3a HUD「就绪」

func _phase_hud_ready(p: Node) -> void:
	print("---- P3a HUD：满弹匣（应显示「蓄力炮（长按）」+「就绪」）----")
	var e := _e()
	if e != null:
		_aim_at(p, e.global_position)
	await _frames(3)
	print("HUD_READY cannon_available=%s cannon_ready=%s cd=%.2f reload=%s"
		% [str(p.cannon_available()), str(p.cannon_ready()), p.cannon_cd_left,
			str(p.rifle_reloading)])
	await _shot("01_hud_ready")


# ============================================================ PD 输入链路逐帧诊断

## ★ 轮 47：把「注入 → 玩家看见边沿」这条链**逐帧摊开印**。
##
## 为什么要有它：P1 曾经读出「按下生效=true 但 `rifle_press_is_cannon()` 恒 false」，
## 看着像"路由没接上 / 边沿丢了"，其实是**读数太早**（`_wait_held` 零帧返回）。
## 这一段的判据是**玩家的锁存值**（`p.rifle_press_is_cannon()`）—— 它由玩家自己的
## `_physics_process` 写，探针读到什么都会如实反映 ⇒ 不会自我欺骗。
##
## 归零那一步不是装饰：`pressed` 态与边沿分离的注入方式（`Input.action_press()`）
## 只在 **0→1 跳变**时记帧戳；若按下态是脏的（上一段没松开 / 手动注入过），
## 再按**不会**产生新帧戳 ⇒ 边沿**永远不出现**，而且一声不吭。
func _phase_input_diag(p: Node) -> void:
	print("---- PD 输入链路逐帧诊断 ----")
	p.debug_input_enabled = false
	p.rifle_mag = p.profile.rifle_magazine
	p.rifle_cooldown = 0.0
	p.cannon_cd_left = 0.0
	p.rifle_reloading = false
	p.reload_timer = 0.0
	await _zero_key("fire_primary")
	print("PD 归零 held=%s just=%s just_rel=%s"
		% [str(Input.is_action_pressed("fire_primary")),
			str(Input.is_action_just_pressed("fire_primary")),
			str(Input.is_action_just_released("fire_primary"))])

	var press_frame := _pf + 2
	_inject("fire_primary", true)
	for i in 12:
		await get_tree().physics_frame
		print("PD pf=%d（注入帧 %d） held=%s just=%s | 玩家 latched=%s hold=%.3f mag=%d charging=%s"
			% [Engine.get_physics_frames(), press_frame,
				str(Input.is_action_pressed("fire_primary")),
				str(Input.is_action_just_pressed("fire_primary")),
				str(p.rifle_press_is_cannon()), p.cannon_hold_ratio(),
				p.rifle_mag, str(p.cannon_charging())])
	print("PD 注入器总共在各帧看见按下边沿 %d 次" % _edge_frames)
	_inject("fire_primary", false)
	# ⚠️ 松手也要**真的等到生效**：不等的话这个 `just_released` 会晚几帧落到 P1 里，
	#    把刚复位好的满弹匣又打掉一发（`just_released` 且没在蓄力 ⇒ `_shoot_rifle_now`）。
	await _wait_held("fire_primary", false)
	await _frames(4)
	print("PD 收尾 held=%s latched=%s" % [str(Input.is_action_pressed("fire_primary")),
		str(p.rifle_press_is_cannon())])


# ============================================================ P1 真输入端到端

func _phase_real_input(p: Node) -> void:
	print("---- P1 真输入：满弹匣按住 ⇒ 蓄力 ⇒ 松手放炮 ----")
	var e := _e()
	if e != null:
		e.global_position = p.global_position + p.forward() * 2200.0
	_aim_at(p, p.global_position + p.forward() * 2200.0)
	await _pin(p, 3)

	# ⚠️ 真实输入这一段必须**关掉 debug 输入**：`debug_input_enabled` 时
	#    `_physics_process()` 在读完瞄准方向之后就 `return` 了，
	#    `_read_weapon_input()` **整个不执行** ⇒ 按火键按到天荒地老也不会蓄力。
	p.debug_input_enabled = false
	Input.warp_mouse(Vector2(SHOT_W, SHOT_H) * 0.5)
	# 先归零、**再**复位状态：归零若真的松开了一次"按着的键"，老路会补打一发
	# ⇒ 复位必须放在归零之后，否则"注入那一刻弹匣全满"就不成立了。
	await _zero_key("fire_primary")
	p.rifle_mag = p.profile.rifle_magazine
	p.rifle_cooldown = 0.0
	p.cannon_cd_left = 0.0
	p.rifle_reloading = false
	p.reload_timer = 0.0
	await _frames(3)
	var shots_before: int = Game.beam_shots

	print("CHARGE 注入前提：cannon_ready=%s mag=%d/%d route=%s 归零后held=%s"
		% [str(p.cannon_ready()), p.rifle_mag, p.profile.rifle_magazine,
			str(p.rifle_press_route()), str(Input.is_action_pressed("fire_primary"))])
	_inject("fire_primary", true)
	var held := await _wait_held("fire_primary", true)
	# ★ 注入是**事件**式的（延迟约 4 个物理帧才生效，见 `_physics_process()` 头注），
	#   所以只能**轮询持续态**、不能"注入后等固定帧数"。
	#   这里再等 2 帧让玩家的锁存值落定 —— `_wait_held` 返回的时刻在帧首，
	#   而玩家的 `_physics_process` 还没跑。
	await _frames(2)
	print("CHARGE 按下生效=%s · rifle_press_is_cannon=%s（应为 true）· 注入器看见边沿 %d 帧"
		% [str(held), str(p.rifle_press_is_cannon()), _edge_frames])

	var charged_seen := false
	var fired_while_holding := 0
	for i in 114:                       # 114 / 60 = 1.9 s > 门槛 1.7 s
		await get_tree().physics_frame
		if not charged_seen and p.cannon_charging():
			charged_seen = true
			# ⚠️ 这个秒数是**自本循环起算**的，比"自按住起算"**小几帧** ——
			#    注入是事件式的、要过几帧才生效，而循环从"生效之后"才开始数。
			#    所以它略小于门槛**不是**阈值没满足（`hold_ratio()` 才是自按住起算的，
			#    进蓄力那一刻它必然是 1.000）。别把这两个数混起来读。
			print("CHARGE entered 自循环起算 %.3f s（门槛 %.2f s）· hold_ratio=%.3f"
				% [float(i + 1) / 60.0, p.profile.cannon_charge_time,
					p.cannon_hold_ratio()])
		if i == 54:                     # 0.9 s：**未满**的在长的弧
			print("CHARGE hold_ratio=%.3f charging=%s route_is_cannon=%s fired_so_far=%d"
				% [p.cannon_hold_ratio(), str(p.cannon_charging()),
					str(p.rifle_press_is_cannon()), Game.beam_shots - shots_before])
			await _shot("10_charge_arc")
			await _crop("10b_charge_arc_zoom", 3)
		if i == 108:                    # 1.8 s：已进蓄力态 ⇒ 脉动整环
			print("CHARGE hold_ratio=%.3f charging=%s charged=%.2f s"
				% [p.cannon_hold_ratio(), str(p.cannon_charging()),
					p.cannon_charged_seconds()])
			await _shot("11_charge_full")
			await _crop("11b_charge_full_zoom", 3)
	fired_while_holding = Game.beam_shots - shots_before
	print("CHARGE_RESULT charging=%s（真机：%s）｜全程按住期间打出普通光束 %d 发（应为 0）"
		% [str(p.cannon_charging()), "真" if charged_seen else "**假** —— 输入没接上",
			fired_while_holding])
	print("CHARGE 按住结束时弹匣 = %d / %d（应为满 —— 这就是「按满 1.7 s 时仍然满」）"
		% [p.rifle_mag, p.profile.rifle_magazine])

	_inject("fire_primary", false)
	var freed := await _wait_held("fire_primary", false)
	print("CHARGE 松手生效=%s" % str(freed))
	# ⚠️ **松手之后不能只等一帧就读** —— `is_action_just_released` 只在它**自己那一帧**
	#    为真，与 `_physics_process` 的对齐关系不确定。轮询到真的打出来为止。
	var fired_at := -1
	for i in 10:
		await get_tree().physics_frame
		if p.active_cannon != null:
			fired_at = i
			break
	print("CHARGE release 之后 active_cannon=%s cd=%.2f reload=%s timer=%.2f mag=%d"
		% [str(p.active_cannon != null), p.cannon_cd_left, str(p.rifle_reloading),
			p.reload_timer, p.rifle_mag] + "  松手后第 %d 帧打出来" % (fired_at + 1))
	if fired_at < 0:
		print("CANNON **没打出来**（松手那一帧没被读到 / 门禁拒了）")

	await _frames(10)
	# ⚠️ 柱体的 `dps` / `duration` / `_core` 都用 `.get()` 读：
	#    `active_cannon` 声明成 `Node3D`，直接写 `cd.dps` 对**有类型的变量**是编译错误
	#    （"Cannot find property dps on Node3D"），不是运行时报错 —— 整个探针跑不起来。
	var col: Node3D = null
	if p.active_cannon != null and is_instance_valid(p.active_cannon):
		col = p.active_cannon
	var core: MeshInstance3D = null
	if col != null:
		core = col.get("_core") as MeshInstance3D
	print("CANNON 柱长=%.1f m（MAX_LEN=%.0f）dps=%s duration=%s"
		% [core.scale.y if core != null else -1.0, BeamCannon.MAX_LEN,
			str(col.get("dps")) if col != null else "-",
			str(col.get("duration")) if col != null else "-"])
	await _shot("12_cannon_column")
	await _closeup(p, "13_cannon_muzzle")


# ============================================================ P2 保住连发

## ★ 本段是用户拍板那条口径的**反面证据**：同一套按键、同一时长，
## 只把弹匣打掉一发 ⇒ **一次都不进蓄力**，而且真的在连发。
func _phase_spray(p: Node) -> void:
	print("---- P2 保住连发：弹匣不满按住 ⇒ 不进蓄力、照旧连发 ----")
	# ⚠️ 归零放在**最前面**、状态设置之前：归零若真的松开了一次"按着的键"，
	#    老路会补打一发 ⇒ 之后设的 `rifle_mag - 1` 才是准的。
	await _zero_key("fire_primary")
	var e := _e()
	if e != null:
		e.global_position = p.global_position + p.forward() * 2200.0
	if p.active_cannon != null and is_instance_valid(p.active_cannon):
		p.active_cannon.queue_free()
		p.active_cannon = null
	p.rifle_mag = p.profile.rifle_magazine - 1
	p.rifle_cooldown = 0.0
	p.cannon_cd_left = 0.0
	p.rifle_reloading = false
	p.reload_timer = 0.0
	await _frames(4)
	print("SPRAY 前提：弹匣 %d / %d ⇒ cannon_ready=%s rifle_press_route=%s"
		% [p.rifle_mag, p.profile.rifle_magazine, str(p.cannon_ready()),
			str(p.rifle_press_route())])
	await _shot("20_hud_not_full")

	var shots_before: int = Game.beam_shots
	_inject("fire_primary", true)
	var held := await _wait_held("fire_primary", true)
	# 同上：等玩家的锁存值落定（`_wait_held` 在帧首返回，玩家还没跑）。
	await _frames(2)
	print("SPRAY 按下生效=%s · rifle_press_is_cannon=%s（应为 false —— 不满弹匣）"
		% [str(held), str(p.rifle_press_is_cannon())])
	var charging_seen := false
	for i in 114:
		await get_tree().physics_frame
		if p.cannon_charging():
			charging_seen = true
			print("SPRAY **进了蓄力态**（第 %d 帧）—— 这就是「连发被废掉」的坏法" % (i + 1))
	_inject("fire_primary", false)
	await _wait_held("fire_primary", false)
	await _frames(3)

	var shots: int = Game.beam_shots - shots_before
	print("SPRAY_RESULT 按住 1.9 s：普通光束 %d 发 · 全程进过蓄力=%s（应为 false）· "
		% [shots, str(charging_seen)] + "弹匣 %d / %d"
		% [p.rifle_mag, p.profile.rifle_magazine])
	print("SPRAY 判据：shots >= 2 且 charging_seen == false ⇒ **保住连发**成立；"
		+ "反之（shots == 0 或 charging_seen）就是路由错了")


# ============================================================ P2b 连发的画面

func _phase_spray_visual(p: Node) -> void:
	print("---- P2b 连发的画面（Engine.time_scale = %.2f，否则光束打出去就到了）----" % SLOW_MO)
	var e := _e()
	if e != null:
		# 靶机挪到**侧上方**：正前方的话弹丸几帧就撞上它，连拍还没跑完就没了。
		e.global_position = p.global_position + p.forward() * 1200.0 \
			+ p.global_transform.basis.x * 900.0 + Vector3(0.0, 500.0, 0.0)
		_aim_at(p, e.global_position)
	p.debug_input_enabled = false
	# 归零在前、状态设置在后（见 `_phase_spray` 里同一条注释）。
	await _zero_key("fire_primary")
	p.rifle_mag = p.profile.rifle_magazine - 1
	p.rifle_cooldown = 0.0
	p.cannon_cd_left = 0.0
	p.rifle_reloading = false
	p.reload_timer = 0.0
	await _frames(4)

	Engine.time_scale = SLOW_MO
	_inject("fire_primary", true)
	await _wait_held("fire_primary", true)
	for i in 4:
		await _frames(20)
		await _shot("30_spray_f%d" % i)
	Engine.time_scale = 1.0
	_inject("fire_primary", false)
	await _wait_held("fire_primary", false)
	print("SPRAY_VIS time_scale 已还回 %.2f；弹匣 %d / %d"
		% [Engine.time_scale, p.rifle_mag, p.profile.rifle_magazine])


# ============================================================ 工具

func _p() -> Node:
	var n = main.get("player")
	return n if (n != null and is_instance_valid(n)) else null


func _e() -> Node:
	var n = main.get("enemy")
	return n if (n != null and is_instance_valid(n)) else null


## 让准星指向世界里的某个点。
##
## ⚠️ `aim_cursor` 是**内容坐标**（`get_visible_rect()`），不是窗口尺寸、
## 更不是落盘 PNG 的尺寸（工程设了拉伸，三个量常常互不相等）。
func _aim_at(p: Node, world: Vector3) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null or cam.is_position_behind(world):
		p.aim_cursor = vp.get_visible_rect().size * 0.5
		return
	p.aim_cursor = cam.unproject_position(world)


func _pin(p: Node, n: int) -> void:
	for i in n:
		p.fm.velocity = Vector3.ZERO
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 把相机挪到炮口旁边拍特写（柱根 + 飞溅）。
func _closeup(p: Node, shot_name: String) -> void:
	var mz: Array[Vector3] = p.cannon_muzzles()
	if mz.is_empty():
		print("CLOSEUP 没有炮口")
		return
	var mid := Vector3.ZERO
	for m: Vector3 in mz:
		mid += p.global_transform * m
	mid /= float(mz.size())
	var fwd: Vector3 = p.forward()
	var side: Vector3 = p.global_transform.basis.x
	var cam := Camera3D.new()
	cam.name = "CloseupCam"
	cam.near = 0.5
	cam.far = 90000.0
	cam.fov = 42.0
	add_child(cam)
	cam.global_position = mid - fwd * 42.0 + side * 34.0 + Vector3(0.0, 14.0, 0.0)
	cam.look_at(mid + fwd * 260.0, Vector3.UP)
	cam.current = true
	print("CLOSEUP 炮口 %d 个 mid=%s" % [mz.size(), _v(mid)])
	await _frames(4)
	await _shot(shot_name)
	cam.queue_free()
	var chase = main.get("chase")
	if chase != null and is_instance_valid(chase):
		chase.current = true
	await _frames(3)


func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


## 等追尾相机**追上机体**再开拍（平滑跟随，不等的话相机还挂在十几公里外）。
## 判据是"距离收敛到正常跟随距离"，不是"等固定帧数"。
func _settle_camera(max_frames := 600) -> void:
	var cam = main.get("chase")
	var p := _p()
	if cam == null or p == null:
		return
	var want: float = (cam.offset as Vector3).length()
	var prev := INF
	var stable := 0
	for i in max_frames:
		await get_tree().physics_frame
		if not is_instance_valid(cam):
			return
		var d: float = cam.global_position.distance_to(p.global_position)
		if d < want * 1.6 and absf(d - prev) < 0.35:
			stable += 1
			if stable >= 10:
				print("CAMERA settled 距离=%.1f m（期望 %.1f，用了 %d 帧）" % [d, want, i + 1])
				return
		else:
			stable = 0
		prev = d
	print("CAMERA **没等到就位**（上限 %d 帧）—— 后面的图可能取景不对" % max_frames)


func _grab() -> Image:
	var vp := get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()


## 无头（dummy 渲染器）时 `RenderingServer.frame_post_draw` **永远不来**
## ⇒ 抓图那两处 `await` 会**永久挂住整个探针**（实测：卡死在 P3a 的第一张图上，
## 输出到此为止、进程不退出）。本脚本本来就不该无头跑（见文件头），
## 但**诊断段**要在无头下跑以省时间（输入语义与渲染无关）⇒ 抓图必须能跳过。
func _no_render() -> bool:
	return DisplayServer.get_name() == "headless"


func _shot(shot_name: String) -> void:
	_idx += 1
	if _no_render():
		print("SHOT %s 跳过（无头）" % shot_name)
		return
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null:
		return
	var path := out_dir.path_join("%s.png" % shot_name)
	print("SHOT %s err=%d" % [path, img.save_png(path)])


## 屏幕中心那块**局部放大** —— 蓄力环半径只有 30 px，整屏图里读不出"弧长到几分之几"。
func _crop(shot_name: String, zoom: int) -> void:
	if _no_render():
		print("CROP %s 跳过（无头）" % shot_name)
		return
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null:
		return
	var half := 150
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	var x := clampi(cx - half, 0, maxi(img.get_width() - 1, 0))
	var y := clampi(cy - half, 0, maxi(img.get_height() - 1, 0))
	var w := mini(half * 2, img.get_width() - x)
	var h := mini(half * 2, img.get_height() - y)
	var sub := img.get_region(Rect2i(x, y, w, h))
	sub.resize(w * zoom, h * zoom, Image.INTERPOLATE_NEAREST)
	var path := out_dir.path_join("%s.png" % shot_name)
	print("CROP %s (%dx%d → %dx%d) err=%d"
		% [path, w, h, w * zoom, h * zoom, sub.save_png(path)])
