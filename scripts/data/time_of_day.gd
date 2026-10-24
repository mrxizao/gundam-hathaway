class_name TimeOfDay
extends RefCounted
## 时段预设：白天 / 黄昏 / 夜晚。
##
## 一个时段要同时改五样东西，缺一样就会"看着不对但说不上哪不对"：
##   1. **天空**（自定义 sky shader 的天顶/地平/地面三色 + 星星 + 日月盘）
##   2. **主光**（方向、颜色、强度 —— 夜里换成冷色低强度的月光）
##   3. **环境**（天空环境光强度、雾的颜色与浓度、曝光、辉光强度）
##   4. **海面 shader**（海面是解析波函数 + 菲涅尔，颜色全靠 uniform，不会自己变暗）
##   5. **三带云层的 tint / shade**（云是 unshaded 的 billboard，不吃光照，必须手工改色）
##
## 所有数值都集中在这里，加时段只要再写一个静态工厂 + 在 all_presets() 里登记。

enum Preset { DAY, DUSK, NIGHT, SPACE }

var preset := Preset.DAY
var name_cn := "白天"
var blurb := ""

# ---- 天空 ----
var sky_zenith := Color(0.19, 0.40, 0.78)
var sky_horizon := Color(0.66, 0.78, 0.92)
var sky_ground := Color(0.30, 0.42, 0.52)
## 天顶到地平的颜色过渡幂次：越小地平带越宽。
var sky_horizon_power := 0.55
## **地平线以下**从 `sky_horizon` 混到 `sky_ground` 的过渡宽度（`sky.gdshader` 的
## `ground_blend`，`smoothstep(0.015, -ground_blend, up)`）。
##
## ## 它管的是"地平线那条线有多厚"
## 值越大，视线越往下颜色就越早开始往 `sky_ground` 走 ⇒ 那条分界读起来是
## **一条有厚度的带**而不是一条硬边。太平洋图那条"海天分界亮带"是**几何**（海雾板）做的，
## 而这一项是**天空侧**的同类手法，不需要任何几何。
##
## ## 为什么它是本工程新提出来的一行（剧情模式轮 B2）
## 轨道图上"地平线"其实是**地球临边**：真空里没有大气散射，
## 那条边完全靠 `sky_ground`（地球反照色）与 `sky_zenith`（真空黑）的差立起来。
## 夜里的默认值 0.18 够用（`night()` 的 `sky_ground` 本来就接近黑，过渡窄也无所谓），
## 但轨道图要靠它把临边做**厚**（1.0 量级）—— 与太平洋"海雾亮带"是同一个目的。
##
## ⚠️ **默认值 0.18 = `sky.gdshader` 里那个 uniform 的默认值** ⇒
## 不给这一项赋值的时段（`day()` / `dusk()` / `night()` / `dusk_overcast()`）
## **行为逐位不变**（`apply_time_of_day()` 会把 0.18 灌回去，与 shader 默认相同）。
var ground_blend := 0.18
var star_amount := 0.0
var star_brightness := 2.6
## Fraction of old star candidates retained on atmospheric maps. Space bypasses it.
var star_coverage := 0.38
var sky_haze := 0.12

# ---- 主光（太阳 / 月亮）----
var sun_color := Color(1.0, 0.965, 0.90)
var sun_energy := 1.35
var sun_rotation_deg := Vector3(-38.0, 128.0, 0.0)
## 天体圆盘的强度 / 颜色 / 大小 / 光晕。夜里把 halo 压到很小，圆盘才像月亮不像太阳。
var disc_amount := 1.0
var disc_color := Color(1.0, 0.96, 0.88)
var disc_size := 0.012
var disc_halo := 0.35

