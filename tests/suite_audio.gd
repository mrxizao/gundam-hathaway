class_name SuiteAudio
extends RefCounted
## 音频系统的测试。
##
## 音频最容易出的问题不是"没声音"，而是**路径写错**（load 返回 null，静默无声）和
## **该响的时候不响 / 不该响的时候一直响**。前者靠"每个音效名都真的能加载"这一条挡住；
## 后者靠下面几条行为断言挡住。


static func run(t: T, host: Node) -> void:
	t.suite("Audio / 素材完整性")
	_assets_exist(t)
	t.suite("Audio / BGM 选择")
	_bgm_choice(t)
	t.suite("Audio / 战斗曲轮流随机")
	_battle_rotation(t)
	t.suite("Audio / 主菜单曲三首轮流随机（★63-25）")
	_menu_rotation(t)
	t.suite("Audio / 仅自选战斗曲（不选不触发）")
	_opt_in_track(t)
	t.suite("Audio / 引擎音量映射")
	_engine_gain(t)
	t.suite("Audio / 引擎与座舱音挂载")
	await _engine_attach(t, host)
	t.suite("Audio / 引擎音源只认机体档案")
	await _engine_source(t, host)
	t.suite("Audio / 节流")
	await _throttle(t, host)
	t.suite("Audio / 爆炸音按距离二选一")
	await _explosion_variant(t, host)
	t.suite("Audio / 武器音效增益")
	await _weapon_gain(t, host)


static func _assets_exist(t: T) -> void:
	var missing: Array[String] = []
	for name: String in SoundBank.SFX:
		var p := SoundBank.sfx_path(name)
		if not ResourceLoader.exists(p):
			missing.append(name + " → " + p)
	t.eq(missing.size(), 0, "所有音效文件都在（缺：%s）" % str(missing))
	t.gt(SoundBank.SFX.size(), 18, "音效表登记了 %d 条" % SoundBank.SFX.size())

	var bgm_missing: Array[String] = []
	for name: String in SoundBank.BGM:
		var p := SoundBank.bgm_path(name)
		if not ResourceLoader.exists(p):
			bgm_missing.append(name + " → " + p)
	t.eq(bgm_missing.size(), 0, "所有 BGM 文件都在（缺：%s）" % str(bgm_missing))

	# 战斗随机池必须是 BGM 表里真实存在的条目
	for track: String in SoundBank.BATTLE_TRACKS:
		t.ok(SoundBank.BGM.has(track), "战斗曲目 %s 在 BGM 表里" % track)
	# ⚠️ **写死名单/首数是有意的**：池子少一首（素材复制进来了但忘了登记）
	# 不会报任何错，只会"某首曲子永远放不到" —— 那种 bug 靠听是听不出来的。
	# 沿革：1.1 把 閃光 从结算挪进战斗轮换（4 首）；
	#       2026-09-21 老板追加 **car5p3 / PENELOPE** 与 **MNE**（6 首）。
	t.eq(SoundBank.BATTLE_TRACKS.size(), 6,
		"战斗曲目为六首（TRACER / NDA-α / XI / 閃光 / car5p3 / MNE）")
	t.eq(SoundBank.STORY_BATTLE_TRACKS.size(), 5, "剧情战斗曲五首（不含閃光）")
	for want: String in ["car5p3", "mne"]:
		t.ok(SoundBank.BGM.has(want), "新曲 %s 在 BGM 表里" % want)
		t.ok(SoundBank.BATTLE_TRACKS.has(want), "新曲 %s 进了**对战**战斗轮换" % want)
		# 两首新曲**两套池子都进**：只有 senkou 有"留给太平洋结算"这层身份。
		t.ok(SoundBank.STORY_BATTLE_TRACKS.has(want),
			"新曲 %s 也进了**剧情**战斗轮换（它不是閃光那种「留给结算」的特例）" % want)

	# 循环标记
	t.ok(SoundBank.is_looping("cruise_xi"), "柯西巡航声是循环音")
	t.ok(SoundBank.is_looping("cruise_penelope"), "佩涅罗佩巡航声是循环音")
	t.not_ok(SoundBank.is_looping("beam_rifle"), "光束步枪是一次性音")


static func _bgm_choice(t: T) -> void:
	# ★63-25（用户 2026-10-08）：「EARth 和 Snooze 添加到主菜单歌曲内，和现在的主菜单
	# 歌曲三首随机循环播放」⇒ 菜单曲从"写死 mobius"变成"三首洗牌袋轮换"。
	# ⚠️ 所以这条**不再断言具体是哪一首**（那是一次有副作用的抽取）。
	# 它原来钉的是"菜单曲 = Möbius"这个**数据**；现在那个位置的**结构**变了，
	# 判据也跟着换成"落在菜单池里"。整轮的轮换数学在 `_menu_rotation` 那一节。
	var mv := Audio.bgm_name(Audio.Bgm.MENU)
	t.ok(SoundBank.MENU_TRACKS.has(mv), "主菜单 BGM 取自菜单池（%s）" % mv)
	t.eq(Audio.result_track_for(MapDef.Id.ULURU, false), "sweet_child", "艾尔斯岩的结算曲 = Sweet Child O' Mine")
	t.eq(Audio.result_track_for(MapDef.Id.PACIFIC, false), "senkou", "太平洋上空的结算曲 = 閃光")
	t.eq(Audio.result_track_for(MapDef.Id.RANGE, false), "sweet_child", "靶场（训练）的结算曲 = Sweet Child O' Mine")
	t.eq(Audio.result_track_for(MapDef.Id.PACIFIC, true), "special_result", "这一局用过閃光当战斗曲 → 特殊结算曲（哪怕在太平洋）")
	# ⚠️ ★ 剧情模式轮 B2：低地球轨道。DESIGN §4.8.5 的坑 2 说 `result_track_for()`
	# 对**未知 id 静默返回 `"senkou"`**，而轨道图是后加的 ⇒ 它会"悄悄"用閃光。
	# 设计稿把处置列成待拍板（接受 / 加一行）。**已拍板：接受** —— M03 是柯西（Ξ）
	# **第一次登场**的那一关（轮 52 之后玩家开的是梅萨指挥官型上去接它），
	# 閃光正是那台机体的曲子。下面这条把"接受"从**默认**变成**决定**：
	# 将来谁给轨道图换曲子而忘了同步这里，会红。
	t.eq(Audio.result_track_for(MapDef.Id.LEO, false), "senkou",
		"★ 轨道图走既有兜底 ⇒ 閃光（§4.8.5 坑 2 的处置：**接受**）")
	t.ok(ResourceLoader.exists(SoundBank.bgm_path("special_result")), "特殊结算曲素材在工程里")
	t.not_ok(SoundBank.STORY_BATTLE_TRACKS.has("senkou"), "剧情挑战的战斗轮换**不含**閃光（用户点名）")
	t.ok(SoundBank.BATTLE_TRACKS.has("senkou"), "对战模式的战斗轮换含閃光")
	t.eq(Audio.bgm_name(Audio.Bgm.TRAINING), "sweet_child", "训练场 BGM 与结算同一首（1.1）")

	# 战斗曲目必须在三首里，且连续两次不重复
	var a := Audio.bgm_name(Audio.Bgm.BATTLE)
	var b := Audio.bgm_name(Audio.Bgm.BATTLE)
	t.ok(SoundBank.BATTLE_TRACKS.has(a), "战斗 BGM 取自战斗曲池（%s）" % a)
	t.ok(SoundBank.BATTLE_TRACKS.has(b), "战斗 BGM 取自战斗曲池（%s）" % b)
	t.ok(a != b, "连续两次战斗 BGM 不重复（%s / %s）" % [a, b])
	t.eq(Audio.bgm_name(Audio.Bgm.NONE), "", "NONE 没有曲目")

	# ★63-25：菜单曲**不再循环** —— 三首随机轮换，靠 `finished` 换下一首。
	# ⚠️ 这是本批**唯一一处语义反转**的断言（原文是"菜单 BGM 被设为循环播放"）。
	# 它原来是 `load(路径)` 上读 `loop` —— 那条读法现在也**失效**了：
	# ★63-25 起 `play_bgm()` 只在需要改 loop 时才**复制**，改的是副本，
	# ⇒ `load(path).loop` 不再是"这次会怎么播"的读数。要问那个，读
	# **播放器持有的那一份**（`suite_mission_bgm` 早就是按这个口径写的）。
	Audio.play_bgm(Audio.Bgm.MENU, 0.0)
	var cur: AudioStream = Audio._bgm_players[Audio._bgm_active].stream
	t.ok(cur != null, "菜单 BGM 能加载")
	t.ok(ResourceLoader.exists(SoundBank.bgm_path("mobius")),
		"菜单池的老成员 mobius 素材还在工程里")
	t.not_ok(Audio._loop_of(cur),
		"★★ 菜单曲**不循环** —— 循环的曲子永远不发 finished，三首轮换会彻底失效")

	var ce := Audio._stream("beam_rifle", false)
	t.ok(ce != null, "一次性音效可以加载")
	t.ok(Audio._stream("cruise_xi", true) != null, "循环音效可以加载")


