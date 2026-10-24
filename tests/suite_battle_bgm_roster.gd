class_name SuiteBattleBgmRoster
extends RefCounted
## 战斗BGM「历代曲册」（★63-20）的测试。
##
## 用户 2026-10-08：「`D:\闪哈游戏历代音乐` 这些是新加的战斗音乐，你把他们都加进游戏内，
## 但是玩家不选择就不播。」
##
## 这句话是**两个方向**的要求，缺一条都不算做到：
##
##   ① **都加进游戏内** —— 46 首必须登记进 `SoundBank.BGM`、素材必须在盘上、
##      必须在自选序列里拨得到、选中了必须真的成为本场第一首；
##   ② **玩家不选择就不播** —— 46 首**一首都不许进轮换池**。
##      ⚠️ 只查「表里没有」证明的是**声明**，证不了**行为** —— 池子可能被谁顺手改宽了。
##      ⇒ 必须**真让洗牌袋抽够轮数**，一次都不许出现（见 `_never_auto`）。
##
## ⚠️ 为什么单开一个套件而不并进 `suite_audio`：本工程**有并行会话**，
## 「一个功能一个 suite 文件、且按主题命名」是硬规矩（HANDOFF §8.3 / §7.3）。
##
## ⚠️ 「选了真的会响」这件事**套件证明不了**：headless 是 Dummy 音频驱动，
## `AudioStreamPlayer.playing` 永远不置 true。那一半由真机探针
## `tools/_r63_20_bgm_roster.tscn` 出图 + 读 `pos` 推进来证。这里证的是
## 「名字对、路径对、解码得出来、循环标志对、轮换数学对」。


## 本批（★63-20）登记的 46 首曲子的键 —— **与 `SoundBank.OPT_IN_BATTLE_TRACKS` 同序**。
##
## ⚠️ 这份名单是**有意的第二份**（第一份是 `SoundBank.OPT_IN_BATTLE_TRACKS`）：
## 同一个名单写两遍，改一处忘另一处就会红 —— 这正是我们要的。
## 只写一遍的话，「素材复制进来了但忘了登记」这件事**永远不会被任何东西发现**，
## 症状只是「某一首怎么点都听不到」。
const ROSTER := [
	"re_i_am", "cerulean", "nibun_no_ichi", "survivor", "akatsuki_no_kuruma",
	"moeagare_toshi", "waga_kokoro_meikyo_shisui", "daybreaks_bell",
	"men_of_destiny", "rage_of_dust", "snooze", "cage_ntv", "anna_ni_issho",
	"beyond_the_time", "just_communication", "rhythm_emotion", "freesia",
	"shukufuku", "flying_in_the_sky", "trust_you_forever", "silent_voice",
	"red_birthmark", "main_title", "ai_senshi", "trust_you", "fight_kawai",
	"anime_ja_nai", "mou_dou_natte_mo_ii_ya", "yoru_ni_saku", "the_winner",
	"sassou_taru_char", "yoake_no_shooting_star", "mizu_no_hoshi_e_ai_wo_komete",
	"itsuka_sora_ni_todoite", "urdr_hunt", "earth_nt", "unicorn", "vigilante",
	"colony_no_kanojo", "reborn", "arashi_no_naka_de", "arashi_no_naka_de_2",
	"plazma", "freedom", "invoke", "z_kioku_wo_koete",
]

## 本批之前工程里已有的 BGM 条目数（9 首：mobius / tracer / nda_alpha / xi / senkou /
## sweet_child / special_result / car5p3 / mne）。
const BGM_BEFORE := 9

## 每首曲子至少该有的字节数 —— 用来咬「复制到一半 / 截断」。
## 这批素材里最小的一首 3.4 MB，1 MB 是很宽松的下限。
const MIN_BYTES := 1048576


static func run(t: T, host: Node) -> void:
	t.suite("战斗BGM / 历代曲册已登记（★63-20）")
	_roster(t)
	t.suite("战斗BGM / 仅自选身份：一首都不进轮换池")
	_opt_in_identity(t)
	t.suite("战斗BGM / 选中就是本场第一首")
	_selected_plays(t)
	t.suite("战斗BGM / 不选 ⇒ 真抽 165 次一次都不出现")
	_never_auto(t)


