extends Node
## ★63-22 真机探针 A：**试听系统**（划到即播 · 2 s 渐入 · 播前 15 秒）。
##
## ## 为什么套件不够（⚠️ 这里是 ★63-20 那句话的**修正版**）
## `--headless` 是 Dummy 音频驱动，**混音不推进**。但注意：`AudioStreamPlayer.playing`
## 在本机 headless 下**也是 true**（★63-20 记的"恒 false"不成立，本探针无头跑就打印过 true）。
## 真正**只有真机**能证的是 **解码位置在推进**（`get_playback_position()` 会涨）。
## ⇒ 三件**只能在这里证**的事：
##   ① 真的在响（`playing == true` **且解码位置推进** ← 后者才是真机独有）；
##   ② **2 s 渐入** —— 逐 0.1 s 采样 `preview_volume_db()` 画出那条曲线；
##   ③ **15 s 到点就停** —— 真等 15.6 s（⚠️ **不许**为了快把 `PREVIEW_SECONDS` 改小，
##      那读的不是用户要的那个值）。
## 逻辑侧（状态机 / "同一首不重启" / 触发点唯一）在 `suite_bgm_preview.gd` 里证。
##
## ## 跑法（⚠️ **不要**加 `--headless`）
##   Godot_v4.7.1-stable_win64_console.exe --path <工程> \
##       res://tools/_r63_22_bgm_preview.tscn -- <输出目录>
##
## ## 读六件事
## ① 常量读数（读 `Audio` 上的真值，不是探针里另抄一份）
## ② **解码位置在推进** ← 这一条无头读不到（headless 下 `playing` 会是 true，但位置不涨）
## ③ **渐入曲线**：1.0 s 时**还在中段**（证"渐"）、2.4 s 时**已到 ≈0 dB**（证"2 s 完成"）
## ④ **15 s 到点**：最后一次听到 t ≤ 15.5 s 且此后 `playing == false`
## ⑤ **3 s 时对同一行再触发一次** ⇒ 秒表**不重置**（若重启，停的时刻会滑到 18.3 s）
## ⑥ 菜单 BGM 进页被压低、离开恢复
##
## ⚠️ 本探针**不写玩家存档**（`_bgm_set_row()` 只读、不落盘）—— 跑前跑后 md5 必须一致。

const SHOT_W := 1600
const SHOT_H := 900

const SAMPLE_DT := 0.1          # 采样间隔（秒）
const FADE_WINDOW := 2.6        # 采样到 2.6 s（渐入 2 s + 余量；按时间取点，不按下标）
const RECALL_AT := 3.0          # 在 t=3.0 s 对**同一行**再触发一次（证"不重启"）
const STOP_DEADLINE := 15.6     # 15.0 + 淡出 0.3 + 余量

