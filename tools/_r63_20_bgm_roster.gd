extends Node
## ★63-20 真机探针：46 首「仅自选」历代战斗曲 —— 出图 + 证明它真的在播。
##
## ## 为什么套件不够（两件套件**证不了**的事）
## `--headless` 是 dummy 渲染器 + Dummy 音频驱动：
##   · **截不出像素** ⇒「选歌页长什么样 / 55 行画不画得下」证不了；
##   · **`AudioStreamPlayer.playing` 永远 false** ⇒「选了它真的响」证不了。
## 所以分工是：`suite_battle_bgm_roster.gd` 证逻辑与行为（轮换数学、抽 165 次不出现），
## 这里证**像素**与**声音**。
##
## ## 跑法（⚠️ **不要**加 `--headless`）
##   Godot_v4.7.1-stable_win64_console.exe --path <工程> \
##       res://tools/_r63_20_bgm_roster.tscn -- <输出目录>
##
## ## 读四件事
## ① 选歌页三张图：顶部（随机 + 轮换池）/ 中段（新曲被选中）/ 底部（老面孔仍在末位）
## ② 版式读数：54 条选项逐条量宽，报**最挤的一条**还剩多少 px（撞右列 = 玩家读不了）
## ③ **播放实证**：`track=… playing=true pos=0.012->1.216 advanced=true`
## ④ **不选实证**：手动打 12 次"放完"，逐首点名 —— 一个仅自选曲都不许出现
## ⑤ 存档原样还回：跑前跑后 `user://settings.cfg` 的 md5（改探针不许替玩家改设置）
##
## ⚠️ 本脚本会临时改 `Settings.battle_bgm_pick` —— 那是**写盘的玩家存档**，
## 结尾必须原样还回去并 `save_config()`。

const SHOT_W := 1600
const SHOT_H := 900

## 拿来做"播放实证"的那一首（新曲里的一首，挑中间位置）。
const PROBE_TRACK := "plazma"
## 手动"放完"几次去驱动轮换（真机等一整首歌太久）。
const ADVANCES := 12

