extends Node
## ★63-22 真机探针 B：**自定义战斗歌单**（6 首 · 整体随机循环）。
##
## ## 读七件事
## ① 三个状态的图：**空态 / 3 首态 / 满 6 首被拒态**（+ 移出一首）
## ② 版式量尺：歌单页的**页头不压第一行**、**最后一行不出面板**、面板没上浮进标题带，
##    以及"歌单页可见行比选歌页少一行"这笔账（页头是付了代价的）
## ③ 行为：歌单 = 3 首 ⇒ **真抽 9 次（3 轮）**，每首**恰好 3 次**、没有第 4 首
## ④ 行为：歌单 = 1 首 ⇒ 只会是它（不崩、不死循环）
## ⑤ 行为：**锁曲仍然生效** —— 锁曲必须"∈ 默认池 且 ∉ 歌单"，否则这条断言没有牙（§4.4）
## ⑥ 行为：空歌单 ⇒ 有效池 == `battle_pool`
## ⑦ 存档：跑前把 `settings.cfg` **原样存下来**，跑完**按字节写回**（md5 必须一致）
##
## ## 跑法（真机出图；不加 `--headless`）
##   Godot_v4.7.1-stable_win64_console.exe --path <工程> \
##       res://tools/_r63_22_bgm_playlist.tscn -- <输出目录>
##
## ⚠️ 本探针**会改** `Settings.battle_playlist`（那是写盘的玩家存档）。
## 所以收尾不是"还回旧值再存一次"，而是**把跑前的文件字节原样写回** ——
## 因为本批新增了 `battle_playlist` 这个键，旧档里**本来没有它**，
## "还回旧值 + `save_config()`" 会在档里**多写一个键**，md5 就不等了。

const SHOT_W := 1600
const SHOT_H := 900

const ROTATE_N := 9             # 歌单 3 首 ⇒ 抽 9 次 = 整 3 轮
const SOLO_N := 4               # 歌单 1 首 ⇒ 抽 4 次，看它会不会崩

