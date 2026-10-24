class_name SuiteSettings
extends RefCounted
## 画面尺寸与音量设置的测试。
##
## 这两项最容易出的问题是**"改了没反应"**：滑块动了、值也存了，但声音还是原来那么大、
## 窗口还是原来那么大 —— 因为值没有真正写到 `AudioServer` / `DisplayServer` 上。
## 所以这里断言的是**引擎侧的真实状态**（总线音量、静音标志、标签），不是本地变量。


static func run(t: T, host: Node) -> void:
	# 整个套件前后各做一次备份/还原。
	# ⚠️ 之前只在单个子测试里还原，结果 `_volume` 把 sfx 改到 1.0 就没还回去，
	# `_persistence` 又照着这个错值"还原"并写进了 user://settings.cfg ——
	# 测试跑一次，玩家自己的音量设置就被改掉了。
	var backup := {
		"res": Settings.resolution_index,
		"fs": Settings.fullscreen,
		"bgm": Settings.bgm_volume,
		"sfx": Settings.sfx_volume,
		"bgm_pick": Settings.battle_bgm_pick,
	}

	t.suite("Settings / 音频总线")
	_buses(t)
	t.suite("Settings / 音量")
	_volume(t)
	t.suite("Settings / 画面尺寸")
	_display(t)
	t.suite("Settings / 存档往返")
	await _persistence(t, host)
	t.suite("Settings / 战斗BGM 自选")
	await _battle_bgm(t, host)

	Settings.set_resolution(int(backup["res"]))
	Settings.set_fullscreen(bool(backup["fs"]))
	Settings.set_volume(Settings.BUS_BGM, float(backup["bgm"]))
	Settings.set_volume(Settings.BUS_SFX, float(backup["sfx"]))
	Settings.battle_bgm_pick = str(backup["bgm_pick"])
	Settings.save_config()
	t.near(Settings.sfx_volume, float(backup["sfx"]), 0.0001, "套件跑完后音效音量已还原")
	t.eq(Settings.resolution_index, int(backup["res"]), "套件跑完后画面尺寸已还原")
	await host.get_tree().process_frame


static func _buses(t: T) -> void:
	var bi := Settings.bus_index(Settings.BUS_BGM)
	var si := Settings.bus_index(Settings.BUS_SFX)
	t.gt(bi, 0, "BGM 总线存在（且不是 Master）")
	t.gt(si, 0, "SFX 总线存在（且不是 Master）")
	t.ok(bi != si, "BGM 与 SFX 是两条不同的总线")

	# BGM 播放器必须真的送到 BGM 总线；送错了的话"音乐音量"会去调音效
	var bgm_ok := false
	var sfx_seen := false
	for c: Node in Audio.get_children():
		var p := c as AudioStreamPlayer
		if p == null:
			continue
		if p.bus == Settings.BUS_BGM:
			bgm_ok = true
		if p.bus == Settings.BUS_SFX:
			sfx_seen = true
	t.ok(bgm_ok, "AudioDirector 的 BGM 播放器挂在 BGM 总线上")

	# 一次性音效走 SFX 总线
	Audio.reset_throttle()
	Audio.play_self("ui_confirm", -20.0)
	for c: Node in Audio.get_children():
		var p := c as AudioStreamPlayer
		if p != null and p.bus == Settings.BUS_SFX:
			sfx_seen = true
	t.ok(sfx_seen, "play_self 出来的一次性音效挂在 SFX 总线上")


