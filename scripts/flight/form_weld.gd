class_name FormWeld
extends RefCounted
## 形态骨的「**帧末焊**」—— 轮 42 定下的形态唯一写入者。
##
## ## 为什么需要它（三条实测结论，缺一条这个类都不成立）
##
## 轮 42 的两支探针把柯西的形态链量穿了
##（`tools/probe_wing_tracks.gd` / `probe_form_layer_vs_anim.gd` /
## `probe_form_weld_timing.gd`，读数见 `_r42/pwt_BEFORE.txt`、`_r42/pfl_3.txt`、
## `_r42/pfwt_1.txt`）：
##
## 1. **方向动作族全都带 8 根形态骨的轨道、姿态 = 常态**
##    （`dash_*` / `fly_*` / `turn_*`：10/10 个动作、80/80 个骨-动作对）。
##    ⇒ 一按方向键就离开 `cruise_idle`，背后的翼立刻被写回「关」。
## 2. **`SkeletonModifier3D` 这条路走不通**：`morph = 1` 时帧末读到的仍是常态
##    （141.30°），**把那些轨道 `track_set_enabled(false)` 关掉，读数一模一样**
##    ⇒ 动画求值链在形态层之后**无条件重写**这批骨。
##    换言之：形态层（`CruiseFormModifier` / `FormCurveModifier`）对
##    **有动画在播**的机体是**结构性地**无效，不是参数没调对。
## 3. **唯一可靠的落点是「动画求值刚写完」那一刻** = `AnimationMixer.mixer_applied`：
##    `_process()` 里写 ✗（父节点的 `_process` 早于子节点的 `AnimationPlayer`，实测）、
##    `call_deferred()` ✗、`SceneTree.process_frame` **只会骗过局部 pose 读数** ✗、
##    **`mixer_applied` ✓**。
##
## ### ★ 踩过的坑：`process_frame` 那条路会给出**假绿**
##
## 在 `SceneTree.process_frame` 信号之后写骨、然后**立刻**读
## `get_bone_pose_rotation()`，读到的确实是刚写进去的巡航姿态（0.00°）——
## 探针 `tools/probe_form_weld_timing.gd` 的 W3 相位据此判「有效」。
## 但**渲染**不是从那一刻取数据的：真机出图（`tools/form_weld_shot.gd`）里
## 「按前进 + 焊接」与「按前进 + 不焊接」**两格的投影面积逐位相同（10.66%）**
## ⇒ 屏幕上的翼**根本没展开过**。
##
## **教训**：判「某个骨姿态有没有生效」，读数必须落在**渲染结果**上（像素）；
## 只读局部 pose 不行 —— 那是渲染的**输入**，不是输出。
## 这条与轮 41 的「眼见不能当证据」是一体两面：**读数必须落在真正被消费的那一层。**
##
## ⇒ 本类就是第 3 条的载体：**每帧在 `AnimationMixer.mixer_applied` 信号之后
##   （= 动画求值刚写完那一刻），按 `cruise_morph` 把那几根形态骨绝对写到
##   `normal.slerp(cruise, morph)`。**
##
## ## 为什么必须**绝对写**（不能像 `CruiseFormModifier` 那样"读当前值再 slerp"）
##
## 叠加语义依赖「动画每帧提供一个常态输入」这件事。而本类生效的场合**恰恰是
## 动画在写别的姿态**（冲刺动作）—— 此时把冲刺姿态当起点 slerp，`morph` 只要不精确
## 等于 1 就收敛不到巡航；`morph` 回到 0 时更**没有任何东西**能把它拉回常态
##（实测：轨道开 + `morph = 0`，读数仍是 141.30°，翼收不回去）。
## ⇒ 唯一自洽的写法是 `normal.slerp(cruise, t)`：**两端都由基准钉死，与动画无关。**
##
## ## 形态骨清单从哪来
##
## **不在这里挑骨名** —— 骨名由 `CruiseFormModifier.setup()`（门槛 0.5°）挑好，本类只**借**它的表。
## 理由：筛选判据只应存在于**一处**。两处判据迟早打架，而"两处判据打架"
## 正是 N42·十二「半升级」那类静默故障的成因。
##
## ## 但**门槛**要更高：`WELD_MIN_DEG = 20°`（默认）
##
## ⚠️ 这不是"第二处判据"，而是**另一件事**：形态层是**叠加**（只在自己 morph>0 时插一脚），
## 而焊接是**覆盖**（从此刻起这根骨的动作全被盖掉）。对一根只差 4° 的骨来说，
## 覆盖的代价（冻结它在**所有**动作里的运动）远大于收益（4° 的形态差根本看不出来）。
## 柯西实测：`Shoulder.L` 差 **4.00°**，其余 8 根从 **75.0°** 起
##（`_r42/pwt_BEFORE.txt`）⇒ 20° 落在两者之间，余量一个半数量级。
## 被滤掉的骨会记进 `skipped`，不静默。
##
## ## 逐帧回读得出的读数（回归判据用）
##
## `weld()` 是**纯函数式**的：给定 `morph` 写什么完全确定，**不读任何当前值**。
## ⇒ 测试里同步调一次、立刻回读 `residual_deg()`，拿到的值与"帧末被引擎驱动"时
## **逐位相同**，时机问题被绕开 ⇒ 它可以当**自动化**判据，不必只靠探针截图。

