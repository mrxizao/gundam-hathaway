extends Node
## 音频总控（autoload 名 `Audio`）。
##
## ## 三条播放通道，用法完全不同，别混
##   1. **BGM**：非定位，整个流程只有一首在播（菜单 / 战斗 / 结算），切换带淡入淡出。
##   2. **play_self / play_ui**：非定位。玩家自己发出的声音（座舱警报、自己的枪声）
##      和界面音都用这条 —— 它们不该有距离衰减。
##   3. **play_3d**：定位。别人的爆炸、别人的武器、引擎循环用这条，
##      所以"敌机离得远就听不见"是引擎自己算的，不需要手写距离判断。
##
## ## 引擎循环由使用方自己持有
## `make_loop_3d()` 返回一个已配置好但**未播放**的节点，由 FlightBody 挂到自己身上。
## 这样音频位置天然跟随机体，不用每帧同步坐标。
##
## ⚠️ 3D 播放器必须挂在当前场景（Node3D）下面才能正确定位，
## 所以 play_3d 会把临时播放器 add_child 到 `get_tree().current_scene`。
##
## ## ★63-23 音量细分：通道决定"送到哪条总线"，全部走 `_bus_for()`
## 分派表是 `SoundBank.SFX_BUS`（音效名 → `VULCAN` / `SABER` / `RIFLE` /
## `FUNNEL` / `ALARM` / `ENGINE`，未列出的送 `SFX`）。
## 四条音效通道（含 `make_loop_3d` 造的引擎循环）**都要接**，
## 少接一条的症状是"那条通道不归它的滑条管"，只有那一条听得出不对。

enum Bgm { NONE, MENU, BATTLE, RESULT, TRAINING }

const FADE_DEFAULT := 1.1
## **一轮之内换下一首**时的衔接淡入时长（战斗曲轮换 / ★63-25 主菜单曲轮换共用）。
##
## 上一首是**自然放完**的（不是被切掉的），所以这里不需要长淡出，只要避开硬切的"啪"。
## ⚠️ 别拿它当一般的换场景淡入：进战斗 / 回菜单是**被人为打断**的，那点尾巴要用
## `FADE_DEFAULT` 盖过去 —— 0.4 s 会让人听出"啪"。
## ⚠️ 原名 `BATTLE_ROTATE_FADE`；★63-25 主菜单曲也开始轮换，改名而不是加一个同值别名
##（别名会让"到底该用哪个"变成一个靠记性的问题，而这里两者**本来就该是同一个数**）。
const ROTATE_FADE := 0.4

# ============================================================ ★63-22 试听
#
# 需求原文（用户 2026-10-08）：「做一个试听系统：玩家划到每首曲子上都会有 2s 的
# 渐入效果，播放曲子前面十五秒」。
#
# ## ⚠️ 「15 秒」是**总时长**，2 s 渐入**含在里面**（用户拍板 Q1 =「1.包含」）
# 即：t=0 起播（−60 dB）→ t=2 s 到满音量 → 再放 13 s → **t=15 s 开始淡出** →
# t≈15.3 s 必须已经停了。
# ⚠️ 被否掉的另一读法是"渐入 2 s 再加 15 s"（共 17 s）。**两版差 2 s，
# 肉眼/耳朵都分不出来** —— 所以判据把这两个数字都钉死（`suite_bgm_preview`），
# 探针读的是"15 s 附近已停"而不是"17 s 附近"。

## 试听渐入时长（秒）。用户原话里的「2s」。
const PREVIEW_FADE_IN := 2.0
## 试听总时长（秒）。用户原话里的「前面十五秒」。**含**上面的渐入。
const PREVIEW_SECONDS := 15.0
## 到点淡出时长（秒）。防"啪"。
const PREVIEW_FADE_OUT := 0.3
## 试听播放时的起点音量（dB）。与 `_crossfade()` 用的同一个"静音"值。
const PREVIEW_MIN_DB := -60.0

## 试听时菜单 BGM 的压低量（dB）。见 `set_menu_duck()`。
const MENU_DUCK_DB := -12.0
## 压低/恢复的过渡时长（秒）。
const MENU_DUCK_FADE := 0.35

## 座舱告警语音的固定音量（dB）。
##
## ⚠️ **写死，不走调用方传参**：语音是"救命提示"，音量必须可预期。
## 如果让它跟着别的音效一起被调（例如"这一枪在这个场合该多响"那种场合音量），
## 玩家调武器滑条就会把"拉起告警"一起调没。这里拒绝的是
## **在代码里给它一个会变的基准** —— 它自己的滑条（★63-23 的「警报」）是另一回事：
## 那是玩家明确表达"我要警报小声一点"，不是被别的旋钮顺带拖走。
##
## ## ★63-23 之后它落在哪条总线
## 与三种合成告警同走 `ALARM`（`SoundBank.SFX_BUS`），而 `ALARM` 是 **`SFX` 的子总线**
## ⇒ ① 玩家那根「警报」滑条一次管全（合成告警 + 语音）；
##    ② 把「音效音量」拉到 0 仍然全场安静（含警报）—— 这条老语义一个字没变。
const VOICE_DB := 0.0

## name → AudioStream（按 是否循环 分两份缓存）
var _streams := {}
var _last_play := {}
var _bgm_players: Array[AudioStreamPlayer] = []
var _bgm_active := 0
var _bgm_kind := Bgm.NONE
## 当前正在播的 BGM 名（`SoundBank.BGM` 的键）。测试与调试用。
var _bgm_track := ""
var _tween: Tween
## 菜单 BGM 的**压低量**（dB，`0.0` = 不压）。★63-22：进选歌页/歌单页时压到 `MENU_DUCK_DB`。
##
## ⚠️ 它必须是**状态**，不能是一次性赋值。`_crossfade()` 的收尾会把目标播放器的
## `volume_db` tween 到 `0.0` ⇒ 写成 `_bgm_players[_bgm_active].volume_db = MENU_DUCK_DB`
## 会在**下一次任何 crossfade**（换曲、回菜单、进结算…）被冲掉。
## 症状很阴：在选歌页待着不动没事，只要菜单曲换了一次，菜单 BGM 自己变响了。
## ⇒ 唯一真源是这个变量，`_crossfade()` 与 `set_menu_duck()` 都施加它。
var _menu_duck_db := 0.0

