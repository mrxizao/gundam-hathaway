extends SceneTree
## 把**阵营 LOGO**（满底截图）转成**带 alpha 的透明 PNG**，放进 `assets/ui/faction/`。
##
## 跑法：
##   godot --headless --path <工程> --script res://tools/make_faction_logos.gd
##
## ## 为什么必须抠底
## 用户给的两张 LOGO 都是**满底色截图**：
##   马夫蒂      = 金色十字＋圆环，**红底**
##   喀耳刻/联邦 = 金四芒星＋新月＋白字 E.F.S.F.，**蓝底**
## 直接铺到主菜单上就是两大块红/蓝色方块（菜单背后是星空与 3D 夜景，一眼就看出来）。
##
## ## 抠图方式：**亮度当 alpha**（不是"离底色的距离"）
##
## 我先用了"与底色的欧氏距离 / 阈值"给 alpha —— **实测效果不对**，理由是量出来的：
##   马夫蒂的**金色**（约 R=210 G=175 B=80、亮度 0.71）与**红底**（亮度 0.33）之间，
##   欧氏距离只有 **0.355**，除以阈值 0.55 之后 alpha 只剩 **0.6** ——
##   于是金十字被压成暗金色，"十字＋圆环"在深色菜单上几乎看不见。
## 根因：那个距离公式把"亮度差"和"色相差"混在一起算，而这里要的只是**亮度分离**。
##
## 改成 `alpha = clamp((亮度 − 底色的亮度) / (1 − 底色的亮度))`：
##   红色像素（亮度 ≤ 底色）→ 0（全透明）
##   金色（0.71）→ (0.71−0.33)/0.67 ≈ **0.57**，白字 → **1.0**
## 金色仍然只有 0.57 的 alpha，所以**同时把笔画的颜色提亮**
## （`_boost()`：把 RGB 按比例推到满值），于是它显示出来是**明亮的金色**而不是暗金。
## 这也正是原图里"金色 logo 浮在红底上"的观感 —— 底色一撤，笔画本身就得更亮。
##
## ⚠️ 两张图都适用：E.F.S.F. 那边底色是深蓝（亮度 0.24），金星与白字都远亮于它。
##
## 底色是**从四角采样**得到的，不写死：两张图底色不同，截图也可能带轻微渐变。

const SRC := [
	{
		"src": "C:/Users/MSIPC/Desktop/游戏/闪哈游戏/马夫蒂logo/QQ20260920-191706.png",
		"dst": "res://assets/ui/faction/mafty.png",
		"name": "马夫蒂",
	},
	{
		"src": "C:/Users/MSIPC/Desktop/游戏/闪哈游戏/喀耳刻部队logo/QQ20260920-191604.png",
		"dst": "res://assets/ui/faction/kilce.png",
		"name": "喀耳刻部队 / E.F.S.F.",
	},
]

## ## 顺带裁掉边距
## 截图四周有空白边，不裁的话贴图里一半是空气，缩放时 LOGO 显得很小。
## 裁到"有内容的包围盒"再留一点内边距。

