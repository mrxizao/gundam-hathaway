extends Node
## **锁定系统重修**（轮 36）的真机判据图台。
##
## ## 要证明的四件事
##
## 用户原话：「锁定系统重修，**除非玩家手动切换锁定，不然不会自动切换锁定对象**」。
##
##   ① 打掉锁定对象之后，火控**不自己咬下一个** —— 屏上那个粗框消失
##   ② 而且它是**稳态**：等大半秒仍然没有（不是"晚一帧就好了"）
##   ③ 组内其余成员**一个都没丢**（它们的细框还在）；玩家按一下 Tab 立刻切过去
##   ④ 光标扫到别人身上**不会**换锁定对象（鼠标只管准星）
##
## ## 跑法
##
## ```
## godot --path <工程> res://tools/capture_lock36.tscn -- <输出目录>
## ```
##
## ⚠️ **不能加 `--headless`** —— 无头用的是 dummy 渲染器，一个像素都不产生，
## 抓出来是全黑。这个脚本的全部意义就是**能真的看到**。
##
## ## 构造上的讲究（每一处都是踩过才知道的）
##
## · **靶机不用 AI，直接造裸 `FlightBody`**：本轮要证明的是 HUD 与锁定系统的行为，
##   而 AI 会飞、会开火、会把画面搅乱。裸机体照样被渲染、照样进 `Game.live_hostiles_of`、
##   照样被 HUD 画框 —— 判据的成色一点不少。
## · **靶机必须 `set_physics_process(false)`**：`FlightBody` 的物理帧里有飞行积分，
##   不关的话三台"静止靶"会在两秒内一起坠海。
## · **不能开 `debug_input_enabled`**：`PlayerController._read_input()` 的 debug 分支
##   是**直接 return** 的 —— 开了之后 Tab 那条路根本不跑，第 ③ 张图会假绿。
##
## ## ★ 玩家机怎么"钉死"（第一版在这里翻过车）
##
## 第一版只锁了**位置**（在 `await physics_frame` 之后赋值），结果：
##
## · `physics_frame` 信号是在 `_physics_process()` **之前**发的 —— 我的赋值
##   **紧接着就被玩家机自己的物理帧覆盖**，等于没锁；
## · 玩家机于是原地**持续转弯**（开场还在俯冲），三台靶机从画面中央一路飘到
##   `x = 1976 / 1760 / 1578`（1600 宽的屏，全在视口外）—— **一张图都读不出来**。
##
## 现在的做法：**在 `_process()` 里锁「完整变换」**（位置 + 朝向，且朝向被水平化）。
##
## · `_process()` 在物理帧**之后**、绘制**之前**跑 ⇒ 赋值活到渲染；
## · 本节点是 `main` 的**父节点** ⇒ 树序在前 ⇒ 相机（`main` 的子树）读到的就是我设的值；
## · 朝向水平化：第一版截到的玩家机是 **PITCH −43.5° 俯冲**，靶机按 `forward()` 摆
##   就会跟着往地下扎；水平化之后相机平视，靶机摆在正前方同一高度，必然在画面里。
##
## ⚠️ **不能图省事直接 `p.set_physics_process(false)`** —— 那样 `_read_input()` 也不跑，
## 第 ③ 张图（按 Tab）就是假绿。这跟 `debug_input_enabled` 是**同一个坑的两种形状**。
##
## ## 靶机摆多近（第二处翻车）
##
## 第一版 `AHEAD = 2600`（米），机身投影高度只有 ~5 px，HUD 那个"粗框 / 细框"
## 根本分不出来 ⇒ 判据图等于废图。现在 `AHEAD = 250`：机身 ~50 px、三台横向间距 ~350 px，
## 框一眼能认。
##
## ## 为什么 versus 那台真敌机要挪到 60 km 外
##
## 它的 `destroyed` 信号连着"击坠即胜"。本台要当着它的面击坠三台靶机里的一台 ——
## 留着它，打掉 A 的那一刻会直接进结算，后面三张图全拍不成。
## 挪到射程（46 575 m）之外 + 冻住，它就既不参战也不会被判胜负。

