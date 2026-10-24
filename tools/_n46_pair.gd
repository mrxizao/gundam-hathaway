extends Node
## N46：把「待机基准」与「四个冲刺方向」的**同一机位**截图并排拼一张。
##
## ## 为什么非有它
##
## 3×3 拼图（`_n45_dash8.tscn`）每格都缩到 1/3，差异被均匀化掉了；
## 差异热力图只会说"这里变了"（二值），说不出**幅度**。
## 用户的原话是「完全看不出」—— 那唯一能服人的材料就是**同机位、等高、并排**的原图。
##
## 判读：左起 = `fly` 基准 / 后冲 / 前冲 / 左冲 / 右冲。
## 若五格的机翼、腿、肩在屏幕上**量得出**不同的倾角 ⇒ 幅度够；若五格几乎重合 ⇒ 幅度不够。
##
## 跑法（不能 `--headless`）：
##   godot --path <工程> res://tools/_n46_pair.tscn -- <输入目录> <输出png>

const CROP := Rect2i(700, 100, 1080, 1400)

var in_dir := "user://n46_dash8"
var out_png := "user://dash_pair.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		in_dir = str(args[0])
	if args.size() > 1:
		out_png = str(args[1])

	var names := ["fly", "dash_b", "dash_f", "dash_l", "dash_r"]
	var cell_w := 420
	var cell_h := int(float(CROP.size.y) * float(cell_w) / float(CROP.size.x))
	var big := Image.create(cell_w * names.size(), cell_h, false, Image.FORMAT_RGBA8)
	big.fill(Color(0.06, 0.07, 0.09))

	for k in names.size():
		var p := in_dir.path_join("%s.png" % str(names[k]))
		var img := Image.load_from_file(p)
		if img == null:
			print("  !! 读不到 %s" % p)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var sub := img.get_region(CROP)
		sub.resize(cell_w, cell_h, Image.INTERPOLATE_LANCZOS)
		big.blit_rect(sub, Rect2i(0, 0, cell_w, cell_h), Vector2i(k * cell_w, 0))
		print("  [%d] %-8s 裁 %s  → %dx%d" % [k, str(names[k]), str(CROP), cell_w, cell_h])

	big.save_png(out_png)
	print("")
	print("VERDICT: N46-PAIR-DONE  → %s" % out_png)
	get_tree().quit(0)
