class_name SuiteBgmPreview
extends RefCounted
## 战斗BGM 试听（★63-22）的测试。
##
## 用户 2026-10-08：「做一个试听系统：玩家划到每首曲子上都会有 2s 的渐入效果，
## 播放曲子前面十五秒」。
##
## ## 这个套件能证什么 / 什么只能真机证
## ⚠️ headless 是 **Dummy 音频驱动**：**不混音** ⇒ `get_playback_position()` **不推进**。
## 所以"文件真的被解码了"这一半本套件**证不了**，由真机探针
## `tools/_r63_22_bgm_preview.tscn` 出图 + 读 `pos` 推进来证。
## ⚠️ **★63-22 实测修正 ★63-20 的一个说法**：★63-20 记的是
## 「`--headless` 下 `AudioStreamPlayer.playing` **恒 false**」—— **在本机不成立**：
## 探针在无头下跑同样读到 `playing == true`（见 `r6322_probeA` 的第一趟无头日志）。
## ⇒ 「在播」这条**不是真机专有证据**，别拿它当"真的响了"的凭据
## （本套件因此**不**用 `playing` 做任何断言）。
##
## 本套件证的是三件更基础的事：
##   ① **参数**是用户说的那两个数（2.0 / 15.0），而且 2.0 **含在** 15.0 里（拍板 Q1）；
##   ② **状态机**对（换一首 / 同一首不重启 / 划到「随机」行会停 / 停得掉）；
##   ③ 试听**不污染 BGM 状态**（这是本设计最硬的一条架构约束）。
##
## ## ⭐ 一个意外的好消息：**渐入曲线在 headless 里就能测**
## Tween 由 `SceneTree` 驱动，**与音频驱动无关** ⇒ `volume_db` 会真的随时间涨。
## 所以"2 秒渐入"这条**不需要真机**也能拿到可红的证据（真机只是多一条独立的旁证）。
## ⇒ 本套件真的等 2.4 秒去采样曲线（负对照：把 `PREVIEW_FADE_IN` 改成 0 ⇒ 立刻满音量 ⇒ 红）。
##
## ## ⚠️ 为什么**不**在这里等满 15 秒
## 那是 15.6 秒的硬成本，而"15 秒到点会停"由真机探针证（它本来就要跑一次真机）。
## 本套件改钉**接线**：秒表存在、是一次性的、窗口 = `PREVIEW_SECONDS`。
## 「枚举对 + 接线对 + 到点行为在别处证」三件加起来才没有空洞。


const PREVIEW_SOURCE := "scripts/audio/audio_director.gd"
const MENU_SOURCE := "scripts/ui/main_menu.gd"


static func run(t: T, host: Node) -> void:
	t.suite("战斗BGM / 试听参数（用户原话里的两个数）")
	_params(t)
	t.suite("战斗BGM / 试听状态机 + 2 秒渐入曲线")
	await _state_machine(t, host)
	t.suite("战斗BGM / 试听不污染 BGM 状态")
	_no_pollution(t)
	t.suite("战斗BGM / 试听接线（唯一触发点 · 页内漏斗 · 不借 BGM 播放器）")
	_wiring(t)


## ① 参数：两个数字是用户说的，且 2 s **含在** 15 s 内。
static func _params(t: T) -> void:
	t.eq(Audio.PREVIEW_FADE_IN, 2.0,
		"渐入 = 2 秒（用户原话「2s 的渐入效果」）")
	t.eq(Audio.PREVIEW_SECONDS, 15.0,
		"试听总时长 = 15 秒（用户原话「播放曲子前面十五秒」）")
	# ⚠️ 这一条就是拍板 Q1「1.包含」的**可红**形式：另一读法是"2 + 15 = 17 秒"，
	# 两版差 2 秒、肉眼与耳朵都分不出来 ⇒ 只能钉常量。
	t.lt(Audio.PREVIEW_FADE_IN, Audio.PREVIEW_SECONDS,
		"渐入**含在** 15 秒里（用户拍板「包含」；若改成'再加 15 秒'必须同时改这条）")
	t.gt(Audio.PREVIEW_FADE_OUT, 0.0, "到点有淡出（防'啪'）")
	t.lt(Audio.PREVIEW_FADE_OUT, Audio.PREVIEW_FADE_IN,
		"淡出比渐入短（收尾不该比开场还拖）")
	t.eq(Audio.PREVIEW_MIN_DB, -60.0, "起点是静音（与 BGM 交叉淡入用同一个'静音'值）")


