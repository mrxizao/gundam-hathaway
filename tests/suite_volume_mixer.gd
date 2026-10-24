class_name SuiteVolumeMixer
extends RefCounted
## ★63-23「音量细分」：武器（机枪 / 军刀 / 步枪 / 浮游飞弹）/ 警报 / BGM / 引擎 各自的音量。
##
## 需求原文（用户 2026-10-08）：「做一个音量调节系统：武器（机枪，军刀，步枪，浮游飞弹）
## 音量，警报音量，bgm音量，引擎音量」。
##
## ## 这一套钉的是**四段接线**，每一段断了都"不报错、也不红"
##
## | 段 | 断了的症状 | 本套件哪一节 |
## |---|---|---|
## | ① 总线没建 / 建错位置 | 滑条还在、还能拖，但它不再被「音效音量」管 | 总线树 |
## | ② `BUS_VAR` 里变量名拼错 | 那条滑条拖了没反应（`get()` 返回 null） | BUS_VAR 完整性 |
## | ③ `SoundBank.SFX_BUS` 里总线名拼错 | 那条音效照旧进 `SFX`，它自己的滑条**不管用** | 分派表闸门 |
## | ④ 某个播放通道没接 `_bus_for` | 只有那一条通道不归滑条管（"自己开炮变响了、敌机开炮没变"） | 四条通道接线 |
##
## ## ⚠️ 无头环境测不了"声音变多大"
## Dummy 音频驱动下不产生采样（`suite_audio` 的注释写过同一条）。
## 所以这里量的是**引擎侧的接线事实**：`AudioServer` 的总线路由与 dB、
## 以及"每个播放器挂在哪条总线上"。**真的音量只有真机听得出来** ——
## 本套件不假装能测它。
##
## ⚠️ 签名 `run(t, host)` 且注册表第 3 列 = **false**、第 4 列 = **true**：
## 没有一处 await（播放器创建是同步的），但要 host 去摸 `current_scene`
##（`play_3d` 会把临时播放器挂到当前场景下面）。

## 四条播放通道在 `AudioDirector` 里都必须走同一个分派函数。
## 数字写死在这里是**故意的**：漏接一条时它才会红（"改小数字让它绿"就是自欺）。
const BUS_FOR_CALL_SITES := 4

## 设置页那个子页的显示名（与 `MainMenu.SETTING_ROWS` 里的 key 对应）。
const ROW_KEY := "volume"


static func run(t: T, host: Node) -> void:
	# 八条总线跑一遍就全动过了 ⇒ 前后各存一份，末尾还原（照 `suite_settings` 的写法：
	# 不还原的话，套件跑一次就把玩家的音量设置改掉了 —— 那是最不该发生的事）。
	var backup := {}
	for n: String in Settings.BUS_ORDER:
		backup[n] = Settings.volume(n)

	t.suite("VolumeMixer / 总线树（八条 · 六条挂在 SFX 下面）")
	_tree(t)

	t.suite("VolumeMixer / 默认值（六条细分一律 100% ⇒ 声音与改动前逐位一致）")
	_defaults(t)

	t.suite("VolumeMixer / BUS_VAR 完整性（唯一真源必须自洽）")
	_table(t)

	t.suite("VolumeMixer / set_volume · volume 往返与静音语义")
	_roundtrip(t)

	t.suite("VolumeMixer / SoundBank.SFX_BUS 分派表闸门（活总线 / 值域 / 真音效名）")
	_dispatch(t)

	t.suite("VolumeMixer / 四条播放通道真的接到了细分总线")
	_wiring(t, host)

	t.suite("VolumeMixer / 设置页「音量」子页（名单覆盖 / 三处分派 / 只退一层）")
	_ui(t)

	for n: String in Settings.BUS_ORDER:
		Settings.set_volume(n, float(backup[n]))
	t.near(Settings.volume(Settings.BUS_FUNNEL), float(backup[Settings.BUS_FUNNEL]), 0.0001,
		"套件跑完后八条总线已还原（跑一次测试不该改掉玩家的音量）")


