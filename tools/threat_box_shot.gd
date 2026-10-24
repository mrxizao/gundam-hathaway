extends Node
## 拦截框形状的**实机判据图**台（用户指定：锁定框正方形 / 拦截框菱形）。
##
## ## 要证明的一件事
##
## 用户原话：「机体的锁定 ui 显示框是正方形的，而导弹的拦截显示框应该是四边相等的棱形」。
## 所以屏上必须**同时**看得到两种框，而且一眼分得开：
##
##   · 锁定框（主目标）    = **正方形**，臂在四个对角（`hud._bracket()`）；
##   · 拦截框（每枚来袭弹）= **菱形**，顶点在正上下左右（`hud._threat_box()`）。
##
## ## 跑法
##
## ```
## godot --path <工程> res://tools/threat_box_shot.tscn -- <输出目录>
## ```
##
## ⚠️ **不能加 `--headless`**：无头用的是 dummy 渲染器，一个像素都不产生，抓出来全黑。
## 本脚本的全部意义就是**能真的看到**。
##
## ## 构造上的讲究
##
## · **靶机 / 来袭弹都不用 AI，造完立刻 `set_physics_process(false)`**：
##   靶机不关物理两秒内自己坠海（`capture_lock36` 记过这笔）；
##   来袭弹不关就会一路咬过来，框的位置每帧都在变，判据图反而读不出来。
## · **玩家机在 `_process()` 里锁完整变换**，而不是 `await physics_frame` 之后赋值 ——
##   后者的赋值紧接着就被玩家机自己的 `_physics_process()` 覆盖（`capture_lock36` 翻过这个车）。
## · **来袭弹的朝向必须 `look_at(玩家)`**：`rank_threats()` 的 TTI = 距离 / 接近分量，
##   而接近分量 = `朝向·视线 × speed`。弹背对着玩家的话接近分量恒为 1.0 的下限，
##   TTI 会变成一个毫无意义的大数，三档颜色就摆不出来。
## · **不止出一张整屏图**：1600×900 下 60 px 的框在整屏图里太小，
##   所以额外裁一块**放大 3 倍**的局部图 —— 判据图的成色全在那一张上。

const SHOT_W := 1600
const SHOT_H := 900
## 钉玩家机时的最低高度（米）。ULURU 有山，拔上去平视就不会被地形挡住。
const CLIMB_Y := 1500.0
## 主目标摆在机头正前方多远（米）。太远的话机身只有几个像素，框旁边看不出锁的是谁。
const TARGET_AHEAD := 250.0