# ---- 环境 ----
## 环境光的**颜色**与**强度**。
##
## ⚠️⚠️ **这两个数在 `ambient_sky_contribution = 1.0` 时一点用都没有。**
##
## 2026-09-24（批 K · 轮 1②）实测把这件事钉死了，起因是用户第二次说
## "**奥恩贝利的效果现在还是太差了，地面和楼房暗面依旧看不到**"：
##
##   · 本工程的环境光走 `ambient_light_source = SKY` + `sky_contribution = 1.0`
##     —— **环境色被天空辐射整体替换**，`ambient_light_color × ambient_light_energy`
##     那一项的权重是 **0**。所以 `ambient_energy` 无论取多少都不进画面。
##   · 零差异是**逐位**的：`--amb=0.0 / 2.0 / 3.0` 三档与不拧的图 **md5 相同**。
##   · 而 `sky_contribution = 0.0` 的同一档与 `source = COLOR` 的同一档
##     **md5 也相同** ⇒ 两条支路收敛到 `color × energy`，机制坐实。
##
## 危害不在"调不动"，在于它**长得完全像"参数没接上"**：
## `dusk_overcast.ambient_energy` 原来是 **1.05** —— 读起来是在补阴天的天光，
## 实际什么也没补。而阴天黄昏的天空色 `sky_zenith = (0.105,0.110,0.125)`
## 转线性只有 **0.011**，半球积分后天空辐射约 **0.02**。反算：
## `0.02 × 地面 albedo 0.16 ≈ 0.003` → ACES 之后 ≈ **0.0004**，
## 与实拍 `darkμ = 0.00043` **逐位吻合**。
## ⇒ 症状就是"地面与楼房暗面**纯黑**"：整帧 **36% 的像素 < 4/255**。
##
## ⇒ 用法：**要填充光就必须同时给 `ambient_sky_contribution < 1`**（或把
## `ambient_light_source` 换成 `COLOR`）。默认 `1.0` = 维持旧行为
##（所有夜战地图的观感一字不变，这是刻意的零回归）。
var ambient_energy := 0.85
## 环境色。**只在 `ambient_sky_contribution < 1.0` 时才有意义**（见上）。
var ambient_color := Color(0.35, 0.35, 0.38)
## 天空辐射在环境光里的权重。**1.0 = 完全用天空、上面两个数失效**；
## 0.0 = 完全用 `ambient_color × ambient_energy`。
##
## ⚠️ 默认给 1.0 而不是 0.0：夜战地图（太平洋 / 艾尔斯岩 / 靶场）的亮度基线
## 是在"只有天空辐射"这个前提下逐张调出来的，改默认值 = 把三张图一起动了。
## 要改的时段**在自己的构造函数里显式写**（`dusk_overcast()` 就是这样）。
var ambient_sky_contribution := 1.0
var fog_color := Color(0.62, 0.75, 0.92)
var fog_density := 0.000045
var fog_sky_affect := 0.18