## ---- ★63-22 试听（选歌页 / 歌单页划到哪首放哪首）----
#
## ## 为什么必须是**独立播放器 + 独立 Tween**
## ① `_bgm_players` 承载**菜单 BGM 的状态**（`_bgm_kind` / `_bgm_active` / `_bgm_track`）——
##    试听借一路过去，玩家退出设置页时菜单 BGM 的状态就是错的；
## ② 那两个是**交叉淡入**结构：`_crossfade()` 会 `_tween.kill()` 掉上一个 Tween ——
##    试听的 2 s 渐入若共用它，会被菜单 BGM 的淡入直接打断。
## ⇒ 试听是**菜单专属的叠加层**，不是一种"BGM 场景"，所以**不进 `enum Bgm`**。
##
## ⚠️⚠️ **不许碰 `loop`**。`play_bgm()` 曾在共享资源上 `_apply_loop()` 栽过一次
##（症状：对战打完一首卡住、再也不换曲，且一行报错都没有）。
## 试听**不循环**，所以现在本来就不改 loop —— 将来谁要加"循环试听"，
## **必须先 `duplicate()` 再改**，别直接改 `load()` 出来的那一份。
var _preview: AudioStreamPlayer = null
## 正在试听的键（`""` = 没在试听）。测试与探针读它（无头下 `playing` 恒 false，见下）。
var _preview_track := ""
## 只管试听的渐入/淡出，与 `_tween`（BGM 交叉淡入）**互不干涉**。
var _preview_tween: Tween
## 15 秒到点的秒表。用 `Timer` 而不是每帧累加：试听的长度不该跟着帧率走。
var _preview_timer: Timer = null
## 当前正在播的那条**告警语音**的播放器（同一时刻只允许一条，见 `play_voice()`）。
var _voice_player: AudioStreamPlayer = null

## 玩家歌单**上一次见到的值**（`Settings.battle_playlist` 的影子，只用来判"变了没有"）。
##
## ⚠️ 歌单的**唯一真源是 `Settings.battle_playlist`**，这里刻意**不做镜像**：
## 镜像会带来"两边不同步"这条本工程最怕的失败 —— 症状是"歌单设了、战斗里不放"，
## 而两边都不报错。这里只留一个"上次是什么"，用途只有一个：**发现变化时清洗牌袋**。
var _playlist_seen: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Bgm%d" % i
		p.bus = Settings.BUS_BGM
		# 一首放完就轮换下一首（战斗曲 / ★63-25 主菜单曲都不循环，见 play_bgm）
		p.finished.connect(_on_bgm_finished.bind(p))
		add_child(p)
		_bgm_players.append(p)
	# ★63-22 试听：**第三个播放器**，与上面两个交叉淡入的完全无关（见 `_preview` 的注释）。
	# ⚠️ 走 `BUS_BGM`：它跟随玩家的「BGM 音量」设置（试听的是曲，不是音效）。
	_preview = AudioStreamPlayer.new()
	_preview.name = "Preview"
	_preview.bus = Settings.BUS_BGM
	_preview.volume_db = PREVIEW_MIN_DB
	add_child(_preview)
	# 15 秒到点。⚠️ `process_mode` 继承自本节点（`ALWAYS`）⇒ 暂停游戏时也照走，
	# 但试听只可能发生在菜单里，这条只是"别在暂停态卡住"的保险。
	_preview_timer = Timer.new()
	_preview_timer.name = "PreviewTimer"
	_preview_timer.one_shot = true
	_preview_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_preview_timer.timeout.connect(_on_preview_timeout)
	add_child(_preview_timer)
	_rng.randomize()


# ============================================================ 资源

func _stream(name: String, looping: bool) -> AudioStream:
	var key := name + ("#loop" if looping else "")
	if _streams.has(key):
		return _streams[key]
	var path := SoundBank.sfx_path(name)
	if path == "" or not ResourceLoader.exists(path):
		_streams[key] = null
		return null
	var base := load(path)
	if base == null:
		_streams[key] = null
		return null
	var s: AudioStream = base
	if looping:
		# 直接改共享资源会把"一次性"用法也变成循环，所以循环版要复制一份再设 loop
		s = base.duplicate() as AudioStream
		_apply_loop(s, true)
	_streams[key] = s
	return s


## 把 `on` 写进这个流的 loop 位（MP3 / OGG / WAV 三种载体各有各的字段名）。
##
## ⚠️ 它**就地改**（不复制）—— 所以调用方必须先确认这个流是**私有的**
##（`_stream()` 里复制过，或 `play_bgm()` 的惰性复制复制过）。
## 直接喂 `load()` 拿到的共享实例 = 写穿，见 `play_bgm()` 里那段说明。
func _apply_loop(s: AudioStream, on: bool) -> void:
	var mp3 := s as AudioStreamMP3
	if mp3 != null:
		mp3.loop = on
		return
	var ogg := s as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = on
		return
	var wav := s as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED


## `_apply_loop()` 的**读数版**：这个流现在循环吗。给 `play_bgm()` 的惰性复制当判据，
## 也让测试/探针能用**同一个**口径问"到底循环不循环"（各写一份 if-else 迟早分叉）。
func _loop_of(s: AudioStream) -> bool:
	if s == null:
		return false
	var mp3 := s as AudioStreamMP3
	if mp3 != null:
		return mp3.loop
	var ogg := s as AudioStreamOggVorbis
	if ogg != null:
		return ogg.loop
	var wav := s as AudioStreamWAV
	if wav != null:
		return wav.loop_mode != AudioStreamWAV.LOOP_DISABLED
	return false


## 某个用途下的 BGM 该不该循环。**纯函数**（测试逐档钉，见 `suite_audio`）。
##
## | 用途 | 循环 | 为什么 |
## |---|---|---|
## | `MENU` | **否** | ★63-25：三首随机轮换，靠 `finished` 换下一首 |
## | `BATTLE`（没锁曲） | 否 | 战斗曲轮换，同上 |
## | `BATTLE`（`locked`） | **是** | 本关锁曲：一关从头到尾就这一首 |
## | `RESULT` / `TRAINING` | 是 | 一直是单曲循环（用户没要求改） |
##
## ⚠️ 这张表是**唯一真源**：`play_bgm()` 只读它，不再内联写布尔括号。
## 内联版（`kind != Bgm.BATTLE or lock_loop`）在 ★63-25 加"菜单曲也要轮换"时，
## 会让这个决定散落进一个括号里 —— 而它正是"改一行、两个场景一起变"的那种地方。
static func bgm_should_loop(kind: int, locked := false) -> bool:
	if kind == Bgm.MENU:
		return false
	if kind == Bgm.BATTLE:
		return locked
	return true


## 这条音效该走哪条总线（★63-23 音量细分）。
##
## 分派表在 `SoundBank.SFX_BUS`（音效名 → 子总线名）；表里没有的名字
## **送 `SFX`**（= 未分类音效：爆炸、UI、变形、起飞……）。
##
## ⚠️ 四条播放通道（`play_self` / `play_3d` / `play_voice` / `make_loop_3d`）
## **全部**走这一个函数：少接一条的症状是"有一条通道不归那根滑条管"，
## 而且**只有那一条**听得出不对 —— 例如"自己开炮变响了、敌机开炮没变"。
## 面板上的层级与总线树是同一棵树：`SFX` → {VULCAN,SABER,RIFLE,FUNNEL,ALARM,ENGINE}。
func _bus_for(name: String) -> String:
	var b := SoundBank.bus_for(name)
	return b if b != "" else Settings.BUS_SFX


