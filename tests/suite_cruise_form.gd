class_name SuiteCruiseForm
extends RefCounted
## 巡航形态层的**门**（棒 12 测试官 · 2026-09-26）。
##
## ## 为什么要有这一套
##
## 用户一句话点穿了架构缺口：「**正常按 shift 或者切换进辅助驾驶模式的时候
## 就是巡航姿态**」—— 也就是说，巡航形态是玩家**飞行的常态**，不是开火那一瞬间。
##
## 上游 GUIDE §6.7 的约定是「**morph 管形态、骨骼管过程**」：巡航形态本该由
## `cruise_on` morph 负责，待机动作 `fly` 只管呼吸微摆。工程侧
## `_tick_cruise_morph()` 也是照这个写的 —— 但它找的是 **blend shape**。
##
## 新交付的三件 glb **blend shape = 0**（形态改由骨骼承载），那条链路于是
## 静默空转，产出一串**全都不报错**的后果：
##
##   * 按住 Shift 机体**一个像素都不动**（形态不显示）；
##   * `cruise_morph` 恒 0 ⇒ `ModelAnimFSM.set_form(cruise_morph >= 0.5)` 恒 false
##     ⇒ **连巡航版全弹发射都选不上**，一路播常态版；
##   * `fly` 里那 8 根形态骨的微摆 key 还会把形态**主动压回常态**
##     （上游 PIPELINE §7.8 预警过这件事）。
##
## 这一套把那三条变成断言，并钉住新装的骨骼形态层。形态层有**两档**
##（N42·十三 —— **曲线层** `FormCurveModifier` 优先、**两点层** `CruiseFormModifier` 回退）：
##
##   ① **构建**：什么时候该有形态层、什么时候必须为 null（老资产零影响）；
##   ①'**交接**（N42·二十一/二十二）：★ 柯西**已经让位** —— 形态层两档都为
##      null，形态改由 `cruise_idle` / `form_on` / `form_off` 三件**动作**表达
##     （实机判决：同一批骨上 `AnimationPlayer` 每帧覆盖 `SkeletonModifier3D`，
##      同时开着只会让形态层白跑一层求值）。见 `_handover`。
##      ⚠️ 所以下面 ②③④⑤ 全部跑在 `_mount(force_layer = true)` **拉回来**的世界里
##      —— 形态层代码仍在工程内，且**其余五台机体仍然走它**，一条断言都不许删。
##   ② **曲线层逻辑**：端点自检（首帧=常态、末帧=巡航）、缺骨回退、对不上就整层弃用；
##   ③ **行为**：写入有效、`morph=0` 完全空操作、**无漂移**、引擎真的在驱动它；
##   ④ **★ 同步展开**：`morph=0.5` 时 8 根完成度极差 ≤ 0.10 —— "一起展开"的机器判据；
##   ⑤ **回退**：没有曲线源 ⇒ 必须落回两点层（是退路，不是死路）。

const XI_DIR := "res://assets/models/xi/"
## 主模型（它自带的 `fly` 就是待机动作）。
##
## ⚠️ 这里**只**覆盖 `model_path`；extras 一律走 `SuitProfile.xi()` 的生产配置
##（`anim/` 下 **35** 件），测试不自己拼一份 —— 免得"测试里的配置"和
##"生产里的配置"分叉，那正是本工程反复吃亏的一类 bug。
##（原先的 `BURST` / `BURST_CRUISE` 常量指向 v12 旧完整版且**全仓无引用**，
## 2026-09-27 删除。）
const FLY := "res://archive/hidden_models/xi_legacy_20261013/xi_fly_legacy_hidden.scn"

## 形态骨门槛。柯西实测的天然分界：第 8 名 75.01°，第 9 名 0.046°。
const MIN_DEG := 0.5

## 柯西的 **8** 根形态骨（引擎实测：`fly` 首帧 vs `burst_cruise` 末帧）。
##
## ⚠️ 2026-09-27 由 6 根改回 8 根 —— **不是判据放宽，是形态表补全**（N42·十五）：
## 用户给了权威参照 `柯西巡航2.0.glb`（别人做的模型，与主模型件名 203/203 全匹配）。
## 逐件比对显示巡航真态只差 15 件、归 11 根骨，其中 ★ **`RearHang.L/R` 4 件**
## —— 就是用户说的「后翼下方**大片**翼」（件中心 y 要从 0.37~0.46 抬到 0.97~1.00）。
## 而 `cruise_on` 此前完全没碰它 ⇒ 症状正是用户说的
## 「后翼下方大片翼没跟着上方的小翼一起展开」。
##
## 根因是历史回归：v11 的 `ref_pose_cruise.json` 里 `RearHang` 有值（141.376°/140.467°、
## 大片翼展开 ✓），N36 为了「相接件不许裂」把 `RearHang.*` 清零并声明作废；
## 而 N42·九 已把那条判据自我推翻（`RearHang` 与小腿件 rest 相距 105.8 mm
## ⇒ 不是相接件），清零却没回头改。
##
## ⚠️ 与 N42·十二 那条「由 8 根改 6 根」**不是同一件事**，别混：
##   * N42·十二：主模型 v12 / extras v14 **不同源** ⇒ 误判出 `LowerArm.R`(90°)、
##     `Thigh.R`(-24°) 两根**假形态骨**，共 10 根。同步主模型后这两根被正确滤掉。
##   * N42·十五（本条）：补回**真形态骨** `RearHang.L/R`（140.6°/134.4°）。
##     ⇒ 4 根 Binder ＋ 2 根 Wing ＋ 2 根后挂架 = 8 根。
##
## ★ 两者判据不同、方向相反，但都不碰门槛 `MIN_DEG = 0.5`：
##   现在是 8 根（最小 75.007°）与第 9 名（0.046°）之间，余量三个数量级。
const FORM_BONES := [
	"Wing.L", "Wing.R",
	"BinderFront.L", "BinderFront.R",
	"BinderBack.L", "BinderBack.R",
	"RearHang.L", "RearHang.R",
]

## 曲线源（`SuitProfile.model_form_curve`）—— 变形过程的逐帧曲线。
##
## ★ 2026-09-27 用户指定换成 `xi_cruise_on.glb`（棒 7 交付的**契约动作**「巡航变形」）：
##   「后翼下方大片翼**跟着**上方的小翼**一起**展开」。
##   ⛔ 早先沿 `xi_morph_anim3` 是**分段**的（`Wing*` 迟至 0.63 才动、两族差 0.50）。
const FORM_CURVE := "res://assets/models/xi/anim/xi_cruise_on.glb"

## ★ 同步演出的数值判据（用户 2026-09-27 明确要求）。
##
## 曲线源 `xi_cruise_on` 里 **8 根形态骨同一进度**展开（实测首动归一化进度
## 全部 0.15、两族差 0.00）⇒ 本套件钉住的就是这条：同一 `morph` 下
## 8 根的**完成度彼此接近**（极差 ≤ `SYNC_TOL`）。
## 对照：分段源（`xi_morph_anim3`）实测极差 **0.50**，本判据能抓住它。
##
## `EASE_TOL` 钉的是曲线层与两点层的**可判差异**：曲线是缓动（两端慢），
## 两点层是纯线性 ⇒ `morph=0.15` 时曲线只走到约 0.057、线性会走到 0.15。
const SPLIT_MORPH := 0.5
const SYNC_TOL := 0.10
const EASE_MORPH := 0.15
const EASE_TOL := 0.10


