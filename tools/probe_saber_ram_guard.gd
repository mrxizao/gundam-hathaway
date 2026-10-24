extends Node
## 判据出图探针：★63-25 军刀近战自伤豁免（真机 = 真物理帧 + 真像素）。
##
## ## 用户报的现象
## 「光束军刀近战容易砍到对方机体的同时自己还掉血」
## 机理：命中判定在 `saber_hit_range`（78 m）就触发，而那一刻 `_slash()` 已经
## `_end_saber()` **收招了、速度却没归零** ⇒ 两机继续贴近到碰撞胶囊（5~7 m）
## ⇒ 一次「砍中」几乎必然附带一次撞机结算（双方各 45）。
##
## ## 这一版要证的（可证伪）
##   ① 真机跑**生产路径**：`PlayerController.try_saber(foe)` ⇒ 突进 ⇒ 砍中 ⇒ 贴脸
##      ⇒ 玩家 HP **一点不掉**、`ram_cooldown` **全程没被写**；
##   ② 而且对方**确实挨了军刀那一刀**（`foe.hp` 掉了 —— 否则"没掉血"只是因为
##      压根没打中，本条就成了空转）；
##   ③ **对照**（用户要的「其他时候正常」）：同一个摆位**不按军刀**、纯撞上去
##      ⇒ 双方各掉一次撞击伤害、`ram_cooldown` 被写上 1.0。
##
## ①②③ 都在同一张图上：两种情形各出一排真机截图 + 逐帧遥测表。
##
## ## 跑法（⚠️ **不能加 `--headless`**：无头下 RenderingServer 是 dummy，图全黑）
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       res://tools/probe_saber_ram_guard.tscn -- <输出目录>
##
## ## ⚠️ 从 saber_blade_shots 继承的两条坑（别重踩）
##   · **抓图本身会推进物理帧**（渲染帧与物理帧不同步，一抓吃 6~27 步）
##     ⇒ 抓图前 `get_tree().paused = true`，抓完解冻。
##   · 别为了"维持突进"把靶机弄死 —— 那会让 `saber_target` 当帧失效、
##     走空挥回收。本探针**不需要**靶机活着维持突进（突进本来就要结束），
##     所以直接用活靶机，让它真的挨刀。

const ALT := 3000.0
const SHOT_W := 1280
const SHOT_H := 720
const RENDER_WAIT := 3

## 情形 A（军刀突进）：靶机放在吸附距离内（玩家 `player_saber_magnet` = 1400 m）。
const A_FOE_Z := -420.0
const A_FRAMES := 110
## 情形 B（纯撞击，对照）：抄 headless 的摆位（70 m / 200 m/s ⇒ 约 21 帧贴上）。
const B_FOE_Z := -70.0
const B_FRAMES := 90

var _out := "user://saber_ram_guard_shots"
var _host: Node3D
var _cont: Node3D
var _cam: Camera3D
var _shots: Array[String] = []


func _ready() -> void:
	_run()


func _say(s: String) -> void:
	print("[ramguard] ", s)


