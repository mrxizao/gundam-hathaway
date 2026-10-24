extends Node
## 佩涅罗佩光束配色 · **真机判据图**（2 列 × 3 排）
##
## ## 要证的事
##
## 用户 2026-09-30：「佩涅罗佩的**光束大炮**和**光束步枪的子弹**颜色都改成**粉紫色**」。
##
## 产品侧是**一个字段管两条通道**（`SuitProfile.rifle_beam_color` → `beam_color()`）：
##   · 步枪弹体：`FlightBody.fire_beam()` → `Projectile.beam(..., profile.beam_color(), ...)`
##   · 大炮光柱：`FlightBody.fire_cannon()` → `BeamCannon.launch(..., profile.beam_color())`
## ⇒ 所以本探针**两列**，就是分别把两条通道**真的开一次火**、量它落在屏幕上的颜色。
##
## | 排 | profile 的 `rifle_beam_color` | 期望 |
## |----|------------------------------|------|
## | ① | **不动**（当前工程值 = 粉紫） | 两列都是**品红/紫**（R 与 B 都抬起来、G 明显低） |
## | ② | 换成「没指定」（`alpha = 0` ⇒ 退回 `accent` 蓝） | 蓝 —— **这是改前的画面**，也是负对照 |
## | ③ | 换成**柯西绿** | 绿 —— 再一个负对照 |
##
## ②③ 两排的作用是证明「① 的判据**能变红**」：判据本体写成一个纯函数
## `_is_pink_purple()`，同一把尺子去量三排，**②③ 必须为假**（本文件会显式打印这件事）。
##
## ## ★ 口径写死在探针里（不从被测对象取）
##
## `WANT_*` 是**用户口径**，硬编码。从 `SuitProfile` 取的话，改色值时"被测值"与"目标值"
## 一起动 ⇒ 判据永绿（`tools/saber_color_shot.gd` 头注里记着这条假绿）。
## 所以另加一条**数据侧锁**：profile 里那个色值必须 = 口径（否则本探针自己先红）。
##
## ## ★ 为什么"看见的颜色"不等于"材质里的颜色"
##
## 光束材质是 `SHADING_MODE_UNSHADED` + `BLEND_MODE_ADD` + `emission × energy`：
##   · 不受光照 ⇒ 改灯光/环境**改不动它**（"关灯看看"这类手段无效）；
##   · ADD ⇒ `dst = 底下的颜色 + 这层的颜色` —— 底下是**被照亮的机体**时会给结果**染色**
##     ⇒ 本图先 `_hide_suit()` 把机体网格全隐藏，背景回到纯中性 0.04；
##   · 能量远超 1.0 ⇒ 8-bit framebuffer 把**实心区夹到接近纯白**，
##     有色信息只留在**边缘混合像素**上 ⇒ 只统计"有饱和度"的像素（`SAT_MIN`）。
##
## ## ★ 两列各自的"带主色那一层"不一样（分层观测）
##
## `BeamCannon` 是**两层同轴圆柱**：内核（`alpha 1.0`、`emission ×1.0` ⇒ 过曝成近白偏粉）
## + 外晕（`alpha 0.22`、`emission ×0.55` ⇒ **不过曝**，是最忠实的那一层）。
## 所以大炮列量的是**只留外晕**（`_core` 藏掉）—— 与军刀那套"量带主色的外层"同源。
## 步枪弹体只有**一层**（单圆柱），没有可分层的东西 ⇒ 只能量边缘混合像素。
##
## ## ★ 大炮必须**先等它展开**
##
## `BeamCannon._physics_process()` 有 `grow = clampf(_life / 0.12, 0, 1)` 的展开斜坡 ——
## 开火后立刻拍只有一根**短桩**。本探针等 `CANNON_GROW_FRAMES` 帧再取景。
## ⚠️ 取景点还要**沿柱往外挪 300 m**：炮口那一片有光晕（`CannonFlare`）与大量飞溅粒子，
## 全是近白，压在柱上会把量到的色相往白里拉。
##
## ## ★ 冻结：两处，都只碰"位置/可见性"，不碰颜色
##
## · 弹丸：`fire_beam` 出来的 `Projectile` 一帧飞 48 m（2880 m/s）⇒ A/B 两张不可能同框。
##   把它的 `_physics_process` 关掉（**只碰位置**）。
## · 大炮：它**每帧重写** `_core.visible / _glow.visible` ⇒ 手动藏内核保持不住，
##   同样要关掉它自己的 `_physics_process`。
##
## 跑法（**不能加 --headless**：dummy 渲染器抓出来是空的）：
##   godot --path <工程> res://tools/penelope_beam_color_shot.tscn -- <输出目录>