# ============================================================ 1. 总线树

static func _tree(t: T) -> void:
	t.gt(float(Settings.bus_index("Master")), -1.0, "（对照）Master 总线可查询")

	for n: String in Settings.BUS_ORDER:
		t.gt(float(Settings.bus_index(n)), 0.0,
			"总线 %s 存在，而且不是 Master（下标 0）" % n)

	# `BUS_ORDER` 是建总线的顺序表 ⇒ 里面不许有重复（重复会让"顺序"这件事说不清）。
	var uniq := {}
	for n: String in Settings.BUS_ORDER:
		uniq[n] = true
	t.eq(uniq.size(), Settings.BUS_ORDER.size(),
		"`BUS_ORDER` 里没有重复项（%d 条全不同）" % Settings.BUS_ORDER.size())

	# ⚠️ 这一条是"父必须在前"的**结果**，不是过程：顺序反了会静默挂到 Master 上。
	var sub := [Settings.BUS_VULCAN, Settings.BUS_SABER, Settings.BUS_RIFLE,
		Settings.BUS_FUNNEL, Settings.BUS_ALARM, Settings.BUS_ENGINE]
	for n: String in sub:
		var i := Settings.bus_index(n)
		t.eq(AudioServer.get_bus_send(i), Settings.BUS_SFX,
			"%s 的 send 目标是 SFX（六条细分都在音效总闸下面）" % n)

	for n: String in [Settings.BUS_BGM, Settings.BUS_SFX]:
		t.eq(AudioServer.get_bus_send(Settings.bus_index(n)), "Master",
			"%s 直接挂 Master" % n)

	# 父子关系表本身也不许少登记（`_ensure_buses()` 查的就是它）。
	t.eq(Settings.BUS_PARENT.size(), sub.size(),
		"`BUS_PARENT` 只登记六条子总线（BGM / SFX 走默认的 Master）")
	for n: String in sub:
		t.eq(str(Settings.BUS_PARENT.get(n, "")), Settings.BUS_SFX,
			"`BUS_PARENT[%s]` = SFX" % n)


# ============================================================ 2. 默认值

static func _defaults(t: T) -> void:
	# ⚠️ 默认值从**新实例**读（与 `Settings.begin_isolated()` 同一套取法），
	# **不写死 1.0** —— 写死的话将来改默认值，这里会静默不同步。
	var fresh: Node = (Settings.get_script() as GDScript).new() as Node
	t.ok(fresh != null, "（对照）能造出 `Settings` 的一个干净实例（默认值的唯一真源）")
	if fresh == null:
		return

	var sub := [Settings.BUS_VULCAN, Settings.BUS_SABER, Settings.BUS_RIFLE,
		Settings.BUS_FUNNEL, Settings.BUS_ALARM, Settings.BUS_ENGINE]
	for n: String in sub:
		var key := str(Settings.BUS_VAR[n])
		var declared := float(fresh.get(key))
		t.near(declared, 1.0, 0.0001,
			"`%s` 的**声明默认**是 100%%（子通道出厂不压任何东西）" % key)
		t.near(Settings.volume(n), declared, 0.0001,
			"%s 的运行期值 = 声明默认（测试隔离真的生效了）" % n)
		t.not_ok(AudioServer.is_bus_mute(Settings.bus_index(n)),
			"%s 出厂不静音" % n)
		t.near(AudioServer.get_bus_volume_db(Settings.bus_index(n)), 0.0, 0.05,
			"%s 出厂 0 dB ⇒ **改动前后的声音逐位一致**" % n)
	fresh.free()

	# 这一条把上面那串话变成一句话：默认态下，引擎侧八条总线的 dB 全是 0.0
	#（BGM / SFX 例外 —— 它们本来就带 0.80 / 0.90 的出厂音量，那是老设定）。
	var nonzero := []
	for n: String in sub:
		if absf(AudioServer.get_bus_volume_db(Settings.bus_index(n))) > 0.05:
			nonzero.append(n)
	t.eq(nonzero.size(), 0, "六条细分的出厂 dB 全是 0.0（不是 0 的：%s）" % str(nonzero))


