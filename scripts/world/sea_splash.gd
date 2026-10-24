class_name SeaSplash
extends Node3D
## **出水特效**：马夫蒂火箭从海里升起来的那一下 —— 一圈泡沫 + 一片滚滚的烟。
##
## ## 它解决什么
## 老板砍掉海上平台、要「**直接从海里面出来**」。只把箭体位置从水下搬到水上，
## 画面读起来是**穿模** —— 58 m 的箭从水面里凭空浮起来，而海面**一点反应都没有**。
## 海水被一枚几百吨的运载器顶开，至少要有两件东西：
##   · 一圈**向外扩张的泡沫环**（水面的反应，看得见"它从这儿出来的"）；
##   · 一片**从水面涌起来、向外翻滚的烟**（把箭推出水面的那几秒跟着走）。
##
## ## ★ 2026-09-30 第二版：**水柱 → 烟雾**（老板原话）
## > 「**发射时候的周围环绕的东西做成风压太丑陋了，还不如做成烟雾呢**」
##
## 第一版的第二件是**一根圆柱壳**（`SplashColumn`：半径 62~96 m、高 `alt+130` m、
## 与火箭**同 XZ**）。它在真机像素上的读数是灾难性的：
##
## | 图 | 读数（亮 = 亮度 > 40 的像素占比） | 看到的东西 |
## |---|---|---|
## | `02_breach_side` | 亮 **0.9416** / 均值 167.7 | 一根满屏纯白巨柱，火箭被整个吞掉 |
## | `04_rocket_side` | 亮 **1.0000** / 均值 **255.0** | **整幅纯白**，连箭体都拍不到 |
## | `05_rocket_top` | 亮 0.9869 / 均值 241.2 | 同上 |
##
## 三个成因缺一不可：**与箭同轴的圆柱**（必然包住箭）、**纯白**（夜里最亮的东西）、
## **不透明**（`ALPHA = alpha × band`，中段 band = 1）。⇒ 读起来不是水，
## 是一层**包住箭体的白壳** —— 老板说的"风压"。
##
## 这一版三处对症（细节见 `shaders/sea_smoke.gdshader` 头注）：
## 球体烟团（球心**不在轴线上**，落在环上） / 暗灰底色 + 引擎火烤亮 / 正面比软边。
##
## ## 它挂在哪、谁驱动
## 建在 `WorldBuilder._build_launch_splash()` 里（**只有太平洋图**），
## 挂在 `_terrain_root` 下 ⇒ 换图时跟着整张图一起被 `free()`。
## 每帧**由 `main.gd._tick_launch()` 显式驱动**（`update()`）——
## 与 `RocketFlame.update()` / `RocketBody.step()` 同一条规矩：
## **不写 `_process()`**，于是这一段能按固定 dt 在单测里复现。
##
## ⚠️ 因此 `main.gd` 那边**必须判 null**：换图之后 `world.launch_splash` 就是 null 了
##（换图发生在幕布后面，玩家看不见，但代码照样每帧跑）。
##
## ## 参数从哪来
## 两个自变量，**各自只跟一个量走**（这是刻意的，也是判据要分开钉的原因）：
##   · **几何 / 浓度** ← 箭底高度 `alt`：泡沫环半径、烟环半径、烟球大小、引擎火光；
##   · **透明度** ← 时间 `_t`（由 `update()` 的 `dt` 累加）：0.18 s 淡入、`RING_LIFE` 散尽。
## ⇒ 环会先没了烟还在、烟没了环还在，两件各自能单独关。
##
## ⚠️ **半径不能跟时间走** —— 第一版就是时间，实测在出水那一刻环已经涨到 798 m
##（`ALT_SHAPE = 3.64` 让火箭前 4.19 s 几乎不动，见 `RING_GROW_ALT` 那段完整推导）。
##
## ## ⚠️ 它是"看起来对"的近似，不是流体
## 没有碰撞、没有粒子、没有回落的液滴。两件网格 + 两个着色器，
## 存在的意义是"出水那一下别穿模"。做成真的 SPH 是另一个工程量级，
## 而这一段玩家会操控一枚 35 km/s 的箭，看它不超过 8 秒。

