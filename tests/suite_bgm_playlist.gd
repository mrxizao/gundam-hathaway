class_name SuiteBgmPlaylist
extends RefCounted
## 自定义战斗歌单（★63-22）的测试。
##
## 用户 2026-10-08：「做一个自定义歌单战斗歌单系统，玩家可以选择 6 首歌曲作为自己的
## 战斗歌单，循环播放」；拍板 Q7 又给了两个字 ——「歌单**整体随机**循环」。
##
## ## 那个「随机」二字是这一节最省的一条
## 它把"循环播放"钉成了**洗牌袋**的语义（一轮里每首各一次、一轮放完重洗、
## 新轮首曲 ≠ 上轮末曲）—— 而那正是 `AudioDirector.bag_next()` 现成的行为。
## ⇒ 播放侧**一行都不新写**，只把取样函数的池子参数换掉。
##
## ## ⚠️ 本设计最大的技术陷阱：**不许把歌单写进 `battle_pool`**
## `battle_pool` 被 **4 个套件、6 处**直接赋值，它是**测试依赖的公开契约**。
## 歌单塞进去 ⇒ 那些"设成默认池、验默认行为"的断言**不再是它设的那个池子**
## ⇒ 幽灵红（而且常常是"我这儿绿、交出去红"）。
## ⇒ 歌单只在 `effective_battle_pool()` 里参与一次判断，`battle_pool` 语义一字不变。
## 这一条在下面有**正反两条**断言钉着（`_effective_pool` + `_lock`）。
##
## ## ⚠️ headless 能证到什么程度
## "哪个池子在轮换"**可以真抽**（纯函数 + 状态），所以本套件**真抽**而不只查表。
## 「声音真的响了」仍要真机（另见 `suite_bgm_preview` 的说明）。


const SETTINGS_SOURCE := "scripts/autoload/settings.gd"
const AUDIO_SOURCE := "scripts/audio/audio_director.gd"
const MENU_SOURCE := "scripts/ui/main_menu.gd"
const INPUT_SOURCE := "scripts/autoload/input_setup.gd"


static func run(t: T, host: Node) -> void:
	t.suite("战斗歌单 / 规范化（去重 · 剔非法 · 上限 6）")
	_data(t)
	t.suite("战斗歌单 / 生效池：歌单优先，且**绝不写进 battle_pool**")
	_effective_pool(t)
	t.suite("战斗歌单 / 轮换（真抽：每轮各一次 · 没有第 4 首 · 单首不崩）")
	_rotation(t)
	t.suite("战斗歌单 / 与关卡锁曲 · 剧情池的交互")
	_lock_and_story(t)
	t.suite("战斗歌单 / 换歌单要清洗牌袋")
	_bag(t)
	t.suite("战斗歌单 / 持久化（往返 · 优雅退化 · 隔离白名单）")
	_persist(t)
	t.suite("战斗歌单 / 接线（设置行 · 子屏 · 复用 confirm · 六张输入表不动）")
	_ui(t)


