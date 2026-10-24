extends Node
## N52 · S0 —— 柯西形态骨**位置**判据探针（**只读**，不改工程）。
##
## ## 它要补的那个洞
##
## 轮 42 的 `tools/form_weld_shot.gd` 主判据是「形态骨**自己的局部旋转**离巡航多远」——
## 而那正是 `FormWeld.weld()` 自己写进去的值 ⇒ **循环自证、必然 PASS**。
## 它从没有量过**骨原点的位置**，也从没有一格在**变形过程中**（4 格全是
## `cruise_idle` / `dash_f` / `dash_l` / `dash_f` 的沉降稳定态）。
##
## ⇒ 本探针把判据换到**另一个自由度**上：每根形态骨的**骨原点世界坐标**（相对机体）。
##   一个骨 pose = **T·R·S**；焊缝只接管 R，把 T 留给当前动画 ⇒ **混合变换**。
##   「翼展开」有一大半靠**位移**表达（`RearHang.R` 展平要平移 1.16 单位 ≈ 118% 身高）
##   ⇒ 只量旋转，看不见这个洞。
##
## ## 四段（缺一段都不算证）
##
## | 段 | 干什么 | 出口判据 |
## |----|--------|----------|
## | 1 | **两基准**：播 `fly`（morph=0）读一次；播 `cruise_idle`（morph=1）读一次 | 位移差应 ≈ 1.18 × 模型高 |
## | 2 | **症状①**：巡航稳态 + 按方向键（焊接**开着**） | ★ **`离巡航/离常态 ≤ 0.20`**（无量纲二选一）＋ 焊缝自报位置残差 ≈ 0 |
## | 3 | **症状②**：`form_on` 变形全程逐帧跟踪 | 相邻帧跳变 ≤ 速率推出的界；全程「离最近端 ≤ 自己的两端差」 |
## | 4 | 出图：变形中段 4 帧（morph 0.15/0.35/0.55/0.75）× 2 自由机位 | 肉眼无「伸到取景外」的长板 |
##
## ## ★ 判据落在**哪一层**（本轮修正，见 `_bones_now()` 的长注释）
##
## 「骨原点的位置」有三种口径，混用会得出完全相反的结论：
##
## | 口径 | 含机体平移 | 含机体姿态 | 含父链 | 用途 |
## |---|---|---|---|---|
## | 实体世界坐标 | ✓ | ✓ | ✓ | ⛔ 本探针**不用**：冲刺时机身滚转会把 27 单位长的挂架甩出 7 单位 |
## | **`Hips` 局部系**（本文用） | ✗ | ✗ | ✓ | ✓ **被消费层**：这就是渲染时那根骨**相对机体**在哪 |
## | `get_bone_pose_position()` | ✗ | ✗ | ✗ | ✓ **写入层**：焊缝自己写进去的值（独立旁证） |
##
## 坐标取「`Hips` 系」的理由与「不能只减 `fb.global_position`」的反例，写在 `_bones_now()` 里。
##
## ## ★ 两个**已踩过**的坑（第一版就是被这两条毁掉的）
##
## 1. **不能用 `weld()` 取位置基准**：轮 42 的焊缝**只写 rotation**，手动 `weld(1.0)` / `weld(0.0)`
##    之后读到的位置**必然相同**（位置一直是当前动画给的）。第一版据此打出
##    `|Δ| = 0.0000`，看起来像"没有位移差" —— 假的。**位置基准必须从动画状态里取**
##    （播 `fly` 读 / 播 `cruise_idle` 读）。
##    ⚠️ N52 起焊缝**写全 T·R**，这条"取不到"的前提已经没了 —— 但**基准仍从动画状态取**：
##    从动画取是**独立于被测对象**的（T35 的证伪条要靠这个独立性）。
## 2. **async 辅助函数必须 `await`**：本探针的 `_wait_*()` 都含 `await`，调用时漏掉
##    `await` 会让它们**在后台各自继续推进** `cruise_morph` ⇒ `morph` 的推进速度被放大
##    8~9 倍、帧与帧之间根本对不上。第一版的 morph 从 0.37 到 1.0 只用了 2 帧
##    （正确值应是 ~17 帧）。§「调用约定」段有自检。
##
## ## 跑法（**不能加 --headless**：dummy 渲染器抓出来是空的）
##   godot --path <工程> res://tools/probe_wing_pos.tscn -- <输出目录>