## 泡沫环的环带分段（越大越圆）。96 段在 800 m 半径上是 52 m 一段，够。
const RING_SEG := 96
## 泡沫环的内 / 外半径（**归一化**，真实半径靠节点 `scale`）。
## 内缘留 0.78 的空档，让"环"读得出是环 —— 中间那一片是箭体破开的水面。
const RING_IN := 0.78
const RING_OUT := 1.0

const RING_SHADER := "res://shaders/sea_splash.gdshader"
const SMOKE_SHADER := "res://shaders/sea_smoke.gdshader"

## 泡沫环的**真实**半径：从 `RING_R0` 扩到 `RING_R1`（米）。
## 扩到最大所需的**箭底高度**是 `RING_GROW_ALT`（米）—— 见下面那段"为什么不是时间"。
const RING_R0 := 110.0
const RING_R1 := 860.0
## ★★ 环扩到最大的**箭底高度**（米），**不是**秒。
##
## ## ⚠️ 为什么不能用时间（第一版就是时间，实测是错的）
## `LaunchScript.ALT_SHAPE = 3.64` 是一条**前段极缓**的曲线：点火后
## `t = 2 s` 箭底只到 −31.7 m、`t = 3 s` 到 −23.9 m、**`t = 4.19 s` 才越过海面**。
## 而环如果按时间扩散（当时 `RING_GROW = 6.5 s`），出水那一刻 `_t` 已经 4.19 s ⇒
## 环早就涨到 **798 / 860 m**。
## ⇒ 玩家看到的是：**火星一响，海面先自己炸开一圈 800 m 的白环，
##   然后干等 4 秒，才有一枚箭从环心里冒出来。** 环和箭是**两件不相干的事**。
##
## 改成按高度之后两者**锁在一起**：出水那一帧环从 `RING_R0`(110 m) 起，
## 箭底到 `RING_GROW_ALT`(260 m) 时环长到 `RING_R1`(860 m) —— 水是被箭顶开的。
##（`alt` 从 `rest_alt()` = −34 起算，所以"出水后 260 m"对应 `u` 上很小的一段，
##  实测约 1.6 s；这与人眼对"爆炸扩张"的期望是同一个量级。）
const RING_GROW_ALT := 260.0
## 泡沫环的存活时长（秒）。与半径那一档**故意分开**：
## 环**长到位之后还要挂一会儿再淡掉**，否则它像被"删掉"而不是"散掉"。
## ⚠️ 这一档仍然是**时间**：它管的是"水面上的痕迹过多久消失"，与箭在哪没关系
##（9.5 s 时箭已经 ~650 m 高、正在往云底去）。
const RING_LIFE := 9.5

# ------------------------------------------------------------ 烟

