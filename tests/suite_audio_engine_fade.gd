class_name SuiteAudioEngineFade
extends RefCounted
## **进战斗时引擎音的"突然爆音"**（2026-10-09 用户实测）。
##
## ## 用户原话
##
## 「现在进入战斗会有引擎的突然爆音，你优化一下进入战斗时候的听觉体验」
##
## ## 根因（不在音源文件里，在**起播值 → 稳态值**的那一帧）
##
## 引擎循环音由两个函数共同决定，而它们之间**没有过渡**：
##
##   ① `Audio.make_loop_3d()` 把播放器造出来时写 **`volume_db = -60.0`**（静音），
##      然后 `FlightBody._build_engine_audio()` 立刻 `play()`。
##   ② `FlightBody._update_engine_audio()` 在**下一物理帧**把它改写为速度映射值：
##      `linear_to_db(engine_gain(fm.speed, fm.max_reachable_speed()))`。
##
## 出生时 `fm.speed = SuitProfile.spawn_speed()`（巡航档，不是 0）
## ⇒ `engine_gain` ≈ 0.31 ⇒ **约 -10 dB**（实测 -10.14）。
## ⇒ **一帧之内 -60 dB → -10 dB（实测 49.9 dB 台阶）**：起播那一帧就是一次满幅冲击。
##
## ⚠️ 雪上加霜的两件事（都让它更响）：
##   · 出生是**整队同时**的 ⇒ N 台机体在**同一物理帧**起同一个循环音，
##     而 `Audio._stream()` 是**按名字缓存**的（同一份 `AudioStream` 实例）
##     ⇒ 相位完全一致，叠起来是相干相加；
##   · 工程**没有任何总线限幅器**（`Settings._ensure_buses()` 只 `add_bus` + 设音量）
##     ⇒ 相干相加不会被兜住。
##
## ## 修法
##
## 给引擎音加**起播淡入**：从 `-60 dB` 在 `ENGINE_FADE_IN` 秒内升到目标值。
## ⚠️ 关键约束：**稳态必须逐位不变** —— 淡入只许改"开头那一段"，
## 不许顺手把整条引擎音量曲线一起改了（那条曲线 `engine_gain` 另有判据钉着，
## 见 `suite_audio._engine_gain`）。
##
## ## ⚠️ 本套件的核心判据是「单帧最大跳变」
##
## 不是"某一帧比某个阈值低" —— 那种写法在"把整体音量调小一半"时照样绿。
## 量**相邻两帧的 dB 差**才直接对应"听不听得出爆音"：
## 施工前那一帧是 **58 dB**，淡入之后是 **≈ 0.8 dB/帧**。

const DT := 1.0 / 60.0
## 跑 2 s：足够跨过 `ENGINE_FADE_IN`（1.2 s）并进入稳态。
const FRAMES := 120
## 单帧 dB 跳变的上限。人耳对"爆音"的容忍远低于此；取 6 dB 是为了给
## "速度在变 ⇒ 目标值本来就在动"留余量，同时把 58 dB 那一帧死死挡在外面。
const MAX_STEP_DB := 6.0
## 与 `Audio.make_loop_3d()` 的起播值一致（差几 dB 就是一个新台阶）。
const SILENT_DB := -60.0


static func run(t: T, host: Node) -> void:
	t.suite("AudioEngineFade / ① 源码：引擎音有起播淡入，且稳态公式没被改")
	_source(t)
	t.suite("AudioEngineFade / ② 行为：玩家机起播不跳变（单帧 ≤ %.0f dB）" % MAX_STEP_DB)
	await _behaviour(t, host, true)
	t.suite("AudioEngineFade / ③ 行为：敌机同样淡入（它是 3D 定位那一路）")
	await _behaviour(t, host, false)


# ================================================================ ① 源码

static func _source(t: T) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/flight/flight_body.gd")
	t.gt(float(src.length()), 1000.0, "读到 flight_body.gd（%d 字节）" % src.length())
	t.ok(src.contains("\nconst ENGINE_FADE_IN"),
		"★ 有 `ENGINE_FADE_IN` 这个常量（淡入时长的唯一真源）")
	t.ok(src.contains("\nconst ENGINE_SILENT_DB"),
		"★ 有 `ENGINE_SILENT_DB` —— 它必须与 `make_loop_3d()` 的起播值同源，"
			+ "否则淡入起点与播放器实际起点对不上（又是新台阶）")
	# 稳态公式**不许被动过**：`engine_gain()` 是需求里唯一给了数字的音频规则，
	# `suite_audio._engine_gain` 钉着它；这里再钉一次"淡入没把它绕过去"。
	t.ok(src.contains("var gain := engine_gain(fm.speed, top)"),
		"稳态仍然是 `engine_gain(fm.speed, top)`（淡入只是在它前面加过渡）")
	t.ok(src.contains("_engine.volume_db = want_db if ramp >= 1.0"),
		"★ 淡入到 1.0 时**逐位写 `want_db`**（`lerpf` 的 `a + (b-a)*t` 不保证 t=1 时逐位等于 b）")