static func run(t: T, host: Node) -> void:
	t.suite("CruiseForm / 构建与门槛")
	await _build(t, host)
	t.suite("CruiseForm / 形态表达权交接（N42·二十一/二十二）")
	await _handover(t, host)
	t.suite("CruiseForm / 曲线层逻辑（合成骨架）")
	await _build_curve(t, host)
	t.suite("CruiseForm / 形态层行为（实现本身）")
	await _behavior(t, host)
	t.suite("CruiseForm / 曲线层与回退")
	await _fallback(t, host)
	t.suite("CruiseForm / 老资产零影响")
	await _zero(t, host)
	t.suite("CruiseForm / 帧末焊（轮 42：形态骨的唯一写入者）")
	await _weld_contract(t, host)


# ============================================================ ① 构建与门槛

## 用**合成骨架**测纯逻辑：什么时候建得起来、门槛怎么筛、边界怎么退。
##
## 不依赖真资产，所以它坏了就一定是逻辑坏了，不会是"资产换了"。
static func _build(t: T, host: Node) -> void:
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	host.add_child(skel)
	skel.add_bone("Big")       # idx 0
	skel.add_bone("Tiny")      # idx 1
	skel.add_bone("NoKey")     # idx 2
	await host.get_tree().process_frame

	var q30 := Quaternion(Vector3.RIGHT, deg_to_rad(30.0))
	var q02 := Quaternion(Vector3.RIGHT, deg_to_rad(0.2))
	var normal := {"Big": Quaternion.IDENTITY, "Tiny": Quaternion.IDENTITY, "NoKey": Quaternion.IDENTITY}
	var cruise := {"Big": q30, "Tiny": q02, "NoKey": Quaternion.IDENTITY}

	var m := CruiseFormModifier.setup(skel, normal, cruise)
	t.ok(m != null, "有形态差（30°）就能建起形态层")
	if m == null:
		skel.free()
		return
	t.eq(m.form_bone_count(), 1,
		"★ 门槛生效：只收差 > %.1f° 的骨（30° 收、0.2° 滤、0° 滤）" % MIN_DEG)
	var picked := m.form_bones(skel)
	t.eq(picked[0] if picked.size() > 0 else "?", "Big", "收进来的正是那根 30° 的骨")
	t.not_ok(picked.has("Tiny"), "0.2° 的骨被滤掉（噪声不进门）")
	t.not_ok(picked.has("NoKey"), "0° 的骨被滤掉（rest 不算形态）")

	# ---- 边界：这四条任何一条崩了，老资产/半成品资产就会在运行期炸 ----
	t.ok(CruiseFormModifier.setup(null, normal, cruise) == null, "无骨架 ⇒ null（不崩）")
	t.ok(CruiseFormModifier.setup(skel, normal, {}) == null, "空巡航基准 ⇒ null")
	t.ok(CruiseFormModifier.setup(skel, {}, cruise) == null, "空常态基准 ⇒ null（算不出差）")
	t.ok(CruiseFormModifier.setup(skel, {"Nope": Quaternion.IDENTITY},
		{"Nope": q30}) == null, "骨名在骨架上找不到 ⇒ null（不崩）")
	var flat := {"Big": q30, "Tiny": q30, "NoKey": q30}
	t.ok(CruiseFormModifier.setup(skel, flat, flat) == null,
		"两份基准完全相同 ⇒ null（没有形态差，不需要形态层）")

	# ---- 只给"部分骨"也能建：缺的那根按"没有形态差"处理 ----
	var partial := CruiseFormModifier.setup(skel, {"Big": Quaternion.IDENTITY}, cruise)
	t.ok(partial != null and partial.form_bone_count() == 1,
		"常态基准只给一根骨时仍能建（缺的骨不参与）")

	skel.free()


# ============================================================ ①' 形态表达权交接
#（N42·二十一 方案 B ＋ N42·二十二 回程过渡）

## ★ 柯西的形态**不由 `SkeletonModifier3D` 表达** —— 这条是 N42·二十二 钉的契约，
## 也正是下面那些形态层断言必须 `force_layer` 把被测对象**拉回来**的原因。
##
## ★★ 轮 42 起这个契约多了**第三侧**：形态 = 「动作（巡航待机）+ 帧末焊（形态骨）」。
##
##   * **两档形态层为空**：`_form_curve == null` 且 `_cruise_form == null`；
##   * **三件动作都在**：`cruise_idle` / `form_on` / `form_off` 三个名字在
##     `ModelAnimator` 上真的可播；
##   * **帧末焊在场**：`_form_weld != null` 且形态骨表非空。
##
## ⛔ 为什么三侧都要钉（每一侧失灵都**不报错**）：
##   * 只钉第 1 侧 —— 把三件动作全删掉，形态层**不会**因此回来
##     （早退判据是 `idle_cruise_action != "" and has(...)`）；
##   * 只钉第 2 侧 —— 方向动作族会把那 8 根形态骨写回常态（轮 42 实测 **80/80**
##     个骨-动作对），于是**按任何一个方向键，背后的翼就关了**；
##   * 只钉第 3 侧 —— 焊的可能是「死值」（永远巡航），退出巡航时翼收不回去。
## 三种残缺**都**表现为「屏幕上一个像素都不动 / 动错方向，而全链不报任何错」，
## 正是本工程反复吃亏的那类静默故障。
static func _handover(t: T, host: Node) -> void:
	var m: Dictionary = await _mount(host)          # 默认配置 = 生产配置
	var body := m["body"] as FlightBody
	if body == null:
		t.ok(false, "（交接契约的前置）柯西建不起来")
		return
	t.ok(body._form_curve == null, "★ 形态层**让位**：柯西不建曲线层")
	t.ok(body._cruise_form == null, "★ 形态层**让位**：柯西也不建两点层")
	t.ok(body._form_weld != null,
		"★ 轮 42：形态改由**帧末焊**承载 —— 两档形态层都为空时它必须在场")
	if body._form_weld != null:
		t.gt(body._form_weld.form_bone_count(), 0,
			"★ 帧末焊的形态骨表非空（%d 根）" % body._form_weld.form_bone_count())
	var anim := body.model_anim
	if anim == null or not anim.ready:
		t.ok(false, "（交接契约的前置）`ModelAnimator` 没就绪 ⇒ 下面三条无意义")
		_teardown(body)
		return
	var names := [anim.idle_cruise_action, anim.form_on_action, anim.form_off_action]
	var labels := ["巡航待机 `cruise_idle`", "进巡航 `form_on`", "退巡航 `form_off`"]
	for i in names.size():
		t.ok(str(names[i]) != "" and anim.has(str(names[i])),
			"★ 形态改由**动作**表达：%s 已挂上、可播" % labels[i])
	_teardown(body)


# ============================================================ ② 形态层行为

