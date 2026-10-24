extends Node
## ★ 轮 59（2026-10-01）探针：**真机**验「TRACER 作为 M01 的 bgm」。
##
## ## 为什么非真机不可
## `--headless` 下音频驱动是 Dummy —— `AudioStreamPlayer.playing` **根本不会置 true**
##（`suite_audio` 头注那句「无头测不了音频」就是这个意思）。所以「真的在放 tracer.mp3」
## 这件事只能在**有音频驱动**的进程里读。套件那边验的是"锁上了 / 曲子选对了 / stream 是循环的"
##（那些都不依赖音频驱动）。
##
## ## 跑法（**不要**加 `--headless`）
##   Godot_v4.7.1-stable_win64_console.exe --path . res://tools/_r59_bgm_probe.tscn
##
## ## 读四件事
## ① M01 出击 → 锁 = tracer / 当前曲 = tracer / **playing = true** / 资源 = tracer.mp3 / 循环 = true
## ② 负对照（**没有关卡数据**的对战）→ 锁 = 空，**而且放完一首会换曲**（证明对战没被锁死）
## ③ **写穿检验**：共享 `tracer.mp3` 的 `loop` 仍是 false（对战要靠它换曲）
## ④ 播放器手里那份**不是**共享实例（`duplicate()` 生效）

const MS := preload("res://scripts/data/mission_script.gd")
const SB := preload("res://scripts/audio/sound_bank.gd")
const MAIN_S := preload("res://scripts/main.gd")

var _fails := 0


func _ready() -> void:
	print("========== R59 · M01 BGM 探针（真机）==========")
	var m := MAIN_S.new()
	var mode_bak: int = Game.match_mode
	var phase_bak: int = Game.phase
	var mission_bak = Game.active_mission
	var pick_bak: String = Settings.battle_bgm_pick

	# ---- ① M01 出击（走 `_start_fight()` 的普通分支：这一关没有开场演出）----
	Game.match_mode = Game.MatchMode.CHALLENGE
	Game.active_mission = MS.by_id("M01")
	Settings.battle_bgm_pick = ""
	m.set("phase", MAIN_S.Phase.MENU)
	Audio.lock_battle_track("")
	m.call("_start_fight")
	await _settle()

	var pl: AudioStreamPlayer = Audio._bgm_players[Audio._bgm_active]
	var lock_now := Audio.battle_track_locked()
	var cur := Audio.current_bgm_track()
	var res := "" if pl.stream == null else pl.stream.resource_path
	var looped := _loops(pl.stream)
	var shared: AudioStream = load(SB.bgm_path("tracer"))
	# ⚠️ `duplicate()` 出来的 stream **没有 `resource_path`**（它不是从文件加载的）
	# ⇒ 判「放的是哪个文件」**不能**看它（实测第一版就栽在这：那串是空的）。
	# 正确做法 = **曲名**（`current_bgm_track()` 走 `SoundBank.BGM` 的映射）+ **时长比对**
	#（副本与共享文件长度一致 ⇒ 就是那份音频）。
	var dur := 0.0 if pl.stream == null else pl.stream.get_length()
	var dur_shared := 0.0 if shared == null else shared.get_length()
	print("① M01 出击后（梅萨 M01 / 达沃 / 剧情挑战）：")
	print("   锁住的本关曲   = %s   （期望 tracer）" % lock_now)
	print("   当前在放的曲子 = %s   （期望 tracer，走 SoundBank.BGM → tracer.mp3）" % cur)
	print("   播放器 playing = %s   （期望 true —— 这一条 headless 永远读不到）" % str(pl.playing))
	print("   音频资源       =「%s」  （空是**正常**的：duplicate 的副本没有 resource_path）" % res)
	print("   副本时长 %.2f s / tracer.mp3 时长 %.2f s" % [dur, dur_shared])
	print("   这份 stream 循环 = %s   （期望 true —— 整关就这一首）" % str(looped))
	_check(lock_now == "tracer", "M01 锁住了 tracer")
	_check(cur == "tracer", "M01 真的在放 tracer（曲名 → tracer.mp3）")
	_check(pl.playing, "音频驱动真的在播（真机专有判据）")
	_check(absf(dur - dur_shared) < 0.05, "副本与 tracer.mp3 时长一致（就是那份音频）")
	_check(looped, "锁曲时是循环的（不循环 = 打两分钟就换曲）")

	# ---- ③ ④ 写穿检验 ----
	print("③ 共享 tracer.mp3 的 loop = %s   （期望 false）" % str(_loops(shared)))
	print("   播放器手里那份就是共享实例吗？ %s   （期望：不是）" % str(pl.stream == shared))
	_check(not _loops(shared), "共享资源没被写穿（对战那边还要靠它换曲）")
	_check(pl.stream != shared, "播放器拿的是私有副本（duplicate 生效）")

	# ---- ② 负对照：没有关卡数据的对战 ----
	Game.active_mission = null
	m.set("phase", MAIN_S.Phase.MENU)
	Audio.lock_battle_track("")
	m.call("_start_fight")
	var first := Audio.current_bgm_track()
	await _settle()
	# 手动"一首放完"：真机等一整首歌太久，直接发 `finished` 让轮换跑起来
	Audio._bgm_players[Audio._bgm_active].finished.emit()
	await _settle()
	var second := Audio.current_bgm_track()
	print("② 负对照（没有关卡数据的对战）：")
	print("   锁 =「%s」   （期望空 —— 对战不许被锁成一首）" % Audio.battle_track_locked())
	print("   第一首 = %s → 放完自动换成 %s   （期望：换掉）" % [first, second])
	_check(Audio.battle_track_locked() == "", "对战不锁曲（整场不会被锁成一首）")
	_check(second != first, "对战照旧轮换（误锁或写穿都会让这里变成同一首）")

	print("========== 探针结束：不符 %d 条 ==========" % _fails)

	# ---- 还原 ----
	Game.match_mode = mode_bak
	Game.set_phase(phase_bak)
	Game.active_mission = mission_bak
	Settings.battle_bgm_pick = pick_bak
	Audio.lock_battle_track("")
	Audio.stop_bgm(0.0)
	for p: AudioStreamPlayer in Audio._bgm_players:
		p.stream = null
	m.free()
	get_tree().quit()


func _settle(n := 8) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("   [%s] %s" % ["OK" if ok else "!!", what])


func _loops(s: AudioStream) -> bool:
	if s == null:
		return false
	if s is AudioStreamMP3:
		return (s as AudioStreamMP3).loop
	if s is AudioStreamOggVorbis:
		return (s as AudioStreamOggVorbis).loop
	if s is AudioStreamWAV:
		return (s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	return false
