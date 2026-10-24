extends Node
## ★63-23「音量细分」**真机**判据探针。
##
## ## 为什么必须有它
## 无头环境拿不到两样东西：
##   ① **像素**（`RenderingServer` 是 dummy ⇒ `_draw()` 不产生画面）
##      ⇒ "音量细分页真的画出来了、八行都看得见"只有真渲染能证；
##   ② **采样**（音频驱动是 Dummy ⇒ 不产生采样）⇒ "0% 真的没声音"要靠真音频设备。
##
## ## 跑法（**不能加 `--headless`**，加了拿不到图也拿不到采样）
##   Godot_v4.7.1-stable_win64_console.exe --path <工程目录> res://tests/volumeprobe.tscn \
##       -- --tag=r63_23 --out=<绝对目录>/
##
## ## 它产什么（三样，缺一样都不算取证）
##   ① 逐页截图 `vp_<tag>_*.png`（1600×900）；
##   ② stdout 上**真引擎**的总线读数：`AudioServer` 的 bus / send / volume_db / mute
##      + 八条滑条 × 三个档位（100 / 50 / 0）；
##   ③ **交叉串扰矩阵**：逐条把某一根滑条拉到 0，看**只有它自己**变了
##      —— 这是「细分」二字的全部意义；
##   ④ `AudioEffectCapture` 的 A/B：同一条 440 Hz 正弦，滑条 100% vs 0%
##      ⇒ 0% 那次的捕获缓冲必须**全 0**（"0 = 真静音"的真机证据）。
##
## ⚠️ 条件固定：分辨率钉 1600×900、抓图前等 `frame_post_draw`、页面顺序固定。
## ⚠️ 读数**不经过产品代码的转述**：一律直接问 `AudioServer`。

const OUT_FALLBACK := "user://"

var _tag := "run"
var _out := "res://"
var _menu: MainMenu = null
var _bad := 0
var _report: Array[String] = []


func _ready() -> void:
	_parse_args()
	if DisplayServer.get_name() == "headless":
		push_error("volumeprobe 必须真渲染运行 —— 去掉 --headless 再来"
			+ "（无头既不产生像素也不产生采样）。")
		get_tree().quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	await _run()
	print("[volumeprobe] 完：tag=%s out=%s 异常=%d" % [_tag, _out, _bad])
	get_tree().quit(1 if _bad > 0 else 0)


func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"--tag": _tag = kv[1]
			"--out": _out = kv[1]


func _run() -> void:
	await _settle()
	await _settle()
	# ① 总线树（真引擎）
	_dump_bus_tree()
	# ② 三条通道的档位读数（001 = 100% / 050 = 50% / 000 = 0%）
	_dump_levels()
	# ③ 交叉串扰矩阵
	_dump_crosstalk()
	# ④ 真静音：同一条正弦，100% vs 0%
	await _capture_ab()
	# ⑤ 截图
	await _shots()


# ============================================================ ① 总线树

func _dump_bus_tree() -> void:
	Settings.apply_audio()
	var n := AudioServer.bus_count
	print("[volumeprobe] ---- ① 真引擎总线树（AudioServer，bus_count=%d）----" % n)
	for i in n:
		var name := AudioServer.get_bus_name(i)
		var send := AudioServer.get_bus_send(i)
		print("[volumeprobe]    [%d] %-8s send=%-8s vol=%.2f dB  mute=%s  linear=%.4f" % [
			i, name, send, AudioServer.get_bus_volume_db(i),
			str(AudioServer.is_bus_mute(i)), AudioServer.get_bus_volume_linear(i)])
	# 断言：六条细分必须挂在 SFX 下面（顺序反了会静默挂到 Master —— 那正是最隐蔽的坑）
	for b: String in [Settings.BUS_VULCAN, Settings.BUS_SABER, Settings.BUS_RIFLE,
			Settings.BUS_FUNNEL, Settings.BUS_ALARM, Settings.BUS_ENGINE]:
		var idx := AudioServer.get_bus_index(b)
		if idx < 0:
			_bad += 1
			print("[volumeprobe]   !! 总线不存在：%s" % b)
			continue
		var s := AudioServer.get_bus_send(idx)
		if s != Settings.BUS_SFX:
			_bad += 1
			print("[volumeprobe]   !! %s 的 send 是 %s（应为 %s）" % [b, s, Settings.BUS_SFX])


# ============================================================ ② 档位读数