# ---- 海面薄雾（1.2.3 批 J：用户"**海面上方一带要有一层薄薄的雾气**"）----
#
# ## 为什么不能用全局 `fog_density` 来做这件事
# 全局雾把远处的东西往 `fog_color` 上推。夜里 `fog_color = (0.030,0.045,0.085)`，
# 而**海面地平色**是 `(0.115,0.165,0.255)` —— 全局雾的方向是**把海推暗**，
# 于是海天分界（第十四轮花一整轮才拉开的那条线）会先被糊掉。
# 薄雾要的是**比海更亮的一条带**（真雾看着发白，是因为光子在雾里多次散射），
# 所以它必须**自带颜色**，不能蹭全局雾的颜色。
#
# ## 机制：`FogVolume`（盒状体积雾）
# `Environment` 上那套 `volumetric_fog_*` **没有**高度衰减（`dump_env_props.gd` 实测：
# 只有 `volumetric_fog_density` / `albedo` / `emission` / `length` / `anisotropy` …，
# 一个 `volumetric_fog_height` 都没有），所以"贴海面的一层"没法靠全局参数做出来。
# `FogVolume` 是 Godot 里唯一带**高度衰减 + 边缘淡出**的体积雾载体 —— 正是这件事的形状。
#
# ## 为什么是"体积"而不是"几张贴图面片"
# 层叠面片（fog card）在**掠射角**下会露馅：会看到每条面片的硬边，
# 而且"看到几层"随视角突变 —— 而贴海平飞全是掠射角。
# 体积雾没有这个问题，代价是 froxel 那一遍（可以用 `--perf` 量出来）。
#
# ⚠️ 这七个数**只有太平洋图会改**（见 `MapDef._pacific_night()`），
# 默认 0 = 关 —— 另外三张图一个字段都不受影响，所以零回归风险。
## 雾板密度。0 = 这一档不要海雾。⚠️ **它不等于"每米消光系数"** ——
## 实测的有效光深 ≈ `3×10⁻³ × density × 光程(米)`，也就是差了约三个数量级。
## 定量与踩坑记在 `MapDef._pacific_night()`，那里才是写这个数的正文。
var sea_mist_density := 0.0
## 雾板**顶面**高度（米，水面以上）；板底固定贴在水面。
## 真实平流雾的厚度就是几十到两百米 —— 这也是它读起来"薄"的原因，不是审美选择。
var sea_mist_top := 160.0
## 雾板水平跨度（米）。给到竞技场外圈，让"贴海那一层"一直铺到看不清为止。
var sea_mist_span := 90000.0
## 散射反照率：**雾自己的颜色**。夜里给比海面亮的冷灰蓝（"亮带"是薄雾的读感本体）。
var sea_mist_albedo := Color(0.42, 0.50, 0.66)
## **自发光**。⚠️ 这不是"雾在发光"，是**多重散射的替身**：
## 体积雾只解一次散射，而真雾之所以发白，是光子在里面弹了很多次。
## 给一点自发光正好补这一项 —— 它也是"雾比背景亮"的来源，
## 而"比背景亮"这条不给就永远做不出月光下的雾。
var sea_mist_emission := Color(0.055, 0.070, 0.105)
## 高度衰减（世界空间，衰减系数）。0 = 上下均匀 —— 那就**不叫**"贴海面"了。
var sea_mist_falloff := 1.6
## 边缘淡出（0~1）：雾板的侧面与顶面各自淡出的比例。
##
## ⚠️ **默认 0.0，而且这不是"懒得调"** —— 是量出来的（2026-09-23，`--misted` 扫描）：
## 本工程的世界尺度下，雾板的六个面**永远在体雾的积分范围之外**
## （雾板 90 km、相机在 20.7 km 处、而 `volumetric_fog_length` 只有 4000 m
## ⇒ 最近的侧面也在 24 km 外），所以淡出**没有任何东西可淡**。
## 它唯一能做到的事，是**把雾板内部近处那一片一起削掉**：
## 实测同剂量 0.0060、同机位（`--seacam=45`），
## `edge_fade = 0.55` → 整帧 +12.10%；`edge_fade = 0.0` → 整帧 **+17.98%**。
## 也就是原来的 0.55 白吃掉了三分之一的雾。
## 另外记一笔：把雾板边长从 90 km 提到 200 km，输出**逐位不变** —— 同一个道理的佐证。
var sea_mist_edge_fade := 0.0
## tonemap 曝光。夜里要抬一点，否则暗部全糊成一片黑、看不清姿态。
var exposure := 1.0
var glow_intensity := 0.45

# Per-map grading; defaults reproduce the previous environment on untouched maps.
var glow_bloom := 0.06
var glow_hdr_threshold := 1.1
var grade_contrast := 1.06
var grade_saturation := 1.05
var fog_sun_scatter := 0.0
var fog_aerial_perspective := 0.45
var volume_anisotropy := 0.35
# Directional sky scattering is independent of the visible sun disc (overcast support).
var sky_scatter_strength := 0.0
var sky_scatter_power := 8.0

# ---- 海面 shader ----
var ocean_deep := Color(0.020, 0.082, 0.152)
var ocean_crest := Color(0.10, 0.32, 0.44)
var ocean_sky := Color(0.44, 0.64, 0.92)
var ocean_horizon := Color(0.62, 0.76, 0.92)
## 月光/日光的**镜面反射带**强度（第十四轮 A1）。0 = 关。
##
## 抬亮海面只解决"看得见"，解决不了"哪个方向是水"；
## 镜面带（`ocean.gdshader` 里的半程向量高光）才给出方位与倾斜。
## 白天不需要它：太阳直射的高光本来就够亮。
var ocean_glitter := 0.0
var ocean_glitter_sharp := 120.0
var ocean_moon_color := Color(0.55, 0.68, 0.95)

# ---- 三带云层：低空 / 主积云 / 高空卷云 ----
var cloud_tints: Array[Color] = [
	Color(0.87, 0.90, 0.97, 0.30),
	Color(1.0, 1.0, 1.0, 0.82),
	Color(0.96, 0.975, 1.0, 0.22),
]
var cloud_shades: Array[Color] = [
	Color(0.58, 0.64, 0.76),
	Color(0.72, 0.78, 0.88),
	Color(0.78, 0.84, 0.94),
]


