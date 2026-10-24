extends Node
## 轮 10 交付用：把「巡航状态下的 HUD 速度读数」抓成 PNG。
##
## ## 为什么需要它
## 本轮把 `SuitProfile.SPEED_REAL_MULT` 从 1.5 提到 2.4（机体**实际**速度 ×1.6），
## 而用户的要求是「前端数据根据提升的量同步下调，和现在保持差不多的数值」。
## 这句话的最终验收标准是**屏幕上那个数**，不是代码里的公式 ——
## 所以这里把真实渲染帧抓下来，用像素说话。
##
## ## 判据
## 同一剧本跑两遍（倍率 1.5 / 倍率 2.4），两帧在**速度读数那一块**应当逐像素相同。
## 机体位置/朝向/速度都被钉成常量 ⇒ 除了速度读数，画面其余部分也应当几乎不动，
## 所以本探针额外做一次「全帧」对比，用来确认"只有该变的变了"。
##
## ## 跑法（**不能加 --headless**，headless 是 dummy 渲染器，抓出来是空的）
##   godot --path <工程> res://tools/hud_speed_shot.tscn -- <输出目录> <tag>
##
## ## 剧本为什么这么写
##   · 开 1v1（柯西 vs 佩涅罗佩，太平洋图）—— 太平洋是最平的一张图，
##     没有地形起伏抢戏，背景干净，A/B 帧更容易读。
##   · 玩家速度**直接写成 `profile.player_top_speed()`**（该机的实际巡航上限），
##     而不是"等油门把它推上去"：等油门要等十几个物理帧且与倍率相关，
##     直接写值才能保证两次运行取到的是**同一个物理状态**（都是巡航满速）。
##     ⚠️ 这个值是**实际域**的 —— 它自己会跟着倍率变，这正是要验的东西。
##   · 每一帧把玩家钉在固定坐标 + 固定朝向，敌机冻在固定偏移处 ⇒
##     物理不再改变任何画面内容，剩下的差异只可能来自速度读数。

const SHOT_W := 1600
const SHOT_H := 900

var main: Node
var out_dir := "user://captures"
var tag := "hud"