# ============================================================ 3. BUS_VAR

static func _table(t: T) -> void:
	t.eq(Settings.BUS_VAR.size(), Settings.BUS_ORDER.size(),
		"`BUS_VAR` 与 `BUS_ORDER` 条数一致（八条）")
	t.eq(Settings.BUS_ORDER.size(), 8, "八条总线：BGM + SFX + 六条细分")

	var missing := []
	var ghosts := []
	for n: String in Settings.BUS_ORDER:
		if not Settings.BUS_VAR.has(n):
			missing.append(n)
			continue
		var key := str(Settings.BUS_VAR[n])
		# ⚠️ 这一条是**拼写闸门**：`get()` 一个不存在的属性返回 null
		# ⇒ 「变量名写错一个字母」当场变红，而不是"那条滑条拖了没反应"。
		var v: Variant = Settings.get(key)
		if not (v is float or v is int):
			ghosts.append(key)
	t.eq(missing.size(), 0, "每条总线都有变量名（缺的：%s）" % str(missing))
	t.eq(ghosts.size(), 0, "每个变量名都真的存在（假名字：%s）" % str(ghosts))

	var extra := []
	for n: String in Settings.BUS_VAR:
		if not Settings.BUS_ORDER.has(n):
			extra.append(n)
	t.eq(extra.size(), 0, "`BUS_VAR` 里没有 `BUS_ORDER` 之外的总线（多的：%s）" % str(extra))

	# 存档清单也要覆盖这八条 —— 漏一条的症状是"下次开机这条滑条自己回到 100%"。
	var not_persisted := []
	for n: String in Settings.BUS_ORDER:
		var key := str(Settings.BUS_VAR[n])
		if not Settings.PERSISTED_VARS.has(key):
			not_persisted.append(key)
	t.eq(not_persisted.size(), 0,
		"八条音量都在 `PERSISTED_VARS` 里（漏掉的：%s）" % str(not_persisted))


# ============================================================ 4. 往返 / 静音

