extends Node
## **分状态模型验收**（1.2 第二十四轮）。
##
## 用户给的方案是按"脱落的是几号机"换模型，所以这里要把**四个状态**各拍一张，
## 两种板共 8 张 —— 一眼能看出"人少了模型有没有跟着变"。
##
## 机位**按实际板长取景**（`FlightPedal.game_length_of()`），不写死距离。
##
## 跑法（不能加 --headless）：
##   godot --path <工程> res://tools/pedal_states_shots.tscn -- <输出目录>

var out_dir := "user://pedal_states"
var _idx := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 38.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.14, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.50, 0.56, 0.64)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 1.0
	cam.far = 40000.0
	add_child(cam)
	cam.current = true

	for item: Array in [
		[FlightPedal.Kind.MAFTY, SuitProfile.messer_m01(), "mafty"],
		[FlightPedal.Kind.KILCE, SuitProfile.gustav00_armed(), "kilce"],
		# ⚠️ 2026-09-30（N62）：**指挥官型单开第三种板** —— 它骑板时画的是**它自己**，
		# 而不是 `mafty_*` 里烤死的量产型。这一组就是那条改动的验收图：
		# 与上面的 `mafty` 组**同机位、同状态**，唯一差别就是机上画的是谁。
		[FlightPedal.Kind.MESSER_CMD, SuitProfile.messer_cmd(), "cmd"],
	]:
		await _shoot(cam, item[0], item[1], str(item[2]))

	print("PEDAL_STATES_DONE -> ", out_dir)
	get_tree().quit(0)


func _shoot(cam: Camera3D, kind: int, prof: SuitProfile, tag: String) -> void:
	var L := FlightPedal.game_length_of(kind)
	# 四个状态：0 = 空板，1 = 只有一号机，2 = 只有二号机，3 = 两台都在
	var setups := [
		[0, "01_empty"],
		[1, "02_slot0_only"],
		[2, "03_slot1_only"],
		[3, "04_both"],
	]
	for st: Array in setups:
		var n: int = st[0]
		var c := Node3D.new()
		add_child(c)
		var lead := _body(c, prof, 0)
		await get_tree().physics_frame
		lead.global_position = Vector3(0.0, 3000.0, 0.0)
		var board := lead.spawn_with_pedal()
		await get_tree().physics_frame
		if board == null:
			print("⚠️ %s 没建出板" % tag)
			c.queue_free()
			continue
		var tag2 := ""
		if n == 0:
			# 空板：把领机也脱下来，模型应当切成空板
			lead.release_pedal()
			await get_tree().physics_frame
			tag2 = "空板"
		else:
			# ⚠️ 座次是**先挂先得**（0 号位先被占），所以"只有二号机"**必须先挂两台、
			# 再把一号机摘掉** —— 不能"只挂一台然后说它是二号机"。
			# 第一版就是这么偷懒的，结果四个状态里有两个拍出来是同一张
			#（日志里两个都报 `状态=1`），等于那个状态**根本没验**。
			var wing := _body(c, prof, 0)
			await get_tree().physics_frame
			board.add_rider(wing)          # wing 拿到 0 号位
			await get_tree().physics_frame
			if n == 1:
				# 只要一号机：把二号机（wing）摘掉
				board.remove_rider(wing)
				wing.queue_free()
				tag2 = "只有一号机"
			elif n == 2:
				# 只要二号机：把一号机（lead）摘掉
				board.remove_rider(lead)
				tag2 = "只有二号机"
			else:
				# 两台都在：把 wing 摆到一号机对面的那个位子上
				wing.global_position = board.slot_world_position(wing.pedal_slot)
				tag2 = "两台都在"
		await get_tree().physics_frame
		# 关掉物理，别让它飞走
		for u in c.get_children():
			if u is FlightBody:
				u.set_physics_process(false)
		if is_instance_valid(board):
			board.set_physics_process(false)
			board._process(0.0)
		await get_tree().physics_frame

		print("[%s/%s] 状态=%d  板长 %.1f m  座位间距 %.1f m" % [
			tag, tag2, board.vis_state() if is_instance_valid(board) else -1,
			L, FlightPedal.slot_separation_m(kind)])
		# 斜上三分之四机位（能同时看到板长、座次与骑手）
		cam.global_position = board.global_position + Vector3(L * 1.5, L * 0.85, L * 1.5)
		cam.look_at(board.global_position, Vector3.UP)
		for f in 5:
			await get_tree().physics_frame
		await _shot("%s_%s" % [tag, str(st[1])])
		c.queue_free()
		await get_tree().physics_frame


func _body(parent: Node3D, prof: SuitProfile, team: int) -> FlightBody:
	var fb := BanditAI.new()
	fb.team = team
	fb.profile = prof
	fb.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	fb.projectile_container = parent
	parent.add_child(fb)
	return fb


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