const W := 400
const H := 470
## 与物理帧率一致 ⇒ 迭代数直接就是时间。
const DT := 1.0 / 60.0
## 判据容差。第一次跑量到世界尺度：模型高 28.0 单位、`RearHang.R` 位移差 33.12 单位
## ⇒ 容差取 1.0 单位（≈3.6% 模型高），比 33.12 小一个多数量级 ⇒ 判据仍能变红。
const POS_TOL := 1.0
## 「写入层」容差（**模型本地单位**，`get_bone_pose_position()` 那一层）。
## 本地 1.0 = 世界 28.53 —— 直接用 `POS_TOL` 会松得量不出东西。
## 最大两端差 1.1607（`RearHang.R`）⇒ 取 0.02（≈ 1.7%，世界 0.57）：
## 比 `POS_TOL` 严、又不至于被 float 噪声顶红。
const WELD_POS_TOL_LOCAL := 0.02
## ★ 段 2 的**主判据**：`离巡航 / 离常态 ≤ POS_FRAC` —— 一个**无量纲的二选一分类**。
##
## ## 为什么不用绝对容差（第一版 1.0 世界单位的错）
##
## 那 8 根骨的父链里还有**非形态骨**（躯干 `Chest`/`Spine`），冲刺姿态会让它们转，
## 于是背包整体在 `Hips` 系里平移 —— 修好位置通路后仍剩 **1.7565 世界单位**
##（`Wing.R`，= 5.3% 的 33.12）。**这是合法的机体姿态，不是病**：翼本来就该跟着躯干走。
## 用固定 1.0 去卡，等于要"翼完全不随躯干动"—— 一个**做不到也没有物理意义**的目标。
##
## ## 那判据该问什么
##
## 用户看到的是二选一：**翼是展开的，还是收起的？**
## ⇒ 直接拿两个候选比：靠近巡航基准则判"展开"。修好后 `1.7565/33.1168 = 0.053`；
##   修好前 `31.2373/0.1483 = 210.6` —— **相差 4000 倍**，判别力比任何绝对容差都强，
##   而且与模型尺寸、身高、机体姿态**全都无关**。
## ⚠️ 它同时挡住另外两种蒙混：停在**中途**（两距离相等 ⇒ 比值 1.0 ⇒ 红）、
##   **跑到离两端都远的地方**（比值 → 1 ⇒ 红）。
const POS_FRAC := 0.20
## 8 根形态骨（与 `FormWeld` 的焊接表一致；`Shoulder.L` 被 20° 门槛滤掉）。
const FORM_BONES := [
	"Wing.L", "Wing.R",
	"BinderFront.L", "BinderFront.R",
	"BinderBack.L", "BinderBack.R",
	"RearHang.L", "RearHang.R",
]
## 读数的**参考骨**：形态骨原点表达在它的坐标系里（去机体平移 ＋ 去机体姿态）。
##
## ⚠️ 它**必须不是**形态骨（不受 `FormWeld` 写入），否则参考物自己也动、判据自证。
## `Hips` 是躯干根，柯西实测它不是形态骨（不在 `FormWeld` 的 8 根里）。
const REF_BONE := "Hips"
## 出图的两个**自由机位**（方位角°，仰角°，名）。⛔ 不再只用俯视/追尾 ——
## 「飘到远处」是**位置**问题，轮 33/34 已记：判一个自由度，机位要垂直于它。
const VIEWS := [
	[90.0, 8.0, "侧视"],
	[35.0, 22.0, "3/4 俯前"],
]
## 变形中段的采样点（`form_on` 归一化进度）。
const MID_T := [0.15, 0.35, 0.55, 0.75]

