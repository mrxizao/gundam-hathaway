extends Node
## ★63-25 真机探针：**主菜单曲三首随机循环**。
##
## 需求原文（用户 2026-10-08）：「EARth 和 Snooze 添加到主菜单歌曲内，
## 和现在的主菜单歌曲三首随机循环播放」。
##
## ## 本探针读七件事
## ① 结构：菜单池就是三首（`mobius` / `earth_nt` / `snooze`），三首素材都在盘上，
##    而且**一首都没混进战斗轮换池**；
## ② 真机播放：菜单曲**真的在解码**（`get_playback_position()` 推进），而且**不循环**；
## ③ ⭐ **全链路轮换**：往播放器上装一段 **0.1 秒的真 WAV**，让它**自然放完** ——
##    观察 `finished` 真的来了、并且自动换到下一首。
##    ⚠️ 与 ④ 的分工：④ 是**手动** `finished.emit()`（只验轮换**数学**），
##    ③ 是**让引擎自己发**这个信号（验**接线真的通到了引擎**）。
##    少了 ③，"菜单到底会不会换曲"就只有数学、没有链路。
##
##    ⚠️⚠️ **★63-25 实测修正 ★63-22 的口径**：★63-22 记的是「headless 是 Dummy 音频
##    驱动、混音不推进 ⇒ 解码位置推进只能真机证」。**在本机不成立** ——
##    本探针**在 `--headless` 下**跑，② 段就读到 `0.999 → 2.416 s`（真的在推进），
##    ③ 段那段 0.1 秒的 WAV 也真的自然放完、`finished` 真的自己来了。
##    ⇒「位置推进」与「自然放完会发 finished」这两条**不是真机专有证据**，
##    无头冒烟里就能拿到（真机跑只是多一份独立旁证 + 出图）。
##    形状与 ★63-20→★63-22 那条教训一样：**先实测，再写口径**。
## ④ 轮换数学：连抽 9 次（3 轮）⇒ 每首恰好 3 次、没有第 4 首、没有连着两首相同；
## ⑤ ⭐ **共享资源没被写穿**：`senkou` 是"同一份资源被两种 loop 值用到"的**真实**场景
##    （对战战斗曲 = 不循环 / 太平洋结算曲 = **循环** / 关卡锁曲 = **循环**）——
##    交替播三种用途，读**共享资源**必须一直是 `false`。
##    写穿的后果：对战打完一首卡住、再也不换曲，而且**一行报错都没有**（★63-20 栽过）。
## ⑥ 试听与「压低菜单 BGM」在菜单曲轮换之后仍然成立（★63-22 的两条机制没被打破）；
## ⑦ 存档：跑前记 md5，跑完必须一致（本探针**不改**任何玩家设置）。
##
## ## 跑法（真机出图；**不加** `--headless`）
##   Godot_v4.7.1-stable_win64_console.exe --path <工程> \
##       res://tools/_r63_25_menu_bgm.tscn -- <输出目录>
##
## ⚠️ 真机会**真的出声**（菜单曲 + 一次试听）。探针末尾会把它们停掉。

const SHOT_W := 1600
const SHOT_H := 900

## ③ 用的"极短流"长度（秒）。够长到能被真的解码启动，够短到能在一次探针里放完。
const SHORT_SEC := 0.1

## ④ 抽多少次（3 轮 × 3 首）。
const ROTATE_N := 9