static func day() -> TimeOfDay:
	var t := TimeOfDay.new()
	t.preset = Preset.DAY
	t.name_cn = "白天"
	t.blurb = "标准日间光照 · 云层最亮 · 视野最清晰"
	return t


static func dusk() -> TimeOfDay:
	var t := TimeOfDay.new()
	t.preset = Preset.DUSK
	t.name_cn = "黄昏"
	t.sky_zenith = Color(0.085, 0.115, 0.330)
	t.sky_horizon = Color(0.92, 0.42, 0.18)
	t.sky_ground = Color(0.10, 0.07, 0.09)
	t.sky_horizon_power = 0.85
	t.star_amount = 0.22
	t.sun_color = Color(1.0, 0.62, 0.36)
	t.sun_energy = 0.85
	t.sun_rotation_deg = Vector3(-7.0, 128.0, 0.0)
	t.disc_amount = 1.6
	t.disc_color = Color(1.0, 0.55, 0.28)
	t.disc_size = 0.020
	t.disc_halo = 0.75
	t.ambient_energy = 0.55
	t.fog_color = Color(0.42, 0.28, 0.32)
	t.fog_density = 0.000058
	t.fog_sky_affect = 0.28
	t.exposure = 1.10
	t.glow_intensity = 0.70
	t.ocean_deep = Color(0.020, 0.030, 0.065)
	t.ocean_crest = Color(0.16, 0.10, 0.12)
	t.ocean_sky = Color(0.55, 0.35, 0.32)
	t.ocean_horizon = Color(0.80, 0.45, 0.28)
	t.cloud_tints = [
		Color(0.55, 0.42, 0.42, 0.28),
		Color(0.78, 0.62, 0.60, 0.80),
		Color(0.70, 0.58, 0.62, 0.22),
	]
	t.cloud_shades = [
		Color(0.30, 0.18, 0.22),
		Color(0.36, 0.24, 0.28),
		Color(0.40, 0.28, 0.32),
	]
	return t


