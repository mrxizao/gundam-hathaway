class_name SuiteGfxLedger
extends RefCounted
## 画质记账：**看得见的东西下面那层算术**。
##
## ⚠️ 命名按**主题**，不按轮次 —— 见 `test_runner.gd` 注册表里的红字：
## 本仓库有并行会话，两边都按轮次占号时撞过一次，一个套件被同名文件**整个覆盖**
## 而 runner 照样绿。第一版叫 `suite_round22.gd`（撞上了「地图放大」的 Round22 标签），
## 已改回语义名。
##
## 这一套不测玩法，测的全是"画质优化攒下的、只在注释里成立的事实"：
##
##   1. **奈奎斯特账**（轮 4）：几何层能表达的最短波长 = 格距 × 2。
##      违反它的那几处（沙漠 λ210 / 靶场 λ800·λ400 / 海面 λ1400）当时都是
##      "写了个注释说它有多细"，**没有任何东西拦得住下一轮再加一个更细的层**。
##      → 落成 `CALIB` 表 + 这里用**算术**检查（不是 grep 字符串）。
##
##   2. **贴海薄雾**（批 J · 用户："海面上方一带要有一层薄薄的雾气"）。
##      → 钉枚举归属 / 全局体积雾开关 / 底面贴水面 / 只有太平洋图开。
##      ⚠️ **更要紧的是钉住"它不能是 no-op"**：原值 `0.00028` 在四个高度上
##       **逐位为零**（不是淡，是像素差精确为 0），而当时没有任何东西拦得住这件事。
##      → 这里把"实测的第一格可见剂量"落成下界断言（见 `_mist()` 的 ⑤）。
##
##   3. **颜色斑驳**（批 I · 轮 7 · 用户："地面看起来都是大色块，不够细致"）。
##      → 钉"围绕 1.0 居中"（不改平均亮度）、"冷暖反推"、三层倍频、放在植被之前。
##
##   4. **新增细节不许扰动既有随机序列**：`_rng` 是整张图共享的一条序列，
##      任何新增抽取都会平移后续所有消费者。这一轮新增的 6 个函数**全部**用局部 RNG。
##
## ⚠️ 与 `suite_gfx_map` 一样：**测不了"好不好看"**（无头环境 RenderingServer 是 dummy）。
##    这里钉的是接线、源码结构、运行期属性，以及"账"能不能算平。
##    真正的观感判据在 `tests/pixprobe.tscn` 的真渲染 A/B（`--mist` / `--mottle` / `--topcam`）。

const CALIB := "GfxLedger / 奈奎斯特账（CALIB 表）"
const MIST := "GfxLedger / 贴海薄雾（批 J）"
const MOTTLE := "GfxLedger / 颜色斑驳（批 I · 轮 7）"
const RNG_SAFE := "GfxLedger / 新增细节不扰动共享随机序列"
const PROBE := "GfxLedger / 探针能力（画质 A/B 的旋钮）"


static func run(t: T, host: Node) -> void:
	t.suite(CALIB)
	_calib(t)
	t.suite(MIST)
	await _mist(t, host)
	t.suite(MOTTLE)
	_mottle(t)
	t.suite(RNG_SAFE)
	_rng_safe(t)
	t.suite(PROBE)
	_probe(t)


# ------------------------------------------------------------- 奈奎斯特账