const W := 360
const H := 430
const COLS := ["步枪弹体（Projectile）", "大炮光柱（BeamCannon）"]
const ROWS := [
	"① 生产路径（当前 profile）",
	"② 负对照：退回 accent（改前那条蓝）",
	"③ 负对照：换成柯西绿",
]

## 背景色：**中性暗灰**（三通道相等）。
##
## ⚠️ 必须是中性色：ADD 混合下背景自己带色相就会给光**染色**
##（军刀那轮实测：偏蓝暗背景把 311° 的粉拉到 282°）。亮灰则把一切推向纯白。
const BG := Vector3(0.04, 0.04, 0.04)
## 差集掩码阈值：两图逐通道绝对差之和。
const MASK_EPS := 0.05
## "有饱和"的下限（HSV 的 s = (max−min)/max）——滤掉被夹成近白的实心区像素。
const SAT_MIN := 0.35
## 色相直方图的格数（10° 一格）。
const HUE_BINS := 36
## "最饱和子集"的下限。⚠️ **不进判据**（最饱和的像素恰是过曝台阶的中间态，
## 色相在那里最不稳定），只留作对照。
const HI_SAT := 0.90

## ---- 用户口径（硬编码）----
## 粉紫 `Color(0.90, 0.38, 1.0)`，材质侧 HSV 色相 **290.3°**、饱和度 0.62。
const WANT_R := 0.90
const WANT_G := 0.38
const WANT_B := 1.00
const WANT_HUE := 290.3
## ⚠️ **屏幕上的**色相口径与材质不同：过曝夹逼把 R 与 B 都顶到 1.0
## （`R = B = 1.0 > G`）⇒ 色相会从 290° 漂到**品红的 300°** 附近。
## 这不是实现问题，是"实心区夹白"的必然结果 —— 本探针把**两个数都打出来**：
## 数据侧锁判 290.3°，像素侧判这个带（容差给得宽，因为夹逼程度随覆盖率变化）。
const MEAS_HUE := 300.0
const MEAS_HUE_TOL := 25.0
## 通道主导的判据余量：粉紫的 R 与 B 都要**明显**高于 G。
## 这一条才是能分开"蓝 / 绿"的东西（夹逼后的像素上，蓝是 `G≈B>R`、绿是 `G` 最高）。
const CH_MARGIN := 0.10
## "**全掩码均值**"那一把尺子的余量。比 `CH_MARGIN` 松：整条光束一起平均时，
## 过曝的近白实心区会把差异摊薄（实测粉紫约 +0.20，蓝约 −0.05）。
const ALL_MARGIN := 0.05

## 相机取景（正交投影，`cam_size` 固定 ⇒ 格与格可直接比）。
const CAM_SIZE_RIFLE := 70.0
const CAM_SIZE_CANNON := 90.0
## 大炮取景点离炮口的距离（米）：躲开光晕与飞溅粒子。
const CANNON_FOCUS_M := 300.0
## 柱体"展开"用掉的帧数（`BeamCannon` 有 0.12 s 的 grow 斜坡）。
const CANNON_GROW_FRAMES := 14