var out_dir := "user://wing_pos"
var _ok_all := true
var _p_cruise := {}
var _p_normal := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	_build_env()
	await get_tree().physics_frame

	FlightBody.use_placeholder = false
	var fb := await _mount(SuitProfile.xi())
	# ★ 关掉机体自己的 `_process`：它的 `_tick_effects()` 会**自己推** `cruise_morph`
	#   与状态机 ⇒ 变形中段的逐帧跟踪会被"多推一帧"污染。关掉之后
	#   `mixer_applied` 照常发（那是引擎求值链，与 `_process` 无关）。
	fb.set_process(false)

	var w: FormWeld = fb._form_weld
	if w == null:
		print("FATAL: `_form_weld` 没建起来 ⇒ 本探针无意义")
		get_tree().quit(1)
		return
	print("DIAG _form_weld=yes 形态骨=%d 根 被门槛滤掉=%s" % [w.form_bone_count(), str(w.skipped)])

	var bounds: AABB = fb.model_bounds
	var focus: Vector3 = fb.global_position \
		+ Vector3(0.0, bounds.position.y + bounds.size.y * 0.5, 0.0)
	# 取景以**静态包围盒**为基准再放 1.5 倍，**全程固定** ⇒ 格与格之间可直接比；
	#「伸出取景外」本身就是证据，不能靠放大取景把它藏起来。
	var cam_size: float = maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z) * 1.5
	print("DIAG bounds size=(%.2f, %.2f, %.2f)  cam.size=%.2f  focus=(%.2f, %.2f, %.2f)" % [
		bounds.size.x, bounds.size.y, bounds.size.z, cam_size,
		focus.x, focus.y, focus.z])

	fb.fm.boosting = true
	fb.fm.hovering = false

	# ============================================================ 段 1：两基准
	print("\n" + "=".repeat(96))
	print("[段 1] 两基准 —— ★ 位置基准从**动画状态**取（与 `FormWeld` 同源同口径，且独立于被测对象）")
	print("=".repeat(96))
	# ---- 常态基准：morph=0，状态机播 `fly` ----
	fb.fm.boosting = false
	fb._dash_anim_dir = ""
	await _wait_morph(fb, 0.0, 400)
	await _wait_action(fb, 200, "fly")
	await _wait_sync(fb, 30)
	_p_normal = _bones_now(fb)
	print("常态基准：morph=%.4f 在播=%-14s 旋转残差=%.4f°"
		% [fb.cruise_morph, _act(fb), (w.residual_deg() if w.attached() else -1.0)])
	# ---- 巡航基准：morph=1，状态机播 `cruise_idle` ----
	fb.fm.boosting = true
	await _wait_morph(fb, 1.0, 400)
	await _wait_action(fb, 300, "cruise_idle")
	await _wait_sync(fb, 30)
	_p_cruise = _bones_now(fb)
	print("巡航基准：morph=%.4f 在播=%-14s 旋转残差=%.4f°"
		% [fb.cruise_morph, _act(fb), (w.residual_deg() if w.attached() else -1.0)])

	print("\n%-14s %-28s %-28s %s" % ["骨", "常态基准(相对机体)", "巡航基准", "|Δ|"])
	var worst_ref := 0.0
	var worst_ref_bone := ""
	for b: String in FORM_BONES:
		if not _p_cruise.has(b) or not _p_normal.has(b):
			continue
		var d: float = (_p_cruise[b] as Vector3).distance_to(_p_normal[b] as Vector3)
		if d > worst_ref:
			worst_ref = d
			worst_ref_bone = b
		print("%-14s %-28s %-28s %.4f" % [b,
			_v(_p_normal[b] as Vector3), _v(_p_cruise[b] as Vector3), d])
	print("★ 最大位移差 = %.4f（%s）｜模型高 %.2f ⇒ 占身高 %.1f%%"
		% [worst_ref, worst_ref_bone, bounds.size.y, worst_ref / maxf(bounds.size.y, 0.001) * 100.0])

	# ============================================================ 段 2：症状①
	print("\n" + "=".repeat(96))
	print("[段 2] 症状①：巡航稳态 + 按方向键（**焊接开着**）—— 位置该留在**巡航**")
	print("=".repeat(96))
	fb._dash_anim_dir = ""
	await _wait_morph(fb, 1.0, 300)
	await _wait_action(fb, 300, "cruise_idle")
	await _wait_sync(fb, 30)
	print("进入时：morph=%.4f 在播=%-14s 旋转残差=%.4f°"
		% [fb.cruise_morph, _act(fb), (w.residual_deg() if w.attached() else -1.0)])

	var dirs := [["f", "前冲 dash_f"], ["b", "后冲 dash_b"], ["l", "左闪 dash_l"], ["r", "右闪 dash_r"]]
	print("\n%-14s %-14s %-9s %-11s %-12s %-12s %-11s %s" % [
		"键", "在播", "morph", "旋转残差°", "离巡航位置", "离常态位置", "焊缝pos残差", "偏离最大的骨"])
	var worst_dir := 0.0
	var worst_dir_normal := 0.0
	var worst_dir_tag := ""
	var worst_dir_bone := ""
	var worst_weld_pos := 0.0
	## 两端差最大的那根骨的距离（= 这一趟总共要走的路）。绝对界用它当尺。
	var span_ref: float = _dev(_p_cruise, _p_normal)[0]
	for d in dirs:
		fb._dash_anim_dir = d[0]
		await _wait_sync(fb, 24)
		var p := _bones_now(fb)
		var dc := _dev(p, _p_cruise)
		var dn := _dev(p, _p_normal)
		var res: float = w.residual_deg() if w.attached() else -1.0
		# ★ 独立旁证：**焊缝自己那一层**的读数（`get_bone_pose_position()`，模型本地单位）。
		# 与上面的「参考系原点」是两个不同的层：一个是**写入层**、一个是**被消费层**。
		# 两者若一致 ⇒ 位置通路真的贯通；若写入层好、消费层坏 ⇒ 是父链/姿态问题。
		var wp: float = w.residual_pos() if w.attached() else -1.0
		print("%-14s %-14s %-9.4f %-11.4f %-12.4f %-12.4f %-11.4f %s" % [
			d[1], _act(fb), fb.cruise_morph, res, dc[0], dn[0], wp, dc[1]])
		if dc[0] > worst_dir:
			worst_dir = dc[0]
			worst_dir_normal = dn[0]
			worst_dir_tag = d[1]
			worst_dir_bone = dc[1]
		worst_weld_pos = maxf(worst_weld_pos, wp)
		fb._dash_anim_dir = ""
		await _wait_action(fb, 300, "cruise_idle")
		await _wait_sync(fb, 10)
	_ok_all = _judge(
		"★ 焊接开着时按方向键，形态骨位置仍**贴在巡航**（`离巡航/离常态` = %.4f/%.4f = %.4f ≤ %.2f ｜ 最差=%s · %s）"
		% [worst_dir, worst_dir_normal, worst_dir / maxf(worst_dir_normal, 1e-6), POS_FRAC,
			worst_dir_bone, worst_dir_tag],
		worst_dir <= POS_FRAC * worst_dir_normal) and _ok_all
	_ok_all = _judge(
		"★ 绝对偏离也在界内（离巡航 %.4f ≤ %.2f = 20%% × 最大两端差 %.4f）"
		% [worst_dir, POS_FRAC * span_ref, span_ref],
		worst_dir <= POS_FRAC * span_ref) and _ok_all
	_ok_all = _judge(
		"★ 焊缝自报位置残差 ≈ 0（最大 %.4f ≤ %.4f ｜ 模型本地单位；-1 = 位置通路未启用）"
		% [worst_weld_pos, WELD_POS_TOL_LOCAL],
		worst_weld_pos >= 0.0 and worst_weld_pos <= WELD_POS_TOL_LOCAL) and _ok_all
	if worst_dir > POS_FRAC * worst_dir_normal:
		print("   ↑ **红**：形态骨在参考系里的位置退回了常态，而旋转仍被焊在巡航")
		print("     ⇒ 世界变换 = 旋转取焊缝 ＋ 位移取动画 —— 这就是「翼看起来关上了」。")

	# ============================================================ 段 3：症状②
	print("\n" + "=".repeat(96))
	print("[段 3] 症状②：`form_on` 变形全程逐帧跟踪（形态骨位置）")
	print("=".repeat(96))
	fb._dash_anim_dir = ""
	fb.fm.boosting = false
	await _wait_morph(fb, 0.0, 400)
	await _wait_action(fb, 200, "fly")
	await _wait_sync(fb, 20)
	print("变形前：morph=%.4f 在播=%s" % [fb.cruise_morph, _act(fb)])
	fb.fm.boosting = true

	var trace: Array = []
	var shots: Array = []
	var taken := {}
	for i in 70:
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame
		var pl: AnimationPlayer = fb.model_anim.player if fb.model_anim != null else null
		var rec := {
			"i": i,
			"morph": fb.cruise_morph,
			"act": _act(fb),
			"p": _bones_now(fb),
			# ★ 拆分量：**局部 position**（不含父链）vs **世界原点**。
			#   局部不跳而世界跳 ⇒ 是父链（焊缝的 rotation / 别的骨）；局部就跳 ⇒ 动画轨或混合。
			"lp": _local_pos(fb),
			"ph": (pl.current_animation_position if pl != null else -1.0),
			"al": (pl.current_animation_length if pl != null else -1.0),
			"an": (pl.current_animation if pl != null else "?"),
		}
		trace.append(rec)

	# ---- 相邻帧跳变：**世界**与**局部**分开算 ----
	var jump := 0.0
	var jump_at := -1
	var jump_bone := ""
	var ljump := 0.0
	var ljump_at := -1
	var ljump_bone := ""
	for i in range(1, trace.size()):
		for bone: String in FORM_BONES:
			var wa: Dictionary = trace[i - 1]["p"]
			var wb: Dictionary = trace[i]["p"]
			if wa.has(bone) and wb.has(bone):
				var d: float = (wa[bone] as Vector3).distance_to(wb[bone] as Vector3)
				if d > jump:
					jump = d
					jump_at = i
					jump_bone = bone
			var la: Dictionary = trace[i - 1]["lp"]
			var lb: Dictionary = trace[i]["lp"]
			if la.has(bone) and lb.has(bone):
				var dl: float = (la[bone] as Vector3).distance_to(lb[bone] as Vector3)
				if dl > ljump:
					ljump = dl
					ljump_at = i
					ljump_bone = bone
	print("逐帧 %d 帧 ｜ morph 0→1 用了 %d 帧（理论 %.0f 帧 @%.4f/帧）" % [
		trace.size(), _frames_to(trace, 1.0), 1.0 / (1.0 / 0.45 * DT), 1.0 / 0.45 * DT])
	print("相邻帧跳变  世界原点 max = %.4f（第 %d 帧 · %s，占模型高 %.1f%%）" % [
		jump, jump_at, jump_bone, jump / maxf(bounds.size.y, 0.001) * 100.0])
	print("相邻帧跳变  局部 pos max = %.4f（第 %d 帧 · %s）—— 若局部**不跳**而世界跳，" % [
		ljump, ljump_at, ljump_bone])
	print("            ⇒ 跳变来自**父链**（焊缝写的 rotation），不是动画轨。")

	# ---- 「离两端都远」= 飘散 ----
	#
	# ⚠️ 原来这条是「越出**两基准包围盒**」——**会误报**：包围盒是那两帧的**点集**，
	# 而变形中每根骨的**父链**也在转（焊缝写的 rotation）⇒ 骨是**绕枢轴扫弧**过来的，
	# 弧本来就会跑到两端点连线的外侧。实测：修好位置通路后它 0.3042 → 3.9819，
	# 而那 3.98 全是弧高，不是病。
	#
	# ⇒ 换成**自校准**判据：每根骨必须落在「离**自己的**常态位或巡航位」
	#   **不超过它自己的两端差 `|Δ|`** 之内。
	#   理由：`|Δ|` 是这根骨这一趟**总共要走的路**（`RearHang.R` 31.27 世界单位）；
	#   一个平滑的 0→1 变形，任意中间帧离某一端的距离**不可能超过全程**。
	#   而「飘到离机体远处乱七八糟」的骨会**同时离两端都很远**（2~3 倍 `|Δ|`）⇒ 照样变红。
	#   ⛔ 这不是把判据放松成恒真：A/B（S2）会把位置写入退回，届时这条必须复现红。
	var over := 0.0
	var over_bone := ""
	var over_pair := ""
	var ratio_max := 0.0
	for bone: String in FORM_BONES:
		if not _p_cruise.has(bone) or not _p_normal.has(bone):
			continue
		var span: float = (_p_cruise[bone] as Vector3).distance_to(_p_normal[bone] as Vector3)
		var worst_near := 0.0
		for rec in trace:
			var p: Dictionary = rec["p"]
			if not p.has(bone):
				continue
			var near: float = minf(
				(p[bone] as Vector3).distance_to(_p_normal[bone] as Vector3),
				(p[bone] as Vector3).distance_to(_p_cruise[bone] as Vector3))
			worst_near = maxf(worst_near, near)
		ratio_max = maxf(ratio_max, worst_near / maxf(span, 1e-6))
		if worst_near - span > over:
			over = worst_near - span
			over_bone = bone
			over_pair = "离最近端 %.4f ＞ 自己的两端差 %.4f" % [worst_near, span]
	print("全程「离两端都远」超限 max = %.4f（%s ｜ %s）｜ 余量：全程离最近端 / 自己的两端差 ≤ %.4f" % [
		over, over_bone, over_pair, ratio_max])
	# 附：旧口径（包围盒越界）照打，供对照，但**不再当判据**。
	var bbox_over := 0.0
	for bone: String in FORM_BONES:
		if _p_cruise.has(bone) and _p_normal.has(bone):
			bbox_over = maxf(bbox_over, _max_over(trace, bone))
	print("（对照）旧口径「越出两基准包围盒」= %.4f —— 含父链扫弧的弧高，**不当判据**" % bbox_over)

	print("\n  帧   morph    在播         播放头/长度       世界跳变   局部跳变   RearHang.R 局部pos        RearHang.R 世界原点")
	var prevP: Dictionary = {}
	var prevL: Dictionary = {}
	for rec in trace:
		var p: Dictionary = rec["p"]
		var lp: Dictionary = rec["lp"]
		var dj := 0.0
		var dl := 0.0
		if not prevP.is_empty():
			for bone: String in FORM_BONES:
				if p.has(bone) and prevP.has(bone):
					dj = maxf(dj, (p[bone] as Vector3).distance_to(prevP[bone] as Vector3))
				if lp.has(bone) and prevL.has(bone):
					dl = maxf(dl, (lp[bone] as Vector3).distance_to(prevL[bone] as Vector3))
		if dj > POS_TOL or dl > POS_TOL or int(rec["i"]) % 5 == 0 \
				or float(rec["morph"]) >= 0.999:
			print("  %-4d %-8.4f %-12s %-16s %-10.4f %-9.4f %-25s %s" % [
				int(rec["i"]), float(rec["morph"]), str(rec["act"]),
				"%.3f/%.3f" % [float(rec["ph"]), float(rec["al"])],
				dj, dl,
				_v(lp.get("RearHang.R", Vector3.ZERO)),
				_v(p.get("RearHang.R", Vector3.ZERO))])
		prevP = p
		prevL = lp

	# ---- 跳变容差**由 morph 速率推出来**，不是拍的 ----
	#
	# 「相邻帧跳变」这个量本身没有绝对尺度：`morph` 每帧推进 `rate`，而两端差 `|Δ|`
	# （`RearHang.R` 31.27 世界单位）⇒ **匀速直线**下每帧上限就是 `|Δ|·rate`。
	# 实测形变路径是弧、不是直线 ⇒ 再给 1.5 倍余量。
	# ⚠️ 这不是把判据放松成恒真：第 21 帧那种 teleport（旧口径 6.52 / 12.89）是
	# **平滑率的 5~10 倍**，照样变红。
	var span_max: float = _dev(_p_cruise, _p_normal)[0]
	var morph_frames := maxf(float(_frames_to(trace, 1.0)), 1.0)
	var jump_tol: float = maxf(POS_TOL, span_max / morph_frames * 1.5)
	_ok_all = _judge("★ 变形全程「离两端都远」不超限（最大 %.4f ≤ 0 ｜ %s）"
		% [over, over_bone], over <= 0.0) and _ok_all
	_ok_all = _judge("★ 变形全程无位置跳变（相邻帧 max %.4f ≤ %.4f ｜ %.3f = %.2f/%.0f帧×1.5 ｜ 第 %d 帧 %s）"
		% [jump, jump_tol, jump_tol, span_max, morph_frames, jump_at, jump_bone],
		jump <= jump_tol) and _ok_all

	# ============================================================ 段 4：变形中段出图
	print("
" + "=".repeat(96))
	print("[段 4] 变形中段出图 —— **单独一轮**")
	print("★ 为什么必须单独一轮：拍一张图要 `await` 5~8 个真实帧，而 `AnimationPlayer`")
	print("  按真实时间推进播放头（我只关了 `FlightBody._process`，管不到它）⇒ 那一帧的")
	print("  播放头会跳过好几帧。混进 §3 的逐帧跟踪里，就会**造出一个 12.9 单位的假跳变**")
	print(" （第一轮实测：播放头 0.217→0.333，而该帧的值与 glb 轨 `t=0.3333` 逐位吻合）。")
	print("=".repeat(96))
	taken.clear()
	fb._dash_anim_dir = ""
	fb.fm.boosting = false
	await _wait_morph(fb, 0.0, 400)
	await _wait_action(fb, 200, "fly")
	await _wait_sync(fb, 20)
	fb.fm.boosting = true
	for i in 70:
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame
		await _shoot_mid({"morph": fb.cruise_morph}, taken, shots, fb, focus, cam_size)

	# ============================================================ 段 5：变形中 + 方向输入
	#
	# ★ 这一格最贴近实机：辅助驾驶下玩家几乎必然在形态展开的同时按着方向键。
	#   它命中的是 R2（作者位移走 CUBICSPLINE、焊缝旋转走线性，两条时间轴各走各的）
	#   与「位置被方向动作写回常态」的**叠加**。
	print("
" + "=".repeat(96))
	print("[段 5] ★ 最贴近实机：**变形进行中**按住前进")
	print("=".repeat(96))
	fb._dash_anim_dir = ""
	fb.fm.boosting = false
	await _wait_morph(fb, 0.0, 400)
	await _wait_action(fb, 200, "fly")
	await _wait_sync(fb, 20)
	fb.fm.boosting = true
	var trace5: Array = []
	var pressed_at := -1
	for i in 70:
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame
		if pressed_at < 0 and fb.cruise_morph >= 0.5:
			fb._dash_anim_dir = "f"
			pressed_at = i
		trace5.append({
			"i": i, "morph": fb.cruise_morph, "act": _act(fb),
			"p": _bones_now(fb),
		})
	var j5 := 0.0
	var j5_at := -1
	var j5_bone := ""
	for i in range(1, trace5.size()):
		for bone: String in FORM_BONES:
			var wa: Dictionary = trace5[i - 1]["p"]
			var wb: Dictionary = trace5[i]["p"]
			if wa.has(bone) and wb.has(bone):
				var d: float = (wa[bone] as Vector3).distance_to(wb[bone] as Vector3)
				if d > j5:
					j5 = d
					j5_at = i
					j5_bone = bone
	print("第 %d 帧按住前进（此刻 morph=%.4f）｜ 逐帧跳变 max = %.4f（第 %d 帧 · %s，占模型高 %.1f%%）" % [
		pressed_at, (float(trace5[pressed_at]["morph"]) if pressed_at >= 0 else -1.0),
		j5, j5_at, j5_bone, j5 / maxf(bounds.size.y, 0.001) * 100.0])
	print("
  帧   morph    在播               跳变       RearHang.R 世界原点")
	var prev5: Dictionary = {}
	for rec in trace5:
		var p: Dictionary = rec["p"]
		var dj := 0.0
		if not prev5.is_empty():
			for bone: String in FORM_BONES:
				if p.has(bone) and prev5.has(bone):
					dj = maxf(dj, (p[bone] as Vector3).distance_to(prev5[bone] as Vector3))
		if dj > POS_TOL or int(rec["i"]) % 6 == 0 or int(rec["i"]) == pressed_at:
			print("  %-4d %-8.4f %-18s %-9.4f %s" % [
				int(rec["i"]), float(rec["morph"]), str(rec["act"]), dj,
				_v(p.get("RearHang.R", Vector3.ZERO))])
		prev5 = p
	_ok_all = _judge("★ 变形中段按前进，位置不跳（最大 %.4f ≤ %.4f ｜ 与 §3 同一把尺：%.2f/%.0f帧×1.5 ｜ 第 %d 帧 %s）"
		% [j5, jump_tol, span_max, morph_frames, j5_at, j5_bone], j5 <= jump_tol) and _ok_all

	# ============================================================ 段 6：两端的**稳定参考**
	#
	# ★ 为什么必须有这一段：段 4 只有「变形中段」4 格。**没有两端当尺子，看图的人
	#   无法判断第 4 格那块长板是「合理地插值到巡航位」还是「飘散了」** ——
	#   柯西 `RearHang.R` 在**巡航稳态**下本来就离机身 **27.3 世界单位**
	#   （≈ 95% 身高，见段 1 的坐标表）。把端点拍出来，中间帧才有参照物。
	#
	# ⚠️ 与段 4 同样**单独一趟**：拍图会吃掉 5~8 个真实帧。
	print("\n" + "=".repeat(96))
	print("[段 6] 两端**稳定态**参考（拍图与任何逐帧跟踪分趟，不污染 trace）")
	print("=".repeat(96))
	var shots_end: Array = []
	fb._dash_anim_dir = ""
	for st: Array in [["常态稳定", 0.0], ["巡航稳定", 1.0]]:
		fb.fm.boosting = float(st[1]) > 0.5
		await _wait_morph(fb, float(st[1]), 400)
		await _wait_sync(fb, 20)
		print("  %-9s morph=%.4f 在播=%-14s 旋转残差=%.4f° 焊缝pos残差=%.4f" % [
			str(st[0]), fb.cruise_morph, _act(fb),
			(w.residual_deg() if w.attached() else -1.0),
			(w.residual_pos() if w.attached() else -1.0)])
		for vi in VIEWS.size():
			var img := await _shoot(fb, vi, focus, cam_size)
			if img != null:
				_draw_text(img, 12, H - 16, str(st[0]))
			shots_end.append({"view": vi, "col": (1 if float(st[1]) > 0.5 else 0), "img": img})
	_sheet(shots_end, 2, VIEWS.size(), "wing_endpoints.png", "列 = [常态稳定 / 巡航稳定]")

	# ============================================================ 拼图
	_sheet(shots, MID_T.size(), VIEWS.size(), "wing_morph_mid.png",
		"列 = morph %s" % str(MID_T))

	print("\nVERDICT: %s" % ("N52-PROBE-OK（现状下判据已绿 —— 没复现出问题）"
		if _ok_all else "N52-BUG-REPRODUCED（现状下判据变红 = 症状已复现）"))
	get_tree().quit(0 if _ok_all else 1)


# ================================================================ 段 3 辅助

## `morph` 从 0 爬到 `target` 用了几帧（用于自检"推进速度有没有被别的 coroutine 放大"）。
func _frames_to(trace: Array, target: float) -> int:
	for rec in trace:
		# 容差 1e-3：`cruise_morph` 是浮点累加，末值常是 0.99999… 而非恰好 1.0。
		if float(rec["morph"]) >= target - 1e-3:
			return int(rec["i"])
	return -1


## 逐骨逐轴：整段轨迹越出「两基准包围盒」的最大距离（**世界原点**）。
func _max_over(trace: Array, bone: String) -> float:
	if not _p_cruise.has(bone) or not _p_normal.has(bone):
		return 0.0
	var a: Vector3 = _p_normal[bone]
	var c: Vector3 = _p_cruise[bone]
	var lo := Vector3(minf(a.x, c.x), minf(a.y, c.y), minf(a.z, c.z))
	var hi := Vector3(maxf(a.x, c.x), maxf(a.y, c.y), maxf(a.z, c.z))
	var mx := 0.0
	for rec in trace:
		var p: Vector3 = rec["p"].get(bone, Vector3.ZERO)
		var d := Vector3(
			maxf(lo.x - p.x, 0.0) + maxf(p.x - hi.x, 0.0),
			maxf(lo.y - p.y, 0.0) + maxf(p.y - hi.y, 0.0),
			maxf(lo.z - p.z, 0.0) + maxf(p.z - hi.z, 0.0))
		mx = maxf(mx, d.length())
	return mx


## 8 根形态骨的**局部** pose position（相对父骨，**不含父链**）。
##
## ★ 与 `_bones_now()` 成对使用，用来**拆分量**：
##   局部不跳而世界跳 ⇒ 跳变来自**父链**（焊缝写的 rotation 改的是骨自己的朝向，
##   但会连带改子骨的世界原点）；局部就跳 ⇒ 动画轨或交叉混合。
func _local_pos(fb: FlightBody) -> Dictionary:
	var out := {}
	var skel := fb._model_skel
	if skel == null:
		return out
	for b: String in FORM_BONES:
		var bi := skel.find_bone(b)
		if bi >= 0:
			out[b] = skel.get_bone_pose_position(bi)
	return out


## 变形进度首次越过某个中段点 ⇒ 拍一张（同一中段点只拍一次）。
func _shoot_mid(rec: Dictionary, taken: Dictionary, shots: Array,
		fb: FlightBody, focus: Vector3, cam_size: float) -> void:
	var mv: float = rec["morph"]
	for ci in MID_T.size():
		if taken.has(ci) or mv < MID_T[ci]:
			continue
		taken[ci] = true
		for vi in VIEWS.size():
			var img := await _shoot(fb, vi, focus, cam_size)
			if img != null:
				_draw_text(img, 12, H - 16, str(int(round(mv * 100.0))))
			shots.append({"view": vi, "col": ci, "img": img})


# ================================================================ 读数

## 把若干张格子拼成一张大图并存盘（§4 变形中段 / §6 两端稳定参考共用）。
func _sheet(shots: Array, cols: int, rows: int, fname: String, hint: String) -> void:
	if shots.is_empty():
		return
	var sheet := Image.create(W * cols, H * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.10, 0.12))
	var got := 0
	for s in shots:
		var rec: Dictionary = s
		var img: Image = rec["img"]
		if img == null:
			continue
		got += 1
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(W, H)),
			Vector2i(W * int(rec["col"]), H * int(rec["view"])))
	for ci in range(1, cols):
		sheet.fill_rect(Rect2i(W * ci, 0, 2, H * rows), Color(0.42, 0.48, 0.58))
	for ri in range(1, rows):
		sheet.fill_rect(Rect2i(0, H * ri, W * cols, 2), Color(0.42, 0.48, 0.58))
	var out := out_dir.path_join(fname)
	print("\nSHOT %s err=%d 拍到 %d 格（%s；排 = %s）" % [
		out, sheet.save_png(out), got, hint,
		str(VIEWS.map(func(v: Array) -> String: return v[2]))])


