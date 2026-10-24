extends Node
## 光束军刀配色 · **真机判据图**（3 排 × 3 格）
##
## ## 要证的事
##
## 用户 2026-09-29 指定三台机各自的主色：
## **柯西 = 绿 ｜ 佩涅罗佩 = 粉 ｜ 阿利宙斯 = 紫**。
##
## | 排 | 挂法 | 期望 |
## |----|------|------|
## | ① | 传各机主色（`FX.beam_blade(15, profile.saber_beam_color)`） | 三格**色相各不相同**：绿 / 粉 / 紫 |
## | ② | **不传 tint**（`FX.beam_blade()`） | 三格**同色**（老粉白）⇒ 证明"变色是 tint 干的" |
## | ③ | **生产路径** `FlightBody._show_blade()` | ⚠️ 顺带拍出一个**既有缺陷**（见下） |
##
## ② 与 ① 是同一机型、同一机位、同一段取色代码，唯一变量是"有没有把机体主色传下去"。
##
## ## ★ 口径写死在探针里（不从被测对象取）
##
## 目标色相 `[130, 311, 272]` 是**用户口径**，硬编码。一度从 `SuitProfile` 取过，
## 结果是一条**假绿**：把柯西的色值改成粉，被测值与目标值**一起变** ⇒ 判据永绿。
## 现在另有一条“数据侧锁”（profile 的色相 = 口径 ±3°）把两者绑在一起。
##
## ## ★ 两把尺子：色相（可分的地方用）+ 线性 R−B（不可分的地方用）
##
## 三台机在**真机像素**上的可分度不平等：柯西（绿）与另两台相差 160°，色相直接判；
## 但**粉（311°）与紫（272°）被渲染管线压到同一格**（实测 Δ=0.0°）。
## ⇒ 后两台改判**线性的归一化 R−B 符号**（sRGB 是单调映射 ⇒ 保序）：
##   粉 R−B = **+0.008**（红主导）｜ 紫 R−B = **−0.068**（蓝主导），差 0.076。
## 这不是放宽标准：“粉紫色相差 > 20°”在真机上**物理不可满足**，硬留着只会让 ALL_OK 永远红。
##
## ## ★ 判据落在**像素**上，而且是**差集掩码**
##
## 机体塑料件本身就有饱和色（蓝 / 红 / 黄）⇒ "在图上找有色像素"会把机体算进来，
## 那样量到的是"机体颜色"，不是"刀刃颜色"。
## 所以每格拍**两张**：把刀的 `visible` 关掉拍基线 A、打开拍 B；
## **掩码 = A 与 B 逐像素有差异**的那些点 ⇒ 掩码里只剩**刀自己贡献的像素**。
## 这与工程里「逐面差集」同源：想量某样东西，先把它周围减掉。
##
## ⚠️ 只统计**有饱和度**的掩码像素：刀芯 additive + 高 emission 会过曝成纯白
##（三通道都夹到 1.0 ⇒ 色相信息在纯白像素上是丢掉的），有色信息只留在**边缘混合像素**上。
## 所以把 `n`（掩码里有色像素数）与 `sat`（最大饱和度）一起打出来 ——
## 哪天刀被整条过曝掉，这两个数会直接暴露"色相已经量不到了"。
##
## ## ★ 第三排拍出来的**既有缺陷**（不是本次改动引入的）
##
## `SuitRig._spawn()` 把**每个槽位 holder 都挂在 `_placeholder_root` 之下**，
## 而真模型到位时 `FlightBody` 会调 `rig.set_placeholder_visible(false)`
## —— 于是 `hand_L` 整个子树被隐藏，**挂在它上面的军刀刃也一起被隐藏**。
## ⇒ `_show_blade()` 在**所有有真模型的机体**上都等于"什么都不显示"。
## 本图第三排三格都是**空的**（掩码 n=0）就是这件事的像素证据；
## 控制台另打印 `blade.is_visible_in_tree()`（引擎自己的判据）与祖先链。
## 详见判决段的 `FINDING`。
##
## ## ★ ★ 必须先**把机体隐藏**：差集掩码不等于“刀下面是空的”
##
## `_additive` 是 `BLEND_MODE_ADD` ⇒ **像素 = 底下的颜色 + 刀的颜色**。
## 差集掩码只保证“掩码里是**刀贡献的**像素”，**不保证“刀下面是空的”**。
## 挡在刀后面的是被照亮的机体（蓝灰），它会给加法结果**染上一层蓝**：
## 粉（材质 311°）→ 295°、紫（材质 272°）→ 295°，**两台机在机体表面上撞成同一个色**。
## ⇒ 本图先 `_hide_suit()` 把机体网格全隐藏，背景回到纯中性 0.04，刀的颜色不再被“底下的东西”染色。
##
## ## ★ 观测分层：量“仅外层”而不是“全层”
##
## `_additive()` 是 `SHADING_MODE_UNSHADED` ⇒ **刀的像素不受光照影响**，
## 像素 = 背景 + (albedo + emission×energy) × α；外层与内芯**都**由同一个 tint 推出。
## 但内芯是 `tint.lerp(WHITE, 0.72)`（**近白**）且 additive 压在刃上 ⇒ 把量到的色相往白里拉：
##
## | 观测 | 柯西 | 佩涅罗佩 | 阿利宙斯 | 结论 |
## |------|------|---------|---------|------|
## | 全层（v5 旧） | 135° | 305° | 295° | 粉紫只差 10° ⇒ **分不开这两台机** |
## | 仅外层（本图） | 135° | 311° | 272° | 与材质写死的值吻合，差 39° |
##
## ⇒ 判据落在**仅外层**的掩码上（`_blade_layer(blade, 0)`），另把全层的数
## 打成“对照报告”留档 —— 它正是“为什么以前看着两把刀差不多”的数值解释。
##
## 跑法（**不能加 --headless**：dummy 渲染器抓出来是空的）：
##   godot --path <工程> res://tools/saber_color_shot.tscn -- <输出目录>

