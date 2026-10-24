class_name SuiteGfxMap
extends RefCounted
## 地图画质（1.2.3 批 E / G）：地表细节、云的主光受光、海面浪尖透光、城市立面。
##
## ⚠️ **这一套测不了"好不好看"** —— 那是人眼的事（见 `tests/pixprobe.gd` 开头那段：
## 无头环境的 RenderingServer 是 dummy，shader 根本不编译、不产生一个像素）。
##
## 它钉的是三件**在无头环境里可以钉住**的事：
##   ① **接线**：uniform 有没有真的从 GDScript 灌进 shader、灌的是不是该灌的值、
##      换时段之后会不会跟着更新；
##   ② **源码事实**：shader 里那几处最容易写错、而且**写错了画面会静默变形**的地方
##     （切向基在地面上退化成零向量、坡度符号反了把凸的照成凹的、远处摩尔纹…）。
##     这类错没有异常、没有报错，只有"看起来不太对"，而画面对比工具又判不了"对不对"。
##   ③ **隔离性**：新加的随机抽取不许动既有序列 ——
##      这是本次最容易**静默搞坏**的东西（楼高/配色/朝向全会移位，
##      而 `suite_round20` 与 `suite_worldscale` 正是拿那套序列在断言）。

## 细节类 uniform 是**浮点**，比较用这个容差。
const EPS := 0.0001


static func run(t: T, host: Node) -> void:
	t.suite("MapGfx / 地表细节接线")
	_terrain_detail(t)
	t.suite("MapGfx / shader 源码事实")
	_shader_facts(t)
	t.suite("MapGfx / 城市立面材质")
	_city_facade_material(t)
	t.suite("MapGfx / 立面不扰动既有随机序列")
	_lot_isolation(t)
	t.suite("MapGfx / 真地图上的接线（沙漠 + 城市两张）")
	await _built_maps(t, host)


# ============================================================ ① 纯函数接线

## `_terrain_material()` 的第 5/6 个参数。
##
## 最关键的一条是**默认值必须为 0**：`detail_strength` 一开，地表就不再是纯顶点色 ——
## 而工程里有一批调用点是 3 个参数的（那种调用点根本不该有细节语义）。
## 默认 0 让"忘了传"等于"行为不变"，也让像素探针的 `--detail=0` 能把这一项单独拧掉。
static func _terrain_detail(t: T) -> void:
	var w := WorldBuilder.new()
	# 不传 → 关
	var off := w._terrain_material(Color.WHITE, 0.9, true) as ShaderMaterial
	t.near(float(off.get_shader_parameter("detail_strength")), 0.0, EPS,
		"不传 detail 时细节强度是 0（老调用点行为一字不变）")
	t.near(float(off.get_shader_parameter("detail_grain")), 0.0, EPS,
		"不传 detail 时颗粒也是 0")
	# 传了 → 就是传的值；颗粒按它的 **0.75** 给（同一份噪声，不多花采样）
	#
	# ⚠️ 波长传 **380**（≠ shader 默认 1280）：传成默认值就分不出"透传对了"
	# 还是"根本没传、读到的只是 shader 默认"。而 `get_shader_parameter()` 读不到
	# shader 源码里的默认值（返回 null）⇒ 那种情况会读成 null 而不是 1280，
	# 所以这里必须用一个**既不是默认、也不是任何调用点**的值。
	var on := w._terrain_material(Color.WHITE, 0.9, true, 0.5, 1.10, 380.0) as ShaderMaterial
	t.near(float(on.get_shader_parameter("detail_strength")), 1.10, EPS, "细节强度 = 传入值")
	t.near(float(on.get_shader_parameter("detail_grain")), 0.825, EPS,
		"颗粒 = 强度的 3/4（批 H · 轮 2 从 1/2 提上来，理由见 `_terrain_material` 的注释）")
	t.near(float(on.get_shader_parameter("detail_wavelength")), 380.0, EPS,
		"最粗层波长 = 传入值（单位是**米**；旧口径是 1/米的频率倍率）")
	# ⚠️ 新参数加在第 5/6 位，**不能把第 4 位（镜面）顶掉** ——
	# 全是 float，写错位不报错，只会静默改变高光。
	t.near(float(on.get_shader_parameter("specular_value")), 0.5, EPS,
		"第 4 个参数（镜面）没有被新参数挤掉")
	t.near(float(off.get_shader_parameter("roughness_value")), 0.9, EPS, "粗糙度照旧")
	# 材质表要登记（换图时 `_refresh_cloud_uniforms()` 与探针都要遍历它）
	t.eq(w._terrain_mats.size(), 2, "两份地表材质都登记进了 `_terrain_mats`")

	# ---- 材质分层（轮 2）：工厂要转发第 7~9 位 ----
	# ⚠️ 同样刻意用**不是默认值**的数（默认 0/3.0/0.0）：
	# 传成默认值就分不出"透传对了"还是"根本没传"。
	var layer := w._terrain_material(Color.WHITE, 0.9, true, 0.5, 1.0, 320.0,
		0.85, 3.4, 0.15) as ShaderMaterial
	t.near(float(layer.get_shader_parameter("mat_blend")), 0.85, EPS, "分层强度 = 传入值")
	t.near(float(layer.get_shader_parameter("mat_stretch")), 3.4, EPS, "拉伸倍率 = 传入值")
	t.near(float(layer.get_shader_parameter("mat_angle")), 0.15, EPS, "层理方向 = 传入值")
	t.near(float(off.get_shader_parameter("mat_blend")), 0.0, EPS,
		"不传第 7~9 位时分层是**关**的 —— 远景地坪那种老调用点行为一字不变")
	t.eq(w._terrain_mats.size(), 3, "分层那一份也登记进了 `_terrain_mats`")

	# ---- 批 H · 轮 2：四条「防回退」断言 ----
	# 这几条全是**实拍归因**出来的结论 —— 光看代码读不出"为什么不能那样写"，
	# 而且四个错误版本都很符合直觉。钉进测试，下次照着直觉改回去时立刻红。
	var sh := _strip_comments(_src("res://shaders/terrain.gdshader"))
	# ① 颗粒必须**围绕 0.5 居中**调制。写成 `1.0 - detail_grain * h0` 是纯压暗：
	#    实测把沙漠地表压暗 47%（`regions.g20.mean_lum` 0.0915 → 0.0487），
	#    于是"颗粒越强、地面越黑"，永远调不出"有颗粒但不暗"。
	t.ok(sh.contains("base *= 1.0 - detail_grain * (h0 - 0.5);"),
		"albedo 颗粒是**围绕 0.5 居中**调制（均值为 0 ⇒ 真的不动亮度基线），"
		+ "而不是 `1.0 - detail_grain * h0` 那种纯压暗")
	# ② 五层倍频的权重必须**接近平坦**。粗层主导（0.4375）在远处对、在近景错得厉害：
	#    最粗层（沙丘 1280 m）在几十米的视场里跨不到一个晶格 ⇒ 它那 43.75% 的权重是常数，
	#    还在归一化里把真正有变化的细层稀释掉（实测：`--detail=0` 与开着**肉眼无差别**）。
	t.ok(sh.contains("DET_W0 = 0.2600") and sh.contains("DET_W4 = 0.1400"),
		"五层权重接近平坦（0.26/0.25/0.19/0.16/0.14，和为 1），不是粗层主导的"
		+ " 0.4375/0.25/0.125/0.125/0.0625")
	# ③ 层理方向必须**分区**（`turn` 那一项）。全局常数方向实测读成"整屏同向拉丝"：
	#    沙丘被打成一片平行斜条纹，像木纹/丝绸，不像风成地貌。
	t.ok(sh.contains("smoothstep(0.42, 0.58, _vnoise(wp * 0.00009))"),
		"层理方向按一层 λ≈11 km 的噪声**分区**并平滑过渡（不是全局常数 `mat_angle`）")
	# ④ 高度场网格必须设 smooth group。`_ground_tri` 只给顶点色、不给法线，
	#    `generate_normals()` 默认**按面**算 ⇒ 300 m 一个三角面的地表是硬边多面体；
	#    近景那些"收敛到消失点的直线明暗块"就是它 —— 而且它**长得很像材质分层**，
	#    会把 A/B 归因搅混（轮 2 第一版"城市分层偏弱"的结论就是被它污染的）。
	var wsrc := _strip_comments(_src("res://scripts/world/world_builder.gd"))
	t.eq(wsrc.count("st.set_smooth_group(0)"), 5,
		"五处**高度场曲面**（地表 / 巨岩 / 城市地形 / 岛屿 / 海蚀柱）都设了 smooth group；"
		+ "`_build_box` 那处是立方体，**故意不设**（设了箱体会被磨成球）")
	w.free()


## 城市立面材质：类别 → 参数的映射，以及**按（颜色+类别）缓存**。
static func _city_facade_material(t: T) -> void:
	var w := WorldBuilder.new()
	var col := Color(0.265, 0.275, 0.295)
	var conc := w._city_facade_material(col, WorldBuilder.Facade.CONCRETE)
	var glass := w._city_facade_material(col, WorldBuilder.Facade.GLASS)
	var metal := w._city_facade_material(col, WorldBuilder.Facade.METAL)
	var podium := w._city_facade_material(col, WorldBuilder.Facade.PODIUM)
	t.ok(conc != null and glass != null and metal != null and podium != null,
		"四个立面类别都能出材质")
	# 缓存键必须含类别：漏了的话"同一块颜色的所有楼"会共用第一种建出来的材质，
	# 表现是"玻璃幕墙的楼和混凝土楼长得一模一样"，而**不会报任何错**。
	t.ok(glass != conc, "同色不同类别是**两份**材质（缓存键含类别）")
	t.ok(metal != conc and podium != conc, "金属 / 裙房也是各自独立的一份")
	t.ok(w._city_facade_material(col, WorldBuilder.Facade.CONCRETE) == conc,
		"同色同类只建一份（缓存生效）")

	# 幕墙之所以"亮起来有天空色"，靠的就是玻璃板足够光滑
	t.lt(float(glass.get_shader_parameter("pane_rough")), 0.10,
		"玻璃幕墙的玻璃板很光滑（%.3f，低粗糙 ⇒ 反射天空）"
			% float(glass.get_shader_parameter("pane_rough")))
	t.lt(float(glass.get_shader_parameter("pane_rough")),
		float(conc.get_shader_parameter("pane_rough")),
		"幕墙的玻璃比混凝土楼的窗更光滑")
	t.gt(float(metal.get_shader_parameter("metallic_value")), 0.2,
		"工业金属类别真的带金属度")
	t.near(float(conc.get_shader_parameter("metallic_value")), 0.0, EPS,
		"混凝土没有金属度（现在全城都是哑光塑料，这是这次的起点问题）")
	# 裙房的开口更大（商铺）：这一条是"裙房与塔楼读起来不一样"的机械判据
	t.gt(float(podium.get_shader_parameter("bay_w")), float(conc.get_shader_parameter("bay_w")),
		"裙房的开间比塔楼大（商铺 vs 办公室）")

	# 强度总开关：`--facade=0` 靠它把这一项**单独**拧回 1.2 的纯色楼体
	t.near(float(conc.get_shader_parameter("facade_strength")),
		WorldBuilder.CITY_FACADE_STRENGTH, EPS, "默认强度 = `CITY_FACADE_STRENGTH`")
	var killed := w._city_facade_material(col, WorldBuilder.Facade.CONCRETE, 0.0)
	t.near(float(killed.get_shader_parameter("facade_strength")), 0.0, EPS,
		"strength 传 0 ⇒ 退化成纯色（探针的 A/B 靠这条）")
	t.ok(killed != conc, "强度不同 → 不同材质（缓存键含强度）")

	# 构件（路灯 / 桥索 / 屋顶设备）不该被误换成立面材质：它们仍然是 StandardMaterial3D
	t.ok(w._city_material(col) is StandardMaterial3D,
		"构件仍走纯色 `_city_material()`（立面 shader 只管楼体）")
	w.free()


## 一个地块的立面类别：**确定性的**、合法的、与分区对得上。
static func _lot_isolation(t: T) -> void:
	var rng := RandomNumberGenerator.new()
	var lots := 0
	var glass_downtown := 0
	var metal := 0
	var all_valid := true
	var waterfront_pure := true
	var all_tall := true
	for gx in range(-8, 8):
		for gz in range(-8, 8):
			if not WorldBuilder.city_is_land(gx + 0.5, gz + 0.5):
				continue
			rng.seed = WorldBuilder._city_lot_seed(gx, gz)
			var lot: Dictionary = WorldBuilder.city_lot_for(gx, gz, rng)
			lots += 1
			if not lot.has("facade"):
				all_valid = false
				continue
			var f: int = lot["facade"]
			if f != WorldBuilder.Facade.CONCRETE and f != WorldBuilder.Facade.GLASS \
					and f != WorldBuilder.Facade.METAL:
				all_valid = false
			if lot["zone"] == "downtown" and f == WorldBuilder.Facade.GLASS:
				glass_downtown += 1
			if f == WorldBuilder.Facade.METAL:
				metal += 1
			if lot["zone"] == "waterfront" and f != WorldBuilder.Facade.CONCRETE:
				waterfront_pure = false
			if float(lot["h"]) < 150.0:
				all_tall = false
	t.gt(lots, 40, "%d 个地块参与检查" % lots)
	t.ok(all_valid, "每个地块都有合法的立面类别")
	t.ok(glass_downtown > 0, "市中心真的有玻璃幕墙（%d 块）" % glass_downtown)
	t.ok(waterfront_pure, "滨水低层住宅一律普通窗格（不会冒出一栋玻璃幕墙小楼）")
	t.ok(metal * 4 < lots, "工业金属是少数派（%d / %d 块）" % [metal, lots])
	# ⚠️ **这一条是本次最重要的回归**：立面那一抽**不许动调用方传进来的 rng**。
	# 动了的话楼高/配色/朝向会整体移位，而 `suite_round20` 的"市中心地块是高层"
	# 与 `suite_worldscale` 的"最高一档仍在 2500~3050"就是拿那套序列在断言 ——
	# 它们会以"平衡/构图问题"的形式红掉，根因却在这里。
	t.ok(all_tall, "楼高的量级没变（每个地块都仍然 > 150 m ⇒ 序列没被新抽取移位）")
	# 确定性：同一格两次调用结果一致
	var r1 := RandomNumberGenerator.new()
	r1.seed = WorldBuilder._city_lot_seed(3, -5)
	var a: Dictionary = WorldBuilder.city_lot_for(3, -5, r1)
	var r2 := RandomNumberGenerator.new()
	r2.seed = WorldBuilder._city_lot_seed(3, -5)
	var b: Dictionary = WorldBuilder.city_lot_for(3, -5, r2)
	t.eq(a["facade"], b["facade"], "同一格的立面类别可复算")
	t.eq(a["color"], b["color"], "同一格的配色可复算（序列没被破坏）")
	t.eq(a["h"], b["h"], "同一格的楼高可复算")

	# ---- 源码层：立面那一抽必须用**新建的** rng ----
	# 机械判据：`"profile"` 那一行之后的每一处 `rng.` 都必须是 `frng.` 的一部分
	#（`"frng.".count("rng.") == 1`，所以两个计数相等 ⇔ 没有裸的 `rng.` 调用）。
	#
	# ⚠️ **必须先剥注释**：函数体里那段"为什么不能用传进来的 rng"的说明**逐字**写着
	# `rng` —— 将来只要有人在注释里写一句 `` `rng.randf()` 会移位 ``，带点的形式
	# 就会让 `rng.` 的计数多 1，断言立刻假红（而代码一行没错）。
	var body := _func_body(_strip_comments(_src("res://scripts/world/world_builder.gd")),
		"static func city_lot_for(")
	var cut := body.find("\"profile\": profile,")
	t.gt(cut, 0, "找到 `city_lot_for` 的字典结尾")
	var tail := body.substr(cut)
	t.gt(tail.count("frng."), 0, "立面那一抽用的是独立的 `frng`")
	t.eq(tail.count("rng."), tail.count("frng."),
		"字典之后**没有任何**裸 `rng.` 调用（否则会把调用方的序列抽移位）")


# ============================================================ ② shader 源码事实