## 给 FlightBody 用：造一个配置好、还没播放的循环 3D 播放器（调用方自己 add_child）。
func make_loop_3d(name: String, max_distance := 3200.0, positional := true) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "EngineLoop"
	p.stream = _stream(name, true)
	p.max_distance = max_distance
	p.unit_size = max_distance * 0.25
	p.volume_db = -60.0
	# 玩家自己的引擎不能有距离衰减（它在座舱里，不是"世界里的一个声源"）；
	# 敌机的引擎必须是定位的 —— 需求里"靠近了才能听到"就是靠这个实现的。
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE if positional \
		else AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.panning_strength = 1.0
	# ★63-23：引擎走 `ENGINE` 子总线（它在 `SFX` 下面）⇒ 玩家的「引擎」滑条立即生效，
	# **包括正在响的那个循环**（这是选总线而不是"播放时乘系数"的决定性理由之一）。
	p.bus = _bus_for(name)
	return p


# ============================================================ BGM

func bgm_name(kind: int) -> String:
	match kind:
		Bgm.MENU:
			# ★63-25（用户 2026-10-08）：「EARth 和 Snooze 添加到主菜单歌曲内，
			# 和现在的主菜单歌曲三首随机循环播放」。
			# ⇒ 从"写死 `mobius`"变成"从 `SoundBank.MENU_TRACKS` 里洗牌袋抽一首"。
			# ⚠️ ⚠️ 这个函数**有副作用**（消耗 `_menu_bag`）—— 与 `Bgm.BATTLE` 那条一样。
			# 所以它**不是**"读一下现在放什么"的查询口：要问那个请用 `current_bgm_track()`。
			return _next_menu_track()
		Bgm.RESULT:
			# 1.2：结算曲**按地图 + 这一局用过哪首**决定（见 `result_track_for`）
			return result_track_for(_active_map_id(), _senkou_used)
		Bgm.TRAINING:
			# 训练场与艾尔斯岩结算同一首（用户指定）
			return "sweet_child"
		Bgm.BATTLE:
			# ★ 2026-10-01（轮 59）：**本关锁曲排在一切之前**。
			# 关卡作者指定的曲子（`Mission.bgm`）要放**整关** ⇒ 它必须盖过
			# 「玩家自选」（`requested_battle_open`）与「随机轮换」，而且**不消耗洗牌袋**。
			# ⚠️ 池子校验照做：锁的曲不在本模式池里 ⇒ **自动退回**轮换 ——
			# 所以「给某关写了个剧情池里没有的曲子名」不会静音，只是**锁不上**。
			# Dedicated suit themes may loop without joining the ordinary random pool.
			if _locked_battle_track != "" and (battle_pool.has(_locked_battle_track) or SoundBank.is_suit_battle_track(_locked_battle_track)):
				# 锁曲把「玩家自选」整个盖住了 ⇒ 顺手把它清掉。
				# ⚠️ 不清的症状：玩家设置页选了 A、进 M01 听的是锁曲（对），但**下一局**
				#（解锁之后）A 会突然冒出来当第一首 —— 一个**迟到了一局的请求**。
				requested_battle_open = ""
				_last_battle_track = _locked_battle_track
				if _locked_battle_track == "senkou":
					_senkou_used = true
				return _locked_battle_track
			# 战斗曲**轮流随机**：洗牌袋抽下一首（见 bag_next）。
			# 池子是 `battle_pool`（对战含閃光、剧情不含 —— 见 SoundBank 的两个常量）。
			# 批 23：出击前自选的开场曲（`request_battle_open`）优先 ——
			# 只管**本场第一首**，放完把洗牌袋重洗，剩余的歌照旧随机轮流。
			# 闸门 = **在本模式的轮换池里**（`senkou` 在剧情模式下就是这样被挡回去的）
			# **或者** 是「仅自选曲」（它按设计就不在任何池子里 —— 见
			# `SoundBank.OPT_IN_BATTLE_TRACKS`）。
			# ⚠️ 少了后半句的症状：菜单里选得中 Sweet Child O' Mine，
			# 进游戏放的却是随机的另一首，而且一行报错都没有。
			var pick := ""
			if requested_battle_open != "" and (battle_pool.has(requested_battle_open)
					or SoundBank.is_opt_in_battle_track(requested_battle_open)):
				pick = requested_battle_open
				_battle_bag.clear()
			else:
				# ★63-22：池子改成**有效池**（玩家歌单优先，否则模式默认池）。
				# ⚠️ 这是本批在 `bgm_name()` 里**唯一**改动的一行 ——
				# 上面那条开场曲闸门（`battle_pool.has(...)`）与**下面**的`if pick == "senkou"`
				# 都刻意**不读有效池**，理由分别见各自的注释。
				pick = bag_next(_battle_bag, _last_battle_track, effective_battle_pool(), _rng)
			requested_battle_open = ""
			_last_battle_track = pick
			# 記住"这一局用过閃光"—— 它决定这一局的结算曲（见 result_track_for）
			if pick == "senkou":
				_senkou_used = true
			return pick
	return ""


## 批 23 出击前自选：**下一场战斗的开场曲**（`SoundBank.battle_pick_tracks()` 的键 ——
## 轮换池里的曲，或「仅自选曲」）。
##
## 由 `main._start_fight()` 在 `play_bgm(BATTLE)` 之前写入（值来自设置页
## 「战斗BGM」行，"" = 随机）；`bgm_name(BATTLE)` **只消费一次** ——
## 本场开场放它，之后的轮换完全回到洗牌袋。不主动清空是**设置页**的事，
## 这里消费掉的是"这一场"的请求，两件事互不干扰。
var requested_battle_open := ""


func request_battle_open(track: String) -> void:
	requested_battle_open = track


