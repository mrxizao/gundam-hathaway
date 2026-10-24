class_name RocketBody
extends Node3D
## 马夫蒂火箭：**玩家可操控的运载器**。
##
## ## 机体坐标约定（与全工程一致）
##   · **机头 = 局部 −Z**（`ChaseCamera._desired_position()` 把镜头放在 `+Z` 侧
##     ⇒ 不写这个约定，追尾镜机会跑到火箭前面去）；
##   · **背侧 = 局部 +Y**（`ChaseCamera._desired_basis()` 拿 `basis.y` 当"上"）。
##
## ## 资产朝向：**一个滚转错了不会报任何错的地方**
##
## 导入后模型的长轴是 **+Y**（实测 `size=(0.1736, 0.8048, 0.3079)`，
## 见 `tools/_rocket_family_probe.gd` 的读数）。于是"摆正机头"只差一步
## `Basis(Vector3.RIGHT, -PI*0.5)`：模型 +Y → 机体 −Z。
##
## ⚠️ 但**只做这一步是错的**：模型的横截面是 **X 0.1736 × Z 0.3079** ——
## Z 那根明显宽（两个助推器沿模型 **Z** 排开）。只转 X −90° 的话
## 模型 +Z 落到机体 **+Y**，也就是**两个助推器上下叠着**。
##
## ⇒ 还要再绕机体 Z 滚 −90°，把模型 +Z 送到**水平**的机体 +X。
## 引擎里的读数（`_rocket_family_probe.gd` 的"朝向备选"那一段）：
## | 备选 | 模型 +Y → | 模型 +Z → | 机体包围盒 | 判 |
## |---|---|---|---|---|
## | 只转 X −90° | 机体 −Z | 机体 +Y | (0.1736, **0.3079**, 0.8048) | 助推器**上下叠着** ✗ |
## | 再滚 −90°  | 机体 −Z | 机体 +X | (**0.3079**, 0.1736, 0.8048) | 助推器**左右并排** ✓ |
##
## ★ 这件事的教训：**"长轴对上了"不等于"朝向对了"**。
## 长轴只约束两个自由度，滚转是第三个 —— 而它错了的表现是
## "火箭看着还是火箭、只是有点别扭"，不报错、不崩、不影响任何读数。
## 凡是"摆正一个刚体"，都要把**三根轴各自落到哪儿**写出来核，不能只核一根。
##
## ## 飞控：真实力 + 制导跟踪（不是"钉在曲线上"）
##
## 每一帧算的是**加速度指令**，然后把它拆成"机头指哪 + 节流阀开多大"：
## ```
## v_des  = ref_vel + (ref_pos − pos) · POS_GAIN          # 位置环：位置误差换速度
## a_cmd  = ref_acc + (v_des − vel) · VEL_GAIN            # 速度环 + 曲线前馈
## a_need = a_cmd − g⃗ − d⃗                                 # ★ 推力要出的那一份（抵掉重力/阻力）
## 机头 → a_need 方向        throttle = |a_need|·m / THRUST_N
## ```
## ⚠️ `a_need` 上的**负号**是这条链上最容易丢的符号：丢了不是"差一点"，
## 而是 `g⃗` 与 `d⃗` 各被算两遍且方向反了（起飞瞬间变成 −2g 往下砸）。
## 详见 `step()` 里 ④ 那段注释。
##
## ⇒ **重力与阻力是真的在吃推力**：`g⃗` 与 `d⃗` 出现在 `a_need` 里，
## 制导必须先把它们抵掉，剩下的才拿去跟踪曲线。低空阻力那一项会让机头
## 多抬几度，高真空里那一项消失后机头自然放平 —— 这不是"演"的。
##
## ⇒ 位置是**力积分**出来的（`velocity += accel·dt`），玩家真的在开这枚箭；
## 而抵达点由曲线保证（`LaunchScript.ascent_pos(1) == arrival_pos()`，纯函数断言）。
##
## ## ⚠️ 三个刻意的失真，全写在明处
##
## 1. **推力极大**（虚构运载器）。曲线自身在末段的加速度是 ~1.5 km/s²
##    （几何决定的，见 `LaunchScript.ALT_SHAPE` 的长注释），
##    所以 `THRUST_N` 必须让**最大加速度显著大于**它，否则末端长期饱和、
##    跟踪滞后、抵达点差几公里。`4.2e8 N / 196 t ≈ 2.1 km/s²` ⇒ 末段约 68% 节流。
##    真实运载器是 1.5~3 g，这里是 10² g —— 这段演出要有戏，不能真让玩家坐十分钟。
## 2. **节流杆改的是"时间表"而不是"推力"**：`thr_in` 调制 `u` 的推进速率
##    （`SCHED_SWING`），推力大小始终由制导的跟踪误差决定。
##    两件事都让玩家控制的话会**互相掩盖** —— 推杆之后分不清是"时间变快"
##    还是"推力变大"，而调参时那种混沌最难查。
## 3. **安全绳**（`LEASH_M`）：跟踪误差超过 9 km 就把它拉回来。
##    制导的 PD 在远场是线性的 ⇒ 真的被拽飞之后**永远追不上**。
##    它是保险丝，不是主回路 —— `leash_count` 是自证清白的读数：
##    名义上升（无输入）跑完应该是 **0**。

