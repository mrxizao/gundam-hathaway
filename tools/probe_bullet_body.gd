extends Node
## 判据探针：**弹体（网格）的朝向**到底有没有跟着飞行方向。
##
## ## 与 `probe_aim_follow.gd` 的分工
##
## 那个探针量的是「弹丸往哪儿飞」（`Projectile.direction`）；本探针量的是
## 「弹丸**长什么样、朝哪边**」（`MeshInstance3D` 的全局轴）。
## 用户的原话是这两件事**不一起**：
##   「子弹出膛后，子弹飞行方向是对的，但是弹体方向还是直挺挺的朝着飞行方向的其他地方」
## ⇒ 飞得对、**画得不对**。所以必须直接读网格的轴，不能只看 `direction`。
##
## ## 三个要分开量的量（少一个就无法归因）
##
##   ① `p.direction`                      —— 弹丸自己的飞行方向（已知是对的）
##   ② `-p.global_transform.basis.z`      —— `look_at()` 有没有真的落到 `p` 上
##                                            （= 父节点朝向，网格跟着它）
##   ③ 网格的**长轴**在全局里的朝向        —— 真正被看见的那条线
##
## ⚠️ ③ 的取法**按网格类型不同**（这是最容易搞错的一步）：
##   · 火神炮 = `BoxMesh`  size = (0.55, 0.55, 16.0) ⇒ 长轴是**网格局部 Z**
##   · 光束   = `CylinderMesh` 默认轴是**局部 Y** ⇒ 长轴是**网格局部 Y**
##   取错了轴，读数会显示"差 90°"，然后你会去改一段本来没坏的代码。
##
## 用法：
##   "C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" \
##     --headless --path . res://tools/probe_bullet_body.tscn

const ALT := 3000.0

var _host: Node3D = null
var _cont: Node3D = null
var _pc: PlayerController = null
var _cam: Camera3D = null
var _log: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("=== 探针结束 ===")
	get_tree().quit()


## ⚠️ **立即打印**，不攒到最后一次性输出。
##
## 踩过的坑（本探针第一版）：原来 `_say()` 只往 `_log` 里塞、`_ready()` 末尾统一 print，
## 于是**只要脚本有解析错**（`_ready()` 压根不跑）或者中途卡住，重定向到文件的 stdout
## 就**一个字都没有** —— 看起来像"跑得慢"，实际是"根本没跑"。实测白等 10 分钟才发现。
## 立即打印 + 落文件 ⇒ 有没有进度一眼可见。
func _say(s: String) -> void:
	_log.append(s)
	print(s)


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ang(a: Vector3, b: Vector3) -> float:
	if a.length_squared() < 1e-9 or b.length_squared() < 1e-9:
		return -1.0
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


func _fmt3(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]


func _clear_shots() -> void:
	for c: Node in _cont.get_children():
		if c != _pc:
			c.queue_free()


## 打一发，返回**那一发弹丸节点**（读它自己的 direction / basis / 网格轴）。
func _fire_one(kind: String) -> Node3D:
	var before := _cont.get_child_count()
	if kind == "beam":
		_pc.rifle_cooldown = 0.0
		_pc.rifle_reloading = false
		_pc.rifle_count = maxi(_pc.rifle_count, 3)
		_pc.rifle_mag = maxi(_pc.rifle_mag, 20)
		_pc.fire_beam(true, null)
	else:
		_pc.gun_cooldown = 0.0
		_pc.vulcan_overheated = false
		_pc.fire_gun(true, null)
	var after := _cont.get_child_count()
	if after <= before:
		return null
	return _cont.get_child(after - 1) as Node3D


func _aim_at(p: Vector2) -> bool:
	var f := get_viewport().get_final_transform()
	var ev := InputEventMouseMotion.new()
	ev.position = f * p
	ev.global_position = ev.position
	ev.relative = Vector2.ZERO
	Input.parse_input_event(ev)
	await _phys(2)
	if _pc.aim_cursor.distance_to(p) <= 1.0:
		return true
	_pc.cursor_seen = true
	_pc.aim_cursor = p
	await _phys(2)
	return false


