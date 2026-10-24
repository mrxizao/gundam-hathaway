extends Node
## ★63-9 · D3a 真机出图：光束步枪辅助瞄准的**提示圈 + 「辅助瞄准 吸附」**。
##
## ## 为什么要出图
## D3a 唯一的**玩家可见字面量**是 HUD 上那一圈 `DANGER` 色吸附环 + 一行
## 「辅助瞄准 吸附」文字（`hud.gd::_draw_target()`）。无头套件能断：
## 阈值只有一处真源、那一行里**一个数字都没有**、`draw_arc` 的实参写法 ——
## 但「它真的画在屏幕上、而且只在准星进锥时才画」**只有像素说了算**
##（本工程栽过"两条断言都绿却看不见"，也栽过"负对照没牙齿"）。
##
## ## 三张图（同一台机器、同一个已锁定的目标、同一个镜头）
##   ① `01_assist_on_pin`   辅助开 + 准星**钉在提示圈上** ⇒ 出现吸附环 + 那一行字
##   ② `02_assist_on_far`   辅助开 + 准星**挪开 ~20°**        ⇒ 环与字**都必须消失**
##   ③ `03_assist_off_pin`  辅助关 + 准星**回到提示圈上**      ⇒ 仍然不出现（模式门）
## ①② 之间只差准星位置、①③ 之间只差辅助开关 —— 两侧都是**单变量**。
##
## ## 读数与量法
## 每张图都打印：`aim_assist_enabled()` / **HUD 自己量出来的那个夹角** /
## 提示圈的屏幕像素 / 该像素在不在屏幕里。像素量法见 `_probe_pixels()`：
## 只取**提示圈旁边一圈极窄的环带**（半径 10~18 px）与它下方那一小块文字区，
## 判据是"**红得出来**"（`r - max(g,b) > 40`）—— 目标框虽然也是 `DANGER`，
## 但它在半径 ~51 px 的矩形边上（`half = clamp(2600/dist,0,1)*44+13`），
## 与这两块**几何上不重叠**（这也是为什么不去整图相减：三张图之间世界飞了几百米）。
##
## ⚠️ 不能加 `--headless`：dummy 渲染器一个像素都不产生，抓出来全黑。
##
## 跑法：godot --path <工程> res://tools/_r63_9_d3a_shot.tscn -- <输出目录>

const FOE_MIN_DIST := 2600.0     ## 目标比这还近就把机体往外挪一点，免得框占满屏幕
const FOE_MAX_DIST := 30000.0    ## ⚠️ 必须 < `LockOnSystem.seeker_range`(46575)，否则 `select_target()` 直接返回 false
const FOE_AIM_DIST := 3000.0
const HOLD_DIST := 3000.0        ## 之后每帧把目标**托在正前方这个距离**上（摆位，见文件头）
const PIN_RING_BAND := Vector2(10.0, 18.0)
const AXIS_MARGIN := 4.0         ## ⚠️ 环带里要**挖掉四个轴向**：准星的四截臂长 13+间隔 5 = 5~18 px，
                                 ##    正好落在环带里、而且颜色是 `WARN`（同样"红得出来"）⇒ 不挖掉就是假读数
const RED_MARGIN := 40           ## "红得出来"的判据：r - max(g,b) > 40（DANGER = 1.0/0.30/0.26）
const TEXT_TOP := 20.0           ## 文字区上边：准星竖臂到 +18 为止，从 +20 起才干净
const TEXT_BOTTOM := 40.0

var out := "user://r63_9_d3a_shot"
var main: Node
var pc: PlayerController
var foe: FlightBody
var cam: Camera3D
var cursor_mode := "pin"          ## "pin" = 准星钉在提示圈上；"far" = 挪开
var bp := Vector2.ZERO            ## 提示圈的屏幕坐标（拍摄那一刻）


func _ready() -> void:
	process_priority = 1000
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(10)

	await _round()

	print("R63_9_D3A_SHOT_DONE -> %s" % out)
	get_tree().quit(0)


