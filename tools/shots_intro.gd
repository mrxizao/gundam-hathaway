extends Node
## 开场动画**专用**真机截图台。
##
## ⚠️ **不能加 `--headless`** —— 无头是 dummy 渲染器，一个像素都不产生，抓出来全黑。
## 这个脚本的全部意义就是**能真的看到**（提示字的位置 / 排版 / 是否压住画面）。
##
## 跑法：
##   godot --path <工程> res://tools/shots_intro.tscn -- <输出目录>
##
## ## 为什么走 `change_scene_to_file` 而不是像别的截图台那样 `add_child(main)`
## 别的截图台把 `main.tscn` 当**子节点**挂进自己的场景里跑，于是
## `get_tree().current_scene` 是**工具自己** —— `IntroMovie.should_play_now()` 会判 false，
## 开场动画根本不播。这一台要验的恰恰是"真开局会不会播"，所以必须把
## `current_scene` 换成 `main.tscn`。
##
## ⚠️ 代价：`change_scene_to_file()` 会把**本工具场景整棵树**释放掉（包括这个脚本）。
## 所以真正干活的观察者是 `Watcher` —— 它被挂在 `SceneTree.root` 上（不是 current_scene
## 的子节点），换场景伤不到它。

const SHOT_W := 1600
const SHOT_H := 900


## 挂在 root 上的观察者：等真开局 → 拍 → 跳过 → 拍 → 等主菜单 → 再强制补两支。
class Watcher extends Node:
	var out_dir := ""
	var main: Node

	func _ready() -> void:
		set_process(false)
		_run()

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	## 按**墙钟**等：`process_frame` 在 165 Hz 的窗口里只走 1/165 秒，
	## 用帧数当时间会拍出完全不同的时刻（第一次跑就是这么踩的 —— 两支片子
	## 都停在片头的 SUNRISE 标上，看着像"两支一样"）。
	func _wait_sec(s: float) -> void:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < int(s * 1000.0):
			await get_tree().process_frame

	func _shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		var vp := get_viewport()
		if vp == null:
			print("SHOT_FAILED(no viewport) %s" % name)
			return
		var img := vp.get_texture().get_image()
		if img == null:
			print("SHOT_FAILED(no image) %s" % name)
			return
		var path := out_dir.path_join(name)
		print("SHOT %s err=%d size=%s" % [path, img.save_png(path), str(img.get_size())])

	## 等 `current_scene` 变成真正的主场景（WorldBuilder 建图要几十帧）。返回是否等到。
	func _await_main(max_frames: int) -> bool:
		for i in max_frames:
			await get_tree().process_frame
			var cs := get_tree().current_scene
			if cs != null and cs.get("_maybe_play_intro") != null:
				main = cs
				return true
		return false

	func _run() -> void:
		if not await _await_main(900):
			print("SHOTS_INTRO_FAILED(等不到主场景变成 current_scene)")
			get_tree().quit(1)
			return
		# ⚠️ 主场景一 ready 就判过 `should_play_now()` 了 —— 这里只是取它的结果。
		var intro = main.get("intro")
		print("REAL_PATH current_scene=%s intro=%s"
			% [main.name, "null" if intro == null else str(intro.name)])
		if intro == null or not is_instance_valid(intro):
			print("SHOTS_INTRO_FAILED(真开局没有起播开场动画 —— should_play_now() 判成了 false)")
			get_tree().quit(1)
			return

		var ci: int = int(intro.get("clip_index"))
		var clip := IntroPlaylist.clip_at(ci)
		var video = intro.get("_video")
		print("PICKED clip_index=%d id=%s label=%s length=%.2fs"
			% [ci, str(clip["id"]), str(clip["label"]),
			(float(video.get_stream_length()) if video != null else -1.0)])
		print("HINT %s" % str(intro.call("hint_text")))
		var canvas: Node = main.get("canvas")
		var last := canvas.get_child(canvas.get_child_count() - 1)
		print("LAYER canvas_children=%d last_child=%s（开场动画必须是最上面那一层）"
			% [canvas.get_child_count(), str(last.name)])
		var overlay_size: Vector2 = intro.get("size")
		print("OVERLAY size=%s" % str(overlay_size))

		await _wait_sec(2.5)
		# ---- 音频证据 ----
		# 视频的声轨走**工程的 BGM 总线**（`IntroMovie.begin()` 里设的），所以
		# "BGM 总线有电平"就是"Godot 的 Theora 播放**真的在出声**"。
		# 官方文档只写了 core 支持"可选带 Ogg Vorbis 音轨"，实机量一次更踏实 ——
		# 毕竟这一条只能靠听，而听是没法写进回归的。
		var bi := Settings.bus_index(Settings.BUS_BGM)
		print("AUDIO bus=%s peak_L=%.2f dB peak_R=%.2f dB"
			% [Settings.BUS_BGM, AudioServer.get_bus_peak_volume_left_db(bi, 0),
			AudioServer.get_bus_peak_volume_right_db(bi, 1)])
		await _shot("01_真机_进游戏首帧.png")

		# ---- 任意键跳过 → 淡出中 ----
		intro.call("skip")
		await _wait_sec(0.2)
		await _shot("02_跳过_淡出中.png")

		# ---- 等它收尾，主菜单自己出来 ----
		for i in 400:
			await get_tree().process_frame
			if main.get("intro") == null:
				break
		await _frames(20)
		await _shot("03_跳过之后_主菜单.png")
		print("AFTER_SKIP intro=%s menu_visible=%s"
			% [str(main.get("intro")), str(main.get("menu").visible)])

		# ---- 强制把两支各播一遍：这两张才是"视频层本身长什么样"的可复现证据 ----
		# （真开局那一支是随机的 80/20，不能拿它当某一支的证据。）
		var menu = main.get("menu")
		if menu != null and is_instance_valid(menu):
			menu.close_menu()
		var forced := [[0, "04_强制_开头动画.png"], [1, "05_强制_马夫蒂劫持演说.png"]]
		for pair in forced:
			var idx: int = int(pair[0])
			var movie: IntroMovie = IntroMovie.spawn(canvas)
			if movie == null or not movie.begin(idx):
				print("SHOTS_INTRO_FAILED(强制第 %d 支起播失败)" % idx)
				continue
			await _wait_sec(6.0)
			await _shot(str(pair[1]))
			movie.dispose()
			await _frames(10)

		print("SHOTS_INTRO_DONE out=%s" % out_dir)
		get_tree().quit(0)


var out_dir := "user://captures_intro"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	# ⚠️ 必须**延后一帧**再动手：`_ready()` 里 root 正忙着装配本场景的子节点，
	# 这时候 `add_child()` 会直接失败（"Parent node is busy setting up children"），
	# 于是观察者根本没挂上、换场景之后什么都不会发生（静默、无图、退出码还是 0）。
	# 顺带把"挂观察者"排在"换场景"**之前** —— 换场景会把本场景整棵树释放掉，
	# 观察者必须先在 root 上站着。
	_boot.call_deferred()


func _boot() -> void:
	var w := Watcher.new()
	w.name = "IntroWatcher"
	w.out_dir = out_dir
	# ⚠️ 挂 root（不是挂自己）：下面换场景会把本场景整棵树释放掉。
	get_tree().root.add_child(w)
	# 走**真开局**这条路：`current_scene` 被换成 main.tscn，
	# `IntroMovie.should_play_now()` 于是为真 —— 这正是要在真机里验的那一条。
	get_tree().change_scene_to_file("res://scenes/main.tscn")
