extends SceneTree
## 把外部的标题 LOGO（白字 + 黑底）转成**带 alpha 通道**的 PNG，放进工程。
##
## 跑法：
##   godot --headless --path <工程> --script res://tools/make_title_logo.gd -- <源 PNG> <输出路径>
## 两个参数都可以省；省略时用下面的默认值。
##
## ## 为什么要转
## 用户给的 `title.png` 是**白字黑底、完全不透明**的：
##   直接画进主菜单就是一个黑色方块（菜单背后是星空与 3D 夜景，一眼就看出来）。
##
## 菜单里的 LOGO 只有"亮/暗"两种信息，所以按**亮度当 alpha** 是最贴切的抠图方式：
##   白色笔画 → 不透明；黑色底 → 全透明；抗锯齿的灰边 → 半透明（边缘依然平滑）。
## 用"亮度"而不是"颜色阈值 + 硬切"，就是为了保住那些灰边 —— 硬切的锯齿在标题这种
## 大字号笔画上非常刺眼。转好的图存成普通 RGBA PNG，运行时就是一张**普通透明贴图**，
## 不需要在游戏里挂 shader（每帧都省一点，也少一个会坏的地方）。
##
## 转换只做一次；以后换标题图，重跑这条命令即可。

const DEFAULT_SRC := "C:/Users/MSIPC/Desktop/游戏/gundam 105 muisc/title.png"
const DEFAULT_DST := "res://assets/ui/title.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src := args[0] if args.size() > 0 else DEFAULT_SRC
	var dst := args[1] if args.size() > 1 else DEFAULT_DST

	var img := Image.load_from_file(src)
	if img == null or img.is_empty():
		printerr("读不到源图：", src)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("源图 %s  %d×%d  alpha=%s" % [src, w, h, _alpha_name(img.detect_alpha())])

	# 先看一眼源图自己的 alpha 到底有没有用（有通道 ≠ 真透明：
	# 常见情况是"通道在，但整张图全是 255"，那种黑底照样是一个黑方块）
	var src_clear := 0
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.5:
				src_clear += 1
	print("源图自带透明像素 %d / %d（%.1f%%）" % [src_clear, w * h,
		100.0 * float(src_clear) / float(w * h)])

	# **一律再乘一次亮度当 alpha**：a = a_src × 亮度。
	#
	# 白字黑底这个前提下它永远是想要的答案：
	#   白色笔画      → 1×1 = 不透明
	#   黑色底        → 1×0 = 全透明（哪怕源图的 alpha 全是 255）
	#   抗锯齿灰边    → 按"有多亮"给半透明，边缘仍然平滑（硬切阈值会有锯齿）
	#   本来就有 alpha 的边 → 0.5×0.5 依旧正确，不会把好图改坏
	# 用乘法而不是二选一，是为了**处理两种源图都不用改代码**。
	var opaque := 0
	var alpha_sum := 0.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var a := c.a * maxf(c.r, maxf(c.g, c.b))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
			alpha_sum += a
			if a > 0.5:
				opaque += 1
	print("亮度抠图后：不透明像素 %d / %d（%.1f%%），平均 alpha %.3f"
		% [opaque, w * h, 100.0 * float(opaque) / float(w * h), alpha_sum / float(w * h)])

	var dir := dst.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(dst)
	print("写出 %s  err=%d  最终 alpha=%s" % [dst, err, _alpha_name(img.detect_alpha())])
	quit(0 if err == OK else 1)


func _alpha_name(mode: int) -> String:
	match mode:
		Image.ALPHA_NONE:
			return "无"
		Image.ALPHA_BIT:
			return "1 bit"
		Image.ALPHA_BLEND:
			return "8 bit 平滑"
	return "?"
