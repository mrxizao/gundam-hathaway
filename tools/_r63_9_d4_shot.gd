extends Node
## ★63-9 · D4 真机出图：**敌方机体坠毁提醒**（中央 toast + 结算页左栏那一行）。
##
## ## 为什么要出图
## D4 改的全是**玩家看得见的字**：中央那摞 toast 的一句新文案，
## 以及结算页左栏「战斗经过」里那一行（P12 把终结性击毁的提示落在结算页）。
## 无头套件能断"字符串对了"（`hud._notices` 里 text 逐字相等），
## 但"它真的画到屏幕上了"只有像素说了算 —— 本工程栽过"两条都绿却看不见"。
##
## ## 三张图（含一张负对照）
##   ① `01_toast_squad`    小队战（7 台）击坠 1 台 ⇒ **中央有一条带机名的坠毁提醒**；
##   ② `02_result_squad`   接着把场上清空 ⇒ **结算页**；左栏「战斗经过」最后一行
##                         就是带机名的那句（终结性击毁的提示落在结算页，不叠 toast）；
##   ③ `03_versus_no_toast` 1v1 对战（唯一一台）击坠 ⇒ **只有结算页、没有 toast**
##                         —— 这是**负对照**：同一套代码，只差"是不是终结性"。
##
## ⚠️ 不能加 `--headless`：dummy 渲染器一个像素都不产生，抓出来全黑。
##
## 跑法：
##   godot --path <工程> res://tools/_r63_9_d4_shot.tscn -- <输出目录>

var out := "user://r63_9_d4_shot"
var main: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(10)

	await _squad_round()

	await _versus_round()

	print("R63_9_D4_SHOT_DONE -> %s" % out)
	get_tree().quit(0)


## 小队战：7 台敌机。击坠 1 台（非终结性）⇒ 出图；再清空（终结性）⇒ 结算页出图。
func _squad_round() -> void:
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	await _frames(10)
	main.call("_start_fight")
	await _frames(6)
	var p = main.get("player")
	var foes: Array = Game.live_hostiles_of(p).duplicate()
	print("[squad] 敌机 %d 台 · Game.phase=%d" % [foes.size(), Game.phase])
	if foes.is_empty():
		print("SHOT_FAILED(小队战没有敌机)")
		return
	var victim = foes[0]
	# ⚠️ killer 必须是玩家：`flight_body.destroy()` 只在 `killer == Game.player` 时
	# 才往战斗日志里写那一行 —— 那不是本探针能绕过的（它就是要验生产路径）。
	victim.destroy(p)
	# 等爆炸亮光淡下去一点，但别等到 toast 的 2.2 s 走完
	await _frames(24)
	print("[squad] 拍 01 之前 hud._notices=%s" % str(_texts()))
	await _shot("01_toast_squad")

	# ---- 清空全场：最后那一台的提示落在结算页 ----
	var rest: Array = Game.live_hostiles_of(p).duplicate()
	for u in rest:
		if is_instance_valid(u):
			u.destroy(p)
		await _frames(2)
	for i in 40:
		await _frames(1)
		if Game.phase == Game.Phase.WIN:
			break
	print("[squad] 清场后 Game.phase=%d" % Game.phase)
	await _frames(20)
	await _shot("02_result_squad")


## 1v1 对战：场上只有一台 ⇒ 击坠必然终结 ⇒ **负对照**（不该有 toast）。
func _versus_round() -> void:
	# ⚠️ 先把上一局残留的 toast 清干净。不清的话，"负对照看不到提醒"可能只是
	# **刚好衰减掉了**而不是"被那道门挡住了" —— 那是两件完全不同的事。
	main.get("hud").set("_notices", [])
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, SuitProfile.Id.PENELOPE)
	await _frames(10)
	main.call("_start_fight")
	await _frames(6)
	var p = main.get("player")
	var foe = main.get("enemy")
	if foe == null or not is_instance_valid(foe):
		print("SHOT_FAILED(对战没有敌机)")
		return
	foe.destroy(p)
	for i in 40:
		await _frames(1)
		if Game.phase == Game.Phase.WIN:
			break
	print("[versus] 击坠后 Game.phase=%d" % Game.phase)
	await _frames(20)
	print("[versus] 拍 03 之前 hud._notices=%s" % str(_texts()))
	await _shot("03_versus_no_toast")


func _texts() -> Array:
	var out: Array = []
	for n in main.get("hud").get("_notices"):
		out.append(str(n.get("text", "")))
	return out


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
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  %dx%d  err=%d"
		% [path, img.get_width(), img.get_height(), img.save_png(path)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