## ① 登记完整性：表里有、盘上有、菜单里有、显示名像样。
static func _roster(t: T) -> void:
	t.eq(ROSTER.size(), 46, "曲册 46 首（= 用户给的目录里 mp3 的实际个数）")
	var uniq := {}
	for k: String in ROSTER:
		uniq[k] = true
	t.eq(uniq.size(), 46, "曲册里没有重复键")

	var no_bgm: Array[String] = []
	var no_file: Array[String] = []
	var tiny: Array[String] = []
	var bad_label: Array[String] = []
	for k: String in ROSTER:
		if not SoundBank.BGM.has(k):
			no_bgm.append(k)
			continue
		var p := SoundBank.bgm_path(k)
		if not ResourceLoader.exists(p):
			no_file.append(k)
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null or f.get_length() < MIN_BYTES:
			tiny.append(k)
		if f != null:
			f.close()
		var lab := SoundBank.battle_track_label(k)
		if lab == "" or lab == k:
			bad_label.append(k)

	t.eq(no_bgm.size(), 0, "46 首都在 BGM 表里（缺 = 忘登记）：%s" % str(no_bgm))
	t.eq(no_file.size(), 0,
		"46 首素材都在盘上（缺 = 复制漏了 / 忘了跑 --import）：%s" % str(no_file))
	t.eq(tiny.size(), 0,
		"46 首素材都不是残档（小于 %d B 的：%s）" % [MIN_BYTES, str(tiny)])
	t.eq(bad_label.size(), 0,
		"46 首都有像样的显示名（空 / 等于键名 = 菜单上玩家认不出来）：%s" % str(bad_label))

	t.eq(SoundBank.BGM.size(), BGM_BEFORE + ROSTER.size() + 2,
		"BGM 表 = %d（原有）+ %d（历代曲）+ 2（雷霆宙域）= %d"
			% [BGM_BEFORE, ROSTER.size(), SoundBank.BGM.size()])
	t.eq(SoundBank.OPT_IN_BATTLE_TRACKS.size(), ROSTER.size() + 1 + 2,
		"自选表 = 46（历代曲）+ 1（sweet_child）+ 2（雷霆宙域）= %d" % SoundBank.OPT_IN_BATTLE_TRACKS.size())

	# 自选序列的**每一首**都要有显示名（选歌页会逐条画出来，缺一个就是一行键名）
	var no_label: Array[String] = []
	for k: String in SoundBank.battle_pick_tracks():
		if SoundBank.battle_track_label(str(k)) == str(k):
			no_label.append(str(k))
	t.eq(no_label.size(), 0,
		"自选列表全体都有显示名（不许出现键名）：%s" % str(no_label))

	# 抽样解码：首 / 中 / 末三首，确认不是「文件在、解码不出」
	var bad: Array[String] = []
	for i: int in [0, ROSTER.size() / 2, ROSTER.size() - 1]:
		var s: AudioStream = load(SoundBank.bgm_path(ROSTER[i]))
		var secs := 0.0 if s == null else s.get_length()
		if s == null or secs <= 60.0:
			bad.append("%s(%.1fs)" % [ROSTER[i], secs])
	t.eq(bad.size(), 0,
		"抽样三首都能解码出 > 60 s 的时长（load 静默返回 null 是这类素材的老毛病）：%s" % str(bad))


