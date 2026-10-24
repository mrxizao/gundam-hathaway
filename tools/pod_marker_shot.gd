extends Node
## 出图探针：**运输仓的 HUD 目标指示**
##（2026-09-29 用户：「从出生环 46.6 km 外看，运输仓只剩 ~1 px：
## 做一个锁定显示功能（类似正常的索敌系统，但是不能被攻击）」）。
##
## 判据在 `suite_space_map.gd`（结构性三条）；本探针只负责把"46.6 km 外到底看不看得见"
## 这件事**画出来** —— 那是用户提这个需求的原话场景。
##
## 三个机位：
##   ① `pod_marker_from_spawn` —— 出生环正对场地中心（46.6 km）。**主图**。
##   ② `pod_marker_turned_away` —— 出生环但机头背对 ⇒ 屏幕边缘的方位箭头。
##   ③ `pod_marker_near` —— 离仓 3 km ⇒ 框随距离收放 + 实物同时可见（确认二者对齐）。
##
## 用法：godot --path <工程> res://tools/pod_marker_shot.tscn -- <输出目录>
## ⚠️ **不能加 `--headless`**：dummy 渲染器抓出来是空图（本工程记过这条）。

const SHOT_W := 1600
const SHOT_H := 900

var main: Node
var out_dir := "user://pod_marker"


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

	var menu = main.get("menu")
	if menu != null:
		menu.call("close_menu")
	# ⚠️ 开局用 **LEO 图**：本探针要拍的运输仓只建在这张图上
	#（`MapDef.leo()` → `WorldBuilder._build_space()` 第 ③ 步）。
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.LEO, Game.MatchMode.VERSUS)
	await _frames(40)
	main.call("_start_fight")
	await _frames(20)

	var p := _player()
	if p == null:
		print("PODMARK_FAILED(no player)")
		get_tree().quit(1)
		return
	# 打不死（这一拍不测伤害）
	p.max_hp = 99999.0
	p.hp = 99999.0
	p.ifield_max = 9999.0
	p.ifield_hp = 9999.0
	p.set("debug_input_enabled", true)
	p.set("debug_input", Vector3.ZERO)
	p.set("debug_throttle", 0.0)
	p.set("debug_boost", false)
	p.set("debug_hover", true)

	var pod := _pod_world_pos()
	var tag := _pod_tag()
	print("[pod] 信标节点 = %s   世界坐标 (%.1f, %.1f, %.1f)"
		% [("null" if tag == null else tag.name), pod.x, pod.y, pod.z])
	print("[pod] 出生环半径 SPAWN_RADIUS = %.0f m（主图机位与场地的距离）"
		% WorldBuilder.SPAWN_RADIUS)
	if tag == null:
		print("PODMARK_FAILED(no pod tag)")

	# ⚠️ 主场景**每帧都在推玩家**（物理 + 它自己的 `_physics_process`）⇒ 先停掉它，
	# 否则下面"钉住原点"的那 60 帧会被它推走，HUD 读数的距离就不是我要拍的那个。
	main.set_physics_process(false)
	main.set_process(false)
	p.set_physics_process(false)
	p.set_process(false)

	# ⚠️⚠️ **相机必须接管**（第一版没接管，翻了个大车）：
	# `main.chase` 是自己的 `_physics_process` 在平滑跟随的，而它跟的不是
	# 我刚 `look_at` 写进去的朝向 —— 实测"相机前向 vs 玩家→仓"的夹角在三个机位下
	# 分别是 **90.5° / 4.0° / 171.9°**，也就是**整整滞后一个机位**（②拿到①该有的、
	# ③拿到②该有的）。⇒ 直接停掉它，相机由本探针自己摆（位置 + 朝向都显式给）。
	var cam := _take_camera()
	if cam == null:
		print("PODMARK_FAILED(no camera)")
		get_tree().quit(1)
		return

	var spawn_pt := Vector3(WorldBuilder.SPAWN_RADIUS, WorldBuilder.SPACE_ORBIT_ALT, 0.0)
	# ① 出生环正对场地中心 —— 用户原话那个场景
	await _park(p, cam, spawn_pt, pod)
	await _shot("pod_marker_from_spawn")
	# ② 同一位置、机头转 180°（背对）⇒ 应当出现屏幕边缘的方位箭头
	await _park(p, cam, spawn_pt, spawn_pt + (spawn_pt - pod))
	await _shot("pod_marker_turned_away")
	# ③ 离仓 3 km、略高 ⇒ 框 + 实物同框
	await _park(p, cam, pod + Vector3(3000.0, 900.0, 0.0), pod)
	await _shot("pod_marker_near")

	print("PODMARK_DONE -> ", out_dir)
	get_tree().quit(0)


