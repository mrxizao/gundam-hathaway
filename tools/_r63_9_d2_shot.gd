extends Node
## ★63-9 · D2 真机出图：辅助驾驶下 CTRL 倒着飞 —— 左上角那一格「倒着飞」。
##
## ## 为什么要出图
## D2 唯一的**玩家可见字面量**就是左上角辅助驾驶那一行右侧的「倒着飞」。
## 无头套件能断 `assist_state()["reverse"]` 与 `_draw_assist_block()` 的
## **位置关系**（三个 x 偏移的大小），但"它真的画在屏幕上、而且紧挨着
## 「辅助驾驶 开启」同一行"只有像素说了算 —— 本工程栽过"两条都绿却看不见"。
##
## ## 三张图（同一台机器、同一个镜头；只差按/不按 CTRL 与辅助开没开）
##   ① `01_reverse_on`   辅助开 + 倒飞中 ⇒ 那一行出现「倒着飞」
##   ② `02_reverse_off`  再按一次 CTRL ⇒ 那一格消失（**负对照**：不是常驻画着的）
##   ③ `03_no_assist`    关掉辅助后再按 CTRL ⇒ 那一格**不可能**出现
##                        （辅助关时 CTRL 回到"悬停"语义，`translate_mode` 为假）
##
## 三张图都会打印 `fm.velocity · forward()` 与 `assist_state()` 的读数 ——
## 图说"字画出来了"，数说"机体真的是倒着飞"。
##
## ⚠️ 不能加 `--headless`：dummy 渲染器一个像素都不产生，抓出来全黑。
##
## 跑法：godot --path <工程> res://tools/_r63_9_d2_shot.tscn -- <输出目录>

var out := "user://r63_9_d2_shot"
var main: Node
var pc: PlayerController


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

	await _round()

	print("R63_9_D2_SHOT_DONE -> %s" % out)
	get_tree().quit(0)


func _round() -> void:
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, SuitProfile.Id.PENELOPE)
	await _frames(10)
	main.call("_start_fight")
	await _frames(20)
	pc = main.get("player") as PlayerController
	if pc == null:
		print("SHOT_FAILED(没有玩家机)")
		return

	# ---- 开辅助：走**真的长按路径**（`flight_assist` 按住 0.45 s），不直接写字段 ----
	print("[d2] 开局 assist_on=%s translate_mode=%s" % [str(pc.assist_on), str(pc.translate_mode)])
	Input.action_press("flight_assist")
	await _frames(40)
	Input.action_release("flight_assist")
	await _frames(20)
	print("[d2] 长按之后 assist_on=%s translate_mode=%s face_target=%s"
		% [str(pc.assist_on), str(pc.translate_mode), str(pc.face_target)])
	if not pc.translate_mode:
		print("SHOT_FAILED(没进平移模式 —— 后面全是恒真)")
		return

	# ---- ① 按一次 CTRL ⇒ 倒飞 ----
	_press_hover()
	await _frames(70)
	await _report("01 倒飞")
	await _shot("01_reverse_on")

	# ---- ② 再按一次 ⇒ 复原（负对照：那一格必须消失）----
	_press_hover()
	await _frames(70)
	await _report("02 复原")
	await _shot("02_reverse_off")

	# ---- ③ 关掉辅助，再按 CTRL ⇒ 那一格不许出现 ----
	Input.action_press("flight_assist")
	await _frames(40)
	Input.action_release("flight_assist")
	await _frames(20)
	print("[d2] 关辅助之后 assist_on=%s translate_mode=%s" % [str(pc.assist_on), str(pc.translate_mode)])
	_press_hover()
	await _frames(30)
	await _report("03 辅助关 + 按 CTRL")
	await _shot("03_no_assist")


## 点按 CTRL（动作名 `hover`）。⚠️ 按下之后要**留够两帧**：`physics_frame` 信号
## 发在 `_physics_process` 之前，只等一帧的话 `_think()` 还没读到这一下按键。
func _press_hover() -> void:
	Input.action_press("hover")
	await _frames(2)
	Input.action_release("hover")
	await _frames(2)


func _report(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var v := pc.fm.velocity
	var f := pc.forward()
	var st: Dictionary = pc.assist_state()
	print("[d2] %s ｜ assist=%s translate=%s reverse=%s ｜ v·f = %+.1f ｜ |v| = %.1f ｜ event=%s"
		% [tag, str(st.get("on", false)), str(pc.translate_mode),
			str(st.get("reverse", false)), v.dot(f), v.length(), str(st.get("event", ""))])


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