## ② 身份：46 首全部是「仅自选曲」，且与两个轮换池互斥。
##
## 这是「玩家不选择就不播」的**结构**那一半；**行为**那一半在 `_never_auto`。
static func _opt_in_identity(t: T) -> void:
	var not_opt: Array[String] = []
	var in_rotate: Array[String] = []
	var not_pick: Array[String] = []
	for k: String in ROSTER:
		if not SoundBank.is_opt_in_battle_track(k):
			not_opt.append(k)
		if SoundBank.BATTLE_TRACKS.has(k) or SoundBank.STORY_BATTLE_TRACKS.has(k):
			in_rotate.append(k)
		if not SoundBank.is_battle_pick(k):
			not_pick.append(k)
	# ★63-22（用户 2026-10-08 要求去掉「（仅自选 · 不参与随机）」后缀）：
	# 这里原来还有一条 `no_note`（46 首必须都带那个后缀标记）。后缀与
	# `SoundBank.battle_track_note()` 一起删了，所以它随之下线 ——
	# ⚠️ 但它钉的**真正要命的东西**是"这 46 首的身份 = 仅自选曲"，
	# 那一条就是上面的 `not_opt`（**保留**），所以**没有留下覆盖空洞**。
	t.eq(not_opt.size(), 0, "46 首全部登记为「仅自选曲」（缺：%s）" % str(not_opt))
	t.eq(in_rotate.size(), 0,
		"⚠️ 46 首**一首都没有进轮换池**（进了就会自动轮播，正好是用户禁止的那件事）：%s"
			% str(in_rotate))
	t.eq(not_pick.size(), 0,
		"46 首都算合法自选值（is_battle_pick 漏认 ⇒ 存档读回来静默退回「随机」）：%s" % str(not_pick))

	# 轮换池**没有变宽** —— 这是「别顺势把新曲塞进池子」的第二道门
	t.eq(SoundBank.BATTLE_TRACKS.size(), 6, "对战轮换池仍是 6 首（本批一首都不许进去）")
	t.eq(SoundBank.STORY_BATTLE_TRACKS.size(), 5, "剧情轮换池仍是 5 首（本批一首都不许进去）")

	# 表级互斥：整张仅自选表（不只本批）都不许与两池相交
	var clash: Array[String] = []
	for k: String in SoundBank.OPT_IN_BATTLE_TRACKS:
		if SoundBank.BATTLE_TRACKS.has(str(k)) or SoundBank.STORY_BATTLE_TRACKS.has(str(k)):
			clash.append(str(k))
	t.eq(clash.size(), 0, "仅自选表与两个轮换池互斥（相交的：%s）" % str(clash))

	# 自选序列的**前缀**必须还是轮换池 —— 老玩家背下来的位置不许被新曲挤乱
	var picks: Array = SoundBank.battle_pick_tracks()
	var prefix_ok := true
	for i in SoundBank.BATTLE_TRACKS.size():
		if str(picks[i]) != str(SoundBank.BATTLE_TRACKS[i]):
			prefix_ok = false
	t.ok(prefix_ok, "自选序列前缀 = 轮换池（新曲只加在它后面）")
	# ⚠️ 这里**不能**写成 `OPT_IN.size() == picks.size() - BATTLE_TRACKS.size()` ——
	# `battle_pick_tracks()` 的定义就是「池 + 仅自选」⇒ 那条断言**恒真、永远不会红**。
	# 负对照实测（NC-A 把一首同时放进池与仅自选表）：写成减法时它照样绿。
	# ⇒ 真正该钉的是**自选序列里没有重复项** —— 同一首既在池里又在仅自选表里时，
	# 玩家会在菜单里看到它两行，而且「它到底会不会被随机播到」变成两说。
	var dup_pick: Array[String] = []
	var seen_pick := {}
	for k: String in picks:
		if seen_pick.has(str(k)):
			dup_pick.append(str(k))
		seen_pick[str(k)] = true
	t.eq(dup_pick.size(), 0,
		"自选序列里没有重复项（重复 = 同一首既在池里又在仅自选表里，玩家会看到两行）：%s"
			% str(dup_pick))
	t.eq(seen_pick.size(), SoundBank.BATTLE_TRACKS.size() + SoundBank.OPT_IN_BATTLE_TRACKS.size(),
		"自选序列去重后条数 = 轮换池 + 仅自选曲（一条不漏、一条不重）：%d" % seen_pick.size())
	# `suite_audio` 与 `suite_settings` 都读 `sweet_child` 的**末位** —— 本批不许把它挤走
	t.eq(str(picks[picks.size() - 1]), "sweet_child",
		"仅自选的老面孔 sweet_child 仍在末位（两处既有断言依赖它）")