## 这几条都是"写错了不会报错、只会静默变形"的地方。
##
## ⚠️ 源码断言天然易碎（改注释也可能碰掉）。所以**只钉那些有具体理由的**，
## 每条都写清"错了会怎样" —— 将来真要改这一行时，至少知道自己在放弃什么保护。
static func _shader_facts(t: T) -> void:
	# ---- 地表：细节法线 ----
	var terr := _strip_comments(_src("res://shaders/terrain.gdshader"))
	t.ok(terr.contains("uniform float detail_strength") and terr.contains("uniform float detail_grain"),
		"地表 shader 有细节强度与颗粒两个 uniform")
	t.ok(terr.contains("FRONT_FACING"),
		"细节扰动按正/背面分别处理（地表是 cull_disabled 的开放曲面，"
		+ "背面法线由引擎翻转 ⇒ 不区分会光照反向）")
	t.ok(terr.contains("cross(n, vec3(0.0, 0.0, 1.0))"),
		"切向基用世界 Z 当参照 —— 地面法线竖直，`cross(n, Y)` 会退化成零向量、"
		+ "整块地面法线变 NaN")
	t.not_ok(terr.contains("cross(vec3(0.0, 1.0, 0.0), n)"),
		"没有退回那个在地面上必然退化的写法")
	t.ok(terr.contains("vec2(h0 - hx, h0 - hz)"),
		"坡度取 `h0-hx` / `h0-hz`（≈ -∂h/∂x）：取反了会把凸的照成凹的，肉眼极难发现")
	t.ok(terr.contains("varying vec3 nrm_t_view"),
		"切向基在顶点阶段算好再传下来（fragment 里的 NORMAL 是视图空间，"
		+ "现算要用 fragment 阶段的矩阵，那是个不必要的未知数）")

	# ---- 地表细节 · 批 E 第二版：**跨距离可读**（实拍推翻第一版后加的）----
	#
	# 第一版只有一层 1.5 m 的波长，实拍四张图**一片平色**。原因是纯算术：
	# 3.2 km 机位高度上，1.5 m 只有 0.05~0.2 px。所以这几条钉的是
	# "波长必须跨三个数量级，且细层必须按像素数自动消失"。
	t.ok(terr.contains("uniform float detail_wavelength"),
		"波长 uniform 叫 `detail_wavelength`（**米**）—— 旧名 `detail_scale` 是"
		+ "1/米的频率倍率，那套口径下数值只有 0.2~0.7，正是「必然隐形」的量级")
	t.not_ok(terr.contains("detail_scale"),
		"没有把旧口径的名字留在源码里（留下就会有人照着它填 0.65）")
	t.ok(terr.contains("length(dFdx(wp))") and terr.contains("length(dFdy(wp))"),
		"每米占几像素由**屏幕空间导数**算（`dFdx/dFdy(world_pos.xz)`）："
		+ "它自动含倾斜、距离、fov、视口尺寸 —— 一个都不用我手写")
	t.not_ok(terr.contains("VIEWPORT_SIZE"),
		"**没有**用 `VIEWPORT_SIZE` —— 它在 Godot 4 的空间 shader 里不存在"
		+ "（实测 `SHADER ERROR: Unknown identifier` ⇒ 整份地面材质退回默认材质，"
		+ "而且无头测试零信号、只有真渲染才暴露）")
	t.not_ok(terr.contains("748.9"),
		"没有把那个只在 1600×900/62° 下成立的常数抄进 shader")
	t.ok(terr.contains("wl = lam * 0.25") and terr.contains("wl = lam * 0.0625")
			and terr.contains("wl = lam * 0.015625") and terr.contains("wl = lam * 0.00390625"),
		"五层倍频按 lacunarity = 4 展开（1280→320→80→20→5 m）："
		+ "`u = lam * 4^-i`，写错一层就会在某个距离带上整段失去细节")
	t.ok(terr.contains("smoothstep(1.0, 2.5, wl / max(mpp, 0.0001))"),
		"逐层按「该层在屏幕上占几个像素」淡出：低于 1 px 必须消失（那是纯噪声），"
		+ "2.5 px 以上才算「看得见的纹理」。**这同时是摩尔纹的解法** ——"
		+ "细层不是被调小，而是在它该消失的距离上消失")
	t.ok(terr.contains("return sum / max(wsum, 0.0001)")
			and terr.contains("return s / max(wsum, 0.0001)"),
		"高度与坡度都按**活着的权重之和**归一化：远处细层被剔除后不归一化就会"
		+ "变亮，等于偷偷改掉 1.2 逐张图调好的亮度基线（沙地均值 R=87.4 那组数）")
	t.ok(terr.contains("return w * vec2(h0 - hx, h0 - hz) * 2.0"),
		"每层用**自己的**差分步长（q 空间 0.5）并除回去：共用一个步长时，"
		+ "粗层的差分被稀释成接近 0 ⇒ 沙丘「有高度」却「不产生明暗」⇒ 画面依旧平 ——"
		+ "这是第一版白做的**第二个**原因")
	t.ok(terr.contains("float mpp = _ground_mpp(wq);")
			and terr.contains("float mpp0 = _ground_mpp(q);"),
		"米/像素在 fragment 里**现算**（`_ground_mpp`），不从顶点插值下来："
		+ "导数只在 fragment 阶段存在，插值出来的值在三角形内部是错的"
		+ "（地表网格 1.2 km 一格，插值误差足以让细节在地形起伏处错位）。"
		+ "轮 2 起有**两处**：`mpp0` 用未 warp 的坐标给材质掩码挑尺度，"
		+ "`mpp` 用 warp 后的坐标给细节剔除倍频")
	t.not_ok(terr.contains("varying float view_dist"),
		"删掉了没人用的 `varying float view_dist`（改用导数口径后它没有用户了）")

	# ---- 材质分层（轮 2）----
	t.ok(terr.contains("uniform float mat_blend") and terr.contains("uniform float mat_stretch")
			and terr.contains("uniform float mat_angle"),
		"材质分层三个旋钮都是 uniform（强度 / 拉伸倍率 / 方向）——"
		+ "方向也要能拧，否则四张图的层理会被锁在同一个世界方向上")
	t.ok(terr.contains("float big = _vnoise(wp * mat_mask_scale)")
			and terr.contains("float small = _vnoise(wp * 0.0167)")
			and terr.contains("mix(big, small, k)"),
		"掩码是**两级**的（大尺度分区 4.5 km + 近处斑驳 60 m）——"
		+ "只留大尺度时整屏是常数（城市地面实测 A/B 逐位相同），"
		+ "只留小尺度时远处变成每像素随机的噪点")
	t.ok(terr.contains("float k = _oct_fade(60.0, mpp);"),
		"小尺度那一级**按「在屏幕上占几个像素」淡出** —— 与逐层剔除倍频"
		+ "用的是同一把尺子（同一个 `_oct_fade`）")
	t.ok(terr.contains("return d * (dot(wp, d) * k) + p * dot(wp, p);"),
		"拉伸用「投影 → 缩放 → 还原」而不是构造旋转矩阵：不依赖坐标轴，"
		+ "`mat_angle` 为 0 时正好退化成 `x *= k`")
	t.ok(terr.contains("vec2 slope = _detail_slope(wq, detail_wavelength, mpp);")
			and terr.contains("float h0 = _detail_h(wq, detail_wavelength, mpp);"),
		"高度场、坡度、颗粒**三者用同一个 warp 后的坐标** ——"
		+ "错开的话会出现「凸的地方不亮」（颗粒与法线错位）")

	# ---- 云：主光方向受光 ----
	var cloud := _strip_comments(_src("res://shaders/cloud.gdshader"))
	t.ok(cloud.contains("uniform vec3 sun_dir"), "云 shader 有主光方向 uniform")
	t.ok(cloud.contains("uniform float sun_shade"), "云 shader 有主光受光的总开关")
	t.ok(cloud.contains("vec3(dot(sd, right), dot(sd, up), dot(sd, fwd))"),
		"主光方向被投到圆盘的三个轴上（x=右、y=上、z=朝相机）——"
		+ "少了 z 分量就只能表达屏幕平面内的方向")
	t.ok(cloud.contains("dot(n, sd) * 0.5 + 0.5"),
		"半兰伯特：背光侧压到纯黑会让云变成「被剪掉一半的黑洞」")
	t.ok(cloud.contains("mix(up_lit, lit, clamp(sun_shade"),
		"`sun_shade = 0` 时退回旧口径（只有上亮下暗）——探针的 A/B 靠这条")
	t.ok(cloud.contains("uv_center, sqrt(max(0.0, 1.0 - d * d))"),
		"盘内法线用 UV 伪造成球面（每一盘各自朝光的一侧亮 ⇒ 整团自然分出受光面）")

	# ---- 海面：浪尖透光 ----
	var ocean := _strip_comments(_src("res://shaders/ocean.gdshader"))
	t.ok(ocean.contains("uniform float crest_sss : hint_range(0.0, 2.0) = 0.0"),
		"浪尖透光**默认关**（海面是 1.2 逐张图调过的，只许做纯增量）")
	# ⚠️ **这一条是"实测推翻了我的第一版写法"留下的证据**（别改回去）：
	# 第一版用三维 `-dot(view_dir, normalize(moon_dir))` —— 教科书公式没写错，
	# 但本工程四张图**全部固定夜战、月亮永远 58°**，三维点积里朝上的两个分量
	# 与水平反向的两个分量**几乎抵消**，实测权重只剩 0.009 ⇒ 像素探针上
	# **全通道逐位为零**（连专门摆的逆光机位也一样），等于永久关闭。
	# 现在只比**水平方位**，同一处权重 0.281（31 倍）。凡是把它改回三维的，
	# 都会让这一项重新变成"装了但看不见"。
	t.ok(ocean.contains("vec3(view_dir.x, 0.0, view_dir.z)")
			and ocean.contains("vec3(md.x, 0.0, md.z)"),
		"逆光权重**只比水平方位**（三维点积在固定的 58° 月亮下会被垂直分量抵消）")
	t.not_ok(ocean.contains("dot(view_dir, normalize(moon_dir))"),
		"没有退回那个实测为零的三维写法")
	t.ok(ocean.contains("length(vf) > 0.0001"),
		"垂直俯视水面时水平分量趋零 ⇒ 显式退化到 0（不发光），而不是归一化出 NaN")

	# ---- 轮 1：长涌浪几何 + 水下礁盘（太平洋图唯一的"地形"）----
	t.ok(ocean.contains("uniform float wave_amp") and ocean.contains("uniform float wave_normal"),
		"长涌浪有**几何位移**（`wave_amp`）与**法线增益**（`wave_normal`）两个旋钮")
	# 实测记录：只做位移、不动法线时 A/B **全表逐位为零**（网格确实是 448 段，
	# 图元数 418960 证明位移加了）—— 海面是纯色，浪峰与浪谷一样亮，位移等于空转。
	t.ok(ocean.contains("_swell_grad") and ocean.contains("vec2 g = _swell_grad"),
		"长涌浪的坡度进了法线（否则位移在纯色海面上是空转）")
	t.ok(ocean.contains("float e = 190.0"),
		"长涌浪的差分步长按**它自己的波长**给（190 m，= `swell_len_b / 10`）——"
		+ "复用细波那支 `epsilon = 0.7` 会让粗层的差分趋近 0，坡度恒为零。"
		+ "⚠️ 这个数字**必须跟着 `swell_len_b` 一起改**：轮 4 把波长 1400 → 1900 时，"
		+ "步长若留在 140，差分就把长波当成了准常量（1900/140 = 13.6 倍波长）")
	t.ok(ocean.contains("uniform float shoal_amount"), "水下礁盘有独立开关")
	# ---- 海面微波（批 H · 轮 3）----
	t.ok(ocean.contains("uniform float ripple_amount")
			and ocean.contains("uniform float ripple_len")
			and ocean.contains("uniform float ripple_normal"),
		"微波有独立的开关 / 波长 / 法线增益三个旋钮（默认 0 = 关）")
	# ⚠️ 微波**必须**按屏幕像素淡出。海面占满全屏又一直铺到地平线，
	# 短波若常开，远处每个像素会随机挑一个相位 ⇒ 整片海变成闪烁的噪点。
	# 判据按**最细那一层**的波长（`wl_min`）走。
	t.ok(ocean.contains("smoothstep(2.0, 4.0, wl_min / max(mpp, 0.0001))"),
		"微波按「一个波长占几像素」淡出（与 `terrain._oct_fade` 同一把尺子），"
		+ "不是按固定米数")
	# ⚠️ 差分步长取**半格**（`+ vec2(0.5, ...)`）：步长比波长小得多时差分趋近 0，
	# 那一层在法线里等于不存在 —— 这个坑 `terrain._detail_slope` 踩过一次。
	t.ok(ocean.contains("_vnoise(qa + vec2(0.5, 0.0))")
			and ocean.contains("_vnoise(qb + vec2(0.0, 0.5))"),
		"微波的差分步长是**半格**（不是远小于波长的步长）")
	# ⚠️ **必须是两层**。单层 value noise 是"一格一个随机值"，
	# 实拍就是一张棋盘（14 m 晶格在 60 m 机位前景上放大成约 100 px 的方块）。
	t.ok(ocean.contains("_vnoise(qa)") and ocean.contains("_vnoise(qb)"),
		"微波是**两层**不同波长 + 不同相位（单层会露出 value noise 的晶格棋盘）")
	# ⚠️ 两层的尺度比必须**非整数**：0.5 会让两套晶格在半个周期处重新对齐，
	# "错开"就白做了。
	t.ok(ocean.contains("RIPPLE_OCT_SCALE = 0.37"),
		"两层尺度比是 0.37 这种**非整数比**（0.5 会让晶格重新对齐）")
	# ⚠️ `_vnoise` 的插值必须是 **quintic**（C2 连续），不是 smoothstep（C1）。
	# 我们拿 value noise 的**差分**当坡度，而 smoothstep 的二阶导在格边界处突变
	# ⇒ 每个晶格读得出一个方块。这是"海面方块感"的根治点。
	t.ok(ocean.contains("f * f * f * (f * (f * 6.0 - 15.0) + 10.0)"),
		"`_vnoise` 用 quintic 插值（C2 连续）—— smoothstep 的二阶折点就是方块感的来源")

	# ---- 地标几何细化（批 H · 轮 3）----
	# 巨岩的两件事必须配套：网格密度够 + 噪声按该网格的格距给波长。
	# 只加细分是白烧顶点（采到的还是同一个缓坡），只改波长会走样成噪点。
	var wsrc_rock := _strip_comments(_src("res://scripts/world/world_builder.gd"))
	t.ok(wsrc_rock.contains("noise.frequency = 1.0") and wsrc_rock.contains("u * n_u")
			and wsrc_rock.contains("v * n_v"),
		"巨岩噪声的频率归到 1.0、跨度按格距算，且 **X/Z 各自换算**"
		+ "（旧写法 `frequency=0.010` × `u*640` 只给了 6.4 个周期 ⇒ 6 km 的岩体上"
		+ "只有 6 个大鼓包，风化在数学上不存在；而 u/v 共用一个周期数会让噪声"
		+ "单向拉伸 ⇒ 岩壁上出现木纹）")
	t.ok(wsrc_rock.contains("cell_max * 8.0"),
		"主波长取 **8 格**（奈奎斯特下限 2 格 × `octaves=3` 的 1/4 ⇒ 最细层正好压在 2 格），"
		+ "且按**粗**那个方向定 —— 取 4 格会让最细层落在 1 个格距上，那是走样，"
		+ "实拍是岩壁上一层'揉皱的纸'")
	# ⚠️ 断言里必须是 `absf(` —— GDScript 的通用 `abs()` 返回 Variant，
	# 配 `var gs :=` 会触发"类型推断自 Variant"的警告，而本工程把警告当错误
	# ⇒ 整份脚本编不过（而且探针仍会"截图成功"，只截到一张纯色空屏）。
	t.ok(wsrc_rock.contains("absf(sin(th * float(grooves) + (n - 0.5) * 2.2))"),
		"侧壁的风化沟用 `1 - |sin|` 的**凹槽**形状（`sin` 本身在实拍里读成木纹/波纹，"
		+ "而侵蚀沟是只凹不凸的），相位带噪声扰动；取绝对值用 `absf()` 而不是 `abs()`"
		+ "（后者返回 Variant，会让整份脚本编不过）")
	t.ok(wsrc_rock.contains("clampi(int(round(span_m / 500.0)), 2, 14)"),
		"沟的条数跟岩体尺寸走（小岩块 2 条，巨岩 14 条上限）—— 固定条数会把小丘切成薯条；"
		+ "除数 500 而非 250，因为 `1-|sin|` 的半周期就是一道沟（视觉沟数是两倍）")
	t.ok(wsrc_rock.contains("7301, 72)"),
		"Uluru 的网格密度是 72（旧值 34 ⇒ 176 m 一格，近景是多面体）")

	# ---- 城市天际线：塔顶桅杆（批 H · 轮 3）----
	t.ok(wsrc_rock.contains("float(lot.gx * 37 + lot.gz * 71)") and wsrc_rock.contains("mast_h"),
		"塔顶桅杆的高度由**格坐标**算出，而不是消耗 `_city_rng`")
	# ⚠️ 这一条是防回退的**关键**：`_city_rng` 是整座城共享的一条序列，
	# 在 `_city_block_at` 里多抽一次，它后面每次抽取的结果都会整体平移 ——
	# 楼高、配色、偏心、退台尺寸全部跟着变，而根因在几百行之外，极难查。
	var mast_body := _func_body(wsrc_rock, "func _city_block_at")
	var mast_seg := ""
	if mast_body.contains("if h > 900.0"):
		mast_seg = mast_body.split("if h > 900.0")[1]
	t.ok(mast_seg != "" and not mast_seg.contains("_city_rng"),
		"桅杆那一段（`if h > 900.0` 之后直到函数末）**没有**动用 `_city_rng`，"
		+ "否则整座城的随机序列会被平移")
	# ---- 城市天际线：楼体横向线脚（批 K · 轮 4）----
	#
	# 用户："楼房地面的褶皱" → 方向定为「**楼体线脚（几何）**」。
	# ⚠️ 这一条**是几何而不是贴图**，而窗格贴图在 `CITY_FACADE_FADE_FAR = 1950 m`
	# 之外就淡出了 —— 淡出之后整栋楼是一个纯色长方体。线脚不吃淡出。
	# 下面那条 `mast_seg` 断言**顺带**把线脚也管住了（它在 `if h > 900.0` 之后，
	# 也就是 `mast_seg` 的范围内）⇒ 线脚同样一次 `_city_rng` 都不许抽。
	t.ok(wsrc_rock.contains("CityBands") and wsrc_rock.contains("CITY_BAND_ALBEDO"),
		"楼体线脚走 **MultiMesh**（`CityBands`，一次 draw call、不进碰撞层）——"
		+ "走 `_add_city_body` 的话 250 栋 × ~10 道 = ~2500 个 `StaticBody3D`，不可接受")
	t.ok(wsrc_rock.contains("float(lot.gx * 53 + lot.gz * 29)"),
		"线脚的间距抖动由**格坐标**算出（`|gx·53 + gz·29| mod step`），而不是消耗 `_city_rng`")
	t.ok(wsrc_rock.contains("_make_band_shell"),
		"线脚的几何来自 `_make_band_shell()`（**开口筒**），而不是直接复用 `_city_cube` ——"
		+ "实心盒的顶面在「塔身宽 1.2 km」这个尺度下是一块 2 km² 的板，会把整栋楼盖住")
	t.ok(wsrc_rock.contains("1 if cull_off else 0"),
		"`_city_material()` 的缓存 key 里带着 **`cull_off`** —— 否则开口筒会拿到"
		+ "纯色楼体那份单面材质（基色相同就不会走到 duplicate），俯视时筒的内壁被剔掉")
	t.ok(ocean.contains("float zone = (s * 0.72 + m * 0.28) * 0.5 + 0.5;")
			and ocean.contains("clamp(zone + jitter, 0.0, 1.0)"),
		"礁盘场是「**正弦分区 + 噪声扰动**」—— 两边都试过："
		+ "纯正弦的边界规则、像水面污渍；纯噪声在 40 km 视场内跨不过阈值，"
		+ "实测整帧只差 +0.0005（等于没做）")
	t.ok(ocean.contains("_vnoise(wp * 0.00022)") and ocean.contains("float _hash21"),
		"扰动那一半用 value noise（形状不规则、可复算），与「分区」的正弦分工")
	t.ok(ocean.contains("ALBEDO += foam_color * top"),
		"礁盘叠在 `sky_color` / `horizon_color` 两次混合**之后** ——"
		+ "叠在 `base` 上时掠射角的 `fres` 会把 base 冲淡到三成，礁盘跟着一起没了")
	t.not_ok(ocean.contains("base = mix(base, shoal_color"),
		"没有退回「叠在 base 上」那个实测看不见的写法")

	# ---- 城市：米制立面 ----
	var city := _strip_comments(_src("res://shaders/city.gdshader"))
	t.ok(city.contains("uniform float facade_strength : hint_range(0.0, 1.0) = 0.0"),
		"立面强度**默认 0** ⇒ 无人设参数时逐字节等价于旧材质")
	t.ok(city.contains("local_pos.x * world_scale.x"),
		"墙面坐标以**米**为单位（用 UV 做不到：单位立方体的 UV 不随实例尺寸变化）")
	t.ok(city.contains("length(MODEL_MATRIX[0].xyz)"),
		"世界尺度取自模型矩阵各基向量的长度（尺寸烘在实例 scale 上）")
	t.ok(city.contains("ALBEDO = mix(base, base * (1.0 - pane_dark), k_near)"),
		"明暗**只在近处**给（远处整面压暗会推翻 1.2 那套「楼靠天光被看清」的基线）")
	t.ok(city.contains("smoothstep(facade_fade_near, facade_fade_far, view_dist)"),
		"远处淡出按**开间像素**反推：最小开间 5.2 m 在 970 m 处还有 4 px（保满对比）、"
		+ "在 1950 m 处到 2 px 奈奎斯特极限（淡净）——"
		+ "第一版凭感觉写的 500 m 起淡，实测让整项改动几乎不可见（`--facade=0` 只差 −0.0002）")
	t.ok(city.contains("uniform float facade_fade_near = 970.0")
			and city.contains("uniform float facade_fade_far = 1950.0"),
		"淡出两端是 **uniform 而不是字面量**：写成字面量时运行时拧不动，"
		+ "`--facade=0` 测不出差别就没法归因「淡出吃掉」与「根本没接上」")
	t.not_ok(city.contains("source_color"),
		"`albedo_tint` 刻意**不加** `source_color`（要与 BaseMaterial3D 的线性口径一致，"
		+ "否则同一个颜色会渲出两种亮度）")


