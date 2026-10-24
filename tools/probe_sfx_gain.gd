extends Node
## 真机实测「武器音效 +25%」**真的进了混音**（不是"代码里写了 1.9382"）。
##
## ⚠️ 必须**不加 `--headless`**：无头下音频驱动是 Dummy、混音根本不推进，
##    `AudioEffectCapture` 一个采样都抓不到。
##
## 跑法：
##   Godot_v4.7.1-stable_win64_console.exe --path . res://tools/probe_sfx_gain.tscn
##
## ## 判据（同一台机器、同一段素材的双路对照）
##
##   路 A：`Audio.play_self("beam_rifle", -4.0)` —— 走 `SoundBank.GAIN_DB`
##   路 B：自己造播放器、`volume_db = -4.0` —— **标称音量一模一样**，但绕开增益表
##
## ⇒ A/B 的**振幅比应该 ≈ 1.25**。三个失败态的读数是互相区分的：
##   · A/B ≈ 1.00  ⇒ 表加了没人读（增益没生效）
##   · A/B ≈ 1.25  ⇒ 正确
##   · A/B ≈ 17.8  ⇒ 把「25%」误写成了 +25 dB（要削顶的）
##
## 第二条独立证据是 SFX 总线的**峰值表**（dB 域），两次差值应 ≈ +1.9382 dB。
##
## ⚠️ 测量期间会把 SFX 总线临时按到 0 dB / 不静音，
##    **只动 `AudioServer`、不写配置**（不碰玩家存档），结尾原样还回去。

const SOUND := "beam_rifle"
const BASE_DB := -4.0
## 取固定的一段窗口来算 RMS：从"清空缓冲"那一刻起的第 1.0 秒。
const WIN_SEC := 1.0
## 播放后等多久开始读缓冲。要 > `WIN_SEC`，否则缓冲里还没攒够一个完整窗口。
const LEAD_SEC := 1.6
## 两次测量之间静一静，别让上一次的尾巴串进下一次。
const GAP_SEC := 0.9

var _cap: AudioEffectCapture
var _bus := -1
var _bus_db := 0.0
var _bus_mute := false


func _ready() -> void:
	# 在 `_ready()` 里直接 await 会撞"节点还没进树/父节点正忙"，延后一帧起步。
	_boot.call_deferred()


func _boot() -> void:
	_bus = Settings.bus_index(Settings.BUS_SFX)
	if _bus < 0:
		print("GAIN FAIL 找不到 SFX 总线（Settings 还没建）")
		_quit()
		return
	# 把"玩家音量"从测量里剔掉：只动 AudioServer，**不写配置**
	_bus_db = AudioServer.get_bus_volume_db(_bus)
	_bus_mute = AudioServer.is_bus_mute(_bus)
	AudioServer.set_bus_mute(_bus, false)
	AudioServer.set_bus_volume_db(_bus, 0.0)
	Audio.play_bgm(Audio.Bgm.NONE, 0.0)     # BGM 别混进来
	await _wait_sec(0.3)

	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 4.0
	AudioServer.add_bus_effect(_bus, _cap)

	print("GAIN mix_rate=%d sound=%s base_db=%.4f win=%.1fs"
		% [AudioServer.get_mix_rate(), SOUND, BASE_DB, WIN_SEC])

	var a := await _measure(true, SOUND, BASE_DB)
	var b := await _measure(false, SOUND, BASE_DB)
	var want_db := SoundBank.gain_db(SOUND)
	print("GAIN path=A(走增益表)     player_db=%+.4f rms=%.6f peak=%.2f dB"
		% [a["db"], a["rms"], a["peak"]])
	print("GAIN path=B(绕开增益表)   player_db=%+.4f rms=%.6f peak=%.2f dB"
		% [b["db"], b["rms"], b["peak"]])

	var ratio: float = float(a["rms"]) / maxf(float(b["rms"]), 1e-9)
	var expect: float = pow(10.0, want_db / 20.0)
	print("GAIN rms_ratio=%.4f  expected=%.4f  err=%+.2f%%"
		% [ratio, expect, (ratio / expect - 1.0) * 100.0])
	print("GAIN peak_delta=%.2f dB  expected=%+.4f dB"
		% [float(a["peak"]) - float(b["peak"]), want_db])

	# ---- 定位通道（play_3d）：真机**读回**它建的播放器音量 ----
	# RMS 量不了：3D 有距离衰减，会和"增益"混在一起。振幅证据由上面 A/B 承担，
	# 这一条只证明"那条通道也读了表"。
	var p3 := _play_3d_and_get("beam_saber", -3.0)
	if p3 != null:
		print("GAIN path=play_3d(beam_saber) player_db=%+.4f  expected=%+.4f"
			% [(p3 as AudioStreamPlayer3D).volume_db,
			-3.0 + SoundBank.gain_db("beam_saber")])
	else:
		print("GAIN path=play_3d 取不到播放器")

	# ---- 没被点名的音效必须分毫不动（对照组）----
	var pv := _play_self_and_get("vulcan", -4.0)
	if pv != null:
		print("GAIN path=对照(vulcan) player_db=%+.4f  expected=-4.0000"
			% [(pv as AudioStreamPlayer).volume_db])

	# 原样还回去
	AudioServer.set_bus_volume_db(_bus, _bus_db)
	AudioServer.set_bus_mute(_bus, _bus_mute)
	_quit()


