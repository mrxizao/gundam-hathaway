class_name MissileRibbon
extends MeshInstance3D
## 浮游飞弹的**连续烟带**（轮 40）。
##
## ## 需求原话
## 「把浮游飞弹的飞行轨迹加长，现在的浮游飞弹的拖尾太短了，拖尾要和飞行轨迹一样长」。
##
## ## 为什么必须是一条**带**，而不是把粒子柱拉长
##
## 粒子尾迹的账是死的（这一条 `FX.missile_trail()` 里已经写明）：
##
##     柱长 = 世界速度 × lifetime          间距 = 柱长 ÷ amount
##
## 实测（`tools/probe_missile_ballistic.gd`）：
##   · 2 km 贴身交战  ⇒ 弹道 **3052.9 m** / 1.98 s
##   · 12 km 交战（工程自己的靶机基准距离 11960 m）⇒ 弹道 **16651.7 m** / 5.35 s
##
## 要让**粒子柱**盖住 16.7 km 且不出现空隙（间距 ≤ 球出生直径 9.95 m），
## 一次扳机 3 发就要 **约 5200 颗粒子** —— 而全弹发射 100 发才 2800。
## 那是量级之外的事，往 `amount` 上加料解决不了。
##
## 带子**没有"间距"这个量**：它是沿弹道连成的一条面，长度只取决于**采样点数**，
## 与浓度无关，也与长度无关（16.7 km 与 3 km 的顶点数一样，只要采样间距不变）。
##
## ## 分工（用户 2026-09-28 选定：「烟带 + 烟团都做」）
##   · **本类**：负责**长度** —— 铺满整条弹道，一直连到发射点；
##   · `FX.missile_trail()` 的粒子球：负责近端的**体积感**（那是轮 38 刚修好的东西，
##     一条平面带子给不出来），照旧挂在弹身上。
## 两者叠在同一根弹道上：带子是"底"，球是"厚"。
##
## ## 世界空间
## `top_level = true`：节点不继承机体的位移/旋转，顶点直接用**世界坐标**。
## **挂点是 `projectile_container`（弹的父容器），不是弹本身** —— 否则弹一命中
## （`queue_free`）那条已经铺了十几公里的烟会跟着一起没，用户就是看不到它才提的这条需求。
##
## ## 生命周期
##   · `push(tip, delta)`：按采样间距推入新点，带子随弹道生长；
##   · `release()`：弹没了 —— 停止推进，整条原地淡出（**不是**从尾端收回：
##     烟不会跟着弹跑），淡完自毁；
##   · 自己 `_process` 驱动淡出，所以弹死了它也能独立走完。
##
## 本类不读输入、不依赖物理：无头测试可以直接 new 出来喂点、数顶点。

