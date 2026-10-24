## 巡航形态层：给「没有 blend shape 的新资产」补上巡航形态。
##
## ---- 为什么需要这个类（2026-09-26）----
##
## 上游 GUIDE §6.7 的架构约定是「**morph 管形态、骨骼管过程**」：
## 巡航形态（翼板/挂架/后挂架展开）本该由 `cruise_on` morph 负责，
## 待机动作 `fly` 只管呼吸微摆。工程侧 `_tick_cruise_morph()` 也是照这个写的
## （按住 Shift → `cruise_morph` 0→1 → 写 blend shape）。
##
## 但**交付的三件新 glb 里 blend shape = 0**（形态改由骨骼承载），于是：
##   * `_collect_morph_nodes()` 收不到任何网格 ⇒ 整条 morph 链**静默空转**；
##   * 而 `fly` 里对 **8 根长板**打了微摆 key ⇒ 单靠动作混合，巡航形态
##     会被这 8 根 key **压回常态位**（上游 PIPELINE §7.8 / §8.5 明确预警过）。
##
## ⇒ 本类就是 **`cruise_on` 的骨骼版**：在骨架求值链上，按 `cruise_morph`
##   把那 8 根形态骨从 `fly` 的姿态 slerp 到「巡航姿态」。
##
## ---- 为什么用 `SkeletonModifier3D` 而不是在 `_process` 里改骨 ----
##
## 玩家按住 Shift 的**整个时长**都是巡航形态（`fm.boosting`，见
## `FlightBody._tick_cruise_morph()`），不是开火瞬间 —— 这段叠加要跟
## `AnimationPlayer` 的每帧写入**争同一个字段**（`Skeleton3D` 的骨 pose）。
## `SkeletonModifier3D` 是引擎提供的正规插队点：`_process_modification()`
## 跑在「动画求值之后、生成 global pose 之前」，写进去的值一定生效、
## 且**每帧都从动画的原始值出发**（不会累积漂移）。
##
## ---- 形态骨是**自动挑**的，不硬编码 ----
##
## `setup()` 收两份基准（常态 / 巡航），自己算角度差，> `min_deg` 的才收。
## 换资产、换动作名都不用改这里。柯西实测：8 根（`RearHang.L/R` 141°/140°、
## `BinderBack.L/R` 108°/103°、`BinderFront.L/R` 90°/75°、`Wing.R/L` 90°/87°）。
class_name CruiseFormModifier
extends SkeletonModifier3D

## 叠加系数：0 = 常态形态（**完全空操作**），1 = 巡航形态。
## 由 `FlightBody._tick_cruise_morph()` 按 `cruise_morph_seconds` 推。
var morph := 0.0

## 形态骨下标与它们的**常态 / 巡航姿态**（局部旋转）。
##
## ★ `_normal` 是轮 42 加的：`FormWeld`（帧末焊）要算 `normal.slerp(cruise, t)`，
## **两端都得有基准**。原来的叠加语义只读「当前值」，用不到常态表。
var _idx: PackedInt32Array = PackedInt32Array()
var _normal: Array[Quaternion] = []
var _cruise: Array[Quaternion] = []

## 形态骨的**常态 / 巡航位置**（父空间局部位置），与 `_idx` / `_normal` / `_cruise`
## **同下标、等长**。★ N52 新增。
##
## ## 为什么位置也要有基准表
##
## 一个骨 pose = **T·R·S**。轮 42 的帧末焊只接管 R ⇒ 世界变换 = 旋转取焊缝 ＋
## 位移取动画。而这 8 根骨的「展开」**有一大半靠位移**（柯西 `RearHang.R` 两端差
## 1.1607 ≈ 118% 身高、`BinderBack.L` 0.3724）⇒ 只写旋转，那根骨就会
## **以展开的角度贴回常态位置**（玩家读作「翼关上了 / 飘到乱七八糟的地方」）。
##
## ⚠️ **留空 = 整条位置通路不启用**：老调用点没传位置表时，本类的行为与改动前
## **逐位相同**（`_process_modification()` 与 `weld()` 都判空后跳过位置分支）。
var _normal_pos: Array[Vector3] = []
var _cruise_pos: Array[Vector3] = []

