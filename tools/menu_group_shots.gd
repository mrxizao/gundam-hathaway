extends Node
## **临时**验收（2026-10-01 更新）：模式页 4 行 + 子页 + 联机页形式行。
##
## 六张图：
##   ① 模式页 **4 行**（对战模式 / 剧情挑战 / 训练模式 / 局域网联机），光标在「对战模式」；
##   ② 同上的模式页，光标移到「剧情挑战」—— 它现在在**第二位**；
##   ③ 同上的模式页，光标移到「训练模式」—— 它现在在**第三位**；
##   ④ 「对战模式」子页：光标在**王牌战**（第 0 项，默认）；
##   ⑤ 同上的子页：光标在**小队战**（第 1 项）；
##   ⑥ 联机页第 5 行「对战形式」高亮着，值是「王牌战 · 一人一台 1v1」。
##
## ⚠️ ①/②/③ 是本次的重点：**行的顺序变了、行高一个常数都没手调** ——
## 全靠 `list_metrics()` 自适应。出图要核对的是「四行都排得下、不压页脚提示行，
## 且四行的名字与顺序和 `MODE_GROUPS` 表逐项一致」。
##
## 跑法（**不能加 `--headless`**：headless 下 RenderingServer 是 dummy，一个像素都不产生）：
##   godot --path <工程> res://tools/menu_group_shots.tscn -- <输出目录>
##
## ⚠️ 这是**临时探针**，不是正式测试：判据在 `suite_menu_groups` / `suite_ace_duel` /
## `suite_round` 里，这里只负责"人眼能核对版式与文案"。

var out_dir := "user://menu_group_shots"
var main: Node = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)

	var menu: Node = main.get("menu")
	if menu == null:
		print("MENU_SHOTS_FAILED 没拿到菜单")
		get_tree().quit(1)
		return
	# ⚠️ 菜单必须在"活动"状态才画（`active` 为假时 `_draw()` 走另一条路）。
	menu.set("active", true)

	# ---- ① 模式页：4 行，光标停在「对战模式」----
	menu.select_mode(Game.MatchMode.VERSUS)
	menu.set("stage", MainMenu.Stage.MODE)
	menu.queue_redraw()
	await _frames(10)
	await _shot("01_mode_4rows")

	# ---- ② 模式页：光标停在「剧情挑战」（**第二位**）----
	# 走 `select_mode()` 而不是直接写 `mode_index` —— 它是"模式 → 分组"的唯一换算，
	# 摆错组的话这张图会指到别处（而那正是要核对的事）。
	menu.select_mode(Game.MatchMode.CHALLENGE)
	menu.queue_redraw()
	await _frames(8)
	await _shot("02_mode_challenge")

	# ---- ③ 模式页：光标停在「训练模式」（**第三位**）----
	menu.select_mode(Game.MatchMode.TRAINING)
	menu.queue_redraw()
	await _frames(8)
	await _shot("03_mode_training")

	# ---- ④ 子页：王牌战高亮 ----
	menu.select_mode(Game.MatchMode.VERSUS)
	menu.set("battle_index", 0)
	menu.set("stage", MainMenu.Stage.BATTLE)
	menu.queue_redraw()
	await _frames(8)
	await _shot("04_battle_versus")

	# ---- ⑤ 子页：小队战高亮 ----
	menu.set("battle_index", 1)
	menu.queue_redraw()
	await _frames(8)
	await _shot("05_battle_squad")

	# ---- ⑥ 联机页：形式那一行高亮着（值 = 王牌战）----
	menu.select_mode(Game.MatchMode.LAN)
	menu.set("stage", MainMenu.Stage.LAN)
	menu.set("lan_row", MainMenu.LAN_FORM_ROW)
	menu.set("lan_form_choice", 1)                             # 1 = 王牌战
	menu.queue_redraw()
	await _frames(8)
	await _shot("06_lan_form_row")

	print("MENU_GROUP_SHOTS_DONE -> ", out_dir)
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
