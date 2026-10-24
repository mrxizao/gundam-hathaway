shader_type spatial;
// `diffuse_lambert` 是**对齐用**的一行：Godot 空间 shader 的默认漫反射模型是
// `diffuse_burley`，而 `BaseMaterial3D` 的默认是 `diffuse_lambert`。
// 换材质时把这条对齐，免得"同 albedo 渲出两种亮度"。
//
// ⚠️ **实测结论（诚实记录）**：加不加这一行，艾尔斯岩同机位的沙地均值
// **一模一样**（R=87.4 G=67.1 B=65.8，逐字节相同），所以它在本工程里
// 没有可观测影响 —— 留着是为了"语义上就该一致"，不是因为它修好了什么。
//
// `cull_disabled` 见下面的说明。
render_mode cull_disabled, specular_schlick_ggx, diffuse_lambert;

// 地表（沙丘 / 靶场地坪 / 岛屿 / 巨岩 / 城市地面）共用的一份材质。
//
// ## 为什么把 StandardMaterial3D 换成 shader
//
// 只有一个原因：**云影**。
//
// `StandardMaterial3D` 只能读它自己那几个属性，没法按世界坐标采样一张自定义贴图；
// 而"云飘过时地面暗一块"天生就是一个按世界 XZ 的查表。
// 云影覆盖图由 `WorldBuilder._bake_cloud_shade()` 烘出来（云的位置本来就是代码算的），
// 同一张图**同时**给 GPU（这里）与 CPU（自机 / 敌机的 albedo）用 ——
// 于是"机体上的云影"和"地上的云影"必然重合，这一点用两套独立算法做不到。
//
// 其余行为刻意与原来那份 StandardMaterial3D 对齐（顶点色当 albedo、粗糙度、
// 镜面反射），所以换过来画面不该有可见变化 —— 除了多了云影。
//
// ## 为什么 cull_disabled
//
// 巨岩（`_build_rock_ridge`）是 `SurfaceTool` 建的**开放曲面**，开背面剔除就会
// "从上方看进山体内部"（1.2 用户实测过）。海面 shader 用的也是 cull_disabled，
// 所以这条不是新特例。地表网格只有一万多个三角形，代价可以忽略。
//
// ## 1.2.3 批 E：地表细节（`detail_strength` / `detail_grain`）
//
// **要解决的问题**：地表网格的细分是**按公里**的 —— `TERRAIN_DETAIL_SIZE` = 101.2 km
// 分 84 段 ⇒ **每格约 1205 m**。所以近看地表是一整块**纯顶点色**：没有沙粒、
// 没有岩面、没有混凝土板缝。1.2 时代没有人低空贴着地看，1.3 的剧情模式要贴地飞。
//
// **为什么是"程序化法线扰动"而不是贴图**：工程规矩是**一张美术资源都不带**
//（`_city_*` 的注释里写着），而且这些网格**没有切线**（`ARRAY_TANGENT` 缺失），
// 加法线贴图连切线空间都没有。程序化噪声零素材、零切线依赖、**可复算**
//（同一个世界坐标永远同一个值，所以 A/B 对比成立）。
//
// **做法**：按世界 XZ 取**五层** value noise（波长 1280 / 320 / 80 / 20 / 5 m），
// **每层用自己的差分步长**求坡度再按权重相加，然后把坡度加到世界法线上。
// 同一份高度场顺便当 albedo 的颗粒（`detail_grain`）—— **不多花采样**。
//
// ⚠️ **"逐层自己的步长"不是优化，是正确性**：见 `_detail_slope` 的血泪注释 ——
// 五个波长共用一个步长时，粗层（沙丘）在法线里的贡献会被差分稀释成 0，
// 于是"有高度"却"不产生明暗"，画面依旧是一片平色。
//
// ⚠️ **五层不是"更精细"，是"跨距离可读"**：波长单一的那版（1.5~4.5 m）在
// 3.2 km 的相机高度上只有 0.05~0.2 px，**数学上必然隐形**；
// 而 1280 m 的沙丘在 20 km 外还有 46 px。两者一起才既能贴地看沙粒、又能高空看沙丘。
// 每层按"在屏幕上占几个像素"自动启用/淡出（`_oct_fade`），
// 所以这**同时**是摩尔纹的解法：细层不是被调小，而是在它该消失的距离上消失。
//
// ⚠️ **坡度方向必须与高度场一致**：高度场 `y = h(x, z)` 的法线是
// `(-∂h/∂x, 1, -∂h/∂z)`，而 `h0 - hx ≈ -∂h/∂x · δ`，所以切向基要取
// **+X / +Z**（下面 `cross(n, Z)` 得到 +X，`cross(t, n)` 得到 +Z）——
// 取反了光照会"凸的看起来像凹的"，这个错很难靠肉眼发现，只能靠推导。
//
// ⚠️ **背面（`FRONT_FACING = false`）不扰动**：地表网格是 `cull_disabled` 的开放
// 曲面（巨岩从上往下看会看到内壁）。背面法线由引擎翻转，而这里的切向基是**顶点阶段
// 按正面法线算的**，翻转之后两边对不上 ⇒ 会出现"光照反向"。背面直接跳过，
// 代价是"从上方看巨岩内壁时没有颗粒"，那是几乎看不到的一格。

uniform float surface_detail : hint_range(0.0, 1.0) = 0.0;
uniform float hardscape : hint_range(0.0, 1.0) = 0.0;
varying vec3 terrain_normal_world;

varying vec3 world_pos;
// ⚠️ 这里**曾经**还有一个 `varying float view_dist`（相机到片元的欧氏距离），
// 用来算"每米占几像素"。改成屏幕空间导数（`_ground_mpp`）之后它就没有用户了 ——
// 已删除，不留没人用的插值（那是一个 varying 的带宽换零收益）。
// 法线扰动的**视图空间**切向基，在顶点阶段算好。
//
// ⚠️ 为什么不在 fragment 里现算：fragment 里的 `NORMAL` 是**视图空间**的，
// 要把世界空间的坡度变换过去就得用 `VIEW_MATRIX` / `INV_VIEW_MATRIX`
//（它们在 fragment 阶段的可用性随管线/版本有差别，是个不必要的未知数）。
// 顶点阶段这两条一定可用，而且**切向基对整块平面是常量**（地表网格的世界尺度是 1），
// 插值过去没有任何精度损失 —— 更短的路径、更少的未知。
varying vec3 nrm_t_view;
varying vec3 nrm_b_view;