## 烟团数。132 团 ÷ 环周长（`SMOKE_R0` 40 m ⇒ 251 m）⇒ 起始每团占 1.9 m 弧长，
## 而球半径 22 m ⇒ **必然大幅互相重叠** ⇒ 读起来是一片连续的烟，不是一串球。
##
## ⚠️⚠️ 第一版是 **72 团 / 半径 40~105 m**，实测在 175 m 处**一屏全是烟**
##（`02_breach_side` 亮 0.9929 / 均值 204.8、`05_rocket_side` 亮 0.9983）——
## 一颗 105 m 半径的球在 175 m 外就是一面墙，72 颗重叠起来把整个画面填满，
## 箭体只剩中间一小条。⇒ **团数翻倍、个体缩小**才是"烟"。
const SMOKE_N := 132
## 烟团**球心所在环**的半径（米）：起始 / 长开后。
## ⚠️ `SMOKE_R0` 必须 **> 箭体半径（11.1 m）+ 一个球的半径**，否则球心落在轴上
## ⇒ 一堆球叠成一根**新的白柱**（那就是第一版被砍掉的东西，绕一圈又回来了）。
## 40 m 的环 + 22 m 的球半径 ⇒ 环带内缘 18 m、外缘 62 m：**箭体从烟里穿出来**。
const SMOKE_R0 := 40.0
const SMOKE_R1 := 215.0
## 烟团**半径**（米）：起始 / 长开后。`SphereMesh` 按 radius 1 建 ⇒ 这里是真实米数。
## ⚠️ 上限 58 m 是"远看还行 / 贴着看不成一堵墙"的那一档：发射段机位离箭体 80 m
##（`LAUNCH_OFFSET` 62/−52），58 m 的球在那个距离上占屏高的 ~60%，
## 五六个叠起来是一片能看穿的烟 —— 而 105 m 的球一个就占满整屏。
const SMOKE_S0 := 22.0
const SMOKE_S1 := 58.0
## 烟团**球心高度**（米）：起始 / 长开后。
## ⚠️ 别让它长太高：烟是从**水面**涌起来的，它该横向铺开、向上散，
## 而不是跟着箭一起爬（跟着爬就又变成"包住箭的筒"了）。
const SMOKE_H0 := 12.0
const SMOKE_H1 := 88.0
## 烟与环**共用同一个"长开"高度**（米）。同一个自变量 ⇒ 图上不会出现
## "环已经扩到最大、烟还没起来"这种两件脱钩的照片。
const SMOKE_GROW_ALT := RING_GROW_ALT
## 绕轴缓慢旋转（弧度 / 秒）。烟是活的：一圈静止的球看起来像围栏。
const SMOKE_SPIN := 0.12
## 逐团**向外飘**的速率（米 / 秒）：越浓的团飘得越慢（`drift` 因子乘它）。
const SMOKE_OUT := 5.5
## 上下起伏（米 / 秒）—— 让烟"滚"起来，而不是整片同步平移。
const SMOKE_BOB := 2.2

## ★★ 烟**从点火后多少秒才开始出现**（秒）。老板 2026-09-30：
## > 「**烟雾要在发射后 4s 再渐变生成**」
##
## ## 为什么 4 s 这个数是对的（不是随手取的）
## `LaunchScript.ALT_SHAPE = 3.64` 是一条**前段极缓**的曲线：点火后箭底在水下
## 一点点往上蹭，**`t = 4.19 s` 才越过海面**（反解见 `suite_rocket_launch.t_of()`：
## `60 × (34/550 034)^(1/3.64) = 4.19 s`）。
## 4 s 之前箭体整个还在水下 ⇒ 那时候冒烟等于"水底下的火在冒烟"，物理上就是错的；
## 先前的版本正是这样：烟在 `t = 0.18 s` 就满浓度顶上来，画面是"海面自己炸开一团烟，
## 而箭还看不见"。
##
## ⚠️ 它**必须 ≤ 破水时刻**（`BREACH_ALT` 对应的时间），否则箭都出水了烟还没起，
## 那一段就变成"没有烟"（`suite_rocket_launch` 有一条断言把这两个数对起来）。
const SMOKE_DELAY := 4.0
## 过了 `SMOKE_DELAY` 之后用多少秒**渐变**到满浓度（老板：「渐变生成」）。
## 取 0 就是"啪一下整片出现"—— 读起来像**贴图切换**，而不是烟涌上来。
const SMOKE_RAMP := 2.0

## 烟散尽的高度区间（米）。⚠️ 必须在爬到云底（2 800 m）**之前**散干净，
## 否则玩家在云里还看着脚下一片烟（那一段该由云幕接管）。
const SMOKE_FADE_LO := 420.0
const SMOKE_FADE_HI := 1250.0
## 引擎火光冷掉的高度（米）：`glow = 1 - alt / 这个数`。
## 夜里从水里顶出来的烟，底下被尾焰烤成暖色 —— 那一眼就是"有动力"。
const SMOKE_GLOW_ALT := 700.0