var _pin_pos := Vector3(0.0, 6000.0, 0.0)
var _pin_fwd := Vector3(0.0, 0.0, -1.0)


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

	# ⚠️ 光钉住**两个机体**还不够：第四版实测全帧仍差 956 px，放大看是
	#    右上角「附近敌机 2.3 km vs 2.4 km」+ 雷达光点 + 顶部一句「敌机接近」。
	#    原因是**主场景自己**在 `_physics_process` 里驱动 AI / 修正位置，
	#    时序是"我钉完 → 它又推一下 → HUD 读到的还是被推过的值"。
	#    所以把 Main 的 process 也停掉：没有任何东西再动，读数才是常量。
	#
	# ⚠️ **停 Main 的位置很要紧**：第五版把这一句放在 30 帧循环**之后**，
	#    结果那 30 帧里主场景的修正量已经被 `player.contacts()` 的缓存吃了进去，
	#    全帧仍差 390 px。挪到"开局之后、摆位之前"，缓存里从头到尾只有钉住的值。
	main.set_physics_process(false)
	main.set_process(false)

	var p := _p()
	if p == null:
		print("HUDSPD_FAILED(no player)")
		get_tree().quit(1)
		return
	# 玩家打不死（这一拍不测伤害，只测读数）
	p.max_hp = 99999.0
	p.hp = 99999.0
	p.ifield_max = 9999.0
	p.ifield_hp = 9999.0
	p.set("debug_input_enabled", true)
	p.set("debug_input", Vector3.ZERO)
	p.set("debug_throttle", 1.0)
	p.set("debug_boost", false)
	p.set("debug_hover", false)

	# 敌机冻在玩家正前方 2.4 km、同高度 —— 两次运行的画面内容一致。
	#
	# ⚠️ **只摆一次是不够的**：第三版实测全帧仍有 1344 px 不同，放大一看是
	#    右上角的「敌机距离」读数 **2.3 km vs 2.4 km** —— 摆完之后敌机又在
	#    某一帧被主场景推走了。所以它和玩家一样**逐帧回钉**（见 `_repin`）。
	var e := _e()
	if e != null:
		e.set_physics_process(false)
		e.set_process(false)
		e.fm.velocity = Vector3.ZERO
		e.fm.speed = 0.0
		e.global_position = _enemy_pos()
		print("[hud_speed_shot] 敌机已就位 = %s（距离 %.1f m）"
			% [e.global_position, e.global_position.distance_to(_pin_pos)])

	# 巡航满速 = 该机的实际巡航上限（**实际域**，自己跟着倍率走）
	var cruise: float = p.profile.player_top_speed()
	p.fm.speed = cruise
	p.fm.velocity = _pin_fwd * cruise
	p.global_position = _pin_pos
	p.look_at(_pin_pos + _pin_fwd, Vector3.UP)
	await _frames(2)

	# 每帧回钉 —— 物理想把机子往前推，这里把它按回去，速度读数不受影响。
	for i in 30:
		await get_tree().physics_frame
		_repin(p, cruise)

	# ⚠️ **必须把 3D 层藏掉再抓图。**
	# 第一版没藏，结果两帧全画面差 74%：太平洋的海面波纹与云是**随时间动**的，
	# HUD 又是叠在 3D 上的半透明层 —— 裁"速度读数"那一块取到的
	# 一多半是晃动的背景（实测 87% 像素不同），数字本身反而看不出差异。
	# 藏掉 3D 之后画面 = HUD 叠在纯清屏色上 ⇒ 差异只可能来自 HUD 自己。
	_hide_3d()
	for i in 30:
		await get_tree().physics_frame
		_repin(p, cruise)

	# ⚠️ **回钉循环结束之后，必须把两个机体的 process 也停掉。**
	#    第六版实测：探针自己算出 `contact 距离=2400.000`（两版完全相同），
	#    抓到的帧却仍然是 2.3 km vs 2.4 km。原因是下面还要等一批**渲染帧**，
	#    而等待期间物理照跑 —— 玩家每帧自己往前飞，**没人再把它钉回来**。
	#    漂移量 = 巡航速度 × 等待时长：×2.4 那版每帧漂得更远，所以差的正是它。
	#    停掉之后位置是常量，HUD 读到的才等于探针算出来的。
	p.set_physics_process(false)
	p.set_process(false)

	# HUD 那句「附近敌机 x.x km」读的是 `player.contacts()`（**批 10 的性能缓存**），
	# 把探针自己算的距离打出来 —— 它才是"应该印在屏上"的那个数，
	# 抓到的帧如果与它不符，就是 HUD 还没重绘，不是取值范围的问题。
	var cs: Array = p.contacts()
	for c in cs:
		if c != null and is_instance_valid(c):
			print("[hud_speed_shot] contact %s 距离=%.3f m"
				% [c.display_name, p.global_position.distance_to(c.global_position)])
	print("[hud_speed_shot] 终态 玩家=%s 敌机=%s 距离=%.3f m"
		% [p.global_position, _enemy_pos(), _enemy_pos().distance_to(p.global_position)])

	# 再等一批**渲染帧**（不是物理帧）：上面所有回钉都发生在物理帧里，
	# 而 HUD 是在渲染帧上重绘的。不额外等，抓到的可能是"物理已钉住、
	# HUD 还没重绘"的那一帧。
	for i in 20:
		await get_tree().process_frame
	# 藏 3D 那一帧之后 HUD 还会重绘一次，多等一帧再抓。
	await _frames(2)

	var shown := int(p.airspeed_kmh() * _hud_speed_scale())
	print("[hud_speed_shot] tag=%s mult=%.2f cruise_real=%.1f airspeed_kmh=%.1f 读数=%d"
		% [tag, SuitProfile.SPEED_REAL_MULT, cruise, p.airspeed_kmh(), shown])
	await _shot(tag)
	print("HUDSPD_DONE -> ", out_dir.path_join("%s.png" % tag))
	get_tree().quit(0)