## 运行期读出「这个弹丸网格最长的那根局部轴」，换算到世界方向。
## 返回 [世界方向: Vector3, 说明: String]。
##
## 为什么不用「盒子长轴是 Z / 圆柱轴是 Y」这种记忆：这两条一旦哪天被改（比如
## `_vulcan_mesh.size` 被写成 (0.55, 16.0, 0.55)），弹体就会**竖着飞**，而按
## 记忆取轴的写法会照样报「0° 共线」，把缺陷整个藏过去。所以这里读资源实际尺寸。
func _mesh_long_axis(mi: MeshInstance3D) -> Array:
	if mi == null:
		return [Vector3.ZERO, "**没有网格子节点**"]
	if mi.mesh is BoxMesh:
		var dims := (mi.mesh as BoxMesh).size
		var ai := 0
		if dims.y > dims[ai]:
			ai = 1
		if dims.z > dims[ai]:
			ai = 2
		var loc := Vector3.ZERO
		loc[ai] = 1.0
		return [mi.global_transform.basis * loc,
			"BoxMesh 最长轴 = 局部 %s（size=%s）" % ["XYZ"[ai], _fmt3(dims)]]
	if mi.mesh is CylinderMesh:
		var cm := mi.mesh as CylinderMesh
		return [mi.global_transform.basis.y,
			"CylinderMesh 轴 = 局部 Y（height=%.1f）" % cm.height]
	return [mi.global_transform.basis.z, "未知网格，退回局部 Z"]


## 量一发弹：打印 ①②③ 三条，并算夹角。
func _measure(tag: String, kind: String, aim: Vector3, nose: Vector3) -> void:
	var p := _fire_one(kind)
	if p == null:
		_say("     %-10s **没打出来**（门禁未过）" % tag)
		return
	var d: Vector3 = p.get("direction")
	# ② look_at 是否生效：它把 −Z 对准飞行方向
	var parent_axis := -p.global_transform.basis.z
	# ③ 网格长轴（⚠️ **不靠"我记得盒子长轴是 Z"这种记忆**：读网格资源的实际
	#     尺寸，自己挑出最长的那根局部轴。理由是"长轴取错"正是本探针要排除的
	#     头号风险 —— 盒子若是 (0.55, 16.0, 0.55)（长轴 = 局部 Y），弹体就会
	#     **竖着飞**，而按记忆取 basis.z 的写法会照样报"0° 共线"，把缺陷藏过去。）
	var mi := p.get_child(0) as MeshInstance3D
	var got := _mesh_long_axis(mi)
	var mesh_axis: Vector3 = got[0]
	var mesh_local_axis: String = got[1]
	_say("     %-10s ① 飞行方向 %s" % [tag, _fmt3(d)])
	_say("               ② −(p.basis.z)  %s   与①夹角 %7.3f°"
		% [_fmt3(parent_axis), _ang(parent_axis, d)])
	_say("               ③ 网格长轴     %s   与①夹角 %7.3f°   [%s]"
		% [_fmt3(mesh_axis), _ang(mesh_axis, d), mesh_local_axis])
	_say("                  网格长轴与**机头**夹角 %7.3f°" % _ang(mesh_axis, nose))
	_say("                  网格长轴与**世界UP**夹角 %7.3f°   ← ≈0 就是竖着飞"
		% _ang(mesh_axis, Vector3.UP))
	if mi != null:
		_say("                  网格 local: rotation=%s  scale=%s"
			% [_fmt3(mi.rotation_degrees), _fmt3(mi.scale)])
	_say("                  p.rotation = %s   p.position=%s"
		% [_fmt3(p.rotation_degrees), _fmt3(p.global_position)])
	_clear_shots()


