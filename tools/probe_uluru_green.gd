extends Node
## 艾尔斯岩「地表绿线」归因探针。
##
## ## 症状（用户截图）
## 夜里低空看出去，红土沙丘上有一条**细长的青绿斜线**横贯画面，像地面裂了一条缝。
##
## ## 本探针要证的三件事
##   ① 绿洲的**团心撒布半径** `DESERT_OASIS_R`（= `SPAWN_RADIUS × 1.16`，派生量）
##      与**覆盖图半宽** `DESERT_OASIS_SPAN / 2` 是否自洽 —— 不自洽的话
##      `_bake_veg_mask()` 里那两条 `maxi/mini` 会把图外的团**静默裁掉**；
##   ② 覆盖图**四条边缘**上有没有非零像素 —— 有，则 `veg_mask_tex` 的
##      `repeat_disable` 钳边会把那一列/行**沿世界轴拉成长条**
##      （shader 里 `muv = (world_pos.xz - origin) / span`，越界即钳到边缘值）；
##   ③ 出真机图：100 km 高空正俯视，直接看绿洲**实际铺开**的范围。
##
## ## 跑法（⚠️ **不能加 `--headless`**：headless 下 RenderingServer 是 dummy，出不了图）
##   Godot_v4.7.1-stable_win64_console.exe --path . res://tools/probe_uluru_green.tscn \
##       -- <输出目录>
##
## ## 为什么要单独一个探针
## `tools/capture.gd` 那套没有「100 km 正俯视」这个机位；而且本探针必须**同时**
## dump 出覆盖图 —— 那是唯一能直接看到「烤出来的绿洲范围」的东西，
## 光看渲染图分不清「绿洲少」与「绿洲被裁」。

const MAIN_SCENE := "res://scenes/main.tscn"
const SHOT_W := 1600
const SHOT_H := 900
## 「非零」的判据。与 shader 里 `if (mask > 0.004)` 同值 —— 低于它的像素
## 在 shader 那一支里**根本进不去**，所以它对"钳边会不会拉出绿条"没有贡献。
const MASK_EPS := 0.004

var _main: Node = null
var _out := "user://probe_uluru"


