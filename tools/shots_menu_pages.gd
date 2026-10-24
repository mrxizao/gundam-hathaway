extends Node
## 主菜单**两页**真机截图台（轮 25）：设置页 + 重绑页。
##
## 为什么单开一个：`tools/capture.gd` 是 1.1 的全流程剧本（十几张图、两分钟起），
## 而这一轮要核对的只有两件**界面事实**：
##   ① 设置页里「第一人称视角」那一行**已经不在了**（轮 25 撤掉，换 F1 / 长按手柄 Back）；
##   ② 重绑页滚到最后一条，能看到 **第一人称 / 第三人称 ⇄ F1** 这一行（可重绑）。
##
## ⚠️ **不能加 `--headless`** —— 无头用的是 dummy 渲染器，一个像素都不产生，
## 抓出来是全黑。这个脚本的全部意义就是**能真的看到**，所以必须开窗口跑。
##
## 跑法：
##   godot --path <工程> res://tools/shots_menu_pages.tscn -- <输出目录>
##
## 脚本里所有等待都走**物理帧**（物理固定 60 Hz；等渲染帧在 300+ fps 的窗口里
## 只有几分之一秒，会出现"页面还没重画就截图了"）。

const SHOT_W := 1600
const SHOT_H := 900

var main: Node
var out_dir := "user://shots_menu_pages"


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
	if menu == null or not is_instance_valid(menu):
		push_error("SHOTS_FAILED(no menu)")
		get_tree().quit(1)
		return

	# ---- ① 设置页：那一行应该没了 ----
	menu.set("stage", MainMenu.Stage.SETTINGS)
	await _frames(14)
	await _shot("menu_settings")

	# ---- ② 重绑页：滚到最后一条（应当就是 toggle_fpv）----
	var rows: Array = MainMenu.keys_flat()
	var target: int = rows.find("toggle_fpv")
	if target < 0:
		push_error("SHOTS_FAILED(keys_flat 里没有 toggle_fpv)")
	else:
		menu.set("stage", MainMenu.Stage.KEYS)
		await _frames(6)
		var cap: int = int(menu.call("_key_window_rows"))
		menu.set("keys_row", target)
		# 让选中行停在窗口最后一行，翻页指示器也落在末尾
		menu.set("keys_scroll", maxi(target - cap + 1, 0))
		await _frames(14)
		await _shot("menu_keys_last")
		print("KEYS target=%d / %d  cap=%d" % [target, rows.size(), cap])

	print("SHOTS done -> %s" % out_dir)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
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
	var path := out_dir.path_join("%s.png" % name)
	print("SHOT %s  err=%d" % [path, img.save_png(path)])