var main: Node
var out_dir := "user://capture_threat_box"
var _home_xform := Transform3D.IDENTITY
var _hold := false
## 所有框心的世界里位置 —— 局部放大图按它们的屏幕外接框裁剪。
var _marks: Array[Vector3] = []
var locked_foe: FlightBody = null
var threats: Array[Missile] = []


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
		push_error("THREATBOX_FAILED(no player)")
		return
	# 判据图不该被伤害打断（被打了 HUD 会叠告警，框反而看不清）。
	p.max_hp = 99999.0
	p.hp = 99999.0
	p.ifield_max = 9999.0
	p.ifield_hp = 9999.0

	_park_enemy()
	await _frames(150)
	_home_xform = _level_xform(p)
	_hold = true
	await _frames(20)
	await _settle_camera()

	# ---- 主目标：机头正前方 250 m（**正方形**框）----
	var bs: Basis = _home_xform.basis
	var fwd: Vector3 = -bs.z
	var right: Vector3 = bs.x
	var up: Vector3 = bs.y
	locked_foe = _spawn_foe(fwd * TARGET_AHEAD, "TGT")
	await _frames(20)

	var lk = main.get("player_lock")
	if lk != null:
		lk.select_target(locked_foe)
		# ⚠️ 等**锁定质量条涨满**：没锁上的目标框是 HUD 青绿（`HUD`），锁上才是 DANGER 红。
		# 判据图要让"方形框"和红菱形同等亮，不然会读成"方形那个框更弱"——
		# 而那是颜色档的差别，与形状无关，正好是这张图不该引入的干扰。
		await _frames(300)
		print("THREATBOX lock locked=%s" % str(lk.locked))

	# ---- 三枚来袭飞弹（**菱形**框），按「选中 / 告警 / 已拦截」三档摆 ----
	#   TTI = 距离 / speed（弹已 `look_at(玩家)`，所以接近分量 = speed）。
	threats.append(_spawn_threat(fwd * 180.0 + right * 170.0 + up * 40.0, 90.0, "M1"))
	threats.append(_spawn_threat(fwd * 720.0 - right * 430.0 + up * 70.0, 120.0, "M2"))
	threats.append(_spawn_threat(fwd * 300.0 - right * 190.0 - up * 70.0, 120.0, "M3"))
	await _frames(30)

	# ---- 选中 #1（走真按键，不走 `_threat_index` 赋值）----
	await _press("select_threat")
	await _frames(10)
	_log_state("00_built")

	# ---- "已拦截" 角标：造一发拦截弹把 M3 咬住 ----
	# 判据读的是**弹自己身上**的 `intercept_target`（`Interceptor.engaged_targets`），
	# 所以这里造一发真的 `Missile` 并写那个字段 —— 与自动拦截走的是同一条路。
	_arm_interceptor(threats[2])
	await _frames(10)
	_log_state("01_armed")

	await _settle_camera()
	await _frames(10)

	await _shot("01_hud_full")
	await _zoom_shot("02_boxes_zoom")
	await _strip_shot("03_same_scale_strip")

	print("THREATBOX done → %s" % out_dir)


## 每渲染帧把玩家机钉回 `_home_xform`（见文件头：必须在 `_process` 而不是物理帧之后）。
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


## 把 versus 那台真敌机挪到机尾方向 60 km 并冻住 —— 留着它会开火、会把画面搅乱，
## 也会被自动接战选中（本台要的主目标是**自己摆的那台**）。
func _park_enemy() -> void:
	var e = main.get("enemy")
	var p := _p()
	if e == null or not is_instance_valid(e) or p == null:
		return
	e.set_physics_process(false)
	e.fm.velocity = Vector3.ZERO
	e.fm.speed = 0.0
	e.global_position = p.global_position - p.forward() * 60000.0
	print("THREATBOX parked real enemy at %s" % str(e.global_position))


## 造一台静止靶机（裸 `FlightBody`，不挂 AI）。
##
## ⚠️ `profile` / `team` / `is_player` / `projectile_container` 必须在 `add_child()` **之前**
## 设好 —— `FlightBody._ready()` 会读它们决定进哪个分组、加载哪个模型。
func _spawn_foe(offset: Vector3, nm: String) -> FlightBody:
	var p := _p()
	var f := FlightBody.new()
	f.name = "Tgt%s" % nm
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
	f.set_physics_process(false)
	f.fm.velocity = Vector3.ZERO
	f.fm.speed = 0.0
	_marks.append(f.global_position)
	return f


## 造一枚**冲着玩家来**的来袭弹，并冻住。
##
## ⚠️ `target` 必须指玩家 —— `_incoming_missiles()` 与 `rank_threats()` 都按它筛，
## 指错了这一枚就压根不进威胁表，屏幕上不会有框。
func _spawn_threat(offset: Vector3, spd: float, nm: String) -> Missile:
	var p := _p()
	var m := Missile.new()
	m.name = "Threat%s" % nm
	m.shooter = main.get("enemy")
	m.target = p
	m.intercept_capable = true
	m.speed = spd
	var container = main.get("projectiles")
	container.add_child(m)
	m.global_position = p.global_position + offset
	# 朝向玩家（TTI 的接近分量才有意义，见文件头）。
	m.look_at(p.global_position, Vector3.UP)
	m.set_physics_process(false)
	_marks.append(m.global_position)
	return m


