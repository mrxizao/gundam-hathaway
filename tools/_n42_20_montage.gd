extends Node
## 把 N42·二十 的四张同相机图拼成一张 2×2 对照图（用 Godot `Image` API，**无 PIL**）。
##
## 布局（每格同尺寸，左上为一格原点）：
##   上排 = 游戏内： [0] 常态 morph=0 ｜ [1] 巡航 morph=1
##   下排 = 参照：   [2] 常态2.0      ｜ [3] 巡航2.0
##
## 用法：godot --path . res://tools/_n42_20_montage.tscn -- --dir <图目录> --out <png>

const NAMES := [
	"game_normal_top.png",
	"game_cruise_top.png",
	"ref_normal_top.png",
	"ref_cruise_top.png",
]
const COLS := 2
const GAP := 8


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var dir := ""
	var out := ""
	for i in a.size():
		if a[i] == "--dir" and i + 1 < a.size():
			dir = a[i + 1]
		if a[i] == "--out" and i + 1 < a.size():
			out = a[i + 1]
	if dir == "" or out == "":
		print("!! 需要 --dir 与 --out")
		get_tree().quit(1)
		return

	var imgs: Array[Image] = []
	var w := 0
	var h := 0
	for n in NAMES:
		var p: String = dir.path_join(n)
		var im := Image.load_from_file(p)
		if im == null:
			print("!! 读不到 %s" % p)
			get_tree().quit(2)
			return
		# 统一到第一张的尺寸（四张同相机 ⇒ 本就同尺寸；防意外仍做一次缩放）。
		if imgs.is_empty():
			w = im.get_width()
			h = im.get_height()
		elif im.get_width() != w or im.get_height() != h:
			im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		# 统一格式：`blit_rect` 要求源与目标**格式一致**（否则静默报错、该格留空）。
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		imgs.append(im)
		print("  loaded %s  %dx%d" % [n, im.get_width(), im.get_height()])

	var rows := int(ceil(float(imgs.size()) / float(COLS)))
	var ow := COLS * w + (COLS + 1) * GAP
	var oh := rows * h + (rows + 1) * GAP
	var canvas := Image.create(ow, oh, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.10, 0.11, 0.13, 1.0))
	for i in imgs.size():
		var c := i % COLS
		var r := i / COLS
		var x := GAP + c * (w + GAP)
		var y := GAP + r * (h + GAP)
		canvas.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i(x, y))
	var err := canvas.save_png(out)
	print("  saved %s (%dx%d) err=%d" % [out, ow, oh, err])
	print("VERDICT: N42-20-MONTAGE-DONE")
	get_tree().quit(0)