## 焊接门槛（°）。见文件头「门槛要更高」一段：焊接是**覆盖式**的，
## 不值得为一根 4° 的骨冻结它的全部动作。
const WELD_MIN_DEG := 20.0

## 焊接目标骨架。**弱引用式的裸引用** —— `_release_model_anim()` 里必须 `detach()`，
## 否则 `model_pivot.free()` 之后这里就是野引用（而它每帧都要读）。
var _skel: Skeleton3D

## 形态骨的**骨下标**，与下面两张姿态表**一一对应、等长**。
var _idx: PackedInt32Array = PackedInt32Array()
## 每根形态骨的**常态**姿态（局部旋转）= slerp 的起点。
var _normal: Array[Quaternion] = []
## 每根形态骨的**巡航**姿态（局部旋转）= slerp 的终点。
var _cruise: Array[Quaternion] = []

## 每根形态骨的**常态 / 巡航位置**（父空间局部位置）= lerp 的两端。★ N52 新增。
##
## ## 为什么必须补这一半
##
## 一个骨 pose = **T·R·S**。本类自称这几根骨的「唯一写入者」，但此前**只写 R**
## ⇒ 世界变换 = **旋转取焊缝 ＋ 位移取动画**。
## 而这 8 根骨的「展开」**有一大半靠位移**：
##
## | 骨 | 常态→巡航 位移差（模型本地） | 占身高 |
## |---|---|---|
## | `RearHang.R` | **1.1607** | **118%** |
## | `RearHang.L` | 0.9876 | 101% |
## | `BinderBack.L` / `.R` | 0.3724 / 0.2800 | 38% / 29% |
## | `Wing.L` / `.R` | 0.1119 / 0.1117 | 11% |
## | `BinderFront.L` / `.R` | 0.0953 / 0.0776 | 10% / 8% |
##
## ⇒ 一按方向键（`dash_*` / `fly_*` 的 translation 轨**恒定写在常态位置**），
## 位置就被写回常态、而旋转仍焊在巡航 ⇒ 翼板「以展开的角度贴回机体」
## = 用户报的「按哪个键都会关上飞行翼」。
## 变形过程中按方向键同理：位置在 6 帧内从巡航位置滚回常态位置（跨 27 单位）。
##
## **可证伪**：写进位置后，`morph = 1` 时这几根骨的 `get_bone_pose_position()`
## 必须等于巡航基准（`_r42` 判据图那条「形态骨局部旋转」是**循环自证**，看不见这个洞）。
##
## ⚠️ 留空（`pick` 没有位置表）⇒ 位置分支整条跳过，行为与改动前**逐位相同**。
var _normal_pos: Array[Vector3] = []
var _cruise_pos: Array[Vector3] = []

