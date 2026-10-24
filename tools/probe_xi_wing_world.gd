extends Node
## N55 · D0/D1 —— 柯西形态骨「**世界漂移**」判据探针（**只读**：不改工程逻辑、不写工程文件）。
##
## ## 它要补的那个洞（N52 的探针为什么没抓到）
##
## `tools/probe_wing_pos.gd`（N52·S0）把判据落在「`Hips` 局部系里的骨原点」上 ——
## 方向是对的，但它的通过线是**无量纲的二选一**（`离巡航/离常态 ≤ 0.20`），
## 于是**今天这 26% 的漂移被当成噪声容忍掉了**：它的注释里明确记着「修好位置通路后
## 仍剩 **1.7565 世界单位**」—— 那正是本探针要抓的症状本身。
##
## ## 判据落在「渲染真正消费的那一层」，且参考物**独立于被测对象**
##
## 读数 = 形态骨的**骨原点**，表达在 **`Skeleton3D` 节点自身的坐标系**里
## （`get_bone_global_pose(i).origin`）：
##
## | 项 | 含不含 | 为什么 |
## |---|---|---|
## | 世界平移 / 机体姿态（`model_pivot` / `spin_pivot`） | ✗ | 它们挂在**骨架之上** ⇒ 不进来 |
## | **焊缝的写入** | ✗ | 焊缝写的是**骨 pose**；参考系是骨架**节点** ⇒ 参考物不会被一起焊住 |
## | 祖先链的姿态 | ✓ | **这正是被测的那个自由度**（N55·T53） |
##
## ⚠️ 为什么**不**沿用 `Hips` 当参考骨（`probe_wing_pos.gd` 的写法）：
## 修好之后 `Hips` **自己也在闭包里被焊住** ⇒ 参考物与被测对象**一起被钉死** ⇒
## 判据自证（T35/T52 同族）。骨架节点则永远在焊缝的管辖之外。
##
## ⚠️ 单位：骨架局部系 = **模型的本地单位**（未经 `target_height` 缩放）⇒ 与离线
## FK 脚本 `_relay/n55_wing_drift_fk.py` 的读数（`dash_f` 首帧 **0.2547**）**同一口径**，
## 可直接对表。占身高的比例用**运行时量的骨架高度**做分母，不写死常数。
##
## ## 段（缺一段都不算证）
##
## | 段 | 干什么 | 出口判据 |
## |----|--------|----------|
## | §0 | 装配诊断：形态骨 / 被 `WELD_MIN_DEG` 滤掉 / 祖先闭包 / 参考系可用性 | 参考骨必须找得到（找不到就说出来，不静默回退） |
## | §1 | 自检：① `seek()` 真的驱动骨架吗 ② **引擎真的在推焊缝吗**（`welds` 计数） | 两条都过，否则下面所有读数作废 |
## | §2 | ★ **主判据**：**`form_on` 末帧**基准（= 引擎里真正还在的巡航父链姿态，见 §2 注释）vs 17 段「展开态下按 WASD」动作 | 修好前 ≈ **0.2547**；修好后 **≤ 0.005** |
## | §3 | 逐骨 `Δy`（「上抬」的直接读数） | 修好前 `RearHang.*` 应为正 |
## | §4 | 非巡航（`morph = 0`）**全骨指纹**：`--dump` / `--cmp` | 改动前后**逐位相同**（门控①的证伪条） |
## | §5 | 证伪条：`--weld=off` ⇒ 应回到 ≈ **1.0949**；修好后 `--anc=off` ⇒ 应回到 ≈ **0.2547** | 红/绿可复现 |
##
## ## 跑法（**读数探针** ⇒ 可以 `--headless`；本探针不出图，出图在 `--shots` 的另一支）
##
##   <godot_console> --path <工程> res://tools/probe_xi_wing_world.tscn -- \
##       [--dump <路径>] [--cmp <路径>] [--weld=off] [--anc=off]
##
## ⚠️ **必须走场景**（`res://tools/probe_xi_wing_world.tscn`），**不能用 `--script`**：
## `--script` 不实例化 autoload，而工程脚本引用 `Settings` / `Game` ⇒ 编译不过。

## 与物理帧率一致 ⇒ 迭代数直接就是时间（同 `probe_wing_pos.gd` 的约定）。
const DT := 1.0 / 60.0

## ① 8 根形态骨 —— **仅用于打印与逐骨表**。真正「挑骨」的判据只有一处
##（`CruiseFormModifier.setup()`），探针**不重算**它，只**借**结果（读 `FormWeld`）。
const FORM_BONES := [
	"Wing.L", "Wing.R",
	"BinderFront.L", "BinderFront.R",
	"BinderBack.L", "BinderBack.R",
	"RearHang.L", "RearHang.R",
]

## ② 参考骨候选（**必须不被焊缝写入**）。`Root` 是 `Hips` 的父骨，柯西实测
## 常态↔巡航差 **0.00° / 0.0000** ⇒ 闭包封到 `Hips` 就封口了 ⇒ `Root` 永远在管辖之外。
## ⚠️ 找不到就**明说并跳过**（不静默改用 `Hips` —— 那会让判据自证）。
const REF_BONE := "Root"

## ②b 祖先闭包的**候选骨名** —— **只用于诊断打印**（「父链漂移」那一列）。
## ⛔ 生产侧的闭包由 `FormWeld.setup()` 从骨架算出来，**不读这张表**（判据只能有一处）。
const ANCESTORS := ["Shoulder.L", "Shoulder.R", "Chest", "Spine", "Hips", "Root"]

## ③ 一段动作取几个相位（只看首帧会漏掉中段更差的时刻）。
const PHASES := [0.0, 0.25, 0.5, 0.75]

## ④ 主判据覆盖的动作 = 「**展开态下按 WASD**」。⛔ 不含 `form_on`/`form_off`/
## `trans_*`/`cruise_on`（那些**本来就要改变**翼位，见方案 §3 的时机表）。
const MAIN_ACTIONS := [
	"dash_f", "dash_b", "dash_l", "dash_r",
	"dash_fl", "dash_fr", "dash_bl", "dash_br",
	"fly_f", "fly_b", "fly_l", "fly_r",
	"fly_fl", "fly_fr", "fly_bl", "fly_br",
	"burst_cruise",
]

## ⑤ 通过线（方案 §7）。**主口径 = 占骨架高度的比例**；绝对值同时打印。
const PASS_FRAC := 0.005

## §7 出图的**每格**图幅（与 `probe_wing_pos.gd` 的 `W`/`H` 一致 ⇒ 两份图可直接并列看）。
const SHOT_W := 400
const SHOT_H := 470

## §7 出图的机位。**只留侧视**：
## 「上抬」是**竖直方向**的自由度，侧视对它的投影最大（轮 34 的机位法则：判一个自由度，
## 机位要垂直于它 —— 俯视会把竖直位移投影成 0）。加第二机位只会让 8 格变糊，
## 而本图要回答的问题只有一个是/否：**关掉闭包后，后翼在巡航下按方向键会不会抬起**。
const VIEWS_SHOT := [
	[90.0, 8.0, "侧视"],
]

## §7 的**行** = 两种状态。第一行是**对照**（`form_on` 末帧：动画自己就把祖先摆到巡航位
## ⇒ 开/关两格**本来就该一样**）；第二行才是症状（`dash_f`：动画把祖先摆到**常态**位）。
const SHOT_STATES := [
	["巡航稳定", "form_on", -1.0],
	["dash_f", "dash_f", 0.5],
]