## ② 状态机 + 渐入曲线。
static func _state_machine(t: T, host: Node) -> void:
	var track_back: String = Audio.preview_track()

	Audio.stop_preview(0.0)
	t.eq(Audio.preview_track(), "", "（对照）起点是「没有在试听」")

	var keys: Array = SoundBank.battle_pick_tracks()
	t.gt(float(keys.size()), 2.0, "（对照）自选列表至少有 3 首可以拿来测")
	var a := str(keys[0])
	var b := str(keys[1])

	# ---- 起播 / 渐入的起点 ----
	Audio.preview_bgm(a)
	t.eq(Audio.preview_track(), a, "preview_bgm(A) ⇒ 正在试听 A")
	t.eq(Audio.preview_volume_db(), Audio.PREVIEW_MIN_DB,
		"起播音量 = −60 dB（渐入必须从静音开始，否则'渐入'这两个字没有意义）")
	t.ok(Audio._preview_timer != null, "试听有自己的秒表（15 秒到点靠它，不靠逐帧累加）")
	t.ok(Audio._preview_timer.one_shot, "秒表是一次性的（循环的话试听永远停不下来）")
	t.eq(Audio._preview_timer.wait_time, Audio.PREVIEW_SECONDS,
		"秒表窗口 = `PREVIEW_SECONDS`（探针读的就是这个窗口到点后停没停）")

	# ---- 渐入曲线：0 → 2 s ----
	var v0 := Audio.preview_volume_db()
	await host.get_tree().create_timer(1.0).timeout
	var v1 := Audio.preview_volume_db()
	# ⚠️ 这两条是"2 秒渐入"的**直接证据**（不是查常量），而且**能红**：
	# 把 `PREVIEW_FADE_IN` 改成 0 ⇒ 起播即 0 dB ⇒ 下面第一条立刻 FAIL。
	t.gt(v1, v0 + 5.0,
		"1 秒后音量已经明显在升（%.1f → %.1f dB）" % [v0, v1])
	t.lt(v1, -1.0,
		"1 秒时**还没到满音量**（2 秒渐入 ⇒ 中点约 −30 dB；实测 %.1f dB）" % v1)
	await host.get_tree().create_timer(1.4).timeout
	var v2 := Audio.preview_volume_db()
	t.ok(absf(v2) < 0.5,
		"2.4 秒后已到满音量（0 dB；实测 %.2f dB）—— 渐入在 2 秒内走完" % v2)

	# ---- 同一首再调一次：**不重启** ----
	# ⚠️ 靠"音量已经到顶"来判：真重启的话它会掉回 −60。
	Audio.preview_bgm(a)
	t.eq(Audio.preview_track(), a, "同一首再调 ⇒ 仍然是 A")
	t.ok(Audio.preview_volume_db() > -1.0,
		"……并且音量**没有掉回 −60**（同一首不重启；重启了这里会读到 −60）")

	# ---- 换一首 ----
	Audio.preview_bgm(b)
	t.eq(Audio.preview_track(), b, "换一首 ⇒ 正在试听 B")
	t.eq(Audio.preview_volume_db(), Audio.PREVIEW_MIN_DB,
		"换歌时音量重新回到 −60（新的那一首也要从头渐入）")

	# ---- 划到「随机」行：**停**（那一行背后没有具体的曲）----
	Audio.preview_bgm("")
	t.eq(Audio.preview_track(), "", "`preview_bgm(\"\")`（划到「随机（洗牌袋轮换）」那一行）⇒ 停掉")

	# ---- 野键：停（不许把野键喂进 load）----
	Audio.preview_bgm(a)
	Audio.preview_bgm("__no_such_track__")
	t.eq(Audio.preview_track(), "", "野键名也会停掉（它不是一个合法的自选值）")

	# ---- 显式停 ----
	Audio.preview_bgm(a)
	Audio.stop_preview(0.0)
	t.eq(Audio.preview_track(), "", "`stop_preview()` 之后 = 没有在试听")

	# 还原（套件之间共用同一个 autoload ⇒ 必须还回去）
	Audio.stop_preview(0.0)
	if track_back != "":
		Audio.preview_bgm(track_back)