## ① 规范化：去重 / 剔非法 / 上限。
static func _data(t: T) -> void:
	var back: Array[String] = Settings.battle_playlist
	var keys: Array = SoundBank.battle_pick_tracks()
	t.gt(float(keys.size()), Settings.PLAYLIST_MAX,
		"（对照）自选列表比歌单上限长（不然下面测不出'截断'）")

	Settings.set_battle_playlist([str(keys[0]), str(keys[1])])
	t.eq(Settings.battle_playlist.size(), 2, "set_battle_playlist([两首]) ⇒ 收下两首")
	t.eq(str(Settings.battle_playlist[0]), str(keys[0]), "顺序 = 加入顺序（页头按它显示）")

	Settings.set_battle_playlist([str(keys[0]), str(keys[0]), str(keys[1])])
	t.eq(Settings.battle_playlist.size(), 2,
		"去重：同一首给两次只留一次（一轮里听两遍同一首，玩家会以为随机坏了）")

	Settings.set_battle_playlist(["__no_such_track__", str(keys[0]), "", str(keys[1])])
	t.eq(Settings.battle_playlist.size(), 2,
		"★ 非法键（野键名 / 空串）被**逐项剔除**、其余保留 —— 不是整单丢弃")

	var eight: Array = []
	for i in 8:
		eight.append(str(SoundBank.battle_pick_tracks()[i]))
	Settings.set_battle_playlist(eight)
	t.eq(Settings.battle_playlist.size(), Settings.PLAYLIST_MAX,
		"上限 %d：给 8 首 ⇒ 截到 %d" % [Settings.PLAYLIST_MAX, Settings.PLAYLIST_MAX])
	t.eq(Settings.PLAYLIST_MAX, 6, "上限就是用户说的 6（拍板 Q9：1~6 首都行，不要求满）")

	# ---- 序号 / 成员判定 ----
	Settings.set_battle_playlist([str(keys[2]), str(keys[3])])
	t.eq(Settings.playlist_slot(str(keys[2])), 1, "序号 1 起")
	t.eq(Settings.playlist_slot(str(keys[3])), 2, "第二首序号 2")
	t.eq(Settings.playlist_slot(str(keys[5])), 0, "★ 不在歌单里 ⇒ 0（'序号'与'在不在'是同一个问题的两面）")
	t.ok(Settings.in_playlist(str(keys[2])), "in_playlist 认得出在单里的")
	t.not_ok(Settings.in_playlist(str(keys[5])), "……也认得出不在的")

	# ---- 读数 ----
	Settings.set_battle_playlist([])
	t.eq(Settings.playlist_label(), "未设置（用默认曲池）",
		"★ 空歌单的读数**不是** `0/6`（玩家分不清'我没设'和'保存失败'）")
	Settings.set_battle_playlist([str(keys[0])])
	t.eq(Settings.playlist_label(), "1/6 首", "非空 ⇒ 几首 / 上限")

	# ---- toggle 四态（UI 靠它选音效，所以每一态都要单独钉）----
	Settings.set_battle_playlist([])
	t.eq(Settings.toggle_playlist_track(str(keys[0])), Settings.PLAYLIST_ADDED,
		"空单里按一次 = 加入")
	t.eq(Settings.toggle_playlist_track(str(keys[0])), Settings.PLAYLIST_REMOVED,
		"再按一次 = 移出（页内一键两义，返回值必须能分辨）")
	t.eq(Settings.toggle_playlist_track("__no_such_track__"), Settings.PLAYLIST_REJECTED_BAD_TRACK,
		"野键 = 拒绝（**不是**加入）")
	Settings.set_battle_playlist(eight)
	t.eq(Settings.battle_playlist.size(), Settings.PLAYLIST_MAX, "（对照）先装满")
	var extra := str(SoundBank.battle_pick_tracks()[Settings.PLAYLIST_MAX + 1])
	t.eq(Settings.toggle_playlist_track(extra), Settings.PLAYLIST_REJECTED_FULL,
		"★ 满 %d 首再加 ⇒ 拒绝（拍板 Q14）" % Settings.PLAYLIST_MAX)
	t.eq(Settings.battle_playlist.size(), Settings.PLAYLIST_MAX, "……而且歌单没被偷偷改大")

	Settings.set_battle_playlist(back)


## ② 生效池：歌单优先；`battle_pool` **逐字不变**。
static func _effective_pool(t: T) -> void:
	var pool_back: Array = Audio.battle_pool
	var pl_back: Array[String] = Settings.battle_playlist

	Audio.battle_pool = SoundBank.BATTLE_TRACKS
	Settings.set_battle_playlist([])
	t.eq(Audio.effective_battle_pool(), SoundBank.BATTLE_TRACKS,
		"空歌单 ⇒ 有效池 = 模式默认池（与加这个功能之前**逐字一致**）")

	var mine: Array = [str(SoundBank.BATTLE_TRACKS[0]), str(SoundBank.BATTLE_TRACKS[1])]
	Settings.set_battle_playlist(mine)
	t.eq(Audio.effective_battle_pool(), Settings.battle_playlist,
		"非空歌单 ⇒ 有效池 = 歌单")
	t.eq(Audio.battle_pool, SoundBank.BATTLE_TRACKS,
		"★★ 歌单**没有**写进 `battle_pool`（4 个套件直接赋值它 —— 那是测试契约，动它=幽灵红）")

	# ⭐ 反证：换模式时 `battle_pool` 照旧被 `set_story_mode()` 换掉，而**有效池**跟着歌单
	Settings.set_battle_playlist([])
	Audio.set_story_mode(true)
	t.eq(Audio.effective_battle_pool(), SoundBank.STORY_BATTLE_TRACKS,
		"（无歌单）剧情模式 ⇒ 有效池 = 剧情池")
	Audio.set_story_mode(false)
	Settings.set_battle_playlist(mine)
	Audio.set_story_mode(true)
	t.eq(Audio.effective_battle_pool(), Settings.battle_playlist,
		"★ 有歌单时**连剧情模式也一样**：开关剧情不改玩家自己选的池子")
	Audio.set_story_mode(false)

	Audio.battle_pool = pool_back
	Settings.set_battle_playlist(pl_back)