static func _roundtrip(t: T) -> void:
	for n: String in Settings.BUS_ORDER:
		Settings.set_volume(n, 0.37)
		t.near(Settings.volume(n), 0.37, 0.0001, "%s 设 37%% 能读回 37%%" % n)
		t.near(AudioServer.get_bus_volume_db(Settings.bus_index(n)), linear_to_db(0.37), 0.05,
			"%s 的 37%% **真的写进了引擎**（不是只存在本地上）" % n)

	# 夹取
	Settings.set_volume(Settings.BUS_RIFLE, 5.0)
	t.near(Settings.volume(Settings.BUS_RIFLE), 1.0, 0.0001, "上限夹到 100%")
	Settings.set_volume(Settings.BUS_RIFLE, -3.0)
	t.near(Settings.volume(Settings.BUS_RIFLE), 0.0, 0.0001, "下限夹到 0%")

	# 静音语义（0 走 `set_bus_mute`，不是 -80 dB 硬凑）
	Settings.set_volume(Settings.BUS_RIFLE, 0.0)
	t.ok(AudioServer.is_bus_mute(Settings.bus_index(Settings.BUS_RIFLE)),
		"步枪 0% = 引擎侧真静音")
	Settings.set_volume(Settings.BUS_RIFLE, 1.0)
	t.not_ok(AudioServer.is_bus_mute(Settings.bus_index(Settings.BUS_RIFLE)),
		"步枪 100% = 解除静音")

	# 细分之间互不影响（这是"细分"这三个字的全部意义）
	Settings.set_volume(Settings.BUS_RIFLE, 0.0)
	t.not_ok(AudioServer.is_bus_mute(Settings.bus_index(Settings.BUS_SABER)),
		"把步枪拉到 0 不会把军刀也静音（两条独立总线）")

	# 父总线归零时，子通道**自己的值不动**：级联是引擎做的，
	# 不是 GDScript 去把子值也改一遍（子值被改的话，玩家把 SFX 拉回来时会发现
	# 自己那根步枪滑条也变了）。
	Settings.set_volume(Settings.BUS_RIFLE, 0.50)
	Settings.set_volume(Settings.BUS_SFX, 0.0)
	t.near(Settings.volume(Settings.BUS_RIFLE), 0.50, 0.0001,
		"SFX 归零时步枪自己的值保持 50%（级联在引擎里，不是把子值也改掉）")
	t.near(AudioServer.get_bus_volume_db(Settings.bus_index(Settings.BUS_RIFLE)),
		linear_to_db(0.50), 0.05, "……而步枪总线自己的 dB 也没被 SFX 动过")
	Settings.set_volume(Settings.BUS_SFX, 0.90)

	# 未知总线 = no-op。⚠️ 老写法（`if BGM … else sfx_volume = …`）会让一个拼错的
	# 总线名**悄悄改掉音效总音量** —— 调用点以为自己在调别的东西。
	var sfx_before := Settings.volume(Settings.BUS_SFX)
	var bgm_before := Settings.volume(Settings.BUS_BGM)
	Settings.set_volume("NOT_A_BUS", 0.05)
	t.near(Settings.volume(Settings.BUS_SFX), sfx_before, 0.0001,
		"未知总线不会落到 SFX 上（老写法会 —— 那是「拼错名字静默生效」的来源）")
	t.near(Settings.volume(Settings.BUS_BGM), bgm_before, 0.0001, "也不会落到 BGM 上")
	t.near(Settings.volume("NOT_A_BUS"), 0.0, 0.0001,
		"未知总线读回来是 0.0（而不是「随便给一个」）")


# ============================================================ 5. 分派表闸门