## `CALIB` 把"几何能表达多细"变成可算的数据。
##
## 为什么必须用**算术**而不是 grep：这几处的错法一模一样 —— 代码里写着
## `1.0/210.0`（一个看着很小的频率），但**没人算过它对应多少米、要几格**。
## 字符串检查在"注释说 210 m"和"真的 210 m"之间分不出来；只有把
## `size / seg` 和 `1 / frequency` 摆在一起比，才算把账算平。
static func _calib(t: T) -> void:
	var calib: Array = WorldBuilder.CALIB
	t.eq(calib.size(), 4, "四张图各一条（%d）" % calib.size())
	var names := []
	for e in calib:
		names.append(String(e["name"]))
	for want in ["沙漠沙丘", "靶场地坪", "城市地面", "海面长涌浪"]:
		t.ok(names.has(want), "账上有「%s」这一条" % want)
	for e in calib:
		var nm := String(e["name"])
		var size := float(e["size"])
		var seg := int(e["seg"])
		var waves: Array = e["waves"]
		t.gt(seg, 0, "[%s] 分段数 > 0" % nm)
		t.gt(size, 0.0, "[%s] 场地边长 > 0" % nm)
		if seg <= 0 or size <= 0.0:
			continue
		var cell := size / float(seg)
		var nyq := cell * 2.0
		t.gt(waves.size(), 0, "[%s] 至少列出 1 个波长分量" % nm)
		# ⚠️ **每一条**都要过账，不只是最短那条：一条 λ=850 的粗波
		#    混在 [3000, 60] 里，只看 min 的写法会"通过"，但渲染出来的
		#    60 m 那一层照样是走样的高频。
		for wv in waves:
			t.ok(float(wv) >= nyq,
				"[%s] λ=%.0f m ≥ 奈奎斯特 %.0f m（格距 %.1f m × 2）"
					% [nm, float(wv), nyq, cell])
		# 排列顺序是**从粗到细**，末项 = 最短的一条 = 决定奈奎斯特裕度的那条。
		var wmin := 1.0e20
		for wv in waves:
			wmin = minf(wmin, float(wv))
		t.near(float(waves[waves.size() - 1]), wmin, 0.001,
			"[%s] waves 按从粗到细排列（末项就是最短的一条）" % nm)
		# 裕度：最短那条至少要有 2 格。等于 2 就是"贴边通过"（城市地面 690 m
		#  对 301 m 格距 = 2.29 格），工程上允许，但低于 2 一律不许。
		t.gt(wmin / cell, 2.0, "[%s] 最短一层至少占 2 格（%.2f 格）" % [nm, wmin / cell])
	# 城市地面那条是**唯一贴边**的（2.29 格）。这条断言的作用是：将来谁把
	# `CITY_GROUND_SEG` 调小、或者把四层里的 0.0091 调大，这里会**先红**，
	# 而不是等他拍完图发现地表在抖。
	var city := {}
	for e in calib:
		if String(e["name"]) == "城市地面":
			city = e
	if not city.is_empty():
		var cell_c := float(city["size"]) / float(city["seg"])
		var wmin_c := 1.0e20
		for wv in city["waves"]:
			wmin_c = minf(wmin_c, float(wv))
		t.between(wmin_c / cell_c, 2.0, 4.0,
			"城市地面最短一层是**刻意贴边**的（%.2f 格，落在 2~4 格）"
				% (wmin_c / cell_c))


# ------------------------------------------------------------- 贴海薄雾