## §7 的**列** = 祖先闭包 **开 / 关**（关 = 改动前的行为）。
const SHOT_GATES := [
	["闭包开", true],
	["闭包关", false],
]

var dump_path := ""
var cmp_path := ""
var weld_off := false
var anc_off := false
## ★ §6（`--form-trace`）：走**生产 `_process` 链**逐帧记录 `State.FORM` 的进出边界。
## ⚠️ 必须配 `--fixed-fps 60`（见 `_form_trace()` 的说明）。
var form_trace := false

## ★ §7（`--shots=<目录>`）：真机出图。⚠️ **不能配 `--headless`** ——
## headless 是 dummy 渲染器，`get_viewport().get_texture().get_image()` 拿不到像素。
var shots_out := ""

var _ok_all := true
var _height := 1.0


func _ready() -> void:
	_parse_args()
	_build_env()
	if shots_out != "":
		DirAccess.make_dir_recursive_absolute(shots_out)
		DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await get_tree().physics_frame

	FlightBody.use_placeholder = false
	var fb := await _mount(SuitProfile.xi())
	# ★ 关掉宿主自己的 `_process`：`_tick_effects()` 会自己推 `cruise_morph`、机体姿态
	#   与转身层 ⇒ 逐相位读数会被"多推一帧"污染。关掉之后 `mixer_applied` 照常发
	#   （那是引擎求值链，与 `_process` 无关）。
	fb.set_process(false)

	var skel := fb._model_skel
	var w: FormWeld = fb._form_weld
	if skel == null or fb.model_anim == null or fb.model_anim.player == null:
		_fatal("骨架 / 动画播放器没建起来 ⇒ 本探针无意义")
		return
	if w == null:
		_fatal("`_form_weld` 没建起来 ⇒ 本探针无意义（柯西应当有）")
		return

	_height = _skel_height(skel)
	var ref_ok := skel.find_bone(REF_BONE) >= 0

	# ============================================================== §0 装配诊断
	_line()
	print("§0 装配诊断")
	_line()
	print("  参考骨 = %s  存在=%s" % [REF_BONE, str(ref_ok)])
	if not ref_ok:
		print("  ⛔ 参考骨不存在 ⇒ **不静默改用 Hips**（那会让判据自证）⇒ 本节及以下全部作废")
	print("  形态骨 %d 根：%s" % [w.form_bone_count(), str(w.form_bones())])
	print("  被 `WELD_MIN_DEG=%.1f°` 滤掉：%s" % [FormWeld.WELD_MIN_DEG, str(w.skipped)])
	print("  位置通路启用 = %s（`residual_pos()` 未启用时返 -1.0，不伪装成 0）" % str(w.has_positions()))
	print("  骨架高度（运行时量）= %.4f 模型本地单位" % _height)
	print("  动作表 %d 段：%s" % [fb.model_anim.action_names().size(),
		str(fb.model_anim.action_names())])
	var closure := _closure_of(skel, w)
	print("  ★ 祖先闭包（探针只**显示**；生产侧的闭包必须由 `FormWeld` 自己算）=")
	if closure.is_empty():
		print("      （空：没找到形态骨的祖先？）")
	for c in closure:
		print("      %s" % c)

	# ---- §0b ★ 轨道覆盖：引擎里的动作**到底有没有**祖先骨的轨道 ----
	#
	# 这一步是必须的：离线读 `.glb` 得到的「父链姿态 = 常态」只有在**引擎里那些轨道还在**
	# 时才成立。Godot 的 glTF 导入带「Remove Immutable Tracks」（常量轨道会被删掉），
	# 一旦祖先骨在方向动作里的轨道被删，父链就**不会**被那段动作驱动 ——
	# 那么「按 WASD 就上抬」的成因就**不是**父链，本方案整个要重做。
	# ⇒ 判据先钉在**引擎侧的事实**上，别拿离线结论当引擎结论（T33）。
	_line()
	print("§0b 轨道覆盖（引擎侧 `Animation` 里真的有那些骨吗）")
	_line()
	var probe_acts := [fb.model_anim.idle_action, fb.model_anim.idle_cruise_action,
		"dash_f", "fly_f", "turn_yaw_L", "burst_cruise", "form_off"]
	for nm: String in probe_acts:
		_track_report(fb, nm, closure)
	print("  --- 旋转轨的**骨名清单**（判断「有没有被导入器按常量删掉」要靠这个）---")
	for nm: String in [fb.model_anim.idle_action, fb.model_anim.idle_cruise_action, "dash_f", "form_on"]:
		print("  %-20s %s" % [nm, str(_rot_bones(fb, nm))])

	# ---- §0c ★★ 父链姿态采样：**巡航的那一套父链姿态在引擎里由谁建立？** ----
	#
	# 这一步是本轮排查的转折点。离线读 `.glb` 时 `cruise_idle` 带全部 51 根骨的轨道，
	# 于是「巡航的父链姿态 = `cruise_idle` 末帧」。但**引擎里 `cruise_idle` 只剩
	# 19 条旋转轨**（常量轨被导入器删了）⇒ `Chest`/`Spine`/`Hips`/`Shoulder.R`
	# 在 `cruise_idle` 里**没有轨道**，它们的值 = **上一段动作留下的**（不是 rest，也不是巡航）。
	# ⇒ 用 `cruise_idle` 末帧当基准会**读到一串残留值**（探针第一版就是这么错的：
	#   于是把「按 WASD 不漂」假读成了 2.5%）。**巡航的父链姿态只能由 `form_on` 末帧建立**
	#   （游戏里也是这条路：按住 Shift ⇒ `form_on` 播完 ⇒ 父链留在巡航位 ⇒ `cruise_idle` 循环）。
	_line()
	print("§0c ★ 父链姿态采样（局部旋转，欧拉°，相对**该动作自己的首帧**无关 —— 看绝对姿态）")
	print("      参考：`form_on` 末帧 = 作者定义的**巡航父链姿态**；`fly` 首帧 = 常态父链姿态")
	_line()
	var samples := [["fly", 0.0], [fb.model_anim.idle_action, 0.0],
		[fb.model_anim.idle_cruise_action, 0.0], [fb.model_anim.idle_cruise_action, -1.0],
		["form_on", 0.0], ["form_on", -1.0], ["dash_f", 0.0], ["fly_f", 0.0],
		["form_off", 0.0], ["burst_cruise", 0.25]]
	print("  %-22s %-6s %s" % ["动作", "相位", "  ".join(ANCESTORS)])
	var euler_of := {}
	for s in samples:
		var nm2: String = s[0]
		if not fb.model_anim.has(nm2):
			continue
		var t2: float = float(s[1]) * _dur(fb, nm2) if float(s[1]) >= 0.0 else -1.0
		await _pose_at(fb, nm2, t2)
		var row := []
		for b: String in ANCESTORS:
			var bi := fb._model_skel.find_bone(b)
			if bi < 0:
				row.append("  --  ")
				continue
			var q := fb._model_skel.get_bone_pose_rotation(bi)
			var e := q.get_euler()
			row.append("%6.2f" % rad_to_deg(e.x))
			euler_of["%s@%.2f/%s" % [nm2, s[1], b]] = rad_to_deg(e.x)
		print("  %-22s %-6.2f %s" % [nm2, s[1], "  ".join(row)])

	if not ref_ok:
		get_tree().quit(1)
		return

	# ============================================================== §1 自检两条
	_line()
	print("§1 自检（不过就说明下面所有读数无效，先修探针）")
	_line()
	await _self_check_engine_welds(fb, w)
	await _self_check_seek(fb)
	if not _ok_all:
		print("\n⛔ 自检没过 ⇒ 后面的读数一律不采信。")
		get_tree().quit(1)
		return

	# ============================================================== 参考态
	#
	# ★★ 参考态取 **`form_on` 末帧**，**不是** `cruise_idle` 末帧。
	#
	# 这一条是本探针**第二版才改对**的：第一版照方案 §1.3 的离线口径取
	# `cruise_idle` 末帧，结果把「26% 上抬」读成了 **2.5%**（`_relay/n55_d0d.log`
	# §2 里 16 段方向动作全是 `0.0216`）—— 判据把症状读没了。
	#
	# ## 为什么（「离线 `.glb` 有什么」≠「引擎里还在」的又一个实例，T33 同族）
	#
	# 离线解析 `.glb` 时 `cruise_idle` 带**全部 51 根骨**的轨道，于是
	# 「巡航父链姿态 = `cruise_idle` 末帧」成立。**但引擎里 `cruise_idle` 只剩
	# 19 条旋转轨**（Godot 的 glTF 导入按「Remove Immutable Tracks」删掉常量轨）
	# ⇒ `Chest` / `Spine` / `Hips` / `Shoulder.R` 在那里**根本没有轨道**
	# ⇒ 它们的值 = **上一段动作留下的残留**（§0c 实测：紧跟 `fly` / `dash_f`
	# 之后读到的是**常态**值 `6.07 / 5.73 / 18.09 / −77.81`）。
	# 后果极隐蔽：那 16 段方向动作的父链**恰好**和这份被污染的基准一样
	# ⇒ 差值**互相抵消** ⇒ 症状从判据里消失（只剩 `Shoulder.L` 那 3.73° 的余数）。
	#
	# ## 正解 = 走**引擎里还留着那条轨道的路**
	#
	# `form_on` 在引擎里 36 条旋转轨、5 根祖先**全在**；实测 `form_on` 末帧 ≡
	# `cruise_idle` 末帧 ≡ `form_off` 首帧（两两差 **≤ 0.04°**）= **同一个姿态**，
	# 只是走了一条还在的路。而且这正是**游戏里**建立巡航父链姿态的那条路：
	# 按住 Shift ⇒ `form_on` 播完 ⇒ 父链留在巡航位 ⇒ `cruise_idle` 循环时不再动它。
	# ⇒ 与生产侧 `flight_body._setup_form_weld()` 取祖先基准的时点**逐位一致**。
	var ref_action := fb.model_anim.form_on_action
	if ref_action == "" or not fb.model_anim.has(ref_action):
		ref_action = fb.model_anim.idle_cruise_action
		print("  ⚠️ 没有 `form_on` ⇒ 退回 `%s` 末帧当基准（本机柯西不该走这条）"
			% ref_action)
	fb.cruise_morph = 1.0
	var ref := await _pose_at(fb, ref_action, -1.0)
	print("\n  参考态：%s 末帧 ｜ cruise_morph=%.4f ｜ welds=%d"
		% [ref_action, fb.cruise_morph, w.welds])
	for b: String in FORM_BONES:
		print("      %-14s %s" % [b, _v(ref.get(b, Vector3.ZERO))])

	# ============================================================== §2 主判据
	_line()
	print("§2 ★ 主判据：展开态（cruise_morph=1）下换动作 ⇒ 形态骨**骨架系**漂移")
	print("      基准 = `%s` 末帧 ｜ 参考系 = `Skeleton3D` 节点自身 ｜ 骨架高 %.4f"
		% [ref_action, _height])
	_line()
	var worst_frac := 0.0
	var worst_tag := ""
	var rows := []
	for nm: String in fb.model_anim.action_names():
		if not fb.model_anim.has(nm):
			continue
		var is_main: bool = MAIN_ACTIONS.has(nm)
		# ★ 基准 = `form_on` 末帧 ⇒ 它自己的 Δ 应当 ≈ 0（**旁证**：基准这条路走对了）；
		# `form_off` 首帧与它同一个姿态 ⇒ 也该 ≈ 0（修好前它读 0.2547，是第一版的症状出口）。
		var wm := {"nm": nm, "main": is_main, "max": 0.0, "ph": -1.0, "who": "",
			"anc": 0.0, "ancwho": "", "ancph": -1.0}
		var dur := _dur(fb, nm)
		for ph in PHASES:
			var t: float = float(ph) * dur if dur > 0.0 else -1.0
			var p := await _pose_at(fb, nm, t)
			var d := _maxdev(p, ref)
			if float(d[0]) > float(wm["max"]):
				wm["max"] = d[0]
				wm["who"] = d[1]
				wm["ph"] = ph
			# 单独量「父链动了多少」——把「翼没被焊住」与「父链没被驱动」分开。
			var da := _maxdev_of(p, ref, ANCESTORS)
			if float(da[0]) > float(wm["anc"]):
				wm["anc"] = da[0]
				wm["ancwho"] = da[1]
				wm["ancph"] = ph
		rows.append(wm)
		if is_main:
			var f: float = float(wm["max"]) / maxf(_height, 1e-9)
			if f > worst_frac:
				worst_frac = f
				worst_tag = nm
	print("  %-22s %-6s %11s %9s  %-15s %-5s %11s" % [
		"动作", "主判据", "翼 max|Δ|", "占身高", "最差骨", "相位", "父链 max|Δ|"])
	for r in rows:
		print("  %-22s %-6s %11.4f %8.2f%%  %-15s %-5s %11.4f" % [
			r["nm"], "✓" if r["main"] else "·", r["max"],
			float(r["max"]) / maxf(_height, 1e-9) * 100.0, r["who"], r["ph"], r["anc"]])
	print("\n  ★ 主判据组（%d 段）最差 = **%.4f（%.2f%% 身高）** 于 `%s`"
		% [MAIN_ACTIONS.size(), worst_frac * _height, worst_frac * 100.0, worst_tag])
	print("  ★ 通过线 max|Δ| ≤ %.3f（%.1f%% 身高）｜ 离线 FK 预测：修好前 **0.2547**、修好后 **0.0000**"
		% [PASS_FRAC * _height, PASS_FRAC * 100.0])
	_judge("主判据组全部 ≤ 通过线", worst_frac <= PASS_FRAC)

	# ============================================================== §3 逐骨 Δy
	#
	# ⚠️ `worst_tag` 为空 = 主判据组**零漂移** ⇒ 没有"最差动作"可分解。此时改用 `dash_f`
	# 当展示样本（读数应当同样是全 0），而不是去 `play("")` —— 后者是个 no-op，
	# 会让后面 §4 指纹读到「上一段动作的残留」（本探针第三版修掉的那个假不一致）。
	var show_tag := worst_tag if worst_tag != "" else "dash_f"
	var wp: float = _worst_phase(rows, worst_tag)
	_line()
	print("§3 逐骨 Δ 分解（%s 的相位 %.2f）—— 「上抬」的直接读数" % [show_tag, wp])
	_line()
	var p_worst := await _pose_at(fb, show_tag, wp * _dur(fb, show_tag))
	print("  %-14s %12s %12s %12s" % ["骨", "Δx", "Δy", "Δz"])
	for b: String in FORM_BONES:
		var dv: Vector3 = (p_worst.get(b, Vector3.ZERO) as Vector3) - (ref.get(b, Vector3.ZERO) as Vector3)
		print("  %-14s %12.4f %12.4f %12.4f" % [b, dv.x, dv.y, dv.z])

	# ============================================================== §4 指纹
	if dump_path != "" or cmp_path != "":
		_line()
		print("§4 非巡航（cruise_morph=0）全骨指纹 —— 门控①的证伪条")
		_line()
		var fp := await _fingerprint(fb)
		if dump_path != "":
			var f := FileAccess.open(dump_path, FileAccess.WRITE)
			if f == null:
				_judge("指纹写盘 %s" % dump_path, false)
			else:
				f.store_string(JSON.stringify(fp, "  "))
				f.close()
				print("  指纹已写：%s（%d 段动作 × %d 骨）"
					% [dump_path, fp.size(), _bone_count(skel)])
		if cmp_path != "":
			_compare_fingerprint(fp, cmp_path)

	# ============================================================== §5 证伪条
	_line()
	print("§5 证伪条")
	_line()
	if weld_off:
		if fb.model_anim.player.mixer_applied.is_connected(fb._weld_form_bones):
			fb.model_anim.player.mixer_applied.disconnect(fb._weld_form_bones)
			print("  已断开焊缝（`mixer_applied` → `_weld_form_bones`）")
		else:
			print("  ⚠️ 焊缝本来就没连在 `mixer_applied` 上")
		var d2 := await _probe_dash_f(fb, ref)
		print("  焊缝**整体关掉** ⇒ `dash_f` 最差 = **%.4f（%.2f%% 身高）**（离线 FK 预测 **1.0949**）"
			% [d2[0], d2[0] / maxf(_height, 1e-9) * 100.0])
		print("  ⚠️ 注意 §2 仍是 0.0000：断开点在这里（§5），§2 期间**引擎的 `mixer_applied` 仍在推焊缝**"
			+ " ⇒ §2 不受本开关影响。本开关证的是「焊缝主导了那个读数」—— 同一判据从 0.0000 涨到 1.0949。")
		_judge("证伪条 ①：断焊缝后漂移必须**变大**（≥ 0.5 ≈ 50% 身高）", d2[0] >= 0.5)
		if fb.model_anim.player.mixer_applied.connect(fb._weld_form_bones) == OK:
			print("  焊缝已接回")
	if anc_off:
		if w.get("ancestors_enabled") == null:
			print("  ⚠️ `FormWeld` 还没有 `ancestors_enabled` 字段（S1 未落地）⇒ 本开关无意义")
		else:
			w.set("ancestors_enabled", false)
			var d3 := await _probe_dash_f(fb, ref)
			print("  祖先写入**关掉**（= 改动前的行为）⇒ `dash_f` 最差 = **%.4f（%.2f%% 身高）**"
				% [d3[0], d3[0] / maxf(_height, 1e-9) * 100.0])
			# ⚠️ 门槛取**区间下限**，而不是"等于某个离线小数 ±0.02"：离线 FK 只给
			# `dash_*` 一个数（0.2547 = 29.44% 身高），而探针取的是 **4 个相位的最大值**
			# ⇒ 只保证"同量级复现"。钉死小数位是在制造一条**可能假红**的判据（T35 的反面）。
			var frac3: float = d3[0] / maxf(_height, 1e-9)
			_judge("证伪条 ②：关掉祖先写入后必须**复现 26% 量级**（≥ 20% 身高；离线预测 29.44%）",
				frac3 >= 0.20)
			w.set("ancestors_enabled", true)

	# ============================================================== §6 形态边界
	if form_trace:
		await _form_trace(fb, w)

	# ============================================================== §7 出图
	if shots_out != "":
		await _shots(fb, w, ref)

	_line()
	print("结论 = %s" % ("PASS（全部判据通过）" if _ok_all else "FAIL（有判据没过）"))
	_line()
	get_tree().quit(0 if _ok_all else 1)