var _ring: MeshInstance3D
var _smoke: MultiMeshInstance3D
var _ring_mat: ShaderMaterial
var _smoke_mat: ShaderMaterial
var _mm: MultiMesh

## 逐团的确定性参数，`_init()` 里按固定种子建一次（不每帧摇 ⇒ 可复现）。
## ⚠️ 分成 6 条平行数组而不是一个 `Array[Dictionary]`：字典取值是 `Variant`，
## 每帧 72 次 × 6 个字段的装箱 + 类型推断，在这一段（每帧都在跑）不划算。
var _ang := PackedFloat32Array()    ## 起始方位角（弧度）
var _radf := PackedFloat32Array()   ## 环半径倍率（0.72 .. 1.32）
var _szf := PackedFloat32Array()    ## 球半径倍率（0.72 .. 1.45）
var _hf := PackedFloat32Array()     ## 高度倍率（0.30 .. 1.55）
var _drift := PackedFloat32Array()  ## 外飘倍率（0.40 .. 1.60）
var _ph := PackedFloat32Array()     ## 起伏相位（0 .. TAU）

## 点火之后过了多少秒。`update()` 累加；`begin()` 清零。
var _t := 0.0
## 是否正在出水。false ⇒ 两件都 `visible = false`（一个像素都不画）。
var active := false
## 自证清白的读数：上一次 `update()` 用到的两个 alpha（探针与测试直接读）。
var ring_alpha := 0.0
var smoke_alpha := 0.0


func _init() -> void:
	name = "SeaSplash"
	_ring_mat = _make_ring_mat()
	_ring = _mk_mesh("SplashRing", _build_ring(), _ring_mat)
	_smoke_mat = _make_smoke_mat()
	_smoke = _mk_smoke(_smoke_mat)
	visible = false


func _make_ring_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	if ResourceLoader.exists(RING_SHADER):
		m.shader = load(RING_SHADER)
	else:
		# ⚠️ 必须喊：静默失败的表现是"出水那一下水面毫无反应"，
		# 而那**正好就是**这特效没做出来的样子 —— 两者分不清。
		push_error("泡沫环着色器载不到（%s）⇒ 出水那一下海面不会有反应" % RING_SHADER)
	m.set_shader_parameter("alpha", 0.0)
	m.set_shader_parameter("scale", 9.0)
	m.set_shader_parameter("churn", 2.4)
	return m


func _make_smoke_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	if ResourceLoader.exists(SMOKE_SHADER):
		m.shader = load(SMOKE_SHADER)
	else:
		push_error("烟雾着色器载不到（%s）⇒ 出水那一下只剩泡沫环，没有烟" % SMOKE_SHADER)
	m.set_shader_parameter("alpha", 0.0)
	m.set_shader_parameter("glow", 0.0)
	m.set_shader_parameter("dens", 1.0)
	m.set_shader_parameter("scale", 2.2)
	return m