static func _mist(t: T, host: Node) -> void:
	var src := _strip_comments(_src("res://scripts/world/world_builder.gd"))

	# ① 枚举常量的**归属**。这不是洁癖 —— 写错位置的后果是 **Parse Error**，
	#    整个 `world_builder.gd` 加载失败（`--check-only` 报
	#    `Cannot find member "FOG_VOLUME_SHAPE_BOX" in base "FogVolume"`），
	#    而错误信息不会告诉你正确的类在哪。真值在 `RenderingServer` 上。
	t.ok(src.contains("RenderingServer.FOG_VOLUME_SHAPE_BOX"),
		"`shape` 用 `RenderingServer.FOG_VOLUME_SHAPE_BOX`（真值所在）")
	t.not_ok(src.contains("FogVolume.FOG_VOLUME_SHAPE_BOX"),
		"不许写成 `FogVolume.FOG_VOLUME_SHAPE_BOX` —— 该成员**不存在**")

	# ② 全局体积雾必须常开。`FogVolume` 只是"允许 raymarch 的一块区域"，
	#    没有 `volumetric_fog_enabled` 它**什么都不画**，而且不报错。
	t.ok(src.contains("env.volumetric_fog_enabled = true"),
		"全局 `volumetric_fog_enabled` 常开（否则 FogVolume 静默不生效）")
	# 关着的那块不参与 raymarch ⇒ 非太平洋图零代价。
	t.ok(src.contains("_sea_mist.visible = on") and src.contains("not on:"),
		"开关落在 `FogVolume.visible` 上 ⇒ 另外三张图**一点代价都不付**")

	# ③ 运行时：不建图（`_ready()` 里不建默认图）也能验节点与几何。
	var root := Node3D.new()
	root.name = "MistProbe"
	host.add_child(root)
	var w := WorldBuilder.new()
	root.add_child(w)
	await host.get_tree().process_frame

	var fv: FogVolume = w._sea_mist
	t.ok(fv != null, "`_ready()` 里建出了 SeaMist（FogVolume）节点")
	if fv == null:
		return
	t.eq(String(fv.name), "SeaMist", "节点名是 SeaMist")
	t.eq(fv.shape, 3, "shape == 3（`RenderingServer.FOG_VOLUME_SHAPE_BOX`）")
	t.ok(fv.material is FogMaterial, "挂的是 FogMaterial（不是 StandardMaterial3D）")

	# ⚠️ **建好之后不是恒为 `false`**：`_ready()` 末尾会
	# `apply_map(MapDef.by_id(initial_map))`，而 `initial_map` 就是**太平洋**
	# ⇒ 海雾在 `_ready()` 之后**已经是开着的**。
	# （第一版断言写死 `visible == false`，被这一条打红 —— 那是**断言错**，不是代码错。
	#  教训：断言"默认值"之前，先读 `_ready()` 到底做了什么，别拿"构造函数的初值"当默认值。）
	#
	# ⚠️ **`WorldBuilder.initial_map` 是会编译失败的写法**（实测：整个套件一条断言都没跑，
	#    报 `Parse Error: Cannot find member "initial_map" in base "WorldBuilder"`）。
	#    它是个**实例变量**（`var initial_map := MapDef.Id.PACIFIC`），
	#    而 GDScript **只允许通过类名访问 `const` / `static`**。
	#    ⇒ 必须从刚建出来的那个实例上读（`w.initial_map`）—— 这样也更准确：
	#    断言的本来就是"这个实例的初始图是哪张"。
	var init_map := MapDef.by_id(w.initial_map)
	var want_on := init_map.time_of_day != null and init_map.time_of_day.sea_mist_density > 0.0
	t.eq(fv.visible, want_on,
		"`_ready()` 按**初始图**「%s」定开关（该图有海雾 = %s ⇒ visible = %s）"
			% [init_map.name_cn, str(want_on), str(fv.visible)])

	# ④ 换成**没有**海雾的时段：立刻不可见（这才是"另外三张图零代价"的真正判据）。
	w.apply_time_of_day(TimeOfDay.night())
	t.eq(fv.visible, false,
		"换成 `TimeOfDay.night()`（`sea_mist_density` = 0）⇒ 不可见（不参与 raymarch）")

	# ⑤ 灌太平洋时段：可见，且**底面贴水面**。
	var pac := MapDef.pacific()
	t.ok(pac.time_of_day != null, "太平洋图有时段")
	if pac.time_of_day == null:
		return
	t.gt(pac.time_of_day.sea_mist_density, 0.0,
		"太平洋的 `sea_mist_density` = %.5f > 0" % pac.time_of_day.sea_mist_density)
	# ⑤ **密度必须高过"实测的第一格可见剂量"** —— 这一条是本套件里最该有的一条。
	#
	# ⚠️ 为什么需要一个**下界**而不是"把当前值抄一遍"：
	# 原工程值 `0.00028` 是照着 `exp(-density × 光程)` 推出来的，而
	# `FogMaterial.density` **不是每米消光系数**（真值：有效光深 ≈ 3e-3 × density × 光程）。
	# 于是它小了约 300 倍，在 45 / 200 / 800 / 1500 m **四个高度上全是逐位为零**
	# —— 一张"开着"的图和一张"关掉"的图 **md5 相同**。
	# 而当时**没有任何断言能发现这件事**（所有断言都在检查"接线"与"数据流"，
	# 没有一条在问"这几个数到底能不能在画面上留下一个像素"）。
	#
	# 下界取 **0.0035**（实测第一格可见的剂量：地平线那行 +840%）。
	# 判据是**大于等于它**而不是等于 —— 将来把 0.0060 调到 0.0050 或 0.0080
	# 都不该红（那是审美），但调回 0.0014（实测方向**反了**：地平线 −36%，变暗）
	# 或 0.00028 必须红。这条红的时候，正确的反应是去跑
	# `tests/pixprobe.tscn --seacam=45 --mist=<候选>` 重拍一张，
	# 而不是把下界改小。
	const DOSE_FIRST_VISIBLE := 0.0035
	const DOSE_MILK := 0.0200
	t.between(pac.time_of_day.sea_mist_density, DOSE_FIRST_VISIBLE, DOSE_MILK,
		"密度 %.5f 落在 [%.4f, %.4f]：下界是实测第一格可见剂量（低于它是**吸光**、方向反了），"
			% [pac.time_of_day.sea_mist_density, DOSE_FIRST_VISIBLE, DOSE_MILK]
		+ "上界是实测的**糊掉**区（0.0240 俯视整帧 −27.5%、0.5 整屏牛奶）")
	# ⑤b 边缘淡出必须是 0：本工程尺度下雾板的六个面永远在体雾积分范围之外
	#     ⇒ 淡出**没有东西可淡**，只会把板内的近处白削一层。
	#     实测同剂量 0.55 → 整帧 +12.10%，0.0 → +17.98%（白吃掉三分之一）。
	#     佐证：把雾板边长从 90 km 提到 200 km，输出**逐位不变**。
	t.eq(pac.time_of_day.sea_mist_edge_fade, 0.0,
		"边缘淡出 = 0（盒子边界在 4 km 光程之外、永远看不见 ⇒ 它只会削减雾本身）")
	# ⑤c 顺带钉住"不许用体雾光程去救高空看不见"这条**已否掉**的路：
	#     实测 4000 → 32000 在出生点机位上确实从"逐位为零"变成 +1.7%~+9.6%，
	#     但那不是一条带，是**整屏均匀抬亮**（光程一给长，全局本底雾
	#     `volumetric_fog_density` 也一起被积分进去：只加光程不加海雾的负对照
	#     自己就动了 −1.3%），而且 32000/64 切片 = 500 m ⇒ 比 160 m 的板还厚，
	#     采样直接走样。⇒ 保持 4000，把这一层老老实实当**低空效果**。
	t.near(w._env.volumetric_fog_length, 4000.0, 0.001,
		"体雾光程保持 4000 m（抬它会把全局本底雾一起抬亮，且板比切片还薄）")
	w.apply_time_of_day(pac.time_of_day)
	t.eq(fv.visible, true, "太平洋 ⇒ 雾板可见")
	t.near(fv.position.y, fv.size.y * 0.5, 0.001,
		"底面**贴水面**：中心 y = 全高 / 2（`FogVolume.size` 是全尺寸不是半尺寸）")
	t.near(fv.position.x, 0.0, 0.001, "雾板水平居中（x）")
	t.near(fv.position.z, 0.0, 0.001, "雾板水平居中（z）")
	t.gt(fv.size.x, 10000.0, "跨度 %.0f m —— 要盖住可见海面，不是一块小板"
		% fv.size.x)
	t.near(fv.size.y, pac.time_of_day.sea_mist_top, 0.001,
		"厚度 = `sea_mist_top`（%.0f m）" % pac.time_of_day.sea_mist_top)
	var mfm := fv.material as FogMaterial
	if mfm != null:
		t.near(mfm.density, pac.time_of_day.sea_mist_density, 1.0e-9,
			"材质密度跟着数据走")
		t.near(mfm.height_falloff, pac.time_of_day.sea_mist_falloff, 1.0e-6,
			"高度衰减跟着数据走")
		t.near(mfm.edge_fade, pac.time_of_day.sea_mist_edge_fade, 1.0e-6,
			"边缘淡出跟着数据走")
		# ⚠️ 反照率必须**比海亮**：薄雾靠"比背景亮"才立得住那条海天分界带。
		var alb := mfm.albedo
		var hz := TimeOfDay.night().ocean_horizon
		t.gt(alb.r + alb.g + alb.b, hz.r + hz.g + hz.b,
			"雾的反照率（%.3f）**亮于**夜海地平线色（%.3f）"
				% [alb.r + alb.g + alb.b, hz.r + hz.g + hz.b])

	# ⑥ 只有太平洋图带这层雾。
	for mid in MapDef.all_maps():
		var mm := MapDef.by_id(mid)
		var on := mm.time_of_day != null and mm.time_of_day.sea_mist_density > 0.0
		if mm.id == MapDef.Id.PACIFIC:
			t.eq(on, true, "「%s」开着海雾" % mm.name_cn)
		else:
			t.eq(on, false, "「%s」**不**开海雾（贴海雾在那儿没有着力点）" % mm.name_cn)

	root.queue_free()