# ============================================================ ③ 真地图上的接线

## 建两张真地图（沙漠 / 城市）核对"接线穿到了场景里的那个实例上"。
##
## 为什么非要建图：上面那些纯函数断言只能证明"材质本身对"，
## 证明不了"楼体真的用了它" —— 漏传一个参数就会让整座城退回纯色，而不报任何错。
static func _built_maps(t: T, host: Node) -> void:
	var root := Node3D.new()
	root.name = "GfxMapProbe"
	host.add_child(root)
	var w := WorldBuilder.new()
	root.add_child(w)
	await host.get_tree().process_frame

	# ---- 沙漠：地表细节 + 云的主光方向 ----
	w.apply_map(MapDef.uluru())
	w.apply_time_of_day(TimeOfDay.make(TimeOfDay.Preset.NIGHT))
	t.gt(w._terrain_mats.size(), 0, "沙漠图建出了 %d 份地表材质" % w._terrain_mats.size())
	# ⚠️ **不是"每一份都开着"** —— 远景地坪（`_build_ground_plane()`，节点名 `GroundFar`）
	# 刻意**不铺细节**：它是一张 `PlaneMesh`，脚下只有 2×2 段细分，拿它去铺 1.8 m 波长的
	# 噪声只会得到"一块均匀的噪点"；而它一铺就是 `LAND_SIZE` = **460 km 见方**。
	# 它在材质上的**签名是 `use_vertex_color == false`**（`PlaneMesh` 没有顶点色），
	# 而其余 5 个细分地表调用点全是 `true` ⇒ 这条断言能区分
	# "刻意不铺" 与 "漏传了第 5 个参数"（后者会让整块沙丘退回纯色，且**不报任何错**）。
	var with_detail := 0
	var no_detail := []
	for m in w._terrain_mats:
		if float(m.get_shader_parameter("detail_strength")) > 0.0:
			with_detail += 1
		else:
			no_detail.append(m)
	t.gt(with_detail, 0, "沙漠图有 %d 份地表材质开着细节" % with_detail)
	t.eq(no_detail.size(), 1, "**恰好一份**不铺细节（%d / %d）"
		% [no_detail.size(), w._terrain_mats.size()])
	if no_detail.size() == 1:
		t.eq(bool(no_detail[0].get_shader_parameter("use_vertex_color")), false,
			"不开细节的那一份正是**没有顶点色的远景地坪**（不是漏传参数的细分地表）")
	var scale_seen := {}
	for m in w._terrain_mats:
		scale_seen[float(m.get_shader_parameter("detail_wavelength"))] = true
	t.gt(scale_seen.size(), 1,
		"沙丘与岩面用的**不同**波长（沙丘 1280 m vs 岩面 320 m，%d 档）" % scale_seen.size())
	# ⚠️ **波长必须是"米"量级的大数**（批 E 第二版的核心修正）。
	# 旧口径传的是 0.22~0.65 的"1/米频率倍率"⇒ 主波长 1.5~4.5 m ⇒
	# 在本工程 3.2 km 的机位高度上只有 0.05~0.2 px，**实拍整张图一片平色**。
	# 这一条钉住"不许再退回小数量级" —— 它是那次白做的**唯一可自动化的表征**。
	for k in scale_seen.keys():
		t.gt(float(k), 100.0,
			"波长 %s m 是「在 3 km 机位高度上读得出来」的量级（必须 > 100 m）" % str(k))

	# ---- 艾尔斯岩绿洲：团 / 串 / 树（批 K · 轮 2）----
	#
	# ## 为什么这些断言只能在**无头**里跑、又为什么现在能跑
	# 轮 1 把树的位姿**特意留在了 `desert_tree_xf`**（`MultiMesh.get_instance_transform()`
	# 在无头模式下读回来全是单位变换，见那里的注释）⇒ 于是"树撒得对不对"
	# 第一次变成一条**可自动化的**判据，而不是"看图数一数"。
	#
	# ## 这一节钉住的三个真事故
	#   ① **静默截断**（轮 1 实测 `trees: 30000` == 上限）：尾部那些团
	#      一棵树都没有 —— 地上是绿的、树是零，而这正好违反用户的第一条要求。
	#      现在两处一起钉：`tree_scale == 1.0`（没触发缩放）+ `trees < CAP`（没顶上）。
	#   ② **串断成珠子**（轮 1 量出 0 条串）：数据侧用 `desert_chain_census()`
	#      数"圆形交叠"的连通分量 —— 它与像素量具**共用同一份定义**。
	#   ③ **两处各算一遍分布**（旧做法）：`terrain.gdshader` 曾经自己算"哪儿该绿"。
	#      现在树与绿斑共用一份 `desert_oasis_sites`，下面第三条断言就是它的机械表达：
	#      **每棵树都必须落在某个团里**。
	var census: Dictionary = w.desert_chain_census()
	t.gt(w.desert_oasis_sites.size(), 0, "沙漠图撒出了 %d 个团/片" % w.desert_oasis_sites.size())
	t.gt(w.desert_tree_xf.size(), 0, "沙漠图撒出了 %d 棵树" % w.desert_tree_xf.size())
	t.ok(w._veg_mask_tex != null, "绿洲覆盖掩码烘出来了（没烘的话地面不会绿，且不报任何错）")
	# ① 预算：**不等于上限**比"不超过上限"更强 —— 轮 1 那次是恰好等于，
	#    而"恰好等于"和"刚好这么多"在日志里长得一模一样。
	t.lt(w.desert_tree_xf.size(), WorldBuilder.DESERT_TREE_CAP,
		"树数 %d **严格小于**上限 %d（等于上限 = 有人把预算撑满了，`tree_scale` 才是判据）"
			% [w.desert_tree_xf.size(), WorldBuilder.DESERT_TREE_CAP])
	t.near(w.desert_tree_scale, 1.0, 0.0001,
		"树密度缩放系数 == 1.0 ⇒ 预算没超（<1.0 说明 `DESERT_CANOPY_FILL` / 团半径被调大了）")
	# ② 串：**数据侧**必须有 ≥3 片连成一组的分量。
	#    ⚠️ 这条断言的是"数据上连上了"，不是"画面上连上了" ——
	#    后者由 `_oasis_stat.py` 的二阶矩长短轴比（> 1.6）在真渲染图上量。
	#    两者缺一不可：数据连上而画面断开，就是轮 1 那个 bug（可见半径收缩）。
	t.gt(int(census["chains"]), 0,
		"数据侧有 %d 条串（≥3 片圆相交连通，共 %d 组）" % [census["chains"], census["groups"]])
	t.gt(float(census["chain_span_m"]), WorldBuilder.DESERT_CLUMP_R_MAX * 2.0,
		"最长的串跨 %.0f m > 2×最大团半径 %.0f m ⇒ 串是**拉长的**（不是几个圆叠成一坨）"
			% [census["chain_span_m"], WorldBuilder.DESERT_CLUMP_R_MAX * 2.0])
	# ③ 构造一致性：**抽样**核每一棵树都落在**看得见绿**的范围里。
	#    ⚠️ 判据用 `DESERT_VEG_VISIBLE_R × 团半径` 而**不是**团半径：
	#    shader 的 `cov = mask×GAIN − BIAS` 会把掩码外围压到 0 ⇒ 地上真正可见的绿
	#    只到 0.89 r。用整半径判的话，"树站在裸沙上"这个错**正好落在判据的盲区里**
	#   （特写 `K9_oasis` 拍出来就是那个样子：边缘一圈树孤零零站在沙上）。
	#    ⚠️ 抽样率写在这里是有意的：全量是 36k × 998 = 3600 万次距离计算，
	#    在无头套件里是**秒级**的开销，而这一条要抓的是"整层错位"
	#  （比如 shader 与树用了两套分布），那种错**随便抽一棵就能看见**。
	var stride := maxi(1, w.desert_tree_xf.size() / 500)
	var checked := 0
	var outside := 0
	for i in range(0, w.desert_tree_xf.size(), stride):
		var o: Vector3 = w.desert_tree_xf[i].origin
		checked += 1
		var inside := false
		for s in w.desert_oasis_sites:
			var rr := s.z * WorldBuilder.DESERT_VEG_VISIBLE_R
			var dx := o.x - s.x
			var dz := o.z - s.y
			if dx * dx + dz * dz <= rr * rr:
				inside = true
				break
		if not inside:
			outside += 1
	t.eq(outside, 0,
		"抽检 %d 棵树，**每一棵都站在看得见绿的地方**（越界 %d 棵）—— 地面绿斑与树同源"
			% [checked, outside])
	# ④ `DESERT_VEG_VISIBLE_R` 与 shader 那两个常数**必须同步**。
	#    ⚠️ 这是一条**算术断言**（不是"grep 看字面量在不在"）：
	#    把 shader 里的 `VEG_MASK_GAIN` / `VEG_MASK_BIAS` 抓出来、按同一个反解公式
	#    算一遍可见半径，再和 GDScript 那个常数比。字面量检查挡不住
	#    "有人只改了 shader 的 BIAS" —— 而那正是这个耦合唯一会断的方式。
	var sh_src := _src("res://shaders/terrain.gdshader")
	var re_g := RegEx.new()
	re_g.compile("const float VEG_MASK_GAIN\\s*=\\s*([0-9.]+)")
	var m_g := re_g.search(sh_src)
	var re_b := RegEx.new()
	re_b.compile("const float VEG_MASK_BIAS\\s*=\\s*([0-9.]+)")
	var m_b := re_b.search(sh_src)
	t.ok(m_g != null and m_b != null,
		"在 `terrain.gdshader` 里找到了 `VEG_MASK_GAIN` / `VEG_MASK_BIAS` 两个字面量")
	if m_g != null and m_b != null:
		var gval := float(m_g.get_string(1))
		var bval := float(m_b.get_string(1))
		# `f^1.35` 的逆：`f = (BIAS/GAIN)^(1/1.35)`
		var vis := 1.0 - pow(bval / gval, 1.0 / 1.35)
		t.near(vis, WorldBuilder.DESERT_VEG_VISIBLE_R, 0.02,
			"shader 反解出的可见半径 %.3f r 与 `DESERT_VEG_VISIBLE_R` %.2f 一致"
				% [vis, WorldBuilder.DESERT_VEG_VISIBLE_R])
	# 半径：**不能有 0 半径的团**（`_bake_veg_mask()` 里是 `radius * radius` 做除数，
	# 0 会得到 NaN/除零，而那种错从画面上看只是"某个团莫名其妙没了"）。
	var rmin := INF
	var rmax := 0.0
	for s in w.desert_oasis_sites:
		rmin = minf(rmin, s.z)
		rmax = maxf(rmax, s.z)
	t.gt(rmin, 1.0, "最小半径 %.1f m > 1 m（防除零）" % rmin)
	# 掩码分辨率 vs 团半径：**算术检查，不是 grep**
	# ⚠️ 这条是"有人把 `DESERT_OASIS_RES` 调小以省内存"时的唯一防线：
	# 25.4 m/px 下最小团半径 140 m = 5.5 px，是"边缘还平滑"的下限；
	# 分辨率再降一档（1024 ⇒ 50.8 m/px）最小团就只有 2.8 px，会读出多边形。
	var mpp := WorldBuilder.DESERT_OASIS_SPAN / float(WorldBuilder.DESERT_OASIS_RES)
	t.gt(WorldBuilder.DESERT_CLUMP_R_MIN / mpp, 4.0,
		"最小团半径 = %.1f 像素（%.1f m/px）⇒ 边缘平滑度够" % [WorldBuilder.DESERT_CLUMP_R_MIN / mpp, mpp])


	# ---- ⚠️ 2026-09-28（轮 37 · 用户报"艾尔斯岩地表有一条绿线"）：两条**覆盖范围**断言 ----
	#
	# 这一节钉的真事故，两个症状同源：
	#   `DESERT_OASIS_SPAN` 是**写死的**，而撒布半径 `DESERT_OASIS_R` 是**派生的**
	#  （= `SPAWN_RADIUS × 1.16`）。`ARENA_RADIUS` 那轮 ×2.25 时前者没跟 ⇒ 覆盖图半宽
	#   只剩 **26 km**，而团心撒到 **54 km**。后果两条：
	#     ① **75% 的绿洲被静默裁掉**：`_bake_veg_mask()` 里 x0/x1/z0/z1 那四条
	#        `maxi/mini` 把图外的团夹到图外 ⇒ 一格都不写、**不报任何错**。
	#        实测：团+叶片 1001 片，落在图外 **751 片**。
	#     ② **覆盖图四条边被钳边拉成绿带** —— `veg_mask_tex` 标了 `repeat_disable`
	#        ⇒ 图外采样一律钳到边缘那一列/行 ⇒ 边上那几个非零格被拉成**长条**，
	#        贴在地上就是"一条细绿线从近处收敛到地平线"。用户截的就是它。
	#        ⚠️ 所以判据是**边必须干净**，不是"有一个斑"。实测边格被拉出的长度：
	#        第一行最长 **57 格 ≈ 1447 m**。
	#
	# ⚠️ 两条都是**算术 / 数据**断言，不用 grep：这类缺陷的成因永远是"两个数之间的关系
	# 断了"，而它们拆开看各自都很合理 —— 字面量检查挡不住。
	t.gt(WorldBuilder.DESERT_OASIS_SPAN * 0.5,
		WorldBuilder.DESERT_OASIS_R + WorldBuilder.DESERT_CLUMP_R_MAX,
		"覆盖图半宽 %.0f m > 撒布半径 %.0f + 最大团半径 %.0f m ⇒ 没有团会掉在覆盖图外被静默裁掉"
			% [WorldBuilder.DESERT_OASIS_SPAN * 0.5,
				WorldBuilder.DESERT_OASIS_R, WorldBuilder.DESERT_CLUMP_R_MAX])
	# 逐团量"外接框最远边"（`|中心| + 半径`，保守上界）—— 与"覆盖图四边全零"等价，
	# 理由见本段开头的注释。用**保守上界**而不用真圆相交，是要它当一条**硬门禁**：
	# 只要有一个团的框够到边界就报出来，不给"刚好差一点"留缝。
	var oasis_half: float = WorldBuilder.DESERT_OASIS_SPAN * 0.5
	var reach_max := 0.0
	var reach_out := 0
	for s in w.desert_oasis_sites:
		var reach: float = maxf(absf(s.x), absf(s.y)) + s.z
		reach_max = maxf(reach_max, reach)
		if reach > oasis_half:
			reach_out += 1
	t.eq(reach_out, 0,
		"逐团核覆盖范围：%d 个团**没有一个**够到覆盖图边界（最远 %0.1f m vs 半宽 %0.1f m，余量 %0.1f m）⇒ 图外不会被钳成绿带"
			% [w.desert_oasis_sites.size(), reach_max, oasis_half, oasis_half - reach_max])
	# 局部 RNG：**只查源码**，运行时查不出来（`_rng` 的状态被 46 块岩块消耗过，
	# 谁动过它从最终状态里分不出来）。这条同时挡住"改动植被会挪动岩块落点"。
	# ⚠️ 这里**另起一个名字**而不是复用下面「材质分层」那一段的 `wsrc`：
	# 那个变量在本函数里是**后面**才声明的，在这里引用会直接编译不过
	#（`Identifier not found`），而在中间插一行 `var` 又会撞上重复声明。
	var obody_src := _strip_comments(_src("res://scripts/world/world_builder.gd"))
	var obody := _func_body(obody_src, "func _desert_oasis_sites")
	t.ok(obody.contains("RandomNumberGenerator.new()"),
		"`_desert_oasis_sites()` 自建 RNG（与 `_city_rng` / `CLOUD_SEED` 同一条规矩）")
	t.ok(not obody.contains("_rng."),
		"`_desert_oasis_sites()` **不碰** `_rng` —— 否则那 46 块散落岩块的落点会跟着植被一起动")

	# ---- 云：三带都拿到主光方向，而且换时段会跟着更新 ----
	t.gt(w._cloud_mats.size(), 1, "云材质登记了 %d 带" % w._cloud_mats.size())
	var tod_night := TimeOfDay.make(TimeOfDay.Preset.NIGHT)
	var tod_day := TimeOfDay.make(TimeOfDay.Preset.DAY)
	var dir_night := WorldBuilder.celestial_dir(tod_night.sun_rotation_deg)
	var dir_day := WorldBuilder.celestial_dir(tod_day.sun_rotation_deg)
	t.gt(dir_night.distance_to(dir_day), 0.01, "白天与夜晚的天体方向确实不同（否则下面两条是空断言）")
	t.ok(_all_clouds_point_at(w, dir_night), "夜里：每一带云的主光方向都等于当前时段的天体方向")
	w.apply_time_of_day(tod_day)
	t.ok(_all_clouds_point_at(w, dir_day), "换到白天后：主光方向跟着更新（不是只在建材质时设了一次）")

	# ---- 城市：楼体真的用了立面 shader ----
	w.apply_map(MapDef.oenbelli())
	w.apply_time_of_day(TimeOfDay.make(TimeOfDay.Preset.NIGHT))
	var tower := _first_material(w, "Tower_")
	var podium := _first_material(w, "Podium_")
	var crown := _first_material(w, "Crown_")
	t.ok(tower is ShaderMaterial,
		"塔楼用的是立面 shader（不是纯色 StandardMaterial3D）—— 漏传一个参数就会退回纯色而不报错")
	t.ok(podium is ShaderMaterial, "裙房也是立面材质")
	if tower is ShaderMaterial:
		t.gt(float((tower as ShaderMaterial).get_shader_parameter("facade_strength")), 0.0,
			"塔楼的立面强度是开着的")
	if podium is ShaderMaterial and tower is ShaderMaterial:
		t.gt(float((podium as ShaderMaterial).get_shader_parameter("bay_w")),
			float((tower as ShaderMaterial).get_shader_parameter("bay_w")),
			"裙房与塔楼**不是**同一份材质（开间不同）")
	if crown != null:
		t.ok(not (crown is ShaderMaterial),
			"顶冠仍是纯色构件（28 m 的小块上铺窗格只会变成噪点）")
	# 材质去重：立面材质数必须远少于建筑体量数（否则等于一栋一份、几百个 draw call）
	t.gt(w._city_facade_cache.size(), 0, "城市建出了 %d 份立面材质" % w._city_facade_cache.size())
	t.lt(w._city_facade_cache.size(), w._city_body_count,
		"立面材质数（%d）少于建筑体量数（%d）⇒ 按颜色+类别去重生效"
			% [w._city_facade_cache.size(), w._city_body_count])
	# 淡出距离**必须在运行时推给材质**：shader 里的 `= 970.0` 只是给"没人设参数"兜底，
	# 而 `get_shader_parameter()` **读不到 shader 源码里的默认值**（返回 null）——
	# 所以这两条读得到，才等于"工程侧真的传了"，也正是 `--fadefar` 能拧得动的前提。
	if tower is ShaderMaterial:
		t.near(float((tower as ShaderMaterial).get_shader_parameter("facade_fade_near")),
			WorldBuilder.CITY_FACADE_FADE_NEAR, EPS,
			"工程把淡出近端推给了材质（读不到 = set_shader_parameter 漏了）")
		t.near(float((tower as ShaderMaterial).get_shader_parameter("facade_fade_far")),
			WorldBuilder.CITY_FACADE_FADE_FAR, EPS,
			"工程把淡出远端推给了材质")
	# 城市地表也走地表 shader（有细节），城市水面走海面 shader（有浪尖透光）
	var city_detail := false
	for m in w._terrain_mats:
		if float(m.get_shader_parameter("detail_strength")) > 0.0:
			city_detail = true
	t.ok(city_detail, "城市地面也开着地表细节")
	# ---- 楼体线脚真的建出来了 + 数量在预算内（批 K · 轮 4）----
	#
	# ⚠️ 这条**不能**只看源码里有 `CityBands` 这个字符串（那就又回到
	# "全是接线断言"的老毛病了）。`MultiMesh.instance_count` 在无头模式下
	# **是有效的**（`get_instance_transform()` 才是读回来全单位变换的那个）。
	# 所以这里可以真正数出"建了多少道线脚"。
	var band_mm := w._terrain_root.get_node_or_null("CityBands") as MultiMeshInstance3D
	t.ok(band_mm != null, "楼体线脚建出来了（`CityBands` 节点在场）")
	if band_mm != null:
		var bn := band_mm.multimesh.instance_count
		t.gt(bn, 200, "线脚实例数 %d > 200 ⇒ 不是「只有个别楼有」" % bn)
		# ⚠️⚠️ B7（2026-09-28）：预算的**基数从"地块数 250"改成"建出来的楼数"**。
		# 一格从 1 栋变成 2~8 栋之后，`547 个地块` 会建出 ~2 900 栋楼 ——
		# 还拿 250 去估，这条会**因为"楼变多了"而红**，而这跟线脚的账毫无关系
		#（正是"判据的基数与口径不匹配"那一类假红）。
		# 基数的真源是 `_city_lot_built`（每次建城开头清零，见那个成员）。
		var lots := maxi(w._city_lot_built, 1)
		t.lt(bn, lots * (WorldBuilder.CITY_BAND_MAX + 1),
			("线脚实例数 %d < %d（**%d 栋楼** × (≤%d 道腰线 + 1 道檐口)）"
				+ "—— 超了说明有人把 `CITY_BAND_PITCH` 调小/`CITY_BAND_MAX` 调大却没重算这笔账")
				% [bn, lots * (WorldBuilder.CITY_BAND_MAX + 1), lots,
					WorldBuilder.CITY_BAND_MAX])
		# ---- ⚠️⚠️ 线脚几何必须是"**开口筒**"（4 个侧面），不是实心立方体 ----
		#
		# **这一条是批 K · 轮 4 最贵那个坑的回归闸，非形式主义。**
		#
		# 实心盒的顶面是 `(tw + 2δ) × (td + 2δ)` 的**完整矩形**。而 `tw` 是
		# `base × 0.30~0.46`、`base = ARENA_RADIUS / CITY_GRID × CITY_FILL` 是**数千米**
		# ⇒ **一块线脚的顶面就有 2 km²**。相机停在塔身中部往下看时，下面每一道线脚的
		# 顶面全部可见、层层叠加 —— 实拍是**一堵亮板盖住整栋楼**，
		# `--bands=0/1` 的 A/B 曾给出 **19.7% / 48.9%** 这种量级。
		#
		# 判据用**三角形数**：`BoxMesh` 是 12 个三角形（36 个顶点），
		# 开口筒（4 个侧面 × 2）是 8 个三角形（24 个顶点）。
		# 拿"顶点数"而不是"有没有顶面"这种语义 —— 后者在这个 API 里读不出来。
		var faces := band_mm.multimesh.mesh.get_faces().size()
		t.eq(faces, 24,
			("线脚几何是**开口筒**（4 个侧面 = 8 三角形 = 24 个顶点），实测 %d 个顶点。"
				+ "⚠️ 若变成 36，就是有人把它换回了 `_city_cube`（实心盒）——"
				+ "那会让顶面变成一块 2 km² 的板、把整栋楼盖住，见 `_make_band_shell()` 的注释")
				% faces)
	# ---- 绿洲必须在**换图时清干净**（批 K · 轮 2）----
	#
	# ⚠️ 这条不是形式主义：绿洲的三份数据（`desert_oasis_sites` / `desert_tree_xf` /
	# `_veg_mask_tex`）是**跨 `apply_map()` 存活**的成员变量。漏清任何一份的后果是
	# "**城市图上长出一片沙漠绿洲**"，而且因为掩码是 `hint_default_black` 兜底、
	# 树是 `MultiMesh` 单 draw call，它**不报任何错**、只是画面上多了一块绿。
	# 三份分开断言（而不是只断言 sites 为空）：它们的清空在三个不同的代码位置
	#（`_map_stage_free()` 清两份，`_terrain_material()` 每次重灌掩码），
	# 只盯一份的话另外两份漏了照样绿。
	t.eq(w.desert_oasis_sites.size(), 0, "换到城市图后：团/串列表被清空（不是残留沙漠的）")
	t.eq(w.desert_tree_xf.size(), 0, "换到城市图后：树的位姿数组被清空")
	t.near(w.desert_tree_scale, 1.0, 0.0001, "换到城市图后：密度缩放系数复位")
	t.ok(w._veg_mask_tex == null, "换到城市图后：覆盖掩码被置空（否则地面会整片按旧掩码长草）")
	# ⚠️ 最后一道：**城市图的 `veg_amount` 必须全是 0**。
	# 这是"改 `terrain.gdshader` 的 `VEG_MASK_GAIN/BIAS` 不会漏到别的图"的机械表达：
	# shader 里整段植被（含那两个常数）都在 `if (veg_amount > 0.0)` 之内，
	# 所以只要 `veg_amount` 恒为 0，那一段就是死代码 —— **不需要靠像素比对去证**。
	# 这条断言的价值在于：它是"逻辑隔离"而不是"实测没差别"
	#（后者只能是"这一次没差别"，前者是"不可能有差别"）。
	var veg_leak := 0
	for m in w._terrain_mats:
		if float(m.get_shader_parameter("veg_amount")) > 0.0:
			veg_leak += 1
	t.eq(veg_leak, 0,
		"城市图的 %d 份地表材质 `veg_amount` 全为 0 ⇒ 植被那一段（含 GAIN/BIAS）是死代码"
			% w._terrain_mats.size())
	# ---- 外围山谷丘陵（批 K · 轮 4）----
	#
	# ⚠️ 这组断言存在的理由：丘陵是**加在既有高度函数上**的一层，而
	# `_city_landform()` 同时决定**城区地面、海湾、运河**三件事的高度。
	# 加错位置（比如忘了乘海湾掩码）的后果是"**海底顶出一排山**"，
	# 或者"楼脚被抬起来" —— 两种都不报错，只是画面上出现不该有的东西。
	#
	# ⚠️⚠️ 为什么用**不变量**而不是"跟改前的图比 md5"：
	# 丘陵**本来就该出现在地平线上**，所以城区机位的 PNG **必然**会变
	#（实测 md5 `381124c7…` → `e9928a10…`，差的就是地平线那一条山脊）。
	# 拿像素比对当隔离证明，会把"**功能正常**"读成"回归" —— 那就反了。
	# ⇒ 改成直接断言"**城区内一个高度都没变**"这件事本身。
	var hill_leak := 0
	var city_h_max := -1.0e9
	for i in 33:
		for j in 33:
			# 覆盖**整个城区**：四块人工岛（2026-09-28 起）的外接范围是
			# `|x| ≤ 64.4 km`、`|z| ≤ 64.4 km`，最远角点半径 **78.2 km**。
			# ⚠️ 原来是 ±33 km（那是**单椭圆**时代的岛半径 31.8 km）——
			# 四块岛之后它只盖住了主岛，有明/青海的远端**从来没被这条判据看过**。
			# 上界取 80 km：再往外就有 `r > CITY_HILL_IN = 82 km` 的采样，
			# 而那些点**本来就有山**（下面 `continue` 会跳过它们）。
			var cx := (float(i) / 32.0 * 2.0 - 1.0) * 80000.0
			var cz := (float(j) / 32.0 * 2.0 - 1.0) * 80000.0
			if Vector2(cx, cz).length() > WorldBuilder.CITY_HILL_IN:
				continue
			if absf(WorldBuilder._city_hills(cx, cz)) > 0.0:
				hill_leak += 1
			city_h_max = maxf(city_h_max, WorldBuilder._city_landform(cx, cz))
	t.eq(hill_leak, 0,
		"`CITY_HILL_IN` 以内丘陵**恒为 0** ⇒ 城区地面/楼脚一个高度都没变")
	t.lt(city_h_max, 24.0,
		"城区最高点 %.1f m 仍在 24 m 分带以下 ⇒ `_city_land_color()` 的城区配色也没动"
			% city_h_max)
	# 丘陵必须**真的立起来**、**只向上**、而且**连成一体**。
	#
	# ⚠️ 2026-09-28（V2）：第三条判据**换了口径**。原来是"谷底平台 > 10%"
	#（统计 `hh == 0.0` 的采样占比），那是**对着 V1 的"硬截断造平地"写的**。
	# V2 让 `rid` 直通、不再归零 ⇒ 旧判据恒为 0，**必须换成新的设计目标**：
	# 用户这一轮要的是"一体、平滑"，所以核的是**贴地面积要少**（实测 22.8% → 0.0%）。
	# 判据换了、但**方向也反了**（从"要多"变成"要少"），这一点很容易看漏。
	var hill_min := 1.0e9
	var hill_max := -1.0e9
	var flat_hits := 0
	var hill_samples := 0
	for i in 49:
		for j in 49:
			# ⚠️⚠️ 2026-09-28：采样方框从 ±50 km 扩到 **±120 km**。
			# 判据是"取 `r > CITY_HILL_OUT` 的点"，而环带外移之后
			# `CITY_HILL_OUT = 96 km` 而旧方框的对角只有 70.7 km ⇒
			# **`hill_samples` 会数到 0**，于是 `hill_max` 停在 `-1e9`（第一条红）、
			# 贴地面积那条变成 `0/0`（NaN，比较恒为假，第二条也红）。
			# 两条都会红，但红的原因与"山好不好看"毫无关系 —— 是取样点全在山外。
			var hx := (float(i) / 48.0 * 2.0 - 1.0) * 120000.0
			var hz := (float(j) / 48.0 * 2.0 - 1.0) * 120000.0
			if Vector2(hx, hz).length() <= WorldBuilder.CITY_HILL_OUT:
				continue
			hill_samples += 1
			var hh := WorldBuilder._city_hills(hx, hz)
			hill_min = minf(hill_min, hh)
			hill_max = maxf(hill_max, hh)
			if hh < WorldBuilder.CITY_HILL_AMP * 0.05:
				flat_hits += 1
	t.gt(hill_max, WorldBuilder.CITY_HILL_AMP * 0.75,
		"丘陵最高 %.0f m > 0.75×幅度（%.0f m）⇒ 山脊**真的立起来了**"
			% [hill_max, WorldBuilder.CITY_HILL_AMP])
	t.gt(hill_min, -0.0001,
		"丘陵最低 %.4f m ≥ 0 ⇒ **只向上**（往下走会掉进 `h < -6` 那一档水下暗蓝，谷底会被染成「泡在水里」）"
			% hill_min)
	t.lt(100.0 * float(flat_hits) / float(hill_samples), 5.0,
		"贴地面积（h < 5%% 幅度）占 %.1f%% ≤ 5%% ⇒ 山体**连成一体**；V1 是 22.8%%"
			% (100.0 * float(flat_hits) / float(hill_samples))
		+ "，那一片绝对平地就是「平地上插着一排刀锋」那个观感的来源")
	# ---- 材质分层（轮 2）：四张图各一套，互不相同 ----
	#
	# ⚠️ **判据不能是"这张图上存在多于一档"**（轮 2 第一版就是这么写的，跑出来 3 条红）：
	# 单张图的 `_terrain_mats` 里本来就**只有一种料子** —— 城市地面就是城市地面，
	# 它的每一份材质都拿同一组 (blend, stretch, angle)。"多档"只存在于**跨图**比较，
	# 而在单图构建里再怎么看也只有 1 档。这不是接线漏了，是判据写错了。
	#
	# 所以改成**查调用点**：把 `world_builder.gd` 里每个 `_terrain_material(...)` 的实参
	# 抓出来，要求「至少四个调用点显式传满了第 7~9 位」且「这些实参不全相同」——
	# 这正是"四张图各一套、且不是同一个方向锁死"的机械表达。
	var wsrc := _strip_comments(_src("res://scripts/world/world_builder.gd"))
	var re := RegEx.new()
	# `(?<!func )` 把**定义那一行**排掉（`func _terrain_material(tint: Color, ...`）。
	# `[^)]*` 是字符类 ⇒ 天然跨行，正好吃下多行书写的调用。
	re.compile("(?<!func )_terrain_material\\(([^)]*)\\)")
	var with_layer := 0
	var triples := {}
	for found in re.search_all(wsrc):
		var args := String(found.get_string(1)).split(",")
		# 传满第 7~9 位 ⇒ 至少 9 个实参。
		if args.size() >= 9:
			with_layer += 1
			triples[",".join([
				args[6].strip_edges(), args[7].strip_edges(), args[8].strip_edges()])] = true
	t.gt(with_layer, 3,
		"至少四个调用点（四张图）显式传了第 7~9 位 —— 实测 %d 个" % with_layer)
	t.gt(triples.size(), 1,
		"这些调用点的（分层强度/拉伸/方向）**不全相同**（%d 组）—— "
		% triples.size()
		+ "锁死会让每张图的地表纹理都朝同一边")
	t.ok(w._ocean_mat != null, "城市图有水面（海湾 + 运河）")
	if w._ocean_mat != null:
		t.gt(float(w._ocean_mat.get_shader_parameter("crest_sss")), 0.0,
			"水面开着浪尖透光（%s）" % str(w._ocean_mat.get_shader_parameter("crest_sss")))
		# ---- 城市水面**必须关掉**长涌浪与礁盘（轮 1）----
		# 城市那个水面是 460 km 铺 2×2 段（格距 230 km），位移会把四个角各抬一段
		# ⇒ 整片水面倾斜成斜板；礁盘则更直接：人工海湾底下长珊瑚礁不合理。
		t.near(float(w._ocean_mat.get_shader_parameter("wave_amp")), 0.0, EPS,
			"城市水面没有长涌浪（460 km 铺 2 段，位移会把它变成一块斜板）")
		t.near(float(w._ocean_mat.get_shader_parameter("shoal_amount")), 0.0, EPS,
			"城市水面没有水下礁盘（人工海湾，底下不该长珊瑚礁）")

	# ---- 地标几何体：**"世界坐标由 body 承担、网格保持局部零位"** ----
	#
	# ⚠️⚠️ 这一段的由来：1.2.3 批 E 里玩家拿着一张实机截图问了一句「**这个球是啥**」，
	# 顺着这句问话查出了两处地标被**父节点重复加了一次偏移**：
	#   · 富士台的球体瞭望室（`FujiSphere`）：`mi.position` 与 `body.position`
	#     都被设成了世界坐标，然后 `body.add_child(mi)` ⇒
	#     实测 global=(-7000, 1722, -7000)，而它该在 (-3500, 861, -3500)，**偏了 5024 m**；
	#   · Big Sight 的倒金字塔（`BigSightCone`）：同一行代码、同一个错法，偏了 **11966 m**。
	#
	# 它一直没被发现，是因为**错得不像 bug**：一个孤零零挂在天上的球，看起来只是
	# "远景里一个不明物体"。真正的危害在玩法侧 —— **碰撞体一直在正确位置**，
	# 于是"能撞到的地方"与"看得见的地方"差了几公里：撞上一团空气，
	# 或者穿过一个看得见的东西。这类"幽灵碰撞"从不报错，只会被当成手感问题。
	#
	# ⚠️ 所以这里断言的是**通用不变量**，不是逐个地标核对坐标：
	# 这类错误会换一个名字再出现（任何"先给 `mi.position` 赋世界坐标、
	# 再 `body.add_child(mi)`"的写法都中招）。而逐个核对还会引入第二份字面量 ——
	# `-3500` 抄进测试的那天起，工程里改位置就不会有测试红。
	# 参照物一律取**场景里已有的兄弟节点**：球体拿它挂着的连廊当参照，倒锥拿四座塔当参照。
	#
	# 为什么放在本套件：这里刚好已经把城市图建出来了（不变量要在真场景图上检，
	# 光看源码看不出父子关系带来的重复偏移）。
	var bad := _body_mesh_offsets(w._terrain_root)
	t.eq(bad.size(), 0, "挂在 StaticBody3D 下的网格全部保持局部零位；非零即世界坐标被重复加了一次（%s）"
		% ("；".join(bad) if bad.size() > 0 else "0 处"))
	var fuji := _node_named(w._terrain_root, "FujiSphere")
	var fuji_deck := _node_named(w._terrain_root, "FujiDeck")
	t.ok(fuji != null and fuji_deck != null, "奥恩贝利建出了富士台的球体与它挂着的那条连廊")
	if fuji != null and fuji_deck != null:
		var fp := (fuji as Node3D).global_position
		var dp := (fuji_deck as Node3D).global_position
		t.near(Vector2(fp.x, fp.z).distance_to(Vector2(dp.x, dp.z)), 0.0, EPS,
			"球体的水平坐标与它挂着的连廊**完全重合**（球心 %s vs 连廊 %s）—— "
			% [str(fp), str(dp)] + "这一条就是「父节点加了两次偏移」的检出条件")
		t.near(fp.y, dp.y, EPS, "球体与连廊同高（设计就是「挂在桥上」）")
	var cone := _node_named(w._terrain_root, "BigSightCone")
	var towers := _nodes_prefixed(w._terrain_root, "BigSightTower")
	t.ok(cone != null and towers.size() == 4,
		"Big Sight 建出了倒锥与四座塔（找到 %d 座塔）" % towers.size())
	if cone != null and towers.size() == 4:
		# 倒锥要落在四塔围成的水平区间**之内** —— 用一个区间而不是一个点，
		# 是为了不把 `c ± 1350/± 950` 那组尺寸在测试里再抄一遍。
		var lo := INF
		var hi := -INF
		for tv in towers:
			lo = minf(lo, ((tv as Node3D).global_position.x))
			hi = maxf(hi, ((tv as Node3D).global_position.x))
		var cx := (cone as Node3D).global_position.x
		t.ok(cx > lo - EPS and cx < hi + EPS,
			"倒锥的 x（%.1f）落在四座塔的 x 区间 [%.1f, %.1f] 之内" % [cx, lo, hi])

	# ================================================================ 达沃：楼体量（1.3 批 M · 轮 2）
	#
	# ## 为什么这一组必须在**真场景**上量，而不是读源码
	# 轮 2 的改动是"两个倍率（`MapDef.city_tower_w` / `city_height_mul`）乘在
	# 已经抽出来的随机数上"。这种改动**没有一种失败方式会报错** ——
	# 乘错了位置、漏乘、或者被"顺手"塞进 `_city_rng` 的序列里，日志全是干净的。
	# 唯一的判据是**建出来的盒子的尺寸**。
	#
	# `_add_box()` 把位置写在 `StaticBody3D.position` 上、尺寸写在
	# `MeshInstance3D.scale` 上（"网格保持零位"那条不变量，见 `_body_mesh_offsets()`）
	# ⇒ 这两样都读得到，而且是**真几何**、不是工程里的字面量。
	#
	# ## 四条断言各守什么
	#   ① **相对量（高宽比）**：达沃的楼体与奥恩贝利**不同**。
	#      2026-09-28 之前这一条写的是"至少 ×1.5 ⇒ 细高"，用户翻方向之后
	#      实测比值从 ×3.83 收到 **×1.22** ⇒ 阈值改成 `>`（只守"两城不同"）。
	#      ⚠️ 它**量不出"变粗了没有"** —— 见下面 ①′ 那段。
	#   ①′ **相对量（塔/裙房）**：塔楼在裙房里占多大 —— 这才是"粗不粗"。
	#      同城内部相比，`bw`/`bd` 全被约掉，与 `lot.h` 无关。
	#   ② **绝对量**：金沙三塔的高宽比落在真实金沙的比例（5 : 1）附近。
	#      它绑的是一个**工程外的数**，所以谁把倍率调到别的方向，这里会红 ——
	#      红得有意义（"三塔不再像金沙"本来就是该有人拍板的事）。
	#      ⚠️ 三塔走 `CITY_SANDS_ASPECT`（构造锁死），**不吃** `city_tower_w`
	#      ⇒ 本轮翻方向**不**影响它（实测仍绿）。
	#   ③ **玩法量**：塔顶到船底那条 370 m 的净空槽**一个字都没变**。
	#      轮 2 把塔高从 2100 抬到了 2415（`×1.15`），若槽宽是**绝对量**写的，
	#      这一抬就把它从 370 挤成 85 —— 玩法通道直接报废，而画面上看不出来。
	#      槽宽是**相对量**（`h + 520` / 船厚 300）写的，所以它必须恒为 370。
	#      ⚠️ 本轮把 `city_height_mul` 压到 0.92 **同样**不动它（它是相对量）。
	var oe_asp := _avg_tower_aspect(w._terrain_root)
	t.gt(oe_asp, 0.0, "奥恩贝利量到 %d 栋塔楼的高宽比（均值 %.2f）" % [
		_nodes_prefixed(w._terrain_root, "Tower_").size(), oe_asp])
	# ⚠️ 在 `apply_map(davao)` **之前**把奥恩贝利的"塔/裙房"比也量出来
	#（下面那条断言要拿它当基准，换图之后就再也量不到奥恩贝利的了）。
	var oe_pr := _avg_tower_podium_ratio(w._terrain_root)
	t.gt(oe_pr, 0.0, "奥恩贝利量到塔宽/裙房宽均值 %.3f（作为达沃的基准）" % oe_pr)
	# 奥恩贝利这边**一颗港区泛光灯都没有**（在 `apply_map(davao)` 之前量）。
	# ⚠️ 这一条不是"顺便"：轮 6 加的 `OmniLight3D` 是全工程第一批**真光源**，
	# 而"死城 / 活城"的开关（`map.city_lights`）在这里**必须继续管得住灯** ——
	# 一旦有人把灯的创建挪到那个 `if` 之外，奥恩贝利会跟着亮起来，
	# 而那正是老板明确说过"不需要"的东西。
	t.eq(_flood_lamps(w._terrain_root).size(), 0,
		"奥恩贝利（死城）0 颗港区泛光灯 —— 真光源同样受 `map.city_lights` 管辖")

	w.apply_map(MapDef.davao())
	w.apply_time_of_day(TimeOfDay.make(TimeOfDay.Preset.NIGHT))
	var dv_asp := _avg_tower_aspect(w._terrain_root)
	# ⚠️ 这条**只证明"两个倍率真的落到了几何上、且两城不同"**，它**不再**表示
	# "达沃是细高城"，所以阈值也从 `×1.5` 收到 `> `（**实测读数**，不是拍的）：
	#
	# | | `oe_asp` | `dv_asp` | 比值 |
	# |---|---|---|---|
	# | 改前（`0.62 / 1.15`） | 0.84 | **≈ 3.22** | ×3.83 |
	# | 本轮（`1.55 / 0.92`） | 0.84 | **1.03** | **×1.22** |
	#
	# ⚠️ 顺带纠正一条**一直写在注释里、但从没被量过**的说法：
	# 早先那句"奥恩贝利的塔高宽比约 2.6 : 1"说的是**市中心那几栋**，
	# 而 `_avg_tower_aspect()` 量的是**全城 2 898 栋的均值** —— 其中绝大多数是
	# fringe / waterfront 的矮楼（`h` 160~620、而子地块宽可到 800 m）
	# ⇒ 全城均值只有 **0.84**（比 1 还小）。两件事不矛盾，但**混用会让阈值拍错**。
	t.gt(dv_asp, oe_asp,
		("达沃全城塔楼高宽比均值 %.2f > 奥恩贝利 %.2f"
			+ " ⇒ 两个倍率真的落在几何上（不是只改了 `MapDef` 上的两个数）；"
			+ "差距已从改前的 ×3.83 收到 ×%.2f —— 这正是本轮要的方向，"
			+ "而「变粗了没有」由下面那条塔/裙房比钉着")
			% [dv_asp, oe_asp, dv_asp / maxf(oe_asp, 1.0e-6)])

	# ---- ⚠️ 达沃的"塔楼占裙房多少"（2026-09-28 新增 —— 钉"粗"这件事）----
	#
	# ## 为什么必须换一个量具，而不是改上面那个阈值
	# `_avg_tower_aspect`（塔高 ÷ 塔宽）**量不出"变粗"**：它同时吃
	# `lot.h`、子地块宽、塔宽三样，而两城的 `lot.h` 分布本来就不同
	# ⇒ 达沃塔宽 ×2.5、楼高 ×0.8 之后，这个均值**照样**大于奥恩贝利。
	# 把阈值调小只会把一条有意义的分工断言变成装饰。
	#
	# 用户要的"粗"是**同一座城内部**的相对关系：塔楼相对裙房有多大。
	# `Tower_*` 与 `Podium_*` 共用**同一个 tag**（`gx_gz_slot`）⇒ 可按后缀配对，
	# 读数 = `塔宽 ÷ 裙房宽`。它只由 `city_tower_w` 与 `[0.30,0.46]`/`[0.72,0.96]`
	# 决定，**与 `lot.h` / 子地块尺寸完全无关** —— 正是"粗不粗"的干净读数。
	#
	# | 城 | `tower_w` | 塔宽/裙房宽（均值，理论） |
	# |---|---|---|
	# | 奥恩贝利 | 1.0 | 0.452（= 0.38 / 0.84） |
	# | 达沃（改前） | 0.62 | 0.281 |
	# | 达沃（本轮） | 1.55 | **0.701** |
	var dv_pr := _avg_tower_podium_ratio(w._terrain_root)
	t.gt(dv_pr, oe_pr * 1.35,
		("达沃塔宽/裙房宽均值 %.3f ≥ 奥恩贝利 %.3f × 1.35"
			+ " ⇒ 塔楼真的在裙房里变胖了（改前是 0.281 < 奥恩贝利 0.452，**反过来**）")
			% [dv_pr, oe_pr])
	# ⚠️ 同一条不变量的**真几何版**（`suite_round20` 里有一条纯数据版）：
	# 塔宽**不许超过**裙房宽，否则塔楼会探出裙房外悬空 —— 塔有几千米高，
	# 那种失效在俯视图上只是一圈亮边，在贴地视角却是一整面悬空的墙。
	# 理论上限 = `0.46 × 1.55 = 0.713 < 0.72`，余量只有 1%。
	t.lt(dv_pr, 1.0,
		"达沃塔宽/裙房宽均值 %.3f < 1.0 ⇒ 塔楼仍在裙房轮廓之内（不悬挑）" % dv_pr)

	# ---- 城市地面**不留地质层理**（轮 9）----
	#
	# 症状：近景（`--aim=PortCraneLeg0_-1:400 --pitch=30`）的**暗地面**上有一层
	# 读起来像水面／大理石的**涡旋纹**；正上方俯视（`--pitch=89`）读成 45° 细晶格。
	# 而那片几何是 `PortApron`（纯色盒子、`Facade.NONE`）—— 本该一个纹都没有。
	#
	# 归因（每一发都是同机位 A/B；量具是 ROI 内平均相邻像素梯度 `grad_h`，单位 /255。
	# ⚠️ **量具粒度必须匹配被测对象**：整帧 `stddev_lum` 对这件事是瞎的，
	# `--matblend=0` 下它 0.0884 → 0.0884 **一动都不动**）：
	#
	# | 旋钮 | ROI-A `grad_h` | 结论 |
	# |---|---|---|
	# | 基线（全开） | 2.6903 | 100.0% |
	# | `--waves=0` / `--ripple=0` / `--facade=0` / `--veg=0` | **逐位相同** | 不是水／窗格／植被 |
	# | `--deband=0` | 2.5320（−6%），但 PNG 1 301 868 → 790 589 B（**−39%**） | **只解释压缩率** |
	# | `--adjust=0` | 2.6113，且 `mean` 48.7 → 52.6（**升**） | 只负责放大 8/255 |
	# | `--cel=0` | **逐位相同** | `cel_post` 面片当前**没参与渲染** |
	# | **`--matblend=0`** | **1.6820（−37.5%）** | 最大的一头 |
	# | 再叠 `--detail=0 --mottle=0` | **0.8740（−67.5%）** | 余下的是正常光照明暗，不是纹 |
	#
	# ⚠️ **上一轮把这件事归给了 `--deband`，那是错的**：`--deband=0` 的画面与基线
	# **肉眼无差别**（1:1 裁图里漩涡一模一样），它只改了 PNG 的压缩率。
	# 「体积差 39%」不能当成「画面变了」（与 v2.8 ㉛ 同族、方向相反）。
	#
	# 机理：`terrain.gdshader::_mat_warp()` 把世界坐标沿 `mat_angle` 压缩 `k` 倍，
	# 而 `k` 由一层**随空间连续变化**的掩码调制 ⇒ 坐标映射的雅可比逐点不同
	# ⇒ 挂在它上面的细节噪声被**揉成涡旋**。近景走 small 层（λ≈60 m），在 400 m 贴脸
	# 的 ~480 m 视场里只有 8 个周期、屏幕上 ~200 px/周期 ⇒ 掩码梯度全落在可见波段。
	#
	# ⇒ 层理对沙丘／岩体／靶场／岛是**正资产**（风成地貌、岩层走向），而**城市地面是
	# 沥青与混凝土 —— 人造铺装本来就不该有地质层理** ⇒ 关掉这一个参数，
	# 而不是去动 `_mat_mask` 的波长（那会同时改四张图、作废它们的画质基线）。
	var cg_node := w._terrain_root.get_node_or_null("CityGround") as MeshInstance3D
	t.ok(cg_node != null, "达沃建出了城市地面 `CityGround`")
	if cg_node != null and cg_node.material_override is ShaderMaterial:
		var cgm := cg_node.material_override as ShaderMaterial
		t.near(float(cgm.get_shader_parameter("mat_blend")), 0.0, EPS,
			("城市地面不留地质层理（`mat_blend` = 0）—— 沥青／混凝土是人造铺装；"
				+ "0.60 会在近景暗面上被 `_mat_warp` 揉出可见涡旋，"
				+ "而近景正是玩家贴地飞行的视距"))
		# 反向下界：**不许**顺手把地面质感一起关掉 ——
		# 关掉层理的理由是"人造铺装没有层理"，不是"地面不该有质感"。
		t.gt(float(cgm.get_shader_parameter("mottle")), 0.0,
			"城市地面的斑驳（`mottle`）仍在 —— 这次修的是层理，不是把地面做平")
		t.gt(float(cgm.get_shader_parameter("detail_strength")), 0.0,
			"城市地面的细节（`detail_strength`）仍在")
		t.lt(float(cgm.get_shader_parameter("mat_blend")),
			0.30, "层理强度落在「可忽略」一侧（剂量表 0.30 仍有 90.9% 的涡旋梯度）")

	var sands := _box_xf(w._terrain_root, "SandsTower0")
	t.ok(sands["size"] != Vector3.ZERO, "达沃建出了 `SandsTower0`")
	if sands["size"] != Vector3.ZERO:
		var ss: Vector3 = sands["size"]
		var s_asp := ss.y / ss.x
		t.between(s_asp, 4.25, 5.75,
			("金沙三塔高宽比 %.2f : 1（真实金沙 ≈ 5 : 1；第一版是 2100 : 800 ≈ 2.6 : 1 的方墩）。"
				+ "⚠️ 这条绑的是**工程外的数** ⇒ **不许**为了让它变绿去放宽区间，"
				+ "只能让几何回到 5 : 1（`CITY_SANDS_ASPECT`：`bw = h / 5`，形状由构造锁死）")
				% s_asp)
		# 形状的**第二条**（构造保证）：宽 : 深 = 1.25，与第一版同。
		# ⚠️ 只钉住高宽比是**不够**的 —— 三条边里只约束了 x、y 两条，
		# `bd` 完全可以被写成任意数，塔身就从"柱"变成"片"，而高宽比照样是 5.00。
		# （2026-09-28：正是这条漏网让 G4 的"只抬 h"翻过去 —— 那时还没有这一条。）
		t.near(ss.x / ss.z, 1.25, 0.02,
			"金沙塔身平面 宽 : 深 = %.3f : 1（与第一版的 800 : 640 同）" % (ss.x / ss.z))
	# 另外两塔同形（三根柱子一根比一根不同的话，"三塔"读起来会散）
	for i in [1, 2]:
		var s2 := _box_xf(w._terrain_root, "SandsTower%d" % i)
		t.ok(s2["size"] == sands["size"],
			"`SandsTower%d` 与 `SandsTower0` 同尺寸（三塔是一组，不是三栋各自随机的楼）" % i)
	var ship := _box_xf(w._terrain_root, "SandsShip")
	t.ok(ship["size"] != Vector3.ZERO, "达沃建出了 `SandsShip`")
	# ---- 净空槽：基准是「船底**最下缘**」（轮 5 改口径）----
	#
	# ⚠️ 轮 5 之前这里量的是 `SandsShip` **自己的底面** —— 因为那时"船就是一块板"，
	# 板底就是最下缘。轮 5 给船底加了横肋（往下 70 m）与纵边梁（往下 95 m），
	# 于是"机体能飞的净空"由**肋梁的底**决定，不是船体板的底。
	# 量的东西必须跟着**设计意图**走：这条断言的语义从第一天起就是"最下缘到塔顶"，
	# 只是当年两块面重合、看不出区别。留在这里的一句话：
	# **以后往船底再挂任何东西，都要让它的底面落在 `SandsKeel0` 这一档上**
	#（`CITY_SHIP_CLEAR` 是上游常量，但常量管不了"有人绕过它写死一个 y"）。
	var keel := _box_xf(w._terrain_root, "SandsKeel0")
	t.ok(keel["size"] != Vector3.ZERO, "达沃建出了船底纵边梁（`SandsKeel0`）")
	if keel["size"] != Vector3.ZERO and sands["size"] != Vector3.ZERO:
		var belly: float = float(keel["pos"].y) - float(keel["size"].y) * 0.5
		var tower_top: float = float(sands["pos"].y) + float(sands["size"].y) * 0.5
		t.near(belly - tower_top, 370.0, 1.0,
			("塔顶（%.0f m）到**船底最下缘**（%.0f m）的净空槽 = %.0f m"
				+ " —— 设计书 §3.2 的「沿船底掠过」通道，是**玩法参数**、不是观感参数")
				% [tower_top, belly, belly - tower_top])
		# 船体板被**抬高了**（肋梁要长在它下面）—— 这是轮 5 的机制本身，
		# 不是副作用：板底必须严格高于最下缘，否则肋梁与板底共面 = 肋梁白加。
		if ship["size"] != Vector3.ZERO:
			var plate_bot: float = float(ship["pos"].y) - float(ship["size"].y) * 0.5
			t.gt(plate_bot - belly, 50.0,
				("船体板底（%.0f m）比船底最下缘（%.0f m）高 %.0f m ⇒ 横肋真的凸在板下"
					+ "（不是共面的一层贴纸）")
					% [plate_bot, belly, plate_bot - belly])
	# 横肋是 MultiMesh（`_box_xf` 读不到实例尺寸）⇒ 钉"节点在" + "道数有上限"。
	var ribs_n := _nodes_prefixed(w._terrain_root, "SandsRibs")
	t.ok(ribs_n.size() > 0, "达沃建出了船底横肋（`SandsRibs`，MultiMesh）")
	var belly_lights_n := _nodes_prefixed(w._terrain_root, "SandsBellyLights")
	t.ok(belly_lights_n.size() > 0,
		"达沃建出了船底作业灯（`SandsBellyLights`）—— 夜间唯一能让这条槽读出来的东西")
	# 针塔仍然高过三塔（"回到市中心"的那个锚点不能被地标群抢掉）
	var needle := _box_xf(w._terrain_root, "NeedleSpire")
	var seg := _box_xf(w._terrain_root, "NeedleSeg0")
	t.ok(needle["size"] != Vector3.ZERO and seg["size"] != Vector3.ZERO,
		"达沃建出了针塔（`NeedleSeg0` + `NeedleSpire`）")
	if needle["size"] != Vector3.ZERO and sands["size"] != Vector3.ZERO:
		var spire_top: float = float(needle["pos"].y) + float(needle["size"].y) * 0.5
		var sands_top: float = float(sands["pos"].y) + float(sands["size"].y) * 0.5
		t.gt(spire_top, sands_top,
			"针塔尖（%.0f m）高过金沙三塔顶（%.0f m）—— 「全图最高」只能有一个" % [spire_top, sands_top])

	# ============================================================ 港区**真光源**（轮 6）
	#
	# ⚠️ 这一组是**几何级**断言：真的从建好的场景里数节点、读属性。
	#
	# 能这么做，恰恰是因为灯是**普通节点**（`OmniLight3D`）—— 而下一组灯头断言
	# 只能做源码级，因为灯头挂在 `MultiMesh` 上、无头模式下实例变换读不回来。
	# **"能不能做几何级"取决于几何存在哪里**，不是取决于"想不想严格"。
	var lamps := _flood_lamps(w._terrain_root)
	t.eq(lamps.size(), 6, "达沃港区建出 6 颗泛光灯（`OmniLight3D`）—— 全工程第一批**真光源**")
	if lamps.size() > 0:
		var l0: OmniLight3D = lamps[0]
		t.near(l0.light_energy, WorldBuilder.CITY_PORT_FLOOD_ENERGY, 0.5,
			("泛光灯能量 == 常量 `CITY_PORT_FLOOD_ENERGY`（%.0f）—— "
				+ "这个数是剂量表七档量出来的，不许被顺手调大") % WorldBuilder.CITY_PORT_FLOOD_ENERGY)
		t.near(l0.omni_range, WorldBuilder.CITY_PORT_FLOOD_RANGE, 0.5,
			"泛光灯射程 == 常量 `CITY_PORT_FLOOD_RANGE`（%.0f m）" % WorldBuilder.CITY_PORT_FLOOD_RANGE)
		t.ok(not l0.shadow_enabled,
			"泛光灯**不开实时阴影**（6 盏 4800 m 射程的阴影是灾难级代价，且夜里没有第二光源）")
		# 容器：`--portlights=0` 靠它一次关整批。灯要是散在 `_terrain_root` 下，
		# 那个开关就只关得掉第一盏（而它**不会报错**，只会让 A/B 变成一个假对照）。
		t.ok(l0.get_parent() != null and String(l0.get_parent().name) == "PortFloodLights",
			"6 颗灯收在 `PortFloodLights` 容器里（探针 `--portlights=0` 才能一次关整批）")
		# 灯必须**高于货柜堆** —— 灯埋在箱子里，照亮的就只是它自己旁边那两个面。
		# ⚠️ 上限改成**从堆高常量算出来**的（旧版写死 400，是"4 层 × 70 m + 底座 60 m"）；
		# 层高/层数一改，写死的阈值就会静默失效（这正是这套代码最怕的那类）。
		var yard_top: float = WorldBuilder.PORT_APRON_TOP \
			+ float(WorldBuilder.PORT_LAYER_MAX) * WorldBuilder.PORT_LAYER_H
		t.gt(l0.global_position.y, yard_top,
			"灯高 y = %.0f m > 堆高上限 %.0f m ⇒ 在货柜堆之上（照明是「从上往下泼」，"
				% [l0.global_position.y, yard_top]
				+ "不是「从箱子里透出来」）")

	# ================================================================ 构件灯头：点，不是板（轮 4）
	#
	# ## 这一条为什么只能做**源码级**断言
	# 灯头挂在 `MultiMesh` 上，而 `MultiMesh.get_instance_transform()` 在无头模式下
	# 读回来全是单位变换（本套件别处已记过这条限制）⇒ **场景里量不到灯头的尺寸**。
	# 而位置/尺寸恰恰就是这里唯一的病根：第 4 轮真渲染（`--aim=PortCraneBoom0:1200`）
	# 拍到吊臂作业灯是 **85 px 的实心白方块** —— 因为它是 70×40×70 m 的自发光盒。
	#
	# 所以退一步钉两件事（它们合起来足以挡住"再退回去"）：
	#   ① 那个常数本身是"点"的量级（不是板）；
	#   ② **两个贴脸构件**的调用点真的在用它，而且旧的大尺寸字面量已经不在函数体里。
	# ②用 `_strip_comments()` 之后的函数体 —— 否则函数注释里那句
	# "第一版这里是 110×36×110" 会把这条断言自己判死（本套件踩过同款坑）。
	var dot := WorldBuilder.CITY_LAMP_DOT
	t.lt(dot.x, 30.0, "构件灯头 `CITY_LAMP_DOT.x` = %.0f m < 30 ⇒ 是「点」的量级" % dot.x)
	t.lt(dot.x, WorldBuilder.CITY_LAMP_HEAD.x,
		("构件灯头（%.0f m）比**远景**路灯灯头（%.0f m）更小 —— "
			+ "路灯是 700~5000 m 外看的点阵、构件灯头是 100~500 m 擦脸而过的，两者不能共用一个尺寸")
			% [dot.x, WorldBuilder.CITY_LAMP_HEAD.x])
	var wsrc4 := _strip_comments(_src("res://scripts/world/world_builder.gd"))
	var crane_body := _func_body(wsrc4, "func _city_container_port")
	var sands_body := _func_body(wsrc4, "func _city_sands")
	t.ok(crane_body.contains("CITY_LAMP_DOT"),
		"吊臂作业灯的灯头用的是 `CITY_LAMP_DOT`（不是写死的大盒子）")
	t.ok(not crane_body.contains("70.0, 40.0, 70.0"),
		"`_city_container_port()` 里已经没有 70×40×70 那个大灯头（1200 m 处 85 px 的白板）")
	t.ok(sands_body.contains("CITY_LAMP_DOT"),
		"金沙「船」沿灯带的灯头用的是 `CITY_LAMP_DOT`")
	t.ok(not sands_body.contains("110.0, 36.0, 110.0"),
		"`_city_sands()` 里已经没有 110×36×110 那个大灯头（250 m 处会摊成 350 px 盖住视野）")

	# ================================================================ 船底结构（轮 5）
	#
	# ## 这几条为什么非要有
	# 轮 5 的定向 A/B 把病根量出来了（`_pix_m12.sh`）：船底的 `edge_density = 0.0000`
	# —— 一块 **9650 × 1500 m 的零边缘平面**，而它的用途是"沿船底掠过"
	#（设计书 §3.2 的签名动作）。同一组 A/B 还证明它**确实在吃环境光**
	#（关掉 `--amben` 就归零）⇒ 病根是**结构**、不是照度。
	#
	# 所以"给船底加了东西"这件事必须有断言守着：下一次有人为了"让船好看一点"
	# 把肋梁删掉，画面会**安静地**退回一块死板 —— 这正是本轮修的那个东西。
	t.ok(sands_body.contains("CITY_SHIP_CLEAR"),
		"净空槽走的是上游常量 `CITY_SHIP_CLEAR`（不再是从船心 `h + 520` 与船厚反推的差）")
	t.ok(not wsrc4.contains("h + 520.0"),
		"`world_builder.gd` 里已经没有写死的 `h + 520.0`（那个写法把「玩法通道宽度」"
			+ "藏进两个观感数字的差里，改任一个都会静默改窄它）")
	t.ok(sands_body.contains("CITY_SHIP_RIB_N") and sands_body.contains("SandsRibs"),
		"船底有横肋（`SandsRibs`）—— 贴槽飞时\"一道道从头顶掠过\"的那个参照")
	t.ok(sands_body.contains("SandsKeel"), "船底有纵边梁（`SandsKeel0/1`）—— 槽的两条\"车道线\"")
	t.ok(sands_body.contains("SandsBellyLights"),
		"船底有作业灯（`SandsBellyLights`）—— 各向同性环境光下肋梁不会靠明暗显形，只能靠灯")

	# ============================================================ 船顶甲板（轮 6）
	#
	# 轮 5 的 `--pitch=42` 俯视取证：船顶是一块 9550 × 1500 m 的**素板**
	#（与船底"零边缘平面"是同一个病的两个面）。轮 6 给它加了空中花园。
	#
	# ⚠️ 这批断言里真正值钱的是**最后那两条不变量**，不是"节点在不在"：
	# "加了什么"看一眼源码就知道，而"新加的东西有没有捅穿玩法通道"没人看得出来
	#（那块区域在船体板的暗面里，画面上没有任何异常）。
	var strips_n := _nodes_prefixed(w._terrain_root, "SandsDeckStrips")
	var garden_n := _nodes_prefixed(w._terrain_root, "SandsSkyGarden")
	var decklight_n := _nodes_prefixed(w._terrain_root, "SandsDeckLights")
	t.ok(strips_n.size() > 0, "达沃建出了船顶铺装带（`SandsDeckStrips`）—— 平飞时的方向读数")
	t.ok(garden_n.size() > 0, "达沃建出了空中花园（`SandsSkyGarden`）—— 打破素板的均匀度")
	t.ok(decklight_n.size() > 0,
		"达沃建出了甲板景观灯（`SandsDeckLights`）—— 与船底同一个理由："
			+ "各向同性的夜间环境光下，新加的矮构件不会靠明暗自己显形")
	var parapet := _box_xf(w._terrain_root, "SandsParapet1")
	var pool := _box_xf(w._terrain_root, "SandsPool")
	var mast := _box_xf(w._terrain_root, "SandsMast0")
	t.ok(parapet["size"] != Vector3.ZERO and pool["size"] != Vector3.ZERO \
			and mast["size"] != Vector3.ZERO,
		"达沃建出了女儿墙 / 泳池 / 桅杆（`SandsParapet1` + `SandsPool` + `SandsMast0`）")
	# ⚠️⚠️ 本组最重要的一条：**船顶构件一个都不许沉到船体板以下**。
	# 往下长的构件全受 `CITY_SHIP_CLEAR` 管（那条槽是玩法通道），船顶这批是"往上长"的。
	# 一旦有人写错符号或漏加 `ship_top`，某个构件就会**戳进净空槽** ——
	# 而画面上完全看不出来（那片在船体板的暗面里），只有玩家贴槽飞时撞上一个幽灵碰撞体。
	if parapet["size"] != Vector3.ZERO and ship["size"] != Vector3.ZERO:
		var ship_top_y: float = float(ship["pos"].y) + float(ship["size"].y) * 0.5
		var parapet_bot: float = float(parapet["pos"].y) - float(parapet["size"].y) * 0.5
		t.gt(parapet_bot, ship_top_y - 1.0,
			("船顶构件的最低点（女儿墙底 %.0f m）不低于船体板顶面（%.0f m）"
				+ " ⇒ 往上长的几何没有回捅进净空槽") % [parapet_bot, ship_top_y])
		var pool_bot: float = float(pool["pos"].y) - float(pool["size"].y) * 0.5
		t.gt(pool_bot, ship_top_y - 1.0,
			"泳池底面（%.0f m）在甲板面（%.0f m）之上，不是「沉进去」的" % [pool_bot, ship_top_y])
		var mast_top: float = float(mast["pos"].y) + float(mast["size"].y) * 0.5
		t.gt(mast_top, ship_top_y + 300.0,
			"桅杆顶（%.0f m）高出甲板面 %.0f m ⇒ 远景剪影里船顶有「桅杆」这个读数"
				% [mast_top, mast_top - ship_top_y])

	# ================================================================ 港区高杆灯（轮 5）
	#
	# 同一次真渲染量出来：港区整帧 `dark_ratio = 0.9757`（97.6% 的像素低于暗阈），
	# 而那片堆场的用途是"低空穿越障碍" —— 看不见的东西不是障碍，是坑。
	# 真实港区夜里靠**几座高杆灯塔**照亮堆场（不是每个箱子装灯），照这个做的。
	t.ok(crane_body.contains("PortLightMast"),
		"港区有高杆灯（`PortLightMast`）—— 真实堆场夜间的照明主体")
	t.ok(crane_body.contains("PortFloodHeads"),
		"高杆灯的灯头走 MultiMesh（`PortFloodHeads`：6 座 × 5 盏，一次 draw call）")
	# ============================================================ 港区**真光源**（轮 6）
	#
	# 轮 5 加了高杆灯（自发光）与反照率，量出来 `dark_ratio` 只从 0.9757 走到 0.9743
	# —— 因为**自发光不是光源**（Godot 的自发光只亮自己那一个像素）。
	# 轮 6 补的是"照别人的灯"：`OmniLight3D`。
	t.ok(crane_body.contains("OmniLight3D"),
		"港区有**真光源**（`OmniLight3D`）—— 全工程第一批\"照别人的灯\""
			+ "（自发光提不了别人的亮度，只能提自己的）")
	t.ok(crane_body.contains("PortFloodLights"),
		"6 颗泛光灯收在一个带位置的容器 `PortFloodLights` 里"
			+ "（`--aim` 能瞄准它、`--portlights=0` 一次关整批）")
	t.ok(crane_body.contains("shadow_enabled = false"),
		"港区泛光灯**不开实时阴影**（6 盏 4800 m 射程的阴影是灾难级代价，"
			+ "而夜里没有第二光源 ⇒ 省掉的差异玩家看不见）")
	t.ok(crane_body.contains("CITY_PORT_FLOOD_RANGE") and crane_body.contains("CITY_PORT_FLOOD_ENERGY"),
		"射程与能量都取常量（`CITY_PORT_FLOOD_*`）—— 剂量表量出来的数要能被引用")
	# ⚠️ 灯头的 MultiMesh **不能**再叫 `PortLightMasts`：它与灯杆 `PortLightMast%d`
	# 共享前缀 ⇒ 探针 `--aim=PortLightMast` 会同时命中"6 根杆 + 1 个灯头批次"，
	# 距离统计与质心全被污染，而且**不报错、只给一个看起来正常的错机位**。
	t.ok(not crane_body.contains("\"PortLightMasts\""),
		"灯头 MultiMesh 已改名（不再与灯杆 `PortLightMast%d` 共享前缀 —— "
			+ "那会让 `--aim=PortLightMast` 静默取到一个混合质心）")

	# ============================================================ 港区堆场：**行 + 道**（轮 7）
	#
	# ## 为什么这一批能做成**几何断言**（而轮 4~6 的构件只能做源码断言）
	#
	# 轮 4~6 反复写"灯头/线脚挂在 `MultiMesh` 上 ⇒ 无头模式下
	# `get_instance_transform()` 读回来全是单位变换 ⇒ 只能退到源码 `contains`"。
	# 轮 7 把堆场布局抽成了**纯函数** `WorldBuilder.port_yard_layout()`
	# ⇒ "排到哪儿去了"第一次可以被**算**。下面每一条都作用在真实几何上。
	#
	# 这也是这一轮的**核心不变量**所在：轮 7 的真渲染归因（`_pix_m21.sh`）量出
	# "蘑菇田"是那 6 颗灯照出来的，但**灯只是放大器** —— 病根是 220 个货柜由
	# `randf_range(-3500, 3500)` 均匀撒开、没有行也没有道：
	# 每一块都是"孤立物体"，而且**一条可飞行的走廊都没有**。
	var apron := _box_xf(w._terrain_root, "PortApron")
	t.ok(apron["size"] != Vector3.ZERO, "达沃建出了港区码头面（`PortApron`）")
	if apron["size"] != Vector3.ZERO:
		var pc := Vector3(apron["pos"].x, 0.0, apron["pos"].z)
		var bl: Array = WorldBuilder.port_yard_layout(pc)
		t.eq(bl.size(), WorldBuilder.PORT_YARD_ROWS * WorldBuilder.PORT_BAY_N,
			"堆场共 %d 节 = %d 块 × %d 节/块"
				% [bl.size(), WorldBuilder.PORT_YARD_ROWS, WorldBuilder.PORT_BAY_N])
		# ---- 归并成"块"（沿 X 的每一条长排）----
		var rows := {}
		for b: Dictionary in bl:
			var rk: int = b["row"]
			var p: Vector3 = b["pos"]
			var s: Vector3 = b["size"]
			if not rows.has(rk):
				rows[rk] = {"left": p.x - s.x * 0.5, "right": p.x + s.x * 0.5,
					"zmin": p.z - s.z * 0.5, "zmax": p.z + s.z * 0.5,
					"top": p.y + s.y * 0.5, "bot": p.y - s.y * 0.5, "tops": []}
			var rec: Dictionary = rows[rk]
			rec["zmin"] = minf(float(rec["zmin"]), p.z - s.z * 0.5)
			rec["zmax"] = maxf(float(rec["zmax"]), p.z + s.z * 0.5)
			rec["top"] = maxf(float(rec["top"]), p.y + s.y * 0.5)
			rec["bot"] = minf(float(rec["bot"]), p.y - s.y * 0.5)
			(rec["tops"] as Array).append(p.y + s.y * 0.5)
		t.eq(rows.size(), WorldBuilder.PORT_YARD_ROWS,
			"布局分成 %d 条块（沿 X 排开，每条沿 Z 铺满）" % rows.size())
		var slim_min := 1e9
		var left_min := 1e9
		var right_max := -1e9
		var top_max := -1e9
		for rk2 in rows:
			var r2: Dictionary = rows[rk2]
			var w_x: float = float(r2["right"]) - float(r2["left"])
			var l_z: float = float(r2["zmax"]) - float(r2["zmin"])
			slim_min = minf(slim_min, l_z / maxf(w_x, 0.001))
			left_min = minf(left_min, float(r2["left"]))
			right_max = maxf(right_max, float(r2["right"]))
			top_max = maxf(top_max, float(r2["top"]))
		# ① **长条**，不是"方墩"：一条块沿 Z 铺满整个堆场长度。
		t.gt(slim_min, 15.0,
			("每条块的长:宽 ≥ %.1f（%.0f × %.0f m）⇒ 是「长排」而不是「孤立方块」"
				+ "—— 这正是轮 7 要换掉的那个观感") % [slim_min, slim_min * WorldBuilder.PORT_BLOCK_W,
					WorldBuilder.PORT_BLOCK_W])
		# ② **不越码头西缘**：再过去就是运河的水面（货柜悬在水上会露馅）。
		t.gt(left_min, pc.x - float(apron["size"].x) * 0.5,
			"块的最西缘（%.0f m）仍在码头平台之内（%.0f m）"
				% [left_min, pc.x - float(apron["size"].x) * 0.5])
		# ③ **车道落在龙门吊的腿下面**（腿站在车道里，不站进货柜里）。
		#    这是本轮最要紧的一条几何不变量：腿与块都是带碰撞的实体，
		#    重叠会在低空穿越时变成一堵"不该存在的墙"。
		#    轮 7 第一版把 `PORT_PITCH` 取成"整数好看值" 1000（腿间距是 900）
		#    ⇒ −X 侧那条腿只剩 **15 m** 净距 —— 就是这条断言该拦下的东西。
		#
		# ⚠️ 判据是"**落在车道中心**"，不是"没有撞上货柜"。
		#
		# 这是本轮**唯一一次反向对照没通过**换来的教训：第一版断言写的是
		# "腿到最近块面净距 > 100 m"，把 `PORT_PITCH` 改成 1000（腿间距是 900）
		# 之后它**照样全绿** —— 因为 `PORT_YARD_ANCHOR_X` 是由 `PITCH/2` 解出来的，
		# 锚点会自动补偿，那条腿只是**偏离车道中心 100 m**，离块面还有 165 m。
		# 也就是说：那条断言对"PITCH 取错"这件事**根本没有牙齿**。
		#（真正会撞进货柜的是 `PORT_BLOCK_W` 变大，不是 PITCH 取错。）
		#
		# 真正的设计意图写在 `PORT_PITCH` 的注释里："两条腿自动落在相邻两条车道的
		# **同一相对位置**" —— 它等价于"每条腿在车道**正中**"，
		# 也就是"到左右两侧块面的净距**相等**"。断言这一条，反向对照才抓得住。
		var iv: Array = []
		for rk3 in rows:
			var r3: Dictionary = rows[rk3]
			iv.append(Vector2(float(r3["left"]), float(r3["right"])))
		iv.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		for leg_nm in ["PortCraneLeg0_-1", "PortCraneLeg0_1"]:
			var leg := _box_xf(w._terrain_root, leg_nm)
			t.ok(leg["size"] != Vector3.ZERO, "龙门吊的腿 `%s` 建出来了" % leg_nm)
			if leg["size"] == Vector3.ZERO:
				continue
			var l0: float = float(leg["pos"].x) - float(leg["size"].x) * 0.5
			var l1: float = float(leg["pos"].x) + float(leg["size"].x) * 0.5
			# 它两侧最近的块面（按 X 排序后，左边第一个的右缘 / 右边第一个的左缘）
			var gap_lo := -1.0
			var gap_hi := -1.0
			for i in iv.size():
				var span: Vector2 = iv[i]
				if span.y < l0:
					gap_lo = l0 - span.y
				elif span.x > l1 and gap_hi < 0.0:
					gap_hi = span.x - l1
			t.gt(gap_lo, 100.0,
				"`%s` 西侧净距 %.0f m > 100（腿站在车道里，不站进货柜里）" % [leg_nm, gap_lo])
			t.gt(gap_hi, 100.0,
				"`%s` 东侧净距 %.0f m > 100" % [leg_nm, gap_hi])
			t.lt(absf(gap_lo - gap_hi), 120.0,
				("`%s` 两侧净距之差 %.0f m < 120 ⇒ 腿在车道**正中**"
					+ "（`PORT_PITCH` 必须 = 2 × `PORT_CRANE_LEG_DX` = %.0f，"
					+ "否则两条腿会各自偏离车道中心，靠边的那条贴到块上）")
					% [leg_nm, absf(gap_lo - gap_hi), 2.0 * WorldBuilder.PORT_CRANE_LEG_DX])
		# ④ **臂下净空为正**："从两腿之间穿过去"这条玩法要有可飞的槽。
		var boom := _box_xf(w._terrain_root, "PortCraneBoom0")
		t.ok(boom["size"] != Vector3.ZERO, "龙门吊的吊臂 `PortCraneBoom0` 建出来了")
		if boom["size"] != Vector3.ZERO:
			var boom_bot: float = float(boom["pos"].y) - float(boom["size"].y) * 0.5
			t.gt(boom_bot - top_max, 300.0,
				("臂下净空 %.0f m（吊臂底 %.0f m − 通道内最高货柜顶 %.0f m）"
					+ "—— 这条槽是「穿吊臂」玩法的一部分，堆高上限 `PORT_LAYER_MAX` 受它约束")
					% [boom_bot - top_max, boom_bot, top_max])
		# ⑤ **块内高度一致、块间有差别**：真实的堆场是"一条块一个高度"
		#    （全随机 ⇒ 退回"随机撒盒"的观感；完全一致 ⇒ 变成一堵墙）。
		var within_max := 0.0
		var block_tops := []
		for rk4 in rows:
			var r4: Dictionary = rows[rk4]
			var tops: Array = r4["tops"]
			var lo := 1e9
			var hi := -1e9
			for tv in tops:
				lo = minf(lo, float(tv))
				hi = maxf(hi, float(tv))
			within_max = maxf(within_max, hi - lo)
			block_tops.append(hi)
		t.ok(within_max <= 2.0 * WorldBuilder.PORT_LAYER_H + 0.01,
			("同一条块内的节高起伏 %.0f m ≤ 2 层（%.0f m）—— "
				+ "块内只该有轻微起伏，差别该落在块与块之间") % [within_max, 2.0 * WorldBuilder.PORT_LAYER_H])
		var uniq := {}
		for tv2 in block_tops:
			uniq[snappedf(float(tv2), 1.0)] = true
		t.gt(uniq.size(), 1, "块与块之间的高度有差别（%d 种不同的顶高）" % uniq.size())
		# ⑥ **高杆灯也站在车道里**（不在货柜里），且不占吊腿那两条车道。
		var mast_xs := []
		for mn in _nodes_prefixed(w._terrain_root, "PortLightMast"):
			mast_xs.append((mn as Node3D).global_position.x)
		t.eq(mast_xs.size(),
			WorldBuilder.PORT_MAST_LANES.size() * WorldBuilder.PORT_MAST_ZS.size(),
			("高杆灯 %d 座 = %d 条车道 × %d 个 Z 位"
				+ "（不再「全挤在东侧一条线」上 —— 那样堆场西半场只剩 1/d² 的尾巴，"
				+ "而看不见的障碍不是障碍、是坑）")
				% [mast_xs.size(), WorldBuilder.PORT_MAST_LANES.size(),
					WorldBuilder.PORT_MAST_ZS.size()])
		var mgap := 1e9
		for mx2 in mast_xs:
			for rk5 in rows:
				var r5: Dictionary = rows[rk5]
				var a3: float = float(r5["left"])
				var b5: float = float(r5["right"])
				if mx2 < a3:
					mgap = minf(mgap, a3 - mx2)
				elif mx2 > b5:
					mgap = minf(mgap, mx2 - b5)
				else:
					mgap = -1.0
		t.gt(mgap, 100.0, "高杆灯的灯杆全部落在车道里：到最近块面 %.0f m > 100" % mgap)

	# ============================================================ 港区龙门吊：**一台岸桥**（轮 8）
	#
	# ## 病根（轮 8 的基线真渲染：`--aim=PortCraneBoom0:2000 --pitch=10`，+Z 侧正对门框）
	#
	# 那 8 台吊车读出来是"**两个桥墩顶着一根栏杆**"：两条腿是光秃秃的方柱、
	# 吊臂是一条光板，而且**两腿之间没有任何东西把它们连起来**。
	# 玩法是"贴海面进港 → 从两腿之间穿过去"，这台机器是玩家在港区里贴得最近的
	# 一个大件 —— 它读不出来，整个港区就只是"一片打了灯的停车场"。
	#
	# ## 为什么这一批既有几何断言、又有节点计数断言（**两者配对才是完整的**）
	#
	# 轮 8 把构件布局抽成了纯函数 `WorldBuilder.port_crane_layout()`：
	#   · **纯函数那半**证明的是**关系**（小车在臂跨内、吊具正吊在小车下方、
	#     通道净高够）。构件走 `_add_box()`，节点**能**读回来，但读回来的只有
	#     "它在哪" —— **没有尺寸关系**，所以这些必须作用在纯函数的输出上。
	#   · **节点计数那半**证明的是"这份布局**真的被建出来了**"。
	#     ⚠️ 只有前者会漏掉最蠢的一种错：布局算得漂漂亮亮，构建循环根本没调它。
	#     （反过来只有后者也不行：数得出 8 个盒子，但盒子在哪、合不合理全不知道。）
	var apron2 := _box_xf(w._terrain_root, "PortApron")
	if apron2["size"] != Vector3.ZERO:
		var pc2 := Vector3(apron2["pos"].x, 0.0, apron2["pos"].z)
		var crs: Array = WorldBuilder.port_crane_layout(pc2)
		t.eq(crs.size(), WorldBuilder.PORT_CRANE_N,
			"龙门吊 %d 台，每台一份构件布局" % crs.size())
		# ---- 基准面：堆场里最高的货柜顶（约束 ② 比的就是它）----
		var yard_top2: float = WorldBuilder.PORT_APRON_TOP \
			+ float(WorldBuilder.PORT_LAYER_MAX) * WorldBuilder.PORT_LAYER_H
		# ---- 通道：两条腿之间那块净空区（X 方向去掉腿本身的厚度）----
		var cxc: float = pc2.x + WorldBuilder.PORT_CRANE_CX
		var chan_half: float = WorldBuilder.PORT_CRANE_LEG_DX \
			- WorldBuilder.PORT_CRANE_LEG_W * 0.5
		# 带**玩法牙**的门槛：通道净高不许低于它（见下面 ①）。
		var chan_min := 500.0
		var portal_clear := 1e9      # 门框横梁的底面 = 通道净高
		var cross_low := 0           # **跨过整条通道**、却低于门槛的构件数
		var cross_low_y := 1e9
		var edge_margin := 1e9       # 小车/吊具边缘到臂端的最近距离
		var off_x := 0.0             # 吊具与小车的 X 偏差
		var off_z := 0.0             # 吊具与小车的 Z 偏差
		var cable_gap := 0.0         # 缆绳两端与小车底面/吊具顶面的最大缝
		var sp_clear := 1e9          # 吊具底面 − 最高箱顶
		var fit_missing := 0
		var trolley_xs := {}
		for cr: Dictionary in crs:
			var bp: Dictionary = cr["boom"]
			var bpos: Vector3 = bp["pos"]
			var bsz: Vector3 = bp["size"]
			var boom_lo: float = bpos.x - bsz.x * 0.5
			var boom_hi: float = bpos.x + bsz.x * 0.5
			var cz3: float = float((cr["legs"][0] as Dictionary)["pos"].z)
			for key: String in ["portal", "trolley", "rope", "spreader", "cab", "house"]:
				if not cr.has(key):
					fit_missing += 1
			var po: Dictionary = cr["portal"]
			var tr: Dictionary = cr["trolley"]
			var sp: Dictionary = cr["spreader"]
			var cbl: Dictionary = cr["rope"]
			portal_clear = minf(portal_clear,
				po["pos"].y - po["size"].y * 0.5)
			# ---- ① 通用：**跨过整条通道**的构件不许压低（防"以后再往通道里加东西"）----
			#
			# ⚠️ 判据刻意是"**跨过整条通道**"（X 跨度 ≥ 2 × LEG_DX），不是
			# "在通道里" —— 小车 / 吊具 / 缆绳**本来就该吊在通道里**
			# （真实岸桥的吊具就在堆场上方作业，玩家绕过它是玩法），
			# 而"一道横跨整个门口的低梁"才是把通道堵死的那种东西。
			for key2: String in ["boom", "portal", "trolley", "rope",
					"spreader", "cab", "house"]:
				if not cr.has(key2):
					continue
				var p2: Dictionary = cr[key2]
				if p2["size"].x < WorldBuilder.PORT_CRANE_LEG_DX * 2.0:
					continue
				var btm: float = p2["pos"].y - p2["size"].y * 0.5
				if btm < chan_min:
					cross_low += 1
					cross_low_y = minf(cross_low_y, btm)
			# ---- ② 小车 / 吊具必须在**臂跨之内**（吊到臂外面就是悬空）----
			trolley_xs[snappedf(float(tr["pos"].x), 1.0)] = true
			for part: Dictionary in [tr, sp]:
				edge_margin = minf(edge_margin, minf(
					(part["pos"].x - part["size"].x * 0.5) - boom_lo,
					boom_hi - (part["pos"].x + part["size"].x * 0.5)))
			# ---- ③ 吊具必须**正吊在它自己那台小车下面**，且底面高于最高箱顶 ----
			off_x = maxf(off_x, absf(float(sp["pos"].x) - float(tr["pos"].x)))
			off_z = maxf(off_z, absf(float(sp["pos"].z) - float(tr["pos"].z)))
			sp_clear = minf(sp_clear,
				(sp["pos"].y - sp["size"].y * 0.5) - yard_top2)
			# ---- ④ 缆绳两端必须**贴住**小车底面与吊具顶面（这是"解出来的"关系）----
			var c_top: float = cbl["pos"].y + cbl["size"].y * 0.5
			var c_bot: float = cbl["pos"].y - cbl["size"].y * 0.5
			cable_gap = maxf(cable_gap, maxf(
				absf(c_top - (tr["pos"].y - tr["size"].y * 0.5)),
				absf(c_bot - (sp["pos"].y + sp["size"].y * 0.5))))
		t.eq(fit_missing, 0,
			"每台都带齐门框 / 小车 / 缆绳 / 吊具 / 司机室 / 机器房（缺 %d 件）" % fit_missing)
		# ---- ① 通道净高：**本轮唯一带玩法牙的一条** ----
		#
		# ⚠️ 它防的不是"这一版写错了"，而是"**以后有人往通道里加结构**"
		#（门框下横梁 / 斜撑 / 减速门）。真实的岸桥**有**下横梁，
		# 所以这个诱惑是真实存在的 —— 而它会把"贴海面进港、从两腿之间穿过去"
		# 这条通道直接堵死。轮 8 的取舍写在常量里：门框只架在**顶部**。
		t.gt(portal_clear, chan_min,
			("通道净高 %.0f m > %.0f —— 门框横梁只架在顶部（臂底 735 之下 70 m 厚）"
				+ "；真实的岸桥有下横梁，在这里那一根就是一堵墙") % [portal_clear, chan_min])
		t.eq(cross_low, 0,
			("没有任何构件**横跨整条通道**却低于 %.0f m（违规 %d 件%s）—— "
				+ "⚠️ 判据是「横跨整条通道」而不是「在通道里」："
				+ "小车 / 吊具 / 缆绳本来就该吊在通道里（玩家绕过它们是玩法），"
				+ "而一道横跨门口的低梁是把通道堵死的那种东西")
				% [chan_min, cross_low,
					"" if cross_low == 0 else "，最低 %.0f m" % cross_low_y])
		t.gt(edge_margin, 0.0,
			("小车与吊具全部落在臂跨之内：边缘到臂端最少 %.0f m（臂跨 %.0f m）")
				% [edge_margin, WorldBuilder.PORT_CRANE_BOOM_L])
		t.lt(off_x, 0.01,
			"吊具正吊在它自己那台小车的正下方（X 偏差 %.3f m）" % off_x)
		t.lt(off_z, 0.01, "吊具与小车同 Z（偏差 %.3f m）" % off_z)
		t.lt(cable_gap, 0.01,
			("缆绳两端严丝合缝（最大缝 %.3f m）—— 缆绳高度是**从两端解出来**的，"
				+ "不是写死的，所以调小车/吊具高度不会留下一段悬空的管子") % cable_gap)
		t.gt(sp_clear, 0.0,
			("吊具底面比堆场最高箱顶高 %.0f m（箱顶 %.0f m）—— 约束 ②："
				+ "吊具啃进箱子里既是穿模，又会多出一个看得见撞不到的幽灵障碍")
				% [sp_clear, yard_top2])
		t.eq(trolley_xs.size(), WorldBuilder.PORT_CRANE_N,
			("%d 台小车停在互不相同的位置（不同 X 的个数 = %d，期望 %d）—— "
				+ "不是 N 个克隆体，而是「都在各干各的活」")
				% [WorldBuilder.PORT_CRANE_N, trolley_xs.size(), WorldBuilder.PORT_CRANE_N])
		# ---- ⑤ 吊臂作业灯：在臂跨内，且**不被机器房盖住** ----
		#
		# ⚠️ 这一条是轮 8 加机器房时**真的踩到**的：旧灯排第一个点在 `cx − 700`，
		# 而机器房落在 `cx − 1180 … cx − 620`、高 795 … 955，灯的 y（855）
		# 正落在机器房的区间里 ⇒ 第一盏灯被盒子盖掉。
		# **它不报错、不变暗，只表现为「少了一个亮点」** —— 与"这盏灯没接线"
		# 在画面上完全一样。这类"静默少一件"只有靠算盒子的交叠才抓得住。
		var lts: Array = WorldBuilder.port_crane_lights(pc2)
		t.eq(lts.size(), WorldBuilder.PORT_CRANE_N * WorldBuilder.PORT_CRANE_LIGHT_N,
			"吊臂作业灯 %d 盏 = %d 台 × %d 盏/台"
				% [lts.size(), WorldBuilder.PORT_CRANE_N, WorldBuilder.PORT_CRANE_LIGHT_N])
		var lit_out := 0
		var lit_house := 0
		for ci in lts.size():
			var ci_k: int = int(ci) / int(WorldBuilder.PORT_CRANE_LIGHT_N)
			var lv: Vector3 = lts[ci]
			var bp3: Dictionary = crs[ci_k]["boom"]
			if lv.x < bp3["pos"].x - bp3["size"].x * 0.5 \
					or lv.x > bp3["pos"].x + bp3["size"].x * 0.5:
				lit_out += 1
			var hz: Dictionary = crs[ci_k]["house"]
			if absf(lv.x - hz["pos"].x) < hz["size"].x * 0.5 \
					and absf(lv.z - hz["pos"].z) < hz["size"].z * 0.5 \
					and absf(lv.y - hz["pos"].y) < hz["size"].y * 0.5:
				lit_house += 1
		t.eq(lit_out, 0, "吊臂作业灯全部落在臂跨之内（越界 %d 盏）" % lit_out)
		t.eq(lit_house, 0,
			("吊臂作业灯没有被机器房盖住（%d 盏在盒子里）—— ⚠️ 这一种错不报错、"
				+ "不变暗，只表现为「少了一个亮点」，与「灯没接线」在画面上完全一样")
				% lit_house)
		# ---- ⑥ 台车必须**收在腿的 footprint 之内**（不然就是一圈看不见的突起）----
		var bogie_ok := true
		var bogie_over := ""
		for cr2: Dictionary in crs:
			for i2 in 2:
				var bo: Dictionary = cr2["bogies"][i2]
				var lg2: Dictionary = cr2["legs"][i2]
				if bo["size"].x > lg2["size"].x or bo["size"].z > lg2["size"].z:
					bogie_ok = false
					bogie_over = "%s×%s vs 腿 %s×%s" % [bo["size"].x, bo["size"].z,
						lg2["size"].x, lg2["size"].z]
		t.ok(bogie_ok,
			("台车全部收在腿的 footprint 之内 %s —— 宽出去就成了「看得见但撞不到」"
				+ "的一圈突起（轮 6 的幽灵碰撞同一族病）：要么有碰撞、要么不出 footprint")
				% ("" if bogie_ok else "（首个越界：%s）" % bogie_over))
		# ---- ⑦ 这份布局**真的被建出来了**（只算不建 = 最蠢的一种错）----
		var fit_nodes := {
			"PortCranePortal": "门框横梁", "PortCraneTrolley": "小车",
			"PortCraneRope": "缆绳", "PortCraneSpreader": "吊具",
			"PortCraneCab": "司机室", "PortCraneHouse": "机器房",
		}
		for pfx: String in fit_nodes:
			var cnt := _nodes_prefixed(w._terrain_root, pfx).size()
			t.eq(cnt, WorldBuilder.PORT_CRANE_N,
				"世界里真的建出了 %d 件%s（前缀 `%s`）" % [cnt, fit_nodes[pfx], pfx])
		t.eq(_nodes_prefixed(w._terrain_root, "PortCraneLeg").size(),
			WorldBuilder.PORT_CRANE_N * 2,
			"两条腿 × %d 台 = %d 根（老命名 `_−1 / _+1` 没变，探针机位还在用）"
				% [WorldBuilder.PORT_CRANE_N,
					_nodes_prefixed(w._terrain_root, "PortCraneLeg").size()])

	# ============================================================ 高杆灯架：**在灯之下**（轮 7）
	#
	# 病根一句话：旧灯架（`PortLightHead`，300×36×300 的**板**）架在灯**上方** 40 m，
	# 它朝下的面正对着下方的点光（法线与光线夹角 ≈ 0）⇒ 全亮，
	# 5 km 外的广角里就是一把把"发光的伞"（`_pixprobe_M15_wide_e2000.png`）。
	t.gt(WorldBuilder.CITY_PORT_LAMP_Y,
		WorldBuilder.CITY_PORT_ARM_Y + WorldBuilder.CITY_PORT_ARM_T * 0.5,
		("灯头（%.0f m）在**灯架顶面之上**（%.0f m）—— 反过来就是「发光的伞」的病根"
			+ "（朝下的面正对点光）")
			% [WorldBuilder.CITY_PORT_LAMP_Y,
				WorldBuilder.CITY_PORT_ARM_Y + WorldBuilder.CITY_PORT_ARM_T * 0.5])
	t.lt(2.0 * WorldBuilder.CITY_PORT_ARM_L * WorldBuilder.CITY_PORT_ARM_W, 300.0 * 300.0,
		("两片悬臂的朝上面合计 %.0f m² < 旧板的 %.0f m²（那个面正对下方的点光 ⇒ 全亮）"
			% [2.0 * WorldBuilder.CITY_PORT_ARM_L * WorldBuilder.CITY_PORT_ARM_W, 300.0 * 300.0]))
	var wsrc7 := _strip_comments(_src("res://scripts/world/world_builder.gd"))
	t.ok(not wsrc7.contains("PortLightHead"),
		"`PortLightHead`（架在灯**上方**的板 ⇒ 广角里的「发光伞」）已经不在了")
	t.ok(wsrc7.contains("PortLightArm"),
		"灯架改成了 `PortLightArm`（24 厚的十字悬臂，在灯之下）")
	t.ok(not wsrc7.contains("randf_range(-3500.0, 3500.0)"),
		("「随机撒盒」的字面量已经不在了 —— 货柜的位置不再由 ±3500/±3300 的均匀随机决定"
			+ "（那是「蘑菇田」与「没有走廊」的共同来源）"))

	root.free()
	await host.get_tree().process_frame