const SHOT_W := 1600
const SHOT_H := 900
## 三台靶机的横向间距（米）。太近的话三个框会叠在一起，图上读不出来。
const SPACING := 140.0
## 靶机摆在机头正前方多远（米）。**必须够近**，否则机身只有几个像素，
## HUD 的粗框 / 细框在图上分不出来（见文件头的第二处翻车）。
const AHEAD := 250.0
## 钉玩家机时的最低高度（米）。ULURU 有山，拔到 1500 m 平视就不会被地形挡住。
const CLIMB_Y := 1500.0

var main: Node
var out_dir := "user://captures_lock36"
var foes: Array[FlightBody] = []
## 玩家机被钉在哪个变换上（`_process()` 每帧恢复，见文件头）。
var _home_xform := Transform3D.IDENTITY
var _hold := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	# 直接进 1v1：判据图要的是"战斗中的 HUD"，不是菜单。
	var menu = main.get("menu")
	if menu != null and is_instance_valid(menu):
		menu.close_menu()
	await _frames(10)
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.ULURU, Game.MatchMode.VERSUS)
	await _frames(30)
	main.call("_start_fight")

	var p := _p()
	if p == null:
		push_error("CAPTURE_LOCK36_FAILED(no player)")
		return
	p.max_hp = 99999.0
	p.hp = 99999.0
	p.ifield_max = 9999.0
	p.ifield_hp = 9999.0

	_park_enemy()
	# 先让玩家机飞完开场（这时候它在俯冲），再把它的**完整变换**钉死。
	await _frames(150)
	_home_xform = _level_xform(p)
	_hold = true
	await _frames(20)
	await _settle_camera()

	# ---- 三台靶机：左 B / 中 A / 右 C，摆在**相机正前方同一高度** ----
	var bs: Basis = _home_xform.basis
	var fwd: Vector3 = -bs.z
	var right: Vector3 = bs.x
	var names := ["B", "A", "C"]
	for i in 3:
		var dx := (float(i) - 1.0) * SPACING
		foes.append(_spawn_foe(fwd * AHEAD + right * dx, names[i]))
	await _frames(20)

	var lk = main.get("player_lock")
	if lk == null:
		push_error("CAPTURE_LOCK36_FAILED(no lock)")
		return

	# 进场自动接战（玩家火控只允许一次）会把正前方那台接上。
	# 等它把质量条涨满 —— 这一等同时也验证了需求 ③ 的前半句。
	await _frames(120)
	_log_state("00_before")

	# ⚠️ 用 `lk.target`（**实际**被自动锁上的那台），不要写死 `foes[1]` ——
	# 候选表头是谁由 `LockOnSystem` 的排序决定，本台不该假设。
	var a: FlightBody = lk.target
	if a == null:
		print("LOCK36 ⚠️ 自动接战没发生，退回手动选中间的 A")
		a = foes[1]
		lk.select_target(a)
		await _frames(30)
	print("LOCK36 auto-engaged = %s" % str(a.display_name))

	# ---- 把其余两台锁进组（等价于玩家长按 Tab，走的是同一个 `add_lock`）----
	for fb in foes:
		if fb == a or lk.lock_group.has(fb):
			continue
		print("LOCK36 add_lock(%s)=%s" % [fb.display_name, str(lk.add_lock(fb))])
		await _frames(30)                  # > ADD_LOCK_COOLDOWN
	await _frames(90)                      # 等它们把质量条涨满
	await _settle_camera()
	await _frames(10)

	await _shot("10_lock_A")
	_log_state("10_lock_A")

	# ---- 打掉锁定对象 A ----
	# ⚠️ 第一版直接 `take_damage(99999)`，结果 `A alive=true` —— 伤害被 **I 力场**
	# 吃掉了（`_apply_damage()` 第 1 层：护盾没碎之前机体一滴血不掉）。
	# 所以先把护盾清零再打；万一还有别的门（无敌帧 / 无限血）挡着，再落 `destroy()` 兜底。
	print("LOCK36 kill probe: ifield=%.0f invul=%s alive=%s"
		% [a.ifield_hp, str(a.is_invulnerable()), str(a.alive)])
	a.ifield_hp = 0.0
	a.take_damage(1.0e9, p)
	await _frames(2)
	if is_instance_valid(a) and a.alive:
		print("LOCK36 take_damage 没打掉 → 落 destroy()")
		a.destroy(p, "capture_kill")
	await _frames(8)
	await _shot("11_after_kill_A")
	_log_state("11_after_kill_A")

	# ---- 稳态：再等大半秒 ----
	await _frames(40)
	await _shot("12_still_empty")
	_log_state("12_still_empty")

	# ---- 玩家手动按一下 Tab ----
	_press("switch_target")
	await _frames(8)
	await _shot("13_after_tab")
	_log_state("13_after_tab")

	# ---- 光标扫到另一台靶机上（鼠标只管准星，不该换锁定对象）----
	_move_mouse_to(foes[2])
	await _frames(10)
	await _shot("14_mouse_over_C")
	_log_state("14_mouse_over_C")

	print("CAPTURE_LOCK36 done → %s" % out_dir)