## 最后写进去的形态角（读数/测试用）。morph=0 时不更新。
var last_applied_deg := 0.0

## `_process_modification()` 被引擎调用的次数（诊断用）。
##
## 存在的理由：这个回调**由引擎在骨架求值链上驱动**，而求值链是渲染端推的 ——
## 它在 headless（dummy renderer）下到底跑不跑，必须实测，不能假定。
## `calls == 0` 而形态没生效 ⇒ 时机问题（回调压根没被调）；
## `calls > 0` 而形态没生效 ⇒ 写入被覆盖了。两种根因修法完全不同。
var calls := 0

## 回调**内部读到**的第一根形态骨与巡航姿态的夹角（°）。
##
## ★ 这是「会不会漂移」的**唯一**可信读数。
##
## 帧边界用 `get_bone_pose_rotation()` 读到的永远是 `AnimationPlayer` 的原始值
##（详见 `_process_modification()` 里的说明），所以那里读不出漂移。
## 只有**在回调内部**记录"这次读到的 `cur` 离巡航多远"才能判断：
##   * 稳定不变 ⇒ 每帧都从动画原始值出发，正确；
##   * 逐帧单调减向 0 ⇒ 读到了自己上一帧写的值，帧内累积叠加（静默 bug）。
var read_residual_deg := 0.0


