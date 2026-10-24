extends SceneTree
## 拼「参照（巡航）vs 主模型（常态）」同相机对比图：2 行 × 4 列。
##   上排 = 参照（别人做的巡航 2.0，已按 −90° 校正朝向）
##   下排 = 主模型 xi_fly（常态）
##   列 = top / side / front / q
##
## 本机无 PIL，用 Godot 的 Image API 拼（headless 只做像素搬运）。
const D := "C:/Users/MSIPC/WorkBuddy/2026-09-25-15-13-53/gundam-anim/_relay/_shots_ref"
const OUT := "C:/Users/MSIPC/WorkBuddy/2026-09-25-15-13-53/gundam-anim/_relay/xi_cruise_ref_vs_main.png"
const ROWS := ["ref", "main"]
const VIEWS := ["top", "side", "front", "q"]


func _initialize() -> void:
	var imgs: Array[Image] = []
	for r: String in ROWS:
		for v: String in VIEWS:
			var p: String = D + "/" + ("%s_%s.png" % [r, v])
			var im := Image.load_from_file(p)
			if im == null:
				print("!! 读不到 " + p)
				quit(1)
				return
			im.convert(Image.FORMAT_RGBA8)
			print("  %-16s %s" % ["%s_%s" % [r, v], str(im.get_size())])
			imgs.append(im)
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	for i in imgs.size():
		if imgs[i].get_width() != w or imgs[i].get_height() != h:
			print("!! 尺寸不一致：index %d" % i)
			quit(1)
			return
	var cols := VIEWS.size()
	var sheet := Image.create_empty(w * cols, h * ROWS.size(), false, Image.FORMAT_RGBA8)
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h),
			Vector2i((i % cols) * w, int(i / cols) * h))
	var err := sheet.save_png(OUT)
	print("saved %s err=%d size=%s" % [OUT, err, str(sheet.get_size())])
	quit(0)