## 每一带云的主光方向都等于 [param want]。
static func _all_clouds_point_at(w: WorldBuilder, want: Vector3) -> bool:
	for m in w._cloud_mats:
		var v: Variant = m.get_shader_parameter("sun_dir")
		if v == null or not (v is Vector3):
			return false
		if (v as Vector3).distance_to(want) > 0.001:
			return false
	return true


## `_terrain_root` 下第一个名字以 [param prefix] 开头的体量的材质。
static func _first_material(w: WorldBuilder, prefix: String) -> Material:
	for c: Node in w._terrain_root.get_children():
		if not String(c.name).begins_with(prefix):
			continue
		for gc: Node in c.get_children():
			var mi := gc as MeshInstance3D
			if mi != null:
				return mi.material_override
	return null


## 挂在 `StaticBody3D` 下、**局部位置不为零**的网格清单（人类可读）。
##
## 空清单 = 不变量成立：**世界坐标由 `body` 承担，网格保持零位**（`_add_box()` 的写法）。
## 非空 = 该网格的世界位置是"设计值 + body 位置"，即被父节点重复加了一次偏移。
##
## 只查 `StaticBody3D` 的**直接**子节点：本工程的地标/楼体一律是"一个 body 一个网格"，
## 世界坐标挂在 body 上；再深一层就属于另一套结构，不属于这条不变量管辖。
static func _body_mesh_offsets(root: Node) -> Array:
	var out := []
	if root == null:
		return out
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var b := n as StaticBody3D
		if b != null:
			for c in b.get_children():
				var mi := c as MeshInstance3D
				if mi != null and not mi.position.is_zero_approx():
					out.append("%s/%s 偏 %s" % [b.name, mi.name, str(mi.position)])
		for c in n.get_children():
			stack.append(c)
	return out


