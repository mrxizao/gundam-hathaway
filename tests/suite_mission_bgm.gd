class_name SuiteMissionBgm
extends RefCounted
## ★ 轮 59（2026-10-01）：**关卡曲**（`Mission.bgm`）怎么变成「整关就这一首」。
##
## ## 老板原话（隔了一轮的两句，说的是同一件事）
## · M04：演出播放 XI，演出结束后战斗播放 car5p3 / PENELOPE。
## · M01：「TRACER 作为 M01 的 bgm」
##
## ## 为什么单开一个套件：它跨三层，而每一层坏掉的样子完全不同
##
## | 层 | 坏了会怎样 |
## |---|---|
## | 数据（`MissionScript`） | 那一关没挂曲子（或被改掉）⇒ 悄悄回到随机轮换，**不报错** |
## | `AudioDirector` | 曲子挂了、却只锁**开场一首** ⇒ 打两分钟就换成别的曲子 |
## | 接线（`main`） | 函数都写好了、**没有调用点**（本工程栽过三次） |
##
## ## 三件必须钉住的事
## 1. **锁曲真的锁住**：连要 6 首全是它，而且 `play_bgm` 之后那个 stream 是**循环**的；
## 2. **共享资源没被写穿**：同一份 `tracer.mp3` 在**对战模式**里必须还是**不循环**
##    （写穿的症状是「对战打完一首就卡住、再也不换曲」，而一行报错都没有）；
## 3. **接线是运行时验的**：真的造一个 `main`、真的调 `_start_fight()`，而不是扫源码
##    字符串 —— 轮 57 那次「有实现、没消费者」就是被字符串扫描放过去的。
##
## ⚠️ 跨文件引用走 `preload`，不走 `class_name`（同 `suite_campaign` / `suite_pod_strike`
## 头注那条：新加的脚本在编辑器重新扫描之前不在全局类缓存里）。

const MS := preload("res://scripts/data/mission_script.gd")
const SB := preload("res://scripts/audio/sound_bank.gd")
## ⚠️ 必须是 `preload`：`MAIN_S.Phase.MENU` 这个**枚举常量**要编译期解析。
const MAIN_S := preload("res://scripts/main.gd")


static func run(t: T) -> void:
	_data(t)
	_audio(t)
	_wiring(t)


# ---------------------------------------------------------------- 第一层：数据
static func _data(t: T) -> void:
	t.suite("★ 关卡曲的数据（Mission.bgm）")
	t.eq(MS.by_id("M01").bgm, "tracer",
		"★ M01 的战斗曲是 TRACER（老板：「TRACER 作为 M01 的 bgm」）")
	t.eq(MS.by_id("M04").bgm, "car5p3",
		"M04 的登场曲还是 PENELOPE（轮 59 动了这条链路，不许把它带丢）")

	# 每一关挂的曲子都必须是 `SoundBank.BGM` 里的键 —— 名字写错**不会报错**，
	# 只会在 `play_bgm` 里 `push_warning` 一句然后**静音**（比"锁不上"更糟）。
	var names: Array[String] = []
	for m: MS.Mission in MS.all():
		var b := str(m.bgm)
		if b == "":
			continue
		names.append(m.id + "=" + b)
		t.ok(SB.BGM.has(b), "%s 的曲子名 %s 在 SoundBank.BGM 里" % [m.id, b])
	print("[关卡曲] 挂了曲子的关：%s" % str(names))

	# ⚠️ **锁的曲子必须在剧情轮换池里** —— `bgm_name()` 的池子校验会把不在池里的
	# 曲子直接退回随机：那时「锁上了」是假的，而且**一行报错都没有**。
	#（`sweet_child` 正是这样的曲子：它是「仅自选曲」，任何轮换池里都没有它。）
	for mid: String in ["M01", "M04"]:
		var track := str(MS.by_id(mid).bgm)
		t.ok(SB.STORY_BATTLE_TRACKS.has(track),
			"★ %s 的曲子 %s 在剧情轮换池里（不在池里 = 锁不上，静默退回随机）" % [mid, track])
		t.not_ok(SB.is_opt_in_battle_track(track),
			"%s 的曲子不是「仅自选曲」（那只进自选列表、不进任何轮换池）" % mid)


