extends Node
## 轮 11 交付用：把「普通加力尾焰（形态 A）」与「辅助冲刺尾焰（形态 B）」
## 抓成 PNG —— 用像素说明"两种形态真的不一样"。
##
## ## 为什么需要它
##
## 用户要求："尾焰在正常加速的时候和辅助驾驶模式时候冲刺的尾焰形态不同，要做区分"。
## 这句话的最终验收标准是**屏幕上看到的东西**，不是代码里的参数表 ——
## 逻辑回归（`suite_fx_plume`）能钉住"两形的锥角/曲线/材质分开了"，
## 但它钉不住"看上去是不是真的两种东西"。所以这里把真实渲染帧抓下来。
##
## ## 机位为什么是侧后方
##
## 正对机尾只能看到"一堆光点叠在一起"，分不出"锥"与"束"；
## 侧剖面才看得出粗细与长宽比。所以相机摆在机尾的**侧后 60°、高 26 m**，
## 用 42° 的长焦把尾焰拉满画面。
##
## ## 剧本（固定条件）
##   · 开 1v1（柯西 vs 佩涅罗佩，太平洋图）—— 背景最干净的一张图；
##   · 停 `Main` 的 process：不然 AI / 位置修正会每帧改画面；
##   · 玩家**逐帧回钉**位置与姿态（`_apply_translate` 会真的把它飞出去）；
##   · 同一个机位、同一姿态、同一速度，**只切冲刺状态**。
##
## ## 跑法（**不能加 --headless**，headless 是 dummy 渲染器，抓出来是空的）
##   godot --path <工程> res://tools/plume_shot.tscn -- <输出目录> <tag>

const SHOT_W := 1600
const SHOT_H := 900
## 切状态之后让粒子积累多久（秒）。两形最长的 lifetime 是 0.30 s，0.6 s 足够换代。
const SETTLE := 0.6

var main: Node
var out_dir := "user://captures"
var tag := "plume"

var _pin_pos := Vector3(0.0, 6000.0, 0.0)
var _pin_fwd := Vector3(0.0, 0.0, -1.0)
var _pin := Vector3.ZERO
var _p: Node = null
## 抓图期间是否把 `_qb_timer` 每帧顶回去（"停在冲刺状态上"，见 pass B 的说明）。
var _dash_pin := false
## 该机的实际巡航速度（**实际域**，自己跟着倍率走）。
var _cruise := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		tag = args[1]
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

	# 停主场景：否则 AI 每帧动、位置每帧被修正，两张图之间会掺进无关差异。
	main.set_physics_process(false)
	main.set_process(false)

	_p = main.get("player")
	if _p == null or not is_instance_valid(_p):
		print("PLUME_FAILED(no player)")
		get_tree().quit(1)
		return
	_p.max_hp = 99999.0
	_p.hp = 99999.0
	_p.ifield_max = 9999.0
	_p.ifield_hp = 9999.0
	# ⚠️ **必须走 debug 输入通道，不能直接写 `fm.boosting`。**
	# `PlayerController._read_flight_input()` 每帧拿**真实按键**重写
	# `fm.boosting = Input.is_action_pressed("boost")` —— 探针里没人按 Shift，
	# 于是手写的 `true` 下一帧就被抹成 false（第一版实测：三个 pass 全部
	# `emitting=F`，看上去像"特效没接线"，其实是"状态被输入层覆盖了"）。
	#
	# debug 分支还有一个恰好需要的性质：它在读输入**之前**就 `return`，
	# 所以 `translate_mode = assist_on and ...` 那行每帧不会重写 —— 探针可以
	# 自己按住"辅助平移模式"这个状态（见下面的 pass B）。
	_p.set("debug_input_enabled", true)
	_p.set("debug_input", Vector3.ZERO)
	_p.set("debug_throttle", 0.75)
	_p.set("debug_boost", true)
	_p.set("debug_hover", false)

	# 敌机挪到远处并冻住：它出现在画面里只会干扰对尾焰的读数。
	var e = main.get("enemy")
	if e != null and is_instance_valid(e):
		e.set_physics_process(false)
		e.set_process(false)
		e.fm.velocity = Vector3.ZERO
		e.fm.speed = 0.0
		e.global_position = _pin_pos + Vector3(0, 0, 9000)

	_hide_ui()
	_place_cam()

	_cruise = _p.profile.player_top_speed()
	_repin()

	# ---- 形态 A：普通加力（不辅助，按住 Shift）----
	_dash_pin = false
	_p.translate_mode = false
	_p.translate_dash = false
	_p.set("_qb_timer", 0.0)
	_p.fm.super_boost = false
	_p.set("debug_boost", true)
	await _settle(SETTLE)
	await _report("A 普通加力")
	await _shot("%s_A" % tag)

	# ---- 形态 B：辅助驾驶的闪避冲刺（平移模式 + QB 窗口）----
	# ⚠️ 必须**每帧**把 `_qb_timer` 顶回去：`_apply_translate` 每帧
	# `_qb_timer -= delta` 并用 `translate_dash = _qb_timer > 0` 重算这个字段，
	# 只设一次的话 0.45 s 后就自然结束了（那正是 QB 的设计），
	# 而我们要的是"停在冲刺状态上"给抓图用。
	_dash_pin = true
	_p.translate_mode = true
	_p.set("_qb_timer", FlightBody.QB_TIME)
	await _settle(SETTLE)
	await _report("B 辅助冲刺")
	await _shot("%s_B" % tag)

	# ---- 切回形态 A：证明是**双向**可切，不是"冲过一次就回不来"----
	_dash_pin = false
	_p.translate_mode = false
	_p.translate_dash = false
	_p.set("_qb_timer", 0.0)
	_p.set("debug_boost", true)
	await _settle(SETTLE)
	await _report("A' 切回普通加力")
	await _shot("%s_A2" % tag)

	print("PLUME_DONE -> ", out_dir)
	get_tree().quit(0)


