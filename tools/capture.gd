extends Node
## 视觉验证工具：把真实渲染出来的画面抓成 PNG，供人工核对。
##
## 跑法（**不能加 --headless**，headless 用 dummy 渲染器，抓出来是空的）：
##   godot --path <工程> res://tools/capture.tscn -- <输出目录>
##
## 1.1 的剧本：
##   主菜单**六页**（模式 / 机体(三张卡) / 敌人 / 难度 / 地图 / 设置）→
##   **艾尔斯岩夜沙漠**的 1v1（巨岩、沙丘）→ 鼠标锁定光标 → Alt 锁定镜头 →
##   **阿利宙斯变形**（闪光 + 巡航形态）→ 常态 → 残血**爆壳变核心** →
##   加速 / 悬停 / 光束 / 军刀 / 暂停 → **训练模式**（废墟靶场 + 四架古斯塔夫00）→ 结算。
##
## 脚本里所有等待都走**物理帧**（物理是固定 60 Hz，等渲染帧在 300+ fps 的窗口里
## 只有几分之一秒，会出现"光束还在半路上就截图了"）。

const SHOT_W := 1600
const SHOT_H := 900

var main: Node
var out_dir := "user://captures"
var _shot_index := 0


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
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(10)

	# ---------------- 主菜单四页 ----------------
	await _shot("menu_mode")
	var menu = main.get("menu")
	menu.set("stage", MainMenu.Stage.SUIT)
	menu.set("suit_index", 2)          # 停在阿利宙斯那张卡上（三张卡一起看）
	menu.queue_redraw()
	await _frames(6)
	await _shot("menu_suit")
	# 敌人页 / 难度页：**1.2 新增的两页，之前完全没进截图剧本** ——
	# 于是"版式是竖排行、输入却只能用 A/D、顶栏还写着③选择难度"这一组 bug
	# 一路活到用户实测才被发现。视觉回归本该拦住它，补上这两页就是补这个窟窿。
	menu.set("stage", MainMenu.Stage.ENEMY)
	menu.set("enemy_index", 1)         # 停在中间的佩涅罗佩上（三行一起看）
	menu.queue_redraw()
	await _frames(6)
	await _shot("menu_enemy")
	menu.set("stage", MainMenu.Stage.DIFFICULTY)
	menu.set("diff_index", 1)
	menu.queue_redraw()
	await _frames(6)
	await _shot("menu_difficulty")
	menu.set("stage", MainMenu.Stage.MAP)
	menu.queue_redraw()
	await _frames(6)
	await _shot("menu_map")
	menu.set("stage", MainMenu.Stage.SETTINGS)
	menu.set("setting_row", 2)
	menu.queue_redraw()
	await _frames(6)
	await _shot("menu_settings")

	# ---------------- 艾尔斯岩 · 夜沙漠 1v1（玩家开阿利宙斯常态）----------------
	menu.close_menu()
	main.call("_on_start_match", SuitProfile.Id.ARIZEUS, Difficulty.Level.NORMAL,
		MapDef.Id.ULURU, Game.MatchMode.VERSUS)
	await _frames(30)
	await _settle_camera()
	await _shot("uluru_intro")

	main.call("_start_fight")
	_make_enemy_durable()
	var p = _p()
	p.max_hp = 99999.0
	p.hp = 99999.0
	p.ifield_max = 9999.0
	p.ifield_hp = 9999.0
	# 摆在巨岩正侧方偏高空：这张图的看点就是"那块巨岩到底有多大"。
	#
	# ⚠️ **机位必须跟着巨岩搬。** 巨岩在 1.2 已从 `(-7800, 0, -5200)` 搬到
	# **`(-3400, 0, -2300)`**（拉近到 4.1 km）并放大到 **6000 × 2600 × 1200 m**
	# —— 见 `world_builder._build_desert()`。老机位 `(-3800, 2100, -2200)`
	# 看着 `(-7800, 400, -5200)`：那个方向现在只剩空沙漠，于是这张"巨岩图"里
	# **根本没有巨岩** —— 它作为"巨岩做出来了"的证据曾经作废过一次。
	#
	# 新机位在岩体**南侧 5.2 km**、比岩顶高 450 m，沿世界 X 轴正视它的长边
	# （岩体的长轴就是 X 轴）：6 km 长的岩体在 4.6 km 外约占水平视场六成，
	# 整块连顶面带斜壁一帧进得去，且机头正对岩体 —— 追尾镜头不会歪着拍。
	p.global_position = Vector3(-3400.0, 1650.0, 2900.0)
	p.look_at(Vector3(-3400.0, 560.0, -2300.0), Vector3.UP)
	p.fm.speed = 420.0
	p.fm.align_velocity(p.forward())
	_drive(Vector3.ZERO, 0.9, false, false)
	_freeze_enemy(p.global_position + p.forward() * 2400.0 + Vector3(140.0, 40.0, 0.0))
	await _settle_camera()
	await _frames(20)
	await _shot("uluru_monolith")

	# 贴着沙丘低飞（夜里的沙丘脊线靠月光读出来）
	p.global_position = Vector3(4200.0, 420.0, 2600.0)
	p.look_at(p.global_position + Vector3(-1600.0, -60.0, -2200.0), Vector3.UP)
	p.fm.speed = 360.0
	p.fm.align_velocity(p.forward())
	_freeze_enemy(p.global_position + p.forward() * 1600.0 + Vector3(80.0, -30.0, 0.0))
	await _settle_camera()
	await _frames(16)
	await _shot("uluru_low_pass")
	# 云量上去最直接的代价是**填充率**（更多半透明圆盘重叠），所以在艾尔斯岩这张
	# 云最多的图上打一次诊断 —— 不量的话"云变多了"和"帧率掉了"是同一件事的两面。
	_diag("uluru-clouds")

	# ---------------- 鼠标锁定光标 + Alt 锁定镜头 ----------------
	await _stage_lock_cursor()
	await _shot("lock_cursor")
	await _stage_lock_camera()
	await _shot("lock_camera")
	main.get("chase").call("set_lock_view", false)
	await _frames(10)

	# ---------------- 阿利宙斯常态：双联背部炮（用户指定）----------------
	# ⚠️ **必须在变形/爆壳之前拍**：爆壳之后是核心形态，那是**单管**（用户只说常态/巡航）。
	# 机位跟在机尾后方，两道并排光束从背包上方射出去的样子只有这个角度看得清。
	await _stage_twin_beam()
	await _shot("arizeus_twin_beam")

	# ---------------- 阿利宙斯三种形态 ----------------
	await _stage_form_toggle()
	await _shot("form_flash")            # 变形闪光那一瞬（换模型的遮罩）
	await _frames(26)
	await _shot("form_cruise")           # 巡航形态（飞起来之后）
	# 巡航形态的双联背部炮：**必须单独验证**——它是一套完全不同的模型，
	# 炮口高度/深度是按它自己的包围盒算的（间距那条 3× 规则与形状无关，是共用的）。
	await _stage_twin_beam(false)
	await _shot("arizeus_cruise_twin_beam")
	# 导弹弹幕：1.2 起一次扳机 3 发（用户要求"追求弹幕的华丽程度"）。
	# 巡航形态有 288 发导弹，连打 3 次扳机 = 9 发，密度才看得出来。
	await _stage_funnel()
	await _shot("arizeus_missile_barrage")
	await _stage_shell_strip()
	await _shot("shell_strip")           # 爆壳（爆炸 + 烟）
	await _frames(90)
	await _shot("form_core")             # 核心 · 量产型ν高达

	# ---------------- 常规战斗镜头（保持原有覆盖）----------------
	_drive(Vector3.ZERO, 1.0, true, false)
	await _frames(40)
	await _shot("boost_speedlines")
	_drive(Vector3.ZERO, 0.6, false, true)
	await _frames(50)
	await _shot("hover")
	_drive(Vector3.ZERO, 0.85, false, false)
	await _stage_beam()
	await _shot("beam_locked")
	await _stage_saber()
	await _shot("saber_dash")
	await _stage_pause()
	await _shot("pause_menu")
	main.call("_set_paused", false)
	await _frames(6)

	# ---------------- 训练模式：废墟靶场 ----------------
	await _stage_training()
	await _shot("training_range")
	await _frames(40)
	await _shot("training_drones")
	await _stage_training_kill()
	await _shot("training_result")

	_diag("final")
	print("CAPTURE_DONE -> ", out_dir)
	get_tree().quit(0)