## **阴天黄昏**（第二十二轮下半新增，奥恩贝利专用）。
##
## ## 为什么不能用现成的 `dusk()` 或 `night()`
## 用户对奥恩贝利的设定是：**"刚刚经历完大屠杀的死城，时间是阴天黄昏"**。
##   - `night()` 是**夜战**：天上有星星、有月亮、有月光镜面 —— 与"阴天"矛盾；
##   - `dusk()` 是**晴天的火烧云**：天边一条橙、太阳低到地平线上、云被染成粉紫 ——
##     那是"风景明信片"的黄昏，不是"屠杀之后的黄昏"。
##
## 这一档要的是**没有太阳的黄昏**：整个天穹被厚云压成一片铅灰，
## 只剩地平线附近一点脏橙色（太阳在云后面），大地全靠**散射光**照亮 ——
## 于是楼没有影子、也没有灯光，只剩轮廓和明暗差。
##
## ⚠️ 三个关键改动都是"跟 `dusk()` 反着来"的，别照抄：
##   | 量 | `dusk()` | 这一档 | 为什么 |
##   |---|---|---|---|
##   | `star_amount` | 0.22 | **0.0** | 阴天，一颗星都不该有 |
##   | `disc_amount` | 1.6（大太阳） | **0.0** | 太阳被云完全挡住 |
##   | `sun_energy` | 0.85 | **0.30** | 直射光被云吃掉了，只剩"一点点方向感" |
##   | `ambient_energy` | 0.55 | **1.05** | 阴天是**散射光天下**，环境光必须顶上来 |
##   | `glow_intensity` | 0.70 | **0.30** | 没有灯光、没有直射，辉光只会让画面发糊 |
static func dusk_overcast() -> TimeOfDay:
	var t := TimeOfDay.new()
	t.preset = Preset.DUSK
	t.name_cn = "阴天黄昏"
	t.blurb = "厚云压顶、太阳在云后 —— 一座刚刚死去的城市"
	# 天穹：铅灰压顶，越靠地平线越脏（带一点橙，暗示太阳的方位）。
	t.sky_zenith = Color(0.105, 0.110, 0.125)
	t.sky_horizon = Color(0.400, 0.330, 0.280)
	t.sky_ground = Color(0.075, 0.072, 0.070)
	t.sky_horizon_power = 0.55
	t.star_amount = 0.0
	t.star_brightness = 0.0
	t.disc_amount = 0.0
	t.disc_color = Color(0.55, 0.42, 0.34)
	t.disc_size = 0.02
	t.disc_halo = 0.0
	# 太阳：**低 + 弱 + 发灰**（云层把直射光散射掉了）。
	# 保留一点方向感是有用的 —— 机体/楼体上有微弱的明暗差，才不至于是一堆剪影。
	t.sun_color = Color(0.86, 0.74, 0.62)
	t.sun_energy = 0.30
	t.sun_rotation_deg = Vector3(-11.0, 128.0, 0.0)
	# 环境光：阴天的光**几乎全部**来自这里。
	#
	# ⚠️ 2026-09-24（批 K · 轮 1②）：**原来这里只有 `ambient_energy = 1.05` 一行，
	# 而它在 `sky_contribution = 1.0` 下是空转的** —— 也就是说这句注释写的意图
	#（"光几乎全部来自环境光"）**从来没有兑现过**，画面上的实际填充光约等于 0。
	# 这与用户两次反馈"地面和楼房暗面看不到"完全一致：整帧 36% 的像素 < 4/255。
	#
	# 现在把那一项**显式打开**（`sky_contribution = 0.0`），填充光才真的存在。
	# 三个数是**实测量出来的**，不是估的 —— 剂量表（`--seacam=300` 平视机位，
	# `--ambcol=0.34,0.35,0.40`，`crush%` = 低于 4/255 的像素占比、
	# `darkσ` = 最暗 30% 内部的起伏，即"暗面看得见"的本体）：
	#
	# | energy | 整帧 mean | crush% | darkμ | darkσ |
	# | 关（旧） | 0.2296 | **36.04%** | 0.00043 | 0.00107 |
	# | 1.0 | 0.2828 | 10.92% | 0.0385 | 0.0336 |
	# | **1.8（采用）** | 0.3115 | **5.55%** | 0.0688 | 0.0468 |
	# | 2.8 | 0.3290 | 4.10% | 0.0848 | 0.0571 |
	# | 4.0 | 0.3488 | 2.77% | 0.1005 | 0.0664 |
	#
	# 选 1.8 而不是 2.8/4.0：① 预算判据是 `crush% < 8%`、整帧涨幅 `< +45%`，
	# 1.8 是**第一个同时满足两条**的档（+35.7%），2.8 已经 +43.3% 贴着上限；
	# ② 边际收益那一段明显走平（1.8→2.8 只把 crush 从 5.55 压到 4.10，
	# 代价是整帧再亮 7.6 个百分点的**绝对**涨幅）—— 阴天黄昏要的是"什么都看得见"，
	# 不是"更亮"。
	#
	# 颜色取**冷灰**（蓝略高）而不是暖色：阴天的天光是冷灰的，
	# 而地面本身的 albedo 已经是红土/暖灰（`ground_swatch`），
	# 环境光再给暖的会把这层色差抹掉（这条在 `VEG_COLOR` 那段踩过一次：
	# 红土旁边任何"正常色"都会过冲）。
	t.ambient_sky_contribution = 0.0
	t.ambient_color = Color(0.34, 0.35, 0.40)
	t.ambient_energy = 1.8
	# 雾：偏暖灰的霾（雨后的空气），比夜景那档更浓一点。
	t.fog_color = Color(0.330, 0.300, 0.285)
	t.fog_density = 0.000030
	t.fog_sky_affect = 0.42
	t.exposure = 1.0
	t.glow_intensity = 0.30
	# 海面：没有太阳镜面，只剩铅灰反光。
	t.ocean_deep = Color(0.030, 0.038, 0.048)
	t.ocean_crest = Color(0.10, 0.11, 0.12)
	t.ocean_sky = Color(0.24, 0.24, 0.25)
	t.ocean_horizon = Color(0.36, 0.32, 0.30)
	t.ocean_glitter = 0.0
	# 云：**这是这张图的天空主角**。低空压得厚、颜色偏铅灰带一点土黄
	#（沙尘/烟尘感），于是"阴天"不是蓝天加灰云，而是一整片顶盖。
	t.cloud_tints = [
		Color(0.30, 0.29, 0.30, 0.62),
		Color(0.38, 0.36, 0.35, 0.90),
		Color(0.30, 0.29, 0.30, 0.50),
	]
	t.cloud_shades = [
		Color(0.16, 0.155, 0.16),
		Color(0.20, 0.19, 0.195),
		Color(0.235, 0.225, 0.23),
	]
	return t


