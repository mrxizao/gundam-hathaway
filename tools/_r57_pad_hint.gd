extends Control
## 一次性出图台（轮 57）：证明「**页脚承诺的手柄键位**」真的会画出来。
##
## ## 为什么需要这张图
## 轮 57 修的 bug 是「任务菜单选择的时候手柄按下没有反应」，根因是
## `campaign_map.gd` / `mission_brief.gd` 的 `_input()` 第一行写着
## `if not (event is InputEventKey): return` ⇒ 手柄事件在门口被丢掉。
##
## ★ 这个 bug 的形状是「**提示与实现分家**」：两页的页脚从落地那天就印着
## 「十字键选择 · A 出击 · B 返回」（`_draw_hint()` 的 `InputSetup.hint()` 第二参数），
## 而实现里一个手柄键都进不来。⇒ 断言能钉住"事件路径通不通"，
## 但**钉不住"页脚到底印了什么字"** —— 那一半只能看图。
##
## ⚠️ 页脚文案随 `InputSetup.using_gamepad` 切换（用户明确要求的行为：
## 接到手柄键才切手柄文案，不是"插了手柄就永远显示手柄"）
## ⇒ 图必须**成对**出：键鼠一版、手柄一版，否则看不出"切换"这件事。
##
## ## 四张图（两对对照）
## | 图 | 钉住的那句话 |
## |---|---|
## | `00_campaign_kb`  | （对照）键鼠模式 ⇒ 页脚是 `W/S 选择 · ←/→ 难度 · Enter 出击 · Esc 返回` |
## | `02_campaign_pad` | ★ 手柄模式 ⇒ 页脚变成 `十字键选择 · 左右调难度 · A 出击 · B 返回` |
## | `01_brief_kb`     | （对照）键鼠模式 ⇒ 页脚是 `Enter 出击 / Esc 返回` |
## | `03_brief_pad`    | ★ 手柄模式 ⇒ 页脚变成 `A 出击 / B 返回` |
##
## ⚠️ **不能加 `--headless`** —— 无头用 dummy 渲染器，一个像素都不产生。
##
## ⚠️ **绝不碰玩家存档**：战役进度用 `CampaignScript.new_progress()` 造一份空的。
## 跑完把 `using_gamepad` 复位回 `false`。
##
## 跑法：
##   godot --path <工程> res://tools/_r57_pad_hint.tscn -- <输出目录>

const CMAP := preload("res://scripts/ui/campaign_map.gd")
const CBRIEF := preload("res://scripts/ui/mission_brief.gd")
const CS := preload("res://scripts/data/campaign.gd")
const MS := preload("res://scripts/data/mission_script.gd")

const SHOT_W := 1600
const SHOT_H := 900

var out_dir := "user://shots_pad"
var cmap: Control
var brief: Control


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.03, 0.055, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	cmap = CMAP.new()
	add_child(cmap)
	brief = CBRIEF.new()
	add_child(brief)

	if not bool(cmap.call("open", CS.new_progress())):
		print("OPEN_FAILED campaign")
	if not bool(brief.call("open", MS.by_id(str(CS.mission_ids()[0])))):
		print("OPEN_FAILED brief")
	# 两页都是纯 `_draw()` 面板 ⇒ 关掉 `_process`（顺带关掉摇杆导航，
	# 免得本机插着手柄时读数被摇杆影响）；重绘由 `_shot()` 自己推。
	cmap.set_process(false)
	brief.set_process(false)

	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	# ---- 第一对：键鼠模式（对照）----
	InputSetup.using_gamepad = false
	await _pair("00_campaign_kb", "01_brief_kb")

	# ---- 第二对：手柄模式（本轮修的现场）----
	InputSetup.using_gamepad = true
	await _pair("02_campaign_pad", "03_brief_pad")

	InputSetup.using_gamepad = false
	print("HINT SHOTS done -> %s" % out_dir)
	get_tree().quit(0)


## 两个页面都是**全屏 `Control`**，在树里后加的那个画在上面 ⇒ 拍谁就把另一个藏起来。
func _pair(a: String, b: String) -> void:
	cmap.visible = true
	brief.visible = false
	await _shot(a)
	cmap.visible = false
	brief.visible = true
	await _shot(b)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	# ⚠️ **必须自己推重绘**：两页都是 `set_process(false)` 的纯 `_draw()` 面板，
	# 正常游戏里由 `main` 每帧替它们 `queue_redraw()`，本台没有 `main`。
	cmap.queue_redraw()
	brief.queue_redraw()
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
	print("SHOT %s  %dx%d  err=%d  gamepad=%s"
		% [path, img.get_width(), img.get_height(), img.save_png(path),
			str(InputSetup.using_gamepad)])