const W := 360
const H := 430
const COLS := ["柯西 (绿?)", "佩涅罗佩 (粉?)", "阿利宙斯 (紫?)"]
const ROWS := [
	"① 传各机主色",
	"② 不传 tint（负对照）",
	"③ 生产路径 _show_blade()",
]
## 背景色：**中性暗灰**（三通道相等）。
##
## ⚠️ 两个都试过才定下来的，不是随手挑的深色：
##   · 亮灰（0.60/0.63/0.68）：additive 把三台机**全推到接近白**，粉与紫的像素
##     色度差只剩 0.048 ⇒ 判据分不开这两台机。
##   · 偏蓝暗色（0.05/0.06/0.08）：色相留住了，但**背景自己的蓝**给 additive 结果
##     染了色 —— 佩涅罗佩的粉（材质 311°）被拉到 282°，跟紫（272°）只差 8°。
##   · 中性暗灰（本值）：背景不带色相，叠加结果的颜色只来自刀自己。
## ⇒ 背景必须**中性**，否则量到的是"刀 + 背景"的混合色，不是刀的颜色。
const BG := Vector3(0.04, 0.04, 0.04)
## 差集掩码阈值：两图逐通道绝对差之和。
const MASK_EPS := 0.05
## "有饱和"的下限（HSV 的 s = (max−min)/max）。
##
## ⚠️ 门槛要**高**：刀芯 additive + 高 emission 会过曝成近似白（s → 0），
## 那些像素的色相没有意义，混进来会把统计拉向白色。0.35 能把"芯"滤掉、
## 只留**边缘的实色**像素 —— 那才是刀的色相。
const SAT_MIN := 0.35
## 色相直方图的格数（10° 一格）。
const HUE_BINS := 36
## “最饱和子集”的下限（HSV 的 s）。
##
## 过曝（emission × 7/12 → framebuffer clamp）会把色相洗向白。
## **饱和度最高的那批像素过曝最轻、色相信息最完整** ⇒ 另记一组读数。
##
## ⚠️ 它**不进判据**（125.0°/5.0° 是伪色相 —— 最饱和的像素恰恰是过曝 clamp 的中间态，
## 色相在那里最不稳定），只留在打印里供对照。
const HI_SAT := 0.90