## 夜晚（四张图原本共用的那档）。
static func night() -> TimeOfDay:
	var t := TimeOfDay.new()
	t.preset = Preset.NIGHT
	t.name_cn = "夜晚"
	t.sky_zenith = Color(0.010, 0.017, 0.045)
	t.sky_horizon = Color(0.045, 0.070, 0.150)
	t.sky_ground = Color(0.006, 0.010, 0.022)
	t.sky_horizon_power = 0.45
	t.star_amount = 1.0
	t.star_brightness = 2.6
	t.sun_color = Color(0.62, 0.72, 1.0)
	# 月光/环境光比"物理正确"要亮一点：完全按真实月夜来，
	# 自家机体就是一个纯黑剪影，玩家连自己的姿态都看不出来。
	# 夜感靠天空、星空和夜航灯撑，不靠把机体压黑。
	t.sun_energy = 0.44
	t.sun_rotation_deg = Vector3(-58.0, -42.0, 0.0)
	t.disc_amount = 1.3
	t.disc_color = Color(0.80, 0.87, 1.0)
	t.disc_size = 0.010
	t.disc_halo = 0.10
	t.ambient_energy = 0.42
	t.fog_color = Color(0.030, 0.045, 0.085)
	t.fog_density = 0.000060
	t.fog_sky_affect = 0.05
	# 曝光抬到 1.55（第四轮从 1.35 再提 15%）：完全不抬就是一片纯黑，
	# 玩家连自己的机体都看不见，那不叫"夜晚"，那叫"屏幕坏了"。
	t.exposure = 1.55
	# 辉光调高，夜航灯 / 尾焰 / 光束才会真的发光
	t.glow_intensity = 0.90
	# ---- 海面（第十四轮 A1：夜海必须"看得见、分得出地平线"）----
	#
	# 原来这四个数是 (0.004,0.012,0.030) 那一档 —— 近似纯黑，而天空地平线
	# (0.045,0.070,0.150) 也在同一个亮度量级上，于是**海天糊成一片**。
	# 玩家实测原话："它说我撞海我都不知道海在哪"、"主要是看不到离海有多远"；
	# 而且低空追尾（唯一能缩短距离的姿态）会一头扎进看不见的海面。
	#
	# 两件事一起做，缺一件都不成立：
	#   ① **整体抬亮约 3 倍** —— 海面自己要有可读的明度；
	#   ② **海的地平色抬到明显高于天空地平色**（约 2.3 倍）——
	#      只抬亮而不拉开这一档，海天仍是同一个明度，地平线照样找不到。
	# 月光镜面带由 shader 负责（`ocean_glitter`），
	# 它解决的是"哪个方向是水"，与这里的明度是两件事。
	t.ocean_deep = Color(0.014, 0.036, 0.070)
	t.ocean_crest = Color(0.060, 0.135, 0.205)
	t.ocean_sky = Color(0.075, 0.110, 0.205)
	t.ocean_horizon = Color(0.115, 0.165, 0.255)
	t.ocean_glitter = 0.55
	t.ocean_glitter_sharp = 120.0
	t.cloud_tints = [
		Color(0.13, 0.16, 0.26, 0.34),
		Color(0.17, 0.20, 0.31, 0.86),
		Color(0.12, 0.15, 0.26, 0.22),
	]
	t.cloud_shades = [
		Color(0.050, 0.060, 0.120),
		Color(0.050, 0.060, 0.120),
		Color(0.060, 0.070, 0.140),
	]
	return t