## 真资产上的行为门。这是**本套件的核心**：上一轮就是在这里漏掉的。
##
## ⚠️ 观测口径很关键：`_process_modification()` 的写入只在**渲染求值链**里生效，
## 帧边界回读 `get_bone_pose_rotation()` 只会拿到 `AnimationPlayer` 覆盖后的原值。
## 所以这里判"写进去没"用的是**同一帧内手动调一次回调、立刻回读** ——
## 这是 headless 下唯一可信的口径，探针 ⑩ 段的同期诊断就是这么定的。
##
## ⚠️ `force_layer = true` 进来的：本段测的是**形态层实现本身**，
## 而柯西默认已让位给动作（见 `_handover`）。理由写在 `_mount` 的注释里。
static func _behavior(t: T, host: Node) -> void:
	var m: Dictionary = await _mount(host, true)
	var body := m["body"] as FlightBody
	var skel := m["skel"] as Skeleton3D
	var lay := m["lay"] as SkeletonModifier3D
	if body == null or skel == null or lay == null:
		t.ok(false, "（形态层实现质量的前置）清空 `model_anim_idle_cruise` 后应当建起形态层")
		_teardown(body)
		return

	# ---- 走了哪一档（两档互斥）----
	t.ok(body._form_curve != null,
		"★ 柯西走**曲线层**（`model_form_curve` 已配 且 端点自检通过）")
	t.ok(body._cruise_form == null,
		"★ 两档**互斥**：曲线层生效时两点层必须为 null —— 否则两个 "
		+ "SkeletonModifier3D 争写同一批形态骨，按子节点序互相覆盖")

	# ---- 形态骨清单 ----
	var got: Array = lay.call("form_bones", skel)
	t.eq(got.size(), FORM_BONES.size(),
		"★ 柯西形态骨 = %d 根（引擎实测）" % FORM_BONES.size())
	for want: String in FORM_BONES:
		t.ok(got.has(want), "形态骨含 %s" % want)

	# ---- 曲线层专属：端点自检 + 无缺骨 ----
	if body._form_curve != null:
		t.lt(body._form_curve.endpoint_max_deg, 2.0,
			"★ 端点自检：曲线首帧=常态、末帧=巡航（最大偏差 %.3f°）"
			% body._form_curve.endpoint_max_deg)
		t.eq(body._form_curve.fell_back.size(), 0,
			"8 根形态骨在曲线源里**都有**独立曲线（没有退回两点线性的）")
		t.gt(body._form_curve.key_count, 1, "曲线至少 2 个关键帧")

	# ---- `morph = 0` 必须**完全空操作** ----
	# 这是"零回归"的根基：常态路径不许因为装了形态层而改变一个字节。
	var b0 := skel.find_bone(str(got[0]))
	m["anim"].player.play("fly")
	m["anim"].player.seek(0.0, true)
	await host.get_tree().process_frame
	m["anim"].player.seek(0.0, true)
	var q_before := skel.get_bone_pose_rotation(b0)
	lay.set("morph", 0.0)
	lay.call("_process_modification")
	var q_after := skel.get_bone_pose_rotation(b0)
	t.near(rad_to_deg(q_before.angle_to(q_after)), 0.0, 0.001,
		"morph=0 ⇒ 一个字节都不写（常态路径零回归的根基）")

	# ---- `morph = 1`：**每一根**形态骨都要被写到巡航姿态 ----
	# ★ 逐根查，不只查第一根：漏掉一根 = 巡航形态缺一块，而且**不报错**。
	for b: String in FORM_BONES:
		var bi := skel.find_bone(b)
		m["anim"].player.seek(0.0, true)
		var q_b := skel.get_bone_pose_rotation(bi)
		var tgt: Quaternion = lay.call("cruise_rotation_of", bi)
		var full := rad_to_deg(q_b.angle_to(tgt))
		lay.set("morph", 1.0)
		lay.call("_process_modification")
		var q_a := skel.get_bone_pose_rotation(bi)
		t.near(rad_to_deg(q_a.angle_to(tgt)), 0.0, 1.0,
			"★ morph=1 ⇒ %s 写到巡航姿态（常态离它 %.1f°）" % [b, full])

	# ---- `morph = 0.5` 落在两端之间 ----
	# ⚠️ 必须先 `seek` 把骨 pose **复位成动画原始值**再手动调回调，
	# 否则回调读到的 `cur` 是上一次手动调**刚写进去的值** ⇒ 假读数。
	var bi0 := skel.find_bone(str(got[0]))
	var normal0: Dictionary = m["anim"].rotations_at(m["anim"].idle_action, 0.0)
	var tgt0: Quaternion = lay.call("cruise_rotation_of", bi0)
	var full0 := rad_to_deg((normal0[str(got[0])] as Quaternion).angle_to(tgt0))
	m["anim"].player.seek(0.0, true)
	lay.set("morph", 0.5)
	lay.call("_process_modification")
	var half := rad_to_deg(skel.get_bone_pose_rotation(bi0).angle_to(tgt0))
	t.between(half, 0.0, full0,
		"morph=0.5 ⇒ 落在常态与巡航之间（%.2f°，满程 %.2f°）" % [half, full0])

	# ---- ★★ 同步展开（用户 2026-09-27 明确要求 · 曲线层的存在理由）----
	# 曲线源 `xi_cruise_on` ⇒ **8 根形态骨同一进度**展开。
	# ⛔ 早先沿 `xi_morph_anim3` 是**分段**的（`Binder*` 先、`Wing*` 迟至 0.63 才动，
	#    两族差 0.50）—— 用户否掉了：「后翼下方大片翼**跟着**上方的小翼**一起**展开」。
	# ⇒ 本段把"一起展开"变成**机器判据**：同一 morph 下 8 根的**完成度彼此接近**。
	if body._form_curve != null:
		var fc := body._form_curve
		var fracs: Array[float] = []
		for sb: String in FORM_BONES:
			var sy_bi := skel.find_bone(sb)
			var sy_n0: Quaternion = normal0[sb]
			var sy_tgt: Quaternion = fc.cruise_rotation_of(sy_bi)
			var sy_full := rad_to_deg(sy_n0.angle_to(sy_tgt))
			var sy_got := rad_to_deg(sy_n0.angle_to(_curve_target_at(fc, sy_bi, SPLIT_MORPH)))
			fracs.append(sy_got / maxf(sy_full, 1e-6))
			t.between(sy_got, 1.0, sy_full - 1.0,
				"%s 在 morph=%.2f 时**动了、但没走完**（%.1f° / 满程 %.1f°）"
				% [sb, SPLIT_MORPH, sy_got, sy_full])
		var sy_lo: float = fracs.min()
		var sy_hi: float = fracs.max()
		t.lt(sy_hi - sy_lo, SYNC_TOL,
			"★★ 8 根形态骨**同步**展开：morph=%.2f 时完成度极差 %.3f ≤ %.2f"
			% [SPLIT_MORPH, sy_hi - sy_lo, SYNC_TOL])
		t.gt(sy_lo, 0.25,
			"（反例闸）极差小不是因为全都没动：最低完成度 %.3f > 0.25" % sy_lo)
		# 曲线层与两点层的**可判差异**在两端：曲线是缓动（慢起慢收），两点层纯线性。
		# 这一条把"曲线层确实不是 slerp"变成可判定的，而不是凭印象。
		var sy_ease := 0.0
		for sb2: String in FORM_BONES:
			var sy_bi2 := skel.find_bone(sb2)
			var sy_n02: Quaternion = normal0[sb2]
			var sy_full2 := rad_to_deg(sy_n02.angle_to(fc.cruise_rotation_of(sy_bi2)))
			sy_ease = maxf(sy_ease,
				rad_to_deg(sy_n02.angle_to(_curve_target_at(fc, sy_bi2, EASE_MORPH)))
					/ maxf(sy_full2, 1e-6))
		t.lt(sy_ease, EASE_TOL,
			"曲线层是**缓动**（慢起）：morph=%.2f 时最快的一根也只走到 %.3f，线性会走到 %.2f"
			% [EASE_MORPH, sy_ease, EASE_MORPH])
		# ★ 把实测值**打进日志**：否则断言通过时不留任何读数，
		#   阈值写错（恒真）也看不出来。
		print("  [同步实测] morph=%.2f 时 8 根完成度 = %s"
			% [SPLIT_MORPH, str(fracs)])
		print("  [同步实测] 极差 = %.4f（门槛 %.2f）｜ morph=%.2f 时最快一根 %.4f（门槛 %.2f）"
			% [sy_hi - sy_lo, SYNC_TOL, EASE_MORPH, sy_ease, EASE_TOL])

	# ---- ★ 引擎真的在驱动它 ----
	var c0: int = lay.get("calls")
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	t.gt(int(lay.get("calls")), c0,
		"★ 引擎在驱动 `_process_modification()`（%d → %d，不是只有我们在手动调）"
		% [c0, int(lay.get("calls"))])

	# ---- ★ 无漂移 ----
	# 回调里读到的必须是**动画刚写完的原始值**。若读到自己上一帧写的值，
	# `morph=0.5` 会逐帧叠加、单调爬向巡航姿态（不报错的"越按越展开"）。
	# 判据只能用**回调内部**的读数 `read_residual_deg` —— 帧边界读不出漂移。
	lay.set("morph", 0.5)
	var seq: Array[float] = []
	for i in 6:
		await host.get_tree().process_frame
		seq.append(float(lay.get("read_residual_deg")))
	var drift := absf(seq[seq.size() - 1] - seq[0])
	var line := ""
	for v in seq:
		line += "%.2f " % v
	t.lt(drift, 1.0,
		"★ 无漂移：morph=0.5 连续 6 帧回调内残余角稳定（%s｜首末差 %.3f°）" % [line, drift])
	t.gt(seq[0], 0.0, "残余角读数非零（证明它真的在量，不是在读一个恒 0）")

	lay.set("morph", 0.0)
	_teardown(body)