func _adv(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _capture(name: String) -> void:
	# ⚠️ 前置：世界已暂停（否则抓图会吃掉物理帧 —— 见文件头「坑」）
	for _i in RENDER_WAIT:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	_shots.append(path)
	_say("    出图 %s  %dx%d" % [path, img.get_width(), img.get_height()])


func _new_pc() -> PlayerController:
	var pc := PlayerController.new()
	pc.name = "PC"
	pc.team = 0
	pc.is_player = true
	pc.profile = SuitProfile.xi()
	pc.display_name = "PC"
	pc.projectile_container = _cont
	_cont.add_child(pc)
	pc.global_position = Vector3(0.0, ALT, 0.0)
	pc.max_hp = 600.0
	pc.hp = 600.0
	pc.ifield_max = 0.0
	pc.ifield_hp = 0.0
	pc.fm.speed = 260.0
	pc.fm.throttle = 0.78
	pc.fm.align_velocity(pc.forward())
	return pc


func _new_foe(z: float) -> FlightBody:
	var foe := FlightBody.new()
	foe.name = "Foe"
	foe.team = 1
	foe.profile = SuitProfile.penelope()
	foe.display_name = "Foe"
	foe.projectile_container = _cont
	_cont.add_child(foe)
	foe.global_position = Vector3(0.0, ALT, z)
	foe.max_hp = 600.0
	foe.hp = 600.0
	foe.ifield_max = 0.0
	foe.ifield_hp = 0.0
	foe.fm.speed = 0.0
	foe.fm.throttle = 0.0
	foe.fm.velocity = Vector3.ZERO
	foe.look_at(Vector3(0.0, ALT, 0.0), Vector3.UP)   # 面对面
	return foe


## 机位：从**侧面**看两机之间的中点，两机与刀都在画框里。
func _place_cam(pc: PlayerController, foe: FlightBody) -> void:
	var focus := (pc.global_position + foe.global_position) * 0.5
	_cam.global_position = focus + pc.right() * 210.0 + Vector3(0.0, 46.0, 0.0)
	_cam.look_at(focus, Vector3.UP)


func _setup_world() -> void:
	FlightBody.use_placeholder = false
	_host = Node3D.new()
	_host.name = "Host"
	add_child(_host)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.06, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.72, 0.90)
	env.ambient_light_energy = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	_host.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.35
	sun.rotation_degrees = Vector3(-32.0, -126.0, 0.0)
	_host.add_child(sun)
	_cont = Node3D.new()
	_cont.name = "Bodies"
	_host.add_child(_cont)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.far = 90000.0
	_host.add_child(_cam)
	_cam.current = true


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_say("输出目录 = %s" % _out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await get_tree().process_frame
	await get_tree().process_frame

	await _case_saber()
	await _case_plain()

	_say("共出图 %d 张" % _shots.size())
	for p in _shots:
		_say("  " + p)
	_say("done.")
	get_tree().quit(0)


## 情形 A：军刀突进（用户报的那个场景）。
func _case_saber() -> void:
	_say("========== 情形 A：军刀突进（砍中 → 贴脸）==========")
	_setup_world()
	var pc := _new_pc()
	var foe := _new_foe(A_FOE_Z)
	_place_cam(pc, foe)
	await get_tree().process_frame
	await _adv(4)

	if not pc.profile.has_saber:
		_say("❌ 柯西没有军刀 —— 读数无效")
		get_tree().quit(3)
		return
	_say("军刀数据：hit_range=%.0f m  magnet=%.0f m  dash_speed=%.0f m/s  dash=%.2f s"
		% [pc.profile.saber_hit_range, pc.saber_magnet_range(),
			pc.profile.saber_dash_speed, pc.saber_dash_seconds()])
	if not pc.try_saber(foe):
		_say("❌ try_saber() 失败 —— 读数无效")
		get_tree().quit(4)
		return
	_say("起手成功：saber_state=%d  吸附目标=%s"
		% [pc.saber_state, str(pc.saber_target != null)])
	_say("")
	_say(" 帧 | pc.hp | foe.hp |  距离m | saber | ram_cd | guard_left | 碰撞数")
	_say("----+-------+--------+--------+-------+--------+------------+-------")

	var hp0: float = pc.hp
	var foe_hp0: float = foe.hp
	var cd_peak := 0.0
	var guard_peak := 0.0
	var contact_frame := -1
	var saber_frame := -1
	var shot_idx := 0
	var shot_every := 0          # 运行时算：整段均匀抓 5 张
	for i in A_FRAMES:
		await get_tree().physics_frame
		var d := pc.global_position.distance_to(foe.global_position)
		var slide := pc.get_slide_collision_count()
		cd_peak = maxf(cd_peak, pc.ram_cooldown)
		guard_peak = maxf(guard_peak, pc.ram_guard_left)
		if saber_frame < 0 and foe.hp < foe_hp0:
			saber_frame = i
		if contact_frame < 0 and slide > 0:
			contact_frame = i
		_say("%3d | %5.1f | %6.1f | %6.1f | %5d | %6.3f | %10.3f | %d"
			% [i, pc.hp, foe.hp, d, pc.saber_state, pc.ram_cooldown,
				pc.ram_guard_left, slide])
		# 抓图：整段 5 张 + 砍中那一帧 + 贴上那一帧
		var want := (i == saber_frame) or (i == contact_frame) or (i % 22 == 0)
		if want and shot_idx < 9:
			shot_idx += 1
			get_tree().paused = true
			_place_cam(pc, foe)
			var tag := "A_%02d" % i
			if i == saber_frame:
				tag += "_SLASH"
			if i == contact_frame:
				tag += "_TOUCH"
			await _capture(tag)
			get_tree().paused = false

	_say("")
	_say("小结 A：砍中帧=%d  首次碰撞帧=%d  豁免余量峰值=%.3f s  ram_cooldown 峰值=%.3f"
		% [saber_frame, contact_frame, guard_peak, cd_peak])
	_say("        pc.hp %.1f -> %.1f（掉了 %.1f）   foe.hp %.1f -> %.1f（掉了 %.1f）"
		% [hp0, pc.hp, hp0 - pc.hp, foe_hp0, foe.hp, foe_hp0 - foe.hp])
	# ---- 判据 ----
	if saber_frame < 0:
		_say("❌ A：军刀整段没打中对方 —— 「没掉血」证明不了任何事，本条无效")
	elif contact_frame < 0:
		_say("❌ A：两机始终没有发生碰撞 —— 豁免根本没被触发到，本条无效")
	else:
		if is_equal_approx(pc.hp, hp0):
			_say("✅ A：砍中（帧 %d）之后贴脸撞上（帧 %d），玩家 hp 一点没掉" % [saber_frame, contact_frame])
		else:
			_say("❌ A：玩家 hp 掉了 %.1f —— 豁免没生效" % (hp0 - pc.hp))
		if cd_peak <= 0.0001:
			_say("✅ A：撞击冷却全程没被写过（峰值 %.3f）—— 豁免拦在**写冷却之前**" % cd_peak)
		else:
			_say("❌ A：撞击冷却被写过（峰值 %.3f）—— 豁免拦在了下游" % cd_peak)
		if foe.hp < foe_hp0:
			_say("✅ A：对方确实挨了军刀那一刀（foe.hp -%.1f）—— 说明是真打中了，不是空挥" % (foe_hp0 - foe.hp))
		if guard_peak >= FlightBody.RAM_GUARD_AFTER_SABER - 0.05:
			_say("✅ A：豁免余量真的到过 %.3f s（≥ RAM_GUARD_AFTER_SABER）" % guard_peak)

	get_tree().paused = false
	_host.free()
	await _adv(2)


## 情形 B（对照）：不按军刀，纯撞上去 —— 用户要的「其他时候正常」。
func _case_plain() -> void:
	_say("")
	_say("========== 情形 B（对照）：纯撞击、不按军刀 ==========")
	_setup_world()
	var pc := _new_pc()
	var foe := _new_foe(B_FOE_Z)
	foe.set_physics_process(false)          # 冻结 ⇒ 它的冷却不会递减，只可能被撞一次
	pc.fm.speed = 200.0
	pc.fm.velocity = pc.forward() * 200.0
	_place_cam(pc, foe)
	await get_tree().process_frame
	await _adv(2)

	_say("注入状态：pc.saber_state=%d（0=IDLE）  pc.ram_guard_left=%.3f  foe.ram_guard_left=%.3f"
		% [pc.saber_state, pc.ram_guard_left, foe.ram_guard_left])
	_say("")
	_say(" 帧 | pc.hp | foe.hp |  距离m | ram_cd | 碰撞数")
	_say("----+-------+--------+--------+--------+-------")

	var hp0: float = pc.hp
	var foe_hp0: float = foe.hp
	var cd_peak := 0.0
	var min_d := 1e9
	var contact_frame := -1
	var shot_idx := 0
	for i in B_FRAMES:
		await get_tree().physics_frame
		var d := pc.global_position.distance_to(foe.global_position)
		min_d = minf(min_d, d)
		var slide := pc.get_slide_collision_count()
		cd_peak = maxf(cd_peak, pc.ram_cooldown)
		if contact_frame < 0 and slide > 0:
			contact_frame = i
		_say("%3d | %5.1f | %6.1f | %6.1f | %6.3f | %d"
			% [i, pc.hp, foe.hp, d, pc.ram_cooldown, slide])
		if contact_frame == i or i % 30 == 0:
			shot_idx += 1
			if shot_idx <= 4:
				get_tree().paused = true
				_place_cam(pc, foe)
				await _capture("B_%02d%s" % [i, "_TOUCH" if contact_frame == i else ""])
				get_tree().paused = false

	_say("")
	_say("小结 B：最近距离=%.1f m  首次碰撞帧=%d  ram_cooldown 峰值=%.3f"
		% [min_d, contact_frame, cd_peak])
	_say("        pc.hp %.1f -> %.1f（掉了 %.1f）   foe.hp %.1f -> %.1f（掉了 %.1f）"
		% [hp0, pc.hp, hp0 - pc.hp, foe_hp0, foe.hp, foe_hp0 - foe.hp])
	if contact_frame < 0:
		_say("❌ B：两机没撞上 —— 对照不成立")
	else:
		var lost: float = hp0 - pc.hp
		if lost > FlightBody.RAM_DAMAGE * 0.5:
			_say("✅ B：没按军刀时照常吃撞击伤害（掉了 %.1f ≈ RAM_DAMAGE %.0f）——「其他时候正常」" % [lost, FlightBody.RAM_DAMAGE])
		else:
			_say("❌ B：纯撞击也没掉血（掉了 %.1f）—— 豁免漏到窗口之外了" % lost)
		if cd_peak > 0.5:
			_say("✅ B：撞击冷却被正常写上（峰值 %.3f）" % cd_peak)

	get_tree().paused = false
	_host.free()
	await _adv(2)