## 每帧的"摆位"（探针纪律④：root 比子节点先跑 ⇒ 靠 `process_priority` 抢到最后）。
## ⚠️ 这里**只摆两个替身**：准星像素、以及把锁定钉住。产品代码一行不碰。
func _process(_d: float) -> void:
	if pc == null or cam == null or foe == null:
		return
	if not is_instance_valid(pc) or not is_instance_valid(foe):
		return
	if not foe.alive:
		return
	# ---- 摆位：把目标**托在正前方 HOLD_DIST**，并让它的速度与玩家同步 ----
	# 为什么必须托：不托的话两台机以 ~4000 m/s 相对速度对撞，50 帧后间距从 3000 m 变 **114 m**
	#（第二版实测），提示圈直接被顶出画面（量到 (2430, 15)）。
	# 速度同步是为了**提前量**：`gun_lead_point_beam()` 读的是相对速度，
	# 不同步的话 3 km 处提前量会偏出十几度 —— 那时 bp 已经不是"目标身上那一圈"了。
	# ⚠️ 这台探针判的是 **HUD 画不画那一圈**，不是飞行/命中 ⇒ 托住目标不影响结论。
	foe.global_position = pc.global_position + pc.forward() * HOLD_DIST
	foe.fm.velocity = pc.fm.velocity
	# 锁定会因为目标机动掉档 ⇒ 每帧钉回去（要看的不是"锁不锁得上"，是提示圈）
	pc.lock.force_lock()
	var blead: Vector3 = pc.lock.gun_lead_point_beam()
	if cam.is_position_behind(blead):
		return
	var p := cam.unproject_position(blead)
	bp = p
	pc.cursor_seen = true
	pc.aim_cursor = p if cursor_mode == "pin" else p + Vector2(340.0, 0.0)


func _round() -> void:
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, SuitProfile.Id.PENELOPE)
	await _frames(10)
	main.call("_start_fight")
	await _frames(20)
	pc = main.get("player") as PlayerController
	if pc == null:
		print("SHOT_FAILED(没有玩家机)")
		return
	cam = get_viewport().get_camera_3d()
	if cam == null:
		print("SHOT_FAILED(没有相机)")
		return
	print("[d3a] 开局 assist_on=%s translate_mode=%s rifle_count=%d 相机=%s"
		% [str(pc.assist_on), str(pc.translate_mode), pc.rifle_count, cam.name])

	# ---- 目标 ----
	var hosts: Array = Game.live_hostiles_of(pc)
	for h in hosts:
		var fb := h as FlightBody
		if fb != null and fb.alive:
			foe = fb
			break
	if foe == null:
		print("SHOT_FAILED(没有敌机)")
		return
	var d0 := pc.global_position.distance_to(foe.global_position)
	print("[d3a] 敌机 %s ｜ 初始间距 %.0f m（锁定射程 %.0f m）"
		% [foe.name, d0, pc.lock.seeker_range])
	# ⚠️ 必须先让"托位"跑几帧再锁：`select_target()` 有距离门槛（≤ `seeker_range`，46575 m），
	#    而出击点相隔 92 km（实测）—— 第一版就是在这里静默失败，
	#    随后量到的"红像素"其实是**屏幕中央的准星**（不是提示圈）。
	await _frames(8)
	print("[d3a] 托位之后间距 %.0f m" % pc.global_position.distance_to(foe.global_position))

	# ---- 开辅助：走**真的长按路径**（`flight_assist` 按住 0.45 s），不直接写字段 ----
	Input.action_press("flight_assist")
	await _frames(40)
	Input.action_release("flight_assist")
	await _frames(20)
	print("[d3a] 长按之后 assist_on=%s translate_mode=%s aim_assist_enabled=%s"
		% [str(pc.assist_on), str(pc.translate_mode), str(pc.aim_assist_enabled())])
	if not pc.translate_mode:
		print("SHOT_FAILED(没进平移模式 —— 后面全是恒真)")
		return

	# ---- 锁定（`seeker_range` = 46575 m，这个距离必成）----
	var ok := pc.lock.select_target(foe)
	pc.lock.force_lock()
	await _frames(50)
	print("[d3a] select_target=%s ｜ locked=%s ｜ 间距 %.0f m ｜ lock.target=%s"
		% [str(ok), str(pc.lock.locked), pc.lock.range_to_target(), str(pc.lock.target)])
	if not pc.lock.locked or pc.lock.target == null:
		print("SHOT_FAILED(没锁上 ⇒ `_draw_target()` 会**整个早退**，量到的红像素不是提示圈)")
		return

	# ---- ① 辅助开 + 准星钉在提示圈上 ----
	cursor_mode = "pin"
	await _frames(45)
	await _report("01 辅助开 + 准星钉住")
	await _shot("01_assist_on_pin")

	# ---- ② 辅助开 + 准星挪开（负对照：只有准星动了）----
	cursor_mode = "far"
	await _frames(45)
	await _report("02 辅助开 + 准星挪开")
	await _shot("02_assist_on_far")

	# ---- ③ 辅助关 + 准星回到圈上（模式门）----
	cursor_mode = "pin"
	await _frames(10)
	Input.action_press("flight_assist")
	await _frames(40)
	Input.action_release("flight_assist")
	await _frames(12)
	cursor_mode = "pin"
	await _frames(8)
	print("[d3a] 关辅助之后 assist_on=%s translate_mode=%s aim_assist_enabled=%s"
		% [str(pc.assist_on), str(pc.translate_mode), str(pc.aim_assist_enabled())])
	await _report("03 辅助关 + 准星钉住")
	await _shot("03_assist_off_pin")