# ------------------------------------------------------------ 工具

func _p() -> Node:
	var n = main.get("player")
	return n if (n != null and is_instance_valid(n)) else null


func _e() -> Node:
	var n = main.get("enemy")
	return n if (n != null and is_instance_valid(n)) else null


func _lock() -> Node:
	var n = main.get("player_lock")
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


## 把敌机冻在原地当靶子（受伤结算照常）。
func _freeze_enemy(pos: Vector3, look_at_player := true) -> void:
	var p := _p()
	var e := _e()
	if e == null or p == null:
		return
	e.set_physics_process(false)
	e.fm.velocity = Vector3.ZERO
	e.fm.speed = 0.0
	e.global_position = pos
	if look_at_player:
		e.look_at(p.global_position, Vector3.UP)


# ------------------------------------------------------------ 剧本

## 鼠标锁定光标：把光标**画到敌机身上**（真实游戏里玩家用鼠标罩住目标，
## 这里直接写光标屏幕坐标，因为无头/自动化环境没有真实鼠标事件）。
func _stage_lock_cursor() -> void:
	var p := _p()
	var e := _e()
	var cam = main.get("chase")
	if p == null or e == null or cam == null:
		return
	_freeze_enemy(p.global_position + p.forward() * 1700.0 + Vector3(90.0, -40.0, 0.0))
	await _frames(20)
	p.cursor_seen = true
	p.aim_cursor = cam.unproject_position(e.global_position)
	await _frames(50)      # 等锁定进度走满
	p.aim_cursor = cam.unproject_position(e.global_position)


