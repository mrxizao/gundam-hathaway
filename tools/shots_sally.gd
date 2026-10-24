extends Node
## 剧情模式「出击循环」四页的真机截图台（DESIGN-2026-09-28 · 轮 C）。
##
## 为什么单开一个而不是扩 `tools/capture.gd`：那个是 1.1 的全流程剧本（十几张图、
## 两分钟起），而这一轮要核对的只有四件**界面事实**：
##   ① 战役图：四态各自的标签（当前 / 已通关 A / 可出击 / 需通关上一关）+ 军资余额；
##   ② 简报页：章节行带**章号**、目标清单「[主] 在前 [次] 在后」、720p 下也排得下；
##   ③ 标题卡：2 秒停留的中途一帧（叠在战场之上）；
##   ④ 结算页：**军资 +N**（通关）/ **军资 +0 · 未达成 + R 重来**（失败），
##      以及**非剧情模式的对照帧**（那一行整行不画、提示行里没有"重来"）。
##
## ⚠️ **不能加 `--headless`** —— 无头用 dummy 渲染器，一个像素都不产生，抓出来全黑。
## 这个脚本的全部意义就是**能真的看到**，所以必须开窗口跑。
##
## ⚠️ 存档走**注入的临时路径**：本台会真的调 `_settle_campaign()`（那是结算页上那两个数
## 的唯一来源），若写到真档就把玩家攒的军资与解锁进度改了。见 §6.6 第 1 条纪律。
##
## 跑法：
##   godot --path <工程> res://tools/shots_sally.tscn -- <输出目录>
##
## 脚本里所有等待都走**物理帧**（物理固定 60 Hz；等渲染帧在 300+ fps 的窗口里
## 只有几分之一秒，会出现"页面还没重画就截图了"）。

const SHOT_W := 1600
const SHOT_H := 900
const SMALL_W := 1280
const SMALL_H := 720

const CS := preload("res://scripts/data/campaign.gd")
const MS := preload("res://scripts/data/mission_script.gd")
const CMAP := preload("res://scripts/ui/campaign_map.gd")

## 本台的临时存档（**绝不碰** `user://campaign.cfg`）。
const TMP := "user://campaign_shots_tmp.cfg"

var main: Node
var out_dir := "user://shots_sally"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)
	# ★ 注入临时存档路径：下面会真的落盘，但写的是临时文件。
	main.set("campaign_save_path", TMP)

	var hud: Node = main.get("hud")
	if hud == null or not is_instance_valid(hud):
		push_error("SHOTS_FAILED(no hud)")
		get_tree().quit(1)
		return

	await _entry_shot()
	await _campaign_shots()
	await _brief_shots()
	await _title_shot()
	await _result_shots(hud)
	await _small_views(hud)

	CS.erase(TMP)
	print("SHOTS done -> %s" % out_dir)
	get_tree().quit(0)


# ============================================================ ⓪ 菜单入口
## 老板的原话是「现在剧情模式的入口还是之前版本的」⇒ 这一张就是那一句的判据：
## 模式页上把光标摆到**剧情挑战**，右侧应该只写"① 选择模式"（**一步**），
## 而不是旧向导的"模式/机体/遭遇/难度"四步。
func _entry_shot() -> void:
	var menu: Node = main.get("menu")
	if menu == null or not is_instance_valid(menu):
		push_error("SHOTS_FAILED(no menu)")
		return
	menu.call("select_mode", Game.MatchMode.CHALLENGE)
	menu.set("stage", MainMenu.Stage.MODE)
	await _frames(16)
	await _shot("00_menu_entry")
	print("MENU 步骤条 = %s（共 %d 步）· 分组 = %s"
		% [str(menu.call("step_labels")), int(menu.call("step_count")),
			str((menu.call("current_group") as Dictionary).get("name", ""))])


