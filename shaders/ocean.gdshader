shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// 海面：不依赖任何贴图，全部由解析波函数生成法线。
//
// 60 km 的平面不可能靠顶点位移做出细节，所以几何保持平坦，细节全走 fragment 的
// 有限差分法线。频率**直接以"米"为单位给出**（rad/m），这样每层对应多长波长一眼可读：
//   0.008 rad/m → 785 m 大洋涌浪
//   1.100 rad/m → 5.7 m 细碎波纹
// 另外按距离压平高频（fade）：一来省掉远处的高频闪烁与摩尔纹，
// 二来避免"贴海飞过时海面像一块糊住的蓝布"（这是第一版的真实问题）。
//
// ⚠️ 2026-09-23（批 K · 轮 1）：**`detail_fade` 从 0.0022 降到 0.0002**。
// 用户："太平洋上空没法看到波浪的渲染材质，看着还是和之前一样的效果"。
// 原值让 3.2 km 高空平视时整片可见海面的 `fade` 只剩 0.083~0.124
// ⇒ 海面读成一块**平的深蓝板**。为什么可以降、以及两个机位的扫描表，
// 见 `world_builder.gd` 的 `OCEAN_DETAIL_FADE`（真源在那里，这里有默认值只为
// "没传参数的调用点"兜底）。

// ---- 动画时钟（批 J）----
//
// ⚠️ **不用引擎内建的 `TIME`。** 这条是被一次"假 A/B"逼出来的：
// `TIME` 是**开机以来的墙钟时间**，两次跑探针它必然不同 ⇒ 波浪相位每次都不一样。
// 实测（2026-09-23，`--seacam=45` 贴海机位、**完全相同的参数连跑两次**）：
//   整帧均值 +0.99%，但**画面下三分之一的水面**逐行差到 **−64%**（第 685 行）。
// 于是"海雾 A/B"测到的所谓效果，量的是相位漂移 —— 而它长得和"一层雾"非常像
// （都是"亮度在某个区域内整体变了"），**光看数字分不开**。
//
// 换成脚本推进的 uniform 之后，探针可以把时钟 **pin 住**（见
// `WorldBuilder.pin_anim_time()` 与 pixprobe 的 `--animtime`）⇒ A/B 才可复算。
// 顺带一个好处：暂停时海面**真的停住**（`_process` 不再推进），与画面一致。
uniform float wave_time : hint_range(0.0, 1000000.0) = 0.0;

uniform vec3 deep_color : source_color = vec3(0.020, 0.082, 0.152);
uniform vec3 crest_color : source_color = vec3(0.10, 0.32, 0.44);
uniform vec3 sky_color : source_color = vec3(0.44, 0.64, 0.92);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.76, 0.92);

// ---- 月光镜面带（第十四轮 A1）----
//
// 玩家实测：「它说我撞海我都不知道海在哪」「主要是看不到离海有多远」。
// 夜里的海面原来是 `ocean_deep = (0.004, 0.012, 0.030)` —— 近似纯黑，
// 而天空地平线也是暗蓝，**海与天亮度几乎一样 → 没有地平线 → 不知道哪边是海**。
//
// 抬亮海面能解决"看得见"，但抬亮解决不了"哪个方向是水"。
// 月光在水面上的**镜面反射带**才解决后者：它是一条从玩家脚下指向月亮的亮带，
// 于是水面的方位、倾斜、以及"我离水面多高"都变得可读。
// 现实里也是这样看夜海的，所以它比单纯提亮更"对"。
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);      // 指向月亮（世界空间，单位向量）
uniform vec3 moon_color : source_color = vec3(0.55, 0.68, 0.95);
uniform float glitter_strength : hint_range(0.0, 4.0) = 0.0;
uniform float glitter_sharp : hint_range(8.0, 512.0) = 120.0;

// ---- 浪尖次表面（1.2.3 批 E）----
//
// 真实海浪在**迎光面**会透光发亮（逆光看时最明显：浪尖像被点着了一样）。
// 现有的 `crest * 0.75`（下面第 84 行那一处）**不带任何方向信息** ——
// 波峰就是波峰，朝哪边看都一样亮。加了这一项之后，"朝着月亮那一侧的浪尖"才亮。
//
// 权重用**水平方位上的反向**：把视线与天体方向都投到水平面，`-dot(vflat, mflat)` ——
// 相机与月亮在**同一侧**（玩家朝着月亮看）时取到 1，正是"逆光"。
//
// ⚠️⚠️ **这里原本写的是三维 `-dot(view_dir, normalize(moon_dir))`（教科书上的
// translucency 公式），2026-09-23 用像素探针实测后**推翻**了它。**
//
// 实测：`--sss=0`（把这一项关掉）之后，**R/G/B/亮度四个通道、画面全部区域
// 逐位为零** —— 连**专门摆的逆光机位**也一样，也就是这一项在游戏里根本看不出来。
//
// 反推原因（不是"没接线"，uniform 确实到位了）：
// 夜战预设固定是 `sun_rotation_deg = (-58, -42, 0)` ⇒ 月亮**仰角 58°**，
// 而相机在水面之上（`view_dir` 朝上）、玩家平视 ⇒ 三维点积里"两个朝上的分量相乘"
// 与"两个水平分量反向相乘"**几乎抵消**：实测 `view·moon ≈ +0.095`（水平分量 0.530），
// 平方之后权重只剩 **0.009**，乘上 `fade`（5 km 处 ≈0.08）已经远低于 8 位量化的一格。
//
// **结论**：三维点积在"高月亮 + 平视水面"这个组合下会把这一项压死 ——
// 而本工程的四张图**全部固定夜战**、月亮**永远 58°**，也就是说那个写法等于**永久关闭**。
// 改成只比水平方位之后，同一机位的权重是 `0.530² = 0.281`（**31 倍**）。
//
// 这是"**按可测的量做设计**"而不是把向量塞进公式就完事的一个例子：
// 公式本身没写错，但它在本工程唯一的那档光照下取值恒为零。
//
// ⚠️ 默认 **0**（关）。海面是 1.2 花大力气调过的（验收报告："看不到离海有多远" ⇒
// 抬亮 3 倍 + 拉开海天明度 + 月光镜面带），所以它是**纯增量**：
// 不设就是原样，设了只在"浪尖 + 逆光"那一小块叠加，不碰任何既有参数。
uniform float crest_sss : hint_range(0.0, 2.0) = 0.0;
uniform vec3 crest_sss_color : source_color = vec3(0.30, 0.62, 0.72);