## HUD 用的显示缩放。这里**故意从 hud.gd 的常量现读**，而不是自己再写一遍
## `0.6 / SPEED_REAL_MULT` —— 否则这个探针就变成"抄了一遍公式"，
## 哪天 HUD 那边改了缩放，它反而会跟着一起错。
func _hud_speed_scale() -> float:
	# ⚠️ `main.get()` 返回 Variant —— 这里必须**显式**写 `: Object`，
	#    用 `:=` 会触发 `INFERENCE_ON_VARIANT`，而本项目把它当错误（见 project.godot）。
	var h: Object = main.get("hud")
	if h == null:
		# 场景里没挂（或还没建）时的兜底：用 HUD 自己的常量。
		return 0.6 / SuitProfile.SPEED_REAL_MULT
	# `const` 不是 `Object` 的属性，`h.get()` 取不到；要从脚本常量表里读。
	var s: Script = h.get_script()
	if s != null:
		var m: Dictionary = s.get_script_constant_map()
		if m.has("SPEED_DISPLAY_SCALE"):
			return float(m["SPEED_DISPLAY_SCALE"])
	return 0.6 / SuitProfile.SPEED_REAL_MULT


func _repin(p: Node, cruise: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	p.global_position = _pin_pos
	p.fm.speed = cruise
	p.fm.velocity = _pin_fwd * cruise
	# 敌机同样回钉 —— 它的位置决定右上角"敌机距离"那个读数，
	# 松一次就会在两帧之间印出 2.3 / 2.4 这种差。（见 `_ready` 里的注释。）
	var e := _e()
	if e != null and is_instance_valid(e):
		e.global_position = _enemy_pos()
		e.fm.velocity = Vector3.ZERO
		e.fm.speed = 0.0


## 敌机的固定停位：玩家正前方 2400 m（正好 2.4 km，读数是个整数公里）。
func _enemy_pos() -> Vector3:
	return _pin_pos + _pin_fwd * 2400.0


## 把 3D 那一层整个藏掉，只留 HUD。
##
## 四个容器 + 那块全屏后处理面片：
##   `world`        地形 / 海面 / 云 / 灯
##   `units_root`   玩家与敌机的模型
##   `projectiles`  弹道与光束
##   `cel_quad`     三渲二全屏后处理（挂在 canvas 上，盖着 3D）
##
## ⚠️ 光藏 `world` **不够**：第二版实测全帧仍差 29%，差异全在**星空**上
##    —— 天空不是 `world` 的子节点能盖住的（环境挂在 `World3D.environment` 上）。
##    这里直接把 `World3D.environment` 摘掉，屏幕底色才真的是纯色。
##
## ⚠️ 相机（`chase`）**不藏**，而是**钉死**：Camera3D 若随可见性一起失效，
##    画面会变成另一台相机（或没有相机），那就不是"HUD 叠在清屏色上"而是"黑屏"。
##    钉死它另有个必要理由 —— HUD 的目标框 / 雷达光点是拿
##    `cam.unproject_position()` 算的，相机姿态差一点点，那几个点就会挪。
func _hide_3d() -> void:
	for key in ["world", "units_root", "projectiles"]:
		var n: Node = main.get(key) as Node
		if n is Node3D:
			(n as Node3D).visible = false
	var q: Node = main.get("cel_quad") as Node
	if q is Node3D:
		(q as Node3D).visible = false
	# 摘掉天空 / 环境
	var w3: World3D = get_viewport().world_3d
	if w3 != null:
		w3.environment = null
	# 钉死机位（在玩家正后方，与玩家同向）
	var cam: Node = main.get("chase") as Node
	if cam is Node3D:
		cam.set_physics_process(false)
		cam.set_process(false)
		var c3 := cam as Node3D
		c3.global_position = _pin_pos - _pin_fwd * 130.0
		c3.look_at(_pin_pos + _pin_fwd * 300.0, Vector3.UP)


func _p() -> Node:
	var n = main.get("player")
	return n if (n != null and is_instance_valid(n)) else null


func _e() -> Node:
	var n = main.get("enemy")
	return n if (n != null and is_instance_valid(n)) else null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
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