var main: Node
var out_dir := "user://shots_r63_22_preview"
var _fails := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	var cfg := ProjectSettings.globalize_path("user://settings.cfg")
	var md5_before := _md5(cfg)
	print("========== ★63-22 试听系统 · 真机探针 ==========")
	print("SETTINGS cfg=%s  md5前=%s" % [cfg, md5_before])

	# ⚠️ main 当**子节点**挂（不是 change_scene_to_file）⇒ 开场动画不抢画面（★63-20 同款）。
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

	# ---- ① 常量读数（从 Audio 上读真值）+ 架构：独立播放器 ----
	var fade_in: float = Audio.PREVIEW_FADE_IN
	var total_s: float = Audio.PREVIEW_SECONDS
	var fade_out: float = Audio.PREVIEW_FADE_OUT
	var duck_db: float = Audio.MENU_DUCK_DB
	print("PARAMS 渐入=%.1fs  总时长=%.1fs  到点淡出=%.2fs  压低=%.1fdB" % [
		fade_in, total_s, fade_out, duck_db])
	_check(is_equal_approx(fade_in, 2.0), "渐入常量 = 2.0 s（用户原话「2s 的渐入效果」）")
	_check(is_equal_approx(total_s, 15.0), "总时长 = 15.0 s（用户原话「前面十五秒」）")

	var pv: Variant = Audio.get("_preview")
	var players: Array = Audio.get("_bgm_players")
	_check(pv != null, "试听播放器已建（`_preview` 非空）")
	_check(not players.has(pv), "⭐ 试听是**独立**播放器 —— 没借 `_bgm_players` 那两个")
	_check(_preview_count() == 1, "名为 `Preview` 的播放器**恰好 1 个**")

	var keys: Array = MainMenu.bgm_pick_keys()
	var ia := 1
	var ib := 2
	var track_a := str(keys[ia])
	var track_b := str(keys[ib])
	print("TRACKS A=%s（下标 %d）  B=%s（下标 %d）" % [track_a, ia, track_b, ib])
	_check(track_a != "" and track_b != "" and track_a != track_b, "抽了两首不同的曲做对比")

	# ---- 进选歌页 ----
	menu.set("stage", MainMenu.Stage.BGM)
	menu.set("bgm_sub", MainMenu.BGM_SUB_PICK)
	menu.set("bgm_row", 0)
	await _frames(10)

	# ⚠️ 先证"划到「随机」行 ⇒ 停"（那一行背后没有具体曲子）
	Audio.preview_bgm(track_b)
	await _frames(6)
	menu.call("_bgm_set_row", 0)
	await _frames(6)
	print("RANDOM 划到第 0 行（随机）⇒ preview_track=%s" % _q(Audio.preview_track()))
	_check(Audio.preview_track() == "", "划到「随机」行 ⇒ 试听停掉（没有东西可听就不响）")

	# ---- ② 起播 + 采样渐入曲线 ----
	var t0 := _wall()
	menu.call("_bgm_set_row", ia)
	await _frames(2)
	print("START track=%s  playing=%s  vol=%.2f dB" % [
		_q(Audio.preview_track()), str(Audio.is_preview_playing()), Audio.preview_volume_db()])
	_check(Audio.preview_track() == track_a, "划到第 %d 行 ⇒ 试听的就是它" % ia)
	_check(Audio.is_preview_playing(), "试听播放器 `playing == true`（⚠️ 本机无头跑**也是 true** ⇒ 这条本身不区分真假机）")
	await _shot("01_preview_started")

	# ⚠️ 采样点必须**连时间一起记**：循环每圈的实际耗时是 ~0.115 s 而不是 0.1 s
	#（每圈还 await 了一个物理帧），所以"下标 22 = 第 2.2 秒"这种写法会**取不到点**
	#（第一次真机跑就是这样，`t≈2.2s=-999`）。改成按时间取最近一个"不晚于目标"的点。
	var times: Array[float] = []
	var volts: Array[float] = []
	while _wall() - t0 < FADE_WINDOW:
		times.append(_wall() - t0)
		volts.append(Audio.preview_volume_db())
		await _wait_sec(SAMPLE_DT)
	var at_end := Audio.preview_volume_db()
	var s0 := _at(times, volts, 0.2)
	var s10 := _at(times, volts, 1.0)
	var s22 := _at(times, volts, 2.2)
	print("FADE 采样 %d 点（目标每 %.1f s）  末点 t=%.2f s  按时间取：t=0.2→%.2f  t=1.0→%.2f  t=2.2→%.2f  末读=%.2f" % [
		volts.size(), SAMPLE_DT, times[times.size() - 1] if not times.is_empty() else -1.0,
		s0, s10, s22, at_end])
	print("FADE 曲线=%s" % _curve(volts))
	_check(volts.size() >= 20, "采到了 %d 个点（够看出曲线的形状）" % volts.size())
	_check(times.size() > 0 and times[times.size() - 1] >= 2.0,
		"采样窗口真的盖到 2.0 s（末点 t=%.2f s）" % (times[times.size() - 1] if not times.is_empty() else -1.0))
	# ⚠️ 这三条**都能红**：把 `PREVIEW_FADE_IN` 改成 0 ⇒ 第①条立刻红（t=1.0 s 就已经 0 dB）。
	_check(s10 <= -10.0, "t=1.0 s 才 %.2f dB ⇒ 渐入是**渐**的（不是一下就到）" % s10)
	_check(s10 >= -55.0, "t=1.0 s 已有 %.2f dB ⇒ 确实在响（不是一直静音）" % s10)
	_check(s22 >= -0.5, "t=2.2 s 到 %.2f dB ≈ 0 ⇒ 2 s 渐入**已完成**" % s22)
	print("FADE 单调升=%s" % str(_monotone(volts)))
	_check(_monotone(volts), "整条曲线单调不降（没有「渐到一半音量乱跳」）")

	# ---- ⭐ 真机**独有**的那一条：解码位置在推进 ----
	# ⚠️ 这里修正 ★63-20 留下的一个说法：「headless 里 `playing` 恒 false」**在本机不成立** ——
	# 实测 `--headless`（Dummy 驱动）下 `playing` **也是 true**（上面那条 START 行就是无头跑出来的）。
	# 真正**只有真机**能证的是**解码在推进**：Dummy 驱动不混音 ⇒ `get_playback_position()`
	# 停在原地不涨。所以"文件真的被解码了（不是挂了个空 stream）"这条判据只能在这儿出。
	var pv_player := Audio.get("_preview") as AudioStreamPlayer
	var pos0 := pv_player.get_playback_position()
	await _wait_sec(0.8)
	var pos1 := pv_player.get_playback_position()
	print("POS 试听解码器位置 %.3f → %.3f s（len=%.2f s, advanced=%s）" % [
		pos0, pos1, pv_player.stream.get_length() if pv_player.stream != null else 0.0,
		str(pos1 > pos0)])
	_check(pos1 > pos0, "⭐ 试听解码位置在推进（Dummy 音频驱动下**不会**推进 ⇒ 这条只能真机读）")
	await _shot("02_fade_in_done")

	# ---- ⑤ 同一行再触发 ⇒ **不重启**（秒表不重置）----
	while _wall() - t0 < RECALL_AT:
		await _wait_sec(SAMPLE_DT)
	var vol_before := Audio.preview_volume_db()
	menu.call("_bgm_set_row", ia)
	await _frames(4)
	print("RECALL t=%.2f s 再触发同一行：vol %.2f→%.2f  track=%s" % [
		_wall() - t0, vol_before, Audio.preview_volume_db(), _q(Audio.preview_track())])
	_check(Audio.preview_track() == track_a, "同一行再触发 ⇒ 还是这首（没被清掉）")
	_check(absf(Audio.preview_volume_db() - vol_before) < 1.0, "同一首不重启 ⇒ 音量没被重置回 −60")

	# ---- ③ 等到 15.6 s：必须停（且秒表**不是**从 3.0 s 重算）----
	var t_last := -1.0
	while _wall() - t0 < STOP_DEADLINE:
		if Audio.is_preview_playing():
			t_last = _wall() - t0
		await _wait_sec(SAMPLE_DT)
	print("STOP 最后一次听到 t=%.2f s  截止 t=%.2f s  playing=%s  track=%s" % [
		t_last, _wall() - t0, str(Audio.is_preview_playing()), _q(Audio.preview_track())])
	_check(not Audio.is_preview_playing(), "⭐ 15 s 到点后 `playing == false`")
	_check(Audio.preview_track() == "", "停了之后 `preview_track()` 清空（划走再划回来会重放）")
	_check(t_last > 0.0 and t_last <= 15.5,
		"最后一次听到 t=%.2f s ⇒ **15 s 到点就停**（若 3 s 那次重启了秒表，这里会拖到 18.3 s）" % t_last)
	await _shot("03_stopped_after_15s")

	# ---- 换行 ⇒ 上一首停、新的在播；且播放器**没叠** ----
	menu.call("_bgm_set_row", ib)
	await _frames(4)
	print("SWITCH track=%s  playing=%s  Preview 播放器数=%d" % [
		_q(Audio.preview_track()), str(Audio.is_preview_playing()), _preview_count()])
	_check(Audio.preview_track() == track_b, "换行 ⇒ 试听换成了新的那一首")
	_check(Audio.is_preview_playing(), "换行之后新的那首在播")
	_check(_preview_count() == 1, "换行前后 `Preview` 始终只有 1 个（没有叠着放）")
	await _shot("04_switched_row")
	Audio.stop_preview(0.0)
	await _frames(4)
	_check(not Audio.is_preview_playing(), "`stop_preview(0.0)` 立即停")

	# ---- ⑥ 菜单 BGM 压低 / 恢复 ----
	var bgm_kind: int = Audio.current_bgm()
	var v_off := _active_bgm_db()
	menu.set("stage", MainMenu.Stage.SETTINGS)          # 离开 ⇒ 恢复
	await _wait_sec(0.6)
	var v_back := _active_bgm_db()
	menu.set("stage", MainMenu.Stage.BGM)               # 进页 ⇒ 压低
	menu.set("bgm_sub", MainMenu.BGM_SUB_PICK)
	await _wait_sec(0.6)
	var v_duck := _active_bgm_db()
	print("DUCK 菜单BGM=%d  离开=%.2f dB  在页=%.2f dB  目标压低=%.1f dB" % [
		bgm_kind, v_back, v_duck, duck_db])
	if bgm_kind == Audio.Bgm.MENU:
		_check(v_duck < v_back - 6.0,
			"进选歌页 ⇒ 菜单 BGM 被压低（%.2f → %.2f dB）" % [v_back, v_duck])
	else:
		print("DUCK 菜单 BGM 没在放（current_bgm=%d）⇒ 压低无从量起，跳过" % bgm_kind)

	# ---- 收尾 ----
	Audio.set_menu_duck(0.0)
	Audio.stop_preview(0.0)
	await _frames(8)
	print("RESTORED md5后=%s" % _md5(cfg))
	_check(_md5(cfg) == md5_before, "本探针没动玩家存档（`_bgm_set_row()` 只读不落盘）")
	print("========== 探针结束：不符 %d 条 ==========" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## 名为 `Preview` 的 AudioStreamPlayer 有几个 —— 防"叠了好几个播放器"。
func _preview_count() -> int:
	var n := 0
	for c in Audio.get_children():
		if c is AudioStreamPlayer and str(c.name) == "Preview":
			n += 1
	return n


## 当前生效的那一路菜单 BGM 的音量（dB）。
func _active_bgm_db() -> float:
	var players: Array = Audio.get("_bgm_players")
	if players.is_empty():
		return 0.0
	var p := players[Audio.get("_bgm_active")] as AudioStreamPlayer
	return p.volume_db if p != null else 0.0


## 取"时间**不晚于** t 的最近一个采样点"的音量。
##
## ⚠️ 为什么不按下标取：采样循环每圈**实际**耗时 ~0.115 s（`_wait_sec` 里还 await 了物理帧），
## 不是常量 `SAMPLE_DT`=0.1 ⇒ "第 22 个点 = 第 2.2 秒"这种写法**会取不到点**（第一次真机跑
## 就是这个错：`t≈2.2s=-999.00`，点数 21 个根本凑不满 2.2 s）。按时间取点才稳。
func _at(times: Array[float], volts: Array[float], t: float) -> float:
	var best := -999.0
	for i in times.size():
		if times[i] <= t:
			best = volts[i]
	return best


## 曲线单调不降（允许 0.01 的浮点毛刺）。
func _monotone(xs: Array[float]) -> bool:
	for i in range(1, xs.size()):
		if xs[i] < xs[i - 1] - 0.01:
			return false
	return true


## 把曲线画成一行 ASCII（人眼扫一遍就能看出是不是"渐"的）。
func _curve(xs: Array[float]) -> String:
	var out := ""
	var step := maxi(1, xs.size() / 26)
	var i := 0
	while i < xs.size():
		var v: float = xs[i]
		if v <= -50.0:
			out += "."
		elif v <= -30.0:
			out += "·"
		elif v <= -12.0:
			out += ":"
		elif v <= -3.0:
			out += "+"
		else:
			out += "#"
		i += step
	return out


func _q(s: String) -> String:
	return "\"%s\"" % s


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
	# 等**物理帧**（物理固定 60 Hz；渲染帧在高刷窗口里只有几分之一秒，会"还没重画就截图了"）。
	for i in n:
		await get_tree().physics_frame


func _wait_sec(s: float) -> void:
	# 等**真秒数**（墙钟）而不是帧数。
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await get_tree().physics_frame


func _wall() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _shot(name: String) -> void:
	# ⚠️ headless（Dummy 渲染器）下 `RenderingServer.frame_post_draw` **永不触发**
	# ⇒ 不加这一句的话，无头跑会**卡死在那里**（实测踩过：就停在第一个 `_shot`）。
	if DisplayServer.get_name() == "headless":
		print("SHOT_SKIPPED(headless) ", name)
		return
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