// 顶上那块远景地坪是 PlaneMesh，**没有顶点色**，所以默认色要用 uniform 给。
//
// ⚠️ **刻意不加 `: source_color`。** 加了的话 Godot 会把传进来的 Color 当 sRGB
// 做一次到线性的转换，而 `BaseMaterial3D.albedo_color` 是**直接当线性值**用的 ——
// 同一个颜色在两条路径上会得到两种 albedo。
// （顶点色的那几块地表不受影响：它们的 tint 是白色，白在两种口径下都是白。）
uniform vec4 albedo_tint = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_vertex_color = true;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;

// ---- 地表细节（批 E）----
// `detail_strength` / `detail_grain` 默认 **0**：**默认值就是"看不出区别"**，
// 谁想要细节谁显式传（`_terrain_material()` 的第 5/6 个参数）。
// 这样 A/B 可以把这一项单独拧掉，且任何"忘了传"的老调用点行为一字不变。
uniform float detail_strength : hint_range(0.0, 3.0) = 0.0;
uniform float detail_grain : hint_range(0.0, 1.0) = 0.0;
// 细节的**最粗那一层波长（米）**。其余四层按 ÷4 递推（1280 → 320 → 80 → 20 → 5）。
//
// ---- ⚠️ 2026-09-23（批 E · **实拍推翻第一版**）：这个 uniform 的语义换过一次 ----
//
// 第一版叫 `detail_scale`，是"1/米的频率倍率"，值域 0.22~0.65 ⇒ 主波长 **1.5~4.5 m**。
// 单测、像素 A/B 全都过（`--detail=0` 确实让画面有差），但**实拍四张图**
// （`--shot=1 --gain=3`）看到的还是一整片没有任何纹理的平色地面。
// 根因是个纯算术问题，量一下立刻清楚：本工程 1600×900、竖直 fov 62°
//   ⇒ 距离 d 处每米占 `748.9 / d` 像素。
//   · 出生点机位：相机离地 **3.2 km**、看的地面在 **5~20 km** 外
//     ⇒ 1.5 m 的波长 = **0.05~0.2 px**。数学上必然隐形，只剩闪烁噪点。
//   · 而玩家是**贴着地飞**的（1.3 剧情模式）—— 100 m 高度时 1.5 m = 11 px，够用。
//
// ⇒ 结论：**"有细节"和"看得到细节"是两件事，而只有后者算数。**
// 单一波长不可能同时服务"贴地飞"和"3 km 高空看 20 km 外的沙丘"，
// 所以改成**五层倍频 + 按屏幕像素数逐层剔除**（见 `_oct_fade`）：
// 远处只留粗层（沙丘），近处五层全开（沙粒）。**这同时解决了摩尔纹**——
// 细层不是"调小"而是"在它该消失的距离上消失"。
//
// 沙丘粗（1280）、岛屿岩面居中（900）、靶场地坪细（250）、
// 城市沥青最细（160）。
uniform float detail_wavelength = 1280.0;

// ---- 材质分层（1.2.3 批 H · 轮 2）----
//
// 上面那套五层倍频给出的是**同一种材质**在五个尺度上的样子 —— 沙丘、混凝土、
// 岩面，三者的"细节"都是同一个**各向同性**的噪声。于是近距离看，这几种地貌
// 在**质感上是同一种料子**，只是放大缩小了不同倍。
//
// 真实地表靠什么分辨？靠**各向异性**：风蚀岩面有层理（沿一个方向拉长）、
// 沙丘有顺风向的波纹、混凝土有浇筑缝与抹面方向。它们的共同点是
// 「纹理在某个方向上被拉长」，而这份 shader 原来是完全各向同性的。
//
// 所以这一轮加一个**低频掩码**（λ ≈ 4.5 km）把地表分成两半：
//   · 掩码 ≈ 0：各向同性（细砂 / 骨料）
//   · 掩码 ≈ 1：沿 `mat_angle` 拉长 `mat_stretch` 倍（层理 / 纹路）
// 掩码自己也是噪声 ⇒ 同一种地貌上会出现「砂一片、岩一片」的自然分布，
// 而不是整张图一个样子。四张图各给一套（方向与拉伸都不同）。
//
// ⚠️ 拉长坐标等于**在那个方向上放大波长**，而 `_oct_fade` 仍按 `wl` 判断
//「这一层在屏幕上占几个像素」⇒ 层理方向上会稍微多保留一点比奈奎斯特更细的层。
// 这是刻意接受的（层理方向本来就不易看出摩尔纹），记在这里以免以后被当成 bug。
uniform float mat_blend : hint_range(0.0, 1.0) = 0.0;
uniform float mat_stretch : hint_range(1.0, 8.0) = 3.0;
uniform float mat_mask_scale = 0.00022;
// 拉伸方向（弧度）。存的是弧度而不是角度：调用点给 0.42 这种数就是为了贴风向，
// 换算成度数反而多一次心算。
uniform float mat_angle = 0.0;