signal event(kind: String, text: String)   ## 播报（离塔 / 最大动压 / 卡门线 / 抵达）

# ============================================================ 箭体参数

## 空载质量（kg）。燃料 210 t ⇒ 起飞质量 256 t、末质量取决于节流。
const MASS_DRY := 46000.0
const FUEL0 := 210000.0
## 真空推力（N）。见头注"刻意的失真"① 的推导。
const THRUST_N := 4.2e8
## 满推力每秒烧掉多少燃料（kg/s）。燃料够烧 210 s ⇒ 整段用不完，
## 但**读数上**必须真的在掉（"还剩多少"是运载器唯一诚实的紧张感来源）。
const BURN_RATE := 1000.0

## 阻力系数折合量（1/m）：`0.5 · Cd · A / m` 全部折进这一个数。
##
## ⚠️ 它必须与 `LaunchScript.drag_accel()` 的指数模型配套看：
## 低空（`rho ≈ 1.2`）速度 2 km/s 时 `a ≈ 3.4e-5 × 1.2 × 4e6 = 163 m/s²`
## —— 与重力 9.8 同量级甚至更大，**制导必须真把它抵掉**。
## 到 100 km 时 `rho ≈ 9e-6` ⇒ 这一项归零。
const DRAG_K := 3.4e-5

## 模型在游戏里的高度（米）。模型自身 0.8048 个单位高 ⇒ 缩放 `58 / 0.8048`。
##
## ★ 用"目标高度 ÷ 实测模型高"来缩放，而不是写死一个倍率：
## 模型将来若被重新导出（换单位、换轴），写死的倍率会静默变错，
## 而"按实测高缩放"永远得到一枚 58 m 的火箭。实测高由 `set_model()` 现场量。
const ROCKET_HEIGHT_M := 58.0

## 姿态角速率上限（rad/s）。太小追不上制导指令（火箭会横着飞），
## 太大则"玩家一动就翻跟头"。
const MAX_RATE := 0.55
## 姿态对齐增益（1/s）。收敛时间常数 ~1/ATT_GAIN，再被 `MAX_RATE` 夹住。
const ATT_GAIN := 3.2

## ---- 制导增益 ----
## 位置环：位置误差 → 期望速度（1/s）。1 km 误差要出 600 m/s 的额外速度。
const POS_GAIN := 0.6
## 速度环：速度误差 → 需要的加速度（1/s）。
## ⚠️ 饱和点 = `可用加速度 / VEL_GAIN` ≈ 2100/3.0 = **700 m/s**。
## 误差超过它就开始丢跟踪，所以前馈（`ref_acc + g⃗ + d⃗`）必须准 ——
## 前馈负责"沿名义轨迹飞"，反馈只负责"抹掉残差"。
const VEL_GAIN := 3.0

## 玩家配平偏置的上限（度）。推杆最多把这枚箭从程序上拽走这么多；
## 松手后制导会把它拉回去（`TRIM_RECENTER`）。
const MAX_TRIM_DEG := 26.0
const TRIM_RATE_DEG := 34.0
const TRIM_RECENTER := 22.0

## 节流杆对**时间表**的摆幅：`u` 的推进速率在 `1 ± SCHED_SWING` 之间。
## 0.35 ⇒ 整段从 60 s 可在 **44 s ~ 92 s** 之间变。
const SCHED_SWING := 0.35

## **安全绳**：跟踪误差超过这个就把它拉回来（米）。见头注"刻意的失真"③。
const LEASH_M := 9000.0
## 拉回来的时间常数（秒）。
const LEASH_TAU := 1.6

# ============================================================ 状态