# ================================================================ 参数 / 环境

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--dump" and i + 1 < args.size():
			dump_path = args[i + 1]
			i += 2
			continue
		if a == "--cmp" and i + 1 < args.size():
			cmp_path = args[i + 1]
			i += 2
			continue
		if a == "--weld=off":
			weld_off = true
		elif a == "--anc=off":
			anc_off = true
		elif a == "--form-trace":
			form_trace = true
		elif a.begins_with("--shots="):
			shots_out = a.substr("--shots=".length())
		else:
			print("[参数] 未知参数（忽略）：%s" % a)
		i += 1


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


## 摆一台**真的** FlightBody（走 `_build_visual()`，骨架 / 动画 / 焊缝都在链上）。
##
## ⚠️ 三个必踩的坑（抄自 `probe_wing_pos.gd` / `form_weld_shot.gd`）：
##   别摆 `y = 0`（`CRASH_ALTITUDE` 判撞海 ⇒ `destroy()` ⇒ `model_root.visible = false`
##   ⇒ 动作链**永不触发且不报错**）；`set_physics_process(false)` 要在 `add_child`
##   **之后**；`_hover_pose` 要补。
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


# ================================================================ 自检

## 自检 ①：**引擎真的在推焊缝吗** —— 不给探针留"手工调内部函数"的假绿空间。
func _self_check_engine_welds(fb: FlightBody, w: FormWeld) -> void:
	var before := w.welds
	fb.cruise_morph = 1.0
	fb.model_anim.player.play(fb.model_anim.idle_cruise_action)
	for i in 20:
		await get_tree().process_frame
	var d := w.welds - before
	print("  ① 引擎驱动焊缝：20 帧内 `welds` +%d（> 0 才算生产路径活着）" % d)
	if d <= 0:
		print("     ⛔ 焊缝没被引擎推 ⇒ 本探针必须**每帧显式补**，且要重新论证时序")
	_ok_all = _judge("自检 ①：`mixer_applied` 在推焊缝", d > 0) and _ok_all