## 战斗曲**轮流随机**播放（用户要求；1.1 从三首变四首）。
##
## 三条不变量：
##   1. 一轮内每首各出现一次（"轮流"，而不是"随机 N 选一"可能连着重复）；
##   2. 跨轮边界不重复（新一轮的第一首 ≠ 上一轮的最后一首）；
##   3. 一首放完（`finished`）会自动换下一首，而且**只在战斗期间** ——
##      回菜单 / 进结算之后，正在淡出的战斗曲放完不能把新曲子顶掉。
static func _battle_rotation(t: T) -> void:
	# ⚠️ 这里**不能写 `size() == N`**：这个函数的重点是"轮换数学用的池子"
	# 就是 `SoundBank` 里那一个（而不是各自复制一份名单）。所以直接比**集合**，
	# 顺序无关 —— 曲池顺序是随意的，名单少一首/多一首才是 bug。
	var want_pool := ["tracer", "nda_alpha", "xi", "senkou", "car5p3", "mne"]
	want_pool.sort()
	var got_pool: Array = SoundBank.BATTLE_TRACKS.duplicate()
	got_pool.sort()
	t.eq(got_pool, want_pool, "战斗曲池 = 那六首（集合一致，顺序无关）")

	# ---- 洗牌袋的纯函数部分（可复现：随机源自己给）----
	# 抽 3 轮（3 × 曲池大小）而不是写死 9 次：曲池从三首变四首时，
	# 写死的 9 会被"3 整除"这个假设带偏（1.1 就是这么失败了一次）。
	var pool := SoundBank.BATTLE_TRACKS.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260918
	var queue: Array = []
	var last := ""
	var picks: Array[String] = []
	for i in pool * 3:
		var pick := Audio.bag_next(queue, last, SoundBank.BATTLE_TRACKS, rng)
		picks.append(pick)
		last = pick

	var expected := SoundBank.BATTLE_TRACKS.duplicate()
	expected.sort()
	var repeat_next := false
	var every_round_complete := true
	for i in picks.size():
		if i > 0 and picks[i] == picks[i - 1]:
			repeat_next = true
		if i % pool == pool - 1:
			var round_tracks: Array = []
			for k in range(i - pool + 1, i + 1):
				round_tracks.append(picks[k])
			round_tracks.sort()
			every_round_complete = every_round_complete and round_tracks == expected
	t.not_ok(repeat_next, "轮换不会连着放同一首（%d 次抽取）" % picks.size())
	t.ok(every_round_complete, "每 %d 首正好是完整的一轮（曲池各一次）：%s" % [pool, str(picks)])

	# ---- 真信号驱动的自动换曲 ----
	Audio.play_bgm(Audio.Bgm.BATTLE, 0.0)
	var first := Audio.current_bgm_track()
	t.ok(SoundBank.BATTLE_TRACKS.has(first), "战斗 BGM 取自战斗曲池（%s）" % first)
	# 战斗曲**必须不循环**：循环的曲子永远不会发 finished，也就永远等不到下一首
	t.not_ok(_loops(Audio._bgm_players[Audio._bgm_active].stream),
		"战斗曲不循环（这是「轮流播放」成立的前提）")

	Audio._bgm_players[Audio._bgm_active].finished.emit()
	var second := Audio.current_bgm_track()
	t.eq(Audio.current_bgm(), Audio.Bgm.BATTLE, "放完一首之后仍然是战斗 BGM")
	t.ok(second != "" and second != first,
		"一首放完会自动换到另一首（%s → %s）" % [first, second])

	# ---- 守卫：离开战斗之后不许再自动换曲 ----
	Audio.play_bgm(Audio.Bgm.RESULT, 0.0)
	var result_track := Audio.current_bgm_track()
		# 放过战斗曲之后，结算曲由"这一局用过閃光吗 + 当前地图"共同决定（1.2 规则）
	var want := Audio.result_track_for(
		Game.active_map.id if Game.active_map != null else MapDef.Id.PACIFIC, Audio._senkou_used)
	t.eq(result_track, want, "结算曲符合规则（用过閃光=%s）" % str(Audio._senkou_used))
	Audio._bgm_players[Audio._bgm_active].finished.emit()
	t.eq(Audio.current_bgm(), Audio.Bgm.RESULT, "结算期间收到 finished 不会把结算曲顶掉")
	t.eq(Audio.current_bgm_track(), result_track, "结算曲没有被换成战斗曲")


