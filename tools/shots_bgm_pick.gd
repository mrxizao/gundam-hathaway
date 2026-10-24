extends Node
## 「战斗BGM 自选」页真机截图台（轮 28）。
##
## 为什么单开一个：轮 25 那个 `shots_menu_pages` 的职责是"设置页 + 重绑页"两件界面事实，
## 本轮要核的是第三页（选歌页），目的也不同，混进去会把那个脚本的说明写歪。
##
## 本轮改动里有一句**玩家可见的字面文案** —— 选歌页给「仅自选曲」加的后缀标记
## 「（仅自选 · 不参与随机）」。字面量**没有消费者**：纯逻辑断言全绿，
## 它照样可以是错的、或者根本没画出来。所以必须出图。
##
## 同时核一件只在真机成立的事：**选了它之后真的播得出来** ——
## 不只是"名字对上了"，还要 `stream_position` 真的在推进（解码器真在读这个文件）。
##
## ⚠️ **不能加 `--headless`**：无头是 dummy 渲染器 + Dummy 音频驱动，
## 既截不出像素、也推不动混音。
##
## ⚠️ 本脚本会临时改 `Settings.battle_bgm_pick` —— 那是**写盘的玩家存档**，
## 结尾必须**原样还回去并写回盘**，否则等于替玩家改了「战斗BGM」。
##
## 跑法：
##   godot --path <工程> res://tools/shots_bgm_pick.tscn -- <输出目录>

const SHOT_W := 1600
const SHOT_H := 900

var main: Node
var out_dir := "user://shots_bgm_pick"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	# ⚠️ 把 main 当**子节点**挂（不是 change_scene_to_file）⇒ `current_scene != main`
	# ⇒ `IntroMovie.should_play_now()` 判 false，开场动画不会插进来抢画面。
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	var menu: Node = main.get("menu")
	if menu == null or not is_instance_valid(menu):
		push_error("SHOTS_FAILED(no menu)")
		get_tree().quit(1)
		return

	var pick_backup: String = Settings.battle_bgm_pick
	var keys: Array = MainMenu.bgm_pick_keys()
	var target: int = keys.find("sweet_child")
	print("PICK_KEYS n=%d  target=%d  pool=%d  label=%s  note=%s" % [
		keys.size(), target, SoundBank.BATTLE_TRACKS.size(),
		SoundBank.battle_track_label("sweet_child"), SoundBank.battle_track_note("sweet_child")])
	print("BAG_POOL_HAS_SWEET=%s" % str(SoundBank.BATTLE_TRACKS.has("sweet_child")))

	# ---- ① 选歌页：翻到末行（仅自选曲）并选中它 ----
	menu.set("stage", MainMenu.Stage.BGM)
	await _frames(6)
	menu.set("bgm_row", target)
	# 走菜单 Enter 的同一条路径（`_read_bgm_input` 里就是这一句）
	Settings.set_battle_bgm_index(target)
	await _frames(16)
	await _shot("bgm_pick_sweet_child")
	print("AFTER_PICK pick=%s  label=%s  index=%d" % [
		Settings.battle_bgm_pick, Settings.battle_bgm_label(), Settings.battle_bgm_index()])

	# ---- ② 真机播出证明 ----
	Audio.set_story_mode(false)
	Audio.request_battle_open(Settings.battle_bgm_pick)
	Audio.play_bgm(Audio.Bgm.BATTLE, 0.0)
	await _frames(8)
	var players: Array = Audio.get("_bgm_players")
	var p: AudioStreamPlayer = players[Audio.get("_bgm_active")]
	var pos0: float = p.get_playback_position()
	# 时长走 `AudioStream.get_length()`（**不是** `AudioStreamPlayer` —— 那是
	# `VideoStreamPlayer` 才有的方法，轮 26 在视频那边踩过同一个坑）。
	var len_s := 0.0
	if p.stream != null:
		len_s = p.stream.get_length()
	await _wait_sec(1.2)
	var pos1: float = p.get_playback_position()
	print("PLAY track=%s  playing=%s  bus=%s  pos=%.3f->%.3f  len=%.2fs  advanced=%s" % [
		Audio.current_bgm_track(), str(p.playing), p.bus, pos0, pos1, len_s,
		str(pos1 > pos0)])
	await _shot("bgm_playing_sweet_child")

	# ---- 收尾：静音 + **原样还回玩家存档** ----
	Audio.stop_bgm(0.0)
	Settings.battle_bgm_pick = pick_backup
	Settings.save_config()
	print("RESTORED pick=%s" % ("(空 = 随机)" if pick_backup == "" else pick_backup))

	print("SHOTS done -> %s" % out_dir)
	get_tree().quit(0)


func _frames(n: int) -> void:
	# 等**物理帧**（物理固定 60 Hz；渲染帧在 300+ fps 的窗口里只有几分之一秒，
	# 会出现"页面还没重画就截图了"）。
	for i in n:
		await get_tree().physics_frame


func _wait_sec(s: float) -> void:
	# 等**真秒数**（按墙钟）而不是帧数：窗口跑在 165 Hz vsync 上时，
	# `process_frame` × N 与实际秒数完全不是一回事。轮 26 在这里栽过。
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
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