// ---- 云影（第十四轮 A5）----
// 与地表共用同一张覆盖图（`WorldBuilder._bake_cloud_shade()`），
// 所以云在海面上的影子与在机体、沙丘上的影子一定对齐。
uniform sampler2D cloud_shade_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec2 cloud_field_origin = vec2(0.0);
uniform float cloud_field_span = 52000.0;
uniform float cloud_shade_strength : hint_range(0.0, 1.0) = 0.0;

uniform float normal_strength = 5.5;
uniform float epsilon = 0.7;
uniform float detail_fade = 0.0002;
uniform float roughness_sea = 0.06;
// 远处淡出到地平色。竞技场扩到 26 km 之后这两个值也跟着外推，
// 否则玩家飞到场地边缘会看到"海面颜色在 34 km 处硬邦邦地定住"
uniform float horizon_start = 9000.0;
uniform float horizon_end = 52000.0;

// ---- 水下地形：浅滩与礁盘（1.2.3 批 H · 轮 1）----
//
// 太平洋图**没有地表网格**（`WorldBuilder.ISLAND_COUNT = 0`，老板要求"小岛删掉，
// 不好看"），所以这张图的"地形细节"只剩一个容身之处：**水面之下**。
//
// 而"看得到水下有地形"本来就是靠**水色随水深变化** —— 浅处透出沙色与青绿，
// 深处是纯黑。真实的海图/航拍能读出礁盘，靠的也正是这个，不是靠浪。
//
// 于是这里用**纯函数**造一张水深图（三层 fbm，形状见 `_shoal_field`），
// 再由它驱动两层着色：
//   · 礁盘**斜坡**（中等深度）→ `shoal_color`（青绿，透出浅水）；
//   · 礁盘**顶面**（最浅，珊瑚砂接近露出水面）→ `foam_color`（几乎白）。
// 白沫取的是**阈值带**而不是整片填充：整片发白看起来像一块贴在海面上的灰补丁
//（第一版用规则正弦积做整片提亮，实拍就是那样）。
//
// ⚠️ 尺度按**真实米**给：分区 λ ≈ 15 km / 5.7 km（视野内必定跨过阈值），
// 扰动 λ ≈ 4.5 km / 1.8 km（只负责把边界打碎）。
// 这个量级才配得上 128 km 的竞技场 —— `ocean_height()` 那套 785 m 的浪
// 在俯瞰时只占几格，读不出「这片海底下有东西」。
//
// ⚠️ **城市图必须关掉它**（`world_builder.gd:_build_city_water()`）：
// 那是人工海湾/运河，底下长礁盘不合理。
uniform float shoal_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 shoal_color : source_color = vec3(0.100, 0.205, 0.190);
// 珊瑚砂刻意偏暖（R ≥ B）：夜战的每通道增益是红 0.30 / 蓝 0.92，
// 中性白会被照成「结冰的湖」，所以这一点暖是必要的。
uniform vec3 foam_color : source_color = vec3(0.520, 0.540, 0.500);

// ---- 场景亮度增益（轮 12：用户"机体不变、场景明暗度更亮一点"，并要求海面一起）----
//
// 由 `world_builder.gd` 灌入；**默认 1.0 = 逐位等价于本轮之前**（`ALBEDO *= 1.0`
// 在浮点上是精确恒等，所以"零回归"可以直接用 PNG 的 md5 验）。
//
// ⚠️ **为什么这里是一个输出乘法，而不是在 world_builder 里逐个乘颜色 uniform**：
// 本文件有一批"代码里从不设、只靠这里的默认值"的颜色（`crest_sss_color` /
// `shoal_color` / `foam_color`），而 `ShaderMaterial.get_shader_parameter()`
// 对**没设过**的参数返回 `null` —— 它**不会**回落到 shader 的默认值。
// 于是"读出来再乘"这条路是死的（第一版就是这么写的，实测拿到 9 条 null、
// 画面纹丝不动、且不报错）；改成在 GDScript 里把默认值抄一份又等于两份真源。
// 一个输出乘法把**全部**水面颜色一起盖住，也没有清单要维护。
//
// ⚠️ 乘的位置在 fragment 的**最后**（所有对 ALBEDO 的写入之后）：提前一步，
// 排在它后面的项（浅滩 / 泡沫）就会漏掉 —— 而画面表现只是"那两块没变亮"。
uniform float scene_gain : hint_range(0.0, 8.0) = 1.0;