## **近地轨道**（剧情模式轮 B2 新增，`MapDef.leo()` 专用）。
##
## ## ★ 它**不登记进 `all_presets()`**，理由有两条，第二条是硬的
## ① **语义**：`all_presets()` 是"**一天里的三个时刻**"（白天 / 黄昏 / 夜晚），
##    而"轨道"不是一个时刻 —— 把它塞进去等于说"轨道是第四个时刻"。
## ② **回归**：`tests/suite_abilities.gd` 有一条断言
##    `all_presets().size() == 3`（"一共三个时段"）。登记进去这条**当场变红**，
##    而它断言的是"三个时段"，不是"三个预设"。
## 而 `MapDef.time_of_day` 是**实例字段** ⇒ `MapDef.leo()` 直接 `TimeOfDay.space()`
## 就行，**不需要经过 `make()`、也就不需要登记** ⇒ 零回归拿到新时段。
##
## ## 这一档与 `night()` 的差别（只有"真空"这一件事）
## | 量 | `night()` | 这一档 | 为什么 |
## |---|---|---|---|
## | `sky_zenith` | (0.010,0.017,0.045) | **更黑** | 真空里天顶没有任何散射光 |
## | `sky_ground` | (0.006,0.010,0.022) | **亮一个量级** | ★ `sky.gdshader` 把地平线以下混到 `ground` 色 —— 轨道上那一片就是**地球本体**。**它是唯一撑起"我在轨道上而不是在黑箱子里"的东西** |
## | `ground_blend` | 0.18 | **0.55** | 让临边读成一条**有厚度的亮带**而不是硬边（同 `night()` 下那条"海雾亮带"的用意，但这里是天空侧、零几何） |
## | `fog_density` | 0.000060 | **0.0** | ★ 那层雾是**大气**雾。轨道上没有大气 ⇒ 必须清零，否则整个背景蒙一层灰 |
## | `sun_energy` | 0.44（月光） | **2.2** | 真空里没有大气衰减，太阳是硬光 |
## | `cloud_tints/shades` | 三带不透明色 | **三带全透明** | 本图 `cloud_density = 0`（不建云），但数组**仍给满 3 项** —— `apply_time_of_day()` 是**按创建顺序**取 tint 的，数组短了会静默 `break`（见那个循环的注释） |
##
## ⚠️ `ambient_sky_contribution` **保持 1.0**（与其余三档一致）：
## `suite_round20` 钉着这一项，而且轨道图的天光本来就只该来自天空辐射。
static func space() -> TimeOfDay:
	var t := TimeOfDay.new()
	t.preset = Preset.SPACE
	t.name_cn = "近地轨道"
	t.blurb = "真空 · 满屏星空 · 地平线以下就是地球"
	# ---- 天空：上黑、临边一圈薄亮、往下是地球 ----
	t.sky_zenith = Color(0.004, 0.006, 0.016)
	t.sky_horizon = Color(0.045, 0.075, 0.145)
	# ★ 地球反照（冷蓝白）。**比 `sky_horizon` 亮** ⇒ 临边是一条从暗到亮的过渡带。
	t.sky_ground = Color(0.135, 0.190, 0.285)
	# 0.35（比夜里那档 0.45 更小）：天顶到地平的变化更慢 ⇒ 临边那一圈更宽。
	t.sky_horizon_power = 0.35
	# ★ 本工程新提出的一行：地平线以下的过渡宽度。
	t.ground_blend = 0.55
	# ---- 星空：轨道上星空是主画面（但 `star_amount` 的 hint 上限是 3.0，别一上来顶满）----
	t.star_amount = 1.0
	t.star_brightness = 2.9
	# ---- 主光：硬、白、无暖偏（真空中没有瑞利散射）----
	t.sun_color = Color(1.0, 0.99, 0.97)
	t.sun_energy = 2.2
	# 方位挑一个与其它五张都不同的：别的图基本都在 ±130° 上下，这里给 62°，
	# 于是"影子朝哪边"一眼就能认出是另一张图（也顺手让探针的三个机位构图不一样）。
	t.sun_rotation_deg = Vector3(-24.0, 62.0, 0.0)
	# 太阳在轨道上很小很硬 ⇒ 盘收小、光晕几乎不要。
	t.disc_amount = 1.5
	t.disc_color = Color(1.0, 0.99, 0.98)
	t.disc_size = 0.006
	t.disc_halo = 0.06
	t.ambient_energy = 0.55
	# ---- 雾：**清零**（这是本档第二重要的一行）----
	t.fog_color = Color(0.020, 0.030, 0.060)
	t.fog_density = 0.0
	t.fog_sky_affect = 0.0
	# 曝光：比夜战那档（1.55）低一点 —— 轨道图的高光是人造物的金属反光与太阳，
	# 抬到 1.55 会让那几块金属过曝成白斑。
	t.exposure = 1.30
	t.glow_intensity = 0.75
	# ---- 海面（本图没有海，但这几项仍是"这一档的定义"的一部分，给暗值）----
	t.ocean_deep = Color(0.006, 0.010, 0.020)
	t.ocean_crest = Color(0.020, 0.030, 0.055)
	t.ocean_sky = Color(0.030, 0.045, 0.080)
	t.ocean_horizon = Color(0.045, 0.070, 0.120)
	t.ocean_glitter = 0.0
	# ---- 三带云：**全透明**（本图不建云；给满 3 项只是为了"数组长度对得上"）----
	t.cloud_tints = [
		Color(0.30, 0.35, 0.45, 0.0),
		Color(0.40, 0.45, 0.55, 0.0),
		Color(0.50, 0.55, 0.65, 0.0),
	]
	t.cloud_shades = [
		Color(0.02, 0.03, 0.05),
		Color(0.02, 0.03, 0.05),
		Color(0.03, 0.04, 0.06),
	]
	return t