func _mk_mesh(n: String, mesh: Mesh, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	return mi


## 烟：一个 `MultiMeshInstance3D`，网格是**单位球**（radius 1 / height 2）。
##
## ⚠️ 为什么是球而不是"绕世界 Y 转的盘"（云用的那种）：
## 云在几百米外、只从下方看；烟在相机**旁边**（发射段机位离箭体 66 m），
## 而且四张判据图里既有平视也有**正俯视** —— 盘在俯视时会退化成一条线。
## 球的代价只有顶点数（16×10 段 ≈ 320 个三角 × 132 团 ≈ 42 k 三角，可以忽略）。
##
## ⚠️ 8×6 段实测**能看出多边形棱角**：烟团被引擎火照亮半边时，暗面上会出现
## 明显的三角形分界（一块块梯形），一眼就不是烟。16×10 是"看不出棱"的下限，
## 且 132 团 × 320 三角 = 42 k 三角仍在噪声里（云垛单单一座就 1135 片）。
func _mk_smoke(mat: ShaderMaterial) -> MultiMeshInstance3D:
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 16
	sph.rings = 10
	sph.material = mat

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = sph
	_mm.instance_count = SMOKE_N

	# ---- 逐团参数：固定种子 ⇒ 每次进这一关的烟长得一模一样（可复现、可对比图） ----
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260930
	_ang.resize(SMOKE_N)
	_radf.resize(SMOKE_N)
	_szf.resize(SMOKE_N)
	_hf.resize(SMOKE_N)
	_drift.resize(SMOKE_N)
	_ph.resize(SMOKE_N)
	for i in SMOKE_N:
		# 均匀铺一圈再加抖动：纯随机会在环上留大空档（一片烟忽然断掉）
		_ang[i] = TAU * float(i) / float(SMOKE_N) + rng.randf_range(-0.055, 0.055)
		_radf[i] = rng.randf_range(0.72, 1.32)
		_szf[i] = rng.randf_range(0.72, 1.45)
		_hf[i] = rng.randf_range(0.30, 1.55)
		_drift[i] = rng.randf_range(0.40, 1.60)
		_ph[i] = rng.randf() * TAU

	var inst := MultiMeshInstance3D.new()
	inst.name = "SplashSmoke"
	inst.multimesh = _mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(inst)
	return inst


## 泡沫环网格：**躺在海面上**（y = 0）的一张圆环。
##
## ⚠️ 半径是**归一化**的（外缘 = 1.0），真实半径由节点的 `scale.xz` 给。
## 于是"涨到多大"是一个每帧可写的小数字，不需要重建网格。
func _build_ring() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 平面不需要平滑组，但法线必须显式给 **世界向上** ——
	# shader 是 `unshaded`，法线其实不参与着色；给它是为了将来谁把
	# `unshaded` 摘掉时，这一片不会因为法线是随机的而变成一块黑。
	for i in RING_SEG:
		var a0 := TAU * float(i) / float(RING_SEG)
		var a1 := TAU * float(i + 1) / float(RING_SEG)
		var u0 := float(i) / float(RING_SEG)
		var u1 := float(i + 1) / float(RING_SEG)
		var c0 := Vector3(cos(a0), 0.0, sin(a0))
		var c1 := Vector3(cos(a1), 0.0, sin(a1))
		var vi0 := c0 * RING_IN
		var vi1 := c1 * RING_IN
		var vo0 := c0 * RING_OUT
		var vo1 := c1 * RING_OUT
		# UV.y：0 = 内缘、1 = 外缘（shader 拿它当"半径"用）
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u0, 0.0))
		st.add_vertex(vi0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u0, 1.0))
		st.add_vertex(vo0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(vi1)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(vi1)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u0, 1.0))
		st.add_vertex(vo0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u1, 1.0))
		st.add_vertex(vo1)
	return st.commit()


# ============================================================ 驱动

## 点火：从头开始这一段（`_t` 归零、两件都摆到位）。
## ⚠️ 幂等**不是**要求：重复点火就是重新出水（调参时反复播同一段）。
##
## ⚠️ 这里**不写 `visible = true`**：紧随其后的 `_apply()` 会按 `alpha` 重算它，
## 写了也立刻被覆盖 —— 而它读起来像"点火即显形"，是错的：
## 两件都有 0.18 s 淡入（`fade_in = _t / 0.18`）⇒ 点火那一帧 `alpha` 还是 0，
## 于是 `visible` 也是 false（**本来就没东西可画**，不是 bug）。
func begin() -> void:
	_t = 0.0
	active = true
	_apply(LaunchScript.rest_alt())


## 收工（`main.gd` 在发射段结束时调）。
func end() -> void:
	active = false
	ring_alpha = 0.0
	smoke_alpha = 0.0
	_ring_mat.set_shader_parameter("alpha", 0.0)
	_smoke_mat.set_shader_parameter("alpha", 0.0)
	visible = false