func _dump_levels() -> void:
	print("[volumeprobe] ---- ② 八条滑条 × 三档（直接读 AudioServer）----")
	print("[volumeprobe]    %-22s %-8s %10s %6s %10s" % ["滑条", "总线", "100% dB", "mute", "0% dB"])
	for b: String in Settings.BUS_ORDER:
		Settings.set_volume(b, 1.0)
	Settings.apply_audio()
	var hi := {}
	for b: String in Settings.BUS_ORDER:
		var i := AudioServer.get_bus_index(b)
		hi[b] = [AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)]
	# 100% ⇒ 必须是 0.00 dB / 不静音（"默认态声音与改动前逐位一致"这条不变量的真机面）
	for b: String in Settings.BUS_ORDER:
		Settings.set_volume(b, 0.0)
	Settings.apply_audio()
	for b: String in Settings.BUS_ORDER:
		var i := AudioServer.get_bus_index(b)
		var label := _label_of(b)
		var lo_db := AudioServer.get_bus_volume_db(i)
		var lo_mute := AudioServer.is_bus_mute(i)
		print("[volumeprobe]    %-22s %-8s %10.2f %6s %10.2f  lo_mute=%s" % [
			label, b, float(hi[b][0]), str(hi[b][1]), lo_db, str(lo_mute)])
		if absf(float(hi[b][0])) > 0.001 or bool(hi[b][1]):
			_bad += 1
			print("[volumeprobe]   !! %s 在 100%% 时不是 0.00 dB / 不静音" % b)
		if not lo_mute:
			_bad += 1
			print("[volumeprobe]   !! %s 在 0%% 时没有真静音（0%% 必须是 mute，不是 -80 dB 硬凑）" % b)
	# 50% 档：dB 必须 = 20*log10(0.5) = -6.02
	Settings.set_volume(Settings.BUS_VULCAN, 0.5)
	Settings.apply_audio()
	var vi := AudioServer.get_bus_index(Settings.BUS_VULCAN)
	print("[volumeprobe]    50%% 档：VULCAN = %.4f dB（期望 %.4f）" % [
		AudioServer.get_bus_volume_db(vi), 20.0 * log(0.5) / log(10.0)])
	# 复原
	for b: String in Settings.BUS_ORDER:
		Settings.set_volume(b, 1.0)
	Settings.apply_audio()


# ============================================================ ③ 交叉串扰

func _dump_crosstalk() -> void:
	print("[volumeprobe] ---- ③ 交叉串扰矩阵：把某一根拉到 0，看**别的**有没有被带着动 ----")
	var base := {}
	for b: String in Settings.BUS_ORDER:
		var i := AudioServer.get_bus_index(b)
		base[b] = [AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)]
	var dirty := 0
	for x: String in Settings.BUS_ORDER:
		Settings.set_volume(x, 0.0)
		Settings.apply_audio()
		var moved: Array[String] = []
		for b: String in Settings.BUS_ORDER:
			var i := AudioServer.get_bus_index(b)
			var now := [AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)]
			if b == x:
				continue
			if absf(float(now[0]) - float(base[b][0])) > 0.001 or now[1] != base[b][1]:
				moved.append(b)
		Settings.set_volume(x, 1.0)
		Settings.apply_audio()
		if moved.size() > 0:
			dirty += 1
			_bad += 1
		print("[volumeprobe]    拉 0 的：%-8s  ⇒ 被带着动的别的总线：%s" % [
			x, "无" if moved.is_empty() else str(moved)])
	print("[volumeprobe]    串扰行数 = %d（必须 0）" % dirty)


# ============================================================ ④ 真静音 A/B