## 自检 ②：`seek()` 真的驱动骨架吗（`godot-headless-probe-shots` §八的假零陷阱）。
func _self_check_seek(fb: FlightBody) -> void:
	var nm := "dash_f"
	if not fb.model_anim.has(nm):
		print("  ② seek 自检跳过：没有 `%s`" % nm)
		return
	var a := await _pose_at(fb, nm, 0.0)
	var b := await _pose_at(fb, nm, 0.5)
	var mx := 0.0
	for k: String in a.keys():
		mx = maxf(mx, (a[k] as Vector3).distance_to(b[k] as Vector3))
	print("  ② `seek()` 驱动骨架：`%s` t=0 vs t=0.5 的最大骨位移 = %.5f（必须 > 1e-3）" % [nm, mx])
	if mx <= 1.0e-3:
		print("     ⛔ 自检失败：seek 没驱动骨架 ⇒ 后面的姿态对比全部无意义")
	_ok_all = _judge("自检 ②：seek 驱动骨架", mx > 1.0e-3) and _ok_all


# ================================================================ 读数

## 把某段动作的某个时刻摆好，**并按生产时序补一次焊缝**，再读全部骨的骨原点。
##
## ⚠️ 为什么探针要**显式**补一次 `_weld_form_bones()`：`AnimationPlayer.seek()` 不保证
## 发 `mixer_applied`，而焊缝的语义是「**动画刚写完那一刻**写进去」（见 `FormWeld` 文件头）。
## 探针在这里手动走**同一条写入链路**（同一个函数、同一时序），得到的是**与生产逐位相同**
## 的结果 —— 且自检 ① 已证明生产路径本身是活的。
##
## ⚠️ 反过来，`--weld=off`（证伪条 ①）**必须在这里也生效** —— 只断开 `mixer_applied`
## 信号是**不够**的，因为本函数自己会显式补焊一次，那样"断开"等于没断
##（第一版就是这么错的：证伪条 ① 是空的）。
func _pose_at(fb: FlightBody, nm: String, t: float) -> Dictionary:
	var pl := fb.model_anim.player
	# `t < 0` = **取末帧**（巡航基准的取法：`_setup_form_weld()` 用的是
	# `rotations_at(idle_cruise)`，即**最后一个关键帧**，不是首帧 —— 首帧还在从常态过渡）。
	var tt := t
	if tt < 0.0:
		var a := pl.get_animation(nm)
		tt = a.length if a != null else 0.0
	pl.play(nm)
	pl.seek(tt, true)
	await get_tree().process_frame
	pl.seek(tt, true)
	if not weld_off:
		fb._weld_form_bones()
	return _origins_all(fb)