var out_dir := "user://pen_beam_color"
## "已隐藏机体网格 N 个"只打一次。
var _hid_reported := false
## 看门狗：`_ready` 万一被脚本错误打断，场景**不会自己退出**，会一直挂在主循环里
## 烧 GPU（本轮实测烧了 7 分钟）。这个兜底让它最多活 `WATCHDOG_FRAMES` 帧。
var _frames := 0
var _done := false
const WATCHDOG_FRAMES := 60 * 240


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames > WATCHDOG_FRAMES:
		push_error("探针超时未完成（%d 帧）—— 大概中途出了脚本错误，强制退出。" % _frames)
		get_tree().quit(1)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	# ⚠️ 无头下 `RenderingServer.frame_post_draw` **永远不来** ⇒ 抓图那几处 await
	#    会**永久挂住**探针。这里显式短路：无头只跑"数据侧锁"（那部分不需要渲染）。
	if DisplayServer.get_name() == "headless":
		print("★ headless：渲染器是 dummy，抓出来的图是空的 ⇒ 只跑数据侧锁，不做像素判据。")
		var dl_ok := _data_lock()
		print("\nALL_OK=%s" % ("true" if dl_ok else "false"))
		_done = true
		get_tree().quit(0 if dl_ok else 1)
		return

	_build_env()
	await get_tree().physics_frame
	FlightBody.use_placeholder = false

	var grid := Image.create(W * COLS.size(), H * ROWS.size(), false, Image.FORMAT_RGBA8)
	grid.fill(Color(0.10, 0.11, 0.13))

	var recs := {}
	for ri in ROWS.size():
		for ci in COLS.size():
			var p := SuitProfile.penelope()
			_apply_row(p, ri)
			var tag := "%s / %s" % [ROWS[ri], COLS[ci]]
			var cell := await _cell(p, ci)
			# ⚠️ 用 `.get()` 而不是 `cell["img"]`：`_cell` 中途出脚本错误时返回的是
			#    **缺 key 的字典**，直接下标会再炸一次，而 `_ready` 被中断后
			#    **场景不会退出**（会一直挂主循环）—— 本轮实测烧了 7 分钟 GPU。
			if cell.get("img") == null:
				print("FATAL: 这一格没拍成（%s）—— %s" % [tag, cell.get("how", "?")])
				_done = true
				get_tree().quit(1)
				return
			var st: Dictionary = cell["stats"]
			recs["%d_%d" % [ri, ci]] = st
			grid.blit_rect(cell["img"], Rect2i(0, 0, W, H), Vector2i(ci * W, ri * H))
			print("%-38s n=%5d sat=%.2f hueMode=%6.1f° share=%.2f RB=%+.3f rgb=(%.2f, %.2f, %.2f) [%s]" % [
				tag, st["n"], st["sat"], st["hue_mode"], st["share"],
				st["rbn"], st["r"], st["g"], st["b"], cell["how"]])
			var path := "%s/cell_%d_%d.png" % [out_dir, ri, ci]
			var sverr: int = cell["img"].save_png(path)
			print("         存图 %s（err=%d）" % [path, sverr])
			if ci == 1:
				print("         对照：全层（内核+外晕）hueMode=%.1f° RB=%+.3f"
					% [st.get("hue_full", -1.0), st.get("rbn_full", 0.0)])
				if not bool(st.get("layered", false)):
					print("         ⚠️ 没分层（取不到 `_core`）—— 量到的是全层")

	# ============================================================ 判决
	print("\n================ 判决（颜色）================")
	var ok := true
	# ---- ① 数据侧锁：profile 里那个值必须 = 用户口径 ----
	ok = _data_lock() and ok

	# ---- ② 像素侧：两列都要是粉紫 ----
	var r00: Dictionary = recs["0_0"]
	var r01: Dictionary = recs["0_1"]
	ok = _judge(ok, "① 步枪弹体：屏幕色相 = 品红带（%.0f° ± %.0f°）"
		% [MEAS_HUE, MEAS_HUE_TOL],
		_hue_gap(r00["hue_mode"], MEAS_HUE) <= MEAS_HUE_TOL, r00)
	ok = _judge(ok, "① 大炮光柱：屏幕色相 = 品红带（%.0f° ± %.0f°）"
		% [MEAS_HUE, MEAS_HUE_TOL],
		_hue_gap(r01["hue_mode"], MEAS_HUE) <= MEAS_HUE_TOL, r01)
	ok = _judge(ok, "① 步枪弹体：R 与 B 都明显高于 G（粉紫 = 红蓝双高）",
		_is_pink_purple(r00), r00)
	ok = _judge(ok, "① 大炮光柱：R 与 B 都明显高于 G（粉紫 = 红蓝双高）",
		_is_pink_purple(r01), r01)
	ok = _judge(ok, "① 两列**同色**：色相差 ≤ 15° 且 R−B 差 ≤ 0.05（一个字段管两条通道）",
		_hue_gap(r00["hue_mode"], r01["hue_mode"]) <= 15.0
			and absf(r00["rbn"] - r01["rbn"]) <= 0.05, r00, r01)
	# ---- 第二把尺子：**全掩码均值**（把过曝成近白的实心区也算进来）----
	#
	# 它不依赖"哪些像素饱和度过得了门槛"，所以对"蓝那种一夹就白"的颜色也有效。
	ok = _judge(ok, "① 步枪弹体：全掩码均值也是 R、B 双高于 G（含过曝区）",
		_is_pink_purple_all(r00), r00)
	ok = _judge(ok, "① 大炮光柱：全掩码均值也是 R、B 双高于 G（含过曝区）",
		_is_pink_purple_all(r01), r01)

	# ---- ③ 负对照：同一把尺子去量 ②③ 两排，必须为假 ----
	print("\n---------------- 负对照（同一把尺子必须变红）----------------")
	var neg_rows := [
		[1, "② 退回 accent（蓝）"],
		[2, "③ 换成柯西绿"],
	]
	for pair: Array in neg_rows:
		var nri: int = pair[0]
		var nname: String = pair[1]
		for ci in COLS.size():
			var s: Dictionary = recs["%d_%d" % [nri, ci]]
			var is_pp := _is_pink_purple(s)
			ok = _judge(ok, "NEGCTL %s / %s：① 的判据必须**为假**"
				% [nname, COLS[ci]], not is_pp, s)
			ok = _judge(ok, "NEGCTL %s / %s：全掩码均值那把尺子也必须**为假**"
				% [nname, COLS[ci]], not _is_pink_purple_all(s), s)
		# 与 ① 的色相差（证明"确实换了颜色"，而不是"两边都量不到")
		var d0 := _hue_gap(recs["0_0"]["hue_mode"], recs["%d_0" % nri]["hue_mode"])
		var d1 := _hue_gap(recs["0_1"]["hue_mode"], recs["%d_1" % nri]["hue_mode"])
		ok = _judge(ok, "NEGCTL %s：与 ① 的屏幕色相差要够大（步枪 %.1f° / 大炮 %.1f°）"
			% [nname, d0, d1], d0 > 40.0 and d1 > 40.0,
			recs["%d_0" % nri], recs["%d_1" % nri])

	# ---- ④ 读数健全性 ----
	print("\n---------------- 读数健全性 ----------------")
	for key: String in recs.keys():
		var s2: Dictionary = recs[key]
		ok = _judge(ok, "读数健全 %s：掩码里有色像素够多（n = %d ≥ 60）" % [key, s2["n"]],
			s2["n"] >= 60, s2)
		ok = _judge(ok, "读数健全 %s：有一个主导色相（众数格占 %.2f ≥ 0.25）" % [key, s2["share"]],
			s2["share"] >= 0.25, s2)

	# ---- 辨识极限：写进图里，不要藏 ----
	print("\n  NOTE  材质侧的口径是 %.1f°（粉紫），而屏幕实心区被 ADD + 过曝夹成近白，"
		% WANT_HUE)
	print("        有色信息只在边缘 / 外晕上 ⇒ 量到的色相被推向品红端 %.0f° 附近。"
		% MEAS_HUE)
	print("        这是 ADD + 过曝 clamp 的必然结果，不是实现问题。")
	print("  NOTE  ②（蓝）那一格**两把尺子都能判它假**，但它的饱和门槛读数没有代表性：")
	print("        蓝的过曝形态是 (0.95, 1.0, 1.0)（饱和度只剩 0.05）⇒ 被 `SAT_MIN` 滤掉，")
	print("        只剩背景附近几百个暗像素。**粉紫则相反**：过曝形态 (1.0, ~0.7, 1.0)")
	print("        饱和度还在，几千个像素过门槛 ⇒ 这说明用户选的粉紫在过曝下**更保色**，")
	print("        不是探针偏心。两排都另有「全掩码均值」那把尺子兜底。")

	for ci in COLS.size():
		for ri in ROWS.size():
			_draw_frame(grid, ci * W, ri * H, W, H)

	var path := "%s/pen_beam_color_grid.png" % out_dir
	var err := grid.save_png(path)
	print("\n图：%s（save_png err=%d）" % [path, err])
	print("\nALL_OK=%s" % ("true" if ok else "false"))
	_done = true
	get_tree().quit(0 if ok else 1)