## ★63-25：**主菜单曲三首随机循环**。
##
## 用户 2026-10-08：「EARth 和 Snooze 添加到主菜单歌曲内，和现在的主菜单歌曲
## 三首随机循环播放」。
##
## 与 `_battle_rotation` 同构（共用 `bag_next()` 那套洗牌袋数学），但**袋子必须分开**。
## 所以这一节除了"轮换数学对不对"，还要钉"两套轮换互不消耗" ——
## 那是本批最容易写错、而且**错了完全不报错**的一处（症状只是"随机听起来怪"）。
##
## ⚠️ 本套件证的是**结构 + 接线 + 数学**；"真的解码、真的自然放完"那一半由
## 真机探针 `tools/_r63_25_menu_bgm.tscn` 出（headless 是 Dummy 驱动，混音不推进）。
## `finished` 驱动的换曲在这里用 `finished.emit()` 就能驱动 —— `_battle_rotation` 早就这么写。
static func _menu_rotation(t: T) -> void:
	# ---- 结构：池子就是三首，而且每首都真的能加载 ----
	# ⚠️ 首数**写死 3** 是**有意**的：用户原话就是"三首"。池子少一首（素材在盘上但忘了登记）
	# 不会报任何错，只会"某首曲子永远放不到" —— 那种 bug 靠听是听不出来的。
	t.eq(SoundBank.MENU_TRACKS.size(), 3, "主菜单曲池 = 三首（用户原话「三首随机循环播放」）")
	for k: String in SoundBank.MENU_TRACKS:
		t.ok(SoundBank.BGM.has(k), "菜单曲 %s 在 BGM 表里" % k)
		t.ok(ResourceLoader.exists(SoundBank.bgm_path(k)), "菜单曲 %s 素材在工程里" % k)
	# 用户点名的那三首（mobius = 原本就有的主菜单曲，另两首是本批加的）
	for k: String in ["mobius", "earth_nt", "snooze"]:
		t.ok(SoundBank.MENU_TRACKS.has(k),
			"★63-25 点名的这一首在菜单池里：%s（Möbius / EARth / Snooze）" % k)

	# ---- 反向：三首都不许混进**战斗轮换池** ----
	# 混进去会被战斗洗牌袋自动抽到 ⇒ 玩家在战斗里听到一首本不该出现在战斗里的曲子，
	# 而且**不报错**（与 `OPT_IN_BATTLE_TRACKS` 那条纪律同族）。
	for k: String in SoundBank.MENU_TRACKS:
		t.not_ok(SoundBank.BATTLE_TRACKS.has(k), "菜单曲 %s 不在对战轮换池里" % k)
		t.not_ok(SoundBank.STORY_BATTLE_TRACKS.has(k), "菜单曲 %s 不在剧情轮换池里" % k)
	t.not_ok(SoundBank.is_battle_pick("mobius"),
		"mobius 不是合法战斗自选值（它只属于菜单）")
	# ⚠️ 而 EARth / Snooze **是**合法战斗自选值 —— 这个**双用途是有意的**。
	# 钉住它是为了将来谁"顺手把菜单曲从自选表里一起删掉"时能红。
	t.ok(SoundBank.is_battle_pick("earth_nt") and SoundBank.is_battle_pick("snooze"),
		"EARth / Snooze 同时是合法战斗自选值（双用途是有意的，别顺手删掉）")

	# ---- 每个用途该不该循环（纯函数，逐档钉）----
	# 这张表是"三首随机循环"的**前提**：菜单曲若循环 ⇒ 永远不发 finished ⇒ 换不了下一首。
	t.not_ok(Audio.bgm_should_loop(Audio.Bgm.MENU), "菜单曲不循环（靠 finished 换下一首）")
	t.not_ok(Audio.bgm_should_loop(Audio.Bgm.BATTLE, false), "战斗曲不循环（靠 finished 轮换）")
	t.ok(Audio.bgm_should_loop(Audio.Bgm.BATTLE, true), "战斗曲**锁曲时**循环（一关就这一首）")
	t.ok(Audio.bgm_should_loop(Audio.Bgm.RESULT), "结算曲循环（用户没要求改）")
	t.ok(Audio.bgm_should_loop(Audio.Bgm.TRAINING), "训练场曲循环（同上）")

	# ---- 轮换数学：与战斗曲同一套，跑 3 轮 ----
	var n := SoundBank.MENU_TRACKS.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	var queue: Array = []
	var last := ""
	var picks: Array[String] = []
	for i in n * 3:
		var pk := Audio.bag_next(queue, last, SoundBank.MENU_TRACKS, rng)
		picks.append(pk)
		last = pk
	var expect := SoundBank.MENU_TRACKS.duplicate()
	expect.sort()
	var repeat_next := false
	var complete := true
	for i in picks.size():
		if i > 0 and picks[i] == picks[i - 1]:
			repeat_next = true
		if i % n == n - 1:
			var rnd: Array = []
			for k in range(i - n + 1, i + 1):
				rnd.append(picks[k])
			rnd.sort()
			complete = complete and rnd == expect
	t.not_ok(repeat_next, "菜单曲轮换不会连着放同一首（%d 次抽取）" % picks.size())
	t.ok(complete, "每 %d 首正好是完整的一轮（菜单池各一次）：%s" % [n, str(picks)])

	# ---- ★ 菜单**自己的入口**也走同一套轮换（写负对照时才发现的盲区）----
	# ⚠️ 上面那段数学证的是 `bag_next()` 这个**纯函数**，它**不**证明菜单真的在用它。
	# 把 `_next_menu_track()` 改成"每次抽之前先清袋"、或者"忘了把上一首传进去"，
	# 上面那段照样全绿 —— 而症状恰恰就是用户点名要的那个"轮流"没了
	#（可能连着放同一首 / 一轮里同一首出现两次），**且不报任何错**。
	# ⇒ 这里从**菜单自己的入口**（`bgm_name(Bgm.MENU)`）连抽 3 轮再钉一遍。
	#   （负对照变体 I 就是干这个的：它必须让下面这几条变红。）
	Audio._menu_bag.clear()
	Audio._last_menu_track = ""
	var mpicks: Array[String] = []
	for i in n * 3:
		mpicks.append(Audio.bgm_name(Audio.Bgm.MENU))
	var m_in_pool := true
	var m_repeat := false
	var m_complete := true
	for i in mpicks.size():
		if not SoundBank.MENU_TRACKS.has(mpicks[i]):
			m_in_pool = false
		if i > 0 and mpicks[i] == mpicks[i - 1]:
			m_repeat = true
		if i % n == n - 1:
			var rnd2: Array = []
			for k in range(i - n + 1, i + 1):
				rnd2.append(mpicks[k])
			rnd2.sort()
			m_complete = m_complete and rnd2 == expect
	t.ok(m_in_pool, "菜单入口抽到的每一首都在菜单池里：%s" % str(mpicks))
	t.not_ok(m_repeat, "★ 菜单入口连抽 %d 次不会连着放同一首（含跨轮边界）" % mpicks.size())
	t.ok(m_complete, "★ 菜单入口连抽 %d 次：每 %d 首正好是完整的一轮：%s"
		% [mpicks.size(), n, str(mpicks)])
	t.eq(Audio._last_menu_track, mpicks[mpicks.size() - 1],
		"……而且「上一首菜单曲」记的是最后一次抽到的那首（跨轮边界靠它去重）")

	# ---- 真信号驱动的自动换曲（与 `_battle_rotation` 同一手法）----
	Audio.play_bgm(Audio.Bgm.MENU, 0.0)
	var first := Audio.current_bgm_track()
	t.ok(SoundBank.MENU_TRACKS.has(first), "真放的第一首取自菜单池（%s）" % first)
	t.not_ok(Audio._loop_of(Audio._bgm_players[Audio._bgm_active].stream),
		"★★ 菜单曲不循环（这是「三首随机循环」成立的前提）")

	Audio._bgm_players[Audio._bgm_active].finished.emit()
	var second := Audio.current_bgm_track()
	t.eq(Audio.current_bgm(), Audio.Bgm.MENU, "放完一首之后仍然是主菜单")
	t.ok(second != "" and second != first,
		"一首放完会自动换下一首（%s → %s）" % [first, second])

	# ---- 守卫：换到别的场景之后，收到的 finished 不许把新曲子顶掉 ----
	# ⚠️ 这是 `_on_bgm_finished` 里那个 `_bgm_kind` 判定的意义：正在淡出的菜单曲
	# 也会自然结束，那时绝不能让菜单轮换把结算曲顶掉（反之亦然）。
	Audio.play_bgm(Audio.Bgm.RESULT, 0.0)
	var res := Audio.current_bgm_track()
	Audio._bgm_players[Audio._bgm_active].finished.emit()
	t.eq(Audio.current_bgm(), Audio.Bgm.RESULT,
		"结算期间收到 finished 不会把结算曲顶掉（更不会换成菜单曲）")
	t.eq(Audio.current_bgm_track(), res, "……而且曲子一个字没变")

	# ---- 两套轮换**互不消耗**（本批最容易写错的一处：共用一个袋子）----
	# ⚠️⚠️ **先给两个袋子都装满是必须的** —— 这是负对照变体 H 逼出来的：
	#   若快照时袋子刚好是空的，下面"抽 3 次"会先 refill 再抽干、**又回到空的**，
	#   于是 `t.eq(bag, 快照)` 两边都是 `[]` ⇒ **恒真**（看起来是绿的，其实什么都没证）。
	#   装满之后再抽 3 次，袋子必然变化 ⇒ 这条断言才有牙（NC 变体 H / L 就是它的牙）。
	# ⚠️⚠️ 快照**必须**用 `.duplicate()`，**不能**用 `Array(x)`：
	#   GDScript 里 `Array(x)` **不是拷贝、是同一个引用**（实测 `is_same:true`，
	#   见 tools/_scratch_array_semantics.gd 的四组读数）。用 `Array(x)` 的话袋子一被
	#   `clear()` / `pop_front()` 改动，快照跟着一起变 ⇒ `t.eq(袋, 快照)` **恒真**，
	#   负对照变体 H / L 只能咬中一半（就是栽在这里）。
	Audio._battle_bag = SoundBank.BATTLE_TRACKS.duplicate()
	Audio._last_battle_track = ""
	var bbag: Array = Audio._battle_bag.duplicate()
	var blast: String = Audio._last_battle_track
	for i in 3:
		Audio.bgm_name(Audio.Bgm.MENU)
	t.eq(Audio._battle_bag, bbag, "★★ 连抽 3 首菜单曲之后，**战斗**袋子一个元素都没少")
	t.eq(Audio._last_battle_track, blast, "……「上一首战斗曲」也没被动过")

	Audio._menu_bag = SoundBank.MENU_TRACKS.duplicate()
	Audio._last_menu_track = ""
	var mbag: Array = Audio._menu_bag.duplicate()
	var mlast: String = Audio._last_menu_track
	for i in 3:
		Audio.bgm_name(Audio.Bgm.BATTLE)
	t.eq(Audio._menu_bag, mbag, "★★ 反过来：连抽 3 首战斗曲，**菜单**袋子一个元素都没少")
	t.eq(Audio._last_menu_track, mlast, "……「上一首菜单曲」也没被动过")

	# 还原（autoload 是各套件共用的）：停在菜单态，与 `_bgm_choice` 的收尾一致
	Audio.play_bgm(Audio.Bgm.MENU, 0.0)