## 造一发"咬住 `victim`"的拦截弹。
##
## ⚠️ 它的 `target` **不能**是玩家：`rank_threats()` 会把 `target == 玩家` 的都算成威胁，
## 这样它会自己多出一个框，把画面搅乱。指到那台被停掉的敌机即可。
func _arm_interceptor(victim: Missile) -> void:
	var m := Missile.new()
	m.name = "InterceptorShot"
	m.shooter = _p()
	m.target = main.get("enemy")
	m.intercept_capable = true
	m.intercept_target = victim
	var container = main.get("projectiles")
	container.add_child(m)
	m.global_position = _p().global_position - Vector3(0.0, 5000.0, 0.0)
	m.set_physics_process(false)
	print("THREATBOX armed interceptor → %s" % victim.name)


# ------------------------------------------------------------ 读数

func _log_state(tag: String) -> void:
	var p := _p()
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	var sel = null
	if p != null and p.has_method("selected_threat"):
		sel = p.call("selected_threat")
	var n := 0
	if p != null and p.has_method("threats"):
		n = (p.call("threats") as Array).size()
	print("THREATBOX %-12s threats=%d selected=%s" % [
		tag, n, str(sel.name) if sel != null else "-"])
	if cam == null:
		return
	for i in _marks.size():
		var sp := cam.unproject_position(_marks[i])
		print("THREATBOX   mark[%d] screen=(%d, %d)" % [i, int(sp.x), int(sp.y)])


# ------------------------------------------------------------ 工具（与 tools/capture_lock36.gd 同源）