// ---- 稀疏植被覆盖（1.2.3 批 I · 轮 5）----
//
// 用户对艾尔斯岩的参照要求："地上还是要有 **7% 左右不均匀**的植被覆盖"。
// 这一条与前面所有层都不同：前面改的是"同一种料子的长相"，这一条改的是
// **"这块地上长不长东西"** —— 它是一层**覆盖**（coverage），不是一层纹理。
//
// ## ⚠️ 覆盖率不是"切一条尾部"能给的（前两版都栽在这里）
//
// 第一、二版都是「固定阈值 + 切尾部」：`cov = smoothstep(cut, cut+soft, f)`。
// 这条构造有**结构性**缺陷：覆盖率是阈值处的**尾部质量**，而噪声在尾部密度极小
// ⇒ 阈值动一点、或 `f` 的局部均值被粗层推动一点，覆盖率就成倍变化。
// 实拍实测（离线复算同样的构造）：
//   · 第一版（band λ1.9 km 权重 0.44）：单帧覆盖率 **0% ~ 40%**，中位 0.7%
//     —— 400 m 机位实拍只量到 **1.76%**，而"全局平均"确实是 7%。
//     **全局平均 7% 完全掩盖了"单帧要么 0 要么 40%"**，而玩家看的是单帧。
//   · 把 band 权重压到 0.08 也只有 P10 1.9% / max 33% —— 因为尾部对偏移
//     是**指数敏感**的，改权重治不了这个病。
//
// ## ⚠️⚠️ 2026-09-24（批 K · 轮 1③）：**下面那两个阈值已经被彻底弃用**
//
// 用户第二次反馈艾尔斯岩："绿洲覆盖**过于难看随机**了……要有**树木**，
// 其次是**有些是随机分布、但是高空也能看到的小团**，也有些是**连在一起的小绿洲**。"
//
// 下面这套"分位数反解阈值"的做法在**覆盖率**这个指标上是最好的（把波动从
// 0~40% 压到 3.6~10.4%），但它在**分布形状**上是不合格的，而且是结构性的：
// 它的场是**一个全局阈值 + 慢调制**，统计上**各向同性** ⇒
// 它产生不了"团"，更产生不了"连在一起的团"。用户要的三件事（树 / 小团 / 串）
// 它一件都给不了，而且它**没有任何几何** —— 整层植被是一张色块，一棵树也没有。
//
// ⇒ 现在覆盖率由 `WorldBuilder._desert_oasis_sites()` 撒出来的**团/串**决定，
//   烘焙成掩码纹理喂进来（`veg_mask_tex`）。**树长在哪里、地上绿在哪里，
//   是同一份数据** —— 这是这一轮唯一重要的架构决定。
//   分布的形状由参数在 `world_builder.gd` 那侧控制，本 shader 只负责
//   把掩码变成"长出来的东西"（软边 + 细噪声打碎 + 法线扰动）。
//
// 下面那一整段历史**保留不删**：它记的是"覆盖率为什么不能用切尾部来做"，
// 那条结论与现在的做法无关、但依然正确，将来做别的覆盖层会再用上。
//
// ## 旧构造（已弃用，仅存档）：**把阈值反过来当"设值"用**
//
//   `target = mix(4%, 10%, band)`                  ← 这一帧要多少覆盖率
//   `thr    = mix(Q(1-10%), Q(1-4%), band)`        ← 把 target 反解成阈值
//   `cov    = smoothstep(thr, thr + SOFT, patch)`
//
// `Q` 是**该噪声自己的分位数函数**（离线测的，见 `_veg_calib.py`）。
// 于是"这一帧的覆盖率"由一个**线性内插**决定，不再经过指数尾部 ⇒
// 离线复算的单帧分布：**min 3.6% / 中位 7.0% / max 10.4%**（200 帧，855×481 m 视场）。
//
// ## ⚠️ 必须减掉 `SOFT/2`（这条对任何 `smoothstep` 阈值构造都成立，仍然有用）
// `smoothstep(thr, thr+SOFT, x)` 的 **0.5 等值线**落在 `thr + SOFT/2` 上，
// 不在 `thr` 上。不减的话目标 4%~10% 会实量成 2.5%~8.3%（中位 5.28%）——
// 这一步漏了就是"整层偏淡"，而它看起来又完全像是"阈值挑得不对"。
uniform float veg_amount : hint_range(0.0, 1.0) = 0.0;
// ---- 绿洲掩码（批 K · 轮 1③）----
//
// `hint_default_black`：没人给它贴图时读到 **0 = 这地方不长东西**。
// ⚠️ 反过来（默认白）会让**四张图的地面**在初始化阶段先全长一遍草，
// 看起来像加载出了错 —— 与 `cloud_shade_tex` 同一个理由，同一个修法。
//
// ⚠️ `repeat_disable`：掩码只覆盖 **±26 km**（`DESERT_OASIS_SPAN = 52000`），
// 出界时希望读到**边缘值**（那里是 0）而不是绕回来重复一遍。
uniform sampler2D veg_mask_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec2 veg_mask_origin = vec2(0.0);
// ⚠️ 默认值**必须与 `DESERT_OASIS_SPAN` 逐字一致**（52000）：它只是个兜底，
// 工程里由 `_terrain_material()` 显式灌入。写着一个过时的 60000 是**隐患** ——
// 一旦哪次漏灌，图不会被画成"没植被"，而会被画成"植被整体缩小 1.15 倍、
// 位置偏掉"，那种错看起来像分布参数错了，查起来极慢。
uniform float veg_mask_span = 52000.0;
// 掩码值 → 覆盖率的**线性重映射**：`cov = mask * VEG_MASK_GAIN - VEG_MASK_BIAS`。
//
// ⚠️ 两个数不是审美，是**口径差**：掩码存的是"几何上的存在度"（核心 1.0、
// 边缘 0），而 `mix(base, VEG_COLOR, cov * VEG_MIX)` 里的 `cov` 是
// "这一片有多少草"。掩码 0.35 的地方已经该看得见草了，所以要把中低段抬起来。
//
// ⚠️ 用**仿射**（乘加）而不是 `smoothstep`：仿射是**逐点**的，不会像
// `smoothstep` 那样在掩码内部造出第三条等值线（那会在团里出现一圈
// "更绿一点的环" —— 看起来像同心圆伪影，很容易被误判成三角形走样）。
//
// ⚠️⚠️ **BIAS 同时是一个"可见半径"，这一点轮 1 漏了，代价是"串断成珠子"**：
// `cov > 0` 要求 `mask > BIAS / GAIN`，而掩码沿半径是 `f^1.35`（`f = 1 − d/r`）
// ⇒ 反解出**可见半径 = r × [1 − (BIAS/GAIN)^(1/1.35)]**：
//   · 轮 1（GAIN 1.30 / BIAS 0.16）⇒ 0.788 r —— 半径 220 m 的团，
//     地上只剩 **173 m**，两道半径收缩一乘，"数据上相切"的两片就出现了缝。
//   · 现在（1.18 / 0.06）⇒ **0.890 r**，且 GAIN 从 1.30 降到 1.18
//     把"中段提前起色"的力度收了一点 —— 那一点力度本来是为了让
//     **单团的边缘**柔和，有了 14 m 细噪声打碎之后不需要了。
// ⚠️ 改这两个数之前**先算上面那个式子**：它直接决定"相邻两片会不会连上"。
const float VEG_MASK_GAIN = 1.18;
const float VEG_MASK_BIAS = 0.06;
// 边缘打碎的**幅度**（作用在掩码上的细噪声的半幅）与它开始起作用的掩码值。
// 判据：团心必须**实**（那里掩码 ≈1，几乎不该被扰动），团缘必须**碎**。
// 所以权重按 `(EDGE_AT - mask)` 线性给 ⇒ 掩码越高扰动越小，自己就收敛了。
const float VEG_EDGE_AMOUNT = 0.34;
const float VEG_EDGE_AT = 0.62;
// 干草丛的反照率（月色下的三齿稃草）。
//
// ⚠️ 这里被实拍**推翻过一版**：第一版按"草是绿的"给了 `(0.240, 0.300, 0.058)`
// —— 绿通道是沙地的 4.2 倍 ⇒ 400 m 俯视图里是一地**荧光绿喷漆斑**，
// 完全不像长出来的东西。根因是这份 shader 的底色是**深红土**
//（`_land_mid = (0.230, 0.072, 0.011)`，绿只有红的 1/3），
// 任何"正常绿"在它旁边都会过冲。
//
// ⇒ 现在的取值按**最终画面**倒推：干草在月光下是**灰橄榄**，
// 比红土亮、但绝不是荧光绿。判据是"绿通道约为红土的 2.8 倍"（不是 4.2 倍），
// 且蓝通道抬到 0.080（第一版只有 0.058，太"纯色"了，真实干草有灰）。
//
// ⚠️ 同时颜色也必须**压住蓝通道**：本工程夜战每通道增益是
// 红 0.30 / 绿 0.45 / 蓝 0.92（蓝是红的三倍），蓝给高了乘完光会读成**青蓝**。
// 要最终画面 G 明显高于 B，需要 `albedo.g > 2.0 × albedo.b`（这里是 2.56 倍）。
const vec3 VEG_COLOR = vec3(0.195, 0.205, 0.080);
// 混入权重。**不给 1.0**：草丛之间要漏出裸土（否则斑块是一张"绿贴纸"），
// 也给 0.72 而不是第一版的 0.88 —— 实拍里 0.88 那版整体太"实"了。
const float VEG_MIX = 0.72;

