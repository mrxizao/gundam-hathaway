extends Node
## 一次性探针 —— **不是套件**，故意不注册进 `tests/test_runner.gd` 的 `SUITES`。
##
## 目的：取「**按住拦截键的时候会突然发射特别多的导弹**」这条 bug 的**实测证据**，
## 而不是靠读码推断。探针直接驱动生产的 `_read_weapon_input()`（不走任何替身），
## 只是把 `_physics_process` 关掉、改成按固定 `DT` 手动步进，让"每秒打了几发"可数。
##
## 跑法：
##   "C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" --headless \
##       --path "C:/Users/MSIPC/Documents/gundam" res://tests/_probe_overfire.tscn
##
## 三个阶段（同一台机、同一个锁定、同一个威胁缓存，只改"按了哪些键"）：
##   A 只按住拦截键（手柄 L1 = `fire_secondary`）…… 应有节奏：0.42 s 一梭
##   B **同时**按住拦截 + 浮游导弹（手柄 L2 = `fire_missile`）…… ← 怀疑点
##   C 只按浮游导弹（松掉拦截，作对照）…… 应有节奏：0.42 s 一梭

const DT := 1.0 / 60.0


func _ready() -> void:
	await _run()


func _run() -> void:
	Game.reset()
	var c := Node3D.new()
	add_child(c)

	var pc := PlayerController.new()
	pc.team = 1
	pc.is_player = true
	pc.profile = SuitProfile.xi()
	pc.projectile_container = c
	c.add_child(pc)
	pc.global_position = Vector3(0, 3000, 0)
	pc.fm.speed = 260.0
	pc.fm.throttle = 0.78
	pc.fm.align_velocity(pc.forward())
	# 手动步进：`_think()` 需要 camera，绕开它，只驱动我们关心的那几个函数
	pc.set_physics_process(false)
	# 排除"弹夹打空 → 自动换弹"这条干扰（一次扳机 3 发，150 发的夹子几帧就空）
	pc.funnel_count = 1000000
	pc.cursor_seen = false                 # 手柄玩家的常态
	InputSetup.using_gamepad = true        # ⇒ `_intercept_pad_mode()` == true

	# 敌机：lock 的 `target` 要求 `FlightBody`（不是普通 Node3D）
	var foe := FlightBody.new()
	foe.team = 2
	foe.profile = SuitProfile.gustav00()
	c.add_child(foe)
	foe.global_position = Vector3(0, 3000, -2200)
	foe.set_physics_process(false)

	var lk := LockOnSystem.new()
	lk.lock_time = 0.05
	c.add_child(lk)
	lk.setup(pc)
	pc.lock = lk

	# 喂到稳定锁定（`locked` 是派生量，只能靠时间喂，不能直接写）
	var guard := 0
	while not lk.locked and guard < 2000:
		lk._physics_process(DT)
		guard += 1
	print("[probe] 锁定 fed_frames=", guard, " locked=", lk.locked,
		" target_is_foe=", lk.target == foe)
	if not lk.locked:
		print("[probe] !! 锁定没喂出来，后面无意义 —— 终止")
		get_tree().quit()
		return

	# 威胁缓存（自动拦截要"挑一枚最危险的、还没被咬住的"）
	var threats: Array = []
	for i in 3:
		threats.append(_threat(c, pc, foe, Vector3(-500.0 + 500.0 * float(i), 3000.0, -1500.0)))
	_fill_cache(pc, threats)

	print("[probe] funnel_interval=", pc.profile.funnel_interval,
		" MISSILE_PER_SHOT=", SuitProfile.MISSILE_PER_SHOT,
		" SHOT_INTERVAL=", InterceptAuto.SHOT_INTERVAL)

	# ---------------------------------------------------------------- A 只按拦截
	Input.action_press("fire_secondary")
	var a0 := pc.funnel_count
	for _i in 150:                                  # 2.5 s
		_step(pc, lk, DT)
	var a_n := a0 - pc.funnel_count
	print("[probe A] 只按拦截 2.5s → 导弹=", a_n, " 扳机=", a_n / 3,
		" (期望 ≈ 6)  active=", pc.get("_intercept_auto").active)

	# ------------------------------------------------- B 拦截 + 浮游（同时按住）
	Input.action_press("fire_missile")
	_fill_cache(pc, threats)
	var b0 := pc.funnel_count
	for _i in 60:                                   # 1.0 s
		_step(pc, lk, DT)
	var b_n := b0 - pc.funnel_count
	print("[probe B] 拦截+浮游 1.0s → 导弹=", b_n, " 扳机=", b_n / 3,
		" (期望 ≈ 2.4)  active=", pc.get("_intercept_auto").active)
	Input.action_release("fire_missile")
	Input.action_release("fire_secondary")

	# ---------------------------------------------------------------- C 只按浮游
	var c0 := pc.funnel_count
	Input.action_press("fire_missile")
	for _i in 60:                                   # 1.0 s
		_step(pc, lk, DT)
	var c_n := c0 - pc.funnel_count
	print("[probe C] 只按浮游 1.0s → 导弹=", c_n, " 扳机=", c_n / 3,
		" (期望 ≈ 2.4)  active=", pc.get("_intercept_auto").active)
	Input.action_release("fire_missile")

	# ------------------------------------------------- D 设备中途切换（鼠标一动）
	#
	# 复现链：按住 L1 进自动拦截 → **鼠标一动**（`cursor_seen` 变真、InputSetup 切回键鼠）
	# ⇒ `_intercept_pad_mode()` 变假 ⇒ `_tick_pad_intercept()` **不再被调用**
	# ⇒ `_intercept_auto` 永远拿不到 `reset()` ⇒ **`active` 卡住**。
	# 之后玩家只按 F（键盘的浮游导弹键）—— 若 `active` 卡住，`salvo` 恒为 0 ⇒ 每帧一梭。
	Input.action_press("fire_secondary")
	for _i in 60:                                   # 先按住 1 s，进自动模式
		_step(pc, lk, DT)
	print("[probe D] 切换前 active=", pc.get("_intercept_auto").active)
	pc.cursor_seen = true                           # ← 鼠标一动
	InputSetup.using_gamepad = false                # ← InputSetup 切回键鼠
	Input.action_release("fire_secondary")          # 松掉拦截键
	for _i in 30:                                   # 再空跑 0.5 s（这段已经走键鼠分支）
		_step(pc, lk, DT)
	var stuck: bool = pc.get("_intercept_auto").active
	print("[probe D] 松手 + 已切键鼠 0.5s 后 active=", stuck,
		"  (True ⇒ **卡住**，说明没人再调 reset()）")

	var d0 := pc.funnel_count
	Input.action_press("fire_missile")              # 只按 F / L2
	for _i in 60:                                   # 1.0 s
		_step(pc, lk, DT)
	var d_n := d0 - pc.funnel_count
	print("[probe D] 只按浮游 1.0s → 导弹=", d_n, " 扳机=", d_n / 3,
		" (若 ≈2.4 ⇒ 正常；若 ≈60 ⇒ **单键也能炸**）")
	Input.action_release("fire_missile")

	# ------------------------------------------------- E 长按 12 s，看会不会自己加速
	InputSetup.using_gamepad = true
	pc.cursor_seen = false
	Input.action_press("fire_secondary")
	var per := []
	for sec in 12:
		var e0 := pc.funnel_count
		for _i in 60:
			_step(pc, lk, DT)
		per.append((e0 - pc.funnel_count) / 3)
	Input.action_release("fire_secondary")
	print("[probe E] 长按 12s 每秒扳机次数=", per, " (应恒 ≈2.4)")

	print("[probe] ==== 判读 ====")
	print("  A 应有 0.42 s 节奏 · B >> 2.4 ⇒ 共用 salvo 导致每帧一梭")
	print("  D active 卡住 ⇒ 单键（只按浮游）也会炸")

	pc.free()
	foe.free()
	c.free()
	await get_tree().process_frame
	get_tree().quit()


## 一帧：把生产路径里与该 bug 相关的三件事按 `_think()` 的真实顺序跑一遍。
func _step(pc: PlayerController, lk: LockOnSystem, dt: float) -> void:
	pc.call("_tick_weapons", dt)       # 冷却递减（生产里在 `_think()` 内）
	pc.call("_read_weapon_input", dt)  # ← 被测代码
	pc.call("_tick_threats", dt)       # 武装（必须在发扳机之后）
	lk._physics_process(dt)


func _threat(c: Node3D, pc: Node3D, foe: Node3D, at: Vector3) -> Missile:
	var th := Missile.new()
	th.shooter = foe
	th.target = pc
	th.speed = 800.0
	c.add_child(th)
	th.global_position = at
	return th


func _fill_cache(pc: PlayerController, threats: Array) -> void:
	var cache: Array = []
	for i in threats.size():
		cache.append({"missile": threats[i], "tti": 1.0 + float(i), "dist": 1500.0})
	pc.set("_threats_cache", cache)