## 8 根形态骨的**骨原点位置**，表达在**参考骨 `Hips` 的坐标系**里（去机体平移 ＋ 去机体姿态）。
##
## ★ 判据落点从「局部旋转」换成「骨原点位置」——这是本探针存在的唯一理由。
##
## ## ⚠️ 为什么不能直接量「世界坐标 − `fb.global_position`」（第一版的错）
##
## 那个口径只去掉了**平移**、没去掉**姿态**。而柯西在冲刺时会 `_start_dash_spin()`：
## 机身**滚转**作用在 `model_pivot` 上 ⇒ 整个骨架一起转 ⇒ 每根骨的世界原点都被甩出去
## `r·sinθ`。`RearHang.R` 在巡航位离机体 27.3 单位，滚 15° 就是 **7.1 单位** ——
## 实测段 2 的残差恰好 **7.2661**、且四个方向**逐位相同**（同一个固定滚转角），
## 那是**机体姿态**，不是翼的位置。
##
## ⇒ 参考系取**非形态骨 `Hips`**（躯干根：`skel.global_transform * get_bone_global_pose(Hips)`），
##   把形态骨原点表达在它里面：`R⁻¹ · (g.origin − hips.origin)`，`R` 取 `hips.basis` 的
##   **纯旋转**部分（丢掉模型缩放 ⇒ 读数仍是**世界单位**，与 `POS_TOL` 同一把尺）。
## `Hips` 不属于那 8 根形态骨，也不受 `FormWeld` 写入 ⇒ 它是干净的参考物。
##
## ⚠️ 这**不是**把判据变松：焊缝若真的没接管位置，形态骨在 `Hips` 系里同样会退回常态位
##（`RearHang.R` 的两端差 **31.27 世界单位**，见段 1）⇒ 判据照样变红。
func _bones_now(fb: FlightBody) -> Dictionary:
	var out := {}
	var skel := fb._model_skel
	if skel == null:
		return out
	# T37：关键 API 当轮实测，不假设它存在。
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()
	var st: Transform3D = skel.global_transform
	var ref_bi := skel.find_bone(REF_BONE)
	var hips_w: Transform3D = st * skel.get_bone_global_pose(ref_bi) if ref_bi >= 0 else st
	var rq := hips_w.basis.get_rotation_quaternion()
	var rinv := Basis(rq).inverse()
	for b: String in FORM_BONES:
		var bi := skel.find_bone(b)
		if bi < 0:
			continue
		var g: Transform3D = st * skel.get_bone_global_pose(bi)
		out[b] = rinv * (g.origin - hips_w.origin)
	return out