static func _volume(t: T) -> void:
	var bi := Settings.bus_index(Settings.BUS_BGM)
	var old := Settings.bgm_volume

	t.near(Settings.VOLUME_STEP, 0.05, 0.0001, "一次按键调 5%")

	Settings.set_volume(Settings.BUS_BGM, 0.0)
	t.ok(AudioServer.is_bus_mute(bi), "音量 0 = 真静音（不是靠 -80 dB 硬凑）")

	Settings.set_volume(Settings.BUS_BGM, 1.0)
	t.not_ok(AudioServer.is_bus_mute(bi), "音量 100% 解除静音")
	t.near(AudioServer.get_bus_volume_db(bi), 0.0, 0.05, "音量 100% 对应 0 dB")

	Settings.set_volume(Settings.BUS_BGM, 0.5)
	t.near(AudioServer.get_bus_volume_db(bi), linear_to_db(0.5), 0.05,
		"音量 50% 写到总线上的是正确的 dB")

	Settings.set_volume(Settings.BUS_SFX, 5.0)
	t.near(Settings.sfx_volume, 1.0, 0.0001, "音量上限夹到 100%")
	Settings.set_volume(Settings.BUS_SFX, -3.0)
	t.near(Settings.sfx_volume, 0.0, 0.0001, "音量下限夹到 0%")

	# 两条总线互不影响
	Settings.set_volume(Settings.BUS_BGM, 0.0)
	Settings.set_volume(Settings.BUS_SFX, 1.0)
	t.ok(AudioServer.is_bus_mute(Settings.bus_index(Settings.BUS_BGM)),
		"把 BGM 调到 0 不会把音效也静音")
	t.not_ok(AudioServer.is_bus_mute(Settings.bus_index(Settings.BUS_SFX)),
		"音效总线仍然是打开的")

	Settings.set_volume(Settings.BUS_BGM, old)


static func _display(t: T) -> void:
	t.gt(Settings.RESOLUTIONS.size(), 2, "提供了多个画面尺寸预设")
	for r: Dictionary in Settings.RESOLUTIONS:
		var sz: Vector2i = r["size"]
		t.near(float(sz.x) / float(sz.y), 16.0 / 9.0, 0.01,
			"%s 是 16:9（和工程基准 1600×900 一致）" % r["label"])

	var old_res := Settings.resolution_index
	var old_fs := Settings.fullscreen

	Settings.set_resolution(0)
	t.not_ok(Settings.fullscreen, "选了具体尺寸就意味着退出全屏")
	t.eq(Settings.resolution_label(), str(Settings.RESOLUTIONS[0]["label"]),
		"尺寸标签和预设对得上")

	Settings.cycle_resolution(-1)
	t.eq(Settings.resolution_index, Settings.RESOLUTIONS.size() - 1,
		"向左越界会绕回最后一个（不是卡在 0）")
	Settings.cycle_resolution(1)
	t.eq(Settings.resolution_index, 0, "向右越界会绕回第一个")

	Settings.set_fullscreen(true)
	t.eq(Settings.resolution_label(), "全屏", "全屏时标签显示「全屏」")

	Settings.set_resolution(old_res)
	Settings.set_fullscreen(old_fs)


## 存档往返。
## 注意备份/还原在 `run()` 里统一做 —— 这里改的值不是这套测试自己的，是玩家的。
static func _persistence(t: T, host: Node) -> void:
	var target_res := posmod(Settings.resolution_index + 1, Settings.RESOLUTIONS.size())

	Settings.set_resolution(target_res)
	Settings.set_volume(Settings.BUS_BGM, 0.35)
	Settings.save_config()

	# 先把内存里的值改乱，再从文件读回来
	Settings.resolution_index = 0
	Settings.bgm_volume = 1.0
	Settings.load_config()
	t.eq(Settings.resolution_index, target_res, "画面尺寸能存下来也能读回来")
	t.near(Settings.bgm_volume, 0.35, 0.001, "BGM 音量能存下来也能读回来")
	await host.get_tree().process_frame