# ============================================================ ① 战役图
func _campaign_shots() -> void:
	# ---- 空档：M01 是"当前该打的"，M02 起全锁着 ----
	CS.erase(TMP)
	main.call("_open_campaign", Difficulty.Level.NORMAL)
	await _frames(16)
	await _shot("01_campaign_fresh")
	_report_map("fresh")

	# ---- 有进度：手工造一份"通了 M01 与 M03（**没通 M02**）"的档 ----
	# 这一份能一次把**四态**全摆出来：
	#   M01/M03 = 已通关（带成绩字母）· M02 = 当前 · M04 = 可出击（四态里最难触发的那一态）
	#   M05 起 = 需通关上一关
	# 另外 `best_grade` 里 M05 故意写 `"-"`（存档里"还没成绩"的写法）——
	# 那一格必须只说"已通关"，**不许画出「已通关 -」**。
	var p := CS.new_progress()
	p["cleared_mask"] = (1 << 0) | (1 << 2)
	p["credits"] = 630
	p["best_grade"] = {"M01": "A", "M03": "B", "M05": "-"}
	CS.save_progress(p, TMP)
	main.call("_open_campaign", Difficulty.Level.NORMAL)
	await _frames(16)
	await _shot("02_campaign_progress")
	_report_map("progress")

	# ---- 光标挪到 M04：把「可出击」那一态也点出来（其余三态仍在同一屏里）----
	var cmap: Node = main.get("campaign_map")
	cmap.set("cursor", CMAP.row_index_of("M04"))
	await _frames(12)
	await _shot("03_campaign_open_state")
	_report_map("open")


func _report_map(tag: String) -> void:
	var cmap: Node = main.get("campaign_map")
	print("MAP[%s] cursor=%d sel=%s credits=%s focus=%s"
		% [tag, int(cmap.get("cursor")), str(cmap.selected_id()),
			str(cmap.credits_text()), str(cmap.focus_text())])


# ============================================================ ② 简报页
func _brief_shots() -> void:
	for id: String in ["M01", "M04"]:
		main.call("_on_campaign_chosen", id)
		await _frames(16)
		await _shot("04_brief_%s" % id.to_lower())
		_report_brief(id)
		# 回战役图（保持下一次 open 的干净状态）
		main.call("_on_brief_cancelled")
		await _frames(8)


func _report_brief(id: String) -> void:
	var brief: Node = main.get("mission_brief")
	var shown: Dictionary = brief.shown_lines()
	print("BRIEF[%s] title=%s chapter=%s objectives=%d"
		% [id, str(shown.get("title", "")), str(shown.get("chapter", "")),
			(shown.get("objectives", []) as Array).size()])
	for line: String in (shown.get("objectives", []) as Array):
		print("   OBJ %s" % line)


# ============================================================ ③ 标题卡
func _title_shot() -> void:
	main.call("_resolve_campaign_match", "M04")
	var title: Node = main.get("mission_title")
	if not bool(title.call("play", "M04")):
		push_error("SHOTS_FAILED(title 起播失败)")
		return
	# 手动把时钟推到 0.8 秒（HOLD = 2.0）⇒ 抓的是**中途那一帧**（不是"刚起播全黑"
	# 也不是"已经收尾"）。然后只等两三帧让渲染跟上，别让树里的 `_process` 跑太多。
	title.call("_process", 0.8)
	await _frames(3)
	await _shot("05_title_card")
	print("TITLE ratio=%.2f lines=%s" % [title.call("progress_ratio"),
		str(title.call("lines"))])
	title.call("skip")
	await _frames(4)


