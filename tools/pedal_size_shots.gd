extends Node
## **临时**验收（第二十二轮）：**踏板放大之后**长什么样、两位骑手有没有站对。
##
## 机位**按实际尺寸取景**（`FlightPedal.game_length_of()`），不写死距离 ——
## 上一版工具把机位写死在旧尺寸上，板一放大就拍到空处。
##
## 跑法（不能加 --headless）：
##   godot --path <工程> res://tools/pedal_size_shots.tscn -- <输出目录>

var out_dir := "user://pedal_size"
var _idx := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 40.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.12, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.50, 0.58)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 1.0
	cam.far = 20000.0
	add_child(cam)
	cam.current = true

	for item: Array in [
		[FlightPedal.Kind.MAFTY, SuitProfile.messer_m01(), "mafty"],
		[FlightPedal.Kind.KILCE, SuitProfile.gustav00_armed(), "kilce"],
	]:
		await _shoot_kind(cam, item[0], item[1], str(item[2]))

	print("PEDAL_SIZE_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0)


func _shoot_kind(cam: Camera3D, kind: int, prof: SuitProfile, tag: String) -> void:
	var c := Node3D.new()
	add_child(c)
	var lead := _body(c, prof, Vector3.ZERO, 0)
	var wing := _body(c, prof, Vector3.ZERO, 1)
	await get_tree().physics_frame
	# 领队挂板（板挂在领机身上），后座骑同一块
	lead.configure_pedal(kind)
	await get_tree().physics_frame
	var board := lead.pedal_owner()
	print("[%s] 板长 %.1f m  厚 %.1f m  座位间距 %.1f m" % [
		tag, FlightPedal.game_length_of(kind),
		FlightPedal.target_height_of(kind), FlightPedal.slot_separation_m(kind)])
	if board != null:
		board.add_rider(wing)
	# 把两台摆到板上的挂位处，好让机位能框住整体
	# ⚠️ `slot_world_position()` 在**踏板**上，不在骑手上。
	lead.global_position = Vector3(0.0, 3000.0, 0.0)
	wing.global_position = board.slot_world_position(1) if board != null else Vector3(0.0, 3000.0, 0.0)
	await get_tree().physics_frame
	# 关掉物理，别让它们飞走
	lead.set_physics_process(false)
	wing.set_physics_process(false)
	if board != null:
		board.set_physics_process(false)
	await get_tree().physics_frame

	var L := FlightPedal.game_length_of(kind)
	# ① 正前（看两位骑手是不是**并排**）
	await _look(cam, Vector3(0.0, 3000.0 + L * 0.30, L * 2.2), Vector3(0.0, 3000.0, 0.0),
		"%s_01_front" % tag)
	# ② 侧上（看板长与骑手比例 —— 这张最直接对比"板够不够大"）
	await _look(cam, Vector3(L * 2.0, 3000.0 + L * 1.1, L * 1.6), Vector3(0.0, 3000.0, 0.0),
		"%s_02_three_quarter" % tag)
	# ③ 正侧（看厚度与骑手身高）
	await _look(cam, Vector3(L * 2.4, 3000.0 + L * 0.25, 0.0), Vector3(0.0, 3000.0, 0.0),
		"%s_03_side" % tag)
	c.queue_free()
	await get_tree().physics_frame


func _body(parent: Node3D, prof: SuitProfile, pos: Vector3, team: int) -> FlightBody:
	var fb := BanditAI.new()
	fb.team = team
	fb.profile = prof
	fb.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	fb.projectile_container = parent
	parent.add_child(fb)
	fb.global_position = pos
	return fb


func _look(cam: Camera3D, from: Vector3, at: Vector3, shot_name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	for i in 4:
		await get_tree().physics_frame
	await _shot(shot_name)


func _shot(shot_name: String) -> void:
	_idx += 1
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		print("SHOT_FAILED ", shot_name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(img) ", shot_name)
		return
	var p := out_dir.path_join("%02d_%s.png" % [_idx, shot_name])
	print("SHOT %s err=%d" % [p, img.save_png(p)])