## 接管追踪相机：停掉它自己的跟随，之后由 `_park()` 显式摆位。
func _take_camera() -> ChaseCamera:
	var c: ChaseCamera = main.get("chase")
	if c == null:
		return null
	c.set_physics_process(false)
	c.set_process(false)
	c.current = true
	return c


## 把玩家钉在 `at`、机头指向 `look`，逐帧回钉（物理想推走它，这里按回来）；
## **相机也一起摆**（在玩家后方 42 m、上方 13 m，正对 `look`）——
## 那正是"机头对准目标"时第三人称视角该有的构图。
##
## ⚠️ 相机**必须每帧一起设**：`_shot()` 前还等 6 个渲染帧，期间若相机自己动过
## （或被别的东西覆盖），抓到的就不是我要的那一帧。
func _park(p: FlightBody, cam: ChaseCamera, at: Vector3, look: Vector3) -> void:
	var dir := at.direction_to(look)
	for i in 30:
		await get_tree().physics_frame
		p.global_position = at
		p.fm.velocity = Vector3.ZERO
		p.fm.speed = 0.0
		p.look_at(look, Vector3.UP)
		_aim(cam, at, dir, look)
	for i in 6:
		await get_tree().process_frame
		_aim(cam, at, dir, look)
	var want := at.direction_to(_pod_world_pos())
	# ⚠️ Godot 相机的**前向是 `−basis.z`**（`basis.z` 是后向 —— 第一版这里写错了符号，
	# 于是读数在"相机明明对准了"时给 180°，白排查了一轮）。
	var ang := rad_to_deg((-cam.global_transform.basis.z).normalized().angle_to(want))
	print("  park 玩家=(%.0f, %.0f, %.0f)  距仓 %.1f m  机头指向 %s  相机前向 vs 玩家→仓 夹角 %.1f°"
		% [at.x, at.y, at.z, at.distance_to(_pod_world_pos()),
		   "场地中心" if (look - _pod_world_pos()).length() < 1.0 else "背离", ang])


## 相机：**侧后方**（不是正后方）。
##
## ⚠️ 正后方会让**自己的机体挡住目标框** —— 第一版就是这么拍的：机头对准仓时，
## 柯西正好压在画面中央、把那个绿色目标框盖掉了一半。侧偏 46 m 之后
## 仓仍在画面中央、机体退到左下方，两个读数互不遮挡。
func _aim(cam: ChaseCamera, at: Vector3, dir: Vector3, look: Vector3) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	cam.global_position = at - dir * 24.0 + side * 46.0 + Vector3.UP * 12.0
	cam.look_at(look, Vector3.UP)


func _player() -> FlightBody:
	for n in get_tree().get_nodes_in_group("player"):
		var fb := n as FlightBody
		if fb != null and fb.is_alive():
			return fb
	return null


func _pod_tag() -> Node3D:
	for n in get_tree().get_nodes_in_group(WorldBuilder.POD_TAG_GROUP):
		if is_instance_valid(n):
			return n as Node3D
	return null


func _pod_world_pos() -> Vector3:
	var t := _pod_tag()
	return t.global_position if t != null else WorldBuilder.SPACE_POD_POS


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		print("SHOT_FAILED ", shot_name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(img) ", shot_name)
		return
	print("SHOT %s err=%d" % [out_dir.path_join("%s.png" % shot_name),
		img.save_png(out_dir.path_join("%s.png" % shot_name))])