## 在**指定 morph** 下取曲线层的目标姿态（临时改 `morph` 再复位）。
static func _curve_target_at(fc: FormCurveModifier, bone_idx: int, morph: float) -> Quaternion:
	var keep := fc.morph
	fc.morph = morph
	var q := fc.curve_target_of(bone_idx)
	fc.morph = keep
	return q


# ============================================================ ②' 曲线层逻辑（合成骨架）

## 曲线层的**纯逻辑**门（合成骨架，不依赖真资产）。
##
## 装真资产测的是"柯西这条曲线对不对"；这里测的是"曲线层这套**规则**对不对" ——
## 换资产、换曲线源时，坏掉的一定是这里。
static func _build_curve(t: T, host: Node) -> void:
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	host.add_child(skel)
	skel.add_bone("Big")
	await host.get_tree().process_frame

	var q0 := Quaternion.IDENTITY
	var q30 := Quaternion(Vector3.RIGHT, deg_to_rad(30.0))
	var normal := {"Big": q0}
	var cruise := {"Big": q30}

	# ---- 端点吻合 ⇒ 建得起来 ----
	var good := {"t0": 0.0, "t1": 1.0, "bones": {"Big": {
		"t": PackedFloat32Array([0.0, 0.5, 1.0]),
		"q": [q0, Quaternion(Vector3.RIGHT, deg_to_rad(5.0)), q30],
	}}}
	var m := FormCurveModifier.setup(skel, normal, cruise, good)
	t.ok(m != null, "★ 端点吻合的曲线 ⇒ 曲线层建得起来")
	if m != null:
		t.eq(m.form_bone_count(), 1, "曲线层形态骨 1 根")
		t.eq(m.fell_back.size(), 0, "有独立曲线的骨不记入 `fell_back`")
		# ★★ 端点一律用**四元数恒等**判，⛔ 不用角度容差：
		#   `Quaternion.angle_to()` 内部是 `acos(2d²−1)`，而 `d = dot(q,q)` 在 float32 下是
		#   `1 − 1.2e-7` ⇒ `acos(1 − 2.4e-7)` = **0.0396°**。
		#   **同一个四元数自比也有 0.0396° 的噪声底**（实测逐位吻合）⇒ 任何 < 0.04° 的角度
		#   容差都是**不可达判据**（会 flaky）。恒等比较没有这个问题。
		t.ok(m.curve_target_of(0).is_equal_approx(q0), "曲线层 morph=0 的目标**就是**常态基准")
		t.ok(_curve_target_at(m, 0, 1.0).is_equal_approx(q30), "曲线层 morph=1 的目标**就是**巡航基准")
		t.lt(m.endpoint_max_deg, 0.1, "端点自检读数 ≈ 0（0.1° 已远高于 float32 噪声底 0.04°）")
		t.eq(m.key_count, 3, "`key_count` 如实反映该骨关键帧数")

	# ---- ★★ 端点对不上 ⇒ **整层放弃**（拦住"半升级"）----
	# 曲线与常态/巡航基准不同源时，硬塞进去的后果是"形态错位且不报错"。
	# 宁可整层不用（回退两点线性），也不要用一段对不上的姿态。
	var bad := {"t0": 0.0, "t1": 1.0, "bones": {"Big": {
		"t": PackedFloat32Array([0.0, 1.0]),
		"q": [q0, Quaternion(Vector3.RIGHT, deg_to_rad(7.0))],
	}}}
	t.ok(FormCurveModifier.setup(skel, normal, cruise, bad) == null,
		"★★ 曲线**末帧**对不上巡航基准（7° vs 30°）⇒ 整层放弃，上层回退两点层")
	var bad2 := {"t0": 0.0, "t1": 1.0, "bones": {"Big": {
		"t": PackedFloat32Array([0.0, 1.0]),
		"q": [Quaternion(Vector3.RIGHT, deg_to_rad(25.0)), q30],
	}}}
	t.ok(FormCurveModifier.setup(skel, normal, cruise, bad2) == null,
		"★★ 曲线**首帧**对不上常态基准（25° vs 0°）⇒ 同样整层放弃")

	# ---- 曲线里没有这根骨 ⇒ 退回两点线性，并**如实记录** ----
	var m2 := FormCurveModifier.setup(skel, normal, cruise, {"t0": 0.0, "t1": 1.0, "bones": {}})
	t.ok(m2 != null, "曲线里没有该骨 ⇒ 仍建得起来（退回两点，形态不缺块）")
	if m2 != null:
		t.eq(m2.fell_back.size(), 1, "并如实记入 `fell_back`（不是静默退回）")
		t.ok(m2.fell_back.has("Big"), "`fell_back` 里就是那根骨")
		# ★ 用**四元数恒等**判「真的到巡航姿态」——比角度容差更严，且不受 float32 噪声底影响
		#   （`angle_to` 自比就有 0.0396° 噪声，见 ②' 那组里的注释）。
		t.ok(_curve_target_at(m2, 0, 1.0).is_equal_approx(q30),
			"退回两点的骨在 morph=1 **恰好**到巡航姿态（与两点层同结果）")
		t.ok(_curve_target_at(m2, 0, 0.0).is_equal_approx(q0),
			"退回两点的骨在 morph=0 **恰好**是常态")

	# ---- 空曲线字典 ⇒ 全部走两点回退（**不是** null：有形态差就该有形态层）----
	t.ok(FormCurveModifier.setup(skel, normal, cruise, {}) != null,
		"空曲线字典 ⇒ 全部退回两点（不是 null）")

	# ---- 边界：任何一条崩了，老资产/半成品资产就会在运行期炸 ----
	t.ok(FormCurveModifier.setup(null, normal, cruise, good) == null, "无骨架 ⇒ null（不崩）")
	t.ok(FormCurveModifier.setup(skel, normal, {}, good) == null, "空巡航基准 ⇒ null")
	t.ok(FormCurveModifier.setup(skel, {}, cruise, good) == null, "空常态基准 ⇒ null（算不出差）")
	var flat := {"Big": q30}
	t.ok(FormCurveModifier.setup(skel, flat, flat, good) == null,
		"两份基准完全相同 ⇒ null（没有形态差，不需要形态层）")

	# ---- 门槛必须与两点层**同判据**（两档挑出的骨必须一致）----
	t.ok(FormCurveModifier.setup(skel, normal, {"Big": Quaternion(Vector3.RIGHT, deg_to_rad(0.2))},
		good) == null,
		"★ 与两点层同判据：差 < %.1f° 的骨不进形态层" % MIN_DEG)

	skel.free()