## ⚠️ `Preset.SPACE` **故意不进这张表**，也不进 `all_presets()` ——
## 见 `space()` 的说明（`all_presets()` 是"一天里的三个时刻"，轨道不是一个时刻；
## 而 `MapDef.time_of_day` 是实例字段，直接给 `space()` 即可，不需要走这里）。
## Warm daylight through cool air; the map remains DAY, with its original geometry.
static func adelaide_cinematic() -> TimeOfDay:
	var t := day()
	t.sky_zenith = Color(0.17, 0.245, 0.34)
	t.sky_horizon = Color(0.40, 0.46, 0.52)
	t.sky_ground = Color(0.16, 0.20, 0.25)
	t.sky_haze = 0.12
	t.sun_color = Color(1.0, 0.84, 0.66)
	t.sun_energy = 1.35
	t.sun_rotation_deg = Vector3(-30.0, 128.0, 0.0)
	t.disc_color = t.sun_color
	t.disc_halo = 0.18
	t.ambient_sky_contribution = 0.30
	t.ambient_color = Color(0.39, 0.45, 0.54)
	t.ambient_energy = 0.95
	t.fog_color = Color(0.52, 0.61, 0.68)
	t.fog_density = 0.000012
	t.fog_sky_affect = 0.12
	t.fog_sun_scatter = 0.12
	t.fog_aerial_perspective = 0.40
	t.volume_anisotropy = 0.50
	t.sky_scatter_strength = 0.18
	t.exposure = 0.93
	t.glow_intensity = 0.23
	t.glow_bloom = 0.015
	t.glow_hdr_threshold = 1.40
	t.grade_contrast = 1.07
	t.grade_saturation = 0.96
	t.cloud_tints = [Color(0.78,0.81,0.84,0.30),Color(0.87,0.87,0.84,0.82),Color(0.78,0.83,0.90,0.22)]
	t.cloud_shades = [Color(0.43,0.50,0.61),Color(0.48,0.56,0.66),Color(0.58,0.66,0.77)]
	return t


## Preserve the unlit, overcast dead-city identity; no sun disc or stars are added.
static func oenbelli_cinematic() -> TimeOfDay:
	var t := dusk_overcast()
	t.sky_zenith = Color(0.12,0.145,0.18)
	t.sky_horizon = Color(0.36,0.31,0.27)
	t.sky_haze = 0.10
	t.sun_energy = 0.34
	t.ambient_color = Color(0.34,0.38,0.44)
	t.ambient_energy = 1.85
	t.fog_color = Color(0.30,0.32,0.35)
	t.fog_density = 0.000027
	t.fog_sky_affect = 0.18
	t.sky_scatter_strength = 0.035
	t.exposure = 0.98
	t.glow_intensity = 0.18
	t.glow_bloom = 0.02
	t.glow_hdr_threshold = 1.40
	t.grade_contrast = 1.04
	t.grade_saturation = 0.94
	t.cloud_tints = [Color(0.30,0.31,0.33,0.62),Color(0.37,0.38,0.40,0.90),Color(0.30,0.31,0.33,0.50)]
	t.cloud_shades = [Color(0.15,0.17,0.20),Color(0.19,0.21,0.25),Color(0.23,0.25,0.28)]
	return t


static func make(preset: int) -> TimeOfDay:
	match preset:
		Preset.DUSK:
			return dusk()
		Preset.NIGHT:
			return night()
	return day()


static func all_presets() -> Array[int]:
	return [Preset.DAY, Preset.DUSK, Preset.NIGHT]
