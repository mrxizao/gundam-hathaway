extends Node
## 量四张同相机图的**非背景轮廓包围盒**，算「巡航/常态」的展开比。
##
## 为什么需要：`model_bounds` 是 rest 包围盒（形态变化它不变）⇒ 不能用它证明"有没有展开"。
## 屏幕轮廓是**唯一**能反映"世界位置真的变了"的读数。
##
## 用法：godot --path . res://tools/_n42_20_sil.tscn -- --dir <图目录>

const NAMES := [
	"game_normal_top.png",
	"game_cruise_top.png",
	"ref_normal_top.png",
	"ref_cruise_top.png",
]
## 降采样后再扫（2560×1600 逐像素在 GDScript 里太慢）。
const DW := 640


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var dir := ""
	for i in a.size():
		if a[i] == "--dir" and i + 1 < a.size():
			dir = a[i + 1]
	print("")
	print("########## 轮廓包围盒（同相机一对一比）##########")
	var res: Dictionary = {}
	for n in NAMES:
		var im := Image.load_from_file(dir.path_join(n))
		if im == null:
			print("  !! 读不到 %s" % n)
			continue
		var h := int(round(float(im.get_height()) * DW / float(im.get_width())))
		im.resize(DW, h, Image.INTERPOLATE_LANCZOS)
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		var bg := im.get_pixel(2, 2)
		var x0 := DW
		var y0 := h
		var x1 := -1
		var y1 := -1
		var count := 0
		for y in h:
			for x in DW:
				var c := im.get_pixel(x, y)
				if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.06:
					count += 1
					if x < x0: x0 = x
					if y < y0: y0 = y
					if x > x1: x1 = x
					if y > y1: y1 = y
		var w := x1 - x0 + 1
		var hh := y1 - y0 + 1
		res[n] = Vector2i(w, hh)
		print("  %-24s 轮廓 w=%4d h=%4d ｜ 像素占比 %5.2f%% ｜ 中心 x=%4d"
			% [n, w, hh, 100.0 * float(count) / float(DW * h), (x0 + x1) / 2])
	print("")
	for pr in [["game_normal", "game_cruise"], ["ref_normal", "ref_cruise"]]:
		var a1: String = str(pr[0]) + "_top.png"
		var b1: String = str(pr[1]) + "_top.png"
		if res.has(a1) and res.has(b1):
			var va: Vector2i = res[a1]
			var vb: Vector2i = res[b1]
			print("  %-14s 巡航/常态  宽 ×%.3f  高 ×%.3f"
				% [str(pr[0]).split("_")[0], float(vb.x) / float(maxi(va.x, 1)),
				   float(vb.y) / float(maxi(va.y, 1))])
	print("VERDICT: N42-20-SIL-DONE")
	get_tree().quit(0)