// ---- 颜色斑驳（1.2.3 批 I · 轮 7）----
//
// 用户："**地面看起来都是大色块，不够细致**，多搞点细节"。
//
// ## 为什么加了五层倍频、又加了材质分层，还是"大色块"
// 因为到目前为止，地表的**颜色**几乎只由两样东西决定：
//   ① `COLOR.rgb` 顶点色 —— 它按**高度分带**（`_land_color()` / `_city_land_color()`
//      就几条阈值线）⇒ 颜色场是**分片常数**，这就是"大色块"的本体；
//   ② `detail_grain` 那条 ±20% 的明暗调制 —— 它是**同一个**五层噪声，
//      而五层里最粗那层（沙漠 1280 m、城市 160 m）在近景就是个**平滑的大包**，
//      于是"细节"集中在大尺度上，小尺度上仍然平。
// 换句话说：**细节做了，但都做在了"比屏幕大的尺度"上**。
//
// ## 所以补一层**专门负责小尺度颜色**的**
// 它的最粗层 λ 只有 20~40 m（比 `detail_wavelength` 小一到两个数量级），
// 三层倍频（lacunarity 4）⇒ 覆盖 20 m 一路到 1.2 m。
// 因此近距离看是"**密密麻麻的小色斑**"，而不是几块大色。
//
// ⚠️ 两个关键点：
//   · **逐层按屏幕像素淡出**（`_oct_fade`）—— λ1.2 m 的层在 3 km 高空只有
//     零点几个像素，不剔除就是整屏噪点（这一条在 `detail_*` 那边踩过一次）；
//   · **围绕 1.0 居中调制**（`1 + m·2·strength`，`m ∈ [-0.5, 0.5]`）——
//     均值为 0，不改平均亮度。这条铁律的出处见 `detail_grain` 那段血泪注释。
//
// 另外它**不止调明暗，还调冷暖**（`mm` 同时推 r 与 b 的反方向）：
// 真实地表的斑块是"矿物色差"（同一亮度下的色偏），只调明暗会读成"脏"。
uniform float mottle : hint_range(0.0, 1.0) = 0.0;
uniform float mottle_wavelength = 24.0;

// ---- 云影覆盖图 ----
// `hint_default_black`：没人给它贴图时读到 0 = 没有云影。
// 反过来（默认白）会让整块地表在初始化阶段先黑一遍，看起来像加载出了错。
uniform sampler2D cloud_shade_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec2 cloud_field_origin = vec2(0.0);
uniform float cloud_field_span = 52000.0;
uniform float cloud_shade_strength : hint_range(0.0, 1.0) = 0.0;

// ---- 程序化噪声（value noise，五层倍频）----
// 用的是最便宜的一套：floor/fract + 双线性 + smoothstep，没有三角函数、没有纹理采样。
float _hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = _hash21(i);
	float b = _hash21(i + vec2(1.0, 0.0));
	float c = _hash21(i + vec2(0.0, 1.0));
	float d = _hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ============================================================ 倍频表
//
// 五层，lacunarity = 4。**权重之和恰好 = 1**（关键：见 `_detail_h` 的归一化说明）。
//
// ---- ⚠️ 2026-09-23（批 H · 轮 2 **实拍第二次推翻**）：权重从"粗层主导"改成"接近平坦" ----
//
// 第一版的权重是 `0.4375 / 0.25 / 0.125 / 0.125 / 0.0625` —— 最粗那层独占 43.75%，
// 理由写在下面（"前三层给地形感"）。这个理由**只在远处成立**：
// 3 km 高空看 20 km 外时细层全被 `_oct_fade` 剔了，粗层权重当然该最大。
//
// 但**近景恰恰相反**：`--seacam=45` 那种贴地机位，视场里只有几十到几百米，
// 波长 1280 m 的层**跨不到一个晶格 ⇒ 它是常数**。于是那 43.75% 的权重
// 不但不产细节，还在归一化里**把细层稀释掉**：
// 真正有变化的 80/20/5 m 三层合计只有 0.3125，`h0` 的峰峰只剩 ±0.09，
// 乘上 `detail_grain` 之后是 ±5% 的 albedo 调制 —— **夜里完全看不出来**。
//
// 实测证据：沙漠贴地（`--detail=0` vs 开）**两张图肉眼无差别**，
// 关掉 `--matblend` 之后地面是一整片纯色赭石。也就是说"地表细节"这一整项
// 在近景**几乎完全由材质分层那一轮贡献**，五层倍频本身是空转的。
//
// 改成接近平坦之后，**远处的行为几乎不变**：远处只有 1280/320/80 三层活着，
// 归一化会把它们重新拉满（`0.26/0.25/0.19` → `0.371/0.357/0.271`），
// 只是多尺度感更强、沙丘的"单一主导"变弱 —— 而这本来就比"一个波长撑满全场"更真。
float tri_noise(vec3 p, vec3 weights) {
	return _vnoise(p.yz) * weights.x + _vnoise(p.xz) * weights.y + _vnoise(p.xy) * weights.z;
}

