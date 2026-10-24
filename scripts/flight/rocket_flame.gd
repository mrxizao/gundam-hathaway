class_name RocketFlame
extends Node3D
## **马夫蒂火箭的发动机火焰与拖尾**（老板原话）：
## > 「**火箭升空的时候都没有大型火焰拖尾**」
##
## 参考图（`发射场景参考`）里那条橙白色的火柱就是它：比箭体长好几倍、
## 从箭底一直拖下去，把下方云层的顶面烤暖。
##
## ## ★★ 2026-09-30 晚：从**一根**变成**三根**（芯级 + 左右助推器）
## 老板原话：
## > 「**火箭下面只有一条长拖尾，但是火箭左右两边还有辅助推进器，
## >   这两条辅助推进器都需要做尾焰和拖尾**」
##
## ⇒ 喷口从常量 `(0,0,0)` 变成一个表 `NOZZLES`（见下面那一段），
## 三根焰**共用一份 `LAYERS` 层表与同一套长度/半径曲线** —— 只有
## 「摆在哪」「多大」「湍流相位」三件事逐喷口不同。
## 于是"三层各拿一份材质""长度随高度涨""熄火即消失"这些规矩一个字都没变，
## 只是每一层现在有**三份**。
##
## ## 它挂在哪
## `RocketFlame` 是 **`RocketBody` 的子节点**，坐标 = 箭体局部
## （原点 = **箭底**、机头 = −Z、右 = +X、上 = +Y）。箭体直立时它的 +Z 指向世界 −Y（**朝下**）。
##
## ## 局部坐标约定（**与 `RocketBody` 一致**）
## ```
##   机头 = −Z      上 = +Y      右 = +X      原点 = **箭底**（= 喷口平面）
##   ⇒ 焰沿 **+Z** 伸出，占 z ∈ [0, L]
## ```
##
## ## ⚠️ 三层为什么必须共用一份着色器、只差参数
## 三层若各写一份着色器，"哪一层盖过哪一层"就变成三个文件之间的事。
## 现在它是 `gain` 一个数：内芯 2.6 > 主焰 1.35 > 外圈 0.55。
##
## ## ⚠️ 长度与半径**都随高度涨**
## 真实羽流在稀薄大气里会被**拉长、胀开**（外面没有大气压着它）。海面附近短而紧、
## 高空长而散 —— 而这恰好也是老板要的"大型拖尾"最出效果的那一段。

const SHADER := "res://shaders/rocket_flame.gdshader"

# ------------------------------------------------------------ 几何（米）
## 海面附近的焰长 / 半径。
const LEN_MIN := 46.0
const R_MIN := 7.0
## 稀薄大气（`ALT_FULL` 以上）的焰长 / 半径。
## ⚠️ `LEN_MAX` 是"大型"这个词的全部来源：箭体 58 m，而这条焰是它的 4.5 倍。
const LEN_MAX := 262.0
const R_MAX := 17.5
## 焰长 / 半径走完 `LEN_MIN→MAX` 的高度。取 55 km（同温层顶上下）——
## 与 `LaunchScript.CLOUD_*` 那几档同一条量纲，别拿它跟 `ORBIT_ALT` 比。
const ALT_FULL := 55000.0

# ------------------------------------------------------------ ★ 喷口表