## 名字**完全等于** [param nm] 的第一个 Node3D（找不到返回 null）。
##
## 用精确名而不是前缀：地标常常是一个 body 套一个同名网格
##（`FujiSphereBody` / `FujiSphere`），前缀匹配会随机命中其中一个 ——
## 而"命中的是哪一个"恰恰是这里要判的东西。
static func _node_named(root: Node, nm: String) -> Node3D:
	if root == null:
		return null
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if String(n.name) == nm:
			return n as Node3D
		for c in n.get_children():
			stack.append(c)
	return null


## 名字以 [param prefix] 开头的所有 Node3D。
##
## 用于**拿场景里已有的兄弟节点当参照物**（例：倒锥拿四座塔的 x 区间当参照），
## 这样就不必把工程里的尺寸字面量在测试里再抄一份。
static func _nodes_prefixed(root: Node, prefix: String) -> Array:
	var out := []
	if root == null:
		return out
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if String(n.name).begins_with(prefix):
			var n3 := n as Node3D
			if n3 != null:
				out.append(n3)
		for c in n.get_children():
			stack.append(c)
	return out


## 场景里所有的港区泛光灯（`OmniLight3D`），按建图顺序返回。
##
## ⚠️ 必须**再过滤一次类型**：前缀 `PortFloodLight` 会同时命中容器
##（`PortFloodLights`）与 6 颗灯 ⇒ 直接数 `_nodes_prefixed()` 的结果会得到 7。
## 这一步顺带把"容器与灯是两类节点"这件事钉住了。
static func _flood_lamps(root: Node) -> Array:
	var out := []
	for n in _nodes_prefixed(root, "PortFloodLight"):
		if n is OmniLight3D:
			out.append(n)
	return out