# ================================================================ 口径

## 按排改 profile 的色值。① 不动 = **生产值**；②③ 是负对照。
##
## ⚠️ `SuitProfile.penelope()` 每次调用**新建一个实例** ⇒ 在探针里改它
## 不会污染别的格（产品代码与测试都读的是各自新建的那份）。
func _apply_row(p: SuitProfile, ri: int) -> void:
	match ri:
		0:
			pass  # 生产值，一个字节都不动
		1:
			# 「没指定」⇒ `beam_color()` 退回 `accent`。**这就是改前的画面**。
			p.rifle_beam_color = Color(0.0, 0.0, 0.0, 0.0)
		_:
			# 换一个完全不同的色相（绿），证明判据不是"对某一种色写死的"。
			p.rifle_beam_color = Color(0.40, 1.0, 0.50, 1.0)


## ① 的判据本体。**同一把尺子**也用来量 ②③ 两排（那里必须为假）。
##
## ⚠️ 从 `Dictionary` 取出来的值是 Variant ⇒ 先落到显式的 float 上再比，
## 免得"类型推断不出来"在解析期就炸（本文件踩过一次同款：`var x := dict["k"].method()`）。
func _is_pink_purple(st: Dictionary) -> bool:
	var r: float = st["r"]
	var g: float = st["g"]
	var b: float = st["b"]
	return r >= g + CH_MARGIN and b >= g + CH_MARGIN