var main: Node
var out_dir := "user://shots_r63_22_playlist"
var _fails := 0
var _cfg := ""
var _cfg_bytes := PackedByteArray()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	_cfg = ProjectSettings.globalize_path("user://settings.cfg")
	_cfg_bytes = FileAccess.get_file_as_bytes(_cfg) if FileAccess.file_exists(_cfg) \
		else PackedByteArray()
	var md5_before := _md5(_cfg)
	print("========== ★63-22 战斗歌单 · 真机探针 ==========")
	print("SETTINGS cfg=%s  md5前=%s  bytes=%d" % [_cfg, md5_before, _cfg_bytes.size()])

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	var menu: Control = main.get("menu")
	if menu == null or not is_instance_valid(menu):
		push_error("SHOTS_FAILED(no menu)")
		get_tree().quit(1)
		return

	var cap: int = Settings.PLAYLIST_MAX
	var keys: Array = MainMenu.bgm_pick_keys()
	print("CONST 容量=%d  候选=%d 首（下标 0 = 随机）  Settings 读数=%s" % [
		cap, keys.size(), Settings.playlist_label()])
	_check(cap == 6, "容量 = 6（用户原话「选择 6 首歌曲」）")
	_check(keys.size() >= 8, "候选列表 %d 首（够挑 6 首 + 还有被拒的一首）" % keys.size())

	# ℹ️ 这里的读数 = **从存档 `settings.cfg` 里读回来的**（不是本次探针设的）。
	# 玩家档里本来就有歌单的话，这行会印出来 —— 正好是「`load_config()` → 内存」
	# 这条路真的通的**旁证**（实测跑时档里是 `["men_of_destiny"]` ⇒ 读回 1 首）。
	# ⚠️ 故意**不做断言**：玩家随时可能把歌单清空，断言会变成一条脆红。
	print("BOOT 启动时从存档读回：%s（%d 首）" % [
		Settings.playlist_label(), Settings.battle_playlist.size()])

	Settings.clear_playlist()

	# ---- ① 空态 ----
	menu.set("stage", MainMenu.Stage.BGM)
	menu.set("bgm_sub", MainMenu.BGM_SUB_LIST)
	menu.set("playlist_row", 0)
	await _frames(12)
	var head_empty: String = menu.call("_bgm_playlist_head_text", 600.0)
	print("EMPTY 空态  Settings=%s  页头=「%s」" % [Settings.playlist_label(), head_empty])
	_check(Settings.battle_playlist.is_empty(), "空歌单 ⇒ `battle_playlist` 为空")
	_check(Settings.playlist_label().contains("未设置"), "设置页读数写明「未设置」而不是只印 0/6")
	_check(head_empty.contains("空"), "歌单页页头写明「（空 · 用默认曲池）」")
	await _shot("01_list_empty")

	# ---- ② 版式量尺（空态量一次就够，行数只跟 keys.size() 有关）----
	_layout(menu, keys)

	# ---- ③ 加 3 首 ----
	var add3 := [1, 2, 3]
	for r: int in add3:
		menu.call("_playlist_toggle_row", r)
	await _frames(12)
	var want3: Array = [str(keys[1]), str(keys[2]), str(keys[3])]
	print("THREE 加 3 首 ⇒ %s  读数=%s  页头=「%s」" % [
		str(Settings.battle_playlist), Settings.playlist_label(), menu.call("_bgm_playlist_head_text", 600.0)])
	_check(Settings.battle_playlist.size() == 3, "加 3 首之后确实是 3 首")
	_check(_same(Settings.battle_playlist, want3), "顺序 = **加入顺序**（页头按它显示）")
	_check(Settings.playlist_slot(str(keys[2])) == 2, "第 2 首的序号 = 2（`playlist_slot()`）")
	_check(Settings.in_playlist(str(keys[1])), "`in_playlist()` 与 `playlist_slot()` 同源")
	_check(not Settings.in_playlist(str(keys[4])), "没加过的那首不在歌单里")
	await _shot("02_list_three")

	# ---- ④ 加满 6 首 ----
	for r: int in [4, 5, 6]:
		menu.call("_playlist_toggle_row", r)
	await _frames(12)
	print("FULL 加满 ⇒ %s  读数=%s" % [str(Settings.battle_playlist), Settings.playlist_label()])
	print("FULL 页头=「%s」" % menu.call("_bgm_playlist_head_text", 600.0))
	_check(Settings.battle_playlist.size() == cap, "加满 = %d 首" % cap)
	_check(Settings.playlist_label() == "6/6 首", "设置页读数 = 6/6 首")
	await _shot("03_list_full")

	# ---- ⑤ 第 7 首**被拒**（且不许听着像成功）----
	var r7: int = Settings.toggle_playlist_track(str(keys[7]))
	menu.call("_playlist_toggle_row", 7)
	await _frames(12)
	var msg: String = str(menu.get("bgm_msg"))
	print("REJECT 第 7 首 ⇒ 返回码=%d（%d=REJECTED_FULL）  仍在单里=%d 首  提示=「%s」" % [
		r7, Settings.PLAYLIST_REJECTED_FULL, Settings.battle_playlist.size(), msg])
	_check(r7 == Settings.PLAYLIST_REJECTED_FULL, "满 6 首后再加入 ⇒ 返回 `REJECTED_FULL`")
	_check(Settings.battle_playlist.size() == cap, "被拒之后歌单**没有**变成 7 首")
	_check(not msg.is_empty() and msg.contains("已满"), "页面给出了「歌单已满」的提示（`bgm_msg`）")
	_check(not Settings.in_playlist(str(keys[7])), "被拒的那首**没进**歌单")
	await _shot("04_list_rejected")

	# ---- ⑥ 移出一首 ⇒ 满员态解除 ----
	menu.call("_playlist_toggle_row", 1)
	await _frames(12)
	print("REMOVE 移出第 1 首 ⇒ %s  读数=%s" % [str(Settings.battle_playlist), Settings.playlist_label()])
	_check(Settings.battle_playlist.size() == cap - 1, "移出之后 = %d 首" % (cap - 1))
	_check(Settings.playlist_slot(str(keys[1])) == 0, "移出的那首序号变回 0（不在单里）")
	_check(str(menu.get("bgm_msg")).is_empty(), "成功移出之后提示行清空")
	await _shot("05_list_removed_one")

	# ---- ⑦ 行为：歌单 = 3 首 ⇒ 真抽 9 次（3 轮）----
	Settings.set_battle_playlist(want3)
	menu.set("playlist_row", 0)
	await _frames(10)
	var seen: Array = await _rotate(ROTATE_N)
	var tally := {}
	for s: String in seen:
		tally[s] = int(tally.get(s, 0)) + 1
	print("ROTATE 歌单=%s  抽 %d 次 ⇒ %s" % [str(want3), ROTATE_N, str(seen)])
	print("ROTATE 计数=%s   （期望每首恰好 %d 次、没有第 4 首）" % [str(tally), ROTATE_N / 3])
	var ok_each := true
	for k: String in want3:
		if int(tally.get(k, 0)) != ROTATE_N / 3:
			ok_each = false
	_check(seen.size() == ROTATE_N, "真的抽了 %d 次" % ROTATE_N)
	_check(ok_each, "每首**恰好轮到 %d 次**（整体随机循环 = 一轮里每首各一次）" % (ROTATE_N / 3))
	_check(tally.size() == 3, "只出现歌单里的这 3 首，**没有第 4 首**（池子没被写宽）")
	await _shot("06_playing_playlist")

	# ---- ⑧ 行为：歌单 = 1 首 ⇒ 只会是它 ----
	Settings.set_battle_playlist([str(keys[1])])
	await _frames(10)
	var solo: Array = await _rotate(SOLO_N)
	var solo_ok := true
	for s: String in solo:
		if s != str(keys[1]):
			solo_ok = false
	print("SOLO 歌单=1 首 抽 %d 次 ⇒ %s" % [SOLO_N, str(solo)])
	_check(solo_ok, "歌单只有 1 首 ⇒ 抽 %d 次都是它（不崩、不死循环）" % SOLO_N)

	# ---- ⑨ 行为：**锁曲仍然生效**（它在默认池里，但**不在**歌单里）----
	#
	# ⚠️ 两条前提**缺一不可**，否则这条断言没有牙：
	#   ① 锁曲 ∈ `battle_pool` —— 它得是个"合法锁曲"，不然会被当脏值剔掉；
	#   ② 锁曲 ∉ 歌单（有效池）—— 若 `bgm_name()` 的锁曲校验**读错了池子**
	#      （读 `effective_battle_pool()` 而不是 `battle_pool`），这条立刻**红**。
	#
	# ⭐ 第一次真机跑在这里出了一条真红：我拿 `tracer` 当锁曲，而它**正好在 `want3` 里**
	# ⇒ "锁曲盖过歌单"变成恒真的废话（歌单里本来就有它，读哪个池子都会返回它）。
	# 现在锁曲**从候选里现挑**（首个"∈默认池且∉歌单"的曲子），前提自动成立。
	Settings.set_battle_playlist(want3)
	await _frames(6)
	var lock_track := ""
	for k: String in keys:
		if k != "" and Audio.battle_pool.has(k) and not want3.has(k):
			lock_track = k
			break
	print("LOCK 挑锁曲=%s  在默认池=%s  在歌单=%s  默认池=%s" % [
		_q(lock_track), str(Audio.battle_pool.has(lock_track)), str(want3.has(lock_track)),
		str(Audio.battle_pool)])
	_check(lock_track != "", "找得到一首「在默认池、但不在这个歌单里」的曲子")
	_check(Audio.battle_pool.has(lock_track), "（前提 ①）锁曲 %s 在默认池 `battle_pool` 里" % _q(lock_track))
	_check(not want3.has(lock_track), "（前提 ②）它**不在**歌单 %s 里" % str(want3))
	Audio.set_story_mode(false)
	Audio.lock_battle_track(lock_track)
	Audio.request_battle_open("")
	var locked := Audio.bgm_name(Audio.Bgm.BATTLE)
	print("LOCK 歌单=%s + 锁曲 %s ⇒ bgm_name=%s" % [str(want3), _q(lock_track), _q(locked)])
	_check(locked == lock_track, "⭐ 关卡锁曲**盖过歌单**（锁曲校验读默认池，不是有效池）")
	Audio.lock_battle_track("")

	# ---- ⑩ 空歌单 ⇒ 有效池 == battle_pool ----
	Settings.clear_playlist()
	await _frames(6)
	var eff: Array = Audio.effective_battle_pool()
	print("POOL 空歌单 ⇒ 有效池 %d 首 == battle_pool %d 首 → %s" % [
		eff.size(), Audio.battle_pool.size(), str(eff == Audio.battle_pool)])
	_check(eff == Audio.battle_pool, "空歌单 ⇒ `effective_battle_pool()` 就是 `battle_pool`")
	_check(Settings.battle_playlist.is_empty(), "（确认歌单这里确实是空的）")

	# ---- 收尾：字节级还原存档 ----
	Audio.lock_battle_track("")
	Audio.set_story_mode(false)
	Audio.stop_bgm(0.0)
	await _frames(6)
	if _cfg_bytes.is_empty():
		Settings.battle_playlist.clear()
		Settings.save_config()
		print("RESTORED 跑前没有存档文件 ⇒ 只把内存里的歌单清空（不新建档）")
	else:
		var f := FileAccess.open(_cfg, FileAccess.WRITE)
		if f == null:
			print("RESTORE_FAILED 写不回 %s" % _cfg)
			_fails += 1
		else:
			f.store_buffer(_cfg_bytes)
			f.close()
	await _frames(8)
	print("RESTORED md5后=%s" % _md5(_cfg))
	_check(_md5(_cfg) == md5_before, "存档**按字节**原样还回（md5 与跑前一致）")
	print("========== 探针结束：不符 %d 条 ==========" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## 真抽 `n` 次：走 `play_bgm(BATTLE)` + `finished` 驱动（真机等一整首歌太久）。
func _rotate(n: int) -> Array:
	Audio.set_story_mode(false)
	Audio.lock_battle_track("")
	Audio.request_battle_open("")
	Audio.play_bgm(Audio.Bgm.BATTLE, 0.0)
	await _frames(8)
	var players: Array = Audio.get("_bgm_players")
	var out: Array = []
	for i in n:
		var p: AudioStreamPlayer = players[Audio.get("_bgm_active")]
		if p != null:
			p.finished.emit()
		await _frames(5)
		out.append(Audio.current_bgm_track())
	return out


## 歌单页的版式量尺（**真机才能量**：要一个真的菜单实例）。
##
## 两条**都要**（设计文档 §4.7 的坑 16）：
##   ① `reserve_top` 少了 ⇒ 行块按 17 行排 ⇒ 最后一行掉出面板；
##   ② 面板矩形没垫 ⇒ 页头压在第一行上。
func _layout(menu: Control, keys: Array) -> void:
	var m: Dictionary = MainMenu.bgm_list_metrics(menu.size)
	var mp: Dictionary = MainMenu.list_panel_metrics(
		menu.size, keys.size(), MainMenu.SETTING_ROW_H, MainMenu.SETTING_ROW_MAX)
	var r: Rect2 = MainMenu.bgm_list_panel_rect(menu.size, m)
	var hd: Rect2 = MainMenu.bgm_head_rect(menu.size, m)
	var win: Vector2i = MainMenu.scroll_window(keys.size(), 0, int(m["shown"]))
	var row0: Rect2 = MainMenu.list_row_rect(menu.size, win.x, win.x, m)
	var rowN: Rect2 = MainMenu.list_row_rect(menu.size, win.x + win.y - 1, win.x, m)
	print("LAYOUT 视口=%s  选歌页可见行=%d  歌单页可见行=%d  行高=%.1f" % [
		str(menu.size), int(mp["shown"]), int(m["shown"]), float(m["row_h"])])
	print("LAYOUT 歌单页面板 y=[%.0f, %.0f]  页头 y=[%.0f, %.0f]  首行 y=%.0f  末行 y=[%.0f, %.0f]" % [
		r.position.y, r.end.y, hd.position.y, hd.end.y,
		row0.position.y, rowN.position.y, rowN.end.y])
	_check(hd.end.y <= row0.position.y + 0.01, "页头底边不越过第一行顶边（**不重叠**）")
	_check(rowN.end.y <= r.end.y + 0.01, "最后一行仍在面板内（行块没排多）")
	_check(r.position.y >= MainMenu.PANEL_TOP - 0.01,
		"面板顶边没上浮进标题带（y=%.0f >= PANEL_TOP=%.0f）" % [r.position.y, MainMenu.PANEL_TOP])
	_check(int(m["shown"]) < int(mp["shown"]),
		"歌单页可见行（%d）比选歌页（%d）**少一行** —— 页头这笔账是明付的，不是 bug" % [
			int(m["shown"]), int(mp["shown"])])


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if str(a[i]) != str(b[i]):
			return false
	return true


func _q(s: String) -> String:
	return "\"%s\"" % s


func _md5(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "(没有这个文件)"
	var b := FileAccess.get_file_as_bytes(path)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(b)
	return ctx.finish().hex_encode()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("   [%s] %s" % ["OK" if ok else "!!", what])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait_sec(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await get_tree().physics_frame


func _shot(name: String) -> void:
	# ⚠️ headless（Dummy 渲染器）下 `RenderingServer.frame_post_draw` **永不触发**
	# ⇒ 不加这一句的话，无头跑会**卡死在那里**（实测踩过：就停在第一个 `_shot`）。
	if DisplayServer.get_name() == "headless":
		print("SHOT_SKIPPED(headless) ", name)
		return
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport) ", name)
		return
	var tex := vp.get_texture()
	if tex == null:
		print("SHOT_FAILED(no texture) ", name)
		return
	var img := tex.get_image()
	if img == null:
		print("SHOT_FAILED(no image) ", name)
		return
	var path := out_dir.path_join("%s.png" % name)
	print("SHOT %s  err=%d  %dx%d" % [path, img.save_png(path), img.get_width(), img.get_height()])