## Alt 锁定镜头（开关式）：切过去之后镜头盯着锁定目标，而不是机头前方。
func _stage_lock_camera() -> void:
	var p := _p()
	if p == null:
		return
	_drive(Vector3.ZERO, 0.85, false, false)
	main.get("chase").call("set_lock_view", true)
	await _frames(30)


## 导弹弹幕：连打 3 次扳机。
##
## 1.2 起一次扳机出 **3 发**（`SuitProfile.MISSILE_PER_SHOT`），所以这里是 9 发在飞 ——
## 只打一次扳机的话画面上只有 3 发，"弹幕"这件事看不出来。
func _stage_funnel() -> void:
	var p := _p()
	var e := _e()
	if p == null or e == null or p.profile == null or not p.profile.has_missiles:
		return
	# 打远一点、抬高一点：近距离导弹会缩成一团，拉开才看得出扇形的展开
	_freeze_enemy(p.global_position + p.forward() * 2400.0 + Vector3(0.0, 240.0, 0.0))
	_drive(Vector3.ZERO, 0.9, false, false)
	await _frames(12)
	for i in 3:
		p.funnel_cooldown = 0.0
		p.call("fire_funnel", e)
		await _frames(9)
	await _frames(4)


## 双联背部炮：把敌机摆到正前方，开**一枪**（一次扳机两道）。
##
## 拍的是"光束刚离膛"的那几帧 —— 两道在背包上方并排、还没在准星处收拢，
## 一眼就能看出是两发而不是一发粗的。等太久两道会交汇成一道，图就失去意义了。
func _stage_twin_beam(force_normal := true) -> void:
	var p := _p()
	var e := _e()
	if p == null or e == null:
		return
	# 保险：默认这一张要的是常态（单管/双管的区别就在这里）。
	# 巡航形态那张传 false —— 它也是双联，但它是一套**完全不同的模型包围盒**，
	# 炮口高度/深度是按它自己的算的，必须单独拍一张才算验证过。
	if force_normal and p.form_index != SuitProfile.ArizeusForm.NORMAL:
		p.form_cooldown = 0.0
		p.call("switch_form", SuitProfile.ArizeusForm.NORMAL, true)
	_freeze_enemy(p.global_position + p.forward() * 1500.0 + Vector3(0.0, 40.0, 0.0))
	p.rifle_mag = p.profile.rifle_magazine
	p.rifle_cooldown = 0.0
	await _frames(20)
	p.rifle_cooldown = 0.0
	p.call("fire_beam", true, e, true)
	# ⚠️ 只等**3 帧**：光束长 250 m，等 6 帧它已经飞出两百多米、被压缩成一小段，
	# 两道之间的空隙也就看不出来了。3 帧时两道还在炮口附近，间距最清楚。
	await _frames(3)


## 变形（Z）：闪光 + 换模型。
func _stage_form_toggle() -> void:
	var p := _p()
	if p == null:
		return
	_drive(Vector3.ZERO, 1.0, false, false)
	p.call("toggle_form")
	await _frames(3)      # 闪光刚起来的那一瞬


## 残血爆壳：把血量压到血线以下，触发"爆炸 → 烟雾 → 换核心形态"。
func _stage_shell_strip() -> void:
	var p := _p()
	if p == null:
		return
	p.ifield_hp = 0.0
	p.take_damage(p.max_hp * 0.5, null, Damage.Type.BEAM)
	await _frames(6)