## ★ 2026-10-01（轮 59）：**本关锁曲**（`Mission.bgm`）。
##
## 非空 ⇒ `Bgm.BATTLE` **永远**返回它（不走洗牌袋），而且它是**循环**的
##（见 `play_bgm` 里的 `lock_loop`）⇒ 一关从头到尾就是这一首。
##
## ## 与 `request_battle_open()` 的分工 —— 两者都能指定战斗曲，但**级别不同**
##
## | | `request_battle_open()` | `lock_battle_track()` |
## |---|---|---|
## | 谁说的 | **玩家**（设置页「战斗BGM」行） | **关卡作者**（`Mission.bgm`） |
## | 管多久 | 本场**第一首**（放完回洗牌袋） | **整关**（循环，不换） |
## | 优先级 | 低 | **高**（盖过前者） |
##
## ⚠️ 两者**都要**：`request_battle_open` 是「这一场拿哪首开头」，锁曲是
## 「这一关就这一首」。老板 2026-10-01 对 M04 说的是「演出 11 秒播放，
## **然后也作为本关的 bgm**」、对 M01 说的是「TRACER 作为 M01 的 bgm」——
## 两句要的都是**整关**，所以锁曲才是主体，`request_battle_open` 只是兜底
##（锁的曲不在池里时它还能顶第一首）。
##
## ⚠️ 池子校验**不在写入时做**：写入时 `battle_pool` 可能还没切成剧情池
##（`set_story_mode()` 与它谁先谁后是调用方的事）⇒ 校验统一在 `bgm_name()` 消费时做。
var _locked_battle_track := ""


func lock_battle_track(track: String) -> void:
	_locked_battle_track = track


## 当前锁着的本关曲（"" = 没锁）。测试与调试用。
func battle_track_locked() -> String:
	return _locked_battle_track


## 结算曲规则（**纯函数**，便于单测）：
##
## | 情况 | 曲目 | 理由 |
## |---|---|---|
## | 这一局把 `senkou` 当过战斗曲 | `special_result` | 用户："如果闪光作为战斗曲用，那么那一把的结算曲就是特殊结算曲" |
## | 艾尔斯岩 | `sweet_child` | 用户："作为在艾尔斯岩石的结算曲" |
## | 废墟靶场（训练） | `sweet_child` | 1.1 用户指定训练场用这首 |
## | 其它（太平洋上空 / **低地球轨道**） | `senkou` | 用户："闪光…作为太平洋上空的结算曲用" |
##
## ⚠️ 第一优先是"用过閃光"而不是地图：对战里在**太平洋**打、而那局抽到閃光当战斗曲时，
## 结算必须是特殊结算曲 —— 否则同一局会两次听到同一首曲子。
##
## ## ★ 低地球轨道（`Id.LEO`）的处置：**接受兜底，但把它变成一个决定**
## DESIGN §4.8.5 的坑 2 点到过这里：`result_track_for()` 对**未知 id 静默返回 `"senkou"`**，
## 而轨道图是后加的 ⇒ 它会"悄悄"用閃光当结算曲。设计稿列的处置是
## 「要么接受（閃光用在 Ξ 第一次启动的那一关，**其实很贴**），要么加一行。列为待拍板」。
##
## **拍板：接受。** 理由就是设计稿自己那句 —— M03 是**柯西（Ξ）第一次登场**的那一关
##（2026-09-30 轮 52 之后玩家开的是梅萨指挥官型上去接它，柯西就在运输仓里），
## 而閃光正是那台机体的曲子；为它单独配一首反而更差。
## ⚠️ 但**接受 ≠ 不管**：`suite_audio` 里加了一条 `Id.LEO ⇒ "senkou"` 的断言。
## ⇒ 将来谁给轨道图换了曲子而忘了同步，那条会红；而不是"谁也没发现它一直是兜底来的"。
static func result_track_for(map_id: int, senkou_used: bool) -> String:
	if senkou_used:
		return "special_result"
	if map_id == MapDef.Id.ULURU:
		return "sweet_child"
	if map_id == MapDef.Id.RANGE:
		return "sweet_child"
	return "senkou"


## 当前地图 id（拿不到就当作太平洋 —— 结算曲总得有一首）。
func _active_map_id() -> int:
	if Game.active_map != null:
		return Game.active_map.id
	return MapDef.Id.PACIFIC


## 1.2：战斗轮换池切换。剧情挑战用 `STORY_BATTLE_TRACKS`（不含 `senkou`），
## 对战用 `BATTLE_TRACKS`（含 `senkou`）。
##
## ⚠️ 这里**不许写死首数**（"三首 / 四首"那种）：两首池子迟早还会长
##（2026-09-21 就刚从 4/3 长到 6/5），写在注释里的数字一定会烂掉，
## 曲目数目的唯一真源是 `SoundBank` 里那两个常量。
## 同时重置洗牌袋与"用过閃光"的标记 —— 后者是**每局**的，跨局带过去会让
## 第二局莫名其妙地放特殊结算曲。
func set_story_mode(on: bool) -> void:
	var pool: Array = SoundBank.STORY_BATTLE_TRACKS if on else SoundBank.BATTLE_TRACKS
	if pool == battle_pool:
		_senkou_used = false
		return
	battle_pool = pool
	_battle_bag.clear()
	_senkou_used = false


var battle_pool: Array = SoundBank.BATTLE_TRACKS
var _senkou_used := false


## ★63-22：当前**生效**的轮换池 —— 玩家歌单优先，否则模式默认池。
##
## ## 为什么不把歌单写进 `battle_pool`（**本批最大的技术陷阱**）
## `battle_pool` 被 **4 个套件、6 处**直接赋值（`suite_audio` / `suite_battle_bgm_roster`
## / `suite_mission_bgm` / `suite_settings`），它是**测试依赖的公开契约**。
## 把歌单塞进去，套件里"设成默认池然后验默认行为"就**不再是它设的那个池子** ⇒
## 幽灵红（而且常常是"我这儿绿、交出去红"）。`set_story_mode()` 的
## `if pool == battle_pool:` 短路也会被搅。
## ⇒ 所以歌单**只在这里参与一次判断**，`battle_pool` 的语义一个字都不变。
##
## ## ⚠️ 副作用（清空洗牌袋）是**刻意**的
## 歌单变了就得清袋子，否则袋子里旧池的残余会先被放出来 ——
## 症状是"改完歌单，下一局还先放歌单外的曲"。把这件事放在**唯一读它的地方**，
## 而不是"让每一个修改歌单的地方记得通知"：后者漏一处就静默失效。
## 只在**检测到变化**时清，所以是幂等的，每首抽一次数组比较（≤6 项）的开销可忽略。
##
## ## ⚠️ 只有"轮换取样"读它
## **锁曲池校验**（`bgm_name()` 里 `battle_pool.has(_locked_battle_track)`）必须继续读
## `battle_pool`：关卡锁的曲（如 M01 的 `tracer`）不在玩家歌单里是**常态**，
## 改成读有效池 ⇒ 锁曲被**静默拒绝**、M01 的 TRACER 锁曲失效，一行报错都没有。
## 规则是「锁曲是作者的、歌单是玩家的，作者优先」。
func effective_battle_pool() -> Array:
	var pl: Array = Settings.battle_playlist
	if pl != _playlist_seen:
		_playlist_seen = pl.duplicate()
		_battle_bag.clear()
	return pl if not pl.is_empty() else battle_pool