## 全部骨的**骨原点**，表达在 `Skeleton3D` 节点自身的坐标系里（见文件头表格）。
func _origins_all(fb: FlightBody) -> Dictionary:
	var out := {}
	var skel := fb._model_skel
	if skel == null:
		return out
	# T37：关键 API 当轮实测，不假设它存在。
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()
	for i in skel.get_bone_count():
		out[skel.get_bone_name(i)] = skel.get_bone_global_pose(i).origin
	return out


## 两条读数之间，**形态骨里**偏离最大的那根（名字 ＋ 距离）。
func _maxdev(p: Dictionary, ref: Dictionary) -> Array:
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


## 骨架高度（骨架局部系单位）—— 占身高比例的分母，**运行时量**，不写死常数。
func _skel_height(skel: Skeleton3D) -> float:
	if skel == null or skel.get_bone_count() == 0:
		return 1.0
	var lo := INF
	var hi := -INF
	for i in skel.get_bone_count():
		var y := skel.get_bone_global_pose(i).origin.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return maxf(hi - lo, 1e-6)


func _dur(fb: FlightBody, nm: String) -> float:
	if not fb.model_anim.has(nm):
		return -1.0
	var a := fb.model_anim.player.get_animation(nm)
	return a.length if a != null else -1.0


func _worst_phase(rows: Array, nm: String) -> float:
	for r in rows:
		if r["nm"] == nm:
			return float(r["ph"])
	return 0.0


## 某个动作各相位的最大形态骨漂移（证伪条用）。
func _probe_dash_f(fb: FlightBody, ref: Dictionary) -> Array:
	var mx := 0.0
	var best := 0.0
	for ph in PHASES:
		var p := await _pose_at(fb, "dash_f", float(ph) * _dur(fb, "dash_f"))
		var d := _maxdev(p, ref)
		if float(d[0]) > mx:
			mx = d[0]
			best = ph
	return [mx, best]


## 非巡航（`cruise_morph = 0`）下，**全部骨**的骨原点指纹（动作 × 相位）。
##
## 这是门控①的证伪条：改动前后必须**逐位相同** —— 一旦祖先骨在 `morph == 0` 时也被写，
## 所有非巡航动作的躯干会被钉死在常态基准上 ⇒ 指纹立刻变。
##
## ⚠️ ★★ 每次摆位**前先 `reset_bone_poses()`** —— 这一条是本探针第三版才补的，必须留：
## 第一版不加归位，指纹会**依赖走查顺序**（= 依赖上一段动作的残留）：
## 本探针对「A/B 两份运行」走的动作顺序**完全相同**，但 §3 播的动作不同
##（绿组 `worst_tag` 为空 ⇒ 没播；红组播了 `burst_cruise`）⇒ 残留不同
## ⇒ 指纹的**第一段**（`burst`，它没有 `ChestArmor.*` / `SideArmor.R` / `Thruster.*`
## 的轨道）读到两份不同的值 ⇒ **报出 10 项假不一致**（实测 `_relay/n55_s2_green.log`）。
## 归位之后指纹变成**动作的纯函数**：与走查顺序、与跑过哪些动作都无关
##（`burst_cruise` 有 51 条轨 ⇒ 它之后各段本来就确定，所以当时只有第一段被污染 —— 那条线索就是证据）。
func _fingerprint(fb: FlightBody) -> Dictionary:
	fb.cruise_morph = 0.0
	var out := {}
	for nm: String in fb.model_anim.action_names():
		if not fb.model_anim.has(nm):
			continue
		var per := {}
		var dur := _dur(fb, nm)
		for ph in [0.0, 0.5]:
			var t: float = float(ph) * dur if dur > 0.0 else -1.0
			# T37：关键 API 当轮实测。
			if fb._model_skel != null and fb._model_skel.has_method("reset_bone_poses"):
				fb._model_skel.reset_bone_poses()
			var p := await _pose_at(fb, nm, t)
			for k: String in p.keys():
				per["%s@%.2f" % [k, ph]] = _round6(p[k] as Vector3)
		out[nm] = per
	fb.cruise_morph = 1.0
	return out


func _compare_fingerprint(cur: Dictionary, path: String) -> void:
	if not FileAccess.file_exists(path):
		_judge("指纹对照：基准文件存在（%s）" % path, false)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var base: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (base is Dictionary):
		_judge("指纹对照：基准文件可解析", false)
		return
	var b := base as Dictionary
	var bad := 0
	var shown := 0
	var worst := 0.0
	var worst_tag := ""
	for nm: String in cur.keys():
		if not b.has(nm):
			print("      ⚠️ 基准里没有动作 `%s`（新增动作？）" % nm)
			continue
		var ca: Dictionary = cur[nm]
		var ba: Dictionary = b[nm]
		for k: String in ca.keys():
			if not ba.has(k):
				bad += 1
				if shown < 8:
					print("      ✗ 新增键 `%s / %s`" % [nm, k])
					shown += 1
				continue
			var d2 := _dist6(ca[k], ba[k])
			if d2 > 1.0e-6:
				bad += 1
				if d2 > worst:
					worst = d2
					worst_tag = "%s / %s" % [nm, k]
				if shown < 8:
					print("      ✗ `%s / %s` 差 %.8f" % [nm, k, d2])
					shown += 1
	print("  指纹对照：不一致 %d 项（最大 %.8f @ %s）" % [bad, worst, worst_tag])
	_judge("非巡航零回归：全骨指纹**逐位相同**", bad == 0)


# ================================================================ §6 形态边界（S3）