## ③ 真抽：每轮每首各一次、一次都不冒出歌单外的曲。
##
## ⚠️ **只查表不算证据**（★63-20 的教训）：「歌单真的是那个池子」必须靠**真抽**。
## ⚠️ 期望值不是"随机的"而是**可精确算的**：N 轮 × K 首 = 每首恰好 N 次
##（洗牌袋的定义就是"一轮内每首各出现一次"）。这条比"只出现歌单里的曲"更强，
## 而且**能红**：把清袋逻辑去掉、或把池子换成 `battle_pool`，计数立刻不是 N。
static func _rotation(t: T) -> void:
	var pool_back: Array = Audio.battle_pool
	var bag_back: Array = Audio._battle_bag.duplicate()
	var last_back: String = Audio._last_battle_track
	var senkou_back: bool = Audio._senkou_used
	var req_back: String = Audio.requested_battle_open
	var lock_back: String = Audio._locked_battle_track
	var pl_back: Array[String] = Settings.battle_playlist

	Audio.battle_pool = SoundBank.BATTLE_TRACKS
	Audio.lock_battle_track("")
	Audio.request_battle_open("")

	var trio: Array = [str(SoundBank.BATTLE_TRACKS[0]), str(SoundBank.BATTLE_TRACKS[1]),
		str(SoundBank.BATTLE_TRACKS[2])]
	Settings.set_battle_playlist(trio)
	Audio._battle_bag.clear()
	Audio._last_battle_track = ""
	var rounds := 5
	var seen := {}
	for i in rounds * trio.size():
		var k: String = Audio.bgm_name(Audio.Bgm.BATTLE)
		seen[k] = int(seen.get(k, 0)) + 1
	t.eq(seen.size(), trio.size(),
		"真抽 %d 次只出现歌单里的 %d 首（实际出现：%s）"
			% [rounds * trio.size(), trio.size(), str(seen.keys())])
	var outside: Array[String] = []
	for k in seen.keys():
		if not Settings.in_playlist(str(k)):
			outside.append(str(k))
	t.eq(outside.size(), 0,
		"★ 一次都没冒出歌单外的曲（这是'歌单真的成了那个池子'的行为证据，不是查表）")
	var wrong: Array[String] = []
	for k in trio:
		if int(seen.get(str(k), 0)) != rounds:
			wrong.append("%s=%d" % [str(k), int(seen.get(str(k), 0))])
	t.eq(wrong.size(), 0,
		"★ 每轮内每首各出现一次 ⇒ %d 轮后每首恰好 %d 次（不等就说明不是洗牌袋语义；%s）"
			% [rounds, rounds, str(wrong)])

	# ---- 只有 1 首：不崩、不死循环 ----
	Settings.set_battle_playlist([str(SoundBank.BATTLE_TRACKS[0])])
	Audio._battle_bag.clear()
	Audio._last_battle_track = ""
	var only_bad: Array[String] = []
	for i in 5:
		var k: String = Audio.bgm_name(Audio.Bgm.BATTLE)
		if not Settings.in_playlist(k):
			only_bad.append(k)
	t.eq(only_bad.size(), 0,
		"歌单只有 1 首 ⇒ 只会是它（`bag_next` 的换位分支在 size==1 时本来就不进）：%s"
			% str(only_bad))

	Audio.battle_pool = pool_back
	Audio._battle_bag = bag_back
	Audio._last_battle_track = last_back
	Audio._senkou_used = senkou_back
	# ⚠️ 写用**方法**（`Audio.request_battle_open(x)`）而不是属性赋值：
	# 这个方法与那个变量**同名**，属性赋值在静态上下文里会被解析成"给方法赋值"。
	Audio.request_battle_open(req_back)
	Audio.lock_battle_track(lock_back)
	Settings.set_battle_playlist(pl_back)