## 同一件事，但用**全掩码均值**（含过曝成近白的实心区）当输入。
##
## ⚠️ 两把尺子都要，因为它们的**失效方式不同**：
##   · 只用"过饱和门槛"那一把：蓝那一格会被滤到只剩几百个背景附近的暗像素，
##     读数没有代表性（但**它仍然不是粉紫**，所以负对照照样能红）；
##   · 只用"全掩码均值"那一把：整条光束一起平均 ⇒ 差异小、余量薄。
## 两把都判，任一把红了就红。
func _is_pink_purple_all(st: Dictionary) -> bool:
	var r: float = st.get("r_all", 0.0)
	var g: float = st.get("g_all", 0.0)
	var b: float = st.get("b_all", 0.0)
	return r >= g + ALL_MARGIN and b >= g + ALL_MARGIN


## 数据侧锁：`SuitProfile.penelope()` 里那个色值必须 = 用户口径。
##
## ⚠️ 这一条**故意**去比 profile —— 色相是口径的一部分，谁改了色值就该红一次、
## 让人确认，而不是让探针把新值当成新标准静默接收。
func _data_lock() -> bool:
	var ok := true
	var c: Color = SuitProfile.penelope().beam_color()
	print("---- 数据侧锁：SuitProfile.penelope().beam_color() ----")
	ok = _num(ok, "① r", c.r, WANT_R)
	ok = _num(ok, "① g", c.g, WANT_G)
	ok = _num(ok, "① b", c.b, WANT_B)
	var h := c.h * 360.0
	var dh := _hue_gap(h, WANT_HUE)
	var hok := dh <= 3.0
	print("  %s  ① 色相 %.1f° = 口径 %.1f°（Δ=%.1f°，容差 3°）"
		% ["PASS" if hok else "FAIL", h, WANT_HUE, dh])
	# 通道主导（口径的"粉紫"就是这么定义的）
	var dom := c.r > c.g and c.b > c.g and c.b > c.r
	print("  %s  ① 通道主导：B > R > G（%s）"
		% ["PASS" if dom else "FAIL", str(c)])
	# 一个字都不许动 accent：它同时管主菜单卡片 / 敌机列表 / HUD 强调色
	var acc := SuitProfile.penelope().accent
	var accok := acc == Color(0.52, 0.76, 1.0)
	print("  %s  ① `accent` 未被改动（仍是 %s —— 光束色没写穿到 UI 配色）"
		% ["PASS" if accok else "FAIL", str(acc)])
	return ok and hok and dom and accok


func _num(ok: bool, label: String, got: float, want: float) -> bool:
	var c := absf(got - want) <= 0.001
	print("  %s  %s = %.3f（口径 %.3f）" % ["PASS" if c else "FAIL", label, got, want])
	return ok and c


# ================================================================ 一格

func _cell(p: SuitProfile, ci: int) -> Dictionary:
	# 防御：把上一格万一没释放干净的容器清掉（正常路径下 `_cell` 末尾已经释放）。
	for old in get_children():
		if old.name == "Container":
			old.queue_free()
			await get_tree().physics_frame
	var box := Node3D.new()
	box.name = "Container"
	add_child(box)
	var fb := await _mount(p)
	fb.projectile_container = box
	# ⚠️ 顺序：**先取 bounds/炮口**（机体还在），**再**把机体网格全隐藏。
	var hid := _hide_suit(fb)
	if not _hid_reported:
		_hid_reported = true
		print("        （已隐藏机体网格 %d 个：ADD 混合会把底下的机体色叠进光束）" % hid)

	var out: Dictionary
	if ci == 0:
		out = await _fire_rifle(p, fb, box)
	else:
		out = await _fire_cannon(p, fb, box)
	# ★★ **必须连容器一起释放**。弹体 / 光柱都挂在 `box` 下，而 `box` 挂在探针根上。
	#    只 free 机体的话，**上一格的弹体/光柱会留在场景里**；而每一格都是同一台机体、
	#    同一个机位、同一个炮口 ⇒ 新的一发**精确叠在旧的那发上面**，
	#    差集掩码读到 n≈0（"看不出差异"）。
	#    本轮实测症状极像"负对照根本没生效"：②③ 两排读数与①一模一样，
	#    而**真因是上一格的残留** —— 出图一眼看穿（② 那格里还漂着① 的粉紫光柱）。
	box.queue_free()
	fb.queue_free()
	for i in 2:
		await get_tree().physics_frame
	return out