## 推一帧。[param alt] = **箭底的世界高度**（米，可能为负 —— 出水前它就在水下）。
## [param dt] 秒。两个都由调用方给，本类不读时钟（见类头注）。
func update(alt: float, dt: float) -> void:
	if not active:
		return
	# ⚠️ `dt` 夹一下：切窗口 / 卡一帧之后 `dt` 可能是 0.2 s 量级，
	# 那会让泡沫环一帧跳到最大半径，"炸开"这个动作就没了。
	_t += clampf(dt, 0.0, 1.0 / 20.0)
	_apply(alt)


## 泡沫环当前**应有**的半径（米，纯函数）。`alt` = 箭底高度。
##
## ⚠️ 抽成纯函数是为了**能判**：无头环境下 `MultiMesh.get_instance_transform()`
## 一律回单位变换（`instance_count` 却是准的）⇒ 烟团的位置**只能在带窗口探针里量**。
## 于是判据分两层：**方位/半径**这一类可解析的东西钉这个纯函数（无头），
## **真几何**（云底多高、烟有没有堆在轴上）归 `tools/_rocket_shots.gd`（带窗口）。
func ring_radius_at(alt: float) -> float:
	var g := clampf((alt - LaunchScript.rest_alt()) / RING_GROW_ALT, 0.0, 1.0)
	# 缓出：出水那一下最快，之后越来越慢（水面被推开后阻力上来）
	var e := 1.0 - pow(1.0 - g, 2.4)
	return lerpf(RING_R0, RING_R1, e)


## 烟环当前**应有**的半径（米，纯函数）。
##
## 指数 1.6 比泡沫环的 2.4 小 ⇒ 烟**长得更快**：水先被顶开（环），
## 烟随后才涌上来铺开。两者的先后差就是"水花 → 烟"那个读法。
func smoke_ring_radius_at(alt: float) -> float:
	var g := clampf((alt - LaunchScript.rest_alt()) / SMOKE_GROW_ALT, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - g, 1.6)
	return lerpf(SMOKE_R0, SMOKE_R1, e)


## 第 `i` 团烟在 `(alt, t)` 时刻**应有**的变换（纯函数，无头套件直接钉它）。
##
## ## 为什么必须是纯函数
## `_apply()` 每帧写 72 个实例变换，而那些变换在**无头环境里读不回来**
##（`MultiMesh.get_instance_transform()` 回单位变换）⇒ 若把算式写在 `_apply()` 里，
## "烟有没有堆在轴上""环有没有跟着长开"这两条**只能靠肉眼看图**。
## 抽出来之后套件能直接断言"球心离轴 ≥ `SMOKE_R0 × 0.72`"这种会变红的判据。
func puff_transform(i: int, alt: float, t: float) -> Transform3D:
	var k := clampi(i, 0, SMOKE_N - 1)
	var g := clampf((alt - LaunchScript.rest_alt()) / SMOKE_GROW_ALT, 0.0, 1.0)
	var ge := 1.0 - pow(1.0 - g, 1.6)
	# 球心绕轴缓慢转 + 逐团向外飘（越浓的团飘得越慢）
	var ang := _ang[k] + SMOKE_SPIN * t * _drift[k]
	var rad := smoke_ring_radius_at(alt) * _radf[k] + SMOKE_OUT * t * _drift[k]
	var s := lerpf(SMOKE_S0, SMOKE_S1, ge) * _szf[k]
	var y := lerpf(SMOKE_H0, SMOKE_H1, ge) * _hf[k] \
		+ sin(t * 0.9 + _ph[k]) * SMOKE_BOB * _drift[k]
	# ⚠️ 球底不许穿到水面以下：烟是从水面**涌起来**的，不是从水里浮上来的。
	# 球绕三轴等比缩放 ⇒ 竖直半高就是 `s`。
	y = maxf(y, s * 0.55)
	var pos := Vector3(cos(ang) * rad, y, sin(ang) * rad)
	return Transform3D(Basis.from_scale(Vector3(s, s, s)), pos)


