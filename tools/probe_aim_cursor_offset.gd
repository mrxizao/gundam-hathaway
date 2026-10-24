extends Node
## 判据探针：**准星在屏幕上推到哪儿，弹道就打到哪儿吗**。
##
## ## 用户原话（轮 40 追加）
##
##   「向上发射光束步枪，为什么光束步枪的子弹还是会朝前？」
##
## ## 为什么值得单开一个探针
##
## 「准星画在哪」和「弹道指向哪」在全工程里是**两个独立的量**，各有各的真源：
##
##   · **准星** = `hud.gd::_draw_aim_cursor()` 直接画在 `player.aim_cursor` 上 ——
##     那是**原始鼠标像素**，能推到屏幕的任意角落。
##   · **弹道** = `player_controller.gd::_read_aim_input()`。
##     **轮 41 之前**：`normalize(-cb.z + cb.x*m.x*MOUSE_GAIN + cb.y*(-m.y)*MOUSE_GAIN)`，
##     `m = (aim_cursor/vs)*2 - 1`、`MOUSE_GAIN = 0.55` ⇒ 偏角恒等于 `atan(0.55*|m|)`，
##     单轴上限 `atan(0.55) = 28.81°`、对角上限 `37.88°`。
##     **轮 41 起**：`cam.project_ray_normal(aim_cursor)` ⇒ 与准星像素同源。
##     探针自己**读源码判定**当前是哪一种，所以同一支探针改前改后都自证。
##
## 鼠标像素隐含的角度（按 FOV 算：半屏上缘 = fov/2 = 34°、左右缘 ≈ 50°）
## 与 `0.55*|m|` **不是同一个量**（一个是 tan 线性、一个是角度线性，且被 0.55 压过）
## ⇒ 准星离屏幕中心越远，两者差得越多。这就是「准星指着头顶、弹道还在前头」的来源。
##
## ## 每个准星位置量四件事（少一个都归不了因）
##
##   ① 准星**承诺**的方向 = `cam.project_ray_normal(准星像素)`
##   ② `aim_forward()`     = 弹道真正读的方向
##   ③ ① 与 ② 的夹角        = **瞄准误差**（这是本探针的判据）
##   ④ 真发一发光束、停在 220 m，它在屏幕上的落点 vs 准星像素
##      （② 是"读的"，④ 是"飞的" —— 两者必须一致，否则还有第二个错）
##
## ## 相机是**真的 `ChaseCamera`**，不是我手搓的
##
## 机位 / FOV / 视线俯角全都影响投影，手搓一个就有"探针自己引入误差"的风险。
## 所以这里 preload `chase_camera.gd`、`set_target(_pc)`，让工程自己把它摆到位。
##
## 用法：
##   "C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" \
##     --headless --path . res://tools/probe_aim_cursor_offset.tscn

const ALT := 3000.0
## 把弹丸停在离炮口多远来量屏幕落点。220 m 落在光束的"出膛慢速段"里，
## 是玩家真能看见那根光柱的距离。
const PARK_AT := 220.0
## 锁定目标放在正前方多远（复刻用户截图里的 6.5 km）。
const TARGET_RANGE := 6500.0

const ChaseCameraScript := preload("res://scripts/flight/chase_camera.gd")

var _host: Node3D = null
var _cont: Node3D = null
var _pc: PlayerController = null
var _cam: Camera3D = null
var _tgt: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("=== 探针结束 ===")
	get_tree().quit()


## ⚠️ **立即打印**，不攒到最后统一输出。
##
## 上一轮踩过：`_say()` 只往数组里塞、末尾统一 print，于是脚本一有解析错
## （`_ready()` 压根不跑）或中途卡住，重定向到文件的 stdout 就**一个字都没有** ——
## 看起来像"跑得慢"，实际是"根本没跑"。白等 10 分钟。立即打印 ⇒ 进度一眼可见。
func _say(s: String) -> void:
	print(s)


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ang(a: Vector3, b: Vector3) -> float:
	if a.length_squared() < 1e-9 or b.length_squared() < 1e-9:
		return -1.0
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