## ★★ 喷口表：**箭体局部坐标**（机头 = −Z / 箭底 = z 0 / 右 = +X / 上 = +Y）。
##
## | 喷口 | 位置 | 几何倍率 | 依据 |
## |---|---|---|---|
## | `Core`  | `(0, 0, 0)`       | **1.0** | 芯级主发动机。位置**保持 `(0,0,0)`** |
## | `SideL` | `(−7.72, 0, 0)`   | 0.55 | 左助推器 |
## | `SideR` | `(+7.77, 0, 0)`   | 0.55 | 右助推器 |
##
## ## 这几个数**是量出来的，不是估的**
## `tools/_rocket_nozzle_probe.gd`：遍历资产里 268 个零件的**箭体局部 AABB**
##（走 `RocketBody._xb_aabb()` —— 直接用 `mesh.get_aabb()` 会拿到"未变换的顶点并集"，
## 实测差 47%），取"贴着箭底（`z_max > −6 m`）"的那 24 个，再按 X 分簇：
##   · 左簇最靠箭底的是 `tripo_part_5`：`X = −7.72`、`Y = −0.86`、`Z_max = 0.00`（喷管口径 5.2 m）
##   · 右簇是 `tripo_part_2`：`X = +7.77`、`Y = −0.31`、`Z_max = −0.03`（口径 5.9 m）
##   · 中簇是 `tripo_part_40` / `43`：`Z_max = −2.97`（芯级喷口比助推器**高 3 m**）
## ⚠️ Y 一律取 **0**：量的三个数分别是 −0.86 / −0.31 / −0.52，都在 1 m 以内 ——
## 那是资产本身的建模误差，不是"助推器装偏了"。
##
## ## ⚠️ 芯级的 `Z` 为什么仍写 0（而不是量出来的 −2.97）
## 焰从 `z = −2.97` 起会**陷进箭体 3 m**：那一带的模型是助推器与芯级的壳体，
## 而焰是加色透明体、不写深度 —— 起点插进壳里之后，近处那一段会被箭体自己挡住，
## 看起来像"焰从助推器中间冒出来"。老板这一轮只说了"给助推器加焰"，
## 没有要求动芯级 ⇒ **不动**（要动的话这是唯一该改的那个数）。
##
## ⚠️ `scale` 是**几何倍率**（长度 × 半径**都**乘它），不是亮度：
## 助推器的喷管口径只有芯级的一半左右，三条都按主焰的尺寸画会把箭底糊成一片。
##
## ⚠️ `seed` 是**这一条的湍流相位**，会加到每层的 `seed` 上：
## 三条共用同一组相位的话它们会**逐帧同相**抖动，读起来是"同一根焰被复制了三份"。
const NOZZLES := [
	{"name": "Core", "pos": Vector3(0.0, 0.0, 0.0), "scale": 1.0, "seed": 0.0},
	{"name": "SideL", "pos": Vector3(-7.72, 0.0, 0.0), "scale": 0.55, "seed": 3.1},
	{"name": "SideR", "pos": Vector3(7.77, 0.0, 0.0), "scale": 0.55, "seed": 6.7},
]

## 侧喷口那两盏灯的**能量倍率**（相对主灯）。
## ⚠️ 不给 0：不给的话助推器下方那片云只有芯级那一盏灯照亮，
## 而画面上三根焰一样亮 —— "光从哪来"就对不上了。
## ⚠️ 也别给 1.0：三盏 `LIGHT_ENERGY = 9.0` 的灯叠在同一个 1400 m 半径里，
## 箭底那一片会直接过曝成白色。
## 距离调近是为了"各照各的脚下"——芯级那盏仍然负责烤亮整片云底。
const SIDE_LIGHT_MUL := 0.30
const SIDE_LIGHT_RANGE_MUL := 0.6

## 尾喷口那盏灯的参数。存在的理由：**参考图里云层的顶面是被焰烤亮的**。
## 没有它，"火箭从云里穿过去"这一段云永远是冷的灰蓝色。
const LIGHT_RANGE := 1400.0
const LIGHT_ENERGY := 9.0

## 绕 X 轴 +90°：`CylinderMesh` 的局部 +Y → 箭体局部 +Z。
## ⚠️ 符号不能改 —— `UV.y = 0` 是**底面**，它必须落在喷口那一头。见着色器头注。
const SPIN := PI * 0.5

## 逐层的（半径倍率, 长度倍率, 亮度, 湍流, 激波, 轴向衰减指数, 相位）。
## ⚠️ 顺序就是绘制顺序（外圈先画、内芯最后）—— 加色混合下顺序不影响结果，
## 但**报告与探针按名字找节点**，名字里的层号别乱动。
const LAYERS := [
	{"name": "Haze", "rad": 1.85, "len": 1.25, "gain": 0.55, "turb": 1.6,
		"rings": 0.0, "fade": 2.10, "seed": 5.3},
	{"name": "Mid", "rad": 1.00, "len": 1.00, "gain": 1.35, "turb": 1.0,
		"rings": 0.0, "fade": 1.35, "seed": 2.1},
	{"name": "Core", "rad": 0.45, "len": 0.55, "gain": 2.60, "turb": 0.55,
		"rings": 1.0, "fade": 0.95, "seed": 0.0},
]

## 上一次写进去的**归一化读数**（探针与测试直接读，不去反解材质）。
## `strength` = 节流、`widen` = 高空膨胀、`length` = 实际焰长（米，**芯级那一条**）。
##
## ⚠️ `length` 报的是**芯级**（`NOZZLES[0]`）的长度，不含侧喷口的 `scale` ——
## 它是"这条曲线现在走到哪了"的读数，三条焰共用同一条曲线。
## 测试里那两条 `fl.length == LEN_MIN / LEN_MAX` 钉的就是它。
var strength := 0.0
var widen := 0.0
var length := 0.0