static func _dispatch(t: T) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/audio/sound_bank.gd")
	t.ok(src != "", "（对照）读得到 `sound_bank.gd`")
	t.eq(src.count("const SFX_BUS := {"), 1, "`SFX_BUS` 只有一份定义")

	t.gt(float(SoundBank.SFX_BUS.size()), 0.0, "（对照）分派表非空")

	# ① 每个值都是一条**活总线**（写错一个字母 ⇒ 那条音效静默退回 SFX）
	var dead := []
	for k: String in SoundBank.SFX_BUS:
		if Settings.bus_index(str(SoundBank.SFX_BUS[k])) < 0:
			dead.append("%s→%s" % [k, str(SoundBank.SFX_BUS[k])])
	t.eq(dead.size(), 0, "表里每个值都是一条活总线（死的：%s）" % str(dead))

	# ② 值域 = 六条细分通道，不多不少
	var want := [Settings.BUS_VULCAN, Settings.BUS_SABER, Settings.BUS_RIFLE,
		Settings.BUS_FUNNEL, Settings.BUS_ALARM, Settings.BUS_ENGINE]
	var want_set := {}
	for w: String in want:
		want_set[w] = true
	var live := {}
	for k: String in SoundBank.SFX_BUS:
		live[str(SoundBank.SFX_BUS[k])] = true
	var outside := []
	for b: String in live:
		if not want_set.has(b):
			outside.append(b)
	t.eq(outside.size(), 0,
		"没有表项指向六条之外的通道（多的：%s）" % str(outside))
	var empty := []
	for w: String in want:
		if not live.has(w):
			empty.append(w)
	t.eq(empty.size(), 0, "六条通道每条都至少有一条音效（空通道：%s）" % str(empty))

	# ③ 键必须是真的音效名 —— 拼错的键 = 一条永远不会被查到的表项（静默无效）
	var wrong_keys := []
	for k: String in SoundBank.SFX_BUS:
		if not (SoundBank.SFX.has(k) or SoundBank.VOICE.has(k)):
			wrong_keys.append(k)
	t.eq(wrong_keys.size(), 0,
		"表里的键都是已登记的音效/语音名（幽灵键：%s）" % str(wrong_keys))

	# ④ 用户点名的那七件事，一条一条对（这是需求原文的逐条落地）
	t.eq(SoundBank.bus_for("vulcan"), Settings.BUS_VULCAN, "机枪（vulcan）→ 机枪通道")
	t.eq(SoundBank.bus_for("beam_saber"), Settings.BUS_SABER, "军刀（挥刀）→ 军刀通道")
	t.eq(SoundBank.bus_for("saber_impact"), Settings.BUS_SABER,
		"军刀（命中）→ 军刀通道（挥与砍是同一件武器的两半）")
	t.eq(SoundBank.bus_for("beam_rifle"), Settings.BUS_RIFLE, "步枪 → 步枪通道")
	t.eq(SoundBank.bus_for("funnel_fire"), Settings.BUS_FUNNEL, "浮游飞弹 → 浮游飞弹通道")
	for a: String in ["alarm_lock", "alarm_missile", "alarm_critical"]:
		t.eq(SoundBank.bus_for(a), Settings.BUS_ALARM, "警报 %s → 警报通道" % a)
	for v: String in ["voice_pull_up", "voice_missile", "voice_stall", "voice_over_g"]:
		t.eq(SoundBank.bus_for(v), Settings.BUS_ALARM, "座舱语音 %s → 也是警报通道" % v)
	for e: String in ["cruise_xi", "cruise_penelope"]:
		t.eq(SoundBank.bus_for(e), Settings.BUS_ENGINE, "引擎 %s → 引擎通道" % e)

	# ⑤ 没被点名的音效**不许**进表 ⇒ 它们照旧进 `SFX`（未分类）。
	# 这一条防的是"顺手把爆炸/UI 也塞进某个通道"——那会让某根滑条管到不相干的东西。
	for k: String in ["ui_confirm", "ui_select", "boom_s", "boom_m", "boom_l",
			"startup", "arizeus_transform", "xi_detect"]:
		t.eq(SoundBank.bus_for(k), "",
			"%s 未分类 ⇒ 走 SFX（表里刻意不登记）" % k)
	# （对照）反过来说：未分类的确实会被 AudioDirector 兜成 SFX
	t.eq(Audio._bus_for("boom_s"), Settings.BUS_SFX,
		"（对照）未分类音效经 `AudioDirector._bus_for()` 兜底成 SFX")


# ============================================================ 6. 四条通道接线