func _ready() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	print("[pg] 输出目录 = ", _out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await get_tree().process_frame
	await get_tree().process_frame

	var ps := load(MAIN_SCENE) as PackedScene
	if ps == null:
		push_error("[pg] 加载主场景失败")
		get_tree().quit(4)
		return
	_main = ps.instantiate()
	add_child(_main)
	for i in 3:
		await get_tree().process_frame

	_main._on_start_match(0, 0, MapDef.Id.ULURU, Game.MatchMode.VERSUS)
	# ⚠️ 建图是**协程**（`apply_map_staged` 里夹着 `await process_frame`）：
	# 不等逻辑帧就读 `desert_oasis_sites` / `_veg_mask_tex`，拿到的是**上一张图**的残留
	#（或者 null）。多等几帧的代价可以忽略，读到空数据的代价是整轮结论作废。
	for i in 20:
		await get_tree().process_frame

	if _main.world == null:
		push_error("[pg] world 为空 —— 没进 ULURU 图？")
		get_tree().quit(5)
		return

	_report()
	_dump_mask()
	await _shots()
	get_tree().quit(0)


# ------------------------------------------------------------ ① 口径

func _report() -> void:
	var wb: Node = _main.world
	var span: float = wb.DESERT_OASIS_SPAN
	var res: int = wb.DESERT_OASIS_RES
	var half := span * 0.5
	# 撒布半径是**派生量**，直接把表达式算出来对比 —— 改的人只改了 SPAWN_RADIUS
	# 而没改 SPAN 时，这一行就是账。
	var oasis_r: float = wb.SPAWN_RADIUS * 1.16
	print("[pg] ================= 口径 =================")
	print("[pg] SPAWN_RADIUS      = %.0f m" % wb.SPAWN_RADIUS)
	print("[pg] ARENA_RADIUS      = %.0f m" % wb.ARENA_RADIUS)
	print("[pg] DESERT_OASIS_R    = %.0f m（= SPAWN_RADIUS × 1.16，团心撒布半径）" % oasis_r)
	print("[pg] DESERT_OASIS_SPAN = %.0f m  ⇒ 覆盖图半宽 %.0f m" % [span, half])
	print("[pg] DESERT_OASIS_RES  = %d  ⇒ 格距 %.1f m" % [res, span / float(res)])
	var short_by := oasis_r - half
	print("[pg] >> 撒布半径 − 覆盖图半宽 = %+.0f m  %s"
		% [short_by, "⚠️ 图外有绿洲，会被静默裁掉" if short_by > 0.0 else "✓ 装得下"])

	# ---- 团/叶片：有多少落在覆盖图外 ----
	var sites: Array = wb.desert_oasis_sites
	var over := 0
	var rmax := 0.0
	for s: Vector4 in sites:
		var rr := Vector2(s.x, s.y).length()
		rmax = maxf(rmax, rr)
		if rr > half:
			over += 1
	var pct := 100.0 * float(over) / maxf(1.0, float(sites.size()))
	print("[pg] 团+叶片 %d 片，最远片心 %.0f m，落在覆盖图外的 %d 片（%.1f%%）"
		% [sites.size(), rmax, over, pct])

	# ---- 树：撒出来的树最远到哪 ----
	var tx: Array = wb.desert_tree_xf
	var trmax := 0.0
	for t: Transform3D in tx:
		trmax = maxf(trmax, Vector2(t.origin.x, t.origin.z).length())
	print("[pg] 树 %d 棵，最远树干 %.0f m，树密度缩放 %.4f"
		% [tx.size(), trmax, wb.desert_tree_scale])


# ------------------------------------------------------------ ② 覆盖图

func _dump_mask() -> void:
	var wb: Node = _main.world
	var tex: ImageTexture = wb._veg_mask_tex
	if tex == null:
		print("[pg] ⚠️ _veg_mask_tex 为空 —— 这张图没烘绿洲掩码")
		return
	var im := tex.get_image()
	var res := im.get_width()
	var src_fmt := im.get_format()
	im.convert(Image.FORMAT_RGB8)
	var p := _out.path_join("oasis_mask.png")
	im.save_png(p)
	print("[pg] 覆盖图 %d²（源格式 %d）已存 %s" % [res, src_fmt, p])

	# ---- 四边最大值：>MASK_EPS 就说明"钳边会拉出绿条" ----
	var e_l := 0.0
	var e_r := 0.0
	var e_t := 0.0
	var e_b := 0.0
	for i in res:
		e_l = maxf(e_l, im.get_pixel(0, i).r)
		e_r = maxf(e_r, im.get_pixel(res - 1, i).r)
		e_t = maxf(e_t, im.get_pixel(i, 0).r)
		e_b = maxf(e_b, im.get_pixel(i, res - 1).r)
	print("[pg] 四边最大值：左 %.3f / 右 %.3f / 上 %.3f / 下 %.3f（判据 > %.3f = 会钳出绿条）"
		% [e_l, e_r, e_t, e_b, MASK_EPS])
	print("[pg] >> 钳边风险：%s"
		% ("⚠️ 至少一条边非零 —— 图外会被拉成绿带"
			if maxf(maxf(e_l, e_r), maxf(e_t, e_b)) > MASK_EPS else "✓ 四边全零，钳边无害"))

	# ---- 最后一行/列的非零段：钳边会拉出几条、每条多宽 ----
	# 格距 = span/res ⇒ 段长（格）× 格距 = 绿条在世界里的宽度。
	# ⚠️ 宽度**不是**"这条绿带在画面里的宽"：钳边把它沿整个越界半平面拉长，
	# 所以宽度就是这几十公里长条在 **z（或 x）方向** 上的厚度。
	var cell: float = float(wb.DESERT_OASIS_SPAN) / float(res)
	_edge_runs(im, res, true, cell, "最后一列 u=1（世界 x=+half）")
	_edge_runs(im, res, false, cell, "最后一行 v=1（世界 z=+half）")
	_edge_runs(im, res, true, cell, "第一列 u=0（世界 x=-half）", 0)
	_edge_runs(im, res, false, cell, "第一行 v=0（世界 z=-half）", 0)

	# ---- 中心区 vs 全图均值：证明"绿洲是挤在中间的一小块，而不是铺满" ----
	var c_mean := _region_mean(im, int(res * 0.45), int(res * 0.55))
	var a_mean := _region_mean(im, 0, res)
	print("[pg] 覆盖图均值：中心 10%% 方块 %.4f / 全图 %.4f（中心/全图 = %.2f）"
		% [c_mean, a_mean, c_mean / maxf(1e-6, a_mean)])


func _edge_runs(im: Image, res: int, col: bool, cell: float, label: String, edge := -1) -> void:
	var idx := res - 1 if edge < 0 else edge
	var nz := 0
	var runs := 0
	var prev := false
	var widest := 0
	var cur := 0
	for i in res:
		var v: float = (im.get_pixel(idx, i) if col else im.get_pixel(i, idx)).r
		var on := v > MASK_EPS
		if on:
			nz += 1
			cur += 1
			widest = maxi(widest, cur)
		else:
			cur = 0
		if on and not prev:
			runs += 1
		prev = on
	print("[pg] %s：非零 %d/%d 格（%.1f%%），连续段 %d 段，最长 %d 格 ≈ %.0f m"
		% [label, nz, res, 100.0 * float(nz) / res, runs, widest, float(widest) * cell])


func _region_mean(im: Image, x0: int, x1: int) -> float:
	var acc := 0.0
	var n := 0
	for y in range(x0, x1):
		for x in range(x0, x1):
			acc += im.get_pixel(x, y).r
			n += 1
	return acc / maxf(1.0, float(n))


# ------------------------------------------------------------ ③ 出图

func _shots() -> void:
	# ---- 冻结：停逻辑、藏 HUD、相机脱靶（照抄 pixprobe 的做法）----
	get_tree().paused = true
	if _main.canvas != null:
		_main.canvas.visible = false
	# ⚠️ **云必须藏掉**：低空云带在 3~8 km，而本探针有两张机位在 30~60 km 高空，
	# 视线**从上往下穿过云层** ⇒ 地面被云糊住（第一版 `a_top100km` 全黑之后，
	# 第二版 `a_top60km` 拍到的全是云团，绿洲一个都看不见 ——
	# 而日志、断言、图都在，只有"结论"是错的）。
	# 低空那几张本来就在云底下，藏了不影响。
	var wbx: Node = _main.world
	if wbx != null:
		var cr: Node = wbx.get("_cloud_root")
		if cr is Node3D:
			(cr as Node3D).visible = false
	var chase: Camera3D = _main.chase
	if chase == null:
		print("[pg] ⚠️ 没有 chase 相机")
		return
	chase.set_target(null)
	chase.set_physics_process(false)
	chase.set_process(false)
	chase.fov = 62.0

	var span: float = _main.world.DESERT_OASIS_SPAN
	var half := span * 0.5
	print("[pg] ================= 出图 =================")

	# ① 60 km 正俯视：垂直覆盖 ±36 km —— 恰好把**覆盖图边界（±half = ±26 km）**
	#    和它外侧那 10 km 的"钳边区"一起框进来。
	#    ⚠️ 用**欧拉角**而不是 `look_at`：正下方看时视线与 up 共线，`look_at` 会翻转。
	#    `Basis.from_euler(Vector3(-PI/2, 0, 0))` 把 -Z 转到正下方，屏幕上方 = 世界 -Z、
	#    屏幕右方 = 世界 +X —— 后面两张图的"哪边是 +X"就靠这条。
	_aim(Vector3(0.0, 60000.0, 0.0), Vector3(-PI * 0.5, 0.0, 0.0))
	await _shot("a_top60km")

	# ② 覆盖图边界特写：站在 x=+half 的正上方 20 km。
	#    画面中心就是"覆盖图右边界"那一列；右半边（x>half）是**钳边区**。
	_aim(Vector3(half, 20000.0, 0.0), Vector3(-PI * 0.5, 0.0, 0.0))
	await _shot("b_edge_top")

	# ③ 低空平视：复现用户视角。站在 20 km 处朝 +X 平视，
	#    pitch 0.05 rad ⇒ 视线与地面交点在 ≈ 30 km（正好跨过 half）。
	_aim(Vector3(20000.0, 1500.0, 0.0), Vector3(-0.05, -PI * 0.5, 0.0))
	await _shot("c_low_flat")

	# ---- ④⑤⑥⑦ 正对"钳边绿条"----
	#
	# ⚠️ 机位不是随便挑的，是**从 dump 出来的覆盖图上量出来的**。改前 SPAN = 52 km
	# ⇒ 覆盖图 2048²、25.4 m/px。四条边的非零段与最大灰度（与 `_dump_mask()` 同一取边方式）：
	#
	#   | 探针口径 | 世界位置        | 段 | 最长段             | 最大灰度 |
	#   |---|---|---|---|---|
	#   | 上（行 0）   | z = **−26 km** | 2 | **57 格 ≈ 1447 m** | **0.820** ← 最强 |
	#   | 右（列末）   | x = **+26 km** | 2 | 11 格 ≈ 279 m      | **0.682** |
	#   | 下（行末）   | z = **+26 km** | 1 | 12 格 ≈ 305 m      | **0.271** ← 最淡 |
	#   | 左（列 0）   | x = −26 km     | 0 | —                  | **0.000** |
	#
	# ⚠️⚠️ **本注释的上一版把"行末/行首"与 z 的符号配反了**（写成"行末 = z+26 km 最大 209/255"），
	# 于是 ④⑤ 的机位被摆到了 **z = +26 km 那条最淡的**（0.271）上头。
	# 后果的**形状**值得记：`cov = mask×1.18 − 0.06`，0.271 ⇒ cov = 0.259，
	# 最终 `mix(base, VEG_COLOR, cov×0.72)` **只往红土里混进 14% 的绿** ——
	# 带子**拍到了**（实测 B 通道 3~7、两侧红土恒为 0），但只是**一条淡带**，
	# 而用户截图那条是**明显看得见的**。也就是说：判据全绿、图也出了，
	# 只是**拍的不是用户看的那一条** —— 又一个"探针没骗人、注释在骗人"。
	#
	# ⚠️ 数值来源要说清：`_report` 打印的"四边最大值：左 0.000 / 右 0.682 / 上 0.820 / 下 0.271"
	# 是**对的**。我曾用 `PIL.Image.convert("L")` 去复量，被 PIL 的亮度权重 **0.299**
	# 整体压掉（0.243/0.299 = 0.812 ≈ 0.820、0.204/0.299 = 0.682、0.082/0.299 = 0.274 ≈ 0.271，
	# 三项全对），一度误判"日志是错的"。→ 量单通道灰度图要 `convert("RGB")` 后取 R 通道。
	#
	# ④ 低空平视：正对 **z = +26 km**（0.271，淡）那条 —— 相机在 x = 11 640（= 该段 x∈[11 489, 11 769] 正中），
	#    朝 +Z 看，pitch 0.05 rad ⇒ 视线落地在 24 km 外，落在 z > 26 km 的钳边半平面里。
	_aim(Vector3(11640.0, 1200.0, 20000.0), Vector3(-0.05, PI, 0.0))
	await _shot("d_line_low")
	# ⑤ 同一条带的高空俯视：绿条沿世界 Z 延伸 ⇒ 俯视图里是一条**贯穿画面的竖线**
	#    （俯视时屏幕竖直方向 = 世界 Z）。它"从头到尾一个样"这一点，
	#    就是"绿洲团"与"钳边条带"最硬的区别 —— 绿洲绝不会贯穿整屏。
	_aim(Vector3(11640.0, 30000.0, 45000.0), Vector3(-PI * 0.5, 0.0, 0.0))
	await _shot("e_line_top")
	# ⑥ 低空平视：正对 **z = −26 km（0.820，最强）** 那条 —— 相机在 x = 5 548
	#    （= 最长那一段 x∈[4 837, 6 259] 的中点），朝 **−Z** 看（yaw = 0）。
	#    cov = 0.820×1.18 − 0.06 = 0.908 ⇒ 混进 49% 的绿 ⇒ **这条才该是用户截图里那条明显可见的线**。
	_aim(Vector3(5548.0, 1200.0, -20000.0), Vector3(-0.05, 0.0, 0.0))
	await _shot("f_strong_low")
	# ⑦ 同一条带的高空俯视（对照 ⑤）：俯视图里应是一条**贯穿画面**的竖线。
	_aim(Vector3(5548.0, 30000.0, -45000.0), Vector3(-PI * 0.5, 0.0, 0.0))
	await _shot("g_strong_top")


func _aim(pos: Vector3, euler: Vector3) -> void:
	var chase: Camera3D = _main.chase
	chase.global_position = pos
	chase.global_transform.basis = Basis.from_euler(euler)
	# ⚠️ **远裁剪面必须自己抬**：`Camera3D` 默认 `far = 4000`，
	# 而本探针的机位在 20~60 km 高空 ⇒ 地面整个落在裁剪面之外、
	# 拍出来是**一片纯背景色**（第一版 100 km 俯视就是全黑，
	# 而日志里没有任何报错 —— 会被读成"夜里地面本来就是黑的"）。
	chase.far = 1500000.0
	chase.near = 1.0
	chase.current = true


func _shot(name: String) -> void:
	# 空转几帧把管线烘热（paused 不影响 `frame_post_draw`）。
	for i in 8:
		await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		print("[pg] ⚠️ 取不到视口纹理：", name)
		return
	var img := tex.get_image()
	if img == null:
		print("[pg] ⚠️ 取不到画面：", name)
		return
	img.convert(Image.FORMAT_RGB8)
	var p := _out.path_join(name + ".png")
	img.save_png(p)
	print("[pg] shot %s -> %s" % [name, p])