## ---- ★★ N55：**祖先闭包**（第二条轴 = 层级，见 `weld()` 里那段长注释）----
##
## 上面那几张表是「**形态骨自己**」。而一根骨的世界变换 =
## **自身局部 TRS**（上面这几张表管住了 ✓） × **祖先链姿态**（谁在管？）。
##
## 实测（`tools/probe_xi_wing_world.gd` §0c）：那 8 根形态骨分别挂在
## `Chest` / `Shoulder.L` / `Shoulder.R` / `Hips` 下，而 16 段方向动作
## **把这几根父骨写成常态**（`Chest` 6.07° / `Spine` 5.73° / `Hips` 18.09°
## / `Shoulder.L/R` −77.81°，而巡航位是 1.07 / −0.27 / 4.09 / −81.54）
## ⇒ 翼板被整条父链拖着走：**抬起 20% 身高、总位移 26% 身高**。
##
## 闭包 = 从每根形态骨沿 `Skeleton3D.get_bone_parent()` 上溯，凡「常态↔巡航有差」
## 的祖先全部纳入。柯西实测 **5 根**（`Shoulder.L` / `Shoulder.R` / `Chest` /
## `Spine` / `Hips`）⇒ 8 + 5 = **13**。`Root` 差 0.00° ⇒ 自动排除。
## ★ 走父链算 ⇒ **换资产不用改代码**；「闭包」这件事只能有一个真源。
var _anc_idx: PackedInt32Array = PackedInt32Array()
var _anc_normal: Array[Quaternion] = []
var _anc_cruise: Array[Quaternion] = []
var _anc_normal_pos: Array[Vector3] = []
var _anc_cruise_pos: Array[Vector3] = []

## 祖先骨名（诊断 / 测试用；**不静默**）。
var ancestors: Array[String] = []

## ★ 运行时总开关（**A/B 证伪条**用）：`false` ⇒ 祖先写入整条跳过，
## 行为与改动前**逐位相同**。存在它的唯一目的 = 让「这条判据抓得住这个缺陷」
## 可以被**跑出来**（把修好的那一行做成一开关），而不是靠读代码相信。
var ancestors_enabled := true

## 纳入祖先的门槛（°／模型本地单位）。取得很小：**「有差」就纳入** ——
## 祖先骨的代价与形态骨不同（它不"展开"，只是"要不要把父链钉住"），
## ⛔ 别拿形态骨那个 20° 门槛来这里比（那是按**自身旋转差**挑骨的判据，
## 混用会把 `Shoulder.L`（4.00°）这类**父骨**再次滤掉）。
const ANCESTOR_MIN_DEG := 0.05

## 被 `WELD_MIN_DEG` 门槛滤掉的骨名（诊断用；**不静默**）。
var skipped: Array[String] = []

## `weld()` 累计被调用的次数（诊断 / 测试用）。
var welds := 0
## ★ N55：**祖先骨真的被写**的累计次数（诊断）。与 `welds` 分开计数的理由：
## 门控② 的判据正是「`State.FORM` 窗口内祖先写入应当**零增量**」—— 若拿 `welds` 当判据，
## 形态骨每帧照写 ⇒ 读数永远在涨 ⇒ 判据恒真（T35）。
var ancestor_writes := 0
## 最后一次焊接写进去的、**离巡航**的最大夹角（°）。诊断用。
var last_applied_deg := 0.0
## 最后一次焊接写进去的、**离巡航位置**的最大距离（世界单位）。诊断用。★ N52
var last_applied_pos := 0.0