## ★★ 门控② 的**进出边界**逐帧轨迹（方案 §5③ / S3 的出口判据）。
##
## ## 要回答的问题
##
## 门控② 的代价是「`State.FORM` 窗口内焊缝**退位**」。退位 / 复位发生在**两个瞬间**
##（`form_on` 结束、`form_off` 开始）。若某个瞬间 `cruise_morph` 还没到位，祖先骨
##就会从「焊缝写的值」跳到「动画写的值」—— 一跳就是一次可见的抽动。
##
## **这两个时长实测不同** ⇒ 这一跳必须**量**，不能靠推：
##   · `cruise_morph_seconds = 0.45`（`SuitProfile.xi()`）⇒ `morph` 用 0.45 s 走完
##   · `form_on` 长度 ≈ **0.4333 s**（`model_anim.gd` 的资产注释）
##   ⇒ `form_on` 播完那一刻 `morph ≈ 0.4333 / 0.45 = 0.963`，**不是 1**。
##
## ## 判据
##
## | 判据 | 量什么 | 通过线 |
## |---|---|---|
## | A | `State.FORM` 窗口内**每一帧**祖先写入增量 | **= 0**（门控② 真的生效） |
## | B | 全程相邻帧**形态骨**最大位移 | **< 0.05**（无跳变） |
## | C | `State.FORM` 进出那一帧的 `morph` | **只报不判**（把 B 的成因写清楚） |
##
## ⚠️ 驱动走**生产链**（`_physics_process` → `_tick_effects` → `_tick_cruise_morph`
## + `_tick_model_anim`），⛔ 不在探针里另抄一遍插值 —— 抄一遍就是"两处判据"，
## 量出来的就不是生产行为了。`FlightBody._think()` 是空实现 ⇒ 手动写 `fm.boosting`
## 不会被覆盖。
##
## ⚠️ **必须配 `--fixed-fps 60`**：headless 下帧 delta = 墙钟时间、长短不一，
## 不等长的"逐帧"读数之间不可比（T43）。
func _form_trace(fb: FlightBody, w: FormWeld) -> void:
	_line()
	print("§6 ★ 门控② 边界：`State.FORM` 进出逐帧轨迹（须配 `--fixed-fps 60`）")
	print("     驱动 = 生产链 `_physics_process` → `_tick_effects` → `_tick_cruise_morph`"
		+ "（`fm.boosting` 推 `morph`）→ `_tick_model_anim` → `fsm.set_form(morph ≥ 0.5)`")
	_line()
	# 前面为逐相位读数把物理帧关了，这里按生产路径打开。
	fb.set_physics_process(true)
	fb.cruise_morph = 0.0
	fb.fm.boosting = false
	fb.fm.hovering = false
	for i in 20:
		await get_tree().physics_frame
	print("  起始：state=%s morph=%.4f 祖先写入累计=%d"
		% [fb.model_fsm.state_name(), fb.cruise_morph, w.ancestor_writes])
	var rows := []
	var prev := _origins_all(fb)
	var pw := w.ancestor_writes
	var pweld := w.welds
	for ph: Array in [["on", 100, true], ["off", 100, false]]:
		fb.fm.boosting = bool(ph[2])
		fb.fm.hovering = false
		for i in int(ph[1]):
			await get_tree().physics_frame
			var p := _origins_all(fb)
			var df := _maxdev(p, prev)
			var da := _maxdev_of(p, prev, ANCESTORS)
			rows.append({
				"ph": ph[0], "i": i, "st": fb.model_fsm.state_name(),
				"form": fb.model_fsm.state == ModelAnimFSM.State.FORM,
				"morph": fb.cruise_morph,
				"aw": w.ancestor_writes - pw, "w": w.welds - pweld,
				"df": float(df[0]), "da": float(da[0]),
			})
			prev = p
			pw = w.ancestor_writes
			pweld = w.welds
	print("  %-4s %-4s %-9s %-6s %7s %5s %5s %10s %10s" % [
		"阶段", "帧", "state", "FORM?", "morph", "写祖先", "焊缝", "形态Δ", "祖先Δ"])
	for r in rows:
		print("  %-4s %-4d %-9s %-6s %7.4f %5d %6d %10.5f %10.5f" % [
			r["ph"], r["i"], r["st"], "✓" if r["form"] else "·", r["morph"],
			r["aw"], r["w"], r["df"], r["da"]])
	# ---- 判据 A：`State.FORM` 窗口内祖先写入必须为 0 ----
	var bad_form := 0
	var first_bad := ""
	for r in rows:
		if bool(r["form"]) and int(r["aw"]) > 0:
			bad_form += 1
			if first_bad == "":
				first_bad = "%s 第 %d 帧（增量 %d）" % [r["ph"], r["i"], r["aw"]]
	print("")
	if bad_form > 0:
		print("  ⛔ `State.FORM` 窗口内仍有 %d 帧写了祖先：%s" % [bad_form, first_bad])
	_judge("判据 A：`State.FORM` 窗口内祖先写入增量为 0（门控② 生效）", bad_form == 0)
	# ---- 判据 B：交接帧相对**它自己的邻居**不离群 ----
	#
	# ⚠️ 两个被否掉的参考量（都实测过，记下来免得下次再踩）：
	#   ① **绝对门槛**（"≤ 0.05"）—— 依赖 `cruise_morph_seconds`：逐帧位移天然
	#      ≈ 总行程 / 帧数。时长调快一半，正常运动就顶破门槛 ⇒ **假红**；调慢一半，
	#      真跳变也可能读不到 0.05 ⇒ **假绿**。
	#   ② **全程中位数** —— 轨迹里有一大段"巡航稳态"（`morph = 1`，位移 ≈ 0）
	#      ⇒ 中位数被拉到 **0.00000** ⇒ 比率算成 **266×** ⇒ **假红**（实测）。
	# ⇒ 参考量取**离交接帧最近的那几个邻居**（跳过静止平台、也跳过其它交接帧）。
	#   这一条尺度无关（改帧率 / 改时长都不变），而且正是"跳变"的定义：
	#   **一个帧比它前后几帧走动得多得多**。
	var edges := []
	for i in rows.size():
		if i > 0 and bool(rows[i]["form"]) != bool(rows[i - 1]["form"]):
			edges.append(i)
	var mx_df := 0.0
	for r in rows:
		mx_df = maxf(mx_df, float(r["df"]))
	var mx_ratio := 1.0
	var mx_edge := 0.0
	var ratio_at := ""
	for i in edges:
		var nb := []
		for j in range(maxi(0, i - 6), mini(rows.size(), i + 7)):
			if j != i and not edges.has(j):
				nb.append(float(rows[j]["df"]))
		if nb.is_empty():
			continue
		var ref := _median(nb)
		var d := float(rows[i]["df"])
		var rt := d / maxf(ref, 1e-9)
		if rt > mx_ratio:
			mx_ratio = rt
			mx_edge = d
			ratio_at = "%s 第 %d 帧（Δ=%.5f vs 邻居中位数 %.5f，state=%s morph=%.4f）" % [
				rows[i]["ph"], rows[i]["i"], d, ref, rows[i]["st"], rows[i]["morph"]]
	print("  逐帧位移：全程最大 %.5f ｜ 交接帧最大 %.5f（%d 个交接帧）"
		% [mx_df, mx_edge, edges.size()])
	print("  ★ 最差交接帧 / 其邻居中位数 = **%.2f×**（门槛 1.5×）%s｜ 改动前实测 **2.15× / 2.11×**"
		% [mx_ratio, ratio_at + " " if ratio_at != "" else ""])
	_judge("判据 B：交接帧不是离群点（位移 ≤ 1.5× 邻居中位数）", mx_ratio <= 1.5)
	# ---- 判据 C：`State.FORM` 进出那一帧的 morph（**只报不判**）----
	var edge_txt := []
	for i in edges:
		edge_txt.append("%s 第 %d 帧：**%s** FORM，morph=%.4f"
			% [rows[i]["ph"], rows[i]["i"],
				"进入" if bool(rows[i]["form"]) else "退出", rows[i]["morph"]])
	print("  ★ 判据 C（只报不判）`State.FORM` 边界帧：%s"
		% ("；".join(edge_txt) if not edge_txt.is_empty() else "（本段没出现 FORM）"))
	fb.set_physics_process(false)
	fb.fm.boosting = false


# ================================================================ §7 出图（S5）

