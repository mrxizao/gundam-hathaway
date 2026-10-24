extends Node
## **临时**验收（1.2）：**五张机体卡**在三种窗口比例下排不排得开。
##
## 背景：古斯塔夫00 做成可选之后机体卡从 4 张变成 5 张。
## 卡片宽度是 `(屏宽 − 2×24 − 4×52) / 5`：
##   1600 → 约 428 px、1280 → 约 363 px、2560 → 约 620 px。
## 1280 是**最窄的那一档**，所以三档都要看，重点看 1280。
##
## 跑法（不能加 --headless）：
##   godot --path <工程> res://tools/cards_check.tscn -- <输出目录>

const SIZES := [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(2560, 1440)]
var out_dir := "user://cards_check"
var main: Node = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(SIZES[0])
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)

	var menu = main.get("menu")
	menu.set("stage", MainMenu.Stage.SUIT)
	# 停在最后一张卡（古斯塔夫）上 —— 既看得到全部五张，也验证"最右那张没被切掉"
	menu.set("suit_index", MainMenu.SUITS.size() - 1)
	menu.queue_redraw()

	for i in SIZES.size():
		DisplayServer.window_set_size(SIZES[i])
		await _frames(14)
		menu.queue_redraw()
		await _frames(6)
		await _shot("cards_%dx%d" % [SIZES[i].x, SIZES[i].y])

	print("CARDS_CHECK_DONE -> ", out_dir)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


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
	var p := out_dir.path_join("%s.png" % shot_name)
	print("SHOT %s err=%d" % [p, img.save_png(p)])