## 一个 `_add_box()` 建出来的盒子的**世界位置**与**尺寸**。
##
## `_add_box()` 的结构是"位置挂 body、尺寸挂子网格"（`MeshInstance3D.scale = size`，
## 见 `_body_mesh_offsets()` 那条不变量）。两样一次拿到，免得每条断言各拆一遍父子。
## 找不到节点时 `size` 返回 `Vector3.ZERO` —— 调用方拿它当"没建出来"的判据。
static func _box_xf(root: Node, nm: String) -> Dictionary:
	var node := _node_named(root, nm)
	if node == null:
		return {"pos": Vector3.ZERO, "size": Vector3.ZERO}
	for c in node.get_children():
		var mi := c as MeshInstance3D
		if mi != null:
			return {"pos": node.global_position, "size": mi.scale}
	return {"pos": node.global_position, "size": Vector3.ZERO}


## 场景里所有 `Tower_*` 的**高宽比均值**（高 ÷ 平面的长边）。
##
## ⚠️ 用 max(x, z) 而不是 x：塔楼有 `±7°` 的 yaw，但 yaw 在 body 上、scale 上读不出来
## 旋转 —— 所以 scale 永远是"未经旋转的盒"。取长边只是为了对"宽"这件事不敏感。
##
## ⚠️ 刻意**不**引进"塔高应该多大"这类字面量：这一条只比较**同一段代码
## 在两份地图参数下的两次产出**（"细高"这件事的相对量），
## 所以它对"以后有人整体调高全城"是**免疫**的 —— 那种改动不该让它红。
static func _avg_tower_aspect(root: Node) -> float:
	var sum := 0.0
	var n := 0
	for node in _nodes_prefixed(root, "Tower_"):
		for c in node.get_children():
			var mi := c as MeshInstance3D
			if mi != null:
				var w := maxf(mi.scale.x, mi.scale.z)
				if w > EPS:
					sum += mi.scale.y / w
					n += 1
	return sum / float(n) if n > 0 else 0.0


