extends Node
## N56 只读诊断探针 —— 「柯西巡航形态下按 WASD」到底发生了什么。
##
## ## 它回答四个问题（对应 `_relay/PLAN-N56-xi-cruise-aim-freeze.md` §2.1–2.4）
##
##   §1 **按 WASD 时状态机真的选了哪一段动作？**（不是读代码猜 —— 走生产 `_tick_model_anim()`）
##   §2 那段动作相对**巡航姿态**把**各部位**（翼 / 臂 / 枪 / 腿 / 躯干）带跑了多远
##   §3 **松开按键之后停在哪？** —— 是回到巡航位，还是停在"举枪"位（决定方案够不够）
##   §4 巡航姿态的臂 / 腿是否 **= rest**（决定"归位"要写在哪一层）
##
## ## 三条口径（都是前几轮实测换来的）
##
##   · **基准取 `form_on` 末帧**，不是 `cruise_idle` 末帧（N55·T54）：引擎里
##     `cruise_idle` 只有 19 条 ROT 轨（不含臂/腿/躯干），拿它当基准会读到**上一段动作的残留**。
##   · **必须扫相位**（N48·T24）：本机每段动作的**末帧都回归同一姿态**，
##     只取末帧会让 27 段动作读数逐位相同（离线脚本第一版就是这么翻车的）。
##   · 每次摆姿态后**显式补一次 `fb._weld_form_bones()`**：与生产时序一致
##     （`seek()` 不保证发 `mixer_applied`）。
##
## ## 跑法
##
##   <godot_console> --path <工程> --headless res://tools/probe_xi_cruise_parts.tscn
##
## ⚠️ 必须走场景（`--script` 不实例化 autoload ⇒ 工程脚本编译不过）。
## ⚠️ 本探针**只读**：不改任何工程文件、不写盘。

const DT := 1.0 / 60.0

## 巡航基准的取法见文件头（N55·T54）。
const REF_ACTION := "form_on"

## 相位：只看首/末帧会漏掉中段最差的时刻（N48·T24）。
const PHASES := [0.0, 0.25, 0.5, 0.75]

## 通过线（与 N55 主判据同口径）：占**骨架运行时高度**的比例。
const PASS_FRAC := 0.005

## 部位分组。骨名取自 `xi_fly.glb` 的 `skin.joints`（51 骨）＋父子表。
## ⚠️ `Weapon.R` 是**枪**本身（`muzzle_L/R` 挂在它下面）—— 「举枪」看这一列。
const WATCH := {
	"翼": ["Wing.L", "Wing.R", "BinderFront.L", "BinderFront.R",
		"BinderBack.L", "BinderBack.R", "RearHang.L", "RearHang.R"],
	"臂": ["Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R",
		"LowerArm.L", "LowerArm.R", "Hand.L", "Hand.R", "hand_L", "hand_R",
		"shield_L", "shield_R"],
	"枪": ["Weapon.R", "muzzle_L", "muzzle_R"],
	"腿": ["Thigh.L", "Thigh.R", "Shin.L", "Shin.R",
		"Foot.L", "Foot.R", "Toe.L", "Toe.R"],
	"躯干": ["Hips", "Spine", "Chest", "chest", "waist", "Neck", "Head", "head"],
}

## 候选动作 = 「巡航形态下按 WASD 可能走到的那几族」＋ 战斗动作对照。
const CAND := [
	"fly_f", "fly_b", "fly_l", "fly_r",
	"fly_fl", "fly_fr", "fly_bl", "fly_br",
	"dash_f", "dash_b", "dash_l", "dash_r",
	"turn_pitch_up", "turn_pitch_down", "turn_yaw_L", "turn_yaw_R",
	"turn_roll_L", "turn_roll_R",
	"shoot", "slash", "shield", "burst_cruise", "cruise_idle",
]

var _ok_all := true
var _height := 1.0


func _ready() -> void:
	_build_env()
	await get_tree().physics_frame
	FlightBody.use_placeholder = false
	var fb := await _mount(SuitProfile.xi())
	# 关掉宿主自己的 `_process`：否则 `_tick_effects()` 每帧也在推形态/模型，
	# 逐相位读数会被"多推一帧"污染。`AnimationPlayer` 的推进不受影响。
	fb.set_process(false)

	var skel := fb._model_skel
	if skel == null or fb.model_anim == null or fb.model_anim.player == null:
		_fatal("骨架 / 播放器没建起来 ⇒ 本探针无意义")
		return
	_height = _skel_height(skel)

	_line()
	print("N56 只读诊断：巡航形态下「按 WASD」")
	_line()
	print("  骨架高（运行时量）= %.4f ｜ 通过线 = %.4f（%.1f%% 身高）"
		% [_height, PASS_FRAC * _height, PASS_FRAC * 100.0])
	print("  动作表：%s" % str(fb.model_anim.action_names()))

	# ---- 自检：`seek()` 真的驱动骨架吗 ----
	var a0 := await _pose_at(fb, "fly_f", 0.0)
	var a1 := await _pose_at(fb, "fly_f", 0.5)
	var mx := 0.0
	for k: String in a0.keys():
		mx = maxf(mx, (a0[k] as Vector3).distance_to(a1[k] as Vector3))
	print("  自检：`fly_f` t=0 vs t=0.5 最大骨位移 = %.5f（必须 > 1e-3）" % mx)
	_judge("自检：seek 驱动骨架", mx > 1.0e-3)
	if not _ok_all:
		print("\n⛔ 自检没过 ⇒ 后面读数一律不采信。")
		get_tree().quit(1)
		return

	# ============================================================ 参考态
	fb.cruise_morph = 1.0
	var ref := await _pose_at(fb, REF_ACTION, -1.0)
	print("\n  参考态 = `%s` 末帧（cruise_morph=%.2f）" % [REF_ACTION, fb.cruise_morph])

	# ============================================================ §0d 归位段自检
	await _sec0d_hold_audit(fb)

	# ============================================================ §1 状态机实测
	await _sec1_fsm(fb, ref)

	# ============================================================ §2 部位位移
	await _sec2_parts(fb, ref)

	# ============================================================ §3 松开按键后停在哪
	await _sec3_release(fb, ref)

	# ============================================================ §4 巡航的臂/腿 vs rest
	await _sec4_rest(fb, ref)

	# ============================================================ §5 候选修法实测
	await _sec5_fix_candidates(fb, ref)

	# ============================================================ §6 倒放收枪
	await _sec6_backwards(fb, ref)

	# ============================================================ §7 收枪（生产路径）
	await _sec7_stow(fb, ref)

	_line()
	print("结论 = %s" % ("PASS（探针本身跑通）" if _ok_all else "FAIL"))
	_line()
	get_tree().quit(0 if _ok_all else 1)