## 两个采样点的间距（米）。弹的峰值速度 4062 m/s ⇒ 每帧 67.7 m，
## 所以这里每 2.3 帧左右落一个点。
##
## ★ 轮 63-12（需求原话：「导弹尾迹的连续性调到现在的 78%」）：**120 → 153.8**。
## 取法 = `120 ÷ 0.78 = 153.846…`，保留一位 ⇒ **153.8**
##（实际比值 `120 / 153.8 = 0.7802` ⇒ 连续性 −21.98% ≈ −22%）。
## 采样密度 ×0.78 ⇒ **折线的段数/顶点数同步 −22%**。
##
## ⚠️ **它不属于「体积」那一轴**：`SPACING` 不参与宽度（`HALF_W`）、不参与长度
##（折线首尾点都保留、`covered_m()` 仍是 100% 弹道），只决定**折线分段的粗细**。
## 因此 D5 那条「体积不变」清单从此只含**四项**（`HALF_W` / `scale_min` /
## `scale_max` / 发射盒长）—— 判据见 `suite_smoke_density` §⑥。
##
## ⚠️ **改这一处就要把它参与的算术全部重算**：
##   · 转弯偏差：转弯半径 = `v / ω = 4062 / 2.55 ≈ 1593 m` ⇒ 偏差 = `弦² / (8 × 1593)`。
##     ⚠️ **真实弦长不是 `SPACING`** —— `push()` 的门是 `≥ SPACING`，而它每**物理帧**
##     才被调一次 ⇒ 弦长落在 `[SPACING, SPACING + 每帧位移]` 里。两条都算：
##       · 理想（弦 = 间距）**153.8 m** ⇒ 偏 **1.86 m**（改动前 120 m 是 1.13 m）
##       · 最坏（弦 = 间距 + 物理帧位移 67.7 m = **221.5 m**）⇒ 偏 **3.85 m**
##     两条都 < 半宽 6.0 m ⇒ 转弯处仍看不出折角。⚠️ 只按理想值算会把上界报小一倍。
##     （两条都由 `suite_smoke_density` §⑥ 钉住，改大 `SPACING` 先红最坏那条。）
##   · 满量程点数：`14 s × 4062 / 153.8 ≈ **370 点**` < `MAX_POINTS` 512
##     ⇒ 余量反而比改动前（约 474 点）更大。
const SPACING := 153.8
## 采样点上限（**不含**实时末端点，见 `_tip`）。
## 弹自毁前最多飞 14 s（`Missile.lifetime`）⇒ 满量程 14 × 4062 / 120 ≈ **474 点**。
## ⚠️ 原来取 400，那在长距离弹道上会**真的触发丢点** —— 而丢的是**最旧**的点，
## 也就是**发射点那一端**（74 × 120 = 8880 m 一整段凭空消失），与本条需求相反。
## 提到 512（比满量程多 8%）：正常飞行一辈子碰不到，丢点只留作绝对兜底。
const MAX_POINTS := 512
## 带子的半宽（米）。粒子球出生直径 3.74~9.95 m（`1.8 × 3.2~8.5 × 0.65`）、
## 随龄 ×1.3，取 6.0 与它相当 ——
## 带子略窄于"最大的那批球"，两者叠起来才不会出现"带子比球还粗"的怪相。
const HALF_W := 6.0
## `release()` 之后多久淡完（秒）。烟要"散"，所以给足时间，而且不能瞬灭。
const FADE_TIME := 1.6
## 头部（弹这一端）的顶点 alpha。**不能到 1.0**：它是叠在实时世界上的半透明面，
## 满值会在烟带正中压出一条硬边的实心色块。
## ★ 轮 63-9 · D5：0.55 → **0.44**（−20%）。
## ★ 轮 63-12（需求原话：「导弹尾迹的透明度调为现在的 70%」）：0.44 → **0.308**
##（`0.44 × 0.70 = 0.308`，精确值、无舍入）。
##
## ⚠️ 为什么（仍然）只降**烟带层**、不碰粒子层（设计文档 P10，本轮沿用）：
## 粒子色带起点 alpha `0.88 × 0.7 = 0.616 < 0.84` 会**撞红**
## `suite_missile_smoke.gd` 那条旧需求「色带起点加浓 —— 弹幕里烟读得出来」。
## 烟带层则**没有任何断言读它**（已 grep 全 `tests/`），所以这一半是零冲突的。
##
## 它与粒子层**乘在一起**才决定屏幕上那层白烟的浓度 ⇒ 白烟整体淡 30%。
## 真机像素 A/B 由 `tools/_r63_9_d5_shot.tscn` 出（烟带是确定性几何，
## 两次跑的像素差只可能来自 alpha；粒子层是随机场，做不出可复现的 A/B）。
const ALPHA := 0.308
## ---- 渲染抽稀（轮 41）----
##
## 段数只影响**画出来的密度**，与长度无关（首尾点一定保留，见 `_render_chain()`）。
## 阈值是算出来的，不是拍的：带子全宽 12 m（`HALF_W × 2`），在 1600×1000、
## 垂直视角 60° 的画布上，距离 d 处一米约合 `11460 / d` 像素 ——
##   · 2500 m 处 12 m ⇒ **4.6 px**（近端，不能抽）
##   · 7000 m 处 12 m ⇒ **1.6 px**（已经细成一根线）
## 而转弯半径 1593 m 下，弦长 240 m 的折线只偏离圆弧 4.5 m < 半宽 6 m，看不出来。
const LOD_NEAR_M := 2500.0
const LOD_FAR_M := 7000.0