# ------------------------------------------------------------- 颜色斑驳

static func _mottle(t: T) -> void:
	var sh := _strip_comments(_src("res://shaders/terrain.gdshader"))
	var src := _strip_comments(_src("res://scripts/world/world_builder.gd"))

	# ① 两个旋钮存在，且**默认 0 = 关**（老调用点行为一字不变）。
	t.ok(sh.contains("uniform float mottle"), "shader 有 `mottle` 强度旋钮")
	t.ok(sh.contains("uniform float mottle_wavelength"), "shader 有 `mottle_wavelength` 波长旋钮")

	# ② 三层倍频，lacunarity 4。
	var body := _func_body(sh, "float _mottle_field(")
	t.gt(body.length(), 0, "找到 `_mottle_field()` 的实现")
	t.ok(body.contains("lam * 0.25") and body.contains("lam * 0.0625"),
		"三层：λ / (λ/4) / (λ/16)（lacunarity 4）")
	t.eq(body.count("_oct_fade("), 3,
		"三层**各自**按屏幕像素淡出（`_oct_fade` 出现 %d 次）—— "
		% body.count("_oct_fade(")
		+ "最细那层在 3 km 机位只有零点几像素，不剔除就是整屏噪点")
	t.ok(body.contains("max(wsum, 0.0001)"),
		"除以「当前活着的权重之和」而不是总权重 —— 远处全被淡出时不会除零，"
		+ "也不会因为淡掉了两层就整体变暗")
	# ③ 均值为 0：末尾减 0.5（`_vnoise` 的值域是 [0,1]）。
	t.ok(body.contains("- 0.5"),
		"返回值**居中**（末尾 `- 0.5`）⇒ 明暗乘子均值 = 1，**平均亮度不动**")
	t.ok(body.contains("+ vec2(") and body.count("vec2(") >= 3,
		"三层各带一个**独立偏移**（否则三层的零点重合、会叠出一块亮斑）")

	# ④ fragment 接线：围绕 1.0 居中 + 冷暖反推。
	t.ok(sh.contains("base *= 1.0 + m * 2.0 * mottle"),
		"明暗乘子 = `1 + m·2·mottle`（围绕 1.0 居中）")
	t.ok(sh.contains("base.r *= 1.0 + warm") and sh.contains("base.b *= 1.0 - warm"),
		"r 与 b **反向**偏（亮斑偏暖、暗斑偏冷）—— 只调明暗会读成「脏」")
	t.ok(sh.contains("float warm = m * 1.10 * mottle"),
		"色偏幅度受同一个 `mottle` 控制（拧到 0 时明暗与色偏一起消失）")

	# ⑤ 位置：斑驳必须在**植被之前**（否则 `--mottle` 的 A/B 会连带改草色）。
	var i_mottle := sh.find("if (mottle > 0.0)")
	var i_veg := sh.find("if (veg_amount > 0.0)")
	t.gt(i_mottle, 0, "fragment 里有斑驳块")
	t.gt(i_veg, 0, "fragment 里有植被块")
	t.ok(i_mottle < i_veg,
		"斑驳排在植被**之前**（%d < %d）⇒ 两组 A/B 正交" % [i_mottle, i_veg])
	# 用未 warp 的坐标（与植被同理：斑驳是矿物成分差异，不是层理走向）。
	t.ok(sh.contains("vec2 mp = world_pos.xz"),
		"斑驳用**未 warp 的** `world_pos.xz`（不跟着层理方向拉丝）")

	# ⑥ 工厂：第 11/12 参数有默认值 ⇒ 老调用点不传也不会变。
	t.ok(src.contains("mottle := 0.0") and src.contains("mottle_wavelength := 24.0"),
		"`_terrain_material()` 用**默认参数**扩展（老调用点行为一字不变）")
	t.ok(src.contains("mat.set_shader_parameter(\"mottle\", mottle)"),
		"工厂真的把参数灌进了材质")

	# ⑦ 四张图各一套值，且**远景地坪刻意不接**。
	for c in ["MOTTLE_CITY", "MOTTLE_RANGE", "MOTTLE_DESERT", "MOTTLE_ROCK"]:
		t.ok(src.contains("const %s :=" % c), "有常数 `%s`" % c)
	t.eq(src.contains("MOTTLE_FAR"), false,
		"**没有** `MOTTLE_FAR` —— 远景地坪刻意不接这一层（它在雾里，"
		+ "斑驳会浮出一层沙沙的噪，比纯色更假）")
	var far := _func_body(src, "func _build_ground_plane(")
	t.gt(far.length(), 0, "找到 `_build_ground_plane()`")
	t.eq(far.contains("MOTTLE"), false,
		"远景地坪的调用点确实没传斑驳参数（不是「定义了常数但忘了接」）")
	# 波长按地表材质类型分档：城市最碎（14 m）、沙漠最粗（40 m）。
	var lens := {}
	for c in ["MOTTLE_CITY_LEN", "MOTTLE_RANGE_LEN", "MOTTLE_DESERT_LEN", "MOTTLE_ROCK_LEN"]:
		var v := float(src.split("const %s := " % c)[1].split("\n")[0])
		lens[c] = v
		t.between(v, 4.0, 200.0, "`%s` = %.0f m（几米一块的小色斑，不是地貌尺度）" % [c, v])
	t.lt(lens["MOTTLE_CITY_LEN"], lens["MOTTLE_DESERT_LEN"],
		"城市最碎（%.0f m）< 沙漠最粗（%.0f m）—— 沥青/混凝土 vs 风成分选的沙"
			% [lens["MOTTLE_CITY_LEN"], lens["MOTTLE_DESERT_LEN"]])