## 每渲染帧把玩家机钉回 `_home_xform`。
##
## **必须在 `_process` 而不是 `await physics_frame` 之后**：后者拿到的赋值会被
## 玩家机自己的 `_physics_process()` 覆盖（见文件头）。
##
## 顺带清掉速度：玩家机"静止"的话 HUD 速度读数也是 0，图更好读。
func _process(_delta: float) -> void:
	if not _hold:
		return
	var p := _p()
	if p == null:
		return
	p.global_transform = _home_xform
	p.fm.velocity = Vector3.ZERO
	p.fm.speed = 0.0


# ------------------------------------------------------------ 场景构造

## 把玩家机的**当前水平朝向**抬到 `CLIMB_Y`，并把俯仰归零 —— 得到一个"平视前方"的姿态。
##
## 不水平化的话，开场俯冲的 **PITCH −43.5°** 会一路传到靶机位置（靶机是按
## `forward()` 摆的），三台一起往地下扎，图上看不见。
func _level_xform(p: Node3D) -> Transform3D:
	var f: Vector3 = -p.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 1.0e-6:
		f = Vector3.FORWARD
	f = f.normalized()
	var z: Vector3 = -f
	var x: Vector3 = Vector3.UP.cross(z).normalized()
	var origin: Vector3 = p.global_position
	origin.y = maxf(origin.y, CLIMB_Y)
	return Transform3D(Basis(x, Vector3.UP, z), origin)


## 把 versus 那台真敌机挪到射程之外并冻住（见文件头的理由）。
func _park_enemy() -> void:
	var e = main.get("enemy")
	var p := _p()
	if e == null or not is_instance_valid(e) or p == null:
		return
	e.set_physics_process(false)
	e.fm.velocity = Vector3.ZERO
	e.fm.speed = 0.0
	# 放到**机尾方向** 60 km：相机朝前看，它就一定不在画面里（放前方会留一个远点）。
	e.global_position = p.global_position - p.forward() * 60000.0
	print("LOCK36 parked real enemy at %s" % str(e.global_position))