## ---- 近距离淡出（★63-21）----
##
## ## 需求原话（两段，第二段是关键）
##   「离镜头越近，透明度就越高，离镜头只有 3 m 的时候透明度彻底 100%」
##   「是镜头内的**部分**透明哦，不是整条透明」
##
## ## ⚠️ 引擎语义是**实测**出来的，不是照文档写的（`tools/_r63_21_fade_probe.tscn`）
## `BaseMaterial3D` 上有一套 `distance_fade_*`，真机像素测出来的公式是
##
##     alpha = smoothstep(min, max, d)      # 平滑起步 + 平滑收尾，**不是**线性 clamp
##
## 也就是 **`min` = "开始出现"的距离、`max` = "完全恢复"的距离**。
## ⚠️ 分辨 smoothstep 与 `clamp((d − min) / (max − min))` 要靠**中段**（两头一样）：
##
##     d(m)       2      5      10     20     30     45     60
##     实测    0.000  0.005  0.043  0.211  0.461  0.814  1.000
##     smooth  0.000  0.0036 0.0415 0.2138 0.4606 0.8287 1.000   ← 残差 ≤ 1.5%
##     线性    0.000  0.0351 0.1228 0.2982 0.4737 0.7368 1.000   ← 残差 ≤ 8.7%
##     （十个距离、角尺寸恒定、比值取**线性域**；`min=3 / max=60` = **本常量**）
##
## 反着给（`min=60 / max=3`）实测是 2 m→1.000 … 60 m→0.000：
## ⚠️ **那得到的不是「近处淡」，是"远处全没"** —— 正是用户否掉的"整条透明"那一路。
## 两个锚点**必须按自然顺序**写（近端 < 远端）。
##
## ## ⚠️ 必须 `PIXEL_ALPHA`（逐片元），不能按节点原点
## 一条带子可以横跨 16 km：只有**逐片元**才能让近处那一段淡、远处那一段照旧 ——
## 这就是「是镜头内的**部分**透明，不是整条透明」。
## 若改用按节点原点的做法（`GeometryInstance3D.visibility_range_begin` 那一路），
## 整条带子会随节点一起消失。
##
## ## 与 `ALPHA` 的关系
## 它是**外加**在 `ALPHA × _along() × global_a` 之上的一个乘子，
## **不改**任何既有的浓淡结构（头浓尾淡 / 边缘羽化 / 释放后淡出都不动）。
## 距离 ≥ `FADE_FULL_M` 时这个乘子恒为 1 ⇒ 远处画面**逐位同改动前**。
const FADE_NEAR_M := 3.0
## 距相机 **≥ 此值** ⇒ 距离淡出乘子恢复为 1（远处画面与改动前逐位一致）。
const FADE_FULL_M := 60.0

var _pts := PackedVector3Array()
## 弹的**当前**世界坐标（`push()` 每帧写）。**不是采样点** —— 是带子的**实时末端**。
## ⚠️ 没有它的话，带子头端永远落后弹最多一个采样间隔（`SPACING` 153.8 m，
## 加上每帧位移 57.3 m ⇒ 最坏 **~211 m** ⇒ 3 km 弹道上短 6.9%，16.7 km 上短 1.3%）。
## 而需求要的是**一样长**。
## `release()` 之后不再更新 ⇒ 淡出时形状冻结（烟不跟着弹跑）。
var _tip := Vector3()
var _imm: ArrayMesh
var _last_camera_position := Vector3(INF, INF, INF)
var _released := false
var _fade := 0.0
## 「折线变了、网格还没跟上」。
##
## ⚠️ 存在的理由（轮 41 实测）：`_physics_process` 每帧可能跑**多个子步**
##（`Engine.max_physics_steps_per_frame` = 8，帧一慢就顶满），而画面**每帧只画一次**。
## 原来在每个子步里重建 ⇒ 每渲染帧重建 8 次。现在这里只标脏，
## 由 `_process()`（每渲染帧一次、且在物理步**之后**）统一重建。
var _dirty := false
## 上一次重建**实际画出去**的四边形数（抽稀之后）。
## 测试与探针用它区分「折线有多少点」和「画了多少段」——这两件事抽稀之后不再相等。
var _quads := 0