# ================================================================ §0d 归位段自检

## 把「巡航归位段」本身摊开看：它有哪些轨、关键骨的末帧值离 rest 多远。
##
## ## 为什么需要这一节（2026-09-29 落地首跑时加的）
##
## §3 与 §5(b) 对"归位段能不能把臂 / 腿放回巡航位"给出了**互相矛盾**的读数
##（§3 松手后 104.78%、§5(b) 射击后 0.00%）。两者都"看起来对"，但只能有一个是真的 ——
## N56 的 T56 已经写死：判据必须在**被主张的那批骨之外**取，
## 而"段里到底有什么"这件事只有把 `Animation` 对象本身读出来才算数。
##
## 读法：hold 的**臂 / 腿**列必须接近 `rest`（= 巡航位）；
## 若接近 `form_on` 末帧、而后者离 rest 很远 ⇒ 说明 `form_on` 的臂 / 腿本来就在**常态位**，
## 拿它当补缺源就是错的（`rest` 才是巡航位）—— 这正是本节要证伪的那条假设。
func _sec0d_hold_audit(fb: FlightBody) -> void:
	_line()
	print("§0d 巡航归位段 `__cruise_hold__` 自检（段里到底有什么）")
	_line()
	var ma := fb.model_anim
	if ma == null or not ma.ready or ma.player == null:
		print("  ⛔ 没有可读的 ModelAnimator")
		return
	print("  has_cruise_hold() = %s ｜ has_rest_clip() = %s"
		% [str(ma.has_cruise_hold()), str(ma.has_rest_clip())])
	print("  %-20s %-24s %s" % ["段", "长度/轨道", "分类型"])
	for nm: String in ["__rest__", "__cruise_hold__", ma.idle_cruise_action,
			ma.form_on_action, ma.idle_action]:
		if nm == "":
			continue
		var an := ma.player.get_animation(nm)
		if an == null:
			print("  %-20s (无此动画)" % nm)
			continue
		var rc := 0
		var pc := 0
		var sc := 0
		for i in an.get_track_count():
			match an.track_get_type(i):
				Animation.TYPE_ROTATION_3D:
					rc += 1
				Animation.TYPE_POSITION_3D:
					pc += 1
				Animation.TYPE_SCALE_3D:
					sc += 1
		print("  %-20s len=%.4fs 轨=%3d          ROT %d / POS %d / SCL %d"
			% [nm, an.length, an.get_track_count(), rc, pc, sc])
	var skel := fb._model_skel
	if skel == null:
		return
	# 逐骨：三段各自的**末关键帧旋转**离 rest 的夹角。`(无轨)` = 这个骨那段里没轨道
	#（⇒ 播它时该骨**保持当前值**，这正是"放不下来"的机制）。
	var bones := ["Shoulder.L", "Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R",
		"Thigh.L", "Shin.L", "Foot.Toe.L", "Chest", "Spine", "Hips"]
	print("  %-14s %12s %14s %14s %12s   %s"
		% ["骨", "hold末帧", "form_on末帧", "cruise_idle", "__rest__末帧", "离rest(度)"])
	for bn: String in bones:
		var bi := skel.find_bone(bn)
		if bi < 0:
			print("  %-14s (骨架里没这根骨)" % bn)
			continue
		var rest_q: Quaternion = skel.get_bone_rest(bi).basis.get_rotation_quaternion()
		var cells := "  %-14s" % bn
		var degs := "  %-14s" % ""
		for nm: String in [str(ModelAnimator.CRUISE_HOLD_CLIP), ma.form_on_action,
				ma.idle_cruise_action, str(ModelAnimator.REST_CLIP)]:
			var r: Variant = _rot_key_at_end(ma, nm, bn)
			if r == null:
				cells += " %14s" % "(无轨)"
				degs += " %14s" % "-"
			else:
				cells += " %11.4f°   " % rad_to_deg((r as Quaternion).angle_to(rest_q))
				degs += " %14s" % "-"
		print(cells)
	print("  ★ 读法：`hold末帧` 那一列**必须接近 0°**（= 巡航位 = rest）。
	    若它接近 `form_on末帧` 而后者远大于 0 ⇒ 补缺源取错了。")
	print("  `(无轨)` = 该段里这根骨没有轨道 ⇒ 播它时该骨**保持当前值**（放不下来的机制）。")


## 读「某动画里某骨旋转轨的**末关键帧**值」。没有该轨道返回 `null`。
##
## ⚠️ 轨道路径里的骨名在 `NodePath` 的**子名**段（`Xi_Rig/Skeleton3D:UpperArm.R`），
## 所以取 `get_slice(":", 1)` 比、**不能**用 `ends_with("/" + 骨名)`（永远匹配不到）。
func _rot_key_at_end(ma: ModelAnimator, anim_name: String, bone: String) -> Variant:
	if anim_name == "" or ma.player == null:
		return null
	var an := ma.player.get_animation(anim_name)
	if an == null:
		return null
	for i in an.get_track_count():
		if an.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		if str(an.track_get_path(i)).get_slice(":", 1) != bone:
			continue
		var n := an.track_get_key_count(i)
		if n <= 0:
			return null
		return an.track_get_key_value(i, n - 1)
	return null


# ================================================================ §1 状态机实测

## 走**生产** `_tick_model_anim()`（不是手调状态机）→ 看它到底选了哪一段。
##
## ⚠️ 方向用**世界系**给（机体前 = `-basis.z`）：`_dash_dir8()` 自己会投影到机体系。
func _sec1_fsm(fb: FlightBody, ref: Dictionary) -> void:
	_line()
	print("§1 巡航形态下按 WASD ⇒ 状态机实际选了哪一段（走生产 `_tick_model_anim`）")
	_line()
	var b := fb.global_transform.basis
	# ⚠️ 先把形态推到**稳态**再开始用例：`cruise_morph` 一跳到 1，状态机要先播完
	#   `form_on`（0.4333 s）才落回 IDLE；每个用例只推 14 帧的话，**前面几个**会读到
	#   `State.FORM`（= 过渡中），那不是"巡航稳态下按 WASD"的答案（首跑实测踩到）。
	fb.cruise_morph = 1.0
	fb.translate_dir = Vector3.ZERO
	fb.control_input = Vector3.ZERO
	for i in 60:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	var cases := [
		["W 前推", -b.z, Vector3.ZERO],
		["S 后推", b.z, Vector3.ZERO],
		["A 左移", -b.x, Vector3.ZERO],
		["D 右移", b.x, Vector3.ZERO],
		["Q/E 纯升降", Vector3.UP, Vector3.ZERO],
		["俯仰杆 +0.5", Vector3.ZERO, Vector3(0.5, 0.0, 0.0)],
		["偏航杆 -0.5", Vector3.ZERO, Vector3(0.0, -0.5, 0.0)],
		["滚转杆 +0.5", Vector3.ZERO, Vector3(0.0, 0.0, 0.5)],
		["W + 俯仰杆", -b.z, Vector3(0.5, 0.0, 0.0)],
		["全零（松手）", Vector3.ZERO, Vector3.ZERO],
	]
	print("  %-16s %-8s %-22s %s" % ["输入", "状态", "状态机动作", "播放器当前动作"])
	# ★★ 主判据（N56 §4.1）：**按住期间**臂 / 枪 / 腿就不得离开巡航位。
	#
	# ⚠️ 为什么必须按"按住期间"判、而不是"松手之后"：用户的症状是「**按 WASD 就会举枪**」
	#   —— 是**按下那一刻**手就抬起来了。只判"松手后能不能回来"会漏掉它：
	#   实测 A/B（关掉抑制、保留归位段）时"松手后"仍是 0.00%（归位段救了回来），
	#   而"按住期间"是 48.46% / 95.28% / 32.77% —— 那正是用户看到的现象。
	#   ⇒ 判据必须量**持续输入下**的姿态，覆盖平移族（`fly_*`）与姿态族（`turn_*`）两者。
	var worst := 0.0
	var worst_case := "—（所有用例都没动过骨）"
	for c in cases:
		fb.cruise_morph = 1.0
		fb.translate_dir = c[1]
		fb.control_input = c[2]
		for i in 14:
			fb._tick_model_anim(DT)
			await get_tree().process_frame
		print("  %-16s %-8s %-22s %s" % [c[0], fb.model_fsm.state_name(),
			fb.model_fsm.current_action(), fb.model_anim.current])
		var cur := _origins_all(fb)
		for p: String in ["臂", "枪", "腿"]:
			for bn: String in WATCH[p]:
				if not cur.has(bn) or not ref.has(bn):
					continue
				var d: float = (cur[bn] as Vector3).distance_to(ref[bn] as Vector3)
				if d > worst:
					worst = d
					worst_case = "%s / %s" % [c[0], bn]
	fb.translate_dir = Vector3.ZERO
	fb.control_input = Vector3.ZERO
	print("  ★ 主判据：**按住期间**「臂 / 枪 / 腿」离巡航位最远 = %.2f%% 身高（%s）"
		% [worst / maxf(_height, 1e-9) * 100.0, worst_case])
	_judge("§1 主判据：按住任意方向/姿态键期间**都不举枪**（≤ 通过线）",
		worst <= PASS_FRAC * _height)


# ================================================================ §2 部位位移

## 逐动作 × 逐部位：相位扫描取最大位移（骨架局部系，占身高比例）。
func _sec2_parts(fb: FlightBody, ref: Dictionary) -> void:
	_line()
	print("§2 逐动作 × 逐部位：相对**巡航姿态**的最大骨位移（扫 4 相位）")
	_line()
	var parts: Array = WATCH.keys()
	var head := "  %-16s" % "动作"
	for p: String in parts:
		head += " %18s" % p
	print(head)
	for nm: String in CAND:
		if not fb.model_anim.has(nm):
			continue
		var dur := _dur(fb, nm)
		var best := {}
		for p: String in parts:
			best[p] = [0.0, "", 0.0]
		for ph in PHASES:
			# ⚠️ 每相位前归位：读数必须是**动作本身**的纯函数，不是"上一次播放的残留"。
			#   不归位的话，一个**不驱动臂 / 腿**的动作（`cruise_idle`）会读到上一段动作
			#   留下的姿态 ⇒ 看起来像"它把臂也带跑了"（首跑实测：`cruise_idle` 的枪 / 腿
			#   与 `burst_cruise` **逐位相同** ⇒ 一眼是残留，不是它的属性）。
			#   ⛔ 不要靠"上一段刚好是待机"来蒙对 —— 顺序一换读数就变。
			if fb._model_skel != null and fb._model_skel.has_method("reset_bone_poses"):
				fb._model_skel.reset_bone_poses()
			var pose := await _pose_at(fb, nm, float(ph) * dur)
			for p: String in parts:
				for bn: String in WATCH[p]:
					if not pose.has(bn) or not ref.has(bn):
						continue
					var d: float = (pose[bn] as Vector3).distance_to(ref[bn] as Vector3)
					if d > float((best[p] as Array)[0]):
						best[p] = [d, bn, float(ph)]
		var row := "  %-16s" % nm
		for p: String in parts:
			var e: Array = best[p]
			row += " %7.2f%%%s@%.2f" % [float(e[0]) / maxf(_height, 1e-9) * 100.0,
				str(e[1]).substr(0, 9), float(e[2])]
		print(row)


# ================================================================ §3 松开按键后停在哪

## 关键实验：按 W 让它播 `fly_f` → **松手** → 推 60 帧 → 量臂 / 腿停在哪。
##
## 判据读三列：**松手后是否回到巡航位**（= 与 `ref` 的位移）。
## 预期（若 `cruise_idle` 不驱动臂/腿）：臂/腿 **停在 `fly_f` 的姿态**（举枪不放）。
func _sec3_release(fb: FlightBody, ref: Dictionary) -> void:
	_line()
	print("§3 ★ 松开按键之后停在哪（「只抑制动作」这条方案够不够，看这一节）")
	_line()
	fb.cruise_morph = 0.0
	fb.control_input = Vector3.ZERO
	fb.translate_dir = Vector3.ZERO
	# ★★ 复刻**真机路径**：常态 → 变形 → 巡航稳态。
	#
	# ⚠️ 为什么不能"凭空把 `cruise_morph` 设成 1"（首跑实测踩到）：真机上巡航待机是
	#   由 **`form_on` 播完那一刻的 `_enter_idle()`** 建立起来的（`ModelAnimFSM` 的
	#   `FORM` 分支 → `_enter_idle` → 巡航归位段）。而状态机**已经在 IDLE** 时，
	#   把 morph 从 0 改成 1 **不会触发任何状态迁移** ⇒ 归位段永远不被起播 ⇒
	#   量到的是"上一节留下的残留姿态"（首跑读到 104.78%，与"停在射击末帧"一模一样）
	#   —— 那是**探针的假红**，不是产品缺陷。
	#   ⇒ 任何"测巡航待机"的探针都必须**先离开巡航再进入**，不能直接跳值。
	for i in 30:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	fb.cruise_morph = 1.0
	for i in 90:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	print("  （已按真机路径进入巡航稳态：形态=%s 状态=%s 播放器=%s）"
		% [fb.model_fsm.form_name(), fb.model_fsm.state_name(), fb.model_anim.current])
	fb.translate_dir = -fb.global_transform.basis.z
	for i in 20:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	var during := _origins_all(fb)
	var st_during := fb.model_fsm.state_name()
	var ac_during := fb.model_fsm.current_action()

	fb.translate_dir = Vector3.ZERO
	for i in 90:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	var after := _origins_all(fb)

	print("  按下期间：状态=%s 动作=%s" % [st_during, ac_during])
	print("  松手之后：状态=%s 动作=%s（播放器=%s）"
		% [fb.model_fsm.state_name(), fb.model_fsm.current_action(), fb.model_anim.current])
	print("  %-8s %14s %14s   %s" % ["部位", "按下时%身高", "松手后%身高", "松手后最差骨"])
	for p: String in WATCH.keys():
		var dm := 0.0
		var da := 0.0
		var who := ""
		for bn: String in WATCH[p]:
			if not during.has(bn) or not after.has(bn):
				continue
			dm = maxf(dm, (during[bn] as Vector3).distance_to(ref[bn] as Vector3))
			var dd: float = (after[bn] as Vector3).distance_to(ref[bn] as Vector3)
			if dd > da:
				da = dd
				who = bn
		print("  %-8s %13.2f%% %13.2f%%   %s" % [p, dm / maxf(_height, 1e-9) * 100.0,
			da / maxf(_height, 1e-9) * 100.0, who])
	print("  ★ 判据：松手后**臂 / 枪 / 腿**是否回到 ≤ %.1f%% 身高（回不去 ⇒ 方案必须带「归位」）"
		% (PASS_FRAC * 100.0))
	var worst := 0.0
	for p: String in ["臂", "枪", "腿"]:
		for bn: String in WATCH[p]:
			if after.has(bn) and ref.has(bn):
				worst = maxf(worst, (after[bn] as Vector3).distance_to(ref[bn] as Vector3))
	print("    实测：松手后「臂 / 枪 / 腿」离巡航位最远 = %.2f%% 身高"
		% (worst / maxf(_height, 1e-9) * 100.0))
	_judge("§3 参考条：松手后能回巡航位（≤ 通过线）", worst <= PASS_FRAC * _height)


# ================================================================ §4 巡航 vs rest

## 巡航姿态的臂 / 腿是不是 **= rest**？—— 「归位要写在哪一层」由这一节定。
func _sec4_rest(fb: FlightBody, ref: Dictionary) -> void:
	_line()
	print("§4 巡航姿态 vs **rest**（决定「归位」是写 rest 还是写巡航值）")
	_line()
	var skel := fb._model_skel
	if skel == null or not skel.has_method("reset_bone_poses"):
		print("  ⛔ 没有 `reset_bone_poses()` ⇒ 本节跳过")
		return
	skel.reset_bone_poses()
	await get_tree().process_frame
	var pr := _origins_all(fb)
	print("  %-8s %14s   %s" % ["部位", "rest离巡航%身高", "rest 最差骨"])
	for p: String in WATCH.keys():
		var dm := 0.0
		var who := ""
		for bn: String in WATCH[p]:
			if not pr.has(bn) or not ref.has(bn):
				continue
			var d: float = (pr[bn] as Vector3).distance_to(ref[bn] as Vector3)
			if d > dm:
				dm = d
				who = bn
		print("  %-8s %13.2f%%   %s" % [p, dm / maxf(_height, 1e-9) * 100.0, who])
	print("  ★ 读法：**臂 / 腿 / 躯干**若 ≈ 0 ⇒ 「归位」可以直接用 rest（= `_begin_rest()` 那条现成路）；")
	print("     **翼**必然 ≠ 0（rest 是收起的）⇒ 翼只能继续靠 N55 的焊缝锁在巡航位。")


# ================================================================ §5 候选修法实测

## 三条对照，直接把「推荐方案」钉死（本探针**不改**生产代码，只量）：
##   (a) **焊缝关掉后**的 rest vs 巡航基准 —— §4 里翼那一格被焊缝掩盖了，非要单独看
##   (b) **射击播完回待机之后**臂 / 腿停在哪 —— 「只有射击才举枪」要求它**能放下**
##   (c) 巡航待机改播**静置段**（`__rest__`，N50）后各部位 vs 巡航基准 —— 归位能力实测
func _sec5_fix_candidates(fb: FlightBody, ref: Dictionary) -> void:
	_line()
	print("§5 候选修法实测（三条对照）")
	_line()
	var pl := fb.model_anim.player
	var skel := fb._model_skel

	# ---- (a) 焊缝关掉 + 归位 ----
	if pl.mixer_applied.is_connected(fb._weld_form_bones):
		pl.mixer_applied.disconnect(fb._weld_form_bones)
		print("  (a) 已断开焊缝，再 `reset_bone_poses()` 看 **rest 本身**离巡航位多远：")
	else:
		print("  (a) ⚠️ 焊缝本来就没连上 ⇒ 本节约等效于 §4")
	skel.reset_bone_poses()
	await get_tree().process_frame
	_report_parts("      rest（焊缝关）", _origins_all(fb), ref)
	if not pl.mixer_applied.is_connected(fb._weld_form_bones):
		pl.mixer_applied.connect(fb._weld_form_bones)
		print("      焊缝已接回")
	fb._weld_form_bones()

	# ---- (b) 射击 → 播完 → 回待机 → 臂/腿在哪 ----
	_line()
	fb.cruise_morph = 1.0
	fb.translate_dir = Vector3.ZERO
	fb.control_input = Vector3.ZERO
	print("  (b) 巡航形态下播 `shoot`，等它播完回待机（120 帧）后：")
	var ok := fb.play_model_action("shoot")
	print("      `play_model_action(\"shoot\")` 返回 %s" % str(ok))
	for i in 120:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	print("      结束态：状态=%s 动作=%s（播放器=%s）"
		% [fb.model_fsm.state_name(), fb.model_fsm.current_action(), fb.model_anim.current])
	_report_parts("      射击后待机", _origins_all(fb), ref)
	# (b') 把收尾那一步换成"静置段" —— 这正是新方案里 `_enter_idle()` 要做的事。
	if fb.model_anim.has_rest_clip():
		fb.model_anim.hold_rest(0.0, true)
		for i in 20:
			await get_tree().process_frame
		fb._weld_form_bones()
		print("      (b') 同一时刻改播静置段 ⇒ 举枪的臂 / 腿**能不能放下**：")
		_report_parts("      射击后→静置段", _origins_all(fb), ref)

	# ---- (c) 巡航待机改播静置段（全骨 rest 恒定段）----
	_line()
	print("  (c) 巡航待机改播静置段 `%s`（N50 · 每骨恒定 = 自己的 rest）："
		% str(ModelAnimator.REST_CLIP))
	if not fb.model_anim.has_rest_clip():
		print("      ⛔ 静置段没建出来 ⇒ 本对照跳过（该方案不可用）")
	else:
		fb.model_anim.hold_rest(0.0, true)
		for i in 20:
			await get_tree().process_frame
		fb._weld_form_bones()
		_report_parts("      rest 段", _origins_all(fb), ref)
		print("      ★ 若四列全 ≈ 0 ⇒ 「巡航待机播静置段 ＋ 焊缝锁翼」**视觉等价于巡航姿态**，")
		print("        且它**能归位**（(b) 里放下不来的臂/腿，在这里被拉回）。")


# ================================================================ §6 倒放收枪

## 用户方案：「射击完，短时间内没有下一发射击 ⇒ **倒放** `shoot` 收枪」。
##
## 本节把它在引擎里跑通（**不改生产代码**），回答四个必须先有答案的问题：
##
##   ① 倒放起手**接不接得上**（`AnimationPlayer` 停播不还原姿态 ⇒ 应当**零接缝**）
##   ② 倒放到底**是不是回到巡航位**（看 `shoot` **首帧**离巡航基准多远 —— 倒放两端姿态不变）
##   ③ 倒放完了**怎么判"结束"**（`ModelAnimator.finished()` 是**正放**判据：`position >= length`）
##   ④ 倒放途中玩家又开火会怎样（`request_action()` 的"同段在播不重播"会不会把人**卡住**）
##
## ★ 「短时间」在本工程**已有单一真源**：`FlightBody.rifle_cooldown`
##（`fire_beam()` 里写成 `profile.rifle_interval`、`_process` 里每帧递减）⇒
## 收枪窗 = 「`rifle_cooldown` **归零之后**再等 `STOW_DELAY`」，而**不是**自己拍一个固定秒数。
func _sec6_backwards(fb: FlightBody, ref: Dictionary) -> void:
	_line()
	print("§6 ★ 倒放收枪（用户方案）可行性实测")
	_line()
	var pl := fb.model_anim.player
	if pl == null or not fb.model_anim.has("shoot"):
		print("  ⛔ 没有播放器 / 没有 `shoot` ⇒ 跳过")
		return
	var dur := _dur(fb, "shoot")
	print("  `shoot` 长度 = %.4f s（%.1f 帧 @60）｜ `rifle_interval` = %.3f s ｜ 连射空隙 ≈ %.3f s"
		% [dur, dur * 60.0, fb.profile.rifle_interval,
			maxf(fb.profile.rifle_interval - dur, 0.0)])
	print("  ⇒ 「短时间」下界 = `rifle_interval`（%.3f s，冷却期玩家开不了枪）＋ `STOW_DELAY`"
		% fb.profile.rifle_interval)

	fb.model_fsm.stop()
	fb.cruise_morph = 1.0
	fb.translate_dir = Vector3.ZERO
	fb.control_input = Vector3.ZERO

	# ---- ①' 这段动作在引擎里**到底动没动**（关键是"相位间差"，不是"离基准多远"）----
	#
	# ⚠️ N55·T54 同源：读「离某个基准的距离」会把**残留姿态**当成"这段动作的姿态"。
	#    要判"动作有没有驱动骨架"，必须量**它自己的相位间差**，且每次测前先归位。
	print("  ①' 动作到底动没动（每次测前 `reset_bone_poses()`，排除残留）")
	for nmx: String in ["shoot", "fly_f", "cruise_idle", "form_on", "dash_f"]:
		if not fb.model_anim.has(nmx):
			continue
		var an := pl.get_animation(nmx)
		var poses: Array = []
		var dx := _dur(fb, nmx)
		for ph in PHASES:
			if fb._model_skel.has_method("reset_bone_poses"):
				fb._model_skel.reset_bone_poses()
			poses.append(await _pose_at(fb, nmx, float(ph) * dx))
		var mx := 0.0
		var who := ""
		for i in poses.size():
			for j in range(i + 1, poses.size()):
				var pi: Dictionary = poses[i]
				var pj: Dictionary = poses[j]
				for k: String in pi.keys():
					if not pj.has(k):
						continue
					var dd: float = (pi[k] as Vector3).distance_to(pj[k] as Vector3)
					if dd > mx:
						mx = dd
						who = k
		print("     `%-12s` 轨 %3d 条 长 %.4f ｜ 相位间最大骨位移 %.5f（%.2f%% 身高，%s）"
			% [nmx, an.get_track_count() if an != null else -1, dx,
				mx, mx / maxf(_height, 1e-9) * 100.0, who])
	print("     ★ 相位间 ≈ 0 而「离基准」很大 ⇒ 那是**残留姿态**，不是这段动作的姿态。")

	# ---- ② 两端姿态（先量，后面的读数靠它解释）----
	var p0 := await _pose_at(fb, "shoot", 0.0)
	var p1 := await _pose_at(fb, "shoot", dur)
	_report_parts("      shoot 首帧", p0, ref)
	_report_parts("      shoot 末帧", p1, ref)
	var a := fb.model_anim.player.get_animation("shoot")
	print("  ② `shoot` 首帧 vs 末帧：最大骨位移 = %.6f ｜ loop_mode = %d（NONE=%d / LINEAR=%d）"
		% [_max_diff(p0, p1), a.loop_mode, Animation.LOOP_NONE, Animation.LOOP_LINEAR])
	print("  ② 常态待机 = `%s`（下面用它把「射击特有的抬枪」与「常态 vs 巡航的整体差」分开）"
		% fb.model_anim.idle_action)
	if fb.model_anim.has(fb.model_anim.idle_action):
		var pn := await _pose_at(fb, fb.model_anim.idle_action, 0.0)
		_report_parts("      常态待机首帧", pn, ref)
		print("  ② 对照：`shoot` **首帧** vs 常态待机 = %.6f ｜ `shoot` **末帧** vs 常态待机 = %.6f"
			% [_max_diff(p0, pn), _max_diff(p1, pn)])
		print("     ★ 读法：末帧离常态待机远 ⇒ **末帧停在举枪位**（倒放有内容可收）；")
		print("       末帧 ≈ 常态待机 ⇒ 射击只是循环，倒放收不到枪（= `shoot` 不含收枪轨迹）。")
	print("  ② 两端即使都显示 48.46%，也只说明它们**都不在巡航位** ⇒ 倒放到底 = 回到 `shoot`")
	print("     首帧（**常态基准**），**不是**巡航位 —— 这一条决定收枪后还要不要接归位。")

	# ---- ① 停播不还原姿态 ⇒ 倒放起手应当零接缝 ----
	pl.play("shoot", 0.0, 1.0, false)
	pl.seek(dur, true)
	await get_tree().process_frame
	pl.seek(dur, true)
	fb._weld_form_bones()
	var at_end := _origins_all(fb)
	pl.stop()
	await get_tree().process_frame
	fb._weld_form_bones()
	var at_stop := _origins_all(fb)
	print("  ① 正放到末帧 → `stop()`：最大骨位移 = %.6f（T30 ⇒ 期望 ≈ 0）"
		% _max_diff(at_end, at_stop))

	pl.play("shoot", 0.0, -1.0, true)
	await get_tree().process_frame
	pl.seek(dur, true)
	await get_tree().process_frame
	pl.seek(dur, true)
	fb._weld_form_bones()
	var at_back0 := _origins_all(fb)
	var seam := _max_diff(at_end, at_back0)
	print("  ① 倒放起手（末尾）vs 正放末帧：最大骨位移 = %.6f" % seam)
	_judge("§6-① 倒放起手零接缝（≤ 1e-5）", seam <= 1.0e-5)

	# ---- ③ 倒放推进：播放头真的递减吗 ----
	var pos_a := pl.current_animation_position
	var pos_prev := pos_a
	var mono := true
	var nf := int(ceil(dur * 60.0)) + 2
	for i in nf:
		await get_tree().process_frame
		var p := pl.current_animation_position
		if p > pos_prev + 1.0e-6:
			mono = false
		pos_prev = p
	print("  ③ 倒放推进 %d 帧：position %.4f → %.4f（单调递减=%s）"
		% [nf, pos_a, pos_prev, str(mono)])
	_judge("§6-③ 倒放时播放头单调递减", mono)
	print("  ③（**自然**到 0、未 seek）`is_playing()`=%s ｜ position=%.6f ｜ `finished()`=%s"
		% [str(pl.is_playing()), pl.current_animation_position, str(fb.model_anim.finished())])
	print("     ★ 若 `is_playing()` 还是 true ⇒ 倒放到底**不会自动停** ⇒ 收尾判据必须自己写")

	# ---- ⑦ 同位置：正放 vs 倒放（证明"倒放" = 时间反演）----
	var mid := dur * 0.5
	var fwd := await _pose_at(fb, "shoot", mid)
	pl.play("shoot", 0.0, -1.0, true)
	pl.seek(mid, true)
	await get_tree().process_frame
	pl.seek(mid, true)
	fb._weld_form_bones()
	var bk := _origins_all(fb)
	var rev := _max_diff(fwd, bk)
	print("  ⑦ 同位置 t=%.3f：正放 vs 倒放 最大骨位移 = %.6f（期望 ≈ 0 ⇒ 确为时间反演）"
		% [mid, rev])
	_judge("§6-⑦ 倒放 = 时间反演（≤ 1e-5）", rev <= 1.0e-5)

	# ---- ④ 倒放到底：姿态 + **判据能不能收尾** ----
	pl.seek(0.0, true)
	await get_tree().process_frame
	fb._weld_form_bones()
	print("  ④ 倒放到 0：position=%.6f ｜ `progress()`=%.6f ｜ `ModelAnimator.finished()`=%s"
		% [pl.current_animation_position, fb.model_anim.progress(),
			str(fb.model_anim.finished())])
	_report_parts("      倒放到底", _origins_all(fb), ref)
	_judge("§6-④ 倒放到 0 时正放判据 `finished()` 也能判结束", fb.model_anim.finished())

	# ---- ⑤ 倒放途中玩家再开火 ----
	fb.model_anim.stop()
	fb.model_fsm.stop()
	fb.cruise_morph = 1.0
	var r1 := fb.play_model_action("shoot")
	for i in 20:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	pl.play("shoot", 0.0, -1.0, true)
	pl.seek(dur * 0.5, true)
	await get_tree().process_frame
	var b4 := pl.current_animation_position
	var sp_b4 := _playing_speed(pl)
	var r2 := fb.play_model_action("shoot")
	await get_tree().process_frame
	print("  ⑤ 倒放途中再开火：`play_model_action` 前后 = %s / %s ｜ position %.4f → %.4f ｜ speed %.2f → %.2f"
		% [str(r1), str(r2), b4, pl.current_animation_position, sp_b4, _playing_speed(pl)])
	print("     ★ 若 speed 仍为负、position 仍倒退 ⇒ **玩家按了没反应**（现有 `request_action()`")
	print("       的「同段在播不重播」把倒放也认成了「正在播」）⇒ 必须新增「倒放可被正放打断」。")

	# ---- ⑧ 收枪的最终读数：**只倒放** vs **倒放 ＋ 归位** ----
	pl.play("shoot", 0.0, -1.0, true)
	pl.seek(dur, true)
	for i in int(ceil(dur * 60.0)) + 2:
		await get_tree().process_frame
	fb._weld_form_bones()
	_report_parts("      只倒放(0.40s)", _origins_all(fb), ref)
	print("     ★ 若这几列**仍非 0** ⇒ 倒放**收不到枪**（`shoot` 首帧本来就在常态位）")
	if fb.model_anim.has_rest_clip():
		fb.model_anim.hold_rest(0.18, true)
		for i in 12:
			await get_tree().process_frame
		fb._weld_form_bones()
		_report_parts("      +归位(0.18s)", _origins_all(fb), ref)

	# ---- ⑥ 「短时间」的现成判据 ----
	print("  ⑥ 「短时间内没有下一发射击」的现成判据：`FlightBody.rifle_cooldown`（此刻 = %.3f s）"
		% fb.rifle_cooldown)
	print("     · 冷却中（> 0）⇒ 玩家**开不了枪**，此刻收枪必被下一发打断 ⇒ 等待")
	print("     · 归零之后再等 `STOW_DELAY` 仍无射击 ⇒ 倒放")
	print("     ⇒ 窗口总长 ≈ `rifle_interval`(%.3f) + `STOW_DELAY`"
		% fb.profile.rifle_interval)


## 打印一个姿态相对巡航基准的部位分解。
func _report_parts(tag: String, cur: Dictionary, ref: Dictionary) -> void:
	print("      %-8s %12s   %s" % ["部位", "%身高", "最差骨"])
	for p: String in WATCH.keys():
		var dm := 0.0
		var who := ""
		for bn: String in WATCH[p]:
			if not cur.has(bn) or not ref.has(bn):
				continue
			var d: float = (cur[bn] as Vector3).distance_to(ref[bn] as Vector3)
			if d > dm:
				dm = d
				who = bn
		print("      %-8s %11.2f%%   %s" % [p, dm / maxf(_height, 1e-9) * 100.0, who])


# ================================================================ §7 收枪（生产路径）

## 走**生产路径**测「射击 → 等窗口 → 倒放 → 归位」（N56 §3.5）。
##
## 与 §6 的分工：§6 用**手动**调播放器证明"倒放机制本身可行"；
## §7 调的是 `FlightBody.play_model_action("shoot", true)` ＋ 每帧 `_tick_model_anim()`，
## 证明**落地的状态机分支**（`UNACTION` 滞留 → 倒放 → 归位）真的串起来了 ——
## 这正是"机制可行"与"接上线了"的分界（同 N49·T27：数据可播 ≠ 运行时会播）。
func _sec7_stow(fb: FlightBody, ref: Dictionary) -> void:
	_line()
	print("§7 收枪（生产路径）：射击 → 等窗口 → 倒放 → 归位")
	_line()
	# ---- 0) 进巡航稳态（必须走真机路径，理由见 §3）----
	fb.cruise_morph = 0.0
	fb.translate_dir = Vector3.ZERO
	fb.control_input = Vector3.ZERO
	for i in 30:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	fb.cruise_morph = 1.0
	for i in 90:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	print("  巡航稳态：状态=%s 播放器=%s" % [fb.model_fsm.state_name(), fb.model_anim.current])

	# ---- 1) 射击（声明 can_stow）----
	fb.rifle_cooldown = 0.0
	fb.stow_idle = 0.0
	var ok := fb.play_model_action("shoot", true)
	print("  `play_model_action(\"shoot\", true)` = %s ｜ 状态=%s 动作=%s"
		% [str(ok), fb.model_fsm.state_name(), fb.model_fsm.current_action()])
	var shoot_len := _dur(fb, "shoot")
	var guard := 0
	while fb.model_fsm.state_name() == "action" and guard < 120:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
		guard += 1
	print("  `shoot`（%.4f s）播完 ⇒ 状态=%s 阶段=%d ｜ 播放器=%s 位置=%.4f"
		% [shoot_len, fb.model_fsm.state_name(), fb.model_fsm.stow_stage(),
			fb.model_anim.current, fb.model_anim.player.current_animation_position])
	_judge("§7-① 射击播完**进 UNACTION 滞留**（阶段 0）",
		fb.model_fsm.state_name() == "unaction" and fb.model_fsm.stow_stage() == 0)
	_report_parts("      滞留期（应仍举枪 —— 用户要的\"打完先举着\"）", _origins_all(fb), ref)

	# ---- 2) 等窗口：真的让 `stow_idle` 逐帧累计（不直接改状态）----
	#   ⚠️ 判据必须走"宿主报事实"这条路 —— 直接改状态就测不到窗口算法本身。
	fb.rifle_cooldown = 0.0
	var wait := 0
	while fb.model_fsm.stow_stage() == 0 and wait < 240:
		fb._tick_weapons(DT)
		fb._tick_model_anim(DT)
		await get_tree().process_frame
		wait += 1
	var expect := int(ceil(FlightBody.STOW_DELAY / DT))
	print("  等窗口：%d 帧（≈%.3f s）后 阶段=%d ｜ 播放器=%s 速度=%.2f"
		% [wait, wait * DT, fb.model_fsm.stow_stage(), fb.model_anim.current,
			_playing_speed(fb.model_anim.player)])
	_judge("§7-② 窗口到点后进入倒放（阶段 1）", fb.model_fsm.stow_stage() == 1)
	_judge("§7-③ 倒放时播放速度为负", _playing_speed(fb.model_anim.player) < 0.0)
	_judge("§7-④ 窗口时长 ≈ `STOW_DELAY`（±6 帧）", absi(wait - expect) <= 6)

	# ---- 3) 倒放正判：枪口**真的回摆**（不是"直接归位"）----
	var p_before := _origins_all(fb)
	var moved := 0.0
	var who := ""
	for i in 24:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
		var cur := _origins_all(fb)
		for bn: String in WATCH["枪"]:
			if cur.has(bn) and p_before.has(bn):
				var d: float = (cur[bn] as Vector3).distance_to(p_before[bn] as Vector3)
				if d > moved:
					moved = d
					who = bn
	print("  倒放 24 帧：枪口最大位移 = %.2f%% 身高（%s）"
		% [moved / maxf(_height, 1e-9) * 100.0, who])
	_judge("§7-⑤ 倒放期间枪口真的回摆（> 1% 身高）", moved > 0.01 * _height)

	# ---- 4) 倒放播完 ⇒ 归位 ----
	var g2 := 0
	while fb.model_fsm.state_name() == "unaction" and g2 < 180:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
		g2 += 1
	# ⚠️ 再推 30 帧再看：`_enter_idle()` 回归位段时的混合是 `BLEND_BURST_OUT`（0.18 s），
	#   而退出上面那个 `while` 的**那一帧**才刚起播 —— 当帧量到的是"混合刚开始"的姿态
	#  （首跑实测读到 95.28%，看着像"归位没生效"，其实是**量早了**）。
	#   ⇒ "某段播完后姿态如何"这类判据，一律要留够混合时间再量（同 N45·T45）。
	for i in 30:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	print("  倒放播完 ⇒ 状态=%s ｜ 播放器=%s"
		% [fb.model_fsm.state_name(), fb.model_anim.current])
	var p_after := _origins_all(fb)
	_report_parts("      收枪完成", p_after, ref)
	var worst := 0.0
	for p: String in ["臂", "枪", "腿"]:
		for bn: String in WATCH[p]:
			if p_after.has(bn) and ref.has(bn):
				worst = maxf(worst, (p_after[bn] as Vector3).distance_to(ref[bn] as Vector3))
	print("    收枪后「臂 / 枪 / 腿」离巡航位最远 = %.2f%% 身高"
		% (worst / maxf(_height, 1e-9) * 100.0))
	_judge("§7-⑥ 收枪后回到巡航位（≤ 通过线）", worst <= PASS_FRAC * _height)

	# ---- 5) 打断语义：倒放途中再开火 ⇒ 速度翻正（改之前实测恒 −1.00）----
	fb.rifle_cooldown = 0.0
	fb.stow_idle = 0.0
	fb.play_model_action("shoot", true)
	var g3 := 0
	while fb.model_fsm.state_name() == "action" and g3 < 120:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
		g3 += 1
	fb.rifle_cooldown = 0.0
	var g4 := 0
	while fb.model_fsm.stow_stage() == 0 and g4 < 240:
		fb._tick_weapons(DT)
		fb._tick_model_anim(DT)
		await get_tree().process_frame
		g4 += 1
	var sp_before := _playing_speed(fb.model_anim.player)
	for i in 6:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	var pos_before := fb.model_anim.player.current_animation_position
	fb.rifle_cooldown = 0.0
	fb.stow_idle = 0.0
	fb.play_model_action("shoot", true)
	for i in 3:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
	var sp_after := _playing_speed(fb.model_anim.player)
	print("  倒放途中开火：速度 %.2f → %.2f（位置 %.4f → %.4f）"
		% [sp_before, sp_after, pos_before, fb.model_anim.player.current_animation_position])
	_judge("§7-⑦ 倒放途中开火**能被抢断**（速度翻正）", sp_after > 0.0)
	_judge("§7-⑧ 抢断后回到 ACTION 态", fb.model_fsm.state_name() == "action")


# ================================================================ 小工具

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


## 摆一台真的 `FlightBody`（抄 `probe_xi_wing_world.gd` 的 `_mount`）。
## ⚠️ 别摆 `y = 0`：`CRASH_ALTITUDE` 判撞海 ⇒ `destroy()` ⇒ 模型隐藏 ⇒ 动作链永不触发且不报错。
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


## 摆好某段动作的某个时刻，**按生产时序补一次焊缝**，再读全部骨的骨原点。
func _pose_at(fb: FlightBody, nm: String, t: float) -> Dictionary:
	var pl := fb.model_anim.player
	var tt := t
	if tt < 0.0:
		var a := pl.get_animation(nm)
		tt = a.length if a != null else 0.0
	pl.play(nm)
	pl.seek(tt, true)
	await get_tree().process_frame
	pl.seek(tt, true)
	fb._weld_form_bones()
	return _origins_all(fb)


func _origins_all(fb: FlightBody) -> Dictionary:
	var out := {}
	var skel := fb._model_skel
	if skel == null:
		return out
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()
	for i in skel.get_bone_count():
		out[skel.get_bone_name(i)] = skel.get_bone_global_pose(i).origin
	return out


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


## 两组「骨名 → 骨原点」的最大差（骨架局部系）。
func _max_diff(a: Dictionary, b: Dictionary) -> float:
	var m := 0.0
	for k: String in a.keys():
		if not b.has(k):
			continue
		m = maxf(m, (a[k] as Vector3).distance_to(b[k] as Vector3))
	return m


## 播放器**当前带符号**的播放速度（`AnimationPlayer.get_playing_speed()`）：
## 正放 = `+1`、倒放 = `-1`。这是"倒放真的在倒放"的直接读数。
func _playing_speed(pl: AnimationPlayer) -> float:
	if pl.has_method("get_playing_speed"):
		return pl.get_playing_speed()
	return pl.speed_scale


func _line() -> void:
	print("=".repeat(88))


func _judge(label: String, cond: bool) -> bool:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_ok_all = false
	return cond


func _fatal(msg: String) -> void:
	_ok_all = false
	print("⛔ %s" % msg)
	get_tree().quit(1)
