extends Node
## 场景亮度增益（`SCENE_GAIN`）的**真机 A/B 截图台**（轮 23）。
##
## ## 为什么单开一个（而不是用 `tests/pixprobe.tscn`）
##
## 用户这一轮的口径是「**只压场景，机体不动**」—— 于是必须有"机体那一块像素没变"的证据。
## 而 `pixprobe` 的机位是"玩家视角的后上方偏移"，实测**拍不到玩家机体**：
##   · 达沃夜战 · 默认机位 —— 画面里只有俯瞰的城市，差分掩码上找不到机体那一块；
##   · 把相机拉到机体正后方 20 m（`--bodycam=20`）—— 仍然没有；
##   · 甚至把场景增益拧到 **0**（地面楼体全黑、只剩自发光）—— 机体**还是**不出现。
## ⇒ 那是它走**同步入口**起局（刻意绕过读条协程，为了确定性）的副产物，不是增益的错。
## 但后果是：「场景增益动不动机体」这个 pixprobe **本该能回答**的问题，
## 在它上面根本无从验证 —— 而两张图照样会输出一堆差值、照样能写出一张看着很像样的表。
##
## 这个台子走**完整流程** + `main.chase`（**第三人称追随机体**）⇒ 机体一定在画面里。
##
## ## 跑法（⚠️ **不能加 `--headless`**：dummy 渲染器一个像素都不产生）
##
##   godot --path <工程> res://tools/scene_gain_shot.tscn -- <输出目录> <场景增益>
##
## 例（A/B 两张，其余条件一字不动）：
##   ... -- /tmp/ab 1.40        # 旧档（轮 12 定的 1.40）
##   ... -- /tmp/ab 0.98        # 新档（轮 23 「压暗 30%」）
##
## ⚠️ 增益必须在 `_on_start_match` **之前**注入：场景材质是在建图时把颜色算死的，
## 建完图再改**不生效**（与 `pixprobe --scenegain` 是同一个坑，那里有完整的血泪注释）。
##
## ⚠️⚠️ 两张图之间**唯一的变量必须是增益**。所以：
##   · 机位与姿态走**固定物理帧数**，不用"等相机稳定"那种不定帧数循环
##     —— 两次运行的贴合时刻会差几帧 ⇒ 差分图全是噪声，而均值表看着还挺合理；
##   · **敌机必须钉死**（关掉它的 `physics_process`、速度清零、放到固定位置）：
##     它的 AI 每帧都会动，不钉的话两张图会"各飞各的"。
## 物理固定在 60 Hz，固定帧数 ⇒ 固定世界状态。

const SHOT_W := 1600
const SHOT_H := 900
## 摆好姿态后等这么多**物理帧**再截图 —— 足够让追尾相机完全贴合。
const SETTLE_FRAMES := 120

var main: Node
var out_dir := "user://captures_scene_gain"
## ≤0 = 不覆盖（用工程里的默认值）。
var gain := 0.0
## 进来时玩家的第一人称开关（结尾原样还回去）。
var _fpv_was := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		gain = float(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	# ---- 关掉第一人称：本台子要的是 `main.chase`（第三人称追随机体）----
	#
	# ⚠️⚠️ 这个开关**不能假设它是 false**：它是玩家存档里的一份设置，
	# 而且同时管两件事 ——「HUD 画不画座舱装饰」与「相机走座舱还是追尾」。
	# 上一轮的 `tools/capture_fpv.gd` 把它打开过，实测这里进来时它就是 true，
	# 于是第一次跑出来的"机体 A/B 图"里**根本没有机体**（画面是座舱视角的沙漠）。
	# 所以显式关掉，结束时再原样还回去。
	_fpv_was = Settings.first_person
	Settings.set_first_person(false)

	# ---- 增益注入（**必须在建图之前**）----
	if gain > 0.0:
		var world = main.get("world")
		if world != null:
			world.scene_gain = gain
		print("SCENEGAIN %.3f（在建图之前注入）" % gain)
	else:
		print("SCENEGAIN 用工程默认值")

	# ---- 起一局：1v1 · 柯西 · 沙漠（地平线清楚，机体轮廓读得出来）----
	# ⚠️ 必须先 `close_menu()`：主菜单页还在的时候 `_on_start_match` 会走另一条路。
	var menu = main.get("menu")
	if menu != null and is_instance_valid(menu):
		menu.close_menu()
	await _frames(10)
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.ULURU, Game.MatchMode.VERSUS)
	await _frames(30)
	main.call("_start_fight")

	var p := _p()
	if p == null:
		push_error("SCENE_GAIN_SHOT_FAILED(no player)")
		_restore()
		get_tree().quit(3)
		return
	p.max_hp = 99999.0
	p.hp = 99999.0
	p.ifield_max = 9999.0
	p.ifield_hp = 9999.0
	_make_enemy_durable()

	# 摆在沙漠上空：机身在画面中央、地平线横过画面中部 ⇒
	# "地面暗下去了、机体没暗" 一眼可读。
	p.global_position = Vector3(3000.0, 900.0, 1500.0)
	await _pose(0.0, 0.0, 0.0)
	await _shot("gain_%s" % _gain_tag())

	print("SCENE_GAIN_SHOT_DONE out=%s" % out_dir)
	_restore()
	get_tree().quit()