## 把当前三个发射器的状态打出来 —— 图之外的第二份证据
##（万一图看起来"差不多"，先看这里是不是真的切过去了）。
func _report(what: String) -> void:
	var ab: GPUParticles3D = _p.get("_afterburner_fx")
	var dash: GPUParticles3D = _p.get("_dash_fx")
	var rings: GPUParticles3D = _p.get("_dash_rings")
	print("[plume_shot] %-14s | 形态A emitting=%s ratio=%.2f | 形态B emitting=%s ratio=%.2f speed=%.2f | 环=%s"
		% [what,
			"T" if ab != null and ab.emitting else "F",
			ab.amount_ratio if ab != null else -1.0,
			"T" if dash != null and dash.emitting else "F",
			dash.amount_ratio if dash != null else -1.0,
			dash.speed_scale if dash != null else -1.0,
			"T" if rings != null and rings.emitting else "F"])


## 逐帧回钉：位置 / 朝向 / 速度。
## `_apply_translate` 是**真的会推速度**的（冲刺档 target = 加力极速 × 1.45），
## 不回钉的话机子几帧就飞出画面了。
func _repin() -> void:
	if _p == null or not is_instance_valid(_p):
		return
	_p.global_position = _pin_pos
	_p.look_at(_pin_pos + _pin_fwd, Vector3.UP)
	_p.fm.speed = _cruise
	_p.fm.velocity = _pin_fwd * _cruise
	# 冲刺态要每帧顶 `_qb_timer`（它每帧被 `_apply_translate` 减 delta）。
	if _dash_pin:
		_p.set("_qb_timer", FlightBody.QB_TIME)


## 等**真实时间**（不是帧数）：无头/窗口模式的帧率不可控，而粒子是按时间衰减的。
func _settle(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().physics_frame
		_repin()


## 藏掉所有 2D UI：HUD / 速度线会盖在机体与尾焰上。
func _hide_ui() -> void:
	for key in ["hud", "speed_lines"]:
		var n: Node = main.get(key)
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	var menu = main.get("menu")
	if menu is CanvasItem:
		(menu as CanvasItem).visible = false


## 相机：机尾**正侧方**（+右 118 m、高 12 m），48° 焦距，看向机尾后方 18 m。
##
## ⚠️ 必须是**正侧**，不能是侧后：尾焰沿机尾轴向（`+Z` = 机头反向）喷出，
##    相机若摆在轴向的后方，看到的是"迎面而来的一束光点"——粗细与长度全被透视压掉，
##    形态 A 与形态 B 在那种机位下**几乎一样**（第一版就是这个错）。
##    正侧方看的是**侧剖面**：粗锥和细束一眼分得开。
##
## ⚠️ 必须 `set_process(false)` 之后再摆位 —— `ChaseCamera` 每帧会按 FOV 档与
##    目标位置重算机位，不关掉的话这里设的下一帧就被它覆盖。
func _place_cam() -> void:
	var cam: Node = main.get("chase")
	if not (cam is Camera3D):
		return
	var c3 := cam as Camera3D
	c3.set_physics_process(false)
	c3.set_process(false)
	var right := _pin_fwd.cross(Vector3.UP).normalized()
	var tail := _pin_pos - _pin_fwd * 28.0
	c3.global_position = tail + right * 118.0 + Vector3.UP * 12.0
	# 看向"机尾往后 18 m"处 —— 尾焰的重心，两形都在这一带展开。
	c3.look_at(tail - _pin_fwd * 18.0, Vector3.UP)
	c3.fov = 48.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	# 抓图前最后钉一次：`_settle` 退出之后到真正取像素之间可能又过了一两个物理帧，
	# 期间 `_apply_translate` 会把机体推走（位置/机头都会变）。
	_repin()
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
