extends Node
## 第一人称（座舱）叠加层**专用**真机截图台（轮 22）。
##
## 为什么单开一个：`tools/capture.gd` 是 1.1 的全流程剧本（十几张图、两分钟起），
## 而这一轮要看的只有"座舱里那两层装饰到底长什么样"。
##
## ⚠️ **不能加 `--headless`** —— 无头用的是 dummy 渲染器，一个像素都不产生，
## 抓出来是全黑。这个脚本的全部意义就是**能真的看到**，所以必须开窗口跑。
##
## 跑法：
##   godot --path <工程> res://tools/capture_fpv.tscn -- <输出目录>
##
## 脚本里所有等待都走**物理帧**（物理固定 60 Hz；等渲染帧在 300+ fps 的窗口里
## 只有几分之一秒，会出现"相机还没贴合就截图了"）。
##
## ⚠️ 它会**临时改 `Settings.first_person`**（HUD 只在那个开关打开时才画那两层），
## 结束时**原样还回去** —— 不还原的话，跑一次截图台就把玩家的存档设置改了。

const SHOT_W := 1600
const SHOT_H := 900
## 仪表台特写：从屏底往上裁这么多像素，再放大这么多倍。
const DASH_CROP_H := 280
const ZOOM := 2

var main: Node
var out_dir := "user://captures_fpv"
var _idx := 0
var _fpv_was := false
var shoot_modes := false
## 轮 32：`suits` ⇒ 拍「按机体换剪影」（4 台有线稿 + 2 台走兜底）。
## 轮 35：`tp` ⇒ 拍「第三人称锁中央屏」（档位 = 剪影但屏上画雷达；真按一下 M 看它动不动；回座舱剪影原样回来）。
var shoot_tp := false
var shoot_suits := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	# 轮 31：第二个参数 `modes` ⇒ 加拍「三模式 + 血量分档」那一组。
	# 默认不拍，免得把原来 21 秒的时长拖长（那一组是给「中央屏切换」这一项用的）。
	shoot_modes = args.size() > 1 and args[1] == "modes"
	# 轮 32：第二个参数 `suits` ⇒ 加拍「六台机体的剪影」那一组。
	shoot_suits = args.size() > 1 and args[1] == "suits"
	# 轮 35：第二个参数 `tp` ⇒ 加拍「第三人称锁中央屏」那一组。
	shoot_tp = args.size() > 1 and args[1] == "tp"
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	# ---- 开第一人称（先记下原值，结尾还原）----
	_fpv_was = Settings.first_person
	Settings.set_first_person(true)

	# ---- 直接进 1v1：要看的是"战斗中的 HUD"，不是菜单 ----
	# ⚠️ 必须先 `close_menu()`：主菜单页还在的时候 `_on_start_match` 会走另一条路
	# （`tools/capture.gd` 也是这么起的，别省这一行）。
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
		push_error("CAPTURE_FPV_FAILED(no player)")
		_restore()
		return
	p.max_hp = 99999.0
	p.hp = 99999.0
	p.ifield_max = 9999.0
	p.ifield_hp = 9999.0
	_make_enemy_durable()

	# 摆在沙漠上空：地平线清楚，刻度导轨与仪表台都读得出来。
	p.global_position = Vector3(3000.0, 900.0, 1500.0)
	p.fm.speed = 300.0
	_dump_dash_numbers()

	# ---- 六种姿态：平飞 / 右滚 / 左滚 / 抬头 / 俯冲 / 转向 90° ----
	await _pose_shot("01_level", 0.0, 0.0, 0.0)
	await _pose_shot("02_roll_r30", 0.0, 30.0, 0.0)
	await _pose_shot("03_roll_l60", 0.0, -60.0, 0.0)
	await _pose_shot("04_pitch_up20", 20.0, 0.0, 0.0)
	await _pose_shot("05_pitch_dn15", -15.0, 0.0, 0.0)
	await _pose_shot("06_yaw90", 0.0, 0.0, 90.0)

	# ---- 底部仪表台特写（裁 + 放大）：造型细节靠这两张看 ----
	await _pose("01", 0.0, 0.0, 0.0)
	await _crop_shot("07_dash_level")
	await _pose("02", 0.0, 30.0, 0.0)
	await _crop_shot("08_dash_roll30")

	# ---- 轮 31：中央屏三模式 + 机体剪影的血量分档 ----
	#
	# ⚠️ 这一段**必须还原 `Settings.dash_screen_mode`**：`set_dash_screen_mode()`
	# 会写存档，不还原的话跑一次截图台就把玩家选好的模式改了。
	# ⚠️ 也要还原 `ifield_hp` / `max_hp` / `hp`：这一组里为了拍血档把它们改过。
	if shoot_modes:
		var mode_was: int = Settings.dash_screen_mode
		var hp_was := []
		var pw := _p()
		if pw != null:
			hp_was = [pw.max_hp, pw.hp, pw.ifield_hp]
		await _pose("30faces", 0.0, 0.0, 0.0)

		# ① 雷达（默认档）：整屏 + 中央屏特写
		Settings.set_dash_screen_mode(Settings.DASH_SCREEN_RADAR)
		await _frames(6)
		await _shot("10_mode_radar")
		await _crop_shot("11_dash_radar")

		# ② 机体剪影：I 立场还在 ⇒ 蓝
		Settings.set_dash_screen_mode(Settings.DASH_SCREEN_SILHOUETTE)
		await _frames(6)
		await _shot("12_mode_silh")
		await _crop_shot("13_dash_silh_ifield")

		# ⑤ 三模式各来一张**中央圆盘特写**（裁到只留那块屏，好并排比）
		#    用 `_shot` 出整屏，裁圆盘交给外部 Python（`_crop_shot` 只会裁整条底边）。
		Settings.set_dash_screen_mode(Settings.DASH_SCREEN_RADAR)
		await _frames(6)
		await _shot("20_disc_radar")
		Settings.set_dash_screen_mode(Settings.DASH_SCREEN_SILHOUETTE)
		await _frames(6)
		await _shot("21_disc_silh")
		Settings.set_dash_screen_mode(Settings.DASH_SCREEN_CONTOUR)
		await _frames(6)
		await _shot("22_disc_contour")

		# ③ 血量四档（先把 I 立场打掉，让它走血量分支）
		# ⚠️ ⑤ 段结束时停在等高线档，血档必须自己切回剪影 —— 否则拍的是地形图上的血条。
		Settings.set_dash_screen_mode(Settings.DASH_SCREEN_SILHOUETTE)
		await _frames(6)
		var ph := _p()
		if ph != null:
			ph.ifield_hp = 0.0
			ph.max_hp = 1000.0
			var tiers := [[0.95, "14_dash_silh_hp95"], [0.70, "15_dash_silh_hp70"],
				[0.45, "16_dash_silh_hp45"], [0.20, "17_dash_silh_hp20"]]
			for t: Array in tiers:
				ph.hp = ph.max_hp * float(t[0])
				await _frames(4)
				await _crop_shot(str(t[1]))

		# ④ 等高线地形图（"小地图"）：整屏 + 特写
		Settings.set_dash_screen_mode(Settings.DASH_SCREEN_CONTOUR)
		await _frames(6)
		await _shot("18_mode_contour")
		await _crop_shot("19_dash_contour")

		# ---- 还原 ----
		if pw != null:
			pw.max_hp = float(hp_was[0])
			pw.hp = float(hp_was[1])
			pw.ifield_hp = float(hp_was[2])
		Settings.set_dash_screen_mode(mode_was)
		print("CAPTURE_FPV restored dash_screen_mode=%d" % mode_was)


	# ---- 轮 32：按机体换剪影（4 台有线稿 + 2 台走兜底）----
	#
	# ⚠️ 这一组必须留**同一姿态、同一血量、同一颜色**：要比的是**形状**。
	# 所以 I 立场先关掉（开着的话一律蓝）、血量拉满（满血 ⇒ 绿）。
	# ⚠️ 换机体走的是 `main.gd` 装配机体的同一条路（`player.profile = ...`），
	# 不是"另写一套只给截图用的画法" —— 但要还原，否则这一跑会把玩家那台换掉。
	if shoot_suits:
		var mode_was3: int = Settings.dash_screen_mode
		var ps := _p()
		var prof_was: SuitProfile = ps.profile if ps != null else null
		var hp_was3 := []
		if ps != null:
			hp_was3 = [ps.max_hp, ps.hp, ps.ifield_hp]
			ps.max_hp = 1000.0
			ps.hp = 1000.0
			ps.ifield_hp = 0.0
		Settings.set_dash_screen_mode(Settings.DASH_SCREEN_SILHOUETTE)
		await _frames(6)
		var lineup: Array = [
			[SuitProfile.Id.XI, SuitProfile.ArizeusForm.NORMAL, "30_suit_xi"],
			[SuitProfile.Id.PENELOPE, SuitProfile.ArizeusForm.NORMAL, "31_suit_penelope"],
			[SuitProfile.Id.ARIZEUS, SuitProfile.ArizeusForm.NORMAL, "32_suit_arizeus"],
			[SuitProfile.Id.ARIZEUS, SuitProfile.ArizeusForm.CORE_NU, "33_suit_core_nu"],
			# ⚠️ 轮 35 新增：巡航态是**另一个形状**（翼展平铺），单列下标 5。
			#    不拍这一张就看不出「它不再与常态共用一张图」到底对不对。
			[SuitProfile.Id.ARIZEUS, SuitProfile.ArizeusForm.CRUISE, "36_suit_cruise"],
			[SuitProfile.Id.GUSTAV00, SuitProfile.ArizeusForm.NORMAL, "34_suit_gustav_fallback"],
			[SuitProfile.Id.MESSER_M01, SuitProfile.ArizeusForm.NORMAL, "35_suit_messer_fallback"],
		]
		for e: Array in lineup:
			if ps != null:
				ps.profile = SuitProfile.by_id_form(int(e[0]), int(e[1]))
			await _frames(6)
			await _shot(str(e[2]))
			print("CAPTURE_FPV suit key=%d" % FlightHUD.silhouette_key(int(e[0]), int(e[1])))
		if ps != null:
			ps.profile = prof_was
			ps.max_hp = float(hp_was3[0])
			ps.hp = float(hp_was3[1])
			ps.ifield_hp = float(hp_was3[2])
		Settings.set_dash_screen_mode(mode_was3)
		print("CAPTURE_FPV restored suit + dash_screen_mode=%d" % mode_was3)



	# ---- 轮 35：第三人称锁中央屏（档位不动、屏恒雷达、回座舱恢复）----
	#
	# 要拍的是「**存档里的档位**与「**屏上画的档位**」分开：第一张里档位已经是剪影、
	# 而屏上是雷达。第二张是**真按一下 M**之后 —— 通过 `Input.action_press`走 `InputMap`
	# 里那个真动作，而不是直接叫 `Settings.cycle_dash_screen()`（直接叫就绕过了
	# `main.gd` 里那道 `Settings.first_person` 门 —— 拍出来的图就证明不了任何东西）。
	if shoot_tp:
		var mode_was4: int = Settings.dash_screen_mode
		var fpv_was4: bool = Settings.first_person
		Settings.set_dash_screen_mode(Settings.DASH_SCREEN_SILHOUETTE)
		Settings.set_first_person(false)
		await _frames(24)
		await _shot("40_tp_silh_mode_screen_radar")
		await _crop_shot("41_tp_dash_radar_locked")
		print("CAPTURE_FPV tp: dash_screen_mode=%d effective=%d"
			% [Settings.dash_screen_mode, Settings.effective_dash_screen()])
		Input.action_press("cycle_dash_screen")
		await _frames(2)
		Input.action_release("cycle_dash_screen")
		await _frames(8)
		await _shot("42_tp_after_M")
		print("CAPTURE_FPV tp after M: dash_screen_mode=%d effective=%d"
			% [Settings.dash_screen_mode, Settings.effective_dash_screen()])
		Settings.set_first_person(true)
		await _frames(24)
		await _shot("43_fpv_silh_back")
		await _crop_shot("44_fpv_dash_silh_back")
		print("CAPTURE_FPV back to fpv: effective=%d"
			% Settings.effective_dash_screen())
		Settings.set_first_person(fpv_was4)
		Settings.set_dash_screen_mode(mode_was4)
	# ---- 回收：把第一人称开关还给玩家原本的值 ----
	_restore()
	print("CAPTURE_FPV_DONE idx=%d out=%s" % [_idx, out_dir])
	get_tree().quit()