## 亮度分离的两个阈值（相对"底色亮度"）：
##   低于 `DEAD` ⇒ 纯底色（全透明）
##   高于 `FULL` ⇒ 纯笔画（全不透明）
##   中间线性过渡（这一段就是抗锯齿边，线性 = 平滑、不硬切）
##
## ## 为什么过渡带这么窄（0.02 ~ 0.20）
##
## 我一开始按"亮度差 / 满量程"给 alpha，想做成**精确的权重**（亮多少就多不透明）——
## 实测是错的：马夫蒂那张的 alpha 直方图**全挤在 0.3~0.4 那一档，没有一个像素接近 1.0**
## （实测：不透明像素仅 11 个），因为金色与红底的亮度差本来就不大，
## 归一化之后谁也到不了满值。结果整个 LOGO 是半透明的暗影。
##
## 结论：**这里要的不是精确权重，而是一个实心 LOGO**。
## 底色与笔画的亮度是可分的（红底 ≈ 0.41、金 ≈ 0.7+），
## 所以只要"明显亮于底色"就判成实心 —— 过渡带只用来吃掉抗锯齿边。
const LUMA_DEAD := 0.02
const LUMA_FULL := 0.20
## 把笔画颜色**提亮**到的目标亮度。
##
## 为什么必须提亮：alpha 只到 0.57 的金色，叠在深色底上会**偏暗**（看上去像青铜而不是金）。
## 原图里它之所以看着是亮金，是因为**衬着一整片红底**；底色一撤就露馅了。
## 所以按比例把 RGB 推到满值（保持色相不变），得到的就是"发光的金"。
## 白色笔画本来就是满的，这一步对它是空操作。
const BOOST_TO := 1.0
## 输出图的长边缩到这么多像素。
##
## ## 为什么要预缩（实测结论，不是优化）
## 菜单里 LOGO 只占约 **96×80** 的格子，而原图是 485×657 —— 也就是要缩到 **1/8**。
## 直接让 GPU 在 `draw_texture_rect` 里缩，实测**画出来是一块白**：
## 透明区域的采样把颜色混进了笔画（那两张图的透明区 RGB 本来是红/蓝底）。
## 把透明像素涂黑之后仍是白块 —— 说明这个 1/8 的实时缩采样在 Godot 的
## 2D 管线里就是不可靠的。
##
## 所以**在工具里先缩好**（`Image.resize` + `INTERPOLATE_LANCZOS`，
## 一次性的高质量滤波），运行时几乎 1:1 绘制 —— 既躲开那个坑，也更省。
##
## ⚠️ 256 是"长边"：短边按比例走，所以长宽比不变。
## 它比 96 大是**刻意的余量** —— 不同窗口比例下格子会变、将来也可能放大显示，
## 留一倍多的余量免得糊。改这个数要重跑本脚本。
const OUT_LONG_SIDE := 256

## 把 LOGO **合成到菜单卡片的底色上**，输出**不透明** PNG。
##
## ## 为什么最终要走这一步（本轮最后才定位到的）
## 抠好的 RGBA PNG **文件本身完全正确**（用 Python 独立解码验证过：
## 金笔画 `(255,176,37,255)`、透明区 `alpha=0` 占 83.9%），
## 用 `Image.blend_rect()` 在 Godot 里合成也正确；
## 但运行期 `draw_texture_rect()` 把它画出来**是一块纯白**
##（截图实测：那块区域 68% 的像素是 `(255,255,255)`）。
##
## 中间排查过并**排除**的：文件损坏（Python 解码对）、纹理未导入
##（`.import` 在、`get_size()` 对）、缩采样混色（预缩到 256 长边仍白）、
## 幂等重复绘制（函数里只有一次 `draw_texture_rect`）。
## 既然 `draw_texture_rect` 上的 alpha 在这条管线里不可靠，
## **就别让它处理 alpha** —— 工具里合好底，纹理变成不透明，
## 运行期就是一次普通的贴图绘制。
##
## ⚠️ 代价：合成用的底色是**写死的菜单卡片色**，卡片换色就要重跑本脚本。
## 菜单卡片色见 `main_menu.gd` 里 `_draw_side_stage()` 的 `draw_rect`。
const CARD_BG := Color(0.05, 0.09, 0.14, 1.0)
## 合成后是否还额外输出一份带 alpha 的版本（`*_alpha.png`）。
## 留着是为了以后在**别的底色**上用（例如标题带）；菜单现在用的是合成版。
const ALSO_SAVE_ALPHA := true

## 裁边时判定"这个像素算内容"的 alpha 门槛。
const CROP_ALPHA := 0.06
## 裁完在四周留的内边距（像素）。
const CROP_PAD := 6


