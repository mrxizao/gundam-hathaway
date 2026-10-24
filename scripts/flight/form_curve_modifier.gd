## 形态曲线层：把巡航变形从「两点匀速 slerp」升级为「按一条变形曲线演出」。
##
## ---- 它解决什么（2026-09-27 · N42·十三）----
##
## `CruiseFormModifier` 的形态是**两点线性插值**：
##     形态骨 quat = slerp( `fly`首帧 , `burst_cruise`末帧 , morph )
## ⇒ 6 根翼板**同时、匀速**弹开。用户实测感受是「巡航模式太丑」——
##   不是方向错，是**没有过程**（像瞬间弹开，而不是"变形"）。
##
## 而交付目录里本来就有一条**逐帧的变形演出** —— 棒 7 交付的**契约动作**：
##     `xi_cruise_on.glb`（「巡航变形」，14 帧 / **0.4333 s** ≈ `cruise_morph_seconds` 0.45）
## 实测它的**首帧 = 常态、末帧 = 巡航**（6 根形态骨最大偏差 0.046° / 0.110°）
## ⇒ 它就是**同一条变形的连续版**，且：
##     * ★ **6 根形态骨同步展开**（首动归一化进度**全部 0.15**、两族差 **0.00**）
##       —— 用户 2026-09-27 明确要求「后翼下方大片翼**跟着**上方的小翼**一起**展开」；
##     * 时间轴**免归一化**（0.4333 vs 0.45）；**50 骨 / v14** ⇒ 不受半升级影响。
## ⛔ 早先沿 `xi_morph_anim3.glb`（107 点 / 4.42 s，**v12 骨架**）是**分段**的
##   （`Wing*` 迟至 0.63 才动、两族差 0.50）—— 那是 v1.1 示范动画自己的编排，已弃用。
##
## 本类就是那条曲线的**执行器**：仍然由 `cruise_morph` 0→1 驱动，
## 但形态骨不再是「朝终点插值」，而是「**沿着曲线上的位置走**」。
## 于是「按住 Shift」看到的是：6 根翼板**一起**展开，两端慢、中间快（缓动）。
##
## ---- 与 `CruiseFormModifier` 的关系：**平行，替代，不修改** ----
##
## * 两者**同判据**挑形态骨（`fly`首帧 vs `burst_cruise`末帧，差 > `min_deg`）
##   ⇒ 挑出来的一定是**同 6 根**，零语义分歧。
## * 本类可用时**替代**它（`FlightBody._setup_cruise_form()` 里二选一），
##   不可用时**回退**到它。**绝不并存** —— 两个 `SkeletonModifier3D` 写同一批骨
##   会按子节点顺序互相覆盖（后者从前者的结果再插值），行为不可预测。
## * `CruiseFormModifier` 一行不改：它已经是验证过的回退路径。
##
## ---- 为什么时间要**归一化**（morph 直接当进度条）----
##
## 曲线本身 4.42 s，而 `cruise_morph_seconds` 是 **0.45 s**。
## 若按 `t = morph × 4.42 s` 播，玩家按满 Shift 时曲线只走到 **10%**
## ⇒ 形态几乎没展开（这是最容易踩的坑：数值全对、效果全无）。
## ⇒ 本类把 `morph ∈ [0,1]` 映射到曲线的**归一化位置**，
##   让整段演出在 `cruise_morph_seconds` 内**压缩**播完。
##   节奏（先 Binder 后 Wing）完整保留，只是整体变紧凑。
##
## ★★ 而且归一化必须按**真实时间轴**，不能按「关键帧下标 / 各自帧数」。
##
## Godot 导入器对 CUBICSPLINE 会**抽稀**：某根骨姿态恒定的那一段，几十个采样点
## 被压成首尾两点。后果是**各骨的关键帧数不同、且不再等间隔**。
## 若按"下标 ÷ 各自帧数"归一化，各骨的节奏就**各自错位** —— 实测踩到过：
## 按下标取，`Wing.L` 在 `morph=0.25` 已经转了 **12.19°**；
## 而按真实时间取，它那一刻应当是 **0**（它前半段本来一动都不动）。
## ⇒ 本类一律用 `t = lerp(t0, t1, morph)` 在**各自的时间轴**上取样，
##   各骨于是共享同一条真实时间 ⇒ 「先 Binder、后 Wing」的节奏才是真的。
##
## ---- 为什么继承 `SkeletonModifier3D` ----
##
## 同 `CruiseFormModifier`：这个叠加要跟 `AnimationPlayer` 的**每帧写入**争
## `Skeleton3D` 的骨 pose。`_process_modification()` 跑在「动画求值之后、
## 生成 global pose 之前」，是引擎提供的正规插队点 —— 写进去一定生效，
## 且**每帧都从动画的原始值出发**（不会帧内累积）。
##
## ---- 端点自检：这条曲线跟本工程是不是同一套 ----
##
## `setup()` 会逐骨核对「曲线首帧 vs 常态基准」「曲线末帧 vs 巡航基准」，
## 超过 `end_tol_deg` 就**整层放弃**（返回 null ⇒ 上层回退两点层）。
##
## ★ 为什么必须自检：任何曲线源都可能与主模型**不同代**。本工程踩过
##   「一端升了、一端没升」的静默故障（N42·十二：v12/v14 混用 ⇒ 形态骨
##   误判 8→10 根、后挂架旋转落错父级，**完全不报错**）。
##   当前源 `xi_cruise_on.glb` 是 **50 骨 / v14**、与主模型同代，
##   但这是**实测结论**，不是可以假定的前提 —— 换资产、换骨架必须重跑自检。
##   这类故障只有端点比对拦得住。
class_name FormCurveModifier
extends SkeletonModifier3D