// 水深场（值域 0..1，越大越浅）。
//
// ⚠️ **形状必须来自噪声，不能是正弦积。** 第一版用的是三层 `sin×cos`，
// 实测拍出来是一片**圆润、规则、互相啮合**的色块 —— 读起来像"水面上的污渍"，
// 不像礁盘。天然礁盘的第一特征是**边界不规则、有枝杈**，那正是 value noise 的形状。
// （代价是多一层 hash；这里只用在海面，而且只有 3 次采样。）
float _hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// ⚠️ 插值曲线用 **quintic**（`6f⁵−15f⁴+10f³`）而不是原来的 smoothstep（`3f²−2f³`）——
	// 这一行是"海面方块感"的根治点，批 H · 轮 3 实测出来的：
	//
	// 我们用的是 value noise 的**差分**（`h0 - hx`）当坡度。smoothstep 是 C1 连续
	//（一阶导连续）但**二阶导在格边界处突变**，而人眼对"梯度变化率的折点"极其敏感：
	// 于是每个晶格都读得出一个**方块**（单层时尤其明显 —— 实拍里前景是一张棋盘）。
	// quintic 是 C2 连续（二阶导也连续），格边界的折点消失，方块感随之消失。
	//
	// 代价是每片元多 3 次乘法。均价换掉一整片海的"网格感"，这个交易是划算的。
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = _hash21(i);
	float b = _hash21(i + vec2(1.0, 0.0));
	float c = _hash21(i + vec2(0.0, 1.0));
	float d = _hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 水深场（0..1，越大越浅）＝ **大尺度分区 + 噪声扰动**。
//
// ⚠️ 这个结构是实测逼出来的，不是先想好再写的 —— 前两版都失败了：
//   · 第一版：三层 `sin×cos` 直接当水深 ⇒ 形状跑通了（A/B 有效），
//     但**边界规则、块块互相啮合**，截图看像"水面污渍"，不像礁盘；
//   · 第二版：整份换成 fbm ⇒ 形状对了，但**画面里几乎没盖到**
//     （整帧只差 +0.0005）。根因在**视野**：λ 30 km 的噪声在 40 km 的视场里
//     跨不到 2 个晶格 ⇒ `sf` 在整屏上近乎常数，跨不过任何阈值。
//     **离线统计"全球分布"看着很宽，可玩家只看得见其中一格。**
//   ⇒ 正确分工是：**正弦负责「分区」**（周期数在视野内是确定的，必定跨过阈值），
//     **噪声只负责把分区边界打碎**（幅度 ±0.24：够打碎规则的边界，不足以改变分区）。
float _shoal_field(vec2 wp) {
	float s = sin(wp.x * 0.00042 + 0.7) * cos(wp.y * 0.00037 - 1.2);   // λ ≈ 15 km
	float m = sin(wp.x * 0.00110 - 2.1) * cos(wp.y * 0.00095 + 0.4);   // λ ≈ 5.7 km
	float zone = (s * 0.72 + m * 0.28) * 0.5 + 0.5;                    // 0..1
	// 扰动用**两个尺度**：单尺度会在边界上留下一圈可见的"抖动周期"。
	float jitter = (_vnoise(wp * 0.00022) - 0.5) * 0.32
		+ (_vnoise(wp * 0.00055 + vec2(31.7, 17.3)) - 0.5) * 0.16;
	return clamp(zone + jitter, 0.0, 1.0);
}