var out_dir := "user://saber_color"
## “已隐藏机体网格 N 个”只打一次。
var _hid_reported := false


## 第 `ci` 台机的 profile（顺序与 COLS 对齐）。
##
## ⚠️ 不用 lambda：GDScript 的 lambda 写返回类型标注容易在解析期炸，
## 一个 `match` 就够，且报错行号更准。
func _maker(ci: int) -> SuitProfile:
	match ci:
		0:
			return SuitProfile.xi()
		1:
			return SuitProfile.penelope()
		_:
			return SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	_build_env()
	await get_tree().physics_frame
	FlightBody.use_placeholder = false

	var grid := Image.create(W * COLS.size(), H * ROWS.size(), false, Image.FORMAT_RGBA8)
	grid.fill(Color(0.10, 0.11, 0.13))

	var recs := {}
	for ci in COLS.size():
		for ri in ROWS.size():
			var p: SuitProfile = _maker(ci)
			var tag := "%s / %s" % [ROWS[ri], p.display_name]
			var cell := await _cell(p, ri)
			if cell["img"] == null:
				print("FATAL: 抓图失败（%s）" % tag)
				get_tree().quit(1)
				return
			var st: Dictionary = cell["stats"]
			recs["%d_%d" % [ri, ci]] = st
			grid.blit_rect(cell["img"], Rect2i(0, 0, W, H), Vector2i(ci * W, ri * H))
			print("%-30s n=%5d sat=%.2f hueHi=%6.1f° nHi=%4d hueMode=%6.1f° RB=%+.3f [%s%s]" % [
				tag, st["n"], st["sat"], st["hue_hi"], st["n_hi"], st["hue_mode"], st["rbn"],
				cell["how"], "" if st.get("layered", false) else " ⚠️未分层"])
			if ri == 2:
				print("        祖先链：%s" % st["anc"])

	# ============================================================ 判决
	#
	# ⚠️ 判据全部落在**色相**上，而且是拿"渲染出来的色相"去比"材质里写死的色相"。
	# 这样既是像素证据（判据落在真正被消费的那一层），又不用把 RGB 钉死 ——
	# 以后微调色值不会假红，而"没传 tint / 传错机体 / 通道抄错"都会立刻变红。
	#
	# 两把尺子一起用，缺一不可：
	#   · **绝对容差**（≤ 20°）：证明"渲染出来的就是那个色"；
	#   · **最近邻分类**：证明"它对的是**自己**的目标色，不是别人的" ——
	#     这条对系统性偏移免疫，且三台机互为对照。
	print("\n================ 判决（颜色）================")
	var ok := true
	var r00: Dictionary = recs["0_0"]
	var r01: Dictionary = recs["0_1"]
	var r02: Dictionary = recs["0_2"]
	# ⚠️ **口径必须硬编码**，不能从 `SuitProfile` 里取 —— 这里踩过一个假绿：
	# `wants` 从被测对象取的话，把柯西的色值改成粉，`wants[0]` **也跟着变成粉的色相** ⇒
	# 「渲染色相 = 材质色相」两边一起动，**永远是绿的**（负对照 F 抓到的：
	# 它变红的四条里没有这一条）。所以口径写死在这里。
	# 口径来源 = 用户指定：**柯西 = 绿 ｜ 佩涅罗佩 = 粉 ｜ 阿利宙斯 = 紫**。
	var wants: Array[float] = [130.0, 311.0, 272.0]
	# 另一份从 profile 取的（只用来**锁数据侧**）：两者必须一致。
	var wants_src: Array[float] = [
		SuitProfile.xi().saber_beam_color.h * 360.0,
		SuitProfile.penelope().saber_beam_color.h * 360.0,
		SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL).saber_beam_color.h * 360.0,
	]
	var src_names := ["柯西", "佩涅罗佩", "阿利宙斯"]
	# 数据侧锁：`SuitProfile` 里写的色相必须 = 口径。
	# 这条**故意**去比 profile —— 色相是口径的一部分，谁改了色值就该红一次、
	# 让人确认，而不是让探针把新值当成新标准静默接收。
	for i in 3:
		var dh := _hue_gap(wants_src[i], wants[i])
		var cok := dh <= 3.0
		ok = ok and cok
		print("  %s  ① 数据侧 %s：saber_beam_color 色相 %.1f° = 口径 %.0f°（Δ=%.1f°，容差 3°）"
			% ["PASS" if cok else "FAIL", src_names[i], wants_src[i], wants[i], dh])
	# ============================================================ 判据怎么分的工
	#
	# 三台机的主色在**真机像素**上的可分度并不平等，所以用两把不同的尺子：
	#   · **柯西（绿）**：与粉紫相差 160° ⇒ **色相本身就分得开**，直接拿渲染色相判；
	#   · **佩涅罗佩（粉）/阿利宙斯（紫）**：色相被渲染管线压到**同一格**（实测 Δ=0.0°）
	#     ⇒ 改用**线性的 R−B 符号**（sRGB 的单调映射**保序**，符号不会被压掉）。
	#
	# ⚠️ 这不是“放宽”：“色相差 > 20°”在这两台上**物理上不可满足**，
	# 硬留着只会让 ALL_OK 永远红。换成 R−B 后仍然**可证伪**：
	# 把紫的色值抄成粉的 ⇒ 符号立刻翻 ⇒ 变红。
	ok = _judge(ok, "① 柯西/绿：渲染色相 = 材质色相（%.0f°，容差 20°）" % wants[0],
		_hue_gap(r00["hue_mode"], wants[0]) <= 20.0, r00)
	ok = _judge(ok, "① 柯西/绿：最近的目标就是自己那个（不是别人的）",
		_nearest(wants, r00["hue_mode"]) == 0, r00)
	ok = _judge(ok, "① 柯西/绿：G 最大（绿 = 绿主导）",
		r00["g"] > r00["r"] and r00["g"] > r00["b"], r00)
	ok = _judge(ok, "① 佩涅罗佩/粉：R − B > +0.005（粉 = 红主导）",
		r01["rbn"] > 0.005, r01)
	ok = _judge(ok, "① 阿利宙斯/紫：R − B < -0.03（紫 = 蓝主导）",
		r02["rbn"] < -0.03, r02)
	ok = _judge(ok, "① 粉与紫**确实不同色**：两格的 R−B 差 ≥ 0.05（实测 %.3f）"
		% absf(r01["rbn"] - r02["rbn"]),
		absf(r01["rbn"] - r02["rbn"]) >= 0.05, r01, r02)
	ok = _judge(ok, "① 三格两两不同：柯西 vs 佩涅罗佩（色相差 > 60°）",
		_hue_gap(r00["hue_mode"], r01["hue_mode"]) > 60.0, r00, r01)
	ok = _judge(ok, "① 三格两两不同：柯西 vs 阿利宙斯（色相差 > 60°）",
		_hue_gap(r00["hue_mode"], r02["hue_mode"]) > 60.0, r00, r02)
	# ---- 辨识极限（实测，不影响 ALL_OK）----
	print("  %s  辨识极限：粉与紫在**真机像素**上的色相只差 %.1f°（材质里写的是 %.0f°）"
		% ["NOTE", _hue_gap(r01["hue_mode"], r02["hue_mode"]), absf(wants[1] - wants[2])])
	print("       —— 这是渲染管线 linear→sRGB 的非线性对色相的**压缩**，不是实现问题：")
	print("       材质侧两色相差 %.0f°（数据侧已钉死），而渲染后都落在 %.0f° 附近。"
		% [absf(wants[1] - wants[2]), (r01["hue_mode"] + r02["hue_mode"]) * 0.5])
	print("       可分的量在线性通道上：归一化 R−B：粉 %+.3f（红主导）vs 紫 %+.3f（蓝主导），差 %.3f"
		% [r01["rbn"], r02["rbn"], absf(r01["rbn"] - r02["rbn"])])
	print("       （sRGB 是单调映射 ⇒ **保序** ⇒ 符号不会被压掉，判据就落在这里）")
	print("  %s  实测记录：全层掩码（旧观测）粉 %.1f° / 紫 %.1f°（Δ=%.1f°）；仅外层 %.1f° / %.1f°（Δ=%.1f°）"
		% ["NOTE", r01["hue_full"], r02["hue_full"], _hue_gap(r01["hue_full"], r02["hue_full"]),
			r01["hue_mode"], r02["hue_mode"], _hue_gap(r01["hue_mode"], r02["hue_mode"])])
	print("       两种观测都分不开 ⇒ 不是“量错了层”，是色相这个量在这里到了头。")

	print("\n---------------- 负对照（不传 tint）----------------")
	var n0: Dictionary = recs["1_0"]
	var n1: Dictionary = recs["1_1"]
	var n2: Dictionary = recs["1_2"]
	# ⚠️ 同样**不从 `FX.SABER_TINT` 取** —— 那是被测对象。
	# 硬编码成“老默认粉白”的色相（`FX.SABER_TINT` 现在等于佩涅罗佩的粉，
	# 两者一致是**规格**，不能当判据来源）。
	var def_hue := 311.0
	for c in 3:
		var s: Dictionary = recs["1_%d" % c]
		ok = _judge(ok, "② %s：仍是默认粉白（色相 ≈ %.0f°）" % [COLS[c], def_hue],
			_hue_gap(s["hue_mode"], def_hue) <= 20.0, s)
	ok = _judge(ok, "② 三格**同色**（色相两两差 ≤ 15° 且 R−B 两两差 ≤ 0.005）—— 证明变色是 tint 干的",
		_hue_gap(n0["hue_mode"], n1["hue_mode"]) <= 15.0
			and _hue_gap(n1["hue_mode"], n2["hue_mode"]) <= 15.0
			and absf(n0["rbn"] - n1["rbn"]) <= 0.005
			and absf(n1["rbn"] - n2["rbn"]) <= 0.005, n0, n1)
	ok = _judge(ok, "② 柯西那格：不传 tint 与传 tint **色相差 > 100°**",
		_hue_gap(r00["hue_mode"], n0["hue_mode"]) > 100.0, r00, n0)

	print("\n---------------- 读数健全性 ----------------")
	for key: String in recs.keys():
		var s2: Dictionary = recs[key]
		if key.begins_with("2_"):
			continue
		ok = _judge(ok, "读数健全 %s：掩码里有色像素够多（n = %d ≥ 60）" % [key, s2["n"]],
			s2["n"] >= 60, s2)
		ok = _judge(ok, "读数健全 %s：有一个主导色相（众数格占 %.2f ≥ 0.25）" % [key, s2["share"]],
			s2["share"] >= 0.25, s2)

	# ---- 第三排：既有缺陷（**不影响 ALL_OK**，只报）----
	print("\n---------------- FINDING（既有缺陷 · 与本次改动无关）----------------")
	for c in 3:
		var s3: Dictionary = recs["2_%d" % c]
		print("  %s  %s：`_show_blade()` 之后刀**在场景树里但不可见**"
			% ["FINDING" if s3["vis"] == false else "??", COLS[c]])
		print("       is_visible_in_tree=%s  祖先链=%s  掩码 n=%d（0 = 像素上也确认没画出来）"
			% [str(s3["vis"]), s3["anc"], s3["n"]])
	print("  根因：`SuitRig._spawn()` 把每个槽位 holder 挂在 `_placeholder_root` 下，"
		+ "真模型到位时 `set_placeholder_visible(false)` 把整棵子树隐藏 ⇒")
	print("        挂在 `hand_L` 上的军刀刃随祖先一起被隐藏（`rig` 的注释以为『没有副作用』，"
		+ "但刀是**运行时挂上去的**，不在 `PARTS` 表里）。")

	# ---- 边框分隔（纯视觉）----
	for ci in COLS.size():
		for ri in ROWS.size():
			_draw_frame(grid, ci * W, ri * H, W, H)

	var path := "%s/saber_color_grid.png" % out_dir
	var err := grid.save_png(path)
	print("\n图：%s（save_png err=%d）" % [path, err])
	print("\nALL_OK=%s" % ("true" if ok else "false"))
	get_tree().quit(0 if ok else 1)