const float DET_W0 = 0.2600;
const float DET_W1 = 0.2500;
const float DET_W2 = 0.1900;
const float DET_W3 = 0.1600;
const float DET_W4 = 0.1400;

// 本片元所在的**屏幕像素**对应地表上多大一块（米/像素）。
//
// ⚠️ **用屏幕空间导数算，不是用视口尺寸算**（批 E 第二版 · 第二次修正）。
// 第一版写的是 `0.5 * VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1] / 距离` ——
// 两个前提都不成立：
//   ① **`VIEWPORT_SIZE` 在 Godot 4 的空间 shader 里根本不存在**
//     （实测报 `SHADER ERROR: Unknown identifier in expression: 'VIEWPORT_SIZE'`，
//      整份地面材质退回默认材质 —— 而且**只在真渲染时才发现**，无头测试一个信号都没有）；
//   ② 就算有，那套算法只是"垂直于视线的平面上的尺寸"，对**斜看的地面**是错的
//     （掠射角下真实足迹会长得多，摩尔纹正是从那儿来的）。
//
// 导数口径把这两条一起解决：`dFdx(world_pos.xz)` 就是"屏幕往右一格，地表上走了几米"。
// 它自动包含了倾斜、距离、fov、视口尺寸 —— **没有任何一个需要我手写**。
// 取 x/y 两个方向的**较大者**：抗锯齿要按最坏方向剔除，取小的会在掠射方向上漏剔除。
float _ground_mpp(vec2 wp) {
	return max(length(dFdx(wp)), length(dFdy(wp)));
}

// 一层波长为 `wl` 的噪声，在屏幕上一个周期占多少像素 ⇒ 该保留多少。
// `smoothstep(1.0, 2.5, ...)`：低于 1 px 的层**必须**消失（那是纯噪声），
// 1~2.5 px 之间线性淡出（这一段即使保留也会闪，淡出比硬切稳）。
// 2.5 px 以上完整保留 —— 那才是"看得见的纹理"。
float _oct_fade(float wl, float mpp) {
	return smoothstep(1.0, 2.5, wl / max(mpp, 0.0001));
}

// 材质掩码：0 = 各向同性（细料），1 = 层理（沿 `mat_angle` 强拉伸）。
// `* 1.30 - 0.15` 把 value noise 的 0..1 拉宽一点，好让两个极端都真的出现
//（不拉宽的话中位数 0.5、极端很稀，整张图会全是「半层理」）。
float _mat_mask(vec2 wp, float mpp) {
	// 大尺度分区（λ ≈ 4.5 km）：远处唯一还读得出来的东西。
	float big = _vnoise(wp * mat_mask_scale);
	// 小尺度斑驳（λ ≈ 60 m）：只在近处出现。
	float small = _vnoise(wp * 0.0167);
	// ⚠️ **两级是必须的，只留一级必炸一边**：
	//   · 只留大尺度（4.5 km）⇒ 在几百米的近景里整屏是一个常数，
	//     实测城市地面 `--matblend=0` 的 A/B **逐位相同**（分层等于没开）；
	//   · 只留小尺度（60 m）⇒ 3 km 高空看 20 km 外时它只有零点几个像素，
	//     于是每个像素随机挑一种材质 ⇒ 变成**噪点**。
	// 按「这一层在屏幕上占几个像素」淡出，就把两边都避开了 ——
	// 同一个 `_oct_fade`，和逐层剔除倍频用的是同一把尺子。
	float k = _oct_fade(60.0, mpp);
	return clamp(mix(big, small, k) * 1.30 - 0.15, 0.0, 1.0);
}

// 沿 `mat_angle` 方向**压缩**坐标（= 纹理在该方向被拉长）。
//
// 写法是「投影 → 缩放 → 还原」：把点投到方向 `d` 与其法向 `p` 上，
// 只在 `d` 那一个分量上乘 `k`，再合成回去。比构造旋转矩阵少一次转置，
// 也不依赖坐标轴（`mat_angle` 为 0 时退化成 `x *= k`）。
//
// ⚠️ `mpp` 传的是**未 warp 的坐标**上的米/像素：掩码要用它挑尺度，
// 而 warp 又依赖掩码 —— 传 warp 后的会绕成一个环。
//
// ---- ⚠️ 2026-09-23（批 H · 轮 2）：方向必须**分区**，不然是"拉丝" ----
//
// 第一版 `mat_angle` 是一个**全局常数**，于是整个屏幕的层理严格平行 ——
// 实拍 `_pixprobe_h2b_ul_on.png` 里，沙丘被打成了一片**从近到远同向的斜条纹**，
// 读起来像木纹或丝绸，不像风成地貌。真地表不会有这种事：沙纹顺风向、岩层顺岩层走向，
// 而风向/走向本来就随地形改。
//
// 修法是用一层**很低频**的噪声（λ ≈ 11 km）把方向在 90° 之内推一下：
// 大尺度上"这一片顺这边、那一片顺那边"，落到任何一块可玩的场地里
// 至少能看到两个方向交织。
//
// ⚠️ **必须 `smoothstep` 平滑过渡，不能硬切**：方向是直接作用在坐标上的，
// 硬切会在两个区域的交界处留下一条**折线接缝**（坐标压缩是仿射的，跨过突变点
// 时梯度不连续）。用 `smoothstep(0.42, 0.58, ...)` 让角度连续转过去，接缝就没有了。
//
// 代价是每片元多一次 `_vnoise`（4 次 hash），相对于这里本来就在做的 10+ 次可以忽略。
vec2 _mat_warp(vec2 wp, float blend, float mpp) {
	float mm = _mat_mask(wp, mpp) * blend;
	float k = mix(1.0, 1.0 / mat_stretch, mm);
	float turn = smoothstep(0.42, 0.58, _vnoise(wp * 0.00009)) * 1.5707963;
	float ang = mat_angle + turn;
	vec2 d = vec2(cos(ang), sin(ang));
	vec2 p = vec2(-d.y, d.x);
	return d * (dot(wp, d) * k) + p * dot(wp, p);
}