## ③ 选中路径：46 首 × 两套池子 = 92 次「选了它，本场第一首就是它」。
##
## ⚠️ 这里证明的是**接线**（曲名 → 本场第一首）而不是**发声**。
## 发声（解码器真的在推进）由真机探针负责 —— headless 证明不了。
static func _selected_plays(t: T) -> void:
	var bag_bak: Array = Audio._battle_bag.duplicate()
	var last_bak: String = Audio._last_battle_track
	var senkou_bak: bool = Audio._senkou_used
	var pool_bak: Array = Audio.battle_pool
	var req_bak: String = Audio.requested_battle_open

	var not_first: Array[String] = []
	var not_consumed: Array[String] = []
	var next_outside: Array[String] = []
	var touched_senkou: Array[String] = []
	var pairs := 0
	for pool: Array in [SoundBank.BATTLE_TRACKS, SoundBank.STORY_BATTLE_TRACKS]:
		for k: String in ROSTER:
			pairs += 1
			Audio.battle_pool = pool
			Audio._battle_bag.clear()
			Audio._last_battle_track = ""
			Audio._senkou_used = false
			Audio.request_battle_open(k)
			if Audio.bgm_name(Audio.Bgm.BATTLE) != k:
				not_first.append(k)
			if Audio.requested_battle_open != "":
				not_consumed.append(k)
			if Audio._senkou_used:
				touched_senkou.append(k)
			var nxt := Audio.bgm_name(Audio.Bgm.BATTLE)
			if not pool.has(nxt):
				next_outside.append(k)

	t.eq(pairs, ROSTER.size() * 2, "跑了 %d 组（46 首 × 两套池子）" % pairs)
	t.eq(not_first.size(), 0, (
		"⚠️ 选中的曲子一定当本场第一首（不成立的 = 菜单里选得中、跑起来放的是随机的另一首，"
		+ "而且一行报错都没有）：%s" % str(not_first)))
	t.eq(not_consumed.size(), 0,
		"请求只被消费一次（不然后面几首会被同一首顶掉）：%s" % str(not_consumed))
	t.eq(next_outside.size(), 0,
		"第二首一定回到本模式的轮换池（回不去 = 整场只剩这一首）：%s" % str(next_outside))
	t.eq(touched_senkou.size(), 0,
		"选的不是 senkou，一个都不该置「用过闪光」标记：%s" % str(touched_senkou))

	# ---- 还原：先切回池子，再写回字段 ----
	# ⚠️ 顺序不能反：`set_story_mode()` 自己会把 `_senkou_used` 清成 false，
	# 放在还原之后调用等于把刚写回的 senkou_bak 抹掉。
	Audio.set_story_mode(pool_bak == SoundBank.STORY_BATTLE_TRACKS)
	Audio._battle_bag = bag_bak
	Audio._last_battle_track = last_bak
	Audio._senkou_used = senkou_bak
	Audio.requested_battle_open = req_bak


## ④ 行为：**玩家什么都不选**，真让洗牌袋抽 3 个种子 × 两套池子 × 5 轮。
##
## 这一节是本轮需求的**核心判据** —— 结构断言只能证明「表里没有它」，
## 证明不了「它不会被放出来」（池子写宽一行，结构断言照样全绿）。
static func _never_auto(t: T) -> void:
	var bag_bak: Array = Audio._battle_bag.duplicate()
	var last_bak: String = Audio._last_battle_track
	var senkou_bak: bool = Audio._senkou_used
	var pool_bak: Array = Audio.battle_pool
	var req_bak: String = Audio.requested_battle_open
	var seed_bak: int = Audio._rng.seed
	var state_bak: int = Audio._rng.state

	var leaked: Array[String] = []
	var outside: Array[String] = []
	var draws := 0
	for s: int in [20261008, 7, 424242]:
		for pool: Array in [SoundBank.BATTLE_TRACKS, SoundBank.STORY_BATTLE_TRACKS]:
			Audio.battle_pool = pool
			Audio._battle_bag.clear()
			Audio._last_battle_track = ""
			Audio._senkou_used = false
			# ⚠️ 是 `request_battle_open`（方法），不是 `requested_battle_open`（属性）——
			# 写错的那个是 String，被当函数调用 ⇒ **整套件 Parse Error**。
			Audio.request_battle_open("")   # = 设置页的「随机」
			Audio._rng.seed = s
			for i in pool.size() * 5:
				var d := Audio.bgm_name(Audio.Bgm.BATTLE)
				draws += 1
				if SoundBank.is_opt_in_battle_track(d):
					leaked.append(d)
				if not pool.has(d):
					outside.append(d)

	t.eq(draws, 3 * (SoundBank.BATTLE_TRACKS.size() + SoundBank.STORY_BATTLE_TRACKS.size()) * 5,
		"真抽了 %d 次（3 种子 × 两套池子 × 5 轮 —— 是**行为**不是查表）" % draws)
	t.eq(leaked.size(), 0, (
		"⚠️⚠️ 玩家不选 ⇒ 抽 %d 次【一次都没有】出现仅自选曲（本轮需求的核心判据）：%s"
		% [draws, str(leaked)]))
	t.eq(outside.size(), 0,
		"抽到的每一首都在本模式轮换池里（池子没被悄悄改宽）：%s" % str(outside))

	Audio.set_story_mode(pool_bak == SoundBank.STORY_BATTLE_TRACKS)
	Audio._battle_bag = bag_bak
	Audio._last_battle_track = last_bak
	Audio._senkou_used = senkou_bak
	Audio.requested_battle_open = req_bak
	Audio._rng.seed = seed_bak
	Audio._rng.state = state_bak