## `normal` / `cruise` 都是 `{骨名: Quaternion}`（局部旋转基准）。
## `normal_pos` / `cruise_pos` 都是 `{骨名: Vector3}`（局部位置基准）—— **可选**，
## 空表则位置通路整条不启用（见 `_normal_pos` 的注释）。
##
## ⚠️ 两张位置表**允许缺键**：缺的那一侧按 **`rest`（`get_bone_rest(bi).origin`）** 补
## （理由见循环里那段注释）。调用方不必先补全——"某条动作没写这根骨的位移轨"
## 本身就意味着它停在 rest。
##
## `min_deg`：判定「这根骨算形态骨吗」的门槛。0.5° 是柯西实测的天然分界
## （第 8 名 75.0°，第 9 名 < 0.5°），留得住信号、滤得掉噪声。
##
## ⚠️ 挑选（`min_deg`）**只看旋转差**：本类不应出现「第二处判据」。
## 一旦认定某根骨是形态骨，就**全分量接管**（旋转 + 位置）——
## 给同一根骨分别设两个门槛，正是「两处判据迟早打架」（N42·十二）的老路。
static func setup(skel: Skeleton3D, normal: Dictionary, cruise: Dictionary,
		min_deg := 0.5, normal_pos := {}, cruise_pos := {}) -> CruiseFormModifier:
	if skel == null or cruise.is_empty():
		return null
	var m := CruiseFormModifier.new()
	m.name = "CruiseFormModifier"
	var want_pos := not normal_pos.is_empty() and not cruise_pos.is_empty()
	for bone: String in cruise.keys():
		if not normal.has(bone):
			continue
		var bi := skel.find_bone(bone)
		if bi < 0:
			continue
		var q0: Quaternion = normal[bone]
		var q1: Quaternion = cruise[bone]
		if rad_to_deg(q0.angle_to(q1)) < min_deg:
			continue
		m._idx.append(bi)
		m._normal.append(q0)
		m._cruise.append(q1)
		if want_pos:
			# ★★ 位置表**按构造与 `_idx` 等长**：某侧没有这根骨的位置轨时用 **rest** 补。
			#
			# 为什么用 rest 而不是"缺就不记"：
			#   ① 一张位置表必须与 `_idx` **同下标**（下面按下标取），缺一格就是**整表错位**
			#      或（按下面的自检）**整表作废**——两种都是静默失效。
			#   ② "动画没写这根骨的位置轨"这件事**本身就是语义**：它的位置停在 rest
			#      （柯西 `fly` 是 POS 1 / ROT 26，唯一那条 POS 轨还不在形态骨上，
			#       所以常态一侧 8 根全靠这条补）。
			#   ③ 两端都补成同一个 rest ⇒ 该骨的位移项 `lerp(rest, rest, t)` = 恒等，
			#      等于"不干涉它的位置"，正是对一根位置不受形态影响的骨应有的行为。
			#
			# ⚠️ 本轮实测踩过的坑（T-新）：`Shoulder.L` 的旋转差 **4.00°** ≥ 0.5°
			#     ⇒ 它进了 `_idx`；但它在 `cruise_idle` 里**没有位置轨** ⇒ 旧写法
			#     `if ... and cruise_pos.has(bone)` 直接跳过 ⇒ 位置表 8 行 vs `_idx` 9 行
			#     ⇒ 触发下面「整表等长」自检 ⇒ `_normal_pos.clear()` ⇒
			#     `has_positions() == false` ⇒ **整条位置通路静默退回只焊旋转**。
			#     （而 `FormWeld` 会用 20° 门槛把 `Shoulder.L` 滤掉 ⇒ 两边表长天然不同，
			#       "在 CFD 里要求两侧都有、在 FormWeld 里又滤掉"是两处判据打架的雏形。）
			var rest_p := skel.get_bone_rest(bi).origin
			m._normal_pos.append(normal_pos.get(bone, rest_p) as Vector3)
			m._cruise_pos.append(cruise_pos.get(bone, rest_p) as Vector3)
	if m._idx.is_empty():
		# 一份形态骨都挑不出来 ⇒ 这个模型不需要形态层（老资产/无形态动作）。
		return null
	m.active = true
	m.morph = 0.0
	# 自检：`_idx` 与 `_cruise` 必须等长，否则下面按下标取会越界。
	if m._idx.size() != m._cruise.size():
		push_error("CruiseFormModifier: 下标表与姿态表长度不一致")
		return null
	# 位置表要么**整表等长**，要么**整表为空**（半张表 = 静默错位，宁可退回去）。
	# ★ N52 起这条**按构造必然成立**（循环里对每个进 `_idx` 的骨都补一格）——
	# 留着当防御性断言：一旦有人改回"缺就不 append"，这里会立刻变红而不是静默降级。
	if not m._normal_pos.is_empty() and m._normal_pos.size() != m._idx.size():
		push_error("CruiseFormModifier: 位置表与下标表长度不一致（%d vs %d）—— 退回只写旋转"
			% [m._normal_pos.size(), m._idx.size()])
		m._normal_pos.clear()
		m._cruise_pos.clear()
	return m


## 某根骨的**巡航姿态**（局部旋转）。不在形态骨里就返回当前姿态。
## 探针/测试要用它算"离巡航还有多远"。
func cruise_rotation_of(bone_idx: int) -> Quaternion:
	var i := _idx.find(bone_idx)
	if i < 0:
		return Quaternion.IDENTITY
	return _cruise[i]


## ---- 按**表内序号**取的三张表的只读访问器（轮 42）----
##
## `FormWeld` 建表时要并行遍历「下标 / 常态 / 巡航」三张表，所以需要按序号取。
## `cruise_rotation_of()` 收的是**骨下标**，语义不同 ⇒ 保留不动（测试在用）。

## 第 `i` 根形态骨的**骨下标**。越界返 -1（不崩）。
func bone_index_at(i: int) -> int:
	if i < 0 or i >= _idx.size():
		return -1
	return _idx[i]


## 第 `i` 根形态骨的**常态姿态**（局部旋转）= `FormWeld` 里 slerp 的起点。
func normal_rotation_at(i: int) -> Quaternion:
	if i < 0 or i >= _normal.size():
		return Quaternion.IDENTITY
	return _normal[i]