## 把第一人称开关还给玩家原本的值（不还的话，跑一次截图台就把玩家存档改了）。
func _restore() -> void:
	if Settings.first_person != _fpv_was:
		Settings.set_first_person(_fpv_was)
		print("SCENE_GAIN_SHOT restored first_person=%s" % str(_fpv_was))


func _gain_tag() -> String:
	if gain <= 0.0:
		return "default"
	return "%.2f" % gain


# ------------------------------------------------------------ 姿态与取景

## 把机体摆到一个确定的姿态，然后**等固定帧数**（不用"等稳定"）。
##
## ⚠️ 写 `basis` 而不是 `look_at()`：`look_at` 只定死机头方向，
## 滚转只能靠 `up` 参数间接表达，摆不出"精确右滚 30°"。
## 欧拉角一次给全（`from_euler` 默认 YXZ：先偏航、再俯仰、后滚转）。
func _pose(pitch: float, roll: float, yaw: float) -> void:
	var p := _p()
	if p == null:
		return
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), deg_to_rad(roll)))
	p.global_transform = Transform3D(b, p.global_position)
	p.fm.align_velocity(p.forward())
	# 悬停 + 零油门：机体**停在原地**，位置不随等待漂移 ⇒ 两张图的世界状态更接近。
	_drive(Vector3.ZERO, 0.0, false, true)
	await _frames(3)
	# 再钉一次：飞行控制器在同一物理帧里也写这个 basis，晚一帧写才能保证是最后生效的那个。
	p.global_transform = Transform3D(b, p.global_position)
	p.fm.align_velocity(p.forward())
	await _frames(SETTLE_FRAMES)
	print("POSE pitch=%.1f roll=%.1f yaw=%.1f pos=%s" % [
		pitch, roll, yaw, str(_p().global_position)])


# ------------------------------------------------------------ 工具（与 tools/capture_fpv.gd 同源）

func _p() -> Node:
	var n = main.get("player")
	return n if (n != null and is_instance_valid(n)) else null


func _e() -> Node:
	var n = main.get("enemy")
	return n if (n != null and is_instance_valid(n)) else null


## 敌机**钉死**：它是画面里唯一的非确定运动源。
func _make_enemy_durable() -> void:
	var e := _e()
	if e == null:
		return
	e.max_hp = 99999.0
	e.hp = 99999.0
	e.ifield_max = 400.0
	e.ifield_hp = 400.0
	e.flare_count = 999
	e.set_physics_process(false)
	e.fm.velocity = Vector3.ZERO
	e.fm.speed = 0.0
	var p := _p()
	if p != null:
		e.global_position = p.global_position + p.forward() * 1400.0 + Vector3(160.0, 30.0, 0.0)
		e.look_at(p.global_position, Vector3.UP)


func _drive(input: Vector3, throttle := 0.8, boost := false, hover := false) -> void:
	var p := _p()
	if p == null:
		return
	p.debug_input_enabled = true
	p.debug_input = input
	p.debug_throttle = throttle
	p.debug_boost = boost
	p.debug_hover = hover


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _grab() -> Image:
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport)")
		return null
	var tex := vp.get_texture()
	if tex == null:
		print("SHOT_FAILED(no texture)")
		return null
	var img := tex.get_image()
	if img == null:
		print("SHOT_FAILED(no image)")
		return null
	return img


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null:
		return
	var path := out_dir.path_join("%s.png" % name)
	var err := img.save_png(path)
	print("SHOT %s  err=%d" % [path, err])