## 「**不选不触发**」的战斗曲（`SoundBank.OPT_IN_BATTLE_TRACKS`）。
##
## 用户 2026-09-27：「把 Sweet Child O' Mine 也加入战斗音乐自选里面（玩家不选他不触发）」。
##
## 这句话是**两个方向**，必须都钉住 —— 只做一边等于没做：
##   ① **选了要能播**：光把它加进菜单列表、而播放端的闸门不认它
##      （旧代码是 `battle_pool.has()`，而它按设计不在任何池子里）⇒
##      菜单上选得中、进游戏却放不出来，**一行报错都没有**；
##   ② **不选绝不触发**：顺手塞进 `BATTLE_TRACKS` 就省事了？
##      那它会被洗牌袋自动抽到，玩家一场没选就先听到它 —— 正是括号里禁止的。
##
## 所以 ② 的判据不能只查"表里没有"，得**真让洗牌袋抽若干轮**去证明。
static func _opt_in_track(t: T) -> void:
	# ---- 结构：仅自选曲与两个轮换池**互斥** ----
	t.gt(SoundBank.OPT_IN_BATTLE_TRACKS.size(), 0, "仅自选曲表非空")
	t.ok(SoundBank.OPT_IN_BATTLE_TRACKS.has("sweet_child"),
		"Sweet Child O' Mine 登记为仅自选曲")
	var clash: Array[String] = []
	for k: String in SoundBank.OPT_IN_BATTLE_TRACKS:
		if SoundBank.BATTLE_TRACKS.has(k) or SoundBank.STORY_BATTLE_TRACKS.has(k):
			clash.append(k)
	t.eq(clash.size(), 0,
		"仅自选曲**不在任何轮换池里**（混进去就会自动轮播，违背「不选不触发」）：%s" % str(clash))
	for k: String in SoundBank.BATTLE_TRACKS:
		t.not_ok(SoundBank.is_opt_in_battle_track(k), "轮换池曲 %s 不是仅自选曲" % k)

	# ---- 素材与显示名 ----
	t.ok(SoundBank.BGM.has("sweet_child"), "sweet_child 在 BGM 表里")
	t.ok(ResourceLoader.exists(SoundBank.bgm_path("sweet_child")),
		"Sweet Child O' Mine 素材在工程里")
	t.eq(SoundBank.battle_track_label("sweet_child"), "Sweet Child O' Mine",
		"菜单显示名是曲名（显示成键名玩家认不出来）")
	# ★63-22（用户 2026-10-08：「把（仅自选，不参与随机）去掉」）：
	# 这里原来钉着 `battle_track_note()` 的两条（"仅自选曲带标记 / 轮换池曲没有"）。
	# 那个函数已**彻底删除**（留空壳会让"菜单不再印后缀"那条判据变成恒真，
	# 见 `sound_bank.gd` 里删掉它时写的说明），所以这两条**随函数一起删** ——
	# 留着就是编译错误，不是可选的清理。
	# ⇒ 那两条钉的"两类曲的可见差异"**没有留下空洞**，换了载体继续钉：
	#   · `suite_settings`：「菜单里不再出现 `battle_track_note`」+「不再出现那个后缀字面量」；
	#   · `suite_bgm_playlist`：「选歌页/歌单页的 `◆` 标记仍然区分两类曲」。
	# （刻意**不在这里补一条"仅自选表非空"** —— 本函数开头第 200 行已经有了，
	#   重复一条只是让条数看起来好看，不是判据。）

	# ---- 自选序列 = 轮换池 + 仅自选曲（四个消费方共用这一份）----
	var picks: Array = SoundBank.battle_pick_tracks()
	t.eq(picks.size(), SoundBank.BATTLE_TRACKS.size() + SoundBank.OPT_IN_BATTLE_TRACKS.size(),
		"自选序列 = 轮换池 + 仅自选曲")
	var head_ok := true
	for i in SoundBank.BATTLE_TRACKS.size():
		if str(picks[i]) != str(SoundBank.BATTLE_TRACKS[i]):
			head_ok = false
	t.ok(head_ok, "自选序列**前缀**与轮换池同序（老玩家背下来的顺序不变）")
	t.eq(str(picks[picks.size() - 1]), "sweet_child", "仅自选曲排在末尾")
	t.ok(SoundBank.is_battle_pick("sweet_child") and SoundBank.is_battle_pick("tracer"),
		"is_battle_pick 认轮换池与仅自选曲两类")
	t.not_ok(SoundBank.is_battle_pick("no_such_track"), "野键名不算合法自选值")

	# ---- 行为侧（真调 AudioDirector，测完原样还回去）----
	# ⚠️ `.duplicate()` 不是风格问题：`Array(x)` 是引用 ⇒ 下面 `_battle_bag.clear()` 会
	#    连着把"备份"一起清掉，还原写回的是个空袋。见 suite_audio.gd 同款注释。
	var bag_backup: Array = Audio._battle_bag.duplicate()
	var last_backup: String = Audio._last_battle_track
	var senkou_backup: bool = Audio._senkou_used
	var pool_backup: Array = Audio.battle_pool
	var req_backup: String = Audio.requested_battle_open

	# ① 选了要能播 —— **两套池子下都得能播**（它不进池，池里有没有它无关）
	var pools: Array = [SoundBank.BATTLE_TRACKS, SoundBank.STORY_BATTLE_TRACKS]
	for pool: Array in pools:
		Audio.battle_pool = pool
		Audio._battle_bag.clear()
		Audio._last_battle_track = ""
		Audio._senkou_used = false
		Audio.request_battle_open("sweet_child")
		t.eq(Audio.bgm_name(Audio.Bgm.BATTLE), "sweet_child",
			"选中的仅自选曲 = 本场第一首（池子里没有它也必须放得出）")
		# ⚠️ 「用过閃光」这条必须紧跟**开场那一次**断言：下一行开始抽洗牌袋，
		# 而袋子里**真的**有 senkou —— 放到后面再断言就是拿"第二首"去怪"第一首"。
		t.not_ok(Audio._senkou_used, "选的是 sweet_child，不该置「用过閃光」标记")
		t.eq(Audio.requested_battle_open, "", "请求只消费一次（不影响后面几首）")
		var nxt: String = Audio.bgm_name(Audio.Bgm.BATTLE)
		t.ok(pool.has(nxt), "第二首回到洗牌袋（%s）" % nxt)
		t.not_ok(nxt == "sweet_child", "第二首不会又是仅自选曲（它不在袋子里）")

	# ② 不选就绝不触发 —— 洗牌袋**真抽 5 轮**，一次都不许出现
	Audio.battle_pool = SoundBank.BATTLE_TRACKS
	Audio._battle_bag.clear()
	Audio._last_battle_track = ""
	Audio._senkou_used = false
	Audio.request_battle_open("")   # = 设置页的「随机」
	var drawn: Array[String] = []
	for i in SoundBank.BATTLE_TRACKS.size() * 5:
		drawn.append(Audio.bgm_name(Audio.Bgm.BATTLE))
	t.not_ok(drawn.has("sweet_child"),
		"**玩家不选 ⇒ 抽 %d 次一次都不出现**（本轮需求的核心判据）" % drawn.size())
	var all_pool := true
	for d: String in drawn:
		if not SoundBank.BATTLE_TRACKS.has(d):
			all_pool = false
	t.ok(all_pool, "随机抽到的每一首都还在轮换池里（池子没被悄悄改宽）")

	# ---- 还原 ----
	Audio._battle_bag = bag_backup
	Audio._last_battle_track = last_backup
	Audio.requested_battle_open = req_backup
	if pool_backup == SoundBank.STORY_BATTLE_TRACKS:
		Audio.set_story_mode(true)
	else:
		Audio.set_story_mode(false)
	Audio._senkou_used = senkou_backup