func _init() -> void:
	name = "MissileRibbon"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_imm = ArrayMesh.new()
	mesh = _imm
	# ⚠️ 材质**静态共享**（轮 41）：原来每条烟带 `new` 一个，36 - 100 条就是
	# 36 - 100 份一模一样的 `StandardMaterial3D`。几何没法合批（每条带的
	# `ImmediateMesh` 都是独立的），但材质没有理由各存一份。
	var mat := _shared_mat()
	material_override = mat


## 烟带的共享材质（`_init()` 里所有实例共用这一份）。
static var _mat_cache: StandardMaterial3D = null


static func _shared_mat() -> StandardMaterial3D:
	if _mat_cache != null:
		return _mat_cache
	var mat := StandardMaterial3D.new()
	# **unshaded**：与粒子球那份（`_trail_smoke_mat()`，受光）不同，这里是被迫的 ——
	# `ImmediateMesh` 不设法线（法线全零），受光材质会把它算成一整片黑。
	# 所以带子靠**顶点色 + 边缘羽化纹理**给形状，不靠光照。
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 双面：带子"面向相机"只是个意图，相机绕到侧面时不该整条消失。
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _edge_mask()
	mat.disable_receive_shadows = true
	# "烟不是火"：普通 alpha，**不加色**（与 `_trail_smoke_mat()` 同一条分界）。
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	# ---- 近距离淡出（★63-21）：镜头贴进烟里时，**贴着镜头那一段**淡掉 ----
	#
	# ⚠️ 逐片元（`PIXEL_ALPHA`）：一条 16 km 的带子上近处淡、远处照旧
	# ⇒ 就是需求里的「是镜头内的**部分**透明，不是整条透明」。
	# ⚠️ 两个锚点**必须按自然顺序**（近端 < 远端）—— 反着给实测得到的是"远处全没"。
	# 公式与真机读数见本文件 `FADE_NEAR_M` 那一段。
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = FADE_NEAR_M
	mat.distance_fade_max_distance = FADE_FULL_M
	_mat_cache = mat
	return _mat_cache


## 横向的"中间实、两侧透"遮罩。一条纯色四边形在屏幕上读起来是**硬边的塑料片**；
## 让宽度方向的两端淡到 0，才有"一团烟"的软边（这和 `_soft_smoke_mat()` 用径向
## 渐变遮罩是同一个意图，只是这里是**横向**而不是径向）。
static var _edge_cache: GradientTexture2D = null


static func _edge_mask() -> GradientTexture2D:
	if _edge_cache != null:
		return _edge_cache
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.30, Color(1, 1, 1, 0.92))
	g.add_point(0.70, Color(1, 1, 1, 0.92))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 4
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0)
	_edge_cache = t
	return _edge_cache


## **历史采样点数**（不含实时末端点）。测试用：喂点应增长；顶点数上限也看它。
func point_count() -> int:
	return _pts.size()


## 折线**有效**点数 = 历史采样点 + （端点不与末采样点重合时的）实时末端点。
func _poly_count() -> int:
	var n := _pts.size()
	if n == 0:
		return 0
	if _tip.distance_to(_pts[n - 1]) > 0.5:
		return n + 1
	return n


func _poly_at(i: int) -> Vector3:
	return _tip if i >= _pts.size() else _pts[i]


## 带子**实际铺了多长**（相邻点距离累加 = 折线长度）。
## ⚠️ **这才是「拖尾和弹道一样长」的直接读数** —— `point_count() × SPACING` 只是
## **下界**（真实段长落在 `[SPACING, SPACING + 每帧位移]` 之间，弹速 3439 m/s 时
## 每帧 57 m ⇒ 段长最多 211 m）。⚠️ 这个下界**随 `SPACING` 变大而收紧** ——
## 轮 63-12 把它从 120 改到 153.8 之后，"每帧位移"那截余量占的比例小了，
## 用下界算的覆盖率更接近真值。读数**一律**用本函数。
func covered_m() -> float:
	var n := _poly_count()
	var s := 0.0
	for i in range(1, n):
		s += _poly_at(i - 1).distance_to(_poly_at(i))
	return s