## 相对某条基准的最大偏离 ＋ 偏离最大的骨名。
func _dev(p: Dictionary, ref: Dictionary) -> Array:
	var mx := -1.0
	var who := ""
	for b: String in FORM_BONES:
		if not p.has(b) or not ref.has(b):
			continue
		var d: float = (p[b] as Vector3).distance_to(ref[b] as Vector3)
		if d > mx:
			mx = d
			who = b
	return [maxf(mx, 0.0), who]


func _act(fb: FlightBody) -> String:
	return fb.model_fsm.current_action() if fb.model_fsm != null else "?"


func _v(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]


func _judge(label: String, cond: bool) -> bool:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	return cond


# ================================================================ 工具

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.63, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.84, 0.87, 0.94)
	env.ambient_light_energy = 1.20
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 20.0, 0.0)
	key.light_energy = 1.8
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, 200.0, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.74, 0.84, 1.0)
	add_child(fill)


## 摆一台**真的** FlightBody（走 `_build_visual()`，`model_root` / 骨架 / 动画都在链上）。
## ⚠️ 三个必踩的坑（抄自 `form_weld_shot.gd`）：不能摆 y=0（`CRASH_ALTITUDE` 判撞海
## 并 `destroy()`）；`set_physics_process(false)` 要在 `add_child` 之后；`_hover_pose` 要补。
func _mount(p: SuitProfile) -> FlightBody:
	var holder := Node3D.new()
	add_child(holder)
	var fb := FlightBody.new()
	fb.team = 0
	fb.profile = p
	holder.add_child(fb)
	fb.global_transform = Transform3D(Basis(), Vector3(0.0, 3000.0, 0.0))
	fb.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	fb._hover_pose = fb.flight_pitch_deg
	return fb