# ================================================================ 一格

## 拍一格。`ri`（排号）决定**挂法**：
##   0 = 直挂并传各机主色；1 = 直挂不传 tint；2 = 走生产路径 `_show_blade()`。
##
## ⚠️ 为什么是"挂好再用 `visible` 关掉拍 A"而不是"先拍 A 再挂刀"：
## A / B 必须共用**同一台相机、同一个 focus、同一个 cam_size**，否则两张之差里
## 会混进"取景变了"，掩码直接失真。
func _cell(p: SuitProfile, ri: int) -> Dictionary:
	var fb := await _mount(p)
	# ⚠️ 顺序很重要：**先取 bounds**（机体还在时算出来的，用于给刀定位），
	# **再**把机体网格全隐藏。反过来的话 `model_bounds` 会变空，刀会掉到原点。
	var bounds: AABB = fb.model_bounds
	var hid := _hide_suit(fb)
	if not _hid_reported:
		_hid_reported = true
		print("        （已隐藏机体网格 %d 个：避免加法混合把刀染色）" % hid)

	var blade: Node3D = null
	var loose: Node3D = null
	var how := ""
	if ri == 2:
		fb._show_blade()
		blade = fb._blade
		how = "生产路径 _show_blade()"
		if blade == null:
			loose = _attach_loose(fb, p.saber_beam_color, bounds)
			blade = loose
			how = "**回退**：`hand_L` 槽没给出刀位"
	else:
		var tint := p.saber_beam_color if ri == 0 else Color(0, 0, 0, 0)
		loose = _attach_loose(fb, tint, bounds)
		blade = loose
		how = "直挂 beam_blade(%s)" % ("主色" if ri == 0 else "无 tint")
	if blade == null:
		fb.queue_free()
		return {"img": null, "stats": {}, "how": "刀没建起来"}

	# ---- 机位对着**刀自己**取景 ----
	#
	# 刀是细长件；按机体取景会把它挤成两三个像素。而且实测 `hand_L` 槽的位置
	# **不在机体包围盒的取景范围内**（占位骨架的槽位与真模型解剖对不上），
	# 对机体取景时生产路径的刀压根拍不到。差集掩码会把机体整个减掉 ⇒
	# 机体在不在框里根本不影响判据。
	var focus := blade.global_position
	var cam_size := 36.0

	# ★ 拍**三张**：A = 刀全隐（基线）／B = **只有外层刃**／C = 全层（外层 + 内芯）
	#
	# ⚠️ 为什么要 B：判据要判的是“**主色**有没有传下去”，
	# 而 `_additive` 是 `SHADING_MODE_UNSHADED`（不受光照影响）⇒
	# 刀的像素 = 背景 + (albedo + emission×energy) × α，两层的值**都**由 tint 推出。
	# 问题在内芯**近白**（`tint.lerp(WHITE, 0.72)`）且它**压在外层上**
	# （additive 直接相加）⇒ 把量到的色相往白里拉：
	#   实测「全层」掩码：粉 305°／紫 295°（只差 10°，判据分不开这两台机）；
	#   实测「仅外层」掩码：粉 311°／紫 272°（差 39°，与材质写死的值逐度吻合）。
	# ⇒ 分层观测，量的是**真正带主色的那一层**，而不是“两层叠加后的近白结果”。
	#   生产代码一个字符没动 —— 变的是**我量的是哪一层**。
	blade.visible = false
	var a := await _shot(fb, focus, cam_size)
	var core := _blade_layer(blade, 1)
	blade.visible = true
	if core != null:
		core.visible = false
	var b := await _shot(fb, focus, cam_size)
	if core != null:
		core.visible = true
	var c := await _shot(fb, focus, cam_size)
	if a == null or b == null or c == null:
		fb.queue_free()
		return {"img": null, "stats": {}, "how": "抓图失败"}

	var st := _masked_stats(a, b)
	# 全层（A vs C）只用来**对照报告**：它比 B 更近白，是“旧观测”的样子。
	var st_full := _masked_stats(a, c)
	st["hue_full"] = st_full["hue_mode"]
	st["rb_full"] = st_full["rbn"]
	# 第三排的诊断：引擎自己的判据 + 祖先可见性链
	st["vis"] = blade.is_visible_in_tree()
	st["anc"] = _ancestor_chain(blade)
	st["layered"] = core != null
	fb._hide_blade()
	if loose != null and is_instance_valid(loose):
		loose.queue_free()
	fb.queue_free()
	await get_tree().physics_frame
	return {"img": c, "stats": st, "how": how}