## 量一次：返回 {rms, db, peak}。`db` 是**播放器上真实的 `volume_db`**（不是算出来的）。
func _measure(use_api: bool, name: String, vol_db: float) -> Dictionary:
	# 清空缓冲：否则这一次会把上一次的尾巴也量进去
	if _cap.get_frames_available() > 0:
		_cap.clear_buffer()
	# 先读一次峰值表，把它清零
	AudioServer.get_bus_peak_volume_left_db(_bus, 0)

	var player: Node = null
	if use_api:
		player = _play_self_and_get(name, vol_db)
	else:
		player = _play_manual(name, vol_db)

	# 峰值表**逐帧轮询取最大**：单次读一个瞬态完全不可靠 —— 实测同一条路
	# 换个时机能差 3 dB（会把「+1.94 dB」读成「-1.54 dB」）。
	# 轮询窗口与 RMS 窗口都从**播放那一刻**起算 ⇒ 两条路取的是同一个时间集合，
	# 峰值之差就正好是增益本身。
	var peak := -80.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(LEAD_SEC * 1000.0):
		peak = maxf(peak, AudioServer.get_bus_peak_volume_left_db(_bus, 0))
		await get_tree().process_frame

	var buf := _cap.get_buffer(_cap.get_frames_available())
	var want := int(WIN_SEC * float(AudioServer.get_mix_rate()))
	var n := mini(want, buf.size())
	var sum := 0.0
	for i in n:
		var v: Vector2 = buf[i]
		sum += v.x * v.x + v.y * v.y
	var rms := sqrt(sum / maxf(1.0, float(n) * 2.0))

	var db := 0.0
	if player is AudioStreamPlayer:
		db = (player as AudioStreamPlayer).volume_db
	elif player is AudioStreamPlayer3D:
		db = (player as AudioStreamPlayer3D).volume_db
	if player != null and is_instance_valid(player):
		player.queue_free()
	await _wait_sec(GAP_SEC)
	return {"rms": rms, "db": db, "peak": peak, "frames": n}


## 路 A：走工程自己的入口（增益表在这里生效）。
## 按"调用前后的子节点数量差"找播放器 —— 不能靠名字猜（`Audio` 自己挂着 `Bgm0`/`Bgm1`）。
func _play_self_and_get(name: String, vol_db: float) -> Node:
	var before := Audio.get_child_count()
	Audio.play_self(name, vol_db)
	var kids := Audio.get_children()
	for i in range(before, kids.size()):
		if kids[i] is AudioStreamPlayer:
			return kids[i]
	return null


## 路 B：**对照组** —— 标称音量与路 A 完全相同，但自己造播放器 ⇒ 绕开 `SoundBank.GAIN_DB`。
## 素材取同一个流实例（`Audio.get_stream_for()` 有缓存）⇒ 两路除增益外没有任何差别。
func _play_manual(name: String, vol_db: float) -> Node:
	var p := AudioStreamPlayer.new()
	p.stream = Audio.get_stream_for(name)
	p.volume_db = vol_db
	p.bus = Settings.BUS_SFX
	add_child(p)
	p.play()
	return p


func _play_3d_and_get(name: String, vol_db: float) -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var before := scene.get_child_count()
	Audio.play_3d(name, Vector3.ZERO, vol_db)
	var kids := scene.get_children()
	for i in range(before, kids.size()):
		if kids[i] is AudioStreamPlayer3D:
			return kids[i]
	return null


## 按**墙钟**等秒数 —— 别按帧数：窗口跑 vsync 时"等 45 帧"可能只走了 0.27 s。
func _wait_sec(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	var ms := int(s * 1000.0)
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


func _quit() -> void:
	get_tree().quit()