func _p() -> Node:
	var n = main.get("player")
	return n if (n != null and is_instance_valid(n)) else null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _press(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(2)


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
	# ⚠️ **必须统一格式**：视口贴图的格式不保证是 RGBA8（本机 RTX 上就不是），
	# 而 `Image.blit_rect()` **要求两端格式一致** —— 不一致时它只打一条
	# `Condition "format != p_src->format" is true`，**一个像素都不拷**，
	# 而调用方那条 `save_png()` 照样 err=0 ⇒ 得到一张"四格全黑、只有编号"的图。
	# 这种失败在成图上看不出是 bug（像是"没渲染出来"），所以在这里一次转干净。
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null:
		return
	var path := out_dir.path_join("%s.png" % name)
	print("SHOT %s  err=%d" % [path, img.save_png(path)])


## 把所有框心在屏幕上的位置框起来、四周留边、**放大 3 倍**再存一张。
##
## 为什么非要它：60 px 的角框在 1600×900 的整屏图里只有指甲盖大，
## "菱形还是正方形"这种判据在整屏图上是**看不出来**的 —— 而这张图存在的全部意义
## 就是让人一眼判出来。放大用 `INTERPOLATE_NEAREST`：不引入插值糊边，
## 抗锯齿形成的像素阶梯反而能把 45° 斜臂和正/水平臂区分得更清楚。
func _zoom_shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null or _marks.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var pts := ""
	for w: Vector3 in _marks:
		var sp := cam.unproject_position(w)
		lo = lo.min(sp)
		hi = hi.max(sp)
		pts += "(%d,%d) " % [int(sp.x), int(sp.y)]
	var pad := 70.0
	var x0 := int(clampf(lo.x - pad, 0.0, float(SHOT_W - 8)))
	var y0 := int(clampf(lo.y - pad, 0.0, float(SHOT_H - 8)))
	var x1 := int(clampf(hi.x + pad, float(x0 + 8), float(SHOT_W)))
	var y1 := int(clampf(hi.y + pad, float(y0 + 8), float(SHOT_H)))
	var r := Rect2i(x0, y0, x1 - x0, y1 - y0)
	var crop := img.get_region(r)
	var k := 3
	crop.resize(crop.get_width() * k, crop.get_height() * k, Image.INTERPOLATE_NEAREST)
	var path := out_dir.path_join("%s.png" % name)
	print("SHOT %s err=%d  裁自 %s  框心屏幕坐标 %s" % [path, crop.save_png(path), str(r), pts])


## **等尺度并排条**：四个框各裁同样大的一块摊平排开 —— 判形状最直接的一张。
##
## 为什么非要它：`02_boxes_zoom` 的四格是**同一块画面**放大，框与框的**像素尺度**
## 会被透视拉开（近的框大、远的框小），于是"菱形比正方形小"这种错觉混进来。
## 这里每个框都按**自己框心**取同样边长的一块，四个格子像素尺度完全相同，
## 方形与菱形就能直接叠着看。
##
## ⚠️ 刻意**不做夹紧**：靠近画面边缘的框会把窗口切掉一部分（留黑边），
## 而"夹紧到画面内"会让那一格变小 —— 那就等于把要对比的那个变量改掉了。
func _strip_shot(name: String, half := 72, k := 3) -> void:
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null or _marks.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var n := _marks.size()
	var cw := half * 2
	var cell_px := cw * k
	var strip := Image.create(cell_px * n, cell_px, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.05, 0.06, 0.07))
	var txt := ""
	for i in n:
		var sp := cam.unproject_position(_marks[i])
		var r := Rect2i(int(sp.x) - half, int(sp.y) - half, cw, cw)
		var cell := Image.create(cw, cw, false, Image.FORMAT_RGBA8)
		cell.fill(Color(0.05, 0.06, 0.07))
		var src := r.intersection(Rect2i(0, 0, SHOT_W, SHOT_H))
		if src.size.x > 0 and src.size.y > 0:
			cell.blit_rect(img.get_region(src), Rect2i(0, 0, src.size.x, src.size.y),
				src.position - r.position)
			cell.resize(cell_px, cell_px, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(cell, Rect2i(0, 0, cell_px, cell_px), Vector2i(cell_px * i, 0))
		_draw_label(strip, cell_px * i + 12, 12, str(i + 1), 4)
		txt += "(%d,%d) " % [int(sp.x), int(sp.y)]
	var path := out_dir.path_join("%s.png" % name)
	print("SHOT %s err=%d  每格 %d×%d（%d× 放大）  框心 %s" % [
		path, strip.save_png(path), cell_px, cell_px, k, txt])
	# ⚠️ 这张条只做到「**裁框**同尺寸」，**不是「框」同尺寸** —— 别拿两格的框去比大小。
	#   格 1 是机体**锁定框**，半高**随距离变**（`_draw_target`：`clampf(2600/dist,0,1)*44+13`，13~57 px）；
	#   格 2..n 是来袭弹**拦截框**，半高**固定** `HUD.THREAT_BOX_H`（30 px）。
	#   实测：近到 200 m 内时锁定框半高 57 px ⇒ 放大 3× 后角点在 ±171 px，
	#   已经贴到格子边缘（格子半径 216 px），看着比菱形「大一圈」—— 那是**尺寸**差，不是形状差。
	print("  格 1 = 机体锁定框（正方形，半高随距离 13~57 px）")
	print("  格 2..%d = 来袭弹拦截框（菱形，半高固定 %d px）" % [n, int(FlightHUD.THREAT_BOX_H)])
	print("  读形状看**顶行/腰行**的角点方位，别看两格谁大：")
	print("    正方形 = 顶行两个角点在左右两侧（框腰那一行反而没有笔画）")
	print("    菱形   = 顶行只有一个点在**框心正上方**，框腰那一行才有左右两个顶点")


## 在 `Image` 上画**数字**（只有点阵 1-4，够给格子编号用）。
##
## 工程里没有可用的字体贴图（HUD 全代码绘制、不落地图片资源），
## 所以这里自带一个 5×7 的极简数字点阵，`k` 是每像素放大倍数。
func _draw_label(img: Image, x: int, y: int, text: String, k: int) -> void:
	var glyphs := {
		"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
		"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
		"3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
		"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	}
	var col := Color(1.0, 0.85, 0.35)
	var cx := x
	for ch in text:
		var rows: Array = glyphs.get(ch, glyphs["1"])
		for ry in rows.size():
			var row: String = rows[ry]
			for rx in row.length():
				if row[rx] != "1":
					continue
				for dy in k:
					for dx in k:
						var px := cx + rx * k + dx
						var py := y + ry * k + dy
						if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
							img.set_pixel(px, py, col)
		cx += 6 * k