## 这个 stream 是不是循环的。
## ⚠️ 实现直接转 `Audio._loop_of()`：★63-25 起"循环与否"有了**唯一真源**
##（`play_bgm()` 的惰性复制要拿它当判据）。这里再抄一份 if-else 迟早会和它分叉
## —— 例如将来加了第四种载体，改了一处、另一处静默走错分支。
static func _loops(s: AudioStream) -> bool:
	return Audio._loop_of(s)


static func _engine_gain(t: T) -> void:
	t.near(FlightBody.engine_gain(0.0, 420.0), 0.05, 0.0001, "速度为 0 时引擎音量是 5%")
	t.near(FlightBody.engine_gain(420.0, 420.0), 1.0, 0.0001, "满速时引擎音量是 100%")
	t.near(FlightBody.engine_gain(210.0, 420.0), 0.525, 0.001, "半速时约在中间")
	t.near(FlightBody.engine_gain(800.0, 420.0), 1.0, 0.0001, "超过上限也不会超过 100%")
	t.near(FlightBody.engine_gain(0.0, 0.0), 0.05, 0.0001, "上限为 0 时兜底为 5%")
	# 单调递增
	var prev := -1.0
	var monotonic := true
	for i in 21:
		var g := FlightBody.engine_gain(420.0 * float(i) / 20.0, 420.0)
		if g < prev - 0.0001:
			monotonic = false
		prev = g
	t.ok(monotonic, "音量随速度单调递增")