## 打印 HUD **自己**量出来的那个夹角（与 `hud.gd::_draw_target()` 逐字同一算式）。
func _report(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var blead: Vector3 = pc.lock.gun_lead_point_beam()
	var snap := Ballistics.angle_off_boresight(pc.aim_forward(), blead - pc.global_position)
	var inside := bp.x >= 0.0 and bp.y >= 0.0 and bp.x < 1600.0 and bp.y < 900.0
	print("[d3a] %s ｜ 辅助=%s ｜ 夹角 %.4f°（阈值 %.1f° ⇒ %s）｜ 提示圈像素 (%.0f, %.0f) 在屏内=%s"
		% [tag, str(pc.aim_assist_enabled()), snap, FlightBody.AIM_ASSIST_SNAP_DEG,
			"进锥" if snap <= FlightBody.AIM_ASSIST_SNAP_DEG else "锥外", bp.x, bp.y, str(inside)])


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
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  %dx%d  err=%d" % [path, img.get_width(), img.get_height(), img.save_png(path)])
	_probe_pixels(img, name)


## 两块**几何上只属于吸附提醒**的区域：提示圈旁边那一圈极窄环带（**挖掉四个轴向**）
## 与它下方那一小块文字区。判据 = "红得出来"（`r - max(g,b) > RED_MARGIN`）。逐点扫，不采样。
func _probe_pixels(img: Image, name: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var ring := 0
	var text := 0
	var r_out := PIN_RING_BAND.y
	var r_in := PIN_RING_BAND.x
	for y in range(maxi(0, int(bp.y - r_out - 2.0)), mini(h, int(bp.y + r_out + 3.0))):
		for x in range(maxi(0, int(bp.x - r_out - 2.0)), mini(w, int(bp.x + r_out + 3.0))):
			var dx := float(x) - bp.x
			var dy := float(y) - bp.y
			var r := sqrt(dx * dx + dy * dy)
			if r < r_in or r > r_out:
				continue
			if absf(dx) <= AXIS_MARGIN or absf(dy) <= AXIS_MARGIN:
				continue          # ★ 准星那四截臂 —— 不挖掉它就是假读数
			if _is_red(img.get_pixel(x, y)):
				ring += 1
	for y in range(maxi(0, int(bp.y + TEXT_TOP)), mini(h, int(bp.y + TEXT_BOTTOM))):
		for x in range(maxi(0, int(bp.x - 70.0)), mini(w, int(bp.x + 70.0))):
			if _is_red(img.get_pixel(x, y)):
				text += 1
	print("[d3a] 像素读数 %s ｜ 吸附环带(%.0f~%.0f px, 挖轴±%.0f) = %d ｜ 文字区 = %d"
		% [name, r_in, r_out, AXIS_MARGIN, ring, text])


func _is_red(c: Color) -> bool:
	return c.r - maxf(c.g, c.b) > float(RED_MARGIN) / 255.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