# ============================================================ ②'' 曲线层与回退（真资产）

## 曲线源不可用时**必须落回两点层** —— 这是退路，不是死路。
##
## 为什么单独测：`_setup_cruise_form()` 里是"曲线层建不起来 ⇒ 落到两点层"的顺序，
## 这条缝若写错（比如提前 `return`），生产上会**静默丢失巡航形态**，
## 而且只在"曲线源丢失 / 换资产 / 路径配错"时才暴露。
##
## ⚠️ N42·二十二 起两处配置都额外清掉 `model_anim_idle_cruise`：
## 本段测的是**形态层内部**的回退链，而柯西默认已让位给动作
##（`_setup_cruise_form()` 第 4 道判据一进来就早退 ⇒ 两档恒 null ⇒ 本段三条断言
## 全部失去被测对象）。清掉那一个字段，"形态层承载形态"的世界就回来了。
## ⛔ 判据本身**逐字未改** —— 既没有放宽，也没有改口径。
static func _fallback(t: T, host: Node) -> void:
	var p := SuitProfile.xi()
	p.model_path = FLY
	p.model_form_curve = "res://assets/models/xi/anim/xi_cruise_on.glb"
	p.model_form_curve = ""          # ★ 抽掉曲线源
	p.model_anim_idle_cruise = ""    # ★ 让形态层重新上岗（见函数头注释）
	var body := FlightBody.new()
	body.name = "XiFallbackBody"
	body.profile = p
	body.use_placeholder = false
	body.flight_pitch_deg = 0.0
	host.add_child(body)
	body.set_physics_process(false)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	body.set_physics_process(false)

	t.ok(body._form_curve == null, "★ 曲线源为空 ⇒ **不**建曲线层")
	t.ok(body._cruise_form != null, "★ …而是回退到两点层（已验证的老路仍在，不是死路）")
	if body._cruise_form != null:
		t.eq(body._cruise_form.form_bone_count(), FORM_BONES.size(),
			"回退层挑出的形态骨根数与曲线层一致（%d 根）" % FORM_BONES.size())
		var skel := body._model_skel
		if skel != null:
			var b0 := skel.find_bone("Wing.L")
			body.model_anim.player.seek(0.0, true)
			var tgt := body._cruise_form.cruise_rotation_of(b0)
			body._cruise_form.morph = 1.0
			body._cruise_form._process_modification()
			t.near(rad_to_deg(skel.get_bone_pose_rotation(b0).angle_to(tgt)), 0.0, 1.0,
				"★ 回退层 morph=1 ⇒ Wing.L 写到巡航姿态（回退不是空转）")
			body._cruise_form.morph = 0.0

	# 曲线源**指向不存在的文件**时也必须能退（配错路径不许让机体失去形态）。
	var p2 := SuitProfile.xi()
	p2.model_path = FLY
	p2.model_form_curve = "res://assets/models/xi/anim/xi_does_not_exist.glb"
	p2.model_anim_idle_cruise = ""   # ★ 同上：让形态层重新上岗
	var body2 := FlightBody.new()
	body2.name = "XiBadPathBody"
	body2.profile = p2
	body2.use_placeholder = false
	body2.flight_pitch_deg = 0.0
	host.add_child(body2)
	body2.set_physics_process(false)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	body2.set_physics_process(false)
	# ★★ 坏路径的真实契约 = **形态不许丢 ＋ 两档不许并存 ＋ 不许静默**，
	#   而**不是**「哪一档非空」。实测：路径不存在时 `load_curve_from()` 给出空曲线 ⇒
	#   `FormCurveModifier.setup()` 仍然建得起（逐骨退回两点，并把**全部**形态骨如实记进
	#   `fell_back`）—— 这与上面 ②' 里「空曲线字典 ⇒ 全部退回两点（**不是** null）」是
	#   **同一条明确设计**。⇒ 判据写在行为上，既抓「并存」也抓「静默退化成没有形态」。
	t.ok((body2._form_curve == null) != (body2._cruise_form == null),
		"★ 两档形态层**互斥**：坏路径下恰有一档生效（绝不并存、也绝不留空）")
	var lay: SkeletonModifier3D = null
	if body2._form_curve != null:
		lay = body2._form_curve
	else:
		lay = body2._cruise_form
	t.ok(lay != null, "曲线路径不存在 ⇒ 仍有形态层（不崩、不丢形态）")
	if body2._form_curve != null:
		t.eq(body2._form_curve.fell_back.size(), body2._form_curve.form_bone_count(),
			"坏路径 ⇒ 曲线层把**全部**形态骨如实记入 `fell_back`（不是静默退回）")
	var skel2 := body2._model_skel
	if skel2 != null and lay != null:
		var b2 := skel2.find_bone("Wing.L")
		body2.model_anim.player.seek(0.0, true)
		lay.set("morph", 1.0)
		lay.call("_process_modification")
		var want2: Quaternion = lay.call("cruise_rotation_of", b2)
		t.lt(rad_to_deg(skel2.get_bone_pose_rotation(b2).angle_to(want2)), 1.0,
			"★ 坏路径 ⇒ morph=1 真的把 Wing.L 写到巡航姿态（形态没丢）")
		lay.set("morph", 0.0)

	body.free()
	body2.free()


# ============================================================ ③ 老资产零影响

## 老资产（无骨架）上形态层必须是 null —— **没有形态层**这件事本身是设计边界，
## 不是降级。18 个老机体每一个都走这里，所以判据是"静默、安全"。
static func _zero(t: T, host: Node) -> void:
	# ★ 2026-09-28（N49）：样本从「古斯塔夫」换成「**阿利宙斯 · 巡航形态**」。
	#   古斯塔夫**已接线（27 段）**，而且它的新主模型 `gustav_fly.glb`
	#   **自带骨架**（46 骨）⇒ 拿它当"无骨架老资产"会**测错对象**
	#   （下面第一条 `_model_skel == null` 会直接变成红的）。
	#   ★ 五台机体现已**全部接线**，唯一还走老路径的就是阿利宙斯巡航形态。
	#   判据**逐字未变**（仍然是"形态层/曲线层必须为 null"），只换样本 ＋ 加一道前置。
	var oldp := SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
	t.eq(oldp.model_anim_files.size(), 0,
		"样本确实是老资产（前置：⛔ 它哪天接线了，就得换样本）")
	var body := FlightBody.new()
	body.profile = oldp
	body.use_placeholder = false
	host.add_child(body)
	body.set_physics_process(false)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	body.set_physics_process(false)

	t.ok(body._model_skel == null, "老资产没有骨架（前置）")
	t.ok(body._cruise_form == null, "★ 老资产 ⇒ 形态层为 null（零影响，不是降级）")
	t.ok(body._form_curve == null, "★ 老资产 ⇒ 曲线层也为 null（两档都不进）")
	t.ok(body.model_fsm != null, "老资产的 model_fsm 仍是哑机（契约：永不 null）")
	# 形态层的存在与否不许影响 `cruise_morph` 的推进语义
	body.cruise_morph = 0.0
	body.profile.cruise_morph = true
	body.fm.boosting = true
	body.fm.hovering = false
	for i in 40:
		body._tick_cruise_morph(1.0 / 60.0)
	t.gt(body.cruise_morph, 0.99,
		"老资产（有 blend shape 的走法）cruise_morph 照样推进到 1（没被形态层改动破坏）")

	body.free()


# ============================================================ ⑦ 帧末焊（轮 42）

