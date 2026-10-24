extends Node
## 轮 53 · 战役图脚注「目标摘要」的真机出图（两处文案改动的复验）。
##
## ## 为什么必须是真机图
## 老板是**照着一张游戏截图**提的这条需求（「这个描述改一下」）⇒ 交付也必须是图。
## 而这条文案的**唯一绘制消费者**是 `scripts/ui/campaign_map.gd::_draw_foot()`：
##     `" · ".join([MS.plain(o.label) for o in m.objectives])`
## `_draw()` 在无头下什么都不画（dummy 渲染器）⇒ **不能加 `--headless`**。
##
## ## 这是"探针摆位"，不是可达界面
## 本脚本只把 `CampaignMap` 的**状态**摆到"M04 / M05 那一行"上，
## **渲染路径与字符串全部是生产代码**（`_draw_foot()` 一行都没绕开）。
## 摆进去的只有：`size` / `progress` / `cursor`。
##
## ## 跑法
##   godot --path <工程> --resolution 1600x1000 res://tools/_r53_shots.tscn -- <输出目录>
##
## 判据（看图时问的两件事）：
##   ① 那一行**是不是**「击败佩涅罗佩」/「摧毁奥恩贝利火力点 · 使金伯利无力化」；
##   ② 它**有没有溢出**脚注右端（左栏让出 260 px 给难度那一栏）。

const CMAP := preload("res://scripts/ui/campaign_map.gd")
const CS := preload("res://scripts/data/campaign.gd")

## M04 = 下标 3、M05 = 下标 4（`MASK_ORDER` 的顺序；行表里 0 是章节标题）。
## ⚠️ 轮 56 顺位：原来记的是 M05/M06 ⇒ 现在这一对是 M04「重力」/ M05「出击奥恩贝利」。
const SHOTS := [
	["01_map_foot_M04", 3],
	["02_map_foot_M05", 4],
]


func _ready() -> void:
	var out_dir := "C:/Users/MSIPC/WorkBuddy/2026-09-27-13-49-56/_r53_gravity"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	print("== r53 campaign-map foot shots ==")
	print("out_dir = %s" % out_dir)
	print("display  = %s" % DisplayServer.get_name())
	print("viewport = %s" % str(get_viewport().get_visible_rect().size))
	await get_tree().process_frame
	for item: Array in SHOTS:
		await _shot(str(item[0]), int(item[1]), out_dir)
	print("== done ==")
	get_tree().quit()


func _shot(tag: String, cursor: int, out_dir: String) -> void:
	var cm: Control = CMAP.new()
	cm.size = Vector2(1600, 1000)
	add_child(cm)
	# M01..M04 视为已通关 ⇒ 选中的那一行是"可进入"的亮色（否则 `can_enter` 为假，
	# 画出来是 `deco_white(0.34)` 的暗灰，读不清字 —— 老板那张截图就是未解锁态）。
	var p: Dictionary = CS.new_progress()
	p["cleared_mask"] = (1 << 4) - 1
	p["chapter"] = 1
	cm.open(p)
	cm.cursor = cursor
	await get_tree().process_frame
	await get_tree().process_frame
	cm.queue_redraw()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, tag]
	var err := img.save_png(path)
	print("SHOT %s  %dx%d  err=%d  cursor=%d" % [path, img.get_width(), img.get_height(), err, cursor])
	cm.queue_free()
	await get_tree().process_frame