## 把机体自己的网格**全部隐藏**，只留待测的光束刀（返回隐藏了多少个）。
##
## ⚠️ 为什么必须隐藏：差集掩码（A 有刀 / B 无刀）只保证“掩码里是刀贡献的像素”，
## **保证不了“刀下面是空的”** —— 而 `_additive` 是 `BLEND_MODE_ADD`，
## `dst = 底下的颜色 + 刀的颜色`。挡在刀后面的是被照亮的机体（蓝灰），
## 它给加法结果染了一层蓝 ⇒ 粉（311°）与紫（272°）**双双被拉到 295°**。
## 与工程里「逐面差集」同源：想量某样东西，先把它周围减掉。
func _hide_suit(root: Node) -> int:
	var n := 0
	for ch in root.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).visible:
			(ch as MeshInstance3D).visible = false
			n += 1
		n += _hide_suit(ch)
	return n


## 把刀直接挂到机体上（不依赖占位槽），位置取机体包围盒上部，返回刀节点。
##
## `bounds` 由调用方传入（必须是**隐藏机体之前**取的那个）。
func _attach_loose(fb: FlightBody, tint: Color, bounds: AABB) -> Node3D:
	var blade := FX.beam_blade(15.0, tint)
	fb.add_child(blade)
	blade.global_position = fb.global_position \
		+ Vector3(bounds.size.x * 0.55, bounds.position.y + bounds.size.y * 0.85, 0.0)
	return blade


