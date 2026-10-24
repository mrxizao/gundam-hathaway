extends Control
## 轮 61 探针：读条层「露出屏幕下的一部分」的尺寸证据（**排查期建的，落地后仍可复跑**）。
##
## ⚠️ **只读 + 对照**，不改任何产品代码：
##   ① 按**产品原样**造一个 `LoadingScreen` ⇒ 量 size / offsets / parent_area，截图，
##      并**像素扫描**出背景矩形的实际底边；
##   ② **另**造一个实例，在探针里手动补一次 `set_anchors_and_offsets_preset`
##      ⇒ 量同样的数、同样扫描（这是「写法正确时该长什么样」的对照，**不是修复动作**）。
##
## ⚠️⚠️ 产品已于 2026-10-01（轮 61）**修好** ⇒ 现在 ① 与 ② 的读数应当**完全相同**。
##   所以本探针不再预判「① 一定是坏的」，而是在结论里打一行 **判定**：
##     `判定：产品状态 = FIXED（铺满视口）` / `= BUGGY（size 为 0 ⇒ 会露底）`。
##   复跑先看那一行 —— `01_buggy_current.png` 这个**文件名**是排查期留下的，别被它误导。
##
## 判据（两种状态各自长什么样）：
##   修复前：① `size == (0,0)`，背景底边 ≈ 900×1.6 渲染 px ⇒ 底部露出 ~100 逻辑 px；
##   修复后：① `size == 视口尺寸`，背景铺到最底（与 ② 一致，只剩抗锯齿那 ~0.6 px）。
##
## 用法（**不能加 `--headless`**：dummy 渲染器截不出像素）：
##   Godot_v4.7.1-stable_win64_console.exe --path <工程> res://tools/_r61_loading_probe.tscn -- <输出目录>

## 每档多等几帧（沿用 `menu_shot.gd` 的 40：渲染历史要几十帧才收敛）。
const SETTLE := 40
## ⚠️ **修复前**产品 `_draw()` 里那条兜底（1600×900）。产品在轮 61 已经删掉它、
## 改成退回父级区域 ⇒ 这里只作为**历史参考**留着，用来把「当时的预期露出量」算给日志看。
const FALLBACK := Vector2(1600, 900)

var _out := ""
var _buggy_size := Vector2.ZERO
var _fixed_size := Vector2.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://r61_loading_probe"
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()
	printerr("[r61] DONE")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 截当前视口。⚠️ 必须等 `frame_post_draw`：早一帧拿到的还是上一帧的画布。
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png("%s/%s.png" % [_out, name])
	printerr("[r61] shot %-22s %dx%d err=%d" % [name, img.get_width(), img.get_height(), err])


## 量一个 Control 的布局四项。
func _report(tag: String, c: Control) -> void:
	var pa: Vector2 = c.get_parent_area_size()
	printerr("[r61] %-11s size=%s offsets=(%.1f, %.1f, %.1f, %.1f) parent_area=%s" % [
		tag, str(c.size), c.offset_left, c.offset_top, c.offset_right, c.offset_bottom, str(pa)])


## 像素扫描：返回**背景矩形的底边**（渲染坐标 y）。
##
## 取样列取 1/4 宽处 —— 读条 `_draw()` 只画「背景 + 居中标题 + 居中阶段文字 + 居中进度条」，
## 全部落在中间，1/4 宽处那列是**纯背景**（否则标题/进度条会把"最后一行背景色"截断）。
func _bg_bottom(name: String) -> int:
	var p := "%s/%s.png" % [_out, name]
	var img := Image.load_from_file(p)
	if img == null:
		printerr("[r61] 读图失败 %s" % p)
		return -1
	var w := img.get_width()
	var h := img.get_height()
	var x := int(w / 4)
	var ref := img.get_pixel(x, 2)  # 第 2 行必定是背景（读条从 y=0 铺）
	var last := -1
	for y in h:
		var c := img.get_pixel(x, y)
		if absf(c.r - ref.r) < 0.04 and absf(c.g - ref.g) < 0.04 and absf(c.b - ref.b) < 0.04:
			last = y
	return last


func _run() -> void:
	var vp := get_viewport()
	var vis: Rect2 = vp.get_visible_rect()
	printerr("[r61] viewport visible_rect = %s  window = %s" % [
		str(vis.size), str(DisplayServer.window_get_size())])
	printerr("[r61] 修复前产品兜底 FALLBACK（历史参考）= %s" % str(FALLBACK))
	printerr("[r61] 修复前预期：兜底高 %.0f vs 视口高 %.0f ⇒ 底部露出 %.0f 逻辑 px" % [
		FALLBACK.y, vis.size.y, vis.size.y - FALLBACK.y])

	# ============================================================ ① 现状
	printerr("[r61] ===== ① 产品原样（product as-is）=====")
	var buggy := LoadingScreen.new()
	buggy.name = "BuggyLoading"
	add_child(buggy)
	await _frames(4)
	_report("PRODUCT", buggy)
	_buggy_size = buggy.size
	buggy.open("太平洋群岛 · 夜")
	buggy.advance(0.55, "重塑地表……")
	await _frames(SETTLE)
	await _shot("01_buggy_current")
	buggy.queue_free()
	await _frames(4)
	var b_bottom := _bg_bottom("01_buggy_current")
	printerr("[r61] ① 产品原样 背景底边(渲染 px) = %d  ⇒ 逻辑高 ≈ %.1f" % [
		b_bottom, float(b_bottom) / 1.6])

	# ============================================================ ② 对照
	printerr("[r61] ===== ② 对照：探针内补一次正确写法（只动探针实例，产品不动）=====")
	var fixed := LoadingScreen.new()
	fixed.name = "FixedLoading"
	add_child(fixed)
	await _frames(4)
	_report("BEFORE-FIX", fixed)
	fixed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames(4)
	_report("AFTER-FIX", fixed)
	_fixed_size = fixed.size
	fixed.open("太平洋群岛 · 夜")
	fixed.advance(0.55, "重塑地表……")
	await _frames(SETTLE)
	await _shot("02_fixed_control")
	fixed.queue_free()
	await _frames(4)
	var f_bottom := _bg_bottom("02_fixed_control")
	printerr("[r61] ② 写法对照 背景底边(渲染 px) = %d  ⇒ 逻辑高 ≈ %.1f" % [
		f_bottom, float(f_bottom) / 1.6])

	# ============================================================ 结论
	printerr("[r61] ===== 结论 =====")
	printerr("[r61] ① 产品原样 size=%s  背景逻辑高≈%.1f  视口高=%.1f  ⇒ 底部露出 ≈%.1f px" % [
		str(_buggy_size), float(b_bottom) / 1.6, vis.size.y, vis.size.y - float(b_bottom) / 1.6])
	printerr("[r61] ② 写法对照 size=%s  背景逻辑高≈%.1f  ⇒ 底部露出 ≈%.1f px" % [
		str(_fixed_size), float(f_bottom) / 1.6, vis.size.y - float(f_bottom) / 1.6])
	# ---- 判定：看 ① 的 size，别被「01_buggy_current」这个文件名误导 ----
	# （用 `+` 拼串，不走 `%` 格式化：格式串里紧跟中文全角括号有前科。）
	var laid_out: bool = _buggy_size.x > 0.0 and _buggy_size.y > 0.0
	var verdict := "FIXED（铺满视口）" if laid_out else "BUGGY（size 为 0 ⇒ 会露底）"
	printerr("[r61] 判定：产品状态 = " + verdict
		+ "  ；① size = " + str(_buggy_size) + "  视口 = " + str(vis.size))