## 把**全透明像素的 RGB 涂黑**。这是为了让缩小时不出现"白块"。
##
## ## 为什么必须做（实测踩过）
## 抠底之后，透明区域的 RGB 仍然是**底色本身**（马夫蒂那里是红、联邦那里是蓝）——
## 因为那些像素本来就是底色，我只把 alpha 改成了 0。
## 而 LOGO 在菜单里要**缩小到约 1/8**（485×657 → 59×80），双线性采样会把
## 相邻像素平均起来：**透明像素的红/蓝被混进笔画边缘**，缩出来的整体发白/发灰。
##
## ⚠️ 只改 `alpha == 0` 的像素，**半透明的抗锯齿边一律不动** ——
## 那些像素本来就该保留颜色（它们正是描边的一部分）。
func _fix_transparent_rgb(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var n := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				n += 1
	return n


func _initialize() -> void:
	for item: Dictionary in SRC:
		_convert(str(item["src"]), str(item["dst"]), str(item["name"]))
	quit(0)


func _convert(src: String, dst: String, label: String) -> void:
	var img := Image.load_from_file(src)
	if img == null or img.is_empty():
		printerr("读不到源图：", src)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var bg := _sample_bg(img, w, h)
	print("\n=== %s ===" % label)
	print("  源图 %d×%d  采样到的底色 = %s" % [w, h, str(bg)])

	# ---- 抠底（亮度分离 + 提亮笔画）----
	var bg_luma := _luma(bg)
	print("  底色亮度 = %.3f" % bg_luma)
	var cleared := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var l := _luma(c)
			# 相对底色的亮度差 ⇒ 死区全透明、超过 LUMA_FULL 全不透明
			var rel := l - bg_luma
			var a := clampf((rel - LUMA_DEAD) / (LUMA_FULL - LUMA_DEAD), 0.0, 1.0)
			# 提亮笔画（保持色相）：按 max(r,g,b) 归一化到 BOOST_TO。
			# 白色本来就满 ⇒ 不变；金色被推到 (1.0, 0.83, 0.38) 这种"发光的金"。
			var rgb := Vector3(c.r, c.g, c.b)
			var top := maxf(rgb.x, maxf(rgb.y, rgb.z))
			if top > 0.02 and a > 0.0:
				var gain := BOOST_TO / top
				rgb = Vector3(minf(rgb.x * gain, 1.0), minf(rgb.y * gain, 1.0),
					minf(rgb.z * gain, 1.0))
			img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, a))
			if a <= 0.0:
				cleared += 1
	print("  抠底：完全透明像素 %d / %d（%.1f%%）" % [cleared, w * h,
		100.0 * float(cleared) / float(w * h)])

	# ---- 把透明像素的 RGB 涂黑（防止缩小时混色发白，见函数头那段）----
	var blackened := _fix_transparent_rgb(img)
	print("  涂黑透明像素 %d 个（缩到 1/8 时才不会发白）" % blackened)

	# ---- 裁到内容包围盒 ----
	var box := _content_box(img, w, h)
	if box.size.x > 0 and box.size.y > 0:
		var padded := Rect2i(
			Vector2i(maxi(box.position.x - CROP_PAD, 0), maxi(box.position.y - CROP_PAD, 0)),
			Vector2i(mini(box.size.x + CROP_PAD * 2, w), mini(box.size.y + CROP_PAD * 2, h)))
		# 再夹一次，别越界
		padded.size.x = mini(padded.size.x, w - padded.position.x)
		padded.size.y = mini(padded.size.y, h - padded.position.y)
		print("  裁边：%s → %s（去掉了四周空白）" % [str(Rect2i(0, 0, w, h)), str(padded)])
		img = img.get_region(padded)
	else:
		print("  ⚠️ 没找到内容，保持原尺寸")

	# ---- 预缩到显示尺寸附近（见 `OUT_LONG_SIDE` 的说明）----
	var long_side := maxi(img.get_width(), img.get_height())
	if long_side > OUT_LONG_SIDE:
		var k := float(OUT_LONG_SIDE) / float(long_side)
		var nw := maxi(int(round(img.get_width() * k)), 1)
		var nh := maxi(int(round(img.get_height() * k)), 1)
		img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
		print("  预缩：长边 %d → %d（%d×%d，躲开运行时的 1/8 实时缩采样）" % [
			long_side, OUT_LONG_SIDE, img.get_width(), img.get_height()])

	var dir := dst.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	# 需要时先留一份带 alpha 的（给别的底色用）
	if ALSO_SAVE_ALPHA:
		var alpha_dst := dst.get_basename() + "_alpha.png"
		print("  写出（带 alpha，备用） %s  err=%d" % [alpha_dst, img.save_png(alpha_dst)])
	# 合成到卡片底色 ⇒ 不透明（见 `CARD_BG` 那段说明）
	var flat := img.duplicate() as Image
	flat.convert(Image.FORMAT_RGBA8)
	for y in flat.get_height():
		for x in flat.get_width():
			var c := flat.get_pixel(x, y)
			# 标准 over 合成：结果 = 笔画 × a + 底色 × (1 − a)
			flat.set_pixel(x, y, Color(
				c.r * c.a + CARD_BG.r * (1.0 - c.a),
				c.g * c.a + CARD_BG.g * (1.0 - c.a),
				c.b * c.a + CARD_BG.b * (1.0 - c.a),
				1.0))
	var err := flat.save_png(dst)
	print("  写出（已合成底色·不透明） %s  %d×%d  err=%d" % [
		dst, flat.get_width(), flat.get_height(), err])