// 植被的**斑块场**（值域 [0, 1]，就是"草丛 / 裸土"的那张图）。
//
// 两层，按屏幕像素换挡：
//   · 簇 λ ≈ 300 m —— 远处用它。855 m 的视场里有 ~2.9 个周期 ⇒
//     单帧统计**收敛到全局分布**（这正是第一版缺的那一环：第一版主导层是
//     λ1.9 km，855 m 视场里跨不到半个周期 ⇒ 它在整帧里是个常数）。
//   · 斑块 λ ≈ 14 m —— 近景的"一丛一丛"。
//
// ⚠️ 换挡点是 **14 m**（细层自己的波长），不是别处的 60 m：
// 换挡点必须等于被换掉那一层自己的波长，否则要么提前杀掉可见的斑块、
// 要么在斑块已经变成噪点之后还留着它。
// ⚠️ `_veg_patch()` 已随阈值方案一起删除（批 K · 轮 1③）：
// 分布形状现在由 `world_builder.gd` 的 `_desert_oasis_sites()` 决定，
// 本 shader 只采样掩码。**不留没人用的函数** —— 那会让人以为它还在生效。
// 需要"团内也要有颗粒感"这一层时，用的是下面 fragment 里那段 14 m 细噪声
//（`_vnoise(vp * 0.0714 ...)`），它与 `_oct_fade` 配合、按 `mpp` 自动淡出，
// 比 `_veg_patch` 那套"两级换挡"更短也更不容易错。

// 颜色斑驳场，返回 **[-0.5, 0.5]**（围绕 0 居中，乘性调制时要先减 0.5）。
//
// 三层、lacunarity 4、权重和 = 1 —— 与 `_detail_h` 同一套规矩，
// 但**整体波长小一到两个数量级**（见 uniform 处的说明）。
float _mottle_field(vec2 wp, float lam, float mpp) {
	float s = 0.0;
	float wsum = 0.0;
	float wl;
	float w;
	wl = lam;
	w = 0.45 * _oct_fade(wl, mpp);
	if (w > 0.0) { s += w * _vnoise(wp / wl + vec2(7.1, 91.3)); wsum += w; }
	wl = lam * 0.25;
	w = 0.33 * _oct_fade(wl, mpp);
	if (w > 0.0) { s += w * _vnoise(wp / wl + vec2(43.7, 12.9)); wsum += w; }
	wl = lam * 0.0625;
	w = 0.22 * _oct_fade(wl, mpp);
	if (w > 0.0) { s += w * _vnoise(wp / wl + vec2(88.3, 55.1)); wsum += w; }
	return s / max(wsum, 0.0001) - 0.5;
}

// 五层倍频的高度场，值域 [0, 1]。
//
// ⚠️ **必须除以"当前活着的权重之和"**（`wsum`），不能直接返回加权和：
// 远处细层被剔除后加权和会变小 ⇒ 颗粒变浅 ⇒ **地面整体变亮** ⇒
// 1.2 逐张图调好的亮度基线（沙地均值 R=87.4 那组数）就被悄悄改掉了。
// 归一化之后"远处更平滑"但不"更亮"。这条不做，A/B 会把"距离"读成"亮度变化"。
float _detail_h(vec2 wp, float lam, float mpp) {
	float sum = 0.0;
	float wsum = 0.0;
	float wl;
	float w;
	// 每层一个固定偏移：不然五层的晶格会同心对齐，看起来像一张方格网。
	wl = lam;
	w = DET_W0 * _oct_fade(wl, mpp);
	if (w > 0.0) { sum += w * _vnoise(wp / wl); wsum += w; }
	wl = lam * 0.25;
	w = DET_W1 * _oct_fade(wl, mpp);
	if (w > 0.0) { sum += w * _vnoise(wp / wl + vec2(31.7, 17.3)); wsum += w; }
	wl = lam * 0.0625;
	w = DET_W2 * _oct_fade(wl, mpp);
	if (w > 0.0) { sum += w * _vnoise(wp / wl + vec2(63.4, 34.6)); wsum += w; }
	wl = lam * 0.015625;
	w = DET_W3 * _oct_fade(wl, mpp);
	if (w > 0.0) { sum += w * _vnoise(wp / wl + vec2(95.1, 51.9)); wsum += w; }
	wl = lam * 0.00390625;
	w = DET_W4 * _oct_fade(wl, mpp);
	if (w > 0.0) { sum += w * _vnoise(wp / wl + vec2(126.8, 69.2)); wsum += w; }
	return sum / max(wsum, 0.0001);
}

// 单层坡度，返回**已按该层权重缩放**的梯度。
//
// 差分步长 = 该层晶格的半个格（q 空间 0.5），再乘 2 除回去 ⇒ 得到的接近该层的
// **真实梯度**。不除的话"波长越小梯度越小"，粗层会被细层直接淹没。
vec2 _oct_slope(vec2 wp, float wl, float w, vec2 off) {
	vec2 q = wp / wl + off;
	float h0 = _vnoise(q);
	float hx = _vnoise(q + vec2(0.5, 0.0));
	float hz = _vnoise(q + vec2(0.0, 0.5));
	return w * vec2(h0 - hx, h0 - hz) * 2.0;
}

// 五层**各自的**坡度之和（同样按活着的权重归一化）。
//
// ⚠️ 为什么必须逐层算坡度、而不是对合成高度场用**一个**步长：
// 步长取得比某层波长小得多时，那一层的差分 `h0 - hx` 趋近于 0 ⇒
// 它在法线上的贡献趋近于 0。第一版只有一个步长（= 最细层的半波长），
// 于是粗层（沙丘）**在法线里等于不存在** —— 沙丘"有高度"却"不产生明暗"，
// 实拍就是一片平的色块。**这是第一版地表细节白做的第二个原因。**
vec2 _detail_slope(vec2 wp, float lam, float mpp) {
	vec2 s = vec2(0.0);
	float wsum = 0.0;
	float wl;
	float w;
	wl = lam;
	w = DET_W0 * _oct_fade(wl, mpp);
	if (w > 0.0) { s += _oct_slope(wp, wl, w, vec2(0.0, 0.0)); wsum += w; }
	wl = lam * 0.25;
	w = DET_W1 * _oct_fade(wl, mpp);
	if (w > 0.0) { s += _oct_slope(wp, wl, w, vec2(31.7, 17.3)); wsum += w; }
	wl = lam * 0.0625;
	w = DET_W2 * _oct_fade(wl, mpp);
	if (w > 0.0) { s += _oct_slope(wp, wl, w, vec2(63.4, 34.6)); wsum += w; }
	wl = lam * 0.015625;
	w = DET_W3 * _oct_fade(wl, mpp);
	if (w > 0.0) { s += _oct_slope(wp, wl, w, vec2(95.1, 51.9)); wsum += w; }
	wl = lam * 0.00390625;
	w = DET_W4 * _oct_fade(wl, mpp);
	if (w > 0.0) { s += _oct_slope(wp, wl, w, vec2(126.8, 69.2)); wsum += w; }
	return s / max(wsum, 0.0001);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 世界法线 + 它的切向基（见 nrm_*_view 的说明）
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// 用世界 **Z** 当参照：地面法线是竖直的，`cross(n, Y)` 会退化成零向量
	//（这正是最常走的一条路径，不能像别处那样"拿 Y 当参照再兜底"）。
	// `cross((0,1,0), (0,0,1)) = (1,0,0)` ⇒ 平地时 t = +X、b = +Z，正是要的两个方向。
	terrain_normal_world = n;
	vec3 t = normalize(abs(n.z) > 0.95 ? cross(n, vec3(0.0, 1.0, 0.0)) : cross(n, vec3(0.0, 0.0, 1.0)));
	vec3 b = cross(t, n);
	nrm_t_view = (VIEW_MATRIX * vec4(t, 0.0)).xyz;
	nrm_b_view = (VIEW_MATRIX * vec4(b, 0.0)).xyz;
}