// ---- 长涌浪几何（1.2.3 批 H · 轮 1）----
//
// `ocean_height()` 全部跑在 fragment —— 它只改**法线**，不改几何。
// 于是海面在**几何上是一块完全平的板**（`PlaneMesh` 原来细分 6×6，每格 61 km），
// 贴海飞的时候看不到"坡"。而真实海面是有长涌浪的：机翼掠过一个浪峰与掠过
// 一个浪谷，地平线在画面里的位置是不同的 —— 这个差就是速度感与高度的来源之一。
//
// ⚠️ **位移的波长必须由网格密度倒推，不能直接搬 `ocean_height()` 的斜率。**
// 几何能表达的最短波长 = **格距的 2 倍**（奈奎斯特）。现在海面是
// `OCEAN_SEG = 448` 段铺满 `OCEAN_SIZE = 368 km` ⇒ 格距 **821 m**
// ⇒ 几何只表达得了 λ ≥ 1642 m。而 `ocean_height()` 的主涌浪是 **λ 785 m**，
// 拿它做位移只会得到**走样**（不到两格一个周期，看起来像抖动而不是浪）。
//
// 所以位移**另起一套更长的波**（3600 m / 1900 m），与 fragment 的解析波
// **刻意不共享**：几何给低频的"大坡"，fragment 给高频的"细纹"，两者叠起来才是海面。
// 共享的话低频坡度会被算两遍（几何一次 + 法线一次），掠射角下会亮得发假。
//
// 幅度 4 m 是**故意保守**的：`FlightBody.CRASH_ALTITUDE = 24 m` 是撞海判定线，
// 浪峰上抬 4 m 不会让"看着还有 20 m 却撞了"出现；再大就会开始改玩法手感。
uniform float wave_amp : hint_range(0.0, 20.0) = 0.0;
uniform float swell_len_a = 3600.0;
// ⚠️ 2026-09-23（批 I · 轮 4 跨图标定）：**1400 → 1900**。
// 旧值 1400 m **低于几何的奈奎斯特下限**：`OCEAN_SEG = 448` 摊在 368 km 的
// 海面网格上 ⇒ 格距 **821 m**、可表达的最短波长 **1642 m**。
// 1400 m 的波在 821 m 的格上只有 **1.7 个采样/周期** ⇒ 逐顶点采样之后不是
// 一条 1400 m 的波，而是**两列波打出来的差拍**（一条 λ ≈ 7 km 的幽灵长波）。
// 改到 1900 m（= 2.3 格）之后落在干净区间；两条涌浪仍分得开（3600 / 1900）。
// 代价是"坡度 ∝ 1/λ"变小，已由 `wave_normal` 8 → 11 补回（11/8 × 1400/1900 ≈ 1.01）。
uniform float swell_len_b = 1900.0;
// ⚠️ **长涌浪在法线上的"视觉增益"**（轮 1 · 实测逼出来的一个数）。
//
// 第一版只做了位移、没动法线，实测结果是 **A/B 全表 `+0.0000`（逐位为零）**：
// 网格确实是 448 段（帧图元数 418 960 = 448²×2，不是没建），位移也确实加上了 ——
// 但**海面是纯色**，而明暗只由法线决定 ⇒ 浪峰和浪谷一样亮 ⇒ 位移等于空转。
//
// 那为什么不干脆"把坡度照实算进法线"就完了？算一下就知道：
//   `_swell` 的坡度 = `wave_amp × 2π / λ` = `4 × 6.28 / 1900` ≈ **0.013**
//   ⇒ 法线偏 **1°**，在这个光照下低于 8 位量化的一格。
// 这是个**结构性矛盾**，不是调参问题：
//   · 几何能表达的 λ ≥ 格距×2 = **1642 m**（`OCEAN_SEG = 448` 定的）；
//   · 幅度又受撞海判定线（`CRASH_ALTITUDE = 24 m`）限制，最多 ~8 m；
//   ⇒ 在这个 λ 上，"真实坡度"永远只有 0.01~0.02，**必然看不见**。
//
// 所以要看到长涌浪，只能承认一件事：**明暗是美术夸张，几何是物理量。**
// 位移保持 4 m（不影响手感与遮挡），法线按 `wave_normal` 倍放大 ——
// 8 倍对应"视觉坡度 ≈ 8.4°"，在掠射角下正是一眼能看出"海面在起伏"的量。
// 两者的分工是：**几何给遮挡与视差，法线给明暗**。真实海面也是短波负责亮、
// 长波负责挡，只是这里把它做成了两个可调的旋钮。
//
// ⚠️ 2026-09-23（批 I · 轮 4）：8 → **11**。`swell_len_b` 从 1400 提到 1900
// 之后坡度按 1/λ 掉了 26%，乘回 11/8 = 1.375 ⇒ 视觉强度与改之前一致（1.01 倍）。
uniform float wave_normal = 11.0;

// ---- 微波（短波）细节（批 H · 轮 3）----
//
// 上面两层（解析波 785 m + 长涌浪 1900/3600 m）管的都是**大尺度**起伏。
// 而"这是水"这个读感其实靠**近处那些细碎的波光** —— 只有几米到几十米的短波
// 才会让掠射角下的海面出现星星点点的反光方向变化。没有它，近处的海面是一块
// **光滑的蓝色塑料布**（太平洋图实拍确认：`--seacam=60` 时画面前景完全是平的）。
//
// ⚠️ **必须按屏幕像素淡出**，而且这里比地表更要紧：海面占满全屏、一直铺到地平线，
// 短波若一直开着，远处每个像素会随机挑一个相位 ⇒ 整片海变成**闪烁的噪点**
//（比"没有细节"难看得多，而且它在动，比静帧噪点更刺眼）。
// 判据与 `terrain.gdshader` 的 `_oct_fade` **同一把尺子**：
// `_vnoise` 的晶格是 1，所以 `ripple_len / mpp` 正是"一个波长占几像素"，
// 低于 2~4 px 就淡到底。
//
// `ripple_len` 是波长（米），`ripple_normal` 是法线增益 ——
// 短波的真实坡度（约 0.07）本来就比长涌浪大，所以增益给 2.2 而不是 8.0。
// 默认 0 = **关**：这样没传参数的调用点（城市运河那层水面）行为一字不变。
uniform float ripple_amount : hint_range(0.0, 1.0) = 0.0;
uniform float ripple_len = 14.0;
uniform float ripple_normal = 2.2;
// 第二层（细）相对 `ripple_len` 的缩放。
//
// ⚠️ 取 **0.37 而不是 0.5**：0.5 会让两层的晶格在半个周期处**重新对齐**，
// 于是"错开晶格"这件事做了等于没做，棋盘格会以更小的格子重新出现。
// 非整数比（0.37、0.41 这类）才能真正把两套晶格错开。
const float RIPPLE_OCT_SCALE = 0.37;