## 从 `CruiseFormModifier` **借**已挑好的形态骨表建载体。
##
## 返回 null 的三种情况都是**正常边界**（不告警）：
## `skel` / `pick` 为空、形态骨表为空、三张表长度对不上（后者是内部错误，会 `push_error`）。
static func setup(skel: Skeleton3D, pick: CruiseFormModifier, min_deg := WELD_MIN_DEG,
		anc_normal := {}, anc_cruise := {}, anc_normal_pos := {}, anc_cruise_pos := {}) -> FormWeld:
	if skel == null or pick == null:
		return null
	var n := pick.form_bone_count()
	if n <= 0:
		return null
	var w := FormWeld.new()
	w._skel = skel
	# ★ N52：位置表能不能借到，决定要不要**全分量接管**（见 `_normal_pos` 注释）。
	# `CruiseFormModifier.setup()` 只在**两张位置表都齐**时才会带上位置表。
	var with_pos := pick.has_positions()
	for i in n:
		var bi := pick.bone_index_at(i)
		if bi < 0:
			continue
		var q0 := pick.normal_rotation_at(i)
		var q1 := pick.cruise_rotation_at(i)
		if rad_to_deg(q0.angle_to(q1)) < min_deg:
			# 差得太小 ⇒ 覆盖它不划算（见文件头）。如实记下来，别静默。
			w.skipped.append(skel.get_bone_name(bi))
			continue
		w._idx.append(bi)
		w._normal.append(q0)
		w._cruise.append(q1)
		if with_pos:
			w._normal_pos.append(pick.normal_position_at(i))
			w._cruise_pos.append(pick.cruise_position_at(i))
	if w._idx.is_empty():
		return null
	if w._idx.size() != w._normal.size() or w._idx.size() != w._cruise.size():
		push_error("FormWeld: 下标表 / 常态表 / 巡航表长度不一致")
		return null
	# 位置表要么**整表等长**，要么**整表为空**（半张表 = 静默错位）。
	if not w._normal_pos.is_empty() and w._normal_pos.size() != w._idx.size():
		push_error("FormWeld: 位置表与下标表长度不一致（%d vs %d）—— 退回只焊旋转"
			% [w._normal_pos.size(), w._idx.size()])
		w._normal_pos.clear()
		w._cruise_pos.clear()
	# ---- ★★ N55：建**祖先闭包**表（不传 `anc_*` ⇒ 整条跳过，行为与改动前逐位相同）----
	if not anc_normal.is_empty() and not anc_cruise.is_empty():
		w._build_ancestors(skel, anc_normal, anc_cruise, anc_normal_pos, anc_cruise_pos)
	return w


## 采集「形态骨的祖先闭包」，并备好它们的两套基准。★ N55
##
## ## 判据只有一条：**在闭包里 ＋ 常态↔巡航有差**
##
## ⛔ 这不是「第二处挑骨判据」（N42·十二）：形态骨由**旋转差 ≥ `min_deg`** 挑
##（`CruiseFormModifier.setup()`，那一条仍然只有一处）；本函数挑的是**另一件事** ——
## 「谁是这几根骨的祖先」。两者**必须**不同，否则就是 N55·T53 那个洞：
## 按**自身旋转差**挑骨，天然会漏掉**自身差小、却是别人父骨**的骨
##（`Shoulder.L` 只差 4.00°，被 20° 门槛滤掉，而它是 4 根挂架骨的直接父骨）。
##
## ## 位置一侧：缺轨 ⇒ 用 `rest` 兜底（与 `CruiseFormModifier.setup()` 同一条规则）
##
## `fly` 只带 1 条位置轨（`Hips`）⇒ `Chest`/`Spine`/`Shoulder.*`/`Root` 的**常态位置**
## 只能取 `get_bone_rest().origin`；而"动画没写这根骨的位置轨"**本身就是语义**
##（它停在 rest）。巡航一侧由调用方给全（`form_on` 末帧是 51/51）。
func _build_ancestors(skel: Skeleton3D, anc_normal: Dictionary, anc_cruise: Dictionary,
		anc_normal_pos: Dictionary, anc_cruise_pos: Dictionary) -> void:
	var mine := {}
	for bi in _idx:
		mine[bi] = true
	var with_pos := not anc_normal_pos.is_empty() and not anc_cruise_pos.is_empty()
	var seen := {}
	for bi in _idx:
		var cur := bi
		while true:
			# T37：关键 API 当轮实测（`get_bone_parent()` 是 Skeleton3D 的公开方法）。
			var par: int = skel.get_bone_parent(cur)
			if par < 0:
				break
			if not seen.has(par):
				seen[par] = true
				if not mine.has(par):
					var nm := skel.get_bone_name(par)
					if anc_normal.has(nm) and anc_cruise.has(nm):
						var q0: Quaternion = anc_normal[nm]
						var q1: Quaternion = anc_cruise[nm]
						var rest_p := skel.get_bone_rest(par).origin
						var p0: Vector3 = anc_normal_pos.get(nm, rest_p) if with_pos else rest_p
						var p1: Vector3 = anc_cruise_pos.get(nm, rest_p) if with_pos else rest_p
						# 「有差」才纳入：没差的骨写进去是纯开销（还多冻结一根骨）。
						var dq := rad_to_deg(q0.angle_to(q1))
						var dp := p0.distance_to(p1)
						if dq >= ANCESTOR_MIN_DEG or dp >= 1.0e-5:
							_anc_idx.append(par)
							_anc_normal.append(q0)
							_anc_cruise.append(q1)
							if with_pos:
								_anc_normal_pos.append(p0)
								_anc_cruise_pos.append(p1)
							ancestors.append(nm)
			cur = par
	if not _anc_normal_pos.is_empty() and _anc_normal_pos.size() != _anc_idx.size():
		push_error("FormWeld: 祖先位置表与下标表长度不一致（%d vs %d）—— 祖先退回只焊旋转"
			% [_anc_normal_pos.size(), _anc_idx.size()])
		_anc_normal_pos.clear()
		_anc_cruise_pos.clear()