## ④ 与关卡锁曲 / 剧情池的交互（两条都**不许**被歌单搅乱）。
static func _lock_and_story(t: T) -> void:
	var pool_back: Array = Audio.battle_pool
	var bag_back: Array = Audio._battle_bag.duplicate()
	var last_back: String = Audio._last_battle_track
	var senkou_back: bool = Audio._senkou_used
	var lock_back: String = Audio._locked_battle_track
	var pl_back: Array[String] = Settings.battle_playlist

	Audio.set_story_mode(false)
	Audio.request_battle_open("")

	# ---- 锁曲必须**盖过**歌单 ----
	var locked := str(SoundBank.BATTLE_TRACKS[0])
	t.ok(not Settings.in_playlist(locked), "（对照）拿来做锁曲的那首**不在**歌单里")
	Settings.set_battle_playlist([str(SoundBank.BATTLE_TRACKS[3]), str(SoundBank.BATTLE_TRACKS[4])])
	Audio._battle_bag.clear()
	Audio.lock_battle_track(locked)
	t.eq(Audio.bgm_name(Audio.Bgm.BATTLE), locked,
		"★★ 玩家歌单**不覆盖**关卡锁曲（锁曲校验读 `battle_pool`，不是有效池 —— "
			+ "改成读有效池的话 M01 的 TRACER 会**静默失效**，一行报错都没有）")
	Audio.lock_battle_track("")

	# ---- 歌单里放 senkou ⇒ 剧情模式下照放（拍板 Q11：放）----
	Settings.set_battle_playlist(["senkou", str(SoundBank.STORY_BATTLE_TRACKS[0])])
	t.ok(SoundBank.is_battle_pick("senkou"), "（对照）senkou 是合法自选值")
	t.not_ok(SoundBank.STORY_BATTLE_TRACKS.has("senkou"),
		"（对照）剧情池里**没有** senkou —— 所以下面那条只能靠歌单放出来")
	Audio.set_story_mode(true)
	Audio._battle_bag.clear()
	Audio._last_battle_track = ""
	Audio._senkou_used = false
	var got: Array[String] = []
	for i in 4:
		got.append(Audio.bgm_name(Audio.Bgm.BATTLE))
	t.ok(got.has("senkou"),
		"★ 剧情模式下歌单里的 senkou 照放（Q11：规则一致 —— 歌单是玩家的明确选择）")
	t.ok(Audio._senkou_used,
		"……并且这一局被标记成'用过閃光' ⇒ 该局结算曲变特殊结算曲（这是必须让用户知情的连带变化）")
	Audio.set_story_mode(false)

	Audio.battle_pool = pool_back
	Audio._battle_bag = bag_back
	Audio._last_battle_track = last_back
	Audio._senkou_used = senkou_back
	Audio.lock_battle_track(lock_back)
	Settings.set_battle_playlist(pl_back)