func _restore() -> void:
	if Settings.first_person != _fpv_was:
		Settings.set_first_person(_fpv_was)
		print("CAPTURE_FPV restored first_person=%s" % str(_fpv_was))
	# ⚠️ 还要**显式**把存档写回去。`Settings.set_dash_screen_mode()` 带"值没变就
	# return"的短路（按 M 时不该每下都写盘），短路会连 `save_config()` 一起跳过 ——
	# 于是上一跑留在盘上的临时档位，这一跑"恢复成同一个值"时是空操作，永远改不回来
	# （实测日志印 `restored …=0`，而 `settings.cfg` 里还写着 `dash_screen=1`）。
	# 这一刻内存里的值已经是恢复后的正确值，补一次落盘即可。
	Settings.save_config()
	print("CAPTURE_FPV persisted settings: dash_screen=%d first_person=%s"
		% [Settings.dash_screen_mode, str(Settings.first_person)])


# ------------------------------------------------------------ 姿态与取景

## 把机体摆到一个确定的姿态。
##
## ⚠️ 写 `basis` 而不是用 `look_at()`：`look_at` **只定死机头方向**，
## 滚转只能靠 `up` 参数间接表达，摆不出"精确右滚 30°"。
## 姿态用欧拉角一次给全（`from_euler` 默认 YXZ：先偏航、再俯仰、后滚转）。
func _pose(tag: String, pitch: float, roll: float, yaw: float) -> void:
	var p := _p()
	if p == null:
		return
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), deg_to_rad(roll)))
	p.global_transform = Transform3D(b, p.global_position)
	p.fm.align_velocity(p.forward())
	_drive(Vector3.ZERO, 0.8, false, false)
	await _frames(3)
	# 再钉一次：飞行控制器在同一物理帧里也写这个 basis，晚一帧写能保证是最后生效的那个。
	p.global_transform = Transform3D(b, p.global_position)
	p.fm.align_velocity(p.forward())
	await _settle_camera()
	await _frames(20)
	print("POSE %s pitch=%.1f roll=%.1f yaw=%.1f" % [tag, pitch, roll, yaw])