## 第 `i` 根形态骨的**巡航姿态**（与 `cruise_rotation_of(骨下标)` 同义）。
func cruise_rotation_at(i: int) -> Quaternion:
	if i < 0 or i >= _cruise.size():
		return Quaternion.IDENTITY
	return _cruise[i]


## ---- 位置表的只读访问器（★ N52）----
##
## `FormWeld` 借这两张表来**全分量接管**形态骨（旋转 + 位置）。
## 没有位置表（老调用点）时返 `Vector3.ZERO` —— 调用方必须先用 `has_positions()`
## 判断，否则会把骨写到原点（那正是 N47「归位把模型压垮」的同款事故）。

## 位置表是否可用（**整表等长**才算可用）。
func has_positions() -> bool:
	return not _normal_pos.is_empty() and _normal_pos.size() == _idx.size() \
		and _cruise_pos.size() == _idx.size()


## 第 `i` 根形态骨的**常态位置**（局部）。
func normal_position_at(i: int) -> Vector3:
	if i < 0 or i >= _normal_pos.size():
		return Vector3.ZERO
	return _normal_pos[i]


## 第 `i` 根形态骨的**巡航位置**（局部）。
func cruise_position_at(i: int) -> Vector3:
	if i < 0 or i >= _cruise_pos.size():
		return Vector3.ZERO
	return _cruise_pos[i]


## 形态骨名（读数/测试用）。
func form_bones(skel: Skeleton3D) -> Array[String]:
	var out: Array[String] = []
	if skel == null:
		return out
	for b in _idx:
		out.append(skel.get_bone_name(b))
	return out


func form_bone_count() -> int:
	return _idx.size()


## ★ 引擎的插队点：动画求值之后、global pose 之前。
##
## `morph <= 0` 时**一个字节都不写** —— 常态路径与「没有形态层」完全等价。
func _process_modification() -> void:
	calls += 1
	if morph <= 0.0 or _idx.is_empty():
		return
	var skel := get_skeleton()
	if skel == null:
		return
	var t := clampf(morph, 0.0, 1.0)
	var mx := 0.0
	for i in _idx.size():
		var b := _idx[i]
		# ⚠️ 这里读的必须是**动画刚写完的原始值**（不是上一帧我写的值）——
		# 靠的就是 `_process_modification()` 的执行时机。
		# 若时机不对，`t < 1` 时会**逐帧叠加漂移**（第 2 帧从第 1 帧的结果再 slerp）。
		# 判据见 `read_residual_deg`：它在帧间必须**稳定**。
		var cur := skel.get_bone_pose_rotation(b)
		var target: Quaternion = _cruise[i]
		var gap := rad_to_deg(cur.angle_to(target))
		if i == 0:
			read_residual_deg = gap
		mx = maxf(mx, gap)
		skel.set_bone_pose_rotation(b, cur.slerp(target, t))
		# ★ N52：**位置也一起接管**（前提是 `setup()` 收到了位置表）。
		#
		# 一个骨 pose = T·R·S：只写 R 就只剩「旋转是巡航、位置是动画」的混合变换，
		# 而这 8 根骨的展开有一大半靠平移 ⇒ 翼板会以展开的角度贴回常态位置。
		# 位置用 `lerp`（线性），旋转用 `slerp`（最短弧）—— 两者的插值语义不同，
		# 逐分量选各自正确的那个，不要图省事用同一个。
		if not _normal_pos.is_empty():
			var cp := skel.get_bone_pose_position(b)
			skel.set_bone_pose_position(b, cp.lerp(_cruise_pos[i], t))
	last_applied_deg = mx


## 当前形态骨的「离巡航姿态还差多少度」（读数用）。morph=1 时应当收敛到 0。
func residual_deg(skel: Skeleton3D) -> float:
	if skel == null or _idx.is_empty():
		return 0.0
	var mx := 0.0
	for i in _idx.size():
		mx = maxf(mx, rad_to_deg(skel.get_bone_pose_rotation(_idx[i]).angle_to(_cruise[i])))
	return mx