## 形态进度：0 = 常态（**完全空操作**），1 = 巡航形态。
## 由 `FlightBody._tick_cruise_morph()` 按 `cruise_morph_seconds` 推。
var morph := 0.0

## 形态骨下标；`_frames[i]` = 第 i 根骨的关键帧姿态，`_times[i]` = 对应时间。
##
## ⚠️ **绝不拿下标当进度轴**：Godot 抽稀后各骨帧数不同、间隔不等（见类头那段）
## ⇒ 一律按**时间**取值，这样各骨才共享同一条真实时间轴。
var _idx: PackedInt32Array = PackedInt32Array()
var _frames: Array = []
var _times: Array = []
## 曲线源的真实时间范围（各骨时间轴的并集）。`t = lerp(_t0, _t1, morph)`。
var _t0 := 0.0
var _t1 := 1.0
## 在变形动画里**没有独立曲线**、退回两点线性的骨名（读数用）。
## 正常情况应为空：柯西实测 6 根形态骨在 `cruise_on` 里都有轨道。
var fell_back: PackedStringArray = PackedStringArray()

## 各形态骨关键帧数的最小值（读数用；各骨差异大说明抽稀幅度不同）。
var key_count := 0
## 端点自检的最大偏差（°）：曲线首/末帧 vs 常态/巡航 基准。
##
## ⚠️ **这个读数有 ~0.04° 的 float32 噪声底，别拿它当「< 0.001°」的判据**：
##   `Quaternion.angle_to()` 内部是 `acos(2d²−1)`，而 `d = dot(q,q)` 在 float32 下是
##   `1 − 1.2e-7` ⇒ `acos(1 − 2.4e-7)` = **0.0396°**。
##   **同一个四元数自比也有这个读数**（2026-09-27 实测：合成骨端点完全吻合，仍读到 0.0396°）。
## ⇒ 本字段的**真判据是 `end_tol_deg = 2.0`**（50 倍于噪声底，柯西实测 0.116° / 0.110°）；
##   要断言「端点真的吻合」请用**四元数恒等**（`is_equal_approx`），不要用角度容差。
var endpoint_max_deg := 0.0

