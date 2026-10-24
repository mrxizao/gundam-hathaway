extends Node
## **临时**验收（2026-09-29）：梅萨指挥官型 / F01型进小队战马夫蒂之后，**机体页排得下吗**。
##
## 四张图（都在 1600×900）+ 一段**多分辨率读数**：
##   ① 马夫蒂机体页，光标在**第 1 张**（柯西）—— 窗口应是 [0,3)，右端有 ▶
##   ② 同上，光标移到**第 4 张**（F01型）—— 窗口应滚到 [1,3)，左端出现 ◀、计数 4/4
##   ③ **对照**：联邦机体页（3 台）—— 必须**逐像素等同于加窗口之前**（无指示器）
##   ④ **对照**：1v1 机体页（3 台 ACE，`SUITS` 固定表）—— 同上，且**没有**新机
##
## ⚠️ ③④ 是**反向判据**：改版式最容易顺手把 3 台的页面也改出个滚动条/窄卡，
##    那属于"没要求的变化"。这两张图就是用来抓这个的。
##
## ## ⚠️ 为什么这里**只出 1600 一档**（第一版出过六张，其中两张是错的）
## 第一版给 1920 / 1280 各拍了一张，靠 `DisplayServer.window_set_size()` 切分辨率。
## 实测**改不动**：截图尺寸确实变成 1920×1080，但**菜单这个 Control 的 `size`
## 仍是 1600×900** —— 那两张图画的是 1600 的版式，而报告里写着 `1920x1080`。
## ⇒ 多分辨率的版式判据**搬进测试**了（`suite_layout._menu()` 逐 view 量卡片几何、
##    窗口容量、滚动指示器装不装得下）。本探针改成把同样的数**打印出来**
##   （见 `_print_windows()`），图只留人眼真能核对的那一档。
##
## 跑法（**不能加 `--headless`**：headless 下 RenderingServer 是 dummy，一个像素都不产生）：
##   godot --path <工程> res://tools/_messer_menu_shots.tscn -- <输出目录>
##
## ⚠️ 这是**临时探针**，不是正式测试：判据在 `suite_messer_roster` / `suite_layout` 里，
## 这里只负责"人眼能核对版式与卡片配色"。

var out_dir := "user://messer_menu_shots"
var main: Node = null
var menu: Node = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	# ⚠️ **必须同时设窗口模式与尺寸**：只设尺寸时，若玩家设置里是全屏，
	# 窗口仍然是全屏（实测拿到 2560×1600 而不是 1600×900）。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)

	menu = main.get("menu")
	if menu == null:
		print("MESSER_SHOTS_FAILED 没拿到菜单")
		get_tree().quit(1)
		return
	# ⚠️ 菜单必须在"活动"状态才画（`active` 为假时 `_draw()` 走另一条路）。
	menu.set("active", true)

	# ---- 小队战 · 马夫蒂 · 第 1 张 ----
	await _squad_mafty(0)
	await _shot("01_mafty_1600_head")

	# ---- 小队战 · 马夫蒂 · 第 4 张（触发滚动）----
	await _squad_mafty(3)
	await _shot("02_mafty_1600_tail")

	# ---- 对照：联邦（3 台）----
	menu.set("side_index", 1)
	menu.set("suit_index", 0)
	menu.queue_redraw()
	await _frames(10)
	await _shot("03_federation_3")

	# ---- 对照：1v1（三台 ACE 固定表）----
	menu.select_mode(Game.MatchMode.VERSUS)
	menu.set("stage", MainMenu.Stage.SUIT)
	menu.set("suit_index", 0)
	menu.queue_redraw()
	await _frames(10)
	await _shot("04_versus_3ace")

	# ---- 其余分辨率**不出图，出读数**（理由见下面 `_print_windows()`）----
	_print_windows()

	print("MESSER_MENU_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0)


## 四个分辨率下的**窗口读数**。
##
## ## ⚠️ 为什么这几档不出图（第一版出过，是错的）
## 第一版给 1920 / 1280 各拍了一张，靠 `DisplayServer.window_set_size()` 切分辨率。
## 实测**改不动**：截图尺寸确实变成 1920×1080（`img.get_width()` 报了），
## 但**菜单这个 Control 的 `size` 仍是 1600×900** —— 于是那两张图画出来是
## 1600 的版式，而报告里写着 "1920x1080"，**判据看上去跑过了、其实量的是旧尺寸**。
##（探针里那条 `[resize] ⚠️ 菜单尺寸未跟到 …` 就是为了把这件事喊出来。）
##
## ⇒ 多分辨率的版式判据**搬进测试**了（`suite_layout._menu()` 逐 view 量卡片几何、
## 窗口容量、以及滚动指示器装不装得下）。这里只把同样的数**打印出来备用对照**。
func _print_windows() -> void:
	var views: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 900),
		Vector2(1600, 1000), Vector2(1920, 1080)]
	print("  ---- 4 台名单在各分辨率下的窗口（马夫蒂侧）----")
	for view: Vector2 in views:
		var cap := MainMenu.max_cards(view)
		var parts: Array[String] = []
		for i in 4:
			var w := MainMenu.suit_window(4, i, view)
			parts.append("[%d,%d)" % [w.x, w.x + w.y])
		var sc_y := MainMenu.cards_top(view) + MainMenu.card_h(view) + 16.0
		print("  view=%s  cap=%d  逐台下标的窗口 %s  指示器y=%.1f 内容区底=%.1f %s"
			% [str(view), cap, " ".join(parts), sc_y, MainMenu.content_bottom(view),
				"（不滚动）" if 4 <= cap else "（要滚动，指示器装得下）"
					if sc_y < MainMenu.content_bottom(view) - 6.0 else "（要滚动，但装不下 ⇒ 不画）"])


## 切到「小队战 · 马夫蒂 · 机体页」，光标停在第 `idx` 张。
func _squad_mafty(idx: int) -> void:
	menu.select_mode(Game.MatchMode.SQUAD)
	menu.set("side_index", 0)          # 0 = 马夫蒂
	menu.set("suit_index", idx)
	menu.set("stage", MainMenu.Stage.SUIT)
	menu.queue_redraw()
	await _frames(12)
	# ---- 把"画出来的那个窗口"与"指示器那串字"一起打出来 ----
	# ⚠️ 光看图判断不了箭头方向（一张 13 px 的字，`◀` 与 `▶` 在截图里都像小三角）。
	# 打印的是**绘制路径真正会用的那几个数**（`active_suit_list()` / `suit_window()`），
	# 所以它与 `_draw_suit_scroll()` 里的那串字是同一个来源。
	var lst: Array = menu.call("active_suit_list")
	var sel: int = menu.get("suit_index")
	var win: Vector2i = MainMenu.suit_window(lst.size(), sel, menu.size)
	print("  [win] view=%s count=%d sel=%d -> first=%d n=%d | label='%s'"
		% [str(menu.size), lst.size(), sel, win.x, win.y,
			"%s %d/%d %s" % ["◀" if win.x > 0 else "_", sel + 1, lst.size(),
				"▶" if win.x + win.y < lst.size() else "_"]])
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
	print("SHOT %s  %dx%d" % [shot_name, img.get_width(), img.get_height()])
	var p := out_dir.path_join("%s.png" % shot_name)
	print("   err=%d" % img.save_png(p))