func _pose_shot(name: String, pitch: float, roll: float, yaw: float) -> void:
	await _pose(name, pitch, roll, yaw)
	await _shot(name)


## 把仪表台那条裁剪出来放大 —— 造型细节（倒角 / 铆钉 / 圆表）在整屏图里太小了。
func _crop_shot(name: String) -> void:
	_shot_index()
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null:
		return
	var h := mini(DASH_CROP_H, img.get_height())
	var region := Rect2i(0, img.get_height() - h, img.get_width(), h)
	var sub := img.get_region(region)
	sub.resize(sub.get_width() * ZOOM, sub.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	var path := out_dir.path_join("%s.png" % name)
	var err := sub.save_png(path)
	print("CROP %s  err=%d  region=%s" % [path, err, str(region)])


## 把仪表台的版式数字打出来 —— 图能看出"像不像"，数字才能看出"有没有越界"。
func _dump_dash_numbers() -> void:
	var view := Vector2(SHOT_W, SHOT_H)
	var lay: Dictionary = FlightHUD.dash_layout(view)
	var rect: Rect2 = lay["rect"]
	var c: Rect2 = lay["center"]
	print("DASH rect=%s center=%s left=%s right=%s"
		% [str(rect), str(c), str(lay["left"]), str(lay["right"])])
	var hud = main.get("hud")
	if hud != null and is_instance_valid(hud):
		var hsize: Vector2 = hud.size
		var has_cam: bool = hud.get("camera") != null
		print("HUD size=%s camera=%s" % [str(hsize), str(has_cam)])


# ------------------------------------------------------------ 工具（与 tools/capture.gd 同源）

func _p() -> Node:
	var n = main.get("player")
	return n if (n != null and is_instance_valid(n)) else null


func _e() -> Node:
	var n = main.get("enemy")
	return n if (n != null and is_instance_valid(n)) else null


func _make_enemy_durable() -> void:
	var e := _e()
	if e == null:
		return
	e.max_hp = 99999.0
	e.hp = 99999.0
	e.ifield_max = 400.0
	e.ifield_hp = 400.0
	e.flare_count = 999
	# 冻在原地当靶子，免得它飞走把画面搅乱
	e.set_physics_process(false)
	e.fm.velocity = Vector3.ZERO
	e.fm.speed = 0.0
	var p := _p()
	if p != null:
		e.global_position = p.global_position + p.forward() * 1400.0 + Vector3(160.0, 30.0, 0.0)
		e.look_at(p.global_position, Vector3.UP)


func _drive(input: Vector3, throttle := 0.8, boost := false, hover := false) -> void:
	var p := _p()
	if p == null:
		return
	p.debug_input_enabled = true
	p.debug_input = input
	p.debug_throttle = throttle
	p.debug_boost = boost
	p.debug_hover = hover


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


func _shot_index() -> void:
	_idx += 1


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
	_shot_index()
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null:
		return
	var path := out_dir.path_join("%s.png" % name)
	var err := img.save_png(path)
	print("SHOT %s  err=%d" % [path, err])