static func _wiring(t: T, host: Node) -> void:
	# ---- ① 分派函数本身 ----
	t.eq(Audio._bus_for("vulcan"), Settings.BUS_VULCAN, "`_bus_for(vulcan)` = VULCAN")
	t.eq(Audio._bus_for("cruise_xi"), Settings.BUS_ENGINE, "`_bus_for(cruise_xi)` = ENGINE")
	t.eq(Audio._bus_for("不是音效"), Settings.BUS_SFX, "未知名字兜底到 SFX")

	# ---- ② 源码：四条通道**都**走了它 ----
	# ⚠️ 数字写死（`BUS_FOR_CALL_SITES`）：改小它才能变绿，那正是"自欺"的定义。
	var ad := FileAccess.get_file_as_string("res://scripts/audio/audio_director.gd")
	t.ok(ad != "", "（对照）读得到 `audio_director.gd`")
	t.eq(ad.count("p.bus = _bus_for("), BUS_FOR_CALL_SITES,
		"四条播放通道全部走 `_bus_for`（play_self / play_3d / play_voice / make_loop_3d）")
	t.ok(not ad.contains("p.bus = Settings.BUS_SFX"),
		"没有任何通道还写死 `Settings.BUS_SFX`（漏接一条 = 那条不归它的滑条管）")
	t.eq(ad.count("func _bus_for("), 1, "`_bus_for()` 只有一份定义")

	# ---- ③ 真播一条，看播放器落在哪条总线上（端到端，不是读源码）----
	Audio.reset_throttle()
	var n0 := Audio.get_child_count()
	Audio.play_self("vulcan", -20.0)
	var got_self := "（没造出播放器）"
	for i in range(n0, Audio.get_child_count()):
		var p := Audio.get_child(i) as AudioStreamPlayer
		if p != null and p.stream != null:
			got_self = p.bus
	t.eq(got_self, Settings.BUS_VULCAN,
		"`play_self(vulcan)` 造出来的播放器挂在 VULCAN 上（端到端）")

	# 未分类的仍然进 SFX（同一条路，反向对照）
	Audio.reset_throttle()
	var n1 := Audio.get_child_count()
	Audio.play_self("ui_confirm", -20.0)
	var got_ui := "（没造出播放器）"
	for i in range(n1, Audio.get_child_count()):
		var p2 := Audio.get_child(i) as AudioStreamPlayer
		if p2 != null and p2.stream != null:
			got_ui = p2.bus
	t.eq(got_ui, Settings.BUS_SFX,
		"（反向对照）`play_self(ui_confirm)` 仍然挂在 SFX 上")

	# 定位通道（`play_3d` 挂在当前场景下面，所以要 host 的树）
	var cs := host.get_tree().current_scene
	t.ok(cs != null, "（对照）`current_scene` 存在（`play_3d` 要一个 3D 父节点）")
	if cs != null:
		Audio.reset_throttle()
		var m0 := cs.get_child_count()
		Audio.play_3d("funnel_fire", Vector3.ZERO, -20.0)
		var got_3d := "（没造出播放器）"
		for i in range(m0, cs.get_child_count()):
			var p3 := cs.get_child(i) as AudioStreamPlayer3D
			if p3 != null and p3.stream != null:
				got_3d = p3.bus
		t.eq(got_3d, Settings.BUS_FUNNEL,
			"`play_3d(funnel_fire)` 挂在 FUNNEL 上（定位通道也接了）")

	# 引擎循环（`make_loop_3d` 造出来、由调用方自己挂）
	var lp := Audio.make_loop_3d("cruise_xi")
	t.ok(lp != null, "（对照）`make_loop_3d()` 造得出来")
	if lp != null:
		t.eq(lp.bus, Settings.BUS_ENGINE,
			"`make_loop_3d(cruise_xi)` 造出来的循环挂在 ENGINE 上（常驻循环也归滑条管）")
		lp.free()

	# 语音：素材可能不存在 ⇒ 走降级，**两种都该在 ALARM 上**。
	# ⚠️ 不写成"if 有语音则断言"，那样素材没到货时这一条会**恒真空过**。
	var resolved := SoundBank.voice_or_fallback("voice_pull_up")
	t.ok(resolved != "", "（对照）语音有降级路径（素材没到货也不会静音）")
	t.eq(Audio._bus_for(resolved), Settings.BUS_ALARM,
		"语音（或它降级到的合成警报）都走 ALARM —— 两种都算「警报」")


# ============================================================ 7. 设置页子页