var main: Node
var out_dir := "user://shots_r63_20"
var _fails := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	var cfg := ProjectSettings.globalize_path("user://settings.cfg")
	print("========== ★63-20 历代曲册 · 真机探针 ==========")
	print("SETTINGS cfg=%s  md5前=%s" % [cfg, _md5(cfg)])

	# ⚠️ main 当**子节点**挂（不是 change_scene_to_file）⇒ `current_scene != main`
	# ⇒ 开场动画不会插进来抢画面（与 `shots_bgm_pick.gd` 同一条理由）。
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	var menu: Control = main.get("menu")
	if menu == null or not is_instance_valid(menu):
		push_error("SHOTS_FAILED(no menu)")
		get_tree().quit(1)
		return

	var pick_bak: String = Settings.battle_bgm_pick
	var keys: Array = MainMenu.bgm_pick_keys()
	print("ROSTER 自选项=%d（1 随机 + %d 轮换池 + %d 仅自选）  BGM 表=%d" % [
		keys.size(), SoundBank.BATTLE_TRACKS.size(),
		SoundBank.OPT_IN_BATTLE_TRACKS.size(), SoundBank.BGM.size()])
	var i_plazma: int = keys.find(PROBE_TRACK)
	_check(i_plazma > 0, "新曲 %s 在选歌页里（下标 %d）" % [PROBE_TRACK, i_plazma])
	_check(str(keys[keys.size() - 1]) == "sweet_child",
		"末位仍是老面孔 sweet_child（两处既有断言依赖它）")

	# ---- ② 版式读数：54 条逐条量宽，报最挤的一条 ----
	_label_fit(menu, keys)

	# ---- ① 三张图 ----
	menu.set("stage", MainMenu.Stage.BGM)
	await _frames(6)
	menu.set("bgm_row", 0)
	await _frames(6)
	await _shot("01_pick_top")

	menu.set("bgm_row", i_plazma)
	Settings.set_battle_bgm_index(i_plazma)   # 走菜单 Enter 的同一条路径
	await _frames(16)
	await _shot("02_pick_new_track_selected")
	print("PICK 选中=%s  标签=%s  序号=%d  后缀=%s" % [
		Settings.battle_bgm_pick, Settings.battle_bgm_label(),
		Settings.battle_bgm_index(), SoundBank.battle_track_note(PROBE_TRACK)])

	menu.set("bgm_row", keys.size() - 1)
	await _frames(10)
	await _shot("03_pick_bottom")

	# ---- ③ 播放实证：选中它 ⇒ 本场第一首就是它，而且解码器真的在推进 ----
	Audio.set_story_mode(false)
	Audio.request_battle_open(PROBE_TRACK)
	Audio.play_bgm(Audio.Bgm.BATTLE, 0.0)
	await _frames(8)
	var players: Array = Audio.get("_bgm_players")
	var p: AudioStreamPlayer = players[Audio.get("_bgm_active")]
	var pos0 := p.get_playback_position()
	var len_s := 0.0
	if p.stream != null:
		len_s = p.stream.get_length()
	await _wait_sec(1.2)
	var pos1 := p.get_playback_position()
	print("PLAY track=%s  playing=%s  pos=%.3f->%.3f  len=%.2fs  advanced=%s" % [
		Audio.current_bgm_track(), str(p.playing), pos0, pos1, len_s, str(pos1 > pos0)])
	_check(Audio.current_bgm_track() == PROBE_TRACK, "本场第一首 = 选中的新曲")
	_check(p.playing, "音频驱动真的在播（headless 永远读不到这一条）")
	_check(pos1 > pos0, "播放位置在推进（文件真的被解码了，不是挂了个空 stream）")
	_check(len_s > 60.0, "时长 %.1f s（> 60 s = 就是那首歌本尊）" % len_s)
	await _shot("04_new_track_playing")
	Audio.stop_bgm(0.0)
	await _frames(6)

	# ---- ④ 不选实证（负对照的另一半）：玩家什么都不选，轮换 12 次逐个点名 ----
	Audio.set_story_mode(false)
	Audio.request_battle_open("")     # = 设置页的「随机」
	Audio.play_bgm(Audio.Bgm.BATTLE, 0.0)
	await _frames(8)
	var seen: Array[String] = []
	for i in ADVANCES:
		var pp: AudioStreamPlayer = players[Audio.get("_bgm_active")]
		pp.finished.emit()
		await _frames(5)
		seen.append(Audio.current_bgm_track())
	var leaked: Array[String] = []
	for s: String in seen:
		if SoundBank.is_opt_in_battle_track(s):
			leaked.append(s)
	print("ROTATE 随机轮到 %d 首：%s" % [seen.size(), str(seen)])
	print("ROTATE 其中仅自选曲：%s   （期望 []）" % str(leaked))
	_check(seen.size() == ADVANCES, "轮换真的跑了 %d 次" % ADVANCES)
	_check(leaked.size() == 0, "玩家不选 ⇒ 轮换 %d 次一个仅自选曲都没出现" % ADVANCES)
	var all_pool := true
	for s: String in seen:
		if not SoundBank.BATTLE_TRACKS.has(s):
			all_pool = false
	_check(all_pool, "轮到的每一首都还在对战轮换池里（池子没被改宽）")
	await _shot("05_rotation_after")

	# ---- ⑤ 收尾：静音 + 原样还回玩家存档 ----
	Audio.stop_bgm(0.0)
	Audio.lock_battle_track("")
	Settings.battle_bgm_pick = pick_bak
	Settings.save_config()
	await _frames(8)
	print("RESTORED pick=%s   md5后=%s" % [
		"(空 = 随机)" if pick_bak == "" else pick_bak, _md5(cfg)])
	print("========== 探针结束：不符 %d 条 ==========" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## 54 条选项逐条量宽：`label + 后缀` 与右列（最宽的「✓ 当前开场曲」）**不许相交**。
##
## ⚠️ 这一条只能在这里做：套件里量不出字体宽度对应的**面板实际矩形**
##（那要 `MainMenu.list_panel_rect(menu.size, …)`，也就是要一个真的菜单实例）。
func _label_fit(menu: Control, keys: Array) -> void:
	var font: Font = menu.get("_font")
	if font == null:
		print("LAYOUT 拿不到 _font —— 跳过量宽")
		return
	var m: Dictionary = MainMenu.list_panel_metrics(
		menu.size, keys.size(), MainMenu.SETTING_ROW_H, MainMenu.SETTING_ROW_MAX)
	var r: Rect2 = MainMenu.list_panel_rect(menu.size, m)
	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD
	var right_w: float = font.get_string_size(
		"✓ 当前开场曲", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var worst := 1.0e9
	var worst_key := ""
	var widest := 0.0
	var widest_key := ""
	for k: String in keys:
		var label := "随机（洗牌袋轮换）" if str(k) == "" else \
			SoundBank.battle_track_label(str(k)) + SoundBank.battle_track_note(str(k))
		var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var gap := (right - right_w) - (left + w)
		if gap < worst:
			worst = gap
			worst_key = label
		if w > widest:
			widest = w
			widest_key = label
	print("LAYOUT 视口=%s  选项=%d  可见行=%d  行高=%.1f" % [
		str(menu.size), keys.size(), int(m["shown"]), float(m["row_h"])])
	print("LAYOUT 面板=[%.0f, %.0f]  左列起点=%.0f  右列宽=%.1f" % [
		r.position.x, r.position.x + r.size.x, left, right_w])
	print("LAYOUT 最宽的一条 「%s」 = %.1f px" % [widest_key, widest])
	print("LAYOUT 最挤的一条 「%s」 余量 %.1f px   （>= 0 = 不撞右列）" % [worst_key, worst])
	_check(worst >= 0.0, "54 条选项的标签都不撞右列（最挤余量 %.1f px）" % worst)


func _md5(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "(没有这个文件)"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "(读不到)"
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(f.get_buffer(f.get_length()))
	f.close()
	return ctx.finish().hex_encode()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("   [%s] %s" % ["OK" if ok else "!!", what])


func _frames(n: int) -> void:
	# 等**物理帧**（物理固定 60 Hz；渲染帧在 300+ fps 的窗口里只有几分之一秒，
	# 会出现"页面还没重画就截图了"）。
	for i in n:
		await get_tree().physics_frame


func _wait_sec(s: float) -> void:
	# 等**真秒数**（墙钟）而不是帧数 —— 窗口跑在高刷 vsync 上时两者完全不是一回事。
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
	print("SHOT %s  err=%d  %dx%d" % [path, img.save_png(path), img.get_width(), img.get_height()])