void fragment() {
	vec3 base = albedo_tint.rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	if (cloud_shade_strength > 0.0) {
		// repeat_disable + 线性过滤：超出覆盖图范围时钳到边缘值。
		// 云只撒在竞技场半径内，覆盖图外面本来就是"没有云"，所以钳边缘是对的。
		vec2 uv = (world_pos.xz - cloud_field_origin) / cloud_field_span;
		float shade = texture(cloud_shade_tex, uv).r;
		base *= 1.0 - shade * cloud_shade_strength;
	}
	if (detail_strength > 0.0 || detail_grain > 0.0) {
		vec2 q = world_pos.xz;
		// 材质分层（轮 2）：低频掩码把这一片地表分成「各向同性细料」与「带层理的粗料」。
		// ⚠️ warp 之后**所有**细节都按 `wq` 取（高度场、坡度、颗粒），
		// 三者用同一个坐标 —— 不然会出现"凸的地方不亮"（颗粒与法线错位）。
		vec2 wq = q;
		// ⚠️ 掩码的尺度选择要用**未 warp 的坐标**上的米/像素（`mpp0`），
		// 因为 warp 依赖掩码 —— 用 warp 后的会绕成一个环。
		float mpp0 = _ground_mpp(q);
		if (mat_blend > 0.0) {
			wq = _mat_warp(q, mat_blend, mpp0);
		}
		// 细节的米/像素用 **warp 之后**的坐标：warp 是线性变换，
		// 对 `wq` 求导就自动带上了「层理方向上波长被拉长」这个效应。
		float mpp = _ground_mpp(wq);
		float h0 = _detail_h(wq, detail_wavelength, mpp);
		// 颗粒（albedo）：与法线用同一份噪声 ⇒ 亮的地方"凸"、暗的地方"凹"，
		// 两者互相印证。
		//
		// ---- ⚠️ 2026-09-23（批 H · 轮 2 第二次修正）：改成**围绕 0.5 居中调制** ----
		//
		// 第一版是 `base *= 1.0 - detail_grain * h0`（**纯压暗**，理由是
		// "不吹亮就不会动 1.2 调好的亮度基线"）。那个理由**是错的**：
		// `h0` 的均值约 0.5，所以纯压暗的实际均值是 `1 − grain/2` ——
		// 颗粒越强，**整块地面越暗**是我自己搬进去的，与噪声无关。
		//
		// 实测（沙漠贴地，`regions.g20.mean_lum`）：
		//   detail=0（纯几何）     0.0915
		//   grain 0.5（旧）        0.0514   ← 已经被压掉 44%
		//   grain 0.825（提高后）  0.0261   ← 压掉 71%，"沙丘变沙尘暴"
		// 也就是说"提高颗粒"和"整体变暗"在旧写法里是**同一件事**，
		// 于是永远调不出"有颗粒但不暗"——这正是它一直被读成"没效果"的原因：
		// 想看出颗粒就得把 gain 拉到很大，然后地面先暗到看不清。
		//
		// 减去 0.5 之后调制**均值为 0**：`h0` 偏高处提亮、偏低处压暗，
		// 整块地表的平均亮度回到"没有 detail"的那个值 —— 基线是真的不动了。
		// 幅度 = `grain × (h0 − 0.5)`，`h0` 实际多在 0.25~0.75 ⇒ 乘子约 0.79~1.21。
		base *= 1.0 - detail_grain * (h0 - 0.5);
		if (detail_strength > 0.0 && FRONT_FACING) {
			vec2 slope = _detail_slope(wq, detail_wavelength, mpp);
			vec3 n = normalize(NORMAL);
			n = normalize(n + (nrm_t_view * slope.x + nrm_b_view * slope.y) * detail_strength);
			NORMAL = n;
		}
	}
	// ---- 颜色斑驳（1.2.3 批 I · 轮 7）----
	//
	// 用户："**地面看起来都是大色块，不够细致**，多搞点细节"。
	// 这一层专门补**小尺度颜色**：最粗 λ = `mottle_wavelength`，三层倍频（lacunarity 4）
	// 一路下探到 `mottle_wavelength / 16`（默认 24 m ⇒ 最细 1.5 m）。
	// 也就是它管的是"几米一块的小色斑"，与 `detail_*`（几百米~几千米）**不重叠**。
	//
	// ⚠️ 用**未 warp 的** `world_pos.xz`（与下面植被同理）：斑驳是**矿物成分**的差异，
	// 与岩石层理的走向无关。这样还有个工程上的好处 ——
	// `--matblend` 的 A/B 与本层的 A/B **正交**：关掉分层纹理时斑驳仍在，
	// 两组对照不会互相污染（被污染的 A/B 比没有 A/B 更坏，见 `_mat_mask` 那两段）。
	//
	// ⚠️ **围绕 1.0 居中 + 冷暖反推**：`m ∈ [-0.5, 0.5]` 且均值为 0（`_mottle_field`
	// 末尾减了 0.5）⇒ 明暗乘子 `1 + m·2·mottle` 的均值为 1，**平均亮度不动**
	//（这条铁律的出处见上面 `detail_grain` 那段：第一版"纯压暗"把亮度基线和颗粒强度
	// 绑成了一件事，于是永远调不出"有细节但不暗"）。
	//
	// 同一份 `m` 还让 r 与 b **反向**偏一点：亮斑偏暖（细沙/浮尘）、暗斑偏冷（砾石/基岩）——
	// 这是风化壳最常见的矿物色差方向。**只调明暗会读成"脏"**：
	// 人眼对"同一亮度下的色偏"的容忍度远高于对亮度的容忍度。
	//
	// ⚠️ 放在植被**之前**：斑驳是"地"的一层，草长在它上面。
	// 反过来的话 `--mottle` 的 A/B 会连带改变草的颜色，两组对照就纠缠在一起了。
	//（代价是草丛内部暂时是**纯色**的；要让草也斑驳，应该是给 `VEG_COLOR`
	//  单独再配一套噪声，而不是让它蹭地面的那一份。）
	if (mottle > 0.0) {
		vec2 mp = world_pos.xz;
		float mm = _ground_mpp(mp);
		float m = _mottle_field(mp, mottle_wavelength, mm);
		base *= 1.0 + m * 2.0 * mottle;
		float warm = m * 1.10 * mottle;
		base.r *= 1.0 + warm;
		base.b *= 1.0 - warm;
	}
	// ---- 稀疏植被覆盖 ----
	// 1.2.3 批 I · 轮 5 立项；**批 K · 轮 1③ 换了分布来源**（见 uniform 处的说明）。
	//
	// ⚠️ 放在 detail 那个 `if` **之外**：植被是一层**独立的覆盖**，
	// 不该因为 `--detail=0` 就跟着消失（那会把"有没有草"和"有没有砂粒"
	// 两件事绑在一起，以后做 A/B 会互相污染）。
	//
	// ⚠️ 用**未 warp 的** `world_pos.xz`：植被不跟着层理方向拉伸 ——
	// 草长在哪里由水土决定，与岩石的层理走向无关。
	if (veg_amount > 0.0) {
		vec2 vp = world_pos.xz;
		float mv = _ground_mpp(vp);
		// 掩码是**世界对齐**的一张图（±30 km），uv 用同一套 `origin/span` 口径。
		// ⚠️ 与云影那一段（`cloud_shade_tex`）是同一个约定：这里任何一处
		// 把 `x`/`y` 写反或把 span 当成半径，症状都是"绿斑整体平移/缩放半个图幅"，
		// 而在单张图上看起来只是"绿的地方不对" —— 所以口径写在一处、抄的时候别改。
		vec2 muv = (vp - veg_mask_origin) / veg_mask_span;
		float mask = texture(veg_mask_tex, muv).r;
		if (mask > 0.004) {
			// 边缘打碎：14 m 的细噪声，权重按"离核心多远"给。
			// ⚠️ 必须乘 `_oct_fade(14.0, mv)`：远处这一层已经淡出，
			// 若还拿它去扰边缘，得到的是**噪点**而不是碎边
			//（"掩码用一个尺度、扰动用另一个尺度"这种错位在 `_mat_mask` 那边踩过一次）。
			float kw = _oct_fade(14.0, mv);
			float grain = _vnoise(vp * 0.0714 + vec2(53.1, 7.7));
			float edge_w = clamp((VEG_EDGE_AT - mask) / VEG_EDGE_AT, 0.0, 1.0);
			float m = mask + (grain - 0.5) * VEG_EDGE_AMOUNT * edge_w * kw;
			float cov = clamp(m * VEG_MASK_GAIN - VEG_MASK_BIAS, 0.0, 1.0) * veg_amount;
			if (cov > 0.001) {
				// 混到 `VEG_MIX`（= 0.72）而不是 1.0：斑块内部也要**漏出裸土**，
				// 真实的稀疏植被不是一块"绿贴纸"（这一步让边缘更碎、更像长出来的）。
				base = mix(base, VEG_COLOR, cov * VEG_MIX);
				if (FRONT_FACING) {
					// 草丛的立体感：用**同一个细噪声**的梯度当坡度（不额外采一层噪声）。
					// ⚠️ 与掩码一样要乘 `_oct_fade(14.0, mv)`，理由同上。
					vec2 g = _oct_slope(vp, 14.0, 1.0, vec2(53.1, 7.7)) * (0.35 * kw);
					vec3 nv = normalize(NORMAL);
					nv = normalize(nv + (nrm_t_view * g.x + nrm_b_view * g.y) * cov);
					NORMAL = nv;
				}
			}
		}
	}
	float surface_rough = roughness_value;
	if (surface_detail > 0.0) {
		vec3 w = pow(abs(terrain_normal_world), vec3(4.0));
		w /= max(w.x + w.y + w.z, 0.0001);
		float footprint = max(length(dFdx(world_pos)), length(dFdy(world_pos)));
		float macro = tri_noise(world_pos / 380.0, w);
		float meso = tri_noise(world_pos / 48.0 + vec3(11.3), w);
		float keep = smoothstep(2.0, 5.0, 48.0 / max(footprint, 0.001));
		float slope = 1.0 - abs(terrain_normal_world.y);
		float rock = smoothstep(0.12, 0.55, slope) * (1.0 - hardscape);
		if (rock > 0.01 && keep > 0.01 && FRONT_FACING) {
			vec3 q = world_pos / 48.0 + vec3(11.3);
			vec3 grad = vec3(tri_noise(q + vec3(0.25,0.0,0.0), w) - meso,
				tri_noise(q + vec3(0.0,0.25,0.0), w) - meso,
				tri_noise(q + vec3(0.0,0.0,0.25), w) - meso);
			grad -= terrain_normal_world * dot(grad, terrain_normal_world);
			NORMAL = normalize(NORMAL - (VIEW_MATRIX * vec4(grad, 0.0)).xyz * rock * keep * 0.8);
		}
		float strata_keep = smoothstep(2.0, 5.0, 90.0 / max(footprint, 0.001));
		float strata = sin(world_pos.y * 0.0698 + macro * 3.0) * 0.5;
		vec3 mineral = mix(vec3(1.035, 1.015, 0.97), vec3(0.82, 0.86, 0.89), rock);
		float grain = (macro - 0.5) * 0.18 + (meso - 0.5) * keep * 0.20;
		mineral *= 1.0 + grain + strata * rock * strata_keep * 0.10;
		// Patch repairs are broad and low-contrast, never a glowing road grid.
		float repair = smoothstep(0.58, 0.70, meso) * hardscape * keep;
		mineral *= 1.0 - repair * 0.14;
		base *= mix(vec3(1.0), mineral, surface_detail);
		surface_rough = clamp(roughness_value - rock * 0.12 + grain * 0.08 - repair * 0.08, 0.35, 1.0);
	}
	ALBEDO = base;
	ROUGHNESS = surface_rough;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
}