static func _ui(t: T) -> void:
	# ---- ① 名单 ----
	var rows := MainMenu.volume_rows()
	t.eq(rows.size(), 8, "音量细分页八行（BGM / 音效 / 四条武器 / 警报 / 引擎）")
	var buses := {}
	for r: Dictionary in rows:
		t.ok(str(r.get("label", "")) != "", "每一行都有显示名（空的会让玩家不知道该调什么）")
		buses[str(r.get("bus", ""))] = true
	t.eq(buses.size(), rows.size(), "八行对应八条**不同**的总线（有重复 = 有一行是摆设）")

	var want := {}
	for n: String in Settings.BUS_ORDER:
		want[n] = true
	var miss := []
	for n: String in want:
		if not buses.has(n):
			miss.append(n)
	t.eq(miss.size(), 0, "名单覆盖 `Settings.BUS_ORDER` 全体（缺的：%s）" % str(miss))
	var extra := []
	for b: String in buses:
		if not want.has(b):
			extra.append(b)
	t.eq(extra.size(), 0, "名单里没有 `Settings` 之外的总线（多的：%s）" % str(extra))

	# ---- ② 设置页那一行 ----
	var hits := 0
	for r2: Dictionary in MainMenu.SETTING_ROWS:
		if str(r2.get("key", "")) == ROW_KEY:
			hits += 1
	t.eq(hits, 1, "设置页恰好有一条 `%s` 行（写两条 = 两处各写一份）" % ROW_KEY)
	t.ok(not bool(MainMenu.SETTING_ROWS[0].get("hidden", false)),
		"（对照）第一行不是隐形行（`SETTING_ROWS` 的表结构没被改坏）")

	# ---- ③ 子屏常量 ----
	t.eq(MainMenu.SET_SUB_MAIN, 0, "主屏常量 = 0")
	t.eq(MainMenu.SET_SUB_VOLUME, 1, "音量页常量 = 1")
	t.ok(MainMenu.SET_SUB_MAIN != MainMenu.SET_SUB_VOLUME,
		"（对照）两个子屏常量**不同值**（同值的话分派条件恒真，音量页会顶掉设置页）")

	# ---- ④ 源码：三处分派 + 一处排除 + 只退一层 ----
	var ms := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	t.ok(ms != "", "（对照）读得到 `main_menu.gd`")
	t.eq(ms.count("func volume_rows() -> Array:"), 1, "`volume_rows()` 只有一份定义")
	t.eq(ms.count("func _draw_volume_stage("), 1, "`_draw_volume_stage()` 只有一份定义")
	t.eq(ms.count("func _read_volume_input("), 1, "`_read_volume_input()` 只有一份定义")
	t.eq(ms.count("func _volume_step("), 1, "`_volume_step()` 只有一份定义")
	t.gt(float(ms.count("if settings_sub == SET_SUB_VOLUME:")), 1.0,
		"输入与绘制**两处**都分派了子屏（只写一处的症状是「那一页画不出来 / 按键没反应」）")
	t.gt(float(ms.count("_draw_volume_stage()")), 1.0, "绘制分派真的调到了它")
	t.gt(float(ms.count("_read_volume_input()")), 1.0, "输入分派真的调到了它")
	t.eq(ms.count("_volume_step(delta)"), 1, "调值步进从 `_process` 里被调到")
	t.gt(float(ms.count('or key == "volume"')), 1.0,
		"`volume` 行在两个地方被点名（左右调值要排除它 + Enter 要进子页）")
	t.ok(ms.contains('if _setting_is_action(key) or key == "battle_playlist" or key == "volume":'),
		"`_setting_step()` 显式排除了 `volume`（不排除就是白吃一次输入）")
	t.eq(ms.count("if stage == Stage.SETTINGS and settings_sub == SET_SUB_VOLUME:"), 1,
		"Esc 保险丝里有「音量页只退一层」那一支（与 `_read_volume_input()` 逐字对应）")
	t.gt(float(ms.count("settings_sub = SET_SUB_MAIN")), 2.0,
		"三处把子屏复位（按 P 从外面进来 / 音量页返回 / Esc 保险丝）")
	t.ok(ms.contains("elif stage == Stage.SETTINGS:\n\t\tsub = settings_sub"),
		"`_presentation_choice()` 把子屏算进了「选择变了」的指纹"
			+ "（不算的话，从音量页退回主屏时高亮不会重置）")

	# ---- ⑤ 长按连调是**共用**的，不是两份 ----
	t.eq(ms.count("func _step_dir(delta: float) -> int:"), 1,
		"`_step_dir()` 只有一份（设置页与音量页共用同一档长按手感）")
	t.eq(ms.count("_step_dir(delta)"), 2,
		"两处步进器各调一次：共 2 次（各写一份 = 两页手感不一样）")