// Environment upgrade: local geometric bandwidth, bounded total height.
uniform bool fft_enabled = false;
uniform sampler2DArray fft_displacements_a : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray fft_displacements_b : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray fft_normals_a : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray fft_normals_b : filter_linear_mipmap, repeat_enable;
uniform float fft_b_weight = 0.0;
// Continuous world-space phase warp prevents visible FFT tile repeats without camera swimming.
vec2 fft_coords(vec2 p, float tile, int cascade) {
	vec2 q = p / 18000.0 + vec2(float(cascade) * 17.3);
	vec2 shift = vec2(_vnoise(q + vec2(11.7, 53.1)), _vnoise(q + vec2(73.2, 19.6))) - vec2(0.5);
	return (p + shift * tile * 0.45) / tile;
}
vec3 fft_displacement(vec2 p, float cell) {
	vec3 d = vec3(0.0);
	for (int i=0; i<3; i++) {
		float wl = i == 0 ? 4096.0 : (i == 1 ? 973.0 : 233.0);
		float lod = log2(max(cell * 256.0 / wl, 1.0));
		d += mix(textureLod(fft_displacements_a, vec3(fft_coords(p, wl, i), float(i * 2)), lod).xyz, textureLod(fft_displacements_b, vec3(fft_coords(p, wl, i), float(i * 2)), lod).xyz, fft_b_weight) * 0.55;
	}
	return d;
}
vec4 fft_surface(vec2 p, float footprint, float aerial) {
	vec4 data = vec4(0.0);
	footprint = max(footprint, aerial * 45.0);
	for (int i=0; i<3; i++) {
		float wl = i == 0 ? 4096.0 : (i == 1 ? 973.0 : 233.0);
		float weight = i == 0 ? mix(1.0, 0.65, aerial) : (i == 1 ? mix(1.0, 0.25, aerial) : 1.0 - aerial);
		if (weight < 0.001) continue;
		float lod = log2(max(footprint * 256.0 / wl, 1.0));
		vec4 a = textureLod(fft_normals_a, vec3(fft_coords(p, wl, i), float(i * 2)), lod);
		vec4 b = textureLod(fft_normals_b, vec3(fft_coords(p, wl, i), float(i * 2)), lod);
		vec4 v = mix(a, b, fft_b_weight);
		data.xy += v.xy * 0.9 * weight;
		data.z += mix(max(a.z - dot(a.xy,a.xy), 0.0), max(b.z - dot(b.xy,b.xy), 0.0), fft_b_weight) * 0.81 * weight * weight;
		data.w = max(data.w, v.w * weight);
	}
	return data;
}
uniform bool adaptive_mesh = false;
uniform float surface_detail : hint_range(0.0, 1.0) = 0.0;
varying float geometry_cell;
float resolved_wave(float wl, float cell) {
	return smoothstep(4.0, 8.0, wl / max(cell, 0.001));
}
// Analytic wave gradients avoid the visible square lattice of value-noise normals.
vec2 sea_gradient(vec2 p, float t, float mpp) {
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float wl = 12.0 * pow(1.53, fi);
		float angle = fi * 2.399963 + 0.27;
		vec2 dir = vec2(cos(angle), sin(angle));
		float k = 6.283185 / wl;
		float phase = dot(p, dir) * k - t * sqrt(9.81 * k) + fi * 1.713;
		float keep = smoothstep(2.0, 5.0, wl / max(mpp, 0.001));
		slope -= dir * cos(phase) * (0.032 + fi * 0.002) * keep;
	}
	return slope;
}
float wind_wave(vec2 p, float t) {
	return sin(dot(p, vec2(0.940, 0.342)) * (6.283185 / 128.0) - t * 0.693) * 0.60
		+ sin(dot(p, vec2(0.766, 0.643)) * (6.283185 / 72.0) - t * 0.925) * 0.25
		+ sin(dot(p, vec2(-0.259, 0.966)) * (6.283185 / 240.0) - t * 0.507) * 0.15;
}

varying vec3 world_pos;

// 两条不同方向的窄带长波。方向刻意不对称（0.82/0.57 与 -0.35/0.94）——
// 不然两组波会在同一轴上拍频，海面会变成一张规则的搓衣板。
float _swell(vec2 wp, float t) {
	float a = sin(dot(wp, vec2(0.82, 0.57)) * (6.28318 / swell_len_a) + t * 0.42);
	float b = sin(dot(wp, vec2(-0.35, 0.94)) * (6.28318 / swell_len_b) - t * 0.63);
	return a * 0.68 + b * 0.32;
}

// 长涌浪的**水平梯度**（∂h/∂x, ∂h/∂z），量纲是米/米。
//
// ⚠️ 差分步长必须**按这一层的波长给**，不能复用上面的 `epsilon = 0.7` ——
// 那是给 5.7 m 的细波用的，拿它去差分 λ 1900 m 的波，`h0 - hx` 会趋近于 0，
// 得到的坡度恒为 0。这正是 `terrain.gdshader` 的 `_detail_slope` 栽过的同一个坑
//（粗层在一个过小的步长下"在法线里等于不存在"），这里第二遍踩到它。
// 步长取 λ/10（1900/10 = 190）：够大以至于差分有意义，又够小以至于不失真。
//
// ⚠️ 2026-09-23（批 I · 轮 4）：140 → **190**，跟着 `swell_len_b` 一起改。
// 这两个数**必须一起动**：只改波长不改步长 ⇒ 步长相对新波长变小 ⇒ 坡度被差分削掉。
vec2 _swell_grad(vec2 wp, float t) {
	float e = 190.0;
	float h0 = _swell(wp, t);
	float hx = _swell(wp + vec2(e, 0.0), t);
	float hz = _swell(wp + vec2(0.0, e), t);
	return vec2(h0 - hx, h0 - hz) / e;
}