## **塔宽 ÷ 裙房宽**的平均值 —— "塔楼在裙房里有多胖"的干净读数。
##
## ## 为什么要单独一个量具（而不是复用 `_avg_tower_aspect`）
## 高宽比（塔高 ÷ 塔宽）同时被 `lot.h`、子地块宽、塔宽三样影响，**与城强相关**：
## 两城的 `lot.h` 分布不同 ⇒ 光看高宽比量不出"同一座城里塔变粗了没有"。
## 而"塔宽 ÷ 裙房宽"里 `bw`/`bd` 全被约掉：
##   塔宽 = `bw × p × city_tower_w`、裙房宽 = `bw × q`
##   ⇒ 比值 = `p × city_tower_w / q`，**只由两个倍率与两对系数决定**。
##
## ## 怎么配对
## `Tower_<tag>` 与 `Podium_<tag>` 的 `tag` 是同一个（`gx_gz_slot`，见
## `_city_block_at()` 里那行 `var tag := …`）⇒ 按后缀就能配上，不需要额外索引。
## ⚠️ 依赖"节点名没被 Godot 改名"（重名会变成 `@StaticBody3D@1346`）——
## 与 `_avg_tower_aspect` 是同一个前提，而那个函数已经在用了 ⇒ 前提已被验证。
static func _avg_tower_podium_ratio(root: Node) -> float:
	var pod: Dictionary = {}
	for node in _nodes_prefixed(root, "Podium_"):
		for c in node.get_children():
			var mi := c as MeshInstance3D
			if mi != null:
				pod[str(node.name).substr(7)] = maxf(mi.scale.x, mi.scale.z)
	var sum := 0.0
	var n := 0
	for node in _nodes_prefixed(root, "Tower_"):
		for c in node.get_children():
			var mi := c as MeshInstance3D
			if mi != null:
				var w := maxf(mi.scale.x, mi.scale.z)
				var pw: float = float(pod.get(str(node.name).substr(6), 0.0))
				if w > EPS and pw > EPS:
					sum += w / pw
					n += 1
	return sum / float(n) if n > 0 else 0.0


