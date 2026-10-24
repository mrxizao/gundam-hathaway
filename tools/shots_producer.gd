extends Control
## **制作人模式**（隐藏的密码入口）的真机截图台 · 2026-09-30。
##
## ## 为什么**不**复用 `tools/shots_sally.gd`
## 那一台要 `main.tscn`（整个 3D 战场 + 主场景相位机）。而本轮要核对的七件事
## **全都只发生在两个纯 `_draw()` 面板上** —— 设置页（`main_menu.gd`）与
## 战役图（`campaign_map.gd`）。直接建这两个面板：少一半启动时间，
## 而且**不受"主场景起不起得来"的影响**。
##
## ⚠️ 这条"不受影响"不是理论，是截这张图时**真实发生**的事：
## `scripts/main.gd` 当时引用着尚不存在的 `LaunchScript.pad_pos()` /
## `pad_top()`（并行会话的火箭发射段在制品）⇒ `main.gd` **整个编译不过** ⇒
## `main.tscn` 起不来 ⇒ 所有走 `main.tscn` 的出图台此刻一张图都拍不出来。
##
## ✅ **该状态已于 2026-09-30 01:41 解除**（`main.gd` 已跟上改名，
## `--check-only` 与全量回归都干净）。但本台**仍然不走 `main.tscn`** ——
## 理由与那次故障无关：它只驱动两个纯 `_draw()` 面板，少一半启动时间。
## ⇒ 这一段留着当"为什么这么设计"的记录，**不要**再把它当成当前状态。
##
## ## 七张图（两张是对照）
## | 图 | 钉住的那句话 |
## |---|---|
## | `00_settings_normal` | （对照）光标在普通行上 ⇒ **有**高亮 |
## | `01_settings_hidden_row` | 「**藏到最地下看不到的地方**」⇒ 光标停上去，**整页没有高亮** |
## | `02_password_typing` | 「选到之后输入密码」⇒ 点数回显（位数看得见、密码看不见） |
## | `03_password_wrong` | 「密码不正确」是**红字**，且**不透露差几位** |
## | `04_settings_after_submit` | 「按 enter 打开制作人模式」⇒ 那一行**显形**、读数「开（Enter 关闭）」 |
## | `05_campaign_locked` | （对照）不开 ⇒ 有锁 / 军资 0 / 没有 ★ 标记 |
## | `06_campaign_producer` | 「解锁各种关卡和配件，可以调试各种关卡」⇒ 全解锁 / 军资 ∞ / ★ 标记 |
##
## ⚠️ **不能加 `--headless`** —— 无头用 dummy 渲染器，一个像素都不产生。
## 这个脚本的全部意义就是**能真的看到**。
##
## ⚠️ **绝不碰玩家存档**：战役进度用 `CampaignScript.new_progress()` 造一份空的
## （不是读 `user://campaign.cfg`）；制作人模式开关是**会话级**的
## （`Game.producer_mode`，本来就不落盘），本台跑完关回去。
##
## 跑法：
##   godot --path <工程> res://tools/shots_producer.tscn -- <输出目录>
##
## 脚本里所有等待都走**物理帧**（物理固定 60 Hz；等渲染帧在 300+ fps 的窗口里
## 只有几分之一秒，会出现"页面还没重画就截图了"）。

const MM := preload("res://scripts/ui/main_menu.gd")
const CMAP := preload("res://scripts/ui/campaign_map.gd")
const CS := preload("res://scripts/data/campaign.gd")
const PROD := preload("res://scripts/data/producer.gd")

const SHOT_W := 1600
const SHOT_H := 900

var out_dir := "user://shots_producer"
var menu: Control
var cmap: Control


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	# 底板。正常游戏里这两页背后是 3D 战场；本台没有战场，画一块深色底
	# 就够了（不然战役图那块半透明面板会压在最底下的默认清屏色上）。
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.03, 0.055, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ★ 每个进程从"关"开始 —— 这正是「每次打开游戏都必须手动开启」的现场。
	Game.set_producer_mode(false)

	menu = MM.new()
	add_child(menu)
	cmap = CMAP.new()
	add_child(cmap)

	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	await _settings_shots()
	await _password_shots()
	await _campaign_shots()

	Game.set_producer_mode(false)
	print("SHOTS done -> %s" % out_dir)
	get_tree().quit(0)


# ============================================================ ①② 设置页

func _settings_shots() -> void:
	menu.set("stage", MainMenu.Stage.SETTINGS)

	# ---- 对照：光标在**普通行**上 ⇒ 有高亮 ----
	menu.set("setting_row", 0)
	await _frames(6)
	await _shot("00_settings_normal")
	_report_settings("00 光标在第 0 行（对照：应当**有**高亮）")

	# ---- 判据：光标停在**隐形行**上 ⇒ 整页没有任何高亮 ----
	menu.set("setting_row", MainMenu.producer_row())
	await _frames(6)
	await _shot("01_settings_hidden_row")
	_report_settings("01 光标停在**隐形行**上（『藏到最地下看不到』的判据）")


## 这一帧上**真的会被高亮**的那一行。
##
## `-1` = 整页没有任何高亮 —— 那就是"藏到最地下看不到"在读数上的样子。
## ⚠️ 它必须与绘制循环走**同一个** `setting_row_hidden()`；各写一份的话
## 判据就会与画面分家（"读数说选中了、屏幕上没高亮"谁也说不清了）。
func _highlighted_row() -> int:
	var i := int(menu.get("setting_row"))
	if i < 0 or i >= MainMenu.SETTING_ROWS.size():
		return -1
	if MainMenu.setting_row_hidden(i, Game.producer_mode):
		return -1
	return i