## 造一台**静止**靶机（裸 `FlightBody`，不挂 AI）。
##
## ⚠️ `profile` / `team` / `is_player` / `projectile_container` 必须在 `add_child()` **之前**
## 设好 —— `FlightBody._ready()` 会读它们决定进哪个分组、加载哪个模型。
func _spawn_foe(offset: Vector3, nm: String) -> FlightBody:
	var p := _p()
	var f := FlightBody.new()
	f.name = "Target%s" % nm
	f.team = 1
	f.is_player = false
	f.profile = SuitProfile.by_id(SuitProfile.Id.PENELOPE)
	f.display_name = nm
	f.projectile_container = main.get("projectiles")
	var root = main.get("units_root")
	root.add_child(f)
	f.global_position = p.global_position + offset
	f.max_hp = 99999.0
	f.hp = 99999.0
	f.invincible = false
	# 冻住：`FlightBody` 的物理帧里有飞行积分，不关的话"静止靶"两秒内就坠海了。
	f.set_physics_process(false)
	f.fm.velocity = Vector3.ZERO
	f.fm.speed = 0.0
	return f


# ------------------------------------------------------------ 读数

func _log_state(tag: String) -> void:
	var lk = main.get("player_lock")
	if lk == null:
		print("LOCK36 %-18s lock=null" % tag)
		return
	var tn := "-"
	var t = lk.target
	if t != null and is_instance_valid(t):
		tn = str(t.display_name)
	var members := ""
	for fb in lk.lock_group:
		members += "%s[tier=%d,slot=%d] " % [fb.display_name, lk.tier_of(fb), lk.group_index(fb)]
	var cands := ""
	for fb in lk.candidates:
		cands += str(fb.display_name) + " "
	print("LOCK36 %-18s target=%s locked=%s group=%d cand=[%s] members=[%s] lost=%s"
		% [tag, tn, str(lk.locked), lk.lock_group.size(), cands, members, str(lk.last_lost_reason)])
	for fb in foes:
		if is_instance_valid(fb):
			var sp := _screen_of(fb)
			print("LOCK36     %s alive=%s screen=(%d,%d)"
				% [fb.display_name, str(fb.alive), int(sp.x), int(sp.y)])


func _screen_of(fb: FlightBody) -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return Vector2.ZERO
	return cam.unproject_position(fb.global_position)


# ------------------------------------------------------------ 输入

## **走 `InputMap` 里的真动作**，而不是直接叫 `LockOnSystem.cycle_target()`。
##
## 直接叫方法就绕过了 `PlayerController` 那一层（`is_action_just_pressed("switch_target")`）
## —— 那样拍出来的图证明不了"玩家按 Tab 会怎样"，只证明"这个方法本身没问题"。
func _press(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(2)


## 把系统光标挪到某台靶机上（顺带兜底写 `aim_cursor`，窗口没抓焦点时 `warp_mouse` 不发事件）。
func _move_mouse_to(fb: FlightBody) -> void:
	var sp := _screen_of(fb)
	Input.warp_mouse(sp)
	var p := _p()
	if p != null:
		p.aim_cursor = sp
		p.cursor_seen = true
	await _frames(2)
	print("LOCK36 mouse → %s at %s" % [fb.display_name, str(sp)])


# ------------------------------------------------------------ 工具（与 tools/capture_fpv.gd 同源）

func _p() -> Node:
	var n = main.get("player")
	return n if (n != null and is_instance_valid(n)) else null


## 等物理帧。玩家机的钉住由 `_process()` 负责（见文件头），这里只管等。
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


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
		var pp := _p()
		if pp == null or not is_instance_valid(cam):
			return
		var d: float = cam.global_position.distance_to(pp.global_position)
		if d < want * 1.6 and absf(d - prev) < 0.35:
			stable += 1
			if stable >= 10:
				return
		else:
			stable = 0
		prev = d


func _grab() -> Image:
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport)")
		return null
	var tex := vp.get_texture()
	if tex == null:
		print("SHOT_FAILED(no texture)")
		return null
	var img := tex.get_image()
	if img == null:
		print("SHOT_FAILED(no image)")
		return null
	return img


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null:
		return
	var path := out_dir.path_join("%s.png" % name)
	var err := img.save_png(path)
	print("SHOT %s  err=%d" % [path, err])