## ③ 试听**不动** BGM 状态 —— 本设计最硬的一条架构约束。
##
## 这条钉的是"试听**必须**是独立播放器"这个决定：一旦有人图省事借了
## `_bgm_players`，这里三条会**一起红**（那才是对的 —— 那不是小修，是架构走错）。
static func _no_pollution(t: T) -> void:
	var kind_back: int = Audio.current_bgm()
	var track_back: String = Audio.current_bgm_track()
	var pool_back: Array = Audio.battle_pool
	var req_back: String = Audio.requested_battle_open
	var bag_back: Array = Audio._battle_bag.duplicate()
	var last_back: String = Audio._last_battle_track

	var keys: Array = SoundBank.battle_pick_tracks()
	Audio.preview_bgm(str(keys[0]))
	Audio.preview_bgm(str(keys[1]))
	Audio.stop_preview(0.0)

	t.eq(Audio.current_bgm(), kind_back,
		"★ 试听**不改** `_bgm_kind`（借 BGM 播放器的话，退出设置页时 BGM 场景就是错的）")
	t.eq(Audio.current_bgm_track(), track_back,
		"★ 试听**不改** `current_bgm_track()`（菜单曲还是菜单曲）")
	t.eq(Audio.battle_pool, pool_back, "试听**不改** `battle_pool`")
	t.eq(Audio.requested_battle_open, req_back, "试听**不消费**'本场开场曲'那个请求")
	t.eq(Audio._last_battle_track, last_back, "试听**不清** `_last_battle_track`")
	t.eq(Audio._battle_bag, bag_back, "试听**不动**洗牌袋（试听不是'放了一首战斗曲'）")

	# 试听走 BGM 总线（曲 = 曲，不该跟着「音效音量」走）
	t.ok(Audio._preview != null and Audio._preview.bus == Settings.BUS_BGM,
		"试听播放器走 `BUS_BGM`（跟随玩家的「BGM 音量」；走 SFX 的话'把音效调小'会连带把试听调没）")