## 步枪弹体：走**生产路径** `fire_beam()`，量弹体自己贡献的像素。
func _fire_rifle(p: SuitProfile, fb: FlightBody, box: Node3D) -> Dictionary:
	# ⚠️ **不要写 `fb.debug_input_enabled`** —— 那是 `PlayerController` 的字段，
	#    `FlightBody` 上根本没有它。写上去是**运行期**报错（"Invalid assignment …"），
	#    而且会把 `_fire_rifle` 整个打断、返回一个**缺 key 的字典** ⇒ `_ready` 里
	#    `cell["img"]` 再炸一次，**场景不退出**（本轮真踩过：探针挂在那里烧了 7 分钟 GPU）。
	#    这条路是**直接调 `fire_beam()`**（生产入口），不需要任何"输入开关"。
	fb.rifle_mag = p.rifle_magazine
	fb.rifle_cooldown = 0.0
	fb.rifle_reloading = false
	fb.rifle_count = 1
	if fb._muzzle_local.is_empty():
		return {"img": null, "stats": {}, "how": "`_muzzle_local` 为空"}
	if not fb.fire_beam(true, null):
		return {"img": null, "stats": {}, "how": "`fire_beam()` 拒绝了（门禁没过）"}
	# ⚠️ 弹体从 `box.get_child(0)` 取，**不用全局类名 `Projectile` 做 `is` 判断**：
	#    本工程有并行会话，全局类名缓存只在编辑器 / `--import` 时刷新，
	#    无头下拿它做类型判断有"整类静默失效"的前科（见 `flight_body.gd` 的 `BeamCannonScript`）。
	if box.get_child_count() != 1:
		return {"img": null, "stats": {},
			"how": "容器里不是一发弹体（%d 个）" % box.get_child_count()}
	var pr: Node3D = box.get_child(0) as Node3D
	if pr == null:
		return {"img": null, "stats": {}, "how": "容器第一个子节点不是 Node3D"}
	# ⚠️ 冻住弹丸：2880 m/s ⇒ 一帧 48 m，A/B 两张不可能同框。
	#    **只碰位置**（`set_physics_process`），颜色是产品代码写进材质的那一份。
	pr.set_physics_process(false)
	pr.lifetime = 99999.0
	var focus: Vector3 = pr.global_position
	var off := Vector3(1.0, 0.35, 0.0)
	pr.visible = false
	var a: Image = await _shot(focus, CAM_SIZE_RIFLE, off)
	pr.visible = true
	var b: Image = await _shot(focus, CAM_SIZE_RIFLE, off)
	if a == null or b == null:
		return {"img": null, "stats": {}, "how": "抓图失败"}
	var st := _merge_all(_masked_stats(a, b), a, b)
	return {"img": b, "stats": st, "how": "生产路径 fire_beam()，弹体单层（无分层可做）"}


## 大炮光柱：走**生产路径** `fire_cannon()`；量的是**只留外晕**那一层。
func _fire_cannon(p: SuitProfile, fb: FlightBody, box: Node3D) -> Dictionary:
	# 同上：`debug_input_enabled` 是 `PlayerController` 的字段，这里不碰。
	fb.rifle_mag = p.rifle_magazine
	fb.rifle_cooldown = 0.0
	fb.cannon_cd_left = 0.0
	fb.rifle_reloading = false
	fb.reload_timer = 0.0
	fb.rifle_count = 1
	var ready_ok: bool = fb.cannon_ready()
	if not fb.fire_cannon(null):
		return {"img": null, "stats": {},
			"how": "`fire_cannon()` 拒绝了（cannon_ready=%s）" % str(ready_ok)}
	# ⚠️ 用**无类型**变量接柱体：`BeamCannon` 的 `_core / _flare` 是它的成员，
	#    若写成 `var c: Node3D = ...` 再读 `c._core`，静态类型检查会当场报
	#    "Node3D 上没有 `_core`"（那是**编译期**错误，不是运行时的）。
	var c = fb.active_cannon
	if c == null:
		return {"img": null, "stats": {}, "how": "`active_cannon` 为 null"}
	# ---- 等柱体展开（`grow = _life / 0.12`）----
	for i in CANNON_GROW_FRAMES:
		await get_tree().physics_frame
	# ⚠️ 停掉柱自己的 `_physics_process`：它每帧都重写 `_core.visible / _glow.visible`
	#    （按 fade），手动藏内核保持不住。
	c.set_physics_process(false)
	# 炮口中点：**自己算**，不去调 `BeamCannon._midpoint()`（私有静态、跨类名依赖）。
	var mzs: Array[Vector3] = fb.cannon_muzzles()
	var mid := Vector3.ZERO
	for o: Vector3 in mzs:
		mid += o
	if not mzs.is_empty():
		mid /= float(mzs.size())
	var muzzle: Vector3 = fb.global_transform * mid
	var dir: Vector3 = fb.cannon_aim_dir()
	# 取景点沿柱往外挪：躲开炮口光晕与飞溅粒子（它们都近白）
	var focus: Vector3 = muzzle + dir * CANNON_FOCUS_M
	var core: MeshInstance3D = c._core
	var flare: Node3D = c._flare
	var off := Vector3(1.0, 0.35, 0.0)
	c.visible = false
	var a: Image = await _shot(focus, CAM_SIZE_CANNON, off)
	c.visible = true
	if core != null:
		core.visible = false
	if flare != null:
		flare.visible = false
	var b: Image = await _shot(focus, CAM_SIZE_CANNON, off)
	if core != null:
		core.visible = true
	if flare != null:
		flare.visible = true
	var b_full: Image = await _shot(focus, CAM_SIZE_CANNON, off)
	if a == null or b == null or b_full == null:
		return {"img": null, "stats": {}, "how": "抓图失败"}
	var st := _merge_all(_masked_stats(a, b), a, b)
	var st_full := _masked_stats(a, b_full)
	st["hue_full"] = st_full["hue_mode"]
	st["rbn_full"] = st_full["rbn"]
	st["layered"] = core != null
	return {"img": b_full, "stats": st, "how": "生产路径 fire_cannon()，只留外晕量色"}