# ---------------------------------------------------------------- 第二层：AudioDirector
static func _audio(t: T) -> void:
	t.suite("★ 锁曲在 AudioDirector 里的行为（纯函数级）")
	var lock_bak: String = Audio.battle_track_locked()
	var pool_bak: Array = Audio.battle_pool
	var bag_bak: Array = Audio._battle_bag
	var req_bak: String = Audio.requested_battle_open
	var last_bak: String = Audio._last_battle_track
	var senkou_bak: bool = Audio._senkou_used

	# 统一到一个已知起点：剧情池 + 空袋子 + 没有自选请求
	Audio.set_story_mode(true)
	Audio._battle_bag.clear()
	Audio._last_battle_track = ""
	Audio.requested_battle_open = ""

	# ---- ① 锁上之后连要 6 首，全是它（这就是“不走洗牌袋”） ----
	Audio.lock_battle_track("tracer")
	t.eq(Audio.battle_track_locked(), "tracer", "锁上了（`battle_track_locked()` 读得回来）")
	var seen: Array[String] = []
	for i in 6:
		seen.append(Audio.bgm_name(Audio.Bgm.BATTLE))
	var same := true
	for s: String in seen:
		if s != "tracer":
			same = false
	t.ok(same, "★★ 锁曲后连要 6 首**全是它**（不走洗牌袋）：%s" % str(seen))

	# ---- ② 真的在放、而且是**循环**的 ----
	Audio.play_bgm(Audio.Bgm.BATTLE, 0.0)
	t.eq(Audio.current_bgm_track(), "tracer", "★ 真的在放 TRACER")
	t.ok(_loops(Audio._bgm_players[Audio._bgm_active].stream),
		"★★ 锁曲时战斗曲**是循环的** —— 这是「整关就这一首」的实现（不循环就会换曲）")

	# ---- ③ 共享资源**没被写穿**（本节的核心） ----
	# `tracer.mp3` 现在有**两种用途**（关卡锁曲 = 循环 / 对战轮换 = 不循环），
	# 而 `load()` 给的是**共享实例**。若 `play_bgm` 少写那个 `duplicate()`，
	# 对战那边会退化成「打完一首就卡住、再也不换曲」—— 而且不报错。
	t.not_ok(_loops(load(SB.bgm_path("tracer"))),
		"★★★ 共享资源仍是**不循环**的（对战模式靠轮换换曲，写穿了就卡死在第一首）")

	# ---- ④ 锁曲把「玩家自选」整个盖住，且不留残渣 ----
	Audio.request_battle_open("nda_alpha")
	Audio.bgm_name(Audio.Bgm.BATTLE)
	t.eq(Audio.requested_battle_open, "",
		"★ 锁曲把「玩家自选」盖住并清掉（不清 = 下一局它会迟到地冒出来当第一首）")

	# ---- ⑤ 锁的曲不在池里 ⇒ 自动退回（不许静音） ----
	Audio.lock_battle_track("sweet_child")
	var got := Audio.bgm_name(Audio.Bgm.BATTLE)
	t.ok(SB.STORY_BATTLE_TRACKS.has(got),
		"★ 锁了一首**仅在自选列表**的曲子 ⇒ 自动退回轮换（拿到 %s，不是静音）" % got)
	Audio.lock_battle_track("no_such_track_at_all")
	got = Audio.bgm_name(Audio.Bgm.BATTLE)
	t.ok(SB.STORY_BATTLE_TRACKS.has(got),
		"★ 锁了个**不存在的名字** ⇒ 同样退回轮换（拿到 %s）" % got)

	# ---- ⑥ 解锁 ⇒ 回到轮换 ----
	Audio.lock_battle_track("")
	Audio._battle_bag.clear()
	Audio._last_battle_track = ""
	var drawn: Array[String] = []
	for i in SB.STORY_BATTLE_TRACKS.size() + 2:
		drawn.append(Audio.bgm_name(Audio.Bgm.BATTLE))
	var vary := false
	for d: String in drawn:
		if d != drawn[0]:
			vary = true
	t.ok(vary, "解锁后回到轮换（不是一直同一首）：%s" % str(drawn))

	# ---- 还原（套件不许留副作用）----
	Audio.lock_battle_track(lock_bak)
	Audio.stop_bgm(0.0)
	_detach_streams()
	Audio.battle_pool = pool_bak
	Audio._battle_bag = bag_bak
	Audio._last_battle_track = last_bak
	Audio.requested_battle_open = req_bak
	Audio._senkou_used = senkou_bak