## 解绑骨架。`FlightBody._release_model_anim()` 里**必须**调。
func detach() -> void:
	_skel = null


## 焊接是否还挂在活着的骨架上（诊断用）。
##
## 存在的理由：`detach()` 之后 `residual_deg()` 会返回 0.0（读不到骨架就返回默认值），
## 而 0.0 恰好等于「焊得很完美」的读数 —— 一个**看起来成功、实际停摆**的值。
## 出图/探针拿它当关卡，免得把「停摆」读成「成功」。
func attached() -> bool:
	return _skel_alive()


func form_bone_count() -> int:
	return _idx.size()


## 形态骨名（诊断 / 测试用）。骨架已失效时返回空表，不崩。
func form_bones() -> Array[String]:
	var out: Array[String] = []
	if not _skel_alive():
		return out
	for b in _idx:
		out.append(_skel.get_bone_name(b))
	return out


## ★ 焊接本体：按 `morph` 把形态骨**绝对**写到 `normal.slerp(cruise, morph)`。
##
## ⚠️ 调用时机**必须**是动画求值刚写完那一刻（`AnimationMixer.mixer_applied` 信号）——
## 理由见文件头第 3 条。在 `_process()` / `call_deferred()` / `process_frame` 里调
## 都留不住（前两者连读数都不变，后者只骗得过读数、骗不过渲染）。
##
## ⚠️ `morph <= 0` **也要写**（写常态）：本类是这几根骨的**唯一**写入者，
## "不写"等于把它们丢给上一个动作 ⇒ 退出巡航时翼收不回去。
##
## ## ★★ N55：`ancestors_ok` —— **祖先骨只在"形态真的展开着"的窗口里写**
##
## 本体（形态骨）与祖先骨的门控**故意不对称**：
##
## | 骨组 | `morph == 0` 时 | 为什么 |
## |---|---|---|
## | 形态骨（8 根） | **照写常态** | 它们本来就没有别的主人（见上面那条 ⚠️） |
## | 祖先骨（闭包） | **一个字节都不写** | 它们**有**主人：当前在播的动作。写 = 把躯干钉死 |
##
## ⛔ **这是本方案最大的坑**（门控①）：一旦祖先骨在 `morph == 0` 时也被写，
## **全部非巡航动作的躯干会被钉死在常态基准上**（腿臂照动、腰胸不动，观感极怪），
## 而**不会有任何报错**。守卫判据见探针的「非巡航零回归指纹」
##（`tools/probe_xi_wing_world.gd` §4 / 测试 `_n55_*`）：改动前后必须**逐位相同**。
##
## `ancestors_ok = false` = **门控②**（`State.FORM` 窗口内祖先退位）：变形动作本体
##（`form_on` / `form_off`）是作者定义的「常态 ↔ 巡航」完整过渡（51 轨全骨），
## 由它主导那几根祖先骨才是对的 —— 焊缝去覆盖它，就是 N52·R2「两条时间轴不同步」
## **搬到躯干上**。★ 这一条与 N52 遗留的 S3（方案 B）是**同一件事**，合并落地。
func weld(morph: float, ancestors_ok := true) -> void:
	welds += 1
	if not _skel_alive() or _idx.is_empty():
		return
	var t := clampf(morph, 0.0, 1.0)
	var has_pos := not _normal_pos.is_empty()
	var mx := 0.0
	var mp := 0.0
	for i in _idx.size():
		var q: Quaternion = _normal[i].slerp(_cruise[i], t)
		_skel.set_bone_pose_rotation(_idx[i], q)
		mx = maxf(mx, rad_to_deg(q.angle_to(_cruise[i])))
		# ★★ N52：**位置与旋转一起写** —— 本类是这几根骨的唯一写入者，
		# 「只写一半」就不叫接管（与 T34「pose 是绝对局部变换，不是相对 rest 的偏移」
		# 同族：只接管一部分，就不叫接管）。
		if has_pos:
			var p: Vector3 = _normal_pos[i].lerp(_cruise_pos[i], t)
			_skel.set_bone_pose_position(_idx[i], p)
			mp = maxf(mp, p.distance_to(_cruise_pos[i]))
	last_applied_deg = mx
	last_applied_pos = mp
	# ---- ★ N55 祖先闭包：① 运行时开关 ② 门控①（`t > 0`） ③ 门控②（调用方给的 `ancestors_ok`）----
	if not ancestors_enabled or not ancestors_ok or t <= 0.0 or _anc_idx.is_empty():
		return
	ancestor_writes += 1
	var has_anc_pos := not _anc_normal_pos.is_empty()
	for i in _anc_idx.size():
		_skel.set_bone_pose_rotation(_anc_idx[i], _anc_normal[i].slerp(_anc_cruise[i], t))
		if has_anc_pos:
			_skel.set_bone_pose_position(_anc_idx[i],
				_anc_normal_pos[i].lerp(_anc_cruise_pos[i], t))