## 战斗 BGM 自选（批 23）：设置页选开场曲 → 出击注入 → 本场第一首，
## 放完剩余的歌洗袋随机轮流。四条线都要钉：
##   ① 循环切换的顺序与绕回（菜单行手感）；
##   ② 存档往返 + 曲池校验（存档里的旧键名不许把选择变成"放不出来的歌"）；
##   ③ AudioDirector 的**一次消费**语义（开场曲只管本场第一首、之后回洗牌袋；
##      选閃光 ⇒ 这一局结算必须走特殊结算曲 —— 与"用过閃光当战斗曲"同一规则）；
##   ④ 菜单行与 main 出击注入的**接线**（源码扫描，注释里写了名字不算数）。
static func _battle_bgm(t: T, host: Node) -> void:
	# ---- ① 循环切换 ----
	# ⚠️ 序列取 `battle_pick_tracks()`（轮换池 **+ 仅自选曲**），不再写死 `BATTLE_TRACKS`：
	# 「仅自选曲」也得能被拨到 —— 那是它**唯一的入口**。
	# 「拨得到」与「会不会被随机放到」是两件事（后者见 suite_audio 的洗牌袋断言）。
	var picks: Array = SoundBank.battle_pick_tracks()
	Settings.battle_bgm_pick = ""
	Settings.cycle_battle_bgm(1)
	t.eq(Settings.battle_bgm_pick, picks[0],
		"随机向右一步 = 自选列表第一首（顺序稳定，玩家能背下来）")
	for i in range(1, picks.size()):
		Settings.cycle_battle_bgm(1)
	t.eq(Settings.battle_bgm_pick, picks[picks.size() - 1],
		"连按到底 = 自选列表最后一首（中间没有暗项）")
	Settings.cycle_battle_bgm(1)
	t.eq(Settings.battle_bgm_pick, "", "最后一首再向右绕回「随机」")
	Settings.cycle_battle_bgm(-1)
	t.eq(Settings.battle_bgm_pick, picks[picks.size() - 1],
		"从随机向左 = 直接跳到自选列表最后一首（双向循环）")
	Settings.battle_bgm_pick = ""
	t.eq(Settings.battle_bgm_label(), "随机", "未选 = 显示「随机」")
	t.eq(Settings.battle_bgm_label() == "", false, "标签不为空（菜单行不会画出一行空值）")
	t.eq(Settings.battle_bgm_pick == "" or SoundBank.is_battle_pick(Settings.battle_bgm_pick),
		true, "选择值要么是随机、要么在自选列表里（不变量）")

	# 仅自选曲（用户 2026-09-27）：**必须拨得到**，否则「加进自选」就是句空话
	var sweet_i := picks.find("sweet_child")
	t.gt(sweet_i, 0, "仅自选曲在自选列表里（下标 %d）" % sweet_i)
	# ⚠️ `set_battle_bgm_index` 的序号里 **0 被「随机」占着**，所以自选列表下标 i
	# 对应序号 i+1 —— 差一格的症状是"点 Sweet Child 却选中了上一首"。
	Settings.set_battle_bgm_index(sweet_i + 1)
	t.eq(Settings.battle_bgm_pick, "sweet_child", "按序号选中 Sweet Child O' Mine")
	t.eq(Settings.battle_bgm_index(), sweet_i + 1,
		"序号读回一致（进选歌页光标落在它上面）")
	t.eq(Settings.battle_bgm_label(), "Sweet Child O' Mine",
		"设置页那一行显示曲名（不是键名）")

	# ---- ② 存档往返 + 曲池校验 ----
	Settings.battle_bgm_pick = "tracer"
	Settings.save_config()
	Settings.battle_bgm_pick = ""
	Settings.load_config()
	t.eq(Settings.battle_bgm_pick, "tracer", "战斗BGM 选择能存下来也能读回来")
	Settings.battle_bgm_pick = "sweet_child"
	Settings.save_config()
	Settings.battle_bgm_pick = ""
	Settings.load_config()
	t.eq(Settings.battle_bgm_pick, "sweet_child",
		"仅自选曲也存得住读得回（校验只认曲池的话会静默退回「随机」）")
	Settings.battle_bgm_pick = "no_such_track"
	Settings.save_config()
	Settings.battle_bgm_pick = "tracer"
	Settings.load_config()
	t.eq(Settings.battle_bgm_pick, "",
		"存档里的旧键名 / 野键名读回来退回「随机」（不校验就会选中放不出来的歌）")
	await host.get_tree().process_frame

	# ---- ③ AudioDirector 一次消费 ----
	# ⚠️ Audio 是真 autoload：先备份轮换状态，测完整套原样还回去，
	# 不然 suite_audio 的轮换断言会莫名撞上被搅乱的洗牌袋。
	# ⚠️ 必须 `.duplicate()`：`Array(x)` 是引用 ⇒ `_battle_bag.clear()` 会把"备份"一起清掉，
	#    "原样还回去"这句注释就成了空话（详见 suite_audio.gd 同款注释）。
	var bag_backup: Array = Audio._battle_bag.duplicate()
	var last_backup: String = Audio._last_battle_track
	var senkou_backup: bool = Audio._senkou_used
	var pool_backup: Array = Audio.battle_pool
	var req_backup: String = Audio.requested_battle_open

	Audio.battle_pool = SoundBank.BATTLE_TRACKS
	Audio.request_battle_open("senkou")
	var first: String = Audio.bgm_name(Audio.Bgm.BATTLE)
	t.eq(first, "senkou", "出击前自选的曲 = 本场**第一首**（精确命中，不是概率）")
	t.eq(Audio.requested_battle_open, "",
		"开场曲请求**只消费一次**（不会每首轮换都回到自选曲）")
	t.ok(Audio._senkou_used, "自选閃光当开场曲 ⇒ 记「这一局用过閃光」")
	t.eq(Audio.result_track_for(0, Audio._senkou_used), "special_result",
		"……于是这一局的结算曲走特殊结算曲（与随机抽到閃光同一规则）")
	var second: String = Audio.bgm_name(Audio.Bgm.BATTLE)
	t.ok(SoundBank.BATTLE_TRACKS.has(second), "第二首回到洗牌袋（仍在曲池里）")
	t.ok(second != "senkou", "第二首**不会**立刻重复自选曲（洗牌袋跨界不连放同一首）")

	Audio.request_battle_open("no_such_track")
	var fallback: String = Audio.bgm_name(Audio.Bgm.BATTLE)
	t.ok(SoundBank.BATTLE_TRACKS.has(fallback),
		"自选曲不在曲池里（剧情池等）⇒ 自动退回随机，不会放出一首不存在的歌")
	t.eq(Audio.requested_battle_open, "", "退回路径同样要消费掉请求（不能留着污染下一场）")

	Audio._battle_bag = bag_backup
	Audio._last_battle_track = last_backup
	Audio.requested_battle_open = req_backup
	# 曲池与「用过閃光」标记一起按备份还原（set_story_mode 本身会重置标记，
	# 所以标记的还原放它后面）。
	if pool_backup == SoundBank.STORY_BATTLE_TRACKS:
		Audio.set_story_mode(true)
	else:
		Audio.set_story_mode(false)
	Audio._senkou_used = senkou_backup
	await host.get_tree().process_frame

	# ---- ④ 接线（源码扫描，复用 SuiteUiStyle 的剥注释工具）----
	var menu_src := SuiteUiStyle._code("scripts/ui/main_menu.gd")
	t.ok(menu_src.contains("\"battle_bgm\""),
		"设置页行表里有「战斗BGM」行")
	t.ok(menu_src.contains("Settings.cycle_battle_bgm(dir)"),
		"设置页左右调值真的接到了 cycle_battle_bgm")
	t.ok(menu_src.contains("SoundBank.battle_pick_tracks()"),
		"选歌页的键序列取自 SoundBank 的一处定义（四个消费方不许各自复制名单）")
	# ★63-22（用户 2026-10-08：「把（仅自选，不参与随机）去掉」）：
	# 这一条原来是 `ok(menu_src.contains("SoundBank.battle_track_note("))`。
	# 现在**反向**钉 —— 后缀与函数都不许再出现。
	#
	# ⚠️ 之所以写成 `not_ok`（而不是"干脆删掉这一条"）：留一条"看得见的删除判决"
	# 比"什么都没有"强 —— 将来有人（比如为了别的原因）把后缀加回去，这两条会红。
	# ⚠️ 两条都要**能红**：负对照 = 把 `battle_track_note` 与那个后缀字面量加回
	# `main_menu.gd` / `sound_bank.gd` ⇒ 这两条读 FAIL（实测见交付说明的负对照节）。
	t.not_ok(menu_src.contains("battle_track_note"),
		"选歌页不再印「（仅自选 · 不参与随机）」后缀（★63-22 用户要求去掉）")
	t.not_ok(menu_src.contains("（仅自选"),
		"菜单里连那个后缀的字面量都没有了（扫描字符串而不只扫函数名 —— 防止有人手抄一份）")
	var bank_src := SuiteUiStyle._code("scripts/audio/sound_bank.gd")
	t.not_ok(bank_src.contains("func battle_track_note"),
		"SoundBank 里那个后缀函数**已删除**（留个永远返回空串的空壳会让上面那条判据变成恒真）")
	t.not_ok(bank_src.contains("（仅自选 · 不参与随机）"),
		"SoundBank 里连那句后缀文案都没有了")
	var main_src := SuiteUiStyle._code("scripts/main.gd")
	# ★ 2026-10-01（轮 59）：自选曲现在**先落到 `want`**，因为**关卡自带的曲子要盖过它**
	#（老板：「TRACER 作为 M01 的 bgm」）。注入点跟着改名 —— 但**这条不变**：
	# 设置页选的那首必须真的被读出来、送进 AudioDirector，否则整个「战斗BGM」行是空摆设。
	t.ok(main_src.contains("var want: String = Settings.battle_bgm_pick"),
		"出击时读设置里的自选曲（不接线的选择是空摆设）")
	t.ok(main_src.contains("Audio.request_battle_open(want)"),
		"……并且真的注入了（这一行是「这一场拿哪首开头」的唯一入口）")

	# ---- ⑤ 选歌页（批 24）----
	# 功能级：按序号直接设定 / 读回序号 —— 与选歌页 UI 用的是同一对 API。
	var pick_backup: String = Settings.battle_bgm_pick
	Settings.set_battle_bgm_index(0)
	t.eq(Settings.battle_bgm_pick, "", "选歌页第 0 项 = 随机（set_battle_bgm_index(0)）")
	t.eq(Settings.battle_bgm_index(), 0, "随机读回序号 0")
	Settings.set_battle_bgm_index(2)
	t.eq(Settings.battle_bgm_pick, str(picks[1]),
		"序号 2 = 自选列表第 2 首（下标 1）—— 与 bgm_pick_keys 同序")
	t.eq(Settings.battle_bgm_index(), 2, "序号读回 = 2（进选歌页时光标落在当前曲上）")
	# 越界钳位：列表循环页不该有"选中一个不存在的项"的可能
	Settings.set_battle_bgm_index(999)
	t.eq(Settings.battle_bgm_pick, str(picks[picks.size() - 1]),
		"越界序号钳到最后一项（不产生野键）")
	Settings.set_battle_bgm_index(-3)
	t.eq(Settings.battle_bgm_pick, "", "负序号钳到第 0 项（随机）")
	Settings.battle_bgm_pick = pick_backup
	# 接线：设置行 Enter 进选歌页 / 选歌页 Escape 回设置页（保险丝两层都在）
	t.ok(menu_src.contains("stage = Stage.BGM"),
		"设置页「战斗BGM」行 Enter 真的打开选歌页")
	t.ok(menu_src.contains("func _read_bgm_input"),
		"选歌页有自己的输入处理（选择 / 选定 / 返回）")
	t.ok(menu_src.contains("func _draw_bgm_stage"),
		"选歌页有自己的绘制（滚动列表 + 当前曲标记）")
	t.ok(menu_src.contains("Settings.set_battle_bgm_index(bgm_row)"),
		"选歌页 Enter 真的写回设置（选了不生效的菜单是装饰品）")
	# ⚠️ 批 29：两页的列表版式都改由 `list_panel_metrics()` / `settings_metrics()` 给，
	# 所以判据也跟着换成这一对（"两处都要能滑动"这件事本身没变）。
	t.ok(menu_src.contains("scroll_window(") and menu_src.contains("list_panel_metrics(")
		and menu_src.contains("settings_metrics("),
		"设置页与选歌页都走同一套滚动窗口（批 24 用户指定：两处都要能滑动）")