func _fmt3(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


## 方向的**世界仰角**（度）。+ = 朝上、− = 朝下。这是"向上发射"最直接的读数。
func _elev(v: Vector3) -> float:
	if v.length_squared() < 1e-9:
		return -999.0
	return rad_to_deg(asin(clampf(v.normalized().y, -1.0, 1.0)))


## 「落点半径是准星半径的百分之几」。
## ⚠️ 准星落在屏幕中心时半径是 **0**，除法会炸 —— 那一格返回 "—"，
## 不要写 `maxf(分母, 0.001)` 那种"防炸但给出 4653386%"的假读数
##（本探针第一版就是这么写的，屏心那一格的百分比是完全没意义的数字）。
func _pct(shot_r: float, cursor_r: float) -> String:
	if cursor_r < 1.0:
		return "—"
	return "%.0f" % (shot_r / cursor_r * 100.0)


func _clear_shots() -> void:
	for c: Node in _cont.get_children():
		if c != _pc:
			c.queue_free()


## 打一发光束，**立刻停住**在离炮口 `PARK_AT` 米处（只动位置、不动旋转）。
## 返回 [弹丸, 出膛点, 飞行方向]；打不出来就返回空数组。
func _fire_parked(target: Node3D) -> Array:
	var before := _cont.get_child_count()
	_pc.rifle_cooldown = 0.0
	_pc.rifle_reloading = false
	_pc.rifle_count = maxi(_pc.rifle_count, 3)
	_pc.rifle_mag = maxi(_pc.rifle_mag, 20)
	_pc.fire_beam(true, target)
	var after := _cont.get_child_count()
	if after <= before:
		return []
	var p := _cont.get_child(after - 1) as Node3D
	var d: Vector3 = p.get("direction")
	var from := p.global_position
	p.set_physics_process(false)
	p.global_position = from + d.normalized() * PARK_AT
	return [p, from, d]


## 一个准星位置：把「准星承诺的」「弹道读的」「弹道飞的」并排量出来。
##
## `fx, fy` 是**屏幕比例**（0..1），与分辨率无关 —— 探针在 headless 下
## 拿到的 viewport 尺寸不一定是 1600x900，写死像素就不是同一件事了。
func _case(label: String, fx: float, fy: float, target: Node3D) -> void:
	var vs := get_viewport().get_visible_rect().size
	var cursor := Vector2(fx * vs.x, fy * vs.y)
	var m := (cursor / vs) * 2.0 - Vector2.ONE
	m.x = clampf(m.x, -1.0, 1.0)
	m.y = clampf(m.y, -1.0, 1.0)

	_pc.cursor_seen = true
	_pc.aim_cursor = cursor
	await _phys(3)

	var aim: Vector3 = _pc.aim_forward()
	var nose: Vector3 = _pc.forward()
	var cam_fwd: Vector3 = -_cam.global_transform.basis.z
	# ① 准星"承诺"的方向：相机穿过该像素的射线
	var ray := _cam.project_ray_normal(cursor)
	# ② 弹道实际读的方向
	var err := _ang(ray, aim)

	var center := vs * 0.5
	var r_cursor := cursor.distance_to(center)

	_say("  ── %s" % label)
	_say("     准星像素 (%.0f, %.0f)  = 屏幕比例 (%.3f, %.3f)   m=(%+.3f, %+.3f)"
		% [cursor.x, cursor.y, fx, fy, m.x, m.y])
	_say("     ① 准星承诺  ray       %s   世界仰角 %+7.2f°   离屏心 %.0f px"
		% [_fmt3(ray), _elev(ray), r_cursor])
	_say("     ② aim_forward()       %s   世界仰角 %+7.2f°"
		% [_fmt3(aim), _elev(aim)])
	_say("     ★ ③ 瞄准误差 ①↔②     **%7.2f°**   （准星说朝上 %.1f°、弹道只朝上 %.1f°）"
		% [err, _elev(ray), _elev(aim)])
	_say("       aim_forward 与 机头 %7.2f°  与 相机前向 %7.2f°   （相机前向仰角 %+.2f°）"
		% [_ang(aim, nose), _ang(aim, cam_fwd), _elev(cam_fwd)])
	# ② 落在屏幕上哪儿（"读的"这个方向，画出来在哪）
	var aim_px := _cam.unproject_position(_pc.global_position + aim * 1000.0)
	var aim_r := aim_px.distance_to(center)
	_say("       ② 在屏幕上落在 (%.0f, %.0f)   离屏心 %.0f px   （准星 %.0f px ⇒ 弹道方向 = 准星的 %s%%）"
		% [aim_px.x, aim_px.y, aim_r, r_cursor, _pct(aim_r, r_cursor)])

	# ④ 真发一发，看它停在哪儿（"飞的"）
	var shot := await _fire_parked(target)
	if shot.is_empty():
		_say("     ④ **没打出来**（门禁未过）")
		return
	var p: Node3D = shot[0]
	var d: Vector3 = shot[2]
	var shot_px := _cam.unproject_position(p.global_position)
	var shot_r := shot_px.distance_to(center)
	_say("     ④ 光束停 %.0f m 处   落点 (%.0f, %.0f)   离屏心 %.0f px   （准星 %.0f px ⇒ 光束 = 准星的 %s%%）"
		% [PARK_AT, shot_px.x, shot_px.y, shot_r, r_cursor, _pct(shot_r, r_cursor)])
	_say("       ④ 与 ② 夹角 %7.3f°  ← 这一项必须 ≈0，否则「读的」和「飞的」分家了"
		% _ang(d, aim))
	_clear_shots()


func _run() -> void:
	_say("")
	_say("################################################################")
	_say("#  探针：准星推到屏幕上边/角落时，弹道到底偏了多少度")
	_say("################################################################")

	Game.reset()
	_host = Node3D.new()
	add_child(_host)
	# 真机里 `Main` 的 `projectiles` 就是这么挂的（main.gd:159），这里照搬
	_cont = Node3D.new()
	_cont.name = "Projectiles"
	_host.add_child(_cont)

	# ⚠️ 用**真的 ChaseCamera**：机位(0,9,53)、视线俯角、FOV 动态全都影响投影，
	#    手搓一个就有"探针自己引入误差"的风险 —— 那正是本探针要量的东西。
	_cam = ChaseCameraScript.new()
	_cam.name = "Chase"
	_host.add_child(_cam)

	_pc = PlayerController.new()
	_pc.name = "PC"
	_pc.team = 0
	_pc.is_player = true
	_pc.profile = SuitProfile.xi()
	_pc.display_name = "PC"
	_pc.projectile_container = _cont
	_cont.add_child(_pc)
	_pc.global_position = Vector3(0.0, ALT, 0.0)
	_pc.max_hp = 600.0
	_pc.hp = 600.0
	_pc.ifield_max = 0.0
	_pc.ifield_hp = 0.0
	_pc.fm.speed = 260.0
	_pc.fm.throttle = 0.78
	_pc.fm.align_velocity(_pc.forward())
	await get_tree().process_frame
	await _phys(3)

	_cam.call("set_target", _pc)
	await _phys(6)

	# 锁定目标：正前方 6.5 km（复刻用户截图里那条 `6.5 km` 的锁定）
	_tgt = Node3D.new()
	_tgt.name = "Tgt"
	_host.add_child(_tgt)
	_tgt.global_position = _pc.global_position + (-_pc.global_transform.basis.z) * TARGET_RANGE

	_pc.controls_enabled = true
	_pc.debug_input_enabled = true
	_pc.debug_input = Vector3.ZERO
	_pc.debug_throttle = 0.8
	_pc.mouse_lock_enabled = true
	_pc.cursor_seen = false
	_pc.set_aim_direction(Vector3.ZERO)
	await _phys(4)

	var vs := get_viewport().get_visible_rect().size
	var think_ran := absf(_pc.fm.throttle - 0.8) < 0.001
	var cam_fwd: Vector3 = -_cam.global_transform.basis.z

	_say("")
	_say("--- 0 环境自检（先证明探针自己没坏）---")
	_say("  pc.alive                = %s   ← false 则 _physics_process 直接 return" % str(_pc.alive))
	_say("  _think() 在跑           = %s   （判据 fm.throttle = %.3f，期望 0.800）"
		% [str(think_ran), _pc.fm.throttle])
	_say("  viewport 可见尺寸        = %.0f x %.0f" % [vs.x, vs.y])
	_say("  相机（真 ChaseCamera）    fov = %.2f   near = %.2f   距机体 %.1f m"
		% [_cam.fov, _cam.near, _cam.global_position.distance_to(_pc.global_position)])
	_say("  相机前向仰角             %+.2f°   ← 追尾机位比机头略低看，这个角会整个平移到弹道上"
		% _elev(cam_fwd))
	_say("  机头仰角                 %+.2f°" % _elev(_pc.forward()))
	# ⚠️ **弹道真源要读源码判定，不能在这里硬编码 0.55**：轮 41 把
	# `MOUSE_GAIN` 换成 `project_ray_normal(aim_cursor)` 之后，硬编码的那几行
	# 会继续打印一张"老公式的表"，看起来像探针在自证——其实是过期读数。
	var pc_src0 := FileAccess.get_file_as_string("res://scripts/flight/player_controller.gd")
	var uses_gain := pc_src0.contains("MOUSE_GAIN")
	if uses_gain:
		_say("  弹道真源（读源码判定）     老公式：像素偏移 × MOUSE_GAIN(0.55)"
			+ " ⇒ 单轴上限 atan(0.55) = %.2f°、对角 %.2f°"
			% [rad_to_deg(atan(0.55)), rad_to_deg(atan(0.55 * sqrt(2.0)))])
	else:
		_say("  弹道真源（读源码判定）     相机射线 `cam.project_ray_normal(aim_cursor)`"
			+ " ⇒ 与准星像素**同源**，偏角上限 = 屏幕角落的射线角")
	_say("  rifle_pellets            %d" % _pc.profile.rifle_pellets)
	if not think_ran or not _pc.alive:
		_say("")
		_say("  ❌ **自检没过 —— 下面所有读数无效，先修探针。**")
		return

	# 解析上界：屏幕各边缘的像素隐含多少度（按 KEEP_HEIGHT 的 f = (H/2)/tan(fov/2)）
	var f := (vs.y * 0.5) / tan(deg_to_rad(_cam.fov) * 0.5)
	_say("")
	_say("--- 1 解析上界：准星承诺的偏角 vs 弹道能给的偏角 ---")
	_say("  像素焦距 f = (H/2)/tan(fov/2) = %.1f px   （未设 keep_aspect ⇒ Godot 默认 KEEP_HEIGHT）" % f)
	_say("  %-16s %-14s %-14s %s" % ["准星推到", "承诺偏角", "弹道偏角", "差"])
	var probes := [
		["屏幕正上缘", Vector2(0.0, -1.0)],
		["屏幕正下缘", Vector2(0.0, 1.0)],
		["屏幕左缘", Vector2(-1.0, 0.0)],
		["屏幕右缘", Vector2(1.0, 0.0)],
		["左上角", Vector2(-1.0, -1.0)],
	]
	for pr: Array in probes:
		var mm: Vector2 = pr[1]
		# 承诺偏角 = 该像素相对屏心的**真实射线角**（两轴各有各的像素尺度，先合成再 atan）
		var dx := mm.x * vs.x * 0.5
		var dy := mm.y * vs.y * 0.5
		var promised := rad_to_deg(atan(Vector2(dx, dy).length() / f))
		if uses_gain:
			var given := rad_to_deg(atan(0.55 * mm.length()))
			_say("  %-16s %-14s %-14s %+.2f°" % [pr[0], "%.2f°" % promised, "%.2f°" % given,
				given - promised])
		else:
			_say("  %-16s %-14s %-14s 0.00°（同源）" % [pr[0], "%.2f°" % promised, "%.2f°" % promised])
	_say("")
	if uses_gain:
		_say("  读法：'弹道偏角' = atan(0.55*|m|)，只跟鼠标的归一化偏移有关；")
		_say("        '承诺偏角' = 该像素的相机射线角，按 FOV 算。两者只在屏幕中心相等。")
	else:
		_say("  读法：弹道方向 = 该像素的相机射线 ⇒ **承诺偏角 与 弹道偏角 恒等**，")
		_say("        与离屏幕中心多远无关（这正是轮 41 修的东西）。")

	# ---- 2 逐位置实测（无目标 / 有目标各一遍）----
	_say("")
	_say("--- 2 实测：准星位置 → 弹道方向 → 屏幕落点 ---")
	_say("")
	_say("[[2a 无锁定目标]]")
	await _case("屏幕正中心 (0.500, 0.500)", 0.5, 0.5, null)
	await _case("用户截图的那个位置 (0.250, 0.331)", 0.25, 0.331, null)
	await _case("屏幕正上方 (0.500, 0.030)", 0.5, 0.03, null)
	await _case("屏幕左上角 (0.030, 0.030)", 0.03, 0.03, null)
	await _case("屏幕正左 (0.030, 0.500)", 0.03, 0.5, null)

	_say("")
	_say("[[2b 锁定正前方 6.5 km 的目标（复刻截图那一帧）]]")
	await _case("用户截图的那个位置 (0.250, 0.331)", 0.25, 0.331, _tgt)
	await _case("屏幕正上方 (0.500, 0.030)", 0.5, 0.03, _tgt)

	# ---- 3 源码事实 ----
	_say("")
	_say("--- 3 源码事实（行号，别信记忆）---")
	var pc_src := FileAccess.get_file_as_string("res://scripts/flight/player_controller.gd")
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	for pair: Array in [
			[pc_src, "const MOUSE_GAIN := 0.55", "player_controller.gd"],
			[pc_src, "set_aim_direction((-cb.z + cb.x * m.x * MOUSE_GAIN", "player_controller.gd"],
			[hud_src, "var p: Vector2 = player.aim_cursor", "hud.gd"],
			[hud_src, "draw_line(p + Vector2(0, -arm - g), p + Vector2(0, -g)", "hud.gd"]]:
		var src: String = pair[0]
		var key: String = pair[1]
		var i := src.find(key)
		_say("  %s  %-58s 行号 = %s"
			% [pair[2], key.substr(0, 56),
				str(src.substr(0, i).count("\n") + 1) if i > 0 else "**找不到**"])
	_say("")