## 轮 42 的形态载体契约：**柯西的形态骨由 `FormWeld` 在帧末「绝对写」**。
##
## ## 为什么它可以是一条**自动化**判据（而不必只靠探针截图）
##
## `weld()` 是**纯函数式**的：给定 `morph` 写什么完全确定，**不读任何当前值**。
## ⇒ 同步调一次、立刻回读，拿到的读数与「帧末被引擎驱动」时**逐位相同**，
## 时机问题被绕开 ⇒ 这支判据在 headless 下也成立、可回归。
##
## ## 三条判据，② ③ 必须成对（单钉 ② 会让「把骨写死成巡航」蒙混过关）
##
##   ① 载体在场，且形态骨数与形态层判据**同一批**（筛选只有一处）；
##   ② `morph = 1` ⇒ 逐根落在**巡航**姿态；
##   ③ `morph = 0` ⇒ 逐根落在**常态**姿态。
##
## ⚠️ 期望姿态是**测试侧独立算**出来的（`rotations_at()` 直接读动作首/末帧），
## **不**复用 `FormWeld` 的内部表 —— 否则就是拿被测对象证明它自己。
static func _weld_contract(t: T, host: Node) -> void:
	var m: Dictionary = await _mount(host)
	var body := m["body"] as FlightBody
	var skel := m["skel"] as Skeleton3D
	if body == null or skel == null:
		t.ok(false, "（帧末焊的前置）柯西建不起来")
		return
	var w := body._form_weld
	t.ok(w != null, "★ 柯西建起了帧末焊载体（`_form_weld`）—— 形态骨的唯一写入者")
	if w == null:
		_teardown(body)
		return
	t.eq(w.form_bone_count(), FORM_BONES.size(),
		"★ 焊接的形态骨 = %d 根（借形态层的骨名筛选）" % FORM_BONES.size())
	for b: String in FORM_BONES:
		t.ok(w.form_bones().has(b), "焊接表含 %s" % b)
	t.eq(w.skipped.size(), 1,
		"★ 只滤掉 1 根（`Shoulder.L` 差 4.00° < 焊接门槛 20°）—— 覆盖式焊接不为它冻结肩甲")

	# ---- 判据 ② ③ 的期望值：测试侧独立算 ----
	var anim := body.model_anim
	if anim == null or not anim.ready:
		t.ok(false, "（帧末焊的前置）`ModelAnimator` 没就绪")
		_teardown(body)
		return
	var want_cruise := anim.rotations_at(anim.idle_cruise_action)
	var want_normal := anim.rotations_at(anim.idle_action, 0.0)

	# ---- ② 焊到巡航 ----
	w.weld(1.0)
	var worst_c := 0.0
	for b: String in FORM_BONES:
		if not want_cruise.has(b):
			continue
		var q := skel.get_bone_pose_rotation(skel.find_bone(b))
		worst_c = maxf(worst_c, rad_to_deg(q.angle_to(want_cruise[b] as Quaternion)))
	# ⚠️ 容差 0.5°：`angle_to()` 内部是 `2*acos(|dot|)`，在 dot≈1 处导数发散，
	# float32 的 ~1e-7 点积误差会被放大成 ~0.03° 的读数噪声（实测 0.0560°）。
	# 0.5° 比噪声大一个数量级、比基线差（141°）小两个多数量级 ⇒ 判据仍能变红。
	t.lt(worst_c, 0.5,
		"★ `morph=1` ⇒ 逐根落在**巡航**姿态（最大残差 %.4f°）" % worst_c)

	# ---- ③ 焊回常态（这一条是 ② 的对照：证明写的是「随 morph 动」而不是死值）----
	#
	# ⚠️ 先把骨**直接推离常态**（不走 `weld()`）：否则若 `weld()` 是空操作，
	# 骨本来就停在常态附近（`_mount()` 之后 FSM 起播 `fly`）⇒ 这条会**假绿**。
	# 负对照实测过这个假绿，才补的这段。起点钉在巡航端，③ 才真的在问
	# 「你能不能把它拉回来」。
	for b: String in FORM_BONES:
		if want_cruise.has(b):
			skel.set_bone_pose_rotation(skel.find_bone(b), want_cruise[b] as Quaternion)
	w.weld(0.0)
	var worst_n := 0.0
	for b: String in FORM_BONES:
		if not want_normal.has(b):
			continue
		var q2 := skel.get_bone_pose_rotation(skel.find_bone(b))
		worst_n = maxf(worst_n, rad_to_deg(q2.angle_to(want_normal[b] as Quaternion)))
	t.lt(worst_n, 0.5,
		"★ `morph=0` ⇒ 逐根落在**常态**姿态（最大残差 %.4f°）" % worst_n)

	# ---- 区分度：两个方向必须真的差开，否则「焊的是死值」----
	var r0 := w.residual_deg()
	w.weld(1.0)
	var r1 := w.residual_deg()
	t.lt(r1, 0.5, "★ `morph=1` ⇒ 离巡航 %.4f°（≈0 = 真焊上去了）" % r1)
	t.gt(r0, 100.0, "★ `morph=0` ⇒ 离巡航 %.2f°（≈两基准夹角 = 不是死值）" % r0)
	t.gt(r0 - r1, 100.0,
		"★ 两个方向的区分度 %.2f°（若 ≈ 0 ⇒ 焊的是死值，退巡航收不回来）" % (r0 - r1))

	# ============================================================ 判据 ④⑤⑥：**位置**
	#
	# ## 为什么必须有这一组（N52）
	#
	# 轮 42 的 `FormWeld` 自称那 8 根形态骨的「唯一写入者」，却**只写 rotation**。
	# 而一个骨 pose = **T·R·S** ⇒ 世界变换 = **旋转取焊缝 ＋ 位移取动画**，
	# 而这 8 根骨的展开**有一大半靠位移**（`RearHang.R` 两端差 1.1607 ≈ 118% 身高）
	# ⇒ 一按方向键（那 8 根骨在方向动作族里**没有位置轨** ⇒ 引擎把未覆盖的轨
	# **混合回 rest = 常态位**），翼就「以展开的角度贴回机体」= 用户报的
	# 「按哪个键都会关上飞行翼」。**上面 ②③ 那一组全是旋转，一条都照不到这个洞。**
	#
	# ⚠️ 期望值仍然**测试侧独立算**（`locations_at()` 直接读 glb 轨），不复用
	# `FormWeld._normal_pos` / `_cruise_pos` —— 否则又是拿被测对象证明它自己。
	#
	# ⚠️ 先钉「位置通路启用」，否则下面三条会在**空表**上假绿（`weld()` 跳过位置分支
	# 时，残差读数是 `-1.0` —— `residual_pos()` 特意**不伪装成 0**，见其注释）。
	t.ok(w.has_positions(),
		"★ 帧末焊**位置通路已启用**（`_normal_pos` / `_cruise_pos` 整表等长）")
	if not w.has_positions():
		_teardown(body)
		return

	# 期望：常态侧 = `fly` 首帧的位置轨；**缺该轨时按生产同一规则用 rest 补**
	#（"动画不写位置轨"本身就是语义：那根骨停在 rest）。
	# ⚠️ 这不是"把生产的实现抄进测试"（T45 警告的那种），而是**复刻生产路径的赋值**：
	#   `fly` 实测为 POS 1 / ROT 26，8 根形态骨**一条位置轨都没有** ⇒ 不补这一步，
	#   测试量的会是"另有一条位置轨的世界"，断言集体变红而生产代码是对的。
	var pos_cruise := anim.locations_at(anim.idle_cruise_action)
	var pos_normal_raw := anim.locations_at(anim.idle_action, 0.0)
	# 容差：本地单位。8 根里两端差**最小**的是 `BinderFront.R` 0.0776
	# ⇒ 取 0.02（≈ 最小信号的 26%、比 float 噪声大 5 个数量级）。
	const POS_TOL_LOCAL := 0.02

	# ---- ④ 推离 + 焊到巡航：位置必须落在**巡航**位置 ----
	#
	# ⚠️ 起点先推到**常态端**：否则"焊到巡航"可能是"本来就停在巡航"（假绿）。
	# 常态端取 **rest**（= `fly` 不写位置轨时那根骨的稳态，见上面的 rest 规则）。
	for b: String in FORM_BONES:
		var bi := skel.find_bone(b)
		if bi >= 0:
			skel.set_bone_pose_position(bi, skel.get_bone_rest(bi).origin)
	var n_pos_moved := 0
	for b: String in FORM_BONES:
		if pos_cruise.has(b):
			n_pos_moved += 1
	t.eq(n_pos_moved, FORM_BONES.size(),
		"★ `cruise_idle` 对 8 根形态骨**都有位置轨**（测试侧独立读得 %d 条）" % n_pos_moved)
	w.weld(1.0)
	var worst_pc := 0.0
	var worst_pc_bone := ""
	for b: String in FORM_BONES:
		var bi := skel.find_bone(b)
		if bi < 0 or not pos_cruise.has(b):
			continue
		var d: float = skel.get_bone_pose_position(bi).distance_to(pos_cruise[b] as Vector3)
		if d > worst_pc:
			worst_pc = d
			worst_pc_bone = b
	t.lt(worst_pc, POS_TOL_LOCAL,
		"★ `morph=1` ⇒ 逐根位置落在**巡航位置**（最大残差 %.4f 本地单位 ｜ %s）" % [worst_pc, worst_pc_bone])

	# ---- ⑤ 焊回常态：位置必须落回**常态**（= `fly` 无位置轨 ⇒ rest） ----
	#
	# ⚠️ 起点**显式**钉在巡航端（不复用 ④ 的结果）：若 `weld()` 不写位置，
	# 位置会**留在巡航** ⇒ 这条**独立地**变红。
	# 【与 ③ 同一条规矩：先直接推离目标，否则"它本来就在那儿"会给出假绿】
	for b: String in FORM_BONES:
		var bi := skel.find_bone(b)
		if bi >= 0 and pos_cruise.has(b):
			skel.set_bone_pose_position(bi, pos_cruise[b] as Vector3)
	var worst_pn := 0.0
	var worst_pn_bone := ""
	var n_normal_checked := 0
	w.weld(0.0)
	for b: String in FORM_BONES:
		var bi := skel.find_bone(b)
		if bi < 0:
			continue
		var want_p: Vector3 = pos_normal_raw[b] as Vector3 if pos_normal_raw.has(b) \
			else skel.get_bone_rest(bi).origin
		var d: float = skel.get_bone_pose_position(bi).distance_to(want_p)
		n_normal_checked += 1
		if d > worst_pn:
			worst_pn = d
			worst_pn_bone = b
	t.eq(n_normal_checked, FORM_BONES.size(), "（前置）8 根形态骨的骨下标都找得到")
	t.lt(worst_pn, POS_TOL_LOCAL,
		"★ `morph=0` ⇒ 逐根位置落回**常态位置**（最大残差 %.4f 本地单位 ｜ %s）" % [worst_pn, worst_pn_bone])

	# ---- ⑥ 位置的区分度：两个方向必须真的差开，且量级 = glb 轨给的位移 ----
	#
	# ⚠️ 单钉 ④ 会被「把位置写死成巡航」蒙混过关；⑥ 用**动作里真实存在**的位移
	#   （`locations_at` 两端之差）当尺子，把「写死」和「随 morph 动」分开。
	var pr0 := w.residual_pos()
	w.weld(1.0)
	var pr1 := w.residual_pos()
	t.lt(pr1, POS_TOL_LOCAL, "★ `morph=1` ⇒ 离巡航位置 %.4f 本地单位（≈0 = 真写进去了）" % pr1)
	var span_expect := 0.0
	var span_bone := ""
	for b: String in FORM_BONES:
		var bi := skel.find_bone(b)
		if bi < 0 or not pos_cruise.has(b):
			continue
		var want_p: Vector3 = pos_normal_raw[b] as Vector3 if pos_normal_raw.has(b) \
			else skel.get_bone_rest(bi).origin
		var sp: float = (pos_cruise[b] as Vector3).distance_to(want_p)
		if sp > span_expect:
			span_expect = sp
			span_bone = b
	t.gt(pr0, 0.5 * span_expect,
		"★ `morph=0` ⇒ 离巡航位置 %.4f（应 ≈ 最大两端差 %.4f · %s ⇒ 不是死值）" % [
			pr0, span_expect, span_bone])
	t.gt(pr0 - pr1, 0.5 * span_expect,
		"★ 位置两个方向的区分度 %.4f（若 ≈ 0 ⇒ 位置写的是死值）" % (pr0 - pr1))

	# ============================================================ 判据 ⑦⑧⑨⑩⑪：**祖先闭包**（N55）
	#
	# ## 为什么必须有这一组
	#
	# `FormWeld` 自称那 8 根形态骨的「唯一写入者」—— 但一根骨的**世界**变换 =
	# **自身局部 TRS** × **祖先链姿态**（第二条轴：层级）。它只写前者
	# ⇒ 16 段方向动作把父骨（`Chest` / `Spine` / `Shoulder.*` / `Hips`）写回常态时，
	# 翼被**整条父链**拖着走：实测**抬起 20% 身高、总位移 26% 身高**
	#（`tools/probe_xi_wing_world.gd` §2/§3；离线 FK `_relay/n55_wing_drift_fk.py` 逐位吻合）。
	# 上面的 ①–⑥ 全在**自身 TRS** 那一层，一条都照不到这个洞。
	#
	# ⚠️ 期望姿态仍然**测试侧独立算**（`rotations_at(form_on)` 直接读 glb 末帧），
	#    不复用 `FormWeld._anc_cruise`。
	# ⚠️ ⑨⑩⑪ 必须**先钉 `has_ancestors()`**：闭包为空时 `residual_ancestor_deg()` 返回 0.0，
	#    而 0.0 恰好等于「焊得很完美」⇒ 会在空表上**假绿**（同 `residual_pos()` 的 `-1.0` 那件事）。
	var anc_c := anim.rotations_at(anim.form_on_action) if anim.form_on_action != "" else {}
	t.ok(not anc_c.is_empty(), "（前置）`form_on` 末帧读得到（= 巡航父链姿态的独立来源）")

	# ---- ⑦ 闭包**在场**且**成员正确** ----
	t.ok(w.has_ancestors(), "★ N55：`FormWeld` 建起了**祖先闭包**（`_anc_idx` 非空）")
	var want_anc := ["Shoulder.L", "Shoulder.R", "Chest", "Spine", "Hips"]
	for b: String in want_anc:
		t.ok(w.ancestor_bones().has(b),
			"★ 闭包含 `%s`（形态骨的祖先，且常态↔巡航有差）" % b)
	t.eq(w.ancestor_count(), want_anc.size(),
		"★ 闭包 = %d 根（8 形态骨 ＋ 5 祖先）｜ `Shoulder.L` 只差 4° 但**是 4 根挂架骨的直接父骨**，必须在内"
		% want_anc.size())
	t.ok(not w.ancestor_bones().has("Root"),
		"★ `Root` **不在**闭包里（它是 `Hips` 的父骨，但常态↔巡航差 0.00° ⇒ 自动排除）")
	t.ok(w.ancestors_have_positions(),
		"★ 祖先**位置通路**也启用了（旋转是主因 25.8 / 26.0，但按「一旦接管就全分量接管」成对写）")

	# ---- ⑧ 门控②b：接管窗 = 「形态真的停在巡航稳态」（`morph >= 0.999`）----
	#
	# 钉的是**本轮的第二次修订**：最初只用「不在 `State.FORM` 窗口内」当判据，
	# 于是焊缝在 `morph` 刚离开 0 的**第一帧**就开始写祖先，而 `form_on` 要等
	# `morph >= 0.5` 才起手、且从**常态**起手 ⇒ 交接那一帧躯干**弹回**：
	# 实测相邻帧位移 **0.08925**（稳态 0.0407）。收紧接管窗后 交接帧/邻居中位数 = **1.00×**。
	var keep_morph := body.cruise_morph
	body.cruise_morph = 1.0
	t.ok(body._ancestors_armed(), "★ `cruise_morph = 1.0` ⇒ 祖先接管窗**打开**")
	body.cruise_morph = 0.963
	t.ok(not body._ancestors_armed(),
		"★ `cruise_morph = 0.963`（`form_on` 播完那一刻的**实测**值）⇒ 接管窗**关闭**（让位作者动画）")
	body.cruise_morph = 0.5
	t.ok(not body._ancestors_armed(), "★ `cruise_morph = 0.5` ⇒ 接管窗关闭")
	body.cruise_morph = keep_morph

	if w.has_ancestors() and not anc_c.is_empty():
		var anc_n := anim.rotations_at(anim.idle_action, 0.0)

		# ---- ⑨ 门控①：`morph == 0` 时**一个字节都不许写祖先** ----
		#
		# ⚠️ 起点先**推到巡航端**：不写 ⇒ 停在巡航 ⇒ 残差 ≈ 0；
		# 门控① 一旦漏了（写了常态）⇒ 残差 ≈ 常态↔巡航夹角 ⇒ **变红**。
		#（反面：起点留在常态时「写常态」与「不写」读数一样 ⇒ 假绿。）
		_push_anc(skel, w, anc_c)
		var before0 := w.ancestor_writes
		w.weld(0.0)   # `ancestors_ok` 默认 true ⇒ 只有门控① 能挡住
		t.eq(w.ancestor_writes - before0, 0,
			"★ 门控①：`morph=0` ⇒ 祖先写入**零增量**（非巡航动作的躯干交给动画，不钉死）")
		t.lt(w.residual_ancestor_deg(), 0.5,
			"★ 门控①：`morph=0` 后祖先**仍停在巡航端**（残差 %.4f° ⇒ 确实没被写）"
			% w.residual_ancestor_deg())

		# ---- ⑩ `morph=1` ＋ 接管窗开 ⇒ 走**生产入口**也必须写祖先到巡航 ----
		t.ok(body.model_fsm == null or body.model_fsm.state != ModelAnimFSM.State.FORM,
			"（前置）测试时 FSM **不在** `State.FORM` 窗口（否则门控② 会正确地把祖先挡住）")
		_push_anc(skel, w, anc_n)
		var before1 := w.ancestor_writes
		body.cruise_morph = 1.0
		body._weld_form_bones()   # 生产入口（含门控①/②/②b 三个条件）
		t.eq(w.ancestor_writes - before1, 1,
			"★ 生产入口 `_weld_form_bones()` 在巡航稳态下**真的写了祖先**（计数增量 1）")
		t.lt(w.residual_ancestor_deg(), 0.5,
			"★ `morph=1` ⇒ 祖先逐根落在**巡航姿态**（最大残差 %.4f°）"
			% w.residual_ancestor_deg())

		# ---- ⑪ 门控②：`ancestors_ok = false`（`State.FORM` 窗口）⇒ 祖先退位 ----
		_push_anc(skel, w, anc_n)
		var before2 := w.ancestor_writes
		w.weld(1.0, false)
		t.eq(w.ancestor_writes - before2, 0,
			"★ 门控②：`ancestors_ok=false` ⇒ 祖先写入**零增量**（形态过渡期间让位给作者动画）")
		t.gt(w.residual_ancestor_deg(), 1.0,
			"★ 门控②：祖先**仍停在常态端**（残差 %.2f° ⇒ 没被焊缝覆盖）"
			% w.residual_ancestor_deg())

	_teardown(body)