## 世界坐标速度（m/s）。**真源** —— 位置是它积分出来的。
var velocity := Vector3.ZERO
var fuel := FUEL0
## 曲线进度（0..1）。
var u := 0.0
## 制导开关。关掉之后完全由玩家操纵姿态与节流阀（调试 / 自由飞用）。
var assist := true
## 制导算出的基准节流阀（0..1）。**不是玩家直接给的**。
var base_throttle := 0.0
## 玩家的姿态配平（度）：x = 俯仰，y = 偏航。
var trim_deg := Vector2.ZERO
## 玩家的节流杆（−1..1）—— 改的是时间表，不是推力。
var throttle_trim := 0.0
## 房间切换是否已完成（影响 `leg()` 与播报）。
var room_swapped := false

## 上一步的推力加速度大小（m/s²）—— 换个说法就是"这枚箭现在推得多狠"。
var last_accel := 0.0
var last_drag := 0.0

## ---- 自证清白的读数（测试与探针直接读）----
## 名义上升全程的最大跟踪误差（米）。见头注"刻意的失真"③。
var max_track_err := 0.0
## 安全绳触发次数。名义上升**必须是 0**。
var leash_count := 0
## 制导**想要**的机头仰角（度）—— 上一步算出的推力方向的高度角。
##
## ⚠️ 它是"姿态环跟踪误差"的唯一真源：拿 `pitch_deg()` 减去它才是姿态误差。
## ## 为什么不能拿"参考航迹角"当姿态的期望值
## 第一版 `suite_rocket_launch` 就是拿 `ascent_pitch_deg(u)`（**速度方向**）去比
## `pitch_deg()`（**机身指向**），结果全程差出 53° 并被判红。
## 那两个角**本来就不该相等**：机身对着的是**推力方向**，而推力除了跟随速度，
## 还得先把重力抵掉 —— 起飞段速度几乎垂直、而推力必须完全垂直（悬停抵消重力），
## 中段要往水平方向额外加速（重力转弯），于是推力比速度**更偏水平**。
## 实测中段 `u = 0.2`：推力方向 52°、速度方向 79° —— 差 27°，而两者都是对的。
var cmd_pitch_deg := 90.0

## 播报去重：同一个 kind 只喊一次（`最大动压` 每帧喊就成了刷屏）。
var _announced: Dictionary = {}
var _u_span := 60.0
## 还在水里（`place_at_launch()` 置 true，"出水"播报时置 false）。
var _was_submerged := true

var _model_root: Node3D = null


# ============================================================ 装配

## **模型 → 机体**的旋转。见头注那张表 —— 两段缺一不可。
static func model_basis() -> Basis:
	# ① 绕机体 X 轴 −90°：模型 +Y（长轴）→ 机体 −Z（机头）
	# ② 再绕机体 Z 轴 −90°：模型 +Z（助推器排开的方向）→ 机体 +X（水平）
	return Basis(Vector3.BACK, -PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5)


## 把资产挂上来：摆正朝向 + 按 `ROCKET_HEIGHT_M` 缩放到真实尺寸。
func set_model(model: Node3D) -> void:
	if _model_root != null and is_instance_valid(_model_root):
		_model_root.queue_free()
	_model_root = Node3D.new()
	_model_root.name = "ModelRoot"
	_model_root.basis = model_basis()
	_model_root.add_child(model)
	add_child(_model_root)
	_fit_scale()


## 按实测模型高度缩放，使整枚箭高 = `ROCKET_HEIGHT_M`，**并把模型的尾端对齐到箭底**。
##
## ⚠️ 量的是**累乘了父链变换**的 AABB（`_xb_aabb`），不是 `model.get_aabb()`
## —— 后者是**模型空间**的，而 268 个零件的变换里带旋转，
## 直接拿它算会得到"未变换的顶点并集"（实测 0.5484 vs 真值 0.8048，差 47%）。
##
## ## ⚠️⚠️ 只有缩放、不摆位 = 模型**以自身中点坐在箭底上**（2026-09-30 实测）
## `glb` 的本体原点在**模型质心**，而本工程的 `RocketBody` 原点约定是**箭底**。
## 只设 `scale` 不动 `position` ⇒ 58 m 的箭有 **30.12 m 沉在箭底之下**：
##   · 静置时（箭底 = 海面 −34 m）模型顶面在 **海面之下 6.12 m** —— 整枚箭全在水里；
##   · `rig_anchor("head")` 按 `ROCKET_HEIGHT_M` 算 ⇒ 眼位比**真实箭顶**高 **31.57 m**，
##     老板要的「在火箭最上端加一个驾驶舱」变成"在箭顶上方 31.6 m 悬空挂一个舱"；
##   · 而它**一条错都不报**，图上看只像"火箭吃水深了一点"。
## 判据：`_geom_probe` 那行「顶面高出箭底 X m」必须 ≈ `ROCKET_HEIGHT_M`，
## 且 `_fit_scale()` 之后 `_model_root.position` 不为零。
func _fit_scale() -> void:
	var hi := -INF
	var lo := INF
	for n in _model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a := _xb_aabb(mi.mesh.get_aabb(), _relative_to(mi, _model_root))
		hi = maxf(hi, a.position.y + a.size.y)
		lo = minf(lo, a.position.y)
	if hi - lo < 1e-6:
		push_warning("火箭模型量不出高度 ⇒ 缩放保持 1.0")
		return
	var s := ROCKET_HEIGHT_M / (hi - lo)
	_model_root.scale = Vector3.ONE * s
	# ★ 把模型的**尾端**（模型局部 y = lo）搬到机体原点（= 箭底）。
	# ⚠️ 不能写 `_model_root.basis * ...`：`Node3D.position` 是在**父空间**里解释的，
	# 而 `.position` **不吃 `.scale`**（Godot 把 basis 与 origin 分开存）。
	# 所以这里是"用 `model_basis()`（纯旋转）换算到机体轴"，再乘缩放。
	# 对当前资产：模型局部 +Y → 机体 −Z（机头）⇒ 尾端落在 +Z 侧，位移 (0, 0, +s·lo)。
	var r := model_basis()
	_model_root.position = -(r * Vector3(0.0, lo * s, 0.0))