## ⑤ 换歌单要清洗牌袋。
##
## ⚠️ 不清的症状：改完歌单，下一局**还先放歌单外的曲**（袋子里有旧池的残余），
## 而且**不报错**。这里的做法是"唯一读它的地方发现变了就清"，
## 所以这条断言只要"改了歌单 ⇒ 袋子空"就够了，不需要模拟任何调用顺序。
static func _bag(t: T) -> void:
	var pool_back: Array = Audio.battle_pool
	var bag_back: Array = Audio._battle_bag.duplicate()
	var last_back: String = Audio._last_battle_track
	var lock_back: String = Audio._locked_battle_track
	var req_back: String = Audio.requested_battle_open
	var pl_back: Array[String] = Settings.battle_playlist

	Audio.battle_pool = SoundBank.BATTLE_TRACKS
	Audio.lock_battle_track("")
	Audio.request_battle_open("")

	var trio: Array = [str(SoundBank.BATTLE_TRACKS[0]), str(SoundBank.BATTLE_TRACKS[1]),
		str(SoundBank.BATTLE_TRACKS[2])]
	Settings.set_battle_playlist(trio)
	Audio._battle_bag.clear()
	Audio.effective_battle_pool()          # 让"上次见到的值"跟上，模拟已经打过一局
	Audio.bgm_name(Audio.Bgm.BATTLE)
	Audio.bgm_name(Audio.Bgm.BATTLE)
	t.eq(Audio._battle_bag.size(), 1,
		"（对照）抽了 2 次 ⇒ 袋子里还剩 1 首（3 首的袋子）")

	var other: Array = [str(SoundBank.BATTLE_TRACKS[3]), str(SoundBank.BATTLE_TRACKS[4]),
		str(SoundBank.BATTLE_TRACKS[5])]
	Settings.set_battle_playlist(other)
	Audio.effective_battle_pool()
	t.eq(Audio._battle_bag.size(), 0,
		"★ 歌单变了 ⇒ 洗牌袋被清空（不清的话旧池残余会先被放出来：'改完歌单还放歌单外的曲'）")

	Audio.battle_pool = pool_back
	Audio._battle_bag = bag_back
	Audio._last_battle_track = last_back
	Audio.lock_battle_track(lock_back)
	# ⚠️ 写用**方法**（`Audio.request_battle_open(x)`）而不是属性赋值：
	# 这个方法与那个变量**同名**，属性赋值在静态上下文里会被解析成"给方法赋值"。
	Audio.request_battle_open(req_back)
	Settings.set_battle_playlist(pl_back)


## ⑥ 持久化：往返 / 优雅退化 / 隔离白名单。
static func _persist(t: T) -> void:
	var pl_back: Array[String] = Settings.battle_playlist
	var path := Settings.config_path()

	# ---- 往返 ----
	Settings.set_battle_playlist(["plazma", "unicorn", "invoke"])
	Settings.battle_playlist = []            # 抹掉内存值（不调 set_*，免得又写一次盘）
	Settings.load_config()
	t.eq(Settings.battle_playlist.size(), 3, "存 → 读往返：三首都回来了")
	t.eq(str(Settings.battle_playlist[2]), "invoke", "……顺序也保住了（页头按加入顺序显示）")

	# ---- 档里有非法项 / 超上限 ----
	var cfg := ConfigFile.new()
	t.eq(cfg.load(path), OK, "（对照）能读到临时存档")
	cfg.set_value("audio", "battle_playlist",
		["plazma", "__no_such_track__", "unicorn", "", "invoke", "freedom",
			"vigilante", "reborn"])
	cfg.save(path)
	Settings.battle_playlist = []
	Settings.load_config()
	t.eq(Settings.battle_playlist.size(), Settings.PLAYLIST_MAX,
		"档里 8 项（含 2 个非法）⇒ 读回正好上限 %d 首" % Settings.PLAYLIST_MAX)
	var bad: Array[String] = []
	for k in Settings.battle_playlist:
		if not SoundBank.is_battle_pick(str(k)):
			bad.append(str(k))
	t.eq(bad.size(), 0, "读回的每一项都合法（野键被剔除）：%s" % str(bad))

	# ---- 一首被删掉的曲：只掉那一首 ----
	cfg.set_value("audio", "battle_playlist", ["plazma", "deleted_track_xyz", "unicorn"])
	cfg.save(path)
	Settings.battle_playlist = []
	Settings.load_config()
	t.eq(Settings.battle_playlist.size(), 2,
		"★ 档里有一首**已经删掉的曲** ⇒ 只掉那一首、其余照常（不是整单丢弃）")

	# ---- 老存档：没有这个键 ----
	var cfg2 := ConfigFile.new()
	cfg2.load(path)
	cfg2.erase_section_key("audio", "battle_playlist")
	cfg2.save(path)
	Settings.battle_playlist = ["plazma"]
	Settings.load_config()
	t.eq(Settings.battle_playlist.size(), 0,
		"★ 老存档里没有这个键 ⇒ 读成空歌单（行为与加这个功能之前逐字一致）")

	# ---- 隔离白名单 ----
	t.ok(Settings.PERSISTED_VARS.has("battle_playlist"),
		"★★ `PERSISTED_VARS` 里有 `battle_playlist`（漏了 ⇒ 隔离静默漏掉它，而所有断言照样绿）")
	var settings_src := SuiteUiStyle._code(SETTINGS_SOURCE)
	t.ok(settings_src.contains("cfg.set_value(\"audio\", \"battle_playlist\", battle_playlist)"),
		"写盘那一行的第三个实参是**裸变量名**（`suite_settings_isolation` 的清单对账扫的就是它）")

	Settings.set_battle_playlist(pl_back)
	Settings.save_config()