## `_process_modification()` 被引擎调用的次数（诊断用，同 `CruiseFormModifier`）。
var calls := 0
## 回调**内部读到**的第一根形态骨与当前曲线目标的夹角（°）。
##
## ★ 这是「会不会漂移」的唯一可信读数：固定 `morph` 下它必须**稳定**。
##   帧边界用 `get_bone_pose_rotation()` 读到的永远是 `AnimationPlayer` 的原始值，
##   读不出漂移；只有回调内部读到的这个值逐帧单调减小才说明发生了帧内累积。
var read_residual_deg := 0.0
## 最后一次写进去的最大夹角（°）。
var last_applied_deg := 0.0


## `normal` / `cruise` = 常态 / 巡航基准（`{骨名: Quaternion}`）；
## `curve` = 变形曲线（`{骨名: Array[Quaternion]}`，逐帧等间隔）。
##
## * `min_deg`：挑形态骨的门槛（**与 `CruiseFormModifier` 同判据**，保证挑出同一批）。
## * `end_tol_deg`：端点自检容差。超了 ⇒ 返回 null（上层回退两点层）。
##
## 返回 null = 本模型不适合曲线层（老资产 / 曲线与基准不同源 / 挑不出形态骨）。
static func setup(skel: Skeleton3D, normal: Dictionary, cruise: Dictionary,
		curve: Dictionary, min_deg := 0.5, end_tol_deg := 2.0) -> FormCurveModifier:
	if skel == null or cruise.is_empty():
		return null
	var m := FormCurveModifier.new()
	m.name = "FormCurveModifier"
	var worst := 0.0
	var nb := 1 << 30
	# 曲线源的**全局时间轴**（`ModelAnimator.load_curve_from()` 给的各骨并集）。
	var cbones: Dictionary = curve.get("bones", {}) if curve.has("bones") else {}
	var t0: float = float(curve.get("t0", 0.0))
	var t1: float = float(curve.get("t1", 1.0))
	if t1 <= t0:
		t1 = t0 + 1.0
	for bone: String in cruise.keys():
		if not normal.has(bone):
			continue
		var bi := skel.find_bone(bone)
		if bi < 0:
			continue
		var q0: Quaternion = normal[bone]
		var q1: Quaternion = cruise[bone]
		# ① 挑形态骨：与 `CruiseFormModifier` **逐字同判据**。
		if rad_to_deg(q0.angle_to(q1)) < min_deg:
			continue
		var ts: PackedFloat32Array
		var qs: Array
		var ent: Dictionary = cbones.get(bone, {})
		if ent.has("q") and (ent["q"] as Array).size() >= 2:
			ts = ent["t"]
			qs = ent["q"]
			# ② 端点自检：曲线必须真的起于常态、终于巡航。
			var d0 := rad_to_deg((qs[0] as Quaternion).angle_to(q0))
			var d1 := rad_to_deg((qs[qs.size() - 1] as Quaternion).angle_to(q1))
			worst = maxf(worst, maxf(d0, d1))
			if d0 > end_tol_deg or d1 > end_tol_deg:
				# 这条曲线与本工程的常态/巡航**不是同一套**（N42·十二 那类半升级）。
				# ⇒ 宁可整层不用（回退已验证的两点层），也不要把对不上的姿态硬塞进去。
				push_warning("[FormCurveModifier] %s 端点对不上（首 %.2f° / 末 %.2f° > %.2f°）→ 放弃曲线层"
						% [bone, d0, d1, end_tol_deg])
				return null
		else:
			# 变形动画里这根骨没有独立曲线（姿态恒定 ⇒ 被导入器抽稀掉）。
			# ⇒ 退回两点线性：形态不能缺块，端点天然吻合，不参与自检。
			ts = PackedFloat32Array([t0, t1])
			qs = [q0, q1]
			m.fell_back.append(bone)
		m._idx.append(bi)
		m._frames.append(qs)
		m._times.append(ts)
		nb = mini(nb, qs.size())
	if m._idx.is_empty():
		# 挑不出形态骨 ⇒ 这个模型的巡航形态不靠骨骼差表达。**不告警**（老资产都走这里）。
		return null
	if m._idx.size() != m._frames.size() or m._idx.size() != m._times.size():
		push_error("FormCurveModifier: 下标表 / 时间表 / 姿态表长度不一致")
		return null
	m._t0 = t0
	m._t1 = t1
	m.key_count = nb if nb < (1 << 30) else 0
	m.endpoint_max_deg = worst
	m.active = true
	m.morph = 0.0
	return m