## `node` 相对 `root` 的变换（沿父链累乘）。**不问场景树** ——
## `global_transform` 在"节点还没真正入树"时会静默返回单位矩阵（见探针头注）。
static func _relative_to(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p := node
	while p != null and p != root:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return xf


## AABB 乘变换后的轴对齐盒。⚠️ 自己乘 8 个角：Godot **没有** `Transform3D * AABB`。
static func _xb_aabb(a: AABB, xf: Transform3D) -> AABB:
	var out := AABB()
	for i in 8:
		var c := a.position + Vector3(
			a.size.x * float(i & 1), a.size.y * float((i >> 1) & 1), a.size.z * float((i >> 2) & 1))
		var w := xf * c
		out = AABB(w, Vector3.ZERO) if i == 0 else out.expand(w)
	return out


func model_root() -> Node3D:
	return _model_root


## ★ **座舱眼位**（机体系，机头 = −Z）。
##
## ## 为什么这个函数名是 `rig_anchor` / 参数是 `"head"`
## `ChaseCamera._fpv_eye_local()` 用**鸭子类型**读它（`t.has_method("rig_anchor")`，
## 不许写死 `FlightBody` —— 那是循环依赖，见那边的注释）。
## 沿用同一个方法名，火箭的驾驶舱就**直接复用**工程里既有的第一人称通道：
## 眼位、视线吸附、混合速率、进出过渡，一行都不用重写。
##
## ## 眼位为什么在 **`ROCKET_HEIGHT_M + 1`**
## 老板：「**在火箭最上端加一个驾驶舱**」。模型顶面在局部 `z = −58`（机头 = −Z），
## 取 59 ⇒ 眼位在**箭顶之上 1 m**，整个箭体都在脚下。
## ⚠️ 这条**依赖 `_fit_scale()` 把模型尾端摆到箭底**（那里有一条长注释）。
## 少了那一步，模型以质心坐在箭底上 ⇒ 顶面只到 `z = −27.88`，
## 而这里照旧按 58 算 ⇒ 眼位跑到**真实箭顶上方 31.57 m** 的空中。
## `_rocket_shots.gd::_geom_probe()` 把「眼位高出模型顶面多少」直接打出来，
## 正常值 ≈ `+1.12 m`。
## （第一版还有一个 `tools/_cockpit_probe.gd` 做同一件事，随 3D 舱一起归档了。）
## ⚠️ 别取 58 以下：那会落进模型的**壳体内部**（本工程的资产是单层壳），
## 看到的是背面剔除之后的碎片 + 近平面剖切 —— 与机体 FPV 踩过的是同一个坑。
## ⚠️ 也别往上加太多：舱内表现在是**屏幕空间的**（HUD 的全周天那一层），
## 不再有"舱底板"这种 3D 件；但眼位仍然是**刻度导轨与取景框的原点**，
## 抬太高会让地平线相对画面中心偏出去（仪表说平飞、而导轨画的不是）。
func rig_anchor(part: String) -> Vector3:
	if part == "head":
		return Vector3(0.0, 0.0, -(ROCKET_HEIGHT_M + 1.0))
	return Vector3.ZERO


# ============================================================ 座舱眼位（第一人称）

## 座舱眼位 —— **机体系**。
##
## ## ⚠️ 2026-09-30：舱体不再是 3D 几何，但这个算式**仍然必须精确存在**
## 第一版那套 3D 舱（`RocketCockpit`）被老板否掉、已删，舱内表现改成
## HUD 的全周天那一层（屏幕空间）。但相机的位置不由舱决定、由**这一条算式**决定：
## `ChaseCamera._fpv_eye_local()` 在头部锚点之外**还会再推一段**
##（`head + Vector3(0, FPV_EYE_UP, −FPV_EYE_FWD)`）。
## 刻度导轨 / 取景框 / 仪表台全以**相机所在那一点**为原点 —— 差 12 cm 高、
## 45 cm 后，症状是"仪表说平飞、而导轨画的是一条歪的地平线"，
## 而它**不报任何错**（看起来只像美术没对齐）。
##
## ⚠️ 别在这里另抄一组数：`ChaseCamera.FPV_EYE_*` 一改，这里必须跟着改，
## 而"两处各写一份"正是那种改完静默错开的写法。`suite_rocket_launch` 有一条断言
## 直接把两者对起来。
func cockpit_eye_local() -> Vector3:
	return rig_anchor("head") \
		+ Vector3(0.0, ChaseCamera.FPV_EYE_UP, -ChaseCamera.FPV_EYE_FWD)


## `span` = 从 u=0 飞到 u=1 的**基准**秒数（玩家节流杆在 `SCHED_SWING` 内改这个数）。
func configure(span: float) -> void:
	_u_span = maxf(span, 1.0)


## 摆到发射点：**浸在海里**、机头朝上（= 机体的 −Z 指向世界 +Y）。
##
## ⚠️ 名字从 `place_on_pad()` 改过来 —— 平台已经被砍掉了（老板：
## 「不需要用发射平台，直接从海里面出来就行了」），"pad" 这个词在这条链上
## 已经没有对应物。调用方传进来的 `pos` 就是"箭底"的世界坐标，
## 由 `LaunchScript.launch_pos() + rest_alt()` 给（低 34 m = 吃水，见 `PAD_DRAFT`）。
##
## ⚠️ 符号别推错：`R_x(θ)` 作用在 `(x,y,z)` 上是 `(x, y·cosθ − z·sinθ, y·sinθ + z·cosθ)`，
## 代 `(0,0,−1)` 得 `(0, sinθ, −cosθ)`。
## ⇒ `θ = −90°` 给 `(0, −1, 0)` = **机头朝下**；`θ = +90°` 才是朝上。
##
## 而且这条**不该靠推理保证** —— `suite_rocket_launch` 直接钉
## `upright_basis() * Vector3.FORWARD == Vector3.UP`。写反了那一刻就红。
static func upright_basis() -> Basis:
	return Basis(Vector3.RIGHT, PI * 0.5)


func place_at_launch(pos: Vector3) -> void:
	global_transform = Transform3D(upright_basis(), pos)
	velocity = Vector3.ZERO
	u = 0.0
	fuel = FUEL0
	max_track_err = 0.0
	leash_count = 0
	_announced.clear()
	_was_submerged = true


# ============================================================ 每帧

## 推进一帧。**显式 dt、显式调用** —— 单测不进树也能按固定 dt 复现整段上升。
func step(dt: float, pitch_in: float, yaw_in: float, thr_in: float) -> void:
	if dt <= 0.0:
		return

	# ---- ⓪ 已经抵达：冻结，不再积分 ----
	#
	# ⚠️⚠️ 这个提前返回**不是**优化，是挡一个很难查的失控：
	# `u` 一到 1.0，`ascent_pos(u)` 就被**冻住**了（参考点停在抵达点不动），
	# 而这一枚箭这时候还带着 **35 km/s**。调用方（`main.gd._tick_launch()`）是
	# "u ≥ 1.0 且换图建完"才交还操控 —— 只要换图还没建完（`await apply_map_staged()`
	# 那几帧，或者它中途出错），位置环就会把"每帧落后 586 m"读成
	# 一个**反向的巨大速度指令**，制导于是把机头指向后方、满推反推。
	#
	# 而且它**一声不响**：`leash_count` 只会默默涨（安全绳会一次次把它拽回来），
	# 表现是"抵达之后箭突然原地抽搐/被甩走"，日志里一切正常。
	# 实测：多跑 8 帧 ⇒ 跟踪误差从 612 m 涨到 5 311 m、机身仰角跑到 −60°。
	#
	# ⇒ 抵达之后这一枚箭就不再是"在飞的箭"了，直接冻结等调用方断电。
	if u >= 1.0:
		return

	# ---- ① 玩家配平（松手自动回中，制导才会把人拽回程序）----
	trim_deg.x = clampf(trim_deg.x + pitch_in * TRIM_RATE_DEG * dt,
		-MAX_TRIM_DEG, MAX_TRIM_DEG)
	trim_deg.y = clampf(trim_deg.y + yaw_in * TRIM_RATE_DEG * dt,
		-MAX_TRIM_DEG, MAX_TRIM_DEG)
	if absf(pitch_in) < 0.01:
		trim_deg.x = move_toward(trim_deg.x, 0.0, TRIM_RECENTER * dt)
	if absf(yaw_in) < 0.01:
		trim_deg.y = move_toward(trim_deg.y, 0.0, TRIM_RECENTER * dt)
	throttle_trim = clampf(throttle_trim + thr_in * 0.6 * dt, -1.0, 1.0)

	# ---- ② 曲线进度 + 参考状态 ----
	# 节流杆改的是**时间表**（见头注"刻意的失真"②），于是参考量按
	# 时间重参数化的链式法则缩放：速度 ×s、加速度 ×s²。
	var sched := schedule_factor()
	u = clampf(u + dt / maxf(_u_span, 1.0) * sched, 0.0, 1.0)
	var ref_pos := LaunchScript.ascent_pos(u)
	var ref_vel := LaunchScript.ascent_velocity(u) * sched
	var ref_acc := LaunchScript.ascent_accel(u) * sched * sched

	# ---- ③ 重力 / 阻力：**真实施加**，制导必须把它们抵掉 ----
	var alt := global_position.y
	var g_vec := _down_dir() * LaunchScript.gravity_at(alt)
	var speed := velocity.length()
	last_drag = LaunchScript.drag_accel(alt, speed, DRAG_K)
	var d_vec := Vector3.ZERO
	if speed > 1.0:
		d_vec = -velocity.normalized() * last_drag

	var mass := MASS_DRY + fuel
	var thrust_dir := -basis.z

	if assist:
		# ---- ④ 制导：位置环 → 速度环 → 需要的**推力加速度** ----
		#
		# ⚠️⚠️ 这里的符号是整段飞控最容易写错、又最不报错的地方，说清楚：
		#
		#   物理：`a_总 = a_推力 + g⃗ + d⃗`（`g⃗` / `d⃗` 是**加速度**，见 ③）。
		#   目标：让 `a_总` 等于指令加速度 `a_指令 = ref_acc + (v_des − vel)·VEL_GAIN`。
		#   ⇒ **推力要出的是 `a_指令 − g⃗ − d⃗`**（把重力与阻力抵掉，剩下的才拿去跟踪曲线）。
		#
		# 第一版写的是 `+ g_vec + d_vec`（少了一个负号）。后果是 `g⃗` 与 `d⃗`
		# **各被算了两遍**，而且方向还是反的 —— 起飞那一刻 `a_指令 ≈ 0`，
		# 于是 `a_need = g⃗` ⇒ 机头指向**地心**、满推往下，加上积分里那一份 `g⃗`，
		# 这一帧的实际加速度是 **−2g（19.6 m/s² 向下）**。
		#
		# 它不报任何错：火箭一开始往下掉，位置环随后把误差拉回来，
		# 于是画面是"点火后先沉一下再爬"，而**读数上**表现为
		# 最大跟踪误差 5.3 km、抵达点差 20.7 km、机身仰角比参考航迹角偏 53°。
		# 四个数一起红，根因只有一个。
		var v_des := ref_vel + (ref_pos - global_position) * POS_GAIN
		var a_cmd := ref_acc + (v_des - velocity) * VEL_GAIN
		var a_need := a_cmd - g_vec - d_vec
		var a_mag := a_need.length()
		last_accel = a_mag
		if a_mag > 1e-6:
			thrust_dir = a_need / a_mag
			# 配平绕**机体自己的轴**转，不是绕世界轴 —— 绕世界轴的话，
			# 火箭一旦倒下来，"推杆"会变成"滚转"。
			thrust_dir = thrust_dir.rotated(basis.x, deg_to_rad(trim_deg.x)) \
				.rotated(basis.y, deg_to_rad(trim_deg.y)).normalized()
		# 推力只要够产生 `a_need` 就行：`throttle = a·m / N`。
		# ⇒ 燃料越烧越少，同样的加速度需要的节流阀**越来越小**（真实火箭同理）。
		base_throttle = clampf(a_mag * mass / THRUST_N, 0.0, 1.0)
		# 姿态环的期望值 = 推力方向的高度角（**不是**速度方向，见 `cmd_pitch_deg`）。
		cmd_pitch_deg = thrust_pitch_of(thrust_dir)
		_align_to(thrust_dir, dt)
	else:
		# 手动模式：不做制导。俯仰/偏航杆**直接**转机身，节流杆**直接**给推力。
		base_throttle = clampf(base_throttle + thr_in * 0.8 * dt, 0.0, 1.0)
		_last_accel_dummy(pitch_in, yaw_in, dt)
		last_accel = base_throttle * THRUST_N / maxf(mass, 1.0)

	# ---- ⑤ 力积分 ----
	fuel = maxf(fuel - BURN_RATE * base_throttle * dt, 0.0)
	var accel := thrust_dir * LaunchScript.thrust_accel(base_throttle, THRUST_N, mass)
	accel += g_vec + d_vec
	velocity += accel * dt
	global_position += velocity * dt

	# ---- ⑥ 安全绳（见 `LEASH_M`）----
	var err := ref_pos - global_position
	var elen := err.length()
	max_track_err = maxf(max_track_err, elen)
	if assist and elen > LEASH_M:
		leash_count += 1
		var pull := 1.0 - exp(-dt / LEASH_TAU)
		global_position = global_position.lerp(ref_pos, pull)
		velocity = velocity.lerp(ref_vel, pull)
		_announce("leash", "制导修正")

	_announce_events(alt)


## 时间表倍率：`1 ± SCHED_SWING`。玩家把节流杆推到底可把整段压到 65%。
func schedule_factor() -> float:
	return clampf(1.0 + throttle_trim * SCHED_SWING, 1.0 - SCHED_SWING, 1.0 + SCHED_SWING)


## 手动模式下"杆 → 机身角速率"那一小段（制导模式不走这里）。
func _last_accel_dummy(pitch_in: float, yaw_in: float, dt: float) -> void:
	var axis := basis.x * pitch_in + basis.y * (-yaw_in)
	if axis.length_squared() < 1e-8:
		return
	basis = (Basis(axis.normalized(), MAX_RATE * dt * axis.length()) * basis).orthonormalized()
	global_transform = Transform3D(basis, global_position)


# ============================================================ 制导的几何

## 反重力方向 = 背离地球球心。地表图上球心在 6371 km 之下 ⇒ 退化成世界 +Y
##（在发射台处偏差 0.22°，可忽略）。
func _up_dir() -> Vector3:
	var c := Vector3(0.0, -LaunchScript.BODY_R, 0.0)
	var r := global_position - c
	return r.normalized() if r.length_squared() > 1.0 else Vector3.UP


func _down_dir() -> Vector3:
	return -_up_dir()


## 把机头（局部 −Z）朝 `want` 转，角速率受限。
##
## ⚠️ 转轴取 `nose × want` —— 两向量共线时它退化成零向量（火箭正对目标，
## 这正是常态），此时**什么都不做**。写成 `normalized()` 会在那里产出 NaN，
## 而 NaN 一旦进了 `basis`，整个变换矩阵烂掉、火箭从画面上消失且不报错。
func _align_to(want: Vector3, dt: float) -> void:
	var nose := -basis.z
	var axis := nose.cross(want)
	var sin_a := axis.length()
	if sin_a < 1e-5:
		return
	var ang := asin(clampf(sin_a, -1.0, 1.0))
	var step_ang := minf(ang * ATT_GAIN * dt, MAX_RATE * dt)
	if step_ang <= 0.0:
		return
	var q := Quaternion(axis / sin_a, step_ang)
	basis = (Basis(q) * basis).orthonormalized()
	global_transform = Transform3D(basis, global_position)


# ============================================================ 播报

func _announce(kind: String, text: String) -> void:
	if _announced.has(kind):
		return
	_announced[kind] = true
	event.emit(kind, text)


## 判据里的高度一律从 `LaunchScript` 取，**不在这里另写一个数**。
func _announce_events(alt: float) -> void:
	# ★ "出水"而不是"离塔"：`BREACH_ALT` = 海面。
	# 给 6 m 的余量不是保险 —— 箭底**正好**在 `y = 0` 那一帧，玩家从追尾镜
	# 看到的是"最后一注水正从箭体上流走"，那时候喊"出水"太早。
	if _was_submerged and alt > LaunchScript.BREACH_ALT + 6.0:
		_was_submerged = false
		_announce("breach", "出水")
	if alt > MAX_Q_ALT:
		_announce("maxq", "通过最大动压")
	if alt > LaunchScript.REVEAL_ALT:
		_announce("karman", "越过卡门线")
	if u >= 1.0:
		_announce("arrived", "抵达")


## 最大动压的高度（米）。**实测**出来的，不是拍的：
## `rho(alt)·v(alt)²` 在 12~13 km 取到峰值（速度的平方增长与密度的指数衰减
## 在这一带交叉）。与 `suite_rocket_launch` 里那条"最大动压落在 10~15 km"配套。
const MAX_Q_ALT := 12000.0


# ============================================================ 读数

## 阶段（HUD 与测试读同一个纯函数）。
func leg() -> int:
	return LaunchScript.leg_for(global_position.y, room_swapped)


func leg_name() -> String:
	return LaunchScript.leg_name(leg())


func mass() -> float:
	return MASS_DRY + fuel


func fuel_fraction() -> float:
	return fuel / FUEL0


## 机头相对水平面的仰角（度）。**读数用** —— 判"倒没倒"就靠它。
func pitch_deg() -> float:
	var nose := -basis.z
	return rad_to_deg(asin(clampf(nose.y, -1.0, 1.0)))


## 某个方向向量对应的高度角（度）。`cmd_pitch_deg` 用它算 ——
## 抽成静态函数是为了让"机身仰角"与"推力仰角"**用同一个公式**，
## 否则两个读数各写一遍 `asin` 的话，符号写反一处就永远看不出差。
static func thrust_pitch_of(dir: Vector3) -> float:
	return rad_to_deg(asin(clampf(dir.normalized().y, -1.0, 1.0)))


## 当前速度（m/s，真实）。
func speed() -> float:
	return velocity.length()


## 空速（km/h）。**鸭子类型契约** —— `ChaseCamera._update_fov()` 拿它算
## "随速度张开"的那一档视野。
##
## ★★ 2026-09-30 晚补上。此前 `RocketBody` **根本没有这个方法**，于是
## `_update_fov()` 里 `t.has_method("airspeed_kmh")` 为假 ⇒ `sp` 恒 0
## ⇒ 整段 60 s 上升的 FOV 恒等于 `base_fov` 68°，末段 35 km/s 一点广角都不张。
## 实测（`tools/_launch_fov_probe.gd` 的 `before_fov.csv`）：全程极差 **0.00°**。
##
## 公式与 `FlightModel.airspeed_kmh()` **逐字相同**（`speed * 3.6`）——
## 同一个物理量在两条机体链上不该有两个定义。
##
## ⚠️ 交出去的是**真实**空速，不是显示域（`display_speed()` 那一套）：
## 相机那条 `300 … 1900 km/h` 的窗口本来就是按"真实 m/s × 3.6"定的。
func airspeed_kmh() -> float:
	return speed() * 3.6


## 给相机的**速度项**（0…1）。`ChaseCamera._update_fov()` 优先用它（鸭子类型）。
##
## ★★ 为什么不能直接吃相机里那条通用窗口：那是**机体域**的
## `(kmh − 300) / 1600`，量程 300 … 1900 km/h。本箭末速
## `LaunchScript.END_SPEED_MS` = 35 000 m/s = **126 000 km/h**，高出两个数量级
## ⇒ 走通用窗口会在第 **8 s** 就顶到 90°，之后 **44 s 一动不动**
##（实测 `tools/_launch_fov_probe.gd` 的 `after_fov.csv`：FOV 恒 90°、
## 箭占屏高恒定 35.8%）。那是把"速度项是死的"换成了"速度项 3/4 时间不动"，
## **依然没有**速度感。
##
## ⇒ 这里给一条**对数**响应。对数不理会速度曲线自身的形状（本条曲线
## `u^3.64`，末段速度涨得极快），所以整段 60 s 是**连续**张开：
## 实测 FOV 68.0° → 79.8°，全程严格单调、无任何一帧触发上一层的 `clampf`。
##
## 归一化基准取 `LaunchScript.END_SPEED_MS`，**不在这里另写一个数**
##（与 `leg()` / `alt()` 那几条同一条规矩）。
## 渐近线 `FOV_MIX_MAX` 刻意留在 1.0 之下：贴到 1.0 就是"顶死"。
const FOV_MIX_REF_KMH := 300.0
const FOV_MIX_MAX := 0.55


func speed_fov_mix() -> float:
	var end_kmh := LaunchScript.END_SPEED_MS * 3.6
	var k := log(1.0 + airspeed_kmh() / FOV_MIX_REF_KMH) \
		/ log(1.0 + end_kmh / FOV_MIX_REF_KMH)
	return clampf(k, 0.0, 1.0) * FOV_MIX_MAX


## 当前速度（HUD 显示域）。全工程同一条规矩（`SuitProfile.speed_to_display`）。
func display_speed() -> float:
	return SuitProfile.speed_to_display(speed())