## ④ 接线：**唯一触发点** + **页内漏斗** + **不借 BGM 播放器**。
##
## ⚠️ 这几条全是**源码扫描**，因为它们的反面是"看起来接好了、实际永远不会被调到"
## —— 那正是本仓库最容易骗过自己的一种失败（`_set_focus()` 的死代码分支）。
static func _wiring(t: T) -> void:
	var menu_src := SuiteUiStyle._code(MENU_SOURCE)
	var audio_src := SuiteUiStyle._code(PREVIEW_SOURCE)

	t.eq(_count(menu_src, "Audio.preview_bgm("), 1,
		"★ `preview_bgm(` 在菜单里**恰好出现 1 次**（两处触发 ⇒ 两个子屏行为分叉）")
	var funnel := _body(menu_src, "func _bgm_set_row(")
	t.ok(funnel != "", "（对照）切出了 `_bgm_set_row()` 的正文")
	t.ok(funnel.contains("Audio.preview_bgm("),
		"★ 那唯一的一次就在**页内漏斗** `_bgm_set_row()` 里")
	t.ok(funnel.contains("_bgm_write_row("),
		"漏斗里调 `_bgm_write_row()`（两个子屏唯一不同的那一处）")

	# ⚠️ Q6 拍板「键盘移到」⇒ 这一页**不做鼠标几何**。
	# 所以试听**不能**挂在 `_set_focus()` 上 —— 那个分支会是死代码。
	# 这三条把"不做鼠标"这个决定本身钉住（否则将来有人加了鼠标，
	# 会以为"顺手也在 `_set_focus` 里加一份"是对的）。
	var geom := _body(menu_src, "func _list_geometry(")
	t.not_ok(geom.contains("Stage.BGM"),
		"★ `_list_geometry()` 里**没有** `Stage.BGM` 分支（拍板 Q6：这一页不做鼠标 ⇒ 仍是 `Geo.NONE`）")
	t.not_ok(_body(menu_src, "func _focus_index(").contains("Stage.BGM"),
		"……`_focus_index()` 也不加（那一页永远不会调它，加了是死代码）")
	t.not_ok(_body(menu_src, "func _set_focus(").contains("Stage.BGM"),
		"……`_set_focus()` 也不加（**试听**正是因此才不能挂在这儿）")

	# 两个子屏换行都只能走漏斗（裸赋值 = 那一路没有试听）
	var rb := _body(menu_src, "func _read_bgm_input(")
	t.ok(rb.contains("_bgm_set_row("), "两个子屏的换行都走 `_bgm_set_row()`")
	t.not_ok(rb.contains("bgm_row = "),
		"★★ ……并且没有裸写 `bgm_row`（绕过漏斗 = 那一路没有试听，且只有走到那页才发现）")
	t.not_ok(rb.contains("playlist_row = "), "★★ ……也没有裸写 `playlist_row`")
	var writer := _body(menu_src, "func _bgm_write_row(")
	t.ok(writer.contains("bgm_row = i") and writer.contains("playlist_row = i"),
		"两个子屏的'写行'都收在 `_bgm_write_row()` 一处")

	# 独立播放器 + 独立 Tween
	t.ok(audio_src.contains("_preview = AudioStreamPlayer.new()"),
		"★ 试听有自己的播放器（借 `_bgm_players` 会写坏菜单 BGM 状态）")
	t.ok(audio_src.contains("_preview_tween"),
		"★ ……也有自己的 Tween（共用 `_tween` 会被 `_crossfade()` 的 `kill()` 打断）")
	t.not_ok(_body(audio_src, "func preview_bgm(").contains("_bgm_players"),
		"★★ `preview_bgm()` 正文里**一次都没提** `_bgm_players`（最强的形式证据）")

	# 兜底：`play_bgm()` 首行无条件停试听
	var pb := _body(audio_src, "func play_bgm(")
	t.ok(pb.substr(0, mini(pb.length(), 800)).contains("stop_preview("),
		"★ `play_bgm()` **开头**就停试听（一处声明、全局成立 —— 出击/回菜单/进结算都不用各自追）")

	# 离开这两页时停（`_tick_bgm_page()` 是唯一的进入/离开判定点）
	t.ok(menu_src.contains("func _tick_bgm_page("),
		"菜单侧有唯一的进入/离开判定点 `_tick_bgm_page()`")
	t.ok(_body(menu_src, "func _tick_bgm_page(").contains("Audio.stop_preview()"),
		"……离开时停试听（追每一条离开路径的话，漏一条就是'试听在战斗里还在响'）")

	# 后缀删了、但信息没丢（R1 与 R2 在这里闭合）
	t.ok(menu_src.contains("BGM_OPT_IN_MARK"),
		"选歌页/歌单页用 `◆` 标记取代了被删掉的「（仅自选 · 不参与随机）」后缀")


# ============================================================ 工具

## 切出某个函数的正文：从 `func <sig>` 到下一个顶层 `func ` 之前。
##
## ⚠️ 必须按函数切，不能整文件扫 —— 例如 `bgm_row = ` 在 `_read_settings_input()`
## 里**本来就该有**（那一行是按 Enter 打开子屏），整文件扫会误报。
static func _body(src: String, sig: String) -> String:
	var head := src.find(sig)
	if head < 0:
		return ""
	var nxt := src.find("\nfunc ", head + 1)
	if nxt < 0:
		return src.substr(head)
	return src.substr(head, nxt - head)


## 子串出现次数。
static func _count(hay: String, needle: String) -> int:
	var n := 0
	var at := hay.find(needle)
	while at >= 0:
		n += 1
		at = hay.find(needle, at + needle.length())
	return n