## 扁平表：`i = 喷口序号 × LAYERS.size() + 层号`。
## ⚠️ **喷口优先**（不是层优先）⇒ 前 `LAYERS.size()` 个恒是芯级那三层，
## 于是"第 0 个喷口 = 主发动机"这件事在索引上就是免费的，
## 测试与探针按 `mats[0..2]` 读主焰的三层仍然对。
var _mats: Array[ShaderMaterial] = []
var _meshes: Array[MeshInstance3D] = []
## 逐喷口一盏。第 0 盏恒叫 `NozzleLight`（旧名字，测试与探针按它找）。
var _lights: Array[OmniLight3D] = []


func _init() -> void:
	name = "RocketFlame"
	for n in NOZZLES.size():
		var nz: Dictionary = NOZZLES[n]
		var nz_name := String(nz["name"])
		var nz_seed := float(nz["seed"])
		for d in LAYERS:
			var mat := ShaderMaterial.new()
			if ResourceLoader.exists(SHADER):
				mat.shader = load(SHADER)
			else:
				# ⚠️ 必须喊：静默失败的表现是"火箭屁股后面什么都没有" ——
				# 而那与"这一轮没做这件事"长得一模一样。
				push_error("火焰着色器载不到（%s）⇒ 火箭不会有焰" % SHADER)
			mat.set_shader_parameter("strength", 0.0)
			mat.set_shader_parameter("widen", 0.0)
			# ⚠️ **每一层、每一个喷口都各拿一份材质**：`ShaderMaterial` 是资源，
			# 共用一份的话最后一次 `set_shader_parameter` 会把共用它的那些一起改掉
			#（症状：三层的 `gain` 全变成 2.6，外圈比内芯还亮；
			#  三根焰的湍流**逐帧同相**，看起来像同一根被复制了三份）。
			mat.set_shader_parameter("turb", d["turb"])
			mat.set_shader_parameter("rings", d["rings"])
			mat.set_shader_parameter("gain", d["gain"])
			mat.set_shader_parameter("fade_pow", d["fade"])
			mat.set_shader_parameter("seed", float(d["seed"]) + nz_seed)

			var cm := CylinderMesh.new()
			# 略收口 + **去掉两端盖**：端盖会在尾端画出一个亮圆盘，
			# 而且顶端那个圆盘的朝向还随相机变（看起来像"拖着一个小碟子"）。
			cm.top_radius = 1.0
			cm.bottom_radius = 0.78
			cm.height = 1.0
			cm.radial_segments = 28
			cm.rings = 1
			cm.cap_top = false
			cm.cap_bottom = false
			cm.material = mat

			var mi := MeshInstance3D.new()
			# ⚠️ 第 0 个喷口（芯级）的节点名**保持原样**（`Haze` / `Mid` / `Core`）——
			# 改名字会连带改掉测试、探针、以及既定验收图里的找节点方式，
			# 而那样改没有任何收益：`NOZZLES[0]` 本来就叫 `Core`。
			# 侧喷口才带前缀（`SideL_Haze` …）—— 不然三条焰的节点名全部撞车。
			mi.name = String(d["name"]) if n == 0 else "%s_%s" % [nz_name, String(d["name"])]
			mi.mesh = cm
			# 焰是加色透明体：不投影（投影会在地面/云上留下一道**黑色的柱影**），
			# 也不参与深度写入（见着色器 `render_mode`）。
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_mats.append(mat)
			_meshes.append(mi)

		# 喷口那盏灯（参考图里被烤亮的云）。
		var lt := OmniLight3D.new()
		lt.name = "NozzleLight" if n == 0 else "%s_Light" % nz_name
		lt.light_color = Color(1.0, 0.72, 0.42)
		lt.light_energy = 0.0
		lt.omni_attenuation = 1.1
		lt.shadow_enabled = false
		if n == 0:
			lt.omni_range = LIGHT_RANGE
		else:
			lt.position = Vector3(nz["pos"])
			lt.omni_range = LIGHT_RANGE * SIDE_LIGHT_RANGE_MUL
		add_child(lt)
		_lights.append(lt)

	# ⚠️ **建好就把几何摆到位**（不是等第一次 `update()`）：
	# 不然在"建出来"与"第一帧 update"之间，三层的变换是**单位矩阵** ——
	# 那时它们是一堆半径 1 m、长度 1 m 的小锥堆在箭底，而那正是
	# "探针第一帧"或"任何只建不推的调用方"会看到的样子。
	_layout(LEN_MIN, R_MIN)