## 同一条 440 Hz 正弦送进被测总线，滑条 100% 与 0% 各捕获一次。
##
## ## ⚠️⚠️ 捕获点为什么必须在 **Master**（★63-23 真机实测，与"想当然"相反）
## 第一版我把捕获挂在**被测总线自己**身上，结果 0% 那一档仍然读到 `rms = 0.351`
## —— 看起来像"0% 没静音"，其实是**捕获点选错了**：
## Godot 4.7.1 里，挂在某条总线上的 `AudioEffectCapture` 看到的是该总线的
## **推子前**信号（总线音量是在它混进父总线时才施加的）。
## 而挂在 **Master** 上时看到的是**推子后**的最终混音 ⇒ 0% 那一档读到
## `rms = 0.000000`（精确零位）。
## ⇒ 判据一律读 Master；本总线那一列只留作"证明源确实在发声"的对照。
func _capture_ab() -> void:
	print("[volumeprobe] ---- ④ 真静音 A/B（同源正弦，100% vs 0%）----")
	print("[volumeprobe]    ⚠️ 捕获点 = Master（挂被测总线自己身上是推子前，读不出静音）")
	var a := await _capture_rms(Settings.BUS_VULCAN, 1.0)
	var b := await _capture_rms(Settings.BUS_VULCAN, 0.0)
	print("[volumeprobe]    VULCAN 100pct: bus_rms=%.6f  master_rms=%.6f" % [
		float(a[2]), float(a[0])])
	print("[volumeprobe]    VULCAN   0pct: bus_rms=%.6f  master_rms=%.6f" % [
		float(b[2]), float(b[0])])
	if int(a[1]) <= 0 or int(b[1]) <= 0:
		# 没有采样 ⇒ 本机音频捕获不可用 ⇒ **不算异常**，但要明说降级
		print("[volumeprobe]    ⚠️ 捕获不到采样（本机音频后端不出样本）⇒ 本段降级为"
			+ "「接线事实」，声音大小以 ②③ 的 AudioServer 读数为准。")
		Settings.set_volume(Settings.BUS_VULCAN, 1.0)
		Settings.apply_audio()
		return
	if float(a[0]) <= 1e-5:
		_bad += 1
		print("[volumeprobe]   !! 100pct 时 Master 也捕获不到声音 ⇒ 这次 A/B 是空的，不能当证据")
	if float(b[0]) > 1e-6:
		_bad += 1
		print("[volumeprobe]   !! 0pct 时 Master 仍有采样（rms=%.6f）⇒ 不是真静音" % float(b[0]))
	# ---- 八条滑条全过一遍：每条都能把声音真的掐死吗 ----
	print("[volumeprobe]    ---- 八条滑条各自 A/B（Master 捕获 rms）----")
	for bus: String in Settings.BUS_ORDER:
		var hi := await _capture_rms(bus, 1.0)
		var lo := await _capture_rms(bus, 0.0)
		var ok := float(hi[0]) > 1e-5 and float(lo[0]) <= 1e-6
		if not ok:
			_bad += 1
		print("[volumeprobe]      %-8s 100pct rms=%.6f → 0pct rms=%.6f   %s" % [
			bus, float(hi[0]), float(lo[0]), "OK" if ok else "!! 不成立"])
	Settings.set_volume(Settings.BUS_VULCAN, 1.0)
	Settings.apply_audio()


## 返回 `[master_rms, master_used, bus_rms, bus_used]`。
##
## ⚠️⚠️ **每次测量前先把全部滑条复位到 100%**（★63-23 实测踩到）：
## 第一版没有复位，量完 `SFX` 的 0% 档后 `SFX` 一直是**静音**的，
## 于是后面六条**挂在 SFX 下面**的细分总线全军覆没 ——
## 100% 档也读到 `rms = 0.000000`，六行全是"不成立"。
## 那看着像"细分通道坏了"，其实是**上一次测量的残留状态**（被测之外的一切没钉死）。
func _capture_rms(bus: String, vol: float) -> Array:
	for b: String in Settings.BUS_ORDER:
		Settings.set_volume(b, 1.0)
	Settings.set_volume(bus, vol)
	Settings.apply_audio()
	var idx := AudioServer.get_bus_index(bus)
	var midx := AudioServer.get_bus_index("Master")
	if idx < 0 or midx < 0:
		return [0.0, 0, 0.0, 0]
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 1.0
	AudioServer.add_bus_effect(idx, cap)
	var mcap := AudioEffectCapture.new()
	mcap.buffer_length = 1.0
	AudioServer.add_bus_effect(midx, mcap)

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 44100.0
	gen.buffer_length = 1.0
	var player := AudioStreamPlayer.new()
	player.stream = gen
	player.bus = bus
	add_child(player)
	player.play()
	await get_tree().process_frame
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		print("[volumeprobe]    （拿不到 GeneratorPlayback，跳过本档）")
		_teardown(player, idx, midx)
		return [0.0, 0, 0.0, 0]

	var want := 8192
	var buf := PackedVector2Array()
	buf.resize(want)
	var phase := 0.0
	var inc := TAU * 440.0 / 44100.0
	for i in want:
		var s := sin(phase) * 0.5
		phase = fmod(phase + inc, TAU)
		buf[i] = Vector2(s, s)
	# 推两次（第一次可能落在还没开的缓冲上限上）
	pb.push_buffer(buf)
	await get_tree().process_frame
	pb.push_buffer(buf)

	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 320:
		await get_tree().process_frame

	var bus_rms := _drain(cap)
	var master_rms := _drain(mcap)
	_teardown(player, idx, midx)
	await get_tree().process_frame
	return [master_rms[0], master_rms[1], bus_rms[0], bus_rms[1]]


## 取走捕获缓冲里现有的全部样本，返回 `[rms, 样本数]`。
func _drain(cap: AudioEffectCapture) -> Array:
	var n := cap.get_frames_available()
	if n <= 0:
		return [0.0, 0]
	var got := cap.get_buffer(n)
	var acc := 0.0
	var used := 0
	for v: Vector2 in got:
		acc += v.x * v.x + v.y * v.y
		used += 2
	if used <= 0:
		return [0.0, 0]
	return [sqrt(acc / float(used)), used]