var main: Node
var out_dir := "user://shots_r63_25_menu"
var _fails := 0
var _cfg := ""
var _cfg_md5 := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	_cfg = ProjectSettings.globalize_path("user://settings.cfg")
	_cfg_md5 = _md5(_cfg)

	print("========== ★63-25 主菜单曲 · 真机探针 ==========")
	print("ENV 显示驱动=%s  存档=%s  md5前=%s" % [
		DisplayServer.get_name(), _cfg, _cfg_md5])

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

	# ============================================================ ① 结构
	var pool: Array = SoundBank.MENU_TRACKS
	print("POOL 菜单池 = %s（%d 首）" % [str(pool), pool.size()])
	_check(pool.size() == 3, "菜单池 = 三首（用户原话「三首随机循环播放」）")
	for k: String in pool:
		_check(SoundBank.BGM.has(k), "菜单曲 %s 在 BGM 表里" % k)
		_check(ResourceLoader.exists(SoundBank.bgm_path(k)),
			"菜单曲 %s 素材在盘上（%s）" % [k, SoundBank.bgm_path(k)])
	for k: String in ["mobius", "earth_nt", "snooze"]:
		_check(pool.has(k), "★63-25 点名的那一首在池里：%s" % k)
	# ⚠️ 反向：混进战斗轮换池 ⇒ 玩家在战斗里被随机放到一首本不该出现在战斗里的曲子，
	# 而且**不报错**（与 `OPT_IN_BATTLE_TRACKS` 那条纪律同族）。
	for k: String in pool:
		_check(not SoundBank.BATTLE_TRACKS.has(k), "菜单曲 %s 不在对战轮换池里" % k)
		_check(not SoundBank.STORY_BATTLE_TRACKS.has(k), "菜单曲 %s 不在剧情轮换池里" % k)
	# 双用途是**有意**的（EARth / Snooze 既是菜单曲、也是玩家的战斗自选曲）。
	_check(SoundBank.is_battle_pick("earth_nt") and SoundBank.is_battle_pick("snooze"),
		"EARth / Snooze 同时是合法战斗自选值（双用途是有意的，别顺手删掉）")
	_check(not SoundBank.is_battle_pick("mobius"), "mobius 不是合法战斗自选值（它只属于菜单）")

	# ============================================================ ② 真机播放
	Audio.set_story_mode(false)
	Audio.lock_battle_track("")
	Audio.request_battle_open("")
	Audio.play_bgm(Audio.Bgm.MENU, 0.0)
	await _frames(20)
	var p0 := _active_player()
	var t0 := Audio.current_bgm_track()
	var pos_a := p0.get_playback_position()
	await _wait_sec(1.6)
	var pos_b := p0.get_playback_position()
	print("PLAY 曲=%s  播放器=%s  playing=%s  loop=%s  流长=%.2f s" % [
		t0, p0.name, str(p0.playing), str(Audio._loop_of(p0.stream)), p0.stream.get_length()])
	print("PLAY 解码位置 %.3f → %.3f s" % [pos_a, pos_b])
	_check(pool.has(t0), "真放的第一首取自菜单池（%s）" % t0)
	_check(p0.playing, "播放器在响")
	_check(not Audio._loop_of(p0.stream),
		"★★ 菜单曲**不循环**（循环的曲子永远不发 finished，三首轮换会彻底失效）")
	_check(pos_b > pos_a + 0.5,
		"★★ 解码位置真的在推进（%.3f → %.3f s）—— 真的在解码，不是「挂在那儿不报错」" % [pos_a, pos_b])
	await _shot("01_menu_playing")

	# ============================================================ ③ 真机全链路轮换
	var wav := _tiny_wav(SHORT_SEC)
	var before := Audio.current_bgm_track()
	print("SHORT 往 %s 装一段 %.2f 秒的真 WAV（len=%.3f s），等它**自然放完** ……" % [
		p0.name, SHORT_SEC, wav.get_length()])
	p0.stream = wav
	p0.volume_db = 0.0
	p0.play()
	await _wait_sec(0.9)
	var after := Audio.current_bgm_track()
	print("SHORT %s → %s" % [before, after])
	_check(after != before,
		"★★★ 全链路：菜单曲**自然放完** ⇒ finished 由引擎自己触发 ⇒ 自动换下一首（%s → %s）" % [before, after])
	_check(pool.has(after), "……而且换到的仍然取自菜单池（%s）" % after)

	# ============================================================ ④ 轮换数学（3 轮）
	#
	# ⚠️ 必须**先把洗牌袋清空**再从空袋开始数：③ 段刚抽过两首，袋子是"半满"的，
	# 从半满的袋子连着抽 9 次会横跨 4 个**部分**轮 ⇒ 计数不是 3/3/3
	#（★63-25 第一次无头冒烟就是这么红的：`{earth_nt:4, snooze:2, mobius:3}`）。
	# 那不是产品坏了，是"从中间开始数轮数"这件事**本身没意义**。
	# 清空之后 9 次 = 恰好 3 整轮（与 `suite_audio._menu_rotation` 用空 queue 同源）。
	Audio._menu_bag.clear()
	Audio._last_menu_track = ""
	Audio.stop_bgm(0.0)                 # `_bgm_kind` 回到 NONE ⇒ 下面那次 play_bgm **必抽**
	await _frames(6)
	Audio.play_bgm(Audio.Bgm.MENU, 0.0)  # 空袋第 1 抽
	await _frames(8)
	var seen: Array = [Audio.current_bgm_track()]
	for i in ROTATE_N - 1:
		_active_player().finished.emit()
		await _frames(4)
		seen.append(Audio.current_bgm_track())
	var tally := {}
	for s: String in seen:
		tally[s] = int(tally.get(s, 0)) + 1
	print("ROTATE 抽 %d 次 ⇒ %s" % [ROTATE_N, str(seen)])
	print("ROTATE 计数=%s  （期望每首恰好 %d 次、没有第 4 首）" % [str(tally), ROTATE_N / 3])
	var ok_each := true
	var ok_pool := true
	var repeat_next := false
	for i in seen.size():
		if not pool.has(str(seen[i])):
			ok_pool = false
		if i > 0 and str(seen[i]) == str(seen[i - 1]):
			repeat_next = true
	for k: String in pool:
		if int(tally.get(k, 0)) != ROTATE_N / 3:
			ok_each = false
	_check(seen.size() == ROTATE_N, "真的抽了 %d 次" % ROTATE_N)
	_check(ok_pool, "只出现菜单池里的曲子，**没有第 4 首**（池子没被写宽）")
	_check(ok_each, "每首**恰好轮到 %d 次**（一轮三首各一次 = 真正的「轮流随机」）" % (ROTATE_N / 3))
	_check(not repeat_next, "轮换不会连着放同一首（含跨轮边界）")
	await _shot("02_after_rotate")

	# ============================================================ ⑤ 共享资源没被写穿
	#
	# ⚠️ 前提必须**显式**写出来，否则这一节会变成恒真的废话：
	#   · 结算曲 == `senkou`（太平洋 + 这一局没用过閃光）—— 它**同时**是对战战斗曲，
	#     "同一份资源被两种 loop 值用到"这个冲突场景才真的成立。
	Game.active_map = MapDef.pacific()
	Audio.set_story_mode(false)
	Audio._senkou_used = false
	Audio.request_battle_open("")
	Audio.lock_battle_track("")
	Audio.play_bgm(Audio.Bgm.RESULT, 0.0)
	await _frames(12)
	var r_track := Audio.current_bgm_track()
	var r_stream := _active_stream()
	print("RESULT 曲=%s  播放器手上 loop=%s  共享资源 loop=%s" % [
		r_track, str(Audio._loop_of(r_stream)),
		str(Audio._loop_of(load(SoundBank.bgm_path(r_track))))])
	_check(r_track == "senkou",
		"（前提）太平洋结算曲 = senkou —— 它**同时**是对战战斗曲，本节才不是废话")
	_check(Audio._loop_of(r_stream), "结算曲在**播放器手上那一份**是循环的（单曲循环）")
	_check(not Audio._loop_of(load(SoundBank.bgm_path("senkou"))),
		"★★ 但**共享资源**仍是不循环的 —— `play_bgm()` 改的是私有副本，没写穿")

	# 反过来：锁曲 senkou ⇒ 战斗曲**也要**循环（整关就这一首），同样不许写穿
	Audio.lock_battle_track("senkou")
	Audio.play_bgm(Audio.Bgm.BATTLE, 0.0)
	await _frames(12)
	print("BATTLE 锁曲 senkou ⇒ 播放器手上 loop=%s  共享资源 loop=%s" % [
		str(Audio._loop_of(_active_stream())),
		str(Audio._loop_of(load(SoundBank.bgm_path("senkou"))))])
	_check(Audio.current_bgm_track() == "senkou", "锁曲生效（%s）" % Audio.current_bgm_track())
	_check(Audio._loop_of(_active_stream()), "锁曲时战斗曲是循环的（一关从头到尾就这一首）")
	_check(not Audio._loop_of(load(SoundBank.bgm_path("senkou"))),
		"★★ 共享资源**依然**是不循环的（结算曲刚把它当循环用过，没被带过去）")

	# 再切回"不循环"的用途：对战轮换
	Audio.lock_battle_track("")
	Audio.play_bgm(Audio.Bgm.BATTLE, 0.0)
	await _frames(12)
	var b2 := Audio.current_bgm_track()
	print("BATTLE 对战轮换 ⇒ 曲=%s  播放器手上 loop=%s  共享资源 loop=%s" % [
		b2, str(Audio._loop_of(_active_stream())),
		str(Audio._loop_of(load(SoundBank.bgm_path("senkou"))))])
	_check(not Audio._loop_of(_active_stream()), "对战轮换的战斗曲不循环（%s）" % b2)
	_check(not Audio._loop_of(load(SoundBank.bgm_path("senkou"))), "……共享资源还是 false")
	Audio.stop_bgm(0.0)

	# ============================================================ ⑥ 压低 + 试听
	Audio.play_bgm(Audio.Bgm.MENU, 0.0)
	await _frames(12)
	Audio.set_menu_duck(Audio.MENU_DUCK_DB)
	await _wait_sec(0.9)
	var ducked := _active_player().volume_db
	print("DUCK 压低后播放器 volume_db=%.2f dB（目标 %.1f）" % [ducked, Audio.MENU_DUCK_DB])
	_check(absf(ducked - Audio.MENU_DUCK_DB) < 0.6,
		"「压低菜单 BGM」仍然落到播放器上（%.2f dB）—— ★63-22 的机制没被这次改动打破" % ducked)

	Audio.preview_bgm("earth_nt")
	await _wait_sec(2.5)
	var pv := Audio.preview_volume_db()
	print("PREVIEW 试听 EARth 2.5 s 后 volume_db=%.2f  正在试听=%s  菜单曲=%s" % [
		pv, _q(Audio.preview_track()), _q(Audio.current_bgm_track())])
	_check(Audio.preview_track() == "earth_nt", "试听打开的是 EARth")
	_check(pv > -1.0,
		"★★ 试听渐入到满音量（%.2f dB）—— 独立通道没被菜单曲轮换搅乱" % pv)
	await _shot("03_preview_earth")
	Audio.stop_preview(0.0)
	Audio.set_menu_duck(0.0)
	await _frames(8)

	# ============================================================ ⑦ 存档没动
	Audio.stop_bgm(0.0)
	await _frames(12)
	print("RESTORED 存档 md5后=%s" % _md5(_cfg))
	_check(_md5(_cfg) == _cfg_md5, "本探针**没动**玩家存档（md5 与跑前一致）")

	print("========== 探针结束：不符 %d 条 ==========" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


# ============================================================ 工具

func _active_player() -> AudioStreamPlayer:
	return Audio._bgm_players[Audio._bgm_active]


func _active_stream() -> AudioStream:
	var p := _active_player()
	return p.stream if p != null else null


## 造一段 `sec` 秒的**静音** WAV。用途见 §③：真机上要一个"真的会放完"的流。
##
## ⚠️ 为什么不用 `AudioStreamGenerator`：它要自己喂帧、还要等混音线程消费，
## 在探针里反而更难控。而一段真实的 `AudioStreamWAV` 走的是**与菜单曲完全一样**
## 的路径（`AudioStreamPlayer` → 解码 → 到头 → `finished`）—— 那才是我要证的那条链路。
func _tiny_wav(sec: float) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var frames := int(22050.0 * sec)
	var data := PackedByteArray()
	data.resize(frames * 2)          # 16 bit 单声道 ⇒ 每帧 2 字节
	data.fill(0)
	w.data = data
	return w


func _q(s: String) -> String:
	return "\"%s\"" % s


func _md5(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "(没有这个文件)"
	var b := FileAccess.get_file_as_bytes(path)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(b)
	return ctx.finish().hex_encode()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("   [%s] %s" % ["OK" if ok else "!!", what])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait_sec(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await get_tree().physics_frame


func _shot(name: String) -> void:
	# ⚠️ headless（Dummy 渲染器）下 `RenderingServer.frame_post_draw` **永不触发**
	# ⇒ 不加这一句的话，无头跑会**卡死在那里**（★63-22 实测踩过：就停在第一个 `_shot`）。
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