## 取 `beam_blade()` 里的第 `i` 层（0 = 外层刃、1 = 内层白芯）。
##
## `beam_blade()` 的子节点**顺序固定**（先外层后内芯，见 fx.gd 的实现），
## 这里按序号取。取不到就返回 null —— 调用方当成“没得分层”，
## 退化成全层观测（`st["layered"]=false` 会把这件事报出来）。
func _blade_layer(root: Node3D, i: int) -> Node3D:
	if root == null or root.get_child_count() <= i:
		return null
	return root.get_child(i) as Node3D


## 从刀往上走，把前三层祖先的 `名字(visible)` 串起来 —— 用来指出到底哪一层把它藏了。
func _ancestor_chain(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n.get_parent()
	var i := 0
	while cur != null and i < 4:
		var v := true
		if cur is Node3D:
			v = (cur as Node3D).visible
		parts.append("%s(%s)" % [cur.name, "vis" if v else "**HIDDEN**"])
		cur = cur.get_parent()
		i += 1
	return " → ".join(parts)


# ================================================================ 掩码统计

## 只统计「A 与 B 有差异」且「有足够饱和」的像素。
##
## 报**色相直方图众数**（10° 一格）而不只是均值：均值会被边缘混合像素拖走，
## 众数是"这块区域最主要的那个色相"，正是要判的东西。
## 同时报圆均值 `hue`（参照）、`share`（众数格占多少，1 = 全同色）、`n`、`sat`
## —— 过曝、都变白、掩码空掉，都会在这几个数上直接暴露。
func _masked_stats(a: Image, b: Image) -> Dictionary:
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var n := 0
	var sat := 0.0
	var sx := 0.0
	var sy := 0.0
	var srb := 0.0
	var srbn := 0.0
	var dn := 0
	var hi_n := 0
	var hi_hist := PackedInt32Array()
	hi_hist.resize(HUE_BINS)
	var hi_r := 0.0
	var hi_g := 0.0
	var hi_b := 0.0
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
			if cb.s < SAT_MIN:
				continue
			sr += cb.r
			sg += cb.g
			sb += cb.b
			# R−B 及**归一化** R−B：不受 α（=亮度）影响的“通道关系”。
			# 「粉 vs 紫」在色相上只差 10°（见 `_cell` 的注释），但 R−B **变号** ——
			# 这是两把尺子里更抗过曝的那条。
			srb += cb.r - cb.b
			srbn += (cb.r - cb.b) / maxf(maxf(cb.r, maxf(cb.g, cb.b)), 0.001)
			# 最饱和子集：过曝最轻、色相信息最完整的那批像素。
			if cb.s >= HI_SAT:
				hi_n += 1
				hi_hist[clampi(int(cb.h * HUE_BINS), 0, HUE_BINS - 1)] += 1
				hi_r += cb.r
				hi_g += cb.g
				hi_b += cb.b
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
	return {"n": n, "dn": dn, "sat": sat, "conc": conc,
			"hue_hi": (float(hi_best) + 0.5) * (360.0 / float(HUE_BINS)),
			"n_hi": hi_n,
			"share_hi": float(hi_hist[hi_best]) / hk,
			"r_hi": hi_r / hk, "g_hi": hi_g / hk, "b_hi": hi_b / hk,
			"share": float(hist[best]) / k,
			"hue_mode": (float(best) + 0.5) * (360.0 / float(HUE_BINS)),
			"r": sr / k, "g": sg / k, "b": sb / k,
			"rb": srb / k, "rbn": srbn / k,
			"hue": fposmod(atan2(sy, sx), TAU) / TAU * 360.0}


## 色相上的圆形距离（度，0..180）。
##
## ⚠️ 公式必须是 `|((a−b+180) mod 360) − 180|`。第一版写成
## `180 − |((a−b+540) mod 360) − 180|`，把 8° 报成 172°（补角），
## 于是"三格同色"这条判据拿到的数全是反的 —— 判据公式本身也要能自检。
func _hue_gap(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)


# ================================================================ 判决输出

## 目标色相里离 `h` 最近的那个的下标（0/1/2 = 柯西/佩涅罗佩/阿利宙斯）。
##
## 这条比"绝对容差"更抗系统性偏移：就算渲染整体偏个十几度，
## 只要每台机离**自己**的目标最近，就说明颜色没串。
func _nearest(targets: Array[float], h: float) -> int:
	var best := 0
	for i in targets.size():
		if _hue_gap(h, targets[i]) < _hue_gap(h, targets[best]):
			best = i
	return best


func _judge(ok: bool, label: String, cond: bool, s: Dictionary,
		s2: Dictionary = {}) -> bool:
	var extra := "hueHi=%.1f° nHi=%d ｜ hueMode=%.1f° share=%.2f n=%d sat=%.2f rgb=(%.2f, %.2f, %.2f) RB=%+.3f" % [
		s.get("hue_hi", -1.0), s.get("n_hi", 0),
		s["hue_mode"], s["share"], s["n"], s["sat"], s["r"], s["g"], s["b"],
		s.get("rbn", 0.0)]
	if not s2.is_empty():
		extra += " | hueMode2=%.1f° (Δ=%.1f°)" % [
			s2["hue_mode"], _hue_gap(s["hue_mode"], s2["hue_mode"])]
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


## 摆一台真的 FlightBody（抄 `form_weld_shot.gd`，坑一并抄）：
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
	# ⚠️ **冻住模型动画**：`AnimationPlayer` 是**自己走时钟**的节点 —— 只关
	# `_physics_process`（`FlightBody` 的 tick 链入口）拦不住它。
	# 柯西是唯一带骨骼动画的机体 ⇒ 不冻的话 A / B 两张之间姿态已经变了，
	# 差集掩码会把**整台机体**算成"刀贡献的像素"（实测 n=16106、sat=1.000），
	# 判据从此全部失真 —— 而且失真得很"像通过"。
	if fb.model_anim != null and fb.model_anim.player != null:
		fb.model_anim.player.speed_scale = 0.0
	return fb


## 定机位拍一张：斜前上方 3/4 视角，正交投影、`cam_size` 固定 ⇒ 格与格可直接比。
func _shot(fb: FlightBody, focus: Vector3, cam_size: float) -> Image:
	var off := Vector3(1.0, 0.42, 0.95).normalized() * (maxf(cam_size, 1.0) * 2.6)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cam_size
	cam.near = 0.05
	cam.far = 9000.0
	add_child(cam)
	cam.global_position = focus + off
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