## 形态骨名（读数/测试用，与 `CruiseFormModifier.form_bones()` 同形参）。
func form_bones(skel: Skeleton3D) -> Array[String]:
	var out: Array[String] = []
	if skel == null:
		return out
	for b in _idx:
		out.append(skel.get_bone_name(b))
	return out


func form_bone_count() -> int:
	return _idx.size()


## 当前 `morph` 下、某根形态骨的**曲线目标姿态**（探针/测试用它算"该到哪"）。
func curve_target_of(bone_idx: int) -> Quaternion:
	var i := _idx.find(bone_idx)
	if i < 0:
		return Quaternion.IDENTITY
	return _target_at(i, clampf(morph, 0.0, 1.0))


## 这根骨**走完曲线**时的姿态（= 巡航形态）。
##
## ★ 与 `CruiseFormModifier.cruise_rotation_of()` **同名同义**，刻意如此：
## 探针/测试就能用同一套调用读两档形态层（曲线层 / 两点层），不必分叉。
## 语义都是「离最终的巡航形态还有多远」。
func cruise_rotation_of(bone_idx: int) -> Quaternion:
	var i := _idx.find(bone_idx)
	if i < 0:
		return Quaternion.IDENTITY
	var series: Array = _frames[i]
	return series[series.size() - 1] as Quaternion


## 第 i 根骨在归一化进度 `t ∈ [0,1]` 处的曲线值。
##
## ★ 先把 `t` 换算成**真实时间** `tm = lerp(_t0, _t1, t)`，再到该骨**自己的**
## 时间轴上取样 —— 这是各骨节奏能对齐的唯一做法（见类头那段）。
func _target_at(i: int, t: float) -> Quaternion:
	return _sample(_times[i], _frames[i], lerpf(_t0, _t1, clampf(t, 0.0, 1.0)))


## 在 `ts` / `qs` 这条**非等间隔**的采样序列上，取时间为 `tm` 的姿态。
static func _sample(ts: PackedFloat32Array, qs: Array, tm: float) -> Quaternion:
	var n := ts.size()
	if n == 0:
		return Quaternion.IDENTITY
	if n == 1 or tm <= ts[0]:
		return qs[0] as Quaternion
	if tm >= ts[n - 1]:
		return qs[n - 1] as Quaternion
	# 抽稀后每根骨只剩几十个点 ⇒ 线性扫足够；二分在这里是过度设计。
	var k := 0
	while k < n - 2 and ts[k + 1] < tm:
		k += 1
	var span := ts[k + 1] - ts[k]
	var f := 0.0 if span <= 0.0 else (tm - ts[k]) / span
	return (qs[k] as Quaternion).slerp(qs[k + 1], clampf(f, 0.0, 1.0))


## ★ 引擎的插队点：动画求值之后、global pose 之前。
##
## `morph <= 0` 时**一个字节都不写** —— 常态路径与「没有形态层」逐位等价。
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
		# ⚠️ 读的必须是**动画刚写完的原始值**（不是上一帧我写的值）——
		# 靠的就是 `_process_modification()` 的执行时机。时机若不对，
		# `t < 1` 时会逐帧叠加漂移（判据见 `read_residual_deg`）。
		var cur := skel.get_bone_pose_rotation(b)
		var target := _target_at(i, t)
		var gap := rad_to_deg(cur.angle_to(target))
		if i == 0:
			read_residual_deg = gap
		mx = maxf(mx, gap)
		skel.set_bone_pose_rotation(b, cur.slerp(target, t))
	last_applied_deg = mx