func _run() -> void:
	_say("")
	_say("################################################################")
	_say("#  探针：弹体（网格）朝向 vs 飞行方向 vs 机头")
	_say("################################################################")

	Game.reset()
	_host = Node3D.new()
	add_child(_host)
	# 真机里 `Main` 的 `projectiles` 就是这么挂的（main.gd:159），这里照搬
	_cont = Node3D.new()
	_cont.name = "Projectiles"
	_host.add_child(_cont)

	_cam = Camera3D.new()
	_cam.current = true
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

	_cam.global_position = _pc.global_position + Vector3(0.0, 0.0, 120.0)
	_cam.look_at(_pc.global_position, Vector3.UP)

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

	_say("")
	_say("--- 0 环境自检（先证明探针自己没坏）---")
	_say("  pc.alive               = %s   ← false 则 _physics_process 直接 return" % str(_pc.alive))
	_say("  _think() 在跑          = %s   （判据 fm.throttle = %.3f，期望 0.800）"
		% [str(think_ran), _pc.fm.throttle])
	_say("  viewport 可见尺寸       = %.0f x %.0f" % [vs.x, vs.y])
	_say("  projectile_container    = %s（父=%s）← 真机里是 Main 的 `Projectiles`"
		% [str(_cont.name), str(_host.name)])
	_say("  container 全局 basis 是单位阵 = %s   ← 若不是单位阵，下面的读数会带一个固定偏转"
		% str(_cont.global_transform.basis.is_equal_approx(Basis())))
	_say("  rifle_pellets          = %d   ← >1 时一次扳机打出多道，探针只读最后一个"
		% _pc.profile.rifle_pellets)
	if not think_ran or not _pc.alive:
		_say("")
		_say("  ❌ **自检没过 —— 下面所有读数无效，先修探针。**")
		return

	# ---- 1 九个准星位置 ----
	_say("")
	_say("--- 1 九个准星位置：三种弹各量一次 ---")
	_say("  读法：③ 网格长轴 vs ① 飞行方向的夹角 ≈ 0 ⇒ 弹体朝向**对**；")
	_say("        若 ≈ 90° 或 ≈ ① vs 机头那个角 ⇒ 弹体朝向**没跟着方向**。")
	_say("")
	var spots: Array = [
		["正中", Vector2(vs.x * 0.50, vs.y * 0.50)],
		["右", Vector2(vs.x * 0.92, vs.y * 0.50)],
		["左", Vector2(vs.x * 0.08, vs.y * 0.50)],
		["上", Vector2(vs.x * 0.50, vs.y * 0.10)],
		["下", Vector2(vs.x * 0.50, vs.y * 0.90)],
		["左上", Vector2(vs.x * 0.12, vs.y * 0.15)],
		["右上", Vector2(vs.x * 0.88, vs.y * 0.15)],
		["左下", Vector2(vs.x * 0.12, vs.y * 0.85)],
		["右下", Vector2(vs.x * 0.88, vs.y * 0.85)],
	]
	for s: Array in spots:
		await _aim_at(s[1] as Vector2)
		var aim := _pc.aim_forward()
		var nose := _pc.forward()
		_say("  ── 准星「%s」  aim_forward %s  ·  机头 %s" % [s[0], _fmt3(aim), _fmt3(nose)])
		_measure("光束", "beam", aim, nose)
		_measure("火神炮", "vulcan", aim, nose)
		await _phys(1)

	# ---- 2 直接手造三发（绕开一切游戏链路）----
	_say("")
	_say("--- 2 直接 `Projectile.beam/vulcan()` 手造：不看准星，只验几何 ---")
	_say("  （绕开 PlayerController / aim_point —— 若这里也不对，问题在 Projectile 内部；")
	_say("    若这里对、第 1 节不对，问题在开火侧传进来的 dir）")
	var dirs: Array = [
		["前 −Z", Vector3(0, 0, -1)],
		["右上", Vector3(0.6, 0.4, -0.7).normalized()],
		["正右 +X", Vector3(1, 0, 0)],
		["正上 +Y", Vector3(0, 1, 0)],
		["斜下 +Z", Vector3(0.3, -0.5, 0.8).normalized()],
	]
	for dd: Array in dirs:
		var dv: Vector3 = dd[1]
		var from := Vector3(0.0, ALT, 0.0)
		for kind2: Array in [["光束", "beam"], ["火神炮", "vulcan"]]:
			# ⚠️ 这里**不能**写 `var is_beam := kind2[1] == "beam"`：
			# `kind2[1]` 是 Variant，`==` 的结果推不出类型 ⇒ **解析期**报
			# "Cannot infer the type of ... variable"。显式标 `: bool`。
			var is_beam: bool = (kind2[1] as String) == "beam"
			var con := Node3D.new()
			_cont.add_child(con)
			var pj: Node3D = (Projectile.beam(con, from, dv, _pc, 10.0, Color.WHITE, 4000.0, 1.0, 0.0)
				if is_beam else Projectile.vulcan(con, from, dv, _pc, 10.0, Color.WHITE))
			var mi := pj.get_child(0) as MeshInstance3D
			var got := _mesh_long_axis(mi)
			var mesh_axis: Vector3 = got[0]
			var parent_axis := -pj.global_transform.basis.z
			_say("  ── 方向「%s」%s" % [dd[0], _fmt3(dv)])
			_say("     %s  ② −(p.basis.z) 与 dir 夹角 %7.3f°   ③ 网格长轴与 dir 夹角 %7.3f°"
				% [kind2[0], _ang(parent_axis, dv), _ang(mesh_axis, dv)])
			_say("        ③ 长轴取法 [%s]；长轴与世界UP夹角 %7.3f°"
				% [got[1], _ang(mesh_axis, Vector3.UP)])
			con.queue_free()
		await _phys(1)

	_say("")
	_say("--- 3 源码事实 ---")
	var src := FileAccess.get_file_as_string("res://scripts/combat/projectile.gd")
	for key: String in ["p.look_at(from + p.direction, Vector3.UP)",
			"mi.rotation_degrees.x = 90.0",
			"_vulcan_mesh.size = Vector3(0.55, 0.55, 16.0)"]:
		var i := src.find(key)
		_say("  %-46s 行号 = %s" % [key, str(src.substr(0, i).count("\n") + 1) if i > 0 else "**找不到**"])
	_say("")