## 当前形态骨「离巡航姿态还差多少度」—— **只读**，供测试/探针判定"这一帧焊成什么样了"。
## `morph = 1` 时应为 0；`morph = 0` 时应 ≈ 两基准的夹角（柯西 141.30°）。
func residual_deg() -> float:
	if not _skel_alive() or _idx.is_empty():
		return 0.0
	var mx := 0.0
	for i in _idx.size():
		mx = maxf(mx, rad_to_deg(_skel.get_bone_pose_rotation(_idx[i]).angle_to(_cruise[i])))
	return mx


## 当前形态骨「离**巡航位置**还差多少」（世界单位）。★ N52 —— **只读**，供测试/探针使用。
##
## ⚠️ 位置表未启用时返 **-1.0**（**不伪装成 0**）。理由同 `attached()`：
## `0.0` 恰好等于「焊得很完美」的读数，一个**看起来成功、实际停摆**的值
## —— 出图/探针必须能用它当关卡。
func residual_pos() -> float:
	if not _skel_alive() or _idx.is_empty() or _normal_pos.is_empty():
		return -1.0
	var mx := 0.0
	for i in _idx.size():
		mx = maxf(mx, _skel.get_bone_pose_position(_idx[i]).distance_to(_cruise_pos[i]))
	return mx


## 位置通路是否启用（`morph = 1` 时位置真的会被写到巡航）。★ N52
func has_positions() -> bool:
	return not _normal_pos.is_empty() and _normal_pos.size() == _idx.size()


## ---- 祖先闭包的诊断访问器（★ N55）----
##
## ⚠️ `ancestor_count()` 返回 0 有两种成因，**读数一样**（N53·T47 同族）：
##   ① 调用方没传 `anc_*` 基准（老调用点）② 闭包算出来是空。
## `ancestors`（骨名表）能把它们分开：空表 = 没纳入任何骨。
func ancestor_count() -> int:
	return _anc_idx.size()


## 祖先骨名（骨架已失效时返回空表，不崩）。
func ancestor_bones() -> Array[String]:
	return ancestors


func has_ancestors() -> bool:
	return not _anc_idx.is_empty()


## 祖先骨的位置通路是否启用。
func ancestors_have_positions() -> bool:
	return not _anc_normal_pos.is_empty() and _anc_normal_pos.size() == _anc_idx.size()


## 当前祖先骨「离**巡航姿态**还差多少度」—— **只读**。
## `morph = 1` 且祖先写入开着时应为 0；祖先写入关掉时 ≈ 两基准的夹角（柯西 `Hips` 14.01°）。
func residual_ancestor_deg() -> float:
	if not _skel_alive() or _anc_idx.is_empty():
		return 0.0
	var mx := 0.0
	for i in _anc_idx.size():
		mx = maxf(mx, rad_to_deg(_skel.get_bone_pose_rotation(_anc_idx[i]).angle_to(_anc_cruise[i])))
	return mx


## 骨架还活着吗。`free()` 过的节点用 `is_instance_valid` 判——
## `model_pivot.free()` 之后这个判据会翻成 false，焊接随即静默停摆（而不是崩）。
func _skel_alive() -> bool:
	return _skel != null and is_instance_valid(_skel)