func is_released() -> bool:
	return _released


## 上一次重建画出去的段数（**抽稀之后**）。
func drawn_segments() -> int:
	return _quads


## 距相机 `dist` 米处的抽稀步长（静态纯函数 ⇒ 可被测试直接钉住）。
static func _lod_stride(dist: float) -> int:
	if dist <= LOD_NEAR_M:
		return 1
	if dist <= LOD_FAR_M:
		return 2
	return 4


## 每物理帧调一次。`tip` = 弹的**世界坐标**。
## `delta` 目前不用（采样按**距离**不按时间）—— 留着是为了调用点不必再改签名。
func push(tip: Vector3, delta: float) -> void:
	if _released:
		return
	_tip = tip
	if _pts.is_empty():
		# ⚠️ 只插**一个**点，**不要**插两个相同坐标的"零长度段"：
		# 那样 `_pts.size()` 一上来就是 2，能骗过下面 `n < 2` 的早退，
		# 但那一整段的 `seg.length()` 是 0、被 `continue` 掉 ⇒ **一个顶点都没有**
		# 就 `surface_end()` ⇒ 每个物理帧刷一行
		# `No vertices were added, surface can't be created`（探针实测抓到）。
		# 插一个点则走 `n < 2` 干净早退，等真走出一段（≥ SPACING）再起带。
		_pts.append(tip)
	elif _pts[_pts.size() - 1].distance_to(tip) >= SPACING:
		_pts.append(tip)
		while _pts.size() > MAX_POINTS:
			_pts.remove_at(0)
	# ⚠️ **只标脏，不在这里重建** —— 本函数是从 `Missile._physics_process()` 调的，
	# 而一帧可能跑 8 个子步（见 `_dirty` 那段）。实测：挂在子步上的话
	# 「编队战 14 台 + 36 发弹」是 127 ms/帧，`--no-ribbon` 只要 32 ms。
	_dirty = true


## 弹没了 —— 停止推进，开始原地淡出。**幂等**（`_detonate` 可能被两条出口调到）。
func release() -> void:
	_released = true


## **每渲染帧至多重建一次**（这是本类性能的全部要点，见 `_dirty`）。
##
## ⚠️ 顺序是实测过的：Godot 4.7 一轮迭代 = 物理子步 → idle `_process`，
## 所以这里读到的 `_tip` 已经是本帧最后一个子步的最新值 ⇒ **头端零滞后**。
## 反过来说，重建**绝不能**挪回 `_physics_process`（那会乘上子步数）。
var _budget_elapsed := 0.0

func _process(delta: float) -> void:
	_budget_elapsed += delta
	if _released:
		_fade += delta / maxf(FADE_TIME, 0.05)
		if _fade >= 1.0:
			queue_free()
			return
		# Fade the static mesh on the rendering server instead of resubmitting every vertex.
		transparency = clampf(_fade, 0.0, 1.0)
		var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
		if camera != null and not camera.global_position.is_equal_approx(_last_camera_position):
			_dirty = true
	if _dirty and (Settings.effects_quality>0 or _budget_elapsed >= 1.0/30.0):
		_budget_elapsed = 0.0
		_dirty = false
		rebuild()


