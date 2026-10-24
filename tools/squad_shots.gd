extends Node
## **临时**验收（第二十轮）：编队战的**阵营页 / 按阵营过滤的机体页 / 14 台同场**。
##
## 三张图对应三个新东西：
##   ① `Stage.SIDE` 阵营页（新页，只有编队战会走）；
##   ② 机体页**按阵营过滤**（马夫蒂 3 台 / 联邦 2 台 —— 张数会变，版式要重算）；
##   ③ 真局：14 台单位同场（两边各 7）＋ 6 块踏板。
##
## 跑法（不能加 --headless）：
##   godot --path <工程> res://tools/squad_shots.tscn -- <输出目录>

var out_dir := "user://squad_shots"
var main: Node = null
var _idx := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)

	var menu = main.get("menu")
	# ---- ① 阵营页 ----
	# ⚠️ 本轮起"摆到小队战"要走 `select_mode()`：它把两层（分组 + 组内形式）一次摆好，
	# 而且找不到就返回 false（不再有 `MODES.find()` 返回 −1 ⇒ 负下标取到"联机"的坑）。
	menu.select_mode(Game.MatchMode.SQUAD)
	menu.set("stage", MainMenu.Stage.SIDE)
	menu.set("side_index", 0)
	menu.queue_redraw()
	await _frames(8)
	await _shot("01_side_mafty")
	menu.set("side_index", 1)
	menu.queue_redraw()
	await _frames(6)
	await _shot("02_side_federation")

	# ---- ② 机体页（按阵营过滤）----
	menu.set("side_index", 0)
	menu.set("stage", MainMenu.Stage.SUIT)
	menu.set("suit_index", 0)
	menu.queue_redraw()
	await _frames(8)
	await _shot("03_suits_mafty")
	menu.set("side_index", 1)
	menu.set("suit_index", 0)
	menu.queue_redraw()
	await _frames(8)
	await _shot("04_suits_federation")

	# ---- ③ 真局：14 台 ----
	Game.active_side = BattleFormation.Side.MAFTY
	main.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	await _frames(40)
	# 把镜头拉远一点：14 台挤在一个屏幕里才看得出编制
	var cam = main.get("chase")
	if cam != null:
		cam.set("offset", Vector3(0.0, 26.0, 190.0))
	await _frames(30)
	var p = main.get("player")
	if p != null and is_instance_valid(p):
		print("玩家=%s  有板=%s" % [
			p.profile.display_name if p.profile != null else "?",
			str(p.has_pedal())])
	var n_units := 0
	var n_boards := 0
	for u in Game.units:
		if is_instance_valid(u) and not u.is_queued_for_deletion():
			n_units += 1
			if u.has_method("pedal_owner") and u.pedal_owner() != null:
				n_boards += 1
	print("场上单位=%d  骑板=%d" % [n_units, n_boards])
	await _shot("05_squad_live")
	await _frames(40)
	await _shot("06_squad_live_2")

	print("SQUAD_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


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