func _stage_beam() -> void:
	var p := _p()
	var e := _e()
	if p == null or e == null:
		return
	_drive(Vector3.ZERO, 0.85, false, false)
	_freeze_enemy(p.global_position + p.forward() * 1500.0 + Vector3(70, -60, 0))
	await _frames(85)
	for i in 6:
		p.rifle_cooldown = 0.0
		p.call("fire_beam", true, e, true)
		await _frames(10)
	await _frames(80)
	if is_instance_valid(e):
		_freeze_enemy(p.global_position + p.forward() * 1200.0 + Vector3(60, -50, 0))
	await _frames(10)


func _stage_saber() -> void:
	var p := _p()
	var e := _e()
	if p == null:
		return
	p.saber_cooldown = 0.0
	p.saber_state = 0
	var target = e
	if e != null:
		e.set_physics_process(true)
		e.global_position = p.global_position + p.forward() * 560.0 + Vector3(150, 40, 0)
		e.look_at(p.global_position, Vector3.UP)
		e.fm.speed = 240.0
		e.fm.align_velocity(e.forward())
	await _frames(6)
	p.call("try_saber", target)
	await _frames(13)


func _stage_pause() -> void:
	main.call("_set_paused", true)
	await _frames(12)


## 训练模式：重新开一局（靶场 + 四架古斯塔夫00）。
func _stage_training() -> void:
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY,
		MapDef.Id.RANGE, Game.MatchMode.TRAINING)
	await _frames(20)
	main.call("_start_fight")
	await _frames(20)
	var p := _p()
	if p != null:
		p.max_hp = 99999.0
		p.hp = 99999.0
		# 从上方俯视靶场：靶环、废墟、探照灯一次看全
		p.global_position = Vector3(2600.0, 1500.0, 2600.0)
		p.look_at(Vector3(0.0, 400.0, 0.0), Vector3.UP)
		p.fm.speed = 320.0
		p.fm.align_velocity(p.forward())
		_drive(Vector3.ZERO, 0.8, false, false)
	await _settle_camera()
	await _frames(20)


## 训练：把光标罩到最近的一架靶机上，展示"鼠标锁定 + 靶机"的实战观感。
func _stage_training_kill() -> void:
	var p := _p()
	var cam = main.get("chase")
	var targets: Array = main.get("targets")
	if p == null or cam == null or targets.is_empty():
		return
	var d = targets[0]
	if d != null and is_instance_valid(d):
		p.global_position = d.global_position + Vector3(0.0, 260.0, 1500.0)
		p.look_at(d.global_position, Vector3.UP)
		p.fm.speed = 300.0
		p.fm.align_velocity(p.forward())
		p.cursor_seen = true
		p.aim_cursor = cam.unproject_position(d.global_position)
		await _frames(40)
		p.aim_cursor = cam.unproject_position(d.global_position)
		await _frames(30)
	# 打光所有靶机 → 结算
	for t in targets:
		if is_instance_valid(t) and t.alive:
			t.ifield_hp = 0.0
			t.take_damage(99999.0, p, Damage.Type.SABER)
			await _frames(6)
	await _frames(40)


# ------------------------------------------------------------ 诊断

func _diag(tag: String) -> void:
	var p := _p()
	var cam = main.get("chase")
	var e := _e()
	if p == null or cam == null:
		return
	var ehp := "n/a"
	if e != null:
		ehp = "%d/%d" % [int(e.hp), int(e.max_hp)]
	# 云实例数：云量是**按地图**配的（`MapDef.cloud_density`），
	# 不数出来就没法验证"这张图真的更密"，也没法和帧率一起看代价。
	var clouds := 0
	var w: Node = main.get("world")
	if w != null:
		var cr: Node = w.get("_cloud_root")
		if cr != null:
			for c: Node in cr.get_children():
				var mm := c as MultiMeshInstance3D
				if mm != null and mm.multimesh != null:
					clouds += mm.multimesh.instance_count
	print("[diag %s] map=%s clouds=%d mode=%d suit=%s form=%d/%d hp=%d/%d fps=%d camdist=%.1f alt=%.0f spd=%.0f lockcam=%s targets_down=%d/%d"
		% [tag,
			Game.active_map.code if Game.active_map != null else "?",
			clouds,
			Game.match_mode,
			p.profile.id_name(), p.form_index, p.form_count(),
			int(p.hp), int(p.max_hp), Engine.get_frames_per_second(),
			cam.global_position.distance_to(p.global_position),
			p.global_position.y, p.airspeed_kmh(),
			str(cam.lock_view_active()), Game.training_targets_down, Game.training_targets_total])


func _shot(name: String) -> void:
	_shot_index += 1
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
	var path := out_dir.path_join("%02d_%s.png" % [_shot_index, name])
	var err := img.save_png(path)
	print("SHOT %s  err=%d" % [path, err])