## 摆一台真的 FlightBody（抄 `saber_color_shot.gd`，坑一并抄）：
## 不能摆 y=0（`CRASH_ALTITUDE` 会判撞海并 destroy）、`set_physics_process(false)`
## 要在 `add_child` 之后、`_hover_pose` 不补会拍到竖直站立。
func _mount(p: SuitProfile) -> FlightBody:
	var holder := Node3D.new()
	add_child(holder)
	var fb := FlightBody.new()
	fb.team = 0
	fb.profile = p
	holder.add_child(fb)
	fb.global_transform = Transform3D(Basis(), Vector3(0.0, 3000.0, 0.0))
	fb.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	fb._hover_pose = fb.flight_pitch_deg
	# ⚠️ 冻住模型动画：`AnimationPlayer` 是**自己走时钟**的节点，只关 `_physics_process`
	#    拦不住它。不冻的话 A/B 之间姿态已变，差集掩码会把整台机体算成"被测物贡献的像素"。
	if fb.model_anim != null and fb.model_anim.player != null:
		fb.model_anim.player.speed_scale = 0.0
	return fb


## 把机体自己的网格**全部隐藏**，只留待测的光束（返回隐藏了多少个）。
##
## ⚠️ 为什么必须隐藏：差集掩码只保证"掩码里是光束贡献的像素"，
## **保证不了"光束下面是空的"** —— 而 ADD 是 `dst = 底下的颜色 + 这层的颜色`。
func _hide_suit(root: Node) -> int:
	var n := 0
	for ch in root.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).visible:
			(ch as MeshInstance3D).visible = false
			n += 1
		n += _hide_suit(ch)
	return n


# ================================================================ 掩码统计

## 只统计「A 与 B 有差异」且「有足够饱和」的像素。
func _masked_stats(a: Image, b: Image, sat_min := SAT_MIN) -> Dictionary:
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var n := 0
	var sat := 0.0
	var sx := 0.0
	var sy := 0.0
	var srbn := 0.0
	var dn := 0
	var hi_n := 0
	var hi_hist := PackedInt32Array()
	hi_hist.resize(HUE_BINS)
	var hist := PackedInt32Array()
	hist.resize(HUE_BINS)
	for y in H:
		for x in W:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := absf(cb.r - ca.r) + absf(cb.g - ca.g) + absf(cb.b - ca.b)
			if d <= MASK_EPS:
				continue
			dn += 1
			if cb.s < sat_min:
				continue
			sr += cb.r
			sg += cb.g
			sb += cb.b
			srbn += (cb.r - cb.b) / maxf(maxf(cb.r, maxf(cb.g, cb.b)), 0.001)
			if cb.s >= HI_SAT:
				hi_n += 1
				hi_hist[clampi(int(cb.h * HUE_BINS), 0, HUE_BINS - 1)] += 1
			n += 1
			sat = maxf(sat, cb.s)
			var hh := cb.h
			hist[clampi(int(hh * HUE_BINS), 0, HUE_BINS - 1)] += 1
			var ang := hh * TAU
			sx += cos(ang)
			sy += sin(ang)
	var k := float(maxi(n, 1))
	var conc := sqrt(sx * sx + sy * sy) / k
	var best := 0
	for i in HUE_BINS:
		if hist[i] > hist[best]:
			best = i
	var hi_best := 0
	for i in HUE_BINS:
		if hi_hist[i] > hi_hist[hi_best]:
			hi_best = i
	var hk := float(maxi(hi_n, 1))
	return {"n": n, "dn": dn, "sat": sat, "conc": conc, "n_hi": hi_n,
			"hue_hi": (float(hi_best) + 0.5) * (360.0 / float(HUE_BINS)),
			"share_hi": float(hi_hist[hi_best]) / hk,
			"share": float(hist[best]) / k,
			"hue_mode": (float(best) + 0.5) * (360.0 / float(HUE_BINS)),
			"r": sr / k, "g": sg / k, "b": sb / k, "rbn": srbn / k,
			"hue": fposmod(atan2(sy, sx), TAU) / TAU * 360.0}