## 推进 `n` 个固定步长的逻辑帧。
##
## ★ 调用约定：**本函数与 `_wait_morph` / `_wait_action` / `_shoot_mid` 全都必须 `await`。**
## 漏掉会把它们丢到后台各自推进 `cruise_morph`，`morph` 的推进速度被放大好几倍。
func _wait_sync(fb: FlightBody, n: int) -> void:
	for i in n:
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame


## 推进直到 `cruise_morph` 到达 `target`（或耗尽预算）。**必须 `await`。**
func _wait_morph(fb: FlightBody, target: float, max_frames: int) -> void:
	for i in max_frames:
		if absf(fb.cruise_morph - target) < 1e-4:
			return
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame


## 推进直到当前动作变成 `want`（或耗尽预算）。**必须 `await`。**
func _wait_action(fb: FlightBody, max_frames: int, want: String) -> void:
	for i in max_frames:
		if fb.model_fsm != null and fb.model_fsm.current_action() == want:
			return
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame


## 拍一张。`vi` = `VIEWS` 下标。**自由机位**（方位角 + 仰角），不是纯俯视/追尾。
##
## ⚠️ 相机 `global_position` 必须在 `add_child` 之后设；`looking_at()` 的 up
## 与视线共线时会被拒绝、相机停在原点。
func _shoot(fb: FlightBody, vi: int, focus: Vector3, cam_size: float) -> Image:
	var az := deg_to_rad(VIEWS[vi][0])
	var el := deg_to_rad(VIEWS[vi][1])
	var d := maxf(cam_size, 1.0) * 2.2
	var off := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * d

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cam_size
	cam.near = 0.05
	cam.far = 9000.0
	add_child(cam)
	cam.global_position = focus + off
	cam.transform = cam.transform.looking_at(focus, Vector3.UP)
	cam.current = true
	for f in 2:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	cam.queue_free()
	await get_tree().physics_frame
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	return img


## 极简 5×7 点阵（数字 + 负号，工具自包含、不引字体资源）。
func _draw_text(img: Image, x: int, y: int, text: String) -> void:
	var glyphs := {
		"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
		"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
		"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
		"3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
		"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
		"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
		"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
		"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
		"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
		"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
		"－": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	}
	var cx := x
	for ch in text:
		var rows: Array = glyphs.get(ch, glyphs["0"])
		for ry in rows.size():
			var row: String = rows[ry]
			for rx in row.length():
				if row[rx] == "1":
					img.set_pixel(cx + rx, y + ry, Color(1.0, 0.85, 0.35))
		cx += 7