## ⑦ 接线：设置行 / 子屏 / 复用 `confirm` / 六张输入表不动。
static func _ui(t: T) -> void:
	var menu_src := SuiteUiStyle._code(MENU_SOURCE)
	var audio_src := SuiteUiStyle._code(AUDIO_SOURCE)

	t.ok(menu_src.contains("{\"key\": \"battle_playlist\", \"label\": \"战斗歌单\"}"),
		"设置页有「战斗歌单」这一行")
	t.ok(_body(menu_src, "func _setting_value_text(").contains("\"battle_playlist\":"),
		"……并且那一行的读数接了 `Settings.playlist_label()`")

	# ---- 子屏：不新增 `Stage` 枚举值（照 LAN_SUB_*）----
	t.ok(menu_src.contains("const BGM_SUB_PICK := 0") and menu_src.contains("const BGM_SUB_LIST := 1"),
		"歌单是 `Stage.BGM` 的**第二个子屏**（用户拍板 Q12「新子屏」）")
	t.not_ok(menu_src.contains("Stage.BGM_LIST"),
		"★★ 用的是 `BGM_SUB_*` 常量 —— **没有**新增 `Stage` 枚举值（加一个值要同步改四处，漏一处就是'没反应'）")
	t.ok(menu_src.contains("func _draw_bgm_list_stage("), "歌单页有自己的绘制")

	# ---- 一键两义：只读 `confirm`，不跟 `fire_gun` ----
	t.not_ok(_body(menu_src, "func _read_bgm_input(").contains("fire_gun"),
		"★★ 两个子屏的 `confirm` 分支都**不跟** `fire_gun`（手柄长按 A = 辅助飞行，跟了会撞心智）")
	var iso := _body(menu_src, "func _playlist_toggle_row(")
	t.ok(iso.contains("Audio.play_ui(\"ui_confirm\")"),
		"加入播 `ui_confirm`")
	t.ok(iso.contains("Audio.play_ui(\"ui_return\")"),
		"★ 移出 / 被拒播 `ui_return`（两个方向听觉上能分辨 —— 同一个键有相反效果时这是最低限度的反馈）")
	t.ok(iso.contains("Settings.toggle_playlist_track("),
		"toggle 的规则在数据层（UI 只调，不重写'满没满 / 在不在'）")

	# ---- 六张输入表一张都不碰（拍板 Q13「复用」）----
	var inp_src := SuiteUiStyle._code(INPUT_SOURCE)
	t.not_ok(inp_src.contains("playlist"),
		"★★ 输入表里**没有**任何 `playlist*` 动作（Q13「复用 confirm」⇒ 六张表一个字都不用动）")

	# ---- 生效池用在取样处；锁曲校验仍读默认池（互为反证）----
	var bn := _body(audio_src, "func bgm_name(")
	t.ok(bn.contains("bag_next(_battle_bag, _last_battle_track, effective_battle_pool(), _rng)"),
		"★ 轮换取样读**有效池**")
	t.ok(bn.contains("battle_pool.has(_locked_battle_track)"),
		"★★ 锁曲池校验读**默认池** —— 与上一条互为反证：改错任何一个方向都会有一条红")


# ============================================================ 工具

## 切出某个函数的正文：从 `func <sig>` 到下一个顶层 `func ` 之前。
##
## ⚠️ 必须按函数切，不能整文件扫 —— `bgm_row = ` 这类串在别的函数里**本来就该有**。
static func _body(src: String, sig: String) -> String:
	var head := src.find(sig)
	if head < 0:
		return ""
	var nxt := src.find("\nfunc ", head + 1)
	if nxt < 0:
		return src.substr(head)
	return src.substr(head, nxt - head)