## 引擎循环音的挂载规则：
##   - 玩家自己的引擎**没有距离衰减**（在座舱里，不是世界里的声源）
##   - 敌机的引擎有距离衰减 —— "靠近了才听得到"就是靠它
##   - 柯西座舱检测音只有"玩家开柯西"才有
static func _engine_attach(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	var xi_player := _unit(c, SuitProfile.xi(), true)
	var pen_foe := _unit(c, SuitProfile.penelope(), false)

	var xi_engine := _find_engine(xi_player)
	var pen_engine := _find_engine(pen_foe)
	t.ok(xi_engine != null, "柯西机体挂了引擎循环音")
	t.ok(pen_engine != null, "佩涅罗佩机体挂了引擎循环音")
	if xi_engine != null:
		t.eq(xi_engine.attenuation_model, AudioStreamPlayer3D.ATTENUATION_DISABLED,
			"玩家自己的引擎不做距离衰减")
		t.ok(xi_engine.stream != null, "玩家引擎有音频流")
		t.ok(xi_engine.playing, "引擎循环已经在播")
		# 循环必须真的设在**播放器持有的那个流**上。
		# 注意不能去 load(路径) 上查：循环版是复制一份再设 loop 的（故意的，
		# 否则会把同一份资源的一次性用法也变成循环），原始资源仍然是未循环的。
		var es := xi_engine.stream
		var looped := false
		if es is AudioStreamMP3:
			looped = (es as AudioStreamMP3).loop
		elif es is AudioStreamOggVorbis:
			looped = (es as AudioStreamOggVorbis).loop
		t.ok(looped, "引擎循环音被设为循环播放")
	if pen_engine != null:
		t.eq(pen_engine.attenuation_model, AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE,
			"敌机引擎有距离衰减（靠近了才听得到）")

	# 座舱检测音：玩家开柯西 → 有；其余 → 没有
	t.ok(_has_detect(xi_player), "玩家开柯西时有座舱巡航检测音")
	t.not_ok(_has_detect(pen_foe), "敌机（非玩家）没有座舱检测音")

	var pen_player := _unit(c, SuitProfile.penelope(), true)
	t.not_ok(_has_detect(pen_player), "玩家开佩涅罗佩时没有柯西的座舱检测音")

	c.free()
	await host.get_tree().process_frame
	Game.reset()


## 引擎音源**只有机体档案一个真源**（`SuitProfile.engine_sound`）。
##
## ⚠️ 这一节是 2026-09-25 补的，起因是一次**死字段**：
## 取音源的那一行原来是
## `"cruise_xi" if profile.id == SuitProfile.Id.XI else "cruise_penelope"`，
## 而阿利宙斯的档案里**早就写着** `engine_sound = "cruise_xi"`（用户此前指定过）——
## 字段写了、全场没有任何一处读它，于是阿利宙斯一直发的是佩涅罗佩那条循环音。
## 用户这一轮报的就是这个：「把阿利宙斯巡航模式的音效换成和柯西一样的」。
##
## 所以这里钉两件事，**缺一不可**：
##   ① **数据**：每台机档案里的 `engine_sound` 都得在 `SoundBank.LOOPING` 里。
##      填了个不循环的 ⇒ 引擎播一遍之后永久静音，而且 `stream` 非空、`playing` 还是
##      true，**不报任何错** —— 静音是最难查的一类故障。
##   ② **真路径**：造真机体，读它引擎播放器上**真正挂着的那个流**。
##      只有 ① 是抓不住死字段的 —— 档案一直是对的，错的是取用方；
##      这条断言的存在理由就是"让档案与实物不许分叉"。
## ② 比的是**对象同一性**：`Audio._stream()` 按名字缓存，所以"同一条音源"
## 必然返回同一个实例，不需要任何容差（比时长、比路径都更钝）。
static func _engine_source(t: T, host: Node) -> void:
	# ---- ① 数据：档案里写的都必须是循环音 ----
	var bad: Array[String] = []
	var suits: Array[SuitProfile] = [
		SuitProfile.xi(),
		SuitProfile.penelope(),
		SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE),
		SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL),
		SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU),
		SuitProfile.messer_m01(),
	]
	for p: SuitProfile in suits:
		if not SoundBank.is_looping(p.engine_sound):
			bad.append("%s → %s" % [p.display_name, p.engine_sound])
	t.eq(bad.size(), 0, "每台机档案里的 `engine_sound` 都是循环音（异常：%s）" % str(bad))
	t.eq(SuitProfile.xi().engine_sound, "cruise_xi", "柯西用的是柯西那条")
	t.eq(SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).engine_sound, "cruise_xi",
		"阿利宙斯**巡航形态**的引擎音就是柯西那一条（用户 2026-09-25 指定）")
	t.eq(SuitProfile.penelope().engine_sound, "cruise_penelope", "佩涅罗佩仍旧用自己那条")
	t.eq(FlightBody.ENGINE_SOUND_DEFAULT, SuitProfile.new().engine_sound,
		"兜底常量与档案默认值一致（%s）—— 不一致的话\"哪个是默认\"就得靠猜"
			% FlightBody.ENGINE_SOUND_DEFAULT)

	# ---- ★ 家族规则（轮 49 · 2026-09-30 用户口径）----
	#
	# 用户：「把除了佩涅罗佩以外的机体的巡航声都使用成柯西的引擎声 ——
	#        因为佩涅罗佩的巡航声过于独特，只能这样使用。」
	# ⇒ 规则**不是"哪台机写了个什么值"**，而是一条**家族规则**：
	#     `id == PENELOPE` ⇒ `cruise_penelope`；**其余一律** `cruise_xi`。
	#
	# ★ 这里**枚举 `Id` 全体 + 每个 id 的全部形态**，而不是手写一张机体名单：
	#   以后加新机体时，只要它没被点名成例外，就必须落在 `cruise_xi` 上。
	#   ⚠️ 手写名单的失效方式是**静默**的 —— 新机不在名单里，这条断言照样绿。
	var off_rule: Array[String] = []
	var ids: Array[int] = [
		SuitProfile.Id.XI, SuitProfile.Id.PENELOPE, SuitProfile.Id.ARIZEUS,
		SuitProfile.Id.GUSTAV00, SuitProfile.Id.MESSER_M01,
		SuitProfile.Id.MESSER_CMD, SuitProfile.Id.MESSER_F01,
	]
	var forms_seen := 0
	# ⚠️ 运行器**只在失败时**打标签 ⇒ 要人复核的读数必须在这里显式 `print()` ——
	#    否则"规则全绿"这句话在日志里看不到任何证据。
	var rows: Array[String] = []
	for id: int in ids:
		var multi := SuitProfile.forms_of(id).size() > 1
		for form: int in SuitProfile.forms_of(id):
			var sp: SuitProfile = SuitProfile.by_id_form(id, form)
			forms_seen += 1
			var want := "cruise_penelope" if id == SuitProfile.Id.PENELOPE else "cruise_xi"
			rows.append("%s%s=%s" % [sp.display_name,
				("(形态%d)" % form) if multi else "", sp.engine_sound])
			if sp.engine_sound != want:
				off_rule.append("%s(形态 %d) → %s（应为 %s）"
					% [sp.display_name, form, sp.engine_sound, want])
	print("  [表] 全部 %d 份档案的巡航声：%s"
		% [forms_seen, ", ".join(PackedStringArray(rows))])
	t.eq(ids.size(), 7, "枚举覆盖 `SuitProfile.Id` 全部 7 个（新增机体时要同步这里）")
	# 7 个 Id，其中只有阿利宙斯有 3 个形态（CRUISE / NORMAL / CORE_NU）⇒ 6 + 3 = 9。
	# 写死这个数是有意的（本文件对 `BATTLE_TRACKS` 也是这个写法）：形态表被改动时
	# 必须有人来确认一次"新形态的引擎音也想清楚了吗"。
	t.eq(forms_seen, 9, "枚举到 %d 份档案（7 个 Id，阿利宙斯 3 形态 ⇒ 6 + 3 = 9）" % forms_seen)
	t.eq(off_rule.size(), 0, "家族规则：除佩涅罗佩外全员 = 柯西那条（越界：%s）" % str(off_rule))
	t.eq(SuitProfile.penelope().engine_sound, "cruise_penelope",
		"★ 佩涅罗佩是**唯一**的例外（她自己那条）")
	# 靶机版 `gustav00()` **不走 `by_id`**（`by_id` 默认给武装版）⇒ 单独钉一遍。
	t.eq(SuitProfile.gustav00().engine_sound, "cruise_xi",
		"古斯塔夫靶机版（不走 `by_id` 的那一支）也是柯西那条")
	# 三台梅萨（M01 / 指挥官型 / F01）都吃同一个默认值 ⇒ 互相一致。
	t.eq(SuitProfile.messer_cmd().engine_sound, SuitProfile.messer_m01().engine_sound,
		"梅萨指挥官型与 M01 引擎音一致")
	t.eq(SuitProfile.messer_f01().engine_sound, SuitProfile.messer_m01().engine_sound,
		"梅萨 F01 与 M01 引擎音一致")

	# ---- ★ 结构断言：`cruise_penelope` 在机体表里**只有一个赋值点** ----
	#
	# 上面那条靠**值**判；这条靠**源码里的赋值点个数**判，两者互补：
	#   · 值判据挡不住"某台机显式写了个恰好等于默认值的值"（值对、语义上却是特例）；
	#   · 计数把"谁在用佩涅罗佩那条"变成一个**可数的事实** —— 这也正是本轮把默认值
	#     改成 `cruise_xi` 的**理由**：默认取"绝大多数"那一侧，例外只剩一处显式，
	#     于是"忘了指定的新机体"拿到的是**安全**的那条。
	# 本套件自备的 `_code()` 会剥掉整行注释与行尾注释 ⇒ "注释里提到也算"不会造成假红。
	# （不走 `SuiteUiStyle`：套件之间不互相依赖 —— 原因见下方 `_code()`。）
	var prof_src := _code("res://scripts/data/suit_profile.gd")
	t.ok(prof_src != "", "读到了 suit_profile.gd 且剥掉了注释")
	t.eq(prof_src.count('"cruise_penelope"'), 1,
		"★ 机体表里 cruise_penelope 的赋值点只有 1 处（= 佩涅罗佩那一份档案）")

	# ---- ★ 接线：兜底函数体里不许出现这两个字面量（必须读字段）----
	#
	# 挡的是设计文档 §7.5 点名的那件事：`_build_engine_audio()` 曾经写死
	# `"cruise_xi" if profile.id == XI else "cruise_penelope"`，
	# 于是"阿利宙斯用柯西那条"这个决定**写在档案里却没人读**（死字段）。
	# 判据必须落在**函数体**上（不是整个文件），否则文件顶部那段历史说明会把它顶红。
	var fb_src := _code("res://scripts/flight/flight_body.gd")
	var engine_body := _body(fb_src, "func _build_engine_audio(")
	t.ok(engine_body != "", "取到了 `_build_engine_audio()` 的函数体")
	t.ok(engine_body.contains("profile.engine_sound"),
		"★ 取音源那一段**确实**读了 `profile.engine_sound`（一个真源）")
	t.ok(not engine_body.contains('"cruise_xi"'),
		"取音源那一段里没有写死 cruise_xi（必须走字段）")
	t.ok(not engine_body.contains('"cruise_penelope"'),
		"取音源那一段里没有写死 cruise_penelope（同上）")

	# ---- ② 真路径：播放器上真正挂着的流 ----
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var xi_e := _find_engine(_unit(c, SuitProfile.xi(), false))
	var ari_e := _find_engine(_unit(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE), false))
	var pen_e := _find_engine(_unit(c, SuitProfile.penelope(), false))
	t.ok(xi_e != null and ari_e != null and pen_e != null, "三台机体的引擎播放器都建起来了")
	if xi_e != null and ari_e != null:
		t.ok(ari_e.stream != null, "阿利宙斯的引擎上挂着音频流")
		t.ok(ari_e.stream == xi_e.stream,
			"……而且与柯西**是同一个流实例**（音源真的一样，不是「碰巧都非空」）")
		t.gt(ari_e.stream.get_length(), 1.0, "……流有实际长度（%.1f s）" % ari_e.stream.get_length())
	if ari_e != null and pen_e != null:
		t.ok(ari_e.stream != pen_e.stream,
			"……并且**不是**佩涅罗佩那条 —— 死字段那段时间它一直发的是佩涅罗佩的")

	# ---- ★ 真路径 · 家族（轮 49）----
	#
	# 家族里**每一台**都要在**真路径**上落到柯西那个流实例上 ——
	# 不只是"档案里那个字符串写对了"。量的是"敌机 / 僚机"那条路（上面量过玩家那 3 台）。
	# 下面是家族全员里**除了柯西与佩涅罗佩**之外的：古斯塔夫两型 + 梅萨三型 + 阿利宙斯核心形态。
	if xi_e != null:
		var fam: Array[SuitProfile] = [
			SuitProfile.gustav00(), SuitProfile.gustav00_armed(),
			SuitProfile.messer_m01(), SuitProfile.messer_cmd(), SuitProfile.messer_f01(),
			SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU),
		]
		var off_fam: Array[String] = []
		var inst: Array[String] = []
		for sp: SuitProfile in fam:
			var e := _find_engine(_unit(c, sp, false))
			# 打印"落到哪个流实例"：与柯西**同一个实例 id** 才是"音源真的一样"。
			# 注意 `0` 是"没挂上引擎 / 没有流"的哨兵，出现 0 就说明那台机没建对。
			var iid := 0
			if e != null and e.stream != null:
				iid = int(e.stream.get_instance_id()) % 100000
			inst.append("%s->#%d" % [sp.display_name, iid])
			if e == null or e.stream != xi_e.stream:
				off_fam.append(sp.display_name)
		inst.append("柯西->#%d" % (int(xi_e.stream.get_instance_id()) % 100000))
		print("  [表] 家族真路径落点（同实例 = 同 id）：%s"
			% ", ".join(PackedStringArray(inst)))
		t.eq(fam.size(), 6, "家族样本 %d 台（古斯塔夫两型 + 梅萨三型 + 阿利宙斯核心形态）"
			% fam.size())
		t.eq(off_fam.size(), 0,
			"家族里每一台的引擎上挂的都是**柯西那个流实例**（异常：%s）" % str(off_fam))
	c.free()
	await host.get_tree().process_frame
	Game.reset()