## 把每一条焰摆到"焰长 `len_m` / 喷口半径 `rad_m`"（**芯级**的尺寸；
## 侧喷口再乘自己那一行的 `scale`）。
##
## 抽出来是为了**建的时候与每帧推的时候走同一条算式**：
## 两处各写一份的话，"建好那一帧"与"跑起来之后"的焰会不一样长，
## 而那种差异看起来只像"第一帧抖了一下"。
func _layout(len_m: float, rad_m: float) -> void:
	length = len_m
	for n in NOZZLES.size():
		var nz: Dictionary = NOZZLES[n]
		var s := float(nz["scale"])
		var origin: Vector3 = nz["pos"]
		for j in LAYERS.size():
			var d: Dictionary = LAYERS[j]
			var lay_len := len_m * s * float(d["len"])
			var lay_rad := rad_m * s * float(d["rad"])
			# `SPIN` 先转、再按**网格局部**缩（`B * Basis.from_scale(s)` 的顺序不能反：
			# `Basis.scaled()` 是**父空间**缩放，反了会把"长"和"宽"对调）。
			var basis := Basis(Vector3.RIGHT, SPIN) \
				* Basis.from_scale(Vector3(lay_rad, lay_len, lay_rad))
			# 网格是**居中**的（`CylinderMesh` 从 −h/2 到 +h/2）⇒ 平移半个层长，
			# 把喷口那一端落在**自己那个喷口的 z 平面**上。
			_meshes[n * LAYERS.size() + j].transform = Transform3D(
				basis, origin + Vector3(0.0, 0.0, lay_len * 0.5))


## 推一帧。由 `main.gd._tick_launch()` 调（与 `SeaSplash` / HUD 的座舱层
## 同一条规矩：**显式调用、显式传参** ⇒ 单测能按固定数据复现）。
##
## ⚠️ 形参类型是 **`Node3D`**（鸭子类型读 `base_throttle`）而不是 `RocketBody`：
## `RocketBody` 是本类的宿主，两个全局类互相引用会以"某个不相干的文件编译失败"的样子
## 冒出来。这条规矩与 `ChaseCamera._target_velocity()` 读 `fm` 是同一条。
func update(rocket: Node3D) -> void:
	if rocket == null or not is_instance_valid(rocket):
		return
	var th := clampf(float(rocket.get("base_throttle")), 0.0, 1.0)
	var alt := clampf(rocket.global_position.y / ALT_FULL, 0.0, 1.0)
	var len_m := lerpf(LEN_MIN, LEN_MAX, alt)
	var rad_m := lerpf(R_MIN, R_MAX, alt)
	strength = th
	widen = alt
	_layout(len_m, rad_m)
	for i in _mats.size():
		# 每帧推 strength / widen：**只要这两个**。
		# 其余参数是"这一层/这一条的身份"，在 `_init()` 里写死一次 ——
		# 每帧重推会把它们从材质里读出来再写回去，纯属浪费。
		_mats[i].set_shader_parameter("strength", th)
		_mats[i].set_shader_parameter("widen", alt)
	for k in _lights.size():
		_lights[k].light_energy = th * LIGHT_ENERGY * (1.0 if k == 0 else SIDE_LIGHT_MUL)


## 熄火：把焰整根收掉（含全部的灯）。
##
## ⚠️ 单独一个函数而不是"靠 `update()` 自然收敛"：`_finish_launch()` 之后
## 火箭**不再被 `step()` 驱动**，也就没人再调 `update()` —— 焰会**冻在最后一次
## 的读数上**（发射段结束时是满推力 ⇒ 抵达轨道后箭尾永远挂着一根满功率的火柱，
## 而它已经熄火了）。这就是那种"看起来像做了特效、其实是没关"的故障。
##
## ⚠️ 现在是**三根焰 + 三盏灯**：只熄主喷口那一支的话，左右两条会永远留在画面上 ——
## 而 `_lights` / `_mats` 都是扁平表 ⇒ 两个 for 各自跑满才是"全熄"。
func extinguish() -> void:
	strength = 0.0
	widen = 0.0
	length = 0.0
	for i in _mats.size():
		_mats[i].set_shader_parameter("strength", 0.0)
	for k in _lights.size():
		if _lights[k] != null and is_instance_valid(_lights[k]):
			_lights[k].light_energy = 0.0