## ★ 真机出图：侧视 × 2 状态（巡航稳定 / `dash_f`）× 2 门控（闭包开 / 关）。
##
## ## 这张图要回答什么
##
## 一个**肉眼可判**的是/否：**关掉祖先闭包后，巡航态下按方向键，后翼会不会从机体上抬起来**。
## 「闭包开」两格应当**看不出差别**（翼都贴在巡航位）；「闭包关」的 `dash_f` 那格应当能看到
## 后翼 / 挂架**被抬起来**（离线 FK：`RearHang.R` Δy **+0.1969**，总位移 26% 身高）。
##
## ## ⚠️ 三条出图的坑（`godot-headless-probe-shots` ＋ 轮 34 的机位法则）
##
## ① **不能配 `--headless`**：dummy 渲染器下 `get_viewport().get_texture().get_image()`
##    拿回来是空图 / 全黑，而脚本**不报错** ⇒ 一张假图。
## ② **取景全程固定**（`focus` / `cam.size` 一次性算好、传进去不再改）：
##    参数一改，「伸出取景外」就看不出来了。
## ③ **图证必须选「被被判别的自由度支配」的量**（N54·T52：给图加逐像素差读数**是骗人的**，
##    实测「同朝向」0.0307 vs「差 248°」0.0290 **同量级** ⇒ 那个读数根本没有判别力）。
##    这里被判别的自由度是**竖直位移** ⇒ 机位取侧视（见 `VIEWS_SHOT` 的注释）。
##
## ⚠️ 本段在**所有逐帧读数之后**才跑：拍一张图要 `await` 好几个真实帧，而 `AnimationPlayer`
## 按真实时间推进播放头（探针只关了 `FlightBody._process`，管不到它）⇒ 混进逐帧跟踪里
## 会**造出假跳变**（`probe_wing_pos.gd` §4 那个 12.9 单位的教训）。
func _shots(fb: FlightBody, w: FormWeld, ref: Dictionary) -> void:
	_line()
	print("§7 出图：侧视 × {巡航稳定 / dash_f} × {闭包开 / 闭包关}")
	print("     取景固定 ｜ ⚠️ 本段**不可**配 `--headless`（dummy 渲染器拍到空图且不报错）")
	_line()
	if DisplayServer.get_name() == "headless" or DisplayServer.get_name() == "dummy":
		print("  ⛔ 现在跑在 `%s` 显示驱动上 ⇒ 拍出来必是空图，本节跳过（这不是判据失败）"
			% DisplayServer.get_name())
		return
	var bounds: AABB = fb.model_bounds
	var focus: Vector3 = fb.global_position \
		+ Vector3(0.0, bounds.position.y + bounds.size.y * 0.5, 0.0)
	# 取景以**静态包围盒**为基准再放 1.5 倍，**全程固定**（同 `probe_wing_pos.gd`）。
	var cam_size: float = maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z) * 1.5
	print("  包围盒 size=(%.2f, %.2f, %.2f)  cam.size=%.2f  focus=(%.2f, %.2f, %.2f)"
		% [bounds.size.x, bounds.size.y, bounds.size.z, cam_size,
			focus.x, focus.y, focus.z])
	var shots := []
	var table := []
	for gi in SHOT_GATES.size():
		var gate: Array = SHOT_GATES[gi]
		w.set("ancestors_enabled", bool(gate[1]))
		for si in SHOT_STATES.size():
			var st: Array = SHOT_STATES[si]
			var nm: String = st[1]
			if not fb.model_anim.has(nm):
				print("  ⚠️ 没有动作 `%s` ⇒ 跳过这一格" % nm)
				continue
			var t: float = float(st[2]) * _dur(fb, nm) if float(st[2]) >= 0.0 else -1.0
			var p := await _pose_at(fb, nm, t)
			var d := _maxdev(p, ref)
			var who: String = d[1]
			var dy := 0.0
			if p.has(who) and ref.has(who):
				dy = (p[who] as Vector3).y - (ref[who] as Vector3).y
			table.append([gate[0], st[0], nm, float(d[0]),
				float(d[0]) / maxf(_height, 1e-9) * 100.0, who, dy])
			# 门控颜色：**开 = 绿 / 关 = 红**（中文习惯里"红=有问题"）。
			# ⚠️ 颜色只做**索引**，判据仍然只有日志里的数字 —— 图不承担判据（T52）。
			var tag_col := Color(0.45, 1.0, 0.60) if bool(gate[1]) else Color(1.0, 0.52, 0.42)
			var tag := "ANC-%s  %s" % ["ON" if bool(gate[1]) else "OFF",
				"CRZ" if si == 0 else "DASH"]
			for vi in VIEWS_SHOT.size():
				var img := await _shoot(fb, vi, focus, cam_size)
				if img != null:
					_draw_text(img, 10, 10, tag, tag_col)
					# 漂移读数 ×1000 取整（字模里没有小数点 ⇒ 不引新符号）。
					_draw_text(img, 10, SHOT_H - 30,
						"DEV:%d" % int(round(float(d[0]) * 1000.0)))
					_draw_text(img, 10, SHOT_H - 18,
						"MORPH:%d" % int(round(fb.cruise_morph * 100.0)))
					_frame(img, tag_col)
				shots.append({"view": vi, "col": gi, "row": si, "img": img})
	w.set("ancestors_enabled", true)
	print("  %-8s %-14s %-12s %10s %9s %-14s %12s" % [
		"闭包", "状态", "动作", "翼 max|Δ|", "占身高", "最差骨", "该骨 Δy"])
	for r in table:
		print("  %-8s %-14s %-12s %10.4f %8.2f%% %-14s %+12.4f" % [
			r[0], r[1], r[2], r[3], r[4], r[5], r[6]])
	print("  ★ 判读：`闭包开` 两格应当**看不出差别**（翼都贴在巡航位）；"
		+ "`闭包关` 的 `dash_f` 格应当能看到**后翼 / 挂架被抬起**（离线 FK 预测 Δy = +0.1969）。")
	_sheet(shots, SHOT_GATES.size(), SHOT_STATES.size(), "wing1_ancestor_closure.png",
		"列 = 闭包[开/关] ｜ 行 = 状态[巡航稳定/dash_f] ｜ 格内数字 = cruise_morph×100")


## 拍一张。`vi` = `VIEWS_SHOT` 下标。**自由机位**（方位角 + 仰角）。
##
## ⚠️ 相机要 `add_child` **之后**再设 `global_position`；`looking_at()` 的 up 与视线共线时
## 会被拒绝、相机停在原点（`godot-headless-probe-shots` §二）。
func _shoot(fb: FlightBody, vi: int, focus: Vector3, cam_size: float) -> Image:
	var az := deg_to_rad(float(VIEWS_SHOT[vi][0]))
	var el := deg_to_rad(float(VIEWS_SHOT[vi][1]))
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
	img.resize(SHOT_W, SHOT_H, Image.INTERPOLATE_LANCZOS)
	return img


## 把若干张格子拼成一张大图并存盘（`col` / `row` 决定落点）。
func _sheet(shots: Array, cols: int, rows: int, fname: String, hint: String) -> void:
	if shots.is_empty():
		return
	var sheet := Image.create(SHOT_W * cols, SHOT_H * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.10, 0.12))
	var got := 0
	for s in shots:
		var rec: Dictionary = s
		var img: Image = rec["img"]
		if img == null:
			continue
		got += 1
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(SHOT_W, SHOT_H)),
			Vector2i(SHOT_W * int(rec["col"]), SHOT_H * int(rec["row"])))
	for ci in range(1, cols):
		sheet.fill_rect(Rect2i(SHOT_W * ci, 0, 2, SHOT_H * rows), Color(0.42, 0.48, 0.58))
	for ri in range(1, rows):
		sheet.fill_rect(Rect2i(0, SHOT_H * ri, SHOT_W * cols, 2), Color(0.42, 0.48, 0.58))
	var out := shots_out.path_join(fname)
	print("\nSHOT %s err=%d 拍到 %d 格（%s）" % [out, sheet.save_png(out), got, hint])