# ------------------------------------------------------------- 防回退

## `_rng` 是**整张图共享**的一条序列（`_ready()` 里 `seed = 20260917`）。
##
## 任何新增的 `_rng.` 抽取都会**平移后续所有消费者** —— 表现为"别的图突然变了样"，
## 而且几乎不可能从 diff 里看出来（改的是一个 3 行的小函数，坏的是 800 行之外的地形）。
## 所以这一轮新增细节时立的规矩是：**一律用按序号派生的局部 RNG**。
static func _rng_safe(t: T) -> void:
	var src := _strip_comments(_src("res://scripts/world/world_builder.gd"))
	var fns := [
		# 轮 3 新增
		"func _ruin_damage(",
		"func _build_sea_marks(",
		"func _add_buoy(",
		"func _add_light_platform(",
		"func _build_sea_stacks(",
		"func _add_sea_stack(",
	]
	for fn in fns:
		var body := _func_body(src, fn)
		t.gt(body.length(), 0, "找到 `%s`" % fn.trim_suffix("("))
		t.eq(body.contains("_rng."), false,
			"`%s` 不碰共享序列 `_rng`（用按序号派生的局部 RNG）" % fn.trim_suffix("("))
	# 局部 RNG 必须是**按序号派生**的，不能是一个固定种子（那样所有废墟一个样）。
	var ruin := _func_body(src, "func _ruin_damage(")
	t.ok(ruin.contains("lr.seed") and ruin.contains("i *"),
		"废墟破损的局部 RNG 按**序号**派生（`lr.seed = 9100 + i * 7919` 这类）——"
		+ "固定种子会让 16 段废墟长得一模一样")
	# 海蚀柱的扰动是**解析正弦**：9 段网格上放高频噪声必然走样。
	var stack := _func_body(src, "func _add_sea_stack(")
	t.ok(stack.contains("sin(") and not stack.contains("Noise"),
		"海蚀柱的顶点扰动是**解析正弦**（9 段网格容不下高频噪声）")