# ============================================================ ④ 结算页
func _result_shots(hud: Node) -> void:
	# ---- 通关：军资那一行要写出 **+N**，提示行**不许**出现"重来" ----
	CS.erase(TMP)
	Game.campaign_progress = CS.new_progress()
	if not await _launch("M01"):
		return
	Game.kills = 3
	main.call("_finish_round")
	await _frames(20)
	await _shot("06_result_win")
	_report_result("win")

	# ---- 失败：**军资 +0 · 未达成**，且提示行多一个 **R 重来**（§6.7）----
	# 走真入口 `_on_player_destroyed()`（player 活着，所以这条路跑得通）——
	# 手工按它的顺序凑一遍证明不了"阵亡这条路上结算确实排在定格之前"。
	main.call("_on_player_destroyed", null)
	await _frames(18)
	await _shot("07_result_lose")
	_report_result("lose")
	print("LOSE can_retry=%s" % str(main.call("_can_retry")))

	# ---- ★ 对照帧：非剧情模式（`active_mission = null` ⇒ sally 空）----
	# 这一帧存在的意义就是**证明多出来的那两样东西真的都不在**：
	#   军资那一行整行不画、提示行回到"Enter / Esc  回主菜单"（§9.4 的硬约束）。
	Game.active_mission = null
	main.call("_settle_campaign", true)
	hud.capture_result(MissionRating.Outcome.WIN)
	await _frames(18)
	await _shot("08_result_nonstory")
	_report_result("nonstory")


## 真起一局：`_resolve_campaign_match()` → `_launch_match()` → 等 player 落地。
##
## ⚠️ 结算页**必须真起一局**才拍得到：`FlightHUD.capture_result()` 第一行就是
## `if player == null or not is_instance_valid(player): return` —— 没有 player 就没有快照，
## 结算页一个像素都不画。而 `_result` 也**不能手工伪造**（那是自己写一份数据给自己看，
## 拍出来的图证明不了任何事）。⇒ 走真入口 `_launch_match()`，它会经
## `spawn_round()` → `spawn_challenge()` 撒出真敌机。
##
## ⚠️ 顺序：`spawn_round()` 里会 `Game.reset()`，而 `reset()` **清零 kills 与 sally_result**
## ⇒ 必须先起局、再写战果（否则那一炮白打）。
func _launch(id: String) -> bool:
	if not bool(main.call("_resolve_campaign_match", id)):
		push_error("SHOTS_FAILED(_resolve_campaign_match %s)" % id)
		return false
	main.call("_launch_match")
	await _frames(30)
	var pl = main.get("player")
	if pl == null or not is_instance_valid(pl):
		push_error("SHOTS_FAILED(player 没起来：%s)" % id)
		return false
	print("LAUNCH %s · suit=%s map=%s player=%s"
		% [id, str(SuitProfile.by_id(Game.active_suit).id_name()),
			str(Game.active_map.name_cn), str(pl.get("display_name"))])
	return true


func _report_result(tag: String) -> void:
	var sally: Dictionary = Game.sally_result
	print("RESULT[%s] sally=%s sally_text=「%s」 hint=「%s」"
		% [tag, str(sally), FlightHUD.sally_text(sally),
			FlightHUD.result_hint(sally, "回战役图" if not sally.is_empty() else "回主菜单")])


# ============================================================ ⑤ 720p 复看
## 矮一档的分辨率：简报页与结算页是**纵向最紧**的两页（720p 下右栏最后一行离框底只剩 8 px）。
## 这两张是"版式没被挤坏"的旁证，不出它们就只能靠 1600×900 那一张推断。
func _small_views(_hud: Node) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SMALL_W, SMALL_H))
	await _frames(16)

	main.call("_open_campaign", Difficulty.Level.NORMAL)
	await _frames(12)
	main.call("_on_campaign_chosen", "M01")
	await _frames(14)
	await _shot("09_brief_m01_720p")
	_report_brief("M01@720p")

	main.call("_on_brief_cancelled")
	await _frames(8)
	CS.erase(TMP)
	Game.campaign_progress = CS.new_progress()
	if not await _launch("M01"):
		return
	Game.kills = 3
	main.call("_finish_round")
	await _frames(18)
	await _shot("10_result_win_720p")
	_report_result("win@720p")

	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(12)


# ============================================================ 工具
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
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
	print("SHOT %s  %dx%d  err=%d"
		% [path, img.get_width(), img.get_height(), img.save_png(path)])