# ================================================================ ② ③ 行为

static func _behaviour(t: T, host: Node, as_player: bool) -> void:
	Game.reset()
	var c := Node3D.new()
	c.name = "EngineFadeStage"
	host.add_child(c)
	var u := FlightBody.new()
	u.team = 0 if as_player else 1
	u.is_player = as_player
	u.profile = SuitProfile.xi()
	u.projectile_container = c
	c.add_child(u)
	u.global_position = Vector3(0, 3000, 0)
	# 复刻**出生那一瞬**：速度就是 `spawn_speed()`（不是 0，也不是手动摆的值）。
	u.fm.speed = SuitProfile.spawn_speed()
	u.fm.align_velocity(u.forward())

	var eng := _find_engine(u)
	t.ok(eng != null, "（前提）机体挂了引擎循环音")
	if eng == null:
		c.free()
		return
	t.near(eng.volume_db, SILENT_DB, 0.001,
		"（前提）刚建好时是**静音值** %.0f dB —— 起播值在这里，台阶也从这里开始" % SILENT_DB)
	t.ok(eng.playing, "（前提）已经 `play()` 了（不然下面量的是「没在播的播放器」）")

	# ---- 稳态目标值：用**产品同一个公式**独立算一遍（不读实现里的中间量）----
	var top := maxf(u.fm.max_reachable_speed(), 1.0)
	var want_db := linear_to_db(maxf(FlightBody.engine_gain(u.fm.speed, top), 0.001))
	if not as_player:
		want_db -= 4.0

	# ---- 逐帧推进，记录 dB 与单帧跳变 ----
	var dbs: Array[float] = []
	var max_step := 0.0
	var was := eng.volume_db
	for i in FRAMES:
		u.call("_update_engine_audio", DT)
		var now: float = eng.volume_db
		dbs.append(now)
		max_step = maxf(max_step, absf(now - was))
		was = now
	var first := dbs[0]
	var last := dbs[FRAMES - 1]
	var tail := dbs[FRAMES - 1 - 10]
	print("[EngFade] %s：top=%.1f 速度=%.1f｜第 1 帧 %.2f dB｜末帧 %.4f dB｜想达到 %.4f dB"
		% ["玩家" if as_player else "敌机", top, u.fm.speed, first, last, want_db])
	print("[EngFade] %s：单帧最大跳变 %.3f dB（施工前 = %.1f dB）"
		% ["玩家" if as_player else "敌机", max_step, absf(want_db - SILENT_DB)])

	# ★ 核心：不许有"一帧到位"
	t.lt(max_step, MAX_STEP_DB,
		"★ 单帧最大跳变 %.3f dB < %.0f dB —— 不是「一帧从静音到满速」"
			% [max_step, MAX_STEP_DB])
	# 施工前的读数（= 负对照）：同一批帧上那一跳就是 58 dB
	t.gt(absf(want_db - SILENT_DB), 30.0,
		"（仪器自证）起播值到稳态本来相距 %.1f dB ⇒ 不淡入就是**一帧跨完**"
			% absf(want_db - SILENT_DB))
	# 起播那一帧必须**已经离开静音**（否则就是"淡入写成了静音"）
	t.gt(first, SILENT_DB,
		"第 1 帧 %.2f dB 已经离开静音值（淡入真的在走，不是没接上）" % first)
	# 单调不降（速度恒定 ⇒ 目标恒定）：防"上下点头"那种更刺耳的写法
	var back := 0
	for i in range(1, FRAMES):
		if dbs[i] < dbs[i - 1] - 0.001:
			back += 1
	t.eq(back, 0, "淡入全程单调不降（回退 0 次）")
	# ★ 稳态回到**旧公式**的值：这是"只改开头、不改曲线"的唯一硬证据。
	#
	# ⚠️ 为什么是 `near` 而不是 `==`：`AudioStreamPlayer3D.volume_db` 是 `real_t`
	#   （非 double 构建下 = **float32**）⇒ 写进去 double、读回来已经过了一次 float32 舍入。
	#   实测差值 ~1e-7 dB（`%.6f` 打印出来一模一样，`==` 却是假）。
	#   ⚠️ 容差取 5e-4 而不是"随手放大"：真出问题（`ramp` 卡在 0.999 没到 1）
	#   会是 **0.05 dB** 量级的残留 —— 比容差大两个数量级，照样红。
	t.near(last, want_db, 0.0005,
		"★ 2 s 后稳态回到旧公式的值（差 %.7f dB，float32 存储精度内）" % absf(last - want_db))
	t.ok(tail == last, "...而且最后 10 帧**一模一样**（淡入没有拖尾）")

	c.free()
	await host.get_tree().process_frame
	Game.reset()


static func _find_engine(u: FlightBody) -> AudioStreamPlayer3D:
	for c: Node in u.get_children():
		var p := c as AudioStreamPlayer3D
		if p != null and p.name == "EngineLoop":
			return p
	return null