static func _unit(container: Node3D, suit: SuitProfile, as_player: bool) -> FlightBody:
	var u := FlightBody.new()
	u.team = 0 if as_player else 1
	u.is_player = as_player
	u.profile = suit
	u.projectile_container = container
	container.add_child(u)
	u.global_position = Vector3(0, 3000, 0)
	u.fm.speed = 260.0
	u.fm.align_velocity(u.forward())
	return u


static func _find_engine(u: FlightBody) -> AudioStreamPlayer3D:
	for c: Node in u.get_children():
		var p := c as AudioStreamPlayer3D
		if p != null and p.name == "EngineLoop":
			return p
	return null


static func _has_detect(u: FlightBody) -> bool:
	return u.get_node_or_null("DetectTimer") != null


## 节流：同一个音效在最小间隔内只放一次。
static func _throttle(t: T, host: Node) -> void:
	Audio.reset_throttle()
	var before := _count_players()
	Audio.play_3d("boom_s", Vector3(0, 100, 0))
	var after_first := _count_players()
	t.eq(after_first, before + 1, "第一次播放会新建一个播放器")
	Audio.play_3d("boom_s", Vector3(0, 100, 0))
	t.eq(_count_players(), after_first, "紧接第二次被节流挡掉，不再新建")

	Audio.reset_throttle()
	# 未知音效名不能崩，只是不出声
	Audio.play_3d("__no_such_sound__", Vector3.ZERO)
	Audio.play_self("__no_such_sound__")
	t.ok(true, "未知音效名不会导致崩溃")
	await host.get_tree().process_frame


static func _count_players() -> int:
	var scene := Audio.get_tree().current_scene
	if scene == null:
		return 0
	var n := 0
	for c: Node in scene.get_children():
		if c is AudioStreamPlayer3D:
			n += 1
	return n


## 导弹爆炸有"近处 / 远处"两版**不同的录音**（用户指定），
## 所以要在播放前按离镜头的距离二选一，不能靠音量衰减糊过去。
static func _explosion_variant(t: T, host: Node) -> void:
	t.eq(SoundBank.SFX["boom_s"], "boom_s.mp3", "boom_s 是近处导弹爆炸")
	t.eq(SoundBank.SFX["boom_m"], "boom_m.mp3", "boom_m 是远处导弹爆炸")
	t.eq(SoundBank.SFX["boom_l"], "boom_l.mp3", "boom_l 是机体爆炸")
	# 1.1：阿利宙斯变形音效（用户提供的素材）。路径写错的话 load 会返回 null、
	# 变形变成哑的 —— 这类问题不报错，所以必须对着音频表查一次。
	t.ok(SoundBank.SFX.has("arizeus_transform"), "变形音效登记在音频表里")
	t.ok(ResourceLoader.exists(SoundBank.sfx_path("arizeus_transform")),
		"变形音效文件真的在工程里：%s" % SoundBank.sfx_path("arizeus_transform"))
	t.gt(SoundBank.NEAR_EXPLOSION_DISTANCE, 100.0, "近 / 远分界距离是个有意义的正数")

	# 放一台相机当"听者"，验证分界规则
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.global_position = Vector3(0, 3000, 0)
	cam.current = true
	await host.get_tree().process_frame

	t.ok(Audio.is_near_explosion(Vector3(0, 3000, -400)), "400 m 内的爆炸判为近处（boom_s）")
	t.not_ok(Audio.is_near_explosion(Vector3(0, 3000, -3000)), "3 km 外的爆炸判为远处（boom_m）")
	t.ok(Audio.is_near_explosion(Vector3(0, 3000, -799)), "刚好在分界内侧算近处")
	t.not_ok(Audio.is_near_explosion(Vector3(0, 3000, -801)), "刚好在分界外侧算远处")

	Audio.reset_throttle()
	Audio.play_explosion(Vector3(0, 3000, -400))
	Audio.reset_throttle()
	Audio.play_explosion(Vector3(0, 3000, -9000))
	t.ok(true, "两种距离的爆炸播放都不报错")

	cam.current = false
	cam.free()
	await host.get_tree().process_frame


