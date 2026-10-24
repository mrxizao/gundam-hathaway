extends Node
## 判据图：**近地轨道的地球**（2026-09-29 · 老板三条需求的像素证据）。
##
## 跑法（**不能加 `--headless`**：headless 是 dummy 渲染器，抓出来是空的）：
##   godot --path <工程> res://tools/leo_earth_shot.tscn -- <输出目录>
##
## ## 老板的三句话，各自落在哪
## | # | 原话 | 证据 |
## |---|---|---|
## | ① | 「**要能分辨出脚底下是地球**」 | ★ `look_down_earth`：中心区的**分布宽度** / 海·陆·云三种色相 / 四条边中点块**都有**地表纹理 |
## | ② | 「近地轨道高度应该和现实高度一致」 | `suite_space_map` 的数值断言 ＋ `limb_curve`（临边落在 **23.0° 下沉角**上 —— 这个角只由 R 与 h 决定）＋ `look_down_wide`（剪影半径 = `asin(R/(R+h))`） |
## | ③ | 「没有撞地，超出就强制回到近地轨道上」 | `suite_space_map::_orbit_floor` 的行为断言 ＋ `_floor_demo()` |
##
## ## ⚠️ 为什么必须有**像素**判据，而不是"看节点在不在"
## 判决"地球存在"最省事的做法是 `find_child("Earth") != null` —— 它证明不了任何事：
##   · 相机远裁面还停在 90 km ⇒ 地球被裁掉，画面与改前**逐像素一样**；
##   · 球心建在 `y = 0`（而不是 −R）⇒ 表面跑到 6 371 km 之外 ⇒ 同样看不见；
##   · 着色器编译失败 ⇒ 节点在、网格在，画出来是一团洋红。
## 这三种**一个都不报错**。所以判据一律落在**帧缓冲**上。
##
## ## ⚠️ 改前那张图长什么样（这是判据的锚）
## `tools/_b2_leo_shots.gd` 的 04 号机位（正下方 90°）读数：
##   `mean 0.14989 / p50 0.14930 / p99 0.15210` ⇒ **分布宽度只有 0.0028**
## 那是一整块**没有任何细节的均匀深蓝**（`sky.gdshader` 把它的"假地面色"画在地平线以下）。
## 「认不出是地球」在那张图上不是形容词，就是这个数。
##
## ## ★ 两个几何量，我第一版算错过（记下来，别再踩）
## 从高度 h 看半径 R 的球：
##   · **可见盘的半角**（相对正下方）= `asin(R/(R+h))` —— 本图 = **67.0°**；
##   · **地平线下沉角** = `90° − 盘半角` = `acos(R/(R+h))` —— 本图 = **23.0°**。
## 这两个数**互为余角**，第一版把 `acos` 的结果当成"盘半角"，于是
## "fov 60 的画面里能不能看见临边"整个判断反过来 —— 真实情况是**看不见**：
## 画面四角只到 **49.1°** < 盘半角 67.0° ⇒ 正下方的画面里**全是地球、一点太空都没有**。
## （而 `limb_curve` 那个机位的视线是**水平**的，临边在它下方 23.0° 处 ⇒ 收得进画面。）

var out_dir := "user://leo_earth"
var _idx := 0
var _world: WorldBuilder
var _pass := 0
var _fail := 0
var _all_ok := true
## 直下点：`(0, SPACE_ORBIT_ALT, 0)` —— 它离球心的距离恰好 = `PHYS_R + PHYS_H`，
## 所以这个机位上的所有角量**严格**等于几何公式算出来的值。
var _base := Vector3.ZERO
## 出击环上的一个点（碎片带 / 残骸 / 卫星都在那一圈上 —— 它们是"读得出我在动"的来源）。
var _ring := Vector3.ZERO

# ------------------------------------------------------------- 常量

## 判据机位用**透视**（不用正交）：
## `Camera3D.fov` 是**垂直**角，且默认 `keep_aspect = KEEP_HEIGHT`。
const FOV_NARROW := 60.0
## "低头看整颗球"那一档要**宽**fov：盘半角 67° 要收进画面，
## 垂直半角必须 > 67° ⇒ fov > 134°（见 `look_down_wide()` 的说明）。
const FOV_WIDE := 150.0
const SHOT_W := 1600
const SHOT_H := 900

## ★ **现实口径**（写死，不从工程常量里取）。
##
## 这两个数是老板需求 ②「高度和现实一致」的**判据基准**。若改成从
## `WorldBuilder.SPACE_ORBIT_ALT` 读，那么把它改成 3 200 m（B2 那版的口径）之后
## **预测值会跟着改**，判据就变成**自证**（两者一起动、永远相符）。
## `suite_space_map` 另外钉着"工程常量必须等于这两个数"。
const PHYS_R := 6371000.0
const PHYS_H := 550000.0