# ============================================================ 工具

static func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


## 把源码里的注释剥掉，再做源码断言。
##
## ⚠️ **这不是洁癖，是必需的一步**（实测报过一条假 FAIL）：
## 本工程的注释习惯是"**为什么不用 X**"也要写清楚，于是注释里会**逐字**出现
## 被禁的符号 —— `city.gdshader` 的注释里写着"刻意不加 `: source_color`"，
## 而 `t.not_ok(city.contains("source_color"))` 正是要钉"没加"这件事，
## 不剥注释就会把自己人当违规。
##
## 两种注释都要剥，**语言不同**：
##   · **shader（`.gdshader`）= `//` 行注释 + `/* */` 块注释**；
##   · **GDScript（`.gd`）= `#` 行注释 + `/* */`（`"""` 文档块不在剥离范围）**。
## ⚠️ 第一版只剥了 `#`，于是 shader 里那句 `// ... source_color ...` 原样留着、
## 假 FAIL 照旧 —— **"剥了注释"这件事本身也要按语言确认，不能想当然**。
##
## 字符串里的符号一律不动（quote 状态机）—— 这条是必需的：本工程的 GDScript
## 里到处是 `"res://shaders/xxx.gdshader"`，无脑剥 `//` 会把路径拦腰截断，
## 于是"注释剥干净了、代码也没了"。
##
## `#` 后面紧跟字母时按**预处理指令**保留（`#include` / `#define` / `#ifdef`…）：
## 本工程目前一个都没有，但剥掉它们会制造一个"改了源码却看不出哪里被删"的坑。
##
## ⚠️ 剥完**换行原样保留**：`_func_body()` 按 `\nfunc ` 找函数边界，行结构不能被打乱。
static func _strip_comments(src: String) -> String:
	var out := ""
	var i := 0
	var n := src.length()
	var quote := ""            # "" = 不在字符串里，否则是那个引号字符
	var block := false
	while i < n:
		var c := src[i]
		var nxt := src[i + 1] if i + 1 < n else ""
		if block:
			if c == "*" and nxt == "/":
				block = false
				i += 2
				continue
			i += 1
			continue
		if quote != "":
			out += c
			if c == "\\":                       # 转义：连下一个字符一起吞掉
				if nxt != "":
					out += nxt
					i += 2
					continue
			elif c == quote:
				quote = ""
			i += 1
			continue
		if c == "/" and (nxt == "/" or nxt == "*"):
			block = nxt == "*"
			while i < n and src[i] != "\n":
				i += 1
			continue
		if c == "#" and not _is_alpha(nxt):
			while i < n and src[i] != "\n":
				i += 1
			continue
		if c == "\"" or c == "'":
			quote = c
		out += c
		i += 1
	return out


static func _is_alpha(c: String) -> bool:
	return c.length() == 1 and (
		(c >= "a" and c <= "z") or (c >= "A" and c <= "Z"))


## 取一个函数的函数体（到下一个顶层 `func ` 为止）。与 `suite_menu_frame` 同款。
static func _func_body(src: String, head: String) -> String:
	var at := src.find(head)
	if at < 0:
		return ""
	var rest := src.substr(at + head.length())
	var nxt := rest.find("\nfunc ")
	return rest.substr(0, nxt) if nxt >= 0 else rest