var _last_battle_track := ""
## 战斗曲的"洗牌袋"：一轮一轮地放（抽空了就重洗）。
var _battle_bag: Array = []
var _rng := RandomNumberGenerator.new()

## ---- ★63-25 主菜单曲的洗牌袋（与战斗那套数学相同，但**袋子分开**）----
#
## 用户 2026-10-08：「EARth 和 Snooze 添加到主菜单歌曲内，和现在的主菜单歌曲
## 三首随机循环播放」。池子 = `SoundBank.MENU_TRACKS`。
#
## ⚠️ 与 `_battle_bag` **必须是两个袋子**：共用一个的话，玩家在菜单里听了几首，
## 战斗曲袋子就被消耗掉几个位置 —— 症状是"进战斗后第一首的随机带着菜单的痕迹"
##（而且一轮三首的"轮流"被菜单的抽取打乱，听起来就是随机坏了）。
## ⚠️ `_last_battle_track` 与 `_last_menu_track` 同理，各管各的跨轮边界。
var _menu_bag: Array = []
## 上一首主菜单曲（`bag_next` 用它保证"新一轮第一首 ≠ 上一轮最后一首"）。
var _last_menu_track := ""


## 主菜单曲：固定使用原有三首菜单音乐，独立洗牌轮换。
##
## 与 `_battle_bag` 共用 `bag_next()` 这个纯函数与同一个随机源 —— 数学只有一处。
func _next_menu_track() -> String:
	var pick := bag_next(_menu_bag, _last_menu_track, SoundBank.MENU_TRACKS, _rng)
	_last_menu_track = pick
	return pick


## 洗牌袋抽下一首 —— **纯函数**（只动传进来的 queue），所以能被测试直接喂数据验证。
##
## 为什么不用"每次 randi() 池里随机抽一首"：那样"随机"是真的，但**不轮流** ——
## 池子不大时可能连着两轮都抽到同一首，听起来就像随机坏了。
## 洗牌袋 = 把**整个池子**洗一遍依次放完，放完再洗一轮，于是：
##   1. 每一轮内每首各出现一次（真正的"轮流"）；
##   2. 新一轮的第一首**不会**和上一轮的最后一首相同（否则跨界处会连放两遍同一首）。
static func bag_next(queue: Array, last: String, pool: Array, rng: RandomNumberGenerator) -> String:
	if queue.is_empty():
		for x: String in pool:
			queue.append(x)
		shuffle_with(queue, rng)
		if queue.size() > 1 and str(queue[0]) == last:
			# 把第一首和后面任意一首换位：不换的话"上一首"会紧跟着再放一遍
			var j := 1 + int(rng.randi() % (queue.size() - 1))
			var tmp: String = queue[0]
			queue[0] = queue[j]
			queue[j] = tmp
	return str(queue.pop_front())