## 烟的时间闸门（纯函数，`0` = 还没起 / `1` = 满浓度）。
##
## ## ⚠️ 为什么必须抽成纯函数
## 烟 alpha 现在是**三个因子**的乘积（淡入 × 时间闸门 × 高度剖面），
## 而无头套件里只推**高度**是推不出 alpha 的 ——
## 2026-09-30 加这道闸门时，套件里 4 条 `smoke_alpha > 0.9` 一起变红，
## 根因就是它们只喂高度、`_t` 才 0.4 s。抽出来之后，判据可以直接钉"几点起、几点满"。
##
## 形状：`SMOKE_DELAY` 之前恒 0；`[DELAY, DELAY + RAMP]` 上一条 `smoothstep`
##（两端导数都是 0 ⇒ 出现和到位都不"顿"）；之后恒 1。
## ⚠️ 声明成 **`static`**：套件里按"纯函数"直接 `SeaSplash.smoke_gate_at(t)` 调，
## 而 GDScript **不许在类上调用非静态方法**（会报 `Cannot call non-static function`）。
static func smoke_gate_at(t: float) -> float:
	return smoothstep(SMOKE_DELAY, SMOKE_DELAY + SMOKE_RAMP, t)


func _apply(alt: float) -> void:
	# 淡入很快（0.18 s），淡出占后 45% 的寿命
	var fade_in := clampf(_t / 0.18, 0.0, 1.0)
	var fade_out := 1.0 - smoothstep(RING_LIFE * 0.55, RING_LIFE, _t)

	# ---- 泡沫环：半径跟**高度**走（见 `RING_GROW_ALT` 那段推导）----
	var g := clampf((alt - LaunchScript.rest_alt()) / RING_GROW_ALT, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - g, 2.4)
	var r := ring_radius_at(alt)
	_ring.scale = Vector3(r, 1.0, r)
	ring_alpha = fade_in * fade_out
	# ⚠️ 泡沫环的浓度**随半径变淡**：同样的 alpha 铺到 860 m 半径上会是一圈
	# 又薄又长的白带，读起来像"一个环状贴图"而不是泡沫散开。
	_ring_mat.set_shader_parameter("alpha", ring_alpha * lerpf(0.92, 0.46, e))

	# ---- 烟：球心铺在环上、向外滚，浓度按**高度**退 ----
	var glow := clampf(1.0 - alt / SMOKE_GLOW_ALT, 0.0, 1.0)
	# 底面最浓、越往上越稀（`dens` 与 `alpha` 分开：那是"有没有"，这是"多厚"）
	var dens := lerpf(1.0, 0.55, clampf(alt / SMOKE_FADE_HI, 0.0, 1.0))
	# ★★ 烟的 alpha 现在是**三个因子**的乘积：
	#    淡入（时间，0.18 s）× **时间闸门**（点火后 4 s 才起，老板 2026-09-30）
	#    × 高度剖面（升上去散掉）。
	# ⚠️ 闸门这一项**不能省**：少了它烟在 `t = 0.18 s` 就满浓度顶上来，
	# 而那时箭体整个还在水下（`t = 4.19 s` 才破水）——
	# 画面读起来是"海面自己炸出一团烟，而箭还看不见"。
	smoke_alpha = fade_in * smoke_gate_at(_t) \
		* (1.0 - smoothstep(SMOKE_FADE_LO, SMOKE_FADE_HI, alt))
	for i in SMOKE_N:
		_mm.set_instance_transform(i, puff_transform(i, alt, _t))
	_smoke_mat.set_shader_parameter("alpha", smoke_alpha)
	_smoke_mat.set_shader_parameter("glow", glow)
	_smoke_mat.set_shader_parameter("dens", dens)

	visible = ring_alpha > 0.002 or smoke_alpha > 0.002
	# 两件各自还要能单独关 —— 环散去之后烟还在，是常态
	_ring.visible = ring_alpha > 0.002
	_smoke.visible = smoke_alpha > 0.002