float ocean_height(vec2 wp, float t) {
	float h = 0.0;
	h += sin(wp.x * 0.0080 + t * 1.15) * cos(wp.y * 0.0071 - t * 0.95) * 1.000;
	h += sin(wp.x * 0.0210 - t * 0.80) * cos(wp.y * 0.0183 + t * 1.55) * 0.420;
	h += sin(wp.x * 0.0550 + t * 2.10) * cos(wp.y * 0.0470 - t * 1.85) * 0.160;
	h += sin(wp.x * 0.1600 - t * 3.10) * cos(wp.y * 0.1400 + t * 2.70) * 0.075;
	h += sin(wp.x * 0.4200 + t * 4.60) * cos(wp.y * 0.3800 - t * 3.90) * 0.032;
	h += sin(wp.x * 1.1000 - t * 6.30) * cos(wp.y * 1.0300 + t * 5.40) * 0.014;
	return h;
}

void vertex() {
	geometry_cell = adaptive_mesh ? UV2.x : 1.0;
	if (adaptive_mesh) {
		VERTEX.xz += floor(CAMERA_POSITION_WORLD.xz / 4.0) * 4.0;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 位移必须在**算完 world_pos 之后**加，而且两份都要加：
	// `world_pos` 是给 fragment 的 varying，`VERTEX` 才是真正的几何位置。
	// 只改其中一个会出现"看着有浪、但云影/反射用的是平地坐标"的分裂。
	//
	// `VERTEX.y` 直接就是世界 y —— 海面的模型矩阵只有平移，没有旋转/缩放。
	//
	// ⚠️ **城市图必须把它关掉**（见 `world_builder.gd:_build_city_water()`）：
	// 那张图复用同一份材质，但网格换成了 460 km、细分 2×2 ⇒ 格距 230 km，
	// 位移会把四个角各抬一段 ⇒ 整片水面**倾斜**成一块斜板。
	if (wave_amp > 0.0) {
		float d = _swell(world_pos.xz, wave_time) * wave_amp;
		if (adaptive_mesh) {
			// 2.8 m swell + <=1.2 m wind waves: envelope never exceeds 4 m.
			d = _swell(world_pos.xz, wave_time) * wave_amp * 0.70 * resolved_wave(swell_len_b, geometry_cell);
			d += wind_wave(world_pos.xz, wave_time) * wave_amp * 0.30 * resolved_wave(72.0, geometry_cell);
			if (fft_enabled) {
				vec3 fd = fft_displacement(world_pos.xz, geometry_cell);
				d = _swell(world_pos.xz, wave_time) * wave_amp * 0.70 * resolved_wave(swell_len_b, geometry_cell);
				d += fd.y / sqrt(1.0 + fd.y * fd.y / 1.44);
			}

		}
		VERTEX.y += d;
		world_pos.y += d;
	}
}

void fragment() {
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	float fade = 1.0 / (1.0 + dist * detail_fade);
	float t = wave_time;
	float h0 = ocean_height(world_pos.xz, t);
	float hx = ocean_height(world_pos.xz + vec2(epsilon, 0.0), t);
	float hz = ocean_height(world_pos.xz + vec2(0.0, epsilon), t);

	float k = normal_strength * fade;
	vec3 n = normalize(vec3(-(hx - h0) * k, 1.0, -(hz - h0) * k));

	// ---- 长涌浪的明暗（轮 1）----
	// 高度场 `y = h(x,z)` 的法线是 `(-∂h/∂x, 1, -∂h/∂z)`，而 `_swell_grad` 返回的
	// 是 `(∂h/∂x, ∂h/∂z)`（带负号：`h0 - hx ≈ -∂h/∂x · e`），所以法线偏移取同号。
	// 增益的理由见 uniform 那一段（真实坡度只有 1°，必然不可见）。
	if (wave_amp > 0.0) {
		vec2 g = _swell_grad(world_pos.xz, t) * wave_amp * wave_normal;
		n = normalize(n + vec3(g.x, 0.0, g.y));
	}

	// ---- 微波细节（批 H · 轮 3）----
	// 只改**法线**、不改高度：短波的几何起伏只有几厘米（在屏幕上不可见），
	// 但它对**明暗**的影响很大 —— 位移交给大波，明暗交给小波，这两件事要分开算。
	//（海面是纯色 + 掠射角 ⇒ 只做位移不做法线时 A/B 会**逐位为零**，批 H 轮 1 实测过。）
	if (ripple_amount > 0.0) {
		float mpp = max(length(dFdx(world_pos.xz)), length(dFdy(world_pos.xz)));
		// 淡出判据按**最细那一层**的波长走：粗层还在、细层已经碎了的时候，
		// 屏幕上只剩"缓慢的涌"而不是噪点 —— 那正是该保留的状态。
		float wl_min = ripple_len * RIPPLE_OCT_SCALE;
		float keep = smoothstep(2.0, 4.0, wl_min / max(mpp, 0.0001));
		if (keep > 0.0) {
			// ---- ⚠️ **必须是两层**：单层 value noise 的晶格是"一格一个随机值" ----
			//
			// 实拍（`--seacam=60`）：单层版的前景是一张**棋盘** —— 14 m 的晶格
			// 在 60 m 机位上放大成约 100 px 的方块，方格感比"没有细节"更假。
			// 两层不同波长 + 不同相位把晶格错开，棋盘的边就没了。
			//
			// 差分步长取**半格**：与 `terrain._oct_slope` 同一个口径 ——
			// 步长比波长小得多时差分趋近 0，"这层在法线里等于不存在"。
			vec2 qa = world_pos.xz / ripple_len;
			vec2 qb = world_pos.xz / (ripple_len * RIPPLE_OCT_SCALE) + vec2(23.7, 61.3);
			float a0 = _vnoise(qa);
			float ax = _vnoise(qa + vec2(0.5, 0.0));
			float az = _vnoise(qa + vec2(0.0, 0.5));
			float b0 = _vnoise(qb);
			float bx = _vnoise(qb + vec2(0.5, 0.0));
			float bz = _vnoise(qb + vec2(0.0, 0.5));
			// 粗层权重 1.35 > 细层 1.0：粗层给"波"，细层只负责把粗层的方格揉碎。
			vec2 gr = vec2(a0 - ax, a0 - az) * 1.35 + vec2(b0 - bx, b0 - bz);
			n = normalize(n + vec3(gr.x, 0.0, gr.y) * ripple_amount * keep * ripple_normal);
		}
	}

	float aerial_detail = surface_detail * smoothstep(900.0, 3500.0, max(CAMERA_POSITION_WORLD.y, 0.0));
	float water_detail = surface_detail * (1.0 - smoothstep(3000.0, 12000.0, dist));
	water_detail *= 1.0 - aerial_detail * 0.75;
	float mpp_water = max(length(dFdx(world_pos.xz)), length(dFdy(world_pos.xz)));
	vec4 fft_sample = vec4(0.0);
	if (fft_enabled) fft_sample = fft_surface(world_pos.xz, mpp_water, aerial_detail);
	float wind_keep = smoothstep(2.0, 5.0, 72.0 / max(mpp_water, 0.001));
	if (surface_detail > 0.0) {
		vec2 spectrum = sea_gradient(world_pos.xz, t, mpp_water);
		if (fft_enabled) spectrum = -fft_sample.xy / 2.2;

		vec2 swell = _swell_grad(world_pos.xz, t) * wave_amp * 1.5;
		vec3 physical_n = normalize(vec3(spectrum.x * 2.2 + swell.x, 1.0, spectrum.y * 2.2 + swell.y));
		n = normalize(mix(n, physical_n, surface_detail));
	}
	float wh = wind_wave(world_pos.xz, t);
	vec2 wg = vec2(wh - wind_wave(world_pos.xz + vec2(2.0, 0.0), t),
		wh - wind_wave(world_pos.xz + vec2(0.0, 2.0), t)) / 2.0;
	n = normalize(n + vec3(wg.x, 0.0, wg.y) * 2.4 * water_detail * wind_keep * (fft_enabled ? 0.0 : 1.0));
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float facing = clamp(dot(n, view_dir), 0.0, 1.0);
	float fres = pow(1.0 - facing, 4.0);
	float horizon = smoothstep(horizon_start, horizon_end, dist);

	// 波峰提亮，让海面有起伏而不是一整块色
	float crest = smoothstep(0.45, 1.30, h0);
	if (fft_enabled) crest = smoothstep(0.35, 1.40, fft_displacement(world_pos.xz, max(mpp_water * 2.0, 2.0)).y);
	crest *= 1.0 - aerial_detail * 0.88;
	vec3 base = mix(deep_color, crest_color, crest * 0.75 * fade);

	// ---- 月光镜面带 ----
	// 半程向量（视线 + 月亮方向）与水面法线越接近，越像"正对着月亮的那道反光"。
	// `(1.0 - horizon)` 让它随距离淡出到地平色，否则 26 km 外会出现一条硬边亮带。
	if (glitter_strength > 0.0) {
		vec3 half_v = normalize(view_dir + normalize(moon_dir));
		float glitter = pow(clamp(dot(n, half_v), 0.0, 1.0), mix(glitter_sharp, 48.0, surface_detail));
		base += moon_color * glitter * glitter_strength * (1.0 - horizon);
	}

	// ---- 浪尖次表面（1.2.3 批 E）----
	// `pow(back, 2)` 把权重收窄：只有真正"朝着月亮看"的那一带才透光，
	// 不然整片海会整体提亮一档（那就是在动 1.2 的亮度基线了）。
	//
	// ⚠️ `back` 取的是**水平方位上的反向**，不是三维夹角 —— 为什么见 uniform 那一段
	// （三维写法在本工程固定的 58° 月亮下实测权重只剩 0.009，等于永久关闭）。
	// 退化保护：相机**垂直向下**看时 `view_dir` 的水平分量趋零 ⇒ 退化成 0（不发光），
	// 这也符合直觉——垂直俯瞰水面时没有"逆光"可言。
	if (crest_sss > 0.0) {
		vec3 md = normalize(moon_dir);
		vec3 vf = vec3(view_dir.x, 0.0, view_dir.z);
		vec3 mf = vec3(md.x, 0.0, md.z);
		float back = 0.0;
		if (length(vf) > 0.0001 && length(mf) > 0.0001) {
			back = clamp(-dot(normalize(vf), normalize(mf)), 0.0, 1.0);
		}
		back *= back;
		base += crest_sss_color * crest * back * crest_sss * fade * (1.0 - horizon);
	}

	// ---- 云影 ----
	if (cloud_shade_strength > 0.0) {
		vec2 shade_uv = (world_pos.xz - cloud_field_origin) / cloud_field_span;
		base *= 1.0 - texture(cloud_shade_tex, shade_uv).r * cloud_shade_strength;
	}

	ALBEDO = mix(base, sky_color, fres * 0.70);
	ALBEDO = mix(ALBEDO, horizon_color, horizon);

	// ---- 水下地形：浅滩与礁盘（轮 1）----
	// 分**两层**，斜坡与顶面用不同的颜色与阈值：
	//   · `shallow`（中等深度，礁盘的斜坡）→ `shoal_color`（青绿，透出浅水）；
	//   · `top`（最浅，珊瑚砂已接近露出水面）→ `foam_color`（几乎白）。
	// 只做一层够不着这个效果：仅提亮整片会读成"水面污渍"（第一版实测就是那样），
	// 而"青绿的环 + 白的心"才是礁盘在航拍里的样子。
	//
	// ⚠️⚠️ **必须叠在 `sky_color` / `horizon_color` 两次混合之后**，不能叠在 `base` 上。
	// 第一版叠在 `base`（和波峰、镜面带同一层），实测几乎看不见（整帧只差 −0.0008）：
	// 高空俯瞰海面是**掠射角** ⇒ `facing` 小 ⇒ `fres ≈ 1` ⇒
	// `mix(base, sky_color, 0.70)` 把 base 冲淡到只剩三成，礁盘那点提亮跟着被冲掉。
	// 礁盘是**水底**的东西，不该被水面反射按比例稀释 —— 所以它排在最后。
	//
	// 这一项**不吃 `fade`**（不像风浪细节那样随距离压掉）：浅滩是"地形"，
	// 远处反而因为占的像素多而更该看得见。淡出只交给 `(1 - horizon)`。
	if (shoal_amount > 0.0) {
		// ⚠️ 阈值是照**这套场在视场内的实测分位数**钉的（离线 4 万点，±20 km 与
		// ±200 km 两档结果几乎一致：mean 0.50 · P50 0.50 · P75 0.645 ·
		// P90 0.77 · P95 0.84）。第一版把顶面定在 `smoothstep(0.74, 0.92)` ——
		// 那只覆盖 P95 以上，实测**整帧只差 +0.0005，等于没做**。
		float sf = _shoal_field(world_pos.xz);
		float amt = shoal_amount * (1.0 - horizon) * (1.0 - aerial_detail * 0.80);
		// 浅海分区：P48 起、P85 全转 ⇒ 约 50% 的海面被转色（含过渡带）
		float shallow = smoothstep(0.48, 0.72, sf);
		// 礁盘顶面：P75 起、P95 到最亮 ⇒ 约 20% 过渡带 + 约 5% 全强
		float top = smoothstep(0.70, 0.88, sf);
		ALBEDO = mix(ALBEDO, shoal_color, shallow * 0.85 * amt);
		// 顶面用**加法**而不是 mix：夜里「最浅的那一块」是发亮的珊瑚砂底，
		// 在近黑的深海底色上，只有加法才堆得出那一点亮度。
		ALBEDO += foam_color * top * 0.55 * amt;
	}
	// ---- 场景亮度增益（轮 12）----
	// 必须压在**所有**对 ALBEDO 的写入之后（上面那一行泡沫是最后一处）。
	// 详见 uniform 处那段：海面走输出乘法而不是逐个乘颜色 uniform。
	// Sparse breaking crests, filtered by footprint. No fake shoreline in open sea.
	float foam = smoothstep(0.73, 0.97, wh) * smoothstep(0.40, 0.70,
		_vnoise(world_pos.xz / 31.0 + vec2(t * 0.13, -t * 0.06)));
	foam *= water_detail * wind_keep * 0.22 * step(0.001, wave_amp);
	if (fft_enabled) foam = fft_sample.w * 0.35 * (1.0 - aerial_detail);

	ALBEDO = mix(ALBEDO, foam_color * 0.65, foam);
	ALBEDO *= scene_gain;
	ROUGHNESS = mix(mix(roughness_sea, 0.18, surface_detail) + water_detail * 0.035 + foam * 0.5, 1.0, horizon);
	if (fft_enabled) ROUGHNESS = clamp(sqrt(ROUGHNESS * ROUGHNESS + fft_sample.z * 0.2), 0.08, 1.0);

	// Stable sky reflection fallback. Reflected radiance is not diffuse albedo,
	// so it remains readable when the night sky's ambient cubemap is very weak.
	vec3 reflected = reflect(-view_dir, n);
	vec3 reflected_sky = mix(horizon_color, sky_color, pow(clamp(reflected.y, 0.0, 1.0), 0.55));
	float sky_fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	float shade_reflect = 1.0;
	if (cloud_shade_strength > 0.0) {
		vec2 cuv = (world_pos.xz - cloud_field_origin) / cloud_field_span;
		shade_reflect -= texture(cloud_shade_tex, cuv).r * cloud_shade_strength * 0.35;
	}
	EMISSION = reflected_sky * sky_fresnel * surface_detail * scene_gain * 0.80 * shade_reflect;
	// Low-level water scattering keeps the sea readable away from the moon's specular band.
	vec3 water_scatter = mix(deep_color, crest_color, clamp(wh * 0.5 + 0.5, 0.0, 1.0));
	EMISSION += water_scatter * surface_detail * scene_gain * 0.10 * (1.0 - sky_fresnel) * shade_reflect;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
