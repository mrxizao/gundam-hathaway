extends Node
## 出图探针：**「内阁成员所在酒店」的 HUD 只读锁定指示**。
##
## 老板原话（2026-09-30）：
##   「顺便你把要对着迪拜塔（游戏内名字"内阁成员所在酒店"）也设置一个类似柯西运输仓的锁定」
##
## 这就是 `pod_marker_shot.gd`（运输仓那一版）的**姊妹台**：
## 两条信标在 `hud.gd` 里走的是**同一段画法**（`BEACONS` 表驱动），
## 所以这一台的意义不只是"证明酒店画出来了"，更是"证明那张表真的被两边共用"——
## 两台拍的构图**逐条对齐**（远景 / 背对 / 近景），一左一右比着看。
##
## 三个机位：
##   ① `hotel_marker_from_air` —— 10 km 外、塔尖高度平飞、机头正对。**主图**。
##   ② `hotel_marker_turned_away` —— 同一位置、机头转 180° ⇒ 屏幕边缘的方位箭头。
##   ③ `hotel_marker_near` —— 2.5 km 外 ⇒ 框随距离收放 + 针塔本体同框（确认二者对齐）。
##
## 用法：godot --path <工程> res://tools/hotel_marker_shot.tscn -- <输出目录>
## ⚠️ **不能加 `--headless`**：dummy 渲染器抓出来是空图（本工程记过这条）。

const SHOT_W := 1600
const SHOT_H := 900

## 主图机位距塔的**水平**距离。取 10 km：全城针塔 9 065 m 高，
## 这个距离上它仍是一个"立得起来"的剪影，而不是一根线。
const FAR_DIST := 10000.0
## 近景机位。2.5 km 时框已经收到下限附近，**塔身要与框同框**才对得上。
const NEAR_DIST := 2500.0

var main: Node
var out_dir := "user://hotel_marker"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	if main.get_script() == null or not main.has_method("_on_start_match"):
		push_error("HOTELMARK_FAILED(main.gd 没装上 —— 解析不过 ⇒ 本台不是「降级」问题，"
			+ "而是**一次真正的主场景调用**都做不了；等 `main.gd` 能解析再跑)")
		get_tree().quit(1)
		return
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	var menu = main.get("menu")
	if menu != null:
		menu.call("close_menu")
	# ⚠️ 用 **DAVAO** 图：针塔（`WorldBuilder._city_needle_tower()`）只建在这张图上。
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.DAVAO, Game.MatchMode.VERSUS)
	await _frames(40)
	main.call("_start_fight")
	await _frames(20)

	var p := _player()
	if p == null:
		print("HOTELMARK_FAILED(no player)")
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

	var tag := _beacon_tag()
	if tag == null:
		print("HOTELMARK_FAILED(no hotel tag —— 组 %s 是空的)" % WorldBuilder.HOTEL_TAG_GROUP)
		get_tree().quit(1)
		return
	var at := tag.global_position
	print("[hotel] 信标节点 = %s · 组 = %s · 世界坐标 (%.1f, %.1f, %.1f)"
		% [tag.name, WorldBuilder.HOTEL_TAG_GROUP, at.x, at.y, at.z])
	print("[hotel] 塔尖标高 %.0f m（全图最高；`HOTEL_TAG_GROUP` 的注释说它钉在针尖顶）"
		% at.y)
	var hotel: Array = get_tree().get_nodes_in_group(WorldBuilder.HOTEL_GROUP)
	print("[hotel] 打中判定那一组（`%s`）现有 %d 件 —— 与信标**分组**（这是有意的，见注释）"
		% [WorldBuilder.HOTEL_GROUP, hotel.size()])

	# ⚠️ 主场景**每帧都在推玩家**⇒ 先停掉它，否则下面"钉住原点"的那 30 帧会被它推走。
	main.set_physics_process(false)
	main.set_process(false)
	p.set_physics_process(false)
	p.set_process(false)

	# ⚠️⚠️ **相机必须接管**：`main.chase` 自己的 `_physics_process` 平滑跟随的
	# 不是我刚写进去的朝向（`pod_marker_shot.gd` 实测滞后整整一个机位）。
	var cam := _take_camera()
	if cam == null:
		print("HOTELMARK_FAILED(no camera)")
		get_tree().quit(1)
		return

	# ① 塔的**正东**方向平飞（避开海湾那侧的地形起伏），塔尖高度略上。
	var far_pt := at + Vector3(FAR_DIST, 300.0, 0.0)
	await _park(p, cam, far_pt, at)
	await _shot("hotel_marker_from_air")
	# ② 同一位置、机头转 180°（背对）⇒ 应当出现屏幕边缘的方位箭头
	await _park(p, cam, far_pt, far_pt + (far_pt - at))
	await _shot("hotel_marker_turned_away")
	# ③ 2.5 km、略上 ⇒ 框 + 针塔同框
	var near_pt := at + Vector3(NEAR_DIST, 200.0, 0.0)
	await _park(p, cam, near_pt, at)
	await _shot("hotel_marker_near")

	print("HOTELMARK_DONE -> ", out_dir)
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


## 把玩家钉在 `at`、机头指向 `look`，逐帧回钉；**相机也一起摆**。
##
## ⚠️ 相机**必须每帧一起设**：`_shot()` 前还等 6 个渲染帧，期间若相机自己动过，抓到的
## 就不是我要的那一帧。
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
	# ⚠️ Godot 相机的**前向是 `−basis.z`**（`basis.z` 是后向；
	# `pod_marker_shot.gd` 第一版这里写错了符号，于是"相机明明对准了"读数给 180°）。
	var want := at.direction_to(_beacon_world_pos())
	var ang := rad_to_deg((-cam.global_transform.basis.z).normalized().angle_to(want))
	print("  park 玩家=(%.0f, %.0f, %.0f)  距塔 %.1f m  机头指向 %s  相机前向 vs 玩家→塔 夹角 %.1f°"
		% [at.x, at.y, at.z, at.distance_to(_beacon_world_pos()),
		   "塔" if (look - _beacon_world_pos()).length() < 1.0 else "背离", ang])


## 相机：**侧后方**（不是正后方）。
##
## ⚠️ 正后方会让**自己的机体挡住目标框** —— `pod_marker_shot.gd` 就是这么翻的车：
## 机头对准目标时柯西正好压在画面中央、把那个框盖掉一半。
## 侧偏之后目标仍在画面中央、机体退到左下方，两个读数互不遮挡。
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


func _beacon_tag() -> Node3D:
	for n in get_tree().get_nodes_in_group(WorldBuilder.HOTEL_TAG_GROUP):
		if is_instance_valid(n):
			return n as Node3D
	return null


func _beacon_world_pos() -> Vector3:
	var t := _beacon_tag()
	return t.global_position if t != null else Vector3.ZERO


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
	print("SHOT %s  %dx%d  err=%d"
		% [out_dir.path_join("%s.png" % shot_name), img.get_width(), img.get_height(),
			img.save_png(out_dir.path_join("%s.png" % shot_name))])