## 感知亮度（Rec.709）。用它做"底色 vs 笔画"的分离 —— 见文首那段说明。
func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## 从全图**取中位数**得到底色亮度。**不写死** —— 两张图底色不同。
##
## ⚠️ 为什么不用"四角采样取平均"（第一版就是这么写的，**结果错了**）：
## 马夫蒂那张的红底亮度真值约 **0.33**，而四角采样算出来是 **0.407** ——
## 偏高的阈值把一大片金色直接判成"比底色暗"，于是 alpha≈0：
## 实测产物里**不透明像素只有 11 个**（整个 LOGO 几乎全被抠没了）。
##
## 中位数天然抗噪：底色的像素占绝大多数，它们的中位数就是底色本身，
## 少数亮笔画拉不动它。
func _sample_bg(img: Image, w: int, h: int) -> Color:
	var lumas := PackedFloat32Array()
	lumas.resize(w * h)
	var i := 0
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			lumas[i] = _luma(c)
			# 同时收一份"亮度接近中位数"的 RGB 平均，用来还原底色的色相
			sr += c.r
			sg += c.g
			sb += c.b
			i += 1
	var sorted := lumas.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	# 用"亮度接近中位数（±0.03）"的那些像素的 RGB 平均作为底色 ——
	# 这样底色是**真的底色像素**平均出来的，而不是全图平均（会被亮笔画污染）。
	var n := 0
	var ar := 0.0
	var ag := 0.0
	var ab := 0.0
	i = 0
	for y in h:
		for x in w:
			if absf(lumas[i] - median) <= 0.03:
				var c := img.get_pixel(x, y)
				ar += c.r
				ag += c.g
				ab += c.b
				n += 1
			i += 1
	if n == 0:
		return Color(sr / float(w * h), sg / float(w * h), sb / float(w * h), 1.0)
	return Color(ar / float(n), ag / float(n), ab / float(n), 1.0)


## 有内容的包围盒（alpha 超过 `CROP_ALPHA` 才算内容）。
func _content_box(img: Image, w: int, h: int) -> Rect2i:
	var minx := w
	var miny := h
	var maxx := -1
	var maxy := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a <= CROP_ALPHA:
				continue
			minx = mini(minx, x)
			miny = mini(miny, y)
			maxx = maxi(maxx, x)
			maxy = maxi(maxy, y)
	if maxx < 0:
		return Rect2i()
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)