## 极简 5×7 点阵（数字 / 大写字母 / 少量符号），工具自包含、不引字体资源。
##
## ⚠️ 为什么值得为这张图写一套字模：**判据图必须能独立读**。只有数字的图，
## 看图的人得回去翻日志才知道哪一格是"闭包关"（N47 的教训：改可见姿态必须
## 至少一图 ＋ 一条量化对照 —— 但图自己也要说清它是什么）。
func _draw_text(img: Image, x: int, y: int, text: String,
		col := Color(1.0, 0.85, 0.35)) -> void:
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
		"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
		"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
		"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
		"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
		"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
		"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
		"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
		"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
		"I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
		"J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
		"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
		"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
		"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
		"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
		"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
		"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
		"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
		"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
		"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
		"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
		"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
		"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
		"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
		"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
		"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
		"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
		"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
		":": ["00000", "00100", "00100", "00000", "00100", "00100", "00000"],
		" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	}
	var cx := x
	for ch in text:
		var rows: Array = glyphs.get(ch, glyphs["0"])
		for ry in rows.size():
			var row: String = rows[ry]
			for rx in row.length():
				if row[rx] == "1":
					img.set_pixel(cx + rx, y + ry, col)
		cx += 7


## 给一格画 3 px 边框（颜色 = 门控索引色）。`Image.fill_rect` 只有 RGBA8 支持。
func _frame(img: Image, col: Color) -> void:
	var r := Rect2i(0, 0, SHOT_W, SHOT_H)
	img.fill_rect(Rect2i(r.position, Vector2i(r.size.x, 3)), col)
	img.fill_rect(Rect2i(r.position + Vector2i(0, r.size.y - 3),
		Vector2i(r.size.x, 3)), col)
	img.fill_rect(Rect2i(r.position, Vector2i(3, r.size.y)), col)
	img.fill_rect(Rect2i(r.position + Vector2i(r.size.x - 3, 0),
		Vector2i(3, r.size.y)), col)


# ================================================================ 小工具

## 形态骨的**祖先闭包**（只用来打印；生产侧的闭包由 `FormWeld.setup()` 自己算）。
##
## ★ 判据与方案 §4.1 一致：从每根形态骨沿 `get_bone_parent()` 上溯到根之前，
## 凡**不是形态骨自己**的祖先全部列出。⛔ 不硬编码骨名。
func _closure_of(skel: Skeleton3D, w: FormWeld) -> Array:
	var out := []
	var seen := {}
	var mine := {}
	for b: String in w.form_bones():
		mine[skel.find_bone(b)] = true
	for b: String in FORM_BONES:
		var bi := skel.find_bone(b)
		if bi < 0:
			continue
		var cur := bi
		while true:
			var par := skel.get_bone_parent(cur)
			if par < 0:
				break
			if not seen.has(par):
				seen[par] = true
				var nm := skel.get_bone_name(par)
				out.append("%s%s" % [nm, "（形态骨）" if mine.has(par) else ""])
			cur = par
	return out


func _bone_count(skel: Skeleton3D) -> int:
	return skel.get_bone_count() if skel != null else 0


## 某段动作在引擎里的**旋转轨骨名清单**（排序后）。
##
## ⚠️ 骨名在 `NodePath` 的**子名**里（`Skeleton3D:RearHang.R`）⇒ 必须按 `:` 切、取最后一段。
## 用 `ends_with("/" + 骨名)` 匹配**永远匹配不到**（本探针第一版就这么错的，
## 结果把「祖先骨没有轨道」报成了全部动作都没有 —— 一个会把人带偏的假结论）。
func _rot_bones(fb: FlightBody, nm: String) -> Array:
	var out := []
	if nm == "" or not fb.model_anim.has(nm):
		return out
	var a := fb.model_anim.player.get_animation(nm)
	if a == null:
		return out
	for tr in a.get_track_count():
		if a.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
			continue
		var parts := String(a.track_get_path(tr)).split(":")
		out.append(parts[parts.size() - 1])
	out.sort()
	return out


## ★ 某个动作在**引擎里**到底覆盖了哪些骨 —— 「离线 `.glb` 有什么」≠「引擎里还在」
##（Godot 的 glTF 导入会按「Remove Immutable Tracks」删掉常量轨道；T33 的同族）。
##
## `closure` 是 §0 算出来的祖先链（形如 `["Chest", "Chest（形态骨）", ...]`）——
## 这里只取前半截骨名做匹配。
func _track_report(fb: FlightBody, nm: String, closure: Array) -> void:
	if nm == "" or not fb.model_anim.has(nm):
		print("  %-20s ⚠️ 没有这段动作" % nm)
		return
	var a := fb.model_anim.player.get_animation(nm)
	if a == null:
		print("  %-20s ⚠️ 拿不到 `Animation`" % nm)
		return
	# ⚠️ 骨架的骨轨道把**骨名放在 path 的子名里**（形如 `Skeleton3D:RearHang.R`）,
	# 不是路径段 ⇒ 用 `ends_with("/" + 骨名)` 匹配**永远匹配不到**（第一版就这么错的）。
	var rots := {}
	var poss := {}
	for tr in a.get_track_count():
		var parts := String(a.track_get_path(tr)).split(":")
		var bone := parts[parts.size() - 1]
		if a.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
			rots[bone] = true
		elif a.track_get_type(tr) == Animation.TYPE_POSITION_3D:
			poss[bone] = true
	var have := []
	var miss := []
	for b: String in ANCESTORS:
		if rots.has(b):
			have.append(b)
		else:
			miss.append(b)
	# 形态骨自身有没有轨道（对照：这两组应当**都有**）。
	var fb_rot := 0
	for b: String in FORM_BONES:
		if rots.has(b):
			fb_rot += 1
	print("  %-20s 轨道 %3d（ROT %2d / POS %2d）｜ 形态骨有旋转轨 %d/8 ｜ 祖先骨有旋转轨：%s ｜ **没有**：%s"
		% [nm, a.get_track_count(), rots.size(), poss.size(), fb_rot, str(have), str(miss)])


## 一组骨的骨原点相对参考态的最大位移（用来把「父链动了没有」单独量出来）。
func _maxdev_of(p: Dictionary, ref: Dictionary, names: Array) -> Array:
	var mx := -1.0
	var who := ""
	for b: String in names:
		if not p.has(b) or not ref.has(b):
			continue
		var d: float = (p[b] as Vector3).distance_to(ref[b] as Vector3)
		if d > mx:
			mx = d
			who = b
	return [maxf(mx, 0.0), who]


func _median(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var ys := xs.duplicate()
	ys.sort()
	var n := ys.size()
	if n % 2 == 1:
		return float(ys[n / 2])
	return (float(ys[n / 2 - 1]) + float(ys[n / 2])) * 0.5


func _round6(v: Vector3) -> Array:
	return [snappedf(v.x, 1e-6), snappedf(v.y, 1e-6), snappedf(v.z, 1e-6)]


func _dist6(a: Variant, b: Variant) -> float:
	var va := Vector3(float(a[0]), float(a[1]), float(a[2]))
	var vb := Vector3(float(b[0]), float(b[1]), float(b[2]))
	return va.distance_to(vb)


func _v(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]


func _line() -> void:
	print("=".repeat(96))


## ⚠️ 判定必须**累加进 `_ok_all`**。第一版只 `return cond` 不累加 ⇒ 出现
## 「`FAIL 主判据组全部 ≤ 通过线`」紧接着「`结论 = PASS（全部判据通过）`」这种自相矛盾的输出
##（实测日志 `_relay/n55_d0d.log`）。**一条不会让结论变红的判据 = 一条不存在的判据**（T35）。
func _judge(label: String, cond: bool) -> bool:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_ok_all = false
	return cond


func _fatal(msg: String) -> void:
	print("FATAL: %s" % msg)
	get_tree().quit(1)
