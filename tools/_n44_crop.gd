extends Node
## 把一张 PNG 的指定矩形**裁切 + 整数倍放大**另存，用来肉眼核对小结构。
##
## 这个工程没装 PIL（`python -c "import PIL"` 直接 ImportError），
## 而 Godot 自带 `Image.get_region()` / `resize()`，所以裁图用它。
##
## 跑法：
##   godot --headless --path <工程> res://tools/_n44_crop.tscn -- <in.png> <out.png> <x> <y> <w> <h> <倍率>
## 说明：坐标是**左上角原点**、单位像素；越界部分会自动裁到图内。

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 7:
		print("用法: -- <in> <out> <x> <y> <w> <h> <scale>")
		get_tree().quit(1)
		return
	var ip := str(a[0])
	var op := str(a[1])
	var x := int(a[2])
	var y := int(a[3])
	var w := int(a[4])
	var h := int(a[5])
	var k := int(a[6])

	var img := Image.new()
	var err := img.load(ip)
	if err != OK:
		print("!! 载入失败 (%d) %s" % [err, ip])
		get_tree().quit(1)
		return
	print("源图 %dx%d ｜ 请求 (%d,%d) %dx%d x%d" % [img.get_width(), img.get_height(), x, y, w, h, k])

	# 裁到图内（原图可能比请求小）
	if x < 0:
		w += x
		x = 0
	if y < 0:
		h += y
		y = 0
	w = mini(w, img.get_width() - x)
	h = mini(h, img.get_height() - y)
	if w <= 0 or h <= 0:
		print("!! 裁切区域为空")
		get_tree().quit(1)
		return

	var sub := img.get_region(Rect2i(x, y, w, h))
	print("裁到 (%d,%d) %dx%d ｜ 放大 x%d" % [x, y, w, h, k])
	sub.resize(w * k, h * k, Image.INTERPOLATE_NEAREST)
	var e2 := sub.save_png(op)
	if e2 != OK:
		print("!! 写盘失败 (%d) %s" % [e2, op])
		get_tree().quit(1)
		return
	print("saved %s (%dx%d)" % [op, sub.get_width(), sub.get_height()])
	print("VERDICT: N44-CROP-DONE")
	get_tree().quit(0)