func _report_settings(tag: String) -> void:
	var i := int(menu.get("setting_row"))
	var key := str((MainMenu.SETTING_ROWS[i] as Dictionary).get("key", ""))
	var hidden := MainMenu.setting_row_hidden(i, Game.producer_mode)
	print("--- %s" % tag)
	print("    setting_row=%d / 共 %d 行（producer_row()=%d）"
		% [i, MainMenu.SETTING_ROWS.size(), MainMenu.producer_row()])
	print("    这一行：key='%s'  名字='%s'  隐藏=%s  读数='%s'"
		% [key, MainMenu.setting_label(i), str(hidden),
			str(menu.call("_setting_value_text", key))])
	print("    ★ 这一帧真的会被高亮的行 = %d（-1 就是「整页没有高亮」）"
		% _highlighted_row())


# ============================================================ ③④ 密码页

func _password_shots() -> void:
	# ---- 输入中：只画点数（位数看得见、密码看不见）----
	menu.set("stage", MainMenu.Stage.PASSWORD)
	menu.set("pw_msg", "")
	menu.set("pw_ok", true)
	menu.set("pw_input", PROD.sanitize("2006"))
	await _frames(6)
	await _shot("02_password_typing")
	print("--- 02 输入中：已洗过的输入='%s'  回显='%s'  位数=%d"
		% [str(menu.get("pw_input")), PROD.echo(str(menu.get("pw_input"))),
			PROD.typed_count(str(menu.get("pw_input")))])

	# ---- 按错：红字，**不透露差几位** ----
	menu.set("pw_input", "")
	menu.set("pw_msg", PROD.WRONG)
	menu.set("pw_ok", false)
	await _frames(6)
	await _shot("03_password_wrong")
	print("--- 03 按错：结果行='%s'（红字）· 里面出现密码吗=%s · 出现「差几位」吗=%s"
		% [PROD.WRONG, str(PROD.WRONG.contains(PROD.CODE)),
			str(PROD.WRONG.contains("位"))])

	# ---- 真提交（走 `submit_password()`，那是判定的**唯一**实现）----
	var ok := bool(menu.call("submit_password", PROD.CODE))
	await _frames(6)
	print("--- 04 submit_password('%s') => %s · Game.producer_mode=%s · stage=%d"
		% [PROD.CODE, str(ok), str(Game.producer_mode), int(menu.get("stage"))])
	menu.set("stage", MainMenu.Stage.SETTINGS)
	menu.set("setting_row", MainMenu.producer_row())
	await _frames(6)
	await _shot("04_settings_after_submit")
	_report_settings("04 提交成功之后停在那一行（**显形**了 ⇒ 这里才看得到高亮）")


# ============================================================ ⑤⑥ 战役图

func _campaign_shots() -> void:
	var fresh := CS.new_progress()

	# ⚠️ 两个页面都是**全屏 `Control`**，在树里后加的那个画在上面。拍战役图之前
	# 必须把菜单藏起来 —— 否则设置页的十四行会从战役图那块半透明面板底下透出来
	# （首版就是这样：一张图里两页叠着，很难看出哪一行是哪一页的）。
	menu.visible = false

	# ---- 对照：不开制作人模式 ----
	Game.set_producer_mode(false)
	cmap.call("open", fresh)
	cmap.set("producer", Game.producer_mode)
	await _frames(6)
	await _shot("05_campaign_locked")
	_report_campaign("05 对照：producer = 关")

	# ---- 开：全关卡解锁 + 军资 ∞ + ★ 标记 ----
	Game.set_producer_mode(true)
	cmap.set("producer", Game.producer_mode)
	cmap.call("refresh")
	await _frames(6)
	await _shot("06_campaign_producer")
	_report_campaign("06 制作人模式：开")
	cmap.call("close")
	menu.visible = true


func _report_campaign(tag: String) -> void:
	var p: Dictionary = cmap.get("progress")
	var lines: Array = []
	for id: String in CS.mission_ids():
		lines.append("%s=%s" % [id, CMAP.state_label(p, id, Game.producer_mode)])
	print("--- %s" % tag)
	print("    producer=%s  军资读数='%s'  credits_of=%d"
		% [str(cmap.get("producer")), str(cmap.call("credits_text")),
			CS.credits_of(p, bool(cmap.get("producer")))])
	print("    七关四态：%s" % "  ".join(lines))
	print("    存档里的真实余额仍然是 %d（∞ 只是**投影**，不写档）"
		% int(p.get("credits", 0)))


# ============================================================ 工具

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	# ⚠️ **必须自己推重绘**：这两个页面都是 `set_process(false)` 的纯 `_draw()` 面板，
	# 正常游戏里由 `main` 每帧替它们 `queue_redraw()`。本台没有 `main`
	# ⇒ 不推的话页面会**停在第一次绘制上**。
	#
	# ★ 这个坑的症状值得记住：**七张图里有五张字节完全相同**（不是报错、不是黑屏 ——
	# 是"页面对了、状态没跟上"）。`campaign_map` 那两张之所以正常，只是因为它
	# 的 `open()` 里自己调了 `queue_redraw()`，属于**巧合**而非设计。
	menu.queue_redraw()
	cmap.queue_redraw()
	await _frames(2)
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