# ---------------------------------------------------------------- 第三层：接线（运行时）
static func _wiring(t: T) -> void:
	t.suite("★ 接线：关卡曲怎么变成整关 BGM（运行时）")
	# ⚠️ 轮 57 的教训：`_finish_pod_strike()` 有实现、**零调用点**，而当时的判据是
	# `main_src.contains(...)` —— 「名字在源码里出现过」**不等于**「被调用」。
	# 所以这一节真的造一个 `main`、真的调 `_start_fight()`，看锁有没有被设上。
	var m := MAIN_S.new()
	# ⚠️ **不进树**（同 `suite_pod_strike` 末节）：进了树会留下信标之类的残留节点，
	# 给别人制造假红；而 `_start_fight()` 只碰自己的字段，不进树一样能跑。
	var mode_bak: int = Game.match_mode
	var gphase_bak: int = Game.phase
	var mission_bak = Game.active_mission
	var pick_bak: String = Settings.battle_bgm_pick
	var lock_bak: String = Audio.battle_track_locked()
	var req_bak: String = Audio.requested_battle_open

	# M04 cinematic and battle now have independent tracks.
	Game.match_mode = Game.MatchMode.CHALLENGE
	Game.active_mission = MS.by_id("M04")
	m._start_pod_strike_music()
	t.eq(Audio.current_bgm_track(), "xi", "M04 cinematic plays XI")
	t.eq(Audio.battle_track_locked(), "xi", "cinematic track stays locked during the scene")
	t.ok(not m._strike_bgm_live, "M04 hands music selection back at battle start")
	m.set("phase", MAIN_S.Phase.POD_STRIKE)
	m._start_fight()
	t.eq(Audio.current_bgm_track(), "car5p3", "M04 battle switches to PENELOPE")
	t.eq(Audio.battle_track_locked(), "car5p3", "M04 battle keeps its mission music")

	# The same audio player/stream survives M03's launch-to-fight handoff.
	Game.active_mission = MS.by_id("M03")
	m._start_launch_music()
	t.eq(Audio.current_bgm_track(),"car5p3","M03 rocket stage plays PENELOPE")
	t.eq(Audio.battle_track_locked(),"car5p3","M03 music stays locked through launch")
	var launch_player:AudioStreamPlayer=Audio._bgm_players[Audio._bgm_active]
	var launch_stream:AudioStream=launch_player.stream
	var active_index:int=Audio._bgm_active
	m.set("phase",MAIN_S.Phase.LAUNCH)
	m._start_fight()
	t.eq(Audio._bgm_active,active_index,"M03 handoff does not start another player")
	t.ok(Audio._bgm_players[Audio._bgm_active].stream==launch_stream,"M03 keeps the current playback stream")
	t.ok(not m._strike_bgm_live,"M03 carry flag consumed at handoff")

	for mid in ["M07","M09"]:
		Game.active_mission=MS.by_id(mid)
		m._start_mission_music()
		t.eq(Audio.current_bgm_track(),"car5p3",mid+" sortie starts PENELOPE")
		t.eq(Audio.battle_track_locked(),"car5p3",mid+" keeps its mission music locked")
		var sortie_index:int=Audio._bgm_active
		var sortie_stream:AudioStream=Audio._bgm_players[sortie_index].stream
		m.set("phase",MAIN_S.Phase.SORTIE);m._start_fight()
		t.eq(Audio._bgm_active,sortie_index,mid+" handoff keeps the same player")
		t.ok(Audio._bgm_players[Audio._bgm_active].stream==sortie_stream,mid+" does not restart the track")
		t.ok(not m._strike_bgm_live,mid+" consumes carry state once")

	# ---- ② 普通分支：M01 没有开场演出 ⇒ 走这里 ----
	Game.match_mode = Game.MatchMode.CHALLENGE
	Game.active_mission = MS.by_id("M01")
	m.set("phase", MAIN_S.Phase.MENU)   # 绕过 `_start_fight()` 的幂等闸
	Audio.lock_battle_track("")
	Audio.request_battle_open("")
	m.call("_start_fight")
	t.eq(Audio.battle_track_locked(), "tracer",
		"★★ M01 走普通分支 ⇒ 关卡曲被**锁住整关**（漏了这一步就只是「锁开场一首」）")
	t.eq(Audio.current_bgm_track(), "tracer", "★★ 而且真的在放 TRACER")

	# ---- ③ 负对照：没有关卡数据（对战 / 联机）⇒ **不许锁** ----
	# ⚠️ 这是最容易写错的一处：把 `lock_want` 写成 `want`，会让**整场对战只有一首**，
	# 而既有断言都不会红（它们只验「开场的自选曲生效了」）。
	Game.active_mission = null
	Settings.battle_bgm_pick = ""
	m.set("phase", MAIN_S.Phase.MENU)
	Audio.lock_battle_track("")
	m.call("_start_fight")
	t.eq(Audio.battle_track_locked(), "",
		"★ 负对照：没有关卡数据时**不锁**（对战/联机整场不许被锁成一首）")

	# ---- 还原（尤其 `Settings` —— 它会被写进存档）----
	Game.match_mode = mode_bak
	Game.set_phase(gphase_bak)
	Game.active_mission = mission_bak
	Settings.battle_bgm_pick = pick_bak
	Audio.lock_battle_track(lock_bak)
	Audio.request_battle_open(req_bak)
	Audio.stop_bgm(0.0)
	_detach_streams()
	# ⚠️ `free()` 不是 `queue_free()`：后者只是排队，而 `--only` 跑完就退出的进程
	# 等不到那一帧的 flush ⇒ 退出时打 `ObjectDB instances were leaked`
	# + `resources still in use`（交付判据的「四类报错计数」会把那条 ERROR 算进去）。
	m.free()


## 把两个 BGM 播放器手上的 stream 摘掉。
##
## ⚠️ 为什么需要它：锁曲时 `play_bgm()` 会 `duplicate()` 一份**私有** AudioStream
##（为了不改到共享资源的 `loop`），而 `stop_bgm()` 只做淡出、**不释放**流 ——
## 那几份副本会一直被 autoload 的播放器持有 ⇒ 进程退出时被算进
## `ObjectDB instances were leaked` / `resources still in use`。
## 它**不在**交付判据的四类报错里（Parse/SCRIPT/SHADER/Failed to load），
## 但 `--only` 单跑时这几个数是**信号**（轮 58 就是靠它发现临时节点没 `free()`）⇒ 能清就清。
static func _detach_streams() -> void:
	for pl: AudioStreamPlayer in Audio._bgm_players:
		pl.stream = null


## 这个 stream 是不是循环的（`suite_audio` 里同名的那个是 private，这里重写一份）。
static func _loops(s: AudioStream) -> bool:
	if s is AudioStreamMP3:
		return (s as AudioStreamMP3).loop
	if s is AudioStreamOggVorbis:
		return (s as AudioStreamOggVorbis).loop
	if s is AudioStreamWAV:
		return (s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	return false