## 把闭包里每根祖先骨的**局部旋转**直接推到 `targets`（骨名 → 四元数）。★ N55
##
## ⚠️ 这是 ⑨⑩⑪ 的**负对照起点**：不先把它们推离目标，「它本来就在那儿」会让断言假绿。
static func _push_anc(skel: Skeleton3D, w: FormWeld, targets: Dictionary) -> void:
	for b: String in w.ancestor_bones():
		var bi := skel.find_bone(b)
		if bi >= 0 and targets.has(b):
			skel.set_bone_pose_rotation(bi, targets[b] as Quaternion)


# ============================================================ 工具

## 装一台**带骨的新资产**柯西（生产代码路径 + 只换 `model_path`）。
##
## ⚠️ 进来就冻物理：测试场景没有地面，物理一开机体会坠落自毁，
## 而 `destroy()` 会把 `model_root.visible` 关掉（探针踩过这个坑）。
##
## ## `force_layer`（N42·二十二 新增）
##
## `true` = 强制回到**形态层承载形态**的世界 —— 把 `model_anim_idle_cruise`
## 清空，`_setup_cruise_form()` 就不早退了。
##
## ★ 为什么需要它：N42·二十一 方案 B 之后，柯西**默认不再建形态层**
##（形态改由 `cruise_idle` / `form_on` / `form_off` 三件动作表达 —— 见 `_handover`），
## ⇒ `_form_curve` 与 `_cruise_form` 恒为 null，于是下面那些
## **形态层实现质量**的断言（形态骨清单、`morph=0/0.5/1` 的写入、无漂移、
## 同步展开）会整批失去被测对象。
##
## ⚠️ 但它们**一条都不能删**：形态层代码还在工程里，且**其余五台机体仍走它**
##（柯西在"文件缺失 / 名字写错"时的回退路径也走它）。
## ⇒ 正解不是放宽判据，而是**把被测对象拉回来**：
##   清掉那一个字段，"形态层承载形态"的世界就重现了，判据逐字不变。
##   （顺带钉住一件事：早退的判据**就只有这一个字段**。）
static func _mount(host: Node, force_layer := false) -> Dictionary:
	var p := SuitProfile.xi()
	# 只改 model_path —— `model_anim_files` 已在 `SuitProfile.xi()` 里配好，
	# 测试不自己拼一份，免得"测试里的配置"和"生产里的配置"分叉。
	p.model_path = FLY
	p.model_form_curve = "res://assets/models/xi/anim/xi_cruise_on.glb"
	if force_layer:
		# `flight_body._setup_cruise_form()` 第 4 道判据（早退）的唯一输入。
		p.model_anim_idle_cruise = ""
	var body := FlightBody.new()
	body.name = "XiFormBody"
	body.profile = p
	body.use_placeholder = false
	body.flight_pitch_deg = 0.0
	host.add_child(body)
	# ⚠️ **立刻**冻物理：测试场景没有地面，物理一开机体就在头几帧坠落自毁，
	# 而 `destroy()` 会关掉 `model_root.visible`（探针踩过这个坑，日志里
	# 表现为一行 `[destroy] MESSER: 撞海`）。
	body.set_physics_process(false)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	body.set_physics_process(false)
	# ★ 统一给"当前生效的那一档"：曲线层优先、两点层回退。
	# 两档的公共接口刻意同构 ⇒ 测试用 `lay` 动态访问即可，不必为两档写两遍。
	var lay: SkeletonModifier3D = body._form_curve
	if lay == null:
		lay = body._cruise_form
	return {
		"body": body,
		"skel": body._model_skel,
		"anim": body.model_anim,
		"lay": lay,
	}


static func _teardown(body: Node) -> void:
	if body != null and is_instance_valid(body):
		body.free()