## 色相上的圆形距离（度，0..180）。
##
## ⚠️ 公式必须是 `|((a−b+180) mod 360) − 180|`。写成 `180 − |((a−b+540) mod 360) − 180|`
## 会算成**补角**（把 8° 报成 172°），于是"同色"判据拿到的数全是反的。
func _hue_gap(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)


## 把"**不带饱和门槛**"的那一份均值并进 `st`（键 `r_all / g_all / b_all`）。
##
## ★ 为什么必须补这一份：`SAT_MIN` 会把**过曝成近白的实心区**滤掉，
## 只看剩下的边缘像素。而那批像素的**多少**取决于颜色自己"抗夹逼"的能力 ——
## 实测（本轮）：粉紫的过曝形态是 `(1.0, ~0.7, 1.0)`（**饱和还在**，几千个像素过门槛）；
## 而蓝（`accent`）的过曝形态是 `(0.95, 1.0, 1.0)`（**饱和只有 0.05**，全被滤掉）
## ⇒ 蓝那一格只剩几百个**背景附近的暗像素**，色相读数没有代表性。
## 不带门槛的均值把所有"被测物贡献的像素"都算进来，于是两排能用**同一把尺子**比。
func _merge_all(st: Dictionary, a: Image, b: Image) -> Dictionary:
	var all := _masked_stats(a, b, 0.0)
	st["r_all"] = all["r"]
	st["g_all"] = all["g"]
	st["b_all"] = all["b"]
	return st


func _judge(ok: bool, label: String, cond: bool, s: Dictionary,
		s2: Dictionary = {}) -> bool:
	var extra := "hueMode=%.1f° share=%.2f n=%d sat=%.2f rgb=(%.2f, %.2f, %.2f) RB=%+.3f" % [
		s.get("hue_mode", -1.0), s.get("share", 0.0), s.get("n", 0), s.get("sat", 0.0),
		s.get("r", 0.0), s.get("g", 0.0), s.get("b", 0.0), s.get("rbn", 0.0)]
	extra += "｜全掩码均值(%d 个)=(%.2f, %.2f, %.2f)" % [
		s.get("dn", 0), s.get("r_all", 0.0), s.get("g_all", 0.0), s.get("b_all", 0.0)]
	if not s2.is_empty():
		extra += " | hueMode2=%.1f° (Δ=%.1f°)" % [
			s2.get("hue_mode", -1.0), _hue_gap(s.get("hue_mode", -1.0), s2.get("hue_mode", -1.0))]
	print("  %s  %s   [%s]" % ["PASS" if cond else "FAIL", label, extra])
	return ok and cond


# ================================================================ 工具

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(BG.x, BG.y, BG.z)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.84, 0.87, 0.94)
	env.ambient_light_energy = 1.20
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 20.0, 0.0)
	key.light_energy = 1.8
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, 200.0, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.74, 0.84, 1.0)
	add_child(fill)


## 定机位拍一张：正交投影、`cam_size` 固定 ⇒ 格与格可直接比。
##
## `off_dir` 决定从哪一侧看。**必须垂直于武器轴向**：光束沿机体的 −Z 飞，
## 所以取景方向要有 +X 分量才有侧视；默认那个 `(1, 0.42, 0.95)`（军刀用的斜前上）
## 在这里会**顺着弹道看过去**，把 52 m 的光柱压成一个点。
func _shot(focus: Vector3, cam_size: float, off_dir: Vector3) -> Image:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cam_size
	cam.near = 0.05
	cam.far = 30000.0
	add_child(cam)
	cam.global_position = focus + off_dir.normalized() * (maxf(cam_size, 1.0) * 2.6)
	cam.transform = cam.transform.looking_at(focus, Vector3.UP)
	cam.current = true
	for f in 3:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	cam.queue_free()
	await get_tree().physics_frame
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	return img


## 给每格画一圈边框（纯视觉，方便肉眼对数格子）。
func _draw_frame(img: Image, x0: int, y0: int, w: int, h: int) -> void:
	var c := Color(0.35, 0.38, 0.42)
	for x in w:
		img.set_pixel(x0 + x, y0, c)
		img.set_pixel(x0 + x, y0 + h - 1, c)
	for y in h:
		img.set_pixel(x0, y0 + y, c)
		img.set_pixel(x0 + w - 1, y0 + y, c)
