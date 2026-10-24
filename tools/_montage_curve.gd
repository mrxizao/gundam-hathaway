extends SceneTree
## 把 12 张形态对照图拼成 **2 行 × 6 列**（上排全身 / 下排背部特写，左→右 morph 递增）。
##
## 曲线源 = `xi_cruise_on.glb`（★ **6 根形态骨同步展开** + 两端缓动）。
## 6 档横排能直接看出两件事：
##   ① 肩板 `Binder*` 与翼板 `Wing*` **一起**张开（不是先肩后翼）；
##   ② 两端慢、中间快（缓动）—— 0.22 与 0.89 两档的变化量都明显小于中段。
##
## 本机无 PIL，用 Godot 的 Image API 拼（headless 下只做像素搬运，不需要渲染）。
const D := "C:/Users/MSIPC/WorkBuddy/2026-09-25-15-13-53/gundam-anim/_relay/_shots_xi_sync"
const OUT := "C:/Users/MSIPC/WorkBuddy/2026-09-25-15-13-53/gundam-anim/_relay/xi_cruise_form_sync.png"
const STEPS := ["f00_m0.00", "f06_m0.22", "f12_m0.44", "f18_m0.67", "f24_m0.89", "f30_m1.00"]

func _initialize() -> void:
	var imgs: Array[Image] = []
	var names: Array[String] = []
	for tag: String in ["full", "tail"]:
		for s: String in STEPS:
			var c := "frozen_%s_%s.png" % [tag, s]
			var p: String = D + "/" + c
			var im := Image.load_from_file(p)
			if im == null:
				print("!! 读不到 " + p)
				quit(1)
				return
			im.convert(Image.FORMAT_RGBA8)
			print("  %-32s %s" % [c, str(im.get_size())])
			imgs.append(im)
			names.append(c)
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	for i in imgs.size():
		if imgs[i].get_width() != w or imgs[i].get_height() != h:
			print("!! 尺寸不一致：%s" % names[i])
			quit(1)
			return
	var cols := STEPS.size()
	var sheet := Image.create_empty(w * cols, h * 2, false, Image.FORMAT_RGBA8)
	for i in imgs.size():
		var cx: int = (i % cols) * w
		var cy: int = int(i / cols) * h
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i(cx, cy))
	var err := sheet.save_png(OUT)
	print("saved %s err=%d size=%s" % [OUT, err, str(sheet.get_size())])
	quit(0)