## 重建时**实际遍历**的点下标链（抽稀后的折线）。
##
## ⚠️ 三条不变量：
##   ① `out[0] == 0`、且最后一跳强制落到 `n-1` ⇒ **首尾必在** ⇒ 长度不变；
##   ② 严格递增（步长至少 1）⇒ 不会原地打转、不会出现零长段；
##   ③ `cam == null` ⇒ **不抽稀**（全画）—— 无头测试与无相机场景因此逐位同改动前。
func _render_chain(cam: Camera3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := _poly_count()
	if n <= 0:
		return out
	out.append(0)
	if n == 1:
		return out
	var use_lod := cam != null
	var cam_pos := cam.global_position if use_lod else Vector3.ZERO
	var i := 0
	while i < n - 1:
		var stride := _lod_stride(_poly_at(i).distance_to(cam_pos)) if use_lod else 1
		var nxt := mini(i + maxi(stride, 1), n - 1)
		out.append(nxt)
		i = nxt
	return out


func rebuild() -> void:
	_imm.clear_surfaces()
	var n := _poly_count()
	if n < 2:
		return
	var global_a := 1.0
	transparency = clampf(_fade, 0.0, 1.0)
	if global_a <= 0.001:
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	# ⚠️ 必须**先数顶点、再决定要不要 `surface_end()`**：
	# `ImmediateMesh` 的 surface 一个顶点都没有时 `surface_end()` 会报
	# `No vertices were added, surface can't be created` —— 而且**每帧一次**、日志刷屏。
	# 上面那条 `n < 2` 挡不住它：只要**所有相邻点都重合**（段长 < 0.01）就会走到这里。
	# ⚠️ 抽稀只改**渲染密度**：`_pts` / `_tip` / `covered_m()` 一概不动，
	# 所以「长度」这条需求与本次优化互不干扰（见 `_render_chain()`）。
	if cam != null: _last_camera_position = cam.global_position
	var chain := _render_chain(cam)
	var vt := 0
	_quads = 0
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var capacity := maxi(chain.size()-1,0)
	vertices.resize(capacity*4)
	colors.resize(capacity*4)
	uvs.resize(capacity*4)
	indices.resize(capacity*6)
	for k in range(1, chain.size()):
		var i0: int = chain[k - 1]
		var i1: int = chain[k]
		var p0 := _poly_at(i0)
		var p1 := _poly_at(i1)
		var seg := p1 - p0
		var sl := seg.length()
		if sl < 0.01:
			continue
		var dir := seg / sl
		# 丝带的"横向"：与这一段轨迹垂直、又尽量面向相机（无相机时退回水平）
		var to_cam := Vector3.UP * 500.0
		if cam != null:
			to_cam = cam.global_position - (p0 + p1) * 0.5
		var side := dir.cross(to_cam)
		if side.length_squared() < 0.0001:
			side = dir.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		# 头部（靠弹那端）浓而宽，尾部（发射点那端）淡而细 —— 烟在那儿飘最久
		var f_tail := _along(i0, n)
		var f_head := _along(i1, n)
		var a_tail := ALPHA * f_tail * global_a
		var a_head := ALPHA * f_head * global_a
		var w_tail := HALF_W * (0.55 + 0.45 * f_tail)
		var w_head := HALF_W * (0.55 + 0.45 * f_head)
		var c := Color(0.80, 0.80, 0.84)
		var v0 := p0 - side * w_tail
		var v1 := p0 + side * w_tail
		var v2 := p1 + side * w_head
		var v3 := p1 - side * w_head
		var offset := _quads*4
		vertices[offset] = v0
		vertices[offset+1] = v1
		vertices[offset+2] = v2
		vertices[offset+3] = v3
		colors[offset] = Color(c, a_tail)
		colors[offset+1] = Color(c, a_tail)
		colors[offset+2] = Color(c, a_head)
		colors[offset+3] = Color(c, a_head)
		uvs[offset] = Vector2(0,0)
		uvs[offset+1] = Vector2(1,0)
		uvs[offset+2] = Vector2(1,1)
		uvs[offset+3] = Vector2(0,1)
		var index := _quads*6
		indices[index] = offset
		indices[index+1] = offset+1
		indices[index+2] = offset+2
		indices[index+3] = offset
		indices[index+4] = offset+2
		indices[index+5] = offset+3
		vt += 6
		_quads += 1
	if vt == 0:
		# 整条带子没有一段是有效的（点全重合）⇒ 撤掉空 surface，别交给 `surface_end()`。
		_imm.clear_surfaces()
		return
	vertices.resize(_quads*4)
	colors.resize(_quads*4)
	uvs.resize(_quads*4)
	indices.resize(_quads*6)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_imm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## 第 idx 个点沿长度的"浓淡系数"：尾部 0.15 → 头部 1.0。
func _along(idx: int, n: int) -> float:
	var t := float(idx) / maxf(float(n - 1), 1.0)
	return 0.15 + 0.85 * t