## 用户 2026-09-27：「光束步枪和光束军刀的音效声音调大25%」。
##
## 三条不变量，缺一不可：
##   ① **换算**：「25%」= `20·log10(1.25)` ≈ +1.9382 dB，**不是** +25 dB（那是 17.78 倍，会爆音）；
##   ② **表值**：三条音效的偏移**等于**那个换算结果 ——
##      这样「调大 25%」在代码里是可审计的，而不是某个手抄的小数；
##   ③ **真路径**：真播一次，读回**播放器上实际的 `volume_db`**。
##      只钉 ①② 抓不住「表加了但没人读」—— 表一直是满的、音量一直没变。
##
## 为什么 ③ 要把**两条通道都测**：`play_self`（玩家自己，非定位）与
## `play_3d`（敌机，定位）是两个几乎长得一样的函数体，只给一边加增益
## **看代码看不出来** —— 而症状是「打敌人听得见、自己开炮没变响」。
static func _weapon_gain(t: T, host: Node) -> void:
	# ---- ① 换算 ----
	var want := SoundBank.db_for_percent(25.0)
	t.near(want, 1.9382, 0.001, "调大 25% = +1.9382 dB（振幅 ×1.25）")
	t.ok(want < 3.0, "「25%」绝不能被当成 +25 dB（那是 17.78 倍，直接削顶）")
	t.near(SoundBank.db_for_percent(0.0), 0.0, 0.0001, "0% = 0 dB（不许变成别的数）")
	t.near(SoundBank.db_for_percent(100.0), 6.0206, 0.001, "调大 100% = +6.0206 dB（振幅 ×2）")
	t.near(SoundBank.db_for_percent(-50.0), -6.0206, 0.001, "调小 50% = -6.0206 dB（振幅 ×0.5）")
	t.eq(SoundBank.db_for_percent(-100.0), -80.0, "调小 100%（静音）走兜底，不产生 -inf")

	# ---- ② 表值 ----
	for n: String in ["beam_rifle", "beam_saber", "saber_impact"]:
		t.near(SoundBank.gain_db(n), want, 0.0005,
			"`%s` 的增益就是「调大 25%%」的换算值（不许手抄成别的数）" % n)
	t.near(SoundBank.gain_db("vulcan"), 0.0, 0.0001, "没被点名的音效增益是 0（不是「顺手都调了」）")
	t.near(SoundBank.gain_db("__no_such_sound__"), 0.0, 0.0001, "表里没有的名字 = 0 dB，不是崩")

	# ---- ③ 真路径：play_self（非定位，玩家自己的武器）----
	var sp := _play_and_get(true, "beam_rifle", -4.0)
	t.ok(sp != null, "play_self 真的建了播放器")
	if sp != null:
		t.near((sp as AudioStreamPlayer).volume_db, -4.0 + want, 0.0005,
			"play_self 把增益加上了（调用点 -4.0 → %.4f dB）" % (-4.0 + want))

	# 没被点名的音效必须**分毫不动** —— 否则「只调两条」就是假的
	var sp2 := _play_and_get(true, "vulcan", -4.0)
	t.ok(sp2 != null, "play_self 也建了对照组播放器")
	if sp2 != null:
		t.near((sp2 as AudioStreamPlayer).volume_db, -4.0, 0.0001,
			"没被点名的音效音量原样不动（vulcan 仍是 -4.0 dB）")

	# ---- ③ 真路径：play_3d（定位，敌机的武器）----
	var sp3 := _play_and_get(false, "beam_saber", -2.0)
	t.ok(sp3 != null, "play_3d 真的建了播放器")
	if sp3 != null:
		t.near((sp3 as AudioStreamPlayer3D).volume_db, -2.0 + want, 0.0005,
			"play_3d 也把增益加上了（调用点 -2.0 → %.4f dB）" % (-2.0 + want))

	# ---- 源码结构：三条通道的职责不许被「顺手统一」----
	# 行为断言已经证明"加上了"，这一层是为了**红了能一眼定位到哪个函数**。
	var src := _code("res://scripts/audio/audio_director.gd")
	t.ok(_body(src, "func play_self(").contains("SoundBank.gain_db(name)"),
		"play_self 读增益表")
	t.ok(_body(src, "func play_3d(").contains("SoundBank.gain_db(name)"),
		"play_3d 读增益表")
	t.not_ok(_body(src, "func play_voice(").contains("gain_db"),
		"座舱告警语音**不**走增益表（它的音量是写死的救命基准，见 VOICE_DB）")
	await host.get_tree().process_frame


## 真播一次，再按「调用前后的子节点数量差」把刚建的那个播放器取出来。
##
## ⚠️ 不能靠名字找：`Audio` 自己就挂着两个 BGM 播放器（`Bgm0` / `Bgm1`），
## 而临时播放器用的是自动名（`@AudioStreamPlayer@123`），名字不可预期。
## ⚠️ 两条通道建的播放器**挂在不同的父节点**上：`play_self` 挂在 `Audio` 自己身上，
## `play_3d` 挂在 `current_scene` 下（定位音必须进场景树 —— 见 `play_3d` 的注释）。
static func _play_and_get(as_self: bool, name: String, vol_db: float) -> Node:
	var owner_node: Node = Audio if as_self else Audio.get_tree().current_scene
	if owner_node == null:
		return null
	var before := owner_node.get_child_count()
	if as_self:
		Audio.play_self(name, vol_db)
	else:
		Audio.play_3d(name, Vector3(0, 0, 0), vol_db)
	var kids := owner_node.get_children()
	for i in range(before, kids.size()):
		if kids[i] is AudioStreamPlayer or kids[i] is AudioStreamPlayer3D:
			return kids[i]
	return null




## 读源文件文本。
static func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## 去掉**整行注释**与**行尾注释**之后的源码。
##
## ⚠️ 所有「源码里有没有 X」的断言都必须走这里：注释里提到某个名字恰恰说明
## 它被慎重考虑过，那不该算违规 —— 本套件的判据注释里**特意**点了
## `cruise_penelope` / `cruise_xi` 这些字面量，扫原文会把自己判失败。
##
## ★ 与 `SuiteUiStyle._code()` **不共享实现是故意的** —— 套件之间不互相依赖。
## 沿革（轮 49 · 2026-09-30 实测）：`SuiteUiStyle` 的 `class_name` 在
## `tests/suite_ui_style.gd` 里；那个文件一旦解析失败（当时是并行会话在改
## `scripts/ui/ui_layout.gd`），`SuiteUiStyle._code()` 就退化成
## `Invalid call. Nonexistent function '_code' in base 'GDScript'` ——
## **运行时错误会把整个 `_engine_source()` 打断**，于是本节的判据从 25 条
## 静默掉到 12 条，而汇总仍然是 `138 PASS / 0 FAIL`：
## **判据「消失」了，却没有变红**。那是最该防的一种失效，所以这里自备一份。
static func _code(path: String) -> String:
	var out: Array = []
	for line in _src(path).split("\n"):
		var s := str(line)
		if s.strip_edges().begins_with("#"):
			continue
		out.append(_strip_inline(s))
	return "\n".join(out)


## 去掉行尾注释（`#` 落在字符串里的时候不算注释）。
##
## 内外靠**引号计数**判断：`#` 前面若有奇数个引号，说明它在字符串里。
## 这不是完整的词法分析，但对“代码行里混一句中文注释”这种实际情况够用。
static func _strip_inline(line: String) -> String:
	var quotes := 0
	for i in line.length():
		var c := line[i]
		if c == "\"" or c == "'":
			quotes += 1
		elif c == "#" and quotes % 2 == 0:
			return line.substr(0, i)
	return line


## 取一个函数体（在**剥过注释**的源码上找，到下一个 `func` 之前）。
## 剥注释那一步用**本套件自己的** `_code()`（见上）—— 不跨套件引用。
static func _body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var lines := src.substr(i).split("\n")
	var out: Array = [str(lines[0])]
	for k in range(1, lines.size()):
		var s := str(lines[k])
		if s.begins_with("func ") or s.begins_with("static func "):
			break
		out.append(s)
	return "\n".join(out)