## Fisher-Yates。不用 `Array.shuffle()` 是为了让随机源可注入 —— 测试要能复现。
static func shuffle_with(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := int(rng.randi() % (i + 1))
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 当前正在播的那首（`SoundBank.BGM` 的键）。测试与调试用。
func current_bgm_track() -> String:
	return _bgm_track if _bgm_kind != Bgm.NONE else ""


func play_bgm(kind: int, fade := FADE_DEFAULT, force := false) -> void:
	set_bgm_paused(false)
	# ★63-22：**试听是菜单专属** —— 这一条在入口处声明一次，就不用去追每一条
	# "离开菜单"的路径（出击 / 回主菜单 / 进结算 / 训练场 / 改设置里的音量…）。
	# ⚠️ 无条件先停（`fade = 0.0`）：进战斗时"菜单试听 + 战斗曲叠着放"是最坏的结果，
	# 而试听淡出只要 0.3 s，那点尾巴不值得为它冒叠音的风险。
	stop_preview(0.0)
	# 同一首还在播就不重放 —— **战斗曲除外**：对战斗曲来说"play_bgm"的语义是
	# "接着轮换下一首"（见 `_on_bgm_finished`），必须放行。
	# ★63-25：**主菜单曲刻意不放进这个例外**。两个方向都想过 ——
	#   · 菜单曲的轮换自己带 `force`（见下），不靠这个例外放行；
	#   · 而"菜单 → 菜单"（进设置再回来、进战役图再退出来）**不该**换曲：
	#     玩家只是去别的页面转了一圈，回来接着听那半首才自然。
	# 真把 MENU 也加进例外，症状是"每点一次返回都换一首"。
	#
	# ⚠️ `force` 只给 `_on_bgm_finished()` 用（语义 = "这一首**已经放完了**，换下一首"）。
	# 少了它，菜单曲的轮换就得依赖"`finished` 信号到手时 `playing` 已经是 `false`"
	# 这个**引擎内部时序** —— 真机上成立（Godot 先 `_stop()` 再 emit `finished`），
	# 但它是条**隐式**假设。一旦不成立（换引擎版本 / 别的音频驱动 / 测试里手动发信号），
	# 症状是"菜单停在最后放完的那一首上、再也不出声"，而且**不报错** —— 本工程最怕的那种。
	# ⇒ 显式传 `force` 把这条假设消掉：放完了就该换，与"还在不在播"无关。
	if not force and kind == _bgm_kind and kind != Bgm.BATTLE \
			and _bgm_players[_bgm_active].playing:
		return
	_bgm_kind = kind
	var name := bgm_name(kind)
	if name == "":
		stop_bgm(fade)
		return
	var path := SoundBank.bgm_path(name)
	if not ResourceLoader.exists(path):
		push_warning("[Audio] BGM 不存在：%s" % path)
		return
	var s: AudioStream = load(path)
	if s == null:
		return
	# ★ 2026-10-01（轮 59）：**本关锁曲时战斗曲要循环**（一关从头到尾这一首、
	# 放完不接下一首 —— `_on_bgm_finished` 靠 `finished` 运作，循环的曲子永不到点）。
	# ★63-25：主菜单曲**也**不循环（三首随机轮换，同一套机制）。
	# 「哪个用途该循环」的唯一真源是 `bgm_should_loop()`，这里不再内联写布尔括号。
	var lock_loop := kind == Bgm.BATTLE and _locked_battle_track != ""
	var want_loop := bgm_should_loop(kind, lock_loop)
	# ⚠️⚠️ **惰性复制**：只在真需要改 loop 的时候，才复制一份私有的再改。
	#
	# ## 为什么不能再"直接改共享资源"
	# 这里原来写着「**每个 BGM 文件只属于一种用途**，所以直接改共享资源是安全的」。
	# 那句话**早就不成立**了：
	#   · `senkou` 三种用途 —— 对战战斗曲（不循环）/ 太平洋结算曲（**循环**）/
	#     关卡锁曲（**循环**）；
	#   · `earth_nt` / `snooze` 两种 —— 主菜单曲（★63-25 起，**不循环**）/
	#     仅自选战斗曲（不循环）；
	#   · `sweet_child` 两种 —— 艾尔斯岩结算 / 训练场（**都循环**，这一对碰巧同值）。
	# 只要有一份资源被两种 loop 值不同的用途用到，直接改就会**写穿**：
	# 症状是"对战打完一首就卡住、再也不换曲"，而且**一行报错都没有**（★63-20 栽过一次）。
	#
	# ## 规则
	# ```
	# if _loop_of(s) != want_loop:   # 共享资源当前值刚好就是我们要的 ⇒ 一个字都不用改
	#     s = s.duplicate()          # 否则**只改副本**，共享资源保持原样
	#     _apply_loop(s, want_loop)
	# ```
	# 于是 `sweet_child` 这类"两用途同值"的场合**一次都不复制**；而将来谁把
	# `earth_nt` 拿去当结算曲，也只会得到一个私有副本，伤不到战斗侧。
	#（与 `_stream()` 里「循环版要复制一份」同一套理由，见那边的注释。）
	#
	# ⚠️ 代价（必须知道）：**`load(path).loop` 不再是"这次会怎么播"的读数**（改的是副本）。
	# 要问那个，读 **`_bgm_players[_bgm_active].stream`** —— `_loop_of()` 就是给这用的。
	# `suite_mission_bgm` 早就按这个口径写（它那条"共享资源没被写穿"是同一规则的另一半）。
	if _loop_of(s) != want_loop:
		s = s.duplicate() as AudioStream
		_apply_loop(s, want_loop)
	_bgm_track = name

	var next := 1 - _bgm_active
	var p := _bgm_players[next]
	p.stream = s
	p.volume_db = -60.0
	p.play()
	_crossfade(_bgm_players[_bgm_active], p, fade)
	_bgm_active = next


## 一首放完 → 接着轮换下一首。**战斗曲与主菜单曲都走这里。**
##
## 判定条件必须是"现在的 BGM 还是**那一类**"，而不是"信号是谁发的"：
## 玩家中途回菜单 / 进结算时，正在淡出的那一路战斗曲也会把 `finished` 发出来
## （它是自然结束，不是被 stop 的）—— 那种情况下绝不能把菜单/结算的曲子顶掉。
##
## ⚠️ `RESULT` / `TRAINING` **故意不在名单里**：它们是**循环**的
##（见 `bgm_should_loop()`）⇒ 永远不发 `finished`。这一条同时是"循环曲不可能被
## 轮换掉"的保险 —— 万一将来有人把它们改成不循环，**这里也不许**把结算曲换成战斗曲。
##
## ⚠️ `Bgm.MENU` 是 ★63-25（主菜单三首随机循环）才加进来的：菜单曲从此**不循环**，
## 放完必须自己换下一首 —— 少覆盖这一个 kind，菜单会停在最后放完的那一首上、
## 再也不出声，而且**不报错**。
##
## ⚠️ 下面这行会经过 `play_bgm()` 开头那条「同一首还在播就不重放」的短路 ——
## 所以它传 `force = true`：**这一首是真的放完了**，轮换不该被任何"还在不在播"拦住。
##
## 为什么不靠"Godot 先 `_stop()` 再 emit `finished`、所以那时 `playing` 已经是 false"
## 这条时序：它在真机上成立，但它是**隐式**的，而且 headless 下**不成立**
##（Dummy 驱动不推进混音 ⇒ `playing` 一直是 `true` ⇒ 手动发信号时正好撞上短路，
##  ★63-25 第一次跑就红了这一条）。`force` 把轮换从那条时序里解放出来。
##
## ⚠️ `Bgm.MENU` 是 ★63-25（主菜单三首随机循环）才加进来的：菜单曲从此**不循环**，
## 放完必须自己换下一首 —— 少覆盖这一个 kind，菜单会停在最后放完的那一首上、
## 再也不出声，而且**不报错**。
func _on_bgm_finished(p: AudioStreamPlayer) -> void:
	var kind := _bgm_kind
	if kind != Bgm.BATTLE and kind != Bgm.MENU:
		return
	if p != _bgm_players[_bgm_active]:
		return
	play_bgm(kind, ROTATE_FADE, true)


func stop_bgm(fade := 0.8) -> void:
	_bgm_kind = Bgm.NONE
	_bgm_track = ""
	var cur := _bgm_players[_bgm_active]
	_crossfade(cur, null, fade)


func _crossfade(from: AudioStreamPlayer, to: AudioStreamPlayer, fade: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	if from != null and from.playing:
		_tween.tween_property(from, "volume_db", -60.0, fade)
		_tween.chain().tween_callback(from.stop)
	if to != null:
		# ★63-22：目标音量 = **压低状态**（`_menu_duck_db`），不是写死的 0.0。
		# 不这么改的话，"压低"只是一次性赋值，会被下一次任何 crossfade 冲掉。
		_tween.tween_property(to, "volume_db", _menu_duck_db, fade)


func current_bgm() -> int:
	return _bgm_kind


# ============================================================ ★63-22 试听

## 试听一首（选歌页 / 歌单页**划到哪首就放哪首**）。同一首正在试听 ⇒ **不重启**。
##
## `track == ""`（选歌页那一行「随机（洗牌袋轮换）」，它背后没有一首具体的曲）
## 或不是合法曲目 ⇒ **停掉**（没有东西可听，就该安静，而不是维持上一首在响）。
##
## ⚠️ **切换 = 直接换流**，不做"旧曲淡出"：`_preview` 只有一个播放器，
## 换 `stream` 的瞬间旧曲就没了，而新曲从 `PREVIEW_MIN_DB` 渐入 ⇒
## 听感上就是"旧的停、新的渐起"，不需要额外的淡出步骤（多一步反而会
## 出现两条 Tween 抢 `volume_db`）。
func preview_bgm(track: String) -> void:
	if track == "" or not SoundBank.is_battle_pick(track):
		stop_preview()
		return
	if track == _preview_track:
		return                      # 同一首正在试听 ⇒ 不重启（划来划去不重放）
	if _preview == null:
		return
	var path := SoundBank.bgm_path(track)
	if not ResourceLoader.exists(path):
		_preview_track = ""
		return
	# ⚠️ 这里**故意不 `duplicate()` 也不碰 loop** —— 试听不循环。
	# 详见 `_preview` 变量头上那条"不许碰 loop"的警告。
	var s: AudioStream = load(path)
	if s == null:
		_preview_track = ""
		return
	# ⚠️ 必须 kill 上一次的渐入 Tween：不然两条 Tween 会同时 tween 同一个
	# `volume_db`，先建的那条每帧把后建的那条的结果覆盖掉 ——
	# 症状是"渐入到一半音量乱跳"，而且只在连续快速划动时出现。
	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
	_preview_track = track
	_preview.stream = s
	_preview.volume_db = PREVIEW_MIN_DB
	_preview.play()
	_preview_tween = create_tween()
	_preview_tween.tween_property(_preview, "volume_db", 0.0, PREVIEW_FADE_IN)
	if _preview_timer != null:
		# ⚠️ `start()` 自带重排：连续划动时秒表从**这一首**重新算（不是累加）。
		_preview_timer.start(PREVIEW_SECONDS)


## 停掉试听。`fade <= 0` = 立即停（`play_bgm()` 的兜底走这一档）。
##
## 清 `_preview_track` 是**有意的**：到点之后**划走再划回来会重新试听**。
## 加一个"这首已经放过了"的记忆会带来新问题（"我以为它坏了"），
## 而重复听 15 s 的代价可以忽略。
func stop_preview(fade := PREVIEW_FADE_OUT) -> void:
	if _preview_timer != null:
		_preview_timer.stop()
	_preview_track = ""
	if _preview == null:
		return
	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
	if fade <= 0.0:
		_preview.stop()
		_preview.volume_db = PREVIEW_MIN_DB
		return
	_preview_tween = create_tween()
	_preview_tween.tween_property(_preview, "volume_db", PREVIEW_MIN_DB, fade)
	_preview_tween.tween_callback(_preview.stop)


## 15 秒到点（用户：「播放曲子前面十五秒」）。淡出之后停。
func _on_preview_timeout() -> void:
	stop_preview()


## 正在试听的键（`""` = 没有）。**无头可读** —— 判据读它。
##
## ⚠️ 别拿 `is_preview_playing()` 当"有没有在试听"：无头（Dummy 音频驱动）下
## `AudioStreamPlayer.playing` **恒 false**，混音根本不推进。
func preview_track() -> String:
	return _preview_track

## Read the preview clock, independently of cursor focus and saved music choices.
func preview_status() -> Dictionary:
	var elapsed := 0.0
	if not _preview_track.is_empty() and _preview_timer != null:
		elapsed = clampf(PREVIEW_SECONDS - _preview_timer.time_left,0.0,PREVIEW_SECONDS)
	return {"track":_preview_track,"elapsed":elapsed,"duration":PREVIEW_SECONDS,
		"progress":elapsed / PREVIEW_SECONDS}



## 现在试听的音量（dB）。**真机探针读它证明"渐入真的在升"** ——
## "2 s 渐入"除了逐点采样这条曲线之外没有别的直接证据。
func preview_volume_db() -> float:
	return _preview.volume_db if _preview != null else PREVIEW_MIN_DB


## 试听播放器**真的在响**吗。⚠️ 只能真机用（理由见 `preview_track()`）。
func is_preview_playing() -> bool:
	return _preview != null and _preview.playing


## 让试听停下来，并把菜单 BGM 压低到 `db`（`0.0` = 恢复）。
##
## 进选歌页/歌单页时压低菜单曲，是为了让 2 s 渐入听得出来（叠在一起就白试听了）。
## 离开时恢复。两个动作合成一个入口，是因为**它们总是同时发生**。
func set_menu_duck(db: float) -> void:
	if is_equal_approx(_menu_duck_db, db):
		return
	_menu_duck_db = db
	if _bgm_players.is_empty():
		return
	var cur := _bgm_players[_bgm_active]
	if not cur.playing:
		return
	# 立即施加（不等下一次 crossfade）：★63-25 起菜单曲**不循环**了，但一轮有三首、
	# 一首好几分钟 —— 等它换曲等不到（玩家在选歌页待十秒就该听见压低效果）。
	# kill 掉当前 Tween 是必须的 —— 它可能正在把这一路淡出/淡入，两条抢同一个属性。
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(cur, "volume_db", _menu_duck_db, MENU_DUCK_FADE)


# ============================================================ 音效

## 取一个音效流（一次性版本）。给"需要自己长期持有播放器"的场合用，
## 例如 FlightBody 的座舱巡航检测音 —— 它要按固定节拍重放同一个流。
func get_stream_for(name: String) -> AudioStream:
	return _stream(name, false)


## 界面音 / 玩家自己的声音。非定位。
func play_self(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if _throttled(name):
		return
	var s := _stream(name, false)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	# 逐条音效的增益（`SoundBank.GAIN_DB`）**在这里统一施加**，不在调用点上。
	# 调用点传的 `vol_db` 只说「这一枪在这个场合该多响」；
	# 「这条音效整体该多响」是 `SoundBank` 的事。两件事分开，才不会出现
	# 「玩家自己那枪调大了、敌机那枪没调」这种漏一半的改动。
	p.volume_db = vol_db + SoundBank.gain_db(name)
	p.pitch_scale = pitch
	# ★63-23：细分通道（`SoundBank.SFX_BUS`）。未分类的音效照旧进 `SFX`。
	# ⚠️ 与 `play_3d` 是**两个函数体**，两边都必须接 —— 只接一边的症状见 `_bus_for()`。
	p.bus = _bus_for(name)
	add_child(p)
	_release_when_done(p, s)
	p.play()


## 保证临时播放器一定会被回收。
##
## 只靠 `finished` 不够：无头模式（Dummy 音频驱动）下混音不推进，
## `finished` 可能永远不触发，跑测试时会攒下成百上千个播放器节点。
## 所以额外挂一个"流长度 + 余量"的兜底计时器。
##
## ⚠️ 兜底**必须做成播放器的子节点**，不能用 `SceneTreeTimer` + lambda：
## lambda 会把播放器当成"捕获变量"持有，播放器先被 `finished` 释放之后，
## 定时器到点再调用就是一个
## `Lambda capture at index 0 was freed. Passed "null" instead.` 错误。
## 火神炮每秒十几发，这个错误会以前所未有的速度刷屏（debug 构建下控制台写同步 I/O，
## 能把帧率拖到像卡死）。挂成子节点就没有这个问题：父节点一释放，
## 定时器连同它与被调对象的连接一起消失，什么都不会残留。
func _release_when_done(p: Node, s: AudioStream) -> void:
	p.finished.connect(p.queue_free)
	var guard := Timer.new()
	guard.name = "AutoFree"
	guard.one_shot = true
	guard.wait_time = maxf(s.get_length(), 0.5) / maxf(float(p.get("pitch_scale")), 0.05) + 0.6
	guard.timeout.connect(p.queue_free)
	p.add_child(guard)
	guard.start()


## 界面音：语义化入口，省得各处记音量。
func play_ui(name: String, vol_db := -6.0) -> void:
	play_self(name, vol_db)


## **座舱告警语音**（§4.3.2）。与 `play_self()` 的四点不同，每一点都有理由：
##
##   ① **不叠加**：正在播的那条先停。两句告警重叠会变成没人听得懂的噪音，
##      而"哪一句更要紧"是节流的职责（HUD 的 `pick_voice()`），不是混音的职责。
##   ② **不受 `_throttled()` 管**：语音有自己的节流（`FlightHUD.VOICE_THROTTLE`）。
##      两边都管会互相掐 —— 症状是本该报的时候哑了，而且查到死也不知道是谁掐的。
##   ③ **固定音量**（`VOICE_DB`）、**非 3D**（座舱语音是"耳机里的"，没有距离衰减）。
##   ④ **素材缺失自动降级**：走 `SoundBank.voice_or_fallback()` 退回合成音效。
##      **"语音没录"绝不能变成"告警没了"。**
##
## `fallback` 传空 = 用 `SoundBank.VOICE_FALLBACK` 的默认映射。
##
## 无头模式安全：素材不存在时 `_stream()` 返回 null，这里直接早退；
## 素材存在时 `_release_when_done()` 的兜底计时器负责回收（Dummy 音频驱动下
## `finished` 可能永不触发，那条注释写得很清楚）。
func play_voice(name: String, fallback := "") -> void:
	var resolved := SoundBank.voice_or_fallback(name, fallback)
	if resolved == "":
		return
	var s := _stream(resolved, false)
	if s == null:
		return
	stop_voice()
	var p := AudioStreamPlayer.new()
	p.name = "Voice"
	p.stream = s
	p.volume_db = VOICE_DB
	# 语音**不打随机音高**：合成音效靠 ±4% 抖动避免机械感，语音抖了会像变速磁带。
	# ★63-23：语音与三种告警**同走 `ALARM`** —— 它本来就是一类东西
	#（"拉起告警"是警报的语音版，不是另一条通道），所以玩家那根「警报」滑条
	# 一次性管全。`resolved` 可能是语音名、也可能是降级到的 `alarm_*`，两者都在表里。
	p.bus = _bus_for(resolved)
	add_child(p)
	_release_when_done(p, s)
	_voice_player = p
	p.play()


## 掐掉正在播的那条语音（`play_voice()` 内部先调它）。
##
## 用 `queue_free()` 而不是 `stop()`：`_release_when_done()` 挂的兜底计时器是
## **播放器的子节点**，父节点一释放它连同连接一起消失 —— 这正是那个注释里要的效果。
## 只 `stop()` 的话播放器会一直挂在那儿等 `finished`，而 headless 下它永远等不到。
func stop_voice() -> void:
	if _voice_player != null and is_instance_valid(_voice_player):
		_voice_player.queue_free()
	_voice_player = null


## 现在有没有语音在播。给测试与调试用（无头下"播了"只到这条为止）。
func is_voice_playing() -> bool:
	return _voice_player != null and is_instance_valid(_voice_player)


## 世界里的声音。定位。
func play_3d(name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, max_distance := 4500.0) -> void:
	if _throttled(name):
		return
	var s := _stream(name, false)
	if s == null:
		return
	var parent := get_tree().current_scene
	if parent == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	# 同上：定位通道与 `play_self` 是**两个函数体**，增益必须两边都加。
	# 少加一边的症状是「打敌人听得见、自己开炮没变响」—— 光看代码看不出来。
	p.volume_db = vol_db + SoundBank.gain_db(name)
	p.pitch_scale = pitch
	p.max_distance = max_distance
	p.unit_size = max_distance * 0.22
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	# ★63-23：定位通道与 `play_self` 是**两个函数体**，细分总线也必须两边都接。
	p.bus = _bus_for(name)
	parent.add_child(p)
	p.global_position = pos
	_release_when_done(p, s)
	p.play()


## 导弹爆炸：按"离听者多远"在近场录音与远场录音之间二选一。
##
## 需求给的是两版**不同的录音**（`boom_s` 近处 / `boom_m` 远处），
## 所以这里必须在播放前选，而不是放同一版再靠 3D 衰减调音量 ——
## 远场那版是闷响 + 长尾，近场那版是脆响，衰减器做不出这个差别。
##
## 远场那版额外给一点增益并放宽 max_distance：
## 敌机在十几公里外被打爆时应该还剩一点点动静，否则夜战会显得太空。
func play_explosion(pos: Vector3, near_name := "boom_s", far_name := "boom_m",
		near_dist := SoundBank.NEAR_EXPLOSION_DISTANCE) -> void:
	var d := INF
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null:
			d = cam.global_position.distance_to(pos)
	if d <= near_dist:
		play_3d(near_name, pos, 0.0, randf_range(0.96, 1.05), 6000.0)
	else:
		play_3d(far_name, pos, 2.0, randf_range(0.92, 1.02), 22000.0)


## 判断一次爆炸会被算作"近"还是"远"（供测试用，和 play_explosion 同一套规则）。
func is_near_explosion(pos: Vector3, near_dist := SoundBank.NEAR_EXPLOSION_DISTANCE) -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var cam := vp.get_camera_3d()
	if cam == null:
		return false
	return cam.global_position.distance_to(pos) <= near_dist


## 节流：同名音效在 MIN_INTERVAL_MS 内只放一次。
func _throttled(name: String) -> bool:
	var gap := SoundBank.min_interval(name)
	if gap <= 0:
		return false
	var now := Time.get_ticks_msec()
	var last := int(_last_play.get(name, -999999))
	if now - last < gap:
		return true
	_last_play[name] = now
	return false


func reset_throttle() -> void:
	_last_play.clear()


## Cinematic pause keeps the soundtrack aligned with the stopped timeline.
func set_bgm_paused(paused: bool) -> void:
	for player in _bgm_players:
		player.stream_paused = paused

## One-shot resonance cue in the existing BGM mixer, preserving master/music volume.
func play_resonance_bgm() -> void:
	var path := SoundBank.bgm_path("beyond_the_time")
	if not ResourceLoader.exists(path) or _bgm_players.size()<2: return
	var stream: AudioStream = load(path)
	if stream == null: return
	stream = stream.duplicate() as AudioStream
	_apply_loop(stream,false)
	stop_preview(0.0)
	set_bgm_paused(false)
	_bgm_kind = Bgm.BATTLE
	_bgm_track = "beyond_the_time"
	var next := 1-_bgm_active
	var player := _bgm_players[next]
	player.stream = stream
	player.volume_db = -60.0
	player.play(88.0)
	_crossfade(_bgm_players[_bgm_active],player,0.35)
	_bgm_active = next