## 中心区取中央 40% × 40%。
const CORE_FRAC := 0.40
## 判据 ②：中心区亮度**分布宽度**下限。改前实测 0.0028 ⇒ 取 0.02 是 7 倍余量。
const SPREAD_MIN := 0.02
## 判据 ③④⑤：海 / 陆 / 云 的像素占比下限。
const OCEAN_FRAC_MIN := 0.08
const LAND_FRAC_MIN := 0.03
const CLOUD_FRAC_MIN := 0.02
## 判据 ①：抬头（真空 + 星空）的全帧均亮上限。
const SKY_MEAN_MAX := 0.06
## 判据 ⑬⑭⑮：临边环的检出余量与容差。
##
## `RING_MARGIN` 的两条边界是**实测量级**（不是随手取的）：
##   · **下界**：地平线以下那片"亮雾"的峰值亮度 ≈ 0.16（`TimeOfDay.space()` 的
##     `sky_ground` 混到 80%，而 `ground_blend = 0.55` 让它正好在临边处最亮）；
##   · **上界**：临边环（`earth.gdshader` 的加法项，恒在剪影上，`glow` 还会给它一圈晕）≈ 0.79。
## 取 0.35 落在两者之间 ⇒ 既不会误检到雾，也不会漏掉环。
##
## ⚠️ 但**光有余量不够**：星空里一颗被 `glow` 晕开的亮星也会越过这个阈值。
## 第一版就是这么翻的 —— `x = +300` 那条竖线找到"行 370"（天空里的星光晕），
## 而真临边在行 804。所以另加一条 `_inside_is_bright()`：
## 候选点的**内侧必须是一大片亮的**（星光辉光的内侧马上又回到真空）。
const RING_MARGIN := 0.35
const ROW_TOL := 0.12
const RADIUS_TOL := 0.15
## 判据 ⑭：临边**弯曲**的下限（像素）。平面世界的地平线是一条**直线** ⇒ sagitta ≈ 0。
const SAGITTA_MIN := 40.0
## 判据 ㉑：**三类均衡度**（归一化熵 `H / ln3` ∈ [0, 1]）的下限。
##
## 实测（真机 1600×900，判定机位 = 正下方 fov 60）：
## | 状态 | 海 / 陆 / 云 | 熵 | 判 |
## |---|---|---|---|
## | **改后**（噪声频率 = 可见张角的 6.25×） | 38.4% / 17.5% / 44.1% | **0.941** | PASS |
## | **改前**（`earth.gdshader` 逐字节回退 · 负对照 N1） | 5.4% / 94.1% / 0.3% | **0.210** | FAIL |
## | 纯天空（far = 90 km） | 100% / 0 / 0 | **0.000** | FAIL |
##
## ⇒ 阈值取两个实测量的**几何中点**：`sqrt(0.210 × 0.941) = 0.444` ⇒ **0.44**，
## 两边余量对称（改后 2.14× / 改前 2.10×）。
## ⚠️ 我第一版随手取了 0.35 —— 那是**还没有负对照时拍的**，事后一量只剩 1.7× 余量。
## **阈值必须在负对照跑完之后定**，这条这次是真金白银买来的。
##
## ⚠️ 熵**天然归一化**（不用拍量纲），这也正是它比"尺度"类指标可靠的地方 —— 见 `_look_down()` 里
## 那三个失败候选的证伪记录。
const BALANCE_ENTROPY_MIN := 0.44
## 判据 ㉑ 附带的**诊断读数**（只打印、不判）用的低通窗口 = 画宽 / 这个数（≈ 100 px @ 1600 宽）。
const SCALE_WIN_DIV := 16.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	# ⚠️ 窗口模式与尺寸**都要设** —— 只设尺寸的话，玩家设置里是"全屏"时窗口仍全屏，
	# 于是"1600×900 的判据图"实际是屏幕原生分辨率，而日志里一个警告都没有。
	#（`tools/_b2_leo_shots.gd` 与 `tests/pixprobe.gd` 都记过这个坑。）
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_world = WorldBuilder.new()
	add_child(_world)
	await get_tree().physics_frame
	_world.apply_map(MapDef.leo())
	await _frames(20)

	var ra := deg_to_rad(-95.0)
	_ring = Vector3(cos(ra) * WorldBuilder.SPAWN_RADIUS, WorldBuilder.SPACE_ORBIT_ALT,
		sin(ra) * WorldBuilder.SPAWN_RADIUS)
	_base = Vector3(0.0, WorldBuilder.SPACE_ORBIT_ALT, 0.0)

	var m: MapDef = _world.get("map")
	print("[earth] 地图 = %s   orbit_alt = %.0f m   body_radius = %.0f m   reentry_alt = %.0f m"
		% [m.code, m.orbit_alt, m.body_radius, m.reentry_alt])
	var terrain: Node = _world.get("_terrain_root")
	var earth := terrain.find_child("Earth", true, false)
	print("[earth] `_terrain_root` 下 %d 个子节点；Earth = %s"
		% [terrain.get_child_count(), "有" if earth != null else "**没有**"])
	if earth is MeshInstance3D:
		var mi := earth as MeshInstance3D
		var sph: SphereMesh = mi.mesh
		print("[earth]   Earth: 半径 %.0f m   球心 y = %.0f m   分段 %d×%d   投影 = %s"
			% [sph.radius, mi.position.y, sph.radial_segments, sph.rings, str(mi.cast_shadow)])
		print("[earth]   ⇒ 球顶 y = %.0f m（应当 = 0：与五张图的「y=0 是地表」同构）"
			% (mi.position.y + sph.radius))

	# ---- 几何账 ------------------------------------------------------------------
	var disc := rad_to_deg(asin(PHYS_R / (PHYS_R + PHYS_H)))
	var dip := 90.0 - disc
	print("[earth] 从 %.0f km 高看 R = %.0f km 的球（现实口径）："
		% [PHYS_H / 1000.0, PHYS_R / 1000.0])
	print("        可见盘半角（相对正下方）= asin(R/(R+h)) = **%.2f°**" % disc)
	print("        地平线下沉角 = 90° − 盘半角 = acos(R/(R+h)) = **%.2f°**" % dip)
	print("        剪影斜距 = sqrt(2Rh + h²) = **%.0f km**"
		% (sqrt(2.0 * PHYS_R * PHYS_H + PHYS_H * PHYS_H) / 1000.0))
	var corner := rad_to_deg(atan(sqrt(_tan2(FOV_NARROW * 0.5) * (1.0 + _aspect2()))))
	print("        fov %.0f（垂直）⇒ 画面**四角**离轴 %.1f° < 盘半角 %.1f° ⇒ **地球把画面填满**"
		% [FOV_NARROW, corner, disc])
	print("        ⇒ 正下方机位里应当**一块太空都没有**（判据 ⑥ 就是把这句话变成像素读数）")

	var cam := Camera3D.new()
	cam.near = 1.0
	add_child(cam)
	cam.current = true

	# ---- 机位（前两个保留配角，后四个隐藏它们 —— 见 `_hide_props()`）----
	cam.fov = FOV_NARROW
	cam.far = ChaseCamera.ORBIT_FAR
	await _level(cam)
	await _look_up(cam)

	_hide_props()
	var s_new := await _look_down(cam, ChaseCamera.ORBIT_FAR, "look_down_earth", true)
	var s_old := await _look_down(cam, 90000.0, "look_down_far90_OLD", false)
	if s_new.size() > 0 and s_old.size() > 0:
		print("\n---- ★ A/B：相机远裁面（证明「far 不提上去 = 这一轮白做」）----")
		print("      far = %.0f km（新的）⇒ 中心区分布宽度 **%.4f**"
			% [ChaseCamera.ORBIT_FAR / 1000.0, s_new["spread"]])
		print("      far = %.0f km（旧的）⇒ 中心区分布宽度 **%.4f**"
			% [90.0, s_old["spread"]])
		# ---- ★ ⑥：这一组里唯一能挡住"**地球是一颗小球、四周还是太空**"的判据 ----
		#
		# 那种画面里中心区一切正常（宽度够、有海有陆），但四条**边中点**是光滑的天。
		# 所以这里不比绝对阈值，而是拿**同一次运行里那张纯天空的图**（far = 90 km）
		# 当基准：要求真图的每一块边中点，纹理至少是它的 3 倍。
		# ⚠️ 绝对阈值不好定（第一版取 0.02，实测一块**风平浪静的洋面**只有 0.0196 —— 差 2%），
		# 而"同一张图里的天空"是个随曝光/时段自动跟着走的基准。
		var bmn := 9.9
		for v in s_new["blocks"]:
			bmn = minf(bmn, float(v))
		var bmx := 0.0
		for v in s_old["blocks"]:
			bmx = maxf(bmx, float(v))
		print("      四边中点块的分布宽度：新图最小 %.4f   vs   旧图（纯天空）最大 %.4f   ⇒ %.1f×"
			% [bmn, bmx, bmn / maxf(bmx, 1.0e-6)])
		_judge("⑥ **四条边中点块都有地表纹理**（最小 %.4f > 3 × %.4f = %.4f ⇒ 地球把画面填满、四周没有太空）"
			% [bmn, bmx, 3.0 * bmx], bmn > 3.0 * bmx)
		_judge("⑦ 旧 far 下地球**整体看不见**（宽度 %.4f < %.2f —— 与改前那块纯色同级）"
			% [s_old["spread"], SPREAD_MIN], s_old["spread"] < SPREAD_MIN)
		_judge("⑧ 旧 far 下**认不出陆**（陆地色相 %.2f%% < %.1f%%）—— 与 ④ 同一把尺子"
			% [100.0 * s_old["land"], 100.0 * LAND_FRAC_MIN], s_old["land"] < LAND_FRAC_MIN)
		_judge("⑨ 新 far 比旧 far 有内容（%.4f vs %.4f，%.0f×）"
			% [s_new["spread"], s_old["spread"],
				s_new["spread"] / maxf(s_old["spread"], 1.0e-6)],
			s_new["spread"] > s_old["spread"] * 3.0)

	await _look_down_wide(cam)
	await _limb_curve(cam)
	await _floor_demo()

	print("\n================ 判决（地球）================")
	print("  %d PASS / %d FAIL" % [_pass, _fail])
	print("  LEO_EARTH_ALL_OK = %s" % ("true" if _all_ok else "false"))
	print("LEO_EARTH_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0 if _all_ok else 1)


# ------------------------------------------------------------- 机位 1 / 2


## 机位 1：出击环上**沿切向平飞**（与 `tools/_b2_leo_shots.gd` 的 01 号同一条视向）。
## 只作交付用的构图图，不落判据（配角的可见性不在这三条需求里）。
func _level(cam: Camera3D) -> void:
	var ra := deg_to_rad(-95.0)
	var tanv := Vector3(-sin(ra), 0.0, cos(ra))
	await _look(cam, _ring, _ring + tanv * 20000.0, "level_orbit_550")


## 机位 2：抬头 90° —— 真空黑 + 星空（**"向下看那张"的阴性对照**）。
##
## ⚠️ 不用 `look_at(from + UP)`：那与 `up = UP` 共线，朝向退化成未定义
##（`godot-headless-probe-shots` 记过这一类静默失败）。直接写 `rotation_degrees`。
func _look_up(cam: Camera3D) -> void:
	cam.global_position = _ring
	cam.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	await _frames(10)
	var img := await _shot(cam, "look_up_stars", "抬头 90°（天顶真空）")
	if img == null:
		return
	var st := _stats(img, Rect2i(0, 0, img.get_width(), img.get_height()))
	print("      [全帧] mean %.4f  p50 %.4f  p99 %.4f"
		% [st["mean"], st["p50"], st["p99"]])
	_judge("① 抬头是**真空**（全帧均亮 %.4f < %.2f）—— 与低头那张互为阴性对照"
		% [st["mean"], SKY_MEAN_MAX], st["mean"] < SKY_MEAN_MAX)


# ------------------------------------------------------------- 机位 3：脚底下的地球


## ★ 低头 90°（正下方）—— **脚底下那颗地球**，也是需求 ① 的正面证据。
##
## ## 判据（五条，全落在像素上；取样区 = **整帧**）
## | # | 判据 | 改前的读数 |
## |---|---|---|
## | ② | 整帧亮度**分布宽度** > 0.02 | **0.0028** ⇒ 红 |
## | ③ | 整帧**陆地色相**占比 > 3% | 0% ⇒ 红（只有一种蓝） |
## | ④ | 整帧**海洋色相**占比 > 8% | 0%（那块蓝是天空的"假地面色"，不算) ⇒ 红 |
## | ⑤ | 整帧**云**（低饱和亮部）占比 > 2% | 0% ⇒ 红 |
## | ⑳ | **没有笔直的子午线接缝**（见函数末） | 77× ⇒ 红 |
##
## ⑥（"地球把画面填满"）不在这里断 —— 它要跟**同一次运行里那张纯天空的图**比，见 A/B 段。
func _look_down(cam: Camera3D, far: float, shot_name: String, judge: bool) -> Dictionary:
	cam.fov = FOV_NARROW
	cam.far = far
	cam.global_position = _base
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	await _frames(10)
	var img := await _shot(cam, shot_name,
		"低头 90°（正下方）  far = %.0f km" % (far / 1000.0))
	if img == null:
		return {}

	# ---- 读数的**取样区**：整帧 ----
	#
	# ⚠️ 第一版取"中央 40%" —— 那是个**没有依据**的框：本机位的画面**整幅都是地球**
	#（见判据 ⑥：四条边的中点块也全是地表），而"中央 40%"只覆盖 44°×26° 的一小块，
	# 一块刚好落在洋面上的话，陆地占比就会读成 0%（实测就是 0.0%，而画面左上角明明有陆地）。
	# "认得出是地球"这件事的对象是**整个画面**，所以判据一律落在整帧上；
	# 中心区仍打印出来当参考（它反映的是正下方那一小片）。
	var full := _stats(img, Rect2i(0, 0, img.get_width(), img.get_height()))
	var core := _stats(img, _core_rect(img))
	var spread: float = full["p99"] - full["p05"]
	print("      [整帧] mean %.4f  p05 %.4f  p50 %.4f  p99 %.4f  **宽度 %.4f**"
		% [full["mean"], full["p05"], full["p50"], full["p99"], spread])
	print("      [整帧色相] 海洋 %.1f%%  陆地 %.1f%%  云 %.1f%%  其它 %.1f%%"
		% [100.0 * full["ocean"], 100.0 * full["land"], 100.0 * full["cloud"],
			100.0 * (1.0 - full["ocean"] - full["land"] - full["cloud"])])
	print("      [中心区 40%% 参考] 宽度 %.4f  海洋 %.1f%%  陆地 %.1f%%  云 %.1f%%"
		% [core["p99"] - core["p05"], 100.0 * core["ocean"], 100.0 * core["land"],
			100.0 * core["cloud"]])
	var blocks := _edge_blocks(img)
	var bsp: Array[float] = []
	for r in blocks:
		var b := _stats(img, r)
		bsp.append(float(b["p99"]) - float(b["p05"]))
	print("      [四边中点块的分布宽度] 上 %.4f  下 %.4f  左 %.4f  右 %.4f"
		% [bsp[0], bsp[1], bsp[2], bsp[3]])

	var out := {"spread": spread, "ocean": full["ocean"], "land": full["land"],
		"cloud": full["cloud"], "mean": full["mean"], "blocks": bsp}
	if not judge:
		return out

	print("      ---- 判据 ----")
	_judge("② 整帧亮度分布宽度 %.4f > %.2f（画面里有东西，不是一块纯色）"
		% [spread, SPREAD_MIN], spread > SPREAD_MIN)
	_judge("③ 陆地色相（整帧）%.1f%% > %.1f%%（认得出**陆**）"
		% [100.0 * full["land"], 100.0 * LAND_FRAC_MIN], full["land"] > LAND_FRAC_MIN)
	_judge("④ 海洋色相（整帧）%.1f%% > %.1f%%（认得出**海**）"
		% [100.0 * full["ocean"], 100.0 * OCEAN_FRAC_MIN], full["ocean"] > OCEAN_FRAC_MIN)
	_judge("⑤ 云（整帧 · 低饱和亮部）%.1f%% > %.1f%%（那一层白是「从轨道上一眼认出行星」最有效的特征）"
		% [100.0 * full["cloud"], 100.0 * CLOUD_FRAC_MIN], full["cloud"] > CLOUD_FRAC_MIN)
	# ---- ★ ⑳ 接缝判据（本轮新钉的一条"静默缺陷"）----
	#
	# `vnoise` 的格子面在输入坐标的整数处。若某个 `fbm6` 的偏移量恰好是频率的整数倍，
	# 格子面就落在 `x = 0` / `z = 0` 上 —— 而相机是**从极点正上方往下看**的
	#（竞技场摊在球面上只有 0.42°，法线就是 +Y）⇒ 那两个平面与视线轴共面
	# ⇒ 投影成**过画面中心的直线** ⇒ 球面上出现两条笔直的子午线，颜色沿它跳变。
	#
	# ⚠️ 用**比值**（最大行梯度 / 中位行梯度）而不是绝对阈值：绝对梯度随画面内容
	#（云、海岸线）大幅变化。实测改前 **77×**（正中行 0.114，中位 0.0015）。
	var seam := _seam(img)
	print("      [接缝] 最大行梯度 %.4f / 中位 %.4f = **%.1f×**；正中行 %.4f（%s）"
		% [seam["mx"], seam["med"], seam["ratio"], seam["center"],
			"正中行就是最大行" if seam["is_center"] else "正中行不是最大行"])
	_judge("⑳ 画面里**没有笔直的子午线接缝**（最大行梯度 / 中位 = %.1f× < 15）"
		% seam["ratio"], seam["ratio"] < 15.0)
	# ---- ★ ㉑ 三类均衡度（本轮新钉的读数；这个缺陷曾被 ③④⑤「绕道」抓到一次）----
	#
	# ## 它挡的是什么
	# 只要噪声频率远低于可见画面的张角，整幅画面就落在**同一个噪声格子**里 ⇒
	# 画面上最多跨过**一条**窄过渡带 ⇒ 绝大多数像素落进同一类 ⇒
	# 实测记为「海 5.4% / 陆 94.1% / 云 0.3% ⇒ 熵 0.210」（负对照 N1 的真机读数，
	# 见 `_leo_earth/neg1_freq.txt`；判定阈值 0.44 就由它与改后 0.941 的几何中点定出）。
	# ③④⑤ 各自**只有下限** ⇒ 那种画面能过 ③（陆地 94.1% > 3%），只有 ④⑤ 变红 ——
	# 而那是**绕道**：那三条的语义是"认得出海/陆/云"，实际读到的是"某一类把画面压倒"。
	# ㉑ 用一个数直接量**三类的分布形状**，并且**天然归一化**（不必拍量纲）。
	#
	# ## ⚠️⚠️ 为什么是熵，而不是「尺度」—— 我先后试了三个尺度类指标，**全部失败**
	# 真因是：改前的画面**不是「糊」而是「一边倒」**（见上）。把占比代进方差就能看出来：
	#   改前 96.4% 同色 ⇒ var ≈ 0.036·Δc²；改后三色各 ≈1/3 ⇒ var ≈ 0.22·Δc²
	#   ⇒ 标准差比 0.40，而实测低通振幅比正是 0.0525 / 0.171 = **0.31**（对上）
	# ⇒ **区分二者的正确量是颜色类的分布形状，不是空间频率。**
	# 失败记录（`_scale*.py`，都在真机 1600×900 图上量的）：
	#   · 「亮度跨该行中位数次数」——✗ 近常数区失效：纯天空那张（分布宽度仅 0.0036、
	#     像素只有 16/17 两个值）读数 **902**（满格 900），平滑 9×9 之后**仍有 533**，
	#     且随窗口**非单调**（r=2→325、r=4→533）。中位数附近的值极密集，
	#     任意微小的量化残差都被记成一次"跨越" ⇒ 那个量测的是**抖动**，不是结构尺度；
	#   · 「中尺度能量占比 var(LP100)/var」——✗ **方向相反**：改前 **0.970** > 改后 0.879
	#    （「整幅缓慢单调」也是低频，低通照样把它保留下来）；
	#   · 「自相关相关长度 ℓ」——✗ 只差 **2.1×**（改前 225 vs 改后 105），阈值余量太薄；
	#     且真机读数(151) 与 CPU 折算(105) 差 1.4× ⇒ "按分辨率比例折算"不成立。
	var ent := _balance_entropy([full["ocean"], full["land"], full["cloud"]])
	print("      [三类均衡] 归一化熵 **%.3f**（下界 %.2f）← 海 %.1f%%  陆 %.1f%%  云 %.1f%%"
		% [ent, BALANCE_ENTROPY_MIN, 100.0 * full["ocean"], 100.0 * full["land"],
			100.0 * full["cloud"]])
	# 诊断读数（**不判**）：上面那几个"尺度"候选里信息量最多的两个，留着手工复核用。
	var ts := _texture_scale(img)
	print("      [诊断·不判] 中尺度结构能量占比 %.3f  低通振幅 %.5f（窗口 %d px）"
		% [ts["ratio"], ts["amp"], int(float(img.get_width()) / SCALE_WIN_DIV)])
	_judge("㉑ 三类分布**均衡**（熵 %.3f > %.2f）—— 挡住「整幅画面落在同一个噪声格子、被一类压倒」"
		% [ent, BALANCE_ENTROPY_MIN], ent > BALANCE_ENTROPY_MIN)
	return out


# ------------------------------------------------------------- 机位 4：整颗球的剪影


## ★ 低头 90° + **宽 fov** —— 把 67° 的盘半角收进画面，量"**它是不是一个圆**"。
##
## ## 为什么必须把 fov 开到 150
## 盘半角 67° 而 fov 60 的垂直半角只有 30°（四角 49.1°）⇒ 60° 下画面**全被地球填满**、
## 根本看不到边（这正是 `_look_down()` 的 ⑥ 在断言的事）。
## 要看见整颗球，垂直半角必须 > 67° ⇒ **fov > 134°**。这里取 150°。
## ⚠️ 换 fov 不是"改判据"：预测公式里**带 fov**（见下），换了它预测值跟着变。
##
## ## 判据（三条）
## | # | 判据 | 它挡住的错法 |
## |---|---|---|
## | ⑩ | 四个方向都找到地球的剪影 | 地球**根本没建** / 被远裁面裁掉（找不到） |
## | ⑪ | 四方向半径**圆对称**（极差/最大 < 0.10） | 建成了一个**方块/平面**（各向半径差得远） |
## | ⑫ | 半径 = `tan(asin(R/(R+h)))/tan(fov/2)·H/2`（±15%） | ★ **R 或 h 写错**（把 h 改成 3 200 m ⇒ 预测差 9 倍） |
func _look_down_wide(cam: Camera3D) -> void:
	cam.fov = FOV_WIDE
	cam.far = ChaseCamera.ORBIT_FAR
	cam.global_position = _base
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	await _frames(10)
	var img := await _shot(cam, "look_down_wide", "低头 90° · fov %.0f（整颗球的剪影）" % FOV_WIDE)
	if img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	var cx := w / 2
	var cy := h / 2
	var ref := _sky_ref(img)
	var radii: Array[float] = []
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		radii.append(_limb_radius(img, cx, cy, d.x, d.y, ref))
	# 预测：盘半角 = asin(R/(R+h)) ⇒ 半径(像素) = tan(盘半角)/tan(fov/2) · H/2
	#
	# ⚠️ 这里**不要再套一层 `deg_to_rad`** —— `asin` 返回的就是弧度，`tan` 要的也是弧度。
	# 第一版写成 `deg_to_rad(asin(...))` ⇒ 预测算成 **2.5 px**（真值 284），
	# 于是判据 ⑫ 变成一条"必然失败"的假红（读数差 12 000%，看着像实现坏了）。
	var pred := tan(asin(PHYS_R / (PHYS_R + PHYS_H))) / tan(deg_to_rad(FOV_WIDE * 0.5)) \
		* (float(h) * 0.5)
	print("      [天空参考亮度] %.4f（四条射线**共用**，见 `_sky_ref()`）" % ref)
	print("      [四方向半径 px] 左 %.1f  右 %.1f  上 %.1f  下 %.1f   （预测 tan(asin(R/(R+h)))/tan(fov/2)·H/2 = %.1f）"
		% [radii[0], radii[1], radii[2], radii[3], pred])
	var found := 0
	for v in radii:
		if float(v) > 0.0:
			found += 1
	_judge("⑩ 四个方向都找到了地球的剪影（%d/4）" % found, found == 4)
	if found != 4:
		return
	var mn: float = minf(minf(radii[0], radii[1]), minf(radii[2], radii[3]))
	var mx: float = maxf(maxf(radii[0], radii[1]), maxf(radii[2], radii[3]))
	var mean_r: float = (radii[0] + radii[1] + radii[2] + radii[3]) / 4.0
	_judge("⑪ 剪影**圆对称**（极差/均值 = %.3f < 0.10）⇒ 脚底下是一个**球**（方块/平面做不到）"
		% ((mx - mn) / maxf(mean_r, 0.0001)), (mx - mn) / maxf(mean_r, 0.0001) < 0.10)
	_judge("⑫ 剪影半径与 `asin(R/(R+h))` 相符（均值 %.1f vs 预测 %.1f px，偏差 %.1f%% < %.1f%%）"
		% [mean_r, pred, 100.0 * absf(mean_r - pred) / pred, 100.0 * RADIUS_TOL],
		absf(mean_r - pred) / pred < RADIUS_TOL)


# ------------------------------------------------------------- 机位 5：临边弧线（需求 ②）


## ★ 出击环上、视线**水平** —— 临边落在下方 **23.0°**（＝地平线下沉角）处。
##
## ## 这一条是需求 ②「高度与现实一致」唯一的**像素**证据
## 下沉角 = `acos(R/(R+h))`，**只由 R 与 h 决定**：
##   · 真口径（R = 6 371 km，h = 550 km）⇒ **23.0°** ⇒ 行 780（画面中心行 450 下方 330 px）；
##   · B2 旧口径（h = 3.2 km）⇒ 1.8° ⇒ 行 474 —— **与实测差 300 多像素**，一眼可分。
##
## ## 为什么量的是**临边环**而不是"亮→暗"的过渡
## 地平线以下的天空是一片**亮雾**（`sky_ground` 混到 80%，亮度 ≈ 0.16），
## 而地球表面在临边附近只有 0.1 上下 ⇒ **"地球比天空亮"这件事不成立**。
## 而 `earth.gdshader` 的大气临边是**加法项**（恒在剪影上、与昼夜无关，亮度 ≈ 0.75）
## ⇒ 它是这条竖线上**唯一**一个明确的几何标记，`RING_MARGIN` 就卡在雾与环之间。
##
## ## 判据（三条）
## | # | 判据 |
## |---|---|---|
## | ⑬ | 五条竖线都在**预测行 ±12%** 内找到临边环 |
## | ⑭ | 临边**是弯的**：sagitta = 行(±600) − 行(0) > 40 px（平面世界 ⇒ 一条直线，≈ 0） |
## | ⑮ | 上半帧仍是**真空**（行 60 处均亮 < 0.06）⇒ "上真空、下地球" |
func _limb_curve(cam: Camera3D) -> void:
	cam.fov = FOV_NARROW
	cam.far = ChaseCamera.ORBIT_FAR
	cam.global_position = _ring
	# 视线水平：Godot 里 `rotation_degrees = 0` 即沿 −Z 平视（up = +Y）。
	cam.rotation_degrees = Vector3.ZERO
	await _frames(10)
	var img := await _shot(cam, "earth_limb_arc", "水平视线（临边在下沉角 23° 处）")
	if img == null:
		return
	var h := img.get_height()
	var cx := img.get_width() / 2
	var b := (float(h) * 0.5) / tan(deg_to_rad(FOV_NARROW * 0.5))
	var tan_dip := tan(deg_to_rad(90.0 - rad_to_deg(asin(PHYS_R / (PHYS_R + PHYS_H)))))
	var xs := [-600, -300, 0, 300, 600]
	var rows: Array[int] = []
	var preds: Array[float] = []
	for x in xs:
		var xf := float(x)
		# 沿一条竖线、相机平视时的投影：行 = H/2 + B·tan(下沉角)·sqrt(1 + (x/B)²)
		var pr := float(h) * 0.5 + b * tan_dip * sqrt(1.0 + (xf / b) * (xf / b))
		preds.append(pr)
		rows.append(_ring_row(img, cx + x, RING_MARGIN))
		print("      x = %+4d px ⇒ 预测行 %6.1f  实测行 %s   （偏差 %+.1f px）"
			% [x, pr, str(rows[rows.size() - 1]) if rows[rows.size() - 1] >= 0 else "未找到",
				float(rows[rows.size() - 1]) - pr if rows[rows.size() - 1] >= 0 else 0.0])
	var found := true
	var worst := 0.0
	for i in rows.size():
		if rows[i] < 0:
			found = false
			continue
		var off := absf(float(rows[i]) - preds[i]) / maxf(preds[i] - float(h) * 0.5, 1.0)
		worst = maxf(worst, off)
	_judge("⑬ 五条竖线都在预测行 ±%.0f%% 内找到临边环（最大偏差 %.1f%%；半球平视的预测由 R=6371 km / h=550 km 算出）"
		% [100.0 * ROW_TOL, 100.0 * worst], found and worst < ROW_TOL)
	var sag := 0.0
	if rows[0] >= 0 and rows[2] >= 0:
		sag = float(rows[0]) - float(rows[2])
	_judge("⑭ 临边**是弯的**（sagitta %.1f px > %.0f —— 平面世界的地平线是直线，这里会 ≈ 0）"
		% [sag, SAGITTA_MIN], sag > SAGITTA_MIN)
	var top := _blur(img, cx, 60, 2)
	print("      [行 60 处] 平滑亮度 %.4f（上半帧应当是真空）" % top)
	_judge("⑮ 上半帧是真空（行 60 处 %.4f < %.2f）⇒ 与 ⑬ 合起来 = 上真空、下地球"
		% [top, SKY_MEAN_MAX], top < SKY_MEAN_MAX)


# ------------------------------------------------------------- 需求 ③：强制回轨


## 真机演一遍"越过下边界"：把机体按到 50 km（远低于 100 km 再入线），
## 看它被**推回战斗高度带**、计数 +1、而且**还活着**（近地轨道没有撞地这回事）。
func _floor_demo() -> void:
	print("\n---- 需求 ③：越过下边界（近地轨道没有撞地）----")
	var hold := Node3D.new()
	hold.name = "OrbitFloorProbe"
	add_child(hold)
	var fb := FlightBody.new()
	fb.profile = SuitProfile.xi()
	hold.add_child(fb)
	var keep = Game.active_map
	Game.active_map = MapDef.leo()

	fb.global_position = Vector3(0.0, 50000.0, 0.0)
	fb.fm.velocity = Vector3(1200.0, -2600.0, 0.0)
	var before := fb.orbit_returns
	fb.call("_check_ceiling")
	print("      机体在 y = 50 000 m（再入线 100 000 m 之下）⇒ 调 `_check_ceiling()` 之后：")
	print("        y = %.0f m（战斗高度带 %.0f m）  回轨计数 %d → %d  alive = %s"
		% [fb.global_position.y, WorldBuilder.SPACE_ORBIT_ALT, before, fb.orbit_returns,
			str(fb.alive)])
	_judge("⑯ 被推回战斗高度带（%.0f m）" % WorldBuilder.SPACE_ORBIT_ALT,
		is_equal_approx(fb.global_position.y, WorldBuilder.SPACE_ORBIT_ALT))
	_judge("⑰ 回轨计数 +1（这条路真的走过）", fb.orbit_returns == before + 1)
	_judge("⑱ **没有判死**（近地轨道没有撞地这回事）", fb.alive)
	_judge("⑲ 垂直速度清零、水平速度留着（%.0f m/s）" % fb.fm.velocity.x,
		is_zero_approx(fb.fm.velocity.y) and is_equal_approx(fb.fm.velocity.x, 1200.0))

	hold.free()
	Game.active_map = keep


## 藏掉"配角"（碎片带 / 大件残骸 / 运输仓 / 卫星）。
##
## ⚠️ 为什么必须藏：后四个机位的判据量的是**脚底下那颗地球**的几何，而这些配角
## **与探针相机同高**（`SPACE_ORBIT_ALT`）——
##   · 在"正下方"机位它们落在离轴 90° 的方向上（画面外，本来就不影响）；
##   · 但在**水平视线**机位它们就贴在镜头边上：运输仓甚至**正好在**
##     `SPACE_POD_POS = (0, 550 km, 0)`，也就是"正下方"机位的相机位置上 ⇒ 会填满画面。
## 它们投出的边比临边还亮 ⇒ `_ring_row()` 找到的就不是地球的临边了。
##
## 隐藏**只影响探针这一张图**：不改场景、不存盘，游戏里照旧。
func _hide_props() -> void:
	var terrain: Node = _world.get("_terrain_root")
	var n := 0
	var stack: Array[Node] = [terrain]
	while stack.size() > 0:
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			var nm := String(c.name)
			var hit := false
			for p in ["SpaceDebris", "SpaceWreck", "Pod", "Sat"]:
				if nm.begins_with(p):
					hit = true
					break
			if hit:
				if c is Node3D:
					(c as Node3D).visible = false
					n += 1
			else:
				stack.append(c)
	print("[earth] 隐藏配角 %d 个（碎片带/残骸/运输仓/卫星 —— 见 `_hide_props()`）" % n)


# ------------------------------------------------------------- 出图 / 读数


func _look(cam: Camera3D, from: Vector3, at: Vector3, shot_name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _frames(10)
	await _shot(cam, shot_name, "机位 (%.0f, %.0f, %.0f)" % [from.x, from.y, from.z])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 存图并**返回 Image**（后面的判据都在它上面算）。
func _shot(cam: Camera3D, shot_name: String, note: String) -> Image:
	_idx += 1
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		print("SHOT_FAILED ", shot_name)
		return null
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(img) ", shot_name)
		return null
	var p := out_dir.path_join("%s.png" % shot_name)
	print("SHOT %s err=%d | %s" % [p, img.save_png(p), note])
	return img


func _lum(img: Image, x: int, y: int) -> float:
	var c := img.get_pixel(x, y)
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## (2r+1)² 邻域的**平均亮度**。
##
## ⚠️ 必须做邻域平均，不能取单像素：星空里的孤立亮星会让某一点"假亮"，
## 而**一个**假亮点就足以让扫描提前停住 —— 那正是"看起来对、数不对"的来源。
## 实测 5×5（r = 2）足以把单像素亮星压到 1/25。
func _blur(img: Image, x: int, y: int, r := 2) -> float:
	var s := 0.0
	var n := 0
	for oy in range(-r, r + 1):
		for ox in range(-r, r + 1):
			var xx := x + ox
			var yy := y + oy
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
				s += _lum(img, xx, yy)
				n += 1
	return s / float(maxi(n, 1))


## 从画面中心沿 (dx, dy) 最远能走多少像素（不能扫出画面）。
func _reach(img: Image, cx: int, cy: int, dx: int, dy: int) -> int:
	var r := 1 << 24
	if dx < 0:
		r = mini(r, cx)
	if dx > 0:
		r = mini(r, img.get_width() - 1 - cx)
	if dy < 0:
		r = mini(r, cy)
	if dy > 0:
		r = mini(r, img.get_height() - 1 - cy)
	return maxi(r, 1)


## ★ **四条射线共用一个**天空参考亮度（在四条射线的画面边缘各取 8 个采样求均值）。
##
## ⚠️ 必须共用，否则"圆对称"那条判据会变成在测**天空亮不亮**：
## 本图地平线以下是一片亮雾、地平线以上是真空，四条边上的天空**本来就不一样亮** ——
## 每条射线各取自己那一侧的参考 ⇒ 四条阈值不同 ⇒ **同一个圆量出四个不同的半径**。
## 第一版就是这么翻的：实测 左 321 / 右 346 / 上 308 / 下 311（同一个球，极差 12%）。
func _sky_ref(img: Image) -> float:
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	var s := 0.0
	var n := 0
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var reach := _reach(img, cx, cy, d.x, d.y)
		for k in 8:
			var i := reach - 1 - k * 3
			s += _blur(img, cx + d.x * i, cy + d.y * i, 2)
			n += 1
	return s / float(maxi(n, 1))


## 候选点的**内侧**必须是一大片亮的（不是一颗被 `glow` 晕开的星 / 一块孤立反光）。
##
## ⚠️ 这条是必需的：第一版在 `x = +300` 那条竖线上把"天空里一颗亮星的晕"当成了临边
##（找到行 370，而真临边在行 804）。星光辉光的内侧马上又回到真空，地球的内侧是**整片亮面**。
func _inside_is_bright(img: Image, cx: int, cy: int, dx: int, dy: int, i: int, reach: int,
		ref: float) -> bool:
	var lo := i + 1
	var hi := mini(i + 30, reach)
	if hi - lo < 4:
		return false
	var s := 0.0
	var n := 0
	for j in range(lo, hi + 1):
		s += _blur(img, cx + dx * j, cy + dy * j, 2)
		n += 1
	return s / float(maxi(n, 1)) > ref + 0.12


## ★ 剪影探测器：从画面边缘**向内**扫，返回"第一个显著亮于天空的采样点"离中心的距离（像素）。
##
## 为什么找的是**临边环**而不是"亮→暗"的过渡：本图地平线以下的天空是一片**亮雾**
##（`sky_ground` 混到 80%，亮度 ≈ 0.16），比暗色的洋面还亮 ⇒
## "地球比天空亮还是暗"这件事**不成立**，过渡检测会落在雾里。
## 而 `earth.gdshader` 的大气临边是**加法项**（恒在剪影上、与昼夜无关）⇒ 它是这条射线上
## **唯一**一个明确的几何标记，`RING_MARGIN` 就卡在雾与环之间。
##
## 返回：`≥ 0` 找到；`-1.0` 射线起点**就已经亮**（那个方向画面里没有天空 ⇒ 地球填满了画面）；
## `-2.0` 起点是天空但整条射线都没找到亮源（既无天空边界也无亮环 ⇒ 改前那种"纯色块"）。
func _limb_radius(img: Image, cx: int, cy: int, dx: int, dy: int, ref: float) -> float:
	var reach := _reach(img, cx, cy, dx, dy)
	var thr := ref + RING_MARGIN
	if _blur(img, cx + dx * reach, cy + dy * reach, 2) >= thr:
		return -1.0
	for i in range(reach - 1, 0, -1):
		if _blur(img, cx + dx * i, cy + dy * i, 2) >= thr \
				and _inside_is_bright(img, cx, cy, dx, dy, i, reach, ref):
			return float(i)
	return -2.0


## 沿一条竖线从上往下找**临边环**的行号（`-1` = 没找到）。
##
## 参考亮度取画面顶部（那一定是真空/天空）；阈值卡在"亮雾峰值 0.16"与"临边环 ≈ 0.79"之间
## ⇒ 第一个跨越它的行就是剪影所在的行。同样要求"下方是一大片亮的"（挡掉星光辉光）。
func _ring_row(img: Image, x: int, margin: float) -> int:
	var h := img.get_height()
	var ref := 0.0
	var n := 0
	for y in range(40, 81, 4):
		ref += _blur(img, x, y, 2)
		n += 1
	ref /= float(maxi(n, 1))
	var thr := ref + margin
	for y in range(100, h - 2):
		if _blur(img, x, y, 2) < thr:
			continue
		var hi := mini(y + 30, h - 1)
		if hi - (y + 1) < 4:
			continue
		var s := 0.0
		var c := 0
		for j in range(y + 1, hi + 1):
			s += _blur(img, x, j, 2)
			c += 1
		if s / float(maxi(c, 1)) > ref + 0.12:
			return y
	return -1


## 一个矩形区间里的读数：亮度五数概括 + 海 / 陆 / 云 三类像素占比。
##
## 色相分档（对着 `earth.gdshader` 的调色板）：
##   · 海洋 `OCEAN_DEEP/SHELF` ⇒ h ≈ 0.61–0.62；  陆地 `LAND_WET/DRY` ⇒ h ≈ 0.33 / 0.11；
##   · **低饱和的亮部**（云 / 冰 / 过曝）不计入海陆，单独算 `cloud`。
## ⚠️ 判据用**色相**而不是 RGB：渲染管线（本图是 ACES）会整体改变亮度与饱和度，
## 但**色相是稳的**（与"军刀配色"那一轮的结论一致）。
func _stats(img: Image, r: Rect2i) -> Dictionary:
	var lums: Array[float] = []
	var ocean := 0
	var land := 0
	var cloud := 0
	var n := 0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			lums.append(lum)
			n += 1
			if c.s >= 0.14:
				if c.h >= 0.45 and c.h <= 0.75:
					ocean += 1
				elif c.h >= 0.05 and c.h <= 0.44:
					land += 1
			elif lum >= 0.55:
				cloud += 1
	lums.sort()
	var m := lums.size()
	var out := {"mean": 0.0, "p02": 0.0, "p05": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0,
		"ocean": 0.0, "land": 0.0, "cloud": 0.0}
	if m == 0:
		return out
	var sum := 0.0
	for v in lums:
		sum += float(v)
	out["mean"] = sum / float(m)
	out["p02"] = lums[mini(int(float(m) * 0.02), m - 1)]
	out["p05"] = lums[mini(int(float(m) * 0.05), m - 1)]
	out["p50"] = lums[int(float(m) * 0.50)]
	out["p95"] = lums[mini(int(float(m) * 0.95), m - 1)]
	out["p99"] = lums[mini(int(float(m) * 0.99), m - 1)]
	var fn := float(maxi(n, 1))
	out["ocean"] = float(ocean) / fn
	out["land"] = float(land) / fn
	out["cloud"] = float(cloud) / fn
	return out


## ★ 「纹理尺度」诊断读数：**中尺度结构能量占比** + **低通振幅**。
##
## ⚠️ 这一对**只打印、不判**（判据 ㉑ 已改用熵，理由见 `_look_down()` 里的失败记录）：
## 占比在"整幅缓慢单调渐变"上会**反向**（改前 0.970 > 改后 0.879）；
## 振幅能分开但**依赖曝光**（改前 0.0525 / 改后 0.171，只有 3.3×）。
##
## ## 定义
## 9 条水平扫描线（行 = 10% … 90% 画高）。对每条线 `y(x)`：
##   · `lo(x) = movavg(y, 画宽/16)`（低通，窗口 ≈ 100 px @ 1600 宽）；
##   · **占比** = `var(lo) / var(y)` —— 被低通**保留**的能量占全部起伏的比例；
##   · **振幅** = `std(lo)` —— 剩下的那部分的绝对量级。
## 9 条线各取**中位数**（取中位不取均值：临边那张图里一半的线在真空里，
## 均值会被天空那几条拉到 0.5 以下，中位则忠实反映"画面里多数位置有没有结构"）。
##
## ## 为什么这个量是对的
## **占比对振幅归一化** ⇒ 不受 8-bit 量化抖动影响（那张纯天空的像素只有 16/17 两个值，
## 抖动幅度 1/255，归一化后照样得 0.004 —— 低通窗口 100 把白噪声方差压掉 100 倍）。
## 三类画面的预言，实测全部成立（`_scale4.py`，1600×900 真机图）：
## | 画面 | 占比 | 振幅 |
## |---|---|---|
## | 真地球（结构 ≈ 336 px，画面 1600） | **0.898** | 0.173 |
## | 纯天空（白噪声抖动） | **0.004** | 0.00008 |
## | 宽 fov 整颗球 | 0.887 | 0.280 |
## | 临边弧线（含天空的线 / 含地球的线） | 0.010 / 0.98 | — |
##
## ## ⚠️⚠️ 我第一版选的代理量是错的，记下来别再踩
## 第一版选了「9 条扫描线上**亮度跨越该行中位数**的次数的中位数」——
## 它在 CPU 浮点复刻里读得漂亮（改前 2 / 改后 5），到**真机 8-bit 图**上直接崩：
## 那张"纯天空"（分布宽度只有 0.0036）读数 **902**（满格 900），
## 平滑 9×9 之后**仍有 533**，而且随窗口**非单调**（r=2→325、r=4→533）。
## 根因：中位数附近的像素值**极度密集**，任意微小的量化残差都被记成一次"跨越"
## ⇒ 那个量测的是**抖动**，不是**结构尺度**。
## **教训：代理量必须在真机 8-bit 图上先验证，别信浮点复刻给的漂亮数字。**
func _texture_scale(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var win := maxi(int(float(w) / SCALE_WIN_DIV), 3)
	var ratios: Array[float] = []
	var amps: Array[float] = []
	for gy in range(1, 10):
		var y := int(float(h) * float(gy) / 10.0)
		var row := PackedFloat64Array()
		row.resize(w)
		for x in w:
			row[x] = _lum(img, x, y)
		var tot := _var(row)
		var lo := _movavg(row, win)
		ratios.append(_var(lo) / maxf(tot, 1.0e-12))
		amps.append(sqrt(maxf(_var(lo), 0.0)))
	ratios.sort()
	amps.sort()
	var mid := ratios.size() / 2
	return {"ratio": ratios[mid], "amp": amps[mid]}


## ★ **三类均衡度**：把 [海, 陆, 云] 三类占比归一化成概率，求归一化熵 `H / ln3` ∈ [0, 1]。
##
## 语义：**画面里三类的分布是不是「一边倒」**。
##   · 三色均匀（各 1/3）⇒ 1.000；两类均分 ⇒ 0.631；一类压倒 ⇒ → 0；只有一类 ⇒ 0。
## 实测：改后真地球 0.941；改前（一类压倒）≈ 0.05；纯天空 0.000。
## ⚠️ 先归一化到三类之和（画面里可能有少量"其它"像素 —— 既不属海也不属陆云的过渡色）。
func _balance_entropy(parts: Array) -> float:
	var s := 0.0
	for v in parts:
		s += float(v)
	if s <= 1.0e-9:
		return 0.0
	var e := 0.0
	var ln3 := log(3.0)
	for v in parts:
		var q := float(v) / s
		if q > 1.0e-12:
			e -= q * (log(q) / ln3)
	return e


## 长度 `win` 的滑动平均，越界按**边缘值**补齐（与 `_scale4.py` 的 `np.pad(mode="edge")` 逐点一致）。
func _movavg(y: PackedFloat64Array, win: int) -> PackedFloat64Array:
	var n := y.size()
	var out := PackedFloat64Array()
	out.resize(n)
	if n == 0 or win <= 0:
		return y.duplicate()
	var hw := win / 2
	var c := PackedFloat64Array()
	c.resize(n + 1)
	c[0] = 0.0
	for i in n:
		c[i + 1] = c[i] + y[i]
	for i in n:
		var a := i - hw
		var b := a + win
		var lo := maxi(a, 0)
		var hi := mini(b, n)
		var s := c[hi] - c[lo]
		if a < 0:
			s += float(-a) * y[0]
		if b > n:
			s += float(b - n) * y[n - 1]
		out[i] = s / float(win)
	return out


func _var(y: PackedFloat64Array) -> float:
	var n := y.size()
	if n == 0:
		return 0.0
	var s := 0.0
	for v in y:
		s += v
	var mu := s / float(n)
	var q := 0.0
	for v in y:
		var d := v - mu
		q += d * d
	return q / float(n)


## 行梯度的"尖峰比" = 最大行梯度 / 中位行梯度（连同"正中行"那一行的梯度）。
##
## 用途见判据 ⑳：噪声格子面若落在 `x = 0` / `z = 0` 上，球面北极那两条子午线会投影成
## **过画面中心的直线** ⇒ 那一行的梯度会远高于其它行。
func _seam(img: Image) -> Dictionary:
	var y0 := int(float(img.get_height()) * 0.05)
	var y1 := img.get_height() - y0
	var cy := img.get_height() / 2
	var g: Array[float] = []
	var bv := -1.0
	var best := y0 + 1
	var ctr := 0.0
	for y in range(y0 + 1, y1):
		var s := 0.0
		var n := 0
		for x in range(0, img.get_width(), 4):
			s += absf(_lum(img, x, y) - _lum(img, x, y - 1))
			n += 1
		var v := s / float(maxi(n, 1))
		g.append(v)
		if v > bv:
			bv = v
			best = y
		if y == cy:
			ctr = v
	g.sort()
	var med: float = g[int(float(g.size()) * 0.5)]
	return {"med": med, "mx": bv, "ratio": bv / maxf(med, 1.0e-6),
		"center": ctr, "is_center": absi(best - cy) <= 2}


func _core_rect(img: Image) -> Rect2i:
	var w := int(float(img.get_width()) * CORE_FRAC)
	var h := int(float(img.get_height()) * CORE_FRAC)
	return Rect2i((img.get_width() - w) / 2, (img.get_height() - h) / 2, w, h)


## **四条边的中点**的采样块（各 12%×12%）：地球填满画面时它们全是"有纹理的地表"；
## 而"一颗小球 + 四周是天空"时它们是**光滑的天**（分布宽度 ≈ 0）。
##
## ⚠️ 不取**四角**：本工程画面四角常有 HUD/准星之类的东西，取边中点更干净。
func _edge_blocks(img: Image) -> Array[Rect2i]:
	var w := int(float(img.get_width()) * 0.12)
	var h := int(float(img.get_height()) * 0.12)
	var out: Array[Rect2i] = []
	out.append(Rect2i((img.get_width() - w) / 2, 0, w, h))
	out.append(Rect2i((img.get_width() - w) / 2, img.get_height() - h, w, h))
	out.append(Rect2i(0, (img.get_height() - h) / 2, w, h))
	out.append(Rect2i(img.get_width() - w, (img.get_height() - h) / 2, w, h))
	return out


func _tan2(deg: float) -> float:
	var t := tan(deg_to_rad(deg))
	return t * t


func _aspect2() -> float:
	var a := float(SHOT_W) / float(SHOT_H)
	return a * a


func _judge(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_all_ok = false
		print("  FAIL  %s" % label)