# ------------------------------------------------------------- 探针能力

## 画质改动的判据只可能来自**真渲染**（无头环境的 RenderingServer 是 dummy）。
## 所以探针必须能单独拧每一层 —— 这一节钉的是"旋钮都还在"。
static func _probe(t: T) -> void:
	var px := _strip_comments(_src("res://tests/pixprobe.gd"))
	for k in ["--mottle", "--mottlelen", "--mist", "--misttop", "--mistfall",
			"--mistemit", "--misted", "--mistspan", "--foglen", "--fogspread",
			"--veg", "--topcam"]:
		t.ok(px.contains("\"%s\"" % k), "探针认识 `%s`" % k)
	# `--mist=0` 必须真的关掉整块板（而不只是把密度设 0）——
	# 密度 0 的 FogVolume 仍要参与 raymarch，A/B 的"关"那一半会白花钱。
	t.ok(px.contains("_sea_mist.visible = md > 0.0"),
		"`--mist=0` 直接 `visible = false`（而不是把密度设成 0）")
	t.ok(px.contains("set_shader_parameter(\"mottle\""),
		"`--mottle` 灌的是 shader uniform")

	# ⚠️⚠️ **守卫条件必须列全它自己那一族的所有旋钮** —— 这一条是一类真实 bug 的不变量。
	#
	# 探针的旋钮是**成族**写的：一整块 `if _overrides.has("mist") or ...:` 里连着处理
	# `mist` / `misttop` / `mistfall` / `mistemit` / `misted` / `mistspan`。
	# 新增一个时只写了处理代码、**忘了加进守卫条件**，后果是：
	# **只传这个新旋钮时整块根本不执行** —— 连读都没读，值也没灌。
	# 它表现出来与"这个旋钮没接线"**完全一样**（A/B 逐位相同），
	# 于是排查会一路往 shader / 引擎那边找，而真相是一行 `or`。
	#
	# 本轮的实测版本：`--misted` / `--mistspan` 漏在守卫条件外，只因为 EF* 那批图
	# 恰好都带着 `--mist=0.0060` 才"顺带生效" —— 也就是**靠同事参数生效**，
	# 这种 A/B 的数字是对的，但结论"这个旋钮有效"是**错的**（它可能无效）。
	var gi := px.find("if _overrides.has(\"mist\")")
	t.gt(gi, 0, "找到海雾那一段的守卫条件")
	if gi > 0:
		var guard := px.substr(gi, 320)
		for k in ["mist", "misttop", "mistfall", "mistemit", "misted", "mistspan"]:
			t.ok(guard.contains("has(\"%s\")" % k),
				"守卫条件里列了 `--%s`（漏列 ⇒ 只传它时整块不执行，表现像旋钮没接线）" % k)

	# 轮 6 新开的一族：港区泛光灯（`--portlights` / `--porten`）。
	# 同一条不变量、同一个理由 —— 新旋钮只写处理代码、忘进守卫条件，
	# 表现与"旋钮完全没接线"一模一样（A/B 逐位相同），而真相是一行 `or`。
	var gi6 := px.find("if _overrides.has(\"portlights\")")
	t.gt(gi6, 0, "找到港区泛光灯那一段的守卫条件")
	if gi6 > 0:
		var guard6 := px.substr(gi6, 160)
		for k in ["portlights", "porten", "portshadow"]:
			t.ok(guard6.contains("has(\"%s\")" % k),
				"守卫条件里列了 `--%s`（漏列 ⇒ 只传它时整块不执行，表现像旋钮没接线）" % k)