func _teardown(player: AudioStreamPlayer, idx: int, midx: int) -> void:
	player.stop()
	player.queue_free()
	# 从**末尾**摘：本函数只加了一个，摘最后一个就是它自己
	if AudioServer.get_bus_effect_count(idx) > 0:
		AudioServer.remove_bus_effect(idx, AudioServer.get_bus_effect_count(idx) - 1)
	if AudioServer.get_bus_effect_count(midx) > 0:
		AudioServer.remove_bus_effect(midx, AudioServer.get_bus_effect_count(midx) - 1)


# ============================================================ ⑤ 截图

func _shots() -> void:
	await _await_focus()
	_menu = MainMenu.new()
	add_child(_menu)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_menu.set_process(true)
	_menu.open_menu(0.0)
	await _settle()
	_menu.set("active", true)
	await _settle()
	_menu.set_process(false)
	_menu.set("_time", 0.0)

	# ---- (a) 设置页主屏：光标落在「音量细分」那一行 ----
	var vi := -1
	for i in MainMenu.SETTING_ROWS.size():
		if str(MainMenu.SETTING_ROWS[i].get("key", "")) == "volume":
			vi = i
	if vi < 0:
		_bad += 1
		print("[volumeprobe] !! 设置页里找不到 volume 行")
	else:
		_menu.set("stage", MainMenu.Stage.SETTINGS)
		_menu.set("settings_sub", MainMenu.SET_SUB_MAIN)
		_menu.set("setting_row", vi)
		_menu.queue_redraw()
		await _settle()
		await _shot("_vp_%s_set_main.png" % _tag)
		print("[volumeprobe] 设置页主屏：setting_row=%d key=volume 共 %d 行" % [
			vi, MainMenu.SETTING_ROWS.size()])

	# ---- (b) 音量细分页：默认（全 100%）----
	for b: String in Settings.BUS_ORDER:
		Settings.set_volume(b, 1.0)
	Settings.apply_audio()
	_menu.set("stage", MainMenu.Stage.SETTINGS)
	_menu.set("settings_sub", MainMenu.SET_SUB_VOLUME)
	_menu.set("volume_row", 0)
	_menu.queue_redraw()
	await _settle()
	await _shot("_vp_%s_vol_default.png" % _tag)

	# ---- (c) 音量细分页：混搭（含两条 0% = 真静音）----
	Settings.set_volume(Settings.BUS_BGM, 0.65)
	Settings.set_volume(Settings.BUS_SFX, 1.0)
	Settings.set_volume(Settings.BUS_VULCAN, 0.45)
	Settings.set_volume(Settings.BUS_SABER, 0.0)
	Settings.set_volume(Settings.BUS_RIFLE, 0.85)
	Settings.set_volume(Settings.BUS_FUNNEL, 1.0)
	Settings.set_volume(Settings.BUS_ALARM, 0.0)
	Settings.set_volume(Settings.BUS_ENGINE, 0.30)
	Settings.apply_audio()
	_menu.set("volume_row", 3)
	_menu.queue_redraw()
	await _settle()
	await _shot("_vp_%s_vol_mixed.png" % _tag)

	# ---- (d) 设置页主屏**高亮回到第一行**（对照：证明这一页没被新行挤坏）----
	_menu.set("settings_sub", MainMenu.SET_SUB_MAIN)
	_menu.set("setting_row", 0)
	_menu.queue_redraw()
	await _settle()
	await _shot("_vp_%s_set_main_top.png" % _tag)

	# 复原默认（别把探针改过的值留进玩家的存档）
	for b: String in Settings.BUS_ORDER:
		Settings.set_volume(b, 1.0)
	Settings.apply_audio()


func _label_of(bus: String) -> String:
	for r: Dictionary in MainMenu.volume_rows():
		if str(r["bus"]) == bus:
			return str(r["label"])
	return bus


# ============================================================ 工具

func _await_focus() -> void:
	for i in 180:
		if DisplayServer.window_is_focused():
			return
		await get_tree().process_frame
	print("[volumeprobe] 环境警告：180 帧内窗口仍未获得焦点（有别的窗口在抢？）")


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		push_error("取画面失败：get_viewport().get_texture() 为空")
		_bad += 1
		return
	var img := tex.get_image()
	if img == null:
		push_error("取画面失败：get_image() 为空")
		_bad += 1
		return
	var path := _out + suffix
	var err := img.save_png(path)
	if err != OK:
		push_error("存图失败 err=%d → %s" % [err, path])
		_bad += 1
		return
	print("[volumeprobe] 图 → %s (%d×%d)" % [path, img.get_width(), img.get_height()])