# ------------------------------------------------------------- 源码辅助

static func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


## 去掉 `#` 与 `//` 之后的注释（字符串里的 # 不处理 —— 本工程没有这种写法）。
static func _strip_comments(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var l := String(line)
		var i := l.find("#")
		if i >= 0:
			l = l.substr(0, i)
		out += l + "\n"
	return out


## 取 `head` 之后到**同一层级的下一个函数**之间的正文。
##
## ⚠️ 两个源语言要一起兼容：
##   · GDScript：函数头是 `func x(`（列 0），体用 Tab 缩进，下一个函数也是列 0 的 `func `
##   · GLSL（`terrain.gdshader`）：函数头是 `float x(...)`（列 0），体用 Tab 缩进，
##     **但收尾的 `}` 也在列 0**
## 所以判据是"**列 0 的、非空的行**"就停 —— 对 GDScript 停在下个 `func`，
## 对 GLSL 停在收尾的 `}`。只判 `func ` 的话，在 shader 上会一路吃到文件末尾
##（`count()` 数出来的次数会虚高，断言看着还挺绿）。
static func _func_body(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var rest := src.substr(i + head.length())
	var out := ""
	var started := false
	for l in rest.split("\n"):
		var s := String(l)
		if s.begins_with("func "):
			break
		if started and s.length() > 0 and s[0] != "\t" and s[0] != " ":
			break
		started = true
		out += s + "\n"
	return out
